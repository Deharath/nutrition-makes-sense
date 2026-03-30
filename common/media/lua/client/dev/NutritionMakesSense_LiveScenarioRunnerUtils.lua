NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.LiveScenarioRunnerUtils = NutritionMakesSense.LiveScenarioRunnerUtils or {}

require "NutritionMakesSense_CoreUtils"

local Utils = NutritionMakesSense.LiveScenarioRunnerUtils
local Metabolism = NutritionMakesSense.Metabolism or {}
local CoreUtils = NutritionMakesSense.CoreUtils or {}
local safeCall = CoreUtils.safeCall
local safeInvoke = CoreUtils.safeInvoke

function Utils.copyTable(source)
    if type(source) ~= "table" then
        return nil
    end
    local out = {}
    for key, value in pairs(source) do
        out[key] = value
    end
    return out
end

function Utils.clamp(value, minValue, maxValue)
    return Metabolism.clamp and Metabolism.clamp(value, minValue, maxValue)
        or math.max(minValue, math.min(maxValue, value))
end

function Utils.nearlyEqual(actual, expected, tolerance)
    return math.abs((tonumber(actual) or 0) - (tonumber(expected) or 0)) <= (tolerance or 0.001)
end

function Utils.normalizeStartWeightKg(value)
    local fallback = tonumber(Metabolism.DEFAULT_WEIGHT_KG) or 80
    local numeric = tonumber(value)
    if numeric == nil then
        return fallback
    end
    return Utils.clamp(numeric, tonumber(Metabolism.WEIGHT_MIN_KG) or 35, tonumber(Metabolism.WEIGHT_MAX_KG) or 140)
end

function Utils.csvEscape(value)
    local text = tostring(value == nil and "" or value)
    if text:find('[,"\n]') then
        text = '"' .. text:gsub('"', '""') .. '"'
    end
    return text
end

function Utils.openWriter(relPath)
    if type(getFileWriter) ~= "function" then
        return nil
    end
    local ok, handle = pcall(getFileWriter, relPath, true, false)
    if ok and handle then
        return handle
    end
    return nil
end

function Utils.getLocalPlayer()
    return CoreUtils.getLocalPlayer()
end

function Utils.getWorldHours()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    return tonumber(gameTime and safeCall(gameTime, "getWorldAgeHours") or nil)
end

function Utils.getTimeMultiplier()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    return tonumber(gameTime and safeCall(gameTime, "getMultiplier") or nil)
end

function Utils.getGameSpeedMode()
    if type(getGameSpeed) ~= "function" then
        return nil
    end
    local ok, value = pcall(getGameSpeed)
    if ok then
        return tonumber(value)
    end
    return nil
end

function Utils.getGameSpeedModeForMultiplier(multiplier)
    local requested = tonumber(multiplier) or 1
    if requested <= 1.01 then
        return 1
    end
    if requested <= 5.01 then
        return 2
    end
    if requested <= 20.01 then
        return 3
    end
    return 4
end

function Utils.setTimeMultiplier(multiplier)
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    if not gameTime then
        return false
    end
    if type(setGameSpeed) == "function" then
        pcall(setGameSpeed, Utils.getGameSpeedModeForMultiplier(multiplier))
    end
    local ok = safeInvoke(gameTime, "setMultiplier", tonumber(multiplier) or 1)
    if not ok then
        return false
    end
    return true
end

function Utils.restoreGameSpeedMode(mode)
    if type(setGameSpeed) ~= "function" then
        return false
    end
    local ok = pcall(setGameSpeed, tonumber(mode) or 1)
    return ok == true
end

function Utils.getExpectedEffectiveMultiplier(baseMultiplier, requestedMultiplier)
    local base = tonumber(baseMultiplier)
    local requested = tonumber(requestedMultiplier)
    if base == nil or requested == nil then
        return nil
    end
    return base * requested
end

function Utils.validateRequestedTimeAcceleration(run, requestedMultiplier)
    if not run or not run.snapshot or not run.snapshot.visible then
        return false
    end

    local before = tonumber(run.snapshot.visible.timeMultiplier)
    local actual = tonumber(Utils.getTimeMultiplier())
    local requested = tonumber(requestedMultiplier)
    local expectedEffective = Utils.getExpectedEffectiveMultiplier(before, requested)
    if before == nil or actual == nil or requested == nil or expectedEffective == nil then
        return false
    end

    local ratio = before ~= 0 and (actual / before) or nil
    run.lastAppliedTimeRatio = ratio
    run.lastAppliedTimeActual = actual
    run.lastAppliedTimeExpected = expectedEffective

    local expectedMode = Utils.getGameSpeedModeForMultiplier(requested)
    local actualMode = Utils.getGameSpeedMode()
    if requested > 1 and actualMode ~= nil and tonumber(actualMode) == tonumber(expectedMode) then
        if actual ~= nil and actual >= 1.5 then
            return true
        end
    end

    if ratio ~= nil and requested > 1 and math.abs(ratio - requested) <= 0.75 then
        return true
    end

    return math.abs(actual - expectedEffective) <= math.max(0.25, math.abs(expectedEffective) * 0.05)
end

function Utils.getPlayerStats(playerObj)
    return playerObj and safeCall(playerObj, "getStats") or nil
end

function Utils.getPlayerNutrition(playerObj)
    return playerObj and safeCall(playerObj, "getNutrition") or nil
end

function Utils.getPlayerBodyDamage(playerObj)
    return playerObj and safeCall(playerObj, "getBodyDamage") or nil
end

function Utils.getCharacterStat(stats, enumKey, getterName)
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

function Utils.setCharacterStat(stats, enumKey, setterName, value)
    if not stats then
        return false
    end
    if CharacterStat and enumKey and CharacterStat[enumKey] then
        local ok = safeInvoke(stats, "set", CharacterStat[enumKey], value)
        if ok then
            return true
        end
    end
    if setterName then
        local ok = safeInvoke(stats, setterName, value)
        if ok then
            return true
        end
    end
    return false
end

function Utils.getTimedActionQueue(playerObj)
    if type(ISTimedActionQueue) ~= "table" or type(ISTimedActionQueue.getTimedActionQueue) ~= "function" then
        return nil
    end
    return ISTimedActionQueue.getTimedActionQueue(playerObj)
end

function Utils.clearTimedActions(playerObj)
    local queue = Utils.getTimedActionQueue(playerObj)
    if queue and type(queue.clearQueue) == "function" then
        queue:clearQueue()
    end
end

function Utils.hasTimedActions(playerObj)
    if safeCall(playerObj, "hasTimedActions") == true then
        return true
    end
    local queue = Utils.getTimedActionQueue(playerObj)
    if queue and type(queue.queue) == "table" and #queue.queue > 0 then
        return true
    end
    return false
end

function Utils.getInventory(playerObj)
    return playerObj and safeCall(playerObj, "getInventory") or nil
end

function Utils.inventoryContainsItem(inventory, item)
    if not inventory or not item then
        return false
    end
    local itemId = tonumber(safeCall(item, "getID"))
    if itemId ~= nil and safeCall(inventory, "containsID", itemId) == true then
        return true
    end
    return safeCall(inventory, "contains", item) == true
end

function Utils.removeInventoryItem(inventory, item)
    if not inventory or not item or not Utils.inventoryContainsItem(inventory, item) then
        return true
    end
    if safeInvoke(inventory, "DoRemoveItem", item) then
        return not Utils.inventoryContainsItem(inventory, item)
    end
    if safeInvoke(inventory, "Remove", item) then
        return not Utils.inventoryContainsItem(inventory, item)
    end
    return false
end

function Utils.getFoodEatenMoodle(playerObj)
    local moodles = playerObj and safeCall(playerObj, "getMoodles") or nil
    if not moodles or not MoodleType or not MoodleType.FOOD_EATEN then
        return nil
    end
    return tonumber(safeCall(moodles, "getMoodleLevel", MoodleType.FOOD_EATEN))
end

function Utils.getHungryMoodleLevel(playerObj)
    local moodles = playerObj and safeCall(playerObj, "getMoodles") or nil
    if not moodles or not MoodleType or not MoodleType.HUNGRY then
        return nil
    end
    return tonumber(safeCall(moodles, "getMoodleLevel", MoodleType.HUNGRY))
end

function Utils.formatMetricHour(hour)
    if hour == nil then
        return "--"
    end
    return string.format("%.2fh", tonumber(hour) or 0)
end

function Utils.formatMetricNumber(value, fmt)
    if value == nil then
        return "--"
    end
    return string.format(fmt or "%.3f", tonumber(value) or 0)
end

function Utils.makeMetricEvent(scenarioClockLabelFn, profile, snapshot, elapsedHours)
    local state = snapshot and snapshot.state or {}
    return {
        hour = tonumber(elapsedHours) or 0,
        clock = scenarioClockLabelFn and scenarioClockLabelFn(profile, elapsedHours) or "--",
        fuel = tonumber(state and state.fuel) or 0,
        deprivation = tonumber(state and state.deprivation) or 0,
        hunger = tonumber(snapshot and snapshot.hunger) or 0,
        zone = tostring(state and state.lastZone or ""),
    }
end

function Utils.measureMealConfirmation(preSnapshot, postSnapshot, expected)
    local preState = preSnapshot and preSnapshot.state or {}
    local postState = postSnapshot and postSnapshot.state or {}
    local expectedKcal = tonumber(expected and expected.kcal or 0) or 0
    local expectedProteins = tonumber(expected and expected.proteins or 0) or 0
    local fuelDelta = (tonumber(postState and postState.fuel) or 0) - (tonumber(preState and preState.fuel) or 0)
    local proteinDelta = (tonumber(postState and postState.proteins) or 0) - (tonumber(preState and preState.proteins) or 0)
    local satietyDelta = (tonumber(postState and postState.satietyBuffer) or 0) - (tonumber(preState and preState.satietyBuffer) or 0)
    local hungerDrop = (tonumber(preSnapshot and preSnapshot.hunger) or 0) - (tonumber(postSnapshot and postSnapshot.hunger) or 0)
    local lastDepositKcal = tonumber(postState and postState.lastDepositKcal or 0) or 0
    local confirmed = false

    if expectedKcal <= 0 then
        confirmed = fuelDelta > 1 or proteinDelta > 0.1 or satietyDelta > 0.01 or hungerDrop > 0.005 or lastDepositKcal > 0
    else
        confirmed = lastDepositKcal > 0
            or fuelDelta >= math.min(25, expectedKcal * 0.2)
            or proteinDelta >= math.min(2, math.max(0.5, expectedProteins * 0.4))
            or satietyDelta >= 0.02
            or hungerDrop >= 0.01
    end

    return {
        confirmed = confirmed,
        expectedKcal = expectedKcal,
        lastDepositKcal = lastDepositKcal,
        fuelDelta = fuelDelta,
        proteinDelta = proteinDelta,
        satietyDelta = satietyDelta,
        hungerDrop = hungerDrop,
    }
end

function Utils.deriveOutcome(run)
    if (run and run.failCount or 0) > 0 then
        return "FAIL"
    end
    if (run and run.warnCount or 0) > 0 then
        return "WARN"
    end
    return "PASS"
end

function Utils.saveReport(run, reportHeader)
    if not run then
        return nil
    end
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local outcome = string.lower(tostring(run.outcome or Utils.deriveOutcome(run) or "pass"))
    local relPath = string.format("nmslogs/nms_live_%s_%s_%s.csv", tostring(run.profile and run.profile.id or "scenario"), outcome, timestamp)
    local writer = Utils.openWriter(relPath)
    if not writer then
        return nil
    end
    writer:writeln(reportHeader)
    for _, row in ipairs(run.reportRows or {}) do
        writer:writeln(row)
    end
    writer:close()
    return relPath
end

return Utils
