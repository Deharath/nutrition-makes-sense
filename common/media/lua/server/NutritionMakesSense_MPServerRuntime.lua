NutritionMakesSense = NutritionMakesSense or {}

local runningOnServer = (type(isServer) == "function") and (isServer() == true)
if not runningOnServer then
    return
end

require "NutritionMakesSense_Boot"
require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_ItemAuthority"
require "NutritionMakesSense_MetabolismRuntime"
require "NutritionMakesSense_CoreUtils"

local MPServerRuntime = NutritionMakesSense.MPServerRuntime or {}
NutritionMakesSense.MPServerRuntime = MPServerRuntime

local MP = NutritionMakesSense.MP or {}
local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
local CoreUtils = NutritionMakesSense.CoreUtils or {}
local serverReadyLogged = false
local CONSUME_EPSILON = tonumber(ItemAuthority.EPSILON) or 0.001
local PASSIVE_SNAPSHOT_INTERVAL_SECONDS = 1
local PASSIVE_SNAPSHOT_KEEPALIVE_SECONDS = 3
local SNAPSHOT_FUEL_EPSILON = 0.2
local SNAPSHOT_HUNGER_EPSILON = 0.0025
local SNAPSHOT_PROTEIN_EPSILON = 0.2
local SNAPSHOT_WEIGHT_EPSILON = 0.01
local SNAPSHOT_MET_EPSILON = 0.1
local snapshotStateByPlayerKey = {}
local recentConsumeEventsByPlayerKey = {}
local RECENT_CONSUME_EVENT_TTL_SECONDS = 60
local RECENT_CONSUME_EVENT_LIMIT = 64
local nextServerSnapshotSeq = 0

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
local sendStateSnapshot

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
    return math.floor((tonumber(getWorldHours()) or 0) * 3600)
end

local function getItemFullType(item)
    return safeCall(item, "getFullType") or item and (item.fullType or item.id) or "unknown"
end

local function getVisibleHunger(playerObj)
    local stats = playerObj and safeCall(playerObj, "getStats") or nil
    return CoreUtils.getCharacterStatValue(stats, "HUNGER", "getHunger") or 0
end

local function resolveEatFraction(item, percentage)
    local percent = CoreUtils.clamp01 and CoreUtils.clamp01(percentage or 1) or math.max(0, math.min(1, tonumber(percentage) or 1))
    local baseHunger = tonumber(safeCall(item, "getBaseHunger") or 0) or 0
    local hungerChange = tonumber(safeCall(item, "getHungChange") or safeCall(item, "getHungerChange") or 0) or 0

    if baseHunger ~= 0 and hungerChange ~= 0 then
        local hungerToConsume = baseHunger * percent
        local usedPercent = hungerToConsume / hungerChange
        percent = CoreUtils.clamp01 and CoreUtils.clamp01(usedPercent) or math.max(0, math.min(1, usedPercent))
    end

    if hungerChange < 0 and hungerChange * (1.0 - percent) > -0.01 then
        percent = 1.0
    end

    local thirstChange = tonumber(safeCall(item, "getThirstChange") or 0) or 0
    if hungerChange == 0 and thirstChange < 0 and thirstChange * (1.0 - percent) > -0.01 then
        percent = 1.0
    end

    return CoreUtils.clamp01 and CoreUtils.clamp01(percent) or math.max(0, math.min(1, percent))
end

local function resolveConsumedContext(item, fraction, preVisibleHunger)
    if not ItemAuthority or type(ItemAuthority.resolveConsumedPayload) ~= "function" then
        return nil
    end
    return ItemAuthority.resolveConsumedPayload(item, fraction, preVisibleHunger)
end

local function buildConsumedSnapshot(values)
    if type(values) ~= "table" then
        return nil
    end

    return {
        fullType = tostring(values.fullType or ""),
        authorityTarget = tostring(values.authorityTarget or values.fullType or ""),
        semanticClass = tostring(values.semanticClass or "unknown"),
        hunger = tonumber(values.hunger) or 0,
        kcal = tonumber(values.kcal) or 0,
        carbs = tonumber(values.carbs) or 0,
        fats = tonumber(values.fats) or 0,
        proteins = tonumber(values.proteins) or 0,
    }
end

local function pruneRecentConsumeEvents(playerObj)
    local key = getPlayerCacheKey(playerObj)
    if not key then
        return {}
    end

    local nowSecond = getWallClockSeconds()
    local existing = type(recentConsumeEventsByPlayerKey[key]) == "table" and recentConsumeEventsByPlayerKey[key] or {}
    local kept = {}
    for _, entry in ipairs(existing) do
        local eventId = entry and tostring(entry.eventId or "") or ""
        local wallSecond = tonumber(entry and entry.wallSecond) or 0
        if eventId ~= "" and (nowSecond - wallSecond) <= RECENT_CONSUME_EVENT_TTL_SECONDS then
            kept[#kept + 1] = {
                eventId = eventId,
                wallSecond = wallSecond,
            }
        end
    end
    recentConsumeEventsByPlayerKey[key] = kept
    return kept
end

local function hasRecentConsumeEvent(playerObj, eventId)
    local targetEventId = tostring(eventId or "")
    if targetEventId == "" then
        return false
    end

    for _, entry in ipairs(pruneRecentConsumeEvents(playerObj)) do
        if tostring(entry.eventId or "") == targetEventId then
            return true
        end
    end
    return false
end

local function rememberConsumeEvent(playerObj, eventId)
    local targetEventId = tostring(eventId or "")
    if targetEventId == "" then
        return
    end

    local entries = pruneRecentConsumeEvents(playerObj)
    entries[#entries + 1] = {
        eventId = targetEventId,
        wallSecond = getWallClockSeconds(),
    }
    while #entries > RECENT_CONSUME_EVENT_LIMIT do
        table.remove(entries, 1)
    end
end

local function resolveServerConsumedContext(playerObj, item, fullType, fraction)
    local recomputed = nil
    if item and type(ItemAuthority.resolveGameplayConsumeContext) == "function" then
        recomputed = ItemAuthority.resolveGameplayConsumeContext(item, fraction, getVisibleHunger(playerObj), fullType)
    elseif item and type(resolveConsumedContext) == "function" then
        recomputed = resolveConsumedContext(item, fraction, getVisibleHunger(playerObj), fullType)
    end
    if type(recomputed) ~= "table" and fullType ~= "" then
        if type(ItemAuthority.resolveGameplayConsumeContext) == "function" then
            recomputed = ItemAuthority.resolveGameplayConsumeContext(fullType, fraction, getVisibleHunger(playerObj), fullType)
        elseif type(ItemAuthority.resolveConsumedPayload) == "function" then
            recomputed = ItemAuthority.resolveConsumedPayload(fullType, fraction, getVisibleHunger(playerObj), fullType)
        end
    end
    if type(recomputed) ~= "table" or type(recomputed.values) ~= "table" then
        log(string.format(
            "[MP_SERVER_CONSUME_HARD_FAIL] player=%s item=%s detail=server-recompute-missing",
            tostring(getPlayerLabel(playerObj)),
            tostring(fullType or "unknown")
        ))
        return nil
    end

    recomputed.source = recomputed.source and tostring(recomputed.source) or "server_snapshot"
    return recomputed
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
        visibleHunger = tonumber(state.visibleHunger or state.hunger) or 0,
        proteins = tonumber(state.proteins) or 0,
        weightKg = tonumber(state.weightKg) or 0,
        zone = tostring(state.lastZone or ""),
        workTier = tostring(state.lastWorkTier or ""),
        metAverage = tonumber(state.lastMetAverage) or 0,
        metPeak = tonumber(state.lastMetPeak) or 0,
    }
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
    if math.abs((tonumber(previous.visibleHunger) or 0) - (tonumber(state.visibleHunger or state.hunger) or 0)) >= SNAPSHOT_HUNGER_EPSILON then
        return true
    end
    if math.abs((tonumber(previous.proteins) or 0) - (tonumber(state.proteins) or 0)) >= SNAPSHOT_PROTEIN_EPSILON then
        return true
    end
    if math.abs((tonumber(previous.weightKg) or 0) - (tonumber(state.weightKg) or 0)) >= SNAPSHOT_WEIGHT_EPSILON then
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
    if elapsed < PASSIVE_SNAPSHOT_INTERVAL_SECONDS then
        return false
    end

    if snapshotChangedMeaningfully(previous, snapshot) then
        return true
    end

    return elapsed >= PASSIVE_SNAPSHOT_KEEPALIVE_SECONDS
end

function sendStateSnapshot(playerObj, reason, extra, preparedSnapshot)
    if type(sendServerCommand) ~= "function" then
        return nil
    end

    local snapshot = preparedSnapshot or (Runtime.buildStateSnapshot and Runtime.buildStateSnapshot(playerObj, reason) or nil)
    if type(snapshot) ~= "table" then
        return nil
    end

    nextServerSnapshotSeq = nextServerSnapshotSeq + 1
    snapshot.serverSeq = nextServerSnapshotSeq
    snapshot.serverWorldHours = tonumber(snapshot.serverWorldHours or snapshot.worldHours or getWorldHours()) or 0
    snapshot.serverWallSeconds = tonumber(snapshot.serverWallSeconds) or getWallClockSeconds()
    snapshot.reason = tostring(reason or snapshot.reason or "server")
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            snapshot[key] = value
        end
    end

    local ok, err = pcall(sendServerCommand, playerObj, tostring(MP.NET_MODULE), tostring(MP.STATE_SNAPSHOT_COMMAND), snapshot)
    if not ok then
        log("[MP_SERVER][ERROR] snapshot send failed err=" .. tostring(err))
        return nil
    end

    rememberSnapshotState(playerObj, snapshot)
    return snapshot
end

local function maybeSendPassiveSnapshot(playerObj, reason, force)
    if not playerObj then
        return false
    end

    local snapshot = Runtime.buildStateSnapshot and Runtime.buildStateSnapshot(playerObj, reason) or nil
    if type(snapshot) ~= "table" then
        return false
    end
    if not shouldSendPassiveSnapshot(playerObj, snapshot, force) then
        return false
    end
    return sendStateSnapshot(playerObj, reason, nil, snapshot) ~= nil
end

local function applyServerConsume(playerObj, item, consumedContext, fraction, reason, options)
    if not playerObj or type(consumedContext) ~= "table" or type(consumedContext.values) ~= "table" then
        return false
    end

    options = type(options) == "table" and options or nil
    local fullType = getItemFullType(item)
    local consumedValues = consumedContext.values
    local report = Runtime.applyAuthoritativeDeposit and Runtime.applyAuthoritativeDeposit(playerObj, consumedValues, reason, {
        item = fullType,
    }) or nil
    if not report then
        return false
    end

    if consumedContext.immediateHunger and type(Runtime.applyVisibleHungerTarget) == "function" then
        Runtime.applyVisibleHungerTarget(
            playerObj,
            tonumber(consumedContext.immediateHunger.targetVisibleHunger) or 0,
            tostring(reason or "server-consume") .. "-hunger"
        )
    end

    log(string.format(
        "[NMS_CONSUME] player=%s item=%s source=%s reason=%s fraction=%.3f",
        tostring(getPlayerLabel(playerObj)),
        tostring(fullType),
        tostring(consumedContext.source or "unknown"),
        tostring(reason or "server-consume"),
        tonumber(fraction or 0)
    ))

    local snapshotExtra = options and type(options.snapshotExtra) == "table" and options.snapshotExtra or nil
    if not (options and options.skipSnapshot == true) then
        local extra = {
            fullType = tostring(fullType),
            appliedFraction = tonumber(fraction or 0),
            consumeSource = consumedContext.source and tostring(consumedContext.source) or nil,
            consumed = buildConsumedSnapshot(consumedValues),
        }
        if snapshotExtra then
            for key, value in pairs(snapshotExtra) do
                extra[key] = value
            end
        end
        sendStateSnapshot(playerObj, reason, extra)
    end
    return true
end

local function installServerHooks()
    return
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
            if type(Runtime.updatePlayer) == "function" then
                Runtime.updatePlayer(playerObj, "workload-report")
            end
            maybeSendPassiveSnapshot(playerObj, "passive-sync", false)
            return
        end

        if tostring(command) == tostring(MP.CONSUME_ITEM_COMMAND) then
            local eventId = args and tostring(args.eventId or "") or ""
            if eventId == "" then
                return
            end
            if hasRecentConsumeEvent(playerObj, eventId) then
                log(string.format(
                    "[MP_SERVER_CONSUME_DUPLICATE] player=%s event=%s",
                    tostring(getPlayerLabel(playerObj)),
                    tostring(eventId)
                ))
                return
            end

            local fraction = CoreUtils.clamp01 and CoreUtils.clamp01(args and args.fraction or 0) or math.max(0, math.min(1, tonumber(args and args.fraction) or 0))
            if fraction <= CONSUME_EPSILON then
                return
            end

            local itemId = tonumber(args and args.itemId) or nil
            local fullType = tostring(args and args.fullType or "")
            local item = itemId and CoreUtils.resolveInventoryItemById(playerObj, itemId) or nil
            if item and fullType ~= "" then
                local resolvedFullType = tostring(getItemFullType(item))
                if resolvedFullType ~= fullType then
                    log(string.format(
                        "[MP_SERVER_CONSUME_WARN] player=%s event=%s client=%s server=%s",
                        tostring(getPlayerLabel(playerObj)),
                        tostring(eventId),
                        tostring(fullType),
                        tostring(resolvedFullType)
                    ))
                end
            end

            local consumedContext = nil
            consumedContext = resolveServerConsumedContext(playerObj, item, fullType, fraction)
            if not consumedContext then
                return
            end
            local reason = tostring(args and args.reason or "client-consume")
            local applied = applyServerConsume(playerObj, item or { fullType = fullType, id = itemId }, consumedContext, fraction, reason, {
                snapshotExtra = {
                    eventId = tostring(eventId),
                    itemId = itemId,
                },
            })
            if applied then
                rememberConsumeEvent(playerObj, eventId)
                if type(Runtime.enqueuePendingNutritionSuppression) == "function" then
                    Runtime.enqueuePendingNutritionSuppression(playerObj, consumedContext.values, reason)
                end
            end
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
    local report = NutritionMakesSense.StablePatcher.ensurePatched("server-start")
    installServerHooks()

    if serverReadyLogged then
        return
    end
    serverReadyLogged = true

    log(string.format(
        "[SERVER_READY] version=%s module=%s patched=%d routed=%d explicit=%d",
        tostring(MP.SCRIPT_VERSION or "1.0.0"),
        tostring(MP.NET_MODULE or "NutritionMakesSenseRuntime"),
        tonumber(report and report.patchedRows or 0),
        tonumber(report and report.routedRows or 0),
        tonumber(report and report.explicitExceptionRows or 0)
    ))
end

local function onEveryOneMinute()
    eachKnownPlayer(function(playerObj)
        if type(Runtime.updatePlayer) == "function" then
            Runtime.updatePlayer(playerObj, "minute-sync")
        end
        maybeSendPassiveSnapshot(playerObj, "minute-sync", true)
    end)
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

    installServerHooks()

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
        if Events.EveryOneMinute and type(Events.EveryOneMinute.Add) == "function" then
            Events.EveryOneMinute.Add(onEveryOneMinute)
        end
    end

    return ServerRuntime
end

return MPServerRuntime
