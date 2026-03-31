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
    local semanticClass = debugSnapshot and debugSnapshot.semanticClass or nil
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

    log(string.format(
        "[FOOD_DEBUG] item=%s name=%s id=%s cooked=%s burnt=%s frozen=%s rotten=%s age=%s offAge=%s offAgeMax=%s",
        tostring(fullType),
        tostring(displayName),
        tostring(itemId or "nil"),
        formatBool(safeCall(item, "isCooked")),
        formatBool(safeCall(item, "isBurnt")),
        formatBool(safeCall(item, "isFrozen")),
        formatBool(safeCall(item, "isRotten")),
        formatNumber(safeCall(item, "getAge"), 3),
        formatNumber(safeCall(item, "getOffAge"), 3),
        formatNumber(safeCall(item, "getOffAgeMax"), 3)
    ))
    log("[FOOD_DEBUG] display " .. formatValues(display))
    log("[FOOD_DEBUG] applied " .. formatValues(applied))
    log("[FOOD_DEBUG] current " .. formatValues(current))
    log("[FOOD_DEBUG] stored  " .. formatValues(stored))
    log(string.format(
        "[FOOD_DEBUG] semantics source=%s class=%s expectedMode=%s resolvedMode=%s patchSource=%s authorityTarget=%s",
        tostring(source or "nil"),
        tostring(semanticClass or "nil"),
        tostring(expectedMode or "nil"),
        tostring(resolvedMode or "nil"),
        tostring(patchSource or "nil"),
        tostring(authorityTarget or "nil")
    ))
    log("[FOOD_DEBUG] meta display " .. formatSnapshotMeta(display))
    log("[FOOD_DEBUG] meta applied " .. formatSnapshotMeta(applied))
    log("[FOOD_DEBUG] meta current " .. formatSnapshotMeta(current))
    log("[FOOD_DEBUG] meta stored  " .. formatSnapshotMeta(stored))
    log(string.format(
        "[FOOD_DEBUG] raw baseHunger=%s hunger=%s thirst=%s thirstUnmod=%s calories=%s carbs=%s fats=%s proteins=%s currentUses=%s maxUses=%s resolvedSource=%s",
        formatNumber(safeCall(item, "getBaseHunger"), 3),
        formatNumber(safeCall(item, "getHungChange") or safeCall(item, "getHungerChange"), 3),
        formatNumber(thirst, 3),
        formatNumber(thirstUnmodified, 3),
        formatNumber(safeCall(item, "getCalories"), 1),
        formatNumber(safeCall(item, "getCarbohydrates"), 3),
        formatNumber(safeCall(item, "getLipids"), 3),
        formatNumber(safeCall(item, "getProteins"), 3),
        formatNumber(safeCall(item, "getCurrentUses"), 3),
        formatNumber(safeCall(item, "getMaxUses"), 3),
        tostring(resolvedSource or "nil")
    ))
    log(string.format(
        "[FOOD_DEBUG] mood boredom=%s unmod=%s dynamicDelta=%s bar=%s unhappy=%s unmod=%s dynamicDelta=%s bar=%s",
        formatNumber(moodBoredom, 3),
        formatNumber(moodBoredomUnmodified, 3),
        formatNumber(moodBoredomDelta, 3),
        formatPercent(math.abs((tonumber(moodBoredom) or 0) * 0.02)),
        formatNumber(moodUnhappy, 3),
        formatNumber(moodUnhappyUnmodified, 3),
        formatNumber(moodUnhappyDelta, 3),
        formatPercent(math.abs((tonumber(moodUnhappy) or 0) * 0.02))
    ))
    log(string.format(
        "[FOOD_DEBUG] mood context ageBand=%s frozen=%s canBeFrozen=%s freezingTime=%s burnt=%s cooked=%s cookable=%s badCold=%s goodHot=%s heat=%s",
        tostring(ageBand),
        formatBool(frozen),
        tostring(canBeFrozen),
        formatNumber(freezingTime, 3),
        formatBool(burnt),
        formatBool(cooked),
        formatBool(cookable),
        formatBool(badCold),
        formatBool(goodHot),
        formatNumber(heat, 3)
    ))
    log(string.format(
        "[FOOD_DEBUG] mood baseline scriptBoredom=%s scriptUnhappy=%s probeBoredom=%s probeBoredomUnmod=%s probeUnhappy=%s probeUnhappyUnmod=%s",
        formatNumber(scriptMoodBoredom, 3),
        formatNumber(scriptMoodUnhappy, 3),
        formatNumber(probeMoodBoredom, 3),
        formatNumber(probeMoodBoredomUnmodified, 3),
        formatNumber(probeMoodUnhappy, 3),
        formatNumber(probeMoodUnhappyUnmodified, 3)
    ))
    log(string.format(
        "[FOOD_DEBUG] thirst baseline script=%s probe=%s probeUnmod=%s",
        formatNumber(scriptThirst, 3),
        formatNumber(probeThirst, 3),
        formatNumber(probeThirstUnmodified, 3)
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
