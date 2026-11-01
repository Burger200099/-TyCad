#!/usr/bin/env python3
"""Right click on a placed part symbol: the Objects menu (every placeable object of the part with [Page n, line n] or [unused]; virtual contacts and the pole made only of them are
left out; choosing a drawn one selects it, an unused one is put on the pointer) and Add Symbol Rung Text (a linked text follows the pointer and is put down by a click).  Also the
Form virtual of a contact in the parts library (PlaceableObjects, UnshownObjects).  Needs xvfb-run and the built program."""
import os, re, sys, shutil, subprocess, tempfile, sqlite3
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("part ribbon checks skipped: need xvfb-run and the built program"); sys.exit(0)
sys.path.insert(0, os.path.join(HERE, "..", "docs")); import parts_seed
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name); print("  FAIL", name, str(detail)[:600])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
f = os.path.join(tmp, "p.TCParts"); parts_seed.build(f).close()
c = sqlite3.connect(f)
pid = c.execute("select PartID from Part where Name like 'Contactor%'").fetchone()[0]
objs = {r[1]: r[0] for r in c.execute("select ObjectID, Name from PartObject where PartID = ?", (pid,))}
coil, c1, c2 = objs["A1/A2"], objs["1L1-1T1"], objs["2L2-2T2"]
sid, drawing = c.execute("select SymbolID, Drawing from Symbol where PartID = ?", (pid,)).fetchone()
c.execute("update Symbol set ShowsObject = ? where SymbolID = ?", (coil, sid))                      # the default symbol draws the coil
c.execute("insert into Symbol(PartID, Standard, Purpose, Name, Drawing, ShowsObject) values (?, 'IEC', 'schematic', 'Main contact', ?, ?)", (pid, drawing, c1))
c.execute("insert into Symbol(PartID, Standard, Purpose, Name, Drawing, ShowsObject) values (?, 'IEC', 'schematic', 'Second contact', ?, ?)", (pid, drawing, c2))
c.commit(); c.close()
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env)
    return r.stdout.splitlines()
def state(out, mk):
    i = out.index(mk); l = [x for x in out[i - 3:i] if x.startswith("PARTRIBBON ") and not x.startswith("PARTRIBBON press")][-1]
    m = re.match(r"PARTRIBBON visible=(\d) title=\[(.*?)\] object=\[(.*?)\] button=\[(.*?)\] enabled=(\d) index=(-?\d+) glyph=(\d) items=\[(.*)\]$", l)
    return dict(zip(("visible", "title", "object", "button", "enabled", "index", "glyph", "items"), m.groups()))

c = sqlite3.connect(f)
fid = c.execute("select FieldID from KindFieldDef where Name = 'Form' and KindID = (select KindID from ObjectKind where Name = 'Contact')").fetchone()[0]
c3 = objs["3L3-3T3"]
c.execute("insert or replace into ObjectValue(ObjectID, FieldID, ValueText) values (?, ?, 'virtual')", (c3, fid))
pf = c.execute("insert into KindFieldDef(KindID, Name, Type, EnumValues, Required) select KindID, 'Form', 'enum', 'standard,virtual', 0 from ObjectKind where Name = 'Pole'").lastrowid
c.execute("insert or replace into ObjectValue(ObjectID, FieldID, ValueText) values (?, ?, 'virtual')", (objs["Pole 3"], pf))
c.commit(); c.close()
out = run(["newdoc A4", "registerframe x all", "pdbtab open " + f, "pdbplace 1 80 80 yes", "tool select", "ctxmenu 80 80", "echo CTX0",
           "ctxclick Objects/1L1-1T1_(NO)___[unused]", "partribbon", "clickmm 120 80", "tool select", "ctxmenu 80 80", "echo CTX1",
           "ctxclick Add_Symbol_Rung_Text", "clickmm 100 120", "objects", "echo OBJ"])
def objs_of(L):
    r = []
    for l in L:
        if l.startswith("CTX 1 Bring_to_Front"): break
        if l.startswith("CTX 1 "): r.append(l)
    return r
ctx0 = objs_of(out[:out.index("CTX0")])
check("Objects lists the coil, two poles and two contacts (the virtual contact and its pole are left out)", len(ctx0) == 5, ctx0)
check("the coil that is drawn says where, the others [unused]", "[Page_1" in ctx0[0] and all("[unused]" in l for l in ctx0[1:]), ctx0)
check("no virtual contact or pole 3 is listed", not any("3L3" in l or "Pole 3" in l for l in ctx0), ctx0)
i1 = out.index("CTX1")
ctx1 = objs_of(out[out.index("CTX0"):i1])
check("after a contact is put down it says [Page 1", any("1L1-1T1" in l and "[Page_1" in l for l in ctx1), ctx1)
click = [l for l in out if l.startswith("CTXCLICK Objects")]
check("choosing an unused contact is accepted", click and "ok=1" in click[0], click)
objsl = [l for l in out[:out.index("OBJ")] if l.startswith("OBJ T")]
check("Add Symbol Rung Text puts a linked text down", any("TDrawRefText" in l for l in objsl), objsl)
rc = [l for l in out if l.startswith("CTXCLICK Add_Symbol_Rung_Text")]
check("the menu command was found", rc and "ok=1" in rc[0], rc)
# the library: virtual objects are not offered to a symbol as what it shows
pname = sqlite3.connect(f).execute("select Name from Part where PartID = ?", (pid,)).fetchone()[0]
o = run(["peopen " + f, "pe page symbols", "pe sym part|" + pname, "pe sym dlg|0|newshows"])
D = [l for l in o if l.startswith("PEDLG")]
check("Shows (New...) does not offer the virtual contact or the pole made only of it", len(D) == 1 and "3L3-3T3" not in D[0] and "Pole 3" not in D[0] and "Pole 2" in D[0], D)
print("part objects virtual: %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
