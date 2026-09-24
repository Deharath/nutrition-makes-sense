NutritionMakesSense = NutritionMakesSense or {}

-- Pure NMS 2.0 model. No PZ API access; the runtime feeds observations in and writes results out.
-- Vanilla owns every persistent value (calories, macros, weight, hunger, Well Fed timer);
-- NMS only decides how those values move between ticks.
local Model = {}
NutritionMakesSense.Model = Model

Model.CALORIES_MIN = -2200
Model.CALORIES_MAX = 3700
Model.WEIGHT_MIN_KG = 35
Model.WEIGHT_MAX_KG = 150
Model.DEFAULT_WEIGHT_KG = 80

Model.MET_REST = 1.0
Model.MET_SLEEP = 0.8
Model.MET_MAX = 12.0
Model.REST_BURN_PER_HOUR = 75
Model.BURN_PER_MET_PER_HOUR = 48
Model.SLEEP_BURN_PER_HOUR = 35

-- Energy reserve band (vanilla calorie counter). Inside the band nothing converts to or from fat.
Model.RESERVE_SET_POINT = 800
Model.RESERVE_LOWER = 300
Model.RESERVE_UPPER = 1300
Model.STORE_RATE_PER_HOUR = 1 / 12
Model.MOBILIZE_RATE_PER_HOUR = 1 / 8
Model.MOBILIZE_CAP_PER_HOUR = 75
Model.MOBILIZE_LEAN_KG = 45
Model.MOBILIZE_FULL_KG = 75
Model.KCAL_PER_KG = 7700

-- Stomach = vanilla Well Fed timer, re-clocked to game hours.
-- Vanilla moodle bands: >0 Satiated, >1600 Well Fed, >3200 Stuffed (eating blocked), >4800 Full to Bursting.
Model.STOMACH_UNITS_PER_HOUR = 1000
Model.STOMACH_CAP = 5000
Model.STOMACH_SATIATED = 0
Model.STOMACH_WELL_FED = 1600
Model.STOMACH_STUFFED = 3200
Model.STOMACH_BURSTING = 4800
Model.FILL_KCAL_PER_HOUR = 250
Model.FILL_QUALITY_MIN = 0.75
Model.FILL_QUALITY_MAX = 1.30
Model.WELL_FED_HEALING = 0.001

Model.HUNGER_BASE_PER_HOUR = 0.07
-- Share of vanilla's eat-time hunger drop that is kept. Item HungerChange stays untouched because it is also
-- the portion reservoir (Eat Half/Quarter gating, evolved recipe ingredient use); NMS scales the applied drop.
Model.HUNGER_DROP_SCALE = 0.7
Model.HUNGER_SLEEP_FACTOR = 0.15
Model.HUNGER_TRAIT_HEARTY = 1.5
Model.HUNGER_TRAIT_LIGHT = 0.75

Model.APPETITE_CURVE = {
    { -2200, 2.2 },
    { -800, 1.7 },
    { 300, 1.15 },
    { 800, 1.0 },
    { 1300, 0.85 },
    { 2200, 0.55 },
    { 3700, 0.4 },
}

Model.MALNUTRITION_CALORIE_ONSET = 0
Model.MALNUTRITION_CALORIE_FULL = -1500
Model.MALNUTRITION_PROTEIN_ONSET = -300
Model.MALNUTRITION_PROTEIN_FULL = -500
Model.MALNUTRITION_PROTEIN_MAX = 0.5
Model.PROTEIN_LOW_WARNING = -100
Model.MALNUTRITION_RISE_HOURS = 48
Model.MALNUTRITION_RECOVERY_HOURS = 36
Model.MALNUTRITION_ENDURANCE_ONSET = 0.15
Model.MALNUTRITION_REGEN_SCALE_MIN = 0.55
Model.MALNUTRITION_ACTIVITY_DRAIN_MAX = 0.012
Model.MALNUTRITION_RECOVERY_PENALTY_MAX = 0.5

Model.TRAIT_BURN_FAST = 1.04
Model.TRAIT_BURN_SLOW = 0.96
Model.TRAIT_GAIN_FAST = 0.90
Model.TRAIT_GAIN_SLOW = 1.12
Model.TRAIT_LOSS_FAST = 1.12
Model.TRAIT_LOSS_SLOW = 0.90

-- Observation thresholds used to separate vanilla drift from real events.
Model.INTAKE_EPSILON_KCAL = 0.5
Model.HUNGER_DROP_EPSILON = 0.0005
Model.HUNGER_EXTERNAL_RISE = 0.02
Model.STOMACH_EXTERNAL_RISE = 1
Model.WEIGHT_EXTERNAL_KG = 0.2
Model.VANILLA_BURN_DEFAULT_PER_HOUR = 60
Model.VANILLA_BURN_SMOOTHING = 0.2
Model.VANILLA_BURN_MAX_PER_HOUR = 800

-- Vanilla moodle/trait thresholds used by forecasts and UI.
Model.HUNGER_PECKISH = 0.15
Model.HUNGER_HUNGRY = 0.25
Model.HUNGER_VERY_HUNGRY = 0.45
Model.HUNGER_STARVING = 0.70
Model.VANILLA_PROTEIN_DECAY_PER_DAY = 8.6e-4 * 86400
Model.MALNOURISHED_LEVELS = { 0.10, 0.30, 0.60, 0.85 }
Model.WEIGHT_TRAIT_BOUNDS = { 50, 65, 75, 85, 100 }

local function clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end
Model.clamp = clamp

local function piecewise(curve, x)
    if x <= curve[1][1] then
        return curve[1][2]
    end
    for i = 2, #curve do
        local x1, y1 = curve[i][1], curve[i][2]
        if x <= x1 then
            local x0, y0 = curve[i - 1][1], curve[i - 1][2]
            return y0 + (y1 - y0) * ((x - x0) / (x1 - x0))
        end
    end
    return curve[#curve][2]
end

function Model.normalizeTraits(traits)
    local t = type(traits) == "table" and traits or {}
    return {
        fastMetabolism = t.fastMetabolism == true,
        slowMetabolism = t.slowMetabolism == true,
        heartyAppetite = t.heartyAppetite == true,
        lightEater = t.lightEater == true,
    }
end

function Model.burnPerHour(met, asleep, weightKg, traits, burnMultiplier)
    local t = Model.normalizeTraits(traits)
    local weight = clamp(tonumber(weightKg) or Model.DEFAULT_WEIGHT_KG, Model.WEIGHT_MIN_KG, Model.WEIGHT_MAX_KG)
    local weightFactor = clamp(1 + (weight - 80) * 0.0025, 0.9, 1.1)
    local traitFactor = (t.fastMetabolism and Model.TRAIT_BURN_FAST) or (t.slowMetabolism and Model.TRAIT_BURN_SLOW) or 1
    local base
    if asleep then
        base = Model.SLEEP_BURN_PER_HOUR
    else
        local m = clamp(tonumber(met) or Model.MET_REST, 0, Model.MET_MAX)
        base = Model.REST_BURN_PER_HOUR + Model.BURN_PER_MET_PER_HOUR * math.max(0, m - Model.MET_REST)
    end
    return base * weightFactor * traitFactor * (tonumber(burnMultiplier) or 1)
end

-- Satiety duration from energy and composition. Volume is vanilla's immediate hunger drop.
function Model.fillQuality(kcal, fats, proteins)
    local energy = math.max(1, tonumber(kcal) or 0)
    local proteinShare = clamp(4 * math.max(0, tonumber(proteins) or 0) / energy, 0, 1)
    local fatShare = clamp(9 * math.max(0, tonumber(fats) or 0) / energy, 0, 1)
    return clamp(0.75 + 0.6 * proteinShare + 0.35 * fatShare, Model.FILL_QUALITY_MIN, Model.FILL_QUALITY_MAX)
end

function Model.fillHours(kcal, fats, proteins)
    local energy = tonumber(kcal) or 0
    if energy <= 0 then
        return 0
    end
    return (energy / Model.FILL_KCAL_PER_HOUR) * Model.fillQuality(energy, fats, proteins)
end

function Model.stomachLevel(timer)
    local t = tonumber(timer) or 0
    if t > Model.STOMACH_BURSTING then return 4 end
    if t > Model.STOMACH_STUFFED then return 3 end
    if t > Model.STOMACH_WELL_FED then return 2 end
    if t > Model.STOMACH_SATIATED then return 1 end
    return 0
end

-- Hunger returns gradually while the stomach empties instead of snapping back when the timer hits 0.
function Model.stomachHungerFactor(timer)
    return clamp(1 - (tonumber(timer) or 0) / Model.STOMACH_WELL_FED, 0, 1)
end

function Model.appetite(calories)
    return piecewise(Model.APPETITE_CURVE, tonumber(calories) or Model.RESERVE_SET_POINT)
end

function Model.hungerRatePerHour(hunger, calories, timer, asleep, traits, appetiteMultiplier)
    local t = Model.normalizeTraits(traits)
    local h = clamp(tonumber(hunger) or 0, 0, 1)
    local traitFactor = (t.heartyAppetite and Model.HUNGER_TRAIT_HEARTY) or (t.lightEater and Model.HUNGER_TRAIT_LIGHT) or 1
    local sleepFactor = asleep and Model.HUNGER_SLEEP_FACTOR or 1
    return Model.HUNGER_BASE_PER_HOUR
        * (1 - h) * (1 - h)
        * Model.appetite(calories)
        * Model.stomachHungerFactor(timer)
        * sleepFactor
        * traitFactor
        * (tonumber(appetiteMultiplier) or 1)
end

local function mobilizeCapacityPerHour(weightKg)
    local progress = clamp((weightKg - Model.MOBILIZE_LEAN_KG) / (Model.MOBILIZE_FULL_KG - Model.MOBILIZE_LEAN_KG), 0, 1)
    return Model.MOBILIZE_CAP_PER_HOUR * progress
end
Model.mobilizeCapacityPerHour = mobilizeCapacityPerHour

-- Energy <-> fat exchange outside the reserve band. Returns calorie delta and weight delta for dt.
function Model.storageFlux(calories, weightKg, traits, dtHours)
    local t = Model.normalizeTraits(traits)
    local dt = math.max(0, tonumber(dtHours) or 0)
    local c = tonumber(calories) or Model.RESERVE_SET_POINT
    local w = tonumber(weightKg) or Model.DEFAULT_WEIGHT_KG
    if dt <= 0 then
        return 0, 0
    end
    if c > Model.RESERVE_UPPER then
        local stored = math.min(c - Model.RESERVE_UPPER, (c - Model.RESERVE_UPPER) * Model.STORE_RATE_PER_HOUR * dt)
        local gain = (t.fastMetabolism and Model.TRAIT_GAIN_FAST) or (t.slowMetabolism and Model.TRAIT_GAIN_SLOW) or 1
        return -stored, (stored / Model.KCAL_PER_KG) * gain
    end
    if c < Model.RESERVE_LOWER then
        local wanted = (Model.RESERVE_LOWER - c) * Model.MOBILIZE_RATE_PER_HOUR
        local rate = math.min(wanted, mobilizeCapacityPerHour(w))
        local released = math.min(Model.RESERVE_LOWER - c, rate * dt)
        local loss = (t.fastMetabolism and Model.TRAIT_LOSS_FAST) or (t.slowMetabolism and Model.TRAIT_LOSS_SLOW) or 1
        return released, -(released / Model.KCAL_PER_KG) * loss
    end
    return 0, 0
end

function Model.malnutritionTargets(calories, proteins)
    local c = tonumber(calories) or Model.RESERVE_SET_POINT
    local p = tonumber(proteins) or 0
    local calorie = clamp(
        (Model.MALNUTRITION_CALORIE_ONSET - c) / (Model.MALNUTRITION_CALORIE_ONSET - Model.MALNUTRITION_CALORIE_FULL),
        0, 1)
    local protein = clamp(
        (Model.MALNUTRITION_PROTEIN_ONSET - p) / (Model.MALNUTRITION_PROTEIN_ONSET - Model.MALNUTRITION_PROTEIN_FULL),
        0, 1) * Model.MALNUTRITION_PROTEIN_MAX
    local combined = 1 - (1 - calorie) * (1 - protein)
    return combined, calorie, protein
end

function Model.advanceMalnutrition(current, target, dtHours)
    local m = clamp(tonumber(current) or 0, 0, 1)
    local goal = clamp(tonumber(target) or 0, 0, 1)
    local hours = goal > m and Model.MALNUTRITION_RISE_HOURS or Model.MALNUTRITION_RECOVERY_HOURS
    local fraction = clamp((tonumber(dtHours) or 0) / hours, 0, 1)
    return m + (goal - m) * fraction
end

-- Cause label for UI: "calories", "protein", "both", or nil.
function Model.malnutritionCause(calorieTarget, proteinTarget)
    local c = tonumber(calorieTarget) or 0
    local p = tonumber(proteinTarget) or 0
    if c <= 0.01 and p <= 0.01 then
        return nil
    end
    if c > 0.01 and p > 0.01 then
        return "both"
    end
    return c > p and "calories" or "protein"
end

local function malnutritionProgress(m)
    local onset = Model.MALNUTRITION_ENDURANCE_ONSET
    return clamp(((tonumber(m) or 0) - onset) / (1 - onset), 0, 1)
end

function Model.enduranceRegenScale(m)
    return 1 + (Model.MALNUTRITION_REGEN_SCALE_MIN - 1) * malnutritionProgress(m)
end

function Model.enduranceActivityDrainPerHour(m, met)
    local activity = clamp(((tonumber(met) or Model.MET_REST) - Model.MET_REST) / (6.0 - Model.MET_REST), 0, 1)
    return Model.MALNUTRITION_ACTIVITY_DRAIN_MAX * malnutritionProgress(m) * activity
end

-- "Depleted" | "Low" | "Ready" | "Stored" for the vanilla calorie reserve.
function Model.reserveZone(calories)
    local c = tonumber(calories) or Model.RESERVE_SET_POINT
    if c < 0 then return "Depleted" end
    if c < Model.RESERVE_LOWER then return "Low" end
    if c <= Model.RESERVE_UPPER then return "Ready" end
    return "Stored"
end

Model.LEGACY_FUEL_CURVE = {
    { 0, -1500 },
    { 200, 0 },
    { 550, 300 },
    { 1500, 1300 },
    { 2000, 2000 },
}

function Model.legacyFuelToCalories(fuel)
    return piecewise(Model.LEGACY_FUEL_CURVE, tonumber(fuel) or 800)
end

function Model.naturalRecoveryMultiplier(m)
    return 1 - Model.MALNUTRITION_RECOVERY_PENALTY_MAX * malnutritionProgress(m)
end

function Model.wellFedHealing(m)
    return Model.WELL_FED_HEALING * (1 - clamp(tonumber(m) or 0, 0, 1))
end

local function vanillaHungerRiseCeiling(hunger, dtHours)
    -- Upper bound on what vanilla can add on its own (0.035/h * Hearty 1.5 * generous sandbox 2).
    return 0.105 * (1 - clamp(hunger, 0, 1)) * dtHours
end

--[[
One authority tick.
prev: values NMS wrote last tick {calories, hunger, timer, weight}
obs:  values read now {calories, hunger, timer, weight, fats, proteins (macro deltas since prev as fatsIn/proteinsIn)}
ctx:  {dtHours, met, asleep, traits, burnMultiplier, appetiteMultiplier, vanillaBurnPerHour}
Returns next values plus event info. The runtime writes next.* into vanilla.
]]
function Model.step(prev, obs, ctx)
    local dt = math.max(0, tonumber(ctx.dtHours) or 0)
    local traits = Model.normalizeTraits(ctx.traits)
    local out = {}

    local vanillaBurn = tonumber(ctx.vanillaBurnPerHour) or Model.VANILLA_BURN_DEFAULT_PER_HOUR
    local rawCalories = obs.calories - prev.calories
    local intake = 0
    if rawCalories > Model.INTAKE_EPSILON_KCAL then
        intake = rawCalories + vanillaBurn * dt
    elseif dt > 0 then
        local observedBurn = -rawCalories / dt
        if observedBurn >= 0 and observedBurn <= Model.VANILLA_BURN_MAX_PER_HOUR then
            vanillaBurn = vanillaBurn + (observedBurn - vanillaBurn) * Model.VANILLA_BURN_SMOOTHING
        end
    end
    out.vanillaBurnPerHour = vanillaBurn
    out.intakeKcal = intake

    local rawWeight = obs.weight - prev.weight
    local weightBase = math.abs(rawWeight) > Model.WEIGHT_EXTERNAL_KG and obs.weight or prev.weight
    out.externalWeight = weightBase == obs.weight and rawWeight ~= 0

    local burn = Model.burnPerHour(ctx.met, ctx.asleep, weightBase, traits, ctx.burnMultiplier)
    out.burnPerHour = burn
    local calories = prev.calories + intake - burn * dt
    local dC, dW = Model.storageFlux(calories, weightBase, traits, dt)
    calories = clamp(calories + dC, Model.CALORIES_MIN, Model.CALORIES_MAX)
    out.calories = calories
    out.weight = clamp(weightBase + dW, Model.WEIGHT_MIN_KG, Model.WEIGHT_MAX_KG)
    out.weightDelta = dW

    local rawTimer = obs.timer - prev.timer
    local timerBase = prev.timer
    if intake <= 0 and rawTimer > Model.STOMACH_EXTERNAL_RISE then
        timerBase = obs.timer
    end
    local fill = 0
    if intake > 0 then
        fill = Model.fillHours(intake, obs.fatsIn, obs.proteinsIn) * Model.STOMACH_UNITS_PER_HOUR
    end
    out.fill = fill
    local drained = math.max(0, timerBase - Model.STOMACH_UNITS_PER_HOUR * dt)
    out.timer = math.max(drained, math.min(Model.STOMACH_CAP, drained + fill))

    local rawHunger = obs.hunger - prev.hunger
    local hungerBase = prev.hunger
    if rawHunger < -Model.HUNGER_DROP_EPSILON then
        local keep = intake > 0 and Model.HUNGER_DROP_SCALE or 1
        hungerBase = clamp(prev.hunger + rawHunger * keep, 0, 1)
    elseif rawHunger > Model.HUNGER_EXTERNAL_RISE + 3 * vanillaHungerRiseCeiling(prev.hunger, dt) then
        hungerBase = obs.hunger
    end
    out.hungerDrop = prev.hunger - hungerBase
    out.hungerDropRaw = math.max(0, -rawHunger)
    local rate = Model.hungerRatePerHour(hungerBase, calories, out.timer, ctx.asleep, traits, ctx.appetiteMultiplier)
    out.hungerRatePerHour = rate
    out.hunger = clamp(hungerBase + rate * dt, 0, 1)

    return out
end

--[[
Forecast with no further eating at the current activity.
start: {calories, hunger, timer, weight}; ctx as for Model.step (dtHours ignored).
Returns hours until Hungry, reserve Low, reserve Depleted (0 = already there, nil = beyond horizon).
]]
function Model.forecast(start, ctx, horizonHours)
    local horizon = tonumber(horizonHours) or 48
    local step = 0.25
    local state = {
        calories = tonumber(start.calories) or Model.RESERVE_SET_POINT,
        hunger = tonumber(start.hunger) or 0,
        timer = tonumber(start.timer) or 0,
        weight = tonumber(start.weight) or Model.DEFAULT_WEIGHT_KG,
    }
    local result = {}
    local function mark(key, reached, t)
        if result[key] == nil and reached then
            result[key] = t
        end
    end
    local stepCtx = {
        dtHours = step,
        met = ctx.met,
        asleep = ctx.asleep,
        traits = ctx.traits,
        burnMultiplier = ctx.burnMultiplier,
        appetiteMultiplier = ctx.appetiteMultiplier,
        vanillaBurnPerHour = 0,
    }
    local t = 0
    while true do
        mark("hungryIn", state.hunger >= Model.HUNGER_HUNGRY, t)
        mark("lowIn", state.calories < Model.RESERVE_LOWER, t)
        mark("depletedIn", state.calories < 0, t)
        if t >= horizon or (result.hungryIn and result.lowIn and result.depletedIn) then
            break
        end
        local out = Model.step(state, state, stepCtx)
        state = { calories = out.calories, hunger = out.hunger, timer = out.timer, weight = out.weight }
        t = t + step
    end
    return result
end

-- Days until vanilla protein decay reaches the Low warning / deficiency onset (0 = already there).
function Model.proteinDaysLeft(proteins)
    local p = tonumber(proteins) or 0
    local rate = Model.VANILLA_PROTEIN_DECAY_PER_DAY
    return math.max(0, (p - Model.PROTEIN_LOW_WARNING) / rate),
        math.max(0, (p - Model.MALNUTRITION_PROTEIN_ONSET) / rate)
end

-- Hours for malnutrition to cross `level` while approaching `target`; nil when it never will.
function Model.malnutritionHoursTo(m, target, level)
    m = clamp(tonumber(m) or 0, 0, 1)
    target = clamp(tonumber(target) or 0, 0, 1)
    if target > m then
        if level <= m or level >= target then
            return nil
        end
        return Model.MALNUTRITION_RISE_HOURS * math.log((target - m) / (target - level))
    end
    if level >= m or level <= target then
        return nil
    end
    return Model.MALNUTRITION_RECOVERY_HOURS * math.log((m - target) / (level - target))
end

-- Weeks until the weight trend crosses the next vanilla trait boundary; returns weeks, boundary kg.
function Model.weightTraitWeeks(weightKg, trendKgPerWeek)
    local w = tonumber(weightKg) or Model.DEFAULT_WEIGHT_KG
    local trend = tonumber(trendKgPerWeek) or 0
    if math.abs(trend) < 0.05 then
        return nil, nil
    end
    local boundary = nil
    for _, b in ipairs(Model.WEIGHT_TRAIT_BOUNDS) do
        if trend < 0 and b < w then
            boundary = b
        elseif trend > 0 and b > w and not boundary then
            boundary = b
        end
    end
    if not boundary then
        return nil, nil
    end
    return math.abs(w - boundary) / math.abs(trend), boundary
end

return Model
