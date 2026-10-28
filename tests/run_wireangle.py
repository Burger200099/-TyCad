#!/usr/bin/env python3
"""The angle a wire, bus or line is drawn at (free / 90 / 45 degrees): the Angle list of the tool panel holds each choice once, starts as TinyCAD's
(wire 90, bus and line free), is used by the tool at once, and is kept for the whole session -- through another tool, a new sheet and a new design.
Oracle: the list as the program shows it, and the rendered sheet (numpy / PIL): a line drawn at 45 degrees is as wide as it is high.
Needs xvfb-run, numpy, PIL and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, re, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
try:
    import numpy as np
    from PIL import Image
except Exception:
    print("Wire angle checks skipped: need numpy and PIL"); sys.exit(0)
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Wire angle checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
def g(out, mk, key):
    i = out.index(mk); return [l for l in out[i + 1:] if l.startswith(key)]
def angle(out, mk): return g(out, mk, "WIREINFO")[0]
out = run(["newdoc A4", "registerframe x all", "ribbontab Draw", "tool wire", "echo W0", "comboitems tool cbAngle", "frameinfo tool", "wireinfo",
           "tool line", "echo L0", "wireinfo", "frameinfo tool", "tool bus", "echo B0", "wireinfo",
           "tool wire", "frameact tool cbAngle choose 2", "echo W1", "wireinfo", "frameinfo tool",
           "tool select", "newdoc A4", "tool wire", "echo W2", "wireinfo", "frameinfo tool", "tool line", "echo L2", "wireinfo", "tool select", "wireinfo"])
items = g(out, "W0", "COMBOITEMS")[0]
check("the list holds each way once: Free, 90 degrees, 45 degrees", re.findall(r'[^",]+', items.split(" ", 2)[2]) == ["Free", "90 degrees", "45 degrees"], items)
fi = lambda mk: [l for l in out[out.index(mk) + 1:] if l.startswith("FRAMEINFO cbAngle")][0]
check("a wire starts at 90 degrees (list shows item 1, tool uses 1)", "item=1" in fi("W0") and angle(out, "W0") == "WIREINFO angle=1", (fi("W0"), angle(out, "W0")))
check("a line starts free", "item=0" in fi("L0") and angle(out, "L0") == "WIREINFO angle=0", (fi("L0"), angle(out, "L0")))
check("a bus starts free", angle(out, "B0") == "WIREINFO angle=0", angle(out, "B0"))
check("choosing 45 degrees is used by the tool at once and shown", angle(out, "W1") == "WIREINFO angle=2" and "item=2" in fi("W1"), (angle(out, "W1"), fi("W1")))
check("kept in a new design", angle(out, "W2") == "WIREINFO angle=2" and "item=2" in fi("W2"), (angle(out, "W2"), fi("W2")))
check("the line's own choice is not changed by the wire's", angle(out, "L2") == "WIREINFO angle=0", angle(out, "L2"))
check("no wire tool, no angle", [l for l in out if l.startswith("WIREINFO")][-1] == "WIREINFO angle=-1")
# what it does to a line being drawn: at 45 degrees a segment drawn near the diagonal is made exactly diagonal (as wide as it is high)
def seg(tool, choose, name):
    run(["newdoc A4", "registerframe x all", "ribbontab Draw", "tool " + tool] + (["frameact tool cbAngle choose %d" % choose] if choose is not None else []) +
        ["mouse move 130 90", "mouse down 130 90", "mouse up 130 90", "mouse move 170 115", "mouse down 170 115", "mouse up 170 115", "mouse rdown 170 115", "tool select", "shot " + fp(name)])
def box(n, base):
    a = np.array(Image.open(fp(n)).convert("RGB")).astype(int); b = np.array(Image.open(fp(base)).convert("RGB")).astype(int)
    ys, xs = np.nonzero(np.abs(a - b).sum(axis=2) > 150)
    return (xs.max() - xs.min() + 1, ys.max() - ys.min() + 1) if len(xs) else (0, 0)
run(["newdoc A4", "shot " + fp("empty.bmp")])
seg("line", 0, "free.bmp"); seg("line", 2, "d45.bmp")
wf, hf = box("free.bmp", "empty.bmp"); w45, h45 = box("d45.bmp", "empty.bmp")
check("a free line keeps the slope it was drawn with (%dx%d)" % (wf, hf), hf > 0 and wf > 1.4 * hf, (wf, hf))
check("a 45 degree line is as wide as it is high (%dx%d)" % (w45, h45), h45 > 0 and abs(w45 - h45) <= max(3, 0.1 * w45), (w45, h45))
print("wire angle checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
