NutritionMakesSense = NutritionMakesSense or {}

local MPClient = NutritionMakesSense.MPClientRuntime or {}
local state = MPClient._state or {}

local MP = MPClient.MP or {}
local Runtime = MPClient.Runtime or {}
local Metabolism = MPClient.Metabolism or {}
local log = MPClient.log
local isClientRuntime = MPClient.isClientRuntime
local getLocalPlayer = MPClient.getLocalPlayer
local getPlayerLabel = MPClient.getPlayerLabel
local getWallClockSeconds = MPClient.getWallClockSeconds
local registerHooks = MPClient.registerHooks or function() end
local SNAPSHOT_STALE_SECONDS = MPClient.SNAPSHOT_STALE_SECONDS or 5
local PROJECTION_SMOOTH_ALPHA = MPClient.PROJECTION_SMOOTH_ALPHA or 0.35

local PROJECTED_NUMERIC_FIELDS = {
    "fuel",
    "proteins",
    "deprivation",
    "weightKg",
    "weightController",
    "lastWeightRateKgPerWeek",
    "lastMetAverage",
    "lastMetPeak",
    "lastBurnKcal",
    "lastDepositKcal",
    "lastProteinDeficiency",
    "lastProteinHealingMultiplier",
    "lastAcuteFuelRecoveryScale",
    "lastExtraEnduranceDrain",
    "visibleHunger",
    "hunger",
}

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

local function refreshSnapshotMeta()
    local nowSecond = getWallClockSeconds()
    local receivedAt = tonumber(state.lastSnapshotReceiveWallSecond) or 0
    local ageSeconds = receivedAt > 0 and math.max(0, nowSecond - receivedAt) or math.huge
    state.snapshotAgeSeconds = ageSeconds
    state.snapshotIsStale = receivedAt <= 0 or ageSeconds >= SNAPSHOT_STALE_SECONDS
end

local function updateProjectedState(playerObj, immediate)
    refreshSnapshotMeta()

    local authoritative = state.authoritativeState or (playerObj and Runtime.getStateCopy and Runtime.getStateCopy(playerObj) or nil)
    if type(authoritative) ~= "table" then
        return
    end

    if type(state.projectedState) ~= "table" or immediate then
        state.projectedState = copyState(authoritative)
        return
    end

    local projected = state.projectedState
    local alpha = PROJECTION_SMOOTH_ALPHA
    if state.snapshotIsStale then
        alpha = 1
    end

    for key, value in pairs(authoritative) do
        if type(value) ~= "number" then
            projected[key] = value
        end
    end

    for _, key in ipairs(PROJECTED_NUMERIC_FIELDS) do
        local target = tonumber(authoritative[key])
        if target ~= nil then
            local current = tonumber(projected[key])
            if current == nil or immediate or state.snapshotIsStale then
                projected[key] = target
            else
                projected[key] = current + ((target - current) * alpha)
            end
        else
            projected[key] = authoritative[key]
        end
    end
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
    if incomingSeq ~= nil and previousSeq ~= nil and incomingSeq <= previousSeq then
        log(string.format(
            "[CLIENT_SNAPSHOT_DROP] seq=%s previous=%s reason=%s",
            tostring(incomingSeq),
            tostring(previousSeq),
            tostring(args.reason or "server")
        ))
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

    log(string.format(
        "[CLIENT_SNAPSHOT] seq=%s reason=%s bootstrap=%s event=%s fuel=%.1f zone=%s",
        tostring(state.lastAcceptedSnapshotSeq or "none"),
        tostring(args.reason or "server"),
        tostring(args.bootstrap == true),
        tostring(args.eventId or "none"),
        tonumber(args.state and args.state.fuel or 0),
        tostring(args.state and args.state.lastZone or "unknown")
    ))
end

local function onCreatePlayer(playerIndex, playerObj)
    registerHooks()

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
        "[CLIENT_READY] player=%s version=%s module=%s",
        tostring(getPlayerLabel(playerObj, playerIndex)),
        tostring(MP.SCRIPT_VERSION or "1.0.0"),
        tostring(MP.NET_MODULE or "NutritionMakesSenseRuntime")
    ))
    log(string.format(
        "[MP_HOOK_REPORT] eat=%s drink=%s handcraft=%s evolved=%s workload_hook=%s snapshot_seq=%s stale_after=%ss",
        tostring(NutritionMakesSense._eatFoodWrapped == true),
        tostring(NutritionMakesSense._drinkFluidWrapped == true),
        tostring(NutritionMakesSense._handcraftWrapped == true),
        tostring(NutritionMakesSense._addItemRecipeWrapped == true),
        tostring(Events and Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function"),
        "enabled",
        tostring(SNAPSHOT_STALE_SECONDS)
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
end

function MPClient.install()
    if MPClient._installed then
        return MPClient
    end
    MPClient._installed = true

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
