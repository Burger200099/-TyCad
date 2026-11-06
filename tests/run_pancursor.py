#!/usr/bin/env python3
"""The pointer after a middle-button pan goes back to the one the tool had: the cross for the wire and line tools, the arrow for select. While panning it is the
four arrows. Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Pan cursor checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "h"); os.makedirs(home)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, d)
sp = os.path.join(tmp, "s.txt")
open(sp, "w").write("\n".join(["newdoc A4", "tool wire", "cursor", "mouse mdown 100 100", "cursor", "mouse mup 100 100", "cursor",
                               "tool select", "mouse mdown 100 100", "mouse mup 100 100", "cursor", "tool line", "mouse mdown 100 100", "mouse mup 100 100", "cursor"]) + "\n")
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=250,
                   env=dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
c = [l.split(None, 1)[1] for l in r.stdout.splitlines() if l.startswith("CURSOR")]
check("five readings", len(c) == 5, c)
if len(c) == 5:
    check("wire tool: the cross before the pan", c[0] == "-3", c)
    check("wire tool: the four arrows while panning", c[1] == "ALL", c)
    check("wire tool: the cross again after the pan", c[2] == c[0], c)
    check("select tool: the arrow after the pan", c[3] == "default", c)
    check("line tool: the cross after the pan", c[4] == c[0], c)
print("Pan cursor checks: %d, failed %d" % (checks, len(fails)))
