NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.DevPanelSink = NutritionMakesSense.DevPanelSink or {}

local DevPanelSink = NutritionMakesSense.DevPanelSink
local DebugSupport = NutritionMakesSense.DebugSupport or {}

local SINK_NAME = "DevPanel"

function DevPanelSink.attach(panel)
    if type(DebugSupport.registerEventSink) ~= "function" then
        return false
    end

    return DebugSupport.registerEventSink(SINK_NAME, panel)
end

function DevPanelSink.detach()
    if type(DebugSupport.unregisterEventSink) ~= "function" then
        return false
    end

    return DebugSupport.unregisterEventSink(SINK_NAME)
end

return DevPanelSink
