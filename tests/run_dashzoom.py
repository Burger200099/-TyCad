#!/usr/bin/env python3
"""Line styles of the shapes (rectangle, circle, polygon, cloud, note) stay dashed when the zoom makes the pen wider than a pixel (150% and more),
where the system would draw a wide pen solid. Oracle: the rendered sheet bitmap (numpy / scipy) -- the number of separate pieces of ink: a solid outline is
one piece, a dashed one many; compared at the zoom where it always worked (the sheet fitted in the window) and at 200%.
Needs xvfb-run, numpy, PIL, scipy and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
try:
    import numpy as np
    from PIL import Image
    from scipy import ndimage
except Exception:
    print("Dash zoom checks skipped: need numpy, PIL and scipy"); sys.exit(0)
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Dash zoom checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = os.environ.get("TC_KEEP") or tempfile.mkdtemp(); fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name); print("  FAIL", name, str(detail)[:500])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env)
    return r.stdout.splitlines()
def fp(n): return os.path.join(tmp, n)
def pieces(n, base):
    a = np.array(Image.open(fp(n)).convert("RGB")).astype(int)
    ink = np.abs(a - np.array(Image.open(fp(base)).convert("RGB")).astype(int)).sum(axis=2) > 150      # what the shape added to the empty sheet
    lab, k = ndimage.label(ink, structure=np.ones((3, 3)))
    sizes = ndimage.sum(ink, lab, range(1, k + 1)) if k else []
    return int(sum(1 for z in sizes if z >= 3))
SHAPES = {
    "rect": ["tool rect", "mouse down 130 90", "mouse move 170 120", "mouse up 170 120"],
    "circle": ["tool circle", "mouse down 130 90", "mouse move 170 120", "mouse up 170 120"],
    "cloud": ["tool cloud", "mouse down 130 90", "mouse move 170 120", "mouse up 170 120"],
    "note": ["tool note", "mouse down 130 90", "mouse move 170 120", "mouse up 170 120"],
    "polygon": ["tool polygon", "mouse down 130 90", "mouse down 170 90", "mouse down 170 120", "mouse dbl 130 120"],
}
for nm, mk in SHAPES.items():
    run(["newdoc A4", "shot " + fp("e_fit.bmp"), "zoom 4", "shot " + fp("e_big.bmp")])
    run(["newdoc A4"] + mk + ["tool select", "selidx 0", "setprop line.style Dash", "shot " + fp("fit.bmp"), "zoom 4", "shot " + fp("big.bmp"),
         "setprop line.style Solid", "shot " + fp("solid.bmp")])
    f, b, s = pieces("fit.bmp", "e_fit.bmp"), pieces("big.bmp", "e_big.bmp"), pieces("solid.bmp", "e_big.bmp")
    check("%s: dashed at the fitted zoom (%d pieces)" % (nm, f), f >= 8, f)
    check("%s: still dashed at 200%% (%d pieces against %d when solid; the handles and a note's text are in both)" % (nm, b, s), b - s >= 8, (b, s))
print("dash zoom checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
