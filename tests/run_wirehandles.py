#!/usr/bin/env python3
"""The small light gray squares TinyCAD shows at both ends of a chosen wire (bus, line), on the real program under Xvfb. Oracle: the pictures the program saves, read
with PIL / numpy: the squares (gray 128 outline, gray 192 inside) are found by colour and must be centred on the two ends of the orange (chosen) wire, whose ends
are found from the orange pixels. Not chosen: no squares. Two wires chosen: four. A chosen polygon or rectangle has none of these squares."""
import os, shutil, subprocess, sys, tempfile
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Wire handle checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:400])
S = """newdoc A4
tool wire
mouse down 40 60
mouse down 100 60
mouse dbl 100 60
tool wire
mouse down 40 100
mouse down 40 140
mouse dbl 40 140
tool rect
mouse down 120 100
mouse down 160 140
tool select
selclear
zoom 2
shot %(t)s/none.bmp
selidx 0
shot %(t)s/one.bmp
selidx 0 1
shot %(t)s/two.bmp
selidx 2
shot %(t)s/rect.bmp
""" % {"t": tmp}
open(os.path.join(tmp, "s.txt"), "w").write(S)
h = os.path.join(tmp, "h"); os.makedirs(h)
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s.txt")], capture_output=True, text=True, timeout=250,
                   env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
def load(n): return np.array(Image.open(os.path.join(tmp, n + ".bmp")).convert("RGB")).astype(int)
def eq(a, c): return (abs(a[:, :, 0] - c[0]) < 3) & (abs(a[:, :, 1] - c[1]) < 3) & (abs(a[:, :, 2] - c[2]) < 3)
def clusters(mask):
    seen = np.zeros(mask.shape, bool); out = []
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]: continue
        st = [(y, x)]; seen[y, x] = True; pts = []
        while st:
            a, b = st.pop(); pts.append((a, b))
            for da, db in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                c, d = a + da, b + db
                if 0 <= c < mask.shape[0] and 0 <= d < mask.shape[1] and mask[c, d] and not seen[c, d]: seen[c, d] = True; st.append((c, d))
        out.append(pts)
    return out
def squares(a):
    """centres of the squares: a gray 128 outline around gray 192 (small blocks, so the grid dots and lines do not count)"""
    res = []
    for pts in clusters(eq(a, (128, 128, 128))):
        ys = [p[0] for p in pts]; xs = [p[1] for p in pts]
        if 5 <= max(ys) - min(ys) + 1 <= 14 and max(xs) - min(xs) == max(ys) - min(ys) and len(pts) >= 12:
            cy, cx = (min(ys) + max(ys)) // 2, (min(xs) + max(xs)) // 2
            if eq(a, (192, 192, 192))[cy, cx]: res.append((cx, cy))
    return res
def orange_ends(a, horizontal):
    o = (a[:, :, 0] > 200) & (a[:, :, 1] > 100) & (a[:, :, 1] < 160) & (a[:, :, 2] < 60)
    ys, xs = np.nonzero(o)
    return o, ys, xs
none, one, two, rect = (load(n) for n in ("none", "one", "two", "rect"))
check("a wire that is not chosen has no squares", squares(none) == [], squares(none))
o, ys, xs = orange_ends(one, True)
sq = squares(one)
check("a chosen wire has a square at each end (two squares)", len(sq) == 2, sq)
if len(sq) == 2:
    sq = sorted(sq)
    check("the squares are centred on the two ends of the wire, found from its orange pixels (the square hides the first pixels of the wire)", 0 <= xs.min() - sq[0][0] <= 5 and 0 <= sq[1][0] - xs.max() <= 5 and all(abs(s[1] - ys.mean()) <= 1 for s in sq), (sq, xs.min(), xs.max(), ys.mean()))
check("two chosen wires: four squares", len(squares(two)) == 4, squares(two))
check("a chosen rectangle does not get the wire squares", squares(rect) == [], squares(rect))
print("Wire handle checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
