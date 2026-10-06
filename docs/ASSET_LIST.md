# Verified Asset Inventory

Authoritative source: the user-provided `Game Assets.blend`, read with Blender 5.2.2. It contains four scenes, 5,811 objects, 93 armatures and 119 action datablocks. Earlier claims of missing troops or no animations came from surveying incomplete Mixar tabs; they are superseded by this source-file audit.

Exported coverage: 125 building tiers across 23 types and eight characters, 133 GLBs total. Only this verified subset has been delivered, not every object or animation in the source library. Dimensions, exact source object names, triangles and clip mappings are recorded in `art/catalog.json` and each asset's manifest. All exported bounds are <=8 m.

## Buildings

All rows are exported and pass Godot import validation. IDs match folder names before the `_tN` suffix.

| ID | Source Type | Exported Tiers |
|---|---|---|
| manor_hall | hall | 1-6 |
| cottage | cottage | 1-6 |
| farm | farm | 1-6 |
| lumber | lumber | 1-6 |
| timber_yard | timber_yard | 1-6 |
| mine | mine | 1-6 |
| tower | tower | 1-6 |
| archer_tower | archer_tower | 1-6 |
| wall | wall | 1-6 |
| stonewall | stonewall | 1-6 |
| gate | gate | 1-6 |
| trap | trap | 1-3 |
| fire_trap | fire-trap | 1 |
| storehouse | storehouse | 1-6 |
| barracks | barracks | 1-6 |
| forge | forge | 1-6 |
| market | market | 1-6 |
| pasture | pasture | 1-6 |
| pond | pond | 1-6 |
| sawmill | sawmill | 1-6 |
| mill | mill | 1-6 |
| scriptorium | scriptorium | 1-6 |
| oathstone | oathstone | 1 |

The `hall` is the manor mapping for this delivery. Building motion is not exported: shared mechanism rigs would bring unrelated catalog parts along. Gate lift, saw blade, wind rotor and water-wheel meshes remain separate for later Godot animation.

## Characters And Animations

Every character uses `MMR Character | <role> Rig` plus its body, wrist connections, held tool and shield when present. The hidden LOD1 duplicate is excluded. Five clips per character pass keyed-track, bone-pose and skinned-vertex motion tests in Godot.

| ID | Work Source Action | Fifth Clip |
|---|---|---|
| char_builder | Hammering | gather |
| char_warrior | Melee_1H_Attack_Chop | attack |
| char_archer | Ranged_Bow_Draw | attack (Ranged_Bow_Release) |
| char_farmer | Digging | gather |
| char_lumberjack | Chopping | gather |
| char_miner | Pickaxing | gather |
| char_fisherman | Fishing_Reeling | gather |
| char_shepherd | Working_A | gather |

Shared clip mappings: `idle` -> `Idle_A`, `walk` -> `Walking_A`, `death` -> `Death_A`. Civilian gather aliases reuse work. No new animation has been generated. Measured native rest heights including tools are approximately 1.54-1.83 m; they are not normalized to an arbitrary humanoid size.

## Limits

- Not all 31 equipment archetypes or all professions/enemies are exported yet. These eight character deliveries include their held default gear, not a complete standalone equipment catalog.
- Building tiers preserve the provided source designs. Import checks prove correct geometry, not that every tier is an artistically distinct redesign.
- Native building widths differ. Grid footprint mapping and seamless wall joins still need gameplay implementation and contact tests.
- Support samples are aggregate rest bounds against ground, not per-foot or animated collision proofs.
- Licensing/attribution for the user-supplied library has not been audited.
- Desktop import/capture tests do not prove web/mobile compatibility or performance.
