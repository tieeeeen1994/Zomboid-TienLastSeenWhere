if isClient() then return end

require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Jobs"

local LSW = TienLastSeenWhere
local Jobs = LSW.Jobs

LSW.Store = {}

local Store = LSW.Store

Store.FOLDER = "TienLastSeenWhere"
Store.WORLD_KEY = "_world"
Store.VERSION = "1"
Store.SAVE_INTERVAL_MS = 30000
Store.IDLE_UNLOAD_MS = 300000

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
    }, "\t")
end

local PLACE_PATTERN = "^P\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$"

local function decodePlace(line)
    local key, kind, x, y, z, placeType, room, building, t, items = string.match(line, PLACE_PATTERN)
    if not key then
        return nil
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
    }
end

local function newRecord(key)
    return { key = key, hours = 0, places = {}, order = {}, version = 0, dirty = false, usedMs = getTimestampMs() }
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
    stopLoading(record)
    record.places = {}
    record.order = {}
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
        list(record, place.key)
        record.places[place.key] = place
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
    writer:writeln(table.concat({ "V", Store.VERSION, string.format("%.3f", record.hours) }, "\t"))
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
        if place and oldest and place.t < oldest then
            record.places[key] = nil
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
        if place.t < oldest then
            record.places[key] = nil
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
    record.places[place.key] = place
    record.version = record.version + 1
    record.dirty = true
end

function Store.Order(record)
    return record.order
end

function Store.Remove(record, key)
    if record.loading then
        record.removed[key] = true
    end
    if record.places[key] then
        record.places[key] = nil
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
