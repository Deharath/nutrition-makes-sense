NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_StablePatcher"

local StableItemRuntime = NutritionMakesSense.StableItemRuntime or {}
NutritionMakesSense.StableItemRuntime = StableItemRuntime

local function ensurePatched(reason)
    if NutritionMakesSense.StablePatcher and NutritionMakesSense.StablePatcher.ensurePatched then
        return NutritionMakesSense.StablePatcher.ensurePatched(reason or "stable-item-runtime")
    end
    return nil
end

function StableItemRuntime.repairKnownInventories(reason)
    return ensurePatched(reason)
end

function StableItemRuntime.install()
    if StableItemRuntime._installed then
        return StableItemRuntime
    end
    StableItemRuntime._installed = true

    if Events then
        if Events.OnLoad and type(Events.OnLoad.Add) == "function" then
            Events.OnLoad.Add(function()
                ensurePatched("on-load")
            end)
        end

        if Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
            Events.OnGameStart.Add(function()
                ensurePatched("game-start")
            end)
        end

        if Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
            Events.OnCreatePlayer.Add(function()
                ensurePatched("create-player")
            end)
        end
    end

    return StableItemRuntime
end

return StableItemRuntime
