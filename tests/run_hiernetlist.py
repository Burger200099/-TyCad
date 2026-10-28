#!/usr/bin/env python3
"""The netlist of a hierarchical design (CNetList::MakeNet following placed hierarchical symbols).

Designs are generated here; the expected nets are worked out in Python from how the design was built (which names sit on
which wires, which wire ends meet a symbol's pin), never from the Pascal:
  - a root design with two placed copies (H1, H2) of one design; that design has two pins (A, B), labels A, B and X inside
    (A and B are joined through X), and places a third design (G1) one level further down, whose pin P meets a label Z
  - each placed copy is its own instance: labels inside are made unique per instance (_HN_<n>_<name>), instance numbers are
    handed out in the order the designs are found, level by level
  - the nets: root and inner names meet through the pins; two copies of one design stay apart
  - the name a net is given: the label at the highest level (lowest instance number); a label inside a design carries the
    path of symbols leading to it (H1_Z, H1_G1_W); the root's labels are unchanged
  - the reference of the pins of a placed symbol: the path to it (H1, H1_G1)
  - hierarchical symbols not followed (flatnodes, what the design rules use): only the root's nets
  - a design that cannot be read is reported, and the rest still works
Mutations: each change that must change the result is made and the result must differ from the unchanged expectation.
Needs the built nettest and hiertest (tests/drivers); run with TC_BUILD set to their folder."""
import os, re, subprocess, sys, tempfile

BUILD = os.environ.get("TC_BUILD", "build")
NT = os.path.join(BUILD, "nettest")
HT = os.path.join(BUILD, "hiertest")
if not (os.path.exists(NT) and os.path.exists(HT)):
    print("Hierarchical netlist checks skipped: build tests/drivers/nettest.pas and hiertest.pas first", BUILD); sys.exit(0)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from netoracle import unesc

tmp = tempfile.mkdtemp()
fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name)
        if len(fails) <= 30: print("  FAIL", name, str(detail)[:900])

# ------------------------------------------------------------------ building designs
def sheetdoc(top, hier):
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<TinyCADSheets><TinyCAD><NAME>Top</NAME><DETAILS><Size width="1485" height="1050"/></DETAILS>%s</TinyCAD>'
            '<HierarchicalSymbol><NAME>x</NAME><DETAILS><Size width="1485" height="1050"/></DETAILS>%s</HierarchicalSymbol></TinyCADSheets>' % (top, hier))
def hier_sheet(pinnames):
    body = '<RECTANGLE a="23,31" b="87,95" style="0" fill="0"/>'
    for k, n in enumerate(pinnames):
        body += '<PIN pos="23,%d" direction="3" length="15" which="0" elec="0" show="1" number="%d" part="0">%s</PIN>' % (47 + 32 * k, k + 1, n)
    return body
def hs(x, y, ref, fname):
    return ('<HIERARCHICAL_SYMBOL pos="%d,%d" rotate="0" can_scale="1" scale_x="1" scale_y="1" file="%s">'
            '<FIELD type="0" description="Ref" value="%s" show="1" pos="0,0"/><FIELD type="0" description="Design" value="" show="0" pos="0,0"/>'
            '</HIERARCHICAL_SYMBOL>' % (x, y, fname, ref))
def wire(a, b): return '<WIRE a="%d,%d" b="%d,%d"/>' % (a + b)
def label(p, t): return '<LABEL pos="%d,%d" direction="0" font="1" color="0" style="0">%s</LABEL>' % (p[0], p[1], t)
def doc(top): return ('<?xml version="1.0" encoding="UTF-8"?>\n<TinyCADSheets><TinyCAD><NAME>Top</NAME><DETAILS><Size width="1485" height="1050"/></DETAILS>%s</TinyCAD></TinyCADSheets>' % top)
def write(path, text): open(path, "w", encoding="utf-8").write(text)

def pin_offsets(fname, pinnames):
    """Where the pins of a design sit, relative to a symbol placed at 0,0 (in file units): the symbol is placed once and the loader asked
    (hiertest). The loader is only used to learn the geometry; what is checked is whether wires drawn to those points join the pins."""
    d = os.path.join(tmp, "probe"); os.makedirs(d, exist_ok=True)
    write(os.path.join(d, "probe.dsn"), doc(hs(100, 200, "H9", fname)))
    r = subprocess.run([HT, "child", os.path.join(d, "probe.dsn")], capture_output=True, text=True)
    m = re.search(r"^PINS (.*)$", r.stdout, re.M)
    pts = [tuple(float(v) / 5 for v in q.split(",")) for q in m.group(1).split()]
    assert len(pts) == len(pinnames), (r.stdout, r.stderr)
    return [(px - 100, py - 200) for px, py in pts]

def nodes(dsn, mode="nodes"):
    r = subprocess.run([NT, mode, dsn], capture_output=True, text=True)
    nets = []; last = None; errors = ""
    for line in r.stdout.split("\n"):
        if line.startswith("IMPORTERRORS\t"): errors = unesc(line.split("\t", 1)[1])
        if not line.startswith("NODE\t"): continue
        f = line.split("\t")
        node = dict(net=int(f[1]), label=unesc(f[2]), pref=unesc(f[3]), ref=unesc(f[4]), pin=unesc(f[5]), ispin=f[6] == "P", pname=unesc(f[7]) if f[6] == "P" else None)
        if node["net"] != last: nets.append([]); last = node["net"]
        nets[-1].append(node)
    return nets, errors, r.returncode

# ------------------------------------------------------------------ the designs
GRAND_PINS = ["P"]
CHILD_PINS = ["A", "B"]

def make(d, rename_a=None, drop_x2=False, break_root_wire=False, inner_file="grand.dsn", extra_root=""):
    """Writes grand.dsn, child.dsn and root.dsn into folder d; returns the path of root.dsn"""
    os.makedirs(d, exist_ok=True)
    write(os.path.join(d, "grand.dsn"), sheetdoc(wire((10, 10), (50, 10)) + label((20, 10), "P") + wire((10, 30), (50, 30)) + label((20, 30), "W"), hier_sheet(GRAND_PINS)))
    go = pin_offsets(os.path.join(d, "grand.dsn"), GRAND_PINS)
    gx, gy = 100, 100
    gp = (gx + go[0][0], gy + go[0][1])
    a_name = rename_a or "A"
    top = (wire((10, 10), (50, 10)) + label((20, 10), a_name) + label((40, 10), "X") +
           wire((10, 30), (50, 30)) + label((20, 30), "B") + (label((40, 30), "X") if not drop_x2 else "") +
           hs(gx, gy, "G1", "./" + inner_file) +
           wire((int(gp[0]) - 40, int(gp[1])), (int(gp[0]), int(gp[1]))) + label((int(gp[0]) - 20, int(gp[1])), "Z"))
    write(os.path.join(d, "child.dsn"), sheetdoc(top, hier_sheet(CHILD_PINS)))
    co = pin_offsets(os.path.join(d, "child.dsn"), CHILD_PINS)
    root = ""
    for (x, y, ref, na, nb) in ((100, 200, "H1", "SIG", "OUT"), (300, 200, "H2", "SIG2", "OUT2")):
        root += hs(x, y, ref, "./child.dsn")
        for off, nm in zip(co, (na, nb)):
            px, py = int(x + off[0]), int(y + off[1])
            ex = px - 40 - (7 if (break_root_wire and ref == "H1" and nm == "SIG") else 0)
            root += wire((ex, py), (px, py)) if not (break_root_wire and ref == "H1" and nm == "SIG") else wire((ex, py), (px - 10, py))
            root += label((px - 20 - (7 if (break_root_wire and ref == "H1" and nm == "SIG") else 0), py), nm)
    root += wire((200, 20), (240, 20)) + label((220, 20), "SIG") + extra_root
    write(os.path.join(d, "root.dsn"), doc(root))
    return os.path.join(d, "root.dsn")

# ------------------------------------------------------------------ the expectation, from how the design was built
def decorated(inst, name): return name if inst == 0 else "_HN_%d_%s" % (inst, name)
# instance numbers: root 0; H1, H2 found in the root's sheet (1, 2); then each of those places G1 (3, 4)
EXPECT_NETS = {
    frozenset(decorated(i, n) for i, n in ((0, "SIG"), (0, "OUT"), (1, "A"), (1, "B"), (1, "X"))),
    frozenset(decorated(i, n) for i, n in ((0, "SIG2"), (0, "OUT2"), (2, "A"), (2, "B"), (2, "X"))),
    frozenset(decorated(i, n) for i, n in ((1, "Z"), (3, "P"))),
    frozenset(decorated(i, n) for i, n in ((2, "Z"), (4, "P"))),
    frozenset([decorated(3, "W")]),
    frozenset([decorated(4, "W")]),
}
# the name each net should be given: the label at the highest level; labels below the root get the path of symbols in front
EXPECT_PREF = {
    frozenset(decorated(i, n) for i, n in ((1, "Z"), (3, "P"))): ["H1_Z"],
    frozenset(decorated(i, n) for i, n in ((2, "Z"), (4, "P"))): ["H2_Z"],
    frozenset([decorated(3, "W")]): ["H1_G1_W"],
    frozenset([decorated(4, "W")]): ["H2_G1_W"],
}
def netsets(nets):
    out = {}
    for nodes_ in nets:
        names = frozenset(n["label"] for n in nodes_ if n["label"])
        out.setdefault(names, []).append(nodes_)
    return out

base = make(os.path.join(tmp, "a"))
nets, errors, rc = nodes(base)
check("it runs", rc == 0 and nets, rc)
check("no import errors", errors == "", errors)
ns = netsets(nets)
got = set(ns)
check("the six nets, by the names in them", got == EXPECT_NETS, (sorted(map(sorted, got - EXPECT_NETS)), sorted(map(sorted, EXPECT_NETS - got))))
check("no net without a name appears", all(any(n["label"] for n in v) for v in nets), len(nets))
check("each name is in exactly one net", sum(len(set(n["label"] for n in v if n["label"])) for v in nets) == len({n["label"] for v in nets for n in v if n["label"]}))
for k, want in EXPECT_PREF.items():
    for v in ns.get(k, []):
        check("net name of %s" % sorted(k), all(n["pref"] in want for n in v), {n["pref"] for n in v})
for k in (frozenset(decorated(i, n) for i, n in ((0, "SIG"), (0, "OUT"), (1, "A"), (1, "B"), (1, "X"))),):
    for v in ns.get(k, []):
        check("net of H1's pins is named by a root label", {n["pref"] for n in v} <= {"SIG", "OUT"} and len({n["pref"] for n in v}) == 1, {n["pref"] for n in v})
for v in ns.get(frozenset(decorated(i, n) for i, n in ((0, "SIG2"), (0, "OUT2"), (2, "A"), (2, "B"), (2, "X"))), []):
    check("net of H2's pins is named by a root label", {n["pref"] for n in v} <= {"SIG2", "OUT2"} and len({n["pref"] for n in v}) == 1, {n["pref"] for n in v})
allpref = [v[0]["pref"] for v in nets]
check("every net has its own name", len(set(allpref)) == len(allpref), allpref)

# the references of the pins of placed symbols: the path of the symbols leading to them
pinrefs = sorted((n["ref"], n["pname"], n["label"]) for v in nets for n in v if n["ispin"])
want_pinrefs = sorted([
    ("H1", "A", decorated(1, "A")), ("H1", "B", decorated(1, "B")), ("H2", "A", decorated(2, "A")), ("H2", "B", decorated(2, "B")),
    ("H1_G1", "P", decorated(3, "P")), ("H2_G1", "P", decorated(4, "P"))])
check("the references of the symbols' pins", pinrefs == want_pinrefs, (pinrefs, want_pinrefs))

# ------------------------------------------------------------------ hierarchical symbols not followed
fnets, ferr, frc = nodes(base, "flatnodes")
fsets = set(frozenset(n["label"] for n in v if n["label"]) for v in fnets)
check("not followed: runs", frc == 0 and fnets, frc)
check("not followed: only the root's labels, and no pin nodes of the placed designs", all(not l.startswith("_HN_") for s in fsets for l in s) and not any(n["ispin"] for v in fnets for n in v), fsets)
check("not followed: each label of the root has its net", fsets == {frozenset(["SIG"]), frozenset(["OUT"]), frozenset(["SIG2"]), frozenset(["OUT2"])}, fsets)

# ------------------------------------------------------------------ mutations: each must change the result
def sets_of(path):
    n, e, r = nodes(path)
    return set(netsets(n)), e
m1, _ = sets_of(make(os.path.join(tmp, "m1"), rename_a="A2"))
check("mutation: a renamed label inside no longer meets pin A", m1 != EXPECT_NETS, m1)
m2, _ = sets_of(make(os.path.join(tmp, "m2"), drop_x2=True))
check("mutation: dropping the second X splits A from B inside", m2 != EXPECT_NETS and len(m2) > len(EXPECT_NETS), len(m2))
m3, _ = sets_of(make(os.path.join(tmp, "m3"), break_root_wire=True))
check("mutation: a root wire that stops short of H1's pin A leaves the pin alone", m3 != EXPECT_NETS, len(m3))
m4, e4 = sets_of(make(os.path.join(tmp, "m4"), inner_file="missing.dsn"))
check("a design that cannot be read is reported", "missing.dsn" in e4, e4)
check("a design that cannot be read: the rest is still netlisted (the root, H1 and H2 and their insides)", frozenset(decorated(i, n) for i, n in ((0, "SIG"), (0, "OUT"), (1, "A"), (1, "B"), (1, "X"))) in m4, sorted(map(sorted, m4)))
check("a design that cannot be read: no net of the missing design appears", not any(l.startswith("_HN_3_") or l.startswith("_HN_4_") for s in m4 for l in s), m4)

# ------------------------------------------------------------------ the number of levels is limited (a design that places itself)
d = os.path.join(tmp, "loop"); os.makedirs(d, exist_ok=True)
write(os.path.join(d, "self.dsn"), sheetdoc(hs(100, 100, "S1", "./self.dsn") + wire((10, 10), (50, 10)) + label((20, 10), "Q"), hier_sheet(["Q"])))
write(os.path.join(d, "top.dsn"), doc(hs(100, 100, "T1", "./self.dsn")))
lnets, lerr, lrc = nodes(os.path.join(d, "top.dsn"))
check("a design that places itself ends", lrc == 0 and "Too many levels" in lerr, (lrc, lerr))

print(f"hierarchical netlist: {checks} checks, {len(fails)} failed")
sys.exit(1 if fails else 0)
