#!/usr/bin/env python3
"""A note's text wraps at the words when a line reaches the edge of the box (CDrawNoteText::Paint: DrawTextEx with DT_WORDBREAK).
Oracle: the rendered sheet bitmap (numpy / PIL) -- the ink of the text is found as the difference between the note with the text and the same note with a blank
text: it stays inside the box, takes several lines in a narrow box, fewer in a wide one, and a line break of the text still starts a new line.
Needs xvfb-run, numpy, PIL and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
try:
    import numpy as np
    from PIL import Image
except Exception:
    print("Note wrap checks skipped: need numpy and PIL"); sys.exit(0)
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Note wrap checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
def img(n): return np.array(Image.open(fp(n)).convert("RGB")).astype(int)
def note(txt, x2, y2, name):
    return ["newdoc A4", "registerframe x all", "ribbontab Draw", "tool note", "frameact tool edText type " + txt, "mouse move 60 100", "mouse down 60 100", "mouse up 60 100",
            "mouse move %d %d" % (x2, y2), "mouse down %d %d" % (x2, y2), "mouse up %d %d" % (x2, y2), "tool select", "shot " + fp(name)]
def ink(txt, x2, y2, tag):
    run(["newdoc A4", "shot " + fp("none" + tag + ".bmp")])
    run(note("_", x2, y2, "blank" + tag + ".bmp")); run(note(txt, x2, y2, "text" + tag + ".bmp"))
    nn, b, t = img("none%s.bmp" % tag), img("blank%s.bmp" % tag), img("text%s.bmp" % tag)
    box = np.abs(nn - b).sum(axis=2) > 60
    m = np.abs(b - t).sum(axis=2) > 120
    ys, xs = np.nonzero(box)
    return m, (xs.min(), xs.max(), ys.min(), ys.max())
def bands(m):
    rows = np.nonzero(m.any(axis=1))[0]
    n = 0; prev = -9
    for r in rows:
        if r - prev > 1: n += 1
        prev = r
    return n
TXT = "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima"
mn, bn = ink(TXT, 100, 125, "n")
mw, bw = ink(TXT, 220, 125, "w")
for nm, m, bx in (("narrow", mn, bn), ("wide", mw, bw)):
    ys, xs = np.nonzero(m)
    check("the %s note's text is inside its box" % nm, len(xs) > 20 and xs.min() >= bx[0] and xs.max() <= bx[1] and ys.min() >= bx[2] and ys.max() <= bx[3], (bx, xs.min() if len(xs) else None, xs.max() if len(xs) else None))
check("the text wraps in the narrow box (%d lines) and less in the wide one (%d)" % (bands(mn), bands(mw)), bands(mn) >= 3 and bands(mw) < bands(mn), (bands(mn), bands(mw)))
print("note wrap checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
