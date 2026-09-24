NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_CoreUtils"
require "NutritionMakesSense_Model"
require "NutritionMakesSense_Settings"
require "NutritionMakesSense_Runtime"
require "NutritionMakesSense_Workload"

-- Dev-build only (stripped from release). Authority-side inspection and state edits.
local DevTools = NutritionMakesSense.DevTools or {}
NutritionMakesSense.DevTools = DevTools

local CoreUtils = NutritionMakesSense.CoreUtils
local Model = NutritionMakesSense.Model
local Settings = NutritionMakesSense.Settings
local Runtime = NutritionMakesSense.Runtime
local Workload = NutritionMakesSense.Workload
local safeCall = CoreUtils.safeCall

DevTools.NET_MODULE = "NutritionMakesSenseDev"
DevTools.TOOL_COMMAND = "devTool"
DevTools.STATE_COMMAND = "devState"

DevTools.SPAWN_FOODS = {
    "Base.Apple", "Base.Bread", "Base.PeanutButter", "Base.Steak", "Base.BeefJerky",
    "Base.Crisps", "Base.TinnedBeans", "Base.Chocolate", "Base.Salad",
}

local function flatCopy(t)
    local out = {}
    for k, v in pairs(t or {}) do
        local kind = type(v)
        if kind == "number" or kind == "boolean" or kind == "string" then
            out[k] = v
        end
    end
    return out
end

-- Everything a dev surface needs, as a plain table that survives sendServerCommand.
function DevTools.inspect(playerObj)
    if not playerObj then
        return nil
    end
    local mem, persisted, modData = Runtime.inspect(playerObj)
    local reads = Runtime.readVanilla(playerObj)
    local bodyDamage = CoreUtils.getPlayerBodyDamage(playerObj)
    local m = persisted and tonumber(persisted.malnutrition) or 0
    local state = {
        mode = (type(isServer) == "function" and isServer()) and "server" or "SP",
        installed = Runtime._installed == true,
        eatHook = type(ISEatFoodAction) == "table" and ISEatFoodAction.__nmsWrapped == true,
        hasMemory = mem ~= nil,
        tickAge = mem and (Workload.wallSeconds() - (mem.lastTickWall or 0)) or nil,
        vanillaBurnPerHour = mem and mem.vanillaBurnPerHour or nil,
        last = mem and flatCopy(mem.last) or {},
        persisted = persisted and flatCopy(persisted) or nil,
        legacyKeyPresent = modData ~= nil and modData[Runtime.LEGACY_STATE_KEY] ~= nil,
        sandboxNutrition = not (SandboxVars and SandboxVars.Nutrition == false),
        compatEndurance = Runtime.isCompatEnduranceActive(),
        burnMultiplier = Settings.getEnergyBurnMultiplier(),
        appetiteMultiplier = Settings.getAppetiteRateMultiplier(),
        statsMultiplier = Settings.getVanillaStatsDecreaseMultiplier(),
        traits = Runtime.readTraits(playerObj),
        worldHours = CoreUtils.getWorldHours(),
        healthFromFood = bodyDamage and tonumber(safeCall(bodyDamage, "getHealthFromFood")) or nil,
        expectedHealthFromFood = Model.wellFedHealing(m),
    }
    if reads then
        state.reads = {
            hunger = reads.hunger, calories = reads.calories, proteins = reads.proteins, fats = reads.fats,
            carbs = reads.carbs, weight = reads.weight, timer = reads.timer, endurance = reads.endurance,
        }
    end
    return state
end

local function addFood(playerObj, fullType)
    local inv = playerObj:getInventory()
    local item = inv and inv:AddItem(fullType) or nil
    if item and type(isServer) == "function" and isServer() and type(sendAddItemToContainer) == "function" then
        sendAddItemToContainer(inv, item)
    end
end

-- Edits vanilla values directly, then forgets runtime memory so the next tick re-seeds
-- instead of reading the edit as intake or burn.
function DevTools.apply(playerObj, op, value)
    if not playerObj or not Runtime.isAuthority() then
        return false
    end
    local reads = Runtime.readVanilla(playerObj)
    local _, persisted, modData = Runtime.inspect(playerObj)
    if not reads then
        return false
    end
    local v = tonumber(value)
    if op == "calories" and v then
        safeCall(reads.nutrition, "setCalories", Model.clamp(v, Model.CALORIES_MIN, Model.CALORIES_MAX))
    elseif op == "proteins" and v then
        safeCall(reads.nutrition, "setProteins", Model.clamp(v, -500, 1000))
    elseif op == "malnutrition" and v and persisted then
        persisted.malnutrition = Model.clamp(v, 0, 1)
    elseif op == "stomach" and v then
        safeCall(reads.bodyDamage, "setHealthFromFoodTimer", Model.clamp(v, 0, 5) * Model.STOMACH_UNITS_PER_HOUR)
    elseif op == "hunger" and v and CharacterStat then
        safeCall(reads.stats, "set", CharacterStat.HUNGER, Model.clamp(v, 0, 1))
    elseif op == "weightDelta" and v then
        safeCall(reads.nutrition, "setWeight", Model.clamp(reads.weight + v, Model.WEIGHT_MIN_KG, Model.WEIGHT_MAX_KG))
        safeCall(reads.nutrition, "applyTraitFromWeight")
    elseif op == "reset" and modData then
        modData[Runtime.STATE_KEY] = nil
    elseif op == "spawn" then
        for _, fullType in ipairs(DevTools.SPAWN_FOODS) do
            addFood(playerObj, fullType)
        end
        return true
    else
        return false
    end
    if type(isServer) == "function" and isServer() and type(syncPlayerStats) == "function" then
        syncPlayerStats(playerObj, -1)
    end
    Runtime.forget(playerObj)
    print(string.format("[NutritionMakesSense] [DEV] %s %s", tostring(op), tostring(value)))
    return true
end

return DevTools
