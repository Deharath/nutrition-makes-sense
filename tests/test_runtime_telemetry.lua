local Support = require "support"
local Metabolism = require "NutritionMakesSense_Metabolism"

NutritionMakesSense.log = function() end
local Runtime = require "NutritionMakesSense_MetabolismRuntime"

local modData = {
    NutritionMakesSenseState = {
        version = 14,
        initialized = true,
        fuel = 480,
        proteins = 210,
        weightKg = 82,
        weightController = -0.2,
        weightBalanceKcal = -900,
        deprivation = 0.08,
        visibleHunger = 0.24,
        satietyBuffer = 0.4,
        depositSequence = 7,
        lastWorldHours = 100,
        baseHealthFromFood = 0.015,
        lastMetAverage = 3.1,
        lastWeightRateKgPerWeek = -0.3,
        lastSyncedHunger = 0.23,
        totalIntakeKcal = 2500,
        totalBurnKcal = 2200,
        totalVisibleHungerGain = 0.7,
        totalObservedHours = 18,
        totalSleepHours = 6,
        pendingObservedHungerDrop = 0.04,
        pendingMealTransaction = { kcal = 80, fragments = 1 },
    },
}
local player = {
    getModData = function() return modData end,
    getStats = function() return nil end,
    getNutrition = function() return nil end,
    getBodyDamage = function() return nil end,
}

local state = Runtime.ensureStateForPlayer(player)
Support.assertEqual(state.version, Metabolism.STATE_VERSION, "durable state migrates to the current schema")
Support.assertClose(state.weightBalanceKcal, -900, 0.000001, "durable recent-energy balance survives migration")
Support.assertNil(state.lastMetAverage, "last-tick workload does not remain in saved state")
Support.assertNil(state.totalIntakeKcal, "recorder intake ledger does not remain in saved state")
Support.assertNil(state.pendingMealTransaction, "in-flight meal bookkeeping does not remain in saved state")

local telemetry = Runtime.getTelemetryForState(state)
Support.assertClose(telemetry.lastMetAverage, 3.1, 0.000001, "legacy workload telemetry survives the live cutover")
Support.assertClose(telemetry.totalIntakeKcal, 2500, 0.000001, "legacy intake ledger survives the live cutover")
Support.assertClose(telemetry.pendingObservedHungerDrop, 0.04, 0.000001,
    "in-flight hunger evidence survives the live cutover")
Support.assertTrue(type(telemetry.pendingMealTransaction) == "table",
    "in-flight meal aggregation survives the live cutover")

local view = Runtime.getStateCopy(player)
Support.assertEqual(view.lastZone, "Low", "runtime view derives the energy zone")
Support.assertEqual(view.lastHungerBand, "peckish", "runtime view derives the hunger band")
Support.assertClose(view.totalBurnKcal, 2200, 0.000001, "runtime view includes recorder telemetry")
Support.assertClose(view.lastWeightRateKgPerWeek, -0.3, 0.000001, "runtime view includes weight trend telemetry")

local deposit = Metabolism.applyFoodValues(state, { kcal = 500, proteins = 20 }, 1, "telemetry-test-meal")
Runtime.recordDepositTelemetry(telemetry, deposit)
Support.assertClose(telemetry.totalIntakeKcal, 3000, 0.000001, "runtime intake ledger advances from deposit reports")
Support.assertClose(telemetry.lastDepositKcal, 500, 0.000001, "runtime retains the latest deposit for diagnostics")

local report = Metabolism.advanceState(state, 0.5, Metabolism.ACTIVITY_WALK, {
    reason = "telemetry-test-advance",
    previousWeightRateKgPerWeek = telemetry.lastWeightRateKgPerWeek,
})
Runtime.recordAdvanceTelemetry(telemetry, report)
Support.assertClose(telemetry.totalBurnKcal, 2200 + report.burnedKcal, 0.000001,
    "runtime burn ledger advances from model reports")
Support.assertClose(telemetry.totalObservedHours, 18.5, 0.000001,
    "runtime observed-time ledger advances from model reports")
Support.assertEqual(telemetry.lastTraceReason, "telemetry-test-advance", "runtime retains the latest diagnostic reason")

local durableCopy = Metabolism.copyState(Runtime.getStateCopy(player))
Support.assertNil(durableCopy.totalBurnKcal, "copying a runtime view back to durable state strips telemetry")
Support.assertNil(durableCopy.lastZone, "copying a runtime view strips derivable display fields")
Support.assertClose(durableCopy.weightBalanceKcal, state.weightBalanceKcal, 0.000001,
    "copying a runtime view preserves gameplay state")

print("nms runtime telemetry separation passed")
