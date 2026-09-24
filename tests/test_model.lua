local Support = require "support"
local Sim = require "sim"
local Model = NutritionMakesSense.Model

local function inRange(value, lo, hi, message)
    Support.assertTrue(value >= lo and value <= hi,
        string.format("%s (got %.3f, expected %.3f..%.3f)", message, value, lo, hi))
end

-- Pure model contracts.
inRange(Model.burnPerHour(1.0, false, 80), 74.9, 75.1, "resting burn is 75 kcal/h at 80 kg")
inRange(Model.burnPerHour(1.0, true, 80), 34.9, 35.1, "sleeping burn is 35 kcal/h")
Support.assertTrue(Model.burnPerHour(1.0, false, 80, { fastMetabolism = true }) > Model.burnPerHour(1.0, false, 80),
    "fast metabolism burns more")

Support.assertTrue(Model.fillHours(400, 20, 30) > Model.fillHours(400, 0, 0),
    "protein and fat keep the stomach full longer than the same energy as carbs")
Support.assertEqual(Model.fillHours(0, 10, 10), 0, "zero-calorie food fills nothing")

local dC, dW = Model.storageFlux(1900, 80, nil, 1)
Support.assertTrue(dC < 0 and dW > 0, "surplus above the reserve band is stored as fat")
dC, dW = Model.storageFlux(-500, 80, nil, 1)
Support.assertTrue(dC > 0 and dW < 0, "deficit below the reserve band mobilizes fat")
dC, dW = Model.storageFlux(800, 80, nil, 1)
Support.assertEqual(dW, 0, "inside the reserve band weight does not move")
inRange(Model.mobilizeCapacityPerHour(45), 0, 0, "a lean body cannot mobilize fat")

local combined, calorieTarget, proteinTarget = Model.malnutritionTargets(-1500, 0)
inRange(calorieTarget, 0.999, 1.0, "calorie depletion drives malnutrition to full")
Support.assertEqual(proteinTarget, 0, "normal protein adds no malnutrition")
combined, calorieTarget, proteinTarget = Model.malnutritionTargets(800, -500)
inRange(proteinTarget, 0.49, 0.5, "protein deficiency alone caps at half")
Support.assertEqual(Model.malnutritionCause(0, proteinTarget), "protein", "protein cause is reported")
Support.assertEqual(Model.malnutritionCause(0.4, 0.2), "both", "combined cause is reported")
Support.assertNil(Model.malnutritionCause(0, 0), "no cause when fed")

Support.assertTrue(Model.wellFedHealing(0) < 0.015 / 10, "Well Fed healing is a fraction of vanilla's 0.015")
Support.assertEqual(Model.naturalRecoveryMultiplier(0), 1, "fed characters recover normally")
inRange(Model.naturalRecoveryMultiplier(1), 0.49, 0.51, "severe malnutrition halves natural recovery")

inRange(Model.legacyFuelToCalories(800), 300, 1300, "old ready fuel lands inside the reserve band")
Support.assertEqual(Model.reserveZone(-10), "Depleted", "negative reserve is depleted")
Support.assertEqual(Model.reserveZone(2000), "Stored", "surplus is stored")

-- Step contracts.
local prev = { calories = 800, hunger = 0.4, timer = 0, weight = 80 }
local out = Model.step(prev, { calories = 1250, hunger = 0.1, timer = 900, weight = 80, fatsIn = 18, proteinsIn = 25 },
    { dtHours = 0.01, met = 1, asleep = false })
inRange(out.intakeKcal, 450, 452, "intake comes from the vanilla calorie counter delta")
inRange(out.hunger, 0.18, 0.20, "eat-time hunger drop is scaled, not taken from item HungerChange")
Support.assertTrue(out.timer > 1000 and out.timer < 3200, "a normal meal fills to Well Fed, not Stuffed")

out = Model.step(prev, { calories = 799, hunger = 0.4, timer = 0, weight = 79.99, fatsIn = 0, proteinsIn = 0 },
    { dtHours = 0.01, met = 1, asleep = false })
inRange(out.weight, 79.999, 80.001, "vanilla weight drift is reverted")
Support.assertEqual(out.intakeKcal, 0, "vanilla burn is not mistaken for intake")

out = Model.step(prev, { calories = 800, hunger = 0.4, timer = 0, weight = 70, fatsIn = 0, proteinsIn = 0 },
    { dtHours = 0.01, met = 1, asleep = false })
inRange(out.weight, 69.99, 70.01, "large weight edits (admin/other mods) are accepted")

out = Model.step(prev, { calories = 800, hunger = 0.4, timer = 1500, weight = 80, fatsIn = 0, proteinsIn = 0 },
    { dtHours = 0.01, met = 1, asleep = false })
Support.assertTrue(out.timer > 1400, "external Well Fed timer increases are kept")

-- Whole-day behaviour.
local meal = Sim.run({ food = "meal" })
inRange(meal.eventsPerDay, 2.0, 3.6, "a normal meal diet means 2-3.5 meals per day")
inRange(meal.weightChangePerWeek, -0.25, 0.25, "a normal meal diet keeps weight roughly stable")
inRange(meal.wellFedShare, 0.1, 0.5, "Well Fed covers part of the day, not all of it")
Support.assertTrue(meal.maxMalnutrition < 0.1, "a normal meal diet does not malnourish")

local veggie = Sim.run({ food = "veggie" })
Support.assertTrue(veggie.weightChangePerWeek < -0.3, "a low-energy diet loses weight")

local dense = Sim.run({ food = "dense" })
Support.assertTrue(dense.weightChangePerWeek > 0.1, "energy-dense food gains weight")

local rice = Sim.run({ food = "rice", days = 21 })
Support.assertTrue(rice.maxMalnutrition > 0.1, "a protein-poor diet builds malnutrition")

local fast = Sim.run({ food = "meal", days = 10, fastFromHour = 0 })
Support.assertTrue(fast.maxMalnutrition > 0.8, "a long fast severely malnourishes")
Support.assertTrue(fast.weightChangePerWeek < -1.0, "a long fast loses fat")

local light = Sim.run({ food = "meal", stopAt = 0.14 })
Support.assertTrue(light.weightChangePerWeek < meal.weightChangePerWeek, "eating only to take the edge off loses weight")

local ctx = { met = 1.0, asleep = false, burnMultiplier = 1, appetiteMultiplier = 1 }
local full = Model.forecast({ calories = 900, hunger = 0.05, timer = 3000, weight = 80 }, ctx)
local empty = Model.forecast({ calories = 900, hunger = 0.05, timer = 0, weight = 80 }, ctx)
Support.assertTrue(full.hungryIn and empty.hungryIn and full.hungryIn >= empty.hungryIn + 1.5, "a full stomach postpones hunger")
inRange(empty.lowIn, 7, 9, "rest burn drains 600 kcal to Low in about 8 h")
Support.assertEqual(Model.forecast({ calories = -10, hunger = 0.5, timer = 0, weight = 80 }, ctx).depletedIn, 0, "already depleted")

local lowDays, deficientDays = Model.proteinDaysLeft(-100 + Model.VANILLA_PROTEIN_DECAY_PER_DAY)
inRange(lowDays, 0.99, 1.01, "one day of vanilla decay to Low")
inRange(deficientDays, 3.6, 3.8, "Low to deficient takes under three days more")

inRange(Model.malnutritionHoursTo(0.4, 0, 0.10), 49, 51, "recovery clears the moodle in about two days")
Support.assertNil(Model.malnutritionHoursTo(0.4, 0.2, 0.10), "never clears while the target stays above the moodle")
Support.assertTrue(Model.malnutritionHoursTo(0.2, 0.6, 0.30) > 0, "worsening reaches the next level")

local weeks, boundary = Model.weightTraitWeeks(78, -0.5)
Support.assertEqual(boundary, 75, "losing weight heads for Underweight")
inRange(weeks, 5.99, 6.01, "3 kg at 0.5 kg/wk")
Support.assertNil(Model.weightTraitWeeks(78, 0.01), "flat trend has no forecast")

print("nms model characterization passed")
