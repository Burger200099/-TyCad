#!/usr/bin/env python3
"""Ruler units: the rulers round the drawing area have units of their own (right click a ruler, or Options > Sheets > Ruler Units), so the grid can be millimetres and the rulers
inches. Oracle: the pixel of a reading is (reading * 25.4 (inches) * 5 units per mm - scroll) * zoom, written again here, for the marks of the rulers (RULERTICK lines), and the
Options values read back from the program (OPTIONSINFO) for the sheet's own units. Cases: nothing chosen = the rulers follow the sheet; the ruler menu ticks the units shown and
both rulers have it; choosing inches on a millimetre sheet changes the marks but not the grid units; choosing millimetres on an inch sheet; the Options radio buttons; the choice is kept
for the next run; a choice from Options that leaves the radio buttons alone does not freeze the rulers; hidden rulers cannot be clicked."""
import os, re, shutil, subprocess, sys, tempfile, math
import xml.etree.ElementTree as ET
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("View ruler checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:420])
def run(script, home=None):
    h = os.path.join(tmp, "home_" + home) if home else tempfile.mkdtemp(dir=tmp)
    os.makedirs(h, exist_ok=True)
    path = os.path.join(tmp, "s.txt"); open(path, "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=150,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
def info(o, nth=0):
    l = [x for x in o if x.startswith("RULERINFO")][nth]
    d = dict(re.findall(r"(\w+)=([^ ]+)", l))
    for k in ("top", "left", "view"): d[k] = tuple(int(v) for v in d[k].split(","))
    return d
def ticks(o, nth=0):
    """the RULERTICK lines that follow the nth RULERINFO: ([h...], [v...]) as (pos, value, major)"""
    idx = [i for i, x in enumerate(o) if x.startswith("RULERINFO")][nth]
    h, v = [], []
    for x in o[idx + 1:]:
        if not x.startswith("RULERTICK"): break
        _, ax, p, val, m = x.split()
        (h if ax == "h" else v).append((int(p), float(val), m == "1"))
    return h, v
def expect_pos(val, d, axis, edge_mm, inch):
    zoom = float(d["zoom"]); org = float(d["ox"] if axis == "h" else d["oy"])
    mm = val * (25.4 if inch else 1.0)
    return round((mm * 5 + edge_mm * 5 - org) * zoom)
def steps_ok(tk, inch):
    maj = [t for t in tk if t[2]]
    gaps = [b[0] - a[0] for a, b in zip(maj, maj[1:])]
    vg = [round(b[1] - a[1], 6) for a, b in zip(maj, maj[1:])]
    return gaps, vg


def st(o): return [x for x in o if x.startswith("RULERUNITS")]
def okpos(h, d, inch, edge=0): return len(h) > 5 and all(p == expect_pos(val, d, "h", edge, inch) for p, val, m in h)
o = run('newdoc "ISO A4" landscape\nrulerunits status\nrulerinfo\n', home="a")
d = info(o); h, v = ticks(o)
check("nothing chosen: saved -1, millimetres ticked, both rulers have the menu", st(o) == ["RULERUNITS saved=-1 mm=1 in=0 topmenu=1 leftmenu=1"], st(o))
check("nothing chosen on a millimetre sheet: the marks are millimetres", okpos(h, d, False), (d, h[:3]))
o = run('newdoc "ISO A4" landscape\nrulerunits in\nrulerinfo\noptionsinfo\n', home="a")
d = info(o); h, v = ticks(o)
check("Inches chosen: saved 1, inches ticked", st(o) == ["RULERUNITS saved=1 mm=0 in=1 topmenu=1 leftmenu=1"], st(o))
check("the marks of both rulers are inches while the sheet is in millimetres", okpos(h, d, True) and len(v) > 5 and all(p == expect_pos(val, d, "v", 0, True) for p, val, m in v), (d, h[:3], v[:3]))
oi = [x for x in o if x.startswith("OPTIONSINFO")]
check("the sheet's own units (the grid, the position bar) are still millimetres", oi and "units=0" in oi[0].replace(" units=", " units="), oi)
o = run('newdoc "ISO A4" landscape\nrulerunits status\nrulerinfo\n', home="a")
d = info(o); h, v = ticks(o)
check("kept for the next run: the next run starts with inches", st(o) == ["RULERUNITS saved=1 mm=0 in=1 topmenu=1 leftmenu=1"] and okpos(h, d, True), st(o))
o = run('newdoc "ISO A4" landscape\noptions units=in\nrulerunits mm\nrulerinfo\n', home="b")
d = info(o); h, v = ticks(o)
check("an inch sheet with the rulers set to millimetres: millimetre marks, millimetres ticked", st(o) == ["RULERUNITS saved=0 mm=1 in=0 topmenu=1 leftmenu=1"] and okpos(h, d, False), (st(o), d, h[:3]))
o = run('newdoc "ISO A4" landscape\noptions rulerunits=in\nrulerunits status\nrulerinfo\n', home="c")
d = info(o); h, v = ticks(o)
check("Options > Sheets > Ruler Units = inches: the same as choosing it on the ruler", st(o) == ["RULERUNITS saved=1 mm=0 in=1 topmenu=1 leftmenu=1"] and okpos(h, d, True), (st(o), d))
o = run('newdoc "ISO A4" landscape\noptions grid=3\nrulerunits status\noptions units=in\nrulerunits status\nrulerinfo\n', home="d")
d = info(o); h, v = ticks(o)
check("Options left alone on the ruler setting does not freeze it: still -1, and the rulers follow the sheet to inches", st(o)[0].startswith("RULERUNITS saved=-1") and st(o)[1].startswith("RULERUNITS saved=-1 mm=0 in=1") and okpos(h, d, True), (st(o), d))
o = run('newdoc "ISO A4" landscape\nviewrulers 0\nrulerunits status\n', home="e")
vr = st(o)
o2 = run('newdoc "ISO A4" landscape\nviewrulers 0\n', home="e")
check("with Show Rulers off the rulers are hidden (so their menu cannot be reached)", any("top=0 left=0" in x for x in o2 if x.startswith("VIEWRULERS")), o2[-3:])
print("%d checks, %d failed" % (checks, len(fails))); sys.exit(1 if fails else 0)
