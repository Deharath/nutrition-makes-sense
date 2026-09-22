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

local oldFuel, oldBalance = state.fuel, state.weightBalanceKcal
Support.assertTrue(Runtime.setAdminWeight(player, 95), "admin edit accepted")
Support.assertClose(state.weightKg, 95, 0.00001, "admin weight persists in authoritative state")
Support.assertClose(state.fuel, oldFuel, 0.00001, "weight edit preserves fuel")
Support.assertClose(state.weightBalanceKcal, oldBalance, 0.00001, "weight edit preserves energy history")
Support.assertTrue(not Runtime.setAdminWeight(player, 0/0), "NaN rejected")
Support.assertTrue(not Runtime.setAdminWeight(player, 200), "out of range weight rejected")
Support.assertNil(state.baseHealthFromFood, "inactive healing baseline removed from saves")

local healingRates = { standard = 0.002, reduced = 0.0013, severe = 0.0008 }
local foodTimerWrites = 0
local bodyDamage = {
    getStandardHealthAddition = function() return healingRates.standard end,
    setStandardHealthAddition = function(_, value) healingRates.standard = value end,
    getReducedHealthAddition = function() return healingRates.reduced end,
    setReducedHealthAddition = function(_, value) healingRates.reduced = value end,
    getSeverlyReducedHealthAddition = function() return healingRates.severe end,
    setSeverlyReducedHealthAddition = function(_, value) healingRates.severe = value end,
    setHealthFromFoodTimer = function() foodTimerWrites = foodTimerWrites + 1 end,
}
local recoveryState = { proteins = Metabolism.getProteinAdequacyMax(80), weightKg = 80, fuel = 1000 }
Support.assertClose(Runtime.syncNaturalRecovery(bodyDamage, recoveryState), 1.2, 0.000001,
    "well-nourished recovery has a bounded bonus")
Support.assertClose(healingRates.standard, 0.0024, 0.000001,
    "recovery adjusts vanilla's ordinary awake healing rate")
Runtime.syncNaturalRecovery(bodyDamage, recoveryState)
Support.assertClose(healingRates.standard, 0.0024, 0.000001,
    "repeated shell sync does not compound the recovery multiplier")
recoveryState.fuel = 0
Runtime.syncNaturalRecovery(bodyDamage, recoveryState)
Support.assertClose(healingRates.standard, 0.002, 0.000001,
    "losing energy support restores the unmodified vanilla baseline")
recoveryState.proteins = 0
Runtime.syncNaturalRecovery(bodyDamage, recoveryState)
Support.assertClose(healingRates.standard, 0.0017, 0.000001,
    "protein depletion slows natural recovery without a direct HP write")
Support.assertEqual(foodTimerWrites, 0, "nutrition recovery never starts the Food Eaten heal timer")
healingRates.standard = 0.003
recoveryState.proteins = Metabolism.getProteinAdequacyMax(80)
recoveryState.fuel = 1000
Runtime.syncNaturalRecovery(bodyDamage, recoveryState)
Support.assertClose(healingRates.standard, 0.003, 0.000001,
    "NMS yields a healing field when another mod changes it")

local workload = { averageMet = 3, peakMet = 3, source = "reconnect-test" }
Support.assertTrue(Runtime.reportPlayerWorkload(player, workload, 100, "before-reconnect", 30, "session-one") ~= nil,
    "first client session workload is accepted")
local cache = Runtime.getActivityCache(player)
Support.assertEqual(cache.reportedWorkloadSeq, 30, "server remembers the first session sequence")
Runtime.markPlayerSessionResumed(player, "create-player")
Support.assertEqual(cache.reportedWorkloadSeq, 30, "snapshot request does not decide the workload session")
Support.assertTrue(Runtime.reportPlayerWorkload(player, workload, 100, "after-reconnect", 1, "session-two") ~= nil,
    "new workload session can restart its sequence at one")
Support.assertEqual(cache.reportedWorkloadSeq, 1, "server tracks the new session sequence")
Support.assertEqual(cache.reportedWorkloadSessionId, "session-two", "server tracks the new session token")
Support.assertNil(Runtime.reportPlayerWorkload(player, workload, 100, "late-old-session", 31, "session-one"),
    "late reports from a retired session cannot replace the new session")
Support.assertNil(Runtime.reportPlayerWorkload(player, workload, 100, "duplicate", 1, "session-two"),
    "duplicate reports within one session are rejected")
