"""Rung grid, "Above block": the bottom of the table is the top of the title block (or of its extended cell), the bottom indent is ignored, and the table follows
later changes to the block. Oracle: the block geometry worked out by hand (A4 landscape 1485 x 1050 units of 0.2 mm; block 9 lines of 18 high, 2 in from the edge,
15 more for the rulers; the extended cell adds 36 above) in Python, and the first line of a sheet without the option."""
import os, re, subprocess, sys, tempfile
exe = os.environ.get("TC_GUI_BIN", "/tmp/sch")
tmp = tempfile.mkdtemp()
open(tmp + "/s.txt", "w").write(f"""newdoc "ISO A4" landscape
tool rungs
setrungs 10 1 5 1 1 1 0
echo OFF
rungs
setrungs 10 1 20 1 1 1 1
echo ON_BIGMARGIN
rungs
details ext 1
echo EXT
rungs
details rulers 1
echo RULERS
rungs
details visible 0
echo HIDDEN
rungs
save {tmp}/a.dsn
open {tmp}/a.dsn
echo REOPEN
rungs
""")
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", tmp + "/s.txt"], capture_output=True, text=True, timeout=240)
o = r.stdout.split("\n")
def bottom(tag):
    i = o.index(tag); l = [x for x in o[i + 1:] if x.startswith("RUNGAREA")][0]
    return float(l.split()[4]), float(l.split()[2])        # bottom, top (mm)
H = 210.0; blocktop = (1050 - 18 * 9 - 2) / 5
bad = []
def check(n, ok, d=""):
    print(("ok   " if ok else "FAIL ") + n + ("" if ok else " " + str(d)))
    if not ok: bad.append(n)
check("without the option the table ends at the bottom of the sheet less the indent and border (210 - 5 - 6.35)", abs(bottom("OFF")[0] - (H - 5 - 6.35)) < 0.01, bottom("OFF"))
check("with it, the table ends on the top of the title block whatever the bottom indent (20 mm here)", abs(bottom("ON_BIGMARGIN")[0] - blocktop) < 0.01 and abs(bottom("ON_BIGMARGIN")[1] - (20 + 6.35)) < 0.01, bottom("ON_BIGMARGIN"))
check("the extended cell pushes it up by 36 units (7.2 mm)", abs(bottom("EXT")[0] - (blocktop - 7.2)) < 0.01, bottom("EXT"))
check("the rulers move the block up 15 units (3 mm) and the table with it", abs(bottom("RULERS")[0] - (blocktop - 7.2 - 3)) < 0.01, bottom("RULERS"))
check("with no title block shown the table goes back to the sheet's bottom (indent ignored: edge less the border)", abs(bottom("HIDDEN")[0] - (H - 20 - 6.35)) < 0.01, bottom("HIDDEN"))
check("the option is saved and read back", 'aboveblock' in open(tmp + "/a.dsn").read() and abs(bottom("REOPEN")[0] - (H - 20 - 6.35)) < 0.01, bottom("REOPEN"))
sys.exit(1 if bad else 0)
