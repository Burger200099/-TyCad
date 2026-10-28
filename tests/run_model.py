"""Checks of properties / mass change, line-number links and undo/redo, against independent references."""
import os, sys, re, subprocess, tempfile, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xml.etree.ElementTree as ET
from canon import canon_file, diff
BUILD = os.environ.get("TC_BUILD", "build"); EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
EXE = os.path.join(BUILD, "modeltest"); tmp = tempfile.mkdtemp(); fails = []
def check(n, ok, d=""):
    if not ok: fails.append(n); print("  FAIL", n, d)
def run(*a): 
    r = subprocess.run([EXE, *a], capture_output=True, text=True)
    if r.returncode != 0: raise SystemExit("modeltest failed: " + r.stderr[-300:])
    return r.stdout.split("\n")

# ---------------- properties and mass change ----------------
out = run("props", os.path.join(tmp, "props.dsn"))
def common(title): return next(l for l in out if l.startswith(title + ":")).split(":")[1].split()
check("text+label share text, direction and the font", common("text+label") == ["text", "dir", "font.face", "font.height", "font.bold", "font.italic", "font.color"], str(common("text+label")))
check("text+ladder share only the font", common("text+ladder") == ["font.face", "font.height", "font.bold", "font.italic", "font.color"])
check("wire+polygon+rectangle share the line", common("wire+polygon+rect") == ["line.color", "line.width", "line.style"])
check("text+wire share nothing", common("text+wire") == [])
text = "\n".join(out)
check("font size mass change reached all four objects", "changed 4 font.height now=20 mixed=0" in text)
check("bold/italic/face/color reached all four", all(s in text for s in ("bold: 4 1", "italic: 4 1", "face: 4 Courier New", "font color: 4 FF0000 raw=0000FF 0000FF")))
check("objects without the property are skipped", "text on text,wire,label: changed 2 -> changed / changed" in text)
check("line color/width/style over three kinds", all(s in text for s in ("line color: 3 00FF00 mixed=0", "line width: 3 4", "line style: 3 Dash wire default style now=0")))
check("fill over polygon+rectangle", "fill type: 2 Solid" in text and "fill color: 2 0000FF" in text)
check("ladder properties: bus labels, line density and colour", "ladder: N M width=5 color=563412 common=5" in text)
check("the numbering properties of the first version are gone", "old keys: 000" in text)
check("bad input is ignored", "bad number leaves width=5" in text and "width 0 becomes 1" in text)
root = ET.parse(os.path.join(tmp, "props.dsn")).getroot().find("TinyCAD")
fonts = {f.get("id"): {c.tag: c.text for c in f} for f in root.findall("FONT")}
used = {e.get("font") for e in root if e.tag in ("TEXT", "LABEL", "NOTE_TEXT", "LADDER")}
check("saved: the four text objects share one 20 pt (27 px) bold italic Courier New font", len(used) == 1 and
      all(fonts[u]["HEIGHT"] == "-27" and fonts[u]["WEIGHT"] == "700" and fonts[u]["ITALIC"] == "1" and fonts[u]["FACENAME"] == "Courier New" for u in used), str((used, fonts)))
styles = {s.get("id"): {c.tag: c.text for c in s} for s in root.findall("STYLE")}
wire = root.find("WIRE"); st = styles[wire.get("style")]
check("saved: the wire got its own style (green, 4 thick, dashed)", (st["COLOR"], st["THICKNESS"], st["STYLE"]) == ("00FF00", "4", "1"), str(st))
fills = {f.get("id"): {c.tag: c.text for c in f} for f in root.findall("FILL")}
fl = fills[root.find("RECTANGLE").get("fill")]
check("saved: the rectangle's fill is solid blue (BGR 'FF0000')", fl["INDEX"] == "0" and fl["COLOR"] == "FF0000", str(fl))
print("properties: shared sets for 4 mixed selections; mass change of font, line, fill and ladder values; skipping and bad input; saved resources checked")

# ---------------- links ----------------
lib = os.path.join(EXAMPLES, "libraries", "gen_passive.TCLib")
out = run("links", lib, os.path.join(tmp, "links.dsn")); text = "\n".join(out)
ys = [float(x) for x in re.search(r"mid y of parts: (\S+) (\S+) (\S+)", text).groups()]
def line1(y): return min(max(math.floor((y - 100) / 85), 0), 9) + 1                   # sheet 1: rung grid, 20 mm indent, 10 rows of 85, numbered from 1
def line2(y): return 20 + min(max(math.floor((y - 100) / 212.5), 0), 3)              # sheet 2: 4 rows of 212.5, numbered from 20
a, b, c = ys
check("line of K1a", f"line of K1a = [{line1(a)}]" in text, text)
check("contacts of K1a (other sheet shown as sheet.line)", f"contacts of K1a = [{line1(b)}, 2.{line2(c)}]" in text, text)
check("K1b seen from sheet 2", f"from sheet 2, K1b = [1.{line1(b)}]" in text)
b2 = b - 170
check("text follows a moved object", f"contacts of K1a = [{line1(b2)}, 2.{line2(c)}]  K1b seen from sheet 2 = [1.{line1(b2)}]" in text, text)
check("in the indent the line is unknown", "K1a in the indent: its line = [?]" in text)
check("renumbering the grid shows through", f"line of K1a = [{line1(a) + 100}]" in text, text)
check("deleted target", "target deleted: [?]" in text)
saved = ET.parse(os.path.join(tmp, "links.dsn")).getroot().findall("TinyCAD")
xrefs = [(i, x.attrib) for i, s in enumerate(saved) for x in s.findall("XREF")]
check("links saved by object id", len(xrefs) == 3 and all(int(x["target"]) > 0 for _, x in xrefs), str(xrefs))
print("links: line numbers, contact lists across sheets, following moves/renumbering/deletion all match an independent computation; stored by id")

# ---------------- undo / redo ----------------
led = os.path.join(EXAMPLES, "circuits", "Computer Operated Telescope", "LED Plate.dsn")
d = os.path.join(tmp, "undo"); os.makedirs(d)
out = run("undo", led, d); text = "\n".join(out)
check("no undo/redo failures", "FAILED" not in text, text)
st = [canon_file(os.path.join(d, f"state{k}.dsn")) for k in range(5)]
for k in range(4): check(f"edit {k+1} changed the design", bool(diff(st[k], st[k + 1], limit=1)))
for k in (3, 2, 1, 0): check(f"undo back to state {k}", not diff(st[k], canon_file(os.path.join(d, f"undone{k}.dsn"))), str(diff(st[k], canon_file(os.path.join(d, f"undone{k}.dsn")), limit=2)))
for k in (1, 2, 3, 4): check(f"redo forward to state {k}", not diff(st[k], canon_file(os.path.join(d, f"redone{k}.dsn"))), str(diff(st[k], canon_file(os.path.join(d, f"redone{k}.dsn")), limit=2)))
check("history counts", "undo steps: 4" in text and "can undo now: 0 can redo: 1" in text and "after redo: can redo=0 can undo=1" in text, text)
check("a new change clears redo", "a new change clears redo: 1" in text)
print("undo/redo: 4 edits (draw, delete, mass change, move) undone and redone one at a time; every state identical to the original; history behaves")
print("\nMODEL CHECKS PASSED" if not fails else f"\nMODEL CHECKS FAILED: {fails}")
sys.exit(1 if fails else 0)
