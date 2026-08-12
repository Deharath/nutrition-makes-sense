NutritionMakesSense = NutritionMakesSense or {}

local Snapshot = NutritionMakesSense.MPSnapshot or {}
NutritionMakesSense.MPSnapshot = Snapshot

local CORE_STATE_FIELDS = {
    "version",
    "fuel",
    "proteins",
    "weightKg",
    "weightController",
    "weightBalanceKcal",
    "deprivation",
    "visibleHunger",
    "satietyBuffer",
    "lastZone",
    "lastWeightTrait",
    "lastWeightRateKgPerWeek",
    "lastHungerBand",
    "lastDeprivationTarget",
    "depositSequence",
}

local DIAGNOSTIC_STATE_FIELDS = {
    "lastMetAverage",
    "lastMetPeak",
    "lastWorkTier",
    "lastMetSource",
    "lastObservedHours",
    "lastHeavyHours",
    "lastVeryHeavyHours",
    "lastBurnKcal",
    "lastDepositKcal",
    "totalIntakeKcal",
    "totalBurnKcal",
    "totalVisibleHungerGain",
    "totalObservedHours",
    "totalSleepHours",
    "lastFuelPressureFactor",
    "lastHungerRateMultiplier",
    "lastStatsDecreaseMultiplier",
    "lastAppetiteRateMultiplier",
    "lastEnergyBurnMultiplier",
    "lastGateMultiplier",
    "lastMetHungerFactor",
    "lastEnergyAppetiteProgress",
    "lastEnergyAppetiteRatePerHour",
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
    "lastMealModeledDrop",
    "lastMealDepositKcal",
    "lastMealTransactionFragments",
    "lastMealMechanicalDrop",
    "lastMealPhysicalDrop",
    "lastMealNutrientDrop",
    "lastMealPreHunger",
    "lastMealTargetHunger",
    "lastSyncedHunger",
    "lastTraceReason",
}
Snapshot.DIAGNOSTIC_STATE_FIELDS = DIAGNOSTIC_STATE_FIELDS

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

return Snapshot
