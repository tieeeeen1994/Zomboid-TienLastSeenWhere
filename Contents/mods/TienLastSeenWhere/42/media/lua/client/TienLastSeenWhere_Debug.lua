require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Arrow"

local Arrow = TienLastSeenWhere.Arrow

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
    Arrow.SetTarget(playerNum, square:getX(), square:getY(), square:getZ())
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
    local floor = sub:addOption(getText("IGUI_TienLastSeenWhere_Debug_DrawFloor"), Arrow.MODE_FLOOR, Arrow.SetMode)
    sub:setOptionChecked(floor, Arrow.mode == Arrow.MODE_FLOOR)
    local overlay = sub:addOption(getText("IGUI_TienLastSeenWhere_Debug_DrawOverlay"), Arrow.MODE_OVERLAY, Arrow.SetMode)
    sub:setOptionChecked(overlay, Arrow.mode == Arrow.MODE_OVERLAY)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
