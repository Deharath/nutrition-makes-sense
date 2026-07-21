local Support = require "support"
local TooltipLogic = require "NutritionMakesSense_TooltipLogic"

local function makeFood(cantEat)
    local scriptItem = {
        isCantEat = function()
            return cantEat == true
        end,
    }
    return {
        isFood = function() return true end,
        getScriptItem = function() return scriptItem end,
        getHungerChange = function() return -0.60 end,
        getCalories = function() return 1650 end,
        getCarbohydrates = function() return 345 end,
        getLipids = function() return 5 end,
        getProteins = function() return 48 end,
    }
end

local edibleRows = TooltipLogic.buildDescriptorRows(makeFood(false), {})
Support.assertEqual(edibleRows[1].label, "Satiety", "direct food keeps a fullness descriptor")

local ingredientRows = TooltipLogic.buildDescriptorRows(makeFood(true), {})
Support.assertEqual(ingredientRows[1].label, "Energy Content", "CantEat reservoir must not present hunger budget as satiety")

print("nms tooltip characterization passed")
