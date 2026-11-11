"""Bring a downloaded gun model into the game's own layout: metres, the top of the pistol grip at the origin, the
barrel along +z, up +y (so the right side is -x); parts that are not the gun itself (spare magazines, loose rounds)
left out; one mesh per material, simplified to a budget; colour, normal and metal/roughness textures as JPEG; a
"muzzle" node at the end of the barrel. Writes <out>/<key>/<key>.gltf, its .bin and textures.
usage: gun_convert.py <src dir with the .glb files> <out dir> [key ...]"""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import meshoptimizer as mo
from gunlib import load

# axes: rows give game x, y, z from the model's x, y, z. origin: the model's point that becomes the game's origin.
# keep: which triangles to keep, from their centre in the model's own coordinates. muzzle: the model's muzzle point.
YAW180 = [[-1, 0, 0], [0, 1, 0], [0, 0, -1]]      # barrel along -z in the model
XFWD = [[0, 0, -1], [0, 1, 0], [1, 0, 0]]         # barrel along +x, up y
XFWD_ZUP = [[0, 1, 0], [0, 0, 1], [1, 0, 0]]      # barrel along +x, up z
GUNS = {
    "ak": dict(file="ak47.glb", axes=YAW180, scale=0.0938, origin=(0.0, 0.39, 1.5), muzzle=(0.0, 0.66, -4.75), tris=3400,
               keep=lambda c: (c[:, 0] > -0.6) & (c[:, 1] < 1.5),
               credit="Ak47 by wburton (sketchfab.com/wburton95), CC BY 4.0"),
    "m4": dict(file="m4a1.glb", axes=XFWD, scale=0.9, origin=(-0.116, 0.033, -0.012), muzzle=(0.475, 0.09, -0.012), tris=3000,
               credit="Gun M4A1 by Ivan008 (sketchfab.com/hukan008), CC BY 4.0"),
    "pistol": dict(file="hand_gun.glb", axes=XFWD_ZUP, scale=0.0321, origin=(-0.5, -0.06, -0.9), muzzle=(7.04, -0.06, -0.45), tris=7000,
                   credit="Hand Gun by lifza (sketchfab.com/lifza), CC BY 4.0"),
    "badger": dict(file="honey_badger.glb", axes=YAW180, scale=0.2195, origin=(0.0, -0.267, 0.48), muzzle=(0.0, -0.062, -1.64), tris=8000,
                   credit="Honey Badger Gun by MDTOWERZ (sketchfab.com/mdtowerz), CC BY 4.0"),
    "smg": dict(file="submachine.glb", axes=XFWD, scale=0.0058, origin=(-7.0, 3.0, 0.0), muzzle=(40.05, 8.1, 0.0), tris=8400,
                credit="Submachine Gun by J.J.West (sketchfab.com/jw202471), CC BY 4.0"),
}
src, out = sys.argv[1], sys.argv[2]
for key in (sys.argv[3:] or list(GUNS)):
    cfg = GUNS[key]
    g, parts, image = load(os.path.join(src, cfg["file"]))
    A = np.array(cfg["axes"], float); s = cfg["scale"]; o = np.array(cfg["origin"], float)
    per = {}
    for name, mat, pos, nor, uv, idx in parts:
        tri = idx.reshape(-1, 3)
        if "keep" in cfg:
            tri = tri[cfg["keep"](pos[tri].mean(1))]
        d = per.setdefault(mat, [[], [], [], [], 0])
        d[0].append((pos - o) @ A.T * s); d[1].append(nor @ A.T); d[2].append(uv); d[3].append(tri.reshape(-1) + d[4]); d[4] += len(pos)
    total = sum(sum(len(x) for x in d[3]) for d in per.values()) // 3
    od = os.path.join(out, key); os.makedirs(os.path.join(od, "textures"), exist_ok=True)
    bout = bytearray(); views, accs, prims, mats, texs, imgs = [], [], [], [], [], []
    def put(arr, target, typ, comp, minmax=False):
        while len(bout) % 4: bout.append(0)
        raw = np.ascontiguousarray(arr).tobytes()
        views.append({"buffer": 0, "byteOffset": len(bout), "byteLength": len(raw), "target": target}); bout.extend(raw)
        a = {"bufferView": len(views) - 1, "componentType": comp, "count": int(len(arr)), "type": typ}
        if minmax: a["min"] = [float(x) for x in arr.min(0)]; a["max"] = [float(x) for x in arr.max(0)]
        accs.append(a); return len(accs) - 1
    done = {}
    def tex(ti, kind, mi):
        srci = g["textures"][ti]["source"]
        if (srci, kind) not in done:
            name = "%s_%d_%s.jpg" % (key, mi, kind)
            im = image(ti).convert("RGB")
            if max(im.size) > 1024: im = im.resize((1024, 1024))
            im.save(os.path.join(od, "textures", name), quality=90)
            imgs.append({"uri": "textures/" + name}); texs.append({"source": len(imgs) - 1}); done[(srci, kind)] = len(texs) - 1
        return done[(srci, kind)]
    tout = 0
    for mi, d in per.items():
        pos = np.concatenate(d[0]).astype(np.float32); nor = np.concatenate(d[1]).astype(np.float32)
        nor /= np.maximum(np.linalg.norm(nor, axis=1, keepdims=True), 1e-9)
        uv = np.concatenate(d[2]); idx = np.concatenate(d[3]).astype(np.uint32)
        target = max(90, int(len(idx) * cfg["tris"] / max(total, 1)) // 3 * 3)
        if len(idx) > target * 1.05:
            dst = np.zeros(len(idx), dtype=np.uint32)
            n = mo.simplify(dst, idx, pos, target_index_count=target, target_error=0.01)
            if n > target * 1.4:
                keyv = np.round(pos * 20000.0).astype(np.int64)
                _, first, inv = np.unique(keyv, axis=0, return_index=True, return_inverse=True)
                widx = inv.reshape(-1)[idx].astype(np.uint32)
                n = mo.simplify(dst, widx, pos[first], target_index_count=target, target_error=0.02)
                idx = first[dst[:n]].astype(np.uint32)
            else:
                idx = dst[:n].astype(np.uint32)
        used, new = np.unique(idx, return_inverse=True); tout += len(idx) // 3
        sm = g["materials"][mi] if g.get("materials") else {}
        pm = sm.get("pbrMetallicRoughness", {})
        m = {"name": "%s_%d" % (key, mi), "pbrMetallicRoughness": {"metallicFactor": pm.get("metallicFactor", 1.0), "roughnessFactor": pm.get("roughnessFactor", 1.0)}}
        if "baseColorFactor" in pm: m["pbrMetallicRoughness"]["baseColorFactor"] = pm["baseColorFactor"]
        if "baseColorTexture" in pm: m["pbrMetallicRoughness"]["baseColorTexture"] = {"index": tex(pm["baseColorTexture"]["index"], "diff", mi)}
        if "metallicRoughnessTexture" in pm:
            t = tex(pm["metallicRoughnessTexture"]["index"], "orm", mi)
            m["pbrMetallicRoughness"]["metallicRoughnessTexture"] = {"index": t}
        else:
            m["pbrMetallicRoughness"]["metallicFactor"] = min(m["pbrMetallicRoughness"]["metallicFactor"], 0.6)
            m["pbrMetallicRoughness"]["roughnessFactor"] = 0.55
        if "normalTexture" in sm: m["normalTexture"] = {"index": tex(sm["normalTexture"]["index"], "nor", mi)}
        if sm.get("doubleSided"): m["doubleSided"] = True
        mats.append(m)
        prims.append({"attributes": {"POSITION": put(pos[used], 34962, "VEC3", 5126, True), "NORMAL": put(nor[used], 34962, "VEC3", 5126), "TEXCOORD_0": put(uv[used], 34962, "VEC2", 5126)},
                      "indices": put(new.astype(np.uint32).reshape(-1), 34963, "SCALAR", 5125), "material": len(mats) - 1})
    mz = ((np.array(cfg["muzzle"], float) - o) @ A.T * s).tolist()
    doc = {"asset": {"version": "2.0", "generator": "gun_convert", "copyright": cfg["credit"]}, "scene": 0, "scenes": [{"nodes": [0, 1]}],
           "nodes": [{"name": "model", "mesh": 0}, {"name": "muzzle", "translation": mz}], "meshes": [{"name": "gun", "primitives": prims}],
           "materials": mats, "textures": texs, "images": imgs, "accessors": accs, "bufferViews": views, "buffers": [{"uri": key + ".bin", "byteLength": len(bout)}]}
    open(os.path.join(od, key + ".bin"), "wb").write(bout); json.dump(doc, open(os.path.join(od, key + ".gltf"), "w"))
    allp = np.concatenate([np.concatenate(d[0]) for d in per.values()])
    print("%-7s %6d -> %5d tris  x[%.3f %.3f] y[%.3f %.3f] z[%.3f %.3f]  muzzle %s" % (key, total, tout, *[v for i in range(3) for v in (allp[:, i].min(), allp[:, i].max())], np.round(mz, 3).tolist()))
