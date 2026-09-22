NutritionMakesSense = NutritionMakesSense or {}

local Runtime = NutritionMakesSense.MetabolismRuntime or {}

local Metabolism = Runtime.Metabolism or {}
local MP = Runtime.MP or {}
local MPSnapshot = Runtime.MPSnapshot or {}
local STATE_KEY = Runtime.STATE_KEY
local getModData = Runtime.getModData
local getWorldHours = Runtime.getWorldHours
local getPlayerLabel = Runtime.getPlayerLabel
local getPlayerNutrition = Runtime.getPlayerNutrition
local getPlayerBodyDamage = Runtime.getPlayerBodyDamage
local safeCall = Runtime.safeCall
local safeInvoke = NutritionMakesSense.CoreUtils and NutritionMakesSense.CoreUtils.safeInvoke
local syncVisibleHunger = Runtime.syncVisibleHunger
local syncVisibleWeight = Runtime.syncVisibleWeight
local suppressFoodEatenTimer = Runtime.suppressFoodEatenTimer
local log = Runtime.log
local getPlayerStats = Runtime.getPlayerStats
local getVisibleHungerValue = Runtime.getVisibleHungerValue
local clamp = Runtime.clamp
local setVisibleHunger = Runtime.setVisibleHunger
local getTelemetryForState = Runtime.getTelemetryForState
local replaceTelemetryForState = Runtime.replaceTelemetryForState
local buildStateView = Runtime.buildStateView
local recoveryByBodyDamage = setmetatable({}, { __mode = "k" })
local RECOVERY_FIELDS = {
    { get = "getStandardHealthAddition", set = "setStandardHealthAddition" },
    { get = "getReducedHealthAddition", set = "setReducedHealthAddition" },
    { get = "getSeverlyReducedHealthAddition", set = "setSeverlyReducedHealthAddition" },
}

function Runtime.syncNaturalRecovery(bodyDamage, state)
    if not bodyDamage or not state then return nil end
    local multiplier = Metabolism.getNaturalRecoveryMultiplier(state.proteins, state.weightKg, state.fuel)
    local fields = recoveryByBodyDamage[bodyDamage]
    if not fields then
        fields = {}
        recoveryByBodyDamage[bodyDamage] = fields
    end

    for _, field in ipairs(RECOVERY_FIELDS) do
        local current = tonumber(safeCall(bodyDamage, field.get))
        if current and current >= 0 then
            local entry = fields[field.get]
            if not entry then
                entry = { baseline = current }
                fields[field.get] = entry
            elseif entry.applied and math.abs(current - entry.applied) > 0.000001 then
                -- Another mod changed this field; leave its value under that mod's control.
                entry.external = true
            end

            if not entry.external then
                local desired = entry.baseline * multiplier
                if math.abs(current - desired) <= 0.0000001 then
                    entry.applied = current
                elseif safeInvoke and safeInvoke(bodyDamage, field.set, desired) then
                    entry.applied = desired
                end
            end
        end
    end
    return multiplier
end

function Runtime.getStateCopy(playerObj)
    local modData = getModData(playerObj)
    local rawState = modData and modData[STATE_KEY] or nil
    if type(rawState) ~= "table" then
        return nil
    end
    return buildStateView(rawState, getTelemetryForState(rawState))
end

function Runtime.buildStateSnapshot(playerObj, reason, includeDiagnostics)
    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return nil
    end

    return {
        version = tostring(MP.SCRIPT_VERSION or "1.0.0"),
        reason = tostring(reason or "snapshot"),
        worldHours = getWorldHours(),
        player = tostring(getPlayerLabel(playerObj)),
        state = MPSnapshot.copyState(buildStateView(state, getTelemetryForState(state)), includeDiagnostics == true),
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
    local telemetry = getTelemetryForState(state)
    syncVisibleHunger(playerObj, state, reason or "sync-visible-indicators")
    syncVisibleWeight(nutrition, state, telemetry)
    Runtime.syncNaturalRecovery(bodyDamage, state)
    if Runtime.shouldRunAuthoritativeUpdates() then
        suppressFoodEatenTimer(bodyDamage)
    end
    telemetry.lastTraceReason = tostring(reason or telemetry.lastTraceReason or "sync-visible-indicators")
    return state
end

function Runtime.syncVisibleShell(playerObj, reason)
    return Runtime.syncVisibleIndicators(playerObj, reason or "sync-visible-shell")
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
    getTelemetryForState(state).lastSyncedHunger = desired
    return setVisibleHunger(stats, desired)
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
    local state = Metabolism.copyState(rawState)
    local telemetry = replaceTelemetryForState(state, rawState)
    state.initialized = true
    telemetry.lastTraceReason = tostring(reason or snapshot.reason or "mp-sync")
    if snapshot.worldHours ~= nil then
        state.lastWorldHours = tonumber(snapshot.worldHours) or state.lastWorldHours
    end

    modData[STATE_KEY] = state

    -- A server snapshot is authoritative. Apply its hunger value directly before the
    -- generic shell sync so a small client-prediction/float difference cannot be
    -- misclassified as a second local meal drop and veto the snapshot.
    Runtime.applyVisibleHungerTarget(
        playerObj,
        state.visibleHunger,
        reason or snapshot.reason or "mp-sync"
    )
    Runtime.syncVisibleShell(playerObj, reason or snapshot.reason or "mp-sync")
    return buildStateView(state, telemetry)
end

return Runtime
