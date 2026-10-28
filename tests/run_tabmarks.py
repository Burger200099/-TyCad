#!/usr/bin/env python3
"""The sheet tab of the sheet the view is on has an arrow (picture 0 of frmSharedControls.ilSheetTabs), every other tab and the + tab none (-1, so only the current tab is wider). The tabs are made again after a change of sheet because the system tab control asks for a tab's picture only when it makes the tab.
Oracle: the sheet the view is on (current=) and the number of tabs, worked out here; the picture number each tab asks for. What the tab control draws is not checked."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Tab marker checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:300])
s = "newdoc A4\naddsheet\naddsheet\naddsheet\ntabmarks\ngosheet 0\ntabmarks\ngosheet 2\ntabmarks\nremovesheet\ntabmarks\n"
h = os.path.join(tmp, "h"); os.makedirs(h); open(os.path.join(tmp, "s.txt"), "w").write(s)
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s.txt")], capture_output=True, text=True, timeout=90,
                   env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
tm = [l for l in r.stdout.split("\n") if l.startswith("TABMARKS")]
try:
    for l in tm:
        marks = [int(x) for x in re.search(r"marks=([-\d,]+)", l).group(1).split(",") if x]; cur = int(re.search(r"current=(\d+)", l).group(1))
        n = len(marks) - 1
        want = [0 if i == cur else -1 for i in range(n)] + [-1]
        check("sheet %d of %d: the tab asks for the arrow (0), every other tab and the + tab for none (-1)" % (cur, n), marks == want, (l, want))
    check("at least the arrow picture of 14 x 14 pixels, linked to the tabs", all(int(re.search(r"images=(\d+)", l).group(1)) >= 1 and "size=14x14" in l and "linked=1" in l for l in tm), tm)
    check("four readings", len(tm) == 4, tm)
except Exception as e:
    check("the script ran", False, repr(e) + "\n".join(r.stdout.split("\n")[-8:]))
print("Tab marker checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
