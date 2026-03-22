NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_Data"
require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_StablePatcher"
require "NutritionMakesSense_CoreUtils"

local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
NutritionMakesSense.ItemAuthority = ItemAuthority

local CoreUtils = NutritionMakesSense.CoreUtils or {}

local SNAPSHOT_KEY = "NutritionMakesSenseItemAuthority"
local SNAPSHOT_VERSION_KEY = "NutritionMakesSenseItemAuthorityVersion"
local SNAPSHOT_VERSION = 6
local EPSILON = 0.001
local HUNGER_TO_RUNTIME_SCALE = 0.01
local TRACKED_SOURCES = {
    authored = true,
    computed = true,
}
local authorityWarnings = {}

local function log(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(msg)
    else
        print("[NutritionMakesSense] " .. tostring(msg))
    end
end

local safeCall = CoreUtils.safeCall
local tryMethod = CoreUtils.tryMethod
local rawLookup = CoreUtils.rawLookup
local clamp01 = CoreUtils.clamp01
local numbersClose = function(a, b)
    return CoreUtils.numbersClose(a, b, EPSILON)
end

local function resolveEntrySource(entry)
    if type(entry) ~= "table" then
        return nil
    end
    if type(entry.nutrition_source) == "string" and entry.nutrition_source ~= "" then
        return entry.nutrition_source
    end
    return nil
end

local function hasVanillaDynamicValues(item)
    if safeCall(item, "isCustomName") == true then
        return true
    end
    if safeCall(item, "isCustomWeight") == true then
        return true
    end
    local spices = safeCall(item, "getSpices")
    if spices and safeCall(spices, "size") and safeCall(spices, "size") > 0 then
        return true
    end
    if safeCall(item, "haveExtraItems") == true then
        return true
    end
    return false
end

local function isTrackedSource(nutritionSource)
    return TRACKED_SOURCES[nutritionSource] == true
end

local function getRuntimeData()
    if NutritionMakesSense.runtimeData then
        return NutritionMakesSense.runtimeData
    end

    local ok, data = pcall(NutritionMakesSense.Data.loadRuntimeData, false)
    if ok then
        return data
    end
    return nil
end

local function getModData(item)
    local modData = safeCall(item, "getModData")
    if modData ~= nil then
        return modData
    end
    return nil
end

local resolveFullType = CoreUtils.resolveItemFullType

local function warnAuthorityOnce(fullType, detail)
    local key = tostring(fullType or "unknown") .. ":" .. tostring(detail or "warning")
    if authorityWarnings[key] then
        return
    end
    authorityWarnings[key] = true
    log(string.format(
        "[ITEM_AUTHORITY_WARN] item=%s detail=%s",
        tostring(fullType or "unknown"),
        tostring(detail or "warning")
    ))
end

local function normalizeSnapshot(fullType, entry, snapshot)
    if type(snapshot) ~= "table" then
        return nil
    end

    local resolvedFullType = tostring(snapshot.fullType or fullType or "")
    if resolvedFullType == "" then
        return nil
    end

    local nutritionSource = tostring(snapshot.nutritionSource or snapshot.nutrition_source or resolveEntrySource(entry) or "")
    if not isTrackedSource(nutritionSource) then
        return nil
    end

    local baseHunger = tonumber(snapshot.baseHunger)
    local hunger = tonumber(snapshot.hunger) or 0
    if baseHunger == nil then
        baseHunger = hunger
    end

    local normalized = {
        version = SNAPSHOT_VERSION,
        fullType = resolvedFullType,
        sourceFullType = tostring(snapshot.sourceFullType or resolvedFullType),
        nutritionSource = nutritionSource,
        nutrition_source = nutritionSource,
        authorityTarget = tostring(snapshot.authorityTarget or (entry and entry.authority_target) or resolvedFullType),
        provenance = tostring(snapshot.provenance or ""),
        seedReason = tostring(snapshot.seedReason or ""),
        hunger = hunger,
        baseHunger = baseHunger,
        kcal = tonumber(snapshot.kcal) or 0,
        carbs = tonumber(snapshot.carbs) or 0,
        fats = tonumber(snapshot.fats) or 0,
        proteins = tonumber(snapshot.proteins) or 0,
        remainingFraction = snapshot.remainingFraction ~= nil and clamp01(snapshot.remainingFraction) or nil,
        fluidPayloadId = snapshot.fluidPayloadId and tostring(snapshot.fluidPayloadId) or nil,
        fluidCapacity = tonumber(snapshot.fluidCapacity) or nil,
        fluidAmount = tonumber(snapshot.fluidAmount) or nil,
    }

    return normalized
end

local function snapshotHasNutrition(snapshot)
    if not snapshot then
        return false
    end

    return math.abs(tonumber(snapshot.hunger) or 0) > EPSILON
        or math.abs(tonumber(snapshot.baseHunger) or 0) > EPSILON
        or math.abs(tonumber(snapshot.kcal) or 0) > EPSILON
        or math.abs(tonumber(snapshot.carbs) or 0) > EPSILON
        or math.abs(tonumber(snapshot.fats) or 0) > EPSILON
        or math.abs(tonumber(snapshot.proteins) or 0) > EPSILON
        or snapshot.remainingFraction ~= nil
        or snapshot.fluidAmount ~= nil
end

local function snapshotsMatch(a, b)
    if not a or not b then
        return false
    end

    return numbersClose(a.hunger, b.hunger)
        and numbersClose(a.baseHunger, b.baseHunger)
        and numbersClose(a.kcal, b.kcal)
        and numbersClose(a.carbs, b.carbs)
        and numbersClose(a.fats, b.fats)
        and numbersClose(a.proteins, b.proteins)
        and numbersClose(a.remainingFraction, b.remainingFraction)
        and numbersClose(a.fluidAmount, b.fluidAmount)
end

local function getFoodEntry(itemOrFullType)
    local fullType = resolveFullType(itemOrFullType)
    if type(fullType) ~= "string" or fullType == "" then
        return nil, nil
    end

    local data = getRuntimeData()
    local entry = data and data.runtimeEntriesByItemId and data.runtimeEntriesByItemId[fullType] or nil
    if entry and isTrackedSource(resolveEntrySource(entry)) then
        return entry, fullType
    end

    return nil, fullType
end

local function getFluidContainer(item)
    return safeCall(item, "getFluidContainer")
end

local function getFluidPropertySource(fluidContainer)
    local properties = safeCall(fluidContainer, "getProperties")
    if properties then
        return properties
    end
    return safeCall(fluidContainer, "getPrimaryFluid")
end

local function getFluidPayloadId(fluidContainer)
    local primaryFluid = safeCall(fluidContainer, "getPrimaryFluid")
    if not primaryFluid then
        return nil
    end

    local fluidType = safeCall(primaryFluid, "getFluidTypeString")
    if fluidType and fluidType ~= "" then
        return tostring(fluidType)
    end

    local fluidName = safeCall(primaryFluid, "getName")
    if fluidName and fluidName ~= "" then
        return tostring(fluidName)
    end

    return nil
end

local function getFluidCapacity(fluidContainer)
    return tonumber(safeCall(fluidContainer, "getCapacity") or 0) or nil
end

local function getFluidAmount(fluidContainer)
    return tonumber(safeCall(fluidContainer, "getAmount") or 0) or nil
end

local function getFluidRemainingFraction(fluidContainer)
    local filledRatio = tonumber(safeCall(fluidContainer, "getFilledRatio"))
    if filledRatio ~= nil then
        return clamp01(filledRatio)
    end

    local amount = getFluidAmount(fluidContainer)
    local capacity = getFluidCapacity(fluidContainer)
    if amount ~= nil and capacity ~= nil and capacity > 0 then
        return clamp01(amount / capacity)
    end

    return nil
end

local function readFluidCurrentValues(item, fullType, entry)
    local fluidContainer = getFluidContainer(item)
    if not fluidContainer then
        return nil
    end

    local properties = getFluidPropertySource(fluidContainer)
    if not properties then
        return nil
    end

    local remainingFraction = getFluidRemainingFraction(fluidContainer)
    if remainingFraction == nil then
        return nil
    end

    local totalHunger = tonumber(safeCall(properties, "getHungerChange") or 0) or 0
    local totalKcal = tonumber(safeCall(properties, "getCalories") or 0) or 0
    local totalCarbs = tonumber(safeCall(properties, "getCarbohydrates") or 0) or 0
    local totalFats = tonumber(safeCall(properties, "getLipids") or 0) or 0
    local totalProteins = tonumber(safeCall(properties, "getProteins") or 0) or 0

    return normalizeSnapshot(fullType, entry, {
        fullType = fullType,
        nutritionSource = resolveEntrySource(entry),
        sourceFullType = fullType,
        provenance = "live",
        seedReason = "current-fluid",
        hunger = totalHunger * remainingFraction,
        baseHunger = totalHunger,
        kcal = totalKcal * remainingFraction,
        carbs = totalCarbs * remainingFraction,
        fats = totalFats * remainingFraction,
        proteins = totalProteins * remainingFraction,
        remainingFraction = remainingFraction,
        fluidPayloadId = getFluidPayloadId(fluidContainer),
        fluidCapacity = getFluidCapacity(fluidContainer),
        fluidAmount = getFluidAmount(fluidContainer),
    })
end

local function readCurrentValues(item, fullType, entry)
    if not item then
        return nil
    end

    local fluidSnapshot = readFluidCurrentValues(item, fullType, entry)
    if snapshotHasNutrition(fluidSnapshot) then
        return fluidSnapshot
    end

    local hunger = safeCall(item, "getHungChange")
    if hunger == nil then
        hunger = safeCall(item, "getHungerChange")
    end

    return normalizeSnapshot(fullType, entry, {
        fullType = fullType,
        nutritionSource = resolveEntrySource(entry),
        sourceFullType = fullType,
        provenance = "live",
        seedReason = "current-values",
        hunger = tonumber(hunger) or 0,
        baseHunger = tonumber(safeCall(item, "getBaseHunger") or hunger) or 0,
        kcal = tonumber(safeCall(item, "getCalories") or 0) or 0,
        carbs = tonumber(safeCall(item, "getCarbohydrates") or 0) or 0,
        fats = tonumber(safeCall(item, "getLipids") or 0) or 0,
        proteins = tonumber(safeCall(item, "getProteins") or 0) or 0,
    })
end

local function getDefaultValues(fullType, entry)
    local data = getRuntimeData()
    local patchSource = (entry and entry.patch_source) or fullType
    local values = data and data.valuesByItemId and data.valuesByItemId[patchSource] or nil
    if not values then
        return nil
    end

    local runtimeHunger = (tonumber(values.hunger) or 0) * HUNGER_TO_RUNTIME_SCALE
    return normalizeSnapshot(fullType, entry, {
        fullType = fullType,
        nutritionSource = "authored",
        sourceFullType = patchSource,
        provenance = "authored",
        seedReason = "defaults",
        hunger = runtimeHunger,
        baseHunger = runtimeHunger,
        kcal = tonumber(values.kcal) or 0,
        carbs = tonumber(values.carbs) or 0,
        fats = tonumber(values.fats) or 0,
        proteins = tonumber(values.proteins) or 0,
    })
end

local function readStoredSnapshot(item, fullType, entry)
    if not item or not entry or resolveEntrySource(entry) ~= "computed" then
        return nil
    end

    local modData = getModData(item)
    if not modData then
        return nil
    end

    local stored = rawLookup(modData, SNAPSHOT_KEY)
    if type(stored) ~= "table" then
        return nil
    end

    local versionTag = tostring(rawLookup(modData, SNAPSHOT_VERSION_KEY) or "")
    if versionTag ~= tostring(SNAPSHOT_VERSION) then
        return nil
    end

    local normalized = normalizeSnapshot(fullType, entry, stored)
    if not normalized then
        return nil
    end
    if tonumber(normalized.version) ~= SNAPSHOT_VERSION then
        return nil
    end
    if tostring(normalized.fullType) ~= tostring(fullType) then
        return nil
    end
    if tostring(normalized.nutritionSource) ~= "computed" then
        return nil
    end

    return normalized
end

local writeStoredSnapshot

local function bootstrapComputedSnapshot(item, fullType, entry, reason)
    if not item or not entry or resolveEntrySource(entry) ~= "computed" then
        return nil
    end

    local current = readCurrentValues(item, fullType, entry)
    if not snapshotHasNutrition(current) then
        return nil
    end

    local total = normalizeSnapshot(fullType, entry, {
        fullType = fullType,
        nutritionSource = "computed",
        sourceFullType = fullType,
        authorityTarget = entry.authority_target or fullType,
        provenance = "live-bootstrap",
        seedReason = reason or "computed-bootstrap-current",
        hunger = current.hunger,
        baseHunger = current.baseHunger,
        kcal = current.kcal,
        carbs = current.carbs,
        fats = current.fats,
        proteins = current.proteins,
        fluidPayloadId = current.fluidPayloadId,
        fluidCapacity = current.fluidCapacity,
        fluidAmount = current.fluidAmount,
    })
    if not total then
        return nil
    end

    if not writeStoredSnapshot(item, total) then
        return nil
    end

    log(string.format(
        "[ITEM_AUTHORITY_COMPUTED_BOOTSTRAP] reason=%s item=%s kcal=%.1f carbs=%.1f fats=%.1f proteins=%.1f",
        tostring(reason or "computed-bootstrap-current"),
        tostring(fullType),
        tonumber(total.kcal or 0),
        tonumber(total.carbs or 0),
        tonumber(total.fats or 0),
        tonumber(total.proteins or 0)
    ))
    return total
end

local resolveRemainingFraction
local buildAppliedSnapshot

local function resolveComputedDisplaySnapshot(item, fullType, entry, allowCurrentFallback)
    local current = readCurrentValues(item, fullType, entry)
    local stored = readStoredSnapshot(item, fullType, entry)
    if not stored then
        stored = bootstrapComputedSnapshot(item, fullType, entry, "computed-display-bootstrap")
    end
    if not stored then
        warnAuthorityOnce(fullType, "computed-payload-missing")
        if allowCurrentFallback then
            return current
        end
        return nil
    end

    local remainingFraction = resolveRemainingFraction(item, current, stored)
    return buildAppliedSnapshot(stored, remainingFraction)
end

writeStoredSnapshot = function(item, snapshot)
    local modData = getModData(item)
    if not modData or not snapshot then
        return false
    end

    modData[SNAPSHOT_KEY] = snapshot
    modData[SNAPSHOT_VERSION_KEY] = tostring(SNAPSHOT_VERSION)
    return true
end

local function clearStoredSnapshot(item)
    local modData = getModData(item)
    if not modData then
        return false
    end

    local hadSnapshot = rawLookup(modData, SNAPSHOT_KEY) ~= nil or rawLookup(modData, SNAPSHOT_VERSION_KEY) ~= nil
    modData[SNAPSHOT_KEY] = nil
    modData[SNAPSHOT_VERSION_KEY] = nil
    return hadSnapshot
end

resolveRemainingFraction = function(item, current, total)
    if current and current.remainingFraction ~= nil then
        return clamp01(current.remainingFraction)
    end

    local currentUses = tonumber(safeCall(item, "getCurrentUses"))
    local maxUses = tonumber(safeCall(item, "getMaxUses"))
    if currentUses ~= nil and maxUses ~= nil and maxUses > 0 then
        return clamp01(currentUses / maxUses)
    end

    local currentHunger = tonumber(current and current.hunger)
    local baseHunger = tonumber(current and current.baseHunger)
    if currentHunger ~= nil and baseHunger ~= nil and math.abs(baseHunger) > EPSILON then
        return clamp01(math.abs(currentHunger / baseHunger))
    end

    local function tryRatio(currentValue, totalValue)
        local currentNumber = tonumber(currentValue)
        local totalNumber = tonumber(totalValue)
        if currentNumber == nil or totalNumber == nil or math.abs(totalNumber) <= EPSILON then
            return nil
        end
        return clamp01(math.abs(currentNumber / totalNumber))
    end

    if current and total then
        local ratio = tryRatio(current.kcal, total.kcal)
            or tryRatio(current.carbs, total.carbs)
            or tryRatio(current.fats, total.fats)
            or tryRatio(current.proteins, total.proteins)
        if ratio ~= nil then
            return ratio
        end
    end

    return 1.0
end

buildAppliedSnapshot = function(totalSnapshot, fraction)
    if not totalSnapshot then
        return nil
    end

    local remainingFraction = clamp01(fraction or 1)
    local fullFluidAmount = tonumber(totalSnapshot.fluidAmount)
    if fullFluidAmount == nil then
        fullFluidAmount = tonumber(totalSnapshot.fluidCapacity)
    end

    return normalizeSnapshot(totalSnapshot.fullType, {
        nutrition_source = totalSnapshot.nutritionSource,
        authority_target = totalSnapshot.authorityTarget,
    }, {
        fullType = totalSnapshot.fullType,
        nutritionSource = totalSnapshot.nutritionSource,
        sourceFullType = totalSnapshot.sourceFullType or totalSnapshot.fullType,
        authorityTarget = totalSnapshot.authorityTarget,
        provenance = totalSnapshot.provenance,
        seedReason = totalSnapshot.seedReason,
        hunger = (tonumber(totalSnapshot.hunger) or 0) * remainingFraction,
        baseHunger = tonumber(totalSnapshot.baseHunger) or tonumber(totalSnapshot.hunger) or 0,
        kcal = (tonumber(totalSnapshot.kcal) or 0) * remainingFraction,
        carbs = (tonumber(totalSnapshot.carbs) or 0) * remainingFraction,
        fats = (tonumber(totalSnapshot.fats) or 0) * remainingFraction,
        proteins = (tonumber(totalSnapshot.proteins) or 0) * remainingFraction,
        remainingFraction = remainingFraction,
        fluidPayloadId = totalSnapshot.fluidPayloadId,
        fluidCapacity = totalSnapshot.fluidCapacity,
        fluidAmount = fullFluidAmount and (fullFluidAmount * remainingFraction) or nil,
    })
end

local function scaleConsumedSnapshot(snapshot, fraction, nutritionMultiplier)
    if not snapshot then
        return nil
    end

    local ratio = clamp01(fraction or 0)
    local multiplier = tonumber(nutritionMultiplier) or 1
    return normalizeSnapshot(snapshot.fullType, {
        nutrition_source = snapshot.nutritionSource,
        authority_target = snapshot.authorityTarget,
    }, {
        fullType = snapshot.fullType,
        nutritionSource = snapshot.nutritionSource,
        sourceFullType = snapshot.sourceFullType or snapshot.fullType,
        authorityTarget = snapshot.authorityTarget,
        provenance = snapshot.provenance,
        seedReason = snapshot.seedReason,
        hunger = (tonumber(snapshot.hunger) or 0) * ratio,
        baseHunger = snapshot.baseHunger,
        kcal = (tonumber(snapshot.kcal) or 0) * ratio * multiplier,
        carbs = (tonumber(snapshot.carbs) or 0) * ratio * multiplier,
        fats = (tonumber(snapshot.fats) or 0) * ratio * multiplier,
        proteins = (tonumber(snapshot.proteins) or 0) * ratio * multiplier,
        remainingFraction = snapshot.remainingFraction and clamp01(snapshot.remainingFraction * ratio) or nil,
        fluidPayloadId = snapshot.fluidPayloadId,
        fluidCapacity = snapshot.fluidCapacity,
        fluidAmount = snapshot.fluidAmount and (snapshot.fluidAmount * ratio) or nil,
    })
end

local function addPayloadSnapshots(fullType, entry, baseSnapshot, addedValues)
    local base = baseSnapshot or {}
    local added = addedValues or {}
    return normalizeSnapshot(fullType, entry, {
        fullType = fullType,
        nutritionSource = "computed",
        sourceFullType = fullType,
        provenance = added.provenance or base.provenance or "computed",
        seedReason = added.seedReason or base.seedReason or "",
        hunger = (tonumber(base.hunger) or 0) + (tonumber(added.hunger) or 0),
        baseHunger = (tonumber(base.baseHunger) or tonumber(base.hunger) or 0) + (tonumber(added.baseHunger) or tonumber(added.hunger) or 0),
        kcal = (tonumber(base.kcal) or 0) + (tonumber(added.kcal) or 0),
        carbs = (tonumber(base.carbs) or 0) + (tonumber(added.carbs) or 0),
        fats = (tonumber(base.fats) or 0) + (tonumber(added.fats) or 0),
        proteins = (tonumber(base.proteins) or 0) + (tonumber(added.proteins) or 0),
        fluidPayloadId = added.fluidPayloadId or base.fluidPayloadId,
        fluidCapacity = tonumber(added.fluidCapacity) or tonumber(base.fluidCapacity) or nil,
        fluidAmount = tonumber(added.fluidAmount) or tonumber(base.fluidAmount) or nil,
    })
end

local function getBurntNutritionMultiplier(item)
    if safeCall(item, "isBurnt") == true then
        return 0.2
    end
    return 1
end

local function resolveAppliedSnapshot(item, fullType, entry)
    local current = readCurrentValues(item, fullType, entry)
    local source = resolveEntrySource(entry)
    if source == "authored" then
        local defaults = getDefaultValues(fullType, entry)
        if not defaults then
            return nil, current, nil, nil, nil
        end
        local remainingFraction = resolveRemainingFraction(item, current, defaults)
        return buildAppliedSnapshot(defaults, remainingFraction), current, nil, defaults, "authored"
    end

    local stored = readStoredSnapshot(item, fullType, entry)
    if not stored then
        stored = bootstrapComputedSnapshot(item, fullType, entry, reason or "computed-restore-bootstrap")
    end
    if not stored then
        warnAuthorityOnce(fullType, "computed-payload-missing")
        return nil, current, nil, nil, nil
    end

    local remainingFraction = resolveRemainingFraction(item, current, stored)
    return buildAppliedSnapshot(stored, remainingFraction), current, stored, nil, "computed"
end

local function applyFluidSnapshot(item, snapshot)
    local fluidContainer = getFluidContainer(item)
    if not fluidContainer or snapshot == nil then
        return false
    end

    local desiredAmount = tonumber(snapshot.fluidAmount)
    if desiredAmount == nil and snapshot.fluidCapacity ~= nil and snapshot.remainingFraction ~= nil then
        desiredAmount = tonumber(snapshot.fluidCapacity) * tonumber(snapshot.remainingFraction)
    end
    if desiredAmount == nil and snapshot.remainingFraction == nil then
        return false
    end

    local currentAmount = getFluidAmount(fluidContainer)
    local currentPayloadId = getFluidPayloadId(fluidContainer)
    local desiredPayloadId = snapshot.fluidPayloadId
    local shouldReset = false

    if desiredAmount ~= nil and currentAmount ~= nil and math.abs(currentAmount - desiredAmount) > EPSILON then
        shouldReset = true
    end
    if desiredPayloadId and currentPayloadId and tostring(currentPayloadId) ~= tostring(desiredPayloadId) then
        shouldReset = true
    end

    if shouldReset then
        tryMethod(fluidContainer, "removeFluid")
        if desiredAmount ~= nil and desiredAmount > EPSILON and desiredPayloadId then
            tryMethod(fluidContainer, "addFluid", desiredPayloadId, desiredAmount)
        end
    end

    if desiredAmount ~= nil then
        tryMethod(fluidContainer, "setAmount", desiredAmount)
    end
    if snapshot.remainingFraction ~= nil then
        tryMethod(fluidContainer, "setFilledRatio", snapshot.remainingFraction)
    end

    return true
end

local function applySnapshot(item, snapshot)
    if not item or not snapshot then
        return false
    end

    applyFluidSnapshot(item, snapshot)
    safeCall(item, "setBaseHunger", tonumber(snapshot.baseHunger) or 0)
    safeCall(item, "setHungChange", tonumber(snapshot.hunger) or 0)
    safeCall(item, "setCalories", tonumber(snapshot.kcal) or 0)
    safeCall(item, "setCarbohydrates", tonumber(snapshot.carbs) or 0)
    safeCall(item, "setLipids", tonumber(snapshot.fats) or 0)
    safeCall(item, "setProteins", tonumber(snapshot.proteins) or 0)
    safeCall(item, "syncItemFields")
    return true
end

ItemAuthority.SNAPSHOT_KEY = SNAPSHOT_KEY
ItemAuthority.SNAPSHOT_VERSION = SNAPSHOT_VERSION

ItemAuthority.safeCall = safeCall
ItemAuthority.log = log
ItemAuthority.EPSILON = EPSILON
ItemAuthority.clamp01 = clamp01
ItemAuthority.getFoodEntry = getFoodEntry
ItemAuthority.resolveEntrySource = resolveEntrySource
ItemAuthority.hasVanillaDynamicValues = hasVanillaDynamicValues
ItemAuthority.readCurrentValuesPrivate = readCurrentValues
ItemAuthority.readStoredSnapshotPrivate = readStoredSnapshot
ItemAuthority.resolveComputedDisplaySnapshot = resolveComputedDisplaySnapshot
ItemAuthority.getDefaultValues = getDefaultValues
ItemAuthority.scaleConsumedSnapshot = scaleConsumedSnapshot
ItemAuthority.getBurntNutritionMultiplier = getBurntNutritionMultiplier
ItemAuthority.normalizeSnapshot = normalizeSnapshot
ItemAuthority.writeStoredSnapshot = writeStoredSnapshot
ItemAuthority.resolveRemainingFraction = resolveRemainingFraction
ItemAuthority.applySnapshot = applySnapshot
ItemAuthority.buildAppliedSnapshot = buildAppliedSnapshot
ItemAuthority.addPayloadSnapshots = addPayloadSnapshots
ItemAuthority.clearStoredSnapshot = clearStoredSnapshot
ItemAuthority.snapshotsMatch = snapshotsMatch
ItemAuthority.warnAuthorityOnce = warnAuthorityOnce
ItemAuthority.resolveAppliedSnapshot = resolveAppliedSnapshot
ItemAuthority.visitList = CoreUtils.visitList

require "items/NutritionMakesSense_ItemAuthority_Query"
require "items/NutritionMakesSense_ItemAuthority_Computed"
require "items/NutritionMakesSense_ItemAuthority_Traversal"
require "items/NutritionMakesSense_ItemAuthority_Lifecycle"

return ItemAuthority
