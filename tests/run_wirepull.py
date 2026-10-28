#!/usr/bin/env python3
"""Several wires chosen (picked by a box that crosses them, so none is wholly picked) and an end handle pulled: every chosen wire's end on that side stretches by the same step
(it used to be only the wire whose handle was pressed). Design units are 0.2 mm (mm x 5). Oracles: worked by hand.
Cases: three parallel wires, handle of the middle one pulled; first-end handle; a wire not chosen stays where it is; a wholly picked set still moves as a whole; undo restores."""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
exe0 = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(exe0):
    print("Wire pull checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(exe0, exe); os.chmod(exe, 0o755)
def wire(y, x1=40, x2=80):
    return "tool wire\nmouse move %d %d\nmouse down %d %d\nmouse up %d %d\nmouse move %d %d\nmouse down %d %d\nmouse up %d %d\ntool select\n" % (x1, y, x1, y, x1, y, x2, y, x2, y, x2, y)
base = 'newdoc "ISO A4" landscape\n' + wire(40) + wire(50) + wire(60) + wire(90)
def box(x1, y1, x2, y2): return "mouse move %d %d\nmouse down %d %d\nmouse move %d %d\nmouse up %d %d\n" % (x1, y1, x1, y1, x2, y2, x2, y2)
S = base + box(55, 35, 65, 65) + "mouse move 80 50\nmouse down 80 50\nmouse move 100 50\nmouse up 100 50\necho PULL\nobjects\nundo\necho UNDO\nobjects\n"
S += box(55, 35, 65, 65) + "mouse move 40 60\nmouse down 40 60\nmouse move 20 60\nmouse up 20 60\necho FIRST\nobjects\nundo\n"
S += "selectall\nmouse move 80 40\nmouse down 80 40\nmouse move 100 40\nmouse up 100 40\necho ALL\nobjects\n"
open(tmp + "/s.txt", "w").write(S)
out = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", tmp + "/s.txt"], capture_output=True, text=True, timeout=240).stdout.split("\n")
def wires(tag):
    i = out.index(tag); r = []
    for l in out[i + 1:]:
        if l.startswith("OBJ wire"): r.append(tuple(float(x) for x in l.split()[2:6]))
        elif l.startswith("echo") or l.strip() in ("PULL", "UNDO", "FIRST", "ALL") and r: break
    return sorted(r)
bad = []
def check(n, ok, d=""):
    print(("ok   " if ok else "FAIL ") + n + ("" if ok else " " + str(d)))
    if not ok: bad.append(n)
w = wires("PULL")
check("pulling the end of the middle wire stretches all three chosen wires to x=100 mm (500)", [t for t in w if t[1] in (200, 250, 300)] == [(200, 200, 500, 200), (200, 250, 500, 250), (200, 300, 500, 300)], w)
check("the wire that was not chosen stays", (200, 450, 400, 450) in w, w)
w = wires("UNDO"); check("undo puts all of them back", [t for t in w if t[1] in (200, 250, 300)] == [(200, 200, 400, 200), (200, 250, 400, 250), (200, 300, 400, 300)], w)
w = wires("FIRST"); check("the first-end handle stretches the first ends of all three to x=20 mm (100)", [t for t in w if t[1] in (200, 250, 300)] == [(100, 200, 400, 200), (100, 250, 400, 250), (100, 300, 400, 300)], w)
w = wires("ALL"); check("all wires wholly picked: the handle moves the whole selection (each wire keeps its length)", all(abs((t[2] - t[0]) - 200) < 1e-6 for t in w) and len(w) == 4, w)
print("wire pull: %d failed" % len(bad)); sys.exit(1 if bad else 0)
