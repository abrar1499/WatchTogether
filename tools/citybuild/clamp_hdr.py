"""Clamp a Radiance .hdr sky to a peak value (the sun's disc is far brighter than a phone's sky buffer holds; the
scene's own sun lamp stands for it). usage: clamp_hdr.py in.hdr out.hdr peak"""
import sys, os
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rgbe import read_hdr
a = np.minimum(read_hdr(sys.argv[1]), float(sys.argv[3]))
m = a.max(axis=2)
e = np.where(m > 1e-32, np.floor(np.log2(np.maximum(m, 1e-32))) + 1, 0)
sc = np.where(m > 1e-32, np.ldexp(1.0, (8 - e).astype(np.int32)), 0)
rgb = np.clip(a * sc[..., None], 0, 255).astype(np.uint8)
out = np.dstack([rgb, np.where(m > 1e-32, e + 128, 0).astype(np.uint8)])
h, w = a.shape[:2]
with open(sys.argv[2], 'wb') as f:
    f.write(b'#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n' % (h, w))
    f.write(out.tobytes())
