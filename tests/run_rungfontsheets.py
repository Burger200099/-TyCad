#!/usr/bin/env python3
"""A rung grid made on a second sheet starts with the font (face, size, bold, italic, colour) of the grid on the other sheet, instead of Arial.
Oracle: the program's own property list (PROPS) read from the first sheet's grid after it was set, compared with the second sheet's new grid; and the
first sheet's grid is not changed by that. Needs the built program and xvfb."""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Rung font checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
S = """newdoc "ISO A4" landscape
rungs
setprop font.face Courier New
setprop font.height 16
setprop font.bold 1
setprop font.italic 1
props
addsheet
rungs
props
gosheet 0
rungs
props
"""
f = os.path.join(tmp, "s.txt"); open(f, "w").write(S)
r = subprocess.run(["xvfb-run", "-a", exe, "--script", f], capture_output=True, text=True, timeout=120, env=dict(os.environ, HOME=tmp, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
p = [l for l in r.stdout.split("\n") if l.startswith("PROPS font")]
fnt = lambda l: [x.strip() for x in l[6:].split(";")[:5]]
fails = 0
for name, ok in (("three property lists", len(p) == 3),
                 ("the new grid on sheet 2 has the font of sheet 1's grid", len(p) == 3 and fnt(p[1]) == fnt(p[0]) and "font.height=16" in fnt(p[1]) and "font.italic=1" in fnt(p[1])),
                 ("sheet 1's grid is unchanged", len(p) == 3 and fnt(p[2]) == fnt(p[0]))):
    if not ok: fails += 1; print("  FAIL", name, p)
print("3 checks, %d failed" % fails); sys.exit(1 if fails else 0)
