local function scriptDir()
    local source = debug.getinfo(1, "S").source or ""
    source = source:gsub("^@", "")
    return source:match("^(.*)/[^/]+$")
end

local root = scriptDir():gsub("/tests$", "")
package.path = table.concat({
    root .. "/common/media/lua/shared/?.lua",
    root .. "/common/media/lua/client/?.lua",
    root .. "/common/media/lua/client/ui/?.lua",
    package.path,
}, ";")

local Support = require "support"

NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.log = function() end

local activeModId = "\\NutritionMakesSense"
function getActivatedMods()
    return {
        size = function() return 1 end,
        get = function() return activeModId end,
    }
end

function isDebugEnabled()
    return false
end

function getCore()
    return {
        getDebug = function()
            return false
        end,
    }
end

function isClient()
    return true
end

function getAccessLevel()
    return "admin"
end

local DebugSupport = require "NutritionMakesSense_DebugSupport"
for key in pairs(DebugSupport._eventSinks or {}) do
    DebugSupport._eventSinks[key] = nil
end

local capturedEvent = nil
local sink = {
    noteConsumeEvent = function(event)
        capturedEvent = event
    end,
}

Support.assertEqual(DebugSupport.registerEventSink("test", sink), true, "debug sink registration")
DebugSupport.noteConsumeEvent({ reason = "consume" })
DebugSupport.unregisterEventSink("test")
Support.assertEqual(capturedEvent and capturedEvent.reason, "consume", "one-argument debug sink payload")
local foodActionEvent = nil
local snapshotEvent = nil
local hungerSyncEvent = nil
Support.assertEqual(DebugSupport.registerEventSink("telemetry", {
    noteFoodActionEvent = function(event) foodActionEvent = event end,
    noteSnapshotEvent = function(event) snapshotEvent = event end,
    noteHungerSyncEvent = function(event) hungerSyncEvent = event end,
}), true, "telemetry-only sink registration")
DebugSupport.noteFoodActionEvent({ item = "Base.Apple" })
DebugSupport.noteSnapshotEvent({ snapshot_sequence = 4 })
DebugSupport.noteHungerSyncEvent({ target_visible_hunger = 0.25 })
DebugSupport.unregisterEventSink("telemetry")
Support.assertEqual(foodActionEvent and foodActionEvent.item, "Base.Apple", "food action telemetry dispatch")
Support.assertEqual(snapshotEvent and snapshotEvent.snapshot_sequence, 4, "snapshot telemetry dispatch")
Support.assertClose(hungerSyncEvent and hungerSyncEvent.target_visible_hunger, 0.25, 0.000001,
    "hunger sync telemetry dispatch")
Support.assertEqual(DebugSupport.canUseDevTools(), false, "admin access must not unlock dev tools")

function isDebugEnabled()
    return true
end

Support.assertEqual(DebugSupport.isDevBuild(), false, "Workshop mod id is not a dev build")
Support.assertEqual(DebugSupport.canUseDevTools(), false, "debug launch does not unlock Workshop dev tools")

activeModId = "\\NutritionMakesSenseDev"
Support.assertEqual(DebugSupport.isDevBuild(), true, "B42-prefixed dev mod id is recognized")
Support.assertEqual(DebugSupport.canUseDevTools(), true, "debug launch unlocks an active dev build")

UIFont = {
    Small = "Small",
    Medium = "Medium",
}

function getTextManager()
    return {
        getFontHeight = function()
            return 10
        end,
        MeasureStringX = function(_, _, text)
            return #(tostring(text or "")) * 6
        end,
    }
end

function round(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local stateByPlayer = {}
NutritionMakesSense.MetabolismRuntime = {
    getStateCopy = function(playerObj)
        return stateByPlayer[playerObj]
    end,
}

ISCharacterScreen = {
    render = function() end,
}

local WeightDisplayHook = require "NutritionMakesSense_WeightDisplayHook"
WeightDisplayHook.install()

local function makeCharacter(weight)
    local nutrition = {
        getWeight = function()
            return weight
        end,
    }
    return {
        getNutrition = function()
            return nutrition
        end,
    }
end

local function renderWeight(character)
    local texts = {}
    ISCharacterScreen.render({
        char = character,
        xOffset = 0,
        backgroundColor = { r = 0, g = 0, b = 0 },
        drawRect = function() end,
        drawText = function(_, text)
            texts[#texts + 1] = tostring(text)
        end,
    })
    return texts[#texts]
end

local gaining = makeCharacter(80)
local losing = makeCharacter(65)
local stable = makeCharacter(75)
stateByPlayer[gaining] = { lastWeightRateKgPerWeek = 1.0 }
stateByPlayer[losing] = { lastWeightRateKgPerWeek = -1.0 }
stateByPlayer[stable] = { lastWeightRateKgPerWeek = -0.001 }

Support.assertEqual(renderWeight(gaining), "+1.00 kg/wk", "gaining character weight rate")
Support.assertEqual(renderWeight(losing), "-1.00 kg/wk", "losing character weight rate")
Support.assertEqual(renderWeight(stable), "0.00 kg/wk", "near-zero weight rate must not render as negative zero")

print("nms client tooling characterization passed")
