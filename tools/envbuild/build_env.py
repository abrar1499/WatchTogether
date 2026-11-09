"""Props and textures for the practice yard: shipping containers, wooden crates, concrete T-wall barriers,
fuel drums, sandbags, the small building; sand, rock and concrete textures for the ground, dunes, mountains
and boulders built in the game. All procedural (numpy), real sizes in metres.
Run: python3 build_env.py ../../godot/assets/env   (needs numpy, Pillow, mapbox_earcut)"""
import io, math, os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "gunbuild"))
from meshlib import Mesh, V, nrm, rounded, AX_Y, at, write_glb

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(OUT, exist_ok=True)
SEED = [100]

# ---------------- tileable noise ----------------
def fbm(n, beta=2.0, aniso=(1.0, 1.0)):
    SEED[0] += 1
    rng = np.random.default_rng(SEED[0])
    F = np.fft.fft2(rng.standard_normal((n, n)))
    fy = np.fft.fftfreq(n)[:, None] * aniso[1]
    fx = np.fft.fftfreq(n)[None, :] * aniso[0]
    f = np.sqrt(fx ** 2 + fy ** 2)
    f[0, 0] = 1.0
    F = F / f ** (beta / 2)
    F[0, 0] = 0
    a = np.real(np.fft.ifft2(F))
    return (a - a.mean()) / (a.std() + 1e-9)

def normal_map(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    n = np.stack([-dx * strength, dy * strength, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5

def img_bytes(a, fmt="JPEG"):
    b = io.BytesIO()
    Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8)).save(b, fmt, **({"quality": 88} if fmt == "JPEG" else {}))
    return (b.getvalue(), "image/jpeg" if fmt == "JPEG" else "image/png")

def save(a, name, fmt="JPEG"):
    Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8)).save(os.path.join(OUT, name), fmt, **({"quality": 90} if fmt == "JPEG" else {}))

def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)

# ---------------- textures ----------------
def tex_sand(n=1024):
    y, x = np.mgrid[0:n, 0:n] / n
    low = fbm(n, 3.2)
    warp = fbm(n, 3.0)
    ripple = np.sin(2 * math.pi * (13 * x + 2 * y + 0.9 * warp)) * (0.55 + 0.45 * smooth(-1, 1.5, fbm(n, 3.0)))
    grain = fbm(n, 0.3)
    h = ripple * 1.0 + grain * 0.18
    base = np.array([0.64, 0.56, 0.45])
    shade = 1 + 0.07 * low + 0.035 * grain - 0.035 * ripple
    alb = base[None, None, :] * shade[..., None]
    specks = (np.random.default_rng(3).random((n, n)) > 0.996)[..., None]
    alb = np.where(specks, alb * 0.6, alb)
    return alb, normal_map(h, 0.55)

def tex_concrete(n=512):
    blot = fbm(n, 2.6)
    mid = fbm(n, 1.6)
    pores = np.random.default_rng(5).random((n, n)) > 0.985
    base = np.array([0.47, 0.45, 0.41])
    shade = 1 + 0.035 * blot + 0.05 * mid + 0.03 * fbm(n, 0.6)
    shade = np.where(pores, shade * 0.72, shade)
    alb = base[None, None, :] * shade[..., None]
    h = mid * 0.4 - pores * 1.5
    return alb, normal_map(h, 0.9)

def tex_rock(n=512):
    big = fbm(n, 2.8)
    mid = fbm(n, 2.0)
    ridged = 1 - np.abs(fbm(n, 2.2))
    y = np.mgrid[0:n, 0:n][0] / n
    strata = np.sin(2 * math.pi * (6 * y + 0.6 * big))
    base = np.array([0.55, 0.47, 0.39])
    shade = 1 + 0.12 * big + 0.06 * mid + 0.04 * strata - 0.22 * smooth(0.85, 1.0, ridged)
    alb = base[None, None, :] * shade[..., None]
    h = big * 0.6 + mid * 0.4 + ridged ** 4 * 1.2 + strata * 0.15
    return alb, normal_map(h, 1.6)

def tex_paint(color, n=512, streaks=26, height_axis=0):
    """Painted steel with rust streaks running down from the top and dirt at the bottom.
    t = height fraction (0 bottom, 1 top) along image rows (height_axis 0) or columns (1)."""
    rng = np.random.default_rng(SEED[0] + 7)
    SEED[0] += 1
    yy, xx = np.mgrid[0:n, 0:n] / n
    t = yy if height_axis == 0 else xx
    s = xx if height_axis == 0 else yy
    var = fbm(n, 2.4)
    col = np.array(color)[None, None, :] * (1 + 0.05 * var)[..., None]
    rust = np.zeros((n, n))
    for i in range(streaks):
        c = rng.random()
        w = rng.uniform(0.003, 0.012)
        L = rng.uniform(0.15, 0.7)
        top = rng.uniform(0.85, 1.0)
        wob = 0.004 * np.sin(t * 40 + i)
        d = np.abs(((s - c - wob + 0.5) % 1.0) - 0.5)
        rust = np.maximum(rust, np.exp(-(d / w) ** 2) * smooth(top - L, top, t) * (t < top) * rng.uniform(0.4, 1.0))
    patches = smooth(0.9, 1.8, fbm(n, 2.2)) + smooth(0.12, 0.0, t) * smooth(0.0, 1.2, fbm(n, 2.0))
    rust = np.clip(rust + patches, 0, 1)
    rust_col = np.array([0.42, 0.2, 0.09])[None, None, :] * (1 + 0.2 * fbm(n, 1.5))[..., None]
    col = col * (1 - rust[..., None]) + rust_col * rust[..., None]
    dirt = smooth(0.18, 0.0, t) * (0.55 + 0.3 * fbm(n, 2.0))
    col = col * (1 - 0.45 * dirt[..., None]) + np.array([0.62, 0.52, 0.38])[None, None, :] * 0.45 * dirt[..., None]
    scratches = np.zeros((n, n))
    for i in range(40):
        x0, y0 = rng.random(2)
        ang = rng.uniform(0, math.pi)
        d = np.abs((xx - x0) * math.sin(ang) - (yy - y0) * math.cos(ang))
        along = np.abs((xx - x0) * math.cos(ang) + (yy - y0) * math.sin(ang))
        scratches = np.maximum(scratches, (d < 0.0015) * (along < rng.uniform(0.02, 0.08)) * 1.0)
    col = col * (1 - 0.35 * scratches[..., None]) + 0.35 * scratches[..., None] * np.array([0.55, 0.55, 0.55])
    return col

def tex_planks(n=512, planks=5):
    yy, xx = np.mgrid[0:n, 0:n] / n
    k = yy * planks
    idx = np.floor(k)
    f = k - idx
    rng = np.random.default_rng(9)
    tint = rng.uniform(0.85, 1.12, planks + 1)[idx.astype(int)]
    grain = np.sin(2 * math.pi * (yy * planks * 9 + 1.6 * fbm(n, 2.5, (0.25, 4.0))))
    knots = smooth(1.8, 2.6, fbm(n, 2.6))
    base = np.array([0.52, 0.38, 0.22])
    shade = tint * (1 + 0.08 * grain + 0.05 * fbm(n, 1.2)) * (1 - 0.35 * knots)
    seam = smooth(0.0, 0.03, f) * smooth(1.0, 0.97, f)
    shade = shade * (0.35 + 0.65 * seam)
    alb = base[None, None, :] * shade[..., None]
    h = seam * 1.0 + grain * 0.08
    return alb, normal_map(h, 2.5)

def tex_burlap(n=256):
    yy, xx = np.mgrid[0:n, 0:n] / n
    weave = np.sin(2 * math.pi * xx * 48) * np.sin(2 * math.pi * yy * 48)
    base = np.array([0.56, 0.5, 0.36])
    shade = 1 + 0.08 * weave + 0.08 * fbm(n, 2.0) + 0.05 * fbm(n, 0.5)
    alb = base[None, None, :] * shade[..., None]
    return alb, normal_map(weave * 0.5 + fbm(n, 1.0) * 0.3, 1.5)

def tex_plaster(n=512):
    yy, xx = np.mgrid[0:n, 0:n] / n
    t = yy
    blot = fbm(n, 2.8)
    base = np.array([0.8, 0.72, 0.6])
    shade = 1 + 0.06 * blot + 0.03 * fbm(n, 1.2)
    rng = np.random.default_rng(21)
    stain = np.zeros((n, n))
    for i in range(14):
        c = rng.random()
        w = rng.uniform(0.006, 0.03)
        L = rng.uniform(0.2, 0.6)
        d = np.abs(((xx - c + 0.5) % 1.0) - 0.5)
        stain = np.maximum(stain, np.exp(-(d / w) ** 2) * smooth(1 - L, 1.0, t) * 0.35)
    dirt = smooth(0.2, 0.0, t) * 0.4
    shade = shade * (1 - stain) * (1 - dirt)
    alb = base[None, None, :] * shade[..., None]
    return alb, normal_map(blot * 0.3 + fbm(n, 0.8) * 0.4, 1.2)

# ---------------- mesh helpers ----------------
def quad3(m, mat, p, n, uv):
    m.quad(mat, *[(p[i], n, uv[i]) for i in range(4)])

def corrugated(m, mat, origin, A, Y, O, length, y0, y1, pitch, depth, us):
    """Trapezoid corrugation along A, from y0 to y1 along Y, ribs out along O."""
    prof = []
    a = 0.0
    while a < length - 1e-6:
        for (da, do) in ((0.0, 0.0), (0.036, 0.0), (0.07, 1.0), (0.208, 1.0), (0.242, 0.0)):
            k = da * pitch / 0.278
            if a + k <= length + 1e-6:
                prof.append((a + k, do * depth))
        a += pitch
    prof.append((length, 0.0))
    origin, A, Y, O = (np.array(v, float) for v in (origin, A, Y, O))
    for i in range(len(prof) - 1):
        (a0, o0), (a1, o1) = prof[i], prof[i + 1]
        if a1 - a0 < 1e-6 and abs(o1 - o0) < 1e-6:
            continue
        t = nrm(A * (a1 - a0) + O * (o1 - o0))
        nn = nrm(np.cross(t, Y))
        if np.dot(nn, O) < 0:
            nn = -nn
        pts = [origin + A * a0 + O * o0 + Y * y0, origin + A * a1 + O * o1 + Y * y0, origin + A * a1 + O * o1 + Y * y1, origin + A * a0 + O * o0 + Y * y1]
        quad3(m, mat, pts, nn, [(a0 / us, y0 / us), (a1 / us, y0 / us), (a1 / us, y1 / us), (a0 / us, y1 / us)])

def box(m, mat, c, size, us=1.0, bevel=0.0, xf=None):
    """Axis box centred at c (x, y, z) of size (sx, sy, sz)."""
    cx, cy, cz = c
    sx, sy, sz = size
    pts = [V(cz - sz / 2, cy - sy / 2), V(cz + sz / 2, cy - sy / 2), V(cz + sz / 2, cy + sy / 2), V(cz - sz / 2, cy + sy / 2)]
    m.extrude(mat, pts, sx / 2, bevel=bevel, steps=1, cx=cx, us=us, vs=us, xf=xf)

def cyl_y(m, mat, x, z, y0, y1, r, seg=10):
    m.lathe(mat, [V(0, 0), V(0, r), V(y1 - y0, r), V(y1 - y0, 0)], seg=seg, xf=(AX_Y[0], V(x, y0, z)))

# ---------------- props ----------------
def container(color):
    m = Mesh()
    L, W, H = 6.06, 2.44, 2.59
    d = 0.036
    us = H
    for sx in (1, -1):
        corrugated(m, "paint", (sx * (W / 2 - d), 0, -L / 2), (0, 0, 1), (0, 1, 0), (sx, 0, 0), L, 0.14, H - 0.1, 0.278, d, us)
    corrugated(m, "paint", (-W / 2, 0, -L / 2 + d), (1, 0, 0), (0, 1, 0), (0, 0, -1), W, 0.14, H - 0.1, 0.278, d, us)
    # roof, rails, corner posts
    box(m, "paint", (0, H - 0.04, 0), (W - 0.1, 0.03, L - 0.1), us)
    for sx in (1, -1):
        box(m, "paint", (sx * (W / 2 - 0.06), 0.08, 0), (0.12, 0.16, L), us, 0.01)
        box(m, "paint", (sx * (W / 2 - 0.05), H - 0.05, 0), (0.1, 0.1, L), us, 0.01)
    for sz in (1, -1):
        box(m, "paint", (0, 0.08, sz * (L / 2 - 0.06)), (W, 0.16, 0.12), us, 0.01)
        box(m, "paint", (0, H - 0.06, sz * (L / 2 - 0.06)), (W, 0.12, 0.12), us, 0.01)
        for sx in (1, -1):
            box(m, "paint", (sx * (W / 2 - 0.075), H / 2, sz * (L / 2 - 0.075)), (0.15, H, 0.15), us, 0.01)
            for y in (0.06, H - 0.06):
                box(m, "dark", (sx * (W / 2 - 0.09), y, sz * (L / 2 - 0.085)), (0.18, 0.12, 0.17), us, 0.008)
    # doors: two panels with stiffeners, four lock rods with brackets and handles
    zd = L / 2 - 0.02
    for sx in (1, -1):
        box(m, "paint", (sx * (W / 4 - 0.03), H / 2, zd), (W / 2 - 0.12, H - 0.3, 0.03), us)
        for y in (0.5, 1.3, 2.1):
            box(m, "paint", (sx * (W / 4 - 0.03), y, zd + 0.025), (W / 2 - 0.16, 0.06, 0.02), us, 0.004)
        for rx in (0.3, 0.85):
            x = sx * rx
            cyl_y(m, "steel", x, zd + 0.06, 0.18, H - 0.18, 0.017)
            for y in (0.2, H - 0.2):
                box(m, "dark", (x, y, zd + 0.04), (0.08, 0.06, 0.05), us, 0.005)
            box(m, "steel", (x + sx * 0.06, 1.2, zd + 0.08), (0.16, 0.04, 0.03), us, 0.005)
        for y in (0.35, 1.3, 2.25):
            box(m, "dark", (sx * (W / 2 - 0.13), y, zd + 0.03), (0.06, 0.18, 0.04), us, 0.005)
    mats = {
        "paint": {"color": (1, 1, 1), "metal": 0.25, "rough": 0.62, "tex": "paint"},
        "dark": {"color": (0.08, 0.08, 0.08), "metal": 0.3, "rough": 0.7},
        "steel": {"color": (0.35, 0.33, 0.3), "metal": 0.6, "rough": 0.5},
    }
    imgs = {"paint": img_bytes(tex_paint(color))}
    return m, mats, imgs

def crate():
    m = Mesh()
    s = 1.3
    box(m, "planks", (0, s / 2, 0), (s - 0.04, s - 0.04, s - 0.04), s)
    t = 0.09
    for sx in (1, -1):
        for sz in (1, -1):
            box(m, "frame", (sx * (s / 2 - t / 2), s / 2, sz * (s / 2 - t / 2)), (t, s, t), s, 0.01)
    for y in (t / 2, s - t / 2):
        for sz in (1, -1):
            box(m, "frame", (0, y, sz * (s / 2 - t / 2)), (s - 2 * t, t, t), s, 0.01)
        for sx in (1, -1):
            box(m, "frame", (sx * (s / 2 - t / 2), y, 0), (t, t, s - 2 * t), s, 0.01)
    alb, nm = tex_planks()
    mats = {"planks": {"color": (1, 1, 1), "metal": 0.0, "rough": 0.85, "tex": "planks", "ntex": "planks_n"},
            "frame": {"color": (0.78, 0.74, 0.7), "metal": 0.0, "rough": 0.85, "tex": "planks", "ntex": "planks_n"}}
    return m, mats, {"planks": img_bytes(alb), "planks_n": img_bytes(nm, "PNG")}

def barrier():
    """One precast concrete T-wall segment, 1.95 m along x, 2.6 m tall."""
    m = Mesh()
    prof = [V(-0.4, 0), V(0.4, 0), V(0.4, 0.14), V(0.14, 0.44), V(0.11, 2.6), V(-0.11, 2.6), V(-0.14, 0.44), V(-0.4, 0.14)]
    m.extrude("concrete", rounded(prof, [0, 0, 0.02, 0.06, 0.02, 0.02, 0.06, 0.02], 2), 0.975, bevel=0.025, steps=1, us=2.0, vs=2.0)
    alb, nm = tex_concrete()
    mats = {"concrete": {"color": (1, 1, 1), "metal": 0.0, "rough": 0.92, "tex": "concrete", "ntex": "concrete_n"}}
    return m, mats, {"concrete": img_bytes(alb), "concrete_n": img_bytes(nm, "PNG")}

def drum(color):
    m = Mesh()
    R, H = 0.29, 0.88
    prof = [V(0, 0), V(0, R - 0.02), V(0.006, R + 0.003), V(0.022, R + 0.003), V(0.028, R - 0.004)]
    for hz in (0.29, 0.59):
        prof += [V(hz - 0.012, R - 0.004), V(hz - 0.004, R + 0.006), V(hz + 0.004, R + 0.006), V(hz + 0.012, R - 0.004)]
    prof += [V(H - 0.028, R - 0.004), V(H - 0.022, R + 0.003), V(H - 0.006, R + 0.003), V(H, R - 0.02), V(H - 0.015, R - 0.024), V(H - 0.015, 0)]
    m.lathe("paint", prof, seg=20, xf=(AX_Y[0], V(0, 0, 0)), us=H)
    cyl_y(m, "steel", 0.15, 0.0, H - 0.02, H - 0.005, 0.03, 8)
    mats = {"paint": {"color": (1, 1, 1), "metal": 0.3, "rough": 0.55, "tex": "paint"},
            "steel": {"color": (0.4, 0.4, 0.4), "metal": 0.6, "rough": 0.45}}
    return m, mats, {"paint": img_bytes(tex_paint(color, 256, 10, height_axis=1))}

def sandbag():
    m = Mesh()
    prof = [V(-0.27, 0.0), V(0.27, 0.0), V(0.28, 0.08), V(0.27, 0.16), V(-0.27, 0.16), V(-0.28, 0.08)]
    m.extrude("burlap", rounded(prof, [0.05, 0.05, 0.05, 0.05, 0.05, 0.05], 2), 0.14, bevel=0.055, steps=2, us=0.5, vs=0.5)
    alb, nm = tex_burlap()
    mats = {"burlap": {"color": (1, 1, 1), "metal": 0.0, "rough": 0.95, "tex": "burlap", "ntex": "burlap_n"}}
    return m, mats, {"burlap": img_bytes(alb), "burlap_n": img_bytes(nm, "PNG")}

def building():
    """10 x 7 m single-storey block, 3.2 m to the roof, parapet, door and windows on the yard side (+z)."""
    m = Mesh()
    W, D, H = 10.0, 7.0, 3.2
    box(m, "plaster", (0, H / 2, 0), (W, H, D), 3.2)
    # parapet round the roof, with a gap at the back of the east side where the outside stairs come up
    g0 = GAP_Z1
    for (c, s) in (((0, H + 0.2, D / 2 - 0.12), (W, 0.4, 0.24)), ((0, H + 0.2, -D / 2 + 0.12), (W, 0.4, 0.24)),
                   ((W / 2 - 0.12, H + 0.2, (g0 + D / 2) / 2), (0.24, 0.4, D / 2 - g0)), ((-W / 2 + 0.12, H + 0.2, 0), (0.24, 0.4, D))):
        box(m, "plaster", c, s, 3.2, 0.02)
    for (c, s) in (((0, H + 0.42, D / 2 - 0.12), (W + 0.04, 0.05, 0.3)), ((0, H + 0.42, -D / 2 + 0.12), (W + 0.04, 0.05, 0.3)),
                   ((W / 2 - 0.12, H + 0.42, (g0 + D / 2) / 2), (0.3, 0.05, D / 2 - g0)), ((-W / 2 + 0.12, H + 0.42, 0), (0.3, 0.05, D))):
        box(m, "trim", c, s, 3.2, 0.01)
    zf = D / 2
    # door
    box(m, "trim", (-2.2, 1.1, zf + 0.02), (1.25, 2.3, 0.06), 3.2, 0.01)
    box(m, "door", (-2.2, 1.04, zf + 0.05), (1.0, 2.08, 0.04), 3.2, 0.005)
    box(m, "steel", (-1.85, 1.0, zf + 0.09), (0.14, 0.03, 0.04), 3.2, 0.005)
    box(m, "trim", (-2.2, 2.35, zf + 0.12), (1.5, 0.06, 0.3), 3.2, 0.01)
    # windows (front and sides)
    def window(cx, cy, cz, ax):
        def b(mat, off, size):
            if ax == "z":
                box(m, mat, (cx + off[0], cy + off[1], cz + off[2]), size, 3.2, 0.005)
            else:
                box(m, mat, (cx + off[2], cy + off[1], cz + off[0]), (size[2], size[1], size[0]), 3.2, 0.005)
        sg = 1.0
        b("trim", (0, 0, 0.02 * sg), (1.35, 1.15, 0.05))
        b("glass", (0, 0, 0.05 * sg), (1.15, 0.95, 0.02))
        b("trim", (0, -0.6, 0.08 * sg), (1.45, 0.07, 0.16))
        for i in range(5):
            b("steel", (-0.46 + i * 0.23, 0, 0.08 * sg), (0.025, 0.95, 0.025))
    for x in (0.4, 2.9):
        window(x, 1.75, zf, "z")
    for z in (-1.5, 1.5):
        window(z, 1.75, W / 2, "x")
    # air conditioner and a roof tank
    box(m, "steel", (1.6, 2.7, zf + 0.25), (0.8, 0.55, 0.45), 3.2, 0.02)
    box(m, "dark", (1.6, 2.7, zf + 0.48), (0.6, 0.4, 0.02), 3.2, 0.0)
    m.lathe("tank", [V(0, 0), V(0, 0.55), V(0.05, 0.6), V(1.0, 0.6), V(1.08, 0.5), V(1.12, 0)], seg=16, xf=(AX_Y[0], V(-3.0, H, -1.5)))
    alb, nm = tex_plaster()
    mats = {"plaster": {"color": (1, 1, 1), "metal": 0.0, "rough": 0.95, "tex": "plaster", "ntex": "plaster_n"},
            "trim": {"color": (0.62, 0.58, 0.5), "metal": 0.0, "rough": 0.9},
            "door": {"color": (0.22, 0.27, 0.24), "metal": 0.4, "rough": 0.55, "tex": "doorpaint"},
            "glass": {"color": (0.05, 0.07, 0.08), "metal": 0.6, "rough": 0.12},
            "steel": {"color": (0.45, 0.45, 0.44), "metal": 0.55, "rough": 0.5},
            "dark": {"color": (0.06, 0.06, 0.06), "metal": 0.2, "rough": 0.8},
            "tank": {"color": (0.08, 0.08, 0.09), "metal": 0.0, "rough": 0.6}}
    return m, mats, {"plaster": img_bytes(alb), "plaster_n": img_bytes(nm, "PNG"), "doorpaint": img_bytes(tex_paint((0.85, 0.85, 0.85), 256, 6))}

GAP_Z1 = -2.1   # building: the east parapet stops here (local z); the stairs' landing meets the roof behind it

def stairs():
    """Outside concrete stairs up to the building's roof: 16 steps of 0.2 x 0.3 m, 1.1 m wide, rising toward -z from
    z = 0, then a 1.2 m landing at 3.2 m. Steel railing on the open side (+x) and across the end of the landing."""
    m = Mesh()
    n, rise, run, wd = 16, 0.2, 0.3, 1.1
    for i in range(n):
        top = (i + 1) * rise
        box(m, "concrete", (0, top / 2, -(i + 0.5) * run), (wd, top, run), 2.0, 0.008)
    z0, z1 = -n * run, -n * run - 1.2
    box(m, "concrete", (0, 3.2 - 0.11, (z0 + z1) / 2), (wd, 0.22, 1.2), 2.0, 0.01)
    for z in (z0 - 0.1, z1 + 0.1):
        box(m, "concrete", (0.4, 1.5, z), (0.22, 3.0, 0.22), 2.0, 0.01)
    # railing: posts, a sloping handrail up the flight, a level one round the landing
    def post(z, y0):
        box(m, "steel", (0.52, y0 + 0.5, z), (0.045, 1.0, 0.045), 1.0, 0.004)
    def rail(a, b, size=0.05):
        a, b = np.array(a, float), np.array(b, float)
        d = b - a
        L = float(np.linalg.norm(d))
        zt = d / L
        yt = nrm(np.cross(zt, np.array([1.0, 0, 0])))
        if yt[1] < 0:
            yt = -yt
        xt = np.cross(yt, zt)
        R = np.stack([xt, yt, zt], axis=1)
        box(m, "steel", (0, 0, 0), (size, size, L), 1.0, 0.004, xf=(R, (a + b) / 2))
    for k in range(5):
        z = -0.15 - k * 1.15
        post(z, rise * (int(-z / run) + 1))
    post(z0 - 0.05, 3.2)
    post(z1 + 0.03, 3.2)
    post(z1 + 0.03, 3.2)
    y_at = lambda z: rise * (-z / run) + 0.2
    rail((0.52, y_at(-0.15) + 0.95, -0.15), (0.52, 3.2 + 0.95, z0 - 0.05))
    rail((0.52, y_at(-0.15) + 0.5, -0.15), (0.52, 3.2 + 0.5, z0 - 0.05), 0.03)
    rail((0.52, 4.15, z0 - 0.05), (0.52, 4.15, z1 + 0.03))
    rail((0.52, 3.7, z0 - 0.05), (0.52, 3.7, z1 + 0.03), 0.03)
    rail((0.52, 4.15, z1 + 0.03), (-0.55, 4.15, z1 + 0.03))
    rail((0.52, 3.7, z1 + 0.03), (-0.55, 3.7, z1 + 0.03), 0.03)
    box(m, "steel", (-0.53, 3.7, z1 + 0.03), (0.045, 1.0, 0.045), 1.0, 0.004)
    alb, nm = tex_concrete()
    mats = {"concrete": {"color": (0.9, 0.88, 0.84), "metal": 0.0, "rough": 0.92, "tex": "concrete", "ntex": "concrete_n"},
            "steel": {"color": (0.2, 0.24, 0.2), "metal": 0.5, "rough": 0.55}}
    return m, mats, {"concrete": img_bytes(alb), "concrete_n": img_bytes(nm, "PNG")}

ONLY = [x for x in os.environ.get("ONLY", "").split(",") if x]   # rebuild just these (the rest is still built, so the noise is the same)

def emit(name, built, nodes=()):
    if ONLY and name not in ONLY:
        return
    m, mats, imgs = built
    used = {k: mats[k] for k in m.parts}
    keep = {k: v for k, v in imgs.items() if any(mats[u].get("tex") == k or mats[u].get("ntex") == k for u in used)}
    tris = write_glb(os.path.join(OUT, name + ".glb"), m, used, keep, list(nodes))
    print("%-16s %6d triangles  %5d KB" % (name, tris, os.path.getsize(os.path.join(OUT, name + ".glb")) // 1024))

emit("container_red", container((0.52, 0.13, 0.09)))
emit("container_blue", container((0.12, 0.24, 0.42)))
emit("container_green", container((0.2, 0.3, 0.18)))
emit("crate", crate())
emit("barrier", barrier())
emit("drum_blue", drum((0.1, 0.22, 0.45)))
emit("drum_red", drum((0.55, 0.14, 0.08)))
emit("sandbag", sandbag())
emit("building", building())
for nm_, fn in (("sand", tex_sand), ("rock", tex_rock)):
    alb, nmap = fn()
    if not ONLY or "textures" in ONLY:
        save(alb, nm_ + "_albedo.jpg")
        save(nmap, nm_ + "_normal.png", "PNG")
print("textures done")
emit("stairs", stairs())
