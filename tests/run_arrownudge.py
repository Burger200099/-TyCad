#!/usr/bin/env python3
"""Arrow keys move the chosen objects: one grid step with snap to grid on, one screen pixel (1 / zoom design units, 5 per mm) with it off. The real program under Xvfb.
Oracles: the positions are read from the saved design file (XML) and the expected steps are plain arithmetic - the grid spacing set with gridmm (2.5 mm; the file is in mm) and 1 / (5 x the zoom factor the program reports) mm.
  - snap on: left, right, up, down move the group by exactly the grid spacing in that direction; several objects move together
  - snap off: the same keys move it by 1 / zoom
  - nothing chosen: nothing moves (and no undo step); one undo brings the old place back
Needs the built program and xvfb."""
import os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Arrow key checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:600])
k = [0]
def run(lines):
    k[0] += 1; h = os.path.join(tmp, "h%d" % k[0]); os.makedirs(h)
    f = os.path.join(tmp, "s%d.txt" % k[0]); open(f, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
GRID = 2.5       # mm: the design file is in millimetres (the program draws 5 design units to the mm); set with gridmm below
SRC = os.path.join(tmp, "a.dsn")
open(SRC, "w").write('<?xml version="1.0"?>\n<TinyCADSheets><TinyCAD><NAME>a</NAME><DETAILS><Size width="1485" height="1050"/><GRID spacing="250" snap="1"/></DETAILS>'
                     '<WIRE a="100,100" b="300,100"/><WIRE a="100,500" b="300,500"/></TinyCAD></TinyCADSheets>\n')
def pts(path):
    r = ET.parse(path).getroot(); res = []
    for e in r.iter("WIRE"):
        res.append(([float(x) for x in e.get("a").split(",")], [float(x) for x in e.get("b").split(",")]))
    return res
def zoom(o):
    for l in o:
        if l.startswith("ZOOMFACTOR"): return float(l.split()[1])
def go(snap, keys, select=True):
    out = os.path.join(tmp, "o%d.dsn" % k[0])
    cmds = ["open " + SRC, "gridmm 2.5", "snap " + snap, "zoomfactor"] + (["selectall"] if select else []) + ["arrowkey " + x for x in keys] + ["save " + out]
    o = run(cmds)
    return o, (pts(out) if os.path.exists(out) else None)
base = pts(SRC) if False else [([100.0, 100.0], [300.0, 100.0]), ([100.0, 500.0], [300.0, 500.0])]
def shifted(dx, dy): return [([a[0] + dx, a[1] + dy], [b[0] + dx, b[1] + dy]) for a, b in base]
def near(p, q): return p is not None and all(abs(x[0] - y[0]) < 1e-3 and abs(x[1] - y[1]) < 1e-3 and abs(x[2] - y[2]) < 1e-3 and abs(x[3] - y[3]) < 1e-3 for x, y in zip([a + b for a, b in p], [a + b for a, b in q]))
for key, dx, dy in (("left", -1, 0), ("right", 1, 0), ("up", 0, -1), ("down", 0, 1)):
    o, p = go("on", [key])
    check("snap on, %s: both wires move one grid step" % key, near(p, shifted(dx * GRID, dy * GRID)) if p else False, p)
o, p = go("on", ["right", "right", "down", "left"])
check("snap on: right, right, down, left", near(p, shifted(GRID, GRID)) if p else False, p)
for key, dx, dy in (("left", -1, 0), ("right", 1, 0), ("up", 0, -1), ("down", 0, 1)):
    o, p = go("off", [key] * 3)
    z = zoom(o)
    check("snap off, %s x3: three screen pixels (zoom %s)" % (key, z), z and near(p, shifted(dx * 3 / (5 * z), dy * 3 / (5 * z))), (z, p))
o, p = go("on", ["right"], select=False)
check("nothing chosen: nothing moves", near(p, shifted(0, 0)) if p else False, p)
out = os.path.join(tmp, "u.dsn")
run(["open " + SRC, "gridmm 2.5", "selectall", "arrowkey left", "undo", "save " + out])
check("one undo puts it back", near(pts(out), shifted(0, 0)) if os.path.exists(out) else False)
print("arrow key checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
