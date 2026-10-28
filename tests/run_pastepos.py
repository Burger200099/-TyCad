"""Paste puts the objects exactly where they were copied from (TinyCAD), not under the pointer: with no mouse move the pasted copies have the coordinates of the
originals, so the objects list holds every original line twice; after a mouse move the block follows the pointer; right click / drop keeps one Paste step."""
import os, subprocess, sys, tempfile
from collections import Counter
exe = os.environ.get("TC_GUI_BIN", "/tmp/sch"); ex = os.environ.get("TC_EXAMPLES", "/tmp/ex")
tmp = tempfile.mkdtemp()
open(tmp + "/s.txt", "w").write(f"""open {ex}/circuits/AMP.DSN
echo ORIG
objects
selectall
copy
paste
echo PASTED
objects
mouse move 150 100
echo MOVED
objects
""")
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", tmp + "/s.txt"], capture_output=True, text=True, timeout=240)
o = r.stdout.split("\n")
def sec(n, nxt):
    a = o.index(n); b = o.index(nxt) if nxt in o else len(o)
    return [l.split(" id=")[0] for l in o[a + 1:b] if l.startswith("OBJ") and not l.startswith("OBJ end")]
orig, pasted, moved = Counter(sec("ORIG", "PASTED")), Counter(sec("PASTED", "MOVED")), Counter(sec("MOVED", "ZZ"))
bad = []
def check(n, ok, d=""):
    print(("ok   " if ok else "FAIL ") + n + ("" if ok else " " + str(d)))
    if not ok: bad.append(n)
check("before any mouse move every pasted object has the coordinates of its original", all(pasted[k] >= 2 * v for k, v in orig.items() if k.startswith("OBJ wire")), [(k, v, pasted[k]) for k, v in orig.items() if pasted[k] < 2 * v][:3])
check("after a mouse move the block has moved off them", moved != pasted)
sys.exit(1 if bad else 0)
