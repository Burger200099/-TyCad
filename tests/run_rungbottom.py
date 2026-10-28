#!/usr/bin/env python3
"""The rung number grid's one handle: the middle of the bottom edge, dragged up or down to set where the table ends (replaces the 'above block' check box).
Oracles (worked out here, not from the program's code): the area printed by the program (RUNGAREA, mm) - after a drag its bottom is the old bottom plus the drag
(within the grid snap), its left, right and top are unchanged, the row height is (bottom - top) / rows; one undo step; saved and read back; a press away from the handle
does nothing to the area; the bottom never goes above the top plus the rows or below the sheet; an old file with aboveblock keeps its look until the handle is dragged,
which then takes over. Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, re, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Rung bottom checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:500])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    return subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env).stdout.splitlines()
def areas(o):
    out = []
    for l in o:
        m = re.match(r"RUNGAREA (\S+) (\S+) (\S+) (\S+) rowh=(\S+)", l)
        if m: out.append(tuple(float(x) for x in m.groups()))
    return out
o = run(["newdoc A4 landscape", "grid 5", "rungs", "info"])
SH = float(re.search(r"page=(\d+)x(\d+)", "\n".join(o)).group(2)) / 5      # the sheet's height, mm
a0 = areas(o)[0]; L, T, R, B, rowh = a0
check("the default table: 20 rows share the height", abs(rowh - (B - T) / 20) < 0.01, a0)
cx = (L + R) / 2
def drag(y_from, y_to, x=cx, extra=()):
    return ["newdoc A4 landscape", "grid 5", "rungs"] + list(extra) + ["mouse down %g %g" % (x, y_from), "mouse move %g %g" % (x, (y_from + y_to) / 2), "mouse move %g %g" % (x, y_to), "mouse up %g %g" % (x, y_to), "rungs"]
# drag the handle (just below the middle of the bottom edge) up by 40 mm
o = run(drag(B + 1, B + 1 - 40))
a1 = areas(o)[-1]
check("dragging the handle up by 40 mm moves the bottom up by 40 (within the 5 mm grid)", abs((B - a1[3]) - 40) <= 5.01 and a1[3] < B - 30, (a0, a1))
check("the left, right and top of the table are unchanged", abs(a1[0] - L) < 0.01 and abs(a1[1] - T) < 0.01 and abs(a1[2] - R) < 0.01, (a0, a1))
check("the rows share the new height: row height = (bottom - top) / 20", abs(a1[4] - (a1[3] - a1[1]) / 20) < 0.01, a1)
# one undo step
o = run(drag(B + 1, B + 1 - 40) + ["undo", "rungs"])
check("one undo brings the old bottom back", abs(areas(o)[-1][3] - B) < 0.01, areas(o)[-2:])
# a press away from the handle (on the middle of the bottom edge, inside) does not resize
o = run(drag(B - 20, B - 60))
check("a press inside the table (not on the handle) does not change its bottom", abs(areas(o)[-1][3] - B) < 0.01, areas(o)[-2:])
o = run(drag(B + 1, B + 1 - 40, x=L + 10))
check("a press under the left end of the edge (not the middle) does not resize", abs(areas(o)[-1][3] - B) < 0.01, areas(o)[-2:])
# the limits: never above the top plus the rows, never below the sheet
o = run(drag(B + 1, T - 100)); a2 = areas(o)[-1]
check("dragged far up the bottom stops below the top (at least one unit per row)", a2[3] > a2[1] and a2[4] > 0, a2)
o = run(drag(B + 1, 400)); a3 = areas(o)[-1]
check("dragged far down the bottom stops at the sheet's bottom edge", abs(a3[3] - SH) < 0.01 and a3[3] > B, a3)
# saved and read back
dsn = os.path.join(tmp, "a.dsn")
o = run(drag(B + 1, B + 1 - 40) + ["save " + dsn, "open " + dsn, "rungs"])
txt = open(dsn, encoding="utf-8", errors="replace").read() if os.path.exists(dsn) else ""
check("the bottom is saved (attribute bottom=) and read back the same", "bottom=" in txt and len(areas(o)) >= 2 and abs(areas(o)[-1][3] - areas(o)[-2][3]) < 0.01, (areas(o)[-2:], re.findall(r"<RUNGS[^>]*>", txt)))
# an old file with aboveblock keeps its look; the handle then takes over
o = run(["newdoc A4 landscape", "rungs", "setrungs 20 1 5 1 1 1 1", "rungs"])
ab = areas(o)[-1]
o = run(["newdoc A4 landscape", "rungs", "setrungs 20 1 5 1 1 1 1"] + ["mouse down %g %g" % (cx, ab[3] + 1), "mouse move %g %g" % (cx, ab[3] - 19), "mouse up %g %g" % (cx, ab[3] - 19), "rungs"])
ab2 = areas(o)[-1]
check("with 'above block' on, dragging the handle takes over: the bottom moves and aboveblock goes off", ab2[3] < ab[3] - 10 and "aboveblock=0" in [l for l in o if l.startswith("RUNGS id")][-1], (ab, ab2))
print("%d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
