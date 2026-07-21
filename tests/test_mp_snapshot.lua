local Support = require "support"
local Metabolism = require "NutritionMakesSense_Metabolism"
local Snapshot = require "NutritionMakesSense_MPSnapshot"

local state = Metabolism.newState({
    initialized = true,
    fuel = 750,
    proteins = 200,
    weightKg = 82,
    visibleHunger = 0.3,
})
state.lastActiveElapsedHours = 0.1
state.lastRawElapsedHours = 4
state.lastElapsedMode = "runtime-stall-clamp"
state.lastMetAverage = 2.4
state.lastMealHungerDrop = 0.22
state.lastMealHungerObserved = true
state.depositSequence = 12
state.baseHealthFromFood = 0.015
state.runtimeOnlySentinel = "must-not-cross-network"

local encoded = Snapshot.copyState(state)
Support.assertClose(encoded.fuel, 750, 0.000001, "snapshot fuel")
Support.assertClose(encoded.weightKg, 82, 0.000001, "snapshot weight")
Support.assertClose(encoded.visibleHunger, 0.3, 0.000001, "snapshot hunger")
Support.assertNil(encoded.lastMetAverage, "release snapshots must omit diagnostics")
Support.assertNil(encoded.lastActiveElapsedHours, "elapsed runtime telemetry must stay local")
Support.assertNil(encoded.lastRawElapsedHours, "raw clock telemetry must stay local")
Support.assertNil(encoded.lastElapsedMode, "elapsed mode must stay local")
Support.assertNil(encoded.baseHealthFromFood, "client healing baseline must stay local")
Support.assertNil(encoded.runtimeOnlySentinel, "unregistered fields must stay local")

local diagnostic = Snapshot.copyState(state, true)
Support.assertClose(diagnostic.lastMetAverage, 2.4, 0.000001, "dev snapshot diagnostics")
Support.assertClose(diagnostic.lastMealHungerDrop, 0.22, 0.000001, "dev snapshot observed meal fullness")
Support.assertEqual(diagnostic.lastMealHungerObserved, true, "dev snapshot meal fullness provenance")
Support.assertEqual(diagnostic.depositSequence, 12, "dev snapshots include deposit sequencing")
Support.assertNil(diagnostic.lastActiveElapsedHours, "dev snapshots still exclude runtime-only telemetry")

local restored = Metabolism.ensureState(encoded)
Support.assertClose(restored.fuel, state.fuel, 0.000001, "snapshot round-trip fuel")
Support.assertClose(restored.proteins, state.proteins, 0.000001, "snapshot round-trip proteins")
Support.assertClose(restored.weightKg, state.weightKg, 0.000001, "snapshot round-trip weight")
Support.assertClose(restored.visibleHunger, state.visibleHunger, 0.000001, "snapshot round-trip hunger")

print("nms MP snapshot contract passed")
