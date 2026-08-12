# Nutrition Makes Sense - Technical Appendix

Current for NMS `1.3.3` development and Project Zomboid Build 42.

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
- `deprivation`: the slow performance consequence of deep, sustained negative energy balance
- `proteins`: several days of protein adequacy, scaled to body weight
- `weightBalanceKcal`: smoothed caloric imbalance used by appetite, deprivation, and the weight controller
- `weightController`: long-term direction and strength of weight change
- `weightKg`: authoritative body weight

The serialized table contains only gameplay state plus lifecycle anchors: the fields above, initialization/schema markers, `lastWorldHours`, the nutrition-deposit sequence, and the original food-healing baseline. Last-tick workload values, recorder totals, shell-sync references, meal-aggregation transactions, and resume bookkeeping live in a weak runtime sidecar keyed by the durable table. Runtime views merge both layers and derive fuel zone, hunger band, weight trait, deprivation target, and current protein-healing values for UI, diagnostics, and MP encoding. Loading a schema-14 save harvests its existing diagnostics into the sidecar before removing those keys from save state.

Carbohydrate and fat values remain food inputs. They contribute to food composition and satiety calculations, but NMS does not maintain carbohydrate or fat reserves on the player.

## Gameplay Effects

### Hunger and satiety

NMS owns the immediate fullness target while leaving vanilla consumption mechanics intact. The runtime derives a bounded nutrient signal from the calories and macro mix, then compares it with a capped physical-volume hint from the hunger drop actually observed during eating. The stronger signal wins; the two are not added together. Nutrient fullness follows a square-root response around a `400 kcal` reference and is capped at `0.40` hunger. Observed mechanical fullness is preserved up to `0.12` hunger and capped beyond that.

This split is necessary because `HungerChange` is overloaded. For multi-use ingredients such as flour, butter, pasta, and sugar, it also determines depletion fractions and the share of calories and macros transferred into prepared food. NMS therefore leaves the field and vanilla item behavior untouched, but no longer treats an arbitrarily large value as authoritative stomach fullness. An `80 kcal` grapefruit can still provide temporary physical fullness without inheriting its full `-20` recipe reservoir, while a substantial meal can communicate its energy even when its raw hunger value is mechanically small.

Consecutive nutrition deltas inside the short observation window are accumulated as one meal transaction before the nonlinear fullness target is evaluated. This keeps progressively consumed fluids and delayed MP stat updates from being counted as many separate snacks. The target is idempotent: if an MP client predicts it locally and the server later observes that corrected drop, the server computes the same result. Prediction changes no item values and sends no consume RPC; observed vanilla nutrition deltas remain the only intake authority.

Passive hunger return depends on:

- current hunger band
- fuel pressure
- recent caloric-balance pressure
- satiety buffer
- workload while awake
- sleep state
- the vanilla Stats Decrease sandbox multiplier
- the NMS Appetite Rate sandbox multiplier
- Hearty Appetite or Light Eater satiety decay

Fuel pressure rises progressively as available energy falls, but ordinary low energy no longer triples hunger return. The strongest pressure is reserved for complete depletion, while recent meals retain part of their staying power.

Recent caloric balance supplies a second, bounded appetite channel. Deficits inside a `200 kcal` deadzone do nothing; pressure then rises to a maximum `0.05 hunger/hour` at an `800 kcal` recent deficit. Unlike meal-return pressure, this additive channel is not suppressed by satiety, so a bulky low-calorie food can provide real immediate fullness without hiding a persistent energy shortfall for the rest of the day. Sleep attenuates the channel with the normal sleep hunger factor. The stronger and earlier response is calibrated against cue-driven replay of a recorded high-activity day: the previous channel reproduced severe under-eating even when the simulated player ate whenever hunger prompted them.

NMS caps modeled hunger at `0.699`. This deliberately keeps its correction layer below vanilla's Starving health-drain threshold.

Vanilla `FoodEaten` / Well Fed remains intentionally suppressed. That moodle is a raw-`HungerChange` healing timer with poison and eating-lock side effects, not a stomach-fullness state, so restoring it unchanged would reintroduce the same overloaded signal through a second path. Eat and drink completion hooks clear its timer immediately, before the normal authority update, so the suppressed moodle does not flash for a frame after a meal.

### Fuel and workload

Fuel burn uses MET-like workload sampled from the vanilla thermoregulator, timed actions, or movement fallbacks. Sleeping, resting, walking, running, sprinting, and heavy work produce progressively higher burn.

Slow Metabolism and Fast Metabolism slightly modify burn and weight response. Body weight also changes fuel burn within a bounded range.

Two server-owned NMS sandbox controls expose the deliberately separate tuning axes without changing the default balance. `Energy Burn Multiplier` (`0.25-3.0`, default `1.0`) scales fuel expenditure and caloric weight balance. `Appetite Rate Multiplier` (`0.25-3.0`, default `1.0`) scales visible-hunger return but does not directly change burn or weight; it composes with vanilla Stats Decrease. Missing options on an older save resolve to `1.0`.

### Deprivation

Deprivation reads the same smoothed caloric balance used by weight, but only after a much deeper `1800 kcal` deficit deadzone. It reaches its full target at `7000 kcal` of sustained negative balance, rises over `48 hours`, and recovers over `36 hours`. A strenuous single day can therefore increase appetite and weight-loss pressure without being labeled malnutrition; continued multi-day underfeeding is required before deprivation becomes visible.

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
- carry the authority's monotonic nutrition-deposit sequence
- use the explicit field contract in `NutritionMakesSense_MPSnapshot.lua`
- carry only player-facing state in release builds
- add metabolism diagnostics only when server dev tools are enabled

The release contract carries fuel, protein, deprivation, weight, recent energy balance, the weight controller, visible hunger, satiety, nutrition-deposit sequence, and the derived labels needed by player-facing UI. Dev servers extend that contract with explicitly whitelisted diagnostic fields. In-flight meal and resume bookkeeping never enters packets.

Clients reject duplicate or older packet sequences and reset the sequence gate on a new player session, so a restarted server is accepted after reconnect. Between snapshots, the client anchors vanilla hunger to the latest server display target; vanilla client drift therefore cannot repeatedly cross a moodle boundary and then be snapped back. Eat and drink completion still get an immediate local fullness prediction, but it is only a presentation bridge: snapshots whose deposit sequence proves they predate the meal cannot raise hunger above that prediction. Fragmented server deposits may settle below the ceiling, and the prediction is released when the server's deposit sequence and hunger target agree, or after a bounded timeout. The raw server hunger, effective display target, causal sequences, age, and resolution are retained in diagnostics. There is no second client metabolism projection, and clients do not write the server-owned protein-healing effect.

## Dev Recording

The dev recorder writes schema-versioned, CSV-formatted `.txt` files. Each run begins with metadata rows covering the loaded NMS and PZ versions, runtime role, sandbox context, traits, and active-mod load order.

Timeline rows distinguish local vanilla hunger, authoritative NMS hunger, and the last synchronized hunger value. They also carry hunger and Food Eaten moodles, the vanilla food-health timer, movement flags, thermoregulator MET, workload source, and each hunger-rate component. Meal rows split raw mechanical, capped physical, nutrient-modeled, applied, and correction values, plus cumulative transaction calories and fragment counts. Transition markers identify hunger-band, fuel-zone, deprivation-penalty, sleep, and moodle changes.

During each runtime session, NMS maintains monotonic diagnostic ledgers for accepted intake, metabolic burn, passive hunger gain, observed time, and sleep. The recorder subtracts its start baselines to report exact interval and whole-run totals without reconstructing them from samples. These transient ledgers do not influence gameplay or enlarge serialized player state.

In dev builds, completed vanilla `ISEatFoodAction` and `ISDrinkFluidAction` calls are observed without changing item behavior. Food-action rows capture the live item or fluid identity, fraction, hunger value, nutrition, preparation state, and ingredient metadata. A short-lived correlation ID joins that evidence to the next authoritative nutrition deposit or MP snapshot. MP rows additionally record snapshot/workload sequences, age, staleness, server timestamps, raw authority hunger versus effective display hunger, deposit-sequence causality, prediction age/resolution, and every actual vanilla-hunger shell correction. The recorder also separates vanilla Stats Decrease, NMS appetite tuning, their effective product, and NMS energy-burn tuning.

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

Development panels and live scenario runners live under `common/media/lua/client/dev/`. The runtime inspector leads with the last intake's applied and modeled fullness, its raw/physical/nutrient source split, correction versus vanilla, energy deposit, and meal staying power. Live scenario meal logs present fullness, energy, and staying power together so low-calorie bulky meals and calorie-dense foods can be compared directly. Server and shared trace support live under their corresponding `dev/` directories.

Dev modules load only when PZ debug tools are enabled and the active mod id is
`NutritionMakesSenseDev`. Workshop builds use `NutritionMakesSense`, so they
reject development surfaces before probing any excluded `dev/` module. Workshop
builds exclude client, server, and shared development directories. Release
servers ignore development trace commands.

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

The deterministic closed-loop soak (`tools/nutrition_makes_sense/run_closed_loop_soak.lua --strict`) advances the shipping metabolism code while simulated survivors respond to visible hunger rather than a fixed food schedule. Its default matrix covers canonical and recorded exploration workloads, three body sizes, appetite and metabolism traits, workload perturbations, balanced meals, the recorded food pattern, delayed reactions, and sandbox hunger-rate extremes. Sleep is tracked separately from awake comfortable-but-depleted time. `--quick --strict` is included in the normal characterization suite; the full matrix is the balance gate used after appetite changes.

The dev live runner's **Recorded Exploration Autopilot** is the engine-level companion test. It reproduces the measured wake-plus-sleep burn profile, then allows a short post-wake response window so a hungry survivor can actually act on the final cue. It cycles actual recorded-style foods through vanilla timed actions whenever the real hunger moodle signals, refuses rotten or dangerous uncooked test food, verifies NMS deposits and immediate hunger relief, records appetite and food-safety diagnostics, and restores player state afterward. This validates engine hooks that source-level simulation cannot cover; MP snapshot synchronization still requires an MP smoke run.

## Food Data Pipeline

1. Edit `docs/nms/authoring/nms_authored_food_table_curated.csv`.
2. Run `tools/nutrition_makes_sense/build_script_food_overrides.py`.
3. Validate representative routing and recipe-reservoir classification with `tools/nutrition_makes_sense/validate_closed_container_routing.py`.
4. Deploy through `tools/mod_sync/sync_local_mod.sh --mod nutrition`.

Do not hand-edit `NutritionMakesSense_food_overrides.txt`; it is generated output.
