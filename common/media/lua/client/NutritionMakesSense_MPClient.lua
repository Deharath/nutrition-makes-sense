NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_Runtime"
require "NutritionMakesSense_Workload"

-- MP client: reports the local MET sample (the server cannot see timed actions/movement reliably)
-- and receives the display snapshot. Vanilla replicates every nutrition value itself.
local MPClient = NutritionMakesSense.MPClient or {}
NutritionMakesSense.MPClient = MPClient

local MP = NutritionMakesSense.MP
local Runtime = NutritionMakesSense.Runtime
local Workload = NutritionMakesSense.Workload

MPClient.REPORT_MIN_SECONDS = 1
MPClient.REPORT_KEEPALIVE_SECONDS = 5
MPClient.SNAPSHOT_STALE_SECONDS = 20

local lastReport = nil
local lastSnapshotAt = nil
local lastRequestAt = nil

local function isLocal(playerObj)
    return playerObj and playerObj.isLocalPlayer and playerObj:isLocalPlayer()
end

local function requestSnapshot(playerObj, now)
    if lastRequestAt and (now - lastRequestAt) < 5 then
        return
    end
    lastRequestAt = now
    sendClientCommand(playerObj, MP.NET_MODULE, MP.REQUEST_SNAPSHOT_COMMAND, {})
end

local function onPlayerUpdate(playerObj)
    if not isLocal(playerObj) then
        return
    end
    local now = Workload.wallSeconds()
    if lastSnapshotAt == nil or (now - lastSnapshotAt) > MPClient.SNAPSHOT_STALE_SECONDS then
        requestSnapshot(playerObj, now)
    end
    if lastReport and (now - lastReport.at) < MPClient.REPORT_MIN_SECONDS then
        return
    end
    local sample = Workload.sampleLocal(playerObj)
    local due = lastReport == nil
        or (now - lastReport.at) >= MPClient.REPORT_KEEPALIVE_SECONDS
        or math.abs(sample.met - lastReport.met) > 0.25
        or sample.asleep ~= lastReport.asleep
    if not due then
        return
    end
    lastReport = { at = now, met = sample.met, asleep = sample.asleep }
    sendClientCommand(playerObj, MP.NET_MODULE, MP.REPORT_WORKLOAD_COMMAND, {
        met = sample.met,
        asleep = sample.asleep,
        source = sample.source,
    })
end

local function onServerCommand(module, command, args)
    if module ~= MP.NET_MODULE or command ~= MP.DISPLAY_SNAPSHOT_COMMAND or type(args) ~= "table" then
        return
    end
    local playerObj = getPlayer()
    if playerObj then
        lastSnapshotAt = Workload.wallSeconds()
        Runtime.importDisplaySnapshot(playerObj, args.display)
    end
end

function MPClient.install()
    if MPClient._installed or not Runtime.isMPClient() then
        return
    end
    MPClient._installed = true
    Events.OnPlayerUpdate.Add(onPlayerUpdate)
    Events.OnServerCommand.Add(onServerCommand)
end

return MPClient
