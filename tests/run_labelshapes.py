#!/usr/bin/env python3
"""Wire label outlines and text directions, as TinyCAD (CDrawLabel::Paint) draws them, and the text box behaviours of the Properties frame.
Oracles are independent of the program: the structure of the rendered sheet bitmap (numpy / PIL) -- which end of an input / output / input-output label is
an arrowhead and which is closed flat, for all four directions; for a text, where its ink lies relative to the red attachment box, and that Up is the
horizontal rendering turned 90 degrees counterclockwise and Down turned 90 degrees clockwise (PIL rotate); and the focus / Del / floating text behaviour read
back from the program. Needs xvfb-run, numpy, PIL and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, re, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
try:
    import numpy as np
    from PIL import Image
except Exception:
    print("Label shape checks skipped: need numpy and PIL"); sys.exit(0)
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Label shape checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = os.environ.get("TC_KEEP") or tempfile.mkdtemp(); fails = []; checks = 0
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

def clusters(mask):
    """4-connected clusters of a boolean mask: list of (ys, xs)"""
    seen = np.zeros(mask.shape, bool); res = []
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]: continue
        st = [(y, x)]; seen[y, x] = True; pts = []
        while st:
            a, b = st.pop(); pts.append((a, b))
            for da, db in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                c, d = a + da, b + db
                if 0 <= c < mask.shape[0] and 0 <= d < mask.shape[1] and mask[c, d] and not seen[c, d]:
                    seen[c, d] = True; st.append((c, d))
        res.append(pts)
    return res

# ---- the sheet: labels of every style in every direction (style 0..3 by rows, direction 0 up, 1 down, 2 left, 3 right by columns), and texts
GX, GY = 45, 40
S = ["newdoc A4"]
for st in range(4):
    for d in range(4):
        S.append("addlabel %d %d _ %d %d" % (30 + d * GX, 30 + st * GY, st, d))
for d in range(4):
    S.append("addtext %d %d LqF7pLE %d" % (30 + d * GX, 190, d))
S.append("selectclass TDrawText")      # a text shows its red attachment box while it is selected (and is then drawn in the selection colour)
S.append("shot %s" % os.path.join(tmp, "a.bmp"))
S.append("selclear")
S.append("shot %s" % os.path.join(tmp, "b.bmp"))
run(S)
im = np.array(Image.open(os.path.join(tmp, "a.bmp")).convert("RGB")).astype(int)
red = (im[:, :, 0] > 200) & (im[:, :, 1] < 80) & (im[:, :, 2] < 80)
anchors = []
for pts in clusters(red):
    ys = [p[0] for p in pts]; xs = [p[1] for p in pts]
    if len(pts) >= 8 and max(ys) - min(ys) <= 8 and max(xs) - min(xs) <= 8: anchors.append(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2))
check("20 red attachment boxes (16 labels, 4 selected texts)", len(anchors) == 20, len(anchors))
im_unsel = np.array(Image.open(os.path.join(tmp, "b.bmp")).convert("RGB")).astype(int)
red_unsel = (im_unsel[:, :, 0] > 200) & (im_unsel[:, :, 1] < 80) & (im_unsel[:, :, 2] < 80)
check("a text that is not selected has no red box (only the 16 labels have)", len([c for c in clusters(red_unsel) if len(c) >= 8]) == 16, len([c for c in clusters(red_unsel) if len(c) >= 8]))
im = im_unsel          # the ink of the texts is measured on the picture without the selection colour
# map design mm to pixels from the first and last anchors
anchors.sort(key=lambda a: (round(a[1] / 20), a[0]))
def fit(a0, a1, m0, m1): s = (a1 - a0) / (m1 - m0); return s, a0 - s * m0
sx, ox = fit(min(a[0] for a in anchors), max(a[0] for a in anchors), 30, 30 + 3 * GX)
sy, oy = fit(min(a[1] for a in anchors), max(a[1] for a in anchors), 30, 190)
def at(xmm, ymm): return (ox + sx * xmm, oy + sy * ymm)
white = (im.sum(axis=2) > 740)
reddish = (im[:, :, 0] - np.maximum(im[:, :, 1], im[:, :, 2]) > 40)
ink = (~white) & (~reddish)
def window(xmm, ymm, r=int(14 * 2.5)):
    cx, cy = at(xmm, ymm); cx, cy = int(round(cx)), int(round(cy))
    return ink[cy - r:cy + r, cx - r:cx + r], (cx - r, cy - r), (cx, cy)
# ---- outlines: which end is an arrowhead, which is closed flat
# the end that attaches to the wire (where the red box is): left for Left (2), right for Right (3), top for Up (0), bottom for Down (1)
CONN = {0: "top", 1: "bottom", 2: "left", 3: "right"}
FAR = {"top": "bottom", "bottom": "top", "left": "right", "right": "left"}
EXPECT_TIP = {1: ("conn",), 2: ("far",), 3: ("conn", "far")}      # input: arrow at the wire end; output: at the other end; both
def end_kind(w, side):
    ys, xs = np.nonzero(w)
    if len(ys) == 0: return None
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    if side in ("left", "right"):
        col = x0 if side == "left" else x1
        n = int(w[:, col].sum()); span = y1 - y0 + 1
        return "flat" if n >= 0.6 * span else ("tip" if n <= 0.5 * span else "?%d/%d" % (n, span))
    row = y0 if side == "top" else y1
    n = int(w[row, :].sum()); span = x1 - x0 + 1
    return "flat" if n >= 0.6 * span else ("tip" if n <= 0.5 * span else "?%d/%d" % (n, span))
for st in range(1, 4):
    for d in range(4):
        w, _, _ = window(30 + d * GX, 30 + st * GY)
        conn = CONN[d]; far = FAR[conn]
        want_conn = "tip" if "conn" in EXPECT_TIP[st] else "flat"
        want_far = "tip" if "far" in EXPECT_TIP[st] else "flat"
        got_conn = end_kind(w, conn); got_far = end_kind(w, far)
        nm = ("input", "output", "input/output")[st - 1] + " " + ("up", "down", "left", "right")[d]
        check(nm + ": end at the wire is " + want_conn, got_conn == want_conn, got_conn)
        check(nm + ": far end is " + want_far, got_far == want_far, got_far)
# a normal label draws no outline: only its (here tiny) text
for d in range(4):
    w, _, _ = window(30 + d * GX, 30)
    ys, xs = np.nonzero(w)
    check("normal label %d draws no outline" % d, len(ys) < 40, len(ys))
# ---- text directions
crops = {}; anch = {}
for d in range(4):
    w, org, (cx, cy) = window(30 + d * GX, 190, 36)
    ys, xs = np.nonzero(w)
    check("text %d has ink" % d, len(ys) > 10)
    x0, x1, y0, y1 = xs.min() + org[0], xs.max() + org[0], ys.min() + org[1], ys.max() + org[1]
    crops[d] = w[ys.min():ys.max() + 1, xs.min():xs.max() + 1].astype(float)
    ax, ay = cx, cy
    if d == 0:   check("Up: starts at the anchor and reads upwards, to its left", abs(y1 - ay) <= 4 and x1 <= ax + 4 and (y1 - y0) > (x1 - x0), (x0, x1, y0, y1, ax, ay))
    if d == 1:   check("Down: starts at the anchor and reads downwards, to its left", abs(y0 - ay) <= 4 and x1 <= ax + 4 and (y1 - y0) > (x1 - x0), (x0, x1, y0, y1, ax, ay))
    if d == 2:   check("Left: ends at the anchor, horizontal", abs(x1 - ax) <= 4 and (x1 - x0) > (y1 - y0) and y1 <= ay + 4, (x0, x1, y0, y1, ax, ay))
    if d == 3:   check("Right: starts at the anchor, horizontal", abs(x0 - ax) <= 4 and (x1 - x0) > (y1 - y0) and y1 <= ay + 4, (x0, x1, y0, y1, ax, ay))
def corr(a, b):
    if a.shape != b.shape:      # (the rotated rendering may differ by a pixel in size: compare at the same size)
        if abs(a.shape[0] - b.shape[0]) > 3 or abs(a.shape[1] - b.shape[1]) > 3: return -1
        a = np.array(Image.fromarray((a * 255).astype('uint8')).resize((b.shape[1], b.shape[0]), Image.BILINEAR)).astype(float) / 255
    a = a - a.mean(); b = b - b.mean()
    return float((a * b).sum() / (np.sqrt((a * a).sum() * (b * b).sum()) + 1e-9))
H = crops[3]
check("Left reads left to right like Right", corr(crops[2], H) > 0.95, corr(crops[2], H))
ccw = np.rot90(H, 1); cw = np.rot90(H, -1)
check("Up is the horizontal text turned 90 degrees counterclockwise", corr(crops[0], ccw) > 0.3 and corr(crops[0], ccw) > corr(crops[0], cw) + 0.3, (corr(crops[0], ccw), corr(crops[0], cw)))
check("Down is the horizontal text turned 90 degrees clockwise", corr(crops[1], cw) > 0.2 and corr(crops[1], cw) > corr(crops[1], ccw) + 0.25, (corr(crops[1], cw), corr(crops[1], ccw)))

# ---- the text box of the Properties frame, Del, and the floating text
out = run(["newdoc A4", "registerframe x all", "addtext 40 40 Hello 3", "addtext 100 40 World 3", "selclear", "echo M0", "focusinfo",
           "selidx 0", "echo M1", "focusinfo", "editdel", "echo M2", "focusinfo", "objects", "editdel", "echo M3", "focusinfo", "objects",
           "selclear", "tool select", "selidx 0", "echo M4", "focusinfo"])
def after(out, mk, pre):
    i = out.index(mk); return [l for l in out[i + 1:] if l.startswith(pre)][:1]
f0 = after(out, "M0", "FOCUS"); f1 = after(out, "M1", "FOCUS"); f2 = after(out, "M2", "FOCUS"); f3 = after(out, "M3", "FOCUS")
check("nothing selected: no text box has the focus", f0 and "edText" not in f0[0], f0)
check("one text selected: edText has the focus with all the text selected", f1 and "FOCUS edText" in f1[0] and 'text="Hello"' in f1[0] and "selstart=0 sellen=5" in f1[0], f1)
check("Del with the text selected removes the text only", f2 and 'text=""' in f2[0] and "sel=1" in f2[0], f2)
objs = [l for l in out if l.startswith("EDITDEL")]
check("the object is still there after the first Del", objs and objs[0].endswith("objects=2"), objs)
out2 = run(["newdoc A4", "registerframe x all", "addtext 40 40 Hello 3", "selclear", "selidx 0", "editcaret 1", "editdel", "echo N1", "focusinfo",
            "editcaret 3", "editdel", "echo N2", "focusinfo", "editcaret 3", "editdel", "echo N3", "focusinfo",
            "editcaret 0 2", "editdel", "echo N4", "focusinfo", "editdel", "editdel"])
g1 = after(out2, "N1", "FOCUS"); g2 = after(out2, "N2", "FOCUS"); g3 = after(out2, "N3", "FOCUS"); g4 = after(out2, "N4", "FOCUS")
ob2 = [l for l in out2 if l.startswith("EDITDEL")]
check("Del with the caret after the H takes the e (the character to its right), by the real key path (menu shortcut first)", g1 and 'text="Hllo"' in g1[0] and ob2[0].endswith("objects=1"), (g1, ob2))
check("Del with the caret at the end of the text does nothing and keeps the object", g3 and 'text="Hll"' in g3[0] and ob2[2].endswith("objects=1"), (g2, g3, ob2))
check("Del with two characters selected removes both, the object stays", g4 and 'text="l"' in g4[0] and ob2[3].endswith("objects=1"), (g4, ob2))
check("Del with one character left and the caret before it empties the box; the next Del (empty box) deletes the object", len(ob2) == 6 and ob2[4].endswith("objects=1") and ob2[5].endswith("objects=0"), ob2)
check("Del in the empty box deletes the object", len(objs) == 2 and objs[1].endswith("objects=1"), objs)
f4 = after(out, "M4", "FOCUS")
check("selecting the remaining text focuses its box again", f4 and "FOCUS edText" in f4[0] and 'text="Hello"' not in f4[0] and "sellen=5" in f4[0], f4)
out = run(["newdoc A4", "registerframe x all", "tool select", "mouse move 60 60", "echo M0", "floatinfo", "tool text", "echo M1", "floatinfo",
           "mouse move 70 70", "echo M2", "floatinfo", "mouse down 70 70", "mouse up 70 70", "echo M3", "floatinfo", "objects", "tool select", "echo M4", "floatinfo"])
fl = lambda m: after(out, m, "FLOAT")
check("no floating text with the select tool", fl("M0") == ['FLOAT ""'], fl("M0"))
check("a floating text follows the pointer after the Text tool is chosen and the pointer moves", fl("M2") and fl("M2") != ['FLOAT ""'], fl("M2"))
check("another one follows after one is placed", fl("M3") and fl("M3") != ['FLOAT ""'], fl("M3"))
check("the floating text goes when the tool is left", fl("M4") == ['FLOAT ""'], fl("M4"))
# the floating text is drawn on the sheet: the form differs with the Text tool and the pointer over the sheet, and is as before when the tool is left
fp = lambda n: os.path.join(tmp, n)
run(["newdoc A4", "ribbontab Draw", "tool text", "formshot " + fp("f0.bmp"), "mouse move 100 100", "mouse move 101 101", "formshot " + fp("f1.bmp"),
     "tool select", "formshot " + fp("f2.bmp")])
F = [np.array(Image.open(fp("f%d.bmp" % i)).convert("RGB")).astype(int)[250:-40] for i in range(3)]      # (the sheet's part of the form: not the ribbon, not the status bar)
d01 = int((np.abs(F[0] - F[1]).sum(axis=2) > 60).sum()); d12 = int((np.abs(F[1] - F[2]).sum(axis=2) > 60).sum())
check("the Text tool shows a floating text on the sheet once the pointer is over it (%d pixels differ)" % d01, d01 > 15, d01)
check("leaving the tool takes it off again (%d pixels differ)" % d12, d12 > 15, d12)
# the Text tool's panel offers the text and the direction before anything is placed; they are used by the floating text and by the text placed; right click cancels
out = run(["newdoc A4", "registerframe x all", "tool text", "echo M0", "frameinfo tool", "frameact tool edText text ABC7", "frameact tool cbTextDirection choose 1",
           "mouse move 80 80", "echo M1", "floatinfo", "mouse down 80 80", "mouse up 80 80", "echo M2", "floatinfo", "frameinfo tool", "selidx 0", "props",
           "tool text", "mouse move 90 90", "mouse rdown 90 90", "echo M3", "floatinfo", "toolbuttons"])
def seg(mk): i = out.index(mk); return out[i + 1:]
fi = [l for l in seg("M0") if l.startswith("FRAMEINFO")][:8]
check("the Text tool's panel shows the text box", any(l.startswith("FRAMEINFO edText") and "visible=1" in l for l in fi), fi)
check("the Text tool's panel shows the direction list", any(l.startswith("FRAMEINFO cbTextDirection") and "visible=1" in l for l in fi), fi)
check("the floating text says what was typed in the tool's text box", [l for l in seg("M1") if l.startswith("FLOAT")][:1] == ['FLOAT "ABC7"'], seg("M1")[:3])
check("the next floating text is that one counted on", [l for l in seg("M2") if l.startswith("FLOAT")][:1] == ['FLOAT "ABC8"'], seg("M2")[:3])
pr = [l for l in seg("M2") if l.startswith("PROPS")]
check("the placed text has the typed text and the chosen direction", pr and "text=ABC7" in pr[0] and "dir=Down" in pr[0], pr)
check("a right click cancels the placement: no floating text, the Select tool", [l for l in seg("M3") if l.startswith("FLOAT")][:1] == ['FLOAT ""'] and any(l.startswith("TOOLBUTTONS tool=0") for l in seg("M3")), seg("M3")[:4])
g = lambda m, p: [l for l in seg(m) if l.startswith(p)][:1]
# the Label tool the same way: text, direction and type offered, floating label, counted on; Esc drops the tool when the focus is off the sheet
out = run(["newdoc A4", "registerframe x all", "tool label", "echo M0", "frameinfo tool", "frameact tool edText text NET1", "frameact tool cbTextDirection choose 2",
           "mouse move 80 80", "echo M1", "floatinfo", "mouse down 80 80", "mouse up 80 80", "echo M2", "floatinfo", "selidx 0", "props",
           "tool label", "formesc", "echo M3", "toolbuttons", "tool text", "formesc", "echo M4", "toolbuttons", "tool text", "formesc view", "echo M5", "toolbuttons"])
fi = [l for l in seg("M0") if l.startswith("FRAMEINFO")][:8]
check("the Label tool's panel shows the text box, the direction list and the type", all(any(l.startswith("FRAMEINFO " + n) and "visible=1" in l for l in fi) for n in ("edText", "cbTextDirection", "cbTextDirection1")), fi)
check("the floating label says what was typed", g("M1", "FLOAT") == ['FLOAT "NET1"'], seg("M1")[:3])
check("the next floating label is counted on", g("M2", "FLOAT") == ['FLOAT "NET2"'], seg("M2")[:3])
pr = [l for l in seg("M2") if l.startswith("PROPS")]
check("the placed label has the typed text and the chosen direction", pr and "text=NET1" in pr[0] and "dir=Left" in pr[0], pr)
check("Esc with the focus off the sheet drops the Label tool", any(l.startswith("TOOLBUTTONS tool=0") for l in seg("M3")), seg("M3")[:2])
check("Esc drops the Text tool", any(l.startswith("TOOLBUTTONS tool=0") for l in seg("M4")), seg("M4")[:2])
check("Esc with the focus on the sheet is left to the sheet", not any(l.startswith("TOOLBUTTONS tool=0") for l in seg("M5")), seg("M5")[:2])
# the font box: a font typed in it and Enter pressed is applied (not only one chosen from the list with the mouse)
out = run(["newdoc A4", "registerframe x all", "addtext 40 40 Hello 3", "selidx 0", "frameact sel cbFont enter Carlito", "echo M0", "props",
           "frameact sel cbFontSize enter 20", "echo M1", "props"])
pr = [l for l in seg("M0") if l.startswith("PROPS")]
check("Enter in the font box applies the font typed", pr and "font.face=Carlito" in pr[0], pr)
pr = [l for l in seg("M1") if l.startswith("PROPS")]
check("Enter in the font size box applies the size typed", pr and "font.height=20" in pr[0], pr)
# choosing the Text (or Label) tool puts the focus in its text box with the text selected; each keystroke there changes the floating text; after a placement the box is ready again
out = run(["newdoc A4", "registerframe x all", "ribbontab Draw", "tool text", "mouse move 80 80", "echo M0", "focusinfo", "frameact tool edText type Hi", "echo M1", "floatinfo",
           "frameact tool edText type Hi2", "echo M2", "floatinfo", "mouse down 80 80", "mouse up 80 80", "echo M3", "focusinfo", "floatinfo",
           "tool select", "tool label", "echo M4", "focusinfo", "frameact tool edText type Net", "echo M5", "floatinfo"])
check("choosing the Text tool focuses its text box with all the text selected", g("M0", "FOCUS") and "FOCUS edText" in g("M0", "FOCUS")[0] and 'text="Text"' in g("M0", "FOCUS")[0] and "selstart=0 sellen=4" in g("M0", "FOCUS")[0], g("M0", "FOCUS"))
check("the floating text follows the first change of the box", g("M1", "FLOAT") == ['FLOAT "Hi"'], g("M1", "FLOAT"))
check("and the next change", g("M2", "FLOAT") == ['FLOAT "Hi2"'], g("M2", "FLOAT"))
check("after a placement the box is focused again with the next text selected", g("M3", "FOCUS") and "FOCUS edText" in g("M3", "FOCUS")[0] and 'text="Hi3"' in g("M3", "FOCUS")[0] and "sellen=3" in g("M3", "FOCUS")[0], g("M3", "FOCUS"))
check("choosing the Label tool focuses its text box", g("M4", "FOCUS") and "FOCUS edText" in g("M4", "FOCUS")[0] and "sellen=5" in g("M4", "FOCUS")[0], g("M4", "FOCUS"))
check("the floating label follows the box too", g("M5", "FLOAT") == ['FLOAT "Net"'], g("M5", "FLOAT"))
# the user font: starts from the design's default, is taken from what is placed, and starts the next tool that has a font; a new design starts afresh
out = run(["newdoc A4", "registerframe x all", "ribbontab Draw", "userfont", "tool text", "frameact tool cbFont enter Carlito", "frameact tool cbFontSize enter 20",
           "frameact tool sbBold click", "echo M0", "userfont", "mouse move 60 60", "mouse down 60 60", "mouse up 60 60", "tool label", "echo M1", "userfont", "frameinfo tool",
           "mouse move 90 60", "mouse down 90 60", "mouse up 90 60", "selidx 1", "props", "tool power", "echo M2", "userfont", "mouse move 60 100", "mouse down 60 100", "mouse up 60 100",
           "selidx 2", "props", "tool select", "newdoc A4", "echo M3", "userfont"])
ufs = [l for l in out if l.startswith("USERFONT")]
check("a new design starts with the default font", ufs and ufs[0] == ufs[-1] and ufs[0] != ufs[1], ufs)
check("a font chosen in the Text tool's panel is the user font (Carlito, 20, bold)", g("M0", "USERFONT") == ['USERFONT Carlito|20|1|0'], g("M0", "USERFONT"))
fi = [l for l in seg("M1") if l.startswith("FRAMEINFO")]
check("the Label tool starts with it: face, size and bold", any(l.startswith("FRAMEINFO cbFontSize") and "text=20" in l for l in fi) and any(l.startswith("FRAMEINFO sbBold") and "down=1" in l for l in fi) and any(l.startswith("FRAMEINFO cbFont ") and "Carlito" in l for l in fi), fi)
pr = [l for l in seg("M1") if l.startswith("PROPS")]
check("the label placed has the font", pr and "font.face=Carlito" in pr[0] and "font.height=20" in pr[0] and "font.bold=1" in pr[0], pr)
pr = [l for l in seg("M2") if l.startswith("PROPS")]
check("the power symbol has no font of its own, and placing it leaves the user font alone", pr and "font." not in pr[0] and len(ufs) == 5 and ufs[3] == ufs[1], (pr, ufs))
check("a new design forgets it", g("M3", "USERFONT") == ufs[-1:] and ufs[-1] != 'USERFONT Carlito|20|1|0', g("M3", "USERFONT"))
# ghosts: a junction, no connect, power symbol and bus slash follow the pointer until placed
for tl in ("junction", "noconnect", "power", "busslash"):
    run(["newdoc A4", "ribbontab Draw", "tool " + tl, "formshot " + fp("g0.bmp"), "mouse move 100 100", "mouse move 101 101", "formshot " + fp("g1.bmp"), "tool select", "formshot " + fp("g2.bmp")])
    G = [np.array(Image.open(fp("g%d.bmp" % i)).convert("RGB")).astype(int)[250:-40] for i in range(3)]
    d = int((np.abs(G[1] - G[2]).sum(axis=2) > 60).sum())
    check("the %s tool shows a ghost that goes when the tool is left (%d pixels)" % (tl, d), d > 3, d)
# the Note tool shows all three panels: its text and direction as well as the font and the frame
out = run(["newdoc A4", "registerframe x all", "ribbontab Draw", "tool note", "frameinfo tool"])
fi = [l for l in out if l.startswith("FRAMEINFO")]
check("the Note tool's panel shows its text box and direction, with the font and frame editors", all(any(l.startswith("FRAMEINFO " + n + " ") and "visible=1" in l for l in fi) for n in ("edText", "cbTextDirection", "cbFont", "seFrameWidth")), fi)
# the Power tool offers its text and direction before the symbol is placed, and what is typed is what is placed; a selected power symbol is called one
out = run(["newdoc A4", "registerframe x all", "ribbontab Draw", "tool power", "frameinfo tool", "frameact tool edText type GND5", "mouse move 100 100", "mouse down 100 100", "mouse up 100 100",
           "tool select", "selidx 0", "props", "ribbontab View", "propspanel", "tool bus", "mouse move 60 60", "mouse down 60 60", "mouse up 60 60", "mouse move 90 60", "mouse down 90 60", "mouse up 90 60", "mouse rdown 90 60", "tool select", "selidx 1", "propspanel"])
fi = [l for l in out if l.startswith("FRAMEINFO")]
check("the Power tool's panel shows its text (VCC) and its direction", any(l.startswith("FRAMEINFO edText ") and "visible=1" in l for l in fi) and any(l.startswith("FRAMEINFO sbOrientation ") and "visible=1" in l for l in fi), fi)
pr = [l for l in out if l.startswith("PROPS")]
check("the symbol placed says what was typed", pr and "text=GND5" in pr[0], pr)
pp = [l for l in out if l.startswith("PROPSPANEL")]
check("a selected power symbol is named Power symbol, a bus Bus (not TDrawPower)", len(pp) == 2 and "label=[Power symbol]" in pp[0] and "label=[Bus]" in pp[1], pp)
print("label shape checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
