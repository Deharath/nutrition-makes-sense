NutritionMakesSense = NutritionMakesSense or {}

local Settings = NutritionMakesSense.Settings or {}
NutritionMakesSense.Settings = Settings

local DEFAULTS = {
    UseCuratedFoodValues = true,
    EnergyBurnMultiplier = 1.0,
    AppetiteRateMultiplier = 1.0,
}

local MULTIPLIER_MIN = 0.25
local MULTIPLIER_MAX = 3.0

local function toBoolean(value, fallback)
    if value == nil then
        return fallback
    end

    if type(value) == "boolean" then
        return value
    end

    if type(value) == "number" then
        return value ~= 0
    end

    local lowered = string.lower(tostring(value))
    if lowered == "true" or lowered == "1" or lowered == "yes" or lowered == "on" then
        return true
    end
    if lowered == "false" or lowered == "0" or lowered == "no" or lowered == "off" then
        return false
    end

    return fallback
end

local function getSandboxOptionValue(shortName)
    if type(shortName) ~= "string" or shortName == "" or type(SandboxVars) ~= "table" then
        return nil
    end

    local nested = SandboxVars.NutritionMakesSense
    if type(nested) == "table" and nested[shortName] ~= nil then
        return nested[shortName]
    end

    return SandboxVars["NutritionMakesSense." .. shortName]
end

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function getMultiplier(shortName, fallback)
    local value = tonumber(getSandboxOptionValue(shortName))
    if value == nil then
        value = fallback
    end
    return clamp(value, MULTIPLIER_MIN, MULTIPLIER_MAX)
end

function Settings.useCuratedFoodValues()
    return toBoolean(getSandboxOptionValue("UseCuratedFoodValues"), DEFAULTS.UseCuratedFoodValues)
end

function Settings.getEnergyBurnMultiplier()
    return getMultiplier("EnergyBurnMultiplier", DEFAULTS.EnergyBurnMultiplier)
end

function Settings.getAppetiteRateMultiplier()
    return getMultiplier("AppetiteRateMultiplier", DEFAULTS.AppetiteRateMultiplier)
end

Settings.DEFAULTS = DEFAULTS
Settings.MULTIPLIER_MIN = MULTIPLIER_MIN
Settings.MULTIPLIER_MAX = MULTIPLIER_MAX

return Settings
