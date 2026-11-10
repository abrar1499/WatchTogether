"""Download a Poly Haven (CC0) model (gltf + its textures) or texture set into a folder.
usage: phget.py model <id> <res> <outdir>   |   phget.py tex <id> <res> <outdir>   |   phget.py hdri <id> <res> <outdir>"""
import json, os, sys, urllib.request

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) asset-fetch"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()

kind, aid, res, out = sys.argv[1:5]
files = json.loads(get("https://api.polyhaven.com/files/" + aid))
os.makedirs(out, exist_ok=True)
total = 0
if kind == "model":
    g = files["gltf"][res]["gltf"]
    data = get(g["url"])
    open(os.path.join(out, aid + ".gltf"), "wb").write(data)
    total += len(data)
    for rel, info in g.get("include", {}).items():
        p = os.path.join(out, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        b = get(info["url"])
        open(p, "wb").write(b)
        total += len(b)
elif kind == "tex":
    for m, name in (("Diffuse", "diff"), ("nor_gl", "nor"), ("Rough", "rough"), ("arm", "arm")):
        if m in files and res in files[m]:
            b = get(files[m][res]["jpg"]["url"])
            open(os.path.join(out, "%s_%s.jpg" % (aid, name)), "wb").write(b)
            total += len(b)
elif kind == "hdri":
    f = files["hdri"][res]["hdr"]
    b = get(f["url"])
    open(os.path.join(out, aid + ".hdr"), "wb").write(b)
    total += len(b)
print(aid, total // 1024, "KB")
