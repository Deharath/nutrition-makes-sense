NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.ToolPanel = NutritionMakesSense.ToolPanel or {}

require "ISUI/ISTextEntryBox"
require "dev/NutritionMakesSense_SimRunner"
require "ui/NutritionMakesSense_UIHelpers"

local ToolPanel = NutritionMakesSense.ToolPanel
local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local Metabolism = NutritionMakesSense.Metabolism or {}
local SimRunner = NutritionMakesSense.SimRunner or {}
local UIHelpers = NutritionMakesSense.UIHelpers or {}

local panelInstance = nil

local W = 360
local H = 520
local PAD = 10
local ROW = 22
local FONT = UIFont.Small
local FONT_S = UIFont.NewSmall

local BG   = { r = 0.05, g = 0.06, b = 0.08, a = 0.96 }
local BORD  = { r = 0.25, g = 0.40, b = 0.48, a = 0.6 }
local HEAD  = { r = 0.42, g = 0.82, b = 0.90, a = 1.0 }
local LBL   = { r = 0.58, g = 0.64, b = 0.68, a = 1.0 }
local VAL   = { r = 0.92, g = 0.94, b = 0.95, a = 1.0 }
local DIM   = { r = 0.40, g = 0.43, b = 0.47, a = 0.9 }
local GOOD  = { r = 0.35, g = 0.70, b = 0.40, a = 1.0 }
local WARN  = { r = 0.85, g = 0.65, b = 0.20, a = 1.0 }
local BAD   = { r = 0.85, g = 0.25, b = 0.20, a = 1.0 }

local PRESETS = {
    {
        name = "Well Fed", color = GOOD,
        state = { fuel = 1300, deprivation = 0, satietyBuffer = 0.8, weightController = 0.05 },
        vanilla = { hunger = 0, endurance = 1, fatigue = 0 },
    },
    {
        name = "Hungry", color = WARN,
        state = { fuel = 400, deprivation = 0, satietyBuffer = 0, weightController = -0.05 },
        vanilla = { hunger = 0.35, endurance = 1, fatigue = 0 },
    },
    {
        name = "Deprived", color = WARN,
        state = { fuel = 0, deprivation = 0.6, satietyBuffer = 0, weightController = -0.2 },
        vanilla = { hunger = 0.60, endurance = 1, fatigue = 0.3 },
    },
    {
        name = "Critical", color = BAD,
        state = { fuel = 0, deprivation = 0.9, satietyBuffer = 0, weightController = -0.4 },
        vanilla = { hunger = 0.69, endurance = 0.5, fatigue = 0.5 },
    },
    {
        name = "Recovery", color = GOOD,
        state = { fuel = 800, deprivation = 0.7, satietyBuffer = 0.5, weightController = 0 },
        vanilla = { hunger = 0.20, endurance = 1, fatigue = 0.2 },
    },
}

local SIM_PROFILES = type(SimRunner.getProfiles) == "function" and SimRunner.getProfiles() or {}

local FIELDS = {
    { key = "fuel",              label = "Fuel",        fmt = "%.0f" },
    { key = "deprivation",       label = "Deprivation", fmt = "%.3f" },
    { key = "satietyBuffer",     label = "Satiety",     fmt = "%.3f" },
    { key = "proteins",          label = "Proteins",    fmt = "%.0f" },
    { key = "weightController",  label = "Controller",  fmt = "%.3f" },
    { key = "weightKg",          label = "Weight",      fmt = "%.1f" },
}

local VANILLA_FIELDS = {
    { key = "hunger",    label = "Hunger",    enum = "HUNGER",    setter = "setHunger",    fmt = "%.3f" },
    { key = "endurance", label = "Endurance", enum = "ENDURANCE", setter = "setEndurance", fmt = "%.2f" },
    { key = "fatigue",   label = "Fatigue",   enum = "FATIGUE",   setter = "setFatigue",   fmt = "%.3f" },
}

local safeCall = UIHelpers.safeCall

local function getLocalPlayer()
    return (NutritionMakesSense.CoreUtils and NutritionMakesSense.CoreUtils.getLocalPlayer)
        and NutritionMakesSense.CoreUtils.getLocalPlayer()
        or nil
end

local function getStats(player)
    return player and safeCall(player, "getStats") or nil
end

local function getStatValue(stats, enumKey)
    if not stats or not CharacterStat or not CharacterStat[enumKey] then return nil end
    return tonumber(safeCall(stats, "get", CharacterStat[enumKey]))
end

local function setStatValue(stats, enumKey, setterName, value)
    if not stats then return false end
    if CharacterStat and CharacterStat[enumKey] then
        local ok = safeCall(stats, "set", CharacterStat[enumKey], value)
        if ok ~= nil then return true end
    end
    if setterName and safeCall(stats, setterName, value) ~= nil then return true end
    return false
end

local function getState(player)
    return player and Runtime.getStateCopy and Runtime.getStateCopy(player) or nil
end

local function fmtVal(value, fmt)
    local n = tonumber(value)
    if n == nil then return "--" end
    return string.format(fmt or "%.1f", n)
end

local function applyPreset(preset)
    local player = getLocalPlayer()
    if not player then return end
    if preset.state and Runtime.debugSetStateFields then
        Runtime.debugSetStateFields(player, preset.state, "tool-preset")
    end
    if preset.vanilla and Runtime.debugSetVisibleBaselines then
        Runtime.debugSetVisibleBaselines(player, preset.vanilla, "tool-preset")
    end
end

local function applyField(key, value)
    local player = getLocalPlayer()
    if not player then return end
    if Runtime.debugSetStateFields then
        Runtime.debugSetStateFields(player, { [key] = tonumber(value) }, "tool-set")
    end
end

local function applyVanillaField(spec, value)
    local player = getLocalPlayer()
    if not player then return end
    local stats = getStats(player)
    local n = tonumber(value)
    if not stats or n == nil then return end
    if spec.key == "hunger" then
        if n > 1 then n = n / 100 end
        n = Metabolism.clamp(n, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
        if Runtime.debugSetVisibleBaselines then
            Runtime.debugSetVisibleBaselines(player, { hunger = n }, "tool-set")
        end
    else
        setStatValue(stats, spec.enum, spec.setter, n)
    end
end

local function buildSimulationStatus(summary)
    if type(summary) ~= "table" then
        return { "simulation failed" }
    end

    return {
        string.format("%s simulated", tostring(summary.label or summary.profileId or "profile")),
        string.format("Peckish %s  Hungry %s", tostring(summary.firstPeckishLabel or "--"), tostring(summary.firstHungryLabel or "--")),
        string.format("Low %s  Penalty %s", tostring(summary.firstLowLabel or "--"), tostring(summary.firstPenaltyLabel or "--")),
        string.format("Deprivation %s  Peak %.3f", tostring(summary.firstDeprivationLabel or "--"), tonumber(summary.highestDeprivation or 0)),
        string.format("End fuel %.0f  End hunger %.3f", tonumber(summary.endFuel or 0), tonumber(summary.endHunger or 0)),
        string.format("Weight %+0.3f kg", tonumber(summary.weightDeltaKg or 0)),
    }
end

-- UI

local NMS_ToolOverlay = (ISPanel and type(ISPanel.derive) == "function")
    and ISPanel:derive("NMS_ToolOverlay") or nil
if not NMS_ToolOverlay then NMS_ToolOverlay = {} end

function NMS_ToolOverlay:new(x, y)
    local p = ISPanel:new(x, y, W, H)
    setmetatable(p, self)
    self.__index = self
    p.moveWithMouse = true
    p.backgroundColor = BG
    p.borderColor = BORD
    p.entries = {}
    p.vanillaEntries = {}
    p.status = ""
    p.statusLines = {}
    p.liveStatusLines = {}
    return p
end

function NMS_ToolOverlay:initialise() ISPanel.initialise(self) end

function NMS_ToolOverlay:createChildren()
    ISPanel.createChildren(self)

    self.closeBtn = ISButton:new(W - 28, 4, 22, 22, "X", self, NMS_ToolOverlay.onClose)
    self.closeBtn:initialise()
    self:addChild(self.closeBtn)

    local y = 30
    local bw = math.floor((W - PAD * 2 - 4 * (#PRESETS - 1)) / #PRESETS)
    for i, preset in ipairs(PRESETS) do
        local bx = PAD + (i - 1) * (bw + 4)
        local btn = ISButton:new(bx, y, bw, 24, preset.name, self, NMS_ToolOverlay.onPreset)
        btn:initialise()
        btn.internal = i
        btn.borderColor = preset.color
        self:addChild(btn)
    end
    y = y + 32

    self:drawSectionAt(y, "NMS State")
    y = y + 18
    for _, spec in ipairs(FIELDS) do
        local entry = ISTextEntryBox:new("", W - PAD - 120, y, 80, 18)
        entry:initialise()
        entry:instantiate()
        entry:setOnlyNumbers(true)
        entry:setFont(FONT_S)
        self:addChild(entry)

        local btn = ISButton:new(W - PAD - 36, y, 34, 18, "Set", self, NMS_ToolOverlay.onSetField)
        btn:initialise()
        btn.internal = spec.key
        self:addChild(btn)

        self.entries[spec.key] = { entry = entry, spec = spec }
        y = y + ROW
    end

    y = y + 6
    self:drawSectionAt(y, "Vanilla Stats")
    y = y + 18
    for _, spec in ipairs(VANILLA_FIELDS) do
        local entry = ISTextEntryBox:new("", W - PAD - 120, y, 80, 18)
        entry:initialise()
        entry:instantiate()
        entry:setOnlyNumbers(true)
        entry:setFont(FONT_S)
        self:addChild(entry)

        local btn = ISButton:new(W - PAD - 36, y, 34, 18, "Set", self, NMS_ToolOverlay.onSetVanilla)
        btn:initialise()
        btn.internal = spec.key
        self:addChild(btn)

        self.vanillaEntries[spec.key] = { entry = entry, spec = spec }
        y = y + ROW
    end

    y = y + 6
    self:drawSectionAt(y, "Sim Profiles")
    y = y + 18
    for _, profile in ipairs(SIM_PROFILES) do
        local btn = ISButton:new(PAD, y, 112, 20, profile.label, self, NMS_ToolOverlay.onRunSimProfile)
        btn:initialise()
        btn.internal = profile.id
        self:addChild(btn)
        y = y + ROW
    end

    self.contentHeight = y + 100
    self:loadValues()
end

function NMS_ToolOverlay:drawSectionAt(y, label)
    -- stored for render pass
    self.sections = self.sections or {}
    self.sections[#self.sections + 1] = { y = y, label = label }
end

function NMS_ToolOverlay:loadValues()
    local player = getLocalPlayer()
    local state = getState(player)
    local stats = getStats(player)

    for _, spec in ipairs(FIELDS) do
        local e = self.entries[spec.key]
        if e and state then
            e.entry:setText(fmtVal(state[spec.key], spec.fmt))
        end
    end
    for _, spec in ipairs(VANILLA_FIELDS) do
        local e = self.vanillaEntries[spec.key]
        if e and stats then
            e.entry:setText(fmtVal(getStatValue(stats, spec.enum), spec.fmt))
        end
    end
end

function NMS_ToolOverlay:onPreset(button)
    local preset = PRESETS[button.internal]
    if not preset then return end
    applyPreset(preset)
    self:loadValues()
    self.status = preset.name .. " applied"
    self.statusLines = {}
end

function NMS_ToolOverlay:onSetField(button)
    local key = button.internal
    local e = self.entries[key]
    if not e then return end
    applyField(key, e.entry:getText())
    self:loadValues()
    self.status = key .. " set"
    self.statusLines = {}
end

function NMS_ToolOverlay:onSetVanilla(button)
    local key = button.internal
    local e = self.vanillaEntries[key]
    if not e then return end
    applyVanillaField(e.spec, e.entry:getText())
    self:loadValues()
    self.status = key .. " set"
    self.statusLines = {}
end

function NMS_ToolOverlay:onRunSimProfile(button)
    local profileId = button and button.internal or nil
    if not profileId or type(SimRunner.runProfile) ~= "function" then
        self.status = "simulation unavailable"
        self.statusLines = { "simulation unavailable" }
        return
    end

    local summary = SimRunner.runProfile(profileId)
    if not summary then
        self.status = "simulation failed"
        self.statusLines = { "simulation failed" }
        return
    end

    self.status = tostring(summary.label or profileId) .. " simulated"
    self.statusLines = buildSimulationStatus(summary)
end

function NMS_ToolOverlay:onClose()
    ToolPanel.hide()
end

function NMS_ToolOverlay:render()
    ISPanel.render(self)

    self:drawText("NMS Tools", PAD, 6, HEAD.r, HEAD.g, HEAD.b, HEAD.a, UIFont.Medium)

    for _, sec in ipairs(self.sections or {}) do
        self:drawRect(PAD, sec.y, W - PAD * 2, 1, 0.3, BORD.r, BORD.g, BORD.b)
        self:drawText(sec.label, PAD, sec.y + 2, HEAD.r, HEAD.g, HEAD.b, HEAD.a, FONT_S)
    end

    local player = getLocalPlayer()
    local state = getState(player)
    local stats = getStats(player)

    local y = 80
    for _, spec in ipairs(FIELDS) do
        self:drawText(spec.label, PAD, y + 1, LBL.r, LBL.g, LBL.b, LBL.a, FONT_S)
        local cur = state and fmtVal(state[spec.key], spec.fmt) or "--"
        self:drawText(cur, 100, y + 1, DIM.r, DIM.g, DIM.b, DIM.a, FONT_S)
        y = y + ROW
    end

    y = y + 24
    for _, spec in ipairs(VANILLA_FIELDS) do
        self:drawText(spec.label, PAD, y + 1, LBL.r, LBL.g, LBL.b, LBL.a, FONT_S)
        local cur = stats and fmtVal(getStatValue(stats, spec.enum), spec.fmt) or "--"
        self:drawText(cur, 100, y + 1, DIM.r, DIM.g, DIM.b, DIM.a, FONT_S)
        y = y + ROW
    end

    local statusY = self.contentHeight or (H - 100)
    if self.status and self.status ~= "" then
        self:drawText(self.status, PAD, statusY, DIM.r, DIM.g, DIM.b, DIM.a, FONT_S)
        statusY = statusY + 16
    end
    for _, line in ipairs(self.statusLines or {}) do
        self:drawText(line, PAD, statusY, DIM.r, DIM.g, DIM.b, DIM.a, FONT_S)
        statusY = statusY + 14
    end
end

function NMS_ToolOverlay:onMouseDown(x, y) self.moving = true; return true end
function NMS_ToolOverlay:onMouseUp(x, y) self.moving = false; return true end
function NMS_ToolOverlay:onMouseMove(dx, dy)
    if self.moving then self:setX(self:getX() + dx); self:setY(self:getY() + dy) end
    return true
end
function NMS_ToolOverlay:onMouseMoveOutside(dx, dy)
    if self.moving then self:setX(self:getX() + dx); self:setY(self:getY() + dy) end
    return true
end

function ToolPanel.show()
    if panelInstance and panelInstance:isVisible() then return end
    if not NMS_ToolOverlay.__index and ISPanel and type(ISPanel.derive) == "function" then
        local methods = {}
        for k, v in pairs(NMS_ToolOverlay) do methods[k] = v end
        NMS_ToolOverlay = ISPanel:derive("NMS_ToolOverlay")
        for k, v in pairs(methods) do NMS_ToolOverlay[k] = v end
    end
    if not ISPanel or not NMS_ToolOverlay.new then
        print("[NutritionMakesSense][ERROR] Cannot open tool panel: ISPanel not available")
        return
    end
    panelInstance = NMS_ToolOverlay:new(getCore():getScreenWidth() - W - 40, 110)
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
    if panelInstance and panelInstance:isVisible() then ToolPanel.hide() else ToolPanel.show() end
end

function ToolPanel.isVisible()
    return panelInstance ~= nil and panelInstance:isVisible()
end

return ToolPanel
