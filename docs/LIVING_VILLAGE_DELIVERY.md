# Living Village: Update 2

## Implemented

- Original dark-medieval, Clash-inspired layout: compact village/quest/research panel, stacked resource capacity meters, categorized real-model building cards and bottom contextual actions. Research expands on request; desktop/portrait panels remain separate.
- Outdoor workers reserve distinct reachable stands and face job targets smoothly. Fallback stands and slot metadata survive JSON saves. Builders face their site, fighters face targets, and orders/hold retain priority.
- Manor-priority defense, ranged shooting and safe archer retreat with hysteresis; emergency nearby threats take precedence over distant targets.
- Friendly movement slowly wears soft dirt trails; no idle or enemy wear. Unused trails regrow only during active time. Cached two-mesh rendering replaces the fixed cross strips. Weighted routes prefer useful roads without huge detours.
- Stoneworking research unlocks the Stone Quarry; Road Masonry unlocks paving. Projects use real prerequisites, costs, insight and time. They pause during alarms, one project runs at a time, and costs are paid once.
- Paving requires an established dirt tile, live confirmation and eight Stone. Stone roads persist and provide15% friendly travel speed, not enemy or passive production bonuses.
- Logical-neighbor wall connectors and rotated gates, with independently moving lift meshes. Enemy pressure closes gates for friendly routing too; clearing danger reopens them.
- Scaffolding and progress geometry replace squashed construction meshes. Incoming perimeter-side warnings and recent-damage building indicators follow actual simulation state.
- Restrained ground variation, stone worksite piles, practical lights and at most six chimney-smoke sources. Transient collection/projectile effects and road/model/thumbnail caches remain capped.
- Validated save version2, v1 migration without resetting the village, finite/integral version checks, saved roads/research/reservations and protection of corrupt originals.

## Asset And Scope Honesty

The existing mine GLB is adapted for the quarry with gray surfaces and stone piles. Road cobbles, connection rails and scaffolds are procedural Godot presentation, not new Blender exports. The133-delivery asset catalog is unchanged. The inspector remains available.

This completes the selected Living Village update to the core-loop prototype, not the entire original campaign/technology/gear/multiplayer game. Mobile-shaped desktop windows have been checked; actual mobile devices/browser exports and frame-rate certification remain untested. Work points are tile-correct, hand-authored approximations to the existing art.

## Verification

Run with the installed Godot4.7.2 console executable:

```powershell
godot --headless --path . --script res://tests/test_village.gd -- --no-save
godot --headless --path . --script res://tests/test_game_scene.gd -- --no-save
godot --headless --path . --script res://tests/test_workers_defense.gd -- --no-save
godot --headless --path . --script res://tests/test_living_village.gd -- --no-save
godot --headless --path . --script res://tests/test_update2_scene.gd -- --no-save
python scripts/verify_assets.py
python -m unittest discover -s tests -v
```

JSON results are under docs/. Native captures are docs/previews/update2-night.png, update2-build.png and update2-portrait.png. The night showcase is an explicitly labelled capture-only accelerated fixture: it demonstrates paving/research/construction without altering a player save. Ordinary startup has no planted trails, completed research or granted Stone.

Final fresh output: village87, game_scene20, workers_defense190, living_village45, update2_scene68, all PASS with zero failures (410 checks total). Four Python regression tests and133 GLB hash/structure checks also pass. Final desktop/build and360x800 screenshots were rendered in native Godot and inspected.

## Worker History

Free Space Bunny drafted/implemented much of the worker/AI, system repairs and UI. Several calls stalled or stopped partially; the controller completed missing references, preview cleanup, responsive layout, real contextual actions, visuals and final integration/tests directly. No failed worker verdict is presented as a completed review. No delegated paid fallback, commits, pushes, source-Blender writes or deployment were performed.
