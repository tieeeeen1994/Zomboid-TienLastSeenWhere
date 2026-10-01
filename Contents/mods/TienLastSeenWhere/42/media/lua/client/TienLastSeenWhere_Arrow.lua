require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Options"
require "TienLastSeenWhere_Route"

local LSW = TienLastSeenWhere

LSW.Arrow = {}

local Arrow = LSW.Arrow

Arrow.TEXTURE = "media/textures/TienLastSeenWhere_Arrow.png"
Arrow.START = 0.5
Arrow.LENGTH = 1.0
Arrow.HALF_WIDTH = 0.25
Arrow.ARRIVED = 1.6
Arrow.ROUTE_MS = 1000
Arrow.FIND_MS = 1000
Arrow.CLEAR_AFTER_ARRIVAL_MS = 8000
Arrow.NO_ROUTE_ALPHA = 0.45

local targets = {}
local texture = nil

local function setHighlight(object, playerNum, on, colour)
    if not object or not object.setHighlighted then
        return
    end
    object:setHighlighted(playerNum, on, false)
    if on then
        object:setHighlightColor(playerNum, colour.r, colour.g, colour.b, 1)
    end
end

local function unhighlight(playerNum, target)
    for _, object in ipairs(target and target.objects or {}) do
        setHighlight(object, playerNum, false)
    end
    if target then
        target.objects = {}
    end
end

local function floorItemsOf(square, fullType)
    local found = {}
    local objects = square:getWorldObjects()
    for i = 0, objects:size() - 1 do
        local worldItem = objects:get(i)
        local item = worldItem:getItem()
        if item and (not fullType or item:getFullType() == fullType) then
            found[#found + 1] = worldItem
        end
    end
    return found
end

local function objectsOf(target)
    local place = target.place
    local square = getCell():getGridSquare(place.x, place.y, place.z)
    if place.kind == LSW.KIND_FLOOR then
        return square and floorItemsOf(square, target.fullType) or {}
    end
    local container = LSW.Actions and LSW.Actions.FindContainer(place)
    if not container then
        return {}
    end
    local part = container:getVehiclePart()
    if part then
        return { part:getVehicle() }
    end
    local bag = container:getContainingItem()
    if bag then
        local worldItem = bag:getWorldItem()
        if worldItem then
            return { worldItem }
        end
        local outer = bag:getContainer()
        local parent = outer and outer:getParent()
        return parent and { parent } or {}
    end
    local parent = container:getParent()
    return parent and { parent } or {}
end

local function shownInLootWindow(playerNum, target, objects)
    local page = getPlayerLoot(playerNum)
    if not page or page.isCollapsed or not page:isReallyVisible() then
        return false
    end
    local shown = page.inventoryPane and page.inventoryPane.inventory
    if not shown then
        return false
    end
    if target.place.kind == LSW.KIND_FLOOR then
        if shown ~= ISInventoryPage.GetFloorContainer(playerNum) then
            return false
        end
        local player = getSpecificPlayer(playerNum)
        local square = player and player:getCurrentSquare()
        return square ~= nil and square:getZ() == target.z
            and math.abs(square:getX() - target.place.x) <= 1 and math.abs(square:getY() - target.place.y) <= 1
    end
    local parent = page:getContainerParent(shown)
    for _, object in ipairs(objects) do
        if object == parent then
            return true
        end
    end
    return false
end

local function stopHighlighting(playerNum, target, ownedByVanilla)
    for _, object in ipairs(target.objects) do
        if object ~= ownedByVanilla then
            setHighlight(object, playerNum, false)
        end
    end
    target.objects = {}
    target.found = true
end

local function refreshHighlight(playerNum, target, now)
    if target.found then
        return
    end
    if shownInLootWindow(playerNum, target, target.objects) then
        local page = getPlayerLoot(playerNum)
        stopHighlighting(playerNum, target, page:getContainerParent(page.inventoryPane.inventory))
        return
    end
    if now - (target.findMs or 0) >= Arrow.FIND_MS then
        target.findMs = now
        local found = objectsOf(target)
        local keep = {}
        for _, object in ipairs(found) do
            keep[object] = true
        end
        for _, object in ipairs(target.objects) do
            if not keep[object] then
                setHighlight(object, playerNum, false)
            end
        end
        target.objects = found
    end
    local colour = LSW.Options.GetArrowColour()
    for _, object in ipairs(target.objects) do
        setHighlight(object, playerNum, true, colour)
    end
end

function Arrow.SetTarget(playerNum, place, fullType)
    local current = targets[playerNum]
    if current and current.place.key == place.key and current.fullType == fullType then
        current.arrivedMs = nil
        return
    end
    Arrow.Clear(playerNum)
    targets[playerNum] = {
        place = place,
        fullType = fullType,
        x = place.x + 0.5,
        y = place.y + 0.5,
        z = place.z,
        routeMs = 0,
        objects = {},
    }
end

function Arrow.Clear(playerNum)
    unhighlight(playerNum, targets[playerNum])
    targets[playerNum] = nil
end

function Arrow.GetTarget(playerNum)
    return targets[playerNum]
end

local function arrowTexture()
    if not texture then
        texture = getTexture(Arrow.TEXTURE)
    end
    return texture
end

local function aimOf(player, target)
    local pz = math.floor(player:getZ())
    if pz == target.z then
        target.waypoint = nil
        target.noRoute = false
        return target.x, target.y
    end
    local now = getTimestampMs()
    if now - target.routeMs >= Arrow.ROUTE_MS or target.routeZ ~= pz then
        target.routeMs = now
        target.routeZ = pz
        target.waypoint = LSW.Route.Waypoint(player, target)
        target.noRoute = target.waypoint == nil
    end
    if target.waypoint then
        return target.waypoint.x, target.waypoint.y
    end
    return target.x, target.y
end

local function worldCorners(player, aimX, aimY)
    local px = player:getX()
    local py = player:getY()
    local dx = aimX - px
    local dy = aimY - py
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < Arrow.ARRIVED then
        return nil
    end
    local scale = LSW.Options.GetArrowScale()
    local ux = dx / distance
    local uy = dy / distance
    local nx = -uy * Arrow.HALF_WIDTH * scale
    local ny = ux * Arrow.HALF_WIDTH * scale
    local tailX = px + ux * Arrow.START
    local tailY = py + uy * Arrow.START
    local tipX = tailX + ux * Arrow.LENGTH * scale
    local tipY = tailY + uy * Arrow.LENGTH * scale
    return {
        tailX - nx, tailY - ny,
        tipX - nx, tipY - ny,
        tipX + nx, tipY + ny,
        tailX + nx, tailY + ny,
        tipX = tipX,
        tipY = tipY,
    }
end

local function floorBadge(player, target)
    local diff = target.z - math.floor(player:getZ())
    if diff == 0 then
        return nil
    end
    local count = string.format("%d", math.abs(diff))
    if diff > 0 then
        return getText("IGUI_TienLastSeenWhere_BadgeUp", count)
    end
    return getText("IGUI_TienLastSeenWhere_BadgeDown", count)
end

local function drawArrow(playerNum, player, target)
    local aimX, aimY = aimOf(player, target)
    local points = worldCorners(player, aimX, aimY)
    local tex = arrowTexture()
    if not points or not tex then
        return
    end
    local pz = player:getZ()
    local function project(wx, wy)
        return isoToScreenX(playerNum, wx, wy, pz), isoToScreenY(playerNum, wx, wy, pz)
    end
    local x1, y1 = project(points[1], points[2])
    local x2, y2 = project(points[3], points[4])
    local x3, y3 = project(points[5], points[6])
    local x4, y4 = project(points[7], points[8])
    local c = LSW.Options.GetArrowColour()
    local alpha = target.noRoute and c.a * Arrow.NO_ROUTE_ALPHA or c.a
    getRenderer():renderPoly(tex, x1, y1, x2, y2, x3, y3, x4, y4, c.r, c.g, c.b, alpha)
    local badge = floorBadge(player, target)
    if badge then
        local bx, by = project(points.tipX, points.tipY)
        getTextManager():DrawStringCentre(UIFont.Small, bx, by - 20, badge, c.r, c.g, c.b, 1)
    end
end

local function onPreUIDraw()
    local now = getTimestampMs()
    for playerNum, target in pairs(targets) do
        local player = getSpecificPlayer(playerNum)
        if not player or player:isDead() then
            Arrow.Clear(playerNum)
        else
            refreshHighlight(playerNum, target, now)
            local sameLevel = math.floor(player:getZ()) == target.z
            if sameLevel and LSW.DistanceTo(player:getX(), player:getY(), target.x, target.y) < Arrow.ARRIVED then
                target.arrivedMs = target.arrivedMs or now
            end
            if target.arrivedMs and now - target.arrivedMs > Arrow.CLEAR_AFTER_ARRIVAL_MS then
                Arrow.Clear(playerNum)
            elseif not target.arrivedMs then
                drawArrow(playerNum, player, target)
            end
        end
    end
end

local function onGameStart()
    targets = {}
end

Events.OnPreUIDraw.Add(onPreUIDraw)
Events.OnGameStart.Add(onGameStart)
