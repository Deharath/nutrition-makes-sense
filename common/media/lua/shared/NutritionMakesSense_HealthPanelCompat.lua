NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.HealthPanelCompat = NutritionMakesSense.HealthPanelCompat or {}

local HealthPanelCompat = NutritionMakesSense.HealthPanelCompat

local function getCompat()
    local compat = NutritionMakesSense.Compat or rawget(_G, "MakesSenseCompat")
    if type(compat) ~= "table" then
        return nil
    end
    if type(compat.getCallback) ~= "function" then
        return nil
    end
    return compat
end

function HealthPanelCompat.registerCoordinator()
    local compat = getCompat()
    if not compat or type(compat.registerProvider) ~= "function" then
        return
    end

    compat:registerProvider("NutritionMakesSense", {
        capabilities = {
            health_panel_coordinator = true,
        },
        callbacks = {},
    })
end

function HealthPanelCompat.collectExternalLines(compat, playerObj)
    local registry = compat or getCompat()
    if not registry then
        return {}
    end

    local callback = registry:getCallback("CaffeineMakesSense", "collectHealthPanelLines")
    if type(callback) ~= "function" then
        return {}
    end

    local ok, result = pcall(callback, playerObj, {
        host = "NutritionMakesSense",
    })
    if not ok or type(result) ~= "table" then
        return {}
    end

    local lines = {}
    for i = 1, #result do
        local line = result[i]
        if type(line) == "table" and type(line.text) == "string" then
            lines[#lines + 1] = line
        end
    end
    return lines
end

function HealthPanelCompat.mergeLines(externalLines, baseLines)
    local merged = {}
    local compatLines = type(externalLines) == "table" and externalLines or {}
    local ownLines = type(baseLines) == "table" and baseLines or {}

    for i = 1, #compatLines do
        merged[#merged + 1] = compatLines[i]
    end
    for i = 1, #ownLines do
        merged[#merged + 1] = ownLines[i]
    end

    return merged
end

return HealthPanelCompat
