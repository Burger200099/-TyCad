#!/usr/bin/env python3
"""Print window check box "Center to page" (printdialog center=0|1) on the test bitmap sink, A4 pages, 100 dpi. A sheet with a line of text is printed at 50 per cent (the sheet is
half the page) with the box off and on. Oracle: off, the text is where the corner-origin print puts it; on, it is moved by half of what the sheet leaves free of the page, both ways
(the sheet is 297 x 210 mm: at 50 per cent the free part is half of each side), and nothing else changes in the picture (same ink); at 100 per cent (the sheet fills the page) the two prints are
the same; the dialog reports the choice. Needs xvfb-run, the built program and Pillow."""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
try:
    from PIL import Image, ImageChops
except ImportError:
    Image = None
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or Image is None:
    print("Print center checks skipped: need xvfb-run, the built program and Pillow"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:500])
def printed(scale, center):
    out = os.path.join(tmp, "o%s_%s" % (scale, center)); os.makedirs(out, exist_ok=True)
    sp = os.path.join(tmp, "s.txt")
    open(sp, "w").write("newdoc A4\ntool text\nframeact tool edText text Visible\nclickmm 80 60\ntool select\nprintsink %s 100\nprintdialog scale=%s center=%s press=ok\n" % (out, scale, center))
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=dict(os.environ, HOME=tempfile.mkdtemp(dir=tmp)))
    return Image.open(os.path.join(out, "page_1.png")).convert("L"), r.stdout
def ink(im):
    return im.point(lambda p: 255 if p < 128 else 0).getbbox()
a, oa = printed(50, 0); b, ob = printed(50, 1)
ba, bb = ink(a), ink(b)
check("both prints have ink", ba and bb, (ba, bb))
if ba and bb:
    dx, dy = bb[0] - ba[0], bb[1] - ba[1]
    k = 100 / 25.4
    check("centred: moved to the right by about half of the free width (dx %d)" % dx, abs(dx - 0.25 * 297 * k) < 25, (dx, dy, ba, bb))
    check("centred: moved down by about half of the free height (dy %d)" % dy, abs(dy - 0.25 * 210 * k) < 25, (dx, dy, ba, bb))
    moved = ImageChops.offset(a, dx, dy)
    check("nothing else changes: the centred picture is the other one moved", sum(1 for p in ImageChops.difference(moved.crop((bb[0] - 5, bb[1] - 5, bb[2] + 5, bb[3] + 5)), b.crop((bb[0] - 5, bb[1] - 5, bb[2] + 5, bb[3] + 5))).tobytes() if p > 64) < 30)
c, oc = printed(100, 0); d, od = printed(100, 1)
check("at 100 per cent the sheet fills the page: centring changes nothing", ImageChops.difference(c, d).getbbox() is None, ImageChops.difference(c, d).getbbox())
check("dialog reports the choice", "center=0" in oa and "center=1" in ob, (oa[:200], ob[:200]))
print("print center: %d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
