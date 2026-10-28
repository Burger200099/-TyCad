#!/usr/bin/env python3
"""Parts library editor, part list (Phase B2): the editor is a tab of the document strip; add / properties / duplicate / delete parts and the library's own details,
on the real program under Xvfb (script commands 'peopen' and 'pe ...' = the editor's calls without their dialogs).
Oracles (independent of the program): the file is read with Python's sqlite3 and compared with expectations written here from the sample library built by
docs/parts_seed.py: rows, revision arithmetic, row counts of every table that belongs to a part, the structure of the copied child objects, foreign key
and integrity checks.
  - the tab: opens as a document after the designs, the same file does not open twice, the tab caption names the library, the list equals the file
  - add: the row (class, prefix, status active, revision 1, a modified stamp, a GUID); refused for a taken name, an empty name, an abstract class, no class
  - properties: new values, revision + 1, modified stamp; refused for a bad status or a taken name (nothing changes then)
  - duplicate: every table that belongs to a part has the same number of rows for the copy; object tree, ratings per object name, links, symbol pins and the default
    symbol follow the copy; the original is untouched; GUID and name differ; a taken name is refused
  - delete: nothing of the part is left in any table; the products stay; other parts are untouched; foreign keys clean; the suggestion count is reported
  - library details: name, description, author written, empty name refused
  - the Parts tab of the library panel shows the changes (read again)
  - dialog: lists the classes that can hold parts (not abstract), class fixed when changing a part; the menu items are in the lfm and enabled as the tab and choice say
Needs the built program and xvfb."""
import os, re, shutil, sqlite3, subprocess, sys, tempfile, uuid
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Parts editor checks skipped: need xvfb-run and the built program"); sys.exit(0)
sys.path.insert(0, os.path.join(ROOT, "docs")); import parts_seed
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:700])
def run(lines):
    h = tempfile.mkdtemp(dir=tmp); f = os.path.join(tmp, "s.txt"); open(f, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
def mk(name):
    p = os.path.join(tmp, name); parts_seed.build(p).close(); return p
def db(p):
    c = sqlite3.connect(p); c.execute("pragma foreign_keys=ON"); return c
def pe(o, sub): return [l for l in o if l.startswith("PE " + sub + " ")]
def rows(o): return [l[len("PEROW "):].split("|") for l in o if l.startswith("PEROW ")]
PARTTABLES = {"PartValue": "PartID", "PartObject": "PartID", "Rating": "PartID", "Link": "PartID", "Symbol": "PartID", "PartGlyph": "PartID", "PartTag": "PartID", "PartRule": "PartID", "PartProduct": "PartID"}
def counts(c, pid):
    d = {t: c.execute("select count(*) from %s where %s=?" % (t, k), (pid,)).fetchone()[0] for t, k in PARTTABLES.items()}
    d["ObjectValue"] = c.execute("select count(*) from ObjectValue where ObjectID in (select ObjectID from PartObject where PartID=?)", (pid,)).fetchone()[0]
    d["SymbolPin"] = c.execute("select count(*) from SymbolPin where SymbolID in (select SymbolID from Symbol where PartID=?)", (pid,)).fetchone()[0]
    return d
f = mk("a.TCParts")
c0 = db(f)
seed_parts = c0.execute("select p.Name,c.Name from Part p join PartClass c using(ClassID) order by lower(c.Name),lower(p.Name)").fetchall()
cont = c0.execute("select PartID from Part where Name like 'Contactor%'").fetchone()[0]
sid = c0.execute("select SymbolID from Symbol where PartID=?", (cont,)).fetchone()[0]
for oid, in c0.execute("select ObjectID from PartObject where PartID=? and Name like '%T%' limit 3", (cont,)).fetchall():
    c0.execute("insert into SymbolPin values (?,?,?,?,?)", (sid, oid, 70.0 + oid, 40.0, 1))
c0.execute("insert into PartTag values (?, 'relay')", (cont,)); c0.execute("insert into PartTag values (?, 'power')", (cont,))
c0.execute("insert into PartRule(PartID,Kind,TargetClassID,Note) values (?, 'requires', (select ClassID from PartClass where Name='Breaker'), 'needs a breaker')", (cont,))
# things that point INTO the contactor and would block its deletion: a product's outline terminal, a model terminal, another part's rule
pid1 = c0.execute("select ProductID from Product where MPN='CTR-25-24DC'").fetchone()[0]
oid1 = c0.execute("select ObjectID from PartObject where PartID=? limit 1", (cont,)).fetchone()[0]
oc = c0.execute("insert into Outline2D(ProductID,Name,Drawing) values (?, 'o', x'00')", (pid1,)).lastrowid
c0.execute("insert into OutlineTerminal values (?,?,1,2)", (oc, oid1))
mc = c0.execute("insert into Model3D(ProductID,Format) values (?, 'step')", (pid1,)).lastrowid
c0.execute("insert into ModelTerminal(ModelID,ObjectID) values (?,?)", (mc, oid1))
c0.execute("insert into PartRule(PartID,Kind,TargetPartID) values ((select PartID from Part where Name like 'Analog%'), 'recommends', ?)", (cont,))
c0.commit()
before = counts(c0, cont); c0.close()
# ---- the tab, add, properties, duplicate, delete, info, panel refresh in one session
o = run(["newdoc \"ISO A4\" landscape", "pdbtab open " + f, "peopen " + f, "peopen " + f, "pe rows", "pe menu", "pe select 1", "pe menu",
         "pe add Test relay|Relay|KR|A test relay", "pe add Test relay|Relay|KR|again", "pe add |Relay|K|x", "pe add Abstract|SwitchingDevice|K|x", "pe add NoClass|Nothing|K|x",
         "pe rows", "pdbtab rows"])
op = [l for l in o if l.startswith("PEOPEN")]
check("the editor opens as a second tab (after the design), the same file again does not open another", len(op) == 2 and "docs=2 current=1" in op[0] and "docs=2 current=1" in op[1], op)
check("the tab caption names the library", "caption=Sample parts (parts)" in op[0], op)
R = rows(o[:o.index(next(l for l in o if l.startswith("PE add ok")))]) if any(l.startswith("PE add ok") for l in o) else []
check("the list equals the file: the sample's parts ordered by class then name", [(r[1], r[2]) for r in R] == seed_parts, (R, seed_parts))
M = [l for l in o if l.startswith("PEMENU")]
check("menu: Add always, the others only with a chosen part", len(M) == 2 and M[0].startswith("PEMENU add=1 props=0 dup=0 del=0") and M[1].startswith("PEMENU add=1 props=1 dup=1 del=1"), M)
A = [l for l in o if l.startswith("PE add ")]
check("add: the first is accepted, a taken name, an empty name, an abstract class and no class are refused", len(A) == 5 and A[0].startswith("PE add ok") and "already has a part" in A[1]
      and "needs a name" in A[2] and "abstract" in A[3] and "abstract" in A[4], A)
c = db(f)
r = c.execute("select p.Name,pc.Name,p.RefPrefix,p.Description,p.Status,p.Revision,p.Modified,p.UID from Part p join PartClass pc using(ClassID) where p.Name='Test relay'").fetchall()
check("add: the row has the class, prefix, description, status active, revision 1, a stamp and a GUID", len(r) == 1 and r[0][1:6] == ("Relay", "KR", "A test relay", "active", "1") and r[0][6] and uuid.UUID(r[0][7]), r)
check("add: only that part was added", c.execute("select count(*) from Part").fetchone()[0] == len(seed_parts) + 1)
pr = [l for l in o if l.startswith("PDBROW")]
check("the Parts tab of the library panel lists the new part (read again)", len(pr) == len(seed_parts) + 1 and any("Test relay" in l for l in pr), pr)
tid = r[0][7]; c.close()
# properties
o = run(["peopen " + f, "pe rows"]); R = rows(o); names = [x[1] for x in R]; idx = names.index("Test relay"); before_row = R[idx]
o = run(["peopen " + f, "pe prop %d|Renamed relay|KX|new text|obsolete" % idx, "pe prop %d|Renamed relay|KX|new text|bogus" % idx, "pe prop %d||KX|t|active" % idx])
P = pe(o, "prop")
check("properties: accepted; a bad status and an empty name refused", len(P) == 3 and P[0] == "PE prop ok" and "status" in P[1] and "needs a name" in P[2], P)
c = db(f)
r = c.execute("select Name,RefPrefix,Description,Status,Revision,Modified from Part where UID=?", (tid,)).fetchone()
check("properties: new values, revision 2, a stamp, and the refused changes left nothing", r and r[:5] == ("Renamed relay", "KX", "new text", "obsolete", "2") and r[5], r)
li = c.execute("select Modified, Created from LibraryInfo").fetchone()
check("the library's Modified stamp is set", li[0] is not None and li[0] >= li[1], li)
# a part of the sample that has no revision counts as revision 1
o = run(["peopen " + f, "pe rows"]); R = rows(o); ia = [x[1] for x in R].index("Analog input module, 4 channels, current")
o = run(["peopen " + f, "pe prop %d|Analog input module, 4 channels, current|U|4-channel 4-20 mA analog input, 16 bit|active" % ia])
check("properties: a part without a revision goes to 2", c.execute("select Revision from Part where Name like 'Analog input%'").fetchone() == ("2",), c.execute("select Revision from Part where Name like 'Analog input%'").fetchone())
c.close()
# name collision inside the class
o = run(["peopen " + f, "pe add Second relay|Relay|KS|x"]); o = run(["peopen " + f, "pe rows"]); R = rows(o); i2 = [x[1] for x in R].index("Second relay")
o = run(["peopen " + f, "pe prop %d|Renamed relay|KS|x|active" % i2])
check("properties: a name the class has already is refused and nothing changes", any("already has a part" in l for l in pe(o, "prop")), o[-4:])
c = db(f); check("... the part keeps its name and revision", c.execute("select Name,Revision from Part where RefPrefix='KS'").fetchone() == ("Second relay", "1")); c.close()
# duplicate
o = run(["peopen " + f, "pe rows"]); R = rows(o); ic = [x[1] for x in R].index(next(x[1] for x in R if x[1].startswith("Contactor")))
o = run(["peopen " + f, "pe dup %d|Contactor copy" % ic, "pe dup %d|Contactor copy" % ic, "pe dup %d|" % ic])
D = pe(o, "dup")
check("duplicate: made; the same name again and an empty name are refused", len(D) == 3 and D[0].startswith("PE dup ok") and "already has a part" in D[1] and "needs a name" in D[2], D)
c = db(f)
new = c.execute("select PartID,UID,ClassID,RefPrefix,Description,Status,Revision,BaseDefault from Part where Name='Contactor copy'").fetchone()
old = c.execute("select PartID,UID,ClassID,RefPrefix,Description,Status,Revision,BaseDefault from Part where PartID=?", (cont,)).fetchone()
check("duplicate: same class, prefix, description, status; new GUID; revision 1", new and new[0] != cont and new[1] != old[1] and new[2:6] == old[2:6] and new[6] == "1", (new, old))
check("duplicate: every table of the part has the same number of rows for the copy", counts(c, new[0]) == before, (counts(c, new[0]), before))
check("duplicate: the original is untouched", counts(c, cont) == before)
def tree(pid):
    return sorted(c.execute("select o.Name, p.Name, k.Name, o.Designator from PartObject o left join PartObject p on p.ObjectID=o.ParentObjectID join ObjectKind k on k.KindID=o.KindID where o.PartID=?", (pid,)).fetchall(), key=str)
check("duplicate: the object tree (name, parent, kind, designator) is the same", tree(new[0]) == tree(cont) and len(tree(cont)) > 5, (tree(new[0])[:4], tree(cont)[:4]))
check("duplicate: the objects have new numbers", not set(x[0] for x in c.execute("select ObjectID from PartObject where PartID=?", (new[0],))) & set(x[0] for x in c.execute("select ObjectID from PartObject where PartID=?", (cont,))))
def rat(pid): return sorted(c.execute("select ifnull(o.Name,''),r.Quantity,r.Max,r.Unit,ifnull(r.Condition,'') from Rating r left join PartObject o on o.ObjectID=r.ObjectID where r.PartID=?", (pid,)).fetchall())
check("duplicate: the requirements are on the same objects (by name) with the same values", rat(new[0]) == rat(cont) and len(rat(cont)) > 3, (rat(new[0])[:3], rat(cont)[:3]))
def links(pid): return sorted(c.execute("select a.Name,b.Name,l.Relation from Link l join PartObject a on a.ObjectID=l.FromObject join PartObject b on b.ObjectID=l.ToObject where l.PartID=?", (pid,)).fetchall())
check("duplicate: the links join the same objects", links(new[0]) == links(cont) and len(links(cont)) > 0, links(new[0]))
def pins(pid): return sorted(c.execute("select o.Name,sp.X,sp.Y from SymbolPin sp join Symbol s using(SymbolID) join PartObject o on o.ObjectID=sp.ObjectID where s.PartID=?", (pid,)).fetchall())
check("duplicate: the symbol pins are on the copied objects", pins(new[0]) == pins(cont) and len(pins(cont)) > 0, pins(new[0]))
bd = c.execute("select PartID from Symbol where SymbolID=?", (new[7],)).fetchone()
check("duplicate: the default symbol is the copy's own", bd and bd[0] == new[0] and new[7] != old[7], (new[7], old[7], bd))
check("duplicate: the symbol drawing and the icons are the same bytes", c.execute("select Drawing from Symbol where PartID=?", (new[0],)).fetchall() == c.execute("select Drawing from Symbol where PartID=?", (cont,)).fetchall()
      and c.execute("select Size,Png from PartGlyph where PartID=? order by Size", (new[0],)).fetchall() == c.execute("select Size,Png from PartGlyph where PartID=? order by Size", (cont,)).fetchall())
check("duplicate: integrity and foreign keys clean", c.execute("pragma integrity_check").fetchone()[0] == "ok" and c.execute("pragma foreign_key_check").fetchall() == [])
nprod = c.execute("select count(*) from Product").fetchone()[0]; nparts = c.execute("select count(*) from Part").fetchone()[0]; c.close()
# delete
o = run(["peopen " + f, "pe rows"]); R = rows(o); ic = [x[1] for x in R].index("Contactor copy"); io = [x[1] for x in R].index(next(x[1] for x in R if x[1].startswith("Contactor") and x[1] != "Contactor copy"))
o = run(["peopen " + f, "pe del %d" % ic, "pe rows"])
Dl = [l for l in o if l.startswith("PE ")]
check("delete: the suggestions of the part are reported and the delete is accepted", any("suggestions=1" in l for l in Dl) and any(l.startswith("PE del ok") for l in Dl), Dl)
c = db(f)
check("delete: nothing of the deleted copy is left in any table", all(v == 0 for v in counts(c, new[0]).values()) and c.execute("select count(*) from Part where PartID=?", (new[0],)).fetchone()[0] == 0, counts(c, new[0]))
check("delete: the original contactor is untouched, and the products stay", counts(c, cont) == before and c.execute("select count(*) from Product").fetchone()[0] == nprod)
check("delete: foreign keys and integrity clean", c.execute("pragma foreign_key_check").fetchall() == [] and c.execute("pragma integrity_check").fetchone()[0] == "ok")
c.close()
# deleting the original (with products' ratings, suggestions, symbol, default symbol)
o = run(["peopen " + f, "pe rows"]); R = rows(o); io = [x[1] for x in R].index(next(x[1] for x in R if x[1].startswith("Contactor 3P")))
o = run(["peopen " + f, "pe del %d" % io])
c = db(f)
check("delete: the outline and model terminals that pointed into it and the other part's rule that named it are gone, the product's outline and model stay",
      c.execute("select count(*) from OutlineTerminal").fetchone()[0] == 0 and c.execute("select count(*) from ModelTerminal").fetchone()[0] == 0
      and c.execute("select count(*) from PartRule").fetchone()[0] == 0 and c.execute("select count(*) from Outline2D").fetchone()[0] == 1 and c.execute("select count(*) from Model3D").fetchone()[0] == 1)
check("delete: the original contactor goes entirely; its suggestion links too; the products stay; the other part is untouched",
      all(v == 0 for v in counts(c, cont).values()) and c.execute("select count(*) from Product").fetchone()[0] == nprod and c.execute("select count(*) from PartProduct").fetchone()[0] == 1
      and c.execute("pragma foreign_key_check").fetchall() == [], (counts(c, cont), c.execute("select count(*) from PartProduct").fetchone()))
c.close()
# library details
o = run(["peopen " + f, "pe info Mine|About it|Someone", "pe info |x|y", "pe rows"])
c = db(f)
check("library details: written; an empty name is refused", any(l == "PE info ok" for l in o) and any("PE info error" in l and "needs a name" in l for l in o)
      and c.execute("select Name,Description,Author from LibraryInfo").fetchone() == ("Mine", "About it", "Someone"), (o[-4:], c.execute("select * from LibraryInfo").fetchall()))
c.close()
# dialog
g = mk("g.TCParts"); c = db(g)
nonabs = c.execute("select count(*) from PartClass where Abstract=0").fetchone()[0]
o = run(["peopen " + g, "pe dlg add", "pe dlg prop 0"])
dl = [l for l in o if l.startswith("PEDLG ")]
check("dialog: the classes that can hold parts are listed (the abstract ones are not); a new part starts empty, active, class box enabled",
      len(dl) == 2 and ("classes=%d " % nonabs) in dl[0] and "classenabled=1" in dl[0] and "status=active" in dl[0] and "valid=0" in dl[0] and "caption=Add Part" in dl[0], dl)
check("dialog: changing a part shows its entries and the class cannot be changed", "classenabled=0" in dl[1] and "valid=1" in dl[1] and "caption=Part Properties" in dl[1], dl)
cl = [l[len("PEDLGCLASS "):] for l in o if l.startswith("PEDLGCLASS ")][:nonabs]
check("dialog: classes show their path from the root, sorted", cl == sorted(cl) and any(x.startswith("Part > ") for x in cl) and any(x.endswith("Contactor") and "SwitchingDevice" in x for x in cl), cl[:6])
# a new library works from nothing
n2 = os.path.join(tmp, "n.TCParts")
o = run(["pdbtab new " + n2, "peopen " + n2, "pe add First|Relay|K|from nothing", "pe dup 0|First 2", "pe rows"])
R = rows(o)
check("a library made by New Parts Library can be edited: add and duplicate work from the empty library", [x[1] for x in R] == ["First", "First 2"], (R, o[-5:]))
# lfm
lfm = open(os.path.join(ROOT, "src", "forms", "mainform.lfm"), encoding="utf-8").read()
m = re.search(r"object mParts: TMenuItem.*?\n    end\n", lfm, re.S); txt = m.group(0) if m else ""
want = [("mPartsNew", "DoNewPartsLibrary"), ("mPartsOpen", "DoOpenPartsLibrary"), ("mPartsEdit", "DoEditPartsLibrary"), ("mPartsAdd", "DoPartAdd"), ("mPartsProps", "DoPartProperties"), ("mPartsDup", "DoPartDuplicate"), ("mPartsDel", "DoPartDelete")]
pos = [txt.find("object " + n + ":") for n, _ in want]
check("mainform.lfm: the Parts menu items in order, each wired", all(p >= 0 for p in pos) and pos == sorted(pos) and all(("OnClick = " + h) in txt for _, h in want) and "OnClick = PartsMenuOpen" in txt, (pos, txt[:200]))
print("Parts editor checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
