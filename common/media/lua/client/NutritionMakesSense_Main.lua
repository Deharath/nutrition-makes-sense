NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_Boot"
require "NutritionMakesSense_MPClient"
require "NutritionMakesSense_ClientOptions"
require "NutritionMakesSense_TooltipOverlay"
require "NutritionMakesSense_HealthPanelHook"
require "NutritionMakesSense_MalnourishedMoodle"
require "NutritionMakesSense_WeightDisplayHook"

NutritionMakesSense.MPClient.install()
NutritionMakesSense.ClientOptions.install()
NutritionMakesSense.TooltipOverlay.install()
NutritionMakesSense.HealthPanelHook.install()
NutritionMakesSense.MalnourishedMoodle.install()
NutritionMakesSense.WeightDisplayHook.install()
