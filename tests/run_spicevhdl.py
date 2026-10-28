"""The SPICE and VHDL netlist writers (USpiceVhdl) against TinyCAD's NetList.cpp restated in tests/spiceoracle.py, and against files TinyCAD itself wrote.
Checked:
  - the helpers: _ttoi, Bus_Properties (names, ranges, members, missing numbers, an end above the start), the signal declaration and reference, the entity name taken from the path,
    the file names proposed, the error file's name, the date line
  - TinyCAD's own outputs in the examples folder: the SPICE file and its error file written for FunctionalUnit.dsn match exactly (apart from the date); the VHDL files written for 14
    designs match after net numbers are matched up (TinyCAD of that time numbered nets from 0) and the older "port(" and header; three of them were written before a port map used
    just the name of a signal that is fully used
  - every sample design, both writers, against the restatement (file and error file, and the count of errors)
  - SPICE macros: $ % @ ? and the escape in every form, conditionals with every test, nested and unfinished macros, unknown ones, a few hundred random macro soups, the prolog and
    epilog (priorities, repeated texts, empty texts, the epilog filed under the prolog priority), repeated references, blank and repeated pin names and numbers, symbols without a model
  - VHDL: buses, members, INPUT and OUTPUT symbols, pins of every electrical type, repeated pin numbers, mismatching bus sizes, unnamed nets, and designs with random
    pin types and names
Needs the built netwtest and nettest."""
import os, random, re, subprocess, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bomoracle import read_design
from netoracle import read_nets, BUILD
import spiceoracle as O

EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
NW = os.path.join(BUILD, "netwtest")
tmp = tempfile.mkdtemp()
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 14: print("  FAIL", n, str(d)[:600])

def prog_vhdl(dsn, path):
    out = os.path.join(tmp, "v.out")
    r = subprocess.run([NW, "vhdl", dsn, path, out], capture_output=True, text=True)
    return open(out, "rb").read().decode("utf-8") if r.returncode == 0 and os.path.exists(out) else None
def prog_spice(dsn, stamp, name):
    out = os.path.join(tmp, "s.out"); er = os.path.join(tmp, "s.err")
    for f in (out, er):
        if os.path.exists(f): os.remove(f)
    r = subprocess.run([NW, "spice", dsn, out, stamp, er, name], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(out): return None
    n = int(r.stdout.strip().split()[-1])
    return open(out, "rb").read().decode("utf-8"), open(er, "rb").read().decode("utf-8"), n

def load(dsn):
    try: sheets = read_design(dsn)
    except Exception: return None
    nets = read_nets(dsn)
    if nets is None: return None
    return sheets, nets, O.read_syms(dsn)
from collections import Counter
cov = Counter()
VF = ["ERROR: Duplicated pin number", "ERROR: Different BUS sizes at label", "ERROR: Different BUS sizes at IN/OUT", "ERROR: Different BUS sizes: ", "\tport(\t", "std_logic_vector", ": out std_logic",
      " downto ", "signal N", "port map (", "\tcomponent "]
SF = ["<pin '", "<attr '", "<Unknown query operation", "<Not implemented yet", "NO_MODEL found", "_N_", "\n\n", "yes", "no\n", "unconnected", "joined", "both", "only1", "only2", "neither"]
def cmp_vhdl(dsn, label, path="/work/Out.vhd"):
    L = load(dsn)
    if L is None: return 0
    sheets, nets, syms = L
    got = prog_vhdl(dsn, path); want = O.vhdl(sheets, nets, syms, path)
    for f in VF: cov["V " + f] += want.count(f)
    cov["V unnamed bus net"] += len(re.findall(r"signal N\d+: +std_logic_vector", want))
    if re.search(r"\(\d+\)[,)]", want): cov["V member"] += 1
    check(f"{label}: VHDL", got == want, (got is None, (got or "")[:300], want[:300]))
    return 1
def cmp_spice(dsn, label, name="C:\\x\\d.dsn"):
    L = load(dsn)
    if L is None: return 0
    sheets, nets, syms = L
    got = prog_spice(dsn, "STAMP", name); want = O.spice(sheets, nets, name, "STAMP")
    for f in SF: cov["S " + f] += want[0].count(f)
    for f in ("blank pin name", "blank pin number", "duplicate pin name", "duplicate pin number", "has no model", "attribute '", "pin '", "unknown query", "unimplemented"): cov["S err " + f] += want[1].count(f)
    check(f"{label}: SPICE", got == want, (got is None, (got or ("", "", 0))[0][:300], want[0][:300]))
    if got != want and got and got[1] != want[1]: check(f"{label}: SPICE error file", False, (got[1][:300], want[1][:300]))
    return 1

# ---------------------------------------------------------------- 1. helpers
H = []
H += [("atoi", t, "") for t in ("12", "   7x", "-5", "+9", "abc", "", "-", "99999999999", "-99999999999", "3.9", "  -0", "0012")]
buses = ["A", "A(7:0)", "A(3)", "A(0:0)", "A(2:5)", "A(7:", "A(7", "A(", "A()", "A(:3)", "A((3)", "A(1:2:3)", "A(1)(2:0)", "(5)", "(7:0)", "A(x:y)", "A(-1:-3)", " A (7:0) ", "A(7:0)B", "n(1)(2)", "caf\u00e9(3:1)", "D(3:0)", "Q", "N", "A(7:4)"]
for b in buses:
    for k in range(4): H.append(("bus", b, str(k)))
for b in buses:
    for k in range(4): H.append(("decl", b, str(k)))
    H.append(("ref", b, ""))
paths = ["C:\\a\\b.vhd", "/x/y.z/design.vhd", "out.vhd", "a/b/c", "a.b.c.vhd", "/dir.d/file", "\\\\srv\\sh\\n.vhd", "x.", ".vhd", "/", "d/", "caf\u00e9/\u00e9t\u00e9.vhd", "q" * 300 + ".vhd", "\u00e9" * 300, "a\\b/c.d\\e.f"]
for p in paths:
    H.append(("entity", p, "")); H.append(("vdefault", p, "")); H.append(("sdefault", p, "")); H.append(("errname", p, ""))
for p in ("", "nodot", "a.b.c", "x.", ".net", "d.d/f", "/a.b/out", "x.net", "x"):
    H.append(("vdefault", p, "")); H.append(("sdefault", p, "")); H.append(("errname", p, ""))
open(f"{tmp}/h.txt", "w", encoding="utf-8", newline="\n").write("\n".join(f"{k}\t{t}\t{a}" for k, t, a in H) + "\n")
r = subprocess.run([NW, "helpers", f"{tmp}/h.txt"], capture_output=True, text=True)
got = [l[2:] for l in r.stdout.split("\n") if l.startswith("R ")]
want = []
KINDS = ["internal", "input", "output", "dont_know"]
for k, t, a in H:
    if k == "atoi": want.append(str(O.atoi(t)))
    elif k == "bus":
        b = O.bus(t); want.append(f"{b['name']}\t{b['start']}\t{b['end']}\t{int(b['is_bus'])}")
    elif k == "decl": want.append(O.decl(O.bus(t, KINDS[int(a)])))
    elif k == "ref": want.append(O.sigref(t))
    elif k == "entity": want.append(O.entity(t))
    elif k == "vdefault": want.append(O.default_name(t, ".vhd"))
    elif k == "sdefault": want.append(O.default_name(t, ".net"))
    elif k == "errname": want.append(O.errname(t))
bad = [(H[i], got[i] if i < len(got) else None, want[i]) for i in range(len(want)) if i >= len(got) or got[i] != want[i]]
check(f"the helpers ({len(H)} cases)", len(got) == len(want) and not bad, bad[:3])
# a few facts stated outright, so the oracle itself is held to the C++
facts = [(("bus", "A(7:0)", "3"), "A\t7\t0\t1"), (("bus", "A(3)", "3"), "A\t3\t3\t1"), (("bus", "A(2:5)", "3"), "A\t2\t2\t1"), (("bus", "A", "3"), "A\t0\t0\t0"),
         (("decl", "D(3:0)", "1"), "D: in std_logic_vector(3 downto 0)"), (("decl", "Q", "2"), "Q: out std_logic"), (("decl", "N", "0"), "N:  std_logic"),
         (("ref", "A(3)", ""), "A(3)"), (("ref", "A(7:4)", ""), "A(7 downto 4)"), (("entity", "C:\\a\\b.vhd", ""), "b"), (("errname", "x.net", ""), "x.txt"), (("errname", "x", ""), ".txt")]
for key, w in facts:
    i = H.index((key[0], key[1], key[2]))
    check(f"helper fact {key}", got[i] == w, (got[i], w))
with open(f"{tmp}/st.txt", "w") as fh: fh.write("stamp\n")
noTZ = {k: v for k, v in os.environ.items() if k != "TZ"}      # (FPC reads the zone from the system, or from TZ only when it is written :name)
r = subprocess.run([NW, "helpers", f"{tmp}/st.txt"], capture_output=True, text=True, env=noTZ)
st = r.stdout.strip()[2:]
zone = subprocess.run(["date", "+%z"], capture_output=True, text=True, env=noTZ).stdout.strip()
check("the date line has TinyCAD's shape and this computer's zone", re.fullmatch(r"\d\d/\d\d/\d\d at \d\d:\d\d:\d\d [+-]\d{4}", st) and st.endswith(zone), (st, zone))

# ---------------------------------------------------------------- 2. TinyCAD's own outputs
NIB = None
for r_, _, fs in os.walk(EXAMPLES):
    if "FunctionalUnit - Spice.net" in fs: NIB = r_
check("the examples hold TinyCAD's own SPICE and VHDL outputs", NIB is not None)
if NIB:
    realname = "C:\\Projects\\TinyCAD-SVN\\TinyCAD\\VHDL Netlister\\examples\\nibbles\\FunctionalUnit.dsn"
    dsn = os.path.join(NIB, "FunctionalUnit.dsn")
    realnet = open(os.path.join(NIB, "FunctionalUnit - Spice.net"), "rb").read().decode("utf-8").replace("\r\n", "\n")
    realerr = open(os.path.join(NIB, "FunctionalUnit - Spice.txt"), "rb").read().decode("utf-8").replace("\r\n", "\n")
    got = prog_spice(dsn, "STAMP", realname)
    check("the SPICE file for FunctionalUnit is the one TinyCAD wrote (but for the date)", got is not None and got[0].split("\n", 1)[1] == realnet.split("\n", 1)[1], (got or ("",))[0][:200])
    check("its first line has the date", realnet.startswith("* Schematics Netlist created on ") and got[0].startswith("* Schematics Netlist created on STAMP *\n"))
    check("the error file is the one TinyCAD wrote", got is not None and got[1] == realerr, (got or ("", ""))[1][:300])
    out0 = os.path.join(tmp, "f0.net")
    subprocess.run([NW, "write", "0", dsn, out0, realname], capture_output=True, text=True)
    def renum(t):
        m = {}
        def f(x):
            m.setdefault(x.group(0), "N%06d" % len(m)); return m[x.group(0)]
        return re.sub(r"'N\d{6}'", f, t)
    realtiny = open(os.path.join(NIB, "FunctionalUnit.net"), "rb").read().decode("utf-8").replace("\r\n", "\n")
    ours = open(out0, "rb").read().decode("utf-8")
    check("TinyCAD's own-format netlist for FunctionalUnit matches (once the unnamed nets are numbered from 0, as that TinyCAD did)", renum(ours) == renum(realtiny) and ours != realtiny, (ours[-300:], realtiny[-300:]))
    def norm(t):
        t = t.replace("-- File Created by TinyCad VHDL\n", "")
        t = re.sub(r"port\(\t?", "port(", t)
        m = {}
        def f(x):
            m.setdefault(x.group(0), "n%d" % len(m)); return m[x.group(0)]
        return re.sub(r"\bN\d\d+\b", f, t)
    def short(t):                 # TinyCAD of that time wrote a range for a port map entry whose signal is used in full
        return "\n".join(re.sub(r"(\w+)\(\d+ downto \d+\)", r"\1", l) if "port map" in l else l for l in t.split("\n"))
    exact = shortened = 0
    for f in sorted(os.listdir(NIB)):
        if not f.endswith(".dsn"): continue
        b = f[:-4]; ref = os.path.join(NIB, b + ".vhd")
        if not os.path.exists(ref): continue
        got = prog_vhdl(os.path.join(NIB, f), "C:\\x\\" + b + ".vhd")
        real = open(ref, "rb").read().decode("utf-8", "replace").replace("\r\n", "\n")
        if norm(got) == norm(real): exact += 1
        elif short(norm(got)) == short(norm(real)): shortened += 1
        else: check(f"VHDL for {b} is what TinyCAD wrote", False, (norm(got)[:300], norm(real)[:300]))
    check("14 VHDL files compare with TinyCAD's own", exact + shortened == 14 and exact >= 11, (exact, shortened))
    print(f"TinyCAD's own outputs: 1 SPICE file and its error file, {exact + shortened} VHDL files ({shortened} written before the shortened port map)")

# ---------------------------------------------------------------- 3. every sample design
files = sorted(os.path.join(r, f) for r, _, fs in os.walk(EXAMPLES) for f in fs if f.lower().endswith((".dsn", ".autosave")))
nv = ns = 0; errs_seen = 0
for p in files:
    nv += cmp_vhdl(p, os.path.basename(p), "/w/" + os.path.basename(p) + ".vhd")
    k = cmp_spice(p, os.path.basename(p)); ns += k
    if k:
        L = load(p); errs_seen += O.spice(L[0], L[1], "x", "S")[2]
print(f"sample designs: {nv} VHDL, {ns} SPICE files compared; {errs_seen} SPICE errors reported in all")
check("samples were found", nv >= 30 and ns >= 30, (nv, ns))
check("SPICE errors are exercised by the samples", errs_seen >= 50, errs_seen)

# ---------------------------------------------------------------- 4. crafted designs
base = next(p for p in files if os.path.basename(p) == "Focus Bipolar Motor Circuit.dsn")
btxt = open(base, encoding="utf-8", errors="replace").read()
def xesc(s): return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("'", "&apos;").replace('"', "&quot;").replace("\r", "&#13;").replace("\n", "&#10;").replace("\t", "&#9;")
def field(name, val): return f"<FIELD type='2' description='{xesc(name)}' value='{xesc(val)}' show='0' pos='0,0'/>\n"
SYM = re.compile(r"(<SYMBOL id='[^']*'[^>]*>.*?)(</SYMBOL>)", re.S)
def with_fields(txt, per_symbol):
    k = [0]
    def f(m):
        add = per_symbol(k[0]); k[0] += 1
        return m.group(1) + add + m.group(2)
    return SYM.sub(f, txt)
def write(name, txt):
    p = os.path.join(tmp, name); open(p, "w", encoding="utf-8").write(txt); return p

MODELS = ["R%(1) %(2) 1k", "$(ref) %(1) %(2) $(Name)", "X$(refnum) @(1) @(2) $(Package)", "?(connected(1),yes,no)", "?(not_connected(2),unconnected,joined)", "?(defined(Package),has,none)",
          "?(not_defined(Package),none,has)", "?(empty(Package),E,F)", "?(not_empty(Package),F,E)", "?(defined(Nope),a,b) end", "?(bogus(1),a,b)", "?(noparen,a,b)",
          "?(include(<x.vhd>),a,b)", "?(connected(1),?(connected(2),both,only1),?(connected(2),only2,neither))", "a\\%b\\@c\\$d\\?e\\\\f", "100% $ @ ? tail", "%(Q) $(Q) @(Q) %(nothere)",
          "?(connected(1),%(1)\\,x,y)", "?(defined(Package),,else)", "?(defined(Package))", "?(defined(Package),only)", "%(1", "line1\r\nline2\r\n", "$($$SPICE_PROLOG_PRIORITY)",
          "?(empty(Ref),a,b)", "$(REF) $(Ref) $(refNUM)", "%(2)%(1)%(2)", "@(1)@(2)", "caf\u00e9 %(1) \u00e9", "?( defined ( Package ) ,yes,no)", "?(connected( 1 ),y,n)", "", "$(package) $(NAME) $(pAcKaGe) $(REFNUM) $(Ref)"]
def models(i): return field("$$SPICE", MODELS[i % len(MODELS)])
p1 = write("models.dsn", with_fields(btxt, models))
cmp_spice(p1, "every macro form on the Focus circuit")
g = prog_spice(p1, "S", "d"); L = load(p1)
# priorities, prologs and epilogs
def pro(i):
    s = ""
    if i % 3 == 0: s += field("$$SPICE_PROLOG", ".param p%d=1\n.lib x" % (i % 4))
    if i % 4 == 1: s += field("$$SPICE_EPILOG", ".end%d" % (i % 3))
    if i % 5 == 2: s += field("$$SPICE_PROLOG_PRIORITY", str((i * 3) % 12 - 1))
    if i % 7 == 3: s += field("$$SPICE_EPILOG_PRIORITY", str(i % 10))
    if i % 6 == 4: s += field("$$SPICE_PROLOG", "%(1) $(Name) ?(defined(Package),p,q)")
    if i % 9 == 5: s += field("$$SPICE_PROLOG_PRIORITY", " 8abc")
    if i % 11 == 6: s += field("$$spice_epilog", "late %(9)")
    if i % 8 == 1: s += field("$$SPICE_PROLOG_PRIORITY", str(9 + (i // 8) % 2)) + field("$$SPICE_PROLOG", "edge %d" % ((i // 8) % 2))
    return s + models(i)
p2 = write("pro.dsn", with_fields(btxt, pro))
cmp_spice(p2, "prolog and epilog with priorities")
g = prog_spice(p2, "S", "d")
check("priorities put the prolog lines in order and the epilog lines in reverse", g is not None and g[0].count("\n") > 20 and ".param p1=1" in g[0], g and g[0][:300])
# the model field is found by its exact name: "$$spice" is not "$$SPICE"
p2b = write("lower.dsn", with_fields(btxt, lambda i: field("$$spice", "lower%d" % i) if i % 2 == 0 else models(i)))
cmp_spice(p2b, "model field names in other case")
g = prog_spice(p2b, "S", "d")
check("a field named in another case is not the model", g is not None and "NO_MODEL found" in g[0] and "lower" not in g[0], g and g[0][:200])
# repeated references, blank references
cnt = [0]
def rep(m):
    cnt[0] += 1
    n = cnt[0]
    if n % 5 == 0: return m.group(1) + "U1" + m.group(3)
    if n % 11 == 0: return m.group(1) + m.group(3)
    return m.group(0)
p3 = write("dups.dsn", with_fields(re.sub(r"(<FIELD type='0' description='Ref' value=')([^']*)('[^>]*/>)", rep, btxt), models))
cmp_spice(p3, "repeated and blank references")
# pin names and numbers: repeated, blank
txt = btxt
cnt = [0]
def pins(m):
    cnt[0] += 1
    n = cnt[0]
    num = "" if n % 7 == 0 else "1" if n % 4 == 0 else m.group(2)
    return m.group(1) + num + m.group(3) + ("" if n % 3 == 0 else "P%d" % (n % 3)) + "</PIN>"
txt = re.sub(r"(<PIN [^>]*number=')([^']*)('[^>]*>)([^<]*)</PIN>", pins, txt)
p4 = write("pins.dsn", with_fields(txt, models))
cmp_spice(p4, "blank and repeated pin names and numbers")
g = prog_spice(p4, "S", "d")
check("those errors are reported", g is not None and "duplicate pin name" in g[1] and "duplicate pin number" in g[1] and "blank pin number" in g[1] and "blank pin name" in g[1], g and g[1][:300])
# wires taken out of the circuit at random, so pins dangle and nets split in every way
rngw = random.Random(4242)
for t in range(16):
    cut = re.sub(r"<WIRE a='[^']*' b='[^']*'/>\n?", lambda m: "" if rngw.random() < 0.2 else m.group(0), btxt)
    cmp_spice(write(f"cut{t}.dsn", with_fields(cut, lambda i: models(i + t))), f"wires removed #{t}")
# random macro soup
rng = random.Random(20260125)
ALPHA = list("%@$?\\(),") * 3 + list("abc123 \n\r") + ["ref", "Name", "Package", "defined(", "connected(", "empty(", "not_empty(", "(1)", "(2)", "(Package)", "1", "2", "\u00e9", "include(x)"]
soup_ok = 0
for t in range(12):
    ms = ["".join(rng.choice(ALPHA) for _ in range(rng.randint(0, 40))) for _ in range(60)]
    p = write(f"soup{t}.dsn", with_fields(btxt, lambda i: field("$$SPICE", ms[i % 60]) + (field("$$SPICE_PROLOG", ms[(i * 7) % 60]) if i % 4 == 0 else "")))
    soup_ok += cmp_spice(p, f"random macro soup #{t}")
print(f"SPICE crafted: macro forms, priorities, duplicates, {soup_ok * 60} random macro soups")

# ---------------------------------------------------------------- 5. crafted VHDL designs
nib = [os.path.join(NIB, f) for f in sorted(os.listdir(NIB)) if f.endswith(".dsn")] if NIB else []
rng = random.Random(8675309)
vt = 0
for p in nib:
    cmp_vhdl(p, "nibbles " + os.path.basename(p), "C:\\w\\" + os.path.basename(p)[:-4] + ".vhd"); vt += 1
for t in range(60):
    p = rng.choice(nib)
    txt = open(p, encoding="utf-8", errors="replace").read()
    mode = t % 4
    def elec(m):
        return m.group(1) + "elec='%d'" % rng.choice((0, 0, 1, 1, 2, 3, 4, 5, 6)) + m.group(2)
    if mode in (0, 2): txt = re.sub(r"(<PIN [^>]*?)elec='\d'([^>]*>)", elec, txt)
    NAMES = ["D(3:0)", "Q(1)", "X", "Y(7:4)", "", "A(3:0)", "B(0)", "Z(2:0)"]
    if mode in (1, 2): txt = re.sub(r"(<PIN [^>]*>)([^<]*)</PIN>", lambda m: m.group(1) + (rng.choice(NAMES) if rng.random() < (0.5 if t < 20 else 0.9) else m.group(2)) + "</PIN>", txt)
    if t % 3 == 0: txt = re.sub(r"<WIRE a='[^']*' b='[^']*'/>\n?", lambda m: "" if rng.random() < 0.25 else m.group(0), txt)
    if t % 5 == 0: txt = re.sub(r"<LABEL [^>]*>[^<]*</LABEL>\n?", lambda m: m.group(0) if rng.random() < 0.5 else "", txt)
    if mode == 3:
        txt = re.sub(r"(<PIN [^>]*number=')(\d+)(')", lambda m: m.group(1) + (m.group(2) if rng.random() < 0.7 else "1") + m.group(3), txt)
        txt = re.sub(r"(<FIELD type='1' description='Name' value=')(?:[^']*)(')", lambda m: m.group(1) + rng.choice(("INPUT", "OUTPUT", "Cell")) + m.group(2) if rng.random() < 0.2 else m.group(0), txt)
    q = write(f"vh{t}.dsn", txt)
    vt += cmp_vhdl(q, f"random variation #{t} of {os.path.basename(p)}", rng.choice(("C:\\o\\v.vhd", "/tmp/dir.x/ent.vhd", "plain")))
print(f"VHDL crafted: {vt} designs compared")
# INPUT / OUTPUT symbols with bus references on the Focus circuit: rename every third connector
cnt = [0]
def io(m):
    cnt[0] += 1
    nm = "INPUT" if cnt[0] % 3 == 1 else "OUTPUT" if cnt[0] % 3 == 2 else m.group(2)
    return m.group(1) + nm + m.group(3)
txt = re.sub(r"(<FIELD type='1' description='Name' value=')(1 Pin Connector)('[^>]*/>)", io, btxt)
cnt = [0]
def busref(m):
    cnt[0] += 1
    return m.group(1) + ("P(%d:0)" % (cnt[0] % 4) if cnt[0] % 5 == 0 else "S(%d)" % cnt[0] if cnt[0] % 5 == 1 else m.group(2)) + m.group(3)
txt = re.sub(r"(<FIELD type='0' description='Ref' value=')([^']*)('[^>]*/>)", busref, txt)
q = write("io.dsn", txt)
cmp_vhdl(q, "INPUT and OUTPUT symbols with bus references")
v = prog_vhdl(q, "x.vhd")
check("INPUT and OUTPUT symbols give the entity ports", v is not None and "\tport(\t" in v and ": in std_logic" in v and ": out std_logic" in v, (v or "")[:300])
need = {"V ERROR: Duplicated pin number": 3, "V ERROR: Different BUS sizes at label": 3, "V ERROR: Different BUS sizes at IN/OUT": 1, "V ERROR: Different BUS sizes: ": 3, "V \tport(\t": 20, "V std_logic_vector": 50, "V : out std_logic": 20,
        "V  downto ": 50, "V unnamed bus net": 3, "V member": 10, "S <pin '": 5, "S <attr '": 5, "S <Unknown query operation": 5, "S <Not implemented yet": 3, "S NO_MODEL found": 5, "S _N_": 20, "S \n\n": 20,
        "S yes": 3, "S unconnected": 1, "S joined": 2, "S both": 1, "S only1": 1, "S only2": 1, "S neither": 1, "S err blank pin name": 5, "S err blank pin number": 3, "S err duplicate pin name": 3,
        "S err duplicate pin number": 3, "S err has no model": 5, "S err attribute '": 5, "S err pin '": 5, "S err unknown query": 3, "S err unimplemented": 2}
low = {k: cov[k] for k, v in need.items() if cov[k] < v}
check("every kind of output and error was reached by some design", not low, low)

print(f"{checks} checks, {len(fails)} failed")
sys.exit(1 if fails else 0)
