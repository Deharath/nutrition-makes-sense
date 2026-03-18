NutritionMakesSense = NutritionMakesSense or {}

local Data = NutritionMakesSense.Data or {}
NutritionMakesSense.Data = Data

local MOD_BASE_IDS = {
    "NutritionMakesSenseDev",
    "NutritionMakesSense",
}
local MOD_BASE_ID_LOOKUP = {}
local DATA_PATH = "data/food_values.lua"

for _, modId in ipairs(MOD_BASE_IDS) do
    MOD_BASE_ID_LOOKUP[modId] = true
end

local function extractBaseModId(modId)
    if type(modId) ~= "string" or modId == "" then
        return nil
    end

    for i = #modId, 1, -1 do
        if string.sub(modId, i, i) == "\\" then
            return string.sub(modId, i + 1)
        end
    end

    return modId
end

local function collectActiveMatches(activatedMods)
    local matches = {}
    local seenBaseIds = {}

    local function addMatch(modId)
        local baseModId = extractBaseModId(modId)
        if not baseModId or not MOD_BASE_ID_LOOKUP[baseModId] or seenBaseIds[baseModId] then
            return
        end

        seenBaseIds[baseModId] = true
        matches[#matches + 1] = {
            modId = modId,
            baseModId = baseModId,
        }
    end

    if type(activatedMods) == "table" then
        for _, modId in ipairs(activatedMods) do
            addMatch(modId)
        end
        return matches
    end

    if activatedMods and type(activatedMods.size) == "function" and type(activatedMods.get) == "function" then
        for i = 0, activatedMods:size() - 1 do
            addMatch(activatedMods:get(i))
        end
    end

    return matches
end

local function describeMatches(matches)
    local parts = {}
    for _, match in ipairs(matches or {}) do
        parts[#parts + 1] = tostring(match.modId)
    end
    return table.concat(parts, ", ")
end

local function resolveFromActivatedMods()
    if type(getActivatedMods) ~= "function" then
        return nil, nil, "getActivatedMods unavailable"
    end

    local matches = collectActiveMatches(getActivatedMods())
    if #matches == 1 then
        return matches[1].modId, matches[1].baseModId
    end
    if #matches == 0 then
        return nil, nil, "no active NutritionMakesSense variant found in getActivatedMods"
    end

    return nil, nil, "multiple active NutritionMakesSense variants: " .. describeMatches(matches)
end

local function resolveFromModInfo()
    if type(getModInfoByID) ~= "function" or type(isModActive) ~= "function" then
        return nil, nil, "getModInfoByID/isModActive unavailable"
    end

    local matches = {}
    for _, baseModId in ipairs(MOD_BASE_IDS) do
        local modInfo = getModInfoByID(baseModId)
        if modInfo and isModActive(modInfo) then
            local resolvedModId = type(modInfo.getId) == "function" and modInfo:getId() or baseModId
            matches[#matches + 1] = {
                modId = resolvedModId,
                baseModId = baseModId,
            }
        end
    end

    if #matches == 1 then
        return matches[1].modId, matches[1].baseModId
    end
    if #matches == 0 then
        return nil, nil, "no active NutritionMakesSense variant found via getModInfoByID"
    end

    return nil, nil, "multiple active NutritionMakesSense variants: " .. describeMatches(matches)
end

local function resolveActiveModId()
    local modId, baseModId, activationErr = resolveFromActivatedMods()
    if modId then
        return modId, baseModId
    end

    local fallbackModId, fallbackBaseModId, modInfoErr = resolveFromModInfo()
    if fallbackModId then
        return fallbackModId, fallbackBaseModId
    end

    return nil, nil, string.format("%s; %s", tostring(activationErr), tostring(modInfoErr))
end

local function readAll(reader)
    local parts = {}
    while true do
        local line = reader:readLine()
        if not line then
            break
        end
        parts[#parts + 1] = line
    end
    reader:close()
    return table.concat(parts, "\n")
end

local function getModReader(modId)
    if type(getModFileReader) ~= "function" then
        return nil, "getModFileReader unavailable"
    end

    local reader = getModFileReader(modId, DATA_PATH, false)
    if not reader then
        return nil, "data file not found: " .. DATA_PATH
    end

    return reader, nil, DATA_PATH
end

local function loadChunk(source, chunkName)
    if type(loadstring) ~= "function" then
        return nil, "loadstring unavailable"
    end

    local chunk, err = loadstring(source, chunkName)
    if not chunk then
        return nil, err
    end

    local ok, result = pcall(chunk)
    if not ok then
        return nil, result
    end

    if type(result) == "table" then
        return result
    end

    if type(NMS_FoodValues) == "table" then
        return NMS_FoodValues
    end

    return nil, "data chunk did not return a table"
end

local function buildLookups(rawData, activeModId, baseModId)
    local valuesByItemId = {}
    local report = rawData.__stablePatchReport or {}
    local entriesByItemId = {}
    local runtimeEntriesByItemId = {}
    local sourceByItemId = {}

    local function entrySource(entry)
        if type(entry) ~= "table" then
            return nil
        end
        if type(entry.nutrition_source) == "string" and entry.nutrition_source ~= "" then
            return entry.nutrition_source
        end
        return nil
    end

    for key, value in pairs(rawData) do
        if type(key) == "string" and string.sub(key, 1, 2) ~= "__" then
            valuesByItemId[key] = value
        end
    end

    if type(report.entries) == "table" then
        for _, entry in ipairs(report.entries) do
            if type(entry) == "table" and entry.item_id then
                entriesByItemId[entry.item_id] = entry
            end
        end
    end

    if type(report.runtime_entries) == "table" then
        for _, entry in ipairs(report.runtime_entries) do
            if type(entry) == "table" and entry.item_id then
                runtimeEntriesByItemId[entry.item_id] = entry
                sourceByItemId[entry.item_id] = entrySource(entry)
            end
        end
    end

    for itemId, entry in pairs(entriesByItemId) do
        if not runtimeEntriesByItemId[itemId] then
            runtimeEntriesByItemId[itemId] = entry
        end
        if not sourceByItemId[itemId] then
            sourceByItemId[itemId] = entrySource(entry)
        end
    end

    return {
        modId = activeModId,
        baseModId = baseModId or extractBaseModId(activeModId),
        rawData = rawData,
        valuesByItemId = valuesByItemId,
        stableReport = report,
        stableEntriesByItemId = entriesByItemId,
        runtimeEntriesByItemId = runtimeEntriesByItemId,
        sourceByItemId = sourceByItemId,
        classByItemId = sourceByItemId,
    }
end

Data.resolveActiveModId = resolveActiveModId

function Data.loadRuntimeData(forceReload)
    if Data._cache and not forceReload then
        return Data._cache
    end

    local activeModId, baseModId, resolveErr = resolveActiveModId()
    if not activeModId then
        error("failed to resolve active NutritionMakesSense mod: " .. tostring(resolveErr))
    end

    local reader, readErr, dataPath = getModReader(activeModId)
    if not reader and baseModId and baseModId ~= activeModId then
        reader, readErr, dataPath = getModReader(baseModId)
    end
    if not reader then
        error("failed to load curated food data: " .. tostring(activeModId) .. ": " .. tostring(readErr))
    end

    local source = readAll(reader)
    local rawData, loadErr = loadChunk(source, "@" .. tostring(activeModId) .. "/" .. tostring(dataPath or DATA_PATH))
    if not rawData then
        error("failed to load curated food data: " .. tostring(activeModId) .. ": " .. tostring(loadErr))
    end

    Data._cache = buildLookups(rawData, activeModId, baseModId)
    return Data._cache
end

return Data
