require "TienLastSeenWhere_Core"

TienLastSeenWhere.Keys = {}

local Keys = TienLastSeenWhere.Keys

Keys.SECTION = "[Last Seen Where]"
Keys.FIND = "LSW Find Item"

local function addKeyBindings()
    for _, bind in ipairs(keyBinding) do
        if bind.value == Keys.SECTION then
            return
        end
    end
    table.insert(keyBinding, { value = Keys.SECTION })
    table.insert(keyBinding, { value = Keys.FIND, key = 0 })
end

if keyBinding then
    addKeyBindings()
end

local function onKeyPressed(key)
    if not key or key == 0 then
        return
    end
    if not getCore():isKey(Keys.FIND, key) then
        return
    end
    local player = getSpecificPlayer(0)
    if not player or player:isDead() then
        return
    end
    TienLastSeenWhere.Window.Toggle(0)
end

Events.OnKeyPressed.Add(onKeyPressed)
