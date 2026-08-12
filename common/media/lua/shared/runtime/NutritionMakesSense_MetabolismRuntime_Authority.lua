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
local eachKnownPlayer = Runtime.eachKnownPlayer
local getTelemetryForState = Runtime.getTelemetryForState
local replaceTelemetryForState = Runtime.replaceTelemetryForState
local buildStateView = Runtime.buildStateView
local recordDepositTelemetry = Runtime.recordDepositTelemetry
local recordAdvanceTelemetry = Runtime.recordAdvanceTelemetry
local DebugSupport = NutritionMakesSense.DebugSupport or {}
local Settings = Runtime.Settings or NutritionMakesSense.Settings or {}
local PENDING_HUNGER_MAX_AGE = 2
local ACTIVE_ELAPSED_CAP_HOURS = 0.25
local MP_RESUME_GAP_THRESHOLD_HOURS = 0.50

local function buildMealEvent(fullness, details)
    local result = type(fullness) == "table" and fullness or {}
    local context = type(details) == "table" and details or {}
    local values = type(context.values) == "table" and context.values or {}
    local mechanicalDrop = tonumber(result.mechanicalDrop) or tonumber(context.observedDrop) or 0
    return {
        reason = tostring(context.reason or "meal-observation"),
        item = "", item_known = false, fraction = 1,
        provenance = tostring(context.provenance or "observed-hunger-only"),
        consume_source = tostring(context.consumeSource or "runtime-observed-hunger"),
        pre_visible_hunger = tonumber(result.preVisibleHunger) or tonumber(context.preHunger) or 0,
        target_visible_hunger = tonumber(result.targetVisibleHunger) or tonumber(context.targetHunger) or 0,
        kcal = tonumber(values.kcal) or 0,
        carbs = tonumber(values.carbs) or 0,
        fats = tonumber(values.fats) or 0,
        proteins = tonumber(values.proteins) or 0,
        observed_hunger_drop = tonumber(context.observedDrop) or mechanicalDrop,
        hunger_observed = mechanicalDrop > 0,
        mechanical_hunger_drop = mechanicalDrop,
        physical_hunger_drop = tonumber(result.physicalDrop) or 0,
        nutrient_hunger_drop = tonumber(result.nutrientDrop) or 0,
        modeled_hunger_drop = tonumber(result.targetDrop) or 0,
        applied_hunger_drop = tonumber(result.appliedDrop) or 0,
        hunger_correction = tonumber(result.appliedCorrection) or 0,
        meal_transaction_kcal = tonumber(result.transactionKcal) or 0,
        meal_transaction_fragments = tonumber(result.transactionFragments) or 0,
    }
end

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

local function resolveActiveElapsedHours(state, telemetry, nowHours, reason)
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

    local pendingResumeHours = tonumber(telemetry and telemetry.pendingResumeWorldHours) or nil
    local pendingResumeReason = tostring(telemetry and telemetry.pendingResumeReason or reason or "resume")
    if pendingResumeHours ~= nil and pendingResumeHours >= previousHours then
        telemetry.pendingResumeWorldHours = nil
        telemetry.pendingResumeReason = nil
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
        return buildStateView(state, getTelemetryForState(state))
    end

    state = Metabolism.ensureState(state)
    getTelemetryForState(state).lastTraceReason = tostring(reason or "debug-set")
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

    return buildStateView(state, getTelemetryForState(state))
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
    local visibleHunger = clamp(
        getVisibleHungerValue(stats) or 0,
        Metabolism.VISIBLE_HUNGER_MIN,
        Metabolism.VISIBLE_HUNGER_MAX
    )
    local state = Metabolism.newState({
        initialized = true,
        fuel = 1300,
        visibleHunger = visibleHunger,
        lastWorldHours = getWorldHours(),
        depositSequence = tonumber(previous and previous.depositSequence) or 0,
        baseHealthFromFood = tonumber(previous and previous.baseHealthFromFood) or seedHealthFromFood(bodyDamage),
    })
    local telemetry = replaceTelemetryForState(state, {
        lastMetSource = "debug-reset",
        lastMealPreHunger = visibleHunger,
        lastMealTargetHunger = visibleHunger,
        lastSyncedHunger = visibleHunger,
        lastTraceReason = tostring(reason or "debug-reset"),
    })
    modData[STATE_KEY] = state

    local nutrition = getPlayerNutrition(playerObj)
    syncVisibleWeight(nutrition, state, telemetry)
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

    return buildStateView(state, telemetry)
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
            getTelemetryForState(state).lastSyncedHunger = state.visibleHunger
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

    local telemetry = getTelemetryForState(state)
    local normalized = normalizeDeposit(values)
    local report = Metabolism.applyFoodValues(state, normalized, 1, reason or "mp-authority")
    recordDepositTelemetry(telemetry, report)
    local opts = type(options) == "table" and options or nil
    if opts and opts.accumulateMealFullness == true then
        local fullness = Runtime.accumulateMealObservation(
            state,
            normalized,
            opts.observedHungerDrop,
            opts.preVisibleHunger,
            reason or "mp-authority"
        )
        report.mealFullness = fullness
        report.mealHungerDrop = fullness.appliedDrop
        report.mealModeledDrop = fullness.targetDrop
        report.mealMechanicalDrop = fullness.mechanicalDrop
        report.mealPhysicalDrop = fullness.physicalDrop
        report.mealNutrientDrop = fullness.nutrientDrop
        report.mealHungerCorrection = fullness.appliedCorrection
        report.preVisibleHunger = fullness.preVisibleHunger
        report.targetVisibleHunger = fullness.targetVisibleHunger
    end

    Runtime.syncVisibleShell(playerObj, reason or "mp-authority")

    return report, state
end

function Runtime.finalizeMealObservation(state, values, observedHungerDrop, preVisibleHunger, reason)
    local telemetry = getTelemetryForState(state)
    state = Metabolism.ensureState(state)
    local normalized = normalizeDeposit(values)
    local preHunger = tonumber(preVisibleHunger)
        or tonumber(telemetry.pendingMealPreVisibleHunger)
        or tonumber(state.visibleHunger)
        or 0
    local fullness = Metabolism.resolveMealHunger(normalized, observedHungerDrop, preHunger)

    state.visibleHunger = fullness.targetVisibleHunger
    telemetry.lastMealHungerDrop = fullness.appliedDrop
    telemetry.lastMealModeledDrop = fullness.targetDrop
    telemetry.lastMealMechanicalDrop = fullness.mechanicalDrop
    telemetry.lastMealPhysicalDrop = fullness.physicalDrop
    telemetry.lastMealNutrientDrop = fullness.nutrientDrop
    telemetry.lastMealPreHunger = fullness.preVisibleHunger
    telemetry.lastMealTargetHunger = fullness.targetVisibleHunger
    telemetry.pendingObservedHungerDrop = 0
    telemetry.pendingObservedHungerAge = 0
    telemetry.pendingMealPreVisibleHunger = nil
    telemetry.lastTraceReason = tostring(reason or "meal-fullness")

    return fullness
end

function Runtime.accumulateMealObservation(state, values, observedHungerDrop, preVisibleHunger, reason)
    local telemetry = getTelemetryForState(state)
    state = Metabolism.ensureState(state)
    local normalized = normalizeDeposit(values)
    local transaction = telemetry.pendingMealTransaction
    if type(transaction) ~= "table" or (tonumber(transaction.age) or 0) > PENDING_HUNGER_MAX_AGE then
        transaction = {
            preVisibleHunger = tonumber(preVisibleHunger)
                or tonumber(telemetry.pendingMealPreVisibleHunger)
                or tonumber(state.visibleHunger)
                or 0,
            kcal = 0,
            carbs = 0,
            fats = 0,
            proteins = 0,
            observedHungerDrop = 0,
            satietyContribution = 0,
            fragments = 0,
            age = 0,
        }
    end

    transaction.kcal = math.max(0, (tonumber(transaction.kcal) or 0) + normalized.kcal)
    transaction.carbs = math.max(0, (tonumber(transaction.carbs) or 0) + normalized.carbs)
    transaction.fats = math.max(0, (tonumber(transaction.fats) or 0) + normalized.fats)
    transaction.proteins = math.max(0, (tonumber(transaction.proteins) or 0) + normalized.proteins)
    transaction.observedHungerDrop = clamp(
        (tonumber(transaction.observedHungerDrop) or 0) + (tonumber(observedHungerDrop) or 0),
        0,
        1
    )
    transaction.satietyContribution = math.max(
        0,
        (tonumber(transaction.satietyContribution) or 0) + Metabolism.getSatietyContribution(normalized, 1)
    )
    if hasMeaningfulDeposit(normalized) then
        transaction.fragments = (tonumber(transaction.fragments) or 0) + 1
    end
    transaction.age = 0
    telemetry.pendingMealTransaction = transaction

    local fullness = Runtime.finalizeMealObservation(
        state,
        transaction,
        transaction.observedHungerDrop,
        transaction.preVisibleHunger,
        reason or "meal-transaction"
    )
    transaction.lastTargetVisibleHunger = fullness.targetVisibleHunger
    telemetry.pendingMealTransaction = transaction
    telemetry.lastMealDepositKcal = transaction.kcal
    telemetry.lastMealTransactionFragments = transaction.fragments
    telemetry.lastSatietyQuality = Metabolism.getSatietyQuality(transaction)
    telemetry.lastSatietyContribution = transaction.satietyContribution
    fullness.transactionKcal = transaction.kcal
    fullness.transactionCarbs = transaction.carbs
    fullness.transactionFats = transaction.fats
    fullness.transactionProteins = transaction.proteins
    fullness.transactionFragments = transaction.fragments
    return fullness
end

function Runtime.updatePlayer(playerObj, reason)
    if not shouldRunAuthoritativeUpdates() or not playerObj then
        return
    end

    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return
    end
    local telemetry = getTelemetryForState(state)

    local playerLabel = getPlayerLabel(playerObj)
    local nutrition = getPlayerNutrition(playerObj)
    local observedDelta = samplePositiveNutritionDelta(nutrition)
    local observedDeltaDetected = hasMeaningfulDeposit(observedDelta)

    local playerStats = getPlayerStats(playerObj)
    local preVisibleHunger = tonumber(telemetry.pendingMealPreVisibleHunger)
        or tonumber(state.visibleHunger)
        or 0
    if observedDeltaDetected and type(importLiveVisibleHungerDrop) == "function" then
        importLiveVisibleHungerDrop(state, playerStats)
    end

    -- Apply observed vanilla nutrition deltas anywhere we are running authoritative updates.
    -- Dedicated servers, listen servers, and solo runtimes must all credit the same intake path.
    if observedDeltaDetected then
        local observedHungerDrop = clamp(tonumber(telemetry.pendingObservedHungerDrop) or 0, 0, 1)
        local mealPreHunger = tonumber(telemetry.pendingMealPreVisibleHunger) or preVisibleHunger
        local depositReport = Runtime.applyAuthoritativeDeposit(
            playerObj,
            observedDelta,
            "vanilla-nutrition-delta",
            {
                accumulateMealFullness = true,
                observedHungerDrop = observedHungerDrop,
                preVisibleHunger = mealPreHunger,
            }
        )
        local fullness = depositReport and depositReport.mealFullness or {}
        if type(DebugSupport.noteConsumeEvent) == "function" then
            DebugSupport.noteConsumeEvent(buildMealEvent(fullness, {
                reason = tostring(reason or "vanilla-nutrition-delta"),
                provenance = "observed-nutrition-delta",
                consumeSource = "runtime-observed-delta",
                values = observedDelta,
                observedDrop = observedHungerDrop,
                preHunger = mealPreHunger,
                targetHunger = state.visibleHunger,
            }))
        end
    else
        local pendingDrop = tonumber(telemetry.pendingObservedHungerDrop) or 0
        local transaction = type(telemetry.pendingMealTransaction) == "table" and telemetry.pendingMealTransaction or nil
        if pendingDrop > 0 and transaction then
            local fullness = Runtime.accumulateMealObservation(
                state,
                nil,
                pendingDrop,
                transaction.preVisibleHunger,
                "delayed-mechanical-confirmation"
            )
            if type(DebugSupport.noteHungerSyncEvent) == "function" then
                DebugSupport.noteHungerSyncEvent(buildMealEvent(fullness, {
                    reason = "delayed-mechanical-confirmation",
                    provenance = "observed-hunger-confirmation",
                }))
            end
        elseif pendingDrop > 0 then
            telemetry.pendingObservedHungerAge = (tonumber(telemetry.pendingObservedHungerAge) or 0) + 1
            if telemetry.pendingObservedHungerAge > PENDING_HUNGER_MAX_AGE then
                local fullness = Runtime.finalizeMealObservation(
                    state,
                    nil,
                    pendingDrop,
                    telemetry.pendingMealPreVisibleHunger,
                    "observed-hunger-only"
                )
                if type(DebugSupport.noteConsumeEvent) == "function" then
                    DebugSupport.noteConsumeEvent(buildMealEvent(fullness, {
                        reason = "observed-hunger-only",
                        provenance = "observed-hunger-only",
                    }))
                end
            end
        end

        transaction = type(telemetry.pendingMealTransaction) == "table" and telemetry.pendingMealTransaction or nil
        if pendingDrop <= 0 and transaction then
            transaction.age = (tonumber(transaction.age) or 0) + 1
            if transaction.age > PENDING_HUNGER_MAX_AGE then
                telemetry.pendingMealTransaction = nil
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
    local elapsedHours, elapsedContext = resolveActiveElapsedHours(state, telemetry, nowHours, reason)
    state.lastWorldHours = nowHours or state.lastWorldHours

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
    local statsDecreaseMultiplier = resolveStatsDecreaseMultiplier()
    local appetiteRateMultiplier = type(Settings.getAppetiteRateMultiplier) == "function"
        and Settings.getAppetiteRateMultiplier() or 1.0
    local energyBurnMultiplier = type(Settings.getEnergyBurnMultiplier) == "function"
        and Settings.getEnergyBurnMultiplier() or 1.0
    local advanceReport = Metabolism.advanceState(state, elapsedHours, workload, {
        reason = reason or workload.workTier or "workload",
        traitEffects = traitEffects,
        statsDecreaseMultiplier = statsDecreaseMultiplier,
        appetiteRateMultiplier = appetiteRateMultiplier,
        hungerRateMultiplier = statsDecreaseMultiplier * appetiteRateMultiplier,
        energyBurnMultiplier = energyBurnMultiplier,
        previousWeightRateKgPerWeek = telemetry.lastWeightRateKgPerWeek,
    })
    recordAdvanceTelemetry(telemetry, advanceReport)
    Runtime.syncVisibleShell(playerObj, reason or workload.workTier or "workload")

    local zoneAfter = Metabolism.getFuelZone(state.fuel)
    if zoneBefore ~= zoneAfter then
        log(string.format(
            "[FUEL_ZONE] player=%s from=%s to=%s fuel=%.1f tier=%s met=%.2f correction=%.4f",
            tostring(playerLabel),
            tostring(zoneBefore),
            tostring(zoneAfter),
            tonumber(state.fuel or 0),
            tostring(telemetry.lastWorkTier or workload.workTier or "--"),
            tonumber(advanceReport.averageMet or telemetry.lastMetAverage or Metabolism.MET_REST),
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
            tostring(Metabolism.getWeightTrait(state.weightKg)),
            tonumber(advanceReport.averageMet or telemetry.lastMetAverage or Metabolism.MET_REST),
            tonumber(advanceReport.peakMet or telemetry.lastMetPeak or Metabolism.MET_REST),
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

    local telemetry = getTelemetryForState(state)
    local nowHours = getWorldHours() or state.lastWorldHours
    telemetry.pendingResumeWorldHours = nowHours
    telemetry.pendingResumeReason = tostring(reason or "session-resume")
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

    local telemetry = getTelemetryForState(state)
    state.lastWorldHours = getWorldHours() or state.lastWorldHours
    if isResumeReason(reason) then
        telemetry.pendingResumeWorldHours = nil
        telemetry.pendingResumeReason = nil
    end
    telemetry.lastTraceReason = tostring(reason or "bootstrap")
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
