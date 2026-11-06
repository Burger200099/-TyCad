"""View > Show Mouse Position Bars: with the option on and the pointer over the view, a 1 pixel vertical and horizontal grey (128,128,128) line is drawn across the whole view
through the pointer; off, no such line; the bars follow the pointer. Oracle: screenshots (a column and a row of that colour spanning the view), VIEWOPT output. Needs xvfb-run,
PIL and the built program."""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
try:
    from PIL import Image
except ImportError:
    Image = None
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or Image is None:
    print("Mouse bars checks skipped: need xvfb-run, PIL and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:300])
def run(script):
    p = os.path.join(tmp, "s.txt"); open(p, "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", p], capture_output=True, text=True, timeout=300,
                       env=dict(os.environ, HOME=tempfile.mkdtemp(dir=tmp), FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.splitlines()
G = (128, 128, 128)
def lines(path):
    im = Image.open(path).convert("RGB"); W, H = im.size; px = im.load()
    cols = [x for x in range(W) if sum(px[x, y] == G for y in range(H)) > H * 0.9]
    rows = [y for y in range(H) if sum(px[x, y] == G for x in range(W)) > W * 0.9]
    return cols, rows
def shot(opt, move, name):
    f = os.path.join(tmp, name + ".png")
    out = run("newdoc A4\nviewopt mousebars %s\nmouse move %s\nshot \"%s\"\n" % (opt, move, f))
    return f, out
f, out = shot("off", "100 80", "off")
b0, b1 = lines(f)    # (grey parts of the window itself, such as a splitter, are the same with the option off)
def lines2(path):
    c, r = lines(path); return [x for x in c if x not in b0], [y for y in r if y not in b1]
check("off: no bars", len(b1) == 0 and len(b0) <= 3, (b0, b1))
f, out = shot("on", "100 80", "on1")
c1, r1 = lines2(f)
check("on: one column and one row across the view", len(c1) == 1 and len(r1) == 1, (c1, r1))
check("VIEWOPT reports mousebars=1", any("mousebars=1" in l for l in out), out[-3:])
f, out = shot("on", "160 120", "on2")
c2, r2 = lines2(f)
check("the bars follow the pointer", len(c2) == 1 and len(r2) == 1 and c2[0] > c1[0] and r2[0] > r1[0], (c1, r1, c2, r2))
print("mouse bars: %d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
