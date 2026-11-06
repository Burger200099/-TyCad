"""Options > Fonts: the default text font (font number 0: free text and wire labels). It is kept in the settings and given to designs made from then on; the design that
is open keeps its own. Oracles: the saved design read as XML (the FONT element with id 0: height, weight, italic, face), height = round(points * 96 / 72) negative (the
conversion TinyCAD's font dialog uses), a second run of the program for what is kept. Cases: the start (Arial 10 points, height -13); a font chosen applies to a design made
afterwards to the text and label tools (not font 0, the title block's) and to the next run; what cannot be used (size 3, 100, not a number, no name) is refused and changes nothing.
Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Text font checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:400])
def run(script, home):
    h = os.path.join(tmp, "home_" + home); os.makedirs(h, exist_ok=True)
    p = os.path.join(tmp, "s.txt"); open(p, "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", p], capture_output=True, text=True, timeout=300,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.splitlines()
def font0(path):
    """the font of the TEXT in the file (the file numbers the fonts it uses afresh): height, weight, italic, face"""
    t = open(path, encoding="utf-8").read()
    k = re.search(r"<TEXT [^>]*font='(\d+)'", t)
    if not k: return None
    m = re.search(r"<FONT id='%s'>\s*<HEIGHT>(-?\d+)</HEIGHT>.*?<WEIGHT>(\d+)</WEIGHT>\s*<ITALIC>(\d+)</ITALIC>.*?<FACENAME>(.*?)</FACENAME>" % k.group(1), t, re.S)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4)) if m else None
def title(o):
    """font number 0 of the first sheet, the one the title block is drawn in (OPTIONSINFO titlefont)"""
    l = [x for x in o if x.startswith("OPTIONSINFO titlefont sheet 0")]
    return l[0].split()[-1] if l else None
T = 'tool text\nmouse down 150 60\nsetprop text Hello\ntool select\n'      # some text, so that the font is in the file
w = os.path.join(tmp, "w"); os.makedirs(w)
run(f'newdoc A4\n{T}save "{w}/a.dsn"\n', "a")
check("a new design starts with Arial, height -13, upright", font0(f"{w}/a.dsn") == (-13, 400, 0, "Arial"), font0(f"{w}/a.dsn"))
o = run(f'newdoc A4\n{T}save "{w}/open.dsn"\noptions textfont=DejaVu_Serif textsize=12 textbold=1 textitalic=1\nsave "{w}/b.dsn"\nnewdoc A4\noptionsinfo\n{T}save "{w}/c.dsn"\n', "b")
check("the title block font (font 0) of a new design is not the default text font", title(o) == "Arial/10/0/0", title(o))
check("the open design keeps its own font", font0(f"{w}/b.dsn") == (-13, 400, 0, "Arial"), (font0(f"{w}/b.dsn"), o[-4:]))
f = font0(f"{w}/c.dsn")
check("a design made afterwards has it: 12 points is -16, bold, italic", f is not None and f[0] == -16 and f[1] == 700 and f[2] == 1 and f[3].startswith("DejaVu"), f)
run(f'newdoc A4\n{T}save "{w}/d.dsn"\n', "b")
f = font0(f"{w}/d.dsn")
check("the next run starts with it", f is not None and f[0] == -16 and f[1] == 700 and f[3].startswith("DejaVu"), f)
for what, args in (("a size of 3", "textsize=3"), ("a size of 100", "textsize=100"), ("a size that is not a number", "textsize=big"), ("no name", "textfont=")):
    run(f'options {args}\nnewdoc A4\n{T}save "{w}/e.dsn"\n', "e")
    check("refused: " + what + ", nothing changes", font0(f"{w}/e.dsn") == (-13, 400, 0, "Arial"), font0(f"{w}/e.dsn") if os.path.exists(f"{w}/e.dsn") else None)
    if os.path.exists(f"{w}/e.dsn"): os.remove(f"{w}/e.dsn")
print("Text font checks: %d, failed %d" % (n[0], len(fails)))
sys.exit(1 if fails else 0)
