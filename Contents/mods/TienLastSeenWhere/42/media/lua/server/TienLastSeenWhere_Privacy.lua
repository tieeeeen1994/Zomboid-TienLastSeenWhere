if isClient() then return end

require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Store"

local LSW = TienLastSeenWhere
local Store = LSW.Store

LSW.Privacy = {}

local Privacy = LSW.Privacy

Privacy.FILE = "_privacy"
Privacy.VERSION = "1"
Privacy.MAX_MARKS = 200
Privacy.SAVE_INTERVAL_MS = 30000

local loaded = false
local owners = {}
local byPlace = {}
local byItem = {}
local bySquare = {}
local dirty = false
local lastSaveMs = 0
local version = 0

local function fileName()
    return Store.Folder() .. "/" .. Privacy.FILE .. ".txt"
end

local function squareOfKey(key)
    return string.match(key, "^o:(%-?%d+,%-?%d+,%-?%d+):")
end

local function targetOf(mark)
    if mark.kind == LSW.MARK_PLACE then
        return byPlace
    end
    return byItem
end

local function index(mark)
    local target = targetOf(mark)
    local levels = target[mark.id]
    if not levels then
        levels = {}
        target[mark.id] = levels
    end
    levels[mark.owner] = mark.level
    local square = mark.kind == LSW.MARK_PLACE and squareOfKey(mark.id)
    if square then
        bySquare[square] = bySquare[square] or {}
        bySquare[square][mark.id] = true
    end
end

local function unindex(mark)
    local target = targetOf(mark)
    local levels = target[mark.id]
    if levels then
        levels[mark.owner] = nil
        local empty = true
        for _ in pairs(levels) do
            empty = false
            break
        end
        if empty then
            target[mark.id] = nil
            local square = mark.kind == LSW.MARK_PLACE and squareOfKey(mark.id)
            if square and bySquare[square] then
                bySquare[square][mark.id] = nil
            end
        end
    end
end

local function changed()
    dirty = true
    version = version + 1
end

local field = Store.Field
local unfield = Store.Unfield

local function encode(mark)
    return table.concat({
        "M",
        mark.owner,
        mark.kind,
        mark.id,
        string.format("%d", mark.level),
        field(mark.placeKind),
        mark.x and string.format("%d", mark.x) or "-",
        mark.y and string.format("%d", mark.y) or "-",
        mark.z and string.format("%d", mark.z) or "-",
        field(mark.type),
        field(mark.room),
        field(mark.fullType),
        string.format("%.3f", mark.t or 0),
        mark.exposedT and string.format("%.3f", mark.exposedT) or "-",
        mark.ackT and string.format("%.3f", mark.ackT) or "-",
        field(mark.exposedBy),
    }, "\t")
end

local MARK_PATTERN = "^M\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$"

local function decode(line)
    local owner, kind, id, level, placeKind, x, y, z, placeType, room, fullType, t, exposedT, ackT, exposedBy =
        string.match(line, MARK_PATTERN)
    if not owner then
        return nil
    end
    return {
        owner = owner,
        kind = kind,
        id = id,
        level = tonumber(level) or LSW.PRIVATE_ME,
        placeKind = unfield(placeKind),
        x = tonumber(x),
        y = tonumber(y),
        z = tonumber(z),
        type = unfield(placeType),
        room = unfield(room),
        fullType = unfield(fullType),
        t = tonumber(t) or 0,
        exposedT = tonumber(exposedT),
        ackT = tonumber(ackT),
        exposedBy = unfield(exposedBy),
    }
end

local function put(mark)
    local marks = owners[mark.owner]
    if not marks then
        marks = {}
        owners[mark.owner] = marks
    end
    local key = LSW.MarkKey(mark.kind, mark.id)
    if marks[key] then
        unindex(marks[key])
    end
    marks[key] = mark
    index(mark)
end

local function ensureLoaded()
    if loaded then
        return
    end
    loaded = true
    local reader = getFileReader(fileName(), false)
    if not reader then
        return
    end
    local line = reader:readLine()
    while line do
        local mark = string.sub(line, 1, 1) == "M" and decode(line)
        if mark then
            put(mark)
        end
        line = reader:readLine()
    end
    reader:close()
end

function Privacy.Save(force)
    if not loaded or not dirty then
        return
    end
    local now = getTimestampMs()
    if not force and now - lastSaveMs < Privacy.SAVE_INTERVAL_MS then
        return
    end
    lastSaveMs = now
    local writer = getFileWriter(fileName(), true, false)
    if not writer then
        return
    end
    dirty = false
    writer:writeln("V\t" .. Privacy.VERSION)
    for _, marks in pairs(owners) do
        for _, mark in pairs(marks) do
            writer:writeln(encode(mark))
        end
    end
    writer:close()
end

function Privacy.Enabled()
    return LSW.IsPrivacyEnabled()
end

function Privacy.Version()
    return version
end

function Privacy.MarksOf(owner)
    ensureLoaded()
    local list = {}
    for _, mark in pairs(owners[owner] or {}) do
        list[#list + 1] = mark
    end
    return list
end

function Privacy.LevelOf(owner, kind, id)
    ensureLoaded()
    local marks = owners[owner]
    local mark = marks and marks[LSW.MarkKey(kind, id)]
    return mark and mark.level or LSW.PRIVATE_NONE
end

function Privacy.Set(owner, mark, level)
    ensureLoaded()
    local key = LSW.MarkKey(mark.kind, mark.id)
    local marks = owners[owner] or {}
    local current = marks[key]
    if level == LSW.PRIVATE_NONE then
        if current then
            unindex(current)
            marks[key] = nil
            changed()
        end
        return true
    end
    if not current then
        local count = 0
        for _ in pairs(marks) do
            count = count + 1
        end
        if count >= Privacy.MAX_MARKS then
            return false, "full"
        end
    end
    mark.owner = owner
    mark.level = level
    mark.t = mark.t or LSW.Now()
    if current then
        mark.exposedT = current.exposedT
        mark.exposedBy = current.exposedBy
        mark.ackT = current.ackT
    end
    put(mark)
    changed()
    return true
end

function Privacy.Acknowledge(owner)
    ensureLoaded()
    local now = LSW.Now()
    for _, mark in pairs(owners[owner] or {}) do
        if mark.exposedT and (not mark.ackT or mark.ackT < mark.exposedT) then
            mark.ackT = now
            dirty = true
        end
    end
end

local function exposeAll(kind, id, levels, name, isFriend)
    for owner, level in pairs(levels) do
        if owner ~= name and level == LSW.PRIVATE_ME and isFriend(owner) then
            local marks = owners[owner]
            local mark = marks and marks[LSW.MarkKey(kind, id)]
            if mark then
                mark.exposedT = LSW.Now()
                mark.exposedBy = name
                dirty = true
            end
        end
    end
end

function Privacy.NoteSighting(player, entry)
    if not LSW.IsPrivacyEnabled() then
        return
    end
    ensureLoaded()
    local name = Store.KeyOf(player)
    local groups = {}
    local function isFriend(owner)
        if not isServer() then
            return true
        end
        if not groups[owner] then
            groups[owner] = Privacy.SharedUsernames(owner)
        end
        return groups[owner][name] == true
    end
    local levels = byPlace[entry.key]
    if levels then
        exposeAll(LSW.MARK_PLACE, entry.key, levels, name, isFriend)
    end
    for _, parent in ipairs(entry.parents or {}) do
        levels = byPlace[parent]
        if levels then
            exposeAll(LSW.MARK_PLACE, parent, levels, name, isFriend)
        end
    end
    for _, list in pairs(entry.ids or {}) do
        for _, id in ipairs(list) do
            local key = tostring(id)
            levels = byItem[key]
            if levels then
                exposeAll(LSW.MARK_ITEM, key, levels, name, isFriend)
            end
        end
    end
end

function Privacy.OwnLevel(owner, entry, fullType)
    ensureLoaded()
    local marks = owners[owner]
    if not marks then
        return nil
    end
    local best = nil
    local function take(kind, id)
        local mark = marks[LSW.MarkKey(kind, id)]
        if mark and (not best or mark.level < best) then
            best = mark.level
        end
    end
    take(LSW.MARK_PLACE, entry.key)
    for _, parent in ipairs(entry.parents or {}) do
        take(LSW.MARK_PLACE, parent)
    end
    for _, id in ipairs(entry.ids and entry.ids[fullType] or {}) do
        take(LSW.MARK_ITEM, tostring(id))
    end
    return best
end

function Privacy.ClearOwner(owner)
    ensureLoaded()
    local marks = owners[owner]
    if not marks then
        return
    end
    for _, mark in pairs(marks) do
        unindex(mark)
    end
    owners[owner] = nil
    changed()
end

function Privacy.ForgetPlace(placeKey)
    ensureLoaded()
    local levels = byPlace[placeKey]
    if not levels then
        return
    end
    local names = {}
    for owner in pairs(levels) do
        names[#names + 1] = owner
    end
    for _, owner in ipairs(names) do
        local marks = owners[owner]
        local key = LSW.MarkKey(LSW.MARK_PLACE, placeKey)
        local mark = marks and marks[key]
        if mark then
            unindex(mark)
            marks[key] = nil
        end
    end
    changed()
end

function Privacy.PlaceKeysAt(x, y, z)
    ensureLoaded()
    return bySquare[LSW.SquareKey(x, y, z)]
end

function Privacy.IsItemMarked(id)
    if not LSW.IsPrivacyEnabled() then
        return false
    end
    ensureLoaded()
    return byItem[tostring(id)] ~= nil
end

function Privacy.SharedUsernames(username)
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

function Privacy.CanSeeAll(player)
    if not isServer() then
        return isDebugEnabled()
    end
    local role = player:getRole()
    return role ~= nil and role:hasAdminTool()
end

local Viewer = {}
Viewer.__index = Viewer

function Privacy.Viewer(player, seeAll)
    if not LSW.IsPrivacyEnabled() or (seeAll and Privacy.CanSeeAll(player)) then
        return nil
    end
    ensureLoaded()
    return setmetatable({ name = Store.KeyOf(player), groups = {} }, Viewer)
end

function Viewer:allowsOne(owner, level)
    if owner == self.name then
        return true
    end
    if level ~= LSW.PRIVATE_GROUP or not isServer() then
        return false
    end
    local group = self.groups[owner]
    if not group then
        group = Privacy.SharedUsernames(owner)
        self.groups[owner] = group
    end
    return group[self.name] == true
end

function Viewer:allows(levels, author)
    if not levels then
        return true
    end
    if author then
        local level = levels[author]
        return level == nil or self:allowsOne(author, level)
    end
    for owner, level in pairs(levels) do
        if not self:allowsOne(owner, level) then
            return false
        end
    end
    return true
end

function Viewer:hidesPlace(entry, author)
    if not self:allows(byPlace[entry.key], author) then
        return true
    end
    for _, parent in ipairs(entry.parents or {}) do
        if not self:allows(byPlace[parent], author) then
            return true
        end
    end
    return false
end

function Viewer:visibleItems(entry, author, floors)
    if self:hidesPlace(entry, author) then
        return nil
    end
    if not entry.ids then
        return entry.items
    end
    local items = {}
    local any = false
    for fullType, count in pairs(entry.items) do
        local hidden = 0
        for _, id in ipairs(entry.ids[fullType] or {}) do
            if not self:allows(byItem[tostring(id)], author) then
                hidden = hidden + 1
            end
        end
        local visible = count - hidden
        if hidden > 0 then
            for _, floor in ipairs(floors or {}) do
                local seen = floor[fullType]
                if seen then
                    visible = math.max(visible, math.min(count, seen))
                end
            end
        end
        if visible > 0 then
            items[fullType] = visible
            any = true
        end
    end
    return any and items or nil
end

local function onEveryOneMinute()
    Privacy.Save(false)
end

local function onSave()
    Privacy.Save(true)
end

local function onGameStart()
    loaded = false
    owners = {}
    byPlace = {}
    byItem = {}
    bySquare = {}
    dirty = false
    version = version + 1
end

Store.clearListeners[#Store.clearListeners + 1] = Privacy.ClearOwner

Events.EveryOneMinute.Add(onEveryOneMinute)
Events.OnSave.Add(onSave)
Events.OnGameStart.Add(onGameStart)
