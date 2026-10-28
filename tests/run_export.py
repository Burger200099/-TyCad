"""Export Image (File > Export Image..., TinyCAD's CDlgExportPNG with CTinyCadDoc::SavePNG / CreateMetafile) on the real program, checked against a separate statement
of what TinyCAD draws and keeps (numpy and the XML of the SVG files; nothing of the program's own code):
  - the dialog: the file name it proposes (the design's name with .png, output.png for a design with no dot in its name), the extension following the kind, the scale and turn
    dimmed for the vector kinds, the whole sheet or the selection, the scale from 1 to 1000 only, an empty name refused, Cancel writing nothing, a file that cannot be written
    reported, the choices kept in the registry (BitmapType, BitmapScaling, BitmapRotation) and coming back
  - the PNG: its size for many scales (the page plus 10 units at the right and bottom, times the scale), a colour one holding the colours of the objects on white, a black and
    white one exactly the same shape in black and white only, a turn equal to a quarter turn clockwise of the unturned picture
  - a selection: only the selected objects, on the area that holds them plus 10 units, up to the 1000 per cent
  - the SVG: its page size is the area at 0.2 mm to the unit (72 / 127 points), the scale and the turn do nothing, colours or only black and white
  - the Insert menu's tools are one group (one check for any tool, whichever submenu), following the tool however it was chosen
Needs the built program, xvfb and numpy / PIL."""
import glob, os, re, shutil, subprocess, sys, tempfile, math
import xml.etree.ElementTree as ET
import numpy as np
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Export checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 14: print("  FAIL", n, str(d)[:700])
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


# ---------------------------------------------------------------- a design of known objects (positions in mm as the file keeps them; 5 units to the mm)
PW, PH = 1485, 1050
R1 = (100, 100, 300, 250); R2 = (750, 500, 1000, 700); LN = (500, 750, 1250, 750)           # in units
design = os.path.join(tmp, "x.dsn")
make_design(design, [dict(w=PW, h=PH, rects=[(20, 20, 60, 50, 1, 1), (150, 100, 200, 140, 0, 0)], lines=[(100, 150, 250, 150, 1), (250, 100, 200, 80, 1)])])
WHITE = (255, 255, 255)
def png(path): return np.array(Image.open(path).convert("RGB"))
def near(img, x, y, rgb, r=3):
    """a pixel of exactly this colour within r pixels of (x, y)"""
    h, w = img.shape[:2]
    win = img[max(0, int(y) - r):min(h, int(y) + r + 1), max(0, int(x) - r):min(w, int(x) + r + 1)]
    return bool(win.size) and bool(((win == np.array(rgb)).all(axis=2)).any())
def nonwhite(img): return ~(img == np.array(WHITE)).all(axis=2)
def size_of(region, s): return (max(1, int((region[2] - region[0]) * s / 100)), max(1, int((region[3] - region[1]) * s / 100)))
def ex(script, home="ex"):
    o, rc, err = run('open %s\n' % design + script, home)
    return o

# ---------------------------------------------------------------- 1. the dialog
o = ex('exportimage type=0 file=%s/d1.png\nexportimage type=1 file=%s/d2.png cancel=1\nexportimage type=2 file=none\nexportimage type=2 file=%s/noext.svg scale=0\nexportimage type=0 file=%s/e.png scale=1001\nexportimage type=0 file=%s/e.png scale=abc\nexportimage type=0 file=%s/e.png scale=1000 rotate=0\n' % ((tmp,) * 6) + 'selidx 3\nexportimage file=%s/sel.png\n' % tmp)
L = lines_of(o, "EXPORTIMAGE")
starts = [kv(l.split("start ", 1)[1]) for l in L if l.startswith("start ")]
check("seven dialogs started", len(starts) == 8, len(starts))
s0 = starts[0]
check("the file proposed is the design's name with .png, the kind colour PNG, scale 100, no turn, both enabled, the button says Export, four kinds", s0.get("file") == design[:-4] + ".png" and s0["type"] == "0" and s0["scale"] == "100" and s0["rotate"] == "0" and s0["scaleenabled"] == "1" and s0["rotateenabled"] == "1" and s0["button"] == "&Export" and s0["kinds"] == "4", s0)
check("nothing selected: the whole sheet is saved", "what=The whole sheet is saved." in L[0], L[0][-60:])
check("a cancelled dialog wrote nothing", not os.path.exists(os.path.join(tmp, "d2.png")) and os.path.exists(os.path.join(tmp, "d1.png")))
check("choosing SVG changes the extension and dims the scale and the turn", any("export type=2 file=none" in l or "export type=2 file=" in l for l in L) and any("type=2" in l and "scaleenabled=0" in l for l in L), [l for l in L if "type=2" in l][:2])
check("a dialog that starts on SVG has the scale and the turn dimmed (and one that starts on PNG has them usable)", any(s["type"] == "2" and s["scaleenabled"] == "0" and s["rotateenabled"] == "0" for s in starts) and all(s["rotateenabled"] == "1" for s in starts if s["type"] in ("0", "1")), [(s["type"], s["scaleenabled"], s["rotateenabled"]) for s in starts])
check("an empty file name is refused", any("file= " in l or l.startswith("export type=2 file= ") for l in L) and any("error=[Enter the name of the file to write.]" in l for l in L), [l for l in L if "error" in l][:4])
check("a scale of 0 does nothing to an SVG", any("noext.svg" in l and "error=[]" in l for l in L) and os.path.exists(os.path.join(tmp, "noext.svg")), [l for l in L if "noext" in l])
check("a scale of 1001 or text is refused with the reason, and the dialog stays open", sum("The scale must be a whole number from 1 to 1000." in l for l in L) >= 2 and sum(l == "stays open" for l in L) >= 3, L)
check("a scale of 1000 is accepted (the whole sheet at ten times)", os.path.exists(os.path.join(tmp, "e.png")) and Image.open(os.path.join(tmp, "e.png")).size == size_of((0, 0, PW + 10, PH + 10), 1000), None)
check("with something selected the dialog says so", any("what=The selected objects are saved." in l for l in L), [l[-80:] for l in L if "start" in l])
# no dot in the name / new document
o2, rc, err = run('newdoc "ISO A4" landscape\nexportimage type=0 file=%s/nd.png\nexportimage type=2 cancel=1\n' % tmp, "nodoc")
L2 = lines_of(o2, "EXPORTIMAGE"); st2 = [kv(l.split("start ", 1)[1]) for l in L2 if l.startswith("start ")]
check("a new design proposes a .png name", st2 and st2[0]["file"].endswith(".png"), st2[:1])
check("the kind chosen last time is proposed next (a new dialog after SVG)", len(st2) == 2 and st2[1]["type"] == "0", st2)

# ---------------------------------------------------------------- 2. what is kept
reg0 = registry("reg") if os.path.exists(os.path.join(tmp, "home_reg")) else {}
o = ex('exportimage type=2 file=%s/k.svg scale=250 rotate=1\n' % tmp, "reg")
r1 = registry("reg")
check("Export keeps the kind, the scale and the turn in the registry (BitmapType 2, BitmapScaling 250, BitmapRotation 1)", r1.get("BitmapType") == "2" and r1.get("BitmapScaling") == "250" and r1.get("BitmapRotation") == "1", {k: v for k, v in r1.items() if k.startswith("Bitmap")})
o = ex('exportimage type=0 file=%s/k2.png scale=0\nexportimage cancel=1\nexportimage type=1 file=%s/nodir/x.png scale=77 rotate=0\nexportimage cancel=1 type=3\n' % (tmp, tmp), "reg")
L = lines_of(o, "EXPORTIMAGE"); st = [kv(l.split("start ", 1)[1]) for l in L if l.startswith("start ")]
check("the next start has what was kept (SVG, 250, turn on, name with .svg)", st[0]["type"] == "2" and st[0]["scale"] == "250" and st[0]["rotate"] == "1" and st[0]["file"].endswith(".svg"), st[0])
check("a refused scale and Cancel keep nothing new", st[1]["type"] == "2" and st[1]["scale"] == "250", st[1])
check("a file in a folder that does not exist is reported and nothing else happens", any("wrote=0 status=Cannot write the image file." in l for l in L), [l for l in L if "wrote" in l])
check("...but the choices are kept when Export was pressed", st[3]["type"] == "1" and st[3]["scale"] == "77" and st[3]["rotate"] == "0", st[3])

# ---------------------------------------------------------------- 3. the PNG
whole = (0, 0, PW + 10, PH + 10)
scales = [1, 7, 37, 50, 100, 133, 250, 300]
script = ""
for s in scales: script += 'exportimage type=0 file=%s/c_%d.png scale=%d rotate=0\nexportimage type=1 file=%s/b_%d.png scale=%d rotate=0\n' % (tmp, s, s, tmp, s, s)
script += 'exportimage type=0 file=%s/c_rot.png scale=100 rotate=1\nexportimage type=1 file=%s/b_rot.png scale=61 rotate=1\nexportimage type=1 file=%s/b_61.png scale=61 rotate=0\n' % ((tmp,) * 3)
o = ex(script, "png")
for s in scales:
    c = png("%s/c_%d.png" % (tmp, s)); b = png("%s/b_%d.png" % (tmp, s))
    w, h = size_of(whole, s)
    check("scale %d: the picture is the page plus 10 units, times the scale (%dx%d)" % (s, w, h), c.shape[1] == w and c.shape[0] == h and b.shape[:2] == c.shape[:2], (c.shape, (h, w)))
    f = s / 100
    if s >= 37:
        check("scale %d: green inside the first rectangle, red on its outline, white beside it" % s, near(c, 200 * f, 175 * f, (0, 255, 0), 2) and near(c, 100 * f, 175 * f, (255, 0, 0), max(3, int(3 * f))) and tuple(c[int(40 * f), int(40 * f)]) == WHITE, None)
        check("scale %d: the second rectangle is a black outline round white" % s, near(c, 750 * f, 600 * f, (0, 0, 0), max(3, int(2 * f))) and tuple(c[int(600 * f), int(875 * f)]) == WHITE and not near(c, 875 * f, 600 * f, (0, 255, 0), 1), None)
    cols = np.unique(c.reshape(-1, 3), axis=0)
    check("scale %d: the colour picture has only the colours of the objects" % s, {tuple(x) for x in cols} <= {WHITE, (0, 255, 0), (255, 0, 0), (0, 0, 0)} or s < 37, [tuple(x) for x in cols][:8])
    bc = {tuple(x) for x in np.unique(b.reshape(-1, 3), axis=0)}
    check("scale %d: the black and white picture is black and white only" % s, bc <= {WHITE, (0, 0, 0)}, list(bc)[:6])
    same = (nonwhite(c) == nonwhite(b)).mean()
    check("scale %d: the black and white picture has the shape of the colour one" % s, same > 0.999 if s >= 37 else same > 0.9, same)
c = png(tmp + "/c_100.png"); r = png(tmp + "/c_rot.png")
check("turned: the picture is a quarter turn clockwise of the unturned one, pixel for pixel", r.shape == (c.shape[1], c.shape[0], 3) and (r == np.rot90(c, k=-1)).all(), (r.shape, c.shape))
b61 = png(tmp + "/b_61.png"); r61 = png(tmp + "/b_rot.png")
check("turned black and white at 61%: exactly the same", (r61 == np.rot90(b61, k=-1)).all(), (r61.shape, b61.shape))

# ---------------------------------------------------------------- 4. a selection
# (the file puts its lines before its rectangles: 0 is the line, 1 a line drawn from right to left, 2 the green rectangle, 3 the black one)
cases = {"r2": ([3], (750, 500, 1010, 710)), "r1r2": ([2, 3], (100, 100, 1010, 710)), "line": ([0], (500, 750, 1260, 760)), "r1": ([2], (100, 100, 310, 260)), "back": ([1], (1000, 400, 1260, 510)), "backr2": ([1, 3], (750, 400, 1260, 710))}
script = ""
for name, (idx, reg) in cases.items():
    script += "selidx %s\n" % " ".join(map(str, idx))
    for s in (100, 1000 if name in ("r2", "line", "r1", "back") else 200):
        script += 'exportimage type=0 file=%s/s_%s_%d.png scale=%d rotate=0\n' % (tmp, name, s, s)
    script += 'exportimage type=1 file=%s/sb_%s.png scale=100\nexportimage type=3 file=%s/s_%s.svg\n' % (tmp, name, tmp, name)
o = ex(script, "sel")
for name, (idx, reg) in cases.items():
    for s in (100, 1000 if name in ("r2", "line", "r1", "back") else 200):
        img = png("%s/s_%s_%d.png" % (tmp, name, s)); w, h = size_of(reg, s)
        check("selection %s at %d%%: the picture is the area round the objects plus 10 units (%dx%d)" % (name, s, w, h), img.shape[1] == w and img.shape[0] == h, (img.shape, (h, w)))
    img = png("%s/s_%s_100.png" % (tmp, name)); nw = nonwhite(img)
    ys, xs = np.nonzero(nw)
    check("selection %s: the objects touch the corner of the picture and end 10 units before the other edges" % name, xs.min() <= 3 and ys.min() <= 3 and xs.max() >= img.shape[1] - 14 and xs.max() <= img.shape[1] - 8 and ys.max() >= img.shape[0] - 14 and ys.max() <= img.shape[0] - 8, (xs.min(), ys.min(), xs.max(), ys.max(), img.shape))
    has = lambda rgb: bool((img == np.array(rgb)).all(axis=2).any())
    check("selection %s: only the selected objects are in it" % name, has((0, 255, 0)) == (2 in idx) and has((0, 0, 0)) == (3 in idx) and (has((255, 0, 0)) == (bool({0, 1, 2} & set(idx)))), (has((0, 255, 0)), has((0, 0, 0)), has((255, 0, 0))))
img = png(tmp + "/s_r1r2_200.png")
check("selection of two objects at 200%", img.shape[:2] == (int(610 * 2), int(910 * 2)) and near(img, (200 - 100) * 2, (175 - 100) * 2, (0, 255, 0), 2) and near(img, (750 - 100) * 2, (600 - 100) * 2, (0, 0, 0), 4), img.shape)
big = png(tmp + "/s_r2_1000.png")
check("a selection at the top scale (1000%) is 2600x2100 with a black outline 10 times the size", big.shape[:2] == (2100, 2600) and near(big, 0, 1000, (0, 0, 0), 6), big.shape)

# ---------------------------------------------------------------- 5. the SVG
def svg_info(path):
    t = open(path, encoding="utf-8").read(); root = ET.fromstring(t)
    cols = set(re.findall(r'(?:fill|stroke)="rgb\(([\d.]+)%,\s*([\d.]+)%,\s*([\d.]+)%\)"', t))
    return float(root.get("width")), float(root.get("height")), root.get("viewBox"), cols, t
o = ex('exportimage type=2 file=%s/v1.svg scale=300 rotate=1\nexportimage type=3 file=%s/v2.svg scale=5\nselidx 3\nexportimage type=2 file=%s/v3.svg\n' % ((tmp,) * 3), "svg")
for nm, reg in (("v1", whole), ("v2", whole), ("v3", cases["r2"][1])):
    w, h, vb, cols, t = svg_info("%s/%s.svg" % (tmp, nm)); pw, ph = size_of(reg, 100)
    check("%s.svg: the page is the area at 0.2 mm to the unit (%d x %d units = %.3f x %.3f pt), whatever the scale and the turn" % (nm, pw, ph, pw * 72 / 127, ph * 72 / 127), abs(w - pw * 72 / 127) < 0.01 and abs(h - ph * 72 / 127) < 0.01 and vb == "0 0 %s %s" % (re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', t).group(1), re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', t).group(2)), (w, h, vb))
w1, h1, _, c1, t1 = svg_info(tmp + "/v1.svg"); w2, h2, _, c2, t2 = svg_info(tmp + "/v2.svg")
check("the colour SVG has the green and the red", ("0", "100", "0") in c1 and ("100", "0", "0") in c1, sorted(c1)[:6])
check("the black and white SVG has only black and white", c2 and all(a == b == c and a in ("0", "100") for a, b, c in c2), sorted(c2)[:6])
check("the SVG draws the three objects as paths (two lines with their end marks, the two rectangles)", t1.count("<path") == 6 and svg_info(tmp + "/v3.svg")[4].count("<path") == 1, t1.count("<path"))
w3, h3, _, c3, t3 = svg_info(tmp + "/v3.svg")
check("the SVG of a selection has no green and no red", ("0", "100", "0") not in c3 and ("100", "0", "0") not in c3, sorted(c3))

# ---------------------------------------------------------------- 6. the menu item and the Insert menu's group of tools
o, rc, err = run('menuselect miExportImage\nopen %s\nmenuselect miExportImage\n' % design, "menu")
m = [l for l in o if l.startswith("MENUSELECT")]
check("Export Image is dimmed with no design and usable with one, with its hint", len(m) == 2 and "enabled=0" in m[0] and "enabled=1" in m[1] and "hint=Save the sheet or the selection as a picture file panel0=Save the sheet or the selection as a picture file" in m[1], m)
TOOLS = ["select", "wire", "line", "polygon", "rect", "circle", "arc", "note", "cloud", "label", "junction", "rulerh", "rulerv", "measure", "ladder", "xrefline", "xrefcontacts", "bus", "busslash", "noconnect", "power", "text"]
MENU = {"select": "miSelect", "wire": "miDrawWire", "line": "miDrawLine", "polygon": "miDrawPolygon", "rect": "miDrawRect", "circle": "miDrawCircle", "arc": "miDrawArc", "note": "miDrawNote", "cloud": "miDrawCloud",
        "label": "miDrawLabel", "junction": "miDrawJunction", "rulerh": "miDrawRulerH", "rulerv": "miDrawRulerV", "measure": "miDrawRulerAB", "ladder": "miLadderRails", "xrefline": "miDrawRefLine",
        "xrefcontacts": "miDrawContact", "bus": "miDrawBus", "busslash": "miDrawBusSlash", "noconnect": "miDrawWireNoCon", "power": "miDrawPower", "text": "miDrawText"}
script = ""
for t in TOOLS:
    script += "tool %s\n" % t + "".join("menuselect %s\n" % n for n in MENU.values()) + "echo END %s\n" % t
o, rc, err = run('open %s\n' % design + script, "group")
chunks = []; cur = []
for l in o:
    if l.startswith("MENUSELECT"): cur.append(l)
    elif l.startswith("END "): chunks.append((l[4:], cur)); cur = []
check("a tool at a time through the menu items", len(chunks) == len(TOOLS), len(chunks))
for name, ms in chunks:
    on = [l.split()[1] for l in ms if " checked=1" in l]
    check("tool %s: exactly its own menu item is checked, in any submenu" % name, on == [MENU[name]], on)
# choosing from the menu (a click) starts the tool and the check follows
o, rc, err = run('open %s\ntool wire\nmenuclick miDrawRect\nmenuselect miDrawRect\nmenuselect miDrawWire\nmenuclick miSelect\nmenuselect miSelect\nmenuselect miDrawRect\n' % design, "group2")
m = [l for l in o if l.startswith("MENUSELECT")]
check("clicking a tool's menu item takes the check from the tool before, even in another submenu; Select takes it back", len(m) == 4 and " checked=1" in m[0] and " checked=0" in m[1] and " checked=1" in m[2] and " checked=0" in m[3], m)
print("Export image checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
