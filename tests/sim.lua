-- Deterministic day simulator for the NMS 2.0 model.
-- Emulates only what vanilla contributes (eating: hunger drop + nutrition deposit; protein decay)
-- and lets Model.step drive everything else, exactly like the runtime does.
require "NutritionMakesSense_Model"
local Model = NutritionMakesSense.Model

local Sim = {}

Sim.FOODS = {
    meal = { kcal = 450, hunger = 0.30, fats = 18, proteins = 25 },
    stew = { kcal = 700, hunger = 0.45, fats = 28, proteins = 35 },
    snack = { kcal = 150, hunger = 0.10, fats = 6, proteins = 3 },
    dense = { kcal = 400, hunger = 0.12, fats = 24, proteins = 6 },
    veggie = { kcal = 90, hunger = 0.15, fats = 1, proteins = 3 },
    rice = { kcal = 350, hunger = 0.25, fats = 1, proteins = 7 },
}

local VANILLA_PROTEIN_DECAY_PER_HOUR = 74 / 24

local function defaultSchedule(hourOfDay)
    if hourOfDay >= 23 or hourOfDay < 7 then
        return 0.8, true
    end
    if hourOfDay >= 9 and hourOfDay < 12 then
        return 3.5, false
    end
    if hourOfDay >= 14 and hourOfDay < 15 then
        return 6.0, false
    end
    return 1.3, false
end

-- opts: food (name), eatAt (hunger threshold), days, weight, traits, schedule(hour)->met,asleep, fastHours
function Sim.run(opts)
    local food = Sim.FOODS[opts.food or "meal"]
    local eatAt = opts.eatAt or 0.25
    local stopAt = opts.stopAt or 0.02
    local days = opts.days or 14
    local dt = opts.dt or 0.05
    local schedule = opts.schedule or defaultSchedule
    local state = {
        calories = opts.calories or Model.RESERVE_SET_POINT,
        hunger = opts.hunger or 0.1,
        timer = 0,
        weight = opts.weight or 80,
    }
    local proteins = opts.proteins or 0
    local malnutrition = 0
    local vanillaBurn = Model.VANILLA_BURN_DEFAULT_PER_HOUR
    local stats = {
        eatingEvents = 0, items = 0, kcal = 0, awakeHours = 0, awakeHunger = 0,
        wellFedAwakeHours = 0, maxMalnutrition = 0, minCalories = state.calories, maxCalories = state.calories,
        hungryAwakeHours = 0,
    }
    local startWeight = state.weight
    local steps = math.floor(days * 24 / dt + 0.5)
    local lastEatHour = -99

    for i = 0, steps - 1 do
        local hour = i * dt
        local hourOfDay = hour % 24
        local met, asleep = schedule(hourOfDay)
        local fasting = opts.fastFromHour and hour >= opts.fastFromHour and (not opts.fastToHour or hour < opts.fastToHour)

        local obs = {
            calories = state.calories, hunger = state.hunger, timer = state.timer, weight = state.weight,
            fatsIn = 0, proteinsIn = 0,
        }
        proteins = math.max(-500, proteins - VANILLA_PROTEIN_DECAY_PER_HOUR * dt)

        if not asleep and not fasting and state.hunger >= eatAt and Model.stomachLevel(state.timer) < 3 then
            stats.eatingEvents = stats.eatingEvents + 1
            local ate = 0
            local fatsIn, proteinsIn = 0, 0
            local scaledHunger = obs.hunger
            repeat
                obs.hunger = math.max(0, obs.hunger - food.hunger)
                scaledHunger = math.max(0, scaledHunger - food.hunger * Model.HUNGER_DROP_SCALE)
                obs.calories = math.min(Model.CALORIES_MAX, obs.calories + food.kcal)
                fatsIn = fatsIn + food.fats
                proteinsIn = proteinsIn + food.proteins
                proteins = math.min(1000, proteins + food.proteins)
                ate = ate + 1
                stats.items = stats.items + 1
                stats.kcal = stats.kcal + food.kcal
            until scaledHunger <= stopAt or ate >= 8
            obs.fatsIn, obs.proteinsIn = fatsIn, proteinsIn
            lastEatHour = hour
        end

        local out = Model.step(state, obs, {
            dtHours = dt, met = met, asleep = asleep, traits = opts.traits,
            burnMultiplier = opts.burnMultiplier, appetiteMultiplier = opts.appetiteMultiplier,
            vanillaBurnPerHour = vanillaBurn,
        })
        vanillaBurn = out.vanillaBurnPerHour
        state.calories, state.hunger, state.timer, state.weight = out.calories, out.hunger, out.timer, out.weight

        local target = Model.malnutritionTargets(state.calories, proteins)
        malnutrition = Model.advanceMalnutrition(malnutrition, target, dt)

        stats.maxMalnutrition = math.max(stats.maxMalnutrition, malnutrition)
        stats.minCalories = math.min(stats.minCalories, state.calories)
        stats.maxCalories = math.max(stats.maxCalories, state.calories)
        if not asleep then
            stats.awakeHours = stats.awakeHours + dt
            stats.awakeHunger = stats.awakeHunger + state.hunger * dt
            if Model.stomachLevel(state.timer) >= 2 then
                stats.wellFedAwakeHours = stats.wellFedAwakeHours + dt
            end
            if state.hunger >= 0.25 then
                stats.hungryAwakeHours = stats.hungryAwakeHours + dt
            end
        end
    end

    return {
        eventsPerDay = stats.eatingEvents / days,
        itemsPerDay = stats.items / days,
        kcalPerDay = stats.kcal / days,
        weightChangePerWeek = (state.weight - startWeight) / days * 7,
        weight = state.weight,
        avgAwakeHunger = stats.awakeHunger / math.max(1e-9, stats.awakeHours),
        wellFedShare = stats.wellFedAwakeHours / math.max(1e-9, stats.awakeHours),
        hungryShare = stats.hungryAwakeHours / math.max(1e-9, stats.awakeHours),
        malnutrition = malnutrition,
        maxMalnutrition = stats.maxMalnutrition,
        calories = state.calories,
        minCalories = stats.minCalories,
        maxCalories = stats.maxCalories,
        proteins = proteins,
    }
end

function Sim.format(name, r)
    return string.format(
        "%-22s ev/d %4.1f items/d %4.1f kcal/d %5.0f dW/wk %+5.2f hungerAvg %.2f wellFed %3.0f%% hungry %3.0f%% M %.2f C[%5.0f..%5.0f] P %4.0f",
        name, r.eventsPerDay, r.itemsPerDay, r.kcalPerDay, r.weightChangePerWeek, r.avgAwakeHunger,
        r.wellFedShare * 100, r.hungryShare * 100, r.malnutrition, r.minCalories, r.maxCalories, r.proteins)
end

return Sim
