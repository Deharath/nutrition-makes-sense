NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.LiveScenarioAnalysis = NutritionMakesSense.LiveScenarioAnalysis or {}

local Analysis = NutritionMakesSense.LiveScenarioAnalysis
local Metabolism = NutritionMakesSense.Metabolism or {}

local PROFILE_EVALUATORS = {}
local PROFILE_SUMMARY_BUILDERS = {}

local function metricLine(label, value)
    return { label = label, value = value }
end

local function buildDefaultAnalysisSummary(run, helpers)
    local analysis = helpers.ensureAnalysis(run)
    return {
        metricLine("First Peckish", string.format("%s  fuel %s", helpers.formatMetricHour(analysis.firstPeckish and analysis.firstPeckish.hour), helpers.formatMetricNumber(analysis.firstPeckish and analysis.firstPeckish.fuel, "%.0f"))),
        metricLine("First Hungry", string.format("%s  fuel %s", helpers.formatMetricHour(analysis.firstHungry and analysis.firstHungry.hour), helpers.formatMetricNumber(analysis.firstHungry and analysis.firstHungry.fuel, "%.0f"))),
        metricLine("First Low", helpers.formatMetricHour(analysis.firstLowZone and analysis.firstLowZone.hour)),
        metricLine("First Penalty", helpers.formatMetricHour(analysis.firstPenaltyZone and analysis.firstPenaltyZone.hour)),
        metricLine("Depriv Start", helpers.formatMetricHour(analysis.firstDeprivationAny and analysis.firstDeprivationAny.hour)),
        metricLine("Peak Depriv", string.format("%s at %s", helpers.formatMetricNumber(analysis.peakDeprivation and analysis.peakDeprivation.value, "%.3f"), helpers.formatMetricHour(analysis.peakDeprivation and analysis.peakDeprivation.hour))),
        metricLine("Depriv Zero", helpers.formatMetricHour(analysis.deprivationZeroAfterRecovery and analysis.deprivationZeroAfterRecovery.hour)),
        metricLine("Low Time", string.format("%.2fh", tonumber(analysis.timeInLowHours) or 0)),
        metricLine("Penalty Time", string.format("%.2fh", tonumber(analysis.timeInPenaltyHours) or 0)),
    }
end

PROFILE_SUMMARY_BUILDERS.junk_food_day = function(run, helpers)
    local analysis = helpers.ensureAnalysis(run)
    local consumes = analysis.consumes or {}
    local finalState = analysis.finalSnapshot and analysis.finalSnapshot.state or {}
    local firstConsume = consumes[1] or {}
    local consumeCount = #consumes
    local totalPreHunger = 0
    local maxPreHunger = nil
    local dropCount = 0
    for _, entry in ipairs(consumes) do
        if tonumber(entry.hungerBefore) ~= nil then
            totalPreHunger = totalPreHunger + tonumber(entry.hungerBefore)
            dropCount = dropCount + 1
            maxPreHunger = maxPreHunger and math.max(maxPreHunger, tonumber(entry.hungerBefore)) or tonumber(entry.hungerBefore)
        end
    end
    local avgPreHunger = dropCount > 0 and (totalPreHunger / dropCount) or nil
    return {
        metricLine("First Junk", string.format("%s  %s",
            helpers.formatMetricHour(firstConsume.hour),
            tostring(firstConsume.label or "--"))),
        metricLine("Items Eaten", tostring(consumeCount)),
        metricLine("Avg Pre-Hunger", helpers.formatMetricNumber(avgPreHunger, "%.3f")),
        metricLine("Max Pre-Hunger", helpers.formatMetricNumber(maxPreHunger, "%.3f")),
        metricLine("First Low", helpers.formatMetricHour(analysis.firstLowZone and analysis.firstLowZone.hour)),
        metricLine("First Penalty", helpers.formatMetricHour(analysis.firstPenaltyZone and analysis.firstPenaltyZone.hour)),
        metricLine("Peak Depriv", string.format("%s at %s", helpers.formatMetricNumber(analysis.peakDeprivation and analysis.peakDeprivation.value, "%.3f"), helpers.formatMetricHour(analysis.peakDeprivation and analysis.peakDeprivation.hour))),
        metricLine("Low Time", string.format("%.2fh", tonumber(analysis.timeInLowHours) or 0)),
        metricLine("Penalty Time", string.format("%.2fh", tonumber(analysis.timeInPenaltyHours) or 0)),
        metricLine("End Fuel", helpers.formatMetricNumber(finalState.fuel, "%.0f")),
        metricLine("End Depriv", helpers.formatMetricNumber(finalState.deprivation, "%.3f")),
    }
end

PROFILE_SUMMARY_BUILDERS.light_meals_day = function(run, helpers)
    local analysis = helpers.ensureAnalysis(run)
    local finalState = analysis.finalSnapshot and analysis.finalSnapshot.state or {}
    return {
        metricLine("First Peckish", string.format("%s  fuel %s",
            helpers.formatMetricHour(analysis.firstPeckish and analysis.firstPeckish.hour),
            helpers.formatMetricNumber(analysis.firstPeckish and analysis.firstPeckish.fuel, "%.0f"))),
        metricLine("First Low", helpers.formatMetricHour(analysis.firstLowZone and analysis.firstLowZone.hour)),
        metricLine("First Penalty", helpers.formatMetricHour(analysis.firstPenaltyZone and analysis.firstPenaltyZone.hour)),
        metricLine("Depriv Start", helpers.formatMetricHour(analysis.firstDeprivationAny and analysis.firstDeprivationAny.hour)),
        metricLine("Peak Depriv", string.format("%s at %s",
            helpers.formatMetricNumber(analysis.peakDeprivation and analysis.peakDeprivation.value, "%.3f"),
            helpers.formatMetricHour(analysis.peakDeprivation and analysis.peakDeprivation.hour))),
        metricLine("Low Time", string.format("%.2fh", tonumber(analysis.timeInLowHours) or 0)),
        metricLine("Penalty Time", string.format("%.2fh", tonumber(analysis.timeInPenaltyHours) or 0)),
        metricLine("End Fuel", helpers.formatMetricNumber(finalState.fuel, "%.0f")),
        metricLine("End Depriv", helpers.formatMetricNumber(finalState.deprivation, "%.3f")),
    }
end

PROFILE_EVALUATORS.canonical_day = function(run, helpers)
    local analysis = helpers.ensureAnalysis(run)
    local validation = run.profile and run.profile.validation or {}
    local consumes = analysis.consumes or {}
    local peakDeprivationValue = tonumber(analysis.peakDeprivation and analysis.peakDeprivation.value) or 0
    local lowHours = tonumber(analysis.timeInLowHours) or 0
    local penaltyHours = tonumber(analysis.timeInPenaltyHours) or 0
    local endState = analysis.finalSnapshot and analysis.finalSnapshot.state or {}
    local endFuel = tonumber(endState.fuel) or 0
    local endDeprivation = tonumber(endState.deprivation) or 0
    local endZone = tostring(endState.lastZone or "")
    local firstPenalty = analysis.firstPenaltyZone
    local hungerDropThreshold = tonumber(validation.hungerDropThreshold) or 0.01
    local lowHoursWarn = tonumber(validation.lowHoursWarn) or 1.5
    local endFuelWarn = tonumber(validation.endFuelWarn) or 350
    local endFuelFail = tonumber(validation.endFuelFail) or 200
    local deprivationWarn = tonumber(validation.deprivationWarn) or 0.01
    local mealIssues = 0

    for index, consume in ipairs(consumes) do
        local drop = tonumber(consume and consume.hungerDrop) or nil
        if drop == nil then
            mealIssues = mealIssues + 1
            helpers.addEvaluation(run, helpers.SEVERITY_WARN, "canonical_meal_hunger_drop_missing_" .. tostring(index),
                string.format("%s hunger delta was not captured", tostring(consume and consume.label or ("meal " .. tostring(index)))))
        elseif drop < hungerDropThreshold then
            mealIssues = mealIssues + 1
            helpers.addEvaluation(run, helpers.SEVERITY_WARN, "canonical_meal_hunger_drop_weak_" .. tostring(index),
                string.format("%s only lowered hunger by %.3f", tostring(consume and consume.label or ("meal " .. tostring(index))), drop))
        end
    end

    if #consumes < 3 then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "canonical_day_too_few_meals",
            string.format("canonical day only completed %d meals", #consumes))
        return
    end

    if firstPenalty or penaltyHours > 0 or endFuel < endFuelFail or endZone == "Penalty" then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "canonical_day_became_too_rough",
            string.format("canonical day still hit penalty behavior (firstPenalty=%s, penaltyTime=%.2fh, endFuel=%.0f, endZone=%s)",
                helpers.formatMetricHour(firstPenalty and firstPenalty.hour), penaltyHours, endFuel, endZone ~= "" and endZone or "--"))
    elseif endDeprivation >= (Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10) or peakDeprivationValue >= (Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10) then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "canonical_day_crossed_deprivation_onset",
            string.format("canonical day crossed deprivation penalty onset (peak=%.3f end=%.3f)", peakDeprivationValue, endDeprivation))
    elseif lowHours > lowHoursWarn or peakDeprivationValue > deprivationWarn or endFuel < endFuelWarn or endZone == "Low" then
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "canonical_day_finished_rough",
            string.format("canonical day stayed afloat, but leaned rough (lowTime=%.2fh peakDepriv=%.3f endFuel=%.0f endZone=%s)",
                lowHours, peakDeprivationValue, endFuel, endZone ~= "" and endZone or "--"))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "canonical_day_stable",
            string.format("canonical day stayed broadly stable (lowTime=%.2fh peakDepriv=%.3f endFuel=%.0f)",
                lowHours, peakDeprivationValue, endFuel))
    end

    if mealIssues == 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "canonical_meals_help",
            "structured proper meals consistently lowered hunger through the day")
    end
end

PROFILE_EVALUATORS.snack_gap_stress = function(run, helpers)
    local analysis = helpers.ensureAnalysis(run)
    local validation = run.profile and run.profile.validation or {}
    local firstPeckish = analysis.firstPeckish
    local firstDeprivationAny = analysis.firstDeprivationAny
    local firstFuelBelow500 = analysis.firstFuelBelow500
    local firstFuelBelow300 = analysis.firstFuelBelow300
    local firstPeckishFuel = tonumber(firstPeckish and firstPeckish.fuel) or nil
    local peckishThreshold = tonumber(validation.peckishFuelThreshold) or 300
    local requiredFuelBelow = tonumber(validation.requireFuelBelow) or peckishThreshold
    local hungerDropThreshold = tonumber(validation.hungerDropThreshold) or 0.01
    local peakDeprivationValue = tonumber(analysis.peakDeprivation and analysis.peakDeprivation.value) or 0
    local recoveryMealBefore = tonumber(analysis.recoveryMealHungerBefore) or nil
    local recoveryMealAfter = tonumber(analysis.recoveryMealHungerAfter) or nil
    local recoveryMealDrop = (recoveryMealBefore and recoveryMealAfter) and (recoveryMealBefore - recoveryMealAfter) or nil

    if firstFuelBelow300 then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "stress_block_reached_deprivation_zone",
            string.format("stress block pushed fuel below %.0f at %s", requiredFuelBelow, helpers.formatMetricHour(firstFuelBelow300.hour)))
    elseif firstFuelBelow500 then
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "stress_block_reached_deprivation_zone",
            string.format("stress block only reached Low zone; fuel stayed above %.0f", requiredFuelBelow))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "stress_block_reached_deprivation_zone",
            string.format("stress block never pushed fuel below 500 or into %s zone", tostring(validation.expectedFuelZone or "Low")))
    end

    if firstDeprivationAny then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "stress_block_accumulated_deprivation",
            string.format("deprivation began at %s", helpers.formatMetricHour(firstDeprivationAny.hour)))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "stress_block_accumulated_deprivation", "stress block never accumulated measurable deprivation")
    end

    if firstPeckish and (not firstDeprivationAny or firstPeckish.hour < firstDeprivationAny.hour) then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "peckish_before_deprivation", "peckish appeared before deprivation began")
    elseif firstPeckish then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "peckish_before_deprivation",
            string.format("deprivation began at %s before peckish at %s",
                helpers.formatMetricHour(firstDeprivationAny and firstDeprivationAny.hour),
                helpers.formatMetricHour(firstPeckish.hour)))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "peckish_before_deprivation", "peckish never appeared during stress scenario")
    end

    if firstPeckishFuel == nil then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "peckish_above_threshold_fuel", "fuel at first peckish was never observed")
    elseif firstPeckishFuel > peckishThreshold then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "peckish_above_threshold_fuel",
            string.format("peckish appeared with fuel %.0f above threshold %.0f", firstPeckishFuel, peckishThreshold))
    elseif firstPeckishFuel > 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "peckish_above_threshold_fuel",
            string.format("peckish appeared late with fuel %.0f below threshold %.0f", firstPeckishFuel, peckishThreshold))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "peckish_above_threshold_fuel", "peckish did not appear before fuel hit zero")
    end

    if recoveryMealDrop ~= nil and recoveryMealDrop >= hungerDropThreshold then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "big_meal_resuppresses_hunger",
            string.format("recovery meal lowered hunger by %.3f", recoveryMealDrop))
    elseif recoveryMealDrop ~= nil then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "big_meal_resuppresses_hunger",
            string.format("recovery meal did not materially lower hunger (drop=%.3f)", recoveryMealDrop))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "big_meal_resuppresses_hunger", "recovery meal hunger deltas were not captured")
    end

    if peakDeprivationValue <= (tonumber(validation.deprivationAnyThreshold) or 0.0001) then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "deprivation_clears_after_refeed", "deprivation never accumulated meaningfully")
    elseif analysis.deprivationZeroAfterRecovery then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "deprivation_clears_after_refeed",
            string.format("deprivation returned to zero by %s", helpers.formatMetricHour(analysis.deprivationZeroAfterRecovery.hour)))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "deprivation_clears_after_refeed", "deprivation did not return to zero by scenario end")
    end

    if peakDeprivationValue < (Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10) then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "deprivation_snap_below_onset", "deprivation never crossed penalty onset")
    elseif analysis.deprivationZeroAfterRecovery and analysis.lastSubOnsetPositiveAfterRecovery then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "deprivation_snap_below_onset",
            string.format("deprivation dropped below onset and snapped to zero by %s", helpers.formatMetricHour(analysis.deprivationZeroAfterRecovery.hour)))
    elseif analysis.deprivationZeroAfterRecovery then
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "deprivation_snap_below_onset",
            "deprivation returned to zero after recovery but sub-onset descent was not observed in samples")
    else
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "deprivation_snap_below_onset", "deprivation never snapped back to zero after crossing onset")
    end
end

PROFILE_EVALUATORS.junk_food_day = function(run, helpers)
    local analysis = helpers.ensureAnalysis(run)
    local validation = run.profile and run.profile.validation or {}
    local consumes = analysis.consumes or {}
    local peakDeprivationValue = tonumber(analysis.peakDeprivation and analysis.peakDeprivation.value) or 0
    local lowHours = tonumber(analysis.timeInLowHours) or 0
    local penaltyHours = tonumber(analysis.timeInPenaltyHours) or 0
    local endState = analysis.finalSnapshot and analysis.finalSnapshot.state or {}
    local endFuel = tonumber(endState.fuel) or 0
    local endDeprivation = tonumber(endState.deprivation) or 0
    local firstPenalty = analysis.firstPenaltyZone
    local hungerDropThreshold = tonumber(validation.hungerDropThreshold) or 0.01
    local lowHoursWarn = tonumber(validation.lowHoursWarn) or 2.0
    local deprivationWarn = tonumber(validation.deprivationWarn) or 0.03
    local mealIssues = 0

    for index, consume in ipairs(consumes) do
        local drop = tonumber(consume and consume.hungerDrop) or nil
        if drop == nil then
            mealIssues = mealIssues + 1
            helpers.addEvaluation(run, helpers.SEVERITY_WARN, "consume_hunger_drop_missing_" .. tostring(index),
                string.format("%s hunger delta was not captured", tostring(consume and consume.label or ("item " .. tostring(index)))))
        elseif drop < hungerDropThreshold then
            mealIssues = mealIssues + 1
            helpers.addEvaluation(run, helpers.SEVERITY_WARN, "consume_hunger_drop_weak_" .. tostring(index),
                string.format("%s only lowered hunger by %.3f", tostring(consume and consume.label or ("item " .. tostring(index))), drop))
        end
    end

    if #consumes == 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "junk_day_never_ate",
            "junk-grazing scenario never consumed any item on hunger signal")
        return
    end

    if firstPenalty or penaltyHours > 0 or endFuel <= 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "junk_day_reserves_collapsed",
            string.format("junk-calorie day still hit penalty behavior (firstPenalty=%s, penaltyTime=%.2fh, endFuel=%.0f)",
                helpers.formatMetricHour(firstPenalty and firstPenalty.hour), penaltyHours, endFuel))
    elseif endDeprivation >= (Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10) or peakDeprivationValue >= (Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10) then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "junk_day_deprivation_crossed_onset",
            string.format("junk-calorie day crossed deprivation penalty onset (peak=%.3f end=%.3f)", peakDeprivationValue, endDeprivation))
    elseif lowHours > lowHoursWarn or peakDeprivationValue > deprivationWarn then
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "junk_day_quality_signal_rough",
            string.format("reserves stayed up, but the day leaned rough (lowTime=%.2fh peakDepriv=%.3f)", lowHours, peakDeprivationValue))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "junk_day_reserves_serviceable",
            string.format("junk-calorie day kept reserves serviceable (lowTime=%.2fh peakDepriv=%.3f endFuel=%.0f)", lowHours, peakDeprivationValue, endFuel))
    end

    if mealIssues == 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "junk_day_meals_still_help",
            "junk grazing consistently lowered hunger, but still produced a rougher day than proper meals")
    end
end

PROFILE_EVALUATORS.light_meals_day = function(run, helpers)
    local analysis = helpers.ensureAnalysis(run)
    local validation = run.profile and run.profile.validation or {}
    local consumes = analysis.consumes or {}
    local peakDeprivationValue = tonumber(analysis.peakDeprivation and analysis.peakDeprivation.value) or 0
    local lowHours = tonumber(analysis.timeInLowHours) or 0
    local penaltyHours = tonumber(analysis.timeInPenaltyHours) or 0
    local endState = analysis.finalSnapshot and analysis.finalSnapshot.state or {}
    local endFuel = tonumber(endState.fuel) or 0
    local endDeprivation = tonumber(endState.deprivation) or 0
    local endZone = tostring(endState.lastZone or "")
    local firstLow = analysis.firstLowZone
    local firstPenalty = analysis.firstPenaltyZone
    local firstDeprivation = analysis.firstDeprivationAny
    local hungerDropThreshold = tonumber(validation.hungerDropThreshold) or 0.01
    local lowHoursExpect = tonumber(validation.lowHoursExpect) or 1.5
    local penaltyHoursWarn = tonumber(validation.penaltyHoursWarn) or 1.5
    local deprivationWarn = tonumber(validation.deprivationWarn) or 0.03
    local minMeals = tonumber(validation.minMeals) or 5
    local minLastMealHour = tonumber(validation.minLastMealHour) or ((tonumber(run.profile and run.profile.durationHours) or 16) - 3.5)
    local lastConsume = consumes[#consumes]
    local mealIssues = 0

    for index, consume in ipairs(consumes) do
        local drop = tonumber(consume and consume.hungerDrop) or nil
        if drop == nil then
            mealIssues = mealIssues + 1
            helpers.addEvaluation(run, helpers.SEVERITY_WARN, "light_meal_hunger_drop_missing_" .. tostring(index),
                string.format("%s hunger delta was not captured", tostring(consume and consume.label or ("meal " .. tostring(index)))))
        elseif drop < hungerDropThreshold then
            mealIssues = mealIssues + 1
            helpers.addEvaluation(run, helpers.SEVERITY_WARN, "light_meal_hunger_drop_weak_" .. tostring(index),
                string.format("%s only lowered hunger by %.3f", tostring(consume and consume.label or ("meal " .. tostring(index))), drop))
        end
    end

    if #consumes < minMeals then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "light_day_too_few_meals",
            string.format("light meals day only completed %d meals", #consumes))
        return
    end

    if tonumber(lastConsume and lastConsume.hour) == nil or tonumber(lastConsume and lastConsume.hour) < minLastMealHour then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "light_day_food_plan_exhausted_early",
            string.format("light meals stopped too early for a full-day scenario (last meal at %s)",
                helpers.formatMetricHour(lastConsume and lastConsume.hour)))
        return
    end

    if endDeprivation >= (Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10)
        or peakDeprivationValue >= (Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10)
        or endFuel <= 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "light_day_became_too_harsh",
            string.format("light meals pushed too far into deprivation/collapse (peakDepriv=%.3f endDepriv=%.3f endFuel=%.0f)",
                peakDeprivationValue, endDeprivation, endFuel))
    elseif firstPenalty or penaltyHours > penaltyHoursWarn or peakDeprivationValue > deprivationWarn then
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "light_day_became_rough",
            string.format("light meals produced meaningful strain (firstPenalty=%s penaltyTime=%.2fh peakDepriv=%.3f endFuel=%.0f endZone=%s)",
                helpers.formatMetricHour(firstPenalty and firstPenalty.hour), penaltyHours, peakDeprivationValue, endFuel, endZone ~= "" and endZone or "--"))
    elseif firstLow or firstDeprivation or lowHours >= lowHoursExpect then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "light_day_sent_early_warning",
            string.format("light meals triggered early warning without deep collapse (firstLow=%s lowTime=%.2fh peakDepriv=%.3f)",
                helpers.formatMetricHour(firstLow and firstLow.hour), lowHours, peakDeprivationValue))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "light_day_too_comfortable",
            string.format("light meals never meaningfully challenged reserves (lowTime=%.2fh peakDepriv=%.3f endFuel=%.0f)",
                lowHours, peakDeprivationValue, endFuel))
    end

    if mealIssues == 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "light_meals_still_help",
            "light meals consistently lowered hunger, but pushed earlier warning than proper meals")
    end
end

function Analysis.buildSummary(run, helpers)
    local validation = run.profile and run.profile.validation or nil
    local summaryBuilder = validation and PROFILE_SUMMARY_BUILDERS[validation.evaluator]
    return type(summaryBuilder) == "function" and summaryBuilder(run, helpers) or buildDefaultAnalysisSummary(run, helpers)
end

function Analysis.evaluate(run, helpers)
    local validation = run.profile and run.profile.validation or nil
    local evaluator = validation and PROFILE_EVALUATORS[validation.evaluator]
    if type(evaluator) == "function" then
        evaluator(run, helpers)
    end
end

return Analysis
