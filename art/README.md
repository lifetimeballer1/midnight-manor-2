# Godot Art Catalog

Authoritative source: `Game Assets.blend`, exported with Blender 5.2.2.

`catalog.json` lists 133 verified deliveries: 125 building tiers and eight characters. Each folder contains its GLB and a manifest. Palette textures are embedded. Old optional `textures/` files are not required to load the GLBs.

- Units: metres; axis: +Y up; pivot: base centre; Godot import scale: 1.
- Grid: 20 x 16, 2 m tiles. Native footprints are preserved, not forced into one tile.
- Building meshes retain separate supports and moving parts. They are static snapshots, not animated mechanism exports.
- Character rigs retain skinning and five clips each. `LOD1 Body` duplicates are excluded.
- Geometry, materials, source mesh names, embedded images and hashes are checked by `scripts/verify_assets.py`.
- Godot load/scale/animation validation is in `scripts/ArtCheck.gd`.
- All exported bounds fit the 8 m limit. Character rest heights, including tools, range about 1.54-1.83 m. Native stylized proportions are retained.
- The representative static layout stays below 30,000 triangles through T06. This is not a per-file or whole-game performance guarantee.

Use only entries in `catalog.json`. It supersedes the early Mixar inventory, which surveyed other tabs and incorrectly classified some assets as missing. No source `.blend` or `.mixar` is stored here.
