#!/usr/bin/env bash
set -euo pipefail

MOD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="$(cd "${MOD_ROOT}/.." && pwd)"
PROJECTOR="tools/nutrition_makes_sense/project_scenario_trends.lua"

output="$(cd "${WORKSPACE_ROOT}" && lua "${PROJECTOR}" canonical_day --days 1 --no-daily)"

grep -q '^SCENARIO canonical_day' <<<"${output}"
grep -q 'foodSource=script_overrides' <<<"${output}"
grep -q 'avgDepleted=' <<<"${output}"
grep -q 'avgIntake=' <<<"${output}"
grep -q 'avgBurn=' <<<"${output}"
grep -q 'avgNet=' <<<"${output}"
grep -q 'avgMeals=' <<<"${output}"
grep -q 'proteinDays=' <<<"${output}"
grep -q 'endStrengthXP=' <<<"${output}"
grep -q 'appetiteRate=0.0500 appetiteFullKcal=800' <<<"${output}"

food_value="$(cd "${WORKSPACE_ROOT}" && lua "${PROJECTOR}" --food-value Base.Apple)"
grep -q '^FOOD Base.Apple hunger=-0.160 kcal=95.0 ' <<<"${food_value}"
grep -q 'source=script_overrides$' <<<"${food_value}"

absolute_output="$(cd /tmp && lua "${WORKSPACE_ROOT}/${PROJECTOR}" junk_food_day --days 1 --no-daily)"
grep -q '^SCENARIO junk_food_day' <<<"${absolute_output}"

tuned_output="$(cd "${WORKSPACE_ROOT}" && lua "${PROJECTOR}" canonical_day --mode cue_driven --days 1 --appetite-rate 0.045 --appetite-full-kcal 1200 --no-daily)"
grep -q 'appetiteRate=0.0450 appetiteFullKcal=1200' <<<"${tuned_output}"

recording_output="$(cd "${WORKSPACE_ROOT}" && lua "${PROJECTOR}" --recording "${MOD_ROOT}/tests/fixtures/nms_recording_replay_smoke.csv" --days 1 --no-daily)"
grep -q '^TRACE .*workloadSteps=1 foodPool=1 observedHours=1.000 observedBurn=100.0kcal' <<<"${recording_output}"
grep -q 'foodSource=recorded_consume_events' <<<"${recording_output}"
grep -q 'avgIntake=200.0kcal avgBurn=100.0kcal avgNet=+100.0kcal' <<<"${recording_output}"

event_output="$(cd "${WORKSPACE_ROOT}" && lua "${PROJECTOR}" --recording "${MOD_ROOT}/tests/fixtures/nms_recording_replay_smoke.csv" --days 1 --events --no-daily)"
grep -q '^EVENT day=01 hour=' <<<"${event_output}"

recorded_day_output="$(cd "${WORKSPACE_ROOT}" && lua "${PROJECTOR}" recorded_exploration_day --days 1 --mode style_repeat --sleep-hours 0 --no-daily)"
grep -q 'avgIntake=2470.0kcal avgBurn=3101.4kcal avgNet=-631.4kcal' <<<"${recorded_day_output}"
grep -q 'avgMeals=9.00 avgItems=9.00' <<<"${recorded_day_output}"

echo "nms scenario projector smoke test passed"
