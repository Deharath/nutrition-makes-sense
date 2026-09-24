#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LUA_PATH="${ROOT_DIR}/tests/?.lua;${ROOT_DIR}/common/media/lua/shared/?.lua;;"

lua "${ROOT_DIR}/tests/test_model.lua"
lua "${ROOT_DIR}/tests/test_runtime.lua"
lua "${ROOT_DIR}/tests/test_settings.lua"
lua "${ROOT_DIR}/tests/test_tooltip_logic.lua"
lua "${ROOT_DIR}/tests/test_tooltip_overlay.lua"
lua "${ROOT_DIR}/tests/test_recipe_code_on_create.lua"
lua "${ROOT_DIR}/tests/test_ui_smoke.lua"
python3 "${ROOT_DIR}/tests/test_recipe_overrides.py"
"${ROOT_DIR}/tests/test_source_shape.sh"

echo "all NMS characterization tests passed"
