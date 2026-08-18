#!/usr/bin/env python3

from pathlib import Path
import re


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

    inherited_recipes = {
        "SliceFillet": (r"tags\[base:uncutfish\]", "item 2 Base.FishFillet,"),
        "SmashPumpkin": (r"\[Base\.Pumpkin\]", "item 5 Base.PumpkinSmashed,"),
        "SmashWatermelon": (
            r"\[Base\.Watermelon\]",
            "item 5 Base.WatermelonSmashed,",
        ),
        "MakeSquidCalamari": (r"\[Base\.Squid\]", "item 2 Base.SquidCalamari,"),
        "GetBaconBits": (r"\[Base\.BaconRashers\]", "item 4 Base.BaconBits,"),
        "GetBaconRashers": (r"\[Base\.Bacon\]", "item 4 Base.BaconRashers,"),
    }

    for name, (source_pattern, expected_output) in inherited_recipes.items():
        block = extract_block(text, f"craftRecipe {name}")
        source_input = re.search(
            rf"item\s+1\s+{source_pattern}[^\n]*flags\[([^]]+)\]",
            block,
        )
        assert source_input is not None, f"missing food input for {name}"
        flags = set(source_input.group(1).split(";"))
        assert "InheritFood" in flags, f"{name} does not inherit nutrition"
        assert expected_output in block, f"unexpected output shape for {name}"

    fish = extract_block(text, "craftRecipe SliceFillet")
    assert "OnCreate = RecipeCodeOnCreate.cutFish," in fish
    assert "OnTest = RecipeCodeOnTest.cutFish," in fish

    small_animal = extract_block(text, "craftRecipe ButcherSmallAnimal")
    assert "OnCreate = RecipeCodeOnCreate.cutSmallAnimal," in small_animal
    assert "InheritFood" in small_animal
    assert "item 1 mapper:animalType," in small_animal

    for name, source, outputs in (
        (
            "CutChicken",
            "Base.ChickenWhole",
            ("Base.Chicken", "Base.ChickenWings", "Base.ChickenFillet"),
        ),
        (
            "CutTurkey",
            "Base.TurkeyWhole",
            ("Base.TurkeyLegs", "Base.TurkeyWings", "Base.TurkeyFillet"),
        ),
    ):
        block = extract_block(text, f"craftRecipe {name}")
        assert "OnCreate = NutritionMakesSense_RecipeCodeOnCreate.cutPoultry," in block
        source_input = re.search(
            rf"item\s+1\s+\[{re.escape(source)}\]\s+flags\[([^]]+)\]",
            block,
        )
        assert source_input is not None, f"missing whole-bird input for {name}"
        flags = set(source_input.group(1).split(";"))
        assert "InheritFood" not in flags, f"{name} would duplicate nutrition per output type"
        for output in outputs:
            assert f"item 2 {output}," in block, f"missing {output} from {name}"

    print("NMS preparation-yield recipe override validation passed")


if __name__ == "__main__":
    main()
