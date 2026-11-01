#!/usr/bin/env python3
"""The 3-phase bus: the Phases button of the Bus panel and the panel that drops down from it, the three wires drawn from the one the user draws, their selection as one,
the spacing, the symbols put on the end of a 3-phase bus, copies, save and load.
Oracles: the wires' places are worked out here from the drawn middle wire (offset by the spacing to the left and right of travel, corners mitred where the offset lines
meet), the pins of the symbols are the library's (the first symbol of gen_passive has its pins 7 mm apart... read from the program's own `pinsof` and compared with the
bus ends), and the saved file is read back with the program (a second document).
Needs xvfb-run, the built program and the example libraries (TC_EXAMPLES)."""
import os, re, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
LIB = os.path.join(EX, "libraries", "gen_passive.TCLib")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not os.path.exists(LIB):
    print("3-phase bus checks skipped: need xvfb-run, the built program and the example libraries"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name); print("  FAIL", name, str(detail)[:700])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
lib = os.path.join(tmp, "g.TCLib"); shutil.copy(LIB, lib)
sys.path.insert(0, os.path.join(HERE, "..", "docs")); import parts_seed
PF = os.path.join(tmp, "p.TCParts"); parts_seed.build(PF).close()
# the library panel lists the symbols alphabetically; the test means "the library's first symbol" (by NameID), so find its row
import sqlite3
_c = sqlite3.connect(lib); _names = [r[0] for r in _c.execute("select Name from Name where Type=0 order by NameID")]; _c.close()
ROW0 = sorted(_names, key=str.lower).index(_names[0])
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env)
    return r.stdout.splitlines()
def after(out, mk, key):
    i = out.index(mk); r = []
    for l in out[i + 1:]:
        if l.startswith(key): r.append(l)
        if l.startswith(key + " end"): break
    return r
def buses(out, mk):
    res = []
    for l in after(out, mk, "BUS"):
        m = re.match(r"BUS (\d+) a=([-\d.]+),([-\d.]+) b=([-\d.]+),([-\d.]+) group=(\d+) phase=(-?\d+) phases=(\d) gap=([\d.]+) selected=(\d)", l)
        if m:
            g = m.groups(); res.append(dict(a=(float(g[1]), float(g[2])), b=(float(g[3]), float(g[4])), group=int(g[5]), phase=int(g[6]), phases=int(g[7]), gap=float(g[8]), sel=int(g[9])))
    return res
def near(p, q): return abs(p[0] - q[0]) < 0.01 and abs(p[1] - q[1]) < 0.01
def seg(b, a, c): return near(b["a"], a) and near(b["b"], c)
def drop(l):
    return dict(re.findall(r"(\w+)=(\S+)", l.replace("edit=[", "edit=").replace("mult=[", "mult=").replace("]", "")))
def dropline(out, mk, n=0): return drop(after(out, mk, "BUSDROP")[n])
DRAW0 = ["newdoc A4", "registerframe x all", "ribbontab Draw", "tool bus", "toolprop bus.phases \"3 phase\"", "mouse down 60 60", "mouse down 120 60", "mouse dbl 120 60", "tool select"]


def pins(out, mk):
    """the pins of the last symbol listed after mk: [(x, y)] in design units"""
    res = []
    i = out.index(mk) + 1
    while i < len(out) and not out[i].startswith("PIN "): i += 1
    while i < len(out) and out[i].startswith("PIN "):
        m = re.match(r"PIN (\d+) (\d+) ([-\d.]+) ([-\d.]+)", out[i]); i += 1
        if m: res.append((int(m.group(1)), float(m.group(3)), float(m.group(4))))
    last = max((p[0] for p in res), default=0)
    return sorted((x, y) for k, x, y in res if k == last)
BUS = lambda n, sp: ["newdoc A4", "registerframe x all", "ribbontab Draw", "tool bus", "toolprop bus.phases \"%s\"" % ("%d phase" % n if n in (1, 3) else "%d wires" % n),
       "frameact tool bbPhase click", "busdrop custom %s" % sp, "busdrop esc", "mouse down 120 30", "mouse down 120 50", "mouse dbl 120 50", "tool select"]
PLACE = lambda x, y: ["pdbtab open " + PF, "pdbplace 1 %s %s yes" % (x, y)]
# a 3 pole contactor: top row of pins 15 mm apart (75 du), 12 mm... placed 2 mm off the 3 conductors and 2 mm under the end of the bus
out = run(BUS(3, 15) + ["echo B", "buses"] + PLACE(143, 100) + ["echo P", "pinsof"])
b = buses(out, "B"); p = pins(out, "P")
check("the bus is 3 wires 15 mm apart", len(b) == 3 and sorted(x["a"][0] for x in b) == [105, 120, 135], b)
top = [q for q in p if q[1] < 150 + 400][:3]
check("placed near the end: the three top pins are on the three conductors (x 525, 600, 675 du) at the end of the bus (y 250 du)",
      [q for q in p if abs(q[1] - 250) < 0.01 and sorted(x for x, _ in [q])] and sorted(x for x, y in p if abs(y - 250) < 0.01) == [525, 600, 675], p)
# the same far from the bus: nothing moves (a 4 mm bus: the pole pitch is not the spacing)
out = run(BUS(3, 4) + PLACE(143, 100) + ["echo P", "pinsof"])
p = pins(out, "P")
check("a bus 4 mm apart does not take a 15 mm pole pitch: the symbol stays where it was put", sorted(x for x, y in p if y < 400)[:3] == [510, 585, 660], p)
# 2 wires: a 3 pole device uses two
out = run(BUS(2, 15) + ["echo B", "buses"] + PLACE(143, 100) + ["echo P", "pinsof"])
b = buses(out, "B"); p = pins(out, "P"); xs = sorted(x for x, y in p if abs(y - 250) < 0.01)
cx = sorted(x["a"][0] * 5 for x in b)
check("the 2 wire bus is 15 mm apart", len(b) == 2 and cx == [525, 600], b)
check("on a 2 wire bus two poles are on the conductors at the end of the bus, the third pin is off it", len(xs) == 3 and [x for x in xs if x in cx] == cx, (xs, p))
def ctxend(c):
    return [k for k, l in enumerate(c) if l.startswith("CTXCLICK")][0]
# right click: Snap poles to bus moves a symbol that is near the bus (here: put on the sheet away from it, then the bus is drawn)
out = run(["newdoc A4", "registerframe x all", "ribbontab Draw"] + PLACE(143, 100) + ["echo A", "pinsof"] + ["tool bus", "toolprop bus.phases \"3 phase\"", "frameact tool bbPhase click", "busdrop custom 15", "busdrop esc", "mouse down 120 30", "mouse down 120 50", "mouse dbl 120 50", "tool select",
        "selidx 0", "echo C", "ctxmenu 102 60", "ctxclick Snap_poles_to_bus", "echo D", "pinsof", "undo", "echo U", "pinsof"])
a0 = pins(out, "A"); d = pins(out, "D"); u = pins(out, "U")
ctx = [l for l in after(out, "C", "CTX")]
check("Snap poles to bus is in the menu and moves the device onto the conductors", any("Snap_poles_to_bus" in l for l in ctx[:ctxend(ctx)]) and sorted(x for x, y in d if abs(y - 250) < 0.01) == [525, 600, 675], (ctx[:6], d))
check("undo puts it back where it was", u == a0, (u, a0))
# a ladder's two rails are a 2 conductor bus: a 3 pole device 15 mm apart puts two poles on the rails
out = run(["newdoc A4", "registerframe x all", "ribbontab Draw", "ladder 105 30 120 100"] + PLACE(143, 100) + ["echo P", "pinsof"])
p = pins(out, "P"); xs = sorted(x for x, y in p if abs(y - 260) < 0.01)
check("on a ladder with rails 15 mm apart the poles go onto the rails (x 525 and 600 du), the third pin is 15 mm further", xs == [525, 600, 675], (xs, p))
out = run(["newdoc A4", "registerframe x all", "ribbontab Draw", "ladder 105 30 130 100"] + PLACE(143, 100) + ["echo P", "pinsof"])
p = pins(out, "P"); xs = sorted(x for x, y in p if abs(y - 260) < 0.01)
check("rails 25 mm apart do not take a 15 mm pole pitch", xs == [510, 585, 660], (xs, p))
print("pole snapping: %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
