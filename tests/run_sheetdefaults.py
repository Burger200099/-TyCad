#!/usr/bin/env python3
"""Options > Sheets: what the sheet of a new design starts with (border, rulers, columns, rows, margin).
The real Options dialog is filled in by script (options sheetborder= sheetrulers= sheetcols= sheetrows= sheetmargin=) and OK'd; what the program then keeps and what a new design
holds is read from the saved design file (<SHOWS> bit 2 = rulers, <GUIDES horiz= vert=>, <BORDER margin=> in internal units, 5 per millimetre), restated here.
Cases:
  - a fresh program: border on, 6.35 mm, no rulers, 7 columns, 5 rows (what New Document always gave)
  - every value chosen reaches the next new design; the sheets already open keep theirs
  - the values are kept for the next start (same home folder); the border box off leaves no <BORDER> and the margin box is off then, the rulers box off disables columns and rows
  - what cannot be used is refused with a message and changes nothing: 0 or 27 columns, a row that is not a letter A-Z, a margin below 0 or above 100 mm
  - the New Document dialog starts with the border box and margin of Options
Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Sheet default checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:500])
def run(lines, home):
    h = os.path.join(tmp, "home_" + home); os.makedirs(h, exist_ok=True)
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    return subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=200, env=dict(os.environ, HOME=h)).stdout.splitlines()
cnt = [0]
def sheet(lines, home, pre=()):
    """runs the script, makes a new A4 design and saves it; returns (output, details of the saved sheet)"""
    cnt[0] += 1; f = os.path.join(tmp, "d%d.dsn" % cnt[0])
    o = run(list(pre) + lines + ["newdoc A4", "savedocas " + f], home)
    t = open(f, encoding="utf-8", errors="replace").read()
    shows = int(re.search(r"<SHOWS>(\d+)</SHOWS>", t).group(1)); g = re.search(r"<GUIDES horiz=.(\d+). vert=.(\d+).", t)
    b = re.search(r"<BORDER margin=.([\d.]+).", t)
    return o, dict(rulers=bool(shows & 2), cols=int(g.group(1)), rows=int(g.group(2)), border=b is not None, margin=float(b.group(1)) / 5 if b else None)
def ns(o):
    l = [x for x in o if x.startswith("OPTIONSINFO settings")]
    return re.search(r"newsheet=(\S+)", l[-1]).group(1) if l else None
# a fresh program
o, d = sheet([], "a")
check("fresh: border on at 6.35 mm, no rulers, 7 columns, 5 rows", d == dict(rulers=False, cols=7, rows=5, border=True, margin=6.35), d)
# every value chosen reaches the next new design
o, d = sheet(["options sheetborder=1 sheetrulers=1 sheetcols=12 sheetrows=H sheetmargin=12.5"], "b")
check("chosen values reach a new design (border 12.5 mm, rulers, 12 columns, rows A-H)", d == dict(rulers=True, cols=12, rows=8, border=True, margin=12.5), d)
o, d = sheet(["options sheetborder=0 sheetrulers=0 sheetcols=3 sheetrows=c"], "c")
check("border off leaves no border; rulers off is the sheet without rulers (counts are still kept: 3 columns, rows A-C)", d["border"] is False and d["rulers"] is False and d["cols"] == 3 and d["rows"] == 3, d)
# kept for the next start
o = run(["options sheetborder=1 sheetrulers=1 sheetcols=9 sheetrows=F sheetmargin=8", "optionsinfo"], "d")
o2, d = sheet(["optionsinfo"], "d")
check("kept for the next start: the saved settings show them and a new design takes them", ns(o2) == "11/9/6/8" and d == dict(rulers=True, cols=9, rows=6, border=True, margin=8.0), (ns(o2), d))
# sheets already open keep theirs
cnt[0] += 1; f = os.path.join(tmp, "d%d.dsn" % cnt[0])
o = run(["newdoc A4", "options sheetborder=0 sheetrulers=1 sheetcols=20 sheetrows=Z sheetmargin=30", "savedocas " + f], "e")
t = open(f, encoding="utf-8", errors="replace").read()
check("the sheet that is open keeps its own details", "<BORDER" in t and "horiz='7'" in t.replace('"', "'") and "vert='5'" in t.replace('"', "'"), t[:600])
# refused
for bad, why in [("sheetcols=0", "0 columns"), ("sheetcols=27", "27 columns"), ("sheetcols=x", "columns not a number"), ("sheetrows=1", "a row that is not a letter"), ("sheetrows=AB", "two letters"),
                 ("sheetrows=", "no row"), ("sheetmargin=-1", "negative margin"), ("sheetmargin=101", "margin over 100"), ("sheetmargin=abc", "margin not a number")]:
    o, d = sheet(["options " + bad], "f_" + str(cnt[0]))
    err = [l for l in o if l.startswith("OPTIONS err=")]
    check("refused: " + why, err and not err[0].startswith("OPTIONS err= ") and not err[0].startswith("OPTIONS err= grid") and d == dict(rulers=False, cols=7, rows=5, border=True, margin=6.35), (err, d))
print("sheet defaults: %d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
