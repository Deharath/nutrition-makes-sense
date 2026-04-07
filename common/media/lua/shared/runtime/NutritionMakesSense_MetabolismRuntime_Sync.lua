NutritionMakesSense = NutritionMakesSense or {}

local Runtime = NutritionMakesSense.MetabolismRuntime or {}

local Metabolism = Runtime.Metabolism or {}
local MP = Runtime.MP or {}
local STATE_KEY = Runtime.STATE_KEY
local getModData = Runtime.getModData
local getWorldHours = Runtime.getWorldHours
local getPlayerLabel = Runtime.getPlayerLabel
local getPlayerNutrition = Runtime.getPlayerNutrition
local getPlayerBodyDamage = Runtime.getPlayerBodyDamage
local syncVisibleHunger = Runtime.syncVisibleHunger
local syncVisibleWeight = Runtime.syncVisibleWeight
local syncProteinHealing = Runtime.syncProteinHealing
local suppressFoodEatenTimer = Runtime.suppressFoodEatenTimer
local log = Runtime.log
local getPlayerStats = Runtime.getPlayerStats
local getVisibleHungerValue = Runtime.getVisibleHungerValue
local clamp = Runtime.clamp
local setVisibleHunger = Runtime.setVisibleHunger

function Runtime.getStateKey()
    return STATE_KEY
end

function Runtime.getStateCopy(playerObj)
    local modData = getModData(playerObj)
    local rawState = modData and modData[STATE_KEY] or nil
    if type(rawState) ~= "table" then
        return nil
    end
    return Metabolism.copyState(rawState)
end

function Runtime.buildStateSnapshot(playerObj, reason)
    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return nil
    end

    return {
        version = tostring(MP.SCRIPT_VERSION or "1.0.0"),
        reason = tostring(reason or "snapshot"),
        worldHours = getWorldHours(),
        player = tostring(getPlayerLabel(playerObj)),
        state = Metabolism.copyState(state),
    }
end

function Runtime.syncVisibleIndicators(playerObj, reason)
    if not playerObj then
        return nil
    end

    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return nil
    end

    local nutrition = getPlayerNutrition(playerObj)
    local bodyDamage = getPlayerBodyDamage(playerObj)
    syncVisibleHunger(playerObj, state, reason or "sync-visible-indicators")
    syncVisibleWeight(nutrition, state)
    syncProteinHealing(bodyDamage, state)
    suppressFoodEatenTimer(bodyDamage)
    state.lastTraceReason = tostring(reason or state.lastTraceReason or "sync-visible-indicators")
    return state
end

function Runtime.syncVisibleShell(playerObj, reason)
    if not playerObj then
        return nil
    end

    local state = Runtime.syncVisibleIndicators(playerObj, reason or "sync-visible-shell")
    if not state then
        return nil
    end

    state.lastTraceReason = tostring(reason or state.lastTraceReason or "sync-visible-shell")
    return state
end

function Runtime.applyVisibleHungerTarget(playerObj, targetHunger, reason)
    if not playerObj then
        return false
    end

    local numeric = tonumber(targetHunger)
    if numeric == nil then
        return false
    end

    local state = Runtime.ensureStateForPlayer(playerObj)
    local stats = getPlayerStats(playerObj)
    if not stats or not state then
        return false
    end

    local desired = clamp(numeric, Metabolism.VISIBLE_HUNGER_MIN, Metabolism.VISIBLE_HUNGER_MAX)
    state.visibleHunger = desired
    state.lastSyncedHunger = desired
    return setVisibleHunger(stats, desired)
end

function Runtime.applyImmediateFullnessCorrection(playerObj, correction, reason)
    local stats = getPlayerStats(playerObj)
    local before = getVisibleHungerValue(stats)
    if before == nil then
        return false
    end
    return Runtime.applyVisibleHungerTarget(playerObj, before + (tonumber(correction) or 0), reason)
end

function Runtime.importStateSnapshot(playerObj, snapshot, reason)
    if not playerObj or type(snapshot) ~= "table" then
        return nil
    end

    local modData = getModData(playerObj)
    if not modData then
        return nil
    end

    local rawState = type(snapshot.state) == "table" and snapshot.state or snapshot
    local state = Metabolism.ensureState(Metabolism.copyState(rawState))
    state.initialized = true
    state.lastTraceReason = tostring(reason or snapshot.reason or "mp-sync")
    if snapshot.worldHours ~= nil then
        state.lastWorldHours = tonumber(snapshot.worldHours) or state.lastWorldHours
    end

    modData[STATE_KEY] = state

    Runtime.syncVisibleShell(playerObj, reason or snapshot.reason or "mp-sync")
    return state
end

return Runtime
