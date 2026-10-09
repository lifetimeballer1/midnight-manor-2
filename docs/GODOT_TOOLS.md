# Godot+ Tool Memory

Inventory checked 2026-10-07 against `project.godot`, installed plugin metadata,
and the live MCP project-info response. Engine: Godot 4.7.2, Compatibility
renderer. This is the standard engine plus project add-ons, not an engine fork.

## Enabled Add-ons

| Add-on | Version | Location | Use |
|---|---|---|---|
| Godot MCP Pro | 1.16.0 | `addons/godot_mcp` | Editor automation and running-game inspection/input/screenshots. Metadata advertises 178 editor tools; individual RPC support must be verified. |
| Funplay MCP | 0.9.2 | `addons/funplay_mcp` | Embedded editor MCP server: code execution, scene/script/file operations, play control and viewport capture. Separate from MCP Pro; connectivity is not certified. |
| Godot Asset Placer | 1.6.0 | `addons/asset_placer` | Existing 3D asset placement and management tools. |
| Antz's Debug Menu | 1.3.0 | `addons/debug_menu` | In-game performance metrics and hardware information; `DebugMenu` autoload. |
| VFX Library | 1.0.0 | `addons/vfx_library` | Particle/shader library with `VFX` and `EnvVFX` autoloads. Metadata advertises 35+ particle effects and 17+ shaders. |
| Manor Studio | 0.1.0 | `addons/manor_studio` | Staged building/tier balance edits with explicit Apply/Discard, validation, backup and external-conflict checks. See its README. |

## Available MCP Tool Families

- Context: project info/settings, current scene, scene tree, selected nodes,
  node properties, script/resource queries, errors and missing references.
- Authoring: node/scene operations, batch properties, resources, materials,
  shaders, animation tracks/state machines, particles, audio, navigation,
  physics, input maps and themes.
- Runtime QA: play/stop, game tree/properties/methods, key/mouse/action input,
  screenshots/frame capture, assertions, signal/property monitoring,
  performance/render metrics, structured scenarios and stress tests.
- Delivery: export presets/project exports and Android device/deploy tools.
  Exporting or deploying still requires an appropriate user request.

Use the tools actually exposed in the current session; do not assume this list
guarantees server support. Prefer small queries over full trees or property dumps.

## Integration Limits

- `godot_get_project_info` succeeded against Midnight Manor II on 2026-10-07.
  `godot_get_editor_state` returned RPC `-32601` (method not found). Do not
  repeatedly probe that method without a connection/plugin change.
- MCP Pro registers `MCPScreenshot`, `MCPInputService` and `MCPGameInspector`
  runtime autoloads. Inspector/input assertions require a running game and a
  working runtime connection; do not run them against the player's save blindly.
- VFX/EnvVFX helpers include `Vector2` APIs and 2D effects. Check dimensionality
  and renderer compatibility before adapting them for this 3D game. Keep the
  existing capped `scripts/game/combat_burst_pool.gd` for home/frontier impacts
  unless a task specifically requires changing it. VFX freeze-frame helpers
  alter global `Engine.time_scale`, so they require pause/lifecycle scrutiny.
- Manor Studio never edits player saves. Balance changes apply to the next game
  run; its numeric validation is not a campaign-balance assessment. Do not
  manually write `data/buildings.json` during Studio Apply.
- Previous checks reported Funplay socket-probe errors and ObjectDB/resource
  leaks. Neither is established fixed. Debug metrics on desktop do not certify
  Safari/phone performance.

## Usage Discipline

Reuse this inventory and existing context; inspect only the tools/files needed
for the task. Avoid duplicate investigations, repeated unsupported calls and
unnecessary full-suite runs. Run focused regressions while iterating and one
applicable final verification after code changes. Documentation-only memory
updates do not require launching the game or rerunning gameplay suites.
