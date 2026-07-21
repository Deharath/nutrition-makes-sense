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
assert_absent 'getImmediateHungerDrop|applyImmediateFullnessCorrection|vanilla-hunger-fallback|HUNGER_FALLBACK' 'calorie-modeled immediate fullness'
assert_absent 'getFatigueAccelFactor|fatigue_provider|computeFatigueContribution' 'NMS fatigue acceleration'
assert_absent 'CARB_PROFILE|getCarbProfileSatietyMultiplier|carbProfile' 'unobservable carb-profile satiety branch'
assert_absent 'projectedState|getProjectedStateCopy|buildProjectedTarget|updateProjectedState' 'unused MP prediction state'
assert_absent 'duplicate_deposit_detected' 'asynchronous per-item calorie comparison'
assert_absent 'setTimedActionInstantCheat|timed_action_instant_unavailable' 'capability-gated runner cheat'
assert_absent 'isHungerSignalReady' 'backend hunger signal trigger'

if ! rg -n 'shouldRunAuthoritativeUpdates\(\)' "${LUA_ROOT}/shared/runtime/NutritionMakesSense_MetabolismRuntime_Sync.lua" >/dev/null; then
  echo "client shell can write authority-owned nutrition effects" >&2
  exit 1
fi

if ! rg -n 'rememberSnapshotState\(playerObj, snapshot\)' "${LUA_ROOT}/server/NutritionMakesSense_MPServerRuntime_Vanilla.lua" >/dev/null; then
  echo "server snapshot cadence is not tracking its full comparison state" >&2
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

echo "nms source-shape checks passed"
