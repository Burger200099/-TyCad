#!/usr/bin/env python3
"""The main window and its two splitters (library panel width, symbol preview height) are kept in the registry when the program closes and applied when it opens.
Oracles: FitSavedWindow against the same rule written out again here (the title strip must overlap a work area by 100 pixels; size raised to the minimum and cut to the
work area), and real round trips through two program runs sharing one home (the registry file): what was set in run 1 is what run 2 finds and applies.
The test display forces the window to 1417 x 854 when a script starts, so the size is read from the settings that were loaded, the place and the splitters from the window."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Layout checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "h"); os.makedirs(home)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:400])
def run(script):
    open(os.path.join(tmp, "s.txt"), "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s.txt")], capture_output=True, text=True, timeout=90,
                       env=dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
def kv(line): return {k: int(v) for k, v in re.findall(r"(\w+)=(-?\d+)", line)}
def oracle(l, t, w, h, minw, minh, works):
    w = max(w, minw); h = max(h, minh); best = None; ba = 0
    for (a, b, c, d) in works:
        ix = min(l + w, c) - max(l, a); iy = min(t + 30, d) - max(t, b)
        if ix >= 100 and iy > 0 and ix * iy > ba: ba = ix * iy; best = (a, b, c, d)
    if best is None: return (0, (0, 0, w, h))
    return (1, (l, t, l + min(w, best[2] - best[0]), t + min(h, best[3] - best[1])))
# 1. the rule
cases = [(100, 80, 1300, 800, 800, 500, [(0, 0, 1600, 960)]),                     # on screen
         (5000, 5000, 1000, 700, 800, 500, [(0, 0, 1600, 960)]),                  # far off screen
         (-1200, 40, 1000, 700, 800, 500, [(0, 0, 1600, 960)]),                   # a monitor that is gone
         (-1200, 40, 1000, 700, 800, 500, [(-1920, 0, 0, 1040), (0, 0, 1600, 960)]),   # ... and there
         (1500, 100, 1000, 700, 800, 500, [(0, 0, 1600, 960)]),                   # only 100 pixels of the strip on screen
         (1501, 100, 1000, 700, 800, 500, [(0, 0, 1600, 960)]),                   # 99: out of reach
         (10, 10, 300, 200, 800, 500, [(0, 0, 1600, 960)]),                       # too small: raised
         (0, 0, 3000, 2000, 800, 500, [(0, 0, 1600, 960)]),                       # too large: cut
         (0, 970, 1000, 700, 800, 500, [(0, 0, 1600, 960)])]                      # the strip below the work area
script = "".join("fitwindow %d %d %d %d %d %d %s\n" % (c[0], c[1], c[2], c[3], c[4], c[5], " ".join("%d,%d,%d,%d" % w for w in c[6])) for c in cases)
o = [l for l in run(script) if l.startswith("FITWINDOW")]
for c, l in zip(cases, o):
    p = l.split(); got = (int(p[1][3:]), tuple(int(x) for x in p[2:6])); want = oracle(*c)
    check("FitSavedWindow %s" % (c,), got[0] == want[0] and (got[0] == 0 and got[1][2:] == want[1][2:] or got[1] == want[1]), (got, want))
check("every case answered", len(o) == len(cases), o)
# 2. a round trip
o = run("newdoc A4\nlayoutset 120 90 1300 800 260 120\nclosequery\n")
o = run("newdoc A4\nlayoutinfo\n")
lay = kv([l for l in o if l.startswith("LAYOUT")][0]); sv = kv([l for l in o if l.startswith("SAVED")][0])
check("the splitters come back where they were (panel 260, preview 120)", lay["leftw"] == 260 and lay["previewh"] == 120, lay)
check("the window's place comes back (120, 90)", (lay["left"], lay["top"]) == (120, 90), lay)
check("the kept size is 1300 x 800, not maximized", (sv["width"], sv["height"], sv["max"]) == (1300, 800, 0), sv)
# 3. other values are not mixed up
o = run("newdoc A4\nlayoutset 300 200 1100 700 180 90\nclosequery\n")
o = run("newdoc A4\nlayoutinfo\n")
lay = kv([l for l in o if l.startswith("LAYOUT")][0]); sv = kv([l for l in o if l.startswith("SAVED")][0])
check("a second set of values: splitters 180 / 90, place 300 / 200, size 1100 x 700", (lay["leftw"], lay["previewh"], lay["left"], lay["top"], sv["width"], sv["height"]) == (180, 90, 300, 200, 1100, 700), (lay, sv))
# 4. a window left out of reach is brought back
o = run("newdoc A4\nlayoutset 6000 6000 1000 700 200 100\nclosequery\n")
o = run("newdoc A4\nlayoutinfo\n")
lay = kv([l for l in o if l.startswith("LAYOUT")][0])
check("a window saved far off screen comes back on screen", 0 <= lay["left"] < 1500 and 0 <= lay["top"] < 900, lay)
# 5. splitters are kept to a sensible range
o = run("newdoc A4\nlayoutset 100 100 1300 800 1200 700\nclosequery\n")
o = run("newdoc A4\nlayoutinfo\n")
lay = kv([l for l in o if l.startswith("LAYOUT")][0])
check("a library panel saved wider than the window allows is cut (1300 wide: at most 1000 minus the border)", lay["leftw"] <= 1000 and lay["leftw"] >= 100, lay)
print("Layout checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
