# Midnight Manor II

> **Play in your browser:** https://lifetimeballer1.github.io/midnight-manor-2/
> Press **Enter Village** to begin. No install needed — the web build is deployed from `main` via GitHub Actions + Pages.

A Clash-style 3D base-builder prototype in **Godot 4.7 / GDScript**: raise a moonlit manor on a 20×16 tile map (40×32 m), gather Wood / Food / Gold / Lumber / Stone, hire eight professions, research Stoneworking and Road Masonry, and hold the walls when the horns sound.

## Play

| Option | How |
|---|---|
| Browser (recommended) | Open https://lifetimeballer1.github.io/midnight-manor-2/ — built automatically on every push to `main` (see `.github/workflows/web.yml`) |
| Godot editor | Open `project.godot` in Godot 4.7.2+, run `scenes/game.tscn`, press **Enter Village** |

### Safari / iPhone / iPad

The web build is exported **single-threaded** on purpose: threaded Godot builds need cross-origin isolation headers that GitHub Pages cannot send, so Safari refuses to boot them. CI enforces this (`Guard Safari compatibility` step fails the build if threads come back). If the page ever shows a "features missing" error or an old build:

1. Hard-refresh (hold Shift + tap reload, or Cmd+Shift+R on Mac)
2. Or open the link in a private window to force a fresh load
3. Requires WebGL2 (iOS 15+, any recent Safari)

### Controls

- **Build:** pick a structure card → click/slide the ghost preview → **Confirm Build**. Cancelling never spends resources. Walls/gates stay in placement mode for repeated segments.
- **Select:** click a building to Collect / Upgrade / Move / Repair, or assign a matching worker. Move is blocked during warnings/raids.
- **People:** hire eight professions, select villagers to assign workplaces, train units. Cottages add beds; warm beds + food grow the population.
- **Defense:** Horn (bottom bar) starts a real wave after a warning. Warriors/archers, towers and traps defend; walls block routes. Click a selected fighter's destination to issue orders. Fallen defenders revive; ruins can be repaired.
- **Village Path:** eleven early quests with original objectives/rewards (one-time rewards).
- **Camera:** left/middle-drag pan, right-drag rotate/tilt, wheel zoom, Q/E orbit, R/F tilt, WASD pan, 0 recentres. Touch tap/drag hooks exist; real mobile testing still pending.
- **Pause / Save:** pauses + save/lighting/sound. Autosaves every 5 active seconds, on focus loss and close. No offline progress.

You start with nine buildings, five villagers, 320 Wood / 180 Food / 210 Gold. Costs, production, caps and stat curves live in `data/`. First scheduled wave at 300 active seconds.

## Latest visual + UI update

- **Balanced HUD:** badge + XP + shield timer + Manor-flavoured resources, 72px top bar, tabular numbers
- **Left rail only** (76px): Path / Research / raid pill — right side stays clear for the shop sheet
- **Bottom bar:** SHOP (gold) + ATTACK (blood) 96px primaries, rest secondary, 44px min hits, 24px safe margins
- **Compact shop cards:** 52px rows, 72px real-model thumbnails (unified 3-point ISO stage + rim light), owned counts, LOCKED dim + Town-Hall requirement tooltips, gold trim on upgradeable
- **Selected-only range ring:** shared 16-gon annulus (fill 0.28 + gold rim 0.85)
- **World:** yaw-following sun + cool fill, filmic tonemap, dusk fog, 6-nearest-lamp pool (was 100+ omnis), full-terrain outskirts (76×64), nature-only scatter, chimney smoke 9/4.2s
- **Tiers T1–T6:** zero-triangle repaint — roof value ramp 0.18→0.75, walls locked, gold only from T4, banner/glow/smoke scale with tier

## Living Village systems

Research Stoneworking (quarry + miners at village level 2) and Road Masonry (pave worn dirt for 8 Stone/segment, +15% friendly speed). Villagers wear dirt into faint paths (~25 crossings) and full trails (~150); unused dirt regrows after ~10 active minutes. Living Manor generates 6 Insight/min; research pauses during alarms. See `docs/LIVING_VILLAGE_DELIVERY.md`.

## Project layout

### Manor Studio

The project now includes a custom **Manor Studio** Godot editor dock for staged
building/tier balance edits, validated Apply, previous-content backups and
external-file conflict protection. Reopen the project or enable it in
**Project Settings > Plugins**. See `addons/manor_studio/README.md` for usage.
It does not modify the engine or player saves.

```
scenes/game.tscn          main scene (Node3D MidnightManor2, procedural village)
scripts/game/             village_game.gd (UI/world), village_sim.gd (sim),
                          village_ui.gd (dark-medieval theme + thumbnails),
                          village_details.gd (scaffolds, smoke, warnings)
art/                      310 verified GLBs + art/catalog.json + manifests
data/                     costs, production, caps, stat curves
docs/                     delivery notes, verification JSON, previews
tests/                    5 GDScript suites + python tests
```

## Assets

- Source: user-provided `Game Assets.blend` (never overwritten; exports run in a separate background Blender process).
- 273 building-tier GLBs (51 types) + 37 rigged characters (the original 8 plus every quest profession: divers, masons, healers, halberdiers…) with idle/walk/work/death (+attack/gather where applicable).
- Base-centred, metres, +Y up, scale 1, materials/palette embedded. LOD1 bodies, reference layouts and rigs excluded.
- `art/catalog.json` is authoritative. See `docs/ASSET_LIST.md`.

Reproduce exports (Blender 5.2.2, `SOURCE` = your `Game Assets.blend`):

```powershell
blender --factory-startup --disable-autoexec -b "SOURCE" --python-exit-code 1 --python scripts/blender/export_mvp.py
```

## Verification

```powershell
python scripts/verify_assets.py
python -m pytest -q
godot --headless --editor --import --path .
godot --headless --path . --script res://scripts/ArtCheck.gd
godot --headless --path . --script res://tests/test_village.gd
godot --headless --path . --script res://tests/test_game_scene.gd -- --no-save
godot --headless --path . --script res://tests/test_workers_defense.gd -- --no-save
godot --headless --path . --script res://tests/test_living_village.gd -- --no-save
godot --headless --path . --script res://tests/test_update2_scene.gd -- --no-save
```

Reports: `docs/export_verification.json`, `docs/godot_verification.json`, `docs/village_verification.json`, `docs/game_smoke_verification.json`; captures in `docs/previews/`.

## Cozy Gothic overhaul (in development)

- Restored building details, live Chronicle/Chart/Board status, safe pause transitions,
  44px minimum controls, and phone layouts checked through native captures.
- Optional Old Bell mentor, Continue/New Game confirmation, and a separate
  `.previous` recovery archive that ordinary autosaves do not rotate away.
- Village needs: every three active minutes each villager eats five Food.
  Shortages and inadequate housing reduce morale/productivity; restoring supplies
  and beds recovers the village. Paused/closed time never adds penalties.
- Frontier (Act IV): choose up to eight defenders, pay 20 Food + 10 Gold, enter a
  separate lightweight region battle map, rally by tapping ground, and return after
  victory, defeat or retreat. Home time freezes; active battles save and resume.
  Each battle's rewards/casualties settle once. Secured regions support repeat patrols.
- Real delivery and level-25 prestige commands, physical Dawn Gate completion,
  specialist recruitment, Great Work proxy models, and repeatable contracts.
  Act VIII now introduces the Bell Tower and Dawn Gate before requiring them.
- Save payload v4 preserves the original `village-v1.json` path and migrates
  v1/v2/v3 villages. Advanced resources, needs and expeditions survive JSON saves.
- Haunted outskirts use inexpensive stone ruins outside the building footprint;
  home enemies now reuse distinct existing character silhouettes by role.

New regression suites: `test_overhaul_foundation`, `test_village_needs`,
`test_frontier_battles`, `test_campaign_actions` (same console command format above).
Optional native QA captures use `--capture-dir=<existing absolute directory>` with
the foundation/frontier suites and never load the player's village.

This is not release-certified: a complete campaign playthrough using unmodified
resources, balance/art polish, real Safari/phone performance and browser export
validation remain required. Fixture tests are not proof of those outcomes.

## Roadmap

Wall-row drag placement/upgrades, more emergency roles, equipment/abilities, campaigns, bigger tech tree, remaining roster. Enemy visuals reuse warrior silhouette + faction tint. Full touch controls, perf testing on device, license audit still open.
