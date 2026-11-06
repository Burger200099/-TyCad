"""Holding Shift while resizing keeps the aspect ratio: one rectangle by a corner and by a side handle, and the whole selection (Resize All). Oracles: the saved XML (RECT points)
and the GRP box. Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Resize Shift checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:300])
def run(script):
    p = os.path.join(tmp, "s.txt"); open(p, "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", p], capture_output=True, text=True, timeout=300,
                       env=dict(os.environ, HOME=tmp, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.splitlines()
def rects(path):
    t = open(path, encoding="utf-8").read()
    return [tuple(float(v) for v in re.findall(r"[-\d.]+", a + " " + b)) for a, b in re.findall(r"<RECT[^>]*? a='([^']*)' b='([^']*)'", t)]
def ratio(r): return abs(r[3] - r[1]) / abs(r[2] - r[0])
mk = "newdoc A4\ngridmm 2\ntool rect\nmouse down 100 60\nmouse move 140 80\nmouse up 140 80\n"   # 40 x 20 mm: ratio 0.5
for name, h, mv in (("corner", "142 82", "180 82"), ("right side", "142 70", "180 70"), ("bottom side", "120 82", "120 110")):
    for shift in (True, False):
        f = os.path.join(tmp, "r.dsn")
        run(mk + f'tool select\nmouse down 120 60\nmouse up 120 60\nmouse down {h}\nmouse move {mv} {"shift" if shift else "plain"}\nmouse up {mv}\nsave "{f}"\n')
        R = rects(f)
        if len(R) != 1: check(name + " saved", False, R); continue
        r = ratio(R[0])
        grew = (R[0][2] - R[0][0]) > 45 or (R[0][3] - R[0][1]) > 25
        check("%s with Shift keeps the ratio (0.5), got %.3f" % (name, r) if shift else "%s without Shift changes the ratio" % name,
              (abs(r - 0.5) < 0.02 and grew) if shift else (abs(r - 0.5) > 0.05), R)
f = os.path.join(tmp, "g.dsn")
o = run(mk + "tool rect\nmouse down 100 120\nmouse move 120 130\nmouse up 120 130\nselectall\nctxmenu 110 125\nctxclick Resize_All\ngrp\nmouse down 142 132\nmouse move 200 150 shift\nmouse up 200 150\ngrp\n")
g = [l.split() for l in o if l.startswith("GRP on=1")]
if len(g) >= 2:
    w0, h0 = float(g[0][4]) - float(g[0][2]), float(g[0][5]) - float(g[0][3]); w1, h1 = float(g[1][4]) - float(g[1][2]), float(g[1][5]) - float(g[1][3])
    check("Resize All with Shift keeps the shape of the box", abs(w1 / h1 - w0 / h0) < 0.03 and w1 > w0 * 1.2, (g[0], g[1]))
else:
    check("Resize All box lines", False, o[-6:])
print("Resize Shift checks: %d run, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
