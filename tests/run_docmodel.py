"""Checks for the document-model additions: paper sizes and border, revision history, title-block
variables, auto sheet numbering, and stable object ids. References are written independently
here (inches/mm for paper, a regex for the variable grammar, ElementTree for the XML)."""
import os, re, sys, math, random, subprocess, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xml.etree.ElementTree as ET
from canon import canon_file, diff

EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
BUILD = os.environ.get("TC_BUILD", "build")
DT = os.path.join(BUILD, "doctest"); DS = os.path.join(BUILD, "designtest")
tmp = tempfile.mkdtemp()
fails = []
def check(name, ok, detail=""):
    if not ok: fails.append(name); print(f"  FAIL {name} {detail}")
def run(*a):
    r = subprocess.run(list(a), capture_output=True, text=True)
    if r.returncode != 0: raise SystemExit("failed: " + " ".join(a) + "\n" + r.stderr[-300:])
    return r.stdout

def unesc(s): return s.replace("\\n", "\n").replace("\\p", "|").replace("\\\\", "\\")
half_up = lambda x: int(math.floor(x + 0.5))

# ---------------- paper and border ----------------
inch = 25.4
papers = {"ANSI A (Letter)": (11 * inch, 8.5 * inch), "ANSI B (Tabloid)": (17 * inch, 11 * inch), "ANSI C": (22 * inch, 17 * inch),
          "ANSI D": (34 * inch, 22 * inch), "ANSI E": (44 * inch, 34 * inch),
          "ARCH A": (12 * inch, 9 * inch), "ARCH B": (18 * inch, 12 * inch), "ARCH C": (24 * inch, 18 * inch), "ARCH D": (36 * inch, 24 * inch),
          "ARCH E1": (42 * inch, 30 * inch), "ARCH E": (48 * inch, 36 * inch),
          "ISO A8": (74, 52), "ISO A7": (105, 74), "ISO A6": (148, 105), "ISO A5": (210, 148), "ISO A4": (297, 210), "ISO A3": (420, 297),
          "ISO A2": (594, 420), "ISO A1": (841, 594), "ISO A0": (1189, 841),
          "ISO B8": (88, 62), "ISO B7": (125, 88), "ISO B6": (176, 125), "ISO B5": (250, 176), "ISO B4": (353, 250), "ISO B3": (500, 353),
          "ISO B2": (707, 500), "ISO B1": (1000, 707), "ISO B0": (1414, 1000),
          "ISO RA2": (610, 430), "ISO RA1": (860, 610), "ISO RA0": (1220, 860), "ISO SRA2": (640, 450), "ISO SRA1": (900, 640), "ISO SRA0": (1280, 900),
          "Legal": (14 * inch, 8.5 * inch), "Executive": (10.5 * inch, 7.25 * inch), "Statement": (8.5 * inch, 5.5 * inch),
          "ISO C4 envelope": (324, 229), "ISO C5 envelope": (229, 162), "ISO C6 envelope": (162, 114)}
out = run(DT, "paper").split("\n"); rows = [l for l in out if l.startswith("PAPER ")]
check("paper table size", len(rows) == len(papers), f"{len(rows)}")
names_seen = []
check("every paper size is distinct", len({(half_up(w * 5), half_up(h * 5)) for w, h in papers.values()}) == len(papers))
for i, l in enumerate(rows):
    name, wl, hl, wp, hp, m1, l1, m2, l2 = l[6:].split("|")
    names_seen.append(name)
    w, h = papers[name]
    check(f"{name} landscape", (int(wl), int(hl)) == (half_up(w * 5), half_up(h * 5)), l)
    check(f"{name} portrait", (int(wp), int(hp)) == (half_up(h * 5), half_up(w * 5)), l)
    check(f"{name} matches itself", (int(m1), int(l1), int(m2), int(l2)) == (i, 1, i, 0), l)
b = [l for l in out if l.startswith("BORDER")][0].split()
check("11x17 is 2159 x 1397 units", (b[1], b[2]) == ("2159", "1397"), str(b))
check("border inset 0.25 in", [float(x) for x in b[3:]] == [31.75, 31.75, 2159 - 31.75, 1397 - 31.75], str(b))
a4 = str(names_seen.index("ISO A4"))
check("closest paper wins / tolerance", [l for l in out if l.startswith("MATCH_TOL")][0].split()[1:] == [a4, "1", "-1", a4, "0"], str([l for l in out if l.startswith("MATCH_TOL")]))
check("page descriptions", [l for l in out if l.startswith("DESCRIBE")][0][9:] == "ISO A4 landscape|Custom 200 x 140 mm|ANSI B (Tabloid) portrait")
check("table has exactly the expected papers", sorted(names_seen) == sorted(papers), str(set(papers) ^ set(names_seen)))
print(f"paper table and border: {len(rows)} papers x 2 orientations, 11x17 = 2159 x 1397, border, matching")

# ---------------- a design using every new feature ----------------
mk = os.path.join(tmp, "mk.dsn")
run(DT, "mkdesign", mk)
root = ET.parse(mk).getroot()
sheets = root.findall("TinyCAD")
check("three sheets", root.tag == "TinyCADSheets" and len(sheets) == 3)
d0, d1, d2 = [s.find("DETAILS") for s in sheets]
check("sheet 1 size 11x17", (d0.find("Size").get("width"), d0.find("Size").get("height")) == ("2159", "1397"))
check("sheet 1 autosheets+border", d0.find("AUTOSHEETS") is not None and d0.find("AUTOSHEETS").text == "1" and abs(float(d0.find("BORDER").get("margin")) - 40) < 1e-9)
revs = d0.find("REVISIONS").findall("REV")
exp = [("A", "2026-01-05", "JS", "MK", "Initial issue"),
       ("B", "2026-03-14", "JS", "MK", "Added feeder F4\nMoved contactor K2 to rung 12\nFixed \"label\" & <note>"),
       ("C", "2026-06-30", "RT", "", "")]
got = [(r.get("label"), r.get("date"), r.get("author"), r.get("approved"), r.text or "") for r in revs]
check("revision entries (incl. multi-line notes with & < > quotes)", got == exp, str(got))
check("title with markup characters", d0.find("TITLE").text == 'Panel A <main> & "feeders"')
check("sheet 2: no history, no border, autosheets", d1.find("REVISIONS") is None and d1.find("BORDER") is None and d1.find("AUTOSHEETS") is not None and d1.find("REVISION").text == "B2")
check("sheet 3: typed sheets text, no autosheets, one revision",
      d2.find("AUTOSHEETS") is None and d2.find("SHEETS").text == "3 of 9" and len(d2.find("REVISIONS")) == 1)
# dump after reload matches what was written
dump = run(DT, "dump", mk).split("\n")
sh = [l for l in dump if l.startswith("SHEET ")]
check("reload: sheet 1", sh[0].split("|")[2:11] == ["2159", "1397", "1", "1", "40", "C", "2026-06-30", "3", "ANSI B (Tabloid) landscape"], sh[0])
check("reload: sheet 1 border rectangle", sh[0].split("|")[11] == "40 40 2119 1357", sh[0])
check("reload: sheet 2 legacy revision", sh[1].split("|")[7] == "B2" and sh[1].split("|")[9] == "0", sh[1])
rl = [l for l in dump if l.startswith("REV 0 1|")][0].split("|")
check("reload: multi-line notes intact", unesc(rl[5]) == exp[1][4], rl[5])
# saving again gives the same bytes
again = os.path.join(tmp, "again.dsn"); run(DS, "rt", mk, again)
check("save of reloaded design is byte-identical", open(mk, "rb").read() == open(again, "rb").read())
print("revision history, border, auto sheet numbers: written, parsed independently, reloaded, re-saved identically")

# ---------------- title-block variables ----------------
exp_vars = [
 dict(SHEET="1", SHEETCOUNT="3", SHEETOF="1 of 3", SHEETS="3", SHEETNAME="Power distribution", PAPER="ANSI B (Tabloid) landscape",
      PAGESIZE="431.8 x 279.4 mm", BORDERMARGIN="8", TITLE='Panel A <main> & "feeders"', AUTHOR="J. Smith", ORG="Acme Controls", DOCNO="1",
      DATE="2026-10-02", REV="C", REVDATE="2026-06-30", REVBY="RT", REVAPPROVED="", REVNOTES=""),
 dict(SHEET="2", SHEETCOUNT="3", SHEETOF="2 of 3", SHEETS="3", SHEETNAME="Sheet 2", PAPER="ISO A4 landscape", PAGESIZE="297 x 210 mm",
      BORDERMARGIN="6.35", TITLE="Controls", AUTHOR="", ORG="", DOCNO="2", DATE="", REV="B2", REVDATE="", REVBY="", REVAPPROVED="", REVNOTES=""),
 dict(SHEET="3", SHEETCOUNT="3", SHEETOF="3 of 3", SHEETS="3 of 9", SHEETNAME="Sheet 3", PAPER="ANSI B (Tabloid) portrait", PAGESIZE="279.4 x 431.8 mm",
      BORDERMARGIN="6.35", TITLE="", AUTHOR="", ORG="", DOCNO="", DATE="", REV="1.0", REVDATE="2026-09-01", REVBY="AB", REVAPPROVED="CD", REVNOTES="Single line note"),
]
for v in exp_vars: v["FILE"] = mk; v["FILENAME"] = os.path.basename(mk)
def reference_expand(text, vars_):
    out = []; i = 0
    while i < len(text):
        c = text[i]
        if c != "$": out.append(c); i += 1
        elif text[i + 1:i + 2] == "$": out.append("$"); i += 2
        elif text[i + 1:i + 2] == "(":
            j = text.find(")", i + 2)
            if j < 0: out.append(text[i:]); break
            name = text[i + 2:j].strip().upper()
            out.append(vars_[name] if name in vars_ else text[i:j + 1]); i = j + 1
        else: out.append("$"); i += 1
    return "".join(out)
random.seed(7)
tokens = ["$(SHEET)", "$(SheetOf)", "$$", "$", "$(", ")", "(", "abc ", " ", "$(REV)", "$(UNKNOWN)", "$( title )", "$(SHEETS)", "$(DOCNO)", "$(REVNOTES)", "$(PAPER)",
          "$(FILENAME)", "$($(SHEET))", "$$(SHEET)", "5% done", "$(FILE)", "$(BORDERMARGIN) mm", "$(SHEETCOUNT)", "$(sheetname)", "|", "x$"]
cases = ["Sheet $(SHEET) of $(SHEETCOUNT)", "$(SHEETOF)", "Document $(DOCNO), sheets $(SHEETS)", "Rev $(REV) $(REVDATE) $(REVBY)", "$$(SHEET)=$(SHEET)", "$(", "$(SHEET", "cost $5", "$()"] + \
        ["".join(random.choice(tokens) for _ in range(random.randint(1, 7))) for _ in range(300)]
bad = 0
for idx in range(3):
    for t in cases:
        got = unesc(run(DT, "expand", mk, str(idx), t).rstrip("\n"))
        want = reference_expand(t, exp_vars[idx])
        if got != want:
            bad += 1
            if bad <= 3: print("   EXPAND", idx, repr(t), "got", repr(got), "want", repr(want))
check("variable expansion vs reference", bad == 0, f"{bad} differ")
print(f"title-block variables: {3 * len(cases)} expansions over 3 sheets compared with an independent implementation ({bad} differ)")

# ---------------- stable object ids over all sample designs ----------------
designs = sorted(os.path.join(r, f) for r, _, fs in os.walk(EXAMPLES) for f in fs if f.lower().endswith((".dsn", ".autosave")))
OBJ = {"BUS", "WIRE", "LINE", "POLYGON", "JUNCTION", "NOCONNECT", "ORIGIN", "BUSSLASH", "RECTANGLE", "ELLIPSE", "TEXT", "BUSNAME", "LABEL", "POWER", "PIN", "NOTE_TEXT", "SYMBOL"}
n_obj = n_designs = 0; probs = 0
for p in designs:
    o = os.path.join(tmp, "ids.dsn")
    line = [l for l in run(DT, "ids", p, o).split("\n") if l.startswith("ids ")][0].split()
    total, assigned, maxid, bad_ = map(int, line[1:5])
    r = ET.parse(o).getroot()
    shs = [r] if r.tag == "TinyCAD" else r.findall("TinyCAD")
    objs = [e for s in shs for e in s if e.tag in OBJ]
    oids = [e.get("oid") for e in objs]
    ok = bad_ == 0 and all(oids) and len(set(oids)) == len(oids) and len(objs) > 0
    # nothing but the ids changed: the same content as the original
    ok = ok and not diff(canon_file(p), canon_file(o))
    if not ok: probs += 1; print("   IDS", os.path.basename(p), line, len(objs), len(set(oids)))
    n_obj += len(objs); n_designs += 1
check("object ids on all designs", probs == 0, f"{probs} problem designs")
print(f"object ids: {n_designs} designs, {n_obj} saved objects: all get unique ids, survive save/reload, content otherwise unchanged ({probs} problems)")

# ordinary files stay exactly as they were: none of the new tags or attributes appear unless used
leaks = 0
for p in designs:
    o = os.path.join(tmp, "plain.dsn"); run(DS, "rt", p, o)
    t = open(o, "rb").read().decode("utf-8", "replace")
    if re.search(r"oid=|<AUTOSHEETS|<BORDER|<REVISIONS", t): leaks += 1
check("no new tags in ordinary files", leaks == 0, f"{leaks} files")
print(f"old-format files: {len(designs) - leaks}/{len(designs)} re-save without any of the new tags or attributes")
print("\nDOCUMENT MODEL CHECKS PASSED" if not fails else f"\nDOCUMENT MODEL CHECKS FAILED: {fails}")
sys.exit(1 if fails else 0)
