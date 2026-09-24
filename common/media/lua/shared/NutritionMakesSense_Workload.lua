NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_CoreUtils"
require "NutritionMakesSense_Model"

-- Live MET sampling. In MP the dedicated server cannot see movement/timed-action state reliably,
-- so clients report their sample and the server prefers a fresh report.
local Workload = NutritionMakesSense.Workload or {}
NutritionMakesSense.Workload = Workload

local CoreUtils = NutritionMakesSense.CoreUtils
local Model = NutritionMakesSense.Model
local safeCall = CoreUtils.safeCall

Workload.REPORT_TTL_SECONDS = 15
local reportsByPlayerKey = {}

local function sample(met, asleep, source)
    return {
        met = Model.clamp(tonumber(met) or Model.MET_REST, Model.MET_SLEEP, Model.MET_MAX),
        asleep = asleep == true,
        source = tostring(source or "rest"),
    }
end

local function getTimedActionMet(playerObj)
    if safeCall(playerObj, "hasTimedActions") ~= true then
        return nil
    end
    local actions = safeCall(playerObj, "getCharacterActions")
    local action = actions and safeCall(actions, "get", 0) or nil
    if not action then
        return nil
    end
    local modifier = tonumber(action.caloriesModifier) or tonumber(safeCall(action, "getCaloriesModifier"))
    if modifier and modifier > 0 then
        return modifier
    end
    return nil
end

local function getThermoMet(playerObj)
    local thermoregulator = CoreUtils.getPlayerThermoregulator(playerObj)
    if not thermoregulator then
        return nil
    end
    local target = tonumber(safeCall(thermoregulator, "getMetabolicTarget"))
    local real = tonumber(safeCall(thermoregulator, "getMetabolicRateReal"))
    local met = (target and target > 0) and target or real
    if not met or met <= 0 then
        return nil
    end
    return math.max(met, real or met)
end

function Workload.sampleLocal(playerObj)
    if not playerObj then
        return sample(Model.MET_REST, false, "none")
    end
    if safeCall(playerObj, "isAsleep") == true then
        return sample(Model.MET_SLEEP, true, "sleep")
    end

    local actionMet = getTimedActionMet(playerObj)
    local thermoMet = getThermoMet(playerObj)
    if actionMet and (not thermoMet or actionMet > thermoMet + 0.1) then
        return sample(actionMet, false, "timed_action")
    end
    if thermoMet then
        return sample(thermoMet, false, "thermo")
    end
    if safeCall(playerObj, "isAttacking") == true then
        return sample(6.0, false, "attacking")
    end
    if safeCall(playerObj, "isSprinting") == true then
        return sample(9.5, false, "sprint")
    end
    if safeCall(playerObj, "isRunning") == true then
        return sample(6.9, false, "run")
    end
    if safeCall(playerObj, "isPlayerMoving") == true then
        return sample(safeCall(playerObj, "isSneaking") == true and 2.0 or 3.1, false, "walk")
    end
    return sample(Model.MET_REST, false, "rest")
end

local function wallSeconds()
    if type(getTimestampMs) == "function" then
        return (tonumber(getTimestampMs()) or 0) / 1000
    end
    return os.time()
end
Workload.wallSeconds = wallSeconds

local function playerKey(playerObj)
    local onlineId = tonumber(safeCall(playerObj, "getOnlineID"))
    if onlineId ~= nil then
        return "online:" .. tostring(onlineId)
    end
    return tostring(playerObj)
end
Workload.playerKey = playerKey

function Workload.acceptReport(playerObj, args)
    if not playerObj or type(args) ~= "table" or tonumber(args.met) == nil then
        return nil
    end
    local report = sample(args.met, args.asleep == true, "mp_" .. tostring(args.source or "client"))
    report.receivedAt = wallSeconds()
    reportsByPlayerKey[playerKey(playerObj)] = report
    return report
end

function Workload.forget(playerObj)
    reportsByPlayerKey[playerKey(playerObj)] = nil
end

-- Authority-side sample: fresh client report on a dedicated server, local sampling otherwise.
function Workload.sampleForAuthority(playerObj)
    if type(isServer) == "function" and isServer() then
        local report = reportsByPlayerKey[playerKey(playerObj)]
        if report and (wallSeconds() - report.receivedAt) <= Workload.REPORT_TTL_SECONDS then
            return report
        end
        if safeCall(playerObj, "isAsleep") == true then
            return sample(Model.MET_SLEEP, true, "server_sleep")
        end
        return sample(Model.MET_REST + 0.3, false, "server_fallback")
    end
    return Workload.sampleLocal(playerObj)
end

return Workload
