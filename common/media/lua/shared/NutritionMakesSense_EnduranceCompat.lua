NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_Compat"
require "NutritionMakesSense_Model"
require "NutritionMakesSense_Workload"
require "NutritionMakesSense_Runtime"

-- mscompat-v1 endurance provider: when AMS coordinates endurance, it asks NMS for the malnutrition share.
local Runtime = NutritionMakesSense.Runtime
local Model = NutritionMakesSense.Model
local Workload = NutritionMakesSense.Workload

local function computeEnduranceContribution(playerObj, args)
    local malnutrition = Runtime.getMalnutrition(playerObj)
    local dtMinutes = math.max(0, tonumber(args and args.dtMinutes) or 0)
    local dtHours = math.max(0, tonumber(args and args.dtHours) or (dtMinutes / 60))
    local naturalDelta = tonumber(args and args.naturalDelta) or 0
    local workload = type(args and args.workload) == "table" and args.workload or Workload.sampleForAuthority(playerObj)
    local met = tonumber(workload and (workload.averageMet or workload.met)) or Model.MET_REST

    local regenScale = 1
    if naturalDelta > 0 then
        regenScale = Model.enduranceRegenScale(malnutrition)
    end
    local extraDrain = 0
    if naturalDelta <= 0 and dtHours > 0 then
        extraDrain = Model.enduranceActivityDrainPerHour(malnutrition, met) * dtHours
    end
    return {
        regenScale = regenScale,
        extraDrain = math.max(0, extraDrain),
        deprivation = malnutrition,
        averageMet = met,
        workloadSource = tostring(workload and workload.source or "compat"),
    }
end

local function recordEnduranceResult(_playerObj, args)
    return {
        controlledEndurance = tonumber(args and args.controlledEndurance),
        regenScale = tonumber(args and args.regenScale) or 1,
        extraDrain = math.max(0, tonumber(args and args.extraDrain) or 0),
    }
end

local function buildTraceSnapshot(playerObj, _args)
    local display = Runtime.getDisplay(playerObj) or {}
    return {
        compat_endurance_active = Runtime.isCompatEnduranceActive(),
        met = tonumber(display.met) or nil,
        calories = tonumber(display.calories) or nil,
        zone = tostring(display.reserveZone or ""),
        malnutrition = tonumber(display.malnutrition) or 0,
        malnutrition_target = tonumber(display.malnutritionTarget) or nil,
        end_regen_scale = Model.enduranceRegenScale(display.malnutrition or 0),
    }
end

NutritionMakesSense.registerCompatProvider({ endurance_provider = true }, {
    computeEnduranceContribution = computeEnduranceContribution,
    recordEnduranceResult = recordEnduranceResult,
    buildTraceSnapshot = buildTraceSnapshot,
})
