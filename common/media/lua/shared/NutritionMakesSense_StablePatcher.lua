NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_Data"

local StablePatcher = NutritionMakesSense.StablePatcher or {}
NutritionMakesSense.StablePatcher = StablePatcher

local EPSILON = 0.001
local HUNGER_TO_RUNTIME_SCALE = 0.01
local MAX_PROBE_FAILURE_LOGS = 8
local PROBE_UNAVAILABLE_ERR = "InventoryItemFactory.CreateItem unavailable"

local function log(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(msg)
    else
        print("[NutritionMakesSense] " .. tostring(msg))
    end
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

local function addIssue(bucket, itemId, detail)
    bucket[#bucket + 1] = {
        item_id = itemId,
        detail = detail,
    }
end

local function numbersClose(a, b)
    if a == nil or b == nil then
        return false
    end
    return math.abs(tonumber(a) - tonumber(b)) <= EPSILON
end

local function getFoodProbe(itemId)
    if not InventoryItemFactory or type(InventoryItemFactory.CreateItem) ~= "function" then
        return nil, "InventoryItemFactory.CreateItem unavailable"
    end

    local item = InventoryItemFactory.CreateItem(itemId)
    if not item then
        return nil, "CreateItem returned nil"
    end

    if type(item.isFood) == "function" and not item:isFood() then
        return nil, "CreateItem returned a non-food item"
    end

    return item
end

local function probePatchedItem(itemId, expected)
    local food, err = getFoodProbe(itemId)
    if not food then
        return false, err
    end

    local observedBaseHunger = type(food.getBaseHunger) == "function" and food:getBaseHunger() or nil
    local observedHungChange = type(food.getHungChange) == "function" and food:getHungChange() or nil
    local observedCalories = type(food.getCalories) == "function" and food:getCalories() or nil
    local observedCarbs = type(food.getCarbohydrates) == "function" and food:getCarbohydrates() or nil
    local observedFats = type(food.getLipids) == "function" and food:getLipids() or nil
    local observedProteins = type(food.getProteins) == "function" and food:getProteins() or nil

    local hungerMatches = numbersClose(observedBaseHunger, expected.runtimeHunger) or numbersClose(observedHungChange, expected.runtimeHunger)
    local matches = hungerMatches
        and numbersClose(observedCalories, expected.kcal)
        and numbersClose(observedCarbs, expected.carbs)
        and numbersClose(observedFats, expected.fats)
        and numbersClose(observedProteins, expected.proteins)

    if matches then
        return true
    end

    local detail = string.format(
        "observed base=%s hung=%s kcal=%s carbs=%s fats=%s proteins=%s expected hunger=%s kcal=%s carbs=%s fats=%s proteins=%s",
        tostring(observedBaseHunger),
        tostring(observedHungChange),
        tostring(observedCalories),
        tostring(observedCarbs),
        tostring(observedFats),
        tostring(observedProteins),
        tostring(expected.runtimeHunger),
        tostring(expected.kcal),
        tostring(expected.carbs),
        tostring(expected.fats),
        tostring(expected.proteins)
    )
    return false, detail
end

local function toExpectedValues(values)
    return {
        hunger = tonumber(values.hunger),
        runtimeHunger = (tonumber(values.hunger) or 0) * HUNGER_TO_RUNTIME_SCALE,
        kcal = tonumber(values.kcal),
        carbs = tonumber(values.carbs),
        fats = tonumber(values.fats),
        proteins = tonumber(values.proteins),
    }
end

local function snapshotScriptItem(scriptItem)
    if not scriptItem then
        return {}
    end

    local hungerChange = nil
    if type(scriptItem.getHungerChange) == "function" then
        hungerChange = scriptItem:getHungerChange()
    elseif scriptItem.hungerChange ~= nil then
        hungerChange = scriptItem.hungerChange
    end

    local calories = nil
    if type(scriptItem.getCalories) == "function" then
        calories = scriptItem:getCalories()
    elseif scriptItem.calories ~= nil then
        calories = scriptItem.calories
    end

    local carbs = nil
    if type(scriptItem.getCarbohydrates) == "function" then
        carbs = scriptItem:getCarbohydrates()
    elseif scriptItem.carbohydrates ~= nil then
        carbs = scriptItem.carbohydrates
    end

    local fats = nil
    if type(scriptItem.getLipids) == "function" then
        fats = scriptItem:getLipids()
    elseif scriptItem.lipids ~= nil then
        fats = scriptItem.lipids
    end

    local proteins = nil
    if type(scriptItem.getProteins) == "function" then
        proteins = scriptItem:getProteins()
    elseif scriptItem.proteins ~= nil then
        proteins = scriptItem.proteins
    end

    return {
        hungerChange = hungerChange,
        calories = calories,
        carbs = carbs,
        fats = fats,
        proteins = proteins,
    }
end

local function patchScriptItem(scriptItem, expected)
    scriptItem:DoParam("HungerChange = " .. tostring(expected.hunger))
    scriptItem:DoParam("Calories = " .. tostring(expected.kcal))
    scriptItem:DoParam("Carbohydrates = " .. tostring(expected.carbs))
    scriptItem:DoParam("Lipids = " .. tostring(expected.fats))
    scriptItem:DoParam("Proteins = " .. tostring(expected.proteins))
end

local function buildRuntimeReport(data, context)
    local entries = {}
    local stableClassTotals = {}
    local actionTotals = {}
    for _, entry in pairs(data.runtimeEntriesByItemId or {}) do
        if type(entry) == "table" and entry.item_id then
            entries[#entries + 1] = entry
            local semanticClass = tostring(entry.semantic_class or "unknown")
            local action = tostring(entry.action or "unknown")
            stableClassTotals[semanticClass] = (tonumber(stableClassTotals[semanticClass]) or 0) + 1
            actionTotals[action] = (tonumber(actionTotals[action]) or 0) + 1
        end
    end
    table.sort(entries, function(a, b)
        return tostring(a.item_id or "") < tostring(b.item_id or "")
    end)

    return {
        modId = data.baseModId or data.modId,
        activeModId = data.modId,
        context = context,
        stableClassTotals = stableClassTotals,
        actionTotals = actionTotals,
        directFoodValidation = {},
        deferredRuntimeRows = {},
        explicitRouteExceptions = {},
        entries = entries,
        validation = {
            duplicateStableRows = {},
            patchedRowsMissingValues = {},
            routeAuthorityConflicts = {},
            missingScriptItems = {},
            patchFailures = {},
            probeFailures = {},
            deferredProbeFailures = {},
        },
        patchedRows = 0,
        routedRows = 0,
        explicitExceptionRows = 0,
        deferredProbeRows = 0,
    }
end

local function validateStaticReport(runtimeReport)
    return true
end

function StablePatcher.ensurePatched(context)
    if StablePatcher._report then
        return StablePatcher._report
    end
    if StablePatcher._failedReport then
        error(StablePatcher._failedError or "stable patch validation previously failed")
    end

    local data = NutritionMakesSense.Data.loadRuntimeData(false)
    local runtimeReport = buildRuntimeReport(data, context or "unknown")
    local reportOkay, reportErr = validateStaticReport(runtimeReport)
    if not reportOkay then
        error(reportErr)
    end

    local scriptManager = getScriptManagerHandle()
    if not scriptManager or type(scriptManager.getItem) ~= "function" then
        error("ScriptManager.getItem unavailable during stable patching")
    end

    for _, entry in ipairs(runtimeReport.entries) do
        if entry.action == "patched" then
            local expectedValues = data.valuesByItemId[entry.patch_source or entry.item_id]
            if not expectedValues then
                addIssue(runtimeReport.validation.patchedRowsMissingValues, entry.item_id, "missing curated runtime values")
            else
                local scriptItem = scriptManager:getItem(entry.item_id)
                if not scriptItem then
                    addIssue(runtimeReport.validation.missingScriptItems, entry.item_id, "script item not found")
                else
                    local expected = toExpectedValues(expectedValues)
                    local ok, patchErr = pcall(patchScriptItem, scriptItem, expected)
                    if not ok then
                        addIssue(runtimeReport.validation.patchFailures, entry.item_id, patchErr)
                    else
                        local probeOkay, probeErr = probePatchedItem(entry.item_id, expected)
                        if not probeOkay then
                            if probeErr == PROBE_UNAVAILABLE_ERR then
                                addIssue(runtimeReport.validation.deferredProbeFailures, entry.item_id, probeErr)
                                runtimeReport.deferredProbeRows = runtimeReport.deferredProbeRows + 1
                                runtimeReport.patchedRows = runtimeReport.patchedRows + 1
                            else
                                addIssue(runtimeReport.validation.probeFailures, entry.item_id, probeErr)
                                if #runtimeReport.validation.probeFailures <= MAX_PROBE_FAILURE_LOGS then
                                    local scriptSnapshot = snapshotScriptItem(scriptItem)
                                    log(string.format(
                                        "[STABLE_PATCH_PROBE_FAIL] item=%s scriptHunger=%s scriptKcal=%s scriptCarbs=%s scriptFats=%s scriptProteins=%s expectedScriptHunger=%s expectedRuntimeHunger=%s expectedKcal=%s detail=%s",
                                        tostring(entry.item_id),
                                        tostring(scriptSnapshot.hungerChange),
                                        tostring(scriptSnapshot.calories),
                                        tostring(scriptSnapshot.carbs),
                                        tostring(scriptSnapshot.fats),
                                        tostring(scriptSnapshot.proteins),
                                        tostring(expected.hunger),
                                        tostring(expected.runtimeHunger),
                                        tostring(expected.kcal),
                                        tostring(probeErr)
                                    ))
                                end
                            end
                        else
                            runtimeReport.patchedRows = runtimeReport.patchedRows + 1
                        end
                    end
                end
            end
        elseif entry.action == "routed" then
            runtimeReport.routedRows = runtimeReport.routedRows + 1
        else
            runtimeReport.explicitExceptionRows = runtimeReport.explicitExceptionRows + 1
        end
    end

    local validation = runtimeReport.validation
    local hasErrors = #validation.patchedRowsMissingValues > 0
        or #validation.missingScriptItems > 0
        or #validation.patchFailures > 0
        or #validation.probeFailures > 0

    NutritionMakesSense.runtimeData = data
    NutritionMakesSense.stablePatchReport = runtimeReport

    log(string.format(
        "[STABLE_PATCH_REPORT] mod=%s active=%s context=%s patched=%d deferred=%d runtime=%d explicit=%d direct=%s whole=%s open=%s composed=%s",
        tostring(runtimeReport.modId),
        tostring(runtimeReport.activeModId),
        tostring(runtimeReport.context),
        runtimeReport.patchedRows,
        runtimeReport.deferredProbeRows,
        tonumber(runtimeReport.actionTotals and runtimeReport.actionTotals.authored_runtime or 0),
        runtimeReport.explicitExceptionRows,
        tostring(runtimeReport.stableClassTotals.direct_food or 0),
        tostring(runtimeReport.stableClassTotals.whole_multiportion or 0),
        tostring(runtimeReport.stableClassTotals.open_edible_container or 0),
        tostring(runtimeReport.stableClassTotals.runtime_composed_output or 0)
    ))

    if hasErrors then
        StablePatcher._failedReport = runtimeReport
        StablePatcher._failedError = string.format(
            "stable patch validation failed (missingScriptItems=%d patchFailures=%d probeFailures=%d missingValues=%d)",
            #validation.missingScriptItems,
            #validation.patchFailures,
            #validation.probeFailures,
            #validation.patchedRowsMissingValues
        )
        error(StablePatcher._failedError)
    end

    StablePatcher._report = runtimeReport
    return runtimeReport
end

return StablePatcher
