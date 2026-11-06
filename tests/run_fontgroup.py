#!/usr/bin/env python3
"""A selection of different kinds of objects (a text and a label here) has no frame of its own, so the program makes its editors; the font properties they share
(face, size, bold, italic) are one group, the frame QFontGroup laid out like the font panel of the designed frames, and not four captions and editors. Oracles: the
panel's controls (PROPCTL lines: the group is one control of class TfmFontGroup and no separate font caption is made), the property dump (PROPS) after a size,
bold, italic and a face are chosen in the group, and undo. Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Font group checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:500])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "h"); os.makedirs(home)
s = """newdoc A4
tool text
mouse down 50 30
setprop text Hello
tool label
mouse down 50 60
setprop text NET1
tool select
selectall
props
propspanel
frameact sel cbFontHeight enter 18
frameact sel sbFontBold click
frameact sel sbFontItalic click
frameact sel cbFontFace enter DejaVu Serif
props
undo
props
"""
open(os.path.join(tmp, "s.txt"), "w").write(s)
o = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s.txt")], capture_output=True, text=True, timeout=200,
                   env=dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))).stdout.splitlines()
pr = [l for l in o if l.startswith("PROPS ")]
ctl = [l for l in o if l.startswith("PROPCTL ")]
check("three property dumps", len(pr) == 3, o[-8:])
if len(pr) == 3:
    check("the shared font properties are there (face, size, bold, italic)", all(k in pr[0] for k in ("font.face=Arial", "font.height=10", "font.bold=0", "font.italic=0")), pr[0])
    check("the group applies the size, bold, italic and face to both objects", all(k in pr[1] for k in ("font.face=DejaVu Serif", "font.height=18", "font.bold=1", "font.italic=1")), pr[1])
    check("undo takes back the last change only (the face)", "font.face=Arial" in pr[2] and "font.height=18" in pr[2], pr[2])
check("the font editors are one group", sum(1 for l in ctl if l.startswith("PROPCTL TfmFontGroup")) == 1, ctl)
check("no separate caption for a font property is made", not any("[Font" in l or "[Size" in l or "[Bold" in l or "[Italic" in l for l in ctl), ctl)
print("Font group checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
