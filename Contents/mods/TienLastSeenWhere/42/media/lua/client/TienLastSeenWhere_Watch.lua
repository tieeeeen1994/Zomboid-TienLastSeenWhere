require "ISUI/ISInventoryPage"
require "Foraging/ISSearchManager"
require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Jobs"

local LSW = TienLastSeenWhere
local Jobs = LSW.Jobs

LSW.Watch = {}

local Watch = LSW.Watch

Watch.CONTAINER_DELAY_MS = 400
Watch.SWEEP_MS = 2000
Watch.SWEEP_RADIUS = 20
Watch.DARK = 0.3
Watch.BATCH = 250

local pages = {}
local floorSent = {}
local lastSweepMs = 0

local function containerIndex(object, container)
    for i = 0, object:getContainerCount() - 1 do
        if object:getContainerByIndex(i) == container then
            return i
        end
    end
    return -1
end

local function bodyIndex(square, body)
    local bodies = square:getDeadBodys()
    for i = 0, bodies:size() - 1 do
        if bodies:get(i) == body then
            return i
        end
    end
    return -1
end

function Watch.Locate(player, container)
    if not container or container:isInCharacterInventory(player) then
        return nil
    end
    local bag = container:getContainingItem()
    if bag then
        local worldItem = bag:getWorldItem()
        local square = worldItem and worldItem:getSquare()
        if square then
            return {
                kind = LSW.KIND_BAG,
                id = bag:getID(),
                parent = { kind = LSW.KIND_FLOOR, x = square:getX(), y = square:getY(), z = square:getZ() },
            }
        end
        local parent = Watch.Locate(player, bag:getContainer())
        if not parent then
            return nil
        end
        return { kind = LSW.KIND_BAG, id = bag:getID(), parent = parent }
    end
    local part = container:getVehiclePart()
    if part then
        return { kind = LSW.KIND_VEHICLE, vehicle = part:getVehicle():getId(), part = part:getId() }
    end
    local parent = container:getParent()
    if not parent then
        return nil
    end
    local square = parent:getSquare()
    if not square then
        return nil
    end
    if instanceof(parent, "IsoDeadBody") then
        return {
            kind = LSW.KIND_BODY,
            x = square:getX(),
            y = square:getY(),
            z = square:getZ(),
            index = bodyIndex(square, parent),
            bodyId = LSW.BodyId(parent),
        }
    end
    local sprite = parent:getSprite()
    return {
        kind = LSW.KIND_OBJECT,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        index = parent:getObjectIndex(),
        containerIndex = containerIndex(parent, container),
        containerType = container:getType(),
        sprite = sprite and sprite:getName() or nil,
    }
end

local function signature(container)
    local items = container:getItems()
    local sum = 0
    for i = 0, items:size() - 1 do
        sum = sum + items:get(i):getID()
    end
    return string.format("%d:%d", items:size(), sum)
end

local function squareSignature(square)
    local objects = square:getWorldObjects()
    local sum = 0
    for i = 0, objects:size() - 1 do
        local item = objects:get(i):getItem()
        if item then
            sum = sum + item:getID()
        end
    end
    return string.format("%d:%d", objects:size(), sum)
end

local function floorRuleOff()
    return LSW.GetFloorRule() == LSW.FLOOR_OFF
end

local function sendSquares(player, squares)
    local batch = {}
    for _, entry in ipairs(squares) do
        batch[#batch + 1] = entry
        if #batch >= Watch.BATCH then
            LSW.ToServer(player, LSW.CMD_SEEN_SQUARES, { squares = batch })
            batch = {}
        end
    end
    if #batch > 0 then
        LSW.ToServer(player, LSW.CMD_SEEN_SQUARES, { squares = batch })
    end
end

local function sentState(playerNum)
    local state = floorSent[playerNum]
    if not state then
        state = {}
        floorSent[playerNum] = state
    end
    return state
end

function Watch.SeeSquares(player, squares, close)
    if floorRuleOff() then
        return
    end
    local sent = sentState(player:getPlayerNum())
    local changed = {}
    for _, square in ipairs(squares) do
        local key = LSW.SquareKey(square:getX(), square:getY(), square:getZ())
        local sig = squareSignature(square)
        local previous = sent[key]
        if not previous or previous.sig ~= sig or (close and not previous.close) then
            sent[key] = { sig = sig, close = close }
            changed[#changed + 1] = { x = square:getX(), y = square:getY(), z = square:getZ(), near = close }
        end
    end
    if #changed > 0 then
        sendSquares(player, changed)
    end
end

local function reachableFloorSquares(player)
    local squares = {}
    local current = player:getCurrentSquare()
    if not current then
        return squares
    end
    local cell = getCell()
    for dx = -1, 1 do
        for dy = -1, 1 do
            local square = cell:getGridSquare(current:getX() + dx, current:getY() + dy, current:getZ())
            if square and (square == current or current:canReachTo(square)) then
                squares[#squares + 1] = square
            end
        end
    end
    return squares
end

local function reportContainer(player, container)
    if container == ISInventoryPage.GetFloorContainer(player:getPlayerNum()) then
        Watch.SeeSquares(player, reachableFloorSquares(player), true)
        return
    end
    local locator = Watch.Locate(player, container)
    if locator then
        LSW.ToServer(player, LSW.CMD_SEEN_CONTAINER, locator)
    end
end

local function watchPage(page)
    if page.onCharacter then
        return
    end
    local player = getSpecificPlayer(page.player)
    if not player or player:isDead() then
        return
    end
    local open = page:isReallyVisible() and not page.isCollapsed
    local pane = page.inventoryPane
    local container = open and pane and pane.inventory or nil
    local state = pages[page.player]
    if not state then
        state = {}
        pages[page.player] = state
    end
    if not container then
        state.container = nil
        state.sig = nil
        state.dueMs = nil
        return
    end
    local sig = signature(container)
    local now = getTimestampMs()
    if state.container ~= container or state.sig ~= sig then
        state.container = container
        state.sig = sig
        state.dueMs = now + Watch.CONTAINER_DELAY_MS
    end
    if state.dueMs and now >= state.dueMs then
        state.dueMs = nil
        reportContainer(player, container)
    end
end

local vanillaUpdate = ISInventoryPage.update

function ISInventoryPage:update(...)
    local result = vanillaUpdate(self, ...)
    watchPage(self)
    return result
end

local function isDark(square, playerNum)
    return square:getLightLevel(playerNum) < Watch.DARK
end

local function sweep(player)
    if LSW.GetFloorRule() ~= LSW.FLOOR_IN_SIGHT then
        return
    end
    local playerNum = player:getPlayerNum()
    local sent = sentState(playerNum)
    local cell = getCell()
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local radius = Watch.SWEEP_RADIUS
    local far = {}
    local close = {}
    for x = px - radius, px + radius do
        for y = py - radius, py + radius do
            Jobs.Step()
            local square = cell:getGridSquare(x, y, pz)
            if square and square:isCanSee(playerNum) then
                local hasItems = square:getWorldObjects():size() > 0
                if hasItems or sent[LSW.SquareKey(x, y, pz)] then
                    local within = math.abs(x - px) <= 1 and math.abs(y - py) <= 1
                    if within then
                        close[#close + 1] = square
                    elseif not isDark(square, playerNum) then
                        far[#far + 1] = square
                    end
                end
            end
        end
    end
    Watch.SeeSquares(player, close, true)
    Watch.SeeSquares(player, far, false)
end

local function onTick()
    local now = getTimestampMs()
    if now - lastSweepMs < Watch.SWEEP_MS then
        return
    end
    lastSweepMs = now
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        local name = "watch:sweep:" .. string.format("%d", i)
        if player and not player:isDead() and not Jobs.IsRunning(name) then
            Jobs.Start(name, function()
                if not player:isDead() then
                    sweep(player)
                end
            end)
        end
    end
end

if ISSearchManager and ISSearchManager.createIconsForWorldItems then
    local vanillaCreateIcons = ISSearchManager.createIconsForWorldItems
    function ISSearchManager:createIconsForWorldItems(square, ...)
        local result = vanillaCreateIcons(self, square, ...)
        if square and self.character and self.character:isLocalPlayer()
            and LSW.GetFloorRule() == LSW.FLOOR_IN_SIGHT then
            Watch.SeeSquares(self.character, { square }, true)
        end
        return result
    end
end

local function onGameStart()
    pages = {}
    floorSent = {}
end

local function onPlayerDeath(player)
    if player:isLocalPlayer() then
        floorSent[player:getPlayerNum()] = nil
        pages[player:getPlayerNum()] = nil
    end
end

Events.OnTick.Add(onTick)
Events.OnGameStart.Add(onGameStart)
Events.OnPlayerDeath.Add(onPlayerDeath)
