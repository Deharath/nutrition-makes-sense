NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_Model"
require "NutritionMakesSense_CoreUtils"

local TooltipLogic = NutritionMakesSense.TooltipLogic or {}
NutritionMakesSense.TooltipLogic = TooltipLogic
local Model = NutritionMakesSense.Model
local CoreUtils = NutritionMakesSense.CoreUtils or {}

local safeCall = CoreUtils.safeCall

local function readFoodValues(item)
    return {
        kcal = math.max(0, tonumber(safeCall(item, "getCalories") or item.kcal) or 0),
        carbs = math.max(0, tonumber(safeCall(item, "getCarbohydrates") or item.carbs) or 0),
        fats = math.max(0, tonumber(safeCall(item, "getLipids") or item.fats) or 0),
        proteins = math.max(0, tonumber(safeCall(item, "getProteins") or item.proteins) or 0),
    }
end

local function isDebugTooltipMode()
    local clientOptions = NutritionMakesSense and NutritionMakesSense.ClientOptions or nil
    if clientOptions and type(clientOptions.getShowDebugFoodTooltips) == "function" then
        local override = clientOptions.getShowDebugFoodTooltips()
        if override ~= nil then
            return override == true
        end
    end

    local debugSupport = NutritionMakesSense and NutritionMakesSense.DebugSupport or nil
    if debugSupport and type(debugSupport.isDebugLaunch) == "function" and debugSupport.isDebugLaunch() then
        return true
    end

    if type(isClient) == "function" and isClient() and type(getAccessLevel) == "function" then
        local ok, accessLevel = pcall(getAccessLevel)
        if ok and (accessLevel == "admin" or accessLevel == "moderator") then
            return true
        end
    end

    return false
end

local function formatDebugNumber(value, decimals)
    local numeric = tonumber(value) or 0
    return string.format("%." .. tostring(decimals or 1) .. "f", numeric)
end

function TooltipLogic.isFoodItem(item)
    if not item then
        return false
    end

    local isFood = safeCall(item, "isFood")
    if isFood == nil then
        isFood = safeCall(item, "IsFood")
    end
    if isFood ~= nil then
        return isFood == true
    end

    return safeCall(item, "getCalories") ~= nil
        or safeCall(item, "getCarbohydrates") ~= nil
        or safeCall(item, "getLipids") ~= nil
        or safeCall(item, "getProteins") ~= nil
end

-- Pip scales share units with the Nutrition window: a satiety pip is one hour of fullness,
-- an energy pip is the kcal that fill one hour at neutral composition.
TooltipLogic.PIP_COUNT = 5
TooltipLogic.SATIETY_HOURS_PER_PIP = 1
TooltipLogic.ENERGY_KCAL_PER_PIP = Model.FILL_KCAL_PER_HOUR
TooltipLogic.PROTEIN_G_PER_PIP = 10

local function tr(key, fallback)
    local text = type(getText) == "function" and getText(key) or nil
    if not text or text == key then
        return fallback
    end
    return text
end

function TooltipLogic.readFoodValues(item)
    return readFoodValues(item)
end

-- Rows: { key, label, pips, color key, debugText? }.
function TooltipLogic.buildPipRows(item)
    if not TooltipLogic.isFoodItem(item) then
        return {}
    end
    local values = readFoodValues(item)
    local debugMode = isDebugTooltipMode()
    local scriptItem = safeCall(item, "getScriptItem")
    local directlyEdible = safeCall(scriptItem, "isCantEat") ~= true
    local rows = {}

    if directlyEdible then
        local hours = Model.fillHours(values.kcal, values.fats, values.proteins)
        rows[#rows + 1] = {
            key = "satiety",
            label = tr("UI_NMS_Tooltip_Satiety", "Satiety"),
            pips = hours / TooltipLogic.SATIETY_HOURS_PER_PIP,
            debugText = debugMode and (formatDebugNumber(hours, 1) .. " h") or nil,
        }
    end
    rows[#rows + 1] = {
        key = "energy",
        label = tr("UI_NMS_Tooltip_Energy", "Energy"),
        pips = values.kcal / TooltipLogic.ENERGY_KCAL_PER_PIP,
        debugText = debugMode and (formatDebugNumber(values.kcal, 0) .. " kcal") or nil,
    }
    rows[#rows + 1] = {
        key = "protein",
        label = tr("UI_NMS_Tooltip_Protein", "Protein"),
        pips = values.proteins / TooltipLogic.PROTEIN_G_PER_PIP,
        debugText = debugMode and (formatDebugNumber(values.proteins, 0) .. " g") or nil,
    }
    return rows
end

return TooltipLogic
