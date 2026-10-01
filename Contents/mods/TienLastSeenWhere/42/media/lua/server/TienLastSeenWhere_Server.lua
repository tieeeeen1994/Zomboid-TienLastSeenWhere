if isClient() then return end

require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Store"
require "TienLastSeenWhere_Jobs"

local LSW = TienLastSeenWhere
local Store = LSW.Store
local Jobs = LSW.Jobs

LSW.Server = {}

local Server = LSW.Server

Server.CONTAINER_REACH = 10
Server.FLOOR_REACH = 45
Server.MAX_SQUARES = 300
Server.LIVE_CACHE_MS = 5000
Server.FLUSH_MS = 300
Server.TYPES_PER_MESSAGE = 8
Server.INGEST_LIMIT = 4000
Server.SUMMARY_CACHE_MS = 10000
Server.FIND_GAP_MS = 250
Server.BUSY_AFTER_MS = 3000

local liveCache = {}
local ingest = {}
local ingestHead = 1
local ingestDropped = 0
local summaryRuns = {}
local summaryCache = {}
local findPending = {}
local lastFindMs = {}

function Server.IsBusy()
    return Jobs.IsStrained() or Jobs.Stats().oldestMs > Server.BUSY_AFTER_MS
end

local function near(player, x, y, reach)
    return math.abs(player:getX() - x) <= reach and math.abs(player:getY() - y) <= reach
end

local function countItems(container)
    local items = {}
    local list = container:getItems()
    for i = 0, list:size() - 1 do
        local item = list:get(i)
        local fullType = item:getFullType()
        items[fullType] = (items[fullType] or 0) + 1
    end
    return items
end

local function isEmpty(items)
    for _ in pairs(items) do
        return false
    end
    return true
end

local function spriteName(object)
    local sprite = object and object:getSprite()
    return sprite and sprite:getName() or nil
end

local function objectKey(x, y, z, sprite, containerType)
    return "o:" .. LSW.SquareKey(x, y, z) .. ":" .. tostring(sprite) .. ":" .. tostring(containerType)
end

local function vehicleKey(vehicle, partId)
    return "v:" .. tostring(vehicle:getSqlId()) .. ":" .. tostring(partId)
end

local function bodyKey(x, y, z, index)
    return "d:" .. LSW.SquareKey(x, y, z) .. ":" .. string.format("%d", index)
end

local function bagKey(item)
    return "b:" .. string.format("%d", item:getID())
end

local function floorKey(x, y, z)
    return "f:" .. LSW.SquareKey(x, y, z)
end

local function place(key, kind, square, x, y, z, placeType, items)
    return {
        key = key,
        kind = kind,
        x = x,
        y = y,
        z = z,
        type = placeType,
        room = LSW.RoomName(square),
        building = LSW.BuildingKey(square),
        t = LSW.Now(),
        items = items,
    }
end

local function findObjectContainer(square, args)
    local objects = square:getObjects()
    local index = tonumber(args.index)
    local containerType = args.containerType
    local candidates = {}
    if index and index >= 0 and index < objects:size() then
        candidates[1] = objects:get(index)
    end
    for i = 0, objects:size() - 1 do
        candidates[#candidates + 1] = objects:get(i)
    end
    for _, object in ipairs(candidates) do
        if not args.sprite or spriteName(object) == args.sprite then
            local container = containerType and object:getContainerByType(containerType)
            if not container then
                local ci = tonumber(args.containerIndex) or 0
                if ci >= 0 and ci < object:getContainerCount() then
                    container = object:getContainerByIndex(ci)
                end
            end
            if container and (not containerType or container:getType() == containerType) then
                return object, container
            end
        end
    end
    return nil, nil
end

local function findBody(square, index)
    local bodies = square:getDeadBodys()
    if not bodies or index < 0 or index >= bodies:size() then
        return nil
    end
    return bodies:get(index)
end

local function findItemOnSquare(square, id)
    local objects = square:getWorldObjects()
    for i = 0, objects:size() - 1 do
        local item = objects:get(i):getItem()
        if item and item:getID() == id then
            return item
        end
    end
    return nil
end

local resolve

local function resolveBag(player, args)
    local id = tonumber(args.id)
    if not id or type(args.parent) ~= "table" then
        return nil
    end
    local parent = args.parent
    local item = nil
    local square = nil
    if parent.kind == LSW.KIND_FLOOR then
        square = getCell():getGridSquare(tonumber(parent.x), tonumber(parent.y), tonumber(parent.z))
        item = square and findItemOnSquare(square, id)
    else
        local resolved = resolve(player, parent)
        if resolved then
            item = resolved.container:getItemWithID(id)
            square = resolved.square
        end
    end
    if not item or not square or not instanceof(item, "InventoryContainer") then
        return nil
    end
    return {
        container = item:getInventory(),
        square = square,
        key = bagKey(item),
        kind = LSW.KIND_BAG,
        type = item:getFullType(),
    }
end

resolve = function(player, args)
    local kind = args.kind
    if kind == LSW.KIND_BAG then
        return resolveBag(player, args)
    end
    if kind == LSW.KIND_VEHICLE then
        local vehicle = getVehicleById(tonumber(args.vehicle) or -1)
        local part = vehicle and vehicle:getPartById(tostring(args.part))
        local container = part and part:getItemContainer()
        if not container then
            return nil
        end
        return {
            container = container,
            square = vehicle:getSquare(),
            key = vehicleKey(vehicle, part:getId()),
            kind = kind,
            type = part:getId() .. "@" .. vehicle:getScript():getFullName(),
        }
    end
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not x or not y or not z then
        return nil
    end
    local square = getCell():getGridSquare(x, y, z)
    if not square then
        return nil
    end
    if kind == LSW.KIND_BODY then
        local index = tonumber(args.index) or -1
        local body = findBody(square, index)
        local container = body and body:getContainer()
        if not container then
            return nil
        end
        return { container = container, square = square, key = bodyKey(x, y, z, index), kind = kind, type = "corpse" }
    end
    if kind == LSW.KIND_OBJECT then
        local object, container = findObjectContainer(square, args)
        if not container then
            return nil
        end
        return {
            container = container,
            square = square,
            key = objectKey(x, y, z, spriteName(object), container:getType()),
            kind = kind,
            type = container:getType(),
        }
    end
    return nil
end

local function remember(player, entry)
    Store.Put(Store.ForPlayer(player), entry)
    Store.Put(Store.World(), entry)
end

local function forgetPlace(player, key)
    Store.Remove(Store.ForPlayer(player), key)
    Store.Remove(Store.World(), key)
end

local function onSeenContainer(player, args)
    local resolved = resolve(player, args)
    if not resolved or not resolved.square then
        return
    end
    local square = resolved.square
    if not near(player, square:getX(), square:getY(), Server.CONTAINER_REACH) then
        return
    end
    local items = countItems(resolved.container)
    if isEmpty(items) then
        forgetPlace(player, resolved.key)
        return
    end
    remember(player, place(resolved.key, resolved.kind, square, square:getX(), square:getY(), square:getZ(),
        resolved.type, items))
end

local function floorItems(square)
    local items = {}
    local small = {}
    local objects = square:getWorldObjects()
    for i = 0, objects:size() - 1 do
        local item = objects:get(i):getItem()
        if item then
            local fullType = item:getFullType()
            if item:getActualWeight() < LSW.SMALL_WEIGHT then
                small[fullType] = (small[fullType] or 0) + 1
            else
                items[fullType] = (items[fullType] or 0) + 1
            end
        end
    end
    return items, small
end

local function isSmallType(fullType)
    local script = getScriptManager():getItem(fullType)
    return script ~= nil and script:getActualWeight() < LSW.SMALL_WEIGHT
end

local function seeSquare(player, record, x, y, z, close)
    local square = getCell():getGridSquare(x, y, z)
    if not square then
        return
    end
    local key = floorKey(x, y, z)
    local items, small = floorItems(square)
    local smallVisible = close or LSW.DistanceTo(player:getX(), player:getY(), x + 0.5, y + 0.5)
        <= LSW.GetSmallItemDistance()
    if smallVisible then
        for fullType, count in pairs(small) do
            items[fullType] = count
        end
    else
        local previous = record.places[key]
        for fullType, count in pairs(previous and previous.items or {}) do
            if items[fullType] == nil and isSmallType(fullType) then
                items[fullType] = count
            end
        end
    end
    if isEmpty(items) then
        forgetPlace(player, key)
        return
    end
    remember(player, place(key, LSW.KIND_FLOOR, square, x, y, z, nil, items))
end

local function onSeenSquares(player, args)
    if LSW.GetFloorRule() == LSW.FLOOR_OFF or type(args.squares) ~= "table" then
        return
    end
    local record = Store.ForPlayer(player)
    Store.WaitLoaded(record)
    local handled = 0
    for _, entry in pairs(args.squares) do
        if handled >= Server.MAX_SQUARES then
            break
        end
        local x, y, z = tonumber(entry.x), tonumber(entry.y), tonumber(entry.z)
        if x and y and z and near(player, x, y, Server.FLOOR_REACH) then
            handled = handled + 1
            seeSquare(player, record, math.floor(x), math.floor(y), math.floor(z), entry.near == true)
            Jobs.Step()
        end
    end
end

local function usernamesShared(username)
    local names = { [username] = true }
    local faction = Faction.getPlayerFaction(username)
    if faction then
        names[faction:getOwner()] = true
        local players = faction:getPlayers()
        for i = 0, players:size() - 1 do
            names[players:get(i)] = true
        end
    end
    local safehouses = SafeHouse.getSafehouseList()
    for i = 0, safehouses:size() - 1 do
        local safehouse = safehouses:get(i)
        local players = safehouse:getPlayers()
        if safehouse:getOwner() == username or players:contains(username) then
            names[safehouse:getOwner()] = true
            for j = 0, players:size() - 1 do
                names[players:get(j)] = true
            end
        end
    end
    return names
end

local function liveScan(player, everything)
    local cacheKey = player:getUsername() .. (everything and ":all" or ":explored")
    local cached = liveCache[cacheKey]
    local now = getTimestampMs()
    if cached and now - cached.ms < Server.LIVE_CACHE_MS then
        return cached.places
    end
    local places = {}
    local cell = getCell()
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local radius = LSW.LIVE_RADIUS
    for z = pz - LSW.LIVE_LEVELS, pz + LSW.LIVE_LEVELS do
        for x = px - radius, px + radius do
            for y = py - radius, py + radius do
                Jobs.Step()
                local square = cell:getGridSquare(x, y, z)
                if square then
                    local objects = square:getObjects()
                    for i = 0, objects:size() - 1 do
                        local object = objects:get(i)
                        for c = 0, object:getContainerCount() - 1 do
                            local container = object:getContainerByIndex(c)
                            if everything or container:isExplored() then
                                local items = countItems(container)
                                if not isEmpty(items) then
                                    local key = objectKey(x, y, z, spriteName(object), container:getType())
                                    places[key] = place(key, LSW.KIND_OBJECT, square, x, y, z, container:getType(), items)
                                end
                            end
                        end
                    end
                    if everything then
                        local items, small = floorItems(square)
                        for fullType, count in pairs(small) do
                            items[fullType] = count
                        end
                        if not isEmpty(items) then
                            local key = floorKey(x, y, z)
                            places[key] = place(key, LSW.KIND_FLOOR, square, x, y, z, nil, items)
                        end
                    end
                end
            end
        end
    end
    liveCache[cacheKey] = { ms = getTimestampMs(), places = places }
    return places
end

local function recordSource(record)
    Store.WaitLoaded(record)
    return { places = record.places, order = record.order }
end

local function sources(player, rule)
    local list = {}
    if rule == LSW.RULE_SHARED and isServer() then
        for username in pairs(usernamesShared(player:getUsername())) do
            list[#list + 1] = recordSource(Store.Get(username))
        end
        return list
    end
    if rule == LSW.RULE_EXPLORED or rule == LSW.RULE_EVERYTHING then
        list[#list + 1] = recordSource(Store.World())
        list[#list + 1] = { places = liveScan(player, rule == LSW.RULE_EVERYTHING) }
        return list
    end
    list[#list + 1] = recordSource(Store.ForPlayer(player))
    return list
end

local function eachPlace(list, fn)
    for _, source in ipairs(list) do
        if source.order then
            local order = source.order
            local i = 1
            while i <= #order do
                local entry = source.places[order[i]]
                if entry then
                    fn(entry)
                end
                i = i + 1
                Jobs.Step()
            end
        else
            for _, entry in pairs(source.places) do
                fn(entry)
                Jobs.Step()
            end
        end
    end
end

local function sendSummary(player, args, rule, totals)
    local chunk = {}
    local size = 0
    local part = 0
    local busy = Server.IsBusy()
    local function flush(last)
        part = part + 1
        LSW.ToClient(player, LSW.REPLY_SUMMARY, {
            request = args.request,
            playerNum = args.playerNum,
            part = part,
            last = last,
            rule = rule,
            busy = busy,
            types = chunk,
        })
        chunk = {}
        size = 0
    end
    for fullType, count in pairs(totals) do
        size = size + 1
        chunk[fullType] = count
        if size >= LSW.SUMMARY_CHUNK then
            flush(false)
        end
    end
    flush(true)
end

local function summaryTotals(player, rule)
    local totals = {}
    local seen = {}
    eachPlace(sources(player, rule), function(entry)
        if not seen[entry.key] then
            seen[entry.key] = true
            for fullType, count in pairs(entry.items) do
                totals[fullType] = (totals[fullType] or 0) + count
            end
        end
    end)
    return totals
end

local function summaryVersion(player, rule)
    if rule == LSW.RULE_SHARED and isServer() then
        local parts = {}
        for username in pairs(usernamesShared(player:getUsername())) do
            parts[#parts + 1] = username .. "=" .. string.format("%d", Store.Get(username).version)
        end
        table.sort(parts)
        return table.concat(parts, ";")
    end
    if rule == LSW.RULE_EXPLORED or rule == LSW.RULE_EVERYTHING then
        return nil
    end
    return string.format("%d", Store.ForPlayer(player).version)
end

local function onSummary(player, args)
    local rule = LSW.ResolveRule(args.rule)
    local name = "summary:" .. player:getUsername() .. ":" .. tostring(args.playerNum)
    local version = summaryVersion(player, rule)
    local cached = summaryCache[name]
    if cached and cached.rule == rule then
        local fresh
        if version then
            fresh = cached.version == version
        else
            fresh = getTimestampMs() - cached.ms < Server.SUMMARY_CACHE_MS
        end
        if fresh then
            sendSummary(player, args, rule, cached.totals)
            return
        end
    end
    local run = summaryRuns[name]
    if run and run.rule == rule and Jobs.IsRunning(name) then
        run.args = args
        return
    end
    run = { args = args, rule = rule }
    summaryRuns[name] = run
    Jobs.Start(name, function()
        local totals = summaryTotals(player, rule)
        summaryCache[name] = { rule = rule, version = version, ms = getTimestampMs(), totals = totals }
        summaryRuns[name] = nil
        sendSummary(player, run.args, rule, totals)
    end)
end

local function vehiclesBySqlId()
    local vehicles = {}
    local list = ArrayList.new()
    list:addAll(getCell():getVehicles())
    for i = 0, list:size() - 1 do
        local vehicle = list:get(i)
        vehicles[tostring(vehicle:getSqlId())] = vehicle
    end
    return vehicles
end

local function resultOf(entry, count, vehicles)
    local result = {
        key = entry.key,
        kind = entry.kind,
        x = entry.x,
        y = entry.y,
        z = entry.z,
        type = entry.type,
        room = entry.room,
        building = entry.building,
        t = entry.t,
        count = count,
    }
    if entry.kind == LSW.KIND_VEHICLE then
        local sqlId = string.match(entry.key, "^v:([^:]+):")
        local vehicle = sqlId and vehicles[sqlId]
        if vehicle then
            result.x = math.floor(vehicle:getX())
            result.y = math.floor(vehicle:getY())
            result.z = math.floor(vehicle:getZ())
            result.vehicle = vehicle:getId()
        end
    end
    return result
end

local function nearest(player, found, vehicles)
    local px, py = player:getX(), player:getY()
    local list = {}
    for _, hit in pairs(found) do
        local result = resultOf(hit.entry, hit.count, vehicles)
        result.d = LSW.DistanceTo(px, py, result.x + 0.5, result.y + 0.5)
        list[#list + 1] = result
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    local trimmed = {}
    for i = 1, math.min(#list, LSW.FIND_LIMIT) do
        trimmed[i] = list[i]
    end
    return trimmed
end

local function findJob(player, args, rule, wanted)
    local found = {}
    for fullType in pairs(wanted) do
        found[fullType] = {}
    end
    local changed = {}
    local part = 0
    local lastFlushMs = getTimestampMs()
    local vehicles = vehiclesBySqlId()

    local function send(types, last)
        local results = {}
        local count = 0
        local pending = {}
        for fullType in pairs(types) do
            pending[#pending + 1] = fullType
        end
        if #pending == 0 and last then
            part = part + 1
            LSW.ToClient(player, LSW.REPLY_FIND, {
                request = args.request, playerNum = args.playerNum, rule = rule, part = part, last = true,
                busy = Server.IsBusy(), results = {},
            })
            return
        end
        for i, fullType in ipairs(pending) do
            results[fullType] = nearest(player, found[fullType], vehicles)
            count = count + 1
            if count >= Server.TYPES_PER_MESSAGE or i == #pending then
                part = part + 1
                LSW.ToClient(player, LSW.REPLY_FIND, {
                    request = args.request,
                    playerNum = args.playerNum,
                    rule = rule,
                    part = part,
                    last = last and i == #pending,
                    busy = Server.IsBusy(),
                    results = results,
                })
                results = {}
                count = 0
            end
        end
    end

    eachPlace(sources(player, rule), function(entry)
        for fullType, n in pairs(entry.items) do
            local hits = found[fullType]
            if hits then
                local current = hits[entry.key]
                if not current or entry.t > current.entry.t then
                    hits[entry.key] = { entry = entry, count = n }
                    changed[fullType] = true
                end
            end
        end
        if getTimestampMs() - lastFlushMs >= Server.FLUSH_MS then
            lastFlushMs = getTimestampMs()
            send(changed, false)
            changed = {}
        end
    end)
    send(wanted, true)
end

local function startFind(name, player, args, rule, wanted)
    lastFindMs[name] = getTimestampMs()
    Jobs.Start(name, function()
        findJob(player, args, rule, wanted)
    end)
end

local function onFind(player, args)
    if type(args.types) ~= "table" then
        return
    end
    local rule = LSW.ResolveRule(args.rule)
    local wanted = {}
    local count = 0
    for _, fullType in pairs(args.types) do
        if type(fullType) == "string" and count < LSW.FIND_LIMIT then
            wanted[fullType] = true
            count = count + 1
        end
    end
    local name = "find:" .. player:getUsername() .. ":" .. tostring(args.playerNum)
    if getTimestampMs() - (lastFindMs[name] or 0) < Server.FIND_GAP_MS then
        Jobs.Cancel(name)
        findPending[name] = { player = player, args = args, rule = rule, wanted = wanted }
        return
    end
    findPending[name] = nil
    startFind(name, player, args, rule, wanted)
end

local function runIngest()
    while ingestHead <= #ingest do
        local entry = ingest[ingestHead]
        ingestHead = ingestHead + 1
        entry.handler(entry.player, entry.args)
        Jobs.Step()
    end
    ingest = {}
    ingestHead = 1
end

local function queueIngest(handler)
    return function(player, args)
        if #ingest - ingestHead + 1 >= Server.INGEST_LIMIT then
            ingestDropped = ingestDropped + 1
            return
        end
        ingest[#ingest + 1] = { handler = handler, player = player, args = args }
        if not Jobs.IsRunning("ingest") then
            Jobs.Start("ingest", runIngest)
        end
    end
end

local function onTick()
    local now = getTimestampMs()
    for name, pending in pairs(findPending) do
        if now - (lastFindMs[name] or 0) >= Server.FIND_GAP_MS then
            findPending[name] = nil
            startFind(name, pending.player, pending.args, pending.rule, pending.wanted)
        end
    end
end

local function onEveryTenMinutes()
    if ingestDropped > 0 then
        print("[TienLastSeenWhere] " .. string.format("%d", ingestDropped)
            .. " sightings dropped because the server was behind")
        ingestDropped = 0
    end
    local now = getTimestampMs()
    for name, cached in pairs(summaryCache) do
        if now - cached.ms > Server.SUMMARY_CACHE_MS * 6 then
            summaryCache[name] = nil
        end
    end
end

local handlers = {
    [LSW.CMD_SEEN_CONTAINER] = queueIngest(onSeenContainer),
    [LSW.CMD_SEEN_SQUARES] = queueIngest(onSeenSquares),
    [LSW.CMD_SUMMARY] = onSummary,
    [LSW.CMD_FIND] = onFind,
}

function Server.Handle(player, command, args)
    local handler = handlers[command]
    if handler and player and type(args) == "table" then
        handler(player, args)
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= LSW.MODULE then
        return
    end
    Server.Handle(player, command, args)
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(onTick)
Events.EveryTenMinutes.Add(onEveryTenMinutes)
