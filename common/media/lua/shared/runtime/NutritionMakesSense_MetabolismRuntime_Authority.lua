NutritionMakesSense = NutritionMakesSense or {}

local Runtime = NutritionMakesSense.MetabolismRuntime or {}

local Metabolism = Runtime.Metabolism or {}
local STATE_KEY = Runtime.STATE_KEY
local getModData = Runtime.getModData
local getPlayerStats = Runtime.getPlayerStats
local getPlayerBodyDamage = Runtime.getPlayerBodyDamage
local getPlayerNutrition = Runtime.getPlayerNutrition
local getVisibleHungerValue = Runtime.getVisibleHungerValue
local normalizeVisibleHungerInput = Runtime.normalizeVisibleHungerInput
local setStatValue = Runtime.setStatValue
local safeCall = Runtime.safeCall
local clamp = Runtime.clamp
local refreshDerivedState = Runtime.refreshDerivedState
local seedHealthFromFood = Runtime.seedHealthFromFood
local syncVisibleWeight = Runtime.syncVisibleWeight
local syncProteinHealing = Runtime.syncProteinHealing
local setNutritionAnchor = Runtime.setNutritionAnchor
local getPlayerLabel = Runtime.getPlayerLabel
local normalizeDeposit = Runtime.normalizeDeposit
local shouldRunAuthoritativeUpdates = Runtime.shouldRunAuthoritativeUpdates or function() return true end
local log = Runtime.log
local samplePositiveNutritionDelta = Runtime.samplePositiveNutritionDelta
local hasMeaningfulDeposit = Runtime.hasMeaningfulDeposit
local importLiveVisibleHungerDrop = Runtime.importLiveVisibleHungerDrop
local getWorldHours = Runtime.getWorldHours
local resolveStatsDecreaseMultiplier = Runtime.resolveStatsDecreaseMultiplier or function() return 1.0 end
local consumeWorkloadSummary = Runtime.consumeWorkloadSummary
local removeEndurance = Runtime.removeEndurance
local eachKnownPlayer = Runtime.eachKnownPlayer
local DebugSupport = NutritionMakesSense.DebugSupport or {}
local PENDING_HUNGER_MAX_AGE = 2
local ACTIVE_ELAPSED_CAP_HOURS = 0.25
local MP_RESUME_GAP_THRESHOLD_HOURS = 0.50

local function isMultiplayerAuthorityRuntime()
    if type(isClient) == "function" and isClient() == true then
        return true
    end
    if type(isServer) == "function" and isServer() == true then
        return true
    end
    return false
end

local function isResumeReason(reason)
    local reasonText = string.lower(tostring(reason or ""))
    return string.find(reasonText, "bootstrap", 1, true) ~= nil
        or string.find(reasonText, "create-player", 1, true) ~= nil
        or string.find(reasonText, "resume", 1, true) ~= nil
        or string.find(reasonText, "request", 1, true) ~= nil
end

local function resolveActiveElapsedHours(state, nowHours, reason)
    if nowHours == nil then
        return 0, {
            rawHours = 0,
            mode = "missing-clock",
        }
    end

    local previousHours = tonumber(state and state.lastWorldHours) or nil
    if previousHours == nil then
        return 0, {
            rawHours = 0,
            mode = "seed-clock",
        }
    end

    local rawElapsed = math.max(0, nowHours - previousHours)
    if rawElapsed <= 0 then
        return 0, {
            rawHours = rawElapsed,
            mode = "no-elapsed",
        }
    end

    local pendingResumeHours = tonumber(state and state.pendingResumeWorldHours) or nil
    local pendingResumeReason = tostring(state and state.pendingResumeReason or reason or "resume")
    if pendingResumeHours ~= nil and pendingResumeHours >= previousHours then
        state.pendingResumeWorldHours = nil
        state.pendingResumeReason = nil
        return 0, {
            rawHours = rawElapsed,
            mode = "resume-freeze",
            reason = pendingResumeReason,
        }
    end

    if isMultiplayerAuthorityRuntime() and rawElapsed >= MP_RESUME_GAP_THRESHOLD_HOURS then
        return 0, {
            rawHours = rawElapsed,
            mode = "mp-gap-freeze",
        }
    end

    if rawElapsed > ACTIVE_ELAPSED_CAP_HOURS then
        return ACTIVE_ELAPSED_CAP_HOURS, {
            rawHours = rawElapsed,
            mode = "runtime-stall-clamp",
        }
    end

    return rawElapsed, {
        rawHours = rawElapsed,
        mode = "active",
    }
end

function Runtime.debugSetStateFields(playerObj, updates, reason)
    if not playerObj or type(updates) ~= "table" then
        return nil
    end

    local modData = getModData(playerObj)
    if not modData then
        return nil
    end

    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return nil
    end

    local changed = {}
    for fieldName, rawValue in pairs(updates) do
        if fieldName == "fuel"
            or fieldName == "proteins"
            or fieldName == "weightKg"
            or fieldName == "weightController"
            or fieldName == "weightBalanceKcal"
            or fieldName == "underfeedingDebtKcal"
            or fieldName == "deprivation"
            or fieldName == "satietyBuffer" then
            local before = state[fieldName]
            state[fieldName] = tonumber(rawValue) or before
            changed[#changed + 1] = {
                field = fieldName,
                before = before,
                after = state[fieldName],
            }
        end
    end

    if #changed == 0 then
        return Metabolism.copyState(state)
    end

    state = refreshDerivedState(state, reason or "debug-set")
    modData[STATE_KEY] = state

    Runtime.syncVisibleShell(playerObj, reason or "mp-authority")

    for _, entry in ipairs(changed) do
        log(string.format(
            "[NMS_DEV_SET] player=%s field=%s old=%s new=%s reason=%s",
            tostring(getPlayerLabel(playerObj)),
            tostring(entry.field),
            tostring(entry.before),
            tostring(state[entry.field]),
            tostring(reason or "debug-set")
        ))
    end

    return Metabolism.copyState(state)
end

function Runtime.debugResetState(playerObj, reason)
    if not playerObj then
        return nil
    end

    local modData = getModData(playerObj)
    if not modData then
        return nil
    end

    local previous = Runtime.ensureStateForPlayer(playerObj)
    local stats = getPlayerStats(playerObj)
    local bodyDamage = getPlayerBodyDamage(playerObj)
    local state = Metabolism.newState({
        initialized = true,
        fuel = 1300,
        weightKg = Metabolism.DEFAULT_WEIGHT_KG,
        proteins = Metabolism.getDefaultProteinAdequacy(Metabolism.DEFAULT_WEIGHT_KG),
        weightController = 0,
        weightBalanceKcal = 0,
        underfeedingDebtKcal = 0,
        satietyBuffer = 0,
        deprivation = 0,
        lastWorldHours = getWorldHours(),
        lastMetAverage = Metabolism.MET_REST,
        lastMetPeak = Metabolism.MET_REST,
        lastEffectiveEnduranceMet = Metabolism.MET_REST,
        lastWorkTier = Metabolism.WORK_TIER_REST,
        lastMetSource = "debug-reset",
        lastObservedHours = 0,
        lastHeavyHours = 0,
        lastVeryHeavyHours = 0,
        visibleHunger = clamp(getVisibleHungerValue(stats) or 0, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX),
        lastSatietyQuality = 0,
        lastSatietyContribution = 0,
        lastSatietyReturnFactor = 1.0,
        lastMealHungerDrop = 0,
        lastMealHungerObserved = false,
        pendingObservedHungerDrop = 0,
        pendingObservedHungerAge = 0,
        lastBurnKcal = 0,
        lastDepositKcal = 0,
        depositSequence = tonumber(previous and previous.depositSequence) or 0,
        lastBaseHungerGain = 0,
        lastPassiveHungerGain = 0,
        lastCorrectionGain = 0,
        lastExtraEnduranceDrain = 0,
        lastWeightDeltaKg = 0,
        lastWeightRateKgPerWeek = 0,
        lastUnderfeedingDebtKcal = 0,
        lastDeprivationTarget = 0,
        lastWeightBalanceKcal = 0,
        lastWeightControllerTarget = 0,
        lastTraceReason = tostring(reason or "debug-reset"),
        baseHealthFromFood = tonumber(previous and previous.baseHealthFromFood) or seedHealthFromFood(bodyDamage),
    })
    state = refreshDerivedState(state, reason or "debug-reset")
    modData[STATE_KEY] = state

    local nutrition = getPlayerNutrition(playerObj)
    syncVisibleWeight(nutrition, state)
    syncProteinHealing(bodyDamage, state)
    setNutritionAnchor(nutrition)

    log(string.format(
        "[NMS_DEV_RESET] player=%s fuel=%.1f proteins=%.1f weight=%.3f reason=%s",
        tostring(getPlayerLabel(playerObj)),
        tonumber(state.fuel or 0),
        tonumber(state.proteins or 0),
        tonumber(state.weightKg or 0),
        tostring(reason or "debug-reset")
    ))

    return Metabolism.copyState(state)
end

function Runtime.debugSetVisibleBaselines(playerObj, fields, reason)
    if not playerObj or type(fields) ~= "table" then
        return nil
    end

    local stats = getPlayerStats(playerObj)
    local bodyDamage = getPlayerBodyDamage(playerObj)
    local changed = {}

    local hunger = normalizeVisibleHungerInput(fields.hunger)
    if hunger ~= nil then
        local before = getVisibleHungerValue(stats)
        if setStatValue(stats, "HUNGER", "setHunger", hunger) then
            changed[#changed + 1] = string.format("hunger:%s->%s", tostring(before), tostring(hunger))
        end
        local state = Runtime.ensureStateForPlayer(playerObj)
        if state then
            state.visibleHunger = clamp(hunger, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
            state.lastSyncedHunger = state.visibleHunger
            state.lastHungerBand = Metabolism.getVisibleHungerBand(state.visibleHunger)
        end
    end

    local endurance = tonumber(fields.endurance)
    if endurance ~= nil then
        local before = stats and (tonumber(safeCall(stats, "getEndurance")) or 0) or nil
        if setStatValue(stats, "ENDURANCE", "setEndurance", endurance) then
            changed[#changed + 1] = string.format("endurance:%s->%s", tostring(before), tostring(endurance))
        end
    end

    local fatigue = tonumber(fields.fatigue)
    if fatigue ~= nil then
        local before = stats and (tonumber(safeCall(stats, "getFatigue")) or 0) or nil
        if setStatValue(stats, "FATIGUE", "setFatigue", fatigue) then
            changed[#changed + 1] = string.format("fatigue:%s->%s", tostring(before), tostring(fatigue))
        end
    end

    local healthFromFood = tonumber(fields.healthFromFood)
    if healthFromFood ~= nil and bodyDamage then
        local before = tonumber(safeCall(bodyDamage, "getHealthFromFood")) or nil
        if safeCall(bodyDamage, "setHealthFromFood", healthFromFood) ~= nil then
            changed[#changed + 1] = string.format("healthFromFood:%s->%s", tostring(before), tostring(healthFromFood))
        end
    end

    local healthFromFoodTimer = tonumber(fields.healthFromFoodTimer)
    if healthFromFoodTimer ~= nil and bodyDamage then
        local before = tonumber(safeCall(bodyDamage, "getHealthFromFoodTimer")) or nil
        if safeCall(bodyDamage, "setHealthFromFoodTimer", healthFromFoodTimer) ~= nil then
            changed[#changed + 1] = string.format("healthFromFoodTimer:%s->%s", tostring(before), tostring(healthFromFoodTimer))
        end
    end

    if #changed == 0 then
        return {}
    end

    log(string.format(
        "[NMS_DEV_VISIBLE] player=%s changes=%s reason=%s",
        tostring(getPlayerLabel(playerObj)),
        table.concat(changed, ","),
        tostring(reason or "debug-visible")
    ))

    return changed
end

function Runtime.applyAuthoritativeDeposit(playerObj, values, reason, options)
    if not playerObj then
        return nil
    end

    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return nil
    end

    local normalized = normalizeDeposit(values)
    local report = Metabolism.applyFoodValues(state, normalized, 1, reason or "mp-authority")

    Runtime.syncVisibleShell(playerObj, reason or "mp-authority")

    return report, state
end

function Runtime.updatePlayer(playerObj, reason)
    if not shouldRunAuthoritativeUpdates() or not playerObj then
        return
    end

    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return
    end

    local playerLabel = getPlayerLabel(playerObj)
    local nutrition = getPlayerNutrition(playerObj)
    local observedDelta = samplePositiveNutritionDelta(nutrition)
    local observedDeltaDetected = hasMeaningfulDeposit(observedDelta)

    local playerStats = getPlayerStats(playerObj)
    local preVisibleHunger = tonumber(state.visibleHunger) or 0
    if observedDeltaDetected and type(importLiveVisibleHungerDrop) == "function" then
        importLiveVisibleHungerDrop(state, playerStats)
    end

    -- Apply observed vanilla nutrition deltas anywhere we are running authoritative updates.
    -- Dedicated servers, listen servers, and solo runtimes must all credit the same intake path.
    if observedDeltaDetected then
        local observedHungerDrop = clamp(tonumber(state.pendingObservedHungerDrop) or 0, 0, 1)
        local hungerObserved = observedHungerDrop > 0
        state.pendingObservedHungerDrop = 0
        state.pendingObservedHungerAge = 0
        state.lastMealHungerDrop = observedHungerDrop
        state.lastMealHungerObserved = hungerObserved

        Runtime.applyAuthoritativeDeposit(playerObj, observedDelta, "vanilla-nutrition-delta")
        if type(DebugSupport.noteConsumeEvent) == "function" then
            DebugSupport.noteConsumeEvent({
                reason = tostring(reason or "vanilla-nutrition-delta"),
                item = "",
                item_known = false,
                provenance = "observed-nutrition-delta",
                consume_source = "runtime-observed-delta",
                fraction = 1,
                pre_visible_hunger = preVisibleHunger,
                target_visible_hunger = tonumber(state.visibleHunger) or preVisibleHunger,
                kcal = tonumber(observedDelta and observedDelta.kcal) or 0,
                carbs = tonumber(observedDelta and observedDelta.carbs) or 0,
                fats = tonumber(observedDelta and observedDelta.fats) or 0,
                proteins = tonumber(observedDelta and observedDelta.proteins) or 0,
                observed_hunger_drop = observedHungerDrop,
                hunger_observed = hungerObserved,
            })
        end
    else
        local pendingDrop = tonumber(state.pendingObservedHungerDrop) or 0
        if pendingDrop > 0 then
            state.pendingObservedHungerAge = (tonumber(state.pendingObservedHungerAge) or 0) + 1
            if state.pendingObservedHungerAge > PENDING_HUNGER_MAX_AGE then
                state.pendingObservedHungerDrop = 0
                state.pendingObservedHungerAge = 0
            end
        end
    end

    if type(setNutritionAnchor) == "function" then
        -- Vanilla nutrition is NMS's transient intake mailbox. Keep it anchored every
        -- authority pass so vanilla burn cannot push it negative and hide later food.
        setNutritionAnchor(nutrition)
    end

    local zoneBefore = Metabolism.getFuelZone(state.fuel)

    local nowHours = getWorldHours()
    local elapsedHours, elapsedContext = resolveActiveElapsedHours(state, nowHours, reason)
    state.lastWorldHours = nowHours or state.lastWorldHours
    state.lastActiveElapsedHours = elapsedHours
    state.lastRawElapsedHours = tonumber(elapsedContext and elapsedContext.rawHours) or elapsedHours
    state.lastElapsedMode = tostring(elapsedContext and elapsedContext.mode or "active")

    if elapsedContext and elapsedContext.mode == "resume-freeze" then
        log(string.format(
            "[MP_RESUME_FREEZE] player=%s skippedHours=%.3f reason=%s resumeReason=%s",
            tostring(playerLabel),
            tonumber(elapsedContext.rawHours or 0),
            tostring(reason or "update"),
            tostring(elapsedContext.reason or "resume")
        ))
    elseif elapsedContext and elapsedContext.mode == "mp-gap-freeze" then
        log(string.format(
            "[MP_OFFLINE_GAP_FREEZE] player=%s skippedHours=%.3f reason=%s threshold=%.3f",
            tostring(playerLabel),
            tonumber(elapsedContext.rawHours or 0),
            tostring(reason or "update"),
            tonumber(MP_RESUME_GAP_THRESHOLD_HOURS)
        ))
    elseif elapsedContext and elapsedContext.mode == "runtime-stall-clamp" then
        log(string.format(
            "[RUNTIME_STALL_CLAMP] player=%s rawHours=%.3f appliedHours=%.3f reason=%s",
            tostring(playerLabel),
            tonumber(elapsedContext.rawHours or 0),
            tonumber(elapsedHours or 0),
            tostring(reason or "update")
        ))
    end

    local workload = consumeWorkloadSummary(playerObj)
    local traitEffects = Runtime.resolveTraitEffects and Runtime.resolveTraitEffects(playerObj) or nil
    local advanceReport = Metabolism.advanceState(state, elapsedHours, workload, {
        reason = reason or workload.workTier or "workload",
        traitEffects = traitEffects,
        hungerRateMultiplier = resolveStatsDecreaseMultiplier(),
    })
    if workload.appliedEnduranceDrain == nil then
        removeEndurance(playerObj, playerStats, advanceReport.extraEnduranceDrain or 0)
    end
    Runtime.syncVisibleShell(playerObj, reason or workload.workTier or "workload")

    local zoneAfter = Metabolism.getFuelZone(state.fuel)
    if zoneBefore ~= zoneAfter then
        log(string.format(
            "[FUEL_ZONE] player=%s from=%s to=%s fuel=%.1f tier=%s met=%.2f correction=%.4f",
            tostring(playerLabel),
            tostring(zoneBefore),
            tostring(zoneAfter),
            tonumber(state.fuel or 0),
            tostring(state.lastWorkTier or workload.workTier or "--"),
            tonumber(advanceReport.averageMet or state.lastMetAverage or Metabolism.MET_REST),
            tonumber(advanceReport.visibleHungerGain or 0)
        ))
    end

    if math.abs(tonumber(advanceReport.weightDeltaKg or 0)) >= 0.001 or tonumber(advanceReport.extraEnduranceDrain or 0) > 0 then
        log(string.format(
            "[BODY_STATE] player=%s weight=%.3f deltaKg=%.4f controller=%.2f trait=%s metAvg=%.2f metPeak=%.2f extraEndurance=%.4f",
            tostring(playerLabel),
            tonumber(state.weightKg or Metabolism.DEFAULT_WEIGHT_KG),
            tonumber(advanceReport.weightDeltaKg or 0),
            tonumber(state.weightController or 0),
            tostring(state.lastWeightTrait or "Normal"),
            tonumber(advanceReport.averageMet or state.lastMetAverage or Metabolism.MET_REST),
            tonumber(advanceReport.peakMet or state.lastMetPeak or Metabolism.MET_REST),
            tonumber(advanceReport.extraEnduranceDrain or 0)
        ))
    end

end

function Runtime.markPlayerSessionResumed(playerObj, reason)
    if not playerObj then
        return nil
    end

    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return nil
    end

    local nowHours = getWorldHours() or state.lastWorldHours
    state.pendingResumeWorldHours = nowHours
    state.pendingResumeReason = tostring(reason or "session-resume")
    return state
end

function Runtime.bootstrapPlayer(playerObj, reason)
    if not playerObj then
        return nil
    end

    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return nil
    end

    state.lastWorldHours = getWorldHours() or state.lastWorldHours
    if isResumeReason(reason) then
        state.pendingResumeWorldHours = nil
        state.pendingResumeReason = nil
        state.lastActiveElapsedHours = 0
        state.lastRawElapsedHours = 0
        state.lastElapsedMode = "bootstrap-freeze"
    end
    state.lastTraceReason = tostring(reason or "bootstrap")
    Runtime.syncVisibleShell(playerObj, reason or "bootstrap")
    Runtime.observePlayerWorkload(playerObj, reason or "bootstrap")
    return state
end

function Runtime.refreshKnownPlayers(reason)
    eachKnownPlayer(function(playerObj)
        Runtime.updatePlayer(playerObj, reason)
    end)
end

function Runtime.bootstrapKnownPlayers(reason)
    eachKnownPlayer(function(playerObj)
        Runtime.bootstrapPlayer(playerObj, reason)
    end)
end

return Runtime
