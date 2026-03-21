NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_Metabolism"

local Runtime = NutritionMakesSense.MetabolismRuntime or {}
NutritionMakesSense.MetabolismRuntime = Runtime

local Metabolism = NutritionMakesSense.Metabolism
local MP = NutritionMakesSense.MP or {}
local STATE_KEY = tostring(MP.MOD_STATE_KEY or "NutritionMakesSenseState")
local ANCHOR = Metabolism.VANILLA_NUTRITION_ANCHOR
local DEPOSIT_EPSILON = 0.001
local SYNC_EPSILON = 0.0001
local DEFAULT_WORKLOAD_SOURCE = "fallback_rest"
local activityCacheByPlayerKey = {}
local scriptedWorkloadOverrideByPlayerKey = {}

local function log(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(msg)
    else
        print("[NutritionMakesSense] " .. tostring(msg))
    end
end

local function safeCall(target, methodName, ...)
    if not target then
        return nil
    end

    local method = target[methodName]
    if type(method) ~= "function" then
        return nil
    end

    local ok, result = pcall(method, target, ...)
    if not ok then
        return nil
    end

    return result
end

local function clamp(value, minValue, maxValue)
    return Metabolism.clamp(value, minValue, maxValue)
end

local function roundToStep(value, step)
    local numeric = tonumber(value) or 0
    local unit = tonumber(step) or 1
    if unit <= 0 then
        return numeric
    end
    return math.floor((numeric / unit) + 0.5) * unit
end

local function isClientOnly()
    return type(isClient) == "function" and isClient() and not (type(isServer) == "function" and isServer())
end

local function shouldRunAuthoritativeUpdates()
    return not isClientOnly()
end

local function getWorldHours()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    return tonumber(gameTime and safeCall(gameTime, "getWorldAgeHours") or nil)
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

local function queuePendingNutritionSuppression(state, values, reason, eventId)
    return nil
end

local function suppressPendingNutritionDelta(state, observed, playerLabel)
    return normalizeDeposit(observed)
end

local function getPlayerLabel(playerObj)
    local username = safeCall(playerObj, "getUsername")
    if username and username ~= "" then
        return tostring(username)
    end

    local displayName = safeCall(playerObj, "getDisplayName")
    if displayName and displayName ~= "" then
        return tostring(displayName)
    end

    local onlineId = safeCall(playerObj, "getOnlineID")
    if onlineId ~= nil then
        return tostring(onlineId)
    end

    return tostring(playerObj)
end

local function getPlayerStats(playerObj)
    return safeCall(playerObj, "getStats")
end

local function getCharacterStatValue(stats, enumKey, getterName)
    if not stats then
        return nil
    end

    if CharacterStat and enumKey and CharacterStat[enumKey] then
        local value = safeCall(stats, "get", CharacterStat[enumKey])
        if value ~= nil then
            return tonumber(value)
        end
    end

    if getterName then
        return tonumber(safeCall(stats, getterName))
    end

    return nil
end

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

local function getPlayerNutrition(playerObj)
    return safeCall(playerObj, "getNutrition")
end

local function getPlayerBodyDamage(playerObj)
    return safeCall(playerObj, "getBodyDamage")
end

local function getPlayerThermoregulator(playerObj)
    local bodyDamage = getPlayerBodyDamage(playerObj)
    return bodyDamage and safeCall(bodyDamage, "getThermoregulator") or nil
end

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
    return clamp(observedCalories, Metabolism.FUEL_PENALTY_THRESHOLD, 1500)
end

local function seedProteinReserve(nutrition, getterName)
    local observed = tonumber(nutrition and safeCall(nutrition, getterName) or nil)
    if observed ~= nil and observed > 0 then
        return clamp(observed, 0, Metabolism.PROTEIN_MAX)
    end
    return Metabolism.DEFAULT_PROTEIN
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

    local healingMultiplier = Metabolism.getProteinHealingMultiplier(state.proteins)
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
        state.proteins = seedProteinReserve(nutrition, "getProteins")
        state.weightKg = seedWeight(nutrition)
        state.weightController = 0
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
        state.lastExertionMultiplier = 1.0
        state.lastProteinDeficiency = Metabolism.getProteinDeficiencyProgress(state.proteins)
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
        state.lastProteinHealingMultiplier = Metabolism.getProteinHealingMultiplier(state.proteins)
        state.lastAcuteFuelRecoveryScale = Metabolism.getFuelRecoveryScale(state.fuel)
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

local function sampleLiveWorkload(playerObj)
    if not playerObj then
        return nil
    end

    local scriptedOverride = Runtime.getScriptedWorkloadOverride(playerObj)
    if scriptedOverride then
        return normalizeScriptedWorkloadOverride(scriptedOverride, scriptedOverride.reason)
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

    local thermoregulator = getPlayerThermoregulator(playerObj)
    local metabolicRateReal = tonumber(thermoregulator and safeCall(thermoregulator, "getMetabolicRateReal") or nil)
    if metabolicRateReal and metabolicRateReal > 0 then
        return Metabolism.normalizeWorkload({
            averageMet = metabolicRateReal,
            peakMet = metabolicRateReal,
            source = "thermo_real",
        })
    end

    local metabolicTarget = tonumber(thermoregulator and safeCall(thermoregulator, "getMetabolicTarget") or nil)
    if metabolicTarget and metabolicTarget > 0 then
        return Metabolism.normalizeWorkload({
            averageMet = metabolicTarget,
            peakMet = metabolicTarget,
            source = "thermo_target",
        })
    end

    local timedActionMet = getTimedActionMet(playerObj)
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

local function addHunger(stats, delta)
    if not stats or delta <= 0 then
        return
    end
    if CharacterStat and CharacterStat.HUNGER then
        safeCall(stats, "add", CharacterStat.HUNGER, delta)
        return
    end

    local current = getVisibleHungerValue(stats) or 0
    safeCall(stats, "setHunger", current + delta)
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

local function adjustHunger(stats, delta)
    local applied = tonumber(delta)
    if not stats or applied == nil or math.abs(applied) <= 0.000001 then
        return false
    end

    if CharacterStat and CharacterStat.HUNGER then
        return safeCall(stats, "add", CharacterStat.HUNGER, applied) == true
    end

    local current = getVisibleHungerValue(stats) or 0
    safeCall(stats, "setHunger", current + applied)
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
    state.lastProteinDeficiency = Metabolism.getProteinDeficiencyProgress(state.proteins)
    state.lastProteinHealingMultiplier = Metabolism.getProteinHealingMultiplier(state.proteins)
    state.lastAcuteFuelRecoveryScale = Metabolism.getFuelRecoveryScale(state.fuel)
    state.lastTraceReason = tostring(reason or state.lastTraceReason or "debug-set")
    return state
end

local ADOPT_THRESHOLD = 0.01

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
    local lastSynced = state.lastSyncedHunger

    if lastSynced ~= nil and math.abs(current - lastSynced) > ADOPT_THRESHOLD then
        state.visibleHunger = clamp(current, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
        state.hunger = state.visibleHunger
        state.lastHungerBand = Metabolism.getVisibleHungerBand(state.visibleHunger)
        state.lastSyncedHunger = current
        state.lastTraceReason = tostring(reason or state.lastTraceReason or "visible-hunger-adopt")
        log(string.format(
            "[VISIBLE_HUNGER_ADOPT] player=%s reason=%s live=%.4f lastSynced=%.4f nmsDesired=%.4f",
            tostring(getPlayerLabel(playerObj)),
            tostring(reason or "sync-visible-hunger"),
            current,
            lastSynced,
            desired
        ))
        return true
    end

    if math.abs(current - desired) <= SYNC_EPSILON then
        return false
    end

    local changed = setVisibleHunger(stats, desired)
    if changed then
        state.lastSyncedHunger = desired
        log(string.format(
            "[VISIBLE_HUNGER_SYNC] player=%s reason=%s hunger=%.4f->%.4f",
            tostring(getPlayerLabel(playerObj)),
            tostring(reason or "sync-visible-hunger"),
            current,
            desired
        ))
    end
    return changed
end

local function hasDeposit(deposit)
    return hasMeaningfulDeposit(deposit)
end

function Runtime.getStateKey()
    return STATE_KEY
end

function Runtime.getStateCopy(playerObj)
    local modData = getModData(playerObj)
    local rawState = modData and modData[STATE_KEY] or nil
    if type(rawState) ~= "table" then
        return nil
    end
    return Metabolism.copyState(rawState)
end

function Runtime.buildStateSnapshot(playerObj, reason)
    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return nil
    end

    return {
        version = tostring(MP.SCRIPT_VERSION or "0.1.0"),
        reason = tostring(reason or "snapshot"),
        worldHours = getWorldHours(),
        player = tostring(getPlayerLabel(playerObj)),
        state = Metabolism.copyState(state),
    }
end

function Runtime.syncVisibleIndicators(playerObj, reason)
    if not playerObj then
        return nil
    end

    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return nil
    end

    local nutrition = getPlayerNutrition(playerObj)
    local bodyDamage = getPlayerBodyDamage(playerObj)
    syncVisibleHunger(playerObj, state, reason or "sync-visible-indicators")
    syncVisibleWeight(nutrition, state)
    syncProteinHealing(bodyDamage, state)
    if suppressFoodEatenTimer(bodyDamage) then
        log(string.format(
            "[FOOD_EATEN_SUPPRESS] player=%s reason=%s",
            tostring(getPlayerLabel(playerObj)),
            tostring(reason or "sync-visible-indicators")
        ))
    end
    state.lastTraceReason = tostring(reason or state.lastTraceReason or "sync-visible-indicators")
    return state
end

function Runtime.syncVisibleShell(playerObj, reason)
    if not playerObj then
        return nil
    end

    local state = Runtime.syncVisibleIndicators(playerObj, reason or "sync-visible-shell")
    if not state then
        return nil
    end

    local nutrition = getPlayerNutrition(playerObj)
    setNutritionAnchor(nutrition)
    state.lastTraceReason = tostring(reason or state.lastTraceReason or "sync-visible-shell")
    return state
end

function Runtime.applyVisibleHungerTarget(playerObj, targetHunger, reason)
    if not playerObj then
        return false
    end

    local numeric = tonumber(targetHunger)
    if numeric == nil then
        return false
    end

    local state = Runtime.ensureStateForPlayer(playerObj)
    local stats = getPlayerStats(playerObj)
    if not stats or not state then
        return false
    end

    local before = getVisibleHungerValue(stats) or 0
    local desired = clamp(numeric, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
    state.visibleHunger = desired
    state.hunger = desired
    state.lastSyncedHunger = desired
    local changed = setVisibleHunger(stats, desired)
    if changed and math.abs(before - desired) > 0.000001 then
        log(string.format(
            "[VISIBLE_HUNGER_TARGET] player=%s reason=%s hunger=%.4f->%.4f",
            tostring(getPlayerLabel(playerObj)),
            tostring(reason or "visible-hunger-target"),
            before,
            desired
        ))
    end
    return changed
end

function Runtime.applyImmediateFullnessCorrection(playerObj, correction, reason)
    local stats = getPlayerStats(playerObj)
    local before = getVisibleHungerValue(stats)
    if before == nil then
        return false
    end
    return Runtime.applyVisibleHungerTarget(playerObj, before + (tonumber(correction) or 0), reason)
end

function Runtime.importStateSnapshot(playerObj, snapshot, reason)
    if not playerObj or type(snapshot) ~= "table" then
        return nil
    end

    local modData = getModData(playerObj)
    if not modData then
        return nil
    end

    local rawState = type(snapshot.state) == "table" and snapshot.state or snapshot
    local state = Metabolism.ensureState(Metabolism.copyState(rawState))
    state.initialized = true
    state.lastTraceReason = tostring(reason or snapshot.reason or "mp-sync")
    if snapshot.worldHours ~= nil then
        state.lastWorldHours = tonumber(snapshot.worldHours) or state.lastWorldHours
    end

    modData[STATE_KEY] = state

    Runtime.syncVisibleShell(playerObj, reason or snapshot.reason or "mp-sync")
    return state
end

function Runtime.queueNutritionSuppression(playerObj, values, reason, eventId)
    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return nil
    end
    return queuePendingNutritionSuppression(state, values, reason, eventId)
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
        proteins = Metabolism.DEFAULT_PROTEIN,
        weightKg = Metabolism.DEFAULT_WEIGHT_KG,
        weightController = 0,
        satietyBuffer = 0.8,
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
        satietyBuffer = 0,
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
        lastExertionMultiplier = 1.0,
        lastTraceReason = tostring(reason or "debug-reset"),
        baseHealthFromFood = tonumber(previous and previous.baseHealthFromFood) or seedHealthFromFood(bodyDamage),
        pendingNutritionSuppressions = nil,
        recentMpEventIds = {},
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

    log(string.format(
        "[MP_AUTHORITY] player=%s reason=%s kcal=%.1f carbs=%.1f fats=%.1f proteins=%.1f fuel=%.1f zone=%s hunger_drop=%.4f",
        tostring(getPlayerLabel(playerObj)),
        tostring(reason or "mp-authority"),
        tonumber(report.kcal or 0),
        tonumber(report.carbs or 0),
        tonumber(report.fats or 0),
        tonumber(report.proteins or 0),
        tonumber(report.fuelAfter or state.fuel),
        tostring(report.zoneAfter or state.lastZone),
        tonumber(report.immediateHungerDrop or report.immediateFillTarget or 0)
    ))

    return report, state
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

    local state = Runtime.ensureStateForPlayer(playerObj)

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

local function consumeWorkloadSummary(playerObj)
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
    if hasMeaningfulDeposit(observedDelta) then
        log(string.format(
            "[NUTRITION_DRIFT] player=%s kcal=%.1f carbs=%.1f fats=%.1f proteins=%.1f",
            tostring(playerLabel),
            tonumber(observedDelta.kcal or 0),
            tonumber(observedDelta.carbs or 0),
            tonumber(observedDelta.fats or 0),
            tonumber(observedDelta.proteins or 0)
        ))
    end
    local zoneBefore = Metabolism.getFuelZone(state.fuel)
    state.lastDepositKcal = 0

    local nowHours = getWorldHours()
    local elapsedHours = 0
    if nowHours and state.lastWorldHours then
        elapsedHours = math.max(0, nowHours - state.lastWorldHours)
        elapsedHours = math.min(elapsedHours, 6)
    end
    state.lastWorldHours = nowHours or state.lastWorldHours

    local workload = consumeWorkloadSummary(playerObj)
    local advanceReport = Metabolism.advanceState(state, elapsedHours, workload, { reason = reason or workload.workTier or "workload" })
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

    if tonumber(state.lastProteinDeficiency or 0) > 0
        or tonumber(state.lastAcuteFuelRecoveryScale or 1.0) < 0.999 then
        log(string.format(
            "[NUTRITION_STATE] player=%s proteinDef=%.3f proteinHealing=%.3f fuelRecovery=%.3f deprivation=%.3f",
            tostring(playerLabel),
            tonumber(state.lastProteinDeficiency or 0),
            tonumber(state.lastProteinHealingMultiplier or 1.0),
            tonumber(state.lastAcuteFuelRecoveryScale or 1.0),
            tonumber(state.deprivation or 0)
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

local function eachKnownPlayer(callback)
    if type(isServer) == "function" and isServer() and type(getOnlinePlayers) == "function" then
        local players = getOnlinePlayers()
        if not players then
            return
        end
        for i = 0, players:size() - 1 do
            callback(players:get(i))
        end
        return
    end

    if type(getNumActivePlayers) == "function" and type(getSpecificPlayer) == "function" then
        for playerIndex = 0, getNumActivePlayers() - 1 do
            local playerObj = getSpecificPlayer(playerIndex)
            if playerObj then
                callback(playerObj)
            end
        end
        return
    end

    if type(getPlayer) == "function" then
        local playerObj = getPlayer()
        if playerObj then
            callback(playerObj)
        end
    end
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

if Events then
    if Events.OnLoad and type(Events.OnLoad.Add) == "function" then
        Events.OnLoad.Add(function()
            Runtime.bootstrapKnownPlayers("on-load")
        end)
    end

    if Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
        Events.OnGameStart.Add(function()
            Runtime.bootstrapKnownPlayers("game-start")
        end)
    end

    if Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
        Events.OnCreatePlayer.Add(function(_, playerObj)
            Runtime.bootstrapPlayer(playerObj, "create-player")
        end)
    end

    if Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
        Events.OnPlayerUpdate.Add(function(playerObj)
            Runtime.observePlayerWorkload(playerObj, "player-update")
        end)
    end

    if Events.EveryOneMinute and type(Events.EveryOneMinute.Add) == "function" then
        Events.EveryOneMinute.Add(function()
            Runtime.refreshKnownPlayers("every-one-minute")
        end)
    end
end

return Runtime
