NutritionMakesSense = NutritionMakesSense or {}

local MPClient = NutritionMakesSense.MPClientRuntime or {}
NutritionMakesSense.MPClientRuntime = MPClient
local Runtime = MPClient.Runtime or {}
local Metabolism = MPClient.Metabolism or Runtime.Metabolism or {}
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
    Metabolism = MPClient.Metabolism or Runtime.Metabolism or Metabolism
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

local function copyConsumeValues(values)
    if type(values) ~= "table" then
        return nil
    end

    return {
        fullType = values.fullType,
        authorityTarget = values.authorityTarget,
        snapshotMode = values.snapshotMode,
        entryAction = values.entryAction,
        hunger = tonumber(values.hunger) or 0,
        kcal = tonumber(values.kcal) or 0,
        carbs = tonumber(values.carbs) or 0,
        fats = tonumber(values.fats) or 0,
        proteins = tonumber(values.proteins) or 0,
        consumeAuthoritySource = values.consumeAuthoritySource,
    }
end

local function copyImmediateHunger(immediateHunger)
    if type(immediateHunger) ~= "table" then
        return nil
    end

    return {
        drop = tonumber(immediateHunger.drop) or 0,
        preVisibleHunger = tonumber(immediateHunger.preVisibleHunger) or 0,
        targetVisibleHunger = tonumber(immediateHunger.targetVisibleHunger) or 0,
        mechanical = tonumber(immediateHunger.mechanical) or 0,
    }
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

local function buildImmediateHunger(values, preVisibleHunger)
    if type(values) ~= "table" or type(Metabolism.getImmediateHungerDrop) ~= "function" then
        return nil
    end

    local drop = tonumber(Metabolism.getImmediateHungerDrop(values, 1))
    if drop == nil then
        return nil
    end

    local hunger = math.abs(tonumber(values.hunger) or 0)
    local pre = tonumber(preVisibleHunger) or 0
    return {
        drop = drop,
        preVisibleHunger = pre,
        targetVisibleHunger = math.max(0, pre - drop),
        mechanical = hunger,
    }
end

local function annotateMeasuredValues(values, entry, fullType, authoritySource)
    if type(values) ~= "table" then
        return nil
    end

    values.fullType = values.fullType or fullType
    if type(entry) == "table" then
        values.authorityTarget = values.authorityTarget or entry.authority_target or entry.authorityTarget
    end
    if type(ItemAuthority.getEntrySnapshotMode) == "function" then
        values.snapshotMode = ItemAuthority.getEntrySnapshotMode(entry) or values.snapshotMode or "unknown"
    end
    if type(ItemAuthority.getEntryAction) == "function" then
        values.entryAction = ItemAuthority.getEntryAction(entry) or values.entryAction or "unknown"
    end
    values.consumeAuthoritySource = authoritySource or values.consumeAuthoritySource or "unknown"
    return values
end

function MPClient.captureCurrentConsumeValues(item, hintedFullType)
    refreshBindings()
    if not item
        or not ItemAuthority
        or type(ItemAuthority.getFoodEntry) ~= "function"
        or type(ItemAuthority.readCurrentValuesPrivate) ~= "function"
    then
        return nil, nil, hintedFullType or MPClient.resolveConsumeFullType(item)
    end

    local fullTypeHint = hintedFullType or MPClient.resolveConsumeFullType(item)
    local entry, fullType = ItemAuthority.getFoodEntry(fullTypeHint or item)
    if not entry or not fullType then
        return nil, nil, fullTypeHint
    end

    return ItemAuthority.readCurrentValuesPrivate(item, fullType, entry), entry, fullType
end

function MPClient.buildMeasuredConsumeContext(item, beforeValues, afterValues, preVisibleHunger, hintedFullType)
    refreshBindings()
    local values = MPClient.measureConsumedPayload(item, beforeValues, afterValues)
    if type(values) ~= "table" then
        return nil
    end

    local authoritySource = nil
    local entry = nil
    local fullType = hintedFullType or MPClient.resolveConsumeFullType(item)
    if ItemAuthority and type(ItemAuthority.resolveGameplayConsumeAuthoritySource) == "function" then
        authoritySource, entry, fullType = ItemAuthority.resolveGameplayConsumeAuthoritySource(item, fullType)
    elseif ItemAuthority and type(ItemAuthority.getFoodEntry) == "function" then
        entry, fullType = ItemAuthority.getFoodEntry(fullType or item)
    end

    values = annotateMeasuredValues(values, entry, fullType, authoritySource)
    return {
        values = values,
        source = tostring(values.consumeAuthoritySource or authoritySource or "unknown"),
        immediateHunger = buildImmediateHunger(values, preVisibleHunger),
        measured = true,
    }
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
    local DebugSupport = NutritionMakesSense.DebugSupport

    local function noteDebugConsumeEvent()
        if not (DebugSupport and type(DebugSupport.noteConsumeEvent) == "function") then
            return
        end
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

    if isClientRuntime() and type(sendClientCommand) == "function" then
        local args = {
            eventId = tostring(eventId),
            itemId = itemId,
            fullType = tostring(fullType),
            fraction = tonumber(fraction or 0),
            reason = tostring(reason or "client-consume"),
            consumeSource = consumeSource and tostring(consumeSource) or nil,
            consumed = copyConsumeValues(consumedValues),
            consumedMeasured = consumedContext.measured == true,
            immediateHunger = copyImmediateHunger(immediateHunger),
        }
        local ok, err = pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.CONSUME_ITEM_COMMAND), args)
        if not ok then
            log(string.format(
                "[MP_CLIENT_CONSUME_SEND_FAIL] event=%s item=%s reason=%s detail=%s",
                tostring(eventId),
                tostring(fullType),
                tostring(reason or "client-consume"),
                tostring(err)
            ))
            return false
        end
        noteDebugConsumeEvent()
        return true
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

    noteDebugConsumeEvent()

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
