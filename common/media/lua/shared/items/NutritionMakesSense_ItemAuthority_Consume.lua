NutritionMakesSense = NutritionMakesSense or {}

local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
NutritionMakesSense.ItemAuthority = ItemAuthority
local Metabolism = NutritionMakesSense.Metabolism or {}

local CONSUME_EPSILON = ItemAuthority.CONSUME_EPSILON or 0.0001

local function refreshBindings()
    ItemAuthority = NutritionMakesSense.ItemAuthority or ItemAuthority
    NutritionMakesSense.ItemAuthority = ItemAuthority
    Metabolism = NutritionMakesSense.Metabolism or Metabolism
    CONSUME_EPSILON = ItemAuthority.CONSUME_EPSILON or CONSUME_EPSILON
end

local function resolveStaticAuthoritySource(totalSnapshot, fullType, entry)
    if type(totalSnapshot) == "table" and type(totalSnapshot.nutritionSource) == "string" and totalSnapshot.nutritionSource ~= "" then
        return totalSnapshot.nutritionSource
    end

    if type(ItemAuthority.getStaticFoodValueSource) == "function" then
        return ItemAuthority.getStaticFoodValueSource(fullType, entry)
    end

    return "authored"
end

local function resolveFullTypeHint(itemOrFullType, hintedFullType)
    if type(hintedFullType) == "string" and hintedFullType ~= "" then
        return hintedFullType
    end

    if type(itemOrFullType) == "string" and itemOrFullType ~= "" then
        return itemOrFullType
    end

    if itemOrFullType == nil then
        return nil
    end

    if type(ItemAuthority.safeCall) == "function" then
        local fullType = ItemAuthority.safeCall(itemOrFullType, "getFullType")
        if fullType and tostring(fullType) ~= "" then
            return tostring(fullType)
        end

        local scriptItem = ItemAuthority.safeCall(itemOrFullType, "getScriptItem")
        local scriptFullName = scriptItem and ItemAuthority.safeCall(scriptItem, "getFullName") or nil
        if scriptFullName and tostring(scriptFullName) ~= "" then
            return tostring(scriptFullName)
        end

        local itemType = ItemAuthority.safeCall(itemOrFullType, "getType")
        local itemModule = ItemAuthority.safeCall(itemOrFullType, "getModule")
        if itemModule and tostring(itemModule) ~= "" and itemType and tostring(itemType) ~= "" then
            return tostring(itemModule) .. "." .. tostring(itemType)
        end
        if itemType and tostring(itemType) ~= "" then
            return tostring(itemType)
        end
    end

    if type(itemOrFullType) == "table" then
        local tableFullType = itemOrFullType.fullType or itemOrFullType.id
        if tableFullType and tostring(tableFullType) ~= "" then
            return tostring(tableFullType)
        end
    end

    local rawString = tostring(itemOrFullType)
    if rawString ~= "" and rawString ~= "nil" and string.find(rawString, "%.") then
        return rawString
    end

    return nil
end

local function isLiveItem(itemOrFullType)
    if itemOrFullType == nil or type(itemOrFullType) == "string" then
        return false
    end
    return type(ItemAuthority.safeCall) == "function"
        and ItemAuthority.safeCall(itemOrFullType, "getFullType") ~= nil
end

local function buildImmediateHunger(values, preVisibleHunger)
    refreshBindings()
    if type(values) ~= "table" or type(Metabolism.getImmediateHungerDrop) ~= "function" then
        return nil
    end

    local drop = tonumber(Metabolism.getImmediateHungerDrop(values, 1))
    if drop == nil then
        return nil
    end

    local mechanical = math.abs(tonumber(values.hunger) or 0)
    local pre = tonumber(preVisibleHunger) or 0
    return {
        drop = drop,
        preVisibleHunger = pre,
        targetVisibleHunger = math.max(0, pre - drop),
        mechanical = mechanical,
    }
end

local function annotateConsumedValues(values, entry, authoritySource)
    if type(values) ~= "table" then
        return nil
    end

    values.snapshotMode = type(ItemAuthority.getEntrySnapshotMode) == "function"
        and (ItemAuthority.getEntrySnapshotMode(entry) or values.snapshotMode) or values.snapshotMode or "unknown"
    values.entryAction = type(ItemAuthority.getEntryAction) == "function"
        and (ItemAuthority.getEntryAction(entry) or values.entryAction) or values.entryAction or "unknown"
    values.consumeAuthoritySource = authoritySource or values.consumeAuthoritySource
    return values
end

local function resolveSnapshotState(itemOrFullType, hintedFullType, reason)
    local fullType = resolveFullTypeHint(itemOrFullType, hintedFullType)
    if type(fullType) ~= "string" or fullType == "" then
        return nil, nil, nil, nil, nil
    end

    local entry = type(ItemAuthority.getFoodEntry) == "function" and select(1, ItemAuthority.getFoodEntry(fullType)) or nil
    if type(entry) ~= "table" then
        return nil, nil, fullType, nil, nil
    end

    local liveItem = isLiveItem(itemOrFullType) and itemOrFullType or nil
    local snapshotMode = type(ItemAuthority.resolveSnapshotMode) == "function"
        and ItemAuthority.resolveSnapshotMode(liveItem, fullType, entry) or "static"
    local current = liveItem and type(ItemAuthority.readCurrentValuesPrivate) == "function"
        and ItemAuthority.readCurrentValuesPrivate(liveItem, fullType, entry) or nil

    if snapshotMode == "static" then
        local defaults = type(ItemAuthority.getDefaultValues) == "function"
            and ItemAuthority.getDefaultValues(fullType, entry) or nil
        return defaults, entry, fullType, snapshotMode, current
    end

    if liveItem and type(ItemAuthority.ensureSnapshot) == "function" then
        local stored, _, ensuredFullType, ensuredMode, ensuredCurrent = ItemAuthority.ensureSnapshot(liveItem, reason or "consume", fullType)
        return stored, entry, ensuredFullType or fullType, ensuredMode or snapshotMode, ensuredCurrent or current
    end

    if snapshotMode ~= "static" then
        return nil, entry, fullType, snapshotMode, nil
    end

    return nil, entry, fullType, snapshotMode, current
end

local function buildRemainingSnapshot(itemOrFullType, totalSnapshot, current)
    if type(totalSnapshot) ~= "table" then
        return nil
    end

    if not isLiveItem(itemOrFullType) then
        return totalSnapshot
    end

    local remainingFraction = type(ItemAuthority.resolveRemainingFraction) == "function"
        and ItemAuthority.resolveRemainingFraction(itemOrFullType, current, totalSnapshot) or 1
    if type(ItemAuthority.buildAppliedSnapshot) == "function" then
        return ItemAuthority.buildAppliedSnapshot(totalSnapshot, remainingFraction)
    end
    return totalSnapshot
end

local function scaleSnapshotForConsume(itemOrFullType, snapshot, fraction, entry, authoritySource)
    if type(snapshot) ~= "table" or type(ItemAuthority.scaleConsumedSnapshot) ~= "function" then
        return nil
    end

    local nutritionMultiplier = type(ItemAuthority.getBurntNutritionMultiplier) == "function"
        and ItemAuthority.getBurntNutritionMultiplier(itemOrFullType) or 1
    local values = ItemAuthority.scaleConsumedSnapshot(snapshot, fraction, nutritionMultiplier)
    return annotateConsumedValues(values, entry, authoritySource)
end

function ItemAuthority.resolveGameplayConsumeAuthoritySource(itemOrFullType, hintedFullType)
    local totalSnapshot, _, _, snapshotMode = resolveSnapshotState(itemOrFullType, hintedFullType, "consume-authority")
    if type(totalSnapshot) ~= "table" then
        return nil, nil, resolveFullTypeHint(itemOrFullType, hintedFullType)
    end

    local fullType = tostring(totalSnapshot.fullType or resolveFullTypeHint(itemOrFullType, hintedFullType) or "")
    local entry = type(ItemAuthority.getFoodEntry) == "function" and select(1, ItemAuthority.getFoodEntry(fullType)) or nil
    local authoritySource = snapshotMode == "static"
        and resolveStaticAuthoritySource(totalSnapshot, fullType, entry) or "computed"
    return authoritySource, entry, fullType
end

function ItemAuthority.resolveGameplayAuthoredConsumedValues(itemOrFullType, fraction, hintedFullType)
    local totalSnapshot, entry, fullType, snapshotMode, current = resolveSnapshotState(itemOrFullType, hintedFullType, "authored-consume")
    if snapshotMode ~= "static" then
        return nil
    end

    local remainingSnapshot = buildRemainingSnapshot(itemOrFullType, totalSnapshot, current)
    local authoritySource = resolveStaticAuthoritySource(totalSnapshot, fullType, entry)
    return scaleSnapshotForConsume(itemOrFullType, remainingSnapshot, fraction, entry, authoritySource)
end

function ItemAuthority.resolveGameplayComputedConsumedValues(itemOrFullType, fraction, hintedFullType)
    local totalSnapshot, entry, _, snapshotMode, current = resolveSnapshotState(itemOrFullType, hintedFullType, "computed-consume")
    if snapshotMode ~= "composed" and snapshotMode ~= "fluid" then
        return nil
    end

    local remainingSnapshot = buildRemainingSnapshot(itemOrFullType, totalSnapshot, current)
    return scaleSnapshotForConsume(itemOrFullType, remainingSnapshot, fraction, entry, "computed")
end

function ItemAuthority.resolveGameplayConsumedValues(itemOrFullType, fraction, hintedFullType)
    local consumedFraction = type(ItemAuthority.clamp01) == "function"
        and ItemAuthority.clamp01(fraction or 0) or 0
    if consumedFraction <= CONSUME_EPSILON then
        return nil
    end

    local totalSnapshot, entry, fullType, snapshotMode, current = resolveSnapshotState(itemOrFullType, hintedFullType, "consume")
    if type(totalSnapshot) ~= "table" then
        return nil
    end

    local remainingSnapshot = buildRemainingSnapshot(itemOrFullType, totalSnapshot, current)
    local authoritySource = snapshotMode == "static"
        and resolveStaticAuthoritySource(totalSnapshot, fullType, entry) or "computed"
    return scaleSnapshotForConsume(itemOrFullType, remainingSnapshot, consumedFraction, entry, authoritySource)
end

function ItemAuthority.resolveGameplayConsumeContext(itemOrFullType, fraction, preVisibleHunger, hintedFullType)
    refreshBindings()
    local values = ItemAuthority.resolveGameplayConsumedValues(itemOrFullType, fraction, hintedFullType)
    if type(values) ~= "table" then
        return nil
    end

    local kcal = tonumber(values.kcal) or 0
    local carbs = tonumber(values.carbs) or 0
    local fats = tonumber(values.fats) or 0
    local proteins = tonumber(values.proteins) or 0
    local hunger = math.abs(tonumber(values.hunger) or 0)
    if kcal <= CONSUME_EPSILON
        and carbs <= CONSUME_EPSILON
        and fats <= CONSUME_EPSILON
        and proteins <= CONSUME_EPSILON
        and hunger <= CONSUME_EPSILON
    then
        return {
            skip = true,
            reason = "no-meaningful-nutrition",
            source = tostring(values.consumeAuthoritySource or "unknown"),
        }
    end

    return {
        values = values,
        source = tostring(values.consumeAuthoritySource or "unknown"),
        immediateHunger = buildImmediateHunger(values, preVisibleHunger),
    }
end

function ItemAuthority.resolveAuthoredConsumedValues(itemOrFullType, fraction, hintedFullType)
    return ItemAuthority.resolveGameplayAuthoredConsumedValues(itemOrFullType, fraction, hintedFullType)
end

function ItemAuthority.getConsumedValues(item, fraction, hintedFullType)
    return ItemAuthority.resolveGameplayConsumedValues(item, fraction, hintedFullType)
end

function ItemAuthority.resolveConsumedPayload(item, fraction, preVisibleHunger, hintedFullType)
    return ItemAuthority.resolveGameplayConsumeContext(item, fraction, preVisibleHunger, hintedFullType)
end

do
    local originalGetDisplayValues = ItemAuthority.getDisplayValues
    function ItemAuthority.getDisplayValues(item)
        local fullType = resolveFullTypeHint(item)
        local entry = fullType and type(ItemAuthority.getFoodEntry) == "function"
            and select(1, ItemAuthority.getFoodEntry(fullType)) or nil
        if item and entry and type(ItemAuthority.resolveDisplaySnapshot) == "function" then
            local applied = select(1, ItemAuthority.resolveDisplaySnapshot(item, fullType, entry))
            if type(applied) == "table" then
                return applied
            end
        end

        if type(originalGetDisplayValues) == "function" then
            return originalGetDisplayValues(item)
        end
        return nil
    end
end

return ItemAuthority
