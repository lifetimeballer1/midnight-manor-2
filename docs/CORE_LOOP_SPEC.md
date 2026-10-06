# Core Loop Playable Prototype

User approved continuing from the asset pipeline and requested free Space Bunny via OpenCode, then opening the running game. This phase implements the previously agreed core-loop MVP, not the complete campaign/endgame port.

## Fixed Direction

- Godot 4.7.2 GDScript, Compatibility renderer, full 3D; use the verified asset catalog.
- Same moonlit village feel and orbit camera, not first-person movement.
- 20x16 tiles, 2m per tile. Original starting buildings, five villagers and resources.
- Copy original JSON data read-only; do not change Manor 1 or the Blender source.
- Authoritative 20Hz simulation; no offline progress. Pause menu and focus loss stop simulation.
- Preview then explicit confirm, with live validation and atomic costs. Invalid placement spends nothing.
- Building tiers use existing stats/costs. Farm/lumber/mine production: 2/s, tier1 reserve500, notification150. Central caps preserve unbanked goods.
- Matching workplace assignment, gather/delivery trips and carry preservation; 25% assigned productivity.
- Recruit eight available roles; housing and resource requirements matter. Population grows with food and beds.
- Walls block grid paths; gates pass allies, not raiders. Towers/traps and fighters defend. Ruins stay repairable; troops revive after raids. Manor defeat ends the raid and grants recovery salvage.
- Original first raid at300 active seconds, 25-second warning, increasing test waves and recovery. Four-side entries on larger waves.
- Supported original early quests evaluate generic task kinds and grant once-only XP/rewards; unsupported late content is not represented as playable.
- Separate versioned local Godot save with error reporting and backup, never overwrite browser saves.

## Boundaries

The headless simulation lives in scripts/game/village_sim.gd; presentation/input/HUD live in scripts/game/village_game.gd. Scene is scenes/game.tscn. The prior asset viewer and tests remain available. Native building footprint widths are fitted to the original logical tile size for readability. Enemy art initially reuses the warrior silhouette with faction coloring; more roster exports remain later work. No full gear/abilities/technology/campaign/multiplayer/cloud-save parity is claimed.

## Acceptance

Build/confirm/cancel, move/upgrade/repair, collection/caps, assign/recruit, a real raid/victory/defeat, quest once-only rewards and save roundtrip are tested headlessly. Render overview, night and portrait shots. Run both existing asset checks and new gameplay checks. Launch the actual game scene and leave it running for the user.
