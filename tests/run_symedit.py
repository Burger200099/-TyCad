"""Checks of the symbol editor's data layer. Libraries are read back with Python's own sqlite3 and XML
parser, independently of the Pascal reader, so what the editor writes is verified as a file."""
import os, sys, shutil, sqlite3, subprocess, tempfile
import xml.etree.ElementTree as ET
BUILD = os.environ.get("TC_BUILD", "build"); EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
EXE = os.path.join(BUILD, "symedittest"); tmp = tempfile.mkdtemp(); fails = []
def check(n, ok, d=""):
    if not ok: fails.append(n); print("  FAIL", n, d)
def run(*a):
    r = subprocess.run([EXE, *a], capture_output=True, text=True, env=dict(os.environ))
    if r.returncode != 0: raise SystemExit("symedittest failed: " + r.stderr[-300:])
    return r.stdout.split("\n")
def rows(path, sql, *args):
    c = sqlite3.connect(path); r = c.execute(sql, args).fetchall(); c.close(); return r
def blob(path, sid):
    t = rows(path, "select Data from Symbol where SymbolID=?", sid)[0][0]
    return t if isinstance(t, bytes) else t.encode("utf-8")
def pins(data):
    root = ET.fromstring(data); out = []
    for sheet in ([root] if root.tag == "TinyCAD" else root.findall("TinyCAD")):
        out.append([(p.get("number"), (p.text or ""), int(p.get("part")), int(p.get("direction")), int(p.get("which")), p.get("pos")) for p in sheet.findall("PIN")])
    return root.tag, out

lib = os.path.join(tmp, "new.TCLib")
out = run("build", lib); text = "\n".join(out)
ids = {l.split()[1]: int(l.split()[2]) for l in out if l.startswith("ID ")}
check("three symbols stored", "SETS 3" in text and len(ids) == 3, text)
check("the new library has the standard tables", sorted(r[0] for r in rows(lib, "select name from sqlite_master where type='table'")) == ["Attribute", "Name", "Symbol"])
check("a clean symbol has no issues", "VALID R_TEST 0" in text and "VALID QUAD_NAND 0" in text)
# ---- the plain symbol
n = rows(lib, "select Name, Reference, Description, ppp, ShowName, ShowRef, DefRotate, SymbolID from Name where Name='R_TEST'")[0]
check("R_TEST name row", n[:7] == ("R_TEST", "R?", "Test resistor", 1, 0, 1, 0) and n[7] == ids["R_TEST"], str(n))
tag, ps = pins(blob(lib, ids["R_TEST"]))
check("R_TEST drawing: one shared sheet with its two pins", tag == "TinyCAD" and len(ps) == 1 and len(ps[0]) == 2, str(ps))
check("pin positions are written in millimetres (internal units / 5)", ps[0][0][5] == "0.00000,0.00000" and ps[0][1][5] == "0.00000,20.00000", str(ps[0]))
check("pin directions and names", [(p[0], p[1], p[3]) for p in ps[0]] == [("1", "1", 0), ("2", "2", 1)])
# ---- the four part IC
q = rows(lib, "select Name, Reference, Description, ppp, SymbolID from Name where SymbolID=? order by NameID", ids["QUAD_NAND"])
check("QUAD_NAND and its alias share one drawing, with 4 parts per package", [(r[0], r[3]) for r in q] == [("QUAD_NAND", 4), ("74HC00", 4)], str(q))
tag, ps = pins(blob(lib, ids["QUAD_NAND"]))
check("QUAD_NAND: one drawing, 12 pins, three per part", tag == "TinyCAD" and len(ps[0]) == 12 and sorted(p[2] for p in ps[0]) == [0] * 3 + [1] * 3 + [2] * 3 + [3] * 3, str(ps))
check("the output pins have a dot (which = 1)", sorted(p[4] for p in ps[0]).count(1) == 4)
att = rows(lib, "select n.Name, a.AttName, a.AttValue, a.ShowAtt from Attribute a join Name n on n.NameID = a.NameID where n.SymbolID=? order by n.NameID", ids["QUAD_NAND"])
check("each name has its own Footprint field", att == [("QUAD_NAND", "Footprint", "DIP14", 1), ("74HC00", "Footprint", "SO14", 1)], str(att))
# ---- the heterogeneous op-amp
tag, ps = pins(blob(lib, ids["OPAMP2"]))
check("OPAMP2: a drawing per part (TinyCADSheets), three pins each", tag == "TinyCADSheets" and [len(x) for x in ps] == [3, 3] and [p[0] for p in ps[1]] == ["5", "6", "7"], str(ps))
check("OPAMP2 stored with 2 parts", rows(lib, "select ppp from Name where Name='OPAMP2'")[0][0] == 2)
# ---- reading back through the editor
o = "\n".join(run("reopen", lib, "QUAD_NAND"))
check("reopened QUAD_NAND: parts, pins per part, both names, both fields", "PARTS 4 hetero=0 sheets=1" in o and all(f"PINS part {i} = 3" in o for i in range(4)) and
      "NAME QUAD_NAND|U?|Quad 2-input NAND" in o and "NAME 74HC00|U?|Quad NAND (HC)" in o and "FIELD QUAD_NAND|Footprint|DIP14|1" in o and "FIELD 74HC00|Footprint|SO14|1" in o, o)
o = "\n".join(run("reopen", lib, "OPAMP2"))
check("reopened OPAMP2: two parts, two sheets, three pins each", "PARTS 2 hetero=1 sheets=2" in o and "PINS part 0 = 3" in o and "PINS part 1 = 3" in o, o)

# ---- editing an existing symbol
before = {r[0]: blob(lib, r[0]) for r in rows(lib, "select SymbolID from Symbol")}
out = run("edit", lib, "R_TEST"); text = "\n".join(out)
old, new = [int(x) for x in [l for l in out if l.startswith("IDS")][0].split()[1:3]]
check("saving an edited symbol gives it a new id and keeps the number of symbols", new != old and "sets=3" in text, text)
check("no orphaned drawing is left behind", len(rows(lib, "select SymbolID from Symbol")) == 3 and not rows(lib, "select SymbolID from Symbol where SymbolID=?", old))
names = rows(lib, "select Name, Description, SymbolID from Name where SymbolID=? order by NameID", new)
check("edited description and the new alias", names == [("R_TEST", "Edited description", new), ("R_TEST_ALT", "An alias", new)], str(names))
tag, ps = pins(blob(lib, new))
check("the new pin is in the saved drawing", len(ps[0]) == 3 and ps[0][2][0] == "99" and ps[0][2][1] == "EXTRA", str(ps))
others = {k: v for k, v in before.items() if k != old}
check("the other symbols' drawings are byte-for-byte unchanged", all(blob(lib, k) == v for k, v in others.items()) and len(others) == 2)
check("their names and fields are unchanged", len(rows(lib, "select * from Name where SymbolID in (?,?)", *others.keys())) == 3 and len(rows(lib, "select * from Attribute")) == 2)

# ---- fewer parts
out = run("parts", lib, "QUAD_NAND"); qid = int(out[0].split()[1])
tag, ps = pins(blob(lib, qid))
check("QUAD_NAND reduced to 2 parts: pins of parts 3 and 4 are gone, and ppp is updated",
      len(ps[0]) == 6 and sorted(p[2] for p in ps[0]) == [0] * 3 + [1] * 3 and {r[0] for r in rows(lib, "select ppp from Name where SymbolID=?", qid)} == {2}, str(ps))

# ---- copy into another library
dst = os.path.join(tmp, "copy.TCLib")
out = run("copyto", lib, "OPAMP2", dst)
check("copied into a new library", "sets=1" in "\n".join(out))
sid = rows(dst, "select SymbolID from Symbol")[0][0]
_, a = pins(blob(lib, rows(lib, "select SymbolID from Name where Name='OPAMP2'")[0][0])); _, b = pins(blob(dst, sid))
check("the copy has the same pins", a == b, f"{a} vs {b}")
check("and the same name row", rows(dst, "select Name, Reference, Description, ppp from Name")[0] == ("OPAMP2", "U?", "Dual op-amp", 2))
out = run("copyto", lib, "R_TEST", dst)
check("a second copy adds another symbol", "sets=2" in "\n".join(out) and len(rows(dst, "select * from Symbol")) == 2)

# ---- delete
out = run("delete", lib, "QUAD_NAND")
check("deleting removes the symbol, its names and its fields", "SETS 2" in "\n".join(out) and not rows(lib, "select * from Name where Name in ('QUAD_NAND','74HC00')")
      and not rows(lib, "select * from Attribute") and len(rows(lib, "select * from Symbol")) == 2)

# ---- editing a real library symbol keeps everything else intact
src = os.path.join(EXAMPLES, "libraries", "gen_passive.TCLib")
if os.path.exists(src):
    cp = os.path.join(tmp, "gp.TCLib"); shutil.copy(src, cp)
    nb = len(rows(cp, "select * from Symbol")); namesb = rows(cp, "select Name, Reference, Description from Name where Name <> 'R' order by Name")
    out = run("edit", cp, "R")
    check("real library: one symbol edited, no symbol gained or lost", len(rows(cp, "select * from Symbol")) == nb and "sets=" in "\n".join(out))
    check("real library: every other name is untouched", rows(cp, "select Name, Reference, Description from Name where Name not in ('R','R_ALT') order by Name") == namesb)
    check("real library: R has its alias", rows(cp, "select count(*) from Name where Name in ('R','R_ALT')")[0][0] == 2)


# ---- symbols made by the editor can be placed and connected like any library symbol
et = os.path.join(BUILD, "edittest")
if os.path.exists(et):
    lib2 = os.path.join(tmp, "place.TCLib"); run("build", lib2)
    def placed_pins(row):
        r = subprocess.run([et], input=f"SYM {lib2} {row} 800 600 0\nPINS\n", capture_output=True, text=True, env=dict(os.environ))
        return [tuple(float(x) for x in l.split()[1:3]) for l in r.stdout.split("\n") if l.startswith("PIN ")]
    # rows run over the names of the sets in storage order: R_TEST, QUAD_NAND, 74HC00, OPAMP2
    counts = [len(placed_pins(i)) for i in range(4)]
    check("placed symbols show the pins of their first part (2, 3, 3, 3)", counts == [2, 3, 3, 3], str(counts))
    rp = placed_pins(0)
    check("the two pins of R_TEST are 100 units apart, one above the other", len(rp) == 2 and abs(rp[0][0] - rp[1][0]) < 1e-6 and abs(abs(rp[0][1] - rp[1][1]) - 100) < 1e-6, str(rp))
    qp = placed_pins(1)
    check("the 4-part IC's first part has its A, B and Y pins (heights 0, 20 and 10 apart from the top)", len(qp) == 3 and sorted(round(p[1] - min(q[1] for q in qp), 3) for p in qp) == [0.0, 10.0, 20.0], str(qp))
    print("editor-made symbols place on a sheet with the right connection points")

# ---- the checks the editor makes
v = "\n".join(run("validate"))
def case(title): 
    a = v.index("CASE " + title + "\n") + len("CASE " + title + "\n"); b = v.find("CASE ", a); return [x.strip() for x in v[a:b if b > 0 else None].split("\n") if x.strip()]
check("a good symbol raises nothing", case("good") == [])
check("empty name is an error, empty reference a warning", case("empty name and reference") == ["0 Name 1 is empty", '1 The name "" has no reference prefix'])
check("duplicate pin numbers are reported", case("duplicate pin number") == ["1 Pin number 1 is used more than once"])
check("pins on top of each other are an error", case("pins on top of each other") == ["0 Pins 1 and 2 are on top of each other"])
check("a pin without a number", case("pin without a number") == ["1 A pin named A has no number"])
check("a pin off the grid", case("pin off the grid") == ["1 Pin 1 is not on the grid, so wires will not snap to it cleanly"])
check("a symbol with no pins", case("no pins") == ["1 The symbol has no pins"])
check("parts without pins", case("a part without pins") == ["1 Part 2 has no pins", "1 Part 3 has no pins"])
check("a name used twice", case("same name twice") == ['0 The name "DUPNAME" is used twice'])
check("the same power pin number in two parts is accepted", case("the same power pin number in two parts is fine") == [])
print("symbol editor: new / edit / parts / alias / field / copy / delete verified in the saved files; 10 validation cases")
print("\nSYMBOL EDITOR CHECKS PASSED" if not fails else f"\nSYMBOL EDITOR CHECKS FAILED: {fails}")
sys.exit(1 if fails else 0)
