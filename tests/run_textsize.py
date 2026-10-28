"""Resizing text and labels with handles (TinyCAD's CDrawText::MoveField and CDrawLabel::MoveField): select one text or label and the tracker's eight handles
appear round its box; dragging a handle does not stretch the text but changes its font: the height by the movement across the line of the text and, if
the font has a width of its own, the width in proportion to the length the box is dragged to. A text's position follows the box's corner; a normal label's
connection point does (the other kinds of label keep theirs); a label has no handle on its middle. Checked against a Python port of the two MoveField
functions and of COption::ChangeFontSize, with the object's own state (corners, direction, font, the recorded widths) read from the program as input:
  - every handle of texts and labels of every direction and kind, dragged by several amounts: the object's position or connection point, its font's height and
    width, and the length the box is dragged to are compared with the port's, as the program reports them and as they are saved (the font by its content)
  - undo gives back the original object and font, redo the resized one; each drag is one undo step called Resize; nothing else in the design changes
  - Ctrl on a corner keeps the shape of the box
  - a press on the middle of the box moves the text and does not change its font; the handles are drawn; the text is really redrawn bigger
Needs the built program and ImageMagick."""
import copy, glob, math, os, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from designoracle import sig, resource_maps, objects, sheet0
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or shutil.which("convert") is None:
    print("Text resize checks skipped: need xvfb-run, ImageMagick and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
env = dict(os.environ, HOME=os.path.join(tmp, "home")); os.makedirs(env["HOME"])
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:420])
def run(script, timeout=250):
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=env)
    return r.stdout.split("\n"), r.returncode, r.stderr
def grid(v): return round(v / 2.0) * 2.0
FMT = lambda v: "%.4f" % v
def pix(path, x, y):
    o = subprocess.run(["convert", path, "-crop", "1x1+%d+%d" % (x, y), "-format", "%[fx:int(255*r)],%[fx:int(255*g)],%[fx:int(255*b)]", "info:"], capture_output=True, text=True).stdout
    return tuple(int(v) for v in o.split(","))
def ink(path, a, b):
    x1, x2 = sorted((a[0], b[0])); y1, y2 = sorted((a[1], b[1]))
    o = subprocess.run(["convert", path, "-crop", f"{max(1, x2 - x1)}x{max(1, y2 - y1)}+{x1}+{y1}", "-colorspace", "Gray", "-threshold", "95%", "-format", "%[fx:int((1-mean)*w*h+0.5)]", "info:"], capture_output=True, text=True).stdout.strip()
    return int(o or 0)
# ---------- TinyCAD's functions, ported independently ----------
def move_field(st, w, r):
    """CDrawText::MoveField / CDrawLabel::MoveField followed by COption::ChangeFontSize, on the object's state (internal units)"""
    A, B, d, tbw, obw, ow = st["a"], st["b"], st["dir"], st["tbw"], st["obw"], st["ow"]
    if d >= 2: L, T, Rt, Bt = A[0], B[1], A[0] + tbw, A[1]
    else: L, T, Rt, Bt = B[0], A[1] + tbw, A[0], A[1]
    rx, ry = r
    if w == 0: L += r[0]; T += r[1]; ry = -ry
    elif w == 1: Rt += r[0]; T += r[1]; ry = -ry; rx = -rx
    elif w == 2: Rt += r[0]; Bt += r[1]; rx = -rx
    elif w == 3: L += r[0]; Bt += r[1]
    elif w == 4: T += r[1]; ry = -ry
    elif w == 5: Rt += r[0]; rx = -rx
    elif w == 6: Bt += r[1]
    elif w == 7: L += r[0]
    out = dict(a=None, active=None)
    if st["kind"] == "text": out["a"] = (L, Bt) if d >= 2 else (Rt, Bt)
    else:
        out["active"] = st["active"]
        if st["style"] == 0: out["active"] = (L, Bt) if d >= 2 else (Rt, Bt)
    out["tbw"] = (Rt - L) if d >= 2 else -(Bt - T)
    fh, fw = st["fh"], st["fw"]
    if obw > 0:
        delta = rx if d < 2 else -ry
        fh += int(delta)                              # (a whole number of units, the part after the point dropped as in C)
        width = (ow * out["tbw"]) / obw
        if width != 0: fw = int(width)
    out["fh"], out["fw"] = fh, fw
    return out
def aspect_keep(w, r, ratio):
    x, y = r
    if w in (1, 3):
        if abs(x) > abs(y): y = -x * ratio
        else: x = -y / ratio
    elif w in (0, 2):
        if abs(x) > abs(y): y = x * ratio
        else: x = y / ratio
    return (x, y)
def parse(lines, nth=0):
    l = [x for x in lines if x.startswith("TEXTINFO ") and "none" not in x][nth].split()
    v = [float(t) for t in l[2:]]
    st = dict(kind=l[1], a=(v[0], v[1]), b=(v[2], v[3]), dir=int(v[4]), font=int(v[5]), fh=int(v[6]), fw=int(v[7]), ow=v[8], obw=v[9], tbw=v[10])      # (design units, every digit)
    if l[1] == "label": st["active"] = (v[11], v[12]); st["style"] = int(v[13])
    return st
def close(p, q, tol=2e-3): return p is not None and q is not None and all(abs(x - y) <= tol for x, y in zip(p, q))
# ---------- the objects to try: each direction and kind the samples have, with fonts that have a width and fonts that have none ----------
designs = sorted(glob.glob(os.path.join(EX, "**", "*.dsn"), recursive=True))
chosen = []; seen = set()
for path in designs:
    try: sh = sheet0(path)
    except Exception: continue
    fw = {f.get("id"): int((f.findtext("WIDTH") or "0").strip() or 0) for f in sh.findall("FONT")}
    for k, e in enumerate(objects(sh)):
        if e.tag not in ("TEXT", "LABEL"): continue
        key = (e.tag, e.get("direction"), e.get("style", "0") if e.tag == "LABEL" else "-", fw.get(e.get("font"), 0) == 0)
        if key not in seen and len(chosen) < 12 and len((e.text or "").strip()) >= 2:
            seen.add(key); chosen.append((path, k, key))
check("the samples give texts and labels of several directions and kinds", len({c[2][:3] for c in chosen}) >= 5, str([c[2] for c in chosen]))
print("objects:", [(os.path.basename(c[0]), c[1], c[2]) for c in chosen])
DELTAS = [(20, 10), (-14, -8), (0, 16), (16, 0), (30, -20), (-40, 26)]
total = exact = 0
def drags(path, k, key, deltas, tag=""):
    global total, exact
    base = os.path.basename(path) + tag; sh = sheet0(path); objs = objects(sh); om = resource_maps(sh); e = objs[k]
    o, rc, err = run(f'open "{path}"\nselidx {k}\ntextinfo\n' + "".join(f"handlepos {c}\n" for c in range(8)))
    if rc != 0 or not any(l.startswith("TEXTINFO ") and "none" not in l for l in o):
        check(f"{base} #{k}: stage 1 ran", False, "\n".join(l for l in o if l.startswith("ERROR")) + err[-200:]); return
    st = parse(o); H = {}
    for l in o:
        if l.startswith("HANDLEPOS") and "none" not in l: t = l.split(); H[int(t[1])] = (float(t[2]), float(t[3]), float(t[5]), float(t[6]))
    ex, ey = (float(v) for v in e.get("pos").split(","))
    own = st["active"] if st["kind"] == "label" else st["a"]
    check(f"{base} #{k}: the program and the file agree about the object ({e.tag}, its position, direction)", abs(own[0] / 5 - ex) < 1e-3 and abs(own[1] / 5 - ey) < 1e-3 and st["dir"] == int(e.get("direction")), f"{st} vs {(ex, ey)}")
    check(f"{base} #{k}: it has eight handles", len(H) == 8, str(len(H)))
    if len(H) != 8: return
    cases = []; script = [f'open "{path}"']
    for c in range(8):
        hx, hy, sx, sy = H[c]
        for (dx, dy) in deltas:
            tx, ty = grid(hx + dx), grid(hy + dy); n = len(cases); cases.append((c, (tx - sx, ty - sy), n))
            script += [f"selidx {k}", f"mouse down {FMT(hx)} {FMT(hy)}", f"mouse move {FMT(tx)} {FMT(ty)}", f"mouse up {FMT(tx)} {FMT(ty)}", "textinfo", f'save "{tmp}/d{n}.dsn"', "undoinfo", "undo", "textinfo", "redo", "textinfo", "undo"]
    o, rc, err = run("\n".join(script) + "\n", 290)
    check(f"{base} #{k}: the drags ran cleanly", rc == 0 and not any(l.startswith("ERROR") for l in o), "\n".join(l for l in o if l.startswith("ERROR")) + err[-200:])
    uds = [l for l in o if l.startswith("UNDOINFO")]
    fid = e.get("font"); fnt = [f for f in sh.findall("FONT") if f.get("id") == fid][0]
    bad_geo = bad_save = bad_undo = bad_step = 0; first = None
    for (c, delta, n) in cases:
        want = move_field(st, c, (delta[0] * 5, delta[1] * 5))
        got = parse(o, 3 * n); undone = parse(o, 3 * n + 1); redone = parse(o, 3 * n + 2)
        pos_ok = close(got["a"], want["a"]) if st["kind"] == "text" else close(got["active"], want["active"])
        boxlen = (got["b"][0] - got["a"][0]) if got["dir"] >= 2 else (got["b"][1] - got["a"][1])
        # with a font that has a width the length being dragged to is kept; with none the box is noted afresh when the text is laid out again, so it is the new box's
        tbw_ok = abs(got["tbw"] - want["tbw"]) < 1e-3 if st["ow"] != 0 else (abs(got["tbw"] - got["obw"]) < 1e-6 and abs(got["obw"] - boxlen) < 1e-6)
        if not (pos_ok and got["fh"] == want["fh"] and got["fw"] == want["fw"] and tbw_ok):
            bad_geo += 1; first = first or (c, tuple(round(v, 2) for v in delta), got, want)
        if not (undone["fh"] == st["fh"] and undone["fw"] == st["fw"] and close(undone["a"], st["a"]) and redone["fh"] == want["fh"] and redone["fw"] == want["fw"]): bad_undo += 1
        if 'next="Resize"' not in uds[n] or "undo=1 " not in uds[n]: bad_step += 1
        try:
            s2 = sheet0(f"{tmp}/d{n}.dsn"); gm = resource_maps(s2)
            nf = copy.deepcopy(fnt); nf.find("HEIGHT").text = str(want["fh"]); nf.find("WIDTH").text = str(want["fw"])
            em = copy.deepcopy(om); em["FONT"] = dict(om["FONT"]); em["FONT"]["999"] = sig(nf, om)
            exp = copy.deepcopy(e); exp.set("font", "999")
            newpos = want["active"] if st["kind"] == "label" else want["a"]
            exp.set("pos", "%.5f,%.5f" % (newpos[0] / 5, newpos[1] / 5))
            wsig = [sig(x, om) for x in objs]; wsig[k] = sig(exp, em)
            if [sig(x, gm) for x in objects(s2)] != wsig: bad_save += 1
        except Exception: bad_save += 1
    total += len(cases); exact += len(cases) - bad_geo
    check(f"{base} #{k} ({key[0]}, direction {key[1]}{', style ' + key[2] if key[2] != '-' else ''}, font width {'none' if key[3] else 'set'}): {len(cases)} drags give TinyCAD's position, font height and width", bad_geo == 0, f"{bad_geo} wrong; first {first}")
    check(f"{base} #{k}: the saved file has that position and a font of that height and width, and nothing else changed", bad_save == 0, str(bad_save))
    check(f"{base} #{k}: undo gives back the original object and font, redo the resized one", bad_undo == 0, str(bad_undo))
    check(f"{base} #{k}: each drag is one undo step called Resize", bad_step == 0, str(bad_step))
for (path, k, key) in chosen: drags(path, k, key, DELTAS)
# the same objects with a font that has no width of its own: the width is left alone and the box is noted afresh each time
nowidth = []
for n, (path, k, key) in enumerate([c for c in chosen if c[2][0] == "LABEL"][:2] + [c for c in chosen if c[2][0] == "TEXT"][:1]):
    r = ET.parse(path); root = r.getroot(); sh = root.findall("TinyCAD")[0] if root.tag == "TinyCADSheets" else root
    e = objects(sh)[k]
    for f in sh.findall("FONT"):
        if f.get("id") == e.get("font"): f.find("WIDTH").text = "0"
    p2 = os.path.join(tmp, f"nowidth{n}.dsn"); r.write(p2, encoding="utf-8", xml_declaration=True); nowidth.append((p2, k, key[:3] + (True,)))
for (p2, k, key) in nowidth: drags(p2, k, key, DELTAS[:4], " (font width 0)")
print(f"drags: {total} drags on {len(chosen)} objects, {exact} exact, {checks} checks, {len(fails)} failures")

# ---------- a drag in several moves: each move is checked against the program's own state before it ----------
def multi(path, k, key, tag):
    base = os.path.basename(path) + tag
    o, rc, err = run(f'open "{path}"\nselidx {k}\ntextinfo\n' + "".join(f"handlepos {c}\n" for c in range(8)))
    st0 = parse(o); H = {}
    for l in o:
        if l.startswith("HANDLEPOS") and "none" not in l: t = l.split(); H[int(t[1])] = (float(t[2]), float(t[3]), float(t[5]), float(t[6]))
    script = [f'open "{path}"']; cases = []
    for c in (0, 2, 4, 5, 6, 7):
        hx, hy, sx, sy = H[c]; steps = [(grid(hx + 8), grid(hy + 6)), (grid(hx + 18), grid(hy - 4)), (grid(hx + 6), grid(hy + 14))]
        cases.append((c, (sx, sy), steps)); script += [f"selidx {k}", f"mouse down {FMT(hx)} {FMT(hy)}"]
        for (tx, ty) in steps: script += [f"mouse move {FMT(tx)} {FMT(ty)}", "textinfo"]
        script += [f"mouse up {FMT(steps[-1][0])} {FMT(steps[-1][1])}", "undo"]
    o, rc, err = run("\n".join(script) + "\n")
    bad = bad_reset = 0; first = None; n = 0
    for (c, (sx, sy), steps) in cases:
        prev = st0; last = (sx * 5, sy * 5)
        for (tx, ty) in steps:
            r = (tx * 5 - last[0], ty * 5 - last[1]); last = (tx * 5, ty * 5)
            want = move_field(prev, c, r); got = parse(o, n); n += 1
            pos_ok = close(got["a"], want["a"]) if prev["kind"] == "text" else close(got["active"], want["active"])
            if not (pos_ok and got["fh"] == want["fh"] and got["fw"] == want["fw"]): bad += 1; first = first or (c, got, want)
            if key[3]:       # a font with no width of its own: the box is noted afresh whenever the text is laid out
                if not (abs(got["tbw"] - got["obw"]) < 1e-6 and got["ow"] == 0): bad_reset += 1
            else:            # a font with a width: what the drag started from is kept, and the length being dragged to carries on
                if not (abs(got["obw"] - st0["obw"]) < 1e-6 and got["ow"] == st0["ow"]): bad_reset += 1
            prev = got
    check(f"{base} #{k}: a drag in three moves ({key[0]}, direction {key[1]}, font width {'none' if key[3] else 'set'}): each move is TinyCAD's, given the state the last one left", bad == 0, f"{bad} wrong; first {first}")
    check(f"{base} #{k}: " + ("with no font width the lengths are noted afresh at each layout" if key[3] else "with a font width the lengths noted at the start are kept"), bad_reset == 0, str(bad_reset))
for (path, k, key) in chosen[:3]: multi(path, k, key, "")
for (p2, k, key) in nowidth[:2]: multi(p2, k, key, " (font width 0)")

# ---------- Ctrl on the corners ----------
path, k, key = chosen[0]
o, rc, err = run(f'open "{path}"\nselidx {k}\ntextinfo\n' + "".join(f"handlepos {c}\n" for c in range(4)))
st = parse(o); H = {}
for l in o:
    if l.startswith("HANDLEPOS") and "none" not in l: t = l.split(); H[int(t[1])] = (float(t[2]), float(t[3]), float(t[5]), float(t[6]))
ratio = abs((st["b"][1] - st["a"][1]) / (st["b"][0] - st["a"][0])); script = [f'open "{path}"']; cases = []
for c in range(4):
    hx, hy, sx, sy = H[c]; tx, ty = grid(hx + 16), grid(hy + 6)
    for ctrl in (False, True):
        n = len(cases); cases.append((c, (tx * 5 - sx * 5, ty * 5 - sy * 5), ctrl))
        script += [f"selidx {k}", f"mouse down {FMT(hx)} {FMT(hy)}", f"mouse move {FMT(tx)} {FMT(ty)}" + (" ctrl" if ctrl else ""), f"mouse up {FMT(tx)} {FMT(ty)}", "textinfo", "undo"]
o, rc, err = run("\n".join(script) + "\n")
bad = 0; first = None
for n, (c, r, ctrl) in enumerate(cases):
    rr = aspect_keep(c, r, ratio) if (ctrl and ratio > 0) else r
    want = move_field(st, c, rr); got = parse(o, n)
    pos_ok = close(got["a"], want["a"]) if st["kind"] == "text" else close(got["active"], want["active"])
    if not (pos_ok and got["fh"] == want["fh"] and got["fw"] == want["fw"]): bad += 1; first = first or (c, ctrl, got, want)
check("with Ctrl held a corner keeps the shape of the box (the movement is adjusted before the font is changed), as without Ctrl it does not", bad == 0, f"{bad} wrong; first {first}")
# ---------- the middle, the handles drawn, the text redrawn ----------
for (path, k, key) in chosen[:4]:
    base = os.path.basename(path); sh = sheet0(path); e = objects(sh)[k]
    o, rc, err = run(f'open "{path}"\nselidx {k}\ntextinfo\n')
    st = parse(o); mid = ((st["a"][0] + st["b"][0]) / 10, (st["a"][1] + st["b"][1]) / 10)
    tx, ty = grid(mid[0] + 20), grid(mid[1] + 10)
    o, rc, err = run(f'open "{path}"\nselidx {k}\nmouse down {FMT(mid[0])} {FMT(mid[1])}\nmouse move {FMT(tx)} {FMT(ty)}\nmouse up {FMT(tx)} {FMT(ty)}\ntextinfo\nundoinfo\n')
    after = parse(o); ud = [l for l in o if l.startswith("UNDOINFO")][0]
    moved = (after["a"][0] - st["a"][0], after["a"][1] - st["a"][1])
    check(f"{base} #{k}: a press on the middle of the box moves the {st['kind']} and leaves its font alone (a move, not a resize)", after["fh"] == st["fh"] and after["fw"] == st["fw"] and (abs(moved[0]) > 1 or abs(moved[1]) > 1) and 'next="Move"' in ud, f"{moved} {ud}")
path, k, key = chosen[0]
o, rc, err = run(f'open "{path}"\nselidx {k}\n' + "".join(f"handlepos {c}\n" for c in range(8)))
H = {}
for l in o:
    if l.startswith("HANDLEPOS") and "none" not in l: t = l.split(); H[int(t[1])] = (float(t[2]), float(t[3]))
o, rc, err = run(f'open "{path}"\nselidx {k}\n' + "".join(f"viewpoint {FMT(H[c][0])} {FMT(H[c][1])}\n" for c in range(8)) + f'shot "{tmp}/h.bmp"\n')
vp = [tuple(int(v) for v in l.split()[1:]) for l in o if l.startswith("VIEWPOINT")]
check("the eight handles are drawn round a selected text or label: a black square at each place", all(pix(f"{tmp}/h.bmp", *p) == (0, 0, 0) for p in vp), str([pix(f"{tmp}/h.bmp", *p) for p in vp]))
# a label made bigger really is drawn bigger
lab = next(c for c in chosen if c[2][0] == "LABEL")
path, k, key = lab; sh = sheet0(path)
o, rc, err = run(f'open "{path}"\nselidx {k}\ntextinfo\nhandlepos 4\n'); st = parse(o); hp = [l for l in o if l.startswith("HANDLEPOS")][0].split()
hx, hy, sx, sy = float(hp[2]), float(hp[3]), float(hp[5]), float(hp[6]); tx, ty = grid(hx), grid(hy - 10)
bx = st["a"][0] / 5; by = st["a"][1] / 5
o, rc, err = run(f'open "{path}"\nselclear\nselidx {k}\nviewpoint {FMT(bx - 2)} {FMT(by - 14)}\nviewpoint {FMT(bx + (st["b"][0] - st["a"][0]) / 5 + 6)} {FMT(by + 3)}\nmouse down {FMT(hx)} {FMT(hy)}\nmouse move {FMT(tx)} {FMT(ty)}\nmouse up {FMT(tx)} {FMT(ty)}\nselclear\nshot "{tmp}/big.bmp"\nundo\nselclear\nshot "{tmp}/small.bmp"\n')
vp = [tuple(int(v) for v in l.split()[1:]) for l in o if l.startswith("VIEWPOINT")]
a_, b_ = vp[0], vp[1]
check("the text really is drawn bigger after its handle is dragged out (more marks in the same area), and as before once undone", ink(f"{tmp}/big.bmp", a_, b_) > ink(f"{tmp}/small.bmp", a_, b_) * 1.3, f"{ink(f'{tmp}/small.bmp', a_, b_)} -> {ink(f'{tmp}/big.bmp', a_, b_)}")
print(f"text resize: {checks} checks, {len(fails)} failures")
print("\nTEXT RESIZE CHECKS PASSED" if not fails else f"\nTEXT RESIZE CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
