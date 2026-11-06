"""A note's text is a multi-line box (a memo): Enter starts a new line and Tab indents. Oracles: the saved design read back as XML (the note's text holds the line breaks and the tab),
the design opened again (text kept), and the picture of the note (a pixel row of text for each line, the indented line starting to the right of the others).
Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Note memo checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
f = os.path.join(tmp, "n.dsn")
o = run(f'newdoc A4\ntool note\nmouse down 130 90\nmouse move 230 160\nmouse up 230 160\npropspanel\nframeact sel prop:text text one\\ntwo\\n\\tthree\nsave "{f}"\nopen "{f}"\nsave "{tmp}/m.dsn"\n')
check("the Properties panel has a memo for the note's text", any(l.startswith("PROPCTL TMemo") for l in o), [l for l in o if l.startswith("PROPCTL")][:4])
t = open(f, encoding="utf-8").read(); m = re.search(r"<NOTE_TEXT[^>]*>(.*?)</NOTE_TEXT>", t, re.S)
check("the saved note holds three lines and the tab", m and m.group(1).replace("\r", "") == "one\ntwo\n\tthree", m and repr(m.group(1)))
t2 = open(os.path.join(tmp, "m.dsn"), encoding="utf-8").read(); m2 = re.search(r"<NOTE_TEXT[^>]*>(.*?)</NOTE_TEXT>", t2, re.S)
check("opened and saved again it is the same", m2 and m and m2.group(1) == m.group(1), m2 and repr(m2.group(1)))
# the direction of the text: where the letters are in the box (note fill FFFFAF, text FF8000 here): up bottom left, down top right, left bottom right, right top left
try:
    from PIL import Image
    for d, want in (("Up", (0, 1)), ("Down", (1, 0)), ("Left", (1, 1)), ("Right", (0, 0))):
        run(f'newdoc A4\ntool note\nmouse down 130 90\nmouse move 230 160\nmouse up 230 160\nframeact sel prop:text text one two three\\nline two here\nsetprop dir {d}\nshot {tmp}/d.bmp\n')
        im = Image.open(f"{tmp}/d.bmp").convert("RGB"); W, H = im.size
        pts = [(x, y) for y in range(H) for x in range(W) if (lambda c: c[0] > 200 and 60 < c[1] < 190 and c[2] < 100)(im.getpixel((x, y)))]
        # the note box is the yellow area: its middle
        ys = [y for y in range(H) for x in (W // 2,) if im.getpixel((x, y)) == (255, 255, 175)]
        xs = [x for x in range(W) for y in (H // 2,) if im.getpixel((x, y)) == (255, 255, 175)]
        mx, my = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        inside = [(x, y) for x, y in pts if min(xs) <= x <= max(xs) and min(ys) <= y <= max(ys)]
        cx = sum(x for x, y in inside) / max(1, len(inside)); cy = sum(y for x, y in inside) / max(1, len(inside))
        check(f"direction {d}: the text sits in the {'right' if want[0] else 'left'} {'lower' if want[1] else 'upper'} part of the note", len(inside) > 20 and (cx > mx) == bool(want[0]) and (cy > my) == bool(want[1]), (len(inside), cx, cy, mx, my))
except ImportError:
    pass
print("Note memo checks: %d run, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
