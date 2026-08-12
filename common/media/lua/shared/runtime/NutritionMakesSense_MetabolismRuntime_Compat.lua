NutritionMakesSense = NutritionMakesSense or {}

local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local Metabolism = Runtime.Metabolism or {}
local getTelemetryForState = Runtime.getTelemetryForState
local buildStateView = Runtime.buildStateView

local PROTOCOL = "mscompat-v1"
local getActivityCache = Runtime.getActivityCache

local function getCompat()
    local compat = NutritionMakesSense.Compat or rawget(_G, "MakesSenseCompat")
    if type(compat) ~= "table" or tostring(compat.protocol) ~= PROTOCOL then
        return nil
    end
    return compat
end

function Runtime.isCompatEnduranceActive()
    local compat = getCompat()
    return type(compat) == "table"
        and type(compat.hasCapability) == "function"
        and compat:hasCapability("ArmorMakesSense", "endurance_coordinator")
end

local function computeEnduranceContribution(playerObj, args)
    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return {
            regenScale = 1.0,
            extraDrain = 0,
        }
    end

    local dtMinutes = math.max(0, tonumber(args and args.dtMinutes) or 0)
    local dtHours = math.max(0, tonumber(args and args.dtHours) or (dtMinutes / 60.0))
    local naturalDelta = tonumber(args and args.naturalDelta) or 0
    local deprivation = tonumber(state.deprivation) or 0
    local workload = type(args and args.workload) == "table" and args.workload or Runtime.getCurrentWorkloadSnapshot(playerObj)
    local telemetry = getTelemetryForState(state)
    local averageMet = tonumber(workload and workload.averageMet) or tonumber(telemetry.lastMetAverage) or Metabolism.MET_REST

    local regenScale = 1.0
    if naturalDelta > 0 then
        regenScale = Metabolism.getDeprivationRegenScale(deprivation)
    end

    local extraDrain = 0
    if naturalDelta <= 0 and deprivation > Metabolism.DEPRIVATION_ENDURANCE_ONSET and dtHours > 0 then
        extraDrain = Metabolism.getDeprivationActivityDrain(deprivation, averageMet) * dtHours
    end

    return {
        regenScale = regenScale,
        extraDrain = math.max(0, extraDrain),
        deprivation = deprivation,
        averageMet = averageMet,
        workloadSource = tostring(workload and workload.source or "compat"),
    }
end

local function recordEnduranceResult(playerObj, args)
    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return nil
    end
    local telemetry = getTelemetryForState(state)

    local controlledEndurance = tonumber(args and args.controlledEndurance)
    local regenScale = tonumber(args and args.regenScale) or 1.0
    local extraDrain = math.max(0, tonumber(args and args.extraDrain) or 0)

    if controlledEndurance ~= nil then
        telemetry.lastEnduranceObserved = controlledEndurance
    end
    telemetry.lastEnduranceRegenScale = regenScale
    telemetry.lastEnduranceDeprivDrain = extraDrain
    telemetry.lastExtraEnduranceDrain = extraDrain

    local cache = getActivityCache and getActivityCache(playerObj) or nil
    if cache then
        cache.appliedEnduranceDrain = (tonumber(cache.appliedEnduranceDrain) or 0) + extraDrain
    end

    return {
        controlledEndurance = controlledEndurance,
        regenScale = regenScale,
        extraDrain = extraDrain,
    }
end

local function buildTraceSnapshot(playerObj, _args)
    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return {}
    end
    local view = buildStateView(state, getTelemetryForState(state))

    local workload = Runtime.getCurrentWorkloadSnapshot and Runtime.getCurrentWorkloadSnapshot(playerObj) or nil
    return {
        compat_endurance_active = Runtime.isCompatEnduranceActive and Runtime.isCompatEnduranceActive() or false,
        work_tier = tostring(view.lastWorkTier or workload and workload.workTier or ""),
        met_avg = tonumber(workload and workload.averageMet or view.lastMetAverage) or nil,
        met_peak = tonumber(workload and workload.peakMet or view.lastMetPeak) or nil,
        met_source = tostring(workload and workload.source or view.lastMetSource or ""),
        fuel = tonumber(view.fuel) or 0,
        zone = tostring(view.lastZone or ""),
        deprivation = tonumber(view.deprivation) or 0,
        deprivation_target = tonumber(view.lastDeprivationTarget) or nil,
        end_regen_scale = tonumber(view.lastEnduranceRegenScale) or 1.0,
        end_depriv_drain = tonumber(view.lastEnduranceDeprivDrain) or 0,
        extra_endurance = tonumber(view.lastExtraEnduranceDrain) or 0,
    }
end

local compat = getCompat()
if compat and type(compat.registerProvider) == "function" then
    compat:registerProvider("NutritionMakesSense", {
        capabilities = {
            endurance_provider = true,
        },
        callbacks = {
            computeEnduranceContribution = computeEnduranceContribution,
            recordEnduranceResult = recordEnduranceResult,
            buildTraceSnapshot = buildTraceSnapshot,
        },
    })
end

return Runtime
