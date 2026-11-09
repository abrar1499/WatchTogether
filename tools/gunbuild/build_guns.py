"""Builds ak.glb, m4.glb, pistol.glb. Gun space: metres, +Z along the barrel, +Y up, +X the shooter's left.
Origin at the top of the pistol grip (on its centre line); the grip rakes back along GRIP_DOWN."""
import io, math, sys
import numpy as np
from PIL import Image
from meshlib import Mesh, V, nrm, rounded, AX_X, AX_Y, at, write_glb

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
GA = nrm(V(-0.34, -0.94))      # (z, y) down the grip
GP = V(0.94, -0.34)            # (z, y) square to it, forward
RIGHT = np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]], float)   # lathe frame: local z -> the gun's right (-x)

# ---------------- textures ----------------
rng = np.random.default_rng(7)
def noise(W, H, gx, gy):
    g = rng.random((gy, gx))
    g = np.pad(g, ((1, 2), (1, 2)), mode="wrap")
    im = Image.fromarray((g * 255).astype(np.uint8)).resize((W * (gx + 3) // gx, H * (gy + 3) // gy), Image.BICUBIC)
    a = np.asarray(im, float) / 255.0
    ox, oy = W // gx, H // gy
    return a[oy:oy + H, ox:ox + W]
def png(a):
    b = io.BytesIO()
    Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8)).save(b, "PNG")
    return b.getvalue()
def wood_tex():
    W, H = 512, 128
    warp = noise(W, H, 4, 2) * 1.6 + noise(W, H, 16, 8) * 0.35
    v = np.linspace(0, 1, H, endpoint=False)[:, None]
    ring = 0.5 + 0.5 * np.sin(2 * math.pi * (v * 14 + warp))
    ring = ring ** 3
    streak = noise(W, H, 256, 96) * 0.3 + noise(W, H, 48, 24) * 0.25
    t = np.clip(ring * 0.32 + streak * 0.8, 0, 1)[..., None]
    dark = np.array([62, 25, 11]) / 255.0
    light = np.array([118, 52, 22]) / 255.0
    col = dark * t + light * (1 - t)
    col *= (0.9 + noise(W, H, 8, 4) * 0.2)[..., None]
    return png(col)
def grey_tex(base, amp, fine):
    W = H = 256
    a = base + (noise(W, H, 8, 8) - 0.5) * amp + (noise(W, H, 128, 128) - 0.5) * fine
    return png(np.repeat(np.clip(a, 0, 1)[..., None], 3, axis=2))
IMAGES = {"wood": wood_tex(), "metal": grey_tex(0.9, 0.14, 0.08), "poly": grey_tex(0.88, 0.06, 0.22)}
MATS = {
    "blued": {"color": (0.075, 0.075, 0.082), "metal": 0.55, "rough": 0.4, "tex": "metal"},
    "steel": {"color": (0.16, 0.16, 0.17), "metal": 0.65, "rough": 0.34, "tex": "metal"},
    "dark": {"color": (0.015, 0.015, 0.015), "metal": 0.0, "rough": 0.8},
    "wood": {"color": (1.0, 1.0, 1.0), "metal": 0.0, "rough": 0.42, "tex": "wood"},
    "alu": {"color": (0.04, 0.04, 0.043), "metal": 0.35, "rough": 0.52, "tex": "metal"},
    "poly": {"color": (0.028, 0.028, 0.028), "metal": 0.0, "rough": 0.74, "tex": "poly"},
    "rubber": {"color": (0.025, 0.025, 0.025), "metal": 0.0, "rough": 0.92, "tex": "poly"},
    "red": {"color": (1.0, 0.08, 0.05), "metal": 0.0, "rough": 1.0, "unlit": True, "emissive": (1.0, 0.1, 0.05)},
}

# ---------------- shared shapes ----------------
def grip(m, mat, length, depth_top, depth_bot, half, bumps=(), hump=0.0, top=-0.012, bevel=0.006):
    """Pistol grip round the GA axis through the origin."""
    ss = np.linspace(top, length, 9)
    front, back = [], []
    for s in ss:
        k = (s - top) / (length - top)
        d = depth_top * (1 - k) + depth_bot * k
        f = d / 2
        for (bs, bh) in bumps:
            f += bh * math.exp(-((s - bs) / 0.008) ** 2)
        front.append(GA * s + GP * f)
        b = d / 2 + (hump * max(0.0, 1 - (s - top) / 0.03))
        back.append(GA * s - GP * b)
    poly = back[::-1] + front           # top-back ... wait: build bottom-back -> top-back -> top-front -> bottom-front
    poly = [back[-1]] + back[-2::-1] + front
    r = [0.0] * len(poly)
    r[0] = 0.008; r[-1] = 0.008
    m.extrude(mat, rounded(poly, r, 3), half, bevel=bevel, steps=3)

def u_guard(m, mat, z0, z1, depth, thick, half, y0=0.0):
    outer = [V(z0, y0), V(z0 + 0.004, y0 - depth), V(z1 - 0.008, y0 - depth), V(z1, y0 - depth + 0.012), V(z1, y0)]
    inner = [V(z1 - thick, y0), V(z1 - thick, y0 - depth + 0.012 + thick * 0.4), V(z1 - 0.008 - thick * 0.3, y0 - depth + thick), V(z0 + 0.004 + thick, y0 - depth + thick), V(z0 + thick, y0)]
    poly = rounded(outer, [0, 0.006, 0.008, 0.006, 0], 3) + rounded(inner, [0, 0.004, 0.006, 0.004, 0], 3)
    m.extrude(mat, poly, half, bevel=0.0015, steps=1)

def trigger(m, mat, z, half=0.003):
    pts = [V(z - 0.004, 0.002), V(z + 0.003, 0.002), V(z + 0.001, -0.008), V(z - 0.002, -0.016), V(z - 0.006, -0.018), V(z - 0.005, -0.012), V(z - 0.003, -0.006)]
    m.extrude(mat, pts, half, bevel=0.001, steps=1)

def curved_mag(m, mat, top, length, depth, th0, th1, half, ribs=(), rib_mat=None, n=14, floor=True):
    c = V(*top)
    front, back, frames = [], [], []
    ds = length / n
    for i in range(n + 1):
        th = th0 + (th1 - th0) * i / n
        d = V(math.sin(th), -math.cos(th))
        p = V(math.cos(th), math.sin(th))
        front.append(c + p * depth / 2)
        back.append(c - p * depth / 2)
        frames.append((c.copy(), d, p))
        c = c + d * ds
    poly = back + front[::-1]
    r = [0.0] * len(poly)
    r[n] = 0.004; r[n + 1] = 0.004
    m.extrude(mat, rounded(poly, r, 2), half, bevel=0.003, steps=2)
    for s in ribs:
        i = int(s * n)
        c0, d, p = frames[i]
        rib = [c0 - p * depth * 0.42 - d * 0.002, c0 + p * depth * 0.42 - d * 0.002, c0 + p * depth * 0.42 + d * 0.002, c0 - p * depth * 0.42 + d * 0.002]
        m.extrude(rib_mat or mat, rib, half + 0.0008, bevel=0.0006, steps=1)
    if floor:
        c0, d, p = frames[-1]
        fl = [c0 - p * (depth / 2 + 0.003) - d * 0.006, c0 + p * (depth / 2 + 0.004) - d * 0.006, c0 + p * (depth / 2 + 0.004) + d * 0.004, c0 - p * (depth / 2 + 0.003) + d * 0.004]
        m.extrude(rib_mat or mat, fl, half + 0.0015, bevel=0.0015, steps=1)

def cyl(m, mat, z0, z1, r, y, x=0.0, seg=18, chamfer=0.0):
    c = min(chamfer, r * 0.5, (z1 - z0) * 0.3)
    m.lathe(mat, [V(z0, 0), V(z0, r - c), V(z0 + c, r), V(z1 - c, r), V(z1, r - c), V(z1, 0)], seg=seg, center=(x, y))

def pin(m, mat, z, y, r, half):
    """Short cylinder across the gun (along x)."""
    m.lathe(mat, [V(-half, 0), V(-half, r), V(half, r), V(half, 0)], seg=10, xf=at(AX_X, (0, y, z)))

def box(m, mat, z0, z1, y0, y1, half, cx=0.0, bevel=0.0015, r=0.0):
    pts = [V(z0, y0), V(z1, y0), V(z1, y1), V(z0, y1)]
    if r > 0:
        pts = rounded(pts, r, 2)
    m.extrude(mat, pts, half, bevel=bevel, steps=1, cx=cx)

# ================= AK-47 =================
def build_ak():
    m = Mesh()
    # receiver and top cover
    box(m, "blued", -0.088, 0.157, 0.002, 0.05, 0.0162, r=0.003, bevel=0.0018)
    m.extrude("blued", rounded([V(-0.09, 0.046), V(0.152, 0.046), V(0.152, 0.06), V(-0.05, 0.067), V(-0.09, 0.062)], [0, 0, 0.003, 0.03, 0.004], 4), 0.0158, bevel=0.007, steps=3)
    # rear trunnion tang and stock socket
    box(m, "blued", -0.1, -0.085, 0.0, 0.048, 0.0175, r=0.002)
    # ejection port (dark) and bolt carrier on the right
    box(m, "dark", 0.03, 0.118, 0.034, 0.049, 0.0012, cx=-0.0158, bevel=0.0004)
    box(m, "steel", 0.05, 0.14, 0.03, 0.038, 0.0015, cx=-0.0172, bevel=0.0005)
    # charging handle, sticking out to the right
    m.lathe("steel", [V(0, 0), V(0, 0.0055), V(0.02, 0.0055), V(0.022, 0.0045), V(0.022, 0)], seg=10, xf=(RIGHT, V(-0.016, 0.034, 0.13)))
    # selector lever (right)
    m.extrude("blued", rounded([V(-0.07, 0.043), V(0.055, 0.037), V(0.06, 0.03), V(-0.02, 0.031), V(-0.07, 0.036)], 0.003, 2), 0.0011, bevel=0.0005, steps=1, cx=-0.0175)
    # rivets
    for (z, y) in ((-0.07, 0.01), (-0.05, 0.01), (0.03, 0.008), (0.14, 0.01), (0.14, 0.035), (-0.075, 0.035)):
        pin(m, "steel", z, y, 0.0022, 0.0172)
    # pistol grip (wood), trigger guard, trigger
    grip(m, "wood", 0.1, 0.034, 0.031, 0.0145, bumps=(), hump=0.0)
    u_guard(m, "blued", 0.012, 0.072, 0.024, 0.0045, 0.0045)
    trigger(m, "blued", 0.034)
    # magazine (steel, curved) with ribs
    curved_mag(m, "blued", (0.098, 0.012), 0.215, 0.056, 0.13, 0.72, 0.0135, ribs=(0.25, 0.45, 0.65, 0.85), rib_mat="steel")
    box(m, "steel", 0.122, 0.132, -0.012, 0.004, 0.006, bevel=0.0008)   # magazine catch
    # stock (wood) and butt plate
    stock = [V(-0.085, 0.045), V(-0.318, 0.036), V(-0.318, -0.099), V(-0.26, -0.078), V(-0.17, -0.042), V(-0.11, -0.012), V(-0.085, 0.002)]
    m.extrude("wood", rounded(stock, [0.004, 0.006, 0.01, 0.02, 0.03, 0.02, 0.004], 4), 0.0195, bevel=0.007, steps=3)
    m.extrude("steel", rounded([V(-0.326, 0.038), V(-0.317, 0.038), V(-0.317, -0.101), V(-0.326, -0.101)], 0.003, 2), 0.0205, bevel=0.004, steps=2)
    # lower handguard (wood) with finger ridge, front ferrule
    lh = [V(0.157, 0.042), V(0.332, 0.042), V(0.332, 0.008), V(0.318, -0.004), V(0.25, -0.006), V(0.19, -0.006), V(0.165, -0.002), V(0.157, 0.006)]
    m.extrude("wood", rounded(lh, [0.002, 0.002, 0.006, 0.01, 0.02, 0.02, 0.008, 0.003], 3), 0.0225, bevel=0.009, steps=3)
    box(m, "blued", 0.332, 0.346, 0.002, 0.046, 0.0205, r=0.002, bevel=0.003)
    # upper handguard over the gas tube (wood), gas tube, gas block
    m.extrude("wood", rounded([V(0.19, 0.046), V(0.336, 0.046), V(0.336, 0.073), V(0.19, 0.073)], 0.004, 2), 0.0145, bevel=0.009, steps=3)
    cyl(m, "blued", 0.33, 0.38, 0.0092, 0.059, chamfer=0.001)
    box(m, "blued", 0.372, 0.398, 0.02, 0.07, 0.0125, r=0.003, bevel=0.003)
    # barrel, cleaning rod, front sight, muzzle brake
    cyl(m, "blued", 0.15, 0.552, 0.0098, 0.031, seg=20)
    cyl(m, "steel", 0.33, 0.512, 0.0026, 0.013, seg=8)
    m.extrude("blued", rounded([V(0.505, 0.016), V(0.537, 0.016), V(0.537, 0.05), V(0.505, 0.05)], 0.003, 2), 0.0115, bevel=0.003, steps=2)
    for sx in (0.0095, -0.0095):
        m.extrude("blued", [V(0.509, 0.048), V(0.533, 0.048), V(0.529, 0.087), V(0.513, 0.087)], 0.0016, bevel=0.0006, steps=1, cx=sx)
    box(m, "blued", 0.518, 0.523, 0.048, 0.083, 0.0015, bevel=0.0005)
    m.lathe("blued", [V(0.548, 0), V(0.548, 0.0118), V(0.552, 0.0128), V(0.578, 0.0128), V(0.586, 0.011), V(0.586, 0.006), V(0.584, 0.0045), V(0.584, 0)], seg=20, center=(0, 0.031))
    # rear sight block and leaf
    m.extrude("blued", rounded([V(0.155, 0.044), V(0.212, 0.044), V(0.212, 0.06), V(0.17, 0.066), V(0.155, 0.064)], 0.003, 2), 0.0132, bevel=0.003, steps=2)
    m.extrude("blued", [V(0.166, 0.064), V(0.205, 0.064), V(0.205, 0.068), V(0.17, 0.0725), V(0.166, 0.0725)], 0.0085, bevel=0.0008, steps=1)
    return m, [("muzzle", (0, 0.031, 0.586))]

# ================= M4A1 =================
def build_m4():
    m = Mesh()
    # upper receiver, forward assist, ejection port, charging handle
    m.extrude("alu", rounded([V(-0.092, 0.029), V(0.15, 0.029), V(0.15, 0.077), V(-0.092, 0.077)], [0.003, 0.004, 0.003, 0.003], 2), 0.0145, bevel=0.003, steps=2)
    cyl(m, "alu", -0.06, -0.02, 0.0075, 0.058, x=-0.017, seg=12, chamfer=0.002)
    box(m, "dark", -0.01, 0.07, 0.036, 0.062, 0.001, cx=-0.0146, bevel=0.0003)
    box(m, "alu", -0.006, 0.066, 0.034, 0.064, 0.0008, cx=-0.0158, bevel=0.0003)
    m.extrude("alu", rounded([V(-0.11, 0.069), V(-0.092, 0.069), V(-0.092, 0.077), V(-0.11, 0.077)], 0.002, 1), 0.019, bevel=0.002, steps=1)
    # picatinny rail on top
    box(m, "alu", -0.088, 0.148, 0.076, 0.081, 0.0105, bevel=0.0008)
    z = -0.084
    while z < 0.144:
        box(m, "alu", z, z + 0.0048, 0.08, 0.0858, 0.0105, bevel=0.0007)
        z += 0.01
    # lower receiver with magazine well
    low = [V(-0.082, 0.031), V(0.145, 0.031), V(0.145, 0.006), V(0.134, -0.036), V(0.074, -0.036), V(0.07, -0.004), V(0.03, 0.0), V(-0.045, 0.0), V(-0.082, 0.012)]
    m.extrude("alu", rounded(low, [0.003, 0.003, 0.006, 0.003, 0.003, 0.004, 0.004, 0.006, 0.004], 2), 0.0155, bevel=0.0025, steps=2)
    for (zz, yy) in ((-0.07, 0.022), (0.138, 0.022)):
        pin(m, "steel", zz, yy, 0.0028, 0.0165)
    pin(m, "steel", 0.06, 0.012, 0.0045, 0.0165)    # mag release / bolt catch
    m.extrude("alu", rounded([V(-0.03, 0.016), V(-0.005, 0.02), V(-0.005, 0.012), V(-0.03, 0.01)], 0.002, 1), 0.0012, bevel=0.0004, steps=1, cx=0.0165)   # selector
    # grip (polymer, finger grooves, beavertail), trigger guard, trigger
    grip(m, "poly", 0.102, 0.036, 0.033, 0.0152, bumps=((0.032, 0.0022), (0.058, 0.0022), (0.082, 0.002)), hump=0.006)
    u_guard(m, "alu", 0.012, 0.07, 0.024, 0.0042, 0.0042)
    trigger(m, "steel", 0.033)
    # magazine (aluminium, slight curve)
    curved_mag(m, "alu", (0.104, 0.0), 0.19, 0.058, 0.04, 0.26, 0.0118, ribs=(0.35, 0.7), rib_mat="poly")
    # buffer tube, castle nut, stock, butt pad
    cyl(m, "alu", -0.27, -0.09, 0.0165, 0.053, seg=18, chamfer=0.002)
    cyl(m, "alu", -0.102, -0.09, 0.019, 0.053, seg=12)
    stk = [V(-0.18, 0.074), V(-0.31, 0.078), V(-0.31, -0.058), V(-0.292, -0.058), V(-0.205, 0.018), V(-0.18, 0.024)]
    m.extrude("poly", rounded(stk, [0.008, 0.006, 0.01, 0.006, 0.02, 0.008], 3), 0.021, bevel=0.007, steps=3)
    m.extrude("rubber", rounded([V(-0.322, 0.082), V(-0.308, 0.082), V(-0.308, -0.062), V(-0.322, -0.062)], 0.005, 2), 0.022, bevel=0.006, steps=2)
    # delta ring, ribbed handguard, front cap
    cyl(m, "alu", 0.147, 0.162, 0.031, 0.051, seg=20, chamfer=0.003)
    prof = [V(0.16, 0), V(0.16, 0.0262)]
    zz = 0.168
    while zz < 0.3:
        prof += [V(zz, 0.0262), V(zz + 0.002, 0.0272), V(zz + 0.008, 0.0272), V(zz + 0.01, 0.0262)]
        zz += 0.0125
    prof += [V(0.302, 0.0262), V(0.302, 0)]
    m.lathe("poly", prof, seg=22, center=(0, 0.051), smooth=50)
    cyl(m, "alu", 0.3, 0.31, 0.022, 0.051, seg=16, chamfer=0.002)
    # barrel, front sight base with post and ears, flash hider
    cyl(m, "blued", 0.15, 0.488, 0.0088, 0.051, seg=18)
    box(m, "alu", 0.312, 0.338, 0.036, 0.066, 0.0122, r=0.003, bevel=0.003)
    m.extrude("alu", [V(0.313, 0.064), V(0.337, 0.064), V(0.33, 0.112), V(0.32, 0.112)], 0.011, bevel=0.002, steps=1, caps=True)
    for sx in (0.0088, -0.0088):
        m.extrude("alu", [V(0.317, 0.11), V(0.333, 0.11), V(0.331, 0.122), V(0.319, 0.122)], 0.0022, bevel=0.0006, steps=1, cx=sx)
    box(m, "alu", 0.323, 0.327, 0.11, 0.121, 0.0016, bevel=0.0005)
    m.lathe("blued", [V(0.486, 0), V(0.486, 0.0105), V(0.49, 0.0112), V(0.528, 0.0112), V(0.532, 0.0098), V(0.532, 0.0062), V(0.528, 0.0055), V(0.528, 0)], seg=18, center=(0, 0.051))
    # red dot sight: mount, hollow tube, turrets, red reticle
    box(m, "alu", 0.004, 0.066, 0.085, 0.104, 0.0125, r=0.002, bevel=0.002)
    m.lathe("alu", [V(-0.008, 0.0165), V(-0.008, 0.0205), V(-0.004, 0.0215), V(0.092, 0.0215), V(0.096, 0.0205), V(0.096, 0.0168), V(-0.008, 0.0165)], seg=24, center=(0, 0.127), smooth=50)
    m.lathe("alu", [V(0, 0), V(0, 0.0065), V(0.012, 0.0065), V(0.012, 0)], seg=12, xf=at(AX_Y, (0, 0.146, 0.045)))
    m.lathe("alu", [V(0, 0), V(0, 0.0065), V(0.012, 0.0065), V(0.012, 0)], seg=12, xf=(RIGHT, V(-0.0205, 0.127, 0.045)))
    m.lathe("red", [V(-0.0012, 0), V(-0.0012, 0.0013), V(0.0012, 0.0013), V(0.0012, 0)], seg=8, center=(0, 0.127), xf=(np.eye(3), V(0, 0, 0.088)))
    # sling loop at the stock
    return m, [("muzzle", (0, 0.051, 0.532))]

# ================= SD-9 pistol with suppressor =================
def build_pistol():
    m = Mesh()
    # slide with rear serrations and ejection port
    m.extrude("blued", rounded([V(-0.036, 0.027), V(0.152, 0.027), V(0.152, 0.058), V(-0.036, 0.058)], [0.003, 0.004, 0.006, 0.004], 2), 0.0124, bevel=0.0035, steps=2)
    for k in range(6):
        z = -0.031 + k * 0.0045
        for sx in (0.0124, -0.0124):
            box(m, "dark", z, z + 0.0016, 0.031, 0.054, 0.0005, cx=sx, bevel=0.0)
    box(m, "dark", 0.03, 0.072, 0.045, 0.0582, 0.0004, cx=-0.0124, bevel=0.0)
    # frame with rail, grip, trigger guard, trigger
    fr = [V(-0.036, 0.028), V(0.142, 0.028), V(0.142, 0.012), V(0.08, 0.009), V(0.076, 0.0), V(0.02, 0.0), V(-0.01, 0.006), V(-0.036, 0.014)]
    m.extrude("poly", rounded(fr, [0.003, 0.003, 0.003, 0.003, 0.004, 0.004, 0.006, 0.004], 2), 0.0136, bevel=0.003, steps=2)
    grip(m, "poly", 0.098, 0.045, 0.042, 0.0148, bumps=((0.035, 0.0015), (0.06, 0.0015)), hump=0.008, top=-0.014, bevel=0.0055)
    u_guard(m, "poly", 0.012, 0.074, 0.026, 0.0048, 0.0052)
    trigger(m, "dark", 0.034)
    # magazine base plate under the grip
    c = GA * 0.1
    bp = [c - GP * 0.024 + GA * -0.004, c + GP * 0.023 + GA * -0.004, c + GP * 0.023 + GA * 0.006, c - GP * 0.024 + GA * 0.006]
    m.extrude("poly", rounded(bp, 0.003, 1), 0.0152, bevel=0.002, steps=1)
    # sights (tall, to clear the suppressor)
    box(m, "dark", -0.033, -0.02, 0.057, 0.071, 0.0045, cx=0.0055, bevel=0.0006)
    box(m, "dark", -0.033, -0.02, 0.057, 0.071, 0.0045, cx=-0.0055, bevel=0.0006)
    box(m, "dark", 0.138, 0.146, 0.057, 0.07, 0.0016, bevel=0.0005)
    # barrel and suppressor
    cyl(m, "steel", 0.148, 0.168, 0.0068, 0.0435, seg=14)
    m.lathe("poly", [V(0.165, 0), V(0.165, 0.0135), V(0.169, 0.0165), V(0.316, 0.0165), V(0.322, 0.0135), V(0.322, 0.004), V(0.32, 0.003), V(0.32, 0)], seg=22, center=(0, 0.0435))
    return m, [("muzzle", (0, 0.0435, 0.322))]

for name, fn in (("ak", build_ak), ("m4", build_m4), ("pistol", build_pistol)):
    m, extra = fn()
    used = {k: MATS[k] for k in m.parts}
    imgs = {k: IMAGES[k] for k in IMAGES if any(MATS[u].get("tex") == k for u in used)}
    tris = write_glb(f"{OUT}/{name}.glb", m, used, imgs, extra)
    print(name, "triangles", tris)
