local function scriptDir()
    local source = debug.getinfo(1, "S").source or ""
    source = source:gsub("^@", "")
    return source:match("^(.*)/[^/]+$")
end

local root = scriptDir():gsub("/tests$", "")
package.path = table.concat({
    root .. "/common/media/lua/shared/?.lua",
    root .. "/common/media/lua/client/dev/?.lua",
    package.path,
}, ";")

local Support = require "support"
local Metabolism = require "NutritionMakesSense_Metabolism"
local RunnerUtils = require "NutritionMakesSense_LiveScenarioRunnerUtils"

Support.assertClose(Metabolism.HUNGER_THRESHOLD_PECKISH, 0.15, 0.000001,
    "NMS peckish threshold matches the vanilla Hungry moodle threshold")
Support.assertNil(RunnerUtils.isHungerSignalReady,
    "live meals must not trigger from backend hunger values")
Support.assertNil(RunnerUtils.getExpectedHungerMoodleLevel,
    "runner must not maintain a shadow copy of mutable vanilla moodle rules")

local state = Metabolism.newState({ fuel = 500 })
Support.assertEqual(state.depositSequence, 0, "new states start with no observed deposits")

local first = Metabolism.applyFoodValues(state, { kcal = 100, proteins = 2 }, 1, "first")
Support.assertEqual(first.depositSequence, 1, "first deposit advances the sequence")
Support.assertEqual(state.depositSequence, 1, "state retains the first deposit sequence")

local second = Metabolism.applyFoodValues(state, { kcal = 50 }, 1, "second")
Support.assertEqual(second.depositSequence, 2, "each deposit advances the sequence exactly once")

local staleDeposit = RunnerUtils.measureMealConfirmation(
    { hunger = 0.20, state = { depositSequence = 7, lastDepositKcal = 250, fuel = 500, proteins = 20, satietyBuffer = 0.1 } },
    { hunger = 0.05, state = { depositSequence = 7, lastDepositKcal = 250, fuel = 500, proteins = 20, satietyBuffer = 0.1 } },
    { kcal = 100, proteins = 2 })
Support.assertEqual(staleDeposit.confirmed, false, "stale deposits and hunger changes cannot confirm a caloric item")
Support.assertEqual(staleDeposit.depositObserved, false, "unchanged sequence reports no deposit")

local newDeposit = RunnerUtils.measureMealConfirmation(
    { hunger = 0.20, state = { depositSequence = 7, lastDepositKcal = 250, fuel = 500 } },
    { hunger = 0.20, state = { depositSequence = 8, lastDepositKcal = 100, fuel = 600 } },
    { kcal = 100 })
Support.assertEqual(newDeposit.confirmed, true, "a new NMS deposit confirms a caloric item")
Support.assertEqual(newDeposit.depositObserved, true, "advanced sequence reports the deposit")

local nonNutritional = RunnerUtils.measureMealConfirmation(
    { hunger = 0.20, state = { depositSequence = 8 } },
    { hunger = 0.10, state = { depositSequence = 8 } },
    nil)
Support.assertEqual(nonNutritional.confirmed, true, "consumed non-nutritional items need no NMS deposit")
Support.assertEqual(nonNutritional.requiresDeposit, false, "nil nutrition does not require a deposit")

print("nms live scenario runner characterization passed")
