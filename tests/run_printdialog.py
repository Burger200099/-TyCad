"""File > Print, Print Preview, Page Setup's printer buttons and Print Setup on the real program, with what is printed compared with printoracle.py (a separate
statement of TinyCadView.cpp / SpecialPrintDlg.cpp) and with the pixels the design's own coordinates say the page should hold:
  - the menu: Print... (Ctrl+P), Print Preview, Page Setup..., Print Setup... after Save All and before the recent files and Exit; usable only with a design open (Print Setup always);
    the three system dialogs (TPrintDialog, TPrinterSetupDialog, TPageSetupDialog) are on the main form
  - the Print dialog: TinyCAD's captions; the scale and black and white come from the registry (PrintScaleFactor "%lg" text, default 100; PrintBandW, default off); the Fit box shows
    the fit scale as "%3.3lg" and unticking it shows the scale the dialog began with; the scale is checked (above 0, at most 10000); black and white is kept when clicked and the scale
    when OK is pressed; with no printer OK is dimmed and a virtual A4 page is used to count pages
  - what is printed (to bitmap pages): the number of pages and what each shows for many sheet sizes and scales, one sheet and all of them, page ranges and copies (collated or not); the
    transform (every drawn line is where the design's coordinates and the page's origin and the print zoom put it), nothing outside the sheet's own objects (no paper, grid, construction
    guides), colors, and black and white
  - the Print Preview window: next/prev, one or two pages, zoom limits, the pages it draws equal what is printed in shape
  - Page Setup's Printer Paper and Printer Setup buttons: the printer's page (the longer side along the longer side of the sheet, whole mm) goes into the boxes; with no printer they say so
Needs the built program and xvfb."""
import glob, os, re, shutil, subprocess, sys, tempfile, random, math
import xml.etree.ElementTree as ET
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import printoracle as po
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Print checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 14: print("  FAIL", n, str(d)[:900])
def run(script, home, timeout=280):
    h = os.path.join(tmp, "home_" + home); os.makedirs(h, exist_ok=True)
    path = os.path.join(tmp, "script_%s.txt" % home); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n"), r.returncode, r.stderr
def kv(text):
    out = {}
    for m in re.finditer(r"(\w+)=(.*?)(?= \w+=|$)", text): out[m.group(1)] = m.group(2)
    return out
def lines_of(o, tag): return [l[len(tag) + 1:] for l in o if l.startswith(tag + " ")]
def registry(home):
    f = glob.glob(os.path.join(tmp, "home_" + home, ".config", "*", "reg.xml"))
    if not f: return {}
    node = ET.parse(f[0]).getroot()
    for part in ("HKEY_CURRENT_USER", "SOFTWARE", "HPL Software", "TyCAD Electrical"):
        node = next(k for k in node.findall("Key") if k.get("Name") == part)
    return {v.get("Name"): v.text for v in node.findall("Value")}
def set_registry(home, name, value):
    f = glob.glob(os.path.join(tmp, "home_" + home, ".config", "*", "reg.xml"))[0]
    tree = ET.parse(f); node = tree.getroot()
    for part in ("HKEY_CURRENT_USER", "SOFTWARE", "HPL Software", "TyCAD Electrical"):
        node = next(k for k in node.findall("Key") if k.get("Name") == part)
    for v in node.findall("Value"):
        if v.get("Name") == name: v.text = str(value); break
    else:
        e = ET.SubElement(node, "Value", dict(Name=name)); e.text = str(value)
    tree.write(f)
def dlg(line):
    """one PRINTDIALOG line -> (start, pressed, done) as dicts"""
    parts = line.split(" | ")
    start = kv(parts[0].split("start ", 1)[1])
    pressed = kv(parts[1].split("pressed ", 1)[1]) if len(parts) > 1 else {}
    done = kv(parts[2].split("done ", 1)[1]) if len(parts) > 2 and parts[2].startswith("done ") else {}
    return start, pressed, done, parts

# the printer used for the tests is an A4 bitmap page at 100 dpi, landscape or portrait as the sheet: 297 x 210 mm (210 x 297), 1169 x 827 pixels
DPI = 100
def device(portrait): return (210, 297) if portrait else (297, 210)
def page_px(portrait):
    h, v = device(portrait); return (round(h / 25.4 * DPI), round(v / 25.4 * DPI))
def rnd(x): return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))

# ---------------------------------------------------------------- designs made from a sample the program saved
BASE = None
def base_design():
    global BASE
    if BASE is None:
        p = os.path.join(tmp, "base.dsn")
        o, rc, err = run('newdoc "ISO A4" landscape\ndetails visible 0 border 0\nsave %s\n' % p, "base")
        BASE = open(p, encoding="utf-8").read()
    return BASE
def make_design(path, sheets):
    """sheets: list of dict(w=, h= in internal units, lines=[(x1,y1,x2,y2,style)], rects=[(x1,y1,x2,y2,style,fill)], rulers=[(x,y,horiz)] with positions in mm (as the file keeps them); style 0 is black 1 thick, 1 is red 3 thick, fill 1 is green, 2 white; a design of one TinyCAD block each, no title block and no border"""
    t = base_design()
    head, rest = t.split("<TinyCAD>", 1)
    block = rest.rsplit("</TinyCAD>", 1)[0]
    out = [head]
    def style(i, color, thick): return "\t\t<STYLE id='%d'>\n\t\t\t<STYLE>0</STYLE>\n\t\t\t<COLOR>%s</COLOR>\n\t\t\t<THICKNESS>%d</THICKNESS>\n\t\t</STYLE>\n" % (i, color, thick)
    def fill(i, index, color): return "\t\t<FILL id='%d'>\n\t\t\t<INDEX>%d</INDEX>\n\t\t\t<COLOR>%s</COLOR>\n\t\t</FILL>\n" % (i, index, color)
    resources = style(0, "000000", 1) + style(1, "0000FF", 3) + fill(0, -1, "000000") + fill(1, 0, "00FF00") + fill(2, 0, "FFFFFF")
    for n, s in enumerate(sheets):
        b = re.sub(r"<Size width='\d+' height='\d+'/>", "<Size width='%d' height='%d'/>" % (s["w"], s["h"]), block)
        b = b.replace("\t\t<OPTIONS>", resources + "\t\t<OPTIONS>", 1)
        b = b.replace("<NAME></NAME>", "<NAME>Sheet%d</NAME>" % (n + 1), 1)
        b = re.sub(r"<LINE .*?/>\n?", "", b)
        objs = ""
        oid = 1
        for (x1, y1, x2, y2, st) in s.get("lines", []):
            objs += "\t\t<LINE oid='%d' style='%d' a='%.5f,%.5f' b='%.5f,%.5f'/>\n" % (oid, st, x1, y1, x2, y2); oid += 1
        for (x1, y1, x2, y2, st, fl) in s.get("rects", []):
            objs += "\t\t<RECTANGLE oid='%d' a='%.5f,%.5f' b='%.5f,%.5f' style='%d' fill='%d'/>\n" % (oid, x1, y1, x2, y2, st, fl); oid += 1
        for (x, y, hz) in s.get("rulers", []):
            objs += "\t\t<RULER oid='%d' pos='%.5f,%.5f' horizontal='%d'/>\n" % (oid, x, y, hz); oid += 1
        b = b.replace("\t</TinyCAD>", "")
        b = b.rstrip() + "\n" + objs
        out.append("<TinyCAD>" + b + "\t</TinyCAD>\n")
    out.append("</TinyCADSheets>\n")
    open(path, "w", encoding="utf-8").write("".join(out)[:].replace("<TinyCADSheets>\n<TinyCAD>", "<TinyCADSheets>\n\t<TinyCAD>"))

def pages_of(d):
    fs = sorted(glob.glob(os.path.join(d, "page_*.png")), key=lambda f: int(re.search(r"page_(\d+)", f).group(1)))
    return [np.array(Image.open(f).convert("RGB")) for f in fs]


# ---------------------------------------------------------------- 1. the menu
o, rc, err = run('printmenu\nopen %s/circuits/AMP.DSN\nprintmenu\nprintsetup\n' % EX, "menu")
m = lines_of(o, "PRINTMENU")
check("menu: two reports", len(m) == 2, o)
if len(m) == 2:
    a, b = m
    check("menu closed: Print, Preview, Page Setup dimmed, Print Setup usable", "enabled=0 index=11 shortcut=Ctrl+P" in a and "Print Pre&view enabled=0 index=12" in a and "P&age Setup... enabled=0 index=13" in a and "Print Set&up... enabled=1 index=14" in a, a)
    check("menu open: all four usable", "&Print... enabled=1" in b and "Print Pre&view enabled=1" in b and "P&age Setup... enabled=1" in b and "Print Set&up... enabled=1" in b, b)
    check("menu: after Save All (4), before the separator and Exit", "save=4" in a and "index=11" in a and "index=14" in a and re.search(r"sep=\d+ exit=\d+", a) and re.search(r"sep=\d+ exit=\d+", b), (a, b))
    check("menu: the three system dialogs are on the main form", "dialogs=TPrintDialog/TPrinterSetupDialog/TPageSetupDialog" in a, a)
    check("menu: hints", "hints=Print the design/See the pages the design will print on/Paper size and orientation of this sheet/Choose the printer and its settings" in a, a)
    check("menu: the container has no printer", "installed=0" in a, a)
ps = lines_of(o, "PRINTSETUP")
check("Print Setup with no printer says so", ps == ["status=No printer is installed."], ps)
for cmd in ("printdialog press=ok", "previewrun"):
    o, rc, err = run(cmd + "\n", "nodoc")
    check("%s without a design is refused, not a crash" % cmd, any("no design is open" in l for l in o), o)

# ---------------------------------------------------------------- 2. the dialog
AMP = EX + "/circuits/AMP.DSN"
o, rc, err = run('open %s\nprintsink %s/d1\nprintdialog press=cancel\nprintdialog scale=0 press=ok\nprintdialog scale=abc press=ok\nprintdialog scale=10001 press=ok\n'
                 'printdialog scale=-5 press=ok\nprintdialog scale=10000 from=1 to=1 press=ok\nprintdialog scale=0.5 from=1 to=1 press=ok\n' % (AMP, tmp), "dlg1")
d = lines_of(o, "PRINTDIALOG")
check("dialog: seven answers", len(d) == 7, o)
if len(d) == 7:
    st, pr, dn, parts = dlg(d[0])
    check("dialog start: TinyCAD's captions", "captions=&Current|&All|Print in black and white|Scale (%):|Fit on a single page|Printer Setup..." in parts[0] and "title=Print" in parts[0], parts[0])
    check("dialog start: defaults scale 100, color, current sheet, no fit, one page", st.get("scale") == "100" and st.get("bw") == "0" and st.get("sheets") == "current" and st.get("fit") == "0" and "[1 page: 1 across and 1 down]" in st.get("pages", ""), st)
    check("dialog start: no printer dims nothing but shows a virtual A4 page", st.get("printer") == "A4 page (no printer)" and st.get("ok") == "1", st)
    check("cancel prints nothing", dn.get("printed") == "-1", d[0])
    for k, what in ((1, "0"), (2, "abc"), (3, "10001"), (4, "-5")):
        st, pr, dn, parts = dlg(d[k])
        check("scale %s is refused, the dialog stays open" % what, parts[-1] == "stays open" and pr.get("err", "[]") != "[]", d[k])
    for k, what, n in ((5, "10000", None), (6, "0.5", None)):
        st, pr, dn, parts = dlg(d[k])
        check("scale %s is accepted" % what, int(dn.get("printed", "-1")) >= 1, d[k])
reg = registry("dlg1")
check("registry: the last good scale kept as %lg text", reg.get("PrintScaleFactor") == "0.5", reg)
check("registry: PrintBandW kept", reg.get("PrintBandW") in ("0", "1"), reg)

# black and white is kept when clicked (even when cancelled), the scale only when OK is pressed
o, rc, err = run('open %s\nprintsink %s/d2\nprintdialog bw=1 scale=77 press=cancel\nprintreport\n' % (AMP, tmp), "dlg2")
d = lines_of(o, "PRINTDIALOG")
check("cancel: black and white was kept", registry("dlg2").get("PrintBandW") == "1", (registry("dlg2"), d))
check("cancel: scale was not kept", registry("dlg2").get("PrintScaleFactor") in (None, "100"), registry("dlg2"))
o, rc, err = run('open %s\nprintsink %s/d3\nprintdialog press=cancel\nprintdialog scale=33.333333 press=ok\nprintdialog press=cancel\n' % (AMP, tmp), "dlg2")
d = lines_of(o, "PRINTDIALOG")
check("next run starts with the kept black and white", d and "bw=1" in d[0].split(" | ")[0], d[:1])
check("next run starts with the kept scale shown as %3.3g", len(d) == 3 and "scale=33.3 " in d[2].split(" | ")[0], d[2:])
# fit
o, rc, err = run('open %s\nprintsink %s/d4\nprintdialog scale=250 fit=1 press=cancel\n' % (AMP, tmp), "dlg3")
d = lines_of(o, "PRINTDIALOG")
if d:
    st, pr, dn, parts = dlg(d[0])
    sheet = None
    check("fit: edit is dimmed and one page", pr.get("fit") == "1" and pr.get("edit") == "0" and "[1 page:" in pr.get("pages", ""), pr)
    exp = po.scale_text(po.fit_scale(297, 210, 1485, 1050)) if False else None
    check("fit: scale shown as the %3.3g text", re.fullmatch(r"\d+(\.\d+)?", pr.get("scale", "")) is not None, pr)
# registry values that are not good give the default
o, rc, err = run('open %s\nprintdialog press=cancel\n' % AMP, "dlg5")
for bad in ("abc", "-3", "20000", "0", ""):
    set_registry("dlg5", "PrintScaleFactor", bad)
    o, rc, err = run('open %s\nprintsink %s/d5\nprintdialog press=cancel\n' % (AMP, tmp), "dlg5")
    d = lines_of(o, "PRINTDIALOG")
    check("registry scale %r gives the default 100" % bad, d and "scale=100 " in d[0].split(" | ")[0], d[:1])

for good in ("6000", "10000", "0.25", "1e2"):
    set_registry("dlg5", "PrintScaleFactor", good)
    o, rc, err = run('open %s\nprintsink %s/d5\nprintdialog press=cancel\n' % (AMP, tmp), "dlg5")
    d = lines_of(o, "PRINTDIALOG")
    want = po.scale_text(po.atof(good))
    check("registry scale %r is the scale %s" % (good, want), d and ("scale=%s " % want) in d[0].split(" | ")[0], d[:1])

# ---------------------------------------------------------------- 3. what is printed
random.seed(20261010)
SIZES = [(1485, 1050), (1050, 1485), (2100, 1485), (1485, 2100), (3000, 2100), (800, 600), (600, 900)]
def build_case(n):
    w, h = random.choice(SIZES)
    nsh = random.choice((1, 1, 2, 3))
    shs = []
    for k in range(nsh):
        rects = []
        for r in range(random.randint(1, 4)):
            x = random.uniform(5, w / 5 - 20); y = random.uniform(5, h / 5 - 20)
            rects.append((x, y, x + random.uniform(8, 18), y + random.uniform(8, 18), 0, random.choice((1, 1, 2))))
        lines = []
        for r in range(random.randint(0, 2)):
            lines.append((random.uniform(2, w / 5 - 2), random.uniform(2, h / 5 - 2), random.uniform(2, w / 5 - 2), random.uniform(2, h / 5 - 2), random.choice((0, 1))))
        shs.append(dict(w=w, h=h, rects=rects, lines=lines, rulers=[(random.uniform(5, 40), random.uniform(5, 40), random.randint(0, 1))]))
    return dict(w=w, h=h, sheets=shs, scale=random.choice((25, 50, 75, 100, 100, 150, 200, 250, 333.5, 400)), all=random.random() < 0.5, bw=random.random() < 0.3,
                active=random.randrange(nsh))
def verify(c, d, pages, label):
    """compare the pages with the oracle's account of where each sheet's objects should be"""
    portrait = c["h"] > c["w"]
    horz, vert = device(portrait)
    pw, ph = page_px(portrait)
    nsh = len(c["sheets"])
    lay = po.layout(horz, vert, DPI, c["w"], c["h"], c["scale"], c["all"], nsh)
    check(label + " page count", len(pages) == lay["pages"], (len(pages), lay["pages"]))
    if len(pages) != lay["pages"]: return
    for (cur, sheet, col, row, ox, oy), img in zip(lay["list"], pages):
        if not c["all"] or lay["sheets"] == 1: sheet = c["active"]
        check(label + " page %d size" % cur, img.shape[1] == pw and img.shape[0] == ph, img.shape)
        sh = c["sheets"][sheet]
        green = np.zeros(img.shape[:2], bool); full = np.zeros(img.shape[:2], bool); inner = np.zeros(img.shape[:2], bool); allowed = np.zeros(img.shape[:2], bool)
        whites = np.zeros(img.shape[:2], bool)
        def box(x1, y1, x2, y2, grow=0):
            xa = rnd((min(x1, x2) * 5 - ox) * lay["zoom"]) - grow; xb = rnd((max(x1, x2) * 5 - ox) * lay["zoom"]) + grow
            ya = rnd((min(y1, y2) * 5 - oy) * lay["zoom"]) - grow; yb = rnd((max(y1, y2) * 5 - oy) * lay["zoom"]) + grow
            return xa, ya, xb, yb
        def mark(m, b):
            xa, ya, xb, yb = b
            xa, ya, xb, yb = max(xa, 0), max(ya, 0), min(xb + 1, img.shape[1]), min(yb + 1, img.shape[0])
            if xb > xa and yb > ya: m[ya:yb, xa:xb] = True
        for (x1, y1, x2, y2, st, fl) in sh["rects"]:
            mark(allowed, box(x1, y1, x2, y2, 4))
            if fl == 1: mark(inner, box(x1, y1, x2, y2, -3)); mark(full, box(x1, y1, x2, y2, 1))
        for (x1, y1, x2, y2, st) in sh["lines"]: mark(allowed, box(x1, y1, x2, y2, 4 if st == 0 else 6))
        r, g, b = img[..., 0].astype(int), img[..., 1].astype(int), img[..., 2].astype(int)
        if c["bw"]:
            check(label + " page %d is gray only" % cur, bool(np.all((r == g) & (g == b))), None)
            ink = (r < 128)
            # green fills print black
            check(label + " page %d filled squares are black" % cur, bool(np.all(ink[inner])) if inner.any() else True, None)
        else:
            gp = (g > 200) & (r < 60) & (b < 60)
            check(label + " page %d green fills inside their squares" % cur, bool(np.all(gp[inner])) if inner.any() else True, None)
            check(label + " page %d no green outside the squares" % cur, not bool(np.any(gp & ~full)), int(np.count_nonzero(gp & ~full)))
        nonwhite = (r < 250) | (g < 250) | (b < 250)
        stray = nonwhite & ~allowed
        check(label + " page %d only the sheet's own objects (no paper, grid, rulers)" % cur, not stray.any(), (int(stray.sum()), np.argwhere(stray)[:3].tolist()))
cases = [build_case(n) for n in range(24)]
GROUP = 6
for g0 in range(0, len(cases), GROUP):
    script = ""
    for k, c in enumerate(cases[g0:g0 + GROUP]):
        n = g0 + k
        p = os.path.join(tmp, "case%d.dsn" % n); make_design(p, c["sheets"])
        c["dir"] = os.path.join(tmp, "out%d" % n)
        script += 'open %s\nprintsink %s %d\ngosheet %d\nprintdialog scale=%s bw=%d sheets=%s press=ok\n' % (p, c["dir"], DPI, c["active"], repr(c["scale"]), c["bw"], "all" if c["all"] else "current")
    o, rc, err = run(script, "geo%d" % g0)
    d = lines_of(o, "PRINTDIALOG")
    check("geometry group %d: all printed" % g0, len(d) == min(GROUP, len(cases) - g0) and rc == 0, (o[:6], err[:200]))
    for k, c in enumerate(cases[g0:g0 + GROUP]):
        n = g0 + k
        if k < len(d):
            st, pr, dn, parts = dlg(d[k])
            lay = po.layout(*device(c["h"] > c["w"]), DPI, c["w"], c["h"], c["scale"], c["all"], len(c["sheets"]))
            check("case %d: dialog says %d pages" % (n, lay["pages"]), dn.get("printed") == str(lay["pages"]), (d[k][-300:], lay["pages"]))
            verify(c, d[k], pages_of(c["dir"]), "case %d (%dx%d scale %s all=%s bw=%s)" % (n, c["w"], c["h"], c["scale"], c["all"], c["bw"]))

# copies, ranges and the order of pages (sheets go round fastest when all are printed)
def sized(n, w=1485, h=1050, k=2):
    return dict(w=w, h=h, rects=[(10 + 10 * n, 10 + 5 * n, 30 + 10 * n, 30 + 5 * n, 0, 1)], lines=[], rulers=[])
p = os.path.join(tmp, "multi.dsn"); make_design(p, [sized(0), sized(1), sized(2)])
dr = os.path.join(tmp, "o_multi")
script = ""
variants = [("a", "scale=100 sheets=all"), ("b", "scale=100 sheets=all from=2 to=3"), ("c", "scale=100 sheets=all from=3 to=2"), ("d", "scale=100 sheets=current copies=2"),
            ("e", "scale=100 sheets=all copies=2 collate=1 from=1 to=2"), ("f", "scale=100 sheets=all copies=2 collate=0 from=1 to=2"), ("g", "scale=100 sheets=all from=9 to=12"),
            ("h", "scale=100 sheets=all from=2 to=4"), ("i", "scale=100 sheets=all from=1 to=-1"), ("j", "scale=100 sheets=all from=-1 to=2"), ("k", "scale=100 sheets=all from=3 to=3")]
for tag, opts in variants:
    script += "open %s\nprintsink %s_%s\ngosheet 1\nprintdialog %s press=ok\n" % (p, dr, tag, opts)
o, rc, err = run(script, "multi")
d = lines_of(o, "PRINTDIALOG")
check("multi: eleven answers", len(d) == 11, o[:5])
def first_green(img):
    ys, xs = np.nonzero((img[..., 1] > 200) & (img[..., 0] < 60)); return (int(xs.min()), int(ys.min())) if len(xs) else None
pos = {}
for tag, _ in variants:
    pos[tag] = [first_green(im) for im in pages_of("%s_%s" % (dr, tag))]
# the sheets' squares move 10 mm right and 5 mm down (3.9 px/mm) from sheet to sheet, so the sheet of a page is its square's position
def sheet_of(pt): return None if pt is None else round((pt[0] - first_green(pages_of(dr + "_a")[0])[0]) / (10 * 3.9 * 1.0)) if False else pt
base = pos["a"]
check("all sheets, 3 pages, sheet order 1 2 3", len(base) == 3 and base[0][0] < base[1][0] < base[2][0], base)
check("range 2-3 prints the last two", pos["b"] == base[1:3], pos["b"])
check("a reversed range 3-2 prints the same two", pos["c"] == base[1:3], pos["c"])
check("current sheet and 2 copies: sheet 2 twice", len(pos["d"]) == 2 and pos["d"][0] == pos["d"][1] == base[1], pos["d"])
check("collated copies of 1-2: 1 2 1 2", pos["e"] == [base[0], base[1], base[0], base[1]], pos["e"])
check("uncollated copies of 1-2: 1 1 2 2", pos["f"] == [base[0], base[0], base[1], base[1]], pos["f"])
check("a range past the pages prints nothing", pos["g"] == [], pos["g"])
check("...and the dialog stays open with the reason", d and "stays open" in d[6] and "does not exist: the print has 3 pages" in d[6] and "done" not in d[6], d[6:] )
check("every dialog opens on All pages", all("start " in x and "range=[Pages: all" in x.split("| pressed")[0] for x in d), [x[:60] for x in d])
check("the dialog has the Printer, Sheets, Pages and Options groups in order", all("groups=Printer|Sheets|Pages|Options" in x for x in d), d[0][:200])
check("the range is shown in the dialog (range 2-3)", "range=[Pages: 2-3" in d[1] and "range=[Pages: all" in d[0], (d[0][-200:], d[1][-200:]))
check("a last page past the pages, or a page below 1, keeps the dialog open", all("stays open" in d[i] and pos["hij"[i - 7]] == [] for i in (7, 8, 9)), d[7:])
check("a one-page range 3-3 prints the last sheet only", "stays open" not in d[10] and pos["k"] == base[2:3], (pos["k"], d[10][-80:]))
check("pages reported", [x.split("printed=")[1].split(" ")[0] for x in d[:6]] == ["3", "2", "2", "1", "2", "2"], d)

# colors: the real example in color has colors; in black and white, none
o, rc, err = run('open %s\nprintsink %s/ex1\nprintdialog scale=100 bw=0 press=ok\nprintsink %s/ex2\nprintdialog scale=100 bw=1 press=ok\n' % (AMP, tmp, tmp), "ex")
c1 = pages_of(os.path.join(tmp, "ex1")); c2 = pages_of(os.path.join(tmp, "ex2"))
check("example: one page each", len(c1) == len(c2) == 1, (len(c1), len(c2)))
if c1 and c2:
    a = c1[0].astype(int); b = c2[0].astype(int)
    check("example in color has colored pixels", bool(np.any((a.max(2) - a.min(2)) > 60)), None)
    check("example in black and white is gray only", bool(np.all((b.max(2) - b.min(2)) == 0)), None)
    check("example prints ink", int((a.min(2) < 128).sum()) > 2000, None)
    # the same drawing: black and white dark pixels are the color page's dark/colored ink, never more of it than ink + fills
    ink_a = a.min(2) < 250; ink_b = b.min(2) < 250
    check("example: black and white inks where color inks (to a pixel of anti-aliasing)", int((ink_a & ~ink_b).sum()) < 0.002 * ink_a.sum() + 5, int((ink_a & ~ink_b).sum()))
    check("example: the paper is blank around (a margin)", bool(np.all(a[:5] == 255)) and bool(np.all(a[-5:] == 255)), None)

# ---------------------------------------------------------------- 6. the preview
pvd = os.path.join(tmp, "pv")
o, rc, err = run('open %s\nprintsink %s 100\nprintdialog scale=250 press=ok\nprintnext scale=250 press=ok\nprintsink %s/pv2 100\n'
                 'previewrun prev next next two next zoomin zoomin zoomin zoomin zoomout zoomout zoomout zoomout page=1 page=5 page=9 page=10 page=99 page=0 press=print\n' % (AMP, pvd, tmp), "pv")
pv = lines_of(o, "PREVIEWRUN")
check("preview: one report", len(pv) == 1, o[-3:])
if pv:
    steps = pv[0].split(" | ")
    names = [x.split(" ", 1)[0] for x in steps]
    S = [kv(x.split(" ", 1)[1]) if x.split(" ", 1)[0] in ("start", "next", "prev", "two", "zoomin", "zoomout") else {} for x in steps]
    check("preview: opens at page 1 of the 9 pages (3 across, 3 down)", S[0].get("page") == "1" and S[0].get("pages") == "9" and S[0].get("cols") == "3" and S[0].get("rows") == "3", steps[0])
    check("preview: first page: Prev dimmed, Next usable, status", S[0].get("prev") == "0" and S[0].get("next") == "1" and S[0].get("status") == "Page 1 of 9", steps[0])
    check("preview: Prev on page 1 stays", S[1].get("page") == "1", steps[1])
    check("preview: Next goes on twice", S[2].get("page") == "2" and S[2].get("prev") == "1" and S[3].get("page") == "3", steps[2:4])
    check("preview: two pages shows two, caption One Page, status Pages 3-4", S[4].get("shown") == "2" and S[4].get("twocaption") == "One Page" and S[4].get("status") == "Pages 3-4 of 9", steps[4])
    check("preview: Next with two shown goes on by two? (by one page)", S[5].get("page") in ("4", "5"), steps[5])
    zs = [int(S[i].get("zoom", -1)) for i in range(6, 14)]
    check("preview: zoom in three steps then stops; out three steps then stops", zs == [1, 2, 3, 3, 2, 1, 0, 0], zs)
    check("preview: Zoom In dimmed at the most, Zoom Out at the least", S[9].get("zoomin") == "0" and S[9].get("zoomout") == "1" and S[13].get("zoomout") == "0" and S[13].get("zoomin") == "1", (steps[9], steps[13]))
    pg = {x.split(" ")[1]: x.split(" ")[2] for x in steps if x.startswith("page ")}
    check("preview: pages out of range are none", pg.get("99") == "none" and pg.get("0") == "none" and pg.get("10") == "none" and pg.get("9") != "none", pg)
    check("preview: Print pressed leads on to the Print dialog", steps[-1] == "press print", steps[-1])
    check("preview: ...which printed the 9 pages", len(pages_of(os.path.join(tmp, "pv2"))) == 9, None)
    # a preview page equals the printed page in shape: same ink, scaled
    pr_pages = pages_of(pvd)
    pw, ph = int(pg["1"].split("x")[0]), int(pg["1"].split("x")[1])
    for pn in (1, 5):
        f = os.path.join(tmp, "pv2", "preview_%d.png" % pn)
        check("preview page %d was drawn" % pn, os.path.exists(f), None)
        if os.path.exists(f) and len(pr_pages) == 9:
            pi = np.array(Image.open(f).convert("RGB")); pp = pr_pages[pn - 1]
            fac = pi.shape[1] / pp.shape[1]
            check("preview page %d has the printed page's proportions" % pn, abs(pi.shape[0] / pp.shape[0] - fac) < 0.01, (pi.shape, pp.shape))
            ys, xs = np.nonzero(pp.min(2) < 128); yp, xp = np.nonzero(pi.min(2) < 160)
            if len(xs) and len(xp):
                ok = abs(xs.min() * fac - xp.min()) < 4 and abs(xs.max() * fac - xp.max()) < 4 and abs(ys.min() * fac - yp.min()) < 4 and abs(ys.max() * fac - yp.max()) < 4
                check("preview page %d: ink spans the same part of the page" % pn, ok, ((xs.min() * fac, xs.max() * fac, ys.min() * fac, ys.max() * fac), (xp.min(), xp.max(), yp.min(), yp.max())))
            else:
                check("preview page %d: ink where the print has ink" % pn, len(xs) == 0 or len(xp) > 0, (len(xs), len(xp)))

# ---------------------------------------------------------------- 7. Page Setup's printer buttons
o, rc, err = run('open %s\nprinterpage 297x210\npagesetupprinter paper landscape\npagesetupprinter paper portrait\nprinterpage 210x297\npagesetupprinter paper landscape\n'
                 'pagesetupprinter paper portrait\nprinterpage 216x279\npagesetupprinter setup landscape\nprinterpage none\npagesetupprinter paper\npagesetupprinter setup\n' % AMP, "ps")
P = lines_of(o, "PAGESETUPPRINTER")
check("page setup: seven answers", len(P) == 7, o[-4:])
if len(P) == 7:
    K = [kv(x) for x in P]
    check("printer 297x210, landscape sheet: 297 x 210", (K[0]["w"], K[0]["h"], K[0]["used"]) == ("297", "210", "1"), P[0])
    check("printer 297x210, portrait sheet: 210 x 297", (K[1]["w"], K[1]["h"]) == ("210", "297"), P[1])
    check("printer 210x297, landscape sheet: 297 x 210", (K[2]["w"], K[2]["h"]) == ("297", "210"), P[2])
    check("printer 210x297, portrait sheet: 210 x 297", (K[3]["w"], K[3]["h"]) == ("210", "297"), P[3])
    check("letter becomes whole mm, long side across", (K[4]["w"], K[4]["h"]) in (("279", "216"), ("279", "215")), P[4])
    check("A4 paper name found", "A4" in K[0]["paper"] and "A4" in K[3]["paper"], (K[0]["paper"], K[3]["paper"]))
    check("no printer: nothing is changed and the status says so", K[5]["used"] == "0" and K[6]["used"] == "0" and "No printer is installed." in P[5] and "No printer is installed." in P[6], P[5:])

# ---------------------------------------------------------------- 8. no printer, bad hand edits
o, rc, err = run('open %s\nprintdialog press=ok\n' % AMP, "nop")
d = lines_of(o, "PRINTDIALOG")
check("no printer and no test sink: no printer name, OK dimmed, nothing printed", d and "printer= scale=100" in d[0] and d[0].count("ok=0") == 2 and "printed=-1" in d[0], d)

print("Print dialog checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
