"""The table editor window keeps its left/top/width/height between sessions (registry; a file on Linux) and is moved back on screen, with the same width and height, when it is
shown off screen. Oracle: TABLEBOUNDS script output. Needs xvfb-run (screen 1600x1000) and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Table bounds checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = tempfile.mkdtemp(dir=tmp)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:300])
def run(script):
    p = os.path.join(tmp, "s.txt"); open(p, "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", p], capture_output=True, text=True, timeout=300,
                       env=dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.splitlines()
def bounds(out):
    return [tuple(map(int, m.groups())) for l in out for m in [re.match(r"TABLEBOUNDS (-?\d+) (-?\d+) (\d+) (\d+)", l)] if m]
mk = "newdoc A4\ngridmm 2\nregisterframe x all\ntable new\nmouse move 150 60\nmouse down 150 60\nmouse up 150 60\n"
b = bounds(run(mk + "table bounds 100 120 500 300\n"))
check("a place on screen is kept", b == [(100, 120, 500, 300)], b)
b = bounds(run(mk + "table info\n" + "table bounds 5000 4000 500 300\n"))
check("off screen: moved back with the same width and height", len(b) == 1 and b[0][2:] == (500, 300) and 0 <= b[0][0] <= 1100 and 0 <= b[0][1] <= 700, b)
b = bounds(run(mk + "table bounds -900 -700 500 300\n"))
check("off screen to the top left: moved back", len(b) == 1 and b[0][2:] == (500, 300) and b[0][0] >= 0 and b[0][1] >= 0, b)
b = bounds(run(mk + "table bounds 0 0 20000 300\n"))
check("wider than the screen: made to fit", len(b) == 1 and b[0][2] <= 1600, b)
b = bounds(run(mk + "table bounds 120 140 500 300\ntable ontop on\ntable bounds 120 140 500 300\ntable ontop off\n"))
out = run(mk + "table bounds 120 140 500 300\ntable ontop on\ntable ontop off\ntable bounds 120 140 500 300\n")
check("always on top on and off keeps the window where it is", bounds(out)[-1] == (120, 140, 500, 300), out[-3:])
# selecting the table with the mouse: the editor appears only once the button is up
out = run("newdoc A4\ngridmm 2\ntable new\nmouse move 100 60\nmouse down 100 60\nmouse up 100 60\nselclear\ntable info\nmouse down 90 50\ntable info\nmouse up 90 50\ntable info\n")
ed = [l for l in out if l.startswith("TABLE editor=")]
check("editor shown only after the mouse button is released", len(ed) == 3 and ed[0].startswith("TABLE editor=0") and ed[1].startswith("TABLE editor=0") and ed[2].startswith("TABLE editor=1"), ed)
# closing the program with a table selected and its editor closed: the question about unsaved designs must not bring the editor up
out = run("newdoc A4\ngridmm 2\ntable new\nmouse move 100 60\nmouse down 100 60\nmouse up 100 60\ntable close\ntable closequery\ntable info\n")
ed = [l for l in out if l.startswith("TABLE editor=")]
check("closing the program does not bring the closed editor up", len(ed) == 1 and ed[0].startswith("TABLE editor=0"), ed)
# the arrow of a cell: the list is asked for on the release, also when the grid has opened its cell editor by then
for extra, what in (("", "plain"), (" editor", "with the cell editor open")):
    out = run("newdoc A4\ngridmm 2\naddtext 80 120 Visible\ntable new\nmouse move 150 60\nmouse down 150 60\nmouse up 150 60\ntable pickauto -1\ntable arrow 1 1" + extra + "\n")
    pk = [l for l in out if l.startswith("TABLEPICK")]
    v = pk[0].split() if pk else []
    check("the arrow asks for the list (%s)" % what, len(v) == 6 and v[1] == "1", (pk, out[-3:]))
    # the list is put just under the cell, not at the top left of the screen
    check("the list is under the cell (%s)" % what, len(v) == 6 and int(v[3]) > 60 and abs(int(v[2]) - int(v[4])) <= 40 and abs(int(v[3]) - int(v[5])) <= 40, pk)
print("table bounds: %d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
