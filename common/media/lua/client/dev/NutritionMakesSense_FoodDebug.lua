NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_CoreUtils"

local FoodDebug = NutritionMakesSense.FoodDebug or {}
NutritionMakesSense.FoodDebug = FoodDebug

local safeCall = NutritionMakesSense.CoreUtils.safeCall

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
