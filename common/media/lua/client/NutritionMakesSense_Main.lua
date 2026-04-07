NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_Boot"
require "NutritionMakesSense_DebugSupport"
require "NutritionMakesSense_MPClientRuntime_Vanilla"
require "NutritionMakesSense_ClientOptions"
require "NutritionMakesSense_TooltipOverlay"
require "NutritionMakesSense_HealthPanelHook"
require "NutritionMakesSense_MalnourishedMoodle"
require "NutritionMakesSense_WeightDisplayHook"
require "bootstrap/NutritionMakesSense_ClientBootstrap"
require "hooks/NutritionMakesSense_ClientHooks"

-- Install thin MP sync before client-facing UI hooks so HUD surfaces can read shared state.
if NutritionMakesSense.MPClientRuntime and type(NutritionMakesSense.MPClientRuntime.install) == "function" then
    NutritionMakesSense.MPClientRuntime.install()
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
-- ClientHooks depends on the runtime/UI state already being installed this tick.
if NutritionMakesSense.ClientHooks and type(NutritionMakesSense.ClientHooks.install) == "function" then
    NutritionMakesSense.ClientHooks.install()
end
