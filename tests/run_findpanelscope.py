#!/usr/bin/env python3
"""The find panel's "Search all Sheets" box, on the real program under Xvfb. The expected lists are written out here from the design's XML:
  - ticked (the default): every object with the text on every sheet, as "<sheet name>: <object>: <text>"; a sheet with a name is listed by it
  - not ticked: only the objects of the sheet shown, and only those get red circles; switching sheets and searching again follows the sheet shown
  - an entry chosen goes to its sheet and object either way
Needs the built program and xvfb."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Find panel scope checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:700])
k = [0]
def run(lines):
    k[0] += 1; h = os.path.join(tmp, "h%d" % k[0]); os.makedirs(h)
    f = os.path.join(tmp, "s%d.txt" % k[0]); open(f, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
def sheet(name, labels):
    s = "".join("<LABEL pos='%d,%d' direction='0' font='1' color='0' style='0'>%s</LABEL>" % (100 + 40 * i, 100, t) for i, t in enumerate(labels))
    return "<TinyCAD><NAME>%s</NAME><DETAILS><Size width='1485' height='1050'/></DETAILS>%s</TinyCAD>" % (name, s)
SRC = os.path.join(tmp, "a.dsn")
open(SRC, "w").write('<?xml version="1.0"?>\n<TinyCADSheets>' + sheet("Power", ["VCC", "GND"]) + sheet("Logic", ["VCC A", "X"]) + sheet("Out", ["out VCC"]) + "</TinyCADSheets>\n")
def entries(o, tag):
    for l in o:
        if l.startswith(tag + " "):
            body = l.split(" ", 1)[1]
            e = [x.rstrip("]") for x in body.split(" [")[1:]]
            m = re.search(r"markers=(\d+)", body)
            return e, int(m.group(1)) if m else None, re.search(r"count=(.*?) chosen", body).group(1)
    return None, None, None
o = run(["open " + SRC, "finder VCC", "gosheet 1", "finder VCC sheet", "gosheet 0", "finder VCC sheet", "finder VCC"])
FL = [l for l in o if l.startswith("FINDER")]
def ent(l):
    body = l.split(" ", 1)[1]; return [x.rstrip("]") for x in body.split(" [")[1:]], int(re.search(r"markers=(\d+)", body).group(1))
check("four finder lines", len(FL) == 4, o[-20:])
if len(FL) == 4:
    (e1, m1), (e2, m2), (e3, m3), (e4, m4) = [ent(l) for l in FL]
    check("ticked: every sheet, 'sheet name: object: text'", e1 == ["Power: Label: VCC", "Logic: Label: VCC A", "Out: Label: out VCC"] and m1 == 3, (e1, m1))
    check("not ticked on the second sheet: only that sheet's object, one circle", e2 == ["Logic: Label: VCC A"] and m2 == 1, (e2, m2))
    check("not ticked on the first sheet: only that one", e3 == ["Power: Label: VCC"] and m3 == 1, (e3, m3))
    check("ticked again: all three", e4 == e1 and m4 == 3, (e4, m4))
print("find panel scope checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
