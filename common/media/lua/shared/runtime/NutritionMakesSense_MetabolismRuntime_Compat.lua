NutritionMakesSense = NutritionMakesSense or {}

local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local Metabolism = Runtime.Metabolism or {}

local PROTOCOL = "mscompat-v1"
local getActivityCache = Runtime.getActivityCache

local function getCompat()
    local compat = NutritionMakesSense.Compat or rawget(_G, "MakesSenseCompat")
    if type(compat) ~= "table" or tostring(compat.protocol) ~= PROTOCOL then
        return nil
    end
    return compat
end

function Runtime.getCompat()
    return getCompat()
end

function Runtime.isCompatEnduranceActive()
    local compat = getCompat()
    return type(compat) == "table"
        and type(compat.hasCapability) == "function"
        and compat:hasCapability("ArmorMakesSense", "endurance_coordinator")
end

function Runtime.isCompatFatigueActive()
    local compat = getCompat()
    return type(compat) == "table"
        and type(compat.hasCapability) == "function"
        and compat:hasCapability("CaffeineMakesSense", "fatigue_coordinator")
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
    local averageMet = tonumber(workload and workload.averageMet) or tonumber(state.lastMetAverage) or Metabolism.MET_REST

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

    local controlledEndurance = tonumber(args and args.controlledEndurance)
    local regenScale = tonumber(args and args.regenScale) or 1.0
    local extraDrain = math.max(0, tonumber(args and args.extraDrain) or 0)

    if controlledEndurance ~= nil then
        state.lastEnduranceObserved = controlledEndurance
    end
    state.lastEnduranceRegenScale = regenScale
    state.lastEnduranceDeprivDrain = extraDrain
    state.lastExtraEnduranceDrain = extraDrain

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

local function computeFatigueContribution(playerObj, args)
    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return {
            extraFatigue = 0,
            fatigueAccelFactor = 1.0,
        }
    end

    if args and args.sleeping == true then
        return {
            extraFatigue = 0,
            fatigueAccelFactor = 1.0,
        }
    end

    local dtMinutes = math.max(0, tonumber(args and args.dtMinutes) or 0)
    local dtHours = math.max(0, tonumber(args and args.dtHours) or (dtMinutes / 60.0))
    local fatigueAccelFactor = Metabolism.getFatigueAccelFactor(state.deprivation)

    if fatigueAccelFactor <= 1.0 or dtHours <= 0 then
        return {
            extraFatigue = 0,
            fatigueAccelFactor = fatigueAccelFactor,
        }
    end

    local vanillaFatiguePerHour = 0.042
    local extraFatigue = vanillaFatiguePerHour * (fatigueAccelFactor - 1.0) * dtHours

    return {
        extraFatigue = math.max(0, extraFatigue),
        fatigueAccelFactor = fatigueAccelFactor,
        deprivation = tonumber(state.deprivation) or 0,
    }
end

local function buildTraceSnapshot(playerObj, _args)
    local state = Runtime.ensureStateForPlayer(playerObj)
    if not state then
        return {}
    end

    local workload = Runtime.getCurrentWorkloadSnapshot and Runtime.getCurrentWorkloadSnapshot(playerObj) or nil
    return {
        compat_endurance_active = Runtime.isCompatEnduranceActive and Runtime.isCompatEnduranceActive() or false,
        compat_fatigue_active = Runtime.isCompatFatigueActive and Runtime.isCompatFatigueActive() or false,
        work_tier = tostring(state.lastWorkTier or workload and workload.workTier or ""),
        met_avg = tonumber(workload and workload.averageMet or state.lastMetAverage) or nil,
        met_peak = tonumber(workload and workload.peakMet or state.lastMetPeak) or nil,
        met_source = tostring(workload and workload.source or state.lastMetSource or ""),
        fuel = tonumber(state.fuel) or 0,
        zone = tostring(state.lastZone or ""),
        deprivation = tonumber(state.deprivation) or 0,
        deprivation_target = tonumber(state.lastDeprivationTarget) or nil,
        end_regen_scale = tonumber(state.lastEnduranceRegenScale) or 1.0,
        end_depriv_drain = tonumber(state.lastEnduranceDeprivDrain) or 0,
        extra_endurance = tonumber(state.lastExtraEnduranceDrain) or 0,
    }
end

local compat = getCompat()
if compat and type(compat.registerProvider) == "function" then
    compat:registerProvider("NutritionMakesSense", {
        capabilities = {
            endurance_provider = true,
            fatigue_provider = true,
        },
        callbacks = {
            computeEnduranceContribution = computeEnduranceContribution,
            recordEnduranceResult = recordEnduranceResult,
            computeFatigueContribution = computeFatigueContribution,
            buildTraceSnapshot = buildTraceSnapshot,
        },
    })
end

return Runtime
