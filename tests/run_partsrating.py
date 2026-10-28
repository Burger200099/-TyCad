#!/usr/bin/env python3
"""Parts library editor, requirements (Phase B4): the Requirements page lists the ratings a generic part must have and adds, changes and deletes them, on the real program
under Xvfb (script commands `pe page requirements`, `pe rat ...` = the editor's calls without their dialogs).
Oracles (independent of the program): the file is read with Python's sqlite3 -- the rows of Rating, the part's Revision and Modified, ProductFitSummary -- and compared with
expectations written here from the sample library built by docs/parts_seed.py.
  - the page: the list equals the part's Rating rows (whole part first, then by object name and quantity); the numbers are shown without trailing zeros; the part box lists every part
  - add: the row (object, quantity, unit taken from the quantity, min/typ/max NULL where not given, condition NULL when empty); a comma as decimal mark; the part's Revision + 1 and
    Modified stamped; other parts' ratings untouched
  - refused (the file stays as it was, byte for byte in Rating and Part): a unit that is not the quantity's, no value, min > typ, typ > max, min > max, an unknown or empty quantity,
    an object that is not the part's, the same quantity + condition on the same object twice
  - change: new values / object / condition; a change that keeps its own key is allowed, one that meets another requirement is refused; delete: the row is gone
  - the verdict of the library's own view ProductFitSummary follows (no requirements = no_requirements)
  - dialog: objects (whole part + the part's child objects), every quantity with its unit and how a product is judged, the entries of a requirement; the menu items follow the page
Needs the built program and xvfb."""
import os, re, shutil, sqlite3, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Requirement checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
def g(x): return None if x is None else ("%.12g" % x)
def snap(p):
    c = db(p); r = (c.execute("select * from Rating order by RatingID").fetchall(), c.execute("select PartID,Revision,Modified from Part order by PartID").fetchall()); c.close(); return r
def rat_rows(c, pid):
    q = ("select coalesce(o.Name,''),r.Quantity,r.Min,r.Typ,r.Max,r.Unit,coalesce(r.Condition,'') from Rating r left join PartObject o on o.ObjectID=r.ObjectID where r.PartID=? "
         "order by o.Name is not null, o.Name, r.Quantity")
    return [[(n if n else "(the whole part)"), qn, g(a) or "", g(b) or "", g(m) or "", u, cd] for n, qn, a, b, m, u, cd in c.execute(q, (pid,)).fetchall()]
def prow(o): return [l[len("PERAT "):].split("|") for l in o if l.startswith("PERAT ")]
def rat(o, sub): return [l for l in o if l.startswith("PE rat %s " % sub)]
CT = "Contactor 3P 25 A AC-3, 24 V DC coil"; AM = "Analog input module, 4 channels, current"
f = mk("a.TCParts"); c = db(f)
ct = c.execute("select PartID from Part where Name=?", (CT,)).fetchone()[0]; am = c.execute("select PartID from Part where Name=?", (AM,)).fetchone()[0]
nparts = c.execute("select count(*) from Part").fetchone()[0]; nobj = c.execute("select count(*) from PartObject where PartID=?", (ct,)).fetchone()[0]
want_ct = rat_rows(c, ct); want_am = rat_rows(c, am); nq = c.execute("select count(*) from RatingQuantity").fetchone()[0]
rev0 = c.execute("select Revision,Modified from Part where PartID=?", (ct,)).fetchone(); c.close()
o = run(["peopen " + f, "pe menu", "pe page requirements", "pe menu", "pe rat part|" + CT, "pe rat rows", "pe menu", "pe rat select|0", "pe menu", "pe rat part|" + AM, "pe rat rows"])
M = [re.sub(r" oadd=.*$", "", l) for l in o if l.startswith("PEMENU")]
check("menu: on the Requirements page Add needs a part, Properties and Delete need a chosen row; the part and class items are off", " radd=0 rprops=0 rdel=0" in M[0] and M[1].endswith("radd=1 rprops=0 rdel=0") and M[2].endswith("radd=1 rprops=0 rdel=0") and M[3].endswith("radd=1 rprops=1 rdel=1") and M[1].startswith("PEMENU add=0 props=0 dup=0 del=0 cadd=0"), M)
parts_a = [l for l in o if l.startswith("PERATINFO")]
rows_ct = prow(o[:o.index(parts_a[0]) + 1]); rows_am = prow(o[o.index(parts_a[0]) + 1:])
check("the Contactor's requirements equal its Rating rows (whole part first, then by object name and quantity)", rows_ct == want_ct and len(want_ct) == 6, (rows_ct, want_ct))
check("the analog module's requirements equal its rows", rows_am == want_am and len(want_am) == 4, (rows_am, want_am))
check("the part box lists every part", "rows=6" in parts_a[0] and ("rows=4" in parts_a[1]), parts_a)
# ---- add
s0 = snap(f)
cmds = ["peopen " + f, "pe page requirements", "pe rat part|" + CT,
        "pe rat add|Pole 1|current||0||25|AC-1 400 V",
        "pe rat add||voltage|V||400|690|",
        "pe rat add||power|W|1,5|2,5||thermal",
        "pe rat rows"]
o = run(cmds); A = rat(o, "add")
check("add: three requirements accepted (a unit left empty, the right unit, a comma as the decimal mark)", len(A) == 3 and all(a.startswith("PE rat add ok") for a in A), A)
c = db(f)
r1 = c.execute("select o.Name,r.Quantity,r.Min,r.Typ,r.Max,r.Unit,r.Condition from Rating r join PartObject o using(ObjectID) where r.PartID=? and r.Condition='AC-1 400 V'", (ct,)).fetchall()
check("add: the row has the object, quantity, the quantity's unit, min 0, no typ, max 25 and the condition", r1 == [("Pole 1", "current", 0.0, None, 25.0, "A", "AC-1 400 V")], r1)
r2 = c.execute("select ObjectID,Min,Typ,Max,Unit,Condition from Rating where PartID=? and Quantity='voltage'", (ct,)).fetchall()
check("add: a whole-part rating has no object; values not given are NULL; an empty condition is NULL", r2 == [(None, None, 400.0, 690.0, "V", None)], r2)
r3 = c.execute("select Min,Typ,Max,Condition from Rating where PartID=? and Quantity='power'", (ct,)).fetchall()
check("add: 1,5 and 2,5 are read as 1.5 and 2.5", r3 == [(1.5, 2.5, None, "thermal")], r3)
rev1 = c.execute("select Revision,Modified from Part where PartID=?", (ct,)).fetchone()
check("add: the part's revision went up by one for each change and Modified is stamped", rev1[0] == str(int(rev0[0] or 1) + 3) and rev1[1] >= (rev0[1] or ""), (rev0, rev1))
check("add: the other part's ratings are as they were", rat_rows(c, am) == want_am)
check("the list shows the rows as the file has them", prow(o) == rat_rows(c, ct) and len(prow(o)) == 9, (prow(o), rat_rows(c, ct)))
c.close()
# ---- refusals
s1 = snap(f)
refuse = [("a unit that is not the quantity's", "pe rat add||current|mA||||10|", "unit of current is A"),
          ("no value at all", "pe rat add||current|A||||AC-3|", "at least one"),
          ("min above typ", "pe rat add||voltage|V|10|5|20|x", "minimum is above the typical"),
          ("typ above max", "pe rat add||voltage|V|1|30|20|x", "typical value is above the maximum"),
          ("min above max", "pe rat add||voltage|V|30||20|x", "minimum is above the maximum"),
          ("an unknown quantity", "pe rat add||nonsense||||5|", "not a quantity"),
          ("no quantity", "pe rat add||||||5|", "Choose what is rated"),
          ("an object that is not the part's", "pe rat add|Nowhere|current|A|||5|", "not a part of this part"),
          ("the same quantity and condition on the same object", "pe rat add|A1/A2|coil_voltage|V|||24|", "already has a requirement"),
          ("the same on the whole part", "pe rat add||voltage|V|||5|", "already has a requirement")]
o = run(["peopen " + f, "pe page requirements", "pe rat part|" + CT] + [x[1] for x in refuse]); A = rat(o, "add")
check("refusals: every one is refused", len(A) == len(refuse) and all(a.startswith("PE rat add error") for a in A), A)
for (n, _, msg), a in zip(refuse, A):
    check("refused with the reason: " + n, msg in a, a)
check("the refusals left Rating and the parts' revisions exactly as they were", snap(f) == s1)
# ---- change
o = run(["peopen " + f, "pe page requirements", "pe rat part|" + CT, "pe rat rows"]); R = prow(o)
i_pole = [r[0] for r in R].index("Pole 1"); i_volt = [r[1] for r in R].index("voltage")
c = db(f); rev_b = c.execute("select Revision from Part where PartID=?", (ct,)).fetchone()[0]; c.close()
o = run(["peopen " + f, "pe page requirements", "pe rat part|" + CT,
         "pe rat prop|%d|Pole 1|current|A|0|20|30|AC-1 400 V" % i_pole,
         "pe rat prop|%d|Pole 1|current|A|0|20|30|AC-1 400 V" % i_pole,
         "pe rat prop|%d||voltage|V|||5|" % i_volt,
         "pe rat prop|%d|A1/A2|voltage|mA|||700|" % i_volt,
         "pe rat prop|%d||motor_power|kW|||5|AC-3 400 V" % i_volt, "pe rat rows"])
P = rat(o, "prop")
check("change: accepted twice (the second keeps its own key), accepted for another object", P[0] == "PE rat prop ok" and P[1] == "PE rat prop ok" and P[2] == "PE rat prop ok", P)
check("change: a wrong unit is refused; becoming another requirement's quantity and condition on the same object is refused", P[3].startswith("PE rat prop error") and "unit of voltage" in P[3] and P[4].startswith("PE rat prop error") and "already has" in P[4], P)
c = db(f)
check("change: the Pole 1 requirement has the new values", c.execute("select Min,Typ,Max from Rating r join PartObject o using(ObjectID) where r.PartID=? and o.Name='Pole 1' and r.Quantity='current' and r.Condition='AC-1 400 V'", (ct,)).fetchall() == [(0.0, 20.0, 30.0)])
check("change: the voltage requirement now has max 5 and no min or typ", c.execute("select Min,Typ,Max from Rating where PartID=? and Quantity='voltage'", (ct,)).fetchall() == [(None, None, 5.0)])
check("change: the revision went up by one for each accepted change", c.execute("select Revision from Part where PartID=?", (ct,)).fetchone()[0] == str(int(rev_b) + 3))
check("the list equals the file after the changes", prow(o) == rat_rows(c, ct), (prow(o), rat_rows(c, ct)))
c.close()
# ---- delete, and the verdict view follows
c = db(f); verdict0 = c.execute("select Verdict from ProductFitSummary where PartID=?", (ct,)).fetchall(); n_all = c.execute("select count(*) from Rating where PartID=?", (ct,)).fetchone()[0]; c.close()
check("setup: the contactor's products have verdicts other than no_requirements while it has requirements", verdict0 and all(v[0] != "no_requirements" for v in verdict0), verdict0)
c = db(f); rev_d = c.execute("select Revision from Part where PartID=?", (ct,)).fetchone()[0]; c.close()
o = run(["peopen " + f, "pe page requirements", "pe rat part|" + CT, "pe rat del|0", "pe rat rows"]); D = rat(o, "del")
c = db(f)
check("delete: the part's revision went up by one", c.execute("select Revision from Part where PartID=?", (ct,)).fetchone()[0] == str(int(rev_d) + 1))
check("delete: one requirement is gone, the others stay", D[0].startswith("PE rat del ok") and c.execute("select count(*) from Rating where PartID=?", (ct,)).fetchone()[0] == n_all - 1 and prow(o) == rat_rows(c, ct), (D, prow(o)))
o = run(["peopen " + f, "pe page requirements", "pe rat part|" + CT] + ["pe rat del|0"] * (n_all - 1) + ["pe rat rows"])
c.close(); c = db(f)
check("delete all: no rating of the part is left, the analog module's four stay", c.execute("select count(*) from Rating where PartID=?", (ct,)).fetchone()[0] == 0 and rat_rows(c, am) == want_am)
check("the library's own view now says no_requirements for every product of the contactor", {v[0] for v in c.execute("select Verdict from ProductFitSummary where PartID=?", (ct,))} == {"no_requirements"})
check("file sound", c.execute("pragma integrity_check").fetchone()[0] == "ok" and c.execute("pragma foreign_key_check").fetchall() == [])
c.close()
# ---- the dialog
g2 = mk("g.TCParts"); c = db(g2); nobj_ct = c.execute("select count(*) from PartObject where PartID=(select PartID from Part where Name=?)", (CT,)).fetchone()[0]; c.close()
o = run(["peopen " + g2, "pe page requirements", "pe rat part|" + CT, "pe rat dlg|-1", "pe rat rows", "pe rat dlg|0", "pe rat part|" + AM, "pe rat dlg|0"])
dl = [l for l in o if l.startswith("PEDLG ")]
check("dialog: a new requirement starts on the whole part with the first quantity; every quantity and object is listed", len(dl) == 3 and "caption=Add Requirement" in dl[0] and "quantities=%d" % nq in dl[0] and "objects=%d" % (nobj_ct + 1) in dl[0]
      and "object=(the whole part)" in dl[0] and "valid=1" in dl[0], dl)
check("dialog: changing one shows its entries, the quantity's unit and how a product is judged", "caption=Requirement Properties" in dl[1] and "unit=Unit: " in dl[1] and "valid=1" in dl[1], dl[1])
check("dialog: the unit and the sense of the quantity are shown", "unit=Unit: " in dl[0] and ("at least" in dl[0] or "at or below" in dl[0] or "exactly" in dl[0]), dl[0])
check("dialog: the analog module's first requirement is on channel CH1 for input_current with max 20", "object=CH1" in dl[2] and "quantity=input_current" in dl[2] and "max=20" in dl[2] and "unit=Unit: mA" in dl[2] and "condition=range" in dl[2], dl[2])
lfm = open(os.path.join(ROOT, "src", "frames", "QPartsEditor.lfm"), encoding="utf-8").read()
check("QPartsEditor.lfm: the Requirements page with the part box, the list, the buttons and the pop-up menu, wired", all(x in lfm for x in ["object tsRatings: TTabSheet", "object cbRatPart: TComboBox", "object lvRatings: TListView", "OnClick = RatAddClick", "OnClick = RatDeleteClick", "object pmRatings: TPopupMenu"]))
ml = open(os.path.join(ROOT, "src", "forms", "mainform.lfm"), encoding="utf-8").read()
m = re.search(r"object mParts: TMenuItem.*?\n    end\n", ml, re.S); txt = m.group(0) if m else ""
want = [("mPartsFieldDel", "DoFieldDelete"), ("mPartsSep4", None), ("mPartsRatAdd", "DoRatingAdd"), ("mPartsRatProps", "DoRatingProperties"), ("mPartsRatDel", "DoRatingDelete")]
pos = [txt.find("object " + n + ":") for n, _ in want]
check("mainform.lfm: the requirement items follow the field items, in order, each wired", all(p >= 0 for p in pos) and pos == sorted(pos) and all(("OnClick = " + h) in txt for _, h in want if h), pos)
print("Requirement checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
