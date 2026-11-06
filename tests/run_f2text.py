"""F2 with a text, wire label or note chosen and the sheet holding the focus: the focus goes to the text box on the ribbon (the View tab comes forward) with the text selected; with nothing
chosen, or a symbol, the key is left alone. Oracle: FORMKEY (the key as the form gets it: handled, and the control with the focus and its selected text). Needs xvfb-run and the built program."""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("F2 checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
p = os.path.join(tmp, "s.txt")
open(p, "w").write("""newdoc A4
tool note
mouse down 130 90
mouse move 230 160
mouse up 230 160
frameact sel prop:text text hello note
mouse down 600 400
mouse up 600 400
formkey f2 onsheet
ribbontab Draw
mouse down 180 120
mouse up 180 120
ribbontab Draw
formkey f2 onsheet
ribbonstate
mouse down 600 400
mouse up 600 400
formkey f2 onsheet
""")
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", p], capture_output=True, text=True, timeout=300,
                   env=dict(os.environ, HOME=tmp, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
o = r.stdout.splitlines(); fk = [l for l in o if l.startswith("FORMKEY")]; rs = [l for l in o if l.startswith("RIBBONSTATE")]
fails = 0
def check(name, ok, d=""):
    global fails
    if not ok: fails += 1; print("  FAIL", name, d)
check("nothing chosen: F2 is not taken", len(fk) == 3 and "handled=0" in fk[0], fk)
check("a note chosen: F2 is taken and the text box has the focus with the text selected", len(fk) == 3 and "handled=1" in fk[1] and "active=TMemo" in fk[1] and "sel=[hello note]" in fk[1], fk)
check("the View tab came forward", rs and "tab=View" in rs[-1], rs)
check("nothing chosen again: not taken", len(fk) == 3 and "handled=0" in fk[2], fk)
print("F2 checks: 4 run, %d failed" % fails); sys.exit(1 if fails else 0)
