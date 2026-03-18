NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.TestPanel = NutritionMakesSense.TestPanel or {}

local TestPanel = NutritionMakesSense.TestPanel
local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local Metabolism = NutritionMakesSense.Metabolism or {}

local panelInstance = nil
local activeRun = nil
local activeSuite = nil
local resultLines = {}
local lastSavedPath = nil

local PANEL_W = 620
local PANEL_H = 520
local PAD = 12
local ROW_H = 24
local FONT = UIFont.Small
local FONT_MEDIUM = UIFont.Medium

local COLOR_BG = { r = 0.06, g = 0.07, b = 0.09, a = 0.96 }
local COLOR_BORDER = { r = 0.30, g = 0.45, b = 0.52, a = 0.7 }
local COLOR_HEADER = { r = 0.42, g = 0.82, b = 0.90, a = 1.0 }
local COLOR_LABEL = { r = 0.58, g = 0.64, b = 0.68, a = 1.0 }
local COLOR_VALUE = { r = 0.92, g = 0.94, b = 0.95, a = 1.0 }
local COLOR_DIM = { r = 0.45, g = 0.48, b = 0.52, a = 0.9 }
local COLOR_PASS = { r = 0.38, g = 0.78, b = 0.45, a = 1.0 }
local COLOR_WARN = { r = 0.93, g = 0.76, b = 0.27, a = 1.0 }
local COLOR_FAIL = { r = 0.88, g = 0.36, b = 0.30, a = 1.0 }
local COLOR_SECTION = { r = 0.34, g = 0.56, b = 0.63, a = 0.9 }

local FINDING_CORE = "core"
local FINDING_SOFT = "soft"
local FINDING_NONE = "none"

local FLOAT_TOLERANCE = {
    hunger = 0.005,
    hungerPenalty = 0.007,
    fuel = 0.05,
    carbs = 0.05,
    fats = 0.05,
    proteins = 0.05,
    balance = 0.25,
    weight = 0.002,
    controller = 0.02,
}

local VISIBLE_BASELINES = {
    hunger = 0.03,
    endurance = 1.0,
    fatigue = 0.0,
}

local BASE_SCENARIOS = {
    {
        id = "idle-comfortable",
        label = "Idle Comfortable",
        minutes = 10,
        state = {
            fuel = 1000,
            carbs = 980,
            fats = 294,
            proteins = 245,
            energyBalanceKcal = 0,
            weightKg = 80.0,
            weightController = 0,
        },
        expectation = "Fuel/hunger baseline in Comfortable zone",
    },
    {
        id = "idle-low-fuel",
        label = "Idle Low Fuel",
        minutes = 10,
        state = {
            fuel = 320,
            carbs = 980,
            fats = 294,
            proteins = 245,
            energyBalanceKcal = 0,
            weightKg = 80.0,
            weightController = 0,
        },
        expectation = "Low-zone hunger correction and decay",
    },
    {
        id = "idle-penalty",
        label = "Idle Penalty",
        minutes = 10,
        state = {
            fuel = 120,
            carbs = 980,
            fats = 294,
            proteins = 245,
            energyBalanceKcal = 0,
            weightKg = 80.0,
            weightController = -0.25,
        },
        expectation = "Penalty-zone hunger pressure and weight-loss onset",
    },
    {
        id = "idle-loss-chevron",
        label = "Idle Loss Chevron",
        minutes = 20,
        state = {
            fuel = 0,
            carbs = 980,
            fats = 294,
            proteins = 245,
            energyBalanceKcal = -1100,
            weightKg = 80.0,
            weightController = -0.60,
        },
        expectation = "Vanilla chevron should stay down under NMS loss",
    },
    {
        id = "idle-gain-chevron",
        label = "Idle Gain Chevron",
        minutes = 20,
        state = {
            fuel = 1900,
            carbs = 980,
            fats = 294,
            proteins = 245,
            energyBalanceKcal = 900,
            weightKg = 80.0,
            weightController = 0.60,
        },
        expectation = "Vanilla chevron should stay up under NMS gain",
    },
    {
        id = "meal-balanced-deposit",
        label = "Meal Balanced Deposit",
        minutes = 3,
        state = {
            fuel = 700,
            carbs = 600,
            fats = 180,
            proteins = 150,
            energyBalanceKcal = 0,
            weightKg = 80.0,
            weightController = 0,
        },
        initialDeposit = {
            hunger = -16,
            kcal = 420,
            carbs = 48,
            fats = 14,
            proteins = 18,
        },
        expectation = "Balanced direct deposit should raise fuel and macros cleanly",
    },
    {
        id = "meal-light-deposit",
        label = "Meal Light Deposit",
        minutes = 3,
        state = {
            fuel = 700,
            carbs = 600,
            fats = 180,
            proteins = 150,
            energyBalanceKcal = 0,
            weightKg = 80.0,
            weightController = 0,
        },
        initialDeposit = {
            hunger = -8,
            kcal = 160,
            carbs = 18,
            fats = 2,
            proteins = 4,
        },
        expectation = "Light direct deposit should raise state by a smaller amount",
    },
    {
        id = "meal-dense-bite-deposit",
        label = "Meal Dense Bite",
        minutes = 3,
        state = {
            fuel = 700,
            carbs = 600,
            fats = 180,
            proteins = 150,
            energyBalanceKcal = 0,
            weightKg = 80.0,
            weightController = 0,
        },
        initialDeposit = {
            hunger = -4,
            kcal = 250,
            carbs = 2,
            fats = 22,
            proteins = 1,
        },
        expectation = "Dense bite should emphasize kcal and fats over hunger-scale",
    },
    {
        id = "meal-partial-deposit",
        label = "Meal Partial Deposit",
        minutes = 3,
        state = {
            fuel = 700,
            carbs = 600,
            fats = 180,
            proteins = 150,
            energyBalanceKcal = 0,
            weightKg = 80.0,
            weightController = 0,
        },
        initialDeposit = {
            hunger = -8,
            kcal = 210,
            carbs = 24,
            fats = 7,
            proteins = 9,
        },
        expectation = "Partial deposit should scale balanced meal effects proportionally",
    },
    {
        id = "carb-deficiency-idle",
        label = "Carb Deficiency Idle",
        minutes = 12,
        state = {
            fuel = 900,
            carbs = 40,
            fats = 294,
            proteins = 245,
            energyBalanceKcal = 0,
            weightKg = 80.0,
            weightController = 0,
        },
        expectation = "Carb deficiency should stay visible in metabolism state while idle",
    },
    {
        id = "fat-deficiency-loss",
        label = "Fat Deficiency Loss",
        minutes = 12,
        state = {
            fuel = 0,
            carbs = 980,
            fats = 10,
            proteins = 245,
            energyBalanceKcal = -1400,
            weightKg = 80.0,
            weightController = -0.75,
        },
        expectation = "Fat deficiency should amplify loss-side weight multiplier",
    },
    {
        id = "protein-healing-penalty",
        label = "Protein Healing Penalty",
        minutes = 8,
        state = {
            fuel = 1000,
            carbs = 980,
            fats = 294,
            proteins = 10,
            energyBalanceKcal = 0,
            weightKg = 80.0,
            weightController = 0,
        },
        expectation = "Low protein should reduce healing multiplier and HealthFromFood",
    },
    {
        id = "trait-threshold-loss",
        label = "Trait Threshold Loss",
        minutes = 18,
        state = {
            fuel = 0,
            carbs = 980,
            fats = 120,
            proteins = 245,
            energyBalanceKcal = -2200,
            weightKg = 85.001,
            weightController = -0.95,
        },
        finalExpectations = {
            weightTrait = "Normal",
        },
        expectation = "Loss run should cross the Overweight threshold back to Normal",
    },
}

local function cloneTable(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = cloneTable(entry)
    end
    return copy
end

local function buildScenario(base, validate, mode)
    local scenario = cloneTable(base)
    scenario.validate = validate or {}
    scenario.mode = mode
    return scenario
end

local function buildSmokeScenarios()
    return {
        buildScenario(BASE_SCENARIOS[1], { hunger = FINDING_SOFT, hungerTolerance = FLOAT_TOLERANCE.hunger }, "smoke"),
        buildScenario(BASE_SCENARIOS[2], { hunger = FINDING_SOFT, hungerTolerance = FLOAT_TOLERANCE.hunger }, "smoke"),
        buildScenario(BASE_SCENARIOS[3], { hunger = FINDING_SOFT, hungerTolerance = FLOAT_TOLERANCE.hungerPenalty }, "smoke"),
        buildScenario(BASE_SCENARIOS[4], { hunger = FINDING_NONE }, "smoke"),
        buildScenario(BASE_SCENARIOS[5], { hunger = FINDING_NONE }, "smoke"),
        buildScenario(BASE_SCENARIOS[6], { hunger = FINDING_NONE, deposit = FINDING_CORE }, "smoke"),
        buildScenario(BASE_SCENARIOS[12], { hunger = FINDING_NONE, proteinDeficiency = FINDING_CORE, proteinHealing = FINDING_CORE }, "smoke"),
    }
end

local function buildDiagnosticScenarios()
    return {
        buildScenario(BASE_SCENARIOS[1], { hunger = FINDING_CORE, hungerTolerance = FLOAT_TOLERANCE.hunger }, "diagnostic"),
        buildScenario(BASE_SCENARIOS[2], { hunger = FINDING_CORE, hungerTolerance = FLOAT_TOLERANCE.hunger }, "diagnostic"),
        buildScenario(BASE_SCENARIOS[3], { hunger = FINDING_CORE, hungerTolerance = FLOAT_TOLERANCE.hungerPenalty }, "diagnostic"),
        buildScenario(BASE_SCENARIOS[4], { hunger = FINDING_NONE }, "diagnostic"),
        buildScenario(BASE_SCENARIOS[5], { hunger = FINDING_NONE }, "diagnostic"),
        buildScenario(BASE_SCENARIOS[6], { hunger = FINDING_NONE, deposit = FINDING_CORE }, "diagnostic"),
        buildScenario(BASE_SCENARIOS[7], { hunger = FINDING_NONE, deposit = FINDING_CORE }, "diagnostic"),
        buildScenario(BASE_SCENARIOS[8], { hunger = FINDING_NONE, deposit = FINDING_CORE }, "diagnostic"),
        buildScenario(BASE_SCENARIOS[9], { hunger = FINDING_NONE, deposit = FINDING_CORE }, "diagnostic"),
        buildScenario(BASE_SCENARIOS[10], { hunger = FINDING_NONE, carbDeficiency = FINDING_CORE }, "diagnostic"),
        buildScenario(BASE_SCENARIOS[11], { hunger = FINDING_NONE, fatDeficiency = FINDING_CORE, fatMultiplier = FINDING_CORE }, "diagnostic"),
        buildScenario(BASE_SCENARIOS[12], { hunger = FINDING_NONE, proteinDeficiency = FINDING_CORE, proteinHealing = FINDING_CORE }, "diagnostic"),
        buildScenario(BASE_SCENARIOS[13], { hunger = FINDING_NONE, weightTrait = FINDING_CORE }, "diagnostic"),
    }
end

local SMOKE_SCENARIOS = buildSmokeScenarios()
local DIAGNOSTIC_SCENARIOS = buildDiagnosticScenarios()

local function log(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(msg)
    else
        print("[NutritionMakesSense] " .. tostring(msg))
    end
end

local function safeCall(target, methodName, ...)
    if not target then
        return nil
    end
    local method = target[methodName]
    if type(method) ~= "function" then
        return nil
    end
    local ok, result = pcall(method, target, ...)
    if not ok then
        return nil
    end
    return result
end

local function clamp(value, lo, hi)
    local numeric = tonumber(value) or lo
    if numeric < lo then
        return lo
    end
    if numeric > hi then
        return hi
    end
    return numeric
end

local function getLocalPlayer()
    if type(getPlayer) ~= "function" then
        return nil
    end
    local ok, playerObj = pcall(getPlayer)
    if not ok then
        return nil
    end
    return playerObj
end

local function getWorldHours()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    if not gameTime then
        return nil
    end
    local ok, hours = pcall(gameTime.getWorldAgeHours, gameTime)
    if not ok then
        return nil
    end
    return tonumber(hours)
end

local function getPlayerStats(playerObj)
    return playerObj and safeCall(playerObj, "getStats") or nil
end

local function getPlayerNutrition(playerObj)
    return playerObj and safeCall(playerObj, "getNutrition") or nil
end

local function getPlayerBodyDamage(playerObj)
    return playerObj and safeCall(playerObj, "getBodyDamage") or nil
end

local function getCharacterStat(stats, enumKey, getterName)
    if not stats then
        return nil
    end
    if CharacterStat and enumKey and CharacterStat[enumKey] then
        local value = safeCall(stats, "get", CharacterStat[enumKey])
        if value ~= nil then
            return tonumber(value)
        end
    end
    if getterName then
        return tonumber(safeCall(stats, getterName))
    end
    return nil
end

local function getCurrentWorkload(playerObj)
    return Runtime.getCurrentWorkloadSnapshot and Runtime.getCurrentWorkloadSnapshot(playerObj) or nil
end

local function isPlayerAtRest(playerObj)
    if not playerObj then
        return false
    end
    if safeCall(playerObj, "isAsleep") == true then
        return false
    end
    if safeCall(playerObj, "isAttacking") == true then
        return false
    end
    if safeCall(playerObj, "hasTimedActions") == true then
        return false
    end

    local workload = getCurrentWorkload(playerObj)
    if workload then
        return tostring(workload.workTier) == tostring(Metabolism.WORK_TIER_REST)
    end
    return safeCall(playerObj, "isPlayerMoving") ~= true
end

local function formatNumber(value, precision)
    local numeric = tonumber(value)
    if numeric == nil then
        return "--"
    end
    return string.format("%." .. tostring(precision or 3) .. "f", numeric)
end

local function csvEscape(value)
    local text = tostring(value == nil and "" or value)
    if string.find(text, "[\",\n\r]", 1) then
        text = "\"" .. text:gsub("\"", "\"\"") .. "\""
    end
    return text
end

local function openWriter(relPath)
    local writer = nil
    if type(getFileWriter) == "function" then
        local ok, handle = pcall(getFileWriter, relPath, true, false)
        if ok and handle then
            writer = handle
        end
    end
    if not writer and type(getSandboxFileWriter) == "function" then
        local ok, handle = pcall(getSandboxFileWriter, relPath, true, false)
        if ok and handle then
            writer = handle
        end
    end
    return writer
end

local function summarizeWeightFlags(snapshot)
    if snapshot.weightUpLot then
        return "up++"
    end
    if snapshot.weightUp then
        return "up"
    end
    if snapshot.weightDown then
        return "down"
    end
    return "flat"
end

local function classifyWeightTrend(state)
    local rate = tonumber(state and state.lastWeightRateKgPerWeek or nil)
    if rate == nil then
        return "flat"
    end
    if rate > 0.05 then
        return "gain"
    end
    if rate < -0.05 then
        return "loss"
    end
    return "flat"
end

local function expectedChevron(state)
    local rate = tonumber(state and state.lastWeightRateKgPerWeek or 0) or 0
    local controller = tonumber(state and state.weightController or 0) or 0
    local up = rate > 0.05
    local down = rate < -0.05
    local upLot = up and (rate > 0.25 or controller > 0.5)
    return {
        weightUp = up,
        weightUpLot = upLot,
        weightDown = down,
    }
end

local function pushResultLine(text, color)
    resultLines[#resultLines + 1] = {
        text = tostring(text or ""),
        color = color or COLOR_VALUE,
    }
    while #resultLines > 16 do
        table.remove(resultLines, 1)
    end
    if panelInstance and type(panelInstance.setStatus) == "function" then
        panelInstance:setStatus(text)
    end
end

local function snapshotPlayer(playerObj)
    local stats = getPlayerStats(playerObj)
    local nutrition = getPlayerNutrition(playerObj)
    local bodyDamage = getPlayerBodyDamage(playerObj)
    local state = Runtime.getStateCopy and Runtime.getStateCopy(playerObj) or nil
    local workload = getCurrentWorkload(playerObj)
    return {
        state = state,
        hunger = clamp(getCharacterStat(stats, "HUNGER", "getHunger") or 0, 0, 1),
        endurance = clamp(getCharacterStat(stats, "ENDURANCE", "getEndurance") or 0, 0, 1),
        fatigue = clamp(getCharacterStat(stats, "FATIGUE", "getFatigue") or 0, 0, 1),
        calories = tonumber(nutrition and safeCall(nutrition, "getCalories")) or 0,
        carbs = tonumber(nutrition and safeCall(nutrition, "getCarbohydrates")) or 0,
        fats = tonumber(nutrition and safeCall(nutrition, "getLipids")) or 0,
        proteins = tonumber(nutrition and safeCall(nutrition, "getProteins")) or 0,
        weight = tonumber(nutrition and safeCall(nutrition, "getWeight")) or 0,
        weightUp = nutrition and safeCall(nutrition, "isIncWeight") == true or false,
        weightUpLot = nutrition and safeCall(nutrition, "isIncWeightLot") == true or false,
        weightDown = nutrition and safeCall(nutrition, "isDecWeight") == true or false,
        healthFromFood = tonumber(bodyDamage and safeCall(bodyDamage, "getHealthFromFood")) or 0,
        weightTrait = tostring(state and state.lastWeightTrait or "--"),
        workTier = tostring(state and state.lastWorkTier or workload and workload.workTier or "--"),
        metAverage = tonumber(state and state.lastMetAverage or workload and workload.averageMet or nil),
        metPeak = tonumber(state and state.lastMetPeak or workload and workload.peakMet or nil),
        metSource = tostring(state and state.lastMetSource or workload and workload.source or "--"),
    }
end

local function cloneState(state)
    if type(state) ~= "table" then
        return nil
    end
    return Metabolism.copyState(state)
end

local function nearlyEqual(actual, expected, tolerance)
    return math.abs((tonumber(actual) or 0) - (tonumber(expected) or 0)) <= (tolerance or 0.001)
end

local function addFinding(findings, severity, message)
    findings[#findings + 1] = {
        severity = severity or FINDING_CORE,
        message = tostring(message or ""),
    }
end

local function summarizeFindings(findings)
    local parts = {}
    for _, finding in ipairs(findings or {}) do
        parts[#parts + 1] = string.format("%s:%s", tostring(finding.severity), tostring(finding.message))
    end
    return table.concat(parts, " | ")
end

local function countFindings(findings, severity)
    local count = 0
    for _, finding in ipairs(findings or {}) do
        if finding.severity == severity then
            count = count + 1
        end
    end
    return count
end

local function deriveOutcome(findings)
    if countFindings(findings, FINDING_CORE) > 0 then
        return "FAIL"
    end
    if countFindings(findings, FINDING_SOFT) > 0 then
        return "WARN"
    end
    return "PASS"
end

local function outcomeColor(outcome)
    if outcome == "PASS" then
        return COLOR_PASS
    end
    if outcome == "WARN" then
        return COLOR_WARN
    end
    return COLOR_FAIL
end

local function compareSnapshot(run, minuteIndex, actual)
    local findings = {}
    local expectedState = run.predictedState
    local expectedChevronFlags = expectedChevron(expectedState)
    local validate = run.scenario and run.scenario.validate or {}
    local anchor = Metabolism.VANILLA_NUTRITION_ANCHOR or { calories = 0, carbs = 0, fats = 0, proteins = 0 }
    local expectedTrend = classifyWeightTrend(expectedState)

    local function check(condition, message, severity)
        if not condition then
            addFinding(findings, severity, string.format("minute=%d %s", minuteIndex, tostring(message)))
        end
    end

    check(actual.workTier == Metabolism.WORK_TIER_REST, string.format("workTier=%s expected rest", tostring(actual.workTier)), FINDING_CORE)
    check(type(actual.state) == "table", "missing NMS state", FINDING_CORE)

    if type(actual.state) == "table" then
        check(nearlyEqual(actual.state.fuel, expectedState.fuel, FLOAT_TOLERANCE.fuel), string.format("fuel actual=%s expected=%s", formatNumber(actual.state.fuel, 3), formatNumber(expectedState.fuel, 3)), FINDING_CORE)
        check(nearlyEqual(actual.state.carbs, expectedState.carbs, FLOAT_TOLERANCE.carbs), string.format("carbs actual=%s expected=%s", formatNumber(actual.state.carbs, 3), formatNumber(expectedState.carbs, 3)), FINDING_CORE)
        check(nearlyEqual(actual.state.fats, expectedState.fats, FLOAT_TOLERANCE.fats), string.format("fats actual=%s expected=%s", formatNumber(actual.state.fats, 3), formatNumber(expectedState.fats, 3)), FINDING_CORE)
        check(nearlyEqual(actual.state.proteins, expectedState.proteins, FLOAT_TOLERANCE.proteins), string.format("proteins actual=%s expected=%s", formatNumber(actual.state.proteins, 3), formatNumber(expectedState.proteins, 3)), FINDING_CORE)
        check(nearlyEqual(actual.state.energyBalanceKcal, expectedState.energyBalanceKcal, FLOAT_TOLERANCE.balance), string.format("balance actual=%s expected=%s", formatNumber(actual.state.energyBalanceKcal, 3), formatNumber(expectedState.energyBalanceKcal, 3)), FINDING_CORE)
        check(nearlyEqual(actual.state.weightKg, expectedState.weightKg, FLOAT_TOLERANCE.weight), string.format("weight actual=%s expected=%s", formatNumber(actual.state.weightKg, 4), formatNumber(expectedState.weightKg, 4)), FINDING_CORE)
        check(nearlyEqual(actual.state.weightController, expectedState.weightController, FLOAT_TOLERANCE.controller), string.format("controller actual=%s expected=%s", formatNumber(actual.state.weightController, 4), formatNumber(expectedState.weightController, 4)), FINDING_CORE)
        check(tostring(actual.state.lastZone) == tostring(expectedState.lastZone), string.format("zone actual=%s expected=%s", tostring(actual.state.lastZone), tostring(expectedState.lastZone)), FINDING_CORE)
        check(classifyWeightTrend(actual.state) == expectedTrend, string.format("trend actual=%s expected=%s", classifyWeightTrend(actual.state), expectedTrend), FINDING_CORE)
        if validate.carbDeficiency == FINDING_CORE then
            check(nearlyEqual(actual.state.lastCarbDeficiency, expectedState.lastCarbDeficiency, 0.001), string.format("carbDef actual=%s expected=%s", formatNumber(actual.state.lastCarbDeficiency, 3), formatNumber(expectedState.lastCarbDeficiency, 3)), FINDING_CORE)
        end
        if validate.fatDeficiency == FINDING_CORE then
            check(nearlyEqual(actual.state.lastFatDeficiency, expectedState.lastFatDeficiency, 0.001), string.format("fatDef actual=%s expected=%s", formatNumber(actual.state.lastFatDeficiency, 3), formatNumber(expectedState.lastFatDeficiency, 3)), FINDING_CORE)
        end
        if validate.proteinDeficiency == FINDING_CORE then
            check(nearlyEqual(actual.state.lastProteinDeficiency, expectedState.lastProteinDeficiency, 0.001), string.format("proteinDef actual=%s expected=%s", formatNumber(actual.state.lastProteinDeficiency, 3), formatNumber(expectedState.lastProteinDeficiency, 3)), FINDING_CORE)
        end
        if validate.fatMultiplier == FINDING_CORE then
            check(nearlyEqual(actual.state.lastFatWeightLossMultiplier, expectedState.lastFatWeightLossMultiplier, 0.001), string.format("fatWeight actual=%s expected=%s", formatNumber(actual.state.lastFatWeightLossMultiplier, 3), formatNumber(expectedState.lastFatWeightLossMultiplier, 3)), FINDING_CORE)
        end
        if validate.proteinHealing == FINDING_CORE then
            check(nearlyEqual(actual.state.lastProteinHealingMultiplier, expectedState.lastProteinHealingMultiplier, 0.001), string.format("proteinHealing actual=%s expected=%s", formatNumber(actual.state.lastProteinHealingMultiplier, 3), formatNumber(expectedState.lastProteinHealingMultiplier, 3)), FINDING_CORE)
            local expectedHealthFromFood = (tonumber(expectedState.baseHealthFromFood) or 0) * (tonumber(expectedState.lastProteinHealingMultiplier) or 0)
            check(nearlyEqual(actual.healthFromFood, expectedHealthFromFood, 0.0005), string.format("healthFromFood actual=%s expected=%s", formatNumber(actual.healthFromFood, 4), formatNumber(expectedHealthFromFood, 4)), FINDING_CORE)
        end
        if validate.weightTrait == FINDING_CORE then
            check(tostring(actual.state.lastWeightTrait) == tostring(expectedState.lastWeightTrait), string.format("weightTrait actual=%s expected=%s", tostring(actual.state.lastWeightTrait), tostring(expectedState.lastWeightTrait)), FINDING_CORE)
        end
        if validate.deposit == FINDING_CORE and minuteIndex == 0 and run.expectedInitialDepositKcal ~= nil then
            check(nearlyEqual(actual.state.lastDepositKcal, run.expectedInitialDepositKcal, 0.001), string.format("deposit actual=%s expected=%s", formatNumber(actual.state.lastDepositKcal, 3), formatNumber(run.expectedInitialDepositKcal, 3)), FINDING_CORE)
        end
    end

    if validate.hunger == FINDING_CORE or validate.hunger == FINDING_SOFT then
        check(
            nearlyEqual(actual.hunger, run.predictedHunger, validate.hungerTolerance or FLOAT_TOLERANCE.hunger),
            string.format("hunger actual=%s expected=%s", formatNumber(actual.hunger, 4), formatNumber(run.predictedHunger, 4)),
            validate.hunger
        )
    end

    check(nearlyEqual(actual.calories, anchor.calories, 0.001), string.format("calories actual=%s expected anchor=%s", formatNumber(actual.calories, 3), formatNumber(anchor.calories, 3)), FINDING_CORE)
    check(nearlyEqual(actual.carbs, anchor.carbs, 0.001), string.format("vanilla carbs actual=%s expected anchor=%s", formatNumber(actual.carbs, 3), formatNumber(anchor.carbs, 3)), FINDING_CORE)
    check(nearlyEqual(actual.fats, anchor.fats, 0.001), string.format("vanilla fats actual=%s expected anchor=%s", formatNumber(actual.fats, 3), formatNumber(anchor.fats, 3)), FINDING_CORE)
    check(nearlyEqual(actual.proteins, anchor.proteins, 0.001), string.format("vanilla proteins actual=%s expected anchor=%s", formatNumber(actual.proteins, 3), formatNumber(anchor.proteins, 3)), FINDING_CORE)
    check(nearlyEqual(actual.weight, expectedState.weightKg, FLOAT_TOLERANCE.weight), string.format("visible weight actual=%s expected=%s", formatNumber(actual.weight, 4), formatNumber(expectedState.weightKg, 4)), FINDING_CORE)
    check(actual.weightUp == expectedChevronFlags.weightUp, string.format("weightUp actual=%s expected=%s", tostring(actual.weightUp), tostring(expectedChevronFlags.weightUp)), FINDING_CORE)
    check(actual.weightUpLot == expectedChevronFlags.weightUpLot, string.format("weightUpLot actual=%s expected=%s", tostring(actual.weightUpLot), tostring(expectedChevronFlags.weightUpLot)), FINDING_CORE)
    check(actual.weightDown == expectedChevronFlags.weightDown, string.format("weightDown actual=%s expected=%s", tostring(actual.weightDown), tostring(expectedChevronFlags.weightDown)), FINDING_CORE)

    return findings
end

local TEST_CSV_HEADER = table.concat({
    "suite_mode",
    "scenario",
    "minute",
    "expected_hunger",
    "actual_hunger",
    "expected_fuel",
    "actual_fuel",
    "expected_zone",
    "actual_zone",
    "expected_balance",
    "actual_balance",
    "expected_weight_kg",
    "actual_weight_kg",
    "expected_controller",
    "actual_controller",
    "expected_trend",
    "actual_trend",
    "expected_chevron",
    "actual_chevron",
    "actual_vanilla_kcal",
    "actual_vanilla_carbs",
    "actual_vanilla_fats",
    "actual_vanilla_proteins",
    "actual_health_from_food",
    "actual_weight_trait",
    "actual_carb_def",
    "actual_fat_def",
    "actual_protein_def",
    "actual_fat_weight_mult",
    "actual_protein_healing_mult",
    "actual_work_tier",
    "actual_met_avg",
    "actual_met_peak",
    "core_findings",
    "soft_findings",
    "findings",
}, ",")

local SUITE_CSV_HEADER = table.concat({
    "suite_mode",
    "suite_outcome",
    "scenario",
    "scenario_outcome",
    "core_findings",
    "soft_findings",
    "report_path",
    "summary",
}, ",")

local function recordSampleRow(run, minuteIndex, actual, findings)
    if not run then
        return
    end
    local expectedState = run.predictedState or {}
    local expectedTrend = classifyWeightTrend(expectedState)
    local expectedFlags = expectedChevron(expectedState)
    local row = {
        run.mode or "",
        run.scenario and run.scenario.id or "",
        tostring(minuteIndex or 0),
        tostring(run.predictedHunger or ""),
        tostring(actual and actual.hunger or ""),
        tostring(expectedState.fuel or ""),
        tostring(actual and actual.state and actual.state.fuel or ""),
        tostring(expectedState.lastZone or ""),
        tostring(actual and actual.state and actual.state.lastZone or ""),
        tostring(expectedState.energyBalanceKcal or ""),
        tostring(actual and actual.state and actual.state.energyBalanceKcal or ""),
        tostring(expectedState.weightKg or ""),
        tostring(actual and actual.weight or ""),
        tostring(expectedState.weightController or ""),
        tostring(actual and actual.state and actual.state.weightController or ""),
        tostring(expectedTrend or ""),
        tostring(actual and actual.state and classifyWeightTrend(actual.state) or ""),
        tostring(expectedFlags.weightUpLot and "up++" or expectedFlags.weightUp and "up" or expectedFlags.weightDown and "down" or "flat"),
        tostring(actual and summarizeWeightFlags(actual) or ""),
        tostring(actual and actual.calories or ""),
        tostring(actual and actual.carbs or ""),
        tostring(actual and actual.fats or ""),
        tostring(actual and actual.proteins or ""),
        tostring(actual and actual.healthFromFood or ""),
        tostring(actual and actual.weightTrait or ""),
        tostring(actual and actual.state and actual.state.lastCarbDeficiency or ""),
        tostring(actual and actual.state and actual.state.lastFatDeficiency or ""),
        tostring(actual and actual.state and actual.state.lastProteinDeficiency or ""),
        tostring(actual and actual.state and actual.state.lastFatWeightLossMultiplier or ""),
        tostring(actual and actual.state and actual.state.lastProteinHealingMultiplier or ""),
        tostring(actual and actual.workTier or ""),
        tostring(actual and actual.metAverage or ""),
        tostring(actual and actual.metPeak or ""),
        tostring(countFindings(findings, FINDING_CORE)),
        tostring(countFindings(findings, FINDING_SOFT)),
        summarizeFindings(findings),
    }
    for index = 1, #row do
        row[index] = csvEscape(row[index])
    end
    run.csvRows[#run.csvRows + 1] = table.concat(row, ",")
end

local function saveCsv(relPath, header, rows)
    local writer = openWriter(relPath)
    if not writer then
        log("[NMS_TEST] failed to open writer for " .. relPath)
        return nil
    end
    writer:writeln(header)
    for _, row in ipairs(rows or {}) do
        writer:writeln(row)
    end
    writer:close()
    lastSavedPath = relPath
    return relPath
end

local function saveRunReport(run, outcome)
    if not run then
        return nil
    end
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local scenarioId = tostring(run.scenario and run.scenario.id or "scenario"):gsub("[^%w%-_]+", "_")
    local relPath = string.format("nmslogs/nms_test_%s_%s_%s.csv", scenarioId, string.lower(outcome or "pass"), timestamp)
    local path = saveCsv(relPath, TEST_CSV_HEADER, run.csvRows)
    if path then
        log(string.format("[NMS_TEST] report saved: %s", path))
    end
    return path
end

local function saveSuiteSummary(suite)
    if not suite then
        return nil
    end
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local relPath = string.format("nmslogs/nms_%s_suite_%s_%s.csv", tostring(suite.mode or "suite"), string.lower(tostring(suite.outcome or "pass")), timestamp)
    local rows = {}
    for _, result in ipairs(suite.results or {}) do
        local row = {
            suite.mode,
            suite.outcome,
            result.id,
            result.outcome,
            tostring(result.coreCount or 0),
            tostring(result.softCount or 0),
            tostring(result.reportPath or ""),
            tostring(result.summary or ""),
        }
        for index = 1, #row do
            row[index] = csvEscape(row[index])
        end
        rows[#rows + 1] = table.concat(row, ",")
    end
    local path = saveCsv(relPath, SUITE_CSV_HEADER, rows)
    if path then
        log(string.format("[NMS_TEST] suite summary saved: %s", path))
    end
    return path
end

local function finalizeSuiteIfDone()
    if not activeSuite or activeRun then
        return
    end

    if #activeSuite.pending > 0 then
        local nextScenario = table.remove(activeSuite.pending, 1)
        TestPanel.startScenario(nextScenario, { mode = activeSuite.mode, chained = true, suite = activeSuite })
        return
    end

    local suiteFindings = {}
    for _, result in ipairs(activeSuite.results or {}) do
        if result.outcome == "FAIL" then
            suiteFindings[#suiteFindings + 1] = FINDING_CORE
        elseif result.outcome == "WARN" then
            suiteFindings[#suiteFindings + 1] = FINDING_SOFT
        end
    end

    local hasFail = false
    local hasWarn = false
    for _, severity in ipairs(suiteFindings) do
        if severity == FINDING_CORE then
            hasFail = true
        elseif severity == FINDING_SOFT then
            hasWarn = true
        end
    end

    activeSuite.outcome = hasFail and "FAIL" or hasWarn and "WARN" or "PASS"
    activeSuite.summaryPath = saveSuiteSummary(activeSuite)

    local text = string.format(
        "[NMS_TEST] %s SUITE=%s scenarios=%d file=%s",
        tostring(activeSuite.outcome),
        tostring(activeSuite.label),
        tonumber(#(activeSuite.results or {})),
        tostring(activeSuite.summaryPath or "--")
    )
    log(text)
    pushResultLine(text, outcomeColor(activeSuite.outcome))
    activeSuite = nil
end

local function appendFindings(run, findings)
    if not run or not findings then
        return
    end
    run.accumulatedFindings = run.accumulatedFindings or {}
    for _, finding in ipairs(findings) do
        run.accumulatedFindings[#run.accumulatedFindings + 1] = finding
    end
end

local function evaluateFinalExpectations(run)
    local findings = {}
    if not run or not run.scenario or not run.scenario.finalExpectations then
        return findings
    end
    local actual = run.lastActual
    local expected = run.scenario.finalExpectations
    if expected.weightTrait and actual and actual.state then
        if tostring(actual.state.lastWeightTrait) ~= tostring(expected.weightTrait) then
            addFinding(findings, FINDING_CORE, string.format("final weightTrait actual=%s expected=%s", tostring(actual.state.lastWeightTrait), tostring(expected.weightTrait)))
        end
    end
    return findings
end

local function completeRun(findings, extraMessage)
    local run = activeRun
    if not run then
        return
    end

    appendFindings(run, findings)
    local finalFindings = run.accumulatedFindings or {}

    local outcome = deriveOutcome(finalFindings)
    local summary = string.format(
        "[NMS_TEST] %s %s minute=%d/%d fuel=%s hunger=%s zone=%s chevron=%s",
        tostring(outcome),
        tostring(run.scenario.label),
        tonumber(run.elapsedMinutes or 0),
        tonumber(run.scenario.minutes or 0),
        formatNumber(run.lastActual and run.lastActual.state and run.lastActual.state.fuel, 3),
        formatNumber(run.lastActual and run.lastActual.hunger, 4),
        tostring(run.lastActual and run.lastActual.state and run.lastActual.state.lastZone or "--"),
        tostring(run.lastActual and summarizeWeightFlags(run.lastActual) or "--")
    )
    if extraMessage and extraMessage ~= "" then
        summary = summary .. " " .. tostring(extraMessage)
    end

    local path = saveRunReport(run, outcome)
    if path then
        summary = summary .. " file=" .. tostring(path)
    end

    log(summary)
    pushResultLine(summary, outcomeColor(outcome))
    for _, finding in ipairs(finalFindings) do
        log(string.format("[NMS_TEST_DETAIL] severity=%s %s", tostring(finding.severity), tostring(finding.message)))
    end

    if activeSuite then
        activeSuite.results[#activeSuite.results + 1] = {
            id = run.scenario.id,
            label = run.scenario.label,
            outcome = outcome,
            coreCount = countFindings(finalFindings, FINDING_CORE),
            softCount = countFindings(finalFindings, FINDING_SOFT),
            reportPath = path,
            summary = summary,
        }
    end

    activeRun = nil
    finalizeSuiteIfDone()
end

function TestPanel.abortActive(reason)
    if not activeRun then
        activeSuite = nil
        return
    end
    completeRun({
        { severity = FINDING_CORE, message = tostring(reason or "aborted") },
    }, tostring(reason or "aborted"))
end

local function normalizeForScenario(playerObj, scenario)
    if not Runtime.debugResetState or not Runtime.debugSetStateFields or not Runtime.debugClearSuppressions then
        return nil, "runtime debug helpers unavailable"
    end

    Runtime.debugResetState(playerObj, "test-panel-reset")
    Runtime.debugClearSuppressions(playerObj, "test-panel-clear")
    Runtime.debugSetStateFields(playerObj, scenario.state or {}, "test-panel-seed")
    if Runtime.syncVisibleShell then
        Runtime.syncVisibleShell(playerObj, "test-panel-seed")
    end

    local state = Runtime.getStateCopy and Runtime.getStateCopy(playerObj) or nil
    local healthFromFood = tonumber(state and state.baseHealthFromFood) or nil
    if Runtime.debugSetVisibleBaselines then
        Runtime.debugSetVisibleBaselines(playerObj, {
            hunger = VISIBLE_BASELINES.hunger,
            endurance = VISIBLE_BASELINES.endurance,
            fatigue = VISIBLE_BASELINES.fatigue,
            healthFromFood = healthFromFood,
        }, "test-panel-visible")
    end

    local snapshot = snapshotPlayer(playerObj)
    local anchor = Metabolism.VANILLA_NUTRITION_ANCHOR or { calories = 0, carbs = 0, fats = 0, proteins = 0 }

    if snapshot.workTier ~= Metabolism.WORK_TIER_REST then
        return nil, "player must remain at rest during normalization"
    end
    if type(snapshot.state) ~= "table" then
        return nil, "failed to capture runtime state after normalization"
    end
    if not nearlyEqual(snapshot.calories, anchor.calories, 0.001)
        or not nearlyEqual(snapshot.carbs, anchor.carbs, 0.001)
        or not nearlyEqual(snapshot.fats, anchor.fats, 0.001)
        or not nearlyEqual(snapshot.proteins, anchor.proteins, 0.001) then
        return nil, "vanilla shell did not anchor after normalization"
    end
    if not nearlyEqual(snapshot.hunger, VISIBLE_BASELINES.hunger, 0.01) then
        return nil, "visible hunger baseline did not normalize"
    end
    if not nearlyEqual(snapshot.endurance, VISIBLE_BASELINES.endurance, 0.01) then
        return nil, "visible endurance baseline did not normalize"
    end
    if not nearlyEqual(snapshot.fatigue, VISIBLE_BASELINES.fatigue, 0.01) then
        return nil, "visible fatigue baseline did not normalize"
    end

    return snapshot, nil
end

local function applyInitialDeposit(playerObj, run)
    local deposit = run and run.scenario and run.scenario.initialDeposit or nil
    if type(deposit) ~= "table" then
        return run.lastActual, {}
    end

    if type(Runtime.applyAuthoritativeDeposit) ~= "function" then
        return run.lastActual, {
            { severity = FINDING_CORE, message = "authoritative deposit helper unavailable" },
        }
    end

    local values = cloneTable(deposit)
    local report = Runtime.applyAuthoritativeDeposit(playerObj, values, "test-panel-deposit", {
        queueSuppression = false,
    })
    if not report then
        return run.lastActual, {
            { severity = FINDING_CORE, message = "authoritative deposit failed" },
        }
    end

    Metabolism.applyFoodValues(run.predictedState, values, 1, "test-panel-deposit")
    run.expectedInitialDepositKcal = tonumber(values.kcal) or 0

    local actual = snapshotPlayer(playerObj)
    run.lastActual = actual
    local findings = compareSnapshot(run, 0, actual)
    recordSampleRow(run, 0, actual, findings)
    return actual, findings
end

function TestPanel.startScenario(scenario, options)
    options = options or {}
    local playerObj = getLocalPlayer()
    if not playerObj then
        pushResultLine("[NMS_TEST] no local player available", COLOR_FAIL)
        return false
    end
    if not isPlayerAtRest(playerObj) then
        pushResultLine("[NMS_TEST] player must be at rest before starting a test", COLOR_FAIL)
        return false
    end

    if activeRun then
        TestPanel.abortActive("replaced by new scenario")
    end

    local initial, err = normalizeForScenario(playerObj, scenario)
    if not initial then
        local finding = { severity = FINDING_CORE, message = tostring(err or "normalization failed") }
        activeRun = {
            scenario = scenario,
            mode = options.mode or scenario.mode or "diagnostic",
            elapsedMinutes = 0,
            predictedState = nil,
            predictedHunger = nil,
            lastActual = snapshotPlayer(playerObj),
            csvRows = {},
        }
        completeRun({ finding }, "preflight")
        return false
    end

    activeRun = {
        scenario = scenario,
        mode = options.mode or scenario.mode or "diagnostic",
        elapsedMinutes = 0,
        predictedState = cloneState(initial.state),
        predictedHunger = initial.hunger,
        lastActual = initial,
        csvRows = {},
        lastObservedWorldHours = getWorldHours(),
        accumulatedFindings = {},
    }

    local postDepositActual, initialFindings = applyInitialDeposit(playerObj, activeRun)
    activeRun.lastActual = postDepositActual or activeRun.lastActual
    appendFindings(activeRun, initialFindings)

    local startLine = string.format(
        "[NMS_TEST] START mode=%s scenario=%s minutes=%d expectation=%s",
        tostring(activeRun.mode),
        tostring(scenario.label),
        tonumber(scenario.minutes or 0),
        tostring(scenario.expectation or "--")
    )
    log(startLine)
    pushResultLine(startLine, COLOR_HEADER)

    if deriveOutcome(initialFindings) == "FAIL" then
        completeRun({}, "setup-failure")
        return false
    end
    return true
end

function TestPanel.startSuite(mode)
    local scenarios = mode == "smoke" and cloneTable(SMOKE_SCENARIOS) or cloneTable(DIAGNOSTIC_SCENARIOS)
    activeSuite = {
        mode = mode == "smoke" and "smoke" or "diagnostic",
        label = mode == "smoke" and "Smoke Suite" or "Diagnostics",
        pending = scenarios,
        results = {},
    }
    local first = table.remove(activeSuite.pending, 1)
    if not first then
        activeSuite = nil
        return
    end
    TestPanel.startScenario(first, { mode = activeSuite.mode, chained = true, suite = activeSuite })
end

function TestPanel.runSmokeSuite()
    TestPanel.startSuite("smoke")
end

function TestPanel.runDiagnostics()
    TestPanel.startSuite("diagnostic")
end

function TestPanel.onEveryOneMinute()
    if not activeRun then
        return
    end

    local playerObj = getLocalPlayer()
    if not playerObj then
        TestPanel.abortActive("local player disappeared")
        return
    end

    local run = activeRun
    run.elapsedMinutes = run.elapsedMinutes + 1
    local nowHours = getWorldHours()
    local elapsedHours = 0
    if nowHours ~= nil and run.lastObservedWorldHours ~= nil then
        elapsedHours = math.max(0, nowHours - run.lastObservedWorldHours)
    end
    run.lastObservedWorldHours = nowHours or run.lastObservedWorldHours

    local report = Metabolism.advanceState(run.predictedState, elapsedHours, {
        averageMet = Metabolism.MET_REST,
        peakMet = Metabolism.MET_REST,
        observedHours = elapsedHours,
        heavyHours = 0,
        veryHeavyHours = 0,
        source = "test-panel-rest",
        sleepObserved = false,
    }, {
        reason = "test-panel-rest",
    })
    run.predictedHunger = clamp(
        run.predictedHunger + (tonumber(report.baseHungerGain) or 0) + (tonumber(report.correctionHungerGain) or 0),
        0,
        1
    )

    local actual = snapshotPlayer(playerObj)
    run.lastActual = actual
    local findings = compareSnapshot(run, run.elapsedMinutes, actual)
    appendFindings(run, findings)
    recordSampleRow(run, run.elapsedMinutes, actual, findings)

    local outcome = deriveOutcome(findings)
    local sampleLine = string.format(
        "[NMS_TEST_SAMPLE] mode=%s scenario=%s minute=%d/%d fuel=%s hunger=%s zone=%s chevron=%s outcome=%s",
        tostring(run.mode),
        tostring(run.scenario.label),
        tonumber(run.elapsedMinutes),
        tonumber(run.scenario.minutes or 0),
        formatNumber(actual.state and actual.state.fuel, 3),
        formatNumber(actual.hunger, 4),
        tostring(actual.state and actual.state.lastZone or "--"),
        summarizeWeightFlags(actual),
        tostring(outcome)
    )
    log(sampleLine)
    pushResultLine(sampleLine, outcomeColor(outcome))

    if outcome == "FAIL" then
        completeRun({}, "core-failure")
        return
    end

    if run.elapsedMinutes >= (run.scenario.minutes or 0) then
        local finalFindings = evaluateFinalExpectations(run)
        completeRun(finalFindings, "completed")
    end
end

local NMS_TestOverlay = (ISPanel and type(ISPanel.derive) == "function")
    and ISPanel:derive("NMS_TestOverlay")
    or nil

if not NMS_TestOverlay then
    NMS_TestOverlay = {}
end

function NMS_TestOverlay:new(x, y)
    local panel = ISPanel:new(x, y, PANEL_W, PANEL_H)
    setmetatable(panel, self)
    self.__index = self
    panel.moveWithMouse = true
    panel.backgroundColor = COLOR_BG
    panel.borderColor = COLOR_BORDER
    panel.statusText = "ready"
    panel.scenarioButtons = {}
    return panel
end

function NMS_TestOverlay:initialise()
    ISPanel.initialise(self)
end

function NMS_TestOverlay:createChildren()
    ISPanel.createChildren(self)

    self.closeBtn = ISButton:new(PANEL_W - 28, 4, 22, 22, "X", self, NMS_TestOverlay.onClose)
    self.closeBtn:initialise()
    self:addChild(self.closeBtn)

    self.smokeBtn = ISButton:new(PAD, 4, 94, 22, "Smoke Suite", self, NMS_TestOverlay.onRunSmoke)
    self.smokeBtn:initialise()
    self:addChild(self.smokeBtn)

    self.diagBtn = ISButton:new(PAD + 98, 4, 96, 22, "Diagnostics", self, NMS_TestOverlay.onRunDiagnostics)
    self.diagBtn:initialise()
    self:addChild(self.diagBtn)

    self.abortBtn = ISButton:new(PAD + 198, 4, 62, 22, "Abort", self, NMS_TestOverlay.onAbort)
    self.abortBtn:initialise()
    self:addChild(self.abortBtn)

    self.clearBtn = ISButton:new(PAD + 264, 4, 74, 22, "Clear Log", self, NMS_TestOverlay.onClearLog)
    self.clearBtn:initialise()
    self:addChild(self.clearBtn)

    local y = 68
    for _, scenario in ipairs(DIAGNOSTIC_SCENARIOS) do
        local button = ISButton:new(PANEL_W - PAD - 56, y - 2, 56, 20, "Run", self, NMS_TestOverlay.onRunScenario)
        button:initialise()
        button.internal = scenario.id
        self:addChild(button)
        self.scenarioButtons[scenario.id] = button
        y = y + ROW_H
    end
end

function NMS_TestOverlay:setStatus(text)
    self.statusText = tostring(text or "ready")
end

function NMS_TestOverlay:onRunSmoke()
    TestPanel.runSmokeSuite()
end

function NMS_TestOverlay:onRunDiagnostics()
    TestPanel.runDiagnostics()
end

function NMS_TestOverlay:onAbort()
    TestPanel.abortActive("aborted by user")
end

function NMS_TestOverlay:onClearLog()
    resultLines = {}
    self:setStatus("cleared")
end

function NMS_TestOverlay:onRunScenario(button)
    local scenarioId = button and button.internal or nil
    for _, scenario in ipairs(DIAGNOSTIC_SCENARIOS) do
        if scenario.id == scenarioId then
            TestPanel.startScenario(cloneTable(scenario), { mode = "diagnostic" })
            return
        end
    end
end

function NMS_TestOverlay:onClose()
    if activeRun then
        TestPanel.abortActive("panel closed")
    end
    self:setVisible(false)
    self:removeFromUIManager()
    panelInstance = nil
end

function NMS_TestOverlay:prerender()
    ISPanel.prerender(self)
    self:drawRectBorder(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)
end

function NMS_TestOverlay:render()
    ISPanel.render(self)

    local suiteLabel = activeSuite and activeSuite.label or "none"
    local runLabel = activeRun and activeRun.scenario and activeRun.scenario.label or "none"

    self:drawText("NMS Test Runner", PAD, 8, COLOR_HEADER.r, COLOR_HEADER.g, COLOR_HEADER.b, COLOR_HEADER.a, FONT_MEDIUM)
    self:drawText(self.statusText or "ready", PAD + 350, 8, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, COLOR_DIM.a, FONT)

    self:drawText("Active Suite: " .. tostring(suiteLabel), PAD, 38, COLOR_LABEL.r, COLOR_LABEL.g, COLOR_LABEL.b, COLOR_LABEL.a, FONT)
    self:drawText("Active Scenario: " .. tostring(runLabel), 220, 38, COLOR_LABEL.r, COLOR_LABEL.g, COLOR_LABEL.b, COLOR_LABEL.a, FONT)

    local y = 70
    self:drawText("Manual Diagnostics", PAD, y - 20, COLOR_SECTION.r, COLOR_SECTION.g, COLOR_SECTION.b, COLOR_SECTION.a, FONT_MEDIUM)
    for _, scenario in ipairs(DIAGNOSTIC_SCENARIOS) do
        self:drawText(scenario.label, PAD, y, COLOR_VALUE.r, COLOR_VALUE.g, COLOR_VALUE.b, COLOR_VALUE.a, FONT)
        self:drawText(string.format("%d min", tonumber(scenario.minutes or 0)), 180, y, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, COLOR_DIM.a, FONT)
        self:drawText(scenario.expectation or "--", 250, y, COLOR_LABEL.r, COLOR_LABEL.g, COLOR_LABEL.b, COLOR_LABEL.a, FONT)
        y = y + ROW_H
    end

    y = y + 10
    self:drawText("Last File: " .. tostring(lastSavedPath or "--"), PAD, y, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, COLOR_DIM.a, FONT)
    y = y + 20
    self:drawText("Recent Results", PAD, y, COLOR_SECTION.r, COLOR_SECTION.g, COLOR_SECTION.b, COLOR_SECTION.a, FONT_MEDIUM)
    y = y + 22

    for _, entry in ipairs(resultLines) do
        local color = entry.color or COLOR_VALUE
        self:drawText(entry.text, PAD, y, color.r, color.g, color.b, color.a, FONT)
        y = y + 18
    end
end

function TestPanel.toggle()
    if panelInstance and panelInstance:getIsVisible() then
        panelInstance:onClose()
        return
    end

    panelInstance = NMS_TestOverlay:new(120, 120)
    panelInstance:initialise()
    panelInstance:addToUIManager()
end

if Events and Events.EveryOneMinute and type(Events.EveryOneMinute.Add) == "function" then
    Events.EveryOneMinute.Add(TestPanel.onEveryOneMinute)
end

return TestPanel
