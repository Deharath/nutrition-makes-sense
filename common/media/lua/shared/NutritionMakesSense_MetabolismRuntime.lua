NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_Metabolism"
require "NutritionMakesSense_CoreUtils"
require "NutritionMakesSense_MPSnapshot"
require "NutritionMakesSense_Settings"

local Runtime = NutritionMakesSense.MetabolismRuntime or {}
NutritionMakesSense.MetabolismRuntime = Runtime

local Metabolism = NutritionMakesSense.Metabolism
local MP = NutritionMakesSense.MP or {}
local CoreUtils = NutritionMakesSense.CoreUtils or {}
local MPSnapshot = NutritionMakesSense.MPSnapshot or {}
local Settings = NutritionMakesSense.Settings or {}
local STATE_KEY = tostring(MP.MOD_STATE_KEY or "NutritionMakesSenseState")
local ANCHOR = Metabolism.VANILLA_NUTRITION_ANCHOR
local DEPOSIT_EPSILON = 0.001
local SYNC_EPSILON = 0.0001
local VISIBLE_HUNGER_IMPORT_EPSILON = 0.0005
local MANUAL_VISIBLE_HUNGER_IMPORT_EPSILON = 0.01
local DEFAULT_WORKLOAD_SOURCE = "fallback_rest"
local REPORTED_ACTIVITY_TTL_HOURS = 0.10
local REPORTED_WORKLOAD_WINDOW_HOURS = 8 / 3600
local activityCacheByPlayerKey = {}
local scriptedWorkloadOverrideByPlayerKey = {}
local DebugSupport = NutritionMakesSense.DebugSupport or {}

local function log(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(msg)
    else
        print("[NutritionMakesSense] " .. tostring(msg))
    end
end

local safeCall = CoreUtils.safeCall
local hasTrait = CoreUtils.hasTrait

local function clamp(value, minValue, maxValue)
    return Metabolism.clamp(value, minValue, maxValue)
end
local roundToStep = CoreUtils.roundToStep

local telemetryByState = setmetatable({}, { __mode = "k" })
local TELEMETRY_FIELDS = {}
for _, field in ipairs(MPSnapshot.DIAGNOSTIC_STATE_FIELDS or {}) do
    TELEMETRY_FIELDS[#TELEMETRY_FIELDS + 1] = field
end
for _, field in ipairs({
    "lastEnduranceObserved", "lastWeightDeltaKg", "lastWeightRateKgPerWeek",
    "pendingObservedHungerDrop", "pendingObservedHungerAge", "pendingMealPreVisibleHunger", "pendingMealTransaction",
    "pendingResumeWorldHours", "pendingResumeReason",
}) do
    TELEMETRY_FIELDS[#TELEMETRY_FIELDS + 1] = field
end

local function newTelemetry(state, seed)
    local telemetry = {}
    for _, field in ipairs(TELEMETRY_FIELDS) do
        local value = type(seed) == "table" and seed[field] or nil
        if value ~= nil then
            telemetry[field] = value
        end
    end
    telemetry.lastMetAverage = tonumber(telemetry.lastMetAverage) or Metabolism.MET_REST
    telemetry.lastMetPeak = tonumber(telemetry.lastMetPeak) or telemetry.lastMetAverage
    telemetry.lastWorkTier = Metabolism.normalizeWorkTier(
        telemetry.lastWorkTier or Metabolism.classifyWorkTier(telemetry.lastMetAverage, false)
    )
    telemetry.lastMetSource = tostring(telemetry.lastMetSource or "bootstrap")
    telemetry.lastSyncedHunger = tonumber(telemetry.lastSyncedHunger)
        or tonumber(state and state.visibleHunger) or 0
    telemetry.lastTraceReason = tostring(telemetry.lastTraceReason or "init")
    if type(telemetry.pendingMealTransaction) ~= "table" then
        telemetry.pendingMealTransaction = nil
    end
    return telemetry
end

local function getTelemetryForState(state, seed)
    if type(state) ~= "table" then
        return nil
    end
    local telemetry = telemetryByState[state]
    if telemetry then
        return telemetry
    end
    telemetry = newTelemetry(state, seed or state)
    telemetryByState[state] = telemetry
    return telemetry
end

local function replaceTelemetryForState(state, seed)
    if type(state) ~= "table" then
        return nil
    end
    local telemetry = newTelemetry(state, seed)
    telemetryByState[state] = telemetry
    return telemetry
end

local function buildStateView(state, telemetry)
    if type(state) ~= "table" then
        return nil
    end
    local view = Metabolism.copyState(state)
    for _, field in ipairs(TELEMETRY_FIELDS) do
        local value = telemetry and telemetry[field] or nil
        if value ~= nil then
            view[field] = value
        end
    end
    view.lastZone = Metabolism.getFuelZone(view.fuel)
    view.lastHungerBand = Metabolism.getVisibleHungerBand(view.visibleHunger)
    view.lastWeightTrait = Metabolism.getWeightTrait(view.weightKg)
    view.lastDeprivationTarget = Metabolism.getDeprivationTarget(view)
    view.lastFuelPressureFactor = tonumber(view.lastFuelPressureFactor) or Metabolism.getFuelPressureFactor(view.fuel)
    view.lastGateMultiplier = tonumber(view.lastGateMultiplier) or Metabolism.getHungerGateMultiplier(view.fuel)
    view.lastEnergyAppetiteProgress = tonumber(view.lastEnergyAppetiteProgress)
        or Metabolism.getEnergyAppetiteProgress(view.weightBalanceKcal)
    view.lastProteinDeficiency = tonumber(view.lastProteinDeficiency)
        or Metabolism.getProteinDeficiencyProgress(view.proteins, view.weightKg)
    view.lastProteinHealingMultiplier = Metabolism.getProteinHealingMultiplier(view.proteins, view.weightKg)
    view.lastMealPreHunger = tonumber(view.lastMealPreHunger) or view.visibleHunger
    view.lastMealTargetHunger = tonumber(view.lastMealTargetHunger) or view.visibleHunger
    return view
end

local function recordDepositTelemetry(telemetry, report)
    if not telemetry or type(report) ~= "table" then
        return
    end
    telemetry.lastDepositKcal = tonumber(report.kcal) or 0
    telemetry.totalIntakeKcal = (tonumber(telemetry.totalIntakeKcal) or 0) + telemetry.lastDepositKcal
    telemetry.lastTraceReason = tostring(report.reason or report.label or "food")
    telemetry.lastSatietyQuality = tonumber(report.satietyQuality) or 0
    telemetry.lastSatietyContribution = tonumber(report.satietyContribution) or 0
    telemetry.lastSatietyReturnFactor = tonumber(report.satietyReturnFactorAfter) or 1
end

local function recordAdvanceTelemetry(telemetry, report)
    if not telemetry or type(report) ~= "table" then
        return
    end
    telemetry.lastMetAverage = tonumber(report.averageMet) or Metabolism.MET_REST
    telemetry.lastMetPeak = tonumber(report.peakMet) or telemetry.lastMetAverage
    telemetry.lastWorkTier = tostring(report.workTier or Metabolism.WORK_TIER_REST)
    telemetry.lastMetSource = tostring(report.source or "runtime")
    telemetry.lastObservedHours = tonumber(report.observedHours) or 0
    telemetry.lastHeavyHours = tonumber(report.heavyHours) or 0
    telemetry.lastVeryHeavyHours = tonumber(report.veryHeavyHours) or 0
    telemetry.lastBurnKcal = tonumber(report.burnedKcal) or 0
    telemetry.lastPassiveHungerGain = tonumber(report.visibleHungerGain) or 0
    telemetry.lastFuelPressureFactor = tonumber(report.peakFuelPressureFactor) or 1
    telemetry.lastGateMultiplier = tonumber(report.peakGateMultiplier) or 1
    telemetry.lastMetHungerFactor = tonumber(report.peakMetHungerFactor) or 1
    telemetry.lastEnergyAppetiteProgress = tonumber(report.peakEnergyAppetiteProgress) or 0
    telemetry.lastEnergyAppetiteRatePerHour = tonumber(report.peakEnergyAppetiteRatePerHour) or 0
    telemetry.lastHungerRateMultiplier = tonumber(report.hungerRateMultiplier) or 1
    telemetry.lastStatsDecreaseMultiplier = tonumber(report.statsDecreaseMultiplier) or 1
    telemetry.lastAppetiteRateMultiplier = tonumber(report.appetiteRateMultiplier) or 1
    telemetry.lastEnergyBurnMultiplier = tonumber(report.energyBurnMultiplier) or 1
    telemetry.lastExtraEnduranceDrain = tonumber(report.extraEnduranceDrain) or 0
    telemetry.lastProteinDeficiency = tonumber(report.peakProteinDeficiency) or telemetry.lastProteinDeficiency
    telemetry.lastSatietyReturnFactor = tonumber(report.satietyReturnFactor) or 1
    telemetry.lastTraceReason = tostring(report.reason or "advance")

    local elapsedHours = math.max(0, tonumber(report.elapsedHours) or 0)
    if elapsedHours > 0 then
        telemetry.totalBurnKcal = (tonumber(telemetry.totalBurnKcal) or 0) + telemetry.lastBurnKcal
        telemetry.totalVisibleHungerGain = (tonumber(telemetry.totalVisibleHungerGain) or 0)
            + telemetry.lastPassiveHungerGain
        telemetry.totalObservedHours = (tonumber(telemetry.totalObservedHours) or 0) + elapsedHours
        if report.sleepObserved == true or tostring(report.source or "") == "sleep" then
            telemetry.totalSleepHours = (tonumber(telemetry.totalSleepHours) or 0) + elapsedHours
        end
        telemetry.lastWeightDeltaKg = tonumber(report.weightDeltaKg) or 0
        telemetry.lastWeightRateKgPerWeek = tonumber(report.weightRateKgPerWeek) or 0
    end
end

local function isClientOnly()
    return type(isClient) == "function" and isClient() and not (type(isServer) == "function" and isServer())
end

local function isDedicatedServerRuntime()
    return type(isServer) == "function" and isServer() == true
end

local function shouldRunAuthoritativeUpdates()
    return not isClientOnly()
end

local getWorldHours = CoreUtils.getWorldHours

local function resolveStatsDecreaseMultiplier()
    local options = SandboxOptions and SandboxOptions.instance or nil
    local multiplier = tonumber(safeCall(options, "getStatsDecreaseMultiplier"))
    if multiplier == nil then
        return 1.0
    end
    return math.max(0, multiplier)
end

local function normalizeDeposit(values)
    return {
        -- Runtime consume payloads already carry hunger in visible-hunger units.
        hunger = tonumber(values and values.hunger) or 0,
        baseHunger = tonumber(values and (values.baseHunger or values.hunger)) or 0,
        kcal = math.max(0, tonumber(values and values.kcal) or 0),
        carbs = math.max(0, tonumber(values and values.carbs) or 0),
        fats = math.max(0, tonumber(values and values.fats) or 0),
        proteins = math.max(0, tonumber(values and values.proteins) or 0),
    }
end

local function hasMeaningfulDeposit(values)
    return (tonumber(values and values.kcal) or 0) > DEPOSIT_EPSILON
        or (tonumber(values and values.carbs) or 0) > DEPOSIT_EPSILON
        or (tonumber(values and values.fats) or 0) > DEPOSIT_EPSILON
        or (tonumber(values and values.proteins) or 0) > DEPOSIT_EPSILON
end

local getPlayerLabel = CoreUtils.getPlayerLabel
local getPlayerStats = CoreUtils.getPlayerStats
local getCharacterStatValue = CoreUtils.getCharacterStatValue

local function getVisibleHungerValue(stats)
    return getCharacterStatValue(stats, "HUNGER", "getHunger")
end

local function normalizeVisibleHungerInput(value)
    local numeric = tonumber(value)
    if numeric == nil then
        return nil
    end

    if math.abs(numeric) > 1 then
        numeric = numeric / 100
    end

    return clamp(numeric, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
end

local function resolveTraitEffects(playerObj)
    local effects = Metabolism.normalizeTraitEffects(nil)
    if not playerObj then
        return effects
    end

    if hasTrait(playerObj, "Hearty Appetite", "HEARTY_APPETITE") then
        effects.satietyDecayMultiplier = effects.satietyDecayMultiplier * Metabolism.TRAIT_SATIETY_DECAY_MULTIPLIER_HEARTY_APPETITE
    end
    if hasTrait(playerObj, "Light Eater", "LIGHT_EATER") then
        effects.satietyDecayMultiplier = effects.satietyDecayMultiplier * Metabolism.TRAIT_SATIETY_DECAY_MULTIPLIER_LIGHT_EATER
    end
    if hasTrait(playerObj, "Slow Metabolism", "WEIGHT_GAIN") then
        effects.burnMultiplier = effects.burnMultiplier * Metabolism.TRAIT_BURN_MULTIPLIER_SLOW_METABOLISM
        effects.weightGainMultiplier = effects.weightGainMultiplier * Metabolism.TRAIT_WEIGHT_GAIN_MULTIPLIER_SLOW_METABOLISM
        effects.weightLossMultiplier = effects.weightLossMultiplier * Metabolism.TRAIT_WEIGHT_LOSS_MULTIPLIER_SLOW_METABOLISM
    end
    if hasTrait(playerObj, "Fast Metabolism", "WEIGHT_LOSS") then
        effects.burnMultiplier = effects.burnMultiplier * Metabolism.TRAIT_BURN_MULTIPLIER_FAST_METABOLISM
        effects.weightGainMultiplier = effects.weightGainMultiplier * Metabolism.TRAIT_WEIGHT_GAIN_MULTIPLIER_FAST_METABOLISM
        effects.weightLossMultiplier = effects.weightLossMultiplier * Metabolism.TRAIT_WEIGHT_LOSS_MULTIPLIER_FAST_METABOLISM
    end

    return effects
end

local getPlayerNutrition = CoreUtils.getPlayerNutrition
local getPlayerBodyDamage = CoreUtils.getPlayerBodyDamage
local getPlayerThermoregulator = CoreUtils.getPlayerThermoregulator

local function setNutritionAnchor(nutrition)
    if not nutrition then
        return false
    end

    local calories = tonumber(safeCall(nutrition, "getCalories")) or 0
    local carbs = tonumber(safeCall(nutrition, "getCarbohydrates")) or 0
    local fats = tonumber(safeCall(nutrition, "getLipids")) or 0
    local proteins = tonumber(safeCall(nutrition, "getProteins")) or 0

    local changed = math.abs(calories - ANCHOR.calories) > SYNC_EPSILON
        or math.abs(carbs - ANCHOR.carbs) > SYNC_EPSILON
        or math.abs(fats - ANCHOR.fats) > SYNC_EPSILON
        or math.abs(proteins - ANCHOR.proteins) > SYNC_EPSILON

    if not changed then
        return false
    end
    safeCall(nutrition, "setCalories", ANCHOR.calories)
    safeCall(nutrition, "setCarbohydrates", ANCHOR.carbs)
    safeCall(nutrition, "setLipids", ANCHOR.fats)
    safeCall(nutrition, "setProteins", ANCHOR.proteins)
    return true
end

local function samplePositiveNutritionDelta(nutrition)
    if not nutrition then
        return {
            kcal = 0,
            carbs = 0,
            fats = 0,
            proteins = 0,
        }
    end

    local observedCalories = tonumber(safeCall(nutrition, "getCalories")) or 0
    local observedCarbs = tonumber(safeCall(nutrition, "getCarbohydrates")) or 0
    local observedFats = tonumber(safeCall(nutrition, "getLipids")) or 0
    local observedProteins = tonumber(safeCall(nutrition, "getProteins")) or 0

    return {
        kcal = math.max(0, observedCalories - ANCHOR.calories),
        carbs = math.max(0, observedCarbs - ANCHOR.carbs),
        fats = math.max(0, observedFats - ANCHOR.fats),
        proteins = math.max(0, observedProteins - ANCHOR.proteins),
    }
end

local function seedFuel(nutrition)
    local observedCalories = tonumber(nutrition and safeCall(nutrition, "getCalories") or nil)
    if observedCalories == nil then
        return Metabolism.DEFAULT_FUEL
    end
    return clamp(observedCalories, Metabolism.FUEL_DEPLETED_THRESHOLD, 1500)
end

local function seedProteinAdequacy(weightKg)
    return Metabolism.getDefaultProteinAdequacy(weightKg)
end

local function seedWeight(nutrition)
    local observed = tonumber(nutrition and safeCall(nutrition, "getWeight") or nil)
    if observed ~= nil then
        return clamp(observed, Metabolism.WEIGHT_MIN_KG, Metabolism.WEIGHT_MAX_KG)
    end
    return Metabolism.DEFAULT_WEIGHT_KG
end

local function getModData(playerObj)
    local modData = safeCall(playerObj, "getModData")
    if type(modData) ~= "table" then
        return nil
    end
    return modData
end

local function seedHealthFromFood(bodyDamage)
    local observed = tonumber(bodyDamage and safeCall(bodyDamage, "getHealthFromFood") or nil)
    if observed ~= nil and observed > 0 then
        return observed
    end
    return 0.015
end

local function syncProteinHealing(bodyDamage, state)
    if not bodyDamage or not state then
        return 1.0
    end
    local baseHealthFromFood = tonumber(state.baseHealthFromFood) or seedHealthFromFood(bodyDamage)
    state.baseHealthFromFood = baseHealthFromFood

    local healingMultiplier = Metabolism.getProteinHealingMultiplier(state.proteins, state.weightKg)
    local desired = baseHealthFromFood * healingMultiplier
    local current = tonumber(safeCall(bodyDamage, "getHealthFromFood")) or nil
    if current == nil or math.abs(current - desired) > SYNC_EPSILON then
        safeCall(bodyDamage, "setHealthFromFood", desired)
    end
    return healingMultiplier
end

local function suppressFoodEatenTimer(bodyDamage)
    if not bodyDamage then
        return false
    end

    local current = tonumber(safeCall(bodyDamage, "getHealthFromFoodTimer")) or 0
    if math.abs(current) <= SYNC_EPSILON then
        return false
    end

    safeCall(bodyDamage, "setHealthFromFoodTimer", 0)
    return true
end

function Runtime.ensureStateForPlayer(playerObj)
    local modData = getModData(playerObj)
    if not modData then
        return nil
    end

    local nutrition = getPlayerNutrition(playerObj)
    local bodyDamage = getPlayerBodyDamage(playerObj)
    local rawState = type(modData[STATE_KEY]) == "table" and modData[STATE_KEY] or {}
    local stats = getPlayerStats(playerObj)
    local telemetry = getTelemetryForState(rawState, rawState)
    local state = Metabolism.ensureState(rawState)
    state.baseHealthFromFood = tonumber(state.baseHealthFromFood) or seedHealthFromFood(bodyDamage)
    if state.initialized ~= true then
        local weightKg = seedWeight(nutrition)
        local visibleHunger = clamp(
            getVisibleHungerValue(stats) or 0,
            Metabolism.VISIBLE_HUNGER_MIN,
            Metabolism.VISIBLE_HUNGER_MAX
        )
        state = Metabolism.newState({
            initialized = true,
            fuel = seedFuel(nutrition),
            weightKg = weightKg,
            proteins = seedProteinAdequacy(weightKg),
            visibleHunger = visibleHunger,
            lastWorldHours = getWorldHours(),
            baseHealthFromFood = tonumber(state.baseHealthFromFood) or seedHealthFromFood(bodyDamage),
        })
        telemetry = replaceTelemetryForState(state, {
            lastMetSource = "seed",
            lastTraceReason = "seed",
            lastMealPreHunger = visibleHunger,
            lastMealTargetHunger = visibleHunger,
            lastSyncedHunger = visibleHunger,
        })
        log(string.format(
            "[STATE_INIT] player=%s fuel=%.1f proteins=%.1f weight=%.3f zone=%s",
            tostring(getPlayerLabel(playerObj)),
            tonumber(state.fuel or 0),
            tonumber(state.proteins or 0),
            tonumber(state.weightKg or Metabolism.DEFAULT_WEIGHT_KG),
            tostring(Metabolism.getFuelZone(state.fuel))
        ))
        setNutritionAnchor(nutrition)
    end

    telemetryByState[state] = telemetry
    modData[STATE_KEY] = state
    return state
end

local function getPlayerCacheKey(playerObj)
    if not playerObj then
        return nil
    end
    local onlineId = tonumber(safeCall(playerObj, "getOnlineID"))
    if onlineId ~= nil then
        return "online:" .. tostring(onlineId)
    end
    local playerNum = tonumber(safeCall(playerObj, "getPlayerNum"))
    if playerNum ~= nil then
        return "player:" .. tostring(playerNum)
    end
    return tostring(playerObj)
end

local function getTimedActionMet(playerObj)
    if safeCall(playerObj, "hasTimedActions") ~= true then
        return nil
    end
    local actions = safeCall(playerObj, "getCharacterActions")
    if not actions then
        return nil
    end
    local action = safeCall(actions, "get", 0)
    if not action then
        action = actions[1]
    end
    if not action then
        return nil
    end
    local modifier = tonumber(action.caloriesModifier) or tonumber(safeCall(action, "getCaloriesModifier"))
    if modifier and modifier > 0 then
        return modifier
    end
    return nil
end

local function sampleVanillaMetabolicWorkload(playerObj)
    local thermoregulator = getPlayerThermoregulator(playerObj)
    if not thermoregulator then
        return nil
    end

    local metabolicTarget = tonumber(safeCall(thermoregulator, "getMetabolicTarget") or nil)
    local metabolicReal = tonumber(safeCall(thermoregulator, "getMetabolicRateReal") or nil)
    local averageMet = metabolicTarget
    if averageMet == nil or averageMet <= 0 then
        averageMet = metabolicReal
    end
    if averageMet == nil or averageMet <= 0 then
        return nil
    end

    local peakMet = math.max(
        tonumber(metabolicTarget) or averageMet,
        tonumber(metabolicReal) or averageMet,
        averageMet
    )
    local source = "thermo_target"
    if metabolicTarget == nil or metabolicTarget <= 0 then
        source = "thermo_real"
    elseif metabolicReal ~= nil and metabolicReal > (metabolicTarget + 0.1) then
        source = "thermo_real"
    end

    return Metabolism.normalizeWorkload({
        averageMet = averageMet,
        peakMet = peakMet,
        source = source,
    })
end

local function normalizeScriptedWorkloadOverride(workload, reason)
    if type(workload) ~= "table" then
        return nil
    end

    local normalized = Metabolism.normalizeWorkload({
        averageMet = tonumber(workload.averageMet) or tonumber(workload.met) or Metabolism.MET_REST,
        peakMet = tonumber(workload.peakMet) or tonumber(workload.averageMet) or tonumber(workload.met) or Metabolism.MET_REST,
        observedHours = tonumber(workload.observedHours) or 0,
        heavyHours = tonumber(workload.heavyHours) or 0,
        veryHeavyHours = tonumber(workload.veryHeavyHours) or 0,
        source = tostring(workload.source or "scripted_override"),
        sleepObserved = workload.sleepObserved == true,
    })
    normalized.reason = tostring(reason or workload.reason or "scripted-override")
    normalized.targetName = workload.targetName and tostring(workload.targetName) or nil
    return normalized
end

local function normalizeReportedWorkloadSample(workload)
    if type(workload) ~= "table" then
        return nil
    end

    local averageMet = tonumber(workload.averageMet) or tonumber(workload.met) or nil
    if averageMet == nil then
        return nil
    end

    local peakMet = tonumber(workload.peakMet) or averageMet
    averageMet = clamp(averageMet, Metabolism.MET_SLEEP, 12)
    peakMet = clamp(peakMet, averageMet, 12)

    return Metabolism.normalizeWorkload({
        averageMet = averageMet,
        peakMet = peakMet,
        source = tostring(workload.source or "mp_reported"),
        sleepObserved = workload.sleepObserved == true,
    })
end

local function getFreshReportedWorkload(playerObj)
    if not isDedicatedServerRuntime() then
        return nil
    end

    local key = getPlayerCacheKey(playerObj)
    if not key then
        return nil
    end

    local cache = activityCacheByPlayerKey[key]
    if not cache or type(cache.reportedWorkload) ~= "table" then
        return nil
    end

    local nowHours = getWorldHours()
    local lastSeenHours = tonumber(cache.reportedWorkloadLastSeenHours) or nil
    if nowHours ~= nil and lastSeenHours ~= nil and (nowHours - lastSeenHours) > REPORTED_ACTIVITY_TTL_HOURS then
        return nil
    end

    return cache.reportedWorkload
end

local function sampleLiveWorkload(playerObj)
    if not playerObj then
        return nil
    end

    local scriptedOverride = Runtime.getScriptedWorkloadOverride(playerObj)
    if scriptedOverride then
        return normalizeScriptedWorkloadOverride(scriptedOverride, scriptedOverride.reason)
    end

    local reportedWorkload = getFreshReportedWorkload(playerObj)
    if reportedWorkload then
        return reportedWorkload
    end

    if safeCall(playerObj, "isAsleep") == true then
        return Metabolism.normalizeWorkload({
            averageMet = Metabolism.MET_SLEEP,
            peakMet = Metabolism.MET_SLEEP,
            observedHours = 0,
            heavyHours = 0,
            veryHeavyHours = 0,
            source = "sleep",
            sleepObserved = true,
        })
    end

    local vanillaMetabolic = sampleVanillaMetabolicWorkload(playerObj)
    local timedActionMet = getTimedActionMet(playerObj)
    if timedActionMet and timedActionMet > 0 then
        local vanillaAverage = tonumber(vanillaMetabolic and vanillaMetabolic.averageMet) or 0
        if vanillaAverage <= 0 or timedActionMet > (vanillaAverage + 0.1) then
            return Metabolism.normalizeWorkload({
                averageMet = timedActionMet,
                peakMet = math.max(timedActionMet, tonumber(vanillaMetabolic and vanillaMetabolic.peakMet) or timedActionMet),
                source = "timed_action",
            })
        end
    end

    if vanillaMetabolic then
        return vanillaMetabolic
    end

    if timedActionMet and timedActionMet > 0 then
        return Metabolism.normalizeWorkload({
            averageMet = timedActionMet,
            peakMet = timedActionMet,
            source = "timed_action",
        })
    end

    if safeCall(playerObj, "isAttacking") == true then
        return Metabolism.normalizeWorkload({
            averageMet = 6.0,
            peakMet = 6.0,
            source = "attacking",
        })
    end

    if safeCall(playerObj, "isSprinting") == true then
        return Metabolism.normalizeWorkload({
            averageMet = 9.5,
            peakMet = 9.5,
            source = "movement_sprint",
        })
    end
    if safeCall(playerObj, "isRunning") == true then
        return Metabolism.normalizeWorkload({
            averageMet = 6.9,
            peakMet = 6.9,
            source = "movement_run",
        })
    end
    if safeCall(playerObj, "isSneaking") == true and safeCall(playerObj, "isPlayerMoving") == true then
        return Metabolism.normalizeWorkload({
            averageMet = 2.0,
            peakMet = 2.0,
            source = "movement_sneak",
        })
    end
    if safeCall(playerObj, "isPlayerMoving") == true then
        return Metabolism.normalizeWorkload({
            averageMet = 3.1,
            peakMet = 3.1,
            source = "movement_walk",
        })
    end

    return Metabolism.normalizeWorkload({
        averageMet = Metabolism.MET_REST,
        peakMet = Metabolism.MET_REST,
        source = DEFAULT_WORKLOAD_SOURCE,
    })
end

local function sampleReportedWorkload(playerObj)
    local live = sampleLiveWorkload(playerObj)
    if type(live) ~= "table" then
        return nil
    end

    return Metabolism.normalizeWorkload({
        averageMet = tonumber(live.averageMet) or Metabolism.MET_REST,
        peakMet = tonumber(live.peakMet) or tonumber(live.averageMet) or Metabolism.MET_REST,
        source = tostring(live.source or DEFAULT_WORKLOAD_SOURCE),
        sleepObserved = live.sleepObserved == true,
    })
end

local function getActivityCache(playerObj)
    local key = getPlayerCacheKey(playerObj)
    if not key then
        return nil
    end
    local cache = activityCacheByPlayerKey[key]
    if cache then
        return cache
    end
    cache = {
        key = key,
        weightedMetHours = 0,
        observedHours = 0,
        heavyHours = 0,
        veryHeavyHours = 0,
        peakMet = Metabolism.MET_REST,
        appliedEnduranceDrain = 0,
        sourceHours = {},
        sleepObserved = false,
        lastSampleWorldHours = getWorldHours(),
        lastLive = nil,
        reportedWorkload = nil,
        reportedWorkloadSamples = {},
        reportedWorkloadSeq = nil,
        reportedWorkloadClientWorldHours = nil,
        reportedWorkloadLastSeenHours = nil,
    }
    activityCacheByPlayerKey[key] = cache
    return cache
end

local function pickDominantSource(sourceHours)
    local bestSource = DEFAULT_WORKLOAD_SOURCE
    local bestHours = -1
    for source, hours in pairs(sourceHours or {}) do
        if hours > bestHours then
            bestSource = source
            bestHours = hours
        end
    end
    return bestSource
end

local function buildWorkloadSummaryFromCache(cache)
    if not cache then
        return Metabolism.normalizeWorkload({
            averageMet = Metabolism.MET_REST,
            peakMet = Metabolism.MET_REST,
            source = DEFAULT_WORKLOAD_SOURCE,
        })
    end

    if cache.observedHours > 0 then
        return Metabolism.normalizeWorkload({
            averageMet = cache.weightedMetHours / cache.observedHours,
            peakMet = cache.peakMet,
            observedHours = cache.observedHours,
            heavyHours = cache.heavyHours,
            veryHeavyHours = cache.veryHeavyHours,
            source = pickDominantSource(cache.sourceHours),
            sleepObserved = cache.sleepObserved,
            appliedEnduranceDrain = cache.appliedEnduranceDrain,
        })
    end

    return cache.lastLive or Metabolism.normalizeWorkload({
        averageMet = Metabolism.MET_REST,
        peakMet = Metabolism.MET_REST,
        source = DEFAULT_WORKLOAD_SOURCE,
        appliedEnduranceDrain = cache.appliedEnduranceDrain,
    })
end

local function setVisibleHunger(stats, value)
    if not stats then
        return false
    end
    local hunger = clamp(value or 0, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_CAP)
    if CharacterStat and CharacterStat.HUNGER then
        local ok = safeCall(stats, "set", CharacterStat.HUNGER, hunger)
        if ok ~= nil then
            return true
        end
    end

    safeCall(stats, "setHunger", hunger)
    return true
end

local function syncVisibleWeight(nutrition, state, telemetry)
    if not nutrition or not state then
        return
    end

    telemetry = telemetry or getTelemetryForState(state)
    local weightRate = tonumber(telemetry and telemetry.lastWeightRateKgPerWeek) or 0
    local weightController = tonumber(state.weightController) or 0
    local gaining = weightRate > 0.05
    local losing = weightRate < -0.05
    local gainingLot = gaining and (weightRate > 0.25 or weightController > 0.5)
    local desiredWeight = tonumber(state.weightKg or Metabolism.DEFAULT_WEIGHT_KG)
    local visibleWeight = roundToStep(desiredWeight, 0.1)
    local currentWeight = tonumber(safeCall(nutrition, "getWeight")) or visibleWeight
    local currentGain = safeCall(nutrition, "isIncWeight") == true
    local currentGainLot = safeCall(nutrition, "isIncWeightLot") == true
    local currentLoss = safeCall(nutrition, "isDecWeight") == true

    if math.abs(currentWeight - visibleWeight) > SYNC_EPSILON
        or currentGain ~= gaining
        or currentGainLot ~= gainingLot
        or currentLoss ~= losing then
        safeCall(nutrition, "setWeight", visibleWeight)
        safeCall(nutrition, "setIncWeight", gaining)
        safeCall(nutrition, "setIncWeightLot", gainingLot)
        safeCall(nutrition, "setDecWeight", losing)
        safeCall(nutrition, "applyTraitFromWeight")
    end
end

local function shouldAdoptManualVisibleHunger(playerObj, reason)
    if safeCall(playerObj, "isGodMod") == true then
        return true
    end

    local reasonText = string.lower(tostring(reason or ""))
    if string.find(reasonText, "debug", 1, true)
        or string.find(reasonText, "dev", 1, true)
        or string.find(reasonText, "tool", 1, true)
        or string.find(reasonText, "cheat", 1, true) then
        return true
    end

    if type(DebugSupport.isDebugLaunch) == "function" and DebugSupport.isDebugLaunch() then
        return true
    end

    return false
end

local function importLiveVisibleHungerDrop(state, stats, options)
    if not state or not stats then
        return 0
    end

    local telemetry = getTelemetryForState(state)
    local opts = type(options) == "table" and options or nil
    local allowRise = opts and opts.allowRise == true
    local riseEpsilon = tonumber(opts and opts.riseEpsilon) or MANUAL_VISIBLE_HUNGER_IMPORT_EPSILON
    local liveHunger = clamp(
        getVisibleHungerValue(stats) or state.visibleHunger or 0,
        Metabolism.VISIBLE_HUNGER_MIN,
        Metabolism.VISIBLE_HUNGER_MAX
    )
    local modeledHunger = clamp(
        state.visibleHunger or 0,
        Metabolism.VISIBLE_HUNGER_MIN,
        Metabolism.VISIBLE_HUNGER_MAX
    )
    local lastSyncedHunger = clamp(
        telemetry.lastSyncedHunger or modeledHunger,
        Metabolism.VISIBLE_HUNGER_MIN,
        Metabolism.VISIBLE_HUNGER_MAX
    )
    local importedDrop = lastSyncedHunger - liveHunger
    local importedRise = liveHunger - lastSyncedHunger
    local hasDrop = importedDrop > VISIBLE_HUNGER_IMPORT_EPSILON
    local hasRise = allowRise and importedRise > riseEpsilon
    if not hasDrop and not hasRise then
        return 0
    end

    if hasDrop and (tonumber(telemetry.pendingObservedHungerDrop) or 0) <= VISIBLE_HUNGER_IMPORT_EPSILON
        and telemetry.pendingMealPreVisibleHunger == nil then
        telemetry.pendingMealPreVisibleHunger = lastSyncedHunger
    end

    -- Import live hunger edits before shell sync to avoid snapping vanilla/UI debug writes
    -- back to stale modeled state. The pre-drop reference is retained so a delayed
    -- nutrition deposit can replace the mechanical result instead of stacking on it.
    state.visibleHunger = liveHunger
    telemetry.lastSyncedHunger = liveHunger
    if hasDrop then
        telemetry.pendingObservedHungerDrop = clamp(
            (tonumber(telemetry.pendingObservedHungerDrop) or 0) + importedDrop,
            0,
            1
        )
        telemetry.pendingObservedHungerAge = 0
    end
    return hasDrop and importedDrop or 0
end

local function syncVisibleHunger(playerObj, state, reason)
    if not playerObj or not state then
        return false
    end

    local telemetry = getTelemetryForState(state)
    local stats = getPlayerStats(playerObj)
    if not stats then
        return false
    end

    local allowManualImport = shouldAdoptManualVisibleHunger(playerObj, reason)
    if importLiveVisibleHungerDrop(state, stats, {
        allowRise = allowManualImport,
        riseEpsilon = MANUAL_VISIBLE_HUNGER_IMPORT_EPSILON,
    }) > 0 then
        return false
    end

    local desired = clamp(state.visibleHunger or 0, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
    local current = getVisibleHungerValue(stats) or desired

    if math.abs(current - desired) <= SYNC_EPSILON then
        telemetry.lastSyncedHunger = desired
        return false
    end

    -- Keep the vanilla-facing hunger stat slaved to NMS state. Letting live vanilla
    -- drift accumulate back into state causes threshold chatter and moodle pop-in/out.
    local changed = setVisibleHunger(stats, desired)
    telemetry.lastSyncedHunger = desired
    if changed and type(DebugSupport.noteHungerSyncEvent) == "function" then
        DebugSupport.noteHungerSyncEvent({
            reason = tostring(reason or "visible-hunger-sync"),
            provenance = "hunger-shell-sync",
            pre_visible_hunger = current,
            target_visible_hunger = desired,
            observed_hunger_drop = math.max(0, current - desired),
            hunger_observed = true,
        })
    end
    return changed
end

local function setStatValue(stats, enumKey, setterName, value)
    if not stats then
        return false
    end
    local numeric = tonumber(value)
    if numeric == nil then
        return false
    end

    if CharacterStat and enumKey and CharacterStat[enumKey] then
        local ok = safeCall(stats, "set", CharacterStat[enumKey], numeric)
        if ok ~= nil then
            return true
        end
    end

    if setterName and safeCall(stats, setterName, numeric) ~= nil then
        return true
    end

    return false
end

local function consumeWorkloadSummary(playerObj)
    if Runtime.observePlayerWorkload then
        Runtime.observePlayerWorkload(playerObj, "consume-workload-summary")
    end
    local cache = getActivityCache(playerObj)
    local summary = buildWorkloadSummaryFromCache(cache)
    if cache then
        cache.weightedMetHours = 0
        cache.observedHours = 0
        cache.heavyHours = 0
        cache.veryHeavyHours = 0
        cache.peakMet = summary.averageMet or Metabolism.MET_REST
        cache.appliedEnduranceDrain = 0
        cache.sourceHours = {}
        cache.sleepObserved = false
        cache.lastSampleWorldHours = getWorldHours() or cache.lastSampleWorldHours
    end
    return summary
end

local eachKnownPlayer = CoreUtils.eachKnownPlayer

Runtime.Metabolism = Metabolism
Runtime.MP = MP
Runtime.MPSnapshot = MPSnapshot
Runtime.Settings = Settings
Runtime.STATE_KEY = STATE_KEY
Runtime.DEFAULT_WORKLOAD_SOURCE = DEFAULT_WORKLOAD_SOURCE
Runtime.scriptedWorkloadOverrideByPlayerKey = scriptedWorkloadOverrideByPlayerKey
Runtime.safeCall = safeCall
Runtime.log = log
Runtime.clamp = clamp
Runtime.getModData = getModData
Runtime.getPlayerLabel = getPlayerLabel
Runtime.getPlayerStats = getPlayerStats
Runtime.getCharacterStatValue = getCharacterStatValue
Runtime.getVisibleHungerValue = getVisibleHungerValue
Runtime.normalizeVisibleHungerInput = normalizeVisibleHungerInput
Runtime.resolveTraitEffects = resolveTraitEffects
Runtime.getPlayerNutrition = getPlayerNutrition
Runtime.getPlayerBodyDamage = getPlayerBodyDamage
Runtime.getWorldHours = getWorldHours
Runtime.resolveStatsDecreaseMultiplier = resolveStatsDecreaseMultiplier
Runtime.setNutritionAnchor = setNutritionAnchor
Runtime.samplePositiveNutritionDelta = samplePositiveNutritionDelta
Runtime.hasMeaningfulDeposit = hasMeaningfulDeposit
Runtime.shouldRunAuthoritativeUpdates = shouldRunAuthoritativeUpdates
Runtime.isDedicatedServerRuntime = isDedicatedServerRuntime
Runtime.getPlayerCacheKey = getPlayerCacheKey
Runtime.getTelemetryForState = getTelemetryForState
Runtime.replaceTelemetryForState = replaceTelemetryForState
Runtime.buildStateView = buildStateView
Runtime.recordDepositTelemetry = recordDepositTelemetry
Runtime.recordAdvanceTelemetry = recordAdvanceTelemetry
Runtime.normalizeScriptedWorkloadOverride = normalizeScriptedWorkloadOverride
Runtime.normalizeReportedWorkloadSample = normalizeReportedWorkloadSample
Runtime.getFreshReportedWorkload = getFreshReportedWorkload
Runtime.sampleLiveWorkload = sampleLiveWorkload
Runtime.sampleReportedWorkload = sampleReportedWorkload
Runtime.getActivityCache = getActivityCache
Runtime.REPORTED_WORKLOAD_WINDOW_HOURS = REPORTED_WORKLOAD_WINDOW_HOURS
Runtime.setVisibleHunger = setVisibleHunger
Runtime.syncVisibleHunger = syncVisibleHunger
Runtime.syncVisibleWeight = syncVisibleWeight
Runtime.syncProteinHealing = syncProteinHealing
Runtime.suppressFoodEatenTimer = suppressFoodEatenTimer
Runtime.importLiveVisibleHungerDrop = importLiveVisibleHungerDrop
Runtime.seedHealthFromFood = seedHealthFromFood
Runtime.setStatValue = setStatValue
Runtime.normalizeDeposit = normalizeDeposit
Runtime.consumeWorkloadSummary = consumeWorkloadSummary
Runtime.eachKnownPlayer = eachKnownPlayer

require "runtime/NutritionMakesSense_MetabolismRuntime_Compat"
require "runtime/NutritionMakesSense_MetabolismRuntime_Workload"
require "runtime/NutritionMakesSense_MetabolismRuntime_Sync"
require "runtime/NutritionMakesSense_MetabolismRuntime_Authority"
require "runtime/NutritionMakesSense_MetabolismRuntime_XP"
require "runtime/NutritionMakesSense_MetabolismRuntime_Lifecycle"

return Runtime
