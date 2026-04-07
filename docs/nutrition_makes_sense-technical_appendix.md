# Nutrition Makes Sense — Technical Appendix (v1.0.2)

_As of April 6, 2026_  
`SCRIPT_VERSION=1.0.2`

## Scope

Nutrition Makes Sense (NMS) is a Build 42 nutrition and weight overhaul for Project Zomboid.

As of `1.0.2`, NMS uses a vanilla-first food model:

- food item behavior is owned by vanilla item scripts
- NMS-authored balancing ships as vanilla script overrides in `common/media/scripts/NutritionMakesSense_food_overrides.txt`
- NMS runtime owns metabolism state, visible-shell synchronization, UI, trait/workload logic, and thin multiplayer state sync

The old item-authority, stable-patching, snapshot, and explicit consume-RPC layers are no longer part of the shipped architecture.

## Design Summary

Core design goals:

- keep food content in native PZ script form instead of a parallel Lua authority stack
- keep metabolism math distinct from vanilla-facing presentation shells
- derive intake from observed vanilla nutrition changes instead of custom consume payload transport
- keep singleplayer and multiplayer behavior aligned through shared metabolism logic
- keep multiplayer server-authoritative for metabolism state without rebuilding a second food system on top of vanilla

Current runtime split:

- authored nutrition values live in the CSV, and the builder emits the rows it classifies as `authored` as script overrides
- vanilla handles live food-item mutation, partial use, and normal item behavior
- NMS samples positive vanilla nutrition deltas and converts them into metabolism deposits
- NMS writes visible hunger, weight, healing, and related shell values back to player-facing surfaces
- multiplayer clients report workload and receive snapshots; the server owns authoritative metabolism state
- release packaging excludes `common/media/lua/client/dev/`

## Build Layout

- Mod root (`NutritionMakesSense/`): metadata and art assets (`mod.info`, `42/mod.info`, `poster.png`, `nms_icon.png`)
- `common/media/scripts/`: generated vanilla script overrides, especially `NutritionMakesSense_food_overrides.txt`
- `common/media/lua/shared/`: metabolism logic, compat helpers, shared UI logic, and runtime support
- `common/media/lua/client/`: client UI, hooks, bootstrap, and thin multiplayer client runtime
- `common/media/lua/server/`: thin multiplayer server runtime
- `common/media/lua/client/dev/`: development-only panels, runners, and scenario tooling
- `42/`: Build 42 override layer containing `42/mod.info`
- `docs/`: technical documentation bundled with the mod repo

## Food Layer

### Script-first nutrition data

NMS no longer ships food authority as generated Lua tables.

Current food-data pipeline:

1. author nutrition rows in `docs/nms/authoring/nms_authored_food_table_curated.csv`
2. run `tools/nutrition_makes_sense/build_script_food_overrides.py`
3. emit `common/media/scripts/NutritionMakesSense_food_overrides.txt`
4. let vanilla load those overrides as normal item-script content

This means the game reads hunger, calories, carbs, fats, and proteins from the item/script layer directly. Tooltip and debug readers now read those vanilla-facing fields instead of consulting an NMS-owned item-authority facade.

### Intake ownership

NMS runtime does not send or accept explicit food consume payloads anymore.

Instead:

- vanilla mutates the live food item and player nutrition fields
- NMS samples positive changes in vanilla calories/macros
- those observed deltas are converted into metabolism deposits
- visible hunger correction and other shell outputs are then synchronized from NMS state

This keeps the item/content side native to vanilla while preserving NMS's custom metabolism model.

### Special item classes

- ordinary foods and opened edible states can ship authored script overrides
- fluid-backed items stay fluid-driven and are not re-authored through the container shell
- scaffold or prep items are skipped from authored override output
- special-case consumables stay explicit review/exclusion surfaces rather than being treated as ordinary food rows

## Metabolism State

The metabolism model is defined in `common/media/lua/shared/NutritionMakesSense_Metabolism.lua` and advanced by `common/media/lua/shared/NutritionMakesSense_MetabolismRuntime.lua`.

Core state fields include:

- `visibleHunger`
- `satietyBuffer`
- `fuel`
- `deprivation`
- `proteins`
- `weightKg`
- normalized workload signals such as `averageMet`, `peakMet`, and `workTier`

Vanilla nutrition is not the primary long-horizon simulation. It is the intake signal and the presentation shell. NMS still owns fuel, deprivation, satiety, protein adequacy, and weight trend behavior.

## Workload Sampling

NMS uses vanilla thermoregulator workload data as input to available-energy burn and exertion-related calculations.

Primary modules:

- `common/media/lua/shared/runtime/NutritionMakesSense_MetabolismRuntime_Workload.lua`
- `common/media/lua/shared/NutritionMakesSense_Metabolism.lua`

These modules normalize MET-like workload signals into NMS runtime state without trying to replace the rest of the metabolism model with a full thermoregulator simulation.

## Multiplayer Authority

Multiplayer metabolism is server-authoritative, but the food path is intentionally thin.

Update flow:

1. clients report workload changes and request snapshots through `common/media/lua/client/NutritionMakesSense_MPClientRuntime_Vanilla.lua`
2. the server receives those commands in `common/media/lua/server/NutritionMakesSense_MPServerRuntime_Vanilla.lua`
3. shared metabolism logic updates authoritative player state
4. the server publishes state snapshots back to clients
5. clients use those snapshots for UI state and shell synchronization

What is gone:

- no explicit `consumeItem` RPC
- no client-side consume payload packaging
- no consume reconcile/projection stack
- no server-side food payload replay/dedupe authority

## Presentation Layer

Tooltip presentation:

- `common/media/lua/shared/NutritionMakesSense_TooltipLogic.lua` decides what food information is visible
- `common/media/lua/client/NutritionMakesSense_TooltipOverlay.lua` patches the tooltip presentation

Character and health presentation:

- `common/media/lua/client/NutritionMakesSense_WeightDisplayHook.lua`
- `common/media/lua/client/NutritionMakesSense_HealthPanelHook.lua`
- `common/media/lua/client/NutritionMakesSense_MalnourishedMoodle.lua`

Client options:

- `common/media/lua/client/NutritionMakesSense_ClientOptions.lua`

## Module Inventory

### Entry points

- `client/NutritionMakesSense_Main.lua` — client boot facade for runtime, UI, bootstrap, and thin MP client wiring
- `server/NutritionMakesSense_Main.lua` — server boot facade for the thin MP server runtime
- `shared/NutritionMakesSense_Boot.lua` — shared boot path for metabolism runtime installation and boot reporting
- `shared/NutritionMakesSense_MPCompat.lua` — multiplayer constants, command names, module id, and script version

### Shared runtime

- `shared/NutritionMakesSense_CoreUtils.lua` — utility helpers
- `shared/NutritionMakesSense_DebugSupport.lua` — debug-launch and development-environment helpers
- `shared/NutritionMakesSense_Compat.lua` — compat registry bootstrap
- `shared/NutritionMakesSense_HealthPanelCompat.lua` — stacked-mode health-panel integration
- `shared/NutritionMakesSense_Metabolism.lua` — metabolism formulas and gameplay-effect math
- `shared/NutritionMakesSense_MetabolismRuntime.lua` — authoritative metabolism facade, deposit handling, and state IO
- `shared/runtime/NutritionMakesSense_MetabolismRuntime_Lifecycle.lua` — lifecycle orchestration
- `shared/runtime/NutritionMakesSense_MetabolismRuntime_Authority.lua` — authoritative state update path
- `shared/runtime/NutritionMakesSense_MetabolismRuntime_Sync.lua` — snapshot building and shell synchronization
- `shared/runtime/NutritionMakesSense_MetabolismRuntime_Workload.lua` — workload sampling and reported-workload helpers
- `shared/NutritionMakesSense_TooltipLogic.lua` — shared tooltip logic

### Client runtime and UI

- `client/NutritionMakesSense_MPClientRuntime_Vanilla.lua` — snapshot requests, workload reports, and projected-state handling
- `client/bootstrap/NutritionMakesSense_ClientBootstrap.lua` — bootstrap actions, hotkeys, inspection helpers, and food debug logging
- `client/hooks/NutritionMakesSense_ClientHooks.lua` — player hooks for shell synchronization and deprivation-driven combat adjustment
- `client/ui/NutritionMakesSense_UIHelpers.lua` — shared client UI helpers
- `client/NutritionMakesSense_TooltipOverlay.lua` — tooltip patch and layout injection
- `client/NutritionMakesSense_HealthPanelHook.lua` — health-panel warning integration
- `client/NutritionMakesSense_WeightDisplayHook.lua` — character-screen weight-trend display
- `client/NutritionMakesSense_MalnourishedMoodle.lua` — malnourishment moodle integration
- `client/NutritionMakesSense_ClientOptions.lua` — client mod options

### Server runtime

- `server/NutritionMakesSense_MPServerRuntime_Vanilla.lua` — server receive path, workload ingest, snapshot publication, and update loop

### Development tooling

- `client/dev/NutritionMakesSense_DevPanel.lua`
- `client/dev/NutritionMakesSense_ToolPanel.lua`
- `client/dev/NutritionMakesSense_TestPanel.lua`
- `client/dev/NutritionMakesSense_LiveScenarioRunner.lua`
- `client/dev/NutritionMakesSense_LiveScenarioRunnerUtils.lua`

## Repo Assets

- `mod.info` — root mod metadata
- `42/mod.info` — Build 42 override metadata
- `poster.png` — poster art
- `nms_icon.png` — icon asset
- `common/media/ui/NMS_Malnourished.png` — malnourishment moodle icon
- `common/media/lua/shared/Translate/EN/UI.json` — English UI strings
- `common/media/lua/shared/Translate/EN/Moodles.json` — English moodle strings

## Implementation Notes

- If a task changes food values, update the authored CSV and rebuild the script overrides.
- If a task changes gameplay math, edit metabolism/runtime code rather than recreating item-level authority helpers.
- If a task changes multiplayer behavior, preserve the thin workload-report plus state-snapshot contract.
- If a task changes tooltip/debug reads, keep them read-only against vanilla item/script fields.
- Do not reintroduce stable patch repair, item snapshots, or explicit food consume transport without a deliberate new architecture decision.
