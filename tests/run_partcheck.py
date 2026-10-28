#!/usr/bin/env python3
"""The parts check of the design rules check: placed parts with a product that does not fit, no product, a typed-only product or an oversized one.
Oracle: Python's sqlite3 on the sample parts file (the ProductFit view: one row per requirement with Status ok / oversized / undersized / missing / mismatch). For every product
of the sample, one placed part: the number of 'Part does not fit' lines equals the view's undersized+mismatch rows, 'larger than required' lines equal its oversized rows (and go when
the setting hides them); a part with no product or one typed by hand gives one line, as a warning, an error, or none by the setting; a design with only plain symbols or with the
check off gets no lines; the markers equal the lines (marker k = line k), also after the ERC's own lines. Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, re, sys, shutil, sqlite3, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, "..", "docs"))
import parts_seed
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Parts check skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; n = [0]
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
parts = db.execute("select p.PartID, p.Name from Part p join PartClass c using(ClassID) order by lower(c.Name), lower(p.Name)").fetchall()
def lines_of(o, only_parts=True):
    w = [l for l in o if l.startswith("ERCWINDOW")]
    if not w: return None
    m = re.search(r"lines=(.*)$", w[-1]); L = [x for x in m.group(1).split("|") if x] if m else []
    return [l for l in L if l.startswith(("Part", "Product"))] if only_parts else L
def count_markers(o):
    w = [l for l in o if l.startswith("ERCMARKERS")]
    return len(re.findall(r"\d+:\d+:", w[-1].split(" ")[1])) if w else -1
cases = 0
for pi, (pid, pname) in enumerate(parts):
    for mfr, mpn in db.execute("select Manufacturer, MPN from Product where ProductID in (select ProductID from ProductFit where PartID=?) order by MPN", (pid,)).fetchall():
        st = dict(db.execute("select f.Status, count(*) from ProductFit f join Product p using(ProductID) where f.PartID=? and p.MPN=? group by 1", (pid, mpn)).fetchall())
        bad = st.get("undersized", 0) + st.get("missing", 0) + st.get("mismatch", 0); over = st.get("oversized", 0)
        base = ["newdoc A4", "pdbtab open " + f, "pdbplace %d 80 60 yes" % pi, "pdbchoose %s %s" % (q(mfr), q(mpn))]
        o = run(base + ["partcheck oversized=1", "check show=1", "ercwindow", "ercmarkers"])
        L = lines_of(o) or []
        nb = sum(1 for l in L if l.startswith("Part does not fit")); no = sum(1 for l in L if l.startswith("Product is larger"))
        check("%s: %d does-not-fit lines, %d larger lines (the view's rows)" % (mpn, bad, over), nb == bad and no == over and len(L) == bad + over, L)
        check("%s: every line of the window has its marker" % mpn, count_markers(o) == len(lines_of(o, False)), (count_markers(o), lines_of(o, False)))
        o = run(base + ["partcheck oversized=0", "check show=1", "ercwindow"])
        L = lines_of(o) or []
        check("%s: with oversized hidden only the real problems stay (%d)" % (mpn, bad), sum(1 for l in L if l.startswith("Part does not fit")) == bad and not any("larger" in l for l in L), L)
        cases += 1
check("every product of the sample was checked", cases == 5, cases)
# unresolved / typed
for how, text in (("none", "no product chosen"), ("type", "typed by hand")):
    for setting, word in ((0, None), (1, "(warning)"), (2, "(error)")):
        pre = ["newdoc A4", "pdbtab open " + f, "pdbplace 0 80 60 yes"] + (["pdbtype Acme X-1"] if how == "type" else [])
        o = run(pre + ["partcheck oversized=1 unresolved=%d" % setting, "check show=1", "ercwindow"])
        L = lines_of(o) or []
        if word is None:
            check("%s, unresolved not reported: no line" % how, not any("Part has no" in l or "typed by hand" in l for l in L), L)
        else:
            hit = [l for l in L if text in l]
            check("%s, unresolved as %s: one line" % (how, word), len(hit) == 1 and word in hit[0], L)
# typed-only is not 'resolved': also the missing ratings are not double reported
o = run(["newdoc A4", "pdbtab open " + f, "pdbplace 0 80 60 yes", "pdbtype Acme X-1", "partcheck unresolved=1", "check show=1", "ercwindow"])
check("a typed-only part gives one line, not one per requirement", len(lines_of(o) or []) == 1, lines_of(o))
# numbering after the ERC's own lines: an unassigned reference line comes first
o = run(["newdoc A4", "pdbtab open " + f, "pdbplace 0 80 60 yes", "pdbplace 1 160 60 yes", "partcheck unresolved=1", "check show=1", "ercwindow", "ercmarkers"])
L = lines_of(o, False) or []
check("the ERC lines come first, then the 2 parts' lines, and every line has its marker", len(L) >= 4 and count_markers(o) == len(L) and not L[0].startswith("Part") and sum(1 for l in L if l.startswith("Part has no")) == 2 and L[-1].startswith("Part has no"), (L, count_markers(o)))
# check off, and plain symbols
o = run(["newdoc A4", "pdbtab open " + f, "pdbplace 0 80 60 yes", "annotatedialog action=add which=all press=ok", "partcheck on=0", "check show=1", "ercwindow"])
check("with the parts check off nothing of it is reported", not any(l.startswith(("Part", "Product")) for l in (lines_of(o) or [])), lines_of(o))
o = run(["newdoc A4", "check show=1", "ercwindow"])
check("an empty design: no errors", any("No errors" in l for l in (lines_of(o, False) or [])), lines_of(o, False))
print("%d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
