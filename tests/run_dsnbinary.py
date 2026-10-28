"""The old binary .dsn reader (Io.cpp's legacy branch, CHeaderStamp, the Load / OldLoad functions), checked against files written here
by dsnbin_gen.py from the C++ source's field order, with every expected value worked out by hand from the C++ (the resource-number
merging included), and read back through XML with ElementTree.  No real old file was available, so these are synthetic.
  - the stamp: revisions 0-6 pass, 7 and a wrong name / magic / short file do not, XML files are not mistaken for binary
  - title block (old and new), the date text, the grid, the options, strings (ANSI, UTF-16, long ones)
  - every object type and its older forms (labels, texts, pins, polygons, arcs, squares, circles, methods, notes, pictures, rulers, tags)
  - the resource tables and the renumbering of fonts, line styles, fills, symbols and pictures (what the objects end up pointing at)
  - symbols (fields, display types, the drawing inside) and symbols stored by name (library lookup)
  - tags that mean nothing, empty objects, the end of the file, damaged files: every cut of a file, random damage
  - opening in the program: the design opens as an unsaved "(converted)" document, Save As starts from a new name
Needs the built dsnbintest (tests/drivers) for the headless checks and, for the last group, the built program and xvfb."""
import glob, os, random, re, shutil, struct, subprocess, sys, tempfile, time
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import dsnbin_gen as g
from uuoracle import uu_decode
EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
BUILD = os.environ.get("TC_BUILD", "build")
DT = os.path.join(BUILD, "dsnbintest")
if not os.path.exists(DT):
    print("Binary design checks skipped: build tests/drivers/dsnbintest.pas first", DT); sys.exit(0)
tmp = tempfile.mkdtemp()
fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name)
        if len(fails) <= 25: print("  FAIL", name, str(detail)[:600])
seq = [0]
def conv(data, finder=False, timeout=30):
    """write the bytes to a file and run the converter: (return code, output lines, root element or None, text)"""
    seq[0] += 1
    src = os.path.join(tmp, "in%d.dsn" % seq[0]); dst = os.path.join(tmp, "out%d.xml" % seq[0])
    open(src, "wb").write(data)
    r = subprocess.run([DT, "convert", src, dst] + (["finder"] if finder else []), capture_output=True, text=True, timeout=timeout)
    root = None
    if r.returncode == 0 and os.path.exists(dst):
        try: root = ET.parse(dst).getroot()
        except ET.ParseError as e: root = None; r.stdout += "XMLERROR %s\n" % e
    return r.returncode, r.stdout.split("\n"), root, r.stdout + r.stderr
def detect(data):
    p = os.path.join(tmp, "det.dsn"); open(p, "wb").write(data)
    return subprocess.run([DT, "detect", p], capture_output=True, text=True).stdout.strip()
def note_of(lines):
    for l in lines:
        if l.startswith("NOTE"): return l[5:]
    return None
RES_TAGS = {"NAME", "DETAILS", "FONT", "STYLE", "FILL", "META", "IMAGE", "SYMBOLDEF", "OPTIONS"}
def sheet(root): return root.find("TinyCAD")
def objs(root): return [e for e in sheet(root) if e.tag not in RES_TAGS]
def table(root, tag): return {e.get("id"): e for e in sheet(root).findall(tag)}
def fl(s): return tuple(float(v) for v in s.split(","))
def P(x, y): return (x / 5.0, y / 5.0)       # the XML holds a fifth of the file's units
def near(a, b): return all(abs(p - q) < 1e-4 for p, q in zip(a, b))
def style_of(root, i):
    e = table(root, "STYLE")[str(i)]
    return (int(e.findtext("STYLE")), int(e.findtext("THICKNESS")), e.findtext("COLOR"))
def font_of(root, i):
    e = table(root, "FONT")[str(i)]
    return (int(e.findtext("HEIGHT")), int(e.findtext("WIDTH")), int(e.findtext("WEIGHT")), int(e.findtext("ITALIC")), int(e.findtext("UNDERLINE")),
            int(e.findtext("STRIKEOUT")), int(e.findtext("CHARSET")), e.findtext("FACENAME"))
def fill_of(root, i):
    e = table(root, "FILL")[str(i)]
    return (int(e.findtext("INDEX")), e.findtext("COLOR"))
def one(data, finder=False):
    rc, lines, root, text = conv(data, finder)
    return root, lines, text
W = g.wire((0, 0), (5, 5))     # a filler object

# =============================================================== the stamp
good = g.design(W)
check("stamp bytes", good[:11] == b"\x07TinyCAD\x06\x5a\x0c", good[:12])
check("detect: a binary design", detect(good) == "DETECT 1")
for rev in range(0, 7):
    check("detect: revision %d" % rev, detect(g.design(W, rev=rev)) == "DETECT 1")
    root, lines, text = one(g.design(W, rev=rev))
    check("opens: revision %d" % rev, root is not None and len(objs(root)) == 1, text)
for rev in (7, 8, 200, 255):
    check("detect: revision %d is newer than the reader" % rev, detect(g.design(W, rev=rev)) == "DETECT 0")
    rc, lines, root, text = conv(g.design(W, rev=rev))
    check("a newer revision is not read (%d)" % rev, rc != 0 and "ERROR" in text, text)
for name in ("tinycad", "TinyCAD2", "TinyCa", "TINYCAD", "", "TinyCAD "):
    check("detect: name %r" % name, detect(g.design(W, name=name)) == "DETECT 0")
for magic in (0, 0x0C5B, 0x5A0C, -1):
    check("detect: magic %x" % (magic & 0xFFFF), detect(g.design(W, magic=magic)) == "DETECT 0")
for k in range(0, 11):
    check("detect: only %d bytes of the stamp" % k, detect(good[:k]) == "DETECT 0")
check("detect: stamp alone", detect(good[:11]) == "DETECT 1")
check("detect: unicode name is not the stamp", detect(g.s("TinyCAD", True) + b"\x06\x5a\x0c" + W) == "DETECT 1", "(a UTF-16 CString with the same text is the same name)")
xml_files = sorted(glob.glob(os.path.join(EXAMPLES, "circuits", "*.dsn")))[:6] + sorted(glob.glob(os.path.join(EXAMPLES, "drawings", "*.dsn")))[:3]
for f in xml_files:
    check("an XML design is not binary: " + os.path.basename(f), detect(open(f, "rb").read()) == "DETECT 0")
if xml_files:
    p = os.path.join(tmp, "x.xml"); r = subprocess.run([DT, "convert", xml_files[0], p], capture_output=True, text=True)
    check("an XML design still loads", "LEGACY 0" in r.stdout and re.search(r"objects=([1-9]\d*)", r.stdout), r.stdout + r.stderr)

# =============================================================== title block, grid, options, strings
def det(root):
    d = sheet(root).find("DETAILS")
    return {k: d.findtext(k) for k in ("TITLE", "AUTHOR", "REVISION", "DOCNUMBER", "ORGANISATION", "SHEETS", "SHOWS", "DATE")}, d
for t in (1078444800, 0, -86400, 2147483647, 1700000000, 951782400):
    root, lines, text = one(g.design(g.details_old(1485, 1050, "Ti", "Au", "R1", "No", "Or", "1 of 2", 1, t), W))
    d, de = det(root)
    want = time.strftime("%d %B %Y", time.gmtime(t))
    check("old title block date %d" % t, d["DATE"] == want, (d["DATE"], want))
    check("old title block text %d" % t, (d["TITLE"], d["AUTHOR"], d["REVISION"], d["DOCNUMBER"], d["ORGANISATION"], d["SHEETS"]) == ("Ti", "Au", "R1", "No", "Or", "1 of 2"), d)
    s = de.find("Size"); check("old title block page size", (s.get("width"), s.get("height")) == ("1485", "1050"))
for vis, shows in ((0, "0"), (1, "1"), (7, "1"), (255, "1")):
    root, lines, text = one(g.design(g.details_old(100, 200, "", "", "", "", "", "", vis, 0), W))
    d, de = det(root)
    check("old visible byte %d -> SHOWS %s (rulers off)" % (vis, shows), d["SHOWS"] == shows, d["SHOWS"])
    g1 = de.find("GUIDES"); check("old title block ruler sizes stay default", (g1.get("horiz"), g1.get("vert")) == ("7", "5"))
for shows in range(0, 4):
    root, lines, text = one(g.design(g.details_ex(297, 210, "T", "A", "B", "C", "D", "E", shows, "5 May 2005"), W))
    d, de = det(root)
    check("new title block SHOWS %d" % shows, d["SHOWS"] == str(shows), d["SHOWS"])
    check("new title block date text kept", d["DATE"] == "5 May 2005", d["DATE"])
    g1 = de.find("GUIDES"); check("new title block rulers are 5 by 7", (g1.get("horiz"), g1.get("vert")) == ("7", "5"))
root, lines, text = one(g.design(g.details_ex(10, 20, "Título €", "Åke", "é", "№1", "Ωmega 中文 😀", "", 3, "dátum", wide=True), W))
d, de = det(root)
check("title block in UTF-16", (d["TITLE"], d["AUTHOR"], d["REVISION"], d["DOCNUMBER"], d["ORGANISATION"], d["SHEETS"], d["DATE"]) == ("Título €", "Åke", "é", "№1".replace("№", "№"), "Ωmega 中文 😀", None if d["SHEETS"] is None else "", "dátum"), d)
for grid, snap, want in ((50, 1, "50.00000"), (25, 0, "25.00000"), (7, 1, "7.00000"), (0, 0, "0.00000"), (100, 5, "100.00000")):
    root, lines, text = one(g.design(g.details_ex(1485, 1050, "", "", "", "", "", "", 1, "", grid=grid, snap=snap), W))
    ge = sheet(root).find("DETAILS").find("GRID")
    check("grid %d snap %d" % (grid, snap), ge.get("spacing") == want and ge.get("snap") == str(snap), ge.attrib)
for gs, un in ((0, 0), (1, 0), (1, 2), (5, -3)):
    root, lines, text = one(g.design(g.options(7, 9, gs, un, 123), W))
    o = sheet(root).find("OPTIONS")
    check("options grid %d units %d" % (gs, un), (o.findtext("GRID"), o.findtext("UNITS")) == (str(gs), str(un)), (o.findtext("GRID"), o.findtext("UNITS")))
# strings through a label
long300 = "".join(chr(97 + i % 26) for i in range(300)); long70k = "".join(chr(65 + i % 26) for i in range(70000))
texts = ["abc", "é€‘’“”…ÿÀ", "<&> \"q\" 'a'", long300, long70k, "x" * 254, "y" * 255, "z" * 256, "w" * 65533, "v" * 65534, "u" * 65535, " lead and trail "]
for t in texts:
    root, lines, text = one(g.design(g.label("Label", (5, 5), 3, t)))
    lab = objs(root)[0] if root is not None else None
    check("ANSI text of %d chars" % len(t), lab is not None and (lab.text or "") == t, (len(lab.text or "") if lab is not None else text))
# (the UTF-16 form is tested next, through labels, the title block above and the symbol names below)
wide_label = g.u8(g.X["Label"]) + g.pt(5, 5) + g.u8(3) + g.s("Ωmega 😀", True)
root, lines, text = one(g.design(wide_label))
check("a UTF-16 string in an object", root is not None and objs(root)[0].text == "Ωmega 😀", text)
wide_long = g.u8(g.X["Label"]) + g.pt(5, 5) + g.u8(3) + g.s("λ" * 70000, True)
root, lines, text = one(g.design(wide_long))
check("a UTF-16 string of 70000 characters", root is not None and objs(root)[0].text == "λ" * 70000)

# =============================================================== simple objects
root, lines, text = one(g.design(
    g.wire((10, 20), (30, 20)), g.bus((0, 0), (0, 50)), g.junction((30, 20)), g.noconnect((40, 40)),
    g.busslash((50, 50), 2), g.busslash((55, 50), 0), g.power((60, 60), 2, 0, "VCC"), g.power((65, 60), 255, 3, "GND"),
    g.ruler((5, 5), 1), g.ruler((10, 5), 0), g.tag((7, 7), "TAGX")))
o = objs(root); tags = [e.tag for e in o]
check("simple objects: tags and order (the tag object is not kept)", tags == ["WIRE", "BUS", "JUNCTION", "NOCONNECT", "BUSSLASH", "BUSSLASH", "POWER", "POWER", "RULER", "RULER"], tags)
check("wire", near(fl(o[0].get("a")), P(10, 20)) and near(fl(o[0].get("b")), P(30, 20)))
check("bus", near(fl(o[1].get("a")), P(0, 0)) and near(fl(o[1].get("b")), P(0, 50)))
check("junction", near(fl(o[2].get("pos")), P(30, 20)))
check("no connect", near(fl(o[3].get("pos")), P(40, 40)))
check("bus slash", near(fl(o[4].get("pos")), P(50, 50)) and o[4].get("direction") == "2" and o[5].get("direction") == "0")
check("power", near(fl(o[6].get("pos")), P(60, 60)) and (o[6].get("which"), o[6].get("direction"), o[6].text) == ("2", "0", "VCC"), o[6].attrib)
check("power: byte values", (o[7].get("which"), o[7].get("direction"), o[7].text) == ("255", "3", "GND"), o[7].attrib)
check("ruler", near(fl(o[8].get("pos")), P(5, 5)) and o[8].get("horizontal") == "1" and o[9].get("horizontal") == "0", (o[8].attrib, o[9].attrib))
root, lines, text = one(g.design(g.wire((-100, -50), (2000000, 70000))))
check("negative and large coordinates", near(fl(objs(root)[0].get("a")), P(-100, -50)) and near(fl(objs(root)[0].get("b")), P(2000000, 70000)))
root, lines, text = one(g.design(g.wire((0, 0), (5, 5)), g.u8(1), g.u8(2), g.u8(29), g.u8(100), g.u8(200), g.u8(255), g.u8(14), g.u8(9), g.junction((9, 9))))
check("tags that mean nothing are skipped without reading anything", root is not None and [e.tag for e in objs(root)] == ["WIRE", "JUNCTION"], [e.tag for e in objs(root)] if root is not None else text)
root, lines, text = one(g.design(W) + b"garbage after the end \x13\x13\x13")
check("bytes after the end tag are not read", root is not None and len(objs(root)) == 1 and note_of(lines) == "", (text))
root, lines, text = one(g.design(g.layer_table([(1, "Layer one"), (7, "L")]), g.junction((5, 5))))
check("layer table is skipped", root is not None and [e.tag for e in objs(root)] == ["JUNCTION"], text)

# ---- labels and texts
root, lines, text = one(g.design(
    g.label("Label", (5, 5), 3, "L1"), g.label("LabelEx", (6, 6), 2, "L2", 3), g.label("LabelEx2", (7, 7), 1, "L3", 4, 0x0000FF),
    g.text("Text", (8, 8), 3, "T1"), g.text("TextEx", (9, 9), 3, "T2", 3), g.text("TextEx2", (10, 10), 0, "T3", 4, 0x00FF00),
    g.text("BusName", (11, 11), 3, "B1", 3), g.text("BusNameEx", (12, 12), 1, "B2", 4, 0xFF0000)))
o = objs(root)
check("labels and texts: tags in order", [e.tag for e in o] == ["LABEL"] * 3 + ["TEXT"] * 3 + ["BUSNAME"] * 2, [e.tag for e in o])
LABELCOL = "208000"   # RGB(0,128,32), the user colours' default for labels (UserColor.cpp)
check("Label: first font, label colour", (o[0].get("font"), o[0].get("color"), o[0].get("direction"), o[0].text) == ("0", LABELCOL, "3", "L1"), o[0].attrib)
check("LabelEx: font number (no table: first font), label colour", (o[1].get("font"), o[1].get("color"), o[1].get("direction")) == ("0", LABELCOL, "2"), o[1].attrib)
check("LabelEx2: colour from the file", (o[2].get("color"), o[2].get("direction"), o[2].text) == ("0000FF", "1", "L3"), o[2].attrib)
check("label position", near(fl(o[0].get("pos")), P(5, 5)) and near(fl(o[1].get("pos")), P(6, 6)))
check("Text: black", (o[3].get("font"), o[3].get("color"), o[3].text) == ("0", "000000", "T1"), o[3].attrib)
check("TextEx: black", (o[4].get("color"), o[4].get("direction")) == ("000000", "3"), o[4].attrib)
check("TextEx2: colour from the file", (o[5].get("color"), o[5].get("direction"), o[5].text) == ("00FF00", "0", "T3"), o[5].attrib)
check("BusName: label colour", (o[6].get("color"), o[6].text) == (LABELCOL, "B1"), o[6].attrib)
check("BusNameEx: colour from the file", (o[7].get("color"), o[7].get("direction")) == ("FF0000", "1"), o[7].attrib)
root, lines, text = one(g.design(g.text("TextEx2", (1, 1), 3, "", 0, 0), g.label("Label", (2, 2), 3, ""), g.text("Text", (3, 3), 3, ""), g.junction((4, 4))))
check("empty texts and labels are dropped", root is not None and [e.tag for e in objs(root)] == ["JUNCTION"], [e.tag for e in objs(root)] if root is not None else text)
rc, lines, root, text = conv(g.design(g.text("TextEx2", (1, 1), 3, "", 0, 0)))
check("a design with only empty objects has no objects", rc != 0 and "no objects" in text, text)
rc, lines, root, text = conv(g.design())
check("a design with nothing in it has no objects", rc != 0 and "no objects" in text, text)

# ---- pins
root, lines, text = one(g.design(
    g.pin_old((13, 13), 128, 2, 1, 0, "PA", "1", 3), g.pin_old((14, 14), 4, 2, 1, 0, "PW", "2", 3), g.pin_old((15, 15), 130, 0, 0, 1, "PC", "", 1),
    g.pin((16, 16), 0, 3, 2, 1, "PB", "2", 3, 3), g.pin((17, 17), 4, 3, 2, 1, "PV", "3", 3, 0), g.pin((18, 18), 0, 1, 0, 0, "P4", "4", 2, 4),
    g.pin((19, 19), 1, 1, 0, 0, "P5", "5", 2, 5), g.pin((20, 20), 4, 1, 0, 0, "P60", "6", 0, 60), g.pin((21, 21), 0, 0, 3, 7, "P65535", "7", 3, 65535)))
o = objs(root)
def pinfo(e): return (e.get("which"), e.get("elec"), e.get("direction"), e.get("part"), e.get("number"), e.get("show"), e.get("length"), e.get("number_pos"), e.get("centre_name"), e.text)
check("old pin, small flag", pinfo(o[0]) == ("0", "2", "1", "0", "1", "3", "20", "0", "0", "PA"), pinfo(o[0]))
check("old pin, normal, power: length 30, name centred", pinfo(o[1]) == ("4", "2", "1", "0", "2", "3", "30", "0", "1", "PW"), pinfo(o[1]))
check("old pin, small flag with other bits", pinfo(o[2]) == ("2", "0", "0", "1", "", "1", "20", "0", "0", "PC"), pinfo(o[2]))
check("pin length 3 becomes 20", pinfo(o[3]) == ("0", "3", "2", "1", "2", "3", "20", "0", "0", "PB"), pinfo(o[3]))
check("pin length 0 stays 0 (power pin: centred)", pinfo(o[4]) == ("4", "3", "2", "1", "3", "3", "0", "0", "1", "PV"), pinfo(o[4]))
check("pin length 4 becomes 20, length 5 stays", o[5].get("length") == "20" and o[6].get("length") == "5", (o[5].get("length"), o[6].get("length")))
check("pin length 60, 65535", o[7].get("length") == "60" and o[8].get("length") == "65535" and o[8].get("part") == "7", (o[7].get("length"), o[8].get("length")))
check("pin position", near(fl(o[0].get("pos")), P(13, 13)) and near(fl(o[3].get("pos")), P(16, 16)))

# =============================================================== resources and renumbering
# fonts: the defaults are 0 (text), 1 (pin), 2 (ruler); a font read from the file takes the next free number (3, 4, 5) unless it equals an unclaimed default
courier = g.font("Courier New", -20, 9, 700, 1, 1, 1, 2)
root, lines, text = one(g.design(g.fonts([(7, courier), (9, g.font("Arial", -18)), (12, g.font("Arial", -16))]),
    g.text("TextEx2", (1, 1), 3, "a", 9, 0x010203), g.text("TextEx", (2, 2), 3, "b", 12), g.label("LabelEx", (3, 3), 3, "c", 7), g.text("Text", (4, 4), 3, "d"),
    g.text("TextEx", (5, 5), 3, "e", 99), g.label("LabelEx2", (6, 6), 3, "f", 12, 5), g.text("BusNameEx", (7, 7), 3, "g", 7, 6), g.text("TextEx2", (8, 8), 3, "h", -1, 7)))
o = objs(root)
check("font numbers are renumbered", [e.get("font") for e in o] == ["4", "5", "3", "0", "0", "5", "3", "2"], [e.get("font") for e in o])
# (the last text names font -1: ConvertOld matches the items whose merge number is -1, and ResetMerge made that every font that no
#  file font claimed, so the last of them, the ruler font 2, answers. An id that nothing matches (99) gives 0.)
check("font Courier kept all its fields", font_of(root, 3) == (-20, 9, 700, 1, 1, 1, 2, "Courier New"), font_of(root, 3))
check("font Arial -18", font_of(root, 4) == (-18, 0, 400, 0, 0, 0, 0, "Arial") and font_of(root, 5)[0] == -16)
check("only fonts in use are saved", sorted(table(root, "FONT")) == ["0", "2", "3", "4", "5"], sorted(table(root, "FONT")))
# a font equal to a default takes the default's number
root, lines, text = one(g.design(g.fonts([(20, g.font("Arial", -10, 0, 400))]), g.text("TextEx", (1, 1), 3, "a", 20), g.label("LabelEx", (2, 2), 3, "b", 21)))
o = objs(root); check("a font equal to the pin font shares its number", [e.get("font") for e in o] == ["1", "0"], [e.get("font") for e in o])
# a repeated font is two entries in the file: the second one is not merged into the first
root, lines, text = one(g.design(g.fonts([(3, g.font("Arial", -33)), (4, g.font("Arial", -33))]), g.text("TextEx", (1, 1), 3, "a", 3), g.text("TextEx", (2, 2), 3, "b", 4)))
o = objs(root); check("two equal fonts in the file become two numbers", [e.get("font") for e in o] == ["3", "4"], [e.get("font") for e in o])

# line styles and fills; the defaults are style 0 solid/1 black, 1 dash/1 black, fill 0 none (-1), 1 black (0)
styles = g.styles([(5, g.style(0, 3, 0x0000FF)), (9, g.style(1, 7, 0x00FF00))])
fills = g.fills([(2, g.fill(3, 0x112233)), (4, g.fill(-1, 0))])
root, lines, text = one(g.design(styles, fills,
    g.square3("SquareEx3", (0, 0), (10, 10), 9, 2), g.square3("CircleEx3", (0, 0), (10, 10), 5, 4), g.square2("SquareEx2", (1, 1), (11, 11), 5), g.square2("CircleEx2", (1, 1), (11, 11), 9),
    g.square3("SquareEx3", (2, 2), (12, 12), 77, 77)))
o = objs(root)
check("squares: tags and kinds", [e.tag for e in o] == ["RECTANGLE", "ELLIPSE", "RECTANGLE", "ELLIPSE", "RECTANGLE"], [e.tag for e in o])
check("squares: style and fill numbers are converted", [(e.get("style"), e.get("fill")) for e in o] == [("3", "2"), ("2", "0"), ("2", "0"), ("3", "0"), ("0", "0")], [(e.get("style"), e.get("fill")) for e in o])
check("squares: corners", near(fl(o[0].get("a")), P(0, 0)) and near(fl(o[0].get("b")), P(10, 10)) and near(fl(o[3].get("b")), P(11, 11)))
check("style table: thickness, colour, dash", style_of(root, 2) == (0, 3, "0000FF") and style_of(root, 3) == (1, 7, "00FF00"), (style_of(root, 2), style_of(root, 3)))
check("fill table: the second file fill equals fill 0 and takes its number", fill_of(root, 2) == (3, "112233") and fill_of(root, 0) == (-1, "000000"), (fill_of(root, 2), fill_of(root, 0)))
# old squares / circles: the style is made from a thickness; the circle forms read no thickness byte
root, lines, text = one(g.design(g.square_old("Square", (0, 0), (5, 5)), g.square_old("SquareEx", (0, 0), (5, 5), 4), g.square_old("SquareEx", (1, 1), (6, 6), 4),
    g.square_old("Circle", (1, 1), (6, 6)), g.square_old("CircleEx", (2, 2), (7, 7)), g.square_old("SquareEx", (3, 3), (8, 8), 9), g.wire((0, 0), (5, 0))))
o = objs(root)
check("old squares and circles: kinds", [e.tag for e in o] == ["RECTANGLE", "RECTANGLE", "RECTANGLE", "ELLIPSE", "ELLIPSE", "RECTANGLE", "WIRE"], [e.tag for e in o])
check("old squares: each thickness makes a style, equal ones share it", [e.get("style") for e in o[:6]] == ["2", "3", "3", "2", "2", "4"], [e.get("style") for e in o[:6]])
# (the document's own two styles have merge number 0, as CDocResource's constructor sets, so AddStyle, which only reuses an item with
#  merge number -1, never finds them: thickness 1 makes a new style too)
check("old squares: thickness made a solid black style", style_of(root, 2) == (0, 1, "000000") and style_of(root, 3) == (0, 4, "000000") and style_of(root, 4) == (0, 9, "000000"), (style_of(root, 2), style_of(root, 3)))
check("old squares: no fill", all(e.get("fill") == "0" for e in o[:6]))
check("old squares: the circle forms leave the next object in step", near(fl(o[6].get("b")), P(5, 0)), o[6].attrib)

# polygons, lines and arcs: every polygon's style is re-added as a copy, so it gets a number of its own (see the notes in the reader)
root, lines, text = one(g.design(styles, fills,
    g.polygon(1, (5, 5), [(0, 0, 0), (10, 0, 1), (10, 10, 2)], 9, 4), g.polygon(1, (6, 6), [(0, 0, 0), (10, 0, 3)], 9, 2), g.polygon(0, (7, 7), [(0, 0), (10, 5), (3, 3), (4, 4)], 5, 0),
    g.line2("LineEx2", (0, 1), (10, 1), g.u16(5)), g.line2("ArcEx2", (0, 2), (10, 2), g.u16(9)), g.line2("Line", (0, 3), (10, 3)), g.line2("Dash", (0, 4), (10, 4)), g.line2("Arc", (0, 5), (10, 5))))
o = objs(root)
check("polygons: all are POLYGON elements", all(e.tag == "POLYGON" for e in o) and len(o) == 8, [e.tag for e in o])
def pts(e): return [(fl(p.get("pos")), int(p.get("arc"))) for p in e.findall("POINT")]
check("polygon v1: points and arc kinds", pts(o[0]) == [((0.0, 0.0), 0), ((2.0, 0.0), 1), ((2.0, 2.0), 2)] and near(fl(o[0].get("pos")), P(5, 5)), pts(o[0]))
check("polygon v1: arc kind 3 (control, no control point in the file) becomes a plain corner and converts without error", [a for _, a in pts(o[1])] == [0, 0], pts(o[1]))
check("polygon v0: points have no arc kind", pts(o[2]) == [((0.0, 0.0), 0), ((2.0, 1.0), 0), ((0.6, 0.6), 0), ((0.8, 0.8), 0)], pts(o[2]))
check("polygon: fill numbers converted (4 -> 0, 2 -> 2, 0 -> 0)", [o[0].get("fill"), o[1].get("fill"), o[2].get("fill")] == ["0", "2", "0"], [e.get("fill") for e in o[:3]])
# styles after re-adding: file style 9 (1,7,green) is table number 3 -> a copy is added as 4 (shared by the next one); file style 5 (0,3,blue) -> copy 5; defaults 0 / 1 are not claimed so a copy of the default line style finds style 0
check("polygon styles: copies of the file styles", [o[0].get("style"), o[1].get("style"), o[2].get("style")] == ["4", "4", "5"], [e.get("style") for e in o[:3]])
check("polygon style copies have the file styles' contents", style_of(root, 4) == (1, 7, "00FF00") and style_of(root, 5) == (0, 3, "0000FF"), (style_of(root, 4), style_of(root, 5)))
check("LineEx2 / ArcEx2: style from the file (converted, then copied)", o[3].get("style") == "5" and o[4].get("style") == "4", (o[3].get("style"), o[4].get("style")))
check("lines: two points, no fill", pts(o[3]) == [((0.0, 0.0), 0), ((2.0, 0.0), 0)] and o[3].get("fill") == "0" and near(fl(o[3].get("pos")), P(0, 1)), (pts(o[3]), o[3].attrib))
check("ArcEx2: the second point is an arc end (kind 2)", [a for _, a in pts(o[4])] == [0, 2], pts(o[4]))
check("Line, Dash, Arc keep the default styles (line 0, dash 1)", [o[5].get("style"), o[6].get("style"), o[7].get("style")] == ["0", "1", "0"], [e.get("style") for e in o[5:]])
check("Arc (plain) has no arc kind on its end", [a for _, a in pts(o[7])] == [0, 0], pts(o[7]))
check("polygons are not closed", all(e.get("polygon") == "0" for e in o[:3]), [e.get("polygon") for e in o])
# old thickness bytes on LineEx and ArcEx: the thickness is kept
root, lines, text = one(g.design(g.line2("LineEx", (0, 0), (10, 0), g.u8(4)), g.line2("ArcEx", (0, 1), (10, 1), g.u8(6)), g.line2("LineEx", (0, 2), (10, 2), g.u8(4)), g.line2("LineEx", (0, 3), (10, 3), g.u8(1))))
o = objs(root)
th = [style_of(root, e.get("style"))[:2] for e in o]
check("old line and arc thickness is kept", th == [(0, 4), (0, 6), (0, 4), (0, 1)], th)
check("equal old thicknesses share a style", o[0].get("style") == o[2].get("style"), [e.get("style") for e in o])
check("old arc end is an arc", [a for _, a in pts(o[1])] == [0, 2], pts(o[1]))

# note text
root, lines, text = one(g.design(g.fonts([(7, g.font("Arial", -30))]), styles, fills, g.notetext((0, 0), (50, 20), 3, 5, 2, 7, 0x123456, 1), g.notetext((5, 5), (60, 30), 0, 9, 4, 99, 0xABCDEF, 2, version=3)))
o = objs(root)
check("note text", [(e.tag, e.get("direction"), e.get("style"), e.get("fill"), e.get("font"), e.get("color"), e.get("border_style"), e.text) for e in o] ==
      [("NOTE_TEXT", "3", "2", "2", "3", "123456", "1", "Note"), ("NOTE_TEXT", "0", "3", "0", "0", "ABCDEF", "2", "Note")], [e.attrib for e in o])
check("note text: corner a", near(fl(o[0].get("a")), P(0, 0)) and near(fl(o[1].get("a")), P(5, 5)))

# pictures (enhanced metafiles are kept as they are)
data1 = bytes(range(256)) * 2 + b"EMF"; data2 = b"second picture"
root, lines, text = one(g.design(g.metafiles([(3, data1), (8, data2), (9, b"")]), g.metafile_obj((0, 0), (50, 50), 8), g.metafile_obj((5, 5), (55, 55), 3), g.metafile_obj((6, 6), (56, 56), 77), g.metafile_obj((7, 7), (57, 57), 9)))
o = objs(root); imgs = {e.get("id"): e for e in sheet(root).findall("IMAGE")}
check("pictures: objects", [e.tag for e in o] == ["METAFILE"] * 4 and near(fl(o[0].get("a")), P(0, 0)) and near(fl(o[0].get("b")), P(50, 50)), [e.attrib for e in o])
def img_bytes(e): u = e.find("UUENCODE"); return uu_decode((u.text or "").replace("\r", ""), int(u.get("size")))
ids = [e.get("id") for e in o]
check("pictures: renumbered (3 -> 1, 8 -> 2, 9 -> 3, unknown -> 0)", ids == ["2", "1", "0", "3"], ids)
check("pictures: contents and type", img_bytes(imgs["1"]) == data1 and img_bytes(imgs["2"]) == data2 and imgs["1"].get("type") == "METAFILE" and imgs["2"].get("type") == "METAFILE", (imgs["1"].attrib, imgs["2"].attrib))

# =============================================================== symbols
sq3 = g.square3("SquareEx3", (0, 0), (40, 40), 9, 0)
symA = g.symbol_def("OPAMP", "Op amp", "U?", 2, [("Package", "DIP8", "dip", (5, 6), 1), ("Gain", "10", "1", (15, 16), 0x20003)],
                    [g.pin_old((0, 0), 0, 1, 3, 0, "IN", "1", 3), g.pin((10, 10), 1, 2, 2, 1, "OUT", "7", 1, 60), sq3, g.label("LabelEx2", (3, 3), 3, "sym", 0, 0x123456)], name_type=1, ref_type=2)
symB = g.symbol_def("RES", "Resistor", "R?", 1, [], [g.pin((0, 0), 0, 0, 3, 0, "1", "1", 3, 30), g.pin((30, 0), 0, 0, 2, 0, "2", "2", 3, 30)], name_type=5, ref_type=3)
sym_table = g.symbols([(5, symA), (8, symB)])
meth = lambda sid, p=(100, 100), part=0, rot=3: g.method(sid, p, part, rot, 1, 1.5, 2.0, [(0, "Ref", "U1", 1, (1, 2)), (1, "Name", "OPAMP", 0, (3, 4)), (3, "Extra", "val", 1, (-5, 6))])
root, lines, text = one(g.design(styles, sym_table, meth(8), meth(5, (200, 100), 1, 7), meth(9, (300, 100))))
o = objs(root)
check("placed symbols: tags", [e.tag for e in o] == ["SYMBOL"] * 3, [e.tag for e in o])
check("placed symbols: symbol numbers are converted (8 -> 2, 5 -> 1, 9 -> 0)", [e.get("id") for e in o] == ["2", "1", "0"], [e.get("id") for e in o])
check("placed symbol: position, part, rotate, scaling", near(fl(o[1].get("pos")), P(200, 100)) and (o[1].get("part"), o[1].get("rotate"), o[1].get("can_scale"), o[1].get("scale_x"), o[1].get("scale_y")) == ("1", "7", "1", "1.50000", "2.00000"), o[1].attrib)
fs = o[0].findall("FIELD")
check("placed symbol: fields", [(f.get("type"), f.get("description"), f.get("value"), f.get("show")) for f in fs] == [("0", "Ref", "U1", "1"), ("1", "Name", "OPAMP", "0"), ("3", "Extra", "val", "1")] and near(fl(fs[2].get("pos")), P(-5, 6)) and near(fl(fs[0].get("pos")), P(1, 2)), [f.attrib for f in fs])
sd = table(root, "SYMBOLDEF")
check("symbol table: used symbols are saved under their new numbers (0 is the stand-in the unknown number 9 maps to)", sorted(sd) == ["0", "1", "2"], sorted(sd))
a = sd["1"]
check("symbol: name, reference, description, parts, display types", (a.findtext("NAME"), a.find("NAME").get("type"), a.findtext("REF"), a.find("REF").get("type"), a.findtext("DESCRIPTION"), a.findtext("PPP")) == ("OPAMP", "1", "U?", "2", "Op amp", "2"), ET.tostring(a)[:300])
check("symbol: name and reference display types are in the high bits (5, 3 -> 43)", (sd["2"].find("NAME").get("type"), sd["2"].find("REF").get("type")) == ("5", "3"), (sd["2"].find("NAME").attrib, sd["2"].find("REF").attrib))
af = a.findall("FIELD")
check("symbol: fields", [(f.findtext("NAME"), f.findtext("VALUE"), f.findtext("DEFAULT"), f.findtext("FT")) for f in af] == [("Package", "DIP8", "dip", "000001"), ("Gain", "10", "1", "020003")] and near(fl(af[0].findtext("POS")), P(5, 6)), [ET.tostring(f)[:200] for f in af])
inner = a.find("TinyCAD"); ic = [e.tag for e in inner]
check("symbol drawing: objects in order", ic == ["PIN", "PIN", "RECTANGLE", "LABEL"], ic)
p0, p1, r0, l0 = list(inner)
check("symbol drawing: pins", pinfo(p0)[:7] == ("0", "1", "3", "0", "1", "3", "30") and pinfo(p1)[:7] == ("1", "2", "2", "1", "7", "1", "60") and near(fl(p1.get("pos")), P(10, 10)), (pinfo(p0), pinfo(p1)))
check("symbol drawing: the rectangle's style number is converted with the sheet's table (file 9 -> 3)", r0.get("style") == "3" and style_of(root, 3) == (1, 7, "00FF00"), r0.attrib)
check("symbol drawing: label colour", l0.get("color") == "123456" and l0.text == "sym", l0.attrib)
check("the nested drawing's end tag does not end the file", [e.tag for e in objs(root)].count("SYMBOL") == 3)
# a symbol that is never placed is still in the table but not saved; the field-count string may have blanks and trailing text
odd = g.u8(g.X["Symbols"]) + g.u16(1) + g.i16(4) + g.s("ODD") + g.s("d") + g.s("R?") + g.u8(1) + g.s("  1x") + g.s("F") + g.s("v") + g.s("dv") + g.pt(5, 5) + g.u32(2) + g.design(g.pin((0, 0), 0, 0, 3, 0, "1", "1", 3, 30))
root, lines, text = one(g.design(odd, g.method(4, (10, 10), 0, 0, 0, 1.0, 1.0, [])))
sd = table(root, "SYMBOLDEF")
check("symbol field-count string: blanks, then digits, then ignored text", root is not None and list(sd) == ["1"] and len(sd["1"].findall("FIELD")) == 1 and sd["1"].find("FIELD").findtext("FT") == "000002", text if root is None else ET.tostring(sd["1"])[:200])
root, lines, text = one(g.design(g.u8(g.X["Symbols"]) + g.u16(1) + g.i16(4) + g.s("Z") + g.s("d") + g.s("R?") + g.u8(1) + g.s("") + g.design(g.pin((0, 0), 0, 0, 3, 0, "1", "1", 3, 30)), g.method(4, (10, 10), 0, 0, 0, 1.0, 1.0, [])))
check("symbol with an empty field-count string has no fields", root is not None and len(table(root, "SYMBOLDEF")["1"].findall("FIELD")) == 0, text)
# symbols inside symbols
deep = lambda n: g.design(g.pin((0, 0), 0, 0, 3, 0, "1", "1", 3, 30)) if n == 0 else g.design(g.symbols([(1, g.symbol_def("N%d" % n, "", "X?", 1, [], [g.pin((0, 0), 0, 0, 3, 0, "1", "1", 3, 30)]) )]) if False else g.pin((0, 0), 0, 0, 3, 0, "1", "1", 3, 30))
nest = lambda n: (g.pin((0, 0), 0, 0, 3, 0, "1", "1", 3, 30) if n == 0 else g.symbols([(1, g.symbol_def("N", "", "X?", 1, [], [nest(n - 1)]))]))
root, lines, text = one(g.design(nest(3), g.method(1, (10, 10), 0, 0, 0, 1.0, 1.0, [])))
check("a symbol that holds a symbol table reads on", root is not None and objs(root)[0].tag == "SYMBOL", text)
root, lines, text = one(g.design(nest(40), g.method(1, (10, 10), 0, 0, 0, 1.0, 1.0, [])))
check("symbols nested without end stop the load with a note instead of running out of stack", root is None or note_of(lines) not in (None, ""), (lines[:3], text[-200:]))
# a symbol drawing saved as XML inside a binary file cannot be followed
xmlsym = g.u8(g.X["Symbols"]) + g.u16(1) + g.i16(4) + g.s("X") + g.s("d") + g.s("R?") + g.u8(1) + g.s("0") + b"<TinyCAD><PIN pos='0,0'/></TinyCAD>"
root, lines, text = one(g.design(g.wire((0, 0), (5, 5)), xmlsym, g.junction((9, 9))))
check("an XML symbol inside a binary design: the objects before it are kept and the user is told", root is not None and [e.tag for e in objs(root)] == ["WIRE"] and "XML" in (note_of(lines) or ""), (lines, text[-200:]))

# old symbol objects: the number-less forms look the symbol up by name in the libraries (a stand-in finds RES and CAP in these tests)
oldm = lambda kind, name, **kw: g.method_old(kind, name, ("N-" + name, "oth", "R1"), [(1, 2), (3, 4), (5, 6)], 5, 2, (100, 50), 1, "attr" if kind == "MethodEx" else None)
root, lines, text = one(g.design(oldm("Method", "RES"), oldm("MethodEx", "CAP"), oldm("Method", "res"), oldm("Method", "RES"), oldm("Method", "XYZ")), finder=True)
o = objs(root)
check("old symbol objects found by name", root is not None and [e.get("id") for e in o] == ["1", "2", "1", "1", "0"], [e.get("id") for e in o] if root is not None else text)
sdn = table(root, "SYMBOLDEF")
check("old symbols found by name are kept with the design", sorted(sdn) == ["0", "1", "2"] and sdn["1"].findtext("NAME") == "RES" and sdn["1"].findtext("DESCRIPTION") == "found RES" and sdn["2"].findtext("NAME") == "CAP", sorted(sdn))
fs = o[0].findall("FIELD")
check("old symbol object: fields are Ref, Name, Other (file order is Name, Other, Ref)", [(f.get("description"), f.get("value"), f.get("type")) for f in fs] == [("Ref", "R1", "0"), ("Name", "N-RES", "0"), ("Other", "oth", "1")], [f.attrib for f in fs])
check("old symbol object: positions Name, Other, Ref and shows byte 5 (name and reference shown)", [fl(f.get("pos")) for f in fs] == [P(5, 6), P(1, 2), P(3, 4)] and [f.get("show") for f in fs] == ["1", "1", "0"], ([f.attrib for f in fs]))
check("old symbol object: rotation, position, part, scaling", near(fl(o[0].get("pos")), P(100, 50)) and (o[0].get("rotate"), o[0].get("part"), o[0].get("scale_x"), o[0].get("can_scale")) == ("2", "1", "1.00000", "0"), o[0].attrib)
check("old symbol objects: one note for the name that was not found", "XYZ" in (note_of(lines) or ""), note_of(lines))
root, lines, text = one(g.design(oldm("Method", "RES")))
check("without libraries an old symbol object shows the no-symbol stand-in and says so", root is not None and objs(root)[0].get("id") == "0" and "RES" in (note_of(lines) or ""), (lines, text[-200:]))
# MethodEx2: symbol number, scaling in the special fields
sp = lambda name, val: (name, val, "", (0, 0), 0)
m2 = g.method_ex2(8, ("Nm", "Ot", "Rf"), [(1, 1), (2, 2), (3, 3)], 2, 1, (10, 10), 2, [sp("SCALING_X", "2.5abc"), sp("OTHER", "9"), sp("SCALING_Y", "-0.5e1")], "attrib")
m3 = g.method_ex2(5, ("Nm", "Ot", "Rf"), [(1, 1), (2, 2), (3, 3)], 7, 0, (10, 10), 0, [sp("SCALING_X", "abc"), sp("SCALING_Y", " 3")])
m4 = g.method_ex2(5, ("Nm", "Ot", "Rf"), [(1, 1), (2, 2), (3, 3)], 0, 0, (10, 10), 0, [])
root, lines, text = one(g.design(styles, sym_table, m2, m3, m4))
o = objs(root)
check("MethodEx2: symbol converted, scaling from the special fields (atof)", root is not None and (o[0].get("id"), o[0].get("scale_x"), o[0].get("scale_y")) == ("2", "2.50000", "-5.00000"), [e.attrib for e in o] if root is not None else text)
check("MethodEx2: unreadable scaling is 0, a leading blank is skipped; default is 1", (o[1].get("scale_x"), o[1].get("scale_y"), o[2].get("scale_x"), o[2].get("scale_y")) == ("0.00000", "3.00000", "1.00000", "1.00000"), [e.attrib for e in o])
check("MethodEx2: shows byte (2 = other only)", [f.get("show") for f in o[0].findall("FIELD")] == ["0", "0", "1"] and [f.get("show") for f in o[1].findall("FIELD")] == ["1", "1", "1"], [[f.get("show") for f in e.findall("FIELD")] for e in o])
check("MethodEx2: values", [(f.get("description"), f.get("value")) for f in o[0].findall("FIELD")] == [("Ref", "Rf"), ("Name", "Nm"), ("Other", "Ot")], [f.attrib for f in o[0].findall("FIELD")])
# MethodEx3 fields: counts of 0, 1 and many; the extra field list is replaced as it is
root, lines, text = one(g.design(sym_table, g.method(5, (10, 10), 0, 0, 0, 1.0, 1.0, []), g.method(5, (20, 10), 0, 0, 0, 1.0, 1.0, [(2, "A", "b", 1, (1, 1))]),
                                 g.method(5, (30, 10), 3, 255, 1, 0.25, -2.0, [(i % 7, "F%d" % i, "v%d" % i, i % 2, (i, -i)) for i in range(12)])))
o = objs(root)
check("MethodEx3: field counts 0, 1, 12", [len(e.findall("FIELD")) for e in o] == [0, 1, 12], [len(e.findall("FIELD")) for e in o] if root is not None else text)
check("MethodEx3: fields in order", [(f.get("type"), f.get("description"), f.get("value"), f.get("show")) for f in o[2].findall("FIELD")] == [(str(i % 7), "F%d" % i, "v%d" % i, str(i % 2)) for i in range(12)])
check("MethodEx3: scaling and rotation", (o[2].get("rotate"), o[2].get("part"), o[2].get("scale_x"), o[2].get("scale_y"), o[2].get("can_scale")) == ("255", "3", "0.25000", "-2.00000", "1"), o[2].attrib)

# =============================================================== the file ends early, damaged files
big = g.design(g.details_ex(1485, 1050, "Title", "Me", "1", "D", "O", "1 of 1", 3, "1 Jan 2000"), g.options(0, 0, 1, 0, 0),
               g.fonts([(7, courier)]), styles, fills, sym_table,
               g.wire((10, 20), (30, 20)), g.label("LabelEx2", (5, 5), 3, "hello", 7, 0x112233), g.text("TextEx2", (9, 9), 0, "text", 7, 0x445566), g.pin((14, 14), 0, 3, 2, 1, "PB", "2", 3, 40),
               g.polygon(1, (5, 5), [(0, 0, 0), (10, 0, 1), (10, 10, 2)], 9, 2), g.square3("SquareEx3", (0, 0), (10, 10), 9, 2), g.line2("LineEx", (0, 0), (10, 0), g.u8(4)),
               meth(8), g.junction((30, 20)), g.noconnect((31, 21)), g.power((60, 60), 2, 0, "VCC"))
def objkey(e): return re.sub(rb"\s+", b" ", ET.tostring(e)).strip()
root_full, lines_full, text_full = one(big)
check("the big file loads in full", root_full is not None and note_of(lines_full) == "" and len(objs(root_full)) == 11, text_full)
full = [objkey(e) for e in objs(root_full)]
res_cuts = 0; bad = []
for cut in range(11, len(big), 1 if len(big) < 900 else 3):
    rc, lines, root, text = conv(big[:cut])
    if rc != 0:
        if not ("no objects" in text): bad.append((cut, text[-120:]))
        continue
    got = [objkey(e) for e in objs(root)]
    note = note_of(lines)
    if got != full[:len(got)] or len(got) > len(full): bad.append((cut, "objects are not a prefix of the full set", len(got)))
    if not note: bad.append((cut, "no note for a file that ends early"))
    res_cuts += 1
check("every cut of a file loads a prefix of its objects (or reports no objects) and says the file ended early", not bad and res_cuts > 200, (bad[:4], res_cuts))
# the objects kept grow with the length
prev = -1; mono = True
for cut in range(11, len(big), 7):
    rc, lines, root, text = conv(big[:cut])
    n = len(objs(root)) if root is not None else 0
    if n < prev: mono = False
    prev = n
check("more of the file never gives fewer objects", mono)
# lengths and counts that cannot fit in the file are refused before anything is allocated
huge_text = g.u8(g.X["Label"]) + g.pt(5, 5) + g.u8(3) + b"\xff\xff\xff" + g.u32(0x7FFFFFF0) + b"abc"
root, lines, text = one(g.design(g.wire((0, 0), (5, 5)), huge_text))
check("a text claiming 2 GB: the objects before it are kept and the file is said to end early", root is not None and [e.tag for e in objs(root)] == ["WIRE"] and "ended early" in (note_of(lines) or ""), text)
huge_text = g.u8(g.X["Label"]) + g.pt(5, 5) + g.u8(3) + b"\xff\xfe\xff\xff\xff\xff\xff" + g.u32(0x7FFFFFF0) + b"abc"
root, lines, text = one(g.design(g.wire((0, 0), (5, 5)), huge_text))
check("a UTF-16 text claiming 4 GB is refused the same way", root is not None and [e.tag for e in objs(root)] == ["WIRE"] and "ended early" in (note_of(lines) or ""), text)
bad_method = g.u8(g.X["MethodEx3"]) + g.i32(1) + g.i16(1) + g.pt(10, 10) + g.u8(0) + g.u8(0) + g.i32(0) + g.f64(1.0) + g.f64(1.0) + g.i32(0x7FFFFFFF)
root, lines, text = one(g.design(g.wire((0, 0), (5, 5)), bad_method))
check("a placed symbol claiming 2 billion fields is refused the same way", root is not None and [e.tag for e in objs(root)] == ["WIRE"] and "ended early" in (note_of(lines) or ""), text)
# damaged files: no crash, no hang
rnd = random.Random(20260211); crashes = []
for k in range(160):
    d = bytearray(big)
    for _ in range(rnd.choice((1, 2, 3, 6))): d[rnd.randrange(11, len(d))] = rnd.randrange(256)
    try:
        rc, lines, root, text = conv(bytes(d), True, timeout=20)
    except subprocess.TimeoutExpired:
        crashes.append((k, "timeout")); continue
    if rc not in (0, 1) or "Runtime error" in text or "Exception" in text.replace("ERROR EXMLException", "").replace("ERROR Exception", "") and rc != 1:
        crashes.append((k, rc, text[-160:]))
check("160 files with random bytes changed: always a result or a clean error", not crashes, crashes[:3])
crashes = []
for k in range(120):
    tail = bytes(rnd.randrange(256) for _ in range(rnd.randrange(1, 300)))
    try:
        rc, lines, root, text = conv(g.stamp() + tail, True, timeout=20)
    except subprocess.TimeoutExpired:
        crashes.append((k, "timeout")); continue
    if rc not in (0, 1) or "Runtime error" in text:
        crashes.append((k, rc, text[-160:]))
check("120 files of a stamp and random bytes: always a result or a clean error", not crashes, crashes[:3])
# claims bigger than the file
for name, data in (("a string longer than the file", g.stamp() + g.u8(g.X["Label"]) + g.pt(0, 0) + g.u8(3) + b"\xff\xff\xff\xff\xff\xff\xff"),
                   ("a polygon with 4 billion points", g.stamp() + g.u8(g.X["Polygon"]) + g.u32(1) + g.u32(0xFFFFFFFF) + g.pt(0, 0) + g.pt(1, 1) + g.i32(0)),
                   ("a symbol with 4 billion fields", g.stamp() + g.u8(g.X["MethodEx3"]) + g.i32(1) + g.i16(0) + g.pt(0, 0) + g.u8(0) + g.u8(0) + g.i32(0) + g.f64(1) + g.f64(1) + g.i32(-1)),
                   ("a picture of 4 billion bytes", g.stamp() + g.u8(g.X["MetaFiles"]) + g.u16(1) + g.i16(1) + g.u32(0xFFFFFFF0)),
                   ("65535 fonts announced, none present", g.stamp() + g.u8(g.X["Font"]) + g.u16(65535))):
    try:
        rc, lines, root, text = conv(data)
        check("claims more than the file holds: " + name, rc in (0, 1) and "Runtime error" not in text, (rc, text[-200:]))
    except subprocess.TimeoutExpired:
        check("claims more than the file holds: " + name, False, "timeout")

# =============================================================== in the program
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("(program checks skipped: need xvfb-run and the built program)")
else:
    exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
    home = os.path.join(tmp, "home"); os.makedirs(home, exist_ok=True)
    src = os.path.join(tmp, "Old_Design.dsn"); open(src, "wb").write(g.design(g.details_ex(1485, 1050, "Old", "me", "1", "", "", "1 of 1", 1, "1 Jan 2000"), g.wire((10, 20), (30, 20)), g.label("Label", (5, 5), 3, "NET1"), g.junction((30, 20))))
    outx = os.path.join(tmp, "saved.dsn")
    script = os.path.join(tmp, "script.txt")
    open(script, "w").write("open %s\ninfo\nopen %s\nsave %s\n" % (src, src, outx))
    env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", script], capture_output=True, text=True, timeout=200, env=env)
    out = r.stdout.split("\n")
    opens = [l for l in out if l.startswith("OPEN ")]
    check("program: the old design opens", len(opens) == 2 and "sheets=1" in opens[0], (out[-12:], r.stderr[-300:]))
    if opens:
        check("program: it is a converted, unsaved document named after the original", "converted=1" in opens[0] and "name=[Old_Design.dsn (converted)]" in opens[0] and "modified=1" in opens[0], opens[0])
        check("program: the status line says what happened", "old binary design Old_Design.dsn" in opens[0] and "Save As" in opens[0], opens[0])
    if len(opens) == 2:
        check("program: opening the same file again shows the open document", "converted=1" in opens[1] and "name=[Old_Design.dsn (converted)]" in opens[1], opens[1])
    info = [l for l in out if l.startswith("INFO ")]
    check("program: the design has its objects", info and "objects=3" in info[0], info)
    if os.path.exists(outx):
        rt = ET.parse(outx).getroot(); check("program: saved as XML with the same objects", [e.tag for e in rt.find("TinyCAD") if e.tag in ("WIRE", "LABEL", "JUNCTION")] == ["WIRE", "LABEL", "JUNCTION"])
    else:
        check("program: saved file written", False, out[-6:])
    check("program: the original file is untouched", open(src, "rb").read() == g.design(g.details_ex(1485, 1050, "Old", "me", "1", "", "", "1 of 1", 1, "1 Jan 2000"), g.wire((10, 20), (30, 20)), g.label("Label", (5, 5), 3, "NET1"), g.junction((30, 20))))

print("%d checks, %d failed" % (checks, len(fails)))
if fails: print("FAILED:", ", ".join(fails[:20])); sys.exit(1)
