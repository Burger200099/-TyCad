#!/usr/bin/env python3
"""Parts list (BoM) columns for placed parts: Manufacturer, Model number, Status (resolved / typed only / unresolved) and Fit, after TinyCAD's own columns.
Oracle: Python's sqlite3 on the sample parts file (the products and their ProductFitSummary verdicts) and the expected lines worked out here from what was placed; the
CSV and the spreadsheet (;) lists are read back with Python's csv module. Cases: lines are grouped by (part, product): identical placements count together, a different
product, a typed-only product and no product are separate lines; the status and the fit words follow the rules; the reference lists match the quantities; the header has the
part columns only when a part is in the design; the semicolon list has the same lines; with 'all attributes' the part columns come after the padded attribute columns.
Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, sys, csv, io, shutil, sqlite3, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, "..", "docs"))
import parts_seed
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Parts list column checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = os.environ.get("KEEP") or tempfile.mkdtemp(); fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:700])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    return subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env).stdout.splitlines()
q = lambda s: '"%s"' % s if " " in s else s
f = os.path.join(tmp, "a.TCParts"); parts_seed.build(f).close(); db = sqlite3.connect(f)
parts = db.execute("select p.PartID, p.Name from Part p join PartClass c using(ClassID) order by lower(c.Name), lower(p.Name)").fetchall()   # the Parts tab order
def verdict(part_id, mpn):
    return db.execute("select f.Verdict from ProductFitSummary f join Product p using(ProductID) where f.PartID=? and p.MPN=?", (part_id, mpn)).fetchone()[0]
def product(part_id, verd):
    return db.execute("select p.Manufacturer, p.MPN from ProductFitSummary f join Product p using(ProductID) where f.PartID=? and f.Verdict=? order by p.MPN", (part_id, verd)).fetchall()
ana = next(i for i, p in enumerate(parts) if p[1].startswith("Analog")); ctr = next(i for i, p in enumerate(parts) if p[1].startswith("Contactor"))
a_mfr, a_mpn = product(parts[ana][0], "fits")[0]
c_ok = product(parts[ctr][0], "fits_oversized")[0]; c_bad = product(parts[ctr][0], "does_not_fit")[0]
check("the sample has the products the cases need", a_mpn and c_ok and c_bad, (a_mpn, c_ok, c_bad))
placements = [  # (row, x, mfr/mpn kind)
    (ana, 40, ("choose", a_mfr, a_mpn)), (ana, 90, ("choose", a_mfr, a_mpn)),
    (ctr, 140, ("choose",) + c_ok), (ctr, 190, ("choose",) + c_ok), (ctr, 240, ("choose",) + c_bad), (ctr, 290, ("type", "Acme", "X-1")), (ctr, 340, ("none",)),
]
script = ["newdoc A4", "pdbtab open " + f]
for row, x, how in placements:
    script.append("pdbplace %d %d 60 yes" % (row, x))
    if how[0] == "choose": script.append("pdbchoose %s %s" % (q(how[1]), q(how[2])))
    elif how[0] == "type": script.append("pdbtype %s %s" % (how[1], how[2]))
script.append("annotatedialog action=add which=all press=ok")
out_csv = os.path.join(tmp, "b.csv"); out_xls = os.path.join(tmp, "b2.csv"); out_att = os.path.join(tmp, "b3.csv"); out_txt = os.path.join(tmp, "b.txt")
script += ["partslist type=1 file=%s sheets=0 attrs=0" % out_csv, "partslist type=2 file=%s sheets=0 attrs=0" % out_xls, "partslist type=1 file=%s sheets=0 attrs=1" % out_att,
           "partslist type=0 file=%s sheets=0 attrs=0" % out_txt]
o = run(script)
check("everything was placed", sum(1 for l in o if l.startswith("PDBPLACE") and l.endswith("placed")) == len(placements), o[:12])
def status_of(how): return {"choose": "resolved", "type": "typed only", "none": "unresolved"}[how[0]]
def fit_ok(how, part_id):
    if how[0] != "choose": return ""
    mpn = how[2]; v = verdict(part_id, mpn)
    return {"fits": "Fits", "fits_oversized": "Fits (oversized)"}.get(v, "Does not fit")
want = {}
for row, x, how in placements:
    mfr, mpn = (how[1], how[2]) if how[0] in ("choose", "type") else ("", "")
    key = (parts[row][1], mfr, mpn, status_of(how), fit_ok(how, parts[row][0]))
    want[key] = want.get(key, 0) + 1
def read(path, delim):
    if not os.path.exists(path): return None, None
    rows = list(csv.reader(io.StringIO(open(path, encoding="utf-8").read()), delimiter=delim))
    return rows[0], rows[1:]
for label, path, delim, attrs in (("CSV", out_csv, ",", False), ("spreadsheet", out_xls, ";", False), ("CSV with attributes", out_att, ",", True)):
    head, rows = read(path, delim)
    check(label + ": the list was written", head is not None, path)
    if head is None: continue
    check(label + ": the header ends with the part columns after TinyCAD's own", head[:3] == ["Reference", "Quantity", "Name"] and head[-4:] == ["Manufacturer", "Model number", "Status", "Fit"], head)
    check(label + ": every line has as many columns as the header", all(len(r) == len(head) for r in rows), [(len(r), len(head)) for r in rows])
    got = {}
    for r in rows:
        key = (r[2],) + tuple(r[-4:-1]) + (r[-1].split(":")[0].split(" (")[0] if r[-1].startswith("Does not fit") else r[-1],)
        got[key] = got.get(key, 0) + int(r[1])
        check(label + ": %s has one reference per piece" % r[2], len([x for x in r[0].replace('"', "").replace(";", ",").split(",") if x]) == int(r[1]), r)
    want_keys = {k[:1] + k[1:4] + (k[4] if k[4] != "Does not fit" else "Does not fit",): v for k, v in want.items()}
    check(label + ": the lines and their quantities equal what was placed", got == want_keys, (got, want_keys))
    if attrs: check(label + ": the attribute columns are padded before the part columns", len(head) >= 3 + 2 + 4, head)
txt = open(out_txt, encoding="utf-8").read() if os.path.exists(out_txt) else ""
check("the text list holds the manufacturer and model of a resolved line", a_mpn in txt and "typed only" in txt and "unresolved" in txt, txt[:400])
# a design without parts: TinyCAD's columns only
o = run(["newdoc A4", "partslist type=1 file=%s sheets=0 attrs=0" % os.path.join(tmp, "e.csv")])
head, rows = read(os.path.join(tmp, "e.csv"), ",")
check("no part in the design: the header is TinyCAD's own", head == ["Reference", "Quantity", "Name", "Description", "Package"], head)
print("%d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
