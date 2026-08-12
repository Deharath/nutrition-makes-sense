local Support = require "support"
local Metabolism = require "NutritionMakesSense_Metabolism"
local Snapshot = require "NutritionMakesSense_MPSnapshot"

local state = Metabolism.newState({
    initialized = true,
    fuel = 750,
    proteins = 200,
    weightKg = 82,
    weightController = -0.4,
    weightBalanceKcal = -4660,
    visibleHunger = 0.3,
})
state.lastMetAverage = 2.4
state.lastMealHungerDrop = 0.22
state.lastMealModeledDrop = 0.31
state.lastMealDepositKcal = 600
state.lastMealTransactionFragments = 3
state.lastMealMechanicalDrop = 0.08
state.lastMealPhysicalDrop = 0.08
state.lastMealNutrientDrop = 0.31
state.lastMealPreHunger = 0.22
state.lastMealTargetHunger = 0
state.lastEnergyAppetiteProgress = 0.45
state.lastEnergyAppetiteRatePerHour = 0.01125
state.lastDeprivationTarget = 0.55
state.depositSequence = 12
state.totalIntakeKcal = 4200
state.totalBurnKcal = 3900
state.totalVisibleHungerGain = 0.8
state.totalObservedHours = 24
state.totalSleepHours = 7
state.lastSyncedHunger = 0.29
state.baseHealthFromFood = 0.015
state.runtimeOnlySentinel = "must-not-cross-network"
state.pendingMealTransaction = { kcal = 80, fragments = 2 }

local encoded = Snapshot.copyState(state)
Support.assertClose(encoded.fuel, 750, 0.000001, "snapshot fuel")
Support.assertClose(encoded.weightKg, 82, 0.000001, "snapshot weight")
Support.assertClose(encoded.visibleHunger, 0.3, 0.000001, "snapshot hunger")
Support.assertClose(encoded.weightBalanceKcal, -4660, 0.000001,
    "release snapshots carry the durable recent-energy balance")
Support.assertClose(encoded.weightController, -0.4, 0.000001,
    "release snapshots carry the durable weight controller")
Support.assertEqual(encoded.depositSequence, 12,
    "release snapshots carry meal causality for client prediction reconciliation")
Support.assertClose(encoded.lastDeprivationTarget, 0.55, 0.000001,
    "release snapshots preserve the authoritative deprivation direction")
Support.assertNil(encoded.lastMetAverage, "release snapshots must omit diagnostics")
Support.assertNil(encoded.baseHealthFromFood, "client healing baseline must stay local")
Support.assertNil(encoded.runtimeOnlySentinel, "unregistered fields must stay local")
Support.assertNil(encoded.pendingMealTransaction, "meal transaction state must stay authority-local")

local diagnostic = Snapshot.copyState(state, true)
Support.assertClose(diagnostic.lastMetAverage, 2.4, 0.000001, "dev snapshot diagnostics")
Support.assertClose(diagnostic.lastMealHungerDrop, 0.22, 0.000001, "dev snapshot applied meal fullness")
Support.assertClose(diagnostic.lastMealModeledDrop, 0.31, 0.000001, "dev snapshot modeled meal fullness")
Support.assertClose(diagnostic.lastMealDepositKcal, 600, 0.000001, "dev snapshot complete meal deposit")
Support.assertEqual(diagnostic.lastMealTransactionFragments, 3, "dev snapshot meal fragment count")
Support.assertClose(diagnostic.lastMealMechanicalDrop, 0.08, 0.000001, "dev snapshot raw mechanical fullness")
Support.assertClose(diagnostic.lastMealPhysicalDrop, 0.08, 0.000001, "dev snapshot bounded physical fullness")
Support.assertClose(diagnostic.lastMealNutrientDrop, 0.31, 0.000001, "dev snapshot nutrient fullness")
Support.assertClose(diagnostic.lastEnergyAppetiteProgress, 0.45, 0.000001, "dev snapshot balance appetite pressure")
Support.assertClose(diagnostic.lastEnergyAppetiteRatePerHour, 0.01125, 0.000001, "dev snapshot balance appetite rate")
Support.assertEqual(diagnostic.depositSequence, 12, "dev snapshots retain deposit sequencing")
Support.assertClose(diagnostic.totalIntakeKcal, 4200, 0.000001, "dev snapshots include exact intake ledger")
Support.assertClose(diagnostic.totalBurnKcal, 3900, 0.000001, "dev snapshots include exact burn ledger")
Support.assertClose(diagnostic.totalVisibleHungerGain, 0.8, 0.000001, "dev snapshots include hunger ledger")
Support.assertClose(diagnostic.totalObservedHours, 24, 0.000001, "dev snapshots include observed hours")
Support.assertClose(diagnostic.totalSleepHours, 7, 0.000001, "dev snapshots include sleep hours")
Support.assertClose(diagnostic.lastSyncedHunger, 0.29, 0.000001, "dev snapshots include hunger sync state")
Support.assertNil(diagnostic.pendingMealTransaction, "dev snapshots exclude in-flight meal transactions")

local restored = Metabolism.ensureState(encoded)
Support.assertClose(restored.fuel, state.fuel, 0.000001, "snapshot round-trip fuel")
Support.assertClose(restored.proteins, state.proteins, 0.000001, "snapshot round-trip proteins")
Support.assertClose(restored.weightKg, state.weightKg, 0.000001, "snapshot round-trip weight")
Support.assertClose(restored.visibleHunger, state.visibleHunger, 0.000001, "snapshot round-trip hunger")

print("nms MP snapshot contract passed")
