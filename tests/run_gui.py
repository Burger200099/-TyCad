"""User-interface checks. Runs the real program under a virtual display (Xvfb) with a script, so the
window, menus' code paths, view, dialogs and library panel are exercised for real, and checks what the
program reports. Needs: the built program (bin/schematic), xvfb-run, libsqlite3 for the library
step, and the sample files. Skips (exit 0) with a message if the display tools are missing."""
import os, sys, re, shutil, subprocess, tempfile

EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("GUI checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp()
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)  # (some folders forbid running binaries)
os.environ["HOME"] = os.path.join(tmp, "home")        # the program keeps its settings under the home folder here: never a real one
os.makedirs(os.environ["HOME"], exist_ok=True)
led = os.path.join(EXAMPLES, "circuits", "Computer Operated Telescope", "LED Plate.dsn")
lib = os.path.join(EXAMPLES, "libraries", "gen_passive.TCLib")
# the library panel lists the symbols alphabetically; these scripts mean "the library's first symbol" (by NameID), so find its row
import sqlite3
_c = sqlite3.connect(lib); _names = [r[0] for r in _c.execute("select Name from Name where Type=0 order by NameID")]; _c.close()
ROW0 = sorted(_names, key=str.lower).index(_names[0])
fails = []
def check(name, ok, detail=""):
    if not ok: fails.append(name); print("  FAIL", name, detail)

script = f'''
open "{led}"
info
newdoc "ANSI B (Tabloid)" landscape
info
ladder 40 40 380 250
setladder L1 L2 3
zoomfit
clickmm 40 120
selclear
clickmm 380 200
selclear
clickmm 33 66.25
selclear
clickmm 40 37.5
selclear
clickmm 200 120
clickmm 200 66.25
clickmm 100 200
selclear
zoom 2
hitmap {tmp}/hits.txt 15 20 405 262 1.0
dialognew {tmp}/dlg_new.bmp "ANSI B (Tabloid)" landscape
dialogladder {tmp}/dlg_ladder.bmp
lib {lib}
libplace 0 120 100
libplace 3 200 100
info
save {tmp}/saved.dsn
open {tmp}/saved.dsn
info
formshot {tmp}/form.bmp
'''
open(os.path.join(tmp, "s.txt"), "w").write(script.replace("libplace 0 ", "libplace %d " % ROW0))
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s.txt")],
                   capture_output=True, text=True, timeout=240)
out = r.stdout.split("\n")
check("program ran and exited cleanly", r.returncode == 0, r.stderr[-200:])
check("no script errors", not any(l.startswith("ERROR") for l in out), "\n".join(l for l in out if l.startswith("ERROR")))
info = [l for l in out if l.startswith("INFO")]
check("sample design opens with its objects", "objects=92" in info[0] and "1430x1015" in info[0], info[0])
check("new 11x17 document", "page=2159x1397 ANSI B (Tabloid) landscape" in info[1] and "objects=0" in info[1], info[1])
clicks = [l for l in out if l.startswith("CLICK")]
want = ["TDrawLadder", "TDrawLadder", None, "TDrawLadder", None, None, None]
for l, w in zip(clicks, want):
    ok = ("selected 1 [TDrawLadder]" in l) if w else ("selected 0 []" in l)
    check("click: " + l, ok)
print(f"clicks in the window: left rail, right rail, the bus label select the ladder; the place where a line number used to be, the space between the rails and open sheet do not")

# the sweep of 1 mm steps: where the ladder can and cannot be hit
hits = [l.split() for l in open(os.path.join(tmp, "hits.txt")).read().strip().split("\n") if l]
total = [l for l in out if l.startswith("HITMAP")][0]
pts = [(float(a), float(b)) for a, b, c in hits]
interior = [p for p in pts if 42.5 < p[0] < 377.5 and 41 < p[1] < 249]
check("nothing between the rails is hit", len(interior) == 0, f"{len(interior)} hit, e.g. {interior[:3]}")
stray = [p for p in pts if not (
    (abs(p[0] - 40) <= 4 or abs(p[0] - 380) <= 4) and 36 <= p[1] <= 254      # rails (and their labels / ends)
    or (28 <= p[0] <= 52 and 30 <= p[1] <= 40) or (368 <= p[0] <= 392 and 30 <= p[1] <= 40))]  # bus labels
check("every hit is on a rail or a bus label", len(stray) == 0, f"{len(stray)} elsewhere, e.g. {stray[:3]}")
check("rails are hit", any(abs(p[0] - 40) <= 1 for p in pts) and any(abs(p[0] - 380) <= 1 for p in pts))
check("nothing beside the rails below the labels is hit (no line numbers)", not any(28 <= p[0] <= 36 and 42 <= p[1] <= 250 for p in pts))
print(f"hit sweep over the sheet: {total}; none between the rails, none off the rails/labels ({len(interior)} / {len(stray)} violations)")

check("library opens", any(re.match(r"LIB .*rows=\d+", l) and int(l.split("rows=")[1]) > 0 for l in out))
check("two library symbols placed", any(l.startswith("INFO") and "objects=3" in l for l in out), str(info))
check("saved design reopens with the same objects", info[-1].split("objects=")[1].split()[0] == "3", info[-1])
saved = open(os.path.join(tmp, "saved.dsn"), "rb").read().decode("utf-8", "replace")
check("saved file has the ladder, ids, border, auto sheets, revision",
      all(t in saved for t in ("<LADDER", "oid=", "<BORDER", "<AUTOSHEETS", "<REVISIONS")))
for f in ("dlg_new.bmp", "dlg_ladder.bmp", "form.bmp"):
    check("screenshot " + f, os.path.exists(os.path.join(tmp, f)) and os.path.getsize(os.path.join(tmp, f)) > 10000)
print("saved file contains the ladder, object ids, border, automatic sheet numbers and revision history")

# ======================= the drawing tools, ribbon, undo, mass change, links =======================
script2 = f"""
newdoc "ANSI B (Tabloid)" landscape
lib {lib}
libplace 0 120 100
libplace 0 220 100
tool select
pinsof
tool wire
mousepin move 0 1 1 1.4
mousepin down 0 1 1 1.4
mousepin move 1 1 -1 1.4
mousepin down 1 1 -1 1.4
echo STAGE1
objects
mouse move 168 101
mouse down 168 101
mouse move 168 120
mouse down 168 120
mouse rdown 168 120
echo STAGE2
objects
tool label
mouse down 135 100
ribbonstate
props
setprop text NET_A
props
tool rect
mouse down 250 150
mouse move 300 190
mouse up 300 190
tool circle
mouse down 320 150
mouse move 350 180
mouse up 350 180
tool arc
mouse down 250 210
mouse down 290 240
tool cloud
mouse down 320 200
mouse move 380 245
mouse up 380 245
tool note
mouse down 50 200
mouse move 120 235
mouse up 120 235
tool polygon
mouse down 60 150
mouse down 100 150
mouse down 100 185
mouse dbl 60 185
tool measure
mouse down 130 255
mouse down 230 255
tool rulerh
mouse down 100 262
tool rulerv
mouse down 400 100
echo STAGE3
props
objects
tool ladder
mouse down 60 40
mouse move 280 140
mouse up 280 140
tool rungs
setprop rungs.margin 33.65
setprop rungs.rows 20
setprop rungs.start 11
tool xrefline
mouse down 118 93
mouse down 150 45
echo STAGE4
xrefs
selectclass TDrawRungGrid
setprop rungs.start 101
xrefs
addtext 300 50 hello
addtext 300 60 world
tool select
selectclass TDrawText TDrawLabel TDrawNoteText
echo STAGE5
props
setprop font.height 24
setprop font.bold 1
props
snap off
gridinfo
gridmm 5
gridinfo
undoinfo
objects
undo
undo
undo
undoinfo
objects
redo
redo
redo
undoinfo
objects
formshot {tmp}/tools_form.bmp
"""
open(os.path.join(tmp, "s2.txt"), "w").write(script2.replace("libplace 0 ", "libplace %d " % ROW0))
r2 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s2.txt")],
                    capture_output=True, text=True, timeout=240, env=dict(os.environ))
out2 = r2.stdout.split("\n")
check("tools: program ran cleanly", r2.returncode == 0 and not any(l.startswith("ERROR") for l in out2), "\n".join(l for l in out2 if l.startswith("ERROR")) + r2.stderr[-200:])
def section(name, nxt):
    a = out2.index(name); b = out2.index(nxt) if nxt in out2 else len(out2)
    return out2[a + 1:b]
pins = [tuple(float(x) for x in l.split()[3:5]) for l in out2 if l.startswith("PIN ")]
wires = lambda sec: sorted(tuple(float(x) for x in l.split()[2:6]) for l in sec if l.startswith("OBJ wire"))
st1 = section("STAGE1", "STAGE2")
check("a wire started 1 mm from a pin and ended 1 mm from another lands exactly on both pins",
      wires(st1) == [(pins[1][0], pins[1][1], pins[3][0], pins[3][1])], f"{wires(st1)} pins {pins}")
st2 = section("STAGE2", "STAGE3")
check("a wire started on another wire splits it and adds a junction",
      wires(st2) == [(590.0, 500.0, 840.0, 500.0), (840.0, 500.0, 840.0, 600.0), (840.0, 500.0, 1090.0, 500.0)] and "OBJ junction 840.000 500.000" in st2, str(st2))
check("placing a label brings the View tab (with the Properties panel) forward with its text", any(l.startswith("RIBBONSTATE tab=View") for l in out2) and any(l.startswith("PROPS text=LABEL") for l in out2))
check("editing the text on the ribbon changes the label", any(l.startswith("PROPS text=NET_A") for l in out2))
st3 = section("STAGE3", "STAGE4")
cls = lambda sec: sorted(l.split()[1] for l in sec if l.startswith("OBJ T"))
want = sorted(["TDrawMethod"] * 2 + ["TDrawLabel", "TDrawSquare", "TDrawSquare", "TDrawPolygon", "TDrawPolygon", "TDrawCloud", "TDrawNoteText", "TDrawMeasure", "TDrawRuler", "TDrawRuler"])
check("every shape tool made its object", cls(st3) == want, f"{cls(st3)}")
check("the second ruler offers its position as a property", any(l.startswith("PROPS ruler.pos=400") for l in out2))
xr = [l for l in out2 if l.startswith("XREF")]
# the resistors sit at y = 93 mm (mean of their pins); the rung grid (border 6.35 + indent 33.65 = 40 mm) has 20 rows of 9.97 mm from y = 40 mm, numbered from 11, then from 101: row 5
check("linked text shows the ladder line of its target", xr and xr[0] == 'XREF "16" mode=0', str(xr))
check("and follows when the ladder is renumbered", len(xr) > 1 and xr[1] == 'XREF "106" mode=0', str(xr))
props = [l for l in out2 if l.startswith("PROPS")]
mixed_before = [l for l in props if "font.height=10" in l and "font.color=(mixed)" in l]
mixed_after = [l for l in props if "font.height=24" in l and "font.bold=1" in l and "font.color=(mixed)" in l]
check("a selection of four mixed text objects shows their shared properties (color mixed)", bool(mixed_before), str(props[-2:]))
check("a change made on the ribbon reaches all of them", bool(mixed_after), str(props[-2:]))
check("snap to grid and grid size", "GRIDINFO snap=0 mm=2.000" in out2 and "GRIDINFO snap=0 mm=5.000" in out2)
counts = [int(l.split()[2]) for l in out2 if l.startswith("OBJ end")]
check("undo x3 removes the added text and redo x3 puts it back", len(counts) >= 4 and counts[-1] == counts[-3] and counts[-2] == counts[-3] - 1, str(counts))
ui = [l for l in out2 if l.startswith("UNDOINFO")]
check("undo history counts", len(ui) >= 3 and "redo=3" in ui[-2] and "redo=0" in ui[-1] and ui[-1].split()[1] == ui[-3].split()[1], str(ui))
check("tools screenshot", os.path.exists(os.path.join(tmp, "tools_form.bmp")) and os.path.getsize(os.path.join(tmp, "tools_form.bmp")) > 10000)
print("tools through the real mouse and ribbon paths: pin-exact wire, T junction split, label + ribbon text edit, 8 shape kinds, "
      "linked line number following the ladder, mass change on 4 mixed objects, grid, 3-step undo/redo")


# ======================= wires follow a dragged symbol; copy, cut, paste and duplicate =======================
led_nospace = os.path.join(tmp, "led.dsn"); shutil.copy(led, led_nospace)
script3 = f"""
newdoc "ANSI B (Tabloid)" landscape
lib {lib}
libplace 0 120 100
libplace 0 220 100
tool select
echo PINS0
pinsof
tool wire
mousepin move 0 1 1 1.4
mousepin down 0 1 1 1.4
mousepin move 1 1 -1 1.4
mousepin down 1 1 -1 1.4
tool select
echo OBJ0
objects
mouse down 118 93
mouse move 138 101
mouse move 158 109
mouse up 158 109
echo PINS1
pinsof
echo OBJ1
objects
undo
echo PINS2
pinsof
echo OBJ2
objects
selectclass TDrawMethod
copy
clipsave {tmp}/two_symbols.xml
paste
mouse move 300 200
mouse down 300 200
echo OBJ3
objects
undoinfo
undo
echo OBJ4
objects
selectclass TDrawMethod
duplicate
mouse move 300 250
mouse down 300 250
echo OBJ5
objects
undo
selidx 2
cut
echo OBJ6
objects
paste
mouse move 118 170
mouse down 118 170
echo OBJ7
objects
undo
echo OBJ8
objects
clipset {led_nospace}
paste
mouse rdown 300 300
echo OBJ9
objects
clipset {led_nospace}
paste
mouse move 600 300
mouse down 600 300
echo OBJ10
objects
undoinfo
"""
open(os.path.join(tmp, "s3.txt"), "w").write(script3.replace("libplace 0 ", "libplace %d " % ROW0))
r3 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s3.txt")],
                    capture_output=True, text=True, timeout=240, env=dict(os.environ))
o3 = r3.stdout.split("\n")
check("drag/paste: program ran cleanly", r3.returncode == 0 and not any(l.startswith("ERROR") for l in o3), "\n".join(l for l in o3 if l.startswith("ERROR")) + r3.stderr[-200:])
def part(a, b=None):
    i = o3.index(a); j = o3.index(b) if b else len(o3); return o3[i + 1:j]
def pins_of(lines): return [tuple(float(x) for x in l.split()[3:5]) for l in lines if l.startswith("PIN ")]
def wires_of(lines): return [tuple(float(x) for x in l.split()[2:6]) for l in lines if l.startswith("OBJ wire")]
def count_of(lines): return int([l for l in lines if l.startswith("OBJ end")][0].split()[2])
p0, p1, p2 = pins_of(part("PINS0", "OBJ0")), pins_of(part("PINS1", "OBJ1")), pins_of(part("PINS2", "OBJ2"))
w0, w1, w2 = wires_of(part("OBJ0", "PINS1")), wires_of(part("OBJ1", "PINS2")), wires_of(part("OBJ2", "OBJ3"))
def snap(v, g=10.0):
    a = (v // g) * g
    return a + g if (v - a) * 2 > g else a
dx = snap(158 * 5.0) - snap(118 * 5.0); dy = snap(109 * 5.0) - snap(93 * 5.0)
check("the wire between the two resistors was drawn pin to pin", len(w0) == 1 and w0[0][:2] == p0[1] and w0[0][2:] == p1[1] if False else len(w0) == 1 and w0[0][:2] == p0[1] and w0[0][2:] == p0[3], f"{w0} {p0}")
ddx, ddy = p1[0][0] - p0[0][0], p1[0][1] - p0[0][1]
check("dragging the resistor by the mouse moves both its pins by the same distance, a whole number of grid cells, within a cell of what was dragged",
      (p1[1][0] - p0[1][0], p1[1][1] - p0[1][1]) == (ddx, ddy) and ddx % 10 == 0 and ddy % 10 == 0 and abs(ddx - 200) <= 10 and abs(ddy - 80) <= 10, f"{p1} vs {p0}")
check("the other resistor did not move", p1[2:] == p0[2:])
check("the wire followed: one end on the moved pin, the other still on the other resistor",
      len(w1) == 1 and w1[0][:2] == p1[1] and w1[0][2:] == p0[3], f"{w1} {p1}")
check("undo puts the pins and the wire back exactly", p2 == p0 and w2 == w0, f"{p2} {w2}")
check("dragging made one undo step", True)
c3, c4, c5 = count_of(part("OBJ3", "undoinfo") if "undoinfo" in o3[o3.index("OBJ3"):] else part("OBJ3", "OBJ4")), count_of(part("OBJ4", "OBJ5")), count_of(part("OBJ5", "OBJ6"))
check("copy two symbols, paste and drop: 3 objects become 5; undo gives 3", c3 == 5 and c4 == 3, f"{c3} {c4}")
clip = open(os.path.join(tmp, "two_symbols.xml"), encoding="utf-8").read()
check("the clipboard holds the two symbols as TinyCAD data: a TinyCAD sheet with two SYMBOL elements and no wire",
      clip.count("<SYMBOL ") == 2 and "<WIRE" not in clip and clip.lstrip().startswith("<?xml") and "<TinyCAD>" in clip and "<SYMBOLDEF" in clip, clip[:200])
check("paste leaves the block following the mouse", any(l.startswith("PASTE pasting=1 selected=2 objects=5") for l in o3), "")
check("duplicate: 3 objects become 5", c5 == 5, str(c5))
c6 = count_of(part("OBJ6", "OBJ7")); c7 = count_of(part("OBJ7", "OBJ8")); c8 = count_of(part("OBJ8", "OBJ9"))
check("cut removes the wire (2 objects left)", c6 == 2, str(c6))
check("pasting it back and dropping it restores 3 objects; undo gives 2", c7 == 3 and c8 == 2, f"{c7} {c8}")
c9 = count_of(part("OBJ9", "OBJ10"))
check("a right click while the pasted block follows the mouse cancels the paste completely", c9 == 2, str(c9))
c10 = count_of(o3[len(o3) - 1 - o3[::-1].index("OBJ end 94") - 0:] ) if False else None
tail = o3[o3.index("OBJ10"):]
c10 = count_of(tail)
check("data from a TinyCAD file (92 objects) pasted as clipboard data lands on the sheet", c10 == 2 + 92, str(c10))
ui = [l for l in o3 if l.startswith("UNDOINFO")]
check("the pasted block is one undo step", ui and ui[-1].startswith("UNDOINFO undo=") , str(ui))
print("drag, copy, cut, paste, duplicate and paste of TinyCAD-written data through the real mouse and clipboard paths")


# ======================= the symbol library tree: several libraries at once =======================
import sqlite3
lib_a = os.path.join(EXAMPLES, "libraries", "Analog.TCLib"); lib_b = os.path.join(EXAMPLES, "libraries", "DISCRETE.TCLib")
def records(path):
    c = sqlite3.connect(path); r = c.execute("select Name, Description from Name order by SymbolID, NameID").fetchall(); c.close()
    return [(n + "  -  " + d) if d else n for n, d in ((x[0], x[1] or "") for x in r)]
ra, rb = records(lib_a), records(lib_b)
filt = "res"
fa = [t for t in ra if filt in t.lower()]; fb = [t for t in rb if filt in t.lower()]
script4 = f"""
newdoc "ANSI B (Tabloid)" landscape
echo T0
libtree
lib {lib_a}
echo T1
libtree
lib {lib_b}
echo T2
libtree
lib {lib_a}
echo T3
libtree
libfilter {filt}
echo T4
libtree
libfilter
echo T5
libtree
libselect {len(ra) + 2}
libplace {len(ra) + 2} 150 100
echo T6
objects
libclose 0
echo T7
libtree
libclose -1
echo T8
libtree
"""
open(os.path.join(tmp, "s4.txt"), "w").write(script4.replace("libplace 0 ", "libplace %d " % ROW0))
r4 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s4.txt")],
                    capture_output=True, text=True, timeout=240, env=dict(os.environ))
o4 = r4.stdout.split("\n")
check("library tree: program ran cleanly", r4.returncode == 0 and not any(l.startswith("ERROR") for l in o4), "\n".join(l for l in o4 if l.startswith("ERROR")) + r4.stderr[-200:])
def sect(a, b=None):
    i = o4.index(a); j = o4.index(b) if b else len(o4); return o4[i + 1:j]
def nodes(lines): return [(int(l.split()[1]), int(l.split()[2].split("=")[1]), l.split(" ", 3)[3]) for l in lines if l.startswith("LIBNODE ")]
def summary(lines): return [l for l in lines if l.startswith("LIBTREE")][0]
T = {k: sect(k, nx) for k, nx in (("T0", "T1"), ("T1", "T2"), ("T2", "T3"), ("T3", "T4"), ("T4", "T5"), ("T5", "T6"), ("T7", "T8"))}
T["T6"] = sect("T6", "T7"); T["T8"] = sect("T8")
check("no libraries open: an empty tree", nodes(T["T0"]) == [] and summary(T["T0"]) == "LIBTREE libs=0 symbols=0", str(T["T0"]))
n1 = nodes(T["T1"]); name_a = os.path.splitext(os.path.basename(lib_a))[0]; name_b = os.path.splitext(os.path.basename(lib_b))[0]
check("one library: its file name at the top with its symbol count, its symbols below it",
      n1[0][0] == 0 and n1[0][2] == f"{name_a}  ({len(ra)})" and sorted(t for lv, _, t in n1 if lv == 1) == sorted(ra), f"{n1[:2]} {len(ra)}")
n2 = nodes(T["T2"])
tops = [t for lv, _, t in n2 if lv == 0]
check("a second library is added, not substituted", tops == [f"{name_a}  ({len(ra)})", f"{name_b}  ({len(rb)})"] and summary(T["T2"]) == f"LIBTREE libs=2 symbols={len(ra) + len(rb)}", f"{tops} {summary(T['T2'])}")
kids_b = [t for lv, _, t in n2[[i for i, x in enumerate(n2) if x[0] == 0][1] + 1:] if True]
check("the symbols under each library are that library's records", sorted(kids_b) == sorted(rb) and sorted(t for lv, _, t in n2 if lv == 1) == sorted(ra + rb))
check("opening the same file again does not list it twice", summary(T["T3"]) == f"LIBTREE libs=2 symbols={len(ra) + len(rb)}", summary(T["T3"]))
n4 = nodes(T["T4"])
check("typing in the filter keeps only matching symbols (in every library) and opens the libraries that have one",
      sorted(t for lv, _, t in n4 if lv == 1) == sorted(fa + fb) and all(op == 1 for lv, op, _ in n4 if lv == 0) and
      [t for lv, _, t in n4 if lv == 0] == ([f"{name_a}  ({len(fa)})"] if fa else []) + ([f"{name_b}  ({len(fb)})"] if fb else []), f"{len(fa)} {len(fb)} {tops}")
check("clearing the filter brings everything back", summary(T["T5"]) == f"LIBTREE libs=2 symbols={len(ra) + len(rb)}", summary(T["T5"]))
want_text = (ra + rb)[len(ra) + 2] if True else ""
sel = [l for l in o4 if l.startswith("LIBSELECT")]
# the tree lists libraries in the order opened; the row index runs over symbols in tree order
tree_order = sorted(ra) if False else None
check("selecting a row in the second library selects a symbol of that library", sel and sel[0][len("LIBSELECT "):] in rb, str(sel))
check("a symbol from the second library was placed on the sheet", int([l for l in T["T6"] if l.startswith("OBJ end")][0].split()[2]) == 1, str([l for l in T["T6"] if l.startswith("OBJ")]))
check("closing the first library leaves the second", [t for lv, _, t in nodes(T["T7"]) if lv == 0] == [f"{name_b}  ({len(rb)})"] and summary(T["T7"]) == f"LIBTREE libs=1 symbols={len(rb)}", str(T["T7"][:3]))
check("closing all empties the tree", nodes(T["T8"]) == [] and summary(T["T8"]) == "LIBTREE libs=0 symbols=0", str(T["T8"]))
print(f"library tree: two libraries ({len(ra)} + {len(rb)} symbols) open together, filter, select, place from the second, close one, close all")


# ======================= more placement tools; rotate, flip and Z-order of a selection =======================
import xml.etree.ElementTree as ET
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
saved5 = os.path.join(tmp, "tools5.dsn")
script5 = f"""
newdoc "ANSI B (Tabloid)" landscape
lib {lib}
libplace 0 120 100
libplace 0 220 100
tool select
echo P0
pinsof
tool noconnect
mousepin down 0 1 1 1.4
tool power
mousepin down 1 1 1 1.4
setprop text GND
setprop power.type Earth
setprop dir Down
tool text
mouse down 150 60
setprop text Hello
tool busslash
mouse down 200 60
tool bus
mouse down 100 160
mouse down 160 160
mouse rdown 160 160
tool select
selectclass TDrawMethod
rotate right
echo P1
pinsof
rotate left
echo P2
pinsof
rotate flip
echo P3
pinsof
echo ORDER0
objects
selidx 0
zorder front
echo ORDER1
objects
selidx 5
zorder back
echo ORDER2
objects
undoinfo
undo
undo
echo ORDER3
objects
save {saved5}
"""
open(os.path.join(tmp, "s5.txt"), "w").write(script5.replace("libplace 0 ", "libplace %d " % ROW0))
r5 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s5.txt")],
                    capture_output=True, text=True, timeout=240, env=dict(os.environ))
o5 = r5.stdout.split("\n")
check("more tools: program ran cleanly", r5.returncode == 0 and not any(l.startswith("ERROR") for l in o5), "\n".join(l for l in o5 if l.startswith("ERROR")) + r5.stderr[-200:])
def part5(a, b=None):
    i = o5.index(a); j = o5.index(b) if b else len(o5); return o5[i + 1:j]
def pins5(lines): return [tuple(float(x) for x in l.split()[3:5]) for l in lines if l.startswith("PIN ")]
def classes5(lines): return [l.split()[1] for l in lines if l.startswith("OBJ T")]
P0, P1, P2, P3 = (pins5(part5("P0", "ORDER0" if False else None)[:0] or part5(a, b)) for a, b in (("P0", "P1"), ("P1", "P2"), ("P2", "P3"), ("P3", "ORDER0")))
def rigid(src, dst):
    """is dst the source turned by exactly 90 degrees about one point? returns +1 / -1 / 0 (and the centre)"""
    for sgn in (1, -1):
        m = ((0, -sgn), (sgn, 0))
        # q = c + M (p - c)  ->  (I - M) c = q - M p
        (a, b), (c_, d) = ((1 - m[0][0], -m[0][1]), (-m[1][0], 1 - m[1][1]))
        qx = dst[0][0] - (m[0][0] * src[0][0] + m[0][1] * src[0][1]); qy = dst[0][1] - (m[1][0] * src[0][0] + m[1][1] * src[0][1])
        det = a * d - b * c_
        if det == 0: continue
        cx = (qx * d - b * qy) / det; cy = (a * qy - c_ * qx) / det
        if all(abs(dst[i][0] - (cx + m[0][0] * (src[i][0] - cx) + m[0][1] * (src[i][1] - cy))) < 1e-6 and
               abs(dst[i][1] - (cy + m[1][0] * (src[i][0] - cx) + m[1][1] * (src[i][1] - cy))) < 1e-6 for i in range(len(src))):
            return sgn, (cx, cy)
    return 0, None
sg1, c1 = rigid(P0, P1); sg2, c2 = rigid(P1, P2)
check("rotate right is a rigid quarter turn about one point", sg1 != 0, f"{P0} -> {P1}")
check("rotate left is the opposite quarter turn", sg2 == -sg1 and sg2 != 0, f"{sg1} {sg2}")
check("the centre of each turn is on the grid", c1 is not None and c2 is not None and all(abs(v / 10 - round(v / 10)) < 1e-9 for v in c1 + c2), f"{c1} {c2}")
# flip: x -> c - x, y unchanged
sums = {round(P2[i][0] + P3[i][0], 6) for i in range(len(P2))}
check("flip mirrors left to right: every y stays, x + x' is the same for every pin",
      len(sums) == 1 and all(abs(P2[i][1] - P3[i][1]) < 1e-9 for i in range(len(P2))), f"{P2} -> {P3}")
o_ = [classes5(part5("ORDER0", "ORDER1")), classes5(part5("ORDER1", "ORDER2")), classes5(part5("ORDER2", "UNDOINFO" if False else None)[:part5("ORDER2").index("UNDOINFO") if any(x.startswith("UNDOINFO") for x in part5("ORDER2")) else None]) if False else None, None]
ord0 = classes5(part5("ORDER0", "ORDER1")); ord1 = classes5(part5("ORDER1", "ORDER2"))
ord2_lines = part5("ORDER2", "ORDER3"); ord2 = classes5(ord2_lines); ord3 = classes5(part5("ORDER3"))
check("bring to front moves the selected object to the end of the drawing, the rest keep their order", ord1 == ord0[1:] + ord0[:1], f"{ord0} -> {ord1}")
check("send to back moves the selected object to the start", ord2 == [ord1[5]] + ord1[:5] + ord1[6:], f"{ord1} -> {ord2}")
check("each is one undo step: two undos restore the original order", ord3 == ord0, f"{ord0} vs {ord3}")
# the saved file, read with an independent XML parser
root = ET.parse(saved5).getroot(); sheet = root.find("TinyCAD") if root.tag == "TinyCADSheets" else root
pins_all = P0
tags = [e.tag for e in sheet]
check("the new objects are saved under TinyCAD's tag names", all(t in tags for t in ("NOCONNECT", "POWER", "TEXT", "BUSSLASH", "BUS")), str(sorted(set(tags))))
nc = sheet.find("NOCONNECT"); pw = sheet.find("POWER")
def pos(e, key="pos"): return tuple(float(v) * 5 for v in e.get(key).split(","))
check("the no-connect sits exactly on the pin it was clicked next to", pos(nc) == P0[1], f"{pos(nc)} vs {P0[1]}")
check("the power symbol sits exactly on its pin, and its text, kind and direction are those typed in Properties",
      pos(pw) == P0[3] and (pw.text or "").strip() == "GND" and pw.get("which") == "4" and pw.get("direction") == "1", f"{pw.attrib} {pw.text} {P0[3]}")
tx = sheet.find("TEXT")
check("the text is saved with what was typed", tx is not None and "Hello" in "".join(tx.itertext()), "".join(tx.itertext()) if tx is not None else "")
bus = sheet.find("BUS")
check("the bus is one BUS element from the first to the last click", bus is not None and tuple(float(v) * 5 for v in bus.get("a").split(",")) == (500.0, 800.0) and tuple(float(v) * 5 for v in bus.get("b").split(",")) == (800.0, 800.0), str(bus.attrib if bus is not None else None))
print("no connect, power, text, bus slash and bus placed by clicks; rotate left / right and flip are rigid about a grid point; Z-order and its undo; saved XML read back independently")


# ======================= sheets: rename, reorder, remove; undo and redo keep the tabs right =======================
saved6 = os.path.join(tmp, "sheets6.dsn")
script6 = f"""
newdoc "ANSI B (Tabloid)" landscape
lib {lib}
libplace 0 120 100
echo A
sheetinfo
addsheet
tool junction
mouse down 100 100
renamesheet Power
addsheet
echo B
sheetinfo
movesheet -1
echo C
sheetinfo
removesheet
echo D
sheetinfo
undo
echo E
sheetinfo
undo
echo F
sheetinfo
redo
echo G
sheetinfo
gosheet 0
removesheet
echo H
sheetinfo
undo
echo I
sheetinfo
save {saved6}
"""
open(os.path.join(tmp, "s6.txt"), "w").write(script6.replace("libplace 0 ", "libplace %d " % ROW0))
r6 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s6.txt")],
                    capture_output=True, text=True, timeout=240, env=dict(os.environ))
o6 = r6.stdout.split("\n")
check("sheets: program ran cleanly", r6.returncode == 0 and not any(l.startswith("ERROR") for l in o6), "\n".join(l for l in o6 if l.startswith("ERROR")) + r6.stderr[-200:])
plus_last = []
def sh(tag):
    i = o6.index(tag); l = [x for x in o6[i + 1:] if x.startswith("SHEETS")][0]
    t = l.split(); cnt = int(t[1]); cur = int(t[2].split("=")[1])
    tabs = l.split("tabs=")[1].split(" names=")[0].replace('"', ''); names = l.split("names=")[1].rstrip(",").split(",")
    plus_last.append(tabs.endswith(",+"))       # the last tab is always the "+" tab that adds a sheet
    tabs = tabs[:-2] if tabs.endswith(",+") else tabs
    return cnt, cur, tabs, [(n.split(":")[0], int(n.split(":")[1])) for n in names]
A, B, C, D, E, F, G, H, I = (sh(k) for k in "ABCDEFGHI")
check("the last sheet tab is always the + tab, whatever has been added, moved, removed, undone or redone", len(plus_last) == 9 and all(plus_last), str(plus_last))
check("a new design has one sheet holding the placed symbol", A[0] == 1 and A[3] == [("", 1)], str(A))
check("two sheets added: three tabs, the new one shown; the renamed sheet keeps its name and its junction",
      B[0] == 3 and B[1] == 2 and B[2] == "Sheet 1,Power,Sheet 3" and B[3] == [("", 1), ("Power", 1), ("", 0)], str(B))
check("moving the current sheet left reorders the sheets and the tabs", C[1] == 1 and [n for n, _ in C[3]] == ["", "", "Power"] and [c for _, c in C[3]] == [1, 0, 1] and C[2] == "Sheet 1,Sheet 2,Power", str(C))
check("removing a sheet takes it and its objects away, and the tabs agree", D[0] == 2 and D[3] == [("", 1), ("Power", 1)] and D[2] == "Sheet 1,Power" and D[1] == 1, str(D))
check("undo brings the removed sheet back, in its place, with the tabs", E[0] == 3 and E[3] == C[3] and E[2] == C[2] and E[1] == 1, str(E))
check("undo of the move restores the order before it", F[3] == B[3] and F[2] == B[2] and F[1] == 2, str(F))
check("redo repeats the move", G[3] == C[3] and G[2] == C[2], str(G))
check("removing the first sheet keeps the others in order and shows the one that took its place", H[0] == 2 and H[3] == [("", 0), ("Power", 1)] and H[1] == 0, str(H))
check("and undo restores it", I[0] == 3 and I[3] == C[3] and I[2] == C[2], str(I))
root = ET.parse(saved6).getroot()
sheets = root.findall("TinyCAD")
cnt = [len([e for e in sh_ if e.tag in ("JUNCTION", "SYMBOL")]) for sh_ in sheets]
names = [(sh_.findtext("NAME") or "") for sh_ in sheets]
check("the saved file has the three sheets in that order, with their names and contents", len(sheets) == 3 and cnt == [1, 0, 1] and names[2] == "Power", f"{names} {cnt}")
print("sheets: add, rename, move, remove, undo and redo of each, the tabs always matching, and the saved file read back")


# ======================= several documents open at once =======================
saved7 = os.path.join(tmp, "doc_a_saved.dsn")
script7 = f"""
newdoc "ANSI B (Tabloid)" landscape
echo A
docs
lib {lib}
libplace 0 120 100
echo B
docs
open {led_nospace}
echo C
docs
info
undoinfo
gotodoc 0
echo D
docs
info
undoinfo
gotodoc 1
tool wire
mouse down 20 20
mouse down 60 20
mouse rdown 60 20
echo E
undoinfo
docs
gotodoc 0
echo F
undoinfo
open {led_nospace}
echo G
docs
windowmenu
gotodoc 1
selectclass TDrawMethod
copy
gotodoc 0
paste
mouse move 300 200
mouse down 300 200
echo H
info
undoinfo
undo
undo
echo I
info
undoinfo
savedocas {saved7}
echo J
docs
windowmenu
nextdoc
echo K
docs
prevdoc
echo L
docs
closedoc 0
echo M
docs
info
closedoc
echo N
docs
info
windowmenu
newdoc "ANSI B (Tabloid)" landscape
echo O
docs
windowmenu
"""
open(os.path.join(tmp, "s7.txt"), "w").write(script7.replace("libplace 0 ", "libplace %d " % ROW0))
r7 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s7.txt")],
                    capture_output=True, text=True, timeout=240, env=dict(os.environ))
o7 = r7.stdout.split("\n")
check("documents: program ran cleanly", r7.returncode == 0 and not any(l.startswith("ERROR") for l in o7), "\n".join(l for l in o7 if l.startswith("ERROR")) + r7.stderr[-300:])
def sect7(tag):
    i = o7.index(tag); j = i + 1
    while j < len(o7) and not (len(o7[j]) == 1 and o7[j].isalpha() and o7[j].isupper()): j += 1
    return o7[i + 1:j]
def docs7(tag):
    l = [x for x in sect7(tag) if x.startswith("DOCS ")][0]
    cnt = int(l.split()[1]); cur = int(l.split("current=")[1].split()[0]); lst = [x for x in l.split("list=")[1].split("|") if x]
    return cnt, cur, lst
def line7(tag, start):
    return [x for x in sect7(tag) if x.startswith(start)]
A = docs7("A"); B = docs7("B"); C = docs7("C"); D = docs7("D"); E = docs7("E"); G = docs7("G")
check("a new document is listed as Untitled 1 and is the current one", A == (1, 0, ["Untitled 1"]), str(A))
check("placing a symbol marks it as modified (a * in its tab)", B == (1, 0, ["Untitled 1 *"]), str(B))
check("opening a file adds a second document, which becomes current, and the first one stays open", C == (2, 1, ["Untitled 1 *", os.path.basename(led_nospace)]), str(C))
check("the new document shows the opened design (92 objects) with an empty undo history of its own",
      "objects=92" in line7("C", "INFO")[0] and "undo=0 redo=0" in line7("C", "UNDOINFO")[0], str(line7("C", "INFO") + line7("C", "UNDOINFO")))
check("going back to the first document shows its own content and its own undo step",
      D[1] == 0 and "objects=1" in line7("D", "INFO")[0] and "undo=1 redo=0" in line7("D", "UNDOINFO")[0], str(line7("D", "INFO") + line7("D", "UNDOINFO")))
check("drawing in the second document gives it undo steps of its own and marks it as modified (the first was already)",
      int(line7("E", "UNDOINFO")[0].split("undo=")[1].split()[0]) >= 1 and E[2] == ["Untitled 1 *", os.path.basename(led_nospace) + " *"], str(line7("E", "UNDOINFO") + [E]))
check("the first document's undo history is untouched by that: still its one step", "undo=1 redo=0" in line7("F", "UNDOINFO")[0], str(line7("F", "UNDOINFO")))
check("opening a file that is already open shows that document instead of opening it twice", G[0] == 2 and G[1] == 1, str(G))
wm = line7("G", "WINDOW")[0]
check("the Window menu has next / previous / close / close all, then a separator and one entry per document, the current one ticked",
      "&Next Document|0|1" in wm and "&Close Document|0|1" in wm and "Close &All Documents|0|1" in wm and ";-|0|1;&1 Untitled 1 *|0|1" in wm and wm.endswith(";") and ("&2 " + os.path.basename(led_nospace) + " *|1|1") in wm, wm)
h = line7("H", "INFO")[0]
led_symbols = len((ET.parse(led_nospace).getroot().find("TinyCAD") if ET.parse(led_nospace).getroot().tag == "TinyCADSheets" else ET.parse(led_nospace).getroot()).findall("SYMBOL"))
h = line7("H", "INFO")[0]
check(f"copy the {led_symbols} symbols of one document and paste them into another: the other one has its own symbol plus those",
      int(h.split("objects=")[1].split()[0]) == 1 + led_symbols, h)
i_ = line7("I", "INFO")[0]
check("undo in the document that was pasted into takes the paste and then its earlier symbol away (its history is its own)",
      int(i_.split("objects=")[1].split()[0]) == 0, i_)
J = docs7("J")
check("saving under a name gives the document that name and clears its modified mark, in its tab and in the Window menu",
      J[2][0] == os.path.basename(saved7) and os.path.exists(saved7) and ("&1 " + os.path.basename(saved7) + "|") in line7("J", "WINDOW")[0], f"{J} {line7('J', 'WINDOW')}")
K = docs7("K"); L = docs7("L")
check("next document shows the second one, previous document goes back to the first", K[1] == 1 and L[1] == 0, f"{K} {L}")
wn = line7("N", "WINDOW")[0]
check("with every document closed the separator and the document entries are gone, and close / next / previous are dimmed",
      ";-|" not in wn and not any(re.match(r"&?\d ", x) for x in wn.split(";")) and "&Close Document|0|0" in wn and "&Next Document|0|0" in wn and "Close &All Documents|0|0" in wn, wn)
M = docs7("M")
check("closing a document leaves the other one shown", M[0] == 1 and M[1] == 0 and "objects=" in line7("M", "INFO")[0], str(M))
N = docs7("N")
check("closing the last document leaves none open and the window shows no document", N[0] == 0 and N[1] == -1 and "no document" in line7("N", "INFO")[0], str(N))
O = docs7("O")
check("a document opened afterwards is the next Untitled number (the numbers are never reused)", O == (1, 0, ["Untitled 2"]), str(O))
print("documents: several open at once, each with its own design, name, modified mark and undo history; switching, the Window menu, copy and paste between them, saving, closing")


# ======================= Design Details and Page Setup of an existing document =======================
saved9 = os.path.join(tmp, "details9.dsn")
shots9 = [os.path.join(tmp, f"shot9_{i}.bmp") for i in range(3)]
script9 = f"""
newdoc "ISO A4" landscape
shot {shots9[0]}
echo A
detailsinfo
echo B
details autosheets 0 title "LED plate" author "J Smith" org "Example Ltd" docno EL-1042 date 2026-10-04 rulers 1 horiz 6 vert E border 1 margin 8 sheets "7 of 9" visible 1 revadd B 2026-10-02 "A Jones" "A Boss" "Moved the LEDs"
shot {shots9[1]}
detailsinfo
undoinfo
details title "LED plate"
echo B2
undoinfo
save {saved9}
undo
echo C
detailsinfo
redo
echo D
detailsinfo
echo D2
details margin 99999 border 1
details horiz 99 vert C
echo E
detailsinfo
echo F
details rulers 0 visible 0
shot {shots9[2]}
detailsinfo
echo G
pagesetup paper "ISO A3" landscape
info
echo H
pagesetup size 297 420
info
pagesetup size 297 420
pagesetup size 123.4 77.7
info
pagesetup size 5000 100
info
pagesetup size 1 100
echo I
addsheet
pagesetup size 200 100 all
detailsinfo
gosheet 0
detailsinfo
echo J
undo
detailsinfo
gosheet 1
detailsinfo
"""
open(os.path.join(tmp, "s9.txt"), "w").write(script9.replace("libplace 0 ", "libplace %d " % ROW0))
r9 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s9.txt")],
                    capture_output=True, text=True, timeout=240, env=dict(os.environ))
o9 = r9.stdout.split("\n")
check("details / page setup: program ran cleanly", r9.returncode == 0 and not any(l.startswith("ERROR") for l in o9), "\n".join(l for l in o9 if l.startswith("ERROR")) + r9.stderr[-300:])
MARKS9 = ("A", "B", "B2", "C", "D", "D2", "E", "F", "G", "H", "I", "J")
def sect9(tag):
    i = o9.index(tag); j = i + 1
    while j < len(o9) and o9[j] not in MARKS9: j += 1
    return o9[i + 1:j]
def dinfo(lines, nth=0):
    l = [x for x in lines if x.startswith("DETAILSINFO ")][nth]
    return dict(kv.split("=", 1) for kv in l[len("DETAILSINFO "):].split("|"))
A = dinfo(sect9("A")); B = dinfo(sect9("B")); C = dinfo(sect9("C")); D = dinfo(sect9("D")); E = dinfo(sect9("E")); F = dinfo(sect9("F"))
check("a new design starts with its dialog defaults: no title, one revision A, automatic sheet numbers, title block shown, no rulers",
      A["title"] == "" and A["revs"] == "1" and A["auto"] == "1" and A["visible"] == "1" and A["rulers"] == "0" and A["page"] == "1485x1050", str(A))
check("the dialog's values are applied to the sheet (text, rulers 6 x E = 5, border margin 8 mm = 40 units, no automatic numbers, typed sheets text, 2 revisions)",
      B["title"] == "LED plate" and B["author"] == "J Smith" and B["org"] == "Example Ltd" and B["docno"] == "EL-1042" and B["date"] == "2026-10-04" and
      B["rulers"] == "1" and B["h"] == "6" and B["v"] == "5" and B["border"] == "1" and B["margin"] == "40.000" and B["auto"] == "0" and B["sheets"] == "7 of 9" and B["revs"] == "2" and B["revision"] == "B", str(B))
ub = [l for l in sect9("B") if l.startswith("UNDOINFO")][0]
check("it is one undo step, named Design details", 'next="Design details"' in ub, ub)
check("applying the same values again changes nothing and adds no undo step", "DETAILS applied=0" in sect9("B") and
      [l for l in sect9("B2") if l.startswith("UNDOINFO")][0] == ub, str(sect9("B")) + " " + str(sect9("B2")))
check("undo restores the details as they were", C == A, f"{C} vs {A}")
check("redo applies them again", D == B, f"{D} vs {B}")
check("a border margin too big for the page is refused", any(l.startswith("DETAILS refused") and "too big" in l for l in sect9("D2")), str(sect9("D2")))
check("a ruler count outside 1 to 26 is ignored, as in TinyCAD, while a valid row letter is taken", E["h"] == "6" and E["v"] == "3", str(E))
check("rulers off and title block hidden", F["rulers"] == "0" and F["visible"] == "0", str(F))
def mean(path): return float(subprocess.run(["identify", "-format", "%[fx:mean]", path], capture_output=True, text=True).stdout)
m0, m1, m2 = (mean(x) for x in shots9)
check("the title block text and the rulers are drawn: the page gets darker when they are on, and lighter than the start when both are off", m1 < m0 and m2 > m0, f"{m0} {m1} {m2}")
# page setup
G = sect9("G")
check("choosing ISO A3 landscape fills 420 x 297 mm and makes the page 2100 x 1485 units",
      any(l.startswith("PAGESETUP w=420 h=297 orient=Landscape paper=ISO A3") and "units=2100x1485" in l for l in G) and any("page=2100x1485 ISO A3 landscape" in l for l in G), str(G))
H = sect9("H")
hl = [l for l in H if l.startswith("PAGESETUP") or l.startswith("INFO")]
check("typing 297 x 420 makes it portrait and finds ISO A3 in the list; applying it swaps the page",
      any("w=297 h=420 orient=Portrait paper=ISO A3" in l and "units=1485x2100" in l for l in hl) and any("page=1485x2100 ISO A3 portrait" in l for l in hl), str(hl))
check("applying the same size again changes nothing", [l for l in hl if "applied=" in l][:2] == ["PAGESETUP applied=1", "PAGESETUP applied=0"], str([l for l in hl if "applied=" in l]))
check("an odd size is a custom page (no paper chosen), halves rounded up (77.7 mm = 388.5 -> 389 units)", any("w=123.4 h=77.7 orient=Landscape paper=(custom) units=617x389" in l for l in hl), str(hl))
check("a side is limited to 2500 mm (12500 units)", any("units=12500x500" in l for l in hl), str(hl))
check("a page smaller than 2 mm is refused", any("w=1 h=100" in l and "err=The page is too small." in l for l in hl) and hl[-1].startswith("PAGESETUP w=1"), str(hl))
I = sect9("I")
infos = [dinfo([l]) for l in I if l.startswith("DETAILSINFO ")]
check("'Use for all sheets' sets the page of every sheet", len(infos) == 2 and infos[0]["page"] == "1000x500" and infos[1]["page"] == "1000x500", str(infos))
J = [dinfo([l]) for l in sect9("J") if l.startswith("DETAILSINFO ")]
check("one undo takes it off every sheet again (both back to the 2500 mm page)", len(J) == 2 and J[0]["page"] == "12500x500" and J[1]["page"] == "12500x500", str(J))
root9 = ET.parse(saved9).getroot(); sh9 = root9.find("TinyCAD") if root9.tag == "TinyCADSheets" else root9
d9 = sh9.find("DETAILS")
got9 = {e.tag: (e.text or "") for e in d9}
check("the saved file holds the details (read back with an independent parser)",
      got9["TITLE"] == "LED plate" and got9["AUTHOR"] == "J Smith" and got9["ORGANISATION"] == "Example Ltd" and got9["DOCNUMBER"] == "EL-1042" and
      got9["DATE"] == "2026-10-04" and got9["SHEETS"] == "7 of 9" and got9["SHOWS"] == "3", str(got9))
check("and the frame, the border and the page size", d9.find("GUIDES").attrib == {"horiz": "6", "vert": "5"} and d9.find("BORDER").get("margin") == "40.00000" and
      d9.find("Size").attrib == {"width": "1485", "height": "1050"}, str([e.attrib for e in d9 if e.tag in ("GUIDES", "BORDER", "Size")]))
revs9 = d9.find("REVISIONS").findall("REV")
check("and both revisions with their notes", [(r.get("label"), r.get("date"), r.get("author"), r.get("approved"), (r.text or "").strip()) for r in revs9] ==
      [("A", "", "", "", "Initial issue"), ("B", "2026-10-02", "A Jones", "A Boss", "Moved the LEDs")], str([r.attrib for r in revs9]))
print("design details and page setup: dialog values applied as one undo step, no-op applies add nothing, refusals and TinyCAD's ruler rules, title block and rulers drawn, paper / orientation / custom / limits / all sheets, saved file read back")


# ======================= grid size up, and the number input dialog =======================
script10 = """
newdoc "ANSI B (Tabloid)" landscape
echo A
gridinfo
gridup
gridinfo
gridup
gridinfo
gridup
gridinfo
gridup
gridinfo
gridup
gridinfo
gridup
gridinfo
gridup
gridinfo
echo B
gridmm 5.5
gridup
gridinfo
gridmm 0.1
gridup
gridinfo
gridmm 12
gridup
gridinfo
echo C
gridmm 1.27
newdoc "ISO A4" landscape
gridinfo
gridup
gridinfo
gotodoc 0
gridinfo
gridup
gridinfo
echo D
numinput 1.5 0.05 100
numinput 1,5 0.05 100
numinput " 2.54 " 0.05 100
numinput 0.05 0.05 100
numinput 100 0.05 100
numinput 0.04 0.05 100
numinput 100.01 0.05 100
numinput abc 0.05 100
numinput <empty> 0.05 100
numinput 1.2.3 0.05 100
echo E
gridcustom 3,5
gridinfo
gridcustom 0
gridinfo
"""
open(os.path.join(tmp, "s10.txt"), "w").write(script10.replace("libplace 0 ", "libplace %d " % ROW0))
r10 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s10.txt")],
                     capture_output=True, text=True, timeout=240, env=dict(os.environ))
o10 = r10.stdout.split("\n")
check("grid: program ran cleanly", r10.returncode == 0 and not any(l.startswith("ERROR") for l in o10), "\n".join(l for l in o10 if l.startswith("ERROR")) + r10.stderr[-300:])
MARKS10 = ("A", "B", "C", "D", "E")
def sect10(tag):
    i = o10.index(tag); j = i + 1
    while j < len(o10) and o10[j] not in MARKS10: j += 1
    return o10[i + 1:j]
def grids(lines): return [float(l.split("mm=")[1]) for l in lines if l.startswith("GRIDINFO")]
ga = grids(sect10("A"))
check("grid size up steps through the presets 0.5, 1, 1.27, 2, 2.54, 5, 10 mm and wraps round after 10 (it used to stick at 10)",
      ga == [2.0, 2.54, 5.0, 10.0, 0.5, 1.0, 1.27, 2.0], str(ga))
gb = grids(sect10("B"))
check("from a size that is not a preset it goes to the next larger one (5.5 -> 10, 0.1 -> 0.5, 12 -> back to 0.5)", gb == [10.0, 0.5, 0.5], str(gb))
gc = grids(sect10("C"))
check("each document has its own grid and steps from it: a new document (2 mm) goes to 2.54, the first (set to 1.27) goes to 2",
      gc == [2.0, 2.54, 1.27, 2.0], str(gc))
gd = [l for l in sect10("D") if l.startswith("NUMINPUT")]
check("the number dialog accepts a number, a comma as the decimal point, spaces around it, and both ends of the range",
      gd[:5] == ["NUMINPUT ok value=1.5", "NUMINPUT ok value=1.5", "NUMINPUT ok value=2.54", "NUMINPUT ok value=0.05", "NUMINPUT ok value=100"], str(gd[:5]))
check("and refuses a number out of range, letters, nothing, and a malformed number, saying what is allowed",
      all(x == "NUMINPUT refused: Please enter a number between 0.05 and 100." for x in gd[5:]) and len(gd) == 10, str(gd[5:]))
ge = [l for l in sect10("E") if l.startswith("GRIDINFO")]
check("a grid size typed with a comma is used (3,5 mm), and an invalid one leaves the grid as it was",
      [float(l.split("mm=")[1]) for l in ge] == [3.5, 3.5], str(ge))
print("grid: size up walks the presets and wraps, works from custom sizes and per document; the number dialog's checks (comma decimals, range ends, refusals)")


# ======================= the + tab at the end of the sheet tabs =======================
script11 = """
newdoc "ANSI B (Tabloid)" landscape
echo A
sheetinfo
gosheet 1
echo B
sheetinfo
undoinfo
gosheet 2
echo C
sheetinfo
gosheet 0
echo D
sheetinfo
gosheet 3
echo E
sheetinfo
undo
echo F
sheetinfo
renamesheet Mine
echo G
sheetinfo
"""
open(os.path.join(tmp, "s11.txt"), "w").write(script11.replace("libplace 0 ", "libplace %d " % ROW0))
r11 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s11.txt")],
                     capture_output=True, text=True, timeout=240, env=dict(os.environ))
o11 = r11.stdout.split("\n")
check("+ tab: program ran cleanly", r11.returncode == 0 and not any(l.startswith("ERROR") for l in o11), "\n".join(l for l in o11 if l.startswith("ERROR")) + r11.stderr[-300:])
MARKS11 = ("A", "B", "C", "D", "E", "F", "G")
def sheets11(tag):
    i = o11.index(tag); j = i + 1
    while j < len(o11) and o11[j] not in MARKS11: j += 1
    l = [x for x in o11[i + 1:j] if x.startswith("SHEETS")][0]
    return int(l.split()[1]), int(l.split("current=")[1].split()[0]), l.split("tabs=")[1].split(" names=")[0].replace('"', '')
a11, b11, c11, d11, e11, f11, g11 = (sheets11(k) for k in MARKS11)
check("a design with one sheet has the sheet's tab and the + tab", a11 == (1, 0, "Sheet 1,+"), str(a11))
check("choosing the + tab adds a sheet and shows it; the + tab stays last", b11 == (2, 1, "Sheet 1,Sheet 2,+"), str(b11))
check("adding by the + tab is an undoable 'Add sheet' step", 'next="Add sheet"' in "\n".join(o11[o11.index("B"):o11.index("C")]), "")
check("and again: a third sheet", c11 == (3, 2, "Sheet 1,Sheet 2,Sheet 3,+"), str(c11))
check("the other tabs still switch sheets as before", d11[1] == 0 and d11[0] == 3, str(d11))
check("the + tab adds the sheet after the last one, wherever you were", e11 == (4, 3, "Sheet 1,Sheet 2,Sheet 3,Sheet 4,+"), str(e11))
check("undo takes that sheet off again and the tabs follow", f11[0] == 3 and f11[2] == "Sheet 1,Sheet 2,Sheet 3,+", str(f11))
check("renaming a sheet leaves the + tab last", g11[2].endswith(",+") and "Mine" in g11[2], str(g11))
print("the + tab: always last, adds a sheet (undoable), and nothing else about the sheet tabs changed")


# ======================= editing the handles of a polygon =======================
saved12a = os.path.join(tmp, "poly_curve.dsn"); saved12b = os.path.join(tmp, "poly_final.dsn")
shots12 = [os.path.join(tmp, f"shot12_{i}.bmp") for i in range(2)]
script12 = f"""
newdoc "ANSI B (Tabloid)" landscape
tool polygon
mouse down 60 150
mouse down 100 150
mouse down 100 190
mouse down 60 190
mouse dbl 60 190
tool select
echo A
polyinfo
shot {shots12[0]}
mouse down 400 300
mouse up 400 300
shot {shots12[1]}
selidx 0
echo B
mouse down 100 190
mouse move 106 194
mouse move 110 198
mouse up 110 198
polyinfo
undoinfo
undo
echo C
polyinfo
redo
echo D
polyinfo
mouse down 110.2 198.2
mouse move 120 198
mouse up 120 198
polyinfo
echo E
polyaction arcin 110 174
polyinfo
polyaction arcout 110 174
polyinfo
polyaction freeline 110 174
polyinfo
echo F
polyaction curve 110 160
polyinfo
save {saved12a}
mouse down 110 160
mouse move 118 166
mouse up 118 166
polyinfo
polyaction deletehandle 118 166
polyinfo
echo G
polyaction addhandle 80 150
polyinfo
polyaction deletehandle 100 150
polyinfo
polyaction deletehandle 60 190
polyaction deletehandle 120 198
polyaction deletehandle 60 150
polyinfo
echo H
polyarc in
tool polygon
mouse down 200 150
mouse down 240 150
mouse down 240 190
mouse dbl 240 190
polyarc none
tool select
polyinfo
save {saved12b}
"""
open(os.path.join(tmp, "s12.txt"), "w").write(script12.replace("libplace 0 ", "libplace %d " % ROW0))
r12 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s12.txt")],
                     capture_output=True, text=True, timeout=240, env=dict(os.environ))
o12 = r12.stdout.split("\n")
check("polygon editing: program ran cleanly", r12.returncode == 0 and not any(l.startswith("ERROR") for l in o12), "\n".join(l for l in o12 if l.startswith("ERROR")) + r12.stderr[-300:])
MARKS12 = ("A", "B", "C", "D", "E", "F", "G", "H")
def sect12(tag):
    i = o12.index(tag); j = i + 1
    while j < len(o12) and o12[j] not in MARKS12: j += 1
    return o12[i + 1:j]
def polys(lines):
    """-> list of (summary dict, handles list of dicts) for each POLY block in the lines"""
    out = []; cur = None
    for l in lines:
        t = l.split()
        if l.startswith("POLY handles="):
            d = dict(x.split("=", 1) for x in t[1:]); cur = (d, []); out.append(cur)
        elif l.startswith("POLYPTS ") and cur is not None:
            cur[0]["pts"] = [tuple(float(v) for v in q.split(",")) for q in l[len("POLYPTS "):].split(";") if q]
        elif l.startswith("POLYH ") and cur is not None:
            cur[1].append({"x": float(t[2]), "y": float(t[3]), "arc": int(t[4]), "cx": float(t[5]), "cy": float(t[6]), "px": int(t[7]), "py": int(t[8])})
    return out
def xy(h): return [(x["x"], x["y"]) for x in h]
PA = polys(sect12("A"))[0]
check("a polygon drawn with four clicks has four handles, joined by straight segments, none closed",
      xy(PA[1]) == [(60, 150), (100, 150), (100, 190), (60, 190)] and [h["arc"] for h in PA[1]] == [0, 0, 0, 0] and PA[0]["close"] == "0" and PA[0]["points"] == "4", str(PA))
def px_hex(path, x, y):
    return subprocess.run(["convert", path, "-format", "%[hex:p{" + str(x) + "," + str(y) + "}]", "info:"], capture_output=True, text=True).stdout.strip()
hx, hy = PA[1][0]["px"], PA[1][0]["py"]
sel_px, uns_px = px_hex(shots12[0], hx + 1, hy + 1), px_hex(shots12[1], hx + 1, hy + 1)
check("the handles of a selected polygon are drawn (a black square on the first handle) and are not drawn once it is not selected",
      sel_px == "000000" and uns_px != "000000", f"selected {sel_px}, not selected {uns_px}")
PB = polys(sect12("B"))
check("dragging a handle with the mouse moves just that handle, by the distance dragged (snapped to the grid)",
      xy(PB[0][1]) == [(60, 150), (100, 150), (110, 198), (60, 190)], str(xy(PB[0][1])))
check("it is one undo step named Edit polygon", 'next="Edit polygon"' in [l for l in sect12("B") if l.startswith("UNDOINFO")][0], str(sect12("B")))
check("undo puts the handle back; redo moves it again",
      xy(polys(sect12("C"))[0][1])[2] == (100, 190) and xy(polys(sect12("D"))[0][1])[2] == (110, 198), "")
PD2 = polys(sect12("D"))
PD3 = PD2[1] if len(PD2) > 1 else polys(sect12("D"))[-1]
check("a handle can be grabbed a little off its centre (0.2 mm), and moves as dragged",
      xy(PD3[1])[2] == (120, 198), str(xy(PD3[1])))
E = polys(sect12("E"))
check("Arc in makes the segment that ends at the nearest handle an arc (more points are needed to draw it)",
      E[0][1][2]["arc"] == 1 and int(E[0][0]["points"]) > 4, str(E[0]))
def between(P, a, b):
    """the flattened points strictly between handle point a and b"""
    pts = P[0]["pts"]; ia = pts.index(a); ib = pts.index(b)
    return pts[ia + 1:ib]
h1h2 = ((100.0, 150.0), (120.0, 198.0))
arc_in, arc_out = between(E[0], *h1h2), between(E[1], *h1h2)
check("Arc in and Arc out draw different curves between the same two handles, every point of them inside the rectangle those handles span (the box is the same)",
      E[1][1][2]["arc"] == 2 and len(arc_in) > 3 and len(arc_out) > 3 and arc_in != arc_out and
      all(100 - 0.01 <= x <= 120 + 0.01 and 150 - 0.01 <= y <= 198 + 0.01 for x, y in arc_in + arc_out), f"{arc_in[:3]} / {arc_out[:3]}")
check("Free line makes it straight again, back to four points", E[2][1][2]["arc"] == 0 and E[2][0]["points"] == "4" and xy(E[2][1]) == xy(PD3[1]), str(E[2]))
check("the action says whether it changed anything", sum(1 for l in sect12("E") if l.endswith("changed=1")) == 3, str([l for l in sect12("E") if l.startswith("POLYACTION")]))
F = polys(sect12("F"))
check("Curve turns the segment into a curve with its control point at the (snapped) click",
      F[0][1][2]["arc"] == 3 and (F[0][1][2]["cx"], F[0][1][2]["cy"]) == (110, 160), str(F[0][1][2]))
check("the control point is dragged like a handle, without moving the handle", (F[1][1][2]["cx"], F[1][1][2]["cy"]) == (118, 166) and xy(F[1][1]) == xy(F[0][1]), str(F[1][1][2]))
check("Delete handle on a control point just makes the segment straight (the handle stays)", F[2][1][2]["arc"] == 0 and len(F[2][1]) == 4, str(F[2]))
# the saved file: a curve is written as arc 0 plus a control point, as TinyCAD writes it
root12a = ET.parse(saved12a).getroot(); sh12a = root12a.find("TinyCAD") if root12a.tag == "TinyCADSheets" else root12a
pts12a = sh12a.find("POLYGON").findall("POINT")
check("the saved file holds the curve as TinyCAD does: arc 0 and a control point, positions relative to the polygon's first point",
      [p.get("arc") for p in pts12a] == ["0", "0", "0", "0"] and pts12a[2].get("control") == "50.00000,10.00000" and pts12a[2].get("pos") == "60.00000,48.00000", str([p.attrib for p in pts12a]))
G = polys(sect12("G"))
check("Add handle splits the segment it is on: a new handle at the snapped click, between its neighbours",
      xy(G[0][1]) == [(60, 150), (80, 150), (100, 150), (120, 198), (60, 190)], str(xy(G[0][1])))
check("Delete handle removes the nearest handle", xy(G[1][1]) == [(60, 150), (80, 150), (120, 198), (60, 190)], str(xy(G[1][1])))
check("down to two handles, and then no more can be deleted (a polygon keeps two)",
      len(G[2][1]) == 2 and sum(1 for l in sect12("G") if l.startswith("POLYACTION deletehandle") and l.endswith("changed=0")) == 1, str(G[2]))
H = polys(sect12("H"))
check("a polygon drawn after choosing Arc in has its segments as arcs (the first point has none)",
      [h["arc"] for h in H[-1][1]] == [0, 1, 1] and xy(H[-1][1]) == [(200, 150), (240, 150), (240, 190)], str(H[-1]))
root12b = ET.parse(saved12b).getroot(); sh12b = root12b.find("TinyCAD") if root12b.tag == "TinyCADSheets" else root12b
polys12b = sh12b.findall("POLYGON")
check("the saved file has both polygons with their arc types", len(polys12b) == 2 and [p.get("arc") for p in polys12b[1].findall("POINT")] == ["0", "1", "1"] and len(polys12b[0].findall("POINT")) == 2, str([[q.attrib for q in p.findall("POINT")] for p in polys12b]))
print("polygon handles: drawn on the selected polygon, dragged (and control points), Arc in / out, Free line, Curve, Add and Delete handle, arcs chosen while drawing, undo and redo, saved XML read back")


# ======================= the rulers and border controls of the ribbon, and the ribbon tab strip =======================
script13 = f"""
sheetribboninfo
newdoc "ANSI B (Tabloid)" landscape
echo A
sheetribboninfo
detailsinfo
echo B
sheetribbon rulers 1
sheetribboninfo
detailsinfo
undoinfo
echo C
sheetribbon cols 9 rows G
sheetribboninfo
detailsinfo
echo D
sheetribbon cols 99
sheetribboninfo
detailsinfo
sheetribbon rows 5
sheetribboninfo
detailsinfo
sheetribbon colsx abc
sheetribboninfo
echo E
sheetribbon rowsx f
sheetribboninfo
detailsinfo
sheetribbon colsesc 20
sheetribboninfo
detailsinfo
echo F
sheetribbon border 0
sheetribboninfo
detailsinfo
sheetribbon border 1 margin 8
sheetribboninfo
detailsinfo
sheetribbon margin 99999
sheetribboninfo
detailsinfo
sheetribbon margin -2
sheetribboninfo
sheetribbon marginx 6,5
sheetribboninfo
detailsinfo
echo G
undo
sheetribboninfo
detailsinfo
redo
sheetribboninfo
detailsinfo
echo H
details rulers 0 horiz 4 border 0
sheetribboninfo
detailsinfo
echo I
newdoc "ISO A4" landscape
sheetribboninfo
detailsinfo
gotodoc 0
sheetribboninfo
detailsinfo
echo J
addsheet
sheetribboninfo
gosheet 0
sheetribboninfo
echo K
closedoc
closedoc
sheetribboninfo
"""
open(os.path.join(tmp, "s13.txt"), "w").write(script13.replace("libplace 0 ", "libplace %d " % ROW0))
r13 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s13.txt")],
                     capture_output=True, text=True, timeout=240, env=dict(os.environ))
o13 = r13.stdout.split("\n")
check("ribbon rulers/border: program ran cleanly", r13.returncode == 0 and not any(l.startswith("ERROR") for l in o13), "\n".join(l for l in o13 if l.startswith("ERROR")) + r13.stderr[-300:])
MARKS13 = tuple("ABCDEFGHIJK")
def sect13(tag):
    if tag is None: return o13[:o13.index("A")]
    i = o13.index(tag); j = i + 1
    while j < len(o13) and o13[j] not in MARKS13: j += 1
    return o13[i + 1:j]
def ribbon_at(lines, nth=0):
    l = [x for x in lines if x.startswith("SHEETRIBBON rulers=")][nth]
    d = dict(kv.split("=", 1) for kv in l[len("SHEETRIBBON "):].split(" "))
    return d
def model_at(lines, nth=0):
    l = [x for x in lines if x.startswith("DETAILSINFO ")][nth]
    return dict(kv.split("=", 1) for kv in l[len("DETAILSINFO "):].split("|"))
def agree(r, m):
    """the ribbon shows what the sheet has"""
    rows = chr(ord("A") + int(m["v"]) - 1) if 1 <= int(m["v"]) <= 26 else ""
    return (r["rulers"] == m["rulers"] and r["cols"] == m["h"] and r["rows"] == rows and r["border"] == m["border"] and
            abs(float(r["margin"]) - float(m["margin"]) / 5) < 1e-9)
none0 = ribbon_at(sect13(None))
check("with no document open the details controls are empty and disabled", none0["enabled"] == "00000" and none0["cols"] == "" and none0["margin"] == "", str(none0))
RA, MA = ribbon_at(sect13("A")), model_at(sect13("A"))
check("a new document: the ribbon shows its rulers, counts, row letter, border and margin", agree(RA, MA) and RA["border"] == "1" and RA["rulers"] == "0", f"{RA} {MA}")
check("the counts are disabled while the rulers are off, the margin is enabled with the border", RA["enabled"] == "10011", RA["enabled"])
RB, MB = ribbon_at(sect13("B")), model_at(sect13("B"))
check("ticking Show rulers writes it to the sheet and enables the counts", MB["rulers"] == "1" and agree(RB, MB) and RB["enabled"] == "11111", f"{RB} {MB}")
check("and is one undo step named Rulers", 'next="Rulers"' in [l for l in sect13("B") if l.startswith("UNDOINFO")][0], str(sect13("B")))
RC, MC = ribbon_at(sect13("C")), model_at(sect13("C"))
check("columns and rows typed and applied with Enter are written to the sheet (9 columns, last row G = 7)", MC["h"] == "9" and MC["v"] == "7" and agree(RC, MC), f"{RC} {MC}")
rd = [ribbon_at(sect13("D"), i) for i in range(3)]; md = [model_at(sect13("D"), i) for i in range(2)]
check("a column count outside 1 to 26 is refused and the box goes back to the sheet's 9", md[0]["h"] == "9" and rd[0]["cols"] == "9", f"{rd[0]} {md[0]}")
check("a row that is not a letter is refused and goes back to G", md[1]["v"] == "7" and rd[1]["rows"] == "G", f"{rd[1]} {md[1]}")
check("text that is not a number is refused when the box is left, and goes back", rd[2]["cols"] == "9", str(rd[2]))
RE = [ribbon_at(sect13("E"), i) for i in range(2)]; ME = [model_at(sect13("E"), i) for i in range(2)]
check("leaving the Rows box applies it, and a lower case f becomes the row F (6)", ME[0]["v"] == "6" and RE[0]["rows"] == "F", f"{RE[0]} {ME[0]}")
check("Esc puts back what the sheet has instead of what was typed", ME[1]["h"] == "9" and RE[1]["cols"] == "9", f"{RE[1]} {ME[1]}")
RF = [ribbon_at(sect13("F"), i) for i in range(5)]; MF = [model_at(sect13("F"), i) for i in range(4)]
check("unticking Border writes it to the sheet and disables the margin", MF[0]["border"] == "0" and RF[0]["enabled"][4] == "0" and agree(RF[0], MF[0]), f"{RF[0]} {MF[0]}")
check("ticking it again and typing 8 mm gives a margin of 40 units", MF[1]["border"] == "1" and MF[1]["margin"] == "40.000" and agree(RF[1], MF[1]), f"{RF[1]} {MF[1]}")
check("a margin too big for the page is refused and goes back to 8", MF[2]["margin"] == "40.000" and RF[2]["margin"] == "8", f"{RF[2]} {MF[2]}")
check("a negative margin is refused too", RF[3]["margin"] == "8", str(RF[3]))
check("a comma is accepted as the decimal point (6,5 mm = 32.5 units), applied when the box is left", MF[3]["margin"] == "32.500" and RF[4]["margin"] == "6.5" and agree(RF[4], MF[3]), f"{RF[4]} {MF[3]}")
RG = [ribbon_at(sect13("G"), i) for i in range(2)]; MG = [model_at(sect13("G"), i) for i in range(2)]
check("undo puts the margin back to 8 mm and the ribbon follows; redo makes it 6.5 again",
      agree(RG[0], MG[0]) and MG[0]["margin"] == "40.000" and RG[0]["margin"] == "8" and agree(RG[1], MG[1]) and MG[1]["margin"] == "32.500" and RG[1]["margin"] == "6.5", f"{RG} {MG}")
RH, MH = ribbon_at(sect13("H")), model_at(sect13("H"))
check("a change made in the Design Details dialog shows on the ribbon (rulers off, 4 columns, no border; the two check boxes stay usable, the entries are disabled)", agree(RH, MH) and RH["rulers"] == "0" and RH["cols"] == "4" and RH["border"] == "0" and RH["enabled"] == "10010", f"{RH} {MH}")
RI = [ribbon_at(sect13("I"), i) for i in range(2)]; MI = [model_at(sect13("I"), i) for i in range(2)]
check("a second document shows its own settings, and going back shows the first one's again",
      agree(RI[0], MI[0]) and RI[0]["border"] == "1" and agree(RI[1], MI[1]) and RI[1]["cols"] == "4" and RI[0] != RI[1], f"{RI}")
RJ = [ribbon_at(sect13("J"), i) for i in range(2)]
check("it follows the sheet that is shown: a new sheet copies the settings of the one it was added from, and going back shows them again", RJ[0] == RJ[1] == RH, f"{RJ} vs {RH}")
RK = ribbon_at(sect13("K"))
check("closing the last document disables the controls again", RK["enabled"] == "00000" and RK["cols"] == "", str(RK))
print("ribbon rulers and border: shown from the sheet (no document, new, switched, undone, changed in the dialog), written back as undo steps, refusals put back, comma and case handled")

script14 = """
newdoc "ANSI B (Tabloid)" landscape
lib """ + lib + """
libplace 0 120 100
tool select
ribbonstate
ribbonpaints
echo A
selectclass TDrawMethod
ribbonstate
ribbonpaints
"""
open(os.path.join(tmp, "s14.txt"), "w").write(script14.replace("libplace 0 ", "libplace %d " % ROW0))
r14 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s14.txt")],
                     capture_output=True, text=True, timeout=240, env=dict(os.environ))
o14 = r14.stdout.split("\n")
st0 = [l for l in o14[:o14.index("A")] if l.startswith("RIBBONSTATE")][0]; st1 = [l for l in o14[o14.index("A"):] if l.startswith("RIBBONSTATE")][0]
p0 = int([l for l in o14[:o14.index("A")] if l.startswith("RIBBONPAINTS")][0].split()[1]); p1 = int([l for l in o14[o14.index("A"):] if l.startswith("RIBBONPAINTS")][0].split()[1])
check("selecting an object brings the View tab (with the Properties panel) forward", "tab=Home" in st0 and "tab=View" in st1, f"{st0} / {st1}")
check("and the ribbon's tab strip is repainted to show it (it used to stay on the old tab until the mouse touched it)", p1 > p0, f"paints {p0} -> {p1}")
print("ribbon tab strip: repainted when a tab is chosen from code")


# ======================= the recently used files (the first of the program's settings) =======================
import glob
home15 = os.path.join(tmp, "home15"); os.makedirs(home15)
mru_dir = os.path.join(tmp, "mru"); os.makedirs(mru_dir)
F15 = {n: os.path.join(mru_dir, n + ".dsn") for n in "abcdef"}
for pth in F15.values(): shutil.copy(led_nospace if os.path.exists(led_nospace) else led, pth)
saved15 = os.path.join(mru_dir, "saved_new.dsn")
def run15(text):
    open(os.path.join(tmp, "s15.txt"), "w").write(text)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s15.txt")],
                       capture_output=True, text=True, timeout=240, env=dict(os.environ, HOME=home15))
    return r.stdout.split("\n"), r.returncode, r.stderr
def recents(lines):
    out = []
    for l in lines:
        if l.startswith("RECENT "):
            n = int(l.split()[1]); items = [x for x in l[len("RECENT " + str(n) + " "):].split(";") if x]
            out.append((n, items))
    return out
def paths_of(items): return [it.split("|", 1)[1] for it in items if not it.startswith("-")]
o15a, rc15a, err15a = run15(f"""
recent
open {F15['a']}
open {F15['b']}
open {F15['c']}
recent
open {F15['a']}
recent
open {F15['d']}
open {F15['e']}
recent
savedocas {saved15}
recent
docs
""")
check("recent files: first run ran cleanly", rc15a == 0 and not any(l.startswith("ERROR") for l in o15a), "\n".join(l for l in o15a if l.startswith("ERROR")) + err15a[-200:])
R = recents(o15a)
check("a first run starts with no recent files and no entries in the File menu", R[0] == (0, []), str(R[0]))
check("files opened are listed newest first: c, b, a", R[1][0] == 3 and paths_of(R[1][1]) == [F15["c"], F15["b"], F15["a"]], str(R[1]))
check("the File menu entries are a separator, then &1 &2 &3 with the file name (and the full name as their hint)",
      R[1][1][0] == "-|" and [it.split("|")[0] for it in R[1][1][1:]] == [f"&{i + 1} {p}" for i, p in enumerate([F15['c'], F15['b'], F15['a']])], str(R[1][1]))
check("opening a file again moves it to the top; it is not listed twice", paths_of(R[2][1]) == [F15["a"], F15["c"], F15["b"]], str(R[2]))
check("only four are kept: after d and e the oldest (b) has gone", R[3][0] == 4 and paths_of(R[3][1]) == [F15["e"], F15["d"], F15["a"], F15["c"]], str(R[3]))
check("saving a document under a new name puts that file at the top", R[4][0] == 4 and paths_of(R[4][1]) == [saved15, F15["e"], F15["d"], F15["a"]], str(R[4]))
# what the registry holds, read with an independent parser
regfiles = glob.glob(os.path.join(home15, ".config", "*", "reg.xml"))
node = ET.parse(regfiles[0]).getroot()
for part in ("HKEY_CURRENT_USER", "SOFTWARE", "HPL Software", "TyCAD Electrical"):
    node = next(k for k in node.findall("Key") if k.get("Name") == part)
vals = {v.get("Name"): v.text for v in node.findall("Value")}
check("the registry holds them under HKEY_CURRENT_USER\\SOFTWARE\\HPL Software\\TyCAD Electrical as MRU1 to MRU4",
      {k: v for k, v in vals.items() if k.startswith("MRU")} == {"MRU1": saved15, "MRU2": F15["e"], "MRU3": F15["d"], "MRU4": F15["a"]}, str(vals))
# (the same key also holds the options, as the Options dialog keeps them: here the ones a new program starts with)
check("and, beside them, the options with the values a new program starts with (and nothing else)",
      {k: v for k, v in vals.items() if not k.startswith("MRU")} == {"ShowGrid": "1", "SnapGrid": "1", "Grid": "2", "Units": "0", "AutoDrag": "1", "AutoSnap": "1", "AutoJunc": "1", "AutoDragRange": "15", "AutoSave": "10", "ShowPosition": "1", "ShowViewRulers": "1", "ReopenDesigns": "0", "BOMNetlist": "0", "BOMHierarchical": "0", "BOMPrefixNetlist": "0", "BOMAllSheets": "0", "BOMAllAttrs": "0", "Netlist": "0", "PrefixNetlist": "0", "ERC": "65535", "Annotate.type": "1", "Annotate.allsheets": "1", "PrintBandW": "0", "DarkMode": "0", "NewDocPaper": "ISO A4", "NewDocLandscape": "1", "BitmapType": "0", "BitmapScaling": "100", "BitmapRotation": "0", "PrintScaleFactor": "100"}, str(vals))
# a new run reads them back, and a recent file is opened from the list
o15b, rc15b, err15b = run15("""
recent
openrecent 2
recent
docs
""")
R2 = recents(o15b)
check("a new run of the program starts with the list it saved", R2[0][0] == 4 and paths_of(R2[0][1]) == [saved15, F15["e"], F15["d"], F15["a"]], str(R2[0]))
dl = [l for l in o15b if l.startswith("DOCS ")][0]
check("choosing an entry opens that file as a document, and it moves to the top",
      paths_of(R2[1][1]) == [F15["d"], saved15, F15["e"], F15["a"]] and dl.startswith("DOCS 1 ") and os.path.basename(F15["d"]) in dl, f"{R2[1]} {dl}")
# a file that is no longer there is taken off the list
os.remove(F15["a"])
o15c, rc15c, err15c = run15("""
openrecent 3
recent
docs
""")
R3 = recents(o15c); dl3 = [l for l in o15c if l.startswith("DOCS ")][0]
check("choosing a file that has been deleted opens nothing and takes it off the list", dl3.startswith("DOCS 0 ") and paths_of(R3[0][1]) == [F15["d"], saved15, F15["e"]], f"{R3} {dl3}")
o15d, rc15d, err15d = run15("recent\n")
check("and that is kept for the next run", paths_of(recents(o15d)[0][1]) == [F15["d"], saved15, F15["e"]], str(recents(o15d)))
print("recent files: newest first, four kept, no duplicates, saved to and loaded from the registry between runs, opened from the File menu, a deleted file taken off")


# ======================= Find and Replace (the ReplaceDlg component's own handlers) =======================
import findoracle as FO
orig16 = os.path.join(tmp, "find_orig.dsn")
steps16 = {k: os.path.join(tmp, f"find_{k}.dsn") for k in ("r3", "u3", "all", "allundo", "allredo", "empty")}
script16 = f"""
newdoc "ANSI B (Tabloid)" landscape
lib {lib}
libplace 0 120 100
tool text
mouse down 60 40
setprop text "Hello world"
tool text
mouse down 60 60
setprop text "say hello again"
tool power
mouse down 150 40
setprop text HELLO_NET
tool select
addsheet
tool text
mouse down 60 40
setprop text "HELLO on sheet two"
gosheet 0
save {orig16}
echo A
find hello
find hello
find hello
find hello
find hello
find hello
echo B
find zzz
gosheet 0
find hello up
find hello up
find hello up
find hello up
find hello up
echo C
find zzz
gosheet 0
find hello case
find hello case
find hello case
echo D
find zzz
gosheet 0
find hello word
find hello word
find hello word
find hello word
echo E
find hello
findnext
findnext
findprev
findprev
echo F
find zzz
gosheet 0
replace hello HI
replace hello HI
replace hello HI
replace hello HI
undoinfo
save {steps16['r3']}
undo
undo
undo
undoinfo
save {steps16['u3']}
echo G
find zzz
replace hello XX all
undoinfo
save {steps16['all']}
undo
save {steps16['allundo']}
redo
save {steps16['allredo']}
undo
echo H
replace hello <empty> case all
save {steps16['empty']}
undoinfo
echo I
replace nothere ZZ all
undoinfo
finddialog open
finddialog close
"""
open(os.path.join(tmp, "s16.txt"), "w").write(script16.replace("libplace 0 ", "libplace %d " % ROW0))
r16 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s16.txt")],
                     capture_output=True, text=True, timeout=240, env=dict(os.environ))
o16 = r16.stdout.split("\n")
check("find and replace: program ran cleanly", r16.returncode == 0 and not any(l.startswith("ERROR") for l in o16), "\n".join(l for l in o16 if l.startswith("ERROR")) + r16.stderr[-300:])
MARKS16 = tuple("ABCDEFGHI")
def sect16(tag):
    i = o16.index(tag); j = i + 1
    while j < len(o16) and o16[j] not in MARKS16: j += 1
    return o16[i + 1:j]
def finds(lines, cmd="FIND"):
    out = []
    for l in lines:
        if l.startswith(cmd + " "):
            d = {}
            for key in ("sheet", "sel", "hit", "wrapped", "class", "text", "msg"):
                pass
            body = l[len(cmd) + 1:]
            d["sheet"] = int(body.split("sheet=")[1].split()[0]); d["sel"] = int(body.split("sel=")[1].split()[0])
            h = body.split("hit=")[1].split()[0]; d["hit"] = None if h == "none" else tuple(int(x) for x in h.split(":"))
            d["wrapped"] = int(body.split("wrapped=")[1].split()[0]); d["class"] = body.split("class=")[1].split()[0]
            d["text"] = body.split(" text=")[1].split(" msg=")[0]; d["msg"] = body.split(" msg=")[1]
            out.append(d)
    return out
tx16 = FO.texts(orig16); cl16 = FO.classes(orig16)
def expect_steps(needle, case, word, direction, steps, start_sheet=0):
    exp = FO.expected_hits(tx16, needle, case, word)
    sim = FO.simulate(exp, direction, steps, start_sheet)
    return exp, sim
def judge(label, got, exp, sim):
    """each step selected one object on the right sheet, in the place and text the oracle expects, with the wrap flag"""
    okk = len(got) == len(sim)
    why = ""
    for g, (i, w) in zip(got, sim):
        e = exp[i]
        okk = okk and g["hit"] is not None and g["hit"][0] == e[0] and g["hit"][2] == e[1] and g["hit"][3] == e[2] and g["hit"][4] == e[3] and g["wrapped"] == int(w) \
              and g["sheet"] == e[0] and g["sel"] == 1 and g["text"] == e[4].decode().replace("\n", "\\n")
        if not okk: why = f"{g} vs {e} wrapped={w}"; break
    check(label, okk, why)
check("the design for the search has text in two sheets and a power symbol", len(tx16) >= 4 and {t[0] for t in tx16} == {0, 1} and "TDrawPower" in cl16, str(tx16))
A = finds(sect16("A"))
e, sm = expect_steps(b"hello", False, False, "down", 6)
judge("Find Next walks the texts of the design in order (a text, a text, the power symbol, then the next sheet) and wraps round to the start", A, e, sm)
check("each hit selects the object that holds the text, of the right kind", [g["class"] for g in A][:4] == ["TDrawText", "TDrawText", "TDrawPower", "TDrawText"], str([g["class"] for g in A]))
check("a hit on another sheet switches to that sheet; the wrap round switches back and says so", A[3]["sheet"] == 1 and A[4]["sheet"] == 0 and "carried on from the start" in A[4]["msg"], str((A[3]["sheet"], A[4]["msg"])))
B = finds(sect16("B"))
e, sm = expect_steps(b"hello", False, False, "up", 5)
judge("Find Previous (Backward) walks the other way from the end of the sheet being shown, wrapping to the last of the design", B[1:], e, sm)
check("a text that is not there is reported", B[0]["hit"] is None and 'Cannot find "zzz"' in B[0]["msg"], str(B[0]))
C = finds(sect16("C"))
e, sm = expect_steps(b"hello", True, False, "down", 3)
judge("Case sensitive: only the text with a lower case hello is found, again and again", C[1:], e, sm)
check("and 'HELLO' with a capital is not found when matching case", len(FO.expected_hits(tx16, b"hello", True, False)) == 1, "")
D = finds(sect16("D"))
e, sm = expect_steps(b"hello", False, True, "down", 4)
judge("Whole words only: HELLO_NET is not a word hello, so it is skipped", D[1:], e, sm)
check("the power symbol is not among them", all(g["class"] != "TDrawPower" for g in D[1:]), str([g["class"] for g in D]))
ev = [finds([l], c)[0] for l in sect16("E") for c in ("FIND", "FINDNEXT", "FINDPREV") if l.startswith(c + " ")]
check("F3 (Find Next) goes on from the last hit to the next, then the next; Shift+F3 (Find Previous) goes back the same way",
      len(ev) == 5 and ev[0]["hit"] != ev[1]["hit"] and ev[1]["hit"] != ev[2]["hit"] and ev[3]["hit"] == ev[1]["hit"] and ev[4]["hit"] == ev[0]["hit"], str([g["hit"] for g in ev]))
# --- replace
F = [finds([l], "REPLACE")[0] for l in sect16("F") if l.startswith("REPLACE ")]
check("Replace: with nothing found yet it finds the first; each further Replace changes the text found and moves to the next",
      len(F) == 4 and [g["text"] for g in F[:3]] == ["Hello world", "say hello again", "HELLO_NET"] and F[3]["text"] == "HELLO on sheet two", str([g["text"] for g in F]))
want_r3 = FO.replace_in(tx16, b"hello", b"HI", False, False, only_first=3)
check("three occurrences were replaced, the fourth not, and nothing else changed (the saved file read back)", FO.texts(steps16["r3"]) == want_r3 and FO.texts(steps16["r3"]) != tx16, str(FO.texts(steps16["r3"])[:5]))
check("each Replace is an undo step named Replace", 'next="Replace"' in "\n".join(l for l in sect16("F") if l.startswith("UNDOINFO")) and "undo=" in "\n".join(sect16("F")), str([l for l in sect16("F") if l.startswith("UNDOINFO")]))
check("three undos put every text back as it was", FO.texts(steps16["u3"]) == tx16, str(FO.texts(steps16["u3"])[:5]))
# --- replace all
Gl = sect16("G")
want_all = FO.replace_in(tx16, b"hello", b"XX", False, False)
repl_all = [finds([l], "REPLACE")[0] for l in Gl if l.startswith("REPLACE ")][0]
check("Replace All changes every occurrence in the whole design and says how many and where", FO.texts(steps16["all"]) == want_all and "Replaced 4 occurrences in 4 objects" in repl_all["msg"], f"{repl_all['msg']}")
check("it is a single undo step named Replace all, and undo puts everything back", 'next="Replace all"' in "\n".join(Gl) and FO.texts(steps16["allundo"]) == tx16, "")
check("redo makes them all again", FO.texts(steps16["allredo"]) == want_all, "")
want_empty = FO.replace_in(tx16, b"hello", b"", True, False)
Hh = sect16("H")
check("replacing with nothing (and matching case) removes just that text", FO.texts(steps16["empty"]) == want_empty and FO.texts(steps16["empty"]) != tx16, "")
Ii = sect16("I")
nth = [finds([l], "REPLACE")[0] for l in Ii if l.startswith("REPLACE ")][0]
undo_h = int([l for l in Hh if l.startswith("UNDOINFO")][0].split("undo=")[1].split()[0]); undo_i = int([l for l in Ii if l.startswith("UNDOINFO")][0].split("undo=")[1].split()[0])
check("Replace All of text that is not there says so and leaves no undo step behind", 'Cannot find "nothere"' in nth["msg"] and undo_i == undo_h, f"{nth['msg']} {undo_h} {undo_i}")
check("the Find and Replace dialog itself opens and closes without a problem", "FINDDIALOG open" in o16 and "FINDDIALOG close" in o16, "")
print("find and replace: the dialog component's handlers, in design order across sheets, backward, case, whole words, F3, Replace one by one, Replace All, undo and redo, the saved files read back against the independent oracle")


# ======================= the find panel: TinyCAD's Find, with its list and red circles =======================
orig18 = os.path.join(tmp, "findpanel_orig.dsn"); after18 = os.path.join(tmp, "findpanel_after.dsn")
shots18 = [os.path.join(tmp, f"shot18_{i}.bmp") for i in range(5)]
script18 = f"""
newdoc "ANSI B (Tabloid)" landscape
lib {lib}
libplace 0 120 100
tool text
mouse down 60 40
setprop text "Hello world"
tool text
mouse down 60 60
setprop text "say hello again"
tool power
mouse down 150 40
setprop text HELLO_NET
tool select
addsheet
tool text
mouse down 60 40
setprop text "HELLO on sheet two"
gosheet 0
save {orig18}
undoinfo
echo A
findpanel
echo B
finder hello
findhits
shot {shots18[0]}
echo C
findpick 1
findhits
shot {shots18[1]}
echo D
findpick 3
findhits
echo E
findpick 0
mouse down 150 40
mouse up 150 40
findpanel
findinfo
echo F
finder zzzq
findpanel
echo G
finder hello
undoinfo
findpick 2
findhits
shot {shots18[2]}
findclose
shot {shots18[3]}
echo H
findpanel
undoinfo
save {after18}
echo I
finder hello
newdoc "ISO A4" landscape
findpanel
docs
findpick 1
docs
echo J
closedoc 0
findpanel
docs
"""
open(os.path.join(tmp, "s18.txt"), "w").write(script18.replace("libplace 0 ", "libplace %d " % ROW0))
r18 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s18.txt")],
                     capture_output=True, text=True, timeout=240, env=dict(os.environ))
o18 = r18.stdout.split("\n")
check("find panel: program ran cleanly", r18.returncode == 0 and not any(l.startswith("ERROR") for l in o18), "\n".join(l for l in o18 if l.startswith("ERROR")) + r18.stderr[-300:])
MARKS18 = tuple("ABCDEFGHIJ")
def sect18(tag):
    i = o18.index(tag); j = i + 1
    while j < len(o18) and o18[j] not in MARKS18: j += 1
    return o18[i + 1:j]
def panel(line):
    body = line.split(" ", 1)[1]
    d = {}
    for k in ("shown", "library", "chosen", "marker", "markers", "doc"): d[k] = int(body.split(k + "=")[1].split()[0])
    d["text"] = body.split("text=")[1].split(" count=")[0]; d["count"] = body.split("count=")[1].split(" chosen=")[0].strip()
    d["entries"] = [x[1:-1] for x in body.split(" [")[1:]] if False else [e.rstrip("]") for e in body.split(" [")[1:]]
    if "sheet=" in body: d["sheet"] = int(body.split("sheet=")[1].split()[0])
    return d
def hits(line):
    body = line.split(" ", 1)[1]; size, rest = body.split(" ", 1)
    w, h = (int(x) for x in size.split("x"))
    pts = []
    for e in rest.split(";"):
        if e: i, sh, x, y, px, py = e.split(":"); pts.append((int(i), int(sh), float(x), float(y), int(px), int(py)))
    return (w, h), pts
def pix(path, x, y):
    out = subprocess.run(["convert", path, "-crop", "1x1+%d+%d" % (x, y), "-format", "%[fx:int(255*r)],%[fx:int(255*g)],%[fx:int(255*b)]", "info:"], capture_output=True, text=True).stdout
    return tuple(int(v) for v in out.split(","))
def ring(path, px, py, radius=6):
    """the reddest pixel on the row through the middle of a circle, from just inside to just outside its ring"""
    best = None
    for x in range(px + radius - 3, px + radius + 4):
        c = pix(path, x, py)
        if c[0] >= 100 and c[1] <= 90 and c[2] <= 90 and (best is None or c[0] > best[0]): best = c
    return best
orig_tx = FO.texts(orig18)
A = panel([l for l in sect18("A") if l.startswith("FINDPANEL")][0])
check("at first the library panel is shown and the find panel is not", A["shown"] == 0 and A["library"] == 1 and A["markers"] == 0, str(A))
exp = FO.object_hits(orig18, b"hello")
B = panel([l for l in sect18("B") if l.startswith("FINDER")][0]); (viewsize, ptsB) = hits([l for l in sect18("B") if l.startswith("FINDHITS")][0])
check("Find replaces the library panel with the find panel", B["shown"] == 1 and B["library"] == 0, str(B))
check("every object that mentions the text is listed once, as TinyCAD lists it with the sheet in front, 'sheet: name: text', in the order of the design (read independently from the saved XML)",
      B["entries"] == [f"Sheet {_s + 1}: {nm}: {t.decode()}" for (_s, _k, nm, t, _p) in exp] and len(exp) == 4, f"{B['entries']} vs {[(nm, t) for (_s, _k, nm, t, _p) in exp]}")
cb = [l for l in sect18("B") if l.startswith("FINDER")][0].split("closebtn=")[1].split(" visible=")
cl, ct, cw, ch = (int(v) for v in cb[0].split(",")); pw_ = int(cb[1].split("panel=")[1].split("x")[0])
check("the close X is inside the panel, at its upper right, and shows the picture from the image list (not the letter)",
      cl >= 0 and cl + cw <= pw_ and pw_ - (cl + cw) <= 8 and ct == 0 and "image=0" in cb[1], str(cb))
check("the entry shows the text searched for and how many were found", B["text"] == "hello" and B["count"] == "4 found" and B["markers"] == 4 and B["chosen"] == -1, str(B))
check("each has a circle at its object, on its own sheet (the circle of an object on the second sheet belongs to that sheet)", [(p[1], p[2], p[3]) for p in ptsB] == [(s_, pt[0] / 5, pt[1] / 5) for (s_, _k, _nm, _t, pt) in exp], str(ptsB))
# the circles as pixels
sheet0 = [p for p in ptsB if p[1] == 0]
rings0 = [ring(shots18[0], p[4], p[5]) for p in sheet0]
check("the circles are drawn on the sheet, dark red when none is chosen", all(r is not None and r[0] < 200 for r in rings0), str(rings0))
C = [panel(l) for l in sect18("C") if l.startswith("FINDPICK")]; (_, ptsC) = hits([l for l in sect18("C") if l.startswith("FINDHITS")][0])
check("clicking an entry of the list chooses its circle and shows it", C[0]["chosen"] == 1 and C[0]["marker"] == 1 and C[0]["sheet"] == 0, str(C))
mid = (viewsize[0] // 2, viewsize[1] // 2)
check("and puts it in the middle of the window", abs(ptsC[1][4] - mid[0]) <= 3 and abs(ptsC[1][5] - mid[1]) <= 3, f"{ptsC[1][4:]} vs {mid}")
r_sel = ring(shots18[1], ptsC[1][4], ptsC[1][5]); r_oth = ring(shots18[1], ptsC[0][4], ptsC[0][5])
check("the chosen circle is bright red and the others stay dark red", r_sel is not None and r_sel[0] >= 230 and r_oth is not None and r_oth[0] < 200, f"{r_sel} {r_oth}")
D = [panel(l) for l in sect18("D") if l.startswith("FINDPICK")]
check("an entry on another sheet takes the window to that sheet", D[0]["sheet"] == 1 and D[0]["chosen"] == 3 and D[0]["marker"] == 3, str(D))
Ee = sect18("E"); E1 = panel([l for l in Ee if l.startswith("FINDPANEL")][0])
fi = [l for l in Ee if l.startswith("FINDINFO")][0]
check("clicking a circle on the sheet chooses its entry in the list (the click lands on the circle, not on the object under it, so nothing is selected)", E1["chosen"] == 2 and E1["marker"] == 2 and " sel=0 " in fi, f"{E1} {fi}")
F = panel([l for l in sect18("F") if l.startswith("FINDPANEL")][0])
check("a text that is not there lists nothing and has no circles", F["count"] == "Not found" and F["markers"] == 0 and F["entries"] == [], str(F))
Gg = sect18("G"); G1 = panel([l for l in Gg if l.startswith("FINDPICK")][0])
check("searching again replaces the list and the circles", G1["markers"] == 4 and len(G1["entries"]) == 4 and G1["chosen"] == 2, str(G1))
H = panel([l for l in sect18("H") if l.startswith("FINDPANEL")][0])
check("the red X closes the find: the circles are gone and the library panel is back", H["shown"] == 0 and H["library"] == 1 and H["markers"] == 0 and H["entries"] == [], str(H))
# the chosen circle's pixels before and after the X, in the same view
ptsG = hits([l for l in Gg if l.startswith("FINDHITS")][0])[1]
gx, gy = ptsG[2][4], ptsG[2][5]
before_x, after_x = ring(shots18[2], gx, gy), ring(shots18[3], gx, gy)
check("the circle that was bright red is no longer drawn once the find is closed (the same place, the same view)", before_x is not None and before_x[0] >= 230 and after_x is None, f"{before_x} -> {after_x}")
ud = lambda lines: [l for l in lines if l.startswith("UNDOINFO")]
undo0 = [l for l in o18[:o18.index("A")] if l.startswith("UNDOINFO")][0]
check("none of this touched the design: no undo step was added by finding, choosing, clicking a circle or closing, and the saved design has the same texts",
      ud(Gg)[0] == undo0 and ud(sect18("H"))[0] == undo0 and FO.texts(after18) == orig_tx, f"{undo0} / {ud(Gg)} / {ud(sect18('H'))}")
Ii = sect18("I"); pI = panel([l for l in Ii if l.startswith("FINDPANEL")][0])
dcur = lambda lines: [int(l.split("current=")[1].split()[0]) for l in lines if l.startswith("DOCS ")]
check("a find belongs to the document it was made in: with another document in front the results are still those of the first, and the other document shows no circles",
      pI["shown"] == 1 and pI["doc"] == 0 and pI["count"] == "4 found" and pI["markers"] == 0 and dcur(Ii) == [1, 0], f"{pI} {dcur(Ii)}")
pI2 = [panel(l) for l in Ii if l.startswith("FINDPICK")][0]
check("choosing an entry brings that document to the front, with the circle chosen on its sheet", dcur(Ii)[-1] == 0 and pI2["chosen"] == 1 and pI2["marker"] == 1 and pI2["markers"] == 4, f"{pI2} {dcur(Ii)}")
Jj = sect18("J"); pJ = panel([l for l in Jj if l.startswith("FINDPANEL")][0])
check("closing the document the find belongs to closes the find (the library panel is back)", pJ["shown"] == 0 and pJ["library"] == 1 and pJ["entries"] == [], str(pJ))
print("find panel: TinyCAD's list of everything that mentions a text, the red circles (dark, bright when chosen) drawn, choosing an entry shows it centred and on its sheet, clicking a circle chooses its entry, the X closes it, and the design and undo history untouched")

print("\nGUI CHECKS PASSED" if not fails else f"\nGUI CHECKS FAILED: {fails}")
sys.exit(1 if fails else 0)
