NutritionMakesSense = NutritionMakesSense or {}

local DebugSupport = NutritionMakesSense.DebugSupport or {}
NutritionMakesSense.DebugSupport = DebugSupport

local eventSinks = DebugSupport._eventSinks or {}
DebugSupport._eventSinks = eventSinks
local DEV_MOD_ID = "NutritionMakesSenseDev"

local function normalizeModId(value)
    local modId = tostring(value or "")
    while string.sub(modId, 1, 1) == "\\" do
        modId = string.sub(modId, 2)
    end
    return modId
end

local function isDevBuild()
    if type(getActivatedMods) ~= "function" then
        return false
    end

    local okMods, activeMods = pcall(getActivatedMods)
    if not okMods or not activeMods then
        return false
    end

    local okSize, size = pcall(function()
        return activeMods:size()
    end)
    if okSize and tonumber(size) then
        for index = 0, tonumber(size) - 1 do
            local okEntry, modId = pcall(function()
                return activeMods:get(index)
            end)
            if okEntry and normalizeModId(modId) == DEV_MOD_ID then
                return true
            end
        end
        return false
    end

    if type(activeMods) == "table" then
        for _, modId in pairs(activeMods) do
            if normalizeModId(modId) == DEV_MOD_ID then
                return true
            end
        end
    end
    return false
end

local function isDebugLaunch()
    if type(isDebugEnabled) == "function" and isDebugEnabled() then
        return true
    end

    local core = type(getCore) == "function" and getCore() or nil
    if core and type(core.getDebug) == "function" then
        local ok, enabled = pcall(core.getDebug, core)
        if ok and enabled then
            return true
        end
    end

    return false
end

function DebugSupport.isDebugLaunch()
    return isDebugLaunch()
end

function DebugSupport.isDevBuild()
    return isDevBuild()
end

function DebugSupport.canUseDevTools()
    return isDebugLaunch() and isDevBuild()
end

local function normalizeSink(sink)
    if type(sink) ~= "table" then
        return nil
    end

    if type(sink.noteConsumeEvent) ~= "function" and type(sink.noteSeedEvent) ~= "function" then
        return nil
    end

    return sink
end

function DebugSupport.registerEventSink(name, sink)
    local key = tostring(name or "")
    if key == "" then
        return false
    end

    local normalized = normalizeSink(sink)
    if not normalized then
        return false
    end

    eventSinks[key] = normalized
    return true
end

function DebugSupport.unregisterEventSink(name)
    local key = tostring(name or "")
    if key == "" then
        return false
    end

    local existed = eventSinks[key] ~= nil
    eventSinks[key] = nil
    return existed
end

local function dispatchEvent(methodName, event)
    for _, sink in pairs(eventSinks) do
        local handler = sink and sink[methodName] or nil
        if type(handler) == "function" then
            local info = debug and debug.getinfo and debug.getinfo(handler, "u") or nil
            if info and tonumber(info.nparams) == 1 and info.isvararg ~= true then
                pcall(handler, event)
            else
                pcall(handler, sink, event)
            end
        end
    end
end

function DebugSupport.noteConsumeEvent(event)
    dispatchEvent("noteConsumeEvent", event)
end

function DebugSupport.noteSeedEvent(event)
    dispatchEvent("noteSeedEvent", event)
end

return DebugSupport
