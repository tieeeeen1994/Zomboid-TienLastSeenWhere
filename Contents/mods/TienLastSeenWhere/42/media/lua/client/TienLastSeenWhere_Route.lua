require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Jobs"

local LSW = TienLastSeenWhere

LSW.Route = {}

local Route = LSW.Route

Route.RADIUS = 40
Route.CACHE_MS = 10000
Route.MARGIN = 30
Route.MAX_NODES = 12000
Route.MAX_CANDIDATES = 6

local DIAGONAL = math.sqrt(2)

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

-- A binary min-heap of { f = priority, x = , y = } records.
local function heapPush(heap, record)
    local i = #heap + 1
    heap[i] = record
    while i > 1 do
        local parent = math.floor(i / 2)
        if heap[parent].f <= heap[i].f then
            break
        end
        heap[parent], heap[i] = heap[i], heap[parent]
        i = parent
    end
end

local function heapPop(heap)
    local top = heap[1]
    local last = table.remove(heap)
    if #heap > 0 then
        heap[1] = last
        local i = 1
        while true do
            local left, right = i * 2, i * 2 + 1
            local smallest = i
            if left <= #heap and heap[left].f < heap[smallest].f then
                smallest = left
            end
            if right <= #heap and heap[right].f < heap[smallest].f then
                smallest = right
            end
            if smallest == i then
                break
            end
            heap[smallest], heap[i] = heap[i], heap[smallest]
            i = smallest
        end
    end
    return top
end

-- A step between two neighbouring squares is open when neither square has a wall, door or object between them.
local function stepOpen(a, b)
    return not a:isSomethingTo(b) and not b:isSomethingTo(a)
end

-- Walking distance on one floor from (sx, sy) to (gx, gy) around walls, or nil when the search finds no route, runs out
-- of nodes or meets squares that are not loaded. Yields through Jobs.Step, so it must run inside a job.
local function walkDistance(z, sx, sy, gx, gy)
    local cell = getCell()
    local start = cell:getGridSquare(sx, sy, z)
    local goal = cell:getGridSquare(gx, gy, z)
    if not start or not goal then
        return nil
    end
    local minX = math.min(sx, gx) - Route.MARGIN
    local maxX = math.max(sx, gx) + Route.MARGIN
    local minY = math.min(sy, gy) - Route.MARGIN
    local maxY = math.max(sy, gy) + Route.MARGIN
    local width = maxX - minX + 1

    local function key(x, y)
        return (y - minY) * width + (x - minX)
    end
    local function estimate(x, y)
        local dx = math.abs(x - gx)
        local dy = math.abs(y - gy)
        return math.max(dx, dy) + (DIAGONAL - 1) * math.min(dx, dy)
    end

    local best = { [key(sx, sy)] = 0 }
    local closed = {}
    local heap = {}
    heapPush(heap, { f = estimate(sx, sy), x = sx, y = sy })
    local expanded = 0
    local unknown = false
    while #heap > 0 do
        local node = heapPop(heap)
        local k = key(node.x, node.y)
        if not closed[k] then
            closed[k] = true
            if node.x == gx and node.y == gy then
                return best[k]
            end
            expanded = expanded + 1
            if expanded > Route.MAX_NODES then
                return nil
            end
            LSW.Jobs.Step()
            local here = cell:getGridSquare(node.x, node.y, z)
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local nx, ny = node.x + dx, node.y + dy
                    local nk = key(nx, ny)
                    if (dx ~= 0 or dy ~= 0) and nx >= minX and nx <= maxX and ny >= minY and ny <= maxY and not closed[nk] then
                        local there = cell:getGridSquare(nx, ny, z)
                        if not there then
                            unknown = true
                        end
                        local open = there ~= nil and stepOpen(here, there)
                        local step = 1
                        if open and dx ~= 0 and dy ~= 0 then
                            -- A diagonal step must not cut a wall corner: both orthogonal steps must be open too.
                            local sideX = cell:getGridSquare(node.x + dx, node.y, z)
                            local sideY = cell:getGridSquare(node.x, node.y + dy, z)
                            open = sideX ~= nil and sideY ~= nil and stepOpen(here, sideX) and stepOpen(sideX, there)
                                and stepOpen(here, sideY) and stepOpen(sideY, there)
                            step = DIAGONAL
                        end
                        if open then
                            local cost = best[k] + step
                            if not best[nk] or cost < best[nk] then
                                best[nk] = cost
                                heapPush(heap, { f = cost + estimate(nx, ny), x = nx, y = ny })
                            end
                        end
                    end
                end
            end
        end
    end
    -- Every reachable square is searched and the goal is still not reached: walled off, not a matter of distance. A
    -- search that met unloaded squares cannot tell, so it reports nil and the caller uses the straight line.
    if unknown then
        return nil
    end
    return math.huge
end

-- The staircase to take next. Candidates are ranked by straight-line distance first; the best few are then priced
-- by the walking distance, so a wall between the stairs and the target sends the arrow to the staircase with the open
-- route. A distance the search cannot measure falls back to the straight line. Runs inside a job.
function Route.Plan(player, target)
    local px, py = player:getX(), player:getY()
    local pz = math.floor(player:getZ())
    if pz == target.z then
        return nil
    end
    local up = target.z > pz
    local stairsZ = up and pz or pz - 1
    local exitZ = up and pz + 1 or pz - 1
    local wanted = up and "bottom" or "top"
    local ranked = {}
    for _, stairs in ipairs(stairsOn(stairsZ, math.floor(px), math.floor(py))) do
        if stairs.kind == wanted then
            local entryX, entryY, exitX, exitY
            if up then
                entryX, entryY, exitX, exitY = upLegs(stairs)
            else
                entryX, entryY, exitX, exitY = downLegs(stairs)
            end
            local straight = LSW.DistanceTo(px, py, entryX + 0.5, entryY + 0.5)
                + LSW.DistanceTo(exitX + 0.5, exitY + 0.5, target.x, target.y)
            ranked[#ranked + 1] = {
                straight = straight,
                entryX = entryX, entryY = entryY, exitX = exitX, exitY = exitY,
            }
        end
    end
    table.sort(ranked, function(a, b) return a.straight < b.straight end)

    local best = nil
    local bestCost = nil
    for i = 1, math.min(#ranked, Route.MAX_CANDIDATES) do
        local c = ranked[i]
        local toEntry = walkDistance(pz, math.floor(px), math.floor(py), c.entryX, c.entryY)
        if toEntry == nil then
            toEntry = LSW.DistanceTo(px, py, c.entryX + 0.5, c.entryY + 0.5)
        end
        local fromExit
        if target.z == exitZ then
            fromExit = walkDistance(exitZ, c.exitX, c.exitY, math.floor(target.x), math.floor(target.y))
        end
        if fromExit == nil then
            fromExit = LSW.DistanceTo(c.exitX + 0.5, c.exitY + 0.5, target.x, target.y)
        end
        local cost = toEntry + fromExit
        if not bestCost or cost < bestCost then
            bestCost = cost
            best = { x = c.entryX + 0.5, y = c.entryY + 0.5, z = pz }
        end
    end
    return best
end

function Route.Reset()
    stairsCache = {}
end

Events.OnGameStart.Add(Route.Reset)
