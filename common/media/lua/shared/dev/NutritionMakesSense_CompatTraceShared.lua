NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.CompatTraceShared = NutritionMakesSense.CompatTraceShared or {}

require "NutritionMakesSense_Compat"

local Shared = NutritionMakesSense.CompatTraceShared

local TRACE_COLUMNS = {
    "elapsed_min", "game_min", "trace_label", "trace_mode", "trace_authority", "sample_index", "sample_reason",
    "player", "online_id",
    "visible_hunger", "visible_endurance", "visible_fatigue",
    "compat_endurance_active", "compat_fatigue_active",
    "nms_work_tier", "nms_met_avg", "nms_met_peak", "nms_met_source",
    "nms_fuel", "nms_zone", "nms_deprivation", "nms_deprivation_target",
    "nms_end_regen_scale", "nms_end_depriv_drain", "nms_extra_endurance",
    "ams_activity", "ams_load_norm", "ams_effective_load", "ams_physical_load", "ams_thermal_load",
    "ams_breathing_load", "ams_thermal_contribution", "ams_breathing_contribution", "ams_endurance_env_factor",
    "ams_end_before", "ams_end_after", "ams_end_natural_delta", "ams_end_applied_delta",
    "ams_ams_regen_scale", "ams_nms_regen_scale", "ams_composed_regen_scale",
    "ams_ams_drain", "ams_nms_drain", "ams_sleep_penalty_fraction",
    "cms_real_fatigue", "cms_hidden_fatigue", "cms_last_set_fatigue",
    "cms_last_nms_extra_fatigue", "cms_last_ams_sleep_fatigue", "cms_last_sleep_recovery_fatigue",
    "cms_peak_stim", "cms_sleep_disruption_score", "cms_sleep_recovery_penalty_fraction", "cms_caffeine_stress",
}

local function safeCall(target, methodName, ...)
    if not target then
        return nil
    end
    local fn = target[methodName]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, target, ...)
    if not ok then
        return nil
    end
    return result
end

local function csvEscape(value)
    local text = tostring(value == nil and "" or value)
    if string.find(text, "[\",\n\r]", 1) then
        text = "\"" .. text:gsub("\"", "\"\"") .. "\""
    end
    return text
end

local function getCompat()
    return NutritionMakesSense.Compat or rawget(_G, "MakesSenseCompat")
end

local function getWorldAgeMinutes()
    if type(getGameTime) ~= "function" then
        return 0
    end
    local gameTime = getGameTime()
    local worldAgeHours = tonumber(gameTime and safeCall(gameTime, "getWorldAgeHours") or nil)
    if worldAgeHours == nil then
        return 0
    end
    return worldAgeHours * 60.0
end

local function getPlayerName(playerObj)
    local descriptor = safeCall(playerObj, "getDescriptor")
    local forename = descriptor and safeCall(descriptor, "getForename") or nil
    local surname = descriptor and safeCall(descriptor, "getSurname") or nil
    local fullName = nil
    if forename or surname then
        fullName = string.format("%s %s", tostring(forename or ""), tostring(surname or "")):gsub("^%s+", ""):gsub("%s+$", "")
    end
    if fullName and fullName ~= "" then
        return fullName
    end
    return tostring(safeCall(playerObj, "getUsername") or safeCall(playerObj, "getDisplayName") or "unknown")
end

local function getOnlineId(playerObj)
    return tonumber(safeCall(playerObj, "getOnlineID") or safeCall(playerObj, "getPlayerNum"))
end

local function getVisibleStats(playerObj)
    local stats = playerObj and safeCall(playerObj, "getStats") or nil
    local function readStat(enumKey, directMethod)
        if not stats then
            return nil
        end
        local directValue = tonumber(safeCall(stats, directMethod))
        if directValue ~= nil then
            return directValue
        end
        if CharacterStat and CharacterStat[enumKey] then
            return tonumber(safeCall(stats, "get", CharacterStat[enumKey]))
        end
        return nil
    end
    return {
        hunger = readStat("HUNGER", "getHunger"),
        endurance = readStat("ENDURANCE", "getEndurance"),
        fatigue = readStat("FATIGUE", "getFatigue"),
    }
end

local function getProviderTrace(modKey, playerObj, args)
    local compat = getCompat()
    if type(compat) ~= "table" or type(compat.getCallback) ~= "function" then
        return {}
    end

    local callback = compat:getCallback(modKey, "buildTraceSnapshot")
    if type(callback) ~= "function" then
        return {}
    end

    local ok, snapshot = pcall(callback, playerObj, args or {})
    if not ok or type(snapshot) ~= "table" then
        return {}
    end
    return snapshot
end

function Shared.getHeaderLine()
    return table.concat(TRACE_COLUMNS, ",")
end

function Shared.collectSample(playerObj, traceState, extra)
    local state = type(traceState) == "table" and traceState or {}
    local args = type(extra) == "table" and extra or {}
    local nowMinutes = getWorldAgeMinutes()
    local visible = getVisibleStats(playerObj)
    local startMinute = tonumber(state.startMinute) or nowMinutes
    local sampleIndex = (tonumber(state.sampleIndex) or 0) + 1
    state.sampleIndex = sampleIndex
    state.startMinute = startMinute

    local nms = getProviderTrace("NutritionMakesSense", playerObj, args)
    local ams = getProviderTrace("ArmorMakesSense", playerObj, args)
    local cms = getProviderTrace("CaffeineMakesSense", playerObj, args)

    return {
        elapsed_min = string.format("%.1f", nowMinutes - startMinute),
        game_min = string.format("%.1f", nowMinutes),
        trace_label = tostring(state.label or args.label or "dev"),
        trace_mode = tostring(state.mode or args.mode or "sp"),
        trace_authority = tostring(state.authority or args.authority or "client"),
        sample_index = sampleIndex,
        sample_reason = tostring(args.reason or "tick"),
        player = getPlayerName(playerObj),
        online_id = getOnlineId(playerObj) or "",
        visible_hunger = visible.hunger,
        visible_endurance = visible.endurance,
        visible_fatigue = visible.fatigue,
        compat_endurance_active = nms.compat_endurance_active,
        compat_fatigue_active = nms.compat_fatigue_active,
        nms_work_tier = nms.work_tier,
        nms_met_avg = nms.met_avg,
        nms_met_peak = nms.met_peak,
        nms_met_source = nms.met_source,
        nms_fuel = nms.fuel,
        nms_zone = nms.zone,
        nms_deprivation = nms.deprivation,
        nms_deprivation_target = nms.deprivation_target,
        nms_end_regen_scale = nms.end_regen_scale,
        nms_end_depriv_drain = nms.end_depriv_drain,
        nms_extra_endurance = nms.extra_endurance,
        ams_activity = ams.activity_label,
        ams_load_norm = ams.load_norm,
        ams_effective_load = ams.effective_load,
        ams_physical_load = ams.physical_load,
        ams_thermal_load = ams.thermal_load,
        ams_breathing_load = ams.breathing_load,
        ams_thermal_contribution = ams.thermal_contribution,
        ams_breathing_contribution = ams.breathing_contribution,
        ams_endurance_env_factor = ams.endurance_env_factor,
        ams_end_before = ams.endurance_before,
        ams_end_after = ams.endurance_after,
        ams_end_natural_delta = ams.endurance_natural_delta,
        ams_end_applied_delta = ams.endurance_applied_delta,
        ams_ams_regen_scale = ams.ams_regen_scale,
        ams_nms_regen_scale = ams.nms_regen_scale,
        ams_composed_regen_scale = ams.composed_regen_scale,
        ams_ams_drain = ams.ams_drain_applied,
        ams_nms_drain = ams.nms_drain_applied,
        ams_sleep_penalty_fraction = ams.sleep_penalty_fraction,
        cms_real_fatigue = cms.real_fatigue,
        cms_hidden_fatigue = cms.hidden_fatigue,
        cms_last_set_fatigue = cms.last_set_fatigue,
        cms_last_nms_extra_fatigue = cms.last_nms_extra_fatigue,
        cms_last_ams_sleep_fatigue = cms.last_ams_sleep_fatigue,
        cms_last_sleep_recovery_fatigue = cms.last_sleep_recovery_fatigue,
        cms_peak_stim = cms.peak_stim,
        cms_sleep_disruption_score = cms.sleep_disruption_score,
        cms_sleep_recovery_penalty_fraction = cms.sleep_recovery_penalty_fraction,
        cms_caffeine_stress = cms.caffeine_stress,
    }
end

function Shared.encodeSample(sample)
    local row = {}
    for _, column in ipairs(TRACE_COLUMNS) do
        row[#row + 1] = csvEscape(sample[column])
    end
    return table.concat(row, ",")
end

function Shared.writeSamples(rows, prefix, label)
    if type(rows) ~= "table" or #rows == 0 then
        return nil, "empty"
    end

    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filePrefix = tostring(prefix or "mscompat_trace")
    local fileLabel = tostring(label or "dev")
    local fileName = string.format("%s_%s_%s.csv", filePrefix, fileLabel, timestamp)
    local relPath = "makes_sense_compat/" .. fileName

    if type(getFileWriter) ~= "function" then
        return nil, "writer_unavailable"
    end

    local okWriter, writer = pcall(getFileWriter, relPath, true, false)
    if not okWriter or not writer then
        return nil, "writer_open_failed"
    end

    writer:writeln(Shared.getHeaderLine())
    for i = 1, #rows do
        writer:writeln(rows[i])
    end
    writer:close()
    return relPath, nil
end

return Shared
