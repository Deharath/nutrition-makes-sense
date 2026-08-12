NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_MetabolismRuntime"
require "NutritionMakesSense_CoreUtils"
require "NutritionMakesSense_DebugSupport"

local MPClient = NutritionMakesSense.MPClientRuntime or {}
NutritionMakesSense.MPClientRuntime = MPClient

local MP = NutritionMakesSense.MP or {}
local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local CoreUtils = NutritionMakesSense.CoreUtils or {}
local DebugSupport = NutritionMakesSense.DebugSupport or {}

local SNAPSHOT_STALE_SECONDS = 6.0
local REQUEST_SNAPSHOT_COOLDOWN_SECONDS = 0.5
local WORKLOAD_KEEPALIVE_SECONDS = 3.0
local WORKLOAD_REPORT_MIN_INTERVAL_SECONDS = 0.5
local MEAL_PREDICTION_HOLD_SECONDS = 6.0
local LEGACY_MEAL_PREDICTION_HOLD_SECONDS = 2.0
local MEAL_PREDICTION_CONFIRM_TOLERANCE = 0.02
local DISPLAY_HUNGER_SYNC_EPSILON = 0.0005

local state = MPClient._state or {}
MPClient._state = state

local function log(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(msg)
    else
        print("[NutritionMakesSense] " .. tostring(msg))
    end
end

local safeCall = CoreUtils.safeCall
local getLocalPlayer = CoreUtils.getLocalPlayer
local getPlayerLabel = CoreUtils.getPlayerLabel

local function isClientRuntime()
    return type(isClient) == "function" and isClient() == true and not (type(isServer) == "function" and isServer() == true)
end

local function getWorldHours()
    return tonumber(CoreUtils.getWorldHours and CoreUtils.getWorldHours() or nil)
end

local function getWallClockSeconds()
    if type(getTimestampMs) == "function" then
        local nowMs = tonumber(getTimestampMs())
        if nowMs ~= nil then
            return nowMs / 1000
        end
    end
    if type(getTimestamp) == "function" then
        local nowSeconds = tonumber(getTimestamp())
        if nowSeconds ~= nil then
            return nowSeconds
        end
    end
    return 0
end

local function refreshSnapshotMeta()
    local nowSecond = getWallClockSeconds()
    local receivedAt = tonumber(state.lastSnapshotReceiveWallSecond) or 0
    local ageSeconds = receivedAt > 0 and math.max(0, nowSecond - receivedAt) or math.huge
    state.snapshotAgeSeconds = ageSeconds
    state.snapshotIsStale = receivedAt <= 0 or ageSeconds >= SNAPSHOT_STALE_SECONDS
end

local function workloadChanged(live)
    local previousAverage = tonumber(state.lastReportedWorkloadAverageMet) or nil
    local previousPeak = tonumber(state.lastReportedWorkloadPeakMet) or nil
    local previousSource = tostring(state.lastReportedWorkloadSource or "")
    local averageMet = tonumber(live and live.averageMet) or 0
    local peakMet = tonumber(live and live.peakMet) or averageMet
    local source = tostring(live and live.source or "")

    if previousAverage == nil or math.abs(previousAverage - averageMet) > 0.15 then
        return true
    end
    if previousPeak == nil or math.abs(previousPeak - peakMet) > 0.15 then
        return true
    end
    return previousSource ~= source
end

function MPClient.getSnapshot()
    return state.latestSnapshot
end

function MPClient.clearSnapshot()
    state.latestSnapshot = nil
    state.lastAcceptedSnapshotSeq = nil
    state.lastSnapshotReceiveWallSecond = nil
    state.lastSnapshotServerWorldHours = nil
    state.lastSnapshotServerWallSeconds = nil
    state.lastSnapshotReason = nil
    state.lastServerDepositSequence = nil
    state.lastAuthoritativeHunger = nil
    state.displayHungerTarget = nil
    state.pendingMealPrediction = nil
    state.lastPredictionResolution = "session-reset"
    state.snapshotAgeSeconds = math.huge
    state.snapshotIsStale = true
end

local function getSnapshotState(snapshot)
    return type(snapshot) == "table" and type(snapshot.state) == "table" and snapshot.state or nil
end

local function getPredictionAgeSeconds(prediction)
    if type(prediction) ~= "table" then
        return nil
    end
    return math.max(0, getWallClockSeconds() - (tonumber(prediction.createdWallSecond) or 0))
end

local function clearMealPrediction(resolution)
    if state.pendingMealPrediction then
        state.lastPredictionResolution = tostring(resolution or "cleared")
    end
    state.pendingMealPrediction = nil
end

local function copySnapshotWithHunger(snapshot, visibleHunger)
    local copy = {}
    for key, value in pairs(snapshot or {}) do
        copy[key] = value
    end
    copy.state = {}
    for key, value in pairs(getSnapshotState(snapshot) or {}) do
        copy.state[key] = value
    end
    copy.state.visibleHunger = visibleHunger
    copy.clientPredictionHeld = true
    return copy
end

local function reconcileMealPrediction(snapshot)
    local snapshotState = getSnapshotState(snapshot)
    local authoritativeHunger = tonumber(snapshotState and snapshotState.visibleHunger) or nil
    local depositSequence = tonumber(snapshotState and snapshotState.depositSequence) or nil
    state.lastAuthoritativeHunger = authoritativeHunger
    state.lastServerDepositSequence = depositSequence

    local prediction = state.pendingMealPrediction
    if type(prediction) ~= "table" or authoritativeHunger == nil then
        state.displayHungerTarget = authoritativeHunger
        return snapshot
    end

    prediction.lastServerDepositSequence = depositSequence
    prediction.lastAuthoritativeHunger = authoritativeHunger
    local baselineDepositSequence = tonumber(prediction.baselineDepositSequence) or nil
    local hasCausalSequence = baselineDepositSequence ~= nil and depositSequence ~= nil
    local predictionConfirmed = hasCausalSequence and depositSequence > baselineDepositSequence
    local holdSeconds = hasCausalSequence
        and MEAL_PREDICTION_HOLD_SECONDS or LEGACY_MEAL_PREDICTION_HOLD_SECONDS
    local ageSeconds = getPredictionAgeSeconds(prediction) or 0

    if ageSeconds >= holdSeconds then
        clearMealPrediction("timeout-authoritative")
        state.displayHungerTarget = authoritativeHunger
        return snapshot
    end

    local targetHunger = tonumber(prediction.targetHunger) or authoritativeHunger
    prediction.displayCeiling = math.min(
        tonumber(prediction.displayCeiling) or targetHunger,
        targetHunger,
        authoritativeHunger
    )

    if predictionConfirmed
        and authoritativeHunger <= targetHunger + MEAL_PREDICTION_CONFIRM_TOLERANCE then
        clearMealPrediction("server-confirmed")
        state.displayHungerTarget = authoritativeHunger
        return snapshot
    end

    local effectiveHunger = math.min(authoritativeHunger, prediction.displayCeiling)
    state.displayHungerTarget = effectiveHunger
    if effectiveHunger < authoritativeHunger - DISPLAY_HUNGER_SYNC_EPSILON then
        state.lastPredictionResolution = predictionConfirmed
            and "confirmed-settling" or "holding-premeal-snapshot"
        return copySnapshotWithHunger(snapshot, effectiveHunger)
    end
    return snapshot
end

function MPClient.noteMealPrediction(playerObj, report)
    if not isClientRuntime() or type(report) ~= "table" then
        return false
    end

    local targetHunger = tonumber(report.targetVisibleHunger)
    if targetHunger == nil then
        return false
    end

    local snapshotState = getSnapshotState(state.latestSnapshot)
    local baselineDepositSequence = tonumber(snapshotState and snapshotState.depositSequence) or nil
    if baselineDepositSequence == nil and playerObj and type(Runtime.getStateCopy) == "function" then
        local localState = Runtime.getStateCopy(playerObj)
        baselineDepositSequence = tonumber(localState and localState.depositSequence) or nil
    end

    state.pendingMealPrediction = {
        createdWallSecond = getWallClockSeconds(),
        targetHunger = targetHunger,
        displayCeiling = targetHunger,
        preVisibleHunger = tonumber(report.preVisibleHunger) or nil,
        baselineSnapshotSeq = tonumber(state.lastAcceptedSnapshotSeq) or nil,
        baselineDepositSequence = baselineDepositSequence,
        reason = tostring(report.reason or "client-meal-prediction"),
    }
    state.displayHungerTarget = targetHunger
    state.lastPredictionResolution = "active"
    return true
end

function MPClient.requestSnapshot(reason, force)
    if not isClientRuntime() or type(sendClientCommand) ~= "function" then
        return false
    end

    local nowSecond = getWallClockSeconds()
    state.lastRequestWallSecond = tonumber(state.lastRequestWallSecond) or 0
    if (not force) and (nowSecond - state.lastRequestWallSecond) < REQUEST_SNAPSHOT_COOLDOWN_SECONDS then
        return false
    end
    state.lastRequestWallSecond = nowSecond

    local args = {
        reason = tostring(reason or "client-request"),
        worldHours = getWorldHours(),
    }
    return pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.REQUEST_SNAPSHOT_COMMAND), args)
end

function MPClient.reportWorkload(playerObj, force, reason)
    if not isClientRuntime() or type(sendClientCommand) ~= "function" or not playerObj then
        return false
    end

    local live = Runtime.sampleReportedWorkload and Runtime.sampleReportedWorkload(playerObj) or nil
    if type(live) ~= "table" then
        return false
    end

    local averageMet = tonumber(live.averageMet) or 0
    local peakMet = tonumber(live.peakMet) or averageMet
    local source = tostring(live.source or "unknown")
    local nowSecond = getWallClockSeconds()
    local changed = workloadChanged(live)
    local lastSent = tonumber(state.lastWorkloadReportWallSecond) or 0
    local keepaliveSent = tonumber(state.lastWorkloadKeepaliveWallSecond) or 0
    local keepaliveDue = (nowSecond - keepaliveSent) >= WORKLOAD_KEEPALIVE_SECONDS

    if not force and not changed and not keepaliveDue then
        return false
    end
    if not force and (nowSecond - lastSent) < WORKLOAD_REPORT_MIN_INTERVAL_SECONDS then
        return false
    end

    state.lastReportedWorkloadAverageMet = averageMet
    state.lastReportedWorkloadPeakMet = peakMet
    state.lastReportedWorkloadSource = source
    state.lastWorkloadReportReason = tostring(reason or (changed and "workload-change" or "workload-keepalive"))
    state.lastWorkloadReportWallSecond = nowSecond
    state.nextWorkloadSequence = (tonumber(state.nextWorkloadSequence) or 0) + 1
    if keepaliveDue or changed or force then
        state.lastWorkloadKeepaliveWallSecond = nowSecond
    end

    local args = {
        seq = tonumber(state.nextWorkloadSequence),
        averageMet = averageMet,
        peakMet = peakMet,
        source = source,
        sleepObserved = live.sleepObserved == true,
        worldHours = getWorldHours(),
        reason = state.lastWorkloadReportReason,
    }
    return pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.REPORT_WORKLOAD_COMMAND), args)
end

function MPClient.getSnapshotMeta()
    if not isClientRuntime() then
        return nil
    end
    refreshSnapshotMeta()
    local prediction = state.pendingMealPrediction
    return {
        lastSeq = tonumber(state.lastAcceptedSnapshotSeq) or nil,
        ageSeconds = tonumber(state.snapshotAgeSeconds) or nil,
        isStale = state.snapshotIsStale == true,
        lastReason = tostring(state.lastSnapshotReason or ""),
        serverWorldHours = tonumber(state.lastSnapshotServerWorldHours) or nil,
        serverWallSeconds = tonumber(state.lastSnapshotServerWallSeconds) or nil,
        workloadSeq = tonumber(state.nextWorkloadSequence) or nil,
        workloadAgeSeconds = state.lastWorkloadReportWallSecond
            and math.max(0, getWallClockSeconds() - tonumber(state.lastWorkloadReportWallSecond)) or nil,
        workloadAverageMet = tonumber(state.lastReportedWorkloadAverageMet) or nil,
        workloadPeakMet = tonumber(state.lastReportedWorkloadPeakMet) or nil,
        workloadSource = tostring(state.lastReportedWorkloadSource or ""),
        workloadReason = tostring(state.lastWorkloadReportReason or ""),
        authoritativeHunger = tonumber(state.lastAuthoritativeHunger) or nil,
        displayHungerTarget = tonumber(state.displayHungerTarget) or nil,
        serverDepositSequence = tonumber(state.lastServerDepositSequence) or nil,
        mealPredictionActive = type(prediction) == "table",
        mealPredictionTargetHunger = tonumber(prediction and prediction.targetHunger) or nil,
        mealPredictionAgeSeconds = getPredictionAgeSeconds(prediction),
        mealPredictionBaselineSnapshotSeq = tonumber(prediction and prediction.baselineSnapshotSeq) or nil,
        mealPredictionBaselineDepositSequence = tonumber(prediction and prediction.baselineDepositSequence) or nil,
        mealPredictionLastServerDepositSequence = tonumber(prediction and prediction.lastServerDepositSequence) or nil,
        mealPredictionResolution = tostring(state.lastPredictionResolution or ""),
    }
end

local function onServerCommand(module, command, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end
    if tostring(command) ~= tostring(MP.STATE_SNAPSHOT_COMMAND) then
        return
    end
    if not isClientRuntime() or type(args) ~= "table" then
        return
    end

    local incomingSeq = tonumber(args.serverSeq) or nil
    local previousSeq = tonumber(state.lastAcceptedSnapshotSeq) or nil
    if incomingSeq ~= nil and previousSeq ~= nil and incomingSeq <= previousSeq then
        return
    end

    state.latestSnapshot = args
    state.lastAcceptedSnapshotSeq = incomingSeq or previousSeq
    state.lastSnapshotReceiveWallSecond = getWallClockSeconds()
    state.lastSnapshotServerWorldHours = tonumber(args.serverWorldHours or args.worldHours) or nil
    state.lastSnapshotServerWallSeconds = tonumber(args.serverWallSeconds) or nil
    state.lastSnapshotReason = tostring(args.reason or "server")

    local effectiveSnapshot = reconcileMealPrediction(args)
    local playerObj = getLocalPlayer(0, nil)
    if playerObj and Runtime.importStateSnapshot then
        Runtime.importStateSnapshot(playerObj, effectiveSnapshot, args.reason or "mp-server")
    end
    if type(DebugSupport.noteSnapshotEvent) == "function" then
        DebugSupport.noteSnapshotEvent({
            reason = tostring(args.reason or "server"),
            provenance = "mp-server-snapshot",
            consume_source = "mp-state-sync",
            snapshot_sequence = incomingSeq,
            snapshot_server_world_hours = tonumber(args.serverWorldHours or args.worldHours),
            snapshot_server_wall_seconds = tonumber(args.serverWallSeconds),
            snapshot_deposit_sequence = tonumber(state.lastServerDepositSequence),
            snapshot_authoritative_hunger = tonumber(state.lastAuthoritativeHunger),
            snapshot_display_hunger = tonumber(state.displayHungerTarget),
            meal_prediction_resolution = tostring(state.lastPredictionResolution or ""),
        })
    end
end

local function onCreatePlayer(playerIndex, playerObj)
    if not isClientRuntime() then
        return
    end

    MPClient.clearSnapshot()
    MPClient.requestSnapshot("create-player", true)
    MPClient.reportWorkload(playerObj or getLocalPlayer(0, nil), true, "create-player")

    if state.bootLogged then
        return
    end
    state.bootLogged = true

    log(string.format(
        "[CLIENT_READY] player=%s version=%s module=%s sync=snapshot+workload",
        tostring(getPlayerLabel(playerObj, playerIndex)),
        tostring(MP.SCRIPT_VERSION or "1.0.0"),
        tostring(MP.NET_MODULE or "NutritionMakesSenseRuntime")
    ))
end

local function onPlayerUpdate(playerObj)
    if not isClientRuntime() then
        return
    end

    local player = playerObj or getLocalPlayer(0, nil)
    if not player then
        return
    end

    MPClient.reportWorkload(player, false, "player-update")
    refreshSnapshotMeta()

    local prediction = state.pendingMealPrediction
    if type(prediction) == "table" then
        local hasCausalSequence = tonumber(prediction.baselineDepositSequence) ~= nil
        local holdSeconds = hasCausalSequence
            and MEAL_PREDICTION_HOLD_SECONDS or LEGACY_MEAL_PREDICTION_HOLD_SECONDS
        if (getPredictionAgeSeconds(prediction) or 0) >= holdSeconds then
            clearMealPrediction("timeout-authoritative")
            local snapshotState = getSnapshotState(state.latestSnapshot)
            state.displayHungerTarget = tonumber(snapshotState and snapshotState.visibleHunger) or nil
            MPClient.requestSnapshot("meal-prediction-timeout", true)
        end
    end

    local displayTarget = tonumber(state.displayHungerTarget)
    if displayTarget ~= nil and type(Runtime.applyVisibleHungerTarget) == "function" then
        local stats = type(Runtime.getPlayerStats) == "function" and Runtime.getPlayerStats(player) or nil
        local liveHunger = type(Runtime.getVisibleHungerValue) == "function"
            and tonumber(Runtime.getVisibleHungerValue(stats)) or nil
        if liveHunger == nil or math.abs(liveHunger - displayTarget) > DISPLAY_HUNGER_SYNC_EPSILON then
            Runtime.applyVisibleHungerTarget(player, displayTarget, "mp-display-anchor")
        end
    end

    if type(Runtime.getPlayerBodyDamage) == "function"
        and type(Runtime.suppressFoodEatenTimer) == "function" then
        Runtime.suppressFoodEatenTimer(Runtime.getPlayerBodyDamage(player))
    end
    if state.snapshotIsStale then
        MPClient.requestSnapshot("stale-snapshot", false)
    end
end

function MPClient.install()
    if MPClient._installed then
        return MPClient
    end
    MPClient._installed = true

    MPClient.MP = MP
    MPClient.Runtime = Runtime
    MPClient.SNAPSHOT_STALE_SECONDS = SNAPSHOT_STALE_SECONDS
    MPClient.MEAL_PREDICTION_HOLD_SECONDS = MEAL_PREDICTION_HOLD_SECONDS
    MPClient.MEAL_PREDICTION_CONFIRM_TOLERANCE = MEAL_PREDICTION_CONFIRM_TOLERANCE
    MPClient.log = log
    MPClient.safeCall = safeCall
    MPClient.isClientRuntime = isClientRuntime
    MPClient.getWorldHours = getWorldHours
    MPClient.getWallClockSeconds = getWallClockSeconds
    MPClient.getPlayerLabel = getPlayerLabel
    MPClient.getLocalPlayer = getLocalPlayer

    if Events then
        if Events.OnServerCommand and type(Events.OnServerCommand.Add) == "function" then
            Events.OnServerCommand.Add(onServerCommand)
        end
        if Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
            Events.OnCreatePlayer.Add(onCreatePlayer)
        end
        if Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
            Events.OnPlayerUpdate.Add(onPlayerUpdate)
        end
    end

    return MPClient
end

return MPClient
