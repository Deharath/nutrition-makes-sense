NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.TestPanel = NutritionMakesSense.TestPanel or {}

require "ISUI/ISTextEntryBox"
require "ISUI/ISTickBox"
require "dev/NutritionMakesSense_LiveScenarioRunner"
require "ui/NutritionMakesSense_UIHelpers"

local TestPanel = NutritionMakesSense.TestPanel
local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local Metabolism = NutritionMakesSense.Metabolism or {}
local LiveRunner = NutritionMakesSense.LiveScenarioRunner or {}
local UIHelpers = NutritionMakesSense.UIHelpers or {}

local panelInstance = nil

local W = 520
local H = 748
local PAD = 12
local ROW = 16
local FONT_S = UIFont.NewSmall
local FONT_M = UIFont.Medium
local CONTROL_ROW_H = 22
local CONTROL_LABEL_OFFSET = 12

local BG    = { r = 0.05, g = 0.06, b = 0.08, a = 0.96 }
local BORD  = { r = 0.25, g = 0.40, b = 0.48, a = 0.6 }
local HEAD  = { r = 0.42, g = 0.82, b = 0.90, a = 1.0 }
local LBL   = { r = 0.58, g = 0.64, b = 0.68, a = 1.0 }
local VAL   = { r = 0.92, g = 0.94, b = 0.95, a = 1.0 }
local DIM   = { r = 0.40, g = 0.43, b = 0.47, a = 0.9 }
local GOOD  = { r = 0.35, g = 0.70, b = 0.40, a = 1.0 }
local WARN  = { r = 0.85, g = 0.65, b = 0.20, a = 1.0 }
local BAD   = { r = 0.85, g = 0.25, b = 0.20, a = 1.0 }
local BAR_BG = { r = 0.12, g = 0.14, b = 0.16 }

local COL_LABEL = PAD + 4
local COL_VAL   = 90
local COL_TAG   = 160
local COL_BAR   = 280
local BAR_W     = W - COL_BAR - PAD - 4

local function getLocalPlayer()
    return (NutritionMakesSense.CoreUtils and NutritionMakesSense.CoreUtils.getLocalPlayer)
        and NutritionMakesSense.CoreUtils.getLocalPlayer()
        or nil
end

local function getState(player)
    return player and UIHelpers.getStateCopy and UIHelpers.getStateCopy(player) or nil
end

local function fmt(value, f)
    local n = tonumber(value)
    if n == nil then return "--" end
    return string.format(f or "%.1f", n)
end

local function colorForZone(z)
    if z == "Stored" then return GOOD end
    if z == "Ready" then return VAL end
    if z == "Low" then return WARN end
    return BAD
end

local function colorForBand(b)
    if b == "comfortable" then return GOOD end
    if b == "peckish" then return VAL end
    if b == "hungry" then return WARN end
    return BAD
end

local function colorForDepriv(d)
    if not d or d < 0.05 then return GOOD end
    if d < 0.20 then return VAL end
    if d < 0.50 then return WARN end
    return BAD
end

local function colorForOutcome(o)
    if o == "PASS" then return GOOD end
    if o == "WARN" then return WARN end
    return BAD
end

local function colorForSeverityWord(severity)
    local key = string.upper(tostring(severity or ""))
    if key == "PASS" then return GOOD end
    if key == "WARN" then return WARN end
    return BAD
end

local function drawBar(self, x, y, w, h, progress, fg)
    self:drawRect(x, y, w, h, 0.3, BAR_BG.r, BAR_BG.g, BAR_BG.b)
    local fill = math.max(0, math.min(1, tonumber(progress) or 0))
    if fill > 0 then
        self:drawRect(x, y, w * fill, h, 0.7, fg.r, fg.g, fg.b)
    end
end

local function drawKV(self, y, label, value, vc)
    vc = vc or VAL
    self:drawText(label, COL_LABEL, y, LBL.r, LBL.g, LBL.b, LBL.a, FONT_S)
    self:drawText(tostring(value or "--"), COL_VAL, y, vc.r, vc.g, vc.b, vc.a, FONT_S)
    return y + ROW
end

local function drawStateRow(self, y, label, numVal, numFmt, tag, tagColor, barProgress, barColor)
    self:drawText(label, COL_LABEL, y, LBL.r, LBL.g, LBL.b, LBL.a, FONT_S)
    self:drawText(fmt(numVal, numFmt), COL_VAL, y, VAL.r, VAL.g, VAL.b, VAL.a, FONT_S)
    if tag then
        local tc = tagColor or VAL
        self:drawText(tostring(tag), COL_TAG, y, tc.r, tc.g, tc.b, tc.a, FONT_S)
    end
    if barProgress then
        drawBar(self, COL_BAR, y + 2, BAR_W, 7, barProgress, barColor or HEAD)
    end
    return y + ROW + 2
end

local function drawSection(self, y, label)
    self:drawRect(PAD, y, W - PAD * 2, 1, 0.3, BORD.r, BORD.g, BORD.b)
    self:drawText(label, PAD, y + 2, HEAD.r, HEAD.g, HEAD.b, HEAD.a, FONT_S)
    return y + 18
end

local function currentProfileData(self)
    if not self or not self.profileCombo or not self.profileCombo.selected or self.profileCombo.selected <= 0 then
        return nil
    end
    return self.profileCombo:getOptionData(self.profileCombo.selected)
end

-- Panel class

local NMS_TestOverlay = (ISPanel and type(ISPanel.derive) == "function")
    and ISPanel:derive("NMS_TestOverlay") or nil
if not NMS_TestOverlay then NMS_TestOverlay = {} end

function NMS_TestOverlay:new(x, y)
    local p = ISPanel:new(x, y, W, H)
    setmetatable(p, self)
    self.__index = self
    p.moveWithMouse = true
    p.backgroundColor = BG
    p.borderColor = BORD
    return p
end

function NMS_TestOverlay:initialise() ISPanel.initialise(self) end

function NMS_TestOverlay:createChildren()
    ISPanel.createChildren(self)

    self.closeBtn = ISButton:new(W - 28, 4, 22, 22, "X", self, NMS_TestOverlay.onClose)
    self.closeBtn:initialise()
    self:addChild(self.closeBtn)

    local profileY = 34
    local modesY = 64
    local weightY = 94
    local traitsY = 120

    self.profileLabelY = profileY - CONTROL_LABEL_OFFSET
    self.intakeLabelY = modesY - CONTROL_LABEL_OFFSET
    self.availabilityLabelY = modesY - CONTROL_LABEL_OFFSET
    self.traitsLabelY = traitsY + 2

    local profiles = type(LiveRunner.getProfiles) == "function" and LiveRunner.getProfiles() or {}
    self.profileCombo = ISComboBox:new(PAD, profileY, 304, CONTROL_ROW_H, self, NMS_TestOverlay.onScenarioChanged)
    self.profileCombo:initialise()
    self:addChild(self.profileCombo)
    for _, profile in ipairs(profiles) do
        self.profileCombo:addOptionWithData(profile.label or profile.id, profile)
    end
    if #profiles > 0 then
        self.profileCombo.selected = 1
    end

    local triggerModes = type(LiveRunner.getTriggerModes) == "function" and LiveRunner.getTriggerModes() or {}
    self.actionBtn = ISButton:new(W - PAD - 72, profileY, 72, CONTROL_ROW_H, "Run", self, NMS_TestOverlay.onAction)
    self.actionBtn:initialise()
    self:addChild(self.actionBtn)

    self.triggerCombo = ISComboBox:new(PAD, modesY, 170, CONTROL_ROW_H, self, NMS_TestOverlay.onTriggerModeChanged)
    self.triggerCombo:initialise()
    self:addChild(self.triggerCombo)
    local currentTriggerMode = type(LiveRunner.getTriggerMode) == "function" and LiveRunner.getTriggerMode() or "strict_hunger_signal"
    for index, mode in ipairs(triggerModes) do
        self.triggerCombo:addOptionWithData(mode.label or mode.id, mode.id)
        if mode.id == currentTriggerMode then
            self.triggerCombo.selected = index
        end
    end
    if #triggerModes > 0 and (not self.triggerCombo.selected or self.triggerCombo.selected <= 0) then
        self.triggerCombo.selected = 1
    end

    local availabilityModes = type(LiveRunner.getAvailabilityModes) == "function" and LiveRunner.getAvailabilityModes() or {}
    self.availabilityCombo = ISComboBox:new(self.triggerCombo:getRight() + 8, modesY, 190, CONTROL_ROW_H, self, NMS_TestOverlay.onAvailabilityModeChanged)
    self.availabilityCombo:initialise()
    self:addChild(self.availabilityCombo)
    local currentAvailabilityMode = type(LiveRunner.getAvailabilityMode) == "function" and LiveRunner.getAvailabilityMode() or "eat_anytime"
    for index, mode in ipairs(availabilityModes) do
        self.availabilityCombo:addOptionWithData(mode.label or mode.id, mode.id)
        if mode.id == currentAvailabilityMode then
            self.availabilityCombo.selected = index
        end
    end
    if #availabilityModes > 0 and (not self.availabilityCombo.selected or self.availabilityCombo.selected <= 0) then
        self.availabilityCombo.selected = 1
    end

    self.speedLabelX = PAD
    self.speedLabelY = weightY + 1
    self.speedCombo = ISComboBox:new(PAD + 42, weightY, 72, CONTROL_ROW_H, self, NMS_TestOverlay.onSpeedChanged)
    self.speedCombo:initialise()
    self:addChild(self.speedCombo)
    local speedOptions = type(LiveRunner.getTimeMultiplierOptions) == "function" and LiveRunner.getTimeMultiplierOptions() or {}
    local currentSpeed = type(LiveRunner.getTimeMultiplier) == "function" and LiveRunner.getTimeMultiplier() or 80
    for index, option in ipairs(speedOptions) do
        self.speedCombo:addOptionWithData(option.label or tostring(option.multiplier), option.multiplier)
        if tonumber(option.multiplier) == tonumber(currentSpeed) then
            self.speedCombo.selected = index
        end
    end
    if #speedOptions > 0 and (not self.speedCombo.selected or self.speedCombo.selected <= 0) then
        self.speedCombo.selected = 1
    end

    self.startWeightLabelX = PAD + 128
    self.startWeightLabelY = weightY + 1
    self.startWeightEntry = ISTextEntryBox:new("", self.startWeightLabelX + 78, weightY, 52, 18)
    self.startWeightEntry:initialise()
    self.startWeightEntry:instantiate()
    self.startWeightEntry:setOnlyNumbers(true)
    self.startWeightEntry:setFont(FONT_S)
    self.startWeightEntry:setText(string.format("%.0f", tonumber(type(LiveRunner.getStartWeightKg) == "function" and LiveRunner.getStartWeightKg() or Metabolism.DEFAULT_WEIGHT_KG) or 80))
    self:addChild(self.startWeightEntry)

    self.startWeightUnitX = self.startWeightEntry:getRight() + 4
    self.startWeightResetBtn = ISButton:new(self.startWeightEntry:getRight() + 34, weightY, 44, 18, "Reset", self, NMS_TestOverlay.onResetStartWeight)
    self.startWeightResetBtn:initialise()
    self:addChild(self.startWeightResetBtn)

    self.traitTickBoxes = {}
    local traitOptions = type(LiveRunner.getTraitOptions) == "function" and LiveRunner.getTraitOptions() or {}
    local traitX = PAD + 52
    local traitColumnWidth = 210
    for index, trait in ipairs(traitOptions) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local tick = ISTickBox:new(traitX + (column * traitColumnWidth), traitsY + (row * 22), traitColumnWidth - 8, 18, "", self, NMS_TestOverlay.onTraitChanged, trait.id)
        tick:initialise()
        tick:instantiate()
        tick:addOption(trait.label or trait.id, trait.id)
        tick:setSelected(1, trait.selected == true)
        self:addChild(tick)
        self.traitTickBoxes[#self.traitTickBoxes + 1] = {
            id = trait.id,
            box = tick,
        }
    end

    self.controlsDividerY = traitsY + 48
    self.contentStartY = self.controlsDividerY + 10

    self:updateControls()
end

function NMS_TestOverlay:onScenarioChanged()
    self:updateControls()
end

function NMS_TestOverlay:onTriggerModeChanged()
    if not self.triggerCombo or not self.triggerCombo.selected or self.triggerCombo.selected <= 0 then
        return
    end
    local mode = self.triggerCombo:getOptionData(self.triggerCombo.selected)
    if type(LiveRunner.setTriggerMode) == "function" then
        LiveRunner.setTriggerMode(mode)
    end
end

function NMS_TestOverlay:onAvailabilityModeChanged()
    if not self.availabilityCombo or not self.availabilityCombo.selected or self.availabilityCombo.selected <= 0 then
        return
    end
    local mode = self.availabilityCombo:getOptionData(self.availabilityCombo.selected)
    if type(LiveRunner.setAvailabilityMode) == "function" then
        LiveRunner.setAvailabilityMode(mode)
    end
end

function NMS_TestOverlay:onSpeedChanged()
    if not self.speedCombo or not self.speedCombo.selected or self.speedCombo.selected <= 0 then
        return
    end
    local multiplier = self.speedCombo:getOptionData(self.speedCombo.selected)
    if type(LiveRunner.setTimeMultiplier) == "function" then
        LiveRunner.setTimeMultiplier(multiplier)
    end
end

function NMS_TestOverlay:getSelectedStartWeightKg()
    local text = self.startWeightEntry and self.startWeightEntry:getText() or nil
    local value = tonumber(text)
    if value == nil then
        value = tonumber(type(LiveRunner.getStartWeightKg) == "function" and LiveRunner.getStartWeightKg() or Metabolism.DEFAULT_WEIGHT_KG) or 80
    end
    if type(LiveRunner.setStartWeightKg) == "function" then
        value = LiveRunner.setStartWeightKg(value)
    end
    if self.startWeightEntry then
        self.startWeightEntry:setText(string.format("%.0f", tonumber(value) or 80))
    end
    return value
end

function NMS_TestOverlay:onResetStartWeight()
    local value = tonumber(Metabolism.DEFAULT_WEIGHT_KG) or 80
    if type(LiveRunner.setStartWeightKg) == "function" then
        value = LiveRunner.setStartWeightKg(value)
    end
    if self.startWeightEntry then
        self.startWeightEntry:setText(string.format("%.0f", tonumber(value) or 80))
    end
end

function NMS_TestOverlay:onRunProfile()
    local profile = currentProfileData(self)
    local profileId = profile and profile.id or nil
    self:getSelectedStartWeightKg()
    if type(LiveRunner.start) == "function" then
        LiveRunner.start(profileId)
    end
end

function NMS_TestOverlay:onAbort()
    if type(LiveRunner.abort) == "function" then
        LiveRunner.abort("panel abort")
    end
end

function NMS_TestOverlay:onAction()
    local running = type(LiveRunner.isRunning) == "function" and LiveRunner.isRunning() or false
    if running then
        self:onAbort()
    else
        self:onRunProfile()
    end
end

function NMS_TestOverlay:onTraitChanged(_, enabled, traitId)
    if type(LiveRunner.setTraitSelected) == "function" then
        LiveRunner.setTraitSelected(traitId, enabled == true)
    end
end

function NMS_TestOverlay:updateControls()
    local running = type(LiveRunner.isRunning) == "function" and LiveRunner.isRunning() or false
    local profile = currentProfileData(self)
    local forcedHungerMode = profile and (profile.consumptionMode == "signal_sequence" or profile.consumptionMode == "signal_meals")
    if self.profileCombo then
        self.profileCombo.enable = not running
    end
    if self.triggerCombo then
        self.triggerCombo.enable = (not running) and (not forcedHungerMode)
    end
    if self.availabilityCombo then
        self.availabilityCombo.enable = not running
    end
    if self.startWeightEntry then
        self.startWeightEntry:setEditable(not running)
    end
    if self.startWeightResetBtn then
        self.startWeightResetBtn.enable = not running
    end
    for _, entry in ipairs(self.traitTickBoxes or {}) do
        if entry.box then
            entry.box.enable = not running
            if type(LiveRunner.isTraitSelected) == "function" then
                local desired = LiveRunner.isTraitSelected(entry.id)
                if entry.box:isSelected(1) ~= desired then
                    entry.box:setSelected(1, desired)
                end
            end
        end
    end
    if self.actionBtn then
        self.actionBtn.title = running and "Abort" or "Run"
        self.actionBtn.tooltip = running and "Abort active live scenario run" or "Start selected live scenario"
    end
end

function NMS_TestOverlay:onClose()
    self:setVisible(false)
    self:removeFromUIManager()
    panelInstance = nil
end

function NMS_TestOverlay:prerender()
    ISPanel.prerender(self)
    self:updateControls()
    self:drawRectBorder(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)
end

function NMS_TestOverlay:render()
    ISPanel.render(self)
    self:drawText("NMS Scenario Runner", PAD, 6, HEAD.r, HEAD.g, HEAD.b, HEAD.a, FONT_M)

    local s = type(LiveRunner.getStatus) == "function" and LiveRunner.getStatus() or nil
    local player = getLocalPlayer()
    local state = getState(player)

    self:drawText("Scenario", PAD, self.profileLabelY, LBL.r, LBL.g, LBL.b, LBL.a, FONT_S)
    self:drawText("Intake", self.triggerCombo and self.triggerCombo.x or PAD, self.intakeLabelY, LBL.r, LBL.g, LBL.b, LBL.a, FONT_S)
    self:drawText("Availability", self.availabilityCombo and self.availabilityCombo.x or PAD, self.availabilityLabelY, LBL.r, LBL.g, LBL.b, LBL.a, FONT_S)
    self:drawText("Speed", self.speedLabelX or PAD, self.speedLabelY + 1, LBL.r, LBL.g, LBL.b, LBL.a, FONT_S)
    self:drawText("Start Weight", self.startWeightLabelX, self.startWeightLabelY + 1, LBL.r, LBL.g, LBL.b, LBL.a, FONT_S)
    self:drawText("kg", self.startWeightUnitX, self.startWeightLabelY + 1, DIM.r, DIM.g, DIM.b, DIM.a, FONT_S)
    self:drawText("Traits", PAD, self.traitsLabelY, LBL.r, LBL.g, LBL.b, LBL.a, FONT_S)
    self:drawRect(PAD, self.controlsDividerY, W - PAD * 2, 1, 0.3, BORD.r, BORD.g, BORD.b)

    local y = self.contentStartY or 84
    if s and s.running then
        y = self:renderRunning(s, y)
    elseif s and s.stage and s.stage ~= "" then
        y = self:renderResult(s, y)
    else
        y = self:renderIdle(state, y)
    end
end

function NMS_TestOverlay:renderIdle(state, startY)
    local y = drawSection(self, startY, "No Active Run")
    if not state then
        return drawKV(self, y, "State", "unavailable", DIM)
    end
    y = drawStateRow(self, y, "Energy", state.fuel, "%.0f", state.lastZone, colorForZone(state.lastZone), (state.fuel or 0) / 2000, colorForZone(state.lastZone))
    y = drawStateRow(self, y, "Hunger", state.visibleHunger, "%.3f", state.lastHungerBand, colorForBand(state.lastHungerBand), state.visibleHunger, colorForBand(state.lastHungerBand))
    y = drawStateRow(self, y, "Depriv", state.deprivation, "%.3f", nil, nil, state.deprivation, colorForDepriv(state.deprivation))
    y = drawStateRow(self, y, "Satiety", state.satietyBuffer, "%.3f", nil, nil, (state.satietyBuffer or 0) / 1.5, HEAD)
    y = drawKV(self, y, "Protein", fmt(state.proteins, "%.0f") .. "g")
    y = drawKV(self, y, "Weight", fmt(state.weightKg, "%.1f") .. " kg   ctrl " .. fmt(state.weightController, "%.3f"))
    y = y + 6
    return drawKV(self, y, "", "Press a profile button to start", DIM)
end

function NMS_TestOverlay:renderRunning(s, startY)
    local y = startY
    local oc = colorForOutcome(s.outcome)

    -- Header
    self:drawText("RUNNING", PAD, y, HEAD.r, HEAD.g, HEAD.b, HEAD.a, FONT_S)
    self:drawText(s.scenarioClock or "--:--", 80, y, VAL.r, VAL.g, VAL.b, VAL.a, FONT_S)
    self:drawText(s.outcome or "--", W - PAD - 40, y, oc.r, oc.g, oc.b, oc.a, FONT_S)
    y = y + 18

    -- Progress bar
    drawBar(self, PAD + 2, y, W - PAD * 2 - 4, 10, s.progress or 0, HEAD)
    y = y + 14
    self:drawText(string.format("%.1fh / %.1fh  (%.0f%%)",
        tonumber(s.elapsedHours) or 0, tonumber(s.durationHours) or 0, (s.progress or 0) * 100),
        PAD + 4, y, DIM.r, DIM.g, DIM.b, DIM.a, FONT_S)
    y = y + 20

    -- Phase & MET
    y = drawSection(self, y, "Phase & Activity")
    local phaseText = tostring(s.phaseLabel or "--")
    if s.phaseIndex and s.phasesTotal and s.phasesTotal > 0 then
        phaseText = string.format("%s  (%d/%d)", phaseText, s.phaseIndex, s.phasesTotal)
    end
    y = drawKV(self, y, "Phase", phaseText)
    local metText = s.targetMet and string.format("%.1f target", s.targetMet) or "--"
    if s.thermoReal then metText = metText .. string.format("  /  %.1f real", s.thermoReal) end
    y = drawKV(self, y, "MET", metText)
    if s.description then
        y = drawKV(self, y, "Profile", s.description, DIM)
    end
    if s.startWeightKg then
        y = drawKV(self, y, "Start Weight", string.format("%.1f kg", tonumber(s.startWeightKg) or 0))
    end
    if s.triggerMode then
        local triggerText = s.triggerMode == "strict_hunger_signal" and "Strict hunger signal"
            or s.triggerMode == "hunger_signal" and "Hunger signal"
            or "Clock"
        y = drawKV(self, y, "Intake", triggerText)
    end
    if s.availabilityMode then
        local availabilityText = s.availabilityMode == "interrupt_work_for_food" and "Interrupt work for food" or "Eat anytime"
        y = drawKV(self, y, "Availability", availabilityText)
    end
    if s.traitSummary then
        y = drawKV(self, y, "Traits", s.traitSummary, s.traitSummary == "None" and DIM or VAL)
    end

    local intakeSectionLabel = s.consumptionMode == "signal_sequence" and "Junk Intake" or "Meals"
    y = drawSection(self, y, intakeSectionLabel)
    if s.currentMealLabel then
        local eating = "Eating: " .. s.currentMealLabel
        if s.currentItemLabel then eating = eating .. "  [" .. s.currentItemLabel .. "]" end
        y = drawKV(self, y, "Active", eating, GOOD)
        if s.currentMealTrigger then
            local triggerLabel = s.currentMealTrigger == "hunger_signal" and "Hunger signal"
                or s.currentMealTrigger == "deadline" and "Deadline fallback"
                or s.currentMealTrigger == "schedule" and "Clock schedule"
                or tostring(s.currentMealTrigger)
            y = drawKV(self, y, "Trigger", triggerLabel, s.currentMealTrigger == "deadline" and WARN or DIM)
        end
        if s.phaseKind == "meal_break" and s.interruptedPhaseLabel then
            y = drawKV(self, y, "Break From", tostring(s.interruptedPhaseLabel), WARN)
            if s.interruptedPhaseRemainingHours then
                y = drawKV(self, y, "Work Left", string.format("%.2fh", tonumber(s.interruptedPhaseRemainingHours) or 0), DIM)
            end
        end
    elseif s.nextMealLabel and s.nextMealLabel ~= "--" then
        local nextAt = ""
        if s.consumptionMode == "signal_sequence" then
            local threshold = s.signalThreshold and (" on " .. tostring(s.signalThreshold)) or ""
            if s.nextSequenceEligibleHour and s.elapsedHours and s.nextSequenceEligibleHour > s.elapsedHours then
                nextAt = string.format(" after h%.1f%s", s.nextSequenceEligibleHour, threshold)
            else
                nextAt = threshold
            end
            y = drawKV(self, y, "Next Item", s.nextMealLabel .. nextAt)
        elseif s.triggerMode == "hunger_signal" or s.triggerMode == "strict_hunger_signal" then
            local earliest = s.nextMealHour and string.format(" from h%.1f", s.nextMealHour) or ""
            local deadline = s.nextMealDeadlineHour and string.format(" force h%.1f", s.nextMealDeadlineHour) or ""
            nextAt = earliest .. deadline
            y = drawKV(self, y, "Next", s.nextMealLabel .. nextAt)
        else
            nextAt = s.nextMealHour and string.format(" at h%.1f", s.nextMealHour) or ""
            y = drawKV(self, y, "Next", s.nextMealLabel .. nextAt)
        end
    else
        y = drawKV(self, y, "Status", s.consumptionMode == "signal_sequence" and "All junk items consumed" or "All meals served", DIM)
    end
    y = drawKV(self, y, "Progress", string.format("%d / %d completed", s.mealsCompleted or 0, s.mealsTotal or 0))
    if s.phaseKind == "scripted" and s.phaseRemainingHours then
        y = drawKV(self, y, "Phase Left", string.format("%.2fh", tonumber(s.phaseRemainingHours) or 0), DIM)
    end

    -- Meal log
    local mealLog = s.mealLog or {}
    if #mealLog > 0 then
        y = y + 2
        for _, entry in ipairs(mealLog) do
            local items = table.concat(entry.items or {}, ", ")
            local line = string.format("%s  %s", entry.clock or "--", entry.label or "--")
            self:drawText(line, COL_LABEL, y, GOOD.r, GOOD.g, GOOD.b, GOOD.a, FONT_S)
            y = y + ROW
            local detail = string.format("  %s", items)
            if entry.trigger then
                detail = detail .. string.format("  [%s]", tostring(entry.trigger))
            end
            if entry.depositKcal and entry.depositKcal > 0 then
                detail = detail .. string.format("  (+%.0f kcal)", entry.depositKcal)
            end
            if entry.fuelAfter then
                detail = detail .. string.format("  energy->%.0f", entry.fuelAfter)
            end
            if entry.hungerAfter then
                detail = detail .. string.format("  hgr->%.3f", entry.hungerAfter)
            end
            self:drawText(detail, COL_LABEL + 8, y, DIM.r, DIM.g, DIM.b, DIM.a, FONT_S)
            y = y + ROW
        end
    end

    -- Player State
    y = drawSection(self, y, "Player State")
    local zc = colorForZone(s.zone)
    y = drawStateRow(self, y, "Energy", s.fuel, "%.0f", s.zone, zc, (s.fuel or 0) / 2000, zc)
    local hc = colorForBand(s.hungerBand)
    y = drawStateRow(self, y, "Hunger", s.hunger, "%.3f", s.hungerBand, hc, s.hunger, hc)
    local dc = colorForDepriv(s.deprivation)
    y = drawStateRow(self, y, "Depriv", s.deprivation, "%.3f", nil, nil, s.deprivation, dc)
    y = drawStateRow(self, y, "Satiety", s.satiety, "%.3f", nil, nil, (s.satiety or 0) / 1.5, HEAD)
    y = drawKV(self, y, "Protein", s.protein and string.format("%.0fg", s.protein) or "--")
    y = drawKV(self, y, "Endurance", fmt(s.endurance, "%.2f"))
    y = drawKV(self, y, "Fatigue", fmt(s.fatigue, "%.3f"))
    y = drawKV(self, y, "Weight", s.weightKg and string.format("%.1f kg   ctrl %.3f", s.weightKg, s.weightController or 0) or "--")

    local summary = s.analysisSummary or {}
    if #summary > 0 then
        y = drawSection(self, y + 4, "Checks")
        for _, entry in ipairs(summary) do
            y = drawKV(self, y, entry.label or "--", entry.value or "--")
        end
    end

    -- Findings
    if (s.failCount or 0) > 0 or (s.warnCount or 0) > 0 then
        y = y + 2
        self:drawRect(PAD, y, W - PAD * 2, 1, 0.3, BORD.r, BORD.g, BORD.b)
        y = y + 4
        local findings = ""
        if s.failCount > 0 then findings = string.format("%d FAIL", s.failCount) end
        if s.warnCount > 0 then
            if findings ~= "" then findings = findings .. "   " end
            findings = findings .. string.format("%d WARN", s.warnCount)
        end
        self:drawText(findings, COL_LABEL, y, BAD.r, BAD.g, BAD.b, BAD.a, FONT_S)
        if s.failureReason then
            y = y + ROW
            self:drawText("Last: " .. tostring(s.failureReason), COL_LABEL, y, BAD.r, BAD.g, BAD.b, BAD.a, FONT_S)
        end
        y = y + ROW
    end

    return y
end

function NMS_TestOverlay:renderResult(s, startY)
    local y = startY
    local oc = colorForOutcome(s.outcome)
    local stageLabel = s.stage == "complete" and "COMPLETE"
        or s.stage == "aborted" and "ABORTED"
        or s.stage == "failed" and "FAILED"
        or string.upper(tostring(s.stage or "--"))

    y = drawSection(self, y, "Run " .. stageLabel)
    y = drawKV(self, y, "Outcome", s.outcome or "--", oc)
    y = drawKV(self, y, "Profile", s.label or "--")
    if s.description then y = drawKV(self, y, "Purpose", s.description, DIM) end
    if s.startWeightKg then y = drawKV(self, y, "Start Weight", string.format("%.1f kg", tonumber(s.startWeightKg) or 0)) end
    if s.triggerMode then
        y = drawKV(self, y, "Intake", s.triggerMode == "strict_hunger_signal" and "Strict hunger signal"
            or s.triggerMode == "hunger_signal" and "Hunger signal"
            or "Clock")
    end
    if s.availabilityMode then
        y = drawKV(self, y, "Availability", s.availabilityMode == "interrupt_work_for_food" and "Interrupt work for food" or "Eat anytime")
    end
    if s.traitSummary then
        y = drawKV(self, y, "Traits", s.traitSummary, s.traitSummary == "None" and DIM or VAL)
    end
    if s.lastMealTrigger then
        local triggerLabel = s.lastMealTrigger == "hunger_signal" and "Hunger signal"
            or s.lastMealTrigger == "deadline" and "Deadline fallback"
            or s.lastMealTrigger == "schedule" and "Clock schedule"
            or tostring(s.lastMealTrigger)
        y = drawKV(self, y, "Last Trigger", triggerLabel, s.lastMealTrigger == "deadline" and WARN or DIM)
    end
    if s.failureReason then y = drawKV(self, y, "Failure", s.failureReason, BAD) end
    if s.abortReason then y = drawKV(self, y, "Abort", s.abortReason, WARN) end
    if (s.failCount or 0) > 0 then y = drawKV(self, y, "Failures", tostring(s.failCount), BAD) end
    if (s.warnCount or 0) > 0 then y = drawKV(self, y, "Warnings", tostring(s.warnCount), WARN) end
    if s.reportPath then y = drawKV(self, y, "Report", tostring(s.reportPath), DIM) end

    local summary = s.analysisSummary or {}
    if #summary > 0 then
        y = y + 6
        y = drawSection(self, y, "Checks")
        for _, entry in ipairs(summary) do
            y = drawKV(self, y, entry.label or "--", entry.value or "--")
        end
    end

    local evaluations = s.analysisEvaluations or {}
    if #evaluations > 0 then
        y = y + 6
        y = drawSection(self, y, "Evaluation")
        for _, entry in ipairs(evaluations) do
            local sev = string.upper(tostring(entry.severity or "--"))
            y = drawKV(self, y, sev, entry.message or entry.code or "--", colorForSeverityWord(sev))
        end
    end

    -- Show final meal log
    local mealLog = s.mealLog or {}
    if #mealLog > 0 then
        y = y + 6
        y = drawSection(self, y, "Meal Log")
        for _, entry in ipairs(mealLog) do
            local items = table.concat(entry.items or {}, ", ")
            local line = string.format("%s  %s  -  %s", entry.clock or "--", entry.label or "--", items)
            self:drawText(line, COL_LABEL, y, GOOD.r, GOOD.g, GOOD.b, GOOD.a, FONT_S)
            y = y + ROW
        end
    end

    y = y + 10
    return drawKV(self, y, "", "Press a profile button to start a new run", DIM)
end

function NMS_TestOverlay:onMouseDown(x, y) self.moving = true; return true end
function NMS_TestOverlay:onMouseUp(x, y) self.moving = false; return true end
function NMS_TestOverlay:onMouseMove(dx, dy)
    if self.moving then self:setX(self:getX() + dx); self:setY(self:getY() + dy) end
    return true
end
function NMS_TestOverlay:onMouseMoveOutside(dx, dy)
    if self.moving then self:setX(self:getX() + dx); self:setY(self:getY() + dy) end
    return true
end

function TestPanel.toggle()
    if panelInstance and panelInstance:isVisible() then
        panelInstance:onClose()
        return
    end
    if not NMS_TestOverlay.__index and ISPanel and type(ISPanel.derive) == "function" then
        local methods = {}
        for k, v in pairs(NMS_TestOverlay) do methods[k] = v end
        NMS_TestOverlay = ISPanel:derive("NMS_TestOverlay")
        for k, v in pairs(methods) do NMS_TestOverlay[k] = v end
    end
    if not ISPanel or not NMS_TestOverlay.new then
        print("[NutritionMakesSense][ERROR] Cannot open test panel: ISPanel not available")
        return
    end
    panelInstance = NMS_TestOverlay:new(100, 100)
    panelInstance:initialise()
    panelInstance:addToUIManager()
    panelInstance:setVisible(true)
end

function TestPanel.isVisible()
    return panelInstance ~= nil and panelInstance:isVisible()
end

function TestPanel.abortActive() end
function TestPanel.onEveryOneMinute() end

return TestPanel
