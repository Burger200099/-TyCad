#!/usr/bin/env python3
"""The Pin tool's property panel (before the pin is put down): while the Pin tool is active in the symbol editor the pin frame is shown with the values the next pin will have,
and what is typed in it is what the next pin gets, then counting goes on from that pin. Oracle: the pin's own properties read back from the placed pin (props), the counting
rule checked against a control run that is not touched in the panel (the same code counts it) and the values typed. Needs xvfb-run, the built program and TC_EXAMPLES."""
import os, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
LIB = os.path.join(EX, "libraries", "gen_passive.TCLib")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not os.path.exists(LIB):
    print("Pin tool checks skipped: need xvfb-run, the built program and the example libraries"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:500])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
lib = os.path.join(tmp, "g.TCLib"); shutil.copy(LIB, lib)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    return subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=200, env=env).stdout.splitlines()
def put(y): return ["mouse move 60 %d" % y, "mouse down 60 %d" % y, "mouse up 60 %d" % y]
def pins(o):
    res = []
    for l in o:
        if l.startswith("PROPS "): res.append(dict(kv.split("=", 1) for kv in l[6:].split("; ") if "=" in kv))
    return res
def shown(o, nth, ctrl):
    """the text shown in the control of the nth FRAMEINFO TfmPin listing"""
    blocks = [i for i, l in enumerate(o) if l.startswith("FRAMEINFO TfmPin")]
    for l in o[blocks[nth]:blocks[nth] + 12]:
        if l.startswith("FRAMEINFO " + ctrl + " "): return l.split("shown=[", 1)[1].rstrip("]")
read = lambda k: ["tool select", "selclear", "selidx %d" % k, "props", "tool pin"]
head = ["newdoc A4", "registerframe x all", "lib " + lib, "sym new=0", "tool pin"]
# control: two pins, nothing typed
c = run(head + put(60) + put(80) + read(0) + read(1))
cp = pins(c)
check("control: two pins placed with nothing typed (the second counts on from the first)", len(cp) == 2 and cp[0]["pin.number"] == "1" and cp[1]["pin.number"] != cp[0]["pin.number"], cp)
# typed in the panel before the first pin, and before the second
o = run(head + ["frameinfo tool", "frameact tool edPinName text CLK", "frameact tool edPinNumber text 7", "frameact tool sePinLength text 40", "frameact tool cbPinShape choose 2"] + put(60)
        + ["frameinfo tool", "frameact tool edPinName text DATA"] + put(80) + put(100) + read(0) + read(1) + read(2))
p = pins(o)
check("the pin frame is shown while the Pin tool is active, before anything is placed", any(l.startswith("FRAMEINFO TfmPin") and "problems=0" in l for l in o), [l for l in o if l.startswith("FRAMEINFO")][:2])
check("first pin: the name, number, length and shape typed in the panel", len(p) == 3 and (p[0]["pin.name"], p[0]["pin.number"], p[0]["pin.length"], p[0]["pin.shape"]) == ("CLK", "7", "40", "Clock"), p)
check("the panel shows the next pin: the length stays 40 and the number has counted on from 7 to 8", (shown(o, 1, "sePinLength"), shown(o, 1, "edPinNumber")) == ("40", "8"), (shown(o, 1, "sePinLength"), shown(o, 1, "edPinNumber")))
check("second pin: the name typed before it, the length and shape kept from the first, number counted on", (p[1]["pin.name"], p[1]["pin.length"], p[1]["pin.shape"], p[1]["pin.number"]) == ("DATA", "40", "Clock", "8"), p[1])
check("third pin: counts on from the second (a typed value is used once): number 9, name counted on from DATA", (p[2]["pin.number"], p[2]["pin.name"]) == ("9", "DATB"), p[2])
# not in a symbol: no pin tool panel
q = run(["newdoc A4", "registerframe x all", "tool pin", "frameinfo tool"])
check("on a sheet (pins cannot be placed): no pin panel", not any(l.startswith("FRAMEINFO TfmPin") for l in q), [l for l in q if l.startswith("FRAMEINFO")][:2])
print("%d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
