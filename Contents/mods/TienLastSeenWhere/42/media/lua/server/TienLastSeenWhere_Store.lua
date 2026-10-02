if isClient() then return end

require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Jobs"

local LSW = TienLastSeenWhere
local Jobs = LSW.Jobs

LSW.Store = {}

local Store = LSW.Store

Store.FOLDER = "TienLastSeenWhere"
Store.WORLD_KEY = "_world"
Store.VERSION = "2"
Store.SAVE_INTERVAL_MS = 30000
Store.IDLE_UNLOAD_MS = 300000

Store.clearListeners = {}

local records = {}
local lastSaveMs = 0
local openWriter = nil

local function sanitize(text)
    return (string.gsub(tostring(text), "[^%w%-_]", "_"))
end

local function worldFolder()
    return Store.FOLDER .. "/" .. sanitize(getWorld():getWorld())
end

local function fileName(key)
    return worldFolder() .. "/" .. sanitize(key) .. ".txt"
end

local function field(value)
    if value == nil or value == "" then
        return "-"
    end
    return tostring(value)
end

local function unfield(value)
    if value == "-" then
        return nil
    end
    return value
end

local function encodeItems(items)
    local parts = {}
    for fullType, count in pairs(items) do
        parts[#parts + 1] = fullType .. "=" .. string.format("%d", count)
    end
    if #parts == 0 then
        return "-"
    end
    return table.concat(parts, ";")
end

local function decodeItems(text)
    local items = {}
    if text == nil or text == "-" then
        return items
    end
    for fullType, count in string.gmatch(text, "([^;=]+)=(%d+)") do
        items[fullType] = tonumber(count)
    end
    return items
end

local function encodeParents(parents)
    if not parents or #parents == 0 then
        return "-"
    end
    return table.concat(parents, "|")
end

local function decodeParents(text)
    if text == nil or text == "-" then
        return nil
    end
    local parents = {}
    for key in string.gmatch(text, "[^|]+") do
        parents[#parents + 1] = key
    end
    return parents
end

local function encodeIds(ids)
    if not ids then
        return "-"
    end
    local parts = {}
    for fullType, list in pairs(ids) do
        local numbers = {}
        for i, id in ipairs(list) do
            numbers[i] = string.format("%d", id)
        end
        parts[#parts + 1] = fullType .. "=" .. table.concat(numbers, ",")
    end
    if #parts == 0 then
        return "-"
    end
    return table.concat(parts, ";")
end

local function decodeIds(text)
    if text == nil or text == "-" then
        return nil
    end
    local ids = {}
    for fullType, numbers in string.gmatch(text, "([^;=]+)=([^;]+)") do
        local list = {}
        for id in string.gmatch(numbers, "%-?%d+") do
            list[#list + 1] = tonumber(id)
        end
        ids[fullType] = list
    end
    return ids
end

function Store.Folder()
    return worldFolder()
end

Store.Field = field
Store.Unfield = unfield

local function encodePlace(place)
    return table.concat({
        "P",
        place.key,
        place.kind,
        string.format("%d", place.x),
        string.format("%d", place.y),
        string.format("%d", place.z),
        field(place.type),
        field(place.room),
        field(place.building),
        string.format("%.3f", place.t),
        encodeItems(place.items),
        encodeParents(place.parents),
        encodeIds(place.ids),
        field(place.by),
        place.touch and string.format("%.3f", place.touch) or "-",
    }, "\t")
end

local PLACE_PATTERN = "^P\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$"
local PLACE_PATTERN_V1 = "^P\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$"

local function decodePlace(line)
    local key, kind, x, y, z, placeType, room, building, t, items, parents, ids, by, touch =
        string.match(line, PLACE_PATTERN)
    if not key then
        key, kind, x, y, z, placeType, room, building, t, items = string.match(line, PLACE_PATTERN_V1)
        if not key then
            return nil
        end
    end
    return {
        key = key,
        kind = kind,
        x = tonumber(x),
        y = tonumber(y),
        z = tonumber(z),
        type = unfield(placeType),
        room = unfield(room),
        building = unfield(building),
        t = tonumber(t) or 0,
        items = decodeItems(items),
        parents = decodeParents(parents),
        ids = decodeIds(ids),
        by = unfield(by),
        touch = tonumber(touch),
    }
end

local function newRecord(key)
    return {
        key = key,
        hours = 0,
        places = {},
        order = {},
        bySquare = {},
        version = 0,
        dirty = false,
        usedMs = getTimestampMs(),
    }
end

local function squareOf(place)
    return LSW.SquareKey(place.x, place.y, place.z)
end

local function index(record, place)
    local square = squareOf(place)
    local keys = record.bySquare[square]
    if not keys then
        keys = {}
        record.bySquare[square] = keys
    end
    keys[place.key] = true
end

local function unindex(record, place)
    local square = squareOf(place)
    local keys = record.bySquare[square]
    if keys then
        keys[place.key] = nil
        for _ in pairs(keys) do
            return
        end
        record.bySquare[square] = nil
    end
end

local function drop(record, key)
    local place = record.places[key]
    if place then
        unindex(record, place)
        record.places[key] = nil
    end
end

local function loadJobName(key)
    return "store:load:" .. tostring(key)
end

local function stopLoading(record)
    if not record.loading then
        return
    end
    record.loading = false
    record.removed = nil
    Jobs.Cancel(loadJobName(record.key))
    if record.reader then
        record.reader:close()
        record.reader = nil
    end
end

local function clear(record)
    if record.key ~= Store.WORLD_KEY then
        for _, listener in ipairs(Store.clearListeners) do
            listener(record.key)
        end
    end
    stopLoading(record)
    record.places = {}
    record.order = {}
    record.bySquare = {}
    record.version = record.version + 1
    record.dirty = true
end

local function list(record, key)
    if record.places[key] == nil then
        record.order[#record.order + 1] = key
    end
end

local function addLoaded(record, line)
    if string.sub(line, 1, 1) ~= "P" then
        return
    end
    local place = decodePlace(line)
    if place and place.x and place.y and place.z and record.places[place.key] == nil
        and not (record.removed and record.removed[place.key]) then
        if not place.by and record.key ~= Store.WORLD_KEY then
            place.by = record.key
        end
        list(record, place.key)
        record.places[place.key] = place
        index(record, place)
    end
end

local forgetOld

local function readRest(record)
    local reader = record.reader
    local line = reader:readLine()
    while line and record.loading do
        addLoaded(record, line)
        Jobs.Step()
        line = reader:readLine()
    end
    if not record.loading then
        return
    end
    reader:close()
    record.reader = nil
    record.loading = false
    record.removed = nil
    record.version = record.version + 1
    forgetOld(record)
end

local function load(key)
    local record = newRecord(key)
    local reader = getFileReader(fileName(key), false)
    if not reader then
        return record
    end
    local header = reader:readLine()
    if not header then
        reader:close()
        return record
    end
    local parts = LSW.Split(header, "\t")
    if parts[1] == "V" then
        record.hours = tonumber(parts[3]) or 0
        record.name = unfield(parts[4])
    else
        addLoaded(record, header)
    end
    record.loading = true
    record.removed = {}
    record.reader = reader
    Jobs.Start(loadJobName(key), function()
        readRest(record)
    end)
    return record
end

local function writeHeader(writer, record)
    writer:writeln(table.concat({ "V", Store.VERSION, string.format("%.3f", record.hours), field(record.name) }, "\t"))
end

local function lastSeen(place)
    return math.max(place.t or 0, place.touch or 0)
end

local function save(record)
    local writer = getFileWriter(fileName(record.key), true, false)
    if not writer then
        return
    end
    openWriter = writer
    record.dirty = false
    writeHeader(writer, record)
    local source = record.order
    local oldest = LSW.GetForgetAfterDays() > 0 and LSW.Now() - LSW.GetForgetAfterDays() * 24 or nil
    local order = {}
    local listed = {}
    local i = 1
    while i <= #source do
        local key = source[i]
        local place = record.places[key]
        if place and oldest and lastSeen(place) < oldest then
            drop(record, key)
            record.version = record.version + 1
            place = nil
        end
        if place and not listed[key] then
            listed[key] = true
            order[#order + 1] = key
            writer:writeln(encodePlace(place))
        end
        i = i + 1
        Jobs.Step()
    end
    writer:close()
    openWriter = nil
    if record.order == source then
        record.order = order
    end
end

forgetOld = function(record)
    local days = LSW.GetForgetAfterDays()
    if days <= 0 then
        return
    end
    local oldest = LSW.Now() - days * 24
    for key, place in pairs(record.places) do
        if lastSeen(place) < oldest then
            drop(record, key)
            record.version = record.version + 1
            record.dirty = true
        end
    end
end

function Store.Get(key)
    local record = records[key]
    if not record then
        record = load(key)
        records[key] = record
        if not record.loading then
            forgetOld(record)
        end
    end
    record.usedMs = getTimestampMs()
    return record
end

function Store.KeyOf(player)
    return player:getUsername()
end

function Store.ForPlayer(player)
    local record = Store.Get(Store.KeyOf(player))
    local hours = player:getHoursSurvived()
    if hours + 1 < record.hours then
        clear(record)
    end
    if hours > record.hours then
        record.hours = hours
    end
    local descriptor = player:getDescriptor()
    if descriptor then
        local name = descriptor:getForename() .. " " .. descriptor:getSurname()
        if name ~= record.name then
            record.name = name
            record.dirty = true
        end
    end
    return record
end

function Store.World()
    return Store.Get(Store.WORLD_KEY)
end

function Store.Reset(key)
    local record = Store.Get(key)
    clear(record)
    record.hours = 0
end

function Store.WaitLoaded(record)
    Jobs.WaitWhile(function()
        return record.loading
    end)
end

function Store.IsLoading(record)
    return record.loading == true
end

function Store.Put(record, place)
    list(record, place.key)
    drop(record, place.key)
    record.places[place.key] = place
    index(record, place)
    record.version = record.version + 1
    record.dirty = true
end

function Store.KeysAt(record, x, y, z)
    return record.bySquare[LSW.SquareKey(x, y, z)]
end

function Store.Touch(record, key)
    local place = record.places[key]
    if place then
        place.touch = LSW.Now()
        record.dirty = true
    end
end

function Store.NameOf(username)
    if LSW.GetFoundByName() ~= LSW.NAME_CHARACTER or not username then
        return username
    end
    return Store.Get(username).name or username
end

function Store.Order(record)
    return record.order
end

function Store.Remove(record, key)
    if record.loading then
        record.removed[key] = true
    end
    if record.places[key] then
        drop(record, key)
        record.version = record.version + 1
        record.dirty = true
    end
end

local function saveAll(force)
    local now = getTimestampMs()
    local keys = {}
    for key in pairs(records) do
        keys[#keys + 1] = key
    end
    for _, key in ipairs(keys) do
        local record = records[key]
        if record and force and record.loading then
            Jobs.Finish(loadJobName(key))
        end
        if record and not record.loading then
            if record.dirty then
                save(record)
            end
            if key ~= Store.WORLD_KEY and now - record.usedMs > Store.IDLE_UNLOAD_MS and not record.dirty then
                records[key] = nil
            end
        end
    end
end

function Store.SaveAll(force)
    local now = getTimestampMs()
    if force then
        Jobs.Cancel("store:save")
        if openWriter then
            openWriter:close()
            openWriter = nil
        end
        lastSaveMs = now
        saveAll(true)
        return
    end
    if now - lastSaveMs < Store.SAVE_INTERVAL_MS or Jobs.IsRunning("store:save") then
        return
    end
    lastSaveMs = now
    Jobs.Start("store:save", saveAll)
end

local function onCharacterDeath(character)
    if instanceof(character, "IsoPlayer") and not character:isAnimal() then
        Store.Reset(Store.KeyOf(character))
    end
end

local function onEveryOneMinute()
    Store.SaveAll(false)
end

local function onSave()
    Store.SaveAll(true)
end

local function onGameStart()
    for _, record in pairs(records) do
        stopLoading(record)
    end
    records = {}
end

Events.OnCharacterDeath.Add(onCharacterDeath)
Events.EveryOneMinute.Add(onEveryOneMinute)
Events.OnSave.Add(onSave)
Events.OnGameStart.Add(onGameStart)
