local function scriptDir()
    local source = debug.getinfo(1, "S").source or ""
    source = source:gsub("^@", "")
    return source:match("^(.*)/[^/]+$")
end

local root = scriptDir():gsub("/tests$", "")
package.path = table.concat({
    root .. "/common/media/lua/shared/?.lua",
    root .. "/common/media/lua/client/dev/?.lua",
    package.path,
}, ";")

local Support = require "support"

NutritionMakesSense = { log = function() end }
CharacterStat = { HUNGER = "hunger" }

local hunger = 0.4
local originalCalls = 0
local originalDrinkCalls = 0
ISEatFoodAction = {
    complete = function(action)
        originalCalls = originalCalls + 1
        hunger = 0.2
        return action.completeResult
    end,
}
package.preload["TimedActions/ISEatFoodAction"] = function()
    return ISEatFoodAction
end
ISDrinkFluidAction = {
    complete = function(action)
        originalDrinkCalls = originalDrinkCalls + 1
        hunger = 0.1
        return action.completeResult
    end,
}
package.preload["TimedActions/ISDrinkFluidAction"] = function()
    return ISDrinkFluidAction
end

local DebugSupport = require "NutritionMakesSense_DebugSupport"
local captured = nil
DebugSupport.registerEventSink("food-test", {
    noteFoodActionEvent = function(event) captured = event end,
})

local stats = {
    get = function(_, key)
        if key == CharacterStat.HUNGER then return hunger end
    end,
}
local player = { getStats = function() return stats end }
local item = {
    isFood = function() return true end,
    getFullType = function() return "SapphCooking.TestMeal" end,
    getDisplayName = function() return "Test Meal" end,
    getID = function() return 42 end,
    getHungerChange = function() return -0.35 end,
    getBaseHunger = function() return -0.40 end,
    getCalories = function() return 700 end,
    getCarbohydrates = function() return 60 end,
    getLipids = function() return 30 end,
    getProteins = function() return 25 end,
    getCurrentUsesFloat = function() return 1 end,
    getMaxUses = function() return 1 end,
    isCooked = function() return true end,
    isBurnt = function() return false end,
    isFrozen = function() return false end,
    isRotten = function() return false end,
    getExtraItems = function() return { "Base.Pork", "Base.Vegetables" } end,
    getSpices = function() return { "Base.Salt" } end,
    getChef = function() return "Recorder" end,
}

local FoodDebug = require "NutritionMakesSense_FoodDebug"
Support.assertEqual(FoodDebug.install(), true, "food telemetry hook installs")
Support.assertEqual(FoodDebug.install(), true, "food telemetry hook is idempotent")
local result = ISEatFoodAction.complete({
    item = item,
    character = player,
    percentage = 0.5,
    completeResult = true,
})

Support.assertEqual(result, true, "food telemetry preserves vanilla completion result")
Support.assertEqual(originalCalls, 1, "food telemetry invokes vanilla completion once")
Support.assertEqual(captured.item, "SapphCooking.TestMeal", "food telemetry captures full type")
Support.assertEqual(captured.item_name, "Test Meal", "food telemetry captures display name")
Support.assertClose(captured.fraction, 0.5, 0.000001, "food telemetry captures eaten fraction")
Support.assertClose(captured.pre_visible_hunger, 0.4, 0.000001, "food telemetry captures hunger before vanilla eat")
Support.assertClose(captured.target_visible_hunger, 0.2, 0.000001, "food telemetry captures hunger after vanilla eat")
Support.assertClose(captured.observed_hunger_drop, 0.2, 0.000001, "food telemetry captures vanilla hunger drop")
Support.assertClose(captured.item_kcal, 700, 0.000001, "food telemetry captures live item calories")
Support.assertEqual(captured.item_ingredients, "Base.Pork, Base.Vegetables", "food telemetry captures ingredients")

hunger = 0.2
local fluidProperties = {
    getHungerChange = function() return -0.1 end,
    getCalories = function() return 180 end,
    getCarbohydrates = function() return 20 end,
    getLipids = function() return 5 end,
    getProteins = function() return 3 end,
}
local fluidContainer = {
    getProperties = function() return fluidProperties end,
    getFilledRatio = function() return 0.75 end,
}
local drinkResult = ISDrinkFluidAction.complete({
    item = item,
    character = player,
    fluidContainer = fluidContainer,
    percentage = 0.25,
    completeResult = true,
})
Support.assertEqual(drinkResult, true, "fluid telemetry preserves vanilla completion result")
Support.assertEqual(originalDrinkCalls, 1, "fluid telemetry invokes vanilla completion once")
Support.assertEqual(captured.reason, "drink-action-complete", "fluid telemetry identifies drink completion")
Support.assertClose(captured.item_kcal, 180, 0.000001, "fluid telemetry captures live fluid calories")
Support.assertClose(captured.observed_hunger_drop, 0.1, 0.000001, "fluid telemetry captures vanilla hunger drop")

DebugSupport.unregisterEventSink("food-test")
print("nms food telemetry characterization passed")
