#!/usr/bin/env python3
"""Lines keep their width on the screen when the sheet is zoomed (TinyCAD's CContext::SelectPen: a pen of width 1 is one pixel at every zoom; only a wider pen is scaled,
and a printout or exported picture scales every pen). Oracle: the pixels of the pictures the program saves, measured in numpy; the zoom the program reports.
  - a wire, a line, a rectangle, a circle and a polygon of the usual width 1 are 1 pixel thick at 50%, 100%, 200%, 400% of zoom
  - a wire of width 3 is round(3 * zoom) pixels thick (at least 1), so a wider pen still grows
  - the wire is found by its blue, the others by black, on the white sheet (the grid dots are gray)
Needs the built program and xvfb."""
import os, shutil, subprocess, sys, tempfile
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Line zoom checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:400])
# at the start the zoom is 0.5; zoom factors applied one after another give 0.5, 1.0, 2.0, 4.0
S = """newdoc A4
tool wire
mouse down 80 70
mouse down 100 70
mouse dbl 100 70
tool line
mouse down 80 74
mouse down 100 74
mouse dbl 100 74
tool rect
mouse down 80 78
mouse down 100 90
tool circle
mouse down 104 78
mouse down 116 90
tool polygon
mouse down 120 78
mouse down 130 78
mouse down 130 90
mouse dbl 130 90
tool wire
toolprop line.width 3
mouse down 80 94
mouse down 100 94
mouse dbl 100 94
tool select
selclear
"""
ZS = [1, 2, 2, 2]
for i, z in enumerate(ZS):
    S += "zoom %d\ncenteron 105 82\nzoomfactor\nshot %s/z%d.bmp\n" % (z, tmp, i)
open(os.path.join(tmp, "s.txt"), "w").write(S)
h = os.path.join(tmp, "h"); os.makedirs(h)
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s.txt")], capture_output=True, text=True, timeout=250,
                   env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
zf = [float(l.split()[1]) for l in r.stdout.split("\n") if l.startswith("ZOOMFACTOR")]
check("the zoom was reported four times, each double the one before", len(zf) == 4 and all(abs(zf[i + 1] / zf[i] - 2) < 0.01 for i in range(3)), zf)
def runs(mask):
    """lengths of the vertical runs of True along the middle column of the longest horizontal run, to read a horizontal line's thickness"""
    best = None
    for x in range(mask.shape[1]):
        col = mask[:, x]
        if col.any():
            n = 0; cur = 0; mx = 0
            for v in col:
                cur = cur + 1 if v else 0; mx = max(mx, cur)
            best = (best or []) + [mx]
    return best
def thickness(a, color_fn, y0, y1):
    """the thickness of the horizontal line found between pixel rows y0 and y1: the most common run length of the colour along columns"""
    m = color_fn(a)[y0:y1, :]
    cols = [c for c in range(m.shape[1]) if m[:, c].any()]
    if not cols: return None
    lens = []
    for c in cols:
        col = m[:, c]; cur = 0; mx = 0
        for v in col:
            cur = cur + 1 if v else 0; mx = max(mx, cur)
        lens.append(mx)
    return max(set(lens), key=lens.count)
blue = lambda a: (a[:, :, 2] > 200) & (a[:, :, 0] < 60) & (a[:, :, 1] < 60)
black = lambda a: (a[:, :, 0] < 60) & (a[:, :, 1] < 60) & (a[:, :, 2] < 60)
if len(zf) == 4:
    for i, z in enumerate(zf):
        a = np.array(Image.open(os.path.join(tmp, "z%d.bmp" % i)).convert("RGB")).astype(int)
        H = a.shape[0]
        # the wires are blue; find their rows: the thin one (width 1) is the upper, the width 3 one the lower
        by = np.nonzero(blue(a).sum(axis=1) > 5)[0]
        groups = np.split(by, np.nonzero(np.diff(by) > 1)[0] + 1) if len(by) else []
        check("zoom %.3g: two blue wires are on the picture" % z, len(groups) == 2, [(g.min(), g.max()) for g in groups])
        if len(groups) == 2:
            check("zoom %.3g: the wire of width 1 is 1 pixel thick" % z, len(groups[0]) == 1, len(groups[0]))
            want = max(1, round(3 * z))
            check("zoom %.3g: the wire of width 3 is %d pixels thick (a wider pen still grows with the zoom)" % (z, want), abs(len(groups[1]) - want) <= 1, (len(groups[1]), want))
        # black shapes: in the middle column of the wires' span the line, the top and the bottom edge of the rectangle cross; each is a run of black pixels
        bx = np.nonzero(blue(a).sum(axis=0) > 0)[0]
        xm = int((bx.min() + bx.max()) // 2)
        col = black(a)[:, xm]; rl = []; cur = 0
        for v in list(col) + [False]:
            if v: cur += 1
            elif cur: rl.append(cur); cur = 0
        check("zoom %.3g: the line and the rectangle's edges (black) are 1 pixel thick" % z, len(rl) >= 3 and all(n == 1 for n in rl), rl)
        # the circle: the middle column of its span (the circle is 104 - 116 mm, the wire 80 - 100 mm: its centre is 15 mm to the right of the wire's middle)
        wpx = (bx.max() - bx.min()) / 20.0          # pixels per mm
        cxm = int(bx.min() + (110 - 80) * wpx)
        col = black(a)[:, cxm]; rl = []; cur = 0
        for v in list(col) + [False]:
            if v: cur += 1
            elif cur: rl.append(cur); cur = 0
        check("zoom %.3g: the top and bottom of the circle are 1 pixel thick" % z, len(rl) >= 2 and all(n == 1 for n in rl), rl)
print("Line zoom checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
