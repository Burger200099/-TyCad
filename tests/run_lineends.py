"""A plain line (not a wire) is manipulated like a wire: a clicked or partly picked line is stretched by dragging an end handle (the other end stays), a wholly
picked one (Select All) is moved by it, and the first end works too. The expected values are relative to what the same gestures leave on the line, worked out
from the line as drawn."""
import os, re, subprocess, sys, tempfile
exe = os.environ.get("TC_GUI_BIN", "/tmp/sch")
tmp = tempfile.mkdtemp()
draw = """newdoc "ISO A4" landscape
tool line
mouse move 40 40
mouse down 40 40
mouse up 40 40
mouse move 80 40
mouse down 80 40
mouse up 80 40
tool select
"""
def run(gesture):
    open(tmp + "/s.txt", "w").write(draw + gesture + f"save {tmp}/o.dsn\n")
    subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", tmp + "/s.txt"], capture_output=True, text=True, timeout=240)
    m = re.search(r"<LINE [^>]*a='([-\d.]+),([-\d.]+)' b='([-\d.]+),([-\d.]+)'", open(tmp + "/o.dsn").read())
    return tuple(float(x) for x in m.groups())
orig = run("")
bad = []
def check(n, ok, d=""):
    print(("ok   " if ok else "FAIL ") + n + ("" if ok else " " + str(d)))
    if not ok: bad.append(n)
ax, ay, bx, by = orig
u = (bx - ax) / 40.0                      # design units per mm as the line was drawn
s = run("clickmm 60 40\nmouse move 80 40\nmouse down 80 40\nmouse move 100 40\nmouse move 100 60\nmouse up 100 60\n")
check("a clicked line is stretched by its second end handle (first end stays)", s[:2] == (ax, ay) and abs(s[2] - (bx + 20 * u)) < 1e-6 and abs(s[3] - (by + 20 * u)) < 1e-6, (orig, s))
f = run("clickmm 60 40\nmouse move 40 40\nmouse down 40 40\nmouse move 20 40\nmouse up 20 40\n")
check("and by its first end handle (second end stays)", f[2:] == (bx, by) and abs(f[0] - (ax - 20 * u)) < 1e-6 and f[1] == ay, (orig, f))
w = run("selectall\nmouse move 80 40\nmouse down 80 40\nmouse move 100 60\nmouse up 100 60\n")
check("a wholly selected line is moved by an end handle", abs(w[0] - (ax + 20 * u)) < 1e-6 and abs(w[2] - (bx + 20 * u)) < 1e-6 and abs(w[3] - (by + 20 * u)) < 1e-6, (orig, w))
m = run("clickmm 60 40\nmouse move 60 40\nmouse down 60 40\nmouse move 70 50\nmouse up 70 50\n")
check("dragging the middle of a clicked line still moves the whole line", abs(m[0] - (ax + 10 * u)) < 1e-6 and abs(m[2] - (bx + 10 * u)) < 1e-6, (orig, m))
sys.exit(1 if bad else 0)
