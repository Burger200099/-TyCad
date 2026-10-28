#!/usr/bin/env python3
"""Special > Check Duplicate References... and Special > Export Symbol BoM (CSV)... on the real program (script commands 'dupcheck' and 'symbom <file>').
Oracle: a separate statement written here from the design's XML (SYMBOL / FIELD / SYMBOLDEF elements), run over sample designs and over variants made by editing references:
  - duplicates: references that more than one placed symbol has, compared ignoring case; the parts of one package (same symbol, each its own part) are not duplicates; "?" references
    are not duplicates; the report lines and their order (natural order of the reference)
  - the CSV: header, one row per kind of symbol (symbol, value, description and attribute values), quantity = distinct numbered references + unnumbered symbols, references in natural
    order, attribute columns by heading (case ignored, order met), item numbers in order of the key; quoting and doubled quotes parsed with Python's csv module
  - the status text when the references are not right, no file written for an unwritable path
  - the menu items are in mainform.lfm after Create Parts List
Needs the built program and xvfb."""
import csv, glob, io, os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Symbol BoM checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:900])
def run(lines):
    h = tempfile.mkdtemp(dir=tmp); f = os.path.join(tmp, "s.txt"); open(f, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n")
import functools
def ncmp(a, b):
    """compares two references: runs of digits by value, other characters one by one ignoring case (a digit against another character by the character)"""
    ta = re.findall(r"\d+|\D", a); tb = re.findall(r"\d+|\D", b)
    for x, y in zip(ta, tb):
        if x.isdigit() and y.isdigit():
            if int(x) != int(y): return -1 if int(x) < int(y) else 1
        elif x[0].lower() != y[0].lower(): return -1 if x[0].lower() < y[0].lower() else 1
    return (len(ta) - len(tb)) and (-1 if len(ta) < len(tb) else 1)
natural = functools.cmp_to_key(ncmp)
def numbered(r): return r.strip() != "" and "?" not in r
def read(path):
    root = ET.parse(path).getroot(); sheets = [root] if root.tag == "TinyCAD" else root.findall("TinyCAD"); rows = []
    for n, sh in enumerate(sheets):
        defs = {d.get("id"): d for d in sh.findall("SYMBOLDEF")}
        for s in sh.findall("SYMBOL"):
            d = defs[s.get("id")]; fl = s.findall("FIELD")
            attrs = [(f.get("description"), f.get("value")) for f in fl[2:] if f.get("type") != "2"]
            rows.append(dict(ref=fl[0].get("value"), value=fl[1].get("value"), sym=d.findtext("NAME") or "", desc=d.findtext("DESCRIPTION") or "", part=s.get("part", "0"), sheet=n + 1, attrs=attrs))
    return rows
def dups(rows):
    groups = {}
    for r in rows:
        if numbered(r["ref"]): groups.setdefault(r["ref"].lower(), []).append(r)
    out = []
    for k, g in groups.items():
        if len(g) < 2: continue
        bad = any(a["sym"] != b["sym"] or a["part"] == b["part"] for i, a in enumerate(g) for b in g[i + 1:])
        if bad: out.append((g[0]["ref"], len(g)))
    out.sort(key=lambda t: natural(t[0])); return out
def bom(rows):
    heads = []
    for r in rows:
        for h, _ in r["attrs"]:
            if h.lower() not in [x.lower() for x in heads]: heads.append(h)
    def key(r):
        a = [""] * len(heads)
        for h, v in r["attrs"]: a[[x.lower() for x in heads].index(h.lower())] = v
        return r["sym"] + "\x01" + r["value"] + "\x01" + r["desc"] + "".join("\x01" + x for x in a), a
    kinds = {}
    for r in rows:
        k, a = key(r); kinds.setdefault(k, dict(rows=[], attrs=a, r=r))["rows"].append(r)
    out = []
    for i, k in enumerate(sorted(kinds, key=lambda s: s.encode("utf-8")), 1):
        K = kinds[k]; seen = []; qty = 0; refs = []
        for r in K["rows"]:
            if numbered(r["ref"]):
                if r["ref"].lower() not in seen: seen.append(r["ref"].lower()); refs.append(r["ref"]); qty += 1
            else: refs.append(r["ref"]); qty += 1
        refs.sort(key=natural)
        out.append([str(i), str(qty), ", ".join(refs), K["r"]["value"], K["r"]["sym"], K["r"]["desc"]] + K["attrs"])
    return ["Item", "Quantity", "References", "Value", "Symbol", "Description"] + heads, out
def variant(src, dst, edits):
    t = open(src, encoding="utf-8", errors="surrogateescape").read(); n = 0
    for old, new in edits:
        t, c = re.subn(r"(<FIELD type='0' description='Ref' value=')%s(')" % re.escape(old), r"\g<1>%s\2" % new, t, count=1); n += c
    open(dst, "w", encoding="utf-8", errors="surrogateescape").write(t); return n
cases = [os.path.join(EX, p) for p in ["circuits/PSU.dsn", "circuits/AtTiny LED Flasher.dsn", "circuits/Attenuator.dsn", "circuits/Miscellaneous Driver Circuits.dsn", "circuits/Nistkasten.dsn",
         "circuits/Computer Operated Telescope/Dual PSU 2.dsn", "circuits/Computer Operated Telescope/Azimuth Drive Circuit.dsn", "drawings/Palletiser Infeed Lox Conveyors.dsn"]]
psu = os.path.join(EX, "circuits/PSU.dsn")
v1 = os.path.join(tmp, "v1.dsn"); variant(psu, v1, [("C2", "C1"), ("R2", "r1"), ("F2", "F?")])
cases.append(v1)
v2 = os.path.join(tmp, "v2.dsn"); tx = open(psu, encoding="utf-8", errors="surrogateescape").read().replace("value='LM350'", "value='LM350, &quot;adj&quot; reg'", 1); open(v2, "w", encoding="utf-8", errors="surrogateescape").write(tx)
cases.append(v2)
v3 = os.path.join(tmp, "v3.dsn"); variant(psu, v3, [("C2", "C1")]); tx = open(v3, encoding="utf-8", errors="surrogateescape").read()
tx, nsub = re.subn(r"(<SYMBOL id='9' pos='[^']*' part=')0('[^>]*>\s*<FIELD type='0' description='Ref' value='C1')", r"\g<1>1\2", tx, count=1); open(v3, "w", encoding="utf-8", errors="surrogateescape").write(tx)
check("test setup: the variant gave the second capacitor part 1 and the reference C1", nsub == 1, nsub)
cases.append(v3)
csvs = []
script = []
for i, c in enumerate(cases):
    o = os.path.join(tmp, "o%d.csv" % i); csvs.append(o)
    script += ["open \"%s\"" % c, "echo CASE%d" % i, "dupcheck", "symbom \"%s\"" % o]
bad = os.path.join(tmp, "nodir", "x.csv")
script += ["open " + v1, "echo BAD", "symbom " + bad]
out = run(script)
idx = [i for i, l in enumerate(out) if l.startswith("CASE") or l.startswith("BAD")]
for n, c in enumerate(cases):
    seg = out[idx[n]: idx[n + 1] if n + 1 < len(idx) else len(out)]; rows = read(c); nm = os.path.basename(c)
    got = [l[len("DUPREF "):] for l in seg if l.startswith("DUPREF ")]
    want = dups(rows)
    check(nm + ": duplicate references equal the oracle's (same references, same counts, natural order)", [(g.split(":")[0], int(re.search(r": (\d+) symbols", g).group(1))) for g in got] == want, (got, want))
    hdr, body = bom(rows)
    try: tab = list(csv.reader(io.StringIO(open(csvs[n], encoding="utf-8").read())))
    except Exception as e: tab = [[str(e)]]
    check(nm + ": the CSV header and every row equal the oracle's", tab and tab[0] == hdr and tab[1:] == body, (tab[:3], hdr, body[:3]))
    if not want: check(nm + ": the quantities add up to the symbols with a reference counted once", tab and sum(int(r[1]) for r in tab[1:]) == len({(r["ref"].lower()) for r in rows if numbered(r["ref"])}) + sum(1 for r in rows if not numbered(r["ref"])))
st = [l for l in out if l.startswith("SYMBOM ")]
check("a design with duplicate or unnumbered references warns that the quantities may be wrong; a clean one does not", "wrong" in st[-4] and "wrong" not in st[0], st)
check("an unwritable path reports it and writes nothing", st[-1].startswith("SYMBOM wrote=0") and "Cannot write" in st[-1], st[-1])
check("PSU has no duplicates", not [l for l in out[idx[0]: idx[1]] if l.startswith("DUPREF")])
check("a value with a comma and quotes is quoted and its quotes doubled (read back equal)", any(r[3] == 'LM350, "adj" reg' for r in list(csv.reader(io.StringIO(open(csvs[len(cases) - 2], encoding="utf-8").read())))[1:]) and '"LM350, ""adj"" reg"' in open(csvs[len(cases) - 2], encoding="utf-8").read())
check("the variant has C1 and R1 (case ignored) duplicated; F? is not a duplicate", dups(read(v1)) == [("C1", 2), ("R1", 2)] and [l.split(":")[0] for l in out[idx[len(cases) - 3]: idx[len(cases) - 2]] if l.startswith("DUPREF")] == ["DUPREF C1", "DUPREF R1"], dups(read(v1)))
lfm = open(os.path.join(ROOT, "src", "forms", "mainform.lfm"), encoding="utf-8").read()
a = lfm.find("object mPartsList:"); b = lfm.find("object mSymbolBom:"); c2 = lfm.find("object mDupRefs:")
check("mainform.lfm: the two items follow Create Parts List and are wired", 0 < a < b < c2 and "OnClick = DoSymbolBom" in lfm and "OnClick = DoCheckDupRefs" in lfm)
print("Symbol BoM checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
