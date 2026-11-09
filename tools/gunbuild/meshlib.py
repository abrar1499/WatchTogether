"""Tiny mesh kit: bevelled extrusions of side profiles, lathes, glb writer."""
import math, json, struct, io
import numpy as np
import mapbox_earcut as earcut

V = lambda *a: np.array(a, dtype=float)

def nrm(v):
    l = np.linalg.norm(v)
    return v / l if l > 1e-12 else v

def signed_area(pts):
    s = 0.0
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        s += a[0] * b[1] - b[0] * a[1]
    return s * 0.5

def inset(pts, d):
    """Miter inset of a CCW polygon (same vertex count)."""
    if d <= 0:
        return [p.copy() for p in pts]
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        e0, e1 = nrm(p1 - p0), nrm(p2 - p1)
        n0, n1 = V(-e0[1], e0[0]), V(-e1[1], e1[0])
        b = nrm(n0 + n1)
        c = max(0.45, float(np.dot(b, n0)))
        out.append(p1 + b * d / c)
    return out

def rounded(pts, r, segs=3):
    """Fillet every corner (r: number or per-vertex list) with a quadratic curve."""
    pts = [np.array(p, float) for p in pts]
    n = len(pts)
    rs = r if isinstance(r, (list, tuple)) else [r] * n
    out = []
    for i in range(n):
        p, a, b = pts[i], pts[i - 1], pts[(i + 1) % n]
        if rs[i] <= 0:
            out.append(p)
            continue
        d1, d2 = a - p, b - p
        t = min(rs[i], 0.45 * np.linalg.norm(d1), 0.45 * np.linalg.norm(d2))
        s, e = p + nrm(d1) * t, p + nrm(d2) * t
        for k in range(segs + 1):
            u = k / segs
            out.append((1 - u) ** 2 * s + 2 * (1 - u) * u * p + u * u * e)
    return out

class Mesh:
    def __init__(self):
        self.parts = {}

    def tri(self, mat, vs, xf=None):
        P = self.parts.setdefault(mat, {"pos": [], "nrm": [], "uv": []})
        ps = [np.array(v[0], float) for v in vs]
        ns = [nrm(np.array(v[1], float)) for v in vs]
        if xf is not None:
            R, t = xf
            ps = [R @ p + t for p in ps]
            ns = [R @ q for q in ns]
        fn = np.cross(ps[1] - ps[0], ps[2] - ps[0])
        if np.linalg.norm(fn) < 1e-14:
            return
        order = [0, 1, 2] if np.dot(fn, ns[0] + ns[1] + ns[2]) >= 0 else [0, 2, 1]
        for k in order:
            P["pos"].append(ps[k]); P["nrm"].append(ns[k]); P["uv"].append(vs[k][2])

    def quad(self, mat, a, b, c, d, xf=None):
        self.tri(mat, [a, b, c], xf)
        self.tri(mat, [a, c, d], xf)

    # ---------------- bevelled extrusion of a (z, y) profile across x ----------------
    def extrude(self, mat, pts, h, bevel=0.0, steps=2, cx=0.0, smooth=42, us=0.5, vs=0.125, xf=None, caps=True):
        pts = [np.array(p, float) for p in pts]
        if signed_area(pts) < 0:
            pts = pts[::-1]
        n = len(pts)
        b = min(bevel, h * 0.95)
        ths = [k / steps * math.pi / 2 for k in range(steps + 1)] if b > 0 else [0.0]
        rings = [inset(pts, b * (1 - math.cos(t))) for t in ths]
        xs = [h - b + b * math.sin(t) for t in ths]
        en = []
        for i in range(n):
            e = nrm(pts[(i + 1) % n] - pts[i])
            en.append(V(e[1], -e[0]))
        cs = math.cos(math.radians(smooth))
        def vn(i, edge):
            o = (i - 1) % n if edge == i else (i + 1) % n
            if np.dot(en[o], en[edge]) > cs:
                return nrm(en[o] + en[edge])
            return en[edge]
        per = [0.0]
        for i in range(n):
            per.append(per[-1] + np.linalg.norm(pts[(i + 1) % n] - pts[i]))
        def P3(q, x):
            return V(cx + x, q[1], q[0])
        def N3(n2, th, sg):
            w = V(0, n2[1], n2[0])
            return w * math.cos(th) + V(sg, 0, 0) * math.sin(th)
        for i in range(n):
            j = (i + 1) % n
            na, nb = vn(i, i), vn(j, i)
            # straight wall
            x0 = xs[0]
            self.quad(mat,
                (P3(rings[0][i], -x0), N3(na, 0, 1), (per[i] / us, -x0 / vs)),
                (P3(rings[0][j], -x0), N3(nb, 0, 1), (per[i + 1] / us, -x0 / vs)),
                (P3(rings[0][j], x0), N3(nb, 0, 1), (per[i + 1] / us, x0 / vs)),
                (P3(rings[0][i], x0), N3(na, 0, 1), (per[i] / us, x0 / vs)), xf)
            for sg in (1, -1):
                for k in range(len(ths) - 1):
                    t0, t1 = ths[k], ths[k + 1]
                    a0, a1 = sg * xs[k], sg * xs[k + 1]
                    self.quad(mat,
                        (P3(rings[k][i], a0), N3(na, t0, sg), (per[i] / us, a0 / vs)),
                        (P3(rings[k][j], a0), N3(nb, t0, sg), (per[i + 1] / us, a0 / vs)),
                        (P3(rings[k + 1][j], a1), N3(nb, t1, sg), (per[i + 1] / us, a1 / vs)),
                        (P3(rings[k + 1][i], a1), N3(na, t1, sg), (per[i] / us, a1 / vs)), xf)
        if not caps:
            return
        cap = rings[-1]
        arr = np.array(cap, dtype=np.float64)
        idx = earcut.triangulate_float64(arr, np.array([len(cap)], dtype=np.uint32))
        for sg in (1, -1):
            x = sg * xs[-1]
            for t in range(0, len(idx), 3):
                self.tri(mat, [(P3(cap[q], x), V(sg, 0, 0), (cap[q][0] / us, cap[q][1] / vs)) for q in idx[t:t + 3]], xf)

    # ---------------- lathe round the local z axis ----------------
    def lathe(self, mat, prof, seg=20, center=(0.0, 0.0), smooth=40, us=0.5, vs=0.125, xf=None, phase=0.0):
        """prof: [(z, r)] outer surface with increasing z (normals face (-dr, dz))."""
        prof = [np.array(p, float) for p in prof]
        m = len(prof)
        sn = []
        for k in range(m - 1):
            d = prof[k + 1] - prof[k]
            sn.append(nrm(V(-d[1], d[0])))   # (n_z, n_r)
        cs = math.cos(math.radians(smooth))
        def pn(k, s):
            o = k - 1 if k == s else k + 1
            if 0 <= o < m - 1 and np.dot(sn[o], sn[s]) > cs:
                return nrm(sn[o] + sn[s])
            return sn[s]
        cx, cy = center
        for s in range(m - 1):
            for q in range(seg):
                f0 = phase + 2 * math.pi * q / seg
                f1 = phase + 2 * math.pi * (q + 1) / seg
                vv = []
                for (k, f) in ((s, f0), (s + 1, f0), (s + 1, f1), (s, f1)):
                    z, r = prof[k]
                    rad = V(math.cos(f), math.sin(f), 0)
                    n2 = pn(k, s)
                    vv.append((V(cx + r * math.cos(f), cy + r * math.sin(f), z), rad * n2[1] + V(0, 0, 1) * n2[0], (z / us, f / (2 * math.pi) * 2)))
                self.quad(mat, *vv, xf=xf)

# axis frames for lathes: local z -> gun x / y
AX_X = (np.array([[0, 0, 1], [0, 1, 0], [-1, 0, 0]], float), V(0, 0, 0))
AX_Y = (np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], float), V(0, 0, 0))
def at(frame, t):
    return (frame[0], np.array(t, float))

def write_glb(path, mesh, materials, images, nodes_extra):
    """materials: name -> dict(color, metal, rough, tex (image name or None), unlit, emissive)."""
    bin_ = bytearray()
    views, accs = [], []
    def add_view(data, target=None):
        while len(bin_) % 4:
            bin_.append(0)
        off = len(bin_)
        bin_.extend(data)
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1
    img_ids = {}
    gl_images = []
    for name, png in images.items():
        mime = "image/png"
        if isinstance(png, tuple):
            png, mime = png
        vi = add_view(png)
        img_ids[name] = len(gl_images)
        gl_images.append({"bufferView": vi, "mimeType": mime})
    textures = [{"sampler": 0, "source": i} for i in range(len(gl_images))]
    mats, prims = [], []
    for mname, P in mesh.parts.items():
        md = materials[mname]
        pos = np.array(P["pos"], np.float32)
        nr = np.array(P["nrm"], np.float32)
        uv = np.array(P["uv"], np.float32)
        mat = {"name": mname, "pbrMetallicRoughness": {"baseColorFactor": list(md["color"]) + [1.0], "metallicFactor": md["metal"], "roughnessFactor": md["rough"]}}
        if md.get("tex"):
            mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": img_ids[md["tex"]]}
        if md.get("ntex"):
            mat["normalTexture"] = {"index": img_ids[md["ntex"]], "scale": md.get("nscale", 1.0)}
        if md.get("unlit"):
            mat["extensions"] = {"KHR_materials_unlit": {}}
        if md.get("emissive"):
            mat["emissiveFactor"] = list(md["emissive"])
        mats.append(mat)
        a = []
        for arr, typ in ((pos, "VEC3"), (nr, "VEC3"), (uv, "VEC2")):
            vi = add_view(arr.tobytes(), 34962)
            acc = {"bufferView": vi, "componentType": 5126, "count": len(arr), "type": typ}
            if arr is pos:
                acc["min"] = pos.min(0).tolist(); acc["max"] = pos.max(0).tolist()
            accs.append(acc)
            a.append(len(accs) - 1)
        prims.append({"attributes": {"POSITION": a[0], "NORMAL": a[1], "TEXCOORD_0": a[2]}, "material": len(mats) - 1})
    nodes = [{"name": "model", "mesh": 0, "children": list(range(1, 1 + len(nodes_extra)))}]
    for nm, t in nodes_extra:
        nodes.append({"name": nm, "translation": list(map(float, t))})
    js = {"asset": {"version": "2.0", "generator": "dust-signal gunbuild"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": nodes,
          "meshes": [{"name": "gun", "primitives": prims}], "materials": mats, "accessors": accs, "bufferViews": views,
          "buffers": [{"byteLength": 0}], "extensionsUsed": ["KHR_materials_unlit"]}
    if gl_images:
        js["images"] = gl_images; js["textures"] = textures
        js["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
    while len(bin_) % 4:
        bin_.append(0)
    js["buffers"][0]["byteLength"] = len(bin_)
    jb = json.dumps(js, separators=(",", ":")).encode()
    while len(jb) % 4:
        jb += b" "
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(jb) + 8 + len(bin_))
    out += struct.pack("<II", len(jb), 0x4E4F534A) + jb + struct.pack("<II", len(bin_), 0x004E4942) + bytes(bin_)
    open(path, "wb").write(out)
    tris = sum(len(P["pos"]) for P in mesh.parts.values()) // 3
    return tris
