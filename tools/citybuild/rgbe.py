"""Read a Radiance .hdr (RLE RGBE) file into a float32 array."""
import numpy as np
def read_hdr(path):
    f = open(path, 'rb')
    while True:
        l = f.readline()
        if l.strip() == b'':
            break
    dims = f.readline().split()
    h, w = int(dims[1]), int(dims[3])
    data = np.frombuffer(f.read(), dtype=np.uint8)
    out = np.zeros((h, w, 4), dtype=np.uint8)
    p = 0
    for y in range(h):
        assert data[p] == 2 and data[p + 1] == 2
        p += 4
        for c in range(4):
            x = 0
            while x < w:
                n = int(data[p]); p += 1
                if n > 128:
                    n -= 128
                    out[y, x:x + n, c] = data[p]; p += 1
                else:
                    out[y, x:x + n, c] = data[p:p + n]; p += n
                x += n
    e = out[..., 3].astype(np.float32)
    s = np.where(e > 0, np.ldexp(1.0, (e - 136).astype(np.int32)), 0).astype(np.float32)
    return out[..., :3].astype(np.float32) * s[..., None]
