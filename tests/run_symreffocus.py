#!/usr/bin/env python3
"""Double clicking one placed symbol (it is chosen by the first click) puts the focus in the reference box (edRef) of its property frame with the whole reference selected, on the real program under Xvfb.
Oracle: the reference shown is read from the library symbol's own reference letters (U? style) as the program placed it, compared with what the focused box holds;
the selection length must equal the text length. Selecting a wire (no frame with a reference) does not put the focus in edRef.
Needs the built program, xvfb and the example libraries (TC_EXAMPLES)."""
import os, re, shutil, sqlite3, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
LIB = os.path.join(EX, "libraries", "gen_passive.TCLib")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not os.path.exists(LIB):
    print("Symbol reference focus checks skipped: need xvfb-run, the built program and the example libraries"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
lib = os.path.join(tmp, "g.TCLib"); shutil.copy(LIB, lib)
_c = sqlite3.connect(lib); _names = [r[0] for r in _c.execute("select Name from Name where Type=0 order by NameID")]; _c.close()
ROW0 = sorted(_names, key=str.lower).index(_names[0])
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:500])
def run(lines):
    f = os.path.join(tmp, "s.txt"); open(f, "w").write("\n".join(lines) + "\n")
    h = tempfile.mkdtemp(dir=tmp)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
o = run(["newdoc \"ISO A4\" landscape", "lib " + lib, "libplace %d 120 100" % ROW0, "tool select", "selclear", "focusinfo", "selectclass TDrawMethod", "focusinfo", "viewdblclick", "focusinfo"])
F = [l for l in o if l.startswith("FOCUS ")]
check("three focus lines", len(F) == 3, o[-8:])
if len(F) == 3:
    check("a single click choosing the symbol does not move the focus into the reference box", 'text="R?"' not in F[1], F[1])
    F = [F[0], F[2]]
    check("nothing chosen: the focus is not in a reference box", 'text="R?"' not in F[0], F[0])
    m = re.match(r'FOCUS (\S*) text="(.*)" selstart=(\d+) sellen=(\d+)', F[1])
    check("one symbol chosen: the focus is in a text box holding its reference (R? for a resistor: letters and a ?)", bool(m) and re.fullmatch(r"[A-Za-z]+\?", m.group(2) or "") is not None, F[1])
    if m:
        check("the whole reference is selected (and it is not empty)", m.group(2) != "" and int(m.group(3)) == 0 and int(m.group(4)) == len(m.group(2)), F[1])
o = run(["newdoc \"ISO A4\" landscape", "tool wire", "mouse down 40 40", "mouse down 100 40", "tool select", "selectclass TDrawLine", "focusinfo"])
F = [l for l in o if l.startswith("FOCUS ")]
check("a wire chosen: the focus does not go to a reference box", F and 'text="R?"' not in F[-1], F)
o = run(["newdoc \"ISO A4\" landscape", "tool wire", "mouse down 40 40", "mouse down 100 40", "tool select", "selectclass TDrawLine", "viewdblclick", "focusinfo"])
F = [l for l in o if l.startswith("FOCUS ")]
check("a double click with a wire chosen: no reference box takes the focus", F and 'text="R?"' not in F[-1], F)
# Del: with the box as it was given (all selected) the symbol is deleted; once the caret was moved Del edits the text
o = run(["newdoc \"ISO A4\" landscape", "lib " + lib, "libplace %d 120 100" % ROW0, "tool select", "selectclass TDrawMethod", "viewdblclick", "info", "formdel", "info"])
I = [int(re.search(r"objects=(\d+)", l).group(1)) for l in o if l.startswith("INFO ")]
check("Del with the reference box as it was given: the symbol is deleted (not the text)", len(I) == 2 and I[1] == I[0] - 1, (I, o[-6:]))
o = run(["newdoc \"ISO A4\" landscape", "lib " + lib, "libplace %d 120 100" % ROW0, "tool select", "selectclass TDrawMethod", "viewdblclick", "editcaret 0 0", "info", "formdel", "info"])
I = [int(re.search(r"objects=(\d+)", l).group(1)) for l in o if l.startswith("INFO ")]
F = [l for l in o if l.startswith("FORMDEL")]
check("after the caret was put in the box: Del edits the text and the symbol stays", len(I) == 2 and I[1] == I[0] and F and 'text="?"' in F[-1], (I, F))
print("symbol reference focus checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
