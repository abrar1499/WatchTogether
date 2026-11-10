"""Light game version of a Poly Haven (CC0) prop: every primitive simplified with meshoptimizer to about
`ratio` of its triangles (careful first, sloppy if that cannot get there). Writes <stem>_game.gltf next to the
source with its own compact .bin (only the vertices still used) and the same textures.
usage: python3 prop_lod.py path/to/prop.gltf ratio"""
import copy, json, os, sys
import numpy as np
import meshoptimizer as mo

src, ratio = sys.argv[1], float(sys.argv[2])
base = os.path.dirname(src)
stem = os.path.splitext(os.path.basename(src))[0]
g = json.load(open(src))
blob = open(os.path.join(base, g["buffers"][0]["uri"]), "rb").read()
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
    out = np.lib.stride_tricks.as_strided(raw, shape=(a["count"], dt.itemsize * n), strides=(stride, 1)).copy()
    return out.view(dt).reshape(a["count"], n) if n > 1 else out.view(dt).reshape(-1)


out = copy.deepcopy(g)
out["buffers"] = []
out["bufferViews"] = []
out["accessors"] = []
binname = "%s_game.bin" % stem
blob_out = bytearray()


def put(arr, target, typ, comp, minmax=False):
    """append a tightly packed accessor to the new buffer"""
    while len(blob_out) % 4:
        blob_out.append(0)
    raw = np.ascontiguousarray(arr).tobytes()
    out["bufferViews"].append({"buffer": 0, "byteOffset": len(blob_out), "byteLength": len(raw), "target": target})
    blob_out.extend(raw)
    acc = {"bufferView": len(out["bufferViews"]) - 1, "componentType": comp, "count": int(len(arr)), "type": typ}
    if minmax:
        acc["min"] = [float(x) for x in arr.min(0)]
        acc["max"] = [float(x) for x in arr.max(0)]
    out["accessors"].append(acc)
    return len(out["accessors"]) - 1


tin = tout = 0
for mi, m in enumerate(g["meshes"]):
    for pi, p in enumerate(m["primitives"]):
        idx = read(p["indices"]).astype(np.uint32)
        pos = read(p["attributes"]["POSITION"]).astype(np.float32)
        target = max(36, int(len(idx) * ratio) // 3 * 3)
        dst = np.zeros(len(idx), dtype=np.uint32)
        n = len(idx)
        dst[:n] = idx
        if len(idx) > target:
            n = mo.simplify(dst, idx, pos, target_index_count=target, target_error=0.02, options=mo.SIMPLIFY_PRUNE)
            if n > target * 1.6:
                n = mo.simplify_sloppy(dst, idx, pos, target_index_count=target, target_error=0.05)
            if n < 3:
                n = len(idx)
                dst[:n] = idx
        res = dst[:n].astype(np.uint32)
        tin += len(idx) // 3
        tout += n // 3
        # keep only the vertices still used, every attribute packed anew
        used, newidx = np.unique(res, return_inverse=True)
        prim = out["meshes"][mi]["primitives"][pi]
        for name, ai in p["attributes"].items():
            a = read(ai)[used]
            src_acc = g["accessors"][ai]
            put(a, 34962, src_acc["type"], src_acc["componentType"], minmax=(name == "POSITION"))
            prim["attributes"][name] = len(out["accessors"]) - 1
        prim["indices"] = put(newidx.astype(np.uint32).reshape(-1), 34963, "SCALAR", 5125)
out["buffers"] = [{"uri": binname, "byteLength": len(blob_out)}]
open(os.path.join(base, binname), "wb").write(blob_out)
json.dump(out, open(os.path.join(base, "%s_game.gltf" % stem), "w"))
print(stem, tin, "->", tout, "tris,", len(blob_out) // 1024, "KB")
