NutritionMakesSense = NutritionMakesSense or {}

local Runtime = NutritionMakesSense.MetabolismRuntime or {}

local Metabolism = Runtime.Metabolism or {}
local DEFAULT_WORKLOAD_SOURCE = Runtime.DEFAULT_WORKLOAD_SOURCE or "fallback_rest"
local scriptedWorkloadOverrideByPlayerKey = Runtime.scriptedWorkloadOverrideByPlayerKey or {}
local getPlayerCacheKey = Runtime.getPlayerCacheKey
local normalizeScriptedWorkloadOverride = Runtime.normalizeScriptedWorkloadOverride
local getPlayerLabel = Runtime.getPlayerLabel
local log = Runtime.log
local shouldRunAuthoritativeUpdates = Runtime.shouldRunAuthoritativeUpdates or function() return true end
local syncVisibleHunger = Runtime.syncVisibleHunger
local getActivityCache = Runtime.getActivityCache
local sampleLiveWorkload = Runtime.sampleLiveWorkload
local getWorldHours = Runtime.getWorldHours
local getPlayerStats = Runtime.getPlayerStats
local getCharacterStatValue = Runtime.getCharacterStatValue
local setStatValue = Runtime.setStatValue
local safeCall = Runtime.safeCall
local normalizeReportedWorkloadSample = Runtime.normalizeReportedWorkloadSample
local REPORTED_WORKLOAD_WINDOW_HOURS = Runtime.REPORTED_WORKLOAD_WINDOW_HOURS or (4 / 3600)

local function pruneReportedWorkloadSamples(samples, nowHours)
    if type(samples) ~= "table" then
        return {}
    end

    local kept = {}
    for _, sample in ipairs(samples) do
        local sampleHours = tonumber(sample.serverWorldHours) or nowHours
        if nowHours == nil or (nowHours - sampleHours) <= REPORTED_WORKLOAD_WINDOW_HOURS then
            kept[#kept + 1] = sample
        end
    end
    return kept
end

local function smoothReportedWorkload(samples)
    if type(samples) ~= "table" or #samples == 0 then
        return nil
    end

    local sumAverage = 0
    local peakMet = 0
    local sleepObserved = false
    local latestSource = "mp_reported"

    for _, sample in ipairs(samples) do
        sumAverage = sumAverage + (tonumber(sample.averageMet) or 0)
        peakMet = math.max(peakMet, tonumber(sample.peakMet) or tonumber(sample.averageMet) or 0)
        sleepObserved = sleepObserved or sample.sleepObserved == true
        latestSource = tostring(sample.source or latestSource)
    end

    return Metabolism.normalizeWorkload({
        averageMet = sumAverage / #samples,
        peakMet = peakMet,
        sleepObserved = sleepObserved,
        source = "mp_smoothed_" .. latestSource,
    })
end

local function accumulateWorkloadSample(playerObj, state, cache, live, nowHours)
    if not cache or not live then
        return live
    end

    cache.lastLive = live

    local previousHours = cache.lastSampleWorldHours
    cache.lastSampleWorldHours = nowHours or previousHours

    if nowHours == nil or previousHours == nil then
        return live
    end

    local deltaHours = math.max(0, nowHours - previousHours)
    deltaHours = math.min(deltaHours, 0.05)
    if deltaHours <= 0 then
        return live
    end

    cache.weightedMetHours = cache.weightedMetHours + (live.averageMet * deltaHours)
    cache.observedHours = cache.observedHours + deltaHours
    cache.peakMet = math.max(cache.peakMet or live.peakMet, live.peakMet or live.averageMet)
    cache.sleepObserved = cache.sleepObserved or live.sleepObserved == true
    cache.sourceHours[live.source or DEFAULT_WORKLOAD_SOURCE] = (cache.sourceHours[live.source or DEFAULT_WORKLOAD_SOURCE] or 0) + deltaHours
    cache.pendingBurnKcal = (cache.pendingBurnKcal or 0) + (Metabolism.getFuelBurnPerHourFromMet(live, state and state.weightKg) * deltaHours)

    if (live.averageMet or 0) >= Metabolism.MET_HEAVY_THRESHOLD then
        cache.heavyHours = cache.heavyHours + deltaHours
    end
    if (live.averageMet or 0) >= Metabolism.MET_VERY_HEAVY_THRESHOLD then
        cache.veryHeavyHours = cache.veryHeavyHours + deltaHours
    end

    local stats = getPlayerStats(playerObj)
    if state and stats then
        local endurance = getCharacterStatValue(stats, "ENDURANCE", "getEndurance")
        local previous = state.lastEnduranceObserved
        if endurance ~= nil then
            local controlled = endurance
            local regenScale = 1.0
            local deprivDrain = 0

            if previous ~= nil then
                local delta = endurance - previous
                local deprivation = tonumber(state.deprivation) or 0
                if delta > 0 then
                    regenScale = Metabolism.getDeprivationRegenScale(deprivation)
                    controlled = previous + delta * regenScale
                end

                if delta <= 0 and deprivation > Metabolism.DEPRIVATION_ENDURANCE_ONSET then
                    deprivDrain = Metabolism.getDeprivationActivityDrain(deprivation, live.averageMet) * deltaHours
                    controlled = controlled - deprivDrain
                end
            end

            controlled = Metabolism.clamp(controlled, 0, 1)
            if previous ~= nil and math.abs(controlled - endurance) > 0.0002 then
                setStatValue(stats, "ENDURANCE", "setEndurance", controlled)
            end

            state.lastEnduranceObserved = controlled
            state.lastEnduranceRegenScale = regenScale
            state.lastEnduranceDeprivDrain = deprivDrain
            cache.appliedEnduranceDrain = (cache.appliedEnduranceDrain or 0) + math.max(0, endurance - controlled)
        end

        local fatigueAccel = Metabolism.getFatigueAccelFactor(state.deprivation)
        if fatigueAccel > 1.0 and not live.sleepObserved then
            local vanillaFatiguePerHour = 0.042
            local extraFatigue = vanillaFatiguePerHour * (fatigueAccel - 1.0) * deltaHours
            if extraFatigue > 0 then
                local currentFatigue = tonumber(safeCall(stats, "getFatigue")) or 0
                if currentFatigue < 0.95 then
                    safeCall(stats, "setFatigue", math.min(0.95, currentFatigue + extraFatigue))
                    cache.appliedFatigueAccel = (cache.appliedFatigueAccel or 0) + extraFatigue
                end
            end
        end
    end

    return live
end

function Runtime.setScriptedWorkloadOverride(playerObj, workload, reason)
    local key = getPlayerCacheKey(playerObj)
    local normalized = normalizeScriptedWorkloadOverride(workload, reason)
    if not key or not normalized then
        return nil
    end

    scriptedWorkloadOverrideByPlayerKey[key] = normalized
    return normalized
end

function Runtime.getScriptedWorkloadOverride(playerObj)
    local key = getPlayerCacheKey(playerObj)
    if not key then
        return nil
    end
    return scriptedWorkloadOverrideByPlayerKey[key]
end

function Runtime.clearScriptedWorkloadOverride(playerObj, reason)
    local key = getPlayerCacheKey(playerObj)
    if not key then
        return false
    end

    local existing = scriptedWorkloadOverrideByPlayerKey[key]
    scriptedWorkloadOverrideByPlayerKey[key] = nil
    if existing then
        log(string.format(
            "[SCRIPTED_WORKLOAD_CLEAR] player=%s source=%s reason=%s",
            tostring(getPlayerLabel(playerObj)),
            tostring(existing.source or "scripted_override"),
            tostring(reason or "clear-scripted-override")
        ))
    end
    return existing ~= nil
end

function Runtime.reportPlayerWorkload(playerObj, workload, clientWorldHours, reason, seq)
    if not shouldRunAuthoritativeUpdates() or not playerObj or type(normalizeReportedWorkloadSample) ~= "function" then
        return nil
    end

    local cache = getActivityCache(playerObj)
    if not cache then
        return nil
    end

    local normalizedWorkload = normalizeReportedWorkloadSample(workload)
    if not normalizedWorkload then
        return nil
    end

    local reportedSeq = tonumber(seq) or nil
    local previousSeq = tonumber(cache.reportedWorkloadSeq) or nil
    if reportedSeq ~= nil and previousSeq ~= nil and reportedSeq <= previousSeq then
        log(string.format(
            "[MP_WORKLOAD_DROP] player=%s source=%s seq=%d previous=%d reason=%s",
            tostring(getPlayerLabel(playerObj)),
            tostring(normalizedWorkload.source or "mp_reported"),
            tonumber(reportedSeq),
            tonumber(previousSeq),
            tostring(reason or "client-report")
        ))
        return nil
    end

    local reportedClientWorldHours = tonumber(clientWorldHours) or nil
    local nowHours = getWorldHours()
    local previousWorkload = type(cache.reportedWorkload) == "table" and cache.reportedWorkload or nil
    if previousWorkload then
        local state = Runtime.ensureStateForPlayer(playerObj)
        accumulateWorkloadSample(playerObj, state, cache, previousWorkload, nowHours)
    end

    local samples = pruneReportedWorkloadSamples(cache.reportedWorkloadSamples, nowHours)
    samples[#samples + 1] = {
        seq = reportedSeq,
        serverWorldHours = nowHours,
        clientWorldHours = reportedClientWorldHours,
        averageMet = normalizedWorkload.averageMet,
        peakMet = normalizedWorkload.peakMet,
        sleepObserved = normalizedWorkload.sleepObserved == true,
        source = normalizedWorkload.source,
    }
    cache.reportedWorkloadSamples = pruneReportedWorkloadSamples(samples, nowHours)

    local smoothedWorkload = smoothReportedWorkload(cache.reportedWorkloadSamples) or normalizedWorkload
    cache.reportedWorkload = smoothedWorkload
    cache.reportedWorkloadSeq = reportedSeq or previousSeq
    cache.reportedWorkloadClientWorldHours = reportedClientWorldHours
    cache.reportedWorkloadLastSeenHours = nowHours or cache.reportedWorkloadLastSeenHours
    cache.lastLive = smoothedWorkload

    local previousAverage = tonumber(previousWorkload and previousWorkload.averageMet) or nil
    local previousPeak = tonumber(previousWorkload and previousWorkload.peakMet) or nil
    local previousSource = tostring(previousWorkload and previousWorkload.source or "")
    if previousAverage == nil
        or math.abs(previousAverage - smoothedWorkload.averageMet) > 0.10
        or math.abs((previousPeak or previousAverage or 0) - smoothedWorkload.peakMet) > 0.10
        or previousSource ~= tostring(smoothedWorkload.source or "") then
        log(string.format(
            "[MP_WORKLOAD] player=%s raw=%.2f/%.2f smooth=%.2f/%.2f source=%s previous=%.2f/%.2f source=%s reason=%s",
            tostring(getPlayerLabel(playerObj)),
            tonumber(normalizedWorkload.averageMet or 0),
            tonumber(normalizedWorkload.peakMet or 0),
            tonumber(smoothedWorkload.averageMet or 0),
            tonumber(smoothedWorkload.peakMet or 0),
            tostring(smoothedWorkload.source or "mp_reported"),
            tonumber(previousAverage or 0),
            tonumber(previousPeak or previousAverage or 0),
            tostring(previousSource ~= "" and previousSource or "none"),
            tostring(reason or "client-report")
        ))
    end

    return smoothedWorkload
end

function Runtime.observePlayerWorkload(playerObj, reason)
    if not shouldRunAuthoritativeUpdates() or not playerObj then
        return nil
    end

    local state = Runtime.ensureStateForPlayer(playerObj)
    if state then
        syncVisibleHunger(playerObj, state, reason or "observe-workload")
    end

    local cache = getActivityCache(playerObj)
    if not cache then
        return nil
    end

    local live = sampleLiveWorkload(playerObj)
    local nowHours = getWorldHours()
    state = Runtime.ensureStateForPlayer(playerObj)
    return accumulateWorkloadSample(playerObj, state, cache, live, nowHours)
end

function Runtime.getCurrentWorkloadSnapshot(playerObj)
    if not playerObj then
        return nil
    end

    local cache = getActivityCache(playerObj)
    local live = sampleLiveWorkload(playerObj)
    if cache then
        cache.lastLive = live
    end
    return live
end

return Runtime
