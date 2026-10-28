#!/usr/bin/env python3
"""Parts library editor, class tree (Phase B3): add / change / move / delete part classes and declare / change / delete their fields, on the real program under Xvfb
(script commands 'pe page', 'pe cls ...', 'pe fld ...' = the editor's calls without their dialogs).
Oracles (independent of the program): the file is read with Python's sqlite3; the fields a class has are worked out here from the raw PartClass / FieldDef rows
(walk up ParentID, root first) and compared with what the program lists; every refused change is shown to leave PartClass and FieldDef byte-for-byte as they were;
integrity and foreign key checks after every session.
  - the page: the editor opens on Parts; the Classes page lists the tree (depth first, sorted) as the file has it; the menu items follow page and choice
  - add class: row (parent, abstract, description); a taken name, an empty name refused; a root class; a new class inherits its parent's fields
  - change class: rename, move under another parent (inherited fields change with it), abstract flag; refused: itself or its own subclass as parent, abstract while it
    has parts, a move that makes two fields of one line share a name (nothing changes then)
  - delete class: refused with subclasses, with parts, with products, as the target of a rule; allowed otherwise and its fields go with it
  - fields: add (type, unit, enum list, required, description), inherited by subclasses (listed as not own); refused: a name used on the class line (above or below),
    a bad type, an enum without values; change: new name / type / unit; type change and delete refused while a part has a value (nothing changes)
  - the dialogs: the Class dialog lists "(none)" and the classes that can be the parent (not itself or its subclasses), the Field dialog's enum box follows the type
Needs the built program and xvfb."""
import os, re, shutil, sqlite3, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Parts class checks skipped: need xvfb-run and the built program"); sys.exit(0)
sys.path.insert(0, os.path.join(ROOT, "docs")); import parts_seed
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:900])
def run(lines):
    h = tempfile.mkdtemp(dir=tmp); f = os.path.join(tmp, "s.txt"); open(f, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
def mk(name):
    p = os.path.join(tmp, name); parts_seed.build(p).close(); return p
def db(p):
    c = sqlite3.connect(p); c.execute("pragma foreign_keys=ON"); return c
def snap(p):
    c = db(p); r = (c.execute("select * from PartClass order by 1").fetchall(), c.execute("select * from FieldDef order by 1").fetchall()); c.close(); return r
def sound(p):
    c = db(p); ok = c.execute("pragma integrity_check").fetchone()[0] == "ok" and c.execute("pragma foreign_key_check").fetchall() == []; c.close(); return ok
def pe(o, g, sub): return [l for l in o if l.startswith("PE %s %s " % (g, sub))]
def cls_rows(o): return [l[len("PECLS "):].split("|") for l in o if l.startswith("PECLS ")]
def fld_rows(o): return [l[len("PEFLD "):].split("|") for l in o if l.startswith("PEFLD ")]
def want_fields(c, name):
    """independent: the fields of a class by walking ParentID, root first, then the declaration order"""
    cid = c.execute("select ClassID from PartClass where Name=?", (name,)).fetchone()[0]; chain = []
    while cid:
        chain.append(cid); cid = c.execute("select ParentID from PartClass where ClassID=?", (cid,)).fetchone()[0]
    out = []
    for k in reversed(chain):
        for r in c.execute("select f.Name,f.Type,coalesce(f.Unit,''),f.Required,pc.Name,coalesce(f.EnumValues,''),coalesce(f.Description,'') from FieldDef f join PartClass pc using(ClassID) where f.ClassID=? order by f.FieldID", (k,)):
            out.append([r[0], r[1], r[2], str(r[3]), r[4], "1" if k == chain[0] else "0", r[5], r[6]])
    return out
def want_tree(c):
    out = []
    def walk(pid, d):
        q = "select ClassID,Name,Abstract,coalesce(Description,'') from PartClass where ParentID is %s order by Name" % ("NULL" if pid is None else pid)
        for cid, n, a, ds in c.execute(q).fetchall():
            par = "" if pid is None else c.execute("select Name from PartClass where ClassID=?", (pid,)).fetchone()[0]
            out.append([str(d), n, par, str(a), ds]); walk(cid, d + 1)
    walk(None, 0); return out
f = mk("a.TCParts")
c0 = db(f)
# something that points at a class from a rule (blocks its deletion) and a field that has values
c0.execute("insert into PartClass(ParentID,Name,Abstract) values (NULL,'RuleTarget',0)")
c0.execute("insert into PartRule(PartID,Kind,TargetClassID,Note) values ((select PartID from Part limit 1),'recommends',(select ClassID from PartClass where Name='RuleTarget'),'x')")
valued = c0.execute("select distinct f.Name,pc.Name,f.Type from PartValue v join FieldDef f using(FieldID) join PartClass pc on pc.ClassID=f.ClassID order by f.FieldID").fetchall()
c0.commit(); c0.close()
vf, vcls, vtype = valued[0]
# ---- the page and the tree
o = run(["peopen " + f, "pe menu", "pe page classes", "pe cls rows", "pe menu", "pe cls select|Contactor", "pe menu", "pe fld rows|Contactor", "pe page parts", "pe menu"])
check("the editor opens on the Parts page", any(l == "PE page ok classes" for l in o) and any(l.startswith("PEMENU add=1 props=0 dup=0 del=0 cadd=0 cprops=0 cdel=0 fadd=0 fprops=0 fdel=0") for l in o), [l for l in o if l.startswith("PEMENU")])
c = db(f)
check("the Classes page lists the tree as the file has it (depth first, sorted by name)", cls_rows(o) == want_tree(c), (cls_rows(o)[:4], want_tree(c)[:4]))
M = [l for l in o if l.startswith("PEMENU")]
check("menu: part items only on Parts, class items only on Classes, field properties only for an own field", len(M) == 4 and M[1].startswith("PEMENU add=0 props=0 dup=0 del=0 cadd=1 cprops=1 cdel=1 fadd=1 fprops=0 fdel=0")
      and M[2].startswith("PEMENU add=0") and "cadd=1 cprops=1 cdel=1 fadd=1" in M[2] and M[3].startswith("PEMENU add=1") and "cadd=0 cprops=0 cdel=0 fadd=0 fprops=0 fdel=0" in M[3], M)
check("fields of Contactor: inherited ones first (root down), then its own; equal to the walk of the raw rows", fld_rows(o) == want_fields(c, "Contactor") and len(fld_rows(o)) >= 15, fld_rows(o)[:3])
own = [r for r in fld_rows(o) if r[5] == "1"]
check("only Category is the Contactor's own field", [r[0] for r in own] == ["Category"], own)
c.close()
# ---- add / change classes
before = snap(f)
o = run(["peopen " + f, "pe page classes",
         "pe cls add|Motor|PassivePart|0|a motor", "pe cls add|Relay|PassivePart|0|dup", "pe cls add||PassivePart|0|none", "pe cls add|Rootless||1|a new root",
         "pe cls add|Probe|Sensor|0|", "pe fld rows|Probe"])
A = pe(o, "cls", "add")
check("add class: accepted; a taken name and an empty name refused; a root and a subclass accepted", len(A) == 5 and A[0].startswith("PE cls add ok") and A[1].startswith("PE cls add error") and "exists" in A[1]
      and A[2].startswith("PE cls add error") and "name" in A[2] and A[3].startswith("PE cls add ok") and A[4].startswith("PE cls add ok"), A)
c = db(f)
r = c.execute("select Name,ParentID,Abstract,Description from PartClass where Name in ('Motor','Rootless','Probe') order by Name").fetchall()
pp = c.execute("select ClassID from PartClass where Name='PassivePart'").fetchone()[0]; sn = c.execute("select ClassID from PartClass where Name='Sensor'").fetchone()[0]
check("add class: the rows have parent, abstract flag and description; a root has no parent", r == [("Motor", pp, 0, "a motor"), ("Probe", sn, 0, ""), ("Rootless", None, 1, "a new root")], r)
check("add class: only three classes were added and nothing else changed", c.execute("select count(*) from PartClass").fetchone()[0] == len(before[0]) + 3 and c.execute("select count(*) from FieldDef").fetchone()[0] == len(before[1]))
check("a new subclass inherits the fields of its line", fld_rows(o) == want_fields(c, "Probe") and [r[0] for r in fld_rows(o)][-2:] == ["SensingPrinciple", "Range"], fld_rows(o)[-3:])
check("a new subclass lists the parent's fields as not own", all(r[5] == "0" for r in fld_rows(o)) and len(fld_rows(o)) == len(want_fields(c, "Sensor")), len(fld_rows(o)))
check("file sound", sound(f)); c.close()
# change: rename, move, abstract; refusals leave the file untouched
snap1 = snap(f)
o = run(["peopen " + f, "pe page classes",
         "pe cls prop|Motor|Machine|ActivePart|0|moved", "pe cls rows", "pe fld rows|Machine"])
P = pe(o, "cls", "prop"); c = db(f)
check("change class: rename and move accepted", P == ["PE cls prop ok "], P)
mrow = c.execute("select Name,ParentID,Description from PartClass where Name='Machine'").fetchone()
check("change class: the row has the new name, parent and description", mrow == ("Machine", c.execute("select ClassID from PartClass where Name='ActivePart'").fetchone()[0], "moved"), mrow)
check("change class: moving it changed what it inherits (now ActivePart's line, not PassivePart's)", fld_rows(o) == want_fields(c, "Machine") and "PowerW" in [r[0] for r in fld_rows(o)] and "Poles" not in [r[0] for r in fld_rows(o)], fld_rows(o)[:14])
check("change class: the tree equals the file's", cls_rows(o) == want_tree(c))
c.close()
snap2 = snap(f)
o = run(["peopen " + f, "pe page classes",
         "pe cls prop|Machine|Machine|Machine|0|self", "pe cls prop|ActivePart|ActivePart|Machine|1|below itself", "pe cls prop|Contactor|Contactor|SwitchingDevice|1|has parts",
         "pe cls prop|Machine||ActivePart|0|", "pe cls prop|Machine|Relay|ActivePart|0|taken"])
P = pe(o, "cls", "prop")
check("change class: itself or its own subclass as parent, abstract while it has parts, an empty name, a taken name - all refused", len(P) == 5 and all(p.startswith("PE cls prop error") for p in P), P)
check("the refused changes left the file exactly as it was", snap(f) == snap2)
# a move that makes two fields of one line share a name is refused and rolled back
c = db(f)
c.execute("insert into PartClass(ParentID,Name,Abstract) values (NULL,'Gizmo',0)"); g = c.execute("select ClassID from PartClass where Name='Gizmo'").fetchone()[0]
c.execute("insert into FieldDef(ClassID,Name,Type) values (?, 'Poles', 'int')", (g,)); c.commit(); c.close()
s3 = snap(f)
o = run(["peopen " + f, "pe page classes", "pe cls prop|Gizmo|Gizmo|PassivePart|0|", "pe cls prop|Gizmo|Gizmo|ActivePart|0|ok"])
P = pe(o, "cls", "prop")
check("change class: a move that makes its field name clash with an inherited one (Poles) is refused, a harmless move is allowed", len(P) == 2 and P[0].startswith("PE cls prop error") and P[1] == "PE cls prop ok ", P)
c = db(f); check("the refused move left Gizmo a root and the later one put it under ActivePart", c.execute("select ParentID from PartClass where Name='Gizmo'").fetchone()[0] == c.execute("select ClassID from PartClass where Name='ActivePart'").fetchone()[0])
c.close()
# ---- delete classes
snap4 = snap(f)
o = run(["peopen " + f, "pe page classes", "pe cls del|SwitchingDevice", "pe cls del|Contactor", "pe cls del|AnalogInputModule", "pe cls del|RuleTarget", "pe cls del|Machine", "pe cls del|Gizmo"])
D = pe(o, "cls", "del")
check("delete class: refused with subclasses, with parts, with a part and product, as the target of a rule; the empty ones are deleted", len(D) == 6 and all(d.startswith("PE cls del error") for d in D[:4]) and D[4].startswith("PE cls del ok") and D[5].startswith("PE cls del ok"), D)
check("delete class: each refusal names its reason (subclasses, parts, a part rule)", "subclasses" in D[0] and "parts" in D[1] and "rule" in D[3], D)
c = db(f)
check("deleted classes and their fields are gone, the others kept", c.execute("select count(*) from PartClass where Name in ('Machine','Gizmo')").fetchone()[0] == 0 and c.execute("select count(*) from FieldDef where ClassID=?", (g,)).fetchone()[0] == 0
      and c.execute("select count(*) from PartClass").fetchone()[0] == len(snap4[0]) - 2, c.execute("select count(*) from PartClass").fetchone())
c.close(); check("file sound after deletes", sound(f))
# ---- fields
f2 = mk("b.TCParts")
o = run(["peopen " + f2, "pe page classes",
         "pe fld add|Sensor|Gain|real|dB||1|amplifier gain", "pe fld add|Sensor|Mode|enum||fast,slow|0|how", "pe fld add|Sensor|Bad|enum|||0|no list", "pe fld add|Sensor|Bad2|blob|||0|",
         "pe fld add|Sensor|WidthMm|real|||0|inherited name", "pe fld add|Sensor|Gain|real|||0|twice", "pe fld add|Sensor||real|||0|empty",
         "pe cls add|Probe|Sensor|0|", "pe fld add|Probe|Gain|real|||0|below", "pe fld add|Probe|Own|text|||0|",
         "pe cls add|Meter|PassivePart|0|", "pe fld add|Meter|Own|text|||0|other line",
         "pe fld rows|Sensor", "pe fld rows|Probe"])
F = pe(o, "fld", "add")
check("add field: Gain and Mode accepted; an enum without values, a bad type, an inherited name, a repeated name and an empty name refused", len(F) == 10 and F[0].endswith("ok ") and F[1].endswith("ok ")
      and all(x.startswith("PE fld add error") for x in F[2:7]), F)
check("add field: the refusals name their reason (the values, the type, a name that exists)", "values" in F[2] and "type" in F[3] and all("exists" in x for x in (F[4], F[5], F[7])) and "needs a name" in F[6], F)
check("add field: a name already used on a subclass line is refused, a free one is accepted; the same name on another line is fine",
      F[7].startswith("PE fld add error") and F[8].endswith("ok ") and F[9].endswith("ok "), F[7:])
c = db(f2)
fr = c.execute("select f.Name,f.Type,f.Unit,f.EnumValues,f.Required,f.Description from FieldDef f where ClassID=(select ClassID from PartClass where Name='Sensor') and f.Name in ('Gain','Mode') order by FieldID").fetchall()
check("add field: the rows hold type, unit, enum list, required flag and description", fr == [("Gain", "real", "dB", None, 1, "amplifier gain"), ("Mode", "enum", None, "fast,slow", 0, "how")] or
      fr == [("Gain", "real", "dB", "", 1, "amplifier gain"), ("Mode", "enum", "", "fast,slow", 0, "how")], fr)
rows_ = fld_rows(o)
check("fields listed for Sensor equal the walk of the raw rows", [r for r in rows_ if r[4] == "Sensor" or r[5] == "1"][:0] == [] and want_fields(c, "Sensor") == rows_[:len(want_fields(c, "Sensor"))], (rows_[-3:], want_fields(c, "Sensor")[-3:]))
check("fields of the subclass: its parent's fields are listed as not own, its own as own", [r[0] for r in rows_ if r[5] == "1"][-1:] == ["Own"] and fld_rows(o)[-1][0] == "Own", rows_[-2:])
check("file sound after field adds", sound(f2)); c.close()
# change / delete fields
c = db(f2); vfid = c.execute("select f.FieldID from FieldDef f join PartClass pc using(ClassID) where f.Name=? and pc.Name=?", (vf, vcls)).fetchone()[0]
nvals = c.execute("select count(*) from PartValue where FieldID=?", (vfid,)).fetchone()[0]; c.close()
s5 = snap(f2)
o = run(["peopen " + f2, "pe page classes",
         "pe fld prop|%s|%s|%s|%s|text|||0|retyped" % (vcls, vf, vf, "text" if vtype != "text" else "real"),
         "pe fld del|%s|%s" % (vcls, vf), "pe fld del|%s|WidthMm" % "Sensor",
         "pe fld prop|Sensor|Gain|Gain2|real|dB||1|renamed", "pe fld prop|Sensor|Gain2|Gain2|text|||1|retyped, no values", "pe fld prop|Sensor|Gain2|WidthMm|text|||1|clash",
         "pe fld del|Probe|Own", "pe fld rows|Probe"])
P = pe(o, "fld", "prop"); D = pe(o, "fld", "del")
check("field with values (%d): its type cannot change and it cannot be deleted; an inherited field is not an own field" % nvals, nvals > 0 and P[0].startswith("PE fld prop error") and D[0].startswith("PE fld del error") and "no such own" in D[1], (P, D))
check("field with values: the refusals say how many parts have a value", "have a value" in D[0] and "value" in P[0], (P[0], D[0]))
check("field without values: rename and retype accepted; a name clash refused", len(P) == 4 and P[1].endswith("ok ") and P[2].endswith("ok ") and P[3].startswith("PE fld prop error"), P)
check("field delete accepted for an unused own field", D[2].endswith("ok "), D)
c = db(f2)
check("the changed field rows", c.execute("select Name,Type,Description from FieldDef where Name='Gain2'").fetchall() == [("Gain2", "text", "retyped, no values")] and c.execute("select count(*) from FieldDef where Name='Gain'").fetchone()[0] == 0)
check("the value rows of the protected field were not touched", c.execute("select count(*) from PartValue where FieldID=?", (vfid,)).fetchone()[0] == nvals and c.execute("select Type from FieldDef where FieldID=?", (vfid,)).fetchone()[0] == vtype)
check("deleted field is gone from the subclass list", "Own" not in [r[0] for r in fld_rows(o)], fld_rows(o)[-2:])
c.close(); check("file sound after field changes", sound(f2))
# ---- dialogs
o = run(["peopen " + f2, "pe cls dlg||Sensor", "pe cls dlg|ActivePart|", "pe cls dlg|Sensor|"])
dl = [l for l in o if l.startswith("PEDLG ")]; allp = [l[len("PEDLGPARENT "):] for l in o if l.startswith("PEDLGPARENT ")]
c = db(f2); ncl = c.execute("select count(*) from PartClass").fetchone()[0]
ac = [x for x in c.execute("select Name from PartClass").fetchall()]
check("Class dialog: a new class starts empty under the class given; the entries of a class are shown with its parent", len(dl) == 3 and "caption=Add Class" in dl[0] and "valid=0" in dl[0] and "parent=Part > ActivePart > Sensor" in dl[0] and "name=ActivePart" in dl[1] and "caption=Class Properties" in dl[1] and "parent=Part" in dl[1], dl)
n0 = allp.index("(none - a root class)") if "(none - a root class)" in allp else -1
first = allp[:ncl + 1]
second = allp[ncl + 1: ncl + 1 + 1 + ncl - 5]
check("Class dialog: a new class may go under every class, changing one leaves out itself and its subclasses (ActivePart has %d)" % 5, n0 == 0 and len(first) == ncl + 1, (len(allp), ncl))
sub = c.execute("with recursive d(i) as (select ClassID from PartClass where Name='ActivePart' union select p.ClassID from PartClass p join d on p.ParentID=d.i) select count(*) from d").fetchone()[0]
lst2 = allp[ncl + 1: ncl + 1 + (ncl - sub) + 1]
check("Class dialog: for ActivePart the list holds (none) and the other %d classes, none below ActivePart" % (ncl - sub), len(lst2) == ncl - sub + 1 and not any("ActivePart" in x for x in lst2[1:]), lst2[:4])
c.close()
src = open(os.path.join(ROOT, "src", "frames", "QPartsEditor.lfm"), encoding="utf-8").read()
check("QPartsEditor.lfm: the Classes page with the tree, the fields list and the buttons, wired", all(x in src for x in ["object tsClasses: TTabSheet", "object tvClasses: TTreeView", "object lvFields: TListView", "OnClick = ClassAddClick", "OnClick = FieldDeleteClick", "object pmClasses: TPopupMenu", "object pmFields: TPopupMenu"]))
lfm = open(os.path.join(ROOT, "src", "forms", "mainform.lfm"), encoding="utf-8").read()
m = re.search(r"object mParts: TMenuItem.*?\n    end\n", lfm, re.S); txt = m.group(0) if m else ""
want = [("mPartsDel", "DoPartDelete"), ("mPartsSep2", None), ("mPartsClassAdd", "DoClassAdd"), ("mPartsClassProps", "DoClassProperties"), ("mPartsClassDel", "DoClassDelete"), ("mPartsSep3", None),
        ("mPartsFieldAdd", "DoFieldAdd"), ("mPartsFieldProps", "DoFieldProperties"), ("mPartsFieldDel", "DoFieldDelete")]
pos = [txt.find("object " + n + ":") for n, _ in want]
check("mainform.lfm: the class and field items follow the part items, in order, each wired", all(p >= 0 for p in pos) and pos == sorted(pos) and all(("OnClick = " + h) in txt for _, h in want if h), pos)
print("Parts class checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
