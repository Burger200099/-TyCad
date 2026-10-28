#!/usr/bin/env python3
"""While a pasted block (or a symbol being placed) floats on the sheet: the middle button pans the view, and R / X turn and flip the pasted block (as Ctrl+L, Ctrl+R and
Flip do), on the real program under Xvfb.
Oracle: the sheet origin the program reports before and after a middle drag (it must move by the drag, opposite way); the pasted wires' end points read from the saved
file after the block is dropped: R turns horizontal wires vertical (two R: horizontal again), X mirrors left-right (wires that shared their left end share their right end).
Needs the built program, xvfb and the example libraries (TC_EXAMPLES).
"""
import os, re, shutil, sqlite3, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
LIB = os.path.join(EX, "libraries", "gen_passive.TCLib")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not os.path.exists(LIB):
    print("Paste keys checks skipped: need xvfb-run, the built program and the example libraries"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
lib = os.path.join(tmp, "g.TCLib"); shutil.copy(LIB, lib)
_c = sqlite3.connect(lib); _names = [r[0] for r in _c.execute("select Name from Name where Type=0 order by NameID")]; _c.close()
ROW0 = sorted(_names, key=str.lower).index(_names[0])
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:500])
k = [0]
def run(lines):
    k[0] += 1; f = os.path.join(tmp, "s%d.txt" % k[0]); open(f, "w").write("\n".join(lines) + "\n")
    h = tempfile.mkdtemp(dir=tmp)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
SRC = os.path.join(tmp, "a.dsn")
open(SRC, "w").write("<?xml version='1.0'?>\n<TinyCADSheets><TinyCAD><NAME>a</NAME><DETAILS><Size width='1485' height='1050'/></DETAILS>"
                     "<WIRE a='30,30' b='60,30'/><WIRE a='30,50' b='40,50'/></TinyCAD></TinyCADSheets>\n")
def origins(o): return [tuple(float(x) for x in l.split()[1:3]) for l in o if l.startswith("VIEWORIGIN ")]
def wires(path):
    return [([float(x) for x in e.get("a").split(",")], [float(x) for x in e.get("b").split(",")]) for e in ET.parse(path).getroot().iter("WIRE")] if os.path.exists(path) else None
# --- the middle button pans while a pasted block floats
o = run(["open " + SRC, "tool select", "selectall", "copy", "paste", "vieworigin", "mouse move 100 100", "mouse mdown 100 100", "mouse move 80 90", "mouse mup 80 90",
         "vieworigin", "mouse move 110 110", "vieworigin"])
g = origins(o)
check("three origin readings", len(g) == 3, o[-8:])
if len(g) == 3:
    check("a middle drag during a paste pans the view (the origin moves by the drag: 20 mm left, 10 mm up of the pointer means the sheet origin moves right/down)", abs(g[1][0] - g[0][0] - 20) < 1.5 and abs(g[1][1] - g[0][1] - 10) < 1.5, g)
    check("the block still follows the pointer after it (no error, the origin stays)", g[2] == g[1], g)
pa = [l for l in o if l.startswith("PASTE ")]
check("still pasting after the pan (the block was not dropped)", pa and "pasting=1" in pa[0], pa)
# --- the middle button pans while a symbol floats
o = run(["newdoc \"ISO A4\" landscape", "lib " + lib, "libghost %d" % ROW0, "vieworigin", "mouse mdown 100 100", "mouse move 80 90", "mouse mup 80 90", "vieworigin", "ghostinfo"])
g = origins(o)
check("a middle drag with a symbol floating pans the view", len(g) == 2 and abs(g[1][0] - g[0][0] - 20) < 1.5 and abs(g[1][1] - g[0][1] - 10) < 1.5, g)
# --- R and X on the pasted block
def dropped(keys):
    out = os.path.join(tmp, "k%d.dsn" % (k[0] + 1))
    run(["open " + SRC, "tool select", "selectall", "copy", "paste"] + ["viewkey " + x for x in keys] + ["mouse move 150 150", "mouse down 150 150", "mouse up 150 150", "save " + out])
    w = wires(out); return w[2:] if w and len(w) >= 4 else w
def vert(w): return abs(w[0][0] - w[1][0]) < 1e-6 and abs(w[0][1] - w[1][1]) > 1
def horiz(w): return abs(w[0][1] - w[1][1]) < 1e-6 and abs(w[0][0] - w[1][0]) > 1
w0 = dropped([])
check("without a key the pasted wires are horizontal and share their left end", w0 and all(horiz(w) for w in w0) and abs(min(w0[0][0][0], w0[0][1][0]) - min(w0[1][0][0], w0[1][1][0])) < 1e-6, w0)
w1 = dropped(["r"])
check("R turns the pasted block: the wires are vertical", w1 and len(w1) == 2 and all(vert(w) for w in w1), w1)
w2 = dropped(["r", "r"])
check("R twice: horizontal again", w2 and all(horiz(w) for w in w2), w2)
wx = dropped(["x"])
check("X flips the pasted block left-right: the wires now share their right end", wx and all(horiz(w) for w in wx) and abs(max(wx[0][0][0], wx[0][1][0]) - max(wx[1][0][0], wx[1][1][0])) < 1e-6, wx)
print("paste keys checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
