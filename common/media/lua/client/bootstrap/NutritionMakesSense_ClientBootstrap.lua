NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_DebugSupport"

local ClientBootstrap = NutritionMakesSense.ClientBootstrap or {}
NutritionMakesSense.ClientBootstrap = ClientBootstrap
local DebugSupport = NutritionMakesSense.DebugSupport or {}

local TAG = "[NutritionMakesSense]"
local DEV_PANEL_HOTKEY = Keyboard and Keyboard.KEY_NUMPAD6 or nil
local TOOL_PANEL_HOTKEY = Keyboard and Keyboard.KEY_NUMPAD7 or nil
local TEST_PANEL_HOTKEY = Keyboard and Keyboard.KEY_NUMPAD8 or nil

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

local function tryLoadDevModule(globalKey, requirePath, label)
    if NutritionMakesSense[globalKey] then
        return true
    end

    local ok, result = pcall(require, requirePath)
    if ok then
        return NutritionMakesSense[globalKey] ~= nil
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

local function tryLoadFoodDebug()
    local loaded = tryLoadDevModule("FoodDebug", "dev/NutritionMakesSense_FoodDebug", "FoodDebug")
    local FoodDebug = NutritionMakesSense.FoodDebug or {}
    if loaded and type(FoodDebug.install) == "function" then
        FoodDebug.install()
    end
    return loaded
end

local function canUseDevTools()
    if type(DebugSupport.canUseDevTools) ~= "function" or not DebugSupport.canUseDevTools() then
        return false
    end
    return tryLoadDevPanel()
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

local function toggleDevSurface(tryLoad, globalKey, label)
    if not canUseDevTools() then
        return false
    end
    toggleLoadedPanel(tryLoad, globalKey, label)
    return true
end

local function onGameBoot()
    if canUseDevTools() then
        tryLoadToolPanel()
        tryLoadTestPanel()
        tryLoadFoodDebug()
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
    local tryLoad = nil
    local globalKey = nil
    local label = nil
    if DEV_PANEL_HOTKEY and key == DEV_PANEL_HOTKEY then
        tryLoad, globalKey, label = tryLoadDevPanel, "DevPanel", "DevPanel"
    elseif TOOL_PANEL_HOTKEY and key == TOOL_PANEL_HOTKEY then
        tryLoad, globalKey, label = tryLoadToolPanel, "ToolPanel", "ToolPanel"
    elseif TEST_PANEL_HOTKEY and key == TEST_PANEL_HOTKEY then
        tryLoad, globalKey, label = tryLoadTestPanel, "TestPanel", "TestPanel"
    else
        return
    end

    toggleDevSurface(tryLoad, globalKey, label)
end

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    if not canUseDevTools() then
        return
    end
    if test then
        if ISWorldObjectContextMenu and type(ISWorldObjectContextMenu.setTest) == "function" then
            return ISWorldObjectContextMenu.setTest()
        end
        return true
    end
    context:addOption("NMS Dev Panel", nil, function() toggleDevSurface(tryLoadDevPanel, "DevPanel", "DevPanel") end)
    context:addOption("NMS Tool Panel", nil, function() toggleDevSurface(tryLoadToolPanel, "ToolPanel", "ToolPanel") end)
    context:addOption("NMS Test Panel", nil, function() toggleDevSurface(tryLoadTestPanel, "TestPanel", "TestPanel") end)
end

local function onFillInventoryObjectContextMenu(player, context, items)
    if not canUseDevTools() then
        return
    end

    if not tryLoadFoodDebug() then
        return
    end

    local FoodDebug = NutritionMakesSense.FoodDebug or {}
    local actualItems = FoodDebug.resolveActualItems and FoodDebug.resolveActualItems(items) or {}
    if #actualItems ~= 1 then
        return
    end

    local item = actualItems[1]
    if not item or not (FoodDebug.isFoodItem and FoodDebug.isFoodItem(item)) then
        return
    end

    context:addOption("NMS Log Food Item", item, FoodDebug.logItem)
end

local function install()
    if Events then
        local previous = ClientBootstrap._handlers or {}
        local function rebind(event, oldHandler, newHandler)
            if not event then
                return
            end
            if oldHandler and type(event.Remove) == "function" then
                event.Remove(oldHandler)
            end
            if type(event.Add) == "function" then
                event.Add(newHandler)
            end
        end

        if Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
            rebind(Events.OnGameBoot, previous.onGameBoot, onGameBoot)
        elseif Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
            rebind(Events.OnGameStart, previous.onGameBoot, onGameBoot)
        end
        rebind(Events.OnKeyPressed, previous.onKeyPressed, onKeyPressed)
        if previous.onFillWorldObjectContextMenu and Events.OnFillWorldObjectContextMenu
            and type(Events.OnFillWorldObjectContextMenu.Remove) == "function" then
            Events.OnFillWorldObjectContextMenu.Remove(previous.onFillWorldObjectContextMenu)
        end
        rebind(Events.OnPreFillWorldObjectContextMenu, previous.onFillWorldObjectContextMenu, onFillWorldObjectContextMenu)
        rebind(Events.OnFillInventoryObjectContextMenu, previous.onFillInventoryObjectContextMenu, onFillInventoryObjectContextMenu)

        ClientBootstrap._handlers = {
            onGameBoot = onGameBoot,
            onKeyPressed = onKeyPressed,
            onFillWorldObjectContextMenu = onFillWorldObjectContextMenu,
            onFillInventoryObjectContextMenu = onFillInventoryObjectContextMenu,
        }
    end

    return ClientBootstrap
end

ClientBootstrap.install = install

return ClientBootstrap
