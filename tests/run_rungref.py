#!/usr/bin/env python3
"""Rung references (Step 4 of docs/parts_review_and_roadmap.md): right click a coil or a contact > Add Rung Reference puts a cross reference text (XREF mode 2) under it. A coil reads like
"5 NO  7 NC" (the rung and the form of every contact with the same reference, in rung order), a contact the rung of its coil. Oracles: the program's own rung lookup at a point (rungat, a
different routine from the one that decides a symbol's rung), the contact forms read from the parts file with sqlite3, the saved .dsn text. Cases: the text of a coil and of a contact; a second
device (K2) is not mixed in; a rung chosen on a contact moves it in the text; a second Add gives no second text; undo takes it away; the .dsn has mode 2 and the coil's id; nothing selected is refused;
the Rung Reference item is in the symbol's pop-up menu.
Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, sys, re, shutil, sqlite3, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, "..", "docs"))
import parts_seed
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Insert contact checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
def build(name, contact_symbols=True):
    f = os.path.join(tmp, name); parts_seed.build(f).close(); c = sqlite3.connect(f)
    ct, = c.execute("select PartID from Part where Name like 'Contactor%'").fetchone(); other, = c.execute("select PartID from Part where PartID<>?", (ct,)).fetchone()
    ob = {nm: i for i, nm in c.execute("select ObjectID, Name from PartObject where PartID=?", (ct,))}
    form, = c.execute("select FieldID from KindFieldDef where Name='Form' and KindID=(select KindID from ObjectKind where Name='Contact')").fetchone()
    for nm, fm in (("1L1-1T1", "NO"), ("2L2-2T2", "NO"), ("3L3-3T3", "NC")):
        c.execute("insert or replace into ObjectValue(ObjectID, FieldID, ValueText) values (?,?,?)", (ob[nm], form, fm))
    c.execute("update Symbol set ShowsObject=? where PartID=?", (ob["A1/A2"], ct))
    coil_blob, = c.execute("select Drawing from Symbol where PartID=?", (ct,)).fetchone(); no_blob, = c.execute("select Drawing from Symbol where PartID=?", (other,)).fetchone()
    if contact_symbols:   # the NO template draws like the other part, the NC template like the contactor's coil symbol
        c.execute("insert into Symbol(PartID, Standard, Purpose, Name, Drawing, ShowsObject) values (?, 'IEC', 'schematic', 'NO template', ?, ?)", (ct, no_blob, ob["1L1-1T1"]))
        c.execute("insert into Symbol(PartID, Standard, Purpose, Name, Drawing, ShowsObject) values (?, 'IEC', 'schematic', 'NC template', ?, ?)", (ct, coil_blob, ob["3L3-3T3"]))
    idx = [r[0] for r in c.execute("select p.PartID from Part p join PartClass c using(ClassID) order by lower(c.Name), lower(p.Name)")].index(ct)
    c.commit(); c.close(); return f, idx, len(re.findall(rb"<PIN ", coil_blob)), len(re.findall(rb"<PIN ", no_blob))
f, idx, pins_coil, pins_no = build("a.TCParts")
dsn = os.path.join(tmp, "r.dsn")
place = ["newdoc A4", "pdbtab open " + f, "pdbplace %d 80 80 yes" % idx, "pdbplace %d 80 190 yes" % idx, "selidx 0", "setprop sym.ref K1", "selidx 1", "setprop sym.ref K2",
         "selidx 0", "insertcontact NO 150 60", "selidx 0", "insertcontact NO 150 120", "selidx 0", "insertcontact NC 150 180", "selidx 1", "insertcontact NO 150 120",
         "rungs", "setrungs 6 1 10.15 1"]
# objects: 0 coil K1, 1 coil K2, 2 K1's first NO, 3 K1's second NO, 4 K1's NC, 5 K2's NO, 6 the rung grid
o = run(place + ["pinsof", "objects"])
pins = {}
for l in o:
    if l.startswith("PIN "):
        q = l.split(); pins.setdefault(int(q[1]), []).append((float(q[3]) / 5, float(q[4]) / 5))
check("six symbols placed (two coils, K1's three contacts, K2's one)", "OBJ end 7" in o, [l for l in o if l.startswith("OBJ end")])
pts = {k: (sum(p[0] for p in v) / len(v), sum(p[1] for p in v) / len(v)) for k, v in pins.items()}
asks = ["rungat %.3f %.3f" % pts[k] for k in sorted(pts)]
o2 = run(place + asks)
rung = {}
for k, l in zip(sorted(pts), [l for l in o2 if l.startswith("RUNGAT")]):
    rung[k] = int(l.split("=")[1])
print("  rungs by symbol (0 coil K1, 1 coil K2, 2/3 NO, 4 NC, 5 K2's NO):", rung)
check("the symbols are on different rungs (so the order of the text can be told)", len({rung[2], rung[3], rung[4]}) == 3, rung)
K1 = sorted([(rung[2], "NO"), (rung[3], "NO"), (rung[4], "NC")])
want_coil = "  ".join("%d %s" % r for r in K1)
o = run(place + ["selidx 0", "rungref", "xrefs"])
rr = [l for l in o if l.startswith("RUNGREF")]; xr = [l for l in o if l.startswith("XREF")]
check("Add Rung Reference on K1's coil: added", rr == ["RUNGREF added"], rr)
check("the coil's text lists the rung and form of K1's contacts in rung order (not K2's)", len(xr) == 1 and xr[0].startswith('XREF "%s" mode=2' % want_coil), (xr, want_coil))
for k, form in ((2, "NO"), (4, "NC")):
    o = run(place + ["selidx %d" % k, "rungref", "xrefs"]); xr = [l for l in o if l.startswith("XREF")]
    check("a contact (%d) shows the rung of its coil, %d" % (k, rung[0]), len(xr) == 1 and xr[0].startswith('XREF "%d" mode=2' % rung[0]), xr)
o = run(place + ["selidx 1", "rungref", "xrefs"]); xr = [l for l in o if l.startswith("XREF")]
check("K2's coil lists only K2's contact", len(xr) == 1 and xr[0].startswith('XREF "%d NO" mode=2' % rung[5]), xr)
# placement: under the symbol, left aligned (the text's baseline is a line below the lowest pin)
o = run(place + ["selidx 0", "rungref", "xrefs", "pinsof"])
xr = [l for l in o if l.startswith("XREF")][0]; at = [float(v) for v in re.search(r"at=([-\d.]+),([-\d.]+)", xr).groups()]
cp = [(float(l.split()[3]) / 5, float(l.split()[4]) / 5) for l in o if l.startswith("PIN 0 ")]
check("the text is under the coil (below its lowest pin) and starts at the left of its box (a pin pitch or less left of the first pin)", at[1] > max(p[1] for p in cp) and abs(at[0] - min(p[0] for p in cp)) <= 12, (at, cp))
# a second Add, nothing selected, undo
o = run(place + ["selidx 0", "rungref", "selidx 0", "rungref", "objects", "selclear", "rungref"])
rr = [l for l in o if l.startswith("RUNGREF")]
check("a second Add gives no second text; nothing selected is refused", rr == ["RUNGREF added", "RUNGREF exists", "RUNGREF nosel"] and "OBJ end 8" in o, (rr, [l for l in o if l.startswith("OBJ end")]))
o = run(place + ["selidx 0", "rungref", "undo", "objects", "xrefs"])
check("undo takes the text away", "OBJ end 7" in o and not [l for l in o if l.startswith("XREF")], [l for l in o if l.startswith("OBJ end")])
# a rung chosen on a contact moves it in the text
o = run(place + ["selidx 0", "rungref", "selidx 3", "rung set 6", "xrefs"])
xr = [l for l in o if l.startswith("XREF")]
K1b = sorted([(rung[2], "NO"), (6, "NO"), (rung[4], "NC")])
check("choosing rung 6 for the second contact changes the coil's text", len(xr) == 1 and xr[0].startswith('XREF "%s" mode=2' % "  ".join("%d %s" % r for r in K1b)), (xr, K1b))
# saved
o = run(place + ["selidx 0", "rungref", "savedocas " + dsn])
t = open(dsn, encoding="utf-8", errors="replace").read()
coil_oid = re.search(r"<SYMBOL oid='(\d+)'", t)[1]
check("the .dsn has the XREF with mode 2 and the coil's object id as its target", re.search(r"<XREF [^>]*target='%s'[^>]*mode='2'|<XREF [^>]*mode='2'[^>]*target='%s'" % (coil_oid, coil_oid), t) is not None, re.findall(r"<XREF [^>]*>", t))
# the menu
o = run(place + ["ctxmenu 80 52"])
check("the symbol's pop-up menu has Add Rung Reference", any(" Add_Rung_Reference " in l for l in o if l.startswith("CTX ")), [l for l in o if l.startswith("CTX ")][:4])
o = run(place + ["selidx 0", "ctxmenu 80 52", "ctxclick Add_Rung_Reference", "xrefs"])
check("choosing it from the menu adds the text", len([l for l in o if l.startswith("XREF")]) == 1, [l for l in o if l.startswith("XREF")])
if fails: print("rung references: %d checks, %d failed" % (n[0], len(fails))); sys.exit(1)
print("rung references: %d checks, 0 failed" % n[0])
