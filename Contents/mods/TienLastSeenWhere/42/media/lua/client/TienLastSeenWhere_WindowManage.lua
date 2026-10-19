require "ISUI/ISTickBox"
require "ISUI/ISModalDialog"
require "TienLastSeenWhere_Window"

local LSW = TienLastSeenWhere
local Window = LSW.Window

local PAD = Window.PAD
local ROW = Window.ROW
local ICON = Window.ICON
local PLACE_ROW = Window.PLACE_ROW
local ARROW_COLUMN = Window.ARROW_COLUMN
local FONT_HGT_SMALL = Window.FONT_HGT_SMALL
local LEFT_WIDTH = 230
local PLAYER_ROW = FONT_HGT_SMALL * 2 + 8
local TICK = math.max(10, ROW - 10)
local TICK_X = 4
local EXPAND_X = TICK_X + TICK + 4
local EXPAND_WIDTH = 14
local ICON_X = EXPAND_X + EXPAND_WIDTH
local PLACE_TICK_X = ICON_X
local PLACE_ARROW_X = PLACE_TICK_X + TICK + 2
local USERS_REFRESH_MS = 60000
local STATUS_MS = 10000
local CONFIRM_NAMES = 5

local function canSeeNetworkUsers(player)
    local role = player and player:getRole()
    return role ~= nil and Capability ~= nil and Capability.SeeNetworkUsers ~= nil
        and role:hasCapability(Capability.SeeNetworkUsers)
end

local function trimmed(entry)
    local text = entry and entry:getInternalText() or ""
    text = string.gsub(text, "^%s+", "")
    return (string.gsub(text, "%s+$", ""))
end

local function contains(text, query)
    return query == "" or (text ~= nil and string.find(string.lower(text), query, 1, true) ~= nil)
end

local function pairKey(key, fullType)
    return key .. "\n" .. fullType
end

local function rowKey(row)
    if row.row == "item" then
        return "i\n" .. row.fullType
    end
    if row.row == "place" then
        return "p\n" .. pairKey(row.place.key, row.fullType)
    end
    return nil
end

local function count(n)
    return string.format("%d", n or 0)
end

function Window:createManageChildren(top, entryHeight, buttonTop, buttonHeight)
    self.mExpanded = {}
    self.mChecked = { types = {}, at = {} }
    self.mExtraNames = {}

    local rightX = PAD * 2 + LEFT_WIDTH
    self.mPlayerEntry = ISTextEntryBox:new("", PAD, top, LEFT_WIDTH, entryHeight)
    self.mPlayerEntry:initialise()
    self.mPlayerEntry:instantiate()
    self.mPlayerEntry:setPlaceholderText(getText("IGUI_TienLastSeenWhere_ManagePlayerPlaceholder"))
    self.mPlayerEntry:setClearButton(true)
    self.mPlayerEntry.tooltip = getText("IGUI_TienLastSeenWhere_ManagePlayerPlaceholder_tooltip")
    self.mPlayerEntry.target = self
    self.mPlayerEntry.onTextChangeFunction = Window.onManagePlayerText
    local window = self
    self.mPlayerEntry.onCommandEntered = function()
        window:onManageLookUp()
    end
    self:addChild(self.mPlayerEntry)

    self.mItemEntry = ISTextEntryBox:new("", rightX, top, self.width - rightX - PAD, entryHeight)
    self.mItemEntry.anchorRight = true
    self.mItemEntry:initialise()
    self.mItemEntry:instantiate()
    self.mItemEntry:setPlaceholderText(getText("IGUI_TienLastSeenWhere_Placeholder"))
    self.mItemEntry:setClearButton(true)
    self.mItemEntry.target = self
    self.mItemEntry.onTextChangeFunction = Window.onManageItemText
    self:addChild(self.mItemEntry)

    local listTop = top + entryHeight + PAD
    local listHeight = buttonTop - PAD - listTop
    self.mPlayers = ISScrollingListBox:new(PAD, listTop, LEFT_WIDTH, listHeight)
    self.mPlayers.anchorBottom = true
    self.mPlayers:initialise()
    self.mPlayers:instantiate()
    self.mPlayers.itemheight = PLAYER_ROW
    self.mPlayers.font = UIFont.Small
    self.mPlayers.drawBorder = true
    self.mPlayers.window = self
    self.mPlayers.doDrawItem = Window.drawManagePlayerRow
    self:addChild(self.mPlayers)

    self.mItems = ISScrollingListBox:new(rightX, listTop, self.width - rightX - PAD, listHeight)
    self.mItems.anchorRight = true
    self.mItems.anchorBottom = true
    self.mItems:initialise()
    self.mItems:instantiate()
    self.mItems.itemheight = ROW
    self.mItems.font = UIFont.Small
    self.mItems.drawBorder = true
    self.mItems.window = self
    self.mItems.doDrawItem = Window.drawManageItemRow
    self.mItems.onMouseDown = Window.onManageItemsMouseDown
    self.mItems:setOnMouseDoubleClick(self, Window.onManageItemDoubleClick)
    self:addChild(self.mItems)

    self.mButtons = {}
    local specs = {
        { "forget", "IGUI_TienLastSeenWhere_ManageForget", Window.onManageForget },
        { "wipe", "IGUI_TienLastSeenWhere_ManageWipe", Window.onManageWipe },
        { "show", "IGUI_TienLastSeenWhere_Show", Window.onManageShow },
        { "refresh", "IGUI_TienLastSeenWhere_ManageRefresh", Window.onManageRefresh },
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
        button.tooltip = getTextOrNull(spec[2] .. "_tooltip")
        self:addChild(button)
        self.mButtons[spec[1]] = button
        x = x + width + PAD / 2
    end
    self.mStatusX = x + PAD / 2

    local tickText = getText("IGUI_TienLastSeenWhere_ManageShared")
    local tickWidth = getTextManager():MeasureStringX(UIFont.Small, tickText) + buttonHeight + 8
    self.mSharedTick = ISTickBox:new(self.width - PAD - tickWidth, buttonTop + 2, tickWidth, buttonHeight, "", self, nil)
    self.mSharedTick.anchorLeft = false
    self.mSharedTick.anchorRight = true
    self.mSharedTick.anchorTop = false
    self.mSharedTick.anchorBottom = true
    self.mSharedTick:initialise()
    self:addChild(self.mSharedTick)
    self.mSharedTick:addOption(tickText)
    self.mSharedTick.tooltip = getText("IGUI_TienLastSeenWhere_ManageShared_tooltip")

    self.manageWidgets = { self.mPlayerEntry, self.mItemEntry, self.mPlayers, self.mItems, self.mSharedTick }
    for _, button in pairs(self.mButtons) do
        self.manageWidgets[#self.manageWidgets + 1] = button
    end
end

function Window:manage()
    return LSW.Client.GetManage(self.playerNum)
end

function Window:onManageShown()
    if not self.mUsersMs or getTimestampMs() - self.mUsersMs > USERS_REFRESH_MS then
        self:requestManageUsers()
    end
    if self.mUsername then
        local summary = self:manage().summary
        if not summary or summary.username ~= self.mUsername then
            self:requestManageSummary()
        end
    end
    self:rebuildManagePlayers()
    self:rebuildManageItems()
    if self.mPlayerEntry and self:isVisible() then
        self.mPlayerEntry:focus()
    end
end

function Window:sendManageUsers()
    local player = self:player()
    if not player then
        return
    end
    local names = {}
    if isClient() and canSeeNetworkUsers(player) then
        local users = getUsers()
        if users then
            for i = 0, users:size() - 1 do
                names[#names + 1] = users:get(i):getUsername()
            end
        end
    end
    for name in pairs(self.mExtraNames) do
        names[#names + 1] = name
    end
    LSW.Client.RequestManage(player, "users", { usernames = names })
end

function Window:requestManageUsers()
    local player = self:player()
    if not player then
        return
    end
    self.mUsersMs = getTimestampMs()
    if isClient() and canSeeNetworkUsers(player) then
        self.mWaitingNetworkUsers = true
        requestUsers()
    end
    self:sendManageUsers()
end

function Window:requestManageSummary()
    local player = self:player()
    if player and self.mUsername then
        LSW.Client.RequestManage(player, "summary", { username = self.mUsername })
    end
end

function Window:requestManagePlaces(fullType)
    local player = self:player()
    if player and self.mUsername then
        LSW.Client.RequestManage(player, "places", { username = self.mUsername, fullType = fullType })
    end
end

function Window:placesSlot(fullType)
    return LSW.Client.ManageSlot("places", { username = self.mUsername, fullType = fullType })
end

function Window:onManagePlayerText()
    self:rebuildManagePlayers()
end

function Window:onManageItemText()
    self:rebuildManageItems()
end

function Window:onManageLookUp()
    local name = trimmed(self.mPlayerEntry)
    if name == "" then
        return
    end
    self.mExtraNames[name] = true
    self.mUsersMs = getTimestampMs()
    self:sendManageUsers()
end

function Window:selectedManageUser()
    local row = self.mPlayers.items[self.mPlayers.selected]
    return row and row.item or nil
end

function Window:selectedManageRow()
    local row = self.mItems.items[self.mItems.selected]
    return row and row.item or nil
end

function Window:rebuildManagePlayers()
    if not self.mPlayers then
        return
    end
    local query = string.lower(trimmed(self.mPlayerEntry))
    local rows = {}
    for _, user in ipairs(self:manage().users or {}) do
        if contains(user.username, query) or contains(user.name, query) then
            rows[#rows + 1] = user
        end
    end
    table.sort(rows, function(a, b)
        if (a.online == true) ~= (b.online == true) then
            return a.online == true
        end
        return string.lower(a.username) < string.lower(b.username)
    end)
    self.mPlayers:clear()
    self.mPlayers.selected = 0
    for i, user in ipairs(rows) do
        self.mPlayers:addItem(user.username, user)
        if user.username == self.mUsername then
            self.mPlayers.selected = i
        end
    end
    self.mLastPlayerSelected = self.mPlayers.selected
end

function Window:selectManageUser(username)
    if username == self.mUsername then
        return
    end
    self.mUsername = username
    self.mExpanded = {}
    self.mChecked = { types = {}, at = {} }
    self.mItems.selected = 0
    self:requestManageSummary()
    self:rebuildManageItems()
end

function Window:summaryRows(query)
    local summary = self:manage().summary
    local rows = {}
    if not summary or summary.username ~= self.mUsername then
        return rows
    end
    for _, total in ipairs(summary.types) do
        local info = Window.ScriptInfo(total.t)
        if query == "" or contains(info.lower, query) or contains(total.t, query) then
            rows[#rows + 1] = { row = "item", fullType = total.t, info = info, count = total.c, places = total.p }
        end
    end
    table.sort(rows, function(a, b)
        if a.info.lower ~= b.info.lower then
            return a.info.lower < b.info.lower
        end
        return a.fullType < b.fullType
    end)
    return rows
end

function Window:rebuildManageItems()
    if not self.mItems then
        return
    end
    local player = self:player()
    local selected = self:selectedManageRow()
    local selectedKey = selected and rowKey(selected)
    local manage = self:manage()
    self.mItems:clear()
    self.mItems.selected = 0
    local function add(row, height)
        local item = self.mItems:addItem(row.label or "", row)
        item.height = height or ROW
        if selectedKey and rowKey(row) == selectedKey then
            self.mItems.selected = #self.mItems.items
        end
    end
    for _, row in ipairs(self:summaryRows(string.lower(trimmed(self.mItemEntry)))) do
        row.label = row.info.name
        add(row)
        if self.mExpanded[row.fullType] then
            local found = manage.places[self:placesSlot(row.fullType)]
            if not found then
                add({ row = "note", label = getText("IGUI_TienLastSeenWhere_Searching") })
            else
                local places = {}
                for _, place in ipairs(found.places) do
                    places[#places + 1] = place
                end
                if player then
                    local px, py = player:getX(), player:getY()
                    table.sort(places, function(a, b)
                        return LSW.DistanceTo(px, py, a.x + 0.5, a.y + 0.5) < LSW.DistanceTo(px, py, b.x + 0.5, b.y + 0.5)
                    end)
                end
                for _, place in ipairs(places) do
                    add({ row = "place", fullType = row.fullType, place = place, label = Window.PlaceLabel(place) },
                        PLACE_ROW)
                end
                if found.total > #places then
                    add({ row = "note", label = getText("IGUI_TienLastSeenWhere_ManageNearest", count(#places),
                        count(found.total)) })
                end
            end
        end
    end
    self:updateManageButtons()
end

function Window:isManageChecked(row)
    if row.row == "item" then
        return self.mChecked.types[row.fullType] == true
    end
    if row.row == "place" then
        return self.mChecked.types[row.fullType] == true
            or self.mChecked.at[pairKey(row.place.key, row.fullType)] ~= nil
    end
    return false
end

function Window:toggleManageCheck(row)
    local checked = self.mChecked
    if row.row == "item" then
        if checked.types[row.fullType] then
            checked.types[row.fullType] = nil
        else
            checked.types[row.fullType] = true
            for key, pair in pairs(checked.at) do
                if pair.type == row.fullType then
                    checked.at[key] = nil
                end
            end
        end
    elseif row.row == "place" and not checked.types[row.fullType] then
        local key = pairKey(row.place.key, row.fullType)
        if checked.at[key] then
            checked.at[key] = nil
        else
            checked.at[key] = { key = row.place.key, type = row.fullType, label = row.label }
        end
    end
    self:updateManageButtons()
end

function Window:toggleManageExpand(fullType)
    if self.mExpanded[fullType] then
        self.mExpanded[fullType] = nil
    else
        self.mExpanded[fullType] = true
        self:requestManagePlaces(fullType)
    end
    self:rebuildManageItems()
end

local function inTick(row, x)
    if row.row == "item" then
        return x < EXPAND_X
    end
    if row.row == "place" then
        return x >= PLACE_TICK_X - 2 and x < PLACE_TICK_X + TICK + 2
    end
    return false
end

function Window.onManageItemsMouseDown(list, x, y)
    local index = list:rowAt(x, y)
    ISScrollingListBox.onMouseDown(list, x, y)
    local item = index > 0 and list.items[index] or nil
    local window = list.window
    if not item then
        return
    end
    local row = item.item
    if inTick(row, x) then
        window:toggleManageCheck(row)
    elseif row.row == "item" and x < ICON_X then
        window:toggleManageExpand(row.fullType)
    end
end

function Window:onManageItemDoubleClick(row)
    if not row or inTick(row, self.mItems:getMouseX()) then
        return
    end
    if row.row == "item" then
        if self.mItems:getMouseX() >= ICON_X then
            self:toggleManageExpand(row.fullType)
        end
    elseif row.row == "place" then
        self:onManageShow()
    end
end

function Window:checkedSelection()
    local types = {}
    local at = {}
    local names = {}
    for fullType in pairs(self.mChecked.types) do
        types[#types + 1] = fullType
        names[#names + 1] = Window.ScriptInfo(fullType).name
    end
    for _, pair in pairs(self.mChecked.at) do
        at[#at + 1] = { key = pair.key, type = pair.type }
        names[#names + 1] = getText("IGUI_TienLastSeenWhere_ManageAtPlace", Window.ScriptInfo(pair.type).name,
            pair.label or "?")
    end
    if #types == 0 and #at == 0 then
        local row = self:selectedManageRow()
        if row and row.row == "item" then
            types[1] = row.fullType
            names[1] = row.info.name
        elseif row and row.row == "place" then
            at[1] = { key = row.place.key, type = row.fullType }
            names[1] = getText("IGUI_TienLastSeenWhere_ManageAtPlace", Window.ScriptInfo(row.fullType).name, row.label)
        end
    end
    table.sort(names)
    return types, at, names
end

function Window:updateManageButtons()
    if not self.mButtons then
        return
    end
    local types, at = self:checkedSelection()
    local row = self:selectedManageRow()
    local busy = self.mPendingAction ~= nil and LSW.Client.IsManageBusy(self.playerNum, self.mPendingAction)
    self.mButtons.forget:setEnable(self.mUsername ~= nil and (#types > 0 or #at > 0) and not busy)
    self.mButtons.wipe:setEnable(self.mUsername ~= nil and not busy)
    self.mButtons.show:setEnable(row ~= nil and row.row == "place")
    local checked = 0
    for _ in pairs(self.mChecked.types) do
        checked = checked + 1
    end
    for _ in pairs(self.mChecked.at) do
        checked = checked + 1
    end
    local title = getText("IGUI_TienLastSeenWhere_ManageForget")
    if checked > 0 then
        title = getText("IGUI_TienLastSeenWhere_ManageForgetCount", count(checked))
    end
    if self.mButtons.forget:getTitle() ~= title then
        self.mButtons.forget:setTitle(title)
        local width = getTextManager():MeasureStringX(UIFont.Small, title) + 16
        local grow = width - self.mButtons.forget:getWidth()
        self.mButtons.forget:setWidth(width)
        for _, name in ipairs({ "wipe", "show", "refresh" }) do
            local button = self.mButtons[name]
            button:setX(button:getX() + grow)
        end
        self.mStatusX = self.mStatusX + grow
    end
end

function Window:confirmManage(text, op, args)
    self:releaseKeyboard()
    self.mConfirm = { op = op, args = args }
    local modal = ISModalDialog:new(0, 0, 420, 150, text, true, self, Window.onManageConfirmed, self.playerNum)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
end

function Window:onManageConfirmed(button)
    local confirm = self.mConfirm
    self.mConfirm = nil
    local player = self:player()
    if not confirm or not player or button.internal ~= "YES" then
        return
    end
    self.mPendingAction = confirm.op
    self.mStatus = nil
    LSW.Client.RequestManage(player, confirm.op, confirm.args)
    self:updateManageButtons()
end

local function nameList(names)
    local shown = {}
    for i = 1, math.min(#names, CONFIRM_NAMES) do
        shown[i] = names[i]
    end
    local text = table.concat(shown, ", ")
    if #names > CONFIRM_NAMES then
        text = getText("IGUI_TienLastSeenWhere_ManageAndMore", text, count(#names - CONFIRM_NAMES))
    end
    return text
end

function Window:sharedTicked()
    return self.mSharedTick.selected[1] == true
end

function Window:onManageForget()
    local types, at, names = self:checkedSelection()
    if not self.mUsername or (#types == 0 and #at == 0) then
        return
    end
    local text = getText("IGUI_TienLastSeenWhere_ManageForgetConfirm", self.mUsername, nameList(names))
    if self:sharedTicked() then
        text = text .. " " .. getText("IGUI_TienLastSeenWhere_ManageSharedConfirm")
    end
    self:confirmManage(text, "forget", { username = self.mUsername, types = types, at = at, world = self:sharedTicked() })
end

function Window:onManageWipe()
    if not self.mUsername then
        return
    end
    local text = getText("IGUI_TienLastSeenWhere_ManageWipeConfirm", self.mUsername)
    if self:sharedTicked() then
        text = text .. " " .. getText("IGUI_TienLastSeenWhere_ManageSharedConfirm")
    end
    self:confirmManage(text, "wipe", { username = self.mUsername, world = self:sharedTicked() })
end

function Window:onManageShow()
    self:releaseKeyboard()
    local row = self:selectedManageRow()
    if row and row.row == "place" then
        LSW.Actions.Show(self:player(), row.place, row.fullType)
    end
end

function Window:onManageRefresh()
    self:requestManageUsers()
    self:requestManageSummary()
    for fullType in pairs(self.mExpanded) do
        self:requestManagePlaces(fullType)
    end
end

function Window:setManageStatus(text)
    self.mStatus = { text = text, ms = getTimestampMs() }
end

function Window:onManageResult(op)
    local result = self:manage().result
    self.mPendingAction = nil
    if not result then
        return
    end
    local text
    if op == "forget" then
        text = getText("IGUI_TienLastSeenWhere_ManageForgot", tostring(result.username), count(result.items),
            count(result.places))
        if (tonumber(result.worldPlaces) or 0) > 0 then
            text = text .. " " .. getText("IGUI_TienLastSeenWhere_ManageForgotShared", count(result.worldPlaces))
        end
        self.mChecked = { types = {}, at = {} }
    else
        text = getText("IGUI_TienLastSeenWhere_ManageWiped", tostring(result.username), count(result.places))
        if (tonumber(result.worldPlaces) or 0) > 0 then
            text = text .. " " .. getText("IGUI_TienLastSeenWhere_ManageForgotShared", count(result.worldPlaces))
        end
        self.mChecked = { types = {}, at = {} }
        self.mExpanded = {}
    end
    self:setManageStatus(text)
    self:onManageRefresh()
end

function Window:onManageEvent(op)
    if op == "access" then
        self:layoutTabs()
        if self.tab == Window.TAB_MANAGE and not self:manageAvailable() then
            self:setTab(Window.TAB_FIND)
        end
        return
    end
    if op == "users" then
        self:rebuildManagePlayers()
    elseif op == "forget" or op == "wipe" then
        self:onManageResult(op)
    else
        self:rebuildManageItems()
    end
end

function Window:prerenderManage(now)
    local selected = self.mPlayers.selected
    if selected ~= self.mLastPlayerSelected then
        self.mLastPlayerSelected = selected
        local user = self:selectedManageUser()
        if user then
            self:selectManageUser(user.username)
        end
    end
    if self.lastManageSelected ~= self.mItems.selected or now - (self.manageButtonsMs or 0) > 500 then
        self.lastManageSelected = self.mItems.selected
        self.manageButtonsMs = now
        self:updateManageButtons()
    end
    if self.mStatus and now - self.mStatus.ms > STATUS_MS then
        self.mStatus = nil
    end
end

function Window:renderManage()
    local function hint(list, key, ...)
        if #list.items == 0 then
            local text = Window.Fit(getText(key, ...), list:getWidth() - PAD * 2)
            self:drawTextCentre(text, list:getX() + list:getWidth() / 2, list:getY() + PAD, 0.7, 0.7, 0.7, 1,
                UIFont.Small)
        end
    end
    local manage = self:manage()
    if not manage.users then
        hint(self.mPlayers, "IGUI_TienLastSeenWhere_Searching")
    else
        hint(self.mPlayers, "IGUI_TienLastSeenWhere_ManageNoPlayers")
    end
    local summary = manage.summary
    if not self.mUsername then
        hint(self.mItems, "IGUI_TienLastSeenWhere_ManagePickPlayer")
    elseif not summary or summary.username ~= self.mUsername
        or LSW.Client.IsManageBusy(self.playerNum, "summary") then
        hint(self.mItems, "IGUI_TienLastSeenWhere_Searching")
    elseif #summary.types == 0 then
        hint(self.mItems, "IGUI_TienLastSeenWhere_ManageRemembersNothing", self.mUsername)
    else
        hint(self.mItems, "IGUI_TienLastSeenWhere_ManageNoMatch")
    end
    local button = self.mButtons.refresh
    local textY = button:getY() + (button:getHeight() - FONT_HGT_SMALL) / 2
    local x = self.mStatusX
    local right = self.mSharedTick:getX() - PAD
    if LSW.Client.IsManageBusy(self.playerNum) then
        self:drawSpinner(x + 8, textY + FONT_HGT_SMALL / 2)
        x = x + 8 + PAD * 2
    end
    if self.mStatus and right > x then
        self:drawText(Window.Fit(self.mStatus.text, right - x), x, textY, 0.6, 0.9, 0.6, 1, UIFont.Small)
    end
end

local function drawTick(list, x, y, height, checked, implied)
    local top = y + (height - TICK) / 2
    list:drawRectBorder(x, top, TICK, TICK, 0.8, 0.8, 0.8, 0.8)
    if checked then
        local alpha = implied and 0.45 or 0.9
        local c = LSW.Options.GetArrowColour()
        list:drawRect(x + 3, top + 3, TICK - 6, TICK - 6, alpha, c.r, c.g, c.b)
    end
end

-- Clipped by hand like Window.drawRow (see the comment there).
local function visibleBand(list, y, item)
    local viewTop = 1 - list:getYScroll()
    local viewBottom = list.height - 1 - list:getYScroll()
    local rowTop = math.max(y, viewTop)
    local rowBottom = math.min(y + item.height, viewBottom)
    return viewTop, viewBottom, rowTop, rowBottom
end

local function highlight(list, item, rowTop, fillBottom)
    if fillBottom <= rowTop then
        return
    end
    if list.selected == item.index then
        list:drawSelection(0, rowTop, list:getWidth(), fillBottom - rowTop)
    elseif list.mouseoverselected == item.index and list:isMouseOver() and not list:isMouseOverScrollBar() then
        list:drawMouseOverHighlight(0, rowTop, list:getWidth(), fillBottom - rowTop)
    end
end

function Window.drawManagePlayerRow(list, y, item, alt)
    local window = list.window
    local user = item.item
    local viewTop, viewBottom, rowTop, rowBottom = visibleBand(list, y, item)
    if rowBottom <= rowTop then
        return y + item.height
    end
    highlight(list, item, rowTop, math.min(y + item.height - 1, viewBottom))
    local top = y + 4
    if top < viewTop or top + FONT_HGT_SMALL * 2 > viewBottom then
        return y + item.height
    end
    local right = list:getWidth() - PAD - (list.vscroll and list.vscroll:getWidth() or 0)
    local x = PAD
    if user.online and window.dotTexture then
        list:drawTextureScaled(window.dotTexture, x, top + (FONT_HGT_SMALL - 8) / 2, 8, 8, 1, 0.4, 0.9, 0.4)
    end
    x = x + 14
    list:drawText(Window.Fit(user.username, right - x), x, top, 0.95, 0.95, 0.95, 1, UIFont.Small)
    local second = user.name or "-"
    if user.online then
        second = getText("IGUI_TienLastSeenWhere_ManageOnline", second)
    end
    list:drawText(Window.Fit(second, right - x), x, top + FONT_HGT_SMALL, 0.6, 0.6, 0.6, 1, UIFont.Small)
    return y + item.height
end

function Window.drawManageItemRow(list, y, item, alt)
    local window = list.window
    local data = item.item
    local viewTop, viewBottom, rowTop, rowBottom = visibleBand(list, y, item)
    if rowBottom <= rowTop then
        return y + item.height
    end
    local function fits(top, bottom)
        return top >= viewTop and bottom <= viewBottom
    end
    if data.row == "item" then
        list:drawRect(0, rowTop, list:getWidth(), rowBottom - rowTop, 0.25, 0.2, 0.2, 0.2)
    end
    highlight(list, item, rowTop, math.min(y + item.height - 1, viewBottom))
    local textY = y + (item.height - FONT_HGT_SMALL) / 2
    if not fits(textY, textY + FONT_HGT_SMALL) then
        return y + item.height
    end
    local right = list:getWidth() - PAD - (list.vscroll and list.vscroll:getWidth() or 0)
    if data.row == "note" then
        list:drawText(Window.Fit(data.label, right - ICON_X), ICON_X, textY, 0.6, 0.6, 0.6, 1, UIFont.Small)
        return y + item.height
    end
    local player = window:player()
    if data.row == "item" then
        drawTick(list, TICK_X, y, item.height, window:isManageChecked(data), false)
        list:drawText(window.mExpanded[data.fullType] and "-" or "+", EXPAND_X + 3, textY, 0.8, 0.8, 0.8, 1,
            UIFont.Small)
        if data.info.script and fits(y + 2, y + 2 + ICON) then
            list:drawScriptItemIcon(data.info.script, ICON_X, y + 2, 1, ICON, ICON)
        end
        local countText = "x" .. count(data.count)
        local placesText = getText(data.places == 1 and "IGUI_TienLastSeenWhere_ManageOnePlace"
            or "IGUI_TienLastSeenWhere_ManagePlaces", count(data.places))
        list:drawTextRight(countText, right, textY, 0.8, 0.8, 0.8, 1, UIFont.Small)
        local placesRight = right - getTextManager():MeasureStringX(UIFont.Small, "x9999") - PAD * 2
        list:drawTextRight(placesText, placesRight, textY, 0.6, 0.6, 0.6, 1, UIFont.Small)
        local labelX = ICON_X + ICON + 6
        local labelRight = placesRight - getTextManager():MeasureStringX(UIFont.Small, placesText) - PAD * 2
        list:drawText(Window.Fit(data.label, labelRight - labelX), labelX, textY, 1, 1, 1, 1, UIFont.Small)
        return y + item.height
    end
    local place = data.place
    drawTick(list, PLACE_TICK_X, y, item.height, window:isManageChecked(data),
        window.mChecked.types[data.fullType] == true)
    local parts = {}
    if player then
        local arrowHalf = item.height * 0.4
        if fits(y + item.height / 2 - arrowHalf, y + item.height / 2 + arrowHalf) then
            window:drawArrow(list, y, item.height, place, player, PLACE_ARROW_X)
        end
        local distance = LSW.DistanceTo(player:getX(), player:getY(), place.x + 0.5, place.y + 0.5)
        local where
        if distance < 1.5 then
            where = getText("IGUI_TienLastSeenWhere_Here")
        else
            where = getText("IGUI_TienLastSeenWhere_Tiles", count(math.floor(distance + 0.5)))
        end
        local floors = Window.FloorText(player, place)
        if floors then
            where = where .. ", " .. floors
        end
        parts[#parts + 1] = where
    end
    parts[#parts + 1] = Window.AgeText(place.t)
    local countText = "x" .. count(place.count)
    list:drawTextRight(countText, right, textY, 0.7, 0.7, 0.7, 1, UIFont.Small)
    local partsText = table.concat(parts, "  ")
    local partsRight = right - getTextManager():MeasureStringX(UIFont.Small, "x9999") - PAD * 2
    list:drawTextRight(partsText, partsRight, textY, 0.6, 0.6, 0.6, 1, UIFont.Small)
    local labelX = PLACE_ARROW_X + ARROW_COLUMN + 6
    local labelRight = partsRight - getTextManager():MeasureStringX(UIFont.Small, partsText) - PAD * 2
    list:drawText(Window.Fit(data.label, labelRight - labelX), labelX, textY, 0.9, 0.9, 0.9, 1, UIFont.Small)
    return y + item.height
end

local function onNetworkUsersReceived()
    for _, window in pairs(Window.instances) do
        if window.mWaitingNetworkUsers then
            window.mWaitingNetworkUsers = false
            if window:isVisible() then
                window:sendManageUsers()
            end
        end
    end
end

if Events.OnNetworkUsersReceived then
    Events.OnNetworkUsersReceived.Add(onNetworkUsersReceived)
end
