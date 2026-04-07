NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.LiveScenarioRunner = NutritionMakesSense.LiveScenarioRunner or {}

require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISEatFoodAction"
require "TimedActions/ISDrinkFluidAction"
require "dev/scenarios/NutritionMakesSense_LiveScenarioCatalog"
require "dev/scenarios/NutritionMakesSense_LiveScenarioAnalysis"
require "dev/NutritionMakesSense_LiveScenarioRunnerUtils"
require "NutritionMakesSense_CoreUtils"

local Runner = NutritionMakesSense.LiveScenarioRunner
local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local Metabolism = NutritionMakesSense.Metabolism or {}
local ScenarioCatalog = NutritionMakesSense.LiveScenarioCatalog or {}
local ScenarioAnalysis = NutritionMakesSense.LiveScenarioAnalysis or {}
local RunnerUtils = NutritionMakesSense.LiveScenarioRunnerUtils or {}
local CoreUtils = NutritionMakesSense.CoreUtils or {}

local activeRun = nil
local lastStatus = nil
local lastReportPath = nil
local selectedTriggerMode = "strict_hunger_signal"
local selectedAvailabilityMode = "eat_anytime"
local selectedStartWeightKg = 80
local TIME_MULTIPLIER_PRESETS = {
    { id = "40x", label = "40x", multiplier = 40 },
    { id = "80x", label = "80x", multiplier = 80 },
    { id = "120x", label = "120x", multiplier = 120 },
}
local selectedTimeMultiplier = 80
local SCENARIO_TRAITS = {
    { id = "hearty_appetite", label = "Hearty Appetite", traitName = "Hearty Appetite", traitEnum = "HEARTY_APPETITE" },
    { id = "light_eater", label = "Light Eater", traitName = "Light Eater", traitEnum = "LIGHT_EATER" },
    { id = "slow_metabolism", label = "Slow Metabolism", traitName = "Slow Metabolism", traitEnum = "WEIGHT_GAIN" },
    { id = "fast_metabolism", label = "Fast Metabolism", traitName = "Fast Metabolism", traitEnum = "WEIGHT_LOSS" },
}
local selectedTraitFlags = {}
for _, trait in ipairs(SCENARIO_TRAITS) do
    selectedTraitFlags[trait.id] = false
end

local TRIGGER_MODE_CLOCK = "clock"
local TRIGGER_MODE_HUNGER_SIGNAL = "hunger_signal"
local TRIGGER_MODE_STRICT_HUNGER_SIGNAL = "strict_hunger_signal"
local CONSUMPTION_MODE_SCHEDULED_MEALS = "scheduled_meals"
local CONSUMPTION_MODE_SIGNAL_SEQUENCE = "signal_sequence"
local CONSUMPTION_MODE_SIGNAL_MEALS = "signal_meals"
local AVAILABILITY_MODE_EAT_ANYTIME = "eat_anytime"
local AVAILABILITY_MODE_INTERRUPT_WORK_FOR_FOOD = "interrupt_work_for_food"
local TRIGGER_MODES = {
    { id = TRIGGER_MODE_CLOCK, label = "Eat On Time" },
    { id = TRIGGER_MODE_HUNGER_SIGNAL, label = "Eat On Hunger Signal" },
    { id = TRIGGER_MODE_STRICT_HUNGER_SIGNAL, label = "Strict Hunger Signal" },
}
local AVAILABILITY_MODES = {
    { id = AVAILABILITY_MODE_EAT_ANYTIME, label = "Eat Anytime" },
    { id = AVAILABILITY_MODE_INTERRUPT_WORK_FOR_FOOD, label = "Interrupt Work For Food" },
}
local recordRow
local addFinding
local snapshotPlayer

local SEVERITY_PASS = "pass"
local SEVERITY_WARN = "warn"
local SEVERITY_FAIL = "fail"
local SAMPLE_INTERVAL_MINUTES = 10
local MET_TOLERANCE = 0.35
local THIRST_TOP_UP_THRESHOLD = 0.08
local THIRST_TOP_UP_TARGET = 0.0
local THIRST_TOP_UP_INTERVAL_HOURS = 20 / 60
local BOREDOM_TOP_UP_THRESHOLD = 0.01
local BOREDOM_TOP_UP_TARGET = 0.0
local BOREDOM_TOP_UP_INTERVAL_HOURS = 20 / 60
local RESTORE_TOLERANCE = {
    hunger = 0.01,
    thirst = 0.01,
    boredom = 0.05,
    endurance = 0.01,
    fatigue = 0.01,
    healthFromFood = 0.001,
    fuel = 0.05,
    deprivation = 0.01,
    satietyBuffer = 0.01,
    proteins = 0.05,
    weightKg = 0.005,
    weightController = 0.02,
    multiplier = 0.001,
}

local REPORT_HEADER = table.concat({
    "severity",
    "code",
    "message",
    "stage",
    "outcome",
    "world_hours",
    "elapsed_hours",
    "scenario_clock",
    "phase",
    "target_met",
    "thermo_target_met",
    "thermo_real_met",
    "work_tier",
    "work_met_avg",
    "work_met_peak",
    "work_source",
    "eat_availability",
    "scenario_traits",
    "eat_block_reason",
    "meal_trigger",
    "meal",
    "item",
    "food_eaten_moodle",
    "visible_hunger",
    "endurance",
    "fatigue",
    "health_from_food",
    "health_from_food_timer",
    "timed_action_instant",
    "time_multiplier",
    "state_fuel",
    "state_zone",
    "state_deprivation",
    "state_deprivation_target",
    "state_underfeeding_debt",
    "state_satiety",
    "state_proteins",
    "state_weight_kg",
    "state_controller",
    "state_last_deposit_kcal",
    "state_last_trace_reason",
}, ",")

local function log(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(msg)
    else
        print("[NutritionMakesSense] " .. tostring(msg))
    end
end

local safeCall = CoreUtils.safeCall
local safeInvoke = CoreUtils.safeInvoke
local hasTrait = CoreUtils.hasTrait
local copyTable = RunnerUtils.copyTable
local clamp = RunnerUtils.clamp
local nearlyEqual = RunnerUtils.nearlyEqual
local normalizeStartWeightKg = RunnerUtils.normalizeStartWeightKg
local csvEscape = RunnerUtils.csvEscape
local getLocalPlayer = RunnerUtils.getLocalPlayer
local getWorldHours = RunnerUtils.getWorldHours
local getTimeMultiplier = RunnerUtils.getTimeMultiplier
local getGameSpeedMode = RunnerUtils.getGameSpeedMode
local getGameSpeedModeForMultiplier = RunnerUtils.getGameSpeedModeForMultiplier
local setTimeMultiplier = RunnerUtils.setTimeMultiplier
local restoreGameSpeedMode = RunnerUtils.restoreGameSpeedMode
local getExpectedEffectiveMultiplier = RunnerUtils.getExpectedEffectiveMultiplier
local validateRequestedTimeAcceleration = RunnerUtils.validateRequestedTimeAcceleration
local getPlayerStats = RunnerUtils.getPlayerStats
local getPlayerNutrition = RunnerUtils.getPlayerNutrition
local getPlayerBodyDamage = RunnerUtils.getPlayerBodyDamage
local getCharacterStat = RunnerUtils.getCharacterStat
local setCharacterStat = RunnerUtils.setCharacterStat
local clearTimedActions = RunnerUtils.clearTimedActions
local hasTimedActions = RunnerUtils.hasTimedActions
local getInventory = RunnerUtils.getInventory
local inventoryContainsItem = RunnerUtils.inventoryContainsItem
local removeInventoryItem = RunnerUtils.removeInventoryItem
local getFoodEatenMoodle = RunnerUtils.getFoodEatenMoodle
local getHungryMoodleLevel = RunnerUtils.getHungryMoodleLevel

local function cloneSelectedTraitFlags(source)
    local flags = {}
    for _, trait in ipairs(SCENARIO_TRAITS) do
        flags[trait.id] = type(source) == "table" and source[trait.id] == true or false
    end
    return flags
end

local function describeSelectedTraits(flags)
    local labels = {}
    for _, trait in ipairs(SCENARIO_TRAITS) do
        if type(flags) == "table" and flags[trait.id] == true then
            labels[#labels + 1] = trait.label
        end
    end
    if #labels == 0 then
        return "None"
    end
    return table.concat(labels, ", ")
end

local function snapshotScenarioTraits(playerObj)
    local flags = {}
    for _, trait in ipairs(SCENARIO_TRAITS) do
        flags[trait.id] = hasTrait(playerObj, trait.traitName, trait.traitEnum)
    end
    return flags
end

local function setScenarioTraitEnabled(playerObj, traitDef, enabled)
    if not playerObj or type(traitDef) ~= "table" then
        return false
    end
    local traits = safeCall(playerObj, "getCharacterTraits")
    if not traits then
        return false
    end

    local alreadyEnabled = hasTrait(playerObj, traitDef.traitName, traitDef.traitEnum)
    if alreadyEnabled == (enabled == true) then
        return true
    end

    local traitKey = (_G.CharacterTrait and traitDef.traitEnum and CharacterTrait[traitDef.traitEnum]) or traitDef.traitName
    local invoked
    if enabled == true then
        invoked = safeInvoke(traits, "add", traitKey)
    else
        invoked = safeInvoke(traits, "remove", traitKey)
    end
    if not invoked then
        return false
    end
    return hasTrait(playerObj, traitDef.traitName, traitDef.traitEnum) == (enabled == true)
end

local function applyScenarioTraits(playerObj, flags)
    for _, trait in ipairs(SCENARIO_TRAITS) do
        if not setScenarioTraitEnabled(playerObj, trait, type(flags) == "table" and flags[trait.id] == true) then
            return false, trait.label
        end
    end
    return true, nil
end

local function normalizeTriggerMode(mode)
    if tostring(mode) == TRIGGER_MODE_STRICT_HUNGER_SIGNAL then
        return TRIGGER_MODE_STRICT_HUNGER_SIGNAL
    end
    if tostring(mode) == TRIGGER_MODE_HUNGER_SIGNAL then
        return TRIGGER_MODE_HUNGER_SIGNAL
    end
    return TRIGGER_MODE_CLOCK
end

local function normalizeAvailabilityMode(mode)
    if tostring(mode) == AVAILABILITY_MODE_INTERRUPT_WORK_FOR_FOOD then
        return AVAILABILITY_MODE_INTERRUPT_WORK_FOR_FOOD
    end
    return AVAILABILITY_MODE_EAT_ANYTIME
end

local function getConsumptionMode(profile)
    if profile and tostring(profile.consumptionMode) == CONSUMPTION_MODE_SIGNAL_SEQUENCE then
        return CONSUMPTION_MODE_SIGNAL_SEQUENCE
    end
    if profile and tostring(profile.consumptionMode) == CONSUMPTION_MODE_SIGNAL_MEALS then
        return CONSUMPTION_MODE_SIGNAL_MEALS
    end
    return CONSUMPTION_MODE_SCHEDULED_MEALS
end

local function getEffectiveTriggerMode(profile, requestedMode)
    local normalized = normalizeTriggerMode(requestedMode)
    local consumptionMode = getConsumptionMode(profile)
    if consumptionMode == CONSUMPTION_MODE_SIGNAL_SEQUENCE or consumptionMode == CONSUMPTION_MODE_SIGNAL_MEALS then
        if normalized == TRIGGER_MODE_STRICT_HUNGER_SIGNAL then
            return TRIGGER_MODE_STRICT_HUNGER_SIGNAL
        end
        return TRIGGER_MODE_HUNGER_SIGNAL
    end
    return normalized
end

local function phaseInterruptibleForFood(phase)
    if type(phase) ~= "table" then
        return false
    end
    if phase.interruptibleForFood ~= nil then
        return phase.interruptibleForFood == true
    end
    if phase.blocksEating ~= nil then
        return phase.blocksEating == true
    end
    local metabolics = tostring(phase.metabolics or "")
    return metabolics == "MediumWork" or metabolics == "UsingTools"
end

local function clearBlockedEatState(run)
    if not run then
        return
    end
    run.pendingBlockedEat = nil
    run.pendingBlockedTrigger = nil
    run.pendingBlockedPhase = nil
    run.pendingBlockedMeal = nil
    run.pendingBlockedReason = nil
    run.lastBlockedSignature = nil
end

local function getSignalThresholdBand(run)
    local base = tostring(run and run.profile and run.profile.signalThreshold or "peckish")
    if run and run.profile and run.profile.preserveSignalThresholdDuringWorkInterrupt then
        return base
    end
    if normalizeAvailabilityMode(run and run.availabilityMode) == AVAILABILITY_MODE_INTERRUPT_WORK_FOR_FOOD
        and phaseInterruptibleForFood(run and run.currentPhase) then
        return "hungry"
    end
    return base
end

local function getMealEarliestHour(meal)
    if type(meal) ~= "table" then
        return nil
    end
    return tonumber(meal.earliestHour) or tonumber(meal.atHour)
end

local function getMealDeadlineHour(run, mealIndex)
    local meals = run and run.profile and run.profile.meals or nil
    if type(meals) ~= "table" then
        return nil
    end
    local meal = meals[mealIndex]
    if type(meal) ~= "table" then
        return nil
    end
    if meal.latestHour ~= nil then
        return tonumber(meal.latestHour)
    end
    local nextMeal = meals[mealIndex + 1]
    if nextMeal then
        return getMealEarliestHour(nextMeal)
    end
    return tonumber(run.profile and run.profile.durationHours)
end

local function getNextMealWindow(run)
    local meal = run and run.profile and run.profile.meals and run.profile.meals[run.nextMealIndex] or nil
    if not meal then
        return nil, nil, nil
    end
    return meal, getMealEarliestHour(meal), getMealDeadlineHour(run, run.nextMealIndex)
end

local function isHungrySignalReady(run, thresholdBand)
    local requiredBand = tostring(thresholdBand or "peckish")
    local hungryMoodle = getHungryMoodleLevel(run and run.player)
    if hungryMoodle ~= nil then
        if requiredBand == "hungry" then
            return hungryMoodle >= 2, hungryMoodle
        end
        return hungryMoodle >= 1, hungryMoodle
    end
    local snapshot = run and run.player and snapshotPlayer(run.player) or nil
    local state = snapshot and snapshot.state or nil
    local hungerBand = state and state.lastHungerBand or nil
    if hungerBand == nil and Metabolism.getVisibleHungerBand then
        hungerBand = Metabolism.getVisibleHungerBand(snapshot and snapshot.hunger)
    end
    if requiredBand == "hungry" then
        return hungerBand == "hungry" or hungerBand == "starving", nil
    end
    return hungerBand == "peckish" or hungerBand == "hungry" or hungerBand == "starving", nil
end

local function getPendingCueReason(triggerMode, hungryMoodle)
    if normalizeTriggerMode(triggerMode) == TRIGGER_MODE_STRICT_HUNGER_SIGNAL then
        return hungryMoodle and ("waiting_hunger_moodle_" .. tostring(hungryMoodle)) or "waiting_hunger_signal"
    end
    return hungryMoodle and ("waiting_hunger_moodle_" .. tostring(hungryMoodle)) or "waiting_hunger_signal"
end

local function shouldStartMeal(run, mealIndex)
    local meal, earliestHour, deadlineHour = getNextMealWindow(run)
    local elapsedHours = tonumber(run and run.elapsedHours) or 0
    if not meal or earliestHour == nil or elapsedHours < earliestHour then
        return false, nil, nil
    end

    local triggerMode = normalizeTriggerMode(run and run.triggerMode)
    if triggerMode == TRIGGER_MODE_CLOCK then
        return true, "schedule", deadlineHour
    end

    local signalReady, hungryMoodle = isHungrySignalReady(run, getSignalThresholdBand(run))
    if signalReady then
        return true, "hunger_signal", deadlineHour
    end
    if triggerMode == TRIGGER_MODE_STRICT_HUNGER_SIGNAL then
        if deadlineHour ~= nil and elapsedHours >= deadlineHour then
            addFinding(run, SEVERITY_FAIL, "strict_hunger_signal_missed_deadline",
                string.format("hunger signal did not arrive before %s deadline at %s",
                    tostring(meal and meal.label or "meal"),
                    formatMetricHour(deadlineHour)),
                { meal = meal and meal.label or "--", trigger = "strict_hunger_signal" })
            run.failureReason = "strict hunger signal missed deadline"
        end
        return false, getPendingCueReason(triggerMode, hungryMoodle), deadlineHour
    end
    if deadlineHour ~= nil and elapsedHours >= deadlineHour then
        return true, "deadline", deadlineHour
    end

    return false, getPendingCueReason(triggerMode, hungryMoodle), deadlineHour
end

local function getSequenceItem(run, itemIndex)
    local items = run and run.profile and run.profile.items or nil
    return items and items[itemIndex] or nil
end

local function getSequenceGapHours(run)
    return tonumber(run and run.profile and run.profile.minGapHours) or 0
end

local function getSignalMeal(run, mealIndex)
    local meals = run and run.profile and run.profile.meals or nil
    return meals and meals[mealIndex] or nil
end

local function buildSequenceMeal(run)
    local itemIndex = tonumber(run and run.nextSequenceItemIndex) or 1
    local itemSpec = getSequenceItem(run, itemIndex)
    if not itemSpec then
        return nil
    end
    return {
        id = string.format("junk_item_%02d", itemIndex),
        label = itemSpec.label or itemSpec.fullType or string.format("Item %02d", itemIndex),
        items = { itemSpec },
        signalSequence = true,
        sequenceIndex = itemIndex,
    }
end

local function shouldStartSequenceItem(run)
    local itemSpec = getSequenceItem(run, run and run.nextSequenceItemIndex)
    if not itemSpec then
        return false, "sequence_complete"
    end
    local elapsedHours = tonumber(run and run.elapsedHours) or 0
    local nextAllowedHour = tonumber(run and run.nextSequenceEligibleHour) or 0
    if elapsedHours < nextAllowedHour then
        return false, "cooldown"
    end
    local signalReady, hungryMoodle = isHungrySignalReady(run, getSignalThresholdBand(run))
    if signalReady then
        return true, "hunger_signal"
    end
    return false, getPendingCueReason(run and run.triggerMode, hungryMoodle)
end

local function shouldStartSignalMeal(run)
    local meal = getSignalMeal(run, run and run.nextMealIndex)
    if not meal then
        return false, "sequence_complete"
    end
    local elapsedHours = tonumber(run and run.elapsedHours) or 0
    local nextAllowedHour = tonumber(run and run.nextMealEligibleHour) or 0
    if elapsedHours < nextAllowedHour then
        return false, "cooldown"
    end
    local signalReady, hungryMoodle = isHungrySignalReady(run, getSignalThresholdBand(run))
    if signalReady then
        return true, "hunger_signal"
    end
    return false, getPendingCueReason(run and run.triggerMode, hungryMoodle)
end

local function getThermoSnapshot(playerObj)
    local bodyDamage = getPlayerBodyDamage(playerObj)
    local thermoregulator = bodyDamage and safeCall(bodyDamage, "getThermoregulator") or nil
    return {
        target = tonumber(thermoregulator and safeCall(thermoregulator, "getMetabolicTarget") or nil),
        real = tonumber(thermoregulator and safeCall(thermoregulator, "getMetabolicRateReal") or nil),
    }
end

snapshotPlayer = function(playerObj)
    local stats = getPlayerStats(playerObj)
    local nutrition = getPlayerNutrition(playerObj)
    local bodyDamage = getPlayerBodyDamage(playerObj)
    local state = Runtime.getStateCopy and Runtime.getStateCopy(playerObj) or nil
    local workload = Runtime.getCurrentWorkloadSnapshot and Runtime.getCurrentWorkloadSnapshot(playerObj) or nil
    local thermo = getThermoSnapshot(playerObj)
    return {
        state = state,
        workload = workload,
        hunger = clamp(getCharacterStat(stats, "HUNGER", "getHunger") or 0, 0, 1),
        thirst = clamp(getCharacterStat(stats, "THIRST", "getThirst") or 0, 0, 1),
        boredom = math.max(0, tonumber(getCharacterStat(stats, "BOREDOM", "getBoredom")) or 0),
        endurance = clamp(getCharacterStat(stats, "ENDURANCE", "getEndurance") or 0, 0, 1),
        fatigue = clamp(getCharacterStat(stats, "FATIGUE", "getFatigue") or 0, 0, 1),
        calories = tonumber(nutrition and safeCall(nutrition, "getCalories")) or 0,
        carbs = tonumber(nutrition and safeCall(nutrition, "getCarbohydrates")) or 0,
        fats = tonumber(nutrition and safeCall(nutrition, "getLipids")) or 0,
        proteins = tonumber(nutrition and safeCall(nutrition, "getProteins")) or 0,
        weight = tonumber(nutrition and safeCall(nutrition, "getWeight")) or 0,
        healthFromFood = tonumber(bodyDamage and safeCall(bodyDamage, "getHealthFromFood")) or 0,
        healthFromFoodTimer = tonumber(bodyDamage and safeCall(bodyDamage, "getHealthFromFoodTimer")) or 0,
        timedActionInstant = safeCall(playerObj, "isTimedActionInstantCheat") == true,
        foodEatenMoodle = getFoodEatenMoodle(playerObj),
        scenarioTraits = snapshotScenarioTraits(playerObj),
        thermoTarget = thermo.target,
        thermoReal = thermo.real,
        timeMultiplier = getTimeMultiplier(),
        gameSpeedMode = getGameSpeedMode(),
    }
end

local function getScenarioClockLabel(profile, elapsedHours)
    local baseHour = tonumber(profile and profile.baseClockHour) or 0
    local totalMinutes = math.max(0, math.floor(((baseHour + (tonumber(elapsedHours) or 0)) * 60) + 0.5))
    local hour = math.floor((totalMinutes / 60) % 24)
    local minute = totalMinutes % 60
    return string.format("%02d:%02d", hour, minute)
end

local function cloneTable(source)
    return copyTable(source)
end

local function normalizeTimeMultiplier(value)
    local numeric = tonumber(value)
    if numeric == nil then
        return tonumber(selectedTimeMultiplier) or 80
    end
    return clamp(numeric, 1, 200)
end

local function buildRunBaseline(profile)
    local baselineState = cloneTable(profile and profile.baselineState) or {}
    local baselineVisible = cloneTable(profile and profile.baselineVisible) or {}
    baselineState.weightKg = normalizeStartWeightKg(selectedStartWeightKg)
    return baselineState, baselineVisible
end

local function copySnapshotPayload(snapshot)
    if type(snapshot) ~= "table" then
        return nil
    end
    local payload = copyTable(snapshot) or {}
    if type(snapshot.state) == "table" then
        payload.state = copyTable(snapshot.state)
    end
    return payload
end

local function describeMeal(meal)
    return meal and tostring(meal.label or "--") or "--"
end

local function mealHasTag(mealObj, tag)
    return type(mealObj) == "table"
        and type(mealObj.tags) == "table"
        and mealObj.tags[tag] == true
end

local function describeItem(itemRun)
    if not itemRun then
        return "--"
    end
    return tostring(itemRun.label or itemRun.fullType or "--")
end

local function buildConsumeAction(playerObj, item)
    if item and safeCall(item, "getFluidContainer") ~= nil and type(ISDrinkFluidAction) == "table" then
        return ISDrinkFluidAction:new(playerObj, item, 1), "drink"
    end
    if type(ISEatFoodAction) == "table" then
        return ISEatFoodAction:new(playerObj, item, 1), "eat"
    end
    return nil, nil
end

local function getFluidFilledRatio(item)
    local fluidContainer = item and safeCall(item, "getFluidContainer") or nil
    if not fluidContainer then
        return nil
    end
    return tonumber(safeCall(fluidContainer, "getFilledRatio"))
end

local function readExpectedNutrition(item)
    if not item then
        return nil
    end

    local expected = {
        kcal = tonumber(safeCall(item, "getCalories")) or 0,
        carbs = tonumber(safeCall(item, "getCarbohydrates")) or 0,
        fats = tonumber(safeCall(item, "getLipids")) or 0,
        proteins = tonumber(safeCall(item, "getProteins")) or 0,
    }
    if expected.kcal <= 0 and expected.carbs <= 0 and expected.fats <= 0 and expected.proteins <= 0 then
        return nil
    end
    return expected
end

local formatMetricHour = RunnerUtils.formatMetricHour
local formatMetricNumber = RunnerUtils.formatMetricNumber

local function makeMetricEvent(run, snapshot, elapsedHours)
    return RunnerUtils.makeMetricEvent(getScenarioClockLabel, run and run.profile, snapshot, elapsedHours)
end

local measureMealConfirmation = RunnerUtils.measureMealConfirmation

local function ensureAnalysis(run)
    if run.analysis then
        return run.analysis
    end
    run.analysis = {
        peakDeprivation = { value = 0, hour = 0, clock = getScenarioClockLabel(run and run.profile, 0) },
        meals = {},
        timeInLowHours = 0,
        timeInDepletedHours = 0,
        lastObservedElapsedHours = 0,
    }
    return run.analysis
end

local function captureAnalysisEvent(run, key, snapshot, elapsedHours)
    local analysis = ensureAnalysis(run)
    if analysis[key] ~= nil then
        return
    end
    analysis[key] = makeMetricEvent(run, snapshot, elapsedHours)
end

local function updateDerivedSignals(run)
    if not run or not run.player then
        return
    end

    local analysis = ensureAnalysis(run)
    local elapsedHours = run.elapsedHours or getRunElapsedHours(run)
    local snapshot = snapshotPlayer(run.player)
    local state = snapshot and snapshot.state or {}
    local fuel = tonumber(state and state.fuel) or 0
    local deprivation = tonumber(state and state.deprivation) or 0
    local hunger = tonumber(snapshot and snapshot.hunger) or 0
    local anyThreshold = tonumber(run.profile and run.profile.validation and run.profile.validation.deprivationAnyThreshold) or 0.0001
    local zeroThreshold = tonumber(run.profile and run.profile.validation and run.profile.validation.deprivationZeroThreshold) or 0.0001
    local zone = tostring(state and state.lastZone or "")
    local previousObservedHours = tonumber(analysis.lastObservedElapsedHours) or 0
    local observedDelta = math.max(0, elapsedHours - previousObservedHours)
    analysis.lastObservedElapsedHours = elapsedHours

    if hunger >= (Metabolism.HUNGER_THRESHOLD_PECKISH or 0.16) then
        captureAnalysisEvent(run, "firstPeckish", snapshot, elapsedHours)
    end
    if hunger >= (Metabolism.HUNGER_THRESHOLD_HUNGRY or 0.25) then
        captureAnalysisEvent(run, "firstHungry", snapshot, elapsedHours)
    end
    if fuel < 500 then
        captureAnalysisEvent(run, "firstFuelBelow500", snapshot, elapsedHours)
    end
    if fuel < 300 then
        captureAnalysisEvent(run, "firstFuelBelow300", snapshot, elapsedHours)
    end
    if fuel <= 0 then
        captureAnalysisEvent(run, "firstFuelZero", snapshot, elapsedHours)
    end
    if zone == "Low" then
        captureAnalysisEvent(run, "firstLowZone", snapshot, elapsedHours)
        analysis.timeInLowHours = (tonumber(analysis.timeInLowHours) or 0) + observedDelta
    elseif zone == "Depleted" then
        captureAnalysisEvent(run, "firstDepletedZone", snapshot, elapsedHours)
        analysis.timeInDepletedHours = (tonumber(analysis.timeInDepletedHours) or 0) + observedDelta
    end
    if deprivation > anyThreshold then
        captureAnalysisEvent(run, "firstDeprivationAny", snapshot, elapsedHours)
    end
    if deprivation >= (Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10) then
        captureAnalysisEvent(run, "firstDeprivationPenalty", snapshot, elapsedHours)
    end
    if deprivation >= (tonumber(analysis.peakDeprivation and analysis.peakDeprivation.value) or -1) then
        analysis.peakDeprivation = makeMetricEvent(run, snapshot, elapsedHours)
        analysis.peakDeprivation.value = deprivation
    end

    local recoveryMealHour = analysis.recoveryMealCompletedHour
    if recoveryMealHour ~= nil and elapsedHours >= recoveryMealHour then
        if deprivation > zeroThreshold and deprivation < (Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10) then
            analysis.lastSubOnsetPositiveAfterRecovery = makeMetricEvent(run, snapshot, elapsedHours)
        end
        if deprivation <= zeroThreshold and analysis.deprivationZeroAfterRecovery == nil then
            analysis.deprivationZeroAfterRecovery = makeMetricEvent(run, snapshot, elapsedHours)
        end
    end
end

local function addEvaluation(run, severity, code, message)
    local analysis = ensureAnalysis(run)
    analysis.evaluations = analysis.evaluations or {}
    analysis.evaluations[#analysis.evaluations + 1] = {
        severity = severity,
        code = code,
        message = message,
    }
    addFinding(run, severity, code, message)
end

local function addAnalysisSummaryRow(run, code, message)
    recordRow(run, SEVERITY_PASS, code, message)
end

local function backfillAnalysisThresholdsFromConsumes(run, analysis)
    if not run or not analysis or analysis.firstPeckish ~= nil then
        return
    end
    local threshold = tonumber(Metabolism.HUNGER_THRESHOLD_PECKISH or 0.16) or 0.16
    for _, consume in ipairs(analysis.consumes or {}) do
        local hungerBefore = tonumber(consume and consume.hungerBefore)
        if hungerBefore ~= nil and hungerBefore >= threshold then
            analysis.firstPeckish = {
                hour = tonumber(consume.hour),
                clock = tostring(consume.clock or getScenarioClockLabel(run.profile, tonumber(consume.hour) or 0)),
                hunger = hungerBefore,
                fuel = tonumber(consume.fuelBefore),
                zone = nil,
            }
            return
        end
    end
end

local function finalizeAnalysis(run)
    if not run then
        return
    end
    if run.startedWorldHours == nil then
        return
    end

    updateDerivedSignals(run)
    local analysis = ensureAnalysis(run)
    backfillAnalysisThresholdsFromConsumes(run, analysis)
    local validation = run.profile and run.profile.validation or nil
    analysis.finalSnapshot = run.player and snapshotPlayer(run.player) or nil
    if not validation then
        return
    end

    analysis.summaryLines = ScenarioAnalysis.buildSummary and ScenarioAnalysis.buildSummary(run, {
        ensureAnalysis = ensureAnalysis,
        formatMetricHour = formatMetricHour,
        formatMetricNumber = formatMetricNumber,
    }) or {}

    addAnalysisSummaryRow(run, "analysis_summary",
        string.format("firstPeckish=%s energy=%s firstDepriv=%s peakDepriv=%s deprivZero=%s",
            formatMetricHour(analysis.firstPeckish and analysis.firstPeckish.hour),
            formatMetricNumber(analysis.firstPeckish and analysis.firstPeckish.fuel, "%.0f"),
            formatMetricHour(analysis.firstDeprivationAny and analysis.firstDeprivationAny.hour),
            formatMetricNumber(analysis.peakDeprivation and analysis.peakDeprivation.value, "%.3f"),
            formatMetricHour(analysis.deprivationZeroAfterRecovery and analysis.deprivationZeroAfterRecovery.hour)))

    if type(ScenarioAnalysis.evaluate) == "function" then
        ScenarioAnalysis.evaluate(run, {
            ensureAnalysis = ensureAnalysis,
            addEvaluation = addEvaluation,
            formatMetricHour = formatMetricHour,
            formatMetricNumber = formatMetricNumber,
            SEVERITY_PASS = SEVERITY_PASS,
            SEVERITY_WARN = SEVERITY_WARN,
            SEVERITY_FAIL = SEVERITY_FAIL,
        })
    end
end

local function getRunElapsedHours(run)
    local nowHours = getWorldHours()
    if not run or nowHours == nil or run.startedWorldHours == nil then
        return 0
    end
    return math.max(0, nowHours - run.startedWorldHours)
end

recordRow = function(run, severity, code, message, extra)
    if not run then
        return
    end

    local snapshot = run.player and snapshotPlayer(run.player) or {}
    local state = snapshot and snapshot.state or {}
    local workload = snapshot and snapshot.workload or {}
    local traitSummary = describeSelectedTraits(run and run.selectedTraits)
    local elapsedHours = getRunElapsedHours(run)
    local phase = run.currentPhase
    local mealRun = run.currentMeal
    local itemRun = mealRun and mealRun.currentItem or nil
    local row = {
        severity or SEVERITY_PASS,
        tostring(code or ""),
        tostring(message or ""),
        tostring(run.stage or ""),
        tostring(run.outcome or ""),
        tostring(getWorldHours() or ""),
        tostring(elapsedHours or ""),
        getScenarioClockLabel(run.profile, elapsedHours),
        tostring(phase and phase.label or ""),
        tostring(phase and phase.averageMet or ""),
        tostring(snapshot and snapshot.thermoTarget or ""),
        tostring(snapshot and snapshot.thermoReal or ""),
        tostring(state and state.lastWorkTier or workload and workload.workTier or ""),
        tostring(state and state.lastMetAverage or workload and workload.averageMet or ""),
        tostring(state and state.lastMetPeak or workload and workload.peakMet or ""),
        tostring(state and state.lastMetSource or workload and workload.source or ""),
        tostring(normalizeAvailabilityMode(run and run.availabilityMode)),
        tostring(traitSummary or ""),
        tostring((run and run.pendingBlockedReason) or ""),
        tostring((mealRun and mealRun.triggerReason) or (run.lastMealTriggerReason) or ""),
        describeMeal(mealRun and mealRun.meal or run.lastMeal),
        describeItem(itemRun),
        tostring(snapshot and snapshot.foodEatenMoodle or ""),
        tostring(snapshot and snapshot.hunger or ""),
        tostring(snapshot and snapshot.endurance or ""),
        tostring(snapshot and snapshot.fatigue or ""),
        tostring(snapshot and snapshot.healthFromFood or ""),
        tostring(snapshot and snapshot.healthFromFoodTimer or ""),
        tostring(snapshot and snapshot.timedActionInstant or ""),
        tostring(snapshot and snapshot.timeMultiplier or ""),
        tostring(state and state.fuel or ""),
        tostring(state and state.lastZone or ""),
        tostring(state and state.deprivation or ""),
        tostring(state and state.lastDeprivationTarget or ""),
        tostring(state and (state.lastUnderfeedingDebtKcal or state.underfeedingDebtKcal) or ""),
        tostring(state and state.satietyBuffer or ""),
        tostring(state and state.proteins or ""),
        tostring(state and state.weightKg or ""),
        tostring(state and state.weightController or ""),
        tostring(state and state.lastDepositKcal or ""),
        tostring(state and state.lastTraceReason or ""),
    }

    if type(extra) == "table" then
        if extra.phase then
            row[9] = tostring(extra.phase)
        end
        if extra.targetMet then
            row[10] = tostring(extra.targetMet)
        end
        if extra.blockReason then
            row[19] = tostring(extra.blockReason)
        end
        if extra.trigger then
            row[20] = tostring(extra.trigger)
        end
        if extra.meal then
            row[21] = tostring(extra.meal)
        end
        if extra.item then
            row[22] = tostring(extra.item)
        end
    end

    for index = 1, #row do
        row[index] = csvEscape(row[index])
    end
    run.reportRows[#run.reportRows + 1] = table.concat(row, ",")
end

addFinding = function(run, severity, code, message, extra)
    if not run then
        return
    end
    if severity == SEVERITY_FAIL then
        run.failCount = (run.failCount or 0) + 1
    elseif severity == SEVERITY_WARN then
        run.warnCount = (run.warnCount or 0) + 1
    end
    recordRow(run, severity, code, message, extra)
end

local deriveOutcome = RunnerUtils.deriveOutcome

local function saveReport(run)
    local relPath = RunnerUtils.saveReport(run, REPORT_HEADER)
    if relPath then
        lastReportPath = relPath
    end
    return relPath
end

local function setLastStatusFromRun(run)
    if not run then
        return
    end
    local elapsedHours = run.elapsedHours or getRunElapsedHours(run)
    local durationHours = tonumber(run.profile and run.profile.durationHours or 0)
    local phaseLabel = run.currentPhase and run.currentPhase.label or run.lastPhaseLabel or "--"
    local targetMet = run.currentPhase and run.currentPhase.averageMet or run.lastTargetMet or nil
    local consumptionMode = getConsumptionMode(run.profile)
    local nextMealDef, nextMealHour, nextMealDeadlineHour = nil, nil, nil
    local nextMeal = "--"
    local nextSequenceEligibleHour = nil
    local nextSequenceIndex = nil
    local signalThreshold = run.profile and run.profile.signalThreshold or nil
    if consumptionMode == CONSUMPTION_MODE_SIGNAL_SEQUENCE then
        local nextItem = getSequenceItem(run, run.nextSequenceItemIndex)
        nextMeal = run.currentMeal and describeMeal(run.currentMeal.meal)
            or (nextItem and tostring(nextItem.label or nextItem.fullType))
            or "--"
        nextSequenceEligibleHour = tonumber(run.nextSequenceEligibleHour)
        nextSequenceIndex = tonumber(run.nextSequenceItemIndex)
    elseif consumptionMode == CONSUMPTION_MODE_SIGNAL_MEALS then
        nextMealDef = run.profile and run.profile.meals and run.profile.meals[run.nextMealIndex] or nil
        nextMeal = run.currentMeal and describeMeal(run.currentMeal.meal)
            or (nextMealDef and nextMealDef.label)
            or "--"
        nextSequenceEligibleHour = tonumber(run.nextMealEligibleHour)
    else
        nextMealDef, nextMealHour, nextMealDeadlineHour = getNextMealWindow(run)
        nextMeal = run.currentMeal and describeMeal(run.currentMeal.meal)
            or (nextMealDef and nextMealDef.label)
            or "--"
    end

    local snapshot = run.player and snapshotPlayer(run.player) or {}
    local state = snapshot.state or {}
    local thermo = getThermoSnapshot(run.player)
    run.lastStatusSnapshot = snapshot

    local mealsCompleted = 0
    local mealsTotal = 0
    if consumptionMode == CONSUMPTION_MODE_SIGNAL_SEQUENCE then
        mealsCompleted = math.max(0, (run.nextSequenceItemIndex or 1) - 1)
        mealsTotal = run.profile and run.profile.items and #run.profile.items or 0
    elseif consumptionMode == CONSUMPTION_MODE_SIGNAL_MEALS then
        mealsCompleted = math.max(0, (run.nextMealIndex or 1) - 1)
        mealsTotal = run.profile and run.profile.meals and #run.profile.meals or 0
    else
        mealsCompleted = (run.nextMealIndex or 1) - 1
        mealsTotal = run.profile and run.profile.meals and #run.profile.meals or 0
        if run.currentMeal then mealsCompleted = mealsCompleted - 1 end
        if mealsCompleted < 0 then mealsCompleted = 0 end
    end

    local phasesTotal = run.profile and run.profile.phases and #run.profile.phases or 0
    local phaseIndex = tonumber(run.scriptedPhaseIndex) or 0

    lastStatus = {
        running = run.stage == "running",
        stage = run.stage,
        label = run.profile and run.profile.label or "Live Scripted Day",
        description = run.profile and run.profile.description or nil,
        outcome = run.outcome or deriveOutcome(run),
        phaseLabel = phaseLabel,
        phaseIndex = phaseIndex,
        phasesTotal = phasesTotal,
        targetMet = targetMet,
        thermoReal = thermo.real,
        consumptionMode = consumptionMode,
        triggerMode = normalizeTriggerMode(run.triggerMode),
        availabilityMode = normalizeAvailabilityMode(run.availabilityMode),
        phaseKind = run.currentPhaseKind,
        phaseRemainingHours = tonumber(run.scriptedPhaseRemainingHours),
        interruptedPhaseLabel = run.interruptedPhase and run.interruptedPhase.phase and run.interruptedPhase.phase.label or nil,
        interruptedPhaseRemainingHours = run.interruptedPhase and tonumber(run.interruptedPhase.remainingHours) or nil,
        nextMealLabel = nextMeal,
        nextMealHour = nextMealHour,
        nextMealDeadlineHour = nextMealDeadlineHour,
        nextSequenceEligibleHour = nextSequenceEligibleHour,
        nextSequenceIndex = nextSequenceIndex,
        signalThreshold = signalThreshold,
        currentMealTrigger = run.currentMeal and run.currentMeal.triggerReason or nil,
        lastMealTrigger = run.lastMealTriggerReason,
        currentMealLabel = run.currentMeal and describeMeal(run.currentMeal.meal) or nil,
        currentItemLabel = run.currentMeal and run.currentMeal.currentItem and run.currentMeal.currentItem.label or nil,
        startWeightKg = tonumber(run.startWeightKg),
        profileTimeMultiplier = tonumber(run.profileTimeMultiplier),
        traitSummary = describeSelectedTraits(run.selectedTraits),
        selectedTraits = cloneSelectedTraitFlags(run.selectedTraits),
        mealsCompleted = mealsCompleted,
        mealsTotal = mealsTotal,
        elapsedHours = elapsedHours,
        durationHours = durationHours,
        progress = durationHours > 0 and (elapsedHours / durationHours) or 0,
        scenarioClock = getScenarioClockLabel(run.profile, elapsedHours),
        reportPath = run.reportPath or lastReportPath,
        failCount = run.failCount or 0,
        warnCount = run.warnCount or 0,
        failureReason = run.failureReason,
        abortReason = run.abortReason,
        fuel = tonumber(state.fuel),
        zone = state.lastZone,
        hunger = snapshot.hunger,
        hungerBand = state.lastHungerBand,
        deprivation = tonumber(state.deprivation),
        satiety = tonumber(state.satietyBuffer),
        protein = tonumber(state.proteins),
        weightKg = tonumber(state.weightKg),
        weightController = tonumber(state.weightController),
        endurance = snapshot.endurance,
        fatigue = snapshot.fatigue,
        lastDepositKcal = tonumber(state.lastDepositKcal),
        mealLog = run.mealLog or {},
        analysisSummary = run.analysis and (run.analysis.summaryLines
            or (ScenarioAnalysis.buildSummary and ScenarioAnalysis.buildSummary(run, {
                ensureAnalysis = ensureAnalysis,
                formatMetricHour = formatMetricHour,
                formatMetricNumber = formatMetricNumber,
            }))) or nil,
        analysisEvaluations = run.analysis and run.analysis.evaluations or nil,
        statusLines = {
            string.format("Stage %s  Outcome %s", tostring(run.stage or "--"), tostring(run.outcome or deriveOutcome(run))),
            string.format("Phase %s  Target MET %s", tostring(phaseLabel or "--"), targetMet and string.format("%.2f", targetMet) or "--"),
            string.format("Next Meal %s  Elapsed %s", tostring(nextMeal or "--"), string.format("%.2fh", tonumber(elapsedHours or 0))),
            string.format("Start Weight %s", run.startWeightKg and string.format("%.1f kg", tonumber(run.startWeightKg) or 0) or "--"),
            string.format("Runner Speed %sx", tostring(math.floor(tonumber(run.profileTimeMultiplier) or 0))),
            string.format("Traits %s", describeSelectedTraits(run.selectedTraits)),
            string.format("Availability %s", normalizeAvailabilityMode(run.availabilityMode) == AVAILABILITY_MODE_INTERRUPT_WORK_FOR_FOOD and "Interrupt work for food" or "Eat anytime"),
            string.format("Report %s", tostring(run.reportPath or lastReportPath or "--")),
        },
    }
end

local function setTimedActionInstant(playerObj, enabled)
    if not playerObj then
        return false
    end
    if not safeInvoke(playerObj, "setTimedActionInstantCheat", enabled == true) then
        return false
    end
    return safeCall(playerObj, "isTimedActionInstantCheat") == (enabled == true)
end

local function restoreTimedActionInstant(run, enabled)
    if not run or not run.player then
        return false
    end
    return setTimedActionInstant(run.player, enabled)
end

local function clearWorkloadOverride(run, reason)
    if run and run.player and Runtime.clearScriptedWorkloadOverride then
        Runtime.clearScriptedWorkloadOverride(run.player, reason or "live-runner-clear")
    end
end

local function applyPhaseOverride(run, phase)
    if not run or not run.player or not phase then
        return false
    end
    if type(Runtime.setScriptedWorkloadOverride) == "function" then
        Runtime.setScriptedWorkloadOverride(run.player, {
            averageMet = phase.averageMet,
            peakMet = phase.averageMet,
            source = "scripted_override",
            targetName = phase.metabolics,
        }, "live-runner-phase")
    end
    if type(Metabolics) == "table" and Metabolics[phase.metabolics]
        and safeInvoke(run.player, "setMetabolicTarget", Metabolics[phase.metabolics]) then
        return true
    end
    return false
end

local function getPhaseDurationHours(phase)
    if type(phase) ~= "table" then
        return 0
    end
    if phase.durationHours ~= nil then
        return math.max(0, tonumber(phase.durationHours) or 0)
    end
    local startHour = tonumber(phase.startHour)
    local endHour = tonumber(phase.endHour)
    if startHour ~= nil and endHour ~= nil then
        return math.max(0, endHour - startHour)
    end
    return 0
end

local function setActivePhase(run, phase, code, message)
    run.currentPhase = phase
    run.lastPhaseLabel = phase and phase.label or "--"
    run.lastTargetMet = phase and phase.averageMet or nil
    run.phaseValidateAfter = (getWorldHours() or 0) + (2 / 60)
    run.phaseValidated = false
    recordRow(run, SEVERITY_PASS, code or "phase_entered", message or "entered scripted phase", {
        phase = phase and phase.label or "--",
        targetMet = phase and phase.averageMet or "",
    })
end

local function advanceToNextScriptedPhase(run, debtHours)
    local phases = run and run.profile and run.profile.phases or nil
    if type(phases) ~= "table" then
        run.currentPhase = nil
        run.currentPhaseKind = nil
        run.scriptedPhaseIndex = nil
        run.scriptedPhaseRemainingHours = nil
        return
    end

    local nextIndex = (run.scriptedPhaseIndex or 0) + 1
    local nextPhase = phases[nextIndex]
    if not nextPhase then
        run.currentPhase = nil
        run.currentPhaseKind = nil
        run.scriptedPhaseIndex = nextIndex
        run.scriptedPhaseRemainingHours = 0
        return
    end

    run.scriptedPhaseIndex = nextIndex
    run.scriptedPhaseRemainingHours = getPhaseDurationHours(nextPhase)
    run.currentPhaseKind = "scripted"
    setActivePhase(run, nextPhase, "phase_entered", "entered scripted phase")

    local remainingDebt = tonumber(debtHours) or 0
    if remainingDebt > 0 and run.scriptedPhaseRemainingHours ~= nil then
        run.scriptedPhaseRemainingHours = run.scriptedPhaseRemainingHours - remainingDebt
    end
end

local function initializePhaseExecution(run)
    local firstPhase = run and run.profile and run.profile.phases and run.profile.phases[1] or nil
    if not firstPhase then
        return
    end
    run.scriptedPhaseIndex = 1
    run.scriptedPhaseRemainingHours = getPhaseDurationHours(firstPhase)
    run.currentPhaseKind = "scripted"
    run.phaseProgressWorldHours = getWorldHours() or run.startedWorldHours or 0
    setActivePhase(run, firstPhase, "phase_entered", "entered scripted phase")
end

local function enterMealBreak(run, meal, triggerReason)
    if not run or run.currentPhaseKind ~= "scripted" or not phaseInterruptibleForFood(run.currentPhase) then
        return
    end
    run.interruptedPhase = {
        index = run.scriptedPhaseIndex,
        phase = run.currentPhase,
        remainingHours = tonumber(run.scriptedPhaseRemainingHours) or 0,
    }
    recordRow(run, SEVERITY_PASS, "phase_interrupted_for_food",
        string.format("%s interrupted for food", tostring(run.currentPhase and run.currentPhase.label or "phase")),
        { meal = meal and meal.label or "--", trigger = triggerReason or "" })
    local mealBreakPhase = {
        label = "Meal Break",
        metabolics = "SedentaryActivity",
        averageMet = 1.2,
    }
    run.currentPhaseKind = "meal_break"
    setActivePhase(run, mealBreakPhase, "meal_break_started", "started meal break")
end

local function resumeInterruptedPhase(run)
    if not run or not run.interruptedPhase then
        return
    end
    local interrupted = run.interruptedPhase
    run.interruptedPhase = nil
    run.scriptedPhaseIndex = interrupted.index
    run.scriptedPhaseRemainingHours = interrupted.remainingHours
    run.currentPhaseKind = "scripted"
    setActivePhase(run, interrupted.phase, "phase_resumed_after_food", "resumed interrupted phase after food")
end

local function updatePhaseProgress(run)
    if not run then
        return
    end
    local nowHours = getWorldHours() or 0
    local lastHours = tonumber(run.phaseProgressWorldHours) or nowHours
    local delta = math.max(0, nowHours - lastHours)
    run.phaseProgressWorldHours = nowHours
    if delta <= 0 or run.currentPhaseKind ~= "scripted" then
        return
    end

    local debt = delta
    while debt > 0 and run.currentPhaseKind == "scripted" and run.currentPhase do
        local remaining = tonumber(run.scriptedPhaseRemainingHours) or 0
        if remaining > debt then
            run.scriptedPhaseRemainingHours = remaining - debt
            debt = 0
        else
            debt = debt - math.max(0, remaining)
            advanceToNextScriptedPhase(run, 0)
            if run.currentPhaseKind == "scripted" and run.scriptedPhaseRemainingHours ~= nil and debt > 0 then
                run.scriptedPhaseRemainingHours = (tonumber(run.scriptedPhaseRemainingHours) or 0) - debt
                debt = 0
            end
        end
    end
end

local function ensurePhase(run)
    if not run.currentPhase then
        initializePhaseExecution(run)
    end
    if not run.currentPhase then
        return
    end
    if not applyPhaseOverride(run, run.currentPhase) then
        addFinding(run, SEVERITY_FAIL, "met_override_apply_failed", "failed to apply scripted metabolic override", {
            phase = run.currentPhase.label,
            targetMet = run.currentPhase.averageMet,
        })
        run.failureReason = "met override apply failed"
    end
end

local function validatePhaseMet(run)
    if not run or not run.currentPhase or run.phaseValidated then
        return
    end
    local nowHours = getWorldHours() or 0
    if nowHours < (run.phaseValidateAfter or 0) then
        return
    end
    run.phaseValidated = true
    local thermo = getThermoSnapshot(run.player)
    local target = tonumber(thermo.target)
    local desired = tonumber(run.currentPhase.averageMet)
    if target == nil or not nearlyEqual(target, desired, MET_TOLERANCE) then
        addFinding(run, SEVERITY_FAIL, "met_override_not_observed",
            string.format("thermoregulator target did not settle near %.2f (actual=%s)", desired or 0, tostring(target)),
            { phase = run.currentPhase.label, targetMet = desired })
        run.failureReason = "met override not observed"
        return
    end
    recordRow(run, SEVERITY_PASS, "met_override_observed", "thermoregulator target matched scripted phase", {
        phase = run.currentPhase.label,
        targetMet = desired,
    })
end

local function spawnMealItem(run, itemSpec)
    local inventory = getInventory(run.player)
    if not inventory then
        return nil, "inventory unavailable"
    end
    local item = safeCall(inventory, "AddItem", itemSpec.fullType)
    if not item then
        return nil, "spawn failed"
    end
    local prepared = itemSpec and itemSpec.prepared or nil
    if type(prepared) == "table" then
        if prepared.cooked ~= nil then
            safeInvoke(item, "setCooked", prepared.cooked == true)
        end
        if prepared.burnt ~= nil then
            safeInvoke(item, "setBurnt", prepared.burnt == true)
        end
        if prepared.heat ~= nil then
            safeInvoke(item, "setHeat", tonumber(prepared.heat) or prepared.heat)
        end
        if prepared.cookedInMicrowave ~= nil then
            safeInvoke(item, "setCookedInMicrowave", prepared.cookedInMicrowave == true)
        end
    end
    run.spawnedItems[#run.spawnedItems + 1] = item
    return item
end

local function beginMealItem(run, mealRun)
    local meal = mealRun and mealRun.meal or nil
    local itemSpec = meal and meal.items and meal.items[mealRun.itemIndex] or nil
    if not itemSpec then
        return false
    end
    local moodleLevel = getFoodEatenMoodle(run.player)
    if moodleLevel ~= nil and moodleLevel >= 3 then
        addFinding(run, SEVERITY_FAIL, "meal_blocked_food_eaten_moodle",
            string.format("FOOD_EATEN moodle=%s blocks ISEatFoodAction start", tostring(moodleLevel)),
            { meal = meal.label, item = itemSpec.label or itemSpec.fullType })
        run.failureReason = "food eaten moodle blocked meal"
        return false
    end

    local item, err = spawnMealItem(run, itemSpec)
    if not item then
        addFinding(run, SEVERITY_FAIL, "meal_spawn_failed", tostring(err or "spawn failed"), {
            meal = meal.label,
            item = itemSpec.label or itemSpec.fullType,
        })
        run.failureReason = "meal spawn failed"
        return false
    end

    local expected = readExpectedNutrition(item)
    mealRun.currentItem = {
        label = itemSpec.label or itemSpec.fullType,
        fullType = itemSpec.fullType,
        item = item,
        itemId = tonumber(safeCall(item, "getID") or nil),
        expected = cloneTable(expected),
        queuedWorldHours = getWorldHours(),
        preConsumeSnapshot = snapshotPlayer(run.player),
        preFluidRatio = getFluidFilledRatio(item),
    }
    run.lastItem = mealRun.currentItem

    local cheatApplied = restoreTimedActionInstant(run, true)
    if not cheatApplied then
        addFinding(run, SEVERITY_WARN, "timed_action_instant_unavailable", "timed-action instant cheat could not be enabled", {
            meal = meal.label,
            item = mealRun.currentItem.label,
        })
    end

    local action, actionKind = buildConsumeAction(run.player, item)
    if not action then
        addFinding(run, SEVERITY_FAIL, "meal_action_unavailable", "no compatible vanilla consume action for scripted item", {
            meal = meal.label,
            item = mealRun.currentItem.label,
        })
        run.failureReason = "meal action unavailable"
        return false
    end
    local queue = ISTimedActionQueue.add(action)
    mealRun.currentItem.action = action
    mealRun.currentItem.actionKind = actionKind
    mealRun.currentItem.queue = queue
    mealRun.currentItem.timeoutWorldHours = (getWorldHours() or 0) + (15 / 60)
    recordRow(run, SEVERITY_PASS, "meal_action_queued", "queued consume action for scripted meal item", {
        meal = meal.label,
        item = mealRun.currentItem.label,
    })
    return true
end

local function completeMeal(run, mealRun)
    restoreTimedActionInstant(run, run.snapshot and run.snapshot.visible and run.snapshot.visible.timedActionInstant == true)
    run.lastMeal = mealRun and mealRun.meal or run.lastMeal
    if mealRun then
        recordRow(run, SEVERITY_PASS, "meal_complete", "completed scripted meal", {
            meal = mealRun.meal and mealRun.meal.label or "--",
        })
        local snapshot = run.player and snapshotPlayer(run.player) or {}
        local state = snapshot.state or {}
        local elapsedHours = run.elapsedHours or getRunElapsedHours(run)
        run.mealLog = run.mealLog or {}
        local itemNames = {}
        for _, itemSpec in ipairs(mealRun.meal and mealRun.meal.items or {}) do
            itemNames[#itemNames + 1] = itemSpec.label or itemSpec.fullType or "?"
        end
        run.mealLog[#run.mealLog + 1] = {
            label = mealRun.meal and mealRun.meal.label or "--",
            clock = getScenarioClockLabel(run.profile, elapsedHours),
            atHour = elapsedHours,
            trigger = mealRun.triggerReason,
            items = itemNames,
            fuelAfter = tonumber(state.fuel),
            hungerAfter = snapshot.hunger,
            depositKcal = tonumber(state.lastDepositKcal),
        }
        local analysis = ensureAnalysis(run)
        analysis.consumes = analysis.consumes or {}
        analysis.consumes[#analysis.consumes + 1] = {
            id = mealRun.meal and mealRun.meal.id or nil,
            label = mealRun.meal and mealRun.meal.label or "--",
            clock = getScenarioClockLabel(run.profile, elapsedHours),
            hour = elapsedHours,
            trigger = mealRun.triggerReason,
            hungerBefore = tonumber(mealRun.preMealSnapshot and mealRun.preMealSnapshot.hunger),
            hungerAfter = tonumber(snapshot.hunger),
            hungerDrop = tonumber(mealRun.preMealSnapshot and mealRun.preMealSnapshot.hunger) and tonumber(snapshot.hunger)
                and (tonumber(mealRun.preMealSnapshot.hunger) - tonumber(snapshot.hunger)) or nil,
            fuelBefore = tonumber(mealRun.preMealSnapshot and mealRun.preMealSnapshot.state and mealRun.preMealSnapshot.state.fuel),
            fuelAfter = tonumber(state.fuel),
            deprivationBefore = tonumber(mealRun.preMealSnapshot and mealRun.preMealSnapshot.state and mealRun.preMealSnapshot.state.deprivation),
            deprivationAfter = tonumber(state.deprivation),
            itemCount = #(mealRun.meal and mealRun.meal.items or {}),
        }
        local validation = run.profile and run.profile.validation or nil
        local mealId = mealRun.meal and mealRun.meal.id or nil
        if mealId then
            analysis.meals[mealId] = analysis.meals[mealId] or {}
            analysis.meals[mealId].label = mealRun.meal.label or mealId
            analysis.meals[mealId].hour = elapsedHours
            analysis.meals[mealId].clock = getScenarioClockLabel(run.profile, elapsedHours)
            analysis.meals[mealId].fuelAfter = tonumber(state.fuel)
            analysis.meals[mealId].hungerAfter = tonumber(snapshot.hunger)
            analysis.meals[mealId].deprivationAfter = tonumber(state.deprivation)
            local hungerBefore = tonumber(analysis.meals[mealId].hungerBefore)
            if hungerBefore ~= nil and analysis.meals[mealId].hungerAfter ~= nil then
                analysis.meals[mealId].hungerDrop = hungerBefore - analysis.meals[mealId].hungerAfter
            end
        end
        if validation and mealRun.meal and mealHasTag(mealRun.meal, "recovery") then
            analysis.recoveryMealCompletedHour = elapsedHours
            analysis.recoveryMealHungerAfter = tonumber(snapshot.hunger)
            analysis.recoveryMealFuelAfter = tonumber(state.fuel)
            analysis.recoveryMealDeprivationAfter = tonumber(state.deprivation)
        end
    end
    run.lastItem = nil
    run.lastMealTriggerReason = mealRun and mealRun.triggerReason or run.lastMealTriggerReason
    run.currentMeal = nil
    clearBlockedEatState(run)
    if run.currentPhaseKind == "meal_break" then
        recordRow(run, SEVERITY_PASS, "meal_break_completed", "completed meal break")
        resumeInterruptedPhase(run)
    end
    local consumptionMode = getConsumptionMode(run.profile)
    if consumptionMode == CONSUMPTION_MODE_SIGNAL_SEQUENCE then
        run.nextSequenceItemIndex = (run.nextSequenceItemIndex or 1) + 1
        run.nextSequenceEligibleHour = (run.elapsedHours or getRunElapsedHours(run)) + getSequenceGapHours(run)
    elseif consumptionMode == CONSUMPTION_MODE_SIGNAL_MEALS then
        run.nextMealIndex = (run.nextMealIndex or 1) + 1
        run.nextMealEligibleHour = (run.elapsedHours or getRunElapsedHours(run)) + getSequenceGapHours(run)
    else
        run.nextMealIndex = run.nextMealIndex + 1
    end
end

local function tickMeal(run)
    local mealRun = run.currentMeal
    if not mealRun then
        local meal = nil
        local shouldStart = false
        local triggerReason = nil
        local deadlineHour = nil
        local consumptionMode = getConsumptionMode(run.profile)
        if consumptionMode == CONSUMPTION_MODE_SIGNAL_SEQUENCE then
            meal = buildSequenceMeal(run)
            shouldStart, triggerReason = shouldStartSequenceItem(run)
        elseif consumptionMode == CONSUMPTION_MODE_SIGNAL_MEALS then
            meal = run.profile and run.profile.meals and run.profile.meals[run.nextMealIndex] or nil
            shouldStart, triggerReason = shouldStartSignalMeal(run)
        else
            meal = run.profile and run.profile.meals and run.profile.meals[run.nextMealIndex] or nil
            shouldStart, triggerReason, deadlineHour = shouldStartMeal(run, run.nextMealIndex)
        end
        if meal and shouldStart then
            if normalizeAvailabilityMode(run.availabilityMode) == AVAILABILITY_MODE_INTERRUPT_WORK_FOR_FOOD
                and run.currentPhaseKind == "scripted"
                and phaseInterruptibleForFood(run.currentPhase) then
                enterMealBreak(run, meal, triggerReason or normalizeTriggerMode(run.triggerMode))
            end
            clearBlockedEatState(run)
            local preMealSnapshot = snapshotPlayer(run.player)
            run.currentMeal = {
                meal = meal,
                itemIndex = 1,
                preMealSnapshot = preMealSnapshot,
                triggerReason = triggerReason,
                deadlineHour = deadlineHour,
            }
            run.lastMeal = meal
            run.lastItem = nil
            recordRow(run, SEVERITY_PASS, "meal_started", "started scripted meal", {
                meal = meal.label,
                trigger = triggerReason or normalizeTriggerMode(run.triggerMode),
            })
            local analysis = ensureAnalysis(run)
            if meal.id then
                analysis.meals[meal.id] = analysis.meals[meal.id] or {}
                analysis.meals[meal.id].label = meal.label or meal.id
                analysis.meals[meal.id].hungerBefore = tonumber(preMealSnapshot and preMealSnapshot.hunger)
                analysis.meals[meal.id].fuelBefore = tonumber(preMealSnapshot and preMealSnapshot.state and preMealSnapshot.state.fuel)
                analysis.meals[meal.id].deprivationBefore = tonumber(preMealSnapshot and preMealSnapshot.state and preMealSnapshot.state.deprivation)
                analysis.meals[meal.id].trigger = triggerReason
                analysis.meals[meal.id].deadlineHour = deadlineHour
                analysis.meals[meal.id].sequenceIndex = meal.sequenceIndex
            end
            local validation = run.profile and run.profile.validation or nil
            if validation and mealHasTag(meal, "recovery") then
                analysis.recoveryMealStartedHour = run.elapsedHours
                analysis.recoveryMealHungerBefore = tonumber(preMealSnapshot and preMealSnapshot.hunger)
                analysis.recoveryMealFuelBefore = tonumber(preMealSnapshot and preMealSnapshot.state and preMealSnapshot.state.fuel)
                analysis.recoveryMealDeprivationBefore = tonumber(preMealSnapshot and preMealSnapshot.state and preMealSnapshot.state.deprivation)
            end
            mealRun = run.currentMeal
        else
            return
        end
    end

    if mealRun.itemIndex > #(mealRun.meal.items or {}) then
        completeMeal(run, mealRun)
        return
    end

    if not mealRun.currentItem then
        beginMealItem(run, mealRun)
        return
    end

    local currentItem = mealRun.currentItem
    local inventory = getInventory(run.player)
    local itemPresent = inventoryContainsItem(inventory, currentItem.item)
    local currentSnapshot = snapshotPlayer(run.player)
    local currentState = currentSnapshot and currentSnapshot.state or nil
    local currentFluidRatio = getFluidFilledRatio(currentItem.item)
    local fluidConsumed = currentItem.actionKind == "drink"
        and currentItem.preFluidRatio ~= nil
        and currentFluidRatio ~= nil
        and currentFluidRatio < (currentItem.preFluidRatio - 0.01)

    if not itemPresent then
        local confirmation = measureMealConfirmation(currentItem.preConsumeSnapshot, currentSnapshot, currentItem.expected)
        currentItem.disappearedWorldHours = currentItem.disappearedWorldHours or (getWorldHours() or 0)

        if not confirmation.confirmed and (getWorldHours() or 0) < ((currentItem.disappearedWorldHours or 0) + (2 / 60)) then
            return
        end

        if not confirmation.confirmed then
            addFinding(run, SEVERITY_FAIL, "deposit_missing_after_meal",
                string.format(
                    "item %s vanished without a matching NMS deposit fuelDelta=%.1f proteinDelta=%.1f satietyDelta=%.3f hungerDrop=%.4f lastDeposit=%.1f",
                    tostring(currentItem.label),
                    tonumber(confirmation.fuelDelta or 0),
                    tonumber(confirmation.proteinDelta or 0),
                    tonumber(confirmation.satietyDelta or 0),
                    tonumber(confirmation.hungerDrop or 0),
                    tonumber(confirmation.lastDepositKcal or 0)
                ),
                { meal = mealRun.meal.label, item = currentItem.label })
            run.failureReason = "deposit missing after meal"
            return
        end
        if confirmation.expectedKcal > 0 and (tonumber(confirmation.lastDepositKcal or 0) > (confirmation.expectedKcal * 1.5)
            or tonumber(confirmation.fuelDelta or 0) > (confirmation.expectedKcal * 1.8)) then
            addFinding(run, SEVERITY_FAIL, "duplicate_deposit_detected",
                string.format("deposit exceeds expected for %s lastDeposit=%.1f fuelDelta=%.1f expected=%.1f",
                    tostring(currentItem.label),
                    tonumber(confirmation.lastDepositKcal or 0),
                    tonumber(confirmation.fuelDelta or 0),
                    tonumber(confirmation.expectedKcal or 0)),
                { meal = mealRun.meal.label, item = currentItem.label })
            run.failureReason = "duplicate deposit detected"
            return
        end

        recordRow(run, SEVERITY_PASS, "meal_item_consumed", "meal item consumed through vanilla path", {
            meal = mealRun.meal.label,
            item = currentItem.label,
        })
        mealRun.currentItem = nil
        mealRun.itemIndex = mealRun.itemIndex + 1
        if mealRun.itemIndex > #(mealRun.meal.items or {}) then
            completeMeal(run, mealRun)
        end
        return
    end

    if fluidConsumed then
        recordRow(run, SEVERITY_PASS, "meal_item_consumed", "meal item consumed through vanilla path", {
            meal = mealRun.meal.label,
            item = currentItem.label,
        })
        mealRun.currentItem = nil
        mealRun.itemIndex = mealRun.itemIndex + 1
        if mealRun.itemIndex > #(mealRun.meal.items or {}) then
            completeMeal(run, mealRun)
        end
        return
    end

    if (getWorldHours() or 0) >= (currentItem.timeoutWorldHours or 0) then
        addFinding(run, SEVERITY_FAIL, "meal_consume_not_observed",
            string.format("timed consume action did not complete for %s", tostring(currentItem.label)),
            { meal = mealRun.meal.label, item = currentItem.label })
        run.failureReason = "meal consume not observed"
        return
    end
end

local function recordPeriodicSample(run)
    local minuteIndex = math.floor((run.elapsedHours or 0) * 60)
    if minuteIndex < 0 then
        minuteIndex = 0
    end
    if run.lastSampleMinute == nil or minuteIndex >= (run.lastSampleMinute + SAMPLE_INTERVAL_MINUTES) then
        run.lastSampleMinute = minuteIndex
        recordRow(run, SEVERITY_PASS, "sample", "periodic live sample")
    end
end

local function maintainThirst(run)
    if not run or not run.player then
        return
    end
    local nowHours = getWorldHours() or 0
    if nowHours < (run.nextThirstMaintenanceHours or 0) then
        return
    end
    run.nextThirstMaintenanceHours = nowHours + THIRST_TOP_UP_INTERVAL_HOURS

    local stats = getPlayerStats(run.player)
    local thirst = getCharacterStat(stats, "THIRST", "getThirst")
    if thirst == nil or thirst <= THIRST_TOP_UP_THRESHOLD then
        return
    end
    if not setCharacterStat(stats, "THIRST", "setThirst", THIRST_TOP_UP_TARGET) then
        addFinding(run, SEVERITY_WARN, "thirst_top_up_failed",
            string.format("failed to restore thirst from %.3f", tonumber(thirst or 0)))
        return
    end
    recordRow(run, SEVERITY_PASS, "thirst_top_up",
        string.format("restored thirst from %.3f to %.3f", tonumber(thirst or 0), THIRST_TOP_UP_TARGET))
end

local function maintainBoredom(run)
    if not run or not run.player then
        return
    end
    local nowHours = getWorldHours() or 0
    if nowHours < (run.nextBoredomMaintenanceHours or 0) then
        return
    end
    run.nextBoredomMaintenanceHours = nowHours + BOREDOM_TOP_UP_INTERVAL_HOURS

    local stats = getPlayerStats(run.player)
    local boredom = tonumber(getCharacterStat(stats, "BOREDOM", "getBoredom")) or 0
    if boredom <= BOREDOM_TOP_UP_THRESHOLD then
        return
    end
    if not setCharacterStat(stats, "BOREDOM", "setBoredom", BOREDOM_TOP_UP_TARGET) then
        addFinding(run, SEVERITY_WARN, "boredom_top_up_failed",
            string.format("failed to restore boredom from %.3f", boredom))
        return
    end
    recordRow(run, SEVERITY_PASS, "boredom_top_up",
        string.format("restored boredom from %.3f to %.3f", boredom, BOREDOM_TOP_UP_TARGET))
end

local function applyBaseline(run)
    if not run or not run.player then
        return false
    end

    if Runtime.debugClearSuppressions then
        Runtime.debugClearSuppressions(run.player, "live-runner-baseline")
    end
    clearWorkloadOverride(run, "live-runner-baseline")
    clearTimedActions(run.player)

    if not Runtime.debugResetState or not Runtime.debugSetStateFields or not Runtime.debugSetVisibleBaselines then
        addFinding(run, SEVERITY_FAIL, "baseline_runtime_helpers_missing", "required runtime debug helpers are unavailable")
        run.failureReason = "baseline runtime helpers missing"
        return false
    end

    Runtime.debugResetState(run.player, "live-runner-baseline")
    Runtime.debugSetStateFields(run.player, run.baselineState, "live-runner-baseline")
    local state = Runtime.getStateCopy and Runtime.getStateCopy(run.player) or nil
    local visible = cloneTable(run.baselineVisible) or {}
    visible.healthFromFood = tonumber(state and state.baseHealthFromFood) or tonumber(run.snapshot and run.snapshot.visible and run.snapshot.visible.healthFromFood) or 0
    Runtime.debugSetVisibleBaselines(run.player, visible, "live-runner-baseline")
    local stats = getPlayerStats(run.player)
    if visible.thirst ~= nil then
        setCharacterStat(stats, "THIRST", "setThirst", visible.thirst)
    end
    if visible.boredom ~= nil then
        setCharacterStat(stats, "BOREDOM", "setBoredom", visible.boredom)
    end
    if Runtime.syncVisibleShell then
        Runtime.syncVisibleShell(run.player, "live-runner-baseline")
    end

    local actual = snapshotPlayer(run.player)
    local ok = true
    ok = ok and type(actual.state) == "table"
    ok = ok and nearlyEqual(actual.hunger, run.baselineVisible.hunger, RESTORE_TOLERANCE.hunger)
    if run.baselineVisible.thirst ~= nil then
        ok = ok and nearlyEqual(actual.thirst, run.baselineVisible.thirst, RESTORE_TOLERANCE.thirst)
    end
    if run.baselineVisible.boredom ~= nil then
        ok = ok and nearlyEqual(actual.boredom, run.baselineVisible.boredom, RESTORE_TOLERANCE.boredom)
    end
    ok = ok and nearlyEqual(actual.endurance, run.baselineVisible.endurance, RESTORE_TOLERANCE.endurance)
    ok = ok and nearlyEqual(actual.fatigue, run.baselineVisible.fatigue, RESTORE_TOLERANCE.fatigue)
    ok = ok and nearlyEqual(actual.state and actual.state.fuel, run.baselineState.fuel, RESTORE_TOLERANCE.fuel)
    ok = ok and nearlyEqual(actual.state and actual.state.deprivation, run.baselineState.deprivation, RESTORE_TOLERANCE.deprivation)
    ok = ok and nearlyEqual(actual.state and actual.state.satietyBuffer, run.baselineState.satietyBuffer, RESTORE_TOLERANCE.satietyBuffer)
    ok = ok and nearlyEqual(actual.state and actual.state.weightKg, run.baselineState.weightKg, RESTORE_TOLERANCE.weightKg)
    if not ok then
        addFinding(run, SEVERITY_FAIL, "baseline_apply_failed", "canonical baseline did not stick")
        run.failureReason = "baseline apply failed"
        return false
    end

    recordRow(run, SEVERITY_PASS, "baseline_applied", "canonical blank-slate baseline applied")
    return true
end

local function captureSnapshot(run)
    if not run or not run.player then
        return false
    end

    if not Runtime.buildStateSnapshot then
        addFinding(run, SEVERITY_FAIL, "snapshot_missing_state", "state snapshot helper unavailable")
        run.failureReason = "snapshot helper unavailable"
        return false
    end

    run.snapshot = {
        state = Runtime.buildStateSnapshot(run.player, "live-runner-snapshot"),
        visible = snapshotPlayer(run.player),
        traits = snapshotScenarioTraits(run.player),
        timeMultiplier = getTimeMultiplier(),
        restoreGameSpeedMode = getGameSpeedMode(),
    }

    if type(run.snapshot.state) ~= "table" or type(run.snapshot.state.state) ~= "table" then
        addFinding(run, SEVERITY_FAIL, "snapshot_missing_state", "failed to capture authoritative NMS snapshot")
        run.failureReason = "snapshot missing state"
        return false
    end

    recordRow(run, SEVERITY_PASS, "snapshot_captured", "captured pre-run player snapshot")
    return true
end

local function checkPreflight(run)
    if not run.player then
        addFinding(run, SEVERITY_FAIL, "preflight_no_player", "no local player available")
        run.failureReason = "no player"
        return false
    end
    if safeCall(run.player, "isAsleep") == true then
        addFinding(run, SEVERITY_FAIL, "preflight_player_busy", "player is asleep")
        run.failureReason = "player asleep"
        return false
    end
    if safeCall(run.player, "getVehicle") ~= nil then
        addFinding(run, SEVERITY_FAIL, "preflight_player_busy", "player is in a vehicle")
        run.failureReason = "player in vehicle"
        return false
    end
    if safeCall(run.player, "isPlayerMoving") == true then
        addFinding(run, SEVERITY_FAIL, "preflight_player_busy", "player must be idle before starting live scenario")
        run.failureReason = "player moving"
        return false
    end
    if hasTimedActions(run.player) then
        addFinding(run, SEVERITY_FAIL, "preflight_player_busy", "player already has timed actions queued")
        run.failureReason = "timed actions already queued"
        return false
    end
    if type(Runtime.setScriptedWorkloadOverride) ~= "function" or type(Runtime.clearScriptedWorkloadOverride) ~= "function" then
        addFinding(run, SEVERITY_FAIL, "preflight_runtime_override_missing", "scripted workload override helpers are unavailable")
        run.failureReason = "runtime override missing"
        return false
    end
    if type(ISTimedActionQueue) ~= "table" or (type(ISEatFoodAction) ~= "table" and type(ISDrinkFluidAction) ~= "table") then
        addFinding(run, SEVERITY_FAIL, "preflight_vanilla_actions_missing", "required vanilla consume/timed action modules are unavailable")
        run.failureReason = "vanilla action modules missing"
        return false
    end
    recordRow(run, SEVERITY_PASS, "preflight_pass", "preflight checks passed")
    return true
end

local function cleanupSpawnedItems(run)
    local leftover = 0
    local inventory = run and run.player and getInventory(run.player) or nil
    for _, item in ipairs(run and run.spawnedItems or {}) do
        if inventory and inventoryContainsItem(inventory, item) then
            leftover = leftover + 1
            removeInventoryItem(inventory, item)
            if inventoryContainsItem(inventory, item) then
                addFinding(run, SEVERITY_WARN, "cleanup_leftover_spawned_items",
                    string.format("failed to remove leftover spawned item %s", tostring(safeCall(item, "getFullType") or "?")),
                    { item = tostring(safeCall(item, "getFullType") or "?") })
            end
        end
    end
    run.spawnedItems = {}
    return leftover
end

local function restoreSnapshot(run)
    if not run or not run.player or not run.snapshot then
        return false
    end

    run.stage = "restoring"
    finalizeAnalysis(run)
    recordRow(run, SEVERITY_PASS, "restore_started", "starting player restore")

    clearTimedActions(run.player)
    clearWorkloadOverride(run, "live-runner-restore")
    if type(Metabolics) == "table" and Metabolics.StandingAtRest then
        safeInvoke(run.player, "setMetabolicTarget", Metabolics.StandingAtRest)
    end

    if run.snapshot.restoreGameSpeedMode ~= nil then
        if not restoreGameSpeedMode(run.snapshot.restoreGameSpeedMode) then
            addFinding(run, SEVERITY_WARN, "restore_game_speed_mode_failed", "failed to restore pre-run game speed mode")
        end
    end
    restoreTimedActionInstant(run, run.snapshot.visible and run.snapshot.visible.timedActionInstant == true)

    if Runtime.importStateSnapshot then
        local restorePayload = copySnapshotPayload(run.snapshot.state)
        local nowHours = getWorldHours()
        if restorePayload then
            restorePayload.worldHours = nowHours
            if type(restorePayload.state) == "table" then
                restorePayload.state.lastWorldHours = nowHours
            end
        end
        Runtime.importStateSnapshot(run.player, restorePayload or run.snapshot.state, "live-runner-restore")
    end
    local restoreTraitsOk, restoreTraitLabel = applyScenarioTraits(run.player, run.snapshot.traits)
    if not restoreTraitsOk then
        addFinding(run, SEVERITY_FAIL, "restore_traits_failed",
            string.format("failed to restore scenario trait %s", tostring(restoreTraitLabel or "?")))
    end
    local stats = getPlayerStats(run.player)
    if run.snapshot.visible and run.snapshot.visible.thirst ~= nil then
        setCharacterStat(stats, "THIRST", "setThirst", run.snapshot.visible.thirst)
    end
    if run.snapshot.visible and run.snapshot.visible.boredom ~= nil then
        setCharacterStat(stats, "BOREDOM", "setBoredom", run.snapshot.visible.boredom)
    end
    if Runtime.debugSetVisibleBaselines and run.snapshot.visible then
        Runtime.debugSetVisibleBaselines(run.player, {
            hunger = run.snapshot.visible.hunger,
            endurance = run.snapshot.visible.endurance,
            fatigue = run.snapshot.visible.fatigue,
            healthFromFood = run.snapshot.visible.healthFromFood,
            healthFromFoodTimer = run.snapshot.visible.healthFromFoodTimer,
        }, "live-runner-restore")
    end
    if Runtime.syncVisibleShell then
        Runtime.syncVisibleShell(run.player, "live-runner-restore")
    end

    cleanupSpawnedItems(run)

    local restored = snapshotPlayer(run.player)
    local before = run.snapshot.visible or {}
    local beforeState = run.snapshot.state and run.snapshot.state.state or {}
    local restoreOk = true
    local multiplierDrift = nil

    restoreOk = restoreOk and nearlyEqual(restored.hunger, before.hunger, RESTORE_TOLERANCE.hunger)
    restoreOk = restoreOk and nearlyEqual(restored.thirst, before.thirst, RESTORE_TOLERANCE.thirst)
    restoreOk = restoreOk and nearlyEqual(restored.boredom, before.boredom, RESTORE_TOLERANCE.boredom)
    restoreOk = restoreOk and nearlyEqual(restored.endurance, before.endurance, RESTORE_TOLERANCE.endurance)
    restoreOk = restoreOk and nearlyEqual(restored.fatigue, before.fatigue, RESTORE_TOLERANCE.fatigue)
    restoreOk = restoreOk and nearlyEqual(restored.healthFromFood, before.healthFromFood, RESTORE_TOLERANCE.healthFromFood)
    if before.timeMultiplier ~= nil and restored.timeMultiplier ~= nil then
        local beforeMode = tonumber(run.snapshot.restoreGameSpeedMode)
        local restoredMode = tonumber(restored.gameSpeedMode)
        if beforeMode ~= nil and restoredMode ~= nil and beforeMode == restoredMode then
            local allowedDelta = math.max(RESTORE_TOLERANCE.multiplier, math.abs(tonumber(before.timeMultiplier) or 0) * 0.35)
            multiplierDrift = math.abs((tonumber(restored.timeMultiplier) or 0) - (tonumber(before.timeMultiplier) or 0))
            if multiplierDrift > allowedDelta then
                recordRow(run, SEVERITY_PASS, "restore_time_multiplier_drift",
                    string.format("raw time multiplier drifted pre=%.4f post=%.4f",
                        tonumber(before.timeMultiplier or 0),
                        tonumber(restored.timeMultiplier or 0)))
            end
        end
    end
    if run.snapshot.restoreGameSpeedMode ~= nil and restored.gameSpeedMode ~= nil then
        restoreOk = restoreOk and tonumber(restored.gameSpeedMode) == tonumber(run.snapshot.restoreGameSpeedMode)
    end
    restoreOk = restoreOk and restored.timedActionInstant == (before.timedActionInstant == true)
    restoreOk = restoreOk and nearlyEqual(restored.state and restored.state.fuel, beforeState.fuel, RESTORE_TOLERANCE.fuel)
    restoreOk = restoreOk and nearlyEqual(restored.state and restored.state.deprivation, beforeState.deprivation, RESTORE_TOLERANCE.deprivation)
    restoreOk = restoreOk and nearlyEqual(restored.state and restored.state.satietyBuffer, beforeState.satietyBuffer, RESTORE_TOLERANCE.satietyBuffer)
    restoreOk = restoreOk and nearlyEqual(restored.state and restored.state.proteins, beforeState.proteins, RESTORE_TOLERANCE.proteins)
    restoreOk = restoreOk and nearlyEqual(restored.state and restored.state.weightKg, beforeState.weightKg, RESTORE_TOLERANCE.weightKg)
    restoreOk = restoreOk and nearlyEqual(restored.state and restored.state.weightController, beforeState.weightController, RESTORE_TOLERANCE.weightController)
    local restoredTraits = restored.scenarioTraits or {}
    local beforeTraits = run.snapshot.traits or {}
    for _, trait in ipairs(SCENARIO_TRAITS) do
        restoreOk = restoreOk and (restoredTraits[trait.id] == beforeTraits[trait.id])
    end

    if not restoreOk then
        addFinding(run, SEVERITY_FAIL, "restore_state_mismatch", "restored player state does not match pre-run snapshot")
    else
        recordRow(run, SEVERITY_PASS, "restore_completed", "player restore completed successfully")
    end

    if Runtime.getScriptedWorkloadOverride and Runtime.getScriptedWorkloadOverride(run.player) then
        addFinding(run, SEVERITY_FAIL, "runner_override_leaked", "scripted workload override still active after restore")
    end

    run.outcome = deriveOutcome(run)
    if run.abortRequested then
        run.stage = "aborted"
    elseif run.outcome == "FAIL" then
        run.stage = "failed"
    else
        run.stage = "complete"
    end
    run.reportPath = saveReport(run)
    setLastStatusFromRun(run)
    activeRun = nil
    return restoreOk
end

local function abortRun(run, reason)
    if not run then
        return false
    end
    run.abortRequested = tostring(reason or run.abortRequested or "aborted")
    run.failureReason = nil
    run.abortReason = run.abortRequested
    addFinding(run, SEVERITY_FAIL, "runner_aborted", run.abortReason)
    return restoreSnapshot(run)
end

local function failRun(run, code, message)
    if not run then
        return false
    end
    if code and message then
        addFinding(run, SEVERITY_FAIL, code, message)
    end
    return restoreSnapshot(run)
end

local function startRun(profile)
    local baselineState, baselineVisible = buildRunBaseline(profile)
    local runTimeMultiplier = normalizeTimeMultiplier(selectedTimeMultiplier)
    local run = {
        profile = profile,
        profileTimeMultiplier = runTimeMultiplier,
        baselineState = baselineState,
        baselineVisible = baselineVisible,
        startWeightKg = tonumber(baselineState and baselineState.weightKg),
        player = getLocalPlayer(),
        stage = "preflight",
        outcome = "PASS",
        failCount = 0,
        warnCount = 0,
        reportRows = {},
        spawnedItems = {},
        mealLog = {},
        nextMealIndex = 1,
        nextSequenceItemIndex = 1,
        nextSequenceEligibleHour = 0,
        nextMealEligibleHour = 0,
        elapsedHours = 0,
        triggerMode = getEffectiveTriggerMode(profile, selectedTriggerMode),
        availabilityMode = normalizeAvailabilityMode(selectedAvailabilityMode),
        selectedTraits = cloneSelectedTraitFlags(selectedTraitFlags),
    }

    recordRow(run, SEVERITY_PASS, "runner_created", "created live scripted scenario run")

    if not checkPreflight(run) then
        run.stage = "failed"
        run.outcome = deriveOutcome(run)
        run.reportPath = saveReport(run)
        setLastStatusFromRun(run)
        return nil
    end

    if not captureSnapshot(run) or not applyBaseline(run) then
        restoreSnapshot(run)
        return nil
    end

    local appliedTraitsOk, failedTraitLabel = applyScenarioTraits(run.player, run.selectedTraits)
    if not appliedTraitsOk then
        addFinding(run, SEVERITY_FAIL, "scenario_traits_apply_failed",
            string.format("failed to apply scenario trait %s", tostring(failedTraitLabel or "?")))
        restoreSnapshot(run)
        return nil
    end
    recordRow(run, SEVERITY_PASS, "scenario_traits_applied",
        string.format("applied scenario traits: %s", describeSelectedTraits(run.selectedTraits)))

    if not setTimeMultiplier(runTimeMultiplier) or not validateRequestedTimeAcceleration(run, runTimeMultiplier) then
        addFinding(run, SEVERITY_FAIL, "time_accel_not_applied",
            string.format(
                "failed to apply accelerated live time request=%s actual=%s base=%s ratio=%s",
                tostring(runTimeMultiplier),
                tostring(getTimeMultiplier()),
                tostring(run.snapshot.visible and run.snapshot.visible.timeMultiplier or "--"),
                tostring(run.lastAppliedTimeRatio or "--")
            ))
        restoreSnapshot(run)
        return nil
    end
    recordRow(run, SEVERITY_PASS, "time_accel_applied", "applied accelerated live time")

    run.startedWorldHours = getWorldHours()
    run.stage = "running"
    run.outcome = "PASS"
    activeRun = run
    ensurePhase(run)
    setLastStatusFromRun(run)
    return run
end

local function tickActiveRun(playerObj)
    local run = activeRun
    if not run or run.player ~= playerObj or run.stage ~= "running" then
        return
    end

    if run.abortRequested then
        abortRun(run, run.abortRequested)
        return
    end

    if run.failureReason then
        failRun(run, nil, nil)
        return
    end

    if tonumber(run.profileTimeMultiplier) and tonumber(run.profileTimeMultiplier) > 0 then
        setTimeMultiplier(run.profileTimeMultiplier)
    end

    run.elapsedHours = getRunElapsedHours(run)
    updatePhaseProgress(run)
    if (not run.currentPhase or not run.currentPhaseKind) and not run.currentMeal then
        restoreSnapshot(run)
        return
    end

    maintainThirst(run)
    maintainBoredom(run)
    ensurePhase(run)
    if run.failureReason then
        failRun(run, nil, nil)
        return
    end

    validatePhaseMet(run)
    if run.failureReason then
        failRun(run, nil, nil)
        return
    end

    tickMeal(run)
    if run.failureReason then
        failRun(run, nil, nil)
        return
    end

    updateDerivedSignals(run)
    recordPeriodicSample(run)
    setLastStatusFromRun(run)
end

function Runner.start(profileId)
    if activeRun then
        return false
    end
    local profile = ScenarioCatalog.getProfile and ScenarioCatalog.getProfile(profileId) or nil
    local run = startRun(profile)
    return run ~= nil
end

function Runner.setTriggerMode(mode)
    selectedTriggerMode = normalizeTriggerMode(mode)
    if activeRun then
        activeRun.triggerMode = selectedTriggerMode
        setLastStatusFromRun(activeRun)
    elseif lastStatus then
        lastStatus.triggerMode = selectedTriggerMode
    end
    return selectedTriggerMode
end

function Runner.getTriggerMode()
    return normalizeTriggerMode(selectedTriggerMode)
end

function Runner.getTriggerModes()
    local modes = {}
    for _, mode in ipairs(TRIGGER_MODES) do
        modes[#modes + 1] = {
            id = mode.id,
            label = mode.label,
        }
    end
    return modes
end

function Runner.setAvailabilityMode(mode)
    selectedAvailabilityMode = normalizeAvailabilityMode(mode)
    if activeRun then
        activeRun.availabilityMode = selectedAvailabilityMode
        setLastStatusFromRun(activeRun)
    elseif lastStatus then
        lastStatus.availabilityMode = selectedAvailabilityMode
    end
    return selectedAvailabilityMode
end

function Runner.getAvailabilityMode()
    return normalizeAvailabilityMode(selectedAvailabilityMode)
end

function Runner.getAvailabilityModes()
    local modes = {}
    for _, mode in ipairs(AVAILABILITY_MODES) do
        modes[#modes + 1] = {
            id = mode.id,
            label = mode.label,
        }
    end
    return modes
end

function Runner.setStartWeightKg(value)
    selectedStartWeightKg = normalizeStartWeightKg(value)
    if activeRun then
        activeRun.startWeightKg = selectedStartWeightKg
        if activeRun.baselineState then
            activeRun.baselineState.weightKg = selectedStartWeightKg
        end
        setLastStatusFromRun(activeRun)
    elseif lastStatus then
        lastStatus.startWeightKg = selectedStartWeightKg
    end
    return selectedStartWeightKg
end

function Runner.getStartWeightKg()
    return normalizeStartWeightKg(selectedStartWeightKg)
end

function Runner.abort(reason)
    if not activeRun then
        return false
    end
    activeRun.abortRequested = tostring(reason or "aborted")
    return true
end

function Runner.getTraitOptions()
    local traits = {}
    for _, trait in ipairs(SCENARIO_TRAITS) do
        traits[#traits + 1] = {
            id = trait.id,
            label = trait.label,
            selected = selectedTraitFlags[trait.id] == true,
        }
    end
    return traits
end

function Runner.setTraitSelected(traitId, enabled)
    local key = tostring(traitId or "")
    for _, trait in ipairs(SCENARIO_TRAITS) do
        if trait.id == key then
            selectedTraitFlags[trait.id] = enabled == true
            if activeRun then
                activeRun.selectedTraits = cloneSelectedTraitFlags(selectedTraitFlags)
                setLastStatusFromRun(activeRun)
            elseif lastStatus then
                lastStatus.selectedTraits = cloneSelectedTraitFlags(selectedTraitFlags)
                lastStatus.traitSummary = describeSelectedTraits(selectedTraitFlags)
            end
            return selectedTraitFlags[trait.id]
        end
    end
    return false
end

function Runner.isTraitSelected(traitId)
    return selectedTraitFlags[tostring(traitId or "")] == true
end

function Runner.isRunning()
    return activeRun ~= nil and activeRun.stage == "running"
end

function Runner.getStatus()
    if activeRun then
        setLastStatusFromRun(activeRun)
    end
    return lastStatus
end

function Runner.getLastReportPath()
    return lastReportPath
end

function Runner.getProfiles()
    return ScenarioCatalog.getProfiles and ScenarioCatalog.getProfiles() or {}
end

function Runner.getTimeMultiplierOptions()
    local options = {}
    for _, option in ipairs(TIME_MULTIPLIER_PRESETS) do
        options[#options + 1] = {
            id = option.id,
            label = option.label,
            multiplier = option.multiplier,
        }
    end
    return options
end

function Runner.setTimeMultiplier(multiplier)
    selectedTimeMultiplier = normalizeTimeMultiplier(multiplier)
    if activeRun then
        activeRun.profileTimeMultiplier = selectedTimeMultiplier
        setLastStatusFromRun(activeRun)
    elseif lastStatus then
        lastStatus.profileTimeMultiplier = selectedTimeMultiplier
    end
    return selectedTimeMultiplier
end

function Runner.getTimeMultiplier()
    return normalizeTimeMultiplier(selectedTimeMultiplier)
end

if Events and Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
    Events.OnPlayerUpdate.Add(function(playerObj)
        tickActiveRun(playerObj)
    end)
end

return Runner
