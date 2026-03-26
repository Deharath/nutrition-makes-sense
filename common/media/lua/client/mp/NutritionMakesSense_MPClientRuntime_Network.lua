NutritionMakesSense = NutritionMakesSense or {}

local MPClient = NutritionMakesSense.MPClientRuntime or {}
local state = MPClient._state or {}

local MP = MPClient.MP or {}
local isClientRuntime = MPClient.isClientRuntime
local getWorldAgeMinutes = MPClient.getWorldAgeMinutes
local getWallClockSeconds = MPClient.getWallClockSeconds
local getPlayerLabel = MPClient.getPlayerLabel
local normalizeIdComponent = MPClient.normalizeIdComponent
local Runtime = MPClient.Runtime or {}

local function workloadChanged(live)
    local previousAverage = tonumber(state.lastReportedWorkloadAverageMet) or nil
    local previousPeak = tonumber(state.lastReportedWorkloadPeakMet) or nil
    local previousSource = tostring(state.lastReportedWorkloadSource or "")
    local averageMet = tonumber(live and live.averageMet) or 0
    local peakMet = tonumber(live and live.peakMet) or averageMet
    local source = tostring(live and live.source or "")

    if previousAverage == nil or math.abs(previousAverage - averageMet) > 0.15 then
        return true
    end
    if previousPeak == nil or math.abs(previousPeak - peakMet) > 0.15 then
        return true
    end
    return previousSource ~= source
end

local function getRuntimeEventSessionId()
    if state.runtimeEventSessionId then
        return state.runtimeEventSessionId
    end

    local wallClockMs = tonumber(type(getTimestampMs) == "function" and getTimestampMs() or nil)
    if wallClockMs == nil then
        wallClockMs = (tonumber(getWallClockSeconds()) or 0) * 1000
    end

    local worldMinute = getWorldAgeMinutes()
    local uniqueToken = tostring({})
    local uniqueSuffix = uniqueToken:match("0x[%da-fA-F]+") or uniqueToken

    state.runtimeEventSessionId = string.format(
        "%s-%s-%s",
        normalizeIdComponent(wallClockMs, "0"),
        normalizeIdComponent(worldMinute, "0"),
        normalizeIdComponent(uniqueSuffix, "session")
    )
    return state.runtimeEventSessionId
end

function MPClient.getRuntimeEventSessionId()
    return getRuntimeEventSessionId()
end

local function makeEventId(playerObj, itemId, reason)
    state.nextEventSequence = tonumber(state.nextEventSequence) or 0
    state.nextEventSequence = state.nextEventSequence + 1
    return string.format(
        "%s:%s:%s:%s:%d",
        tostring(getPlayerLabel(playerObj, "player")),
        tostring(getRuntimeEventSessionId()),
        tostring(itemId or "item"),
        tostring(reason or "consume"),
        tonumber(state.nextEventSequence)
    )
end

MPClient.makeEventId = makeEventId

function MPClient.getSnapshot()
    return state.latestSnapshot
end

function MPClient.clearSnapshot()
    state.latestSnapshot = nil
end

function MPClient.requestSnapshot(reason, force)
    if not isClientRuntime() or type(sendClientCommand) ~= "function" then
        return false
    end

    local nowSecond = getWallClockSeconds()
    state.lastRequestWallSecond = tonumber(state.lastRequestWallSecond) or 0
    if (not force) and (nowSecond - state.lastRequestWallSecond) < 1 then
        return false
    end
    state.lastRequestWallSecond = nowSecond

    local args = {
        reason = tostring(reason or "client-request"),
        worldMinute = getWorldAgeMinutes(),
    }
    return pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.REQUEST_SNAPSHOT_COMMAND), args)
end

function MPClient.reportWorkload(playerObj, force, reason)
    if not isClientRuntime() or type(sendClientCommand) ~= "function" or not playerObj then
        return false
    end

    local live = Runtime.sampleReportedWorkload and Runtime.sampleReportedWorkload(playerObj) or nil
    if type(live) ~= "table" then
        return false
    end

    local averageMet = tonumber(live.averageMet) or 0
    local peakMet = tonumber(live.peakMet) or averageMet
    local source = tostring(live.source or "unknown")
    local nowSecond = getWallClockSeconds()
    local changed = workloadChanged(live)
    local lastSent = tonumber(state.lastWorkloadReportWallSecond) or 0
    local keepaliveSent = tonumber(state.lastWorkloadKeepaliveWallSecond) or 0
    local keepaliveDue = (nowSecond - keepaliveSent) >= 1

    if not force and not changed and not keepaliveDue then
        return false
    end
    if not force and changed == false and (nowSecond - lastSent) < 1 then
        return false
    end

    state.lastReportedWorkloadAverageMet = averageMet
    state.lastReportedWorkloadPeakMet = peakMet
    state.lastReportedWorkloadSource = source
    state.lastWorkloadReportWallSecond = nowSecond
    state.nextWorkloadSequence = (tonumber(state.nextWorkloadSequence) or 0) + 1
    if keepaliveDue or changed or force then
        state.lastWorkloadKeepaliveWallSecond = nowSecond
    end

    local args = {
        seq = tonumber(state.nextWorkloadSequence),
        averageMet = averageMet,
        peakMet = peakMet,
        source = source,
        sleepObserved = live.sleepObserved == true,
        worldHours = MPClient.getWorldHours and MPClient.getWorldHours() or nil,
        reason = tostring(reason or (changed and "workload-change" or "workload-keepalive")),
    }
    local ok = pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.REPORT_WORKLOAD_COMMAND), args)
    if ok and changed then
        print(string.format(
            "[NutritionMakesSense] [CLIENT_WORKLOAD] met=%.2f/%.2f source=%s reason=%s",
            averageMet,
            peakMet,
            source,
            tostring(args.reason)
        ))
    end
    return ok
end

return MPClient
