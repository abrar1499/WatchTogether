"""Take the knife out of the "knife Animated" model (first-person arms, knife, animation) as a small prop.

usage: knife_take.py knife_animated.glb out.glb
Keeps only the knife's mesh and its textures (cut to 512 pixels, JPEG); turns it so the blade lies along +z with
the grip at the origin, and sizes it to 30 cm overall.
"""
import io, json, struct, sys
import numpy as np
from PIL import Image

d = open(sys.argv[1], "rb").read()
n = struct.unpack("<I", d[12:16])[0]
j = json.loads(d[20:20 + n])
b = d[20 + n + 8:]
COMP = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NUM = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def acc(i):
    a = j["accessors"][i]
    v = j["bufferViews"][a["bufferView"]]
    dt = np.dtype(COMP[a["componentType"]])
    k = NUM[a["type"]]
    off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    st = v.get("byteStride", 0)
    if st and st != dt.itemsize * k:
        raw = np.frombuffer(b, np.uint8, st * a["count"], off).reshape(a["count"], st)[:, :dt.itemsize * k]
        return np.frombuffer(raw.tobytes(), dt).reshape(a["count"], k)
    return np.frombuffer(b, dt, a["count"] * k, off).reshape(a["count"], k).copy()


mesh = [m for m in j["meshes"] if "knife" in m.get("name", "")][0]
p = mesh["primitives"][0]
pos = acc(p["attributes"]["POSITION"]).astype(np.float32)
nor = acc(p["attributes"]["NORMAL"]).astype(np.float32)
uv = acc(p["attributes"]["TEXCOORD_0"]).astype(np.float32)
idx = acc(p["indices"]).reshape(-1).astype(np.uint32)
k = 0.30 / (pos[:, 1].max() - pos[:, 1].min())
turn = lambda v: np.stack([v[:, 0], -v[:, 2], v[:, 1]], axis=1)     # the blade (+y) to +z
pos = turn(pos) * k
nor = turn(nor)
out = bytearray()
views, accs, images, textures = [], [], [], []


def put(raw, target=None):
    while len(out) % 4:
        out.append(0)
    v = {"buffer": 0, "byteOffset": len(out), "byteLength": len(raw)}
    if target:
        v["target"] = target
    out.extend(raw)
    views.append(v)
    return len(views) - 1


def add(arr, typ, ctype, target, bounds=False):
    a = {"bufferView": put(arr.tobytes(), target), "componentType": ctype, "count": int(arr.shape[0]), "type": typ}
    if bounds:
        a["min"] = [float(x) for x in arr.min(axis=0)]
        a["max"] = [float(x) for x in arr.max(axis=0)]
    accs.append(a)
    return len(accs) - 1


def tex(ref):
    im = j["images"][j["textures"][ref["index"]]["source"]]
    v = j["bufferViews"][im["bufferView"]]
    pic = Image.open(io.BytesIO(b[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]])).convert("RGB")
    pic = pic.resize((512, 512), Image.LANCZOS)
    buf = io.BytesIO()
    pic.save(buf, "JPEG", quality=88)
    images.append({"bufferView": put(buf.getvalue()), "mimeType": "image/jpeg"})
    textures.append({"source": len(images) - 1})
    return {"index": len(textures) - 1}


src = j["materials"][p["material"]]
pbr = src.get("pbrMetallicRoughness", {})
mat = {"name": "knife", "pbrMetallicRoughness": {}}
if "baseColorTexture" in pbr:
    mat["pbrMetallicRoughness"]["baseColorTexture"] = tex(pbr["baseColorTexture"])
if "metallicRoughnessTexture" in pbr:
    mat["pbrMetallicRoughness"]["metallicRoughnessTexture"] = tex(pbr["metallicRoughnessTexture"])
if "normalTexture" in src:
    mat["normalTexture"] = tex(src["normalTexture"])
prim = {"attributes": {"POSITION": add(pos, "VEC3", 5126, 34962, True), "NORMAL": add(nor, "VEC3", 5126, 34962), "TEXCOORD_0": add(uv, "VEC2", 5126, 34962)},
        "indices": add(idx.reshape(-1, 1), "SCALAR", 5125, 34963), "material": 0}
while len(out) % 4:
    out.append(0)
g = {"asset": {"version": "2.0", "extras": j["asset"].get("extras", {})}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "knife", "mesh": 0}],
     "meshes": [{"name": "knife", "primitives": [prim]}], "materials": [mat], "textures": textures, "images": images, "samplers": [{}],
     "bufferViews": views, "accessors": accs, "buffers": [{"byteLength": len(out)}]}
js = json.dumps(g, separators=(",", ":")).encode()
js += b" " * (-len(js) % 4)
with open(sys.argv[2], "wb") as f:
    f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)))
    f.write(struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(out), 0x004E4942) + bytes(out))
print("knife: %d triangles, %d textures, %d KB; reaches z %.3f .. %.3f m" % (len(idx) // 3, len(images), (len(js) + len(out)) // 1024, pos[:, 2].min(), pos[:, 2].max()))
