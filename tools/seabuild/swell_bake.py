"""Bake the animated "ocean wave" model into frames the game's water can tile over the whole sea.

usage: swell_bake.py ocean_wave.glb out.bin
The model is one 201 x 201 sheet with 20 shapes it moves through. Each shape is read as a field of displacements
(sideways, up, sideways), made to join at its edges (each frame is cross-faded with itself shifted half way, so
the seam falls where the fade hides it), cut to 128 x 128, and written as float32 [20][128][128][3] in fractions
of the sheet's width. tools/seabuild/swell_pack.gd turns that into the texture the game loads.
"""
import json, struct, sys
import numpy as np

N = 128
d = open(sys.argv[1], "rb").read()
n = struct.unpack("<I", d[12:16])[0]
j = json.loads(d[20:20 + n])
b = d[20 + n + 8:]


def acc(i):
    a = j["accessors"][i]
    v = j["bufferViews"][a["bufferView"]]
    k = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[a["type"]]
    off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    st = v.get("byteStride", 0)
    if st and st != 4 * k:
        raw = np.frombuffer(b, np.uint8, st * a["count"], off).reshape(a["count"], st)[:, :4 * k]
        return np.frombuffer(raw.tobytes(), np.float32).reshape(a["count"], k)
    return np.frombuffer(b, np.float32, a["count"] * k, off).reshape(a["count"], k)


p = j["meshes"][0]["primitives"][0]
base = acc(p["attributes"]["POSITION"]).astype(np.float64)
uv = acc(p["attributes"]["TEXCOORD_0"])
gu = np.round(uv[:, 0] * 200).astype(int)
gv = np.round(uv[:, 1] * 200).astype(int)
zs = [x for x in j["nodes"] if x.get("name") == "Wave"][0]["scale"][2]
width = base[:, 0].max() - base[:, 0].min()
flat = np.zeros((201, 201, 2))
flat[gv, gu] = np.stack([np.linspace(base[:, 0].min(), base[:, 0].max(), 201)[gu], np.linspace(base[:, 1].min(), base[:, 1].max(), 201)[gv]], axis=1)
# the cross-fade's weight: 1 in the middle of the sheet, 0 at its edges
t = np.linspace(0.0, 1.0, 200, endpoint=False)
w1 = 0.5 - 0.5 * np.cos(t * 2.0 * np.pi)
W = np.minimum.outer(w1, w1)[:, :, None]
norm = np.sqrt(W * W + (1.0 - W) * (1.0 - W))
out = np.zeros((20, N, N, 3), np.float32)
for k in range(20):
    pos = base if k == 0 else base + acc(p["targets"][k - 1]["POSITION"])
    g = np.zeros((201, 201, 3))
    g[gv, gu] = pos
    f = np.stack([g[:, :, 0] - flat[:, :, 0], g[:, :, 2] * zs, g[:, :, 1] - flat[:, :, 1]], axis=2)[:200, :200]
    f -= f.mean(axis=(0, 1), keepdims=True)
    f = (f * W + np.roll(f, (100, 100), axis=(0, 1)) * (1.0 - W)) / norm
    # 200 -> 128, each point the mean of what it covers (wrapping round)
    idx = np.arange(N) * 200.0 / N
    i0 = np.floor(idx).astype(int)
    fr = (idx - i0)[:, None, None]
    rows = f[i0 % 200] * (1 - fr) + f[(i0 + 1) % 200] * fr
    fc = (idx - i0)[None, :, None]
    out[k] = (rows[:, i0 % 200] * (1 - fc) + rows[:, (i0 + 1) % 200] * fc) / width
out.tofile(sys.argv[2])
print("frames", out.shape, "height: std %.4f, least %.4f, most %.4f of the sheet's width" % (out[:, :, :, 1].std(), out[:, :, :, 1].min(), out[:, :, :, 1].max()),
      "sideways std %.4f" % out[:, :, :, 0].std(), "seam L/R %.5f" % np.abs(out[0][:, 0, 1] - out[0][:, -1, 1]).mean(), "next to each other %.5f" % np.abs(out[0][:, 0, 1] - out[0][:, 1, 1]).mean())
