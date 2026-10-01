require "TienLastSeenWhere_Core"

local LSW = TienLastSeenWhere

LSW.Route = {}

local Route = LSW.Route

Route.RADIUS = 40
Route.CACHE_MS = 10000

local stairsCache = {}

local function stairsOn(z, cx, cy)
    local key = string.format("%d:%d:%d", z, math.floor(cx / 20), math.floor(cy / 20))
    local cached = stairsCache[key]
    local now = getTimestampMs()
    if cached and now - cached.ms < Route.CACHE_MS then
        return cached.list
    end
    local list = {}
    local cell = getCell()
    for x = cx - Route.RADIUS, cx + Route.RADIUS do
        for y = cy - Route.RADIUS, cy + Route.RADIUS do
            local square = cell:getGridSquare(x, y, z)
            if square and square:HasStairs() then
                local north = square:getStairsDirection() == IsoDirections.N
                if square:HasStairTop() then
                    list[#list + 1] = { kind = "top", x = x, y = y, z = z, north = north }
                elseif not square:HasElevatedFloor() then
                    list[#list + 1] = { kind = "bottom", x = x, y = y, z = z, north = north }
                end
            end
        end
    end
    stairsCache[key] = { ms = now, list = list }
    return list
end

local function upLegs(stairs)
    if stairs.north then
        return stairs.x, stairs.y + 1, stairs.x, stairs.y - 3
    end
    return stairs.x + 1, stairs.y, stairs.x - 3, stairs.y
end

local function downLegs(stairs)
    if stairs.north then
        return stairs.x, stairs.y - 1, stairs.x, stairs.y + 3
    end
    return stairs.x - 1, stairs.y, stairs.x + 3, stairs.y
end

function Route.Waypoint(player, target)
    local px, py = player:getX(), player:getY()
    local pz = math.floor(player:getZ())
    if pz == target.z then
        return nil
    end
    local up = target.z > pz
    local candidates = up and stairsOn(pz, math.floor(px), math.floor(py))
        or stairsOn(pz - 1, math.floor(px), math.floor(py))
    local best = nil
    local bestCost = nil
    for _, stairs in ipairs(candidates) do
        local wanted = up and "bottom" or "top"
        if stairs.kind == wanted then
            local entryX, entryY, exitX, exitY
            if up then
                entryX, entryY, exitX, exitY = upLegs(stairs)
            else
                entryX, entryY, exitX, exitY = downLegs(stairs)
            end
            local cost = LSW.DistanceTo(px, py, entryX + 0.5, entryY + 0.5)
                + LSW.DistanceTo(exitX + 0.5, exitY + 0.5, target.x, target.y)
            if not bestCost or cost < bestCost then
                bestCost = cost
                best = { x = entryX + 0.5, y = entryY + 0.5, z = pz }
            end
        end
    end
    return best
end

function Route.Reset()
    stairsCache = {}
end

Events.OnGameStart.Add(Route.Reset)
