#!/usr/bin/env python3
"""Characterization checks for the workspace NMS recording inspector."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


MOD_ROOT = Path(__file__).resolve().parents[1]
INSPECTOR_PATH = MOD_ROOT.parent / "tools" / "nutrition_makes_sense" / "inspect_recording.py"
SPEC = importlib.util.spec_from_file_location("nms_inspect_recording", INSPECTOR_PATH)
assert SPEC is not None and SPEC.loader is not None
INSPECTOR = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = INSPECTOR
SPEC.loader.exec_module(INSPECTOR)


fieldnames = [
    "row_kind",
    "elapsed_min",
    "visible_hunger",
    "nms_fuel",
    "nms_deposit_kcal",
    "event_reason",
    "event_item",
    "event_kcal",
    "event_mechanical_hunger_drop",
    "event_physical_hunger_drop",
    "event_nutrient_hunger_drop",
    "event_modeled_hunger_drop",
    "event_applied_hunger_drop",
    "event_hunger_correction",
]

rows = [
    {
        "row_kind": "food_action",
        "elapsed_min": "10",
        "visible_hunger": "0.18",
        "nms_fuel": "500",
        "nms_deposit_kcal": "100",
        "event_reason": "eat-action-complete",
        "event_item": "Base.TestFood",
        "event_kcal": "",
        "event_mechanical_hunger_drop": "0.20",
        "event_physical_hunger_drop": "0.12",
        "event_nutrient_hunger_drop": "0.10",
        "event_modeled_hunger_drop": "0.12",
        "event_applied_hunger_drop": "0.12",
        "event_hunger_correction": "-0.08",
    },
    {
        "row_kind": "consume",
        "elapsed_min": "10.1",
        "visible_hunger": "0.18",
        "nms_fuel": "700",
        "nms_deposit_kcal": "200",
        "event_reason": "player-update-fastpath",
        "event_item": "Base.TestFood",
        "event_kcal": "200",
        "event_mechanical_hunger_drop": "0.20",
        "event_physical_hunger_drop": "0.12",
        "event_nutrient_hunger_drop": "0.10",
        "event_modeled_hunger_drop": "0.12",
        "event_applied_hunger_drop": "0.12",
        "event_hunger_correction": "-0.08",
    },
]

recording = INSPECTOR.RecordingData(
    path=Path("synthetic_recording.txt"),
    fieldnames=fieldnames,
    rows=rows,
)
analysis = INSPECTOR.analyze_recording(recording)

assert len(analysis.events) == 2
assert analysis.events[0].deposit_kcal is None, "food_action must not repeat the previous deposit"
assert analysis.events[1].deposit_kcal == 200
assert analysis.total_kcal == 200
assert analysis.total_deposit_kcal == 200
assert analysis.events[1].hunger_drop == 0.12
assert analysis.events[1].hunger_mechanical == 0.20
assert analysis.events[1].hunger_physical == 0.12
assert analysis.events[1].hunger_nutrient == 0.10
assert analysis.events[1].hunger_modeled == 0.12
assert analysis.events[1].hunger_correction == -0.08
assert not analysis.issues

mp_fieldnames = [
    "row_kind",
    "elapsed_min",
    "visible_hunger",
    "local_hunger",
    "nms_fuel",
    "event_reason",
    "event_kcal",
    "nms_deposit_kcal",
    "mp_snapshot_seq",
    "mp_authoritative_hunger",
    "mp_display_hunger_target",
    "mp_prediction_active",
    "mp_prediction_age_seconds",
    "mp_prediction_resolution",
]
mp_rows = [
    {
        "row_kind": "mp_snapshot",
        "elapsed_min": "1",
        "visible_hunger": "0.10",
        "local_hunger": "0.10",
        "nms_fuel": "900",
        "event_reason": "",
        "event_kcal": "",
        "nms_deposit_kcal": "",
        "mp_snapshot_seq": "10",
        "mp_authoritative_hunger": "0.26",
        "mp_display_hunger_target": "0.10",
        "mp_prediction_active": "true",
        "mp_prediction_age_seconds": "0.2",
        "mp_prediction_resolution": "holding-premeal-snapshot",
    },
    {
        "row_kind": "mp_snapshot",
        "elapsed_min": "1.1",
        "visible_hunger": "0.115",
        "local_hunger": "0.115",
        "nms_fuel": "980",
        "event_reason": "",
        "event_kcal": "",
        "nms_deposit_kcal": "",
        "mp_snapshot_seq": "11",
        "mp_authoritative_hunger": "0.115",
        "mp_display_hunger_target": "0.115",
        "mp_prediction_active": "false",
        "mp_prediction_age_seconds": "",
        "mp_prediction_resolution": "server-confirmed",
    },
]
mp_recording = INSPECTOR.RecordingData(
    path=Path("synthetic_mp_recording.txt"),
    fieldnames=mp_fieldnames,
    rows=mp_rows,
)
mp_analysis = INSPECTOR.analyze_recording(mp_recording)
assert not mp_analysis.issues, mp_analysis.issues

bad_mp_rows = [dict(row) for row in mp_rows]
bad_mp_rows[1]["mp_snapshot_seq"] = "10"
bad_mp_rows[1]["mp_display_hunger_target"] = "0.10"
bad_mp_rows[1]["local_hunger"] = "0.14"
bad_mp_recording = INSPECTOR.RecordingData(
    path=Path("synthetic_bad_mp_recording.txt"),
    fieldnames=mp_fieldnames,
    rows=bad_mp_rows,
)
bad_mp_analysis = INSPECTOR.analyze_recording(bad_mp_recording)
assert any("sequence did not increase" in issue for issue in bad_mp_analysis.issues)
assert any("without an active meal prediction" in issue for issue in bad_mp_analysis.issues)
assert any("escaped the MP display anchor" in issue for issue in bad_mp_analysis.issues)

print("nms recording inspector characterization passed")
