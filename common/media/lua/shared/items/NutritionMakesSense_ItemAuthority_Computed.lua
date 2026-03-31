NutritionMakesSense = NutritionMakesSense or {}

local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
NutritionMakesSense.ItemAuthority = ItemAuthority

local log = ItemAuthority.log
local EPSILON = ItemAuthority.EPSILON
local clamp01 = ItemAuthority.clamp01
local getFoodEntry = ItemAuthority.getFoodEntry
local resolveEntrySource = ItemAuthority.resolveEntrySource
local readCurrentValues = ItemAuthority.readCurrentValuesPrivate
local readStoredSnapshot = ItemAuthority.readStoredSnapshotPrivate
local normalizeSnapshot = ItemAuthority.normalizeSnapshot
local writeStoredSnapshot = ItemAuthority.writeStoredSnapshot
local resolveRemainingFraction = ItemAuthority.resolveRemainingFraction
local applySnapshot = ItemAuthority.applySnapshot
local buildAppliedSnapshot = ItemAuthority.buildAppliedSnapshot
local addPayloadSnapshots = ItemAuthority.addPayloadSnapshots
local visitList = ItemAuthority.visitList

local function refreshBindings()
    ItemAuthority = NutritionMakesSense.ItemAuthority or ItemAuthority
    NutritionMakesSense.ItemAuthority = ItemAuthority
    log = ItemAuthority.log
    EPSILON = ItemAuthority.EPSILON
    clamp01 = ItemAuthority.clamp01
    getFoodEntry = ItemAuthority.getFoodEntry
    resolveEntrySource = ItemAuthority.resolveEntrySource
    readCurrentValues = ItemAuthority.readCurrentValuesPrivate
    readStoredSnapshot = ItemAuthority.readStoredSnapshotPrivate
    normalizeSnapshot = ItemAuthority.normalizeSnapshot
    writeStoredSnapshot = ItemAuthority.writeStoredSnapshot
    resolveRemainingFraction = ItemAuthority.resolveRemainingFraction
    applySnapshot = ItemAuthority.applySnapshot
    buildAppliedSnapshot = ItemAuthority.buildAppliedSnapshot
    addPayloadSnapshots = ItemAuthority.addPayloadSnapshots
    visitList = ItemAuthority.visitList
end

local function isDynamicPayloadEntry(entry)
    if type(entry) ~= "table" then
        return false
    end

    if resolveEntrySource(entry) == "computed" then
        return true
    end

    local semanticClass = tostring(entry.semantic_class or entry.semanticClass or "")
    return semanticClass == "runtime_composed_output"
end

local function notifySeedEvent(reason, item, values)
    local DebugSupport = NutritionMakesSense.DebugSupport
    if DebugSupport and type(DebugSupport.noteSeedEvent) == "function" then
        DebugSupport.noteSeedEvent({
            reason = reason,
            item = item,
            kcal = values.kcal,
            carbs = values.carbs,
            fats = values.fats,
            proteins = values.proteins,
        })
    end
end

local function getComputedEntry(item)
    local entry, fullType = getFoodEntry(item)
    if not entry or not fullType then
        return nil, nil
    end
    if not isDynamicPayloadEntry(entry) then
        return nil, nil
    end
    return fullType, entry
end

local function seedComputedPayload(item, values, reason)
    refreshBindings()
    local fullType, entry = getComputedEntry(item)
    if not fullType or not entry or type(values) ~= "table" then
        return nil
    end

    local total = normalizeSnapshot(fullType, entry, {
        fullType = fullType,
        nutritionSource = "computed",
        snapshotMode = "composed",
        sourceFullType = values.sourceFullType or fullType,
        authorityTarget = values.authorityTarget or entry.authority_target or fullType,
        provenance = values.provenance or "computed",
        seedReason = values.seedReason or reason or "computed-seed",
        hunger = values.hunger,
        baseHunger = values.baseHunger,
        kcal = values.kcal,
        carbs = values.carbs,
        fats = values.fats,
        proteins = values.proteins,
        fluidPayloadId = values.fluidPayloadId,
        fluidCapacity = values.fluidCapacity,
        fluidAmount = values.fluidAmount,
    })
    if not total then
        return nil
    end

    if not writeStoredSnapshot(item, total) then
        return nil
    end

    local current = readCurrentValues(item, fullType, entry)
    local remainingFraction = resolveRemainingFraction(item, current, total)
    applySnapshot(item, buildAppliedSnapshot(total, remainingFraction))

    notifySeedEvent(reason or "computed-seed", fullType, total)

    log(string.format(
        "[ITEM_AUTHORITY_COMPUTED_SEED] reason=%s item=%s kcal=%.1f carbs=%.1f fats=%.1f proteins=%.1f",
        tostring(reason or "computed-seed"),
        tostring(fullType),
        tonumber(total.kcal or 0),
        tonumber(total.carbs or 0),
        tonumber(total.fats or 0),
        tonumber(total.proteins or 0)
    ))
    return total
end

local function accumulateComputedPayload(item, addedValues, reason)
    refreshBindings()
    local fullType, entry = getComputedEntry(item)
    if not fullType or not entry or type(addedValues) ~= "table" then
        return nil
    end

    local stored = readStoredSnapshot(item, fullType, entry)
    local base = stored or normalizeSnapshot(fullType, entry, {
        fullType = fullType,
        nutritionSource = "computed",
        snapshotMode = "composed",
        sourceFullType = fullType,
        provenance = "computed",
        seedReason = reason or "computed-accumulate",
        hunger = 0,
        baseHunger = 0,
        kcal = 0,
        carbs = 0,
        fats = 0,
        proteins = 0,
    })
    local combined = addPayloadSnapshots(fullType, entry, base, {
        provenance = "computed",
        seedReason = reason or "computed-accumulate",
        hunger = addedValues.hunger,
        baseHunger = addedValues.baseHunger,
        kcal = addedValues.kcal,
        carbs = addedValues.carbs,
        fats = addedValues.fats,
        proteins = addedValues.proteins,
        fluidPayloadId = addedValues.fluidPayloadId,
        fluidCapacity = addedValues.fluidCapacity,
        fluidAmount = addedValues.fluidAmount,
    })
    if not combined then
        return nil
    end

    if not writeStoredSnapshot(item, combined) then
        return nil
    end

    local current = readCurrentValues(item, fullType, entry)
    local remainingFraction = resolveRemainingFraction(item, current, combined)
    applySnapshot(item, buildAppliedSnapshot(combined, remainingFraction))

    notifySeedEvent(reason or "computed-accumulate", fullType, combined)

    log(string.format(
        "[ITEM_AUTHORITY_COMPUTED_ACCUMULATE] reason=%s item=%s kcal=%.1f carbs=%.1f fats=%.1f proteins=%.1f",
        tostring(reason or "computed-accumulate"),
        tostring(fullType),
        tonumber(combined.kcal or 0),
        tonumber(combined.carbs or 0),
        tonumber(combined.fats or 0),
        tonumber(combined.proteins or 0)
    ))
    return combined
end

local function seedComputedOutputs(createdItems, payloadValues, reason)
    refreshBindings()
    if not createdItems or type(payloadValues) ~= "table" then
        return 0
    end

    local targets = {}
    local ratioWeights = {}
    local ratioTotal = 0

    visitList(createdItems, function(item)
        local fullType, entry = getComputedEntry(item)
        if fullType and entry then
            targets[#targets + 1] = {
                item = item,
                fullType = fullType,
                entry = entry,
            }
        end
    end)

    if #targets <= 0 then
        return 0
    end

    if #targets == 1 then
        return seedComputedPayload(targets[1].item, {
            sourceFullType = targets[1].fullType,
            provenance = "computed",
            seedReason = reason or "computed-create",
            hunger = payloadValues.hunger,
            baseHunger = payloadValues.baseHunger,
            kcal = payloadValues.kcal,
            carbs = payloadValues.carbs,
            fats = payloadValues.fats,
            proteins = payloadValues.proteins,
        }, reason) and 1 or 0
    end

    for index, target in ipairs(targets) do
        local current = readCurrentValues(target.item, target.fullType, target.entry)
        local weight = math.max(
            math.abs(tonumber(current and current.kcal) or 0),
            math.abs(tonumber(current and current.carbs) or 0),
            math.abs(tonumber(current and current.fats) or 0),
            math.abs(tonumber(current and current.proteins) or 0),
            math.abs(tonumber(current and current.hunger) or 0)
        )
        if weight <= EPSILON then
            weight = 1
        end
        ratioWeights[index] = weight
        ratioTotal = ratioTotal + weight
    end

    local seeded = 0
    local remainingRatio = 1
    for index, target in ipairs(targets) do
        local ratio = 0
        if index == #targets then
            ratio = remainingRatio
        elseif ratioTotal > EPSILON then
            ratio = clamp01(ratioWeights[index] / ratioTotal)
            remainingRatio = math.max(0, remainingRatio - ratio)
        end

        local scaled = normalizeSnapshot(target.fullType, target.entry, {
            fullType = target.fullType,
            nutritionSource = "computed",
            snapshotMode = "composed",
            sourceFullType = target.fullType,
            provenance = "computed",
            seedReason = reason or "computed-create",
            hunger = (tonumber(payloadValues.hunger) or 0) * ratio,
            baseHunger = (tonumber(payloadValues.baseHunger) or tonumber(payloadValues.hunger) or 0) * ratio,
            kcal = (tonumber(payloadValues.kcal) or 0) * ratio,
            carbs = (tonumber(payloadValues.carbs) or 0) * ratio,
            fats = (tonumber(payloadValues.fats) or 0) * ratio,
            proteins = (tonumber(payloadValues.proteins) or 0) * ratio,
        })
        if scaled and seedComputedPayload(target.item, scaled, reason) then
            seeded = seeded + 1
        end
    end

    return seeded
end

ItemAuthority.seedDynamicPayload = seedComputedPayload
ItemAuthority.accumulateDynamicPayload = accumulateComputedPayload
ItemAuthority.seedDynamicOutputs = seedComputedOutputs

return ItemAuthority
