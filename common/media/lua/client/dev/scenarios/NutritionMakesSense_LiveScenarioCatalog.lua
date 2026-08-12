NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.LiveScenarioCatalog = NutritionMakesSense.LiveScenarioCatalog or {}

local Catalog = NutritionMakesSense.LiveScenarioCatalog
local Metabolism = NutritionMakesSense.Metabolism or {}
Catalog.DEFAULT_TIME_MULTIPLIER = 80

local function copyTable(source)
    if type(source) ~= "table" then
        return nil
    end
    local out = {}
    for key, value in pairs(source) do
        out[key] = value
    end
    return out
end

local DEFAULT_BASELINE_STATE = {
    fuel = 800,
    deprivation = 0,
    satietyBuffer = 0,
    proteins = Metabolism.DEFAULT_PROTEIN or 245,
    weightKg = Metabolism.DEFAULT_WEIGHT_KG or 80,
    weightController = 0,
}

local DEFAULT_BASELINE_VISIBLE = {
    hunger = 0.10,
    hungryMoodle = 0,
    thirst = 0.0,
    boredom = 0.0,
    foodSickness = 0.0,
    poison = 0.0,
    endurance = 1.0,
    fatigue = 0.0,
    healthFromFoodTimer = 0,
}

local CANONICAL_DAY_PHASES = {
    { label = "Morning", startHour = 0.0, endHour = 1.0, metabolics = "SedentaryActivity", averageMet = 1.2 },
    { label = "Work", startHour = 1.0, endHour = 5.0, metabolics = "MediumWork", averageMet = 3.9 },
    { label = "Calm Walk", startHour = 5.0, endHour = 6.0, metabolics = "Walking5kmh", averageMet = 3.1 },
    { label = "Work", startHour = 6.0, endHour = 9.0, metabolics = "MediumWork", averageMet = 3.9 },
    { label = "Leisure", startHour = 9.0, endHour = 11.0, metabolics = "SedentaryActivity", averageMet = 1.2 },
    { label = "More Work", startHour = 11.0, endHour = 12.5, metabolics = "UsingTools", averageMet = 2.5 },
    { label = "Evening Leisure", startHour = 12.5, endHour = 16.0, metabolics = "StandingAtRest", averageMet = 1.1 },
}

local function phase(label, startHour, endHour, metabolics, averageMet, options)
    local value = {
        label = label,
        startHour = startHour,
        endHour = endHour,
        metabolics = metabolics,
        averageMet = averageMet,
    }
    for key, optionValue in pairs(options or {}) do
        value[key] = optionValue
    end
    return value
end

local function food(fullType, label, prepared)
    local spec = {
        fullType = fullType,
        label = label,
    }
    if prepared ~= nil then
        spec.prepared = prepared
    end
    return spec
end

local function meal(id, label, atHour, items, tags)
    return {
        id = id,
        label = label,
        atHour = atHour,
        items = items,
        tags = tags,
    }
end

local function withProfileDefaults(profile)
    local normalized = copyTable(profile) or {}
    normalized.baseClockHour = tonumber(normalized.baseClockHour) or 6
    normalized.durationHours = tonumber(normalized.durationHours) or 16
    normalized.timeMultiplier = tonumber(normalized.timeMultiplier) or Catalog.DEFAULT_TIME_MULTIPLIER
    normalized.sortOrder = tonumber(normalized.sortOrder) or 100
    normalized.baselineState = normalized.baselineState or DEFAULT_BASELINE_STATE
    normalized.baselineVisible = normalized.baselineVisible or DEFAULT_BASELINE_VISIBLE
    return normalized
end

local LIVE_PROFILES = {
    recorded_exploration_day = withProfileDefaults({
        id = "recorded_exploration_day",
        label = "Recorded Exploration Autopilot",
        description = "Closed-loop wake, sleep, and post-wake response derived from the recorded 3055 kcal exploration day.",
        sortOrder = 5,
        durationHours = 20.334,
        consumptionMode = "signal_sequence",
        signalThreshold = "peckish",
        repeatSequenceOnSignal = true,
        minGapHours = 0.25,
        baselineState = {
            fuel = 1341,
            deprivation = 0,
            satietyBuffer = 0.05,
            proteins = 257,
            weightKg = 80,
            weightController = 0,
            weightBalanceKcal = 41,
        },
        baselineVisible = {
            hunger = 0.002,
            hungryMoodle = 0,
            thirst = 0.0,
            boredom = 0.0,
            foodSickness = 0.0,
            poison = 0.0,
            endurance = 1.0,
            fatigue = 0.0,
            healthFromFoodTimer = 0,
        },
        phases = {
            phase("Early Exploration", 0.000, 3.000, "MediumWork", 4.232),
            phase("Forest Travel", 3.000, 9.000, "MediumWork", 3.727),
            phase("Hard Exploration", 9.000, 12.000, "MediumWork", 3.975),
            phase("Wind-Down", 12.000, 13.830, "UsingTools", 2.512),
            phase("Recorded Sleep", 13.830, 19.834, "Sleeping", 0.807, {
                sleepObserved = true,
                allowEating = false,
                interruptibleForFood = false,
            }),
            phase("Post-Wake Response", 19.834, 20.334, "StandingAtRest", 1.1, {
                allowEating = true,
                postWakeResponse = true,
            }),
        },
        items = {
            food("Base.BellPepper", "Bell Pepper"),
            food("Base.CannedSardinesOpen", "Canned Sardines"),
            food("Base.Steak", "Steak", { cooked = true, heat = 1.8 }),
            food("Base.BeefJerky", "Beef Jerky"),
            food("Base.Sausage", "Sausage", { cooked = true, heat = 1.8 }),
            food("Base.Burger", "Burger"),
        },
        validation = {
            evaluator = "recorded_exploration_day",
            minimumItems = 9,
            maximumItems = 14,
            minimumIntakeBurnRatio = 0.70,
            maximumIntakeBurnRatio = 1.25,
            maximumAwakeHiddenDepletedStreakHours = 2.0,
            maximumDeprivation = 0.01,
            hungerDropThreshold = 0.01,
        },
    }),
    canonical_day = withProfileDefaults({
        id = "canonical_day",
        label = "Live Scripted Day",
        description = "Balanced hunger-driven meal sequence for broad live-runtime sanity.",
        sortOrder = 10,
        projectionDefaultMode = "style_repeat",
        projectionRepeatMeals = { "supper", "afternoon_snack" },
        projectionCueMeals = {
            peckish = { "supper" },
            hungry = { "supper" },
            very_hungry = { "supper" },
        },
        projectionCueWorkMeals = {
            peckish = { "afternoon_snack" },
            hungry = { "supper" },
            very_hungry = { "supper" },
        },
        consumptionMode = "signal_meals",
        signalThreshold = "peckish",
        minGapHours = 3.0,
        phases = CANONICAL_DAY_PHASES,
        meals = {
            meal("breakfast", "Breakfast", nil, {
                food("Base.CerealBowl", "Cereal Bowl"),
                food("Base.EggOmelette", "Egg Omelette"),
                food("Base.Banana", "Banana"),
            }),
            meal("lunch", "Lunch", nil, {
                food("Base.TVDinner", "TV Dinner", { cooked = true, heat = 1.8, cookedInMicrowave = true }),
                food("Base.Yoghurt", "Yoghurt"),
            }),
            meal("afternoon_snack", "Afternoon Snack", nil, {
                food("Base.GranolaBar", "Granola Bar"),
                food("Base.Apple", "Apple"),
                food("Base.Yoghurt", "Yoghurt"),
            }),
            meal("supper", "Supper", nil, {
                food("Base.Burger", "Burger"),
                food("Base.Yoghurt", "Yoghurt"),
            }),
        },
        validation = {
            evaluator = "canonical_day",
            hungerDropThreshold = 0.01,
            endFuelWarn = 350,
            endFuelFail = 200,
            deprivationWarn = 0.01,
        },
    }),
    junk_food_day = withProfileDefaults({
        id = "junk_food_day",
        label = "Junk Food Day",
        description = "Calorie-dense convenience food to check reserve stability versus weaker hunger control.",
        sortOrder = 20,
        projectionDefaultMode = "style_repeat",
        projectionCueItems = {
            peckish = {
                food("Base.Crisps", "Crisps"),
                food("Base.MuffinGeneric", "Muffin"),
                food("Base.IcecreamSandwich", "Ice Cream Sandwich"),
            },
            hungry = {
                food("Base.Hotdog", "Hot Dog"),
                food("Base.Crisps", "Crisps"),
                food("Base.Chocolate_Smirkers", "Chocolate Bar"),
            },
            very_hungry = {
                food("Base.Hotdog", "Hot Dog"),
                food("Base.Crisps", "Crisps"),
            },
        },
        consumptionMode = "signal_sequence",
        signalThreshold = "peckish",
        minGapHours = 0.5,
        phases = CANONICAL_DAY_PHASES,
        items = {
            food("Base.DoughnutFrosted", "Frosted Doughnut"),
            food("Base.Crisps", "Crisps"),
            food("Base.MuffinGeneric", "Muffin"),
            food("Base.Hotdog", "Hot Dog"),
            food("Base.IcecreamSandwich", "Ice Cream Sandwich"),
            food("Base.Crisps", "Crisps"),
            food("Base.Chocolate_Smirkers", "Chocolate Bar"),
            food("Base.MuffinFruit", "Fruit Muffin"),
        },
        validation = {
            evaluator = "junk_food_day",
            minimumItems = 3,
            hungerDropThreshold = 0.01,
            lowHoursWarn = 2.0,
            deprivationWarn = 0.03,
            endFuelWarn = 300,
            endFuelFail = 100,
            deprivationFail = Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10,
        },
    }),
    light_meals_day = withProfileDefaults({
        id = "light_meals_day",
        label = "Light Meals Day",
        description = "Light fruit-and-greens meals to check for early warning without abrupt punishment.",
        sortOrder = 25,
        projectionDefaultMode = "style_repeat",
        projectionRepeatMeals = { "late_fruit_snack", "light_supper", "late_greens" },
        projectionCueMeals = {
            peckish = { "late_fruit_snack", "afternoon_bowl" },
            hungry = { "light_supper", "late_greens" },
            very_hungry = { "light_supper", "late_greens" },
        },
        projectionCueWorkMeals = {
            peckish = { "late_fruit_snack" },
            hungry = { "late_greens" },
            very_hungry = { "light_supper" },
        },
        consumptionMode = "signal_meals",
        signalThreshold = "peckish",
        preserveSignalThresholdDuringWorkInterrupt = true,
        minGapHours = 1.5,
        phases = CANONICAL_DAY_PHASES,
        meals = {
            meal("light_breakfast", "Light Breakfast", nil, {
                food("Base.Apple", "Apple"),
                food("Base.Banana", "Banana"),
                food("Base.Yoghurt", "Yoghurt"),
            }),
            meal("mid_morning_greens", "Mid-Morning Greens", nil, {
                food("Base.Salad", "Salad"),
                food("Base.Tomato", "Tomato"),
                food("Base.BellPepper", "Bell Pepper"),
            }),
            meal("light_lunch", "Light Lunch", nil, {
                food("Base.Grapes", "Grapes"),
                food("Base.Orange", "Orange"),
                food("Base.Yoghurt", "Yoghurt"),
            }),
            meal("afternoon_bowl", "Afternoon Bowl", nil, {
                food("Base.FruitSalad", "Fruit Salad"),
                food("Base.Lettuce", "Lettuce"),
                food("Base.Broccoli", "Broccoli"),
            }),
            meal("late_fruit_snack", "Late Fruit Snack", nil, {
                food("Base.Apple", "Apple"),
                food("Base.Orange", "Orange"),
                food("Base.Banana", "Banana"),
            }),
            meal("light_supper", "Light Supper", nil, {
                food("Base.Salad", "Salad"),
                food("Base.Cabbage", "Cabbage"),
                food("Base.Tomato", "Tomato"),
            }),
            meal("late_greens", "Late Greens", nil, {
                food("Base.Grapes", "Grapes"),
                food("Base.FruitSalad", "Fruit Salad"),
                food("Base.Cabbage", "Cabbage"),
            }),
        },
        validation = {
            evaluator = "light_meals_day",
            hungerDropThreshold = 0.01,
            lowHoursExpect = 1.5,
            deprivationWarn = 0.03,
            minMeals = 5,
            minLastMealHour = 12.5,
        },
    }),
    snack_gap_stress = withProfileDefaults({
        id = "snack_gap_stress",
        label = "Snack Gap Stress",
        description = "Small snack plus long work block to verify early hunger warning and deprivation cleanup.",
        sortOrder = 30,
        durationHours = 10,
        phases = {
            phase("Morning", 0.0, 1.0, "SedentaryActivity", 1.2),
            phase("Stress Work", 1.0, 7.0, "MediumWork", 3.9),
            phase("Recovery Leisure", 7.0, 10.0, "SedentaryActivity", 1.2),
        },
        meals = {
            meal("snack_breakfast", "Snack Breakfast", 1.0, {
                food("Base.Orange", "Orange"),
            }),
            meal("recovery_meal", "Recovery Meal", 7.0, {
                food("Base.Burger", "Burger"),
                food("Base.Yoghurt", "Yoghurt"),
            }, { recovery = true }),
        },
        validation = {
            evaluator = "snack_gap_stress",
            peckishFuelThreshold = 300,
            deprivationAnyThreshold = 0.0001,
            deprivationZeroThreshold = 0.0001,
            hungerDropThreshold = 0.01,
            requireFuelBelow = 300,
            expectedFuelZone = "Low",
            recoveryTolerance = 0.01,
        },
    }),
}

function Catalog.getProfile(profileId)
    return LIVE_PROFILES[profileId or "canonical_day"] or LIVE_PROFILES.canonical_day
end

function Catalog.getProfiles()
    local profiles = {}
    for _, profile in pairs(LIVE_PROFILES) do
        profiles[#profiles + 1] = {
            id = profile.id,
            label = profile.label,
            description = profile.description,
            sortOrder = profile.sortOrder,
            consumptionMode = profile.consumptionMode,
        }
    end
    table.sort(profiles, function(a, b)
        local aOrder = tonumber(a.sortOrder) or 100
        local bOrder = tonumber(b.sortOrder) or 100
        if aOrder ~= bOrder then
            return aOrder < bOrder
        end
        return tostring(a.label) < tostring(b.label)
    end)
    return profiles
end

return Catalog
