local Support = require "support"
local Metabolism = require "NutritionMakesSense_Metabolism"
NutritionMakesSense.log = function() end
local Runtime = require "NutritionMakesSense_MetabolismRuntime"

SandboxOptions = {
    instance = {
        getStatsDecreaseMultiplier = function()
            return 0.65
        end,
    },
}
Support.assertClose(Runtime.resolveStatsDecreaseMultiplier(), 0.65, 0.000001,
    "runtime must read the current vanilla stats decrease multiplier")
SandboxOptions = nil
Support.assertClose(Runtime.resolveStatsDecreaseMultiplier(), 1.0, 0.000001,
    "runtime must use the vanilla normal rate when sandbox options are unavailable")

local function makePlayer(initialHunger)
    local liveHunger = initialHunger
    local stats = {
        getHunger = function()
            return liveHunger
        end,
        setHunger = function(_, value)
            liveHunger = value
        end,
    }
    local player = {
        getStats = function()
            return stats
        end,
        isGodMod = function()
            return false
        end,
    }
    return player, function()
        return liveHunger
    end
end

local player, getLiveHunger = makePlayer(0.19)
local state = Metabolism.newState({
    visibleHunger = 0.20,
})
local stateTelemetry = Runtime.replaceTelemetryForState(state, { lastSyncedHunger = 0.19 })

Support.assertEqual(Runtime.syncVisibleHunger(player, state, "modeled-advance"), true,
    "modeled hunger gain should sync outward")
Support.assertClose(state.visibleHunger, 0.20, 0.000001,
    "stale vanilla value must not erase modeled hunger gain")
Support.assertClose(getLiveHunger(), 0.20, 0.000001,
    "modeled hunger gain reaches the vanilla stat")
Support.assertClose(stateTelemetry.lastSyncedHunger, 0.20, 0.000001,
    "successful sync advances the live reference")

local eatingPlayer, getPostMealHunger = makePlayer(0.05)
local eatingState = Metabolism.newState({
    visibleHunger = 0.20,
})
local eatingTelemetry = Runtime.replaceTelemetryForState(eatingState, { lastSyncedHunger = 0.20 })

Support.assertEqual(Runtime.syncVisibleHunger(eatingPlayer, eatingState, "food-observation"), false,
    "vanilla food drop should be imported instead of overwritten")
Support.assertClose(eatingState.visibleHunger, 0.05, 0.000001,
    "real vanilla food drop remains visible while its nutrition deposit is pending")
Support.assertClose(eatingTelemetry.pendingObservedHungerDrop, 0.15, 0.000001,
    "food drop remains available for the delayed nutrition deposit")
Support.assertClose(eatingTelemetry.pendingMealPreVisibleHunger, 0.20, 0.000001,
    "food observation retains the pre-meal baseline")
Support.assertClose(eatingTelemetry.lastSyncedHunger, 0.05, 0.000001,
    "imported food drop advances the live reference")
Support.assertClose(getPostMealHunger(), 0.05, 0.000001,
    "food drop remains visible to the player")

local grapefruit = {
    kcal = 80,
    carbs = 20,
    fats = 0.2,
    proteins = 1.6,
}
local grapefruitResolution = Runtime.finalizeMealObservation(
    eatingState,
    grapefruit,
    eatingTelemetry.pendingObservedHungerDrop,
    eatingTelemetry.pendingMealPreVisibleHunger,
    "grapefruit-test"
)
Support.assertClose(grapefruitResolution.targetDrop, 0.12, 0.000001,
    "grapefruit resolves to bounded modeled fullness")
Support.assertClose(eatingState.visibleHunger, 0.08, 0.000001,
    "modeled fullness replaces rather than stacks on the vanilla drop")
Support.assertClose(eatingTelemetry.lastMealMechanicalDrop, 0.15, 0.000001,
    "state preserves raw vanilla evidence")
Support.assertClose(eatingTelemetry.lastMealPhysicalDrop, 0.12, 0.000001,
    "state records bounded volume fullness")
Support.assertTrue(eatingTelemetry.lastMealNutrientDrop < eatingTelemetry.lastMealPhysicalDrop,
    "state records the distinct nutrient contribution")
Support.assertClose(grapefruitResolution.appliedCorrection, -0.03, 0.000001,
    "meal resolution reports the upward correction from vanilla grapefruit fullness")
Support.assertNil(eatingTelemetry.pendingMealPreVisibleHunger,
    "resolved meal clears its delayed baseline")
Support.assertEqual(Runtime.syncVisibleHunger(eatingPlayer, eatingState, "meal-resolution"), true,
    "resolved fullness syncs back to the vanilla stat")
Support.assertClose(getPostMealHunger(), 0.08, 0.000001,
    "player sees the resolved NMS hunger target")

local mealState = Metabolism.newState({ visibleHunger = 0.35 })
Runtime.replaceTelemetryForState(mealState, { lastSyncedHunger = 0.35 })
local mealResolution = Runtime.finalizeMealObservation(mealState, {
    kcal = 600,
    carbs = 65,
    fats = 20,
    proteins = 35,
}, 0.05, 0.35, "balanced-meal-test")
Support.assertTrue(mealResolution.targetDrop > 0.28,
    "high-energy balanced meal resolves beyond a weak raw hunger drop")
Support.assertTrue(mealState.visibleHunger < 0.07,
    "balanced meal leaves a hungry character comfortably fed")

local fallbackState = Metabolism.newState({ visibleHunger = 0.30 })
Runtime.replaceTelemetryForState(fallbackState, { lastSyncedHunger = 0.30 })
local fallbackResolution = Runtime.finalizeMealObservation(fallbackState, {
    kcal = 500,
    carbs = 55,
    fats = 18,
    proteins = 25,
}, 0, 0.30, "nutrition-only-test")
Support.assertTrue(fallbackResolution.targetDrop > 0.25,
    "missing HungerChange evidence still has a universal nutrition fallback")
Support.assertClose(fallbackResolution.mechanicalDrop, 0, 0.000001,
    "nutrition fallback retains missing-mechanical provenance")

local fragmentedState = Metabolism.newState({ visibleHunger = 0.70 })
local fragmentedTelemetry = Runtime.replaceTelemetryForState(fragmentedState, { lastSyncedHunger = 0.70 })
local fragmentedResolution = nil
for _ = 1, 10 do
    fragmentedResolution = Runtime.accumulateMealObservation(fragmentedState, {
        kcal = 60,
        carbs = 6.5,
        fats = 2,
        proteins = 3.5,
    }, 0.008, 0.70, "fragmented-drink-test")
end
local wholeDrink = Metabolism.getMealFullness({
    kcal = 600,
    carbs = 65,
    fats = 20,
    proteins = 35,
}, 0.08)
Support.assertClose(fragmentedResolution.targetDrop, wholeDrink.targetDrop, 0.000001,
    "fragmented fluid consumption resolves like one whole nutritional deposit")
Support.assertClose(fragmentedResolution.transactionKcal, 600, 0.000001,
    "meal transaction accumulates all fluid calories")
Support.assertEqual(fragmentedResolution.transactionFragments, 10,
    "meal transaction counts observed nutrition fragments")
Support.assertClose(fragmentedTelemetry.lastMealDepositKcal, 600, 0.000001,
    "state exposes the complete fragmented meal deposit")
Support.assertEqual(fragmentedTelemetry.lastMealTransactionFragments, 10,
    "state exposes the complete fragmented meal shape")
Support.assertClose(fragmentedTelemetry.lastSatietyContribution,
    Metabolism.getSatietyContribution({ kcal = 60, carbs = 6.5, fats = 2, proteins = 3.5 }, 1) * 10,
    0.000001,
    "fragmented meal diagnostics preserve the total satiety deposited")
Support.assertClose(fragmentedState.visibleHunger, 0.70 - wholeDrink.targetDrop, 0.000001,
    "fragmented fluid fullness replaces the cumulative target instead of stacking each slice")

local freshModData = {}
local freshStats = { getHunger = function() return 0.32 end }
local freshNutrition = {
    getCalories = function() return 500 end,
    getCarbohydrates = function() return 0 end,
    getLipids = function() return 0 end,
    getProteins = function() return 0 end,
    getWeight = function() return 92 end,
    setCalories = function() end,
    setCarbohydrates = function() end,
    setLipids = function() end,
    setProteins = function() end,
}
local freshPlayer = {
    getModData = function() return freshModData end,
    getStats = function() return freshStats end,
    getNutrition = function() return freshNutrition end,
}
local freshState = Runtime.ensureStateForPlayer(freshPlayer)
Support.assertEqual(freshState.initialized, true, "fresh player state is initialized")
Support.assertClose(freshState.fuel, 500, 0.000001, "fresh state seeds energy from vanilla nutrition")
Support.assertClose(freshState.weightKg, 92, 0.000001, "fresh state seeds authoritative weight")
Support.assertClose(freshState.visibleHunger, 0.32, 0.000001, "fresh state seeds visible hunger")
Support.assertNil(freshState.lastZone, "durable state does not persist a derivable energy zone")
local freshView = Runtime.getStateCopy(freshPlayer)
Support.assertEqual(freshView.lastZone, "Low", "runtime views derive the current energy zone")
Support.assertClose(freshView.lastMealPreHunger, 0.32, 0.000001,
    "fresh state initializes meal diagnostics from the visible baseline")

local mpLiveHunger = 0.10
local mpModData = {}
local mpStats = {
    getHunger = function() return mpLiveHunger end,
    setHunger = function(_, value) mpLiveHunger = value end,
}
local mpPlayer = {
    getStats = function() return mpStats end,
    getModData = function() return mpModData end,
    isGodMod = function() return false end,
}
local imported = Runtime.importStateSnapshot(mpPlayer, {
    state = {
        initialized = true,
        visibleHunger = 0.18,
        fuel = 900,
        proteins = Metabolism.DEFAULT_PROTEIN,
        weightKg = 80,
    },
}, "mp-authoritative-test")
Support.assertClose(mpLiveHunger, 0.18, 0.000001,
    "authoritative MP snapshot replaces a slightly different local prediction")
Support.assertClose(imported.lastSyncedHunger, 0.18, 0.000001,
    "authoritative MP snapshot advances the local hunger sync reference")
Support.assertNil(imported.pendingObservedHungerDrop,
    "snapshot correction does not create pending meal evidence")

print("nms visible hunger bridge characterization passed")
