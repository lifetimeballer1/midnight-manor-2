import json, struct, sys, os

def read_gltf_json(path):
    with open(path, 'rb') as f:
        magic, ver, length = struct.unpack('<III', f.read(12))
        clen, ctype = struct.unpack('<II', f.read(8))
        j = json.loads(f.read(clen).decode('utf-8'))
        return j

targets = sys.argv[sys.argv.index('--') + 1:]
for t in targets:
    p = t if os.path.exists(t) else None
    if not p:
        print(t, "MISSING"); continue
    try:
        j = read_gltf_json(p)
        print("%-28s meshes=%-3d nodes=%-3d anims=%-3d mats=%-2d imgs=%-2d size=%d" % (
            os.path.basename(os.path.dirname(p)) + "/" + os.path.basename(p),
            len(j.get('meshes', [])), len(j.get('nodes', [])),
            len(j.get('animations', [])), len(j.get('materials', [])),
            len(j.get('images', [])), os.path.getsize(p)))
        names = [n.get('name', '?') for n in j.get('nodes', [])][:6]
        print("      nodes:", names)
    except Exception as e:
        print(t, "ERR", e)