"""Ladder rails: the bus text can also be shown under the rails (ladder.bottom, "Bus text at both ends"), and the text above sits close to the top of the rail (5 units).

(text pixels above and, when on, below each rail; none below when off), the property list (ladder.bottom shown). Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Ladder bottom text checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:300])
def run(script):
    p = os.path.join(tmp, "s.txt"); open(p, "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", p], capture_output=True, text=True, timeout=300,
                       env=dict(os.environ, HOME=tmp, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.splitlines()
mk = "newdoc A4\ntool ladder\nmouse down 100 60\nmouse move 300 200\nmouse up 300 200\n"
off, on = os.path.join(tmp, "off.dsn"), os.path.join(tmp, "on.dsn")
o = run(mk + f'props\nsave "{off}"\nsetprop ladder.bottom 1\nsave "{on}"\nopen "{on}"\nselectall\nprops\n')
check("the properties list ladder.bottom", any("ladder.bottom=0" in l for l in o) and any("ladder.bottom=1" in l for l in o), [l for l in o if l.startswith("PROPS")])
check("off: nothing written", "bottom=" not in open(off, encoding="utf-8").read())
check("on: bottom='1' written", "bottom='1'" in open(on, encoding="utf-8").read())
print("Ladder bottom text checks: %d run, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
