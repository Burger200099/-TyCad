#!/usr/bin/env python3
"""Reading the design behind a hierarchical symbol (step 2 of the hierarchical designs).

The driver (tests/drivers/hiertest.pas, command `child`) prints, for each placed design, the objects the loader reads (RAW, before the
symbol touches them), the grid, and what the symbol makes of them (SYM, PINS). The oracle here is a restatement of
CDrawHierarchicalSymbol::Load / ExtractSymbol / TranslatePointToDesign written from the C++, working on the RAW numbers, and the XML of the
child (rectangle and line corners are checked against the file itself). Run with TC_BUILD set to the folder holding hiertest."""
import os, re, sys, math, random, subprocess, tempfile, shutil

BUILD = os.environ.get("TC_BUILD", "build")
HT = os.path.join(BUILD, "hiertest")
if not os.path.exists(HT):
    print("Hierarchical load checks skipped: build tests/drivers/hiertest.pas first", HT); sys.exit(0)
tmp = tempfile.mkdtemp()
fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name)
        if len(fails) <= 25: print("  FAIL", name, str(detail)[:900])
def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True); open(path, "w", encoding="utf-8").write(text)

def parent(file, grid_attr="", rotate=0, sx=1.0, sy=1.0, pos="100,200", fields=None):
    f = fields if fields is not None else '<FIELD type="0" description="Ref" value="H1" show="1" pos="0,0"/><FIELD type="0" description="Design" value="" show="0" pos="0,0"/>'
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<TinyCADSheets><TinyCAD><NAME>T</NAME><DETAILS><Size width="1485" height="1050"/></DETAILS>%s'
            '<HIERARCHICAL_SYMBOL pos="%s" rotate="%d" can_scale="1" scale_x="%s" scale_y="%s" file="%s">%s</HIERARCHICAL_SYMBOL></TinyCAD></TinyCADSheets>'
            % (grid_attr, pos, rotate, sx, sy, file, f))
def child(body, tag="HierarchicalSymbol", extra=""):
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<TinyCADSheets><TinyCAD><NAME>Top</NAME><WIRE a="1,1" b="5,1"/></TinyCAD>%s'
            '<%s><NAME>x</NAME><DETAILS><Size width="1485" height="1050"/></DETAILS>%s</%s></TinyCADSheets>' % (extra, tag, body, tag))
def run(parent_path):
    r = subprocess.run([HT, "child", parent_path], capture_output=True, text=True, timeout=60)
    return r.stdout.splitlines(), r.returncode, r.stderr
def pt(s): x, y = s.split(","); return (float(x), float(y))
def objs_of(s):
    out = []
    for it in s.split(";"):
        if not it: continue
        t, a, b = it.split(":")
        inv = t.endswith("i"); t = int(t.rstrip("i"))
        out.append((t, pt(a), None if b.lower().startswith("nan") else pt(b), inv))
    return out
def parse(lines):
    d = {}
    for l in lines:
        if l.startswith("RAW "):
            m = re.match(r"RAW ok=(\d) err=\[(.*)\] count=(\d+) objs=(.*)", l); d["raw_ok"] = m.group(1) == "1"; d["raw_err"] = m.group(2); d["raw"] = objs_of(m.group(4))
        elif l.startswith("GRID "):
            m = re.match(r"GRID (\S+) snap=(\d+)", l); d["grid"] = float(m.group(1)); d["snap"] = int(m.group(2))
        elif l.startswith("SYM "):
            m = re.match(r"SYM ok=(\d) err=\[(.*)\] nosymbol=(\d) tr=(\S+) A=(\S+) B=(\S+) file=\[(.*)\] name=\[(.*)\] desc=\[(.*)\] show=(\d+) objs=(.*)", l)
            d["ok"] = m.group(1) == "1"; d["err"] = m.group(2); d["nosym"] = m.group(3) == "1"; d["tr"] = pt(m.group(4)); d["A"] = pt(m.group(5)); d["B"] = pt(m.group(6))
            d["file"] = m.group(7); d["name"] = m.group(8); d["desc"] = m.group(9); d["show"] = int(m.group(10)); d["objs"] = objs_of(m.group(11))
        elif l.startswith("FRESHTR "):
            d["freshtr"] = pt(l.split()[1])
        elif l.startswith("FRESHNOSYM "):
            m = re.match(r"FRESHNOSYM (\d) has=(\d)", l); d["freshnosym"] = m.group(1) == "1"; d["freshhas"] = m.group(2) == "1"
        elif l.startswith("PINS"):
            d["pins"] = [pt(x) for x in l.split()[1:]]
    return d

def snap(grid, on, v):
    if not on or grid == 0: return v
    a = math.floor(v / grid) * grid
    if (v - a) * 2 > grid: a += grid
    return a
def want_symbol(raw, grid, on):
    """Load(): the box, the grid snap, the translation. raw = [(type, A, B, invisible)]"""
    a = [0.0, 0.0]; b = list(raw[0][1]); pin = None
    for t, A, B, inv in raw:
        if t == 28 and pin is None and not inv: pin = A
        a[0] = max(a[0], max(A[0], B[0])); a[1] = max(a[1], max(A[1], B[1]))
        b[0] = min(b[0], min(A[0], B[0])); b[1] = min(b[1], min(A[1], B[1]))
    sa = [snap(grid, on, a[0]), snap(grid, on, a[1])]; sb = [snap(grid, on, b[0]), snap(grid, on, b[1])]
    if pin is not None:
        off = (pin[0] - snap(grid, on, pin[0]), pin[1] - snap(grid, on, pin[1]))
        sa = [sa[0] + off[0], sa[1] + off[1]]; sb = [sb[0] + off[0], sb[1] + off[1]]
    if sa[0] < a[0]: sa[0] += grid
    if sa[1] < a[1]: sa[1] += grid
    if sb[0] > b[0]: sb[0] -= grid
    if sb[1] > b[1]: sb[1] -= grid
    objs = [(t, (A[0] - sa[0], A[1] - sa[1]), (B[0] - sa[0], B[1] - sa[1]), inv) for t, A, B, inv in raw]
    return objs, (sb[0] - sa[0], sb[1] - sa[1])
def close(p, q, e=0.002): return abs(p[0] - q[0]) <= e and abs(p[1] - q[1]) <= e
def same_objs(x, y):
    if len(x) != len(y): return False
    return all(a[0] == b[0] and a[3] == b[3] and close(a[1], b[1]) and close(a[2], b[2]) for a, b in zip(x, y))
def to_design(p, tr, A, rot, sx, sy):
    """CDrawMethod::TranslatePointToDesign, tr already scaled"""
    x, y = p[0] * sx, p[1] * sy
    if rot & 4: x = tr[0] - x
    r = rot & 3
    if r == 0: return (x + A[0], y + A[1])
    if r == 1: return (x + A[0], (tr[1] - y) + A[1])
    if r == 2: return (y + A[0], x + A[1])
    return ((tr[1] - y) + A[0], x + A[1])

# ======================================================================= 1. one design, by hand
cdir = os.path.join(tmp, "p")
write(os.path.join(cdir, "child.dsn"), child('<RECTANGLE a="23,31" b="87,95" style="0" fill="0"/><PIN pos="23,47" direction="3" length="15" which="0" elec="0" show="1" number="1" part="0"/>'))
write(os.path.join(cdir, "main.dsn"), parent(".\\child.dsn"))
out, rc, err = run(os.path.join(cdir, "main.dsn"))
d = parse(out)
check("by hand: it runs", rc == 0 and "ok" in d, (out, err))
if "ok" in d:
    check("by hand: the rectangle's corners are the file's, times five", d["raw"][0][0] == 136 and d["raw"][0][1] == (115.0, 155.0) and d["raw"][0][2] == (435.0, 475.0), d["raw"])
    check("by hand: a copy not read yet reads the design when asked its size or whether it has a drawing", d.get("freshtr") == (-320.0, -320.0) and d.get("freshnosym") is False and d.get("freshhas") is True, (d.get("freshtr"), d.get("freshnosym"), d.get("freshhas")))
    check("by hand: it loaded", d["ok"] and d["err"] == "" and not d["nosym"], d)
    check("by hand: the box is 320 square, drawn up and to the left of the placement point (the C++ moves the far corner to the origin)", d["tr"] == (-320.0, -320.0) and d["B"] == (180.0, 680.0) and d["A"] == (500.0, 1000.0), d)
    check("by hand: the objects are moved by the far corner", d["objs"][0][1] == (-320.0, -320.0) and d["objs"][0][2] == (0.0, 0.0) and d["objs"][1][1] == (-320.0, -240.0), d["objs"])
    check("by hand: the pin is on the left edge of the box", d["pins"] == [(180.0, 760.0)], d["pins"])
    check("by hand: the file is the design's and the Name field shows it as a shown field called Design", d["file"] == os.path.join(cdir, "child.dsn") and d["name"] == "child.dsn" and d["desc"] == "Design" and d["show"] == 1, d)

# ======================================================================= 2. random designs against the oracle
rnd = random.Random(2718)
def rect(x1, y1, x2, y2): return ('<RECTANGLE a="%g,%g" b="%g,%g" style="0" fill="0"/>' % (x1, y1, x2, y2), ("r", x1, y1, x2, y2))
bad = []; ncase = 0; with_pins = 0; with_snap = 0; with_hidden = 0
for k in range(90):
    body = ""; rects = []
    for _ in range(rnd.randint(1, 4)):
        neg = rnd.random() < 0.15
        x1, y1 = rnd.randint(-90 if neg else 1, 120) + rnd.choice([0, 0, 0.5, 0.25]), rnd.randint(-90 if neg else 1, 120) + rnd.choice([0, 0, 0.4])
        x2, y2 = x1 + rnd.randint(1, 80), y1 + rnd.randint(1, 80)
        s, r = rect(x1, y1, x2, y2); body += s; rects.append(r)
    pins = rnd.randint(0, 3)
    for q in range(pins):
        body += '<PIN pos="%g,%g" direction="%d" length="%d" which="%d" elec="0" show="1" number="%d" part="0">P%d</PIN>' % (
            rnd.randint(1, 100) + rnd.choice([0, 0.5]), rnd.randint(1, 100), rnd.randint(0, 3), rnd.choice([0, 15, 20, 30]), rnd.choice([0, 0, 4]), q + 1, q)
    grid_attr = rnd.choice(["", '<GRID spacing="%d" snap="1"/>' % rnd.choice([25, 50, 100, 200]), '<GRID spacing="50" snap="0"/>'])
    rot = rnd.randint(0, 7); sx = rnd.choice([1, 1, 2, 0.5, 1.5]); sy = rnd.choice([1, 1, 2, 0.5])
    write(os.path.join(cdir, "c%d.dsn" % k), child(body, rnd.choice(["HierarchicalSymbol", "HierachicalSymbol"])))
    write(os.path.join(cdir, "m%d.dsn" % k), parent(".\\c%d.dsn" % k, grid_attr, rot, sx, sy, "%d,%d" % (rnd.randint(0, 300), rnd.randint(0, 300))))
    out, rc, err = run(os.path.join(cdir, "m%d.dsn" % k)); d = parse(out); ncase += 1
    if rc != 0 or "ok" not in d: bad.append((k, "run", out[-3:], err[-200:])); continue
    # the XML check of the corners the loader read
    for (t, A, B, inv), r in zip([o for o in d["raw"] if o[0] == 136], rects):
        if not (close(A, (r[1] * 5, r[2] * 5)) and close(B, (r[3] * 5, r[4] * 5))): bad.append((k, "raw corners", A, B, r))
    objs, tr = want_symbol(d["raw"], d["grid"], d["snap"])
    with_pins += any(o[0] == 28 for o in objs); with_snap += d["snap"]; with_hidden += any(o[0] == 28 and o[3] for o in objs)
    if not d["ok"] or not same_objs(objs, d["objs"]): bad.append((k, "objects", objs, d["objs"])); continue
    scaled = (tr[0] * sx, tr[1] * sy)
    if not close(d["tr"], scaled): bad.append((k, "tr", scaled, d["tr"])); continue
    A = d["A"]
    wantB = (scaled[0] + A[0], scaled[1] + A[1]) if (rot & 3) < 2 else (scaled[1] + A[0], scaled[0] + A[1])
    if not close(d["B"], wantB): bad.append((k, "B", wantB, d["B"], rot)); continue
    wantpins = [to_design(o[1], scaled, A, rot, sx, sy) for o in objs if o[0] == 28 and not o[3]]
    if len(wantpins) != len(d["pins"]) or not all(close(p, q) for p, q in zip(wantpins, d["pins"])): bad.append((k, "pins", wantpins, d["pins"], rot))
check("%d random designs (rectangles, pins, two tag spellings, grids, rotations 0-7, scaling) against the Python restatement of the C++" % ncase, not bad, bad[:3])
check("the random designs included many with pins, with hidden pins and with snapping on", with_pins >= 30 and with_snap >= 40 and with_hidden >= 3, (with_pins, with_snap, with_hidden))

# a design whose objects all lie at negative coordinates (the box starts from 0,0, as the C++ does)
write(os.path.join(cdir, "neg.dsn"), child('<RECTANGLE a="-90,-70" b="-30,-20" style="0" fill="0"/>'))
write(os.path.join(cdir, "m_neg.dsn"), parent(".\\neg.dsn"))
d = parse(run(os.path.join(cdir, "m_neg.dsn"))[0])
objs, tr = want_symbol(d["raw"], d["grid"], d["snap"])
check("objects all at negative coordinates: the box still starts from 0,0", d.get("ok") and same_objs(objs, d["objs"]) and close(d["tr"], tr) and d["raw"][0][1] == (-450.0, -350.0), (d.get("raw"), d.get("objs"), d.get("tr"), tr))

# ======================================================================= 3. designs that cannot be read
def single(name, text, errpart, tr=(-50.0, -50.0), what=""):
    write(os.path.join(cdir, name), text)
    write(os.path.join(cdir, "m_" + name), parent(".\\" + name))
    out, rc, err = run(os.path.join(cdir, "m_" + name))
    d = parse(out)
    ok = rc == 0 and "ok" in d and (not d["ok"]) and d["nosym"] and errpart in d["err"] and d["tr"] == tr and d["B"] == (tr[0] + d["A"][0], tr[1] + d["A"][1])
    check("%s: not loaded, message %r, a 50 by 50 box" % (what, errpart), ok, (out, err[-200:]))
    return d
write(os.path.join(cdir, "m_nofile.dsn"), parent(".\\nofile.dsn"))
d = parse(run(os.path.join(cdir, "m_nofile.dsn"))[0])
check("missing file: not loaded, File not found, a 50 by 50 box, no objects", d.get("ok") is False and d["err"].startswith("File not found: ") and d["err"].endswith("nofile.dsn") and d["nosym"] and d["tr"] == (-50.0, -50.0) and d["B"] == (450.0, 950.0) and d["objs"] == [] and d["pins"] == [], d)
single("onesheet.dsn", '<?xml version="1.0"?>\n<TinyCAD><NAME>a</NAME><WIRE a="1,1" b="5,1"/></TinyCAD>', "This file does not have a hierarchical symbol", what="a single sheet file")
single("nosheet.dsn", '<?xml version="1.0"?>\n<TinyCADSheets><TinyCAD><NAME>a</NAME><WIRE a="1,1" b="5,1"/></TinyCAD></TinyCADSheets>', "This file does not have a hierarchical symbol", what="sheets with no symbol sheet")
single("emptysym.dsn", child(""), "This file does not have a hierarchical symbol", what="an empty symbol sheet")
single("empty.dsn", "", "", what="an empty file")
single("binary.dsn", "\x00\x01\x02garbage", "", what="garbage")

# ======================================================================= 4. two symbol sheets, the old tag, other sheets in front
write(os.path.join(cdir, "two.dsn"), child('<RECTANGLE a="1,1" b="3,3" style="0" fill="0"/>') .replace("</TinyCADSheets>", '<HierarchicalSymbol><NAME>y</NAME><RECTANGLE a="10,10" b="30,30" style="0" fill="0"/></HierarchicalSymbol></TinyCADSheets>'))
write(os.path.join(cdir, "m_two.dsn"), parent(".\\two.dsn"))
d = parse(run(os.path.join(cdir, "m_two.dsn"))[0])
check("two symbol sheets: the later one is used", d.get("ok") and len(d["objs"]) == 1 and d["raw"][0][1] == (50.0, 50.0) and d["raw"][0][2] == (150.0, 150.0), d)

# ======================================================================= 5. in the program
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
def kv(line, name):
    m = re.search(r"(?:^| )%s=\[(.*?)\]" % name, line) or re.search(r"(?:^| )%s=(\S*)" % name, line)
    return m.group(1) if m else None
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("(program checks skipped: need xvfb-run and the built program)")
else:
    exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
    home = os.path.join(tmp, "home"); os.makedirs(home, exist_ok=True)
    env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
    g = os.path.join(tmp, "g"); os.makedirs(g)
    RECT_A = '<RECTANGLE a="23,31" b="87,95" style="0" fill="0"/><PIN pos="23,47" direction="3" length="15" which="0" elec="0" show="1" number="1" part="0"/>'
    RECT_B = '<RECTANGLE a="10,10" b="150,50" style="0" fill="0"/><PIN pos="10,30" direction="3" length="15" which="0" elec="0" show="1" number="1" part="0"/><PIN pos="150,30" direction="2" length="15" which="0" elec="0" show="1" number="2" part="0"/>'
    write(os.path.join(g, "childA.dsn"), child(RECT_A))
    write(os.path.join(g, "childB.dsn"), child(RECT_B))
    write(os.path.join(g, "plain.dsn"), '<?xml version="1.0"?>\n<TinyCADSheets><TinyCAD><NAME>a</NAME><DETAILS><Size width="1485" height="1050"/></DETAILS><WIRE a="1,1" b="5,1"/></TinyCAD></TinyCADSheets>\n')
    def gui(lines, timeout=200):
        sp = os.path.join(g, "script.txt"); open(sp, "w").write("\n".join(lines) + "\n")
        r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=timeout, env=env)
        return r.stdout.split("\n"), r.stderr
    def pick(out, prefix): return [l for l in out if l.startswith(prefix)]
    def box_of(line):
        m = re.search(r"box=(\S+),(\S+)", line); return (float(m.group(1)), float(m.group(2)))
    def truth(path, which=0):
        """what the driver (the unit-level loader and the oracle-checked numbers) says for the placed design in a saved file"""
        o, rc, e = run(path); d = parse(o); return d

    # --- insert another design as symbol, place it, save
    A = os.path.join(g, "childA.dsn"); plain = os.path.join(g, "plain.dsn"); out1 = os.path.join(g, "out1.dsn")
    out, err = gui(["open " + plain, "hiermenu", "insertdesign " + os.path.join(g, "nofile.dsn"), "insertdesign " + plain, "sel",
                    "insertdesign " + A, "mouse move 60 60", "mouse down 60 60", "mouse up 60 60", "hiersymbols", "pinsof", "sel", "hiermenu", "save " + out1])
    hm = pick(out, "HIERMENU"); ins = pick(out, "INSERTDESIGN"); hl = pick(out, "HIER ")
    hl = [l for l in hl if not l.startswith("HIER end")]
    check("program: with a plain sheet shown, inserting and adding are on and the commands on a placed design are off", hm and hm[0] == "HIERMENU insert=1 add=1 addsheet=1 reload=0 change=0 open=0", hm[:1])
    check("program: a missing design and a design with no symbol sheet are refused", len(ins) == 3 and ins[0].startswith("INSERTDESIGN 0") and ins[1].startswith("INSERTDESIGN 0") and ins[2].startswith("INSERTDESIGN 1"), ins)
    check("program: and the reasons are given", len(ins) == 3 and "File not found: " in ins[0] and "does not have a hierarchical symbol" in ins[1], ins)
    check("program: one placed design after the click", len(hl) == 1 and "hassym=1" in hl[0] and "err=[]" in hl[0], (hl, err[-200:]))
    check("program: the placed design shows its file in the Name field", hl and kv(hl[0], "file") == A and kv(hl[0], "name") == "childA.dsn", hl)
    check("program: after placing it is selected and the commands on it are on", len(hm) > 1 and hm[1] == "HIERMENU insert=1 add=1 addsheet=1 reload=1 change=1 open=1", hm)
    t = truth(out1)
    check("program: the file saved with it reads back the same box (width and height)", t.get("ok") and hl and box_of(hl[0]) == (t["B"][0] - t["A"][0], t["B"][1] - t["A"][1]), (t.get("A"), t.get("B"), hl))
    check("program: the box is the child's 320 by 320 units, up and to the left of where it was put", t.get("ok") and t["tr"] == (-320.0, -320.0), t)
    pins = [l for l in pick(out, "PIN ")]
    check("program: the pin of the child is a connection point of the placed design", len(pins) == 1 and len(t.get("pins", [])) == 1, (pins, t.get("pins")))
    root = ET.parse(out1).getroot()
    hs_el = [e for e in root.iter() if e.tag == "HIERARCHICAL_SYMBOL"]
    check("program: saved as one placed design with a relative file name, the Name field empty and the field called Design", len(hs_el) == 1 and hs_el[0].get("file") == ".\\childA.dsn"
          and [(f.get("description"), f.get("value")) for f in hs_el[0].findall("FIELD")][1] == ("Design", ""), [e.attrib for e in hs_el])

    # --- change the design, undo, a bad design
    B = os.path.join(g, "childB.dsn"); out2 = os.path.join(g, "out2.dsn")
    out, err = gui(["open " + out1, "gosheet 0", "selectclass TDrawHierarchicalSymbol", "hiersymbols", "changedesign " + B, "hiersymbols", "pinsof", "undo", "hiersymbols", "changedesign " + os.path.join(g, "nofile.dsn"),
                    "hiersymbols", "changedesign " + plain, "hiersymbols", "redo", "hiersymbols", "save " + out2])
    chg = pick(out, "CHANGEDESIGN"); hl = [l for l in pick(out, "HIER ") if not l.startswith("HIER end")]
    check("program: change design: the good one worked, the missing and the plain ones were refused", len(chg) == 3 and chg[0].startswith("CHANGEDESIGN 1") and chg[1].startswith("CHANGEDESIGN 0") and chg[2].startswith("CHANGEDESIGN 0"), (chg, out[-6:], err[-200:]))
    check("program: change design: and the reasons are given", len(chg) == 3 and "File not found: " in chg[1] and "does not have a hierarchical symbol" in chg[2], chg)
    if len(hl) >= 6:
        check("program: change design: new file and a different box, undo brings the old ones back, refused changes change nothing, redo again",
              kv(hl[0], "file") == A and kv(hl[1], "file") == B and box_of(hl[1]) != box_of(hl[0]) and kv(hl[2], "file") == A and box_of(hl[2]) == box_of(hl[0])
              and kv(hl[3], "file") == A and kv(hl[4], "file") == A and kv(hl[5], "file") == B, [(kv(x, "file"), box_of(x)) for x in hl])
    else:
        check("program: change design lines", False, hl)
    t2 = truth(out2)
    check("program: after the change the saved file's design is childB with the box the loader works out", t2.get("ok") and t2["file"] == B and same_objs(want_symbol(t2["raw"], t2["grid"], t2["snap"])[0], t2["objs"]) and close(t2["tr"], want_symbol(t2["raw"], t2["grid"], t2["snap"])[1]), t2)
    check("program: childB has two pins and both are connection points", len(t2.get("pins", [])) == 2, t2.get("pins"))

    # --- add the hierarchical symbol sheet, pins on it, only one
    out3 = os.path.join(g, "out3.dsn")
    write(os.path.join(g, "titled.dsn"), '<?xml version="1.0"?>\n<TinyCADSheets><TinyCAD><NAME>a</NAME><DETAILS><Size width="800" height="600"/><TITLE>My title</TITLE><ORGANISATION>My org</ORGANISATION><DOCNUMBER>D-7</DOCNUMBER><GRID spacing="250" snap="1"/></DETAILS><WIRE a="1,1" b="5,1"/></TinyCAD></TinyCADSheets>\n')
    out4 = os.path.join(g, "out4.dsn")
    gui(["open " + os.path.join(g, "titled.dsn"), "addhier", "save " + out4])
    r4 = ET.parse(out4).getroot() if os.path.exists(out4) else None
    dt = r4[0].find("DETAILS") if r4 is not None else None
    check("program: the new symbol sheet takes the paper, title block and grid of the sheet that was shown", dt is not None and dt.find("Size").attrib == {"width": "800", "height": "600"}
          and dt.findtext("TITLE") == "My title" and dt.findtext("ORGANISATION") == "My org" and dt.findtext("DOCNUMBER") == "D-7" and float(dt.find("GRID").get("spacing")) == 250.0,
          ET.tostring(dt)[:400] if dt is not None else None)
    out, err = gui(["open " + plain, "tool pin", "mouse down 30 30", "mouse up 30 30", "objects", "addhier", "sheetinfo", "hiermenu", "addhier", "insertdesign " + A, "tool pin",
                    "mouse down 20 20", "mouse up 20 20", "mouse down 20 40", "mouse up 20 40", "objects", "undo", "undo", "sheetinfo", "objects", "undo", "sheetinfo", "redo", "redo", "redo", "sheetinfo", "objects",
                    "save " + out3])
    ah = pick(out, "ADDHIER"); sh = pick(out, "SHEETS"); hm = pick(out, "HIERMENU"); ins = pick(out, "INSERTDESIGN")
    check("program: pins cannot be put on a plain sheet, but add hierarchical symbol works once", len(ah) == 2 and ah[0] == "ADDHIER 1" and ah[1] == "ADDHIER 0", (ah, pick(out, "OBJ")[:3]))
    check("program: the pin tool put nothing on the plain sheet (only its wire is there)", pick(out, "OBJ end")[0] == "OBJ end 1", pick(out, "OBJ end"))
    check("program: the new sheet is first and named Hierarchical Symbol, and is the one shown", sh and sh[0].startswith("SHEETS 2 current=0") and 'tabs="Hierarchical Symbol",' in sh[0], sh)
    check("program: with the symbol sheet there, adding is off and inserting a design on it is refused", hm and "insert=0 add=0 addsheet=0" in hm[0] and ins and ins[0].startswith("INSERTDESIGN 0"), (hm, ins))
    nsh = [int(x.split()[1]) for x in sh]; ob = [int(x.split()[2]) for x in pick(out, "OBJ end")]
    check("program: undo takes away the two pins, then the sheet; redo brings all three back", nsh == [2, 2, 1, 2] and ob[-3:] == [2, 0, 2], (nsh, ob))
    r3 = ET.parse(out3).getroot() if os.path.exists(out3) else None
    check("program: saved with the symbol sheet first, holding the two pins, and the plain sheet second", r3 is not None and [e.tag for e in r3 if e.tag != "COMMENT"][:2] == ["HierarchicalSymbol", "TinyCAD"]
          and len(r3[0].findall("PIN")) == 2, [e.tag for e in r3] if r3 is not None else None)

    # --- reload from the design, open the design
    C = os.path.join(g, "childC.dsn"); P2 = os.path.join(g, "par2.dsn")
    shutil.copy(A, C)
    write(P2, parent(".\\childC.dsn"))
    out, err = gui(["open " + P2, "selectclass TDrawHierarchicalSymbol", "hiersymbols", "open " + C, "gosheet 1", "selectall", "delete", "tool pin", "mouse down 40 40", "mouse up 40 40", "save " + C,
                    "gotodoc 0", "selectclass TDrawHierarchicalSymbol", "hiersymbols", "reloaddesign", "hiersymbols"])
    hl = [l for l in pick(out, "HIER ") if not l.startswith("HIER end")]
    rl = pick(out, "RELOADDESIGN")
    if len(hl) >= 3:
        tn = truth(P2)
        check("program: reload: the box before is the old design's, after the design was changed and reloaded it is the new one's", box_of(hl[0]) == box_of(hl[1]) and box_of(hl[2]) != box_of(hl[1])
              and tn.get("ok") and box_of(hl[2]) == (tn["B"][0] - tn["A"][0], tn["B"][1] - tn["A"][1]) and rl and rl[0].startswith("RELOADDESIGN 1"), ([(box_of(x)) for x in hl], tn.get("tr"), rl, err[-200:]))
    else:
        check("program: reload lines", False, (hl, out[-12:], err[-300:]))
    out, err = gui(["open " + P2, "opendesign", "selectclass TDrawHierarchicalSymbol", "docs", "opendesign", "docs", "opendesign", "docs"])
    dc = pick(out, "DOCS"); od = pick(out, "OPENDESIGN")
    check("program: open design: nothing happens with no design chosen, then the design's file opens in a document, and a second time it is only shown", len(dc) == 3 and len(od) == 3
          and od[0] == "OPENDESIGN 0" and od[1] == "OPENDESIGN 1" and dc[0].startswith("DOCS 1 ") and dc[1].startswith("DOCS 2 ") and "childC.dsn" in dc[1] and dc[2].startswith("DOCS 2 "), (od, dc))

    # --- a placed design whose file is gone is the plain box and the file still saves
    gone = os.path.join(g, "gone.dsn"); P3 = os.path.join(g, "par3.dsn"); P3b = os.path.join(g, "par3b.dsn")
    shutil.copy(A, gone); write(P3, parent(".\\gone.dsn"))
    os.remove(gone)
    out, err = gui(["open " + P3, "selectclass TDrawHierarchicalSymbol", "hiersymbols", "reloaddesign", "hiersymbols", "save " + P3b])
    hl = [l for l in pick(out, "HIER ") if not l.startswith("HIER end")]
    check("program: a design that is not there: the 50 by 50 box, the reason is kept, reload says no", len(hl) == 2 and box_of(hl[0]) == (-50.0, -50.0) and "hassym=0" in hl[0] and "File not found" in hl[1] and pick(out, "RELOADDESIGN")[0].startswith("RELOADDESIGN 0"), (hl, err[-200:]))
    check("program: and the design is saved with the same file name", os.path.exists(P3b) and ET.parse(P3b).getroot().find(".//HIERARCHICAL_SYMBOL").get("file") == ".\\gone.dsn")

shutil.rmtree(tmp, ignore_errors=True)
print("hierarchical (reading the design): %d checks, %d failed" % (checks, len(fails)))
if fails: print("FAILED:", ", ".join(fails[:20])); sys.exit(1)
