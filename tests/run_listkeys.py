#!/usr/bin/env python3
"""Editing the text of a value in the symbol parameter list (dropped down from a symbol text's panel) with the real keyboard (X key events through XTEST).
The Value cell is clicked with the mouse and keys are sent: End, Left, BackSpace remove the space before the 7 of 'Pump 7' (the caret moves with the arrows and Backspace deletes);
Ctrl+A, Ctrl+C, End, Ctrl+V give "Pump 7Pump 7" (the shortcuts work in the box); Home, Delete, Delete leave 'mp 7' and the symbol is still on the sheet (Delete edits the text, it is not the Delete command of the window); Esc ends the edit. The text is read back
from the program (script 'symlist sel text'). Needs Xvfb, python-xlib (Xlib), the built program."""
import os, shutil, subprocess, sys, tempfile, time
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
try:
    from Xlib import X, display, XK
    from Xlib.ext import xtest
except ImportError:
    X = None
if X is None or shutil.which("Xvfb") is None or not os.path.exists(BIN):
    print("List keys checks skipped: need Xvfb, python-xlib and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:500])
def run(keys, disp):
    D = ":%d" % disp
    xv = subprocess.Popen(["Xvfb", D, "-screen", "0", "1600x1000x24"], stderr=subprocess.DEVNULL); time.sleep(2)
    try:
        S = ["newdoc A4", "registerframe x all", "tool symboltext", "frameinfo tool", "frameact tool edSymbolText text Pump 7", "clickmm 80 40", "frameinfo sel", "symlist sel open", "symlist sel rows", "symlist sel pos", "symlist sel text",
             "sleep 12000", "symlist sel text", "sleep 1500", "symlist sel text", "selectall", "selcount"]
        sp = os.path.join(tmp, "s%d.txt" % disp); open(sp, "w").write("\n".join(S) + "\n")
        p = subprocess.Popen([exe, "--script", sp], env=dict(os.environ, DISPLAY=D, HOME=tempfile.mkdtemp(dir=tmp)), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        d = display.Display(D); time.sleep(5)
        # the list opens at the Properties panel's hidden button (far right); its first Value cell is 212 px right and 51 px below the list's corner
        pos = None
        xtest.fake_input(d, X.MotionNotify, x=1500, y=265); d.sync(); time.sleep(.5)
        xtest.fake_input(d, X.ButtonPress, 1); xtest.fake_input(d, X.ButtonRelease, 1); d.sync(); time.sleep(.5)
        for k in keys:
            mods = k.split("+")[:-1]; kn = k.split("+")[-1]
            mk = [d.keysym_to_keycode(XK.string_to_keysym({"ctrl": "Control_L"}[m])) for m in mods]
            kc = d.keysym_to_keycode(XK.string_to_keysym(kn))
            for m in mk: xtest.fake_input(d, X.KeyPress, m)
            xtest.fake_input(d, X.KeyPress, kc); xtest.fake_input(d, X.KeyRelease, kc)
            for m in mk: xtest.fake_input(d, X.KeyRelease, m)
            d.sync(); time.sleep(.25)
        out = p.communicate(timeout=120)[0]
    finally:
        xv.terminate(); xv.wait()
    return out.split("\n")
def texts(o): return [l.split(" ", 2)[2].split("|")[0] for l in o if l.startswith("SYMLIST text")]
o = run(["End", "Left", "BackSpace"], 91); t = texts(o)
check("End, Left, BackSpace in the Value box: 'Pump7' (the keys reach the box)", t[-1:] == ["Pump7"], (t, o[:12]))
o = run(["Home", "Delete", "Delete"], 92); t = texts(o)
check("Home, Delete, Delete in the Value box: 'mp 7' (Delete edits the text)", t[-1:] == ["mp 7"], (t, o[:12]))
check("the symbol text is still there after those Deletes", t[-1:] == ["mp 7"] and "SYMLIST text noframe" not in o, o[:12])
o = run(["ctrl+a", "ctrl+c", "End", "ctrl+v"], 93); t = texts(o)
check("Ctrl+A, Ctrl+C, End, Ctrl+V in the Value box: 'Pump 7Pump 7' (the shortcuts act on the box, not on the sheet)", t[-1:] == ["Pump 7Pump 7"], (t, o[:12]))
o = run(["ctrl+a", "ctrl+x"], 94); t = texts(o)
check("Ctrl+X in the Value box cuts its text and the symbol stays", t[-1:] == [""] and "SYMLIST text noframe" not in o, (t, o[:12]))
print("list keys: %d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
