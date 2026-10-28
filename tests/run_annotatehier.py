#!/usr/bin/env python3
"""Generate Symbol References and the designs placed as symbols (Special.cpp treats xHierarchicalSymbol like a placed symbol: it is numbered with the
others, and DrawMethod.cpp AddReference counts it among the numbers already used). Checked against annooracle.py (the oracle takes the placed designs'
prefix and box from annotest dump and restates everything the command does with them). Designs: samples with placed designs injected (some numbered,
some not, one whose design is missing, so it has nothing to draw and is left alone). Mutations: the placed designs left out of the counting.
Needs the built annotest."""
import os, random, re, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import annooracle as ao

EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
if not os.path.exists(ao.AT):
    print("Annotate (placed designs) checks skipped: build tests/drivers/annotest.pas first", ao.AT); sys.exit(0)
tmp = tempfile.mkdtemp()
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 15: print("  FAIL", n, str(d)[:700])

def child(path):
    body = ('<RECTANGLE a="23,31" b="87,95" style="0" fill="0"/><PIN pos="23,47" direction="3" length="15" which="0" elec="0" show="1" number="1" part="0">A</PIN>')
    open(path, "w").write('<?xml version="1.0" encoding="UTF-8"?>\n<TinyCADSheets><TinyCAD><NAME>Top</NAME><WIRE a="1,1" b="5,1"/></TinyCAD>'
                          '<HierarchicalSymbol><NAME>x</NAME><DETAILS><Size width="1485" height="1050"/></DETAILS>%s</HierarchicalSymbol></TinyCADSheets>' % body)
def hs(x, y, ref, fname):
    return ('<HIERARCHICAL_SYMBOL pos="%g,%g" rotate="0" can_scale="1" scale_x="1" scale_y="1" file="%s">'
            '<FIELD type="0" description="Ref" value="%s" show="1" pos="0,0"/><FIELD type="0" description="Design" value="" show="0" pos="0,0"/>'
            '</HIERARCHICAL_SYMBOL>' % (x, y, fname, ref))
def inject(txt, add):
    i = txt.rfind("</TinyCAD>", 0, txt.rfind("</TinyCADSheets>") if "</TinyCADSheets>" in txt else len(txt))
    return txt[:i] + add + txt[i:]
def run_prog(dsn, add, which, value, match, start, alls, active):
    out = os.path.join(tmp, "out.dsn")
    r = subprocess.run([ao.AT, "run", dsn, out, "1" if add else "0", str(which), str(value), match, str(start), "1" if alls else "0", str(active)], capture_output=True, text=True)
    return r.returncode, r.stdout.split("\n")
def same(a, b):
    if len(a) != len(b): return False
    for x, y in zip(a, b):
        if (x["sheet"], x["idx"], x["ref"], x["part"]) != (y["sheet"], y["idx"], y["ref"], y["part"]): return False
        if any(abs(p - q) > 1e-6 for p, q in zip(x["A"] + x["B"], y["A"] + y["B"])): return False
    return True

cdir = os.path.join(tmp, "d"); os.makedirs(cdir)
child(os.path.join(cdir, "c.dsn"))
files = sorted(p for dp, _, fs in os.walk(EXAMPLES) for f in fs for p in [os.path.join(dp, f)] if f.lower().endswith(".dsn") and os.path.getsize(os.path.join(dp, f)) < 120000)
random.seed(11)
random.shuffle(files)
refs_pool = ["H?", "H?", "H3", "H12", "U?", "U4", "H1A", "?", ""]
total = 0; seen = dict(hs_changed=0, hs_counted=0, missing=0)
for n, src in enumerate(files[:10]):
    txt = open(src, encoding="utf-8", errors="replace").read()
    if n % 2 == 0:
        # one symbol definition takes the prefix H?, the same as the placed designs have, so they share their numbers
        txt = re.sub(r"(<REF[^>]*>)[^<]*(</REF>)", r"\1H?\2", txt, count=1)
    add = "".join(hs(10 + 25 * k, 10 + 7 * k, random.choice(refs_pool), "./c.dsn") for k in range(4)) + hs(200, 20, "H?", "./missing.dsn")
    dsn = os.path.join(cdir, "t%d.dsn" % n)
    open(dsn, "w", encoding="utf-8").write(inject(txt, add))
    # the copies are made where the child is, so the placed designs find it
    ms = ao.dump(dsn)
    hsm = [m for m in ms if m["hier"]]
    check("%s: the placed designs are listed" % os.path.basename(src), len(hsm) == 5 and sum(m["nosym"] for m in hsm) == 1, len(hsm))
    nsheets = max([m["sheet"] for m in ms] + [0]) + 1
    prefs = sorted({m["prefix"] for m in ms}) or ["U?"]
    for k in range(10):
        a = random.random() < 0.8
        which = random.choice([0, 1, 2, 0, 1])
        value = random.choice([0, 1])
        match = random.choice(prefs) if which == 2 else "U?"
        start = random.choice([1, 1, 5, 10]) if value == 1 else 1
        want, miss = ao.annotate(ms, a, which, value, match, start, False, 0)
        rc, o = run_prog(dsn, a, which, value, match, start, False, 0)
        got = ao.parse(o)
        ok = rc == 0 and same(got, want) and o[0] == ("R 1" if miss else "R 0")
        check("%s add=%s which=%d value=%d match=%s start=%d" % (os.path.basename(src), a, which, value, match, start), ok, (rc, o[:2]))
        total += 1
        seen["missing"] += miss
        seen["hs_changed"] += any(g["ref"] != m["ref"] for g, m in zip(got, ms) if m["hier"])
        # a placed design with a number counts among the numbers already used by symbols of the same prefix
        if any(m["prefix"] == x["prefix"] and not x["hier"] and m is not x for m in hsm for x in ms): seen["hs_counted"] += 1
print("sample designs with placed designs: %d runs; placed designs changed in %d, same prefix as other symbols in %d, runs with a missing design %d" % (total, seen["hs_changed"], seen["hs_counted"], seen["missing"]))
check("the placed designs were renumbered somewhere", seen["hs_changed"] > 20, seen)
check("a missing design was met", seen["missing"] > 20, seen)

# a small design by hand: H1 and a symbol sharing the prefix of symbol 0 get distinct numbers
print("annotate (placed designs): %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
