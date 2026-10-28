#!/usr/bin/env python3
"""Parts library editor, child objects (Phase B5): the Objects page shows the terminals, poles, channels ... of a generic part as a tree and adds, changes and deletes them, on the
real program under Xvfb (script commands `pe page objects`, `pe obj ...` = the editor's calls without their dialogs).
Oracles (independent of the program): the file is read with Python's sqlite3 -- PartObject, Link, Rating, ObjectValue, the part's Revision -- and compared with expectations written
here from the sample library built by docs/parts_seed.py; the kinds a class allows are worked out here by walking PartClass and ObjectKind (not with the library's views).
  - the page: the tree equals PartObject (children below their parent, in Sort, ObjectID order; "name [designator] - kind")
  - add: the row (name, designator, kind, parent, order, description); revision + 1, Modified stamped; other parts untouched
  - refused (PartObject, Link, Rating, Part unchanged): empty name, a name the part has already (any case), an unknown kind, a kind the class does not allow, an abstract kind, a parent that
    is not an object of the part, an object below itself or below its own child, a kind change that strands field values
  - change: every entry; keeping its own name is allowed; the revision goes up
  - delete: the object, everything inside it, their requirements, values and links go; the rest stays; refused while a symbol pin uses the object or one inside it
  - dialog: the kinds offered, the parents offered (not itself or what lies inside), the entries of an object, the default order and parent; menu items follow the page and the choice
Needs the built program and xvfb."""
import os, shutil, sqlite3, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Object checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
    r = tuple(c.execute("select * from %s order by 1,2" % t).fetchall() for t in ("PartObject", "Link", "Rating", "ObjectValue")) + (c.execute("select PartID,Revision,Modified from Part order by PartID").fetchall(),)
    c.close(); return r
def pid(c, name): return c.execute("select PartID from Part where Name=?", (name,)).fetchone()[0]
def objs(c, p): return c.execute("select o.ObjectID,o.Name,coalesce(o.Designator,''),k.Name,o.ParentObjectID,o.Sort,coalesce(o.Description,'') from PartObject o join ObjectKind k using(KindID) where o.PartID=? order by o.Sort,o.ObjectID", (p,)).fetchall()
def tree(c, p):
    L = objs(c, p); out = []
    def walk(par, d):
        for i, n, ds, k, pa, so, de in L:
            if pa == par:
                out.append([str(d), "%s%s - %s" % (n, " [%s]" % ds if ds else "", k), str(i)]); walk(i, d + 1)
    walk(None, 0); return out
def kind_chain(c, k):
    r = []
    while k is not None: r.append(k); k = c.execute("select ParentID from ObjectKind where KindID=?", (k,)).fetchone()[0]
    return r
def class_chain(c, k):
    r = []
    while k is not None: r.append(k); k = c.execute("select ParentID from PartClass where ClassID=?", (k,)).fetchone()[0]
    return r
def allowed(c, p):
    cls = c.execute("select ClassID from Part where PartID=?", (p,)).fetchone()[0]
    roots = {r[0] for r in c.execute("select KindID from ClassAllowsKind where ClassID in (%s)" % ",".join(map(str, class_chain(c, cls))))}
    return sorted([n for k, n, ab in c.execute("select KindID,Name,Abstract from ObjectKind") if ab == 0 and roots & set(kind_chain(c, k))], key=str.lower)
def descend(c, p, oid):
    r = {oid}; ch = True
    while ch:
        ch = False
        for (i,) in c.execute("select ObjectID from PartObject where PartID=? and ParentObjectID in (%s)" % ",".join(map(str, r)), (p,)).fetchall():
            if i not in r: r.add(i); ch = True
    return r
def pe(o, sub, what): return [l for l in o if l.startswith("PE %s %s " % (sub, what))]
def rows(o): return [l[len("PEOBJ "):].split("|") for l in o if l.startswith("PEOBJ ")]
CT = "Contactor 3P 25 A AC-3, 24 V DC coil"; AM = "Analog input module, 4 channels, current"
f = mk("a.TCParts"); c = db(f)
ct = pid(c, CT); am = pid(c, AM)
rev0 = c.execute("select Revision from Part where PartID=?", (ct,)).fetchone()[0]
want = tree(c, ct); want_am = tree(c, am); n0 = len(objs(c, ct)); c.close()
check("sample: 13 objects", n0 == 13 and len(want) == 13)
o = run(["peopen " + f, "pe menu", "pe page objects", "pe menu", "pe obj part|" + CT, "pe obj rows", "pe menu", "pe obj select|Pole 2", "pe menu", "pe obj part|" + AM, "pe obj rows"])
M = [l for l in o if l.startswith("PEMENU")]
check("menu: off outside the page; Add needs a part, Properties and Delete a chosen object", len(M) == 4 and ("oadd=0 oprops=0 odel=0" in M[0]) and ("oadd=1 oprops=0 odel=0" in M[1]) and
      ("oadd=1 oprops=0 odel=0" in M[2]) and ("oadd=1 oprops=1 odel=1" in M[3]), M)
info = [l for l in o if l.startswith("PEOBJINFO")]; i0 = o.index(info[0])
check("the tree equals the part's objects (parent first, children in order)", rows(o[:i0]) == want, (rows(o[:i0]), want))
check("the analog module's tree equals its objects", rows(o[i0 + 1:]) == want_am and len(want_am) == 13, rows(o[i0 + 1:]))
check("info: the part, row count and enabled buttons", "rows=13" in info[0] and CT in info[0] and "addenabled=1" in info[0] and "editenabled=0" in info[0], info)
# ---- add
s0 = snap(f)
o = run(["peopen " + f, "pe page objects", "pe obj part|" + CT,
         "pe obj add|Aux|X1|Terminal|Pole 1|7|extra terminal", "pe obj add|Aux coil|A3|Coil||2|", "pe obj add|aux 2||terminal|Pole 3|-1|", "pe obj rows"])
A = pe(o, "obj", "add")
check("add: three accepted (a kind in any case, a parent by name, none, a negative order)", len(A) == 3 and all(a.startswith("PE obj add ok") for a in A), A)
c = db(f); L = {r[1]: r for r in objs(c, ct)}
name_of = {r[0]: r[1] for r in objs(c, ct)}
check("add: the row has designator, kind, parent, order and description", L["Aux"][2:4] == ("X1", "Terminal") and name_of[L["Aux"][4]] == "Pole 1" and L["Aux"][5:] == (7, "extra terminal"), L.get("Aux"))
check("add: no parent = directly in the part; an empty designator is stored empty", L["Aux coil"][4] is None and L["Aux coil"][3] == "Coil" and L["aux 2"][5] == -1 and L["aux 2"][2] == "", (L["Aux coil"], L["aux 2"]))
rev1 = c.execute("select Revision,Modified from Part where PartID=?", (ct,)).fetchone()
check("add: revision up by one for each change and Modified stamped", rev1[0] == str(int(rev0 or 1) + 3) and rev1[1] is not None, (rev0, rev1))
check("add: the tree shows the file (a new object inside a pole sits below it, order respected)", rows(o) == tree(c, ct) and len(rows(o)) == 16, (rows(o), tree(c, ct)))
check("add: the other part's objects are as they were", tree(c, am) == want_am)
c.close()
# ---- refusals
c = db(f)
# (the contactor's class gets the abstract PassiveObject kind allowed, so that an abstract kind can be offered to it)
c.execute("insert or ignore into ClassAllowsKind(ClassID,KindID) select ClassID,(select KindID from ObjectKind where Name='PassiveObject') from Part where PartID=?", (ct,)); c.commit()
s1 = snap(f)
dis = [k for (k,) in c.execute("select Name from ObjectKind where Abstract=0") if k not in allowed(c, ct)]
ab = [n for (n,) in c.execute("select Name from ObjectKind where Abstract=1") if c.execute("select 1 from ObjectKind where Name=?", (n,)).fetchone()]
# the abstract kind that the class allows through the tree: ActiveObject for the contactor's class
ct_roots = {r[0] for r in c.execute("select KindID from ClassAllowsKind where ClassID in (%s)" % ",".join(map(str, class_chain(c, c.execute("select ClassID from Part where PartID=?", (ct,)).fetchone()[0]))))}
abs_ok = [n for k, n, a in c.execute("select KindID,Name,Abstract from ObjectKind") if a == 1 and ct_roots & set(kind_chain(c, k))]
# an object with values, and a kind the class allows that lacks one of its fields
valued = None
for oid, nm, kn in c.execute("select distinct o.ObjectID,o.Name,k.KindID from ObjectValue v join PartObject o using(ObjectID) join ObjectKind k using(KindID) where o.PartID=?", (ct,)).fetchall():
    fields = {r[0] for r in c.execute("select FieldID from ObjectValue where ObjectID=?", (oid,))}
    for k2n in allowed(c, ct):
        k2 = c.execute("select KindID from ObjectKind where Name=?", (k2n,)).fetchone()[0]
        have = {r[0] for r in c.execute("select FieldID from KindFieldDef where KindID in (%s)" % ",".join(map(str, kind_chain(c, k2))))}
        if k2 != kn and not fields <= have and valued is None: valued = (nm, k2n)
c.close()
check("sample: a disallowed kind, an allowed abstract kind and a value-holding object exist", dis and abs_ok and valued, (dis, abs_ok, valued))
cmds = ["peopen " + f, "pe page objects", "pe obj part|" + CT,
        "pe obj add||A|Terminal||0|", "pe obj add|POLE 1||Terminal||0|", "pe obj add|Z1||Nonexistent||0|", "pe obj add|Z2||%s||0|" % dis[0], "pe obj add|Z3||%s||0|" % abs_ok[0],
        "pe obj add|Z4||Terminal|No such||0|", "pe obj prop|Pole 1|Pole 1||Pole|Pole 1|0|", "pe obj prop|Pole 1|Pole 1||Pole|1L1|0|", "pe obj prop|Aux|Pole 2||Terminal|Pole 1|0|",
        "pe obj prop|%s|%s||%s||0|" % (valued[0], valued[0], valued[1]), "pe obj prop|Nobody|X||Terminal||0|", "pe obj del|Nobody", "pe obj prop|Pole 1|Pole 1||%s||0|" % dis[0]]
o = run(cmds); E = [l for l in o if l.startswith("PE obj ") and "error" in l]
check("refusals: all thirteen were refused", len(E) == 13, [l for l in o if l.startswith("PE obj")])
txt = " ".join(E)
for frag in ("needs a name", "already has an object named POLE 1", "Choose the kind", "The part's class does not allow", "only groups other kinds", "not an object of this part", "below itself", "already has an object named Pole 2",
             "holds values of fields"):
    check("refusal says: " + frag, frag in txt, txt[-700:])
check("refusals: nothing in the file changed", snap(f) == s1)
# ---- change
c = db(f); cid = {r[1]: r[0] for r in objs(c, ct)}; c.close()
o = run(["peopen " + f, "pe page objects", "pe obj part|" + CT,
         "pe obj prop|Aux|Aux|X9|Terminal|Pole 2|3|moved", "pe obj prop|Aux|Aux renamed|X9|Terminal|Pole 2|3|moved", "pe obj prop|Pole 3|Pole 3||Pole||99|last", "pe obj rows"])
P = pe(o, "obj", "prop")
check("change: keeping its own name is allowed; rename, designator, parent, order, description accepted", len(P) == 3 and all(p == "PE obj prop ok" for p in P), P)
c = db(f); L = {r[1]: r for r in objs(c, ct)}; nm = {r[0]: r[1] for r in objs(c, ct)}
check("change: the row follows", "Aux" not in L and L["Aux renamed"][2] == "X9" and nm[L["Aux renamed"][4]] == "Pole 2" and L["Aux renamed"][5:] == (3, "moved") and L["Aux renamed"][0] == cid["Aux"], L.get("Aux renamed"))
check("change: Pole 3 now last in order and with its description; its children stay", L["Pole 3"][5:] == (99, "last") and nm[L["3L3"][4]] == "Pole 3", L["Pole 3"])
check("change: the tree shows the file", rows(o) == tree(c, ct), (rows(o), tree(c, ct)))
rev2 = c.execute("select Revision from Part where PartID=?", (ct,)).fetchone()[0]
check("change: revision up by three", int(rev2) == int(rev1[0]) + 3, (rev1, rev2))
c.close()
# ---- delete
c = db(f)
pole2 = [r[0] for r in objs(c, ct) if r[1] == "Pole 2"][0]; gone = descend(c, ct, pole2); gl = ",".join(map(str, gone))
before = {"obj": n0 + 3, "link_gone": c.execute("select count(*) from Link where FromObject in (%s) or ToObject in (%s)" % (gl, gl)).fetchone()[0],
          "link": c.execute("select count(*) from Link where PartID=?", (ct,)).fetchone()[0], "rat_gone": c.execute("select count(*) from Rating where ObjectID in (%s)" % gl).fetchone()[0],
          "rat": c.execute("select count(*) from Rating").fetchone()[0], "val_gone": c.execute("select count(*) from ObjectValue where ObjectID in (%s)" % gl).fetchone()[0],
          "val": c.execute("select count(*) from ObjectValue").fetchone()[0]}
rev3 = c.execute("select Revision from Part where PartID=?", (ct,)).fetchone()[0]; c.close()
check("sample: Pole 2 holds objects with links, ratings and values", len(gone) >= 5 and before["link_gone"] > 0 and before["rat_gone"] > 0 and before["val_gone"] > 0, (gone, before))
o = run(["peopen " + f, "pe page objects", "pe obj part|" + CT, "pe obj del|Pole 2", "pe obj rows"])
D = pe(o, "obj", "del")
c = db(f); gl2 = ",".join(map(str, gone))
check("delete: accepted", D == ["PE obj del ok rows=%d" % (before["obj"] - len(gone))], D)
check("delete: the object and everything inside it are gone, the rest stays", c.execute("select count(*) from PartObject where ObjectID in (%s)" % gl2).fetchone()[0] == 0 and
      c.execute("select count(*) from PartObject where PartID=?", (ct,)).fetchone()[0] == before["obj"] - len(gone))
check("delete: their links, requirements and values are gone, all others stay", c.execute("select count(*) from Link where PartID=?", (ct,)).fetchone()[0] == before["link"] - before["link_gone"] and
      c.execute("select count(*) from Rating").fetchone()[0] == before["rat"] - before["rat_gone"] and c.execute("select count(*) from ObjectValue").fetchone()[0] == before["val"] - before["val_gone"])
check("delete: revision + 1", int(c.execute("select Revision from Part where PartID=?", (ct,)).fetchone()[0]) == int(rev3) + 1)
check("delete: the tree shows the file; the other part is untouched", rows(o) == tree(c, ct) and tree(c, am) == want_am)
c.close()
# ---- delete blocked by a symbol pin (set up with sqlite directly)
c = db(f)
c.execute("insert into Symbol(PartID,Name,Drawing) values (?,?,x'00')", (ct, "S")); sym = c.execute("select max(SymbolID) from Symbol").fetchone()[0]
t3 = c.execute("select ObjectID from PartObject where PartID=? and Name='3T3'", (ct,)).fetchone()[0]
c.execute("insert into SymbolPin(SymbolID,ObjectID,X,Y) values (?,?,0,0)", (sym, t3)); c.commit(); c.close()
s2 = snap(f)
o = run(["peopen " + f, "pe page objects", "pe obj part|" + CT, "pe obj del|3T3", "pe obj del|Pole 3"])
D = pe(o, "obj", "del")
check("delete: refused while a symbol pin uses the object, or an object inside it", len(D) == 2 and all("error" in d and "symbol pin" in d for d in D), D)
check("delete refused: nothing changed", snap(f) == s2)
c = db(f); c.execute("delete from SymbolPin"); c.commit(); c.close()
o = run(["peopen " + f, "pe page objects", "pe obj part|" + CT, "pe obj del|Pole 3"]); D = pe(o, "obj", "del")
c = db(f)
check("delete: allowed once the pin is gone", len(D) == 1 and D[0].startswith("PE obj del ok") and c.execute("select count(*) from PartObject where Name in ('Pole 3','3L3','3T3','3L3-3T3')").fetchone()[0] == 0, D)
c.close()
# ---- the analog module's class does not allow a pole; its channels exist
o = run(["peopen " + f, "pe page objects", "pe obj part|" + AM, "pe obj add|P||Pole||0|", "pe obj add|Channel 5|I4|Channel||9|"])
A = pe(o, "obj", "add")
c = db(f)
check("a class that does not allow poles refuses one and takes a channel", A[0].startswith("PE obj add error") and "does not allow" in A[0] and A[1].startswith("PE obj add ok") and
      c.execute("select count(*) from PartObject where PartID=? and Name='Channel 5'", (am,)).fetchone()[0] == 1, A)
c.close()
# ---- dialog
f2 = mk("b.TCParts"); c = db(f2)
want_kinds = allowed(c, ct); L = objs(c, ct); nmap = {r[0]: r for r in L}
def path(i):
    r = nmap[i]; return r[1] if r[4] is None else path(r[4]) + " > " + r[1]
pole1 = [r[0] for r in L if r[1] == "Pole 1"][0]; sub = descend(c, ct, pole1)
want_par = ["(the part itself)"] + [path(r[0]) for r in L if r[0] not in sub]
want_par_new = ["(the part itself)"] + [path(r[0]) for r in L]
c.close()
o = run(["peopen " + f2, "pe page objects", "pe obj part|" + CT, "pe obj dlg||", "pe obj dlg||Pole 2", "pe obj dlg|Pole 1|"])
D = [l for l in o if l.startswith("PEDLG ")]
k_new = [l[len("PEDLGKIND "):] for l in o[:o.index(D[1])] if l.startswith("PEDLGKIND ")]
p_new = [l[len("PEDLGPAR "):] for l in o[:o.index(D[1])] if l.startswith("PEDLGPAR ")]
p_pole = [l[len("PEDLGPAR "):] for l in o[o.index(D[2]):] if l.startswith("PEDLGPAR ")]
check("dialog (new): title, the allowed kinds sorted, every object as a parent, order one past the last", "caption=Add Object" in D[0] and k_new == want_kinds and p_new == want_par_new and "order=1 " in D[0] + " " and
      "parent=(the part itself)" in D[0], (D[0], k_new, want_kinds))
check("dialog (new inside Pole 2): the parent starts as Pole 2", "parent=Pole 2" in D[1], D[1])
check("dialog (Pole 1): its entries; itself and what lies inside are not offered as parents", "caption=Object Properties" in D[2] and "name=Pole 1" in D[2] and "kind=Pole" in D[2] and "parent=(the part itself)" in D[2] and p_pole == want_par, (D[2], p_pole, want_par))
print("object checks: %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
