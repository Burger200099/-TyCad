#!/usr/bin/env python3
"""A sheet that has not been shown yet prints its labels' text (it printed only the label's red anchor square until the sheet's tab had been clicked): a document of two sheets with
a label on each is opened, every sheet is printed to the test sink, and the first page of each sheet has the label's green text.  Needs xvfb-run, the built program and PIL."""
import os, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
try:
    from PIL import Image
except ImportError:
    Image = None
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or Image is None:
    print("print of unopened sheets skipped: need xvfb-run, the built program and PIL"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home); outd = os.path.join(tmp, "out"); os.makedirs(outd)
dsn = os.path.join(tmp, "t.dsn"); shutil.copy(os.path.join(HERE, "data", "two_sheet_labels.dsn"), dsn)
open(os.path.join(tmp, "s.txt"), "w").write("\n".join(["registerframe x all", "open " + dsn, "printsink " + outd + " 100", "printdialog sheets=all press=ok"]) + "\n")
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s.txt")], capture_output=True, text=True, timeout=300, env=env)
def green(f):
    im = Image.open(os.path.join(outd, f)).convert("RGB"); px = im.load(); n = 0
    for y in range(im.height):
        for x in range(im.width):
            r, g, b = px[x, y]
            if g > r + 40 and g > b + 40: n += 1
    return n
fails = []
# the pages come one position at a time for all sheets: page_1 is sheet 1's first page, page_2 sheet 2's
g1, g2 = green("page_1.png"), green("page_2.png")
if g1 < 50: fails.append("sheet 1 prints no label text (%d green pixels)" % g1)
if g2 < 50: fails.append("sheet 2, never shown, prints no label text (%d green pixels)" % g2)
print("print of unopened sheets: 2 checks, %d failed  (green pixels %d, %d)" % (len(fails), g1, g2))
for f in fails: print("  FAIL", f)
sys.exit(1 if fails else 0)
