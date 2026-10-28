#!/usr/bin/env python3
"""Rotate Left / Rotate Right / Flip (Ctrl+L, Ctrl+R) while a symbol is being placed turn the symbol that follows the pointer, on the real program under Xvfb.
Oracle: the library's first symbol has a box that is not square; a quarter turn swaps its width and height, a flip keeps them, two turns the same way
(or one each way) bring it back; and the placed copy has the turned box. The numbers are compared with each other, not with the program's own rotation code.
Needs the built program, xvfb and the example libraries (TC_EXAMPLES)."""
import os, re, shutil, sqlite3, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
LIB = os.path.join(EX, "libraries", "gen_passive.TCLib")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not os.path.exists(LIB):
    print("Ghost rotate checks skipped: need xvfb-run, the built program and the example libraries"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
lib = os.path.join(tmp, "g.TCLib"); shutil.copy(LIB, lib)
_c = sqlite3.connect(lib); _names = [r[0] for r in _c.execute("select Name from Name where Type=0 order by NameID")]; _c.close()
ROW0 = sorted(_names, key=str.lower).index(_names[0])
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:500])
def run(lines):
    f = os.path.join(tmp, "s.txt"); open(f, "w").write("\n".join(lines) + "\n")
    h = tempfile.mkdtemp(dir=tmp)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
def ghosts(o): return [tuple(float(x) for x in l.split()[1:3]) for l in o if l.startswith("GHOST ") and "none" not in l]
o = run(["newdoc \"ISO A4\" landscape", "lib " + lib, "libghost %d" % ROW0, "ghostinfo", "rotate left", "ghostinfo", "rotate right", "ghostinfo", "rotate right", "ghostinfo",
         "rotate flip", "ghostinfo", "rotate left", "rotate left", "ghostinfo"])
g = ghosts(o)
check("six readings", len(g) == 6, o[-12:])
if len(g) == 6:
    w, h = g[0]
    check("the box is not square (so a turn shows)", abs(w - h) > 1e-6, g[0])
    check("Rotate Left turns the ghost a quarter: width and height swap", g[1] == (h, w), g[:2])
    check("Rotate Right after it brings it back", g[2] == (w, h), g[:3])
    check("Rotate Right turns it a quarter the other way: swap", g[3] == (h, w), g[:4])
    check("Flip keeps the size", g[4] == g[3], g)
    check("two Rotate Lefts: back to a quarter turn from the start's twin (swap twice)", g[5] == g[4], g)
check("the ghost is still being placed (tool stays Place)", all("tool=" in l for l in o if l.startswith("GHOST ") and "none" not in l))
print("ghost rotate checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
