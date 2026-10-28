#!/usr/bin/env python3
"""The parts database design (docs/parts_schema.sql, docs/parts_seed.py). Oracle: the class tree is read back through the inheritance views and compared with
a Python walk of the same tree made from the parent column only; the triggers must refuse values and children the class does not inherit. Needs only Python's sqlite3."""
import os, sys, sqlite3, struct, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, "..", "docs"))
import parts_seed
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:300])
c = parts_seed.build(os.path.join(tempfile.mkdtemp(), "t.TCParts"))
par = dict(c.execute("select ClassID,ParentID from PartClass").fetchall()); own = {}
for cid_, name in c.execute("select ClassID,Name from FieldDef"): pass
for cid_, name in c.execute("select ClassID,Name from FieldDef"): own.setdefault(cid_, set()).add(name)
def walk(x):
    out = set()
    while x is not None: out |= own.get(x, set()); x = par[x]
    return out
bad = [(nm, ) for cid_, nm in c.execute("select ClassID,Name from PartClass") if {r[0] for r in c.execute("select Name from ClassFields where ClassID=?", (cid_,))} != walk(cid_)]
check("every class has exactly its own and its ancestors' fields (view = independent walk)", not bad, bad)
am = c.execute("select ClassID from PartClass where Name='AnalogInputModule'").fetchone()[0]
fs = {r[0] for r in c.execute("select Name from ClassFields where ClassID=?", (am,))}
check("the analog input module has the fields of Part, ActivePart, ControlModule, IOModule and its own", {"WidthMm", "PowerW", "BackplaneCurrentmA", "ChannelCount", "ResolutionBits"} <= fs and "Poles" not in fs, sorted(fs))
check("a contactor does not inherit active-part fields", "PowerW" not in {r[0] for r in c.execute("select cf.Name from ClassFields cf join PartClass p using(ClassID) where p.Name='Contactor'")})
sk = {r[0] for r in c.execute("select k.Name from ClassKinds ck join ObjectKind k using(KindID) join PartClass p on p.ClassID=ck.ClassID where p.Name='AnalogInputModule'")}
check("child kinds are inherited and include sub-kinds (Terminal from Part, Channel and SensorIO from IOModule, Coil from ActiveObject)", {"Terminal", "Channel", "SensorIO", "PowerInput", "Coil", "Load"} <= sk and "Pole" not in sk, sorted(sk))
kf = {r[0] for r in c.execute("select f.Name from KindFields f join ObjectKind k using(KindID) where k.Name='SensorIO'")}
check("a SensorIO inherits Channel, PassiveObject and PartObject fields", {"Signal", "Direction", "WireMinMm2", "Label", "SensorSupplyV"} <= kf, kf)
def refuses(sql, a=()):
    try: c.execute(sql, a); return False
    except sqlite3.IntegrityError: return True
fpoles = c.execute("select FieldID from FieldDef where Name='Poles'").fetchone()[0]
pid = c.execute("select PartID from Part where Name like 'Analog input module%'").fetchone()[0]
check("a value of a field the class does not inherit is refused", refuses("insert into PartValue values (?,?,1,null)", (pid, fpoles)))
pole = c.execute("select KindID from ObjectKind where Name='Pole'").fetchone()[0]
check("a child kind the class does not allow is refused", refuses("insert into PartObject(PartID,KindID,Name) values (?,?,'x')", (pid, pole)))
check("the sample module has 4 channels with 2 terminals each and a rating each", c.execute("select count(*) from PartObject o join ObjectKind k using(KindID) where PartID=? and k.Name='Channel'", (pid,)).fetchone()[0] == 4
      and c.execute("select count(*) from PartObject where PartID=? and ParentObjectID is not null", (pid,)).fetchone()[0] == 8 and c.execute("select count(*) from Rating where PartID=?", (pid,)).fetchone()[0] == 4)
ct = c.execute("select PartID from Part where Name like 'Contactor%'").fetchone()[0]
check("the contactor's three contacts are each driven by its coil", c.execute("select count(*) from Link where PartID=? and Relation='driven_by' and ToObject=(select ObjectID from PartObject where PartID=? and Name='A1/A2')", (ct, ct)).fetchone()[0] == 3)
check("the file says it is not TinyCAD compatible and refuses to say otherwise", c.execute("select TinyCADCompatible from FormatInfo").fetchone()[0] == 0 and refuses("update FormatInfo set TinyCADCompatible=1"))
check("deleting a part removes its children, values, ratings and links", (c.execute("delete from Part where PartID=?", (ct,)), c.execute("select count(*) from PartObject where PartID=?", (ct,)).fetchone()[0], c.execute("select count(*) from Link where PartID=?", (ct,)).fetchone()[0])[1:] == (0, 0))
check("every part has its own GUID and a repeated one is refused", c.execute("select count(distinct UID) = count(*) and count(*) > 0 from Part").fetchone()[0] == 1 and all(len(r[0]) == 36 for r in c.execute("select UID from Part"))
      and refuses("insert into Part(UID,ClassID,Name) values ((select UID from Part limit 1),1,'x')") and refuses("insert into Product(UID,ClassID,Manufacturer,MPN) values ((select UID from Product limit 1),1,'m','x')"))
check("a library knows its own GUID and name", c.execute("select count(*), max(Name) from LibraryInfo").fetchone() == (1, "Sample parts"))
c = parts_seed.build(os.path.join(tempfile.mkdtemp(), "u.TCParts"))      # (a fresh file: the checks above deleted the sample contactor)
# ---- generic part / product: does the product fit?  Oracle: the verdict is worked out here from the raw rating rows and the stated rules
def value(r): return next(v for v in (r[2], r[1], r[0]) if v is not None)      # (Min, Typ, Max) -> Max, else Typ, else Min
def expect(prid, partid):
    bad = oversized = 0
    for rid, q, oid, cond in c.execute("select RatingID,Quantity,ObjectID,Condition from Rating where PartID=?", (partid,)).fetchall():
        need = value(c.execute("select Min,Typ,Max from Rating where RatingID=?", (rid,)).fetchone()); sense = c.execute("select Sense from RatingQuantity where Name=?", (q,)).fetchone()[0]
        oname = c.execute("select Name from PartObject where ObjectID=?", (oid,)).fetchone()[0] if oid else None
        kinds = set()
        if oid:
            k = c.execute("select KindID from PartObject where ObjectID=?", (oid,)).fetchone()[0]
            while k is not None: kinds.add(c.execute("select Name from ObjectKind where KindID=?", (k,)).fetchone()[0]); k = c.execute("select ParentID from ObjectKind where KindID=?", (k,)).fetchone()[0]
        have = None
        for mn, ty, mx, ap in c.execute("select Min,Typ,Max,AppliesTo from Rating where ProductID=? and Quantity=? and Condition is ?", (prid, q, cond)).fetchall():
            if (oid is None and ap is None) or (oid is not None and ap is not None and (ap == oname or (ap.startswith("kind:") and ap[5:] in kinds))): have = value((mn, ty, mx))
        if have is None or (sense == "match" and have != need) or (sense == "min" and have < need) or (sense == "max" and have > need): bad += 1
        elif have != need: oversized += 1
    return "does_not_fit" if bad else "fits_oversized" if oversized else "fits"
verdicts = {(m, n): v for m, n, v in c.execute("select p.MPN, s.Name, f.Verdict from ProductFitSummary f join Product p using(ProductID) join Part s using(PartID)")}
allok = True
for prid, mpn in c.execute("select ProductID, MPN from Product").fetchall():
    for partid, nm in c.execute("select p.PartID, p.Name from Part p join Product x on x.ClassID=p.ClassID where x.ProductID=?", (prid,)).fetchall():
        allok &= verdicts[(mpn, nm)] == expect(prid, partid)
check("every verdict of ProductFitSummary equals the one worked out from the raw rating rows", allok and len(verdicts) == 5, verdicts)
V = lambda m: next(v for (mp, nm), v in verdicts.items() if mp == m)
check("the exact product fits, the bigger one fits (oversized is allowed), the smaller one and the wrong coil do not", V("CTR-32-24DC") == "fits_oversized" and V("OC-18-24DC") == "does_not_fit" and V("OC-25-110AC") == "does_not_fit" and V("P2-04AD-1") == "fits")
check("a smaller product is undersized on each of its three contacts and its motor power; a wrong coil voltage is a mismatch (not undersized)",
      c.execute("select count(*) from ProductFit where ProductID=(select ProductID from Product where MPN='OC-18-24DC') and Status='undersized'").fetchone()[0] == 4
      and c.execute("select Status from ProductFit where ProductID=(select ProductID from Product where MPN='OC-25-110AC') and Quantity='coil_voltage'").fetchone()[0] == "mismatch")
check("a lower coil power than asked counts as better (max-sense), not undersized", c.execute("select Status from ProductFit where ProductID=(select ProductID from Product where MPN='CTR-25-24DC') and Quantity='coil_power'").fetchone()[0] == "oversized")
pc = c.execute("select PartID from Part where Name like 'Contactor%'").fetchone()[0]
c.execute("insert into Product(UID,ClassID,Manufacturer,MPN) select 'bare', ClassID, 'X', 'NO-RATINGS' from Part where PartID=?", (pc,))
check("a product with no ratings is reported missing on every requirement, and does not fit", c.execute("select Verdict, Missing from ProductFitSummary where ProductID=(select ProductID from Product where MPN='NO-RATINGS') and PartID=?", (pc,)).fetchone() == ("does_not_fit", 6))
check("a rating needs a known quantity in its unit, and is a part's or a product's, not both", refuses("insert into Rating(PartID,Quantity,Max,Unit) values (?,'nosuch',1,'A')", (pc,)) and refuses("insert into Rating(PartID,Quantity,Max,Unit) values (?,'current',1,'mA')", (pc,))
      and refuses("insert into Rating(PartID,ProductID,Quantity,Max,Unit) values (?,1,'current',1,'A')", (pc,)) and refuses("insert into Rating(PartID,AppliesTo,Quantity,Max,Unit) values (?,'x','current',1,'A')", (pc,)))
check("deleting a product removes its ratings, and its generic part stays", (c.execute("delete from Product where MPN='OC-18-24DC'"), c.execute("select count(*) from Rating where ProductID is not null and Quantity='current' and Max=18").fetchone()[0], c.execute("select count(*) from Part where PartID=?", (pc,)).fetchone()[0])[1:] == (0, 1))
gl = c.execute("select Size, Png from PartGlyph where PartID=(select PartID from Part where Name like 'Contactor%') order by Size").fetchall()
def png_size(b): return struct.unpack(">II", b[16:24]) if b[:8] == b"\x89PNG\r\n\x1a\n" else None
check("a part has glyphs in several sizes, each a real PNG of the size it is filed under", [g[0] for g in gl] == [24, 48] and all(png_size(b) == (s, s) for s, b in gl), [(s, png_size(b)) for s, b in gl])
check("a second glyph of the same size for a part is refused, and deleting the part removes its glyphs", refuses("insert into PartGlyph values (?,24,x'00')", (pc,)) and (c.execute("delete from Part where PartID=?", (pc,)), c.execute("select count(*) from PartGlyph where PartID=?", (pc,)).fetchone()[0])[1] == 0)
print("%d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
