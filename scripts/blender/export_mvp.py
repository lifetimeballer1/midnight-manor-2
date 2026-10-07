"""Export copies from a multi-scene library; never save or modify its source file.

blender --factory-startup --disable-autoexec -b SOURCE --python-exit-code 1
        --python scripts/blender/export_mvp.py -- [--pilot]
"""
import hashlib
import json
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'art'
BUILDINGS = [
    ('manor_hall', 'hall'), ('cottage', 'cottage'), ('farm', 'farm'),
    ('lumber', 'lumber'), ('timber_yard', 'timber_yard'), ('mine', 'mine'),
    ('tower', 'tower'), ('archer_tower', 'archer_tower'), ('wall', 'wall'),
    ('stonewall', 'stonewall'), ('gate', 'gate'), ('trap', 'trap'),
    ('fire_trap', 'fire-trap'), ('storehouse', 'storehouse'),
    ('barracks', 'barracks'), ('forge', 'forge'), ('market', 'market'),
    ('pasture', 'pasture'), ('pond', 'pond'), ('sawmill', 'sawmill'),
    ('mill', 'mill'), ('scriptorium', 'scriptorium'), ('oathstone', 'oathstone'),
    ('grove', 'grove'), ('frostgrove', 'frostgrove'),
    ('whisper-grove', 'whisper-grove'), ('chapel', 'chapel'),
    ('sunken-chapel', 'sunken-chapel'), ('schoolroom', 'schoolroom'),
    ('armory', 'armory'), ('workshop', 'workshop'), ('smeltery', 'smeltery'),
    ('tannery', 'tannery'), ('butchery', 'butchery'), ('bakery', 'bakery'),
    ('mason_yard', 'mason_yard'), ('emberglass', 'emberglass'),
    ('fletcher', 'fletcher'), ('scout_post', 'scout_post'),
    ('watchfire', 'watchfire'), ('ballista', 'ballista'),
    ('bastion', 'bastion'), ('rampart', 'rampart'), ('longhouse', 'longhouse'),
    ('bellcote', 'bellcote'), ('bell-tower', 'bell-tower'),
    ('blackwater-weir', 'blackwater-weir'), ('deephole', 'deephole'),
    ('cairnfield', 'cairnfield'), ('moon-dial', 'moon-dial'),
    ('dawn-gate', 'dawn-gate'),
]
WORK = {
    'builder': 'Hammering', 'warrior': 'Melee_1H_Attack_Chop',
    'archer': 'Ranged_Bow_Draw', 'farmer': 'Digging',
    'lumberjack': 'Chopping', 'miner': 'Pickaxing',
    'fisherman': 'Fishing_Reeling', 'shepherd': 'Working_A',
    'diver': 'Fishing_Reeling', 'sapper': 'Pickaxing', 'smelter': 'Working_B',
    'forager': 'Working_A', 'miller': 'Sawing', 'butcher': 'Chopping',
    'haggler': 'Use_Item', 'heartwarden': 'Chopping', 'healer': 'Use_Item',
    'chorister': 'Use_Item', 'sawyer': 'Sawing', 'woodward': 'Chopping',
    'halberdier': 'Melee_2H_Attack_Chop', 'pikewoman': 'Melee_2H_Attack_Chop',
    'oathsworn': 'Melee_1H_Attack_Chop', 'warden': 'Melee_1H_Attack_Chop',
    'squire': 'Melee_1H_Attack_Chop', 'weaponsmith': 'Hammering',
    'armorer': 'Hammering', 'toolsmith': 'Working_B', 'mason': 'Hammering',
    'apprentice': 'Working_A', 'scholar': 'Use_Item',
    'leatherworker': 'Working_A', 'ranger': 'Ranged_Bow_Draw',
    'longbowman': 'Ranged_Bow_Draw', 'scout': 'Use_Item',
    'mudlark': 'Working_A', 'tidecaller': 'Use_Item',
}
ATTACK_FROM = {
    'warrior': 'Melee_1H_Attack_Chop', 'archer': 'Ranged_Bow_Release',
    'halberdier': 'Melee_2H_Attack_Chop', 'pikewoman': 'Melee_2H_Attack_Chop',
    'oathsworn': 'Melee_1H_Attack_Chop', 'warden': 'Melee_1H_Attack_Chop',
    'squire': 'Melee_1H_Attack_Chop', 'ranger': 'Ranged_Bow_Draw',
    'longbowman': 'Ranged_Bow_Draw',
}


def glb_json(path):
    with path.open('rb') as handle:
        magic, version, length = struct.unpack('<4sII', handle.read(12))
        assert magic == b'glTF' and version == 2 and length == path.stat().st_size
        size, kind = struct.unpack('<I4s', handle.read(8))
        assert kind == b'JSON'
        return json.loads(handle.read(size))


def export(stem, sources, clips=None):
    # Selection in the source's active view layer does not include assets in
    # other hidden scenes. Export an isolated scene, with no catalogue objects.
    previous = bpy.context.window.scene
    source_scene = next(s for s in bpy.data.scenes if sources[0].name in s.objects)
    bpy.context.window.scene = source_scene
    source_deps = bpy.context.evaluated_depsgraph_get()
    scene = bpy.data.scenes.new('MM2 Export Scratch ' + stem)
    scene.render.fps = 30
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    bpy.context.window.scene = scene
    copies = {}
    matrices = {s.name: s.matrix_world.copy() for s in sources}
    try:
        for source in sources:
            clone = source.copy()
            if not clips and source.type == 'MESH':
                # Gate/trap parts reference a catalogue-wide mechanism rig.
                # Bake their current shape into copies instead of importing it.
                clone.data = bpy.data.meshes.new_from_object(source.evaluated_get(source_deps),
                    preserve_all_data_layers=True, depsgraph=source_deps)
                clone.modifiers.clear()
                clone.constraints.clear()
            else:
                clone.data = source.data.copy()
            clone.animation_data_clear()
            clone.hide_viewport = False
            clone.hide_render = False
            clone.hide_select = False
            scene.collection.objects.link(clone)
            clone.hide_set(False)
            copies[source.name] = clone
        rig = next((c for c in copies.values() if c.type == 'ARMATURE'), None)
        for source in sources:
            clone = copies[source.name]
            clone.parent = copies.get(source.parent.name) if source.parent else None
            clone.matrix_world = matrices[source.name]
            for modifier in clone.modifiers:
                if modifier.type == 'ARMATURE' and modifier.object:
                    modifier.object = copies[modifier.object.name]
            for constraint in clone.constraints:
                if hasattr(constraint, 'target') and constraint.target:
                    assert constraint.target.name in copies, 'External constraint: ' + source.name
                    constraint.target = copies[constraint.target.name]
        if rig:
            for bone in rig.pose.bones:
                bone.matrix_basis = Matrix.Identity(4)
            rig.data.pose_position = 'REST'
        scene.frame_set(0)
        bpy.context.view_layer.update()
        deps = bpy.context.evaluated_depsgraph_get()
        points = [c.matrix_world @ Vector(p) for c in copies.values() if c.type == 'MESH'
                  for p in c.evaluated_get(deps).bound_box]
        assert points, 'No geometry: ' + stem
        lo = Vector([min(p[i] for p in points) for i in range(3)])
        hi = Vector([max(p[i] for p in points) for i in range(3)])
        center = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
        offset = Matrix.Translation(-center)
        for source in sources:
            clone = copies[source.name]
            if clone.parent is None:
                clone.matrix_world = offset @ clone.matrix_world
        if rig:
            rig.data.pose_position = 'POSE'
            ad = rig.animation_data_create()
            for alias, action_name in clips.items():
                action = bpy.data.actions[action_name]
                assert len(action.slots) == 1, action_name
                track = ad.nla_tracks.new()
                track.name = alias
                strip = track.strips.new(alias, 0, action)
                strip.action_slot = action.slots[0]
            ad.use_nla = True
            # Work strips are muted for the bind pose; exporter samples tracks.
            for track in ad.nla_tracks:
                track.mute = True
        bpy.context.view_layer.update()
        folder = ART / stem
        folder.mkdir(parents=True, exist_ok=True)
        temporary = folder / (stem + '.pending.glb')
        target = folder / (stem + '.glb')
        result = bpy.ops.export_scene.gltf(
            filepath=str(temporary), export_format='GLB', use_active_scene=True,
            use_selection=False, use_visible=False, use_renderable=False,
            export_yup=True, export_apply=False,
            export_animations=bool(clips), export_animation_mode='NLA_TRACKS',
            export_force_sampling=True, export_frame_range=False,
            export_anim_slide_to_zero=True, export_anim_single_armature=False,
            export_extras=False,
        )
        assert 'FINISHED' in result
        doc = glb_json(temporary)
        expected_names = {c.name for c in copies.values() if c.type == 'MESH'}
        actual_names = {n.get('name') for n in doc.get('nodes', []) if 'mesh' in n}
        assert expected_names == actual_names, (stem, expected_names, actual_names)
        assert doc.get('meshes'), 'Empty GLB'
        animations = [a['name'] for a in doc.get('animations', [])]
        if clips:
            assert doc.get('skins'), 'Lost armature: ' + stem
            assert set(clips) == set(animations), (stem, clips, animations)
        assert doc.get('materials'), 'Lost materials'
        assert doc.get('images'), 'Lost palette texture'
        assert all('bufferView' in i for i in doc['images']), 'External texture dependency'
        triangles = sum(doc['accessors'][p['indices']]['count'] // 3
                        for mesh in doc['meshes'] for p in mesh['primitives'])
        dims = list(hi - lo)
        assert max(dims) <= 8.0, (stem, dims)
        temporary.replace(target)
        manifest = {
            'asset': stem, 'file': stem + '.glb', 'kind': 'character' if rig else 'building',
            'source_file': Path(bpy.data.filepath).name, 'source_objects': [s.name for s in sources],
            'pivot': 'base_center', 'units': 'metres', 'up_axis': '+Y',
            'dimensions_m': [dims[0], dims[2], dims[1]],
            'triangles': triangles, 'meshes': len(doc['meshes']),
            'materials': len(doc['materials']), 'images': len(doc['images']),
            'clips': animations, 'clip_sources': clips or {},
            'sha256': hashlib.sha256(target.read_bytes()).hexdigest(), 'verified': True,
        }
        (folder / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
        print('VERIFIED', stem, triangles, animations, flush=True)
        return manifest
    finally:
        bpy.context.window.scene = previous
        bpy.data.scenes.remove(scene)
        for clone in copies.values():
            data = clone.data
            bpy.data.objects.remove(clone, do_unlink=True)
            if data.users == 0:
                if isinstance(data, bpy.types.Mesh):
                    bpy.data.meshes.remove(data)
                elif isinstance(data, bpy.types.Armature):
                    bpy.data.armatures.remove(data)


def main():
    pilot = '--pilot' in sys.argv
    entries = []
    for stem, source_type in BUILDINGS:
        if pilot and stem != 'cottage':
            continue
        for tier in ([1] if pilot else range(1, 7)):
            root = bpy.data.objects.get('MMR | %s | Tier %02d' % (source_type, tier))
            if not root:
                continue
            parts = [c for c in root.children_recursive if c.type == 'MESH']
            entries.append(export('%s_t%d' % (stem, tier), parts))
    for role, work in WORK.items():
        if pilot and role != 'warrior':
            continue
        rig = bpy.data.objects['MMR Character | ' + role + ' Rig']
        parts = [rig] + [c for c in rig.children_recursive if c.type == 'MESH' and 'LOD1' not in c.name]
        clips = {'idle': 'Idle_A', 'walk': 'Walking_A', 'work': work, 'death': 'Death_A'}
        if role in ATTACK_FROM:
            clips['attack'] = ATTACK_FROM[role]
        else:
            clips['gather'] = work
        entries.append(export('char_' + role, parts, clips))
    if not pilot:
        (ART / 'catalog.json').write_text(json.dumps({'tile_size_m': 2, 'grid': [20, 16],
             'source': 'Game Assets.blend', 'assets': entries}, indent=2), encoding='utf-8')
    print('EXPORT_DONE', len(entries), flush=True)


if __name__ == '__main__':
    main()
