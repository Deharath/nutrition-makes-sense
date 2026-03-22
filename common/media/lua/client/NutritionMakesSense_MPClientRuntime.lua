NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.MPClientRuntime = NutritionMakesSense.MPClientRuntime or {}

require "mp/NutritionMakesSense_MPClientRuntime_Context"

local MPClient = NutritionMakesSense.MPClientRuntime

require "mp/NutritionMakesSense_MPClientRuntime_Network"
require "mp/NutritionMakesSense_MPClientRuntime_Consume"
require "mp/NutritionMakesSense_MPClientRuntime_Hooks"
require "mp/NutritionMakesSense_MPClientRuntime_Lifecycle"

return MPClient
