# Cozy Gothic Overhaul Checkpoint

Branch: `update/cozy-gothic-overhaul`. Existing user changes were retained.
This is a playable development checkpoint, not the completed public release.

## Implemented

- Visible building inspector, correct Pause/More transitions, live Chronicle,
  Chart and Board state, touch-sized controls, nearest-body phone selection,
  fixed story-banner/Chart/nav overflow and scrollable secondary actions.
- Contextual optional mentor, Continue/New Game confirmation, separate previous-
  village recovery archive, explicit save failures and battle save feedback.
- Needs using the existing town-meal tuning: five Food per villager every three
  active minutes, housing/morale effects and recoverable production penalties.
  No closed-time or pause-time penalties; no starvation deaths.
- Separate 3D frontier prototype: seven region configurations, up to eight
  selected defenders, real food/gold costs, automatic combat, rally commands,
  pause/retreat, persisted battle state, one-time casualty/reward settlement and
  repeat patrols. Hidden-home input and simulation cannot consume battle gestures.
- Real resource deliveries, level-25 prestige with retained honors, physical Dawn
  Gate objectives, specialist hire controls, unlocked trade structures, Great
  Work placement/proxies, and functional bounded repeatable contracts.
- Research storage reaches every authored cost; bonus categories are isolated;
  repair discounts save wood. Migration preserves derived acts and research
  unlocks. Optional rewards pay once. Advanced stocks and fractional refinery
  production survive, and manufactured materials count toward gathering goals.
- Save payload v4 retains `village-v1.json` and migrates v1/v2/v3. Needs and frontier
  sections are validated before state replacement.
- Lightweight stone ruins outside the playable footprint and distinct existing
  enemy character silhouettes. Original Blender sources and GLBs were untouched.
- Explicit JSON export filter; single-threaded Safari setting remains unchanged.
- Real shared combat burst pool: twelve preallocated emitters with billboard
  render geometry, bounded particle counts, expiry/reuse and shared home
  decoration cap. Projectiles and bursts pause/resume together; New Game kills
  pending effect callbacks and clears the previous village's effects.
- Navigation memo keys use path topology revisions. Friendly road-weight changes
  no longer churn enemy routes, and gate closure invalidates cached edge goals.
- Manor Studio editor extension: staged building/tier balance forms, explicit
  Apply/Discard, full-precision numeric handling, previous-content backup,
  cooperating-writer lock and optimistic external-change checks. No engine fork
  or gameplay save writes; see `addons/manor_studio/README.md`.
- Home raid stars and loot: Hall = 1 star, 50% destruction = 1 star, 100% = 1 star;
  walls/traps excluded, denominator fixed at raid start. Resource raiders steal
  up to 20% of starting Wood/Food/Gold, saved and capped per site. Live HUD shows
  stars/destruction; defense report lists stars, damage and stolen goods.

## Fresh Verification

| Suite | Checks | Failures |
| --- | ---: | ---: |
| Village | 96 | 0 |
| Game scene | 20 | 0 |
| Workers/defense | 191 | 0 |
| Living village | 45 | 0 |
| Update2 scene | 93 | 0 |
| Chronicle | 221 | 0 |
| Overhaul foundation | 99 | 0 |
| Village needs | 29 | 0 |
| Frontier battles | 40 | 0 |
| Campaign actions | 27 | 0 |
| Combat VFX | 42 | 0 |
| Raid navigation cache | 7 | 0 |
| Manor Studio | 63 | 0 |
| Home raid scoring | 31 | 0 |
| Total | 1004 | 0 |

All suites exited 0 using the Godot 4.7.2 console binary with `--headless` and
`--no-save`. Four Python tests and both asset checks passed all 310 assets.
Latest native captures passed: foundation 111, combat VFX 44, Studio 64 and raid report 33.
The combat proof measured 2,291 changed pixels with ambience frozen. Frontier
images predate the latest pool lifecycle tests; they are not fresh VFX proof.
Screenshots in docs/previews include inspectors, Chart, needs, shop, village
overview and frontier at phone/desktop sizes. They are fixtures, never player saves.

An earlier QA PCK passed packed campaign/frontier/needs checks. That package
predates the current combat pool, navigation and Studio changes and has not been
re-exported in this pass. It is not a playable HTML/WebAssembly export.

Native desktop profiling (`docs/raid_profile_observed.json`) completed a real
first Horn raid in a fresh, save-isolated village without health/resource grants.
Combat median was 33.341 ms, p95 34.869 ms, maximum 35.737 ms; the largest sampled
frame was 68.199 ms during warning. Worst simulation tick was 8.777 ms and worst
route search 2.813 ms. Twelve burst emitters were allocated, peak live effects
four and peak combat draw calls 443. This is one desktop observation, not a
speedup comparison or phone/browser certification; no GPU readbacks occurred
during sampling.

Editor loading registered `MANOR_STUDIO READY buildings=63`. Studio persistence
and native form tests use scratch files and leave real balance data untouched.

## Remaining Gates

- Complete all ten acts using ordinary resources/actions, then balance needs,
  training, raids, research timing and expedition difficulty. The fixture suites
  deliberately isolate behaviors; they do not establish this playthrough.
- Frontier maps now place a second region landmark plus wall/tower/grove props
  from existing GLBs at edge positions clear of both spawns (verified in
  overhaul-frontier-1280.png). Full bespoke regional art remains future work;
  no new assets were imported and original Blender sources are untouched.
- Shutdown diagnostics remain: the final headless suites reported 10-16 leaked
  ObjectDB instances in several scene fixtures. Editor import/exit reported
  twelve instances and five resources still in use. Process exits were zero,
  but these warnings/errors are unresolved and not proof of leak-free gameplay.
- The final editor import also emitted socket-probe errors from the existing
  Funplay MCP plugin. Studio still registered all 63 buildings; the MCP errors
  and unavailable editor RPC methods were not repaired in this scoped pass.
- The sealed-hall siege fix and navigation memo regressions pass. Additional
  raid sizes, campaign balance and the warning-frame hitch need investigation;
  the first-wave profile is not comprehensive stress testing.
- Studio's lock protects cooperating Studio writers. Godot's file APIs do not
  offer atomic compare-and-replace against arbitrary external editors; avoid
  simultaneous external writes during Apply. Quest/troop/map tools are deferred.
- Install matching web export templates, smoke-test an actual browser build and
  validate Safari/touch/performance on real devices. Phone-sized native windows
  are not evidence of stable 30 FPS on a phone.
- No commit, push or deployment occurred. No Blender source writes or paid
  asset/material generation were performed. A bounded read-only code review
  identified numeric precision issues; failing regressions reproduced them
  before the fixes. All thirteen final GDScript suites exited zero.
