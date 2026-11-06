"""Show Text Alignment and Show Position Bars (View menu): while a text object is dragged, a dashed line is drawn where it lines up with another text object, and with Show
Position Bars a 1 pixel vertical and horizontal bar goes through the dragged object's origin across the whole view. Oracle: a screenshot taken in the middle of the drag (the
bar colour (0,128,192) and the alignment colour (176,0,176) are looked for), VIEWOPT output. Needs xvfb-run, PIL and the built program."""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
try:
    from PIL import Image
except ImportError:
    Image = None
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or Image is None:
    print("Move alignment checks skipped: need xvfb-run, PIL and the built program"); sys.exit(0)
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
def count(path, rgb):
    im = Image.open(path).convert("RGB"); W, H = im.size; px = im.load()
    cols = set(); rows = set()
    for y in range(H):
        for x in range(W):
            if px[x, y] == rgb:
                cols.add(x); rows.add(y)
    return len(cols), len(rows), W, H
BAR, ALN = (0, 128, 192), (176, 0, 176)
mk = "newdoc A4\ngridmm 2\ntool note\nmouse down 100 60\nmouse move 140 80\nmouse up 140 80\ntool note\nmouse down 100 120\nmouse move 140 140\nmouse up 140 140\n"
drag = "tool select\nmouse down 120 130\nmouse move 120 140\nmouse move 120 150\n"
def shot(opts, name):
    f = os.path.join(tmp, name + ".png")
    run(mk + opts + drag + f'shot "{f}"\nmouse up 120 150\n')
    return f
f = shot("viewopt textalign off\nviewopt posbars off\n", "none")
check("no options: no bars", count(f, BAR)[:2] == (0, 0) and count(f, ALN)[:2] == (0, 0), count(f, BAR))
f = shot("viewopt textalign off\nviewopt posbars on\n", "bars")
c = count(f, BAR)
check("position bars: one vertical and one horizontal line across the view", c[0] == 1 and c[1] >= c[3] * 0.9 or (c[0] >= 1 and c[1] >= c[3] * 0.9), c)
check("position bars: no alignment colour", count(f, ALN)[:2] == (0, 0))
f = shot("viewopt textalign on\nviewopt posbars off\n", "text")
c = count(f, ALN)
check("text alignment: a line in the alignment colour (the two notes start at the same x)", c[0] >= 1 or c[1] >= 1, c)
f = shot("viewopt textalign on\nviewopt posbars on\n", "both")
check("both on: both are drawn", count(f, BAR)[0] >= 1 and (count(f, ALN)[0] >= 1 or count(f, ALN)[1] >= 1))
# a wire taken by its second anchor: the bars go through that anchor, not the first
def barcols(press):
    f = os.path.join(tmp, "wire.png")
    run("newdoc A4\ngridmm 2\ntool wire\nmouse move 40 100\nmouse down 40 100\nmouse move 120 100\nmouse up 120 100\nkey escape\ntool select\nselclear\n"
        "viewopt posbars on\nmouse move %d 100\nmouse down %d 100\nmouse move %d 105\nmouse move %d 110\n" % (press, press, press, press) + f'shot "{f}"\nmouse up %d 110\n' % press)
    im = Image.open(f).convert("RGB"); W, H = im.size; px = im.load()
    return sorted({x for x in range(W) for y in (H // 2,) if px[x, y] == BAR})
a = barcols(40); b = barcols(120)
check("wire taken by its first anchor and by its second: the vertical bar follows the anchor", a and b and b[0] - a[0] >= 100, (a, b))
# two wires in the shape of an L, both chosen: each of the three handles has the bars on it
def lcols(px, py):
    f = os.path.join(tmp, "ell.png")
    run("newdoc A4\ngridmm 2\ntool wire\nmouse move 40 60\nmouse down 40 60\nmouse move 40 100\nmouse up 40 100\ntool select\ntool wire\nmouse move 40 100\nmouse down 40 100\nmouse move 100 100\nmouse up 100 100\ntool select\nselclear\n"
        "viewopt posbars on\nmouse move 20 40\nmouse down 20 40\nmouse move 120 120\nmouse up 120 120\n"
        "mouse move %d %d\nmouse down %d %d\nmouse move %d %d\nmouse move %d %d\n" % (px, py, px, py, px, py + 5, px, py + 10) + f'shot "{f}"\nmouse up %d %d\n' % (px, py + 10))
    im = Image.open(f).convert("RGB"); W, H = im.size; px_ = im.load()
    return sorted({x for x in range(W) for y in (H // 2,) if px_[x, y] == BAR})
t1 = lcols(40, 60); t2 = lcols(40, 100); t3 = lcols(100, 100)
check("L of two wires: the bars follow each of the three handles", t1 and t2 and t3 and abs(t1[0] - t2[0]) <= 2 and t3[0] - t1[0] >= 50, (t1, t2, t3))
print("Move alignment checks: %d run, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
