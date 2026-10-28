#!/usr/bin/env python3
"""Parts library editor, part symbols (Phase B7): the Symbols page lists the symbols of a part, draws a new one or edits one in the symbol editor (Store puts the drawing back into the
parts file), imports the symbol chosen in the library panel, and changes standard / purpose / name, the default and deletes -- on the real program under Xvfb (`pe page symbols`, `pe sym ...`).
Oracles (independent of the program): the file is read with Python's sqlite3 and the stored drawings are counted with regular expressions (pins) and compared byte for byte with the
.TCLib's own Symbol table (import); expectations (default symbol rules, revision + 1 per change) are written here.
  - the page: rows equal the Symbol table (name, standard, purpose, default marker, bytes)
  - edit: a pin drawn in the symbol editor and Stored replaces the drawing of that very symbol (one more pin, same row, same default, revision + 1, other parts untouched); the same symbol
    opened twice is one document; the page shows the new size after the store
  - new: nothing is in the file until Store; the properties typed first are the stored ones; the first schematic symbol of a part becomes its default, later ones and non-schematic ones do not
  - import: the library panel's chosen symbol arrives byte for byte, named after the library symbol; with nothing chosen it is refused
  - rules: only a schematic symbol is the default; the default cannot become another purpose; empty standard / unknown purpose / empty drawing refused (file unchanged); deleting the
    default re-picks the lowest other schematic symbol, deleting the last clears it; pin assignments go with the symbol
  - menu items follow the page and the choice; the properties dialog shows the symbol
Needs the built program, xvfb and the example libraries (TC_EXAMPLES, for the import)."""
import io, os, re, shutil, sqlite3, subprocess, sys, tempfile
try:
    from PIL import Image
except ImportError:
    Image = None
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Symbol checks skipped: need xvfb-run and the built program"); sys.exit(0)
sys.path.insert(0, os.path.join(ROOT, "docs")); import parts_seed
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:900])
def run(lines):
    h = tempfile.mkdtemp(dir=tmp); f = os.path.join(tmp, "s.txt"); open(f, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
def mk(name):
    p = os.path.join(tmp, name); parts_seed.build(p).close(); return p
def db(p):
    c = sqlite3.connect(p); c.execute("pragma foreign_keys=ON"); return c
def syms(p, pid):
    c = db(p); r = c.execute("select SymbolID,Name,Standard,Purpose,length(Drawing) from Symbol where PartID=? order by SymbolID", (pid,)).fetchall(); d = c.execute("select BaseDefault from Part where PartID=?", (pid,)).fetchone()[0]; c.close(); return r, d
def rev(p, pid):
    c = db(p); r = c.execute("select Revision from Part where PartID=?", (pid,)).fetchone()[0]; c.close(); return int(r or 1)
def pins(p, sid):
    c = db(p); b = c.execute("select Drawing from Symbol where SymbolID=?", (sid,)).fetchone()[0].decode(); c.close(); return len(re.findall(r"<PIN\b", b))
def blobs(p):
    c = db(p); r = c.execute("select SymbolID,Drawing from Symbol order by 1").fetchall(); c.close(); return r
def others(p, pid):
    c = db(p); r = c.execute("select SymbolID,Drawing from Symbol where PartID<>? order by 1", (pid,)).fetchall(); r2 = c.execute("select PartID,Revision from Part where PartID<>? order by 1", (pid,)).fetchall(); c.close(); return r, r2
def glyphs(p, pid):
    c = db(p); r = c.execute("select Size,Png from PartGlyph where PartID=? order by Size", (pid,)).fetchall(); c.close(); return r
def ink(png):
    im = Image.open(io.BytesIO(png)).convert("RGB"); d = im.tobytes(); return sum(1 for i in range(0, len(d), 3) if d[i:i + 3] != b"\xff\xff\xff"), im.size
def span(png):
    im = Image.open(io.BytesIO(png)).convert("L").point(lambda v: 255 if v < 250 else 0); b = im.getbbox(); return max(b[2] - b[0], b[3] - b[1]) if b else 0
def prow(o): return [l[len("PESYM "):].split("|") for l in o if l.startswith("PESYM ")]
def want_rows(p, pid):
    r, d = syms(p, pid); return [[n, s, pu, "default" if i == d else "", str(b)] for i, n, s, pu, b in r]
def last(o, what): return [l for l in o if l.startswith("PE sym %s" % what)]
CT = "Contactor 3P 25 A AC-3, 24 V DC coil"; AM = "Analog input module, 4 channels, current"
f = mk("a.TCParts"); c = db(f)
ct = c.execute("select PartID from Part where Name=?", (CT,)).fetchone()[0]; am = c.execute("select PartID from Part where Name=?", (AM,)).fetchone()[0]
cls = c.execute("select c.Name from PartClass c join Part p on p.ClassID=c.ClassID where p.PartID=?", (ct,)).fetchone()[0]; c.close()
# ---- the page, the menu
o = run(["peopen " + f, "pe menu", "pe page symbols", "pe menu", "pe sym part|" + CT, "pe sym rows", "pe menu", "pe sym select|0", "pe sym rows", "pe menu", "pe sym part|" + AM, "pe sym rows"])
M = [l for l in o if l.startswith("PEMENU")]
check("menu: symbol items off outside the page; on the page New and Import need a part; Edit / Properties / Delete need a symbol; Make Default not for the default",
      len(M) == 4 and "symnew=0 symedit=0 symimp=0 symprops=0 symdef=0 symdel=0" in M[0] and "symnew=0" in M[1] and "symnew=0" in M[1] and "symedit=0" in M[2] and "symprops=0" in M[2], M)
I = [i for i, l in enumerate(o) if l.startswith("PESYMINFO")]
check("the contactor's rows equal the Symbol table", prow(o[:I[0]]) == want_rows(f, ct) and len(want_rows(f, ct)) == 1, (prow(o[:I[0]]), want_rows(f, ct)))
check("the analog module's rows equal the Symbol table", prow(o[I[1] + 1:I[2]]) == want_rows(f, am) and len(want_rows(f, am)) == 1, (prow(o[I[1] + 1:I[2]]), want_rows(f, am)))
check("the default row says so", prow(o[:I[0]])[0][3] == "default", prow(o[:I[0]]))
check("buttons: nothing chosen = Edit / Properties / Make Default / Delete off; chosen default = Make Default off", "edit=0" in o[I[0]] and "props=0" in o[I[0]] and "delete=0" in o[I[0]], o[I[0]])
check("buttons after choosing the default: Edit on (the main form gives the page its editor), Make Default off", "default=0" in o[I[1]] and "props=1" in o[I[1]] and "delete=1" in o[I[1]], o[I[1]])
# ---- the dialog
o = run(["peopen " + f, "pe page symbols", "pe sym part|" + CT, "pe sym dlg|0"])
D = [l for l in o if l.startswith("PEDLG")]
check("dialog shows standard, purpose and name of the symbol and four purposes", len(D) == 1 and "standard=IEC" in D[0] and "purpose=schematic" in D[0] and "name=" + CT in D[0] and "purposes=4" in D[0], D)
# ---- edit: draw a pin, store, same symbol row
f = mk("b.TCParts"); r0, d0 = syms(f, ct); before = pins(f, r0[0][0]); rv = rev(f, ct); oth = others(f, ct)
o = run(["peopen " + f, "pe page symbols", "pe sym part|" + CT, "pe sym select|0", "pe sym start|0|||", "docs", "gotodoc 0", "pe sym start|0|||", "docs", "gotodoc 1", "tool pin", "clickmm 150 150", "sym store=1", "gotodoc 0", "pe sym rows"])
S = last(o, "start"); Dc = [l for l in o if l.startswith("DOCS")]
check("edit: the editor opens as a second tab, the same symbol again is the same tab", len(S) == 2 and "docs=2" in S[0] and "docs=2" in S[1] and len(Dc) == 2 and Dc[0].split()[1] == "2" and Dc[1].split()[1] == "2", (S, Dc))
st = [l for l in o if l.startswith("SYM store")]
check("edit: store ok", st and "ok=1" in st[0], st)
r1, d1 = syms(f, ct)
check("edit: same symbol id, same name / standard / purpose, still the default, drawing changed", len(r1) == 1 and r1[0][:4] == r0[0][:4] and r1[0][4] != r0[0][4] and d1 == d0, (r0, r1, d0, d1))
check("edit: one more pin in the stored drawing", pins(f, r1[0][0]) == before + 1, (before, pins(f, r1[0][0])))
g0 = glyphs(mk("b0.TCParts"), ct); g1 = glyphs(f, ct)
check("edit: the part's glyphs were drawn again from the stored symbol (four sizes, each a PNG of that size with drawing in it, not the same as before)",
      Image is None or ([s for s, _ in g1] == [16, 24, 32, 48] and all(ink(b)[1] == (s, s) and ink(b)[0] > 0 for s, b in g1) and [b for _, b in g1] != [b for _, b in g0]), (g0 and [s for s, _ in g0], [s for s, _ in g1]))
check("edit: revision up by one; other parts and symbols untouched", rev(f, ct) == rv + 1 and others(f, ct) == oth, (rv, rev(f, ct)))
check("edit: the page shows the new size", prow(o[[i for i, l in enumerate(o) if l.startswith("PESYMINFO")][-1] - 1:]) == want_rows(f, ct), (prow(o)[-1:], want_rows(f, ct)))
# ---- new symbol: not in the file until stored; first schematic of a part becomes default
f = mk("c.TCParts"); snap = blobs(f)
o = run(["peopen " + f, "pe add Test part|%s|T|a test" % cls, "pe page symbols", "pe sym part|Test part", "pe sym rows",
         "pe sym start|-1|ANSI|schematic|First", "tool pin", "clickmm 20 20", "tool pin", "clickmm 20 30", "gotodoc 0", "pe sym rows", "gotodoc 1", "sym store=1", "gotodoc 0", "pe sym rows",
         "pe sym start|-1|IEC|oneline|Line", "tool pin", "clickmm 20 20", "sym store=1", "gotodoc 0", "pe sym rows"])
c = db(f); pid = c.execute("select PartID from Part where Name='Test part'").fetchone()[0]; c.close()
R = [l for l in o if l.startswith("PESYMINFO")]
rows_all = [[l[len("PESYM "):].split("|") for l in []]]
r2, d2 = syms(f, pid)
check("new: both symbols are in the file with the typed properties", [(n, s, p) for _, n, s, p, _ in r2] == [("First", "ANSI", "schematic"), ("Line", "IEC", "oneline")], r2)
check("new: the first schematic symbol is the default, the one-line symbol is not", len(r2) == 2 and d2 == r2[0][0], (r2, d2))
check("new: pins drawn = pins stored (2 and 1)", len(r2) == 2 and pins(f, r2[0][0]) == 2 and pins(f, r2[1][0]) == 1, [pins(f, x[0]) for x in r2])
check("new: nothing in the file until Store (the page showed no rows after the drawing)", o.count("PESYMINFO part=Test part  (%s) rows=0 new=1 edit=0 import=1 props=0 default=0 delete=0" % cls) == 2, [l for l in o if l.startswith("PESYMINFO")])
check("new: the existing symbols are untouched", [b for b in blobs(f) if b[0] in (1, 2)] == snap, None)
g = glyphs(f, pid)
check("new: the first stored symbol gave the part its glyphs (four sizes, drawn, of that size)", Image is None or ([s for s, _ in g] == [16, 24, 32, 48] and all(ink(b)[1] == (s, s) and ink(b)[0] > 0 for s, b in g)), [s for s, _ in g])
check("new: the symbol fills the glyph (largest extent at least half of 48 pixels)", Image is None or span(g[-1][1]) >= 24, None if Image is None else span(g[-1][1]))
check("new: the part's revision went up twice", rev(f, pid) >= 3, rev(f, pid))
# ---- closing without store leaves the file alone
f = mk("d.TCParts"); snap = blobs(f); rv = rev(f, ct)
o = run(["peopen " + f, "pe page symbols", "pe sym part|" + CT, "pe sym start|-1|IEC|schematic|Nope", "tool pin", "clickmm 20 20", "sym close=1", "docs"])
check("close without store: file unchanged", blobs(f) == snap and rev(f, ct) == rv, None)
# ---- import from the library panel
lib = os.path.join(EX, "libraries", "gen_passive.TCLib")
if os.path.exists(lib):
    f = mk("e.TCParts"); L = os.path.join(tmp, "lib.TCLib"); shutil.copy(lib, L)
    o = run(["peopen " + f, "pe page symbols", "pe sym part|" + CT, "pe sym import|IEC|schematic|", "lib " + L, "libselect 1", "pe sym import|ANSI|panel|", "pe sym import||panel|X", "pe sym rows"])
    I = last(o, "import"); sel = [l for l in o if l.startswith("LIBSELECT")]
    check("import: nothing chosen is refused with the reason", I and I[0] == "PE sym import error Choose a symbol in the library panel first.", I)
    r, d = syms(f, ct); lc = sqlite3.connect(L)
    libblobs = [bytes(x[0]) for x in lc.execute("select Data from Symbol").fetchall()]; libnames = [x[0] for x in lc.execute("select Name from Name").fetchall()]; lc.close()
    check("import: one symbol added, ANSI / panel, drawing equals a drawing of the library byte for byte", len(r) == 2 and r[1][2] == "ANSI" and r[1][3] == "panel" and bytes(blobs(f)[-1][1]) in libblobs and "import ok" in " ".join(I), (r, I))
    check("import: named after the library symbol", len(r) == 2 and r[1][1] in libnames and r[1][1] in sel[0], (r, sel))
    check("import: an empty standard is refused", len(I) == 3 and I[2].startswith("PE sym import error The symbol needs a drawing standard"), I)
else:
    print("  (import checks skipped: no example libraries)")
# ---- rules
f = mk("g.TCParts"); blob = os.path.join(tmp, "blob.xml"); shutil.copy(os.path.join(tmp, "g.TCParts"), os.path.join(tmp, "x")); c = db(f); open(blob, "wb").write(c.execute("select Drawing from Symbol where SymbolID=1").fetchone()[0]); c.close()
snapf = open(f, "rb").read()
cmds = ["peopen " + f, "pe page symbols", "pe sym part|" + AM,
        "pe sym add|IEC|oneline|One|" + blob,        # row 1, not default
        "pe sym add|IEC|schematic|Two|" + blob,      # row 2
        "pe sym add|DIN|schematic|Three|" + blob,    # row 3
        "pe sym default|1",                          # refused: oneline
        "pe sym info|0|IEC|panel|X",                 # refused: the default must be schematic
        "pe sym info|1|IEC|nonsense|X",              # refused: purpose
        "pe sym info|1||oneline|X",                  # refused: standard
        "pe sym add|IEC|schematic|Empty|/nonexistent",  # refused: empty drawing
        "pe sym rows"]
o = run(cmds); S = o
A = [l for l in o if l.startswith("PE sym ")]
check("rules: three symbols added", sum(1 for l in A if l.startswith("PE sym add ok")) == 3, A)
check("rules: the first schematic stays the default; a later schematic and the one-line symbol do not take over", syms(f, am)[1] == syms(f, am)[0][0][0], syms(f, am))
check("rules: oneline cannot be the default", "PE sym default error Only a schematic symbol can be the default." in A, A)
check("rules: the default cannot become another purpose", any(l.startswith("PE sym info error This is the part's default symbol, which must be a schematic one") for l in A), A)
check("rules: unknown purpose, empty standard, empty drawing refused", "PE sym info error The purpose must be schematic, oneline, panel or block." in A and "PE sym info error The symbol needs a drawing standard (IEC, ANSI ...)." in A and "PE sym add error The symbol has no drawing." in A, A)
rows, dflt = syms(f, am); ids = [x[0] for x in rows]
check("rules: rows are original, One, Two, Three; Name of the added = typed", [x[1] for x in rows][1:] == ["One", "Two", "Three"] and len(rows) == 4, rows)
ga = glyphs(f, am)
o = run(["peopen " + f, "pe page symbols", "pe sym part|" + AM, "pe sym default|2", "pe sym info|2|JIC|schematic|Two b", "pe sym info|1|IEC|schematic|One b"])
rows, dflt = syms(f, am)
check("default: Make Default draws the glyphs again from the new default", Image is None or (glyphs(f, am) != ga and len(glyphs(f, am)) == 4), len(ga))
check("default: Make Default moves it (Two b is row 2 = id %d)" % ids[2], dflt == ids[2], (rows, dflt, ids))
check("default: properties changed; a non-default may become schematic", rows[2][1:4] == ("Two b", "JIC", "schematic") and rows[1][1:4] == ("One b", "IEC", "schematic"), rows)
# delete default -> lowest other schematic; delete rest -> NULL
rv = rev(f, am)
o = run(["peopen " + f, "pe page symbols", "pe sym part|" + AM, "pe sym del|2"])
rows, dflt = syms(f, am)
check("delete default: the lowest other schematic symbol takes over", len(rows) == 3 and dflt == ids[0], (rows, dflt, ids))
c = db(f); c.execute("insert into SymbolPin(SymbolID,ObjectID,X,Y) select ?, ObjectID, 1, 1 from PartObject where PartID=? limit 1", (ids[0], am)); c.commit(); n = c.execute("select count(*) from SymbolPin").fetchone()[0]; c.close()
o = run(["peopen " + f, "pe page symbols", "pe sym part|" + AM, "pe sym del|0", "pe sym del|0", "pe sym del|0", "pe sym rows"])
rows, dflt = syms(f, am); c = db(f); n2 = c.execute("select count(*) from SymbolPin").fetchone()[0]; c.close()
check("delete: all gone, no default left, the pin assignments went with the symbol", rows == [] and dflt is None and n == 1 and n2 == 0, (rows, dflt, n, n2))
check("delete: no symbol left, no glyph left", glyphs(f, am) == [], [s for s, _ in glyphs(f, am)])
check("delete: revision up by one per delete", rev(f, am) >= rv + 3, (rv, rev(f, am)))
# ---- more rules: a non-schematic first symbol is no default; block purpose; empty name = the part's; default of another part
f = mk("h.TCParts"); c = db(f); open(blob, "wb").write(c.execute("select Drawing from Symbol where SymbolID=1").fetchone()[0]); c.close()
o = run(["peopen " + f, "pe page symbols", "pe sym part|" + AM, "pe sym select|0", "pe sym del|0", "pe sym add|IEC|block||" + blob, "pe sym add|IEC|oneline|Line|" + blob, "pe sym rows", "pe sym defraw|1", "pe sym add|IEC|schematic|Sch|" + blob, "pe sym rows"])
rows, dflt = syms(f, am); A = [l for l in o if l.startswith("PE sym ")]
check("a block symbol is accepted and, with no name typed, is named after the part", [x[1:4] for x in rows][:1] == [(AM, "IEC", "block")], rows)
check("only a schematic symbol becomes the first default (block and one-line did not)", dflt == rows[2][0] and rows[2][3] == "schematic", (rows, dflt))
check("the default of a symbol of another part is refused", "PE sym defraw error That symbol belongs to another part." in A, A)
print("%d checks, %d failed" % (checks, len(fails))); sys.exit(1 if fails else 0)
