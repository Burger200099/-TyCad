#!/usr/bin/env python3
"""Parts library editor, products (Phase B6): the Products page lists the catalog products with their fit for a chosen part, adds / changes / deletes them and their
ratings, and keeps the library author's suggestions (PartProduct), on the real program under Xvfb (script commands `pe page products`, `pe prod ...`).
Oracles (independent of the program): the file is read with Python's sqlite3 and compared with expectations written here from the sample library built by docs/parts_seed.py;
the FIT verdict is worked out here from the Rating rows (a re-implementation of the rule in Python, not the library's views ProductFit / ProductFitSummary).
  - the page: rows = Product rows sorted by manufacturer, model; fit column = the Python verdict ('fits', 'fits, oversized', 'does not fit: ...', 'no requirements', '(other class)');
    suggested column = PartProduct
  - add / change: the row, revision '1' then +1 per change, GUID, Modified; refused (file unchanged): no manufacturer, no model number, the pair taken (any case), a bad status, no / an abstract
    class, a class change while suggested; delete: the product, its ratings and suggestions go, others' ReplacedBy and Substitute mentions are cleared, other products stay
  - ratings: the row (applies to: whole product / object name / kind:X with the kind's spelling), unit from the quantity; refused: unit mismatch, no value, min > max, unknown kind, a duplicate;
    every change raises the product's revision; the fit column follows (compared with the Python verdict after each change)
  - suggestions: suggested / preferred (one preferred per part) / removed; another class refused
  - dialogs: the classes offered (not abstract), the choices for a rating (kinds, then object names of the class), the entries; menu items follow the page and the choice
Needs the built program and xvfb."""
import os, re, shutil, sqlite3, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Product checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
    c = db(p)
    r = tuple(c.execute("select * from %s order by 1,2" % t).fetchall() for t in ("Product", "Rating", "PartProduct", "Substitute", "Part"))
    c.close(); return r
def g(x): return "" if x is None else ("%.12g" % x)
def kind_chain(c, k):
    r = []
    while k is not None: r.append(k); k = c.execute("select ParentID from ObjectKind where KindID=?", (k,)).fetchone()[0]
    return r
def fit_py(c, prod, part):
    """verdict text of a product for a part, from the Rating rows"""
    pc = c.execute("select ClassID from Product where ProductID=?", (prod,)).fetchone()[0]
    if c.execute("select ClassID from Part where PartID=?", (part,)).fetchone()[0] != pc: return "(other class)"
    cnt = {"ok": 0, "oversized": 0, "undersized": 0, "missing": 0, "mismatch": 0}; n = 0
    for rid, oid, q, mn, ty, mx, cond in c.execute("select RatingID,ObjectID,Quantity,Min,Typ,Max,Condition from Rating where PartID=?", (part,)).fetchall():
        n += 1
        need = next(v for v in (mx, ty, mn, None) if v is not None) if any(v is not None for v in (mx, ty, mn)) else None
        sense = c.execute("select Sense from RatingQuantity where Name=?", (q,)).fetchone()[0]
        names = []
        if oid is not None:
            nm, kid = c.execute("select Name,KindID from PartObject where ObjectID=?", (oid,)).fetchone()
            names = [nm] + ["kind:" + c.execute("select Name from ObjectKind where KindID=?", (k,)).fetchone()[0] for k in kind_chain(c, kid)]
        have = None
        for cand in (names if oid is not None else [None]):
            rows = c.execute("select Min,Typ,Max from Rating where ProductID=? and Quantity=? and Condition is ? and AppliesTo is ?", (prod, q, cond, cand)).fetchall()
            if rows:
                mn2, ty2, mx2 = rows[0]; have = next((v for v in (mx2, ty2, mn2) if v is not None), None); break
        if have is None: cnt["missing"] += 1
        elif have == need: cnt["ok"] += 1
        elif sense == "match": cnt["mismatch"] += 1
        elif (sense == "min" and have > need) or (sense == "max" and have < need): cnt["oversized"] += 1
        else: cnt["undersized"] += 1
    if n == 0: return "no requirements"
    bad = [("%d %s" % (cnt[k], k)) for k in ("undersized", "missing", "mismatch") if cnt[k]]
    if bad: return "does not fit: " + ", ".join(bad)
    return "fits, oversized" if cnt["oversized"] else "fits"
def prod_rows(c, part):
    out = []
    for pid, mf, mpn, se, cl, st, rev, de in c.execute("select p.ProductID,p.Manufacturer,p.MPN,coalesce(p.Series,''),c.Name,p.Status,coalesce(p.Revision,''),coalesce(p.Description,'') from Product p join PartClass c using(ClassID) order by lower(p.Manufacturer),lower(p.MPN)").fetchall():
        sg = ""
        if part:
            r = c.execute("select Preferred from PartProduct where PartID=? and ProductID=?", (part, pid)).fetchone()
            sg = "" if r is None else ("preferred" if r[0] else "suggested")
        out.append([mf, mpn, se, cl, st, rev, fit_py(c, pid, part) if part else "", sg, de])
    return out
def rows(o): return [l[len("PEPROD "):].split("|") for l in o if l.startswith("PEPROD ")]
def rrows(o): return [l[len("PEPRODRAT "):].split("|") for l in o if l.startswith("PEPRODRAT ")]
def pe(o, sub, what): return [l for l in o if l.startswith("PE %s %s " % (sub, what))]
CT = "Contactor 3P 25 A AC-3, 24 V DC coil"; AM = "Analog input module, 4 channels, current"
f = mk("a.TCParts"); c = db(f)
ct = c.execute("select PartID from Part where Name=?", (CT,)).fetchone()[0]; am = c.execute("select PartID from Part where Name=?", (AM,)).fetchone()[0]
want_ct = prod_rows(c, ct); want_none = prod_rows(c, 0); want_am = prod_rows(c, am); c.close()
check("sample: the python verdicts are what the sample is built to show (and what ProductFitSummary says)", [r[6] for r in want_ct] == ["(other class)", "fits, oversized", "fits, oversized", "does not fit: 4 undersized", "does not fit: 1 mismatch"], want_ct)
o = run(["peopen " + f, "pe menu", "pe page products", "pe menu", "pe prod rows", "pe prod part|" + CT, "pe prod rows", "pe prod part|" + AM, "pe prod rows", "pe prod part|", "pe prod select|1", "pe menu", "pe prod part|" + CT, "pe prod select|1", "pe menu"])
M = [l for l in o if l.startswith("PEMENU")]
check("menu: product items are off outside the page; Add on the page; the rest need a product; Suggest needs a part of the product's class",
      len(M) == 4 and " padd=0 pprops=0 pdel=0 psug=0 ppref=0 pradd=0 prprops=0 prdel=0" in M[0] and " padd=1 pprops=0 pdel=0 psug=0" in M[1] and " padd=1 pprops=1 pdel=1 psug=0 ppref=0 pradd=1 prprops=0" in M[2] and
      " padd=1 pprops=1 pdel=1 psug=1 ppref=1 pradd=1 prprops=0" in M[3], M)
R = [l for l in o if l.startswith("PEPRODINFO")]
r1 = rows(o[o.index(R[0]) - 5:o.index(R[0])]); i1 = o.index(R[0]); i2 = o.index(R[1]); i3 = o.index(R[2])
check("no part: the list equals the products, no fit and no suggestions", rows(o[:i1]) == want_none and len(want_none) == 5, (rows(o[:i1]), want_none))
check("the contactor: fit by the python rule and its suggestion", rows(o[i1 + 1:i2]) == want_ct, (rows(o[i1 + 1:i2]), want_ct))
check("the analog module: its product fits and is suggested; the others are another class", rows(o[i2 + 1:i3]) == want_am, (rows(o[i2 + 1:i3]), want_am))
check("info: the part, rows, enabled flags", "rows=5" in R[0] and "addenabled=1" in R[0] and "editenabled=0" in R[0] and CT in R[1] and "suggestenabled=0" in R[1], R)
# ---- add / change
s0 = snap(f)
o = run(["peopen " + f, "pe page products", "pe prod part|" + CT,
         "pe prod add|Acme|AC-1|S1|Contactor|preview|first", "pe prod add|acme|ac-2||AnalogInputModule|custom|", "pe prod rows"])
A = pe(o, "prod", "add")
check("add: two accepted", len(A) == 2 and all(a.startswith("PE prod add ok") for a in A), A)
c = db(f); got = c.execute("select Manufacturer,MPN,Series,Status,Description,Revision,length(UID),Modified is not null from Product where Manufacturer in ('Acme','acme') order by MPN").fetchall()
check("add: manufacturer, model, series, status, description, revision 1, a GUID and Modified", got == [("Acme", "AC-1", "S1", "preview", "first", "1", 36, 1), ("acme", "ac-2", "", "custom", "", "1", 36, 1)], got)
check("add: the class is the one named", c.execute("select c.Name from Product p join PartClass c using(ClassID) where MPN='AC-1'").fetchone()[0] == "Contactor" and
      c.execute("select c.Name from Product p join PartClass c using(ClassID) where MPN='ac-2'").fetchone()[0] == "AnalogInputModule")
check("add: the list shows the file", rows(o) == prod_rows(c, ct) and len(rows(o)) == 7, (rows(o), prod_rows(c, ct)))
absn = c.execute("select Name from PartClass where Abstract=1 limit 1").fetchone()[0]; c.close()
s1 = snap(f)
o = run(["peopen " + f, "pe page products", "pe prod add||X||Contactor|active|", "pe prod add|Acme||S||Contactor|active|", "pe prod add|ACME|ac-1||Contactor|active|", "pe prod add|Zed|Z1||Contactor|bogus|",
         "pe prod add|Zed|Z2||%s|active|" % absn, "pe prod add|Zed|Z3||Nonexistent|active|"])
E = pe(o, "prod", "add")
check("refusals: six refused with their reasons", len(E) == 6 and all("error" in e for e in E) and "needs a manufacturer" in E[0] and "needs a model number" in E[1] and "already has a product" in E[2] and
      "status must be" in E[3] and "abstract class" in E[4] and "Choose a class" in E[5], E)
check("refusals: nothing changed", snap(f) == s1)
# change
o = run(["peopen " + f, "pe page products", "pe prod part|" + CT, "pe prod rows"])
rr = rows(o); order = [r[:2] for r in rr]
ix = lambda m: order.index(m)
o = run(["peopen " + f, "pe page products", "pe prod part|" + CT, "pe prod prop|%d|Acme|AC-1|S2|Contactor|active|changed" % ix(["Acme", "AC-1"]),
         "pe prod prop|%d|Example Co|CTR-25-24DC|S3|AnalogInputModule|active|" % ix(["Example Co", "CTR-25-24DC"]),
         "pe prod prop|%d|Other Co|OC-18-24DC|x|AnalogInputModule|active|moved" % ix(["Other Co", "OC-18-24DC"]), "pe prod prop|%d|Example Co|ctr-32-24dc||Contactor|active|" % ix(["Acme", "AC-1"]), "pe prod rows"])
P = pe(o, "prod", "prop")
check("change: own key kept ok; a product suggested for parts cannot change class; an unsuggested one can; a taken key refused",
      len(P) == 4 and P[0] == "PE prod prop ok" and "suggested for parts" in P[1] and P[2] == "PE prod prop ok" and "already has a product" in P[3], P)
c = db(f)
r = c.execute("select Series,Status,Description,Revision from Product where MPN='AC-1'").fetchone()
check("change: values and revision + 1", r == ("S2", "active", "changed", "2"), r)
check("change: the unsuggested product moved class, revision 1 (null) -> 2", c.execute("select c.Name,Revision from Product p join PartClass c using(ClassID) where MPN='OC-18-24DC'").fetchone() == ("AnalogInputModule", "2"))
check("change: the suggested product is where it was", c.execute("select c.Name,Revision from Product p join PartClass c using(ClassID) where MPN='CTR-25-24DC'").fetchone()[0] == "Contactor")
check("change: the list follows the file", rows(o) == prod_rows(c, ct), (rows(o), prod_rows(c, ct)))
c.close()
# ---- delete
c = db(f)
p3 = c.execute("select ProductID from Product where MPN='CTR-32-24DC'").fetchone()[0]; p5 = c.execute("select ProductID from Product where MPN='OC-25-110AC'").fetchone()[0]
c.execute("update Product set ReplacedBy=? where ProductID=?", (p3, p5)); c.execute("insert into Substitute(ProductID,SubstituteID) values (?,?)", (p5, p3)); c.execute("insert into PartProduct(PartID,ProductID) values (?,?)", (ct, p3)); c.commit()
n_rat = c.execute("select count(*) from Rating").fetchone()[0]; r3 = c.execute("select count(*) from Rating where ProductID=?", (p3,)).fetchone()[0]; c.close()
o = run(["peopen " + f, "pe page products", "pe prod part|" + CT, "pe prod rows"]); order = [r[:2] for r in rows(o)]
o = run(["peopen " + f, "pe page products", "pe prod part|" + CT, "pe prod del|%d" % order.index(["Example Co", "CTR-32-24DC"]), "pe prod rows"])
D = pe(o, "prod", "del"); c = db(f)
check("delete: accepted", D == ["PE prod del ok rows=6"], D)
check("delete: the product, its ratings and suggestions are gone; the others' mentions cleared", c.execute("select count(*) from Product where ProductID=?", (p3,)).fetchone()[0] == 0 and
      c.execute("select count(*) from Rating").fetchone()[0] == n_rat - r3 and c.execute("select count(*) from PartProduct where ProductID=?", (p3,)).fetchone()[0] == 0 and
      c.execute("select ReplacedBy from Product where ProductID=?", (p5,)).fetchone()[0] is None and c.execute("select count(*) from Substitute").fetchone()[0] == 0)
check("delete: the list follows the file", rows(o) == prod_rows(c, ct), (rows(o), prod_rows(c, ct)))
c.close()
# ---- ratings
c = db(f); ocr = c.execute("select ProductID from Product where MPN='OC-18-24DC'").fetchone()[0]; c.close()
o = run(["peopen " + f, "pe page products", "pe prod part|" + CT, "pe prod rows"]); order = [r[:2] for r in rows(o)]
row_oc = order.index(["Other Co", "OC-18-24DC"]); row_5 = order.index(["Other Co", "OC-25-110AC"]); row_ex = order.index(["Example Co", "CTR-25-24DC"]); row_ac = order.index(["Acme", "AC-1"])
o = run(["peopen " + f, "pe page products", "pe prod part|" + CT, "pe prod select|%d" % row_ac, "pe prod rrows",
         "pe prod radd|kind:contact|current||0|25|25|AC-3 400 V", "pe prod radd||motor_power|kW||11|11|AC-3 400 V", "pe prod radd|A1/A2|coil_voltage|V|||24|", "pe prod radd|A1/A2|coil_power||2,4|||", "pe prod rrows", "pe prod rows"])
Rr = pe(o, "prod", "radd")
check("ratings: four accepted (a kind in any case, the whole product, an object name, a comma as the decimal mark)", len(Rr) == 4 and all(a.startswith("PE prod radd ok") for a in Rr), Rr)
c = db(f); pid = c.execute("select ProductID from Product where MPN='AC-1'").fetchone()[0]
got = c.execute("select coalesce(AppliesTo,''),Quantity,Min,Typ,Max,Unit,coalesce(Condition,'') from Rating where ProductID=? order by AppliesTo is not null, AppliesTo, Quantity", (pid,)).fetchall()
want = [("", "motor_power", None, 11.0, 11.0, "kW", "AC-3 400 V"), ("A1/A2", "coil_power", 2.4, None, None, "W", ""), ("A1/A2", "coil_voltage", None, None, 24.0, "V", ""), ("kind:Contact", "current", 0.0, 25.0, 25.0, "A", "AC-3 400 V")]
check("ratings: the rows (kind spelled as the library has it, unit from the quantity)", [tuple(x) for x in got] == want, got)
shown = [r for r in rrows(o)]
check("ratings: the list shows them with the whole product first", [r[0] for r in shown] == ["(the whole product)", "A1/A2", "A1/A2", "kind:Contact"] and shown[3][2:5] == ["0", "25", "25"], shown)
check("ratings: revision up by one per change (2 -> 6)", c.execute("select Revision from Product where ProductID=?", (pid,)).fetchone()[0] == "6")
check("ratings: the fit column follows the python verdict", rows(o) == prod_rows(c, ct), (rows(o), prod_rows(c, ct)))
s2 = snap(f); c.close()
o = run(["peopen " + f, "pe page products", "pe prod part|" + CT, "pe prod select|%d" % row_ac, "pe prod radd|kind:Nonexistent|current||0|25|25|AC-3 400 V", "pe prod radd||motor_power|W||11|11|AC-3 400 V",
         "pe prod radd||coil_power||||", "pe prod radd||coil_power||5|2||", "pe prod radd||motor_power|kW||11|12|AC-3 400 V", "pe prod radd||no_such|V||1||"])
E = pe(o, "prod", "radd")
check("rating refusals: six refused with reasons", len(E) == 6 and all("error" in e for e in E) and "not a kind of object" in E[0] and "unit of motor_power is kW" in E[1] and "at least one" in E[2] and "minimum is above" in E[3] and
      "already has a rating" in E[4] and "not a quantity" in E[5], E)
check("rating refusals: nothing changed", snap(f) == s2)
o = run(["peopen " + f, "pe page products", "pe prod part|" + CT, "pe prod select|%d" % row_ac, "pe prod rrows"]); sh = rrows(o)
iw = [r[0] for r in sh].index("(the whole product)")
o = run(["peopen " + f, "pe page products", "pe prod part|" + CT, "pe prod select|%d" % row_ac, "pe prod rprop|%d|kind:Contact|current|A|0|20|20|AC-3 400 V" % [r[0] for r in sh].index("kind:Contact"),
         "pe prod rprop|%d|kind:Contact|current|A|0|20|20|AC-3 400 V" % iw, "pe prod rdel|%d" % iw, "pe prod rrows", "pe prod rows"])
Q = [l for l in o if l.startswith("PE prod rprop") or l.startswith("PE prod rdel")]
c = db(f)
check("rating change: own key kept ok, a clash with another rating refused; delete ok", Q[0] == "PE prod rprop ok" and "already has a rating" in Q[1] and Q[2].startswith("PE prod rdel ok"), Q)
check("rating change: the value, the deletion, the revision (6 -> 8) and the fit follow the file", c.execute("select Max from Rating where ProductID=? and AppliesTo='kind:Contact'", (pid,)).fetchone()[0] == 20.0 and
      c.execute("select count(*) from Rating where ProductID=? and AppliesTo is null", (pid,)).fetchone()[0] == 0 and c.execute("select Revision from Product where ProductID=?", (pid,)).fetchone()[0] == "8" and rows(o) == prod_rows(c, ct), (rows(o), prod_rows(c, ct)))
c.close()
# ---- suggestions
row_oc2 = order.index(["Other Co", "OC-18-24DC"])
o = run(["peopen " + f, "pe page products", "pe prod part|" + CT, "pe prod select|%d" % row_5, "pe prod sug|%d|0" % row_5, "pe prod sug|%d|1" % row_ex, "pe prod sug|%d|1" % row_5, "pe prod rows", "pe prod sug|%d|-1" % row_ex,
         "pe prod sug|%d|0" % row_oc2, "pe prod rows"])
S = pe(o, "prod", "sug"); c = db(f)
ir = [i for i, l in enumerate(o) if l.startswith("PEPRODINFO")]
sg1 = {tuple(r[:2]): r[7] for r in rows(o[:ir[0]])}; sg2 = {tuple(r[:2]): r[7] for r in rows(o[ir[0] + 1:ir[1]])}
check("suggestions: four accepted, the product of another class refused", S[:4] == ["PE prod sug ok"] * 4 and S[4].startswith("PE prod sug error") and "another class" in S[4], S)
check("suggestions: one preferred per part (the new preferred takes it over); the others stay suggested",
      sg1[("Example Co", "CTR-25-24DC")] == "suggested" and sg1[("Other Co", "OC-25-110AC")] == "preferred" and [k for k, v in sg1.items() if v] == [("Example Co", "CTR-25-24DC"), ("Other Co", "OC-25-110AC")], sg1)
check("suggestions: removing one", [k for k, v in sg2.items() if v] == [("Other Co", "OC-25-110AC")], sg2)
pp = c.execute("select p.MPN,Preferred from PartProduct pp join Product p using(ProductID) where PartID=? order by 1", (ct,)).fetchall()
check("suggestions: the file has the short list; the other part's list is untouched", pp == [("OC-25-110AC", 1)] and c.execute("select count(*) from PartProduct where PartID=?", (am,)).fetchone()[0] == 1, pp)
check("suggestions: the list shows the file", rows(o[ir[0] + 1:ir[1]]) == prod_rows(c, ct), (rows(o[ir[0] + 1:ir[1]]), prod_rows(c, ct)))
c.close()
# ---- dialogs
f2 = mk("b.TCParts"); c = db(f2)
nonabs = c.execute("select ClassID,Name,ParentID from PartClass where Abstract=0").fetchall(); cm = {r[0]: r for r in c.execute("select ClassID,Name,ParentID from PartClass")}
def path(i):
    r = cm[i]; return r[1] if r[2] is None else path(r[2]) + " > " + r[1]
want_cls = sorted(path(r[0]) for r in nonabs)
kinds = ["kind:" + n for (n,) in c.execute("select Name from ObjectKind where Abstract=0")]
objn = [n for (n,) in c.execute("select distinct o.Name from PartObject o join Part p using(PartID) where p.ClassID=(select ClassID from Product where MPN='CTR-25-24DC') order by o.Name")]
c.close()
o = run(["peopen " + f2, "pe page products", "pe prod part|" + CT, "pe prod dlg|-1", "pe prod dlg|%d" % 1, "pe prod select|1", "pe prod rdlg|-1", "pe prod rdlg|0"])
D = [l for l in o if l.startswith("PEDLG ")]
cl = [l[len("PEDLGCLASS "):] for l in o if l.startswith("PEDLGCLASS ")][:len(want_cls)]
check("product dialog (new): the classes offered are the non-abstract ones, by path", "caption=Add Product" in D[0] and cl == want_cls, (D[0], cl, want_cls))
check("product dialog (change): its entries", "caption=Product Properties" in D[1] and "manufacturer=Example Co" in D[1] and "model=CTR-25-24DC" in D[1] and "class=" in D[1] and "status=active" in D[1], D[1])
objs = [l[len("PEDLGOBJ "):] for l in o if l.startswith("PEDLGOBJ ")]
n1 = 1 + len(kinds) + len(objn)
check("rating dialog (product): the whole product, every kind, then the class's object names", "caption=Add Product Rating" in D[2] and "choices=%d" % n1 in D[2] and objs[:n1] == ["(the whole product)"] + kinds + objn, (D[2], objs[:n1]))
check("rating dialog (change): its entries", "caption=Product Rating Properties" in D[3] and "quantity=" in D[3] and "appliesto=" in D[3], D[3])
print("product checks: %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
