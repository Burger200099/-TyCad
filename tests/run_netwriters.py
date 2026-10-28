"""The netlist writers other than SPICE and VHDL (TinyCAD, PADS-PCB, PADS-PCB-WITH-VALUE, Eagle, Protel, gEDA PCB and XML), against TinyCAD's NetList.cpp restated here.
The nets themselves (which pins are on which net, the labels, the numbers) are the netlist build that run_netlist.py checks against TinyCAD's own Protel files, and
are taken from nettest's node listing; the parts come from a separate reading of the design's XML (bomoracle.read_design). What is checked is everything the writers
do with them:
  - the parts: each distinct reference once, in drawing order (the XML format lists every placed symbol), the package and value looked for by name ignoring case, with
    the last of equal names winning, the defaults, the padding of a PADS reference to at least eight characters, the Eagle grid of nine to a row
  - the nets: in net number order, named by the first label or by N and six digits; which nets are left out (fewer than two pins for Protel and PADS, none with a
    reference for the others); the wrapping of a PADS or Protel line after 127 characters (characters, not bytes); the gEDA continuation after 41 pins carried over
    from one net to the next
  - the XML: printed as rapidxml prints it (a tab to a level, empty elements as <x/>, single quotes round a value with a double quote, all five characters
    escaped), and read back by an XML parser it holds the same parts, pins (with their electrical type) and nets
  - the dispatch by number (an unknown number gives TinyCAD's format), the names and extensions of the export dialog, and the file names it proposes
Over every sample design, over copies of them with awkward text put into the field values (<, >, &, both kinds of quote, accented letters) and long lines, and over
designs with no nets or no parts. Needs the built netwtest and nettest."""
import os, re, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bomoracle import read_design

EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
BUILD = os.environ.get("TC_BUILD", "build")
NW = os.path.join(BUILD, "netwtest"); NT = os.path.join(BUILD, "nettest")
tmp = tempfile.mkdtemp()
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:500])

from netoracle import unesc, read_nets, netname, parts_of, named, distinct, oracle, ETYPES, xesc, w_pads, w_gedapcb

def program(fmt, dsn, heading):
    out = os.path.join(tmp, "o.txt")
    r = subprocess.run([NW, "write", str(fmt), dsn, out, heading], capture_output=True, text=True)
    if r.returncode != 0: return None
    return open(out, "rb").read().decode("utf-8")

def compare(dsn, label, heading=None, formats=range(7)):
    heading = heading if heading is not None else dsn
    try: sheets = read_design(dsn)
    except Exception: return 0
    nets = read_nets(dsn)
    if nets is None: return 0
    parts = parts_of(sheets); n = 0
    for fmt in formats:
        got = program(fmt, dsn, heading)
        want = oracle(fmt, parts, nets, heading)
        check(f"{label} format {fmt}", got == want, (got is None, (got or "")[:160], want[:160]))
        n += 1
    return n

# ---------------------------------------------------------------- 1. every sample design, every format
files = sorted(os.path.join(r, f) for r, _, fs in os.walk(EXAMPLES) for f in fs if f.lower().endswith((".dsn", ".autosave")))
total = used = 0; withnets = 0; longlines = 0; stats = dict(pads_wrap=0, gedawrap=0, eaglerows=0)
for p in files:
    k = compare(p, os.path.basename(p))
    if k:
        used += 1; total += k
        nets = read_nets(p)
        withnets += bool(nets)
        stats["pads_wrap"] += any(sum(len(n["ref"]) + len(n["pin"]) + 2 for n in nodes if n["ref"]) > 127 for nodes in (nets or []))
        stats["gedawrap"] += "\\\n" in w_gedapcb(nets)
        stats["eaglerows"] += len(distinct(parts_of(read_design(p)))) > 9
print(f"sample designs: {used}, {total} files compared; {withnets} with nets, {stats['eaglerows']} with more than one row of Eagle parts, {stats['gedawrap']} that wrap in gEDA PCB")
check("samples were found", used >= 30, used)
check("the Eagle rows are exercised", stats["eaglerows"] >= 5, stats)


# ---------------------------------------------------------------- 1b. one very long net, to wrap lines (built by adding connectors that all carry the same label)
base = next(p for p in files if os.path.basename(p) == "Dual PSU.dsn")
btxt = open(base, encoding="utf-8", errors="replace").read()
def big_design(n, prefix, path, text='BIGNET', lens=None):
    add = []
    for k in range(n):
        x = 20 + 8 * k
        add.append(f"<SYMBOL id='1' pos='{x},222' part='0' rotate='1' can_scale='0' scale_x='1' scale_y='1'><FIELD type='0' description='Ref' value='{(prefix * lens[k]) if lens else prefix}{k + 1}' show='1' pos='1,-2'/>\n"
                   "<FIELD type='1' description='Name' value='1 Pin Connector' show='0' pos='0,0'/>\n<FIELD type='2' description='$$SPICE_PROLOG_PRIORITY' value='5' show='0' pos='0,0'/>\n"
                   "<FIELD type='1' description='Package' value='1PIN' show='0' pos='1,0.4'/>\n</SYMBOL>\n"
                   f"<WIRE a='{x},220' b='{x},210'/>\n<LABEL pos='{x},210' direction='0' font='1' color='0' style='0'>{text}</LABEL>\n")
    i = btxt.rfind("</TinyCAD>", 0, btxt.rfind("</TinyCADSheets>"))
    open(path, "w", encoding="utf-8").write(btxt[:i] + "".join(add) + btxt[i:])
for n, prefix in ((2, "Z"), (30, "Z"), (41, "Z"), (42, "Z"), (45, "Z"), (70, "Z"), (130, "Z"), (60, "\u00e9\u00e9\u00e9")):
    bp = os.path.join(tmp, f"big{n}_{len(prefix)}.dsn")
    big_design(n, prefix, bp)
    k = compare(bp, f"big net of {n} connectors, prefix {prefix}")
    bn = read_nets(bp)
    check(f"the long net of {n} was built", any(len([x for x in nodes if x['ref'].startswith(prefix)]) == n for nodes in bn), n)
    pads = w_pads(parts_of(read_design(bp)), bn, False)
    stats["pads_wrap"] += n >= 30 and "*SIGNAL*  BIGNET\n" in pads and any(len(l) > 0 and l.count(".") > 0 and len(l) < 130 for l in pads.split("\n")) and any("\n" in blk for blk in [pads.split("*SIGNAL*  BIGNET\n")[1].split("*SIGNAL*")[0].rstrip("\n")])
    stats["gedawrap"] += "\\\n" in w_gedapcb(bn)
import random
rng = random.Random(127128)
hit128 = 0
for t in range(30):
    n = rng.randint(22, 60)
    lens = [rng.randint(1, 9) for _ in range(n)]
    bp = os.path.join(tmp, f"var{t}.dsn")
    big_design(n, "Z", bp, lens=lens)
    compare(bp, f"long net with references of mixed length #{t}", formats=(1, 2, 4))
    ln = 0
    for k in range(n):
        ln += lens[k] + len(str(k + 1)) + 2          # "<ref>.1": the reference, the pin and the dot (and one for the space after the first)
        if ln == 128: hit128 += 1
        if ln > 127: ln = lens[k] + len(str(k + 1)) + 2
        ln += 1
check("the wrap is tried at exactly 127 and 128 characters", hit128 >= 3, hit128)
for txt, tag in (("(Z1,1)", "TinyCAD-style"), ("Z1-1 ", "gEDA-style")):   # (a pin entry equal to its own node's label is left out; real nodes almost never have such a label)
    bp = os.path.join(tmp, f"lab_{tag}.dsn")
    big_design(3, "Z", bp, txt)
    compare(bp, f"label that looks like a pin entry ({tag})")
check("the PADS and Protel wrapping at 127 characters is exercised", stats["pads_wrap"] >= 3, stats)
check("the gEDA continuation (after the 41st pin, carried from net to net) is exercised", stats["gedawrap"] >= 4, stats)
print("long nets: 8 designs compared in all formats")

# ---------------------------------------------------------------- 2. copies with awkward field text, long references, and an empty design
ugly = os.path.join(tmp, "ugly"); os.makedirs(ugly)
samples = [p for p in files if os.path.basename(p) in ("PSU.dsn", "Focus Bipolar Motor Circuit.dsn", "Dual PSU 2.dsn", "Attenuator.dsn", "AMP.DSN", "nanocomp6802.dsn", "WaterSensor.dsn")]
WEIRD = ["a&lt;b&amp;c&quot;d&apos;e&gt;", "x&quot;y", "caf\u00e9 &amp; cr\u00e8me", "", "  spaced  ", "tab&#9;in", "&lt;&lt;&lt;"]
made = 0
for i, p in enumerate(samples):
    t = open(p, encoding="utf-8", errors="replace").read()
    j = [0]
    def weird(m):
        j[0] += 1
        return m.group(1) + WEIRD[(i + j[0]) % len(WEIRD)] + m.group(3)
    t2 = re.sub(r"(<FIELD type='[12]' description='[^']*' value=')([^']*)('[^>]*/>)", weird, t)   # the Name and other fields of placed symbols
    # references with accents and very long pins and references
    t2 = re.sub(r"(<FIELD type='0' description='Ref' value=')([A-Za-z]+)(\d+)'", lambda m: m.group(1) + m.group(2) + ("\u00e9" if int(m.group(3)) % 3 == 0 else "") + m.group(3) + "'", t2)
    path = os.path.join(ugly, f"u{i}.dsn")
    open(path, "w", encoding="utf-8").write(t2); made += 1
    try: read_design(path)
    except Exception: continue
    compare(path, f"weird {os.path.basename(p)}", heading="C:\\x\\a&b<c>.dsn")
print(f"{made} copies with awkward text compared")
# a design that has only a sheet: no parts, no nets
empty = os.path.join(tmp, "empty.dsn")
open(empty, "w").write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<TinyCADSheets><TinyCAD><NAME>Sheet 1</NAME>\n<DETAILS><Size width='1485' height='1050'/></DETAILS>\n</TinyCAD></TinyCADSheets>\n")
k = compare(empty, "empty design")
check("the empty design was written in all seven formats", k == 7, k)
got = program(6, empty, "e.dsn")
check("an empty XML list has <parts/> and <nets/>", got == '<?xml version="1.0" encoding="utf-8"?>\n<netlist design="e.dsn">\n\t<parts/>\n\t<nets/>\n</netlist>\n', got)

# ---------------------------------------------------------------- 3. the XML read back by a parser
xml_checked = 0
for p in samples[:5]:
    nets = read_nets(p); sheets = read_design(p); parts = parts_of(sheets)
    got = program(6, p, p)
    root = ET.fromstring(got.encode("utf-8"))
    ok = root.tag == "netlist" and root.get("design") == p
    pe = root.find("parts"); ne = root.find("nets")
    ok = ok and [(e.get("ref"), e.get("name")) for e in pe] == [(r, n) for r, n, fl in parts]
    for e, (r, n, fl) in zip(pe, parts):
        ok = ok and [(a.get("name"), a.text or "") for a in e] == [(dn, val) for t, dn, val in fl[2:]]
    ok = ok and len(ne) == len(nets)
    for e, nodes in zip(ne, nets):
        pins = [(x.get("part"), x.get("name"), x.get("number"), x.get("type")) for x in e]
        want = [(n["ref"] or None, n["pname"], n["pnum"], ETYPES[n["elec"]] if 0 <= n["elec"] < 7 else None) for n in nodes if n["ispin"]]
        ok = ok and pins == want and e.get("number") == str(nodes[0]["net"])
    check(f"the XML of {os.path.basename(p)} read back by a parser holds the parts, pins and nets", ok)
    xml_checked += 1
print(f"XML read back: {xml_checked} designs")

# ---------------------------------------------------------------- 4. dispatch, names, extensions, file names
nm = [("name", "", i) for i in (-1, 0, 1, 2, 3, 4, 5, 6, 7)] + [("ext", "", i) for i in (-1, 0, 1, 2, 3, 4, 5, 6, 7)]
nm += [("default", t, 0) for t in ("C:\\a\\b.dsn", "/x/y.z/design.dsn", "", "nodot", "a.b.c", "x.")]
nm += [("change", t, i) for t in ("out.net", "out.scr", "out.net.xml", "x.net.xml", "abcd.net", "a.net", "abc.net.xml", "out", "", "a.b.c", ".net.xml", "x.net.net") for i in (0, 3, 6)]
nm += [("elec", "", i) for i in range(-1, 9)]
nm += [("escape", t, 0) for t in ("plain", "<a&b>", "\"q\" 'r'", "", "&amp;")]
open(f"{tmp}/names.txt", "w", encoding="utf-8", newline="\n").write("\n".join(f"{k}\t{t}\t{i}" for k, t, i in nm) + "\n")
r = subprocess.run([NW, "names", f"{tmp}/names.txt"], capture_output=True, text=True)
got = [l[2:] for l in r.stdout.split("\n") if l.startswith("R ")]
NAMES = ["TinyCAD", "PADS-PCB", "PADS-PCB-WITH-VALUE", "Eagle SCR", "Protel", "gEDA PCB", "XML"]
def ext(i): return ".scr" if i == 3 else ".net.xml" if i == 6 else ".net"
def default(p):
    i = p.rfind("."); return "output.net" if i < 0 else p[:i] + ".net"
def change(p, i):
    b = p.rfind(".")
    if b < 0: return p
    if b >= 4 and p[b - 4:b] == ".net": b -= 4
    return p[:b] + ext(i)
want = []
for k, t, i in nm:
    want.append(NAMES[i] if k == "name" and 0 <= i < 7 else NAMES[0] if k == "name" else ext(i) if k == "ext" else default(t) if k == "default" else change(t, i) if k == "change"
                else (ETYPES[i] if 0 <= i < 7 else "") if k == "elec" else xesc(t))
check("names, extensions and file names", got == want, [(a, b) for a, b in zip(got, want) if a != b][:4])
print(f"export dialog helpers: {len(nm)} cases")
focus = next(p for p in files if os.path.basename(p) == "Focus Bipolar Motor Circuit.dsn")
a = program(0, focus, focus); b = program(9, focus, focus); c = program(-3, focus, focus)
check("an unknown format number gives TinyCAD's format", a == b == c and a.startswith("; ====+"))
check("a design that cannot be read writes nothing and fails", subprocess.run([NW, "write", "0", os.path.join(tmp, "nope.dsn"), os.path.join(tmp, "x.out")], capture_output=True).returncode != 0)

print(f"{checks} checks, {len(fails)} failed")
sys.exit(1 if fails else 0)
