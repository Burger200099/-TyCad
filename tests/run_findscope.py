#!/usr/bin/env python3
"""Find and Replace: "Search entire file" and "Prompt on replace" of the dialog, on the real program under Xvfb (the dialog's own handlers are called).
Oracle: the design is written here with labels on three sheets; the texts after each command are read from the saved file (XML) and compared with plain string work.
  - Replace All with Search entire file on changes the labels of every sheet of the document; off, only the sheet shown
  - Replace All with Prompt on replace: the answers y, n, y change the first and third occurrence and leave the second; c stops
  - with both: the questions follow the scope, one for each occurrence in it
  - each replacement of a prompted Replace All is one undo step
  - Find Next with the box off stays on the sheet shown and wraps in it
Needs the built program and xvfb."""
import os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Find scope checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
def sheet(labels):
    s = "".join("<LABEL pos='%d,%d' direction='0' font='1' color='0' style='0'>%s</LABEL>" % (100 + 40 * i, 100, t) for i, t in enumerate(labels))
    return "<TinyCAD><NAME>s</NAME><DETAILS><Size width='1485' height='1050'/></DETAILS>%s</TinyCAD>" % s
SHEETS = [["foo", "bar foo"], ["foo x"], ["a foo", "foo foo"]]       # 6 occurrences of foo: 2 on the first sheet, 1 on the second, 3 on the third
SRC = os.path.join(tmp, "a.dsn")
open(SRC, "w").write('<?xml version="1.0"?>\n<TinyCADSheets>' + "".join(sheet(s) for s in SHEETS) + "</TinyCADSheets>\n")
def texts(path):
    r = ET.parse(path).getroot(); return [[(l.text or "") for l in t.iter("LABEL")] for t in r.iter("TinyCAD")]
def go(cmds, tail=()):
    out = os.path.join(tmp, "o%d.dsn" % (k[0] + 1))
    o = run(["open " + SRC] + list(cmds) + ["save " + out])
    return o, (texts(out) if os.path.exists(out) else None)
def sub(sheets_changed, answers=None):
    """the expected texts: foo -> BAR on the sheets given (in order, all occurrences, or only those answered y)"""
    res = [list(s) for s in SHEETS]; n = 0
    for si in sheets_changed:
        for li, t in enumerate(res[si]):
            parts = t.split("foo"); out = parts[0]
            for p in parts[1:]:
                ok = True if answers is None else (n < len(answers) and answers[n] == "y"); n += 1
                out += ("BAR" if ok else "foo") + p
            res[si][li] = out
    return res
o, t = go(["replace foo BAR all"])
check("entire file on: every sheet", t == sub([0, 1, 2]), t)
o, t = go(["replace foo BAR all sheet"])
check("entire file off: only the sheet shown (the first)", t == sub([0]), t)
o, t = go(["replace foo BAR all prompt:yny"])
check("prompt y n y: first and third changed, second left, then the box asks again (script has no more answers: cancel)", t == sub([0, 1, 2], "yny"), t)
o, t = go(["replace foo BAR all prompt:yyyyyy"])
check("prompt yes to all six: the same as without a prompt", t == sub([0, 1, 2]), t)
o, t = go(["replace foo BAR all prompt:nnnnnn"])
check("prompt no to all: nothing changed", t == SHEETS, t)
o, t = go(["replace foo BAR all prompt:yc"])
check("prompt y then cancel: only the first occurrence changed", t == sub([0, 1, 2], "y"), t)
o, t = go(["replace foo BAR all sheet prompt:yyyyyy"])
check("prompt with entire file off: only the three occurrences of the first sheet are asked and changed", t == sub([0]), t)
# undo of a prompted replacement is one step each
out = os.path.join(tmp, "u.dsn")
run(["open " + SRC, "replace foo BAR all prompt:yyyyyy", "undo", "save " + out])
check("one undo takes back one replacement only (5 of 6 remain)", sum(t.count("BAR") for s in texts(out) for t in s) == 5, texts(out))
# find next stays on the sheet
o = run(["open " + SRC, "find foo sheet", "findnext", "findnext", "findnext"])
infos = [l for l in o if l.startswith("FIND") ]
check("find with the box off: never leaves the sheet shown (2 hits there, the 3rd call wraps)", len(infos) == 4 and all("sheet=0 " in l for l in infos) and "wrapped=1" in infos[2], infos)
print("find scope checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
