"""A light far-away version of a skinned character (.glb): the same skeleton, skin and vertices, every primitive's
triangles simplified with meshoptimizer to about `ratio` of them. The pictures and materials are left out (the game
puts the full model's materials on it), so the file is small. Writes <stem>_low.glb next to the source.
usage: python3 skin_lod.py path/to/character.glb ratio"""
import json, struct, sys
import numpy as np
import meshoptimizer as mo

src, ratio = sys.argv[1], float(sys.argv[2])
d = open(src, "rb").read()
jl = struct.unpack("<I", d[12:16])[0]
g = json.loads(d[20:20 + jl])
o = 20 + jl
bl = struct.unpack("<I", d[o:o + 4])[0]
blob = d[o + 8:o + 8 + bl]
COMP = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


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


# a new buffer from nothing: for each primitive only the vertices its simplified triangles still use (every
# attribute of them: skin joints and weights too), and the skins' bind matrices; the pictures are left out
new_blob = bytearray()
new_views = []
new_acc = []
CT = {np.dtype(np.float32): 5126, np.dtype(np.uint32): 5125, np.dtype(np.uint16): 5123, np.dtype(np.uint8): 5121}


def put(arr, typ, target=None, minmax=False, normalized=False):
    while len(new_blob) % 4:
        new_blob.append(0)
    raw = np.ascontiguousarray(arr).tobytes()
    v = {"buffer": 0, "byteOffset": len(new_blob), "byteLength": len(raw)}
    if target:
        v["target"] = target
    new_views.append(v)
    new_blob.extend(raw)
    acc = {"bufferView": len(new_views) - 1, "componentType": CT[arr.dtype], "count": int(len(arr)), "type": typ}
    if normalized:
        acc["normalized"] = True
    if minmax:
        acc["min"] = [float(x) for x in arr.min(0)]
        acc["max"] = [float(x) for x in arr.max(0)]
    new_acc.append(acc)
    return len(new_acc) - 1


before = after = 0
for m in g["meshes"]:
    for p in m["primitives"]:
        idx = read(p["indices"]).astype(np.uint32)
        pos = read(p["attributes"]["POSITION"]).astype(np.float32)
        target = max(60, int(len(idx) * ratio) // 3 * 3)
        dst = np.zeros(len(idx), dtype=np.uint32)
        n = mo.simplify(dst, idx, pos, target_index_count=target, target_error=0.03)
        if n > target * 1.4:
            n = mo.simplify(dst, idx, pos, target_index_count=target, target_error=0.08)
        res = dst[:n]
        before += len(idx) // 3
        after += n // 3
        used, inv = np.unique(res, return_inverse=True)
        attrs = {}
        for name, ai in p["attributes"].items():
            old = g["accessors"][ai]
            data = read(ai)[used]
            attrs[name] = put(data, old["type"], 34962, name == "POSITION", old.get("normalized", False))
        p["attributes"] = attrs
        p["indices"] = put(inv.astype(np.uint32 if len(used) > 65535 else np.uint16), "SCALAR", 34963)
        p.pop("material", None)
        p.pop("targets", None)
for sk in g.get("skins", []):
    if "inverseBindMatrices" in sk:
        old = g["accessors"][sk["inverseBindMatrices"]]
        sk["inverseBindMatrices"] = put(read(sk["inverseBindMatrices"]), old["type"])
g["accessors"] = new_acc
g["bufferViews"] = new_views
g.pop("animations", None)
for k in ("images", "textures", "materials", "samplers"):
    g.pop(k, None)
g.pop("extensionsUsed", None)
g.pop("extensionsRequired", None)
while len(new_blob) % 4:
    new_blob.append(0)
g["buffers"] = [{"byteLength": len(new_blob)}]
js = json.dumps(g, separators=(",", ":")).encode()
while len(js) % 4:
    js += b" "
out = src[:-4] + "_low.glb"
with open(out, "wb") as f:
    f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(new_blob)))
    f.write(struct.pack("<II", len(js), 0x4E4F534A))
    f.write(js)
    f.write(struct.pack("<II", len(new_blob), 0x004E4942))
    f.write(bytes(new_blob))
print("%s: %d -> %d tris, %d KB" % (out, before, after, (len(js) + len(new_blob)) // 1024))
