"""Paste to Grid (Ctrl+Shift+V): the pasted block is moved so that its corner (the largest x and y of its objects) is on a grid point and the objects keep their spacing; plain Paste
keeps the block's own offset from the grid. It is available only while Snap to Grid is on. Oracles: the saved design read as XML (the rectangles' corner points; the grid is 2 mm =
10 design units, so a point is on the grid when it is a multiple of 10), PASTETOGRID enabled= (the menu item). Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Paste to grid checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
    return [tuple(float(v) for v in re.findall(r"[-\d.]+", m)) for m in re.findall(r"<RECT[^>]*? a='([^']*)' b='([^']*)'", t) and [" ".join(x) for x in re.findall(r"<RECT[^>]*? a='([^']*)' b='([^']*)'", t)]]
mk = "newdoc A4\ngridmm 2\nsnap off\ntool rect\nmouse down 101 63\nmouse move 143 95\nmouse up 143 95\ntool rect\nmouse down 101 123\nmouse move 143 155\nmouse up 143 155\nselectall\ncopy\nsnap on\n"
f1, f2 = os.path.join(tmp, "grid.dsn"), os.path.join(tmp, "plain.dsn")
o = run(mk + f'pastetogrid\nmouse move 400 300\nmouse down 400 300\nmouse up 400 300\nsave "{f1}"\n')
check("the item is enabled while snap is on", any("PASTETOGRID enabled=1" in l for l in o), o[-4:])
o = run("newdoc A4\nsnap off\nsnap on\nsnap off\npastetogrid\n")
check("the item is disabled while snap is off", any("PASTETOGRID enabled=0" in l for l in o), o[-3:])
R = rects(f1)
new = R[2:]
check("two rectangles were pasted", len(R) == 4, R)
if len(R) == 4:
    mx = max(max(r[0], r[2]) for r in new); my = max(max(r[1], r[3]) for r in new)
    check("the corner of the pasted block is on the grid (multiple of 10)", abs(mx / 10 - round(mx / 10)) < 1e-6 and abs(my / 10 - round(my / 10)) < 1e-6, (mx, my))
    check("the spacing between the pasted rectangles is that of the originals", abs((new[1][1] - new[0][1]) - (R[1][1] - R[0][1])) < 1e-3, (new, R[:2]))
o = run(mk + f'paste\nmouse move 400 300\nmouse down 400 300\nmouse up 400 300\nsave "{f2}"\n')
R2 = rects(f2)
if len(R2) == 4:
    new2 = R2[2:]
    check("plain Paste keeps the block's offset: its rectangle points are not all on the grid", any(abs(v / 10 - round(v / 10)) > 1e-3 for r in new2 for v in r), new2)
print("Paste to grid checks: %d run, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
