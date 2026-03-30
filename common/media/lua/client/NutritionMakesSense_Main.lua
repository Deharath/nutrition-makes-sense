NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_Boot"
require "NutritionMakesSense_DevSupport"
require "NutritionMakesSense_MPClientRuntime"
require "NutritionMakesSense_ClientOptions"
require "NutritionMakesSense_TooltipOverlay"
require "NutritionMakesSense_ItemAuthority"
require "NutritionMakesSense_HealthPanelHook"
require "NutritionMakesSense_MalnourishedMoodle"
require "NutritionMakesSense_WeightDisplayHook"
require "bootstrap/NutritionMakesSense_ClientBootstrap"
require "hooks/NutritionMakesSense_ClientHooks"

if NutritionMakesSense.MPClientRuntime and type(NutritionMakesSense.MPClientRuntime.install) == "function" then
    NutritionMakesSense.MPClientRuntime.install()
end
if NutritionMakesSense.MPClientRuntime and type(NutritionMakesSense.MPClientRuntime.installHooks) == "function" then
    NutritionMakesSense.MPClientRuntime.installHooks()
end
if NutritionMakesSense.ClientOptions and type(NutritionMakesSense.ClientOptions.install) == "function" then
    NutritionMakesSense.ClientOptions.install()
end
if NutritionMakesSense.TooltipOverlay and type(NutritionMakesSense.TooltipOverlay.install) == "function" then
    NutritionMakesSense.TooltipOverlay.install()
end
if NutritionMakesSense.HealthPanelHook and type(NutritionMakesSense.HealthPanelHook.install) == "function" then
    NutritionMakesSense.HealthPanelHook.install()
end
if NutritionMakesSense.MalnourishedMoodle and type(NutritionMakesSense.MalnourishedMoodle.install) == "function" then
    NutritionMakesSense.MalnourishedMoodle.install()
end
if NutritionMakesSense.WeightDisplayHook and type(NutritionMakesSense.WeightDisplayHook.install) == "function" then
    NutritionMakesSense.WeightDisplayHook.install()
end
if NutritionMakesSense.ClientBootstrap and type(NutritionMakesSense.ClientBootstrap.install) == "function" then
    NutritionMakesSense.ClientBootstrap.install()
end
if NutritionMakesSense.ClientHooks and type(NutritionMakesSense.ClientHooks.install) == "function" then
    NutritionMakesSense.ClientHooks.install()
end
