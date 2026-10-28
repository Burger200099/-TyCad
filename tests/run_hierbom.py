#!/usr/bin/env python3
"""The parts list across hierarchical designs (CBOMGenerator::GenerateBomForDesign following placed hierarchical symbols).

Designs are made from the sample designs: a root with placed designs H1 (a two-sheet design that itself places a design G1), H3 and H1 again
placed as H4. The expected list is worked out in Python from the XML alone (bomoracle's separate reading and writers), by this rule: with
the option on, a placed design is read first (every sheet of it, whatever 'all sheets' says), its parts are listed with the path of the
symbols leading to them in front of the reference ('H1_G1_R3'), then the parts of the sheet(s) themselves; with it off the placed designs
are passed by. Over all three formats, attributes or not, all sheets or one.
Mutations: the option off, a missing design, a design placed twice (two sets of references), and a change to a child.
Needs the built bomtest."""
import os, re, subprocess, sys, tempfile, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xml.etree.ElementTree as ET
from bomoracle import read_design, write, esc

EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
BUILD = os.environ.get("TC_BUILD", "build")
EXE = os.path.join(BUILD, "bomtest")
if not os.path.exists(EXE):
    print("Hierarchical parts list checks skipped: build tests/drivers/bomtest.pas first", EXE); sys.exit(0)
tmp = tempfile.mkdtemp()
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 20: print("  FAIL", n, str(d)[:600])

def sample(name): return os.path.join(EXAMPLES, "circuits", name)
def text(p): return open(p, encoding="utf-8", errors="replace").read()
def hs(x, y, ref, fname):
    return ('<HIERARCHICAL_SYMBOL pos="%d,%d" rotate="0" can_scale="1" scale_x="1" scale_y="1" file="%s">'
            '<FIELD type="0" description="Ref" value="%s" show="1" pos="0,0"/><FIELD type="0" description="Design" value="" show="0" pos="0,0"/>'
            '</HIERARCHICAL_SYMBOL>' % (x, y, fname, ref))
def inject(txt, add):
    i = txt.rfind("</TinyCAD>", 0, txt.rfind("</TinyCADSheets>") if "</TinyCADSheets>" in txt else len(txt))
    return txt[:i] + add + txt[i:]
def sheet_of(txt):
    return txt[txt.index("<TinyCAD>"):txt.rfind("</TinyCAD>") + len("</TinyCAD>")]    # (symbol definitions hold TinyCAD elements too)
def two_sheets(path, out):
    """a design of two sheets: the sample's sheet and a copy of it with every reference prefixed by Q"""
    s = sheet_of(text(path))
    s2 = re.sub(r"""(<FIELD type=.0. description=.Ref. value=.)""", r"\1Q", s)
    open(out, "w", encoding="utf-8").write('<?xml version="1.0" encoding="UTF-8"?>\n<TinyCADSheets>' + s + s2 + '</TinyCADSheets>')

def make(d, missing=False, twice=True):
    os.makedirs(d, exist_ok=True)
    g = os.path.join(d, "g.dsn"); shutil.copy(sample("CurrSens.dsn"), g)
    # h1: two sheets, one of which also places g.dsn as G1
    h1 = os.path.join(d, "h1.dsn"); two_sheets(sample("PSU.dsn"), h1)
    t = inject(text(h1), hs(10, 10, "G1", "./g.dsn" if not missing else "./nothere.dsn"))
    open(h1, "w", encoding="utf-8").write(t)
    h3 = os.path.join(d, "h3.dsn"); shutil.copy(sample("AMP.DSN") if os.path.exists(sample("AMP.DSN")) else sample("PSU.dsn"), h3)
    root = os.path.join(d, "root.dsn")
    add = hs(10, 10, "H1", "./h1.dsn") + hs(40, 10, "H3", "./h3.dsn") + (hs(70, 10, "H4", "./h1.dsn") if twice else "")
    open(root, "w", encoding="utf-8").write(inject(text(sample("Attenuator.dsn")), add))
    return root

# ---------------------------------------------------------------- the expectation: a separate reading of the XML
def placed(path):
    r = ET.parse(path).getroot()
    sheets = [r] if r.tag == "TinyCAD" else r.findall("TinyCAD")
    out = []
    for sh in sheets:
        out.append([(h.findtext("FIELD[@description='Ref']") if False else [f.get("value") for f in h.findall("FIELD") if f.get("description") == "Ref"][0], h.get("file")) for h in sh.findall("HIERARCHICAL_SYMBOL")])
    return out
def collect(path, prefix, allsheets, active, depth=0):
    """[(sheet symbols with the prefix on their references)] for this level and, recursively, for the designs placed on the sheets listed"""
    sheets = read_design(path); hsyms = placed(path)
    chosen = range(len(sheets)) if (allsheets or depth > 0) else [active]
    res = []
    for si in chosen:
        for (ref, fname) in hsyms[si]:
            child = os.path.normpath(os.path.join(os.path.dirname(path), fname.replace("\\", "/")))
            if os.path.exists(child):
                res += collect(child, prefix + ref + "_", allsheets, active, depth + 1)
        res += [(prefix + ref, name, dref, desc, fl) for (ref, name, dref, desc, fl) in sheets[si]]
    return res
def expect(path, ftype, allsheets, allattrs, active, hier):
    if hier:
        flat = collect(path, "", allsheets, active)
        sheets = [flat]
    else:
        sheets = read_design(path); 
        if allsheets: sheets = [[s for sh in sheets for s in sh]]
        else: sheets = [sheets[active]]
    from bomoracle import build
    heads, entries = build(sheets, True, allattrs, 0, ftype)
    return write(heads, entries, ftype, path)[0]

def run(dsn, ftype, allsheets, allattrs, active, hier):
    out = os.path.join(tmp, "o.txt")
    r = subprocess.run([EXE, dsn, out, str(ftype), str(int(allsheets)), str(int(allattrs)), str(active), dsn, str(int(hier))], capture_output=True, text=True)
    if r.returncode != 0: return None, r.stdout + r.stderr
    return open(out, encoding="utf-8", errors="replace").read(), r.stdout

root = make(os.path.join(tmp, "a"))
nsheets = len(read_design(root))
for ftype in (0, 1, 2):
    for allattrs in (False, True):
        for allsheets in (False, True):
            for hier in (False, True):
                got, so = run(root, ftype, allsheets, allattrs, 0, hier)
                want = expect(root, ftype, allsheets, allattrs, 0, hier)
                check("type %d attrs %d sheets %d hier %d" % (ftype, allattrs, allsheets, hier), got == want, (got or so)[:300] + " /// " + want[:300])
got1, _ = run(root, 1, True, False, 0, True)
got0, _ = run(root, 1, True, False, 0, False)
check("the option changes the list", got1 != got0)
check("references carry the path", "H1_G1_" in got1 and "H1_Q" in got1 and "H4_G1_" in got1 and "H3_" in got1, got1[:400])
check("a design placed twice is listed twice with separate references", "H1_" in got1 and "H4_" in got1)
check("without the option nothing has a path", "H1_" not in got0 and "H3_" not in got0, got0[:200])

# mutations
m_missing = make(os.path.join(tmp, "b"), missing=True)
gm, so = run(m_missing, 1, True, False, 0, True)
check("a missing design is reported", gm is not None and "IMPORTERRORS" in so and "nothere.dsn" in so, so)
check("a missing design: the rest of the list is still there, without the missing parts", gm is not None and "H1_Q" in gm and "H1_G1_" not in gm, (gm or "")[:200])
check("a missing design: differs from the full list", gm != got1)
m_once = make(os.path.join(tmp, "c"), twice=False)
go, _ = run(m_once, 1, True, False, 0, True)
check("placing the design once leaves out H4's references", go is not None and "H4_" not in go and go != got1)
# change a child: one part's reference renamed in g.dsn -> the list changes at the right place
d = os.path.join(tmp, "d"); r2 = make(d)
t = text(os.path.join(d, "g.dsn")); t2 = re.sub(r"""(<FIELD type=.0. description=.Ref. value=.)[^'"]*""", r"\g<1>R91", t, count=1)
open(os.path.join(d, "g.dsn"), "w", encoding="utf-8").write(t2)
gc, _ = run(r2, 1, True, False, 0, True)
check("mutation: renaming a part inside the innermost design shows in the list as H1_G1_R91", t2 != t and gc is not None and "H1_G1_R91" in gc and "H4_G1_R91" in gc and gc != got1, (t2 != t))
check("mutation: the oracle agrees with the changed design", gc == expect(r2, 1, True, False, 0, True))

print("hierarchical parts list: %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
