NutritionMakesSense = NutritionMakesSense or {}

local DevSupport = NutritionMakesSense.DevSupport or {}
NutritionMakesSense.DevSupport = DevSupport

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

function DevSupport.isDebugLaunch()
    return isDebugLaunch()
end

function DevSupport.canUseDevTools()
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

local function resolveDevPanel()
    local panel = NutritionMakesSense and NutritionMakesSense.DevPanel or nil
    if not panel or type(panel) ~= "table" then
        return nil
    end
    return panel
end

function DevSupport.noteConsumeEvent(event)
    local panel = resolveDevPanel()
    if panel and type(panel.noteConsumeEvent) == "function" then
        panel.noteConsumeEvent(event)
    end
end

function DevSupport.noteSeedEvent(event)
    local panel = resolveDevPanel()
    if panel and type(panel.noteSeedEvent) == "function" then
        panel.noteSeedEvent(event)
    end
end

return DevSupport
