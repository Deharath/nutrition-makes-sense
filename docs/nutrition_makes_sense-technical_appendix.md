# Nutrition Makes Sense — Technical Appendix (v1.0.0)

_As of March 30, 2026_  
`SCRIPT_VERSION=1.0.0`

## Scope

Nutrition Makes Sense (NMS) is a Build 42 nutrition and weight overhaul for Project Zomboid. The mod replaces vanilla nutrition values as gameplay authority, maintains its own metabolism state, and synchronizes the visible vanilla-facing surfaces from that state. Singleplayer and multiplayer share the same core authority and metabolism logic, with a server-authoritative path for multiplayer.

This appendix documents the repository as shipped in `1.0.0`: build layout, runtime architecture, multiplayer split, presentation surfaces, module map, and bundled development tooling.

## Design Summary

Core design goals:
- make food values authoritative across stable foods, partial foods, opened containers, fluids, and composed outputs
- separate appetite, available energy, deprivation, protein adequacy, and weight trend into distinct gameplay layers
- retain vanilla-facing hunger, weight, and healing surfaces only as synchronized presentation shells
- prevent vanilla starvation damage from becoming the active penalty model
- keep singleplayer and multiplayer behavior aligned through shared logic in `common/media/lua/shared/`

Runtime split:
- the client path runs the shared item and metabolism runtime in singleplayer
- multiplayer clients report consume events and workload summaries
- the multiplayer server owns authoritative metabolism state and snapshot publication
- stable authored food rows are patched at boot and repaired during runtime lifecycle events
- release packages exclude `common/media/lua/client/dev/`

## Build Layout

- Mod root (`NutritionMakesSense/`): metadata and art assets (`mod.info`, `42/mod.info`, `poster.png`, `nms_icon.png`)
- `common/`: source-of-truth Lua, translations, and runtime UI assets
- `common/media/lua/shared/generated/`: committed generated nutrition values and food-semantics tables
- `common/media/lua/client/dev/`: development-only panels, runners, and scenario tooling
- `42/`: Build 42 override layer containing `42/mod.info`
- `docs/`: technical documentation bundled with the mod repo

## Runtime Architecture

### Food Data And Item Authority

NMS uses two authority paths for food values:
- stable authored rows are embedded in generated Lua modules and applied directly to vanilla script items
- runtime-tracked foods carry per-item snapshots so nutrition survives partial use and stateful transformation

Primary modules:
- [NutritionMakesSense_Data.lua](../common/media/lua/shared/NutritionMakesSense_Data.lua) — loads embedded food values and semantic metadata
- [NutritionMakesSense_StablePatcher.lua](../common/media/lua/shared/NutritionMakesSense_StablePatcher.lua) — applies stable authored rows to script items and validates the result
- [NutritionMakesSense_StableItemRuntime.lua](../common/media/lua/shared/NutritionMakesSense_StableItemRuntime.lua) — re-runs patch repair during load, game start, and player creation
- [NutritionMakesSense_ItemAuthority.lua](../common/media/lua/shared/NutritionMakesSense_ItemAuthority.lua) — runtime authority facade for lookup, snapshot handling, and display resolution
- [NutritionMakesSense_ItemAuthority_Consume.lua](../common/media/lua/shared/items/NutritionMakesSense_ItemAuthority_Consume.lua) — resolves consumed values for gameplay deposits
- [NutritionMakesSense_FoodValues.lua](../common/media/lua/shared/generated/NutritionMakesSense_FoodValues.lua) — generated nutrition values keyed by item id
- [NutritionMakesSense_FoodSemantics.lua](../common/media/lua/shared/generated/NutritionMakesSense_FoodSemantics.lua) — generated semantic metadata used for authority routing

Authority modes:
- `authored` — stable items and authored runtime rows
- `computed` — composed, fluid, and other runtime-derived foods

This structure preserves nutritional values across partial consumption, opened-container transitions, evolved recipes, and crafted outputs.

### Metabolism State

The metabolism model is defined in [NutritionMakesSense_Metabolism.lua](../common/media/lua/shared/NutritionMakesSense_Metabolism.lua) and advanced by [NutritionMakesSense_MetabolismRuntime.lua](../common/media/lua/shared/NutritionMakesSense_MetabolismRuntime.lua).

Core state fields:
- `visibleHunger`
- `satietyBuffer`
- `fuel` (available-energy buffer)
- `deprivation`
- `proteins`
- `weightKg`
- weight-trend state derived from long-horizon energy-balance history

Vanilla nutrition fields are not the primary simulation. Instead, the runtime:
- anchors vanilla calories, carbohydrates, fats, and proteins to neutral baseline values
- samples positive vanilla deltas as food deposits entering NMS state
- writes synchronized visible hunger, visible weight, and healing values back to vanilla-facing surfaces
- suppresses vanilla food-eaten timer behavior where required to avoid conflicting signals

### Workload Sampling

NMS uses vanilla thermoregulator workload data as input to available-energy burn and exertion-related calculations.

[NutritionMakesSense_MetabolismRuntime_Workload.lua](../common/media/lua/shared/runtime/NutritionMakesSense_MetabolismRuntime_Workload.lua) samples:
- average MET exposure
- peak MET exposure
- heavy-exposure duration
- sleep observation

[NutritionMakesSense_Metabolism.lua](../common/media/lua/shared/NutritionMakesSense_Metabolism.lua) normalizes those samples into:
- `averageMet`
- `peakMet`
- `effectiveEnduranceMet`
- `workTier`

These normalized workload values feed available-energy burn, hunger pressure, and exertion-related penalties without replacing the broader metabolism model with a direct thermoregulator simulation.

### Multiplayer Authority

Multiplayer metabolism is server-authoritative.

Update flow:
1. clients bootstrap local hooks for consume and workload reporting
2. clients send consume events and workload summaries through [NutritionMakesSense_MPClientRuntime.lua](../common/media/lua/client/NutritionMakesSense_MPClientRuntime.lua)
3. the server receives and applies those inputs in [NutritionMakesSense_MPServerRuntime.lua](../common/media/lua/server/NutritionMakesSense_MPServerRuntime.lua)
4. shared metabolism logic updates authoritative player state
5. state snapshots are returned to clients for presentation and shell synchronization

This arrangement keeps presentation responsive on clients while preserving one authoritative metabolism state per player on the server.

### Presentation Layer

Tooltip presentation:
- [NutritionMakesSense_TooltipLogic.lua](../common/media/lua/shared/NutritionMakesSense_TooltipLogic.lua) decides what food information is visible and under which gating conditions
- [NutritionMakesSense_TooltipOverlay.lua](../common/media/lua/client/NutritionMakesSense_TooltipOverlay.lua) removes the vanilla hunger row and inserts NMS-owned nutrition rows

Character and health presentation:
- [NutritionMakesSense_WeightDisplayHook.lua](../common/media/lua/client/NutritionMakesSense_WeightDisplayHook.lua) adds a smoothed `kg/wk` trend readout to the character screen
- [NutritionMakesSense_HealthPanelHook.lua](../common/media/lua/client/NutritionMakesSense_HealthPanelHook.lua) displays deprivation and low-protein warnings in the health panel
- [NutritionMakesSense_MalnourishedMoodle.lua](../common/media/lua/client/NutritionMakesSense_MalnourishedMoodle.lua) registers and drives the malnourishment moodle surface

Client options:
- [NutritionMakesSense_ClientOptions.lua](../common/media/lua/client/NutritionMakesSense_ClientOptions.lua) registers client-facing debug-tooltip options

## Module Inventory

### Entry Points

- `client/NutritionMakesSense_Main.lua` — client boot facade that assembles runtime, multiplayer, UI, and bootstrap modules
- `server/NutritionMakesSense_Main.lua` — server boot facade that installs the multiplayer server runtime
- `shared/NutritionMakesSense_Boot.lua` — shared boot path for stable patching, item authority, metabolism runtime installation, and boot reporting
- `shared/NutritionMakesSense_MPCompat.lua` — multiplayer constants, command names, module id, and script version

### Shared Runtime

- `shared/NutritionMakesSense_CoreUtils.lua` — utility helpers for safe calls, item resolution, stat access, and runtime support
- `shared/NutritionMakesSense_Data.lua` — generated food-data loader
- `shared/NutritionMakesSense_StablePatcher.lua` — authored-food patcher and validation report builder
- `shared/NutritionMakesSense_StableItemRuntime.lua` — stable patch repair hooks
- `shared/NutritionMakesSense_DebugSupport.lua` — debug-launch and development-environment helpers
- `shared/NutritionMakesSense_Metabolism.lua` — metabolism formulas, thresholds, normalization, and gameplay-effect math
- `shared/NutritionMakesSense_MetabolismRuntime.lua` — authoritative metabolism facade, deposit handling, shell anchoring, and state IO
- `shared/runtime/NutritionMakesSense_MetabolismRuntime_Lifecycle.lua` — runtime installation and event lifecycle orchestration
- `shared/runtime/NutritionMakesSense_MetabolismRuntime_Authority.lua` — authoritative player-state update path
- `shared/runtime/NutritionMakesSense_MetabolismRuntime_Sync.lua` — snapshot building and visible-shell synchronization
- `shared/runtime/NutritionMakesSense_MetabolismRuntime_Workload.lua` — MET sampling, smoothing, and reported-workload helpers
- `shared/NutritionMakesSense_ItemAuthority.lua` — item-authority facade
- `shared/items/NutritionMakesSense_ItemAuthority_Query.lua` — item lookup and display-value resolution
- `shared/items/NutritionMakesSense_ItemAuthority_Lifecycle.lua` — snapshot lifecycle management for live items
- `shared/items/NutritionMakesSense_ItemAuthority_Traversal.lua` — traversal helpers for inventories, world items, containers, and vehicles
- `shared/items/NutritionMakesSense_ItemAuthority_Computed.lua` — runtime snapshot construction for computed foods
- `shared/items/NutritionMakesSense_ItemAuthority_Consume.lua` — consumed-value resolution for gameplay deposits
- `shared/NutritionMakesSense_TooltipLogic.lua` — shared tooltip logic
- `shared/generated/NutritionMakesSense_FoodValues.lua` — generated nutrition values
- `shared/generated/NutritionMakesSense_FoodSemantics.lua` — generated semantic metadata

### Client Runtime And UI

- `client/NutritionMakesSense_MPClientRuntime.lua` — multiplayer client facade
- `client/mp/NutritionMakesSense_MPClientRuntime_Context.lua` — multiplayer client state and context initialization
- `client/mp/NutritionMakesSense_MPClientRuntime_Network.lua` — snapshot requests, workload reports, and event ids
- `client/mp/NutritionMakesSense_MPClientRuntime_Consume.lua` — consume request packaging and dedupe protection
- `client/mp/NutritionMakesSense_MPClientRuntime_Hooks.lua` — client hook registration for multiplayer runtime surfaces
- `client/mp/NutritionMakesSense_MPClientRuntime_Lifecycle.lua` — snapshot receive path, projection, stale handling, and readiness logging
- `client/bootstrap/NutritionMakesSense_ClientBootstrap.lua` — bootstrap actions, hotkeys, inspection helpers, and food debug logging
- `client/hooks/NutritionMakesSense_ClientHooks.lua` — player hooks for shell synchronization and deprivation-driven melee damage adjustment
- `client/ui/NutritionMakesSense_UIHelpers.lua` — UI helper functions for translation, formatting, and state access
- `client/NutritionMakesSense_TooltipOverlay.lua` — tooltip patch and layout injection
- `client/NutritionMakesSense_HealthPanelHook.lua` — health-panel warning integration
- `client/NutritionMakesSense_WeightDisplayHook.lua` — character-screen weight-trend display
- `client/NutritionMakesSense_MalnourishedMoodle.lua` — malnourishment moodle integration
- `client/NutritionMakesSense_ClientOptions.lua` — client mod options

### Server Runtime

- `server/NutritionMakesSense_MPServerRuntime.lua` — multiplayer server command receive path, workload ingest, snapshot publication, and minute update loop

### Development Tooling

- `client/dev/NutritionMakesSense_DevPanel.lua` — main in-game development panel
- `client/dev/NutritionMakesSense_ToolPanel.lua` — targeted tool panel for item and state operations
- `client/dev/NutritionMakesSense_TestPanel.lua` — live scenario runner control surface for time acceleration, scripted intake, and result review
- `client/dev/NutritionMakesSense_SimRunner.lua` — simulation runner entry point
- `client/dev/NutritionMakesSense_LiveScenarioRunner.lua` — live scenario orchestration, recording, and assertion runtime
- `client/dev/NutritionMakesSense_LiveScenarioRunnerUtils.lua` — shared helpers for live runner assertions and state comparison
- `client/dev/scenarios/NutritionMakesSense_LiveScenarioCatalog.lua` — scenario catalog definitions
- `client/dev/scenarios/NutritionMakesSense_LiveScenarioAnalysis.lua` — scenario analysis helpers
- `client/dev/panels/NutritionMakesSense_DevPanelSink.lua` — sink and bridge helpers used by development panels

## Repo Assets

- [mod.info](../mod.info) — root mod metadata
- [42/mod.info](../42/mod.info) — Build 42 override metadata
- [poster.png](../poster.png) — poster art
- [nms_icon.png](../nms_icon.png) — icon asset
- [NMS_Malnourished.png](../common/media/ui/NMS_Malnourished.png) — malnourishment moodle icon
- [UI.json](../common/media/lua/shared/Translate/EN/UI.json) — English UI strings
- [Moodles.json](../common/media/lua/shared/Translate/EN/Moodles.json) — English moodle strings

## Implementation Notes

- NMS, not vanilla nutrition, is the gameplay authority for calories, macros, and related state transitions
- visible hunger remains capped below the vanilla starvation-damage threshold
- workload sampling is derived from vanilla thermoregulator MET data and normalized into NMS workload fields
- food authority persists across authored foods, partial consumption, open-container routes, and runtime-composed outputs
- release packaging excludes `common/media/lua/client/dev/` while retaining the gameplay runtime and player-facing UI
