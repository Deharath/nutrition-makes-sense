NutritionMakesSense = NutritionMakesSense or {}

if NutritionMakesSense._bootDone then
    return
end
NutritionMakesSense._bootDone = true

local function log(msg)
    print("[NutritionMakesSense] " .. tostring(msg))
end

NutritionMakesSense.log = NutritionMakesSense.log or log

require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_Compat"
require "NutritionMakesSense_DebugSupport"
require "NutritionMakesSense_RecipeCodeOnCreate"
require "NutritionMakesSense_Runtime"
require "NutritionMakesSense_EnduranceCompat"

NutritionMakesSense.Runtime.install()

local function onGameBoot()
    log(string.format(
        "[BOOT] version=%s module=%s model=2",
        tostring(NutritionMakesSense.MP and NutritionMakesSense.MP.SCRIPT_VERSION or "1.0.0"),
        tostring(NutritionMakesSense.MP and NutritionMakesSense.MP.NET_MODULE or "NutritionMakesSenseRuntime")
    ))
end

if Events and Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
    Events.OnGameBoot.Add(function()
        onGameBoot()
    end)
else
    log("Events.OnGameBoot.Add unavailable; boot hook not registered")
end
