"""Import (Ctrl+I): another TinyCAD design brought into the sheet as a block that follows the mouse until it is placed. Checked on every
sample design against an independent reading of the XML (designoracle.py):
  - the objects that come in are exactly the first sheet's objects, by meaning (before they are placed, so the junction work done when a
    block is dropped does not come into it)
  - the page details of the sheet it goes into are not changed by the file's
  - the block moves as one: every object shifts by the same amount, and moving the mouse by some distance moves it by that distance
  - the import is one undo step called Import, and undo and redo take it away and bring it back
and, in separate scenarios: importing into a sheet that already has objects (theirs are kept, the new ones added, the ids stay unique),
a file with several sheets (only the first comes in), what Copy to wrote (a round trip), cancelling with a right click (also into a sheet
that has objects: exactly what was there comes back), and files that
cannot be imported (not a design, missing, empty), which change nothing."""
import glob, os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from designoracle import sig, resource_maps, objects, sheet0
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Import checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
env = dict(os.environ, HOME=os.path.join(tmp, "home")); os.makedirs(env["HOME"])
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:400])
def run(script):
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=120, env=env)
    return r.stdout.split("\n"), r.returncode, r.stderr
def pick(lines, start, nth=0): return [l for l in lines if l.startswith(start)][nth]
def objs_of(line): return int(re.search(r"objects=(\d+)", line).group(1))
POS = ("pos", "a", "b")
def xy(v): return tuple(float(c) for c in v.split(","))
def shift_of(a, b):
    """how far object b is from a (a before, b after moving): the shift of its position attributes, which must be the same for all of them"""
    d = []
    for k in POS:
        if k in a.attrib and k in b.attrib: d.append(tuple(round(q - p, 3) for p, q in zip(xy(a.get(k)), xy(b.get(k)))))
    return d
def stripped(e):
    c = ET.fromstring(ET.tostring(e))
    for k in POS: c.attrib.pop(k, None)
    return c
def at(e, delta, maps):
    """an object by meaning (everything but its position) and where it is once moved by delta"""
    pos = tuple(sorted((k, tuple(round(v + d, 2) for v, d in zip(xy(e.get(k)), delta))) for k in POS if k in e.attrib))
    return (repr(sig(stripped(e), maps)), pos)
LINES = ("WIRE", "BUS")
def cover(wires, delta):
    """the lines a set of wires covers, as the program may have joined or split them while the block moved: a horizontal or vertical wire
    as stretches along its line (touching or overlapping stretches count as one), any other wire as itself"""
    spans = {}
    for e in wires:
        (ax, ay), (bx, by) = xy(e.get("a")), xy(e.get("b"))
        ax, ay, bx, by = ax + delta[0], ay + delta[1], bx + delta[0], by + delta[1]
        if abs(ay - by) < 1e-6: spans.setdefault(("h", round(ay, 2)), []).append((round(min(ax, bx), 2), round(max(ax, bx), 2)))
        elif abs(ax - bx) < 1e-6: spans.setdefault(("v", round(ax, 2)), []).append((round(min(ay, by), 2), round(max(ay, by), 2)))
        else: spans.setdefault(("d", tuple(sorted(((round(ax, 2), round(ay, 2)), (round(bx, 2), round(by, 2))))), 0), []).append((0, 0))
    out = set()
    for k, v in spans.items():
        v.sort(); lo, hi = v[0]
        for a_, b_ in v[1:]:
            if a_ <= hi + 1e-6: hi = max(hi, b_)
            else: out.add((k, lo, hi)); lo, hi = a_, b_
        out.add((k, lo, hi))
    return out
def block_shift(src, moved, sm, mm):
    """the one shift that takes the block to where it is now, or None. While a block moves the program, as TinyCAD does for one that is pasted,
    keeps the junctions right (it takes away one that is not needed and adds one that is) and may join or split wires; so every object that is
    not a junction or a wire must be there, exactly, moved by that shift (and no other of that kind), and the wires must cover the same lines."""
    from collections import Counter
    strict = [e for e in src if e.tag not in LINES and e.tag != "JUNCTION"]
    if not strict: return "skip", 0
    first = strict[0]; want = repr(sig(stripped(first), sm)); cands = set()
    for m in moved:
        if m.tag == first.tag and repr(sig(stripped(m), mm)) == want:
            d = shift_of(first, m)
            if d: cands.add(d[0])
    mstrict = [m for m in moved if m.tag not in LINES and m.tag != "JUNCTION"]
    have = Counter(at(m, (0.0, 0.0), mm) for m in mstrict)
    for c in sorted(cands):
        if Counter(at(e, c, sm) for e in strict) == have and cover([e for e in src if e.tag in LINES], c) == cover([m for m in moved if m.tag in LINES], (0.0, 0.0)):
            return c, len(moved) - len(src)
    return None, 0

designs = sorted(glob.glob(os.path.join(EX, "**", "*.dsn"), recursive=True))
used = n_objs = other_page = multi = skipped_move = with_labels = 0
for path in designs:
    sh = sheet0(path); src = objects(sh)
    if not src: continue
    out = os.path.join(tmp, "o"); shutil.rmtree(out, ignore_errors=True); os.makedirs(out)
    o, rc, err = run(f'''newdoc "ISO A4" landscape
detailsinfo
undoinfo
info
import "{path}"
save "{out}/pre.dsn"
detailsinfo
mouse move 100 100
save "{out}/m1.dsn"
mouse move 120 110
save "{out}/m2.dsn"
mouse down 120 110
mouse up 120 110
undoinfo
info
undo
info
redo
info
''')
    base = os.path.basename(path)
    if rc != 0 or any(l.startswith("ERROR") for l in o):
        check(f"{base}: ran cleanly", False, "\n".join(l for l in o if l.startswith("ERROR")) + err[-200:]); continue
    used += 1; n_objs += len(src)
    if any(e.tag == "LABEL" for e in src): with_labels += 1
    if len(ET.parse(path).getroot().findall("TinyCAD")) > 1: multi += 1
    imp = int(pick(o, "IMPORT ").split()[1])
    check(f"{base}: the number of objects that came in is the first sheet's", imp == len(src), f"{imp} vs {len(src)}")
    om, cm = resource_maps(sh), resource_maps(sheet0(f"{out}/pre.dsn"))
    got = objects(sheet0(f"{out}/pre.dsn"))
    check(f"{base}: the objects are the first sheet's, by meaning", len(got) == len(src) and [sig(e, om) for e in src] == [sig(e, cm) for e in got], f"{len(got)} vs {len(src)}")
    dets = [l for l in o if l.startswith("DETAILSINFO")]
    check(f"{base}: the page details of the sheet are not changed by the file's", dets[0] == dets[1], f"{dets[0][-60:]} vs {dets[1][-60:]}")
    srcsize = sh.find("DETAILS").find("Size")
    if srcsize is not None and (srcsize.get("width"), srcsize.get("height")) != ("1485", "1050"): other_page += 1
    m1, m2 = sheet0(f"{out}/m1.dsn"), sheet0(f"{out}/m2.dsn")
    o1, o2 = objects(m1), objects(m2)
    r1 = block_shift(src, o1, om, resource_maps(m1)); r2 = block_shift(src, o2, om, resource_maps(m2))
    if r1[0] == "skip": skipped_move += 1
    else:
        check(f"{base}: the block moves as one: one shift takes every object (the wires covering the same lines) to where it is now", r1[0] is not None and r2[0] is not None, "no common shift")
        if r1[0] is not None and r2[0] is not None:
            d1, d2 = r1[0], r2[0]
            check(f"{base}: moving the mouse by (20, 10) mm moves the block by (20, 10)", (round(d2[0] - d1[0], 2), round(d2[1] - d1[1], 2)) == (20.0, 10.0), f"{d1} -> {d2}")
    ud = pick(o, "UNDOINFO", 1)
    check(f"{base}: the import is one undo step named Import", 'next="Import"' in ud and "undo=1 " in ud, ud)
    infos = [objs_of(l) for l in o if l.startswith("INFO ")]
    check(f"{base}: undo takes the imported objects away and redo brings them back (placing keeps the junctions right, so the count can change)", infos[0] == 0 and infos[2] == 0 and infos[3] == infos[1] and 0 < infos[1] <= 2 * len(src), str(infos))
print(f"{used} designs imported ({multi} with several sheets, {other_page} with a page size different from the A4 it went into, {skipped_move} with only wires and junctions so no shift to check; {with_labels} have labels, which must move with the block), {n_objs} objects, {checks} checks, {len(fails)} failures")

pool = [p for p in designs if objects(sheet0(p))]
A = next(p for p in pool if "LED Flasher" in p); B = next(p for p in pool if "Attenuator" in p)
out = os.path.join(tmp, "scn"); os.makedirs(out)
# 1. into a sheet that already has objects
o, rc, err = run(f'''open "{A}"
detailsinfo
info
import "{B}"
save "{out}/both.dsn"
detailsinfo
info
mouse down 140 80
mouse up 140 80
undoinfo
undo
info
''')
check("a design is imported into a sheet that already has objects: ran cleanly", rc == 0 and not any(l.startswith("ERROR") for l in o), "\n".join(l for l in o if l.startswith("ERROR")))
sa, sb = sheet0(A), sheet0(B); both = sheet0(f"{out}/both.dsn")
want = [sig(e, resource_maps(sa)) for e in objects(sa)] + [sig(e, resource_maps(sb)) for e in objects(sb)]
cmb = resource_maps(both)
check("its own objects are kept, in front, and the imported ones follow (fonts, styles and symbols of both merged)", [sig(e, cmb) for e in objects(both)] == want, f"{len(objects(both))} vs {len(want)}")
oids = [e.get("oid") for e in objects(both)]
check("every object has an id of its own (the imported ones were given new ones)", len(set(oids)) == len(oids) and None not in oids, f"{len(set(oids))} of {len(oids)}")
dd = [l for l in o if l.startswith("DETAILSINFO")]
check("the details of the sheet are those of its own design", dd[0] == dd[1], "")
inf = [objs_of(l) for l in o if l.startswith("INFO ")]
check("one undo takes back all that was imported", inf[-1] == inf[0], str(inf))
# 2. a design of several sheets: only the first comes in
multi_f = os.path.join(out, "multi.dsn")
o, rc, err = run(f'''newdoc "ISO A4" landscape
tool text
mouse down 60 40
setprop text "FIRST SHEET"
tool select
addsheet
tool text
mouse down 60 40
setprop text "SECOND SHEET"
save "{multi_f}"
newdoc "ISO A4" landscape
import "{multi_f}"
save "{out}/multi_in.dsn"
''')
imp_texts = [(e.text or "") for e in objects(sheet0(f"{out}/multi_in.dsn")) if e.tag == "TEXT"]
check("a file with several sheets: only the first sheet is imported", rc == 0 and imp_texts == ["FIRST SHEET"], str(imp_texts))
check("and that file really has two sheets", len(ET.parse(multi_f).getroot().findall("TinyCAD")) == 2, "")
# 3. what Copy to wrote
o, rc, err = run(f'''open "{A}"
selectclass TDrawMethod
copyto "{out}/copied.dsn"
newdoc "ISO A4" landscape
import "{out}/copied.dsn"
save "{out}/round.dsn"
''')
cp = [e for e in objects(sa) if e.tag == "SYMBOL"]; rd = objects(sheet0(f"{out}/round.dsn"))
check("what Copy to wrote can be imported: the same symbols come back", rc == 0 and len(rd) == len(cp) and [sig(e, resource_maps(sa)) for e in cp] == [sig(e, resource_maps(sheet0(f"{out}/round.dsn"))) for e in rd], f"{len(rd)} vs {len(cp)}")
# 4. cancelling with a right click
o, rc, err = run(f'''newdoc "ISO A4" landscape
info
undoinfo
import "{A}"
mouse move 90 90
mouse rdown 90 90
mouse rup 90 90
info
undoinfo
docs
''')
inf = [objs_of(l) for l in o if l.startswith("INFO ")]; uds = [l for l in o if l.startswith("UNDOINFO")]
check("a right click cancels the import: the objects are gone, no undo step is left and the document is not marked as changed",
      rc == 0 and inf[0] == inf[1] and uds[0] == uds[1] and "*" not in pick(o, "DOCS "), f"{inf} {uds} {pick(o, 'DOCS ')}")
# 5. files that cannot be imported
notdsn = os.path.join(out, "notes.txt"); open(notdsn, "w").write("this is not a design\n")
empty = os.path.join(out, "empty.dsn"); open(empty, "w").write("")
o, rc, err = run(f'''open "{A}"
info
undoinfo
import "{notdsn}"
import "{empty}"
import "{out}/missing.dsn"
info
undoinfo
''')
res = [int(l.split()[1]) for l in o if l.startswith("IMPORT ")]
inf = [objs_of(l) for l in o if l.startswith("INFO ")]; uds = [l for l in o if l.startswith("UNDOINFO")]
check("files that cannot be imported (not a design, empty, missing) bring in nothing and are reported, not a crash",
      rc == 0 and res == [0, 0, 0] and not any(l.startswith("ERROR") for l in o), f"{res} {[l for l in o if l.startswith('ERROR')]}")
check("and they change nothing: the objects and the undo history are as they were", inf[0] == inf[1] and uds[0] == uds[1], f"{inf} {uds}")
# 6. cancelling an import into a sheet that already has objects gives back exactly what was there
o, rc, err = run(f'''open "{A}"
info
undoinfo
import "{B}"
mouse move 120 100
mouse rdown 120 100
mouse rup 120 100
save "{out}/after_cancel.dsn"
info
undoinfo
''')
ac = sheet0(f"{out}/after_cancel.dsn"); inf = [objs_of(l) for l in o if l.startswith("INFO ")]; uds = [l for l in o if l.startswith("UNDOINFO")]
check("cancelling an import into a sheet that has objects gives back exactly those objects (and leaves no undo step)",
      rc == 0 and [sig(e, resource_maps(ac)) for e in objects(ac)] == [sig(e, resource_maps(sa)) for e in objects(sa)] and inf[0] == inf[1] and uds[0] == uds[1], f"{inf} {uds} {len(objects(ac))} vs {len(objects(sa))}")
print(f"import: {checks} checks, {len(fails)} failures")
print("\nIMPORT CHECKS PASSED" if not fails else f"\nIMPORT CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
