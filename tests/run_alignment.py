#!/usr/bin/env python3
"""The Alignment panel (the old Position panel: Show Bar, Show Rulers, 1 px grid) and Z-Order > Align to Grid of the symbol editor.
Oracles: the nearest grid dot is worked out here (floor(v / grid + 0.5) * grid) for each point drawn off the grid; the shape is unchanged when b - a is the same before
and after; the panel's places are read from mainform.lfm.
Needs xvfb-run, the built program and the example libraries (TC_EXAMPLES)."""
import os, re, sys, math, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
LIB = os.path.join(EX, "libraries", "gen_passive.TCLib")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not os.path.exists(LIB):
    print("Alignment checks skipped: need xvfb-run, the built program and the example libraries"); sys.exit(0)
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
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env)
    return r.stdout.splitlines()
def after(out, mk, key):
    i = out.index(mk); r = []
    for l in out[i + 1:]:
        if l.startswith(key + " end"): break
        if l.startswith(key): r.append(l)
    return r
def pts(out, mk):
    res = []
    for l in after(out, mk, "SELPT"):
        m = re.match(r"SELPT \d+ (\w+) a=([-\d.]+),([-\d.]+) b=([-\d.]+),([-\d.]+)", l)
        if m: res.append((m.group(1), (float(m.group(2)), float(m.group(3))), (float(m.group(4)), float(m.group(5)))))
    return res
def near(g, v): return math.floor(v / g + 0.5) * g
# --- the panel as designed: one split button whose pop-up menu holds Show Rulers and 1 px grid, in that order (read from mainform.lfm)
lfm = open(os.path.join(HERE, "..", "src", "forms", "mainform.lfm")).read()
i = lfm.index("object pmAlignmentOptions: TPopupMenu"); seg = lfm[i:i + 900]
names = re.findall(r"object (\w+): TMenuItem", seg)[:3]
check("the Alignment pop-up menu holds Show Rulers and 1 px grid in that order", names[:2] == ["miAlignShowRulers", "miAlign1pxgrid"], names)
j = lfm.index("object sbView: TSplitButton"); sb = lfm[j:j + 800]
check("Show Position Bar is the main action of the Alignment split button (a check button)", "AutoCheck = True" in sb and "OnClick = DoShowPosition" in sb, sb[:400])
check("the Alignment split button opens that menu", "DownArrowPopup = pmAlignmentOptions" in sb, sb[:300])
# --- a design: the check box is grayed, the menu item hidden
out = run(["newdoc A4", "registerframe x all", "onepxgrid 1", "echo D", "aligntogrid"])
check("in a design the 1 px grid check box is grayed and stays off", "ONEPXGRID checked=0 enabled=0 mm=2.000 dot600=6 dot100=1 alignmm=2.000" in out, [l for l in out if l.startswith("ONEPX")])
check("in a design the Align to Grid item is not shown", "ALIGNTOGRID visible=0 enabled=0" in out, [l for l in out if l.startswith("ALIGN")])
# --- the Pin button of the Draw tab: hidden in a design, shown in a symbol, and it chooses the Pin tool
out = run(["newdoc A4", "registerframe x all", "pinbutton", "pinbutton click", "lib %s" % lib, "sym new=0", "pinbutton", "pinbutton click", "echo X"])
pb = [l for l in out if l.startswith("PINBUTTON")]
check("the Pin button is hidden in a design and a click does nothing", pb and pb[0] == "PINBUTTON visible=0 tool=0 down=0 pintool=0" and pb[1].startswith("PINBUTTON visible=0"), pb)
check("in a symbol it is shown, and a click chooses the Pin tool and presses the button", len(pb) == 4 and pb[2].startswith("PINBUTTON visible=1 tool=0") and pb[3] == "PINBUTTON visible=1 tool=%s down=1 pintool=1" % pb[3].split("tool=")[1].split()[0], pb)
# --- a symbol
G = 2.0
S = ["newdoc A4", "registerframe x all", "lib %s" % lib, "sym new=0", "onepxgrid 1", "snap off", "echo G1",
     "tool line", "mouse move 31 41", "mouse down 31 41", "mouse move 61 43", "mouse up 61 43",
     "tool rect", "mouse move 70.2 80.6", "mouse down 70.2 80.6", "mouse move 90.4 100.8", "mouse up 90.4 100.8",
     "tool pin", "mouse move 41.4 61.6", "mouse down 41.4 61.6", "mouse up 41.4 61.6",
     "tool select", "selectall", "echo B", "selpoints", "aligntogrid", "echo A", "selpoints", "undo", "echo U", "selpoints", "redo", "aligntogrid", "echo R", "selpoints",
     "onepxgrid 0", "echo OFF", "gridinfo"]
out = run(S)
g1 = [l for l in out if l.startswith("ONEPXGRID")]
check("in a symbol the check box is enabled; ticked, the grid stays 2 mm (spacing and snapping unchanged) and the dots are one pixel at 600% (and at 100%); Align uses the sheet grid", g1 and g1[0] == "ONEPXGRID checked=1 enabled=1 mm=2.000 dot600=1 dot100=1 alignmm=2.000", g1)
check("the Align to Grid item is shown and enabled with a selection", "ALIGNTOGRID visible=1 enabled=1" in out, [l for l in out if l.startswith("ALIGN")])
B, A, U = pts(out, "B"), pts(out, "A"), pts(out, "U")
check("three objects were drawn off the grid (line, rectangle, pin)", len(B) == 3 and [b[0] for b in B] == ["TDrawLine", "TDrawSquare", "TDrawPin"], B)
ok = len(A) == 3 and len(B) == 3
if ok:
    for b, a in zip(B, A):
        want = (near(G, b[1][0]), near(G, b[1][1]))
        ok = ok and abs(a[1][0] - want[0]) < .002 and abs(a[1][1] - want[1]) < .002
check("each object's first end (the pin's connection end) is on the nearest 2 mm dot", ok, (B, A))
ok2 = len(A) == 3
if ok2:
    for b, a in zip(B, A):
        ok2 = ok2 and abs((a[2][0] - a[1][0]) - (b[2][0] - b[1][0])) < .002 and abs((a[2][1] - a[1][1]) - (b[2][1] - b[1][1])) < .002
check("the shapes are not changed (the other end moved by the same amount)", ok2, (B, A))
check("undo puts them back as one step", U == B, (B, U))
check("redo and align again gives the same places", pts(out, "R") == A, pts(out, "R"))
c = [l for l in out if l.startswith("GRIDINFO")]
check("unticking the box leaves the 2 mm grid as it was", c and "mm=2.000" in c[-1], c)
o2 = [l for l in out if l.startswith("ONEPXGRID")]
check("unticked, the dots are as many pixels as the zoom is hundreds of per cent (6 at 600%)", len(o2) > 1 and "dot600=6" in o2[-1], o2)
# the pop-up menu: Z-Order has Align to Grid in a symbol, not in a design
out = run(["newdoc A4", "registerframe x all", "lib %s" % lib, "sym new=0", "tool line", "mouse move 31 41", "mouse down 31 41", "mouse move 61 43", "mouse up 61 43", "tool select", "ctxmenu 45 42"])
check("in a symbol the pop-up menu's Z-Order submenu lists Align to Grid", any(l.startswith("CTX 1 Align_to_Grid enabled=1") for l in out), [l for l in out if l.startswith("CTX 1")])
out = run(["newdoc A4", "registerframe x all", "tool line", "mouse move 31 41", "mouse down 31 41", "mouse move 61 43", "mouse up 61 43", "tool select", "ctxmenu 45 42"])
check("in a design it does not", not any("Align_to_Grid" in l for l in out) and any(l.startswith("CTX 1 Send_to_Back") for l in out), [l for l in out if l.startswith("CTX 1")])
# --- mutation: an oracle that rounds down is not what the program does
check("(mutation) rounding down would give other places than the nearest dot for some object", len(A) == 3 and any(abs(a[1][0] - math.floor(b[1][0] / G) * G) > .002 or abs(a[1][1] - math.floor(b[1][1] / G) * G) > .002 for a, b in zip(A, B)), (B, A))
print("%d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
