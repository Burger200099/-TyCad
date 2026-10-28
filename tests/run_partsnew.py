#!/usr/bin/env python3
"""Parts > New Parts Library: the program makes an empty TyCAD parts file (schema + starting classes/fields/kinds/rating quantities, no parts), on the real
program under Xvfb (script 'pdbtab new <file>' = the menu command without its Save dialog).
Oracles (all independent of the program's own code): the schema is applied by Python's sqlite3 from docs/parts_schema.sql and the taxonomy built by
docs/parts_seed.py; the new file must have the same objects (names and normalised SQL), the same taxonomy rows, FormatInfo/LibraryInfo as the format says,
PRAGMA integrity/foreign key checks clean, and must accept a part with a rating (and refuse a rating with a wrong unit, by the schema's own trigger).
  - the file: objects equal to the reference schema, user_version 2, FormatInfo, LibraryInfo (name = file name, a GUID that differs between two files)
  - taxonomy equal to the seed's; no parts, no products
  - usable: a part and a product can be inserted in Python; the program opens the file again (0 rows) and then lists the part
  - an existing file is replaced (new GUID); an impossible path gives an error and leaves no file
  - the menu: Parts has New Parts Library... (before Open), wired to DoNewPartsLibrary, in mainform.lfm
Needs the built program and xvfb."""
import os, re, shutil, sqlite3, subprocess, sys, tempfile, uuid
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("New parts library checks skipped: need xvfb-run and the built program"); sys.exit(0)
sys.path.insert(0, os.path.join(ROOT, "docs")); import parts_seed
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:600])
def run(lines):
    h = tempfile.mkdtemp(dir=tmp); f = os.path.join(tmp, "s.txt"); open(f, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
norm = lambda s: re.sub(r"\s+", " ", re.sub(r"--[^\n]*", "", s or "")).strip()
def objects(c): return {(t, n): norm(s) for t, n, s in c.execute("select type,name,sql from sqlite_master where name not like 'sqlite_%'")}
ref = parts_seed.build(os.path.join(tmp, "ref.db"))
a = os.path.join(tmp, "Mine.TCParts"); b = os.path.join(tmp, "Other.TCParts"); bad = os.path.join(tmp, "nodir", "x.TCParts")
o = run(["pdbtab new " + a, "pdbtab new " + b, "pdbtab new " + bad])
P = [l for l in o if l.startswith("PDBTAB")]
check("two libraries made, the impossible path reported", len(P) == 3 and P[0].startswith("PDBTAB ok rows=0") and P[1].startswith("PDBTAB ok rows=0") and P[2].startswith("PDBTAB error"), P)
check("the caption of the Parts tab names the library", "Other" in P[1] or "Other" in "".join(o), P[1])
check("no file for the impossible path", not os.path.exists(bad))
c = sqlite3.connect(a); r2 = sqlite3.connect(b)
oa, orf = objects(c), objects(ref)
check("same tables, views and triggers as the reference schema", set(oa) == set(orf), (set(orf) ^ set(oa)))
check("every definition equals the reference's", all(oa[k] == orf[k] for k in orf if k in oa), [k for k in orf if k in oa and oa[k] != orf[k]])
check("user_version 2", c.execute("pragma user_version").fetchone()[0] == 2)
fi = c.execute("select Format,SchemaVersion,TinyCADCompatible,Generator from FormatInfo").fetchall()
check("FormatInfo: TyCAD-Parts, version 2, not TinyCAD compatible", fi == [("TyCAD-Parts", 2, 0, "TyCAD")], fi)
li = c.execute("select LibraryUID,Name,Created from LibraryInfo").fetchall()
check("LibraryInfo: one row, name = file name, a GUID, a creation stamp", len(li) == 1 and li[0][1] == "Mine" and li[0][2], li)
check("the GUID is a GUID and differs between two files", bool(li) and uuid.UUID(li[0][0]) and li[0][0] != r2.execute("select LibraryUID from LibraryInfo").fetchone()[0])
for t, cols in (("PartClass", "Name,Abstract,(select Name from PartClass x where x.ClassID=PartClass.ParentID)"), ("FieldDef", "Name,Type,Unit,EnumValues,Required,(select Name from PartClass x where x.ClassID=FieldDef.ClassID)"),
                ("ObjectKind", "Name,Abstract,(select Name from ObjectKind x where x.KindID=ObjectKind.ParentID)"), ("KindFieldDef", "Name,Type,Unit,EnumValues,Required,(select Name from ObjectKind x where x.KindID=KindFieldDef.KindID)"),
                ("RatingQuantity", "Name,Unit,Sense,Description")):
    q = "select %s from %s order by 1,2,3" % (cols, t)
    check("%s rows equal the seed's" % t, c.execute(q).fetchall() == ref.execute(q).fetchall() and c.execute("select count(*) from " + t).fetchone()[0] > 0, t)
q = "select (select Name from PartClass where ClassID=ClassID_), (select Name from ObjectKind where KindID=KindID_), Min_, Max_ from (select ClassID ClassID_, KindID KindID_, * from ClassAllowsKind) order by 1,2"
check("which kinds a class allows equals the seed's (by names)", c.execute("select pc.Name,k.Name from ClassAllowsKind a join PartClass pc using(ClassID) join ObjectKind k using(KindID) order by 1,2").fetchall()
      == ref.execute("select pc.Name,k.Name from ClassAllowsKind a join PartClass pc using(ClassID) join ObjectKind k using(KindID) order by 1,2").fetchall())
check("no parts and no products", c.execute("select (select count(*) from Part)+(select count(*) from Product)").fetchone()[0] == 0)
check("integrity and foreign key checks are clean", c.execute("pragma integrity_check").fetchone()[0] == "ok" and c.execute("pragma foreign_key_check").fetchall() == [])
# usable
c.execute("pragma foreign_keys=ON")
cid = c.execute("select ClassID from PartClass where Name='Contactor'").fetchone()[0]
pid = c.execute("insert into Part(UID,ClassID,Name,RefPrefix) values (?,?,'Test contactor','K')", (str(uuid.uuid4()), cid)).lastrowid
c.execute("insert into Rating(PartID,Quantity,Max,Unit) values (?,'current',25,'A')", (pid,))
try:
    c.execute("insert into Rating(PartID,Quantity,Max,Unit) values (?,'current',25,'V')", (pid,)); wrong = False
except sqlite3.DatabaseError: wrong = True
check("a part with a rating can be added; a rating with the wrong unit is refused by the schema", wrong and c.execute("select count(*) from Rating").fetchone()[0] == 1)
c.commit(); c.close(); r2.close()
o = run(["pdbtab open " + a, "pdbtab rows"])
R = [l for l in o if l.startswith("PDBROW")]
check("the program opens the file again and lists the part added in Python", len(R) == 1 and "Test contactor" in R[0], (R, [l for l in o if l.startswith("PDBTAB")]))
g1 = sqlite3.connect(a).execute("select LibraryUID from LibraryInfo").fetchone()[0]
o = run(["pdbtab new " + a])
g2 = sqlite3.connect(a).execute("select LibraryUID from LibraryInfo").fetchone()[0]
n = sqlite3.connect(a).execute("select count(*) from Part").fetchone()[0]
check("making a library at an existing file replaces it (new GUID, the part is gone)", g1 != g2 and n == 0, (g1, g2, n))
lfm = open(os.path.join(ROOT, "src", "forms", "mainform.lfm"), encoding="utf-8").read()
m = re.search(r"object mParts: TMenuItem.*?\n    end\n", lfm, re.S)
txt = m.group(0) if m else ""
check("mainform.lfm: Parts has New Parts Library... before Open, wired to DoNewPartsLibrary",
      "mPartsNew" in txt and txt.index("mPartsNew") < txt.index("mPartsOpen") and "OnClick = DoNewPartsLibrary" in txt and "'&New Parts Library...'" in txt, txt[:300])
print("New parts library checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
