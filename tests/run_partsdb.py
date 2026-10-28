#!/usr/bin/env python3
"""The Pascal reader of the parts database (src/UPartsDb.pas) through the script commands pdbopen / pdblist / pdbglyph / pdbratings / pdbproducts / pdbupgrade.
Oracle: Python's own sqlite3 on the same file (the sample file of docs/parts_seed.py): the library name and GUID, the order and fields of the parts, the icon chosen
for a wanted size (nearest, the larger on a tie) and its CRC, the ratings, and the products with their fit verdicts. Refusals (missing file, a TinyCAD .TCLib, a text
file, a file of a newer version) must leave the file byte for byte the same; the upgrade machinery is run with made-up steps (backup, history, rollback of a failing step).
Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic) and the example libraries (TC_EXAMPLES) for the TinyCAD file."""
import os, sys, shutil, sqlite3, subprocess, tempfile, hashlib, zlib
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, "..", "docs"))
import parts_seed
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic")); EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Parts database checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:400])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env)
    return r.stdout.splitlines()
sha = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
f = os.path.join(tmp, "sample.TCParts"); parts_seed.build(f).close(); h0 = sha(f)
db = sqlite3.connect(f)
parts = db.execute("select p.PartID, p.UID, p.Name, c.Name, coalesce(p.Description,'') from Part p join PartClass c using(ClassID) order by lower(c.Name), lower(p.Name)").fetchall()
S = ["pdbopen " + f, "pdblist"]
for i in range(len(parts)):
    S += ["pdbglyph %d %d" % (i, w) for w in (20, 24, 36, 48, 100, 1)] + ["pdbratings %d" % i, "pdbproducts %d" % i]
o = run(S)
li = db.execute("select Name, LibraryUID from LibraryInfo").fetchone()
op = [l for l in o if l.startswith("PARTSOPEN")]
check("the file opens, with the library's name, GUID, the schema version and the counts the database has", op == ["PARTSOPEN ok version=2 name=%s uid=%s parts=%d classes=%d" % (li[0], li[1], len(parts), db.execute("select count(*) from PartClass").fetchone()[0])], op)
got = [l[5:].split("|")[1:] for l in o if l.startswith("PART ") and not l.startswith("PART end")]
check("the parts come in the order class name then part name, with GUID, name, class and description", got == [[u, nm, cl, de] for _, u, nm, cl, de in parts], got)
check("opening a file at the current version does not change it (same bytes, no backup)", sha(f) == h0 and not os.path.exists(f + ".v1.bak"))
gl = [l for l in o if l.startswith("PARTGLYPH")]; ok = True; det = []
for i, (pid, *_r) in enumerate(parts):
    for j, w in enumerate((20, 24, 36, 48, 100, 1)):
        rows = db.execute("select Size, Png from PartGlyph where PartID=? order by abs(Size-?), Size desc limit 1", (pid, w)).fetchall()
        want = "PARTGLYPH size=%d bytes=%d crc=%x" % (rows[0][0], len(rows[0][1]), zlib.crc32(rows[0][1])) if rows else "PARTGLYPH size=0 bytes=0 crc=0"
        if gl[i * 6 + j] != want: ok = False; det.append((gl[i * 6 + j], want))
check("the icon for a wanted size is the nearest one (the larger on a tie), with the same bytes as stored", ok and len(gl) == len(parts) * 6, det[:3])
sizes = {l.split()[1] for l in gl}
check("both sizes are actually used by the wanted sizes (the check can fail)", sizes == {"size=24", "size=48"}, sizes)
rt = []; cur = None
for l in o:
    if l.startswith("RATING end"): rt.append(cur or []); cur = None
    elif l.startswith("RATING "): cur = (cur or []) + [l[7:]]
def fmt(v): return "-" if v is None else ("%g" % v)
okr = True
for i, (pid, *_r) in enumerate(parts):
    want = ["%s|%s|%s|%s|%s|%s|%s" % (on or "", q, fmt(mn), fmt(ty), fmt(mx), un, cd or "") for q, un, cd, on, mn, ty, mx in
            db.execute("select r.Quantity, r.Unit, r.Condition, o.Name, r.Min, r.Typ, r.Max from Rating r left join PartObject o on o.ObjectID=r.ObjectID where r.PartID=? order by o.Name is not null, o.Name, r.Quantity", (pid,))]
    okr &= sorted(rt[i]) == sorted(want) and len(want) > 0
check("the ratings of every part are the rows of the Rating table (object, quantity, min, typ, max, unit, condition)", okr and len(rt) == len(parts), rt[:1])
pr = []; cur = []
for l in o:
    if l.startswith("PRODUCT end"): pr.append(cur); cur = []
    elif l.startswith("PRODUCT "): cur.append(l[8:])
okp = True
for i, (pid, *_r) in enumerate(parts):
    want = ["%s|%s|%s|%d|%d|%d|%d" % r for r in db.execute("select p.Manufacturer, p.MPN, f.Verdict, f.Undersized, f.Missing, f.Mismatch, f.Oversized from ProductFitSummary f join Product p using(ProductID) where f.PartID=? order by f.Verdict='does_not_fit', lower(p.Manufacturer), lower(p.MPN)", (pid,))]
    okp &= pr[i] == want and len(want) > 0
check("the products are those of the part's class with the fit verdicts of the schema view, the ones that fit first", okp, pr)
ct = next(i for i, p in enumerate(parts) if p[2].startswith("Contactor"))
check("for the contactor the exact and the bigger product fit and the other two do not", [x.split("|")[2] for x in pr[ct]] == ["fits_oversized", "fits_oversized", "does_not_fit", "does_not_fit"], pr[ct])
# ---- refusals leave the file alone
newer = os.path.join(tmp, "newer.TCParts"); shutil.copy(f, newer); c = sqlite3.connect(newer); c.execute("update FormatInfo set SchemaVersion=9"); c.commit(); c.close(); hn = sha(newer)
txt = os.path.join(tmp, "x.TCParts"); open(txt, "w").write("not a database at all, just text, long enough to look like a file header....\n" * 4); ht = sha(txt)
tc = os.path.join(EX, "libraries", "gen_passive.TCLib"); tcl = os.path.join(tmp, "tc.TCLib")
have_tc = os.path.exists(tc)
if have_tc: shutil.copy(tc, tcl)
o = run(["pdbopen " + os.path.join(tmp, "missing.TCParts"), "pdbopen " + newer, "pdbopen " + txt] + (["pdbopen " + tcl] if have_tc else []) + ["pdblist"])
er = [l for l in o if l.startswith("PARTSOPEN")]
check("a missing file, a newer file, a text file and a TinyCAD library are each refused with a message", len(er) == (4 if have_tc else 3) and all(l.startswith("PARTSOPEN error") for l in er), er)
check("the message for the newer file says so, and for a TinyCAD library says it is not a TyCAD parts file", "newer" in er[1] and (not have_tc or "not a TyCAD parts file" in er[3]), er)
check("the refused files are untouched, and nothing is listed after a refusal", sha(newer) == hn and sha(txt) == ht and (not have_tc or sha(tcl) == hashlib.sha256(open(tc, "rb").read()).hexdigest()) and "PART end" in o and not any(l.startswith("PART 0") for l in o))
# ---- the upgrade machinery with made-up steps
f1 = os.path.join(tmp, "v1.TCParts"); shutil.copy(f, f1); x = sqlite3.connect(f1)   # a version 1 file (version 2 added Symbol.ShowsObject)
x.execute("alter table Symbol drop column ShowsObject"); x.execute("update FormatInfo set SchemaVersion=1"); x.execute("pragma user_version=1"); x.commit(); x.close(); h1 = sha(f1)
g = os.path.join(tmp, "up.TCParts"); shutil.copy(f1, g)
o = run(["pdbupgrade %s 3 ALTER_TABLE_Part_ADD_COLUMN_Gtin_TEXT; update_Product_set_Series='x'_where_Series_is_null;" % g])
c = sqlite3.connect(g)
check("an old file goes through both steps: version, columns, data, history, backup", o == ["PARTSUPGRADE 3"] and "Gtin" in [r[1] for r in c.execute("pragma table_info(Part)")]
      and c.execute("select SchemaVersion from FormatInfo").fetchone()[0] == 3 and c.execute("pragma user_version").fetchone()[0] == 3
      and c.execute("select FromVersion,ToVersion from SchemaHistory order by 1").fetchall() == [(1, 2), (2, 3)] and c.execute("select count(*) from Product where Series is null").fetchone()[0] == 0
      and os.path.exists(g + ".v1.bak") and sha(g + ".v1.bak") == h1, o)
b = os.path.join(tmp, "bad.TCParts"); shutil.copy(f1, b)
o = run(["pdbupgrade %s 3 ALTER_TABLE_Part_ADD_COLUMN_Ok1_TEXT; ALTER_TABLE_NoSuchTable_ADD_COLUMN_x_TEXT;" % b])
c = sqlite3.connect(b)
check("a failing step is undone and reported, the step before it stays", len(o) == 1 and o[0].startswith("PARTSUPGRADE error") and c.execute("select SchemaVersion from FormatInfo").fetchone()[0] == 2
      and "Ok1" in [r[1] for r in c.execute("pragma table_info(Part)")] and c.execute("select count(*) from SchemaHistory").fetchone()[0] == 1, o)
d = os.path.join(tmp, "m.TCParts"); shutil.copy(f1, d); hd = sha(d)
o = run(["pdbupgrade %s 4 ALTER_TABLE_Part_ADD_COLUMN_A_TEXT;" % d])
check("a missing step is refused before anything is written (no backup either)", o and o[0].startswith("PARTSUPGRADE error") and sha(d) == hd and not os.path.exists(d + ".v1.bak"), o)
print("%d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
