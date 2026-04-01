NutritionMakesSense = NutritionMakesSense or {}

local Data = NutritionMakesSense.Data or {}
NutritionMakesSense.Data = Data

local FOOD_VALUES_MODULE = "generated/NutritionMakesSense_FoodValues"
local FOOD_SEMANTICS_MODULE = "generated/NutritionMakesSense_FoodSemantics"

local function loadEmbeddedFoodValues()
    local ok, rawData = pcall(require, FOOD_VALUES_MODULE)
    if ok and type(rawData) == "table" then
        return rawData
    end
    if type(NMS_FoodValues) == "table" then
        return NMS_FoodValues
    end

    error(string.format(
        "failed to load embedded food values module %s: %s",
        tostring(FOOD_VALUES_MODULE),
        tostring(rawData)
    ))
end

local function loadEmbeddedFoodSemantics()
    local ok, semantics = pcall(require, FOOD_SEMANTICS_MODULE)
    if ok and type(semantics) == "table" then
        return semantics
    end
    if type(NMS_FoodSemantics) == "table" then
        return NMS_FoodSemantics
    end
    return {}
end

local function buildLookups(rawData, semanticsByItemId)
    local valuesByItemId = {}
    local entriesByItemId = {}
    local runtimeEntriesByItemId = {}
    local sourceByItemId = {}
    local authorityByItemId = {}
    local portionByItemId = {}

    local function entrySource(entry)
        if type(entry) ~= "table" then
            return nil
        end
        if type(entry.nutrition_source) == "string" and entry.nutrition_source ~= "" then
            return entry.nutrition_source
        end
        return nil
    end

    for key, value in pairs(rawData) do
        if type(key) == "string" and string.sub(key, 1, 2) ~= "__" then
            valuesByItemId[key] = value
        end
    end

    for itemId, entry in pairs(semanticsByItemId or {}) do
        if type(entry) == "table" and entry.item_id then
            entriesByItemId[itemId] = entry
            runtimeEntriesByItemId[itemId] = entry
            sourceByItemId[itemId] = entrySource(entry)
            authorityByItemId[itemId] = entry.authority_kind
            portionByItemId[itemId] = entry.portion_kind
        end
    end

    return {
        modId = FOOD_VALUES_MODULE,
        baseModId = FOOD_VALUES_MODULE,
        rawData = rawData,
        valuesByItemId = valuesByItemId,
        stableReport = nil,
        stableEntriesByItemId = entriesByItemId,
        runtimeEntriesByItemId = runtimeEntriesByItemId,
        sourceByItemId = sourceByItemId,
        authorityByItemId = authorityByItemId,
        portionByItemId = portionByItemId,
    }
end

Data.FOOD_VALUES_MODULE = FOOD_VALUES_MODULE
Data.FOOD_SEMANTICS_MODULE = FOOD_SEMANTICS_MODULE

function Data.loadRuntimeData(forceReload)
    if Data._cache and not forceReload then
        return Data._cache
    end

    local rawData = loadEmbeddedFoodValues()
    local semanticsByItemId = loadEmbeddedFoodSemantics()
    Data._cache = buildLookups(rawData, semanticsByItemId)
    return Data._cache
end

return Data
