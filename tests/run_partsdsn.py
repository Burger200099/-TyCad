#!/usr/bin/env python3
"""Part data in the .dsn: a placed generic part keeps its part copy (GUIDs, name, class, requirements) and the chosen product (manufacturer, model, ratings) in the design file, loads
them back, and judges the fit without the library. Oracles: Python's sqlite3 on the sample file (ProductFitSummary verdicts, ratings of Part/Product) and the text of the saved .dsn.
Cases: save/load round trip; fit verdict of every product of each part equals the SQL view's; a typed-only product is 'does_not_fit' (missing); no product -> missing; undo of the choice;
copy-paste keeps the product; a .dsn without part data still loads. Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, sys, re, shutil, sqlite3, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, "..", "docs"))
import parts_seed
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Part data checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:600])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    return subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env).stdout.splitlines()
q = lambda s: '"%s"' % s if " " in s else s
f = os.path.join(tmp, "a.TCParts"); parts_seed.build(f).close(); db = sqlite3.connect(f)
parts = db.execute("select p.PartID, p.UID, p.Name from Part p join PartClass c using(ClassID) order by lower(c.Name), lower(p.Name)").fetchall()
for idx, (pid, uid, name) in enumerate(parts):
    need_n = db.execute("select count(*) from Rating where PartID=?", (pid,)).fetchone()[0]
    prods = db.execute("select p.Manufacturer, p.MPN, f.Verdict, (select count(*) from Rating where ProductID=p.ProductID) from ProductFitSummary f join Product p using(ProductID) where f.PartID=?", (pid,)).fetchall()
    check("the sample part %d has requirements and products (so the checks can fail)" % idx, need_n > 0 and len(prods) >= 1, (need_n, prods))
    for mfr, mpn, verdict, have_n in prods:
        dsn = os.path.join(tmp, "d%d_%s.dsn" % (idx, re.sub(r"\W", "", mpn)))
        o = run(["newdoc A4", "pdbtab open " + f, "pdbplace %d 80 60 yes" % idx, "selectall", "pdbfit", "pdbchoose %s %s" % (q(mfr), q(mpn)), "pdbfit", "savedocas " + dsn])
        fit = [l for l in o if l.startswith("PARTFIT")]
        check("%s / %s: before a product is chosen every requirement is missing" % (name, mpn), fit and fit[0] == "PARTFIT does_not_fit", fit)
        check("%s / %s: the fit verdict equals the SQL view's (%s)" % (name, mpn, verdict), len(fit) == 2 and fit[1] == "PARTFIT " + verdict, (fit, verdict))
        txt = open(dsn, encoding="utf-8", errors="replace").read() if os.path.exists(dsn) else ""
        check("%s / %s: the .dsn holds the part copy, %d needs and the product with %d ratings" % (name, mpn, need_n, have_n),
              ("uid='%s'" % uid) in txt and len(re.findall(r"<NEED ", txt)) == need_n and len(re.findall(r"<HAVE ", txt)) == have_n and (mpn in txt), (len(txt), re.findall(r"<(?:PART|PRODUCT)[^>]*>", txt)))
        o = run(["open " + dsn, "pdbinfo", "selectall", "pdbfit"])
        info = [l for l in o if l.startswith("PARTINFO ") and "end" not in l]
        check("%s / %s: after loading, the part and product are back" % (name, mpn), len(info) == 1 and info[0].startswith("PARTINFO 0|%s|%s|" % (name, uid)) and ("|%d|%s|%s|" % (need_n, mfr, mpn)) in info[0] and info[0].endswith("|%d" % have_n), info)
        fit = [l for l in o if l.startswith("PARTFIT")]
        check("%s / %s: after loading, the fit is judged from the file alone: same verdict" % (name, mpn), fit == ["PARTFIT " + verdict], fit)
allv = {r[0] for r in db.execute("select Verdict from ProductFitSummary")}
check("the sample products give several different verdicts (so the verdict check can fail)", len(allv) >= 3, allv)
# typed product, undo, copy/paste, clear
dsn = os.path.join(tmp, "t.dsn")
o = run(["newdoc A4", "pdbtab open " + f, "pdbplace 0 80 60 yes", "selectall", "pdbtype Acme X-1", "pdbfit", "savedocas " + dsn])
check("a typed manufacturer and model with no ratings: every requirement is missing", "PARTFIT does_not_fit" in o and all(l.endswith("|missing") for l in o if l.startswith("FITLINE")), o)
o = run(["open " + dsn, "pdbinfo"])
check("the typed product survives save and load", any("|Acme|X-1||0" in l for l in o), o)
mf, mp, _v, _h = db.execute("select p.Manufacturer, p.MPN, f.Verdict, 0 from ProductFitSummary f join Product p using(ProductID) where f.PartID=? and f.Verdict='fits'", (parts[0][0],)).fetchone() if db.execute("select count(*) from ProductFitSummary where PartID=? and Verdict='fits'", (parts[0][0],)).fetchone()[0] else (None,)*4
if mf:
    o = run(["newdoc A4", "pdbtab open " + f, "pdbplace 0 80 60 yes", "selectall", "pdbchoose %s %s" % (q(mf), q(mp)), "undo", "pdbinfo", "redo", "pdbinfo"])
    inf = [l for l in o if l.startswith("PARTINFO ") and "end" not in l]
    check("undo takes the product away, redo brings it back", len(inf) == 2 and ("|%s|%s|" % (mf, mp)) not in inf[0] and ("|%s|%s|" % (mf, mp)) in inf[1], inf)
    o = run(["newdoc A4", "pdbtab open " + f, "pdbplace 0 80 60 yes", "selectall", "pdbchoose %s %s" % (q(mf), q(mp)), "copy", "paste", "pdbinfo"])
    inf = [l for l in o if l.startswith("PARTINFO ") and "end" not in l]
    check("a pasted copy of a placed part keeps its part and product", len(inf) == 2 and all(("|%s|%s|" % (mf, mp)) in l for l in inf), o)
    o = run(["newdoc A4", "pdbtab open " + f, "pdbplace 0 80 60 yes", "selectall", "pdbchoose %s %s" % (q(mf), q(mp)), "pdbclear", "pdbinfo"])
    inf = [l for l in o if l.startswith("PARTINFO ") and "end" not in l]
    check("clearing the product leaves the part", len(inf) == 1 and inf[0].split("|")[5:8] == ["", "", ""], inf)
# plain design without part data
plain = os.path.join(tmp, "p.dsn")
o = run(["newdoc A4", "savedocas " + plain]); o = run(["open " + plain, "pdbinfo"])
check("a design with no part data loads and reports none", "PARTINFO end" in o and not any(l.startswith("PARTINFO ") and "end" not in l for l in o), o)
print("%d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
