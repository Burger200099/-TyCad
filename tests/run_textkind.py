"""Every text object has the same kind whether it was placed with the Text tool or read from a file (before, a placed text had kind 0 and Select All Alike on it left the loaded ones
out, or the other way round). Oracle: OBJ ... kind= of the objects list, SELECTALIKE count. Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Text kind checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
f = os.path.join(tmp, "t.dsn")
mk = "newdoc A4\ngridmm 2\ntool text\nmouse down 100 60\nmouse up 100 60\nformshot /dev/null\n"
o = run("newdoc A4\ngridmm 2\ntool text\nmouse down 100 60\nmouse up 100 60\ntool select\nobjects\n")
k = [int(m.group(1)) for l in o for m in [re.search(r"TDrawText .*kind=(\d+)", l)] if m]
check("a text placed with the Text tool has kind 137 (xTextEx2)", k == [137], (k, o[-4:]))
o = run(f'newdoc A4\ngridmm 2\ntool text\nmouse down 100 60\nmouse up 100 60\ntool select\nsave "{f}"\nopen "{f}"\nobjects\n')
k2 = [int(m.group(1)) for l in o for m in [re.search(r"TDrawText .*kind=(\d+)", l)] if m]
check("the same text read back from the file has the same kind", k2 == [137], (k2, o[-4:]))
print("Text kind checks: %d run, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
