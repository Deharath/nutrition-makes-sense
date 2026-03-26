NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_MetabolismRuntime"
require "NutritionMakesSense_ItemAuthority"
require "NutritionMakesSense_CoreUtils"

local MPClient = NutritionMakesSense.MPClientRuntime or {}
NutritionMakesSense.MPClientRuntime = MPClient

local MP = NutritionMakesSense.MP or {}
local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local Metabolism = Runtime.Metabolism or {}
local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
local CoreUtils = NutritionMakesSense.CoreUtils or {}

local CONSUME_EPSILON = 0.0001
local SNAPSHOT_STALE_SECONDS = 5
local PROJECTION_SMOOTH_ALPHA = 0.35
local safeCall = CoreUtils.safeCall

local function log(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(msg)
    else
        print("[NutritionMakesSense] " .. tostring(msg))
    end
end

local function isClientRuntime()
    return type(isClient) == "function" and isClient() == true and not (type(isServer) == "function" and isServer() == true)
end

local function isLocalAuthorityRuntime()
    return not isClientRuntime()
end

local function getWorldAgeMinutes()
    local worldHours = CoreUtils.getWorldHours and CoreUtils.getWorldHours() or nil
    return math.floor((tonumber(worldHours) or 0) * 60)
end

local function getWorldHours()
    return tonumber(CoreUtils.getWorldHours and CoreUtils.getWorldHours() or nil)
end

local function getWallClockSeconds()
    if type(getTimestampMs) == "function" then
        local nowMs = tonumber(getTimestampMs())
        if nowMs ~= nil then
            return math.floor(nowMs / 1000)
        end
    end
    if type(getTimestamp) == "function" then
        local nowSecond = tonumber(getTimestamp())
        if nowSecond ~= nil then
            return math.floor(nowSecond)
        end
    end
    return 0
end

local function normalizeIdComponent(value, fallback)
    local text = tostring(value or "")
    text = text:gsub("[^%w_.-]", "-")
    text = text:gsub("-+", "-")
    text = text:gsub("^%-", "")
    text = text:gsub("%-$", "")
    if text == "" then
        return tostring(fallback or "unknown")
    end
    return text
end

local function resolveEatFraction(item, percentage)
    local percent = CoreUtils.clamp01(percentage or 1)
    local baseHunger = tonumber(safeCall(item, "getBaseHunger") or 0) or 0
    local hungerChange = tonumber(safeCall(item, "getHungChange") or safeCall(item, "getHungerChange") or 0) or 0

    if baseHunger ~= 0 and hungerChange ~= 0 then
        local hungerToConsume = baseHunger * percent
        local usedPercent = hungerToConsume / hungerChange
        percent = CoreUtils.clamp01(usedPercent)
    end

    if hungerChange < 0 and hungerChange * (1.0 - percent) > -0.01 then
        percent = 1.0
    end

    local thirstChange = tonumber(safeCall(item, "getThirstChange") or 0) or 0
    if hungerChange == 0 and thirstChange < 0 and thirstChange * (1.0 - percent) > -0.01 then
        percent = 1.0
    end

    return CoreUtils.clamp01(percent)
end

local state = MPClient._state or {}
MPClient._state = state
state.bootLogged = state.bootLogged == true
state.latestSnapshot = state.latestSnapshot
state.authoritativeState = type(state.authoritativeState) == "table" and state.authoritativeState or nil
state.projectedState = type(state.projectedState) == "table" and state.projectedState or nil
state.lastAcceptedSnapshotSeq = tonumber(state.lastAcceptedSnapshotSeq) or nil
state.lastSnapshotReceiveWallSecond = tonumber(state.lastSnapshotReceiveWallSecond) or 0
state.lastSnapshotServerWorldHours = tonumber(state.lastSnapshotServerWorldHours) or nil
state.lastSnapshotServerWallSeconds = tonumber(state.lastSnapshotServerWallSeconds) or nil
state.lastSnapshotReason = tostring(state.lastSnapshotReason or "")
state.snapshotAgeSeconds = tonumber(state.snapshotAgeSeconds) or 0
state.snapshotIsStale = state.snapshotIsStale == true
state.lastRequestWallSecond = tonumber(state.lastRequestWallSecond) or 0
state.nextEventSequence = tonumber(state.nextEventSequence) or 0
state.runtimeEventSessionId = state.runtimeEventSessionId
state.lastWorkloadReportWallSecond = tonumber(state.lastWorkloadReportWallSecond) or 0
state.lastWorkloadKeepaliveWallSecond = tonumber(state.lastWorkloadKeepaliveWallSecond) or 0
state.lastReportedWorkloadAverageMet = tonumber(state.lastReportedWorkloadAverageMet) or nil
state.lastReportedWorkloadPeakMet = tonumber(state.lastReportedWorkloadPeakMet) or nil
state.lastReportedWorkloadSource = tostring(state.lastReportedWorkloadSource or "")
state.nextWorkloadSequence = tonumber(state.nextWorkloadSequence) or 0

MPClient.MP = MP
MPClient.Runtime = Runtime
MPClient.Metabolism = Metabolism
MPClient.ItemAuthority = ItemAuthority
MPClient.CONSUME_EPSILON = CONSUME_EPSILON
MPClient.SNAPSHOT_STALE_SECONDS = SNAPSHOT_STALE_SECONDS
MPClient.PROJECTION_SMOOTH_ALPHA = PROJECTION_SMOOTH_ALPHA
MPClient.safeCall = safeCall
MPClient.log = log
MPClient.isClientRuntime = isClientRuntime
MPClient.isLocalAuthorityRuntime = isLocalAuthorityRuntime
MPClient.getWorldAgeMinutes = getWorldAgeMinutes
MPClient.getWorldHours = getWorldHours
MPClient.getWallClockSeconds = getWallClockSeconds
MPClient.getPlayerLabel = CoreUtils.getPlayerLabel
MPClient.getLocalPlayer = CoreUtils.getLocalPlayer
MPClient.normalizeIdComponent = normalizeIdComponent
MPClient.resolveEatFraction = resolveEatFraction
MPClient.getCharacterStatValue = CoreUtils.getCharacterStatValue
MPClient.clamp01 = CoreUtils.clamp01

return MPClient
