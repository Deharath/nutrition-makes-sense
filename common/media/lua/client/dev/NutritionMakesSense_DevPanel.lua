NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.DevPanel = NutritionMakesSense.DevPanel or {}

require "NutritionMakesSense_DebugSupport"
require "dev/panels/NutritionMakesSense_DevPanelSink"
require "ui/NutritionMakesSense_UIHelpers"

local DevPanel = NutritionMakesSense.DevPanel
local MPClient = NutritionMakesSense.MPClientRuntime or {}
local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local Metabolism = NutritionMakesSense.Metabolism or {}
local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
local UIHelpers = NutritionMakesSense.UIHelpers or {}

local panelInstance = nil
local recording = false
local recordBuffer = {}
local recordStartMinute = nil
local recordLabel = nil
local lastSampleGameMinute = nil
local pendingRecordEvent = nil
local SAMPLE_INTERVAL_MINUTES = 1

local PANEL_W = 440
local PANEL_H = 620
local PAD = 12
local LINE_H = 18
local SECTION_GAP = 10
local BAR_H = 8
local BAR_TOP_PAD = 4
local BAR_BOT_PAD = 6
local FONT = UIFont.Medium
local FONT_S = UIFont.Small

local C = {
    bg       = { r = 0.05, g = 0.06, b = 0.08, a = 0.94 },
    border   = { r = 0.25, g = 0.38, b = 0.44, a = 0.6 },
    title    = { r = 0.40, g = 0.80, b = 0.88, a = 1.0 },
    section  = { r = 0.30, g = 0.52, b = 0.58, a = 0.9 },
    label    = { r = 0.55, g = 0.60, b = 0.64, a = 1.0 },
    value    = { r = 0.90, g = 0.92, b = 0.93, a = 1.0 },
    dim      = { r = 0.40, g = 0.43, b = 0.46, a = 0.8 },
    bar_bg   = { r = 0.10, g = 0.11, b = 0.14, a = 1.0 },
    fuel     = { r = 0.86, g = 0.56, b = 0.22, a = 1.0 },
    hunger   = { r = 0.82, g = 0.36, b = 0.30, a = 1.0 },
    satiety  = { r = 0.36, g = 0.68, b = 0.82, a = 1.0 },
    proteins = { r = 0.36, g = 0.76, b = 0.46, a = 1.0 },
    good     = { r = 0.38, g = 0.75, b = 0.42, a = 1.0 },
    warn     = { r = 0.93, g = 0.76, b = 0.27, a = 1.0 },
    bad      = { r = 0.86, g = 0.32, b = 0.28, a = 1.0 },
    rec      = { r = 0.90, g = 0.20, b = 0.20, a = 1.0 },
}

local ZONE_COLORS = {
    Depleted    = C.bad,
    Low         = C.warn,
    Ready       = C.fuel,
    Stored      = C.satiety,
}

local BAND_COLORS = {
    comfortable = C.good,
    peckish     = C.value,
    hungry      = C.warn,
    very_hungry = C.bad,
    starving    = C.bad,
}

local BAND_LABELS = {
    comfortable = "Comfortable",
    peckish     = "Peckish",
    hungry      = "Hungry",
    very_hungry = "Very Hungry",
    starving    = "Starving",
}

local safeCall = UIHelpers.safeCall

local function clamp(v, lo, hi)
    local n = tonumber(v) or lo
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function getLocalPlayer()
    return (NutritionMakesSense.CoreUtils and NutritionMakesSense.CoreUtils.getLocalPlayer)
        and NutritionMakesSense.CoreUtils.getLocalPlayer()
        or nil
end

local function getWorldAgeMinutes()
    local gt = type(getGameTime) == "function" and getGameTime() or nil
    if not gt then return 0 end
    local ok, h = pcall(gt.getWorldAgeHours, gt)
    return ok and (tonumber(h) or 0) * 60 or 0
end

local function getGameSpeed()
    local gt = type(getGameTime) == "function" and getGameTime() or nil
    if not gt then return 1 end
    local ok, v = pcall(gt.getMultiplier, gt)
    return ok and tonumber(v) or 1
end

local function getStat(stats, enumKey, getter)
    if not stats then return nil end
    if CharacterStat and enumKey and CharacterStat[enumKey] then
        local val = safeCall(stats, "get", CharacterStat[enumKey])
        if val ~= nil then return tonumber(val) end
    end
    return getter and tonumber(safeCall(stats, getter)) or nil
end

local function fmt(v, p) local n = tonumber(v); if n == nil then return "--" end; return string.format("%." .. (p or 1) .. "f", n) end
local function fmts(v, p) local n = tonumber(v); if n == nil then return "--" end; return string.format("%+." .. (p or 1) .. "f", n) end
local function pct(v) local n = tonumber(v); if n == nil then return "--" end; return string.format("%.0f%%", n * 100) end

local function computeSnapshot()
    local player = getLocalPlayer()
    if not player then return nil end
    local stats = safeCall(player, "getStats")
    local nutr = safeCall(player, "getNutrition")
    local bd = safeCall(player, "getBodyDamage")
    local projectedState = UIHelpers.getStateCopy and UIHelpers.getStateCopy(player) or nil
    local authoritativeState = UIHelpers.getAuthoritativeStateCopy and UIHelpers.getAuthoritativeStateCopy(player) or projectedState
    local projectionMeta = UIHelpers.getProjectionMeta and UIHelpers.getProjectionMeta(player) or nil
    local workload = Runtime.getCurrentWorkloadSnapshot and Runtime.getCurrentWorkloadSnapshot(player) or nil

    return {
        player = safeCall(player, "getDisplayName") or safeCall(player, "getUsername") or "player",
        hunger = getStat(stats, "HUNGER", "getHunger"),
        endurance = getStat(stats, "ENDURANCE", "getEndurance"),
        fatigue = getStat(stats, "FATIGUE", "getFatigue"),
        vanillaWeight = tonumber(safeCall(nutr, "getWeight")),
        healthFromFood = tonumber(safeCall(bd, "getHealthFromFood")),
        fedTimer = tonumber(safeCall(bd, "getHealthFromFoodTimer")),
        state = authoritativeState,
        projectedState = projectedState,
        projectionMeta = projectionMeta,
        workload = workload,
    }
end

-- Drawing helpers

local function drawRow(self, y, label, value, valueColor)
    local vc = valueColor or C.value
    self:drawText(label, PAD, y, C.label.r, C.label.g, C.label.b, C.label.a, FONT_S)
    self:drawTextRight(tostring(value), PANEL_W - PAD, y, vc.r, vc.g, vc.b, vc.a, FONT_S)
    return y + LINE_H
end

local function drawSection(self, y, title)
    y = y + SECTION_GAP
    self:drawRect(PAD, y + LINE_H - 2, PANEL_W - PAD * 2, 1, 0.2, C.section.r, C.section.g, C.section.b)
    self:drawText(title, PAD, y, C.section.r, C.section.g, C.section.b, C.section.a, FONT_S)
    return y + LINE_H + 4
end

local function drawLabeledBar(self, y, fraction, color, label, valueText)
    self:drawText(label, PAD, y, C.label.r, C.label.g, C.label.b, C.label.a, FONT_S)
    if valueText then
        self:drawTextRight(valueText, PANEL_W - PAD, y, C.value.r, C.value.g, C.value.b, C.value.a, FONT_S)
    end
    y = y + LINE_H + BAR_TOP_PAD
    local w = PANEL_W - PAD * 2
    self:drawRect(PAD, y, w, BAR_H, C.bar_bg.a, C.bar_bg.r, C.bar_bg.g, C.bar_bg.b)
    local fw = math.floor(w * clamp(fraction, 0, 1))
    if fw > 0 then
        self:drawRect(PAD, y, fw, BAR_H, color.a * 0.85, color.r, color.g, color.b)
    end
    return y + BAR_H + BAR_BOT_PAD
end

local function drawProteinReserveBar(self, y, proteins, weightKg)
    local maxP = Metabolism.getProteinAdequacyMax and Metabolism.getProteinAdequacyMax(weightKg) or Metabolism.PROTEIN_MAX or 350
    local w = PANEL_W - PAD * 2

    self:drawText("Protein Adequacy", PAD, y, C.label.r, C.label.g, C.label.b, C.label.a, FONT_S)
    self:drawTextRight(
        string.format("%s / %s g", fmt(proteins, 0), fmt(maxP, 0)),
        PANEL_W - PAD, y, C.value.r, C.value.g, C.value.b, C.value.a, FONT_S)
    y = y + LINE_H + BAR_TOP_PAD

    self:drawRect(PAD, y, w, BAR_H, C.bar_bg.a, C.bar_bg.r, C.bar_bg.g, C.bar_bg.b)
    local pw = math.floor(w * clamp(proteins / maxP, 0, 1))
    if pw > 0 then
        self:drawRect(PAD, y, pw, BAR_H, 0.8, C.proteins.r, C.proteins.g, C.proteins.b)
    end

    return y + BAR_H + BAR_BOT_PAD
end

-- Recording (CSV)

local CSV_HEADER = table.concat({
    "elapsed_min", "game_min", "game_speed",
    "auth_work_tier", "auth_met_avg", "auth_met_peak", "auth_met_source",
    "live_work_tier", "live_met_avg", "live_met_peak", "live_met_source",
    "visible_hunger", "visible_endurance", "visible_fatigue",
    "nms_fuel", "nms_zone", "nms_underfeeding_debt",
    "nms_proteins", "nms_weight_kg", "nms_weight_trait",
    "nms_weight_rate_kg_week", "nms_weight_controller",
    "nms_satiety_buffer", "nms_satiety_quality", "nms_satiety_return_factor",
    "nms_hunger_band", "nms_hunger_drop", "nms_hunger_mechanical",
    "nms_fuel_pressure", "nms_gate_mult", "nms_met_hunger_factor",
    "nms_passive_hunger_gain", "nms_burn_kcal", "nms_deposit_kcal",
    "nms_extra_endurance", "nms_end_regen_scale", "nms_end_depriv_drain",
    "nms_protein_def", "nms_protein_heal_mult",
    "nms_exertion_mult",
    "nms_deprivation", "nms_deprivation_target", "nms_deprivation_end", "nms_deprivation_fat", "nms_deprivation_melee",
    "event_reason", "event_item", "event_fraction",
    "event_pre_hunger", "event_target_hunger",
    "event_kcal", "event_carbs", "event_fats", "event_proteins",
    "event_consume_source",
}, ",")

local function csvEscape(v)
    local t = tostring(v == nil and "" or v)
    if string.find(t, "[\",\n\r]", 1) then t = "\"" .. t:gsub("\"", "\"\"") .. "\"" end
    return t
end

local function recordSample(snap)
    if not recording or not snap then return end
    local now = getWorldAgeMinutes()
    local elapsed = now - (recordStartMinute or now)
    local s = snap.state or {}
    local w = snap.workload or {}
    local ev = pendingRecordEvent

    local row = {
        string.format("%.1f", elapsed),
        string.format("%.1f", now),
        string.format("%.2f", getGameSpeed()),
        tostring(s.lastWorkTier or ""),
        tostring(s.lastMetAverage or ""),
        tostring(s.lastMetPeak or ""),
        tostring(s.lastMetSource or ""),
        tostring(w.workTier or ""),
        tostring(w.averageMet or ""),
        tostring(w.peakMet or ""),
        tostring(w.source or ""),
        tostring(snap.hunger or ""),
        tostring(snap.endurance or ""),
        tostring(snap.fatigue or ""),
        tostring(s.fuel or ""),
        tostring(s.lastZone or ""),
        tostring(s.lastUnderfeedingDebtKcal or s.underfeedingDebtKcal or ""),
        tostring(s.proteins or ""),
        tostring(s.weightKg or ""),
        tostring(s.lastWeightTrait or ""),
        tostring(s.lastWeightRateKgPerWeek or ""),
        tostring(s.weightController or ""),
        tostring(s.satietyBuffer or ""),
        tostring(s.lastSatietyQuality or ""),
        tostring(s.lastSatietyReturnFactor or ""),
        tostring(s.lastHungerBand or ""),
        tostring(s.lastImmediateHungerDrop or ""),
        tostring(s.lastImmediateHungerMechanical or ""),
        tostring(s.lastFuelPressureFactor or ""),
        tostring(s.lastGateMultiplier or ""),
        tostring(s.lastMetHungerFactor or ""),
        tostring(s.lastPassiveHungerGain or ""),
        tostring(s.lastBurnKcal or ""),
        tostring(s.lastDepositKcal or ""),
        tostring(s.lastExtraEnduranceDrain or ""),
        tostring(s.lastEnduranceRegenScale or ""),
        tostring(s.lastEnduranceDeprivDrain or ""),
        tostring(s.lastProteinDeficiency or ""),
        tostring(s.lastProteinHealingMultiplier or ""),
        tostring(s.lastExertionMultiplier or ""),
        tostring(s.deprivation or 0),
        tostring(s.lastDeprivationTarget or ""),
        tostring(Metabolism.getExertionPenaltyMultiplier(tonumber(s.deprivation) or 0)),
        tostring(Metabolism.getFatigueAccelFactor(tonumber(s.deprivation) or 0)),
        tostring(Metabolism.getMeleeDamageMultiplier(tonumber(s.deprivation) or 0)),
        tostring(ev and ev.reason or ""),
        tostring(ev and ev.item or ""),
        tostring(ev and ev.fraction or ""),
        tostring(ev and ev.pre_visible_hunger or ""),
        tostring(ev and ev.target_visible_hunger or ""),
        tostring(ev and ev.kcal or ""),
        tostring(ev and ev.carbs or ""),
        tostring(ev and ev.fats or ""),
        tostring(ev and ev.proteins or ""),
        tostring(ev and ev.consume_source or ""),
    }

    for i = 1, #row do row[i] = csvEscape(row[i]) end
    recordBuffer[#recordBuffer + 1] = table.concat(row, ",")
    pendingRecordEvent = nil
end

local function writeRecordingToFile()
    if #recordBuffer == 0 then
        print("[NutritionMakesSense] recording empty, nothing to write")
        return nil
    end
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename = "nms_recording_" .. (recordLabel or "dev") .. "_" .. timestamp .. ".csv"
    local relPath = "nmslogs/" .. filename

    local writer = nil
    if type(getFileWriter) == "function" then
        local ok, h = pcall(getFileWriter, relPath, true, false)
        if ok and h then writer = h end
    end
    if not writer then
        print("[NutritionMakesSense] failed to open file writer for " .. relPath)
        return nil
    end
    writer:writeln(CSV_HEADER)
    for i = 1, #recordBuffer do writer:writeln(recordBuffer[i]) end
    writer:close()
    print(string.format("[NutritionMakesSense] recording saved: %s (%d samples)", relPath, #recordBuffer))
    return relPath
end

function DevPanel.startRecording(label)
    if recording then DevPanel.stopRecording() end
    recordBuffer = {}
    recordStartMinute = getWorldAgeMinutes()
    lastSampleGameMinute = recordStartMinute
    recordLabel = label or "dev"
    pendingRecordEvent = nil
    recording = true
    recordSample(computeSnapshot())
    print(string.format("[NutritionMakesSense] recording started (label=%s)", recordLabel))
end

function DevPanel.stopRecording()
    if not recording then return nil end
    recording = false
    local path = writeRecordingToFile()
    local count = #recordBuffer
    recordBuffer = {}
    recordStartMinute = nil
    lastSampleGameMinute = nil
    recordLabel = nil
    pendingRecordEvent = nil
    return path, count
end

function DevPanel.isRecording() return recording end

function DevPanel.noteConsumeEvent(event)
    if type(event) ~= "table" then return end
    pendingRecordEvent = {
        reason = tostring(event.reason or ""),
        item = tostring(event.item or ""),
        consume_source = tostring(event.consume_source or ""),
        fraction = tonumber(event.fraction) or "",
        pre_visible_hunger = tonumber(event.pre_visible_hunger) or "",
        target_visible_hunger = tonumber(event.target_visible_hunger) or "",
        kcal = tonumber(event.kcal) or "",
        carbs = tonumber(event.carbs) or "",
        fats = tonumber(event.fats) or "",
        proteins = tonumber(event.proteins) or "",
    }
    if recording then
        lastSampleGameMinute = getWorldAgeMinutes()
        recordSample(computeSnapshot())
    end
end

function DevPanel.noteSeedEvent(event)
    if type(event) ~= "table" or not recording then return end
    lastSampleGameMinute = getWorldAgeMinutes()
    recordSample(computeSnapshot())
end

if NutritionMakesSense.DevPanelSink and type(NutritionMakesSense.DevPanelSink.attach) == "function" then
    NutritionMakesSense.DevPanelSink.attach(DevPanel)
end

function DevPanel.sampleTick(force)
    if not recording then return end
    local now = getWorldAgeMinutes()
    if not force and (now - (lastSampleGameMinute or now)) < SAMPLE_INTERVAL_MINUTES then return end
    recordSample(computeSnapshot())
    lastSampleGameMinute = now
end

-- Panel UI

local NMS_DevOverlay = (ISPanel and type(ISPanel.derive) == "function")
    and ISPanel:derive("NMS_DevOverlay") or nil
if not NMS_DevOverlay then NMS_DevOverlay = {} end

function NMS_DevOverlay:new(x, y)
    local p = ISPanel:new(x, y, PANEL_W, PANEL_H)
    setmetatable(p, self)
    self.__index = self
    p.moveWithMouse = true
    p.backgroundColor = C.bg
    p.borderColor = C.border
    return p
end

function NMS_DevOverlay:initialise() ISPanel.initialise(self) end

function NMS_DevOverlay:createChildren()
    ISPanel.createChildren(self)
    local bx = PAD
    self.recordBtn = ISButton:new(bx, 4, 72, 22, "Record", self, NMS_DevOverlay.onToggleRecord)
    self.recordBtn:initialise()
    self:addChild(self.recordBtn)
    bx = bx + 76

    self.resetBtn = ISButton:new(bx, 4, 58, 22, "Reset", self, NMS_DevOverlay.onReset)
    self.resetBtn:initialise()
    self:addChild(self.resetBtn)
    bx = bx + 62

    self.hunger50Btn = ISButton:new(bx, 4, 72, 22, "Hunger 50", self, NMS_DevOverlay.onSetHunger50)
    self.hunger50Btn:initialise()
    self:addChild(self.hunger50Btn)

    self.closeBtn = ISButton:new(PANEL_W - 28, 4, 22, 22, "X", self, NMS_DevOverlay.onClose)
    self.closeBtn:initialise()
    self:addChild(self.closeBtn)
    self:updateRecordButton()
end

function NMS_DevOverlay:updateRecordButton()
    if not self.recordBtn then return end
    if recording then
        self.recordBtn:setTitle("Stop (" .. #recordBuffer .. ")")
        self.recordBtn.backgroundColor = { r = 0.55, g = 0.12, b = 0.12, a = 0.92 }
        self.recordBtn.textColor = { r = 1, g = 1, b = 1, a = 1 }
    else
        self.recordBtn:setTitle("Record")
        self.recordBtn.backgroundColor = { r = 0.14, g = 0.14, b = 0.18, a = 0.92 }
        self.recordBtn.textColor = { r = 0.8, g = 0.8, b = 0.8, a = 1 }
    end
end

function NMS_DevOverlay:onToggleRecord()
    if recording then
        local path, count = DevPanel.stopRecording()
        if path then print(string.format("[NutritionMakesSense] saved %d samples -> %s", count or 0, path)) end
    else
        DevPanel.startRecording("dev")
    end
    self:updateRecordButton()
end

function NMS_DevOverlay:onReset()
    local player = getLocalPlayer()
    if not player or not Runtime.debugResetState then return end
    Runtime.debugResetState(player, "dev-panel-reset")
    print("[NutritionMakesSense] NMS state reset to defaults")
end

function NMS_DevOverlay:onSetHunger50()
    local player = getLocalPlayer()
    if not player or not Runtime.debugSetVisibleBaselines then return end
    Runtime.debugSetVisibleBaselines(player, { hunger = 0.50 }, "dev-panel-hunger50")
    print("[NutritionMakesSense] visible hunger set to 0.50")
end

function NMS_DevOverlay:onClose()
    if recording then DevPanel.stopRecording() end
    DevPanel.hide()
end

function NMS_DevOverlay:render()
    ISPanel.render(self)
    local snap = computeSnapshot()
    local y = PAD

    self:drawText("NMS Dev", PAD + 88, y, C.title.r, C.title.g, C.title.b, C.title.a, FONT)
    y = y + LINE_H + 6

    if recording then
        local elapsed = getWorldAgeMinutes() - (recordStartMinute or 0)
        self:drawText(
            string.format("REC  %d samples  %.0fm", #recordBuffer, elapsed),
            PAD + 88, y, C.rec.r, C.rec.g, C.rec.b, C.rec.a, FONT_S)
        y = y + LINE_H
    end

    if not snap then
        self:drawText("Waiting for player...", PAD, y, C.dim.r, C.dim.g, C.dim.b, C.dim.a, FONT_S)
        return
    end

    local s = snap.state or {}
    local projected = snap.projectedState or s
    local projectionMeta = snap.projectionMeta or {}

    ---------------------------------------------------------------- Sync
    y = drawSection(self, y, "Sync")
    local seqText = projectionMeta.lastSeq and tostring(projectionMeta.lastSeq) or "--"
    local ageSeconds = tonumber(projectionMeta.ageSeconds)
    local ageText = ageSeconds and string.format("%.1fs", ageSeconds) or "--"
    local stale = projectionMeta.isStale == true
    local reasonText = tostring(projectionMeta.lastReason or "--")
    y = drawRow(self, y, "Status", stale and "STALE" or "Live", stale and C.warn or C.good)
    y = drawRow(self, y, "Seq", seqText)
    y = drawRow(self, y, "Age", ageText, stale and C.warn or C.dim)
    y = drawRow(self, y, "Reason", reasonText, C.dim)

    ---------------------------------------------------------------- Hunger
    y = drawSection(self, y, "Hunger")
    local band = s.lastHungerBand or "comfortable"
    local bandColor = BAND_COLORS[band] or C.value
    local bandLabel = BAND_LABELS[band] or band
    local hungerVal = snap.hunger or 0
    y = drawLabeledBar(self, y, hungerVal, bandColor, bandLabel, fmt(hungerVal, 3))

    local satBuf = tonumber(s.satietyBuffer) or 0
    local satMax = Metabolism.SATIETY_BUFFER_MAX or 1.5
    y = drawLabeledBar(self, y, satBuf / satMax, C.satiety,
        "Satiety Buffer", fmt(satBuf, 2) .. " / " .. fmt(satMax, 1))

    local passiveGain = tonumber(s.lastPassiveHungerGain) or 0
    local retFactor = tonumber(s.lastSatietyReturnFactor) or 1
    local fuelPressure = tonumber(s.lastFuelPressureFactor) or 1
    local gateMult = tonumber(s.lastGateMultiplier) or 1
    local metFactor = tonumber(s.lastMetHungerFactor) or 1
    y = drawRow(self, y, "Rate", fmts(passiveGain, 4) .. " / tick")
    y = drawRow(self, y, "Multipliers",
        string.format("gate x%s   met x%s   sat x%s   energy x%s",
            fmt(gateMult, 2), fmt(metFactor, 2), fmt(retFactor, 2), fmt(fuelPressure, 2)))

    ---------------------------------------------------------------- Available Energy
    y = drawSection(self, y, "Available Energy")
    local fuel = tonumber(s.fuel) or 0
    local fuelMax = Metabolism.FUEL_MAX or 2000
    local zone = s.lastZone or "Ready"
    local zoneColor = ZONE_COLORS[zone] or C.fuel
    y = drawLabeledBar(self, y, fuel / fuelMax, zoneColor,
        zone, fmt(fuel, 0) .. " / " .. fmt(fuelMax, 0))

    local burn = tonumber(s.lastBurnKcal) or 0
    local deposit = tonumber(s.lastDepositKcal) or 0
    y = drawRow(self, y, "Flow",
        string.format("burn:%s kcal  dep:%s kcal", fmt(burn, 0), fmt(deposit, 0)))
    local projectedFuel = tonumber(projected.fuel)
    if projectedFuel ~= nil and math.abs(projectedFuel - fuel) >= 0.1 then
        y = drawRow(self, y, "Projected",
            string.format("%s / %s", fmt(projectedFuel, 0), fmt(fuelMax, 0)),
            C.dim)
    end

    ---------------------------------------------------------------- Protein
    y = drawSection(self, y, "Protein")
    local mp = tonumber(s.proteins) or 0
    y = drawProteinReserveBar(self, y, mp, tonumber(s.weightKg) or Metabolism.DEFAULT_WEIGHT_KG)

    local pd = tonumber(s.lastProteinDeficiency) or 0
    if pd > 0 then
        y = drawRow(self, y, "Deficiency", pct(pd), C.warn)
    end

    local protHeal = tonumber(s.lastProteinHealingMultiplier) or 1
    if math.abs(protHeal - 1) > 0.005 then
        y = drawRow(self, y, "Healing", string.format("x%s", fmt(protHeal, 2)), C.warn)
    end

    ---------------------------------------------------------------- Body
    y = drawSection(self, y, "Body")
    local wkg = tonumber(s.weightKg) or 80
    local trait = s.lastWeightTrait or "Normal"
    local rate = tonumber(s.lastWeightRateKgPerWeek) or 0
    local ctrl = tonumber(s.weightController) or 0
    local rateColor = math.abs(rate) < 0.05 and C.dim or (rate > 0 and C.warn or C.bad)
    y = drawRow(self, y, "Weight", string.format("%s kg   %s", fmt(wkg, 1), trait))
    y = drawRow(self, y, "Trend",
        string.format("%s kg/wk   ctrl: %s", fmts(rate, 2), fmts(ctrl, 3)), rateColor)
    y = drawRow(self, y, "Heal", fmt(snap.healthFromFood, 4))

    ---------------------------------------------------------------- Activity
    y = drawSection(self, y, "Activity")
    local liveWorkload = snap.workload
    local tier = s.lastWorkTier or "rest"
    local authoritativeMetAvg = tonumber(s.lastMetAverage)
    local authoritativeMetPeak = tonumber(s.lastMetPeak)
    local metAvg = authoritativeMetAvg or tonumber(liveWorkload and liveWorkload.averageMet) or 1
    local metPeak = authoritativeMetPeak or tonumber(liveWorkload and liveWorkload.peakMet) or metAvg
    local exertion = tonumber(s.lastExertionMultiplier) or 1
    y = drawRow(self, y, "Auth",
        string.format("%s   MET %s / %s", tier, fmt(metAvg, 1), fmt(metPeak, 1)))
    if liveWorkload then
        local liveAvg = tonumber(liveWorkload.averageMet)
        local livePeak = tonumber(liveWorkload.peakMet) or liveAvg
        if liveAvg ~= nil then
            y = drawRow(self, y, "Live",
                string.format("%s   MET %s / %s", tostring(liveWorkload.workTier or "--"), fmt(liveAvg, 1), fmt(livePeak or liveAvg, 1)),
                C.dim)
        end
    end

    local endurance = snap.endurance
    local fatigue = snap.fatigue
    local extraEnd = tonumber(s.lastExtraEnduranceDrain) or 0
    y = drawRow(self, y, "Endurance", string.format("%s   drain: %s   exert: x%s",
        pct(endurance), fmts(extraEnd, 4), fmt(exertion, 2)))
    y = drawRow(self, y, "Fatigue", pct(fatigue))

    local deprivation = tonumber(s.deprivation) or 0
    local depDebt = tonumber(s.lastUnderfeedingDebtKcal or s.underfeedingDebtKcal) or 0
    local depTarget = tonumber(s.lastDeprivationTarget) or 0
    local endPenalty = Metabolism.getExertionPenaltyMultiplier(deprivation)
    local fatAccel = Metabolism.getFatigueAccelFactor(deprivation)
    local meleeMult = Metabolism.getMeleeDamageMultiplier(deprivation)
    if deprivation > 0.01 or depDebt > 1 or endPenalty > 1.005 then
        y = drawSection(self, y, "Deprivation")
        local depColor = deprivation > 0.5 and C.bad or deprivation > 0.1 and C.warn or C.dim
        y = drawLabeledBar(self, y, deprivation, depColor,
            "Deprivation", fmt(deprivation, 3) .. " / 1.0")
        if depDebt > 1 or depTarget > 0.001 then
            y = drawRow(self, y, "Recent Debt",
                string.format("%s kcal  target:%s", fmt(depDebt, 0), fmt(depTarget, 3)),
                C.dim)
        end
        if endPenalty > 1.005 or fatAccel > 1.005 or meleeMult < 0.995 then
            y = drawRow(self, y, "Penalties",
                string.format("end:x%s  fat:x%s  melee:x%s",
                    fmt(endPenalty, 2), fmt(fatAccel, 2), fmt(meleeMult, 2)),
                C.warn)
        end
    end

    ---------------------------------------------------------------- Last Eat
    local drop = tonumber(s.lastImmediateHungerDrop) or 0
    local mech = tonumber(s.lastImmediateHungerMechanical) or 0
    local sq = tonumber(s.lastSatietyQuality) or 0
    local sc = tonumber(s.lastSatietyContribution) or 0
    if drop > 0 or mech > 0 then
        y = drawSection(self, y, "Last Eat")
        y = drawRow(self, y, "Fill",
            string.format("drop:%s  mech:%s", fmt(drop, 3), fmt(mech, 3)))
        y = drawRow(self, y, "Satiety",
            string.format("quality:%s  added:%s", fmt(sq, 2), fmt(sc, 2)))
    end

    local neededH = y + PAD
    if math.abs(neededH - self.height) > 2 then self:setHeight(neededH) end
end

function NMS_DevOverlay:update()
    ISPanel.update(self)
    self:updateRecordButton()
    DevPanel.sampleTick(false)
end

function NMS_DevOverlay:onMouseDown(x, y) self.moving = true; return true end
function NMS_DevOverlay:onMouseUp(x, y) self.moving = false; return true end
function NMS_DevOverlay:onMouseMove(dx, dy)
    if self.moving then self:setX(self:getX() + dx); self:setY(self:getY() + dy) end
    return true
end
function NMS_DevOverlay:onMouseMoveOutside(dx, dy)
    if self.moving then self:setX(self:getX() + dx); self:setY(self:getY() + dy) end
    return true
end

function DevPanel.show()
    if panelInstance and panelInstance:isVisible() then return end
    if not NMS_DevOverlay.__index and ISPanel and type(ISPanel.derive) == "function" then
        local methods = {}
        for k, v in pairs(NMS_DevOverlay) do methods[k] = v end
        NMS_DevOverlay = ISPanel:derive("NMS_DevOverlay")
        for k, v in pairs(methods) do NMS_DevOverlay[k] = v end
    end
    if not ISPanel or not NMS_DevOverlay.new then
        print("[NutritionMakesSense][ERROR] Cannot open dev panel: ISPanel not available")
        return
    end
    local x = getCore():getScreenWidth() - PANEL_W - 30
    panelInstance = NMS_DevOverlay:new(x, 80)
    panelInstance:initialise()
    panelInstance:addToUIManager()
    panelInstance:setVisible(true)
end

function DevPanel.hide()
    if panelInstance then
        panelInstance:setVisible(false)
        panelInstance:removeFromUIManager()
        panelInstance = nil
    end
end

function DevPanel.toggle()
    if panelInstance and panelInstance:isVisible() then DevPanel.hide() else DevPanel.show() end
end

function DevPanel.isVisible()
    return panelInstance ~= nil and panelInstance:isVisible()
end

function NMS_DevPanel()
    local ok, err = pcall(DevPanel.toggle)
    if not ok then print("[NutritionMakesSense][ERROR] NMS_DevPanel: " .. tostring(err)) end
end

local function onTickSampler()
    if recording then
        DevPanel.sampleTick(false)
    end
end

if Events and Events.OnTick and type(Events.OnTick.Add) == "function" then
    Events.OnTick.Add(onTickSampler)
end

return DevPanel
