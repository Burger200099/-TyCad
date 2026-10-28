"""Resizing with handles (TinyCAD's CRectTracker behaviour for a rectangle, ellipse, picture, note and revision cloud): select one of them and eight
handles appear just outside its rectangle; dragging one changes the rectangle by TinyCAD's rules (CDrawRectOutline::MoveField), Ctrl keeps
the shape on a corner, the pointer shows the way it will resize, and each drag is one undo step. Checked against a Python port of
MoveField and of the aspect rule in CDrawEditItem::Move, on the saved coordinates:
  - every handle of every kind of object, dragged by several amounts (in one step and in several, past the opposite side so the
    rectangle turns inside out, and with Ctrl held on the corners)
  - undo takes each drag back exactly, redo does it again; a press that does not move leaves no undo step
  - the handles are really drawn (black squares at their places, not on an unselected or multiply selected object), and the pointer
    shows the right arrow over each handle and the ordinary pointer elsewhere
  - a click inside the object still moves it, with nothing resized
Needs the built program and ImageMagick."""
import itertools, math, os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from uuoracle import uu_lines
from xml.sax.saxutils import escape
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or shutil.which("convert") is None:
    print("Resize checks skipped: need xvfb-run, ImageMagick and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
env = dict(os.environ, HOME=os.path.join(tmp, "home")); os.makedirs(env["HOME"])
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:400])
def run(script, timeout=240):
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=env)
    return r.stdout.split("\n"), r.returncode, r.stderr
def pix(path, x, y):
    o = subprocess.run(["convert", path, "-crop", "1x1+%d+%d" % (x, y), "-format", "%[fx:int(255*r)],%[fx:int(255*g)],%[fx:int(255*b)]", "info:"], capture_output=True, text=True).stdout
    return tuple(int(v) for v in o.split(","))
# ---------- TinyCAD's rules, ported independently ----------
def snap(v, grid=10.0): return math.floor(v / grid + 0.5) * grid
def move_field(a, b, w, r):
    """CDrawRectOutline::MoveField on corners a and b (design units), by r"""
    left, right = min(a[0], b[0]), max(a[0], b[0]); top, bottom = min(a[1], b[1]), max(a[1], b[1])
    if w == 0: left += r[0]; top += r[1]
    elif w == 1: right += r[0]; top += r[1]
    elif w == 2: right += r[0]; bottom += r[1]
    elif w == 3: left += r[0]; bottom += r[1]
    elif w == 4: top += r[1]
    elif w == 5: right += r[0]
    elif w == 6: bottom += r[1]
    elif w == 7: left += r[0]
    ax, bx = (left, right) if a[0] < b[0] else (right, left)
    ay, by = (top, bottom) if a[1] < b[1] else (bottom, top)
    return (ax, ay), (bx, by)
def aspect_keep(w, r, ratio):
    """CDrawEditItem::Move with Ctrl held: a corner keeps the shape of the rectangle"""
    x, y = r
    if w in (1, 3):
        if abs(x) > abs(y): y = -x * ratio
        else: x = -y / ratio
    elif w in (0, 2):
        if abs(x) > abs(y): y = x * ratio
        else: x = y / ratio
    return (x, y)
CURSOR = {0: "NWSE", 2: "NWSE", 1: "NESW", 3: "NESW", 4: "NS", 6: "NS", 5: "WE", 7: "WE"}
# ---------- a design with one of each ----------
pic = os.path.join(tmp, "two.png"); subprocess.run(["convert", "-size", "100x60", "xc:red", "-fill", "blue", "-draw", "rectangle 50,0 99,59", pic], check=True)
sample = next(p for p in sorted(os.path.join(dp, f) for dp, _, fs in os.walk(EX) for f in fs if f.endswith(".dsn")) if "LED Flasher" in p)
raw = open(sample, encoding="utf-8", errors="replace").read()
pdata = open(pic, "rb").read()
image = '<IMAGE id="5" type="PNG"><UUENCODE size="%d">\r\n' % len(pdata) + "".join(escape(l, {"'": "&#039;", '"': "&quot;"}) + "\n" for l in uu_lines(pdata)) + "</UUENCODE></IMAGE>\r\n"
objs = ('<RECTANGLE a="20,20" b="60,44" style="0" fill="0" />\r\n'
        '<ELLIPSE a="90,20" b="130,50" style="0" fill="0" />\r\n'
        "<NOTE_TEXT a='160,20' b='200,50' direction='3' style='6' fill='0' font='3' color='FF0000' border_style='1'>A note\r\nwith two lines</NOTE_TEXT>\r\n"
        '<METAFILE a="20,90" b="40,102" id="5" />\r\n'
        '<CLOUD a="100,90" b="140,114" style="0" bump="25" />\r\n')
i = raw.index("<SYMBOLDEF") if "<SYMBOLDEF" in raw else raw.index("<SYMBOL "); j = raw.index("<SYMBOL ")
design = raw[:i] + image + raw[i:j] + objs + raw[j:]
dpath = os.path.join(tmp, "four.dsn"); open(dpath, "w", encoding="utf-8").write(design)
src = ET.parse(dpath).getroot(); src = src.findall("TinyCAD")[0] if src.tag == "TinyCADSheets" else src
# the objects in the order the program holds them: find their indexes through the program
KINDS = [("rectangle", "RECTANGLE", "TDrawSquare"), ("ellipse", "ELLIPSE", "TDrawSquare"), ("note", "NOTE_TEXT", "TDrawNoteText"), ("picture", "METAFILE", "TDrawMetaFile"), ("revision cloud", "CLOUD", "TDrawCloud")]
def orig(tag):
    e = src.find(tag); a = tuple(float(v) * 5 for v in e.get("a").split(",")); b = tuple(float(v) * 5 for v in e.get("b").split(","))
    return a, b
def corners(path, tag):
    r = ET.parse(path).getroot(); sh = r.findall("TinyCAD")[0] if r.tag == "TinyCADSheets" else r
    e = sh.find(tag); return tuple(float(v) * 5 for v in e.get("a").split(",")), tuple(float(v) * 5 for v in e.get("b").split(","))
def close(p, q, tol=1e-3): return all(abs(x - y) <= tol for x, y in zip(p[0] + p[1], q[0] + q[1]))
# which index is each kind? (the program numbers its objects: ask it by selecting through selectclass)
# ---------- stage 1: where the handles are ----------
# rectangle and ellipse share a class: select them by their position in the drawing list (the oracle reads the file in order)
order = [e.tag for e in src if e.tag not in {"NAME", "DETAILS", "FONT", "STYLE", "FILL", "IMAGE", "SYMBOLDEF", "OPTIONS", "METAFILE_"}]
def index_of(tag): return [k for k, t in enumerate(order) if t == tag][0]
def select(name, tag, cls):
    return ["selclear", f"selidx {index_of(tag)}"]
def handle_script(name, tag, cls):
    out = select(name, tag, cls) + ["findinfo"]
    for c in range(8): out.append(f"handlepos {c}")
    return out
lines = [f'open "{dpath}"']
for k in KINDS: lines += handle_script(*k)
o, rc, err = run("\n".join(lines) + "\n")
check("the program started and the handles were reported", rc == 0 and not any(l.startswith("ERROR") for l in o), "\n".join(l for l in o if l.startswith("ERROR")) + err[-200:])
infos = [l for l in o if l.startswith("FINDINFO")]
check("selecting each of the five objects finds the right class", [re.search(r"class=(\w+)", l).group(1) for l in infos] == [k[2] for k in KINDS], str(infos))
H = {}; seen = 0
for l in o:
    if l.startswith("HANDLEPOS") and "none" not in l:
        t = l.split(); H.setdefault(seen // 8, {})[int(t[1])] = (float(t[2]), float(t[3]), float(t[5]), float(t[6]), float(t[8])); seen += 1
check("all five have eight handles each", len(H) == 5 and all(len(v) == 8 for v in H.values()), str(len(H)))
# the geometry of the handles, from the file's rectangle: independent of the zoom (their size is the only unknown, and it must be the same everywhere)
for n, (name, tag, cls) in enumerate(KINDS):
    a, b = orig(tag); L, R = min(a[0], b[0]) / 5, max(a[0], b[0]) / 5; T, B = min(a[1], b[1]) / 5, max(a[1], b[1]) / 5
    hs = H[n][0][4]; cx, cy = (L + R) / 2, (T + B) / 2
    want = {0: (L - hs / 2, T - hs / 2), 1: (R + hs / 2, T - hs / 2), 2: (R + hs / 2, B + hs / 2), 3: (L - hs / 2, B + hs / 2),
            4: (cx, T - hs / 2), 5: (R + hs / 2, cy), 6: (cx, B + hs / 2), 7: (L - hs / 2, cy)}
    ok = all(abs(H[n][c][0] - want[c][0]) < 2e-4 and abs(H[n][c][1] - want[c][1]) < 2e-4 for c in range(8))
    check(f"{name}: the eight handles are the squares just outside the rectangle, at its corners and the middles of its sides (corners first, as MFC numbers them)", ok, f"{H[n]} vs {want}")
    check(f"{name}: a handle is a few pixels across, whatever the zoom (6 pixels)", 0.3 < hs < 8, str(hs))
print(f"handles: {checks} checks, {len(fails)} failures")
# ---------- stage 2: drags ----------
GRID_MM = 2.0
def on_grid(v): return round(v / GRID_MM) * GRID_MM
DELTAS = [(20, 10), (-14, -8), (0, 16), (16, 0), (-60, -40), (30, -26)]
total_drags = 0
for n, (name, tag, cls) in enumerate(KINDS):
    a0, b0 = orig(tag); script = [f'open "{dpath}"'] + select(name, tag, cls)
    cases = []
    for c in range(8):
        hx, hy, sx, sy, hs = H[n][c]
        for dx, dy in DELTAS:
            tx, ty = on_grid(hx + dx), on_grid(hy + dy)
            cases.append((c, (sx, sy), (tx, ty)))
            script += [f"mouse down {hx} {hy}", f"mouse move {tx} {ty}", f"mouse up {tx} {ty}", f'save "{tmp}/d_{name}_{len(cases)-1}.dsn"', "undoinfo", "undo", f'save "{tmp}/u_{name}_{len(cases)-1}.dsn"', "redo", f'save "{tmp}/r_{name}_{len(cases)-1}.dsn"', "undo"]
    o, rc, err = run("\n".join(script) + "\n", 280)
    check(f"{name}: the drags ran cleanly", rc == 0 and not any(l.startswith("ERROR") for l in o), "\n".join(l for l in o if l.startswith("ERROR")) + err[-200:])
    uds = [l for l in o if l.startswith("UNDOINFO")]
    bad_geo = bad_undo = bad_redo = bad_step = 0; first_bad = None
    for k, (c, (sx, sy), (tx, ty)) in enumerate(cases):
        r = (snap(tx * 5) - sx * 5, snap(ty * 5) - sy * 5)
        # the start point the view used is on the grid; the target is on the grid: the move between them is exact
        r = (tx * 5 - sx * 5, ty * 5 - sy * 5)
        want = move_field(a0, b0, c, r)
        try: got = corners(f"{tmp}/d_{name}_{k}.dsn", tag)
        except Exception: got = None
        if got is None or not close(got, want):
            bad_geo += 1; first_bad = first_bad or (c, (tx - sx, ty - sy), got, want)
        if 'next="Resize"' not in uds[k] or not re.search(r"undo=1 ", uds[k]): bad_step += 1
        try:
            if not close(corners(f"{tmp}/u_{name}_{k}.dsn", tag), (a0, b0)): bad_undo += 1
            if got is not None and not close(corners(f"{tmp}/r_{name}_{k}.dsn", tag), got): bad_redo += 1
        except Exception: bad_undo += 1
    total_drags += len(cases)
    check(f"{name}: {len(cases)} drags (8 handles x {len(DELTAS)} amounts, some of them past the opposite side) give the rectangle TinyCAD's MoveField gives", bad_geo == 0, f"{bad_geo} wrong; first: {first_bad}")
    check(f"{name}: each drag is exactly one undo step called Resize", bad_step == 0, str(bad_step))
    check(f"{name}: undo gives back the original rectangle exactly, and redo the resized one", bad_undo == 0 and bad_redo == 0, f"{bad_undo} {bad_redo}")
print(f"drags: {total_drags} drags, {checks} checks so far, {len(fails)} failures")
# ---------- several moves in one drag, Ctrl on the corners, a press with no move ----------
for n, (name, tag, cls) in enumerate(KINDS):
    a0, b0 = orig(tag); ratio = abs((b0[1] - a0[1]) / (b0[0] - a0[0]))
    script = [f'open "{dpath}"'] + select(name, tag, cls); cases = []
    for c in (0, 1, 2, 3):
        hx, hy, sx, sy, hs = H[n][c]
        steps = [(on_grid(hx + 10), on_grid(hy + 8)), (on_grid(hx + 24), on_grid(hy + 12)), (on_grid(hx + 6), on_grid(hy + 30))]
        for ctrl in (False, True):
            k = len(cases); cases.append((c, (sx, sy), steps, ctrl))
            script.append(f"mouse down {hx} {hy}")
            for (tx, ty) in steps: script.append(f"mouse move {tx} {ty}" + (" ctrl" if ctrl else ""))
            script += [f"mouse up {steps[-1][0]} {steps[-1][1]}", f'save "{tmp}/m_{name}_{k}.dsn"', "undo"]
    script += [f"mouse down {H[n][2][0]} {H[n][2][1]}", f"mouse up {H[n][2][0]} {H[n][2][1]}", "undoinfo"]
    o, rc, err = run("\n".join(script) + "\n", 280)
    bad = 0; first = None
    for k, (c, (sx, sy), steps, ctrl) in enumerate(cases):
        a, b = a0, b0; last = (sx * 5, sy * 5)
        for (tx, ty) in steps:
            r = (tx * 5 - last[0], ty * 5 - last[1]); last = (tx * 5, ty * 5)
            if ctrl and ratio > 0: r = aspect_keep(c, r, ratio)
            a, b = move_field(a, b, c, r)
        try: got = corners(f"{tmp}/m_{name}_{k}.dsn", tag)
        except Exception: got = None
        if got is None or not close(got, (a, b), 2e-3): bad += 1; first = first or (c, ctrl, got, (a, b))
    check(f"{name}: a drag in three moves, with and without Ctrl on each corner (Ctrl keeps the shape), follows TinyCAD's rules move by move", bad == 0, f"{bad} wrong; first {first}")
    check(f"{name}: pressing a handle and letting go without moving leaves no undo step", "undo=0 " in [l for l in o if l.startswith("UNDOINFO")][-1], [l for l in o if l.startswith("UNDOINFO")][-1])
# ---------- what is drawn, the pointer, and clicking inside ----------
n = 3; name, tag, cls = KINDS[n]
a0, b0 = orig(tag); cx = (a0[0] + b0[0]) / 10; cy = (a0[1] + b0[1]) / 10
script = [f'open "{dpath}"', "selclear", f"selidx {index_of('RECTANGLE')}"] + [f"viewpoint {H[0][c][0]} {H[0][c][1]}" for c in range(8)] + ["shot " + tmp + "/sel_rect.bmp"]
script += ["selclear", f"selidx {index_of('RECTANGLE')} {index_of('ELLIPSE')}", "findinfo", "handlepos 0"]
script += ["selclear", f"viewpoint {H[0][0][0]} {H[0][0][1]}", "shot " + tmp + "/none.bmp"]
script += [f"selclear", f"selidx {index_of('RECTANGLE')}"]
for c in range(8): script += [f"mouse move {H[0][c][0]} {H[0][c][1]}", "cursor"]
script += ["mouse move 40 32", "cursor", "mouse move 300 200", "cursor"]
o, rc, err = run("\n".join(script) + "\n")
vps = [tuple(int(v) for v in l.split()[1:]) for l in o if l.startswith("VIEWPOINT")]
sel_png = f"{tmp}/sel_rect.bmp"
blacks = [pix(sel_png, *vps[c]) for c in range(8)]
check("the eight handles are drawn: a black square at each place", all(b == (0, 0, 0) for b in blacks), str(blacks))
two = [l for l in o if l.startswith("FINDINFO")][-1]
check("with two objects selected there are no handles (handles are for a single object)", " sel=2 " in two and any("HANDLEPOS none" in l for l in o), two)
# nothing selected: where the rectangle's top-left handle would be, nothing black is drawn
hx0, hy0 = H[0][0][0], H[0][0][1]
check("and none are drawn when nothing is selected", pix(f"{tmp}/none.bmp", vps[8][0], vps[8][1]) != (0, 0, 0), str(pix(f"{tmp}/none.bmp", vps[8][0], vps[8][1])))
curs = [l.split()[1] for l in o if l.startswith("CURSOR")]
check("the pointer shows the way each handle resizes, and the ordinary pointer away from them", curs[:8] == [CURSOR[c] for c in range(8)] and curs[8:] == ["default", "default"], str(curs))
# a click inside a selected picture still moves it: nothing is resized
script = [f'open "{dpath}"', "selclear", f"selidx {index_of('METAFILE')}", f"mouse down {cx} {cy}", f"mouse move {cx + 20} {cy + 10}", f"mouse up {cx + 20} {cy + 10}", f'save "{tmp}/inside.dsn"', "undoinfo"]
o, rc, err = run("\n".join(script) + "\n")
mv = corners(f"{tmp}/inside.dsn", "METAFILE")
sw, sh_ = a0[0] - b0[0], a0[1] - b0[1]
check("a press inside the selected picture moves it (the size is unchanged) rather than resizing it", abs((mv[1][0] - mv[0][0]) - (b0[0] - a0[0])) < 1e-3 and abs((mv[1][1] - mv[0][1]) - (b0[1] - a0[1])) < 1e-3 and abs(mv[0][0] - a0[0]) > 5, f"{mv} from {(a0, b0)}")
# the picture stretches with its rectangle: red left half, blue right half stay halves
hx, hy, sx, sy, hs = H[3][2]
script = [f'open "{dpath}"', "selclear", f"selidx {index_of('METAFILE')}", f"mouse down {hx} {hy}", f"mouse move {on_grid(hx + 30)} {on_grid(hy + 18)}", f"mouse up {on_grid(hx + 30)} {on_grid(hy + 18)}", "selclear"]
a, b = move_field(a0, b0, 2, (on_grid(hx + 30) * 5 - sx * 5, on_grid(hy + 18) * 5 - sy * 5))
x1, y1, x2, y2 = a[0] / 5, a[1] / 5, b[0] / 5, b[1] / 5; ym = (y1 + y2) / 2
script += [f"viewpoint {x1 + (x2 - x1) * 0.25} {ym}", f"viewpoint {x1 + (x2 - x1) * 0.75} {ym}", "shot " + tmp + "/stretched.bmp"]
o, rc, err = run("\n".join(script) + "\n")
vps = [tuple(int(v) for v in l.split()[1:]) for l in o if l.startswith("VIEWPOINT")]
cl, cr = pix(f"{tmp}/stretched.bmp", *vps[0]), pix(f"{tmp}/stretched.bmp", *vps[1])
check("a picture is drawn stretched to its new rectangle: still red on the left half and blue on the right", all(abs(p - q) < 50 for p, q in zip(cl, (255, 0, 0))) and all(abs(p - q) < 50 for p, q in zip(cr, (0, 0, 255))), f"{cl} {cr}")
print(f"resize: {checks} checks, {len(fails)} failures")
print("\nRESIZE CHECKS PASSED" if not fails else f"\nRESIZE CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
