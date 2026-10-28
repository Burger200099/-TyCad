#!/usr/bin/env python3
"""The New Document dialog starts on the paper size and orientation chosen last time (kept in the program's settings), ISO A4 landscape the first time;
a cancelled dialog and a script's new document change nothing. Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, re, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("New document checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name); print("  FAIL", name, str(detail)[:500])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=200, env=env)
    return [l for l in r.stdout.splitlines() if l.startswith("NEWDOCDIALOG")]
def last(o): return o[-1] if o else ""
o = run(["newdocdialog"])
check("the first time the dialog starts on ISO A4, landscape, with the 6.35 mm border margin", last(o) == "NEWDOCDIALOG paper=ISO A4 landscape=1 margin=6.35", o)
o = run(["newdocdialog pick=ISO_A3 orient=portrait"])
check("choosing in the dialog shows the choice", last(o) == "NEWDOCDIALOG paper=ISO A3 landscape=0 margin=6.35", o)
o = run(["newdocdialog"])
check("a dialog that was cancelled (not accepted) remembers nothing", last(o).startswith("NEWDOCDIALOG paper=ISO A4 landscape=1"), o)
o = run(["newdocdialog pick=ISO_A3 orient=portrait ok=1"])
check("accepting reports what is remembered", "remembered paper=ISO A3 landscape=0" in "".join(o), o)
o = run(["newdocdialog"])
check("the next run of the program starts the dialog on ISO A3 portrait", last(o).startswith("NEWDOCDIALOG paper=ISO A3 landscape=0"), o)
o = run(["newdoc ISO_A0", "newdocdialog"])
check("a script's new document does not change what is remembered", last(o).startswith("NEWDOCDIALOG paper=ISO A3 landscape=0"), o)
o = run(["newdocdialog pick=ANSI_B_(Tabloid) orient=landscape ok=1", "newdocdialog"])
check("another choice replaces it at once", last(o) == "NEWDOCDIALOG paper=ANSI B (Tabloid) landscape=1 margin=6.35", o)
o = run(["newdocdialog"])
check("... and is what the next run shows", last(o).startswith("NEWDOCDIALOG paper=ANSI B (Tabloid) landscape=1"), o)
shutil.rmtree(tmp, ignore_errors=True)
print("new document: %d checks, %d failed" % (checks, len(fails)))
if fails: sys.exit(1)
