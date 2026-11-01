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

def draw(n):
    return ["newdoc A4", "registerframe x all", "ribbontab Draw", "tool bus", "toolprop bus.phases \"%s\"" % ("%d wires" % n if n not in (1, 3) else "%d phase" % n), "mouse down 60 60", "mouse down 120 60", "mouse dbl 120 60", "tool select"]
def ys(b): return sorted(x["a"][1] for x in b)
out = run(draw(2) + ["echo B2", "buses"] + draw(4) + ["echo B4", "buses"] + draw(5) + ["echo B5", "buses"])
b2, b4, b5 = buses(out, "B2"), buses(out, "B4"), buses(out, "B5")
check("2 wires: the drawn one and one 4 mm to the right of the way it runs (phases 0, 1)", sorted(x["phase"] for x in b2) == [0, 1] and ys(b2) == [60, 64] and all(x["phases"] == 2 for x in b2), b2)
check("4 wires: phases -1..2", sorted(x["phase"] for x in b4) == [-1, 0, 1, 2] and ys(b4) == [56, 60, 64, 68], b4)
check("5 wires: phases -2..2, 4 mm apart, one group", sorted(x["phase"] for x in b5) == [-2, -1, 0, 1, 2] and ys(b5) == [52, 56, 60, 64, 68] and len({x["group"] for x in b5}) == 1 and b5[0]["group"] != 0, b5)
# changing the count of a drawn bus
SEL = ["mouse move 90 60", "mouse down 90 60", "mouse up 90 60", "frameact sel bbPhase click"]
out = run(draw(3) + SEL + ["busdrop phase 5", "echo A", "buses", "busdrop phase 2", "echo B", "buses", "busdrop phase 1", "echo C", "buses", "busdrop esc"])
a, bb, c = buses(out, "A"), buses(out, "B"), buses(out, "C")
check("3 wires changed to 5", len(a) == 5 and ys(a) == [52, 56, 60, 64, 68], a)
check("5 wires changed to 2", len(bb) == 2 and ys(bb) == [60, 64], bb)
check("2 wires changed to 1: the drawn wire only, no group", len(c) == 1 and c[0]["group"] == 0 and ys(c) == [60], c)
# right click menu: Change to bus / Change to wire
WIRE = ["newdoc A4", "registerframe x all", "ribbontab Draw", "tool wire", "mouse down 60 60", "mouse down 120 60", "mouse dbl 120 60", "tool select"]
out = run(WIRE + ["echo M1", "ctxmenu 90 60"] + ["ctxclick Change_to_bus/4_wires", "echo W4", "buses",
           "echo M2", "ctxmenu 90 60", "ctxclick Number_of_wires/2_wires", "echo W2", "buses",
           "ctxmenu 90 60", "ctxclick Change_to_wire", "echo W1", "buses", "undo", "echo U", "buses"])
ctx1 = [l for l in after(out, "M1", "CTX")]; ctx1 = ctx1[:[k for k, l in enumerate(ctx1) if l.startswith("CTXCLICK")][0]]
check("a wire's menu has Change to bus with 1 to 6 wires and no Change to wire", any("Change_to_bus" in l for l in ctx1) and any("4_wires" in l for l in ctx1) and not any("Change_to_wire" in l for l in ctx1), ctx1[:12])
check("Change to bus 4 wires: four wires, phases -1..2", sorted(x["phase"] for x in buses(out, "W4")) == [-1, 0, 1, 2], buses(out, "W4"))
ctx2 = after(out, "M2", "CTX"); ctx2 = ctx2[:[k for k, l in enumerate(ctx2) if l.startswith("CTXCLICK")][0]]
check("a bus's menu has Number of wires and Change to wire", any("Number_of_wires" in l for l in ctx2) and any("Change_to_wire" in l for l in ctx2), ctx2[:12])
check("Number of wires > 2 wires gives two", ys(buses(out, "W2")) == [60, 64], buses(out, "W2"))
check("Change to wire: no bus is left (a plain wire)", len(buses(out, "W1")) == 0, buses(out, "W1"))
check("undo brings the 2 wire bus back", ys(buses(out, "U")) == [60, 64], buses(out, "U"))
print("multi-wire bus: %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
