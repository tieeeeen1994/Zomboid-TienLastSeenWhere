require "ISUI/ISTickBox"
require "TienLastSeenWhere_Window"
require "TienLastSeenWhere_Watch"
require "TienLastSeenWhere_PrivacyMenu"

local LSW = TienLastSeenWhere
local Window = LSW.Window
local Menu = LSW.PrivacyMenu

local PAD = Window.PAD
local ROW = Window.ROW
local ICON = Window.ICON
local PLACE_ROW = Window.PLACE_ROW
local ARROW_COLUMN = Window.ARROW_COLUMN
local ARROW_X = Window.ARROW_X
local FONT_HGT_SMALL = Window.FONT_HGT_SMALL
local PLACES_REFRESH_MS = 15000
local NEAR_REFRESH_MS = 1000

Window.VIEW_MARKED = 1
Window.VIEW_PLACES = 2
Window.VIEW_NEAR = 3

local LEVEL_COLOURS = {
    [LSW.PRIVATE_ME] = { 1, 0.6, 0.35 },
    [LSW.PRIVATE_GROUP] = { 0.5, 0.75, 1 },
}

local function levelText(level)
    if level == LSW.PRIVATE_ME then
        return getText("IGUI_TienLastSeenWhere_LevelMe")
    end
    if level == LSW.PRIVATE_GROUP then
        return getText("IGUI_TienLastSeenWhere_LevelGroup")
    end
    return nil
end

local function trimmedLower(entry)
    local text = entry and entry:getInternalText() or ""
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return string.lower(text)
end

local function matches(text, query)
    return query == "" or string.find(string.lower(text), query, 1, true) ~= nil
end

function Window:createPrivacyChildren(top, entryHeight, buttonTop, buttonHeight)
    self.privacyView = Window.VIEW_NEAR

    self.pEntry = ISTextEntryBox:new("", PAD, top, self.width - PAD * 2, entryHeight)
    self.pEntry.anchorRight = true
    self.pEntry:initialise()
    self.pEntry:instantiate()
    self.pEntry:setPlaceholderText(getText("IGUI_TienLastSeenWhere_PrivacyPlaceholder"))
    self.pEntry:setClearButton(true)
    self.pEntry.target = self
    self.pEntry.onTextChangeFunction = Window.onPrivacyTextChange
    self:addChild(self.pEntry)

    local comboTop = self.pEntry:getBottom() + PAD
    self.viewCombo = ISComboBox:new(PAD, comboTop, 240, entryHeight, self, Window.onViewChange)
    self.viewCombo:initialise()
    self:addChild(self.viewCombo)
    self.viewCombo:addOptionWithData(getText("IGUI_TienLastSeenWhere_ViewNear"), Window.VIEW_NEAR)
    self.viewCombo:addOptionWithData(getText("IGUI_TienLastSeenWhere_ViewPlaces"), Window.VIEW_PLACES)
    self.viewCombo:addOptionWithData(getText("IGUI_TienLastSeenWhere_ViewMarked"), Window.VIEW_MARKED)
    self.viewCombo.selected = 1

    local tickText = getText("IGUI_TienLastSeenWhere_SeeAll")
    local tickWidth = getTextManager():MeasureStringX(UIFont.Small, tickText) + entryHeight + 8
    self.seeAllTick = ISTickBox:new(self.width - PAD - tickWidth, comboTop + 2, tickWidth, entryHeight, "", self,
        Window.onSeeAllTick)
    self.seeAllTick.anchorLeft = false
    self.seeAllTick.anchorRight = true
    self.seeAllTick:initialise()
    self:addChild(self.seeAllTick)
    self.seeAllTick:addOption(tickText)
    self.seeAllTick.tooltip = getText("IGUI_TienLastSeenWhere_SeeAll_tooltip")

    local listTop = self.viewCombo:getBottom() + PAD
    self.pList = ISScrollingListBox:new(PAD, listTop, self.width - PAD * 2, buttonTop - PAD - listTop)
    self.pList.anchorRight = true
    self.pList.anchorBottom = true
    self.pList:initialise()
    self.pList:instantiate()
    self.pList.itemheight = ROW
    self.pList.font = UIFont.Small
    self.pList.drawBorder = true
    self.pList.window = self
    self.pList.doDrawItem = Window.drawPrivacyRow
    self.pList:setOnMouseDoubleClick(self, Window.onPrivacyShow)
    self:addChild(self.pList)

    self.pButtons = {}
    local specs = {
        { "me", "IGUI_TienLastSeenWhere_MarkMe", Window.onMarkMe, "IGUI_TienLastSeenWhere_MarkMe_tooltip" },
        { "group", "IGUI_TienLastSeenWhere_MarkGroup", Window.onMarkGroup, "IGUI_TienLastSeenWhere_MarkGroup_tooltip" },
        { "none", "IGUI_TienLastSeenWhere_Unmark", Window.onUnmark, "IGUI_TienLastSeenWhere_Unmark_tooltip" },
        { "show", "IGUI_TienLastSeenWhere_Show", Window.onPrivacyShow, nil },
    }
    local x = PAD
    for _, spec in ipairs(specs) do
        local text = getText(spec[2])
        local width = getTextManager():MeasureStringX(UIFont.Small, text) + 16
        local button = ISButton:new(x, buttonTop, width, buttonHeight, text, self, spec[3])
        button.anchorTop = false
        button.anchorBottom = true
        button:initialise()
        button:instantiate()
        if spec[4] then
            button.tooltip = getText(spec[4])
        end
        self:addChild(button)
        self.pButtons[spec[1]] = button
        x = x + width + PAD / 2
    end

    self.privacyWidgets = { self.pEntry, self.viewCombo, self.seeAllTick, self.pList }
    for _, button in pairs(self.pButtons) do
        self.privacyWidgets[#self.privacyWidgets + 1] = button
    end
end

function Window:acknowledgeIfNeeded()
    local privacy = LSW.Client.GetPrivacy(self.playerNum)
    local player = self:player()
    if player and privacy and privacy.fresh and self.tab == Window.TAB_PRIVACY
        and self.privacyView == Window.VIEW_MARKED and not LSW.Client.IsPrivacyBusy(self.playerNum) then
        LSW.Client.RequestPrivacy(player, true)
    end
end

function Window:onPrivacyShown()
    local player = self:player()
    if not player then
        return
    end
    local privacy = LSW.Client.GetPrivacy(self.playerNum)
    if not privacy and not LSW.Client.IsPrivacyBusy(self.playerNum) then
        LSW.Client.RequestPrivacy(player)
    end
    if privacy and privacy.fresh and self.privacyView ~= Window.VIEW_MARKED then
        self.viewCombo:selectData(Window.VIEW_MARKED)
        self.privacyView = Window.VIEW_MARKED
    end
    self:acknowledgeIfNeeded()
    if self.privacyView == Window.VIEW_PLACES then
        self:requestPlaces()
    end
    self:rebuildPrivacyRows()
    if self.pEntry and self:isVisible() then
        self.pEntry:focus()
    end
end

function Window:requestPlaces()
    local player = self:player()
    if player then
        self.placesMs = getTimestampMs()
        LSW.Client.RequestPlaces(player)
    end
end

function Window:onPrivacyTextChange()
    self:rebuildPrivacyRows()
end

function Window:onViewChange()
    self.privacyView = self.viewCombo:getOptionData(self.viewCombo.selected) or Window.VIEW_MARKED
    if self.privacyView == Window.VIEW_PLACES then
        self:requestPlaces()
    end
    self.nearSignature = nil
    self:rebuildPrivacyRows()
    self:acknowledgeIfNeeded()
end

function Window:onSeeAllTick(index, selected)
    LSW.Client.SetSeeAll(self.playerNum, selected == true)
    self:refreshSearch()
end

function Window:selectedPrivacyRow()
    local row = self.pList.items[self.pList.selected]
    return row and row.item or nil
end

local function rowKey(row)
    if row.row == "place" or row.row == "container" then
        return LSW.MarkKey(LSW.MARK_PLACE, row.key)
    end
    if row.row == "item" and row.bag then
        return LSW.MarkKey(LSW.MARK_PLACE, "b:" .. string.format("%d", tonumber(row.id)))
    end
    if row.row == "item" then
        return LSW.MarkKey(LSW.MARK_ITEM, string.format("%d", tonumber(row.id)))
    end
    return nil
end

function Window:isNewRow(row)
    local key = self.freshKeys and rowKey(row)
    return key ~= nil and self.freshKeys[key] == true
end

local function placeRow(playerNum, place, key, level)
    local mark = LSW.Client.GetMark(playerNum, LSW.MARK_PLACE, key)
    return {
        row = "place",
        key = key,
        place = place,
        level = level,
        label = Window.PlaceLabel(place),
        exposed = mark and mark.exposed or nil,
        exposedBy = mark and mark.exposedBy or nil,
        fresh = mark and mark.fresh == true,
    }
end

local function itemRow(playerNum, item, where, holder)
    local fullType = item:getFullType()
    local bag = instanceof(item, "InventoryContainer")
    local id = item:getID()
    local level
    local mark
    if bag then
        level = LSW.Client.GetMarkLevel(playerNum, LSW.MARK_PLACE, "b:" .. string.format("%d", id))
        mark = LSW.Client.GetMark(playerNum, LSW.MARK_PLACE, "b:" .. string.format("%d", id))
    else
        level = LSW.Client.GetMarkLevel(playerNum, LSW.MARK_ITEM, string.format("%d", id))
        mark = LSW.Client.GetMark(playerNum, LSW.MARK_ITEM, string.format("%d", id))
    end
    return {
        row = "item",
        id = id,
        fullType = fullType,
        info = Window.ScriptInfo(fullType),
        label = item:getDisplayName(),
        holder = holder,
        bag = bag,
        where = where,
        level = level,
        exposed = mark and mark.exposed or nil,
        exposedBy = mark and mark.exposedBy or nil,
        fresh = mark and mark.fresh == true,
    }
end

-- Nearest first by floor, then by flat distance: the player's own floor before any
-- other, nearer floors before farther ones (the one below first when one above is as
-- near), and within a floor by X/Y distance, then name.
local function setNearness(row, place, player)
    if not place.x or not place.y or not place.z then
        return
    end
    row.d = LSW.DistanceTo(player:getX(), player:getY(), place.x + 0.5, place.y + 0.5)
    row.floorGap = math.abs(place.z - math.floor(player:getZ()))
    row.floorZ = place.z
end

local function nearerPlace(a, b)
    if a.floorGap ~= b.floorGap then
        return a.floorGap < b.floorGap
    end
    if a.floorZ ~= b.floorZ then
        return a.floorZ < b.floorZ
    end
    if a.d ~= b.d then
        return a.d < b.d
    end
    return string.lower(a.label) < string.lower(b.label)
end

function Window:markedRows(query, player)
    local rows = {}
    local privacy = LSW.Client.GetPrivacy(self.playerNum)
    for _, mark in ipairs(privacy and privacy.marks or {}) do
        local row
        if mark.kind == LSW.MARK_PLACE then
            local place = {
                key = mark.id,
                kind = mark.placeKind or LSW.KIND_OBJECT,
                x = mark.x,
                y = mark.y,
                z = mark.z,
                type = mark.type,
                room = mark.room,
                t = mark.seen,
            }
            row = placeRow(self.playerNum, place, mark.id, mark.level)
            row.remembered = mark.seen ~= nil
            setNearness(row, place, player)
        else
            local info = Window.ScriptInfo(mark.fullType or "")
            row = {
                row = "item",
                id = mark.id,
                fullType = mark.fullType,
                info = info,
                label = info.name,
                level = mark.level,
                exposed = mark.exposed,
                exposedBy = mark.exposedBy,
                fresh = mark.fresh == true,
            }
        end
        if matches(row.label, query) then
            rows[#rows + 1] = row
        end
    end
    local window = self
    for _, row in ipairs(rows) do
        row.isNew = window:isNewRow(row)
    end
    table.sort(rows, function(a, b)
        if a.isNew ~= b.isNew then
            return a.isNew
        end
        if a.row ~= b.row then
            return a.row == "place"
        end
        if a.row == "place" and (a.d ~= nil) ~= (b.d ~= nil) then
            return a.d ~= nil
        end
        if a.row == "place" and a.d ~= nil then
            return nearerPlace(a, b)
        end
        return string.lower(a.label) < string.lower(b.label)
    end)
    return rows
end

function Window:placeRows(query, player)
    local rows = {}
    for _, place in ipairs(LSW.Client.GetPlaces(self.playerNum)) do
        local row = placeRow(self.playerNum, place, place.key,
            LSW.Client.GetMarkLevel(self.playerNum, LSW.MARK_PLACE, place.key))
        row.remembered = true
        if matches(row.label, query) then
            setNearness(row, place, player)
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b)
        if (a.d ~= nil) ~= (b.d ~= nil) then
            return a.d ~= nil
        end
        if a.d == nil then
            return string.lower(a.label) < string.lower(b.label)
        end
        return nearerPlace(a, b)
    end)
    return rows
end

local function lootContainer(playerNum)
    local page = getPlayerLoot(playerNum)
    if not page or not page:isReallyVisible() or page.isCollapsed then
        return nil
    end
    return page.inventoryPane and page.inventoryPane.inventory or nil
end

local function lootButtons(playerNum)
    local page = getPlayerLoot(playerNum)
    return page and page.backpacks or {}
end

local function squareOfContainer(container)
    local part = container:getVehiclePart()
    if part then
        return part:getVehicle():getSquare()
    end
    local bag = container:getContainingItem()
    if bag then
        local worldItem = bag:getWorldItem()
        if worldItem then
            return worldItem:getSquare()
        end
        local outer = bag:getContainer()
        return outer and squareOfContainer(outer) or nil
    end
    local parent = container:getParent()
    return parent and parent:getSquare() or nil
end

local function containerRow(playerNum, container, locator, title, shown)
    local square = squareOfContainer(container)
    local key = Menu.KeyOf(locator)
    local mark = key and LSW.Client.GetMark(playerNum, LSW.MARK_PLACE, key)
    return {
        row = "container",
        container = container,
        locator = locator,
        key = key or tostring(container),
        label = title,
        level = Menu.ContainerLevel(playerNum, locator) or LSW.PRIVATE_NONE,
        shown = shown,
        place = square and { x = square:getX(), y = square:getY(), z = square:getZ() } or {},
        exposed = mark and mark.exposed or nil,
        exposedBy = mark and mark.exposedBy or nil,
        fresh = mark and mark.fresh == true,
    }
end

function Window:nearRows(query, player)
    local rows = {}
    local playerNum = self.playerNum
    local walked = {}
    local function walk(container, where, holder, out, q)
        if walked[container] then
            return
        end
        walked[container] = true
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            local row = itemRow(playerNum, item, where, holder)
            if matches(row.label, q) then
                out[#out + 1] = row
            end
            if row.bag then
                walk(item:getInventory(), where, item:getDisplayName(), out, q)
            end
        end
    end
    local function append(block)
        for _, row in ipairs(block) do
            rows[#rows + 1] = row
        end
    end
    local mine = {}
    walk(player:getInventory(), { inv = true }, nil, mine, query)
    if #mine > 0 then
        rows[#rows + 1] = { row = "header", label = getText("IGUI_TienLastSeenWhere_HeaderOnMe") }
        append(mine)
    end
    local shownContainer = lootContainer(playerNum)
    local floor = ISInventoryPage.GetFloorContainer(playerNum)
    local blocks = {}
    local floorBlock = nil
    for _, button in ipairs(lootButtons(playerNum)) do
        local container = button.inventory
        if container and not walked[container] then
            if container == floor then
                local found = {}
                walk(container, { floor = true }, nil, found, query)
                if #found > 0 then
                    floorBlock = { { row = "header", label = getText("IGUI_TienLastSeenWhere_Floor") } }
                    for _, row in ipairs(found) do
                        floorBlock[#floorBlock + 1] = row
                    end
                end
            else
                local locator = LSW.Watch.Locate(player, container)
                if locator then
                    local title = button.name or Menu.ContainerTitle(container)
                    local labelMatches = matches(title, query)
                    local found = {}
                    walk(container, { locator = locator }, nil, found, labelMatches and "" or query)
                    if labelMatches or #found > 0 then
                        local shown = container == shownContainer
                        local block
                        if Menu.IsMarkable(locator) then
                            block = { containerRow(playerNum, container, locator, title, shown) }
                        else
                            block = { { row = "header", label = title } }
                        end
                        for _, row in ipairs(found) do
                            block[#block + 1] = row
                        end
                        if shown then
                            table.insert(blocks, 1, block)
                        else
                            blocks[#blocks + 1] = block
                        end
                    end
                end
            end
        end
    end
    for _, block in ipairs(blocks) do
        append(block)
    end
    if floorBlock then
        append(floorBlock)
    end
    return rows
end

local function nearSignature(player, playerNum)
    local count, sum = 0, 0
    local walked = {}
    local function walk(container)
        if walked[container] then
            return
        end
        walked[container] = true
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            count = count + 1
            sum = sum + item:getID()
            if instanceof(item, "InventoryContainer") then
                walk(item:getInventory())
            end
        end
    end
    walk(player:getInventory())
    local buttons = lootButtons(playerNum)
    local containers = {}
    for _, button in ipairs(buttons) do
        if button.inventory then
            containers[#containers + 1] = tostring(button.inventory)
            walk(button.inventory)
        end
    end
    return string.format("%d:%d:%s:%s", count, sum, tostring(lootContainer(playerNum)), table.concat(containers, ","))
end

function Window:rebuildPrivacyRows()
    local player = self:player()
    if not self.pList or not player then
        return
    end
    local selected = self:selectedPrivacyRow()
    local selectedKey = selected and rowKey(selected)
    local query = trimmedLower(self.pEntry)
    local rows
    if self.privacyView == Window.VIEW_PLACES then
        rows = self:placeRows(query, player)
    elseif self.privacyView == Window.VIEW_NEAR then
        rows = self:nearRows(query, player)
    else
        rows = self:markedRows(query, player)
    end
    self.pList:clear()
    for i, row in ipairs(rows) do
        local item = self.pList:addItem(row.label, row)
        if row.row == "place" or row.row == "container" then
            item.height = PLACE_ROW
        end
        if selectedKey and rowKey(row) == selectedKey then
            self.pList.selected = i
        end
    end
    self:updatePrivacyButtons()
end

function Window:updatePrivacyButtons()
    if not self.pButtons then
        return
    end
    local privacy = LSW.Client.GetPrivacy(self.playerNum)
    local row = self:selectedPrivacyRow()
    local markable = row ~= nil and (row.row == "place" or row.row == "item" or row.row == "container")
        and privacy ~= nil and privacy.enabled
    local level = row and row.level or LSW.PRIVATE_NONE
    self.pButtons.me:setEnable(markable and level ~= LSW.PRIVATE_ME)
    self.pButtons.group:setEnable(markable and level ~= LSW.PRIVATE_GROUP)
    self.pButtons.none:setEnable(markable and level ~= LSW.PRIVATE_NONE)
    self.pButtons.show:setEnable(row ~= nil and (row.row == "container"
        or (row.row == "place" and row.place.x ~= nil)))
end

function Window:setSelectedLevel(level)
    local player = self:player()
    local row = self:selectedPrivacyRow()
    if not player or not row then
        return
    end
    if row.row == "container" then
        Menu.MarkContainer(player, row.locator, level)
    elseif row.row == "place" then
        LSW.Client.SetMark(player, { kind = LSW.MARK_PLACE, key = row.key, level = level })
    elseif row.row == "item" then
        if row.bag and level == LSW.PRIVATE_NONE then
            LSW.Client.SetMark(player, {
                kind = LSW.MARK_PLACE,
                key = "b:" .. string.format("%d", row.id),
                level = level,
            })
        else
            LSW.Client.SetMark(player, {
                kind = LSW.MARK_ITEM,
                id = tonumber(row.id),
                level = level,
                locator = row.where and row.where.locator or nil,
            })
        end
    end
end

function Window:onMarkMe()
    self:setSelectedLevel(LSW.PRIVATE_ME)
end

function Window:onMarkGroup()
    self:setSelectedLevel(LSW.PRIVATE_GROUP)
end

function Window:onUnmark()
    self:setSelectedLevel(LSW.PRIVATE_NONE)
end

function Window:onPrivacyShow()
    self:releaseKeyboard()
    local row = self:selectedPrivacyRow()
    if row and row.row == "container" then
        LSW.Actions.OpenLoot(self:player(), row.container)
    elseif row and row.row == "place" and row.place.x then
        LSW.Actions.Show(self:player(), row.place, nil)
    end
end

function Window:onPrivacyEvent(event)
    if string.match(event, "^privacyRefused:") then
        return
    end
    local privacy = LSW.Client.GetPrivacy(self.playerNum)
    for _, mark in ipairs(privacy and privacy.marks or {}) do
        if mark.fresh then
            self.freshKeys = self.freshKeys or {}
            self.freshKeys[LSW.MarkKey(mark.kind, mark.id)] = true
        end
    end
    self:rebuildPrivacyRows()
    self:updatePrivacyTabTitle()
    self:acknowledgeIfNeeded()
end

function Window:updatePrivacyTabTitle()
    local button = self.tabButtons and self.tabButtons[Window.TAB_PRIVACY]
    if not button then
        return
    end
    local privacy = LSW.Client.GetPrivacy(self.playerNum)
    local fresh = privacy ~= nil and privacy.fresh
    local key = fresh and "IGUI_TienLastSeenWhere_TabPrivacyFound" or "IGUI_TienLastSeenWhere_TabPrivacy"
    if button.lswKey ~= key then
        button.lswKey = key
        button:setTitle(getText(key))
        if fresh then
            button.textColor = { r = 1, g = 0.55, b = 0.45, a = 1 }
        else
            button.textColor = { r = 1, g = 1, b = 1, a = 1 }
        end
    end
end

function Window:prerenderPrivacy(now)
    local privacy = LSW.Client.GetPrivacy(self.playerNum)
    local canSeeAll = privacy ~= nil and privacy.canSeeAll
    self.seeAllTick:setVisible(canSeeAll)
    self.seeAllTick.selected[1] = LSW.Client.GetSeeAll(self.playerNum)
    self.pButtons.group:setVisible(privacy ~= nil and privacy.group)
    if self.privacyView == Window.VIEW_PLACES and now - (self.placesMs or 0) > PLACES_REFRESH_MS then
        self:requestPlaces()
    end
    if self.privacyView == Window.VIEW_NEAR and now - (self.nearMs or 0) > NEAR_REFRESH_MS then
        self.nearMs = now
        local player = self:player()
        local signature = player and nearSignature(player, self.playerNum)
        if signature ~= self.nearSignature then
            self.nearSignature = signature
            self:rebuildPrivacyRows()
        end
    end
    if self.lastPrivacySelected ~= self.pList.selected then
        self.lastPrivacySelected = self.pList.selected
        self:updatePrivacyButtons()
    end
end

function Window:renderPrivacy()
    if #self.pList.items > 0 then
        return
    end
    local key
    local privacy = LSW.Client.GetPrivacy(self.playerNum)
    if LSW.Client.IsPrivacyBusy(self.playerNum) or not privacy then
        key = "IGUI_TienLastSeenWhere_Searching"
    elseif self.privacyView == Window.VIEW_PLACES then
        key = "IGUI_TienLastSeenWhere_NoPlaces"
    elseif self.privacyView == Window.VIEW_NEAR then
        key = "IGUI_TienLastSeenWhere_NothingNear"
    else
        key = "IGUI_TienLastSeenWhere_NothingMarked"
    end
    self:drawTextCentre(getText(key), self.pList:getX() + self.pList:getWidth() / 2,
        self.pList:getY() + PAD, 0.7, 0.7, 0.7, 1, UIFont.Small)
end

-- Clipped by hand like Window.drawRow (see the comment there).
function Window.drawPrivacyRow(list, y, item, alt)
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
    local isNew = data.row ~= "header" and window:isNewRow(data)
    if isNew and rowBottom > rowTop then
        list:drawRect(0, rowTop, list:getWidth(), rowBottom - rowTop, 0.18, 1, 0.35, 0.3)
    end
    if fillBottom > rowTop and data.row ~= "header" then
        if list.selected == item.index then
            list:drawSelection(0, rowTop, list:getWidth(), fillBottom - rowTop)
        elseif list.mouseoverselected == item.index and list:isMouseOver() and not list:isMouseOverScrollBar() then
            list:drawMouseOverHighlight(0, rowTop, list:getWidth(), fillBottom - rowTop)
        end
    end
    local textY = y + (item.height - FONT_HGT_SMALL) / 2
    if not fits(textY, textY + FONT_HGT_SMALL) then
        return y + item.height
    end
    local right = list:getWidth() - PAD - (list.vscroll and list.vscroll:getWidth() or 0)
    if data.row == "header" then
        list:drawRect(0, rowTop, list:getWidth(), rowBottom - rowTop, 0.25, 0.2, 0.2, 0.2)
        list:drawText(data.label, PAD, textY, 0.8, 0.8, 0.8, 1, UIFont.Small)
        return y + item.height
    end
    local parts = {}
    local level = levelText(data.level)
    local colour = LEVEL_COLOURS[data.level] or { 0.7, 0.7, 0.7 }
    local player = window:player()
    local x = PAD
    if data.row == "item" then
        if data.info and data.info.script and fits(y + 2, y + 2 + ICON) then
            list:drawScriptItemIcon(data.info.script, 4, y + 2, 1, ICON, ICON)
        end
        x = ICON + 10
        if data.holder then
            parts[#parts + 1] = data.holder
        end
    elseif data.row == "place" or data.row == "container" then
        local place = data.place
        x = ARROW_X + ARROW_COLUMN + 6
        if data.row == "container" and list.selected ~= item.index then
            list:drawRect(0, rowTop, list:getWidth(), rowBottom - rowTop, 0.25, 0.2, 0.2, 0.2)
        end
        if player and place.x then
            local arrowHalf = item.height * 0.4
            if fits(y + item.height / 2 - arrowHalf, y + item.height / 2 + arrowHalf) then
                window:drawArrow(list, y, item.height, place, player)
            end
            local distance = LSW.DistanceTo(player:getX(), player:getY(), place.x + 0.5, place.y + 0.5)
            local where
            if distance < 1.5 then
                where = getText("IGUI_TienLastSeenWhere_Here")
            else
                where = getText("IGUI_TienLastSeenWhere_Tiles", string.format("%d", math.floor(distance + 0.5)))
            end
            local floors = Window.FloorText(player, place)
            if floors then
                where = where .. ", " .. floors
            end
            parts[#parts + 1] = where
        end
        if data.shown then
            parts[#parts + 1] = getText("IGUI_TienLastSeenWhere_OpenNow")
        end
        if data.row == "place" and data.remembered == false then
            parts[#parts + 1] = getText("IGUI_TienLastSeenWhere_NotRemembered")
        elseif data.row == "place" and place.t then
            parts[#parts + 1] = Window.AgeText(place.t)
        end
    end
    local levelWidth = 0
    if level then
        list:drawTextRight(level, right, textY, colour[1], colour[2], colour[3], 1, UIFont.Small)
        levelWidth = getTextManager():MeasureStringX(UIFont.Small, level) + PAD * 2
    end
    local partsRight = right - levelWidth
    if data.exposed and data.level and data.level ~= LSW.PRIVATE_NONE then
        local text = getText("IGUI_TienLastSeenWhere_Exposed", tostring(data.exposedBy or "?"),
            Window.AgeText(data.exposed))
        if isNew then
            text = getText("IGUI_TienLastSeenWhere_NewFind", text)
            list:drawTextRight(text, partsRight, textY, 1, 0.4, 0.3, 1, UIFont.Small)
        else
            list:drawTextRight(text, partsRight, textY, 0.85, 0.55, 0.5, 1, UIFont.Small)
        end
        partsRight = partsRight - getTextManager():MeasureStringX(UIFont.Small, text) - PAD * 2
    end
    local partsText = table.concat(parts, "  ")
    if #parts > 0 then
        list:drawTextRight(partsText, partsRight, textY, 0.6, 0.6, 0.6, 1, UIFont.Small)
        partsRight = partsRight - getTextManager():MeasureStringX(UIFont.Small, partsText) - PAD * 2
    end
    list:drawText(Window.Fit(data.label, partsRight - x), x, textY, 0.9, 0.9, 0.9, 1, UIFont.Small)
    return y + item.height
end
