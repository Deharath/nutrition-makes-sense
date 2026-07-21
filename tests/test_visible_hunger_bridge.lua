local Support = require "support"
local Metabolism = require "NutritionMakesSense_Metabolism"
local Runtime = require "NutritionMakesSense_MetabolismRuntime"

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
    lastSyncedHunger = 0.19,
})

Support.assertEqual(Runtime.syncVisibleHunger(player, state, "modeled-advance"), true,
    "modeled hunger gain should sync outward")
Support.assertClose(state.visibleHunger, 0.20, 0.000001,
    "stale vanilla value must not erase modeled hunger gain")
Support.assertClose(getLiveHunger(), 0.20, 0.000001,
    "modeled hunger gain reaches the vanilla stat")
Support.assertClose(state.lastSyncedHunger, 0.20, 0.000001,
    "successful sync advances the live reference")

local eatingPlayer, getPostMealHunger = makePlayer(0.05)
local eatingState = Metabolism.newState({
    visibleHunger = 0.20,
    lastSyncedHunger = 0.20,
})

Support.assertEqual(Runtime.syncVisibleHunger(eatingPlayer, eatingState, "food-observation"), false,
    "vanilla food drop should be imported instead of overwritten")
Support.assertClose(eatingState.visibleHunger, 0.05, 0.000001,
    "real vanilla food drop becomes authoritative visible hunger")
Support.assertClose(eatingState.pendingObservedHungerDrop, 0.15, 0.000001,
    "food drop remains available for the delayed nutrition deposit")
Support.assertClose(eatingState.lastSyncedHunger, 0.05, 0.000001,
    "imported food drop advances the live reference")
Support.assertClose(getPostMealHunger(), 0.05, 0.000001,
    "food drop remains visible to the player")

print("nms visible hunger bridge characterization passed")
