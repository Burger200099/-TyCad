#!/usr/bin/env python3
"""Each sheet remembers its zoom and pan: leave a sheet zoomed in and panned, go to another sheet (fitted) and back: the zoom and pan come back; a sheet left
fitted is fitted again. Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Sheet view checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; checks = 0
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
sp = os.path.join(tmp, "s.txt")
open(sp, "w").write("\n".join(["newdoc A4", "addsheet", "gosheet 0", "zoom 2", "centeron 20 30", "viewpos", "gosheet 1", "viewpos", "zoom 1.5", "gosheet 0", "viewpos",
                               "gosheet 1", "viewpos", "zoomfit", "gosheet 0", "gosheet 1", "viewpos"]) + "\n")
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env)
v = [l for l in r.stdout.splitlines() if l.startswith("VIEWPOS")]
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok: fails.append(name); print("  FAIL", name, detail)
check("five readings", len(v) == 5, r.stdout[-600:])
if len(v) == 5:
    check("sheet 0 left zoomed, sheet 1 shown fitted", v[0] != v[1])
    check("sheet 0 comes back as it was left", v[2] == v[0], (v[0], v[2]))
    check("sheet 1 comes back as it was left (zoomed 1.5 times)", v[3] != v[1] and v[3].split()[1] != v[1].split()[1], (v[1], v[3]))
    check("a sheet left fitted is fitted again", v[4] == v[1], (v[1], v[4]))
print("Sheet view checks: %d, failed %d" % (checks, len(fails)))
