if isClient() then return end

require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Store"
require "TienLastSeenWhere_Privacy"
require "TienLastSeenWhere_Jobs"
require "TienLastSeenWhere_Server"

local LSW = TienLastSeenWhere
local Store = LSW.Store
local Privacy = LSW.Privacy
local Server = LSW.Server
local Jobs = LSW.Jobs

LSW.Manage = {}

local Manage = LSW.Manage

Manage.USERS_LIMIT = 2000
Manage.USERS_PER_MESSAGE = 200
Manage.NAME_LENGTH = 64
Manage.TYPE_LENGTH = 200
Manage.FORGET_LIMIT = 400

local runs = 0

function Manage.Allowed(player)
    return Privacy.CanSeeAll(player)
end

local function validName(name)
    return type(name) == "string" and name ~= "" and string.len(name) <= Manage.NAME_LENGTH
end

local function validType(fullType)
    return type(fullType) == "string" and fullType ~= "" and string.len(fullType) <= Manage.TYPE_LENGTH
end

local function reply(player, args, fields)
    fields.op = args.op
    fields.request = args.request
    fields.playerNum = args.playerNum
    LSW.ToClient(player, LSW.REPLY_MANAGE, fields)
end

local function sendList(player, args, field, list, perMessage, extra)
    local total = #list
    local part = 0
    local i = 1
    repeat
        local chunk = {}
        for n = i, math.min(total, i + perMessage - 1) do
            chunk[#chunk + 1] = list[n]
        end
        i = i + perMessage
        part = part + 1
        local fields = { part = part, last = i > total }
        fields[field] = chunk
        for key, value in pairs(extra or {}) do
            fields[key] = value
        end
        reply(player, args, fields)
    until i > total
end

local function jobName(player, args, what)
    return "manage:" .. what .. ":" .. Store.KeyOf(player) .. ":" .. tostring(args.playerNum)
end

local function nextRun(what)
    runs = runs + 1
    return "manage:" .. what .. ":" .. string.format("%d", runs)
end

local function log(player, text)
    local line = "[TienLastSeenWhere] " .. Store.KeyOf(player) .. " " .. text
    print(line)
    if isServer() and writeLog then
        writeLog("admin", line)
    end
end

local function walk(record, fn)
    local order = record.order
    local done = {}
    local i = 1
    while i <= #order do
        local key = order[i]
        if not done[key] then
            done[key] = true
            local entry = record.places[key]
            if entry then
                fn(key, entry)
            end
        end
        i = i + 1
        Jobs.Step()
    end
end

local function onAccess(player, args)
    reply(player, args, { allowed = Manage.Allowed(player) })
end

local function onUsers(player, args)
    local names = {}
    local seen = {}
    local online = {}
    local function add(name)
        if validName(name) and not seen[name] and #names < Manage.USERS_LIMIT then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    for _, here in ipairs(Server.PlayersHere()) do
        local name = Store.KeyOf(here)
        online[name] = true
        add(name)
    end
    if type(args.usernames) == "table" then
        for _, name in pairs(args.usernames) do
            add(name)
        end
    end
    Jobs.Start(jobName(player, args, "users"), function()
        local users = {}
        for _, name in ipairs(names) do
            local described = Store.Describe(name)
            if described and described.remembers then
                users[#users + 1] = { username = name, name = described.name, online = online[name] == true }
            end
            Jobs.Step()
        end
        sendList(player, args, "users", users, Manage.USERS_PER_MESSAGE, nil)
    end)
end

local function onSummary(player, args)
    local username = args.username
    if not validName(username) then
        return
    end
    Jobs.Start(jobName(player, args, "summary"), function()
        local record = Store.Get(username)
        Store.WaitLoaded(record)
        local totals = {}
        walk(record, function(key, entry)
            for fullType, count in pairs(entry.items) do
                local total = totals[fullType]
                if not total then
                    total = { c = 0, p = 0 }
                    totals[fullType] = total
                end
                total.c = total.c + count
                total.p = total.p + 1
            end
        end)
        local list = {}
        for fullType, total in pairs(totals) do
            list[#list + 1] = { t = fullType, c = total.c, p = total.p }
        end
        sendList(player, args, "types", list, LSW.SUMMARY_CHUNK, { username = username })
    end)
end

local function onPlaces(player, args)
    local username = args.username
    local fullType = args.fullType
    if not validName(username) or not validType(fullType) then
        return
    end
    Jobs.Start(jobName(player, args, "places:" .. fullType), function()
        local record = Store.Get(username)
        Store.WaitLoaded(record)
        local vehicles = Server.VehiclesBySqlId()
        local px, py = player:getX(), player:getY()
        local list = {}
        walk(record, function(key, entry)
            local count = entry.items[fullType]
            if count then
                local result = Server.ResultOf(entry, count, vehicles)
                result.d = LSW.DistanceTo(px, py, result.x + 0.5, result.y + 0.5)
                list[#list + 1] = result
            end
        end)
        table.sort(list, function(a, b) return a.d < b.d end)
        local trimmed = {}
        for i = 1, math.min(#list, Server.PLACES_LIMIT) do
            trimmed[i] = list[i]
        end
        sendList(player, args, "places", trimmed, Server.PLACES_PER_MESSAGE,
            { username = username, fullType = fullType, total = #list })
    end)
end

local function forgetIn(record, everywhere, at, by)
    local items = 0
    local touched = {}
    local places = 0
    local function forget(key, types)
        local entry = record.places[key]
        if entry and (not by or entry.by == by) then
            local removed = Store.ForgetTypes(record, key, types)
            if removed > 0 then
                items = items + removed
                if not touched[key] then
                    touched[key] = true
                    places = places + 1
                end
            end
        end
    end
    if everywhere then
        walk(record, function(key)
            forget(key, everywhere)
        end)
    end
    for key, types in pairs(at) do
        forget(key, types)
    end
    return items, places
end

local function onForget(player, args)
    local username = args.username
    if not validName(username) then
        return
    end
    local count = 0
    local everywhere = nil
    if type(args.types) == "table" then
        for _, fullType in pairs(args.types) do
            if validType(fullType) and count < Manage.FORGET_LIMIT then
                everywhere = everywhere or {}
                everywhere[fullType] = true
                count = count + 1
            end
        end
    end
    local at = {}
    if type(args.at) == "table" then
        for _, pair in pairs(args.at) do
            if type(pair) == "table" and validType(pair.type) and type(pair.key) == "string"
                and string.len(pair.key) <= Server.MARK_KEY_LENGTH and count < Manage.FORGET_LIMIT then
                at[pair.key] = at[pair.key] or {}
                at[pair.key][pair.type] = true
                count = count + 1
            end
        end
    end
    if count == 0 then
        return
    end
    local world = args.world == true
    Jobs.Start(nextRun("forget"), function()
        local record = Store.Get(username)
        Store.WaitLoaded(record)
        local items, places = forgetIn(record, everywhere, at, nil)
        local worldItems, worldPlaces = 0, 0
        if world then
            local shared = Store.World()
            Store.WaitLoaded(shared)
            worldItems, worldPlaces = forgetIn(shared, everywhere, at, username)
        end
        log(player, string.format("made %s forget %d items in %d places (%d item types)%s", username, items, places,
            count, world and string.format(", and %d items in %d places of shared knowledge", worldItems, worldPlaces)
            or ""))
        reply(player, args, {
            username = username, items = items, places = places, worldItems = worldItems, worldPlaces = worldPlaces,
        })
    end)
end

local function onWipe(player, args)
    local username = args.username
    if not validName(username) then
        return
    end
    local world = args.world == true
    Jobs.Start(nextRun("wipe"), function()
        local record = Store.Get(username)
        Store.WaitLoaded(record)
        local places = 0
        for _ in pairs(record.places) do
            places = places + 1
        end
        Store.Wipe(username)
        local worldPlaces = 0
        if world then
            local shared = Store.World()
            Store.WaitLoaded(shared)
            walk(shared, function(key, entry)
                if entry.by == username then
                    Store.Remove(shared, key)
                    worldPlaces = worldPlaces + 1
                end
            end)
        end
        log(player, string.format("wiped the memory of %s (%d places)%s", username, places,
            world and string.format(", and %d places of shared knowledge", worldPlaces) or ""))
        reply(player, args, { username = username, places = places, worldPlaces = worldPlaces })
    end)
end

local ops = {
    access = onAccess,
    users = onUsers,
    summary = onSummary,
    places = onPlaces,
    forget = onForget,
    wipe = onWipe,
}

local function onManage(player, args)
    local op = ops[args.op]
    if not op then
        return
    end
    if args.op ~= "access" and not Manage.Allowed(player) then
        reply(player, args, { refused = true })
        return
    end
    op(player, args)
end

Server.AddHandler(LSW.CMD_MANAGE, onManage)
