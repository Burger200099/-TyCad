#!/usr/bin/env python3
"""The middle mouse button moves the viewport while the left button holds a drag (the edge of a rectangle, a symbol, a rubber band) -- script commands 'mouse down/move/mdown/mup/up', 'vieworigin', 'dragmode'.
Checks (oracle: the origin printed by the program before and after, and the saved position of the dragged object):
  - during a left drag the middle press + moves change the view origin by the pointer's movement (in mm of the sheet, about 1:1 as the zoom is fixed), the drag mode stays on
  - after the middle release moves of the pointer change the origin no more, and the drag goes on and ends with the left release (drag mode 0)
  - the object ends where the pointer put it (its start + the pointer's movement in sheet units), not shifted by the panning
  - a plain middle drag with nothing held still pans (drag mode 3); moving the pointer with only the left button does not change the origin
  - a release that never came (the symbol parameter list opens under the pointer and takes it): the next move with no button held ends the drag, and later moves do not drag anything\nNeeds the built program and xvfb."""
import os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Middle pan checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:600])
dsn = os.path.join(tmp, "m.dsn")
S = ["newdoc A4", "tool rect", "mouse move 40 40", "mouse down 40 40", "mouse move 80 70", "mouse up 80 70", "tool select",
     "mouse down 60 40", "mouse move 63 42", "mouse move 66 45", "vieworigin", "dragmode",          # 1: dragging
     "mouse mdown 66 45", "dragmode", "mouse move 76 55", "vieworigin", "mouse move 70 58", "vieworigin",  # 2: panning during the drag
     "mouse mup 70 58", "dragmode", "mouse move 68 55", "vieworigin",                                    # 3: pan released
     "mouse up 68 55", "dragmode", "vieworigin", "savedocas " + dsn,
     "mouse mdown 100 100", "dragmode", "mouse move 110 100", "vieworigin", "mouse mup 110 100", "dragmode"]
f = os.path.join(tmp, "s.txt"); open(f, "w").write("\n".join(S) + "\n")
out = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=200, env=dict(os.environ, HOME=tempfile.mkdtemp(dir=tmp))).stdout.split("\n")
org = [tuple(map(float, l.split()[1:])) for l in out if l.startswith("VIEWORIGIN")]
dm = [int(l.split()[1]) for l in out if l.startswith("DRAGMODE")]
check("the script ran (six origins, six drag modes)", len(org) == 6 and len(dm) == 6, (org, dm))
if len(org) == 6 and len(dm) == 6:
    check("a left drag is under way before the middle press", dm[0] != 0, dm)
    check("the middle press does not end or change the drag", dm[1] == dm[0], dm)
    check("the pointer's movement with the middle button held moves the viewport (origin changed against the pointer's move)", org[1][0] < org[0][0] - 5 and org[1][1] < org[0][1] - 5, (org[0], org[1]))
    check("a further move with the middle button held moves the viewport again", org[2] != org[1], (org[1], org[2]))
    check("after the middle release the drag goes on (mode unchanged) and the view stays put", dm[2] == dm[0] and org[3] == org[2] and org[4] == org[2], (dm, org[2], org[3], org[4]))
    check("the left release ends the drag", dm[3] == 0, dm)
    check("a plain middle drag pans (mode 3) and the mode is 0 after its release", dm[4] == 3 and dm[5] == 0 and org[5][0] < org[4][0], (dm, org[4], org[5]))
    root = ET.parse(dsn).getroot(); rc = list(root.iter("RECTANGLE"))
    pa = [float(v) for v in rc[0].get("a", rc[0].get("pos", "0,0")).split(",")] if rc else None
    check("the dragged rectangle is in the file", len(rc) == 1, [e.attrib for e in rc])
    if rc:
        at = rc[0].attrib; xs = sorted(float(v.split(",")[0]) for k, v in at.items() if "," in v and k in ("a", "b", "pos", "pos_a", "pos_b", "point_a", "point_b")); ys = sorted(float(v.split(",")[1]) for k, v in at.items() if "," in v and k in ("a", "b", "pos", "pos_a", "pos_b", "point_a", "point_b"))
        check("the top edge was dragged by the pointer's movement on the sheet (y 40 -> the pointer's 55, the sides unchanged), not shifted by the panning", xs == [40.0, 80.0] and abs(ys[0] - 55) <= 2 and ys[1] == 70.0, (at, xs, ys))
# a release that never came (the parameter list opened under the pointer on the press): the next move with the button up ends the drag and moves nothing
lost = os.path.join(tmp, "l.dsn")
S2 = ["newdoc A4", "tool rect", "mouse move 40 40", "mouse down 40 40", "mouse move 80 70", "mouse up 80 70", "tool select",
      "mouse down 60 40", "mouse move 63 42", "dragmode", "mouse lost 66 45", "dragmode", "mouse move 90 90", "mouse move 95 99", "dragmode", "savedocas " + lost]
open(f, "w").write("\n".join(S2) + "\n")
o2 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=200, env=dict(os.environ, HOME=tempfile.mkdtemp(dir=tmp))).stdout.split("\n")
d2 = [int(l.split()[1]) for l in o2 if l.startswith("DRAGMODE")]
check("a lost release: the drag is on, then ended by the move with no button, and stays off", len(d2) == 3 and d2[0] != 0 and d2[1] == 0 and d2[2] == 0, d2)
at = [e.attrib for e in ET.parse(lost).getroot().iter("RECTANGLE")]
check("a lost release: the later moves change nothing (the rectangle is as the last drag step left it, not following the pointer to 95,99)", len(at) == 1 and float(at[0]["b"].split(",")[0]) == 80.0 and float(at[0]["b"].split(",")[1]) <= 70.0 and float(at[0]["a"].split(",")[1]) < 50, at)
print("middle pan: %d checks, %d failed" % (checks, len(fails))); sys.exit(1 if fails else 0)
