"""Show Position (TinyCAD's View > Show Position and its Position bar): the pointer's position as text, a snap button, a button that goes through the standard grid sizes, and the grid
size with its units. Checked against TinyCAD's own formulas (COption::PointToUnit, CDlgPositionBox::SetGridSize, CTinyCadView::OnToggleGridSize and OnMouseMove):
  - the position is the pointer snapped to the grid (when snapping is on), measured from the sheet's origin, as "%9.02f,%9.02f mm" or "%9.03f,%9.03f ''": compared as text, for many
    places, grid sizes, units and origins
  - the grid size button goes 2 mm, 1, 0.5, 0.25, 0.1 mm and back to 2 mm (any other size goes to 2 mm); the bar shows the size in tenths of a millimetre or thousandths of an inch
    with four figures, and its units; the ribbon's caption agrees and follows the units
  - the snap and Show grid buttons, the View menu and the bar always agree with the sheet, whatever changed it (a button, the grid button, the Options dialog)
  - Show Position: the View menu item, the ribbon button and the script all show and hide the bar; the choice is kept for the next run; with the bar hidden the position goes to the
    status message instead; with no design open the bar is empty and its buttons cannot be used
Needs the built program."""
import os, re, shutil, subprocess, sys, tempfile, random
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Position checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:420])
def run(script, home=None, timeout=150):
    h = os.path.join(tmp, "home_" + home) if home else tempfile.mkdtemp(dir=tmp)
    os.makedirs(h, exist_ok=True)
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n"), r.returncode, r.stderr
def pinfo(lines):
    out = []
    for l in lines:
        if l.startswith("POSITIONINFO "):
            m = re.match(r"POSITIONINFO visible=(\d) text=\[(.*)\] grid=(\S*) units=(\S+) snap=(\d)(\d) grid_show=(\d)(\d)(\d) size_enabled=(\d) snap_enabled=(\d) menu=(\d) ribbon=(\d) status=\[(.*?)\] caption=\[(.*)\]$", l)
            out.append(dict(visible=m.group(1), text=m.group(2), grid=m.group(3), units=m.group(4), snap=m.group(5) + m.group(6), grid_show=m.group(7) + m.group(8) + m.group(9),
                            size_en=m.group(10), snap_en=m.group(11), menu=m.group(12), ribbon=m.group(13), status=m.group(14), caption=m.group(15)))
    return out
sample = next(p for p in sorted(os.path.join(dp, f) for dp, _, fs in os.walk(EX) for f in fs if f.endswith(".dsn")) if os.path.basename(p) == "PSU.dsn")
work = os.path.join(tmp, "work"); os.makedirs(work); psu = os.path.join(work, "PSU.dsn"); shutil.copy(sample, psu)
def mmtext(x, y): return f"{x:9.2f},{y:9.2f} mm"
def intext(x, y): return f"{x / 25.4:9.3f},{y / 25.4:9.3f} ''"
def gtext(mm, inches): return ("%.4g" % (mm * 1000 / 25.4)) if inches else ("%.4g" % (mm * 10))
# ---------- the position text ----------
rnd = random.Random(21); bad = 0; first = None; n = 0; n_off = 0; n_origin = 0; n_inch = 0
for k in range(12):
    grid = [2, 5, 10][k % 3]; inches = (k // 2) % 2 == 1; origin = [None, (40.0, 30.0), (12.5, 7.5), None][k % 4]; snap = k % 3 != 0          # (every combination comes up: snapping off, inches, an origin)
    targets = []
    for _ in range(8):
        gx, gy = rnd.randint(8, 50) * grid / 2.0 + 20, rnd.randint(6, 30) * grid / 2.0 + 20
        gx, gy = round(gx / grid) * grid, round(gy / grid) * grid
        dx, dy = rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3)
        targets.append((gx, gy, dx, dy))
    script = f'open "{psu}"\noptions grid={grid} snap={1 if snap else 0}' + (" units=in" if inches else "") + "\n"
    if inches: script = f'open "{psu}"\noptions units=in\noptions grid={grid / 25.4:.8f} snap={1 if snap else 0}\n'
    if origin: script += f"setorigin {origin[0]} {origin[1]}\n"
    for gx, gy, dx, dy in targets: script += f"mouse move {gx + dx:.3f} {gy + dy:.3f}\npositioninfo\n"
    o, rc, err = run(script); infos = pinfo(o)
    for (gx, gy, dx, dy), inf in zip(targets, infos):
        n += 1
        ox, oy = origin if origin else (0.0, 0.0)
        n_off += 0 if snap else 1; n_origin += 1 if origin else 0; n_inch += 1 if inches else 0
        if snap: want = (gx - ox, gy - oy); exact = True
        else: want = (gx + dx - ox, gy + dy - oy); exact = False
        text = inf["text"]
        if exact:
            wt = intext(*want) if inches else mmtext(*want)
            if text != wt: bad += 1; first = first or (grid, inches, origin, snap, (gx, gy, dx, dy), text, wt)
        else:
            m = re.match(r"\s*(-?[\d.]+),\s*(-?[\d.]+) (mm|'')$", text)
            if not m: bad += 1; first = first or ("format", text); continue
            vx, vy = float(m.group(1)), float(m.group(2))
            if inches: vx, vy = vx * 25.4, vy * 25.4
            if abs(vx - want[0]) > 0.6 or abs(vy - want[1]) > 0.6 or m.group(3) != ("''" if inches else "mm"): bad += 1; first = first or ("raw", text, want)
check(f"{n} pointer positions (grids of 2, 5 and 10 mm, millimetres and inches, with and without an origin): the text is exactly TinyCAD's, from the snapped point measured from the origin", bad == 0, str(first))
check("those places included positions with snapping off (where the pointer is, to within a pixel, as TinyCAD does), with an origin, and in inches", n_off >= 6 and n_origin >= 6 and n_inch >= 6, f"{n_off} {n_origin} {n_inch}")
# the format itself
o, rc, err = run(f'open "{psu}"\noptions grid=2\nmouse move 50.1 40.2\npositioninfo\n'); t = pinfo(o)[0]["text"]
check("in millimetres the text is two numbers of two decimals padded to nine places, a comma between and mm after, as %9.02f,%9.02f mm", re.fullmatch(r" {4}\s*\d+\.\d\d, {0,}\s*\d+\.\d\d mm", t) is not None and len(t.split(",")[0]) == 9 and t.endswith(" mm"), repr(t))
# ---------- the grid size button and the size shown ----------
CYCLE = {2: 1, 1: 0.5, 0.5: 0.25, 0.25: 0.1, 0.1: 2}
bad = 0; first = None
for inches in (False, True):
    for start in (2, 1, 0.5, 0.25, 0.1, 3.7, 0.3, 7):
        script = f'open "{psu}"\n' + (f"options units=in grid={start / 25.4:.9f}\n" if inches else f"options grid={start}\n") + "positioninfo\n" + "gridcycle\npositioninfo\n" * 6
        o, rc, err = run(script); infos = pinfo(o)
        cur = start; seq = [cur]
        for _ in range(6): cur = CYCLE.get(round(cur, 9), 2); seq.append(cur)
        for step, (mm, inf) in enumerate(zip(seq, infos)):
            wg = gtext(mm, inches); wu = '.001"' if inches else ".1mm"
            wc = "Grid: " + (("%.4g" % (mm / 25.4)) + " in" if inches else ("%.4g" % mm) + " mm")
            if inf["grid"] != wg or inf["units"] != wu or inf["caption"] != wc: bad += 1; first = first or (inches, start, step, inf["grid"], wg, inf["units"], inf["caption"], wc)
check("the grid size button: from 2 mm, 1, 0.5, 0.25, 0.1 and back to 2, and from any other size to 2 mm, in millimetres and in inches (16 sequences of 6 presses): the size shown (tenths of a mm, or thousandths of an inch, four figures), its units and the ribbon's caption all follow", bad == 0, str(first))
o, rc, err = run(f'open "{psu}"\noptions grid=1\ngridcycle\noptionsinfo\n'); g = [l for l in o if l.startswith("OPTIONSINFO sheet")][0]
check("and the sheet really has the new spacing (1 mm to 0.5 mm)", "grid=0.5" in g, g)
# ---------- the controls agree with the sheet, whatever changed it ----------
o, rc, err = run(f'open "{psu}"\npositioninfo\npositionsnap\npositioninfo\npositionsnap\npositioninfo\noptions snap=0 showgrid=0\npositioninfo\noptions snap=1 showgrid=1\npositioninfo\n'); p = pinfo(o)
check("the snap button of the bar and the ribbon's agree with the sheet: on at first, off after a click, on again after another", (p[0]["snap"], p[1]["snap"], p[2]["snap"]) == ("11", "00", "11"), str([x["snap"] for x in p[:3]]))
check("the Options dialog changes them too: snap off and grid hidden put the bar's and ribbon's snap, the View menu's Show grid and the ribbon's Show grid all off together, and on again all together", p[3]["snap"] == "00" and p[3]["grid_show"] == "000" and p[4]["snap"] == "11" and p[4]["grid_show"] == "111", f"{p[3]} {p[4]}")
two = os.path.join(work, "two.dsn"); shutil.copy(sample, two)
o, rc, err = run(f'open "{psu}"\nnewdoc "ISO A4" landscape\noptions grid=5\npositioninfo\ngotodoc 0\npositioninfo\ngotodoc 1\npositioninfo\n'); p = pinfo(o)
check("switching between designs shows each design's own grid size on the bar (the new design's 5 mm is 50, the PSU's 1 mm is 10)", [x["grid"] for x in p] == ["50", "10", "50"] or [x["grid"] for x in p] == ["100", "10", "100"], f"{[x['grid'] for x in p]}")
# ---------- Show Position ----------
o, rc, err = run(f'open "{psu}"\npositioninfo\npositionshow 0\npositioninfo\npositionshow 1\npositioninfo\npositionshow menu\npositioninfo\npositionshow menu\npositioninfo\npositionshow button\npositioninfo\npositionshow button\npositioninfo\n'); p = pinfo(o)
st = [(x["visible"], x["menu"], x["ribbon"]) for x in p]
check("the bar is shown to begin with, as in TinyCAD; hiding and showing it from the script, the View menu item and the ribbon button each change the bar, the menu tick and the ribbon button together",
      st == [("1", "1", "1"), ("0", "0", "0"), ("1", "1", "1"), ("0", "0", "0"), ("1", "1", "1"), ("0", "0", "0"), ("1", "1", "1")], str(st))
o, rc, err = run(f'open "{psu}"\npositionshow 0\n', home="pos")
o, rc, err = run(f'open "{psu}"\npositioninfo\n', home="pos"); p = pinfo(o)
check("hidden, it is hidden again next time: the choice is kept (the menu tick and the ribbon button too)", p[0]["visible"] == "0" and p[0]["menu"] == "0" and p[0]["ribbon"] == "0", str(p[0]))
regs = [os.path.join(dp, f) for dp, _, fs in os.walk(os.path.join(tmp, "home_pos")) for f in fs if f == "reg.xml"]
node = ET.parse(regs[0]).getroot()
for part in ("HKEY_CURRENT_USER", "SOFTWARE", "HPL Software", "TyCAD Electrical"): node = next(k for k in node.findall("Key") if k.get("Name") == part)
vals = {v.get("Name"): v.text for v in node.findall("Value")}
check("the registry holds it as ShowPosition = 0", vals.get("ShowPosition") == "0", str(vals))
o, rc, err = run(f'open "{psu}"\npositionshow 1\n', home="pos"); o, rc, err = run(f'positioninfo\n', home="pos"); p = pinfo(o)
check("and shown again is kept as well (visible with no design open, since it is the program's bar)", p[0]["visible"] == "1", str(p[0]))
# where the position goes
o, rc, err = run(f'open "{psu}"\noptions grid=2\nmouse move 60.2 40.1\nfindinfo\npositioninfo\npositionshow 0\nmouse move 80.1 50.1\nfindinfo\npositioninfo\n')
msgs = [re.search(r"msg=(.*)$", l).group(1) for l in o if l.startswith("FINDINFO")]; p = pinfo(o)
check("with the bar shown the position is on the bar and the status message is left alone", p[0]["text"] == mmtext(60, 40) and mmtext(60, 40) not in msgs[0], f"{p[0]['text']!r} {msgs[0]!r}")
check("with the bar hidden the position goes to the status bar instead (its second panel), so it is never lost", p[1]["status"] == mmtext(80, 50), repr(p[1]["status"]))
check("...and with the bar shown it is not there", p[0]["status"] != mmtext(60, 40), repr(p[0]["status"]))
# no design open
o, rc, err = run('positioninfo\n'); p = pinfo(o)[0]
check("with no design open the bar is empty and its snap and grid size buttons cannot be used", p["size_en"] == "0" and p["snap_en"] == "0" and p["text"].strip() == "" and p["grid"] == "", str(p))
print(f"position: {checks} checks, {len(fails)} failures")
print("\nPOSITION CHECKS PASSED" if not fails else f"\nPOSITION CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
