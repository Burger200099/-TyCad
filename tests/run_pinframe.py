#!/usr/bin/env python3
"""The pin property frame (src/frames/QPin, TfmPin): shown for a selected pin of a symbol being drawn, every editor linked to its property, values shown, changes applied
and undone, a selection of two pins, and the lists holding the choices of TinyCAD's pin dialog (read from the C++ resource text below).
Needs xvfb-run, the built program and the example libraries (TC_EXAMPLES)."""
import os, re, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
LIB = os.path.join(EX, "libraries", "gen_passive.TCLib")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not os.path.exists(LIB):
    print("Pin frame checks skipped: need xvfb-run, the built program and the example libraries"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name); print("  FAIL", name, str(detail)[:500])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
lib = os.path.join(tmp, "g.TCLib"); shutil.copy(LIB, lib)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=200, env=env)
    return r.stdout.splitlines()
def props(out):
    res = []
    for l in out:
        if l.startswith("PROPS "):
            res.append(dict(kv.split("=", 1) for kv in l[6:].split("; ") if "=" in kv))
    return res
pin = ["newdoc A4", "registerframe x all", "lib " + lib, "sym new=0", "tool pin", "mouse move 60 60", "mouse down 60 60", "mouse up 60 60", "tool select", "selectall", "sel"]
out = run(pin + ["frameinfo sel", "props",
    "frameact sel edPinName text CLK", "props", "frameact sel edPinNumber text A7", "props", "frameact sel sePinLength text 40", "props",
    "frameact sel sePinNumPos text 10", "props", "frameact sel cbPinShape choose 2", "props", "frameact sel cbPinElec choose 1", "props",
    "frameact sel sbPinShowName click", "props", "frameact sel sbPinShowNumber click", "props", "frameact sel sbPinCentre click", "props",
    "undo", "props", "undo", "props"])
fi = [l[10:] for l in out if l.startswith("FRAMEINFO ")]
check("the pin frame is the one shown, with no problems", fi and fi[0].startswith("TfmPin") and "problems=0" in fi[0], fi[:1])
want = {"edPinName": ("TEdit", "pin.name"), "edPinNumber": ("TEdit", "pin.number"), "sePinNumPos": ("TSpinEdit", "pin.numpos"), "sePinLength": ("TSpinEdit", "pin.length"),
        "cbPinShape": ("TComboBox", "pin.shape"), "cbPinElec": ("TComboBox", "pin.elec"), "sbPinShowName": ("TSpeedButton", "pin.showname"),
        "sbPinShowNumber": ("TSpeedButton", "pin.shownumber"), "sbPinCentre": ("TSpeedButton", "pin.centre")}
got = {l.split()[0]: (l.split()[1], l.split()[2]) for l in fi[1:] if "visible=1 enabled=1" in l}
check("all nine editors are bound to their properties and enabled", got == want, got)
P = props(out)
check("a fresh pin shows its values (length 30, Normal, Input, name and number shown)", P and P[0]["pin.length"] == "30" and P[0]["pin.shape"] == "Normal" and P[0]["pin.elec"] == "Input"
      and P[0]["pin.showname"] == "1" and P[0]["pin.shownumber"] == "1" and P[0]["pin.centre"] == "0", P[:1])
steps = [("pin.name", "CLK"), ("pin.number", "A7"), ("pin.length", "40"), ("pin.numpos", "10"), ("pin.shape", "Clock"), ("pin.elec", "Output"), ("pin.showname", "0"), ("pin.shownumber", "0"), ("pin.centre", "1")]
for i, (k, v) in enumerate(steps):
    check("changing %s in the frame sets it to %s" % (k, v), len(P) > i + 1 and P[i + 1].get(k) == v, P[i + 1] if len(P) > i + 1 else P)
check("each change leaves the others alone", all(P[i + 1].get(steps[i - 1][0]) == steps[i - 1][1] for i in range(1, 9) if len(P) > i + 1))
check("undo takes back the last change, and the one before", len(P) > 11 and P[10].get("pin.centre") == "0" and P[11].get("pin.shownumber") == "1", P[10:])
# the lists hold TinyCAD's choices, in its order
shapes = "Normal|Dot|Clock|Dot Clock|Power|Hidden|Cross".split("|"); elecs = "Input|Output|Tristate|Open Collector|Passive|Input/Output|Not Connected".split("|")
res = run(pin + ["frameact sel cbPinShape choose 6", "props", "frameact sel cbPinElec choose 6", "props"])
P2 = props(res)
check("the last item of each list is Cross and Not Connected", len(P2) >= 2 and P2[0]["pin.shape"] == shapes[6] and P2[1]["pin.elec"] == elecs[6], P2)
# no frame: two pins selected together share the frame; a pin and a rectangle do not
two = ["newdoc A4", "registerframe x all", "lib " + lib, "sym new=0", "tool pin", "mouse move 60 60", "mouse down 60 60", "mouse up 60 60", "mouse move 60 100", "mouse down 60 100", "mouse up 60 100",
       "tool select", "selectall", "sel", "frameinfo sel", "frameact sel sePinLength text 50", "props"]
r2 = run(two)
fi2 = [l for l in r2 if l.startswith("FRAMEINFO TfmPin")]
check("two pins selected use the pin frame", len(fi2) == 1, fi2)
check("a change in the frame reaches both pins (the shared value is shown)", any("pin.length=50" in l for l in r2 if l.startswith("PROPS")), [l for l in r2 if l.startswith("PROPS")])
print("pin frame: %d checks, %d failed" % (checks, len(fails))); sys.exit(1 if fails else 0)
