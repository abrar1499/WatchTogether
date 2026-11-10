"""Make light versions of Poly Haven's modular_urban_apartments_facade (CC0) for mobile.
Writes <name>_hi.gltf (near) and <name>_lo.gltf (far) next to the source, simplified with meshoptimizer: flat
plaster and bands welded by position and normal and cut to the fewest triangles their openings allow, window and
door frames welded by position (their plain paint hides the texture seams) and cut to about 15% (near) or 6% (far).
Both reuse the original .bin plus a new index-only .bin, and the same textures.
usage: python3 kit_lod.py path/to/modular_urban_apartments_facade.gltf"""
import copy, json, os, sys
import numpy as np
import meshoptimizer as mo

src = sys.argv[1]
base = os.path.dirname(src)
stem = os.path.splitext(os.path.basename(src))[0]
g = json.load(open(src))
binfile = g["buffers"][0]["uri"]
blob = open(os.path.join(base, binfile), "rb").read()
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


def plan(name, mat):
    """(ratio, error, sloppy) per piece family and level"""
    if name.startswith(("wall_", "dado_", "cornice_", "base_")):
        # flat plaster and bands: as few triangles as the openings allow
        return {"hi": (0.004, 0.002, False), "lo": (0.002, 0.01, False)}
    if name.startswith("crown_"):
        return {"hi": (0.12, 0.012, False), "lo": (0.08, 0.06, False)}
    return {"hi": (0.15, 0.008, False), "lo": (0.06, 0.06, False)}


NODE = {n["mesh"]: n["name"] for n in g["nodes"] if "mesh" in n}   # mesh names are generic; nodes carry the piece names

for level in ("hi", "lo"):
    out = copy.deepcopy(g)
    ib = bytearray()
    tin = tout = 0
    for mi, m in enumerate(g["meshes"]):
        for pi, p in enumerate(m["primitives"]):
            idx = read(p["indices"]).astype(np.uint32)
            pos = read(p["attributes"]["POSITION"]).astype(np.float32)
            mat = g["materials"][p["material"]]["name"]
            ratio, err, sloppy = plan(NODE[mi], mat)[level]
            target = max(3, int(len(idx) * ratio) // 3 * 3)
            flat = NODE[mi].startswith(("wall_", "dado_", "cornice_", "base_"))
            rep = None
            if not mat.endswith("_glass"):
                # the frames' paint is plain enough that texture seams can go too (position-only weld)
                # flat plaster/trim is planar-mapped: weld by position + normal so the simplifier
                # can merge the scan's many tiny faces; keep one original vertex per welded one
                nor = read(p["attributes"]["NORMAL"]).astype(np.float32)
                key = np.round(np.c_[pos * 1000.0, nor * (2.0 if flat else 0.0)]).astype(np.int64)
                _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
                rep = first
                idx = inv.reshape(-1)[idx].astype(np.uint32)
                pos = pos[first]
            dst = np.zeros(len(idx), dtype=np.uint32)
            if mat.endswith("_glass") or len(idx) <= 60:
                n = len(idx)
                dst[:n] = idx
            elif sloppy:
                n = mo.simplify_sloppy(dst, idx, pos, target_index_count=target, target_error=err)
            else:
                n = mo.simplify(dst, idx, pos, target_index_count=target, target_error=err,
                                options=mo.SIMPLIFY_PRUNE if not NODE[mi].startswith("wall_") else 0)
            if n < 3:
                n = len(idx)
                dst[:n] = idx
            res = dst[:n].astype(np.uint32)
            if rep is not None:
                res = rep[res].astype(np.uint32)
            tin += len(idx) // 3
            tout += n // 3
            while len(ib) % 4:
                ib.append(0)
            off = len(ib)
            ib += res.tobytes()
            out["bufferViews"].append({"buffer": 1, "byteOffset": off, "byteLength": len(res) * 4, "target": 34963})
            out["accessors"].append({"bufferView": len(out["bufferViews"]) - 1, "componentType": 5125,
                                     "count": int(len(res)), "type": "SCALAR"})
            out["meshes"][mi]["primitives"][pi]["indices"] = len(out["accessors"]) - 1
    ibname = "%s_%s_idx.bin" % (stem, level)
    open(os.path.join(base, ibname), "wb").write(ib)
    out["buffers"].append({"uri": ibname, "byteLength": len(ib)})
    json.dump(out, open(os.path.join(base, "%s_%s.gltf" % (stem, level)), "w"))
    print(level, tin, "->", tout, "tris")
