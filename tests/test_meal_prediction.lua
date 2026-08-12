local function scriptDir()
    local source = debug.getinfo(1, "S").source or ""
    source = source:gsub("^@", "")
    return source:match("^(.*)/[^/]+$")
end

local root = scriptDir():gsub("/tests$", "")
package.path = table.concat({
    root .. "/common/media/lua/shared/?.lua",
    root .. "/common/media/lua/client/hooks/?.lua",
    root .. "/common/media/lua/client/dev/?.lua",
    package.path,
}, ";")

local Support = require "support"

NutritionMakesSense = { log = function() end }
CharacterStat = { HUNGER = "hunger" }
isClient = function() return true end
local serverRuntime = false
isServer = function() return serverRuntime end

local hunger = 0.30
local foodEatenTimer = 0
local eatCalls = 0
local drinkCalls = 0
ISEatFoodAction = {
    complete = function(action)
        eatCalls = eatCalls + 1
        hunger = tonumber(action.vanillaTarget) or hunger
        foodEatenTimer = tonumber(action.vanillaFoodEatenTimer) or 100
        return action.completeResult
    end,
}
package.preload["TimedActions/ISEatFoodAction"] = function() return ISEatFoodAction end
ISDrinkFluidAction = {
    complete = function(action)
        drinkCalls = drinkCalls + 1
        hunger = tonumber(action.vanillaTarget) or hunger
        foodEatenTimer = tonumber(action.vanillaFoodEatenTimer) or 100
        return action.completeResult
    end,
}
package.preload["TimedActions/ISDrinkFluidAction"] = function() return ISDrinkFluidAction end

local stats = {
    get = function(_, key)
        if key == CharacterStat.HUNGER then return hunger end
    end,
}
local bodyDamage = {
    getHealthFromFoodTimer = function() return foodEatenTimer end,
    setHealthFromFoodTimer = function(_, value) foodEatenTimer = value end,
}
local player = {
    getStats = function() return stats end,
    getBodyDamage = function() return bodyDamage end,
}
local grapefruit = {
    isFood = function() return true end,
    getFullType = function() return "Base.Grapefruit" end,
    getDisplayName = function() return "Grapefruit" end,
    getID = function() return 17 end,
    getHungerChange = function() return -0.20 end,
    getBaseHunger = function() return -0.20 end,
    getCalories = function() return 80 end,
    getCarbohydrates = function() return 20 end,
    getLipids = function() return 0.2 end,
    getProteins = function() return 1.6 end,
    getCurrentUsesFloat = function() return 1 end,
    getMaxUses = function() return 1 end,
    isCooked = function() return false end,
    isBurnt = function() return false end,
    isFrozen = function() return false end,
    isRotten = function() return false end,
    getExtraItems = function() return {} end,
    getSpices = function() return {} end,
    getChef = function() return "" end,
}

local MealPrediction = require "NutritionMakesSense_MealPrediction"
local appliedTarget = nil
local notedPrediction = nil
NutritionMakesSense.MPClientRuntime = {
    noteMealPrediction = function(_, report)
        notedPrediction = report
        return true
    end,
}
NutritionMakesSense.MetabolismRuntime.applyVisibleHungerTarget = function(_, target)
    appliedTarget = target
    hunger = target
    return true
end

Support.assertEqual(MealPrediction.install(), true, "meal prediction hooks install")
Support.assertEqual(MealPrediction.install(), true, "meal prediction hooks are idempotent")
local action = {
    item = grapefruit,
    character = player,
    percentage = 1,
    vanillaTarget = 0.10,
    completeResult = true,
}
local result = ISEatFoodAction.complete(action)
Support.assertEqual(result, true, "prediction preserves vanilla completion result")
Support.assertEqual(eatCalls, 1, "prediction calls vanilla eat exactly once")
Support.assertClose(action.nmsMealPrediction.mechanicalDrop, 0.20, 0.000001,
    "prediction observes the raw grapefruit drop")
Support.assertClose(action.nmsMealPrediction.targetDrop, 0.12, 0.000001,
    "prediction uses bounded grapefruit fullness")
Support.assertClose(appliedTarget, 0.18, 0.000001,
    "prediction corrects the local client immediately")
Support.assertEqual(notedPrediction, action.nmsMealPrediction,
    "prediction registers its target with MP snapshot reconciliation")
Support.assertClose(foodEatenTimer, 0, 0.000001,
    "successful eat suppresses the vanilla FoodEaten timer before it can render")

hunger = 0.30
foodEatenTimer = 17
local rejectedAction = {
    item = grapefruit,
    character = player,
    percentage = 1,
    vanillaTarget = 0.30,
    completeResult = false,
}
Support.assertEqual(ISEatFoodAction.complete(rejectedAction), false,
    "prediction preserves a rejected completion")
Support.assertNil(rejectedAction.nmsMealPrediction,
    "rejected completion does not create fullness")
Support.assertClose(foodEatenTimer, 100, 0.000001,
    "rejected completion leaves the vanilla action result untouched")

local fluidProperties = {
    getHungerChange = function() return -0.04 end,
    getCalories = function() return 600 end,
    getCarbohydrates = function() return 65 end,
    getLipids = function() return 20 end,
    getProteins = function() return 35 end,
}
local fluidContainer = { getProperties = function() return fluidProperties end }
hunger = 0.35
local drinkAction = {
    item = grapefruit,
    character = player,
    fluidContainer = fluidContainer,
    percentage = 1,
    vanillaTarget = 0.31,
    completeResult = "drink-ok",
}
local drinkResult = ISDrinkFluidAction.complete(drinkAction)
Support.assertEqual(drinkResult, "drink-ok", "drink prediction preserves completion result")
Support.assertEqual(drinkCalls, 1, "prediction calls vanilla drink exactly once")
Support.assertTrue(drinkAction.nmsMealPrediction.targetDrop > 0.28,
    "nutrition-rich fluid receives a real fullness target")
Support.assertTrue(hunger < 0.07,
    "nutrition-rich fluid prediction reaches the local player without waiting for a snapshot")
Support.assertClose(foodEatenTimer, 0, 0.000001,
    "successful drink suppresses the vanilla FoodEaten timer before it can render")

serverRuntime = true
hunger = 0.30
foodEatenTimer = 0
local hostAction = {
    item = grapefruit,
    character = player,
    percentage = 1,
    vanillaTarget = 0.10,
    completeResult = true,
}
ISEatFoodAction.complete(hostAction)
Support.assertClose(hunger, 0.10, 0.000001,
    "listen-server authority is not changed by client prediction")
Support.assertNil(hostAction.nmsMealPrediction,
    "listen-server actions wait for the authoritative observed-delta path")
Support.assertClose(foodEatenTimer, 0, 0.000001,
    "listen-server actions suppress FoodEaten immediately even without client prediction")

serverRuntime = false
local DebugSupport = require "NutritionMakesSense_DebugSupport"
local capturedFoodEvent = nil
DebugSupport.registerEventSink("meal-prediction-food-debug", {
    noteFoodActionEvent = function(event) capturedFoodEvent = event end,
})
local FoodDebug = require "NutritionMakesSense_FoodDebug"
Support.assertEqual(FoodDebug.install(), true, "dev telemetry wraps the prediction hook")
hunger = 0.30
ISEatFoodAction.complete({
    item = grapefruit,
    character = player,
    percentage = 1,
    vanillaTarget = 0.10,
    completeResult = true,
})
Support.assertClose(capturedFoodEvent.observed_hunger_drop, 0.20, 0.000001,
    "dev telemetry retains pre-correction vanilla evidence")
Support.assertClose(capturedFoodEvent.modeled_hunger_drop, 0.12, 0.000001,
    "dev telemetry records the predicted NMS target")
Support.assertClose(capturedFoodEvent.target_visible_hunger, 0.18, 0.000001,
    "dev telemetry records the corrected local target")
DebugSupport.unregisterEventSink("meal-prediction-food-debug")

print("nms meal prediction characterization passed")
