"""Hierarchical designs, step 1: they are read and written back without losing anything (TinyCAD's CDrawHierarchicalSymbol,
CTinyCadHierarchicalDoc and CTinyCadDoc::formatXMLFilename / unformatXMLFilename). Checked against statements written from the C++
source and Python's own path functions, never against the Pascal:
  - file names inside a design: read as full names from the design's folder (backslashes, '.', '..', Windows drive names) and written
    relative to the folder of the file being saved (".\\x.dsn", "..\\lib\\x.dsn"), 400 random cases against posixpath
  - the HierarchicalSymbol sheet (and its old misspelling HierachicalSymbol): kept as a sheet of its own, saved under the right tag,
    always named "Hierarchical Symbol"; the sheets around it unchanged
  - the HIERARCHICAL_SYMBOL object (and HIERACHICAL_SYMBOL): position, rotation, scaling, file, every field, defaults for what is missing,
    the Name field's value written empty, the design's file name written relative to the new folder
  - in the program: the placed design is selected, copied, pasted, moved with undo, saved and read again; the netlist passes it by; the
    hierarchical sheet cannot be renamed
Needs the built hiertest (tests/drivers) and, for the last group, the built program and xvfb."""
import os, posixpath, random, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.environ.get("TC_BUILD", "build")
HT = os.path.join(BUILD, "hiertest")
if not os.path.exists(HT):
    print("Hierarchical checks skipped: build tests/drivers/hiertest.pas first", HT); sys.exit(0)
tmp = tempfile.mkdtemp()
fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name)
        if len(fails) <= 25: print("  FAIL", name, str(detail)[:700])
def ht(*args):
    r = subprocess.run([HT] + list(args), capture_output=True, text=True, timeout=60)
    return r.stdout, r.returncode
def result(out):
    m = re.search(r"RESULT \[(.*)\]", out); return m.group(1) if m else None

# ======================================================================= 1. file names (the oracle is posixpath)
DRIVE = re.compile(r"^([A-Za-z]:[\\/]|\\\\)")
def want_unformat(design, name):
    if name == "": return ""
    if DRIVE.match(name): return name                      # a Windows drive name means nothing here: kept as it is
    n = name.replace("\\", "/")
    if n.startswith("/"): return posixpath.normpath(n)
    if design is None: return n
    return posixpath.normpath(posixpath.join(posixpath.dirname(design), n))
def want_format(design, name):
    if name == "": return ""
    if design is None or DRIVE.match(name): return name.replace("/", "\\")
    rel = posixpath.relpath(posixpath.normpath(name), posixpath.dirname(design))
    if not rel.startswith(".."): rel = "./" + rel
    return rel.replace("/", "\\")
def un(design, name):
    out, rc = ht("unformat", design or "-", name); return result(out)
def fmt(design, name):
    out, rc = ht("format", design or "-", name); return result(out)
D1 = "/work/proj/main.dsn"
for name, exp in [(".\\child.dsn", "/work/proj/child.dsn"), ("child.dsn", "/work/proj/child.dsn"), ("..\\lib\\c.dsn", "/work/lib/c.dsn"),
                  ("sub\\deeper\\c.dsn", "/work/proj/sub/deeper/c.dsn"), ("..\\..\\x.dsn", "/x.dsn"), ("..\\..\\..\\x.dsn", "/x.dsn"),
                  (".\\sub\\..\\c.dsn", "/work/proj/c.dsn"), ("a//b\\c.dsn", "/work/proj/a/b/c.dsn"), ("/abs/dir/c.dsn", "/abs/dir/c.dsn"),
                  ("\\abs\\dir\\..\\c.dsn", "/abs/c.dsn"), ("C:\\Designs\\c.dsn", "C:\\Designs\\c.dsn"), ("D:/Designs/c.dsn", "D:/Designs/c.dsn"),
                  ("\\\\server\\share\\c.dsn", "\\\\server\\share\\c.dsn"), ("", ""), ("name with spaces.dsn", "/work/proj/name with spaces.dsn")]:
    check("unformat %r" % name, un(D1, name) == exp, (un(D1, name), exp))
    check("unformat oracle agrees %r" % name, want_unformat(D1, name) == exp, (want_unformat(D1, name), exp))
check("unformat with no design file: only the separators change", un(None, ".\\a\\b.dsn") == "./a/b.dsn" and un(None, "/x/y.dsn") == "/x/y.dsn", (un(None, ".\\a\\b.dsn"), un(None, "/x/y.dsn")))
for name, exp in [("/work/proj/child.dsn", ".\\child.dsn"), ("/work/lib/c.dsn", "..\\lib\\c.dsn"), ("/work/proj/sub/c.dsn", ".\\sub\\c.dsn"), ("/x.dsn", "..\\..\\x.dsn"),
                  ("/work/proj/../proj/c.dsn", ".\\c.dsn"), ("C:\\Designs\\c.dsn", "C:\\Designs\\c.dsn"), ("", "")]:
    check("format %r" % name, fmt(D1, name) == exp, (fmt(D1, name), exp))
check("format with no design file: written whole, with backslashes", fmt(None, "/x/y.dsn") == "\\x\\y.dsn", fmt(None, "/x/y.dsn"))
rnd = random.Random(31415); bad = []
parts = ["a", "b", "c d", "lib", "x.y", "..", ".", "..", "sub"]
for k in range(400):
    design = "/" + "/".join(rnd.choice(["w", "proj", "p q", "z"]) for _ in range(rnd.randint(1, 4))) + "/main.dsn"
    rel = "\\".join(rnd.choice(parts) for _ in range(rnd.randint(0, 4)) ) 
    name = (rel + "\\" if rel else "") + rnd.choice(["f.dsn", "g h.dsn"])
    if rnd.random() < 0.2: name = ".\\" + name
    got = un(design, name); exp = want_unformat(design, name)
    if got != exp: bad.append(("unformat", design, name, got, exp)); continue
    if got.startswith("/") and got != "/":
        back = fmt(design, got); e2 = want_format(design, got)
        if back != e2: bad.append(("format", design, got, back, e2))
check("400 random names read and written back (against posixpath)", not bad, bad[:3])
check("display name is the part after the last backslash or slash", [result(ht("display", n)[0]) for n in ("a\\b\\c.dsn", "/x/y/z.dsn", "plain.dsn", "")] == ["c.dsn", "z.dsn", "plain.dsn", ""])

# ======================================================================= 2. the sheets
def doc(*sheets):
    return '<?xml version="1.0" encoding="UTF-8"?>\n<TinyCADSheets>\n' + "\n".join(sheets) + "\n</TinyCADSheets>\n"
def sheet(tag, name, body, w=1485, h=1050):
    return "<%s><NAME>%s</NAME><DETAILS><Size width=\"%d\" height=\"%d\"/></DETAILS>%s</%s>" % (tag, name, w, h, body, tag)
WIRE = '<WIRE a="1,1" b="5,1"/>'
def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True); open(path, "w", encoding="utf-8").write(text)
def convert(src, dst, *extra):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    out, rc = ht("convert", src, dst, *extra)
    root = None
    if rc == 0 and os.path.exists(dst):
        try: root = ET.parse(dst).getroot()
        except ET.ParseError: root = None
    return out, rc, root
def sheets_of(root): return [(e.tag, e.findtext("NAME")) for e in root]
w1 = os.path.join(tmp, "p", "w1.dsn")
for tag in ("HierarchicalSymbol", "HierachicalSymbol"):
    write(w1, doc(sheet(tag, "Whatever", WIRE + '<PIN pos="0,0" direction="3"/>'), sheet("TinyCAD", "Top", WIRE), sheet("TinyCAD", "Second", WIRE)))
    out, rc, root = convert(w1, os.path.join(tmp, "o", "w1.dsn"))
    check("%s: loads, first sheet flagged, the others not" % tag, rc == 0 and "SHEET 0 hier=1" in out and "SHEET 1 hier=0" in out and "SHEET 2 hier=0" in out, out)
    check("%s: always named Hierarchical Symbol (the file's name is ignored)" % tag, "name=[Hierarchical Symbol]" in out and "name=[Top]" in out and "name=[Second]" in out, out)
    check("%s: saved as HierarchicalSymbol (the old spelling is corrected), named, with its objects" % tag, root is not None and sheets_of(root) == [("HierarchicalSymbol", "Hierarchical Symbol"), ("TinyCAD", "Top"), ("TinyCAD", "Second")], sheets_of(root) if root is not None else out)
    if root is not None:
        hs = root[0]
        check("%s: the objects of the sheet are kept" % tag, [e.tag for e in hs if e.tag in ("WIRE", "PIN")] == ["WIRE", "PIN"], [e.tag for e in hs])
        check("%s: its details are kept" % tag, hs.find("DETAILS/Size").get("width") == "1485")
# a file whose hierarchical sheet comes after the others keeps the order
write(w1, doc(sheet("TinyCAD", "A", WIRE), sheet("HierarchicalSymbol", "x", WIRE), sheet("TinyCAD", "B", WIRE)))
out, rc, root = convert(w1, os.path.join(tmp, "o", "w2.dsn"))
check("sheet order is kept", root is not None and sheets_of(root) == [("TinyCAD", "A"), ("HierarchicalSymbol", "Hierarchical Symbol"), ("TinyCAD", "B")], sheets_of(root) if root is not None else out)
# the name is the sheet's own business: even a hierarchical sheet that something renamed is saved as Hierarchical Symbol, a normal one under its name
write(w1, doc(sheet("HierarchicalSymbol", "x", WIRE), sheet("TinyCAD", "T", WIRE)))
out, rc, root = convert(w1, os.path.join(tmp, "o", "w5.dsn"), "rename")
check("a renamed hierarchical sheet is still saved as Hierarchical Symbol", root is not None and sheets_of(root)[0] == ("HierarchicalSymbol", "Hierarchical Symbol"), sheets_of(root) if root is not None else out)
write(w1, doc(sheet("TinyCAD", "T", WIRE), sheet("HierarchicalSymbol", "x", WIRE)))
out, rc, root = convert(w1, os.path.join(tmp, "o", "w6.dsn"), "rename")
check("... and a normal sheet that is renamed is saved under its new name", root is not None and sheets_of(root)[0] == ("TinyCAD", "Other"), sheets_of(root) if root is not None else out)
# a design with only a hierarchical sheet, and a hierarchical sheet with nothing in it
write(w1, doc(sheet("HierarchicalSymbol", "x", "")))
out, rc, root = convert(w1, os.path.join(tmp, "o", "w3.dsn"))
check("an empty hierarchical sheet is kept", rc == 0 and root is not None and sheets_of(root) == [("HierarchicalSymbol", "Hierarchical Symbol")], out)
# resources of the hierarchical sheet are its own
write(w1, doc(sheet("HierarchicalSymbol", "x", '<FONT id="7"><HEIGHT>-33</HEIGHT><WIDTH>0</WIDTH><WEIGHT>400</WEIGHT><ITALIC>0</ITALIC><UNDERLINE>0</UNDERLINE><STRIKEOUT>0</STRIKEOUT><CHARSET>0</CHARSET><FACENAME>Courier</FACENAME></FONT><TEXT pos="1,1" direction="3" font="7" color="0">hi</TEXT>'), sheet("TinyCAD", "T", WIRE)))
out, rc, root = convert(w1, os.path.join(tmp, "o", "w4.dsn"))
fonts = [(e.findtext("HEIGHT"), e.findtext("FACENAME")) for e in root[0].findall("FONT")] if root is not None else []
check("the hierarchical sheet's font and text come through", fonts == [("-33", "Courier")] and root[0].find("TEXT") is not None and root[0].find("TEXT").text == "hi", fonts)

# ======================================================================= 3. the placed design
def hs(attrs, fields, tag="HIERARCHICAL_SYMBOL"):
    a = " ".join('%s="%s"' % kv for kv in attrs)
    f = "".join('<FIELD type="%s" description="%s" value="%s" show="%s" pos="%s"/>' % x for x in fields)
    return "<%s %s>%s</%s>" % (tag, a, f, tag)
def get(root, i=0):
    return [e for e in root.iter() if e.tag == "HIERARCHICAL_SYMBOL"][i]
def fields_of(e): return [(f.get("type"), f.get("description"), f.get("value"), f.get("show"), f.get("pos")) for f in e.findall("FIELD")]
src = os.path.join(tmp, "proj", "main.dsn")
F3 = [("0", "Ref", "H1", "1", "1.00000,2.00000"), ("0", "Design", "", "1", "3.00000,4.00000"), ("1", "Other", "xyz", "0", "-5.00000,6.50000")]
for tag in ("HIERARCHICAL_SYMBOL", "HIERACHICAL_SYMBOL"):
    write(src, doc(sheet("TinyCAD", "Top", WIRE + hs([("pos", "10.5,20.25"), ("rotate", "2"), ("can_scale", "1"), ("scale_x", "1.5"), ("scale_y", "0.25"), ("file", "..\\lib\\child.dsn")], F3, tag))))
    out, rc, root = convert(src, os.path.join(tmp, "proj2", "x", "out.dsn"))
    check("%s: loads" % tag, rc == 0 and "OBJ 141 " in out, out)
    if root is None: continue
    e = get(root)
    check("%s: saved as HIERARCHICAL_SYMBOL" % tag, e is not None)
    check("%s: position, rotation, scaling kept" % tag, (e.get("pos"), e.get("rotate"), e.get("can_scale"), e.get("scale_x"), e.get("scale_y")) == ("10.50000,20.25000", "2", "1", "1.50000", "0.25000"), e.attrib)
    check("%s: the file is written relative to where the design is saved" % tag, e.get("file") == "..\\..\\lib\\child.dsn", e.get("file"))
    check("%s: fields kept, the Name field's value written empty" % tag, fields_of(e) == [F3[0], ("0", "Design", "", "1", "3.00000,4.00000"), F3[2]], fields_of(e))
    check("%s: the object is not saved as a library symbol, with no symbol number or part" % tag, not root.findall(".//SYMBOL") and e.get("id") is None and e.get("part") is None)
check("the Name field shows the design's file name in memory", "name=[child.dsn]" in out and "file=[%s]" % os.path.normpath(os.path.join(tmp, "lib", "child.dsn")) in out, out)
cl_out, cl_rc = ht("convert", src, os.path.join(tmp, "o", "clone.dsn"), "clone")
cl = [l for l in cl_out.splitlines() if l.startswith("CLONE")]
check("a copy made by Clone keeps file, rotation, fields, scaling and size", cl_rc == 0 and len(cl) == 1 and ("file=[%s]" % os.path.normpath(os.path.join(tmp, "lib", "child.dsn"))) in cl[0] and "rotate=2" in cl[0] and "fields=3" in cl[0] and "scale=1.500,0.250" in cl[0] and "can_scale=1" in cl[0] and "name=[child.dsn]" in cl[0], cl)
# saved in the same folder, and in the folder below
for dst, exp in [(os.path.join(tmp, "proj", "same.dsn"), "..\\lib\\child.dsn"), (os.path.join(tmp, "proj", "sub", "deeper", "d.dsn"), "..\\..\\..\\lib\\child.dsn"), (os.path.join(tmp, "lib", "e.dsn"), ".\\child.dsn"), (os.path.join(tmp, "lib", "sub", "e.dsn"), "..\\child.dsn")]:
    out, rc, root = convert(src, dst)
    check("saved as %s: file=%s" % (os.path.relpath(dst, tmp), exp), root is not None and get(root).get("file") == exp, get(root).get("file") if root is not None else out)
# a design that goes to the folder it came from comes back as it was written
write(src, doc(sheet("TinyCAD", "Top", hs([("pos", "1,1"), ("file", ".\\child.dsn")], F3))))
out, rc, root = convert(src, os.path.join(tmp, "proj", "back.dsn"))
check("a file beside the design stays .\\child.dsn", root is not None and get(root).get("file") == ".\\child.dsn", get(root).get("file") if root is not None else out)
write(src, doc(sheet("TinyCAD", "Top", hs([("pos", "1,1"), ("file", "sub\\child.dsn")], F3))))
out, rc, root = convert(src, os.path.join(tmp, "proj", "back.dsn"))
check("a file below the design: sub\\child.dsn is written .\\sub\\child.dsn (as PathRelativePathTo does)", root is not None and get(root).get("file") == ".\\sub\\child.dsn", get(root).get("file") if root is not None else out)
# Windows drive names cannot be followed here but are not lost
write(src, doc(sheet("TinyCAD", "Top", hs([("pos", "1,1"), ("file", "C:\\Designs\\child.dsn")], F3))))
out, rc, root = convert(src, os.path.join(tmp, "elsewhere", "back.dsn"))
check("a Windows drive name is written back as it was", root is not None and get(root).get("file") == "C:\\Designs\\child.dsn", get(root).get("file") if root is not None else out)
check("... and its Name field shows the file name", "name=[child.dsn]" in out, out)
# no file at all, and defaults for what is missing
write(src, doc(sheet("TinyCAD", "Top", '<HIERARCHICAL_SYMBOL></HIERARCHICAL_SYMBOL>')))
out, rc, root = convert(src, os.path.join(tmp, "proj", "back.dsn"))
if root is not None:
    e = get(root)
    check("nothing given: position 0,0, rotation 0, no scaling, 1.0 each, an empty file", (e.get("pos"), e.get("rotate"), e.get("can_scale"), e.get("scale_x"), e.get("scale_y"), e.get("file")) == ("0.00000,0.00000", "0", "0", "1.00000", "1.00000", ""), e.attrib)
    check("nothing given: the three fields a placed symbol starts with (Ref and Name shown, Other hidden)", fields_of(e) == [("0", "Ref", "", "1", "0.00000,0.00000"), ("0", "Name", "", "1", "0.00000,0.00000"), ("1", "Other", "", "0", "0.00000,0.00000")], fields_of(e))
else: check("an empty HIERARCHICAL_SYMBOL loads", False, out)
for n in (1, 2, 5):
    fl = [("0", "F%d" % i, "v%d" % i, "1", "%d.00000,0.00000" % i) for i in range(n)]
    write(src, doc(sheet("TinyCAD", "Top", hs([("pos", "1,1")], fl))))
    out, rc, root = convert(src, os.path.join(tmp, "proj", "back.dsn"))
    got = fields_of(get(root)) if root is not None else None
    check("%d field element(s): the field list becomes exactly that long, in order (a field read as Name has its value written empty)" % n, got == [(a, b, "" if i == 1 else c, d, e_) for i, (a, b, c, d, e_) in enumerate(fl)], got)
# several placed designs and other objects round-trip in order
write(src, doc(sheet("TinyCAD", "Top", hs([("pos", "1,1"), ("file", "a.dsn")], F3) + WIRE + hs([("pos", "2,2"), ("file", "b.dsn")], F3) + '<JUNCTION pos="3,3"/>')))
out, rc, root = convert(src, os.path.join(tmp, "proj", "back.dsn"))
check("objects keep their order", root is not None and [e.tag for e in root[0] if e.tag in ("WIRE", "HIERARCHICAL_SYMBOL", "JUNCTION")] == ["HIERARCHICAL_SYMBOL", "WIRE", "HIERARCHICAL_SYMBOL", "JUNCTION"], out)
# saving twice does not change anything
out, rc, root2 = convert(os.path.join(tmp, "proj", "back.dsn"), os.path.join(tmp, "proj", "back2.dsn"))
check("a second load and save is the same file", open(os.path.join(tmp, "proj", "back.dsn")).read() == open(os.path.join(tmp, "proj", "back2.dsn")).read())

# ======================================================================= 4. in the program
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
def field_of(line, name):
    m = re.search(r"(?:^| )%s=\[(.*?)\]" % name, line) or re.search(r"(?:^| )%s=(\S*)" % name, line)
    return m.group(1) if m else None
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("(program checks skipped: need xvfb-run and the built program)")
else:
    exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
    home = os.path.join(tmp, "home"); os.makedirs(home, exist_ok=True)
    gdir = os.path.join(tmp, "gui", "sub"); os.makedirs(gdir)
    main = os.path.join(gdir, "main.dsn")
    write(main, doc(sheet("HierarchicalSymbol", "ignored", WIRE + '<PIN pos="0,0" direction="3"/>'),
                    sheet("TinyCAD", "Top", WIRE + hs([("pos", "10,20"), ("rotate", "2"), ("can_scale", "1"), ("scale_x", "1.5"), ("scale_y", "2"), ("file", "..\\lib\\child.dsn")], F3, "HIERACHICAL_SYMBOL"))))
    saved = os.path.join(tmp, "gui", "saved.dsn"); parts = os.path.join(tmp, "gui", "parts.csv")
    script = os.path.join(tmp, "script.txt")
    open(script, "w").write("""open %s
sheetinfo
renamesheet Renamed
sheetinfo
gosheet 1
hiersymbols
selectall
sel
delete
objects
undo
objects
selectall
copy
paste
hiersymbols
netlist
partslist type=1 file=%s sheets=0
save %s
""" % (main, parts, saved))
    env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", script], capture_output=True, text=True, timeout=200, env=env)
    out = r.stdout.split("\n")
    check("program ran", "SAVED " + saved in "\n".join(out) or any(l.startswith("SAVED") for l in out), (out[-8:], r.stderr[-300:]))
    sh = [l for l in out if l.startswith("SHEETS")]
    check("program: the hierarchical sheet is the first tab, named Hierarchical Symbol", len(sh) == 2 and "names=Hierarchical Symbol:2,Top:2," in sh[0] and '"Hierarchical Symbol",Top' in sh[0], sh)
    check("program: it cannot be renamed", len(sh) == 2 and sh[1] == sh[0].replace(sh[0].split(" ")[0], sh[1].split(" ")[0]) and "Renamed" not in sh[1], sh)
    hl = [l for l in out if l.startswith("HIER ") and not l.startswith("HIER end")]
    check("program: the placed design is there with its settings (position, rotation, scaling, file, Name field)", hl and "pos=10.000,20.000" in hl[0] and "rotate=2" in hl[0] and "scale=1.500,2.000" in hl[0] and "can_scale=1" in hl[0]
          and "file=[%s]" % os.path.normpath(os.path.join(tmp, "gui", "lib", "child.dsn")) in hl[0] and "name=[child.dsn]" in hl[0], hl[:1])
    check("program: its box is the 50 by 50 square TinyCAD draws for a design it cannot load", hl and "box=-50.0,-50.0" in hl[0], hl[:1])
    check("program: select all takes the wire and the placed design", any(l.startswith("SEL 2") and "TDrawHierarchicalSymbol" in l for l in out), [l for l in out if l.startswith("SEL")])
    check("program: copy and paste makes a second one, the same", len(hl) == 3 and field_of(hl[1], "file") == field_of(hl[0], "file") and "rotate=2" in hl[2], hl)
    check("program: the copy has an object number of its own", len(hl) == 3 and field_of(hl[0], "id") != field_of(hl[2], "id"), hl)
    oe = [l for l in out if l.startswith("OBJ end")]
    check("program: delete takes both away, undo brings them back", len(oe) == 2 and oe[0] == "OBJ end 0" and oe[1] == "OBJ end 2", oe)
    check("program: the netlist is written and does not stop at the placed design", any(l.startswith("NETLIST wrote=1") for l in out), [l for l in out if l.startswith("NETLIST")])
    pl = [l for l in out if l.startswith("PARTSLIST wrote")]
    txt = open(parts, encoding="utf-8", errors="replace").read() if os.path.exists(parts) else ""
    check("program: the parts list passes the placed design by (it is not a part)", pl and "wrote=1" in pl[0] and "H1" not in txt and "child" not in txt, (pl, txt[:200]))
    check("program: saved, the file has the hierarchical sheet and the object once, the file name relative to the new folder", os.path.exists(saved), saved)
    if os.path.exists(saved):
        rt = ET.parse(saved).getroot()
        check("program: saved sheets", sheets_of(rt) == [("HierarchicalSymbol", "Hierarchical Symbol"), ("TinyCAD", "Top")], sheets_of(rt))
        e = get(rt)
        check("program: saved placed design", e.get("file") == ".\\lib\\child.dsn" and (e.get("pos"), e.get("rotate"), e.get("scale_x")) == ("10.00000,20.00000", "2", "1.50000"), e.attrib)
    # saved to another folder and opened again
    saved2 = os.path.join(tmp, "gui", "deeper", "x", "again.dsn"); os.makedirs(os.path.dirname(saved2))
    script2 = os.path.join(tmp, "script2.txt")
    open(script2, "w").write("open %s\nsave %s\nopen %s\ngosheet 1\nhiersymbols\n" % (main, saved2, saved2))
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", script2], capture_output=True, text=True, timeout=200, env=env)
    out2 = r.stdout.split("\n")
    hl2 = [l for l in out2 if l.startswith("HIER ") and not l.startswith("HIER end")]
    check("program: saved in another folder, the design is written relative to it and found again at the same place", os.path.exists(saved2) and get(ET.parse(saved2).getroot()).get("file") == "..\\..\\lib\\child.dsn" and hl2 and "file=[%s]" % os.path.normpath(os.path.join(tmp, "gui", "lib", "child.dsn")) in hl2[0], (hl2, r.stderr[-200:]))

    # the box is drawn: the same sheet with and without the placed design differs by a black square outline
    hidden = [("0", "Ref", "H1", "0", "0,0"), ("0", "Design", "", "0", "0,0"), ("1", "Other", "", "0", "0,0")]
    same = os.path.join(tmp, "gui", "same.dsn")      # (one name for both, the title block shows it)
    pa = os.path.join(tmp, "gui", "a.bmp"); pb = os.path.join(tmp, "gui", "b.bmp")
    for text, shot in ((doc(sheet("TinyCAD", "A", WIRE + hs([("pos", "120,80"), ("file", "x.dsn")], hidden))), pa), (doc(sheet("TinyCAD", "A", WIRE)), pb)):
        write(same, text)
        script3 = os.path.join(tmp, "script3.txt")
        open(script3, "w").write("open %s\nshot %s\n" % (same, shot))
        r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", script3], capture_output=True, text=True, timeout=200, env=env)
    try:
        from PIL import Image, ImageChops
        A = Image.open(pa).convert("RGB"); B = Image.open(pb).convert("RGB")
        bbox = ImageChops.difference(A, B).getbbox()
        px = [A.getpixel((x, y)) for x in range(bbox[0], bbox[2]) for y in range(bbox[1], bbox[3])] if bbox else []
        black = sum(1 for c in px if c == (0, 0, 0))
        check("program: the placed design is drawn as a black square outline (50 units, so as wide as it is high)", bbox is not None and abs((bbox[2] - bbox[0]) - (bbox[3] - bbox[1])) <= 2 and black >= 2 * ((bbox[2] - bbox[0]) + (bbox[3] - bbox[1])) - 12 and black <= 2 * ((bbox[2] - bbox[0]) + (bbox[3] - bbox[1])) + 12, (bbox, black))
    except ImportError:
        print("(box drawing check skipped: needs PIL)")

shutil.rmtree(tmp, ignore_errors=True)
print("hierarchical (step 1): %d checks, %d failed" % (checks, len(fails)))
if fails: print("FAILED:", ", ".join(fails[:20])); sys.exit(1)
