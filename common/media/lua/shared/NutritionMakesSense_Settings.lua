NutritionMakesSense = NutritionMakesSense or {}

local Settings = NutritionMakesSense.Settings or {}
NutritionMakesSense.Settings = Settings

local DEFAULTS = {
    UseCuratedFoodValues = true,
}

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

function Settings.useCuratedFoodValues()
    return toBoolean(getSandboxOptionValue("UseCuratedFoodValues"), DEFAULTS.UseCuratedFoodValues)
end

function Settings.getStaticFoodValueSource()
    return Settings.useCuratedFoodValues() and "authored" or "vanilla"
end

return Settings
