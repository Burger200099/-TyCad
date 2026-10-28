#!/usr/bin/env python3
"""Right click menu entries for lines and placed designs (TinyCAD IDR_LINETOOL_EDIT and IDR_HIERARCHICAL_EDIT), on the real program under Xvfb.
Oracles: the line ends are read from the saved design file (XML), the expected result is plain arithmetic (nearer end stays, the far one lines up):
  - a wire / bus / line: Make horizontal, Make vertical at the top of the menu, then a separator and TinyCAD's common commands
  - the nearer end of the click stays, the other end lines up with it (both ends, both directions)
  - an already straight line is not changed (no undo step); one undo brings the old ends back
  - a placed design: Reload symbol from design, Open design, a separator, then the common commands; no Replace Symbol...
  - Reload symbol from design shows the changed design; Open design opens the file as a document
Needs the built program and xvfb."""
import os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Context menu 2 checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:600])
k = [0]
def run(lines):
    k[0] += 1; h = os.path.join(tmp, "h%d" % k[0]); os.makedirs(h)
    f = os.path.join(tmp, "s%d.txt" % k[0]); open(f, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
def menu(o, which=0):
    out = []; res = []
    for l in o:
        m = re.match(r"CTX (\d+) (\S+) enabled=(\d) key=\[(.*)\]", l)
        if m: out.append((m.group(2), int(m.group(3))))
        elif l.startswith("CTX done"): res.append(out); out = []
    return res
def ends(path, tag):
    r = ET.parse(path).getroot(); e = r.iter(tag).__next__()
    a = [float(x) for x in e.get("a").split(",")]; b = [float(x) for x in e.get("b").split(",")]
    return a, b
COMMON = ["Undo", "Redo", "-", "Z-Order", "Bring_to_Front", "Send_to_Back", "-", "Cut", "Copy", "Paste", "Duplicate", "Select_All", "Select_All_Alike", "-", "Delete", "-", "Rotate_Left", "Rotate_Right", "Flip", "-", "Zoom_In", "Zoom_Out"]
def body(tag): return '<?xml version="1.0"?>\n<TinyCADSheets><TinyCAD><NAME>a</NAME><DETAILS><Size width="1485" height="1050"/><GRID spacing="250" snap="1"/></DETAILS>%s</TinyCAD></TinyCADSheets>\n'
# a slanted line from 100,100 to 300,250 (mm, as the file says)
for tag in ("WIRE", "BUS", "LINE"):
    src = os.path.join(tmp, tag + ".dsn")
    open(src, "w").write(body(tag) % ('<%s a="100,100" b="300,250"/>' % tag))
    for click, name in (("140 130", "near A"), ("260 220", "near B")):
        for cmd, vert in (("Make_horizontal", 0), ("Make_vertical", 1)):
            out = os.path.join(tmp, "o_%s_%s_%d.dsn" % (tag, name.replace(" ", ""), vert))
            o = run(["open " + src, "ctxmenu %s" % click, "ctxclick %s" % cmd, "save " + out])
            ms = menu(o)
            if tag == "WIRE" and name == "near A" and vert == 0:
                check("line menu: Make horizontal, Make vertical, a separator, then TinyCAD's common commands", ms and [c for c, e in ms[0]] == (["Add_wire_cut_here"] if tag == "WIRE" else []) + ["Make_horizontal", "Make_vertical", "-"] + COMMON, ms[:1])
            if not os.path.exists(out): check("%s %s %s saved" % (tag, name, cmd), False, o[-5:]); continue
            a, b = ends(out, tag)
            # oracle: the nearer end stays; far end lines up
            if name == "near A":
                exp = ([100, 100], [100, 250]) if vert else ([100, 100], [300, 100])
            else:
                exp = ([300, 100], [300, 250]) if vert else ([100, 250], [300, 250])
            check("%s %s %s: nearer end stays, the other lines up" % (tag, name, cmd), (a, b) == exp, (a, b, exp))
# already straight: no change, no undo step recorded
src = os.path.join(tmp, "st.dsn"); open(src, "w").write(body("WIRE") % '<WIRE a="100,100" b="300,100"/>')
o = run(["open " + src, "ctxmenu 200 100", "ctxclick Make_horizontal", "ctxmenu 30 20"])
ms = menu(o)
check("an already horizontal wire: Make horizontal changes nothing (Undo stays off)", len(ms) == 2 and dict(ms[1]).get("Undo") == 0, ms)
# undo returns the old ends
out = os.path.join(tmp, "undo.dsn"); src = os.path.join(tmp, "WIRE.dsn")
o = run(["open " + src, "ctxmenu 140 130", "ctxclick Make_vertical", "undo", "save " + out])
a, b = ends(out, "WIRE") if os.path.exists(out) else (None, None)
check("one undo puts the old ends back", (a, b) == ([100, 100], [300, 250]), (a, b))
# a line is not offered the polygon or symbol entries, and an empty click has no line entries
o = run(["open " + src, "selclear", "ctxmenu 20 20"])
check("no line chosen: no Make horizontal / vertical", "Make_horizontal" not in [c for c, e in menu(o)[0]], menu(o))
# --- placed design -------------------------------------------------------------------------------------------------------------------------------------------------
C = os.path.join(tmp, "child.dsn"); P = os.path.join(tmp, "par.dsn")
RECT = '<RECTANGLE a="23,31" b="87,95" style="0" fill="0"/><PIN pos="23,47" direction="3" length="15" which="0" elec="0" show="1" number="1" part="0"/>'
def child(b): return ('<?xml version="1.0"?>\n<TinyCADSheets><TinyCAD><NAME>Top</NAME><WIRE a="1,1" b="5,1"/></TinyCAD><HierarchicalSymbol><NAME>x</NAME><DETAILS><Size width="1485" height="1050"/></DETAILS>%s</HierarchicalSymbol></TinyCADSheets>' % b)
open(C, "w").write(child(RECT))
open(P, "w").write('<?xml version="1.0"?>\n<TinyCADSheets><TinyCAD><NAME>T</NAME><DETAILS><Size width="1485" height="1050"/></DETAILS><HIERARCHICAL_SYMBOL pos="100,200" rotate="0" can_scale="1" scale_x="1" scale_y="1" file="%s"><FIELD type="0" description="Ref" value="H1" show="1" pos="0,0"/><FIELD type="0" description="Design" value="" show="0" pos="0,0"/></HIERARCHICAL_SYMBOL></TinyCAD></TinyCADSheets>' % C)
o = run(["open " + P, "selectclass TDrawHierarchicalSymbol", "hiersymbols", "ctxmenu 90 190", "docs"])
hs = [l for l in o if l.startswith("HIER ") and "end" not in l]
ms = menu(o)
check("placed design: the file was read", hs and "hassym=1" in hs[0], hs)
check("placed design: Reload symbol from design, Open design, a separator, then the common commands; no Replace Symbol",
      ms and [c for c, e in ms[0]] == ["Reload_symbol_from_design", "Open_design", "-"] + COMMON, ms[:1])
o = run(["open " + P, "selectclass TDrawHierarchicalSymbol", "ctxmenu 90 190", "ctxclick Open_design", "docs"])
dc = [l for l in o if l.startswith("DOCS")]
check("Open design opens the design file as a second document", dc and dc[-1].startswith("DOCS 2"), dc)
def box(l): return re.search(r"box=(\S+)", l).group(1)
open(C + ".new", "w").write(child('<RECTANGLE a="23,31" b="150,140" style="0" fill="0"/><PIN pos="23,47" direction="3" length="15" which="0" elec="0" show="1" number="1" part="0"/>'))
o = run(["open " + P, "selectclass TDrawHierarchicalSymbol", "ctxmenu 90 190", "hiersymbols", "shellcopy %s %s" % (C + ".new", C), "ctxmenu 90 190", "ctxclick Reload_symbol_from_design", "hiersymbols"])
hs = [l for l in o if l.startswith("HIER ") and "end" not in l]
check("reload: the box grows to the changed design's (oracle: the new rectangle is larger than the old)",
      len(hs) == 2 and abs(float(box(hs[1]).split(",")[0])) > abs(float(box(hs[0]).split(",")[0])), hs)
# mutation guard note: removing the Reload handler makes the box equal -> this check fails
print("Context menu 2 checks: %d, failed %d" % (checks, len(fails))); sys.exit(1 if fails else 0)
