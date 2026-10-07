"""Independent, standard-library check of exported GLBs and their manifests."""
import hashlib
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1]


def validate(path, manifest):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from('<4sII', raw)
    assert magic == b'glTF' and version == 2 and length == len(raw), 'Invalid GLB header'
    size, kind = struct.unpack_from('<I4s', raw, 12)
    assert kind == b'JSON', 'Missing GLB JSON chunk'
    doc = json.loads(raw[20:20 + size])
    assert hashlib.sha256(raw).hexdigest() == manifest['sha256'], 'GLB hash mismatch'
    mesh_nodes = [n for n in doc['nodes'] if 'mesh' in n]
    source_meshes = [s for s in manifest['source_objects'] if not s.endswith(' Rig')]
    assert len(mesh_nodes) == len(source_meshes), 'Wrong number of source parts'
    for source in source_meshes:
        assert any(re.fullmatch(re.escape(source) + r'(?:\.\d+)?', n['name']) for n in mesh_nodes), 'Wrong exported object: ' + source
    assert all('LOD1' not in n['name'] for n in mesh_nodes), 'Accidental LOD overlay'
    triangles = sum(doc['accessors'][p['indices']]['count'] // 3
                    for mesh in doc['meshes'] for p in mesh['primitives'])
    assert triangles == manifest['triangles'] and triangles > 0, 'Wrong geometry count'
    assert len(doc['meshes']) == manifest['meshes'], 'Mesh count mismatch'
    assert len(doc['materials']) == manifest['materials'], 'Material count mismatch'
    assert len(doc['images']) == manifest['images'], 'Image count mismatch'
    assert all('bufferView' in i and not i.get('uri') for i in doc['images']), 'Missing embedded image'
    assert set(a['name'] for a in doc.get('animations', [])) == set(manifest['clips']), 'Clip set mismatch'
    if manifest['kind'] == 'character':
        assert doc.get('skins'), 'Missing skeleton'
        assert any('skin' in n for n in mesh_nodes), 'Lost mesh skin bindings'
        assert all(a.get('channels') and a.get('samplers') for a in doc['animations']), 'Empty clip'
    assert max(manifest['dimensions_m']) <= 8, 'Excessive dimensions'
    assert manifest['units'] == 'metres' and manifest['up_axis'] == '+Y', 'Wrong unit/axis contract'
    return {'asset': manifest['asset'], 'triangles': triangles, 'bytes': len(raw), 'passed': True}


def main():
    catalog = json.loads((ROOT / 'art/catalog.json').read_text(encoding='utf-8'))
    declared = {entry['asset'] for entry in catalog['assets']}
    assert len(declared) == len(catalog['assets']) == 310, 'Catalog count/duplicates'
    disk = {p.parent.name for p in (ROOT / 'art').glob('*/*.glb')}
    assert disk == declared, 'Uncatalogued or missing GLB: ' + str(disk ^ declared)
    records = []
    for entry in catalog['assets']:
        folder = ROOT / 'art' / entry['asset']
        manifest = json.loads((folder / 'manifest.json').read_text(encoding='utf-8'))
        assert manifest == entry, 'Catalog manifest mismatch'
        records.append(validate(folder / manifest['file'], manifest))
    assert len({r['asset']: r for r in records}) == 310
    report = {'passed': True, 'assets': len(records), 'bytes': sum(r['bytes'] for r in records), 'records': records}
    (ROOT / 'docs/export_verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('EXPORT_CHECK PASS assets=%d bytes=%d' % (len(records), report['bytes']))


if __name__ == '__main__':
    main()
