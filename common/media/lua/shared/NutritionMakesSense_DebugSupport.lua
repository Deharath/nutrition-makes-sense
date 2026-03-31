NutritionMakesSense = NutritionMakesSense or {}

local DebugSupport = NutritionMakesSense.DebugSupport or {}
NutritionMakesSense.DebugSupport = DebugSupport

local eventSinks = DebugSupport._eventSinks or {}
DebugSupport._eventSinks = eventSinks

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

function DebugSupport.canUseDevTools()
    if isDebugLaunch() then
        return true
    end

    if type(isClient) == "function" and isClient() and type(getAccessLevel) == "function" then
        local ok, accessLevel = pcall(getAccessLevel)
        if ok and (accessLevel == "admin" or accessLevel == "moderator") then
            return true
        end
    end

    return false
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

function DebugSupport.getEventSinkCount()
    local count = 0
    for _, _ in pairs(eventSinks) do
        count = count + 1
    end
    return count
end

local function dispatchEvent(methodName, event)
    for _, sink in pairs(eventSinks) do
        local handler = sink and sink[methodName] or nil
        if type(handler) == "function" then
            pcall(handler, sink, event)
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
