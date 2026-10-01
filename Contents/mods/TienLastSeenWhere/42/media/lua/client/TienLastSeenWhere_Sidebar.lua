require "ISUI/ISEquippedItem"
require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Window"

local LSW = TienLastSeenWhere

LSW.Sidebar = {}

local Sidebar = LSW.Sidebar

Sidebar.INTERNAL = "TIENLASTSEENWHERE"
Sidebar.SPACING = 15

local function iconPath(size, state)
    local px = string.format("%d", size)
    return "media/ui/Sidebar/" .. px .. "/TienLastSeenWhere_" .. state .. "_" .. px .. ".png"
end

local vanillaInitialise = ISEquippedItem.initialise

function ISEquippedItem:initialise()
    vanillaInitialise(self)
    local inventory = self.invBtn
    if not inventory then
        return
    end
    local size = inventory:getWidth()
    local top = inventory:getBottom() + Sidebar.SPACING
    local shift = inventory:getHeight() + Sidebar.SPACING
    for _, child in pairs(self:getChildren()) do
        if child ~= inventory and child:getY() >= inventory:getBottom() then
            child:setY(child:getY() + shift)
        end
    end

    local button = ISButton:new(0, top, inventory:getWidth(), inventory:getHeight(), "", self,
        ISEquippedItem.onOptionMouseDown)
    button.internal = Sidebar.INTERNAL
    button.lswIconOff = getTexture(iconPath(size, "Off"))
    button.lswIconOn = getTexture(iconPath(size, "On"))
    button:setImage(button.lswIconOff)
    button:initialise()
    button:instantiate()
    button:setDisplayBackground(false)
    button:ignoreWidthChange()
    button:ignoreHeightChange()
    self:addChild(button)
    self:addMouseOverToolTipItem(button, getText("IGUI_TienLastSeenWhere_SidebarTooltip"))
    self.tienLastSeenWhereBtn = button
    self:shrinkWrap()
end

local vanillaPrerender = ISEquippedItem.prerender

function ISEquippedItem:prerender()
    vanillaPrerender(self)
    local button = self.tienLastSeenWhereBtn
    if not button then
        return
    end
    if getCore():getGameMode() == "Tutorial" then
        button:setVisible(false)
        return
    end
    local window = LSW.Window.instances[self.chr:getPlayerNum()]
    local open = window ~= nil and window:isVisible()
    button:setImage(open and button.lswIconOn or button.lswIconOff)
end

local vanillaOnOptionMouseDown = ISEquippedItem.onOptionMouseDown

function ISEquippedItem:onOptionMouseDown(button, x, y)
    if button.internal == Sidebar.INTERNAL then
        if not self.chr:isDead() then
            LSW.Window.Toggle(self.chr:getPlayerNum())
        end
        return
    end
    return vanillaOnOptionMouseDown(self, button, x, y)
end
