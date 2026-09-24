NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_Runtime"
require "NutritionMakesSense_Workload"

-- Dedicated-server side: accepts client workload reports and pushes display snapshots.
-- Vanilla already replicates hunger, calories, macros, weight and the Well Fed timer every second.
local MPServer = NutritionMakesSense.MPServer or {}
NutritionMakesSense.MPServer = MPServer

local MP = NutritionMakesSense.MP
local Runtime = NutritionMakesSense.Runtime
local Workload = NutritionMakesSense.Workload

MPServer.SNAPSHOT_MIN_SECONDS = 2
MPServer.SNAPSHOT_KEEPALIVE_SECONDS = 10

local sentByPlayer = setmetatable({}, { __mode = "k" })

local function changed(a, b)
    if not a or not b then
        return true
    end
    return math.abs((a.malnutrition or 0) - (b.malnutrition or 0)) > 0.002
        or math.abs((a.malnutritionTarget or 0) - (b.malnutritionTarget or 0)) > 0.01
        or math.abs((a.calorieTarget or 0) - (b.calorieTarget or 0)) > 0.01
        or math.abs((a.proteinTarget or 0) - (b.proteinTarget or 0)) > 0.01
        or math.abs((a.trendKgPerWeek or 0) - (b.trendKgPerWeek or 0)) > 0.02
        or math.abs((a.burnPerHour or 0) - (b.burnPerHour or 0)) > 10
end

local function sendSnapshot(playerObj, force)
    local now = Workload.wallSeconds()
    local sent = sentByPlayer[playerObj]
    if not force and sent and (now - sent.checkedAt) < MPServer.SNAPSHOT_MIN_SECONDS then
        return
    end
    local snapshot = Runtime.buildDisplaySnapshot(playerObj)
    if not snapshot then
        return
    end
    if not force and sent and (now - sent.at) < MPServer.SNAPSHOT_KEEPALIVE_SECONDS
        and not changed(snapshot, sent.snapshot) then
        sent.checkedAt = now
        return
    end
    sentByPlayer[playerObj] = { at = now, checkedAt = now, snapshot = snapshot }
    sendServerCommand(playerObj, MP.NET_MODULE, MP.DISPLAY_SNAPSHOT_COMMAND, { display = snapshot })
end

local function onClientCommand(module, command, playerObj, args)
    if module ~= MP.NET_MODULE or not playerObj then
        return
    end
    if command == MP.REPORT_WORKLOAD_COMMAND then
        Workload.acceptReport(playerObj, args)
    elseif command == MP.REQUEST_SNAPSHOT_COMMAND then
        Runtime.tick(playerObj, true)
        sendSnapshot(playerObj, true)
    end
end

local function onPlayerUpdate(playerObj)
    sendSnapshot(playerObj, false)
end

function MPServer.install()
    if MPServer._installed or not (type(isServer) == "function" and isServer()) then
        return
    end
    MPServer._installed = true
    Events.OnClientCommand.Add(onClientCommand)
    Events.OnPlayerUpdate.Add(onPlayerUpdate)
end

return MPServer
