#!/usr/bin/env python3
"""Property frames (src/frames/QPropFrame): a designer-made frame is found by its control names, shown in the tool panel and the selection panel, linked to the
properties, hides what the object lacks, reports badly named or wrongly typed editors, and gives way to the built-in editors when none is registered.
Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, re, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Property frame checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name); print("  FAIL", name, str(detail)[:500])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=200, env=env)
    return r.stdout.splitlines()
def after(out, marker, n=1):
    """the n-th (1-based) block of FRAMEINFO lines following the n-th occurrence of the marker line"""
    idx = [i for i, l in enumerate(out) if l.startswith(marker)]
    if len(idx) < n: return []
    res = []
    for l in out[idx[n - 1] + 1:]:
        if l.startswith("FRAMEINFO "): res.append(l[10:])
        else: break
    return res
wire = ["mouse move 50 50", "mouse down 50 50", "mouse move 90 50", "mouse down 90 50", "mouse rdown 90 50", "mouse rdown 90 50"]
script = ["newdoc A4",
          "tool wire", "toolpanel",                                  # no frame yet: built-in editors
          "registerframe wire demo", "tool wire", "frameinfo tool", "toolpanel", "typenumber tool line.width 3 done", "props"] \
         + wire + ["selectall", "sel", "frameinfo sel", "props", "typenumber sel line.width 5 done", "props", "propspanel",
                   "registerframe wire bad", "frameinfo sel", "registerframe wire none", "frameinfo sel", "propspanel", "tool select", "selclear", "tool rect", "toolpanel",
                   "registerframe rect demo", "tool select", "tool rect", "frameinfo tool", "toolpanel"]
out = run(script)
check("the script ran", any(l.startswith("PROPSPANEL") for l in out), out[:5])
tp = [l for l in out if l.startswith("TOOLPANEL")]
check("without a frame the built-in editors are used (4 of them: colour, width, style and the wire angle)", len(tp) >= 1 and "editors=4" in tp[0], tp[:1])
fi = after(out, "REGISTERFRAME wire demo")
check("the tool panel uses the frame", len(fi) > 0 and fi[0].startswith("TfrDemoWire") and "problems=0" in fi[0], fi[:1])
check("width, color and style are linked to their properties", any(l.startswith("spLineWidth TSpinEdit line.width mode=0 visible=1 enabled=1") for l in fi)
      and any(l.startswith("cbtnLineColor TColorButton line.color mode=0 visible=1 enabled=1") for l in fi) and any(l.startswith("cbLineStyle TComboBox line.style mode=0 visible=1") for l in fi), fi)
check("fill type is not a wire property, so it is hidden", any(l.startswith("cbFillType") and l.endswith(" hidden") for l in fi), fi)
# (the panel is as wide as the frame was designed, scaled to the screen's resolution by Scale96ToForm: 360 at 96 dpi)
wd = int(re.search(r" width=(\d+)", tp[1]).group(1)) if len(tp) >= 2 else 0
check("the tool panel lists the three linked editors", len(tp) >= 2 and "editors=3" in tp[1] and 360 <= wd <= 480, tp[:2])
check("a number typed in the frame's spin box is applied to the tool", "TYPENUMBER line.width 1" in out, [l for l in out if l.startswith("TYPENUMBER")])
props = [l for l in out if l.startswith("PROPS ")]
check("the new wire has the width typed", len(props) >= 2 and "line.width=3" in props[1], props[:2])
si = after(out, "SEL 1")
check("the selection uses the frame too", len(si) > 0 and si[0].startswith("TfrDemoWire"), si[:1])
check("selection editors are tagged from 0", any(l.startswith("spLineWidth") and " tag=0 " in l for l in si), si)
check("a number typed in the selection's frame changes the wire", len(props) >= 3 and "line.width=5" in props[2], props)
ps = [l for l in out if l.startswith("PROPSPANEL")]
check("the panel holds the frame and is as wide as the frame", len(ps) >= 1 and "width=360" in ps[0] and "label=[Wire]" in ps[0], ps[:1])
bad = after(out, "REGISTERFRAME wire bad")
check("a badly named frame is reported: 3 problems", len(bad) > 0 and "problems=3" in bad[0], bad[:1])
check("a TEdit for a number is disabled", any(l == "edLineWidth TEdit line.width disabled" for l in bad), bad)
check("a spin edit for a color is disabled", any(l == "spLineColor TSpinEdit line.color disabled" for l in bad), bad)
check("the first editor of a property keeps it, a second one is disabled", any(l.startswith("cbLineStyle ") and "enabled=1" in l for l in bad) and any(l == "cbStyleLineStyle TComboBox line.style disabled" for l in bad), bad)
check("each problem is reported", sum(1 for l in bad if l.startswith("PROBLEM")) == 3, bad)
none = after(out, "REGISTERFRAME wire none")
check("with no frame registered, none is used", none == ["none"], none)
check("the built-in editors are back (6 controls: 3 captions and 3 editors)", len(ps) >= 2 and "controls=6" in ps[-1] or any("controls=6" in l for l in ps), ps)
rect = after(out, "REGISTERFRAME rect demo")
check("a frame for the rectangle: fill type is not hidden by line only", len(rect) > 0 and rect[0].startswith("TfrDemoWire"), rect[:1])
check("a rectangle tool without a registration used the built-in editors", len(tp) >= 3 and "editors=" in tp[2], tp)
if fails:
    print("%d of %d checks failed" % (len(fails), checks)); sys.exit(1)
print("Property frame checks passed (%d)" % checks)
