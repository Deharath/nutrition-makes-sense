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

# 2.0 steers vanilla state; the 1.x parallel metabolism must not come back.
assert_absent 'NutritionMakesSense\.Metabolism\b|MetabolismRuntime|MPSnapshot' '1.x parallel metabolism'
assert_absent 'visibleHunger|VISIBLE_HUNGER|satietyBuffer|depositSequence|mp-display-anchor' '1.x hunger shell and meal reconciliation'
assert_absent 'suppressFoodEatenTimer' '1.x Well Fed suppression'
if rg -n 'getHungerChange|getHungChange' "${LUA_ROOT}/shared/NutritionMakesSense_Runtime.lua" "${LUA_ROOT}/shared/NutritionMakesSense_Model.lua"; then
  echo "runtime must read intake from vanilla counters, never item HungerChange" >&2
  exit 1
fi
assert_absent '\\.csv"' 'B42.20-blocked runtime CSV output extension'

for dir in client/bootstrap client/hooks shared/runtime; do
  if [[ -e "${LUA_ROOT}/${dir}" ]]; then
    echo "retired NMS directory remains: ${dir}" >&2
    exit 1
  fi
done

# Dev dirs ship only in the dev build; release code must not depend on them.
if rg -n 'require "dev/|NutritionMakesSense\.Dev(Tools|Hud|Panel)\b' "${LUA_ROOT}" -g '*.lua' -g '!**/dev/**'; then
  echo "release Lua references dev-only modules" >&2
  exit 1
fi

if ! rg -n 'Runtime\.isAuthority\(\)' "${LUA_ROOT}/shared/NutritionMakesSense_Runtime.lua" >/dev/null; then
  echo "runtime writes are not gated by authority" >&2
  exit 1
fi

if rg -n 'setCalories|setWeight|setHealthFromFoodTimer|CharacterStat\.HUNGER' "${LUA_ROOT}/client" -g '*.lua'; then
  echo "client code writes authority-owned nutrition values" >&2
  exit 1
fi

echo "nms source-shape checks passed"
