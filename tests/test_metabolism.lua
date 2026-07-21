local Support = require "support"
local Metabolism = require "NutritionMakesSense_Metabolism"

Support.assertEqual(Metabolism.getFuelZone(0), "Depleted", "zero fuel zone")
Support.assertEqual(Metabolism.getFuelZone(Metabolism.FUEL_DEPLETED_THRESHOLD), "Low", "depleted threshold zone")
Support.assertEqual(Metabolism.getFuelZone(Metabolism.FUEL_LOW_THRESHOLD), "Ready", "low threshold zone")
Support.assertEqual(Metabolism.getFuelZone(Metabolism.FUEL_STORED_THRESHOLD + 1), "Stored", "stored zone")
Support.assertEqual(Metabolism.getVisibleHungerBand(0.15), "comfortable", "peckish threshold remains below vanilla's strict boundary")
Support.assertEqual(Metabolism.getVisibleHungerBand(0.150001), "peckish", "hunger above peckish threshold changes band")
Support.assertEqual(Metabolism.getVisibleHungerBand(0.25), "peckish", "hungry threshold remains in peckish band")
Support.assertEqual(Metabolism.getVisibleHungerBand(0.250001), "hungry", "hunger above hungry threshold changes band")
Support.assertEqual(Metabolism.getVisibleHungerBand(0.45), "hungry", "very-hungry threshold remains in hungry band")
Support.assertEqual(Metabolism.getVisibleHungerBand(0.70), "very_hungry", "starving threshold remains in very-hungry band")
Support.assertEqual(Metabolism.getVisibleHungerBand(0.700001), "starving", "hunger above starving threshold changes band")

local sleepBurn = Metabolism.getFuelBurnPerHourFromMet(Metabolism.ACTIVITY_SLEEP, 80)
local restBurn = Metabolism.getFuelBurnPerHourFromMet(Metabolism.ACTIVITY_IDLE, 80)
local walkBurn = Metabolism.getFuelBurnPerHourFromMet(Metabolism.ACTIVITY_WALK, 80)
local strenuousBurn = Metabolism.getFuelBurnPerHourFromMet(Metabolism.ACTIVITY_STRENUOUS, 80)
Support.assertTrue(sleepBurn < restBurn, "sleep must burn less fuel than rest")
Support.assertTrue(restBurn < walkBurn, "rest must burn less fuel than walking")
Support.assertTrue(walkBurn < strenuousBurn, "walking must burn less fuel than strenuous work")

local weight = 80
local proteinMax = Metabolism.getProteinAdequacyMax(weight)
local penaltyBoundary = Metabolism.getProteinNeedPerDay(weight) * Metabolism.PROTEIN_STRENGTH_XP_PENALTY_MAX_DAYS
local bonusBoundary = Metabolism.getProteinNeedPerDay(weight) * Metabolism.PROTEIN_STRENGTH_XP_BONUS_MIN_DAYS
Support.assertClose(Metabolism.getStrengthXpProteinMultiplier(0, weight), 0.7, 0.000001, "empty protein reserve XP multiplier")
Support.assertClose(Metabolism.getStrengthXpProteinMultiplier(penaltyBoundary, weight), 0.7, 0.000001, "protein penalty boundary")
Support.assertClose(Metabolism.getStrengthXpProteinMultiplier(penaltyBoundary + 0.01, weight), 1.0, 0.000001, "protein neutral range")
Support.assertClose(Metabolism.getStrengthXpProteinMultiplier(bonusBoundary, weight), 1.5, 0.000001, "protein bonus boundary")
Support.assertClose(Metabolism.getStrengthXpProteinMultiplier(proteinMax, weight), 1.5, 0.000001, "full protein reserve XP multiplier")

Support.assertClose(Metabolism.getDeprivationRegenScale(0), 1.0, 0.000001, "fed endurance regeneration")
Support.assertClose(Metabolism.getDeprivationRegenScale(1), Metabolism.DEPRIVATION_REGEN_SCALE_MIN, 0.000001, "maximum deprivation regeneration")
Support.assertTrue(Metabolism.getDeprivationActivityDrain(1, 6) > 0, "deprivation must add activity endurance drain")
Support.assertNil(Metabolism.getExertionPenaltyMultiplier, "retired exertion multiplier API")
Support.assertNil(Metabolism.getFatigueAccelFactor, "sleep-pressure penalty must remain outside NMS")
Support.assertNil(Metabolism.getImmediateHungerDrop, "calories must not manufacture immediate fullness")

local state = Metabolism.newState({
    fuel = 900,
    proteins = proteinMax,
    weightKg = weight,
    pendingNutritionSuppressions = { { kcal = 100 } },
    lastExertionMultiplier = 1.2,
})
Support.assertNil(state.carbs, "carbohydrate reserve must remain retired")
Support.assertNil(state.fats, "fat reserve must remain retired")
Support.assertNil(state.pendingNutritionSuppressions, "consume suppression state must be retired")
Support.assertNil(state.lastExertionMultiplier, "imaginary exertion metric must be retired")

local deposit = Metabolism.applyFoodValues(state, {
    hunger = -0.25,
    kcal = 500,
    carbs = 50,
    fats = 20,
    proteins = 25,
}, 1, "test-meal")
Support.assertClose(deposit.kcal, 500, 0.000001, "meal calorie deposit")
Support.assertTrue(deposit.satietyContribution > 0, "meal must contribute satiety")
Support.assertTrue(state.fuel > 900, "meal must increase fuel")
Support.assertClose(state.visibleHunger, 0, 0.000001, "nutrition deposit must not change visible hunger")
Support.assertNil(deposit.immediateHungerDrop, "deposit report must not contain modeled fullness")

local beforeFuel = state.fuel
local report = Metabolism.advanceState(state, 8, Metabolism.ACTIVITY_IDLE, { reason = "test-advance" })
Support.assertTrue(report.burnedKcal > 0, "time advance must burn fuel")
Support.assertTrue(state.fuel < beforeFuel, "time advance must lower fuel")
Support.assertTrue(state.visibleHunger >= 0 and state.visibleHunger <= Metabolism.VISIBLE_HUNGER_CAP, "visible hunger invariant")
Support.assertTrue(state.weightKg >= Metabolism.WEIGHT_MIN_KG and state.weightKg <= Metabolism.WEIGHT_MAX_KG, "weight invariant")

print("nms metabolism characterization passed")
