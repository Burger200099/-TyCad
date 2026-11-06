"""Arrow tool (Draw > Shapes, Insert > Shapes > Arrow): click the tail, then the point; the arrow is a line with a head at B, saved as <ARROW a= b= style=>. Oracle: saved XML,
a screenshot (barbs of the head beside the shaft, only at the B end), Shift makes it level/plumb, one undo removes it, the arrow survives save and open. Needs xvfb-run, PIL and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
try:
    from PIL import Image
except ImportError:
    Image = None
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or Image is None:
    print("Arrow tool checks skipped: need xvfb-run, PIL and the built program"); sys.exit(0)
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
def xml(path):
    t = open(path, encoding="utf-8").read(); m = re.search(r"<ARROW [^>]*>", t); return m.group(0) if m else ""
def pt(x, k):
    m = re.search(r" %s='([^']*)'" % k, x); return [float(v) for v in m.group(1).split(",")] if m else None
mk = "newdoc A4\ngridmm 2\ntool arrow\nmouse down 100 100\nmouse move 140 100\nmouse up 140 100\n"
f = os.path.join(tmp, "a.dsn"); s = os.path.join(tmp, "a.png")
run(mk + 'shot "%s"\nsave "%s"\n' % (s, f))
x = xml(f)
check("saved as ARROW with the two points", pt(x, "a") == [100.0, 100.0] and pt(x, "b") == [140.0, 100.0], x)
im = Image.open(s).convert("RGB"); W, H = im.size; px = im.load(); O = (255, 128, 0)   # (the new arrow is chosen: drawn in the selection colour)
rows = {y: [xx for xx in range(W) if px[xx, y] == O] for y in range(H)}
line = max(rows, key=lambda y: len(rows[y])); xs = rows[line]; xa, xb = min(xs), max(xs)
k = (xb - xa) / 40.0
near_b = sum(1 for y in range(H) if 1 <= abs(y - line) <= 6 for xx in rows[y] if xb - 6 <= xx <= xb)
near_a = sum(1 for y in range(H) if 1 <= abs(y - line) <= 6 for xx in rows[y] if xa <= xx <= xa + 6)
check("head barbs beside the shaft at B", near_b >= 4, near_b)
check("no head at A", near_a == 0, near_a)
f2 = os.path.join(tmp, "b.dsn")
run("newdoc A4\ngridmm 2\nmeasure shift on\ntool arrow\nmouse down 100 100\nmouse move 140 108\nmouse up 140 108\nsave \"%s\"\n" % f2)
x2 = xml(f2)
check("Shift: level about the tail", pt(x2, "a") and pt(x2, "b") and abs(pt(x2, "a")[1] - pt(x2, "b")[1]) < 1e-6, x2)
f3 = os.path.join(tmp, "c.dsn")
run(mk + "undo\nsave \"%s\"\n" % f3)
check("one undo removes the arrow", xml(f3) == "", xml(f3))
f4 = os.path.join(tmp, "d.dsn"); s4 = os.path.join(tmp, "d.png")
run('open "%s"\nsave "%s"\n' % (f, f4))
check("the arrow survives open and save", xml(f4) != "" and pt(xml(f4), "b") == [140.0, 100.0], xml(f4))
print("arrow tool: %d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
