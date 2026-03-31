NutritionMakesSense = NutritionMakesSense or {}

local MPClient = NutritionMakesSense.MPClientRuntime or {}
NutritionMakesSense.MPClientRuntime = MPClient
local Runtime = MPClient.Runtime or {}
local ItemAuthority = MPClient.ItemAuthority or {}
local MP = MPClient.MP or {}
local CONSUME_EPSILON = MPClient.CONSUME_EPSILON or 0.0001
local log = MPClient.log
local safeCall = MPClient.safeCall
local clamp01 = MPClient.clamp01
local getCharacterStatValue = MPClient.getCharacterStatValue
local isClientRuntime = MPClient.isClientRuntime
local isLocalAuthorityRuntime = MPClient.isLocalAuthorityRuntime
local makeEventId = MPClient.makeEventId

local function refreshBindings()
    MPClient = NutritionMakesSense.MPClientRuntime or MPClient
    NutritionMakesSense.MPClientRuntime = MPClient
    Runtime = MPClient.Runtime or NutritionMakesSense.MetabolismRuntime or Runtime
    ItemAuthority = MPClient.ItemAuthority or NutritionMakesSense.ItemAuthority or ItemAuthority
    MP = MPClient.MP or MP
    CONSUME_EPSILON = MPClient.CONSUME_EPSILON or CONSUME_EPSILON
    log = MPClient.log or log
    safeCall = MPClient.safeCall or safeCall
    clamp01 = MPClient.clamp01 or clamp01
    getCharacterStatValue = MPClient.getCharacterStatValue or getCharacterStatValue
    isClientRuntime = MPClient.isClientRuntime or isClientRuntime
    isLocalAuthorityRuntime = MPClient.isLocalAuthorityRuntime or isLocalAuthorityRuntime
    makeEventId = MPClient.makeEventId or makeEventId
end

function MPClient.getVisibleHunger(playerObj)
    refreshBindings()
    local stats = playerObj and safeCall(playerObj, "getStats") or nil
    return getCharacterStatValue(stats, "HUNGER", "getHunger") or 0
end

function MPClient.resolveConsumeFullType(item)
    refreshBindings()
    if not item then
        return nil
    end

    local fullType = safeCall(item, "getFullType")
    if fullType and tostring(fullType) ~= "" then
        return tostring(fullType)
    end

    local scriptItem = safeCall(item, "getScriptItem")
    local scriptFullName = scriptItem and safeCall(scriptItem, "getFullName") or nil
    if scriptFullName and tostring(scriptFullName) ~= "" then
        return tostring(scriptFullName)
    end

    local itemType = safeCall(item, "getType")
    local itemModule = safeCall(item, "getModule")
    if itemModule and tostring(itemModule) ~= "" and itemType and tostring(itemType) ~= "" then
        return tostring(itemModule) .. "." .. tostring(itemType)
    end
    if itemType and tostring(itemType) ~= "" then
        return tostring(itemType)
    end

    if type(item) == "table" then
        local tableFullType = item.fullType or item.id
        if tableFullType and tostring(tableFullType) ~= "" then
            return tostring(tableFullType)
        end
    end

    local rawString = tostring(item)
    if rawString ~= "" and rawString ~= "nil" and string.find(rawString, "%.") then
        return rawString
    end

    return nil
end

function MPClient.resolveConsumedContext(item, fraction, preVisibleHunger, hintedFullType)
    refreshBindings()
    if not item or not ItemAuthority then
        return nil
    end
    local fullTypeHint = hintedFullType or MPClient.resolveConsumeFullType(item)
    if type(ItemAuthority.resolveGameplayConsumeContext) == "function" then
        return ItemAuthority.resolveGameplayConsumeContext(item, fraction, preVisibleHunger, fullTypeHint)
    end
    if type(ItemAuthority.resolveConsumedPayload) == "function" then
        return ItemAuthority.resolveConsumedPayload(item, fraction, preVisibleHunger, fullTypeHint)
    end
    return nil
end

function MPClient.measureConsumedPayload(item, beforeValues, afterValues)
    refreshBindings()
    if not ItemAuthority or type(ItemAuthority.measureConsumedPayload) ~= "function" then
        return nil
    end
    return ItemAuthority.measureConsumedPayload(item, beforeValues, afterValues)
end

function MPClient.getDebugSnapshot(item)
    refreshBindings()
    if not ItemAuthority or type(ItemAuthority.getDebugSnapshot) ~= "function" then
        return nil
    end
    return ItemAuthority.getDebugSnapshot(item)
end

function MPClient.collectItems(listLike)
    refreshBindings()
    local items = {}
    if not listLike then
        return items
    end

    local size = safeCall(listLike, "size")
    if type(size) == "number" then
        for index = 0, size - 1 do
            items[#items + 1] = safeCall(listLike, "get", index)
        end
        return items
    end

    if type(listLike) == "table" then
        for _, item in ipairs(listLike) do
            items[#items + 1] = item
        end
    end
    return items
end

function MPClient.applyLocalConsume(playerObj, item, consumedContext, fraction, reason)
    refreshBindings()
    if type(consumedContext) ~= "table" or type(consumedContext.values) ~= "table" then
        return false
    end

    local consumedValues = consumedContext.values
    local immediateHunger = consumedContext.immediateHunger
    local consumeSource = consumedContext.source
    local fullType = safeCall(item, "getFullType") or item and (item.fullType or item.id) or "unknown"
    local itemId = ItemAuthority.getItemId and ItemAuthority.getItemId(item) or tonumber(safeCall(item, "getID") or item and item.id or nil)
    local eventId = makeEventId(playerObj, itemId, reason)

    if isClientRuntime() and type(sendClientCommand) == "function" then
        local args = {
            eventId = tostring(eventId),
            itemId = itemId,
            fullType = tostring(fullType),
            fraction = tonumber(fraction or 0),
            reason = tostring(reason or "client-consume"),
        }
        return pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.CONSUME_ITEM_COMMAND), args)
    end

    if not isLocalAuthorityRuntime() or not Runtime or type(Runtime.applyAuthoritativeDeposit) ~= "function" then
        return false
    end

    local report = Runtime.applyAuthoritativeDeposit(playerObj, consumedValues, reason or "local-consume", {
        eventId = eventId,
    })
    if not report then
        return false
    end
    if immediateHunger and type(Runtime.applyVisibleHungerTarget) == "function" then
        Runtime.applyVisibleHungerTarget(playerObj, immediateHunger.targetVisibleHunger, (reason or "local-consume") .. "-hunger")
    end

    local DebugSupport = NutritionMakesSense.DebugSupport
    if DebugSupport and type(DebugSupport.noteConsumeEvent) == "function" then
        DebugSupport.noteConsumeEvent({
            reason = reason or "local-consume",
            item = fullType,
            consume_source = consumeSource,
            fraction = fraction,
            kcal = consumedValues.kcal,
            carbs = consumedValues.carbs,
            fats = consumedValues.fats,
            proteins = consumedValues.proteins,
            immediate_hunger_drop = immediateHunger and immediateHunger.drop or nil,
            immediate_hunger_mechanical = immediateHunger and immediateHunger.mechanical or nil,
            pre_visible_hunger = immediateHunger and immediateHunger.preVisibleHunger or nil,
            target_visible_hunger = immediateHunger and immediateHunger.targetVisibleHunger or nil,
        })
    end

    log(string.format(
        "[NMS_CONSUME] item=%s source=%s reason=%s fraction=%.3f",
        tostring(fullType),
        tostring(consumeSource or "unknown"),
        tostring(reason or "local-consume"),
        tonumber(fraction or 0)
    ))

    return true
end

return MPClient
