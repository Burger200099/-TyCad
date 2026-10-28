"""View menu mirrors of ribbon tools: Snap to Grid, Show Rulers, Show Detailed Block and the Grid Size submenu.
Checked against independent state: the ribbon button, the position-bar button and the menu tick must always agree
(whichever of them was used); the submenu is a one-for-one copy of the grid-size popup, ticks the size in use, and
choosing an item changes the grid (position bar text, in tenths of a millimetre).
Needs the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("View menu checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n); print("  FAIL", n, str(d)[:300])
def run(script):
    h = tempfile.mkdtemp(dir=tmp); path = os.path.join(tmp, "s.txt"); open(path, "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=150, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n")
def info(lines):
    out = []
    for l in lines:
        m = re.match(r"VIEWMENUINFO snap=(\d)(\d)(\d) rulers=(\d)(\d) ext=(\d)(\d) grid=(\d+) checked=(-?\d+) captions=(.*)$", l)
        if m: out.append(m)
    return out
psu = next(os.path.join(dp, f) for dp, _, fs in os.walk(EX) for f in fs if f == "PSU.dsn")
w = os.path.join(tmp, "PSU.dsn"); shutil.copy(psu, w)
L = run(f"open {w}\nviewmenuinfo\nmenuclick miGridSnap\nviewmenuinfo\nmenuclick miGridSnap\nviewmenuinfo\n"
        "menuclick miShowRulers\nviewmenuinfo\nmenuclick miShowRulers\nviewmenuinfo\n"
        "menuclick miExtendedInfo\nviewmenuinfo\nmenuclick miExtendedInfo\nviewmenuinfo\n"
        "gridmenuclick 0\nviewmenuinfo\npositioninfo\ngridmenuclick 3\nviewmenuinfo\npositioninfo\n")
I = info(L)
check("ran", len(I) == 9, L[-6:])
if len(I) == 9:
    for k, m in enumerate(I):
        check(f"snap agrees {k}", len(set(m.group(1, 2, 3))) == 1, m.group(0))
        check(f"rulers agree {k}", m.group(4) == m.group(5), m.group(0))
        check(f"ext agrees {k}", m.group(6) == m.group(7), m.group(0))
    s0 = I[0].group(1)
    check("snap toggles", I[1].group(3) != s0 and I[2].group(3) == s0, [m.group(0) for m in I[:3]])
    r0 = I[2].group(4)
    check("rulers toggle", I[3].group(5) != r0 and I[4].group(5) == r0, [m.group(0) for m in I[2:5]])
    e0 = I[4].group(6)
    check("ext toggles", I[5].group(7) != e0 and I[6].group(7) == e0, [m.group(0) for m in I[4:7]])
    caps = I[0].group(10).split("|")
    check("submenu copies popup (sizes + sep + custom)", int(I[0].group(8)) == len(caps) and caps[-1].startswith("Custom") and caps[-2] == "-", caps)
    n_sizes = len(caps) - 2
    check("one tick, on a size", int(I[0].group(9)) in range(n_sizes), I[0].group(0))
    check("click item 0 ticks it", I[7].group(9) == "0", I[7].group(0))
    check("click item 3 ticks it", I[8].group(9) == "3", I[8].group(0))
    g = [re.search(r"grid=(\S+)", l).group(1) for l in L if l.startswith("POSITIONINFO ")]
    check("grid follows the item (tenths of mm)", len(g) == 2 and g[0] != g[1], g)
print("view menu: %d checks, %d failed" % (checks, len(fails))); sys.exit(1 if fails else 0)
