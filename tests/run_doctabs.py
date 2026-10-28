#!/usr/bin/env python3
"""The strip of document tabs (UDocTabs.TDocTabStrip, drawn by the program): a tab for each open document, a close glyph on the right of each (picture 0 of frmSharedControls.ilDocTabs), the glyph with
the pointer over it (picture 1), the unsaved-changes mark (picture 2) in its place until the pointer is over the tab. A click on a tab makes it current; button down and up on the glyph closes it, down
on the glyph and up anywhere else does not; a middle click closes the tab it is on; a right click makes a tab current. Too many tabs make two scroll arrows appear and the tabs scroll (wheel, arrows,
and the current tab is always brought into view). The mouse is worked by script (doctab move/down/up/wheel, x and y in the strip) so the real program is clicked at real positions; the strip's picture
is saved (doctab shot) and read here.
Oracles: the layout arithmetic written down here again from the rules above (tabs side by side from the left, each DocTabHeight (24) high on the bottom of the strip, the glyph square 18 x 18 centred up
and down and 6 from the tab's right edge, widths between 70 and 220); the documents' own list (docs) for what a click did; the pixels of the saved pictures (the glyph square against the others, the
pressed glyph one pixel down and right of the hover one)."""
import os, re, shutil, subprocess, sys, tempfile
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Document tab checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:500])
n_run = [0]
def run(script):
    n_run[0] += 1
    h = os.path.join(tmp, "h%d" % n_run[0]); os.makedirs(h)
    sp = os.path.join(tmp, "s%d.txt" % n_run[0]); open(sp, "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=180,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return [l for l in r.stdout.split("\n")]
def tabs(lines):
    out = []
    for l in lines:
        if not l.startswith("DOCTABS "): continue
        d = {}
        d["w"] = int(re.search(r" w=(\d+)", l).group(1)); d["h"] = int(re.search(r" h=(\d+)", l).group(1))
        d["count"] = int(re.search(r"count=(\d+)", l).group(1)); d["current"] = int(re.search(r"current=(-?\d+)", l).group(1))
        d["names"] = [x for x in re.search(r"names=(.*?) modified=", l).group(1).split("|") if x]
        d["modified"] = [int(x) for x in re.search(r"modified=([\d,]*)", l).group(1).split(",") if x]
        d["glyphs"] = [int(x) for x in re.search(r"glyphs=([\d,]*)", l).group(1).split(",") if x]
        rc = lambda key: [tuple(int(v) for v in x.split(":")) for x in re.search(key + r"=([-\d:;]*)", l).group(1).split(";") if x]
        d["rects"] = rc("rects"); d["closes"] = rc("closes")
        for k in ("arrows", "scroll", "total", "hot", "hotclose", "pressed"):
            d[k] = int(re.search(r" %s=(-?\d+)" % k, l).group(1))
        d["visible"] = int(re.search(r"visible=(\d)", l).group(1))
        out.append(d)
    return out
def docs(lines):
    out = []
    for l in lines:
        if l.startswith("DOCS "):
            out.append((int(l.split()[1]), int(l.split("current=")[1].split()[0]), [x for x in l.split("list=")[1].split("|") if x]))
    return out
SETUP = "newdoc A4\nnewdoc A4\nnewdoc A4\ngotodoc 1\ntool wire\nmouse down 20 20\nmouse down 60 20\nmouse rdown 60 20\ngotodoc 0\n"   # three documents, the second has unsaved changes, the first is current
def cx(r): return (r[0] + r[2]) // 2
def cy(r): return (r[1] + r[3]) // 2
# ---- 1. layout
L = run(SETUP + "doctabs\n")
T = tabs(L); R = T[0]
check("a strip of 3 tabs, shown, the first current, names and the unsaved flag of the second", R["visible"] == 1 and R["count"] == 3 and R["current"] == 0 and R["names"] == ["Untitled 1", "Untitled 2", "Untitled 3"] and R["modified"] == [0, 1, 0], R)
check("the pictures: 3 of 18 x 18, linked to frmSharedControls.ilDocTabs", any("images=3 size=18x18 linked=1" in l for l in L), [l for l in L if "DOCTABIMAGES" in l])
check("tabs stand side by side from x=0, each 24 high on the bottom of the strip", R["rects"][0][0] == 0 and all(R["rects"][i][2] == R["rects"][i + 1][0] for i in range(2)) and all(r[3] == R["h"] and r[3] - r[1] == 24 for r in R["rects"]), R["rects"])
check("each tab is 70 to 220 wide and the total is the sum of them", all(70 <= r[2] - r[0] <= 220 for r in R["rects"]) and R["total"] == sum(r[2] - r[0] for r in R["rects"]), (R["rects"], R["total"]))
ok = True
for t, c in zip(R["rects"], R["closes"]):
    ok = ok and c[2] - c[0] == 18 and c[3] - c[1] == 18 and c[2] == t[2] - 6 and c[1] - t[1] == (24 - 18) // 2
check("the close glyph is 18 x 18, 6 from the tab's right edge, centred up and down", ok, list(zip(R["rects"], R["closes"])))
check("no arrows while everything fits", R["arrows"] == 0 and R["scroll"] == 0)
check("the glyphs shown: the close glyph (0) on the others, the unsaved mark (2) on the modified one", R["glyphs"] == [0, 2, 0], R["glyphs"])
H = R["h"]; Y = R["rects"][0][1] + 12                 # a y inside the tabs
body = [(r[0] + 12, Y) for r in R["rects"]]; clo = [(cx(c), cy(c)) for c in R["closes"]]
# ---- 2. hover
L = run(SETUP + "doctab move %d %d\ndoctabs\ndoctab move %d %d\ndoctabs\ndoctab move %d %d\ndoctabs\ndoctab move %d %d\ndoctabs\ndoctab move %d %d\ndoctabs\n" %
        (body[0] + body[1] + clo[1] + (5, 0) + clo[2]))
a, b, c, d, e = tabs(L)
check("pointer on the body of tab 0: it is the hot tab, not on the glyph, glyphs unchanged", (a["hot"], a["hotclose"], a["glyphs"]) == (0, 0, [0, 2, 0]), a)
check("pointer on the body of the modified tab: its mark gives way to the close glyph (0)", (b["hot"], b["hotclose"], b["glyphs"]) == (1, 0, [0, 0, 0]), b)
check("pointer on the glyph of the modified tab: the pointer-over picture (1)", (c["hot"], c["hotclose"], c["glyphs"]) == (1, 1, [0, 1, 0]), c)
check("pointer in the gap above the tabs: nothing is hot, the mark is back", (d["hot"], d["hotclose"], d["glyphs"]) == (-1, 0, [0, 2, 0]), d)
check("pointer on the glyph of the last tab", (e["hot"], e["hotclose"], e["glyphs"]) == (2, 1, [0, 2, 1]), e)
# ---- 3. clicking
L = run(SETUP + "doctab down %d %d\ndoctab up %d %d\ndocs\ndoctab down %d %d\ndoctab up %d %d\ndocs\ndoctab down %d %d\ndoctab up %d %d\ndocs\ndoctabs\n" % (body[2] + body[2] + body[1] + body[1] + body[0] + body[0]))
D = docs(L)
check("clicking the body of a tab makes its document current (the click on tab 2, then 1, then 0)", [x[1] for x in D] == [2, 1, 0] and all(x[0] == 3 for x in D), D)
check("the strip shows the same tab as current", tabs(L)[-1]["current"] == 0)
L = run(SETUP + "doctab down %d %d\ndoctabs\ndoctab move %d %d\ndoctabs\ndoctab move %d %d\ndoctabs\ndoctab move %d %d\ndoctab up %d %d\ndoctabs\ndocs\n" % (clo[2] + body[2] + clo[2] + (5, 0) + (5, 0)))
a, m1, m2, b = tabs(L)
check("button down on a glyph holds it pressed (picture 1) and does not change the current tab", a["pressed"] == 2 and a["glyphs"][2] == 1 and a["current"] == 0, a)
check("moving off the glyph (onto the tab) with the button still held: the glyph is the plain one again (0), the press is still remembered", m1["glyphs"][2] == 0 and m1["hotclose"] == 0 and m1["pressed"] == 2, m1)
check("moving back onto the glyph with the button still held: pressed again (1)", m2["glyphs"][2] == 1 and m2["hotclose"] == 1, m2)
L2 = run(SETUP + "doctab down %d %d\ndoctabs\ndoctab move %d %d\ndoctabs\ndoctab move %d %d\ndoctabs\ndoctab up %d %d\ndoctabs\ndocs\n" % (clo[1] + (5, 0) + clo[1] + (5, 0)))
a2, o1, o2, o3 = tabs(L2)
check("a modified tab: pressed on its glyph (1); moved right off the tab with the button held it shows its unsaved mark (2) again, not the pressed glyph", a2["glyphs"][1] == 1 and o1["glyphs"][1] == 2 and o1["hot"] == -1 and o1["pressed"] == 1, (a2["glyphs"], o1["glyphs"], o1["hot"]))
check("... and back on the glyph it is pressed again (1); let go off it, the press is dropped and nothing is closed (a modified document would ask first, which a script cannot answer)", o2["glyphs"][1] == 1 and o3["pressed"] == -1 and o3["count"] == 3, (o2["glyphs"], o3))
check("let go elsewhere: nothing is closed and the press is dropped", b["pressed"] == -1 and b["count"] == 3 and docs(L)[0][0] == 3, (b, docs(L)))
L = run(SETUP + "doctab down %d %d\ndoctab up %d %d\ndocs\ndoctab down %d %d\ndoctab up %d %d\ndocs\ndoctabs\n" % (clo[2] + clo[0] + clo[2] + clo[2]))
D = docs(L)
check("down on a glyph and up on the glyph of another tab closes nothing", D[0][0] == 3, D)
check("down and up on the glyph of the last tab closes that document (the others stay, in order)", D[1][0] == 2 and D[1][2] == ["Untitled 1", "Untitled 2 *"] and tabs(L)[-1]["count"] == 2 and tabs(L)[-1]["names"] == ["Untitled 1", "Untitled 2"], (D, tabs(L)[-1]))
L = run(SETUP + "doctab down %d %d m\ndoctab up %d %d m\ndocs\ndoctab down %d %d m\ndoctab up %d %d m\ndocs\n" % (body[0] + body[1] + body[0] + body[0]))
D = docs(L)
check("a middle click down on one tab and up on another closes nothing", D[0][0] == 3, D)
check("a middle click on a tab closes its document", D[1][0] == 2 and D[1][2] == ["Untitled 2 *", "Untitled 3"], D)
L = run(SETUP + "doctab down %d %d r\ndoctab up %d %d r\ndocs\n" % (body[2] + body[2]))
D = docs(L)
check("a right click on a tab makes its document current and closes nothing", D[0] == (3, 2, ["Untitled 1", "Untitled 2 *", "Untitled 3"]), D)
L = run(SETUP + "doctab down 5 0\ndoctab up 5 0\ndoctab down %d %d\ndoctab up %d %d\ndocs\n" % ((R["w"] - 5, Y) * 2))
check("a click in the gap above the tabs or on the empty strip to the right of them does nothing", docs(L)[0] == (3, 0, ["Untitled 1", "Untitled 2 *", "Untitled 3"]), docs(L))
# ---- 4. too many tabs
N = 16
L = run("".join("newdoc A4\n" for _ in range(N)) + "doctabs\ngotodoc 0\ndoctabs\ngotodoc %d\ndoctabs\ndoctab wheel 1\ndoctabs\ndoctab wheel -1\ndoctabs\ndoctab wheel -1\ndoctabs\n" % (N - 1))
a, b, c, d, e, f = tabs(L)
W = a["w"]; room = W - 40
check("16 tabs are wider than the strip: the arrows show, 16 tabs listed", a["count"] == N and a["arrows"] == 1 and a["total"] > W, a)
check("the newest document's tab is current and wholly in view (left of the arrows)", a["current"] == N - 1 and a["rects"][-1][2] <= room and a["rects"][-1][0] >= 0, a["rects"][-1])
check("going to the first document scrolls back: its tab starts at 0", b["current"] == 0 and b["scroll"] == 0 and b["rects"][0][0] == 0, b)
check("going to the last one scrolls so that its tab ends at the arrows", c["scroll"] == c["total"] - room and c["rects"][-1][2] == room, (c["scroll"], c["total"], room, c["rects"][-1]))
check("a turn of the wheel one way scrolls the tabs back by 90 pixels", d["scroll"] == max(0, c["scroll"] - 90), (c["scroll"], d["scroll"]))
check("a turn the other way scrolls them on by 90, never past the end", e["scroll"] == min(c["total"] - room, d["scroll"] + 90), (d["scroll"], e["scroll"]))
check("the scroll stays within 0 and total - room", all(0 <= x["scroll"] <= x["total"] - room for x in (a, b, c, d, e, f)), [x["scroll"] for x in (a, b, c, d, e, f)])
L = run("".join("newdoc A4\n" for _ in range(N)) + "gotodoc 0\ndoctabs\ndoctab down %d %d\ndoctab up %d %d\ndoctabs\ndoctab down %d %d\ndoctab up %d %d\ndoctabs\ndoctab down %d %d\ndocs\n" %
        (W - 10, H - 8, W - 10, H - 8, W - 30, H - 8, W - 30, H - 8, W - 10, H - 8))
a, b, c = tabs(L)
check("the right arrow scrolls the tabs on by 90, the left one back by 90", b["scroll"] == min(b["total"] - room, 90) and c["scroll"] == max(0, b["scroll"] - 90), (a["scroll"], b["scroll"], c["scroll"]))
check("clicking an arrow does not change the current tab", docs(L)[0][1] == 0 and c["current"] == 0, docs(L))
# ---- 5. pictures
P = lambda n: os.path.join(tmp, n)
L = run(SETUP + "doctab move 5 0\ndoctab shot %s\ndoctab move %d %d\ndoctab shot %s\ndoctab move %d %d\ndoctab shot %s\ndoctab down %d %d\ndoctab shot %s\ndoctab move %d %d\ndoctab shot %s\n" %
        ((P("a.png"),) + body[0] + (P("b.png"),) + clo[0] + (P("c.png"),) + clo[0] + (P("d.png"),) + body[1] + (P("e.png"),)))
im = {k: Image.open(P(k + ".png")).convert("RGB") for k in "abcde"}
def region(img, r): return [[img.getpixel((x, y)) for x in range(r[0], r[2])] for y in range(r[1], r[3])]
def lum(p): return (p[0] * 299 + p[1] * 587 + p[2] * 114) // 1000
g0, g1 = R["closes"][0], R["closes"][1]
check("the pictures are as wide and high as the strip", im["a"].size == (R["w"], R["h"]), im["a"].size)
check("tab 0's glyph square: the pointer-over picture (c) is not the plain one (a)", region(im["c"], g0) != region(im["a"], g0))
check("the glyph square of the pressed glyph (d) is the pointer-over picture (c) moved one pixel down and right",
      all(region(im["d"], g0)[y + 1][x + 1] == region(im["c"], g0)[y][x] for y in range(0, 16) for x in range(0, 16)), None)
check("the unsaved mark of tab 1 (a) is not the close glyph it gives way to when the pointer is on the tab (e)", region(im["a"], g1) != region(im["e"], g1))
check("the glyph pictures draw something in the glyph square: pixels differ from the tab's own colour", len({p for row in region(im["a"], g0) for p in row}) > 1 and len({p for row in region(im["a"], g1) for p in row}) > 1)
cur = R["rects"][0]; oth = R["rects"][2]
curbody = im["a"].getpixel((cur[0] + 4, cur[1] + 12)); othbody = im["a"].getpixel((oth[0] + 4, oth[1] + 12)); face = im["a"].getpixel((R["w"] - 5, R["h"] // 2))
check("the current tab is lighter than the others and than the strip behind", lum(curbody) > lum(othbody) and lum(curbody) > lum(face), (curbody, othbody, face))
check("the current tab has a line along its top that the others do not (a different colour from its body)", im["a"].getpixel((cur[0] + 4, cur[1] + 1)) != curbody and im["a"].getpixel((oth[0] + 4, oth[1] + 1)) == othbody, (im["a"].getpixel((cur[0] + 4, cur[1] + 1)), curbody, othbody))
check("the current tab is open at the bottom (its colour runs to the last row), the others have a line under them",
      lum(im["a"].getpixel((cur[0] + 4, R["h"] - 1))) > lum(im["a"].getpixel((oth[0] + 4, R["h"] - 1))), (im["a"].getpixel((cur[0] + 4, R["h"] - 1)), im["a"].getpixel((oth[0] + 4, R["h"] - 1))))
check("the tab under the pointer (b, tab 0 is current so use tab 1 in e) has a different colour from the same tab with no pointer on it", im["e"].getpixel((R["rects"][1][0] + 4, R["rects"][1][1] + 12)) != im["a"].getpixel((R["rects"][1][0] + 4, R["rects"][1][1] + 12)))
print("Document tab checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
