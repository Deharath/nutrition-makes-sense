NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_MetabolismRuntime"
require "NutritionMakesSense_CoreUtils"
require "NutritionMakesSense_DebugSupport"
require "TimedActions/ISEatFoodAction"
require "TimedActions/ISDrinkFluidAction"

local MealPrediction = NutritionMakesSense.MealPrediction or {}
NutritionMakesSense.MealPrediction = MealPrediction

local Metabolism = NutritionMakesSense.Metabolism or {}
local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local CoreUtils = NutritionMakesSense.CoreUtils or {}
local DebugSupport = NutritionMakesSense.DebugSupport or {}
local safeCall = CoreUtils.safeCall

local function isPureClient()
    return type(isClient) == "function" and isClient() == true
        and not (type(isServer) == "function" and isServer() == true)
end

local function getVisibleHunger(playerObj)
    local stats = safeCall(playerObj, "getStats")
    if not stats then
        return nil
    end
    if CharacterStat and CharacterStat.HUNGER then
        local value = safeCall(stats, "get", CharacterStat.HUNGER)
        if value ~= nil then
            return tonumber(value)
        end
    end
    return tonumber(safeCall(stats, "getHunger"))
end

local function readFoodValues(source, fraction, label)
    if not source then
        return nil
    end
    return Metabolism.scaleFoodValues({
        hunger = tonumber(safeCall(source, "getHungerChange") or safeCall(source, "getHungChange")) or 0,
        baseHunger = tonumber(safeCall(source, "getBaseHunger") or safeCall(source, "getHungerChange")) or 0,
        kcal = tonumber(safeCall(source, "getCalories")) or 0,
        carbs = tonumber(safeCall(source, "getCarbohydrates")) or 0,
        fats = tonumber(safeCall(source, "getLipids")) or 0,
        proteins = tonumber(safeCall(source, "getProteins")) or 0,
        label = label,
    }, fraction or 1)
end

function MealPrediction.buildFoodActionValues(action)
    local item = action and action.item or nil
    return readFoodValues(
        item,
        tonumber(action and action.percentage) or 1,
        tostring(safeCall(item, "getFullType") or "eat-action")
    )
end

function MealPrediction.buildFluidActionValues(action)
    local fluidContainer = action and action.fluidContainer or nil
    local properties = safeCall(fluidContainer, "getProperties")
    local item = action and action.item or nil
    return readFoodValues(
        properties,
        tonumber(action and action.percentage) or 1,
        tostring(safeCall(item, "getFullType") or "drink-action")
    )
end

function MealPrediction.apply(action, values, reason, preVisibleHunger)
    if not isPureClient() or not action or not action.character or type(values) ~= "table" then
        return nil
    end

    local preHunger = tonumber(preVisibleHunger)
    local postHunger = getVisibleHunger(action.character)
    if preHunger == nil or postHunger == nil then
        return nil
    end

    preHunger = Metabolism.clamp(preHunger, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
    postHunger = Metabolism.clamp(postHunger, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
    local observedDrop = math.max(0, preHunger - postHunger)
    local fullness = Metabolism.resolveMealHunger(values, observedDrop, preHunger)

    if type(Runtime.applyVisibleHungerTarget) == "function" then
        Runtime.applyVisibleHungerTarget(action.character, fullness.targetVisibleHunger, reason or "client-meal-prediction")
    end

    local report = {
        reason = tostring(reason or "client-meal-prediction"),
        preVisibleHunger = fullness.preVisibleHunger,
        vanillaVisibleHunger = postHunger,
        targetVisibleHunger = fullness.targetVisibleHunger,
        mechanicalDrop = fullness.mechanicalDrop,
        physicalDrop = fullness.physicalDrop,
        nutrientDrop = fullness.nutrientDrop,
        targetDrop = fullness.targetDrop,
        appliedDrop = fullness.appliedDrop,
        appliedCorrection = fullness.appliedCorrection,
        kcal = tonumber(values.kcal) or 0,
        carbs = tonumber(values.carbs) or 0,
        fats = tonumber(values.fats) or 0,
        proteins = tonumber(values.proteins) or 0,
    }
    action.nmsMealPrediction = report

    local mpClient = NutritionMakesSense.MPClientRuntime or {}
    if type(mpClient.noteMealPrediction) == "function" then
        mpClient.noteMealPrediction(action.character, report)
    end

    if math.abs(fullness.appliedCorrection) > 0.000001 and type(DebugSupport.noteHungerSyncEvent) == "function" then
        DebugSupport.noteHungerSyncEvent({
            reason = report.reason,
            provenance = "client-meal-prediction",
            consume_source = "client-action-prediction",
            pre_visible_hunger = fullness.preVisibleHunger,
            vanilla_visible_hunger = postHunger,
            target_visible_hunger = fullness.targetVisibleHunger,
            kcal = report.kcal,
            carbs = report.carbs,
            fats = report.fats,
            proteins = report.proteins,
            observed_hunger_drop = observedDrop,
            hunger_observed = observedDrop > 0,
            mechanical_hunger_drop = fullness.mechanicalDrop,
            physical_hunger_drop = fullness.physicalDrop,
            nutrient_hunger_drop = fullness.nutrientDrop,
            modeled_hunger_drop = fullness.targetDrop,
            applied_hunger_drop = fullness.appliedDrop,
            hunger_correction = fullness.appliedCorrection,
            meal_transaction_kcal = report.kcal,
            meal_transaction_fragments = 1,
        })
    end

    return report
end

function MealPrediction.suppressFoodEaten(action)
    local playerObj = action and action.character or nil
    local bodyDamage = safeCall(playerObj, "getBodyDamage")
    if not bodyDamage or type(Runtime.suppressFoodEatenTimer) ~= "function" then
        return false
    end
    return Runtime.suppressFoodEatenTimer(bodyDamage) == true
end

local function installEatActionHook()
    if MealPrediction._eatActionInstalled then
        return true
    end
    if type(ISEatFoodAction) ~= "table" or type(ISEatFoodAction.complete) ~= "function" then
        return false
    end

    MealPrediction._eatActionInstalled = true
    MealPrediction._originalEatActionComplete = ISEatFoodAction.complete
    local originalComplete = MealPrediction._originalEatActionComplete
    ISEatFoodAction.complete = function(action)
        local preHunger = getVisibleHunger(action and action.character or nil)
        local values = MealPrediction.buildFoodActionValues(action)
        local result = originalComplete(action)
        if result ~= false then
            MealPrediction.suppressFoodEaten(action)
            MealPrediction.apply(action, values, "client-eat-prediction", preHunger)
        end
        return result
    end
    return true
end

local function installDrinkActionHook()
    if MealPrediction._drinkActionInstalled then
        return true
    end
    if type(ISDrinkFluidAction) ~= "table" or type(ISDrinkFluidAction.complete) ~= "function" then
        return false
    end

    MealPrediction._drinkActionInstalled = true
    MealPrediction._originalDrinkActionComplete = ISDrinkFluidAction.complete
    local originalComplete = MealPrediction._originalDrinkActionComplete
    ISDrinkFluidAction.complete = function(action)
        local preHunger = getVisibleHunger(action and action.character or nil)
        local values = MealPrediction.buildFluidActionValues(action)
        local result = originalComplete(action)
        if result ~= false then
            MealPrediction.suppressFoodEaten(action)
            MealPrediction.apply(action, values, "client-drink-prediction", preHunger)
        end
        return result
    end
    return true
end

function MealPrediction.install()
    installEatActionHook()
    installDrinkActionHook()
    return MealPrediction._eatActionInstalled == true and MealPrediction._drinkActionInstalled == true
end

MealPrediction.isPureClient = isPureClient
MealPrediction.getVisibleHunger = getVisibleHunger

return MealPrediction
