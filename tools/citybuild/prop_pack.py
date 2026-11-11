"""Pack a Poly Haven (CC0) prop for phones: every node's mesh baked with its transform into one mesh per material,
simplified with meshoptimizer to about `tris` triangles in all, its colour and normal textures at `tex` pixels (the
roughness/metal/AO map is dropped: the game sets a plain roughness; with PACK_ARM=1 in the environment it is kept). Writes <out>/<id>_game.gltf, its .bin and textures.
usage: python3 prop_pack.py <dir with id.gltf> <out dir> <tris> [tex=512]"""
import json, os, sys
import numpy as np
import meshoptimizer as mo
from PIL import Image

src, out, tris = sys.argv[1], sys.argv[2], int(sys.argv[3])
tex = int(sys.argv[4]) if len(sys.argv) > 4 else 512
aid = os.path.basename(os.path.normpath(src))
g = json.load(open(os.path.join(src, aid + ".gltf")))
blob = open(os.path.join(src, g["buffers"][0]["uri"]), "rb").read()
COMP = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read(ai):
    a = g["accessors"][ai]
    v = g["bufferViews"][a["bufferView"]]
    n = NCOMP[a["type"]]
    dt = np.dtype(COMP[a["componentType"]])
    off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = v.get("byteStride", 0) or dt.itemsize * n
    raw = np.frombuffer(blob, dtype=np.uint8, count=stride * (a["count"] - 1) + dt.itemsize * n, offset=off)
    o = np.lib.stride_tricks.as_strided(raw, shape=(a["count"], dt.itemsize * n), strides=(stride, 1)).copy()
    return o.view(dt).reshape(a["count"], n) if n > 1 else o.view(dt).reshape(-1)


def local(n):
    if "matrix" in n:
        return np.array(n["matrix"], float).reshape(4, 4).T
    m = np.eye(4)
    if "scale" in n:
        m = np.diag(list(n["scale"]) + [1.0]) @ m
    if "rotation" in n:
        x, y, z, w = n["rotation"]
        r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                      [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                      [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        rm = np.eye(4)
        rm[:3, :3] = r
        m = rm @ m
    if "translation" in n:
        t = np.eye(4)
        t[:3, 3] = n["translation"]
        m = t @ m
    return m


parent = {}
for i, n in enumerate(g["nodes"]):
    for c in n.get("children", []):
        parent[c] = i


def world(i):
    m = local(g["nodes"][i])
    while i in parent:
        i = parent[i]
        m = local(g["nodes"][i]) @ m
    return m


per = {}        # material -> [pos, nor, uv, idx]
skip = set(sys.argv[5].split(",")) if len(sys.argv) > 5 else set()
for i, n in enumerate(g["nodes"]):
    if "mesh" not in n or n.get("name") in skip:
        continue
    M = world(i)
    N = np.linalg.inv(M[:3, :3]).T
    for p in g["meshes"][n["mesh"]]["primitives"]:
        pos = read(p["attributes"]["POSITION"]).astype(np.float64) @ M[:3, :3].T + M[:3, 3]
        nor = read(p["attributes"]["NORMAL"]).astype(np.float64) @ N.T
        nor /= np.maximum(np.linalg.norm(nor, axis=1, keepdims=True), 1e-9)
        uv = read(p["attributes"]["TEXCOORD_0"]).astype(np.float32)
        idx = read(p["indices"]).astype(np.uint32)
        if np.linalg.det(M[:3, :3]) < 0:
            idx = idx.reshape(-1, 3)[:, ::-1].reshape(-1)
        d = per.setdefault(p["material"], [[], [], [], [], 0])
        d[0].append(pos); d[1].append(nor); d[2].append(uv); d[3].append(idx + d[4]); d[4] += len(pos)
total = sum(sum(len(x) for x in d[3]) for d in per.values()) // 3
os.makedirs(os.path.join(out, "textures"), exist_ok=True)
bout = bytearray()
views, accs, prims, mats, texs, imgs = [], [], [], [], [], []


def put(arr, target, typ, comp, minmax=False):
    while len(bout) % 4:
        bout.append(0)
    raw = np.ascontiguousarray(arr).tobytes()
    views.append({"buffer": 0, "byteOffset": len(bout), "byteLength": len(raw), "target": target})
    bout.extend(raw)
    a = {"bufferView": len(views) - 1, "componentType": comp, "count": int(len(arr)), "type": typ}
    if minmax:
        a["min"] = [float(x) for x in arr.min(0)]
        a["max"] = [float(x) for x in arr.max(0)]
    accs.append(a)
    return len(accs) - 1


def image(ti):
    uri = g["images"][g["textures"][ti]["source"]]["uri"]
    name = os.path.basename(uri).replace("_1k", "")
    im = Image.open(os.path.join(src, uri)).convert("RGB")
    if max(im.size) > tex:
        im = im.resize((tex, tex), Image.LANCZOS)
    im.save(os.path.join(out, "textures", name), quality=88)
    imgs.append({"uri": "textures/" + name})
    texs.append({"source": len(imgs) - 1})
    return len(texs) - 1


tout = 0
for mi, d in per.items():
    pos = np.concatenate(d[0]).astype(np.float32)
    nor = np.concatenate(d[1]).astype(np.float32)
    uv = np.concatenate(d[2])
    idx = np.concatenate(d[3]).astype(np.uint32)
    target = max(60, int(len(idx) * tris / max(total, 1)) // 3 * 3)
    res = idx
    if len(idx) > target:
        dst = np.zeros(len(idx), dtype=np.uint32)
        n = mo.simplify(dst, idx, pos, target_index_count=target, target_error=0.03, options=mo.SIMPLIFY_PRUNE)
        if n > target * 1.5:
            # seams stop the careful pass: weld by position, simplify, and keep one original vertex for each
            key = np.round(pos * 2000.0).astype(np.int64)
            _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
            widx = inv.reshape(-1)[idx].astype(np.uint32)
            n = mo.simplify(dst, widx, pos[first], target_index_count=target, target_error=0.05, options=mo.SIMPLIFY_PRUNE)
            if n > target * 1.6:
                n = mo.simplify_sloppy(dst, widx, pos[first], target_index_count=target, target_error=0.08)
            res = first[dst[:n]].astype(np.uint32) if n >= 3 else idx
        else:
            res = dst[:n].astype(np.uint32)
    used, new = np.unique(res, return_inverse=True)
    tout += len(res) // 3
    src_m = g["materials"][mi]
    m = {"name": src_m.get("name", aid), "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.78}}
    pm = src_m.get("pbrMetallicRoughness", {})
    if "baseColorTexture" in pm:
        m["pbrMetallicRoughness"]["baseColorTexture"] = {"index": image(pm["baseColorTexture"]["index"])}
    if "baseColorFactor" in pm:
        m["pbrMetallicRoughness"]["baseColorFactor"] = pm["baseColorFactor"]
    if "normalTexture" in src_m:
        m["normalTexture"] = {"index": image(src_m["normalTexture"]["index"])}
    if os.environ.get("PACK_ARM") and "metallicRoughnessTexture" in pm:
        # the full set: occlusion (red), roughness (green) and metal (blue) in one image
        ti = image(pm["metallicRoughnessTexture"]["index"])
        m["pbrMetallicRoughness"]["metallicRoughnessTexture"] = {"index": ti}
        m["pbrMetallicRoughness"]["metallicFactor"] = 1.0
        m["pbrMetallicRoughness"]["roughnessFactor"] = 1.0
        m["occlusionTexture"] = {"index": ti}
    for k in ("alphaMode", "alphaCutoff", "doubleSided"):
        if k in src_m:
            m[k] = src_m[k]
    mats.append(m)
    prims.append({"attributes": {"POSITION": put(pos[used], 34962, "VEC3", 5126, True), "NORMAL": put(nor[used], 34962, "VEC3", 5126),
                                 "TEXCOORD_0": put(uv[used], 34962, "VEC2", 5126)},
                  "indices": put(new.astype(np.uint32).reshape(-1), 34963, "SCALAR", 5125), "material": len(mats) - 1})
doc = {"asset": {"version": "2.0", "generator": "prop_pack (Poly Haven CC0 source)"}, "scene": 0, "scenes": [{"nodes": [0]}],
       "nodes": [{"name": aid, "mesh": 0}], "meshes": [{"name": aid, "primitives": prims}], "materials": mats, "textures": texs, "images": imgs,
       "accessors": accs, "bufferViews": views, "buffers": [{"uri": aid + "_game.bin", "byteLength": len(bout)}]}
open(os.path.join(out, aid + "_game.bin"), "wb").write(bout)
json.dump(doc, open(os.path.join(out, aid + "_game.gltf"), "w"))
allp = np.concatenate([np.concatenate(d[0]) for d in per.values()])
print("%-28s %6d -> %5d tris  size %s  min y %.2f" % (aid, total, tout, np.round(allp.max(0) - allp.min(0), 2).tolist(), allp[:, 1].min()))
