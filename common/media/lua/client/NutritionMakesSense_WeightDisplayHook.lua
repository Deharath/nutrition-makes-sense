NutritionMakesSense = NutritionMakesSense or {}

require "ui/NutritionMakesSense_UIHelpers"

local UIHelpers = NutritionMakesSense.UIHelpers or {}
local WeightDisplayHook = NutritionMakesSense.WeightDisplayHook or {}
NutritionMakesSense.WeightDisplayHook = WeightDisplayHook

local UI_BORDER_SPACING = 10
local FONT = UIFont.Small
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)

local smoothedRate = nil
local SMOOTH_ALPHA = 0.08

local function getState(player)
    return UIHelpers.getStateCopy(player)
end

local originalRender = nil

local function hookedRender(self)
    originalRender(self)

    local state = getState(self.char)
    if not state then return end

    local rawRate = tonumber(state.lastWeightRateKgPerWeek) or 0
    if smoothedRate == nil then
        smoothedRate = rawRate
    else
        smoothedRate = smoothedRate + SMOOTH_ALPHA * (rawRate - smoothedRate)
    end

    local rate = smoothedRate
    local z = UI_BORDER_SPACING + FONT_HGT_MEDIUM + UI_BORDER_SPACING * 2

    local weightStr = tostring(round(self.char:getNutrition():getWeight(), 0))
    local weightTextWidth = getTextManager():MeasureStringX(FONT, weightStr)

    local chevronX = self.xOffset + weightTextWidth + 13
    local rateWidth = getTextManager():MeasureStringX(FONT, "+0.00 kg/wk") + 8

    self:drawRect(chevronX, z, rateWidth, getTextManager():getFontHeight(FONT), 1.0,
        self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)

    local sign = rate >= 0 and "+" or ""
    local rateStr = string.format("%s%.2f kg/wk", sign, rate)
    local r, g, b
    if math.abs(rate) < 0.05 then
        r, g, b = 0.55, 0.60, 0.65
    else
        r, g, b = 0.85, 0.60, 0.25
    end

    self:drawText(rateStr, chevronX, z, r, g, b, 0.85, FONT)
end

local function install()
    if not ISCharacterScreen or type(ISCharacterScreen.render) ~= "function" then return end
    if originalRender then return end

    originalRender = ISCharacterScreen.render
    ISCharacterScreen.render = hookedRender
end

function WeightDisplayHook.install()
    if WeightDisplayHook._installed then
        return WeightDisplayHook
    end
    WeightDisplayHook._installed = true
    install()

    return WeightDisplayHook
end

return WeightDisplayHook
