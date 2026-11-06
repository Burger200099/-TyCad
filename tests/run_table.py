"""Insert > Insert Table: a table floats on the pointer (its bottom right corner at the pointer) until a click places it; the table editor window (always on top) opens with it, edits go into the table with
undo, rows and columns can be inserted and deleted, the titles can be hidden, the grid is solid, dashed or hidden, the table is the size of its text until a handle
resizes it, it is saved as <TABLE> and read back, and the editor goes away when the table is not the chosen object. Oracle: TABLE / TABLECELL script output, saved XML.
Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Table checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:400])
def run(script):
    p = os.path.join(tmp, "s.txt"); open(p, "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", p], capture_output=True, text=True, timeout=300,
                       env=dict(os.environ, HOME=tempfile.mkdtemp(dir=tmp), FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.splitlines()
def infos(out):
    res = []
    for l in out:
        if l.startswith("TABLE ") and "none" not in l:
            d = dict(re.findall(r"(\w+)=(\S+)", l)); res.append(d)
    return res
def cells(out):
    return {(int(m.group(1)), int(m.group(2))): m.group(3) for l in out for m in [re.match(r"TABLECELL (\d+) (\d+) ?(.*)", l)] if m}
place = "newdoc A4\ngridmm 2\ntable new\ntable info\nmouse move 100 60\nmouse down 100 60\nmouse up 100 60\n"
out = run(place + "table info\n")
i = infos(out)
check("while floating: the editor is open, on top of the program only, the table is pasting", len(i) == 2 and i[0]["editor"] == "1" and i[0]["ontop"] == "1" and i[0]["pasting"] == "1", out[-6:])
check("3 columns, titles row + 3 rows, titles shown, solid grid", i and i[0]["cols"] == "3" and i[0]["rows"] == "4" and i[0]["titles"] == "1" and i[0]["grid"] == "0", i)
check("placed: not floating any more, the editor stays", len(i) == 2 and i[1]["pasting"] == "0" and i[1]["editor"] == "1", i)
w0, h0 = float(i[1]["w"]), float(i[1]["h"])
out = run(place + "table cell 0 0 Component\ntable cell 1 0 Resistor 10k 1/4W metal film\ntable cell 1 1 R1\ntable info\n")
i = infos(out)[-1]; c = cells(out)
check("typed cells are in the table", c.get((0, 0)) == "Component" and c.get((1, 0)) == "Resistor 10k 1/4W metal film" and c.get((1, 1)) == "R1", c)
check("the table grows with its text", float(i["w"]) > w0 + 10, (i["w"], w0))
out = run(place + "table cell 1 0 Resistor 10k 1/4W metal film\ntable info\nundo\ntable info\n")
ii = infos(out); c2 = cells(out)
check("one undo takes the typing back", ii[-1]["w"] != ii[-2]["w"] and abs(float(ii[-1]["w"]) - w0) < 1, (ii[-2:], w0))
out = run(place + "table ontop on\ntable info\ntable ontop off\ntable info\n")
ii = infos(out)
check("Always on top: on = over every program (system=1), off = over this program only", [x["system"] for x in ii[-2:]] == ["1", "0"] and ii[-2]["editor"] == "1" and ii[-1]["editor"] == "1", ii[-2:])
out = run(place + "table titles off\ntable info\n")
check("titles off: the table is shorter", float(infos(out)[-1]["h"]) < h0 - 3 and infos(out)[-1]["titles"] == "0", (infos(out)[-1], h0))
out = run(place + "table grid dashed\ntable info\ntable grid hidden\ntable info\n")
check("grid dashed (1) and hidden (2)", [x["grid"] for x in infos(out)[-2:]] == ["1", "2"], infos(out)[-2:])
out = run(place + "table row ins 2\ntable col ins 1\ntable info\n")
i = infos(out)[-1]
check("a row and a column inserted", i["rows"] == "5" and i["cols"] == "4", i)
out = run(place + "table row del 3\ntable col del 2\ntable info\ntable row del 0\ntable info\n")
ii = infos(out)
check("a row and a column deleted; the titles row cannot be", ii[-2]["rows"] == "3" and ii[-2]["cols"] == "2" and ii[-1]["rows"] == "3", ii[-2:])
f = os.path.join(tmp, "t.dsn")
run(place + "table cell 0 1 Ref\\x\ntable cell 2 2 a b\ntable grid dashed\nselclear\nsave \"%s\"\n" % f)
t = open(f, encoding="utf-8").read(); m = re.search(r"<TABLE [^>]*>", t)
check("saved as <TABLE> with cols, rows and data", m and "cols='3'" in m.group(0) and "rows='4'" in m.group(0) and "grid='1'" in m.group(0) and "data='" in m.group(0), m and m.group(0))
out = run('open "%s"\nselectall\ntable info\n' % f)
c = cells(out); i = infos(out)
check("read back: cells and grid", c.get((0, 1)) == "Ref\\x" and c.get((2, 2)) == "a b" and i and i[-1]["grid"] == "1", (c, i))
out = run(place + "selclear\ntable info\nmouse down 90 50\nmouse up 90 50\ntable info\n")
check("not chosen: no editor; clicking the table brings it back", "TABLE editor=0 none" in out and infos(out)[-1]["editor"] == "1", [l for l in out if l.startswith("TABLE")])
corner = "mouse down %s %s\nmouse move %s %s plain\nmouse up %s %s\n"
w, h = w0, h0
out = run(place + (corner % (100, 60, 130, 80, 130, 80)) + "table info\n")
i = infos(out)[-1]
check("a handle resizes it (no longer the size of the text)", i["auto"] == "0" and float(i["w"]) > w0 + 20 and float(i["h"]) > h0 + 12, (i, w0, h0))
out = run(place + "registerframe x all\nframeinfo sel\n")
check("the ribbon shows the Font part of the text frame: 207 wide, no text panel", any("TfmPropTable width=207" in l and "problems=0" in l for l in out) and any("plText TPanel text hidden" in l for l in out) and any("cbFont " in l and "font.face" in l for l in out), out[-9:])
print("table: %d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
