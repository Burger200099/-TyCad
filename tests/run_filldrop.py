#!/usr/bin/env python3
"""The Fill button of the Rectangle / Circle panel (the check box, type list and color button became one button), and the menu that drops down from it.
Oracles: the picture on the button is counted pixel by pixel (a 32 x 32 box, 1 pixel black outline, the pattern in the color) against numbers worked out from the
geometry (30 x 30 inside; a line every 4th row/column; every 4th diagonal), the menu's items are checked against their captions' fill styles (Vertical is
the third item, the fourth in the property list), and the objects' properties are read back with `props`.
Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, re, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Fill button checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name); print("  FAIL", name, str(detail)[:600])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env)
    return r.stdout.splitlines()
def after(out, mk, key):
    i = out.index(mk); return [l for l in out[i + 1:] if l.startswith(key)]
def kv(line):
    return dict(re.findall(r'(\w+)=(\S+)', line))
CH = ["None", "Solid", "Horizontal", "Vertical", "Backward diagonal", "Forward diagonal", "Cross", "Diagonal cross"]
# the ink of each pattern inside the 30 x 30 box, worked out by counting rows / columns / diagonals of a 1-based grid (corner = 0)
def ink(c):
    n = 0
    for v in range(1, 31):
        for u in range(1, 31):
            d = (u - v) % 4 == 0; f = (u + v) % 4 == 0; h = v % 4 == 2; vt = u % 4 == 2
            n += {0: False, 1: True, 2: h, 3: vt, 4: d, 5: f, 6: h or vt, 7: d or f}[c]
    return n
check("the numbers: a row every 4th, 8 rows of 30", ink(2) == 240 and ink(3) == 240 and ink(1) == 900 and ink(0) == 0 and ink(6) == 240 + 240 - 64, [ink(i) for i in range(8)])
S = ["newdoc A4", "registerframe x all", "ribbontab Draw", "tool rect", "echo P0", "frameinfo tool", "frameglyph tool sbFill"]
for c in range(8):
    S += ["frameact tool sbFill pick %d 0000FF" % c, "echo G%d" % c, "frameglyph tool sbFill", "props"]
out = run(S)
fi = [l for l in after(out, "P0", "FRAMEINFO")]
names = {l.split()[1]: l for l in fi if len(l.split()) > 2}
check("the rectangle tool has the Fill button", "sbFill" in names and "visible=1" in names["sbFill"] and "fill.type" in names["sbFill"], fi)
check("the check box, type list and color button are gone", not any(n in names for n in ("cbFill", "cbFillType", "cbFillColor")), list(names))
g0 = kv(after(out, "P0", "FRAMEGLYPH")[0])
check("the picture is 32 x 32 with a 1 pixel black outline (124 pixels)", g0["size"] == "32x32" and g0["black"] == "124", g0)
for c in range(8):
    g = kv(after(out, "G%d" % c, "FRAMEGLYPH")[0])
    check("tool fill %s: pattern pixels %d in the color, outline 124" % (CH[c], ink(c)), g["ink"] == str(ink(c)) and g["black"] == "124" and g["white"] == str(900 - ink(c)) and (c == 0 or g["inkcolor"].upper().endswith("0000FF") or g["inkcolor"].upper().endswith("FF0000")), g)
# on objects: the rectangle takes the style and the color; props reads them back
S = ["newdoc A4", "registerframe x all", "ribbontab Draw", "tool rect", "frameact tool sbFill pick 3 00FF00", "mouse move 100 100", "mouse down 100 100", "mouse move 160 140", "mouse up 160 140", "mouse rdown 160 140", "tool select", "selidx 0", "echo O1", "props", "frameinfo sel", "frameglyph sel sbFill",
     "frameact sel sbFill pick 4", "echo O2", "props", "frameglyph sel sbFill", "frameact sel sbFill pick 4 FF0000", "echo O3", "props", "frameglyph sel sbFill",
     "frameact sel sbFill pick 0", "echo O4", "props", "frameglyph sel sbFill", "undo", "echo O5", "props"]
out = run(S)
gl = lambda mk: kv(after(out, mk, "FRAMEGLYPH")[0])
hint = lambda mk: [l for l in after(out, mk, "FRAMEINFO") if " sbFill " in l][0]
pt = lambda mk: after(out, mk, "PROPS")[0]
check("a rectangle drawn with the tool's fill has it: Vertical, green", "fill.type=Vertical" in pt("O1") and "Fill Vertical 00FF00" in hint("O1") and gl("O1")["inkcolor"] == "00FF00", (pt("O1"), hint("O1"), gl("O1")))
check("the selected rectangle's button shows it (Vertical: %d pixels)" % ink(3), gl("O1")["ink"] == str(ink(3)), gl("O1"))
check("picking Backward diagonal changes the type only (green stays)", "fill.type=Backward diagonal" in pt("O2") and gl("O2")["inkcolor"] == "00FF00" and gl("O2")["ink"] == str(ink(4)), (pt("O2"), gl("O2")))
check("picking a style and a color changes both", "fill.type=Backward diagonal" in pt("O3") and gl("O3")["inkcolor"] == "FF0000" and gl("O3")["ink"] == str(ink(4)), (pt("O3"), gl("O3")))
check("None shows an empty box", gl("O4")["ink"] == "0" and gl("O4")["white"] == "900" and "fill.type=None" in pt("O4"), (gl("O4"), pt("O4")))
check("undo takes the None back", "fill.type=Backward diagonal" in pt("O5"), pt("O5"))
# the menu: wheel, arrows, Enter, Esc. Menu order: None, Fill, Vertical, Horizontal, Back diagonal, Forward diagonal, Cross, Diagonal cross, Color
S = ["newdoc A4", "registerframe x all", "ribbontab Draw", "tool rect", "frameact tool sbFill pick 0 000000", "frameact tool sbFill click", "echo D0", "filldrop",
     "filldrop wheel-up", "echo D1", "filldrop", "filldrop wheel-down", "filldrop wheel-down", "filldrop wheel-down", "echo D2", "filldrop",
     "filldrop end", "filldrop wheel-down", "echo D3", "filldrop", "filldrop up", "echo D4", "filldrop", "filldrop home", "filldrop up", "echo D5", "filldrop",
     "filldrop down", "filldrop down", "filldrop enter", "echo D6", "filldrop", "frameinfo tool",
     "frameact tool sbFill click", "echo D7", "filldrop", "filldrop esc", "echo D8", "filldrop",
     "frameact tool sbFill pick 4 000000", "frameact tool sbFill click", "echo D9", "filldrop",
     "frameact tool sbFill click", "echo D10", "filldrop",
     "frameact tool sbFill pick 0 000000", "frameact tool sbFill click", "filldrop color 0000FF", "echo D11", "filldrop", "frameglyph tool sbFill",
     "frameact tool sbFill pick 5 000000", "frameact tool sbFill click", "filldrop color 00FF00", "echo D12", "filldrop", "frameglyph tool sbFill"]
out = run(S)
d = lambda mk: kv(after(out, mk, "FILLDROP")[0])
check("the menu opens with the current style highlighted (None: item 0)", d("D0")["visible"] == "1" and d("D0")["sel"] == "0", d("D0"))
check("wheel up on the first item stays on the first", d("D1")["sel"] == "0", d("D1"))
check("wheel down three times goes to the fourth item (3)", d("D2")["sel"] == "3", d("D2"))
check("End and wheel down stop at the last item (Color, 8)", d("D3")["sel"] == "8", d("D3"))
check("arrow up goes back one (7)", d("D4")["sel"] == "7", d("D4"))
check("Home and arrow up stop at the first (0)", d("D5")["sel"] == "0", d("D5"))
check("Down, Down, Enter chooses the third item, Vertical, and closes", d("D6")["visible"] == "0" and d("D6")["choice"] == "3", d("D6"))
check("the tool has Vertical now (the menu's third item is the property list's fourth)", "Fill Vertical" in [l for l in after(out, "D6", "FRAMEINFO") if " sbFill " in l][0], after(out, "D6", "FRAMEINFO"))
check("the next time the menu opens on the style the tool has (Vertical is item 2)", d("D7")["visible"] == "1" and d("D7")["sel"] == "2", d("D7"))
check("Esc closes it", d("D8")["visible"] == "0", d("D8"))
check("opened on Backward diagonal (item 4); a click on the button while it is open closes it", d("D9")["sel"] == "4" and d("D9")["visible"] == "1" and d("D10")["visible"] == "0", (d("D9"), d("D10")))
check("a color chosen while the fill is None makes it Solid, in that color, and closes the menu", d("D11")["visible"] == "0" and d("D11")["choice"] == "1" and d("D11")["color"] == "0000FF" and kv(after(out, "D11", "FRAMEGLYPH")[0])["ink"] == "900", (d("D11"), after(out, "D11", "FRAMEGLYPH")))
check("a color chosen with a pattern keeps the pattern", d("D12")["choice"] == "5" and d("D12")["color"] == "00FF00" and kv(after(out, "D12", "FRAMEGLYPH")[0])["ink"] == str(ink(5)), (d("D12"), after(out, "D12", "FRAMEGLYPH")))
check("a color chosen while the fill is None makes it Solid, in that color, and closes the menu", d("D11")["visible"] == "0" and d("D11")["choice"] == "1" and d("D11")["color"] == "0000FF" and kv(after(out, "D11", "FRAMEGLYPH")[0])["ink"] == "900", (d("D11"), after(out, "D11", "FRAMEGLYPH")))
check("a color chosen with a pattern keeps the pattern", d("D12")["choice"] == "5" and d("D12")["color"] == "00FF00" and kv(after(out, "D12", "FRAMEGLYPH")[0])["ink"] == str(ink(5)), (d("D12"), after(out, "D12", "FRAMEGLYPH")))
print("Fill button checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
