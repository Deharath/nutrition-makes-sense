NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_CoreUtils"
require "NutritionMakesSense_DebugSupport"
require "TimedActions/ISEatFoodAction"
require "TimedActions/ISDrinkFluidAction"

local FoodDebug = NutritionMakesSense.FoodDebug or {}
NutritionMakesSense.FoodDebug = FoodDebug

local safeCall = NutritionMakesSense.CoreUtils.safeCall
local DebugSupport = NutritionMakesSense.DebugSupport or {}

local function log(message)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(message)
    else
        print("[NutritionMakesSense] " .. tostring(message))
    end
end

local function formatNumber(value, precision)
    local numeric = tonumber(value)
    if numeric == nil then
        return "nil"
    end
    return string.format("%." .. tostring(precision or 3) .. "f", numeric)
end

local function formatValues(item)
    if not item then
        return "nil"
    end

    local hunger = safeCall(item, "getHungerChange") or safeCall(item, "getHungChange")
    return string.format(
        "hunger=%s kcal=%s carbs=%s fats=%s proteins=%s",
        formatNumber(math.abs(tonumber(hunger) or 0), 3),
        formatNumber(safeCall(item, "getCalories"), 1),
        formatNumber(safeCall(item, "getCarbohydrates"), 3),
        formatNumber(safeCall(item, "getLipids"), 3),
        formatNumber(safeCall(item, "getProteins"), 3)
    )
end

local function summarizeCollection(collection)
    local values = {}
    if type(collection) == "table" then
        for _, value in pairs(collection) do
            values[#values + 1] = tostring(value)
        end
    else
        local size = tonumber(safeCall(collection, "size")) or 0
        for index = 0, size - 1 do
            values[#values + 1] = tostring(safeCall(collection, "get", index))
        end
    end
    return #values > 0 and table.concat(values, ", ") or "none"
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

local function getItemNumber(item, methodName)
    return tonumber(item and safeCall(item, methodName))
end

function FoodDebug.buildFoodActionEvent(action)
    local item = action and action.item or nil
    local playerObj = action and action.character or nil
    if not item or not FoodDebug.isFoodItem(item) then
        return nil
    end

    local fraction = tonumber(action and action.percentage) or 1
    local hungerChange = getItemNumber(item, "getHungerChange") or getItemNumber(item, "getHungChange")
    return {
        reason = "eat-action-complete",
        consume_source = "client-eat-action",
        provenance = "client-item-instance",
        item = tostring(safeCall(item, "getFullType") or item),
        item_name = tostring(safeCall(item, "getDisplayName") or ""),
        item_id = tostring(safeCall(item, "getID") or ""),
        item_known = true,
        fraction = fraction,
        pre_visible_hunger = getVisibleHunger(playerObj),
        item_hunger_change = hungerChange,
        item_base_hunger = getItemNumber(item, "getBaseHunger"),
        item_kcal = getItemNumber(item, "getCalories"),
        item_carbs = getItemNumber(item, "getCarbohydrates"),
        item_fats = getItemNumber(item, "getLipids"),
        item_proteins = getItemNumber(item, "getProteins"),
        item_uses = getItemNumber(item, "getCurrentUsesFloat") or getItemNumber(item, "getCurrentUses"),
        item_max_uses = getItemNumber(item, "getMaxUses"),
        item_cooked = safeCall(item, "isCooked") == true,
        item_burnt = safeCall(item, "isBurnt") == true,
        item_frozen = safeCall(item, "isFrozen") == true,
        item_rotten = safeCall(item, "isRotten") == true,
        item_ingredients = summarizeCollection(safeCall(item, "getExtraItems")),
        item_spices = summarizeCollection(safeCall(item, "getSpices")),
        item_chef = tostring(safeCall(item, "getChef") or ""),
    }
end

function FoodDebug.buildFluidActionEvent(action)
    local item = action and action.item or nil
    local playerObj = action and action.character or nil
    local fluidContainer = action and action.fluidContainer or nil
    local properties = fluidContainer and safeCall(fluidContainer, "getProperties") or nil
    if not item or not properties then
        return nil
    end

    return {
        reason = "drink-action-complete",
        consume_source = "client-drink-action",
        provenance = "client-fluid-instance",
        item = tostring(safeCall(item, "getFullType") or item),
        item_name = tostring(safeCall(item, "getDisplayName") or ""),
        item_id = tostring(safeCall(item, "getID") or ""),
        item_known = true,
        fraction = tonumber(action and action.percentage) or 1,
        pre_visible_hunger = getVisibleHunger(playerObj),
        item_hunger_change = getItemNumber(properties, "getHungerChange"),
        item_base_hunger = getItemNumber(properties, "getHungerChange"),
        item_kcal = getItemNumber(properties, "getCalories"),
        item_carbs = getItemNumber(properties, "getCarbohydrates"),
        item_fats = getItemNumber(properties, "getLipids"),
        item_proteins = getItemNumber(properties, "getProteins"),
        item_uses = getItemNumber(fluidContainer, "getFilledRatio"),
        item_max_uses = 1,
        item_cooked = safeCall(item, "isCooked") == true,
        item_burnt = safeCall(item, "isBurnt") == true,
        item_frozen = safeCall(item, "isFrozen") == true,
        item_rotten = safeCall(item, "isRotten") == true,
        item_ingredients = summarizeCollection(safeCall(item, "getExtraItems")),
        item_spices = summarizeCollection(safeCall(item, "getSpices")),
        item_chef = tostring(safeCall(item, "getChef") or ""),
    }
end

function FoodDebug.install()
    if FoodDebug._eatActionInstalled and FoodDebug._drinkActionInstalled then
        return true
    end
    if type(ISEatFoodAction) ~= "table" or type(ISEatFoodAction.complete) ~= "function"
        or type(ISDrinkFluidAction) ~= "table" or type(ISDrinkFluidAction.complete) ~= "function" then
        return false
    end

    local function finishEvent(action, event)
        if not event then return end
        local prediction = action and action.nmsMealPrediction or nil
        event.target_visible_hunger = getVisibleHunger(action and action.character or nil)
        event.vanilla_visible_hunger = tonumber(prediction and prediction.vanillaVisibleHunger) or ""
        event.observed_hunger_drop = tonumber(prediction and prediction.mechanicalDrop) or math.max(
            0,
            (tonumber(event.pre_visible_hunger) or 0) - (tonumber(event.target_visible_hunger) or 0)
        )
        event.hunger_observed = event.observed_hunger_drop > 0
        if prediction then
            event.physical_hunger_drop = tonumber(prediction.physicalDrop) or 0
            event.nutrient_hunger_drop = tonumber(prediction.nutrientDrop) or 0
            event.modeled_hunger_drop = tonumber(prediction.targetDrop) or 0
            event.applied_hunger_drop = tonumber(prediction.appliedDrop) or 0
            event.hunger_correction = tonumber(prediction.appliedCorrection) or 0
            event.meal_transaction_kcal = tonumber(prediction.kcal) or 0
            event.meal_transaction_fragments = 1
        end
        if type(DebugSupport.noteFoodActionEvent) == "function" then
            DebugSupport.noteFoodActionEvent(event)
        end
    end

    if not FoodDebug._eatActionInstalled then
        FoodDebug._eatActionInstalled = true
        FoodDebug._originalEatActionComplete = FoodDebug._originalEatActionComplete or ISEatFoodAction.complete
        local originalEatComplete = FoodDebug._originalEatActionComplete
        ISEatFoodAction.complete = function(action)
            local event = FoodDebug.buildFoodActionEvent(action)
            local result = originalEatComplete(action)
            finishEvent(action, event)
            return result
        end
    end

    if not FoodDebug._drinkActionInstalled then
        FoodDebug._drinkActionInstalled = true
        FoodDebug._originalDrinkActionComplete = FoodDebug._originalDrinkActionComplete or ISDrinkFluidAction.complete
        local originalDrinkComplete = FoodDebug._originalDrinkActionComplete
        ISDrinkFluidAction.complete = function(action)
            local event = FoodDebug.buildFluidActionEvent(action)
            local result = originalDrinkComplete(action)
            finishEvent(action, event)
            return result
        end
    end

    return true
end

local function makeScriptProbe(fullType)
    if not fullType or not InventoryItemFactory or type(InventoryItemFactory.CreateItem) ~= "function" then
        return nil
    end
    local ok, item = pcall(InventoryItemFactory.CreateItem, fullType)
    return ok and item or nil
end

function FoodDebug.resolveActualItems(items)
    if ISInventoryPane and type(ISInventoryPane.getActualItems) == "function" then
        local ok, actual = pcall(ISInventoryPane.getActualItems, items)
        if ok and type(actual) == "table" then
            return actual
        end
    end

    local actual = {}
    for _, item in ipairs(items or {}) do
        if item and type(item.items) == "table" then
            for _, grouped in ipairs(item.items) do
                actual[#actual + 1] = grouped
            end
        elseif item then
            actual[#actual + 1] = item
        end
    end
    return actual
end

function FoodDebug.isFoodItem(item)
    return safeCall(item, "isFood") == true or safeCall(item, "IsFood") == true
end

function FoodDebug.logItem(item)
    if not FoodDebug.isFoodItem(item) then
        return
    end

    local fullType = safeCall(item, "getFullType") or tostring(item)
    local probe = makeScriptProbe(fullType)
    log(string.format(
        "[FOOD_DEBUG] item=%s name=%s id=%s cooked=%s burnt=%s frozen=%s rotten=%s heat=%s uses=%s/%s",
        tostring(fullType),
        tostring(safeCall(item, "getDisplayName") or fullType),
        tostring(safeCall(item, "getID") or "nil"),
        tostring(safeCall(item, "isCooked") == true),
        tostring(safeCall(item, "isBurnt") == true),
        tostring(safeCall(item, "isFrozen") == true),
        tostring(safeCall(item, "isRotten") == true),
        formatNumber(safeCall(item, "getHeat"), 3),
        formatNumber(safeCall(item, "getCurrentUses"), 3),
        formatNumber(safeCall(item, "getMaxUses"), 3)
    ))
    log(string.format(
        "[FOOD_DEBUG] nutrition live={%s} script={%s} thirst=%s",
        formatValues(item),
        formatValues(probe),
        formatNumber(safeCall(item, "getThirstChange"), 3)
    ))
    log(string.format(
        "[FOOD_DEBUG] mood boredom=%s base=%s unhappy=%s base=%s",
        formatNumber(safeCall(item, "getBoredomChange"), 3),
        formatNumber(safeCall(item, "getBoredomChangeUnmodified"), 3),
        formatNumber(safeCall(item, "getUnhappyChange"), 3),
        formatNumber(safeCall(item, "getUnhappyChangeUnmodified"), 3)
    ))
    log(string.format(
        "[FOOD_DEBUG] composition ingredients=[%s] spices=[%s] chef=%s",
        summarizeCollection(safeCall(item, "getExtraItems")),
        summarizeCollection(safeCall(item, "getSpices")),
        tostring(safeCall(item, "getChef") or "none")
    ))
end

return FoodDebug
