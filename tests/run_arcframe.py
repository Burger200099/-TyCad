#!/usr/bin/env python3
"""The Arc property frame (QArc, fmArc) and the Arc tool, which works like the Polygon tool: the tool's panel and the panel of a selected arc show the line, the fill and the in / out radio
buttons (rbArcIn, rbArcOut, linked to 'arc.type'); a click starts the next arc at the last point, every click after the first turns the next arc the other way (the radio buttons follow), the
arc being drawn is ghosted as it will look, Esc drops the whole drawing, a double click commits it, and choosing in or out changes the selected arc (seen in the picture).
Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, re, sys, shutil, subprocess, tempfile
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Arc frame checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env)
    return r.stdout.splitlines()
def radios(out, start=0):
    """(in, out) shown by the next FRAMEINFO block after index start"""
    i = next(k for k in range(start, len(out)) if out[k].startswith("FRAMEINFO Tfm"))
    d = {}
    for l in out[i + 1:i + 12]:
        m = re.match(r"FRAMEINFO (rbArc\w+) TRadioButton (\S+) mode=(\d+) visible=(\d) enabled=(\d) .*shown=\[(\d)\]", l)
        if m: d[m.group(1)] = (m.group(2), m.group(3), m.group(4), m.group(5), m.group(6))
    return out[i], d
def mark(n): return "echo M%d" % n
def mark(n): return "echo M%d" % n
g0 = os.path.join(tmp, "g0.bmp"); g1 = os.path.join(tmp, "g1.bmp"); a1 = os.path.join(tmp, "a1.bmp"); a2 = os.path.join(tmp, "a2.bmp")
A, B, C = (60, 100), (100, 130), (140, 100)
D, E = (60, 150), (100, 180)
S = ["newdoc A4", "registerframe x all", "tool arc", mark(1), "frameinfo tool", "arctype show", "frameact tool rbArcOut click", mark(2), "arctype show", "frameinfo tool",
     "frameact tool rbArcIn click", mark(3), "arctype show", "frameinfo tool",
     # three clicks: the first starts, the second ends the first arc (in) and turns the next to out, the third ends the second arc and turns it back
     "mouse move %d %d" % A, "mouse down %d %d" % A, mark(4), "arctype show", "mouse move %d %d" % B, "shot " + g0, "mouse down %d %d" % B, mark(5), "arctype show",
     "mouse move %d %d" % C, "shot " + g1, "mouse down %d %d" % C, mark(6), "arctype show", "mouse move 180 130", "formesc view", mark(7), "objects", "arctype show",
     # a second drawing: in is ticked again; the double click commits what was drawn
     "tool arc", "frameact tool rbArcIn click", "mouse down %d %d" % A, "mouse down %d %d" % B, "mouse down %d %d" % C, "mouse dbl %d %d" % C, mark(8), "objects",
     "selidx 0", mark(9), "frameinfo sel", "props", "selclear",
     "selidx 0", "frameact sel rbArcOut click", mark(10), "props", "frameinfo sel", "selclear",
     # a single arc, in then out, for the picture
     "tool arc", "frameact tool rbArcIn click", "mouse down %d %d" % D, "mouse down %d %d" % E, "mouse dbl %d %d" % E, "selclear", "shot " + a1,
     "selidx 1", "frameact sel rbArcOut click", mark(11), "props", "selclear", "shot " + a2, "echo end"]
out = run(S)
check("the script ran", "end" in out, out[-5:])
def at(m): return out.index(m)
def arctype(m): return out[at(m) + 1]
h, r = radios(out, at("M1"))
check("the Arc tool shows the arc frame, no problems", h.startswith("FRAMEINFO TfmArc ") and "problems=0" in h, h)
check("both radio buttons are linked to arc.type as radio buttons (mode 4), visible and enabled", set(r) == {"rbArcIn", "rbArcOut"} and all(v[0] == "arc.type" and v[1] == "4" and v[2] == "1" and v[3] == "1" for v in r.values()), r)
check("the tool starts with arc in ticked", r["rbArcIn"][4] == "1" and r["rbArcOut"][4] == "0", r)
check("the frame's line, width and fill editors are linked too", all(any(l.startswith("FRAMEINFO " + n + " ") and (k in l) for l in out[at("M1"):at("M1") + 12]) for n, k in (("seWidth", "line.width"), ("cbWireColor", "line.color"), ("cbWireType", "line.style"), ("bbFill", "fill.type"))))
check("clicking out sets the tool's arc to out (2) and moves the tick", arctype("M2") == "ARCTYPE 2 in=1 out=2" and radios(out, at("M2"))[1]["rbArcOut"][4] == "1" and radios(out, at("M2"))[1]["rbArcIn"][4] == "0", arctype("M2"))
check("clicking in sets it back (1)", arctype("M3") == "ARCTYPE 1 in=1 out=2" and radios(out, at("M3"))[1]["rbArcIn"][4] == "1", arctype("M3"))
check("the first click starts the arc and does not turn the kind (still in)", arctype("M4") == "ARCTYPE 1 in=1 out=2", arctype("M4"))
check("the second click turns the next arc to out (2)", arctype("M5") == "ARCTYPE 2 in=1 out=2", arctype("M5"))
check("the third click turns it back to in (1)", arctype("M6") == "ARCTYPE 1 in=1 out=2", arctype("M6"))
check("Esc drops the whole drawing: no object was made", out[at("M7") + 1] == "OBJ end 0", out[at("M7") + 1:at("M7") + 3])
check("the double click commits one polygon", out[at("M8") + 1:at("M8") + 3] == ["OBJ TDrawPolygon id=1", "OBJ end 1"], out[at("M8") + 1:at("M8") + 3])
# the ghost and the pictures: the side of a chord the ink lies on (the page is at 224,20 in the picture and 2.5 pixels to the millimetre)
PX = 2.5
def side(path, P, Q, left=False, right=False):
    """ink off the chord P-Q: (count, on one side, on the other); left / right keep only the part of the picture clear of the next / previous arc"""
    im = Image.open(path).convert("L"); ax, ay = 224 + PX * P[0], 20 + PX * P[1]; bx, by = 224 + PX * Q[0], 20 + PX * Q[1]
    n = pos = neg = 0
    x0, x1 = int(min(ax, bx)) - 5, int(max(ax, bx)) + 6
    if left: x1 = int(max(ax, bx)) - 6
    if right: x0 = int(min(ax, bx)) + 6
    for x in range(x0, x1):
        for y in range(int(min(ay, by)) - 5, int(max(ay, by)) + 6):
            if im.getpixel((x, y)) < 110:
                c = (bx - ax) * (y - ay) - (by - ay) * (x - ax)
                c /= max(((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5, 1)      # (the distance from the chord, in pixels)
                if abs(c) > 4: n += 1; pos += c > 0; neg += c < 0
    return n, pos, neg
gA, gB = side(g0, A, B), side(g1, B, C, right=True)
check("while drawing, the arc to the pointer (in) is ghosted as a curve to one side of its chord", gA[0] > 20 and min(gA[1], gA[2]) <= 2, gA)
check("and after the click the next arc (out, to the pointer) is ghosted as a curve too (ink off its straight line)", gB[0] > 20, (gA, gB))
h9, r9 = radios(out, at("M9"))
p9 = [l for l in out[at("M9"):at("M10")] if l.startswith("PROPS ")][0]
check("the committed arc polygon shows the arc frame; its two arcs differ, so the kind is mixed (empty)", h9.startswith("FRAMEINFO TfmArc ") and p9.endswith("arc.type="), (h9, p9))
check("it is not offered the Closed box of the polygon", "poly.closed" not in p9, p9)
p10 = [l for l in out[at("M10"):] if l.startswith("PROPS ")][0]
h10, r10 = radios(out, at("M10"))
check("clicking out on it turns every arc out (arc.type=out) and moves the tick", "arc.type=out" in p10 and r10["rbArcOut"][4] == "1" and r10["rbArcIn"][4] == "0", (p10, r10))
check("the picture changes when the kind is changed", open(a1, "rb").read() != open(a2, "rb").read())
sa1, sa2 = side(a1, D, E), side(a2, D, E)
check("a single arc (in) is all on one side of its chord, and on the other side once out is chosen", sa1[0] > 20 and min(sa1[1], sa1[2]) <= 2 and sa2[0] > 20 and min(sa2[1], sa2[2]) <= 2 and (sa1[1] > 0) != (sa2[1] > 0), (sa1, sa2))
print("Arc frame checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
