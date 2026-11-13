"""Make a downloaded boat model light enough for the game: fewer triangles, smaller pictures.

usage: boat_light.py in.glb out.glb [triangles wanted] [picture size]
Keeps the model's nodes and materials; rewrites each mesh with welded points, thinned to its share of the wanted
triangle count (smooth normals worked out afresh), and every picture scaled down and stored as JPEG (PNG if it
has see-through parts).
"""
import io, json, struct, sys
import numpy as np

COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NUM = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def main():
    src, dst = sys.argv[1], sys.argv[2]
    want = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    pic = int(sys.argv[4]) if len(sys.argv) > 4 else 512
    d = open(src, "rb").read()
    n = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + n])
    bin_ = d[20 + n + 8:]

    def view(i):
        v = j["bufferViews"][i]
        return bin_[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]], v.get("byteStride", 0)

    def read(ai):
        a = j["accessors"][ai]
        raw, stride = view(a["bufferView"])
        dt = np.dtype(COMP[a["componentType"]])
        k = NUM[a["type"]]
        off = a.get("byteOffset", 0)
        if stride and stride != dt.itemsize * k:
            out = np.zeros((a["count"], k), dt)
            for r in range(a["count"]):
                out[r] = np.frombuffer(raw, dt, k, off + r * stride)
            return out
        return np.frombuffer(raw, dt, a["count"] * k, off).reshape(a["count"], k).copy()

    out = bytearray()
    views, accs = [], []

    def put(arr, target=None):
        while len(out) % 4:
            out.append(0)
        b = arr.tobytes()
        v = {"buffer": 0, "byteOffset": len(out), "byteLength": len(b)}
        if target:
            v["target"] = target
        out.extend(b)
        views.append(v)
        return len(views) - 1

    def acc(arr, typ, ctype, target=None, bounds=False):
        a = {"bufferView": put(arr, target), "componentType": ctype, "count": int(arr.shape[0]), "type": typ}
        if bounds:
            a["min"] = [float(x) for x in arr.min(axis=0)]
            a["max"] = [float(x) for x in arr.max(axis=0)]
        accs.append(a)
        return len(accs) - 1

    total = 0
    for m in j["meshes"]:
        for p in m["primitives"]:
            total += (j["accessors"][p["indices"]]["count"] if "indices" in p else j["accessors"][p["attributes"]["POSITION"]]["count"]) // 3
    ratio = min(1.0, want / total) if want else 1.0
    after = 0
    for m in j["meshes"]:
        for p in m["primitives"]:
            pos = read(p["attributes"]["POSITION"]).astype(np.float32)
            idx = read(p["indices"]).reshape(-1).astype(np.uint32) if "indices" in p else np.arange(len(pos), dtype=np.uint32)
            uv = read(p["attributes"]["TEXCOORD_0"]).astype(np.float32) if "TEXCOORD_0" in p["attributes"] else None
            attrs = {}
            if ratio < 1.0 and uv is None:
                import fast_simplification
                # weld what shares a place, thin, and take the normals afresh
                key = np.round(pos / (np.ptp(pos, axis=0).max() * 1e-5)).astype(np.int64)
                _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
                pos = pos[first]
                tri = inv.reshape(-1)[idx].reshape(-1, 3)
                tri = tri[(tri[:, 0] != tri[:, 1]) & (tri[:, 1] != tri[:, 2]) & (tri[:, 0] != tri[:, 2])]
                if len(tri) > 60:
                    pos, tri = fast_simplification.simplify(pos, tri, target_reduction=1.0 - max(ratio, 60.0 / len(tri)))
                    pos = pos.astype(np.float32)
                # points split where the surface turns sharply, so flat panels stay flat and edges stay crisp
                fn = np.cross(pos[tri[:, 1]] - pos[tri[:, 0]], pos[tri[:, 2]] - pos[tri[:, 0]])
                area = np.linalg.norm(fn, axis=1, keepdims=True)
                fn = fn / np.maximum(area, 1e-20)
                vn = np.zeros_like(pos)
                for c in range(3):
                    np.add.at(vn, tri[:, c], fn * area)
                vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-20)
                npos, nnor, nidx = [], [], []
                for c in range(3):
                    sharp = (fn * vn[tri[:, c]]).sum(axis=1) < 0.8
                    npos.append(pos[tri[:, c]])
                    nnor.append(np.where(sharp[:, None], fn, vn[tri[:, c]]))
                P = np.stack(npos, axis=1).reshape(-1, 3)
                N = np.stack(nnor, axis=1).reshape(-1, 3)
                both = np.round(np.hstack([P / (np.ptp(P, axis=0).max() * 1e-5), N * 50.0])).astype(np.int64)
                _, first, inv = np.unique(both, axis=0, return_index=True, return_inverse=True)
                pos, nor, idx = P[first].astype(np.float32), N[first].astype(np.float32), inv.reshape(-1).astype(np.uint32)
                attrs["NORMAL"] = acc(nor, "VEC3", 5126, 34962)
            else:
                if "NORMAL" in p["attributes"]:
                    attrs["NORMAL"] = acc(read(p["attributes"]["NORMAL"]).astype(np.float32), "VEC3", 5126, 34962)
                if uv is not None:
                    attrs["TEXCOORD_0"] = acc(uv, "VEC2", 5126, 34962)
                if "TANGENT" in p["attributes"]:
                    attrs["TANGENT"] = acc(read(p["attributes"]["TANGENT"]).astype(np.float32), "VEC4", 5126, 34962)
            attrs["POSITION"] = acc(pos, "VEC3", 5126, 34962, True)
            p["attributes"] = attrs
            p["indices"] = acc(idx.reshape(-1, 1), "SCALAR", 5125, 34963)
            after += len(idx) // 3
    if j.get("images"):
        from PIL import Image
        for im in j["images"]:
            raw, _ = view(im["bufferView"])
            pic_ = Image.open(io.BytesIO(raw))
            pic_.load()
            if max(pic_.size) > pic:
                pic_ = pic_.resize((max(1, pic_.size[0] * pic // max(pic_.size)), max(1, pic_.size[1] * pic // max(pic_.size))), Image.LANCZOS)
            buf = io.BytesIO()
            alpha = pic_.mode in ("RGBA", "LA") and pic_.getchannel("A").getextrema()[0] < 250
            if alpha:
                pic_.save(buf, "PNG", optimize=True)
                im["mimeType"] = "image/png"
            else:
                pic_.convert("RGB").save(buf, "JPEG", quality=88)
                im["mimeType"] = "image/jpeg"
            im["bufferView"] = put(np.frombuffer(buf.getvalue(), np.uint8))
    j["bufferViews"], j["accessors"] = views, accs
    while len(out) % 4:
        out.append(0)
    j["buffers"] = [{"byteLength": len(out)}]
    for k in ("animations", "skins"):
        j.pop(k, None)
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(out), 0x004E4942) + bytes(out))
    print("%s: %d -> %d triangles, %d -> %d KB" % (dst, total, after, len(d) // 1024, (28 + len(js) + len(out)) // 1024))


main()
