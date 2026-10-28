#!/usr/bin/env python3
"""The red ring of a wire that sticks to a wire end, pin or wire (TinyCAD's PaintConnectPoint) is HIGHLIGHT_SIZE = 10 design units from the centre, so on the
screen it is 10 * zoom pixels from the centre (at least 4), at every zoom, and it comes with the wire tool before the first click as well. Oracle: the red pixels of
the picture the program saves, and the zoom the program reports; with the cursor far from any wire there is no ring."""
import os, re, shutil, subprocess, sys, tempfile
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Connect ring checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:400])
ZOOMS = [0.5, 1.0, 1.0, 1.25, 1.25]       # factors applied one after the other: the zoom is 0.5, 1.0 ... as reported
s = "newdoc A4\ntool wire\nmouse down 60 40\nmouse down 60 100\nmouse dbl 60 100\ntool wire\n"
for i, z in enumerate(ZOOMS):
    s += "zoom %s\nzoomfactor\nmouse move 62 70\nshot %s/z%d.bmp\nmouse move 120 150\nshot %s/f%d.bmp\n" % (z, tmp, i, tmp, i)
open(os.path.join(tmp, "s.txt"), "w").write(s)
h = os.path.join(tmp, "h"); os.makedirs(h)
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s.txt")], capture_output=True, text=True, timeout=250,
                   env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
zf = [float(l.split()[1]) for l in r.stdout.split("\n") if l.startswith("ZOOMFACTOR")]
def red_box(path):
    a = np.array(Image.open(path).convert("RGB")).astype(int)
    m = (a[:, :, 0] > 200) & (a[:, :, 1] < 60) & (a[:, :, 2] < 60)
    ys, xs = np.nonzero(m)
    return None if len(xs) == 0 else (xs.min(), xs.max(), ys.min(), ys.max())
check("the zoom was reported each time", len(zf) == len(ZOOMS), r.stdout[-300:])
for i, z in enumerate(zf):
    b = red_box(os.path.join(tmp, "z%d.bmp" % i))
    want = max(4, round(10 * z))
    check("zoom %s: the ring is %d pixels from its centre (10 design units), found from its red pixels" % (z, want), b is not None and (b[1] - b[0]) == 2 * want and (b[3] - b[2]) == 2 * want, (b, want))
    check("zoom %s: far from every wire there is no ring" % z, red_box(os.path.join(tmp, "f%d.bmp" % i)) is None)
print("Connect ring checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
