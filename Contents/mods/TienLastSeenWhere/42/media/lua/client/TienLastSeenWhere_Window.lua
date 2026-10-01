require "ISUI/ISCollapsableWindow"
require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Options"
require "TienLastSeenWhere_Client"
require "TienLastSeenWhere_Actions"
require "TienLastSeenWhere_Jobs"

local LSW = TienLastSeenWhere
local Jobs = LSW.Jobs

local Window = ISCollapsableWindow:derive("TienLastSeenWhereWindow")
LSW.Window = Window

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local PAD = 8
local WIDTH = 420
local HEIGHT = 420
local ROW = math.max(22, FONT_HGT_SMALL + 8)
local ICON = ROW - 4
local PLACE_ROW = ROW + 8
local ARROW_COLUMN = math.floor(PLACE_ROW * 1.7)
local ARROW_X = 10
local FIND_DELAY_MS = 300
local SUMMARY_REFRESH_MS = 15000
local NEARBY = 30
local BUTTONS_REFRESH_MS = 500
local PUBLISH_MS = 150
local SPINNER_DOTS = 8
local SPINNER_RADIUS = 6
local SPINNER_DOT = 4

Window.SCOPE_ALL = 1
Window.SCOPE_BUILDING = 2
Window.SCOPE_NEARBY = 3
Window.SCOPE_ON_ME = 4

Window.instances = {}

local nameCache = {}

local function scriptInfo(fullType)
    local info = nameCache[fullType]
    if info then
        return info
    end
    local script = getScriptManager():getItem(fullType)
    if not script then
        info = { name = fullType, lower = string.lower(fullType), tags = "" }
    else
        local tags = {}
        local set = script:getTags()
        if set then
            local iterator = set:iterator()
            while iterator:hasNext() do
                local tag = tostring(iterator:next())
                tags[#tags + 1] = string.lower(string.match(tag, ":(.+)$") or tag)
            end
        end
        local name = script:getDisplayName()
        info = { name = name, lower = string.lower(name), tags = table.concat(tags, " "), script = script }
    end
    nameCache[fullType] = info
    return info
end

local function plain(text)
    return (string.gsub(text, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function score(info, query)
    local pattern = plain(query)
    local at = string.find(info.lower, pattern)
    if at == 1 then
        return 0
    end
    if at then
        return 1
    end
    if info.tags ~= "" and string.find(info.tags, pattern) then
        return 2
    end
    return nil
end

local function placeLabel(place)
    local label
    if place.kind == LSW.KIND_FLOOR then
        label = getText("IGUI_TienLastSeenWhere_Floor")
    elseif place.kind == LSW.KIND_BODY then
        label = getText("IGUI_TienLastSeenWhere_Corpse")
    elseif place.kind == LSW.KIND_BAG then
        label = scriptInfo(place.type or "").name
    elseif place.kind == LSW.KIND_VEHICLE then
        local partId, scriptName = string.match(place.type or "", "^(.-)@(.+)$")
        local partName = partId and (getTextOrNull("IGUI_VehiclePart" .. partId) or partId) or getText("IGUI_TienLastSeenWhere_Vehicle")
        local vehicleScript = scriptName and getScriptManager():getVehicle(scriptName)
        local vehicleName = vehicleScript and getTextOrNull("IGUI_VehicleName" .. vehicleScript:getName())
        label = vehicleName and getText("IGUI_TienLastSeenWhere_InVehicle", partName, vehicleName) or partName
    else
        label = getTextOrNull("IGUI_ContainerTitle_" .. tostring(place.type)) or tostring(place.type)
    end
    if place.room then
        label = getText("IGUI_TienLastSeenWhere_InRoom", label, place.room)
    end
    return label
end

local function ageText(t)
    local hours = math.max(0, LSW.Now() - (t or 0))
    if hours < 1 / 60 then
        return getText("IGUI_TienLastSeenWhere_JustNow")
    end
    if hours < 1 then
        return getText("IGUI_TienLastSeenWhere_MinutesAgo", string.format("%d", math.floor(hours * 60)))
    end
    if hours < 48 then
        return getText("IGUI_TienLastSeenWhere_HoursAgo", string.format("%d", math.floor(hours)))
    end
    return getText("IGUI_TienLastSeenWhere_DaysAgo", string.format("%d", math.floor(hours / 24)))
end

local function floorText(player, place)
    local diff = place.z - math.floor(player:getZ())
    if diff == 0 then
        return nil
    end
    local count = string.format("%d", math.abs(diff))
    if diff > 0 then
        return getText(diff == 1 and "IGUI_TienLastSeenWhere_FloorUp" or "IGUI_TienLastSeenWhere_FloorsUp", count)
    end
    return getText(diff == -1 and "IGUI_TienLastSeenWhere_FloorDown" or "IGUI_TienLastSeenWhere_FloorsDown", count)
end

local function ruleText(rule)
    local keys = {
        [LSW.RULE_MINE] = "UI_TienLastSeenWhere_SearchRule_Mine",
        [LSW.RULE_SHARED] = "UI_TienLastSeenWhere_SearchRule_Shared",
        [LSW.RULE_EXPLORED] = "UI_TienLastSeenWhere_SearchRule_Explored",
        [LSW.RULE_EVERYTHING] = "UI_TienLastSeenWhere_SearchRule_Everything",
    }
    return getText(keys[rule] or keys[LSW.RULE_MINE])
end

function Window:new(x, y, width, height, playerNum)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.playerNum = playerNum
    o.title = getText("IGUI_TienLastSeenWhere_Title")
    o.minimumWidth = 340
    o.minimumHeight = 260
    o.scope = Window.SCOPE_ALL
    o.matches = {}
    o.findDueMs = nil
    o.summaryMs = 0
    o.arrowTexture = getTexture(LSW.Arrow.TEXTURE)
    o.dotTexture = getTexture("media/ui/circle.png")
    return o
end

function Window:player()
    return getSpecificPlayer(self.playerNum)
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)

    local top = self:titleBarHeight() + PAD
    local entryHeight = FONT_HGT_SMALL + 6

    self.entry = ISTextEntryBox:new("", PAD, top, self.width - PAD * 2, entryHeight)
    self.entry.anchorRight = true
    self.entry:initialise()
    self.entry:instantiate()
    self.entry:setPlaceholderText(getText("IGUI_TienLastSeenWhere_Placeholder"))
    self.entry:setClearButton(true)
    self.entry.target = self
    self.entry.onTextChangeFunction = Window.onTextChange
    self:addChild(self.entry)

    local comboTop = self.entry:getBottom() + PAD
    self.scopeCombo = ISComboBox:new(PAD, comboTop, 170, entryHeight, self, Window.onScopeChange)
    self.scopeCombo:initialise()
    self:addChild(self.scopeCombo)
    self.scopeCombo:addOptionWithData(getText("IGUI_TienLastSeenWhere_ScopeAll"), Window.SCOPE_ALL)
    self.scopeCombo:addOptionWithData(getText("IGUI_TienLastSeenWhere_ScopeBuilding"), Window.SCOPE_BUILDING)
    self.scopeCombo:addOptionWithData(getText("IGUI_TienLastSeenWhere_ScopeNearby"), Window.SCOPE_NEARBY)
    self.scopeCombo:addOptionWithData(getText("IGUI_TienLastSeenWhere_ScopeOnMe"), Window.SCOPE_ON_ME)
    self.scopeCombo.selected = 1
    self.ruleY = comboTop

    local buttonHeight = FONT_HGT_SMALL + 8
    local bottom = self.height - self:resizeWidgetHeight() - PAD
    local buttonTop = bottom - buttonHeight
    local listTop = self.scopeCombo:getBottom() + PAD
    self.list = ISScrollingListBox:new(PAD, listTop, self.width - PAD * 2, buttonTop - PAD - listTop)
    self.list.anchorRight = true
    self.list.anchorBottom = true
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = ROW
    self.list.font = UIFont.Small
    self.list.drawBorder = true
    self.list.window = self
    self.list.doDrawItem = Window.drawRow
    self.list:setOnMouseDoubleClick(self, Window.onRowDoubleClick)
    self:addChild(self.list)

    self.buttons = {}
    local labels = {
        { "show", "IGUI_TienLastSeenWhere_Show", Window.onShow },
        { "go", "IGUI_TienLastSeenWhere_GoThere", Window.onGoThere },
        { "take", "IGUI_TienLastSeenWhere_Take", Window.onTake },
        { "stop", "IGUI_TienLastSeenWhere_StopArrow", Window.onStopArrow },
    }
    local x = PAD
    for _, spec in ipairs(labels) do
        local text = getText(spec[2])
        local width = getTextManager():MeasureStringX(UIFont.Small, text) + 16
        local button = ISButton:new(x, buttonTop, width, buttonHeight, text, self, spec[3])
        button.anchorTop = false
        button.anchorBottom = true
        button:initialise()
        button:instantiate()
        self:addChild(button)
        self.buttons[spec[1]] = button
        x = x + width + PAD / 2
    end
end

function Window:onTextChange()
    self:refreshResults()
end

function Window:onScopeChange()
    local wasOnMe = self.scope == Window.SCOPE_ON_ME
    self.scope = self.scopeCombo:getOptionData(self.scopeCombo.selected) or Window.SCOPE_ALL
    if wasOnMe or self.scope == Window.SCOPE_ON_ME then
        self:refreshResults()
    else
        self:rebuildRows()
    end
end

function Window:getQuery()
    local text = self.entry and self.entry:getInternalText() or ""
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return string.lower(text)
end

function Window:selectedRow()
    local row = self.list.items[self.list.selected]
    return row and row.item or nil
end

local function itemsOnMe(player, query)
    local found = {}
    local function walk(container, holder)
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            local info = scriptInfo(item:getFullType())
            if score(info, query) then
                local key = item:getFullType()
                found[key] = found[key] or { fullType = key, info = info, total = 0, places = {} }
                found[key].total = found[key].total + 1
                local holderName = holder or getText("IGUI_TienLastSeenWhere_MainInventory")
                found[key].places[holderName] = (found[key].places[holderName] or 0) + 1
            end
            if instanceof(item, "InventoryContainer") then
                walk(item:getInventory(), item:getDisplayName())
            end
        end
    end
    walk(player:getInventory(), nil)
    return found
end

function Window:refreshOnMe(player, query)
    local found = itemsOnMe(player, query)
    local list = {}
    for _, entry in pairs(found) do
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b) return a.info.lower < b.info.lower end)
    for _, entry in ipairs(list) do
        self.list:addItem(entry.info.name, { row = "item", fullType = entry.fullType, info = entry.info, total = entry.total })
        for holder, count in pairs(entry.places) do
            self.list:addItem(holder, { row = "held", fullType = entry.fullType, holder = holder, count = count })
        end
    end
end

local function sortMatches(matches)
    table.sort(matches, function(a, b)
        if a.score ~= b.score then
            return a.score < b.score
        end
        return a.info.lower < b.info.lower
    end)
    local trimmed = {}
    for i = 1, math.min(#matches, LSW.FIND_LIMIT) do
        trimmed[i] = matches[i]
    end
    return trimmed
end

function Window:jobName()
    return "window:match:" .. string.format("%d", self.playerNum)
end

function Window:publishMatches(matches, final)
    self.matches = sortMatches(matches)
    if final then
        local key = {}
        for i, match in ipairs(self.matches) do
            key[i] = match.fullType
        end
        local wantedKey = table.concat(key, "|")
        if wantedKey ~= self.lastFindKey then
            self.lastFindKey = wantedKey
            self.findDueMs = #key > 0 and getTimestampMs() + FIND_DELAY_MS or nil
            self.findTypes = key
        end
    end
    self:rebuildRows()
end

function Window:startMatching(query)
    local window = self
    local summary = LSW.Client.GetSummary(self.playerNum)
    self.matching = true
    Jobs.Start(self:jobName(), function()
        local matches = {}
        local lastPublishMs = getTimestampMs()
        for fullType, total in pairs(summary) do
            local info = scriptInfo(fullType)
            local s = score(info, query)
            if s then
                matches[#matches + 1] = { fullType = fullType, info = info, total = total, score = s }
            end
            Jobs.Step()
            if getTimestampMs() - lastPublishMs >= PUBLISH_MS then
                lastPublishMs = getTimestampMs()
                window:publishMatches(matches, false)
            end
        end
        window.matching = false
        window:publishMatches(matches, true)
    end)
end

function Window:inScope(player, place)
    if self.scope == Window.SCOPE_BUILDING then
        local building = LSW.BuildingKey(player:getCurrentSquare())
        return building ~= nil and place.building == building
    end
    if self.scope == Window.SCOPE_NEARBY then
        return LSW.DistanceTo(player:getX(), player:getY(), place.x + 0.5, place.y + 0.5) <= NEARBY
    end
    return true
end

function Window:refreshResults()
    local player = self:player()
    if not self.list or not player then
        return
    end
    local query = self:getQuery()
    Jobs.Cancel(self:jobName())
    self.matching = false
    if query == "" then
        self.matches = {}
        self.list:clear()
        self:updateButtons()
        return
    end
    if self.scope == Window.SCOPE_ON_ME then
        self.list:clear()
        self:refreshOnMe(player, query)
        self:updateButtons()
        return
    end
    self:startMatching(query)
end

function Window:rebuildRows()
    local player = self:player()
    if not self.list or not player or self.scope == Window.SCOPE_ON_ME then
        return
    end
    local selected = self:selectedRow()
    local selectedKey = selected and ((selected.place and selected.place.key or "") .. ":" .. (selected.fullType or ""))
    self.list:clear()
    local find = LSW.Client.GetFind(self.playerNum)
    for _, match in ipairs(self.matches) do
        local places = {}
        for _, place in ipairs(find[match.fullType] or {}) do
            if self:inScope(player, place) then
                places[#places + 1] = place
            end
        end
        table.sort(places, function(a, b)
            return LSW.DistanceTo(player:getX(), player:getY(), a.x, a.y)
                < LSW.DistanceTo(player:getX(), player:getY(), b.x, b.y)
        end)
        if find[match.fullType] == nil or #places > 0 then
            self.list:addItem(match.info.name, {
                row = "item",
                fullType = match.fullType,
                info = match.info,
                total = match.total,
                waiting = find[match.fullType] == nil,
            })
            for _, place in ipairs(places) do
                local index = #self.list.items + 1
                local row = self.list:addItem(placeLabel(place), { row = "place", fullType = match.fullType, place = place })
                row.height = PLACE_ROW
                if selectedKey == place.key .. ":" .. match.fullType then
                    self.list.selected = index
                end
            end
        end
    end
    self:updateButtons()
end

function Window:updateButtons()
    if not self.buttons then
        return
    end
    local player = self:player()
    local row = self:selectedRow()
    local place = row and row.place
    self.buttons.show:setEnable(place ~= nil)
    self.buttons.go:setEnable(place ~= nil)
    self.buttons.take:setEnable(place ~= nil and player ~= nil and LSW.Actions.Takeable(player, place, row.fullType) ~= nil)
    self.buttons.stop:setEnable(LSW.Arrow.GetTarget(self.playerNum) ~= nil)
end

function Window:onShow()
    local row = self:selectedRow()
    if row and row.place then
        LSW.Actions.Show(self:player(), row.place, row.fullType)
        self:updateButtons()
    end
end

function Window:onGoThere()
    local row = self:selectedRow()
    if row and row.place then
        LSW.Actions.GoThere(self:player(), row.place, row.fullType)
        self:updateButtons()
    end
end

function Window:onTake()
    local row = self:selectedRow()
    if row and row.place then
        LSW.Actions.Take(self:player(), row.place, row.fullType)
    end
end

function Window:onStopArrow()
    LSW.Arrow.Clear(self.playerNum)
    self:updateButtons()
end

function Window:onRowDoubleClick(item)
    if item and item.place then
        LSW.Actions.Show(self:player(), item.place, item.fullType)
        self:updateButtons()
    end
end

function Window:drawArrow(list, y, height, place, player)
    local tex = self.arrowTexture
    if not tex then
        return
    end
    local dx = place.x + 0.5 - player:getX()
    local dy = place.y + 0.5 - player:getY()
    local distance = math.sqrt(dx * dx + dy * dy)
    local c = LSW.Options.GetArrowColour()
    local localX = ARROW_X + ARROW_COLUMN / 2
    local localY = y + height / 2
    if distance < 1.5 then
        list:drawRect(localX - 4, localY - 4, 8, 8, 1, c.r, c.g, c.b)
        return
    end
    local cx = list:getAbsoluteX() + localX
    local cy = list:getAbsoluteY() + list:getYScroll() + localY
    local ux, uy = dx / distance, dy / distance
    local nx, ny = -uy * 0.3, ux * 0.3
    local half = 0.5
    local scale = height * 0.95
    local function project(wx, wy)
        return cx + (wx - wy) * scale, cy + (wx + wy) * scale / 2
    end
    local x1, y1 = project(-ux * half - nx, -uy * half - ny)
    local x2, y2 = project(ux * half - nx, uy * half - ny)
    local x3, y3 = project(ux * half + nx, uy * half + ny)
    local x4, y4 = project(-ux * half + nx, -uy * half + ny)
    list:drawTextureAllPoint(tex, x1, y1, x2, y2, x3, y3, x4, y4, c.r, c.g, c.b, 1)
end

-- Rows are clipped by hand instead of trusting the list's stencil: with PZ_Optimization's retained UI
-- (uiRetained + uiRetainedChildren) the row just above the list was drawn over the scope box. Vanilla's skip test
-- (`y + yScroll + height < 0`) also draws a row whose bottom is exactly on the top edge, which is where every
-- mouse-wheel scroll stops. So: rects are cut to the visible band, and text, icons and arrows are drawn only
-- when they fit in it whole.
function Window.drawRow(list, y, item, alt)
    local window = list.window
    local data = item.item
    local viewTop = 1 - list:getYScroll()
    local viewBottom = list.height - 1 - list:getYScroll()
    local rowTop = math.max(y, viewTop)
    local rowBottom = math.min(y + item.height, viewBottom)
    if rowBottom <= rowTop then
        return y + item.height
    end
    local function fits(top, bottom)
        return top >= viewTop and bottom <= viewBottom
    end
    local fillBottom = math.min(y + item.height - 1, viewBottom)
    if fillBottom > rowTop then
        if list.selected == item.index then
            list:drawSelection(0, rowTop, list:getWidth(), fillBottom - rowTop)
        elseif list.mouseoverselected == item.index and list:isMouseOver() and not list:isMouseOverScrollBar() then
            list:drawMouseOverHighlight(0, rowTop, list:getWidth(), fillBottom - rowTop)
        end
    end
    local textY = y + (item.height - FONT_HGT_SMALL) / 2
    local textFits = fits(textY, textY + FONT_HGT_SMALL)
    local right = list:getWidth() - PAD - (list.vscroll and list.vscroll:getWidth() or 0)
    local player = window:player()
    if data.row == "item" then
        list:drawRect(0, rowTop, list:getWidth(), rowBottom - rowTop, 0.25, 0.2, 0.2, 0.2)
        if data.info.script and fits(y + 2, y + 2 + ICON) then
            list:drawScriptItemIcon(data.info.script, 4, y + 2, 1, ICON, ICON)
        end
        if textFits then
            list:drawText(item.text, ICON + 10, textY, 1, 1, 1, 1, UIFont.Small)
            local count = data.waiting and getText("IGUI_TienLastSeenWhere_Looking") or ("x" .. string.format("%d", data.total or 0))
            list:drawTextRight(count, right, textY, 0.8, 0.8, 0.8, 1, UIFont.Small)
        end
    elseif data.row == "held" then
        if textFits then
            list:drawText(item.text, ICON + 18, textY, 0.85, 0.85, 0.85, 1, UIFont.Small)
            list:drawTextRight("x" .. string.format("%d", data.count), right, textY, 0.7, 0.7, 0.7, 1, UIFont.Small)
        end
    elseif data.row == "place" and player and textFits then
        local place = data.place
        local arrowHalf = item.height * 0.4
        if fits(y + item.height / 2 - arrowHalf, y + item.height / 2 + arrowHalf) then
            window:drawArrow(list, y, item.height, place, player)
        end
        list:drawText(item.text, ARROW_X + ARROW_COLUMN + 6, textY, 0.9, 0.9, 0.9, 1, UIFont.Small)
        local distance = LSW.DistanceTo(player:getX(), player:getY(), place.x + 0.5, place.y + 0.5)
        local parts = {}
        if distance < 1.5 then
            parts[#parts + 1] = getText("IGUI_TienLastSeenWhere_Here")
        else
            parts[#parts + 1] = getText("IGUI_TienLastSeenWhere_Tiles", string.format("%d", math.floor(distance + 0.5)))
        end
        parts[#parts + 1] = floorText(player, place)
        parts[#parts + 1] = ageText(place.t)
        parts[#parts + 1] = "x" .. string.format("%d", place.count or 0)
        list:drawTextRight(table.concat(parts, "  "), right, textY, 0.7, 0.7, 0.7, 1, UIFont.Small)
    end
    return y + item.height
end

function Window:prerender()
    ISCollapsableWindow.prerender(self)
    local now = getTimestampMs()
    local player = self:player()
    if not player then
        return
    end
    if self.findDueMs and now >= self.findDueMs then
        self.findDueMs = nil
        LSW.Client.RequestFind(player, self.findTypes)
    end
    if now - self.summaryMs > SUMMARY_REFRESH_MS then
        self.summaryMs = now
        LSW.Client.RequestSummary(player)
    end
    if self.lastSelected ~= self.list.selected or now - (self.buttonsMs or 0) > BUTTONS_REFRESH_MS then
        self.lastSelected = self.list.selected
        self.buttonsMs = now
        self:updateButtons()
    end
end

function Window:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed or not self.list then
        return
    end
    local rule = LSW.Options.GetEffectiveRule()
    local text = ruleText(rule)
    if LSW.GetSandboxRule() ~= LSW.RULE_PLAYER then
        text = getText("IGUI_TienLastSeenWhere_RuleForced", text)
    end
    self:drawTextRight(text, self.width - PAD, self.ruleY + 3, 0.7, 0.7, 0.7, 1, UIFont.Small)
    if self:isBusy() then
        local width = getTextManager():MeasureStringX(UIFont.Small, text)
        local spinnerX = self.width - PAD - width - PAD - SPINNER_RADIUS - SPINNER_DOT
        self:drawSpinner(spinnerX, self.ruleY + 3 + FONT_HGT_SMALL / 2)
        if LSW.Client.IsServerBusy(self.playerNum) then
            self:drawTextRight(getText("IGUI_TienLastSeenWhere_ServerBusy"), spinnerX - SPINNER_RADIUS - PAD,
                self.ruleY + 3, 1, 0.75, 0.4, 1, UIFont.Small)
        end
    end
    if #self.list.items > 0 then
        return
    end
    local key
    if self:getQuery() == "" then
        key = "IGUI_TienLastSeenWhere_Hint"
    elseif self.scope == Window.SCOPE_BUILDING and not LSW.BuildingKey(self:player():getCurrentSquare()) then
        key = "IGUI_TienLastSeenWhere_NotInBuilding"
    elseif self:isBusy() then
        key = "IGUI_TienLastSeenWhere_Searching"
    else
        key = "IGUI_TienLastSeenWhere_NothingRemembered"
    end
    self:drawTextCentre(getText(key), self.list:getX() + self.list:getWidth() / 2,
        self.list:getY() + PAD, 0.7, 0.7, 0.7, 1, UIFont.Small)
end

function Window:isBusy()
    return self.matching or self.findDueMs ~= nil or LSW.Client.IsBusy(self.playerNum)
end

function Window:drawSpinner(cx, cy)
    local tex = self.dotTexture
    if not tex then
        return
    end
    local c = LSW.Options.GetArrowColour()
    local step = math.floor(getTimestampMs() / 90) % SPINNER_DOTS
    for i = 0, SPINNER_DOTS - 1 do
        local angle = i * 2 * math.pi / SPINNER_DOTS
        local age = (step - i) % SPINNER_DOTS
        local alpha = 1 - age / SPINNER_DOTS
        local x = cx + math.cos(angle) * SPINNER_RADIUS - SPINNER_DOT / 2
        local y = cy + math.sin(angle) * SPINNER_RADIUS - SPINNER_DOT / 2
        self:drawTextureScaled(tex, x, y, SPINNER_DOT, SPINNER_DOT, alpha, c.r, c.g, c.b)
    end
end

function Window:onClientEvent(event)
    if event == "summary" then
        self.lastFindKey = nil
        self:refreshResults()
    else
        self:rebuildRows()
    end
end

function Window:close()
    Jobs.Cancel(self:jobName())
    self.matching = false
    if self.entry then
        self.entry:unfocus()
    end
    LSW.Client.Unlisten(self.playerNum, "window")
    ISCollapsableWindow.close(self)
end

function Window:open()
    self:setVisible(true)
    self:bringToTop()
    self.entry:focus()
    local window = self
    LSW.Client.Listen(self.playerNum, "window", function(event)
        window:onClientEvent(event)
    end)
    self.summaryMs = getTimestampMs()
    self.lastFindKey = nil
    LSW.Client.RequestSummary(self:player())
    self:refreshResults()
end

function Window.Get(playerNum)
    local window = Window.instances[playerNum]
    if window then
        return window
    end
    local x = getPlayerScreenLeft(playerNum) + (getPlayerScreenWidth(playerNum) - WIDTH) / 2
    local y = getPlayerScreenTop(playerNum) + (getPlayerScreenHeight(playerNum) - HEIGHT) / 2
    window = Window:new(x, y, WIDTH, HEIGHT, playerNum)
    window:initialise()
    window:addToUIManager()
    window:setVisible(false)
    Window.instances[playerNum] = window
    return window
end

function Window.Toggle(playerNum)
    local window = Window.Get(playerNum)
    if window:isVisible() then
        window:close()
    else
        window:open()
    end
end

local function onPlayerDeath(player)
    if not player:isLocalPlayer() then
        return
    end
    local window = Window.instances[player:getPlayerNum()]
    if window then
        window:close()
    end
end

local function onGameStart()
    Window.instances = {}
    nameCache = {}
end

Events.OnPlayerDeath.Add(onPlayerDeath)
Events.OnGameStart.Add(onGameStart)
