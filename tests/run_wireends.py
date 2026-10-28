"""Wire end handles: a wire picked by a click (or only touched by a box) is stretched by dragging an
end; a wire wholly inside the picking box is moved. Expected numbers are worked out by hand
(design units are 0.2 mm, so mm * 5)."""
import os, subprocess, sys, tempfile
exe = os.environ.get("TC_GUI_BIN", "/tmp/sch")
tmp = tempfile.mkdtemp()
script = """newdoc "ISO A4" landscape
tool wire
mouse move 40 40
mouse down 40 40
mouse up 40 40
mouse move 80 40
mouse down 80 40
mouse up 80 40
tool select
clickmm 60 40
mouse move 80 40
mouse down 80 40
mouse move 100 40
mouse move 100 60
mouse up 100 60
echo STRETCH
objects
undo
selectall
mouse move 80 40
mouse down 80 40
mouse move 100 60
mouse up 100 60
echo WHOLE
objects
undo
clickmm 150 120
clickmm 60 40
mouse move 40 40
mouse down 40 40
mouse move 20 40
mouse up 20 40
echo FIRSTEND
objects
newdoc "ISO A4" landscape
tool wire
mouse move 40 40
mouse down 40 40
mouse up 40 40
mouse move 100 40
mouse down 100 40
mouse up 100 40
tool wire
mouse move 70 80
mouse down 70 80
mouse up 70 80
mouse move 70 40
mouse down 70 40
mouse up 70 40
tool select
clickmm 70 60
mouse move 70 40
mouse down 70 40
mouse move 70 30
mouse up 70 30
echo JUNCTION
sel
"""
open(tmp + "/s.txt", "w").write(script)
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", tmp + "/s.txt"],
                   capture_output=True, text=True, timeout=240)
out = r.stdout.split("\n")
def wire(after):
    i = out.index(after)
    return [tuple(float(x) for x in l.split()[2:6]) for l in out[i + 1:] if l.startswith("OBJ wire")][0]
bad = []
def check(n, ok, d=""):
    print(("ok   " if ok else "FAIL ") + n + ("" if ok else " " + str(d)))
    if not ok: bad.append(n)
w = wire("STRETCH"); check("a clicked wire is stretched by its end handle (other end stays)", w == (200, 200, 500, 300), w)
w = wire("WHOLE");   check("a wholly selected wire is moved by its end handle", w == (300, 300, 500, 300), w)
w = wire("FIRSTEND"); check("the first end stretches too", w == (100, 200, 400, 200), w)
i = out.index("JUNCTION")
sel = [l for l in out[i + 1:] if l.startswith("SEL ")]
check("a handle on a junction dot drags the wire, and the dot is not picked", sel == ["SEL 1 [TDrawLine]"], sel)
sys.exit(1 if bad else 0)
