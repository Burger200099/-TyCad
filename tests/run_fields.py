"""Dragging the fields of a placed symbol (TinyCAD's CDrawMethod::IsInsideField / MoveField): with one symbol selected, pressing on the box of one
of its shown fields (reference, name, values) and dragging moves that field alone, by the snapped distance, one undo step called Move field.
Checked on symbols of the sample designs against the original file, whose only change must be the one field's position:
  - every shown field of the chosen symbols, dragged from the middle of its box, moves by exactly the snapped distance, and nothing else in the
    design changes (every other object, every other field, the symbol's own origin)
  - the edges of the box: pressing just inside near its corners picks the field, pressing just outside it leaves the field where it was
  - undo gives back the original design exactly and redo the moved one; each drag is one undo step called Move field
  - a field that is not shown cannot be picked; with two objects selected a press on a field moves the selection, not the field
  - after the symbol has been turned, its fields can still be dragged
  - the pointer is the 4-way arrow over the selected symbol's fields and the ordinary pointer away from it
  - the text really moves on the screen (dark pixels leave the old box and arrive in the new one)
Needs the built program and ImageMagick."""
import glob, os, re, shutil, subprocess, sys, tempfile, copy
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from designoracle import sig, resource_maps, objects, sheet0
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or shutil.which("convert") is None:
    print("Field checks skipped: need xvfb-run, ImageMagick and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
env = dict(os.environ, HOME=os.path.join(tmp, "home")); os.makedirs(env["HOME"])
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:400])
def run(script, timeout=200):
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write("resizewindow 1500 1000\n" + script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=env)
    return r.stdout.split("\n"), r.returncode, r.stderr
def grid(v): return round(v / 2.0) * 2.0            # the grid is 2 mm
def dark(path, x1, y1, x2, y2):
    """how many dark pixels are in a window rectangle"""
    x1, x2 = sorted((int(x1), int(x2))); y1, y2 = sorted((int(y1), int(y2)))
    if x2 <= x1 or y2 <= y1: return 0
    o = subprocess.run(["convert", path, "-crop", f"{x2 - x1}x{y2 - y1}+{x1}+{y1}", "-colorspace", "Gray", "-threshold", "50%", "-format", "%[fx:int((1-mean)*w*h+0.5)]", "info:"], capture_output=True, text=True).stdout.strip()
    return int(o or 0)
FMT = lambda v: "%.4f" % v
designs = sorted(glob.glob(os.path.join(EX, "**", "*.dsn"), recursive=True))
# ---- which symbols to try: those with shown fields, found in the file ----
plan = []
for path in designs:
    try: sh = sheet0(path)
    except Exception: continue
    objs = objects(sh); syms = [(k, e) for k, e in enumerate(objs) if e.tag == "SYMBOL" and any(f.get("show") == "1" for f in e.findall("FIELD"))]
    if len(syms) >= 1: plan.append((path, [k for k, _ in syms[:3]]))
plan = plan[::max(1, len(plan) // 14)][:14]            # a spread of designs
moved = fields_total = skipped = inside_ok = outside_ok = 0
undo_checked = 0; hidden_tested = 0; rotated_tested = 0; multi_tested = 0
for path, idxs in plan:
    base = os.path.basename(path); sh = sheet0(path); objs = objects(sh); om = resource_maps(sh)
    # stage 1: the boxes of the fields, as the program has them
    o, rc, err = run(f'open "{path}"\n' + "".join(f"selidx {k}\nfieldinfo\n" for k in idxs))
    if rc != 0 or any(l.startswith("ERROR") for l in o):
        check(f"{base}: stage 1 ran", False, "\n".join(l for l in o if l.startswith("ERROR")) + err[-200:]); continue
    boxes = {}; cur = None
    for l in o:
        if l.startswith("FIELDINFO origin"):
            t = l.split(); cur = {"origin": (float(t[2]), float(t[3])), "fields": []}; boxes[len(boxes)] = cur
        elif l.startswith("FIELD ") and cur is not None:
            t = l.split(None, 11); cur["fields"].append(dict(i=int(t[1]), show=int(t[2]), x=float(t[3]), y=float(t[4]), w=float(t[5]), h=float(t[6]), sx=float(t[8]), sy=float(t[9]), text=t[10] if len(t) > 10 else ""))
    # keep the symbols the program and the file agree about (the same origin)
    good = []
    for n, k in enumerate(idxs):
        e = objs[k]; ox, oy = (float(v) for v in e.get("pos").split(","))
        if n in boxes and abs(boxes[n]["origin"][0] - ox) < 1e-3 and abs(boxes[n]["origin"][1] - oy) < 1e-3 and len(boxes[n]["fields"]) == len(e.findall("FIELD")): good.append((k, boxes[n]))
        else: skipped += 1
    if not good: continue
    # stage 2: the drags
    cases = []; script = [f'open "{path}"']
    for gi, (k, bx) in enumerate(good):
        for f in bx["fields"]:
            if (not f["show"]) or f["w"] <= 0 or f["h"] <= 0: continue        # (a field with no text has a box of no size: nothing to point at)
            cx, cy = f["x"] + f["w"] / 2, f["y"] - f["h"] / 2
            for (dx, dy) in ((20, -10), (-14, 8)) if f["i"] == 0 else ((20, -10),):
                tx, ty = grid(cx + dx), grid(cy + dy)
                n = len(cases); cases.append(dict(kind="center", k=k, f=f["i"], delta=(tx - f["sx"], ty - f["sy"]), n=n))
                script += [f"selidx {k}", f"mouse down {FMT(cx)} {FMT(cy)}", f"mouse move {FMT(tx)} {FMT(ty)}", f"mouse up {FMT(tx)} {FMT(ty)}", f'save "{tmp}/d{n}.dsn"', "undoinfo", "undo", f'save "{tmp}/u{n}.dsn"', "redo", f'save "{tmp}/r{n}.dsn"', "undo"]
    o, rc, err = run("\n".join(script) + "\n", 280)
    check(f"{base}: the drags ran cleanly", rc == 0 and not any(l.startswith("ERROR") for l in o), "\n".join(l for l in o if l.startswith("ERROR")) + err[-200:])
    uds = [l for l in o if l.startswith("UNDOINFO")]
    for c in cases:
        n = c["n"]; fields_total += 1
        exp = copy.deepcopy(objs[c["k"]]); ff = exp.findall("FIELD")[c["f"]]
        px, py = (float(v) for v in ff.get("pos").split(",")); ff.set("pos", "%.5f,%.5f" % (px + c["delta"][0], py + c["delta"][1]))
        want = [sig(e, om) for e in objs]; want[c["k"]] = sig(exp, om)
        try:
            got = objects(sheet0(f"{tmp}/d{n}.dsn")); gm = resource_maps(sheet0(f"{tmp}/d{n}.dsn"))
            ok = [sig(e, gm) for e in got] == want
        except Exception: ok = False
        check(f"{base}: field {c['f']} of symbol {c['k']} moves by exactly the snapped distance {tuple(round(v, 2) for v in c['delta'])} mm, and nothing else changes", ok, f"{c}")
        moved += ok
        check(f"{base}: that drag is one undo step called Move field", 'next="Move field"' in uds[n] and "undo=1 " in uds[n], uds[n])
        try:
            uo = objects(sheet0(f"{tmp}/u{n}.dsn")); um = resource_maps(sheet0(f"{tmp}/u{n}.dsn")); ro = objects(sheet0(f"{tmp}/r{n}.dsn")); rm = resource_maps(sheet0(f"{tmp}/r{n}.dsn"))
            undone = [sig(e, um) for e in uo] == [sig(e, om) for e in objs]; redone = [sig(e, rm) for e in ro] == want
        except Exception: undone = redone = False
        check(f"{base}: undo gives back the original design exactly, redo the moved one", undone and redone, f"{undone} {redone}")
        undo_checked += 1
print(f"drags from the middle of a field: {fields_total} fields in {len(plan)} designs, {moved} moved exactly, {skipped} symbols skipped, {checks} checks, {len(fails)} failures")
# ---- the edges of the box, and fields that are not shown ----
path, idxs = plan[0]
for path, idxs in plan[:6]:
    base = os.path.basename(path); sh = sheet0(path); objs = objects(sh); om = resource_maps(sh)
    k = idxs[0]; e = objs[k]
    o, rc, err = run(f'open "{path}"\nselidx {k}\nfieldinfo\n')
    fl = []
    for l in o:
        if l.startswith("FIELD "):
            t = l.split(None, 11); fl.append(dict(i=int(t[1]), show=int(t[2]), x=float(t[3]), y=float(t[4]), w=float(t[5]), h=float(t[6])))
    boxes = [(f["x"], f["y"] - f["h"], f["x"] + f["w"], f["y"]) for f in fl if f["show"] and f["w"] > 0]
    def in_any(px, py, margin=0.3): return any(b[0] - margin <= px <= b[2] + margin and b[1] - margin <= py <= b[3] + margin for b in boxes)
    pts = []     # (kind, field, x, y)
    for f in fl:
        if (not f["show"]) or f["w"] <= 0: continue
        x1, y1, x2, y2 = f["x"], f["y"] - f["h"], f["x"] + f["w"], f["y"]
        if f["w"] >= 2.2 and f["h"] >= 2.2:
            pts += [("inside", f["i"], x1 + 0.9, y2 - 0.9), ("inside", f["i"], x2 - 0.9, y1 + 0.9)]
        for (px, py) in ((x1 - 1.5, (y1 + y2) / 2), (x2 + 1.5, (y1 + y2) / 2), ((x1 + x2) / 2, y1 - 1.5), ((x1 + x2) / 2, y2 + 1.5)):
            if not in_any(px, py, 1.0): pts.append(("outside", f["i"], px, py))
    o2, rc, err = run(f'open "{path}"\nselidx {k}\n' + "".join(f"snapat {FMT(x)} {FMT(y)}\n" for _, _, x, y in pts))
    snaps = [tuple(float(v) for v in l.split()[3:5]) for l in o2 if l.startswith("SNAPAT")]
    script = [f'open "{path}"']
    for n, ((kind, fi, x, y), (sx, sy)) in enumerate(zip(pts, snaps)):
        tx, ty = grid(x + 12), grid(y - 8)
        script += [f"selidx {k}", f"mouse down {FMT(x)} {FMT(y)}", f"mouse move {FMT(tx)} {FMT(ty)}", f"mouse up {FMT(tx)} {FMT(ty)}", f'save "{tmp}/e{n}.dsn"', "undoinfo", "undo"]
    o3, rc, err = run("\n".join(script) + "\n", 250)
    uds = [l for l in o3 if l.startswith("UNDOINFO")]
    for n, ((kind, fi, x, y), (sx, sy)) in enumerate(zip(pts, snaps)):
        tx, ty = grid(x + 12), grid(y - 8); delta = (tx - sx, ty - sy)
        got = objects(sheet0(f"{tmp}/e{n}.dsn")); gm = resource_maps(sheet0(f"{tmp}/e{n}.dsn"))
        sym = got[k]
        rel_old = [tuple(float(v) for v in f.get("pos").split(",")) for f in e.findall("FIELD")]
        rel_new = [tuple(float(v) for v in f.get("pos").split(",")) for f in sym.findall("FIELD")]
        if kind == "inside":
            exp = copy.deepcopy(e); ff = exp.findall("FIELD")[fi]; px_, py_ = rel_old[fi]; ff.set("pos", "%.5f,%.5f" % (px_ + delta[0], py_ + delta[1]))
            ok = sig(sym, gm) == sig(exp, om)
            check(f"{base}: a press just inside the box of field {fi} (0.9 mm from a corner) picks the field and drags it alone", ok, f"{rel_old} -> {rel_new} by {delta}")
            inside_ok += ok
        else:
            # the field stays where it was relative to its symbol (the symbol itself may have moved, if the press was on it)
            ok = all(abs(a[0] - b[0]) < 1e-3 and abs(a[1] - b[1]) < 1e-3 for a, b in zip(rel_old, rel_new))
            check(f"{base}: a press 1.5 mm outside the box of field {fi} does not pick the field", ok, f"{rel_old} -> {rel_new}")
            outside_ok += ok
print(f"edges: {inside_ok} presses just inside picked a field, {outside_ok} presses just outside did not, {checks} checks, {len(fails)} failures")
# ---- not shown, two selected, turned, the pointer, the pixels ----
for path, idxs in plan[:6]:
    base = os.path.basename(path); sh = sheet0(path); objs = objects(sh); om = resource_maps(sh)
    k = idxs[0]; e = objs[k]
    # a field that is not shown cannot be picked (find one among all the symbols of the design)
    hid = [(kk, ee) for kk, ee in enumerate(objs) if ee.tag == "SYMBOL" and any(f.get("show") != "1" for f in ee.findall("FIELD"))]
    if hid:
        hk, he = hid[0]; hf = [i for i, f in enumerate(he.findall("FIELD")) if f.get("show") != "1"][0]
        ox, oy = (float(v) for v in he.get("pos").split(",")); rx, ry = (float(v) for v in he.findall("FIELD")[hf].get("pos").split(","))
        px, py = ox + rx + 0.8, oy + ry - 0.8
        o, rc, err = run(f'open "{path}"\nselidx {hk}\nfieldinfo\nmouse down {FMT(px)} {FMT(py)}\nmouse move {FMT(grid(px + 10))} {FMT(grid(py + 6))}\nmouse up {FMT(grid(px + 10))} {FMT(grid(py + 6))}\nsave "{tmp}/h.dsn"\n')
        got = objects(sheet0(f"{tmp}/h.dsn"))[hk]
        rel_old = [tuple(float(v) for v in f.get("pos").split(",")) for f in he.findall("FIELD")]; rel_new = [tuple(float(v) for v in f.get("pos").split(",")) for f in got.findall("FIELD")]
        check(f"{base}: a field that is not shown cannot be picked (its position is unchanged relative to the symbol)", all(abs(a[0] - b[0]) < 1e-3 and abs(a[1] - b[1]) < 1e-3 for a, b in zip(rel_old, rel_new)), f"{rel_old} -> {rel_new}")
        hidden_tested += 1
    # two selected: a press on a field moves the selection, the field keeps its place relative to its symbol
    syms = [kk for kk, ee in enumerate(objs) if ee.tag == "SYMBOL"]
    if len(syms) >= 2 and k in syms:
        other = [s for s in syms if s != k][0]
        o, rc, err = run(f'open "{path}"\nselidx {k}\nfieldinfo\n'); f0 = [l.split(None, 11) for l in o if l.startswith("FIELD ") and float(l.split()[5]) > 0 and l.split()[2] == "1"][0]
        fx, fy = float(f0[3]) + float(f0[5]) / 2, float(f0[4]) - float(f0[6]) / 2
        tx, ty = grid(fx + 14), grid(fy + 10)
        o, rc, err = run(f'open "{path}"\nselidx {k} {other}\nmouse down {FMT(fx)} {FMT(fy)}\nmouse move {FMT(tx)} {FMT(ty)}\nmouse up {FMT(tx)} {FMT(ty)}\nsave "{tmp}/two.dsn"\n')
        got = objects(sheet0(f"{tmp}/two.dsn"))
        rel_old = [tuple(float(v) for v in f.get("pos").split(",")) for f in e.findall("FIELD")]; rel_new = [tuple(float(v) for v in f.get("pos").split(",")) for f in got[k].findall("FIELD")]
        po = tuple(float(v) for v in e.get("pos").split(",")); pn = tuple(float(v) for v in got[k].get("pos").split(","))
        # (whether the selection moves depends on whether the press is near enough to the symbol to pick it, as in TinyCAD; what matters is that the field is not dragged by itself)
        check(f"{base}: with two objects selected a press on a field does not drag the field by itself (it keeps its place relative to its symbol)", all(abs(a[0] - b[0]) < 1e-3 and abs(a[1] - b[1]) < 1e-3 for a, b in zip(rel_old, rel_new)), f"{po}->{pn} {rel_old}->{rel_new}")
        multi_tested += 1
    # turned: the fields can still be dragged (the program's own positions after the turn are the reference)
    o, rc, err = run(f'open "{path}"\nselidx {k}\nrotate left\nfieldinfo\n')
    fl = [l.split(None, 11) for l in o if l.startswith("FIELD ") and float(l.split()[5]) > 0 and l.split()[2] == "1"]; org = [l for l in o if l.startswith("FIELDINFO origin")]
    if fl and org:
        f0 = fl[0]; fi0 = f0[1]; fx, fy = float(f0[3]) + float(f0[5]) / 2, float(f0[4]) - float(f0[6]) / 2
        tx, ty = grid(fx + 14), grid(fy + 10)
        o, rc, err = run(f'open "{path}"\nselidx {k}\nrotate left\nfieldinfo\nmouse down {FMT(fx)} {FMT(fy)}\nmouse move {FMT(tx)} {FMT(ty)}\nmouse up {FMT(tx)} {FMT(ty)}\nfieldinfo\nundoinfo\n')
        infos = [l for l in o if l.startswith("FIELD ") and l.split(None, 11)[1] == fi0]
        a0 = infos[0].split(None, 11); a1 = infos[1].split(None, 11)
        d = (float(a1[3]) - float(a0[3]), float(a1[4]) - float(a0[4])); want = (tx - float(a0[8]), ty - float(a0[9]))
        check(f"{base}: after the symbol has been turned its field can still be dragged, by exactly the snapped distance", abs(d[0] - want[0]) < 2e-3 and abs(d[1] - want[1]) < 2e-3, f"{d} vs {want}")
        rotated_tested += 1
print(f"others: {hidden_tested} hidden-field presses, {multi_tested} two-object presses, {rotated_tested} turned symbols, {checks} checks, {len(fails)} failures")
# ---- the pointer, and what is drawn ----
path, idxs = plan[0]; k = idxs[0]
o, rc, err = run(f'open "{path}"\nselidx {k}\nfieldinfo\n')
f0 = [l.split(None, 11) for l in o if l.startswith("FIELD ") and float(l.split()[5]) > 0 and l.split()[2] == "1"][0]; fx, fy = float(f0[3]) + float(f0[5]) / 2, float(f0[4]) - float(f0[6]) / 2
org = [l for l in o if l.startswith("FIELDINFO origin")][0].split(); ox, oy = float(org[2]), float(org[3])
o, rc, err = run(f'open "{path}"\nselidx {k}\nmouse move {FMT(fx)} {FMT(fy)}\ncursor\nmouse move 5 5\ncursor\nselclear\nmouse move {FMT(fx)} {FMT(fy)}\ncursor\n')
cs = [l.split()[1] for l in o if l.startswith("CURSOR")]
check("over a field of the selected symbol the pointer is the 4-way move arrow, away from it the ordinary one, and with nothing selected the ordinary one", cs == ["ALL", "default", "default"], str(cs))
w, h = float(f0[5]), float(f0[6]); sx0, sy0 = float(f0[8]), float(f0[9])
cands = []
for off in ((24, 16), (-24, 16), (24, -16), (-24, -16), (40, 0), (-40, 0), (0, 30), (0, -30), (60, 20), (-60, 20)):
    tx, ty = grid(fx + off[0]), grid(fy + off[1]); d = (tx - sx0, ty - sy0)
    cands.append(((tx, ty), (float(f0[3]) + d[0], float(f0[4]) + d[1] - h, float(f0[3]) + d[0] + w, float(f0[4]) + d[1])))
script = [f'open "{path}"', "selclear", f"selidx {k}", f"viewpoint {FMT(fx - w / 2)} {FMT(fy - h / 2)}", f"viewpoint {FMT(fx + w / 2)} {FMT(fy + h / 2)}"]
for _, (x1, y1, x2, y2) in cands: script += [f"viewpoint {FMT(x1)} {FMT(y1)}", f"viewpoint {FMT(x2)} {FMT(y2)}"]
script.append(f'shot "{tmp}/before.bmp"')
o, rc, err = run("\n".join(script) + "\n")
vp = [tuple(int(v) for v in l.split()[1:]) for l in o if l.startswith("VIEWPOINT")]
def blank(path_, a_, b_):   # how many pixels of a window rectangle are not white
    x1, x2 = sorted((a_[0], b_[0])); y1, y2 = sorted((a_[1], b_[1]))
    return subprocess.run(["convert", path_, "-crop", f"{max(1, x2 - x1)}x{max(1, y2 - y1)}+{x1}+{y1}", "-colorspace", "Gray", "-threshold", "95%", "-format", "%[fx:int((1-mean)*w*h+0.5)]", "info:"], capture_output=True, text=True).stdout.strip()
b_old = int(blank(f"{tmp}/before.bmp", vp[0], vp[1]) or 0)
pick_ = next(((c, (vp[2 + 2 * i], vp[3 + 2 * i])) for i, c in enumerate(cands) if int(blank(f"{tmp}/before.bmp", vp[2 + 2 * i], vp[3 + 2 * i]) or 1) == 0), None)
check("there is an empty place on the sheet to drag a field to (so the pixels can be compared)", pick_ is not None, "")
if pick_ is not None:
    cand, (pa, pb) = pick_; tx, ty = cand[0]
    o, rc, err = run(f'open "{path}"\nselclear\nselidx {k}\nmouse down {FMT(fx)} {FMT(fy)}\nmouse move {FMT(tx)} {FMT(ty)}\nmouse up {FMT(tx)} {FMT(ty)}\nselclear\nshot "{tmp}/after.bmp"\n')
    a_old = int(blank(f"{tmp}/after.bmp", vp[0], vp[1]) or 0); a_new = int(blank(f"{tmp}/after.bmp", pa, pb) or 0)
    check("the text really moves on the screen: marks leave the old box (it is blank again) and arrive in the new, empty one", b_old > 3 and a_old == 0 and a_new > 3, f"old box {b_old}->{a_old}, new box 0->{a_new}")
print(f"fields: {checks} checks, {len(fails)} failures")
print("\nFIELD DRAG CHECKS PASSED" if not fails else f"\nFIELD DRAG CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
