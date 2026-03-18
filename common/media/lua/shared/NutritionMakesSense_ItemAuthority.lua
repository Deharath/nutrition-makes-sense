NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_Data"
require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_StablePatcher"

local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
NutritionMakesSense.ItemAuthority = ItemAuthority

local MP = NutritionMakesSense.MP or {}

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

local function tryMethod(target, methodName, ...)
    if not target then
        return false, nil
    end

    local method = target[methodName]
    if type(method) ~= "function" then
        return false, nil
    end

    local ok, result = pcall(method, target, ...)
    if not ok then
        return false, nil
    end

    return true, result
end

local function rawLookup(tableLike, key)
    if not tableLike then
        return nil
    end
    if type(tableLike.rawget) == "function" then
        local ok, value = pcall(tableLike.rawget, tableLike, key)
        if ok then
            return value
        end
    end
    if type(tableLike) == "table" then
        return tableLike[key]
    end
    return nil
end

local function clamp01(value)
    local numeric = tonumber(value) or 0
    if numeric < 0 then
        return 0
    end
    if numeric > 1 then
        return 1
    end
    return numeric
end

local function numbersClose(a, b)
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= EPSILON
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

local function resolveFullType(itemOrFullType)
    if type(itemOrFullType) == "string" and itemOrFullType ~= "" then
        return itemOrFullType
    end
    if itemOrFullType ~= nil then
        return safeCall(itemOrFullType, "getFullType")
            or safeCall(itemOrFullType, "getType")
            or (type(itemOrFullType) == "table" and (itemOrFullType.fullType or itemOrFullType.id))
    end
    return nil
end

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

local function summarizeResult(summary, action)
    summary[action] = (summary[action] or 0) + 1
end

local syncItem
local visitContainer
local eachKnownPlayer

local function newTraversalState(summary)
    return {
        summary = summary,
        seenItems = {},
        seenContainers = {},
        seenSquares = {},
        seenObjects = {},
        seenWorldObjects = {},
        seenVehicles = {},
        seenChunkMaps = {},
        surfaceCounts = {
            player = 0,
            world = 0,
            object = 0,
            vehicle = 0,
        },
        chunkMapsVisited = 0,
        squaresVisited = 0,
        objectsVisited = 0,
        worldObjectsVisited = 0,
        vehiclesVisited = 0,
        containersVisited = 0,
    }
end

local function visitList(list, callback)
    if not list or type(callback) ~= "function" then
        return
    end

    local size = safeCall(list, "size")
    if type(size) == "number" then
        for index = 0, size - 1 do
            callback(safeCall(list, "get", index), index)
        end
        return
    end

    if type(list) == "table" then
        for index, value in ipairs(list) do
            callback(value, index - 1)
        end
    end
end

local function recordSurfaceVisit(state, surface)
    if state and surface and state.surfaceCounts[surface] ~= nil then
        state.surfaceCounts[surface] = state.surfaceCounts[surface] + 1
    end
end

local function visitTrackedItem(item, state, mode, reason, surface)
    if not item or not state or state.seenItems[item] then
        return
    end

    state.seenItems[item] = true
    recordSurfaceVisit(state, surface)
    summarizeResult(state.summary, syncItem(item, mode, reason))

    if type(item.getItemContainer) == "function" then
        visitContainer(item:getItemContainer(), state, mode, reason, surface)
    end
end

visitContainer = function(container, state, mode, reason, surface)
    if not container or not state or state.seenContainers[container] or type(container.getItems) ~= "function" then
        return
    end

    state.seenContainers[container] = true
    state.containersVisited = state.containersVisited + 1

    visitList(container:getItems(), function(item)
        visitTrackedItem(item, state, mode, reason, surface)
    end)
end

local function visitObjectContainers(object, state, mode, reason)
    if not object or not state or state.seenObjects[object] then
        return
    end

    state.seenObjects[object] = true
    state.objectsVisited = state.objectsVisited + 1

    local primaryContainer = safeCall(object, "getItemContainer")
    if primaryContainer then
        visitContainer(primaryContainer, state, mode, reason, "object")
    end

    local containerCount = tonumber(safeCall(object, "getContainerCount")) or 0
    for containerIndex = 0, containerCount - 1 do
        local objectContainer = safeCall(object, "getContainerByIndex", containerIndex)
        if objectContainer then
            visitContainer(objectContainer, state, mode, reason, "object")
        end
    end
end

local function visitWorldInventoryObject(worldObject, state, mode, reason)
    if not worldObject or not state or state.seenWorldObjects[worldObject] then
        return
    end

    state.seenWorldObjects[worldObject] = true
    state.worldObjectsVisited = state.worldObjectsVisited + 1
    visitTrackedItem(safeCall(worldObject, "getItem"), state, mode, reason, "world")
end

local function visitSquare(square, state, mode, reason)
    if not square or not state or state.seenSquares[square] then
        return
    end

    state.seenSquares[square] = true
    state.squaresVisited = state.squaresVisited + 1

    visitList(safeCall(square, "getWorldObjects"), function(worldObject)
        visitWorldInventoryObject(worldObject, state, mode, reason)
    end)

    visitList(safeCall(square, "getObjects"), function(object)
        visitObjectContainers(object, state, mode, reason)
    end)
end

local function visitVehicle(vehicle, state, mode, reason)
    if not vehicle or not state or state.seenVehicles[vehicle] then
        return
    end

    state.seenVehicles[vehicle] = true
    state.vehiclesVisited = state.vehiclesVisited + 1

    local partCount = tonumber(safeCall(vehicle, "getPartCount")) or 0
    for partIndex = 0, partCount - 1 do
        local part = safeCall(vehicle, "getPartByIndex", partIndex)
        local vehicleContainer = part and safeCall(part, "getItemContainer") or nil
        if vehicleContainer then
            visitContainer(vehicleContainer, state, mode, reason, "vehicle")
        end
    end
end

local function getWorldCell()
    if type(getCell) == "function" then
        local cell = getCell()
        if cell then
            return cell
        end
    end

    if type(getWorld) == "function" then
        local world = getWorld()
        local cell = safeCall(world, "getCell")
        if cell then
            return cell
        end
    end

    return nil
end

local function visitChunkMap(chunkMap, cell, state, mode, reason)
    if not chunkMap or not state or state.seenChunkMaps[chunkMap] then
        return
    end

    local minX = tonumber(safeCall(chunkMap, "getWorldXMinTiles"))
    local maxX = tonumber(safeCall(chunkMap, "getWorldXMaxTiles"))
    local minY = tonumber(safeCall(chunkMap, "getWorldYMinTiles"))
    local maxY = tonumber(safeCall(chunkMap, "getWorldYMaxTiles"))
    if not minX or not maxX or not minY or not maxY then
        return
    end

    state.seenChunkMaps[chunkMap] = true
    state.chunkMapsVisited = state.chunkMapsVisited + 1

    local minZ = tonumber(cell and safeCall(cell, "getMinZ")) or 0
    local maxZ = tonumber(cell and safeCall(cell, "getMaxZ")) or 0

    for z = minZ, maxZ do
        for y = minY, maxY do
            for x = minX, maxX do
                visitSquare(safeCall(chunkMap, "getGridSquare", x, y, z), state, mode, reason)
            end
        end
    end
end

local function eachActiveChunkMap(callback)
    if type(callback) ~= "function" then
        return
    end

    local cell = getWorldCell()
    if not cell or type(cell.getChunkMap) ~= "function" then
        return cell
    end

    local seen = {}
    local yieldedAny = false

    local function yieldChunkMap(index)
        local chunkMap = safeCall(cell, "getChunkMap", index)
        if chunkMap and not seen[chunkMap] then
            seen[chunkMap] = true
            yieldedAny = true
            callback(chunkMap, cell, index)
        end
    end

    if type(getNumActivePlayers) == "function" then
        local playerCount = tonumber(getNumActivePlayers()) or 0
        for playerIndex = 0, playerCount - 1 do
            yieldChunkMap(playerIndex)
        end
    end

    if type(isServer) == "function" and isServer() and type(getOnlinePlayers) == "function" then
        local players = getOnlinePlayers()
        local playerCount = tonumber(players and safeCall(players, "size")) or 0
        for playerIndex = 0, playerCount - 1 do
            yieldChunkMap(playerIndex)
        end
    end

    if not yieldedAny then
        yieldChunkMap(0)
    end

    return cell
end

local function logTraversalSummary(tag, summary, state, mode, reason)
    if not summary or not state then
        return
    end

    if (summary.restored + summary.captured + summary.updated) <= 0 then
        return
    end

    log(string.format(
        "[%s] mode=%s reason=%s restored=%d captured=%d updated=%d unchanged=%d player=%d world=%d object=%d vehicle=%d chunk_maps=%d squares=%d containers=%d vehicles=%d",
        tostring(tag),
        tostring(mode or "capture"),
        tostring(reason),
        tonumber(summary.restored or 0),
        tonumber(summary.captured or 0),
        tonumber(summary.updated or 0),
        tonumber(summary.unchanged or 0),
        tonumber(state.surfaceCounts.player or 0),
        tonumber(state.surfaceCounts.world or 0),
        tonumber(state.surfaceCounts.object or 0),
        tonumber(state.surfaceCounts.vehicle or 0),
        tonumber(state.chunkMapsVisited or 0),
        tonumber(state.squaresVisited or 0),
        tonumber(state.containersVisited or 0),
        tonumber(state.vehiclesVisited or 0)
    ))
end

local function syncTraversedSurfaces(reason, mode, includeLoadedWorld)
    pcall(function()
        if NutritionMakesSense.StablePatcher and NutritionMakesSense.StablePatcher.ensurePatched then
            NutritionMakesSense.StablePatcher.ensurePatched(tostring(reason or "item-authority"))
        end
    end)

    local summary = {
        restored = 0,
        captured = 0,
        updated = 0,
        unchanged = 0,
        ignored = 0,
    }
    local state = newTraversalState(summary)

    eachKnownPlayer(function(playerObj)
        if playerObj and type(playerObj.getInventory) == "function" then
            visitContainer(playerObj:getInventory(), state, mode or "capture", reason, "player")
        end
    end)

    if includeLoadedWorld then
        local cell = eachActiveChunkMap(function(chunkMap, activeCell)
            visitChunkMap(chunkMap, activeCell, state, mode or "capture", reason)
        end)

        if cell and state.chunkMapsVisited <= 0 then
            visitList(safeCall(cell, "getProcessWorldItems"), function(worldObject)
                visitWorldInventoryObject(worldObject, state, mode or "capture", reason)
            end)

            visitList(safeCall(cell, "getProcessIsoObjects"), function(object)
                visitObjectContainers(object, state, mode or "capture", reason)
            end)
        end

        if cell and type(cell.getVehicles) == "function" then
            visitList(cell:getVehicles(), function(vehicle)
                visitVehicle(vehicle, state, mode or "capture", reason)
            end)
        end
    end

    logTraversalSummary(includeLoadedWorld and "ITEM_AUTHORITY_PERSISTENCE_SYNC" or "ITEM_AUTHORITY_SYNC", summary, state, mode, reason)
    return summary
end

syncItem = function(item, mode, reason)
    if not item then
        return "ignored"
    end

    local isFood = safeCall(item, "isFood")
    if isFood == nil then
        isFood = safeCall(item, "IsFood")
    end
    if isFood == false then
        return "ignored"
    end

    local entry, fullType = getFoodEntry(item)
    if not entry or not fullType then
        return "ignored"
    end

    if resolveEntrySource(entry) == "authored" and hasVanillaDynamicValues(item) then
        clearStoredSnapshot(item)
        return "ignored"
    end

    local applied, current, stored, defaults, resolvedSource = resolveAppliedSnapshot(item, fullType, entry)
    if not applied then
        warnAuthorityOnce(fullType, "missing-normalization-source")
        return "ignored"
    end

    local changed = false
    if resolveEntrySource(entry) == "authored" then
        changed = clearStoredSnapshot(item) or changed
    end

    if not current or not snapshotsMatch(current, applied) then
        applySnapshot(item, applied)
        log(string.format(
            "[ITEM_AUTHORITY] mode=%s reason=%s item=%s source=%s resolved=%s action=normalize",
            tostring(mode or "capture"),
            tostring(reason),
            tostring(fullType),
            tostring(resolveEntrySource(entry)),
            tostring(resolvedSource or "authored")
        ))
        return changed and "updated" or "restored"
    end

    if changed then
        return "updated"
    end

    if resolvedSource == "computed" and stored and not defaults then
        return "captured"
    end

    return "unchanged"
end

eachKnownPlayer = function(callback)
    if type(isServer) == "function" and isServer() and type(getOnlinePlayers) == "function" then
        local players = getOnlinePlayers()
        if not players then
            return
        end
        for i = 0, players:size() - 1 do
            callback(players:get(i))
        end
        return
    end

    if type(getNumActivePlayers) == "function" and type(getSpecificPlayer) == "function" then
        for playerIndex = 0, getNumActivePlayers() - 1 do
            local playerObj = getSpecificPlayer(playerIndex)
            if playerObj then
                callback(playerObj)
            end
        end
        return
    end

    if type(getPlayer) == "function" then
        local playerObj = getPlayer()
        if playerObj then
            callback(playerObj)
        end
    end
end

ItemAuthority.SNAPSHOT_KEY = SNAPSHOT_KEY
ItemAuthority.SNAPSHOT_VERSION = SNAPSHOT_VERSION

function ItemAuthority.getTrackedEntry(itemOrFullType)
    local entry = getFoodEntry(itemOrFullType)
    return entry
end

function ItemAuthority.getDisplayEntry(itemOrFullType)
    local entry = getFoodEntry(itemOrFullType)
    return entry
end

function ItemAuthority.getNutritionSource(itemOrFullType)
    local entry = getFoodEntry(itemOrFullType)
    return entry and resolveEntrySource(entry) or nil
end

function ItemAuthority.getResolvedNutritionSource(item)
    local entry, fullType = getFoodEntry(item)
    if not entry or not fullType then
        return nil
    end
    return resolveEntrySource(entry)
end

function ItemAuthority.getFoodClass(itemOrFullType)
    return ItemAuthority.getNutritionSource(itemOrFullType)
end

function ItemAuthority.getFoodDisposition(itemOrFullType)
    return ItemAuthority.getNutritionSource(itemOrFullType) and "authority" or "ignored"
end

function ItemAuthority.readCurrentValues(item)
    local entry, fullType = getFoodEntry(item)
    if not entry or not fullType then
        return nil
    end
    return readCurrentValues(item, fullType, entry)
end

function ItemAuthority.readStoredSnapshot(item)
    local entry, fullType = getFoodEntry(item)
    if not entry or not fullType then
        return nil
    end
    return readStoredSnapshot(item, fullType, entry)
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

function ItemAuthority.isDynamicItem(itemOrFullType)
    return ItemAuthority.getNutritionSource(itemOrFullType) == "computed"
end

function ItemAuthority.scaleSnapshot(snapshot, fraction, nutritionMultiplier)
    return scaleConsumedSnapshot(snapshot, fraction, nutritionMultiplier)
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

local function getComputedEntry(item)
    local entry, fullType = getFoodEntry(item)
    if not entry or not fullType then
        return nil, nil
    end
    if resolveEntrySource(entry) ~= "computed" then
        return nil, nil
    end
    return fullType, entry
end

function ItemAuthority.seedComputedPayload(item, values, reason)
    local fullType, entry = getComputedEntry(item)
    if not fullType or not entry or type(values) ~= "table" then
        return nil
    end

    local total = normalizeSnapshot(fullType, entry, {
        fullType = fullType,
        nutritionSource = "computed",
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

    local DevPanel = NutritionMakesSense.DevPanel
    if DevPanel and type(DevPanel.noteSeedEvent) == "function" then
        DevPanel.noteSeedEvent({
            reason = reason or "computed-seed",
            item = fullType,
            kcal = total.kcal,
            carbs = total.carbs,
            fats = total.fats,
            proteins = total.proteins,
        })
    end

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

function ItemAuthority.accumulateComputedPayload(item, addedValues, reason)
    local fullType, entry = getComputedEntry(item)
    if not fullType or not entry or type(addedValues) ~= "table" then
        return nil
    end

    local stored = readStoredSnapshot(item, fullType, entry)
    local base = stored or normalizeSnapshot(fullType, entry, {
        fullType = fullType,
        nutritionSource = "computed",
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

    local DevPanel = NutritionMakesSense.DevPanel
    if DevPanel and type(DevPanel.noteSeedEvent) == "function" then
        DevPanel.noteSeedEvent({
            reason = reason or "computed-accumulate",
            item = fullType,
            kcal = combined.kcal,
            carbs = combined.carbs,
            fats = combined.fats,
            proteins = combined.proteins,
        })
    end

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

function ItemAuthority.seedComputedOutputs(createdItems, payloadValues, reason)
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
        return ItemAuthority.seedComputedPayload(targets[1].item, {
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
        if scaled and ItemAuthority.seedComputedPayload(target.item, scaled, reason) then
            seeded = seeded + 1
        end
    end

    return seeded
end

function ItemAuthority.transferItemSnapshot(sourceItem, targetItem, reason)
    local sourceEntry, sourceFullType = getFoodEntry(sourceItem)
    local targetEntry, targetFullType = getFoodEntry(targetItem)
    if not sourceEntry or not sourceFullType or not targetEntry or not targetFullType then
        return nil
    end
    if resolveEntrySource(targetEntry) ~= "computed" then
        clearStoredSnapshot(targetItem)
        return nil
    end

    local stored = readStoredSnapshot(sourceItem, sourceFullType, sourceEntry)
    if not stored then
        return nil
    end

    local transferred = normalizeSnapshot(targetFullType, targetEntry, {
        fullType = targetFullType,
        nutritionSource = "computed",
        sourceFullType = stored.sourceFullType or sourceFullType,
        authorityTarget = targetEntry.authority_target or targetFullType,
        provenance = stored.provenance,
        seedReason = stored.seedReason or reason or "transfer",
        hunger = stored.hunger,
        baseHunger = stored.baseHunger,
        kcal = stored.kcal,
        carbs = stored.carbs,
        fats = stored.fats,
        proteins = stored.proteins,
        fluidPayloadId = stored.fluidPayloadId,
        fluidCapacity = stored.fluidCapacity,
        fluidAmount = stored.fluidAmount,
    })
    if not transferred then
        return nil
    end

    if not writeStoredSnapshot(targetItem, transferred) then
        return nil
    end

    local current = readCurrentValues(targetItem, targetFullType, targetEntry)
    local remainingFraction = resolveRemainingFraction(targetItem, current, transferred)
    applySnapshot(targetItem, buildAppliedSnapshot(transferred, remainingFraction))

    log(string.format(
        "[ITEM_AUTHORITY_TRANSFER] reason=%s source=%s target=%s source=%s kcal=%.1f",
        tostring(reason or "transfer"),
        tostring(sourceFullType),
        tostring(targetFullType),
        tostring(stored.provenance or "computed"),
        tonumber(transferred.kcal or 0)
    ))
    return transferred
end

function ItemAuthority.captureItem(item, reason)
    return syncItem(item, "capture", reason or "capture")
end

function ItemAuthority.restoreItem(item, reason)
    return syncItem(item, "restore", reason or "restore")
end

function ItemAuthority.syncKnownInventories(reason, mode)
    return syncTraversedSurfaces(reason, mode, false)
end

function ItemAuthority.syncPersistenceSurfaces(reason, mode)
    return syncTraversedSurfaces(reason, mode, true)
end

function ItemAuthority.syncPlayerInventories(reason, mode)
    return syncTraversedSurfaces(reason, mode, false)
end

ItemAuthority.seedDynamicPayload = ItemAuthority.seedComputedPayload
ItemAuthority.accumulateDynamicPayload = ItemAuthority.accumulateComputedPayload
ItemAuthority.seedDynamicOutputs = ItemAuthority.seedComputedOutputs

if Events then
    if Events.OnLoad and type(Events.OnLoad.Add) == "function" then
        Events.OnLoad.Add(function()
            ItemAuthority.syncPersistenceSurfaces("on-load", "restore")
        end)
    end

    if Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
        Events.OnGameStart.Add(function()
            ItemAuthority.syncPlayerInventories("game-start", "restore")
        end)
    end

    if Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
        Events.OnCreatePlayer.Add(function()
            ItemAuthority.syncPlayerInventories("create-player", "restore")
        end)
    end

    if Events.OnContainerUpdate and type(Events.OnContainerUpdate.Add) == "function" then
        Events.OnContainerUpdate.Add(function(item)
            if item then
                ItemAuthority.restoreItem(item, "container-update-item")
            end
        end)
    end
end

return ItemAuthority
