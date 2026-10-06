# Plan 1 Delivery

## Result

Completed the Blender-source inventory, GLB export pipeline and Godot asset-import test scene. Source is the user-specified `Game Assets.blend`; it was read in separate background Blender 5.2.2 processes and never saved. Manor 1 was not changed.

- 133 GLBs, about 19.37 MB total: 125 building tiers across 23 types, eight characters.
- 40 character clips total: five each, drawn from the source animation library.
- Embedded palette textures, valid skinning, base-centred metre scale and +Y up.
- Godot 4.7.2 Compatibility-renderer test scene with a 20x16 board, 2m tiles.
- Asset catalog, per-file manifests, independent checks, Godot checks and saved preview images.

## Verification Evidence

| Check | Observed Result |
|---|---|
| Blender exports | EXPORT_DONE 133; per-asset mesh/material/image/clip checks passed |
| Independent file checker | EXPORT_CHECK PASS assets=133 bytes=19371456 |
| Positive/negative Python tests | 4 passed, including rejection of unrelated forge mesh |
| Godot headless editor import | Completed without errors |
| Godot ArtCheck | PASS assets=133 failures=0 |
| Character clip samples | All 40 have keyed tracks and changing bone poses and skinned vertices |
| Base/scale | All buildings centered at ground within 0.02m; all bounds <=8m |
| Sample static budget | 19,136 triangles at T01; 29,468 at T06, including board/grid/rim |
| Screenshots | Overview, characters and 360x800 portrait saved and visually inspected |
| Final review | Actual GPT-6 Luna read-only review: spec PASS |

Commands are documented in README.md. Machine-readable results are `export_verification.json` and `godot_verification.json`.

## Resolved Problems

The initial Mixar inventory surveyed incomplete tabs and incorrectly marked characters and animations missing. Reading the `.blend` revealed the full library. The first background export also selected the wrong scene's forge banner pole. The replacement pipeline copies each requested assembly into an isolated scene, re-centres it at ground level, and checks the emitted mesh names before replacing generated files. All earlier incorrect exports in the project were regenerated. Negative tests protect against the observed failure.

## Decisions And Caveats

- `hall` maps to the manor. Replacing that choice only changes the art mapping.
- Delivered the already-expanded tier batch plus eight MVP characters; this is not every object in the library.
- Kept native character proportions (about 1.54-1.83m including tools), rather than artificially scaling to a provisional uniform-height band.
- Building mechanism meshes stay separate, but are static snapshots. Their Godot motion remains a gameplay-phase task.
- The independent checker verifies source mesh names, counts, embedded images, clip sets and file hashes. It does not prove vertex-for-vertex equality with the source. Godot additionally verifies actual imported geometry and sampled deformation.
- The sample budget excludes characters and label glyphs; it is not a full-game frame-rate claim.
- Narrow UI wraps, but the asset lineup becomes small. Touch controls and real-device/browser performance are not implemented/tested here.
- Equipment/enemy coverage and licensing/attribution are not complete.

## Handoff

Run `project.godot` to inspect the art and clips. Next implementation phase is the same-feel GDScript core-loop port: camera/input parity, grid placement, capped economy reserves, worker assignment, raids, quests and versioned saves. This delivery is not a playable village simulation or a deployed web game.
