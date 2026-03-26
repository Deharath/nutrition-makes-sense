NutritionMakesSense = NutritionMakesSense or {}

local CoreUtils = NutritionMakesSense.CoreUtils or {}
NutritionMakesSense.CoreUtils = CoreUtils

local function safeCall(target, methodName, ...)
    if not target then
        return nil
    end

    local method = target[methodName]
    if type(method) ~= "function" then
        return nil
    end

    local ok, result = pcall(method, target, ...)
    if not ok then
        return nil
    end

    return result
end

local function safeInvoke(target, methodName, ...)
    if not target then
        return false, nil
    end

    local method = target[methodName]
    if type(method) ~= "function" then
        return false, nil
    end

    local ok, result = pcall(method, target, ...)
    if not ok then
        return false, nil
    end

    return true, result
end

local function getLocalPlayer(playerIndex)
    if type(getSpecificPlayer) == "function" and playerIndex ~= nil then
        local resolved = getSpecificPlayer(playerIndex)
        if resolved then
            return resolved
        end
    end

    if type(getPlayer) ~= "function" then
        return nil
    end

    local ok, playerObj = pcall(getPlayer)
    if ok then
        return playerObj
    end

    return nil
end

local function getPlayerLabel(playerObj, fallback)
    local username = safeCall(playerObj, "getUsername")
    if username and username ~= "" then
        return tostring(username)
    end

    local displayName = safeCall(playerObj, "getDisplayName")
    if displayName and displayName ~= "" then
        return tostring(displayName)
    end

    local onlineId = safeCall(playerObj, "getOnlineID")
    if onlineId ~= nil then
        return tostring(onlineId)
    end

    return tostring(fallback or playerObj or "unknown")
end

local function eachKnownPlayer(callback)
    if type(callback) ~= "function" then
        return
    end

    if type(isServer) == "function" and isServer() and type(getOnlinePlayers) == "function" then
        local players = getOnlinePlayers()
        if not players then
            return
        end
        local count = tonumber(safeCall(players, "size")) or 0
        for index = 0, count - 1 do
            local playerObj = safeCall(players, "get", index)
            if playerObj then
                callback(playerObj, index)
            end
        end
        return
    end

    if type(getNumActivePlayers) == "function" and type(getSpecificPlayer) == "function" then
        local playerCount = tonumber(getNumActivePlayers()) or 0
        for playerIndex = 0, playerCount - 1 do
            local playerObj = getSpecificPlayer(playerIndex)
            if playerObj then
                callback(playerObj, playerIndex)
            end
        end
        return
    end

    local playerObj = getLocalPlayer()
    if playerObj then
        callback(playerObj, 0)
    end
end

local function visitList(list, callback)
    if type(callback) ~= "function" or not list then
        return
    end

    local size = safeCall(list, "size")
    if type(size) == "number" then
        for index = 0, size - 1 do
            callback(safeCall(list, "get", index), index)
        end
        return
    end

    if type(list) == "table" then
        for index, value in ipairs(list) do
            callback(value, index - 1)
        end
    end
end

local function normalizeUnitFraction(value)
    local requested = tonumber(value)
    if requested == nil or requested ~= requested then
        return nil, nil, false
    end

    if requested <= 0 then
        return requested, 0, false
    end

    local applied = requested
    local clamped = false
    if applied > 1 then
        applied = 1
        clamped = true
    end

    return requested, applied, clamped
end

local function resolveInventoryItemById(playerObj, itemId)
    local inventory = playerObj and safeCall(playerObj, "getInventory") or nil
    if not inventory or itemId == nil then
        return nil
    end

    local item = safeCall(inventory, "getItemWithID", itemId)
    if item then
        return item
    end

    item = safeCall(inventory, "getItemById", itemId)
    if item then
        return item
    end

    return safeCall(inventory, "getItemWithIDRecursiv", itemId)
end

local function tryMethod(target, methodName, ...)
    if not target then
        return false, nil
    end

    local method = target[methodName]
    if type(method) ~= "function" then
        return false, nil
    end

    local ok, result = pcall(method, target, ...)
    if not ok then
        return false, nil
    end

    return true, result
end

local function rawLookup(tableLike, key)
    if not tableLike then
        return nil
    end
    if type(tableLike.rawget) == "function" then
        local ok, value = pcall(tableLike.rawget, tableLike, key)
        if ok then
            return value
        end
    end
    if type(tableLike) == "table" then
        return tableLike[key]
    end
    return nil
end

local function clamp01(value)
    local numeric = tonumber(value) or 0
    if numeric < 0 then
        return 0
    end
    if numeric > 1 then
        return 1
    end
    return numeric
end

local function numbersClose(a, b, epsilon)
    local limit = tonumber(epsilon) or 0.001
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= limit
end

local function resolveItemFullType(itemOrFullType)
    if type(itemOrFullType) == "string" and itemOrFullType ~= "" then
        return itemOrFullType
    end
    if itemOrFullType ~= nil then
        local fullType = safeCall(itemOrFullType, "getFullType")
        if fullType and tostring(fullType) ~= "" then
            return tostring(fullType)
        end

        local itemType = safeCall(itemOrFullType, "getType")
        local itemModule = safeCall(itemOrFullType, "getModule")
        if itemModule and itemModule ~= "" and itemType and itemType ~= "" then
            return tostring(itemModule) .. "." .. tostring(itemType)
        end

        if itemType and tostring(itemType) ~= "" then
            return tostring(itemType)
        end

        if type(itemOrFullType) == "table" then
            local tableFullType = itemOrFullType.fullType or itemOrFullType.id
            if tableFullType and tostring(tableFullType) ~= "" then
                return tostring(tableFullType)
            end
        end

        local rawString = tostring(itemOrFullType)
        if rawString ~= "" and rawString ~= "nil" and string.find(rawString, "%.") then
            return rawString
        end
    end
    return nil
end

local function roundToStep(value, step)
    local numeric = tonumber(value) or 0
    local unit = tonumber(step) or 1
    if unit <= 0 then
        return numeric
    end
    return math.floor((numeric / unit) + 0.5) * unit
end

local function getWorldHours()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    return tonumber(gameTime and safeCall(gameTime, "getWorldAgeHours") or nil)
end

local function getPlayerStats(playerObj)
    return safeCall(playerObj, "getStats")
end

local function getPlayerNutrition(playerObj)
    return safeCall(playerObj, "getNutrition")
end

local function getPlayerBodyDamage(playerObj)
    return safeCall(playerObj, "getBodyDamage")
end

local function getPlayerThermoregulator(playerObj)
    local bodyDamage = getPlayerBodyDamage(playerObj)
    return bodyDamage and safeCall(bodyDamage, "getThermoregulator") or nil
end

local function getCharacterStatValue(stats, enumKey, getterName)
    if not stats then
        return nil
    end

    if CharacterStat and enumKey and CharacterStat[enumKey] then
        local value = safeCall(stats, "get", CharacterStat[enumKey])
        if value ~= nil then
            return tonumber(value)
        end
    end

    if getterName then
        return tonumber(safeCall(stats, getterName))
    end

    return nil
end

function CoreUtils.safeCall(target, methodName, ...)
    return safeCall(target, methodName, ...)
end

function CoreUtils.safeInvoke(target, methodName, ...)
    return safeInvoke(target, methodName, ...)
end

function CoreUtils.getLocalPlayer(playerIndex)
    return getLocalPlayer(playerIndex)
end

function CoreUtils.getPlayerLabel(playerObj, fallback)
    return getPlayerLabel(playerObj, fallback)
end

function CoreUtils.eachKnownPlayer(callback)
    eachKnownPlayer(callback)
end

function CoreUtils.visitList(list, callback)
    visitList(list, callback)
end

function CoreUtils.normalizeUnitFraction(value)
    return normalizeUnitFraction(value)
end

function CoreUtils.resolveInventoryItemById(playerObj, itemId)
    return resolveInventoryItemById(playerObj, itemId)
end

function CoreUtils.tryMethod(target, methodName, ...)
    return tryMethod(target, methodName, ...)
end

function CoreUtils.rawLookup(tableLike, key)
    return rawLookup(tableLike, key)
end

function CoreUtils.clamp01(value)
    return clamp01(value)
end

function CoreUtils.numbersClose(a, b, epsilon)
    return numbersClose(a, b, epsilon)
end

function CoreUtils.resolveItemFullType(itemOrFullType)
    return resolveItemFullType(itemOrFullType)
end

function CoreUtils.roundToStep(value, step)
    return roundToStep(value, step)
end

function CoreUtils.getWorldHours()
    return getWorldHours()
end

function CoreUtils.getPlayerStats(playerObj)
    return getPlayerStats(playerObj)
end

function CoreUtils.getPlayerNutrition(playerObj)
    return getPlayerNutrition(playerObj)
end

function CoreUtils.getPlayerBodyDamage(playerObj)
    return getPlayerBodyDamage(playerObj)
end

function CoreUtils.getPlayerThermoregulator(playerObj)
    return getPlayerThermoregulator(playerObj)
end

function CoreUtils.getCharacterStatValue(stats, enumKey, getterName)
    return getCharacterStatValue(stats, enumKey, getterName)
end

return CoreUtils
