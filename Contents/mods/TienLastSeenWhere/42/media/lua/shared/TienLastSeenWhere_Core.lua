TienLastSeenWhere = TienLastSeenWhere or {}

local LSW = TienLastSeenWhere

LSW.MODULE = "TienLastSeenWhere"

LSW.CMD_SEEN_CONTAINER = "seenContainer"
LSW.CMD_SEEN_SQUARES = "seenSquares"
LSW.CMD_SUMMARY = "summary"
LSW.CMD_FIND = "find"
LSW.REPLY_SUMMARY = "summary"
LSW.REPLY_FIND = "find"

LSW.RULE_PLAYER = 1
LSW.RULE_MINE = 2
LSW.RULE_SHARED = 3
LSW.RULE_EXPLORED = 4
LSW.RULE_EVERYTHING = 5

LSW.FLOOR_IN_SIGHT = 1
LSW.FLOOR_IN_REACH = 2
LSW.FLOOR_OFF = 3

LSW.KIND_OBJECT = "o"
LSW.KIND_VEHICLE = "v"
LSW.KIND_BODY = "d"
LSW.KIND_BAG = "b"
LSW.KIND_FLOOR = "f"

LSW.SMALL_WEIGHT = 0.2
LSW.LIVE_RADIUS = 30
LSW.LIVE_LEVELS = 3
LSW.FIND_LIMIT = 40
LSW.SUMMARY_CHUNK = 400

local function sandbox()
    return SandboxVars and SandboxVars.TienLastSeenWhere or {}
end

function LSW.GetSandboxRule()
    local rule = tonumber(sandbox().SearchRule)
    if not rule or rule < LSW.RULE_PLAYER or rule > LSW.RULE_EVERYTHING then
        return LSW.RULE_PLAYER
    end
    return rule
end

function LSW.ResolveRule(playerRule)
    local forced = LSW.GetSandboxRule()
    if forced ~= LSW.RULE_PLAYER then
        return forced
    end
    local rule = tonumber(playerRule)
    if not rule or rule < LSW.RULE_MINE or rule > LSW.RULE_EVERYTHING then
        return LSW.RULE_MINE
    end
    return rule
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

function LSW.SquareKey(x, y, z)
    return string.format("%d,%d,%d", x, y, z)
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
