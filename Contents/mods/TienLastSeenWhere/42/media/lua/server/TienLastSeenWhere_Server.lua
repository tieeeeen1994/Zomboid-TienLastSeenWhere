if isClient() then return end

require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Store"
require "TienLastSeenWhere_Privacy"
require "TienLastSeenWhere_Jobs"

local LSW = TienLastSeenWhere
local Store = LSW.Store
local Privacy = LSW.Privacy
local Jobs = LSW.Jobs

LSW.Server = {}

local Server = LSW.Server

Server.CONTAINER_REACH = 10
Server.FLOOR_REACH = 45
Server.MAX_SQUARES = 300
Server.FLUSH_MS = 300
Server.TYPES_PER_MESSAGE = 8
Server.INGEST_LIMIT = 4000
Server.SUMMARY_CACHE_MS = 10000
Server.FIND_GAP_MS = 250
Server.BUSY_AFTER_MS = 3000
Server.GONE_CHECK_MS = 2000
Server.GONE_REACH = 1
Server.GONE_STILL_MS = 10000
Server.PLACES_LIMIT = 300
Server.PLACES_PER_MESSAGE = 100
Server.MARK_KEY_LENGTH = 300

local ingest = {}
local ingestHead = 1
local ingestDropped = 0
local summaryRuns = {}
local summaryCache = {}
local findPending = {}
local lastFindMs = {}
local lastGoneCheckMs = 0
local goneChecked = {}

function Server.IsBusy()
    return Jobs.IsStrained() or Jobs.Stats().oldestMs > Server.BUSY_AFTER_MS
end

local function near(player, x, y, reach)
    return math.abs(player:getX() - x) <= reach and math.abs(player:getY() - y) <= reach
end

local function noteMarked(ids, item, fullType)
    if not Privacy.IsItemMarked(item:getID()) then
        return ids
    end
    ids = ids or {}
    local list = ids[fullType]
    if not list then
        list = {}
        ids[fullType] = list
    end
    list[#list + 1] = item:getID()
    return ids
end

local function countItems(container)
    local items = {}
    local ids = nil
    local list = container:getItems()
    for i = 0, list:size() - 1 do
        local item = list:get(i)
        local fullType = item:getFullType()
        items[fullType] = (items[fullType] or 0) + 1
        ids = noteMarked(ids, item, fullType)
    end
    return items, ids
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

local function bodyKey(x, y, z, body, index)
    local id = LSW.BodyId(body)
    if id then
        return "d:" .. LSW.SquareKey(x, y, z) .. ":#" .. string.format("%d", id)
    end
    return "d:" .. LSW.SquareKey(x, y, z) .. ":" .. string.format("%d", index)
end

local function bagKey(item)
    return "b:" .. string.format("%d", item:getID())
end

local function floorKey(x, y, z)
    return "f:" .. LSW.SquareKey(x, y, z)
end

local function place(key, kind, square, x, y, z, placeType, items, ids)
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
        ids = ids,
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
    local parents = nil
    if parent.kind == LSW.KIND_FLOOR then
        square = getCell():getGridSquare(tonumber(parent.x), tonumber(parent.y), tonumber(parent.z))
        item = square and findItemOnSquare(square, id)
        if square then
            parents = { floorKey(square:getX(), square:getY(), square:getZ()) }
        end
    else
        local resolved = resolve(player, parent)
        if resolved then
            item = resolved.container:getItemWithID(id)
            square = resolved.square
            parents = { resolved.key }
            for _, key in ipairs(resolved.parents or {}) do
                parents[#parents + 1] = key
            end
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
        parents = parents,
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
        local body = nil
        local id = tonumber(args.bodyId)
        if id then
            body = LSW.FindBody(square, ":#" .. string.format("%d", id))
        end
        if not body then
            body = findBody(square, index)
        end
        local container = body and body:getContainer()
        if not container then
            return nil
        end
        return {
            container = container,
            square = square,
            key = bodyKey(x, y, z, body, index),
            kind = kind,
            type = "corpse",
        }
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
    entry.by = Store.KeyOf(player)
    Privacy.NoteSighting(player, entry)
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
    local items, ids = countItems(resolved.container)
    if isEmpty(items) then
        forgetPlace(player, resolved.key)
        return
    end
    local entry = place(resolved.key, resolved.kind, square, square:getX(), square:getY(), square:getZ(),
        resolved.type, items, ids)
    entry.parents = resolved.parents
    remember(player, entry)
end

local function floorItems(square)
    local items = {}
    local small = {}
    local ids = nil
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
            ids = noteMarked(ids, item, fullType)
        end
    end
    return items, small, ids
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
    local items, small, ids = floorItems(square)
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
                if previous.ids and previous.ids[fullType] then
                    ids = ids or {}
                    ids[fullType] = previous.ids[fullType]
                end
            end
        end
        if ids then
            for fullType in pairs(ids) do
                if items[fullType] == nil then
                    ids[fullType] = nil
                end
            end
        end
    end
    if isEmpty(items) then
        forgetPlace(player, key)
        return
    end
    remember(player, place(key, LSW.KIND_FLOOR, square, x, y, z, nil, items, ids))
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

local function objectKeysOn(square)
    local keys = {}
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        for c = 0, object:getContainerCount() - 1 do
            keys[objectKey(x, y, z, spriteName(object), object:getContainerByIndex(c):getType())] = true
        end
    end
    return keys
end

local function bagOnSquare(square, id)
    local worldObjects = square:getWorldObjects()
    for i = 0, worldObjects:size() - 1 do
        local item = worldObjects:get(i):getItem()
        if item then
            if item:getID() == id then
                return true
            end
            if instanceof(item, "InventoryContainer") and item:getInventory():getItemWithIDRecursiv(id) then
                return true
            end
        end
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        for c = 0, object:getContainerCount() - 1 do
            if object:getContainerByIndex(c):getItemWithIDRecursiv(id) then
                return true
            end
        end
    end
    local bodies = square:getDeadBodys()
    for i = 0, bodies:size() - 1 do
        local container = bodies:get(i):getContainer()
        if container and container:getItemWithIDRecursiv(id) then
            return true
        end
    end
    return false
end

local function isGone(square, entry, objectKeys)
    local kind = entry.kind
    if kind == LSW.KIND_OBJECT then
        return not objectKeys()[entry.key]
    end
    if kind == LSW.KIND_BODY then
        return LSW.FindBody(square, entry.key) == nil
    end
    if kind == LSW.KIND_FLOOR then
        return square:getWorldObjects():size() == 0
    end
    if kind == LSW.KIND_BAG then
        local parents = entry.parents
        local top = parents and parents[#parents]
        local via = top and string.sub(top, 1, 1)
        if via ~= LSW.KIND_FLOOR and via ~= LSW.KIND_OBJECT and via ~= LSW.KIND_BODY then
            return false
        end
        local id = tonumber(string.match(entry.key, "^b:(%-?%d+)$"))
        return id ~= nil and not bagOnSquare(square, id)
    end
    return false
end

local function forgetGoneOn(record, square, objectKeys, touch)
    local keys = Store.KeysAt(record, square:getX(), square:getY(), square:getZ())
    if not keys then
        return
    end
    local gone = {}
    local still = {}
    for key in pairs(keys) do
        local entry = record.places[key]
        if entry and isGone(square, entry, objectKeys) then
            gone[#gone + 1] = key
        elseif entry and touch and entry.kind ~= LSW.KIND_FLOOR then
            still[#still + 1] = key
        end
    end
    for _, key in ipairs(gone) do
        Store.Remove(record, key)
    end
    for _, key in ipairs(still) do
        Store.Touch(record, key)
    end
end

local function checkGone(player, now)
    local current = player:getCurrentSquare()
    if not current then
        return
    end
    local who = Store.KeyOf(player)
    local spot = LSW.SquareKey(current:getX(), current:getY(), current:getZ())
    local last = goneChecked[who]
    if last and last.spot == spot and now - last.ms < Server.GONE_STILL_MS then
        return
    end
    goneChecked[who] = { spot = spot, ms = now }
    local mine = Store.ForPlayer(player)
    local world = Store.World()
    local cell = getCell()
    local reach = Server.GONE_REACH
    local touch = LSW.GetMemoryRefresh() == LSW.REFRESH_NEARBY and LSW.GetForgetAfterDays() > 0
    local z = current:getZ()
    for x = current:getX() - reach, current:getX() + reach do
        for y = current:getY() - reach, current:getY() + reach do
            Jobs.Step()
            local square = cell:getGridSquare(x, y, z)
            if square then
                local cached = nil
                local function objectKeys()
                    if not cached then
                        cached = objectKeysOn(square)
                    end
                    return cached
                end
                if not Store.IsLoading(mine) then
                    forgetGoneOn(mine, square, objectKeys, touch)
                end
                if not Store.IsLoading(world) then
                    forgetGoneOn(world, square, objectKeys)
                end
                local marked = Privacy.PlaceKeysAt(x, y, z)
                if marked then
                    local gone = {}
                    for key in pairs(marked) do
                        if not objectKeys()[key] then
                            gone[#gone + 1] = key
                        end
                    end
                    for _, key in ipairs(gone) do
                        Privacy.ForgetPlace(key)
                    end
                end
            end
        end
    end
end

local function playersHere()
    local players = {}
    if isServer() then
        local online = getOnlinePlayers()
        for i = 0, online:size() - 1 do
            players[#players + 1] = online:get(i)
        end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(i)
            if player then
                players[#players + 1] = player
            end
        end
    end
    return players
end

local function recordSource(record, own)
    Store.WaitLoaded(record)
    return { places = record.places, order = record.order, own = own }
end

local function sources(player, rule)
    local list = {}
    local mine = Store.KeyOf(player)
    if rule == LSW.RULE_SHARED and isServer() then
        list[#list + 1] = recordSource(Store.ForPlayer(player), true)
        for username in pairs(Privacy.SharedUsernames(player:getUsername())) do
            if username ~= mine then
                local source = recordSource(Store.Get(username), false)
                source.author = username
                list[#list + 1] = source
            end
        end
        return list
    end
    if rule == LSW.RULE_EXPLORED then
        list[#list + 1] = recordSource(Store.ForPlayer(player), true)
        local world = recordSource(Store.World(), false)
        world.world = true
        list[#list + 1] = world
        return list
    end
    list[#list + 1] = recordSource(Store.ForPlayer(player), true)
    return list
end

local function eachPlace(list, viewer, fn)
    local ownPlaces = {}
    for _, source in ipairs(list) do
        if source.own then
            ownPlaces = source.places
        end
    end
    local function visit(source, entry)
        if source.own or not viewer then
            fn(entry, entry.items)
            return
        end
        local author = source.author
        if source.world then
            author = entry.by
        end
        local floors = {}
        local own = ownPlaces[entry.key]
        if own then
            floors[#floors + 1] = own.items
        end
        local items = viewer:visibleItems(entry, author, floors)
        if items then
            fn(entry, items)
        end
    end
    for _, source in ipairs(list) do
        if source.order then
            local order = source.order
            local i = 1
            while i <= #order do
                local entry = source.places[order[i]]
                if entry then
                    visit(source, entry)
                end
                i = i + 1
                Jobs.Step()
            end
        else
            for _, entry in pairs(source.places) do
                visit(source, entry)
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

local function summaryTotals(player, rule, seeAll)
    local totals = {}
    local chosen = {}
    eachPlace(sources(player, rule), Privacy.Viewer(player, seeAll), function(entry, items)
        local current = chosen[entry.key]
        if current and current.t >= entry.t then
            return
        end
        if current then
            for fullType, count in pairs(current.items) do
                totals[fullType] = totals[fullType] - count
                if totals[fullType] <= 0 then
                    totals[fullType] = nil
                end
            end
        end
        chosen[entry.key] = { t = entry.t, items = items }
        for fullType, count in pairs(items) do
            totals[fullType] = (totals[fullType] or 0) + count
        end
    end)
    return totals
end

local function summaryVersion(player, rule)
    if rule == LSW.RULE_SHARED and isServer() then
        local parts = {}
        for username in pairs(Privacy.SharedUsernames(player:getUsername())) do
            parts[#parts + 1] = username .. "=" .. string.format("%d", Store.Get(username).version)
        end
        table.sort(parts)
        return table.concat(parts, ";")
    end
    if rule == LSW.RULE_EXPLORED then
        return string.format("%d;%d", Store.ForPlayer(player).version, Store.World().version)
    end
    return string.format("%d", Store.ForPlayer(player).version)
end

local function onSummary(player, args)
    local rule = LSW.ResolveRule(args.rule)
    local name = "summary:" .. player:getUsername() .. ":" .. tostring(args.playerNum)
    local version = summaryVersion(player, rule)
    local seeAll = args.seeAll == true
    local flags = (seeAll and "all:" or "") .. string.format("%d", Privacy.Version())
    local cached = summaryCache[name]
    if cached and cached.rule == rule and cached.flags == flags then
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
    if run and run.rule == rule and run.flags == flags and Jobs.IsRunning(name) then
        run.args = args
        return
    end
    run = { args = args, rule = rule, flags = flags }
    summaryRuns[name] = run
    Jobs.Start(name, function()
        local totals = summaryTotals(player, rule, seeAll)
        summaryCache[name] = { rule = rule, flags = flags, version = version, ms = getTimestampMs(), totals = totals }
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

local function finderOf(player)
    local name = Store.KeyOf(player)
    local group = isServer() and Privacy.SharedUsernames(player:getUsername()) or nil
    return function(result, entry, fullType)
        if LSW.IsPrivacyEnabled() and Privacy.OwnLevel(name, entry, fullType) then
            result.private = true
        end
        local by = entry.by
        if not by then
            return
        end
        if by == name then
            result.byMe = true
        elseif not group or group[by] then
            result.by = Store.NameOf(by)
        else
            result.bySomeone = true
        end
    end
end

local function nearest(player, found, vehicles, finder, fullType)
    local px, py = player:getX(), player:getY()
    local list = {}
    for _, hit in pairs(found) do
        local result = resultOf(hit.entry, hit.count, vehicles)
        finder(result, hit.entry, fullType)
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
    local finder = finderOf(player)

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
            results[fullType] = nearest(player, found[fullType], vehicles, finder, fullType)
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

    local chosen = {}
    eachPlace(sources(player, rule), Privacy.Viewer(player, args.seeAll == true), function(entry, items)
        local current = chosen[entry.key]
        if not current or entry.t > current.entry.t then
            if current then
                for fullType in pairs(current.items) do
                    local hits = found[fullType]
                    if hits and hits[entry.key] then
                        hits[entry.key] = nil
                        changed[fullType] = true
                    end
                end
            end
            chosen[entry.key] = { entry = entry, items = items }
            for fullType, n in pairs(items) do
                local hits = found[fullType]
                if hits then
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

local function markInfo(mark, record)
    local info = {
        kind = mark.kind,
        id = mark.id,
        level = mark.level,
        placeKind = mark.placeKind,
        x = mark.x,
        y = mark.y,
        z = mark.z,
        type = mark.type,
        room = mark.room,
        fullType = mark.fullType,
        t = mark.t,
        exposed = mark.exposedT,
        exposedBy = Store.NameOf(mark.exposedBy),
        fresh = mark.exposedT ~= nil and (mark.ackT == nil or mark.ackT < mark.exposedT),
    }
    local entry = mark.kind == LSW.MARK_PLACE and record and record.places[mark.id]
    if entry then
        info.x, info.y, info.z = entry.x, entry.y, entry.z
        info.room = entry.room
        info.seen = entry.t
    end
    return info
end

local function sendPrivacy(player, args, reason)
    local record = Store.ForPlayer(player)
    if Store.IsLoading(record) then
        record = nil
    end
    local marks = {}
    for _, mark in ipairs(Privacy.MarksOf(Store.KeyOf(player))) do
        marks[#marks + 1] = markInfo(mark, record)
    end
    LSW.ToClient(player, LSW.REPLY_PRIVACY, {
        request = args.request,
        playerNum = args.playerNum,
        enabled = LSW.IsPrivacyEnabled(),
        group = isServer(),
        canSeeAll = Privacy.CanSeeAll(player),
        marks = marks,
        reason = reason,
    })
end

local function onPrivacy(player, args)
    if args.ack == true then
        Privacy.Acknowledge(Store.KeyOf(player))
    end
    sendPrivacy(player, args, nil)
end

local function itemOnSquare(square, id)
    local worldObjects = square:getWorldObjects()
    for i = 0, worldObjects:size() - 1 do
        local item = worldObjects:get(i):getItem()
        if item then
            if item:getID() == id then
                return item
            end
            if instanceof(item, "InventoryContainer") then
                local inner = item:getInventory():getItemWithIDRecursiv(id)
                if inner then
                    return inner
                end
            end
        end
    end
    return nil
end

local function itemInReach(player, id, args)
    local item = player:getInventory():getItemWithIDRecursiv(id)
    if item then
        return item, nil
    end
    if type(args.locator) == "table" then
        local resolved = resolve(player, args.locator)
        local square = resolved and resolved.square
        if square and near(player, square:getX(), square:getY(), Server.CONTAINER_REACH) then
            item = resolved.container:getItemWithIDRecursiv(id)
            if item then
                return item, { locator = args.locator }
            end
        end
    end
    local current = player:getCurrentSquare()
    if not current then
        return nil, nil
    end
    local cell = getCell()
    for dx = -1, 1 do
        for dy = -1, 1 do
            local square = cell:getGridSquare(current:getX() + dx, current:getY() + dy, current:getZ())
            item = square and itemOnSquare(square, id)
            if item then
                return item, { square = square }
            end
        end
    end
    return nil, nil
end

local function placeMark(player, key, level)
    if type(key) ~= "string" or string.len(key) > Server.MARK_KEY_LENGTH then
        return "invalid"
    end
    local prefix = string.sub(key, 1, 2)
    if prefix ~= "o:" and prefix ~= "v:" and prefix ~= "b:" then
        return "invalid"
    end
    local owner = Store.KeyOf(player)
    if level == LSW.PRIVATE_NONE then
        Privacy.Set(owner, { kind = LSW.MARK_PLACE, id = key }, level)
        return nil
    end
    local record = Store.ForPlayer(player)
    if Store.IsLoading(record) then
        return "busy"
    end
    local entry = record.places[key]
    if not entry then
        return "unknown"
    end
    local ok, reason = Privacy.Set(owner, {
        kind = LSW.MARK_PLACE,
        id = key,
        placeKind = entry.kind,
        x = entry.x,
        y = entry.y,
        z = entry.z,
        type = entry.type,
        room = entry.room,
    }, level)
    return not ok and reason or nil
end

local function itemMark(player, args, level)
    local id = tonumber(args.id)
    if not id then
        return "invalid"
    end
    local owner = Store.KeyOf(player)
    if level == LSW.PRIVATE_NONE then
        Privacy.Set(owner, { kind = LSW.MARK_ITEM, id = string.format("%d", id) }, level)
        return nil
    end
    local item, where = itemInReach(player, id, args)
    if not item then
        return "unknown"
    end
    local square = player:getCurrentSquare()
    local ok, reason
    if instanceof(item, "InventoryContainer") then
        ok, reason = Privacy.Set(owner, {
            kind = LSW.MARK_PLACE,
            id = bagKey(item),
            placeKind = LSW.KIND_BAG,
            x = square and square:getX(),
            y = square and square:getY(),
            z = square and square:getZ(),
            type = item:getFullType(),
            room = LSW.RoomName(square),
        }, level)
    else
        ok, reason = Privacy.Set(owner, {
            kind = LSW.MARK_ITEM,
            id = string.format("%d", id),
            fullType = item:getFullType(),
        }, level)
    end
    if not ok then
        return reason
    end
    if where and where.locator then
        onSeenContainer(player, where.locator)
    elseif where and where.square and LSW.GetFloorRule() ~= LSW.FLOOR_OFF then
        local record = Store.ForPlayer(player)
        if not Store.IsLoading(record) then
            seeSquare(player, record, where.square:getX(), where.square:getY(), where.square:getZ(), true)
        end
    end
    return nil
end

local function onPrivacySet(player, args)
    if not LSW.IsPrivacyEnabled() then
        sendPrivacy(player, args, "off")
        return
    end
    local level = tonumber(args.level)
    if level ~= LSW.PRIVATE_NONE and level ~= LSW.PRIVATE_ME and level ~= LSW.PRIVATE_GROUP then
        sendPrivacy(player, args, "invalid")
        return
    end
    if level == LSW.PRIVATE_GROUP and not isServer() then
        level = LSW.PRIVATE_ME
    end
    local reason
    if args.kind == LSW.MARK_PLACE then
        reason = placeMark(player, args.key, level)
    elseif args.kind == LSW.MARK_ITEM then
        reason = itemMark(player, args, level)
    else
        reason = "invalid"
    end
    sendPrivacy(player, args, reason)
end

local function onPlaces(player, args)
    local name = "places:" .. player:getUsername() .. ":" .. tostring(args.playerNum)
    Jobs.Start(name, function()
        local record = Store.ForPlayer(player)
        Store.WaitLoaded(record)
        local vehicles = vehiclesBySqlId()
        local px, py = player:getX(), player:getY()
        local list = {}
        local order = record.order
        local listed = {}
        local i = 1
        while i <= #order do
            local key = order[i]
            local entry = record.places[key]
            if entry and not listed[key] and (entry.kind == LSW.KIND_OBJECT or entry.kind == LSW.KIND_VEHICLE
                or entry.kind == LSW.KIND_BAG) then
                listed[key] = true
                local result = resultOf(entry, nil, vehicles)
                result.d = LSW.DistanceTo(px, py, result.x + 0.5, result.y + 0.5)
                list[#list + 1] = result
            end
            i = i + 1
            Jobs.Step()
        end
        table.sort(list, function(a, b) return a.d < b.d end)
        local chunk = {}
        local part = 0
        local total = math.min(#list, Server.PLACES_LIMIT)
        for n = 1, total do
            chunk[#chunk + 1] = list[n]
            if #chunk >= Server.PLACES_PER_MESSAGE or n == total then
                part = part + 1
                LSW.ToClient(player, LSW.REPLY_PLACES, {
                    request = args.request, playerNum = args.playerNum, part = part, last = n == total, places = chunk,
                })
                chunk = {}
            end
        end
        if total == 0 then
            LSW.ToClient(player, LSW.REPLY_PLACES, {
                request = args.request, playerNum = args.playerNum, part = 1, last = true, places = {},
            })
        end
    end)
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
    if now - lastGoneCheckMs >= Server.GONE_CHECK_MS and not Jobs.IsRunning("gone") then
        lastGoneCheckMs = now
        local players = playersHere()
        Jobs.Start("gone", function()
            for _, player in ipairs(players) do
                if not player:isDead() then
                    checkGone(player, now)
                end
            end
        end)
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
    for who, last in pairs(goneChecked) do
        if now - last.ms > Server.GONE_STILL_MS * 6 then
            goneChecked[who] = nil
        end
    end
end

local handlers = {
    [LSW.CMD_SEEN_CONTAINER] = queueIngest(onSeenContainer),
    [LSW.CMD_SEEN_SQUARES] = queueIngest(onSeenSquares),
    [LSW.CMD_SUMMARY] = onSummary,
    [LSW.CMD_FIND] = onFind,
    [LSW.CMD_PRIVACY] = onPrivacy,
    [LSW.CMD_PRIVACY_SET] = onPrivacySet,
    [LSW.CMD_PLACES] = onPlaces,
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
