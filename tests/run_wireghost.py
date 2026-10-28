#!/usr/bin/env python3
"""The wire being drawn (the ghost, red until confirmed) is as thick as the width chosen in the Wire tool's panel, follows a change of it, and is
as thick as the wire it becomes. Oracle: the rendered form bitmap (numpy / PIL) -- thickness of the changed pixels in a column through the middle of
the segment, compared with the thickness of the same wire once placed. Needs xvfb-run, numpy, PIL and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
try:
    import numpy as np
    from PIL import Image
except Exception:
    print("Wire ghost checks skipped: need numpy and PIL"); sys.exit(0)
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Wire ghost checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; checks = 0
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
def img(n): return np.array(Image.open(fp(n)).convert("RGB")).astype(int)[250:-40]
def thick(a, b):
    """thickness of the changed pixels (b against a) in the column through the middle of the changed area"""
    m = np.abs(a - b).sum(axis=2) > 60
    ys, xs = np.nonzero(m)
    if len(xs) == 0: return 0
    x = int(np.median(xs)); col = np.nonzero(m[:, x])[0]
    return int(len(col))
def ghost(tool, width):
    run(["newdoc A4", "registerframe x all", "ribbontab Draw", "tool " + tool, "frameact tool seWireSize text %d" % width if tool != "line" else "echo",
         "mouse move 60 100", "mouse down 60 100", "mouse up 60 100", "formshot " + fp("a.bmp"),
         "mouse move 160 100", "formshot " + fp("b.bmp"),
         "mouse down 160 100", "mouse up 160 100", "mouse rdown 160 100", "tool select", "formshot " + fp("c.bmp")])
    return thick(img("a.bmp"), img("b.bmp")), thick(img("a.bmp"), img("c.bmp"))
res = {}
for w in (1, 3, 7):
    res[w] = ghost("wire", w)
    check("wire width %d: the ghost is as thick as the placed wire (%s)" % (w, res[w]), res[w][0] > 0 and abs(res[w][0] - res[w][1]) <= 1, res[w])
check("a wider width gives a thicker ghost", res[1][0] < res[3][0] < res[7][0], res)
# the width is changed while the segment is being drawn: the ghost follows without the pointer moving
run(["newdoc A4", "registerframe x all", "ribbontab Draw", "tool wire", "mouse move 60 100", "mouse down 60 100", "mouse up 60 100", "mouse move 160 100",
     "formshot " + fp("d.bmp"), "frameact tool seWireSize text 7", "formshot " + fp("e.bmp")])
a, b = img("d.bmp"), img("e.bmp")
check("changing the width while drawing changes the ghost at once", int((np.abs(a - b).sum(axis=2) > 60).sum()) > 50)
for tl in ("bus", "line"):
    run(["newdoc A4", "ribbontab Draw", "tool " + tl, "mouse move 60 100", "mouse down 60 100", "mouse up 60 100", "formshot " + fp("a.bmp"), "mouse move 160 100", "formshot " + fp("b.bmp")])
    check("the %s ghost is drawn" % tl, thick(img("a.bmp"), img("b.bmp")) > 0)
print("wire ghost checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
