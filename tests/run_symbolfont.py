"""Options > Fonts: the symbol font (TinyCAD's pin font, font number 1: the reference and the other fields of a symbol, and pin text).
Oracles: the saved design read as XML (the FONT element with id 1: height, weight, italic, face), the conversion TinyCAD's font dialog uses between points and LOGFONT units
restated here (height = round(points * 96 / 72), negative), the width of a symbol field as the program measures it (it follows the size: twice the points, about twice the width),
and a second run of the program for what is kept (registry) and what a new design starts with.
Cases: the start (Arial, 8 points, not bold, not italic, height -10); a font is chosen and applied to every sheet and to new designs and kept for the next run; choosing the
font it already has changes nothing (8 points stays height -10, not -11); what cannot be used (a size of 3 or 100, a size that is not a number, no name) is refused and
changes nothing; bold and italic; the field of a symbol is as wide as the size says. Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from designoracle import objects, sheet0
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
PSU = os.path.join(EX, "circuits", "PSU.dsn")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not os.path.exists(PSU):
    print("Symbol font checks skipped: need xvfb-run, the built program and the examples"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:500])
def run(script, home):
    h = os.path.join(tmp, "home_" + home); os.makedirs(h, exist_ok=True)
    p = os.path.join(tmp, "s.txt"); open(p, "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", p], capture_output=True, text=True, timeout=300,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.splitlines()
def font1(path):
    t = open(path, encoding="utf-8").read()
    m = re.search(r"<FONT id='1'>\s*<HEIGHT>(-?\d+)</HEIGHT>.*?<WEIGHT>(\d+)</WEIGHT>\s*<ITALIC>(\d+)</ITALIC>.*?<FACENAME>(.*?)</FACENAME>", t, re.S)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4)) if m else None
def sym(line):
    m = re.search(r"symbolfont (?:sheet \d+ )?(.*?)/(\d+)/(\d)/(\d)(?: height=(-?\d+))?", line); return m.groups() if m else None
def fh(points): return -int(points * 96 / 72 + 0.5)
work = os.path.join(tmp, "w"); os.makedirs(work)
psu = os.path.join(work, "PSU.dsn"); shutil.copy(PSU, psu)
k = next(i for i, e in enumerate(objects(sheet0(psu))) if e.tag == "SYMBOL")
# ---- the start
o = run(f'open "{psu}"\noptionsinfo\nsave "{work}/a.dsn"\n', "a")
l = [x for x in o if "OPTIONSINFO symbolfont now" in x][0]
check("starts as TinyCAD does: Arial 8 points, upright", "now=Arial/8/0/0" in l and "settings=Arial/8/0/0" in l, l)
check("the design's font 1 is what the file has (height -10, Arial)", any(sym(x) and sym(x)[4] == "-10" and sym(x)[0] == "Arial" for x in o if "symbolfont sheet" in x), o[-6:])
check("nothing changed in the saved font", font1(f"{work}/a.dsn") == (-10, 400, 0, "Arial"), font1(f"{work}/a.dsn"))
# ---- choosing the font it has changes nothing
o = run(f'open "{psu}"\noptions symfont=Arial symsize=8\noptionsinfo\nsave "{work}/b.dsn"\n', "b")
check("the same font again: height stays -10", font1(f"{work}/b.dsn") == (-10, 400, 0, "Arial"), font1(f"{work}/b.dsn"))
# ---- a font
o = run(f'open "{psu}"\noptions symfont="DejaVu Serif" symsize=12 symbold=1 symitalic=1\noptionsinfo\nsave "{work}/c.dsn"\n'.replace('"DejaVu Serif"', "DejaVu_Serif"), "c")
f = font1(f"{work}/c.dsn")
check("applied: 12 points is height -16, bold (700), italic, the face", f is not None and f[0] == fh(12) and f[1] == 700 and f[2] == 1 and f[3].startswith("DejaVu"), f)
l = [x for x in o if "OPTIONSINFO symbolfont now" in x][0]
check("the settings keep it", "settings=DejaVu" in l and "/12/1/1" in l, l)
# ---- kept for the next run, and a new design starts with it
o = run(f'optionsinfo\nnewdoc "ISO A4" landscape\noptionsinfo\n', "c")
ls = [x for x in o if "OPTIONSINFO symbolfont sheet 0" in x]
check("the next run starts with it, and a new design has it", ls and sym(ls[0])[0].startswith("DejaVu") and sym(ls[0])[1] == "12" and sym(ls[0])[4] == str(fh(12)), ls)
# ---- refused
for what, args in (("a size of 3", "symsize=3"), ("a size of 100", "symsize=100"), ("a size that is not a number", "symsize=big"), ("no name", "symfont=")):
    o = run(f'open "{psu}"\noptions {args}\noptionsinfo\nsave "{work}/d.dsn"\n', "d")
    check(f"{what} is refused and nothing changes", font1(f"{work}/d.dsn") == (-10, 400, 0, "Arial"), (args, font1(f"{work}/d.dsn")))
# ---- the field of a symbol follows the size
def width(points):
    o = run(f'open "{psu}"\noptions symsize={points}\nselidx {k}\nfieldinfo\n', "w%d" % points)
    return float([x for x in o if x.startswith("FIELD 0 ")][0].split()[5])
w8, w16 = width(8), width(16)
check("a field is about twice as wide at twice the size", 1.7 < w16 / w8 < 2.3, (w8, w16))
print(f"{n[0]} checks, {len(fails)} failed")
sys.exit(1 if fails else 0)
