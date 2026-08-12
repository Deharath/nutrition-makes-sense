#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_ROOT="${ROOT_DIR}/common/media/lua"

assert_absent() {
  local pattern="$1"
  local label="$2"
  if rg -n "${pattern}" "${LUA_ROOT}" -g '*.lua'; then
    echo "retired NMS source remains: ${label}" >&2
    exit 1
  fi
}

assert_absent 'enqueuePendingNutritionSuppression|consumePendingNutritionSuppressions|server-explicit-consume' 'explicit consume suppression queue'
assert_absent 'getExertionPenaltyMultiplier|DEPRIVATION_ENDURANCE_MAX' 'diagnostic-only exertion multiplier'
assert_absent 'getImmediateHungerDrop|applyImmediateFullnessCorrection|vanilla-hunger-fallback|HUNGER_FALLBACK' 'retired immediate-fullness authority stack'
assert_absent 'getFatigueAccelFactor|fatigue_provider|computeFatigueContribution' 'NMS fatigue acceleration'
assert_absent 'CARB_PROFILE|getCarbProfileSatietyMultiplier|carbProfile' 'unobservable carb-profile satiety branch'
assert_absent 'projectedState|getProjectedStateCopy|buildProjectedTarget|updateProjectedState' 'unused MP prediction state'
assert_absent 'duplicate_deposit_detected' 'asynchronous per-item calorie comparison'
assert_absent 'setTimedActionInstantCheat|timed_action_instant_unavailable' 'capability-gated runner cheat'
assert_absent 'isHungerSignalReady' 'backend hunger signal trigger'
assert_absent 'getUnderfeedingDebtBurnFactor|getUnderfeedingDebtProgress|advanceUnderfeedingDebtKcal' 'retired low-fuel deprivation ledger'
assert_absent 'pendingBurnKcal' 'duplicate runtime calorie accumulator'
assert_absent 'getSatietyDescriptorFromValues|getStaticFoodValueSource|getStateFields|Runtime\.getStateKey|Runtime\.getCompat|CoreUtils\.clamp01|noteSeedEvent' 'dead public helper surface'
assert_absent 'migrateAuthoritativeWeightFields|STATE_MIGRATION' 'redundant weight migration path'
assert_absent 'lastEffectiveEnduranceMet|lastCorrectionGain|lastBaseHungerGain|lastWeightBalanceKcal|lastWeightControllerTarget|lastMealHungerObserved|lastMealHungerCorrection' 'stored values that are unused or derivable at the diagnostic boundary'
assert_absent 'lastActiveElapsedHours|lastRawElapsedHours|lastElapsedMode' 'write-only elapsed-time telemetry'
assert_absent 'removeEndurance' 'unreachable second endurance-drain authority path'
if rg -n 'state\.(lastMet|lastZone|lastHungerBand|lastWeightTrait|lastDeprivationTarget|total(Intake|Burn|Visible|Observed|Sleep)|pending(Meal|Observed|Resume))' \
    "${LUA_ROOT}/shared/NutritionMakesSense_Metabolism.lua"; then
  echo "durable metabolism state still owns transient telemetry" >&2
  exit 1
fi

if ! rg -n 'telemetryByState.*__mode = "k"' \
    "${LUA_ROOT}/shared/NutritionMakesSense_MetabolismRuntime.lua" >/dev/null; then
  echo "runtime telemetry is not isolated from serialized player state" >&2
  exit 1
fi
assert_absent '\\.csv"' 'B42.20-blocked runtime CSV output extension'

if ! rg -n 'shouldRunAuthoritativeUpdates\(\)' "${LUA_ROOT}/shared/runtime/NutritionMakesSense_MetabolismRuntime_Sync.lua" >/dev/null; then
  echo "client shell can write authority-owned nutrition effects" >&2
  exit 1
fi

if ! rg -n 'rememberSnapshotState\(playerObj, snapshot\)' "${LUA_ROOT}/server/NutritionMakesSense_MPServerRuntime_Vanilla.lua" >/dev/null; then
  echo "server snapshot cadence is not tracking its full comparison state" >&2
  exit 1
fi

if ! rg -U -n 'CORE_STATE_FIELDS[\s\S]*"depositSequence"' \
    "${LUA_ROOT}/shared/NutritionMakesSense_MPSnapshot.lua" >/dev/null; then
  echo "release MP snapshots cannot causally reconcile client meal predictions" >&2
  exit 1
fi

if ! rg -U -n 'snapshotChangedMeaningfully[\s\S]*previous\.depositSequence[\s\S]*state\.depositSequence' \
    "${LUA_ROOT}/server/NutritionMakesSense_MPServerRuntime_Vanilla.lua" >/dev/null; then
  echo "server snapshots do not promptly acknowledge meal deposits" >&2
  exit 1
fi

if ! rg -U -n 'getAppetiteRateMultiplier[\s\S]*getEnergyBurnMultiplier[\s\S]*Metabolism\.advanceState' \
    "${LUA_ROOT}/shared/runtime/NutritionMakesSense_MetabolismRuntime_Authority.lua" >/dev/null; then
  echo "NMS sandbox tuning is not wired into authoritative metabolism" >&2
  exit 1
fi

if rg -n 'addDebugOption' "${LUA_ROOT}/client/bootstrap/NutritionMakesSense_ClientBootstrap.lua"; then
  echo "NMS dev entries are still subject to vanilla's hide-debug-context-options preference" >&2
  exit 1
fi

if ! rg -n 'OnPreFillWorldObjectContextMenu' "${LUA_ROOT}/client/bootstrap/NutritionMakesSense_ClientBootstrap.lua" >/dev/null; then
  echo "NMS dev entries are not registered on the reliable world pre-fill event" >&2
  exit 1
fi

if ! rg -n 'DebugSupport\.canUseDevTools\(\)' "${LUA_ROOT}/client/bootstrap/NutritionMakesSense_ClientBootstrap.lua" >/dev/null; then
  echo "NMS dev surfaces are not gated by an active debug launch" >&2
  exit 1
fi

if ! rg -n 'function DebugSupport\.isDevBuild\(\)' "${LUA_ROOT}/shared/NutritionMakesSense_DebugSupport.lua" >/dev/null; then
  echo "NMS dev surfaces do not distinguish dev and Workshop builds" >&2
  exit 1
fi

if ! rg -n 'nms_weight_balance_kcal.*nms_weight_controller_target.*nms_deposit_sequence' \
    "${LUA_ROOT}/client/dev/NutritionMakesSense_DevPanel.lua" >/dev/null; then
  echo "NMS recording schema is missing weight-controller diagnostics" >&2
  exit 1
fi

if ! rg -n 'local_hunger.*auth_visible_hunger.*last_synced_hunger' \
    "${LUA_ROOT}/client/dev/NutritionMakesSense_DevPanel.lua" >/dev/null; then
  echo "NMS recording schema is missing split hunger telemetry" >&2
  exit 1
fi

if ! rg -U -n 'function Metabolism\.getMealFullness[\s\S]*math\.max\(nutrientDrop, physicalDrop\)' \
    "${LUA_ROOT}/shared/NutritionMakesSense_Metabolism.lua" >/dev/null; then
  echo "NMS meal fullness does not combine nutrition with a bounded physical hint" >&2
  exit 1
fi

if ! rg -U -n 'function Runtime\.accumulateMealObservation[\s\S]*transaction\.fragments' \
    "${LUA_ROOT}/shared/runtime/NutritionMakesSense_MetabolismRuntime_Authority.lua" >/dev/null; then
  echo "NMS authority does not aggregate fragmented meal deposits" >&2
  exit 1
fi

if ! rg -n 'nms_meal_mechanical_drop.*nms_meal_physical_drop.*nms_meal_nutrient_drop' \
    "${LUA_ROOT}/client/dev/NutritionMakesSense_DevPanel.lua" >/dev/null; then
  echo "NMS recording schema is missing meal-fullness source diagnostics" >&2
  exit 1
fi

if rg -n 'sendClientCommand' "${LUA_ROOT}/client/hooks/NutritionMakesSense_MealPrediction.lua"; then
  echo "NMS meal prediction has reintroduced an explicit consume RPC" >&2
  exit 1
fi

if ! rg -n 'run_intake_kcal.*run_burn_kcal.*run_net_kcal' \
    "${LUA_ROOT}/client/dev/NutritionMakesSense_DevPanel.lua" >/dev/null; then
  echo "NMS recording schema is missing exact run accounting" >&2
  exit 1
fi

if ! rg -n 'mp_snapshot_seq.*mp_snapshot_age_seconds.*mp_snapshot_stale' \
    "${LUA_ROOT}/client/dev/NutritionMakesSense_DevPanel.lua" >/dev/null; then
  echo "NMS recording schema is missing MP synchronization telemetry" >&2
  exit 1
fi

if ! rg -U -n 'getCharacterTraits[\s\S]*getKnownTraits' \
    "${LUA_ROOT}/client/dev/NutritionMakesSense_DevPanel.lua" >/dev/null; then
  echo "NMS recording metadata is not reading the active B42 trait list" >&2
  exit 1
fi

if ! rg -U -n 'function FoodDebug\.install\(\)[\s\S]*ISEatFoodAction\.complete' \
    "${LUA_ROOT}/client/dev/NutritionMakesSense_FoodDebug.lua" >/dev/null; then
  echo "NMS dev food telemetry does not observe completed vanilla eat actions" >&2
  exit 1
fi

if ! rg -U -n 'function FoodDebug\.install\(\)[\s\S]*ISDrinkFluidAction\.complete' \
    "${LUA_ROOT}/client/dev/NutritionMakesSense_FoodDebug.lua" >/dev/null; then
  echo "NMS dev food telemetry does not observe completed vanilla drink actions" >&2
  exit 1
fi

echo "nms source-shape checks passed"
