local Support = require "support"
local source = debug.getinfo(1, "S").source:gsub("^@", "")
local root = source:match("^(.*)/tests/")
package.path = root .. "/common/media/lua/server/?.lua;" .. package.path
NutritionMakesSense = { log = function() end }
package.preload.NutritionMakesSense_Boot = function() return true end
isServer = function() return true end
isClient = function() return false end
local now = 100
getTimestampMs = function() return now * 1000 end
local canEdit = false
Capability = { CanModifyPlayerStatsInThePlayerStatsUI = "edit" }
local player = {
    getOnlineID = function() return 1 end,
    getRole = function() return { hasCapability = function() return canEdit end } end,
}
getPlayerByOnlineID = function(id) if id == 1 then return player end end
getOnlinePlayers = function() return { size = function() return 1 end, get = function() return player end } end
local Snapshot = require "NutritionMakesSense_MPSnapshot"
local state = { fuel = 1500, visibleHunger = 0.2, proteins = 200, weightKg = 80,
    deprivation = 0, depositSequence = 0, lastZone = "Normal", lastMetAverage = 3 }
local updates, weightEdits = 0, 0
local lastWorkloadSessionId
local Runtime = {
    getPlayerCacheKey = function(p) return tostring(p) end,
    updatePlayer = function() updates = updates + 1 end,
    buildStateSnapshot = function(_, reason, diagnostics)
        return { version = "test", reason = reason, state = Snapshot.copyState(state, diagnostics) }
    end,
    setAdminWeight = function(_, weight) weightEdits = weightEdits + 1; state.weightKg = weight; return true end,
    reportPlayerWorkload = function(_, _, _, _, _, sessionId) lastWorkloadSessionId = sessionId end,
}
package.preload.NutritionMakesSense_MetabolismRuntime = function()
    NutritionMakesSense.MetabolismRuntime = Runtime
    return Runtime
end
local events = {}
Events = setmetatable({}, { __index = function(self, key)
    local value = { Add = function(fn) events[key] = fn end }
    rawset(self, key, value)
    return value
end })
local packets = {}
sendServerCommand = function(_, _, _, payload) packets[#packets + 1] = payload end
require("NutritionMakesSense_MPServerRuntime_Vanilla").install()
for tick = 1, 1200 do
    now = 100 + tick * 0.25
    state.fuel = state.fuel - 0.1
    state.lastMetAverage = tick % 4
    events.OnPlayerUpdate(player)
end
Support.assertTrue(#packets >= 75 and #packets <= 76, "idle changes should use four-second keepalives")
Support.assertNil(packets[1].state.lastMetAverage, "release packets exclude diagnostics")
local before = #packets
now = now + 0.25
state.depositSequence = 1
events.OnPlayerUpdate(player)
Support.assertEqual(#packets, before + 1, "meal acknowledgement bypasses passive interval")
before = #packets
now = now + 0.25
state.visibleHunger = 0.65
events.OnPlayerUpdate(player)
Support.assertEqual(#packets, before + 1, "critical hunger bypasses passive interval")
local beforeUpdates = updates
events.OnPlayerUpdate({ getOnlineID = function() return 1 end })
Support.assertEqual(updates, beforeUpdates, "NPC sharing a player id cannot update that session")
events.OnClientCommand("player", "setWeight", player, { id = 1, weight = 90 })
Support.assertEqual(weightEdits, 0, "weight edits require admin capability")
canEdit = true
events.OnClientCommand("player", "setWeight", player, { id = 1, weight = 90 })
Support.assertEqual(weightEdits, 1, "authorized vanilla weight command reaches NMS")
Support.assertEqual(packets[#packets].state.weightKg, 90, "weight edit sends its result immediately")
local MP = NutritionMakesSense.MP
before = #packets
events.OnClientCommand(MP.NET_MODULE, MP.REQUEST_SNAPSHOT_COMMAND, player, { reason = "request" })
Support.assertEqual(#packets, before + 1, "explicit snapshot requests bypass cadence")
events.OnClientCommand(MP.NET_MODULE, MP.REPORT_WORKLOAD_COMMAND, player, {
    averageMet = 3, peakMet = 3, source = "walk", seq = 1, sessionId = "session-two",
})
Support.assertEqual(lastWorkloadSessionId, "session-two", "server forwards workload session token")
print("nms MP server cadence and admin boundary passed: " .. tostring(75) .. " idle packets / 300 seconds")
