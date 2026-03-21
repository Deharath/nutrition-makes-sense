NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.SimRunner = NutritionMakesSense.SimRunner or {}

local SimRunner = NutritionMakesSense.SimRunner
local Metabolism = NutritionMakesSense.Metabolism or {}

local SIM_DURATION_HOURS = 24
local SIM_STEP_HOURS = 0.25

local function clamp(value, minValue, maxValue)
    return Metabolism.clamp(value, minValue, maxValue)
end

local function cloneTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            copy[key] = cloneTable(value)
        else
            copy[key] = value
        end
    end
    return copy
end

local function makeDefaultState()
    return Metabolism.newState({
        initialized = true,
        fuel = Metabolism.DEFAULT_FUEL,
        proteins = Metabolism.DEFAULT_PROTEIN,
        weightKg = Metabolism.DEFAULT_WEIGHT_KG,
        weightController = 0,
        deprivation = 0,
        satietyBuffer = 0,
        visibleHunger = 0.03,
        hunger = 0.03,
    })
end

local function compareHours(a, b)
    return (tonumber(a) or 0) < (tonumber(b) or 0)
end

local function formatHour(hour)
    local totalMinutes = math.floor(((tonumber(hour) or 0) * 60) + 0.5)
    local hh = math.floor(totalMinutes / 60)
    local mm = totalMinutes % 60
    return string.format("%02d:%02d", hh, mm)
end

local function getWorkloadForHour(profile, hour)
    for _, segment in ipairs(profile.workload or {}) do
        if hour >= (tonumber(segment.startHour) or 0) and hour < (tonumber(segment.endHour) or 0) then
            return {
                averageMet = tonumber(segment.averageMet) or Metabolism.MET_REST,
                peakMet = tonumber(segment.peakMet) or tonumber(segment.averageMet) or Metabolism.MET_REST,
                observedHours = SIM_STEP_HOURS,
                heavyHours = (tonumber(segment.averageMet) or 0) >= Metabolism.MET_HEAVY_THRESHOLD and SIM_STEP_HOURS or 0,
                veryHeavyHours = (tonumber(segment.averageMet) or 0) >= Metabolism.MET_VERY_HEAVY_THRESHOLD and SIM_STEP_HOURS or 0,
                source = tostring(segment.source or "sim"),
                sleepObserved = segment.sleepObserved == true,
            }
        end
    end

    return {
        averageMet = Metabolism.MET_REST,
        peakMet = Metabolism.MET_REST,
        observedHours = SIM_STEP_HOURS,
        heavyHours = 0,
        veryHeavyHours = 0,
        source = "sim-fallback",
        sleepObserved = false,
    }
end

local function sortedMeals(profile)
    local meals = cloneTable(profile.meals or {})
    table.sort(meals, function(a, b)
        return compareHours(a.hour, b.hour)
    end)
    return meals
end

local function markFirst(summary, key, condition, hour)
    if summary[key] == nil and condition then
        summary[key] = hour
    end
end

local function updateSummary(summary, state, report, hour)
    local hunger = tonumber(state.visibleHunger) or 0
    local fuel = tonumber(state.fuel) or 0
    local deprivation = tonumber(state.deprivation) or 0
    local zone = tostring(state.lastZone or Metabolism.getFuelZone(fuel))

    summary.lowestFuel = math.min(summary.lowestFuel, fuel)
    summary.highestDeprivation = math.max(summary.highestDeprivation, deprivation)
    summary.highestHunger = math.max(summary.highestHunger, hunger)
    summary.lastZone = zone
    summary.totalBurnKcal = summary.totalBurnKcal + (tonumber(report and report.burnedKcal) or 0)

    markFirst(summary, "firstLowHour", zone == "Low" or zone == "Penalty", hour)
    markFirst(summary, "firstPenaltyHour", zone == "Penalty", hour)
    markFirst(summary, "firstDeprivationHour", deprivation >= 0.10, hour)
    markFirst(summary, "firstPeckishHour", hunger >= Metabolism.HUNGER_THRESHOLD_PECKISH, hour)
    markFirst(summary, "firstHungryHour", hunger >= Metabolism.HUNGER_THRESHOLD_HUNGRY, hour)
end

local function makeProfiles()
    return {
        {
            id = "recording_like",
            label = "Recording-Like Day",
            description = "Sedentary-to-light day with snack gap and late dense meal.",
            meals = {
                { hour = 0.0, label = "Omelette", hunger = -16, kcal = 391, carbs = 6, fats = 28, proteins = 24 },
                { hour = 3.5, label = "Ice Cream", hunger = -8, kcal = 190, carbs = 24, fats = 9, proteins = 3 },
                { hour = 10.9, label = "Stew 1", hunger = -16, kcal = 430, carbs = 30, fats = 18, proteins = 35 },
                { hour = 11.0, label = "Stew 2", hunger = -16, kcal = 430, carbs = 30, fats = 18, proteins = 35 },
                { hour = 18.0, label = "Sandwich", hunger = -28, kcal = 1141, carbs = 88, fats = 52, proteins = 44 },
            },
            workload = {
                { startHour = 0.0, endHour = 7.0, averageMet = 1.0, peakMet = 1.1, source = "rest" },
                { startHour = 7.0, endHour = 10.0, averageMet = 2.4, peakMet = 3.1, source = "light_outing" },
                { startHour = 10.0, endHour = 17.0, averageMet = 1.1, peakMet = 1.3, source = "rest" },
                { startHour = 17.0, endHour = 19.5, averageMet = 2.1, peakMet = 3.1, source = "walk" },
                { startHour = 19.5, endHour = 24.0, averageMet = 1.0, peakMet = 1.1, source = "rest" },
            },
        },
        {
            id = "scavenge_day",
            label = "Scavenge Day",
            description = "Mostly walking with one moderate work block and normal meals.",
            meals = {
                { hour = 0.0, label = "Breakfast", hunger = -16, kcal = 520, carbs = 48, fats = 18, proteins = 28 },
                { hour = 6.0, label = "Lunch", hunger = -18, kcal = 640, carbs = 62, fats = 22, proteins = 34 },
                { hour = 13.0, label = "Dinner", hunger = -22, kcal = 760, carbs = 56, fats = 30, proteins = 42 },
            },
            workload = {
                { startHour = 0.0, endHour = 2.0, averageMet = 1.0, peakMet = 1.1, source = "rest" },
                { startHour = 2.0, endHour = 8.0, averageMet = 3.1, peakMet = 3.4, source = "walk" },
                { startHour = 8.0, endHour = 11.0, averageMet = 4.0, peakMet = 4.8, source = "loot" },
                { startHour = 11.0, endHour = 17.0, averageMet = 3.0, peakMet = 3.3, source = "walk" },
                { startHour = 17.0, endHour = 24.0, averageMet = 1.0, peakMet = 1.1, source = "rest" },
            },
        },
        {
            id = "labor_day",
            label = "Labor Day",
            description = "Heavy labor blocks with three square meals.",
            meals = {
                { hour = 0.0, label = "Breakfast", hunger = -18, kcal = 700, carbs = 65, fats = 24, proteins = 32 },
                { hour = 5.5, label = "Lunch", hunger = -20, kcal = 820, carbs = 72, fats = 28, proteins = 40 },
                { hour = 12.0, label = "Dinner", hunger = -24, kcal = 920, carbs = 78, fats = 34, proteins = 48 },
            },
            workload = {
                { startHour = 0.0, endHour = 1.5, averageMet = 1.0, peakMet = 1.1, source = "rest" },
                { startHour = 1.5, endHour = 6.5, averageMet = 5.0, peakMet = 6.0, source = "heavy_work" },
                { startHour = 6.5, endHour = 9.5, averageMet = 2.3, peakMet = 3.1, source = "walk" },
                { startHour = 9.5, endHour = 14.5, averageMet = 5.2, peakMet = 6.2, source = "heavy_work" },
                { startHour = 14.5, endHour = 24.0, averageMet = 1.0, peakMet = 1.1, source = "rest" },
            },
        },
    }
end

SimRunner.PROFILES = makeProfiles()

function SimRunner.getProfiles()
    return cloneTable(SimRunner.PROFILES)
end

function SimRunner.runProfile(profileId, initialState)
    local profile = nil
    for _, candidate in ipairs(SimRunner.PROFILES) do
        if candidate.id == profileId then
            profile = candidate
            break
        end
    end
    if not profile then
        return nil, "unknown profile"
    end

    local state = Metabolism.copyState(initialState or makeDefaultState())
    state.initialized = true
    local summary = {
        profileId = profile.id,
        label = profile.label,
        description = profile.description,
        startFuel = tonumber(state.fuel) or 0,
        startWeightKg = tonumber(state.weightKg) or 0,
        startHunger = tonumber(state.visibleHunger) or 0,
        lowestFuel = tonumber(state.fuel) or 0,
        highestDeprivation = tonumber(state.deprivation) or 0,
        highestHunger = tonumber(state.visibleHunger) or 0,
        totalBurnKcal = 0,
        totalDepositKcal = 0,
        deposits = {},
    }

    local meals = sortedMeals(profile)
    local mealIndex = 1
    local steps = math.floor(SIM_DURATION_HOURS / SIM_STEP_HOURS)

    for step = 1, steps do
        local hour = (step - 1) * SIM_STEP_HOURS

        while meals[mealIndex] and hour >= (tonumber(meals[mealIndex].hour) or 0) do
            local meal = meals[mealIndex]
            local report = Metabolism.applyFoodValues(state, meal, 1, "sim-" .. tostring(meal.label or mealIndex))
            summary.totalDepositKcal = summary.totalDepositKcal + (tonumber(report and report.kcal) or 0)
            summary.deposits[#summary.deposits + 1] = {
                hour = tonumber(meal.hour) or 0,
                label = tostring(meal.label or ("Meal " .. tostring(mealIndex))),
                kcal = tonumber(meal.kcal) or 0,
            }
            mealIndex = mealIndex + 1
        end

        local workload = getWorkloadForHour(profile, hour)
        local report = Metabolism.advanceState(state, SIM_STEP_HOURS, workload, { reason = "sim-" .. tostring(profile.id) })
        updateSummary(summary, state, report, hour + SIM_STEP_HOURS)
    end

    summary.endFuel = tonumber(state.fuel) or 0
    summary.endWeightKg = tonumber(state.weightKg) or 0
    summary.endHunger = tonumber(state.visibleHunger) or 0
    summary.endDeprivation = tonumber(state.deprivation) or 0
    summary.endZone = tostring(state.lastZone or Metabolism.getFuelZone(state.fuel))
    summary.weightDeltaKg = summary.endWeightKg - summary.startWeightKg
    summary.weightRateKgPerWeek = tonumber(state.lastWeightRateKgPerWeek) or 0
    summary.finalState = Metabolism.copyState(state)
    summary.firstLowLabel = summary.firstLowHour and formatHour(summary.firstLowHour) or "--"
    summary.firstPenaltyLabel = summary.firstPenaltyHour and formatHour(summary.firstPenaltyHour) or "--"
    summary.firstDeprivationLabel = summary.firstDeprivationHour and formatHour(summary.firstDeprivationHour) or "--"
    summary.firstPeckishLabel = summary.firstPeckishHour and formatHour(summary.firstPeckishHour) or "--"
    summary.firstHungryLabel = summary.firstHungryHour and formatHour(summary.firstHungryHour) or "--"

    return summary
end

return SimRunner
