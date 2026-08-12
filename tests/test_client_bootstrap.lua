local function scriptDir()
    local source = debug.getinfo(1, "S").source or ""
    source = source:gsub("^@", "")
    return source:match("^(.*)/[^/]+$")
end

local root = scriptDir():gsub("/tests$", "")
package.path = table.concat({
    root .. "/common/media/lua/shared/?.lua",
    root .. "/common/media/lua/client/?.lua",
    root .. "/common/media/lua/client/bootstrap/?.lua",
    package.path,
}, ";")

local Support = require "support"

local function makeEvent()
    local handlers = {}
    return {
        handlers = handlers,
        Add = function(handler)
            handlers[#handlers + 1] = handler
        end,
        Remove = function(handler)
            for i = #handlers, 1, -1 do
                if handlers[i] == handler then
                    table.remove(handlers, i)
                end
            end
        end,
    }
end

Events = {
    OnGameBoot = makeEvent(),
    OnKeyPressed = makeEvent(),
    OnPreFillWorldObjectContextMenu = makeEvent(),
    OnFillInventoryObjectContextMenu = makeEvent(),
}
Keyboard = {
    KEY_NUMPAD6 = 102,
    KEY_NUMPAD7 = 103,
    KEY_NUMPAD8 = 104,
}

local toggles = { dev = 0, tool = 0, test = 0 }
local foodDebugInstalls = 0
local foodDebugInstalled = false
local debugEnabled = false
local activeModId = "\\NutritionMakesSenseDev"
isDebugEnabled = function()
    return debugEnabled
end
getActivatedMods = function()
    return {
        size = function() return 1 end,
        get = function() return activeModId end,
    }
end
NutritionMakesSense = {
    log = function() end,
}

package.preload["dev/NutritionMakesSense_DevPanel"] = function()
    NutritionMakesSense.DevPanel = {
        toggle = function() toggles.dev = toggles.dev + 1 end,
    }
    return NutritionMakesSense.DevPanel
end
package.preload["dev/NutritionMakesSense_ToolPanel"] = function()
    NutritionMakesSense.ToolPanel = {
        toggle = function() toggles.tool = toggles.tool + 1 end,
    }
    return NutritionMakesSense.ToolPanel
end
package.preload["dev/NutritionMakesSense_TestPanel"] = function()
    NutritionMakesSense.TestPanel = {
        toggle = function() toggles.test = toggles.test + 1 end,
    }
    return NutritionMakesSense.TestPanel
end
package.preload["dev/NutritionMakesSense_FoodDebug"] = function()
    NutritionMakesSense.FoodDebug = {
        resolveActualItems = function(items) return items end,
        isFoodItem = function() return true end,
        logItem = function() end,
        install = function()
            if not foodDebugInstalled then
                foodDebugInstalled = true
                foodDebugInstalls = foodDebugInstalls + 1
            end
        end,
    }
    return NutritionMakesSense.FoodDebug
end

ISWorldObjectContextMenu = {
    setTest = function() return "test-set" end,
}

local Bootstrap = require "NutritionMakesSense_ClientBootstrap"
Bootstrap.install()

Support.assertEqual(#Events.OnKeyPressed.handlers, 1, "hotkey hook registration")
Support.assertEqual(#Events.OnPreFillWorldObjectContextMenu.handlers, 1, "world pre-fill hook registration")
Support.assertEqual(#Events.OnFillInventoryObjectContextMenu.handlers, 1, "inventory hook registration")

Bootstrap.install()
Support.assertEqual(#Events.OnKeyPressed.handlers, 1, "hotkey hook must rebind without duplication")
Support.assertEqual(#Events.OnPreFillWorldObjectContextMenu.handlers, 1, "world hook must rebind without duplication")

Events.OnKeyPressed.handlers[1](Keyboard.KEY_NUMPAD6)
Events.OnKeyPressed.handlers[1](Keyboard.KEY_NUMPAD7)
Events.OnKeyPressed.handlers[1](Keyboard.KEY_NUMPAD8)
Support.assertEqual(toggles.dev, 0, "normal launch blocks dev-panel hotkey")
Support.assertEqual(toggles.tool, 0, "normal launch blocks tool-panel hotkey")
Support.assertEqual(toggles.test, 0, "normal launch blocks test-panel hotkey")

local normalOptions = {}
local normalContext = {
    addOption = function(_, name)
        normalOptions[#normalOptions + 1] = name
    end,
}
Events.OnPreFillWorldObjectContextMenu.handlers[1](0, normalContext, {}, false)
Support.assertEqual(#normalOptions, 0, "normal launch exposes no NMS dev context entries")

local normalInventoryOptions = {}
local normalInventoryContext = {
    addOption = function(_, name)
        normalInventoryOptions[#normalInventoryOptions + 1] = name
    end,
}
Events.OnFillInventoryObjectContextMenu.handlers[1](0, normalInventoryContext, { {} })
Support.assertEqual(#normalInventoryOptions, 0, "normal launch exposes no NMS food-debug entry")

debugEnabled = true
activeModId = "\\NutritionMakesSense"
local workshopRequireAttempts = 0
local devPanelLoader = package.preload["dev/NutritionMakesSense_DevPanel"]
package.preload["dev/NutritionMakesSense_DevPanel"] = function()
    workshopRequireAttempts = workshopRequireAttempts + 1
    return {}
end
package.loaded["dev/NutritionMakesSense_DevPanel"] = nil
Support.assertEqual(workshopRequireAttempts, 0, "Workshop build never probes an excluded dev module")

local workshopOptions = {}
Events.OnPreFillWorldObjectContextMenu.handlers[1](0, {
    addOption = function(_, name)
        workshopOptions[#workshopOptions + 1] = name
    end,
}, {}, false)
Events.OnFillInventoryObjectContextMenu.handlers[1](0, {
    addOption = function(_, name)
        workshopOptions[#workshopOptions + 1] = name
    end,
}, { {} })
Support.assertEqual(#workshopOptions, 0, "debug Workshop launch exposes no dev context entries")
Support.assertEqual(workshopRequireAttempts, 0, "context-menu events never probe excluded dev modules")

activeModId = "\\NutritionMakesSenseDev"
Events.OnKeyPressed.handlers[1](Keyboard.KEY_NUMPAD6)
Support.assertEqual(workshopRequireAttempts, 1, "dev build probes its included dev panel")
Support.assertEqual(toggles.dev, 0, "invalid dev module cannot toggle a panel")
package.preload["dev/NutritionMakesSense_DevPanel"] = devPanelLoader
package.loaded["dev/NutritionMakesSense_DevPanel"] = nil

Events.OnKeyPressed.handlers[1](Keyboard.KEY_NUMPAD6)
Events.OnKeyPressed.handlers[1](Keyboard.KEY_NUMPAD7)
Events.OnKeyPressed.handlers[1](Keyboard.KEY_NUMPAD8)
Support.assertEqual(toggles.dev, 1, "dev-panel hotkey")
Support.assertEqual(toggles.tool, 1, "tool-panel hotkey")
Support.assertEqual(toggles.test, 1, "test-panel hotkey")
Events.OnGameBoot.handlers[1]()
Support.assertEqual(foodDebugInstalls, 1, "dev boot installs observation-only food telemetry")

local options = {}
local context = {
    addOption = function(_, name, target, callback)
        options[#options + 1] = { name = name, target = target, callback = callback }
    end,
}
Events.OnPreFillWorldObjectContextMenu.handlers[1](0, context, {}, false)
Support.assertEqual(#options, 3, "world menu entries")
Support.assertEqual(options[1].name, "NMS Dev Panel", "first world menu entry")
options[1].callback()
Support.assertEqual(toggles.dev, 2, "world menu callback")

local debugInventoryOptions = {}
local debugInventoryContext = {
    addOption = function(_, name)
        debugInventoryOptions[#debugInventoryOptions + 1] = name
    end,
}
Events.OnFillInventoryObjectContextMenu.handlers[1](0, debugInventoryContext, { {} })
Support.assertEqual(#debugInventoryOptions, 1, "debug launch exposes the NMS food-debug entry")
Support.assertEqual(debugInventoryOptions[1], "NMS Log Food Item", "food-debug entry label")

debugEnabled = false
Support.assertEqual(options[1].callback(), nil, "existing dev callback is inert outside debug mode")
Support.assertEqual(toggles.dev, 2, "normal launch cannot toggle a previously loaded dev panel")
debugEnabled = true

local testResult = Events.OnPreFillWorldObjectContextMenu.handlers[1](0, context, {}, true)
Support.assertEqual(testResult, "test-set", "controller context-menu test")

print("nms client bootstrap characterization passed")
