require "TienLastSeenWhere_Core"
require "TienLastSeenWhere_Options"

local LSW = TienLastSeenWhere

LSW.Client = {}

local Client = LSW.Client

Client.TIMEOUT_MS = 20000

local states = {}
local nextRequest = 0

local function stateOf(playerNum)
    local state = states[playerNum]
    if not state then
        state = { summary = {}, pending = {}, summaryRequest = nil, findRequest = nil, find = {}, listeners = {} }
        states[playerNum] = state
    end
    return state
end

local function newRequest()
    nextRequest = nextRequest + 1
    return nextRequest
end

local function notify(state, event)
    for _, listener in pairs(state.listeners) do
        listener(event)
    end
end

function Client.Listen(playerNum, id, fn)
    stateOf(playerNum).listeners[id] = fn
end

function Client.Unlisten(playerNum, id)
    stateOf(playerNum).listeners[id] = nil
end

function Client.GetSummary(playerNum)
    return stateOf(playerNum).summary
end

function Client.GetFind(playerNum)
    return stateOf(playerNum).find
end

function Client.IsBusy(playerNum)
    local state = stateOf(playerNum)
    local now = getTimestampMs()
    local summarizing = state.summaryMs and now - state.summaryMs < Client.TIMEOUT_MS
    local finding = state.findMs and now - state.findMs < Client.TIMEOUT_MS
    return summarizing or finding or false
end

function Client.IsServerBusy(playerNum)
    return stateOf(playerNum).serverBusy == true and Client.IsBusy(playerNum)
end

function Client.RequestSummary(player)
    local state = stateOf(player:getPlayerNum())
    state.summaryRequest = newRequest()
    state.summaryMs = getTimestampMs()
    state.pending = {}
    LSW.ToServer(player, LSW.CMD_SUMMARY, {
        request = state.summaryRequest,
        playerNum = player:getPlayerNum(),
        rule = LSW.Options.GetSearchRule(),
    })
end

function Client.RequestFind(player, types)
    local state = stateOf(player:getPlayerNum())
    state.findRequest = newRequest()
    state.findMs = getTimestampMs()
    local kept = {}
    for _, fullType in ipairs(types) do
        kept[fullType] = state.find[fullType]
    end
    state.find = kept
    state.findTypes = types
    LSW.ToServer(player, LSW.CMD_FIND, {
        request = state.findRequest,
        playerNum = player:getPlayerNum(),
        rule = LSW.Options.GetSearchRule(),
        types = types,
    })
end

local function onSummary(state, args)
    if args.request ~= state.summaryRequest then
        return
    end
    state.summaryMs = getTimestampMs()
    state.serverBusy = args.busy == true
    for fullType, count in pairs(args.types or {}) do
        state.pending[fullType] = count
    end
    if args.last then
        state.summary = state.pending
        state.pending = {}
        state.rule = args.rule
        state.summaryMs = nil
        notify(state, "summary")
    end
end

local function onFind(state, args)
    if args.request ~= state.findRequest then
        return
    end
    state.findMs = getTimestampMs()
    state.serverBusy = args.busy == true
    for fullType, places in pairs(args.results or {}) do
        state.find[fullType] = places
    end
    state.rule = args.rule
    if args.last then
        for _, fullType in ipairs(state.findTypes or {}) do
            if state.find[fullType] == nil then
                state.find[fullType] = {}
            end
        end
        state.findMs = nil
    end
    notify(state, "find")
end

function Client.Handle(player, command, args)
    if type(args) ~= "table" then
        return
    end
    local state = stateOf(tonumber(args.playerNum) or 0)
    if command == LSW.REPLY_SUMMARY then
        onSummary(state, args)
    elseif command == LSW.REPLY_FIND then
        onFind(state, args)
    end
end

local function onServerCommand(module, command, args)
    if module ~= LSW.MODULE then
        return
    end
    Client.Handle(getPlayer(), command, args)
end

local function onGameStart()
    states = {}
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnGameStart.Add(onGameStart)
