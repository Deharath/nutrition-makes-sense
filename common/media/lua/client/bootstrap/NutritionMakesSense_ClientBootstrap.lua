NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_DebugSupport"
require "NutritionMakesSense_ItemAuthority"
require "NutritionMakesSense_CoreUtils"

local ClientBootstrap = NutritionMakesSense.ClientBootstrap or {}
NutritionMakesSense.ClientBootstrap = ClientBootstrap
local CoreUtils = NutritionMakesSense.CoreUtils or {}

local TAG = "[NutritionMakesSense]"
local DEV_PANEL_HOTKEY = Keyboard and Keyboard.KEY_NUMPAD6 or nil
local TOOL_PANEL_HOTKEY = Keyboard and Keyboard.KEY_NUMPAD7 or nil
local TEST_PANEL_HOTKEY = Keyboard and Keyboard.KEY_NUMPAD8 or nil
local DebugSupport = NutritionMakesSense.DebugSupport or {}

local function log(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(msg)
    else
        print(TAG .. " " .. tostring(msg))
    end
end

local function logError(where, err)
    log("[ERROR] " .. tostring(where) .. ": " .. tostring(err))
end

local safeCall = CoreUtils.safeCall

local function formatNumber(value, precision)
    local numeric = tonumber(value)
    if numeric == nil then
        return "nil"
    end
    return string.format("%." .. tostring(precision or 3) .. "f", numeric)
end

local function formatBool(value)
    if value == nil then
        return "nil"
    end
    return value and "true" or "false"
end

local function formatValues(values)
    if type(values) ~= "table" then
        return "nil"
    end
    return string.format(
        "hunger=%s kcal=%s carbs=%s fats=%s proteins=%s",
        formatNumber(values.hunger, 3),
        formatNumber(values.kcal, 1),
        formatNumber(values.carbs, 3),
        formatNumber(values.fats, 3),
        formatNumber(values.proteins, 3)
    )
end

local FOOD_VALUE_KEYS = { "hunger", "kcal", "carbs", "fats", "proteins" }

local function formatSignedNumber(value, precision)
    local numeric = tonumber(value)
    if numeric == nil then
        return "nil"
    end
    return string.format("%+." .. tostring(precision or 3) .. "f", numeric)
end

local function joinParts(parts, separator)
    if type(parts) ~= "table" or #parts <= 0 then
        return ""
    end
    return table.concat(parts, separator or " | ")
end

local function formatSnapshotMeta(snapshot)
    if type(snapshot) ~= "table" then
        return "nil"
    end
    return string.format(
        "mode=%s source=%s provenance=%s seed=%s fullType=%s sourceFullType=%s authorityTarget=%s rem=%s",
        tostring(snapshot.snapshotMode or snapshot.snapshot_mode or "nil"),
        tostring(snapshot.nutritionSource or snapshot.nutrition_source or "nil"),
        tostring(snapshot.provenance or "nil"),
        tostring(snapshot.seedReason or "nil"),
        tostring(snapshot.fullType or "nil"),
        tostring(snapshot.sourceFullType or "nil"),
        tostring(snapshot.authorityTarget or "nil"),
        formatNumber(snapshot.remainingFraction, 3)
    )
end

local function formatDeltaLine(lhs, rhs)
    local function delta(key)
        return (tonumber(lhs and lhs[key]) or 0) - (tonumber(rhs and rhs[key]) or 0)
    end
    return string.format(
        "dhunger=%s dkcal=%s dcarbs=%s dfats=%s dproteins=%s",
        formatNumber(delta("hunger"), 3),
        formatNumber(delta("kcal"), 3),
        formatNumber(delta("carbs"), 3),
        formatNumber(delta("fats"), 3),
        formatNumber(delta("proteins"), 3)
    )
end

local function formatPercent(value)
    local numeric = tonumber(value)
    if numeric == nil then
        return "nil"
    end
    return string.format("%.1f%%", numeric * 100.0)
end

local function resolveMoodDynamicDelta(runtimeValue, unmodifiedValue)
    local runtime = tonumber(runtimeValue)
    local unmodified = tonumber(unmodifiedValue)
    if runtime == nil or unmodified == nil then
        return nil
    end
    return runtime - unmodified
end

local function nearlyEqual(lhs, rhs, epsilon)
    local left = tonumber(lhs)
    local right = tonumber(rhs)
    if left == nil or right == nil then
        return left == right
    end
    return math.abs(left - right) <= (epsilon or 0.0005)
end

local function valuesDiffer(lhs, rhs)
    if lhs == nil and rhs == nil then
        return false
    end
    if type(lhs) ~= "table" or type(rhs) ~= "table" then
        return lhs ~= rhs
    end

    for _, key in ipairs(FOOD_VALUE_KEYS) do
        if not nearlyEqual(lhs[key], rhs[key]) then
            return true
        end
    end

    return false
end

local function shouldLogAuthorityDump(display, applied, current, stored, expectedMode, resolvedMode)
    if expectedMode ~= nil and resolvedMode ~= nil and tostring(expectedMode) ~= tostring(resolvedMode) then
        return true
    end

    return valuesDiffer(display, applied)
        or valuesDiffer(display, current)
        or valuesDiffer(display, stored)
        or valuesDiffer(applied, current)
        or valuesDiffer(applied, stored)
        or valuesDiffer(current, stored)
end

local function flattenCollectionEntries(collection)
    local entries = {}
    if collection == nil then
        return entries
    end

    if type(collection) == "table" then
        local count = 0
        for _, entry in ipairs(collection) do
            entries[#entries + 1] = entry
            count = count + 1
        end
        if count > 0 then
            return entries
        end
        for _, entry in pairs(collection) do
            entries[#entries + 1] = entry
        end
        return entries
    end

    local size = tonumber(safeCall(collection, "size"))
    if size == nil then
        return entries
    end

    for i = 0, size - 1 do
        entries[#entries + 1] = safeCall(collection, "get", i)
    end
    return entries
end

local function summarizeCollection(collection)
    local entries = flattenCollectionEntries(collection)
    local counts = {}
    local order = {}
    local total = 0

    for _, entry in ipairs(entries) do
        local token = tostring(entry or "")
        if token ~= "" and token ~= "nil" then
            if counts[token] == nil then
                counts[token] = 0
                order[#order + 1] = token
            end
            counts[token] = counts[token] + 1
            total = total + 1
        end
    end

    local listed = {}
    local duplicates = {}
    for _, token in ipairs(order) do
        local count = counts[token]
        local part = token .. " x" .. tostring(count)
        listed[#listed + 1] = part
        if count > 1 then
            duplicates[#duplicates + 1] = part
        end
    end

    return {
        total = total,
        distinct = #order,
        listed = #listed > 0 and table.concat(listed, ", ") or "none",
        duplicates = #duplicates > 0 and table.concat(duplicates, ", ") or "none",
    }
end

local function hasGoodFrozenMood(item)
    local itemType = tostring(safeCall(item, "getType") or "")
    if itemType == "Icecream" then
        return true
    end
    if safeCall(item, "hasTag", "GOOD_FROZEN") == true then
        return true
    end
    if ItemTag and ItemTag.GOOD_FROZEN and safeCall(item, "hasTag", ItemTag.GOOD_FROZEN) == true then
        return true
    end
    return false
end

local function formatMoodContributorSummary(item, context)
    local boredomParts = {}
    local unhappyParts = {}

    local function addBoth(label, amount)
        local part = label .. " " .. formatSignedNumber(amount, 0)
        boredomParts[#boredomParts + 1] = part
        unhappyParts[#unhappyParts + 1] = part
    end

    local function addUnhappy(label, amount)
        unhappyParts[#unhappyParts + 1] = label .. " " .. formatSignedNumber(amount, 0)
    end

    if context.frozen and not hasGoodFrozenMood(item) then
        addBoth("frozen", 30)
    end
    if context.burnt then
        addBoth("burnt", 20)
    end
    if context.ageBand == "stale" then
        addBoth("stale", 10)
    elseif context.ageBand == "rotten" then
        addBoth("rotten", 20)
    end

    local heat = tonumber(context.heat) or 0
    if context.badCold and context.cookable and context.cooked and heat < 1.3 then
        addUnhappy("badCold", 2)
    end
    if context.goodHot and context.cookable and context.cooked and heat > 1.3 then
        addUnhappy("goodHot", -2)
    end

    return #boredomParts > 0 and table.concat(boredomParts, ", ") or "none",
        #unhappyParts > 0 and table.concat(unhappyParts, ", ") or "none"
end

local function choosePrimaryValues(display, current, applied, stored)
    if type(display) == "table" then
        return display, "display"
    end
    if type(current) == "table" then
        return current, "current"
    end
    if type(applied) == "table" then
        return applied, "applied"
    end
    if type(stored) == "table" then
        return stored, "stored"
    end
    return nil, "none"
end

local function resolveActualItems(items)
    if ISInventoryPane and type(ISInventoryPane.getActualItems) == "function" then
        local ok, actual = pcall(ISInventoryPane.getActualItems, items)
        if ok and type(actual) == "table" then
            return actual
        end
    end

    local actual = {}
    for _, item in ipairs(items or {}) do
        if item and item.items and type(item.items) == "table" then
            for _, grouped in ipairs(item.items) do
                actual[#actual + 1] = grouped
            end
        elseif item then
            actual[#actual + 1] = item
        end
    end
    return actual
end

local function isFoodItem(item)
    return safeCall(item, "isFood") == true or safeCall(item, "IsFood") == true
end

local function makeFoodProbe(fullType)
    if not fullType or not InventoryItemFactory or type(InventoryItemFactory.CreateItem) ~= "function" then
        return nil
    end
    local ok, probe = pcall(InventoryItemFactory.CreateItem, fullType)
    if not ok or not probe then
        return nil
    end
    if safeCall(probe, "isFood") == false and safeCall(probe, "IsFood") == false then
        return nil
    end
    return probe
end

local function logFoodItemDebug(item)
    local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
    local fullType = safeCall(item, "getFullType") or tostring(item)
    local itemId = ItemAuthority.getItemId and ItemAuthority.getItemId(item) or tonumber(safeCall(item, "getID"))
    local displayName = safeCall(item, "getDisplayName") or fullType
    local display = ItemAuthority.getDisplayValues and ItemAuthority.getDisplayValues(item) or nil
    local debugSnapshot = ItemAuthority.getDebugSnapshot and ItemAuthority.getDebugSnapshot(item) or nil
    local applied = debugSnapshot and debugSnapshot.applied or nil
    local current = debugSnapshot and debugSnapshot.current or nil
    local stored = debugSnapshot and debugSnapshot.stored or nil
    local resolvedMode = debugSnapshot and debugSnapshot.resolvedMode or nil
    local expectedMode = debugSnapshot and debugSnapshot.expectedMode or nil
    local authorityKind = debugSnapshot and debugSnapshot.authorityKind or nil
    local portionKind = debugSnapshot and debugSnapshot.portionKind or nil
    local authorityTarget = debugSnapshot and debugSnapshot.authorityTarget or nil
    local patchSource = debugSnapshot and debugSnapshot.patchSource or nil
    local source = debugSnapshot and debugSnapshot.source or nil
    local resolvedSource = ItemAuthority.getResolvedNutritionSource and ItemAuthority.getResolvedNutritionSource(item) or nil
    local moodBoredom = safeCall(item, "getBoredomChange")
    local moodBoredomUnmodified = safeCall(item, "getBoredomChangeUnmodified")
    local moodUnhappy = safeCall(item, "getUnhappyChange")
    local moodUnhappyUnmodified = safeCall(item, "getUnhappyChangeUnmodified")
    local moodBoredomDelta = resolveMoodDynamicDelta(moodBoredom, moodBoredomUnmodified)
    local moodUnhappyDelta = resolveMoodDynamicDelta(moodUnhappy, moodUnhappyUnmodified)
    local frozen = safeCall(item, "isFrozen") == true
    local burnt = safeCall(item, "isBurnt") == true
    local cooked = safeCall(item, "isCooked") == true
    local cookable = safeCall(item, "isCookable") == true
    local badCold = safeCall(item, "isBadCold") == true
    local goodHot = safeCall(item, "isGoodHot") == true
    local canBeFrozen = safeCall(item, "canBeFrozen")
    local freezingTime = safeCall(item, "getFreezingTime")
    local heat = safeCall(item, "getHeat")
    local age = tonumber(safeCall(item, "getAge")) or 0
    local offAge = tonumber(safeCall(item, "getOffAge")) or 0
    local offAgeMax = tonumber(safeCall(item, "getOffAgeMax")) or 0
    local ageBand = "fresh"
    if offAgeMax > 0 and age >= offAgeMax then
        ageBand = "rotten"
    elseif offAge > 0 and age >= offAge then
        ageBand = "stale"
    end
    local scriptItem = safeCall(item, "getScriptItem")
    local scriptMoodBoredom = safeCall(scriptItem, "getBoredomChange")
    local scriptMoodUnhappy = safeCall(scriptItem, "getUnhappyChange")
    local probe = makeFoodProbe(fullType)
    local probeMoodBoredom = safeCall(probe, "getBoredomChange")
    local probeMoodBoredomUnmodified = safeCall(probe, "getBoredomChangeUnmodified")
    local probeMoodUnhappy = safeCall(probe, "getUnhappyChange")
    local probeMoodUnhappyUnmodified = safeCall(probe, "getUnhappyChangeUnmodified")
    local thirst = safeCall(item, "getThirstChange")
    local thirstUnmodified = safeCall(item, "getThirstChangeUnmodified")
    local scriptThirst = safeCall(scriptItem, "getThirstChange")
    local probeThirst = safeCall(probe, "getThirstChange")
    local probeThirstUnmodified = safeCall(probe, "getThirstChangeUnmodified")
    local chef = tostring(safeCall(item, "getChef") or "")
    if chef == "" then
        chef = "nil"
    end
    local ingredients = summarizeCollection(safeCall(item, "getExtraItems"))
    local spices = summarizeCollection(safeCall(item, "getSpices"))
    local boredomContribSummary, unhappyContribSummary = formatMoodContributorSummary(item, {
        ageBand = ageBand,
        frozen = frozen,
        burnt = burnt,
        cooked = cooked,
        cookable = cookable,
        badCold = badCold,
        goodHot = goodHot,
        heat = heat,
    })
    local primaryValues, primaryLabel = choosePrimaryValues(display, current, applied, stored)
    local authorityMismatch = shouldLogAuthorityDump(display, applied, current, stored, expectedMode, resolvedMode)
    local scriptBoredomDelta = nil
    local scriptUnhappyDelta = nil
    if tonumber(moodBoredomUnmodified) ~= nil and tonumber(scriptMoodBoredom) ~= nil then
        scriptBoredomDelta = (tonumber(moodBoredomUnmodified) or 0) - (tonumber(scriptMoodBoredom) or 0)
    end
    if tonumber(moodUnhappyUnmodified) ~= nil and tonumber(scriptMoodUnhappy) ~= nil then
        scriptUnhappyDelta = (tonumber(moodUnhappyUnmodified) or 0) - (tonumber(scriptMoodUnhappy) or 0)
    end

    log(string.format(
        "[FOOD_DEBUG] item=%s name=%s id=%s state=cooked:%s burnt:%s frozen:%s rotten:%s ageBand=%s heat=%s uses=%s/%s",
        tostring(fullType),
        tostring(displayName),
        tostring(itemId or "nil"),
        formatBool(cooked),
        formatBool(burnt),
        formatBool(frozen),
        formatBool(safeCall(item, "isRotten")),
        tostring(ageBand),
        formatNumber(heat, 3),
        formatNumber(safeCall(item, "getCurrentUses"), 3),
        formatNumber(safeCall(item, "getMaxUses"), 3)
    ))

    local nutritionParts = {
        "source=" .. tostring(resolvedSource or source or "nil"),
        "authority=" .. tostring(authorityKind or "nil"),
        "portion=" .. tostring(portionKind or "nil"),
        "mode=" .. tostring(resolvedMode or expectedMode or "nil"),
        primaryLabel .. "=" .. formatValues(primaryValues),
        "raw=" .. formatValues({
            hunger = safeCall(item, "getHungChange") or safeCall(item, "getHungerChange"),
            kcal = safeCall(item, "getCalories"),
            carbs = safeCall(item, "getCarbohydrates"),
            fats = safeCall(item, "getLipids"),
            proteins = safeCall(item, "getProteins"),
        }),
        "thirst=" .. formatNumber(thirst, 3),
    }
    if type(primaryValues) == "table" and type(current) == "table" and valuesDiffer(primaryValues, current) then
        nutritionParts[#nutritionParts + 1] = "live=" .. formatValues(current)
    end
    log("[FOOD_DEBUG] nutrition " .. joinParts(nutritionParts))

    local authorityParts = {
        "status=" .. (authorityMismatch and "mismatch" or "aligned"),
        "expected=" .. tostring(expectedMode or "nil"),
        "resolved=" .. tostring(resolvedMode or "nil"),
        "patch=" .. tostring(patchSource or "nil"),
        "target=" .. tostring(authorityTarget or "nil"),
    }
    log("[FOOD_DEBUG] authority " .. joinParts(authorityParts))

    log(string.format(
        "[FOOD_DEBUG] mood current boredom=%s unhappy=%s | unmodified boredom=%s unhappy=%s | script boredom=%s unhappy=%s",
        formatNumber(moodBoredom, 3),
        formatNumber(moodUnhappy, 3),
        formatNumber(moodBoredomUnmodified, 3),
        formatNumber(moodUnhappyUnmodified, 3),
        formatNumber(scriptMoodBoredom, 3),
        formatNumber(scriptMoodUnhappy, 3)
    ))
    log(string.format(
        "[FOOD_DEBUG] mood provenance boredom dynamic=%s itemVsScript=%s | unhappy dynamic=%s itemVsScript=%s",
        tostring(boredomContribSummary),
        formatSignedNumber(scriptBoredomDelta, 3),
        tostring(unhappyContribSummary),
        formatSignedNumber(scriptUnhappyDelta, 3)
    ))

    local compositionParts = {
        "ingredients=" .. tostring(ingredients.total) .. " [" .. ingredients.listed .. "]",
        "duplicates=" .. ingredients.duplicates,
        "spices=" .. tostring(spices.total) .. " [" .. spices.listed .. "]",
        "chef=" .. chef,
    }
    log("[FOOD_DEBUG] composition " .. joinParts(compositionParts))

    if not authorityMismatch then
        return
    end

    log("[FOOD_DEBUG] display " .. formatValues(display))
    log("[FOOD_DEBUG] applied " .. formatValues(applied))
    log("[FOOD_DEBUG] current " .. formatValues(current))
    log("[FOOD_DEBUG] stored  " .. formatValues(stored))
    log("[FOOD_DEBUG] meta display " .. formatSnapshotMeta(display))
    log("[FOOD_DEBUG] meta applied " .. formatSnapshotMeta(applied))
    log("[FOOD_DEBUG] meta current " .. formatSnapshotMeta(current))
    log("[FOOD_DEBUG] meta stored  " .. formatSnapshotMeta(stored))
    log(string.format(
        "[FOOD_DEBUG] mood baselines probeBoredom=%s probeBoredomUnmod=%s probeUnhappy=%s probeUnhappyUnmod=%s scriptThirst=%s probeThirst=%s probeThirstUnmod=%s canBeFrozen=%s freezingTime=%s badCold=%s goodHot=%s",
        formatNumber(probeMoodBoredom, 3),
        formatNumber(probeMoodBoredomUnmodified, 3),
        formatNumber(probeMoodUnhappy, 3),
        formatNumber(probeMoodUnhappyUnmodified, 3),
        formatNumber(scriptThirst, 3),
        formatNumber(probeThirst, 3),
        formatNumber(probeThirstUnmodified, 3),
        tostring(canBeFrozen),
        formatNumber(freezingTime, 3),
        formatBool(badCold),
        formatBool(goodHot)
    ))
    log("[FOOD_DEBUG] delta current-stored " .. formatDeltaLine(current, stored))
    log("[FOOD_DEBUG] delta current-applied " .. formatDeltaLine(current, applied))
    log("[FOOD_DEBUG] delta applied-stored " .. formatDeltaLine(applied, stored))
end

local function tryLoadDevModule(globalKey, requirePath, label)
    if NutritionMakesSense[globalKey] then
        return true
    end

    local ok, result = pcall(require, requirePath)
    if ok then
        return true
    end

    local err = tostring(result)
    if string.find(string.lower(err), "not found", 1, true) then
        return false
    end

    logError("require " .. tostring(label), err)
    return false
end

local function tryLoadDevPanel()
    return tryLoadDevModule("DevPanel", "dev/NutritionMakesSense_DevPanel", "DevPanel")
end

local function tryLoadToolPanel()
    return tryLoadDevModule("ToolPanel", "dev/NutritionMakesSense_ToolPanel", "ToolPanel")
end

local function tryLoadTestPanel()
    return tryLoadDevModule("TestPanel", "dev/NutritionMakesSense_TestPanel", "TestPanel")
end

local function canUseDevPanel()
    if not tryLoadDevPanel() then
        return false
    end

    return DebugSupport.canUseDevTools and DebugSupport.canUseDevTools() or false
end

local function toggleLoadedPanel(tryLoad, globalKey, label)
    tryLoad()
    local panel = NutritionMakesSense[globalKey]
    if not panel or type(panel.toggle) ~= "function" then
        log(string.lower(tostring(label)) .. " unavailable")
        return
    end

    local ok, err = pcall(panel.toggle)
    if not ok then
        logError("toggle" .. tostring(label), err)
    end
end

local function onGameBoot()
    if canUseDevPanel() then
        tryLoadToolPanel()
        tryLoadTestPanel()
    end
    if DEV_PANEL_HOTKEY and NutritionMakesSense.DevPanel then
        log("dev panel hotkey available: Numpad 6")
    end
    if TOOL_PANEL_HOTKEY and NutritionMakesSense.ToolPanel then
        log("tool panel hotkey available: Numpad 7")
    end
    if TEST_PANEL_HOTKEY and NutritionMakesSense.TestPanel then
        log("test panel hotkey available: Numpad 8")
    end
end

local function onKeyPressed(key)
    if not canUseDevPanel() then
        return
    end
    if DEV_PANEL_HOTKEY and key == DEV_PANEL_HOTKEY then
        toggleLoadedPanel(tryLoadDevPanel, "DevPanel", "DevPanel")
        return
    end
    if TOOL_PANEL_HOTKEY and key == TOOL_PANEL_HOTKEY then
        toggleLoadedPanel(tryLoadToolPanel, "ToolPanel", "ToolPanel")
        return
    end
    if TEST_PANEL_HOTKEY and key == TEST_PANEL_HOTKEY then
        toggleLoadedPanel(tryLoadTestPanel, "TestPanel", "TestPanel")
    end
end

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    if not canUseDevPanel() then
        return
    end
    if test and ISWorldObjectContextMenu and ISWorldObjectContextMenu.Test then
        return true
    end
    context:addDebugOption("NMS Dev Panel", nil, function() toggleLoadedPanel(tryLoadDevPanel, "DevPanel", "DevPanel") end)
    context:addDebugOption("NMS Tool Panel", nil, function() toggleLoadedPanel(tryLoadToolPanel, "ToolPanel", "ToolPanel") end)
    context:addDebugOption("NMS Test Panel", nil, function() toggleLoadedPanel(tryLoadTestPanel, "TestPanel", "TestPanel") end)
end

local function onFillInventoryObjectContextMenu(player, context, items)
    if not canUseDevPanel() then
        return
    end

    local actualItems = resolveActualItems(items)
    if #actualItems ~= 1 then
        return
    end

    local item = actualItems[1]
    if not item or not isFoodItem(item) then
        return
    end

    context:addDebugOption("NMS Log Food Item", item, logFoodItemDebug)
end

function ClientBootstrap.isDevPanelEnabled()
    return canUseDevPanel()
end

function ClientBootstrap.toggleDevPanel()
    toggleLoadedPanel(tryLoadDevPanel, "DevPanel", "DevPanel")
end

function ClientBootstrap.toggleToolPanel()
    toggleLoadedPanel(tryLoadToolPanel, "ToolPanel", "ToolPanel")
end

function ClientBootstrap.toggleTestPanel()
    toggleLoadedPanel(tryLoadTestPanel, "TestPanel", "TestPanel")
end

local function install()
    if ClientBootstrap._installed then
        return ClientBootstrap
    end
    ClientBootstrap._installed = true

    if Events then
        if Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
            Events.OnGameBoot.Add(onGameBoot)
        elseif Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
            Events.OnGameStart.Add(onGameBoot)
        end
        if Events.OnKeyPressed and type(Events.OnKeyPressed.Add) == "function" then
            Events.OnKeyPressed.Add(onKeyPressed)
        end
        if Events.OnFillWorldObjectContextMenu and type(Events.OnFillWorldObjectContextMenu.Add) == "function" then
            Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
        end
        if Events.OnFillInventoryObjectContextMenu and type(Events.OnFillInventoryObjectContextMenu.Add) == "function" then
            Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
        end
    end

    return ClientBootstrap
end

ClientBootstrap.install = install

return ClientBootstrap
