#!/usr/bin/env python3
"""A text box has the focus (the text of a selected text object, in the Properties panel); the sheet is panned with the middle button, or the right button in the Select tool:
when the pan has moved the sheet the box has the focus again (script 'focusinfo'); a right click that did not move anything leaves the focus where the click put it (the sheet).
Needs xvfb-run and the built program."""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Pan focus checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
S = ["newdoc A4", "registerframe x all", "addtext 40 40 Hello 3", "selclear", "selidx 0", "echo A", "focusinfo",
     "mouse mdown 100 100", "mouse move 120 110", "mouse mup 120 110", "echo B", "focusinfo",
     "mouse move 100 100", "mouse mdown 100 100", "mouse mup 100 100", "echo C", "focusinfo"]
sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(S) + "\n")
out = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=200).stdout.split("\n")
def focus(m):
    i = out.index(m); return [l for l in out[i + 1:] if l.startswith("FOCUS")][0]
bad = []
def check(n, ok, d=""):
    print(("ok   " if ok else "FAIL ") + n + ("" if ok else " " + str(d)))
    if not ok: bad.append(n)
check("the text box has the focus before the pan", "FOCUS edText" in focus("A"), focus("A"))
check("after a middle-button pan that moved the sheet the text box has the focus again", "FOCUS edText" in focus("B"), focus("B"))
check("a middle click that moved nothing leaves the focus on the sheet", "FOCUS edText" not in focus("C"), focus("C"))
print("pan focus: %d failed" % len(bad)); sys.exit(1 if bad else 0)
