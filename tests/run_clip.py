"""Copy and paste checks. The format is TinyCAD's own ("TinyCAD Design": the sheet XML restricted to the
selection), so a single-sheet .dsn written by TinyCAD is valid clipboard data and is used here as real
TinyCAD output. Objects are compared in canonical form (resources resolved), independent of the Pascal code."""
import os, sys, math, subprocess, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xml.etree.ElementTree as ET
from canon import canon_file
BUILD = os.environ.get("TC_BUILD", "build"); EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
EXE = os.path.join(BUILD, "cliptest"); tmp = tempfile.mkdtemp(); fails = []
def check(n, ok, d=""):
    if not ok: fails.append(n); print("  FAIL", n, d)
def run(*a):
    r = subprocess.run([EXE, *a], capture_output=True, text=True)
    if r.returncode != 0: raise SystemExit("cliptest failed: " + " ".join(a) + "\n" + r.stderr[-300:])
    return r.stdout.strip().split("\n")
designs = sorted(os.path.join(r, f) for r, _, fs in os.walk(EXAMPLES) for f in fs if f.lower().endswith(".dsn"))
single = designs   # every design: its first sheet is copied / pasted
def sheet_el(path):
    r = ET.parse(path).getroot()
    return r.find("TinyCAD") if r.tag == "TinyCADSheets" else r
def norm(o):
    """a symbol that has been laid out writes its reference points, so a pasted one may gain REF_POINT entries: ignore them"""
    if o[0] == "SYMBOL" and isinstance(o[1], tuple) and o[1][0] == "SYM":
        sym = list(o[1]); sym[9] = (); return (o[0], tuple(sym)) + tuple(o[2:])
    return o
objs = lambda path: [norm(o) for o in canon_file(path)[0]["objects"]]

# ---- 1. everything copied, then pasted into an empty document, comes back identical
bad = 0; n_obj = 0
for p in single:
    clip = os.path.join(tmp, "c.xml"); out = os.path.join(tmp, "o.dsn")
    run("copy", p, clip, "all"); run("paste", clip, "NEW", out)
    ok = objs(out) == objs(p); n_obj += len(objs(p))
    if not ok: bad += 1; print("   copy/paste round trip differs:", os.path.basename(p))
check("copy all + paste into an empty document restores every object", bad == 0, f"{bad} designs")
print(f"copy + paste round trip: {len(single)} designs, {n_obj} objects restored identically ({bad} differ)")

# ---- 2. data written by TinyCAD itself (a .dsn) pasted as if from the clipboard
bad = 0
for p in single:
    out = os.path.join(tmp, "o2.dsn"); run("paste", p, "NEW", out)
    if objs(out) != objs(p): bad += 1; print("   TinyCAD file pasted differently:", os.path.basename(p))
check("a TinyCAD-written sheet pastes as clipboard data", bad == 0, f"{bad}")
print(f"TinyCAD-written data pasted: {len(single)} files read as clipboard data, {bad} differ")

# ---- 3. a partial copy holds exactly the selected objects, and only the resources they need
led = os.path.join(EXAMPLES, "circuits", "Computer Operated Telescope", "LED Plate.dsn")
orig_root = sheet_el(led)
orig_tags = [e.tag for e in orig_root if e.tag in ("WIRE", "BUS", "LINE", "JUNCTION", "SYMBOL", "POLYGON", "TEXT", "LABEL", "POWER", "RECTANGLE", "ELLIPSE", "NOCONNECT", "NOTE_TEXT", "PIN", "BUSSLASH")]
clip = os.path.join(tmp, "w.xml"); r = run("copy", led, clip, "class:TDrawLine")
wires_n = orig_tags.count("WIRE") + orig_tags.count("BUS") + orig_tags.count("LINE")
root = ET.parse(clip).getroot()
got = [e.tag for e in root if e.tag in ("WIRE", "BUS", "LINE", "JUNCTION", "SYMBOL", "POLYGON", "TEXT", "LABEL")]
check("copying only the wires writes only wire elements", sorted(got) == sorted(["WIRE"] * orig_tags.count("WIRE") + ["BUS"] * orig_tags.count("BUS") + ["LINE"] * orig_tags.count("LINE")), str(got)[:200])
check("and says how many", r[0] == f"COPIED {wires_n}", str(r))
check("no symbol definitions or fonts are written when no symbol or text is selected", not root.findall("SYMBOLDEF") and not root.findall("FONT"))
check("the sheet header is there (NAME, DETAILS with GRID)", root.find("NAME") is not None and root.find("DETAILS") is not None and root.find("DETAILS").find("GRID") is not None)
check("the root is a single sheet, as the clipboard data is", root.tag == "TinyCAD")
r = run("copy", led, clip, "class:TDrawMethod"); sym_n = int(r[0].split()[1]); root = ET.parse(clip).getroot()
used_syms = {e.get("id") for e in root if e.tag == "SYMBOL"}
check("copying symbols writes the symbol definitions they use", {s.get("id") for s in root.findall("SYMBOLDEF")} == used_syms and len(used_syms) > 0, f"{used_syms} {[s.get('id') for s in root.findall('SYMBOLDEF')]}")
n_text_font = {e.get("font") for e in root if e.get("font")}
check("and the fonts they use", {f.get("id") for f in root.findall("FONT")} >= n_text_font)
check("copying nothing writes nothing", run("copy", led, os.path.join(tmp, "none.xml"), "index:99999")[0] == "COPIED 0")

# ---- 4. pasting into a sheet that already has other fonts, styles and symbols merges them
a = designs[0]; b = led
base = os.path.join(EXAMPLES, "circuits", "Computer Operated Telescope", "Dual PSU.dsn")
if not os.path.exists(base): base = a
clipb = os.path.join(tmp, "b.xml"); run("copy", b, clipb, "class:TDrawMethod,TDrawText,TDrawLabel")
out = os.path.join(tmp, "merged.dsn"); r = run("paste", clipb, base, out)
before = objs(base); sel = [o for o in objs(b) if o[0] in ("SYMBOL", "TEXT", "LABEL")]
after = objs(out)
check("pasting into an existing design keeps what was there and adds the copied objects with the right look",
      after[:len(before)] == before and after[len(before):] == sel, f"{len(after)} vs {len(before)}+{len(sel)}")
print(f"merge: {len(sel)} symbols/texts pasted into a design with {len(before)} objects of its own, all resolved to the same look")

# ---- 5. data that is not TinyCAD's is refused and changes nothing
for name, data in (("empty", b""), ("text", b"hello world"), ("cut off", open(clip, "rb").read()[:300] if os.path.exists(clip) else b"<TinyCAD><NAME>x"), ("other xml", b"<?xml version='1.0'?><note>not a drawing</note>")):
    bad_clip = os.path.join(tmp, "bad.bin"); open(bad_clip, "wb").write(data)
    r = run("paste", bad_clip, "NEW", os.path.join(tmp, "bad.dsn"))
    check(f"refused: {name}", r[0].startswith("PASTED 0 0"), str(r))
good = open(os.path.join(tmp, "w.xml"), "rb").read()
open(os.path.join(tmp, "nul.bin"), "wb").write(good + b"\x00" * 37)
check("trailing zero bytes (Windows rounds clipboard blocks up) are ignored", run("paste", os.path.join(tmp, "nul.bin"), "NEW", os.path.join(tmp, "nul.dsn"))[0].startswith("PASTED 1"))
one = open(clip, "rb").read().split(b"?>", 1)[1]
open(os.path.join(tmp, "multi.bin"), "wb").write(b"<?xml version='1.0'?>\n<TinyCADSheets>\n" + one + b"\n" + one + b"\n</TinyCADSheets>\n")
r = run("paste", os.path.join(tmp, "multi.bin"), "NEW", os.path.join(tmp, "multi.dsn"))
check("a multi-sheet document pastes its first sheet", r[0].startswith("PASTED 1 ") and r[0].split()[2] == str(sym_n), str(r))

# ---- 6. the block reference: the snapped far corner of the pasted objects (wires only, so no symbol boxes are involved)
def snap(v, g=10.0):
    a_ = math.floor(v / g) * g
    return a_ + g if (v - a_) * 2 > g else a_
run("copy", led, os.path.join(tmp, "wires.xml"), "class:TDrawLine")
r = run("block", os.path.join(tmp, "wires.xml"), "NEW")
bx, by = [float(x) for x in [l for l in r if l.startswith("BLOCK")][0].split()[1:]]
xs, ys = [], []
for e in ET.parse(os.path.join(tmp, "wires.xml")).getroot():
    if e.tag in ("WIRE", "BUS", "LINE"):
        for k in ("a", "b"):
            x, y = (float(t) * 5 for t in e.get(k).split(",")); xs.append(x); ys.append(y)
check("block reference is the snapped far corner of the wires", (bx, by) == (snap(max(xs)), snap(max(ys))), f"{(bx, by)} vs {(snap(max(xs)), snap(max(ys)))}")
print("block reference point:", (bx, by), "= snapped far corner of the copied wires")
print("\nCLIPBOARD CHECKS PASSED" if not fails else f"\nCLIPBOARD CHECKS FAILED: {fails}")
sys.exit(1 if fails else 0)
