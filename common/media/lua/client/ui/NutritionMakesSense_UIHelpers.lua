NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_CoreUtils"

local UIHelpers = NutritionMakesSense.UIHelpers or {}
NutritionMakesSense.UIHelpers = UIHelpers
local CoreUtils = NutritionMakesSense.CoreUtils or {}

local safeCall = CoreUtils.safeCall

function UIHelpers.safeCall(target, methodName, ...)
    return safeCall(target, methodName, ...)
end

function UIHelpers.getStateCopy(playerObj)
    local Runtime = NutritionMakesSense.MetabolismRuntime or {}
    if type(Runtime.getStateCopy) ~= "function" then
        return nil
    end
    return Runtime.getStateCopy(playerObj)
end

function UIHelpers.clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

function UIHelpers.formatPercent(value)
    local numeric = tonumber(value) or 0
    return string.format("%d%%", math.floor(numeric + 0.5))
end

function UIHelpers.tr(key, fallback)
    local text = getText and getText(key) or nil
    if not text or text == key then
        return fallback or key
    end
    return text
end

return UIHelpers
