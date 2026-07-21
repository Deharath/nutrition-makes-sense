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
require "NutritionMakesSense_Metabolism"
local Analysis = require "NutritionMakesSense_LiveScenarioAnalysis"

local function evaluate(run)
    local evaluations = {}
    Analysis.evaluate(run, {
        ensureAnalysis = function(target)
            return target.analysis
        end,
        addEvaluation = function(_, severity, code, message)
            evaluations[#evaluations + 1] = {
                severity = severity,
                code = code,
                message = message,
            }
        end,
        formatMetricHour = function()
            return "--"
        end,
        formatMetricNumber = function(value)
            return tostring(value or "--")
        end,
        SEVERITY_PASS = "pass",
        SEVERITY_WARN = "warn",
        SEVERITY_FAIL = "fail",
    })
    return evaluations
end

local function hasEvaluation(evaluations, severity, code)
    for _, entry in ipairs(evaluations) do
        if entry.severity == severity and entry.code == code then
            return true
        end
    end
    return false
end

local stalled = evaluate({
    profile = { validation = { evaluator = "junk_food_day", minimumItems = 3 } },
    analysis = {
        consumes = { { hungerDrop = 0.07 } },
        finalSnapshot = { state = { fuel = 0, deprivation = 0.55, lastZone = "Depleted" } },
        peakDeprivation = { value = 0.55 },
        timeInLowHours = 10,
    },
})
Support.assertTrue(hasEvaluation(stalled, "fail", "junk_food_day_too_few_items"),
    "one-item junk run cannot pass sequence coverage")
Support.assertTrue(hasEvaluation(stalled, "fail", "junk_food_day_became_too_rough"),
    "depleted junk run cannot pass metabolic outcome")

local stable = evaluate({
    profile = { validation = { evaluator = "junk_food_day", minimumItems = 3 } },
    analysis = {
        consumes = {
            { hungerDrop = 0.07 },
            { hungerDrop = 0.12 },
            { hungerDrop = 0.08 },
        },
        finalSnapshot = { state = { fuel = 450, deprivation = 0.01, lastZone = "Low" } },
        peakDeprivation = { value = 0.02 },
        timeInLowHours = 1,
    },
})
Support.assertTrue(hasEvaluation(stable, "pass", "junk_food_day_stayed_fed"),
    "adequate junk grazing should receive a positive metabolic verdict")
Support.assertTrue(hasEvaluation(stable, "pass", "junk_food_items_relieve_hunger"),
    "observable short-term relief should be reported")

local canonicalStable = evaluate({
    profile = { validation = { evaluator = "canonical_day" } },
    analysis = {
        consumes = {
            { hungerDrop = 0.20 },
            { hungerDrop = 0.18 },
            { hungerDrop = 0.16 },
            { hungerDrop = 0.19 },
        },
        finalSnapshot = { state = { fuel = 754, deprivation = 0, lastZone = "Ready" } },
        peakDeprivation = { value = 0 },
        timeInLowHours = 4.57,
        timeInDepletedHours = 0,
    },
})
Support.assertTrue(hasEvaluation(canonicalStable, "pass", "canonical_day_stable"),
    "low-zone exposure alone does not make a healthy canonical day rough")

local lightStable = evaluate({
    profile = {
        validation = {
            evaluator = "light_meals_day",
            minMeals = 5,
            minLastMealHour = 12.5,
            lowHoursExpect = 1.5,
        },
    },
    analysis = {
        consumes = {
            { hour = 1.7, hungerDrop = 0.12 },
            { hour = 4.7, hungerDrop = 0.12 },
            { hour = 6.4, hungerDrop = 0.12 },
            { hour = 8.0, hungerDrop = 0.12 },
            { hour = 9.6, hungerDrop = 0.12 },
            { hour = 11.4, hungerDrop = 0.12 },
            { hour = 13.4, hungerDrop = 0.12 },
        },
        finalSnapshot = { state = { fuel = 399, deprivation = 0, lastZone = "Low" } },
        peakDeprivation = { value = 0.008 },
        timeInLowHours = 8.0,
        timeInDepletedHours = 2.67,
    },
})
Support.assertTrue(hasEvaluation(lightStable, "pass", "light_meals_day_covered"),
    "a complete light-meals sequence earns scenario coverage")
Support.assertTrue(hasEvaluation(lightStable, "pass", "light_meals_day_stayed_viable"),
    "time below the reserve boundary is not mistaken for an active gameplay penalty")
Support.assertTrue(hasEvaluation(lightStable, "pass", "light_meals_day_exposed_low_reserve"),
    "the light-meals scenario confirms that it exercised low reserve")

local lightIncomplete = evaluate({
    profile = { validation = { evaluator = "light_meals_day", minMeals = 5 } },
    analysis = {
        consumes = { { hour = 1, hungerDrop = 0.12 } },
        finalSnapshot = { state = { fuel = 400, deprivation = 0, lastZone = "Low" } },
        peakDeprivation = { value = 0 },
        timeInLowHours = 2,
        timeInDepletedHours = 0,
    },
})
Support.assertTrue(hasEvaluation(lightIncomplete, "fail", "light_meals_day_too_few_meals"),
    "an incomplete light-meals run cannot pass by lacking an evaluator")

local snackRecovered = evaluate({
    profile = {
        validation = {
            evaluator = "snack_gap_stress",
            peckishFuelThreshold = 300,
            requireFuelBelow = 300,
            recoveryTolerance = 0.01,
        },
    },
    analysis = {
        firstFuelBelow300 = { hour = 3.3 },
        firstDeprivationAny = { hour = 3.41 },
        firstPeckish = { hour = 1.69, fuel = 568 },
        firstPeckishAfterFirstMeal = { hour = 3.49, fuel = 242 },
        firstDeprivationPenalty = { hour = 4.0 },
        recoveryMealHungerBefore = 0.55,
        recoveryMealHungerAfter = 0.153,
        finalSnapshot = { state = { deprivation = 0.102 } },
        peakDeprivation = { value = 0.137 },
    },
})
Support.assertTrue(hasEvaluation(snackRecovered, "pass", "peckish_before_deprivation"),
    "peckish is compared with penalty onset rather than numerical deprivation dust")
Support.assertTrue(hasEvaluation(snackRecovered, "pass", "deprivation_clears_after_refeed"),
    "near-onset deprivation after clear recovery is treated as negligible")

local snackNotRecovered = evaluate({
    profile = { validation = { evaluator = "snack_gap_stress" } },
    analysis = {
        firstFuelBelow300 = { hour = 3.3 },
        firstPeckishAfterFirstMeal = { hour = 3.4, fuel = 320 },
        firstDeprivationPenalty = { hour = 4.0 },
        recoveryMealHungerBefore = 0.55,
        recoveryMealHungerAfter = 0.15,
        finalSnapshot = { state = { deprivation = 0.20 } },
        peakDeprivation = { value = 0.20 },
    },
})
Support.assertTrue(hasEvaluation(snackNotRecovered, "fail", "deprivation_clears_after_refeed"),
    "a recovery meal that leaves deprivation unchanged still fails cleanup")

local snackMissingSecondCue = evaluate({
    profile = { validation = { evaluator = "snack_gap_stress" } },
    analysis = {
        firstFuelBelow300 = { hour = 3.3 },
        firstPeckish = { hour = 1.7, fuel = 570 },
        firstDeprivationPenalty = { hour = 4.0 },
        recoveryMealHungerBefore = 0.55,
        recoveryMealHungerAfter = 0.15,
        finalSnapshot = { state = { deprivation = 0 } },
        peakDeprivation = { value = 0 },
    },
})
Support.assertTrue(hasEvaluation(snackMissingSecondCue, "fail", "peckish_before_deprivation"),
    "the pre-breakfast cue cannot stand in for a post-snack warning")

print("nms scenario analysis characterization passed")
