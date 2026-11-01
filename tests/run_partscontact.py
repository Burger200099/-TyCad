#!/usr/bin/env python3
"""Insert Contact of Selected Coil (Step 2 of docs/parts_review_and_roadmap.md). Oracles: Python's sqlite3 on the parts file (the contacts of the part, their forms, the symbols)
and the text of the saved .dsn (the <PART object= objectkind= form=> and <REF> of every symbol; the pins of each placed symbol come from the symbol drawn).
Cases: the coil is placed and named K1; NO contacts are taken in the part's order, a NC one when asked for NC, each with the reference K1 and its own contact in the part data;
when none of the form is left nothing is placed and the status says so; 'any' takes whatever is free; the NO template symbol and the NC template symbol are the ones used;
nothing selected, a library that is not the part's, and a part without a contact symbol are refused with nothing placed.
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
check("the two template drawings have different pin counts (so the choice of symbol can be told)", pins_coil != pins_no and min(pins_coil, pins_no) > 0, (pins_coil, pins_no))
dsn = os.path.join(tmp, "k.dsn"); csvf = os.path.join(tmp, "k.csv")
cmds = ["newdoc A4", "pdbtab open " + f, "pdbplace %d 40 40 yes" % idx, "selidx 0", "setprop sym.ref K1",
        "selclear", "insertcontact NO 100 40", "pinsof",
        "selidx 0", "insertcontact NO 100 60",
        "selidx 0", "insertcontact NO 100 80",
        "selidx 0", "insertcontact NC 100 100", "pinsof",
        "selidx 0", "insertcontact NO 100 120",
        "selidx 0", "insertcontact NC 100 120",
        "selidx 0", "insertcontact any 100 120",
        "objects", "savedocas " + dsn, "symdata " + csvf]
o = run(cmds)
ic = [l for l in o if l.startswith("INSERTCONTACT")]
check("nothing selected is refused; then NO, NO, the NC one (when NC is asked for), then no NO / NC / any left",
      ic == ["INSERTCONTACT nosel ", "INSERTCONTACT placed 1L1-1T1", "INSERTCONTACT placed 2L2-2T2", "INSERTCONTACT placed 3L3-3T3", "INSERTCONTACT none ", "INSERTCONTACT none ", "INSERTCONTACT none "], ic)
check("nothing more was placed than the coil and the three contacts", "OBJ end 4" in o, [l for l in o if l.startswith("OBJ end")])
txt = open(dsn, encoding="utf-8", errors="replace").read() if os.path.exists(dsn) else ""
syms = re.findall(r"<PART [^>]*>", txt); refs = re.findall(r"<REF[^>]*>([^<]*)</REF>", txt)
want = [("A1/A2", "Coil", None), ("1L1-1T1", "Contact", "NO"), ("2L2-2T2", "Contact", "NO"), ("3L3-3T3", "Contact", "NC")]
got = [(re.search(r"object='([^']*)'", s).group(1), re.search(r"objectkind='([^']*)'", s).group(1), (re.search(r"form='([^']*)'", s) or [None, None])[1]) for s in syms if "object=" in s]
check("the .dsn has the coil and the three contacts, each with its own contact and form", sorted(got, key=str) == sorted(want, key=str), (got, syms))
import csv
rows = list(csv.reader(open(csvf, encoding="utf-8", errors="replace"))) if os.path.exists(csvf) else []
check("all four placed symbols carry the reference K1 (the symbol data export is the oracle)", len(rows) == 5 and [r[rows[0].index("Reference")] if "Reference" in rows[0] else r[0] for r in rows[1:]].count("K1") == 4, rows[:2])
# pins per placed object in the last listing (objects 0 coil, 1 and 2 the NO contacts, 3 the NC contact)
P = [l for l in o if l.startswith("PIN ")]; last = max(i for i, l in enumerate(P) if l.startswith("PIN 0 0 ")); P = P[last:]
per = [len([l for l in P if l.startswith("PIN %d " % k)]) for k in range(4)]
check("the NO contacts have the NO template's pins and the NC contact the NC template's", per == [pins_coil, pins_no, pins_no, pins_coil], (per, pins_coil, pins_no))
# two devices of the same part are counted apart (K1 and K2 each start at the first contact)
o = run(["newdoc A4", "pdbtab open " + f, "pdbplace %d 40 40 yes" % idx, "pdbplace %d 40 140 yes" % idx, "selidx 0", "setprop sym.ref K1", "selidx 1", "setprop sym.ref K2",
         "selidx 0", "insertcontact NO 100 40", "selidx 1", "insertcontact NO 100 140", "selidx 0", "insertcontact NO 100 80"])
ic = [l for l in o if l.startswith("INSERTCONTACT")]
check("K1 and K2 of the same part each get their own first contact; K1's next is its second", ic == ["INSERTCONTACT placed 1L1-1T1", "INSERTCONTACT placed 1L1-1T1", "INSERTCONTACT placed 2L2-2T2"], ic)
# a library that is not the part's
g, *_ = build("b.TCParts")
o = run(["newdoc A4", "pdbtab open " + f, "pdbplace %d 40 40 yes" % idx, "pdbtab open " + g, "selidx 0", "insertcontact NO 100 40", "objects"])
ic = [l for l in o if l.startswith("INSERTCONTACT")]
check("another library is open: refused, nothing placed", ic == ["INSERTCONTACT nolibrary "] and "OBJ end 1" in o, (ic, o[-3:]))
h, idx2, *_ = build("c.TCParts", contact_symbols=False)
o = run(["newdoc A4", "pdbtab open " + h, "pdbplace %d 40 40 yes" % idx2, "selidx 0", "insertcontact NO 100 40", "objects"])
ic = [l for l in o if l.startswith("INSERTCONTACT")]
check("a part with no contact symbol: refused, nothing placed", ic == ["INSERTCONTACT nosymbol "] and "OBJ end 1" in o, (ic, o[-3:]))
print("%d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
