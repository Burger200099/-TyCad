#!/usr/bin/env python3
"""The mouse wheel zooms about the pointer whatever the size of the window, and the zoom is shown in per cent (lbZoomPct on the position bar and the last status panel).
Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, re, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Zoom checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name); print("  FAIL", name, str(detail)[:600])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1920x1200x24", exe, "--script", sp], capture_output=True, text=True, timeout=200, env=env)
    return r.stdout.splitlines()
def pt(s): a, b = s.split(","); return (float(a), float(b))
def wheels(out): 
    res = []
    for l in out:
        if l.startswith("WHEEL "):
            d = dict(re.findall(r"(\w+)=(\[[^\]]*\]|\S+)", l)); res.append(d)
    return res
# a blank sheet; the window at the standard size, then larger; the pointer at several places; in and out
script = ["newdoc A4", "wheel 300 200 120 1000 700", "wheel 300 200 120", "wheel 700 400 -120", "wheel 50 60 120", "wheel 600 100 -120",
          "wheel 400 300 120 1500 900", "wheel 1200 700 120", "wheel 20 20 -120", "wheel 1000 500 120 1900 1100", "wheel 900 600 -120"]
out = run(script)
ws = wheels(out)
check("newdoc and the wheel commands ran", len(ws) == 10, out[:6])
prev = None
for k, d in enumerate(ws):
    b, a = pt(d["before"]), pt(d["after"])
    check("wheel %d: the point of the sheet under the pointer stays under it" % k, abs(b[0] - a[0]) < 0.01 and abs(b[1] - a[1]) < 0.01, d)
    check("wheel %d: the label and the status panel show the zoom in per cent" % k, d["label"] == "[%s%%]" % d["zoom"] and d["panel"] == "[%s%%]" % d["zoom"], d)
    check("wheel %d: the drawing area is not at the top of the screen (so converting twice would have been wrong)" % k, int(d["top"]) > 0, d)
    if prev is not None:
        z0, z1 = int(prev["zoom"]), int(d["zoom"])
check("zooming in raises and zooming out lowers the percentage", int(ws[0]["zoom"]) > 0 and int(ws[1]["zoom"]) > int(ws[0]["zoom"]) and int(ws[2]["zoom"]) < int(ws[1]["zoom"]) and int(ws[3]["zoom"]) > int(ws[2]["zoom"]), [d["zoom"] for d in ws])
ratio = int(ws[1]["zoom"]) / int(ws[0]["zoom"])
check("one notch is a factor of 1.2", abs(ratio - 1.2) < 0.03, ratio)
d = ws[0]
w = [int(x) for x in d["widths"].split(",")]; fw = int(d["formwidth"])
check("the five status panels have 20, 20, 8, 50 and 2 per cent of the window width", d["panels"] == "5" and all(abs(w[i] - round(fw * p / 100)) <= 1 for i, p in enumerate((20, 20, 8, 50, 2))), (w, fw))
zl = [int(x) for x in d["zoomlabel"].split(",")]; pl = [int(x) for x in d["poslabel"].split(",")]
sc = zl[2] / 40.0   # the form is scaled to the screen's resolution; the design values are 5, 7, 40 and 50, 210
check("lbZoomPct (5, 7, 40) and lblPosition (50, 210) keep their design proportions beside each other", abs(zl[0] - 5 * sc) <= 1 and abs(zl[1] - 7 * sc) <= 1 and abs(pl[0] - 50 * sc) <= 1 and abs(pl[1] - 210 * sc) <= 2 and zl[0] + zl[2] <= pl[0], (zl, pl))
# the position bar clears the status panel when shown
out = run(["newdoc A4", "positionshow 0", "positioninfo", "positionshow 1", "positioninfo"])
pi = [l for l in out if l.startswith("POSITION")]
check("showing the position bar empties the status panel that held the position", len(pi) >= 2 and "status=[]" in pi[-1], pi)
shutil.rmtree(tmp, ignore_errors=True)
print("zoom wheel: %d checks, %d failed" % (checks, len(fails)))
if fails: sys.exit(1)
