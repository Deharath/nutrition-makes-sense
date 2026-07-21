#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LUA_PATH="${ROOT_DIR}/tests/?.lua;${ROOT_DIR}/common/media/lua/shared/?.lua;;"

lua "${ROOT_DIR}/tests/test_metabolism.lua"
lua "${ROOT_DIR}/tests/test_mp_snapshot.lua"
lua "${ROOT_DIR}/tests/test_tooltip_logic.lua"
lua "${ROOT_DIR}/tests/test_client_tooling.lua"
lua "${ROOT_DIR}/tests/test_client_bootstrap.lua"
lua "${ROOT_DIR}/tests/test_live_scenario_runner.lua"
lua "${ROOT_DIR}/tests/test_visible_hunger_bridge.lua"
lua "${ROOT_DIR}/tests/test_scenario_analysis.lua"
"${ROOT_DIR}/tests/test_projector.sh"
"${ROOT_DIR}/tests/test_source_shape.sh"

echo "all NMS characterization tests passed"
