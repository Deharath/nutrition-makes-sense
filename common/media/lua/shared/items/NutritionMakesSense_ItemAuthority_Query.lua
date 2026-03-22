NutritionMakesSense = NutritionMakesSense or {}

local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
local Metabolism = NutritionMakesSense.Metabolism or {}
local CoreUtils = NutritionMakesSense.CoreUtils or {}

local safeCall = ItemAuthority.safeCall
local getFoodEntry = ItemAuthority.getFoodEntry
local resolveEntrySource = ItemAuthority.resolveEntrySource
local hasVanillaDynamicValues = ItemAuthority.hasVanillaDynamicValues
local readCurrentValues = ItemAuthority.readCurrentValuesPrivate
local readStoredSnapshot = ItemAuthority.readStoredSnapshotPrivate
local resolveComputedDisplaySnapshot = ItemAuthority.resolveComputedDisplaySnapshot
local getDefaultValues = ItemAuthority.getDefaultValues
local scaleConsumedSnapshot = ItemAuthority.scaleConsumedSnapshot
local getBurntNutritionMultiplier = ItemAuthority.getBurntNutritionMultiplier
local visitList = CoreUtils.visitList
local clamp01 = ItemAuthority.clamp01
local CONSUME_EPSILON = 0.0001

function ItemAuthority.getResolvedNutritionSource(item)
    local entry, fullType = getFoodEntry(item)
    if not entry or not fullType then
        return nil
    end
    if resolveEntrySource(entry) == "authored" and hasVanillaDynamicValues(item) then
        return nil
    end
    return resolveEntrySource(entry)
end

function ItemAuthority.getItemId(item)
    return tonumber(safeCall(item, "getID") or safeCall(item, "getEntityNetID") or item and item.id or nil)
end

function ItemAuthority.getDisplayValues(item)
    local entry, fullType = getFoodEntry(item)
    if not entry or not fullType then
        return nil
    end
    if resolveEntrySource(entry) == "computed" then
        return resolveComputedDisplaySnapshot(item, fullType, entry, true)
    end

    return readCurrentValues(item, fullType, entry) or getDefaultValues(fullType, entry)
end

function ItemAuthority.getConsumedValues(item, fraction)
    local entry, fullType = getFoodEntry(item)
    if not entry or not fullType then
        return nil
    end

    local current = nil
    if resolveEntrySource(entry) == "computed" then
        current = resolveComputedDisplaySnapshot(item, fullType, entry, false)
    else
        current = readCurrentValues(item, fullType, entry) or getDefaultValues(fullType, entry)
    end
    if not current then
        return nil
    end
    return scaleConsumedSnapshot(current, fraction, getBurntNutritionMultiplier(item))
end

function ItemAuthority.resolveConsumedPayload(item, fraction, preVisibleHunger)
    local consumedFraction = clamp01(fraction or 0)
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
        source = ItemAuthority.getResolvedNutritionSource(item),
        immediateHunger = immediate,
    }
end

function ItemAuthority.measureConsumedPayload(item, beforeValues, afterValues)
    if type(beforeValues) ~= "table" then
        return nil
    end

    local after = type(afterValues) == "table" and afterValues or nil
    local multiplier = getBurntNutritionMultiplier(item)
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
    local entry, fullType = getFoodEntry(item)
    if not entry or not fullType then
        return nil
    end

    return {
        source = resolveEntrySource(entry),
        display = ItemAuthority.getDisplayValues(item),
        current = readCurrentValues(item, fullType, entry),
        stored = readStoredSnapshot(item, fullType, entry),
    }
end

function ItemAuthority.sumConsumedPayload(items)
    if not items then
        return nil
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
