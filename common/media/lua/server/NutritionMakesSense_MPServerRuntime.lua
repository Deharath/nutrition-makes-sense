NutritionMakesSense = NutritionMakesSense or {}

local runningOnServer = (type(isServer) == "function") and (isServer() == true)
if not runningOnServer then
    return
end

require "NutritionMakesSense_Boot"
require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_ItemAuthority"
require "NutritionMakesSense_MetabolismRuntime"

local MP = NutritionMakesSense.MP or {}
local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
local serverReadyLogged = false
local recentEventsByPlayer = {}
local MAX_RECENT_EVENTS = 32
local RECENT_EVENT_STATE_KEY = "recentMpEventIds"

local function log(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(msg)
    else
        print("[NutritionMakesSense] " .. tostring(msg))
    end
end

local function safeCall(target, methodName, ...)
    if not target then
        return nil
    end

    local method = target[methodName]
    if type(method) ~= "function" then
        return nil
    end

    local ok, result = pcall(method, target, ...)
    if not ok then
        return nil
    end

    return result
end

local function normalizeConsumeFraction(value)
    local requested = tonumber(value)
    if requested == nil or requested ~= requested then
        return nil, nil, false
    end

    if requested <= 0 then
        return requested, 0, false
    end

    local applied = requested
    local clamped = false
    if applied > 1 then
        applied = 1
        clamped = true
    end

    return requested, applied, clamped
end

local function getPlayerKey(playerObj)
    local username = safeCall(playerObj, "getUsername")
    if username and username ~= "" then
        return tostring(username)
    end

    local onlineId = safeCall(playerObj, "getOnlineID")
    if onlineId ~= nil then
        return tostring(onlineId)
    end

    local displayName = safeCall(playerObj, "getDisplayName")
    if displayName and displayName ~= "" then
        return tostring(displayName)
    end

    return tostring(playerObj)
end

local function loadPersistedRecentEvents(playerObj)
    local state = Runtime.ensureStateForPlayer and Runtime.ensureStateForPlayer(playerObj) or nil
    local persisted = state and type(state[RECENT_EVENT_STATE_KEY]) == "table" and state[RECENT_EVENT_STATE_KEY] or nil
    local order = {}
    local seen = {}

    for _, entry in ipairs(persisted or {}) do
        local eventId = tostring(entry or "")
        if eventId ~= "" and not seen[eventId] then
            order[#order + 1] = eventId
            seen[eventId] = true
        end
    end

    return {
        order = order,
        seen = seen,
    }
end

local function persistRecentEvents(playerObj, bucket)
    if not playerObj or type(bucket) ~= "table" then
        return
    end

    local state = Runtime.ensureStateForPlayer and Runtime.ensureStateForPlayer(playerObj) or nil
    if type(state) ~= "table" then
        return
    end

    local order = {}
    for _, eventId in ipairs(bucket.order or {}) do
        if eventId and eventId ~= "" then
            order[#order + 1] = tostring(eventId)
        end
    end
    state[RECENT_EVENT_STATE_KEY] = order
end

local function getRecentEventBucket(playerObj, playerKey)
    if not playerKey then
        return nil
    end

    local bucket = recentEventsByPlayer[playerKey]
    if bucket then
        return bucket
    end

    bucket = loadPersistedRecentEvents(playerObj)
    recentEventsByPlayer[playerKey] = bucket
    return bucket
end

local function hasRecentEvent(playerObj, playerKey, eventId)
    if not playerKey or not eventId then
        return false
    end
    local bucket = getRecentEventBucket(playerObj, playerKey)
    return bucket and bucket.seen and bucket.seen[eventId] == true or false
end

local function rememberRecentEvent(playerObj, playerKey, eventId)
    if not playerKey or not eventId then
        return
    end

    local bucket = getRecentEventBucket(playerObj, playerKey)
    if not bucket then
        return
    end

    if bucket.seen[eventId] then
        return
    end

    bucket.order[#bucket.order + 1] = eventId
    bucket.seen[eventId] = true
    while #bucket.order > MAX_RECENT_EVENTS do
        local expired = table.remove(bucket.order, 1)
        bucket.seen[expired] = nil
    end

    persistRecentEvents(playerObj, bucket)
end

local function resolveInventoryItem(playerObj, itemId)
    local inventory = playerObj and safeCall(playerObj, "getInventory") or nil
    if not inventory or itemId == nil then
        return nil
    end

    local item = safeCall(inventory, "getItemWithID", itemId)
    if item then
        return item
    end

    item = safeCall(inventory, "getItemById", itemId)
    if item then
        return item
    end

    return safeCall(inventory, "getItemWithIDRecursiv", itemId)
end

local function eachOnlinePlayer(callback)
    if type(callback) ~= "function" or type(getOnlinePlayers) ~= "function" then
        return
    end

    local players = getOnlinePlayers()
    local count = tonumber(players and safeCall(players, "size")) or 0
    for index = 0, count - 1 do
        local playerObj = safeCall(players, "get", index)
        if playerObj then
            callback(playerObj, index)
        end
    end
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

local function normalizeConsumedValues(values)
    if type(values) ~= "table" then
        return nil
    end

    local normalized = {
        hunger = tonumber(values.hunger) or 0,
        baseHunger = tonumber(values.baseHunger or values.hunger) or 0,
        kcal = tonumber(values.kcal) or 0,
        carbs = tonumber(values.carbs) or 0,
        fats = tonumber(values.fats) or 0,
        proteins = tonumber(values.proteins) or 0,
    }

    if normalized.kcal <= 0
        and normalized.carbs <= 0
        and normalized.fats <= 0
        and normalized.proteins <= 0 then
        return nil
    end

    return normalized
end

local function sendStateSnapshot(playerObj, reason, extra)
    if type(sendServerCommand) ~= "function" then
        return nil
    end

    local snapshot = Runtime.buildStateSnapshot and Runtime.buildStateSnapshot(playerObj, reason) or nil
    if type(snapshot) ~= "table" then
        return nil
    end

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

    return snapshot
end

local function handleConsumeCommand(playerObj, args)
    if not playerObj or type(args) ~= "table" then
        return false
    end

    local requestedFraction, fraction, fractionClamped = normalizeConsumeFraction(args.fraction)
    if requestedFraction == nil or fraction <= 0 then
        return false
    end

    local playerKey = getPlayerKey(playerObj)
    local eventId = args.eventId and tostring(args.eventId) or nil
    if hasRecentEvent(playerObj, playerKey, eventId) then
        sendStateSnapshot(playerObj, "consume-duplicate", {
            eventId = eventId,
            requestedFraction = requestedFraction,
            appliedFraction = fraction,
            fractionClamped = fractionClamped == true,
            duplicate = true,
        })
        return true
    end

    local itemId = tonumber(args.itemId)
    local item = resolveInventoryItem(playerObj, itemId)
    local fullType = item and (safeCall(item, "getFullType") or item.fullType or item.id) or nil
    if args.fullType and fullType and tostring(args.fullType) ~= tostring(fullType) then
        item = nil
    end

    local consumedValues = normalizeConsumedValues(args.consumed)
    local immediateHungerDrop = tonumber(args.immediateHungerDrop) or 0
    if type(consumedValues) ~= "table" then
        sendStateSnapshot(playerObj, "consume-unresolved", {
            eventId = eventId,
            itemId = itemId,
            requestedFraction = requestedFraction,
            appliedFraction = fraction,
            fractionClamped = fractionClamped == true,
            unresolved = true,
        })
        return false
    end

    local report = Runtime.applyAuthoritativeDeposit and Runtime.applyAuthoritativeDeposit(playerObj, consumedValues, args.reason or "mp-consume", {
        eventId = eventId,
    }) or nil
    if not report then
        sendStateSnapshot(playerObj, "consume-ignored", {
            eventId = eventId,
            itemId = itemId,
            requestedFraction = requestedFraction,
            appliedFraction = fraction,
            fractionClamped = fractionClamped == true,
            ignored = true,
        })
        return false
    end
    if type(Runtime.applyVisibleHungerTarget) == "function" and args.preVisibleHunger ~= nil then
        Runtime.applyVisibleHungerTarget(
            playerObj,
            math.max(0, (tonumber(args.preVisibleHunger) or 0) - immediateHungerDrop),
            args.reason or "mp-consume"
        )
    end

    rememberRecentEvent(playerObj, playerKey, eventId)
    log(string.format(
        "[MP_SERVER_CONSUME] player=%s event=%s item=%s requested=%.3f applied=%.3f clamped=%s kcal=%.1f",
        tostring(playerKey),
        tostring(eventId or "none"),
        tostring(fullType or args.fullType or itemId or "unknown"),
        requestedFraction,
        fraction,
        tostring(fractionClamped == true),
        tonumber(consumedValues.kcal or 0)
    ))
    sendStateSnapshot(playerObj, "consume-applied", {
        eventId = eventId,
        itemId = itemId,
        fullType = tostring(fullType or args.fullType or "unknown"),
        requestedFraction = requestedFraction,
        appliedFraction = fraction,
        fractionClamped = fractionClamped == true,
        immediateHungerDrop = immediateHungerDrop,
        consumed = buildConsumedSnapshot(consumedValues),
    })
    return true
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

        if tostring(command) == tostring(MP.CONSUME_COMMAND) then
            handleConsumeCommand(playerObj, args or {})
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
    getRecentEventBucket(playerObj, getPlayerKey(playerObj))
    sendStateSnapshot(playerObj, "bootstrap-create-player", {
        bootstrap = true,
    })
end

local function onServerStarted()
    local report = NutritionMakesSense.StablePatcher.ensurePatched("server-start")

    if serverReadyLogged then
        return
    end
    serverReadyLogged = true

    log(string.format(
        "[SERVER_READY] version=%s module=%s patched=%d routed=%d explicit=%d",
        tostring(MP.SCRIPT_VERSION or "0.1.0"),
        tostring(MP.NET_MODULE or "NutritionMakesSenseRuntime"),
        tonumber(report and report.patchedRows or 0),
        tonumber(report and report.routedRows or 0),
        tonumber(report and report.explicitExceptionRows or 0)
    ))
end

local function onEveryOneMinute()
    eachOnlinePlayer(function(playerObj)
        sendStateSnapshot(playerObj, "minute-sync")
    end)
end

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
