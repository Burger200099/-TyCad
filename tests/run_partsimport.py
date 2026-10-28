#!/usr/bin/env python3
"""Parts library editor, CSV import and export of products (Phase B12): `pe prod csvimport|<file>` / `csvexport|<file>` (what Parts > Import Products from CSV... / Export Products to CSV... do) on the
real program under Xvfb.
Oracles (independent of the program): the CSV files are written here with Python's csv module (quotes, commas, line breaks, BOM, other delimiters); the expected Product / Rating / PartProduct
rows are computed here from the lines and the seed library's rows, and the file is read with Python's sqlite3.
  - import: new products, rating lines merged under their product, an existing product's non-empty fields changed, an existing rating replaced, suggestions with the preferred flag, class taken
    from the part, comma as decimal mark, quoted fields holding comma / quote / line break, semicolon + BOM + CRLF text the same result
  - all or nothing: every kind of bad line stops the import with "Line n: reason" and the whole file (tables and revisions) is as before
  - export then import into a library without products gives the same products, ratings and suggestions
  - the menu items follow the Products page
Needs the built program and xvfb."""
import csv, io, os, shutil, sqlite3, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Import checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
HEAD = ["Manufacturer", "MPN", "Series", "Class", "Status", "Description", "Part", "Preferred", "Quantity", "Unit", "Condition", "AppliesTo", "Min", "Typ", "Max"]
def csvtext(rows, head=HEAD, delim=",", nl="\r\n"):
    b = io.StringIO(); w = csv.writer(b, delimiter=delim, lineterminator=nl); w.writerow(head)
    for r in rows: w.writerow(r + [""] * (len(head) - len(r)))
    return b.getvalue()
def put(name, text, bom=False):
    p = os.path.join(tmp, name); open(p, "wb").write((b"\xef\xbb\xbf" if bom else b"") + text.encode()); return p
def dump(p):
    c = db(p); r = {t: c.execute("select * from %s order by 1,2,3" % t).fetchall() for t in ("Product", "Rating", "PartProduct", "Part", "Symbol")}; c.close(); return r
def norm(p):
    """products, ratings and suggestions without ids, uids, revisions and times"""
    c = db(p)
    prod = c.execute("select p.Manufacturer,p.MPN,coalesce(p.Series,''),pc.Name,p.Status,coalesce(p.Description,'') from Product p join PartClass pc using(ClassID) order by 1,2").fetchall()
    rat = c.execute("select p.Manufacturer,p.MPN,coalesce(r.AppliesTo,''),r.Quantity,coalesce(r.Condition,''),r.Min,r.Typ,r.Max,r.Unit from Rating r join Product p using(ProductID) order by 1,2,3,4,5").fetchall()
    sug = c.execute("select p.Manufacturer,p.MPN,pa.Name,x.Preferred from PartProduct x join Product p using(ProductID) join Part pa using(PartID) order by 1,2,3").fetchall()
    c.close(); return prod, rat, sug
def res(o, what): return [l for l in o if l.startswith("PE prod %s" % what)]
f = mk("a.TCParts"); c = db(f)
CT = "Contactor 3P 25 A AC-3, 24 V DC coil"; AM = "Analog input module, 4 channels, current"
rev_before = dict((m, r) for m, r in c.execute("select MPN,Revision from Product").fetchall()); c.close()
# ---- a good import
rows = [
 ["Acme", "AC-1", "A-series", "Contactor", "", "25 A, \"tough\", with comma\nand a second line", CT, "yes", "current", "A", "AC-3 400 V", "kind:Contact", "", "", "25,5"],
 ["acme", "ac-1", "", "", "", "", "", "", "coil_voltage", "V", "", "A1/A2", "", "24", ""],
 ["Acme", "AC-1", "", "", "", "", "", "", "motor_power", "", "AC-3 400 V", "", "9.5", "", "12"],
 ["Beta", "B-9", "", "", "preview", "analog thing", AM, "1", "input_current", "mA", "range", "kind:Channel", "", "", "20"],
 ["Example Co", "CTR-25-24DC", "Series 9", "", "", "", "", "", "current", "", "AC-3 400 V", "kind:Contact", "", "", "26"],   # existing product + existing rating replaced
 ["Example Co", "CTR-25-24DC", "", "", "", "Changed text", "", "", "", "", "", "", "", "", ""],                                  # series stays from the line before
 ["Other Co", "OC-18-24DC", "", "", "obsolete", "", "", "", "", "", "", "", "", "", ""],                                  # existing product status only
 ["Other Co", "OC-18-24DC", "", "", "", "18 A contactor, 24 V DC coil (too small)"],                                  # status stays obsolete
 ["Example Co", "CTR-32-24DC", "", "", "", "", CT, "", "", "", "", "", "", "", ""],                                       # suggestion only
]
p1 = put("g1.csv", csvtext(rows), bom=True)
o = run(["peopen " + f, "pe page products", "pe prod csvimport|" + p1])
R = res(o, "csvimport")
check("good import: ok with the summary", len(R) == 1 and R[0] == "PE prod csvimport ok Products added 2, changed 2; ratings added 4, changed 1; suggestions made or changed 3.", R)
prod, rat, sug = norm(f); c = db(f)
want_new = [("Acme", "AC-1", "A-series", "Contactor", "active", "25 A, \"tough\", with comma\nand a second line"), ("Beta", "B-9", "", "AnalogInputModule", "preview", "analog thing")]
check("good import: the new products (class from the line or from the part, status active by default, text with quotes and line break intact)", all(w in prod for w in want_new), [p for p in prod if p[0] in ("Acme", "Beta")])
check("good import: case-insensitive match merged the 'acme / ac-1' line into one product", sum(1 for p in prod if p[0].lower() == "acme") == 1 and len(prod) == 7, prod)
ex = [p for p in prod if p[1] == "CTR-25-24DC"][0]; ob = [p for p in prod if p[1] == "OC-18-24DC"][0]
check("good import: an existing product keeps what the line leaves empty and takes what it gives", ex[2] == "Series 9" and ex[5] == "Changed text" and ob[4] == "obsolete" and ob[5] == "18 A contactor, 24 V DC coil (too small)", (ex, ob))
mine = [r for r in rat if r[0] == "Acme"]
check("good import: three Acme ratings with the numbers (comma decimal 25,5), units filled in, condition and target kept",
      sorted(mine) == sorted([("Acme", "AC-1", "kind:Contact", "current", "AC-3 400 V", None, None, 25.5, "A"), ("Acme", "AC-1", "A1/A2", "coil_voltage", "", None, 24.0, None, "V"), ("Acme", "AC-1", "", "motor_power", "AC-3 400 V", 9.5, None, 12.0, "kW")]), mine)
exr = [r for r in rat if r[1] == "CTR-25-24DC" and r[3] == "current"]
check("good import: the existing rating (same target, quantity, condition) was replaced, not doubled", exr == [("Example Co", "CTR-25-24DC", "kind:Contact", "current", "AC-3 400 V", None, None, 26.0, "A")], exr)
check("good import: suggestions -- preferred yes for Acme on the contactor, plain for CTR-32, the old ones kept", sorted(sug) == sorted([("Acme", "AC-1", CT, 1), ("Beta", "B-9", AM, 1), ("Example Co", "CTR-32-24DC", CT, 0), ("AutomationDirect", "P2-04AD-1", AM, 0), ("Example Co", "CTR-25-24DC", CT, 0)]), sug)
rv = dict(c.execute("select MPN,Revision from Product").fetchall()); c.close()
check("good import: revisions -- an untouched product keeps its revision, a changed one goes up", rv["P2-04AD-1"] == rev_before["P2-04AD-1"] and rv["CTR-25-24DC"] != rev_before["CTR-25-24DC"] and rv["OC-18-24DC"] != rev_before["OC-18-24DC"], (rv, rev_before))
# ---- the same data as semicolon text, BOM and CRLF, into a fresh file: same result
f2 = mk("b.TCParts"); p2 = put("g2.csv", csvtext(rows, delim=";"), bom=True)
o = run(["peopen " + f2, "pe page products", "pe prod csvimport|" + p2])
check("semicolon-separated text gives the same tables", norm(f2) == norm(f), (res(o, "csvimport"), ))
f2b = mk("b2.TCParts"); p2b = put("g2b.csv", csvtext(rows, delim="\t", nl="\n"))
o = run(["peopen " + f2b, "pe page products", "pe prod csvimport|" + p2b])
check("tab-separated text with plain line ends gives the same tables", norm(f2b) == norm(f), res(o, "csvimport"))
# ---- importing the same file again changes nothing in the tables (ratings replaced by themselves)
o = run(["peopen " + f, "pe page products", "pe prod csvimport|" + p1])
check("importing the file twice: nothing added", res(o, "csvimport")[0].startswith("PE prod csvimport ok Products added 0, changed 0; ratings added 0, changed 5;") and norm(f) == norm(f2), res(o, "csvimport"))
# ---- bad lines: reason + file unchanged
BAD = [
 ("empty manufacturer", [["", "X1", "", "Contactor"]], HEAD, "Line 2: The manufacturer is empty."),
 ("empty mpn", [["Z", "", "", "Contactor"]], HEAD, "Line 2: The model number (MPN) is empty."),
 ("unknown column", [["Z", "1"]], ["Manufacturer", "MPN", "Colour"], 'Line 1: "Colour" is not a column of the product import'),
 ("column twice", [["Z", "1"]], ["Manufacturer", "MPN", "mpn"], 'Line 1: the column "mpn" is there twice.'),
 ("missing column", [["Z"]], ["Manufacturer", "Series"], "Line 1: the columns Manufacturer and MPN are needed."),
 ("unknown class", [["Z", "1", "", "Spaceship"]], HEAD, 'Line 2: "Spaceship" is not a class of this library.'),
 ("abstract class", [["Z", "1", "", "SwitchingDevice"]], HEAD, "Line 2: Choose a class for the product (an abstract class cannot hold products)."),
 ("new product without class", [["Z", "1"]], HEAD, "Line 2: The product Z 1 is new, so it needs a class (or a part to take it from)."),
 ("bad status", [["Z", "1", "", "Contactor", "dead"]], HEAD, "Line 2: The status must be active, obsolete, preview or custom."),
 ("unknown part", [["Z", "1", "", "Contactor", "", "", "Nothing"]], HEAD, 'Line 2: "Nothing" is not a part of this library.'),
 ("part of another class", [["Z", "1", "", "Contactor", "", "", AM]], HEAD, "Line 2: The product belongs to another class than the part"),
 ("bad number", [["Z", "1", "", "Contactor", "", "", "", "", "current", "", "", "", "abc"]], HEAD, 'Line 2: "abc" is not a number (minimum).'),
 ("no quantity", [["Z", "1", "", "Contactor", "", "", "", "", "", "", "", "", "", "", "5"]], HEAD, "Line 2: A rating needs a quantity."),
 ("unknown quantity", [["Z", "1", "", "Contactor", "", "", "", "", "luck", "", "", "", "", "", "5"]], HEAD, 'Line 2: "luck" is not a quantity of this library.'),
 ("wrong unit", [["Z", "1", "", "Contactor", "", "", "", "", "current", "V", "", "", "", "", "5"]], HEAD, "Line 2: The unit of current is A, not V."),
 ("no values", [["Z", "1", "", "Contactor", "", "", "", "", "current"]], HEAD, "Line 2: Give at least one of minimum, typical and maximum."),
 ("min above max", [["Z", "1", "", "Contactor", "", "", "", "", "current", "", "", "", "9", "", "3"]], HEAD, "Line 2: The minimum is above the maximum."),
 ("unknown kind", [["Z", "1", "", "Contactor", "", "", "", "", "current", "", "", "kind:Zzz", "", "", "3"]], HEAD, 'Line 2: "Zzz" is not a kind of object in this library.'),
]
for name, rws, head, msg in BAD:
    before = dump(f)
    # two good lines first, so a half-done import would show
    good = [["Good", "G-1", "", "Contactor", "", "", "", "", "current", "", "", "", "", "", "7"], ["Good", "G-2", "", "Contactor"]]
    p = put("bad.csv", csvtext(good + rws if head is HEAD else rws, head=head))
    o = run(["peopen " + f, "pe page products", "pe prod csvimport|" + p]); R = res(o, "csvimport")
    exp = msg if head is not HEAD else msg.replace("Line 2:", "Line 4:")
    if head is not HEAD: exp = msg
    check("bad: " + name, len(R) == 1 and R[0].startswith("PE prod csvimport error " + exp), R)
    check("bad: %s leaves the file as it was" % name, dump(f) == before, None)
# ---- empty and unreadable file
p = put("empty.csv", ""); o = run(["peopen " + f, "pe page products", "pe prod csvimport|" + p, "pe prod csvimport|" + os.path.join(tmp, "nonexistent.csv")])
R = res(o, "csvimport")
check("an empty file and a missing file are refused", len(R) == 2 and R[0] == "PE prod csvimport error The file has no lines." and R[1].startswith("PE prod csvimport error The file cannot be read"), R)
# ---- export, then import into a library without products
out = os.path.join(tmp, "out.csv"); o = run(["peopen " + f, "pe page products", "pe prod csvexport|" + out])
E = res(o, "csvexport")
check("export: ok with the count", len(E) == 1 and E[0] == "PE prod csvexport ok Products written: 7.", E)
rows_out = list(csv.reader(open(out, encoding="utf-8", newline="")))
check("export: header and a line per rating / suggestion, readable by Python's csv", rows_out[0] == HEAD and len(rows_out) > 8 and all(len(r) == 15 for r in rows_out), (rows_out[0], len(rows_out)))
f3 = mk("c.TCParts"); c = db(f3); c.execute("delete from Rating where ProductID is not null"); c.execute("delete from PartProduct"); c.execute("delete from Product"); c.commit(); c.close()
o = run(["peopen " + f3, "pe page products", "pe prod csvimport|" + out])
a, b = norm(f3), norm(f)
check("export then import into a library without products: same products, ratings and suggestions", a == b and len(a[0]) == 7, ([x for x in a[0] if x not in b[0]], [x for x in b[0] if x not in a[0]], [x for x in a[1] if x not in b[1]][:3], [x for x in b[1] if x not in a[1]][:3], [x for x in a[2] if x not in b[2]], [x for x in b[2] if x not in a[2]]))
# ---- menu
o = run(["peopen " + f, "pe menu", "pe page products", "pe menu"]); M = [l for l in o if l.startswith("PEMENU")]
check("menu: import / export are available on the Products page only", len(M) == 2 and "pimp=0 pexp=0" in M[0] and "pimp=1 pexp=1" in M[1], M)
print("%d checks, %d failed" % (checks, len(fails))); sys.exit(1 if fails else 0)
