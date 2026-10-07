"""Finalize a Mixar-exported GLB into game-ready art; never touches any source file.

Replicates the export_mvp.py delivery contract for assets whose source is the
Game Assets.mixar project instead of the .blend: base-centered pivot, metres,
+Y up, embedded palette, NLA-free game-named clips for characters.

blender --factory-startup --disable-autoexec -b --python-exit-code 1
        --python scripts/blender/finalize_mixar.py -- RAW OUT STEM KIND [ROLE]
KIND is building or character. ROLE marks combat roles (attack clip).
"""
import json
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

COMBAT = {'halberdier', 'pikewoman', 'oathsworn', 'warden', 'squire',
          'ranger', 'longbowman', 'warrior', 'archer'}


def process(raw, out, stem, kind, role, tier_root, summary):
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=raw, merge_vertices=False)
    if tier_root:
        keep = bpy.data.objects.get(tier_root)
        assert keep is not None, 'Tier root missing: ' + tier_root
        keep_set = {keep} | set(keep.children_recursive)
        for ob in list(bpy.data.objects):
            if ob not in keep_set:
                bpy.data.objects.remove(ob, do_unlink=True)
    tops = [o for o in bpy.context.scene.objects if o.parent is None]
    assert tops, 'Empty import: ' + stem
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    assert meshes, 'No geometry: ' + stem
    deps = bpy.context.evaluated_depsgraph_get()
    points = [o.matrix_world @ Vector(p) for o in meshes
              for p in o.evaluated_get(deps).bound_box]
    lo = Vector([min(p[i] for p in points) for i in range(3)])
    hi = Vector([max(p[i] for p in points) for i in range(3)])
    offset = Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))
    for ob in tops:
        ob.location = ob.location + offset
    clips = []
    if kind == 'character':
        rig = next((o for o in bpy.data.objects if o.type == 'ARMATURE'), None)
        assert rig is not None, 'Lost armature: ' + stem
        for bone in rig.pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
        rig.data.pose_position = 'REST'
        if rig.animation_data:
            rig.animation_data_clear()
        renamed = {}
        for action in list(bpy.data.actions):
            upper = action.name.upper()
            target = ''
            if 'IDLE' in upper:
                target = 'idle'
            elif 'WALK' in upper:
                target = 'walk'
            elif 'DEATH' in upper:
                target = 'death'
            elif 'ATTACK' in upper or 'MELEE' in upper or 'RANGED' in upper or 'BOW' in upper:
                target = 'attack'
            elif 'WORK' in upper or 'HAMMER' in upper or 'CHOP' in upper or 'DIG' in upper or 'FISH' in upper \
                    or 'SAW' in upper or 'PICKAX' in upper or 'USE_ITEM' in upper or 'REEL' in upper:
                target = 'work'
            if target and target not in renamed:
                action.name = '%s_%s' % (stem, target)
                renamed[target] = action
            elif target:
                bpy.data.actions.remove(action)
            else:
                bpy.data.actions.remove(action)
        for key in ['idle', 'walk', 'work', 'death']:
            assert key in renamed, 'No %s action: %s' % (key, stem)
        if role in COMBAT and 'attack' in renamed:
            clips = ['idle', 'walk', 'work', 'death', 'attack']
        else:
            if 'attack' in renamed:
                bpy.data.actions.remove(renamed.pop('attack'))
            extra = renamed['work'].copy()
            extra.name = '%s_gather' % stem
            clips = ['idle', 'walk', 'work', 'death', 'gather']
        keep = {'%s_%s' % (stem, c) for c in clips}
        for action in list(bpy.data.actions):
            if action.name not in keep:
                bpy.data.actions.remove(action)
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    result = bpy.ops.export_scene.gltf(
        filepath=str(out), export_format='GLB', use_selection=False,
        export_yup=True, export_apply=False,
        export_animations=(kind == 'character'),
        export_animation_mode='ACTIONS',
        export_force_sampling=True, export_frame_range=False,
        export_extras=False,
    )
    assert 'FINISHED' in result
    dims = [hi.x - lo.x, hi.z - lo.z, hi.y - lo.y]
    sources = sorted({o.name for o in meshes})
    summary[stem] = {'dims': dims, 'clips': clips, 'meshes': len(meshes),
                     'sources': sources, 'kind': kind}
    print('FINALIZED', json.dumps({'stem': stem, 'dims': dims, 'clips': clips,
          'meshes': len(meshes)}), flush=True)


def main():
    args = sys.argv[sys.argv.index('--') + 1:]
    if args[0] == '@batch':
        jobs = json.loads(Path(args[1]).read_text(encoding='utf-8'))
        summary_path = Path(args[2])
        summary = {}
        for job in jobs:
            process(job['raw'], job['out'], job['stem'], job['kind'],
                    job.get('role', ''), job.get('tier_root', ''), summary)
        summary_path.write_text(json.dumps(summary, indent=2), encoding='utf-8')
        print('BATCH_DONE', len(summary), flush=True)
    else:
        raw, out, stem, kind = args[0], args[1], args[2], args[3]
        role = args[4] if len(args) > 4 else ''
        process(raw, out, stem, kind, role, '', {})


if __name__ == '__main__':
    main()
