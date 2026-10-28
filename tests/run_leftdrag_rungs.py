#!/usr/bin/env python3
"""Dragging a selection box to the LEFT (selects only what it holds completely) over a sheet that has a rung grid used to stop with
"invalid floating point operation": the grid has no corners of its own. Oracle: the program's own count of the selection. A box that holds the
text objects only selects the 3 texts; a box holding the whole page also selects the grid. Needs the built program and xvfb."""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Left drag checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
S = """newdoc "ISO A4" landscape
rungs
addtext 100 100 12
addtext 100 110 13
addtext 100 120 14
tool select
selclear
mouse down 130 130
mouse move 90 95
mouse up 90 95
echo A
sel
selclear
mouse down 295 205
mouse move 2 2
mouse up 2 2
echo B
sel
"""
f = os.path.join(tmp, "s.txt"); open(f, "w").write(S)
r = subprocess.run(["xvfb-run", "-a", exe, "--script", f], capture_output=True, text=True, timeout=120, env=dict(os.environ, HOME=tmp, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
o = r.stdout.split("\n"); fails = 0
a = [l for l in o[o.index("A"):] if l.startswith("SEL ")][0]; b = [l for l in o[o.index("B"):] if l.startswith("SEL ")][0]
for name, ok in (("a box holding 3 texts selects only them", a.startswith("SEL 3 ") and "RungGrid" not in a),
                 ("a box holding the page also selects the grid", "TDrawRungGrid" in b and b.startswith("SEL 4 "))):
    if not ok: fails += 1; print("  FAIL", name, a, b)
print("2 checks, %d failed" % fails); sys.exit(1 if fails else 0)
