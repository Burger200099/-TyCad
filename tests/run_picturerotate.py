"""Turning and flipping a picture, on the screen. TinyCAD only moves a picture's two corners when it is turned or flipped (the picture stays upright, squeezed into the turned box); here the
picture itself turns and flips with its corners. A picture with a different color in each corner (red, green / blue, yellow) is turned and flipped by script through the real commands, and what
is drawn is compared with the geometry (following points through TinyCAD's formulas for turning left, turning right and flipping):
  - after any sequence of up to 6 operations (all eight orientations are reached) each corner of the box shows the color the geometry puts there; the box has the picture's own shape (a
    quarter turn makes it taller instead of wider), and the picture's orientation is what the operations make it
  - undo and redo take the picture and its orientation back and forth; a picture that is turned and then saved and opened again is the same, and one that was not turned is written exactly as
    before (the two new attributes appear only when needed, and TinyCAD skips them)
  - turning a selection that holds a picture and other things turns them together (their positions relative to each other turn as the operation says); copy and paste and Copy to keep the
    orientation; resizing the picture afterwards keeps it and does not squeeze it; a JPEG is turned too
Needs the built program and ImageMagick."""
import itertools, os, random, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or shutil.which("convert") is None:
    print("Picture rotation checks skipped: need xvfb-run, ImageMagick and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:420])
def run(script, timeout=120):
    h = tempfile.mkdtemp(dir=tmp)
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n"), r.returncode, r.stderr
def pix(path, x, y):
    o = subprocess.run(["convert", path, "-crop", "1x1+%d+%d" % (x, y), "-format", "%[fx:int(255*r)],%[fx:int(255*g)],%[fx:int(255*b)]", "info:"], capture_output=True, text=True).stdout
    return tuple(int(v) for v in o.split(","))
def near(c, want, tol=60): return all(abs(a - b) <= tol for a, b in zip(c, want))
pics = os.path.join(tmp, "pics"); os.makedirs(pics)
RED, GREEN, BLUE, YELLOW = (255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0)
quad = os.path.join(pics, "quad.png"); subprocess.run(["convert", "-size", "60x40", "xc:red", "-fill", "lime", "-draw", "rectangle 30,0 59,19", "-fill", "blue", "-draw", "rectangle 0,20 29,39", "-fill", "yellow", "-draw", "rectangle 30,20 59,39", quad], check=True)
quadj = os.path.join(pics, "quad.jpg"); subprocess.run(["convert", "-size", "60x40", "xc:red", "-fill", "lime", "-draw", "rectangle 30,0 59,19", "-fill", "blue", "-draw", "rectangle 0,20 29,39", "-fill", "yellow", "-draw", "rectangle 30,20 59,39", "-quality", "95", quadj], check=True)
SRC = {(-1, -1): RED, (1, -1): GREEN, (-1, 1): BLUE, (1, 1): YELLOW}       # a corner of the picture as it is: (-1,-1) is its top left
# ---------- the geometry ----------
def move(p, op):
    x, y = p
    return {"left": (y, -x), "right": (-y, x), "flip": (-x, y)}[op]
def matrix_of(ops):
    cx, cy = (1, 0), (0, 1)
    for op in ops: cx, cy = move(cx, op), move(cy, op)
    return (cx[0], cy[0], cx[1], cy[1])
def expected_corner(m, d):
    """the color shown at displayed corner d = (dx, dy): the picture's corner that the orientation moves there, found by taking d back through the matrix (its transpose)"""
    a, b, c, dd = m
    return SRC[(a * d[0] + c * d[1], b * d[0] + dd * d[1])]
def decompose(ops):
    m = matrix_of(ops)
    for mirror in (0, 1):
        for turns in range(4):
            if matrix_of(([ "flip"] if mirror else []) + ["right"] * turns) == m: return turns, mirror
def picinfo(lines, nth=-1):
    l = [x for x in lines if x.startswith("PICINFO ") and "none" not in x][nth]
    t = re.match(r"PICINFO a=([-\d.]+),([-\d.]+) b=([-\d.]+),([-\d.]+) rot=(-?\d+) mirror=(\d)", l)
    ax, ay, bx, by = (float(t.group(i)) for i in range(1, 5))
    return dict(x1=min(ax, bx), x2=max(ax, bx), y1=min(ay, by), y2=max(ay, by), rot=int(t.group(5)), mirror=int(t.group(6)))
def place(path): return f'newdoc "ISO A4" landscape\npicture "{path}"\nmouse down 40 40\nselidx 0\n'
def corner_points(b):
    w, h = b["x2"] - b["x1"], b["y2"] - b["y1"]; cx, cy = (b["x1"] + b["x2"]) / 2, (b["y1"] + b["y2"]) / 2
    return {d: (cx + d[0] * w / 4, cy + d[1] * h / 4) for d in SRC}
def shown(path, ops, name):
    """run the operations, and read the colors at the four corners of the box (two runs: one to find the box, one to sample it)"""
    s = place(path) + "".join(f"rotate {op}\n" for op in ops) + "picinfo\n"
    o, rc, err = run(s); b = picinfo(o); pts = corner_points(b)
    o2, rc, err = run(s + "".join(f"viewpoint {pts[d][0]:.4f} {pts[d][1]:.4f}\n" for d in SRC) + f"shot {tmp}/{name}.bmp\n")
    vp = [tuple(int(v) for v in l.split()[1:]) for l in o2 if l.startswith("VIEWPOINT")]
    return b, {d: pix(f"{tmp}/{name}.bmp", *vp[i]) for i, d in enumerate(SRC)}
# ---------- every orientation, by sequences of operations ----------
rnd = random.Random(14)
seqs = [(), ("right",), ("left",), ("flip",), ("right", "flip"), ("flip", "right"), ("left", "flip"), ("right", "right"), ("flip", "left"), ("right", "right", "right")]
seqs += [tuple(rnd.choice(["left", "right", "flip"]) for _ in range(rnd.randint(2, 6))) for _ in range(14)]
reached = set(); bad_col = bad_attr = bad_shape = 0; first = None
for n, ops in enumerate(seqs):
    b, cols = shown(quad, ops, f"s{n}"); m = matrix_of(ops); reached.add(m); turns, mirror = decompose(ops)
    for d in SRC:
        if not near(cols[d], expected_corner(m, d)): bad_col += 1; first = first or (ops, d, cols[d], expected_corner(m, d))
    if (b["rot"], b["mirror"]) != (turns, mirror): bad_attr += 1; first = first or ("attr", ops, b, turns, mirror)
    w, h = b["x2"] - b["x1"], b["y2"] - b["y1"]
    quarter = m[1] != 0
    if abs((h / w) - (3 / 2 if quarter else 2 / 3)) > 0.02: bad_shape += 1; first = first or ("shape", ops, w, h)
check(f"{len(seqs)} sequences of operations (all eight orientations are reached): each of the four corners of the box shows the color the geometry puts there", bad_col == 0 and len(reached) == 8, f"{bad_col} wrong, {len(reached)} orientations; first {first}")
check("and the picture's own orientation is what the operations make it (turns to the right, flipped first or not)", bad_attr == 0, str(first))
check("and the box has the picture's shape: the 3:2 picture is 2:3 in the box after a quarter turn, 3:2 otherwise, never squeezed", bad_shape == 0, str(first))
# ---------- undo, save, open ----------
ops = ("right", "flip", "left")
s = place(quad) + "picinfo\n" + "".join(f"rotate {op}\npicinfo\n" for op in ops) + f'save "{tmp}/turned.dsn"\nundo\npicinfo\nundo\npicinfo\nundo\npicinfo\nredo\npicinfo\nredo\npicinfo\nredo\npicinfo\n'
o, rc, err = run(s); infos = [picinfo([l], 0) for l in o if l.startswith("PICINFO ") and "none" not in l]
key = lambda b: (round(b["x1"], 3), round(b["y1"], 3), round(b["x2"], 3), round(b["y2"], 3), b["rot"], b["mirror"])
fwd = [key(i) for i in infos[:4]]; back = [key(i) for i in infos[4:7]]; again = [key(i) for i in infos[7:10]]
check("each operation is one undo step: undoing three times goes back through the three states, picture and box together, and redoing goes forward again", back == [fwd[2], fwd[1], fwd[0]] and again == [fwd[1], fwd[2], fwd[3]], f"{fwd} {back} {again}")
r = ET.parse(f"{tmp}/turned.dsn").getroot(); sh = r.findall("TinyCAD")[0] if r.tag == "TinyCADSheets" else r
mf = sh.find("METAFILE"); turns, mirror = decompose(ops)
check("saved, the picture has rot and mirror attributes that say its orientation (as TinyCAD never wrote them, TinyCAD skips them), and its object number, box and picture number as before", mf.get("rot") == (str(turns) if turns else None) and mf.get("mirror") == ("1" if mirror else None) and mf.get("a") and mf.get("b") and mf.get("id") is not None, str(mf.attrib))
o, rc, err = run(f'open "{tmp}/turned.dsn"\nselidx 0\npicinfo\n'); b2 = picinfo(o)
check("opened again, it is in the same orientation, with the same box", key(b2) == fwd[3], f"{key(b2)} {fwd[3]}")
o, rc, err = run(place(quad) + f'save "{tmp}/upright.dsn"\n'); r = ET.parse(f"{tmp}/upright.dsn").getroot(); sh = r.findall("TinyCAD")[0] if r.tag == "TinyCADSheets" else r
check("a picture that was never turned is written exactly as TinyCAD writes it: the object number, a, b and id and nothing else", sorted(sh.find("METAFILE").attrib) == ["a", "b", "id", "oid"], str(sh.find("METAFILE").attrib))
o, rc, err = run(place(quad) + f'rotate right\nrotate left\nsave "{tmp}/back.dsn"\n'); r = ET.parse(f"{tmp}/back.dsn").getroot(); sh = r.findall("TinyCAD")[0] if r.tag == "TinyCADSheets" else r
check("and one that has been turned and turned back is upright again, written without the new attributes", sorted(sh.find("METAFILE").attrib) == ["a", "b", "id", "oid"], str(sh.find("METAFILE").attrib))
# ---------- with other things, copy and paste, resizing, a JPEG ----------
rect = ('<RECTANGLE a="60,40" b="80,52" style="0" fill="0" />\r\n')
base = open(os.path.join(os.environ.get("TC_EXAMPLES", "examples"), "circuits", "PSU.dsn"), encoding="utf-8", errors="replace").read()
o, rc, err = run(place(quad) + f'tool rect\nmouse down 100 60\nmouse move 120 72\nmouse up 120 72\nselectall\npicinfo\n')
o, rc, err = run(place(quad) + 'tool rect\nmouse down 100 60\nmouse move 120 72\nmouse up 120 72\ntool select\nselectall\nsave "' + f'{tmp}/g0.dsn"\nrotate right\nsave "{tmp}/g1.dsn"\n')
def centres(path):
    r = ET.parse(path).getroot(); sh = r.findall("TinyCAD")[0] if r.tag == "TinyCADSheets" else r
    def c(tag):
        e = sh.find(tag); ax, ay = (float(v) for v in e.get("a").split(",")); bx, by = (float(v) for v in e.get("b").split(","))
        return ((ax + bx) / 2, (ay + by) / 2)
    return c("METAFILE"), c("RECTANGLE"), sh.find("METAFILE")
(p0, r0, m0), (p1, r1, m1) = centres(f"{tmp}/g0.dsn"), centres(f"{tmp}/g1.dsn")
rel0 = (p0[0] - r0[0], p0[1] - r0[1]); rel1 = (p1[0] - r1[0], p1[1] - r1[1]); want_rel = move(rel0, "right")
check("turning a selection of a picture and a rectangle turns them together: the picture's place relative to the rectangle turns right, and the picture turns right too (rot=1)", abs(rel1[0] - want_rel[0]) < 0.6 and abs(rel1[1] - want_rel[1]) < 0.6 and m1.get("rot") == "1", f"{rel0} {rel1} {want_rel} {m1.attrib}")
o, rc, err = run(place(quad) + 'rotate right\nrotate flip\npicinfo\ncopy\npaste\nmouse move 120 90\nmouse down 120 90\npicinfo\nsave "' + f'{tmp}/pasted.dsn"\n')
infos = [picinfo([l], 0) for l in o if l.startswith("PICINFO ") and "none" not in l]
r = ET.parse(f"{tmp}/pasted.dsn").getroot(); sh = r.findall("TinyCAD")[0] if r.tag == "TinyCADSheets" else r
mfs = sh.findall("METAFILE")
check("copy and paste keep the orientation: the pasted picture is turned right and flipped as the one it was copied from, and there are two pictures", len(mfs) == 2 and mfs[0].get("rot") == mfs[1].get("rot") and mfs[0].get("mirror") == mfs[1].get("mirror") and mfs[1].get("mirror") == "1", str([m.attrib for m in mfs]))
o, rc, err = run(place(quad) + f'rotate right\ncopyto "{tmp}/copied.dsn"\n'); r = ET.parse(f"{tmp}/copied.dsn").getroot(); sh = r.findall("TinyCAD")[0] if r.tag == "TinyCADSheets" else r
check("Copy to keeps it too (the saved file's picture is turned right)", sh.find("METAFILE").get("rot") == "1", str(sh.find("METAFILE").attrib))
# resizing keeps the orientation and the corners' colors
o, rc, err = run(place(quad) + "rotate right\nrotate flip\npicinfo\nhandlepos 2\n"); b = picinfo(o); hp = [l for l in o if l.startswith("HANDLEPOS")][0].split()
hx, hy, sx, sy = float(hp[2]), float(hp[3]), float(hp[5]), float(hp[6])
s = place(quad) + f"rotate right\nrotate flip\nmouse down {hx:.4f} {hy:.4f}\nmouse move {sx + 14:.4f} {sy + 10:.4f}\nmouse up {sx + 14:.4f} {sy + 10:.4f}\npicinfo\n"
o, rc, err = run(s); b2 = picinfo(o); pts = corner_points(b2)
o, rc, err = run(s + "".join(f"viewpoint {pts[d][0]:.4f} {pts[d][1]:.4f}\n" for d in SRC) + f"shot {tmp}/rs.bmp\n"); vp = [tuple(int(v) for v in l.split()[1:]) for l in o if l.startswith("VIEWPOINT")]
m = matrix_of(("right", "flip"))
check("resizing the turned picture by a handle keeps its orientation and the box bigger, and the corners still show the geometry's colors (it is not squeezed or turned back)", (b2["rot"], b2["mirror"]) == (b["rot"], b["mirror"]) and (b2["x2"] - b2["x1"]) > (b["x2"] - b["x1"]) + 5 and all(near(pix(f"{tmp}/rs.bmp", *vp[i]), expected_corner(m, d)) for i, d in enumerate(SRC)), f"{b} {b2}")
b, cols = shown(quadj, ("right", "flip"), "jpg"); m = matrix_of(("right", "flip"))
check("a JPEG is turned and flipped too: its four corners show the geometry's colors", all(near(cols[d], expected_corner(m, d), 90) for d in SRC), str(cols))
# ---------- a picture that is part of a symbol follows the symbol ----------
o, rc, err = run(place(quad) + f'save "{tmp}/withpic.dsn"\n')
t = open(f"{tmp}/withpic.dsn", encoding="utf-8").read(); mf_text = re.search(r"<METAFILE[^>]*/>", t).group(0)
t = t.replace(mf_text, "")
symdef = ('<SYMBOLDEF id="1"><NAME type="0">PICSYM</NAME><REF type="0">P?</REF><DESCRIPTION>picture</DESCRIPTION><PPP>1</PPP><REF_POINT power="0" part="0" pos="12,10" />'
          '<TinyCAD><METAFILE a="6,6" b="18,14" id="1" /></TinyCAD></SYMBOLDEF>\r\n')
place_sym = '<SYMBOL id="1" pos="60,40" part="0" rotate="0" can_scale="0" show_power="0" scale_x="1" scale_y="1"><FIELD type="0" description="Ref" value="P1" show="0" pos="0,0" /></SYMBOL>\r\n'
j = t.rindex("</TinyCAD>"); symfile = os.path.join(tmp, "sympic.dsn"); open(symfile, "w", encoding="utf-8").write(t[:j] + symdef + place_sym + t[j:])
def find_picture(shotpath, box):
    """the bounding box of the picture on the screen (the only thing in that part of the sheet with its colors), found by looking for them"""
    x1, y1, x2, y2 = box
    out = subprocess.run(["convert", shotpath, "-crop", f"{x2 - x1}x{y2 - y1}+{x1}+{y1}", "+repage", "-depth", "8", "txt:-"], capture_output=True, text=True).stdout
    pts = {}
    for line in out.split("\n")[1:]:
        m = re.match(r"(\d+),(\d+): \((\s*\d+),(\s*\d+),(\s*\d+)", line)
        if m: pts[(int(m.group(1)), int(m.group(2)))] = (int(m.group(3)), int(m.group(4)), int(m.group(5)))
    cols = [(x, y) for (x, y), c in pts.items() if any(near(c, k, 50) for k in (RED, GREEN, BLUE, YELLOW))]
    if not cols: return None
    xs = [x for x, y in cols]; ys = [y for x, y in cols]
    return min(xs), min(ys), max(xs), max(ys), pts
sym_seqs = [(), ("right",), ("left",), ("flip",), ("right", "flip"), ("flip", "right"), ("right", "right"), ("left", "flip", "left"), ("flip", "right", "right"), ("right", "right", "right", "flip")]
bad = []; reached = set()
for n, ops in enumerate(sym_seqs):
    o, rc, err = run(f'open "{symfile}"\nselidx 0\n' + "".join(f"rotate {op}\n" for op in ops) + f'selclear\nviewpoint 20 10\nviewpoint 130 100\nshot {tmp}/sym{n}.bmp\n')
    vp = [tuple(int(v) for v in l.split()[1:]) for l in o if l.startswith("VIEWPOINT")]
    box = (vp[0][0], vp[0][1], vp[1][0], vp[1][1]); f = find_picture(f"{tmp}/sym{n}.bmp", box); m = matrix_of(ops); reached.add(m)
    if f is None: bad.append((ops, "no picture")); continue
    x1, y1, x2, y2, pts = f; w, h = x2 - x1 + 1, y2 - y1 + 1
    ok = True
    for d in SRC:
        px_, py_ = int(x1 + (d[0] + 1) / 2 * (w - 1) * 0.5 + (w - 1) * 0.25) if d[0] < 0 else int(x1 + (w - 1) * 0.75), int(y1 + (h - 1) * 0.25) if d[1] < 0 else int(y1 + (h - 1) * 0.75)
        if d[0] < 0: px_ = int(x1 + (w - 1) * 0.25)
        c = pts.get((px_, py_), (0, 0, 0))
        if not near(c, expected_corner(m, d), 60): ok = False; bad.append((ops, d, c, expected_corner(m, d)))
    quarter = m[1] != 0
    if abs((h / w) - (1.5 if quarter else 2 / 3)) > 0.12: bad.append((ops, "shape", w, h))
check(f"a picture inside a symbol follows the symbol: after {len(sym_seqs)} sequences of turns and flips of the symbol (all eight orientations) its four corners show the geometry's colors and it has the right shape", not bad and len(reached) == 8, f"{len(reached)} orientations; {bad[:3]}")
print(f"picture rotation: {checks} checks, {len(fails)} failures")
print("\nPICTURE ROTATION CHECKS PASSED" if not fails else f"\nPICTURE ROTATION CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
