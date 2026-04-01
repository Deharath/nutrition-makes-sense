NutritionMakesSense = NutritionMakesSense or {}

if NutritionMakesSense._bootDone then
    return
end
NutritionMakesSense._bootDone = true

local function log(msg)
    local text = tostring(msg or "")
    -- Keep the release runtime quiet while preserving boot, warnings, and failures.
    local suppressedPrefixes = {
        "[CLIENT_SNAPSHOT]",
        "[CLIENT_READY]",
        "[MP_HOOK_REPORT]",
        "[CLIENT_WORKLOAD]",
        "[NMS_CONSUME]",
        "[NMS_HOOK_WRAP]",
        "[NMS_EVOLVED_ADD]",
        "[NMS_EVOLVED_ADD_SKIP]",
        "[ITEM_AUTHORITY_LOAD]",
        "[ITEM_AUTHORITY_APIS]",
        "[ITEM_AUTHORITY_COMPUTED_SEED]",
        "[ITEM_AUTHORITY_COMPUTED_ACCUMULATE]",
        "[ITEM_AUTHORITY_SYNC]",
        "[ITEM_AUTHORITY_PERSISTENCE_SYNC]",
        "[ITEM_AUTHORITY] mode=",
        "[STATE_INIT]",
        "[STATE_MIGRATION]",
        "[MP_WORKLOAD]",
    }

    for _, prefix in ipairs(suppressedPrefixes) do
        if string.find(text, prefix, 1, true) then
            return
        end
    end

    print("[NutritionMakesSense] " .. tostring(msg))
end

NutritionMakesSense.log = NutritionMakesSense.log or log

require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_Compat"
require "NutritionMakesSense_DebugSupport"
require "NutritionMakesSense_StablePatcher"
require "NutritionMakesSense_StableItemRuntime"
require "NutritionMakesSense_ItemAuthority"
require "NutritionMakesSense_MetabolismRuntime"

if NutritionMakesSense.StableItemRuntime and type(NutritionMakesSense.StableItemRuntime.install) == "function" then
    NutritionMakesSense.StableItemRuntime.install()
end
if NutritionMakesSense.ItemAuthority and type(NutritionMakesSense.ItemAuthority.install) == "function" then
    NutritionMakesSense.ItemAuthority.install()
end
if NutritionMakesSense.MetabolismRuntime and type(NutritionMakesSense.MetabolismRuntime.install) == "function" then
    NutritionMakesSense.MetabolismRuntime.install()
end

local function onGameBoot()
    local report = NutritionMakesSense.StablePatcher.ensurePatched("game-boot")
    log(string.format(
        "[BOOT] version=%s module=%s patched=%d routed=%d explicit=%d",
        tostring(NutritionMakesSense.MP and NutritionMakesSense.MP.SCRIPT_VERSION or "1.0.0"),
        tostring(NutritionMakesSense.MP and NutritionMakesSense.MP.NET_MODULE or "NutritionMakesSenseRuntime"),
        tonumber(report and report.patchedRows or 0),
        tonumber(report and report.routedRows or 0),
        tonumber(report and report.explicitExceptionRows or 0)
    ))
end

if Events and Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
    Events.OnGameBoot.Add(function()
        onGameBoot()
    end)
else
    log("Events.OnGameBoot.Add unavailable; boot hook not registered")
end
