require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Options"
require "TienLastSeenWhere_Route"

local LSW = TienLastSeenWhere

LSW.Arrow = {}

local Arrow = LSW.Arrow

Arrow.MODE_FLOOR = "floor"
Arrow.MODE_OVERLAY = "overlay"
Arrow.mode = Arrow.MODE_FLOOR

Arrow.TEXTURE = "media/textures/TienLastSeenWhere_Arrow.png"
Arrow.START = 0.5
Arrow.LENGTH = 1.6
Arrow.HALF_WIDTH = 0.4
Arrow.ARRIVED = 1.6
Arrow.ROUTE_MS = 1000
Arrow.MARKER_AFTER_ARRIVAL_MS = 8000
Arrow.NO_ROUTE_ALPHA = 0.45

local targets = {}
local texture = nil

local function removeMarker(target)
    if target and target.marker then
        target.marker:remove()
        target.marker = nil
    end
end

local function placeMarker(target)
    if target.marker then
        return
    end
    local square = getCell():getGridSquare(math.floor(target.x), math.floor(target.y), target.z)
    if not square then
        return
    end
    local colour = LSW.Options.GetArrowColour()
    target.marker = getWorldMarkers():addGridSquareMarker(square, colour.r, colour.g, colour.b, true, 0.8)
end

function Arrow.SetTarget(playerNum, x, y, z)
    Arrow.Clear(playerNum)
    targets[playerNum] = { x = x + 0.5, y = y + 0.5, z = z, routeMs = 0 }
end

function Arrow.Clear(playerNum)
    removeMarker(targets[playerNum])
    targets[playerNum] = nil
end

function Arrow.GetTarget(playerNum)
    return targets[playerNum]
end

function Arrow.SetMode(mode)
    Arrow.mode = mode
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

local function updateTarget(playerNum, player, target)
    local pz = math.floor(player:getZ())
    if pz == target.z then
        placeMarker(target)
        local distance = LSW.DistanceTo(player:getX(), player:getY(), target.x, target.y)
        if distance < Arrow.ARRIVED then
            target.arrivedMs = target.arrivedMs or getTimestampMs()
        end
    end
    if target.arrivedMs and getTimestampMs() - target.arrivedMs > Arrow.MARKER_AFTER_ARRIVAL_MS then
        Arrow.Clear(playerNum)
        return false
    end
    return true
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
    local ux = dx / distance
    local uy = dy / distance
    local nx = -uy * Arrow.HALF_WIDTH
    local ny = ux * Arrow.HALF_WIDTH
    local tailX = px + ux * Arrow.START
    local tailY = py + uy * Arrow.START
    local tipX = tailX + ux * Arrow.LENGTH
    local tipY = tailY + uy * Arrow.LENGTH
    return {
        tailX - nx, tailY - ny,
        tipX - nx, tipY - ny,
        tipX + nx, tipY + ny,
        tailX + nx, tailY + ny,
        tipX = tipX,
        tipY = tipY,
    }
end

local function draw(points, project, faded)
    local tex = arrowTexture()
    if not tex then
        return
    end
    local x1, y1 = project(points[1], points[2])
    local x2, y2 = project(points[3], points[4])
    local x3, y3 = project(points[5], points[6])
    local x4, y4 = project(points[7], points[8])
    local c = LSW.Options.GetArrowColour()
    local a = faded and c.a * Arrow.NO_ROUTE_ALPHA or c.a
    getRenderer():renderPoly(tex, x1, y1, x2, y2, x3, y3, x4, y4, c.r, c.g, c.b, a)
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

local function onPostFloorLayerDraw(z)
    if Arrow.mode ~= Arrow.MODE_FLOOR then
        return
    end
    local player = IsoCamera.getCameraCharacter()
    if not player or not instanceof(player, "IsoPlayer") or not player:isLocalPlayer() then
        return
    end
    local playerNum = player:getPlayerNum()
    local target = targets[playerNum]
    if not target or target.arrivedMs or math.floor(player:getZ()) ~= z then
        return
    end
    local aimX, aimY = aimOf(player, target)
    local points = worldCorners(player, aimX, aimY)
    if not points then
        return
    end
    local pz = player:getZ()
    local offX = IsoCamera.getOffX(playerNum)
    local offY = IsoCamera.getOffY(playerNum)
    draw(points, function(wx, wy)
        return IsoUtils.XToScreen(wx, wy, pz, 0) - offX, IsoUtils.YToScreen(wx, wy, pz, 0) - offY
    end, target.noRoute)
end

local function onPreUIDraw()
    for playerNum, target in pairs(targets) do
        local player = getSpecificPlayer(playerNum)
        if not player or player:isDead() then
            Arrow.Clear(playerNum)
        elseif updateTarget(playerNum, player, target) and not target.arrivedMs then
            local aimX, aimY = aimOf(player, target)
            local points = worldCorners(player, aimX, aimY)
            if points then
                local pz = player:getZ()
                local function project(wx, wy)
                    return isoToScreenX(playerNum, wx, wy, pz), isoToScreenY(playerNum, wx, wy, pz)
                end
                if Arrow.mode == Arrow.MODE_OVERLAY then
                    draw(points, project, target.noRoute)
                end
                local badge = floorBadge(player, target)
                if badge then
                    local bx, by = project(points.tipX, points.tipY)
                    local c = LSW.Options.GetArrowColour()
                    getTextManager():DrawStringCentre(UIFont.Small, bx, by - 24, badge, c.r, c.g, c.b, 1)
                end
            end
        end
    end
end

local function onGameStart()
    targets = {}
end

if Events.OnPostFloorLayerDraw then
    Events.OnPostFloorLayerDraw.Add(onPostFloorLayerDraw)
end
Events.OnPreUIDraw.Add(onPreUIDraw)
Events.OnGameStart.Add(onGameStart)
