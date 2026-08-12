local function scriptDir()
    local source = debug.getinfo(1, "S").source or ""
    source = source:gsub("^@", "")
    return source:match("^(.*)/[^/]+$")
end

local root = scriptDir():gsub("/tests$", "")
package.path = table.concat({
    root .. "/common/media/lua/shared/?.lua",
    root .. "/common/media/lua/client/dev/scenarios/?.lua",
    package.path,
}, ";")

local Support = require "support"
NutritionMakesSense = NutritionMakesSense or {}
local Metabolism = require "NutritionMakesSense_Metabolism"
local Catalog = require "NutritionMakesSense_LiveScenarioCatalog"

local profile = Catalog.getProfile("recorded_exploration_day")
Support.assertEqual(profile.id, "recorded_exploration_day", "recorded autopilot profile is registered")
Support.assertEqual(profile.consumptionMode, "signal_sequence", "autopilot eats from visible hunger cues")
Support.assertEqual(profile.repeatSequenceOnSignal, true, "autopilot can keep eating when hunger returns")
Support.assertEqual(#profile.items, 6, "autopilot uses the six-food recorded-day cycle")
Support.assertEqual(#profile.phases, 6, "autopilot has awake workload, sleep, and a wake-response window")
Support.assertEqual(profile.phases[5].sleepObserved, true, "fifth workload phase uses the sleep path")
Support.assertEqual(profile.phases[5].allowEating, false, "autopilot does not wake itself to eat")
Support.assertEqual(profile.phases[6].postWakeResponse, true, "autopilot lets a hungry survivor respond after waking")
Support.assertEqual(profile.validation.minimumItems, 9, "recorded day expects the calibrated nine-item response")
Support.assertEqual(profile.validation.maximumAwakeHiddenDepletedStreakHours, 2.0,
    "sleep time is excluded from the hidden-depletion failure gate")
Support.assertEqual(profile.items[3].prepared.cooked, true, "recorded steak is spawned cooked")
Support.assertEqual(profile.items[5].prepared.cooked, true, "recorded sausage is spawned cooked")

local duration = 0
local recordedBurn = 0
local projectedBurn = 0
for phaseIndex, phase in ipairs(profile.phases) do
    local hours = (tonumber(phase.endHour) or 0) - (tonumber(phase.startHour) or 0)
    duration = duration + hours
    local phaseBurn = Metabolism.getFuelBurnPerHourFromMet({
        averageMet = phase.averageMet,
        peakMet = phase.averageMet,
        sleepObserved = phase.sleepObserved == true,
    }, 80) * hours
    projectedBurn = projectedBurn + phaseBurn
    if phaseIndex <= 5 then
        recordedBurn = recordedBurn + phaseBurn
    end
end
Support.assertClose(duration, profile.durationHours, 0.000001, "autopilot phase duration covers the whole trace")
Support.assertClose(recordedBurn, 3055.4, 10.0, "autopilot wake-plus-sleep workload reproduces recorded daily burn")
Support.assertEqual(projectedBurn > recordedBurn, true, "wake-response observation includes its own small energy cost")

print("nms live scenario catalog characterization passed")
