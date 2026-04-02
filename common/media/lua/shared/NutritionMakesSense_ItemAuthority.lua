NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_Data"
require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_StablePatcher"
require "NutritionMakesSense_CoreUtils"
require "NutritionMakesSense_Settings"

local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
NutritionMakesSense.ItemAuthority = ItemAuthority

local CoreUtils = NutritionMakesSense.CoreUtils or {}
local Settings = NutritionMakesSense.Settings or {}

local SNAPSHOT_KEY = "NutritionMakesSenseItemAuthority"
local SNAPSHOT_VERSION_KEY = "NutritionMakesSenseItemAuthorityVersion"
local SNAPSHOT_VERSION = 9
local EPSILON = 0.001
local CONSUME_EPSILON = 0.0001
local HUNGER_TO_RUNTIME_SCALE = 0.01
local SNAPSHOT_MODE_STATIC = "static"
local SNAPSHOT_MODE_FLUID = "fluid"
local SNAPSHOT_MODE_COMPOSED = "composed"
local VALID_SNAPSHOT_MODES = {
    [SNAPSHOT_MODE_STATIC] = true,
    [SNAPSHOT_MODE_FLUID] = true,
    [SNAPSHOT_MODE_COMPOSED] = true,
}
local TRACKED_SOURCES = {
    authored = true,
    vanilla = true,
    computed = true,
}
local authorityWarnings = {}
local runtimeDataWarnings = {}
local embeddedModuleWarnings = {}
local embeddedFoodValuesCache = nil
local embeddedFoodSemanticsCache = nil

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

local function getEntrySnapshotMode(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local snapshotMode = entry.snapshot_mode or entry.snapshotMode
    if type(snapshotMode) == "string" and VALID_SNAPSHOT_MODES[snapshotMode] then
        return snapshotMode
    end
    return nil
end

local function getEntryAction(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local action = entry.action
    if type(action) == "string" and action ~= "" then
        return action
    end
    return nil
end

local function normalizeCarbProfile(value)
    local profile = tostring(value or ""):lower()
    if profile == "starchy" or profile == "sugary" then
        return profile
    end
    return "neutral"
end

local function getEntryCarbProfile(entry)
    if type(entry) ~= "table" then
        return "neutral"
    end
    return normalizeCarbProfile(entry.carb_profile or entry.carbProfile)
end

local function usesComposedSnapshots(entry)
    return getEntrySnapshotMode(entry) == SNAPSHOT_MODE_COMPOSED
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

local function getStaticFoodValueSource()
    if type(Settings.getStaticFoodValueSource) == "function" then
        return Settings.getStaticFoodValueSource()
    end
    return "authored"
end

local function getScriptManagerHandle()
    if type(getScriptManager) == "function" then
        return getScriptManager()
    end
    if ScriptManager and ScriptManager.instance then
        return ScriptManager.instance
    end
    return nil
end

local function getRuntimeData()
    if NutritionMakesSense.runtimeData then
        return NutritionMakesSense.runtimeData
    end

    local ok, dataOrErr = pcall(NutritionMakesSense.Data.loadRuntimeData, false)
    if ok then
        return dataOrErr
    end

    local warnKey = tostring(dataOrErr or "unknown-load-error")
    if not runtimeDataWarnings[warnKey] then
        runtimeDataWarnings[warnKey] = true
        log(string.format("[ITEM_AUTHORITY_WARN] item=runtime-data detail=load-failed:%s", warnKey))
    end
    return NutritionMakesSense.Data and NutritionMakesSense.Data._cache or nil
end

local function warnEmbeddedModuleOnce(moduleName, detail)
    local key = tostring(moduleName or "module") .. ":" .. tostring(detail or "warning")
    if embeddedModuleWarnings[key] then
        return
    end
    embeddedModuleWarnings[key] = true
    log(string.format(
        "[ITEM_AUTHORITY_WARN] item=%s detail=%s",
        tostring(moduleName or "module"),
        tostring(detail or "warning")
    ))
end

local function loadEmbeddedFoodValues()
    if embeddedFoodValuesCache ~= nil then
        return embeddedFoodValuesCache or nil
    end

    local ok, values = pcall(require, "generated/NutritionMakesSense_FoodValues")
    if ok and type(values) == "table" then
        embeddedFoodValuesCache = values
        return values
    end
    if type(NMS_FoodValues) == "table" then
        embeddedFoodValuesCache = NMS_FoodValues
        return embeddedFoodValuesCache
    end

    warnEmbeddedModuleOnce("embedded-values", "load-failed:" .. tostring(values))
    embeddedFoodValuesCache = false
    return nil
end

local function loadEmbeddedFoodSemantics()
    if embeddedFoodSemanticsCache ~= nil then
        return embeddedFoodSemanticsCache or nil
    end

    local ok, semantics = pcall(require, "generated/NutritionMakesSense_FoodSemantics")
    if ok and type(semantics) == "table" then
        embeddedFoodSemanticsCache = semantics
        return semantics
    end
    if type(NMS_FoodSemantics) == "table" then
        embeddedFoodSemanticsCache = NMS_FoodSemantics
        return embeddedFoodSemanticsCache
    end

    embeddedFoodSemanticsCache = false
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

    local inferredMode = tostring(snapshot.snapshotMode or snapshot.snapshot_mode or "")
    if inferredMode == "" then
        if snapshot.fluidPayloadId ~= nil or getEntrySnapshotMode(entry) == SNAPSHOT_MODE_FLUID then
            inferredMode = SNAPSHOT_MODE_FLUID
        elseif usesComposedSnapshots(entry) then
            inferredMode = SNAPSHOT_MODE_COMPOSED
        else
            inferredMode = SNAPSHOT_MODE_STATIC
        end
    end
    if inferredMode ~= SNAPSHOT_MODE_STATIC
        and inferredMode ~= SNAPSHOT_MODE_FLUID
        and inferredMode ~= SNAPSHOT_MODE_COMPOSED
    then
        return nil
    end

    local nutritionSource = snapshot.nutritionSource or snapshot.nutrition_source
    if nutritionSource == nil or tostring(nutritionSource) == "" then
        if inferredMode == SNAPSHOT_MODE_STATIC then
            nutritionSource = getStaticFoodValueSource()
        else
            nutritionSource = resolveEntrySource(entry) or "computed"
        end
    end
    nutritionSource = tostring(nutritionSource or "")
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
        snapshotMode = inferredMode,
        snapshot_mode = inferredMode,
        authorityTarget = tostring(snapshot.authorityTarget or (entry and entry.authority_target) or resolvedFullType),
        provenance = tostring(snapshot.provenance or ""),
        seedReason = tostring(snapshot.seedReason or ""),
        hunger = hunger,
        baseHunger = baseHunger,
        kcal = tonumber(snapshot.kcal) or 0,
        carbs = tonumber(snapshot.carbs) or 0,
        fats = tonumber(snapshot.fats) or 0,
        proteins = tonumber(snapshot.proteins) or 0,
        carbProfile = normalizeCarbProfile(snapshot.carbProfile or snapshot.carb_profile or getEntryCarbProfile(entry)),
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

    return tostring(a.snapshotMode or "") == tostring(b.snapshotMode or "")
        and tostring(a.nutritionSource or "") == tostring(b.nutritionSource or "")
        and tostring(a.carbProfile or "") == tostring(b.carbProfile or "")
        and tostring(a.fluidPayloadId or "") == tostring(b.fluidPayloadId or "")
        and numbersClose(a.hunger, b.hunger)
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
    if type(entry) ~= "table" then
        local embeddedSemantics = loadEmbeddedFoodSemantics()
        entry = embeddedSemantics and embeddedSemantics[fullType] or nil
    end
    if type(entry) == "table" then
        if isTrackedSource(resolveEntrySource(entry)) or usesComposedSnapshots(entry) then
            return entry, fullType
        end
        return nil, fullType
    end

    local authoredValues = data and data.valuesByItemId and data.valuesByItemId[fullType] or nil
    if type(authoredValues) ~= "table" then
        local embeddedValues = loadEmbeddedFoodValues()
        authoredValues = embeddedValues and embeddedValues[fullType] or nil
    end
    if type(authoredValues) == "table" then
        return {
            item_id = fullType,
            snapshot_mode = SNAPSHOT_MODE_STATIC,
            action = "patched",
            nutrition_source = "authored",
            authority_target = fullType,
            patch_source = fullType,
        }, fullType
    end

    return nil, fullType
end

local function readScriptNumber(scriptItem, getterName, fieldName)
    local value = safeCall(scriptItem, getterName)
    if value == nil and fieldName then
        value = rawLookup(scriptItem, fieldName)
    end
    return tonumber(value)
end

local function getStaticScriptItem(fullType, entry)
    local scriptManager = getScriptManagerHandle()
    if not scriptManager or type(scriptManager.getItem) ~= "function" then
        return nil, nil
    end

    local resolvedFullType = tostring(fullType or "")
    if resolvedFullType ~= "" then
        local directItem = scriptManager:getItem(resolvedFullType)
        if directItem then
            return directItem, resolvedFullType
        end
    end

    local patchSource = entry and entry.patch_source and tostring(entry.patch_source) or nil
    if patchSource and patchSource ~= "" and patchSource ~= resolvedFullType then
        local patchItem = scriptManager:getItem(patchSource)
        if patchItem then
            return patchItem, patchSource
        end
    end

    return nil, nil
end

local function getVanillaDefaultValues(fullType, entry)
    local scriptItem, sourceFullType = getStaticScriptItem(fullType, entry)
    if not scriptItem then
        warnAuthorityOnce(fullType, "vanilla-defaults-script-missing")
        return nil
    end

    local scriptHunger = readScriptNumber(scriptItem, "getHungerChange", "hungerChange") or 0
    local runtimeHunger = scriptHunger * HUNGER_TO_RUNTIME_SCALE
    return normalizeSnapshot(fullType, entry, {
        fullType = fullType,
        nutritionSource = "vanilla",
        snapshotMode = SNAPSHOT_MODE_STATIC,
        sourceFullType = sourceFullType or fullType,
        provenance = "vanilla",
        seedReason = "defaults",
        hunger = runtimeHunger,
        baseHunger = runtimeHunger,
        kcal = readScriptNumber(scriptItem, "getCalories", "calories") or 0,
        carbs = readScriptNumber(scriptItem, "getCarbohydrates", "carbohydrates") or 0,
        fats = readScriptNumber(scriptItem, "getLipids", "lipids") or 0,
        proteins = readScriptNumber(scriptItem, "getProteins", "proteins") or 0,
    })
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
        nutritionSource = resolveEntrySource(entry) or "computed",
        snapshotMode = SNAPSHOT_MODE_FLUID,
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
        nutritionSource = usesComposedSnapshots(entry) and "computed" or getStaticFoodValueSource(),
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
    local resolvedFullType = type(fullType) == "string" and fullType or tostring(fullType or "")
    if resolvedFullType == "" then
        return nil
    end

    if getStaticFoodValueSource() == "vanilla" then
        return getVanillaDefaultValues(resolvedFullType, entry)
    end

    local patchSource = (entry and entry.patch_source) or resolvedFullType
    if patchSource ~= nil then
        patchSource = tostring(patchSource)
    end
    local values = data and data.valuesByItemId and data.valuesByItemId[patchSource] or nil
    if not values then
        local embeddedValues = loadEmbeddedFoodValues()
        values = embeddedValues and embeddedValues[patchSource] or nil
    end
    if not values then
        return nil
    end

    local runtimeHunger = (tonumber(values.hunger) or 0) * HUNGER_TO_RUNTIME_SCALE
    return normalizeSnapshot(resolvedFullType, entry, {
        fullType = resolvedFullType,
        nutritionSource = "authored",
        snapshotMode = SNAPSHOT_MODE_STATIC,
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

local function getExpectedSnapshotMode(item, fullType, entry)
    if item and snapshotHasNutrition(readFluidCurrentValues(item, fullType, entry)) then
        return SNAPSHOT_MODE_FLUID
    end
    if usesComposedSnapshots(entry) then
        return SNAPSHOT_MODE_COMPOSED
    end
    return SNAPSHOT_MODE_STATIC
end

local function buildEmptyComposedSnapshot(fullType, entry, reason)
    return normalizeSnapshot(fullType, entry, {
        fullType = fullType,
        nutritionSource = "computed",
        snapshotMode = SNAPSHOT_MODE_COMPOSED,
        sourceFullType = fullType,
        authorityTarget = entry and entry.authority_target or fullType,
        provenance = "composed",
        seedReason = reason or "composed-empty-seed",
        hunger = 0,
        baseHunger = 0,
        kcal = 0,
        carbs = 0,
        fats = 0,
        proteins = 0,
        remainingFraction = 1,
    })
end

local function buildCurrentComposedSnapshot(fullType, entry, current, reason)
    if type(current) ~= "table" or not snapshotHasNutrition(current) then
        return nil
    end

    return normalizeSnapshot(fullType, entry, {
        fullType = fullType,
        nutritionSource = "computed",
        snapshotMode = SNAPSHOT_MODE_COMPOSED,
        sourceFullType = fullType,
        authorityTarget = entry and entry.authority_target or fullType,
        provenance = "live",
        seedReason = reason or "composed-current-seed",
        hunger = tonumber(current.hunger) or 0,
        baseHunger = tonumber(current.baseHunger) or tonumber(current.hunger) or 0,
        kcal = tonumber(current.kcal) or 0,
        carbs = tonumber(current.carbs) or 0,
        fats = tonumber(current.fats) or 0,
        proteins = tonumber(current.proteins) or 0,
        remainingFraction = 1,
        fluidPayloadId = current.fluidPayloadId,
        fluidCapacity = current.fluidCapacity,
        fluidAmount = current.fluidAmount,
    })
end

local function buildFluidSeedSnapshot(item, fullType, entry, reason)
    local current = readFluidCurrentValues(item, fullType, entry)
    if type(current) ~= "table" then
        return nil
    end

    local currentAmount = tonumber(current.fluidAmount)
    return normalizeSnapshot(fullType, entry, {
        fullType = fullType,
        nutritionSource = "computed",
        snapshotMode = SNAPSHOT_MODE_FLUID,
        sourceFullType = current.sourceFullType or fullType,
        authorityTarget = current.authorityTarget or (entry and entry.authority_target) or fullType,
        provenance = "fluid",
        seedReason = reason or "fluid-seed",
        hunger = tonumber(current.hunger) or 0,
        baseHunger = tonumber(current.hunger) or 0,
        kcal = tonumber(current.kcal) or 0,
        carbs = tonumber(current.carbs) or 0,
        fats = tonumber(current.fats) or 0,
        proteins = tonumber(current.proteins) or 0,
        remainingFraction = 1,
        fluidPayloadId = current.fluidPayloadId,
        fluidCapacity = currentAmount,
        fluidAmount = currentAmount,
    })
end

local function readStoredSnapshot(item, fullType, entry)
    if not item or not fullType then
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
        modData[SNAPSHOT_KEY] = nil
        modData[SNAPSHOT_VERSION_KEY] = nil
        return nil
    end

    local normalized = normalizeSnapshot(fullType, entry, stored)
    if not normalized then
        modData[SNAPSHOT_KEY] = nil
        modData[SNAPSHOT_VERSION_KEY] = nil
        return nil
    end
    if tonumber(normalized.version) ~= SNAPSHOT_VERSION then
        return nil
    end
    if tostring(normalized.fullType) ~= tostring(fullType) then
        return nil
    end
    return normalized
end

local writeStoredSnapshot

local resolveRemainingFraction
local buildAppliedSnapshot

writeStoredSnapshot = function(item, snapshot, fullType, entry)
    local modData = getModData(item)
    if not modData or not snapshot then
        return false
    end

    local normalized = normalizeSnapshot(fullType or snapshot.fullType, entry, snapshot)
    if not normalized then
        return false
    end

    modData[SNAPSHOT_KEY] = normalized
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

local function shouldReseedFluidSnapshot(current, stored)
    if type(current) ~= "table" or type(stored) ~= "table" then
        return false
    end
    if tostring(current.fluidPayloadId or "") ~= tostring(stored.fluidPayloadId or "") then
        return true
    end
    if (tonumber(current.fluidAmount) or 0) > ((tonumber(stored.fluidAmount) or 0) + EPSILON) then
        return true
    end
    if (tonumber(current.kcal) or 0) > ((tonumber(stored.kcal) or 0) + EPSILON) then
        return true
    end
    return false
end

local function shouldReseedComposedSnapshot(current, stored)
    if type(current) ~= "table" or type(stored) ~= "table" then
        return false
    end

    local currentKcal = tonumber(current.kcal) or 0
    local storedKcal = tonumber(stored.kcal) or 0
    local currentCarbs = tonumber(current.carbs) or 0
    local storedCarbs = tonumber(stored.carbs) or 0
    local currentFats = tonumber(current.fats) or 0
    local storedFats = tonumber(stored.fats) or 0
    local currentProteins = tonumber(current.proteins) or 0
    local storedProteins = tonumber(stored.proteins) or 0
    local currentHunger = math.abs(tonumber(current.hunger) or 0)
    local storedHunger = math.abs(tonumber(stored.hunger) or 0)

    return currentKcal > (storedKcal + EPSILON)
        or currentCarbs > (storedCarbs + EPSILON)
        or currentFats > (storedFats + EPSILON)
        or currentProteins > (storedProteins + EPSILON)
        or currentHunger > (storedHunger + EPSILON)
end

local function ensureSnapshot(item, reason, hintedFullType)
    if not item then
        return nil, nil, nil, nil, nil
    end

    local entry, fullType = getFoodEntry(hintedFullType or item)
    if not entry or not fullType then
        return nil, nil, nil, nil, nil
    end

    local current = readCurrentValues(item, fullType, entry)
    local expectedMode = getExpectedSnapshotMode(item, fullType, entry)
    local stored = readStoredSnapshot(item, fullType, entry)
    if stored and tostring(stored.snapshotMode or "") ~= tostring(expectedMode) then
        clearStoredSnapshot(item)
        stored = nil
    end
    if stored and expectedMode == SNAPSHOT_MODE_STATIC then
        local expectedSource = getStaticFoodValueSource()
        if tostring(stored.nutritionSource or "") ~= tostring(expectedSource) then
            clearStoredSnapshot(item)
            stored = nil
        end
    end

    if stored and expectedMode == SNAPSHOT_MODE_FLUID and shouldReseedFluidSnapshot(current, stored) then
        clearStoredSnapshot(item)
        stored = nil
    end

    if stored and expectedMode == SNAPSHOT_MODE_COMPOSED and (not snapshotHasNutrition(stored)) and snapshotHasNutrition(current) then
        clearStoredSnapshot(item)
        stored = nil
    end
    if stored and expectedMode == SNAPSHOT_MODE_COMPOSED and shouldReseedComposedSnapshot(current, stored) then
        log(string.format(
            "[ITEM_AUTHORITY_COMPOSED_RESEED] reason=%s item=%s stored_kcal=%.1f current_kcal=%.1f stored_hunger=%.3f current_hunger=%.3f",
            tostring(reason or "composed-reseed"),
            tostring(fullType),
            tonumber(stored.kcal or 0),
            tonumber(current and current.kcal or 0),
            tonumber(stored.hunger or 0),
            tonumber(current and current.hunger or 0)
        ))
        clearStoredSnapshot(item)
        stored = nil
    end

    if not stored then
        if expectedMode == SNAPSHOT_MODE_STATIC then
            stored = getDefaultValues(fullType, entry)
        elseif expectedMode == SNAPSHOT_MODE_FLUID then
            stored = buildFluidSeedSnapshot(item, fullType, entry, reason or "fluid-seed")
        elseif snapshotHasNutrition(current) then
            stored = buildCurrentComposedSnapshot(fullType, entry, current, reason or "composed-current-seed")
        else
            stored = buildEmptyComposedSnapshot(fullType, entry, reason or "composed-empty-seed")
        end

        if type(stored) ~= "table" or not writeStoredSnapshot(item, stored, fullType, entry) then
            warnAuthorityOnce(fullType, "snapshot-seed-failed")
            return nil, entry, fullType, expectedMode, current
        end
        stored = readStoredSnapshot(item, fullType, entry) or stored
    end

    return stored, entry, fullType, expectedMode, current
end

local function resolveComputedDisplaySnapshot(item, fullType, entry, allowCurrentFallback)
    local stored, _, _, _, current = ensureSnapshot(item, "computed-display", fullType)
    if not stored then
        if allowCurrentFallback then
            return current
        end
        return nil
    end

    local remainingFraction = resolveRemainingFraction(item, current, stored)
    return buildAppliedSnapshot(stored, remainingFraction)
end

resolveRemainingFraction = function(item, current, total)
    if current and current.remainingFraction ~= nil then
        return clamp01(current.remainingFraction)
    end

    local function tryRatio(currentValue, totalValue)
        local currentNumber = tonumber(currentValue)
        local totalNumber = tonumber(totalValue)
        if currentNumber == nil or totalNumber == nil or math.abs(totalNumber) <= EPSILON then
            return nil
        end
        return clamp01(math.abs(currentNumber / totalNumber))
    end

    local function tryExactSnapshotRatio()
        if not current or not total then
            return nil
        end
        return tryRatio(current.kcal, total.kcal)
            or tryRatio(current.carbs, total.carbs)
            or tryRatio(current.fats, total.fats)
            or tryRatio(current.proteins, total.proteins)
            or tryRatio(current.hunger, total.hunger)
            or tryRatio(current.baseHunger, total.baseHunger)
    end

    local currentMode = tostring(current and current.snapshotMode or "")
    local totalMode = tostring(total and total.snapshotMode or "")
    local exactSnapshotRatio = tryExactSnapshotRatio()
    if exactSnapshotRatio ~= nil
        and (currentMode == SNAPSHOT_MODE_COMPOSED
            or totalMode == SNAPSHOT_MODE_COMPOSED
            or currentMode == SNAPSHOT_MODE_FLUID
            or totalMode == SNAPSHOT_MODE_FLUID)
    then
        return exactSnapshotRatio
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

    if exactSnapshotRatio ~= nil then
        return exactSnapshotRatio
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
        snapshot_mode = totalSnapshot.snapshotMode,
        authority_target = totalSnapshot.authorityTarget,
    }, {
        fullType = totalSnapshot.fullType,
        nutritionSource = totalSnapshot.nutritionSource,
        snapshotMode = totalSnapshot.snapshotMode,
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
        carbProfile = totalSnapshot.carbProfile,
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
        snapshot_mode = snapshot.snapshotMode,
        authority_target = snapshot.authorityTarget,
    }, {
        fullType = snapshot.fullType,
        nutritionSource = snapshot.nutritionSource,
        snapshotMode = snapshot.snapshotMode,
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
        carbProfile = snapshot.carbProfile,
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
        snapshotMode = SNAPSHOT_MODE_COMPOSED,
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

local function measureAccumulatedPayload(fullType, entry, beforeValues, afterValues)
    if type(fullType) ~= "string" or fullType == "" then
        return nil
    end
    if type(beforeValues) ~= "table" or type(afterValues) ~= "table" then
        return nil
    end

    local hungerDelta = (tonumber(afterValues.hunger) or 0) - (tonumber(beforeValues.hunger) or 0)
    local baseHungerDelta = (tonumber(afterValues.baseHunger) or tonumber(afterValues.hunger) or 0)
        - (tonumber(beforeValues.baseHunger) or tonumber(beforeValues.hunger) or 0)
    local measured = normalizeSnapshot(fullType, entry, {
        fullType = fullType,
        nutritionSource = "computed",
        snapshotMode = SNAPSHOT_MODE_COMPOSED,
        sourceFullType = fullType,
        provenance = "vanilla-add",
        seedReason = "evolved-add-measured",
        hunger = math.min(0, hungerDelta),
        baseHunger = math.min(0, baseHungerDelta),
        kcal = math.max(0, (tonumber(afterValues.kcal) or 0) - (tonumber(beforeValues.kcal) or 0)),
        carbs = math.max(0, (tonumber(afterValues.carbs) or 0) - (tonumber(beforeValues.carbs) or 0)),
        fats = math.max(0, (tonumber(afterValues.fats) or 0) - (tonumber(beforeValues.fats) or 0)),
        proteins = math.max(0, (tonumber(afterValues.proteins) or 0) - (tonumber(beforeValues.proteins) or 0)),
    })
    if not snapshotHasNutrition(measured) then
        return nil
    end
    return measured
end

local function getBurntNutritionMultiplier(item)
    if safeCall(item, "isBurnt") == true then
        return 0.2
    end
    return 1
end

local function resolveAppliedSnapshot(item, fullType, entry)
    local stored, _, _, mode, current = ensureSnapshot(item, "resolve-applied", fullType)
    if not stored then
        return nil, current, nil, nil, nil
    end

    local remainingFraction = resolveRemainingFraction(item, current, stored)
    return buildAppliedSnapshot(stored, remainingFraction), current, stored, nil, mode
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
    elseif snapshot.remainingFraction ~= nil then
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
    local isClientRuntime = type(isClient) == "function" and isClient() == true
    local isServerRuntime = type(isServer) == "function" and isServer() == true
    if isServerRuntime and not isClientRuntime then
        safeCall(item, "syncItemFields")
    end
    return true
end

ItemAuthority.SNAPSHOT_KEY = SNAPSHOT_KEY
ItemAuthority.SNAPSHOT_VERSION = SNAPSHOT_VERSION

ItemAuthority.safeCall = safeCall
ItemAuthority.log = log
ItemAuthority.EPSILON = EPSILON
ItemAuthority.CONSUME_EPSILON = CONSUME_EPSILON
ItemAuthority.clamp01 = clamp01
ItemAuthority.getFoodEntry = getFoodEntry
ItemAuthority.resolveEntrySource = resolveEntrySource
ItemAuthority.hasVanillaDynamicValues = hasVanillaDynamicValues
ItemAuthority.getStaticFoodValueSource = getStaticFoodValueSource
ItemAuthority.readCurrentValuesPrivate = readCurrentValues
ItemAuthority.readStoredSnapshotPrivate = readStoredSnapshot
ItemAuthority.resolveSnapshotMode = getExpectedSnapshotMode
ItemAuthority.ensureSnapshot = ensureSnapshot
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
ItemAuthority.measureAccumulatedPayload = measureAccumulatedPayload
ItemAuthority.clearStoredSnapshot = clearStoredSnapshot
ItemAuthority.snapshotsMatch = snapshotsMatch
ItemAuthority.warnAuthorityOnce = warnAuthorityOnce
ItemAuthority.resolveAppliedSnapshot = resolveAppliedSnapshot
ItemAuthority.getEntrySnapshotMode = getEntrySnapshotMode
ItemAuthority.getEntryAction = getEntryAction
ItemAuthority.usesComposedSnapshots = usesComposedSnapshots
ItemAuthority.visitList = CoreUtils.visitList

local function loadItemAuthorityModule(moduleName, shortName)
    local ok, result = pcall(require, moduleName)
    if not ok then
        log(string.format(
            "[ITEM_AUTHORITY_LOAD_FAIL] module=%s detail=%s",
            tostring(shortName or moduleName),
            tostring(result)
        ))
        return false
    end
    log(string.format(
        "[ITEM_AUTHORITY_LOAD] module=%s ok=true",
        tostring(shortName or moduleName)
    ))
    return true
end

loadItemAuthorityModule("items/NutritionMakesSense_ItemAuthority_Query", "query")
loadItemAuthorityModule("items/NutritionMakesSense_ItemAuthority_Consume", "consume")
loadItemAuthorityModule("items/NutritionMakesSense_ItemAuthority_Computed", "computed")
loadItemAuthorityModule("items/NutritionMakesSense_ItemAuthority_Traversal", "traversal")
loadItemAuthorityModule("items/NutritionMakesSense_ItemAuthority_Lifecycle", "lifecycle")

log(string.format(
    "[ITEM_AUTHORITY_APIS] gameplay=%s legacy=%s computed=%s lifecycle=%s",
    tostring(type(ItemAuthority.resolveGameplayConsumeContext) == "function"),
    tostring(type(ItemAuthority.resolveConsumedPayload) == "function"),
    tostring(type(ItemAuthority.accumulateDynamicPayload) == "function"),
    tostring(type(ItemAuthority.install) == "function")
))

if type(ItemAuthority.resolveGameplayConsumeContext) ~= "function"
    or type(ItemAuthority.resolveConsumedPayload) ~= "function"
    or type(ItemAuthority.accumulateDynamicPayload) ~= "function"
    or type(ItemAuthority.install) ~= "function"
then
    error(string.format(
        "[NMS_BOOT_HARD_FAIL] ItemAuthority gameplay=%s legacy=%s computed=%s lifecycle=%s",
        tostring(type(ItemAuthority.resolveGameplayConsumeContext) == "function"),
        tostring(type(ItemAuthority.resolveConsumedPayload) == "function"),
        tostring(type(ItemAuthority.accumulateDynamicPayload) == "function"),
        tostring(type(ItemAuthority.install) == "function")
    ))
end

return ItemAuthority
