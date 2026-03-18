NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.ToolPanel = NutritionMakesSense.ToolPanel or {}

require "ISUI/ISTextEntryBox"

local ToolPanel = NutritionMakesSense.ToolPanel
local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local Metabolism = NutritionMakesSense.Metabolism or {}

local panelInstance = nil

local PANEL_W = 440
local PANEL_H = 400
local PAD = 12
local ROW_H = 26
local FONT = UIFont.Small

local COLOR_BG = { r = 0.06, g = 0.07, b = 0.09, a = 0.96 }
local COLOR_BORDER = { r = 0.30, g = 0.45, b = 0.52, a = 0.7 }
local COLOR_LABEL = { r = 0.58, g = 0.64, b = 0.68, a = 1.0 }
local COLOR_VALUE = { r = 0.92, g = 0.94, b = 0.95, a = 1.0 }
local COLOR_DIM = { r = 0.45, g = 0.48, b = 0.52, a = 0.9 }
local COLOR_HEADER = { r = 0.42, g = 0.82, b = 0.90, a = 1.0 }

local FIELD_SPECS = {
    { key = "fuel", label = "Fuel", precision = 1 },
    { key = "carbs", label = "Carbs", precision = 1 },
    { key = "fats", label = "Fats", precision = 1 },
    { key = "proteins", label = "Proteins", precision = 1 },
    { key = "energyBalanceKcal", label = "Balance", precision = 1 },
    { key = "weightKg", label = "Weight", precision = 3 },
    { key = "weightController", label = "Ctrl", precision = 3 },
}

local function log(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(msg)
    else
        print("[NutritionMakesSense] " .. tostring(msg))
    end
end

local function safeCall(target, methodName, ...)
    if not target then
        return nil
    end
    local method = target[methodName]
    if type(method) ~= "function" then
        return nil
    end
    local ok, result = pcall(method, target, ...)
    if not ok then
        return nil
    end
    return result
end

local function getLocalPlayer()
    if type(getPlayer) ~= "function" then
        return nil
    end
    local ok, playerObj = pcall(getPlayer)
    if not ok then
        return nil
    end
    return playerObj
end

local function formatNumber(value, precision)
    local numeric = tonumber(value)
    if numeric == nil then
        return "--"
    end
    return string.format("%." .. tostring(precision or 3) .. "f", numeric)
end

local function getFieldSpec(fieldKey)
    for _, spec in ipairs(FIELD_SPECS) do
        if spec.key == fieldKey then
            return spec
        end
    end
    return nil
end

local function getPlayerStats(playerObj)
    if not playerObj then return nil end
    local ok, stats = pcall(playerObj.getStats, playerObj)
    if not ok then return nil end
    return stats
end

local function getCharacterStatValue(stats, enumKey, getterName)
    if not stats then
        return nil
    end

    if CharacterStat and enumKey and CharacterStat[enumKey] then
        local value = safeCall(stats, "get", CharacterStat[enumKey])
        if value ~= nil then
            return tonumber(value)
        end
    end

    if getterName then
        local ok, value = pcall(stats[getterName], stats)
        if ok then
            return tonumber(value)
        end
    end

    return nil
end

local function normalizeVisibleHungerInput(value)
    local numeric = tonumber(value)
    if numeric == nil then
        return nil
    end
    if math.abs(numeric) > 1 then
        numeric = numeric / 100
    end
    return Metabolism.clamp(numeric, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
end

local function getVisibleHunger()
    local playerObj = getLocalPlayer()
    local stats = getPlayerStats(playerObj)
    if not stats then return nil end
    return getCharacterStatValue(stats, "HUNGER", "getHunger")
end

local function describeCurrentState()
    local playerObj = getLocalPlayer()
    local state = playerObj and Runtime.getStateCopy and Runtime.getStateCopy(playerObj) or nil
    if not state then
        return nil
    end
    return state
end

local function logSnapshot()
    local playerObj = getLocalPlayer()
    if not playerObj then
        log("[NMS_TOOL] no local player")
        return
    end

    local state = Runtime.getStateCopy and Runtime.getStateCopy(playerObj) or nil
    if not state then
        log("[NMS_TOOL] no NMS state available")
        return
    end

    log(string.format(
        "[NMS_TOOL_SNAPSHOT] fuel=%.1f carbs=%.1f fats=%.1f proteins=%.1f balance=%.1f weight=%.3f ctrl=%.3f zone=%s trait=%s queue=%d",
        tonumber(state.fuel or 0),
        tonumber(state.carbs or 0),
        tonumber(state.fats or 0),
        tonumber(state.proteins or 0),
        tonumber(state.energyBalanceKcal or 0),
        tonumber(state.weightKg or 0),
        tonumber(state.weightController or 0),
        tostring(state.lastZone or "--"),
        tostring(state.lastWeightTrait or "--"),
        tonumber(state.pendingNutritionSuppressions and #state.pendingNutritionSuppressions or 0)
    ))
end

local NMS_ToolOverlay = (ISPanel and type(ISPanel.derive) == "function")
    and ISPanel:derive("NMS_ToolOverlay")
    or nil

if not NMS_ToolOverlay then
    NMS_ToolOverlay = {}
end

function NMS_ToolOverlay:new(x, y)
    local panel = ISPanel:new(x, y, PANEL_W, PANEL_H)
    setmetatable(panel, self)
    self.__index = self
    panel.moveWithMouse = true
    panel.backgroundColor = COLOR_BG
    panel.borderColor = COLOR_BORDER
    panel.fieldEntries = {}
    panel.statusText = "ready"
    return panel
end

function NMS_ToolOverlay:initialise()
    ISPanel.initialise(self)
end

function NMS_ToolOverlay:createChildren()
    ISPanel.createChildren(self)

    self.closeBtn = ISButton:new(PANEL_W - 28, 4, 22, 22, "X", self, NMS_ToolOverlay.onClose)
    self.closeBtn:initialise()
    self:addChild(self.closeBtn)

    self.loadBtn = ISButton:new(PAD, 4, 64, 22, "Load", self, NMS_ToolOverlay.onLoad)
    self.loadBtn:initialise()
    self:addChild(self.loadBtn)

    self.snapBtn = ISButton:new(PAD + 68, 4, 74, 22, "Snapshot", self, NMS_ToolOverlay.onSnapshot)
    self.snapBtn:initialise()
    self:addChild(self.snapBtn)

    self.resetBtn = ISButton:new(PAD + 146, 4, 82, 22, "Reset NMS", self, NMS_ToolOverlay.onReset)
    self.resetBtn:initialise()
    self:addChild(self.resetBtn)

    self.clearBtn = ISButton:new(PAD + 232, 4, 84, 22, "Clear Q", self, NMS_ToolOverlay.onClearQueue)
    self.clearBtn:initialise()
    self:addChild(self.clearBtn)

    local y = 40
    for _, spec in ipairs(FIELD_SPECS) do
        local entry = ISTextEntryBox:new("", 248, y - 2, 92, 20)
        entry:initialise()
        entry:instantiate()
        entry:setOnlyNumbers(true)
        entry:setFont(UIFont.Small)
        self:addChild(entry)

        local button = ISButton:new(348, y - 2, 48, 20, "Set", self, NMS_ToolOverlay.onSetField)
        button:initialise()
        button.internal = spec.key
        self:addChild(button)

        self.fieldEntries[spec.key] = entry
        y = y + ROW_H
    end

    y = y + 4
    self.hungerEntryY = y
    local hungerEntry = ISTextEntryBox:new("", 248, y - 2, 92, 20)
    hungerEntry:initialise()
    hungerEntry:instantiate()
    hungerEntry:setOnlyNumbers(true)
    hungerEntry:setFont(UIFont.Small)
    self:addChild(hungerEntry)
    self.hungerEntry = hungerEntry

    local hungerBtn = ISButton:new(348, y - 2, 48, 20, "Set", self, NMS_ToolOverlay.onSetHunger)
    hungerBtn:initialise()
    self:addChild(hungerBtn)

    self:loadFromState()
end

function NMS_ToolOverlay:setStatus(text)
    self.statusText = tostring(text or "ready")
end

function NMS_ToolOverlay:loadFromState()
    local state = describeCurrentState()
    if not state then
        self:setStatus("no state")
        return
    end
    for _, spec in ipairs(FIELD_SPECS) do
        local entry = self.fieldEntries[spec.key]
        if entry then
            entry:setText(formatNumber(state[spec.key], spec.precision))
        end
    end
    if self.hungerEntry then
        local h = getVisibleHunger()
        self.hungerEntry:setText(formatNumber(h, 3))
    end
    self:setStatus("loaded current state")
end

function NMS_ToolOverlay:onLoad()
    self:loadFromState()
end

function NMS_ToolOverlay:onSnapshot()
    logSnapshot()
    self:setStatus("snapshot logged")
end

function NMS_ToolOverlay:onReset()
    local playerObj = getLocalPlayer()
    if not playerObj or not Runtime.debugResetState then
        self:setStatus("reset unavailable")
        return
    end
    Runtime.debugResetState(playerObj, "tool-panel-reset")
    self:loadFromState()
    self:setStatus("NMS baseline restored")
end

function NMS_ToolOverlay:onClearQueue()
    local playerObj = getLocalPlayer()
    if not playerObj or not Runtime.debugClearSuppressions then
        self:setStatus("clear unavailable")
        return
    end
    local _, cleared = Runtime.debugClearSuppressions(playerObj, "tool-panel-clear")
    self:loadFromState()
    self:setStatus(string.format("cleared queue=%d", tonumber(cleared or 0)))
end

function NMS_ToolOverlay:onSetField(button)
    local fieldKey = button and button.internal or nil
    local entry = fieldKey and self.fieldEntries[fieldKey] or nil
    local playerObj = getLocalPlayer()
    local spec = getFieldSpec(fieldKey)
    if not fieldKey or not entry or not playerObj or not spec or not Runtime.debugSetStateFields then
        self:setStatus("set unavailable")
        return
    end

    local rawText = entry:getText()
    local value = tonumber(rawText)
    if value == nil then
        self:setStatus("invalid " .. tostring(fieldKey))
        return
    end

    local before = describeCurrentState()
    Runtime.debugSetStateFields(playerObj, { [fieldKey] = value }, "tool-panel-set")
    local after = describeCurrentState()
    self:loadFromState()
    self:setStatus(string.format(
        "%s %s -> %s",
        tostring(fieldKey),
        formatNumber(before and before[fieldKey], spec.precision),
        formatNumber(after and after[fieldKey], spec.precision)
    ))
end

function NMS_ToolOverlay:onSetHunger()
    local playerObj = getLocalPlayer()
    if not playerObj or not self.hungerEntry or not Runtime.debugSetVisibleBaselines then
        self:setStatus("hunger set unavailable")
        return
    end

    local rawText = self.hungerEntry:getText()
    local value = normalizeVisibleHungerInput(rawText)
    if value == nil then
        self:setStatus("invalid hunger value")
        return
    end

    local before = getVisibleHunger()
    Runtime.debugSetVisibleBaselines(playerObj, { hunger = value }, "tool-panel-hunger")
    local after = getVisibleHunger()
    self:loadFromState()
    self:setStatus(string.format("hunger %s -> %s", formatNumber(before, 3), formatNumber(after, 3)))
end

function NMS_ToolOverlay:onClose()
    ToolPanel.hide()
end

function NMS_ToolOverlay:render()
    ISPanel.render(self)

    self:drawText("NMS Tool Panel", PAD, 8, COLOR_HEADER.r, COLOR_HEADER.g, COLOR_HEADER.b, COLOR_HEADER.a, UIFont.Medium)
    self:drawText("NMS + visible", 320, 10, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, COLOR_DIM.a, FONT)

    self:drawText("Field", PAD, 28, COLOR_LABEL.r, COLOR_LABEL.g, COLOR_LABEL.b, COLOR_LABEL.a, FONT)
    self:drawText("Current", 92, 28, COLOR_LABEL.r, COLOR_LABEL.g, COLOR_LABEL.b, COLOR_LABEL.a, FONT)
    self:drawText("Set To", 248, 28, COLOR_LABEL.r, COLOR_LABEL.g, COLOR_LABEL.b, COLOR_LABEL.a, FONT)

    local state = describeCurrentState()
    local y = 40
    for _, spec in ipairs(FIELD_SPECS) do
        self:drawText(spec.label, PAD, y, COLOR_VALUE.r, COLOR_VALUE.g, COLOR_VALUE.b, COLOR_VALUE.a, FONT)
        self:drawTextRight(
            formatNumber(state and state[spec.key], spec.precision),
            216,
            y,
            COLOR_DIM.r,
            COLOR_DIM.g,
            COLOR_DIM.b,
            COLOR_DIM.a,
            FONT
        )
        y = y + ROW_H
    end

    y = y + 4
    self:drawText("Hunger (0-1 or %)", PAD, y, COLOR_VALUE.r, COLOR_VALUE.g, COLOR_VALUE.b, COLOR_VALUE.a, FONT)
    self:drawTextRight(
        formatNumber(getVisibleHunger(), 3),
        216,
        y,
        COLOR_DIM.r,
        COLOR_DIM.g,
        COLOR_DIM.b,
        COLOR_DIM.a,
        FONT
    )
    self:drawText("(stat+NMS)", 140, y, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, COLOR_DIM.a, FONT)
    y = y + ROW_H

    y = y + 4
    self:drawText("Read-only", PAD, y, COLOR_HEADER.r, COLOR_HEADER.g, COLOR_HEADER.b, COLOR_HEADER.a, FONT)
    y = y + 20

    local queueCount = state and state.pendingNutritionSuppressions and #state.pendingNutritionSuppressions or 0
    self:drawText("Zone", PAD, y, COLOR_LABEL.r, COLOR_LABEL.g, COLOR_LABEL.b, COLOR_LABEL.a, FONT)
    self:drawTextRight(tostring(state and state.lastZone or "--"), 216, y, COLOR_VALUE.r, COLOR_VALUE.g, COLOR_VALUE.b, COLOR_VALUE.a, FONT)
    self:drawText("Trait", 230, y, COLOR_LABEL.r, COLOR_LABEL.g, COLOR_LABEL.b, COLOR_LABEL.a, FONT)
    self:drawTextRight(tostring(state and state.lastWeightTrait or "--"), PANEL_W - PAD, y, COLOR_VALUE.r, COLOR_VALUE.g, COLOR_VALUE.b, COLOR_VALUE.a, FONT)
    y = y + ROW_H

    self:drawText("Queue", PAD, y, COLOR_LABEL.r, COLOR_LABEL.g, COLOR_LABEL.b, COLOR_LABEL.a, FONT)
    self:drawTextRight(tostring(queueCount), 216, y, COLOR_VALUE.r, COLOR_VALUE.g, COLOR_VALUE.b, COLOR_VALUE.a, FONT)
    self:drawText("Trace", 230, y, COLOR_LABEL.r, COLOR_LABEL.g, COLOR_LABEL.b, COLOR_LABEL.a, FONT)
    self:drawTextRight(tostring(state and state.lastTraceReason or "--"), PANEL_W - PAD, y, COLOR_VALUE.r, COLOR_VALUE.g, COLOR_VALUE.b, COLOR_VALUE.a, FONT)

    self:drawRect(PAD, PANEL_H - 34, PANEL_W - PAD * 2, 1, 0.35, COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b)
    self:drawText(self.statusText or "ready", PAD, PANEL_H - 26, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, COLOR_DIM.a, FONT)
end

function NMS_ToolOverlay:onMouseDown(x, y)
    self.moving = true
    return true
end

function NMS_ToolOverlay:onMouseUp(x, y)
    self.moving = false
    return true
end

function NMS_ToolOverlay:onMouseMove(dx, dy)
    if self.moving then
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
    end
    return true
end

function NMS_ToolOverlay:onMouseMoveOutside(dx, dy)
    if self.moving then
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
    end
    return true
end

function ToolPanel.show()
    if panelInstance and panelInstance:isVisible() then
        return
    end

    if not NMS_ToolOverlay.__index and ISPanel and type(ISPanel.derive) == "function" then
        local methods = {}
        for key, value in pairs(NMS_ToolOverlay) do
            methods[key] = value
        end
        NMS_ToolOverlay = ISPanel:derive("NMS_ToolOverlay")
        for key, value in pairs(methods) do
            NMS_ToolOverlay[key] = value
        end
    end

    if not ISPanel or not NMS_ToolOverlay.new then
        print("[NutritionMakesSense][ERROR] Cannot open tool panel: ISPanel not available")
        return
    end

    panelInstance = NMS_ToolOverlay:new(getCore():getScreenWidth() - PANEL_W - 40, 110)
    panelInstance:initialise()
    panelInstance:addToUIManager()
    panelInstance:setVisible(true)
end

function ToolPanel.hide()
    if panelInstance then
        panelInstance:setVisible(false)
        panelInstance:removeFromUIManager()
        panelInstance = nil
    end
end

function ToolPanel.toggle()
    if panelInstance and panelInstance:isVisible() then
        ToolPanel.hide()
    else
        ToolPanel.show()
    end
end

function ToolPanel.isVisible()
    return panelInstance ~= nil and panelInstance:isVisible()
end

return ToolPanel
