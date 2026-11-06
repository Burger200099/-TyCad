"""Holding Shift while a rectangle or circle is drawn makes it square (a circle round); without Shift, or once Shift is let go, it has the shape the pointer gave. Other tools are not
changed. Oracle: the saved XML (RECT / ELLIPSE-like points a= b=). Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Square shift checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
def box(path):
    t = open(path, encoding="utf-8").read()
    m = re.search(r"<(?:RECT|ELLIPSE|CIRCLE)[^>]*? a='([^']*)' b='([^']*)'", t)
    if not m: return None
    a = [float(v) for v in m.group(1).split(",")]; b = [float(v) for v in m.group(2).split(",")]
    return abs(b[0] - a[0]), abs(b[1] - a[1]), a, b
def draw(tool, shift, a, b, name):
    f = os.path.join(tmp, name + ".dsn")
    run(f"newdoc A4\ngridmm 2\nmeasure shift {'on' if shift else 'off'}\ntool {tool}\nmouse down {a[0]} {a[1]}\nmouse move {b[0]} {b[1]}\nmouse up {b[0]} {b[1]}\nsave \"{f}\"\n")
    return box(f)
for tool in ("rect", "circle"):
    r = draw(tool, False, (100, 60), (140, 80), tool + "0")
    check(tool + " without Shift keeps the pointer's shape (40 x 20)", r and abs(r[0] - 40) < 1 and abs(r[1] - 20) < 1, r)
    r = draw(tool, True, (100, 60), (140, 80), tool + "1")
    check(tool + " with Shift is square (40 x 40)", r and abs(r[0] - 40) < 1 and abs(r[1] - 40) < 1, r)
    r = draw(tool, True, (100, 60), (110, 100), tool + "2")
    check(tool + " with Shift uses the longer side when it is the vertical one", r and abs(r[0] - 40) < 1 and abs(r[1] - 40) < 1, r)
    r = draw(tool, True, (140, 100), (120, 90), tool + "3")
    check(tool + " with Shift towards the upper left keeps the direction", r and abs(r[0] - 20) < 1 and abs(r[1] - 20) < 1 and r[3][0] < 140 and r[3][1] < 100, r)
print("Square shift checks: %d run, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
