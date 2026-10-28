#!/usr/bin/env python3
"""The "hot spot" of a pin: a very light gray square (RGB 208,208,208, 2 design units across) on the connection end of every pin of a placed symbol, on the screen and
not in an exported picture or printout (TinyCAD's CDrawPin::Paint). Oracle: the library file read with sqlite3 is not needed; the pin positions come from the
program's own list of placed pins (design units) and the zoom it reports, and the squares are found by colour in the picture it saves: the squares must be one per
pin and their distances from each other must be the pins' distances times the zoom. Not in an exported picture: `run_export.py` checks the exported pictures against its own statement of what is drawn.
Needs the built program, xvfb and the example libraries (TC_EXAMPLES)."""
import os, re, shutil, subprocess, sys, tempfile
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
LIB = os.path.join(EX, "libraries", "gen_passive.TCLib")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not os.path.exists(LIB):
    print("Hot spot checks skipped: need xvfb-run, the built program and the example libraries"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:500])
S = """newdoc A4
lib %s
libplace 0 90 70
libplace 3 105 70
libplace 5 120 70
selclear
zoom 4
centeron 105 74
zoomfactor
pinsof
shot %s/a.bmp
selectclass TDrawMethod
shot %s/sel.bmp
selclear
""" % (LIB, tmp, tmp)
open(os.path.join(tmp, "s.txt"), "w").write(S)
h = os.path.join(tmp, "h"); os.makedirs(h)
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s.txt")], capture_output=True, text=True, timeout=250,
                   env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
o = r.stdout.split("\n")
zoom = float([l for l in o if l.startswith("ZOOMFACTOR")][0].split()[1])
pins = [(float(l.split()[3]), float(l.split()[4])) for l in o if l.startswith("PIN ")]
def squares(path):
    a = np.array(Image.open(path).convert("RGB")).astype(int)
    m = (abs(a[:, :, 0] - 208) < 2) & (abs(a[:, :, 1] - 208) < 2) & (abs(a[:, :, 2] - 208) < 2)
    seen = np.zeros(m.shape, bool); res = []
    for y, x in zip(*np.nonzero(m)):
        if seen[y, x]: continue
        st = [(y, x)]; seen[y, x] = True; pts = []
        while st:
            p, q = st.pop(); pts.append((p, q))
            for dp, dq in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                c, d = p + dp, q + dq
                if 0 <= c < m.shape[0] and 0 <= d < m.shape[1] and m[c, d] and not seen[c, d]: seen[c, d] = True; st.append((c, d))
        ys = [p for p, q in pts]; xs = [q for p, q in pts]
        if len(pts) >= 8 and max(ys) - min(ys) >= 3 and max(xs) - min(xs) >= 3: res.append(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2))
    return res
check("pins were listed", len(pins) >= 6, pins)
for name in ("a", "sel"):
    sq = squares(os.path.join(tmp, name + ".bmp"))
    check("%s: one hot spot square for each of the %d pins" % (name, len(pins)), len(sq) == len(pins), (len(sq), len(pins)))
    if len(sq) == len(pins):
        # the first pin's square and the pins' design positions give the others (pixel = units * zoom), whatever the placement of the sheet
        srt = sorted(sq)
        want = sorted((px * zoom, py * zoom) for px, py in pins)
        dx = srt[0][0] - want[0][0]; dy = srt[0][1] - want[0][1]
        bad = [(s, w) for s, w in zip(srt, want) if abs(s[0] - dx - w[0]) > 1.5 or abs(s[1] - dy - w[1]) > 1.5]
        check("%s: the squares are on the pins (distances between them are the pins' distances times the zoom %.3g)" % (name, zoom), not bad, bad[:3])
check("a chosen symbol shows the same light gray squares (not the selection colour)", len(squares(os.path.join(tmp, "sel.bmp"))) == len(pins))
print("Hot spot checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
