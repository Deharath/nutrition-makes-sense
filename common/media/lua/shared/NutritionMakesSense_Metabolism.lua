NutritionMakesSense = NutritionMakesSense or {}

local Metabolism = NutritionMakesSense.Metabolism or {}
NutritionMakesSense.Metabolism = Metabolism

Metabolism.STATE_VERSION = 7

Metabolism.WORK_TIER_SLEEP = "sleep"
Metabolism.WORK_TIER_REST = "rest"
Metabolism.WORK_TIER_LIGHT = "light"
Metabolism.WORK_TIER_MODERATE = "moderate"
Metabolism.WORK_TIER_HEAVY = "heavy"
Metabolism.WORK_TIER_VERY_HEAVY = "very_heavy"

Metabolism.MET_REST = 1.0
Metabolism.MET_SLEEP = 0.8
Metabolism.MET_HEAVY_THRESHOLD = 4.5
Metabolism.MET_VERY_HEAVY_THRESHOLD = 7.0
Metabolism.MET_MAX = 12.0

Metabolism.ACTIVITY_SLEEP = "sleep"
Metabolism.ACTIVITY_IDLE = "idle"
Metabolism.ACTIVITY_WALK = "walk"
Metabolism.ACTIVITY_STRENUOUS = "strenuous"

Metabolism.FUEL_MIN = 0
Metabolism.FUEL_MAX = 2000
Metabolism.FUEL_STORAGE_THRESHOLD = 1700
Metabolism.FUEL_HIGH_THRESHOLD = 1500
Metabolism.FUEL_LOW_THRESHOLD = 550
Metabolism.FUEL_PENALTY_THRESHOLD = 200
Metabolism.DEFAULT_FUEL = 1000

Metabolism.DEPRIVATION_MIN = 0
Metabolism.DEPRIVATION_MAX = 1.0
Metabolism.DEPRIVATION_FUEL_THRESHOLD = 200
Metabolism.DEPRIVATION_RISE_HOURS = 12
Metabolism.DEPRIVATION_RECOVERY_HOURS = 10
Metabolism.DEPRIVATION_PENALTY_ONSET = 0.10
Metabolism.DEPRIVATION_ENDURANCE_MAX = 0.35
Metabolism.DEPRIVATION_FATIGUE_MAX = 0.25
Metabolism.DEPRIVATION_MELEE_MAX = 0.15

Metabolism.VANILLA_NUTRITION_ANCHOR = {
    calories = 0,
    carbs = 0,
    fats = 0,
    proteins = 0,
}

Metabolism.PROTEIN_MAX = 350
Metabolism.DEFAULT_PROTEIN = 245
Metabolism.PROTEIN_DEFICIENCY_START_RATIO = 0.10
Metabolism.PROTEIN_HEALING_MAX_PENALTY = 0.12

Metabolism.DEFAULT_WEIGHT_KG = 80
Metabolism.WEIGHT_MIN_KG = 35
Metabolism.WEIGHT_MAX_KG = 140
Metabolism.WEIGHT_CONTROLLER_RESPONSE_HOURS = 24
Metabolism.WEIGHT_MAX_RATE_KG_PER_HOUR = 1 / (24 * 7)
Metabolism.WEIGHT_BURN_REFERENCE_KG = 80
Metabolism.WEIGHT_BURN_FACTOR_PER_KG = 0.0025
Metabolism.WEIGHT_BURN_FACTOR_MIN = 0.90
Metabolism.WEIGHT_BURN_FACTOR_MAX = 1.10

Metabolism.SLEEP_FUEL_BURN_PER_HOUR = 35
Metabolism.SLEEP_VISIBLE_HUNGER_PER_HOUR = 0.004
Metabolism.SLEEP_PROTEIN_BURN_PER_HOUR = 0.8
Metabolism.WAKE_PROTEIN_BURN_PER_HOUR = 2.0
Metabolism.FUEL_ACUTE_ENDURANCE_THRESHOLD = 450
Metabolism.FUEL_ACUTE_ENDURANCE_MAX_PENALTY = 0.15

Metabolism.SATIETY_BUFFER_MAX = 1.5
Metabolism.SATIETY_BUFFER_DECAY_PER_HOUR = 0.08
Metabolism.SATIETY_RETURN_FACTOR_MIN = 0.55
Metabolism.SATIETY_FUEL_PIERCE_FLOOR = 0.40
Metabolism.IMMEDIATE_HUNGER_MAX_DELTA = 0.30
Metabolism.IMMEDIATE_FULLNESS_MAX_DELTA = Metabolism.IMMEDIATE_HUNGER_MAX_DELTA
Metabolism.VISIBLE_HUNGER_MIN = 0.0
Metabolism.VISIBLE_HUNGER_MAX = 1.0
Metabolism.HUNGER_THRESHOLD_PECKISH = 0.16
Metabolism.HUNGER_THRESHOLD_HUNGRY = 0.25
Metabolism.HUNGER_THRESHOLD_VERY_HUNGRY = 0.45
Metabolism.HUNGER_THRESHOLD_STARVING = 0.70
Metabolism.BASE_WAKE_HUNGER_PER_HOUR = 0.028
Metabolism.STARVATION_DECEL_FLOOR = 0.02
Metabolism.VISIBLE_HUNGER_CAP = 0.699
Metabolism.SLEEP_HUNGER_FACTOR = 0.33
Metabolism.HUNGER_MET_FACTOR_PER_MET = 0.05
Metabolism.HUNGER_MET_FACTOR_MAX = 1.30

local function clamp(value, minValue, maxValue)
    local numeric = tonumber(value) or minValue
    if numeric < minValue then
        return minValue
    end
    if numeric > maxValue then
        return maxValue
    end
    return numeric
end

local function shallowCopy(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

local function lerp(a, b, t)
    return a + ((b - a) * clamp(t, 0, 1))
end

local function roundToStep(value, step)
    local numeric = tonumber(value) or 0
    local unit = tonumber(step) or 1
    if unit <= 0 then
        return numeric
    end
    return math.floor((numeric / unit) + 0.5) * unit
end

local function approach(current, target, fraction)
    return current + ((target - current) * clamp(fraction, 0, 1))
end

function Metabolism.clamp(value, minValue, maxValue)
    return clamp(value, minValue, maxValue)
end

local function normalizedMet(value, fallback)
    local numeric = tonumber(value)
    if numeric == nil then
        return fallback or Metabolism.MET_REST
    end
    return clamp(numeric, 0, Metabolism.MET_MAX)
end

function Metabolism.normalizeWorkTier(workTier)
    if workTier == Metabolism.WORK_TIER_SLEEP
        or workTier == Metabolism.WORK_TIER_REST
        or workTier == Metabolism.WORK_TIER_LIGHT
        or workTier == Metabolism.WORK_TIER_MODERATE
        or workTier == Metabolism.WORK_TIER_HEAVY
        or workTier == Metabolism.WORK_TIER_VERY_HEAVY then
        return workTier
    end
    return Metabolism.WORK_TIER_REST
end

function Metabolism.classifyWorkTier(met, sleepObserved)
    if sleepObserved == true then
        return Metabolism.WORK_TIER_SLEEP
    end

    local normalized = normalizedMet(met, Metabolism.MET_REST)
    if normalized <= 1.3 then
        return Metabolism.WORK_TIER_REST
    end
    if normalized < 2.5 then
        return Metabolism.WORK_TIER_LIGHT
    end
    if normalized < Metabolism.MET_HEAVY_THRESHOLD then
        return Metabolism.WORK_TIER_MODERATE
    end
    if normalized < Metabolism.MET_VERY_HEAVY_THRESHOLD then
        return Metabolism.WORK_TIER_HEAVY
    end
    return Metabolism.WORK_TIER_VERY_HEAVY
end

function Metabolism.normalizeWorkload(workload)
    if type(workload) == "string" then
        if workload == Metabolism.ACTIVITY_SLEEP then
            workload = {
                averageMet = Metabolism.MET_SLEEP,
                peakMet = Metabolism.MET_SLEEP,
                source = "legacy_sleep",
                sleepObserved = true,
            }
        elseif workload == Metabolism.ACTIVITY_WALK then
            workload = {
                averageMet = 3.1,
                peakMet = 3.1,
                source = "legacy_walk",
            }
        elseif workload == Metabolism.ACTIVITY_STRENUOUS then
            workload = {
                averageMet = 6.9,
                peakMet = 6.9,
                heavyHours = 1,
                source = "legacy_strenuous",
            }
        else
            workload = {
                averageMet = Metabolism.MET_REST,
                peakMet = Metabolism.MET_REST,
                source = "legacy_idle",
            }
        end
    end

    local summary = type(workload) == "table" and workload or {}
    local sleepObserved = summary.sleepObserved == true
    local averageMet = normalizedMet(summary.averageMet or summary.avgMet, sleepObserved and Metabolism.MET_SLEEP or Metabolism.MET_REST)
    local peakMet = normalizedMet(summary.peakMet, averageMet)
    local observedHours = math.max(0, tonumber(summary.observedHours) or 0)
    local heavyHours = math.max(0, tonumber(summary.heavyHours) or 0)
    local veryHeavyHours = math.max(0, tonumber(summary.veryHeavyHours) or 0)
    local source = tostring(summary.source or (sleepObserved and "sleep" or "fallback"))
    local effectiveEnduranceMet = averageMet
    local pendingBurnKcal = tonumber(summary.pendingBurnKcal)
    if pendingBurnKcal ~= nil and pendingBurnKcal <= 0 then
        pendingBurnKcal = nil
    end
    local appliedEnduranceDrain = tonumber(summary.appliedEnduranceDrain)

    if sleepObserved then
        averageMet = Metabolism.MET_SLEEP
        peakMet = Metabolism.MET_SLEEP
        effectiveEnduranceMet = Metabolism.MET_SLEEP
    else
        local exposureRatio = clamp(heavyHours / math.max(observedHours, 0.000001), 0, 1)
        effectiveEnduranceMet = averageMet + math.max(0, peakMet - averageMet) * exposureRatio
    end

    return {
        averageMet = averageMet,
        peakMet = peakMet,
        observedHours = observedHours,
        heavyHours = heavyHours,
        veryHeavyHours = veryHeavyHours,
        source = source,
        sleepObserved = sleepObserved,
        effectiveEnduranceMet = effectiveEnduranceMet,
        workTier = Metabolism.classifyWorkTier(averageMet, sleepObserved),
        pendingBurnKcal = pendingBurnKcal,
        appliedEnduranceDrain = appliedEnduranceDrain,
    }
end

function Metabolism.copyState(state)
    return Metabolism.ensureState(shallowCopy(state or {}))
end

function Metabolism.getFuelZone(fuel)
    local value = clamp(fuel, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
    if value > Metabolism.FUEL_STORAGE_THRESHOLD then
        return "Storage"
    end
    if value > Metabolism.FUEL_HIGH_THRESHOLD then
        return "High"
    end
    if value >= Metabolism.FUEL_LOW_THRESHOLD then
        return "Comfortable"
    end
    if value >= Metabolism.FUEL_PENALTY_THRESHOLD then
        return "Low"
    end
    return "Penalty"
end

function Metabolism.getWeightFuelBurnFactor(weightKg)
    local weight = clamp(weightKg or Metabolism.DEFAULT_WEIGHT_KG, Metabolism.WEIGHT_MIN_KG, Metabolism.WEIGHT_MAX_KG)
    local delta = weight - Metabolism.WEIGHT_BURN_REFERENCE_KG
    local factor = 1.0 + (delta * Metabolism.WEIGHT_BURN_FACTOR_PER_KG)
    return clamp(factor, Metabolism.WEIGHT_BURN_FACTOR_MIN, Metabolism.WEIGHT_BURN_FACTOR_MAX)
end

function Metabolism.getFuelBurnPerHourFromMet(workload, weightKg)
    local summary = Metabolism.normalizeWorkload(workload)
    local weightFactor = Metabolism.getWeightFuelBurnFactor(weightKg)
    if summary.sleepObserved then
        return Metabolism.SLEEP_FUEL_BURN_PER_HOUR * weightFactor
    end
    return (75 + (48 * math.max(0, summary.averageMet - Metabolism.MET_REST))) * weightFactor
end

function Metabolism.getVisibleHungerPerHourFromMet(workload)
    local summary = Metabolism.normalizeWorkload(workload)
    if summary.sleepObserved then
        return Metabolism.BASE_WAKE_HUNGER_PER_HOUR * Metabolism.SLEEP_HUNGER_FACTOR
    end
    return Metabolism.BASE_WAKE_HUNGER_PER_HOUR
end

function Metabolism.getProteinBurnPerHour(workload)
    local summary = Metabolism.normalizeWorkload(workload)
    if summary.sleepObserved then
        return Metabolism.SLEEP_PROTEIN_BURN_PER_HOUR
    end
    return Metabolism.WAKE_PROTEIN_BURN_PER_HOUR
end

function Metabolism.getEnduranceDrainPerHourFromMet(workload)
    local summary = Metabolism.normalizeWorkload(workload)
    if summary.sleepObserved then
        return 0
    end
    return math.max(0, summary.effectiveEnduranceMet - 2.5) * 0.04
end

function Metabolism.getInstantEnduranceDrainPerHourFromMet(workload)
    return Metabolism.getEnduranceDrainPerHourFromMet(workload)
end

Metabolism.DEPRIVATION_REGEN_SCALE_MIN = 0.55
Metabolism.DEPRIVATION_ACTIVITY_DRAIN_MAX = 0.012
Metabolism.DEPRIVATION_ENDURANCE_ONSET = 0.15
function Metabolism.getDeprivationRegenScale(deprivation)
    local d = tonumber(deprivation) or 0
    if d <= Metabolism.DEPRIVATION_ENDURANCE_ONSET then return 1.0 end
    local progress = clamp((d - Metabolism.DEPRIVATION_ENDURANCE_ONSET) / (1.0 - Metabolism.DEPRIVATION_ENDURANCE_ONSET), 0, 1)
    return lerp(1.0, Metabolism.DEPRIVATION_REGEN_SCALE_MIN, progress)
end

function Metabolism.getDeprivationActivityDrain(deprivation, averageMet)
    local d = tonumber(deprivation) or 0
    if d <= Metabolism.DEPRIVATION_ENDURANCE_ONSET then return 0 end
    local met = tonumber(averageMet) or Metabolism.MET_REST
    local activityFactor = clamp((met - Metabolism.MET_REST) / (6.0 - Metabolism.MET_REST), 0, 1)
    local progress = clamp((d - Metabolism.DEPRIVATION_ENDURANCE_ONSET) / (1.0 - Metabolism.DEPRIVATION_ENDURANCE_ONSET), 0, 1)
    return Metabolism.DEPRIVATION_ACTIVITY_DRAIN_MAX * progress * activityFactor
end

function Metabolism.getProteinDeficiencyProgress(proteins)
    local deficiencyStart = Metabolism.PROTEIN_MAX * Metabolism.PROTEIN_DEFICIENCY_START_RATIO
    local available = clamp(proteins or 0, 0, Metabolism.PROTEIN_MAX)
    if available >= deficiencyStart then
        return 0
    end
    if deficiencyStart <= 0 then
        return 1
    end
    return clamp((deficiencyStart - available) / deficiencyStart, 0, 1)
end

function Metabolism.getMacroDeficiencyProgress(macroName, reserve)
    if macroName ~= "proteins" then
        return 0
    end
    return Metabolism.getProteinDeficiencyProgress(reserve)
end

function Metabolism.getFuelRecoveryScale(fuel)
    local value = clamp(fuel, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
    if value >= Metabolism.FUEL_ACUTE_ENDURANCE_THRESHOLD then
        return 1.0
    end
    local progress = 1.0 - (value / Metabolism.FUEL_ACUTE_ENDURANCE_THRESHOLD)
    return lerp(1.0, 1.0 - Metabolism.FUEL_ACUTE_ENDURANCE_MAX_PENALTY, progress)
end

function Metabolism.getProteinHealingMultiplier(proteins)
    local deficiency = Metabolism.getProteinDeficiencyProgress(proteins)
    return lerp(1.0, 1.0 - Metabolism.PROTEIN_HEALING_MAX_PENALTY, deficiency)
end

function Metabolism.getMacroEffectSnapshot(state, workload)
    state = Metabolism.ensureState(state)
    return {
        carbDeficiency = 0,
        fatDeficiency = 0,
        proteinDeficiency = Metabolism.getProteinDeficiencyProgress(state.proteins),
        carbEnduranceMultiplier = 1.0,
        fatWeightLossMultiplier = 1.0,
        proteinHealingMultiplier = Metabolism.getProteinHealingMultiplier(state.proteins),
    }
end

local function computeMacroCalories(values)
    local carbs = math.max(0, tonumber(values and values.carbs) or 0)
    local fats = math.max(0, tonumber(values and values.fats) or 0)
    local proteins = math.max(0, tonumber(values and values.proteins) or 0)
    local carbKcal = carbs * 4
    local fatKcal = fats * 9
    local proteinKcal = proteins * 4
    return carbKcal, fatKcal, proteinKcal, carbKcal + fatKcal + proteinKcal
end

function Metabolism.getSatietyQuality(values)
    local kcal = math.max(0, tonumber(values and values.kcal) or 0)
    local _, fatKcal, proteinKcal, totalMacroKcal = computeMacroCalories(values)
    if kcal <= 0 and totalMacroKcal <= 0 then
        return 0
    end

    local proteinShare = 0
    local fatShare = 0
    if totalMacroKcal > 0 then
        proteinShare = proteinKcal / totalMacroKcal
        fatShare = fatKcal / totalMacroKcal
    end

    local lowCalPenalty = lerp(0.20, 0.00, clamp(kcal / 80, 0, 1))
    return clamp(0.55 + (proteinShare * 0.30) + (fatShare * 0.15) - lowCalPenalty, 0, 1)
end

function Metabolism.getSatietyContribution(values, fraction)
    local applied = Metabolism.scaleFoodValues(values, fraction or 1)
    local kcal = math.max(0, tonumber(applied.kcal) or 0)
    if kcal <= 0 then
        return 0
    end

    local qualityFactor = Metabolism.getSatietyQuality(applied)
    return clamp((kcal / 100) * qualityFactor * 0.12, 0, Metabolism.SATIETY_BUFFER_MAX)
end

function Metabolism.getSatietyDescriptorFromValues(values)
    local contribution = Metabolism.getSatietyContribution(values, 1)
    if contribution >= 0.24 then
        return "Very high"
    end
    if contribution >= 0.18 then
        return "High"
    end
    if contribution >= 0.10 then
        return "Moderate"
    end
    if contribution >= 0.045 then
        return "Light"
    end
    if contribution > 0 then
        return "Minimal"
    end
    return nil
end

function Metabolism.getSatietyReturnFactor(satietyBuffer)
    return lerp(1.0, Metabolism.SATIETY_RETURN_FACTOR_MIN, clamp(satietyBuffer or 0, 0, 1))
end

function Metabolism.getVisibleHungerBand(hunger)
    local value = clamp(hunger or 0, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
    if value < Metabolism.HUNGER_THRESHOLD_PECKISH then
        return "comfortable"
    end
    if value < Metabolism.HUNGER_THRESHOLD_HUNGRY then
        return "peckish"
    end
    if value < Metabolism.HUNGER_THRESHOLD_VERY_HUNGRY then
        return "hungry"
    end
    if value < Metabolism.HUNGER_THRESHOLD_STARVING then
        return "very_hungry"
    end
    return "starving"
end

function Metabolism.getFuelPressureFactor(fuel)
    local value = clamp(fuel, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
    if value >= Metabolism.FUEL_LOW_THRESHOLD then
        return 1.0
    end
    if value >= Metabolism.FUEL_PENALTY_THRESHOLD then
        local lowProgress = (Metabolism.FUEL_LOW_THRESHOLD - value) / (Metabolism.FUEL_LOW_THRESHOLD - Metabolism.FUEL_PENALTY_THRESHOLD)
        local curved = 1.0 - ((1.0 - lowProgress) * (1.0 - lowProgress) * (1.0 - lowProgress))
        return lerp(1.0, 3.2, curved)
    end
    local penaltyProgress = 1.0 - (value / Metabolism.FUEL_PENALTY_THRESHOLD)
    return lerp(3.2, 4.2, penaltyProgress)
end

function Metabolism.getHungerGateMultiplier(fuel)
    local value = clamp(fuel, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
    if value >= Metabolism.FUEL_LOW_THRESHOLD then
        return 0.8
    end
    if value >= Metabolism.FUEL_PENALTY_THRESHOLD then
        local lowProgress = (Metabolism.FUEL_LOW_THRESHOLD - value) / (Metabolism.FUEL_LOW_THRESHOLD - Metabolism.FUEL_PENALTY_THRESHOLD)
        return lerp(0.8, 1.5, lowProgress)
    end
    local penaltyProgress = 1.0 - (value / Metabolism.FUEL_PENALTY_THRESHOLD)
    return lerp(1.5, 2.2, penaltyProgress)
end

function Metabolism.getMetHungerFactor(workload)
    local summary = Metabolism.normalizeWorkload(workload)
    if summary.sleepObserved then
        return 1.0
    end
    return clamp(
        1.0 + (math.max(0, summary.averageMet - Metabolism.MET_REST) * Metabolism.HUNGER_MET_FACTOR_PER_MET),
        1.0,
        Metabolism.HUNGER_MET_FACTOR_MAX
    )
end

function Metabolism.getSatietyFuelScale(fuel)
    local value = clamp(fuel, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
    if value >= Metabolism.FUEL_LOW_THRESHOLD then
        return 1.0
    end
    return lerp(
        Metabolism.SATIETY_FUEL_PIERCE_FLOOR,
        1.0,
        value / Metabolism.FUEL_LOW_THRESHOLD
    )
end

function Metabolism.getSatietyBandFactor(satietyBuffer, visibleHunger, fuel)
    local hunger = clamp(visibleHunger or 0, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
    local satietyFuelScale = Metabolism.getSatietyFuelScale(fuel)
    local effectiveSatietyBuffer = clamp((satietyBuffer or 0) * satietyFuelScale, 0, Metabolism.SATIETY_BUFFER_MAX)
    local satietyReturnFactor = Metabolism.getSatietyReturnFactor(effectiveSatietyBuffer)
    if hunger < Metabolism.HUNGER_THRESHOLD_PECKISH then
        return satietyReturnFactor
    end
    if hunger >= Metabolism.HUNGER_THRESHOLD_VERY_HUNGRY then
        return 1.0
    end

    local fade = 1.0 - ((hunger - Metabolism.HUNGER_THRESHOLD_PECKISH) / (Metabolism.HUNGER_THRESHOLD_VERY_HUNGRY - Metabolism.HUNGER_THRESHOLD_PECKISH))
    return lerp(1.0, satietyReturnFactor, fade)
end

function Metabolism.getStarvationDecelFactor(hunger)
    if hunger <= Metabolism.HUNGER_THRESHOLD_VERY_HUNGRY then
        return 1.0
    end
    if hunger >= Metabolism.HUNGER_THRESHOLD_STARVING then
        return Metabolism.STARVATION_DECEL_FLOOR
    end
    local remaining = Metabolism.HUNGER_THRESHOLD_STARVING - hunger
    local range = Metabolism.HUNGER_THRESHOLD_STARVING - Metabolism.HUNGER_THRESHOLD_VERY_HUNGRY
    local ratio = remaining / range
    return math.max(Metabolism.STARVATION_DECEL_FLOOR, ratio * ratio)
end

function Metabolism.getPassiveVisibleHungerRatePerHour(state, workload)
    state = Metabolism.ensureState(state)
    local summary = Metabolism.normalizeWorkload(workload)
    local hunger = clamp(state.visibleHunger or 0, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
    local fuelPressureFactor = Metabolism.getFuelPressureFactor(state.fuel)
    local gateMultiplier = Metabolism.getHungerGateMultiplier(state.fuel)
    local metHungerFactor = Metabolism.getMetHungerFactor(summary)
    local satietyBandFactor = Metabolism.getSatietyBandFactor(state.satietyBuffer, hunger, state.fuel)
    local baseRate = summary.sleepObserved
        and (Metabolism.BASE_WAKE_HUNGER_PER_HOUR * Metabolism.SLEEP_HUNGER_FACTOR)
        or (Metabolism.BASE_WAKE_HUNGER_PER_HOUR * metHungerFactor)

    local bandMultiplier = 1.0
    if hunger < Metabolism.HUNGER_THRESHOLD_PECKISH then
        bandMultiplier = 1.0 * fuelPressureFactor
    elseif hunger < Metabolism.HUNGER_THRESHOLD_HUNGRY then
        bandMultiplier = 1.1 * fuelPressureFactor
    elseif hunger < Metabolism.HUNGER_THRESHOLD_VERY_HUNGRY then
        bandMultiplier = 1.3 * fuelPressureFactor
    else
        bandMultiplier = gateMultiplier
    end

    local starvationDecel = Metabolism.getStarvationDecelFactor(hunger)

    return {
        ratePerHour = baseRate * bandMultiplier * satietyBandFactor * starvationDecel,
        baseRatePerHour = baseRate,
        band = Metabolism.getVisibleHungerBand(hunger),
        bandMultiplier = bandMultiplier,
        satietyBandFactor = satietyBandFactor,
        fuelPressureFactor = fuelPressureFactor,
        gateMultiplier = gateMultiplier,
        starvationDecel = starvationDecel,
        metHungerFactor = metHungerFactor,
        sleepObserved = summary.sleepObserved,
    }
end

local function computeImmediateHungerSnapshot(values, fraction)
    local applied = Metabolism.scaleFoodValues(values, fraction or 1)
    local kcal = math.max(0, tonumber(applied.kcal) or 0)
    local _, fatKcal, proteinKcal, totalMacroKcal = computeMacroCalories(applied)
    local proteinShare = 0
    local fatShare = 0
    if totalMacroKcal > 0 then
        proteinShare = proteinKcal / totalMacroKcal
        fatShare = fatKcal / totalMacroKcal
    end

    local kcalFactor = kcal > 0 and clamp(math.sqrt(kcal / 400), 0, 1) or 0
    local lowCalPenalty = lerp(0.04, 0.00, clamp(kcal / 60, 0, 1))
    local targetHungerDrop = clamp(
        (kcalFactor * 0.22) + (proteinShare * 0.06) + (fatShare * 0.03) - lowCalPenalty,
        0,
        Metabolism.IMMEDIATE_HUNGER_MAX_DELTA
    )
    local mechanicalVisibleHunger = math.abs(tonumber(applied.hunger) or 0)

    return {
        targetHungerDrop = targetHungerDrop,
        mechanicalVisibleHunger = mechanicalVisibleHunger,
    }
end

function Metabolism.getImmediateHungerDrop(values, fraction)
    return computeImmediateHungerSnapshot(values, fraction).targetHungerDrop
end

function Metabolism.getImmediateFullnessDelta(values, fraction)
    return Metabolism.getImmediateHungerDrop(values, fraction)
end

function Metabolism.getImmediateFullnessCorrection(values, fraction)
    return -Metabolism.getImmediateHungerDrop(values, fraction)
end

function Metabolism.getFuelHungerMultiplier(fuel)
    return Metabolism.getFuelPressureFactor(fuel)
end

function Metabolism.getWeightControllerTarget(fuel)
    local value = clamp(fuel, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
    if value > Metabolism.FUEL_STORAGE_THRESHOLD then
        return 0.5
    end
    if value > Metabolism.FUEL_HIGH_THRESHOLD then
        return 0.1
    end
    if value >= Metabolism.FUEL_LOW_THRESHOLD then
        return 0.0
    end
    if value >= Metabolism.FUEL_PENALTY_THRESHOLD then
        return -0.15
    end
    return -0.6
end

function Metabolism.getDeprivationTarget(fuel)
    local value = clamp(fuel, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
    if value >= Metabolism.DEPRIVATION_FUEL_THRESHOLD then
        return 0
    end
    return (Metabolism.DEPRIVATION_FUEL_THRESHOLD - value) / Metabolism.DEPRIVATION_FUEL_THRESHOLD
end

function Metabolism.advanceDeprivation(current, fuel, deltaHours)
    local target = Metabolism.getDeprivationTarget(fuel)
    local recovering = target <= current
    local responseHours = target > current
        and Metabolism.DEPRIVATION_RISE_HOURS
        or Metabolism.DEPRIVATION_RECOVERY_HOURS
    local fraction = clamp(deltaHours / responseHours, 0, 1)
    local nextValue = clamp(approach(current, target, fraction), Metabolism.DEPRIVATION_MIN, Metabolism.DEPRIVATION_MAX)
    if recovering and nextValue < Metabolism.DEPRIVATION_PENALTY_ONSET then
        return 0
    end
    return nextValue
end

function Metabolism.getDeprivationPenaltyProgress(deprivation)
    local d = clamp(deprivation or 0, Metabolism.DEPRIVATION_MIN, Metabolism.DEPRIVATION_MAX)
    if d <= Metabolism.DEPRIVATION_PENALTY_ONSET then
        return 0
    end
    return clamp(
        (d - Metabolism.DEPRIVATION_PENALTY_ONSET) / (Metabolism.DEPRIVATION_MAX - Metabolism.DEPRIVATION_PENALTY_ONSET),
        0, 1)
end

function Metabolism.getExertionPenaltyMultiplier(deprivation)
    local progress = Metabolism.getDeprivationPenaltyProgress(deprivation)
    if progress <= 0 then
        return 1.0
    end
    return lerp(1.0, 1.0 + Metabolism.DEPRIVATION_ENDURANCE_MAX, progress)
end

function Metabolism.getFatigueAccelFactor(deprivation)
    local progress = Metabolism.getDeprivationPenaltyProgress(deprivation)
    if progress <= 0 then
        return 1.0
    end
    return lerp(1.0, 1.0 + Metabolism.DEPRIVATION_FATIGUE_MAX, progress)
end

function Metabolism.getMeleeDamageMultiplier(deprivation)
    local progress = Metabolism.getDeprivationPenaltyProgress(deprivation)
    if progress <= 0 then
        return 1.0
    end
    return lerp(1.0, 1.0 - Metabolism.DEPRIVATION_MELEE_MAX, progress)
end

function Metabolism.getWeightTrait(weightKg)
    local weight = roundToStep(tonumber(weightKg) or Metabolism.DEFAULT_WEIGHT_KG, 0.1)
    if weight <= 50 then
        return "Emaciated"
    end
    if weight <= 65 then
        return "Very Underweight"
    end
    if weight <= 75 then
        return "Underweight"
    end
    if weight >= 100 then
        return "Obese"
    end
    if weight >= 85 then
        return "Overweight"
    end
    return "Normal"
end

function Metabolism.ensureState(state)
    state = type(state) == "table" and state or {}

    state.version = Metabolism.STATE_VERSION
    state.fuel = clamp(state.fuel or state.fuelKcal or Metabolism.DEFAULT_FUEL, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
    state.carbs = nil
    state.fats = nil
    state.lipids = nil
    state.proteins = clamp(state.proteins or Metabolism.DEFAULT_PROTEIN, 0, Metabolism.PROTEIN_MAX)
    state.lastWorldHours = tonumber(state.lastWorldHours) or nil
    state.weightKg = clamp(state.weightKg or state.weight or Metabolism.DEFAULT_WEIGHT_KG, Metabolism.WEIGHT_MIN_KG, Metabolism.WEIGHT_MAX_KG)
    state.energyBalanceKcal = nil
    state.weightController = clamp(state.weightController or 0, -1, 1)
    state.deprivation = clamp(state.deprivation or 0, Metabolism.DEPRIVATION_MIN, Metabolism.DEPRIVATION_MAX)
    state.lastZone = tostring(state.lastZone or Metabolism.getFuelZone(state.fuel))
    state.lastMetAverage = normalizedMet(state.lastMetAverage, Metabolism.MET_REST)
    state.lastMetPeak = normalizedMet(state.lastMetPeak, state.lastMetAverage)
    state.lastEffectiveEnduranceMet = normalizedMet(state.lastEffectiveEnduranceMet, state.lastMetAverage)
    state.lastWorkTier = Metabolism.normalizeWorkTier(state.lastWorkTier or Metabolism.classifyWorkTier(state.lastMetAverage, false))
    state.lastMetSource = tostring(state.lastMetSource or "bootstrap")
    state.lastObservedHours = math.max(0, tonumber(state.lastObservedHours) or 0)
    state.lastHeavyHours = math.max(0, tonumber(state.lastHeavyHours) or 0)
    state.lastVeryHeavyHours = math.max(0, tonumber(state.lastVeryHeavyHours) or 0)
    state.lastBurnKcal = tonumber(state.lastBurnKcal) or 0
    state.lastDepositKcal = tonumber(state.lastDepositKcal) or 0
    state.visibleHunger = clamp(state.visibleHunger or state.hunger or 0, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
    state.lastSyncedHunger = tonumber(state.lastSyncedHunger) or nil
    state.lastBaseHungerGain = tonumber(state.lastBaseHungerGain) or 0
    state.lastPassiveHungerGain = tonumber(state.lastPassiveHungerGain) or state.lastBaseHungerGain
    state.lastCorrectionGain = tonumber(state.lastCorrectionGain) or 0
    state.lastHungerMultiplier = tonumber(state.lastHungerMultiplier) or Metabolism.getFuelHungerMultiplier(state.fuel)
    state.lastHungerBand = tostring(state.lastHungerBand or Metabolism.getVisibleHungerBand(state.visibleHunger))
    state.lastFuelPressureFactor = tonumber(state.lastFuelPressureFactor) or Metabolism.getFuelPressureFactor(state.fuel)
    state.lastGateMultiplier = tonumber(state.lastGateMultiplier) or Metabolism.getHungerGateMultiplier(state.fuel)
    state.lastMetHungerFactor = tonumber(state.lastMetHungerFactor) or 1.0
    state.lastTraceReason = tostring(state.lastTraceReason or "init")
    state.lastEnduranceObserved = tonumber(state.lastEnduranceObserved) or nil
    state.lastEnduranceRegenScale = tonumber(state.lastEnduranceRegenScale) or 1.0
    state.lastEnduranceDeprivDrain = tonumber(state.lastEnduranceDeprivDrain) or 0
    state.lastExtraEnduranceDrain = tonumber(state.lastExtraEnduranceDrain) or 0
    state.lastWeightDeltaKg = tonumber(state.lastWeightDeltaKg) or 0
    state.lastWeightChangeKcal = nil
    state.lastWeightRateKgPerWeek = tonumber(state.lastWeightRateKgPerWeek) or 0
    state.lastExertionMultiplier = tonumber(state.lastExertionMultiplier) or 1.0
    state.lastCarbDeficiency = nil
    state.lastFatDeficiency = nil
    state.lastProteinDeficiency = tonumber(state.lastProteinDeficiency) or Metabolism.getProteinDeficiencyProgress(state.proteins)
    state.lastCarbEnduranceMultiplier = nil
    state.lastFatWeightLossMultiplier = nil
    state.lastProteinHealingMultiplier = tonumber(state.lastProteinHealingMultiplier) or Metabolism.getProteinHealingMultiplier(state.proteins)
    state.lastAcuteFuelRecoveryScale = tonumber(state.lastAcuteFuelRecoveryScale) or Metabolism.getFuelRecoveryScale(state.fuel)
    state.satietyBuffer = clamp(state.satietyBuffer or 0, 0, Metabolism.SATIETY_BUFFER_MAX)
    state.lastSatietyQuality = clamp(tonumber(state.lastSatietyQuality) or 0, 0, 1)
    state.lastSatietyContribution = math.max(0, tonumber(state.lastSatietyContribution) or 0)
    state.lastSatietyReturnFactor = clamp(tonumber(state.lastSatietyReturnFactor) or 1.0, Metabolism.SATIETY_RETURN_FACTOR_MIN, 1.0)
    state.lastImmediateHungerDrop = clamp(tonumber(state.lastImmediateHungerDrop) or 0, 0, Metabolism.IMMEDIATE_HUNGER_MAX_DELTA)
    state.lastImmediateHungerMechanical = math.max(0, tonumber(state.lastImmediateHungerMechanical) or 0)
    state.lastImmediateFillTarget = clamp(tonumber(state.lastImmediateFillTarget) or 0, 0, Metabolism.IMMEDIATE_FULLNESS_MAX_DELTA)
    state.lastImmediateFillVanilla = math.max(0, tonumber(state.lastImmediateFillVanilla) or 0)
    state.lastImmediateFillCorrection = tonumber(state.lastImmediateFillCorrection) or 0
    state.baseHealthFromFood = tonumber(state.baseHealthFromFood) or nil
    state.pendingNutritionSuppressions = type(state.pendingNutritionSuppressions) == "table" and state.pendingNutritionSuppressions or nil
    state.lastWeightTrait = tostring(state.lastWeightTrait or Metabolism.getWeightTrait(state.weightKg))

    return state
end

function Metabolism.newState(overrides)
    return Metabolism.ensureState(shallowCopy(overrides or {}))
end

function Metabolism.scaleFoodValues(values, fraction)
    local scale = clamp(fraction or 1, 0, 1)
    return {
        hunger = (tonumber(values and values.hunger) or 0) * scale,
        baseHunger = (tonumber(values and (values.baseHunger or values.hunger)) or 0) * scale,
        kcal = (tonumber(values and values.kcal) or 0) * scale,
        carbs = (tonumber(values and values.carbs) or 0) * scale,
        fats = (tonumber(values and values.fats) or 0) * scale,
        proteins = (tonumber(values and values.proteins) or 0) * scale,
        fraction = scale,
        label = values and values.label or values and values.id or nil,
    }
end

function Metabolism.applyFoodValues(state, values, fraction, reason)
    state = Metabolism.ensureState(state)
    local applied = Metabolism.scaleFoodValues(values, fraction)
    local satietyQuality = Metabolism.getSatietyQuality(applied)
    local satietyContribution = Metabolism.getSatietyContribution(applied, 1)
    local immediateHunger = computeImmediateHungerSnapshot(applied, 1)
    local immediateFillCorrection = immediateHunger.targetHungerDrop - immediateHunger.mechanicalVisibleHunger

    state.fuel = clamp(state.fuel + applied.kcal, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
    state.proteins = clamp(state.proteins + applied.proteins, 0, Metabolism.PROTEIN_MAX)
    state.satietyBuffer = clamp(state.satietyBuffer + satietyContribution, 0, Metabolism.SATIETY_BUFFER_MAX)
    state.lastDepositKcal = applied.kcal
    state.lastWeightDeltaKg = 0
    state.lastWeightRateKgPerWeek = 0
    state.lastTraceReason = tostring(reason or applied.label or "food")
    state.lastZone = Metabolism.getFuelZone(state.fuel)
    state.lastHungerMultiplier = Metabolism.getFuelHungerMultiplier(state.fuel)
    state.lastWeightTrait = Metabolism.getWeightTrait(state.weightKg)
    state.lastSatietyQuality = satietyQuality
    state.lastSatietyContribution = satietyContribution
    state.lastSatietyReturnFactor = Metabolism.getSatietyReturnFactor(state.satietyBuffer)
    state.lastImmediateHungerDrop = immediateHunger.targetHungerDrop
    state.lastImmediateHungerMechanical = immediateHunger.mechanicalVisibleHunger
    state.lastImmediateFillTarget = immediateHunger.targetHungerDrop
    state.lastImmediateFillVanilla = immediateHunger.mechanicalVisibleHunger
    state.lastImmediateFillCorrection = immediateFillCorrection

    return {
        label = applied.label,
        fraction = applied.fraction,
        hunger = applied.hunger,
        visibleHunger = applied.hunger,
        kcal = applied.kcal,
        carbs = applied.carbs,
        fats = applied.fats,
        proteins = applied.proteins,
        fuelAfter = state.fuel,
        zoneAfter = state.lastZone,
        hungerMultiplierAfter = state.lastHungerMultiplier,
        weightAfter = state.weightKg,
        weightTraitAfter = state.lastWeightTrait,
        satietyQuality = satietyQuality,
        satietyContribution = satietyContribution,
        satietyBufferAfter = state.satietyBuffer,
        satietyReturnFactorAfter = state.lastSatietyReturnFactor,
        immediateHungerDrop = immediateHunger.targetHungerDrop,
        immediateHungerMechanical = immediateHunger.mechanicalVisibleHunger,
        immediateFillTarget = immediateHunger.targetHungerDrop,
        immediateFillVanilla = immediateHunger.mechanicalVisibleHunger,
        immediateFillCorrection = immediateFillCorrection,
    }
end

function Metabolism.advanceState(state, elapsedHours, workload, options)
    state = Metabolism.ensureState(state)

    local totalHours = math.max(0, tonumber(elapsedHours) or 0)
    local normalizedWorkload = Metabolism.normalizeWorkload(workload)
    local report = {
        elapsedHours = totalHours,
        averageMet = normalizedWorkload.averageMet,
        peakMet = normalizedWorkload.peakMet,
        effectiveEnduranceMet = normalizedWorkload.effectiveEnduranceMet,
        workTier = normalizedWorkload.workTier,
        source = normalizedWorkload.source,
        observedHours = normalizedWorkload.observedHours,
        heavyHours = normalizedWorkload.heavyHours,
        veryHeavyHours = normalizedWorkload.veryHeavyHours,
        sleepObserved = normalizedWorkload.sleepObserved,
        pendingBurnKcal = normalizedWorkload.pendingBurnKcal,
        appliedEnduranceDrain = normalizedWorkload.appliedEnduranceDrain,
        startFuel = state.fuel,
        startZone = Metabolism.getFuelZone(state.fuel),
        startWeightKg = state.weightKg,
        endFuel = state.fuel,
        endZone = Metabolism.getFuelZone(state.fuel),
        endWeightKg = state.weightKg,
        burnedKcal = 0,
        baseHungerGain = 0,
        correctionHungerGain = 0,
        visibleHungerGain = 0,
        startVisibleHunger = state.visibleHunger,
        endVisibleHunger = state.visibleHunger,
        peakHungerMultiplier = Metabolism.getFuelHungerMultiplier(state.fuel),
        peakFuelPressureFactor = Metabolism.getFuelPressureFactor(state.fuel),
        peakGateMultiplier = Metabolism.getHungerGateMultiplier(state.fuel),
        peakMetHungerFactor = Metabolism.getMetHungerFactor(normalizedWorkload),
        hungerBand = Metabolism.getVisibleHungerBand(state.visibleHunger),
        peakExertionMultiplier = Metabolism.getExertionPenaltyMultiplier(state.deprivation),
        extraEnduranceDrain = 0,
        weightDeltaKg = 0,
        weightRateKgPerWeek = 0,
        startWeightTrait = Metabolism.getWeightTrait(state.weightKg),
        endWeightTrait = Metabolism.getWeightTrait(state.weightKg),
        peakWeightController = math.abs(state.weightController or 0),
        burnWeightFactor = Metabolism.getWeightFuelBurnFactor(state.weightKg),
        peakProteinDeficiency = Metabolism.getProteinDeficiencyProgress(state.proteins),
        startProteinHealingMultiplier = Metabolism.getProteinHealingMultiplier(state.proteins),
        endProteinHealingMultiplier = Metabolism.getProteinHealingMultiplier(state.proteins),
        peakAcuteFuelRecoveryScale = Metabolism.getFuelRecoveryScale(state.fuel),
        startSatietyBuffer = state.satietyBuffer,
        endSatietyBuffer = state.satietyBuffer,
        satietyReturnFactor = Metabolism.getSatietyReturnFactor(state.satietyBuffer),
        slices = 0,
        reason = tostring(options and options.reason or normalizedWorkload.workTier or state.lastTraceReason or "advance"),
    }

    if totalHours <= 0 then
        state.lastMetAverage = report.averageMet
        state.lastMetPeak = report.peakMet
        state.lastEffectiveEnduranceMet = report.effectiveEnduranceMet
        state.lastWorkTier = report.workTier
        state.lastMetSource = report.source
        state.lastObservedHours = report.observedHours
        state.lastHeavyHours = report.heavyHours
        state.lastVeryHeavyHours = report.veryHeavyHours
        state.lastBurnKcal = 0
        state.lastBaseHungerGain = 0
        state.lastPassiveHungerGain = 0
        state.lastCorrectionGain = 0
        state.lastHungerMultiplier = report.peakHungerMultiplier
        state.lastHungerBand = report.hungerBand
        state.lastFuelPressureFactor = report.peakFuelPressureFactor
        state.lastGateMultiplier = report.peakGateMultiplier
        state.lastMetHungerFactor = report.peakMetHungerFactor
        state.lastExtraEnduranceDrain = 0
        state.lastWeightDeltaKg = 0
        state.lastWeightRateKgPerWeek = 0
        state.lastExertionMultiplier = report.peakExertionMultiplier
        state.lastWeightTrait = report.endWeightTrait
        state.lastZone = report.endZone
        state.lastSatietyReturnFactor = report.satietyReturnFactor
        state.lastAcuteFuelRecoveryScale = report.peakAcuteFuelRecoveryScale
        return report
    end

    local slices = math.max(1, math.ceil(totalHours / 0.25))
    local sliceHours = totalHours / slices
    local burnPerHour = Metabolism.getFuelBurnPerHourFromMet(normalizedWorkload, state.weightKg)
    local proteinBurnPerHour = Metabolism.getProteinBurnPerHour(normalizedWorkload)
    local hasPendingBurn = normalizedWorkload.pendingBurnKcal ~= nil and normalizedWorkload.pendingBurnKcal > 0
    if hasPendingBurn and totalHours > 0 then
        burnPerHour = math.max(0, normalizedWorkload.pendingBurnKcal) / totalHours
    end
    report.extraEnduranceDrain = math.max(0, normalizedWorkload.appliedEnduranceDrain or 0)

    report.slices = slices
    local satietyReturnFactorAccum = 0

    for _ = 1, slices do
        local hungerRate = Metabolism.getPassiveVisibleHungerRatePerHour(state, normalizedWorkload)
        local hungerGain = hungerRate.ratePerHour * sliceHours
        satietyReturnFactorAccum = satietyReturnFactorAccum + (hungerRate.satietyBandFactor * sliceHours)
        report.baseHungerGain = report.baseHungerGain + hungerGain
        report.visibleHungerGain = report.visibleHungerGain + hungerGain
        report.peakHungerMultiplier = math.max(report.peakHungerMultiplier, hungerRate.bandMultiplier)
        report.peakFuelPressureFactor = math.max(report.peakFuelPressureFactor, hungerRate.fuelPressureFactor)
        report.peakGateMultiplier = math.max(report.peakGateMultiplier, hungerRate.gateMultiplier)
        report.peakMetHungerFactor = math.max(report.peakMetHungerFactor, hungerRate.metHungerFactor)
        report.hungerBand = hungerRate.band
        state.visibleHunger = clamp(state.visibleHunger + hungerGain, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_CAP)
        report.endVisibleHunger = state.visibleHunger

        local metabolicBurn = burnPerHour * sliceHours
        local fuelBurn = math.min(state.fuel, metabolicBurn)
        state.fuel = clamp(state.fuel - fuelBurn, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
        state.proteins = clamp(state.proteins - (proteinBurnPerHour * sliceHours), 0, Metabolism.PROTEIN_MAX)
        report.burnedKcal = report.burnedKcal + metabolicBurn

        local proteinDeficiency = Metabolism.getProteinDeficiencyProgress(state.proteins)
        report.peakProteinDeficiency = math.max(report.peakProteinDeficiency, proteinDeficiency)
        report.peakAcuteFuelRecoveryScale = math.min(report.peakAcuteFuelRecoveryScale, Metabolism.getFuelRecoveryScale(state.fuel))

        report.peakExertionMultiplier = math.max(report.peakExertionMultiplier, Metabolism.getExertionPenaltyMultiplier(state.deprivation))

        local weightTarget = Metabolism.getWeightControllerTarget(state.fuel)
        state.weightController = approach(
            state.weightController,
            weightTarget,
            sliceHours / Metabolism.WEIGHT_CONTROLLER_RESPONSE_HOURS
        )
        report.peakWeightController = math.max(report.peakWeightController, math.abs(state.weightController))

        state.deprivation = Metabolism.advanceDeprivation(state.deprivation, state.fuel, sliceHours)
        report.peakDeprivation = math.max(report.peakDeprivation or 0, state.deprivation)

        local weightBefore = state.weightKg
        state.weightKg = clamp(
            state.weightKg + (Metabolism.WEIGHT_MAX_RATE_KG_PER_HOUR * state.weightController * sliceHours),
            Metabolism.WEIGHT_MIN_KG,
            Metabolism.WEIGHT_MAX_KG
        )
        report.weightDeltaKg = report.weightDeltaKg + (state.weightKg - weightBefore)

        state.satietyBuffer = clamp(
            state.satietyBuffer - (Metabolism.SATIETY_BUFFER_DECAY_PER_HOUR * sliceHours),
            0,
            Metabolism.SATIETY_BUFFER_MAX
        )
    end

    report.endFuel = state.fuel
    report.endZone = Metabolism.getFuelZone(state.fuel)
    report.endWeightKg = state.weightKg
    report.endWeightTrait = Metabolism.getWeightTrait(state.weightKg)
    report.endProteinHealingMultiplier = Metabolism.getProteinHealingMultiplier(state.proteins)
    report.endSatietyBuffer = state.satietyBuffer
    if totalHours > 0 then
        report.weightRateKgPerWeek = report.weightDeltaKg / totalHours * 24 * 7
        report.satietyReturnFactor = satietyReturnFactorAccum / totalHours
    end

    state.lastMetAverage = report.averageMet
    state.lastMetPeak = report.peakMet
    state.lastEffectiveEnduranceMet = report.effectiveEnduranceMet
    state.lastWorkTier = report.workTier
    state.lastMetSource = report.source
    state.lastObservedHours = report.observedHours
    state.lastHeavyHours = report.heavyHours
    state.lastVeryHeavyHours = report.veryHeavyHours
    state.lastBurnKcal = report.burnedKcal
    state.lastBaseHungerGain = report.baseHungerGain
    state.lastPassiveHungerGain = report.visibleHungerGain
    state.lastCorrectionGain = report.correctionHungerGain
    state.lastHungerMultiplier = Metabolism.getFuelHungerMultiplier(state.fuel)
    state.lastHungerBand = report.hungerBand
    state.lastFuelPressureFactor = report.peakFuelPressureFactor
    state.lastGateMultiplier = report.peakGateMultiplier
    state.lastMetHungerFactor = report.peakMetHungerFactor
    state.lastExtraEnduranceDrain = report.extraEnduranceDrain
    state.lastWeightDeltaKg = report.weightDeltaKg
    state.lastWeightRateKgPerWeek = report.weightRateKgPerWeek
    state.lastExertionMultiplier = report.peakExertionMultiplier
    state.lastProteinDeficiency = report.peakProteinDeficiency
    state.lastProteinHealingMultiplier = report.endProteinHealingMultiplier
    state.lastAcuteFuelRecoveryScale = report.peakAcuteFuelRecoveryScale
    state.lastWeightTrait = report.endWeightTrait
    state.lastZone = report.endZone
    state.lastTraceReason = report.reason
    state.lastSatietyReturnFactor = report.satietyReturnFactor
    state.hunger = state.visibleHunger

    return report
end

return Metabolism
