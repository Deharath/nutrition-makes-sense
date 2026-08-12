NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.DevPanel = NutritionMakesSense.DevPanel or {}

require "NutritionMakesSense_DebugSupport"
require "NutritionMakesSense_Settings"
require "dev/NutritionMakesSense_CompatTraceClient"
require "dev/panels/NutritionMakesSense_DevPanelSink"
require "ui/NutritionMakesSense_UIHelpers"

local DevPanel = NutritionMakesSense.DevPanel
local CompatTrace = NutritionMakesSense.CompatTraceClient or {}
local MPClient = NutritionMakesSense.MPClientRuntime or {}
local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local Metabolism = NutritionMakesSense.Metabolism or {}
local UIHelpers = NutritionMakesSense.UIHelpers or {}
local Settings = NutritionMakesSense.Settings or {}
local MP = NutritionMakesSense.MP or {}

local panelInstance = nil
local recording = false
local recordBuffer = {}
local recordStartMinute = nil
local recordLabel = nil
local lastSampleGameMinute = nil
local lastRecordingRowMinute = nil
local recordingBaselines = nil
local recordingLastTotals = nil
local lastTransitionSnapshot = nil
local pendingFoodActions = {}
local nextFoodActionId = 0
local SAMPLE_INTERVAL_MINUTES = 1
local RECORDING_SCHEMA_VERSION = 2

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

local clamp = Metabolism.clamp or function(v, lo, hi)
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

local function getMoodleLevel(player, moodleType)
    local moodles = player and safeCall(player, "getMoodles") or nil
    if not moodles or not moodleType then return nil end
    return tonumber(safeCall(moodles, "getMoodleLevel", moodleType))
end

local function getThermoSnapshot(bodyDamage)
    local thermo = bodyDamage and safeCall(bodyDamage, "getThermoregulator") or nil
    return {
        target = tonumber(thermo and safeCall(thermo, "getMetabolicTarget")),
        real = tonumber(thermo and safeCall(thermo, "getMetabolicRateReal")),
    }
end

local function getMovementMode(player)
    if safeCall(player, "isAsleep") == true then return "sleep" end
    if safeCall(player, "isAttacking") == true then return "attack" end
    if safeCall(player, "isSprinting") == true then return "sprint" end
    if safeCall(player, "isRunning") == true then return "run" end
    if safeCall(player, "isSneaking") == true and safeCall(player, "isPlayerMoving") == true then return "sneak" end
    if safeCall(player, "isPlayerMoving") == true then return "walk" end
    if safeCall(player, "hasTimedActions") == true then return "timed_action" end
    return "stationary"
end

local function getRuntimeRole()
    local client = type(isClient) == "function" and isClient() == true
    local server = type(isServer) == "function" and isServer() == true
    if client and server then return "listen_server" end
    if client then return "mp_client" end
    if server then return "dedicated_server" end
    return "singleplayer"
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
    local authoritativeState = UIHelpers.getStateCopy and UIHelpers.getStateCopy(player) or nil
    local snapshotMeta = UIHelpers.getSnapshotMeta and UIHelpers.getSnapshotMeta(player) or nil
    local workload = Runtime.getCurrentWorkloadSnapshot and Runtime.getCurrentWorkloadSnapshot(player) or nil
    local thermo = getThermoSnapshot(bd)
    local snapshotState = authoritativeState or {}

    return {
        player = safeCall(player, "getDisplayName") or safeCall(player, "getUsername") or "player",
        hunger = getStat(stats, "HUNGER", "getHunger"),
        endurance = getStat(stats, "ENDURANCE", "getEndurance"),
        fatigue = getStat(stats, "FATIGUE", "getFatigue"),
        vanillaWeight = tonumber(safeCall(nutr, "getWeight")),
        healthFromFood = tonumber(safeCall(bd, "getHealthFromFood")),
        fedTimer = tonumber(safeCall(bd, "getHealthFromFoodTimer")),
        state = authoritativeState,
        snapshotMeta = snapshotMeta,
        workload = workload,
        authoritativeHunger = tonumber(snapshotState.visibleHunger),
        lastSyncedHunger = tonumber(snapshotState.lastSyncedHunger),
        hungryMoodle = getMoodleLevel(player, MoodleType and MoodleType.HUNGRY or nil),
        foodEatenMoodle = getMoodleLevel(player, MoodleType and MoodleType.FOOD_EATEN or nil),
        thermoTarget = thermo.target,
        thermoReal = thermo.real,
        runtimeRole = getRuntimeRole(),
        movementMode = getMovementMode(player),
        asleep = safeCall(player, "isAsleep") == true,
        moving = safeCall(player, "isPlayerMoving") == true,
        running = safeCall(player, "isRunning") == true,
        sprinting = safeCall(player, "isSprinting") == true,
        sneaking = safeCall(player, "isSneaking") == true,
        attacking = safeCall(player, "isAttacking") == true,
        timedAction = safeCall(player, "hasTimedActions") == true,
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

-- Recording (CSV-formatted text; B42.20 only permits a small file-extension allowlist)

local CSV_COLUMNS = {
    "row_kind", "row_trigger",
    "elapsed_min", "game_min", "interval_game_hours", "game_speed", "runtime_role",
    "auth_work_tier", "auth_met_avg", "auth_met_peak", "auth_met_source",
    "live_work_tier", "live_met_avg", "live_met_peak", "live_met_source",
    "thermo_target_met", "thermo_real_met",
    "movement_mode", "is_asleep", "is_moving", "is_running", "is_sprinting",
    "is_sneaking", "is_attacking", "has_timed_action",
    "visible_hunger", "local_hunger", "auth_visible_hunger", "last_synced_hunger",
    "hungry_moodle", "food_eaten_moodle", "health_from_food", "health_from_food_timer",
    "visible_endurance", "visible_fatigue",
    "nms_fuel", "nms_zone",
    "nms_proteins", "nms_weight_kg", "nms_weight_trait",
    "nms_weight_rate_kg_week", "nms_weight_controller",
    "nms_weight_balance_kcal", "nms_weight_controller_target", "nms_deposit_sequence",
    "nms_satiety_buffer", "nms_satiety_quality", "nms_satiety_return_factor",
    "nms_hunger_band", "nms_meal_deposit_kcal", "nms_meal_transaction_fragments",
    "nms_meal_hunger_drop", "nms_meal_modeled_drop",
    "nms_meal_mechanical_drop", "nms_meal_physical_drop", "nms_meal_nutrient_drop",
    "nms_meal_hunger_correction", "nms_meal_pre_hunger", "nms_meal_target_hunger",
    "nms_meal_hunger_observed",
    "nms_fuel_pressure", "nms_hunger_rate_mult", "nms_stats_decrease_mult",
    "nms_appetite_rate_mult", "nms_energy_burn_mult", "nms_gate_mult", "nms_met_hunger_factor",
    "nms_energy_appetite_progress", "nms_energy_appetite_rate_hour",
    "nms_satiety_contribution", "nms_base_hunger_gain", "nms_passive_hunger_gain",
    "nms_observed_hours", "nms_heavy_hours", "nms_very_heavy_hours",
    "nms_burn_kcal", "nms_deposit_kcal",
    "nms_total_intake_kcal", "nms_total_burn_kcal", "nms_total_hunger_gain",
    "nms_total_observed_hours", "nms_total_sleep_hours",
    "run_intake_kcal", "run_burn_kcal", "run_net_kcal", "run_hunger_gain",
    "run_observed_hours", "run_awake_hours", "run_sleep_hours",
    "interval_intake_kcal", "interval_burn_kcal", "interval_hunger_gain",
    "nms_extra_endurance", "nms_end_regen_scale", "nms_end_depriv_drain",
    "nms_protein_def", "nms_protein_heal_mult",
    "nms_deprivation", "nms_deprivation_target",
    "event_reason", "event_item", "event_fraction",
    "event_correlation_id", "event_deposit_sequence_before",
    "event_item_known", "event_provenance",
    "event_pre_hunger", "event_target_hunger",
    "event_kcal", "event_carbs", "event_fats", "event_proteins",
    "event_consume_source", "event_observed_hunger_drop", "event_hunger_observed",
    "event_vanilla_hunger", "event_mechanical_hunger_drop", "event_physical_hunger_drop",
    "event_nutrient_hunger_drop", "event_modeled_hunger_drop", "event_applied_hunger_drop",
    "event_hunger_correction", "event_meal_transaction_kcal", "event_meal_transaction_fragments",
    "event_item_name", "event_item_id", "event_item_hunger_change", "event_item_base_hunger",
    "event_item_kcal", "event_item_carbs", "event_item_fats", "event_item_proteins",
    "event_item_uses", "event_item_max_uses", "event_item_cooked", "event_item_burnt",
    "event_item_frozen", "event_item_rotten", "event_item_ingredients", "event_item_spices",
    "event_item_chef",
    "mp_snapshot_seq", "mp_snapshot_age_seconds", "mp_snapshot_stale", "mp_snapshot_reason",
    "mp_server_world_hours", "mp_server_wall_seconds",
    "mp_workload_seq", "mp_workload_age_seconds", "mp_workload_average_met",
    "mp_workload_peak_met", "mp_workload_source", "mp_workload_reason",
    "mp_authoritative_hunger", "mp_display_hunger_target", "mp_server_deposit_sequence",
    "mp_prediction_active", "mp_prediction_target_hunger", "mp_prediction_age_seconds",
    "mp_prediction_baseline_snapshot_seq", "mp_prediction_baseline_deposit_sequence",
    "mp_prediction_last_server_deposit_sequence", "mp_prediction_resolution",
    "state_transitions", "meta_key", "meta_value",
}
local CSV_HEADER = table.concat(CSV_COLUMNS, ",")

local function csvEscape(v)
    local t = tostring(v == nil and "" or v)
    if string.find(t, "[\",\n\r]", 1) then t = "\"" .. t:gsub("\"", "\"\"") .. "\"" end
    return t
end

local function appendRecordingRow(row)
    for i = 1, #row do
        row[i] = csvEscape(row[i])
    end
    recordBuffer[#recordBuffer + 1] = table.concat(row, ",")
end

local function appendRecordingValues(values)
    local row = {}
    for index, column in ipairs(CSV_COLUMNS) do
        local value = nil
        if values then value = values[column] end
        row[index] = value == nil and "" or value
    end
    appendRecordingRow(row)
end

local function normalizeTimelineEvent(kind, trigger, event)
    if type(event) ~= "table" then
        return {
            kind = kind or "event",
            trigger = trigger or "",
        }
    end

    local item = tostring(event.item or "")
    local itemKnown = event.item_known
    if itemKnown == nil then
        itemKnown = item ~= ""
    end

    local provenance = tostring(event.provenance or "")
    if provenance == "" and (item ~= "" or kind == "consume" or kind == "food_action") then
        provenance = itemKnown and "explicit-item" or "observed-delta"
    end

    return {
        kind = kind or "event",
        trigger = trigger or "",
        reason = tostring(event.reason or ""),
        item = item,
        fraction = tonumber(event.fraction) or "",
        correlation_id = tostring(event.correlation_id or ""),
        deposit_sequence_before = tonumber(event.deposit_sequence_before) or "",
        item_known = itemKnown == true and "true" or "false",
        provenance = provenance,
        pre_visible_hunger = tonumber(event.pre_visible_hunger) or "",
        target_visible_hunger = tonumber(event.target_visible_hunger) or "",
        kcal = tonumber(event.kcal) or "",
        carbs = tonumber(event.carbs) or "",
        fats = tonumber(event.fats) or "",
        proteins = tonumber(event.proteins) or "",
        consume_source = tostring(event.consume_source or ""),
        observed_hunger_drop = tonumber(event.observed_hunger_drop) or "",
        hunger_observed = event.hunger_observed == true and "true" or "",
        vanilla_visible_hunger = tonumber(event.vanilla_visible_hunger) or "",
        mechanical_hunger_drop = tonumber(event.mechanical_hunger_drop) or "",
        physical_hunger_drop = tonumber(event.physical_hunger_drop) or "",
        nutrient_hunger_drop = tonumber(event.nutrient_hunger_drop) or "",
        modeled_hunger_drop = tonumber(event.modeled_hunger_drop) or "",
        applied_hunger_drop = tonumber(event.applied_hunger_drop) or "",
        hunger_correction = tonumber(event.hunger_correction) or "",
        meal_transaction_kcal = tonumber(event.meal_transaction_kcal) or "",
        meal_transaction_fragments = tonumber(event.meal_transaction_fragments) or "",
        item_name = tostring(event.item_name or ""),
        item_id = tostring(event.item_id or ""),
        item_hunger_change = tonumber(event.item_hunger_change) or "",
        item_base_hunger = tonumber(event.item_base_hunger) or "",
        item_kcal = tonumber(event.item_kcal) or "",
        item_carbs = tonumber(event.item_carbs) or "",
        item_fats = tonumber(event.item_fats) or "",
        item_proteins = tonumber(event.item_proteins) or "",
        item_uses = tonumber(event.item_uses) or "",
        item_max_uses = tonumber(event.item_max_uses) or "",
        item_cooked = event.item_cooked == true and "true" or event.item_cooked == false and "false" or "",
        item_burnt = event.item_burnt == true and "true" or event.item_burnt == false and "false" or "",
        item_frozen = event.item_frozen == true and "true" or event.item_frozen == false and "false" or "",
        item_rotten = event.item_rotten == true and "true" or event.item_rotten == false and "false" or "",
        item_ingredients = tostring(event.item_ingredients or ""),
        item_spices = tostring(event.item_spices or ""),
        item_chef = tostring(event.item_chef or ""),
        snapshot_sequence = tonumber(event.snapshot_sequence) or "",
        snapshot_server_world_hours = tonumber(event.snapshot_server_world_hours) or "",
        snapshot_server_wall_seconds = tonumber(event.snapshot_server_wall_seconds) or "",
        state_transitions = tostring(event.state_transitions or ""),
        meta_key = tostring(event.meta_key or ""),
        meta_value = tostring(event.meta_value or ""),
        suppressed_kcal = tonumber(event.suppressed_kcal) or "",
        suppressed_carbs = tonumber(event.suppressed_carbs) or "",
        suppressed_fats = tonumber(event.suppressed_fats) or "",
        suppressed_proteins = tonumber(event.suppressed_proteins) or "",
    }
end

local function snapshotTotals(state)
    local observedHours = math.max(0, tonumber(state and state.totalObservedHours) or 0)
    local sleepHours = clamp(tonumber(state and state.totalSleepHours) or 0, 0, observedHours)
    return {
        intake = math.max(0, tonumber(state and state.totalIntakeKcal) or 0),
        burn = math.max(0, tonumber(state and state.totalBurnKcal) or 0),
        hunger = math.max(0, tonumber(state and state.totalVisibleHungerGain) or 0),
        observed = observedHours,
        sleep = sleepHours,
    }
end

local function resetRecordingAccounting(state, now)
    local totals = snapshotTotals(state)
    recordingBaselines = {
        intake = totals.intake,
        burn = totals.burn,
        hunger = totals.hunger,
        observed = totals.observed,
        sleep = totals.sleep,
    }
    recordingLastTotals = snapshotTotals(state)
    lastRecordingRowMinute = now
end

local function getRecordingAccounting(state, now)
    local totals = snapshotTotals(state)
    local baseline = recordingBaselines or totals
    local previous = recordingLastTotals or totals
    local intervalHours = math.max(0, (now - (lastRecordingRowMinute or now)) / 60)
    local result = {
        intervalHours = intervalHours,
        intervalIntake = math.max(0, totals.intake - previous.intake),
        intervalBurn = math.max(0, totals.burn - previous.burn),
        intervalHunger = math.max(0, totals.hunger - previous.hunger),
        runIntake = math.max(0, totals.intake - baseline.intake),
        runBurn = math.max(0, totals.burn - baseline.burn),
        runHunger = math.max(0, totals.hunger - baseline.hunger),
        runObserved = math.max(0, totals.observed - baseline.observed),
        runSleep = math.max(0, totals.sleep - baseline.sleep),
    }
    result.runAwake = math.max(0, result.runObserved - result.runSleep)
    result.runNet = result.runIntake - result.runBurn
    recordingLastTotals = totals
    lastRecordingRowMinute = now
    return totals, result
end

local function deriveStateTransitions(snap)
    local state = snap and snap.state or {}
    local current = {
        hungerBand = tostring(state.lastHungerBand or ""),
        zone = tostring(state.lastZone or ""),
        asleep = snap and snap.asleep == true,
        deprivationPenalty = (tonumber(state.deprivation) or 0) >= 0.10,
        hungryMoodle = tonumber(snap and snap.hungryMoodle),
        foodEatenMoodle = tonumber(snap and snap.foodEatenMoodle),
    }
    local previous = lastTransitionSnapshot
    lastTransitionSnapshot = current
    if not previous then return "" end

    local transitions = {}
    local function note(name, before, after)
        if before ~= after then
            transitions[#transitions + 1] = string.format("%s:%s>%s", name, tostring(before), tostring(after))
        end
    end
    note("hunger_band", previous.hungerBand, current.hungerBand)
    note("fuel_zone", previous.zone, current.zone)
    note("sleep", previous.asleep, current.asleep)
    note("deprivation_penalty", previous.deprivationPenalty, current.deprivationPenalty)
    note("hungry_moodle", previous.hungryMoodle, current.hungryMoodle)
    note("food_eaten_moodle", previous.foodEatenMoodle, current.foodEatenMoodle)
    return table.concat(transitions, "|")
end

local function hasStateTransition(snap)
    if not lastTransitionSnapshot then return false end
    local state = snap and snap.state or {}
    return tostring(state.lastHungerBand or "") ~= lastTransitionSnapshot.hungerBand
        or tostring(state.lastZone or "") ~= lastTransitionSnapshot.zone
        or (snap and snap.asleep == true) ~= lastTransitionSnapshot.asleep
        or ((tonumber(state.deprivation) or 0) >= 0.10) ~= lastTransitionSnapshot.deprivationPenalty
        or tonumber(snap and snap.hungryMoodle) ~= lastTransitionSnapshot.hungryMoodle
        or tonumber(snap and snap.foodEatenMoodle) ~= lastTransitionSnapshot.foodEatenMoodle
end

local function recordTimelineRow(kind, trigger, snap, event)
    if not recording or not snap then return end
    local now = getWorldAgeMinutes()
    local elapsed = now - (recordStartMinute or now)
    local s = snap.state or {}
    local w = snap.workload or {}
    local sm = snap.snapshotMeta or {}
    local ev = normalizeTimelineEvent(kind, trigger, event)
    local totals, account = getRecordingAccounting(s, now)
    local values = {
        row_kind = ev.kind or kind or "", row_trigger = ev.trigger or trigger or "",
        elapsed_min = string.format("%.1f", elapsed), game_min = string.format("%.1f", now),
        interval_game_hours = account.intervalHours, game_speed = string.format("%.2f", getGameSpeed()),
        runtime_role = snap.runtimeRole or "",
        auth_work_tier = s.lastWorkTier, auth_met_avg = s.lastMetAverage,
        auth_met_peak = s.lastMetPeak, auth_met_source = s.lastMetSource,
        live_work_tier = w.workTier, live_met_avg = w.averageMet,
        live_met_peak = w.peakMet, live_met_source = w.source,
        thermo_target_met = snap.thermoTarget, thermo_real_met = snap.thermoReal,
        movement_mode = snap.movementMode,
        is_asleep = snap.asleep, is_moving = snap.moving, is_running = snap.running,
        is_sprinting = snap.sprinting, is_sneaking = snap.sneaking,
        is_attacking = snap.attacking, has_timed_action = snap.timedAction,
        visible_hunger = snap.hunger, local_hunger = snap.hunger,
        auth_visible_hunger = snap.authoritativeHunger, last_synced_hunger = snap.lastSyncedHunger,
        hungry_moodle = snap.hungryMoodle, food_eaten_moodle = snap.foodEatenMoodle,
        health_from_food = snap.healthFromFood, health_from_food_timer = snap.fedTimer,
        visible_endurance = snap.endurance, visible_fatigue = snap.fatigue,
        nms_fuel = s.fuel, nms_zone = s.lastZone, nms_proteins = s.proteins,
        nms_weight_kg = s.weightKg, nms_weight_trait = s.lastWeightTrait,
        nms_weight_rate_kg_week = s.lastWeightRateKgPerWeek,
        nms_weight_controller = s.weightController, nms_weight_balance_kcal = s.weightBalanceKcal,
        nms_weight_controller_target = Metabolism.getWeightControllerTargetFromBalance(s.weightBalanceKcal),
        nms_deposit_sequence = s.depositSequence, nms_satiety_buffer = s.satietyBuffer,
        nms_satiety_quality = s.lastSatietyQuality, nms_satiety_return_factor = s.lastSatietyReturnFactor,
        nms_hunger_band = s.lastHungerBand,
        nms_meal_deposit_kcal = s.lastMealDepositKcal,
        nms_meal_transaction_fragments = s.lastMealTransactionFragments,
        nms_meal_hunger_drop = s.lastMealHungerDrop,
        nms_meal_modeled_drop = s.lastMealModeledDrop,
        nms_meal_mechanical_drop = s.lastMealMechanicalDrop,
        nms_meal_physical_drop = s.lastMealPhysicalDrop,
        nms_meal_nutrient_drop = s.lastMealNutrientDrop,
        nms_meal_hunger_correction = (tonumber(s.lastMealHungerDrop) or 0)
            - (tonumber(s.lastMealMechanicalDrop) or 0),
        nms_meal_pre_hunger = s.lastMealPreHunger,
        nms_meal_target_hunger = s.lastMealTargetHunger,
        nms_meal_hunger_observed = (tonumber(s.lastMealMechanicalDrop) or 0) > 0,
        nms_fuel_pressure = s.lastFuelPressureFactor,
        nms_hunger_rate_mult = s.lastHungerRateMultiplier,
        nms_stats_decrease_mult = s.lastStatsDecreaseMultiplier,
        nms_appetite_rate_mult = s.lastAppetiteRateMultiplier,
        nms_energy_burn_mult = s.lastEnergyBurnMultiplier,
        nms_gate_mult = s.lastGateMultiplier, nms_met_hunger_factor = s.lastMetHungerFactor,
        nms_energy_appetite_progress = s.lastEnergyAppetiteProgress,
        nms_energy_appetite_rate_hour = s.lastEnergyAppetiteRatePerHour,
        nms_satiety_contribution = s.lastSatietyContribution,
        nms_base_hunger_gain = s.lastPassiveHungerGain,
        nms_passive_hunger_gain = s.lastPassiveHungerGain,
        nms_observed_hours = s.lastObservedHours, nms_heavy_hours = s.lastHeavyHours,
        nms_very_heavy_hours = s.lastVeryHeavyHours,
        nms_burn_kcal = s.lastBurnKcal, nms_deposit_kcal = s.lastDepositKcal,
        nms_total_intake_kcal = totals.intake, nms_total_burn_kcal = totals.burn,
        nms_total_hunger_gain = totals.hunger, nms_total_observed_hours = totals.observed,
        nms_total_sleep_hours = totals.sleep,
        run_intake_kcal = account.runIntake, run_burn_kcal = account.runBurn,
        run_net_kcal = account.runNet, run_hunger_gain = account.runHunger,
        run_observed_hours = account.runObserved, run_awake_hours = account.runAwake,
        run_sleep_hours = account.runSleep,
        interval_intake_kcal = account.intervalIntake, interval_burn_kcal = account.intervalBurn,
        interval_hunger_gain = account.intervalHunger,
        nms_extra_endurance = s.lastExtraEnduranceDrain,
        nms_end_regen_scale = s.lastEnduranceRegenScale,
        nms_end_depriv_drain = s.lastEnduranceDeprivDrain,
        nms_protein_def = s.lastProteinDeficiency,
        nms_protein_heal_mult = s.lastProteinHealingMultiplier,
        nms_deprivation = s.deprivation or 0, nms_deprivation_target = s.lastDeprivationTarget,
        event_reason = ev.reason, event_item = ev.item, event_fraction = ev.fraction,
        event_correlation_id = ev.correlation_id,
        event_deposit_sequence_before = ev.deposit_sequence_before,
        event_item_known = ev.item_known, event_provenance = ev.provenance,
        event_pre_hunger = ev.pre_visible_hunger, event_target_hunger = ev.target_visible_hunger,
        event_kcal = ev.kcal, event_carbs = ev.carbs, event_fats = ev.fats,
        event_proteins = ev.proteins, event_consume_source = ev.consume_source,
        event_observed_hunger_drop = ev.observed_hunger_drop,
        event_hunger_observed = ev.hunger_observed,
        event_vanilla_hunger = ev.vanilla_visible_hunger,
        event_mechanical_hunger_drop = ev.mechanical_hunger_drop,
        event_physical_hunger_drop = ev.physical_hunger_drop,
        event_nutrient_hunger_drop = ev.nutrient_hunger_drop,
        event_modeled_hunger_drop = ev.modeled_hunger_drop,
        event_applied_hunger_drop = ev.applied_hunger_drop,
        event_hunger_correction = ev.hunger_correction,
        event_meal_transaction_kcal = ev.meal_transaction_kcal,
        event_meal_transaction_fragments = ev.meal_transaction_fragments,
        event_item_name = ev.item_name, event_item_id = ev.item_id,
        event_item_hunger_change = ev.item_hunger_change, event_item_base_hunger = ev.item_base_hunger,
        event_item_kcal = ev.item_kcal, event_item_carbs = ev.item_carbs,
        event_item_fats = ev.item_fats, event_item_proteins = ev.item_proteins,
        event_item_uses = ev.item_uses, event_item_max_uses = ev.item_max_uses,
        event_item_cooked = ev.item_cooked, event_item_burnt = ev.item_burnt,
        event_item_frozen = ev.item_frozen, event_item_rotten = ev.item_rotten,
        event_item_ingredients = ev.item_ingredients, event_item_spices = ev.item_spices,
        event_item_chef = ev.item_chef,
        mp_snapshot_seq = ev.snapshot_sequence ~= "" and ev.snapshot_sequence or sm.lastSeq,
        mp_snapshot_age_seconds = sm.ageSeconds, mp_snapshot_stale = sm.isStale,
        mp_snapshot_reason = ev.reason ~= "" and kind == "mp_snapshot" and ev.reason or sm.lastReason,
        mp_server_world_hours = ev.snapshot_server_world_hours ~= "" and ev.snapshot_server_world_hours or sm.serverWorldHours,
        mp_server_wall_seconds = ev.snapshot_server_wall_seconds ~= "" and ev.snapshot_server_wall_seconds or sm.serverWallSeconds,
        mp_workload_seq = sm.workloadSeq, mp_workload_age_seconds = sm.workloadAgeSeconds,
        mp_workload_average_met = sm.workloadAverageMet, mp_workload_peak_met = sm.workloadPeakMet,
        mp_workload_source = sm.workloadSource, mp_workload_reason = sm.workloadReason,
        mp_authoritative_hunger = sm.authoritativeHunger,
        mp_display_hunger_target = sm.displayHungerTarget,
        mp_server_deposit_sequence = sm.serverDepositSequence,
        mp_prediction_active = sm.mealPredictionActive,
        mp_prediction_target_hunger = sm.mealPredictionTargetHunger,
        mp_prediction_age_seconds = sm.mealPredictionAgeSeconds,
        mp_prediction_baseline_snapshot_seq = sm.mealPredictionBaselineSnapshotSeq,
        mp_prediction_baseline_deposit_sequence = sm.mealPredictionBaselineDepositSequence,
        mp_prediction_last_server_deposit_sequence = sm.mealPredictionLastServerDepositSequence,
        mp_prediction_resolution = sm.mealPredictionResolution,
        state_transitions = ev.state_transitions, meta_key = ev.meta_key, meta_value = ev.meta_value,
    }
    appendRecordingValues(values)
end

local function recordSample(snap, trigger)
    if not snap then return end
    recordTimelineRow("sample", trigger or "tick", snap, {
        state_transitions = deriveStateTransitions(snap),
    })
end

local function captureAndRecordEvent(kind, trigger, event)
    if not recording then
        return
    end

    local snap = computeSnapshot()
    event = event or {}
    event.state_transitions = deriveStateTransitions(snap)
    recordTimelineRow(kind, trigger, snap, event)
end

local function summarizeCollection(collection, formatter)
    local values = {}
    local function append(value)
        local formatted = formatter and formatter(value) or value
        if formatted ~= nil then
            values[#values + 1] = tostring(formatted)
        end
    end
    if type(collection) == "table" then
        for _, value in pairs(collection) do
            append(value)
        end
    else
        local size = tonumber(safeCall(collection, "size")) or 0
        for index = 0, size - 1 do
            append(safeCall(collection, "get", index))
        end
    end
    return table.concat(values, "|")
end

local function getGameVersion()
    local core = type(getCore) == "function" and getCore() or nil
    return tostring(
        (core and safeCall(core, "getVersionNumber"))
        or (core and safeCall(core, "getVersion"))
        or "unknown"
    )
end

local function recordMetadata(snap)
    local player = getLocalPlayer()
    local sandbox = type(SandboxVars) == "table" and SandboxVars or {}
    local activeMods = type(getActivatedMods) == "function" and getActivatedMods() or nil
    local characterTraits = player and safeCall(player, "getCharacterTraits") or nil
    local traits = characterTraits and safeCall(characterTraits, "getKnownTraits") or nil
    local entries = {
        { "recording_schema_version", RECORDING_SCHEMA_VERSION },
        { "nms_version", tostring(MP.SCRIPT_VERSION or "unknown") },
        { "nms_state_version", tostring(Metabolism.STATE_VERSION or "unknown") },
        { "pz_version", getGameVersion() },
        { "runtime_role", snap and snap.runtimeRole or getRuntimeRole() },
        { "player", snap and snap.player or "unknown" },
        { "recording_label", tostring(recordLabel or "dev") },
        { "start_world_minutes", tostring(recordStartMinute or "") },
        { "active_mods_load_order", summarizeCollection(activeMods) },
        { "traits", summarizeCollection(traits, function(trait)
            return safeCall(trait, "getName") or trait
        end) },
        { "sandbox_stats_decrease", tostring(sandbox.StatsDecrease or "") },
        { "stats_decrease_multiplier", tostring(
            type(Runtime.resolveStatsDecreaseMultiplier) == "function"
                and Runtime.resolveStatsDecreaseMultiplier() or ""
        ) },
        { "sandbox_day_length", tostring(sandbox.DayLength or "") },
        { "sandbox_nutrition", tostring(sandbox.Nutrition or "") },
        { "nms_use_curated_food_values", tostring(
            type(Settings.useCuratedFoodValues) == "function" and Settings.useCuratedFoodValues() or ""
        ) },
        { "nms_energy_burn_multiplier", tostring(
            type(Settings.getEnergyBurnMultiplier) == "function" and Settings.getEnergyBurnMultiplier() or ""
        ) },
        { "nms_appetite_rate_multiplier", tostring(
            type(Settings.getAppetiteRateMultiplier) == "function" and Settings.getAppetiteRateMultiplier() or ""
        ) },
    }
    for _, entry in ipairs(entries) do
        appendRecordingValues({
            row_kind = "meta",
            row_trigger = "start",
            elapsed_min = "0.0",
            game_min = string.format("%.1f", recordStartMinute or 0),
            runtime_role = snap and snap.runtimeRole or getRuntimeRole(),
            meta_key = entry[1],
            meta_value = entry[2],
        })
    end
end

local function writeRecordingToFile()
    if #recordBuffer == 0 then
        print("[NutritionMakesSense] recording empty, nothing to write")
        return nil
    end
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename = "nms_recording_" .. (recordLabel or "dev") .. "_" .. timestamp .. ".txt"
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
    if recording then
        local path = DevPanel.stopRecording()
        if not path then
            return false
        end
    end
    recordBuffer = {}
    recordStartMinute = getWorldAgeMinutes()
    lastSampleGameMinute = recordStartMinute
    recordLabel = label or "dev"
    lastTransitionSnapshot = nil
    pendingFoodActions = {}
    nextFoodActionId = 0
    recording = true
    local snap = computeSnapshot()
    resetRecordingAccounting(snap and snap.state or {}, recordStartMinute)
    recordMetadata(snap)
    recordSample(snap, "start")
    print(string.format("[NutritionMakesSense] recording started (label=%s)", recordLabel))
    return true
end

function DevPanel.stopRecording()
    if not recording then return nil end
    local snap = computeSnapshot()
    recordSample(snap, "stop")
    recordTimelineRow("summary", "stop-summary", snap, { reason = "recording-stop" })
    recording = false
    local path = writeRecordingToFile()
    local count = #recordBuffer
    if not path then
        recording = true
        print(string.format(
            "[NutritionMakesSense] recording save failed; keeping %d buffered samples and recording active",
            count
        ))
        return nil, count
    end
    recordBuffer = {}
    recordStartMinute = nil
    lastSampleGameMinute = nil
    lastRecordingRowMinute = nil
    recordingBaselines = nil
    recordingLastTotals = nil
    lastTransitionSnapshot = nil
    pendingFoodActions = {}
    nextFoodActionId = 0
    recordLabel = nil
    return path, count
end

local FOOD_ACTION_EVENT_FIELDS = {
    "item", "item_name", "item_id", "fraction", "item_known",
    "item_hunger_change", "item_base_hunger",
    "item_kcal", "item_carbs", "item_fats", "item_proteins",
    "item_uses", "item_max_uses", "item_cooked", "item_burnt",
    "item_frozen", "item_rotten", "item_ingredients", "item_spices", "item_chef",
}

local function correlateFoodAction(event, snap, requireDepositAdvance)
    local now = getWorldAgeMinutes()
    while #pendingFoodActions > 0 and (now - pendingFoodActions[1].createdMinute) > 15 do
        table.remove(pendingFoodActions, 1)
    end
    local pending = pendingFoodActions[1]
    if not pending then return event end

    local currentSequence = tonumber(snap and snap.state and snap.state.depositSequence) or 0
    if requireDepositAdvance and currentSequence <= pending.depositSequenceBefore then
        return event
    end

    local merged = event or {}
    for _, field in ipairs(FOOD_ACTION_EVENT_FIELDS) do
        local current = merged[field]
        if current == nil or current == "" then
            merged[field] = pending.event[field]
        end
    end
    merged.correlation_id = pending.id
    merged.deposit_sequence_before = pending.depositSequenceBefore
    merged.item_known = pending.event.item_known == true
    if tostring(merged.provenance or "") == "observed-nutrition-delta" then
        merged.provenance = "observed-delta+client-item-instance"
    end
    table.remove(pendingFoodActions, 1)
    return merged
end

function DevPanel.noteConsumeEvent(_self, event)
    if not recording then return end
    local snap = computeSnapshot()
    event = correlateFoodAction(event, snap, false) or {}
    event.state_transitions = deriveStateTransitions(snap)
    recordTimelineRow("consume", "consume-event", snap, event)
end

function DevPanel.noteFoodActionEvent(_self, event)
    if not recording then return end
    local snap = computeSnapshot()
    nextFoodActionId = nextFoodActionId + 1
    event = event or {}
    event.correlation_id = string.format("meal-%d", nextFoodActionId)
    event.deposit_sequence_before = tonumber(snap and snap.state and snap.state.depositSequence) or 0
    pendingFoodActions[#pendingFoodActions + 1] = {
        id = event.correlation_id,
        event = event,
        createdMinute = getWorldAgeMinutes(),
        depositSequenceBefore = event.deposit_sequence_before,
    }
    event.state_transitions = deriveStateTransitions(snap)
    recordTimelineRow("food_action", tostring(event.reason or "food-action-complete"), snap, event)
end

function DevPanel.noteSnapshotEvent(_self, event)
    if not recording then return end
    local snap = computeSnapshot()
    event = correlateFoodAction(event, snap, true) or {}
    event.state_transitions = deriveStateTransitions(snap)
    recordTimelineRow("mp_snapshot", "server-snapshot", snap, event)
end

function DevPanel.noteHungerSyncEvent(_self, event)
    captureAndRecordEvent("hunger_sync", "visible-hunger-sync", event)
end

if NutritionMakesSense.DevPanelSink and type(NutritionMakesSense.DevPanelSink.attach) == "function" then
    NutritionMakesSense.DevPanelSink.attach(DevPanel)
end

function DevPanel.sampleTick(force)
    if not recording then return end
    local now = getWorldAgeMinutes()
    local snap = computeSnapshot()
    local stateChanged = hasStateTransition(snap)
    if not force and not stateChanged
        and (now - (lastSampleGameMinute or now)) < SAMPLE_INTERVAL_MINUTES then return end
    recordSample(snap, force and "forced-sample" or stateChanged and "state-change" or "tick")
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
    self.recordBtn = ISButton:new(bx, 4, 68, 22, "Record", self, NMS_DevOverlay.onToggleRecord)
    self.recordBtn:initialise()
    self:addChild(self.recordBtn)
    bx = bx + 72

    self.testsBtn = ISButton:new(bx, 4, 52, 22, "Tests", self, NMS_DevOverlay.onOpenTests)
    self.testsBtn:initialise()
    self.testsBtn.tooltip = "Open live scenario tests"
    self:addChild(self.testsBtn)
    bx = bx + 56

    self.compatBtn = ISButton:new(bx, 4, 66, 22, "Compat", self, NMS_DevOverlay.onToggleCompatTrace)
    self.compatBtn:initialise()
    self:addChild(self.compatBtn)
    bx = bx + 70

    self.resetBtn = ISButton:new(bx, 4, 50, 22, "Reset", self, NMS_DevOverlay.onReset)
    self.resetBtn:initialise()
    self:addChild(self.resetBtn)
    bx = bx + 54

    self.hunger50Btn = ISButton:new(bx, 4, 78, 22, "Hunger .50", self, NMS_DevOverlay.onSetHunger50)
    self.hunger50Btn:initialise()
    self:addChild(self.hunger50Btn)

    self.closeBtn = ISButton:new(PANEL_W - 28, 4, 22, 22, "X", self, NMS_DevOverlay.onClose)
    self.closeBtn:initialise()
    self:addChild(self.closeBtn)
    self:updateRecordButton()
    self:updateCompatTraceButton()
end

function NMS_DevOverlay:onOpenTests()
    local testPanel = NutritionMakesSense.TestPanel
    if type(testPanel) ~= "table" then
        local ok = pcall(require, "dev/NutritionMakesSense_TestPanel")
        testPanel = ok and NutritionMakesSense.TestPanel or nil
    end
    if testPanel and type(testPanel.toggle) == "function" then
        testPanel.toggle()
    end
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

function NMS_DevOverlay:updateCompatTraceButton()
    if not self.compatBtn then return end
    local status = CompatTrace.getStatus and CompatTrace.getStatus() or { active = false }
    if status.active then
        local label = status.mode == "mp" and "Compat MP" or "Compat SP"
        self.compatBtn:setTitle(label)
        self.compatBtn.backgroundColor = { r = 0.10, g = 0.36, b = 0.18, a = 0.92 }
        self.compatBtn.textColor = { r = 1, g = 1, b = 1, a = 1 }
    else
        self.compatBtn:setTitle("Compat")
        self.compatBtn.backgroundColor = { r = 0.14, g = 0.14, b = 0.18, a = 0.92 }
        self.compatBtn.textColor = { r = 0.8, g = 0.8, b = 0.8, a = 1 }
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

function NMS_DevOverlay:onToggleCompatTrace()
    local status = CompatTrace.getStatus and CompatTrace.getStatus() or { active = false }
    if status.active then
        local path, count, err = CompatTrace.stop and CompatTrace.stop()
        if path then
            print(string.format("[NutritionMakesSense] compat trace saved: %s (%d samples)", path, count or 0))
        elseif err and err ~= "mp" then
            print("[NutritionMakesSense] compat trace stop error: " .. tostring(err))
        end
    else
        local ok, modeOrErr = CompatTrace.start and CompatTrace.start("dev")
        if not ok then
            print("[NutritionMakesSense] compat trace start error: " .. tostring(modeOrErr))
        end
    end
    self:updateCompatTraceButton()
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
    if recording then
        local path = DevPanel.stopRecording()
        if not path then
            self:updateRecordButton()
            return
        end
    end
    if CompatTrace.isRecording and CompatTrace.isRecording() then CompatTrace.stop() end
    DevPanel.hide()
end

function NMS_DevOverlay:render()
    ISPanel.render(self)
    local snap = computeSnapshot()
    local y = 32

    self:drawText("NMS Runtime Inspector", PAD, y, C.title.r, C.title.g, C.title.b, C.title.a, FONT)
    y = y + LINE_H + 6

    if recording then
        local elapsed = getWorldAgeMinutes() - (recordStartMinute or 0)
        self:drawText(
            string.format("REC  %d samples  %.0fm", #recordBuffer, elapsed),
            PAD + 88, y, C.rec.r, C.rec.g, C.rec.b, C.rec.a, FONT_S)
        y = y + LINE_H
    end

    local compatStatus = CompatTrace.getStatus and CompatTrace.getStatus() or nil
    if compatStatus and compatStatus.active then
        local traceText = compatStatus.mode == "mp"
            and string.format("TRACE MP  %s", compatStatus.pending and "pending" or "active")
            or string.format("TRACE SP  %d samples", tonumber(compatStatus.sampleCount) or 0)
        self:drawText(traceText, PAD + 88, y, C.good.r, C.good.g, C.good.b, C.good.a, FONT_S)
        y = y + LINE_H
    end

    if not snap then
        self:drawText("Waiting for player...", PAD, y, C.dim.r, C.dim.g, C.dim.b, C.dim.a, FONT_S)
        return
    end

    local s = snap.state or {}
    local snapshotMeta = snap.snapshotMeta or {}

    ---------------------------------------------------------------- Last Intake
    y = drawSection(self, y, "Last Intake")
    local mealDrop = tonumber(s.lastMealHungerDrop) or 0
    local modeledDrop = tonumber(s.lastMealModeledDrop) or mealDrop
    local mechanicalDrop = tonumber(s.lastMealMechanicalDrop) or 0
    local physicalDrop = tonumber(s.lastMealPhysicalDrop) or 0
    local nutrientDrop = tonumber(s.lastMealNutrientDrop) or 0
    local fullnessCorrection = mealDrop - mechanicalDrop
    local hungerObserved = mechanicalDrop > 0
    local deposit = tonumber(s.lastMealDepositKcal) or tonumber(s.lastDepositKcal) or 0
    local transactionFragments = tonumber(s.lastMealTransactionFragments) or 0
    local satietyQuality = tonumber(s.lastSatietyQuality) or 0
    local satietyAdded = tonumber(s.lastSatietyContribution) or 0
    local intakeStatus = deposit <= 0 and "Waiting"
        or hungerObserved and "Resolved"
        or "Nutrition fallback"
    local intakeColor = deposit <= 0 and C.dim
        or hungerObserved and C.good
        or C.warn
    y = drawRow(self, y, "Status", intakeStatus, intakeColor)
    y = drawRow(self, y, "Fullness", string.format("-%s applied  (-%s modeled)", fmt(mealDrop, 3), fmt(modeledDrop, 3)),
        deposit > 0 and C.value or C.dim)
    y = drawRow(self, y, "Sources",
        string.format("raw:%s  volume:%s  nutrients:%s", fmt(mechanicalDrop, 3), fmt(physicalDrop, 3), fmt(nutrientDrop, 3)))
    y = drawRow(self, y, "Correction", string.format("%+.3f vs vanilla", fullnessCorrection),
        math.abs(fullnessCorrection) < 0.001 and C.dim or C.value)
    local energyText = deposit > 0 and ("+" .. fmt(deposit, 0) .. " kcal") or "--"
    if deposit > 0 and transactionFragments > 0 then
        energyText = string.format("%s  (%d part%s)", energyText, transactionFragments,
            transactionFragments == 1 and "" or "s")
    end
    y = drawRow(self, y, "Energy", energyText)
    y = drawRow(self, y, "Staying Power",
        string.format("quality:%s  added:%s", fmt(satietyQuality, 2), fmt(satietyAdded, 2)))

    ---------------------------------------------------------------- Sync
    y = drawSection(self, y, "Sync")
    local seqText = snapshotMeta.lastSeq and tostring(snapshotMeta.lastSeq) or "--"
    local ageSeconds = tonumber(snapshotMeta.ageSeconds)
    local ageText = ageSeconds and string.format("%.1fs", ageSeconds) or "--"
    local stale = snapshotMeta.isStale == true
    local reasonText = tostring(snapshotMeta.lastReason or "--")
    y = drawRow(self, y, "Status", stale and "STALE" or "Live", stale and C.warn or C.good)
    y = drawRow(self, y, "Seq", seqText)
    y = drawRow(self, y, "Age", ageText, stale and C.warn or C.dim)
    y = drawRow(self, y, "Reason", reasonText, C.dim)

    ---------------------------------------------------------------- Hunger
    y = drawSection(self, y, "Hunger & Return")
    local band = s.lastHungerBand or "comfortable"
    local bandColor = BAND_COLORS[band] or C.value
    local bandLabel = BAND_LABELS[band] or band
    local hungerVal = snap.hunger or 0
    y = drawLabeledBar(self, y, hungerVal, bandColor, bandLabel, fmt(hungerVal, 3))

    local satBuf = tonumber(s.satietyBuffer) or 0
    local satMax = Metabolism.SATIETY_BUFFER_MAX or 1.5
    y = drawLabeledBar(self, y, satBuf / satMax, C.satiety,
        "Meal Staying Power", fmt(satBuf, 2) .. " / " .. fmt(satMax, 1))

    local passiveGain = tonumber(s.lastPassiveHungerGain) or 0
    local retFactor = tonumber(s.lastSatietyReturnFactor) or 1
    local fuelPressure = tonumber(s.lastFuelPressureFactor) or 1
    local hungerRateMultiplier = tonumber(s.lastHungerRateMultiplier) or 1
    local statsDecreaseMultiplier = tonumber(s.lastStatsDecreaseMultiplier) or 1
    local appetiteRateMultiplier = tonumber(s.lastAppetiteRateMultiplier) or 1
    local gateMult = tonumber(s.lastGateMultiplier) or 1
    local metFactor = tonumber(s.lastMetHungerFactor) or 1
    local energyAppetiteProgress = tonumber(s.lastEnergyAppetiteProgress) or 0
    local energyAppetiteRate = tonumber(s.lastEnergyAppetiteRatePerHour) or 0
    y = drawRow(self, y, "Rate", fmts(passiveGain, 4) .. " / tick")
    y = drawRow(self, y, "Multipliers",
        string.format("gate x%s   met x%s   sat x%s   energy x%s",
            fmt(gateMult, 2), fmt(metFactor, 2), fmt(retFactor, 2), fmt(fuelPressure, 2)))
    y = drawRow(self, y, "Appetite tuning",
        string.format("vanilla x%s   NMS x%s   effective x%s",
            fmt(statsDecreaseMultiplier, 2), fmt(appetiteRateMultiplier, 2), fmt(hungerRateMultiplier, 2)), C.dim)
    y = drawRow(self, y, "Balance appetite",
        string.format("pressure:%s  rate:%s/h", fmt(energyAppetiteProgress, 2), fmts(energyAppetiteRate, 4)), C.dim)

    ---------------------------------------------------------------- Available Energy
    y = drawSection(self, y, "Energy Reserve")
    local fuel = tonumber(s.fuel) or 0
    local fuelMax = Metabolism.FUEL_MAX or 2000
    local zone = s.lastZone or "Ready"
    local zoneColor = ZONE_COLORS[zone] or C.fuel
    y = drawLabeledBar(self, y, fuel / fuelMax, zoneColor,
        zone, fmt(fuel, 0) .. " / " .. fmt(fuelMax, 0))

    local burn = tonumber(s.lastBurnKcal) or 0
    local energyBurnMultiplier = tonumber(s.lastEnergyBurnMultiplier) or 1
    y = drawRow(self, y, "Flow",
        string.format("burn:%s kcal  dep:%s kcal  tuning:x%s",
            fmt(burn, 0), fmt(deposit, 0), fmt(energyBurnMultiplier, 2)))
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
    local extraEnd = tonumber(s.lastExtraEnduranceDrain) or 0
    local regenScale = tonumber(s.lastEnduranceRegenScale) or 1
    y = drawRow(self, y, "Endurance", string.format("%s   regen:x%s   drain:%s",
        pct(endurance), fmt(regenScale, 2), fmts(extraEnd, 4)))
    local deprivation = tonumber(s.deprivation) or 0
    local balance = tonumber(s.weightBalanceKcal) or 0
    local depTarget = tonumber(s.lastDeprivationTarget) or 0
    if deprivation > 0.01 or depTarget > 0.001 or regenScale < 0.995 then
        y = drawSection(self, y, "Deprivation")
        local depColor = deprivation > 0.5 and C.bad or deprivation > 0.1 and C.warn or C.dim
        y = drawLabeledBar(self, y, deprivation, depColor,
            "Deprivation", fmt(deprivation, 3) .. " / 1.0")
        if depTarget > 0.001 then
            y = drawRow(self, y, "Sustained Balance",
                string.format("%s kcal  target:%s", fmt(balance, 0), fmt(depTarget, 3)),
                C.dim)
        end
        if regenScale < 0.995 then
            y = drawRow(self, y, "Stamina Recovery", "x" .. fmt(regenScale, 2), C.warn)
        end
    end

    local neededH = y + PAD
    if math.abs(neededH - self.height) > 2 then self:setHeight(neededH) end
end

function NMS_DevOverlay:update()
    ISPanel.update(self)
    self:updateRecordButton()
    self:updateCompatTraceButton()
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

function NMS_DevPanel()
    local ok, err = pcall(DevPanel.toggle)
    if not ok then print("[NutritionMakesSense][ERROR] NMS_DevPanel: " .. tostring(err)) end
end

local function onTickSampler()
    if recording then
        DevPanel.sampleTick(false)
    end
    if CompatTrace.sampleTick then
        CompatTrace.sampleTick(false)
    end
end

if Events and Events.OnTick and type(Events.OnTick.Add) == "function" then
    Events.OnTick.Add(onTickSampler)
end

return DevPanel
