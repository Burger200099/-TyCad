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
DRAW = ["newdoc A4", "registerframe x all", "ribbontab Draw", "tool bus", "toolprop bus.phases \"3 phase\"", "mouse down 60 60", "mouse down 120 60", "mouse dbl 120 60", "tool select"]
GRIDMM = 2    # A4's grid, read from the program below

# --- 1: a straight bus, an L shaped bus: the places of the wires
S = DRAW + ["echo S", "buses", "gridmm",
            "newdoc A4", "tool bus", "toolprop bus.phases \"3 phase\"", "mouse down 60 60", "mouse down 120 60", "mouse down 120 120", "mouse dbl 120 120", "tool select", "echo L", "buses"]
out = run(S)
b = buses(out, "S")
by = {x["phase"]: x for x in b}
check("a 3-phase bus is three wires", len(b) == 3 and sorted(by) == [-1, 0, 1], b)
check("the middle wire is the one drawn", len(b) == 3 and seg(by[0], (60, 60), (120, 60)), b)
check("the others are 4 mm either side (the spacing)", len(b) == 3 and seg(by[-1], (60, 56), (120, 56)) and seg(by[1], (60, 64), (120, 64)), b)
check("one group, 3 phases, gap 4", len(b) == 3 and len({x["group"] for x in b}) == 1 and b[0]["group"] != 0 and all(x["phases"] == 3 and abs(x["gap"] - 4) < 1e-6 for x in b), b)
L = buses(out, "L"); ly = {}
for x in L: ly.setdefault(x["phase"], []).append(x)
# the offsets of the L worked out here: a line 4 mm to the left of travel (screen y grows down: left of east-going is y-4, left of south-going is x+4)
ok = len(L) == 6 and all(len(v) == 2 for v in ly.values())
if ok:
    def has(ph, a, c): return any(seg(x, a, c) for x in ly[ph])
    ok = has(0, (60, 60), (120, 60)) and has(0, (120, 60), (120, 120)) and has(-1, (60, 56), (124, 56)) and has(-1, (124, 56), (124, 120)) and has(1, (60, 64), (116, 64)) and has(1, (116, 64), (116, 120))
check("an L shaped bus: the outer wires meet at the mitred corners (124,56) and (116,64)", ok, L)
# the oracle is sensitive: a corner not mitred is not accepted
check("(mutation) an unmitred corner is not what is expected", not (len(L) == 6 and any(seg(x, (60, 56), (120, 56)) for x in L)), L)

# --- 2: selecting
SEL = DRAW + ["mouse move 90 60", "mouse down 90 60", "mouse up 90 60", "echo C1", "buses", "selclear",
              "mouse move 90 55", "mouse down 90 55", "mouse up 90 55", "echo C2", "buses", "selclear",
              "mouse move 40 40", "mouse down 40 40", "mouse move 130 70", "mouse up 130 70", "echo R", "buses", "selclear",
              "mouse move 90 80", "mouse down 90 80", "mouse move 80 58", "mouse up 80 58", "echo L1", "buses", "selclear",
              "mouse move 130 70", "mouse down 130 70", "mouse move 50 50", "mouse up 50 50", "echo L2", "buses", "selclear",
              "mouse move 130 70", "mouse down 130 70", "mouse move 50 61", "mouse up 50 61", "echo L3", "buses"]
out = run(SEL)
count = lambda mk: sum(x["sel"] for x in buses(out, mk))
check("a click on the middle wire selects all three", count("C1") == 3, buses(out, "C1"))
check("a click on an outer wire selects all three", count("C2") == 3, buses(out, "C2"))
check("a drag to the right that touches one wire selects all three", count("R") == 3, buses(out, "R"))
check("a drag to the left that takes in only part of the bus selects none", count("L1") == 0, buses(out, "L1"))
check("a drag to the left around the whole bus selects all three", count("L2") == 3, buses(out, "L2"))
check("a drag to the left around the middle wire only (not the outer ones) selects none", count("L3") == 0, buses(out, "L3"))

# --- 3: the panel: the choice stays open, the spacing, 3 to 1 to 3, undo
P = DRAW + ["mouse move 90 60", "mouse down 90 60", "mouse up 90 60", "frameact sel bbPhase click", "echo D0", "busdrop", "busdropshot %s" % os.path.join(tmp, "bd.png"),
            "busdrop space 3", "echo D1", "busdrop", "buses", "busdrop custom 9", "echo D2", "busdrop", "buses", "busdrop custom abc", "echo D2b", "buses",
            "busdrop phase 1", "echo D3", "buses", "busdrop phase 3", "echo D4", "buses", "undo", "echo U1", "buses", "redo", "echo U2", "buses", "busdrop esc", "echo E", "busdrop",
            "frameinfo sel"]
out = run(P)
d = dropline(out, "D0")
check("the panel opens showing 3 phase and the 2 x grid (4 mm on a 2 mm grid), 4 in the box in millimetres", d.get("visible") == "1" and d.get("phases") == "3" and d.get("radios") == "010100000" and d.get("edit") == "4", d)
d = dropline(out, "D1")
b = buses(out, "D1")
check("choosing 3 x grid keeps the panel open and shows 6", d.get("visible") == "1" and d.get("radios") == "010010000" and d.get("edit") == "6", d)
check("the outer wires are now 6 mm either side", len(b) == 3 and {x["phase"]: x for x in b}.get(-1) is not None and seg({x["phase"]: x for x in b}[-1], (60, 54), (120, 54)) and seg({x["phase"]: x for x in b}[1], (60, 66), (120, 66)) and all(x["gap"] == 6 for x in b), b)
b = buses(out, "D2"); d = dropline(out, "D2")
check("a width typed (9 mm, not a whole number of grids) is Custom and moves the wires to 9 mm", d.get("radios") == "010000001" and len(b) == 3 and {x["phase"]: x for x in b}[-1]["a"][1] == 51 and {x["phase"]: x for x in b}[1]["a"][1] == 69, (d, b))
b2 = buses(out, "D2b")
check("a width that is not a number changes nothing", len(b2) == 3 and [x["a"] for x in b2] == [x["a"] for x in b], b2)
b = buses(out, "D3")
check("1 phase leaves the middle wire only, and no group", len(b) == 1 and b[0]["group"] == 0 and seg(b[0], (60, 60), (120, 60)) and b[0]["phases"] == 1, b)
b = buses(out, "D4")
check("3 phase again: three wires, new group, the spacing kept (9 mm)", len(b) == 3 and len({x["group"] for x in b}) == 1 and all(x["gap"] == 9 for x in b) and sorted(x["a"][1] for x in b) == [51, 60, 69], b)
check("undo goes back one step (1 phase)", len(buses(out, "U1")) == 1, buses(out, "U1"))
check("redo returns the three wires", len(buses(out, "U2")) == 3, buses(out, "U2"))
check("Esc closes the panel", dropline(out, "E").get("visible") == "0", after(out, "E", "BUSDROP"))
fi = [l for l in after(out, "U2", "FRAMEINFO") if "bbPhase" in l]
check("the button is bound to bus.phases and shows a 32 x 32 picture with the phases in the hint", any("bus.phases" in l and "glyph=32x32 Bus: 3 phase" in l for l in fi) or any("glyph=32x32 Bus: 3 phase" in l for l in out if l.startswith("FRAMEINFO bbPhase")), fi)
try:
    from PIL import Image
    im = Image.open(os.path.join(tmp, "bd.png")); check("the panel's picture is taken (about 190 x 262)", abs(im.size[0] - 190) <= 12 and abs(im.size[1] - 262) <= 12, im.size)
except Exception as e:
    check("the panel's picture is taken", False, e)

# --- 3b: the custom multiplier
M = DRAW + ["mouse move 90 60", "mouse down 90 60", "mouse up 90 60", "frameact sel bbPhase click", "busdrop mult 7", "echo M1", "busdrop", "buses", "busdrop mult 0", "echo M2", "busdrop", "busdrop mult 2.5", "busdrop space 5", "echo M3", "busdrop", "buses"]
out = run(M)
d = dropline(out, "M1"); b = buses(out, "M1")
check("a custom multiplier of 7 gives 14 mm on a 2 mm grid, ticks the multiplier radio and fills the box at the foot", d.get("radios") == "010000010" and d.get("mult") == "7" and d.get("edit") == "14" and sorted(x["a"][1] for x in b) == [46, 60, 74], (d, b))
d = dropline(out, "M2")
check("a multiplier that is not a whole number above zero changes nothing", d.get("edit") == "14" and d.get("radios") == "010000010", d)
d = dropline(out, "M3")
check("5 x grid after that: 10 mm", d.get("radios") == "010000100" and d.get("edit") == "10", d)

# --- 4: the tool's panel: the choice made before drawing
T = ["newdoc A4", "registerframe x all", "ribbontab Draw", "tool bus", "frameact tool bbPhase click", "busdrop phase 3", "busdrop space 5", "busdrop esc", "mouse down 60 60", "mouse dbl 120 60", "tool select", "echo T", "buses"]
out = run(T)
b = buses(out, "T")
check("the tool's panel: 3 phase and 5 x grid before drawing draws three wires 10 mm apart", len(b) == 3 and sorted(x["a"][1] for x in b) == [50, 60, 70], b)

# --- 5: symbols on the end of a 3-phase bus
Y = DRAW[:-1] + ["tool select", "lib %s" % lib, "libplace %d 122 60" % ROW0, "tool select", "echo Y", "pinsof", "objects", "buses", "selidx 3", "delete", "echo Z", "objects", "undo", "save %s" % os.path.join(tmp, "bp.dsn"), "newdoc A4", "open %s" % os.path.join(tmp, "bp.dsn"), "echo O", "buses", "objects"]
out = run(Y)
pins = [tuple(float(v) for v in l.split()[3:5]) for l in after(out, "Y", "PIN")]
ends = sorted((600.0, y) for y in (280.0, 300.0, 320.0))
check("a symbol on the middle wire's end is three symbols; the 6 pins are at the three wire ends, 4 mm apart (20 units)", all(any(abs(p[0] - e[0]) < .01 and abs(p[1] - e[1]) < .01 for p in pins) for e in ends) and len(pins) == 6, pins)
n = len([l for l in after(out, "Y", "OBJ") if "TDrawMethod" in l])
n2 = len([l for l in after(out, "Z", "OBJ") if "TDrawMethod" in l])
check("they are objects of their own: one is deleted alone, two stay", n == 3 and n2 == 2, (n, n2))
b = buses(out, "O"); n3 = len([l for l in after(out, "O", "OBJ") if "TDrawMethod" in l])
check("saved and opened again: the bus is a group of three and so are the symbols", len(b) == 3 and len({x["group"] for x in b}) == 1 and b[0]["group"] != 0 and n3 == 3, (b, n3))

# --- 6: a copy of a 3-phase bus is a group of its own
C = DRAW + ["mouse move 90 60", "mouse down 90 60", "mouse up 90 60", "duplicate", "echo D", "buses"]
out = run(C)
b = buses(out, "D"); g = sorted({x["group"] for x in b})
check("a duplicate of a 3-phase bus has a group number of its own (2 groups of 3)", len(b) == 6 and len(g) == 2 and all(sum(1 for x in b if x["group"] == k) == 3 for k in g), b)

print("%d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
