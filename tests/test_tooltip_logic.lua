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

local edibleRows = TooltipLogic.buildPipRows(makeFood(false))
Support.assertEqual(edibleRows[1].key, "satiety", "direct food leads with satiety")
Support.assertEqual(#edibleRows, 3, "satiety, energy, protein")
Support.assertTrue(math.abs(edibleRows[2].pips - 1650 / 250) < 1e-9, "an energy pip is 250 kcal")
Support.assertTrue(math.abs(edibleRows[3].pips - 4.8) < 1e-9, "a protein pip is 10 g")

local ingredientRows = TooltipLogic.buildPipRows(makeFood(true))
Support.assertEqual(ingredientRows[1].key, "energy", "CantEat reservoirs do not promise satiety")

local Model = NutritionMakesSense.Model
local lean = TooltipLogic.buildPipRows({ isFood = function() return true end, getCalories = function() return 500 end,
    getProteins = function() return 60 end, getLipids = function() return 5 end })
local sugary = TooltipLogic.buildPipRows({ isFood = function() return true end, getCalories = function() return 500 end,
    getProteins = function() return 0 end, getLipids = function() return 0 end })
Support.assertTrue(lean[1].pips > sugary[1].pips, "protein keeps you full longer at equal energy")
Support.assertTrue(math.abs(sugary[1].pips - Model.fillHours(500, 0, 0)) < 1e-9, "a satiety pip is one hour of fullness")

print("nms tooltip characterization passed")
