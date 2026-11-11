"""Read a .glb gun model: every mesh node baked with its transform (skins ignored: the bind pose), per material."""
import json, struct, io
import numpy as np
COMP = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8, 5120: np.int8, 5122: np.int16}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}

def load(path):
    b = open(path, 'rb').read()
    n = struct.unpack('<I', b[12:16])[0]
    g = json.loads(b[20:20 + n]); blob = b[20 + n + 8:]
    def read(ai):
        a = g["accessors"][ai]; v = g["bufferViews"][a["bufferView"]]
        k = NC[a["type"]]; dt = np.dtype(COMP[a["componentType"]])
        off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        st = v.get("byteStride", 0) or dt.itemsize * k
        raw = np.frombuffer(blob, dtype=np.uint8, count=st * (a["count"] - 1) + dt.itemsize * k, offset=off)
        o = np.lib.stride_tricks.as_strided(raw, shape=(a["count"], dt.itemsize * k), strides=(st, 1)).copy()
        o = o.view(dt).reshape(a["count"], k) if k > 1 else o.view(dt).reshape(-1)
        if a.get("normalized"):
            o = o.astype(np.float32) / np.iinfo(dt).max
        return o
    def local(nd):
        if "matrix" in nd:
            return np.array(nd["matrix"], float).reshape(4, 4).T
        m = np.eye(4)
        if "scale" in nd: m = np.diag(list(nd["scale"]) + [1.0]) @ m
        if "rotation" in nd:
            x, y, z, w = nd["rotation"]
            r = np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)], [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)], [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])
            rm = np.eye(4); rm[:3, :3] = r; m = rm @ m
        if "translation" in nd:
            t = np.eye(4); t[:3, 3] = nd["translation"]; m = t @ m
        return m
    parent = {}
    for i, nd in enumerate(g["nodes"]):
        for c in nd.get("children", []): parent[c] = i
    def world(i):
        m = local(g["nodes"][i])
        while i in parent:
            i = parent[i]; m = local(g["nodes"][i]) @ m
        return m
    parts = []          # (node name, material index, pos, nor, uv, idx)
    for i, nd in enumerate(g["nodes"]):
        if "mesh" not in nd: continue
        M = np.eye(4) if "skin" in nd else world(i)
        N = np.linalg.inv(M[:3, :3]).T
        for p in g["meshes"][nd["mesh"]]["primitives"]:
            pos = read(p["attributes"]["POSITION"]).astype(np.float64) @ M[:3, :3].T + M[:3, 3]
            nor = read(p["attributes"]["NORMAL"]).astype(np.float64) @ N.T
            nor /= np.maximum(np.linalg.norm(nor, axis=1, keepdims=True), 1e-9)
            uv = read(p["attributes"]["TEXCOORD_0"]).astype(np.float32) if "TEXCOORD_0" in p["attributes"] else np.zeros((len(pos), 2), np.float32)
            idx = read(p["indices"]).astype(np.uint32) if "indices" in p else np.arange(len(pos), dtype=np.uint32)
            if np.linalg.det(M[:3, :3]) < 0: idx = idx.reshape(-1, 3)[:, ::-1].reshape(-1)
            parts.append([nd.get("name", ""), p.get("material", 0), pos, nor, uv, idx])
    def image(ti):
        im = g["images"][g["textures"][ti]["source"]]; v = g["bufferViews"][im["bufferView"]]; o = v.get("byteOffset", 0)
        from PIL import Image
        return Image.open(io.BytesIO(blob[o:o + v["byteLength"]]))
    return g, parts, image
