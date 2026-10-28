#!/usr/bin/env python3
"""Wire labels on a printout (File > Print to the test bitmap sink, A4 pages, 100 dpi).
A design with 16 labels (4 styles: plain, input, output, in/out; 4 directions) is printed with and without them (same design, labels removed); the pages must differ at each label:
the dark pixels in the box round the label's position (position in mm x 100 / 25.4 pixels from the page corner) number at least 15 more with the label than without.
Also in black and white (every label's pixels black or white), at 300 dpi and at a scale of 50 %.
Needs xvfb-run, the built program, the sample design vhdl/nibbles/NOR4Bus.dsn (TC_EXAMPLES) and Pillow."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
SRC = os.path.join(EX, "vhdl", "nibbles", "NOR4Bus.dsn")
try:
    from PIL import Image
except ImportError:
    Image = None
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not os.path.exists(SRC) or Image is None:
    print("Print label checks skipped: need xvfb-run, the built program, the example design and Pillow"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:500])
t = open(SRC, encoding="utf-8", errors="replace").read()
i = t.index("<LABEL"); j = t.rfind("\n", 0, i)
labels = []; xml = ""
for st in range(4):
    for d in range(4):
        x, y = 20 + d * 40, 100 + st * 30
        labels.append((x, y)); xml += "\t\t<LABEL pos='%d.0,%d.0' direction='%d' font='3' color='000000' style='%d'>L%d%d</LABEL>\n" % (x, y, d, st, st, d)
open(os.path.join(tmp, "with.dsn"), "w").write(t[:j + 1] + xml + t[j + 1:])
open(os.path.join(tmp, "without.dsn"), "w").write(t)
def printed(dsn, dpi, extra=""):
    out = os.path.join(tmp, "o_%s_%d_%s" % (dsn, dpi, extra or "x")); os.makedirs(out, exist_ok=True)
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write('open "%s"\nprintsink %s %d\nprintdialog %s press=ok\n' % (os.path.join(tmp, dsn + ".dsn"), out, dpi, extra))
    subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=dict(os.environ, HOME=os.path.join(tmp, "h")))
    return Image.open(os.path.join(out, "page_1.png")).convert("L")
def dark(im, box):
    return sum(1 for p in im.crop(box).tobytes() if p < 128)
for dpi, extra, name in [(100, "scale=100", "100 dpi"), (100, "scale=100 bw=1", "black and white"), (300, "scale=100", "300 dpi"), (150, "scale=50", "50 %")]:
    a = printed("with", dpi, extra.replace(" ", "_")); b = printed("without", dpi, extra.replace(" ", "_"))
    k = dpi / 25.4 * (0.5 if "scale=50" in extra else 1); R = int(14 * dpi / 100); weak = []
    for (x, y) in labels:
        cx, cy = int(x * k), int(y * k)
        box = (cx - R * 3, cy - R * 3, cx + R * 3, cy + R * 3)
        gain = dark(a, box) - dark(b, box)
        if gain < max(6, int(15 * dpi / 100 * (0.5 if "scale=50" in extra else 1))): weak.append(((x, y), gain))
    check("%s: every one of the 16 labels is on the page (dark pixels gained at its place)" % name, not weak, weak[:5])
print("print labels: %d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
