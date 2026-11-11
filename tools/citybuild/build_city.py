"""Vehicles for the city mission: a family saloon (painted, dusty) and a burnt-out one, a town bus and a burnt one,
and a militia pickup with a machine gun on a post in the bed. Side profiles extruded with bevelled edges (the gun
kit), real sizes in metres, +z is the front, y up from the ground.
Run: python3 build_city.py ../../godot/assets/city   (needs numpy, Pillow, mapbox_earcut)"""
import io, os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "gunbuild"))
from meshlib import Mesh, V, rounded, write_glb

# vehicles are big: one texture tile across about 3 m (the gun kit's defaults tile every few centimetres)
Mesh.extrude.__defaults__ = (0.0, 2, 0.0, 42, 3.0, 3.0, None, True)
Mesh.lathe.__defaults__ = (20, (0.0, 0.0), 40, 3.0, 3.0, None, 0.0)
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(31)
X_AXIS = np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]], float)   # lathe frame: its axis along x (wheels)


def noise(n, octaves=5):
    """Value noise, tileable, 0..1."""
    acc = np.zeros((n, n))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        k = 4 * 2 ** o
        g = rng.random((k, k))
        g = np.kron(g, np.ones((n // k, n // k)))
        for _ in range(2):
            g = (g + np.roll(g, 1, 0) + np.roll(g, -1, 0) + np.roll(g, 1, 1) + np.roll(g, -1, 1)) / 5.0
        acc += g * amp
        tot += amp
        amp *= 0.55
    acc /= tot
    return (acc - acc.min()) / (acc.max() - acc.min() + 1e-9)


def img_bytes(a):
    im = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    b = io.BytesIO()
    im.save(b, "JPEG", quality=88)
    return (b.getvalue(), "image/jpeg")


def tex_paint(color, dust=0.35):
    n = 256
    d = noise(n)
    streak = noise(n, 3)
    c = np.array(color)[None, None, :]
    dustc = np.array([0.62, 0.57, 0.5])[None, None, :]
    k = np.clip((d * 0.7 + streak * 0.3 - (1.0 - dust)) * 2.2, 0, 1)[..., None]
    return img_bytes(c * (0.9 + 0.1 * d[..., None]) * (1 - k) + dustc * k)


def tex_burnt():
    n = 256
    d = noise(n)
    r = noise(n, 4)
    black = np.array([0.06, 0.055, 0.05])
    rust = np.array([0.36, 0.17, 0.07])
    ash = np.array([0.32, 0.31, 0.29])
    k1 = np.clip((r - 0.45) * 3.0, 0, 1)[..., None]
    k2 = np.clip((d - 0.7) * 4.0, 0, 1)[..., None]
    a = black * (1 - k1) + rust * k1
    return img_bytes(a * (1 - k2) + ash * k2)


def wheel(m, z, x, y, r, w, burnt):
    tire = [V(-w / 2, 0), V(-w / 2, r - 0.03), V(-w / 2 + 0.03, r), V(w / 2 - 0.03, r), V(w / 2, r - 0.03), V(w / 2, 0)]
    if not burnt:
        m.lathe("rubber", tire, seg=18, xf=(X_AXIS, V(x, y, z)))
        m.lathe("rim", [V(-w / 2 - 0.002, 0), V(-w / 2 - 0.002, r * 0.62), V(w / 2 + 0.002, r * 0.62), V(w / 2 + 0.002, 0)], seg=14, xf=(X_AXIS, V(x, y, z)))
    else:
        rr = r * 0.66
        m.lathe("rust", [V(-w / 2, 0), V(-w / 2, rr), V(w / 2, rr), V(w / 2, 0)], seg=14, xf=(X_AXIS, V(x, y, z)))


def saloon(burnt=False):
    m = Mesh()
    body = "burnt" if burnt else "paint"
    glass = "char" if burnt else "glass"
    y0 = -0.1 if burnt else 0.0          # a burnt car sits on its rims
    lower = [V(-2.25, 0.32), V(2.25, 0.32), V(2.3, 0.55), V(2.22, 0.78), V(1.15, 0.9), V(-1.55, 0.94), V(-2.2, 0.9), V(-2.3, 0.62)]
    m.extrude(body, rounded([p + V(0, y0) for p in lower], [0.06, 0.06, 0.12, 0.15, 0.1, 0.1, 0.12, 0.08], 3), 0.86, bevel=0.07, steps=3)
    m.extrude(glass, [V(1.12, 0.9 + y0), V(0.45, 1.36 + y0), V(-0.8, 1.4 + y0), V(-1.5, 0.94 + y0)], 0.74, bevel=0.03, steps=1)
    m.extrude(body, [V(0.42, 1.36 + y0), V(-0.78, 1.4 + y0), V(-0.78, 1.45 + y0), V(0.4, 1.41 + y0)], 0.77, bevel=0.03, steps=1)
    for cx in (0.745, -0.745):
        m.extrude(body, [V(1.12, 0.9 + y0), V(1.03, 0.9 + y0), V(0.38, 1.37 + y0), V(0.47, 1.37 + y0)], 0.03, steps=1, cx=cx)
        m.extrude(body, [V(-0.18, 0.94 + y0), V(-0.06, 0.94 + y0), V(-0.06, 1.4 + y0), V(-0.18, 1.4 + y0)], 0.03, steps=1, cx=cx)
        m.extrude(body, [V(-0.8, 1.4 + y0), V(-0.94, 1.4 + y0), V(-1.56, 0.94 + y0), V(-1.42, 0.94 + y0)], 0.03, steps=1, cx=cx)
    trim = "rust" if burnt else "plastic"
    m.extrude(trim, rounded([V(2.2, 0.3 + y0), V(2.36, 0.3 + y0), V(2.36, 0.52 + y0), V(2.2, 0.52 + y0)], 0.03, 2), 0.88, bevel=0.03, steps=1)
    m.extrude(trim, rounded([V(-2.36, 0.3 + y0), V(-2.2, 0.3 + y0), V(-2.2, 0.52 + y0), V(-2.36, 0.52 + y0)], 0.03, 2), 0.88, bevel=0.03, steps=1)
    if not burnt:
        for cx in (0.6, -0.6):
            m.extrude("lamp", [V(2.22, 0.62), V(2.29, 0.62), V(2.26, 0.74), V(2.19, 0.74)], 0.16, steps=1, cx=cx)
            m.extrude("tail", [V(-2.31, 0.66), V(-2.24, 0.66), V(-2.24, 0.8), V(-2.3, 0.8)], 0.15, steps=1, cx=cx)
    for z in (1.38, -1.38):
        for x in (0.78, -0.78):
            wheel(m, z, x, 0.32 + y0 * 0.5, 0.32, 0.2, burnt)
    return m


def bus(burnt=False):
    m = Mesh()
    body = "burnt" if burnt else "paint"
    glass = "char" if burnt else "glass"
    y0 = -0.12 if burnt else 0.0
    prof = [V(-5.0, 0.38), V(5.0, 0.38), V(5.05, 0.9), V(4.96, 2.85), V(4.75, 3.05), V(-4.9, 3.05), V(-5.05, 2.8)]
    m.extrude(body, rounded([p + V(0, y0) for p in prof], [0.08, 0.08, 0.1, 0.25, 0.2, 0.2, 0.15], 3), 1.25, bevel=0.08, steps=3)
    # the window band down both sides, broken by pillars; windscreen; a stripe
    m.extrude(glass, [V(-4.6, 1.5 + y0), V(4.35, 1.5 + y0), V(4.35, 2.6 + y0), V(-4.6, 2.6 + y0)], 1.262, steps=1)
    z = -4.6
    while z < 4.4:
        m.extrude(body, [V(z - 0.05, 1.48 + y0), V(z + 0.05, 1.48 + y0), V(z + 0.05, 2.62 + y0), V(z - 0.05, 2.62 + y0)], 1.268, steps=1)
        z += 1.25
    m.extrude(glass, [V(4.98, 1.3 + y0), V(5.07, 1.3 + y0), V(4.99, 2.72 + y0), V(4.9, 2.72 + y0)], 1.1, steps=1)
    m.extrude("stripe" if not burnt else "rust", [V(-5.02, 1.1 + y0), V(5.04, 1.1 + y0), V(5.04, 1.25 + y0), V(-5.02, 1.25 + y0)], 1.258, steps=1)
    for z in (3.3, -3.0):
        for x in (1.1, -1.1):
            wheel(m, z, x, 0.48 + y0 * 0.5, 0.48, 0.28, burnt)
    return m


def pickup():
    m = Mesh()
    # chassis and lower body from the bed's tail to the bumper
    lower = [V(-2.6, 0.48), V(2.4, 0.48), V(2.46, 0.78), V(2.36, 1.02), V(1.2, 1.08), V(1.0, 1.08), V(-2.6, 1.02)]
    m.extrude("paint", rounded(lower, [0.05, 0.06, 0.1, 0.12, 0.05, 0.05, 0.05], 3), 0.9, bevel=0.06, steps=3)
    m.extrude("glass", [V(1.18, 1.08), V(0.6, 1.72), V(-0.25, 1.75), V(-0.3, 1.08)], 0.8, bevel=0.03, steps=1)
    m.extrude("paint", [V(0.58, 1.72), V(-0.26, 1.74), V(-0.26, 1.8), V(0.56, 1.78)], 0.82, bevel=0.03, steps=1)
    for cx in (0.81, -0.81):
        m.extrude("paint", [V(1.18, 1.08), V(1.08, 1.08), V(0.52, 1.74), V(0.62, 1.74)], 0.03, steps=1, cx=cx)
        m.extrude("paint", [V(-0.32, 1.08), V(-0.2, 1.08), V(-0.2, 1.76), V(-0.32, 1.76)], 0.03, steps=1, cx=cx)
    # bed walls
    for cx in (0.86, -0.86):
        m.extrude("paint", [V(-2.6, 1.0), V(-0.4, 1.0), V(-0.4, 1.38), V(-2.6, 1.38)], 0.04, steps=1, cx=cx)
    m.extrude("paint", [V(-2.62, 1.0), V(-2.54, 1.0), V(-2.54, 1.38), V(-2.62, 1.38)], 0.9, steps=1)
    m.extrude("paint", [V(-0.44, 1.0), V(-0.36, 1.0), V(-0.36, 1.45), V(-0.44, 1.45)], 0.9, steps=1)
    m.extrude("plastic", rounded([V(2.3, 0.42), V(2.5, 0.42), V(2.5, 0.66), V(2.3, 0.66)], 0.03, 2), 0.95, bevel=0.03, steps=1)
    for cx in (0.62, -0.62):
        m.extrude("lamp", [V(2.36, 0.8), V(2.43, 0.8), V(2.4, 0.92), V(2.33, 0.92)], 0.16, steps=1, cx=cx)
    # the machine gun on its post, with a shield
    m.lathe("gunmetal", [V(1.0, 0), V(1.0, 0.05), V(2.15, 0.05), V(2.15, 0)], seg=10, xf=(np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], float), V(0, 0, -1.5)))
    m.extrude("gunmetal", rounded([V(-1.75, 2.1), V(-1.0, 2.1), V(-1.0, 2.3), V(-1.75, 2.3)], 0.03, 2), 0.09, bevel=0.02, steps=1)
    m.lathe("gunmetal", [V(-1.0, 0), V(-1.0, 0.025), V(-0.05, 0.025), V(-0.05, 0)], seg=10, center=(0, 2.22))
    m.extrude("gunmetal", [V(-1.0, 2.0), V(-0.96, 2.0), V(-0.96, 2.62), V(-1.0, 2.62)], 0.35, steps=1)
    for z in (1.55, -1.75):
        for x in (0.82, -0.82):
            wheel(m, z, x, 0.4, 0.4, 0.26, False)
    return m


# ---------------- 2026: modern saloon, SUV, city bus ----------------
def wheel26(m, z, x, y, r, w):
    tire = [V(-w / 2, 0), V(-w / 2, r - 0.04), V(-w / 2 + 0.04, r), V(w / 2 - 0.04, r), V(w / 2, r - 0.04), V(w / 2, 0)]
    m.lathe("rubber", tire, seg=20, xf=(X_AXIS, V(x, y, z)))
    m.lathe("alloy", [V(-w / 2 - 0.003, 0), V(-w / 2 - 0.003, r * 0.72), V(w / 2 + 0.003, r * 0.72), V(w / 2 + 0.003, 0)], seg=16, xf=(X_AXIS, V(x, y, z)))


def sedan26():
    """A modern four-door: long smooth body, glasshouse running into a fastback, full-width light bars."""
    m = Mesh()
    lower = [V(-2.4, 0.3), V(2.4, 0.3), V(2.46, 0.5), V(2.38, 0.72), V(1.35, 0.88), V(-1.75, 0.95), V(-2.38, 0.88), V(-2.46, 0.6)]
    m.extrude("paint", rounded(lower, [0.08, 0.08, 0.18, 0.28, 0.2, 0.22, 0.2, 0.14], 6), 0.9, bevel=0.1, steps=4)
    glass = [V(1.36, 0.87), V(0.58, 1.36), V(-0.7, 1.43), V(-1.78, 0.94)]
    m.extrude("glass", rounded(glass, [0.04, 0.32, 0.45, 0.04], 6), 0.76, bevel=0.06, steps=3)
    m.extrude("plastic", [V(-1.95, 0.3), V(1.95, 0.3), V(1.95, 0.4), V(-1.95, 0.4)], 0.915, steps=1)
    m.extrude("led", [V(2.35, 0.69), V(2.43, 0.69), V(2.41, 0.74), V(2.33, 0.74)], 0.72, steps=1)
    m.extrude("tail", [V(-2.45, 0.79), V(-2.38, 0.79), V(-2.38, 0.83), V(-2.44, 0.83)], 0.78, steps=1)
    for z in (1.45, -1.48):
        for x in (0.8, -0.8):
            wheel26(m, z, x, 0.34, 0.34, 0.24)
    return m


def suv26():
    m = Mesh()
    lower = [V(-2.35, 0.42), V(2.35, 0.42), V(2.43, 0.66), V(2.36, 0.98), V(1.55, 1.1), V(-2.28, 1.14), V(-2.43, 0.76)]
    m.extrude("paint", rounded(lower, [0.08, 0.08, 0.15, 0.25, 0.15, 0.15, 0.12], 6), 0.95, bevel=0.1, steps=4)
    glass = [V(1.56, 1.09), V(0.98, 1.68), V(-2.08, 1.72), V(-2.28, 1.13)]
    m.extrude("glass", rounded(glass, [0.04, 0.2, 0.12, 0.04], 5), 0.84, bevel=0.06, steps=3)
    for cx in (0.62, -0.62):
        m.extrude("alloy", [V(0.8, 1.73), V(-1.9, 1.75), V(-1.9, 1.79), V(0.8, 1.77)], 0.025, steps=1, cx=cx)
    m.extrude("plastic", [V(-1.85, 0.42), V(1.85, 0.42), V(1.85, 0.56), V(-1.85, 0.56)], 0.97, steps=1)
    m.extrude("led", [V(2.33, 0.92), V(2.41, 0.92), V(2.39, 0.97), V(2.31, 0.97)], 0.78, steps=1)
    m.extrude("tail", [V(-2.43, 1.0), V(-2.37, 1.0), V(-2.37, 1.05), V(-2.42, 1.05)], 0.82, steps=1)
    for z in (1.5, -1.45):
        for x in (0.84, -0.84):
            wheel26(m, z, x, 0.38, 0.38, 0.26)
    return m


def bus26():
    """A low-floor city bus: deep glazing almost to the floor, a big curved windscreen, an LED route sign."""
    m = Mesh()
    prof = [V(-5.9, 0.32), V(5.9, 0.32), V(6.0, 0.8), V(5.92, 2.95), V(5.6, 3.15), V(-5.8, 3.15), V(-6.0, 2.9)]
    m.extrude("paint", rounded(prof, [0.08, 0.08, 0.15, 0.3, 0.3, 0.25, 0.2], 5), 1.27, bevel=0.1, steps=3)
    m.extrude("glass", [V(-5.5, 1.0), V(5.2, 1.0), V(5.2, 2.75), V(-5.5, 2.75)], 1.282, steps=1)
    z = -5.5
    while z < 5.3:
        m.extrude("plastic", [V(z - 0.04, 0.98), V(z + 0.04, 0.98), V(z + 0.04, 2.77), V(z - 0.04, 2.77)], 1.29, steps=1)
        z += 1.5
    m.extrude("glass", rounded([V(5.88, 0.9), V(6.04, 0.9), V(5.98, 2.85), V(5.82, 2.85)], 0.04, 2), 1.18, steps=1)
    m.extrude("route", [V(5.86, 2.88), V(5.95, 2.88), V(5.93, 3.05), V(5.84, 3.05)], 0.8, steps=1)
    m.extrude("stripe", [V(-5.95, 0.78), V(5.98, 0.78), V(5.98, 0.92), V(-5.95, 0.92)], 1.276, steps=1)
    m.extrude("led", [V(5.95, 0.55), V(6.02, 0.55), V(6.01, 0.62), V(5.94, 0.62)], 1.0, steps=1)
    for z in (4.2, -3.4):
        for x in (1.12, -1.12):
            wheel26(m, z, x, 0.48, 0.48, 0.3)
    return m


def emit(name, m, mats, imgs):
    used = {k: mats[k] for k in m.parts}
    keep = {k: v for k, v in imgs.items() if any(mats[u].get("tex") == k for u in used)}
    write_glb(os.path.join(OUT, name + ".glb"), m, used, keep, [])
    print("%-14s %6d KB" % (name, os.path.getsize(os.path.join(OUT, name + ".glb")) // 1024))


base = {"glass": {"color": (0.05, 0.07, 0.08), "metal": 0.6, "rough": 0.15},
        "char": {"color": (0.04, 0.035, 0.03), "metal": 0.0, "rough": 1.0},
        "rubber": {"color": (0.06, 0.06, 0.06), "metal": 0.0, "rough": 0.9},
        "rim": {"color": (0.55, 0.55, 0.53), "metal": 0.7, "rough": 0.4},
        "plastic": {"color": (0.08, 0.08, 0.08), "metal": 0.0, "rough": 0.7},
        "lamp": {"color": (0.85, 0.85, 0.8), "metal": 0.3, "rough": 0.2},
        "tail": {"color": (0.5, 0.05, 0.03), "metal": 0.2, "rough": 0.3, "emissive": (0.35, 0.02, 0.01)},
        "rust": {"color": (1, 1, 1), "metal": 0.2, "rough": 0.95, "tex": "burnt"},
        "burnt": {"color": (1, 1, 1), "metal": 0.2, "rough": 0.95, "tex": "burnt"},
        "gunmetal": {"color": (0.1, 0.1, 0.1), "metal": 0.7, "rough": 0.45},
        "stripe": {"color": (0.55, 0.12, 0.08), "metal": 0.2, "rough": 0.6},
        "alloy": {"color": (0.12, 0.12, 0.13), "metal": 0.8, "rough": 0.3},
        "led": {"color": (0.95, 0.97, 1.0), "metal": 0.0, "rough": 0.3, "emissive": (0.9, 0.95, 1.0)},
        "route": {"color": (1.0, 0.6, 0.15), "metal": 0.0, "rough": 0.4, "emissive": (1.0, 0.55, 0.12)}}
burnt_img = tex_burnt()
for name, colour in (("car_white", (0.78, 0.78, 0.75)), ("car_blue", (0.16, 0.25, 0.4)), ("car_red", (0.45, 0.1, 0.08))):
    mats = dict(base, paint={"color": (1, 1, 1), "metal": 0.35, "rough": 0.5, "tex": "paint"})
    emit(name, saloon(), mats, {"paint": tex_paint(colour, 0.45), "burnt": burnt_img})
emit("car_burnt", saloon(True), dict(base), {"burnt": burnt_img})
emit("bus", bus(), dict(base, paint={"color": (1, 1, 1), "metal": 0.3, "rough": 0.55, "tex": "paint"}), {"paint": tex_paint((0.82, 0.78, 0.66), 0.5)})
emit("bus_burnt", bus(True), dict(base), {"burnt": burnt_img})
emit("pickup", pickup(), dict(base, paint={"color": (1, 1, 1), "metal": 0.3, "rough": 0.55, "tex": "paint"}), {"paint": tex_paint((0.6, 0.58, 0.5), 0.55)})

for name, colour in (("sedan_white", (0.88, 0.88, 0.86)), ("sedan_black", (0.06, 0.06, 0.07)), ("sedan_silver", (0.58, 0.6, 0.62)),
                     ("sedan_blue", (0.08, 0.16, 0.32)), ("sedan_red", (0.5, 0.06, 0.05))):
    emit(name, sedan26(), dict(base, paint={"color": (1, 1, 1), "metal": 0.55, "rough": 0.28, "tex": "paint"}), {"paint": tex_paint(colour, 0.15)})
for name, colour in (("suv_black", (0.05, 0.05, 0.06)), ("suv_white", (0.86, 0.86, 0.84)), ("suv_grey", (0.32, 0.34, 0.36))):
    emit(name, suv26(), dict(base, paint={"color": (1, 1, 1), "metal": 0.55, "rough": 0.3, "tex": "paint"}), {"paint": tex_paint(colour, 0.2)})
emit("bus_city", bus26(), dict(base, paint={"color": (1, 1, 1), "metal": 0.35, "rough": 0.35, "tex": "paint"},
     stripe={"color": (0.05, 0.45, 0.48), "metal": 0.2, "rough": 0.4}), {"paint": tex_paint((0.9, 0.9, 0.88), 0.12)})


# ---------------- mission 3: service and army vehicles, a forklift ----------------
def box(m, mat, x0, x1, y0, y1, hw, cx=0.0, r=0.03):
    """a rounded block from x0 to x1 (along the vehicle), y0 to y1 (up), half width hw, centred cx across"""
    m.extrude(mat, rounded([V(x0, y0), V(x1, y0), V(x1, y1), V(x0, y1)], r, 2), hw, bevel=min(r, hw * 0.5), steps=1, cx=cx)


def police():
    m = saloon(False)
    box(m, "stripe", -1.5, 1.05, 0.6, 0.74, 0.875)            # the band down both sides
    box(m, "plastic", -0.45, -0.1, 1.45, 1.5, 0.55)            # the bar's base on the roof
    box(m, "bar_r", -0.42, -0.13, 1.5, 1.6, 0.26, cx=0.28)
    box(m, "bar_b", -0.42, -0.13, 1.5, 1.6, 0.26, cx=-0.28)
    box(m, "plastic", 2.3, 2.42, 0.34, 0.6, 0.7)                # a push bar
    return m


def van(burnt=False):
    m = Mesh()
    body = "burnt" if burnt else "paint"
    glass = "char" if burnt else "glass"
    prof = [V(-2.9, 0.42), V(2.5, 0.42), V(2.75, 0.75), V(2.7, 1.15), V(2.0, 1.25), V(1.45, 2.05), V(1.2, 2.45), V(-2.9, 2.45)]
    m.extrude(body, rounded(prof, [0.06, 0.08, 0.12, 0.12, 0.08, 0.15, 0.15, 0.1], 3), 1.02, bevel=0.07, steps=3)
    m.extrude(glass, [V(2.02, 1.28), V(1.5, 2.0), V(1.42, 2.0), V(1.94, 1.28)], 0.9, steps=1)           # windscreen
    for cx in (1.03, -1.03):
        m.extrude(glass, [V(0.75, 1.35), V(1.75, 1.35), V(1.3, 1.98), V(0.75, 1.98)], 0.012, steps=1, cx=cx)   # cab side windows
    box(m, "rust" if burnt else "plastic", 2.6, 2.86, 0.4, 0.66, 0.98)
    box(m, "rust" if burnt else "plastic", -3.0, -2.86, 0.4, 0.66, 0.98)
    for z in (1.75, -1.85):
        for x in (0.92, -0.92):
            wheel(m, z, x, 0.38, 0.38, 0.24, burnt)
    return m


def ambulance():
    m = van(False)
    for cx in (1.03, -1.03):
        m.extrude("stripe", [V(-2.8, 1.25), V(0.6, 1.25), V(0.6, 1.5), V(-2.8, 1.5)], 0.014, steps=1, cx=cx)
        m.extrude("stripe", [V(-1.4, 1.65), V(-1.2, 1.65), V(-1.2, 2.25), V(-1.4, 2.25)], 0.014, steps=1, cx=cx)   # the cross
        m.extrude("stripe", [V(-1.6, 1.85), V(-1.0, 1.85), V(-1.0, 2.05), V(-1.6, 2.05)], 0.014, steps=1, cx=cx)
    box(m, "bar_r", 0.9, 1.15, 2.45, 2.56, 0.3, cx=0.4)
    box(m, "bar_b", 0.9, 1.15, 2.45, 2.56, 0.3, cx=-0.4)
    return m


def truck_mil():
    """an army cargo truck: bonnet, cab, a canvas tilt over the bed, three axles"""
    m = Mesh()
    box(m, "paint", -3.9, 3.3, 0.72, 0.95, 0.95)                                  # the frame
    bonnet = [V(1.75, 0.95), V(3.25, 0.95), V(3.35, 1.25), V(3.25, 1.75), V(1.75, 1.85)]
    m.extrude("paint", rounded(bonnet, [0.04, 0.08, 0.1, 0.12, 0.04], 3), 0.85, bevel=0.07, steps=3)
    cab = [V(0.55, 0.95), V(1.8, 0.95), V(1.8, 1.85), V(1.55, 2.55), V(0.55, 2.6)]
    m.extrude("paint", rounded(cab, [0.04, 0.04, 0.06, 0.12, 0.1], 3), 1.08, bevel=0.07, steps=3)
    m.extrude("glass", [V(1.78, 1.9), V(1.6, 2.44), V(1.52, 2.44), V(1.7, 1.9)], 0.95, steps=1)
    for cx in (1.09, -1.09):
        m.extrude("glass", [V(0.75, 1.9), V(1.6, 1.9), V(1.45, 2.42), V(0.75, 2.42)], 0.012, steps=1, cx=cx)
    box(m, "paint", -3.95, 0.4, 0.95, 1.5, 1.2)                                   # the bed's sides
    tilt = [V(-3.9, 1.5), V(0.35, 1.5), V(0.35, 2.75), V(0.2, 2.95), V(-3.75, 2.95), V(-3.9, 2.75)]
    m.extrude("canvas", rounded(tilt, [0.03, 0.03, 0.1, 0.15, 0.15, 0.1], 3), 1.17, bevel=0.1, steps=3)
    box(m, "plastic", 3.3, 3.5, 0.75, 1.05, 1.0)                                  # bumper
    for cx in (0.62, -0.62):
        m.extrude("lamp", [V(3.3, 1.3), V(3.38, 1.3), V(3.36, 1.5), V(3.28, 1.5)], 0.13, steps=1, cx=cx)
    for z in (2.55, -1.6, -2.9):
        for x in (0.95, -0.95):
            wheel(m, z, x, 0.55, 0.55, 0.32, False)
    return m


def apc():
    """an armoured 4x4: sloped nose, slab sides, small armoured glass, a hatch ring on the roof"""
    m = Mesh()
    hull = [V(-2.7, 0.75), V(2.2, 0.75), V(2.75, 1.05), V(2.6, 1.5), V(1.5, 1.7), V(1.05, 2.45), V(-2.55, 2.45), V(-2.75, 2.1)]
    m.extrude("paint", rounded(hull, [0.05, 0.08, 0.08, 0.08, 0.06, 0.1, 0.1, 0.08], 2), 1.15, bevel=0.1, steps=2)
    m.extrude("glass", [V(1.5, 1.78), V(1.14, 2.36), V(1.08, 2.36), V(1.44, 1.78)], 0.95, steps=1)
    for cx in (1.16, -1.16):
        m.extrude("glass", [V(0.2, 1.85), V(0.95, 1.85), V(0.85, 2.25), V(0.2, 2.25)], 0.012, steps=1, cx=cx)
        m.extrude("glass", [V(-1.6, 1.9), V(-0.9, 1.9), V(-0.9, 2.2), V(-1.6, 2.2)], 0.012, steps=1, cx=cx)
        box(m, "plastic", -2.6, 2.1, 0.7, 0.9, 0.05, cx=cx * 1.03)                # running boards
    m.lathe("gunmetal", [V(0.0, 0.5), V(0.1, 0.5), V(0.1, 0.62), V(0.0, 0.62)], seg=14, xf=(np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], float), V(0, 2.45, -0.6)))
    box(m, "plastic", 2.7, 2.9, 0.8, 1.15, 1.05)
    for z in (1.75, -1.75):
        for x in (1.0, -1.0):
            wheel(m, z, x, 0.6, 0.6, 0.36, False)
    return m


def forklift():
    m = Mesh()
    box(m, "paint", -1.25, 0.55, 0.3, 1.05, 0.55, r=0.06)                         # body and counterweight
    box(m, "plastic", -0.75, 0.2, 1.05, 1.2, 0.4)                                  # seat
    for cx in (0.5, -0.5):                                                         # the overhead guard
        box(m, "gunmetal", -1.1, -1.02, 1.05, 2.1, 0.03, cx=cx, r=0.01)
        box(m, "gunmetal", 0.42, 0.5, 1.05, 2.1, 0.03, cx=cx, r=0.01)
    box(m, "gunmetal", -1.12, 0.52, 2.08, 2.14, 0.53, r=0.01)
    for cx in (0.32, -0.32):                                                       # mast rails and forks
        box(m, "gunmetal", 0.62, 0.72, 0.1, 2.5, 0.04, cx=cx, r=0.01)
        box(m, "gunmetal", 0.72, 1.85, 0.12, 0.17, 0.06, cx=cx, r=0.01)
        box(m, "gunmetal", 0.72, 0.78, 0.12, 0.7, 0.06, cx=cx, r=0.01)
    box(m, "gunmetal", 0.6, 0.7, 2.44, 2.52, 0.38, r=0.01)
    box(m, "gunmetal", 0.6, 0.7, 0.6, 0.68, 0.38, r=0.01)
    for z, r in ((0.3, 0.3), (-0.95, 0.24)):
        for x in (0.52, -0.52):
            wheel(m, z, x, r, r, 0.2, False)
    return m


m3 = dict(base, bar_r={"color": (0.8, 0.08, 0.06), "metal": 0.1, "rough": 0.25}, bar_b={"color": (0.08, 0.2, 0.85), "metal": 0.1, "rough": 0.25},
          canvas={"color": (0.3, 0.33, 0.24), "metal": 0.0, "rough": 0.95})
white = tex_paint((0.86, 0.86, 0.84), 0.4)
olive = tex_paint((0.27, 0.3, 0.2), 0.5)
emit("police", police(), dict(m3, paint={"color": (1, 1, 1), "metal": 0.4, "rough": 0.45, "tex": "paint"}, stripe={"color": (0.08, 0.18, 0.5), "metal": 0.2, "rough": 0.5}), {"paint": white})
emit("ambulance", ambulance(), dict(m3, paint={"color": (1, 1, 1), "metal": 0.3, "rough": 0.5, "tex": "paint"}, stripe={"color": (0.7, 0.08, 0.06), "metal": 0.1, "rough": 0.5}), {"paint": white})
emit("van_burnt", van(True), dict(base), {"burnt": burnt_img})
emit("truck_mil", truck_mil(), dict(m3, paint={"color": (1, 1, 1), "metal": 0.2, "rough": 0.7, "tex": "paint"}), {"paint": olive})
emit("apc", apc(), dict(m3, paint={"color": (1, 1, 1), "metal": 0.25, "rough": 0.65, "tex": "paint"}), {"paint": olive})
emit("forklift", forklift(), dict(m3, paint={"color": (1, 1, 1), "metal": 0.3, "rough": 0.55, "tex": "paint"}), {"paint": tex_paint((0.85, 0.6, 0.1), 0.45)})
