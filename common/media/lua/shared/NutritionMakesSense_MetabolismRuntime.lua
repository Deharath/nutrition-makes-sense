NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_Metabolism"
require "NutritionMakesSense_CoreUtils"

local Runtime = NutritionMakesSense.MetabolismRuntime or {}
NutritionMakesSense.MetabolismRuntime = Runtime

local Metabolism = NutritionMakesSense.Metabolism
local MP = NutritionMakesSense.MP or {}
local CoreUtils = NutritionMakesSense.CoreUtils or {}
local STATE_KEY = tostring(MP.MOD_STATE_KEY or "NutritionMakesSenseState")
local ANCHOR = Metabolism.VANILLA_NUTRITION_ANCHOR
local DEPOSIT_EPSILON = 0.001
local SYNC_EPSILON = 0.0001
local DEFAULT_WORKLOAD_SOURCE = "fallback_rest"
local REPORTED_ACTIVITY_TTL_HOURS = 0.08
local REPORTED_WORKLOAD_WINDOW_HOURS = 4 / 3600
local activityCacheByPlayerKey = {}
local scriptedWorkloadOverrideByPlayerKey = {}

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

local function migrateAuthoritativeWeightFields(rawState, nutrition)
    if type(rawState) ~= "table" or rawState.initialized ~= true then
        return nil
    end

    local migratedWeight = nil
    local source = nil

    if tonumber(rawState.weightKg) == nil then
        local legacyWeight = tonumber(rawState.weight)
        if legacyWeight ~= nil then
            migratedWeight = clamp(legacyWeight, Metabolism.WEIGHT_MIN_KG, Metabolism.WEIGHT_MAX_KG)
            source = "legacy-weight"
        else
            local liveWeight = tonumber(nutrition and safeCall(nutrition, "getWeight") or nil)
            if liveWeight ~= nil then
                migratedWeight = clamp(liveWeight, Metabolism.WEIGHT_MIN_KG, Metabolism.WEIGHT_MAX_KG)
                source = "live-weight"
            end
        end

        if migratedWeight ~= nil then
            rawState.weightKg = migratedWeight
        end
    else
        migratedWeight = clamp(rawState.weightKg, Metabolism.WEIGHT_MIN_KG, Metabolism.WEIGHT_MAX_KG)
    end

    if rawState.lastWeightTrait == nil or rawState.lastWeightTrait == "" then
        local traitWeight = migratedWeight
        if traitWeight == nil then
            local legacyWeight = tonumber(rawState.weight)
            local liveWeight = tonumber(nutrition and safeCall(nutrition, "getWeight") or nil)
            if legacyWeight ~= nil then
                traitWeight = clamp(legacyWeight, Metabolism.WEIGHT_MIN_KG, Metabolism.WEIGHT_MAX_KG)
                rawState.weightKg = rawState.weightKg or traitWeight
                source = source or "legacy-weight"
            elseif liveWeight ~= nil then
                traitWeight = clamp(liveWeight, Metabolism.WEIGHT_MIN_KG, Metabolism.WEIGHT_MAX_KG)
                rawState.weightKg = rawState.weightKg or traitWeight
                source = source or "live-weight"
            end
        end
        if traitWeight ~= nil then
            rawState.lastWeightTrait = Metabolism.getWeightTrait(traitWeight)
        end
    end

    if source == nil then
        return nil
    end

    return {
        source = source,
        weightKg = tonumber(rawState.weightKg),
        trait = tostring(rawState.lastWeightTrait),
    }
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
    state.lastProteinHealingMultiplier = healingMultiplier
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
    local migratedWeight = migrateAuthoritativeWeightFields(rawState, nutrition)
    local state = Metabolism.ensureState(rawState)
    state.baseHealthFromFood = tonumber(state.baseHealthFromFood) or seedHealthFromFood(bodyDamage)
    if migratedWeight then
        log(string.format(
            "[STATE_MIGRATION] player=%s source=%s weight=%.3f trait=%s",
            tostring(getPlayerLabel(playerObj)),
            tostring(migratedWeight.source),
            tonumber(migratedWeight.weightKg or state.weightKg or Metabolism.DEFAULT_WEIGHT_KG),
            tostring(migratedWeight.trait or state.lastWeightTrait or Metabolism.getWeightTrait(state.weightKg))
        ))
    end
    if state.initialized ~= true then
        state.fuel = seedFuel(nutrition)
        state.weightKg = seedWeight(nutrition)
        state.proteins = seedProteinAdequacy(state.weightKg)
        state.weightController = 0
        state.weightBalanceKcal = 0
        state.underfeedingDebtKcal = 0
        state.lastZone = Metabolism.getFuelZone(state.fuel)
        state.lastHungerMultiplier = Metabolism.getFuelHungerMultiplier(state.fuel)
        state.visibleHunger = clamp(getVisibleHungerValue(stats) or 0, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
        state.lastHungerBand = Metabolism.getVisibleHungerBand(state.visibleHunger)
        state.lastFuelPressureFactor = Metabolism.getFuelPressureFactor(state.fuel)
        state.lastGateMultiplier = Metabolism.getHungerGateMultiplier(state.fuel)
        state.lastMetHungerFactor = 1.0
        state.lastWeightTrait = Metabolism.getWeightTrait(state.weightKg)
        state.lastWorldHours = getWorldHours()
        state.initialized = true
        state.lastTraceReason = "seed"
        state.lastDepositKcal = 0
        state.lastBurnKcal = 0
        state.lastBaseHungerGain = 0
        state.lastPassiveHungerGain = 0
        state.lastCorrectionGain = 0
        state.lastExtraEnduranceDrain = 0
        state.lastWeightDeltaKg = 0
        state.lastWeightRateKgPerWeek = 0
        state.lastUnderfeedingDebtKcal = 0
        state.lastDeprivationTarget = Metabolism.getDeprivationTarget(state)
        state.lastWeightBalanceKcal = 0
        state.lastWeightControllerTarget = 0
        state.lastExertionMultiplier = 1.0
        state.lastProteinDeficiency = Metabolism.getProteinDeficiencyProgress(state.proteins, state.weightKg)
        state.lastMetAverage = Metabolism.MET_REST
        state.lastMetPeak = Metabolism.MET_REST
        state.lastEffectiveEnduranceMet = Metabolism.MET_REST
        state.lastWorkTier = Metabolism.WORK_TIER_REST
        state.lastMetSource = "seed"
        state.lastObservedHours = 0
        state.lastHeavyHours = 0
        state.lastVeryHeavyHours = 0
        state.satietyBuffer = 0
        state.lastSatietyQuality = 0
        state.lastSatietyContribution = 0
        state.lastSatietyReturnFactor = 1.0
        state.lastImmediateHungerDrop = 0
        state.lastImmediateHungerMechanical = 0
        state.lastImmediateFillTarget = 0
        state.lastImmediateFillVanilla = 0
        state.lastImmediateFillCorrection = 0
        state.lastProteinHealingMultiplier = Metabolism.getProteinHealingMultiplier(state.proteins, state.weightKg)
        log(string.format(
            "[STATE_INIT] player=%s fuel=%.1f proteins=%.1f weight=%.3f zone=%s",
            tostring(getPlayerLabel(playerObj)),
            tonumber(state.fuel or 0),
            tonumber(state.proteins or 0),
            tonumber(state.weightKg or Metabolism.DEFAULT_WEIGHT_KG),
            tostring(state.lastZone or Metabolism.getFuelZone(state.fuel))
        ))
        setNutritionAnchor(nutrition)
    end

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
        pendingBurnKcal = 0,
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
            pendingBurnKcal = cache.pendingBurnKcal,
            appliedEnduranceDrain = cache.appliedEnduranceDrain,
        })
    end

    return cache.lastLive or Metabolism.normalizeWorkload({
        averageMet = Metabolism.MET_REST,
        peakMet = Metabolism.MET_REST,
        source = DEFAULT_WORKLOAD_SOURCE,
        pendingBurnKcal = cache.pendingBurnKcal,
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

local function removeEndurance(playerObj, stats, delta)
    if not playerObj or delta <= 0 then
        return
    end

    if stats and CharacterStat and CharacterStat.ENDURANCE then
        safeCall(stats, "remove", CharacterStat.ENDURANCE, delta)
        return
    end

    safeCall(playerObj, "exert", delta)
end

local function syncVisibleWeight(nutrition, state)
    if not nutrition or not state then
        return
    end

    local weightRate = tonumber(state.lastWeightRateKgPerWeek) or 0
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
    end
    safeCall(nutrition, "applyTraitFromWeight")
end

local function refreshDerivedState(state, reason)
    state = Metabolism.ensureState(state)
    state.lastZone = Metabolism.getFuelZone(state.fuel)
    state.lastHungerMultiplier = Metabolism.getFuelHungerMultiplier(state.fuel)
    state.lastHungerBand = Metabolism.getVisibleHungerBand(state.visibleHunger)
    state.lastFuelPressureFactor = Metabolism.getFuelPressureFactor(state.fuel)
    state.lastGateMultiplier = Metabolism.getHungerGateMultiplier(state.fuel)
    state.lastWeightTrait = Metabolism.getWeightTrait(state.weightKg)
    state.lastUnderfeedingDebtKcal = tonumber(state.underfeedingDebtKcal) or 0
    state.lastDeprivationTarget = Metabolism.getDeprivationTarget(state)
    state.lastProteinDeficiency = Metabolism.getProteinDeficiencyProgress(state.proteins, state.weightKg)
    state.lastProteinHealingMultiplier = Metabolism.getProteinHealingMultiplier(state.proteins, state.weightKg)
    state.lastTraceReason = tostring(reason or state.lastTraceReason or "debug-set")
    return state
end

local function syncVisibleHunger(playerObj, state, reason)
    if not playerObj or not state then
        return false
    end

    local stats = getPlayerStats(playerObj)
    if not stats then
        return false
    end

    local desired = clamp(state.visibleHunger or 0, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
    local current = getVisibleHungerValue(stats) or desired

    if math.abs(current - desired) <= SYNC_EPSILON then
        return false
    end

    -- Keep the vanilla-facing hunger stat slaved to NMS state. Letting live vanilla
    -- drift accumulate back into state causes threshold chatter and moodle pop-in/out.
    local changed = setVisibleHunger(stats, desired)
    if changed then
        state.lastSyncedHunger = desired
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
        cache.pendingBurnKcal = 0
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
Runtime.setNutritionAnchor = setNutritionAnchor
Runtime.samplePositiveNutritionDelta = samplePositiveNutritionDelta
Runtime.hasMeaningfulDeposit = hasMeaningfulDeposit
Runtime.shouldRunAuthoritativeUpdates = shouldRunAuthoritativeUpdates
Runtime.isDedicatedServerRuntime = isDedicatedServerRuntime
Runtime.getPlayerCacheKey = getPlayerCacheKey
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
Runtime.refreshDerivedState = refreshDerivedState
Runtime.seedHealthFromFood = seedHealthFromFood
Runtime.setStatValue = setStatValue
Runtime.normalizeDeposit = normalizeDeposit
Runtime.removeEndurance = removeEndurance
Runtime.consumeWorkloadSummary = consumeWorkloadSummary
Runtime.eachKnownPlayer = eachKnownPlayer

require "runtime/NutritionMakesSense_MetabolismRuntime_Workload"
require "runtime/NutritionMakesSense_MetabolismRuntime_Sync"
require "runtime/NutritionMakesSense_MetabolismRuntime_Authority"
require "runtime/NutritionMakesSense_MetabolismRuntime_Lifecycle"

return Runtime
