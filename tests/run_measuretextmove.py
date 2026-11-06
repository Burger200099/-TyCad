"""Measure A-B ruler: with the ruler chosen, dragging its distance text moves the text only (TextOff, saved as toff=); moved more than 10 units (2 mm) an arrow is drawn
from the text centre to the ruler centre, stopping 20 units short of each; a small move draws no arrow; one undo takes the move back; the offset survives save and open.
Oracle: saved XML (MEASURE toff= a= b=), MEASURETEXTPOS output, screenshot pixels of the ruler colour in the column through the ruler's middle. Needs xvfb-run, PIL and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
try:
    from PIL import Image
except ImportError:
    Image = None
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or Image is None:
    print("Measure text move checks skipped: need xvfb-run, PIL and the built program"); sys.exit(0)
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
    t = open(path, encoding="utf-8").read()
    m = re.search(r"<MEASURE [^>]*>", t); return m.group(0) if m else ""
def attr(x, k):
    m = re.search(r" %s='([^']*)'" % k, x); return [float(v) for v in m.group(1).split(",")] if m else None
def pos(out):
    for l in out:
        if l.startswith("MEASURETEXTPOS"):
            return dict((k, float(v)) for k, v in re.findall(r"(\w+)=([-\d.]+)", l))
mk = "newdoc A4\ngridmm 2\ntool measure\nmouse down 100 100\nmouse move 140 100\nmouse up 140 100\ntool select\n"
out = run(mk + "shot \"%s\"\nmeasure text\n" % os.path.join(tmp, "p.png"))
p0 = pos(out)
check("text shown, not moved", p0 and p0["shown"] == 1 and p0["offx"] == 0 and p0["offy"] == 0, out[-4:])
cx, cy = p0["cx"], p0["cy"]
def drag(dx, dy, name, extra=""):
    f = os.path.join(tmp, name + ".dsn"); s = os.path.join(tmp, name + ".png")
    o = run(mk + "mouse down %s %s\nmouse move %s %s plain\nmouse up %s %s\n" % (cx, cy, cx + dx, cy + dy, cx + dx, cy + dy) + extra +
            'save "%s"\nshot "%s"\nmeasure text\n' % (f, s))
    return xml(f), s, pos(o)
x, s, p = drag(0, 15, "far")
check("far drag: offset saved (0,15), ends unchanged", attr(x, "toff") and abs(attr(x, "toff")[0]) < 1 and abs(attr(x, "toff")[1] - 15) < 0.8 and attr(x, "a") == [100.0, 100.0] and attr(x, "b") == [140.0, 100.0], x)
check("text centre follows the pointer", p and abs(p["cy"] - (cy + 15)) < 0.8, (p, cy))
def teal_col(path):
    im = Image.open(path).convert("RGB"); W, H = im.size; px = im.load()
    T = (255, 128, 0)    # (the chosen ruler is drawn in the selection colour)
    rows = {}
    for y in range(H):
        c = [x for x in range(W) if px[x, y] == T]
        if len(c) > 60: rows[y] = c       # the ruler line
    if not rows: return None
    y0 = min(rows); xs = rows[y0]; xa, xb = min(xs), max(xs); k = (xb - xa) / 40.0; xm = (xa + xb) // 2
    return sum(1 for y in range(int(y0 + 7 * k), int(y0 + 11 * k)) for dx in (-1, 0, 1) if px[xm + dx, y] == T)
a = teal_col(s)
check("far: an arrow is drawn between the text and the ruler", a and a > 8, a)
x2, s2, p2 = drag(0, 1.5, "near")
b = teal_col(s2)
check("small move (under 10 units): no arrow", b == 0, b)
x3, s3, p3 = drag(0, 15, "undo", "undo\n")
check("one undo takes the text move back", attr(x3, "toff") is None, x3)
f = os.path.join(tmp, "far.dsn")
o = run('open "%s"\nshot "%s"\nmeasure text\n' % (f, os.path.join(tmp, "r.png")))
p4 = pos(o)
check("offset survives save and open", p4 and abs(p4["offy"] - 15) < 0.8, (p4, o[-3:]))
print("Measure text move: %d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
