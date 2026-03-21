NutritionMakesSense = NutritionMakesSense or {}

if NutritionMakesSense._bootDone then
    return
end
NutritionMakesSense._bootDone = true

require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_DevSupport"
require "NutritionMakesSense_StablePatcher"
require "NutritionMakesSense_StableItemRuntime"
require "NutritionMakesSense_ItemAuthority"
require "NutritionMakesSense_MetabolismRuntime"

local function log(msg)
    print("[NutritionMakesSense] " .. tostring(msg))
end

NutritionMakesSense.log = NutritionMakesSense.log or log

local function onGameBoot()
    local report = NutritionMakesSense.StablePatcher.ensurePatched("game-boot")
    log(string.format(
        "[BOOT] version=%s module=%s patched=%d routed=%d explicit=%d",
        tostring(NutritionMakesSense.MP and NutritionMakesSense.MP.SCRIPT_VERSION or "0.1.0"),
        tostring(NutritionMakesSense.MP and NutritionMakesSense.MP.NET_MODULE or "NutritionMakesSenseRuntime"),
        tonumber(report and report.patchedRows or 0),
        tonumber(report and report.routedRows or 0),
        tonumber(report and report.explicitExceptionRows or 0)
    ))
end

if Events and Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
    Events.OnGameBoot.Add(function()
        local ok, err = pcall(onGameBoot)
        if not ok then
            log("[ERROR] boot hook failed: " .. tostring(err))
        end
    end)
else
    log("Events.OnGameBoot.Add unavailable; boot hook not registered")
end
