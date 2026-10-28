#!/usr/bin/env python3
"""What a part symbol shows of its device (Step 1 of docs/parts_review_and_roadmap.md). Oracles: Python's sqlite3 on the parts file (Symbol.ShowsObject, Revision, the version and
columns of an upgraded file) and the text of the saved .dsn (<PART object= objectkind= form=>). Cases: a symbol is set to show a pole / the coil / a contact (with its Form), a
terminal and an object of another part are refused, 0 clears it; a placed symbol keeps it in the .dsn and loads it back; a symbol that shows nothing saves no object;
deleting a shown object is refused; a duplicate of the part shows the copy of the object; a version 1 file is upgraded (column added, backup kept, old data unchanged).
Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, sys, re, shutil, sqlite3, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, "..", "docs"))
import parts_seed
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Symbol shows checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:500])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    return subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env).stdout.splitlines()
def fresh(name):
    f = os.path.join(tmp, name); parts_seed.build(f).close(); return f
def sc(f, sql, *a):
    c = sqlite3.connect(f); r = c.execute(sql, a).fetchall(); c.commit(); c.close(); return r
f = fresh("a.TCParts")
CT, = sc(f, "select Name from Part where Name like 'Contactor%'")[0]; ct, = sc(f, "select PartID from Part where Name=?", CT)[0]
other, = sc(f, "select PartID from Part where PartID<>?", ct)[0]
obj = {nm: i for i, nm in sc(f, "select ObjectID, Name from PartObject where PartID=?", ct)}
index = [r[0] for r in sc(f, "select p.PartID from Part p join PartClass c using(ClassID) order by lower(c.Name), lower(p.Name)")].index(ct)
sym, = sc(f, "select SymbolID from Symbol where PartID=?", ct)[0]
foreign, = sc(f, "select ObjectID from PartObject where PartID=? limit 1", other)[0]
form, = sc(f, "select FieldID from KindFieldDef where Name='Form' and KindID=(select KindID from ObjectKind where Name='Contact')")[0]
sc(f, "insert or replace into ObjectValue(ObjectID, FieldID, ValueText) values (?,?,'NO')", obj["1L1-1T1"], form)
check("the sample has a contactor with a coil, poles and a contact (so the checks can fail)", all(k in obj for k in ("A1/A2", "Pole 2", "1L1-1T1", "1L1")), obj)
rev0, = sc(f, "select Revision from Part where PartID=?", ct)[0]
def shows(): return sc(f, "select ShowsObject from Symbol where SymbolID=?", sym)[0][0]
def lines(o): return [l for l in o if l.startswith("PE sym shows")]
base = ["peopen " + f, "pe page symbols", "pe sym part|" + CT, "pe sym select|0"]
check("a new file has no symbol showing anything", shows() is None)
o = run(base + ["pe sym shows|0|%d" % obj["Pole 2"]])
check("set to Pole 2: accepted, stored", lines(o) == ["PE sym shows ok"] and shows() == obj["Pole 2"], (lines(o), shows()))
check("the part's revision went up", sc(f, "select Revision from Part where PartID=?", ct)[0][0] != rev0)
o = run(base + ["pe sym shows|0|%d" % obj["1L1"]])
check("a terminal is refused and nothing changes", lines(o) == ["PE sym shows error A symbol can only show a coil, a pole or a contact of its part."] and shows() == obj["Pole 2"], (lines(o), shows()))
o = run(base + ["pe sym shows|0|%d" % foreign])
check("an object of another part is refused", lines(o)[0].startswith("PE sym shows error") and shows() == obj["Pole 2"], (lines(o), shows()))
def place(name, tag):
    d = os.path.join(tmp, name + ".dsn")
    o = run(["newdoc A4", "pdbtab open " + f, "pdbplace %d 80 60 yes" % index, "savedocas " + d])
    t = open(d, encoding="utf-8", errors="replace").read() if os.path.exists(d) else ""
    m = re.search(r"<PART [^>]*>", t); return (m.group(0) if m else ""), d, o
part, d, o = place("pole", "p")
check("placed: the .dsn names the object and its kind", " object='Pole 2'" in part and " objectkind='Pole'" in part and ' form=' not in part, part)
o = run(["open " + d, "savedocas " + os.path.join(tmp, "again.dsn")])
again = open(os.path.join(tmp, "again.dsn"), encoding="utf-8", errors="replace").read()
check("loaded and saved again it still names the object", " object='Pole 2'" in again and " objectkind='Pole'" in again, re.findall(r"<PART [^>]*>", again))
run(base + ["pe sym shows|0|%d" % obj["A1/A2"]])
part, *_ = place("coil", "c")
check("coil: object A1/A2 of kind Coil", " object='A1/A2'" in part and " objectkind='Coil'" in part, part)
run(base + ["pe sym shows|0|%d" % obj["1L1-1T1"]])
part, *_ = place("contact", "k")
check("contact: its Form is saved", " object='1L1-1T1'" in part and " objectkind='Contact'" in part and " form='NO'" in part, part)
c = sqlite3.connect(f)
try:
    c.execute("PRAGMA foreign_keys=ON"); c.execute("delete from PartObject where ObjectID=?", (obj["1L1-1T1"],)); oracle_blocks = False
except sqlite3.IntegrityError: oracle_blocks = True
c.close()
check("oracle: the database itself refuses to delete an object a symbol shows", oracle_blocks)
o = run(base[:3] + ["pe page objects", "pe obj part|" + CT, "pe obj del|1L1-1T1", "pe obj del|Pole 3"])
D = [l for l in o if l.startswith("PE obj del")]
check("deleting the object a symbol shows is refused with a reason; another object goes", D[0].startswith("PE obj del error A symbol, symbol pin") and D[1].startswith("PE obj del ok"), D)
check("the shown object is still there", sc(f, "select count(*) from PartObject where ObjectID=?", obj["1L1-1T1"])[0][0] == 1)
run(["peopen " + f, "pe dup %d|Contactor copy" % index])
cp = sc(f, "select o.PartID, o.Name from Symbol s join PartObject o on o.ObjectID = s.ShowsObject where s.PartID = (select PartID from Part where Name='Contactor copy')")
check("a duplicate of the part shows the copy of the object (same name, an object of the new part)", len(cp) == 1 and cp[0][1] == "1L1-1T1" and cp[0][0] != ct, cp)
run(base + ["pe sym shows|0|0"])
check("0 clears it", shows() is None)
part, *_ = place("whole", "w")
check("a symbol that shows nothing saves no object", part.startswith("<PART") and " object=" not in part and " objectkind=" not in part, part)
# upgrade of a version 1 file
g = fresh("old.TCParts"); c = sqlite3.connect(g)
c.execute("alter table Symbol drop column ShowsObject"); c.execute("update FormatInfo set SchemaVersion=1"); c.execute("pragma user_version=1"); c.commit()
names = c.execute("select Name from Part order by 1").fetchall(); c.close()
o = run(["newdoc A4", "pdbtab open " + g, "pdbplace %d 80 60 yes" % index, "objects"])
cols = [r[1] for r in sc(g, "pragma table_info(Symbol)")]
check("a version 1 file opens: column added, version 2 in both places, history and backup kept, data unchanged",
      cols[-1] == "ShowsObject" and sc(g, "select SchemaVersion from FormatInfo")[0][0] == 2 and sc(g, "pragma user_version")[0][0] == 2 and sc(g, "select FromVersion,ToVersion from SchemaHistory")[0] == (1, 2)
      and os.path.exists(g + ".v1.bak") and sc(g, "select Name from Part order by 1") == names and "PDBPLACE %d placed" % index in o, (cols, o[:6]))
print("%d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
