#!/usr/bin/env bash
set -euo pipefail

MOD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="$(cd "${MOD_ROOT}/.." && pwd)"
SOAK="tools/nutrition_makes_sense/run_closed_loop_soak.lua"

output="$(cd "${WORKSPACE_ROOT}" && lua "${SOAK}" --quick --strict)"

grep -q '^SOAK PASS ' <<<"${output}"
grep -q 'cases=36 core=36 edge=0 agentDays=180 daysPerCase=5 coreFailures=0' <<<"${output}"
grep -q 'coreRatio=' <<<"${output}"
grep -q 'allRatio=' <<<"${output}"
grep -q 'coreMaxHiddenStreak=' <<<"${output}"
grep -q 'coreMaxDeprivation=' <<<"${output}"

echo "nms closed-loop soak smoke test passed"
