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
        metricLine("First Peckish", string.format("%s  energy %s", helpers.formatMetricHour(analysis.firstPeckish and analysis.firstPeckish.hour), helpers.formatMetricNumber(analysis.firstPeckish and analysis.firstPeckish.fuel, "%.0f"))),
        metricLine("First Hungry", string.format("%s  energy %s", helpers.formatMetricHour(analysis.firstHungry and analysis.firstHungry.hour), helpers.formatMetricNumber(analysis.firstHungry and analysis.firstHungry.fuel, "%.0f"))),
        metricLine("First Low", helpers.formatMetricHour(analysis.firstLowZone and analysis.firstLowZone.hour)),
        metricLine("First Depleted", helpers.formatMetricHour(analysis.firstDepletedZone and analysis.firstDepletedZone.hour)),
        metricLine("Depriv Start", helpers.formatMetricHour(analysis.firstDeprivationAny and analysis.firstDeprivationAny.hour)),
        metricLine("Peak Depriv", string.format("%s at %s", helpers.formatMetricNumber(analysis.peakDeprivation and analysis.peakDeprivation.value, "%.3f"), helpers.formatMetricHour(analysis.peakDeprivation and analysis.peakDeprivation.hour))),
        metricLine("Depriv Zero", helpers.formatMetricHour(analysis.deprivationZeroAfterRecovery and analysis.deprivationZeroAfterRecovery.hour)),
        metricLine("Low Time", string.format("%.2fh", tonumber(analysis.timeInLowHours) or 0)),
        metricLine("Depleted Time", string.format("%.2fh", tonumber(analysis.timeInDepletedHours) or 0)),
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
        metricLine("First Depleted", helpers.formatMetricHour(analysis.firstDepletedZone and analysis.firstDepletedZone.hour)),
        metricLine("Peak Depriv", string.format("%s at %s", helpers.formatMetricNumber(analysis.peakDeprivation and analysis.peakDeprivation.value, "%.3f"), helpers.formatMetricHour(analysis.peakDeprivation and analysis.peakDeprivation.hour))),
        metricLine("Low Time", string.format("%.2fh", tonumber(analysis.timeInLowHours) or 0)),
        metricLine("Depleted Time", string.format("%.2fh", tonumber(analysis.timeInDepletedHours) or 0)),
        metricLine("End Energy", helpers.formatMetricNumber(finalState.fuel, "%.0f")),
        metricLine("End Depriv", helpers.formatMetricNumber(finalState.deprivation, "%.3f")),
    }
end

PROFILE_SUMMARY_BUILDERS.light_meals_day = function(run, helpers)
    local analysis = helpers.ensureAnalysis(run)
    local finalState = analysis.finalSnapshot and analysis.finalSnapshot.state or {}
    return {
        metricLine("First Peckish", string.format("%s  energy %s",
            helpers.formatMetricHour(analysis.firstPeckish and analysis.firstPeckish.hour),
            helpers.formatMetricNumber(analysis.firstPeckish and analysis.firstPeckish.fuel, "%.0f"))),
        metricLine("First Low", helpers.formatMetricHour(analysis.firstLowZone and analysis.firstLowZone.hour)),
        metricLine("First Depleted", helpers.formatMetricHour(analysis.firstDepletedZone and analysis.firstDepletedZone.hour)),
        metricLine("Depriv Start", helpers.formatMetricHour(analysis.firstDeprivationAny and analysis.firstDeprivationAny.hour)),
        metricLine("Peak Depriv", string.format("%s at %s",
            helpers.formatMetricNumber(analysis.peakDeprivation and analysis.peakDeprivation.value, "%.3f"),
            helpers.formatMetricHour(analysis.peakDeprivation and analysis.peakDeprivation.hour))),
        metricLine("Low Time", string.format("%.2fh", tonumber(analysis.timeInLowHours) or 0)),
        metricLine("Depleted Time", string.format("%.2fh", tonumber(analysis.timeInDepletedHours) or 0)),
        metricLine("End Energy", helpers.formatMetricNumber(finalState.fuel, "%.0f")),
        metricLine("End Depriv", helpers.formatMetricNumber(finalState.deprivation, "%.3f")),
    }
end

PROFILE_SUMMARY_BUILDERS.snack_gap_stress = function(run, helpers)
    local analysis = helpers.ensureAnalysis(run)
    local finalState = analysis.finalSnapshot and analysis.finalSnapshot.state or {}
    return {
        metricLine("Post-Snack Peckish", string.format("%s  energy %s",
            helpers.formatMetricHour(analysis.firstPeckishAfterFirstMeal and analysis.firstPeckishAfterFirstMeal.hour),
            helpers.formatMetricNumber(analysis.firstPeckishAfterFirstMeal and analysis.firstPeckishAfterFirstMeal.fuel, "%.0f"))),
        metricLine("Penalty Onset", helpers.formatMetricHour(analysis.firstDeprivationPenalty and analysis.firstDeprivationPenalty.hour)),
        metricLine("Peak Depriv", string.format("%s at %s",
            helpers.formatMetricNumber(analysis.peakDeprivation and analysis.peakDeprivation.value, "%.3f"),
            helpers.formatMetricHour(analysis.peakDeprivation and analysis.peakDeprivation.hour))),
        metricLine("Recovery Meal", helpers.formatMetricHour(analysis.recoveryMealCompletedHour)),
        metricLine("End Energy", helpers.formatMetricNumber(finalState.fuel, "%.0f")),
        metricLine("End Depriv", helpers.formatMetricNumber(finalState.deprivation, "%.3f")),
    }
end

PROFILE_SUMMARY_BUILDERS.recorded_exploration_day = function(run, helpers)
    local analysis = helpers.ensureAnalysis(run)
    local finalState = analysis.finalSnapshot and analysis.finalSnapshot.state or {}
    local intake = tonumber(finalState.totalIntakeKcal) or 0
    local burn = tonumber(finalState.totalBurnKcal) or 0
    local ratio = burn > 0 and (intake / burn) or 0
    return {
        metricLine("Items Eaten", tostring(#(analysis.consumes or {}))),
        metricLine("Intake / Burn", string.format("%.0f / %.0f kcal  (%.0f%%)", intake, burn, ratio * 100)),
        metricLine("First Peckish", string.format("%s  energy %s",
            helpers.formatMetricHour(analysis.firstPeckish and analysis.firstPeckish.hour),
            helpers.formatMetricNumber(analysis.firstPeckish and analysis.firstPeckish.fuel, "%.0f"))),
        metricLine("First Depleted", helpers.formatMetricHour(analysis.firstDepletedZone and analysis.firstDepletedZone.hour)),
        metricLine("Depleted Time", string.format("%.2fh", tonumber(analysis.timeInDepletedHours) or 0)),
        metricLine("Max Hidden Awake", string.format("%.2fh", tonumber(analysis.maxAwakeHiddenDepletedStreakHours) or 0)),
        metricLine("End Energy", helpers.formatMetricNumber(finalState.fuel, "%.0f")),
        metricLine("Peak Depriv", helpers.formatMetricNumber(analysis.peakDeprivation and analysis.peakDeprivation.value, "%.3f")),
    }
end

PROFILE_EVALUATORS.canonical_day = function(run, helpers)
    local analysis = helpers.ensureAnalysis(run)
    local validation = run.profile and run.profile.validation or {}
    local consumes = analysis.consumes or {}
    local peakDeprivationValue = tonumber(analysis.peakDeprivation and analysis.peakDeprivation.value) or 0
    local lowHours = tonumber(analysis.timeInLowHours) or 0
    local depletedHours = tonumber(analysis.timeInDepletedHours) or 0
    local endState = analysis.finalSnapshot and analysis.finalSnapshot.state or {}
    local endFuel = tonumber(endState.fuel) or 0
    local endDeprivation = tonumber(endState.deprivation) or 0
    local endZone = tostring(endState.lastZone or "")
    local firstDepleted = analysis.firstDepletedZone
    local hungerDropThreshold = tonumber(validation.hungerDropThreshold) or 0.01
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

    if firstDepleted or depletedHours > 0 or endFuel < endFuelFail or endZone == "Depleted" then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "canonical_day_became_too_rough",
            string.format("canonical day still hit depleted behavior (firstDepleted=%s, depletedTime=%.2fh, endEnergy=%.0f, endZone=%s)",
                helpers.formatMetricHour(firstDepleted and firstDepleted.hour), depletedHours, endFuel, endZone ~= "" and endZone or "--"))
    elseif endDeprivation >= (Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10) or peakDeprivationValue >= (Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10) then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "canonical_day_crossed_deprivation_onset",
            string.format("canonical day crossed deprivation penalty onset (peak=%.3f end=%.3f)", peakDeprivationValue, endDeprivation))
    elseif peakDeprivationValue > deprivationWarn or endFuel < endFuelWarn or endZone == "Low" then
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "canonical_day_finished_rough",
            string.format("canonical day stayed afloat, but leaned rough (lowTime=%.2fh peakDepriv=%.3f endEnergy=%.0f endZone=%s)",
                lowHours, peakDeprivationValue, endFuel, endZone ~= "" and endZone or "--"))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "canonical_day_stable",
            string.format("canonical day stayed broadly stable (lowTime=%.2fh peakDepriv=%.3f endEnergy=%.0f)",
                lowHours, peakDeprivationValue, endFuel))
    end

    if mealIssues == 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "canonical_meals_help",
            "structured proper meals consistently lowered hunger through the day")
    end
end

PROFILE_EVALUATORS.recorded_exploration_day = function(run, helpers)
    local analysis = helpers.ensureAnalysis(run)
    local validation = run.profile and run.profile.validation or {}
    local consumes = analysis.consumes or {}
    local finalState = analysis.finalSnapshot and analysis.finalSnapshot.state or {}
    local intake = tonumber(finalState.totalIntakeKcal) or 0
    local burn = tonumber(finalState.totalBurnKcal) or 0
    local ratio = burn > 0 and (intake / burn) or 0
    local minimumItems = tonumber(validation.minimumItems) or 8
    local maximumItems = tonumber(validation.maximumItems) or 14
    local minimumRatio = tonumber(validation.minimumIntakeBurnRatio) or 0.70
    local maximumRatio = tonumber(validation.maximumIntakeBurnRatio) or 1.25
    local maximumHiddenStreak = tonumber(validation.maximumAwakeHiddenDepletedStreakHours) or 2.0
    local maximumDeprivation = tonumber(validation.maximumDeprivation) or 0.01
    local hiddenStreak = tonumber(analysis.maxAwakeHiddenDepletedStreakHours) or 0
    local peakDeprivation = tonumber(analysis.peakDeprivation and analysis.peakDeprivation.value) or 0
    local weakReliefCount = 0
    local hungerDropThreshold = tonumber(validation.hungerDropThreshold) or 0.01

    for _, consume in ipairs(consumes) do
        if (tonumber(consume and consume.hungerDrop) or 0) < hungerDropThreshold then
            weakReliefCount = weakReliefCount + 1
        end
    end

    if #consumes < minimumItems then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "recorded_day_underprompted",
            string.format("closed-loop appetite only prompted %d items; expected at least %d", #consumes, minimumItems))
    elseif #consumes > maximumItems then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "recorded_day_overprompted",
            string.format("closed-loop appetite prompted %d items; expected at most %d", #consumes, maximumItems))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "recorded_day_prompt_count_plausible",
            string.format("closed-loop appetite prompted %d items", #consumes))
    end

    if burn <= 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "recorded_day_burn_missing",
            "recorded-workload autopilot produced no metabolic burn ledger")
    elseif ratio < minimumRatio then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "recorded_day_intake_too_low",
            string.format("hunger-led intake only covered %.0f%% of burn (%.0f / %.0f kcal)", ratio * 100, intake, burn))
    elseif ratio > maximumRatio then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "recorded_day_intake_too_high",
            string.format("hunger-led intake reached %.0f%% of burn (%.0f / %.0f kcal)", ratio * 100, intake, burn))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "recorded_day_intake_tracks_burn",
            string.format("hunger-led intake covered %.0f%% of burn (%.0f / %.0f kcal)", ratio * 100, intake, burn))
    end

    if hiddenStreak > maximumHiddenStreak then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "recorded_day_hidden_depletion_too_long",
            string.format("awake energy depletion stayed hidden for %.2fh; maximum %.2fh", hiddenStreak, maximumHiddenStreak))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "recorded_day_avoids_hidden_depletion",
            string.format("longest awake comfortable-but-depleted streak stayed at %.2fh", hiddenStreak))
    end

    if peakDeprivation > maximumDeprivation then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "recorded_day_deprivation_too_high",
            string.format("one recorded day reached %.3f deprivation", peakDeprivation))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "recorded_day_no_same_day_malnutrition",
            string.format("peak deprivation stayed at %.3f", peakDeprivation))
    end

    if #consumes > 0 and weakReliefCount == 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "recorded_day_meals_feel_effective",
            "every hunger-triggered item produced observable immediate relief")
    elseif weakReliefCount > 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "recorded_day_meals_feel_effective",
            string.format("%d hunger-triggered items failed to produce immediate relief", weakReliefCount))
    end
end

PROFILE_EVALUATORS.junk_food_day = function(run, helpers)
    local analysis = helpers.ensureAnalysis(run)
    local validation = run.profile and run.profile.validation or {}
    local consumes = analysis.consumes or {}
    local finalState = analysis.finalSnapshot and analysis.finalSnapshot.state or {}
    local endFuel = tonumber(finalState.fuel) or 0
    local endDeprivation = tonumber(finalState.deprivation) or 0
    local endZone = tostring(finalState.lastZone or "")
    local peakDeprivation = tonumber(analysis.peakDeprivation and analysis.peakDeprivation.value) or 0
    local lowHours = tonumber(analysis.timeInLowHours) or 0
    local minimumItems = tonumber(validation.minimumItems) or 3
    local hungerDropThreshold = tonumber(validation.hungerDropThreshold) or 0.01
    local weakReliefCount = 0

    for _, consume in ipairs(consumes) do
        if (tonumber(consume and consume.hungerDrop) or 0) < hungerDropThreshold then
            weakReliefCount = weakReliefCount + 1
        end
    end

    if #consumes < minimumItems then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "junk_food_day_too_few_items",
            string.format("junk-food sequence only consumed %d items; expected at least %d", #consumes, minimumItems))
    end

    if endZone == "Depleted"
        or endFuel < (tonumber(validation.endFuelFail) or 100)
        or endDeprivation >= (tonumber(validation.deprivationFail) or (Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10)) then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "junk_food_day_became_too_rough",
            string.format("junk-food day failed to stay fed (endEnergy=%.0f endDepriv=%.3f endZone=%s)",
                endFuel, endDeprivation, endZone ~= "" and endZone or "--"))
    elseif lowHours > (tonumber(validation.lowHoursWarn) or 2.0)
        or peakDeprivation > (tonumber(validation.deprivationWarn) or 0.03)
        or endFuel < (tonumber(validation.endFuelWarn) or 300) then
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "junk_food_day_finished_rough",
            string.format("junk food supplied energy, but the day ran rough (lowTime=%.2fh peakDepriv=%.3f endEnergy=%.0f)",
                lowHours, peakDeprivation, endFuel))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "junk_food_day_stayed_fed",
            string.format("junk-food grazing kept energy serviceable (items=%d endEnergy=%.0f peakDepriv=%.3f)",
                #consumes, endFuel, peakDeprivation))
    end

    if #consumes > 0 and weakReliefCount == 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "junk_food_items_relieve_hunger",
            "each consumed junk item produced an observable short-term hunger reduction")
    elseif weakReliefCount > 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "junk_food_items_relieve_hunger",
            string.format("%d consumed junk items did not materially reduce hunger", weakReliefCount))
    end
end

PROFILE_EVALUATORS.light_meals_day = function(run, helpers)
    local analysis = helpers.ensureAnalysis(run)
    local validation = run.profile and run.profile.validation or {}
    local consumes = analysis.consumes or {}
    local finalState = analysis.finalSnapshot and analysis.finalSnapshot.state or {}
    local endFuel = tonumber(finalState.fuel) or 0
    local endDeprivation = tonumber(finalState.deprivation) or 0
    local endZone = tostring(finalState.lastZone or "")
    local peakDeprivation = tonumber(analysis.peakDeprivation and analysis.peakDeprivation.value) or 0
    local lowHours = tonumber(analysis.timeInLowHours) or 0
    local depletedHours = tonumber(analysis.timeInDepletedHours) or 0
    local minimumMeals = tonumber(validation.minMeals) or 5
    local minimumLastMealHour = tonumber(validation.minLastMealHour) or 12.5
    local lastConsume = consumes[#consumes]
    local lastMealHour = tonumber(lastConsume and lastConsume.hour)
    local hungerDropThreshold = tonumber(validation.hungerDropThreshold) or 0.01
    local weakReliefCount = 0

    for _, consume in ipairs(consumes) do
        if (tonumber(consume and consume.hungerDrop) or 0) < hungerDropThreshold then
            weakReliefCount = weakReliefCount + 1
        end
    end

    if #consumes < minimumMeals then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "light_meals_day_too_few_meals",
            string.format("light-meals day only completed %d meals; expected at least %d", #consumes, minimumMeals))
    elseif lastMealHour == nil or lastMealHour < minimumLastMealHour then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "light_meals_day_ended_early",
            string.format("last light meal completed at %s; expected coverage through %s",
                helpers.formatMetricHour(lastMealHour), helpers.formatMetricHour(minimumLastMealHour)))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "light_meals_day_covered",
            string.format("light-meals sequence completed %d meals through %s",
                #consumes, helpers.formatMetricHour(lastMealHour)))
    end

    local deprivationOnset = Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10
    if peakDeprivation >= deprivationOnset or endDeprivation >= deprivationOnset then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "light_meals_day_became_too_rough",
            string.format("light meals produced meaningful deprivation (depletedTime=%.2fh endEnergy=%.0f endDepriv=%.3f endZone=%s)",
                depletedHours, endFuel, endDeprivation, endZone ~= "" and endZone or "--"))
    elseif endFuel <= 0 or endZone == "Depleted" or peakDeprivation > (tonumber(validation.deprivationWarn) or 0.03) then
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "light_meals_day_became_marginal",
            string.format("light meals stayed penalty-free, but reserve ended marginal (depletedTime=%.2fh endEnergy=%.0f peakDepriv=%.3f)",
                depletedHours, endFuel, peakDeprivation))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "light_meals_day_stayed_viable",
            string.format("light meals kept penalties negligible (lowTime=%.2fh endEnergy=%.0f peakDepriv=%.3f)",
                lowHours, endFuel, peakDeprivation))
    end

    if lowHours >= (tonumber(validation.lowHoursExpect) or 1.5) then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "light_meals_day_exposed_low_reserve",
            string.format("light diet exposed %.2fh of low energy without abrupt punishment", lowHours))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "light_meals_day_exposed_low_reserve",
            string.format("light diet only exposed %.2fh of low energy; scenario may be too generous", lowHours))
    end

    if #consumes > 0 and weakReliefCount == 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "light_meals_relieve_hunger",
            "each light meal produced an observable short-term hunger reduction")
    elseif weakReliefCount > 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "light_meals_relieve_hunger",
            string.format("%d light meals did not materially reduce hunger", weakReliefCount))
    end
end

PROFILE_EVALUATORS.snack_gap_stress = function(run, helpers)
    local analysis = helpers.ensureAnalysis(run)
    local validation = run.profile and run.profile.validation or {}
    local firstPeckish = analysis.firstPeckishAfterFirstMeal
    local firstDeprivationAny = analysis.firstDeprivationAny
    local firstDeprivationPenalty = analysis.firstDeprivationPenalty
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
    local finalState = analysis.finalSnapshot and analysis.finalSnapshot.state or {}
    local finalDeprivation = tonumber(finalState.deprivation) or 0
    local deprivationOnset = Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10
    local recoveryTolerance = tonumber(validation.recoveryTolerance) or 0.01

    if firstFuelBelow300 then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "stress_block_reached_deprivation_zone",
            string.format("stress block pushed energy below %.0f at %s", requiredFuelBelow, helpers.formatMetricHour(firstFuelBelow300.hour)))
    elseif firstFuelBelow500 then
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "stress_block_reached_deprivation_zone",
            string.format("stress block only reached Low zone; energy stayed above %.0f", requiredFuelBelow))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "stress_block_reached_deprivation_zone",
            string.format("stress block never pushed energy below 500 or into %s zone", tostring(validation.expectedFuelZone or "Low")))
    end

    if firstDeprivationAny then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "stress_block_accumulated_deprivation",
            string.format("deprivation began at %s", helpers.formatMetricHour(firstDeprivationAny.hour)))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "stress_block_accumulated_deprivation", "stress block never accumulated measurable deprivation")
    end

    if firstPeckish and (not firstDeprivationPenalty or firstPeckish.hour <= firstDeprivationPenalty.hour) then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "peckish_before_deprivation", "peckish reappeared after the snack before deprivation could apply penalties")
    elseif firstPeckish then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "peckish_before_deprivation",
            string.format("deprivation reached penalty onset at %s before peckish at %s",
                helpers.formatMetricHour(firstDeprivationPenalty and firstDeprivationPenalty.hour),
                helpers.formatMetricHour(firstPeckish.hour)))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "peckish_before_deprivation", "peckish never reappeared after the snack")
    end

    if firstPeckishFuel == nil then
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "peckish_above_threshold_fuel", "energy at first post-snack peckish was never observed")
    elseif firstPeckishFuel > peckishThreshold then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "peckish_above_threshold_fuel",
            string.format("peckish appeared with energy %.0f above threshold %.0f", firstPeckishFuel, peckishThreshold))
    elseif firstPeckishFuel > 0 then
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "peckish_above_threshold_fuel",
            string.format("peckish appeared late with energy %.0f below threshold %.0f", firstPeckishFuel, peckishThreshold))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "peckish_above_threshold_fuel", "peckish did not appear before energy hit zero")
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
    elseif finalDeprivation <= deprivationOnset + recoveryTolerance then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "deprivation_clears_after_refeed",
            string.format("deprivation returned to negligible penalty range by scenario end (%.3f)", finalDeprivation))
    elseif finalDeprivation < peakDeprivationValue then
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "deprivation_clears_after_refeed",
            string.format("deprivation was recovering but remained elevated at scenario end (peak=%.3f end=%.3f)",
                peakDeprivationValue, finalDeprivation))
    else
        helpers.addEvaluation(run, helpers.SEVERITY_FAIL, "deprivation_clears_after_refeed",
            string.format("deprivation did not recover after refeeding (peak=%.3f end=%.3f)",
                peakDeprivationValue, finalDeprivation))
    end

    if peakDeprivationValue < deprivationOnset then
        helpers.addEvaluation(run, helpers.SEVERITY_PASS, "stress_block_no_penalty", "stress block never crossed penalty onset")
    else
        helpers.addEvaluation(run, helpers.SEVERITY_WARN, "stress_block_no_penalty", "stress block did cross penalty onset")
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
