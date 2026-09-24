NutritionMakesSense = NutritionMakesSense or {}

local DebugSupport = NutritionMakesSense.DebugSupport or {}
NutritionMakesSense.DebugSupport = DebugSupport

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

return DebugSupport
