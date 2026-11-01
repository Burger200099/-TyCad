#!/usr/bin/env python3
"""The Part page of the ribbon: choosing a placed part symbol shows its part, reference and every object of the part with where each is drawn ([Page n, line n] or [unused]); the
button is Goto for a drawn object and Place for an unused one; Place puts the symbol of the object down with the part's reference; the page is there only while a symbol of the part is selected and goes with the document.  Needs xvfb-run and the built program."""
import os, re, sys, shutil, subprocess, tempfile, sqlite3
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("part ribbon checks skipped: need xvfb-run and the built program"); sys.exit(0)
sys.path.insert(0, os.path.join(HERE, "..", "docs")); import parts_seed
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name); print("  FAIL", name, str(detail)[:600])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
f = os.path.join(tmp, "p.TCParts"); parts_seed.build(f).close()
c = sqlite3.connect(f)
pid = c.execute("select PartID from Part where Name like 'Contactor%'").fetchone()[0]
objs = {r[1]: r[0] for r in c.execute("select ObjectID, Name from PartObject where PartID = ?", (pid,))}
coil, c1, c2 = objs["A1/A2"], objs["1L1-1T1"], objs["2L2-2T2"]
sid, drawing = c.execute("select SymbolID, Drawing from Symbol where PartID = ?", (pid,)).fetchone()
c.execute("update Symbol set ShowsObject = ? where SymbolID = ?", (coil, sid))                      # the default symbol draws the coil
c.execute("insert into Symbol(PartID, Standard, Purpose, Name, Drawing, ShowsObject) values (?, 'IEC', 'schematic', 'Main contact', ?, ?)", (pid, drawing, c1))
c.execute("insert into Symbol(PartID, Standard, Purpose, Name, Drawing, ShowsObject) values (?, 'IEC', 'schematic', 'Second contact', ?, ?)", (pid, drawing, c2))
c.commit(); c.close()
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env)
    return r.stdout.splitlines()
def state(out, mk):
    i = out.index(mk); l = [x for x in out[i - 3:i] if x.startswith("PARTRIBBON ") and not x.startswith("PARTRIBBON press")][-1]
    m = re.match(r"PARTRIBBON visible=(\d) title=\[(.*?)\] object=\[(.*?)\] button=\[(.*?)\] enabled=(\d) index=(-?\d+) glyph=(\d) items=\[(.*)\]$", l)
    return dict(zip(("visible", "title", "object", "button", "enabled", "index", "glyph", "items"), m.groups()))
out = run(["newdoc A4", "registerframe x all", "pdbtab open " + f, "partribbon", "echo ST00", "pdbplace 1 80 80 yes", "partribbon", "echo ST0", "clickmm 80 80", "partribbon", "echo ST1",
           "partribbon pick 2", "partribbon", "echo ST2", "partribbon press", "clickmm 120 80", "partribbon", "echo ST3",
           "tool select", "clickmm 200 150", "partribbon", "echo ST4", "selidx 1", "partribbon pick 4", "partribbon press", "clickmm 140 80", "tool select", "selidx 2", "partribbon", "echo ST6",
           "selidx 0", "partribbon pick 2", "partribbon press", "echo ST5", "sheetinfo", "tool select", "clickmm 200 150", "selidx 0", "partribbon", "echo ST8", "newdoc A4", "partribbon", "echo ST7"])
s00, s0, s1, s2 = state(out, "ST00"), state(out, "ST0"), state(out, "ST1"), state(out, "ST2")
check("with no part chosen the Part page has no tab", s00["visible"] == "0", s00)
check("a part just placed is the part", s0["visible"] == "1", s0)
check("selecting a placed part shows the page: part name and the reference K?", s1["visible"] == "1" and s1["title"].startswith("Contactor") and s1["title"].rstrip().endswith("K?"), s1)
items = s1["items"].split("|")
check("the list holds every coil, pole and contact of the part", len(items) == 7 and items[0].startswith("A1/A2") and sum(1 for i in items if i.split()[0].startswith(("Pole", "1L1", "2L2", "3L3"))) >= 6, items)
check("the coil that is drawn says [Page 1], the others [unused]", items[0].endswith("[Page 1]") and all(i.endswith("[unused]") for i in items[1:]), items)
check("the coil is chosen, its button is Goto and there is a glyph", s1["index"] == "0" and s1["button"] == "Goto" and s1["glyph"] == "1" and s1["enabled"] == "1", s1)
check("an unused contact turns the button into Place, with its own symbol drawn", s2["button"] == "Place" and s2["index"] == "2" and "Contact" in s2["object"] and s2["glyph"] == "1", s2)
i3 = out.index("ST3"); press = [l for l in out if l.startswith("PARTRIBBON press")]
check("Place puts the symbol on the cursor", press and press[0].split()[2] == "placed", press)
s3 = state(out, "ST3"); it3 = s3["items"].split("|")
check("after it is put down the contact is [Page 1] and keeps the reference K?", it3[2].endswith("[Page 1]") and s3["title"].rstrip().endswith("K?"), s3)
s4 = state(out, "ST4")
check("with nothing selected (a click on empty paper) there is no Part tab", s4["visible"] == "0", s4)
s6 = state(out, "ST6")
check("a second object put down says [Page 1] too", s6["visible"] == "1" and s6["items"].split("|")[4].endswith("[Page 1]") and s6["items"].split("|")[2].endswith("[Page 1]"), s6)
g = [l for l in out if l.startswith("PARTRIBBON press goto")]
check("Goto on a drawn object runs", len(g) == 1, g)
s8 = state(out, "ST8"); i8 = s8["items"].split("|")
check("choosing the coil afresh lists the contacts put down as placed at once (found when the symbol is chosen)", i8[2].endswith("[Page 1]") and i8[4].endswith("[Page 1]"), s8)
s7 = state(out, "ST7")
check("a new document ends it", s7["visible"] == "0", s7)
out = run(["newdoc A4", "registerframe x all", "pdbtab open " + f, "pdbpreview 1", "pdbpreview 1 dbl 90 90"])
pv = [l for l in out if l.startswith("PDBPREVIEW")]
check("choosing a part shows its default symbol in the preview", pv and pv[0].endswith("shown=1"), pv)
check("double clicking the preview places the part", len(pv) == 3 and pv[2].endswith("objects=1"), pv)
print("part ribbon: %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
