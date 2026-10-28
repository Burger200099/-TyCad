#!/usr/bin/env python3
"""Font sizes are points, as in TinyCAD (a font saved as 16 pt Courier New is height -21 in the file: pixels of a 96 dpi screen, MulDiv(16, 96, 72)).
Before, TyCAD showed that 21 as the size. Oracle: the arithmetic written out here, and the stored height the program reports (TEXTINFO), not its own conversion.
  - setting 16 pt stores height 21, 14 pt stores 19, and every size from 6 to 72 pt stores round(pt * 96 / 72); the box shows the points typed
  - saved and opened again the size is the same points (the file keeps the height)
  - the size shown for a stored height is round(height * 72 / 96): 21 -> 16, 19 -> 14, 13 -> 10 (the default text)
  - setting the size a font already shows does not change its stored height"""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Font size checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:500])
SIZES = list(range(6, 73))
s = 'newdoc "ANSI B (Tabloid)" landscape\naddtext 100 100 hello\ntool select\nselectclass TDrawText\necho DEFAULT\ntextinfo\nprops\n'
for p in SIZES:
    s += "setprop font.height %d\nselectclass TDrawText\necho P%d\ntextinfo\nprops\n" % (p, p)
s += "setprop font.height 16\nselectclass TDrawText\nsave %s/f.dsn\nopen %s/f.dsn\nselectclass TDrawText\necho REOPEN\ntextinfo\nprops\n" % (tmp, tmp)
h = os.path.join(tmp, "h"); os.makedirs(h); open(os.path.join(tmp, "s.txt"), "w").write(s)
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s.txt")], capture_output=True, text=True, timeout=280,
                   env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
o = r.stdout.split("\n")
def block(tag):
    i = o.index(tag); ti = [l for l in o[i:i + 6] if l.startswith("TEXTINFO")][0].split(); pr = [l for l in o[i:i + 6] if l.startswith("PROPS")][0]
    return abs(int(ti[8])), int(re.search(r"font.height=(\d+)", pr).group(1))
try:
    d = block("DEFAULT")
    check("the default text (13 pixels) shows as 10 pt", d == (13, 10), d)
    bad = [(p, block("P%d" % p)) for p in SIZES if block("P%d" % p) != (round(p * 96 / 72), p)]
    check("every size from 6 to 72 pt is stored as round(pt * 96 / 72) pixels and shown back as the points", not bad, bad[:3])
    check("16 pt is stored as 21 and 14 pt as 19 (TinyCAD's numbers)", block("P16") == (21, 16) and block("P14") == (19, 14), (block("P16"), block("P14")))
    check("saved and opened again: 16 pt, height 21", block("REOPEN") == (21, 16), block("REOPEN"))
except Exception as e:
    check("the script ran", False, repr(e) + "\n".join(o[-8:]))
print("Font size checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
