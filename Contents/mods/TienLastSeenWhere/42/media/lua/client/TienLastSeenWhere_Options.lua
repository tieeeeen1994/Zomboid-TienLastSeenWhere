require "TienLastSeenWhere_Core"

local LSW = TienLastSeenWhere

LSW.Options = {}

local Options = LSW.Options
local OPTIONS_ID = "TienLastSeenWhere"

Options.SEARCH_RULE = "searchRule"
Options.ARROW_COLOUR = "arrowColour"
Options.ARROW_SIZE = "arrowSize"

local function getOption(id)
    if not PZAPI or not PZAPI.ModOptions then
        return nil
    end
    local options = PZAPI.ModOptions:getOptions(OPTIONS_ID)
    return options and options:getOption(id)
end

function Options.GetSearchRule()
    local option = getOption(Options.SEARCH_RULE)
    local index = option and option:getValue()
    if type(index) ~= "number" then
        return LSW.RULE_MINE
    end
    return LSW.RULE_MINE + index - 1
end

function Options.SetSearchRule(rule)
    local option = getOption(Options.SEARCH_RULE)
    if not option then
        return
    end
    local index = math.max(1, math.min(rule, LSW.RULE_EXPLORED) - LSW.RULE_MINE + 1)
    if option:getValue() ~= index then
        option:setValue(index)
        PZAPI.ModOptions:save()
    end
end

function Options.GetEffectiveRule()
    return LSW.ResolveRule(Options.GetSearchRule())
end

function Options.GetArrowColour()
    local option = getOption(Options.ARROW_COLOUR)
    local colour = option and option:getValue()
    if type(colour) ~= "table" then
        return { r = 1, g = 0.84, b = 0.31, a = 0.85 }
    end
    return { r = colour.r or 1, g = colour.g or 1, b = colour.b or 1, a = math.max(0.15, colour.a or 0.85) }
end

function Options.GetArrowScale()
    local option = getOption(Options.ARROW_SIZE)
    local percent = option and tonumber(option:getValue()) or 100
    return math.max(0.5, math.min(2, percent / 100))
end

if PZAPI and PZAPI.ModOptions then
    local options = PZAPI.ModOptions:create(OPTIONS_ID, "UI_TienLastSeenWhere_Title")

    options:addDescription("UI_TienLastSeenWhere_Description")
    options:addSeparator()

    local rule = options:addComboBox(Options.SEARCH_RULE, "UI_TienLastSeenWhere_SearchRule",
        "UI_TienLastSeenWhere_SearchRule_tooltip")
    rule:addItem("UI_TienLastSeenWhere_SearchRule_Mine", true)
    rule:addItem("UI_TienLastSeenWhere_SearchRule_Shared", false)
    rule:addItem("UI_TienLastSeenWhere_SearchRule_Explored", false)

    options:addColorPicker(Options.ARROW_COLOUR, "UI_TienLastSeenWhere_ArrowColour", 1, 0.84, 0.31, 0.85,
        "UI_TienLastSeenWhere_ArrowColour_tooltip")

    options:addSlider(Options.ARROW_SIZE, "UI_TienLastSeenWhere_ArrowSize", 50, 200, 10, 100,
        "UI_TienLastSeenWhere_ArrowSize_tooltip")

    Events.OnGameStart.Add(function()
        local option = getOption(Options.SEARCH_RULE)
        local index = option and option:getValue()
        if type(index) == "number" and index > LSW.RULE_EXPLORED - LSW.RULE_MINE + 1 then
            option:setValue(LSW.RULE_EXPLORED - LSW.RULE_MINE + 1)
        end
    end)
end
