#!/usr/bin/env python3

from pathlib import Path
import re
import os
import sys
import tempfile
import subprocess


ROOT = Path(__file__).resolve().parents[1]
RECIPE_OVERRIDES = (
    ROOT / "common/media/scripts/NutritionMakesSense_recipe_overrides.txt"
)


def extract_block(text: str, declaration: str) -> str:
    match = re.search(rf"(?m)^\s*{re.escape(declaration)}\s*$", text)
    if match is None:
        raise AssertionError(f"missing {declaration}")

    brace_start = text.find("{", match.end())
    if brace_start < 0:
        raise AssertionError(f"missing opening brace for {declaration}")

    depth = 0
    for index in range(brace_start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[match.start() : index + 1]
    raise AssertionError(f"missing closing brace for {declaration}")


def main() -> None:
    text = RECIPE_OVERRIDES.read_text(encoding="utf-8")
    names = re.findall(r"craftRecipe\s+(\w+)", text)
    assert set(names) == {"SmashPumpkin", "SmashWatermelon", "MakeSquidCalamari",
                          "GetBaconBits", "GetBaconRashers", "CutChicken", "CutTurkey"}
    for name in names:
        block = extract_block(text, f"craftRecipe {name}")
        assert "inputs" not in block and "outputs" not in block, name
        assert block.count("OnCreate =") == 1, name
    print("NMS scalar recipe overlay contract passed")

    if "--engine" in sys.argv:
        install = Path(os.environ.get("PZ_INSTALL", "/mnt/c/SteamLibrary/steamapps/common/ProjectZomboid"))
        java = os.environ.get("PZ_JAVA", "/home/deharath/pzserver42/jre64/bin/java")
        vanilla = (install / "media/scripts/generated/recipes/recipes_cooking.txt").read_text()
        with tempfile.TemporaryDirectory(prefix="nms-engine-") as temp:
            for name in names:
                Path(temp, name + ".vanilla").write_text(extract_block(vanilla, f"craftRecipe {name}"))
                Path(temp, name + ".overlay").write_text(extract_block(text, f"craftRecipe {name}"))
            actions = set(re.findall(r"timedAction\s*=\s*(\w+)",
                                     "".join(Path(temp, n + ".vanilla").read_text() for n in names)))
            for path in (install / "media/scripts").rglob("*.txt"):
                content = path.read_text(encoding="utf-8-sig", errors="replace")
                for action in list(actions):
                    if re.search(rf"(?m)^\s*timedAction {action}\s*$", content):
                        Path(temp, action + ".action").write_text(extract_block(content, f"timedAction {action}"))
                        actions.remove(action)
                if not actions:
                    break
            assert not actions, f"missing vanilla actions: {actions}"
            subprocess.run(["javac", "-d", temp, str(ROOT / "tests/engine/NutritionContracts.java")], check=True)
            subprocess.run([java, "-cp", os.pathsep.join([temp, str(install / "projectzomboid.jar")]),
                            "NutritionContracts", temp, ",".join(names)], check=True)


if __name__ == "__main__":
    main()
