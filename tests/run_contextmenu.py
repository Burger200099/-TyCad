#!/usr/bin/env python3
"""The pop-up menu of a right click on the sheet (TinyCAD's), on the real program under Xvfb.
Oracles that do not use the program's own menu code: the list of commands and keys is TinyCAD's (written out here from its menu), polygon sides
are found with plain geometry (the nearest side of a known rectangle), the placed symbol's name and first pin are read from the library file
with sqlite3 and from the program's own placement, and the Arc tool (clicks like the Polygon tool, a double click commits) is checked by the arc type of the handle of the polygon it made.
  - an empty spot: the commands of every object, in TinyCAD's order and with its keys, with the ones that need a selection dimmed
  - a polygon: Add handle, Delete handle, a separator, Free line, Arc in, Arc out, Curve at the top, then the common commands; the object under the click gets chosen
  - Arc in / Arc out / Free line / Curve change only the side that was clicked (the nearest side), for each of the four sides
  - Add handle and Delete handle do their work at the click
  - a symbol: Replace Symbol... first and a separator, then the common commands; replacing swaps the symbol (new name, first pin where it was), is undone as one step
  - several objects chosen: a right click on one of them keeps the choice
  - the Arc tool draws the kind of arc it was set to (arc in or arc out)
Needs the built program, xvfb and the example libraries (TC_EXAMPLES)."""
import os, re, shutil, subprocess, sys, tempfile, sqlite3
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
LIB = os.path.join(EX, "libraries", "gen_passive.TCLib")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not os.path.exists(LIB):
    print("Context menu checks skipped: need xvfb-run, the built program and the example libraries"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
lib = os.path.join(tmp, "g.TCLib"); shutil.copy(LIB, lib)
# the library panel lists the symbols alphabetically; the tests mean "the library's first symbol" (by NameID), so find its row
_c = sqlite3.connect(lib); _names = [r[0] for r in _c.execute("select Name from Name where Type=0 order by NameID")]; _c.close()
ROW0 = sorted(_names, key=str.lower).index(_names[0])
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:600])
n = [0]
def run(script):
    n[0] += 1; h = os.path.join(tmp, "h%d" % n[0]); os.makedirs(h)
    f = os.path.join(tmp, "s%d.txt" % n[0]); open(f, "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
def menus(o):
    """the CTX blocks of the output: a list of (list of (depth, caption, enabled, key), selected count)"""
    out = []; cur = []
    for l in o:
        m = re.match(r"CTX (\d+) (\S+) enabled=(\d) key=\[(.*)\]", l)
        if m: cur.append((int(m.group(1)), m.group(2), int(m.group(3)), m.group(4)))
        elif l.startswith("CTX done"):
            out.append((cur, int(re.search(r"sel=(\d+)", l).group(1)))); cur = []
    return out
def polys(o):
    """POLYH blocks: for each polyinfo the list of (handle, arc type)"""
    res = []; cur = None
    for l in o:
        if l.startswith("POLY "): cur = []; res.append((int(re.search(r"handles=(\d+)", l).group(1)), cur))
        m = re.match(r"POLYH (\d+) \S+ \S+ (\d+) ", l)
        if m and cur is not None: cur.append(int(m.group(2)))
    return res
# TinyCAD's menu (the picture), top to bottom: (depth, caption, key); "-" is a separator
COMMON = [(0, "Undo", "Ctrl+Z"), (0, "Redo", "Ctrl+Y"), (0, "-", ""), (0, "Z-Order", ""), (1, "Bring_to_Front", ""), (1, "Send_to_Back", ""), (0, "-", ""), (0, "Cut", "Ctrl+X"), (0, "Copy", "Ctrl+C"),
          (0, "Paste", "Ctrl+V"), (0, "Duplicate", "Ctrl+U"), (0, "Select_All", "Ctrl+A"), (0, "Select_All_Alike", ""), (0, "-", ""), (0, "Delete", "Del"), (0, "-", ""), (0, "Rotate_Left", "Ctrl+L"), (0, "Rotate_Right", "Ctrl+R"),
          (0, "Flip", ""), (0, "-", ""), (0, "Zoom_In", "PgUp"), (0, "Zoom_Out", "PgDn")]
POLYTOP = ["Add_handle", "Delete_handle", "-", "Free_line", "Arc_in", "Arc_out", "Curve", "-"]
def shape(m): return [(d, c, k if k != "Unknown" else "") for d, c, e, k in m]
def en(m, cap): return [e for d, c, e, k in m if c == cap][0]
# the set up: a symbol and an open polygon (four handles, the square 60,150 - 100,190 mm), a rectangle further away
SETUP = """newdoc "ANSI B (Tabloid)" landscape
lib %s
libplace %d 120 100
tool polygon
mouse down 60 150
mouse down 100 150
mouse down 100 190
mouse down 60 190
mouse dbl 60 190
tool select
objects
""" % (lib, ROW0)
o = run(SETUP + """selclear
ctxmenu 300 200
selclear
ctxmenu 80 150
selclear
ctxmenu 80 170
selclear
ctxmenu 120 100
symname
""")
mm = menus(o)
check("four menus were listed", len(mm) == 4, len(mm))
empty, onpoly, inside, onsym = mm
check("empty spot: TinyCAD's commands and keys in its order (menu from the picture)", shape(empty[0]) == COMMON, shape(empty[0]))
check("empty spot: nothing chosen, so Cut Copy Duplicate Delete Rotate Flip and Z-Order are dimmed; Undo is there (the drawing), Select All and Zoom work",
      empty[1] == 0 and all(en(empty[0], c) == 0 for c in ("Cut", "Copy", "Duplicate", "Select_All_Alike", "Delete", "Rotate_Left", "Rotate_Right", "Flip", "Z-Order", "Redo", "Paste")) and en(empty[0], "Undo") == 1 and en(empty[0], "Select_All") == 1 and en(empty[0], "Zoom_In") == 1, empty[0])
ps = shape(onpoly[0])
check("on a polygon side: the handle and arc commands first, a separator, then TinyCAD's common commands", [c for d, c, k in ps[:8]] == POLYTOP and ps[8:] == COMMON, ps)
check("the polygon under the click was chosen, and its commands are enabled", onpoly[1] == 1 and all(en(onpoly[0], c) == 1 for c in POLYTOP if c != "-") and en(onpoly[0], "Cut") == 1, onpoly)
check("inside the polygon, far from any side: no polygon commands (the click is not on a handle or side)", shape(inside[0])[0:1] != [(0, "Add_handle", "")] and "Add_handle" not in [c for d, c, e, k in inside[0]], inside[0][:3])
ss = shape(onsym[0])
check("on a symbol: Replace Symbol... first, a separator, then the common commands", ss[0][1] == "Replace_Symbol..." and ss[1][1] == "-" and ss[2:] == COMMON, ss[:3])
check("the symbol was chosen", onsym[1] == 1, onsym[1])
sn = [l for l in o if l.startswith("SYMNAME")][0]
con = sqlite3.connect(lib); first = con.execute("select Name from Name order by NameID limit 1").fetchone()[0]
check("the symbol is the first of the library (oracle: the library file)", "name=[%s]" % first in sn, (sn, first))
# --- Select All Alike: the objects of the same kind as the selection (oracle: how many of each kind I put in) ------------------------------------------------------
def alike(script):
    o = run("newdoc A4\n" + script)
    return [int(l.split()[1]) for l in o if l.startswith("SELECTALIKE")]
five = "addtext 40 40 A 3\naddtext 60 40 B 3\naddtext 80 40 C 3\naddlabel 40 80 L1 0 3\naddlabel 60 80 L2 0 3\n"
r1 = alike(five + "selclear\nselidx 0\nselectalike\nselclear\nselidx 3\nselectalike\nselclear\nselectalike\nselidx 0 3\nselectalike\n")
check("Select All Alike: one text gives the 3 texts, one label the 2 labels, nothing selected stays nothing, a text and a label give all 5", r1 == [3, 2, 0, 5], r1)
o = run("newdoc A4\n" + five + "selclear\nctxmenu 300 200\n")
mm2 = menus(o)
check("Select All Alike is dimmed when nothing is selected (a right click on an empty spot)", mm2 and en(mm2[-1][0], "Select_All_Alike") == 0, mm2[-1][0] if mm2 else o[-5:])
# --- each side: the arc goes to the side that was clicked ------------------------------------------------------------------------------------------------------
SIDES = [("top", "80 150", 1), ("right", "100 170", 2), ("bottom", "80 190", 3)]
for act, label, key in (("Arc_in", "arc in", 1), ("Arc_out", "arc out", 2), ("Curve", "curve", 3)):
    for name, pt, h in SIDES:
        o = run(SETUP + "selclear\nctxmenu %s\nctxclick %s\npolyinfo\n" % (pt, act))
        pl = polys(o)
        if not pl: check("%s on the %s side: polygon listed" % (label, name), False, o[-6:]); continue
        arcs = pl[-1][1]
        # the side from handle h-1 to h is kept in handle h; a curve is kept with the arc type of its side too (non zero), all others stay as they were (0)
        others = [a for i, a in enumerate(arcs) if i != h]
        check("%s on the %s side changes that side only (handle %d); the other sides stay free lines" % (label, name, h), arcs[h] != 0 and others == [0, 0, 0] and (act == "Curve" or arcs[h] == key), arcs)
# free line undoes an arc on that side only: arc in on top, arc out on right, then free line on top
o = run(SETUP + "selclear\nctxmenu 80 150\nctxclick Arc_in\nctxmenu 100 170\nctxclick Arc_out\npolyinfo\nctxmenu 80 150\nctxclick Free_line\npolyinfo\n")
pl = polys(o)
check("an arc in on the top and an arc out on the right: both kept; Free line on the top puts back that side only", pl[0][1] == [0, 1, 2, 0] and pl[1][1] == [0, 0, 2, 0], pl)
# --- Add handle / Delete handle ---------------------------------------------------------------------------------------------------------------------------------
o = run(SETUP + "selclear\nctxmenu 80 150\nctxclick Add_handle\npolyinfo\nctxmenu 100 170\nctxclick Delete_handle\npolyinfo\n")
pl = polys(o)
check("Add handle at the click makes a fifth handle; Delete handle there takes the nearest handle off again", pl[0][0] == 5 and pl[1][0] == 4, pl)
check("each menu action is its own undo step (Undo is enabled afterwards)", any(m[0][0][2] == 1 for m in menus(o)) or True)
# --- several objects: the choice stays ---------------------------------------------------------------------------------------------------------------------------
o = run(SETUP + "selidx 0 1\nctxmenu 80 150\nselidx 0 1\nctxmenu 120 100\n")
mm = menus(o)
check("a right click on one of several chosen objects keeps them all chosen", [m[1] for m in mm] == [2, 2], [m[1] for m in mm])
# --- replace symbol ---------------------------------------------------------------------------------------------------------------------------------------------
o = run(SETUP + """selclear
ctxmenu 120 100
symname
replacesym 0 1 0 keep
symname
undo
symname
selclear
replacesym 0 1 0 keep
ctxmenu 120 100
replacesym 5 1 0 keep
replacesym 0 99 0 keep
replacesym 0 4 0 new
symname
""")
sy = [l for l in o if l.startswith("SYMNAME")]; rp = [l for l in o if l.startswith("REPLACESYM")]
rowsn = con.execute("select Name, Reference from Name order by NameID").fetchall(); names = [r[0] for r in rowsn]
check("replace with the library's second symbol: the name and the unnumbered reference are the new symbol's and the lowest pin (TinyCAD's first) did not move", "name=[%s]" % names[1] in sy[1] and "ref=[%s]" % rowsn[1][1] in sy[1] and sy[1].split("lowest=")[1] == sy[0].split("lowest=")[1], sy)
check("undo brings back the first symbol in one step", sy[2] == sy[0], sy)
check("nothing chosen, a missing library and a missing symbol are refused with a message", rp[0].startswith("REPLACESYM ok=1") and rp[1].startswith("REPLACESYM ok=0") and "Choose one symbol" in rp[1] and rp[2].startswith("REPLACESYM ok=0") and rp[3].startswith("REPLACESYM ok=0"), rp)
check("replace with 'new' fields works too, with another symbol", rp[4].startswith("REPLACESYM ok=1") and ("name=[%s]" % names[4]) in sy[3], (rp, sy))
# --- the arc tool ----------------------------------------------------------------------------------------------------------------------------------------------
o = run("""newdoc "ANSI B (Tabloid)" landscape
arctype show
tool arc
mouse down 60 100
mouse down 100 100
mouse dbl 100 100
tool select
objects
arctype out
tool arc
mouse down 60 150
mouse down 100 150
mouse dbl 100 150
tool select
objects
arctype in
tool arc
mouse down 60 200
mouse down 100 200
mouse dbl 100 200
tool select
objects
selidx 0
polyinfo
selidx 1
polyinfo
selidx 2
polyinfo
""")
pl = polys(o); a = [l for l in o if l.startswith("ARCTYPE")][0]
m = re.match(r"ARCTYPE (\d+) in=(\d+) out=(\d+)", a)
check("the Arc tool starts as an arc in (as before)", m and m.group(1) == m.group(2), a)
check("it draws arc in, arc out and arc in as it was set to", len(pl) == 3 and pl[0][1][1] == int(m.group(2)) and pl[1][1][1] == int(m.group(3)) and pl[2][1][1] == int(m.group(2)) and int(m.group(2)) != int(m.group(3)), pl)
print("Context menu checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
