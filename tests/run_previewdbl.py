#!/usr/bin/env python3
"""A double click on the preview pane of the library panel starts placing the chosen symbol, as a double click on the tree does.
Oracle: the tool before (select) and after (place); a plain symbol row of the example library gen_passive.TCLib; a mutation (the event not hooked) leaves the tool on select."""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "/tmp/orig/TinyCAD-master/examples")
lib = os.path.join(EX, "libraries", "gen_passive.TCLib")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not os.path.exists(lib):
    print("Preview double click checks skipped: need xvfb-run, the built program and the example libraries"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:300])
s = "newdoc A4\nlib %s\nlibselect 0\nlibtree\npreviewdbl 0\n" % lib
h = os.path.join(tmp, "h"); os.makedirs(h); open(os.path.join(tmp, "s.txt"), "w").write(s)
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s.txt")], capture_output=True, text=True, timeout=90,
                   env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
pd = [l for l in r.stdout.split("\n") if l.startswith("PREVIEWDBL")]
check("a double click on the preview pane starts placing the symbol", pd and "placing=1" in pd[0], r.stdout[-600:])
print("Preview double click checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
