#!/usr/bin/env python3
"""A text object's box is as wide as the text drawn in its font (real font measuring, as TinyCAD measures with GDI at five times the size and divides by five).
Oracle: PIL measures the same TrueType files at five times the size (65 pixels for the 13 unit text font), divided by five, and the unit is 0.2 mm; the
table of Arial widths (the script default) is shown to give another width for the monospace face, so the test cannot pass by the table."""
import os, shutil, subprocess, sys, tempfile
from PIL import ImageFont
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
FONTS = {"DejaVu Sans Mono": "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", "DejaVu Sans": "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"}
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not all(os.path.exists(p) for p in FONTS.values()):
    print("Text metrics checks skipped: need xvfb-run, the built program and the DejaVu fonts"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:300])
TEXT = "CURE OVEN BURNER #3"
s = "newdoc A4\nfontface 0 \"DejaVu Sans Mono\"\naddtext 40 40 \"%s\" 3\ntextbox 0\nmetrics real\nnewdoc A4\nfontface 0 \"DejaVu Sans Mono\"\naddtext 40 40 \"%s\" 3\ntextbox 0\n" % (TEXT, TEXT)
s += "fontface 0 \"DejaVu Sans\"\naddtext 40 60 \"%s\" 3\ntextbox 1\nnewdoc A4\nfontface 0 \"DejaVu Sans\"\naddtext 40 60 \"%s\" 3\ntextbox 0\n" % (TEXT, TEXT)
h = os.path.join(tmp, "h"); os.makedirs(h); open(os.path.join(tmp, "s.txt"), "w").write(s)
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s.txt")], capture_output=True, text=True, timeout=120,
                   env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
tb = [tuple(map(float, l.split()[1:])) for l in r.stdout.split("\n") if l.startswith("TEXTBOX")]
def want(face):
    f = ImageFont.truetype(FONTS[face], 65)
    return f.getlength(TEXT) / 5 * 0.2          # mm
try:
    table_mono = tb[0]; real_mono = tb[1]; real_prop = tb[2]
    check("the table of Arial widths (the script default) does not fit the monospace face: more than 1.5% off", abs(table_mono[0] - want("DejaVu Sans Mono")) > 0.015 * want("DejaVu Sans Mono"), (table_mono, want("DejaVu Sans Mono")))
    check("monospace face: the box is as wide as the text (within 1.5%)", abs(real_mono[0] - want("DejaVu Sans Mono")) < 0.015 * want("DejaVu Sans Mono"), (real_mono, want("DejaVu Sans Mono")))
    check("proportional face: the box is as wide as the text (within 1.5%)", abs(real_prop[0] - want("DejaVu Sans")) < 0.015 * want("DejaVu Sans"), (real_prop, want("DejaVu Sans")))
    check("the two faces give different widths (the font is used)", abs(real_mono[0] - real_prop[0]) > 1, (real_mono, real_prop))
    check("the box is not taller than the font's line (13 units = 2.6 mm: about 1.2 to 1.35 of it)", 2.6 * 1.0 < real_mono[1] < 2.6 * 1.45, real_mono)
except Exception as e:
    check("the script ran", False, repr(e) + r.stdout[-400:] + r.stderr[-300:])
print("Text metrics checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
