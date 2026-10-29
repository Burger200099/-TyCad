#!/usr/bin/env python3
"""Parts library editor, Poles and Contacts (step 5 of docs/parts_review_and_roadmap.md): the coil, poles and contacts of a part as rows with the form (NO / NC ...) and delay (none /
on-delay / off-delay and its seconds) of each contact, added, changed and deleted through the dialog's calls (script `pe sw ...`) on the real program under Xvfb.
Oracles (independent of the program): the file read with Python's sqlite3 -- PartObject, ObjectValue, KindFieldDef, Part.Revision -- against expectations written here from the sample
library built by docs/parts_seed.py.
  - new files have the Contact fields Delay and DelaySecs; an older file without them gets them when the dialog is used
  - the dialog lists the Form and Delay values of the file, and the rows equal the part's Coil / Pole / Contact objects with their values
  - Add Pole: a Pole n with PoleNo n and a Contact inside it with the form and delay chosen; Add Contact goes inside the pole; Change stores designator, form, delay and seconds; none removes
    the delay and its seconds; each change raises the part's revision
  - refused (file unchanged): a delay without a time, a time that is not a number, a part whose class has no poles, deleting a contact a symbol shows
  - Delete takes a pole with its contact
Needs the built program and xvfb."""
import os, shutil, sqlite3, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Switching checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
def pid(c, name): return c.execute("select PartID from Part where Name=?", (name,)).fetchone()[0]
CT = "Contactor 3P 25 A AC-3, 24 V DC coil"; AM = "Analog input module, 4 channels, current"
def model(c, p):
    """rows of the part as the page must show them, from the tables: (kind, name, designator, form, delay, seconds)"""
    kinds = {r[0]: r[1] for r in c.execute("select KindID, Name from ObjectKind")}
    par = {r[0]: r[1] for r in c.execute("select KindID, ParentID from ObjectKind")}
    def isa(k, names):
        while k is not None:
            if kinds[k] in names: return kinds[k]
            k = par[k]
        return None
    fid = {r[0]: r[1] for r in c.execute("select FieldID, Name from KindFieldDef")}
    out = []
    for oid, name, des, k, so in c.execute("select ObjectID, Name, coalesce(Designator,''), KindID, Sort from PartObject where PartID=? order by Sort, ObjectID", (p,)).fetchall():
        kk = isa(k, ("Coil", "Pole", "Contact"))
        if not kk: continue
        form = delay = ""; secs = 0.0
        if kk == "Contact":
            delay = "none"
            for f, vt, vn in c.execute("select FieldID, ValueText, ValueNum from ObjectValue where ObjectID=?", (oid,)):
                if fid[f] == "Form": form = vt or ""
                if fid[f] == "Delay": delay = vt or "none"
                if fid[f] == "DelaySecs": secs = vn or 0.0
        out.append((oid, kk, name, des, form, delay, secs))
    return out
def sw_rows(o):
    r = []
    for l in o:
        if l.startswith("PESW ") and "|" in l:
            kind, name, des, form, delay, secs, oid = l[5:].split("|")
            r.append((int(oid), kind, name, des, form, delay, float(secs)))
    return r
def snap(p):
    c = db(p); r = tuple(c.execute("select * from %s order by 1,2" % t).fetchall() for t in ("PartObject", "ObjectValue", "KindFieldDef")) + (c.execute("select PartID,Revision from Part order by PartID").fetchall(),)
    c.close(); return r
OPEN = lambda f: ["peopen " + f, "pe page objects", "pe obj part|" + CT]
f = mk("a.TCParts"); c = db(f); ct = pid(c, CT); am = pid(c, AM)
names = {r[0] for r in c.execute("select Name from KindFieldDef where KindID=(select KindID from ObjectKind where Name='Contact')")}
check("a new parts file gives the Contact kind Delay and DelaySecs", {"Delay", "DelaySecs", "Form"} <= names, names)
form_enum, = c.execute("select EnumValues from KindFieldDef where Name='Form' and KindID=(select KindID from ObjectKind where Name='Contact')").fetchone()
delay_enum, = c.execute("select EnumValues from KindFieldDef where Name='Delay' and KindID=(select KindID from ObjectKind where Name='Contact')").fetchone()
want0 = model(c, ct); rev0, = c.execute("select Revision from Part where PartID=?", (ct,)).fetchone(); c.close()
o = run(OPEN(f) + ["pe sw dlg", "pe sw rows"])
d = [l for l in o if l.startswith("PESWDLG")]
check("the dialog lists the file's Form and Delay values, one row per coil / pole / contact", d and ("forms=" + form_enum.replace(",", "/")) in d[0] and ("delays=" + delay_enum.replace(",", "/")) in d[0] and ("rows=%d" % len(want0)) in d[0], (d, want0[:2]))
check("with nothing chosen Add Pole is on, Add Contact / Change / Delete off; the first row (a coil or pole) is then chosen", "addpole=1 addcontact=0 change=0 delete=0" in d[0] if d else False, d)
check("the rows equal the part's coil, poles and contacts with their values", sw_rows(o) == want0, (sw_rows(o)[:3], want0[:3]))
# ---- add a pole
s0 = snap(f)
o = run(OPEN(f) + ["pe sw addpole|NC|on-delay|5", "pe sw rows"])
c = db(f); got = model(c, ct); rev1, = c.execute("select Revision from Part where PartID=?", (ct,)).fetchone()
pn = c.execute("select v.ValueNum from ObjectValue v join PartObject o using(ObjectID) where o.Name='Pole 4'").fetchone()
cont = [r for r in got if r[1] == "Contact" and r[0] not in {x[0] for x in want0}]
pole = [r for r in got if r[2] == "Pole 4"]
inside = c.execute("select ParentObjectID from PartObject where ObjectID=?", (cont[0][0],)).fetchone()[0] if cont else None
check("Add Pole: a Pole 4 with PoleNo 4 and one new contact of the form and delay chosen", len(pole) == 1 and pn and pn[0] == 4 and len(cont) == 1 and cont[0][4:] == ("NC", "on-delay", 5.0), (pole, pn, cont))
check("... the contact is inside the new pole and the part's revision went up", cont and inside == pole[0][0] and rev1 != rev0 and sw_rows(o)[-2:] == [(r[0], *r[1:]) for r in got][-2:], (inside, rev0, rev1))
check("... the other rows are unchanged", [r for r in got if r[0] in {x[0] for x in want0}] == want0)
check("the answer is ok", "PESW addpole ok" in o, [l for l in o if l.startswith("PESW add")])
new_pole, new_contact = pole[0][0], cont[0][0]; cname = cont[0][2]; c.close()
# ---- add a contact in the pole, by the pole's name and by a contact's name
o = run(OPEN(f) + ["pe sw addcontact|Pole 4|CO|none|", "pe sw addcontact|%s|NO|off-delay|1.5" % cname])
c = db(f); got = model(c, ct); old = {x[0] for x in want0} | {new_pole, new_contact}
extra = [r for r in got if r[0] not in old]
parents = [c.execute("select ParentObjectID from PartObject where ObjectID=?", (r[0],)).fetchone()[0] for r in extra]
check("Add Contact: two more contacts, both inside Pole 4 (chosen by the pole, and by a contact in it)", len(extra) == 2 and parents == [new_pole, new_pole], (extra, parents))
check("... with their own form and delay", [r[4:] for r in extra] == [("CO", "none", 0.0), ("NO", "off-delay", 1.5)], extra)
c.close()
# ---- change
o = run(OPEN(f) + ["pe sw set|%s|13-14|CO|off-delay|2.5" % cname])
c = db(f); got = {r[2]: r for r in model(c, ct)}; c.close()
check("Change: designator, form, delay and seconds stored", got[cname][3:] == ("13-14", "CO", "off-delay", 2.5), got[cname])
s1 = snap(f)
o = run(OPEN(f) + ["pe sw set|%s|13-14|CO|none|" % cname])
c = db(f); got = {r[2]: r for r in model(c, ct)}
left = c.execute("select count(*) from ObjectValue v join KindFieldDef k using(FieldID) where v.ObjectID=? and k.Name in ('Delay','DelaySecs')", (new_contact,)).fetchone()[0]; c.close()
check("none removes the delay and its seconds", got[cname][4:] == ("CO", "none", 0.0) and left == 0, (got[cname], left))
# ---- refused
s2 = snap(f)
o = run(OPEN(f) + ["pe sw set|%s|13-14|CO|on-delay|" % cname])
check("a delay without a time is refused and the file is unchanged", any(l.startswith("PESW set error") and "delay time" in l for l in o) and snap(f) == s2, [l for l in o if l.startswith("PESW set")])
o = run(OPEN(f) + ["pe sw set|%s|13-14|CO|on-delay|abc" % cname])
check("a time that is not a number is refused and the file is unchanged", any(l.startswith("PESW set error") and "abc" in l for l in o) and snap(f) == s2, [l for l in o if l.startswith("PESW set")])
am_rows = run(["peopen " + f, "pe page objects", "pe obj part|" + AM, "pe sw addpole|NO|none|", "pe sw rows"])
check("a part whose class has no poles refuses Add Pole and nothing changes", any(l.startswith("PESW addpole error") for l in am_rows) and snap(f) == s2, [l for l in am_rows if l.startswith("PESW")][:2])
# ---- delete
o = run(OPEN(f) + ["pe sw del|Pole 4"])
c = db(f); gone = c.execute("select count(*) from PartObject where PartID=? and (Name='Pole 4' or ParentObjectID=?)", (ct, new_pole)).fetchone()[0]; got = model(c, ct); c.close()
check("Delete takes the pole with the contacts inside it", gone == 0 and got == want0, (gone, len(got), len(want0)))
# a symbol shows a contact: it cannot be deleted
c = db(f); first_contact = [r for r in model(c, ct) if r[1] == "Contact"][0]
c.execute("update Symbol set ShowsObject=? where PartID=?", (first_contact[0], ct)); c.commit(); c.close(); s3 = snap(f)
o = run(OPEN(f) + ["pe sw del|%s" % first_contact[2]])
check("a contact a symbol shows can not be deleted", any(l.startswith("PESW del error") for l in o) and snap(f) == s3, [l for l in o if l.startswith("PESW del")])
# ---- an older file without the delay fields
g = mk("b.TCParts"); c = db(g)
c.execute("delete from KindFieldDef where Name in ('Delay','DelaySecs')"); c.commit(); c.close()
o = run(OPEN(g) + ["pe sw addpole|NO|on-delay|3"])
c = db(g); names = {r[0] for r in c.execute("select Name from KindFieldDef where KindID=(select KindID from ObjectKind where Name='Contact')")}
got = [r for r in model(c, pid(c, CT)) if r[1] == "Contact"][-1]; c.close()
check("an older file gets the Delay and DelaySecs fields when the dialog is used, and the pole is added", {"Delay", "DelaySecs"} <= names and got[4:] == ("NO", "on-delay", 3.0), (names, got))
if fails: print("poles and contacts: %d checks, %d failed" % (checks, len(fails))); sys.exit(1)
print("poles and contacts: %d checks, 0 failed" % checks)
