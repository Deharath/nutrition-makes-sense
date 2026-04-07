NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_MetabolismRuntime"
require "NutritionMakesSense_CoreUtils"

local MPClient = NutritionMakesSense.MPClientRuntime or {}
NutritionMakesSense.MPClientRuntime = MPClient

local MP = NutritionMakesSense.MP or {}
local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local CoreUtils = NutritionMakesSense.CoreUtils or {}
local Metabolism = Runtime.Metabolism or {}

local SNAPSHOT_STALE_SECONDS = 2.5
local PROJECTION_SMOOTH_ALPHA = 0.35
local REQUEST_SNAPSHOT_COOLDOWN_SECONDS = 0.5
local WORKLOAD_KEEPALIVE_SECONDS = 1.5
local WORKLOAD_REPORT_MIN_INTERVAL_SECONDS = 0.5
local PROJECTION_PREDICTION_MAX_SECONDS = 1.0

local PROJECTED_NUMERIC_FIELDS = {
    "fuel",
    "proteins",
    "deprivation",
    "underfeedingDebtKcal",
    "weightKg",
    "weightController",
    "weightBalanceKcal",
    "lastWeightRateKgPerWeek",
    "lastWeightBalanceKcal",
    "lastWeightControllerTarget",
    "lastMetAverage",
    "lastMetPeak",
    "lastBurnKcal",
    "lastDepositKcal",
    "lastProteinDeficiency",
    "lastProteinHealingMultiplier",
    "lastUnderfeedingDebtKcal",
    "lastDeprivationTarget",
    "lastExtraEnduranceDrain",
    "visibleHunger",
}

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

local function copyState(rawState)
    if type(rawState) ~= "table" then
        return nil
    end

    if Metabolism and type(Metabolism.copyState) == "function" then
        return Metabolism.copyState(rawState)
    end

    local copy = {}
    for key, value in pairs(rawState) do
        copy[key] = value
    end
    return copy
end

local function clamp(value, minValue, maxValue)
    local numeric = tonumber(value) or 0
    if numeric < minValue then
        return minValue
    end
    if numeric > maxValue then
        return maxValue
    end
    return numeric
end

local function buildProjectedTarget(authoritative)
    if type(authoritative) ~= "table" then
        return authoritative
    end

    local target = copyState(authoritative)
    local nowSecond = getWallClockSeconds()
    local serverWallSecond = tonumber(state.lastSnapshotServerWallSeconds) or 0
    local receiveWallSecond = tonumber(state.lastSnapshotReceiveWallSecond) or 0
    local snapshotAgeSeconds = 0
    if serverWallSecond > 0 then
        snapshotAgeSeconds = math.max(0, nowSecond - serverWallSecond)
    elseif receiveWallSecond > 0 then
        snapshotAgeSeconds = math.max(0, nowSecond - receiveWallSecond)
    end
    snapshotAgeSeconds = math.min(snapshotAgeSeconds, PROJECTION_PREDICTION_MAX_SECONDS)
    if snapshotAgeSeconds <= 0 then
        return target
    end

    if Metabolism and type(Metabolism.getFuelBurnPerHourFromMet) == "function" then
        local averageMet = tonumber(authoritative.lastMetAverage) or tonumber(Metabolism.MET_REST) or 1.0
        local peakMet = tonumber(authoritative.lastMetPeak) or averageMet
        local burnPerHour = Metabolism.getFuelBurnPerHourFromMet({
            averageMet = averageMet,
            peakMet = peakMet,
            effectiveEnduranceMet = averageMet,
            workTier = tostring(authoritative.lastWorkTier or "rest"),
            source = tostring(authoritative.lastMetSource or "mp-projection"),
            sleepObserved = false,
            observedHours = 0,
            heavyHours = 0,
            veryHeavyHours = 0,
        }, tonumber(authoritative.weightKg), nil)
        local currentFuel = tonumber(authoritative.fuel)
        if currentFuel ~= nil and tonumber(burnPerHour) ~= nil then
            local predictedFuel = currentFuel - ((tonumber(burnPerHour) or 0) * (snapshotAgeSeconds / 3600))
            target.fuel = clamp(
                predictedFuel,
                tonumber(Metabolism.FUEL_MIN) or 0,
                tonumber(Metabolism.FUEL_MAX) or 2000
            )
        end
    end

    if Metabolism and type(Metabolism.getPassiveVisibleHungerRatePerHour) == "function" then
        local hungerRate = Metabolism.getPassiveVisibleHungerRatePerHour(authoritative, {
            averageMet = tonumber(authoritative.lastMetAverage),
            peakMet = tonumber(authoritative.lastMetPeak),
            effectiveEnduranceMet = tonumber(authoritative.lastEffectiveEnduranceMet),
            workTier = authoritative.lastWorkTier,
            source = authoritative.lastMetSource,
            sleepObserved = false,
            observedHours = tonumber(authoritative.lastObservedHours),
            heavyHours = tonumber(authoritative.lastHeavyHours),
            veryHeavyHours = tonumber(authoritative.lastVeryHeavyHours),
        }, nil)
        local currentHunger = tonumber(authoritative.visibleHunger)
        if type(hungerRate) == "table" and currentHunger ~= nil then
            local predictedHunger = currentHunger + ((tonumber(hungerRate.ratePerHour) or 0) * (snapshotAgeSeconds / 3600))
            target.visibleHunger = clamp(
                predictedHunger,
                tonumber(Metabolism.VISIBLE_HUNGER_MIN) or 0,
                tonumber(Metabolism.VISIBLE_HUNGER_CAP) or tonumber(Metabolism.VISIBLE_HUNGER_MAX) or 1
            )
        end
    end

    return target
end

local function refreshSnapshotMeta()
    local nowSecond = getWallClockSeconds()
    local receivedAt = tonumber(state.lastSnapshotReceiveWallSecond) or 0
    local ageSeconds = receivedAt > 0 and math.max(0, nowSecond - receivedAt) or math.huge
    state.snapshotAgeSeconds = ageSeconds
    state.snapshotIsStale = receivedAt <= 0 or ageSeconds >= SNAPSHOT_STALE_SECONDS
end

local function updateProjectedState(playerObj, immediate)
    refreshSnapshotMeta()

    local authoritative = state.authoritativeState
        or (playerObj and Runtime.getStateCopy and Runtime.getStateCopy(playerObj) or nil)
    if type(authoritative) ~= "table" then
        if type(state.projectedState) == "table" then
            local nowSecond = getWallClockSeconds()
            local lastWarn = tonumber(state.lastMissingAuthoritativeWarnWallSecond) or 0
            if (nowSecond - lastWarn) >= 1 then
                state.lastMissingAuthoritativeWarnWallSecond = nowSecond
                log(string.format(
                    "[MP_CLIENT][WARN] missing authoritative state seq=%s reason=%s",
                    tostring(state.lastAcceptedSnapshotSeq or "none"),
                    tostring(state.lastSnapshotReason or "none")
                ))
            end
        end
        return
    end

    if type(state.projectedState) ~= "table" or immediate then
        state.projectedState = buildProjectedTarget(authoritative)
        return
    end

    local projected = state.projectedState
    local targetState = buildProjectedTarget(authoritative)
    local alpha = state.snapshotIsStale and 1 or PROJECTION_SMOOTH_ALPHA

    for key, value in pairs(targetState) do
        if type(value) ~= "number" then
            projected[key] = value
        end
    end

    for _, key in ipairs(PROJECTED_NUMERIC_FIELDS) do
        local target = tonumber(targetState[key])
        if target ~= nil then
            local current = tonumber(projected[key])
            if current == nil or immediate or state.snapshotIsStale then
                projected[key] = target
            else
                projected[key] = current + ((target - current) * alpha)
            end
        else
            projected[key] = targetState[key]
        end
    end
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
    if not force and changed == false and (nowSecond - lastSent) < WORKLOAD_REPORT_MIN_INTERVAL_SECONDS then
        return false
    end

    state.lastReportedWorkloadAverageMet = averageMet
    state.lastReportedWorkloadPeakMet = peakMet
    state.lastReportedWorkloadSource = source
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
        reason = tostring(reason or (changed and "workload-change" or "workload-keepalive")),
    }
    return pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.REPORT_WORKLOAD_COMMAND), args)
end

function MPClient.getProjectionMeta()
    if not isClientRuntime() then
        return nil
    end
    refreshSnapshotMeta()
    return {
        lastSeq = tonumber(state.lastAcceptedSnapshotSeq) or nil,
        ageSeconds = tonumber(state.snapshotAgeSeconds) or nil,
        isStale = state.snapshotIsStale == true,
        lastReason = tostring(state.lastSnapshotReason or ""),
        serverWorldHours = tonumber(state.lastSnapshotServerWorldHours) or nil,
        serverWallSeconds = tonumber(state.lastSnapshotServerWallSeconds) or nil,
    }
end

function MPClient.getProjectedStateCopy(playerObj)
    if not isClientRuntime() then
        return nil
    end
    updateProjectedState(playerObj, false)
    return copyState(state.projectedState)
end

function MPClient.getAuthoritativeStateCopy(playerObj)
    if not isClientRuntime() then
        return nil
    end
    if type(state.authoritativeState) == "table" then
        return copyState(state.authoritativeState)
    end
    if playerObj and Runtime.getStateCopy then
        return Runtime.getStateCopy(playerObj)
    end
    return nil
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
    if incomingSeq ~= nil and previousSeq ~= nil and incomingSeq < previousSeq then
        return
    end

    state.latestSnapshot = args
    state.lastAcceptedSnapshotSeq = incomingSeq or previousSeq
    state.lastSnapshotReceiveWallSecond = getWallClockSeconds()
    state.lastSnapshotServerWorldHours = tonumber(args.serverWorldHours or args.worldHours) or nil
    state.lastSnapshotServerWallSeconds = tonumber(args.serverWallSeconds) or nil
    state.lastSnapshotReason = tostring(args.reason or "server")

    local playerObj = getLocalPlayer(0, nil)
    if playerObj and Runtime.importStateSnapshot then
        Runtime.importStateSnapshot(playerObj, args, args.reason or "mp-server")
        state.authoritativeState = Runtime.getStateCopy and Runtime.getStateCopy(playerObj) or copyState(args.state)
    else
        state.authoritativeState = copyState(args.state)
    end

    updateProjectedState(playerObj, type(state.projectedState) ~= "table")
end

local function onCreatePlayer(playerIndex, playerObj)
    if not isClientRuntime() then
        return
    end

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
    updateProjectedState(player, false)
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
    MPClient.Metabolism = Metabolism
    MPClient.SNAPSHOT_STALE_SECONDS = SNAPSHOT_STALE_SECONDS
    MPClient.PROJECTION_SMOOTH_ALPHA = PROJECTION_SMOOTH_ALPHA
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
