NutritionMakesSense_RecipeCodeOnCreate = NutritionMakesSense_RecipeCodeOnCreate or {}

local RecipeCode = NutritionMakesSense_RecipeCodeOnCreate

local NUTRITION_FIELDS = {
    {
        get = function(food) return food:getCalories() end,
        set = function(food, value) food:setCalories(value) end,
    },
    {
        get = function(food) return food:getCarbohydrates() end,
        set = function(food, value) food:setCarbohydrates(value) end,
    },
    {
        get = function(food) return food:getLipids() end,
        set = function(food, value) food:setLipids(value) end,
    },
    {
        get = function(food) return food:getProteins() end,
        set = function(food, value) food:setProteins(value) end,
    },
}

local function collectFoods(items)
    local foods = {}
    if not items then
        return foods
    end

    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item and instanceof(item, "Food") then
            foods[#foods + 1] = item
        end
    end
    return foods
end

local function firstConsumedFood(data)
    local foods = collectFoods(data and data:getAllConsumedItems() or nil)
    return foods[1]
end

local function createdFoods(data)
    return collectFoods(data and data:getAllCreatedItems() or nil)
end

local function normalizeField(source, outputs, field)
    local sourceTotal = tonumber(field.get(source)) or 0
    local outputTotal = 0
    for _, output in ipairs(outputs) do
        outputTotal = outputTotal + (tonumber(field.get(output)) or 0)
    end

    if math.abs(outputTotal) > 0.000001 then
        local factor = sourceTotal / outputTotal
        for _, output in ipairs(outputs) do
            field.set(output, (tonumber(field.get(output)) or 0) * factor)
        end
        return
    end

    local share = #outputs > 0 and sourceTotal / #outputs or 0
    for _, output in ipairs(outputs) do
        field.set(output, share)
    end
end

local function normalizeNutrition(source, outputs)
    for _, field in ipairs(NUTRITION_FIELDS) do
        normalizeField(source, outputs, field)
    end
end

function RecipeCode.cutPoultry(data, character)
    local source = firstConsumedFood(data)
    local outputs = createdFoods(data)
    if not source or #outputs == 0
        or not RecipeCodeOnCreate
        or type(RecipeCodeOnCreate.cutChicken) ~= "function"
    then
        return false
    end

    RecipeCodeOnCreate.cutChicken(data, character)
    normalizeNutrition(source, outputs)
    return true
end

return RecipeCode
