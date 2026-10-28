#!/usr/bin/env python3
"""Text tool and text frame: new text reads Right (TinyCAD's default), the Text frame has a colour button right of the Italic button that sets the text colour,
(not for wire labels, which have no colour) and the 2 pixel separator of the View tab is left of the properties panel (between Position and the properties).
Oracles: the stored Dir of the placed text (TEXTINFO), the colour read back with PROPS, and the Left values of separator and panel."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Text frame checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:400])
s = """newdoc A4
registerframe x all
tool text
clickmm 50 50
echo PLACED
textinfo
frameinfo sel
propspanel
frameact sel cbTextColor color 00FF00
echo COLORED
props
tool label
clickmm 100 50
echo LABEL
frameinfo sel
frameact sel cbTextColor color 0000FF
props
"""
h = os.path.join(tmp, "h"); os.makedirs(h); open(os.path.join(tmp, "s.txt"), "w").write(s)
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s.txt")], capture_output=True, text=True, timeout=120,
                   env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
o = r.stdout.split("\n")
def after(tag, prefix, n=12):
    i = o.index(tag); return [l for l in o[i:i + n] if l.startswith(prefix)]
try:
    ti = after("PLACED", "TEXTINFO")[0].split()
    check("a text placed with the Text tool reads Right (direction 3)", ti[6] == "3", ti)
    fi = "\n".join(l for l in o if l.startswith("FRAMEINFO"))
    check("the text frame has a colour button bound to the text colour", "cbTextColor" in fi, fi[:300])
    pp = [l for l in o if l.startswith("PROPSPANEL")][0]
    sl = int(re.search(r"sepleft=(\d+)", pp).group(1)); pl = int(re.search(r"panelleft=(\d+)", pp).group(1))
    check("the separator is left of the properties panel", sl < pl and int(re.search(r"sepvisible=(\d)", pp).group(1)) == 1, pp)
    p1 = [l for l in o if l.startswith("PROPS ")]
    check("the colour button changes the text colour", any("font.color=00FF00" in l for l in p1), p1)
    check("a wire label has no text colour property, so the button does not change it", not any("font.color=0000FF" in l for l in p1), p1)
except Exception as e:
    check("the script ran", False, repr(e) + "\n".join(o[-10:]))
print("Text frame checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
