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
Support.assertNil(Metabolism.getImmediateHungerDrop, "retired immediate-fullness API stays removed")

local grapefruitFullness = Metabolism.getMealFullness({
    kcal = 80,
    carbs = 20,
    fats = 0.2,
    proteins = 1.6,
}, 0.20)
Support.assertClose(grapefruitFullness.physicalDrop, Metabolism.MEAL_FULLNESS_PHYSICAL_CAP, 0.000001,
    "overloaded grapefruit HungerChange is only a bounded volume hint")
Support.assertClose(grapefruitFullness.targetDrop, Metabolism.MEAL_FULLNESS_PHYSICAL_CAP, 0.000001,
    "grapefruit provides temporary physical fullness without inheriting its whole recipe reservoir")
Support.assertTrue(grapefruitFullness.nutrientDrop < grapefruitFullness.targetDrop,
    "low-calorie fruit gets most immediate fullness from physical volume")
Support.assertClose(grapefruitFullness.correction, -0.08, 0.000001,
    "grapefruit raw fullness is corrected downward")

local balancedMealFullness = Metabolism.getMealFullness({
    kcal = 600,
    carbs = 65,
    fats = 20,
    proteins = 35,
}, 0.08)
Support.assertTrue(balancedMealFullness.nutrientDrop > 0.28,
    "balanced meal nutrition supplies strong immediate fullness")
Support.assertClose(balancedMealFullness.targetDrop, balancedMealFullness.nutrientDrop, 0.000001,
    "strong nutrition can exceed a mechanically small HungerChange")
Support.assertTrue(balancedMealFullness.correction > 0,
    "balanced meal is corrected toward more fullness than its raw reservoir")

local denseFoodFullness = Metabolism.getMealFullness({
    kcal = 1200,
    fats = 133,
}, 0.04)
Support.assertTrue(denseFoodFullness.targetDrop <= Metabolism.MEAL_FULLNESS_MAX_DELTA,
    "energy-dense food cannot manufacture gigantic immediate fullness")
Support.assertTrue(denseFoodFullness.targetDrop > denseFoodFullness.mechanicalDrop,
    "energy-dense food still communicates its real energy deposit")

local physicalOnlyFullness = Metabolism.getMealFullness({}, 0.35)
Support.assertClose(physicalOnlyFullness.targetDrop, Metabolism.MEAL_FULLNESS_PHYSICAL_CAP, 0.000001,
    "unknown zero-calorie intake retains bounded physical fullness")
local confirmedFullness = Metabolism.getMealFullness({
    kcal = 80,
    carbs = 20,
    fats = 0.2,
    proteins = 1.6,
}, grapefruitFullness.targetDrop)
Support.assertClose(confirmedFullness.targetDrop, grapefruitFullness.targetDrop, 0.000001,
    "client prediction and server confirmation are idempotent")
Support.assertClose(Metabolism.getFuelPressureFactor(Metabolism.FUEL_LOW_THRESHOLD), 1.0, 0.000001,
    "ready fuel must not accelerate hunger")
Support.assertClose(Metabolism.getFuelPressureFactor(Metabolism.FUEL_DEPLETED_THRESHOLD),
    Metabolism.FUEL_PRESSURE_LOW_MAX, 0.000001, "low fuel pressure ceiling")
Support.assertClose(Metabolism.getFuelPressureFactor(0),
    Metabolism.FUEL_PRESSURE_DEPLETED_MAX, 0.000001, "depleted fuel pressure ceiling")

Support.assertClose(Metabolism.getEnergyAppetiteProgress(0), 0, 0.000001,
    "balanced recent intake must not add appetite pressure")
Support.assertClose(Metabolism.ENERGY_APPETITE_BALANCE_FULL_KCAL, 800, 0.000001,
    "appetite reaches full strength before a demanding day can hide a large deficit")
Support.assertClose(Metabolism.ENERGY_APPETITE_MAX_RATE_PER_HOUR, 0.05, 0.000001,
    "full deficit pressure can materially affect same-day eating cues")
Support.assertClose(Metabolism.getEnergyAppetiteProgress(-Metabolism.ENERGY_APPETITE_BALANCE_DEADZONE_KCAL), 0, 0.000001,
    "small recent deficits stay in the appetite deadzone")
Support.assertClose(Metabolism.getEnergyAppetiteProgress(-Metabolism.ENERGY_APPETITE_BALANCE_FULL_KCAL), 1, 0.000001,
    "large recent deficits saturate appetite pressure")

local balancedAppetiteRate = Metabolism.getPassiveVisibleHungerRatePerHour(
    Metabolism.newState({ fuel = 900, weightBalanceKcal = 0, satietyBuffer = 1 }),
    Metabolism.ACTIVITY_IDLE,
    nil,
    1.0
)
local deficitAppetiteRate = Metabolism.getPassiveVisibleHungerRatePerHour(
    Metabolism.newState({ fuel = 900, weightBalanceKcal = -Metabolism.ENERGY_APPETITE_BALANCE_FULL_KCAL, satietyBuffer = 1 }),
    Metabolism.ACTIVITY_IDLE,
    nil,
    1.0
)
Support.assertClose(deficitAppetiteRate.ratePerHour - balancedAppetiteRate.ratePerHour,
    Metabolism.ENERGY_APPETITE_MAX_RATE_PER_HOUR, 0.000001,
    "persistent deficit adds appetite independently from meal staying power")

local sleepingBalancedRate = Metabolism.getPassiveVisibleHungerRatePerHour(
    Metabolism.newState({ fuel = 900, weightBalanceKcal = 0 }),
    Metabolism.ACTIVITY_SLEEP,
    nil,
    1.0
)
local sleepingDeficitRate = Metabolism.getPassiveVisibleHungerRatePerHour(
    Metabolism.newState({ fuel = 900, weightBalanceKcal = -Metabolism.ENERGY_APPETITE_BALANCE_FULL_KCAL }),
    Metabolism.ACTIVITY_SLEEP,
    nil,
    1.0
)
Support.assertClose(sleepingDeficitRate.ratePerHour - sleepingBalancedRate.ratePerHour,
    Metabolism.ENERGY_APPETITE_MAX_RATE_PER_HOUR * Metabolism.SLEEP_HUNGER_FACTOR, 0.000001,
    "sleep attenuates recent-balance appetite pressure")

Support.assertClose(Metabolism.getDeprivationTarget(-1100), 0, 0.000001,
    "one demanding recorded-day deficit must not target deprivation")
Support.assertClose(Metabolism.getDeprivationTarget(-Metabolism.DEPRIVATION_BALANCE_DEADZONE_KCAL), 0, 0.000001,
    "deprivation has a multi-day balance deadzone")
Support.assertClose(Metabolism.getDeprivationTarget(-Metabolism.DEPRIVATION_BALANCE_FULL_KCAL), 1, 0.000001,
    "deep sustained imbalance targets full deprivation")
Support.assertClose(Metabolism.advanceDeprivation(0, -Metabolism.DEPRIVATION_BALANCE_FULL_KCAL, 24), 0.5, 0.000001,
    "deprivation needs two days to approach a severe target")
Support.assertClose(Metabolism.advanceDeprivation(0.2, 0, 18), 0.1, 0.000001,
    "deprivation recovery remains smooth through the moodle threshold")
Support.assertNil(Metabolism.getUnderfeedingDebtProgress, "retired low-fuel deprivation ledger API")
local migratedTransientDeprivation = Metabolism.ensureState({
    version = 13,
    weightBalanceKcal = -1100,
    deprivation = 0.5,
})
Support.assertClose(migratedTransientDeprivation.deprivation, 0, 0.000001,
    "old same-day deprivation is cleared when the new sustained-balance target is zero")

local normalRate = Metabolism.getPassiveVisibleHungerRatePerHour(
    Metabolism.newState({ fuel = 900 }),
    Metabolism.ACTIVITY_IDLE,
    nil,
    1.0
)
local slowRate = Metabolism.getPassiveVisibleHungerRatePerHour(
    Metabolism.newState({ fuel = 900 }),
    Metabolism.ACTIVITY_IDLE,
    nil,
    0.65
)
Support.assertClose(slowRate.ratePerHour, normalRate.ratePerHour * 0.65, 0.000001,
    "sandbox stats decrease multiplier must scale visible hunger")

local state = Metabolism.newState({
    fuel = 900,
    proteins = proteinMax,
    weightKg = weight,
    pendingNutritionSuppressions = { { kcal = 100 } },
    lastExertionMultiplier = 1.2,
    underfeedingDebtKcal = 500,
})
Support.assertNil(state.carbs, "carbohydrate reserve must remain retired")
Support.assertNil(state.fats, "fat reserve must remain retired")
Support.assertNil(state.pendingNutritionSuppressions, "consume suppression state must be retired")
Support.assertNil(state.lastExertionMultiplier, "imaginary exertion metric must be retired")
Support.assertNil(state.underfeedingDebtKcal, "retired underfeeding debt state must be discarded")

local deposit = Metabolism.applyFoodValues(state, {
    hunger = -0.25,
    kcal = 500,
    carbs = 50,
    fats = 20,
    proteins = 25,
}, 1, "test-meal")
Support.assertClose(deposit.kcal, 500, 0.000001, "meal calorie deposit")
Support.assertNil(state.totalIntakeKcal, "diagnostic intake ledgers must not live in durable metabolism state")
Support.assertTrue(deposit.satietyContribution > 0, "meal must contribute satiety")
Support.assertTrue(state.fuel > 900, "meal must increase fuel")
Support.assertClose(state.visibleHunger, 0, 0.000001, "nutrition deposit must not change visible hunger")
Support.assertNil(deposit.immediateHungerDrop, "deposit report must not contain modeled fullness")

local secondDeposit = Metabolism.applyFoodValues(state, { kcal = 50 }, 1, "second-deposit")
Support.assertClose(secondDeposit.kcal, 50, 0.000001, "each deposit reports its own intake")
local zeroTimeReport = Metabolism.advanceState(state, 0, Metabolism.ACTIVITY_IDLE, {
    reason = "zero-time",
    previousWeightRateKgPerWeek = -0.25,
})
Support.assertClose(zeroTimeReport.weightRateKgPerWeek, -0.25, 0.000001,
    "zero-time reports preserve a runtime-supplied weight trend")
Support.assertNil(state.lastWeightRateKgPerWeek, "weight trend telemetry must stay outside durable state")

local beforeFuel = state.fuel
local report = Metabolism.advanceState(state, 8, Metabolism.ACTIVITY_IDLE, { reason = "test-advance" })
Support.assertTrue(report.burnedKcal > 0, "time advance must burn fuel")
Support.assertNil(state.totalBurnKcal, "diagnostic burn ledgers must not live in durable metabolism state")
Support.assertTrue(state.fuel < beforeFuel, "time advance must lower fuel")
Support.assertTrue(state.visibleHunger >= 0 and state.visibleHunger <= Metabolism.VISIBLE_HUNGER_CAP, "visible hunger invariant")
Support.assertTrue(state.weightKg >= Metabolism.WEIGHT_MIN_KG and state.weightKg <= Metabolism.WEIGHT_MAX_KG, "weight invariant")

local sleepLedgerState = Metabolism.newState()
local sleepReport = Metabolism.advanceState(sleepLedgerState, 2, Metabolism.ACTIVITY_SLEEP, { reason = "sleep-ledger" })
Support.assertClose(sleepReport.elapsedHours, 2, 0.000001, "sleep reports observed time")
Support.assertEqual(sleepReport.sleepObserved, true, "sleep reports its workload mode")

local lowBurnState = Metabolism.newState({ fuel = 1500, visibleHunger = 0.05 })
local highBurnState = Metabolism.newState({ fuel = 1500, visibleHunger = 0.05 })
local measuredWorkload = {
    averageMet = 3.1,
    peakMet = 3.1,
    source = "sandbox-burn-test",
}
local lowBurnReport = Metabolism.advanceState(lowBurnState, 0.25, measuredWorkload, {
    burnKcalOverride = 100,
    energyBurnMultiplier = 0.5,
})
local highBurnReport = Metabolism.advanceState(highBurnState, 0.25, measuredWorkload, {
    burnKcalOverride = 100,
    energyBurnMultiplier = 2.0,
})
Support.assertClose(lowBurnReport.burnedKcal, 50, 0.000001,
    "energy tuning scales measured workload burn downward")
Support.assertClose(highBurnReport.burnedKcal, 200, 0.000001,
    "energy tuning scales measured workload burn upward")
Support.assertClose(lowBurnReport.energyBurnMultiplier, 0.5, 0.000001,
    "advance reports the applied energy multiplier")

local slowTraitBurnState = Metabolism.newState({ fuel = 1500 })
local fastTraitBurnState = Metabolism.newState({ fuel = 1500 })
local slowTraitBurn = Metabolism.advanceState(slowTraitBurnState, 0.25, measuredWorkload, {
    traitEffects = { burnMultiplier = 0.96 },
})
local fastTraitBurn = Metabolism.advanceState(fastTraitBurnState, 0.25, measuredWorkload, {
    traitEffects = { burnMultiplier = 1.04 },
})
Support.assertTrue(slowTraitBurn.burnedKcal < fastTraitBurn.burnedKcal,
    "sampled workload burn must retain metabolism-trait effects")

local lowAppetiteState = Metabolism.newState({ fuel = 1200, visibleHunger = 0.05 })
local highAppetiteState = Metabolism.newState({ fuel = 1200, visibleHunger = 0.05 })
local lowAppetiteReport = Metabolism.advanceState(lowAppetiteState, 0.10, Metabolism.ACTIVITY_IDLE, {
    statsDecreaseMultiplier = 0.8,
    appetiteRateMultiplier = 0.5,
})
local highAppetiteReport = Metabolism.advanceState(highAppetiteState, 0.10, Metabolism.ACTIVITY_IDLE, {
    statsDecreaseMultiplier = 0.8,
    appetiteRateMultiplier = 2.0,
})
Support.assertClose(highAppetiteReport.visibleHungerGain, lowAppetiteReport.visibleHungerGain * 4, 0.000001,
    "NMS appetite tuning composes independently with vanilla Stats Decrease")
Support.assertClose(highAppetiteReport.statsDecreaseMultiplier, 0.8, 0.000001,
    "advance reports the vanilla multiplier separately")
Support.assertClose(highAppetiteReport.appetiteRateMultiplier, 2.0, 0.000001,
    "advance reports the NMS appetite multiplier separately")
Support.assertClose(highAppetiteReport.hungerRateMultiplier, 1.6, 0.000001,
    "advance reports the effective appetite multiplier")

print("nms metabolism characterization passed")
