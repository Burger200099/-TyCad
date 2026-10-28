#!/usr/bin/env python3
"""The Select button of the Draw ribbon, the draw tool that stays pressed, the Properties panel's layout, the wire being drawn (red, and as thick as the
confirmed wire) and the selection box (drag right: what it touches; drag left: what it holds completely).
Needs xvfb-run, Pillow and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, re, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
try:
    from PIL import Image
except ImportError:
    Image = None
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or Image is None:
    print("Ribbon tool checks skipped: need xvfb-run, Pillow and the built program"); sys.exit(0)
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
def tb(l):
    return dict((k, int(v)) for k, v in re.findall(r"(\w+)=(\d+)", l))
prev, final = os.path.join(tmp, "prev.png"), os.path.join(tmp, "final.png")
def drawwire(x1, y1, x2, y2):
    return ["tool wire", "mouse move %d %d" % (x1, y1), "mouse down %d %d" % (x1, y1), "mouse move %d %d" % (x2, y2), "mouse down %d %d" % (x2, y2), "mouse rdown %d %d" % (x2, y2), "mouse rdown %d %d" % (x2, y2)]
script = ["newdoc A4", "toolbuttons",
          "tool wire", "toolbuttons", "mouse move 50 50", "mouse down 50 50", "mouse move 90 50", "shot " + prev,
          "mouse down 90 50", "mouse rdown 90 50", "toolbuttons", "mouse rdown 90 50", "shot " + final, "toolbuttons",
          "tool rect", "toolbuttons", "selectbutton draw", "toolbuttons", "selectbutton draw", "toolbuttons",
          "tool wire", "toolbuttons", "selectbutton home", "toolbuttons", "tool bus", "toolbuttons", "tool select", "toolbuttons"]
script += drawwire(20, 120, 40, 120) + drawwire(60, 120, 100, 120)
script += ["ribbontab View", "propspanel", "selectall", "propspanel", "selclear"]
boxes = [(30, 110, 70, 130), (70, 130, 30, 110), (110, 130, 10, 110), (45, 130, 15, 110), (15, 110, 45, 130), (110, 130, 50, 110), (50, 110, 110, 130)]
for (a, b, c, d) in boxes:
    script += ["mouse down %d %d" % (a, b), "mouse move %d %d" % (c, d), "mouse up %d %d" % (c, d), "sel", "selclear"]
out = run(script)
T = [tb(l) for l in out if l.startswith("TOOLBUTTONS")]
check("the script ran", len(T) >= 11 and sum(1 for l in out if l.startswith("SEL ")) == len(boxes), out[:5])
if len(T) >= 11:
    check("Select is the tool at the start and both Select buttons are pressed", T[0]["tool"] == 0 and T[0]["homeselect"] == 1 and T[0]["drawselect"] == 1 and T[0]["wire"] == 0, T[0])
    check("the Wire tool presses its button and releases both Select buttons", T[1]["tool"] == 1 and T[1]["wire"] == 1 and T[1]["homeselect"] == 0 and T[1]["drawselect"] == 0, T[1])
    check("the first right click (ending the wire) leaves the Wire tool", T[2]["tool"] == 1 and T[2]["wire"] == 1, T[2])
    check("the second right click returns to Select: both Select buttons pressed, and the Wire button released", T[3]["tool"] == 0 and T[3]["homeselect"] == 1 and T[3]["drawselect"] == 1 and T[3]["wire"] == 0, T[3])
    check("another draw tool presses its button and releases the Wire button on another panel", T[4]["tool"] == 4 and T[4]["rect"] == 1 and T[4]["wire"] == 0 and T[4]["drawselect"] == 0, T[4])
    check("a click on the Draw ribbon's Select button returns to Select and releases the tool's button", T[5]["tool"] == 0 and T[5]["drawselect"] == 1 and T[5]["homeselect"] == 1 and T[5]["rect"] == 0, T[5])
    check("a second click on it keeps it pressed", T[6]["tool"] == 0 and T[6]["drawselect"] == 1 and T[6]["rect"] == 0, T[6])
    check("Wire again: its button pressed, the Rectangle released", T[7]["wire"] == 1 and T[7]["rect"] == 0 and T[7]["drawselect"] == 0, T[7])
    check("the Home ribbon's Select button also returns to Select and releases the Wire button", T[8]["tool"] == 0 and T[8]["homeselect"] == 1 and T[8]["drawselect"] == 1 and T[8]["wire"] == 0, T[8])
    check("the Bus tool presses its button and releases the Wire button", T[9]["bus"] == 1 and T[9]["wire"] == 0, T[9])
    check("the select tool leaves no draw button pressed", T[10]["tool"] == 0 and T[10]["bus"] == 0 and T[10]["wire"] == 0 and T[10]["rect"] == 0 and T[10]["drawselect"] == 1, T[10])
# the wire being drawn: red, as thick as the confirmed one
def count(path, rgb):
    im = Image.open(path).convert("RGB"); px = im.load(); W, H = im.size
    return sum(1 for x in range(W) for y in range(H) if px[x, y] == rgb)
if os.path.exists(prev) and os.path.exists(final):
    pr, pb, fr, fb = count(prev, (255, 0, 0)), count(prev, (0, 0, 255)), count(final, (255, 0, 0)), count(final, (0, 0, 255))
    check("while it is drawn the wire is red and not blue", pr > 20 and pb == 0, (pr, pb))
    check("once confirmed it is blue and not red", fb > 20 and fr == 0, (fr, fb))
    check("the wire does not change size when it is confirmed", fb == pr, (pr, fb))
else:
    check("the pictures were made", False)
# the Properties panel
lines = [l for l in out if l.startswith("PROPSPANEL") or l.startswith("PROPCTL")]
heads = [i for i, l in enumerate(lines) if l.startswith("PROPSPANEL")]
if len(heads) == 2:
    h0 = dict(re.findall(r"(\w+)=(\[[^\]]*\]|\S+)", lines[heads[0]])); h1 = dict(re.findall(r"(\w+)=(\[[^\]]*\]|\S+)", lines[heads[1]]))
    check("with nothing selected the label says so and the panel is as wide as the text needs", h0["label"] == "[Nothing selected]" and int(h0["controls"]) == 0 and int(h0["width"]) > 100, h0)
    check("the label at the foot is as wide as the panel (inside its border)", abs(int(h1["labelwidth"]) - int(h1["width"])) <= 4, h1)
    ctl = [[int(x) for x in l.split()[2:7]] + [l.split()[1]] for l in lines[heads[1] + 1:]]
    check("a selection shows its properties in the panel, two to a column", int(h1["controls"]) == len(ctl) and len(ctl) >= 4 and len(ctl) % 2 == 0, h1)
    caps = ctl[0::2]; eds = ctl[1::2]
    check("the first caption starts 5 pixels from the left", caps[0][0] == 5, caps[0])
    # rows: row one is 36 high from 5 (centre 23), row two from 56 (centre 74); a control shorter than the row is centred on it
    ok = True; why = []
    for k, c in enumerate(ctl):
        centre = c[1] + c[3] / 2.0; want = 23 if (k // 2) % 2 == 0 else 74
        if abs(centre - want) > 1.5: ok = False; why.append((k, c, want))
    check("every control is centred on its row (23 and 74)", ok, why)
    ok = True
    for k in range(2, len(caps), 2):
        right = max(caps[k - 2][4], eds[k - 2][4], caps[k - 1][4], eds[k - 1][4])
        if caps[k][0] - right != 20: ok = False; why.append((k, right, caps[k][0]))
    check("20 pixels between one column and the next", ok, why)
    right_end = max(c[4] for c in ctl)
    check("the panel is as wide as all its controls plus 5 on each side (and its border)", abs(int(h1["width"]) - (right_end + 5)) <= 4 and int(h1["width"]) > int(h0["width"]), (h1["width"], right_end))
else:
    check("the panel was described twice", False, lines)
# the selection box
S = [l for l in out if l.startswith("SEL ")]
def n(l): return int(l.split()[1])
if len(S) == len(boxes):
    want = [2, 0, 2, 1, 1, 1, 1]
    names = ["right: both wires touched", "left over both: neither is held completely", "left over both with room: both held", "left round the first wire: only it", "right round the first wire", "left round the second wire only (50..110): the second", "right: the second is touched, the first is not"]
    for i in range(len(boxes)):
        check("drag %d (%s): %d selected" % (i, names[i], want[i]), n(S[i]) == want[i], S[i])
# the grid dots grow with the zoom: as many pixels wide as the zoom is whole hundreds of per cent (rounded), one at 100% and below
gs = ["newdoc A4", "zoompercent", "shot " + os.path.join(tmp, "g0.png")]
for k in range(1, 4):
    gs += ["zoom %s" % ("4" if k == 1 else "2"), "zoompercent", "shot " + os.path.join(tmp, "g%d.png" % k)]
go = run(gs)
zp = [int(l.split()[1]) for l in go if l.startswith("ZOOMPERCENT")]
def longest_run(path):
    im = Image.open(path).convert("RGB"); px = im.load(); W, H = im.size; best = 0
    for y in range(H):
        run = 0
        for x in range(W):
            if px[x, y] == (0xB0, 0xB0, 0xB0):
                run += 1; best = max(best, run)
            else: run = 0
    return best
if len(zp) == 4:
    for k in range(1, 4):
        got = longest_run(os.path.join(tmp, "g%d.png" % k))
        check("grid dots at %d%% zoom are %d pixels wide (%d)" % (zp[k], max(1, int(round(zp[k] / 100.0))), got), got == max(1, int(round(zp[k] / 100.0))), (zp, got))
    check("the dots get bigger as the zoom grows", longest_run(os.path.join(tmp, "g1.png")) < longest_run(os.path.join(tmp, "g2.png")) < longest_run(os.path.join(tmp, "g3.png")))
else:
    check("the zoom steps ran", False, go[:6])
# the tool's Properties panel on the Draw ribbon, and what it chooses for the wires drawn
tp = ["newdoc A4", "ribbontab Draw", "toolpanel", "tool wire", "toolpanel", "toolprop line.style Dash", "toolprop line.width 3", "toolprop nothing x", "toolpanel",
      "tool rect", "toolpanel", "tool select", "toolpanel", "tool junction", "toolpanel", "tool wire", "toolpanel"] + drawwire(130, 105, 170, 105) + ["objects", "selectclass TDrawLine", "props", "selclear", "tool rect", "mouse down 20 20", "mouse move 60 50", "mouse up 60 50", "tool select", "selectclass TDrawSquare", "props"]
to = run(tp)
panels = [l for l in to if l.startswith("TOOLPANEL")]
check("the tool panel script ran", len(panels) == 7, panels)
if len(panels) == 7:
    check("no panel while Select is the tool", panels[0] == "TOOLPANEL none" and panels[4] == "TOOLPANEL none", (panels[0], panels[4]))
    d = dict(re.findall(r"(\w+)=(\[[^\]]*\]|\S+)", panels[1]))
    check("a draw tool makes a separator (2 wide, aligned left, no caption) after the last panel of the sheet", d["sepwidth"] == "2" and d["sepalign"] == "3" and d["sepcaption"] == "[]" and int(d["sepleft"]) >= int(d["ladderright"]), d)
    check("then a panel with no caption, aligned left, no bevel, with a label aligned to the bottom, centred, captioned Properties", d["panelalign"] == "3" and d["bevel"] == "0" and d["caption"] == "[]" and d["label"] == "[Properties]" and d["labelalign"] == "2" and d["labelalignment"] == "2" and d["parent"] == "FTabDraw" and int(d["left"]) == int(d["sepleft"]) + 2, d)
    check("a wire has editors for its line colour, width and style, and the angle", d["editors"] == "4", d)
    check("the Rectangle tool has editors for line and fill (5)", "editors=5 " in panels[3] and "tool=4" in panels[3], panels[3])
    check("a tool with nothing to choose (Junction) has no panel", panels[5] == "TOOLPANEL none", panels[5])
    check("the panel comes back for the next draw tool", "tool=1" in panels[6], panels[6])
tc = [l for l in to if l.startswith("TOOLCTL")][:3]
if len(tc) == 3:
    c = [l.split()[1:] for l in tc]
    check("the rows of editors are centred on 23 and 74", all(abs(int(x[3]) + int(x[5]) / 2.0 - w) <= 1.5 for x, w in zip(c, (23, 74, 23))), tc)
tpr = [l for l in to if l.startswith("TOOLPROP")]
check("choosing in the panel is accepted, and a property it has not got is refused", [l.split()[-1] for l in tpr] == ["1", "1", "0"], tpr)
ow = [l for l in to if l.startswith("OBJ wire")]
pr = [l for l in to if l.startswith("PROPS ")]
check("the wire drawn afterwards has the colour set by hand (not the default style), the width and the style chosen", len(ow) == 1 and "default=0" in ow[0] and len(pr) == 2 and "line.width=3" in pr[0] and "line.style=Dash" in pr[0], (ow, pr))
check("the rectangle drawn after it has the line choices made for it (none): no dash", len(pr) == 2 and "line.style=Dash" not in pr[1] and "line.width=3" not in pr[1], pr)
# a dashed wire stays dashed at every zoom (a pen wider than a pixel cannot be dashed by the system: the painter does it; the width is 2 because a pen of width 1 stays one pixel at every zoom, as in TinyCAD)
ds = ["newdoc A4", "ribbontab Draw", "tool wire", "toolprop line.style Dash", "toolprop line.width 2"] + drawwire(130, 105, 170, 105) + ["tool wire"]
for k in range(1, 4):
    ds += ["zoom 2", "zoompercent", "shot " + os.path.join(tmp, "d%d.png" % k)]
do = run(ds)
dz = [int(l.split()[1]) for l in do if l.startswith("ZOOMPERCENT")]
def blue_runs(path):
    im = Image.open(path).convert("RGB"); px = im.load(); W, H = im.size
    rows = [y for y in range(H) if any(px[x, y] == (0, 0, 255) for x in range(W))]
    if not rows: return 0, 0
    y = rows[len(rows) // 2]; line = [px[x, y] == (0, 0, 255) for x in range(W)]
    return sum(1 for i in range(1, W) if line[i] and not line[i - 1]), len(rows)
if len(dz) == 3:
    for k in range(3):
        runs, th = blue_runs(os.path.join(tmp, "d%d.png" % (k + 1)))
        check("a dashed wire at %d%% zoom (%d pixels thick) is still dashed (%d dashes)" % (dz[k], th, runs), runs >= 8, (dz, runs, th))
    check("it was thick enough to need the painter's dashes at the last two", blue_runs(os.path.join(tmp, "d3.png"))[1] >= 3)
else:
    check("the zoom steps for the dashes ran", False, do[:5])
# a list of line styles (dash, dot, dash-dot, dash-dot-dot) is painted with the pictures of ilListBoxImages (image N for item N: Solid is image 0)
ls = run(["newdoc A4", "ribbontab Draw", "tool wire", "toolprop line.style Dot", "linestylecombos", "linestyleitems", "tool rect", "linestylecombos", "tool junction", "linestylecombos"])
cb = [l for l in ls if l.startswith("LSCOMBOS")]
check("the line style drop-downs of the wire and rectangle tools are owner-drawn with 28 pixel items; a tool without one has none", len(cb) == 3 and all("style=3 itemheight=28 ownerdraw=1" in c and "images=5 imgw=115" in c for c in cb[:2]) and cb[2].endswith("none"), cb)
it = [[int(x) for x in l.split()[2:]] for l in ls if l.startswith("LSITEM")]
if len(it) == 5:
    check("each of the five items paints something wide (a line about 115 pixels across)", all(i[2] - i[1] >= 100 for i in it), it)
    check("the four dashed styles have pictures of their own (different amounts of ink) and Solid is its own line", len(set(i[0] for i in it)) == 5, it)
    check("Solid is a continuous line (about 115 wide and 2 thick)", it[0][0] >= 200, it[0])
else:
    check("the five items were painted", False, ls[:6])
# the line colour, width and style are labelled Color:, Width: and Style: (not Line color: ...); the colour is a TColorButton
cp = run(["newdoc A4", "ribbontab Draw", "tool wire", "toolpanel", "toolprop line.color 00FF00"] + drawwire(20, 120, 60, 120) + ["selectall", "propspanel", "selclear"])
tpl = [l for l in cp if l.startswith("TOOLPANEL")]
check("the wire tool's captions are Color:, Width:, Style: and Angle:", len(tpl) == 1 and "captions=[Color:|Width:|Style:|Angle:]" in tpl[0], tpl)
tcl = [l.split() for l in cp if l.startswith("TOOLCTL")]
check("the tool's colour editor is a TColorButton", len(tcl) >= 1 and tcl[0][1] == "line.color" and tcl[0][2] == "TColorButton", tcl)
pcl = [l for l in cp if l.startswith("PROPCTL")]
check("the selection's Properties panel has the same captions and a TColorButton", any("TLabel" in l and "[Color:]" in l for l in pcl) and any("[Width:]" in l for l in pcl) and any("[Style:]" in l for l in pcl)
      and any("TColorButton" in l for l in pcl) and not any("[Line " in l for l in pcl), pcl)
# whole numbers get a TSpinEdit and fractional ones a TFloatSpinEdit (60 wide); text boxes stay TEdit (134 wide)
ne = run(["newdoc A4", "ribbontab Draw", "tool wire", "toolpanel", "tool cloud", "toolpanel", "tool text", "toolpanel"])
kinds = {}
for l in ne:
    if l.startswith("TOOLCTL"):
        f = l.split(); kinds[f[1]] = (f[2], int(f[5]), int(f[6]))
check("line.width is a TSpinEdit 60 wide", kinds.get("line.width", ("", 0, 0))[:2] == ("TSpinEdit", 60), kinds)
check("a fractional property (cloud scallop) is a TFloatSpinEdit 60 x 28", kinds.get("cloud.bump", ("", 0, 0))[:2] == ("TFloatSpinEdit", 60), kinds)
check("a text property stays a TEdit (134 wide)", any(v[0] == "TEdit" and v[1] == 134 for v in kinds.values()), kinds)
check("the font size is a TSpinEdit", kinds.get("font.height", ("",))[0] == "TSpinEdit", kinds)
def width_after(*cmds):
    o = run(["newdoc A4", "ribbontab Draw", "tool wire"] + list(cmds) + drawwire(20, 120, 60, 120) + ["selectclass TDrawLine", "props"])
    pr = [l for l in o if l.startswith("PROPS ")]
    m = re.search(r"line\.width=(\d+)", pr[0]) if pr else None
    return int(m.group(1)) if m else None
w0 = width_after()
check("Enter in the tool's number box applies the value", width_after("typenumber tool line.width 4 done") == 4, width_after("typenumber tool line.width 4 done"))
check("a change not yet finished is not applied at once", width_after("typenumber tool line.width 7") == w0, (w0, width_after("typenumber tool line.width 7")))
check("... but is applied after the pause", width_after("typenumber tool line.width 6", "sleep 1000") == 6)
sel = run(["newdoc A4"] + drawwire(20, 120, 60, 120) + ["selectall", "typenumber sel line.width 5 done", "props", "typenumber sel line.width 2", "sleep 1000", "props"])
sp = [l for l in sel if l.startswith("PROPS ")]
check("the selection's number box applies on Enter and after the pause", len(sp) == 2 and "line.width=5" in sp[0] and "line.width=2" in sp[1], sp)
# selecting brings the View tab (the Properties panel is on it) forward; deselecting puts back the tab that was showing
tabs = run(["newdoc A4", "ribbontab Draw"] + drawwire(20, 120, 60, 120) + [
    "ribbonclick Draw", "selectall", "ribbonstate", "selclear", "ribbonstate",
    "ribbonclick View", "selectall", "ribbonstate", "selclear", "ribbonstate",
    "ribbonclick Home", "selectall", "ribbonstate", "ribbonclick Draw", "selclear", "ribbonstate",
    "ribbonclick View", "selectall", "ribbonstate", "selclear", "ribbonstate",
    "ribbonclick Home", "selectall", "ribbonstate", "selclear", "ribbonstate", "selectall", "ribbonstate", "selclear", "ribbonstate",
    "ribbonclick Home", "selectall", "ribbonclick Draw", "ribbonclick View", "selclear", "ribbonstate"])
rs = [re.search(r"tab=(\w+)", l).group(1) for l in tabs if l.startswith("RIBBONSTATE")]
want = ["View", "Draw", "View", "View", "View", "Draw", "View", "View", "View", "Home", "View", "Home", "View"]
check("selecting shows the View tab (which holds the Properties panel); deselecting returns to the tab that was showing (Draw, Home), not after the person chose another tab (Draw stays), and View stays when the person was on it", rs == want[:len(rs)] and len(rs) == len(want), (rs, want))
shutil.rmtree(tmp, ignore_errors=True)
print("ribbon tools: %d checks, %d failed" % (checks, len(fails)))
if fails: sys.exit(1)
