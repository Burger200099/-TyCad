"""Symbol editor (TinyCAD's CTinyCadMultiSymbolDoc, the Update Library dialog and the Library menu) on the real program, checked against Python's own sqlite3 / XML reading of the library files:
  - New symbol: pins placed with the Pin tool (numbers counted on), the origin set, names/description/attributes from Symbol Properties, stored: the Name, Symbol and Attribute rows and the PIN/ORIGIN
    elements of the stored drawing; the other symbols of the library untouched
  - problems: no name, a repeated name, two pins on one spot stop the store (the file is unchanged); warnings are reported and do not
  - Edit symbol: the pins shown are those of the stored XML, a changed symbol replaces the old one (same names/attributes kept), the same symbol opened twice is one document
  - Symbol Properties: aliases added and deleted, attributes with display methods, SPICE fields, Cancel changes nothing
  - parts per package: homogeneous (pins tagged with their part, part switching, shrinking removes pins) and heterogeneous (a sheet per part, "Part A" tabs); the kind can only change at one part
  - Delete / Duplicate / Copy to on the library list; a symbol being edited cannot be deleted and its library cannot be closed
  - Symbol properties on a symbol in the library list: the dialog on its own (no tab), OK stores into the library, Cancel and refused changes leave the file byte for byte
  - tool restrictions: no wires or placing in a symbol, no pins in a design, no extra sheets; Save All stores symbols; undo
Needs the built program, xvfb and the example libraries (TC_EXAMPLES)."""
import glob, os, re, shutil, subprocess, sys, tempfile, sqlite3
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Symbol editor checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 16: print("  FAIL", n, str(d)[:1200])
def run(script, home, timeout=280):
    h = os.path.join(tmp, "home_" + home); os.makedirs(h, exist_ok=True)
    path = os.path.join(tmp, "script_%s.txt" % home); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n"), r.returncode, r.stderr
def field(line, name):
    m = re.search(r"(?:^| )%s=\[(.*?)\](?= \w+=|$)" % name, line) or re.search(r"(?:^| )%s=(\S*)" % name, line)
    return m.group(1) if m else None
def lines(o, tag): return [l for l in o if l.startswith(tag + " ")]
def info_after(o, step_prefix):
    """the SYMINFO line after the first line that starts with step_prefix"""
    for i, l in enumerate(o):
        if l.startswith(step_prefix):
            for m in o[i + 1:]:
                if m.startswith("SYMINFO "): return m
    return ""
def pins_after(o, step_prefix):
    out = []
    for i, l in enumerate(o):
        if l.startswith(step_prefix):
            for m in o[i + 1:]:
                if m.startswith("SYMPIN "): out.append(m)
                elif m.startswith("SYM ") or m.startswith("SYMPROPS") or m.startswith("SYMPARTS"): break
            return out
    return out
# ---- the oracle: the library file read with sqlite3 and ElementTree
def names(path):
    c = sqlite3.connect(path)
    rows = c.execute("select NameID,Name,SymbolID,Type,Reference,ppp,Description,ShowName,ShowRef,DefRotate from Name order by NameID").fetchall()
    c.close(); return rows
def by_name(path): return {r[1]: r for r in names(path)}
def atts(path, nameid):
    c = sqlite3.connect(path)
    rows = c.execute("select AttName,AttValue,ShowAtt from Attribute where NameID=? order by AttributeID", (nameid,)).fetchall()
    c.close(); return rows
def drawing(path, symid):
    c = sqlite3.connect(path)
    r = c.execute("select Data from Symbol where SymbolID=?", (symid,)).fetchone()
    c.close()
    if r is None: return None
    d = r[0] if isinstance(r[0], bytes) else r[0].encode("utf-8")
    return ET.fromstring(d)
def sheets(root): return [root] if root.tag == "TinyCAD" else root.findall("TinyCAD")
def xpins(root):
    out = []
    for si, sh in enumerate(sheets(root)):
        for p in sh.findall("PIN"):
            x, y = (float(v) for v in p.get("pos").split(","))
            out.append(dict(sheet=si, part=int(p.get("part")), num=p.get("number"), x=x, y=y, dir=int(p.get("direction")), length=int(p.get("length")), name=(p.text or ""), which=int(p.get("which")), elec=int(p.get("elec")), show=int(p.get("show")), numpos=int(p.get("number_pos")), centre=int(p.get("centre_name"))))
    return out
def sympins(lines_):
    out = []
    for l in lines_:
        out.append(dict(sheet=int(field(l, "sheet")), part=int(field(l, "part")), num=field(l, "num"), x=float(field(l, "x")), y=float(field(l, "y")), dir=int(field(l, "dir")), length=int(field(l, "len"))))
    return out
def sets_of(o):
    d = {}
    for l in lines(o, "SYMSET"):
        d[field(l, "names").split("|")[0]] = (int(l.split()[1]), int(field(l, "id")), int(field(l, "ppp")))
    return d
def libcopy(name, dest):
    src = os.path.join(EX, "libraries", name)
    shutil.copy(src, dest); return dest
if not all(os.path.exists(os.path.join(EX, "libraries", n)) for n in ("gen_passive.TCLib", "IC-OPAMP.TCLib", "Mechanical.TCLib")):
    print("Symbol editor checks skipped: need the example libraries in", EX); sys.exit(0)

# ======================================================================= 1. a new symbol
d1 = os.path.join(tmp, "l1"); os.makedirs(d1)
A = libcopy("gen_passive.TCLib", os.path.join(d1, "a.TCLib"))
before = names(A)
o, rc, err = run("""lib %s
sym new=0
tool wire
tool pin
clickmm 20 20
clickmm 20 30
mouse move 40 40
tool origin
clickmm 24 26
tool select
syminfo
symprops desc="A test part" orient=2 cell=1:1:"Never Show" cell=1:2:"X?" cell=2:2:TESTPART addfield=1 cell=4:0:Tolerance cell=4:1:"Show Value (Extra Only)" cell=4:2:5%% model=".model D1N" prolog="* pro" epilog="* epi" prologpri=3 epilogpri=7 ok=1
syminfo
sym store=1
symsets 0
""" % A, "new")
check("1 program ran", rc == 0 and any(l.startswith("SYM store") for l in o), (rc, err[-300:]))
hdr = [l for l in o if l.startswith("SYMINFO")]
check("1 a new symbol starts as New symbol, unmodified, one part, no origin", len(hdr) >= 1 and field(hdr[0], "name") == "New symbol" and field(hdr[0], "modified") == "0" and field(hdr[0], "origin") == "none" and field(hdr[0], "parts") == "1", hdr[:1])
st = [l for l in o if l.startswith("SYM store")]
check("1 store ok", st and field(st[0], "ok") == "1", st)
after = names(A); bn = by_name(A)
check("1 one name more, the old ones unchanged", len(after) == len(before) + 1 and all(r in after for r in before), (len(before), len(after)))
nm = bn.get("TESTPART")
check("1 the Name row: reference X?, description, parts 1, ShowName 2 (Never Show), ShowRef 2... (display methods as typed), rotation", nm is not None and nm[4] == "X?" and nm[6] == "A test part" and nm[5] == 1 and nm[9] == 2, nm)
check("1 Name row display methods: name 'Show Value Only' = 0, reference 'Never Show' = 2", nm is not None and nm[7] == 0 and nm[8] == 2, nm)
root = drawing(A, nm[2]) if nm else None
check("1 the stored drawing is XML with two pins numbered 1 and 2 at the clicked spots", root is not None and [(p["num"], p["x"], p["y"]) for p in xpins(root)] == [("1", 20.0, 20.0), ("2", 20.0, 30.0)], None if root is None else xpins(root))
check("1 the stored drawing has the origin", root is not None and any(e.get("pos") == "24.00000,26.00000" for e in sheets(root)[0].findall("ORIGIN")), None if root is None else [ET.tostring(e) for e in sheets(root)[0].findall("ORIGIN")])
if nm:
    at = {a[0]: a for a in atts(A, nm[0])}
    check("1 attribute Tolerance with value 5%% and display 'Show Value (Extra Only)' (3)", at.get("Tolerance") == ("Tolerance", "5%", 3), at.get("Tolerance"))
    check("1 SPICE fields kept as hidden attributes", at.get("$$SPICE", (0, 0, 0))[1:] == (".model D1N", 2) and at.get("$$SPICE_PROLOG", (0, 0, 0))[1] == "* pro" and at.get("$$SPICE_EPILOG", (0, 0, 0))[1] == "* epi", at)
    check("1 SPICE priorities", at.get("$$SPICE_PROLOG_PRIORITY", (0, 0, 0))[1] == "3" and at.get("$$SPICE_EPILOG_PRIORITY", (0, 0, 0))[1] == "7", at)
    check("1 a Package attribute is added, hidden", at.get("Package", (0, 0, 0))[2] == 1, at.get("Package"))
ss = sets_of(o)
check("1 the library list shows the new symbol (set of the library)", "TESTPART" in ss and ss["TESTPART"][1] == (nm[2] if nm else -1), ss.get("TESTPART"))
tail = [l for l in o if l.startswith("SYMINFO")][-1]
check("1 after the store the document is unmodified, named by the symbol and tied to its id", field(tail, "modified") == "0" and field(tail, "name") == "TESTPART (symbol)" and field(tail, "source") == str(nm[2] if nm else -1), tail)
mid = [l for l in o if l.startswith("SYMINFO")][1]
check("1 pins: the SYMPIN lines are the clicked pins (counted on)", [(p["num"], p["x"], p["y"]) for p in sympins(lines(o, "SYMPIN")[:2])] == [("1", 20.0, 20.0), ("2", 20.0, 30.0)], lines(o, "SYMPIN")[:2])
check("1 origin shown (snapped to the grid)", field(mid, "origin") == "24.000,26.000", mid)
check("1 Symbol Properties starts with the library name, one part, empty name, OK/Cancel", any(l.startswith("SYMPROPS start") and "lib=[Library: a]" in l and "parts=[Parts per package: 1]" in l and "tabs=[Attributes|SPICE]" in l for l in o))
check("1 default attributes of a new symbol: Reference U? hidden, Name, Package hidden", any(l.startswith("SYMPROPS start") and "grid=[Reference~Hide Value~U?;Name~Show Value Only~;Package~Hide Value~package name for PCB layout]" in l for l in o))

# ======================================================================= 2. problems stop the store
d2 = os.path.join(tmp, "l2"); os.makedirs(d2)
B = libcopy("gen_passive.TCLib", os.path.join(d2, "b.TCLib"))
before = names(B)
o, rc, err = run("""lib %s
sym new=0
tool pin
clickmm 20 20
clickmm 20 20
sym store=1
symprops cell=2:2:DUP addname=1 cell=2:2:DUP ok=1
sym store=1
symprops select=1 cell=2:2:SECOND ok=1
sym store=1
""" % B, "problems")
stores = [l for l in o if l.startswith("SYM store")]
check("2 program ran", rc == 0 and len(stores) == 3, (rc, err[-300:]))
check("2 no name: refused with the reason, and a pin on a pin", stores and field(stores[0], "ok") == "0" and "Name 1 is empty" in stores[0], stores[:1])
check("2 two pins on one spot: refused", stores and "are on top of each other" in stores[0], stores[:1])
check("2 a repeated name: refused", len(stores) > 1 and field(stores[1], "ok") == "0" and 'The name "DUP" is used twice' in stores[1], stores[1:2])
check("2 after the pins are apart... still refused for the pins", len(stores) > 2 and field(stores[2], "ok") == "0", stores[2:3])
check("2 refused stores leave the library as it was", names(B) == before)
o, rc, err = run("""lib %s
sym new=0
tool pin
clickmm 20 20
clickmm 20 30
symprops cell=2:2:LONELY ok=1
sym store=1
""" % B, "warn")
stores = [l for l in o if l.startswith("SYM store")]
check("2 numbered pins on the grid and a name: stored", stores and field(stores[0], "ok") == "1", stores)

# ======================================================================= 3. edit an existing symbol
d3 = os.path.join(tmp, "l3"); os.makedirs(d3)
C = libcopy("gen_passive.TCLib", os.path.join(d3, "c.TCLib"))
before = names(C); bn = by_name(C)
R = bn["R"]; Rpins = xpins(drawing(C, R[2])); Ratt = atts(C, R[0])
o, rc, err = run("""lib %s
symsets 0
sym edit=0:0
syminfo
sym edit=0:0
sym edit=0:1
docs
sym edit=0:0
tool pin
clickmm 60 60
syminfo
sym store=1
symsets 0
""" % C, "edit")
check("3 program ran", rc == 0, (rc, err[-300:]))
i1 = [l for l in o if l.startswith("SYMINFO")]
check("3 edit opens R: name R (symbol), parts 1, source id = its id", i1 and field(i1[0], "name") == "R (symbol)" and field(i1[0], "source") == str(R[2]) and field(i1[0], "modified") == "0", i1[:1])
pl = [l for l in o if l.startswith("SYMPIN")]
shown = sympins(pl[:len(Rpins)])
check("3 the pins shown are those of the stored XML", [(p["num"], p["x"], p["y"], p["dir"], p["length"]) for p in shown] == [(p["num"], p["x"], p["y"], p["dir"], p["length"]) for p in Rpins], (shown, Rpins))
dl = [l for l in o if l.startswith("DOCS")]
check("3 the same symbol opened twice is one document, another symbol a second", dl and field(dl[0], "current") == "1" and dl[0].startswith("DOCS 2 "), dl)
stores = [l for l in o if l.startswith("SYM store")]
check("3 store ok after a pin was added", stores and field(stores[0], "ok") == "1", stores)
bn2 = by_name(C); R2 = bn2.get("R")
check("3 R keeps its name, reference and description, but has a new symbol id", R2 and R2[4] == R[4] and R2[6] == R[6] and R2[2] != R[2], (R, R2))
check("3 R has one pin more than before, at the clicked spot", R2 and len(xpins(drawing(C, R2[2]))) == len(Rpins) + 1 and any(p["x"] == 60.0 and p["y"] == 60.0 for p in xpins(drawing(C, R2[2]))), None if not R2 else xpins(drawing(C, R2[2])))
check("3 R's attributes survive", R2 and atts(C, R2[0]) == Ratt, (Ratt, None if not R2 else atts(C, R2[0])))
check("3 the old symbol row is gone", sqlite3.connect(C).execute("select count(*) from Symbol where SymbolID=?", (R[2],)).fetchone()[0] == 0)
check("3 every other name is unchanged", all(r in names(C) for r in before if r[1] != "R"))

# ======================================================================= 4. Symbol Properties: aliases, attributes, cancel
d4 = os.path.join(tmp, "l4"); os.makedirs(d4)
M = libcopy("Mechanical.TCLib", os.path.join(d4, "m.TCLib"))
M0 = names(M)
c = sqlite3.connect(M)
multi = c.execute("select SymbolID from Name group by SymbolID having count(*)>=3 limit 1").fetchone()[0]
nm4 = c.execute("select Name from Name where SymbolID=? order by NameID", (multi,)).fetchall(); nm4 = [x[0] for x in nm4]
c.close()
o, rc, err = run("""lib %s
symsets 0
""" % M, "m0")
pos = [int(l.split()[1]) for l in lines(o, "SYMSET") if field(l, "names").split("|")[:-1] == nm4][0]
o, rc, err = run("""lib %s
sym edit=0:%d
symprops cancel=1
symprops desc=ZZZ select=1 delname=1 cancel=1
syminfo
symprops select=1 desc="Alias text" cell=1:2:"new alias" delname=1 select=0 addname=1 cell=2:2:BRANDNEW desc="New one" addfield=1 cell=4:2:77 addfield=1 delfield=5 ok=1
sym store=1
""" % (M, pos), "props")
check("4 program ran", rc == 0, (rc, err[-300:]))
sp = [l for l in o if l.startswith("SYMPROPS start")]
check("4 the dialog lists all the names of the symbol, the first showing", sp and field(sp[0], "names") == "|".join(nm4) and field(sp[0], "cur") == "0", (sp[:1], nm4))
check("4 cancel leaves the symbol as it was (not modified)", any(l.startswith("SYMINFO") and field(l, "modified") == "0" for l in o))
st = [l for l in o if l.startswith("SYM store")]
check("4 store ok", st and field(st[0], "ok") == "1", st)
bnM = by_name(M)
after_names = [r[1] for r in names(M) if r[2] == bnM["BRANDNEW"][2]]
check("4 the symbol's names now: the deleted alias is gone, the new one is last", after_names == [nm4[0], nm4[2], nm4[3], "BRANDNEW"], after_names)
check("4 each name keeps its own description", bnM["ENCLOSURE_7.6_4.6_2.37"][6] == "7.6\" X 4.6\" X 2.37\" Black plastic enclosure" and bnM["BRANDNEW"][6] == "New one", (bnM["ENCLOSURE_7.6_4.6_2.37"][6], bnM["BRANDNEW"][6]))
check("4 the new name started as a copy of the first (reference MECH?, same Manufacturer)", bnM["BRANDNEW"][4] == "MECH?" and dict((a[0], a[1]) for a in atts(M, bnM["BRANDNEW"][0])).get("Manufacturer") == "Radio Shack", atts(M, bnM["BRANDNEW"][0])[:14])
ba = atts(M, bnM["BRANDNEW"][0]); bn_ = [a[0] for a in ba]
check("4 attribute edits reach the database: Usage 77, Datasheet deleted, two new 'Other' attributes shown", dict((a[0], a[1]) for a in ba).get("Usage") == "77" and "Datasheet" not in bn_ and bn_.count("Other") == 2, bn_)
c = sqlite3.connect(M)
orph = c.execute("select count(*) from Attribute where NameID not in (select NameID from Name)").fetchone()[0]
orph2 = c.execute("select count(*) from Symbol where SymbolID not in (select SymbolID from Name)").fetchone()[0]
c.close()
check("4 no attribute or drawing rows are left over from the deleted alias or the old symbol", orph == 0 and orph2 == 0, (orph, orph2))
check("4 the other symbols are unchanged", all(r in names(M) for r in M0 if r[2] != multi))


def pins_following(o, idx):
    out = []
    for l in o[idx + 1:]:
        if l.startswith("SYMPIN "): out.append(l)
        else: break
    return out
def blocks(o):
    """[(SYMINFO line, [SYMPIN lines])] in order"""
    r = []
    for i, l in enumerate(o):
        if l.startswith("SYMINFO "): r.append((l, pins_following(o, i)))
    return r
def key(p): return (p["sheet"], p["part"], p["num"], p["x"], p["y"], p["dir"], p["length"])
def xkey(p): return (p["sheet"], p["part"], p["num"], p["x"], p["y"], p["dir"], p["length"])

# ======================================================================= 5. parts per package, one drawing shared by the parts
d5 = os.path.join(tmp, "l5"); os.makedirs(d5)
O = libcopy("IC-OPAMP.TCLib", os.path.join(d5, "o.TCLib"))
bo = by_name(O); L339 = bo["LM339"]; Lpins = xpins(drawing(O, L339[2]))
o, rc, err = run("""lib %s
sym edit=0:3
symmenu
symparts cancel=1
symparts parts=3 ok=1
sym part=2
tool pin
clickmm 100 100
sym store=1
symsets 0
""" % O, "parts")
check("5 program ran", rc == 0, (rc, err[-300:]))
bl = blocks(o)
check("5 LM339 opens with 4 parts, one shared drawing, part A showing", bl and field(bl[0][0], "parts") == "4" and field(bl[0][0], "hetero") == "0" and field(bl[0][0], "parttext") == "Part A of 4", bl[:1])
check("5 the pins in the drawing are those of the stored XML, all parts", sorted(key(p) for p in sympins(bl[0][1])) == sorted((0, p["part"], p["num"], p["x"], p["y"], p["dir"], p["length"]) for p in Lpins), (len(bl[0][1]), len(Lpins)))
sm = [l for l in o if l.startswith("SYMMENU")]
check("5 Library menu in a symbol: Pin, Origin, Symbol Properties, Parts, Previous/Next part, Store enabled", sm and all(field(sm[0], k) == "1" for k in ("pin", "origin", "symprops", "parts", "prev", "next", "store")), sm)
pt = [l for l in o if l.startswith("SYMPARTS")]
check("5 a symbol's sheet has no title block (a new symbol's neither)", field(bl[0][0], "titleblock") == "0" and field(hdr[0], "titleblock") == "0", (bl[0][0][:200], hdr[0][:200]))
check("5 a symbol with parts that share one drawing has no sheet tabs (and no + tab to add sheets)", field(bl[0][0], "tabsvisible") == "0" and field(bl[0][0], "tabs") == "Part A|" and field(bl[0][0], "tabsmatch") == "1", bl[0][0])
check("5 the Parts dialog starts with 4 parts, homogeneous; the kind is dimmed with several parts", pt and pt[0] == "SYMPARTS start parts=4 hetero=0 heteroenabled=0", pt[:1])
check("5 Cancel changes nothing", bl[1][0] and field(bl[1][0], "modified") == "0" and field(bl[1][0], "parts") == "4", bl[1:2])
check("5 fewer parts (3) removes the pins of the part that is gone", field(bl[2][0], "parts") == "3" and field(bl[2][0], "modified") == "1" and sorted(key(p) for p in sympins(bl[2][1])) == sorted((0, p["part"], p["num"], p["x"], p["y"], p["dir"], p["length"]) for p in Lpins if p["part"] < 3), (field(bl[2][0], "parts"), len(bl[2][1])))
st = [l for l in o if l.startswith("SYM store")]
check("5 store ok", st and field(st[0], "ok") == "1", st[:1])
bo2 = by_name(O); n339 = bo2["LM339"]
x339 = xpins(drawing(O, n339[2]))
check("5 database: 3 parts, the pins of parts A to C, plus the one placed on part B (100,100)", n339[5] == 3 and sorted((p["part"], p["num"], p["x"], p["y"]) for p in x339) == sorted([(p["part"], p["num"], p["x"], p["y"]) for p in Lpins if p["part"] < 3] + [(1, "1", 100.0, 100.0)]), (n339[5], len(x339)))
check("5 the new pin belongs to the part showing (B)", any(p["part"] == 1 and p["x"] == 100.0 for p in x339), x339[-2:])
check("5 a pin placed fresh has the default length 30 (the first pin of the session copies nothing)", any(p["x"] == 100.0 and p["length"] == 30 for p in x339), [p for p in x339 if p["x"] == 100.0])

# a second run on the stored symbol: part C showing, then parts=2 clamps it to B; the kind cannot be changed with several parts
check("5 database after the first store (read before the second run): 3 parts, the pins of A to C and the new one", n339[5] == 3, n339)
pos = [int(l.split()[1]) for l in lines(o, "SYMSET") if field(l, "names").startswith("LM339")][0]
o, rc, err = run("""lib %s
sym edit=0:%d
sym part=3
symparts parts=2 hetero=1 ok=1
sym store=1
""" % (O, pos), "parts2")
bl = blocks(o)
last = bl[-1][0]
check("5 the second run opened the stored symbol with 3 parts", field(bl[0][0], "parts") == "3", bl[0][0])
check("5 shrinking to 2 parts while part C shows: part B shows; still homogeneous (the kind box was dimmed)", field(bl[-1][0], "parts") == "2" and field(bl[-1][0], "hetero") == "0" and field(bl[1][0], "parttext") == "Part C of 3", (bl[1][0], last))
check("5 second store: ppp 2 in the database and no pin of part C", by_name(O)["LM339"][5] == 2 and all(p["part"] < 2 for p in xpins(drawing(O, by_name(O)["LM339"][2]))))

# ======================================================================= 6. a drawing for each part
d6 = os.path.join(tmp, "l6"); os.makedirs(d6)
H = libcopy("gen_passive.TCLib", os.path.join(d6, "h.TCLib"))
o, rc, err = run("""lib %s
sym new=0
symparts parts=3 hetero=1 ok=1
syminfo
tool pin
clickmm 20 20
sym part=2
tool pin
clickmm 30 30
clickmm 30 40
sym part=3
tool pin
clickmm 40 50
symprops cell=2:2:HETERO ok=1
sym store=1
sym close=1
symsets 0
sym edit=0:19
symparts hetero=0 parts=2
symparts parts=1 hetero=0 ok=1
syminfo
""" % H, "hetero")
check("6 program ran", rc == 0, (rc, err[-300:]))
bl = blocks(o)
check("6 3 parts with a drawing each: 3 sheets, tabs Part A, B, C", field(bl[1][0], "sheets") == "3" and field(bl[1][0], "hetero") == "1" and field(bl[1][0], "tabs") == "Part A|Part B|Part C|" and field(bl[1][0], "tabsvisible") == "1" and field(bl[1][0], "tabsmatch") == "1", bl[1][0])
st = [l for l in o if l.startswith("SYM store")]
check("6 store ok", st and field(st[0], "ok") == "1", st[:1])
bh = by_name(H).get("HETERO")
root = drawing(H, bh[2]) if bh else None
check("6 database: ppp 3 and three sheets in the stored drawing", bh and bh[5] == 3 and root is not None and len(sheets(root)) == 3, None if root is None else (bh, len(sheets(root))))
xp = xpins(root) if root is not None else []
check("6 each sheet holds the pins drawn on it, all as part 0", sorted((p["sheet"], p["part"], p["x"], p["y"]) for p in xp) == [(0, 0, 20.0, 20.0), (1, 0, 30.0, 30.0), (1, 0, 30.0, 40.0), (2, 0, 40.0, 50.0)], xp)
bl = blocks(o)
re_ = [b for b in bl if field(b[0], "name") == "HETERO (symbol)" and field(b[0], "modified") == "0" and field(b[0], "sheets") == "3" and field(b[0], "source") == str(bh[2] if bh else -1)]
check("6 reopened from the library: hetero, 3 sheets, pins by sheet as stored", re_ and sorted((int(field(l, "sheet")), float(field(l, "x")), float(field(l, "y"))) for l in re_[-1][1]) == [(0, 20.0, 20.0), (1, 30.0, 30.0), (1, 30.0, 40.0), (2, 40.0, 50.0)], re_[-1:] )
sp = [l for l in o if l.startswith("SYMPARTS")]
check("6 several parts: the kind box dimmed; after the count is 1 it can be changed", any(l == "SYMPARTS start parts=3 hetero=1 heteroenabled=0" for l in sp) and any(l == "SYMPARTS parts parts=1 hetero=1 heteroenabled=1" or l.startswith("SYMPARTS parts parts=1 hetero=1 heteroenabled=1") for l in sp), sp)
fin = bl[-1][0]
check("6 down to one part and homogeneous: one sheet", field(fin, "sheets") == "1" and field(fin, "hetero") == "0" and field(fin, "parts") == "1", fin)


# ======================================================================= 7. duplicate, delete, copy to
d7 = os.path.join(tmp, "l7"); os.makedirs(d7)
A7 = libcopy("gen_passive.TCLib", os.path.join(d7, "a.TCLib")); B7 = libcopy("DISCRETE.TCLib", os.path.join(d7, "b.TCLib"))
a0 = names(A7); b0 = names(B7); an = by_name(A7)
R = an["R"]; Rd = drawing(A7, R[2]); Ratt = atts(A7, R[0])
Lr = an["L"]; Lcore = an["L_CORE"]
Cap = an["C_ELECTROLYTIC"]; CapC = an["C"]
o, rc, err = run("""lib %s
lib %s
sym dup=0:0
sym edit=0:2
sym delete=0:2
sym delete=0:1
sym copy=0:4:1
libselect 1
sym cmd=duplicate
libclose 0
libraries select=a remove=1 ok=1
""" % (A7, B7), "dupdel")
check("7 program ran", rc == 0, (rc, err[-300:]))
st = [l for l in o if l.startswith("SYM ")]
d = {field(l.replace("SYM ", "x=", 1).replace("x=", "step=", 1), "ok") for l in st}
steps = [(l.split()[1], field(l, "ok"), field(l, "msg")) for l in st]
check("7 duplicate, a delete of the symbol being edited refused, delete, copy to, duplicate on the list's selection", steps[:6] == [("dup", "1", ""), ("edit", "1", ""), ("delete", "0", "This symbol is being edited. Close it before deleting it."), ("delete", "1", ""), ("copy", "1", ""), ("cmd", "1", "")], steps)
a1 = by_name(A7)
dup = a1.get("R copy")
check("7 Duplicate: R copy has R's reference, description, parts and attributes", dup and dup[4] == R[4] and dup[6] == R[6] and dup[5] == R[5] and atts(A7, dup[0]) == Ratt, dup)
dd = drawing(A7, dup[2]) if dup else None
check("7 ... and R's drawing (same pins, same kinds of elements)", dd is not None and sorted(xkey(p) for p in xpins(dd)) == sorted(xkey(p) for p in xpins(Rd)) and sorted(e.tag for e in sheets(dd)[0]) == sorted(e.tag for e in sheets(Rd)[0]), None if dd is None else (len(xpins(dd)), len(xpins(Rd))))
check("7 Duplicate leaves R itself as it was", a1["R"] == R)
c = sqlite3.connect(A7)
gone = c.execute("select count(*) from Name where Name='L'").fetchone()[0], c.execute("select count(*) from Symbol where SymbolID=?", (Lr[2],)).fetchone()[0], c.execute("select count(*) from Attribute where NameID=?", (Lr[0],)).fetchone()[0]
orph = c.execute("select count(*) from Attribute where NameID not in (select NameID from Name)").fetchone()[0], c.execute("select count(*) from Symbol where SymbolID not in (select SymbolID from Name)").fetchone()[0]
c.close()
check("7 Delete: the Name, Symbol and Attribute rows of L are gone, nothing is left over", gone == (0, 0, 0) and orph == (0, 0), (gone, orph))
check("7 every other symbol of the library is unchanged", all(r in names(A7) for r in a0 if r[1] not in ("L",)), [r for r in a0 if r not in names(A7)][:3])
check("7 the symbol being edited when delete was refused is still there", "L_CORE" in a1 and a1["L_CORE"] == Lcore)
b1 = by_name(B7)
check("7 Copy to: C_ELECTROLYTIC (position 4 once L was deleted) is now also in the other library, same reference, description and attributes", "C_ELECTROLYTIC" in b1 and b1["C_ELECTROLYTIC"][4] == Cap[4] and b1["C_ELECTROLYTIC"][6] == Cap[6] and [a[:2] for a in atts(B7, b1["C_ELECTROLYTIC"][0])] == [a[:2] for a in atts(A7, Cap[0])] and "C_ELECTROLYTIC" in a1, b1.get("C_ELECTROLYTIC"))
check("7 ... and its drawing, and the other library has one more name only", sorted(xkey(p) for p in xpins(drawing(B7, b1["C_ELECTROLYTIC"][2]))) == sorted(xkey(p) for p in xpins(drawing(A7, Cap[2]))) and len(names(B7)) == len(b0) + 1, (len(names(B7)), len(b0)))
c_copy = by_name(A7).get("C copy")
check("7 the list's Duplicate command acted on the row chosen (libselect 1 is C of the first library: the panel lists the symbols alphabetically, BUZZER first): C copy with C's attributes", c_copy and atts(A7, c_copy[0]) == atts(A7, CapC[0]) and c_copy[6] == CapC[6], c_copy)
lc = [l for l in o if l.startswith("LIBCLOSE")]
check("7 a library cannot be closed while one of its symbols is being edited", lc and field(lc[0], "libs") == "2", lc)
lr = [l for l in o if l.startswith("LIBRARIES remove")]
check("7 ... nor removed in Library Setup: TinyCAD's message, the library stays in the list", lr and "Cannot delete a library while it is being edited" in lr[0] and field(lr[0], "items") == "a|b", lr)

# ======================================================================= 8. tools
o, rc, err = run("""newdoc A4
tool pin
ribbonstate
tool origin
ribbonstate
tool wire
ribbonstate
symmenu
lib %s
sym edit=0:0
symmenu
tool wire
ribbonstate
tool bus
ribbonstate
tool label
ribbonstate
tool junction
ribbonstate
tool power
ribbonstate
tool place
ribbonstate
tool pin
ribbonstate
tool line
ribbonstate
tool origin
ribbonstate
addsheet
syminfo
removesheet
renamesheet X
movesheet 1
syminfo
""" % A7, "tools")
check("8 program ran", rc == 0, (rc, err[-300:]))
rs = [int(field(l, "tool")) for l in lines(o, "RIBBONSTATE")]
# tool numbers: select 0, wire 1, line 2, ..., pin 24, origin 25
check("8 in a design the Pin and Origin tools are refused, wire works", rs[:3] == [0, 0, 1], rs[:3])
sm = lines(o, "SYMMENU")
check("8 Library menu in a design: Pin, Origin, Symbol Properties, Parts and Store are dimmed", sm and all(field(sm[0], k) == "0" for k in ("pin", "origin", "symprops", "parts", "store", "prev", "next")), sm[:1])
check("8 in a symbol they are on", len(sm) > 1 and all(field(sm[1], k) == "1" for k in ("pin", "origin", "symprops", "parts", "store")) and field(sm[1], "prev") == "0", sm[1:2])
check("8 in a symbol: wire, bus, label, junction, power and place are refused (the tool stays Select)", rs[3:9] == [0, 0, 0, 0, 0, 0], rs)
check("8 in a symbol: Pin, Line and Origin tools work", rs[9:12] == [24, 2, 25], rs[9:12])
bl = blocks(o)
check("8 Add sheet, Remove, Rename, Move do nothing to a symbol (one sheet, status says why)", bl and field(bl[-1][0], "sheets") == "1" and "Parts per Package" in field(bl[-1][0], "status"), bl[-1:])

# ======================================================================= 9. library in use, Save All, title, undo
d9 = os.path.join(tmp, "l9"); os.makedirs(d9)
A9 = libcopy("gen_passive.TCLib", os.path.join(d9, "a.TCLib"))
a9 = names(A9)
o, rc, err = run("""lib %s
sym new=0
tool pin
clickmm 20 20
tool pin
clickmm 20 30
undo
syminfo
redo
symprops cell=2:2:SAVEALL ok=1
newdoc A4
saveall
docs
gotodoc 0
syminfo
symparts parts=2 hetero=1 ok=1
tool pin
clickmm 30 30
sym part=2
tool pin
clickmm 30 40
undo
syminfo
""" % A9, "saveall")
check("9 program ran", rc == 0, (rc, err[-300:]))
bl = blocks(o)
check("9 Undo takes the last placed pin away in a symbol (one of two left)", len(bl[1][1]) == 1 and field(bl[1][0], "modified") == "1", bl[1])
sa = lines(o, "SAVEALL")
check("9 Save All stores the symbol (named by Properties); the untouched new design is not written", sa and sa[0] == "SAVEALL saved=1 skipped=0 failed=0", sa)
bn = by_name(A9)
check("9 the symbol is in the library with its two pins", "SAVEALL" in bn and len(xpins(drawing(A9, bn["SAVEALL"][2]))) == 2, bn.get("SAVEALL"))
check("9 the other symbols are unchanged", all(r in names(A9) for r in a9))
check("9 the stored symbol's document is unmodified and named by the symbol", field(bl[3][0], "modified") == "0" and field(bl[3][0], "name") == "SAVEALL (symbol)" and field(bl[2][0], "modified") == "1", (bl[2][0], bl[3][0]))
last = bl[-1][0]
check("9 undo in a symbol with a drawing for each part keeps the kind: 2 sheets, hetero", field(last, "hetero") == "1" and field(last, "sheets") == "2" and field(last, "parts") == "2", last)


# ======================================================================= 10. pin properties and counting on
d10 = os.path.join(tmp, "l10"); os.makedirs(d10)
P10 = libcopy("gen_passive.TCLib", os.path.join(d10, "p.TCLib"))
o, rc, err = run("""lib %s
sym new=0
tool pin
clickmm 20 20
setprop pin.number A9
setprop pin.name P9
setprop pin.length 40
setprop pin.dir Left
setprop pin.shape Clock
setprop pin.elec Output
setprop pin.numpos 2
setprop pin.showname 0
setprop pin.centre 1
tool pin
clickmm 20 30
setprop pin.length 3
props
tool pin
clickmm 20 40
setprop pin.length 0
props
undo
props
symprops cell=2:2:PINS ok=1
sym store=1
""" % P10, "pins")
check("10 program ran", rc == 0, (rc, err[-300:]))
bp = by_name(P10).get("PINS")
xp = xpins(drawing(P10, bp[2])) if bp else []
check("10 first pin as set: number, name, length, direction Left (2), Clock (2), Output (1), number position 2, name hidden (show 2), centred", xp and (xp[0]["num"], xp[0]["name"], xp[0]["length"], xp[0]["dir"], xp[0]["which"], xp[0]["elec"], xp[0]["numpos"], xp[0]["show"], xp[0]["centre"]) == ("A9", "P9", 40, 2, 2, 1, 2, 2, 1), xp[:1])
check("10 the next pins count on (A10/P10, A11/P11) and copy the previous pin's direction, type and settings", len(xp) == 3 and [(p["num"], p["name"], p["dir"], p["which"], p["elec"], p["show"], p["centre"]) for p in xp[1:]] == [("A10", "P10", 2, 2, 1, 2, 1), ("A11", "P11", 2, 2, 1, 2, 1)], xp[1:])
pr = lines(o, "PROPS")
check("10 a length of 3 is made 5 (a length is 0 or at least 5), and 0 is allowed", len(pr) >= 2 and "pin.length=5;" in pr[0] and "pin.length=0;" in pr[1], pr[:2])
check("10 undo of the length change brings the length back; the stored third pin has the length of the second (5)", len(pr) > 2 and "pin.length=5;" in pr[2] and len(xp) == 3 and xp[2]["length"] == 5, (pr[2:], xp[2:] ))


# ======================================================================= 11. the Symbols menu's commands are made in the form file (mainform.lfm), each with a caption, a hint and its handler
lfm = open(os.path.join(HERE, "..", "src", "forms", "mainform.lfm"), encoding="utf-8").read()
menu = lfm[lfm.index("object mSymbol: TMenuItem"):lfm.index("object mParts: TMenuItem")]
items = re.findall(r"object (miSym\w+|sepSymbol\d): TMenuItem\n(.*?)\n      end", menu, re.S)
cmds = [(n, b) for n, b in items if not n.startswith("sep")]
check("11 the Symbols menu has its 15 symbol commands in the form file, each with a hint and a handler",
      len(cmds) == 15 and all("Hint = '" in b and "OnClick = " in b for n, b in cmds), [n for n, b in cmds])
check("11 the Pin and Origin items are radio items of the tool group, tagged with their tools", all(("RadioItem = True" in b and "GroupIndex = 2" in b) for n, b in cmds if n in ("miSymPin", "miSymOrigin")) and len(items) == 18, len(items))
src0 = open(os.path.join(HERE, "..", "src", "forms", "mainform.pas"), encoding="utf-8").read()
check("11 the menu is no longer made in code", "mSymbol.Add(" not in src0 and "mLIbrary" not in src0)

# ======================================================================= 12. Symbol properties on a symbol in the library list: the dialog alone, stored straight into the library
def drawings(path):
    c = sqlite3.connect(path)
    rows = sorted(r[0] for r in c.execute("select Data from Symbol").fetchall())
    c.close(); return rows      # (a store gives the symbol a new SymbolID, so the drawings are compared as a set)
d12 = os.path.join(tmp, "l12"); os.makedirs(d12)
Q = libcopy("gen_passive.TCLib", os.path.join(d12, "q.TCLib"))
before = names(Q); dr_before = drawings(Q)
o, rc, err = run("""lib %s
symprops lib=0:0 desc="Edited here" cell=2:2:RENAMED ok=1
syminfo
""" % Q, "standalone")
check("12 program ran", rc == 0, (rc, err[-300:]))
st = lines(o, "SYMPROPS")
check("12 the dialog starts with the symbol's name and OK / Cancel", st and "start" in st[0], st[:1])
stored = [l for l in st if l.startswith("SYMPROPS stored")]
check("12 OK stores it", stored and field(stored[0], "ok") == "1" and "Symbol stored" in stored[0], stored)
si = [l for l in o if l.startswith("SYMINFO")]
check("12 no editor tab was made", si and field(si[-1], "symbol") == "0" and field(si[-1], "docs") == "0", si[-1:])
after = names(Q)
# (a store writes the symbol's name rows again, so the oracle compares rows without their NameID)
nb = sorted(r[1:] for r in before); na = sorted(r[1:] for r in after)
gone = [r for r in nb if r not in na]; came = [r for r in na if r not in nb]
check("12 exactly one name row changed; none added or lost", len(after) == len(before) and len(gone) == 1 and len(came) == 1, (len(before), len(after), gone, came))
if gone and came:
    r = came[0]; ro = gone[0]
    check("12 the row has the new name and description and everything else as it was (type, reference, parts) and a drawing under its symbol id", r[0] == "RENAMED" and r[5] == "Edited here" and (r[2], r[3], r[4]) == (ro[2], ro[3], ro[4]) and drawing(Q, r[1]) is not None, (r, ro))
def same_drawings(now, was, edited):
    """every drawing but at most `edited` of them byte for byte; those are the same objects written again (the design writer adds attributes such as polygon='0')"""
    rest_now = list(now); rest_was = list(was); diff = []
    for d in list(rest_now):
        if d in rest_was: rest_now.remove(d); rest_was.remove(d)
    if len(rest_now) != len(rest_was) or len(rest_now) > edited: return False
    def tags(b): return sorted(e.tag + ":" + str(sorted((k, v) for k, v in e.attrib.items() if k != "polygon")) for e in ET.fromstring(b).iter())
    return all(any(tags(a) == tags(b) for b in rest_was) for a in rest_now)
check("12 every other symbol's drawing is exactly as it was, and the edited one holds the same objects", same_drawings(drawings(Q), dr_before, 1))

# Cancel changes nothing, not even the file
raw = open(Q, "rb").read()
o, rc, err = run("""lib %s
symprops lib=0:1 desc="Never" cell=2:2:NEVER cancel=1
syminfo
""" % Q, "standalonecancel")
check("12 Cancel: the library file is byte for byte as it was", open(Q, "rb").read() == raw)
si = [l for l in o if l.startswith("SYMINFO")]
check("12 Cancel: no tab", si and field(si[-1], "docs") == "0", si[-1:])

# a problem stops the store, says why and leaves the file alone
o, rc, err = run("""lib %s
symprops lib=0:1 cell=2:2: ok=1
symprops lib=0:1 addname=1 cell=2:2:TWIN select=0 cell=2:2:TWIN ok=1
syminfo
""" % Q, "standaloneprob")
stored = [l for l in o if l.startswith("SYMPROPS stored")]
check("12 an empty name is refused with the reason", len(stored) >= 1 and field(stored[0], "ok") == "0" and "is empty" in stored[0], stored[:1])
check("12 a repeated name is refused", len(stored) >= 2 and field(stored[1], "ok") == "0" and "used twice" in stored[1], stored[1:2])
check("12 refused changes leave the file as it was", open(Q, "rb").read() == raw)

# aliases: added and removed in the same dialog
before = names(Q)
o, rc, err = run("""lib %s
symprops lib=0:0 addname=1 cell=2:2:ALIAS_ONE desc="an alias" ok=1
""" % Q, "standalonealias")
after = names(Q)
added = [r for r in after if r[1] == "ALIAS_ONE"]
check("12 an alias added in the dialog is stored with the symbol", len(after) == len(before) + 1 and len(added) == 1 and drawing(Q, added[0][2]) is not None, (added, len(before), len(after)))
check("12 the drawings are still the same objects", same_drawings(drawings(Q), dr_before, 2))

# ======================================================================= done
shutil.rmtree(tmp, ignore_errors=True)
print("symbol editor: %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
