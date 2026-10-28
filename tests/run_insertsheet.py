#!/usr/bin/env python3
"""Right click on a sheet's tab, "Insert sheet": the new sheet goes right after the one clicked, on the real program under Xvfb.
Oracle: a design with nine named sheets (S1..S9) written here; the order of the sheet names in the saved file (XML) is compared with plain list work.
  - right click on sheet 3 (index 2) and Insert sheet: S1 S2 S3 <new> S4 .. S9 (ten sheets), and the new sheet is the one shown (index 3)
  - on the last sheet: the new sheet is last; on the first: second
  - one undo takes the new sheet away and gives the old order back
  - the ribbon's Add Sheet still adds at the end
Needs the built program and xvfb."""
import os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Insert sheet checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:500])
k = [0]
def run(lines):
    k[0] += 1; f = os.path.join(tmp, "s%d.txt" % k[0]); open(f, "w").write("\n".join(lines) + "\n")
    h = tempfile.mkdtemp(dir=tmp)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
SRC = os.path.join(tmp, "a.dsn")
def sheet(n): return "<TinyCAD><NAME>S%d</NAME><DETAILS><Size width='1485' height='1050'/></DETAILS><WIRE a='%d,30' b='%d,30'/></TinyCAD>" % (n, 10 * n, 10 * n + 5)
open(SRC, "w").write("<?xml version='1.0'?>\n<TinyCADSheets>" + "".join(sheet(n) for n in range(1, 10)) + "</TinyCADSheets>\n")
OLD = ["S%d" % n for n in range(1, 10)]
def names(path):
    return [(t.findtext("NAME") or "") for t in ET.parse(path).getroot().iter("TinyCAD")] if os.path.exists(path) else None
def go(cmds):
    out = os.path.join(tmp, "o%d.dsn" % (k[0] + 1))
    o = run(["open " + SRC] + cmds + ["save " + out]); return o, names(out)
def cur(o):
    m = [re.search(r"current=(\d+)", l) for l in o if l.startswith("TABMENU")]; return int(m[-1].group(1)) if m else None
o, n = go(["tabmenu 2", "tabclick Insert_sheet", "tabmenu 3"])
check("sheet 3 clicked: the new sheet is the 4th, the old 4-9 are 5-10", n is not None and len(n) == 10 and n[:3] == OLD[:3] and n[4:] == OLD[3:] and n[3] not in OLD, n)
check("the new sheet is the one shown (4th)", cur(o) == 3, o[-5:])
o, n = go(["tabmenu 8", "tabclick Insert_sheet"])
check("last sheet clicked: the new one is last", n is not None and len(n) == 10 and n[:9] == OLD and n[9] not in OLD, n)
o, n = go(["tabmenu 0", "tabclick Insert_sheet"])
check("first sheet clicked: the new one is second", n is not None and len(n) == 10 and n[0] == "S1" and n[2:] == OLD[1:] and n[1] not in OLD, n)
o, n = go(["tabmenu 2", "tabclick Insert_sheet", "undo"])
check("one undo gives the old order back", n == OLD, n)
o, n = go(["tabmenu 2", "addsheet"])
check("Add Sheet (ribbon) still adds at the end", n is not None and len(n) == 10 and n[:9] == OLD, n)
print("insert sheet checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
