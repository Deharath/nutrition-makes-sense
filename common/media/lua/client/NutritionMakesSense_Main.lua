NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_Boot"
require "NutritionMakesSense_DevSupport"
require "NutritionMakesSense_MPClientRuntime"
require "NutritionMakesSense_ClientOptions"
require "NutritionMakesSense_TooltipOverlay"
require "NutritionMakesSense_ItemAuthority"
require "NutritionMakesSense_HealthPanelHook"
require "NutritionMakesSense_MalnourishedMoodle"
require "NutritionMakesSense_WeightDisplayHook"

local TAG = "[NutritionMakesSense]"
local DEV_PANEL_HOTKEY = Keyboard and Keyboard.KEY_NUMPAD6 or nil
local TOOL_PANEL_HOTKEY = Keyboard and Keyboard.KEY_NUMPAD7 or nil
local TEST_PANEL_HOTKEY = Keyboard and Keyboard.KEY_NUMPAD8 or nil
local DevSupport = NutritionMakesSense.DevSupport or {}

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

local function logFoodItemDebug(item)
    local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
    local fullType = safeCall(item, "getFullType") or tostring(item)
    local itemId = ItemAuthority.getItemId and ItemAuthority.getItemId(item) or tonumber(safeCall(item, "getID"))
    local displayName = safeCall(item, "getDisplayName") or fullType
    local display = ItemAuthority.getDisplayValues and ItemAuthority.getDisplayValues(item) or nil
    local current = ItemAuthority.readCurrentValues and ItemAuthority.readCurrentValues(item) or nil
    local stored = ItemAuthority.readStoredSnapshot and ItemAuthority.readStoredSnapshot(item) or nil

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
    log("[FOOD_DEBUG] current " .. formatValues(current))
    log("[FOOD_DEBUG] stored  " .. formatValues(stored))
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

    return DevSupport.canUseDevTools and DevSupport.canUseDevTools() or false
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

local function onPlayerUpdate(playerObj)
    if not playerObj then
        return
    end
    if type(getPlayer) == "function" and playerObj ~= getPlayer() then
        return
    end
    local Runtime = NutritionMakesSense.MetabolismRuntime
    if Runtime and type(Runtime.syncVisibleIndicators) == "function" then
        Runtime.syncVisibleIndicators(playerObj, "client-player-update")
    end
end

local nmsMeleePenalty = {}

local function onMeleeAttackStart(character, chargeDelta, weapon)
    if not character or not weapon then
        return
    end
    if not instanceof(character, "IsoPlayer") then
        return
    end
    if safeCall(weapon, "isRanged") then
        return
    end

    local Runtime = NutritionMakesSense.MetabolismRuntime
    local Metabolism = NutritionMakesSense.Metabolism
    if not Runtime or not Metabolism then
        return
    end

    local state = Runtime.ensureStateForPlayer and Runtime.ensureStateForPlayer(character)
    if not state then
        return
    end

    local mult = Metabolism.getMeleeDamageMultiplier(state.deprivation)
    if mult >= 1.0 then
        return
    end

    local weaponId = safeCall(weapon, "getID") or tostring(weapon)
    local origMin = safeCall(weapon, "getMinDamage") or 0
    local origMax = safeCall(weapon, "getMaxDamage") or 0
    nmsMeleePenalty[weaponId] = { minDmg = origMin, maxDmg = origMax }
    safeCall(weapon, "setMinDamage", origMin * mult)
    safeCall(weapon, "setMaxDamage", origMax * mult)
end

local function onMeleeAttackFinished(playerObj, weapon)
    if not playerObj or not weapon then
        return
    end
    local weaponId = safeCall(weapon, "getID") or tostring(weapon)
    local saved = nmsMeleePenalty[weaponId]
    if saved then
        safeCall(weapon, "setMinDamage", saved.minDmg)
        safeCall(weapon, "setMaxDamage", saved.maxDmg)
        nmsMeleePenalty[weaponId] = nil
    end
end

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
    if Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
        Events.OnPlayerUpdate.Add(onPlayerUpdate)
    end
    if Events.OnPlayerAttackFinished and type(Events.OnPlayerAttackFinished.Add) == "function" then
        Events.OnPlayerAttackFinished.Add(onMeleeAttackFinished)
    end
end

if Hook and Hook.Attack and type(Hook.Attack.Add) == "function" then
    Hook.Attack.Add(onMeleeAttackStart)
end
