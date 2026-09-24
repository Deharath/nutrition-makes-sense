NutritionMakesSense = NutritionMakesSense or {}

local Settings = NutritionMakesSense.Settings or {}
NutritionMakesSense.Settings = Settings

local DEFAULTS = {
    EnergyBurnMultiplier = 1.0,
    AppetiteRateMultiplier = 1.0,
}

local MULTIPLIER_MIN = 0.25
local MULTIPLIER_MAX = 3.0

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

function Settings.getEnergyBurnMultiplier()
    return getMultiplier("EnergyBurnMultiplier", DEFAULTS.EnergyBurnMultiplier)
end

function Settings.getAppetiteRateMultiplier()
    return getMultiplier("AppetiteRateMultiplier", DEFAULTS.AppetiteRateMultiplier)
end

-- Vanilla "Stats Decrease" sandbox level (1 very fast .. 5 very slow), as SandboxOptions.getStatsDecreaseMultiplier.
local STATS_DECREASE_MULTIPLIERS = { 2.0, 1.6, 1.0, 0.8, 0.65 }

function Settings.getVanillaStatsDecreaseMultiplier()
    local level = type(SandboxVars) == "table" and tonumber(SandboxVars.StatsDecrease) or nil
    return STATS_DECREASE_MULTIPLIERS[level or 3] or 1.0
end

Settings.DEFAULTS = DEFAULTS
Settings.MULTIPLIER_MIN = MULTIPLIER_MIN
Settings.MULTIPLIER_MAX = MULTIPLIER_MAX

return Settings
