"""Drop nodes from a glTF (by name) and every mesh, material, texture and image nothing uses any more.
usage: python3 gltf_prune.py file.gltf node [node ...]"""
import json, sys
path, drop = sys.argv[1], set(sys.argv[2:])
g = json.load(open(path))
keep_nodes = [i for i, n in enumerate(g["nodes"]) if n.get("name") not in drop]
nmap = {o: i for i, o in enumerate(keep_nodes)}
nodes = [g["nodes"][i] for i in keep_nodes]
for n in nodes:
    if "children" in n:
        n["children"] = [nmap[c] for c in n["children"] if c in nmap]
for sc in g.get("scenes", []):
    sc["nodes"] = [nmap[c] for c in sc["nodes"] if c in nmap]
used_mesh = sorted({n["mesh"] for n in nodes if "mesh" in n})
mmap = {o: i for i, o in enumerate(used_mesh)}
for n in nodes:
    if "mesh" in n:
        n["mesh"] = mmap[n["mesh"]]
meshes = [g["meshes"][i] for i in used_mesh]
used_mat = sorted({p["material"] for m in meshes for p in m["primitives"] if "material" in p})
matmap = {o: i for i, o in enumerate(used_mat)}
for m in meshes:
    for p in m["primitives"]:
        if "material" in p:
            p["material"] = matmap[p["material"]]
mats = [g["materials"][i] for i in used_mat]


def tex_refs(o, acc):
    if isinstance(o, dict):
        for k, v in o.items():
            if k.endswith("Texture") and isinstance(v, dict) and "index" in v:
                acc.append(v)
            else:
                tex_refs(v, acc)
    elif isinstance(o, list):
        for v in o:
            tex_refs(v, acc)
    return acc


refs = tex_refs(mats, [])
used_tex = sorted({r["index"] for r in refs})
tmap = {o: i for i, o in enumerate(used_tex)}
for r in refs:
    r["index"] = tmap[r["index"]]
texs = [g["textures"][i] for i in used_tex]
used_img = sorted({t["source"] for t in texs})
imap = {o: i for i, o in enumerate(used_img)}
for t in texs:
    t["source"] = imap[t["source"]]
dropped_imgs = [g["images"][i]["uri"] for i in range(len(g["images"])) if i not in imap]
g.update(nodes=nodes, meshes=meshes, materials=mats, textures=texs, images=[g["images"][i] for i in used_img])
json.dump(g, open(path, "w"))
print("kept", len(nodes), "nodes; images no longer used:", dropped_imgs)
