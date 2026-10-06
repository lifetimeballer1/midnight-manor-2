# Core Loop Delivery

## Implemented

The main scene is now a playable Godot core-loop prototype, not an asset gallery. It uses the source JSON tables and verified GLBs without modifying Manor 1 or the Blender source.

- Original starting buildings, roster and resources; orthographic orbit camera on a20x16 map with2m tiles.
- Live-validated preview/confirm/cancel, footprint collision, building counts/level gates, construction, tier upgrades, relocation and repairs.
- On-site capped production, whole-unit collection, central capacity, partial collection and held reward overflow.
- Recruitment/housing, matching workplace assignments, gathering/delivery, carried goods, direct orders/hold and basic stat-curve training.
- Population growth with food and beds; first eleven original early quests with once-only rewards/XP.
- Scheduled and test perimeter waves, real fighter/tower/trap damage, blocked wall routes, friendly gate passage, ruins, manor defeat salvage and defender revival.
- Versioned local saves, backup rotation, validated roundtrip, visible errors and protection of unreadable saves. Focus/pause freeze active simulation; no offline production.
- Navy/brass/parchment HUD, practical warm lights, job/combat animations, collection chimes and projectile effects.

## Worker Use

Actual OpenCode calls used `opencode/space-bunny-free`, as requested. Space Bunny supplied grid-pathfinding/input/timing draft advice. Its implementation attempt stopped at an external-directory permission boundary before writing files. Its broad read-only review timed out without a verdict. The controller implemented and verified the game; no free-worker execution or review success is falsely claimed, and no paid fallback was used in this phase.

## Verification

Headless simulation checks (87) and scene integration checks (20) run with the real Godot4.7.2 runtime. Generated JSON reports record the result. Tests cover costs/refusals, production/caps, pause/focus, assignments, housing, training, routes/gates, natural raid resolution, victory/defeat/revival, repairs, all eleven quest completions, save roundtrip/corruption and dynamic UI controls. The asset-file checker still verifies all133 original delivered GLBs, and its four positive/negative Python tests pass.

Desktop rendering is captured and inspected separately. Headless UI tests are not equivalent to exhaustive native input or real-device mobile/browser tests.

Final observed results: `VILLAGE_TEST PASS checks=87 failures=0`, `GAME_SMOKE PASS checks=20 failures=0`, `ARTCHECK PASS assets=133 failures=0`, Python asset-regression tests4/4 PASS, and independent GLB checker133/133 PASS. Night, day and portrait renders saved in `docs/previews/` and inspected. The native `Midnight Manor II (DEBUG)` window was launched through the desktop shell and confirmed responding; it is left open for the user at Enter Village.

## Limits

This is the first playable MVP, not exact parity with every original system. No advanced gear/abilities, full campaign, research, multiplayer or cloud save. The prototype has single-segment repeat wall placement, not original drag-row batching. Workers use simplified gather/delivery and civilian shelter behavior; no full emergency-service simulation. Enemy art temporarily reuses the warrior model with faction color. Connected wall joins and building mechanism clips require more work. The day/night control is a lighting toggle, not the full authored sky/weather clock. Only collection SFX are implemented, not the original generative music score.

Web-first cross-platform remains the direction, but desktop verification is the evidence available. No export/deployment or mobile performance claim is made.
