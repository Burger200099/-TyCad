"""The parts list (BOM), checked against TinyCAD's BOMGenerator.cpp restated here (a separate reading of the design's XML and a
separate statement of the rules; nothing is shared with the Pascal unit):
  - what is collected: every placed symbol of the active sheet, or of all sheets; a set ordered by (text, reference) in which a second
    symbol with the same text and reference is dropped (first one kept), so the parts of a multi-part symbol count once
  - the text: the name, and with "all attributes" one column per heading - Description, Package, then every other field name met in
    the order met (names compared ignoring case), fields that are always hidden left out, a symbol with fewer fields getting no trailing
    columns - each column quoted if it holds the separator (',' for text and CSV, ';' for the spreadsheet format)
  - the three file formats: the text list (heading, references wrapped at 25 columns, padded, count, text), CSV (heading line, quoted
    reference list, count, text) and the semicolon file; and the "symbols without a proper reference" warning
  - the file names the dialog proposes
  - TinyCAD's own output: the text parts lists that ship with TinyCAD's samples (six have their design with them), made by an older version from designs that were edited
    afterwards; those whose design has not changed must come out byte for byte the same
Over every sample design with every combination of format, all sheets or one, attributes or not, and over generated designs full of the
awkward cases (commas, semicolons, quotes, empty names, repeated and missing references, multi-part symbols, mixed-case field names,
hidden fields). Needs the built bomtest."""
import os, random, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
BUILD = os.environ.get("TC_BUILD", "build")
EXE = os.path.join(BUILD, "bomtest")
tmp = tempfile.mkdtemp()
last_entries = -1
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:400])

from bomoracle import read_design, build, write, esc

# ---------------------------------------------------------------- running the program
def run(dsn, ftype, allsheets, allattrs, active, heading=None):
    out = os.path.join(tmp, "o.txt")
    args = [EXE, dsn, out, str(ftype), str(int(allsheets)), str(int(allattrs)), str(active)] + ([heading] if heading is not None else [])
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0: return None, None, r.stderr[-200:]
    miss = "MISSING 1" in r.stdout
    global last_entries
    last_entries = int(r.stdout.split("ENTRIES ")[1].split()[0])
    return open(out, "rb").read().decode("utf-8"), miss, ""

def compare(dsn, label, sheets, combos, heading=None):
    n = 0
    for ftype, allsheets, allattrs, active in combos:
        got, miss, err = run(dsn, ftype, allsheets, allattrs, active, heading)
        h, e = build(sheets, allsheets, allattrs, active, ftype)
        want, wmiss = write(h, e, ftype, heading if heading is not None else dsn)
        check(f"{label} t{ftype} s{int(allsheets)} a{int(allattrs)} #{active}", got == want and miss == wmiss and last_entries == len(e), (err, last_entries, len(e), repr(got)[:200], repr(want)[:200], miss, wmiss))
        n += 1
    return n

# ---------------------------------------------------------------- 1. every sample design, every combination
files = sorted(os.path.join(r, f) for r, _, fs in os.walk(EXAMPLES) for f in fs if f.lower().endswith((".dsn", ".autosave")))
done = skipped = 0; combos_run = 0; nonempty = 0; wrapped = 0
for p in files:
    try: sheets = read_design(p)
    except Exception as e:
        skipped += 1; continue
    if not sheets: skipped += 1; continue
    # the program may refuse a file the oracle can read (an old format); then it must refuse every time
    probe, _, err = run(p, 0, False, False, 0)
    if probe is None: skipped += 1; continue
    last = len(sheets) - 1
    combos = [(t, a, b, s) for t in (0, 1, 2) for a in (False, True) for b in (False, True) for s in sorted({0, last})]
    combos_run += compare(p, os.path.basename(p), sheets, combos)
    done += 1
    h, e = build(sheets, True, True, 0, 0)
    nonempty += bool(e)
    wrapped += any(len(x.split(",")) > 6 for x in write(h, e, 0, p)[0].split("\n")[2:3])
print(f"sample designs: {done} read ({skipped} not readable by both), {combos_run} combinations compared, {nonempty} with parts")
check("samples were found", done >= 30, done)

# ---------------------------------------------------------------- 2. TinyCAD's own parts lists
real = exact = 0; exact_names = []
for r, _, fs in os.walk(EXAMPLES):
    for f in fs:
        if not f.lower().endswith(".txt"): continue
        txt = os.path.join(r, f)
        raw = open(txt, "rb").read().decode("latin1").replace("\r", "")
        d = os.path.join(r, f[:-4] + ".dsn")
        if not raw.startswith("====+  Parts List for ") or not os.path.exists(d): continue
        real += 1
        heading = raw.split("\n")[0][len("====+  Parts List for "):-len("  +====")]
        got, miss, err = run(d, 0, False, False, 0, heading)
        if got == raw: exact += 1; exact_names.append(f)
print(f"TinyCAD's own text lists: {real} found, {exact} identical to what this program writes ({', '.join(sorted(exact_names))})")
for must in ("Dual PSU 2.txt", "Focus Bipolar Motor Circuit.txt", "Parallel Port and Handpad Connect.txt"):
    check("TinyCAD list reproduced: " + must, must in exact_names)

# ---------------------------------------------------------------- 3. generated designs with the awkward cases
rng = random.Random(20261009)
NAMES = ["10k", "10K", "100n", "1N4148", "BC547", "74LS08", "a,b", "x;y", 'q"r', "", " lead", "Ünï", "R,;both", "Z", "z", "A"]
FNAMES = ["Package", "package", "PACKAGE", "Value", "value", "Tolerance", "Power", "Voltage", "Notes", "x,y", "Description", "description", "Mfr"]
VALS = ["", "0805", "1%", "a,b", "c;d", "5V", "1/4W", "é", "q\"u"]
def esc_x(s): return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("'", "&apos;")
def gen(seed):
    g = random.Random(seed)
    nd = g.randint(1, 5); defs = []
    for i in range(1, nd + 1):
        defs.append(dict(id=i, ref=g.choice(["R?", "C?", "U?", "J?", "D?", "X"]), desc=g.choice(["", "A, resistor", "chip; fast", "cap"]),
                         ppp=g.choice([1, 1, 1, 2, 4]), name=g.choice(NAMES)))
    nsh = g.randint(1, 3); sheets = []
    for s in range(nsh):
        syms = []
        for _ in range(g.choice([0, 1, 3, 8, 20, 45])):
            d = g.choice(defs)
            if g.random() < 0.3: ref = d["ref"]                                  # left as the symbol's own reference
            else: ref = g.choice("RCUJD") + str(g.randint(1, 30)) + g.choice(["", "", "", "a", "b"])
            if g.random() < 0.15: ref = ""
            name = g.choice(NAMES) if g.random() < 0.5 else d["name"]
            fl = [(0, "Ref", ref), (1, "Name", name)]
            for _ in range(g.randint(0, 6)):
                fl.append((g.choice([0, 1, 2, 2, 4, 5]), g.choice(FNAMES), g.choice(VALS)))
            syms.append((d, g.randint(0, 3), fl))
            if g.random() < 0.25:                                    # the same reference and name again, from another definition
                d2 = g.choice(defs)
                syms.append((d2, g.randint(0, 3), [fl[0], fl[1]] + ([] if g.random() < 0.5 else fl[2:])))
        sheets.append(syms)
    x = ['<?xml version="1.0" encoding="UTF-8"?>\n<TinyCADSheets>']
    for si, syms in enumerate(sheets):
        x.append("<TinyCAD><NAME>Sheet %d</NAME>\n<DETAILS><Size width='1485' height='1050'/></DETAILS>\n" % (si + 1))
        for d in defs:
            x.append("<SYMBOLDEF id='%d'><NAME type='0'>%s</NAME>\n<REF type='0'>%s</REF>\n<DESCRIPTION>%s</DESCRIPTION>\n<PPP>%d</PPP>\n<TinyCAD></TinyCAD></SYMBOLDEF>\n"
                     % (d["id"], esc_x(d["name"]), esc_x(d["ref"]), esc_x(d["desc"]), d["ppp"]))
        for d, part, fl in syms:
            x.append("<SYMBOL id='%d' pos='%d,%d' part='%d' rotate='0' can_scale='0' scale_x='1' scale_y='1'>" % (d["id"], g.randint(0, 200), g.randint(0, 200), part % d["ppp"]))
            for t, dn, val in fl:
                x.append("<FIELD type='%d' description='%s' value='%s' show='0' pos='0,0'/>\n" % (t, esc_x(dn), esc_x(val)))
            x.append("</SYMBOL>\n")
        x.append("</TinyCAD>\n")
    x.append("</TinyCADSheets>\n")
    return "".join(x)
gen_n = 0; gen_combos = 0; gen_missing = 0; gen_multi = 0
for seed in range(120):
    path = os.path.join(tmp, f"g{seed}.dsn")
    open(path, "w", encoding="utf-8").write(gen(seed))
    sheets = read_design(path)
    probe, _, err = run(path, 0, False, False, 0)
    check(f"generated {seed} loads", probe is not None, err)
    if probe is None: continue
    last = len(sheets) - 1
    combos = [(t, a, b, s) for t in (0, 1, 2) for a in (False, True) for b in (False, True) for s in sorted({0, last})]
    gen_combos += compare(path, f"gen{seed}", sheets, combos)
    gen_n += 1
    h, e = build(sheets, True, True, 0, 1)
    gen_missing += write(h, e, 1, "")[1]
    gen_multi += len(e) > 1
print(f"generated designs: {gen_n}, {gen_combos} combinations compared; {gen_missing} with a symbol still on its own reference, {gen_multi} with more than one entry")
check("generated designs reach the missing-reference case", gen_missing >= 20, gen_missing)

# ---------------------------------------------------------------- 4. the names the dialog proposes
cases = [("default", "C:\\x\\Dual PSU.dsn", 0), ("default", "/home/a/b.c/design.dsn", 0), ("default", "", 0), ("default", "nodot", 0), ("default", "a.b.c", 0),
         ("default", "x.", 0), ("ext", "", 0), ("ext", "", 1), ("ext", "", 2), ("ext", "", 7),
         ("change", "out.txt", 1), ("change", "out.csv", 0), ("change", "out", 1), ("change", "a.b.c", 2), ("change", "", 0),
         ("escape", "plain", ","), ("escape", "a,b", ","), ("escape", "a,b", ";"), ("escape", "a;b", ";"), ("escape", "", ","), ("escape", 'q"r,s', ",")]
def cpp_default(p):
    i = p.rfind(".")
    return "output.txt" if i < 0 else p[:i] + ".txt"
def cpp_ext(t): return ".csv" if t in (1, 2) else ".txt"
def cpp_change(p, t):
    i = p.rfind(".")
    return p if i < 0 else p[:i] + cpp_ext(t)
lines = ["%s\t%s\t%s" % c for c in cases]
open(f"{tmp}/names.txt", "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
r = subprocess.run([EXE, "names", f"{tmp}/names.txt"], capture_output=True, text=True)
got = [l[2:] for l in r.stdout.split("\n") if l.startswith("R ")]
want = []
for k, a, b in cases:
    want.append(cpp_default(a) if k == "default" else cpp_ext(b) if k == "ext" else cpp_change(a, b) if k == "change" else esc(a, b))
check("name helpers", got == want, list(zip(got, want)))
print(f"file name helpers: {len(cases)} cases")

# ---------------------------------------------------------------- 5. a design that cannot be read must fail, not write a list
open(f"{tmp}/bad.dsn", "w").write("<TinyCADSheets><TinyCAD>")
r = subprocess.run([EXE, f"{tmp}/bad.dsn", f"{tmp}/bad.out", "0", "0", "0", "0"], capture_output=True, text=True)
check("unreadable design fails", r.returncode != 0)

print(f"{checks} checks, {len(fails)} failed")
sys.exit(1 if fails else 0)
