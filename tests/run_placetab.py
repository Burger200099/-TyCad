"""A shape or note drawn from the ribbon's Draw tab: once placed it is the selection and the select tool is back, so the Properties (View) tab comes forward, as it does
when the tool is chosen from the menu. Oracle: the ribbon tab showing (RIBBONSTATE tab=) after each placement. Needs xvfb-run and the built program."""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Placed-object tab checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
S = "newdoc A4\n"
for tool in ("note", "rect", "circle", "cloud"):
    S += f"ribbontab Draw\ntool {tool}\nmouse down 130 90\nmouse move 170 120\nmouse up 170 120\nribbonstate\n"
p = os.path.join(tmp, "s.txt"); open(p, "w").write(S)
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", p], capture_output=True, text=True, timeout=300,
                   env=dict(os.environ, HOME=tmp, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
st = [l for l in r.stdout.splitlines() if l.startswith("RIBBONSTATE")]
fails = 0
for tool, l in zip(("note", "rect", "circle", "cloud"), st):
    if "tab=View" not in l or "tool=0" not in l: fails += 1; print("  FAIL", tool, l)
if len(st) != 4: fails += 1; print("  FAIL states", st)
# a note chosen with the select tool from the Draw tab brings View forward, and clearing the selection returns to Draw
p2 = os.path.join(tmp, "s2.txt")
open(p2, "w").write("newdoc A4\ntool note\nmouse down 130 90\nmouse move 230 160\nmouse up 230 160\nmouse down 500 330\nmouse up 500 330\nribbontab Draw\nmouse down 180 120\nmouse up 180 120\nribbonstate\nmouse down 500 330\nmouse up 500 330\nribbonstate\n")
r2 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", p2], capture_output=True, text=True, timeout=300,
                    env=dict(os.environ, HOME=tmp, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
s2 = [l for l in r2.stdout.splitlines() if l.startswith("RIBBONSTATE")]
if len(s2) != 2 or "tab=View" not in s2[0] or "tab=Draw" not in s2[1]: fails += 1; print("  FAIL selecting a note and clearing the selection", s2)
print("Placed-object tab checks: 5 run, %d failed" % fails); sys.exit(1 if fails else 0)
