"""A placed Measure A-B ruler has a handle on each end: dragging one moves that end only (the other stays), Shift makes the ruler level or plumb about the other end, and one undo
takes the drag back. Oracle: the saved XML (MEASURE a= and b=). Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Measure ends checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:300])
def run(script):
    p = os.path.join(tmp, "s.txt"); open(p, "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", p], capture_output=True, text=True, timeout=300,
                       env=dict(os.environ, HOME=tmp, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.splitlines()
def ends(path):
    t = open(path, encoding="utf-8").read()
    m = re.search(r"<MEASURE [^>]*?a='([^']*)' b='([^']*)'", t)
    return ([float(v) for v in m.group(1).split(",")], [float(v) for v in m.group(2).split(",")]) if m else None
mk = "newdoc A4\ngridmm 2\ntool measure\nmouse down 100 100\nmouse move 140 100\nmouse up 140 100\ntool select\n"
def go(extra, name):
    f = os.path.join(tmp, name + ".dsn"); run(mk + extra + f'save "{f}"\n'); return ends(f)
e = go("mouse down 140 100\nmouse move 150 110 plain\nmouse up 150 110\n", "b")
check("end B dragged: B moves, A stays", e and e[0] == [100.0, 100.0] and abs(e[1][0] - 150) < 1 and abs(e[1][1] - 110) < 1, e)
e = go("mouse down 100 100\nmouse move 90 110 plain\nmouse up 90 110\n", "a")
check("end A dragged: A moves, B stays", e and e[1] == [140.0, 100.0] and abs(e[0][0] - 90) < 1 and abs(e[0][1] - 110) < 1, e)
e = go("mouse down 100 100\nmouse move 80 108 shift\nmouse up 80 108\n", "s")
check("Shift: the ruler is level about the other end", e and abs(e[0][1] - e[1][1]) < 1e-6 and abs(e[0][0] - 80) < 1, e)
e = go("mouse down 140 100\nmouse move 143 160 shift\nmouse up 143 160\n", "v")
check("Shift: the ruler is plumb about the other end", e and abs(e[0][0] - e[1][0]) < 1e-6 and abs(e[1][1] - 160) < 1, e)
e = go("mouse down 140 100\nmouse move 150 110 plain\nmouse up 150 110\nundo\n", "u")
check("one undo takes the drag back", e and abs(e[1][0] - 140) < 1 and abs(e[1][1] - 100) < 1, e)
print("Measure ends checks: %d run, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
