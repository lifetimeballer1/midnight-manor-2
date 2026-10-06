import bpy
import json
import sys
from pathlib import Path

output = Path(sys.argv[sys.argv.index('--') + 1])
roles = ['builder', 'warrior', 'archer', 'farmer', 'lumberjack', 'miner', 'fisherman', 'shepherd']
report = {'version': bpy.app.version_string, 'scenes': {}, 'characters': {}, 'actions': [], 'export_options': {}}
for scene in bpy.data.scenes:
    report['scenes'][scene.name] = len(scene.objects)
for role in roles:
    rig = bpy.data.objects.get('MMR Character | ' + role + ' Rig')
    if not rig:
        continue
    ad = rig.animation_data
    report['characters'][role] = {
        'bones': [b.name for b in rig.data.bones],
        'action': ad.action.name if ad and ad.action else None,
        'slot': ad.action_slot.identifier if ad and ad.action_slot else None,
        'nla': [{'track': t.name, 'strips': [{'name': s.name, 'action': s.action.name if s.action else None,
                 'slot': s.action_slot.identifier if s.action_slot else None} for s in t.strips]} for t in ad.nla_tracks] if ad else [],
        'meshes': [{'name': c.name, 'hide': c.hide_viewport, 'render_hide': c.hide_render,
                    'modifiers': [(m.type, m.object.name if m.type == 'ARMATURE' and m.object else '') for m in c.modifiers],
                    'dims': list(c.dimensions), 'groups': len(c.vertex_groups)} for c in rig.children_recursive if c.type == 'MESH'],
        'properties': {k: str(v) for k, v in rig.items()},
    }
for action in bpy.data.actions:
    report['actions'].append({'name': action.name, 'range': list(action.frame_range),
                              'slots': [s.identifier for s in action.slots]})
for p in bpy.ops.export_scene.gltf.get_rna_type().properties:
    if p.identifier.startswith(('export_animation', 'export_anim', 'export_nla', 'export_force', 'export_bake', 'use_')):
        report['export_options'][p.identifier] = {'type': p.type, 'default': str(getattr(p, 'default', '')),
            'choices': [e.identifier for e in p.enum_items] if p.type == 'ENUM' else []}
output.write_text(json.dumps(report, indent=2), encoding='utf-8')
print('AUDIT_OK', output.name, flush=True)
