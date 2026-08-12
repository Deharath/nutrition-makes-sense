local function scriptDir()
    local source = debug.getinfo(1, "S").source or ""
    source = source:gsub("^@", "")
    return source:match("^(.*)/[^/]+$")
end

local testsDir = scriptDir()
local root = testsDir:match("^(.*)/tests$") or "."
package.path = table.concat({
    root .. "/common/media/lua/shared/?.lua",
    root .. "/common/media/lua/client/?.lua",
    package.path,
}, ";")

local Support = require "support"

NutritionMakesSense = { log = function() end }
isClient = function() return true end
isServer = function() return false end

local nowSeconds = 100
local worldHours = 8
getTimestampMs = function() return nowSeconds * 1000 end

local liveHunger = 0.25
local foodEatenTimer = 0
local localState = nil
local imports = {}
local anchors = {}
local suppressionCount = 0
local sentCommands = {}

local stats = {}
local bodyDamage = {}
local player = {}

local Runtime = {
    sampleReportedWorkload = function()
        return { averageMet = 3.1, peakMet = 3.1, source = "movement_walk" }
    end,
    importStateSnapshot = function(_, snapshot)
        localState = {}
        for key, value in pairs(snapshot.state or {}) do localState[key] = value end
        liveHunger = tonumber(localState.visibleHunger) or liveHunger
        imports[#imports + 1] = snapshot
        return localState
    end,
    getStateCopy = function() return localState end,
    applyVisibleHungerTarget = function(_, target)
        liveHunger = target
        anchors[#anchors + 1] = target
        if localState then localState.visibleHunger = target end
        return true
    end,
    getPlayerStats = function() return stats end,
    getVisibleHungerValue = function() return liveHunger end,
    getPlayerBodyDamage = function() return bodyDamage end,
    suppressFoodEatenTimer = function()
        suppressionCount = suppressionCount + 1
        foodEatenTimer = 0
        return true
    end,
}
package.preload["NutritionMakesSense_MetabolismRuntime"] = function()
    NutritionMakesSense.MetabolismRuntime = Runtime
    return Runtime
end

local CoreUtils = {
    safeCall = function(object, methodName, ...)
        local method = object and object[methodName]
        if type(method) ~= "function" then return nil end
        return method(object, ...)
    end,
    getLocalPlayer = function() return player end,
    getPlayerLabel = function() return "mp-test-player" end,
    getWorldHours = function() return worldHours end,
}
package.preload["NutritionMakesSense_CoreUtils"] = function()
    NutritionMakesSense.CoreUtils = CoreUtils
    return CoreUtils
end

local snapshotEvents = 0
local DebugSupport = {
    noteSnapshotEvent = function() snapshotEvents = snapshotEvents + 1 end,
}
package.preload["NutritionMakesSense_DebugSupport"] = function()
    NutritionMakesSense.DebugSupport = DebugSupport
    return DebugSupport
end

sendClientCommand = function(module, command, args)
    sentCommands[#sentCommands + 1] = { module = module, command = command, args = args }
end

local handlers = {}
local function event(name)
    return { Add = function(callback) handlers[name] = callback end }
end
Events = {
    OnServerCommand = event("serverCommand"),
    OnCreatePlayer = event("createPlayer"),
    OnPlayerUpdate = event("playerUpdate"),
}

local MPClient = require "NutritionMakesSense_MPClientRuntime_Vanilla"
MPClient.install()
handlers.createPlayer(0, player)
Support.assertTrue(#sentCommands >= 2,
    "client creation requests an authoritative snapshot and reports workload")

local function snapshot(seq, hunger, depositSequence)
    handlers.serverCommand(NutritionMakesSense.MP.NET_MODULE, NutritionMakesSense.MP.STATE_SNAPSHOT_COMMAND, {
        serverSeq = seq,
        serverWorldHours = worldHours,
        serverWallSeconds = nowSeconds,
        reason = "test-snapshot",
        state = {
            initialized = true,
            visibleHunger = hunger,
            fuel = 900,
            proteins = 200,
            weightKg = 80,
            deprivation = 0,
            depositSequence = depositSequence,
        },
    })
end

snapshot(10, 0.25, 5)
Support.assertClose(liveHunger, 0.25, 0.000001,
    "first authoritative snapshot is applied")
Support.assertEqual(#imports, 1, "first snapshot imports once")

snapshot(10, 0.40, 5)
Support.assertEqual(#imports, 1,
    "duplicate snapshot sequence is ignored instead of replaying hunger")
Support.assertClose(liveHunger, 0.25, 0.000001,
    "duplicate snapshot cannot overwrite the display")

Support.assertEqual(MPClient.noteMealPrediction(player, {
    reason = "client-eat-prediction",
    preVisibleHunger = 0.25,
    targetVisibleHunger = 0.10,
}), true, "meal prediction is registered")
liveHunger = 0.10

nowSeconds = nowSeconds + 2.1
handlers.playerUpdate(player)
Support.assertEqual(MPClient.getSnapshotMeta().mealPredictionActive, true,
    "a causally sequenced prediction does not fall back to the short legacy timeout")
Support.assertClose(liveHunger, 0.10, 0.000001,
    "prediction stays anchored while the first post-meal snapshot is in flight")

nowSeconds = nowSeconds + 0.2
snapshot(11, 0.26, 5)
Support.assertClose(liveHunger, 0.10, 0.000001,
    "a causally pre-meal snapshot cannot undo local fullness")
Support.assertClose(MPClient.getSnapshot().state.visibleHunger, 0.26, 0.000001,
    "raw authoritative snapshot remains available for diagnosis")
Support.assertEqual(MPClient.getSnapshotMeta().mealPredictionResolution, "holding-premeal-snapshot",
    "MP metadata explains why the display was held")

nowSeconds = nowSeconds + 0.2
snapshot(12, 0.18, 6)
Support.assertClose(liveHunger, 0.10, 0.000001,
    "a partial server meal observation settles without an upward hunger flash")
Support.assertEqual(MPClient.getSnapshotMeta().mealPredictionResolution, "confirmed-settling",
    "MP metadata distinguishes a partially confirmed meal")

nowSeconds = nowSeconds + 0.2
snapshot(13, 0.115, 6)
Support.assertClose(liveHunger, 0.115, 0.000001,
    "client returns to authority once the meal target agrees")
Support.assertEqual(MPClient.getSnapshotMeta().mealPredictionActive, false,
    "confirmed meal prediction is cleared")
Support.assertEqual(MPClient.getSnapshotMeta().mealPredictionResolution, "server-confirmed",
    "MP metadata records causal confirmation")

liveHunger = 0.20
foodEatenTimer = 100
handlers.playerUpdate(player)
Support.assertClose(liveHunger, 0.115, 0.000001,
    "client hunger drift is anchored between server snapshots")
Support.assertTrue(#anchors > 0, "display anchor writes only when local hunger diverges")
Support.assertEqual(foodEatenTimer, 0,
    "late vanilla Food Eaten state is suppressed on the MP client")
Support.assertTrue(suppressionCount > 0, "MP shell checked the Food Eaten timer")

snapshot(99, 0.20, 7)
handlers.createPlayer(0, player)
snapshot(1, 0.21, 7)
Support.assertClose(liveHunger, 0.21, 0.000001,
    "a reconnect accepts a restarted server sequence")
Support.assertEqual(MPClient.getSnapshotMeta().lastSeq, 1,
    "reconnect resets sequence monotonicity to the new session")
Support.assertTrue(snapshotEvents >= 6,
    "accepted snapshots remain visible to recording diagnostics")

print("nms MP client reconciliation characterization passed")
