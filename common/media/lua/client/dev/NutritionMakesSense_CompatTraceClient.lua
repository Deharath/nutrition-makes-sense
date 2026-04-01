NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.CompatTraceClient = NutritionMakesSense.CompatTraceClient or {}

require "NutritionMakesSense_MPCompat"
require "dev/NutritionMakesSense_CompatTraceShared"

local ClientTrace = NutritionMakesSense.CompatTraceClient
local MP = NutritionMakesSense.MP or {}
local Shared = NutritionMakesSense.CompatTraceShared or {}

local SAMPLE_INTERVAL_MINUTES = 1

local localState = {
    active = false,
    label = nil,
    mode = "sp",
    authority = "client",
    rows = {},
    startMinute = nil,
    lastSampleMinute = nil,
    sampleIndex = 0,
}

local mpState = {
    active = false,
    pending = false,
    label = nil,
    lastStatus = nil,
    lastSavedPath = nil,
    sampleCount = 0,
}

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

local function isMpClient()
    return type(isClient) == "function" and isClient() == true
end

local function getLocalPlayerSafe()
    if type(getPlayer) ~= "function" then
        return nil
    end
    local ok, playerObj = pcall(getPlayer)
    if not ok then
        return nil
    end
    return playerObj
end

local function sendTraceCommand(command, args)
    if not isMpClient() or type(sendClientCommand) ~= "function" then
        return false
    end
    local ok, err = pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(command), args or {})
    if not ok then
        print("[NutritionMakesSense] compat trace command failed: " .. tostring(err))
        return false
    end
    return true
end

local function formatSavedPath(savedPath)
    local path = tostring(savedPath or "")
    if path == "" then
        return path
    end
    if string.find(path, "Zomboid/Lua/", 1, true) then
        return path
    end
    return "Zomboid/Lua/" .. path
end

local function appendLocalSample(reason, force)
    if not localState.active then
        return
    end
    local nowMinutes = getWorldAgeMinutes()
    if (not force) and math.abs(nowMinutes - (localState.lastSampleMinute or nowMinutes)) < SAMPLE_INTERVAL_MINUTES then
        return
    end
    local playerObj = getLocalPlayerSafe()
    if not playerObj then
        return
    end
    local sample = Shared.collectSample(playerObj, localState, {
        label = localState.label,
        mode = "sp",
        authority = "client",
        reason = reason or "tick",
    })
    localState.rows[#localState.rows + 1] = Shared.encodeSample(sample)
    localState.lastSampleMinute = nowMinutes
end

function ClientTrace.start(label)
    local traceLabel = tostring(label or "dev")
    if isMpClient() then
        if not sendTraceCommand(MP.COMPAT_TRACE_START_COMMAND, { label = traceLabel }) then
            return false, "mp_send_failed"
        end
        mpState.active = false
        mpState.pending = true
        mpState.label = traceLabel
        mpState.lastStatus = "requested"
        return true, "mp"
    end

    localState.active = true
    localState.label = traceLabel
    localState.mode = "sp"
    localState.authority = "client"
    localState.rows = {}
    localState.startMinute = getWorldAgeMinutes()
    localState.lastSampleMinute = nil
    localState.sampleIndex = 0
    appendLocalSample("start", true)
    return true, "sp"
end

function ClientTrace.stop()
    if isMpClient() then
        if not mpState.active then
            return nil, 0, "mp_idle"
        end
        if not sendTraceCommand(MP.COMPAT_TRACE_STOP_COMMAND, { label = tostring(mpState.label or "dev") }) then
            return nil, 0, "mp_send_failed"
        end
        mpState.pending = true
        return nil, 0, "mp"
    end

    if not localState.active then
        return nil, 0, "sp_idle"
    end

    appendLocalSample("stop", true)
    local path, err = Shared.writeSamples(localState.rows, "mscompat_trace_sp", localState.label)
    local count = #localState.rows
    localState.active = false
    localState.label = nil
    localState.rows = {}
    localState.startMinute = nil
    localState.lastSampleMinute = nil
    localState.sampleIndex = 0
    if not path then
        print("[NutritionMakesSense] compat trace save failed: " .. tostring(err))
        return nil, count, tostring(err or "save_failed")
    end
    return path, count, nil
end

function ClientTrace.sampleTick(force)
    if localState.active then
        appendLocalSample("tick", force == true)
    end
end

function ClientTrace.isRecording()
    return localState.active or mpState.active or mpState.pending
end

function ClientTrace.getStatus()
    if localState.active then
        return {
            active = true,
            mode = "sp",
            sampleCount = #localState.rows,
            label = localState.label,
            lastSavedPath = nil,
            pending = false,
        }
    end
    return {
        active = mpState.active,
        mode = (mpState.active or mpState.pending) and "mp" or "idle",
        sampleCount = mpState.sampleCount,
        label = mpState.label,
        lastSavedPath = mpState.lastSavedPath,
        pending = mpState.pending,
        lastStatus = mpState.lastStatus,
    }
end

local function onServerCommand(module, command, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end
    if tostring(command) ~= tostring(MP.COMPAT_TRACE_STATUS_COMMAND) then
        return
    end
    if type(args) ~= "table" then
        return
    end

    local action = tostring(args.action or "")
    mpState.pending = false
    mpState.lastStatus = action
    mpState.sampleCount = tonumber(args.sampleCount) or mpState.sampleCount or 0
    mpState.lastSavedPath = tostring(args.savedPath or mpState.lastSavedPath or "")

    if action == "started" then
        mpState.active = true
        mpState.label = tostring(args.label or mpState.label or "dev")
        print(string.format("[NutritionMakesSense] compat trace started on server (label=%s)", mpState.label))
        return
    end

    if action == "stopped" then
        local savedPath = formatSavedPath(args.savedPath or "")
        local count = tonumber(args.sampleCount) or 0
        print(string.format("[NutritionMakesSense] compat trace saved: %s (%d samples)", savedPath, count))
        mpState.active = false
        mpState.label = nil
        mpState.sampleCount = count
        return
    end

    if action == "error" then
        print("[NutritionMakesSense] compat trace server error: " .. tostring(args.error or "unknown"))
        mpState.active = false
    end
end

if Events and Events.OnServerCommand and type(Events.OnServerCommand.Add) == "function" and not ClientTrace._registered then
    ClientTrace._registered = true
    Events.OnServerCommand.Add(onServerCommand)
end

return ClientTrace
