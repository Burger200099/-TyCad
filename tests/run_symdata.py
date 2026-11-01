#!/usr/bin/env python3
"""Symbol Text (tool 'symboltext', tag SYMTEXT) and Special > Export Symbol Data (CSV)... (script command 'symdata <file>') on the real program.
Checks:
  - placing symbol text with the tool: a TDrawSymbolText is selected, setprop sym.ref / sym.name change its Ref and Name fields, the saved file has SYMTEXT elements (id 0, three fields)
  - a click on the text selects it, a click far away does not
  - symbol text is not a symbol for the other reports: the Symbol BoM and the duplicate check ignore it
  - the report, on designs made by adding SYMTEXT elements with other field sets to a sample design: the CSV equals one built here from the XML in two passes (the oracle lists every
    heading first, then puts each value under its heading): Reference first, then every field heading (hidden fields too, case ignored, order first met, a heading used twice by one object
    numbered "x (2)"), then Sheet, Sheet name, Kind, Symbol; rows in natural order of reference, none last; values quoted with commas and quotes parsed by Python's csv module
  - each value is under its own heading when objects have different field sets (the point of the two passes)
  - a file that cannot be written gives wrote=0; the menu item is in mainform.lfm after the Symbol BoM item
Needs the built program and xvfb."""
import csv, functools, io, os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Symbol data checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:900])
def run(lines):
    h = tempfile.mkdtemp(dir=tmp); f = os.path.join(tmp, "s.txt"); open(f, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n")
def ncmp(a, b):
    ta = re.findall(r"\d+|\D", a); tb = re.findall(r"\d+|\D", b)
    for x, y in zip(ta, tb):
        if x.isdigit() and y.isdigit():
            if int(x) != int(y): return -1 if int(x) < int(y) else 1
        elif x[0].lower() != y[0].lower(): return -1 if x[0].lower() < y[0].lower() else 1
    return (len(ta) - len(tb)) and (-1 if len(ta) < len(tb) else 1)
natural = functools.cmp_to_key(ncmp)

# ---- placing, saving, selecting
a_dsn = os.path.join(tmp, "a.dsn"); a_csv = os.path.join(tmp, "a.csv")
out = run(["newdoc A4", "tool symboltext", "clickmm 50 50", "setprop sym.name Pump", "setprop sym.ref P1", "tool symboltext", "clickmm 100 50", "setprop sym.name Valve",
           "savedocas " + a_dsn, "tool select", "clickmm 200 150", "symdata " + a_csv])
check("the tool places a symbol text and selects it", sum("selected 1 [TDrawSymbolText]" in l for l in out) == 2, out[:8])
check("setprop reaches the Ref and Name fields", "SETPROP sym.name=Pump" in out and "SETPROP sym.ref=P1" in out, out[:8])
root = ET.parse(a_dsn).getroot(); st = root.iter("SYMTEXT"); st = list(root.iter("SYMTEXT"))
check("the file has two SYMTEXT elements, symbol 0, three fields each", len(st) == 2 and all(s.get("id") == "0" and len(s.findall("FIELD")) == 3 for s in st), len(st))
check("the saved fields hold what was typed (Ref P1 hidden, Name Pump shown)", [f.get("value") for f in st[0].findall("FIELD")][:2] == ["P1", "Pump"] and st[0].findall("FIELD")[0].get("show") == "0" and st[0].findall("FIELD")[1].get("show") == "1")
check("no SYMBOL element is made", not list(root.iter("SYMBOL")))
check("a click far from the text selects nothing", any(l.startswith("CLICK 200,150") and "selected 0" in l for l in out), [l for l in out if l.startswith("CLICK 200")])

# ---- a click on the text selects it (found by trying points round the placement)
hit = run(["open " + a_dsn] + ["clickmm %s %s" % (50 + dx, 50 + dy) for dx in (1, 3, 6) for dy in (-3, -1, 1, 3)])
check("a click on the text selects the symbol text", any("selected 1 [TDrawSymbolText]" in l for l in hit), [l for l in hit if l.startswith("CLICK")][:6])

# ---- the properties frame of a symbol text: the symbol frame without scale / resize / power; the parameter list adds fields
fo = run(["newdoc A4", "registerframe x all", "tool symboltext", "frameinfo tool", "clickmm 80 50", "frameinfo sel", "symlist sel open", "symlist sel rows", "symlist sel add", "symlist sel state"])
fi = [l for l in fo if l.startswith("FRAMEINFO")]
check("the symbol text uses the symbol frame with no problems, for the tool and for the selection", sum(l.startswith("FRAMEINFO TfmSymbols") and "problems=0" in l for l in fi) == 2, fi)
check("its frame has no resize or power editor (they are hidden: not bound)", not any("sym.canscale" in l or "sym.showpower" in l for l in fi), fi)
check("the parameter list shows Name and Other and 'add' gives a third row (the new row is selected: Delete is on and its value is being edited)", "SYMLIST rows Name|Yes|Symbol text ## Other|No|" in fo and "SYMLIST state visible=1 delete=1 editing=1 rows=3" in fo, [l for l in fo if l.startswith("SYMLIST")])

# ---- the text box of the tool's panel: the text typed there is the text of what is placed; with none, a placed one still shows something (an empty one could not be seen or clicked)
t_csv = os.path.join(tmp, "t.csv")
to = run(["newdoc A4", "registerframe x all", "tool symboltext", "frameinfo tool", "clickmm 40 40", "frameinfo sel", "tool symboltext", "frameact tool edSymbolText text Pump 7", "clickmm 80 40", "clickmm 120 40", "symdata " + t_csv])
tf = [l for l in to if l.startswith("FRAMEINFO")]
check("the tool's panel has the text box (edSymbolText, symtext.text) and so does the selection's", sum("edSymbolText TEdit symtext.text" in l and "visible=1" in l for l in tf) == 2, tf)
tt = list(csv.reader(io.StringIO(open(t_csv, encoding="utf-8").read())))
check("with no text typed the placed symbol text reads 'Symbol text'; text typed in the box is the text of each one placed after", [r[1] for r in tt[1:]] == ["Symbol text", "Pump 7", "Pump 7"], tt)

# ---- hit detection: a symbol text whose text was typed in the tool's box can be picked by a click on its text, at any zoom (its box is worked out when it is tested)
def hit_range(zoom):
    L = ["newdoc A4", "tool symboltext", "frameact tool edSymbolText text Some quite long symbol text in here", "clickmm 80 60"] + (["zoom %s" % zoom] if zoom != 1 else []) + ["tool select"]
    for x in range(78, 140, 2): L += ["selclear", "clickmm %d 59" % x]
    h = [int(m.group(1)) for m in re.finditer(r"CLICK (\d+),59 mm -> selected 1", "\n".join(run(L)))]
    return (min(h), max(h)) if h else None
hr = [hit_range(z) for z in (1, 0.5, 2)]
check("a click on the text of a symbol text picks it, over the same stretch of the sheet at zooms 1, 0.5 and 2 (about 8 mm long from x = 80; the click tolerance changes with the zoom)", all(h is not None and 78 <= h[0] <= 84 and 86 <= h[1] <= 96 for h in hr) and all(abs(h[1] - hr[0][1]) <= 2 for h in hr), hr)

# ---- the other reports ignore symbol texts
psu = os.path.join(EX, "circuits/PSU.dsn")
def inject(src, dst, texts):
    t = open(src, encoding="utf-8", errors="surrogateescape").read()
    block = "".join(texts)
    i = t.rindex("</TinyCAD>"); t = t[:i] + block + t[i:]
    open(dst, "w", encoding="utf-8", errors="surrogateescape").write(t)
def symtext(ref, fields, x=10, y=10):
    f = "".join("<FIELD type='%s' description='%s' value='%s' show='%s' pos='0.00000,0.00000'/>" % (ty, d.replace("&", "&amp;").replace("'", "&apos;"), v.replace("&", "&amp;").replace("'", "&apos;").replace('"', "&quot;"), sh) for (d, v, ty, sh) in [("Ref", ref, "1", "0")] + fields)
    return "<SYMTEXT id='0' pos='%d.0,%d.0' part='0' rotate='3' can_scale='0' show_power='0' scale_x='1.0' scale_y='1.0'>%s</SYMTEXT>\n" % (x, y, f)
texts = [symtext("Z9", [("Name", "Zeta, \"big\"", "0", "1"), ("Other", "", "1", "0"), ("Voltage", "12V", "0", "0"), ("Colour", "red", "0", "0")]),
         symtext("A10", [("Name", "Alpha", "0", "1"), ("Other", "", "1", "0"), ("colour", "blue", "0", "0"), ("Zone", "North", "2", "0")], 30, 10),
         symtext("A2", [("Name", "Alpha two", "0", "1"), ("Other", "", "1", "0"), ("Tag", "t1", "0", "0"), ("Tag", "t2", "0", "0"), ("TAG", "t3", "0", "0")], 50, 10),
         symtext("", [("Name", "No ref", "0", "1")], 70, 10)]
v1 = os.path.join(tmp, "v1.dsn"); inject(psu, v1, texts)
v1_csv = os.path.join(tmp, "v1.csv"); psu_csv = os.path.join(tmp, "psu.csv"); v1_bom = os.path.join(tmp, "v1bom.csv"); psu_bom = os.path.join(tmp, "psubom.csv")
bad = os.path.join(tmp, "nodir", "x.csv")
out = run(["open " + v1, "echo V1", "dupcheck", "symbom " + v1_bom, "symdata " + v1_csv, "symdata " + bad, "open " + psu, "echo PSU", "dupcheck", "symbom " + psu_bom, "symdata " + psu_csv])
iv = out.index("V1"); ip = out.index("PSU")
check("an unwritable path gives wrote=0", "SYMDATA wrote=0" in out, [l for l in out if l.startswith("SYMDATA")])
check("the BoM and the duplicate check give the same with and without symbol texts", open(v1_bom).read() == open(psu_bom).read() and [l for l in out[iv:ip] if l.startswith("DUPREF")] == [l for l in out[ip:] if l.startswith("DUPREF")])

# ---- the oracle: two passes over the XML
def heads_of(el):
    out = []; seen = {}
    for f in el.findall("FIELD")[1:]:
        h = (f.get("description") or "").strip() or "Field %d" % (len(out) + 2)
        n = seen.get(h.lower(), 0) + 1; seen[h.lower()] = n
        out.append((h if n == 1 else "%s (%d)" % (h, n), f.get("value") or ""))
    return out
def oracle(path):
    r = ET.parse(path).getroot(); sheets = [r] if r.tag == "TinyCAD" else r.findall("TinyCAD")
    items = []
    for n, sh in enumerate(sheets):
        defs = {d.get("id"): d for d in sh.findall("SYMBOLDEF")}
        for el in sh:
            if el.tag not in ("SYMBOL", "SYMTEXT"): continue
            fl = el.findall("FIELD")
            items.append((n, el, fl[0].get("value") or "", "Symbol" if el.tag == "SYMBOL" else "Symbol text",
                          (defs[el.get("id")].findtext("NAME") or "") if el.tag == "SYMBOL" else "", sh.findtext("NAME") or ""))
    heads = []                                          # pass 1
    for it in items:
        for h, _ in heads_of(it[1]):
            if h.lower() not in [x.lower() for x in heads]: heads.append(h)
    rows = []                                           # pass 2
    for n, el, ref, kind, sym, sname in items:
        cells = [""] * len(heads)
        for h, v in heads_of(el): cells[[x.lower() for x in heads].index(h.lower())] = v
        rows.append((ref, cells, [str(n + 1), sname, kind, sym]))
    rows.sort(key=lambda r: (r[0] == "", natural(r[0])) if r[0] else (True, 0))
    return ["Reference"] + heads + ["Sheet", "Sheet name", "Kind", "Symbol"], [[r[0]] + r[1] + r[2] for r in rows]
def table(p): return list(csv.reader(io.StringIO(open(p, encoding="utf-8").read())))
for name, dsn, got in [("psu with four symbol texts", v1, v1_csv), ("psu alone", psu, psu_csv), ("two placed symbol texts", a_dsn, a_csv)]:
    t = table(got); h, b = oracle(dsn)
    check(name + ": header equals the oracle's", t[0] == h, (t[0], h))
    check(name + ": every row equals the oracle's (values under their own headings, order)", t[1:] == b, [(x, y) for x, y in zip(t[1:], b) if x != y][:2])
    check(name + ": every row has as many cells as the header", all(len(r) == len(t[0]) for r in t))
t = table(v1_csv); h = t[0]
check("v1: the headings are shared by name ignoring case (Colour once, Tag, Tag (2), TAG (3): numbered as typed)", h.count("Colour") + h.count("colour") == 1 and "Tag" in h and "Tag (2)" in h and "TAG (3)" in h, h)
check("v1: hidden fields are in (Voltage, Zone)", "Voltage" in h and "Zone" in h, h)
rows = {r[0]: r for r in t[1:]}
check("v1: Z9's quoted name came back through the csv module", rows["Z9"][h.index("Name")] == 'Zeta, "big"', rows["Z9"])
check("v1: A2 sorts before A10 and the row without a reference is last", [r[0] for r in t[1:] if r[0] in ("A2", "A10")] == ["A2", "A10"] and t[-1][0] == "", [r[0] for r in t[1:]][-5:])
check("v1: Voltage is only in Z9's row, Zone only in A10's", [r[0] for r in t[1:] if r[h.index("Voltage")]] == ["Z9"] and [r[0] for r in t[1:] if r[h.index("Zone")]] == ["A10"])
check("v1: Reference is the first column; Kind says Symbol text for four rows", h[0] == "Reference" and sum(r[h.index("Kind")] == "Symbol text" for r in t[1:]) == 4)

# ---- the menu item
lfm = open(os.path.join(ROOT, "src/forms/mainform.lfm"), encoding="utf-8").read()
check("Export Symbol Data is a menu item of mainform.lfm after the Symbol BoM item", lfm.index("object mSymbolData: TMenuItem") > lfm.index("object mSymbolBom: TMenuItem") and "OnClick = DoSymbolData" in lfm)
print("symbol data: %d checks, %d failed" % (checks, len(fails))); sys.exit(1 if fails else 0)
