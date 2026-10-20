require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Jobs"

local LSW = TienLastSeenWhere

LSW.Route = {}

local Route = LSW.Route

Route.RADIUS = 40
Route.CACHE_MS = 10000
Route.MARGIN = 30
Route.MAX_NODES = 20000
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
        LSW.Jobs.Step()
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

local function octile(ax, ay, bx, by)
    local dx = math.abs(ax - bx)
    local dy = math.abs(ay - by)
    return math.max(dx, dy) + (DIAGONAL - 1) * math.min(dx, dy)
end

local function stepOpen(a, b)
    if a:isWindowTo(b) then
        return false
    end
    return not a:isWallTo(b) or a:isDoorTo(b)
end

local function wallFacing(here, dx, dy)
    if dy == -1 then
        return here:has(IsoFlagType.collideN)
    elseif dx == -1 then
        return here:has(IsoFlagType.collideW)
    end
    return false
end

function Route.WalkDistances(z, sx, sy, goals)
    local results = {}
    local cell = getCell()
    local start = cell:getGridSquare(sx, sy, z)
    if not start then
        for i, goal in ipairs(goals) do
            results[i] = octile(sx, sy, goal.x, goal.y)
        end
        return results
    end
    local minX, maxX, minY, maxY = sx, sx, sy, sy
    for _, goal in ipairs(goals) do
        minX = math.min(minX, goal.x)
        maxX = math.max(maxX, goal.x)
        minY = math.min(minY, goal.y)
        maxY = math.max(maxY, goal.y)
    end
    minX, maxX = minX - Route.MARGIN, maxX + Route.MARGIN
    minY, maxY = minY - Route.MARGIN, maxY + Route.MARGIN
    local width = maxX - minX + 1

    local function key(x, y)
        return (y - minY) * width + (x - minX)
    end

    local pending = {}
    local remaining = 0
    for i, goal in ipairs(goals) do
        local k = key(goal.x, goal.y)
        pending[k] = pending[k] or {}
        table.insert(pending[k], i)
        remaining = remaining + 1
    end

    local best = { [key(sx, sy)] = 0 }
    local closed = {}
    local heap = {}
    heapPush(heap, { f = 0, x = sx, y = sy })
    local expanded = 0
    local settled = 0
    local unsure = false
    while #heap > 0 and remaining > 0 do
        local node = heapPop(heap)
        local k = key(node.x, node.y)
        if not closed[k] then
            closed[k] = true
            settled = best[k]
            local hits = pending[k]
            if hits then
                for _, i in ipairs(hits) do
                    results[i] = settled
                    remaining = remaining - 1
                end
                pending[k] = nil
            end
            expanded = expanded + 1
            if remaining > 0 and expanded > Route.MAX_NODES then
                unsure = true
                break
            end
            LSW.Jobs.Step()
            local here = cell:getGridSquare(node.x, node.y, z)
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local nx, ny = node.x + dx, node.y + dy
                    local inBox = nx >= minX and nx <= maxX and ny >= minY and ny <= maxY
                    local nk = inBox and key(nx, ny) or -1
                    local diagonal = dx ~= 0 and dy ~= 0
                    if (dx ~= 0 or dy ~= 0) and not closed[nk] then
                        local there = cell:getGridSquare(nx, ny, z)
                        if not inBox or not there then
                            if not diagonal and ((there and stepOpen(here, there)) or (not there and not wallFacing(here, dx, dy))) then
                                unsure = true
                            end
                        else
                            local open = stepOpen(here, there)
                            local step = 1
                            if open and diagonal then
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
                                    heapPush(heap, { f = cost, x = nx, y = ny })
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    for i, goal in ipairs(goals) do
        if not results[i] then
            if unsure then
                results[i] = math.max(settled, octile(sx, sy, goal.x, goal.y))
            else
                results[i] = math.huge
            end
        end
    end
    return results
end

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
    if #ranked == 0 then
        return nil
    end
    table.sort(ranked, function(a, b) return a.straight < b.straight end)
    while #ranked > Route.MAX_CANDIDATES do
        table.remove(ranked)
    end

    local entries = {}
    local exits = {}
    for i, c in ipairs(ranked) do
        entries[i] = { x = c.entryX, y = c.entryY }
        exits[i] = { x = c.exitX, y = c.exitY }
    end
    local toEntry = Route.WalkDistances(pz, math.floor(px), math.floor(py), entries)
    local fromExit = nil
    if target.z == exitZ then
        fromExit = Route.WalkDistances(exitZ, math.floor(target.x), math.floor(target.y), exits)
    end

    local best = nil
    local bestCost = nil
    for i, c in ipairs(ranked) do
        local leg = fromExit and fromExit[i] or LSW.DistanceTo(c.exitX + 0.5, c.exitY + 0.5, target.x, target.y)
        local cost = toEntry[i] + leg
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
