NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_CoreUtils"
require "NutritionMakesSense_Model"
require "NutritionMakesSense_Runtime"
require "NutritionMakesSense_ClientOptions"
require "ui/NutritionMakesSense_Draw"

local UIHelpers = NutritionMakesSense.UIHelpers or {}
NutritionMakesSense.UIHelpers = UIHelpers
local CoreUtils = NutritionMakesSense.CoreUtils or {}

local safeCall = CoreUtils.safeCall

function UIHelpers.safeCall(target, methodName, ...)
    return safeCall(target, methodName, ...)
end

function UIHelpers.getDisplay(playerObj)
    return NutritionMakesSense.Runtime.getDisplay(playerObj)
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

-- getText with %1..%3 substitution. Java overloads are picked by argument count, so never pass trailing nils.
function UIHelpers.trf(key, a1, a2, a3)
    if not getText then
        return key
    end
    if a1 == nil then
        return getText(key)
    end
    if a2 == nil then
        return getText(key, tostring(a1))
    end
    if a3 == nil then
        return getText(key, tostring(a1), tostring(a2))
    end
    return getText(key, tostring(a1), tostring(a2), tostring(a3))
end

-- Detail follows the option; Nutritionists always read food and body precisely.
function UIHelpers.isDetailed(playerObj)
    if NutritionMakesSense.ClientOptions.isDetailedDisplay() then
        return true
    end
    return playerObj ~= nil and (CoreUtils.hasTrait(playerObj, "Nutritionist", "NUTRITIONIST")
        or CoreUtils.hasTrait(playerObj, "Nutritionist2", "NUTRITIONIST2"))
end

local function roughly(hours)
    if hours < 0.75 then return getText("UI_NMS_Rough_LittleWhile") end
    if hours < 2 then return getText("UI_NMS_Rough_Hour") end
    if hours < 4.5 then return getText("UI_NMS_Rough_FewHours") end
    if hours < 14 then return getText("UI_NMS_Rough_SeveralHours") end
    if hours < 36 then return getText("UI_NMS_Rough_Day") end
    if hours < 24 * 5 then return getText("UI_NMS_Rough_FewDays") end
    if hours < 24 * 12 then return getText("UI_NMS_Rough_Week") end
    return getText("UI_NMS_Rough_Weeks")
end

-- A span of time: "~2 h 15 m" when detailed, "a few hours" otherwise.
function UIHelpers.duration(hours, detailed)
    if detailed then
        return "~" .. NutritionMakesSense.Draw.duration(hours)
    end
    return roughly(hours)
end

local PARTS = { "Morning", "Afternoon", "Evening", "Night" }

local function partOfDay(t)
    if t >= 5 and t < 12 then return 1 end
    if t >= 12 and t < 17 then return 2 end
    if t >= 17 and t < 21 then return 3 end
    return 4
end

-- A moment ahead: "around 14:30" when detailed, "by this evening" / "by tomorrow morning" otherwise.
function UIHelpers.when(hours, detailed)
    if detailed then
        if hours >= 12 then
            -- Malnourishment effects: exact penalties when detailed, felt otherwise. nil when negligible.
function UIHelpers.effectsText(m, detailed)
    local Model = NutritionMakesSense.Model
    local stamina = math.floor((1 - Model.enduranceRegenScale(m)) * 100 + 0.5)
    local healing = math.floor((1 - Model.naturalRecoveryMultiplier(m)) * 100 + 0.5)
    local parts = {}
    if stamina >= 1 then
        parts[#parts + 1] = detailed and UIHelpers.trf("UI_NMS_Effect_Stamina", stamina) or getText("UI_NMS_Effect_Stamina_Felt")
    end
    if healing >= 1 then
        parts[#parts + 1] = detailed and UIHelpers.trf("UI_NMS_Effect_Healing", healing) or getText("UI_NMS_Effect_Healing_Felt")
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "  ")
end

return UIHelpers.trf("UI_NMS_In", UIHelpers.duration(hours, true))
        end
        -- Malnourishment effects: exact penalties when detailed, felt otherwise. nil when negligible.
function UIHelpers.effectsText(m, detailed)
    local Model = NutritionMakesSense.Model
    local stamina = math.floor((1 - Model.enduranceRegenScale(m)) * 100 + 0.5)
    local healing = math.floor((1 - Model.naturalRecoveryMultiplier(m)) * 100 + 0.5)
    local parts = {}
    if stamina >= 1 then
        parts[#parts + 1] = detailed and UIHelpers.trf("UI_NMS_Effect_Stamina", stamina) or getText("UI_NMS_Effect_Stamina_Felt")
    end
    if healing >= 1 then
        parts[#parts + 1] = detailed and UIHelpers.trf("UI_NMS_Effect_Healing", healing) or getText("UI_NMS_Effect_Healing_Felt")
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "  ")
end

return UIHelpers.trf("UI_NMS_Around", NutritionMakesSense.Draw.clockIn(hours))
    end
    if hours < 1 then
        return getText("UI_NMS_When_Soon")
    end
    local gt = getGameTime()
    local ahead = gt:getTimeOfDay() + hours
    local day = math.floor(ahead / 24)
    local t = ahead % 24
    if t < 5 and day > 0 then
        day = day - 1
    end
    if day > 1 then
        -- Malnourishment effects: exact penalties when detailed, felt otherwise. nil when negligible.
function UIHelpers.effectsText(m, detailed)
    local Model = NutritionMakesSense.Model
    local stamina = math.floor((1 - Model.enduranceRegenScale(m)) * 100 + 0.5)
    local healing = math.floor((1 - Model.naturalRecoveryMultiplier(m)) * 100 + 0.5)
    local parts = {}
    if stamina >= 1 then
        parts[#parts + 1] = detailed and UIHelpers.trf("UI_NMS_Effect_Stamina", stamina) or getText("UI_NMS_Effect_Stamina_Felt")
    end
    if healing >= 1 then
        parts[#parts + 1] = detailed and UIHelpers.trf("UI_NMS_Effect_Healing", healing) or getText("UI_NMS_Effect_Healing_Felt")
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "  ")
end

return UIHelpers.trf("UI_NMS_In", roughly(hours))
    end
    return getText("UI_NMS_When_" .. (day == 0 and "This" or "Tomorrow") .. PARTS[partOfDay(t)])
end

-- Malnourishment effects: exact penalties when detailed, felt otherwise. nil when negligible.
function UIHelpers.effectsText(m, detailed)
    local Model = NutritionMakesSense.Model
    local stamina = math.floor((1 - Model.enduranceRegenScale(m)) * 100 + 0.5)
    local healing = math.floor((1 - Model.naturalRecoveryMultiplier(m)) * 100 + 0.5)
    local parts = {}
    if stamina >= 1 then
        parts[#parts + 1] = detailed and UIHelpers.trf("UI_NMS_Effect_Stamina", stamina) or getText("UI_NMS_Effect_Stamina_Felt")
    end
    if healing >= 1 then
        parts[#parts + 1] = detailed and UIHelpers.trf("UI_NMS_Effect_Healing", healing) or getText("UI_NMS_Effect_Healing_Felt")
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "  ")
end

return UIHelpers
