# Living Village Systems Report

Scope: Milestone A only (living-system simulation, Stone/research/paving, save v2 + v1 migration).
Milestones B (interface and terrain presentation) and C (walls/gates, scaffolding, atmosphere,
raid warnings) were **not** started. No UI file was touched.

Date: 2026-10-05
Engine used for every run: `Godot_v4.7.2-stable_win64.exe` (official), headless.

## 1. What was actually repaired

### 1.1 Root cause of the v2 restore failure (one line, in the simulation)

`JSON.parse_string()` returns every number as a float, so a save reloaded from disk carried
`"version": 2.0`. The save validator tested membership with

```gdscript
if state.get("version") not in [1, 2]:
```

and `2.0 in [1, 2]` is **false** in GDScript, so *every* JSON-round-tripped save was rejected.
This was not specific to v2: it silently broke `restore_state`, `load_game`, and the
"existing save is still readable" guard inside `save_game` for v1 and v2 alike.

Fix in `scripts/game/village_sim.gd:1193` — validate the version as a finite integer and cast
before the membership test:

```gdscript
# JSON hands back every number as a float, so the version is checked as a finite integer and cast once.
if not _integer(state.get("version")) or int(state["version"]) not in [1, 2]:
	return false
if int(state["version"]) == 2 and not living.valid(state.get("living")):
	return false
```

`_integer()` requires an int or float, finite and `>= 0`, with an integral value, so `"2"`,
`-1`, `2.5`, `INF` and `NAN` are all still rejected. The only other numeric membership test in
the codebase was audited; nothing else is affected.

This single defect explains the whole pre-existing failure set: `test_village` was failing
3 checks and `test_workers_defense` was failing 9 before this change. Both are green now.

### 1.2 Test-setup error: quarry overlapping the trail

`tests/test_living_village.gd` built the quarry at `1,1` with size 2, which covers tiles
`(1..2, 1..2)` and therefore overlapped the trail segment deliberately worn at `2,2`. Paving
correctly refused with "Roads cannot overlap buildings.", so the paving block failed.

The rule was **not** weakened. The quarry moved to `1,5` (a free site; the nearest building is
the barracks at `7,5`), which is free of the worn trail. A new check was added to prove the
overlap rule still bites:

- `paving still cannot overlap a building footprint` — paving tile `1,5` is refused.

### 1.3 Test robustness (no more hung runs)

`tests/test_living_village.gd` previously indexed `living.cells["2,2"]["stone"]` directly after
`restore_state`. When the restore failed, Godot raised `Invalid access to property or key '2,2'`
and the `SceneTree` never reached `quit()`, so the run had to be killed after the timeout.

Now:

- a `cell(living, tile)` accessor reads through `.get()` with an empty-dictionary default;
- the v2 restore result is stored, and if it is rejected the test prints
  `Cannot continue: the version 2 snapshot was rejected`, writes the report and quits;
- all cell reads in the decay and migration blocks go through the accessor;
- the JSON writer for `docs/living_verification.json` is null-guarded;
- the suite always reaches `quit(0 or 1)`.

### 1.4 Notes on toolchain

`apply_patch` is not installed on this machine (`Get-Command apply_patch` returns nothing), so
the patches above were applied with the session's dedicated file-edit tool, one exact-match
replacement at a time. Temporary diagnostic scratch files created during the investigation
(`tests/_diag_tmp.gd`, plus capture files under the OS temp directory) were deleted;
`tests/` contains only the four original suites and the Python asset check.

## 2. Save format

- Field `version` is `2`; the file path is unchanged at `user://village-v1.json`, so existing
  saves keep loading and no file is orphaned.
- A v1 save is accepted and migrated in place: resources, buildings, units, quests and raid
  phase are restored exactly as saved, `stone` defaults to `0`, and the living system starts
  empty (`cells` empty, `insight` 0, no discoveries, no active project).
- The v1 fixture in the test is now internally coherent: because a v1 village never had a
  Stone Quarry, any worker that had been posted to the test quarry is unposted in the fixture.
  Without that the fixture itself was invalid and the migration check could never pass.

## 3. Verification runs (actual output)

All runs used `--headless --path . --script res://tests/<test>.gd -- --no-save` with a bounded
wait; no process needed to be killed.

| Suite | Exit | Result | Checks | Failures |
| --- | --- | --- | --- | --- |
| `tests/test_living_village.gd` | 0 | `LIVING_VILLAGE PASS` | 45 | 0 |
| `tests/test_village.gd` | 0 | `VILLAGE_TEST PASS` | 87 | 0 |
| `tests/test_workers_defense.gd` | 0 | `WORKERS_DEFENSE PASS` | 190 | 0 |
| `tests/test_game_scene.gd` | 0 | `GAME_SMOKE PASS` | 20 | 0 |
| `tests/test_asset_verification.py` | 0 | `4 passed in 0.41s` | 4 | 0 |

Totals: **342 GDScript checks + 4 Python checks, 0 failures, 0 hung runs.**

`test_village` also printed `NATURAL_RAID_CPU_MS 1301`.

Machine-written result files, all `"passed": true`:
`docs/living_verification.json` (45), `docs/village_verification.json` (87),
`docs/workers_defense_verification.json` (190), `docs/game_smoke_verification.json` (20).

### Before the fix, for comparison

| Suite | Exit | Failures |
| --- | --- | --- |
| `test_living_village` | hung (killed at 180 s) | 6 reported, then a key-access error |
| `test_village` | 1 | 3 |
| `test_workers_defense` | 1 | 9 |
| `test_game_scene` | 0 | 0 |

## 4. What the 45 living-system checks cover

Movement and wear
- Standing and turning in place produce no path cells.
- Wear accrues from distance travelled, not from frame count (25 short crossings give exactly
  `25/150` wear).
- 150 crossings establish a fully worn dirt path.

Research
- Paving and the Stone Quarry are both refused before discovery.
- `Stoneworking` starts and charges once; a second attempt while active is refused and does not
  charge again.
- Pause stops the research timer; a raid warning stops it too; it completes exactly once.
- The quarry unlocks only after discovery, before Stone costs exist.
- Insufficient Stone refuses `Road Masonry` atomically (Insight untouched).
- `Road Masonry` starts once its prerequisite, level, Insight and cost are satisfied.

Stone economy
- The quarry produces real Stone on site using the normal production rule.
- `sim.collect()` banks Stone under the existing capacity rules.

Paving
- An established dirt path paves; 8 Stone are spent; the same segment cannot be charged twice.
- Unworn ground cannot be paved.
- Paving is still refused over a building footprint.
- Friendly travel on stone is exactly 1.15x, and `_walk()` shows the bonus changing real unit
  movement (`1.5 * 1.15 * 0.05`).
- Enemies get no road speed bonus (still 1.2) and leave the friendly wear map untouched.
- Weighted routing prefers the paved run of 10 tiles from `2,3` to `11,3` with no detour.

Wear decay
- Unused dirt regrows only after the 10 active-minute quiet delay.
- Stone roads never decay.
- The `elapsed = 700` jump really does fire a scheduled raid; the test now asserts that
  (`raid_active` with 2 hostiles) instead of assuming it is harmless.

Save v2 / v1 migration / invalid states
- JSON really does return the field version as a float — this is the regression guard for §1.1.
- A v2 snapshot restores; roads, research discoveries and Stone survive; the mid-raid phase and
  its hostiles survive so the raid can be finished after loading.
- A v1 save migrates: stock, roster size and quest progress are preserved, Stone is 0 and the
  living system starts empty.
- Rejected without partial mutation: out-of-bounds road coordinates, non-finite Insight,
  `Road Masonry` without `Stoneworking`, a non-boolean stone flag, a non-canonical `"2, 2"`
  cell key, a missing `cells` section, and research time without an active project.
- The untouched save still loads after all of those rejected attempts.

## 5. Limits of this checkpoint

- Headless runs prove simulation and save logic only. Nothing here demonstrates visual quality.
- No capture was taken for this milestone; no interface work exists to capture.
- The 133 catalogued GLB assets were not re-verified file-by-file by this worker beyond the
  existing Python asset check; no catalog or art file was modified.
- Milestones B and C are untouched, so `village_game.gd` still shows the old interface, the
  fixed cross path strips are still in place, and there is no `stone_quarry` model path yet
  (there is no exported `stone_quarry` GLB). Those are the next milestone's work.