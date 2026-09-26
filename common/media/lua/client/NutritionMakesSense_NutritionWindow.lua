NutritionMakesSense = NutritionMakesSense or {}

require "ISUI/ISCollapsableWindow"
require "ui/NutritionMakesSense_UIHelpers"
require "ui/NutritionMakesSense_Draw"
require "NutritionMakesSense_Model"
require "NutritionMakesSense_Settings"
require "NutritionMakesSense_Runtime"

-- Player-facing Nutrition window: what the body is doing now and what happens next.
local NutritionWindow = NutritionMakesSense.NutritionWindow or {}
NutritionMakesSense.NutritionWindow = NutritionWindow

local UIHelpers = NutritionMakesSense.UIHelpers
local Draw = NutritionMakesSense.Draw
local Model = NutritionMakesSense.Model
local Settings = NutritionMakesSense.Settings
local Runtime = NutritionMakesSense.Runtime
local C = Draw.C
local T = UIHelpers.trf

local FONT = UIFont.Small
local FORECAST_SECONDS = 1.0
local LAYOUT_NAME = "nms_nutrition"

local STOMACH_KEYS = { [0] = "UI_NMS_Stomach_Empty", "UI_NMS_Stomach_Satiated", "UI_NMS_Stomach_WellFed",
    "UI_NMS_Stomach_Stuffed", "UI_NMS_Stomach_Bursting" }
local ZONE_KEYS = { Depleted = "UI_NMS_Zone_Depleted", Low = "UI_NMS_Zone_Low", Ready = "UI_NMS_Zone_Ready",
    Stored = "UI_NMS_Zone_Stored" }
local CAUSE_KEYS = { calories = "UI_NMS_Malnutrition_Cause_Calories", protein = "UI_NMS_Malnutrition_Cause_Protein",
    both = "UI_NMS_Malnutrition_Cause_Both" }

local instance = nil

local function hungerBand(h)
    if h >= Model.HUNGER_STARVING then return "UI_NMS_Hunger_Starving", 1.0 end
    if h >= Model.HUNGER_VERY_HUNGRY then return "UI_NMS_Hunger_VeryHungry", 0.8 end
    if h >= Model.HUNGER_HUNGRY then return "UI_NMS_Hunger_Hungry", 0.55 end
    if h >= Model.HUNGER_PECKISH then return "UI_NMS_Hunger_Peckish", 0.3 end
    return "UI_NMS_Hunger_Comfortable", 0
end

local function malnutritionLevelKey(m)
    local levels = Model.MALNOURISHED_LEVELS
    if m >= levels[3] then return "UI_NMS_Deprivation_Severity_Severe" end
    if m >= levels[2] then return "UI_NMS_Deprivation_Severity_Moderate" end
    if m >= levels[1] then return "UI_NMS_Deprivation_Severity_Mild" end
    return nil
end

-- One sentence with the most useful thing to know right now.
local function verdict(d)
    local m, target = d.malnutrition, d.malnutritionTarget
    local worsening = target > m + 0.01
    if m >= Model.MALNOURISHED_LEVELS[1] and worsening and d.cause then
        return T("UI_NMS_Verdict_Wasting_" .. d.cause), Draw.bad()
    end
    if d.reserveZone == "Depleted" then
        return T("UI_NMS_Verdict_Empty"), Draw.bad()
    end
    if d.hunger >= Model.HUNGER_VERY_HUNGRY then
        return T("UI_NMS_Verdict_VeryHungry"), Draw.bad()
    end
    if d.hunger >= Model.HUNGER_HUNGRY then
        return T("UI_NMS_Verdict_Hungry"), C.warn
    end
    if (d.proteinTarget or 0) > 0 then
        return T("UI_NMS_Verdict_NeedProtein"), C.warn
    end
    if m >= Model.MALNOURISHED_LEVELS[1] then
        return T("UI_NMS_Verdict_Recovering"), C.warn
    end
    if d.stomachLevel >= 3 then
        return T("UI_NMS_Verdict_Stuffed"), C.stomach
    end
    if d.stomachLevel >= 2 then
        return T("UI_NMS_Verdict_WellFed"), Draw.good()
    end
    return T("UI_NMS_Verdict_Fine"), C.text
end

local NMS_NutritionWindow = ISCollapsableWindow:derive("NMS_NutritionWindow")

function NMS_NutritionWindow:new(x, y, playerObj)
    local fh = Draw.fontHeight(FONT)
    local width = math.max(300, fh * 22)
    local o = ISCollapsableWindow.new(self, x, y, width, 200)
    o.playerObj = playerObj
    o.fh = fh
    o.pad = math.max(8, math.floor(fh * 0.6))
    o.gaugeH = math.max(5, math.floor(fh * 0.4))
    o.forecastAt = -1
    o:setTitle(T("UI_NMS_Window_Title"))
    o:setResizable(false)
    return o
end

function NMS_NutritionWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:setInfo(T("UI_NMS_Help"))
end

function NMS_NutritionWindow:close()
    NutritionWindow.hide()
end

function NMS_NutritionWindow:when(hours)
    return UIHelpers.when(hours, self.detailed)
end

function NMS_NutritionWindow:dur(hours)
    return UIHelpers.duration(hours, self.detailed)
end

function NMS_NutritionWindow:notches(list)
    return self.detailed and list or nil
end

function NMS_NutritionWindow:refreshForecast(d)
    local now = getTimestampMs and getTimestampMs() / 1000 or os.time()
    if self.forecast and (now - self.forecastAt) < FORECAST_SECONDS then
        return self.forecast
    end
    self.forecastAt = now
    self.forecast = Model.forecast({
        calories = d.calories, hunger = d.hunger, timer = d.stomachTimer, weight = d.weightKg,
    }, {
        met = d.met,
        asleep = d.asleep,
        traits = Runtime.readTraits(self.playerObj),
        burnMultiplier = Settings.getEnergyBurnMultiplier(),
        appetiteMultiplier = Settings.getAppetiteRateMultiplier() * Settings.getVanillaStatsDecreaseMultiplier(),
    }, 48)
    return self.forecast
end

-- Row header: label left, state right (optional chevron); returns next y.
function NMS_NutritionWindow:header(y, label, state, stateColor, chevron)
    local right = self.width - self.pad
    self:drawText(label, self.pad, y, C.label.r, C.label.g, C.label.b, 1, FONT)
    if chevron then
        right = right - 12
        Draw.chevron(self, right + 2, y + math.floor(self.fh / 2) - 2, chevron.up, chevron.color)
    end
    self:drawTextRight(state, right, y, stateColor.r, stateColor.g, stateColor.b, 1, FONT)
    return y + self.fh + 2
end

function NMS_NutritionWindow:detail(y, text, color)
    if not text or text == "" then
        return y
    end
    local c = color or C.dim
    self:drawText(text, self.pad, y, c.r, c.g, c.b, 1, FONT)
    self.widest = math.max(self.widest, Draw.textWidth(FONT, text) + self.pad * 2)
    return y + self.fh
end

function NMS_NutritionWindow:gauge(y, spec)
    Draw.gauge(self, self.pad, y, self.width - self.pad * 2, self.gaugeH, spec)
    return y + self.gaugeH + 3
end

function NMS_NutritionWindow:rowStomach(y, d)
    local level = d.stomachLevel
    local color = level == 0 and C.dim or C.stomach
    y = self:header(y, T("UI_NMS_Row_Stomach"), T(STOMACH_KEYS[level]), color)

    -- Five hour-cells: the same unit as satiety pips on food tooltips.
    local hours = d.stomachHoursLeft
    local w = self.width - self.pad * 2
    local cells = Model.STOMACH_CAP / Model.STOMACH_UNITS_PER_HOUR
    local gap = 3
    local cellW = math.floor((w - gap * (cells - 1)) / cells)
    local sink = Draw.elementSink(self)
    for i = 1, cells do
        local cx = self.pad + (i - 1) * (cellW + gap)
        sink(cx, y, cellW, self.gaugeH, C.track, Draw.TRACK_ALPHA)
        local fill = math.max(0, math.min(1, hours - (i - 1)))
        if fill > 0 then
            sink(cx, y, math.max(1, math.floor(cellW * fill + 0.5)), self.gaugeH, C.stomach, 0.95)
        end
    end
    y = y + self.gaugeH + 3

    local text
    if hours >= 0.05 then
        text = T("UI_NMS_Stomach_FullFor", self:dur(hours))
        local bodyDamage = self.playerObj:getBodyDamage()
        if bodyDamage and bodyDamage:getOverallBodyHealth() < 99.9 then
            text = text .. "  " .. T("UI_NMS_WellFed_Healing")
        end
    else
        text = T("UI_NMS_Stomach_Nothing")
    end
    return self:detail(y, text)
end

function NMS_NutritionWindow:rowHunger(y, d, f)
    local key, sev = hungerBand(d.hunger)
    y = self:header(y, T("UI_NMS_Row_Hunger"), T(key), sev > 0 and Draw.severity(sev) or C.text)
    y = self:gauge(y, {
        min = 0, max = 1, value = d.hunger, color = C.hunger,
        notches = self:notches({ Model.HUNGER_PECKISH, Model.HUNGER_HUNGRY, Model.HUNGER_VERY_HUNGRY, Model.HUNGER_STARVING }),
    })
    local text
    if d.hunger >= Model.HUNGER_HUNGRY then
        text = T("UI_NMS_Hunger_EatSoon")
    elseif f.hungryIn then
        text = T("UI_NMS_Hunger_HungryWhen", self:when(f.hungryIn))
    else
        text = T("UI_NMS_Hunger_NotSoon")
    end
    return self:detail(y, text)
end

function NMS_NutritionWindow:rowEnergy(y, d, f)
    local zone = d.reserveZone
    local color = (zone == "Depleted" and Draw.bad()) or (zone == "Low" and C.warn) or C.energy
    y = self:header(y, T("UI_NMS_Row_Energy"), T(ZONE_KEYS[zone]), color)
    y = self:gauge(y, {
        min = -1500, max = 2200, from = 0, value = d.calories, color = color,
        bands = { { -1500, 0, Draw.bad(), 0.14 }, { Model.RESERVE_LOWER, Model.RESERVE_UPPER, Draw.good(), 0.10 } },
        notches = self:notches({ 0, Model.RESERVE_LOWER, Model.RESERVE_UPPER }),
    })
    local text
    if zone == "Depleted" then
        text = T("UI_NMS_Energy_Depleted")
    elseif zone == "Low" then
        text = T("UI_NMS_Energy_DrawingFat")
    elseif zone == "Stored" then
        text = T("UI_NMS_Energy_StoringFat")
    elseif f.lowIn then
        text = T("UI_NMS_Energy_LowWhen", self:when(f.lowIn))
    end
    if self.detailed then
        local burning = T("UI_NMS_Energy_Burning", string.format("%.0f", d.burnPerHour or 0))
        text = text and (burning .. "  " .. text) or burning
    end
    return self:detail(y, text)
end

function NMS_NutritionWindow:rowProtein(y, d)
    local deficient = (d.proteinTarget or 0) > 0
    local low = d.proteins < Model.PROTEIN_LOW_WARNING
    local state = deficient and T("UI_NMS_Protein_Deficient") or low and T("UI_NMS_Protein_Low") or T("UI_NMS_Protein_Good")
    local color = deficient and Draw.bad() or low and C.warn or C.protein
    y = self:header(y, T("UI_NMS_Row_Protein"), state, color)
    y = self:gauge(y, {
        min = Model.MALNUTRITION_PROTEIN_FULL, max = 300, from = 0, value = d.proteins, color = color,
        bands = { { Model.MALNUTRITION_PROTEIN_FULL, Model.MALNUTRITION_PROTEIN_ONSET, Draw.bad(), 0.14 } },
        notches = self:notches({ Model.MALNUTRITION_PROTEIN_ONSET, Model.PROTEIN_LOW_WARNING, 0 }),
    })
    local lowDays, deficientDays = Model.proteinDaysLeft(d.proteins)
    local text
    if deficient or low then
        text = low and not deficient and T("UI_NMS_Protein_DeficientIn", self:dur(deficientDays * 24)) or nil
        y = self:detail(y, text)
        return self:detail(y, T("UI_NMS_Protein_Sources"))
    end
    return self:detail(y, T("UI_NMS_Protein_LastsFor", self:dur(lowDays * 24)))
end

function NMS_NutritionWindow:rowMalnutrition(y, d)
    local m, target = d.malnutrition, d.malnutritionTarget
    local label = T("UI_NMS_Deprivation_Header")
    if m < 0.01 and target < 0.01 then
        return self:header(y, label, T("UI_NMS_Malnutrition_None"), Draw.good())
    end
    local worsening, recovering = target > m + 0.01, target < m - 0.01
    local color = Draw.severity(m / 0.6)
    local levelKey = malnutritionLevelKey(m)
    local state = T(levelKey or "UI_NMS_Deprivation_Severity_Slight")
    if self.detailed then
        state = state .. "  " .. string.format("%d%%", math.floor(m * 100 + 0.5))
    end
    local chevron = (worsening and { up = true, color = Draw.bad() })
        or (recovering and { up = false, color = Draw.good() }) or nil
    y = self:header(y, label, state, color, chevron)
    y = self:gauge(y, {
        min = 0, max = 1, value = m, color = color, ghost = target, ghostColor = color,
        notches = self:notches(Model.MALNOURISHED_LEVELS),
    })
    if d.cause then
        y = self:detail(y, T(CAUSE_KEYS[d.cause]), C.text)
    end
    y = self:detail(y, UIHelpers.effectsText(m, self.detailed))
    if recovering then
        local clears = Model.malnutritionHoursTo(m, target, Model.MALNOURISHED_LEVELS[1])
        if clears then
            y = self:detail(y, T("UI_NMS_Malnutrition_ClearsIn", self:dur(clears)), Draw.good())
        end
    end
    return y
end

function NMS_NutritionWindow:rowWeight(y, d)
    local w, trend = d.weightKg, d.trendKgPerWeek or 0
    local chevron = math.abs(trend) >= 0.05 and { up = trend > 0, color = C.weight } or nil
    y = self:header(y, T("UI_NMS_Row_Weight"), string.format("%.1f kg", w), C.text, chevron)
    local warn, bad, good = C.warn, Draw.bad(), Draw.good()
    y = self:gauge(y, {
        min = 40, max = 115, value = w, color = C.weight, marker = true, from = w,
        bands = { { 40, 50, bad, 0.22 }, { 50, 65, bad, 0.12 }, { 65, 75, warn, 0.12 }, { 75, 85, good, 0.14 },
            { 85, 100, warn, 0.12 }, { 100, 115, bad, 0.14 } },
        notches = self:notches(Model.WEIGHT_TRAIT_BOUNDS),
    })
    local text
    if math.abs(trend) < 0.05 then
        text = T("UI_NMS_Weight_Steady")
    elseif self.detailed then
        text = T("UI_NMS_Weight_Trend", string.format("%+.2f", trend))
    else
        text = T(trend < 0 and "UI_NMS_Weight_Losing" or "UI_NMS_Weight_Gaining")
    end
    local weeks, boundary = Model.weightTraitWeeks(w, trend)
    if weeks and weeks < 26 then
        text = text .. "  " .. T("UI_NMS_Weight_Crosses_" .. tostring(boundary) .. (trend < 0 and "_Down" or "_Up"),
            self:dur(weeks * 168))
    end
    return self:detail(y, text)
end

function NMS_NutritionWindow:prerender()
    ISCollapsableWindow.prerender(self)
    if self.isCollapsed then
        return
    end
    self.widest = 0
    self.detailed = UIHelpers.isDetailed(self.playerObj)
    local pad = self.pad
    local y = self:titleBarHeight() + pad
    local d = UIHelpers.getDisplay(self.playerObj)
    if not d then
        self:drawText(T("UI_NMS_Window_Waiting"), pad, y, C.dim.r, C.dim.g, C.dim.b, 1, FONT)
        self:fitHeight(y + self.fh + pad)
        return
    end
    local f = self:refreshForecast(d)

    local text, color = verdict(d)
    self:drawText(text, pad, y, color.r, color.g, color.b, 1, FONT)
    self.widest = math.max(self.widest, Draw.textWidth(FONT, text) + pad * 2)
    y = y + self.fh + math.floor(pad * 0.6)
    self:drawRect(pad, y, self.width - pad * 2, 1, 0.18, 1, 1, 1)
    y = y + math.floor(pad * 0.8)

    local gap = math.floor(pad * 0.9)
    y = self:rowStomach(y, d) + gap
    y = self:rowHunger(y, d, f) + gap
    y = self:rowEnergy(y, d, f) + gap
    y = self:rowProtein(y, d) + gap
    y = self:rowMalnutrition(y, d) + gap
    y = self:rowWeight(y, d)
    self:fitHeight(y + pad)
    if self.widest > self.width then
        self:setWidth(self.widest)
    end
end

function NMS_NutritionWindow:fitHeight(h)
    if math.abs(self.height - h) > 1 then
        self:setHeight(h)
    end
end

function NutritionWindow.show(playerObj)
    if not playerObj then
        return
    end
    if instance and instance.playerObj ~= playerObj then
        NutritionWindow.hide()
        instance = nil
    end
    if instance then
        instance:setVisible(true)
        instance:addToUIManager()
        instance:bringToTop()
        return
    end
    local core = getCore()
    instance = NMS_NutritionWindow:new(core:getScreenWidth() - 420, 140, playerObj)
    instance:initialise()
    instance:instantiate()
    instance:addToUIManager()
    if ISLayoutManager then
        ISLayoutManager.RegisterWindow(LAYOUT_NAME, ISCollapsableWindow, instance)
    end
end

function NutritionWindow.hide()
    if instance then
        if instance.infoRichText then
            instance.infoRichText:removeFromUIManager()
        end
        instance:setVisible(false)
        instance:removeFromUIManager()
    end
end

function NutritionWindow.toggle(playerObj)
    playerObj = playerObj or (getPlayer and getPlayer() or nil)
    if instance and instance.playerObj == playerObj and instance:isReallyVisible() then
        NutritionWindow.hide()
    else
        NutritionWindow.show(playerObj)
    end
end

-- Public entry point for mods that replace the Health panel and carry the Nutrition button themselves
-- (Wounds Overhaul calls PlayerStatusPanel.toggle() and labels it with UI_NMS_StatusPanel_Button).
NutritionMakesSense.PlayerStatusPanel = { toggle = NutritionWindow.toggle }

return NutritionWindow
