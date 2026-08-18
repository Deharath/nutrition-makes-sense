local function assertClose(actual, expected, message)
    if math.abs(actual - expected) > 0.0001 then
        error(string.format("%s: expected %.6f, got %.6f", message, expected, actual))
    end
end

local function javaList(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local Food = {}
Food.__index = Food

function Food.new(values)
    values = values or {}
    return setmetatable({
        _isFood = true,
        calories = values.calories or 0,
        carbohydrates = values.carbohydrates or 0,
        lipids = values.lipids or 0,
        proteins = values.proteins or 0,
        baseHunger = values.baseHunger or 0,
        hungChange = values.hungChange or 0,
        weight = values.weight or 0,
        actualWeight = values.actualWeight or values.weight or 0,
        unhappyChange = values.unhappyChange or 0,
        cooked = values.cooked or false,
        customWeight = false,
    }, Food)
end

for _, field in ipairs({ "Calories", "Carbohydrates", "Lipids", "Proteins" }) do
    local key = field:sub(1, 1):lower() .. field:sub(2)
    Food["get" .. field] = function(self) return self[key] end
    Food["set" .. field] = function(self, value) self[key] = value end
end

function Food:getBaseHunger() return self.baseHunger end
function Food:setBaseHunger(value) self.baseHunger = value end
function Food:getHungChange() return self.hungChange end
function Food:setHungChange(value) self.hungChange = value end
function Food:getWeight() return self.weight end
function Food:setWeight(value) self.weight = value end
function Food:getActualWeight() return self.actualWeight end
function Food:setActualWeight(value) self.actualWeight = value end
function Food:getUnhappyChange() return self.unhappyChange end
function Food:setUnhappyChange(value) self.unhappyChange = value end
function Food:isCooked() return self.cooked end
function Food:setCooked(value) self.cooked = value end
function Food:setCustomWeight(value) self.customWeight = value end

instanceof = function(item, className)
    return className == "Food" and item and item._isFood == true
end

local vanillaCutCalls = 0
RecipeCodeOnCreate = {
    cutChicken = function(data, character)
        vanillaCutCalls = vanillaCutCalls + 1
        local source = data:getAllConsumedItems():get(0)
        local outputs = data:getAllCreatedItems()
        local outputHunger = 0
        for index = 0, outputs:size() - 1 do
            outputHunger = outputHunger + outputs:get(index):getHungChange()
        end
        local hungerFactor = source:getHungChange() / outputHunger
        for index = 0, outputs:size() - 1 do
            local output = outputs:get(index)
            output:setBaseHunger(output:getBaseHunger() * hungerFactor)
            output:setHungChange(output:getHungChange() * hungerFactor)
            output:setActualWeight(output:getActualWeight() * 0.9 * hungerFactor)
            output:setWeight(output:getActualWeight())
            output:setCustomWeight(true)
            output:setCooked(source:isCooked())
        end
    end,
}

local RecipeCode = require("NutritionMakesSense_RecipeCodeOnCreate")

local function craftData(source, outputs)
    return {
        getAllConsumedItems = function() return javaList({ source }) end,
        getAllCreatedItems = function() return javaList(outputs) end,
    }
end

local function sum(outputs, getter)
    local total = 0
    for _, output in ipairs(outputs) do
        total = total + output[getter](output)
    end
    return total
end

local chicken = Food.new({
    calories = 1400,
    carbohydrates = 0,
    lipids = 84,
    proteins = 140,
    baseHunger = -160,
    hungChange = -160,
    cooked = true,
})
local chickenOutputs = {
    Food.new({ calories = 260, carbohydrates = 0, lipids = 15, proteins = 28, baseHunger = -33, hungChange = -33, weight = 0.3 }),
    Food.new({ calories = 260, carbohydrates = 0, lipids = 15, proteins = 28, baseHunger = -33, hungChange = -33, weight = 0.3 }),
    Food.new({ calories = 430, carbohydrates = 4, lipids = 32, proteins = 30, baseHunger = -16, hungChange = -16, weight = 0.2 }),
    Food.new({ calories = 430, carbohydrates = 4, lipids = 32, proteins = 30, baseHunger = -16, hungChange = -16, weight = 0.2 }),
    Food.new({ calories = 220, carbohydrates = 0, lipids = 5, proteins = 42, baseHunger = -30, hungChange = -30, weight = 0.3 }),
    Food.new({ calories = 220, carbohydrates = 0, lipids = 5, proteins = 42, baseHunger = -30, hungChange = -30, weight = 0.3 }),
}

assert(RecipeCode.cutPoultry(craftData(chicken, chickenOutputs)))
assert(vanillaCutCalls == 1, "poultry wrapper should delegate to vanilla cut behavior")
assertClose(sum(chickenOutputs, "getCalories"), chicken:getCalories(), "chicken calories")
assertClose(sum(chickenOutputs, "getCarbohydrates"), chicken:getCarbohydrates(), "chicken carbohydrates")
assertClose(sum(chickenOutputs, "getLipids"), chicken:getLipids(), "chicken lipids")
assertClose(sum(chickenOutputs, "getProteins"), chicken:getProteins(), "chicken proteins")
assertClose(sum(chickenOutputs, "getHungChange"), chicken:getHungChange(), "chicken hunger")
assertClose(
    chickenOutputs[1]:getCalories() / chickenOutputs[3]:getCalories(),
    260 / 430,
    "poultry cut calorie ratio"
)
for _, output in ipairs(chickenOutputs) do
    assert(output:isCooked(), "poultry cut should inherit cooked state")
    assert(output.customWeight, "poultry cut should have custom weight")
end

assert(RecipeCode.cutPoultry(nil) == false)

print("NMS recipe callback tests passed")
