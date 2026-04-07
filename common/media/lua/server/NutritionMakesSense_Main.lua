NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_Boot"
require "NutritionMakesSense_MPServerRuntime_Vanilla"

if NutritionMakesSense.MPServerRuntime and type(NutritionMakesSense.MPServerRuntime.install) == "function" then
    NutritionMakesSense.MPServerRuntime.install()
end
