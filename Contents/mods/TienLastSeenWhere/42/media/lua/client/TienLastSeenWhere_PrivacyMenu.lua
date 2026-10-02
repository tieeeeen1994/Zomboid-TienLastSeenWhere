require "ISUI/ISContextMenu"
require "ISUI/ISInventoryPage"
require "ISUI/ISInventoryPane"
require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Client"
require "TienLastSeenWhere_Watch"

local LSW = TienLastSeenWhere

LSW.PrivacyMenu = {}

local Menu = LSW.PrivacyMenu

Menu.MAX_ITEMS = 20
Menu.MAX_TOP_CONTAINERS = 3

local LEVELS = {
    { LSW.PRIVATE_ME, "IGUI_TienLastSeenWhere_MarkMe", "IGUI_TienLastSeenWhere_MarkMe_tooltip" },
    { LSW.PRIVATE_GROUP, "IGUI_TienLastSeenWhere_MarkGroup", "IGUI_TienLastSeenWhere_MarkGroup_tooltip" },
    { LSW.PRIVATE_NONE, "IGUI_TienLastSeenWhere_Unmark", "IGUI_TienLastSeenWhere_Unmark_tooltip" },
}

function Menu.Usable(playerNum)
    if not LSW.IsPrivacyUseful() then
        return false
    end
    local privacy = LSW.Client.GetPrivacy(playerNum or 0)
    return privacy == nil or privacy.enabled
end

function Menu.GroupAllowed(playerNum)
    local privacy = LSW.Client.GetPrivacy(playerNum)
    if privacy then
        return privacy.group
    end
    return isClient()
end

function Menu.EnsurePrivacy(player)
    local playerNum = player:getPlayerNum()
    if not LSW.Client.GetPrivacy(playerNum) and not LSW.Client.IsPrivacyBusy(playerNum) then
        LSW.Client.RequestPrivacy(player)
    end
end

function Menu.IsMarkable(locator)
    return locator ~= nil and (locator.kind == LSW.KIND_OBJECT or locator.kind == LSW.KIND_VEHICLE
        or locator.kind == LSW.KIND_BAG)
end

function Menu.KeyOf(locator)
    if not locator then
        return nil
    end
    if locator.kind == LSW.KIND_OBJECT then
        return LSW.ObjectKey(locator.x, locator.y, locator.z, locator.sprite, locator.containerType)
    end
    if locator.kind == LSW.KIND_BAG then
        return "b:" .. string.format("%d", locator.id)
    end
    if locator.kind == LSW.KIND_VEHICLE then
        local vehicle = getVehicleById(locator.vehicle)
        local sqlId = vehicle and vehicle:getSqlId()
        if sqlId and sqlId >= 0 then
            return "v:" .. tostring(sqlId) .. ":" .. tostring(locator.part)
        end
    end
    return nil
end

function Menu.ContainerLevel(playerNum, locator)
    if not LSW.Client.GetPrivacy(playerNum) then
        return nil
    end
    local key = Menu.KeyOf(locator)
    if not key then
        return nil
    end
    return LSW.Client.GetMarkLevel(playerNum, LSW.MARK_PLACE, key)
end

function Menu.ItemLevel(playerNum, item)
    if not LSW.Client.GetPrivacy(playerNum) then
        return nil
    end
    local id = string.format("%d", item:getID())
    if instanceof(item, "InventoryContainer") then
        return LSW.Client.GetMarkLevel(playerNum, LSW.MARK_PLACE, "b:" .. id)
    end
    return LSW.Client.GetMarkLevel(playerNum, LSW.MARK_ITEM, id)
end

function Menu.ContainerTitle(container)
    local part = container:getVehiclePart()
    if part then
        return getTextOrNull("IGUI_VehiclePart" .. part:getId()) or part:getId()
    end
    local bag = container:getContainingItem()
    if bag then
        return bag:getDisplayName()
    end
    local containerType = tostring(container:getType())
    return getTextOrNull("IGUI_ContainerTitle_" .. containerType) or containerType
end

function Menu.MarkContainer(player, locator, level)
    LSW.Client.SetMark(player, { kind = LSW.MARK_PLACE, locator = locator, level = level })
end

function Menu.ItemLocator(player, item)
    local container = item:getContainer()
    if not container or container:isInCharacterInventory(player) then
        return nil
    end
    return LSW.Watch.Locate(player, container)
end

function Menu.MarkItem(player, item, level, locator)
    local id = item:getID()
    if instanceof(item, "InventoryContainer") and level == LSW.PRIVATE_NONE then
        LSW.Client.SetMark(player, { kind = LSW.MARK_PLACE, key = "b:" .. string.format("%d", id), level = level })
        return
    end
    LSW.Client.SetMark(player, { kind = LSW.MARK_ITEM, id = id, level = level, locator = locator })
end

local function addLevels(menu, playerNum, current, apply)
    local group = Menu.GroupAllowed(playerNum)
    for _, spec in ipairs(LEVELS) do
        local level = spec[1]
        if level ~= LSW.PRIVATE_GROUP or group then
            local option = menu:addOption(getText(spec[2]), level, apply)
            local tooltip = ISWorldObjectContextMenu.addToolTip()
            tooltip.description = getText(spec[3])
            option.toolTip = tooltip
            if current ~= nil then
                menu:setOptionChecked(option, current == level)
            end
        end
    end
end

function Menu.AddContainer(context, player, container, locator)
    local playerNum = player:getPlayerNum()
    local option = context:addOption(getText("IGUI_TienLastSeenWhere_MenuPrivacyOf", Menu.ContainerTitle(container)))
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(option, sub)
    addLevels(sub, playerNum, Menu.ContainerLevel(playerNum, locator), function(level)
        Menu.MarkContainer(player, locator, level)
    end)
end

local function objectContainers(player, worldobjects)
    local found = {}
    local seenObjects = {}
    for _, object in ipairs(worldobjects or {}) do
        if instanceof(object, "IsoObject") and not seenObjects[object] then
            seenObjects[object] = true
            for c = 0, object:getContainerCount() - 1 do
                local container = object:getContainerByIndex(c)
                local locator = LSW.Watch.Locate(player, container)
                if locator and locator.kind == LSW.KIND_OBJECT then
                    found[#found + 1] = { container = container, locator = locator }
                end
            end
        end
    end
    return found
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test or not Menu.Usable(playerNum) then
        return
    end
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then
        return
    end
    local found = objectContainers(player, worldobjects)
    if #found == 0 then
        return
    end
    Menu.EnsurePrivacy(player)
    local target = context
    if #found > Menu.MAX_TOP_CONTAINERS then
        local option = context:addOption(getText("IGUI_TienLastSeenWhere_TabPrivacy"))
        target = ISContextMenu:getNew(context)
        context:addSubMenu(option, target)
    end
    for _, entry in ipairs(found) do
        Menu.AddContainer(target, player, entry.container, entry.locator)
    end
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    if not Menu.Usable(playerNum) then
        return
    end
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then
        return
    end
    local actual = ISInventoryPane.getActualItems(items or {})
    if #actual == 0 then
        return
    end
    Menu.EnsurePrivacy(player)
    local chosen = {}
    for i = 1, math.min(#actual, Menu.MAX_ITEMS) do
        chosen[i] = actual[i]
    end
    local current = Menu.ItemLevel(playerNum, chosen[1])
    for i = 2, #chosen do
        if Menu.ItemLevel(playerNum, chosen[i]) ~= current then
            current = nil
            break
        end
    end
    local text
    if #chosen == 1 then
        text = getText("IGUI_TienLastSeenWhere_TabPrivacy")
    else
        text = getText("IGUI_TienLastSeenWhere_MenuPrivacyItems", string.format("%d", #chosen))
    end
    local option = context:addOption(text)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(option, sub)
    addLevels(sub, playerNum, current, function(level)
        for _, item in ipairs(chosen) do
            Menu.MarkItem(player, item, level, Menu.ItemLocator(player, item))
        end
    end)
end

local originalBackpackRightMouseDown = ISInventoryPage.onBackpackRightMouseDown

function ISInventoryPage:onBackpackRightMouseDown(x, y)
    local result = originalBackpackRightMouseDown(self, x, y)
    local container = self.inventory
    local page = self.parent and self.parent.parent
    if not container or not page or page.player == nil or container:getContainingItem()
        or not Menu.Usable(page.player) then
        return result
    end
    local player = getSpecificPlayer(page.player)
    local locator = player and LSW.Watch.Locate(player, container)
    if not locator or (locator.kind ~= LSW.KIND_OBJECT and locator.kind ~= LSW.KIND_VEHICLE) then
        return result
    end
    Menu.EnsurePrivacy(player)
    local context = getPlayerContextMenu(page.player)
    if not context or not context:isVisible() then
        context = ISContextMenu.get(page.player, getMouseX(), getMouseY())
    end
    Menu.AddContainer(context, player, container, locator)
    return result
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
