require "TienLastSeenWhere_Core"

local LSW = TienLastSeenWhere

LSW.Jobs = {}

local Jobs = LSW.Jobs

Jobs.CHECK_EVERY = 25
Jobs.SERVER = { max = 8, min = 1, healthyMs = 110, strainedMs = 130 }
Jobs.CLIENT = { max = 3, min = 1, healthyMs = 34, strainedMs = 50 }
Jobs.ADAPT_MS = 1000
Jobs.RECOVER_AFTER = 3
Jobs.REPORT_MS = 300000

local jobs = {}
local order = {}
local sliceEndMs = 0
local counter = 0
local current = nil

local lastTickMs = nil
local avgIntervalMs = nil
local budgetMs = nil
local lastAdaptMs = 0
local healthyRuns = 0
local usedMs = 0
local usedWindowStartMs = 0
local usedPerSecond = 0
local lastReportMs = 0
local reportUsedMs = 0
local reportStarted = 0
local reportStrained = 0
local started = 0

local function profile()
    if isServer() then
        return Jobs.SERVER
    end
    return Jobs.CLIENT
end

local function currentBudget()
    if not budgetMs then
        budgetMs = profile().max
    end
    return budgetMs
end

local function remove(name)
    jobs[name] = nil
    for i = #order, 1, -1 do
        if order[i] == name then
            table.remove(order, i)
        end
    end
end

function Jobs.Start(name, fn)
    Jobs.Cancel(name)
    local job = { name = name, startedMs = getTimestampMs() }
    if coroutine then
        job.co = coroutine.create(fn)
    else
        job.run = fn
    end
    jobs[name] = job
    order[#order + 1] = name
    started = started + 1
    return job
end

function Jobs.Cancel(name)
    local job = jobs[name]
    if job then
        job.cancelled = true
        remove(name)
    end
end

function Jobs.IsRunning(name)
    return jobs[name] ~= nil
end

function Jobs.WaitWhile(fn)
    if not current or not current.co then
        return
    end
    while fn() do
        coroutine.yield()
    end
end

function Jobs.Finish(name)
    local job = jobs[name]
    if not job then
        return
    end
    remove(name)
    if not job.co then
        job.run()
        return
    end
    local saved = current
    current = nil
    while coroutine.status(job.co) ~= "dead" do
        local ok, err = coroutine.resume(job.co)
        if not ok then
            print("[TienLastSeenWhere] job " .. tostring(name) .. " failed: " .. tostring(err))
            break
        end
    end
    current = saved
end

function Jobs.IsStrained()
    return currentBudget() < profile().max
end

function Jobs.Stats()
    local now = getTimestampMs()
    local oldest = 0
    for _, job in pairs(jobs) do
        oldest = math.max(oldest, now - job.startedMs)
    end
    return {
        budgetMs = currentBudget(),
        maxBudgetMs = profile().max,
        tickMs = avgIntervalMs or 0,
        usedPerSecond = usedPerSecond,
        jobs = #order,
        oldestMs = oldest,
    }
end

function Jobs.Step()
    if not current or not current.co then
        return
    end
    counter = counter + 1
    if counter < Jobs.CHECK_EVERY then
        return
    end
    counter = 0
    if getTimestampMs() >= sliceEndMs then
        coroutine.yield()
    end
end

local function runOne(name)
    local job = jobs[name]
    if not job then
        return
    end
    current = job
    counter = 0
    local finished
    if job.co then
        local ok, err = coroutine.resume(job.co)
        if not ok then
            print("[TienLastSeenWhere] job " .. tostring(name) .. " failed: " .. tostring(err))
        end
        finished = coroutine.status(job.co) == "dead"
    else
        job.run()
        finished = true
    end
    current = nil
    if finished and jobs[name] == job then
        remove(name)
    end
end

local function adapt(now)
    if now - lastAdaptMs < Jobs.ADAPT_MS or not avgIntervalMs then
        return
    end
    lastAdaptMs = now
    local p = profile()
    local budget = currentBudget()
    if avgIntervalMs > p.strainedMs and #order > 0 then
        healthyRuns = 0
        if budget > p.min then
            budgetMs = math.max(p.min, math.floor(budget / 2))
            reportStrained = reportStrained + 1
            if isServer() then
                print(string.format("[TienLastSeenWhere] server ticks are slow (%d ms); search budget lowered to %d ms a tick",
                    math.floor(avgIntervalMs), budgetMs))
            end
        end
    elseif avgIntervalMs < p.healthyMs then
        healthyRuns = healthyRuns + 1
        if budget < p.max and healthyRuns >= Jobs.RECOVER_AFTER then
            healthyRuns = 0
            budgetMs = budget + 1
        end
    end
end

local function report(now)
    if not isServer() then
        return
    end
    if lastReportMs == 0 then
        lastReportMs = now
        return
    end
    if now - lastReportMs < Jobs.REPORT_MS then
        return
    end
    local seconds = (now - lastReportMs) / 1000
    lastReportMs = now
    if started == reportStarted and reportUsedMs == 0 then
        return
    end
    print(string.format(
        "[TienLastSeenWhere] load: %.1f ms/s for %d jobs over %d s, budget %d ms, ticks %d ms, slowdowns %d",
        reportUsedMs / math.max(1, seconds), started - reportStarted, math.floor(seconds), currentBudget(),
        math.floor(avgIntervalMs or 0), reportStrained))
    reportStarted = started
    reportUsedMs = 0
    reportStrained = 0
end

local function measure(now)
    if lastTickMs then
        local interval = now - lastTickMs
        if avgIntervalMs then
            avgIntervalMs = avgIntervalMs * 0.8 + interval * 0.2
        else
            avgIntervalMs = interval
        end
    end
    lastTickMs = now
    if now - usedWindowStartMs >= 1000 then
        usedPerSecond = usedMs * 1000 / math.max(1, now - usedWindowStartMs)
        usedWindowStartMs = now
        usedMs = 0
    end
end

local function onTick()
    local now = getTimestampMs()
    measure(now)
    adapt(now)
    report(now)
    if #order == 0 then
        return
    end
    sliceEndMs = now + currentBudget()
    local names = {}
    for i, name in ipairs(order) do
        names[i] = name
    end
    for _, name in ipairs(names) do
        if getTimestampMs() >= sliceEndMs then
            break
        end
        runOne(name)
    end
    if #order > 1 then
        local first = table.remove(order, 1)
        if jobs[first] then
            order[#order + 1] = first
        end
    end
    local spent = getTimestampMs() - now
    usedMs = usedMs + spent
    reportUsedMs = reportUsedMs + spent
end

Events.OnTick.Add(onTick)
