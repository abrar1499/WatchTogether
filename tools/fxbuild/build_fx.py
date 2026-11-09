"""Muzzle-flash and tracer textures for Dust Signal (additive, white-hot core to orange edge).
Run: python3 build_fx.py ../../godot/assets/fx   (needs numpy, Pillow)"""
import math, os, sys
import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(11)

def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)

def colorize(I, heat=1.0, alpha_gain=1.0):
    orange = np.array([1.0, 0.42, 0.08])
    yellow = np.array([1.0, 0.82, 0.32])
    white = np.array([1.0, 0.98, 0.9])
    H = I * heat
    a = smooth(0.15, 0.6, H)[..., None]
    b = smooth(0.7, 1.0, H)[..., None]
    col = orange + (yellow - orange) * a
    col = col + (white - col) * b
    rgba = np.concatenate([col, np.clip(I * alpha_gain, 0, 1)[..., None]], axis=2)
    return Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")

def noise1d(n, k):
    g = rng.random(k + 3)
    x = np.linspace(0, k, n)
    i = x.astype(int)
    f = x - i
    f = f * f * (3 - 2 * f)
    return g[i] * (1 - f) + g[i + 1] * f

# front view: a star of uneven spikes round a white-hot core
def flash_front(name, spikes):
    N = 256
    y, x = np.mgrid[0:N, 0:N] / (N - 1) * 2 - 1
    r = np.sqrt(x * x + y * y)
    th = np.arctan2(y, x)
    S = np.zeros_like(r)
    for k in range(spikes):
        a = k * 2 * math.pi / spikes + rng.uniform(-0.25, 0.25)
        L = rng.uniform(0.5, 0.97)
        w = rng.uniform(0.13, 0.24)
        d = np.angle(np.exp(1j * (th - a)))
        width = w * (1.1 - r / L).clip(0.04, None)
        S = np.maximum(S, np.exp(-(d / width) ** 2) * smooth(L, L * 0.3, r))
    petals = 0.5 + 0.5 * np.cos(spikes * th + 0.7)
    body = np.exp(-(r / (0.3 + 0.12 * petals)) ** 2) * 0.75
    core = np.exp(-(r / 0.14) ** 2)
    glow = np.exp(-(r / 0.55) ** 2) * 0.25
    I = np.clip(core * 1.1 + S * 0.8 + body + glow, 0, 1) * smooth(1.0, 0.9, r)
    colorize(I).save(os.path.join(OUT, name))

# side view: the flame leaving the muzzle (x = 0) and burning out at x = 1
def flash_side(name):
    W, H = 256, 64
    y, x = np.mgrid[0:H, 0:W]
    u = x / (W - 1)
    v = (y / (H - 1)) * 2 - 1
    jag = noise1d(W, 10)[None, :] * 0.3 + 0.82
    half = (0.22 + 0.78 * np.sin(np.clip(u, 0, 1) ** 0.6 * math.pi * 0.95)) * jag
    body = np.exp(-(v / np.maximum(half * 0.8, 1e-3)) ** 2 * 1.6)
    along = smooth(0.0, 0.05, u) * smooth(1.0, 0.45, u)
    core = np.exp(-(v / 0.22) ** 2) * smooth(0.6, 0.03, u)
    I = np.clip(body * along * 0.62 + core * 0.75, 0, 1)
    colorize(I).save(os.path.join(OUT, name))

# tracer: tail (x = 0) fading in to a bright round head (x = 1)
def tracer(name):
    W, H = 256, 32
    y, x = np.mgrid[0:H, 0:W]
    u = x / (W - 1)
    v = (y / (H - 1)) * 2 - 1
    along = u ** 1.8 * smooth(1.0, 0.94, u)
    core = np.exp(-(v / 0.42) ** 2)
    glow = np.exp(-(v / 0.85) ** 2) * 0.5
    I = np.clip(along * (core + glow) * 1.25, 0, 1)
    head = np.exp(-((u - 0.95) / 0.035) ** 2) * core
    colorize(np.clip(I * 0.8 + head * 0.4, 0, 1), heat=1.0, alpha_gain=1.5).save(os.path.join(OUT, name))

flash_front("flash_front.png", 7)
flash_side("flash_side.png")
tracer("tracer.png")
print("written to", OUT)
