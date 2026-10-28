#!/usr/bin/env python3
"""The symbol parameter list remembers a resize for the rest of the session. The Properties panel (and the list it owns) is rebuilt for each selection, so a new list must open at the size
the last one was left at. Oracle: the sizes asked for (script 'symlist sel size <w> <h>' sets the size as the grip does, never below the minimum / past the screen).
Checks: first opening is the default size; after resizing to 480x330, closing, clearing the selection and selecting again (a new list) it opens at 480x330; resized again to 420x260 it
opens there next time; a minimum-size request is remembered as the minimum. Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("List size checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
S = ["newdoc A4", "registerframe x all", "tool symboltext", "frameinfo tool", "clickmm 80 40", "tool select", "frameinfo sel",
     "symlist sel open", "echo S0", "symlist sel size", "symlist sel size 480 330", "symlist sel close",
     "selclear", "selidx 0", "frameinfo sel", "symlist sel open", "echo S1", "symlist sel size", "symlist sel size 420 260", "symlist sel close",
     "selclear", "selidx 0", "frameinfo sel", "symlist sel open", "echo S2", "symlist sel size", "symlist sel size 100 100", "symlist sel close",
     "selclear", "selidx 0", "frameinfo sel", "symlist sel open", "echo S3", "symlist sel size"]
sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(S) + "\n")
out = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=200, env=dict(os.environ, HOME=tempfile.mkdtemp(dir=tmp))).stdout.split("\n")
def size_after(mark):
    i = out.index(mark); l = [x for x in out[i + 1:] if x.startswith("SYMLIST size")][0]
    return tuple(int(v) for v in re.match(r"SYMLIST size (\d+)x(\d+)", l).groups())
fails = []
def check(n, ok, d=""):
    print(("ok   " if ok else "FAIL ") + n + ("" if ok else " " + str(d)))
    if not ok: fails.append(n)
d0 = size_after("S0"); check("the first list opens at its own size (not 480x330)", d0 != (480, 330), d0)
d1 = size_after("S1"); check("after resizing to 480x330 a new list (new selection) opens at 480x330", d1 == (480, 330), d1)
d2 = size_after("S2"); check("after resizing to 420x260 the next list opens at 420x260", d2 == (420, 260), d2)
d3 = size_after("S3"); check("a request below the minimum is remembered as the minimum it was held to", d3[0] >= 300 and d3[1] >= 220 and d3[0] < 420, d3)
print("list size: %d failed" % len(fails)); sys.exit(1 if fails else 0)
