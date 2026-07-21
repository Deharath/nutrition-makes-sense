NutritionMakesSense = NutritionMakesSense or {}

local Snapshot = NutritionMakesSense.MPSnapshot or {}
NutritionMakesSense.MPSnapshot = Snapshot

local CORE_STATE_FIELDS = {
    "version",
    "fuel",
    "proteins",
    "weightKg",
    "deprivation",
    "visibleHunger",
    "satietyBuffer",
    "lastZone",
    "lastWeightTrait",
    "lastWeightRateKgPerWeek",
    "lastHungerBand",
}

local DIAGNOSTIC_STATE_FIELDS = {
    "weightController",
    "weightBalanceKcal",
    "underfeedingDebtKcal",
    "lastWeightBalanceKcal",
    "lastWeightControllerTarget",
    "lastUnderfeedingDebtKcal",
    "lastDeprivationTarget",
    "lastMetAverage",
    "lastMetPeak",
    "lastEffectiveEnduranceMet",
    "lastWorkTier",
    "lastMetSource",
    "lastObservedHours",
    "lastHeavyHours",
    "lastVeryHeavyHours",
    "lastBurnKcal",
    "lastDepositKcal",
    "depositSequence",
    "lastFuelPressureFactor",
    "lastGateMultiplier",
    "lastMetHungerFactor",
    "lastPassiveHungerGain",
    "lastExtraEnduranceDrain",
    "lastEnduranceRegenScale",
    "lastEnduranceDeprivDrain",
    "lastProteinDeficiency",
    "lastProteinHealingMultiplier",
    "lastSatietyQuality",
    "lastSatietyContribution",
    "lastSatietyReturnFactor",
    "lastMealHungerDrop",
    "lastMealHungerObserved",
    "lastTraceReason",
}

local function copyFields(target, state, fields)
    for _, field in ipairs(fields) do
        local value = state[field]
        if value ~= nil then
            target[field] = value
        end
    end
end

function Snapshot.copyState(state, includeDiagnostics)
    if type(state) ~= "table" then
        return nil
    end

    local copy = {}
    copyFields(copy, state, CORE_STATE_FIELDS)
    if includeDiagnostics == true then
        copyFields(copy, state, DIAGNOSTIC_STATE_FIELDS)
    end
    return copy
end

function Snapshot.getStateFields(includeDiagnostics)
    local copy = {}
    for _, field in ipairs(CORE_STATE_FIELDS) do
        copy[#copy + 1] = field
    end
    if includeDiagnostics == true then
        for _, field in ipairs(DIAGNOSTIC_STATE_FIELDS) do
            copy[#copy + 1] = field
        end
    end
    return copy
end

return Snapshot
