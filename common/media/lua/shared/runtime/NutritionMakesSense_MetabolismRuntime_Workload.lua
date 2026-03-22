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
    cache.lastLive = live

    local nowHours = getWorldHours()
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

    state = Runtime.ensureStateForPlayer(playerObj)

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
                local fuelRecoveryScale = Metabolism.getFuelRecoveryScale(state.fuel)

                if delta > 0 then
                    regenScale = Metabolism.getDeprivationRegenScale(deprivation) * fuelRecoveryScale
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
