#!/usr/bin/env python3
"""Right click on a wire: "Add wire cut here" (new in this program) on the real program under Xvfb.
Oracles: the wires are read back from the saved design file (XML); the expectation is plain geometry - two wires, the first from the old first end to a
point Q, the second from Q to the old second end, Q on the old wire (cross product 0), strictly between the ends, on the 2.5 grid, nearest to the click.
  - a wire: the menu's first item is Add wire cut here; a bus and a line do not have it
  - choosing it makes two wires that join at Q and together cover the old one; Q is the grid point nearest the click
  - one undo brings the single wire back; redo cuts it again
  - a click at an end of the wire does not offer the item
Needs the built program and xvfb."""
import os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Wire cut checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:600])
k = [0]
def run(lines):
    k[0] += 1; h = os.path.join(tmp, "h%d" % k[0]); os.makedirs(h)
    f = os.path.join(tmp, "s%d.txt" % k[0]); open(f, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
def firstitem(o):
    for l in o:
        m = re.match(r"CTX (\d+) (\S+) enabled=(\d)", l)
        if m: return m.group(2)
def wires(path, tag="WIRE"):
    r = ET.parse(path).getroot(); res = []
    for e in r.iter(tag):
        res.append(([float(x) for x in e.get("a").split(",")], [float(x) for x in e.get("b").split(",")]))
    return res
def body(x): return '<?xml version="1.0"?>\n<TinyCADSheets><TinyCAD><NAME>a</NAME><DETAILS><Size width="1485" height="1050"/><GRID spacing="250" snap="1"/></DETAILS>%s</TinyCAD></TinyCADSheets>\n' % x
A, B = [100, 100], [300, 250]
for tag in ("WIRE", "BUS", "LINE"):
    src = os.path.join(tmp, tag + ".dsn"); open(src, "w").write(body('<%s a="100,100" b="300,250"/>' % tag))
    o = run(["open " + src, "ctxmenu 200 175"])
    check("%s: first menu item is %s" % (tag, "Add wire cut here" if tag == "WIRE" else "not the cut"), (firstitem(o) == "Add_wire_cut_here") == (tag == "WIRE"), firstitem(o))
src = os.path.join(tmp, "WIRE.dsn")
for click in ((200, 175), (140, 130), (260, 220)):
    out = os.path.join(tmp, "cut%d.dsn" % click[0])
    run(["open " + src, "ctxmenu %d %d" % click, "ctxclick Add_wire_cut_here", "save " + out])
    w = wires(out) if os.path.exists(out) else []
    check("click %s: two wires" % (click,), len(w) == 2, w)
    if len(w) == 2:
        (a1, b1), (a2, b2) = w
        q = b1
        check("click %s: they join at the cut point" % (click,), a1 == A and a2 == q and b2 == B, w)
        cross = (q[0] - A[0]) * (B[1] - A[1]) - (q[1] - A[1]) * (B[0] - A[0])
        check("click %s: the cut point is on the old wire" % (click,), abs(cross) < 1e-6 * 1000, cross)
        check("click %s: strictly between the ends" % (click,), A[0] < q[0] < B[0] and A[1] < q[1] < B[1], q)
        check("click %s: nearest to the click" % (click,), abs(q[0] - click[0]) <= 8 and abs(q[1] - click[1]) <= 8, (q, click))
# undo / redo
out = os.path.join(tmp, "undo.dsn"); out2 = os.path.join(tmp, "redo.dsn")
run(["open " + src, "ctxmenu 200 175", "ctxclick Add_wire_cut_here", "undo", "save " + out])
check("undo: one wire again, the old ends", wires(out) == [(A, B)], wires(out) if os.path.exists(out) else None)
run(["open " + src, "ctxmenu 200 175", "ctxclick Add_wire_cut_here", "undo", "redo", "save " + out2])
check("redo: two wires", len(wires(out2)) == 2 if os.path.exists(out2) else False)
# at an end
o = run(["open " + src, "ctxmenu 100 100"])
check("a click at the end of the wire: no cut offered", firstitem(o) != "Add_wire_cut_here", firstitem(o))
print("wire cut checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
