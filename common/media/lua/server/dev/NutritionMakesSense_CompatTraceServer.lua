NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.CompatTraceServer = NutritionMakesSense.CompatTraceServer or {}

require "NutritionMakesSense_MPCompat"
require "dev/NutritionMakesSense_CompatTraceShared"

local ServerTrace = NutritionMakesSense.CompatTraceServer
local Shared = NutritionMakesSense.CompatTraceShared or {}

local sessionsByKey = {}

local function getWorldAgeMinutes()
    if type(getGameTime) ~= "function" then
        return 0
    end
    local gameTime = getGameTime()
    local hours = tonumber(gameTime and gameTime:getWorldAgeHours() or nil)
    if hours == nil then
        return 0
    end
    return hours * 60.0
end

local function safeCall(target, methodName, ...)
    if not target then
        return nil
    end
    local fn = target[methodName]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, target, ...)
    if not ok then
        return nil
    end
    return result
end

local function getPlayerKey(playerObj)
    return tostring(safeCall(playerObj, "getOnlineID") or safeCall(playerObj, "getUsername") or safeCall(playerObj, "getDisplayName") or "unknown")
end

local function appendSample(session, playerObj, reason, force)
    local nowMinutes = getWorldAgeMinutes()
    if (not force) and math.abs(nowMinutes - (session.lastSampleMinute or nowMinutes)) < 1 then
        return
    end
    local sample = Shared.collectSample(playerObj, session, {
        label = session.label,
        mode = "mp",
        authority = "server",
        reason = reason or "tick",
    })
    session.rows[#session.rows + 1] = Shared.encodeSample(sample)
    session.lastSampleMinute = nowMinutes
end

function ServerTrace.startForPlayer(playerObj, label)
    if not playerObj then
        return {
            ok = false,
            error = "missing_player",
        }
    end

    local key = getPlayerKey(playerObj)
    local session = {
        label = tostring(label or "dev"),
        mode = "mp",
        authority = "server",
        rows = {},
        startMinute = getWorldAgeMinutes(),
        lastSampleMinute = nil,
        sampleIndex = 0,
    }
    sessionsByKey[key] = {
        player = playerObj,
        trace = session,
    }
    appendSample(session, playerObj, "start", true)
    return {
        ok = true,
        label = session.label,
        sampleCount = #session.rows,
    }
end

function ServerTrace.stopForPlayer(playerObj)
    if not playerObj then
        return {
            ok = false,
            error = "missing_player",
        }
    end

    local key = getPlayerKey(playerObj)
    local entry = sessionsByKey[key]
    if not entry or type(entry.trace) ~= "table" then
        return {
            ok = false,
            error = "not_recording",
        }
    end

    appendSample(entry.trace, playerObj, "stop", true)
    local path, err = Shared.writeSamples(entry.trace.rows, "mscompat_trace_mp", entry.trace.label)
    local count = #entry.trace.rows
    sessionsByKey[key] = nil
    if not path then
        return {
            ok = false,
            error = tostring(err or "save_failed"),
            sampleCount = count,
        }
    end
    return {
        ok = true,
        action = "stopped",
        savedPath = path,
        sampleCount = count,
        label = entry.trace.label,
    }
end

function ServerTrace.sampleAll()
    for key, entry in pairs(sessionsByKey) do
        if not entry.player then
            sessionsByKey[key] = nil
        else
            appendSample(entry.trace, entry.player, "tick", false)
        end
    end
end

return ServerTrace
