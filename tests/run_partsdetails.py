#!/usr/bin/env python3
"""Details of a placed generic part (A2): Manufacturer / Model number properties, the Choose Product window, the fit words, the remembered parts file.
Oracles: Python's sqlite3 on the sample file (ProductFitSummary counts -> the words, the product ratings), the script's PROPS dump.
Cases: properties offered only for a placed part; list of products with the fit words; choosing each product sets manufacturer / model and its fit; typing a different model drops the
ratings (every requirement missing), typing the same keeps them; cancel changes nothing; undo; no selection / no library / part not in the library / unknown product; the last parts file
is opened again at the next start. Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, sys, shutil, sqlite3, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, "..", "docs"))
import parts_seed
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Part details checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
def words(v, u, m, x):
    if v == "fits": return "Fits"
    if v == "fits_oversized": return "Fits (oversized)"
    if v == "no_requirements": return "No requirements"
    return "Does not fit:" + ",".join(" %d %s" % (c, w) for c, w in ((u, "undersized"), (m, "missing"), (x, "mismatched")) if c)
f = os.path.join(tmp, "a.TCParts"); parts_seed.build(f).close(); db = sqlite3.connect(f)
parts = db.execute("select p.PartID, p.Name from Part p join PartClass c using(ClassID) order by lower(c.Name), lower(p.Name)").fetchall()
for idx, (pid, name) in enumerate(parts):
    need_n = db.execute("select count(*) from Rating where PartID=?", (pid,)).fetchone()[0]
    prods = db.execute("select p.Manufacturer, p.MPN, f.Verdict, f.Undersized, f.Missing, f.Mismatch from ProductFitSummary f join Product p using(ProductID) where f.PartID=? "
                       "order by f.Verdict='does_not_fit', lower(p.Manufacturer), lower(p.MPN)", (pid,)).fetchall()
    want_rows = ["%s|%s|%s" % (m, mp, words(v, u, ms, x)) for m, mp, v, u, ms, x in prods]
    o = run(["newdoc A4", "pdbtab open " + f, "pdbplace %d 80 60 yes" % idx, "selectall", "props", "pdbpick list", "pdbfittext"])
    pr = [l for l in o if l.startswith("PROPS")]
    check("%s: Manufacturer and Model number are offered, empty to begin with" % name, pr and "sym.mfr=;" in pr[0] and pr[0].endswith("sym.model="), pr)
    rows = [l[len("PICKROW "):] for l in o if l.startswith("PICKROW ") and "end" not in l]
    check("%s: the window lists the part's products with the fit words" % name, rows == want_rows, (rows, want_rows))
    check("%s: no product yet: every requirement missing" % name, "PARTFITTEXT Does not fit: %d missing" % need_n in o, o)
    for m, mp, v, u, ms, x in prods:
        o = run(["newdoc A4", "pdbtab open " + f, "pdbplace %d 80 60 yes" % idx, "selectall", "pdbpick %s %s" % (q(m), q(mp)), "props", "pdbfittext"])
        pr = [l for l in o if l.startswith("PROPS")]
        check("%s / %s: chosen: manufacturer and model are set" % (name, mp), "PDBPICK chosen" in o and pr and ("sym.mfr=%s;" % m) in pr[0] and pr[0].endswith("sym.model=" + mp), (pr, o[:6]))
        check("%s / %s: the fit words are %r" % (name, mp, words(v, u, ms, x)), "PARTFITTEXT " + words(v, u, ms, x) in o, o)
# typing, cancel, undo
m0, mp0, v0 = db.execute("select p.Manufacturer, p.MPN, f.Verdict from ProductFitSummary f join Product p using(ProductID) where f.PartID=? and f.Verdict like 'fits%' order by p.MPN", (parts[1][0],)).fetchone()
need1 = db.execute("select count(*) from Rating where PartID=?", (parts[1][0],)).fetchone()[0]
o = run(["newdoc A4", "pdbtab open " + f, "pdbplace 1 80 60 yes", "selectall", "pdbpick %s %s" % (q(m0), q(mp0)), "setprop sym.model %s" % mp0, "pdbfittext",
         "setprop sym.model Z-99", "props", "pdbfittext", "undo", "props", "pdbfittext", "pdbpick cancel", "props"])
pf = [l for l in o if l.startswith("PARTFITTEXT")]; pr = [l for l in o if l.startswith("PROPS")]
check("typing the same model keeps the product's ratings", pf[0] == "PARTFITTEXT " + words(v0, 0, 0, 0), pf)
check("typing a different model keeps the text but drops the ratings (all missing)", pr[0].endswith("sym.model=Z-99") and ("sym.mfr=%s;" % m0) in pr[0] and pf[1] == "PARTFITTEXT Does not fit: %d missing" % need1, (pr, pf))
check("undo of the typing brings the product and its ratings back", pr[1].endswith("sym.model=" + mp0) and pf[2] == pf[0], (pr, pf))
check("cancelling the window changes nothing", pr[2] == pr[1] and "PDBPICK cancelled" in o, o)
# refusals
o = run(["newdoc A4", "pdbtab open " + f, "pdbplace 1 80 60 yes", "selclear", "pdbpick %s %s" % (q(m0), q(mp0)), "selectall", "pdbpick Nobody X-0"])
check("nothing selected / unknown product are refused", [l for l in o if l.startswith("PDBPICK")] == ["PDBPICK noselection", "PDBPICK noproduct"], o)
o = run(["newdoc A4", "pdbtab open " + f, "pdbplace 1 80 60 yes", "selectall", "pdbtab open " + os.path.join(tmp, "b.TCParts") if parts_seed.build(os.path.join(tmp, "b.TCParts")).close() is None else "", "pdbpick %s %s" % (q(m0), q(mp0)), "props"])
check("a library that does not have the part (another file) leaves the part as it is", "PDBPICK nopart" in o and [l for l in o if l.startswith("PROPS")][0].endswith("sym.model="), o)
# remembered parts file
o = run(["newdoc A4", "pdbtab open " + f])
o = run(["pdbtab rows"])
check("the parts file open last time is open again at the next start", len([l for l in o if l.startswith("PDBROW")]) == len(parts), o)
print("%d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
