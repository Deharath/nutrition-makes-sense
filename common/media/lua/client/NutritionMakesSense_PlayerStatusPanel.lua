NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.PlayerStatusPanel = NutritionMakesSense.PlayerStatusPanel or {}

require "ui/NutritionMakesSense_UIHelpers"
require "NutritionMakesSense_Metabolism"

local PlayerStatusPanel = NutritionMakesSense.PlayerStatusPanel
local UIHelpers = NutritionMakesSense.UIHelpers or {}
local Metabolism = NutritionMakesSense.Metabolism or {}

local panelInstance = nil

local W = 380
local H = 220
local PAD = 12
local LINE_H = 18
local BAR_H = 8
local FONT = UIFont.Small
local FONT_TITLE = UIFont.Medium

local C = {
    bg = { r = 0.05, g = 0.06, b = 0.06, a = 0.94 },
    border = { r = 0.34, g = 0.36, b = 0.34, a = 0.75 },
    title = { r = 0.86, g = 0.88, b = 0.82, a = 1.0 },
    section = { r = 0.58, g = 0.62, b = 0.54, a = 1.0 },
    label = { r = 0.66, g = 0.68, b = 0.62, a = 1.0 },
    text = { r = 0.90, g = 0.91, b = 0.86, a = 1.0 },
    dim = { r = 0.50, g = 0.52, b = 0.48, a = 1.0 },
    bar = { r = 0.12, g = 0.13, b = 0.12, a = 1.0 },
    good = { r = 0.42, g = 0.72, b = 0.42, a = 1.0 },
    warn = { r = 0.90, g = 0.72, b = 0.30, a = 1.0 },
    bad = { r = 0.82, g = 0.34, b = 0.30, a = 1.0 },
    energy = { r = 0.84, g = 0.58, b = 0.28, a = 1.0 },
    satiety = { r = 0.42, g = 0.64, b = 0.74, a = 1.0 },
    protein = { r = 0.46, g = 0.70, b = 0.48, a = 1.0 },
}

local ZONE_LABELS = {
    Depleted = "Depleted",
    Low = "Low",
    Ready = "Ready",
    Stored = "Stored",
}

local HUNGER_LABELS = {
    comfortable = "Comfortable",
    peckish = "Peckish",
    hungry = "Hungry",
    very_hungry = "Very Hungry",
    starving = "Starving",
}

local function tr(key, fallback)
    return UIHelpers.tr and UIHelpers.tr(key, fallback) or fallback or key
end

local function safeCall(target, methodName, ...)
    return UIHelpers.safeCall and UIHelpers.safeCall(target, methodName, ...) or nil
end

local function clamp(value, minValue, maxValue)
    if Metabolism.clamp then
        return Metabolism.clamp(value, minValue, maxValue)
    end
    local numeric = tonumber(value) or minValue
    if numeric < minValue then return minValue end
    if numeric > maxValue then return maxValue end
    return numeric
end

local function fmt(value, decimals)
    local numeric = tonumber(value)
    if numeric == nil then
        return "--"
    end
    return string.format("%." .. tostring(decimals or 0) .. "f", numeric)
end

local function pct(value)
    local numeric = tonumber(value)
    if numeric == nil then
        return "--"
    end
    return string.format("%.0f%%", clamp(numeric, 0, 1) * 100)
end

local function getLocalPlayer()
    local coreUtils = NutritionMakesSense.CoreUtils or {}
    if type(coreUtils.getLocalPlayer) == "function" then
        return coreUtils.getLocalPlayer()
    end
    return type(getPlayer) == "function" and getPlayer() or nil
end

local function getStat(stats, enumKey, getterName)
    if not stats then
        return nil
    end
    if CharacterStat and CharacterStat[enumKey] then
        local value = safeCall(stats, "get", CharacterStat[enumKey])
        if value ~= nil then
            return tonumber(value)
        end
    end
    return getterName and tonumber(safeCall(stats, getterName)) or nil
end

local function colorForFraction(value)
    local numeric = tonumber(value) or 0
    if numeric >= 0.65 then return C.good end
    if numeric >= 0.30 then return C.warn end
    return C.bad
end

local function computeSnapshot()
    local player = getLocalPlayer()
    if not player then
        return nil
    end

    local stats = safeCall(player, "getStats")
    local state = UIHelpers.getStateCopy and UIHelpers.getStateCopy(player) or nil
    local weightKg = tonumber(state and state.weightKg) or Metabolism.DEFAULT_WEIGHT_KG
    local proteinMax = Metabolism.getProteinAdequacyMax and Metabolism.getProteinAdequacyMax(weightKg) or Metabolism.PROTEIN_MAX or 350

    return {
        hunger = getStat(stats, "HUNGER", "getHunger"),
        state = state,
        proteinMax = proteinMax,
    }
end

local function drawBar(self, y, label, valueText, fraction, color)
    self:drawText(label, PAD, y, C.label.r, C.label.g, C.label.b, C.label.a, FONT)
    self:drawTextRight(valueText, W - PAD, y, C.text.r, C.text.g, C.text.b, C.text.a, FONT)
    y = y + LINE_H + 3

    local barWidth = W - PAD * 2
    self:drawRect(PAD, y, barWidth, BAR_H, C.bar.a, C.bar.r, C.bar.g, C.bar.b)
    local fillWidth = math.floor(barWidth * clamp(fraction, 0, 1))
    if fillWidth > 0 then
        self:drawRect(PAD, y, fillWidth, BAR_H, 0.85, color.r, color.g, color.b)
    end

    return y + BAR_H + 5
end

local NMS_PlayerStatusWindow = (ISPanel and type(ISPanel.derive) == "function")
    and ISPanel:derive("NMS_PlayerStatusWindow") or nil
if not NMS_PlayerStatusWindow then
    NMS_PlayerStatusWindow = {}
end

function NMS_PlayerStatusWindow:new(x, y)
    local panel = ISPanel:new(x, y, W, H)
    setmetatable(panel, self)
    self.__index = self
    panel.backgroundColor = C.bg
    panel.borderColor = C.border
    panel.moveWithMouse = true
    return panel
end

function NMS_PlayerStatusWindow:initialise()
    ISPanel.initialise(self)
end

function NMS_PlayerStatusWindow:createChildren()
    ISPanel.createChildren(self)
    self.closeBtn = ISButton:new(W - 28, 4, 22, 22, "X", self, NMS_PlayerStatusWindow.onClose)
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self:addChild(self.closeBtn)
end

function NMS_PlayerStatusWindow:onClose()
    PlayerStatusPanel.hide()
end

function NMS_PlayerStatusWindow:render()
    ISPanel.render(self)

    local snap = computeSnapshot()
    local y = PAD
    self:drawText(tr("UI_NMS_StatusPanel_Title", "Nutrition Status"), PAD, y, C.title.r, C.title.g, C.title.b, C.title.a, FONT_TITLE)
    y = y + LINE_H + 8

    if not snap or not snap.state then
        self:drawText(tr("UI_NMS_StatusPanel_Waiting", "Waiting for nutrition data..."), PAD, y, C.dim.r, C.dim.g, C.dim.b, C.dim.a, FONT)
        return
    end

    local state = snap.state
    local fuel = tonumber(state.fuel) or 0
    local fuelMax = tonumber(Metabolism.FUEL_MAX) or 2000
    local zone = tostring(state.lastZone or (Metabolism.getFuelZone and Metabolism.getFuelZone(fuel)) or "Ready")
    local hunger = tonumber(snap.hunger) or 0
    local hungerBand = tostring(state.lastHungerBand or "comfortable")
    local satiety = tonumber(state.satietyBuffer) or 0
    local satietyMax = tonumber(Metabolism.SATIETY_BUFFER_MAX) or 1.5
    local protein = tonumber(state.proteins) or 0
    local proteinMax = tonumber(snap.proteinMax) or 350

    y = drawBar(self, y, tr("UI_NMS_StatusPanel_Energy", "Energy"),
        string.format("%s / %s kcal  %s", fmt(fuel, 0), fmt(fuelMax, 0), ZONE_LABELS[zone] or zone),
        fuel / fuelMax, colorForFraction(fuel / fuelMax))
    y = drawBar(self, y, tr("UI_NMS_StatusPanel_Hunger", "Hunger"),
        string.format("%s  %s", pct(hunger), HUNGER_LABELS[hungerBand] or hungerBand),
        hunger, hunger >= 0.45 and C.bad or hunger >= 0.25 and C.warn or C.good)
    y = drawBar(self, y, tr("UI_NMS_StatusPanel_Satiety", "Meal Satiety"),
        string.format("%s / %s", fmt(satiety, 2), fmt(satietyMax, 1)),
        satiety / satietyMax, C.satiety)

    y = drawBar(self, y, tr("UI_NMS_StatusPanel_Protein", "Protein Adequacy"),
        string.format("%s / %s g", fmt(protein, 0), fmt(proteinMax, 0)),
        protein / proteinMax, C.protein)

    local needed = y + PAD
    if math.abs(needed - self.height) > 2 then
        self:setHeight(needed)
    end
end

function NMS_PlayerStatusWindow:onMouseDown()
    self.moving = true
    return true
end

function NMS_PlayerStatusWindow:onMouseUp()
    self.moving = false
    return true
end

function NMS_PlayerStatusWindow:onMouseMove(dx, dy)
    if self.moving then
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
    end
    return true
end

function NMS_PlayerStatusWindow:onMouseMoveOutside(dx, dy)
    if self.moving then
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
    end
    return true
end

function PlayerStatusPanel.show()
    if panelInstance and panelInstance:isVisible() then
        return
    end

    if not NMS_PlayerStatusWindow.__index and ISPanel and type(ISPanel.derive) == "function" then
        local methods = {}
        for key, value in pairs(NMS_PlayerStatusWindow) do
            methods[key] = value
        end
        NMS_PlayerStatusWindow = ISPanel:derive("NMS_PlayerStatusWindow")
        for key, value in pairs(methods) do
            NMS_PlayerStatusWindow[key] = value
        end
    end

    if not ISPanel or not NMS_PlayerStatusWindow.new then
        print("[NutritionMakesSense][ERROR] Cannot open player status panel: ISPanel not available")
        return
    end

    local core = getCore and getCore() or nil
    local screenW = core and core:getScreenWidth() or 1024
    local x = math.max(20, screenW - W - 40)
    panelInstance = NMS_PlayerStatusWindow:new(x, 120)
    panelInstance:initialise()
    panelInstance:addToUIManager()
    panelInstance:setVisible(true)
end

function PlayerStatusPanel.hide()
    if panelInstance then
        panelInstance:setVisible(false)
        panelInstance:removeFromUIManager()
        panelInstance = nil
    end
end

function PlayerStatusPanel.toggle()
    if panelInstance and panelInstance:isVisible() then
        PlayerStatusPanel.hide()
    else
        PlayerStatusPanel.show()
    end
end

function PlayerStatusPanel.isVisible()
    return panelInstance ~= nil and panelInstance:isVisible()
end

function PlayerStatusPanel.install()
    if PlayerStatusPanel._installed then
        return PlayerStatusPanel
    end
    PlayerStatusPanel._installed = true

    return PlayerStatusPanel
end

function NMS_NutritionStatus()
    local ok, err = pcall(PlayerStatusPanel.toggle)
    if not ok then
        print("[NutritionMakesSense][ERROR] NMS_NutritionStatus: " .. tostring(err))
    end
end

return PlayerStatusPanel
