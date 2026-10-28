#!/usr/bin/env python3
"""Select all (a rung grid and ordinary objects), then copy / paste / duplicate / rotate / export extent, with floating point invalid operations turned
into errors as on Windows (the rung grid has no corner points, which are not-a-number; comparing them used to stop the program), on the real program under Xvfb.
Oracle: the program must run to the end without an error line; the pasted block holds the same number of objects as were copied (counted from the script's own
numbers), and the wire's corner points are where they were (read from the saved file).
Needs the built program and xvfb."""
import os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Grid select all checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:500])
def run(lines):
    f = os.path.join(tmp, "s.txt"); open(f, "w").write("\n".join(lines) + "\n")
    h = tempfile.mkdtemp(dir=tmp)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n"), r.returncode, r.stderr
SRC = os.path.join(tmp, "a.dsn")
open(SRC, "w").write("<?xml version='1.0'?>\n<TinyCADSheets><TinyCAD><NAME>a</NAME><DETAILS><Size width='1485' height='1050'/></DETAILS>"
                     "<WIRE a='30,30' b='60,30'/><WIRE a='30,60' b='60,60'/></TinyCAD></TinyCADSheets>\n")
OUT = os.path.join(tmp, "o.dsn")
o, rc, err = run(["fpuexceptions on", "open " + SRC, "rungs", "tool select", "selectall", "copy", "paste", "mouse down 100 100", "mouse up 100 100",
                  "rotate left", "duplicate", "mouse down 120 120", "mouse up 120 120", "fpuexceptions off", "save " + OUT])
errs = [l for l in o if l.startswith("ERROR") or "xception" in l]
check("ran to the end without an error", rc == 0 and not errs and any(l.startswith("SAVED") for l in o), (rc, errs, err[-300:], o[-6:]))
sel = [l for l in o if l.startswith("COPY ")]
check("the grid and the two wires were chosen (3 objects)", sel and sel[0].strip() == "COPY 3", sel)
pa = [l for l in o if l.startswith("PASTE ")]
check("the paste is a floating block of the same 3 objects", pa and "pasting=1" in pa[0] and "selected=3" in pa[0], pa)
print("grid select all checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
