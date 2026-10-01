require "TienLastSeenWhere_Core"

local LSW = TienLastSeenWhere

LSW.Options = {}

local Options = LSW.Options
local OPTIONS_ID = "TienLastSeenWhere"

Options.SEARCH_RULE = "searchRule"
Options.ARROW_COLOUR = "arrowColour"

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

if PZAPI and PZAPI.ModOptions then
    local options = PZAPI.ModOptions:create(OPTIONS_ID, getText("UI_TienLastSeenWhere_Title"))

    options:addDescription("UI_TienLastSeenWhere_Description")
    options:addSeparator()

    local rule = options:addComboBox(Options.SEARCH_RULE, getText("UI_TienLastSeenWhere_SearchRule"),
        getText("UI_TienLastSeenWhere_SearchRule_tooltip"))
    rule:addItem("UI_TienLastSeenWhere_SearchRule_Mine", true)
    rule:addItem("UI_TienLastSeenWhere_SearchRule_Shared", false)
    rule:addItem("UI_TienLastSeenWhere_SearchRule_Explored", false)
    rule:addItem("UI_TienLastSeenWhere_SearchRule_Everything", false)

    options:addColorPicker(Options.ARROW_COLOUR, getText("UI_TienLastSeenWhere_ArrowColour"), 1, 0.84, 0.31, 0.85,
        getText("UI_TienLastSeenWhere_ArrowColour_tooltip"))
end
