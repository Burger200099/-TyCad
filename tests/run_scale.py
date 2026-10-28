"""Scaling a placed symbol with handles (TinyCAD's CDrawMethod::IsInsideField / MoveField for a symbol marked resizable, can_scale): select one
such symbol and the tracker's eight handles appear; dragging one changes the symbol's rectangle and its scale together. Checked against a Python
port of the C++ rule (the new rectangle by MoveField's arithmetic; the scale from it, divided by the symbol's own size taken at scale 1, the
two swapped for a symbol turned a quarter; the corners then set from the scale), with the symbol's own size read from the program as input:
  - every handle of symbols of every turning and mirroring, dragged by several amounts (including so far that the box turns over), compared on the
    symbol's origin, other corner and scale as the program reports them and as they are saved
  - undo gives back the original box and scale, redo the scaled one; each drag is one undo step called Resize; nothing else in the design changes
    (not the other objects, not the symbol's fields, which keep their offsets from the origin)
  - Ctrl on a corner keeps the shape of the box
  - a symbol that is not marked resizable has no handles; the Resizable property turns them on and off and is saved as can_scale
  - the handles are drawn, and the pointer is the right arrow over a handle, the 4-way arrow over the symbol, the ordinary one away from it
Needs the built program and ImageMagick."""
import copy, glob, os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from designoracle import sig, resource_maps, objects, sheet0
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or shutil.which("convert") is None:
    print("Scaling checks skipped: need xvfb-run, ImageMagick and the built program", BIN); sys.exit(0)
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
def pix(path, x, y):
    o = subprocess.run(["convert", path, "-crop", "1x1+%d+%d" % (x, y), "-format", "%[fx:int(255*r)],%[fx:int(255*g)],%[fx:int(255*b)]", "info:"], capture_output=True, text=True).stdout
    return tuple(int(v) for v in o.split(","))
def grid(v): return round(v / 2.0) * 2.0
FMT = lambda v: "%.4f" % v
# ---------- TinyCAD's rule, ported independently ----------
def rect_move(a, b, w, r):
    """CDrawRectOutline::MoveField on the corners a and b (their order kept)"""
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
def layout(a, native, scale, rotate):
    """CDrawMethod::ExtractSymbol: the other corner, from the origin, the symbol's own size and the scale"""
    tr = (native[0] * scale[0], native[1] * scale[1])
    return (a[0] + tr[0], a[1] + tr[1]) if (rotate & 3) < 2 else (a[0] + tr[1], a[1] + tr[0])
def scale_move(a, b, native, scale, rotate, w, r):
    """CDrawMethod::MoveField for a handle, followed by the layout the next paint does (it puts the other corner right again)"""
    na, nb = rect_move(a, b, w, r)
    unit = layout(na, native, (1.0, 1.0), rotate)                    # the symbol's own size, at scale 1
    den = (abs(na[0] - unit[0]), abs(na[1] - unit[1]))
    sx = abs((nb[0] - na[0]) / den[0]) if den[0] > 0 else 1.0
    sy = abs((nb[1] - na[1]) / den[1]) if den[1] > 0 else 1.0
    if (rotate & 3) >= 2: sx, sy = sy, sx
    return na, layout(na, native, (sx, sy), rotate), (sx, sy)
def aspect_keep(w, r, ratio):
    x, y = r
    if w in (1, 3):
        if abs(x) > abs(y): y = -x * ratio
        else: x = -y / ratio
    elif w in (0, 2):
        if abs(x) > abs(y): y = x * ratio
        else: x = y / ratio
    return (x, y)
CURSOR = {0: "NWSE", 2: "NWSE", 1: "NESW", 3: "NESW", 4: "NS", 6: "NS", 5: "WE", 7: "WE"}
def parse_info(lines, nth=0):
    l = [x for x in lines if x.startswith("SYMINFO ") and "none" not in x][nth].split()
    v = [float(t) for t in l[1:]]
    return dict(a=(v[0] * 5, v[1] * 5), b=(v[2] * 5, v[3] * 5), scale=(v[4], v[5]), native=(v[6] * 5, v[7] * 5), rotate=int(v[8]), can=int(v[9]))
def close(p, q, tol=2e-3): return all(abs(x - y) <= tol for x, y in zip(p, q))
# ---------- the symbols to try: every turning and mirroring, and the scalable ones the samples have ----------
designs = sorted(glob.glob(os.path.join(EX, "**", "*.dsn"), recursive=True))
chosen = []; seen_rot = set()
for path in designs:
    try: sh = sheet0(path)
    except Exception: continue
    for k, e in enumerate(objects(sh)):
        if e.tag != "SYMBOL": continue
        rot = int(e.get("rotate", "0"))
        if e.get("can_scale") == "1" and (path, "orig") not in [(c[0], c[3]) for c in chosen] and len([c for c in chosen if c[3] == "orig"]) < 3:
            chosen.append((path, k, rot, "orig")); continue
        if rot not in seen_rot and len(seen_rot) < 8 and e.get("can_scale") != "1":
            seen_rot.add(rot); chosen.append((path, k, rot, "forced"))
check("the samples give symbols of several turnings and some already scalable", len(seen_rot) >= 4 and len([c for c in chosen if c[3] == "orig"]) >= 2, f"{sorted(seen_rot)} {len(chosen)}")
# the designs the program is given: those symbols marked resizable in a copy of the file
work = []
for n, (path, k, rot, kind) in enumerate(chosen):
    r = ET.parse(path); root = r.getroot(); sh = root.findall("TinyCAD")[0] if root.tag == "TinyCADSheets" else root
    objs = objects(sh); e = objs[k]; e.set("can_scale", "1")
    p2 = os.path.join(tmp, f"scalable{n}.dsn"); r.write(p2, encoding="utf-8", xml_declaration=True)
    work.append((p2, k, rot, kind, os.path.basename(path)))
total = ok_geo = 0; DELTAS = [(20, 12), (-16, -10), (30, -20), (-40, 26)]
for (p2, k, rot, kind, base) in work:
    sh = sheet0(p2); objs = objects(sh); om = resource_maps(sh); e = objs[k]
    # stage 1: the symbol's box and where its handles are
    o, rc, err = run(f'open "{p2}"\nselidx {k}\nsymbolinfo\n' + "".join(f"handlepos {c}\n" for c in range(8)))
    if rc != 0 or any(l.startswith("ERROR") for l in o) or not any(l.startswith("SYMINFO ") and "none" not in l for l in o):
        check(f"{base} #{k}: stage 1 ran", False, "\n".join(l for l in o if l.startswith("ERROR")) + err[-200:]); continue
    st = parse_info(o)
    ox, oy = (float(v) for v in e.get("pos").split(","))
    check(f"{base} #{k}: the program and the file agree about the symbol (origin), its rotation and that it can be scaled", abs(st["a"][0] / 5 - ox) < 1e-3 and abs(st["a"][1] / 5 - oy) < 1e-3 and st["rotate"] == rot and st["can"] == 1, f"{st} vs {(ox, oy, rot)}")
    H = {}
    for l in o:
        if l.startswith("HANDLEPOS") and "none" not in l:
            t = l.split(); H[int(t[1])] = (float(t[2]), float(t[3]), float(t[5]), float(t[6]))
    check(f"{base} #{k}: a scalable symbol has eight handles", len(H) == 8, str(len(H)))
    if len(H) != 8: continue
    # stage 2: the drags
    cases = []; script = [f'open "{p2}"']
    for c in range(8):
        hx, hy, sx, sy = H[c]
        for (dx, dy) in DELTAS:
            tx, ty = grid(hx + dx), grid(hy + dy); n = len(cases); cases.append((c, (tx - sx, ty - sy), n))
            script += [f"selidx {k}", f"mouse down {FMT(hx)} {FMT(hy)}", f"mouse move {FMT(tx)} {FMT(ty)}", f"mouse up {FMT(tx)} {FMT(ty)}", "symbolinfo", f'save "{tmp}/d{n}.dsn"', "undoinfo", "undo", "symbolinfo", "redo", "symbolinfo", "undo"]
    o, rc, err = run("\n".join(script) + "\n", 290)
    check(f"{base} #{k}: the drags ran cleanly", rc == 0 and not any(l.startswith("ERROR") for l in o), "\n".join(l for l in o if l.startswith("ERROR")) + err[-200:])
    uds = [l for l in o if l.startswith("UNDOINFO")]
    bad_geo = bad_save = bad_undo = bad_step = 0; first = None
    for (c, delta, n) in cases:
        d = (delta[0] * 5, delta[1] * 5)
        wa, wb, ws = scale_move(st["a"], st["b"], st["native"], st["scale"], st["rotate"], c, d)
        got = parse_info(o, 3 * n); undone = parse_info(o, 3 * n + 1); redone = parse_info(o, 3 * n + 2)
        if not (close(got["a"], wa) and close(got["b"], wb) and close(got["scale"], ws, 2e-4)):
            bad_geo += 1; first = first or (c, tuple(round(v, 2) for v in delta), got, (wa, wb, ws))
        if not (close(undone["a"], st["a"]) and close(undone["b"], st["b"]) and close(undone["scale"], st["scale"], 2e-4) and close(redone["a"], wa) and close(redone["scale"], ws, 2e-4)): bad_undo += 1
        if 'next="Resize"' not in uds[n] or "undo=1 " not in uds[n]: bad_step += 1
        try:
            s2 = sheet0(f"{tmp}/d{n}.dsn"); g = objects(s2)[k]; gm = resource_maps(s2)
            exp = copy.deepcopy(e); exp.set("pos", "%.5f,%.5f" % (wa[0] / 5, wa[1] / 5)); exp.set("scale_x", "%.5f" % ws[0]); exp.set("scale_y", "%.5f" % ws[1])
            want = [sig(x, om) for x in objs]; want[k] = sig(exp, om)
            if [sig(x, gm) for x in objects(s2)] != want: bad_save += 1
        except Exception: bad_save += 1
    total += len(cases); ok_geo += len(cases) - bad_geo
    check(f"{base} #{k} (rotate {rot}): {len(cases)} drags (8 handles x {len(DELTAS)} amounts, some so far that the box turns over) give TinyCAD's box and scale", bad_geo == 0, f"{bad_geo} wrong; first {first}")
    check(f"{base} #{k}: the saved file has the new origin and scale, and nothing else changed (the other objects, the fields' offsets)", bad_save == 0, str(bad_save))
    check(f"{base} #{k}: undo gives back the original box and scale, redo the scaled one", bad_undo == 0, str(bad_undo))
    check(f"{base} #{k}: each drag is one undo step called Resize", bad_step == 0, str(bad_step))
print(f"drags: {total} drags on {len(work)} symbols, {ok_geo} exact, {checks} checks, {len(fails)} failures")
# ---------- Ctrl keeps the shape ----------
p2, k, rot, kind, base = work[0]; sh = sheet0(p2)
o, rc, err = run(f'open "{p2}"\nselidx {k}\nsymbolinfo\n' + "".join(f"handlepos {c}\n" for c in range(4)))
st = parse_info(o); H = {}
for l in o:
    if l.startswith("HANDLEPOS") and "none" not in l: t = l.split(); H[int(t[1])] = (float(t[2]), float(t[3]), float(t[5]), float(t[6]))
ratio = abs((st["b"][1] - st["a"][1]) / (st["b"][0] - st["a"][0])); script = [f'open "{p2}"']; cases = []
for c in range(4):
    hx, hy, sx, sy = H[c]; steps = [(grid(hx + 10), grid(hy + 8)), (grid(hx + 24), grid(hy + 12)), (grid(hx + 6), grid(hy + 30))]
    for ctrl in (False, True):
        n = len(cases); cases.append((c, (sx, sy), steps, ctrl)); script.append(f"selidx {k}"); script.append(f"mouse down {FMT(hx)} {FMT(hy)}")
        for (tx, ty) in steps: script.append(f"mouse move {FMT(tx)} {FMT(ty)}" + (" ctrl" if ctrl else ""))
        script += [f"mouse up {FMT(steps[-1][0])} {FMT(steps[-1][1])}", "symbolinfo", "undo"]
o, rc, err = run("\n".join(script) + "\n")
bad = 0; first = None
for n, (c, (sx, sy), steps, ctrl) in enumerate(cases):
    a, b, sc = st["a"], st["b"], st["scale"]; last = (sx * 5, sy * 5)
    for (tx, ty) in steps:
        r = (tx * 5 - last[0], ty * 5 - last[1]); last = (tx * 5, ty * 5)
        if ctrl and ratio > 0: r = aspect_keep(c, r, ratio)
        a, b, sc = scale_move(a, b, st["native"], sc, st["rotate"], c, r)
    got = parse_info(o, n)
    if not (close(got["a"], a, 5e-3) and close(got["b"], b, 5e-3) and close(got["scale"], sc, 5e-4)): bad += 1; first = first or (c, ctrl, got, (a, b, sc))
check("a drag in three moves, with and without Ctrl on each corner (Ctrl keeps the shape of the box), follows the rule move by move", bad == 0, f"{bad} wrong; first {first}")
# ---------- not resizable: no handles; the property turns them on and off ----------
path, k0, rot0, kind0 = [c for c in chosen if c[3] == "forced"][-1]      # (a symbol the sample does not mark resizable)
o, rc, err = run(f'open "{path}"\nselidx {k0}\nsymbolinfo\nhandlepos 2\nsetprop sym.canscale 1\nsymbolinfo\nhandlepos 2\nundoinfo\nsave "{tmp}/on.dsn"\nsetprop sym.canscale 0\nhandlepos 2\nsave "{tmp}/off.dsn"\n')
infos = [l for l in o if l.startswith("SYMINFO ")]; hp = [l for l in o if l.startswith("HANDLEPOS")]
check("a symbol that is not marked resizable has no handles", "HANDLEPOS none" in hp[0] and infos[0].split()[-1] == "0", f"{hp[0]} / {infos[0]}")
check("setting the Resizable property gives it handles, and the file says can_scale=1", "none" not in hp[1] and infos[1].split()[-1] == "1" and objects(sheet0(f"{tmp}/on.dsn"))[k0].get("can_scale") == "1", f"{hp[1]} / {infos[1]}")
check("setting it off takes the handles away again, and the file says can_scale=0", "HANDLEPOS none" in hp[2] and objects(sheet0(f"{tmp}/off.dsn"))[k0].get("can_scale") == "0", hp[2])
# ---------- the handles are drawn, and the pointer ----------
p2, k, rot, kind, base = work[0]
o, rc, err = run(f'open "{p2}"\nselidx {k}\nsymbolinfo\n' + "".join(f"handlepos {c}\n" for c in range(8)))
H = {}
for l in o:
    if l.startswith("HANDLEPOS") and "none" not in l: t = l.split(); H[int(t[1])] = (float(t[2]), float(t[3]))
st = parse_info(o); mid = ((st["a"][0] + st["b"][0]) / 10, (st["a"][1] + st["b"][1]) / 10)
script = [f'open "{p2}"', f"selidx {k}"] + [f"viewpoint {FMT(H[c][0])} {FMT(H[c][1])}" for c in range(8)] + [f'shot "{tmp}/handles.bmp"', "selclear", f"viewpoint {FMT(H[0][0])} {FMT(H[0][1])}", f'shot "{tmp}/nohandles.bmp"', f"selidx {k}"]
for c in range(8): script += [f"mouse move {FMT(H[c][0])} {FMT(H[c][1])}", "cursor"]
script += [f"mouse move {FMT(mid[0])} {FMT(mid[1])}", "cursor", "mouse move 5 5", "cursor"]
o, rc, err = run("\n".join(script) + "\n")
vps = [tuple(int(v) for v in l.split()[1:]) for l in o if l.startswith("VIEWPOINT")]
blacks = [pix(f"{tmp}/handles.bmp", *vps[c]) for c in range(8)]
check("the eight handles are drawn: a black square at each place", all(b == (0, 0, 0) for b in blacks), str(blacks))
check("and none is drawn when the symbol is not selected", pix(f"{tmp}/nohandles.bmp", *vps[8]) != (0, 0, 0), str(pix(f"{tmp}/nohandles.bmp", *vps[8])))
cs = [l.split()[1] for l in o if l.startswith("CURSOR")]
check("the pointer shows the way each handle scales, the 4-way arrow over the body of the symbol, and the ordinary one away from it", cs[:8] == [CURSOR[c] for c in range(8)] and cs[8] == "ALL" and cs[9] == "default", str(cs))
print(f"scale: {checks} checks, {len(fails)} failures")
print("\nSCALE CHECKS PASSED" if not fails else f"\nSCALE CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
