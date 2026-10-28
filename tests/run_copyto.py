"""Copy to (Ctrl+E): the selected objects of the sheet saved as a design file of their own. Checked on every sample design,
for select all and for each kind of object the design has, against an independent reading of the original XML:
  - the file is a one-sheet TinyCAD document with the sheet's name and details
  - the objects in it are exactly the selected ones, in the same order, with the same attributes and children
    (numbers compared as numbers; the only attributes the file may add are those listed in ALLOWED_EXTRA)
  - every symbol definition is there; fonts, styles and fills are some of the original's with the same content,
    and every font the objects use is there
  - the file opens again in the program with that many objects
  - the document that was copied from is untouched: no undo step, no unsaved-changes mark
and for the edge cases: nothing selected writes nothing (an existing file is left alone), an existing file is replaced,
a name with spaces and non-ASCII characters works, and a folder that does not exist is reported, not a crash."""
import glob, os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Copy to checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
env = dict(os.environ, HOME=os.path.join(tmp, "home")); os.makedirs(env["HOME"])
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, d[:400])
def run(script):
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=120, env=env)
    return r.stdout.split("\n"), r.returncode, r.stderr
from designoracle import HEADER, ALLOWED_EXTRA, REFS, EXTRA_CHILD, CLASS_OF, norm, sig, resource_maps, dropped, objects, sheet0
designs = sorted(glob.glob(os.path.join(EX, "**", "*.dsn"), recursive=True))
used = copies = elements = 0
for path in designs:
    sh = sheet0(path); objs = objects(sh)
    if not objs: continue
    out = os.path.join(tmp, "out"); shutil.rmtree(out, ignore_errors=True); os.makedirs(out)
    plan = [("all", "selectall", objs)]
    for tag, cls in CLASS_OF.items():
        sel = [e for e in objs if e.tag == tag or (tag == "TEXT" and e.tag == "BUSNAME")]
        if sel: plan.append((tag, f"selectclass {cls}", sel))
    lines = [f'open "{path}"', "undoinfo", "docs"]
    for name, cmd, _ in plan: lines += ["selclear", cmd, f'copyto "{out}/{name}.dsn"']
    lines += ["undoinfo", "docs"]
    for name, _c, _s in plan: lines += [f'open "{out}/{name}.dsn"', "info"]
    o, rc, err = run("\n".join(lines) + "\n")
    if rc != 0 or any(l.startswith("ERROR") for l in o):
        check(f"{os.path.basename(path)}: ran cleanly", False, "\n".join(l for l in o if l.startswith("ERROR")) + err[-200:]); continue
    used += 1
    base = os.path.basename(path)
    wrote = {l.split()[2].rsplit("/", 1)[-1][:-4]: int(l.split()[1]) for l in o if l.startswith("COPYTO ")}
    for k, (name, cmd, sel) in enumerate(plan):
        copies += 1; elements += len(sel)
        check(f"{base}: {name}: Copy to reports how many objects it wrote", wrote.get(name) == len(sel), f"{wrote.get(name)} vs {len(sel)}")
        f = os.path.join(out, name + ".dsn")
        if not os.path.exists(f): check(f"{base}: {name}: the file was written", False); continue
        r = ET.parse(f).getroot()
        check(f"{base}: {name}: a one-sheet TinyCAD document", r.tag == "TinyCAD", r.tag)
        check(f"{base}: {name}: the sheet's name and details", sig(sh.find("NAME"), {}) == sig(r.find("NAME"), {}) and sig(sh.find("DETAILS"), {}) == sig(r.find("DETAILS"), {}), "")
        got = objects(r)
        om, cm = resource_maps(sh), resource_maps(r)
        check(f"{base}: {name}: exactly the selected objects, in order, with the same attributes, fonts, styles and fills",
              len(got) == len(sel) and [sig(e, om) for e in sel] == [sig(e, cm) for e in got], f"{len(got)} vs {len(sel)}")
        # the symbol definitions in the file are exactly those the selected symbols use (TinyCAD writes every definition of the sheet; this writes
        # only what the selection needs, so a copy of a few wires does not carry the whole library of the design along)
        # (counted by definition, not by content: a design can have two definitions that are identical)
        used_ids = sorted({e.get("id") for e in sel if e.tag == "SYMBOL"})
        want_defs = sorted(repr(om["SYMBOLDEF"][i]) for i in used_ids)
        have_defs = sorted(repr(sig(e, cm)) for e in r.findall("SYMBOLDEF"))
        check(f"{base}: {name}: exactly the symbol definitions the selected symbols use", have_defs == want_defs, f"{len(have_defs)} vs {len(want_defs)}")
        for res in ("FONT", "STYLE", "FILL"):
            check(f"{base}: {name}: {res} definitions are the original's", all(v in om[res].values() for v in cm[res].values()), "")
    ud = [l for l in o if l.startswith("UNDOINFO")]; dk = [l for l in o if l.startswith("DOCS ")]
    check(f"{base}: the document copied from is untouched (no undo step, no unsaved-changes mark)", ud[0] == ud[1] and dk[0].split("list=")[1] == dk[1].split("list=")[1] and "*" not in dk[1], f"{ud} {dk}")
    # each file opens again with that many objects (an origin the loader adds is allowed for)
    oi = [l for l in o if l.startswith("INFO ")]
    extra = None
    for (name, _c, sel), l in zip(plan, oi):
        n_obj = int(re.search(r"objects=(\d+)", l).group(1))
        extra = n_obj - len(sel) if extra is None else extra
        check(f"{base}: {name}: the file opens again with those objects", n_obj - len(sel) == extra and 0 <= extra <= 2, f"{n_obj} vs {len(sel)} (extra {extra})")
print(f"{used} designs, {copies} copies, {elements} objects checked")
# the edge cases
d0 = next(p for p in designs if objects(sheet0(p)))
edge = os.path.join(tmp, "edge"); os.makedirs(edge)
sentinel = os.path.join(edge, "keep.dsn"); open(sentinel, "w").write("SENTINEL")
named = os.path.join(edge, "a name with spaces and \u00e9\u00e8 \u2126.dsn")
o, rc, err = run(f'''open "{d0}"
copyto "{sentinel}"
selectall
copyto "{named}"
copyto "{sentinel}"
copyto "{edge}/no/such/folder/x.dsn"
selclear
copyto "{edge}/none.dsn"
''')
lines = [l for l in o if l.startswith("COPYTO") or l.startswith("ERROR")]
check("edge cases: the program ran cleanly (an unwritable place is reported, not a crash)", rc == 0 and not any(l.startswith("ERROR") for l in o), str(lines) + err[-200:])
counts = [int(l.split()[1]) for l in lines if l.startswith("COPYTO")]
check("nothing selected: 0 objects", counts[0] == 0 and counts[-1] == 0, str(counts))
check("nothing selected writes nothing: no file appears", not os.path.exists(os.path.join(edge, "none.dsn")), "")
check("a name with spaces and non-ASCII characters works", counts[1] > 0 and os.path.exists(named) and ET.parse(named).getroot().tag == "TinyCAD", str(counts))
check("an existing file is replaced by the copy", ET.parse(sentinel).getroot().tag == "TinyCAD" and counts[2] == counts[1], str(counts))
check("a folder that does not exist: 0 objects written, nothing created", counts[3] == 0 and not os.path.exists(os.path.join(edge, "no")), str(counts))
sent2 = os.path.join(edge, "keep2.dsn"); open(sent2, "w").write("SENTINEL")
o, rc, err = run(f'open "{d0}"\ncopyto "{sent2}"\n')
check("with nothing selected an existing file keeps its contents", open(sent2).read() == "SENTINEL", "")
print(f"copy to: {checks} checks, {len(fails)} failures")
print("\nCOPY TO CHECKS PASSED" if not fails else f"\nCOPY TO CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
