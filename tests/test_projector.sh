#!/usr/bin/env bash
set -euo pipefail

MOD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="$(cd "${MOD_ROOT}/.." && pwd)"
PROJECTOR="tools/nutrition_makes_sense/project_scenario_trends.lua"

output="$(cd "${WORKSPACE_ROOT}" && lua "${PROJECTOR}" canonical_day --days 1 --no-daily)"

grep -q '^SCENARIO canonical_day' <<<"${output}"
grep -q 'foodSource=script_overrides' <<<"${output}"
grep -q 'avgDepleted=' <<<"${output}"
grep -q 'proteinDays=' <<<"${output}"
grep -q 'endStrengthXP=' <<<"${output}"

food_value="$(cd "${WORKSPACE_ROOT}" && lua "${PROJECTOR}" --food-value Base.Apple)"
grep -q '^FOOD Base.Apple hunger=-0.160 kcal=95.0 ' <<<"${food_value}"
grep -q 'source=script_overrides$' <<<"${food_value}"

absolute_output="$(cd /tmp && lua "${WORKSPACE_ROOT}/${PROJECTOR}" junk_food_day --days 1 --no-daily)"
grep -q '^SCENARIO junk_food_day' <<<"${absolute_output}"

echo "nms scenario projector smoke test passed"
