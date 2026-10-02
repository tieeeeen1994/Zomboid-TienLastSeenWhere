TienLastSeenWhere = TienLastSeenWhere or {}

local LSW = TienLastSeenWhere

LSW.MODULE = "TienLastSeenWhere"

LSW.CMD_SEEN_CONTAINER = "seenContainer"
LSW.CMD_SEEN_SQUARES = "seenSquares"
LSW.CMD_SUMMARY = "summary"
LSW.CMD_FIND = "find"
LSW.CMD_PRIVACY = "privacy"
LSW.CMD_PRIVACY_SET = "privacySet"
LSW.CMD_PLACES = "places"
LSW.REPLY_SUMMARY = "summary"
LSW.REPLY_FIND = "find"
LSW.REPLY_PRIVACY = "privacy"
LSW.REPLY_PLACES = "places"

LSW.RULE_PLAYER = 1
LSW.RULE_MINE = 2
LSW.RULE_SHARED = 3
LSW.RULE_EXPLORED = 4

LSW.FLOOR_IN_SIGHT = 1
LSW.FLOOR_IN_REACH = 2
LSW.FLOOR_OFF = 3

LSW.KIND_OBJECT = "o"
LSW.KIND_VEHICLE = "v"
LSW.KIND_BODY = "d"
LSW.KIND_BAG = "b"
LSW.KIND_FLOOR = "f"

LSW.MARK_PLACE = "p"
LSW.MARK_ITEM = "i"

LSW.PRIVATE_NONE = 0
LSW.PRIVATE_ME = 1
LSW.PRIVATE_GROUP = 2

LSW.SMALL_WEIGHT = 0.2
LSW.FIND_LIMIT = 40
LSW.SUMMARY_CHUNK = 400

local function sandbox()
    return SandboxVars and SandboxVars.TienLastSeenWhere or {}
end

function LSW.GetSandboxRule()
    local rule = tonumber(sandbox().SearchRule)
    if not rule or rule < LSW.RULE_PLAYER then
        return LSW.RULE_PLAYER
    end
    return math.min(rule, LSW.RULE_EXPLORED)
end

function LSW.ResolveRule(playerRule)
    local forced = LSW.GetSandboxRule()
    if forced ~= LSW.RULE_PLAYER then
        return forced
    end
    local rule = tonumber(playerRule)
    if not rule or rule < LSW.RULE_MINE then
        return LSW.RULE_MINE
    end
    return math.min(rule, LSW.RULE_EXPLORED)
end

function LSW.GetFloorRule()
    local rule = tonumber(sandbox().FloorRule)
    if not rule or rule < LSW.FLOOR_IN_SIGHT or rule > LSW.FLOOR_OFF then
        return LSW.FLOOR_IN_SIGHT
    end
    return rule
end

function LSW.GetSmallItemDistance()
    local distance = tonumber(sandbox().SmallItemDistance)
    if not distance or distance < 1 then
        return 4
    end
    return distance
end

function LSW.GetForgetAfterDays()
    local days = tonumber(sandbox().ForgetAfterDays)
    if not days or days < 0 then
        return 0
    end
    return days
end

LSW.REFRESH_OPENED = 1
LSW.REFRESH_NEARBY = 2
LSW.NAME_USERNAME = 1
LSW.NAME_CHARACTER = 2

function LSW.GetMemoryRefresh()
    return tonumber(sandbox().MemoryRefresh) == LSW.REFRESH_NEARBY and LSW.REFRESH_NEARBY or LSW.REFRESH_OPENED
end

function LSW.GetFoundByName()
    return tonumber(sandbox().FoundByName) == LSW.NAME_CHARACTER and LSW.NAME_CHARACTER or LSW.NAME_USERNAME
end

function LSW.IsPrivacyEnabled()
    return sandbox().Privacy ~= false
end

function LSW.IsPrivacyUseful()
    return LSW.IsPrivacyEnabled() and LSW.GetSandboxRule() ~= LSW.RULE_MINE
end

function LSW.MarkKey(kind, id)
    return kind .. ":" .. tostring(id)
end

function LSW.Now()
    return getGameTime():getWorldAgeHours()
end

function LSW.Split(text, separator)
    local parts = {}
    for part in string.gmatch(text, "([^" .. separator .. "]+)") do
        parts[#parts + 1] = part
    end
    return parts
end

function LSW.BodyId(body)
    local id = body and body:getObjectIDAsLong()
    if type(id) == "number" and id >= 0 then
        return id
    end
    return nil
end

function LSW.FindBody(square, key)
    local bodies = square:getDeadBodys()
    local id = tonumber(string.match(key, ":#(%d+)$"))
    if id then
        for i = 0, bodies:size() - 1 do
            local body = bodies:get(i)
            if LSW.BodyId(body) == id then
                return body
            end
        end
        return nil
    end
    local index = tonumber(string.match(key, ":(%d+)$"))
    if index and index < bodies:size() then
        return bodies:get(index)
    end
    return nil
end

function LSW.SquareKey(x, y, z)
    return string.format("%d,%d,%d", x, y, z)
end

function LSW.ObjectKey(x, y, z, sprite, containerType)
    return "o:" .. LSW.SquareKey(x, y, z) .. ":" .. tostring(sprite) .. ":" .. tostring(containerType)
end

function LSW.BuildingKey(square)
    local building = square and square:getBuilding()
    local def = building and building:getDef()
    if not def then
        return nil
    end
    return string.format("%d,%d", def:getX(), def:getY())
end

function LSW.RoomName(square)
    local room = square and square:getRoom()
    return room and room:getName() or nil
end

function LSW.DirectionTo(fromX, fromY, toX, toY)
    local dx = toX - fromX
    local dy = toY - fromY
    if dx == 0 and dy == 0 then
        return nil
    end
    return IsoDirections.fromAngle(dx, dy)
end

function LSW.DistanceTo(fromX, fromY, toX, toY)
    local dx = toX - fromX
    local dy = toY - fromY
    return math.sqrt(dx * dx + dy * dy)
end

function LSW.ToServer(player, command, args)
    if isClient() then
        sendClientCommand(player, LSW.MODULE, command, args)
    elseif LSW.Server then
        LSW.Server.Handle(player, command, args)
    end
end

function LSW.ToClient(player, command, args)
    if isServer() then
        sendServerCommand(player, LSW.MODULE, command, args)
    elseif LSW.Client then
        LSW.Client.Handle(player, command, args)
    end
end
