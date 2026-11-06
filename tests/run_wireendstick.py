#!/usr/bin/env python3
"""The end handle of a chosen wire sticks to a wire (or a pin) it is dragged onto, as the wire tool does, and not only to the grid: an end that stopped short of an off-grid
pin was not attached to it, so the wire stayed behind when the symbol moved. Design units are 0.2 mm (mm x 5). Oracle: worked by hand -- a vertical wire drawn with snap off at
x = 50.7 mm (the program puts it at a screen pixel: 253.14), a horizontal wire from x = 20 to 40 mm at y = 45 mm on the 2.5 mm grid, its end pulled to the other wire (mouse at x = 50.4 mm): the end goes to
the wire's x, where it used to stop on the grid at x = 50 mm (250). With auto snap off it goes to the grid point, as before.
Needs xvfb-run and the built program."""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
exe0 = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(exe0):
    print("Wire end stick checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(exe0, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "h"); os.makedirs(home)
def wire(x1, y1, x2, y2): return "tool wire\nmouse move %s %s\nmouse down %s %s\nmouse up %s %s\nmouse move %s %s\nmouse down %s %s\nmouse up %s %s\ntool select\n" % ((x1, y1) * 3 + (x2, y2) * 3)
def run(extra):
    s = 'newdoc "ISO A4" landscape\ngridmm 2.5\nsnap off\n' + wire(50.7, 30, 50.7, 60) + "snap on\n" + extra + wire(20, 45, 40, 45)
    s += "mouse move 30 45\nmouse down 30 45\nmouse up 30 45\nmouse move 40 45\nmouse down 40 45\nmouse move 46 45.2\nmouse move 50.4 45.2\nmouse up 50.4 45.2\nobjects\n"
    open(tmp + "/s.txt", "w").write(s)
    o = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", tmp + "/s.txt"], capture_output=True, text=True, timeout=240,
                       env=dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))).stdout.split("\n")
    return sorted(tuple(float(x) for x in l.split()[2:6]) for l in o if l.startswith("OBJ wire"))
bad = []
def check(n, ok, d=""):
    print(("ok   " if ok else "FAIL ") + n + ("" if ok else " " + str(d)))
    if not ok: bad.append(n)
w = run("")
a = [t for t in w if abs(t[1] - 225) < 1 and abs(t[3] - 225) < 1 and t[0] < 150]
v = [t for t in w if abs(t[0] - t[2]) < 0.01]
check("the pulled end sticks to the wire drawn off the grid (its x, not the grid's 250)", len(a) == 1 and v and abs(a[0][2] - v[0][0]) < 0.01 and abs(a[0][2] - 250) > 1, w)
w = run("options autosnap=0\n")
a = [t for t in w if abs(t[1] - 225) < 1 and abs(t[3] - 225) < 1 and t[0] < 150]
check("with auto snap off the end goes to the grid point (250, 225)", len(a) == 1 and abs(a[0][2] - 250) < 0.01, w)
print("wire end stick: %d failed" % len(bad)); sys.exit(1 if bad else 0)
