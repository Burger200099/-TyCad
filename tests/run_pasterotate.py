"""Rotating the pasted block while it floats: Rotate Left changes it, Rotate Right after it puts it back, and the drop leaves ONE undo step ("Paste")
that removes everything again (the rotation made no step of its own and did not replace the paste's snapshot)."""
import os, subprocess, sys, tempfile
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
menuclick miRotateL
echo LEFT
objects
menuclick miRotateR
echo BACK
objects
mouse down 150 100
mouse up 150 100
undoinfo
undo
echo UNDONE
objects
""")
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", tmp + "/s.txt"], capture_output=True, text=True, timeout=240)
o = r.stdout.split("\n")
def sec(n, nxt):
    a = o.index(n); b = o.index(nxt) if nxt in o else len(o)
    return [l for l in o[a + 1:b] if l.startswith("OBJ")]
orig = sec("ORIG", "PASTED"); pasted = sec("PASTED", "LEFT"); left = sec("LEFT", "BACK"); back = sec("BACK", "UNDONE"); undone = sec("UNDONE", "ZZ")
bad = []
def check(n, ok, d=""):
    print(("ok   " if ok else "FAIL ") + n + ("" if ok else " " + str(d)))
    if not ok: bad.append(n)
check("Rotate Left turns the floating block", left != pasted and len(set(left) ^ set(pasted)) > 20, (len(left), len(pasted), len(set(left) ^ set(pasted))))
def lens(sec):
    out = []
    for l in sec:
        t = l.split()
        if t[1] == "wire": out.append(round(abs(float(t[4]) - float(t[2])) + abs(float(t[5]) - float(t[3])), 3))
    return sorted(out)
check("Rotate Right after it turns it back: same wires (lengths), same count (it may sit a grid step off: the centre is snapped)", lens(back) == lens(pasted) and len(back) == len(pasted), (len(back), len(pasted)))
check("one undo step, Paste", 'next="Paste"' in r.stdout and "undo=1" in r.stdout, [l for l in o if l.startswith("UNDOINFO")])
check("undo removes the pasted objects and leaves the design as opened", undone == orig, (len(undone), len(orig)))
sys.exit(1 if bad else 0)
