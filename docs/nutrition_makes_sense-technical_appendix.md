# Nutrition Makes Sense - Technical Appendix

Current for NMS 2.0 development and Project Zomboid Build 42.20.

## Ownership

NMS 2.0 steers vanilla nutrition instead of running a parallel metabolism.

- Vanilla owns every value: hunger, calories, carbohydrates/lipids/proteins, weight, and the Food Eaten ("Well Fed") timer `BodyDamage.healthFromFoodTimer`.
- Vanilla item scripts own food instances, partial consumption, recipe mutation, and normal eat/drink behavior.
- The authored CSV is the source for NMS food balancing; the builder emits vanilla script overrides.
- NMS reads vanilla each tick, runs the pure model (`shared/NutritionMakesSense_Model.lua`), and writes corrections back. This happens only on the authority: the dedicated server in MP, the local player in SP (`shared/NutritionMakesSense_Runtime.lua`).
- MP clients never write nutrition values. Vanilla's `PlayerStats` packet already replicates Stats, Nutrition, and the Food Eaten timer every second.

NMS persists only `{version = 2, malnutrition, trendKgPerWeek}` under the `NutritionMakesSense2` player modData key. Everything else is re-read from vanilla.

## Intake

Intake is the positive delta of vanilla's calorie counter between ticks (plus the vanilla burn estimate for that tick). Fat and protein deltas give the meal's composition.

`HungerChange` is never an intake or volume signal. On an item it is both the remaining reservoir (it drives the Eat Half/Quarter gates, evolved-recipe ingredient use, and tooltips) and the per-bite hunger drop. NMS never scales the table's `HungerChange`. It scales the hunger drop vanilla actually applied, keeping `HUNGER_DROP_SCALE = 0.7`, but only in a tick where intake was also detected. This is the structural lever for meals per day. Without it, meals per day ≈ daily burn ÷ kcal per meal, and kcal per meal is capped by how much hunger a food removes.

On the authority, `ISEatFoodAction:complete` forces an immediate tick. On a dedicated server it also calls `syncPlayerStats`, so the scaled drop reaches the client without a visible bounce.

## Energy

- Burn: `75 + 48 × (MET − 1)` kcal/h awake and `35` kcal/h asleep. Multipliers: body weight (±10%), Fast/Slow Metabolism (1.04/0.96), and the `EnergyBurnMultiplier` sandbox option. NMS reverts vanilla's own burn every tick.
- Vanilla calories are the energy reserve. The set point is 800 kcal; the band is 300–1300.
  - Above the band, the surplus is stored as fat at `(C − 1300)/12` per hour.
  - Below the band, fat is released at `(300 − C)/8` per hour, capped at 75 kcal/h. The cap shrinks linearly to 0 between 75 kg and 45 kg: lean bodies cannot keep up.
  - Energy converts at 7700 kcal/kg. Fast/Slow Metabolism scales gain (0.90/1.12) and loss (1.12/0.90).
- NMS reverts vanilla weight drift. A single change larger than 0.2 kg is accepted as external (admin edit, another mod). NMS calls `applyTraitFromWeight` whenever weight moves by 0.05 kg or is edited externally.
- Workload (MET) comes from `shared/NutritionMakesSense_Workload.lua`. Sources, in order: timed-action `caloriesModifier`, the thermoregulator metabolic rate, then a movement fallback. In MP the client reports its sample (on change, 5 s keepalive). The server uses a report if it is under 15 s old.

## Stomach (Well Fed)

The vanilla Food Eaten timer is re-clocked as a stomach:

- Each meal adds `kcal/250 × q` hours at 1000 units per game hour, capped at 5000. Composition sets `q = clamp(0.75 + 0.6 × proteinShare + 0.35 × fatShare, 0.75, 1.3)`.
- The timer drains in game time. Vanilla's moodle bands therefore read as "hours of fullness left": Satiated above 0, Well Fed above 1600, Stuffed above 3200 (which blocks eating), Full to Bursting above 4800.
- Timer increases without intake (other mods) are kept. Vanilla's raw-dangerous-food reset is not honored.
- Well Fed healing: `healthFromFood = 0.001 × (1 − malnutrition)`, against vanilla's 0.015. Being fed helps you recover a little; it no longer regenerates like a potion.

## Hunger

NMS owns passive hunger rise:

`0.07/h × (1 − H)² × appetite(C) × clamp(1 − timer/1600, 0, 1) × sleep 0.15 × trait × sandbox`

- `appetite(C)` runs from 2.2 (depleted) through 1.0 at the set point to 0.4 (large surplus).
- Traits: Hearty Appetite 1.5, Light Eater 0.75.
- Sandbox: the NMS `AppetiteRateMultiplier` times vanilla Stats Decrease (2.0/1.6/1.0/0.8/0.65).
- A full stomach holds hunger back, and hunger returns gradually as the stomach empties.
- Hunger rises larger than vanilla could produce are accepted as external.

## Malnutrition

- Calorie target: `clamp(−C/1500, 0, 1)`, which starts once the reserve goes negative.
- Protein target: `clamp((−300 − P)/200, 0, 1) × 0.5`, using the vanilla protein counter P (vanilla decays it by about 74 g/day).
- Combined: `1 − (1 − calorie)(1 − protein)`.
- Malnutrition moves toward the target over 48 h when rising and 36 h when recovering.
- Effects start at 0.15 and scale to full at 1.0:
  - Endurance regeneration down to ×0.55.
  - Extra endurance drain up to 0.012/h under activity.
  - Natural HP recovery (standard, reduced and severely reduced additions) down to ×0.5. This uses baseline capture: a field another mod changes is left alone.
- With ArmorMakesSense coordinating endurance (`mscompat-v1` `endurance_coordinator`), NMS stops controlling endurance itself. It contributes through the `endurance_provider` callbacks instead (`shared/NutritionMakesSense_EnduranceCompat.lua`).
- Melee damage is not modified directly. Vanilla computes melee damage entirely in Java from Strength, weight traits, pain and moodles, and exposes no Lua-settable scalar. Malnutrition reaches combat through vanilla's own paths: endurance moodles (×0.5 to ×0.05 damage) and the weight traits that sustained loss produces (Underweight ×0.8, Very Underweight ×0.6).

## Lifecycle

- The authority tick runs from `OnPlayerUpdate`, throttled to 0.25 s real time per player. Long ticks are split into 0.1 game-hour steps.
- An elapsed time of 2 game hours or more, or a negative one (load, reconnect, clock change), re-seeds from current vanilla values without catch-up.
- Migration from 1.x: if the old `NutritionMakesSenseState` key exists, NMS seeds the vanilla counters once and then deletes the key.
  - Calories come from old fuel, mapped piecewise into the reserve band.
  - Weight is kept.
  - Protein: P = `clamp((adequacyDays − 2)/2 × 300, −500, 300)`.
  - Carbohydrates and lipids are zeroed.
  - Malnutrition = old deprivation.

## Multiplayer

- Client → server: `reportWorkload {met, asleep, source}` and `requestSnapshot`.
- Server → client: `displaySnapshot {malnutrition, target, calorie/protein targets, trend, burn, hunger rate}`. It is sent on meaningful change at most every 2 s, with a 10 s keepalive. The client applies the matching body tuning locally.
- Every other UI value (calories, protein, hunger, stomach, weight) is read straight from vanilla on the client.

## Presentation

Display mode (client mod option "Nutrition display", default Immersive). Both modes use the same screens and data; only precision changes. Characters with the Nutritionist trait always get Detailed. Immersive:

- replaces amounts, percentages and clock times with short phrases: "Full for a few hours", "Hungry by this evening", "Clears in about a day", "Losing weight";
- drops gauge notches, the kcal/h burn line and the malnourishment percent (the level word stays);
- words effects as felt ("Tiring faster  Healing slower");
- rounds tooltip pips to whole pips, capped at five with no overflow "+". A trace amount (at least a quarter pip) still shows one pip. Debug tooltips keep full precision.

Colours, bars, verdicts, causes, remedies and weight in kg stay in both modes. Wording helpers are `UIHelpers.isDetailed`, `duration`, `when` and `effectsText`.

All surfaces share one drawing kit (`client/ui/NutritionMakesSense_Draw.lua`): palette, pips, gauges, trend chevrons (vanilla `Moodle_chevron_*` textures), durations and clock times. Good/bad colours come from `getCore():getGood/BadHighlitedColor()`, so they follow the colour-blind option. Text is ASCII only; arrows are textures.

- Food tooltips: three pip rows under vanilla's block, aligned to vanilla's value column. Five pips each, quarter-pip resolution, `+` on overflow.
  - Satiety: 1 pip = 1 h of `Model.fillHours` (the Well Fed timer unit). Skipped for inedible items.
  - Energy: 1 pip = `Model.FILL_KCAL_PER_HOUR` (250 kcal).
  - Protein: 1 pip = 10 g.
  - Exact numbers only in debug mode with the debug-tooltip option on.
- Nutrition window (`NutritionMakesSense_NutritionWindow.lua`, `ISCollapsableWindow`, opened from the health panel "Nutrition" button, position saved as `nms_nutrition`):
  - a one-line verdict, priority-ordered: wasting (with cause), empty reserve, very hungry, hungry, protein, recovering, stuffed, well fed, fine;
  - Stomach: five hour-cells matching tooltip satiety pips, "Full for ~X", "Healing faster" when hurt;
  - Hunger: gauge notched at 15/25/45/70 %, forecast "Hungry around 14:30" from `Model.forecast`;
  - Energy: -1500..2200 gauge with the 300..1300 comfort band, burn kcal/h, "Low around..." / storing / drawing on fat;
  - Protein: gauge notched at -300/-100, days left from `Model.proteinDaysLeft`, food sources when low;
  - Malnourishment: %, level, direction chevron, ghost bar for the target, cause, effects, "Clears in ~X" from `Model.malnutritionHoursTo`;
  - Weight: trait-band gauge (50/65/75/85/100 kg), trend, "Underweight in ~X" from `Model.weightTraitWeeks`;
  - the "?" button opens rich-text help (`UI_NMS_Help`).
  - Forecasts re-run at most once a second (48 h horizon, 0.25 h steps, no further eating, current MET).
- Health panel lines: "Malnourishment: 34%" with a direction chevron and the cause; one line of stamina/healing penalties; a protein warning; "Well Fed: Healing faster" while the stomach timer runs and HP is below full.
- The Malnourished moodle levels are 0.10 / 0.30 / 0.60 / 0.85; the description names the cause and whether it is worsening or recovering.

## Dev surface (dev build only)

`client/dev`, `server/dev` and `shared/dev` deploy only with the `*Dev` build. The workshop build strips them and release Lua must never reference them (`tests/test_source_shape.sh`). They self-install through Events.

- `shared/dev/NutritionMakesSense_DevTools.lua`: `inspect(player)` (plain-table authority state) and `apply(player, op, value)` for `calories`, `proteins`, `malnutrition`, `stomach` (hours), `hunger`, `weightDelta`, `reset`, `spawn`. Every edit calls `Runtime.forget` so the next tick re-seeds instead of reading the edit as intake.
- `server/dev/NutritionMakesSense_DevServer.lua`: net module `NutritionMakesSenseDev`; runs `devTool` commands and pushes `devState` to each player every second.
- `client/dev/NutritionMakesSense_DevHud.lua`:
  - load check about 8 s after spawn: a green halo "NMS dev: N checks OK" or red halos naming failures, plus `[DEV] load check` console lines. It checks the runtime, ticking, eat hook, display data, v2 save (notes a 1.x migration), legacy key gone, well-fed healing value, stomach cap, sandbox Nutrition (warn only), and fresh server data in MP;
  - meal log: diffs the runtime's cumulative intake totals, halos each meal ("Ate 420 kcal: stomach +1.6 h, hunger -12% (vanilla -17%)"), and flags a hunger-drop ratio away from 0.7 or a stomach over cap;
  - 24 h history sampled every 0.1 game hour;
  - a draggable top-centre chip (green/red edge) with live hunger, stomach, kcal, protein and M. Click opens the dev panel.
- `client/dev/NutritionMakesSense_DevPanel.lua`: check pills, input and model columns, sparklines (hunger, stomach, energy with band, malnourishment) with meal ticks, the last six meals, and tool buttons.

## Validation

- `tests/run_tests.sh`: model contracts plus multi-day balance gates (`tests/test_model.lua` via `tests/sim.lua`), a runtime integration test against fake vanilla objects (`tests/test_runtime.lua`), settings, tooltips, a UI render smoke over every surface and the dev tools (`tests/test_ui_smoke.lua`), recipe callbacks and source shape.
- Balance targets at defaults (rest/work/sleep day, about 2250 kcal):
  - normal meals: 2–3.5 meals a day with stable weight;
  - low-energy food loses weight; energy-dense food gains it;
  - protein-poor diets build malnutrition over weeks;
  - a long fast severely malnourishes.

## Food Data Pipeline

1. Edit `docs/nms/authoring/nms_authored_food_table_curated.csv`.
2. Run `tools/nutrition_makes_sense/build_script_food_overrides.py`.
3. Validate representative routing and recipe-reservoir classification with `tools/nutrition_makes_sense/validate_closed_container_routing.py`.
4. Deploy through `tools/mod_sync/sync_local_mod.sh --mod nutrition`.

Do not hand-edit `NutritionMakesSense_food_overrides.txt`; it is generated output.

## Recipe and reservoir contracts

Recipe overlays change only `OnCreate`. The B42 loader appends repeated input/output declarations; a full copy of a recipe is not a replacement and can fail with duplicate props. Homogeneous cuts normalize total calories/macros against the consumed food; poultry calls vanilla cutting before normalization. Native fish and small-animal callbacks remain untouched.

Foods without a vanilla `HungerChange` reservoir stay vanilla. Adding one changes whole-item crafting consumption into partial consumption, enabling repeated head processing or frozen-bag unpacking. Curation excludes these definitions and the builder rejects stale classifications.

The observed-nutrition intake contract retains a vanilla limitation: a single consumption exceeding the engine's 3,700 kcal counter ceiling can be clipped before NMS sees it. No speculative compensation is applied.

`python3 tests/test_recipe_overrides.py --engine` additionally compiles a small reflection probe and uses the installed game's actual recipe loader and vanilla timed-action definitions. It checks that all seven overlays retain original input/output objects, resolve their callbacks, and finalize. Set `PZ_INSTALL` and `PZ_JAVA` to run against another installation. This is separate from the portable Lua suite and does not claim a running client/server smoke test.
