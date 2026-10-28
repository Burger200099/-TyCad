#!/usr/bin/env python3
"""Parts library editor, field values (Phase B5b): the Values page lists the fields a generic part can hold values for (its class's, then each child object's kind's) and sets or
clears the values, on the real program under Xvfb (script commands `pe page values`, `pe val ...`).
Oracles (independent of the program): the file is read with Python's sqlite3 -- FieldDef / KindFieldDef walked up the class and kind trees here, PartValue, ObjectValue, the part's
Revision -- and compared with expectations written here from the sample library built by docs/parts_seed.py.
  - the page: the rows equal the fields (ancestors' first, then the object's kinds' fields in the part's order) with the stored values as a person reads them (numbers without
    trailing zeros, bool yes / no) and the Required column ('required - missing' for an empty required field)
  - set: one value of every type on the part and on an object (the columns the type uses: int / real / bool in ValueNum, the rest in ValueText; a comma as the decimal mark;
    enum in the field's own spelling); revision + 1 per change; clear removes the row
  - refused (file unchanged): a fraction for an int, text for a real, anything but yes / no for a bool, a value outside an enum, a field the class (or the object's kind) does not have,
    an object of another part
  - dialog: the information line, a list for enum (none + values) and bool (none, yes, no), typing for the rest, the value now; menu items follow the page and the choice
Needs the built program and xvfb."""
import os, shutil, sqlite3, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Value checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
    c = db(p); r = (c.execute("select * from PartValue order by 1,2").fetchall(), c.execute("select * from ObjectValue order by 1,2").fetchall(), c.execute("select PartID,Revision,Modified from Part order by 1").fetchall()); c.close(); return r
def chain(c, tbl, k):
    r = []
    while k is not None: r.append(k); k = c.execute("select ParentID from %s where %sID=?" % (tbl, "Class" if tbl == "PartClass" else "Kind"), (k,)).fetchone()[0]
    return r
def fmt(t, n, s):
    if t in ("int", "real"): return "%.12g" % n
    if t == "bool": return "yes" if n else "no"
    return s
def oracle(c, pid):
    out = []; cls = c.execute("select ClassID from Part where PartID=?", (pid,)).fetchone()[0]
    def fields(tbl, key, k, vtbl, vkey, vid):
        for anc in reversed(chain(c, tbl, k)):
            for fid, nm, ty, un, en, rq in c.execute("select FieldID,Name,Type,coalesce(Unit,''),coalesce(EnumValues,''),Required from %s where %s=? order by FieldID" % ("FieldDef" if tbl == "PartClass" else "KindFieldDef", key), (anc,)).fetchall():
                v = c.execute("select ValueNum,ValueText from %s where %s=? and FieldID=?" % (vtbl, vkey), (vid, fid)).fetchone()
                dec = c.execute("select Name from %s where %s=?" % (tbl, "ClassID" if tbl == "PartClass" else "KindID"), (anc,)).fetchone()[0]
                yield fid, nm, ty, un, en, rq, v, dec
    for fid, nm, ty, un, en, rq, v, dec in fields("PartClass", "ClassID", cls, "PartValue", "PartID", pid):
        out.append(dict(obj=0, objn="(the part)", fid=fid, name=nm, type=ty, unit=un, enum=en, req=rq, has=v is not None, val=fmt(ty, v[0], v[1]) if v else "", dec=dec))
    for oid, on, kid in c.execute("select ObjectID,Name,KindID from PartObject where PartID=? order by Sort,ObjectID", (pid,)).fetchall():
        for fid, nm, ty, un, en, rq, v, dec in fields("ObjectKind", "KindID", kid, "ObjectValue", "ObjectID", oid):
            out.append(dict(obj=oid, objn=on, fid=fid, name=nm, type=ty, unit=un, enum=en, req=rq, has=v is not None, val=fmt(ty, v[0], v[1]) if v else "", dec=dec))
    return out
def as_lines(rows): return [[r["objn"], r["name"], r["type"], r["unit"], r["val"], ("required - missing" if not r["has"] else "required") if r["req"] else "", r["dec"]] for r in rows]
def prow(o): return [l[len("PEVAL "):].split("|") for l in o if l.startswith("PEVAL ")]
def pe(o, what): return [l for l in o if l.startswith("PE val %s" % what)]
CT = "Contactor 3P 25 A AC-3, 24 V DC coil"; AM = "Analog input module, 4 channels, current"
f = mk("a.TCParts"); c = db(f)
ct = c.execute("select PartID from Part where Name=?", (CT,)).fetchone()[0]; am = c.execute("select PartID from Part where Name=?", (AM,)).fetchone()[0]
want_ct = as_lines(oracle(c, ct)); want_am = as_lines(oracle(c, am)); orc = oracle(c, ct); rev0 = c.execute("select Revision from Part where PartID=?", (ct,)).fetchone()[0]
amobj = c.execute("select ObjectID from PartObject where PartID=? limit 1", (am,)).fetchone()[0]; c.close()
o = run(["peopen " + f, "pe menu", "pe page values", "pe menu", "pe val part|" + CT, "pe val rows", "pe val select|0", "pe menu", "pe val part|" + AM, "pe val rows"])
M = [l.split(" symnew=")[0] for l in o if l.startswith("PEMENU")]
check("menu: off outside the page; Set needs a chosen field; Clear needs a stored value", len(M) == 3 and M[0].endswith("vset=0 vclear=0") and (M[1].endswith("vset=0 vclear=0") or M[1].endswith("vset=1 vclear=1") or M[1].endswith("vset=1 vclear=0")) and M[0].startswith("PEMENU add=1"), M)
I = [i for i, l in enumerate(o) if l.startswith("PEVALINFO")]
check("the contactor's rows equal the fields and values in the file", prow(o[:I[0]]) == want_ct and len(want_ct) > 30, (prow(o[:I[0]])[:6], want_ct[:6], len(want_ct)))
check("the analog module's rows equal the file", prow(o[I[0] + 1:I[1]]) == want_am and len(want_am) > 10, (prow(o[I[0] + 1:I[1]])[:4], want_am[:4]))
check("the required column marks required fields (with and without a value)", any(r[5] == "required" for r in want_ct) and any(r[5].startswith("required") for r in want_am), [r[5] for r in want_ct][:20])
# ---- set one of each type on the part and on objects
def pick(ty, obj_zero):
    for i, r in enumerate(orc):
        if r["type"] == ty and ((r["obj"] == 0) == obj_zero): return i, r
    return None, None
cmds = ["peopen " + f, "pe page values", "pe val part|" + CT]; plan = []
for ty, zero, val in (("real", True, "12,5"), ("int", True, "7"), ("bool", True, "1"), ("text", True, "hello"), ("enum", True, None), ("enum", False, None), ("bool", False, "1"), ("real", False, "0.25")):
    i, r = pick(ty, zero)
    if r is None: continue
    if val is None: val = r["enum"].split(",")[-1].strip().lower()
    cmds.append("pe val set|%d|%s" % (i, val)); plan.append((i, r, val))
cmds.append("pe val rows")
o = run(cmds); S = pe(o, "set")
check("set: every value accepted", len(S) == len(plan) and all(x == "PE val set ok" for x in S) and len(plan) >= 6, (S, [(p[1]["type"], p[1]["obj"]) for p in plan]))
c = db(f); bad = []
for i, r, val in plan:
    tbl, key, kid = ("PartValue", "PartID", ct) if r["obj"] == 0 else ("ObjectValue", "ObjectID", r["obj"])
    n, t = c.execute("select ValueNum,ValueText from %s where %s=? and FieldID=?" % (tbl, key), (kid, r["fid"])).fetchone()
    ty = r["type"]
    if ty == "real": ok = n is not None and t is None and abs(n - float(val.replace(",", "."))) < 1e-12
    elif ty == "int": ok = n == int(val) and t is None
    elif ty == "bool": ok = t is None and n == (1 if val.lower() in ("true", "yes", "1") else 0)
    elif ty == "enum": ok = n is None and t == [e.strip() for e in r["enum"].split(",") if e.strip().lower() == val.lower()][0]
    else: ok = n is None and t == val
    if not ok: bad.append((r["name"], ty, n, t, val))
check("set: the right column holds each value (numbers in ValueNum, text in ValueText, enum in the field's spelling)", not bad, bad)
rev1 = c.execute("select Revision from Part where PartID=?", (ct,)).fetchone()[0]
check("set: revision up by one per change", int(rev1) == int(rev0 or 1) + len(plan), (rev0, rev1))
check("set: the list shows the file", prow(o) == as_lines(oracle(c, ct)), (prow(o)[:3], as_lines(oracle(c, ct))[:3]))
check("set: the other part is untouched", as_lines(oracle(c, am)) == want_am)
c.close()
# ---- clear
c = db(f); orc2 = oracle(c, ct); c.close()
idx = [i for i, r in enumerate(orc2) if r["has"]][0]
o = run(["peopen " + f, "pe page values", "pe val part|" + CT, "pe val clear|%d" % idx, "pe val rows"])
c = db(f); r = orc2[idx]; tbl, key, kid = ("PartValue", "PartID", ct) if r["obj"] == 0 else ("ObjectValue", "ObjectID", r["obj"])
check("clear: the stored value is gone and the list says so", c.execute("select count(*) from %s where %s=? and FieldID=?" % (tbl, key), (kid, r["fid"])).fetchone()[0] == 0 and prow(o) == as_lines(oracle(c, ct)) and
      pe(o, "clear") == ["PE val clear ok"], pe(o, "clear"))
check("clear: revision + 1", int(c.execute("select Revision from Part where PartID=?", (ct,)).fetchone()[0]) == int(rev1) + 1)
orc3 = oracle(c, ct); c.close()
# ---- refusals
s0 = snap(f)
def find(ty, zero):
    for i, r in enumerate(orc3):
        if r["type"] == ty and ((r["obj"] == 0) == zero): return i, r
ii = find("int", True)[0]; ri = find("real", True)[0]; bi = find("bool", True)[0]; ei = find("enum", True)[0]; ri2 = find("real", False)[0]
c = db(f)
otherclass_field = c.execute("select FieldID from FieldDef where ClassID not in (%s)" % ",".join(map(str, chain(c, "PartClass", c.execute("select ClassID from Part where PartID=?", (ct,)).fetchone()[0])))).fetchone()[0]
amkind_field = c.execute("select kf.FieldID from PartObject o join ObjectKind k using(KindID) join KindFieldDef kf on kf.KindID=o.KindID where o.PartID=? limit 1", (am,)).fetchone()[0]
ok_kinds = chain(c, "ObjectKind", c.execute("select KindID from PartObject where ObjectID=?", (orc3[ri2]["obj"],)).fetchone()[0])
wrong_kind_field = c.execute("select FieldID from KindFieldDef where KindID not in (%s) limit 1" % ",".join(map(str, ok_kinds))).fetchone()[0]
c.close()
o = run(["peopen " + f, "pe page values", "pe val part|" + CT, "pe val set|%d|2.5" % ii, "pe val set|%d|abc" % ri, "pe val set|%d|maybe" % bi, "pe val set|%d|zzz" % ei, "pe val set|%d|x" % ri2,
         "pe val raw|0|%d|1" % otherclass_field, "pe val raw|%d|%d|1" % (amobj, amkind_field), "pe val raw|%d|%d|1" % (orc3[ri2]["obj"], wrong_kind_field)])
E_ = [l for l in o if l.startswith("PE val set error") or l.startswith("PE val raw error")]
check("refusals: eight refused with reasons", len(E_) == 8 and "not a whole number" in E_[0] and "not a number" in E_[1] and "not yes or no" in E_[2] and "is not one of" in E_[3] and "not a number" in E_[4] and
      "That field is not a field of the part's class." in E_[5] and "That object is not an object of this part." in E_[6] and "That field is not a field of the object's kind." in E_[7], E_)
check("refusals: nothing changed", snap(f) == s0)
# ---- dialogs
f2 = mk("b.TCParts"); c = db(f2); o3 = oracle(c, ct); c.close()
ie = find.__call__ if False else None
def first(ty, zero, o3=o3):
    for i, r in enumerate(o3):
        if r["type"] == ty and ((r["obj"] == 0) == zero): return i, r
iE, rE = first("enum", False); iB, rB = first("bool", True); iR, rR = first("real", True); iT, rT = first("text", True)
o = run(["peopen " + f2, "pe page values", "pe val part|" + CT, "pe val dlg|%d" % iE, "pe val dlg|%d" % iB, "pe val dlg|%d" % iR, "pe val dlg|%d" % iT])
D = [l for l in o if l.startswith("PEDLG ")]
vals = lambda a, b: [l[len("PEDLGVAL "):] for l in o[o.index(a) + 1:(o.index(b) if b else len(o))] if l.startswith("PEDLGVAL ")]
check("dialog (enum on an object): a list of (none) and the field's values, its information line", "picker=1" in D[0] and vals(D[0], D[1]) == ["(none)"] + [e.strip() for e in rE["enum"].split(",")] and rE["name"] in D[0] and rE["objn"] in D[0] and "enum" in D[0], D[0])
check("dialog (bool): (none), yes, no; the stored value is selected", "picker=1" in D[1] and vals(D[1], D[2]) == ["(none)", "yes", "no"] and ("value=" + rB["val"]) in D[1] + " ", D[1])
check("dialog (real, text): typed, with the value now and a hint", "picker=0" in D[2] and "picker=0" in D[3] and ("value=" + rR["val"]) in D[2] and "number" in D[2] and "Text" in D[3], (D[2], D[3]))
print("value checks: %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
