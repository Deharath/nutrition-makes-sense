NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.DevPanelSink = NutritionMakesSense.DevPanelSink or {}

local DevPanelSink = NutritionMakesSense.DevPanelSink
local DevSupport = NutritionMakesSense.DevSupport or {}

local SINK_NAME = "DevPanel"

function DevPanelSink.attach(panel)
    if type(DevSupport.registerEventSink) ~= "function" then
        return false
    end

    return DevSupport.registerEventSink(SINK_NAME, panel)
end

function DevPanelSink.detach()
    if type(DevSupport.unregisterEventSink) ~= "function" then
        return false
    end

    return DevSupport.unregisterEventSink(SINK_NAME)
end

return DevPanelSink
