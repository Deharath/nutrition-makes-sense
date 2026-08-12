NutritionMakesSense = NutritionMakesSense or {}

local Metabolism = NutritionMakesSense.Metabolism or {}
NutritionMakesSense.Metabolism = Metabolism

Metabolism.STATE_VERSION = 15

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
Metabolism.FUEL_STORED_THRESHOLD = 1500
Metabolism.FUEL_LOW_THRESHOLD = 550
Metabolism.FUEL_DEPLETED_THRESHOLD = 200
Metabolism.DEFAULT_FUEL = 1000

Metabolism.DEPRIVATION_MIN = 0
Metabolism.DEPRIVATION_MAX = 1.0
Metabolism.ENERGY_APPETITE_BALANCE_DEADZONE_KCAL = 200
Metabolism.ENERGY_APPETITE_BALANCE_FULL_KCAL = 800
Metabolism.ENERGY_APPETITE_MAX_RATE_PER_HOUR = 0.050
Metabolism.DEPRIVATION_BALANCE_DEADZONE_KCAL = 1800
Metabolism.DEPRIVATION_BALANCE_FULL_KCAL = 7000
Metabolism.DEPRIVATION_RISE_HOURS = 48
Metabolism.DEPRIVATION_RECOVERY_HOURS = 36
Metabolism.DEPRIVATION_PENALTY_ONSET = 0.10

Metabolism.VANILLA_NUTRITION_ANCHOR = {
    calories = 0,
    carbs = 0,
    fats = 0,
    proteins = 0,
}

Metabolism.DEFAULT_WEIGHT_KG = 80
Metabolism.WEIGHT_MIN_KG = 35
Metabolism.WEIGHT_MAX_KG = 140
Metabolism.WEIGHT_CONTROLLER_RESPONSE_HOURS = 24
Metabolism.WEIGHT_BALANCE_RESPONSE_HOURS = 72
Metabolism.WEIGHT_DAILY_BALANCE_DEADZONE_KCAL = 50
Metabolism.WEIGHT_BALANCE_GAIN_CAP_KCAL = 9000
Metabolism.WEIGHT_BALANCE_LOSS_CAP_KCAL = 9000
Metabolism.WEIGHT_MAX_GAIN_RATE_KG_PER_HOUR = 1.5 / (24 * 7)
Metabolism.WEIGHT_MAX_LOSS_RATE_KG_PER_HOUR = 2.4 / (24 * 7)
Metabolism.WEIGHT_BURN_REFERENCE_KG = 80
Metabolism.WEIGHT_BURN_FACTOR_PER_KG = 0.0025
Metabolism.WEIGHT_BURN_FACTOR_MIN = 0.90
Metabolism.WEIGHT_BURN_FACTOR_MAX = 1.10
Metabolism.LEGACY_PROTEIN_MAX = 350
Metabolism.PROTEIN_DAILY_NEED_G_PER_KG = 0.80
Metabolism.PROTEIN_DAILY_NEED_MIN = 45
Metabolism.PROTEIN_DAILY_NEED_MAX = 110
Metabolism.PROTEIN_ADEQUACY_DEFAULT_DAYS = 4.0
Metabolism.PROTEIN_ADEQUACY_MAX_DAYS = 5.0
Metabolism.PROTEIN_DEFICIENCY_START_DAYS = 2.0
Metabolism.PROTEIN_HEALING_MAX_PENALTY = 0.12
Metabolism.PROTEIN_STRENGTH_XP_BONUS_MULTIPLIER = 1.5
Metabolism.PROTEIN_STRENGTH_XP_PENALTY_MULTIPLIER = 0.7
Metabolism.PROTEIN_STRENGTH_XP_BONUS_MIN_DAYS = 3.75
Metabolism.PROTEIN_STRENGTH_XP_BONUS_MAX_DAYS = Metabolism.PROTEIN_ADEQUACY_MAX_DAYS
Metabolism.PROTEIN_STRENGTH_XP_PENALTY_MAX_DAYS = 1.5
Metabolism.PROTEIN_MAX = Metabolism.DEFAULT_WEIGHT_KG * Metabolism.PROTEIN_DAILY_NEED_G_PER_KG * Metabolism.PROTEIN_ADEQUACY_MAX_DAYS
Metabolism.DEFAULT_PROTEIN = Metabolism.DEFAULT_WEIGHT_KG * Metabolism.PROTEIN_DAILY_NEED_G_PER_KG * Metabolism.PROTEIN_ADEQUACY_DEFAULT_DAYS

Metabolism.SLEEP_FUEL_BURN_PER_HOUR = 35
Metabolism.SLEEP_VISIBLE_HUNGER_PER_HOUR = 0.004

Metabolism.SATIETY_BUFFER_MAX = 1.5
Metabolism.SATIETY_BUFFER_DECAY_PER_HOUR = 0.08
Metabolism.SATIETY_RETURN_FACTOR_MIN = 0.55
Metabolism.SATIETY_FUEL_PIERCE_FLOOR = 0.55
Metabolism.MEAL_FULLNESS_KCAL_REFERENCE = 400
Metabolism.MEAL_FULLNESS_KCAL_FACTOR_MAX = 1.60
Metabolism.MEAL_FULLNESS_PHYSICAL_CAP = 0.12
Metabolism.MEAL_FULLNESS_NUTRIENT_CAP = 0.40
Metabolism.MEAL_FULLNESS_MAX_DELTA = 0.40
Metabolism.VISIBLE_HUNGER_MIN = 0.0
Metabolism.VISIBLE_HUNGER_MAX = 1.0
Metabolism.HUNGER_THRESHOLD_PECKISH = 0.15
Metabolism.HUNGER_THRESHOLD_HUNGRY = 0.25
Metabolism.HUNGER_THRESHOLD_VERY_HUNGRY = 0.45
Metabolism.HUNGER_THRESHOLD_STARVING = 0.70
Metabolism.BASE_WAKE_HUNGER_PER_HOUR = 0.028
Metabolism.STARVATION_DECEL_FLOOR = 0.02
Metabolism.VISIBLE_HUNGER_CAP = 0.699
Metabolism.SLEEP_HUNGER_FACTOR = 0.33
Metabolism.HUNGER_MET_FACTOR_PER_MET = 0.05
Metabolism.HUNGER_MET_FACTOR_MAX = 1.30
Metabolism.FUEL_PRESSURE_LOW_MAX = 2.40
Metabolism.FUEL_PRESSURE_DEPLETED_MAX = 3.00
Metabolism.TRAIT_SATIETY_DECAY_MULTIPLIER_HEARTY_APPETITE = 1.20
Metabolism.TRAIT_SATIETY_DECAY_MULTIPLIER_LIGHT_EATER = 0.85
Metabolism.TRAIT_BURN_MULTIPLIER_SLOW_METABOLISM = 0.96
Metabolism.TRAIT_BURN_MULTIPLIER_FAST_METABOLISM = 1.04
Metabolism.TRAIT_WEIGHT_GAIN_MULTIPLIER_SLOW_METABOLISM = 1.12
Metabolism.TRAIT_WEIGHT_GAIN_MULTIPLIER_FAST_METABOLISM = 0.90
Metabolism.TRAIT_WEIGHT_LOSS_MULTIPLIER_SLOW_METABOLISM = 0.90
Metabolism.TRAIT_WEIGHT_LOSS_MULTIPLIER_FAST_METABOLISM = 1.12
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
    local appliedEnduranceDrain = tonumber(summary.appliedEnduranceDrain)

    if sleepObserved then
        averageMet = Metabolism.MET_SLEEP
        peakMet = Metabolism.MET_SLEEP
    end

    return {
        averageMet = averageMet,
        peakMet = peakMet,
        observedHours = observedHours,
        heavyHours = heavyHours,
        veryHeavyHours = veryHeavyHours,
        source = source,
        sleepObserved = sleepObserved,
        workTier = Metabolism.classifyWorkTier(averageMet, sleepObserved),
        appliedEnduranceDrain = appliedEnduranceDrain,
    }
end

function Metabolism.normalizeTraitEffects(traitEffects)
    local normalized = type(traitEffects) == "table" and traitEffects or {}
    return {
        satietyDecayMultiplier = math.max(0, tonumber(normalized.satietyDecayMultiplier) or 1.0),
        burnMultiplier = math.max(0, tonumber(normalized.burnMultiplier) or 1.0),
        weightGainMultiplier = math.max(0, tonumber(normalized.weightGainMultiplier) or 1.0),
        weightLossMultiplier = math.max(0, tonumber(normalized.weightLossMultiplier) or 1.0),
    }
end

function Metabolism.copyState(state)
    return Metabolism.ensureState(shallowCopy(state or {}))
end

function Metabolism.getFuelZone(fuel)
    local value = clamp(fuel, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
    if value > Metabolism.FUEL_STORED_THRESHOLD then
        return "Stored"
    end
    if value >= Metabolism.FUEL_LOW_THRESHOLD then
        return "Ready"
    end
    if value >= Metabolism.FUEL_DEPLETED_THRESHOLD then
        return "Low"
    end
    return "Depleted"
end

function Metabolism.getWeightFuelBurnFactor(weightKg)
    local weight = clamp(weightKg or Metabolism.DEFAULT_WEIGHT_KG, Metabolism.WEIGHT_MIN_KG, Metabolism.WEIGHT_MAX_KG)
    local delta = weight - Metabolism.WEIGHT_BURN_REFERENCE_KG
    local factor = 1.0 + (delta * Metabolism.WEIGHT_BURN_FACTOR_PER_KG)
    return clamp(factor, Metabolism.WEIGHT_BURN_FACTOR_MIN, Metabolism.WEIGHT_BURN_FACTOR_MAX)
end

function Metabolism.getFuelBurnPerHourFromMet(workload, weightKg, traitEffects)
    local summary = Metabolism.normalizeWorkload(workload)
    local weightFactor = Metabolism.getWeightFuelBurnFactor(weightKg)
    local traitSummary = Metabolism.normalizeTraitEffects(traitEffects)
    if summary.sleepObserved then
        return Metabolism.SLEEP_FUEL_BURN_PER_HOUR * weightFactor * traitSummary.burnMultiplier
    end
    return (75 + (48 * math.max(0, summary.averageMet - Metabolism.MET_REST))) * weightFactor * traitSummary.burnMultiplier
end

function Metabolism.getProteinNeedPerDay(weightKg)
    local weight = clamp(tonumber(weightKg) or Metabolism.DEFAULT_WEIGHT_KG, Metabolism.WEIGHT_MIN_KG, Metabolism.WEIGHT_MAX_KG)
    return clamp(
        weight * Metabolism.PROTEIN_DAILY_NEED_G_PER_KG,
        Metabolism.PROTEIN_DAILY_NEED_MIN,
        Metabolism.PROTEIN_DAILY_NEED_MAX
    )
end

function Metabolism.getProteinAdequacyMax(weightKg)
    return Metabolism.getProteinNeedPerDay(weightKg) * Metabolism.PROTEIN_ADEQUACY_MAX_DAYS
end

function Metabolism.getDefaultProteinAdequacy(weightKg)
    return Metabolism.getProteinNeedPerDay(weightKg) * Metabolism.PROTEIN_ADEQUACY_DEFAULT_DAYS
end

local function clampProteinAdequacy(value, weightKg)
    return clamp(tonumber(value) or 0, 0, Metabolism.getProteinAdequacyMax(weightKg))
end

function Metabolism.getProteinRequirementPerHour(weightKg)
    return Metabolism.getProteinNeedPerDay(weightKg) / 24
end

function Metabolism.getProteinAdequacyDays(proteins, weightKg)
    local needPerDay = Metabolism.getProteinNeedPerDay(weightKg)
    if needPerDay <= 0 then
        return 0
    end
    return clampProteinAdequacy(proteins or 0, weightKg) / needPerDay
end

function Metabolism.getStrengthXpProteinMultiplier(proteins, weightKg)
    local adequacyDays = Metabolism.getProteinAdequacyDays(proteins, weightKg)
    if adequacyDays <= Metabolism.PROTEIN_STRENGTH_XP_PENALTY_MAX_DAYS then
        return Metabolism.PROTEIN_STRENGTH_XP_PENALTY_MULTIPLIER
    end
    if adequacyDays >= Metabolism.PROTEIN_STRENGTH_XP_BONUS_MIN_DAYS
        and adequacyDays <= Metabolism.PROTEIN_STRENGTH_XP_BONUS_MAX_DAYS then
        return Metabolism.PROTEIN_STRENGTH_XP_BONUS_MULTIPLIER
    end
    return 1.0
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

function Metabolism.getProteinDeficiencyProgress(proteins, weightKg)
    local deficiencyStart = Metabolism.getProteinNeedPerDay(weightKg) * Metabolism.PROTEIN_DEFICIENCY_START_DAYS
    local available = clampProteinAdequacy(proteins or 0, weightKg)
    if available >= deficiencyStart then
        return 0
    end
    if deficiencyStart <= 0 then
        return 1
    end
    return clamp((deficiencyStart - available) / deficiencyStart, 0, 1)
end

function Metabolism.getProteinHealingMultiplier(proteins, weightKg)
    local deficiency = Metabolism.getProteinDeficiencyProgress(proteins, weightKg)
    return lerp(1.0, 1.0 - Metabolism.PROTEIN_HEALING_MAX_PENALTY, deficiency)
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

function Metabolism.getMealFullness(values, observedHungerDrop)
    local kcal = math.max(0, tonumber(values and values.kcal) or 0)
    local _, fatKcal, proteinKcal, totalMacroKcal = computeMacroCalories(values)
    local proteinShare = 0
    local fatShare = 0
    if totalMacroKcal > 0 then
        proteinShare = proteinKcal / totalMacroKcal
        fatShare = fatKcal / totalMacroKcal
    end

    -- Nutrition supplies a bounded post-ingestive fullness signal. The square-root
    -- response lets ordinary meals matter without allowing oils, recipe reservoirs,
    -- or giant modded foods to manufacture an arbitrarily large hunger drop.
    local kcalFactor = kcal > 0 and math.sqrt(kcal / Metabolism.MEAL_FULLNESS_KCAL_REFERENCE) or 0
    kcalFactor = math.min(kcalFactor, Metabolism.MEAL_FULLNESS_KCAL_FACTOR_MAX)
    local lowCalPenalty = lerp(0.04, 0.00, clamp(kcal / 60, 0, 1))
    local nutrientDrop = clamp(
        (kcalFactor * 0.22) + (proteinShare * 0.06) + (fatShare * 0.03) - lowCalPenalty,
        0,
        Metabolism.MEAL_FULLNESS_NUTRIENT_CAP
    )

    -- Vanilla HungerChange remains useful as evidence that physical volume was
    -- consumed, but it is also a recipe/depletion reservoir. Preserve small real
    -- drops exactly and cap the overloaded part. max(), rather than addition, avoids
    -- counting the same meal twice and makes prediction/server confirmation idempotent.
    local mechanicalDrop = clamp(tonumber(observedHungerDrop) or 0, 0, 1)
    local physicalDrop = math.min(mechanicalDrop, Metabolism.MEAL_FULLNESS_PHYSICAL_CAP)
    local targetDrop = clamp(
        math.max(nutrientDrop, physicalDrop),
        0,
        Metabolism.MEAL_FULLNESS_MAX_DELTA
    )

    return {
        kcal = kcal,
        proteinShare = proteinShare,
        fatShare = fatShare,
        mechanicalDrop = mechanicalDrop,
        physicalDrop = physicalDrop,
        nutrientDrop = nutrientDrop,
        targetDrop = targetDrop,
        correction = targetDrop - mechanicalDrop,
    }
end

function Metabolism.resolveMealHunger(values, observedHungerDrop, preVisibleHunger)
    local fullness = Metabolism.getMealFullness(values, observedHungerDrop)
    local preHunger = clamp(
        tonumber(preVisibleHunger) or 0,
        Metabolism.VISIBLE_HUNGER_MIN,
        Metabolism.VISIBLE_HUNGER_MAX
    )
    local targetHunger = clamp(
        preHunger - fullness.targetDrop,
        Metabolism.VISIBLE_HUNGER_MIN,
        Metabolism.VISIBLE_HUNGER_MAX
    )

    fullness.preVisibleHunger = preHunger
    fullness.targetVisibleHunger = targetHunger
    fullness.appliedDrop = math.max(0, preHunger - targetHunger)
    fullness.appliedCorrection = fullness.appliedDrop - fullness.mechanicalDrop
    return fullness
end

function Metabolism.getSatietyReturnFactor(satietyBuffer)
    return lerp(1.0, Metabolism.SATIETY_RETURN_FACTOR_MIN, clamp(satietyBuffer or 0, 0, 1))
end

function Metabolism.getVisibleHungerBand(hunger)
    local value = clamp(hunger or 0, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
    if value <= Metabolism.HUNGER_THRESHOLD_PECKISH then
        return "comfortable"
    end
    if value <= Metabolism.HUNGER_THRESHOLD_HUNGRY then
        return "peckish"
    end
    if value <= Metabolism.HUNGER_THRESHOLD_VERY_HUNGRY then
        return "hungry"
    end
    if value <= Metabolism.HUNGER_THRESHOLD_STARVING then
        return "very_hungry"
    end
    return "starving"
end

function Metabolism.getFuelPressureFactor(fuel)
    local value = clamp(fuel, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
    if value >= Metabolism.FUEL_LOW_THRESHOLD then
        return 1.0
    end
    if value >= Metabolism.FUEL_DEPLETED_THRESHOLD then
        local lowProgress = (Metabolism.FUEL_LOW_THRESHOLD - value) / (Metabolism.FUEL_LOW_THRESHOLD - Metabolism.FUEL_DEPLETED_THRESHOLD)
        local curved = 1.0 - ((1.0 - lowProgress) * (1.0 - lowProgress) * (1.0 - lowProgress))
        return lerp(1.0, Metabolism.FUEL_PRESSURE_LOW_MAX, curved)
    end
    local depletedProgress = 1.0 - (value / Metabolism.FUEL_DEPLETED_THRESHOLD)
    return lerp(Metabolism.FUEL_PRESSURE_LOW_MAX, Metabolism.FUEL_PRESSURE_DEPLETED_MAX, depletedProgress)
end

function Metabolism.getHungerGateMultiplier(fuel)
    local value = clamp(fuel, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
    if value >= Metabolism.FUEL_LOW_THRESHOLD then
        return 0.8
    end
    if value >= Metabolism.FUEL_DEPLETED_THRESHOLD then
        local lowProgress = (Metabolism.FUEL_LOW_THRESHOLD - value) / (Metabolism.FUEL_LOW_THRESHOLD - Metabolism.FUEL_DEPLETED_THRESHOLD)
        return lerp(0.8, 1.5, lowProgress)
    end
    local depletedProgress = 1.0 - (value / Metabolism.FUEL_DEPLETED_THRESHOLD)
    return lerp(1.5, 2.2, depletedProgress)
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
    if hunger <= Metabolism.HUNGER_THRESHOLD_PECKISH then
        return satietyReturnFactor
    end
    if hunger > Metabolism.HUNGER_THRESHOLD_VERY_HUNGRY then
        return 1.0
    end

    local fade = 1.0 - ((hunger - Metabolism.HUNGER_THRESHOLD_PECKISH) / (Metabolism.HUNGER_THRESHOLD_VERY_HUNGRY - Metabolism.HUNGER_THRESHOLD_PECKISH))
    return lerp(1.0, satietyReturnFactor, fade)
end

function Metabolism.getStarvationDecelFactor(hunger)
    if hunger <= Metabolism.HUNGER_THRESHOLD_VERY_HUNGRY then
        return 1.0
    end
    if hunger > Metabolism.HUNGER_THRESHOLD_STARVING then
        return Metabolism.STARVATION_DECEL_FLOOR
    end
    local remaining = Metabolism.HUNGER_THRESHOLD_STARVING - hunger
    local range = Metabolism.HUNGER_THRESHOLD_STARVING - Metabolism.HUNGER_THRESHOLD_VERY_HUNGRY
    local ratio = remaining / range
    return math.max(Metabolism.STARVATION_DECEL_FLOOR, ratio * ratio)
end

function Metabolism.getPassiveVisibleHungerRatePerHour(state, workload, traitEffects, hungerRateMultiplier)
    state = Metabolism.ensureState(state)
    local summary = Metabolism.normalizeWorkload(workload)
    local hunger = clamp(state.visibleHunger or 0, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
    local fuelPressureFactor = Metabolism.getFuelPressureFactor(state.fuel)
    local gateMultiplier = Metabolism.getHungerGateMultiplier(state.fuel)
    local metHungerFactor = Metabolism.getMetHungerFactor(summary)
    local satietyBandFactor = Metabolism.getSatietyBandFactor(state.satietyBuffer, hunger, state.fuel)
    local unscaledBaseRate = summary.sleepObserved
        and (Metabolism.BASE_WAKE_HUNGER_PER_HOUR * Metabolism.SLEEP_HUNGER_FACTOR)
        or (Metabolism.BASE_WAKE_HUNGER_PER_HOUR * metHungerFactor)
    local sandboxMultiplier = math.max(0, tonumber(hungerRateMultiplier) or 1.0)
    local baseRate = unscaledBaseRate * sandboxMultiplier

    local bandMultiplier = 1.0
    if hunger <= Metabolism.HUNGER_THRESHOLD_PECKISH then
        bandMultiplier = 1.0 * fuelPressureFactor
    elseif hunger <= Metabolism.HUNGER_THRESHOLD_HUNGRY then
        bandMultiplier = 1.1 * fuelPressureFactor
    elseif hunger <= Metabolism.HUNGER_THRESHOLD_VERY_HUNGRY then
        bandMultiplier = 1.3 * fuelPressureFactor
    else
        bandMultiplier = gateMultiplier
    end

    local starvationDecel = Metabolism.getStarvationDecelFactor(hunger)
    local energyAppetiteProgress = Metabolism.getEnergyAppetiteProgress(state.weightBalanceKcal)
    local energyAppetiteRatePerHour = Metabolism.ENERGY_APPETITE_MAX_RATE_PER_HOUR
        * energyAppetiteProgress
        * sandboxMultiplier
        * starvationDecel
    if summary.sleepObserved then
        energyAppetiteRatePerHour = energyAppetiteRatePerHour * Metabolism.SLEEP_HUNGER_FACTOR
    end

    return {
        ratePerHour = (baseRate * bandMultiplier * satietyBandFactor * starvationDecel) + energyAppetiteRatePerHour,
        baseRatePerHour = baseRate,
        unscaledBaseRatePerHour = unscaledBaseRate,
        hungerRateMultiplier = sandboxMultiplier,
        band = Metabolism.getVisibleHungerBand(hunger),
        bandMultiplier = bandMultiplier,
        satietyBandFactor = satietyBandFactor,
        fuelPressureFactor = fuelPressureFactor,
        gateMultiplier = gateMultiplier,
        starvationDecel = starvationDecel,
        metHungerFactor = metHungerFactor,
        sleepObserved = summary.sleepObserved,
        energyAppetiteProgress = energyAppetiteProgress,
        energyAppetiteRatePerHour = energyAppetiteRatePerHour,
    }
end

local function clampWeightBalance(value)
    return clamp(
        value,
        -Metabolism.WEIGHT_BALANCE_LOSS_CAP_KCAL,
        Metabolism.WEIGHT_BALANCE_GAIN_CAP_KCAL
    )
end

function Metabolism.getWeightControllerTargetFromBalance(weightBalanceKcal)
    local value = clampWeightBalance(tonumber(weightBalanceKcal) or 0)
    local estimatedDailyBalanceKcal = value * (24 / Metabolism.WEIGHT_BALANCE_RESPONSE_HOURS)
    local absDailyBalanceKcal = math.abs(estimatedDailyBalanceKcal)
    local deadzoneDailyKcal = Metabolism.WEIGHT_DAILY_BALANCE_DEADZONE_KCAL
    if absDailyBalanceKcal <= deadzoneDailyKcal then
        return 0
    end
    if estimatedDailyBalanceKcal > 0 then
        local adjustedDailyBalanceKcal = estimatedDailyBalanceKcal - deadzoneDailyKcal
        local desiredRateKgPerWeek = (adjustedDailyBalanceKcal * 7) / 7700
        local maxGainKgPerWeek = Metabolism.WEIGHT_MAX_GAIN_RATE_KG_PER_HOUR * 24 * 7
        return clamp(desiredRateKgPerWeek / math.max(0.000001, maxGainKgPerWeek), 0, 1)
    end
    local adjustedDailyBalanceKcal = absDailyBalanceKcal - deadzoneDailyKcal
    local desiredRateKgPerWeek = (adjustedDailyBalanceKcal * 7) / 7700
    local maxLossKgPerWeek = Metabolism.WEIGHT_MAX_LOSS_RATE_KG_PER_HOUR * 24 * 7
    return -clamp(desiredRateKgPerWeek / math.max(0.000001, maxLossKgPerWeek), 0, 1)
end

function Metabolism.addWeightBalanceKcal(state, deltaKcal)
    if type(state) ~= "table" then
        return 0
    end
    state.weightBalanceKcal = clampWeightBalance((tonumber(state.weightBalanceKcal) or 0) + (tonumber(deltaKcal) or 0))
    return state.weightBalanceKcal
end

function Metabolism.advanceWeightBalanceKcal(currentBalanceKcal, deltaKcal, deltaHours)
    local balance = clampWeightBalance((tonumber(currentBalanceKcal) or 0) + (tonumber(deltaKcal) or 0))
    local hours = math.max(0, tonumber(deltaHours) or 0)
    if hours <= 0 then
        return balance
    end
    return clampWeightBalance(approach(balance, 0, hours / Metabolism.WEIGHT_BALANCE_RESPONSE_HOURS))
end

function Metabolism.getEnergyAppetiteProgress(weightBalanceKcal)
    local deficit = math.max(0, -(tonumber(weightBalanceKcal) or 0) - Metabolism.ENERGY_APPETITE_BALANCE_DEADZONE_KCAL)
    return clamp(
        deficit / math.max(1, Metabolism.ENERGY_APPETITE_BALANCE_FULL_KCAL - Metabolism.ENERGY_APPETITE_BALANCE_DEADZONE_KCAL),
        0,
        1
    )
end

function Metabolism.getDeprivationTarget(balanceOrState)
    local balance = balanceOrState
    if type(balanceOrState) == "table" then
        balance = tonumber(balanceOrState.weightBalanceKcal) or 0
    end
    local deficit = math.max(0, -(tonumber(balance) or 0) - Metabolism.DEPRIVATION_BALANCE_DEADZONE_KCAL)
    return clamp(
        deficit / math.max(1, Metabolism.DEPRIVATION_BALANCE_FULL_KCAL - Metabolism.DEPRIVATION_BALANCE_DEADZONE_KCAL),
        0,
        1
    )
end

function Metabolism.advanceDeprivation(current, weightBalanceKcal, deltaHours)
    local target = Metabolism.getDeprivationTarget(weightBalanceKcal)
    local responseHours = target > current
        and Metabolism.DEPRIVATION_RISE_HOURS
        or Metabolism.DEPRIVATION_RECOVERY_HOURS
    local fraction = clamp(deltaHours / responseHours, 0, 1)
    local nextValue = clamp(approach(current, target, fraction), Metabolism.DEPRIVATION_MIN, Metabolism.DEPRIVATION_MAX)
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

local DURABLE_STATE_FIELDS = {
    version = true,
    initialized = true,
    fuel = true,
    proteins = true,
    lastWorldHours = true,
    weightKg = true,
    weightController = true,
    weightBalanceKcal = true,
    deprivation = true,
    visibleHunger = true,
    satietyBuffer = true,
    depositSequence = true,
    baseHealthFromFood = true,
}

function Metabolism.ensureState(state)
    state = type(state) == "table" and state or {}
    local legacyVersion = tonumber(state.version) or 0
    local initialized = state.initialized == true
    local fuel = state.fuel or state.fuelKcal or Metabolism.DEFAULT_FUEL
    local weightKg = state.weightKg or state.weight or Metabolism.DEFAULT_WEIGHT_KG
    local proteins = state.proteins
    local lastWorldHours = tonumber(state.lastWorldHours) or nil
    local weightController = state.weightController
    local weightBalanceKcal = state.weightBalanceKcal
    local deprivation = state.deprivation
    local visibleHunger = state.visibleHunger
    local satietyBuffer = state.satietyBuffer
    local depositSequence = state.depositSequence
    local baseHealthFromFood = state.baseHealthFromFood

    for field in pairs(state) do
        if not DURABLE_STATE_FIELDS[field] then
            state[field] = nil
        end
    end

    state.version = Metabolism.STATE_VERSION
    state.initialized = initialized
    state.fuel = clamp(fuel, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
    state.lastWorldHours = lastWorldHours
    state.weightKg = clamp(weightKg, Metabolism.WEIGHT_MIN_KG, Metabolism.WEIGHT_MAX_KG)
    if legacyVersion >= 1 and legacyVersion < 9 and tonumber(proteins) ~= nil then
        local legacyFraction = clamp((tonumber(proteins) or Metabolism.DEFAULT_PROTEIN) / math.max(0.000001, Metabolism.LEGACY_PROTEIN_MAX), 0, 1)
        state.proteins = clampProteinAdequacy(legacyFraction * Metabolism.getProteinAdequacyMax(state.weightKg), state.weightKg)
    else
        state.proteins = clampProteinAdequacy(proteins or Metabolism.getDefaultProteinAdequacy(state.weightKg), state.weightKg)
    end
    state.weightController = clamp(weightController or 0, -1, 1)
    state.weightBalanceKcal = clampWeightBalance(weightBalanceKcal or 0)
    state.deprivation = clamp(deprivation or 0, Metabolism.DEPRIVATION_MIN, Metabolism.DEPRIVATION_MAX)
    if legacyVersion >= 1 and legacyVersion < 14 then
        state.deprivation = math.min(state.deprivation, Metabolism.getDeprivationTarget(state.weightBalanceKcal))
    end
    state.visibleHunger = clamp(visibleHunger or 0, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
    state.satietyBuffer = clamp(satietyBuffer or 0, 0, Metabolism.SATIETY_BUFFER_MAX)
    state.depositSequence = math.max(0, math.floor(tonumber(depositSequence) or 0))
    state.baseHealthFromFood = tonumber(baseHealthFromFood) or nil
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
    state.fuel = clamp(state.fuel + applied.kcal, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
    state.weightBalanceKcal = Metabolism.addWeightBalanceKcal(state, applied.kcal)
    state.proteins = clampProteinAdequacy(state.proteins + applied.proteins, state.weightKg)
    state.satietyBuffer = clamp(state.satietyBuffer + satietyContribution, 0, Metabolism.SATIETY_BUFFER_MAX)
    state.depositSequence = state.depositSequence + 1
    local zoneAfter = Metabolism.getFuelZone(state.fuel)
    local weightTraitAfter = Metabolism.getWeightTrait(state.weightKg)
    local satietyReturnFactorAfter = Metabolism.getSatietyReturnFactor(state.satietyBuffer)

    return {
        reason = tostring(reason or applied.label or "food"),
        label = applied.label,
        fraction = applied.fraction,
        hunger = applied.hunger,
        visibleHunger = applied.hunger,
        kcal = applied.kcal,
        depositSequence = state.depositSequence,
        carbs = applied.carbs,
        fats = applied.fats,
        proteins = applied.proteins,
        fuelAfter = state.fuel,
        zoneAfter = zoneAfter,
        weightAfter = state.weightKg,
        weightTraitAfter = weightTraitAfter,
        satietyQuality = satietyQuality,
        satietyContribution = satietyContribution,
        satietyBufferAfter = state.satietyBuffer,
        satietyReturnFactorAfter = satietyReturnFactorAfter,
    }
end

function Metabolism.advanceState(state, elapsedHours, workload, options)
    state = Metabolism.ensureState(state)

    local totalHours = math.max(0, tonumber(elapsedHours) or 0)
    local normalizedWorkload = Metabolism.normalizeWorkload(workload)
    local traitEffects = Metabolism.normalizeTraitEffects(options and options.traitEffects)
    local statsDecreaseMultiplier = math.max(0, tonumber(options and options.statsDecreaseMultiplier) or 1.0)
    local appetiteRateMultiplier = math.max(0, tonumber(options and options.appetiteRateMultiplier) or 1.0)
    local hungerRateMultiplier = math.max(0,
        tonumber(options and options.hungerRateMultiplier)
            or (statsDecreaseMultiplier * appetiteRateMultiplier)
    )
    local energyBurnMultiplier = math.max(0, tonumber(options and options.energyBurnMultiplier) or 1.0)
    local report = {
        elapsedHours = totalHours,
        averageMet = normalizedWorkload.averageMet,
        peakMet = normalizedWorkload.peakMet,
        workTier = normalizedWorkload.workTier,
        source = normalizedWorkload.source,
        observedHours = normalizedWorkload.observedHours,
        heavyHours = normalizedWorkload.heavyHours,
        veryHeavyHours = normalizedWorkload.veryHeavyHours,
        sleepObserved = normalizedWorkload.sleepObserved,
        appliedEnduranceDrain = normalizedWorkload.appliedEnduranceDrain,
        startFuel = state.fuel,
        startZone = Metabolism.getFuelZone(state.fuel),
        startWeightKg = state.weightKg,
        endFuel = state.fuel,
        endZone = Metabolism.getFuelZone(state.fuel),
        endWeightKg = state.weightKg,
        startWeightBalanceKcal = tonumber(state.weightBalanceKcal) or 0,
        endWeightBalanceKcal = tonumber(state.weightBalanceKcal) or 0,
        burnedKcal = 0,
        visibleHungerGain = 0,
        startVisibleHunger = state.visibleHunger,
        endVisibleHunger = state.visibleHunger,
        peakFuelPressureFactor = Metabolism.getFuelPressureFactor(state.fuel),
        peakGateMultiplier = Metabolism.getHungerGateMultiplier(state.fuel),
        peakMetHungerFactor = Metabolism.getMetHungerFactor(normalizedWorkload),
        peakEnergyAppetiteProgress = Metabolism.getEnergyAppetiteProgress(state.weightBalanceKcal),
        peakEnergyAppetiteRatePerHour = 0,
        hungerBand = Metabolism.getVisibleHungerBand(state.visibleHunger),
        extraEnduranceDrain = 0,
        weightDeltaKg = 0,
        weightRateKgPerWeek = tonumber(options and options.previousWeightRateKgPerWeek) or 0,
        startWeightTrait = Metabolism.getWeightTrait(state.weightKg),
        endWeightTrait = Metabolism.getWeightTrait(state.weightKg),
        startDeprivationTarget = Metabolism.getDeprivationTarget(state),
        endDeprivationTarget = Metabolism.getDeprivationTarget(state),
        peakWeightController = math.abs(state.weightController or 0),
        burnWeightFactor = Metabolism.getWeightFuelBurnFactor(state.weightKg),
        peakProteinDeficiency = Metabolism.getProteinDeficiencyProgress(state.proteins, state.weightKg),
        startProteinHealingMultiplier = Metabolism.getProteinHealingMultiplier(state.proteins, state.weightKg),
        endProteinHealingMultiplier = Metabolism.getProteinHealingMultiplier(state.proteins, state.weightKg),
        traitSatietyDecayMultiplier = traitEffects.satietyDecayMultiplier,
        traitBurnMultiplier = traitEffects.burnMultiplier,
        traitWeightGainMultiplier = traitEffects.weightGainMultiplier,
        traitWeightLossMultiplier = traitEffects.weightLossMultiplier,
        hungerRateMultiplier = hungerRateMultiplier,
        statsDecreaseMultiplier = statsDecreaseMultiplier,
        appetiteRateMultiplier = appetiteRateMultiplier,
        energyBurnMultiplier = energyBurnMultiplier,
        startSatietyBuffer = state.satietyBuffer,
        endSatietyBuffer = state.satietyBuffer,
        satietyReturnFactor = Metabolism.getSatietyReturnFactor(state.satietyBuffer),
        slices = 0,
        reason = tostring(options and options.reason or normalizedWorkload.workTier or "advance"),
    }

    if totalHours <= 0 then
        return report
    end

    local slices = math.max(1, math.ceil(totalHours / 0.25))
    local sliceHours = totalHours / slices
    local burnPerHour = Metabolism.getFuelBurnPerHourFromMet(normalizedWorkload, state.weightKg, traitEffects)
    local proteinRequirementPerHour = Metabolism.getProteinRequirementPerHour(state.weightKg)
    local burnKcalOverride = tonumber(options and options.burnKcalOverride)
    if burnKcalOverride ~= nil and totalHours > 0 then
        burnPerHour = math.max(0, burnKcalOverride) / totalHours
    end
    burnPerHour = burnPerHour * energyBurnMultiplier
    report.extraEnduranceDrain = math.max(0, normalizedWorkload.appliedEnduranceDrain or 0)

    report.slices = slices
    local satietyReturnFactorAccum = 0

    for _ = 1, slices do
        local hungerRate = Metabolism.getPassiveVisibleHungerRatePerHour(
            state,
            normalizedWorkload,
            traitEffects,
            hungerRateMultiplier
        )
        local hungerGain = hungerRate.ratePerHour * sliceHours
        satietyReturnFactorAccum = satietyReturnFactorAccum + (hungerRate.satietyBandFactor * sliceHours)
        report.visibleHungerGain = report.visibleHungerGain + hungerGain
        report.peakFuelPressureFactor = math.max(report.peakFuelPressureFactor, hungerRate.fuelPressureFactor)
        report.peakGateMultiplier = math.max(report.peakGateMultiplier, hungerRate.gateMultiplier)
        report.peakMetHungerFactor = math.max(report.peakMetHungerFactor, hungerRate.metHungerFactor)
        report.peakEnergyAppetiteProgress = math.max(report.peakEnergyAppetiteProgress, hungerRate.energyAppetiteProgress)
        report.peakEnergyAppetiteRatePerHour = math.max(report.peakEnergyAppetiteRatePerHour, hungerRate.energyAppetiteRatePerHour)
        report.hungerBand = hungerRate.band
        state.visibleHunger = clamp(state.visibleHunger + hungerGain, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_CAP)
        report.endVisibleHunger = state.visibleHunger

        local metabolicBurn = burnPerHour * sliceHours
        local fuelBurn = math.min(state.fuel, metabolicBurn)
        state.fuel = clamp(state.fuel - fuelBurn, Metabolism.FUEL_MIN, Metabolism.FUEL_MAX)
        state.weightBalanceKcal = Metabolism.advanceWeightBalanceKcal(state.weightBalanceKcal, -metabolicBurn, sliceHours)
        state.proteins = clampProteinAdequacy(state.proteins - (proteinRequirementPerHour * sliceHours), state.weightKg)
        report.burnedKcal = report.burnedKcal + metabolicBurn

        local proteinDeficiency = Metabolism.getProteinDeficiencyProgress(state.proteins, state.weightKg)
        report.peakProteinDeficiency = math.max(report.peakProteinDeficiency, proteinDeficiency)

        local weightTarget = Metabolism.getWeightControllerTargetFromBalance(state.weightBalanceKcal)
        state.weightController = approach(
            state.weightController,
            weightTarget,
            sliceHours / Metabolism.WEIGHT_CONTROLLER_RESPONSE_HOURS
        )
        report.peakWeightController = math.max(report.peakWeightController, math.abs(state.weightController))

        state.deprivation = Metabolism.advanceDeprivation(state.deprivation, state.weightBalanceKcal, sliceHours)
        report.peakDeprivation = math.max(report.peakDeprivation or 0, state.deprivation)
        report.endDeprivationTarget = Metabolism.getDeprivationTarget(state)

        local weightBefore = state.weightKg
        local weightRatePerHour = 0
        if state.weightController > 0 then
            weightRatePerHour = Metabolism.WEIGHT_MAX_GAIN_RATE_KG_PER_HOUR * state.weightController
            weightRatePerHour = weightRatePerHour * traitEffects.weightGainMultiplier
        elseif state.weightController < 0 then
            weightRatePerHour = Metabolism.WEIGHT_MAX_LOSS_RATE_KG_PER_HOUR * state.weightController
            weightRatePerHour = weightRatePerHour * traitEffects.weightLossMultiplier
        end
        state.weightKg = clamp(
            state.weightKg + (weightRatePerHour * sliceHours),
            Metabolism.WEIGHT_MIN_KG,
            Metabolism.WEIGHT_MAX_KG
        )
        report.weightDeltaKg = report.weightDeltaKg + (state.weightKg - weightBefore)

        state.satietyBuffer = clamp(
            state.satietyBuffer - (Metabolism.SATIETY_BUFFER_DECAY_PER_HOUR * traitEffects.satietyDecayMultiplier * sliceHours),
            0,
            Metabolism.SATIETY_BUFFER_MAX
        )
    end

    report.endFuel = state.fuel
    report.endZone = Metabolism.getFuelZone(state.fuel)
    report.endWeightKg = state.weightKg
    report.endWeightBalanceKcal = tonumber(state.weightBalanceKcal) or 0
    report.endWeightTrait = Metabolism.getWeightTrait(state.weightKg)
    report.endDeprivationTarget = Metabolism.getDeprivationTarget(state)
    report.endProteinHealingMultiplier = Metabolism.getProteinHealingMultiplier(state.proteins, state.weightKg)
    report.endSatietyBuffer = state.satietyBuffer
    if totalHours > 0 then
        report.weightRateKgPerWeek = report.weightDeltaKg / totalHours * 24 * 7
        report.satietyReturnFactor = satietyReturnFactorAccum / totalHours
    end

    return report
end

return Metabolism
