# Fortress & Command Delivery

Date: 2026-10-06  
Branch: `gbt`  
Scope: major defensive-gameplay update built on the existing Living Village / Godot 4.7.2 architecture.

## Delivered systems

### Fortress construction
- Fortifications research unlocks drag-built wall lines.
- Wall-line placement snaps to a cardinal row/column, previews the full run, validates every tile, checks the full building cap and spends the total cost atomically.
- Connected walls, stone walls and gates can be repaired or upgraded as one defense section.
- Gate Engineering can replace an existing wall/stone-wall segment with an engineered gate without breaking its connected-defense identity.
- Existing wall/gate visual connection code remains authoritative.

### Fortress Command
- New Defense panel shows the next wave, predicted approach sides and expected enemy composition.
- Persistent rally point on valid open ground with an in-world marker.
- Defender duties: Patrol, Gate, Manor, Towers and Rally.
- Gates, towers, archer towers and Guard Posts can hold exact defender-post assignments.
- More > Commands exposes selected-building advanced controls on the compact phone UI.
- Tower targeting modes: Closest, Strongest, Weakest, Sappers and Manor Threat.

### Defensive progression
The Living Village research tree now continues:
1. Stoneworking
2. Road Masonry
3. Fortifications
4. Gate Engineering
5. Watchtower Doctrine
6. Defensive Logistics

These nodes unlock real mechanics rather than passive percentage-only bonuses.

Activated dormant content:
- Guard Post (adapted from Wayfinder Post data; reuses verified tower art)
- Mason Yard (reuses verified sawmill art)
- Emberforge (native verified art)
- Oathstone (native verified art)
- Mason (reuses builder rig)
- Weaponsmith (reuses builder rig)
- Warden (reuses warrior rig)
- Longbowman (reuses archer rig)

No Blender source was modified and no unverified model was introduced.

### Siege AI
Five hostile archetypes now compose later waves:
- Raider: baseline attacker
- Skirmisher: fast pressure unit
- Brute: slow, durable wall breaker
- Marksman: ranged attacker
- Sapper: prioritizes gates, walls and defensive posts

Later waves mix archetypes instead of only scaling enemy count. Sappers receive elevated defender threat priority. Brutes/sappers seek defensive structures; ranged enemies can fire from distance.

Gate Engineering increases gate reaction distance and reduces incoming gate damage. Fortifications reduces wall/stone-wall siege damage.

### Defenders and support
- Warriors/Wardens default toward gate/manor duties.
- Archers/Longbowmen default toward tower duty.
- Assigned defenders assemble at their post/rally area during warning periods and respond to threats according to their duty.
- Wardens take reduced incoming raid damage.
- Posted Weaponsmiths at a finished Emberforge grant combat-unit damage support.
- Defensive Logistics gives Builders and Masons automatic post-raid repair work. Repairs consume real Wood; Masons repair faster.

### Raid presentation
- Player-triggered Horn raids use a 20-second preparation period; scheduled raids retain the normal warning window.
- HUD warning text includes approach sides and composition.
- Enemy archetypes are visually differentiated with scale/tint while reusing the verified warrior rig.
- Damaged structures gain progressive battle scars at roughly 75/50/30% health.
- Existing smoke-capable structures visibly smoke under heavy damage.
- Every completed raid creates an after-action report with victory/defeat, enemies defeated, buildings damaged/destroyed, defenders knocked out, duration and reward.

## Save compatibility

The file path remains `user://village-v1.json` and payload version remains 2.

Version-2 saves now persist:
- rally point
- defender duty and exact defensive post
- tower targeting mode
- last raid report
- active raid tracking needed for accurate reports

Runtime path caches remain excluded from JSON. Old version-2 saves restore with defaults for all new fields. The unset rally/post sentinels are explicitly supported.

## Verification

GitHub Actions run on `gbt` without deploying Pages. A verified green run before this documentation pass reported:

- asset verification: 133 assets, PASS
- Python asset tests: 4 PASS
- `test_village.gd`: 92 checks, 0 failures
- `test_game_scene.gd`: 28 checks, 0 failures
- `test_workers_defense.gd`: 190 checks, 0 failures
- `test_living_village.gd`: 45 checks, 0 failures
- `test_update2_scene.gd`: 76 checks, 0 failures
- `test_fortress_command.gd`: 46 checks, 0 failures
- Web export: PASS
- Safari single-thread guard: PASS

Total GDScript assertions: **477**, plus 4 Python tests.

The dedicated Fortress suite covers research gates, wall-line atomicity, connected defenses, engineered gate insertion, rally points, exact defender posts, tower targeting, mixed wave manifests, dormant role/building activation, save roundtrips, Defensive Logistics repairs and after-action reporting.

## Still outside this update

- Full campaign/endgame port
- Full equipment/ability system
- Remaining dormant building/profession roster
- Dedicated new character meshes for the four activated fortress professions
- Multiplayer/cloud saves
- On-device performance certification and final asset-license audit

Those remain future work; this update does not claim them.
