require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Arrow"

local LSW = TienLastSeenWhere
local Arrow = LSW.Arrow

local function clickedSquare(worldObjects)
    for _, object in ipairs(worldObjects) do
        local square = object:getSquare()
        if square then
            return square
        end
    end
    return nil
end

local function pointHere(playerNum, square)
    Arrow.SetTarget(playerNum, {
        key = "debug:" .. LSW.SquareKey(square:getX(), square:getY(), square:getZ()),
        kind = LSW.KIND_FLOOR,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
    }, nil)
end

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test or not isDebugEnabled() then
        return
    end
    local square = clickedSquare(worldObjects)
    if not square then
        return
    end
    local option = context:addOption(getText("IGUI_TienLastSeenWhere_Debug"))
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(option, sub)
    sub:addOption(getText("IGUI_TienLastSeenWhere_Debug_PointHere"), playerNum, pointHere, square)
    if Arrow.GetTarget(playerNum) then
        sub:addOption(getText("IGUI_TienLastSeenWhere_Debug_Clear"), playerNum, Arrow.Clear)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
