NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_CoreUtils"

local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
NutritionMakesSense.ItemAuthority = ItemAuthority
local Metabolism = NutritionMakesSense.Metabolism or {}
local CoreUtils = NutritionMakesSense.CoreUtils or {}

-- Consume.lua loads after this file and overrides the public consume/display entry points.
local visitList = CoreUtils.visitList
local CONSUME_EPSILON = ItemAuthority.CONSUME_EPSILON or 0.0001

local function refreshBindings()
    ItemAuthority = NutritionMakesSense.ItemAuthority or ItemAuthority
    NutritionMakesSense.ItemAuthority = ItemAuthority
    Metabolism = NutritionMakesSense.Metabolism or Metabolism
    CoreUtils = NutritionMakesSense.CoreUtils or CoreUtils
    visitList = ItemAuthority.visitList or CoreUtils.visitList
    CONSUME_EPSILON = ItemAuthority.CONSUME_EPSILON or CONSUME_EPSILON
end

local function hasMeaningfulNutrition(snapshot)
    if type(snapshot) ~= "table" then
        return false
    end

    return math.abs(tonumber(snapshot.hunger) or 0) > CONSUME_EPSILON
        or math.abs(tonumber(snapshot.baseHunger) or 0) > CONSUME_EPSILON
        or math.abs(tonumber(snapshot.kcal) or 0) > CONSUME_EPSILON
        or math.abs(tonumber(snapshot.carbs) or 0) > CONSUME_EPSILON
        or math.abs(tonumber(snapshot.fats) or 0) > CONSUME_EPSILON
        or math.abs(tonumber(snapshot.proteins) or 0) > CONSUME_EPSILON
end

local function mergeAuthoredCurrentWithDefaults(current, defaults)
    if type(current) ~= "table" then
        return defaults, false
    end
    if type(defaults) ~= "table" then
        return current, false
    end

    local merged = {}
    local usedFallback = false
    for key, value in pairs(defaults) do
        merged[key] = value
    end
    for key, value in pairs(current) do
        merged[key] = value
    end

    if math.abs(tonumber(merged.kcal) or 0) <= CONSUME_EPSILON then
        merged.kcal = tonumber(defaults.kcal) or 0
        usedFallback = true
    end
    if math.abs(tonumber(merged.carbs) or 0) <= CONSUME_EPSILON then
        merged.carbs = tonumber(defaults.carbs) or 0
        usedFallback = true
    end
    if math.abs(tonumber(merged.fats) or 0) <= CONSUME_EPSILON then
        merged.fats = tonumber(defaults.fats) or 0
        usedFallback = true
    end
    if math.abs(tonumber(merged.proteins) or 0) <= CONSUME_EPSILON then
        merged.proteins = tonumber(defaults.proteins) or 0
        usedFallback = true
    end
    if math.abs(tonumber(merged.baseHunger) or 0) <= CONSUME_EPSILON then
        merged.baseHunger = tonumber(defaults.baseHunger) or tonumber(defaults.hunger) or 0
        usedFallback = true
    end

    return merged, usedFallback
end

function ItemAuthority.resolveAuthoredConsumedValues(itemOrFullType, fraction)
    refreshBindings()
    local entry, fullType = nil, nil
    if type(ItemAuthority.getFoodEntry) == "function" then
        entry, fullType = ItemAuthority.getFoodEntry(itemOrFullType)
    end
    if not entry or not fullType or (type(ItemAuthority.resolveEntrySource) == "function" and ItemAuthority.resolveEntrySource(entry) or nil) ~= "authored" then
        return nil
    end

    local defaults = type(ItemAuthority.getDefaultValues) == "function" and ItemAuthority.getDefaultValues(fullType, entry) or nil
    if not defaults then
        if type(ItemAuthority.warnAuthorityOnce) == "function" then
            ItemAuthority.warnAuthorityOnce(fullType, "authored-consume-defaults-missing")
            local patchSource = entry and entry.patch_source
            local data = NutritionMakesSense.runtimeData
            local valuesByItemId = data and data.valuesByItemId or nil
            local patchValues = patchSource and valuesByItemId and valuesByItemId[tostring(patchSource)] or nil
            local typeValues = fullType and valuesByItemId and valuesByItemId[tostring(fullType)] or nil
            ItemAuthority.warnAuthorityOnce(fullType, string.format(
                "authored-defaults-debug patch=%s patchValues=%s typeValues=%s",
                tostring(patchSource),
                tostring(patchValues ~= nil),
                tostring(typeValues ~= nil)
            ))
        end
        return nil
    end

    local nutritionMultiplier = type(ItemAuthority.getBurntNutritionMultiplier) == "function"
        and ItemAuthority.getBurntNutritionMultiplier(itemOrFullType) or 1
    local scaled = type(ItemAuthority.scaleConsumedSnapshot) == "function"
        and ItemAuthority.scaleConsumedSnapshot(defaults, fraction, nutritionMultiplier) or nil
    if not scaled and type(ItemAuthority.warnAuthorityOnce) == "function" then
        ItemAuthority.warnAuthorityOnce(fullType, "authored-consume-scale-missing")
    end
    return scaled
end

function ItemAuthority.getResolvedNutritionSource(item)
    refreshBindings()
    local entry, fullType = nil, nil
    if type(ItemAuthority.getFoodEntry) == "function" then
        entry, fullType = ItemAuthority.getFoodEntry(item)
    end
    if not entry or not fullType then
        return nil
    end
    local stored = type(ItemAuthority.readStoredSnapshotPrivate) == "function"
        and ItemAuthority.readStoredSnapshotPrivate(item, fullType, entry) or nil
    if type(stored) == "table" then
        local storedSource = tostring(stored.nutritionSource or "")
        if storedSource ~= "" then
            return storedSource
        end
        local storedMode = tostring(stored.snapshotMode or "")
        if storedMode == "composed" or storedMode == "fluid" then
            return "computed"
        end
        return storedMode ~= "" and storedMode or "unknown"
    end
    local source = type(ItemAuthority.resolveEntrySource) == "function" and ItemAuthority.resolveEntrySource(entry) or nil
    local snapshotMode = type(ItemAuthority.resolveSnapshotMode) == "function"
        and ItemAuthority.resolveSnapshotMode(item, fullType, entry) or nil
    if source == "authored" and snapshotMode == "static" and type(ItemAuthority.getStaticFoodValueSource) == "function" then
        return ItemAuthority.getStaticFoodValueSource(fullType, entry)
    end
    return source
end

function ItemAuthority.getItemId(item)
    refreshBindings()
    local safeCall = ItemAuthority.safeCall
    return tonumber(safeCall and (safeCall(item, "getID") or safeCall(item, "getEntityNetID")) or item and item.id or nil)
end

function ItemAuthority.getDisplayValues(item)
    refreshBindings()
    local entry, fullType = nil, nil
    if type(ItemAuthority.getFoodEntry) == "function" then
        entry, fullType = ItemAuthority.getFoodEntry(item)
    end
    if not entry or not fullType then
        return nil
    end

    if type(ItemAuthority.resolveDisplaySnapshot) == "function" then
        local applied = select(1, ItemAuthority.resolveDisplaySnapshot(item, fullType, entry))
        if type(applied) == "table" then
            return applied
        end
    end

    local current = type(ItemAuthority.readCurrentValuesPrivate) == "function"
        and ItemAuthority.readCurrentValuesPrivate(item, fullType, entry) or nil
    if hasMeaningfulNutrition(current) then
        return current
    end
    return type(ItemAuthority.getDefaultValues) == "function"
        and ItemAuthority.getDefaultValues(fullType, entry) or nil
end

function ItemAuthority.getConsumedValues(item, fraction)
    refreshBindings()
    local entry, fullType = nil, nil
    if type(ItemAuthority.getFoodEntry) == "function" then
        entry, fullType = ItemAuthority.getFoodEntry(item)
    end
    if not entry or not fullType then
        return nil
    end

    local source = type(ItemAuthority.resolveEntrySource) == "function" and ItemAuthority.resolveEntrySource(entry) or nil
    if source == "computed" then
        local current = type(ItemAuthority.resolveComputedDisplaySnapshot) == "function"
            and ItemAuthority.resolveComputedDisplaySnapshot(item, fullType, entry, false) or nil
        if not current and type(ItemAuthority.warnAuthorityOnce) == "function" then
            ItemAuthority.warnAuthorityOnce(fullType, "computed-consume-payload-missing")
        end
        if not current then
            return nil
        end
        local multiplier = type(ItemAuthority.getBurntNutritionMultiplier) == "function"
            and ItemAuthority.getBurntNutritionMultiplier(item) or 1
        return type(ItemAuthority.scaleConsumedSnapshot) == "function"
            and ItemAuthority.scaleConsumedSnapshot(current, fraction, multiplier) or nil
    end

    return ItemAuthority.resolveAuthoredConsumedValues(item, fraction)
end

function ItemAuthority.resolveConsumedPayload(item, fraction, preVisibleHunger)
    refreshBindings()
    local consumedFraction = type(ItemAuthority.clamp01) == "function" and ItemAuthority.clamp01(fraction or 0) or 0
    if consumedFraction <= CONSUME_EPSILON then
        return nil
    end

    local values = ItemAuthority.getConsumedValues(item, consumedFraction)
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
        and hunger <= CONSUME_EPSILON then
        return nil
    end

    local immediate = nil
    if type(Metabolism.getImmediateHungerDrop) == "function" then
        local drop = tonumber(Metabolism.getImmediateHungerDrop(values, 1))
        if drop ~= nil then
            local pre = tonumber(preVisibleHunger) or 0
            immediate = {
                drop = drop,
                preVisibleHunger = pre,
                targetVisibleHunger = math.max(0, pre - drop),
                mechanical = hunger,
            }
        end
    end

    return {
        values = values,
        source = ItemAuthority.getResolvedNutritionSource(item) or "authored",
        immediateHunger = immediate,
    }
end

function ItemAuthority.measureConsumedPayload(item, beforeValues, afterValues)
    refreshBindings()
    if type(beforeValues) ~= "table" then
        return nil
    end

    local after = type(afterValues) == "table" and afterValues or nil
    local multiplier = type(ItemAuthority.getBurntNutritionMultiplier) == "function"
        and ItemAuthority.getBurntNutritionMultiplier(item) or 1
    local measured = {
        hunger = math.max(0, (tonumber(beforeValues.hunger) or 0) - (tonumber(after and after.hunger) or 0)),
        baseHunger = tonumber(beforeValues.baseHunger) or tonumber(beforeValues.hunger) or 0,
        kcal = math.max(0, (tonumber(beforeValues.kcal) or 0) - (tonumber(after and after.kcal) or 0)) * multiplier,
        carbs = math.max(0, (tonumber(beforeValues.carbs) or 0) - (tonumber(after and after.carbs) or 0)) * multiplier,
        fats = math.max(0, (tonumber(beforeValues.fats) or 0) - (tonumber(after and after.fats) or 0)) * multiplier,
        proteins = math.max(0, (tonumber(beforeValues.proteins) or 0) - (tonumber(after and after.proteins) or 0)) * multiplier,
    }

    if measured.kcal <= CONSUME_EPSILON
        and measured.carbs <= CONSUME_EPSILON
        and measured.fats <= CONSUME_EPSILON
        and measured.proteins <= CONSUME_EPSILON
        and math.abs(measured.hunger) <= CONSUME_EPSILON then
        return nil
    end

    return measured
end

function ItemAuthority.getDebugSnapshot(item)
    refreshBindings()
    local entry, fullType = nil, nil
    if type(ItemAuthority.getFoodEntry) == "function" then
        entry, fullType = ItemAuthority.getFoodEntry(item)
    end
    if not entry or not fullType then
        return nil
    end

    local applied, currentResolved, storedResolved, resolvedMode = nil, nil, nil, nil
    if type(ItemAuthority.resolveDisplaySnapshot) == "function" then
        applied, currentResolved, storedResolved, resolvedMode = ItemAuthority.resolveDisplaySnapshot(item, fullType, entry)
    end
    local expectedMode = type(ItemAuthority.resolveSnapshotMode) == "function"
        and ItemAuthority.resolveSnapshotMode(item, fullType, entry) or nil
    local current = currentResolved or (type(ItemAuthority.readCurrentValuesPrivate) == "function"
        and ItemAuthority.readCurrentValuesPrivate(item, fullType, entry) or nil)
    local stored = storedResolved or (type(ItemAuthority.readStoredSnapshotPrivate) == "function"
        and ItemAuthority.readStoredSnapshotPrivate(item, fullType, entry) or nil)

    return {
        fullType = fullType,
        source = type(ItemAuthority.resolveEntrySource) == "function" and ItemAuthority.resolveEntrySource(entry) or nil,
        snapshotMode = type(ItemAuthority.getEntrySnapshotMode) == "function"
            and ItemAuthority.getEntrySnapshotMode(entry) or nil,
        entryAction = type(ItemAuthority.getEntryAction) == "function"
            and ItemAuthority.getEntryAction(entry) or nil,
        authorityTarget = entry.authority_target or nil,
        patchSource = entry.patch_source or nil,
        expectedMode = expectedMode,
        resolvedMode = resolvedMode,
        display = ItemAuthority.getDisplayValues(item),
        applied = applied,
        current = current,
        stored = stored,
    }
end

function ItemAuthority.sumConsumedPayload(items)
    refreshBindings()
    if not items then
        return nil
    end

    if type(visitList) ~= "function" then
        error("[NMS_BOOT_HARD_FAIL] ItemAuthority Query missing visitList")
    end

    local total = {
        hunger = 0,
        baseHunger = 0,
        kcal = 0,
        carbs = 0,
        fats = 0,
        proteins = 0,
    }
    local hadAny = false

    visitList(items, function(item)
        local values = ItemAuthority.getConsumedValues(item, 1)
        if type(values) == "table" then
            total.hunger = total.hunger + (tonumber(values.hunger) or 0)
            total.baseHunger = total.baseHunger + (tonumber(values.baseHunger) or tonumber(values.hunger) or 0)
            total.kcal = total.kcal + (tonumber(values.kcal) or 0)
            total.carbs = total.carbs + (tonumber(values.carbs) or 0)
            total.fats = total.fats + (tonumber(values.fats) or 0)
            total.proteins = total.proteins + (tonumber(values.proteins) or 0)
            hadAny = true
        end
    end)

    if not hadAny then
        return nil
    end
    return total
end

return ItemAuthority
