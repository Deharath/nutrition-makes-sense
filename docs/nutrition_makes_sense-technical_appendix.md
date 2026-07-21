# Nutrition Makes Sense - Technical Appendix

Current for NMS `1.3.0` and Project Zomboid Build 42.

## Ownership

NMS uses a vanilla-first food model.

- Vanilla item scripts own food instances, partial consumption, recipe mutation, and normal eat/drink behavior.
- The authored CSV is the source for NMS food balancing.
- The builder emits vanilla script overrides to `common/media/scripts/NutritionMakesSense_food_overrides.txt`.
- NMS observes positive changes in vanilla calories and macros as its intake signal.
- NMS owns its metabolism state and writes hunger, weight, weight trends, and protein-dependent healing back to vanilla-facing fields.
- Multiplayer clients report workload; the server advances metabolism and returns authoritative state snapshots.

NMS does not own an item registry, item snapshots, stable-item patching, explicit consume RPCs, or consume reconciliation queues.

## Metabolism State

The durable model is defined in `common/media/lua/shared/NutritionMakesSense_Metabolism.lua`.

Primary state:

- `visibleHunger`: the hunger value presented through the vanilla stat and moodles
- `satietyBuffer`: meal-duration pressure that slows hunger return
- `fuel`: short-term usable energy, clamped to `0-2000`
- `underfeedingDebtKcal`: recent underfeeding accumulated while fuel is low
- `deprivation`: the smoothed performance consequence of sustained underfeeding
- `proteins`: several days of protein adequacy, scaled to body weight
- `weightBalanceKcal`: smoothed caloric imbalance used by the weight controller
- `weightController`: long-term direction and strength of weight change
- `weightKg`: authoritative body weight

Carbohydrate and fat values remain food inputs. They contribute to food composition and satiety calculations, but NMS does not maintain carbohydrate or fat reserves on the player.

## Gameplay Effects

### Hunger and satiety

Vanilla food hunger changes provide the immediate fullness signal. The authoritative runtime imports the hunger drop actually observed during eating. Calories and macros replenish energy and add meal-duration pressure, but they never manufacture or correct immediate fullness.

This boundary preserves vanilla recipe accounting. For multi-use ingredients such as flour, butter, pasta, and sugar, `HungerChange` also determines depletion fractions and the share of calories and macros transferred into prepared food. NMS therefore leaves those mechanics to vanilla and observes the completed eating outcome.

Passive hunger return depends on:

- current hunger band
- fuel pressure
- satiety buffer
- workload while awake
- sleep state
- Hearty Appetite or Light Eater satiety decay

NMS caps modeled hunger at `0.699`. This deliberately keeps its correction layer below vanilla's Starving health-drain threshold.

### Fuel and workload

Fuel burn uses MET-like workload sampled from the vanilla thermoregulator, timed actions, or movement fallbacks. Sleeping, resting, walking, running, sprinting, and heavy work produce progressively higher burn.

Slow Metabolism and Fast Metabolism slightly modify burn and weight response. Body weight also changes fuel burn within a bounded range.

### Deprivation

Low fuel accumulates underfeeding debt. Debt drives deprivation over a slower timescale than fuel.

Deprivation has two real effects:

- reduced positive endurance regeneration
- a small extra endurance drain during active exertion

There is no separate generic exertion multiplier or fatigue acceleration. Sleep pressure remains owned by vanilla and caffeine systems.

### Protein

Protein adequacy depletes over several days and is replenished by observed food protein.

- deficiency reduces food-based healing by up to 12 percent
- very low adequacy applies a Strength XP multiplier of `0.7`
- high adequacy applies a Strength XP multiplier of `1.5`
- the middle range leaves Strength XP unchanged

The XP adjustment is installed through the vanilla `Events.AddXP` event and guards its injected adjustment against recursive processing.

### Weight

Food deposits and metabolic burn feed a 72-hour caloric balance memory. That balance produces a target for the 24-hour weight controller. Weight then changes smoothly, with limits of roughly `+1.5 kg/week` and `-2.4 kg/week` before trait modifiers.

NMS writes weight and trend chevrons to vanilla Nutrition fields and calls vanilla weight-trait refresh only when those visible outputs change.

## Runtime

`NutritionMakesSense_MetabolismRuntime.lua` assembles the shared runtime from focused modules:

- `MetabolismRuntime_Authority`: intake observation, elapsed-time handling, state advancement, and debug mutation helpers
- `MetabolismRuntime_Workload`: local workload sampling, MP workload ingestion, and endurance control
- `MetabolismRuntime_Sync`: state snapshots and vanilla-facing hunger, weight, and authoritative healing output
- `MetabolismRuntime_Compat`: AMS endurance-coordinator contributions
- `MetabolismRuntime_XP`: protein-dependent Strength XP handling
- `MetabolismRuntime_Lifecycle`: event registration and update cadence

Local authoritative updates are limited to four per real second. Client shell maintenance uses the same maximum cadence.

Long multiplayer gaps are frozen rather than simulated as active play. Short runtime stalls are capped at 15 in-game minutes per update.

## Multiplayer

The MP contract has two client-to-server commands:

- `requestSnapshot`
- `reportWorkload`

The server replies with `stateSnapshot`.

Workload reports:

- are sent immediately for meaningful activity changes
- are limited to one report per 0.5 seconds
- use a 3-second idle keepalive
- carry a monotonic client sequence

State snapshots:

- are server-authoritative
- are limited to two change-driven sends per second
- use a 4-second idle keepalive
- carry a monotonic server sequence
- use the explicit field contract in `NutritionMakesSense_MPSnapshot.lua`
- carry only player-facing state in release builds
- add metabolism diagnostics only when server dev tools are enabled

The release contract carries fuel, protein, deprivation, weight, visible hunger, satiety, and the derived labels needed by player-facing UI. Dev servers extend that contract with diagnostic fields. Runtime-only telemetry and future state fields never enter packets automatically. Clients import the latest accepted snapshot directly; there is no second client metabolism projection, and clients do not write the server-owned protein-healing effect.

## Presentation

Player-facing modules:

- `NutritionMakesSense_TooltipOverlay.lua`: food tooltip integration
- `NutritionMakesSense_HealthPanelHook.lua`: health-panel warning and status-button integration
- `NutritionMakesSense_PlayerStatusPanel.lua`: exact fuel, hunger, satiety, and protein status
- `NutritionMakesSense_MalnourishedMoodle.lua`: deprivation warning moodle
- `NutritionMakesSense_WeightDisplayHook.lua`: weight trend presentation
- `NutritionMakesSense_ClientOptions.lua`: client options

The status panel is an intentional post-design addition. It exposes exact metabolism values and supersedes the original no-gauge visibility proposal.

## Development Tooling

Development panels and live scenario runners live under `common/media/lua/client/dev/`. The runtime inspector leads with the last intake's observed fullness, energy deposit, and meal staying power. Live scenario meal logs present the same three values together so low-calorie bulky meals and calorie-dense foods can be compared directly. Server and shared trace support live under their corresponding `dev/` directories.

Dev modules load only when PZ debug tools are enabled. Workshop builds exclude client, server, and shared development directories. Release servers ignore development trace commands.

The inventory food inspector also lives under `client/dev/`; the normal client bootstrap contains only dev-module discovery, hotkeys, and context-menu wiring.

The canonical offline check is:

```bash
./tests/run_tests.sh
```

The workspace compatibility command delegates to the same suite:

```bash
lua tools/nutrition_makes_sense/run_model_runtime_suite.lua
```

Offline characterization covers model boundaries, deprivation effects, protein XP thresholds, state invariants, the MP snapshot contract, debug access, per-player weight display state, and retired-source checks. In-game live scenario tools remain the authority for vanilla action integration and gameplay calibration.

The multi-day projector reads the generated shipping script overrides directly. It converts script-scale `HungerChange` values to the runtime `0..1` hunger scale and follows the same strict vanilla moodle boundaries as the live runner. Its reports distinguish time in the `Low` and `Depleted` fuel zones from time under an actual deprivation-driven endurance penalty, and include protein-adequacy, Strength XP, and healing trends. `--food-value Base.ItemName` prints the exact normalized input used for a projected food.

## Food Data Pipeline

1. Edit `docs/nms/authoring/nms_authored_food_table_curated.csv`.
2. Run `tools/nutrition_makes_sense/build_script_food_overrides.py`.
3. Validate representative routing and recipe-reservoir classification with `tools/nutrition_makes_sense/validate_closed_container_routing.py`.
4. Deploy through `tools/mod_sync/sync_local_mod.sh --mod nutrition`.

Do not hand-edit `NutritionMakesSense_food_overrides.txt`; it is generated output.
