#!/usr/bin/env python3
"""A wire of no length in a design (it can be left by pasting and moving copies again and again) must not stop a Ctrl+drag copy or a move of the whole selection:
the wire engine used to divide by the wire's length (LineIsPointOnLine) and raised "division by zero" inside TWireEngine.AddAttachedObjects.
The design is the PSU sample with a wire of no length added on the end of another wire. Select all, drag the selection (once as a move, once with Ctrl held, a copy),
and check the program answered without an error and went on to the end.
The program is run with floating point exceptions on (script command fpuexceptions), as it is on Windows.
Needs the built program and xvfb."""
import os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic")); EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Zero length wire checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:600])
def run(lines):
    h = tempfile.mkdtemp(dir=tmp); f = os.path.join(tmp, "s.txt"); open(f, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n")
src = open(os.path.join(EX, "circuits", "PSU.dsn"), encoding="utf-8", errors="surrogateescape").read()
d = os.path.join(tmp, "z.dsn")
open(d, "w", encoding="utf-8", errors="surrogateescape").write(src.replace("<WIRE a='84,61' b='113.8,61'/>", "<WIRE a='84,61' b='113.8,61'/>\n<WIRE a='84,61' b='84,61'/>", 1))
def wires(path):
    root = ET.parse(path).getroot(); out = []
    for e in root.iter("WIRE"):
        a = tuple(float(v) for v in e.get("a").split(",")); b = tuple(float(v) for v in e.get("b").split(",")); out.append((a, b))
    return out
check("test setup: the design has a wire of no length", sum(1 for a, b in wires(d) if a == b) == 1)
o = run(["fpuexceptions on", 'open "%s"' % d, "selectall", "mouse move 100 61", "mouse down 100 61", "mouse move 110 71 ctrl", "mouse up 110 71", "echo COPYDONE", "selectall",
         'open "%s"' % d, "selectall", "mouse move 100 61", "mouse down 100 61", "mouse move 110 71", "mouse up 110 71", "echo MOVEDONE", "selectall", "echo END"])
bad = [l for l in o if "ERROR" in l or "xception" in l or "EZeroDivide" in l or "EInvalidOp" in l]
check("no error from the Ctrl+drag copy or from the move", not bad, bad[:3])
check("both ran to the end", "COPYDONE" in o and "MOVEDONE" in o and "END" in o)
sel = [int(l.split()[1]) for l in o if l.startswith("SELECTALL ")]
check("the copy kept the selection of what was copied and the move left the objects (same count before and after)", len(sel) == 4 and sel[2] == sel[3] and sel[1] > 0, sel)
print("Zero length wire checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
