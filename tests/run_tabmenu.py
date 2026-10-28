#!/usr/bin/env python3
"""The sheet tabs' right-click menu (pmSheetTabs, made at design time): the items and their order as in TinyCAD, every item wired to its command, the tab control uses it,
a right click on a tab makes that sheet current first, Enabled follows the position of the sheet, and the commands act on the sheet clicked.
Oracles: the SHEETS report (names and order) and the item states, worked out here from the number of sheets and the clicked position."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Tab menu checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:400])
s = """newdoc A4
renamesheet Alpha
addsheet
renamesheet Beta
addsheet
renamesheet Gamma
sheetinfo
tabmenu 0
tabmenu 1
tabmenu 2
tabmenu 1
tabclick Move_Sheet_right_->
sheetinfo
tabmenu 0
tabclick <-_Move_Sheet_left
tabclick Insert_sheet
sheetinfo
tabmenu 1
echo HIER
sheetinfo
"""
h = os.path.join(tmp, "h"); os.makedirs(h); open(os.path.join(tmp, "s.txt"), "w").write(s)
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s.txt")], capture_output=True, text=True, timeout=60,
                   env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
o = r.stdout.split("\n")
def items(l): return [x.rsplit(":", 1) for x in re.search(r"items=(.*?) wired", l).group(1).split("|") if x]
try:
    tm = [l for l in o if l.startswith("TABMENU")]; sh = [l for l in o if l.startswith("SHEETS")]
    caps = [c for c, e in items(tm[0])]
    check("the items and their order", caps == ["Insert sheet", "Delete sheet", "Rename sheet...", "-", "<- Move Sheet left", "Move Sheet right ->", "-", "Add hierarchical symbol"], caps)
    check("every item is wired to its command and the tabs use the menu", all(" wired=111111 popup=1" in l for l in tm), tm[0])
    st = lambda l: [e for c, e in items(l)]
    check("first of three sheets: no Move left, Move right on", st(tm[0])[4:6] == ["0", "1"] and st(tm[0])[1] == "1", tm[0])
    check("middle sheet: both moves on", st(tm[1])[4:6] == ["1", "1"], tm[1])
    check("last sheet: Move right off, Move left on", st(tm[2])[4:6] == ["1", "0"], tm[2])
    check("a right click on a tab makes that sheet current", [re.search(r"current=(\d)", l).group(1) for l in tm[:4]] == ["0", "1", "2", "1"], tm[:4])
    check("start order is Alpha, Beta, Gamma", "names=Alpha:0,Beta:0,Gamma:0," in sh[0], sh[0])
    check("Move Sheet right on the middle sheet gives Alpha, Gamma, Beta", "names=Alpha:0,Gamma:0,Beta:0," in sh[1], sh[1])
    check("Move left is off on the first sheet (so does nothing) and Insert sheet adds a fourth", "SHEETS 4" in sh[2], sh[2])
    check("Add hierarchical symbol is on for a design without one (its dialog is not run here)", st(tm[0])[7] == "1", tm[0])
except Exception as e:
    check("the script ran", False, repr(e) + "\n".join(o[-10:]))
print("Tab menu checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
