NutritionMakesSense = NutritionMakesSense or {}

local runningOnServer = (type(isServer) == "function") and (isServer() == true)
if not runningOnServer then
    return
end

require "NutritionMakesSense_Boot"
require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_MetabolismRuntime"
require "NutritionMakesSense_CoreUtils"
require "dev/NutritionMakesSense_CompatTraceServer"

local MPServerRuntime = NutritionMakesSense.MPServerRuntime or {}
NutritionMakesSense.MPServerRuntime = MPServerRuntime

local MP = NutritionMakesSense.MP or {}
local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local CoreUtils = NutritionMakesSense.CoreUtils or {}
local CompatTraceServer = NutritionMakesSense.CompatTraceServer or {}

local PASSIVE_SNAPSHOT_INTERVAL_SECONDS = 0.25
local PASSIVE_SNAPSHOT_KEEPALIVE_SECONDS = 1.5
local SNAPSHOT_FUEL_EPSILON = 0.1
local SNAPSHOT_HUNGER_EPSILON = 0.0015
local SNAPSHOT_PROTEIN_EPSILON = 0.1
local SNAPSHOT_WEIGHT_EPSILON = 0.01
local SNAPSHOT_MET_EPSILON = 0.05
local SNAPSHOT_DEPRIVATION_EPSILON = 0.01
local CRITICAL_VISIBLE_HUNGER = 0.85
local CRITICAL_DEPRIVATION = 0.90
local SERVER_PLAYER_UPDATE_INTERVAL_SECONDS = 0.25

local snapshotStateByPlayerKey = {}
local lastServerUpdateByPlayerKey = {}
local nextServerSnapshotSeq = 0
local serverReadyLogged = false

local function log(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(msg)
    else
        print("[NutritionMakesSense] " .. tostring(msg))
    end
end

local safeCall = CoreUtils.safeCall
local eachKnownPlayer = CoreUtils.eachKnownPlayer
local getPlayerLabel = CoreUtils.getPlayerLabel
local getWorldHours = CoreUtils.getWorldHours
local getPlayerCacheKey = Runtime.getPlayerCacheKey or function(playerObj)
    return tostring(getPlayerLabel(playerObj))
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
    return (tonumber(getWorldHours()) or 0) * 3600
end

local function shallowCopy(tableLike)
    if type(tableLike) ~= "table" then
        return nil
    end
    local copy = {}
    for key, value in pairs(tableLike) do
        copy[key] = value
    end
    return copy
end

local function sendCompatTraceStatus(playerObj, payload)
    if not playerObj or type(sendServerCommand) ~= "function" or type(payload) ~= "table" then
        return false
    end

    local ok, err = pcall(
        sendServerCommand,
        playerObj,
        tostring(MP.NET_MODULE),
        tostring(MP.COMPAT_TRACE_STATUS_COMMAND),
        payload
    )
    if not ok then
        log("[MP_SERVER][ERROR] compat trace status send failed: " .. tostring(err))
        return false
    end
    return true
end

local function rememberSnapshotState(playerObj, snapshot)
    local key = getPlayerCacheKey(playerObj)
    local state = type(snapshot) == "table" and type(snapshot.state) == "table" and snapshot.state or nil
    if not key or not state then
        return
    end

    snapshotStateByPlayerKey[key] = {
        wallSecond = getWallClockSeconds(),
        fuel = tonumber(state.fuel) or 0,
        visibleHunger = tonumber(state.visibleHunger) or 0,
        proteins = tonumber(state.proteins) or 0,
        weightKg = tonumber(state.weightKg) or 0,
        deprivation = tonumber(state.deprivation) or 0,
        zone = tostring(state.lastZone or ""),
        workTier = tostring(state.lastWorkTier or ""),
        metAverage = tonumber(state.lastMetAverage) or 0,
        metPeak = tonumber(state.lastMetPeak) or 0,
    }
end

local function snapshotHasCriticalPressure(previous, snapshot)
    local state = type(snapshot) == "table" and type(snapshot.state) == "table" and snapshot.state or nil
    if not state then
        return false
    end

    local hunger = tonumber(state.visibleHunger) or 0
    local deprivation = tonumber(state.deprivation) or 0
    local zone = tostring(state.lastZone or "")

    if hunger >= CRITICAL_VISIBLE_HUNGER and (not previous or (tonumber(previous.visibleHunger) or 0) < CRITICAL_VISIBLE_HUNGER) then
        return true
    end
    if deprivation >= CRITICAL_DEPRIVATION and (not previous or (tonumber(previous.deprivation) or 0) < CRITICAL_DEPRIVATION) then
        return true
    end
    if zone == "depleted" and tostring(previous and previous.zone or "") ~= "depleted" then
        return true
    end

    return false
end

local function snapshotChangedMeaningfully(previous, snapshot)
    local state = type(snapshot) == "table" and type(snapshot.state) == "table" and snapshot.state or nil
    if not previous or not state then
        return true
    end

    if tostring(previous.zone or "") ~= tostring(state.lastZone or "") then
        return true
    end
    if tostring(previous.workTier or "") ~= tostring(state.lastWorkTier or "") then
        return true
    end
    if math.abs((tonumber(previous.fuel) or 0) - (tonumber(state.fuel) or 0)) >= SNAPSHOT_FUEL_EPSILON then
        return true
    end
    if math.abs((tonumber(previous.visibleHunger) or 0) - (tonumber(state.visibleHunger) or 0)) >= SNAPSHOT_HUNGER_EPSILON then
        return true
    end
    if math.abs((tonumber(previous.proteins) or 0) - (tonumber(state.proteins) or 0)) >= SNAPSHOT_PROTEIN_EPSILON then
        return true
    end
    if math.abs((tonumber(previous.weightKg) or 0) - (tonumber(state.weightKg) or 0)) >= SNAPSHOT_WEIGHT_EPSILON then
        return true
    end
    if math.abs((tonumber(previous.deprivation) or 0) - (tonumber(state.deprivation) or 0)) >= SNAPSHOT_DEPRIVATION_EPSILON then
        return true
    end
    if math.abs((tonumber(previous.metAverage) or 0) - (tonumber(state.lastMetAverage) or 0)) >= SNAPSHOT_MET_EPSILON then
        return true
    end
    if math.abs((tonumber(previous.metPeak) or 0) - (tonumber(state.lastMetPeak) or 0)) >= SNAPSHOT_MET_EPSILON then
        return true
    end

    return false
end

local function shouldSendPassiveSnapshot(playerObj, snapshot, force)
    if not playerObj or type(snapshot) ~= "table" then
        return false
    end

    local key = getPlayerCacheKey(playerObj)
    local previous = key and snapshotStateByPlayerKey[key] or nil
    local nowSecond = getWallClockSeconds()
    if force or not previous then
        return true
    end

    local elapsed = nowSecond - (tonumber(previous.wallSecond) or 0)
    if snapshotHasCriticalPressure(previous, snapshot) then
        return true
    end
    if elapsed < PASSIVE_SNAPSHOT_INTERVAL_SECONDS then
        return false
    end
    if snapshotChangedMeaningfully(previous, snapshot) then
        return true
    end

    return elapsed >= PASSIVE_SNAPSHOT_KEEPALIVE_SECONDS
end

local function sendStateSnapshot(playerObj, reason, extra, preparedSnapshot)
    if not playerObj or type(sendServerCommand) ~= "function" then
        return nil
    end

    local snapshot = preparedSnapshot
    if type(snapshot) ~= "table" and Runtime.buildStateSnapshot then
        snapshot = Runtime.buildStateSnapshot(playerObj, reason or "server")
    end
    if type(snapshot) ~= "table" or type(snapshot.state) ~= "table" then
        return nil
    end

    nextServerSnapshotSeq = nextServerSnapshotSeq + 1

    local payload = {
        version = tostring(snapshot.version or MP.SCRIPT_VERSION or "1.0.0"),
        reason = tostring(reason or snapshot.reason or "server"),
        state = shallowCopy(snapshot.state),
        worldHours = tonumber(snapshot.worldHours) or getWorldHours(),
        player = tostring(snapshot.player or getPlayerLabel(playerObj)),
        serverSeq = tonumber(nextServerSnapshotSeq),
        serverWorldHours = getWorldHours(),
        serverWallSeconds = getWallClockSeconds(),
    }

    if type(extra) == "table" then
        for key, value in pairs(extra) do
            payload[key] = value
        end
    end

    local ok, err = pcall(
        sendServerCommand,
        playerObj,
        tostring(MP.NET_MODULE),
        tostring(MP.STATE_SNAPSHOT_COMMAND),
        payload
    )
    if not ok then
        log("[MP_SERVER][ERROR] snapshot send failed: " .. tostring(err))
        return nil
    end

    rememberSnapshotState(playerObj, payload)
    return payload
end

local function maybeSendPassiveSnapshot(playerObj, reason, force)
    if not playerObj or type(Runtime.buildStateSnapshot) ~= "function" then
        return false
    end

    local snapshot = Runtime.buildStateSnapshot(playerObj, reason or "passive-sync")
    if not shouldSendPassiveSnapshot(playerObj, snapshot, force) then
        return false
    end

    return sendStateSnapshot(playerObj, reason or "passive-sync", nil, snapshot) ~= nil
end

local function onPlayerUpdate(playerObj)
    if not playerObj then
        return
    end

    local playerKey = getPlayerCacheKey(playerObj)
    if playerKey == nil then
        return
    end

    local nowSecond = getWallClockSeconds()
    local previousSecond = tonumber(lastServerUpdateByPlayerKey[playerKey]) or 0
    if (nowSecond - previousSecond) < SERVER_PLAYER_UPDATE_INTERVAL_SECONDS then
        return
    end
    lastServerUpdateByPlayerKey[playerKey] = nowSecond

    if Runtime.updatePlayer then
        Runtime.updatePlayer(playerObj, "server-player-update")
    end
    maybeSendPassiveSnapshot(playerObj, "server-player-update", false)
end

local function onClientCommand(module, command, playerObj, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end

    local ok, err = pcall(function()
        if tostring(command) == tostring(MP.REQUEST_SNAPSHOT_COMMAND) then
            sendStateSnapshot(playerObj, args and args.reason or "request", {
                bootstrap = true,
            })
            return
        end

        if tostring(command) == tostring(MP.REPORT_WORKLOAD_COMMAND) then
            if Runtime.reportPlayerWorkload then
                Runtime.reportPlayerWorkload(
                    playerObj,
                    {
                        averageMet = args and args.averageMet or nil,
                        peakMet = args and args.peakMet or nil,
                        source = args and args.source or nil,
                        sleepObserved = args and args.sleepObserved == true,
                    },
                    args and args.worldHours or nil,
                    args and args.reason or "client-report",
                    args and args.seq or nil
                )
            end
            if Runtime.updatePlayer then
                Runtime.updatePlayer(playerObj, "workload-report")
            end
            maybeSendPassiveSnapshot(playerObj, "workload-report", false)
            return
        end

        if tostring(command) == tostring(MP.COMPAT_TRACE_START_COMMAND) then
            local result = CompatTraceServer.startForPlayer and CompatTraceServer.startForPlayer(playerObj, args and args.label or "dev") or {
                ok = false,
                error = "trace_server_unavailable",
            }
            sendCompatTraceStatus(playerObj, {
                action = result.ok and "started" or "error",
                label = tostring(result.label or args and args.label or "dev"),
                sampleCount = tonumber(result.sampleCount) or 0,
                error = result.ok and nil or tostring(result.error or "trace_start_failed"),
            })
            return
        end

        if tostring(command) == tostring(MP.COMPAT_TRACE_STOP_COMMAND) then
            local result = CompatTraceServer.stopForPlayer and CompatTraceServer.stopForPlayer(playerObj) or {
                ok = false,
                error = "trace_server_unavailable",
            }
            sendCompatTraceStatus(playerObj, {
                action = result.ok and "stopped" or "error",
                label = tostring(result.label or args and args.label or "dev"),
                sampleCount = tonumber(result.sampleCount) or 0,
                savedPath = tostring(result.savedPath or ""),
                error = result.ok and nil or tostring(result.error or "trace_stop_failed"),
            })
            return
        end
    end)

    if not ok then
        log("[MP_SERVER][ERROR] onClientCommand: " .. tostring(err))
    end
end

local function onCreatePlayer(_, playerObj)
    if not playerObj then
        return
    end

    if Runtime.ensureStateForPlayer then
        Runtime.ensureStateForPlayer(playerObj)
    end
    sendStateSnapshot(playerObj, "bootstrap-create-player", {
        bootstrap = true,
    })
end

local function onServerStarted()
    if serverReadyLogged then
        return
    end
    serverReadyLogged = true

    log(string.format(
        "[SERVER_READY] version=%s module=%s mode=vanilla-first",
        tostring(MP.SCRIPT_VERSION or "1.0.0"),
        tostring(MP.NET_MODULE or "NutritionMakesSenseRuntime")
    ))
end

local function onEveryOneMinute()
    eachKnownPlayer(function(playerObj)
        if Runtime.updatePlayer then
            Runtime.updatePlayer(playerObj, "minute-maintenance")
        end
        maybeSendPassiveSnapshot(playerObj, "minute-maintenance", false)
    end)

    if CompatTraceServer.sampleAll then
        CompatTraceServer.sampleAll()
    end
end

function MPServerRuntime.install()
    local ServerRuntime = MPServerRuntime
    if not runningOnServer or not ServerRuntime then
        return ServerRuntime
    end
    if ServerRuntime._installed then
        return ServerRuntime
    end
    ServerRuntime._installed = true

    if Events then
        if Events.OnClientCommand and type(Events.OnClientCommand.Add) == "function" then
            Events.OnClientCommand.Add(onClientCommand)
        end
        if Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
            Events.OnCreatePlayer.Add(onCreatePlayer)
        end
        if Events.OnServerStarted and type(Events.OnServerStarted.Add) == "function" then
            Events.OnServerStarted.Add(onServerStarted)
        end
        if Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
            Events.OnPlayerUpdate.Add(onPlayerUpdate)
        end
        if Events.EveryOneMinute and type(Events.EveryOneMinute.Add) == "function" then
            Events.EveryOneMinute.Add(onEveryOneMinute)
        end
    end

    return ServerRuntime
end

return MPServerRuntime
