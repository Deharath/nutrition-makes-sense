NutritionMakesSense = NutritionMakesSense or {}

local MPClient = NutritionMakesSense.MPClientRuntime or {}
local state = MPClient._state or {}

local MP = MPClient.MP or {}
local ItemAuthority = MPClient.ItemAuthority or {}
local CONSUME_EPSILON = MPClient.CONSUME_EPSILON or 0.0001
local log = MPClient.log
local safeCall = MPClient.safeCall
local clamp01 = MPClient.clamp01
local isClientRuntime = MPClient.isClientRuntime
local getWorldAgeMinutes = MPClient.getWorldAgeMinutes
local getWallClockSeconds = MPClient.getWallClockSeconds
local getPlayerLabel = MPClient.getPlayerLabel
local normalizeIdComponent = MPClient.normalizeIdComponent

local function getRuntimeEventSessionId()
    if state.runtimeEventSessionId then
        return state.runtimeEventSessionId
    end

    local wallClockMs = tonumber(type(getTimestampMs) == "function" and getTimestampMs() or nil)
    if wallClockMs == nil then
        wallClockMs = (tonumber(getWallClockSeconds()) or 0) * 1000
    end

    local worldMinute = getWorldAgeMinutes()
    local uniqueToken = tostring({})
    local uniqueSuffix = uniqueToken:match("0x[%da-fA-F]+") or uniqueToken

    state.runtimeEventSessionId = string.format(
        "%s-%s-%s",
        normalizeIdComponent(wallClockMs, "0"),
        normalizeIdComponent(worldMinute, "0"),
        normalizeIdComponent(uniqueSuffix, "session")
    )
    return state.runtimeEventSessionId
end

function MPClient.getRuntimeEventSessionId()
    return getRuntimeEventSessionId()
end

local function makeEventId(playerObj, itemId, reason)
    state.nextEventSequence = tonumber(state.nextEventSequence) or 0
    state.nextEventSequence = state.nextEventSequence + 1
    return string.format(
        "%s:%s:%s:%s:%d",
        tostring(getPlayerLabel(playerObj, "player")),
        tostring(getRuntimeEventSessionId()),
        tostring(itemId or "item"),
        tostring(reason or "consume"),
        tonumber(state.nextEventSequence)
    )
end

MPClient.makeEventId = makeEventId

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
    if (not force) and (nowSecond - state.lastRequestWallSecond) < 1 then
        return false
    end
    state.lastRequestWallSecond = nowSecond

    local args = {
        reason = tostring(reason or "client-request"),
        worldMinute = getWorldAgeMinutes(),
    }
    return pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.REQUEST_SNAPSHOT_COMMAND), args)
end

function MPClient.queueConsume(playerObj, item, fraction, reason, consumedValues, immediateHunger)
    if not isClientRuntime() or type(sendClientCommand) ~= "function" then
        return false
    end

    local consumedFraction = clamp01(fraction or 0)
    if consumedFraction <= CONSUME_EPSILON then
        return false
    end

    local itemId = ItemAuthority.getItemId and ItemAuthority.getItemId(item) or tonumber(safeCall(item, "getID") or item and item.id or nil)
    local fullType = safeCall(item, "getFullType") or item and (item.fullType or item.id) or nil
    if itemId == nil or not fullType then
        return false
    end

    if not state.latestSnapshot then
        MPClient.requestSnapshot("pre-consume-bootstrap", true)
    end

    local eventId = makeEventId(playerObj, itemId, reason)
    local args = {
        eventId = eventId,
        itemId = itemId,
        fullType = tostring(fullType),
        fraction = consumedFraction,
        reason = tostring(reason or "consume"),
        worldMinute = getWorldAgeMinutes(),
    }
    if type(consumedValues) == "table" then
        args.consumed = {
            hunger = tonumber(consumedValues.hunger) or 0,
            baseHunger = tonumber(consumedValues.baseHunger or consumedValues.hunger) or 0,
            kcal = tonumber(consumedValues.kcal) or 0,
            carbs = tonumber(consumedValues.carbs) or 0,
            fats = tonumber(consumedValues.fats) or 0,
            proteins = tonumber(consumedValues.proteins) or 0,
        }
    end
    if type(immediateHunger) == "table" then
        args.immediateHungerDrop = tonumber(immediateHunger.drop) or 0
        args.preVisibleHunger = tonumber(immediateHunger.preVisibleHunger) or 0
    elseif immediateHunger ~= nil then
        args.immediateHungerDrop = tonumber(immediateHunger) or 0
    end

    local ok = pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.CONSUME_COMMAND), args)
    if ok then
        log(string.format(
            "[CLIENT_CONSUME_REQUEST] event=%s item=%s fraction=%.3f reason=%s payload=%s",
            tostring(eventId),
            tostring(fullType),
            consumedFraction,
            tostring(reason or "consume"),
            tostring(args.consumed ~= nil)
        ))
    end
    return ok, eventId, args
end

return MPClient
