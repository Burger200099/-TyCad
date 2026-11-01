#!/usr/bin/env python3
"""A Symbol Text object moves as one block: pressing on any of its lines (its name, or an added parameter line) and dragging moves the object; the lines keep their places relative to it
(the lines are not dragged out of the block one at a time, as the fields of an ordinary symbol are). Also when it was chosen with a drag box. Oracle: the saved file: the object's pos
changes by the drag (mm, on the grid) and every FIELD pos (relative to the object) is the same as before the drag. Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Symbol text move checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:500])
def run(lines, tag):
    f = os.path.join(tmp, tag + ".dsn"); sp = os.path.join(tmp, tag + ".txt")
    open(sp, "w").write("\n".join(lines + ["savedocas " + f]) + "\n")
    subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=200, env=dict(os.environ, HOME=tempfile.mkdtemp(dir=tmp)))
    t = open(f, encoding="utf-8", errors="replace").read()
    m = re.search(r"<SYMTEXT [^>]*pos='([-\d.]+),([-\d.]+)'", t)
    fields = re.findall(r"<FIELD [^>]*pos='([^']*)'", t)
    return (float(m.group(1)), float(m.group(2))) if m else None, fields
H = ["newdoc A4", "registerframe x all", "tool symboltext", "frameinfo tool", "frameact tool edSymbolText text Pump 7", "clickmm 80 60", "tool select", "symlist sel open", "symlist sel add", "symlist sel add", "symlist sel close"]
p0, f0 = run(H + ["selclear", "clickmm 84 58.5"], "before")
check("premise: the object is at 80,60 and has three lines (name and two added)", p0 == (80.0, 60.0) and len(f0) >= 3, (p0, f0))
for label, sel in [("pressed on the name line of the chosen object", ["clickmm 84 58.5"]), ("chosen with a drag box", ["selclear", "mouse move 60 40", "mouse down 60 40", "mouse move 120 80", "mouse up 120 80"])]:
    p1, f1 = run(H + sel + ["mouse move 84 58.5", "mouse down 84 58.5", "mouse move 94 63.5", "mouse move 114 78.5", "mouse up 114 78.5"], "m" + str(len(label)))
    check("%s: the object moved by the drag (+30,+20 mm)" % label, p1 is not None and abs(p1[0] - 110) < 1.5 and abs(p1[1] - 80) < 1.5, p1)
    check("%s: every line kept its place in the block" % label, f1 == f0, (f0, f1))
print("symbol text move: %d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
