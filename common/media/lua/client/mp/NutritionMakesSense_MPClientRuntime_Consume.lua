NutritionMakesSense = NutritionMakesSense or {}

local MPClient = NutritionMakesSense.MPClientRuntime or {}
local Runtime = MPClient.Runtime or {}
local ItemAuthority = MPClient.ItemAuthority or {}
local CONSUME_EPSILON = MPClient.CONSUME_EPSILON or 0.0001
local log = MPClient.log
local safeCall = MPClient.safeCall
local clamp01 = MPClient.clamp01
local getCharacterStatValue = MPClient.getCharacterStatValue
local isClientRuntime = MPClient.isClientRuntime
local isLocalAuthorityRuntime = MPClient.isLocalAuthorityRuntime
local makeEventId = MPClient.makeEventId

function MPClient.getVisibleHunger(playerObj)
    local stats = playerObj and safeCall(playerObj, "getStats") or nil
    return getCharacterStatValue(stats, "HUNGER", "getHunger") or 0
end

function MPClient.resolveConsumedContext(item, fraction, preVisibleHunger)
    if not item or not ItemAuthority or type(ItemAuthority.resolveConsumedPayload) ~= "function" then
        return nil
    end
    return ItemAuthority.resolveConsumedPayload(item, fraction, preVisibleHunger)
end

function MPClient.measureConsumedPayload(item, beforeValues, afterValues)
    if not ItemAuthority or type(ItemAuthority.measureConsumedPayload) ~= "function" then
        return nil
    end
    return ItemAuthority.measureConsumedPayload(item, beforeValues, afterValues)
end

function MPClient.getDebugSnapshot(item)
    if not ItemAuthority or type(ItemAuthority.getDebugSnapshot) ~= "function" then
        return nil
    end
    return ItemAuthority.getDebugSnapshot(item)
end

function MPClient.usesCustomMpConsume(item)
    return isClientRuntime()
        and ItemAuthority
        and type(ItemAuthority.getResolvedNutritionSource) == "function"
        and tostring(ItemAuthority.getResolvedNutritionSource(item) or "") ~= ""
end

function MPClient.collectItems(listLike)
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
    if not isLocalAuthorityRuntime() or not Runtime or type(Runtime.applyAuthoritativeDeposit) ~= "function" then
        return false
    end

    if type(consumedContext) ~= "table" or type(consumedContext.values) ~= "table" then
        return false
    end

    local consumedValues = consumedContext.values
    local immediateHunger = consumedContext.immediateHunger
    local consumeSource = consumedContext.source
    local fullType = safeCall(item, "getFullType") or item and (item.fullType or item.id) or "unknown"
    local itemId = ItemAuthority.getItemId and ItemAuthority.getItemId(item) or tonumber(safeCall(item, "getID") or item and item.id or nil)
    local eventId = makeEventId(playerObj, itemId, reason)
    local report = Runtime.applyAuthoritativeDeposit(playerObj, consumedValues, reason or "local-consume", {
        eventId = eventId,
    })
    if not report then
        return false
    end
    if immediateHunger and type(Runtime.applyVisibleHungerTarget) == "function" then
        Runtime.applyVisibleHungerTarget(playerObj, immediateHunger.targetVisibleHunger, (reason or "local-consume") .. "-hunger")
    end

    local DevSupport = NutritionMakesSense.DevSupport
    if DevSupport and type(DevSupport.noteConsumeEvent) == "function" then
        DevSupport.noteConsumeEvent({
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
        "[LOCAL_CONSUME] event=%s item=%s source=%s fraction=%.3f kcal=%.1f carbs=%.1f fats=%.1f proteins=%.1f hunger_drop=%.4f",
        tostring(eventId),
        tostring(fullType),
        tostring(consumeSource or "unknown"),
        tonumber(fraction or 0),
        tonumber(consumedValues.kcal or 0),
        tonumber(consumedValues.carbs or 0),
        tonumber(consumedValues.fats or 0),
        tonumber(consumedValues.proteins or 0),
        tonumber(immediateHunger and immediateHunger.drop or 0)
    ))

    return true
end

return MPClient
