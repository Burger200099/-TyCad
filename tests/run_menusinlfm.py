#!/usr/bin/env python3
"""Menus whose items are made in the form file (mainform.lfm) rather than in code: the document tab menu (Close, Close all), the Grid Size menu (View
menu and the toolbar's drop-down), the Polygon tool's and the Arc tool's right click menus, and the extra items of the sheet's right click menu.
Oracles: the expected captions, tags and radio marks are written out here by hand (grid sizes from the size table, in hundredths of a millimetre);
the lfm text is also read to see that nothing in the code builds these menus again (no TMenuItem.Create for them).
  - doc menu: Close, Close all, both wired
  - grid menus: 7 sizes + separator + Custom..., the same tags in the View menu and in the popup; choosing a size ticks it in both
  - polygon menu: Finish polygon, Cancel drawing, separator, Free line, Arc in, Arc out; the current kind is ticked; choosing Arc in changes it
  - arc menu: Finish arc is hidden without two points; Arc in / Arc out radio; choosing Arc out changes the tool's kind
  - sheet menu: with nothing selected none of the object items is shown
Needs the built program and xvfb."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Menus-in-lfm checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:700])
def run(lines):
    h = os.path.join(tmp, "h"); shutil.rmtree(h, ignore_errors=True); os.makedirs(h)
    f = os.path.join(tmp, "s.txt"); open(f, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
def popups(o, name):
    res = []
    for l in o:
        if l.startswith("POPUP %s " % name):
            items = []
            for it in l.split(" ", 2)[2].split("|"):
                c, tag, rad, chk, vis, en, wired = it.rsplit(":", 6)
                items.append(dict(cap=c, tag=int(tag), radio=rad == "1", checked=chk == "1", vis=vis == "1", en=en == "1", wired=wired == "1"))
            res.append(items)
    return res
EX = os.environ.get("TC_EXAMPLES", "examples")
psu = next(os.path.join(dp, f) for dp, _, fs in os.walk(EX) for f in fs if f == "PSU.dsn")
w = os.path.join(tmp, "PSU.dsn"); shutil.copy(psu, w)
o = run(["open " + w, "popup doc", "popup grid", "popup draw", "tool polygon", "popup draw", "popup draw click Arc_in", "popup draw",
         "tool select", "tool arc", "popup arc", "popup arc click Arc_out", "popup arc", "popup sheet", "viewmenuinfo", "gridmenuclick 4", "popup grid", "viewmenuinfo", "quit"])
doc = popups(o, "doc")[0]
check("doc menu: Close and Close all, wired", [(i["cap"], i["wired"]) for i in doc] == [("Close", True), ("Close_all", True)], doc)
grid = popups(o, "grid")[0]
sizes = [("0.5_mm", 50), ("1_mm", 100), ("1.27_mm_(0.05_in)", 127), ("2_mm", 200), ("2.54_mm_(0.1_in)", 254), ("5_mm", 500), ("10_mm", 1000)]
check("grid popup: seven sizes with tags in hundredths of a mm, radio items", [(i["cap"], i["tag"]) for i in grid[:7]] == sizes and all(i["radio"] for i in grid[:7]), grid)
check("grid popup: separator then Custom...", grid[7]["cap"] == "-" and grid[8]["cap"] == "Custom..." and grid[8]["wired"], grid[7:])
check("grid popup: every size is wired", all(i["wired"] for i in grid), grid)
g = [l for l in o if l.startswith("VIEWMENUINFO")]
check("View menu Grid Size has 9 items (7 sizes, separator, Custom)", g and "grid=9" in g[0], g)
g2 = popups(o, "grid")[1]
check("choosing the fifth size (2.54 mm) ticks it in the popup and in the View menu, and only it",
      [i["checked"] for i in g2[:7]] == [False, False, False, False, True, False, False] and g and "checked=4" in g[-1], (g2, g[-1:]))
dr = popups(o, "draw")
d0 = dr[0]
check("polygon menu: Finish, Cancel, separator, Free line, Arc in, Arc out with tags 1, 2, 0, 10, 11, 12",
      [(i["cap"], i["tag"]) for i in d0] == [("Finish_polygon", 1), ("Cancel_drawing", 2), ("-", 0), ("Free_line", 10), ("Arc_in", 11), ("Arc_out", 12)], d0)
check("polygon menu: all wired; only the three kinds are radio items", all(i["wired"] for i in d0) and [i["radio"] for i in d0] == [False, False, False, True, True, True], d0)
check("polygon menu: the kind in use (Free line) is ticked", [i["checked"] for i in d0[3:]] == [True, False, False], d0)
check("polygon menu: choosing Arc in ticks it", [i["checked"] for i in dr[2][3:]] == [False, True, False], dr[2])
ar = popups(o, "arc")
a0 = ar[0]
check("arc menu: Finish arc, Cancel drawing, separator, Arc in, Arc out with tags 3, 1, 0, 11, 12",
      [(i["cap"], i["tag"]) for i in a0] == [("Finish_arc", 3), ("Cancel_drawing", 1), ("-", 0), ("Arc_in", 11), ("Arc_out", 12)], a0)
check("arc menu: Finish arc hidden without points; the others shown", [i["vis"] for i in a0] == [False, True, True, True, True], a0)
check("arc menu: Arc in is the kind in use at first, Arc out after choosing it", [i["checked"] for i in a0[3:]] == [True, False] and [i["checked"] for i in ar[1][3:]] == [False, True], (a0, ar[1]))
sh = popups(o, "sheet")[0]
objcaps = {"Add_handle", "Delete_handle", "Free_line", "Arc_in", "Arc_out", "Curve", "Add_wire_cut_here", "Make_horizontal", "Make_vertical", "Reload_symbol_from_design", "Open_design", "Replace_Symbol..."}
check("sheet menu: with nothing chosen no object item is shown, and no separator of those groups",
      not [i for i in sh if i["vis"] and (i["cap"] in objcaps)] and len([i for i in sh if i["vis"] and i["cap"] == "-"]) == len([i for i in sh if i["cap"] == "-" and i["vis"]]), sh)
# the lfm file itself
lfm = open(os.path.join(HERE, "..", "src", "forms", "mainform.lfm"), encoding="utf-8").read()
pas = open(os.path.join(HERE, "..", "src", "forms", "mainform.pas"), encoding="utf-8").read()
for nm in ("pmDocTabs", "pmGridSize", "pmPolyDraw", "pmArcDraw"):
    check("%s is in the form file" % nm, ("object %s: TPopupMenu" % nm) in lfm)
check("the code no longer builds the grid or document tab menus", "FGridMenu" not in pas and "FDocPopup" not in pas and "BuildGridSizeMenu" not in pas)
view = open(os.path.join(HERE, "..", "src", "UView.pas"), encoding="utf-8").read()
check("the view builds no menu items itself", "TMenuItem.Create" not in view and "TPopupMenu.Create" not in view)
print("Menus in lfm checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
