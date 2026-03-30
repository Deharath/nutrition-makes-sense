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
local getWorldHours = Runtime.getWorldHours
local consumeWorkloadSummary = Runtime.consumeWorkloadSummary
local removeEndurance = Runtime.removeEndurance
local eachKnownPlayer = Runtime.eachKnownPlayer
local runningOnServer = (type(isServer) == "function") and (isServer() == true)
local SUPPRESSION_EPSILON = 0.01
local SUPPRESSION_TTL_HOURS = 0.20

local function copySuppressionValues(values)
    local normalized = normalizeDeposit(values)
    return {
        kcal = math.max(0, tonumber(normalized.kcal) or 0),
        carbs = math.max(0, tonumber(normalized.carbs) or 0),
        fats = math.max(0, tonumber(normalized.fats) or 0),
        proteins = math.max(0, tonumber(normalized.proteins) or 0),
    }
end

local function queueHasMeaningfulDelta(values)
    return math.abs(tonumber(values and values.kcal) or 0) > SUPPRESSION_EPSILON
        or math.abs(tonumber(values and values.carbs) or 0) > SUPPRESSION_EPSILON
        or math.abs(tonumber(values and values.fats) or 0) > SUPPRESSION_EPSILON
        or math.abs(tonumber(values and values.proteins) or 0) > SUPPRESSION_EPSILON
end

local function formatMacroValues(values)
    return string.format(
        "kcal=%.1f carbs=%.1f fats=%.1f proteins=%.1f",
        tonumber(values and values.kcal) or 0,
        tonumber(values and values.carbs) or 0,
        tonumber(values and values.fats) or 0,
        tonumber(values and values.proteins) or 0
    )
end

function Runtime.enqueuePendingNutritionSuppression(playerObj, values, reason)
    if not playerObj then
        return nil
    end

    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return nil
    end

    local queued = copySuppressionValues(values)
    if not queueHasMeaningfulDelta(queued) then
        return nil
    end

    local suppressions = type(state.pendingNutritionSuppressions) == "table" and state.pendingNutritionSuppressions or {}
    suppressions[#suppressions + 1] = {
        kcal = queued.kcal,
        carbs = queued.carbs,
        fats = queued.fats,
        proteins = queued.proteins,
        reason = tostring(reason or "server-explicit-consume"),
        worldHours = tonumber(getWorldHours()) or nil,
    }
    state.pendingNutritionSuppressions = suppressions
    return suppressions[#suppressions]
end

function Runtime.consumePendingNutritionSuppressions(playerObj, observedDelta, reason)
    local remaining = copySuppressionValues(observedDelta)
    if not playerObj then
        return remaining, nil
    end

    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return remaining, nil
    end

    local suppressions = state.pendingNutritionSuppressions
    if type(suppressions) ~= "table" or #suppressions == 0 then
        return remaining, nil
    end

    local nowHours = tonumber(getWorldHours()) or nil
    local absorbed = {
        kcal = 0,
        carbs = 0,
        fats = 0,
        proteins = 0,
    }
    local remainingQueue = {}

    for _, entry in ipairs(suppressions) do
        local entryWorldHours = tonumber(entry and entry.worldHours) or nil
        local isStale = nowHours ~= nil
            and entryWorldHours ~= nil
            and (nowHours - entryWorldHours) > SUPPRESSION_TTL_HOURS
        if not isStale and type(entry) == "table" then
            local leftover = {
                kcal = math.max(0, tonumber(entry.kcal) or 0),
                carbs = math.max(0, tonumber(entry.carbs) or 0),
                fats = math.max(0, tonumber(entry.fats) or 0),
                proteins = math.max(0, tonumber(entry.proteins) or 0),
                reason = tostring(entry.reason or "server-explicit-consume"),
                worldHours = entryWorldHours,
            }

            for _, field in ipairs({ "kcal", "carbs", "fats", "proteins" }) do
                local matched = math.min(tonumber(remaining[field]) or 0, tonumber(leftover[field]) or 0)
                if matched > SUPPRESSION_EPSILON then
                    remaining[field] = math.max(0, (tonumber(remaining[field]) or 0) - matched)
                    leftover[field] = math.max(0, (tonumber(leftover[field]) or 0) - matched)
                    absorbed[field] = (tonumber(absorbed[field]) or 0) + matched
                end
            end

            if queueHasMeaningfulDelta(leftover) then
                remainingQueue[#remainingQueue + 1] = {
                    kcal = tonumber(leftover.kcal) or 0,
                    carbs = tonumber(leftover.carbs) or 0,
                    fats = tonumber(leftover.fats) or 0,
                    proteins = tonumber(leftover.proteins) or 0,
                    reason = tostring(entry.reason or "server-explicit-consume"),
                    worldHours = entryWorldHours,
                }
            end
        end
    end

    state.pendingNutritionSuppressions = (#remainingQueue > 0) and remainingQueue or nil

    if queueHasMeaningfulDelta(absorbed) then
        log(string.format(
            "[MP_SERVER_DRIFT_SUPPRESS] player=%s reason=%s %s",
            tostring(getPlayerLabel(playerObj)),
            tostring(reason or "server-drift-suppress"),
            formatMacroValues(absorbed)
        ))
    end

    return remaining, absorbed
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
        lastImmediateHungerDrop = 0,
        lastImmediateHungerMechanical = 0,
        lastImmediateFillTarget = 0,
        lastImmediateFillVanilla = 0,
        lastImmediateFillCorrection = 0,
        lastBurnKcal = 0,
        lastDepositKcal = 0,
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
        lastExertionMultiplier = 1.0,
        lastTraceReason = tostring(reason or "debug-reset"),
        baseHealthFromFood = tonumber(previous and previous.baseHealthFromFood) or seedHealthFromFood(bodyDamage),
        pendingNutritionSuppressions = nil,
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

function Runtime.debugClearSuppressions(playerObj, reason)
    if not playerObj then
        return nil
    end

    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return nil
    end

    local cleared = state.pendingNutritionSuppressions and #state.pendingNutritionSuppressions or 0
    state.pendingNutritionSuppressions = nil
    state = refreshDerivedState(state, reason or "debug-clear-suppressions")

    local modData = getModData(playerObj)
    if modData then
        modData[STATE_KEY] = state
    end

    log(string.format(
        "[NMS_DEV_CLEAR] player=%s queue=%d reason=%s",
        tostring(getPlayerLabel(playerObj)),
        tonumber(cleared or 0),
        tostring(reason or "debug-clear-suppressions")
    ))

    return Metabolism.copyState(state), cleared
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
            state.hunger = state.visibleHunger
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
    local remainingDrift = observedDelta
    if runningOnServer and hasMeaningfulDeposit(observedDelta) then
        remainingDrift = Runtime.consumePendingNutritionSuppressions(playerObj, observedDelta, reason)
    end
    if runningOnServer and hasMeaningfulDeposit(remainingDrift) then
        Runtime.applyAuthoritativeDeposit(playerObj, remainingDrift, "food-drift-consume", {
            item = "vanilla-drift",
        })
    end
    local zoneBefore = Metabolism.getFuelZone(state.fuel)

    local nowHours = getWorldHours()
    local elapsedHours = 0
    if nowHours and state.lastWorldHours then
        elapsedHours = math.max(0, nowHours - state.lastWorldHours)
        elapsedHours = math.min(elapsedHours, 6)
    end
    state.lastWorldHours = nowHours or state.lastWorldHours

    local workload = consumeWorkloadSummary(playerObj)
    local traitEffects = Runtime.resolveTraitEffects and Runtime.resolveTraitEffects(playerObj) or nil
    local advanceReport = Metabolism.advanceState(state, elapsedHours, workload, {
        reason = reason or workload.workTier or "workload",
        traitEffects = traitEffects,
    })
    local stats = getPlayerStats(playerObj)
    if workload.appliedEnduranceDrain == nil then
        removeEndurance(playerObj, stats, advanceReport.extraEnduranceDrain or 0)
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

function Runtime.bootstrapPlayer(playerObj, reason)
    if not playerObj then
        return nil
    end

    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return nil
    end

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
