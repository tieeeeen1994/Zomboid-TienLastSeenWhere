require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferUtil"
require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Arrow"

local LSW = TienLastSeenWhere

LSW.Actions = {}

local Actions = LSW.Actions

Actions.OPEN_TIMEOUT_MS = 60000
Actions.OPEN_DISTANCE = 1.8

local pending = {}

local function squareOf(place)
    return getCell():getGridSquare(place.x, place.y, place.z)
end

local function spriteName(object)
    local sprite = object and object:getSprite()
    return sprite and sprite:getName() or nil
end

local function findBag(square, id)
    local objects = square:getWorldObjects()
    for i = 0, objects:size() - 1 do
        local item = objects:get(i):getItem()
        if item and item:getID() == id then
            return item
        end
    end
    local all = square:getObjects()
    for i = 0, all:size() - 1 do
        local object = all:get(i)
        for c = 0, object:getContainerCount() - 1 do
            local item = object:getContainerByIndex(c):getItemWithID(id)
            if item then
                return item
            end
        end
    end
    local vehicle = square:getVehicleContainer()
    if vehicle then
        for p = 0, vehicle:getPartCount() - 1 do
            local container = vehicle:getPartByIndex(p):getItemContainer()
            local item = container and container:getItemWithID(id)
            if item then
                return item
            end
        end
    end
    return nil
end

function Actions.FindContainer(place)
    local square = squareOf(place)
    if place.kind == LSW.KIND_VEHICLE then
        local partId = string.match(place.key, "^v:[^:]+:(.+)$")
        local vehicle = place.vehicle and getVehicleById(place.vehicle)
        if not vehicle and square then
            vehicle = square:getVehicleContainer()
        end
        local part = vehicle and partId and vehicle:getPartById(partId)
        return part and part:getItemContainer() or nil
    end
    if not square then
        return nil
    end
    if place.kind == LSW.KIND_OBJECT then
        local sprite, containerType = string.match(place.key, "^o:[^:]+:(.*):([^:]+)$")
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            if sprite == "nil" or spriteName(object) == sprite then
                local container = object:getContainerByType(containerType)
                if container then
                    return container
                end
            end
        end
        return nil
    end
    if place.kind == LSW.KIND_BODY then
        local index = tonumber(string.match(place.key, ":(%d+)$"))
        local bodies = square:getDeadBodys()
        local body = index and index < bodies:size() and bodies:get(index) or nil
        return body and body:getContainer() or nil
    end
    if place.kind == LSW.KIND_BAG then
        local id = tonumber(string.match(place.key, "^b:(%-?%d+)$"))
        local bag = id and findBag(square, id)
        if bag and instanceof(bag, "InventoryContainer") then
            return bag:getInventory()
        end
    end
    return nil
end

local function findOnFloor(square, fullType)
    local objects = square:getWorldObjects()
    for i = 0, objects:size() - 1 do
        local worldItem = objects:get(i)
        local item = worldItem:getItem()
        if item and item:getFullType() == fullType then
            return worldItem
        end
    end
    return nil
end

local function lootHas(playerNum, container)
    local loot = getPlayerLoot(playerNum)
    for _, button in ipairs(loot and loot.backpacks or {}) do
        if button.inventory == container then
            return true
        end
    end
    return false
end

local function floorInReach(player, square)
    local current = player:getCurrentSquare()
    if not current or square:getZ() ~= current:getZ() then
        return false
    end
    if math.abs(square:getX() - current:getX()) > 1 or math.abs(square:getY() - current:getY()) > 1 then
        return false
    end
    return square == current or current:canReachTo(square)
end

function Actions.Takeable(player, place, fullType)
    if place.kind == LSW.KIND_FLOOR then
        local square = squareOf(place)
        if not square or not floorInReach(player, square) then
            return nil
        end
        local worldItem = findOnFloor(square, fullType)
        return worldItem and { worldItem = worldItem } or nil
    end
    local container = Actions.FindContainer(place)
    if not container or not lootHas(player:getPlayerNum(), container) then
        return nil
    end
    local item = container:getFirstTypeRecurse(fullType)
    if not item or item:getContainer() ~= container then
        item = container:getFirstType(fullType)
    end
    return item and { item = item, container = container } or nil
end

function Actions.Take(player, place, fullType)
    local found = Actions.Takeable(player, place, fullType)
    if not found then
        return false
    end
    if found.worldItem then
        local time = ISWorldObjectContextMenu.grabItemTime(player, found.worldItem)
        ISTimedActionQueue.add(ISGrabItemAction:new(player, found.worldItem, time))
    else
        ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player, found.item,
            found.container, player:getInventory()))
    end
    return true
end

function Actions.Show(player, place, fullType)
    LSW.Arrow.SetTarget(player:getPlayerNum(), place, fullType)
end

local function openLoot(player, place)
    local container = Actions.FindContainer(place)
    local loot = getPlayerLoot(player:getPlayerNum())
    if not loot then
        return
    end
    if container then
        loot:setForceSelectedContainer(container, 1500)
        loot:selectButtonForContainer(container)
    elseif place.kind == LSW.KIND_FLOOR then
        local floor = ISInventoryPage.GetFloorContainer(player:getPlayerNum())
        loot:setForceSelectedContainer(floor, 1500)
        loot:selectButtonForContainer(floor)
    end
    loot:setVisible(true)
    loot.collapseCounter = 0
    if loot.isCollapsed then
        loot.isCollapsed = false
        loot:clearMaxDrawHeight()
        loot.collapseCounter = -30
    end
    ISInventoryPage.renderDirty = true
end

function Actions.GoThere(player, place, fullType)
    Actions.Show(player, place, fullType)
    local square = squareOf(place)
    if not square then
        return false
    end
    local destination = square
    if place.kind ~= LSW.KIND_FLOOR or not square:isFree(false) then
        destination = AdjacentFreeTileFinder.Find(square, player)
    end
    if not destination then
        return false
    end
    ISTimedActionQueue.clear(player)
    ISTimedActionQueue.add(ISWalkToTimedAction:new(player, destination))
    pending[player:getPlayerNum()] = { place = place, deadline = getTimestampMs() + Actions.OPEN_TIMEOUT_MS }
    return true
end

local function onTick()
    for playerNum, entry in pairs(pending) do
        local player = getSpecificPlayer(playerNum)
        if not player or player:isDead() or getTimestampMs() > entry.deadline then
            pending[playerNum] = nil
        elseif not ISTimedActionQueue.isPlayerDoingAction(player) and not player:isPlayerMoving() then
            pending[playerNum] = nil
            local place = entry.place
            local close = math.floor(player:getZ()) == place.z
                and LSW.DistanceTo(player:getX(), player:getY(), place.x + 0.5, place.y + 0.5) <= Actions.OPEN_DISTANCE
            if close then
                openLoot(player, place)
            end
        end
    end
end

local function onGameStart()
    pending = {}
end

Events.OnTick.Add(onTick)
Events.OnGameStart.Add(onGameStart)
