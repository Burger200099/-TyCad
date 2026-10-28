"""Options (TinyCAD's View > Options): the Grid, Auto-snap and Auto-save pages, applied to the open design and kept for new ones. The real dialog is filled in and OK'd
by script, and what the program then holds is compared with an independent statement of what it should be:
  - the limits and the messages: a grid of up to 1000 mm, a snap range of 1 to 200 design units, 1 to 60 minutes between saves; what cannot be used is refused with
    its message and changes nothing
  - the units: a spacing typed in inches is that many times 25.4 mm; switching units does not change the spacing (a 5 mm grid stays exactly 5 mm there and back); the
    list of usual sizes follows the spacing
  - applying: every sheet of the design takes the settings, so do the view, the settings that are kept in the registry, and what a new design starts with
  - keeping: after a restart the saved options are shown; a new design starts with them, while a design opened from a file keeps the grid its file says
  - what they do: the grid size and snapping decide where a drawn shape lands; auto junctions decide whether a T of wires gets a junction; the status bar shows
    positions in the chosen units
  - the automatic save: a named design is written as <name>.autosave with whatever it holds now (including changes not yet saved), the design itself and its
    file are not touched, an unnamed design is left out, a failure is silent, and the timer follows the minutes
Needs the built program."""
import hashlib, os, random, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from designoracle import sig, resource_maps, objects, sheet0
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Options checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:420])
homes = {}
def run(script, home="fresh", timeout=120):
    h = os.path.join(tmp, "home_" + home) if home != "fresh" else tempfile.mkdtemp(dir=tmp)
    os.makedirs(h, exist_ok=True)
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n"), r.returncode, r.stderr
def kv(line):
    return {k: v for k, v in (t.split("=", 1) for t in line.split() if "=" in t)}
def info(lines, nth=0):
    """the OPTIONSINFO groups of the nth optionsinfo command: now, sheets, settings, defaults, autosave"""
    groups = []; cur = None
    for l in lines:
        if l.startswith("OPTIONSINFO now"): cur = {"sheets": []}; groups.append(cur); cur["now"] = kv(l)
        elif l.startswith("OPTIONSINFO sheet") and cur is not None: cur["sheets"].append(kv(l))
        elif l.startswith("OPTIONSINFO settings") and cur is not None: cur["settings"] = kv(l)
        elif l.startswith("OPTIONSINFO defaults") and cur is not None: cur["defaults"] = kv(l)
        elif l.startswith("OPTIONSINFO autosave") and cur is not None: cur["autosave"] = kv(l)
    return groups[nth]
def opt(lines, nth=0):
    out = [l for l in lines if l.startswith("OPTIONS err=")]
    m = re.match(r"OPTIONS err=(.*?) grid=(\S*) (\S+) preset=(\d+)", out[nth])
    return dict(err=m.group(1), grid=m.group(2), unit=m.group(3), preset=int(m.group(4)))
sample = next(p for p in sorted(os.path.join(dp, f) for dp, _, fs in os.walk(EX) for f in fs if f.endswith(".dsn")) if os.path.basename(p) == "PSU.dsn")
work = os.path.join(tmp, "work"); os.makedirs(work)
psu = os.path.join(work, "PSU.dsn"); shutil.copy(sample, psu)
def close(a, b, tol=1e-5): return abs(float(a) - float(b)) <= tol
# ---------- the defaults (TinyCAD's: grid on, snap on, 2 mm, millimetres, all the auto options on, 15 units, a save every 10 minutes) ----------
o, rc, err = run(f'open "{psu}"\noptionsinfo\n')
check("the program starts", rc == 0 and not any(l.startswith("ERROR") for l in o), err[-200:])
g = info(o); st = g["settings"]; df = g["defaults"]; au = g["autosave"]
check("what the program starts with: grid and snap on, 2 mm, millimetres, auto drag, snap and junctions on, a range of 15, a save every 10 minutes",
      (st["showgrid"], st["snap"], st["grid"], st["units"], st["autodrag"], st["autosnap"], st["autojunction"], st["range"], st["autosave"]) == ("1", "1", "2", "0", "1", "1", "1", "15", "10"), str(st))
check("and the defaults for a new design are the same, and the timer runs every 10 minutes", (df["grid"], df["units"], df["range"]) == ("2", "0", "15") and au["timer"] == "1" and au["interval"] == "600000", f"{df} {au}")
baseline = info(o)["sheets"][0]
# ---------- what cannot be used is refused, with its message, and nothing changes ----------
BAD = [("grid=abc", "The grid spacing is not a number."), ("grid=0", "The grid spacing must be more than 0 and not more than 1000 mm."),
       ("grid=-2", "The grid spacing must be more than 0 and not more than 1000 mm."), ("grid=1001", "The grid spacing must be more than 0 and not more than 1000 mm."),
       ("units=in grid=40", "The grid spacing must be more than 0 and not more than 1000 mm."), ("range=0", "The auto-snap range must be from 1 to 200 design units."),
       ("range=201", "The auto-snap range must be from 1 to 200 design units."), ("range=abc", "The auto-snap range is not a whole number."),
       ("autosave=61", "The time between automatic saves must be from 1 to 60 minutes."), ("autosave=abc", "The time between automatic saves is not a whole number of minutes."),
       ("autosave=-3", "The time between automatic saves is not a whole number of minutes.")]
script = f'open "{psu}"\noptionsinfo\n' + "".join(f"options {b}\n" for b, _ in BAD) + "optionsinfo\n"
o, rc, err = run(script)
errs = [l for l in o if l.startswith("OPTIONS err=")]
check("every value that cannot be used is refused with its own message", [re.match(r"OPTIONS err=(.*?) grid=", l).group(1) for l in errs] == [m for _, m in BAD], str([re.match(r"OPTIONS err=(.*?) grid=", l).group(1) for l in errs]))
check("and none of them was applied (nothing applied=1 was printed) nor changed what the design or the settings hold", not any("applied=1" in l for l in o) and info(o, 0) == info(o, 1), "")
# ---------- the limits themselves are allowed ----------
o, rc, err = run(f'open "{psu}"\noptions grid=1000 range=200 autosave=60\noptionsinfo\noptions grid=0.001 range=1 autosave=1\noptionsinfo\n')
a, b = info(o, 0), info(o, 1)
check("the limits are allowed: 1000 mm, a range of 200 and 60 minutes; and 0.001 mm, a range of 1 and 1 minute", close(a["now"]["grid"], 1000) and a["now"]["range"] == "200" and a["autosave"]["interval"] == "3600000" and close(b["now"]["grid"], 0.001) and b["now"]["range"] == "1" and b["autosave"]["interval"] == "60000", f"{a['now']} {a['autosave']} {b['now']} {b['autosave']}")
# ---------- units and the usual sizes ----------
PRESETS = [0.5, 1, 1.27, 2, 2.54, 5, 10]
o, rc, err = run(f'open "{psu}"\n' + "".join(f"options grid={v}\n" for v in ("2", "2.54", "0.5", "10", "3", "1,27", "1.27")) + "options units=in grid=0.1\noptions units=in grid=0.0787402\n")
ps = [opt(o, i) for i in range(9)]
want = [4, 5, 1, 7, 0, 3, 3]
check("the list of usual sizes follows the spacing: 2, 2.54, 0.5 and 10 mm select theirs, 3 mm is Custom, and a comma is a decimal point (1,27 mm is 1.27)", [p["preset"] for p in ps[:7]] == want, str([p["preset"] for p in ps[:7]]))
check("in inches 0.1 is the 2.54 mm size and 0.0787402 is the 2 mm size", ps[7]["preset"] == 5 and ps[8]["preset"] == 4 and ps[7]["unit"] == "in", str(ps[7:]))
rnd = random.Random(11); exact_ok = True; first = None
for k in range(8):
    mm = rnd.choice([0.25, 0.5, 1, 1.27, 2, 2.54, 5, 7.5, 10, 12.7, 25.4, 33.3])
    o, rc, err = run(f'open "{psu}"\noptions grid={mm}\noptions units=in\noptionsinfo\noptions units=mm\noptionsinfo\noptions units=in\noptions units=mm\noptionsinfo\n')
    gs = [info(o, i)["now"]["grid"] for i in range(3)]
    if not all(abs(float(x) - mm) < 1e-5 for x in gs): exact_ok = False; first = first or (mm, gs)
check("switching the units does not change the spacing: it is exactly what it was after to inches and back, however often (8 sizes)", exact_ok, str(first))
o, rc, err = run(f'open "{psu}"\noptions units=in grid=0.25\noptionsinfo\noptions units=in grid=1/4\n')
check("a spacing typed in inches is that many times 25.4 mm (0.25 in is 6.35 mm)", close(info(o)["now"]["grid"], 6.35) and info(o)["now"]["units"] == "1", str(info(o)["now"]))
# ---------- applying: every sheet, the view, the settings and the defaults ----------
rnd = random.Random(5); bad = 0; firstbad = None; n_apply = 0
for k in range(14):
    units = rnd.choice(["mm", "in"]); val = rnd.choice([0.5, 1, 2, 2.54, 5, 7]) if units == "mm" else rnd.choice([0.05, 0.1, 0.25, 0.5])
    flags = {f: rnd.choice(["0", "1"]) for f in ("showgrid", "snap", "autodrag", "autojunction")}; asnap = rnd.choice(["0", "1"]); rng_ = rnd.choice([1, 15, 40, 200]); mins = rnd.choice([0, 1, 5, 60])
    o, rc, err = run(f'open "{psu}"\naddsheet\n' + f"options units={units} grid={val} showgrid={flags['showgrid']} snap={flags['snap']} autodrag={flags['autodrag']} autosnap={asnap} autojunction={flags['autojunction']} range={rng_} autosave={mins}\noptionsinfo\n")
    n_apply += 1
    g = info(o); mm = val * (25.4 if units == "in" else 1)
    expect_now = dict(showgrid=flags["showgrid"], snap=flags["snap"], units="1" if units == "in" else "0", autodrag=flags["autodrag"], autosnap=asnap, autojunction=flags["autojunction"], range=str(rng_))
    ok = all(g["now"][key] == v for key, v in expect_now.items()) and close(g["now"]["grid"], mm) and len(g["sheets"]) == 2
    for sh in g["sheets"]:
        ok = ok and close(sh["grid"], mm) and sh["snap"] == flags["snap"] and sh["show"] == flags["showgrid"] and sh["units"] == expect_now["units"] and sh["autodrag"] == flags["autodrag"] and sh["autosnap"] == asnap and sh["autojunction"] == flags["autojunction"] and sh["range"] == str(rng_)
    ok = ok and close(g["settings"]["grid"], mm) and g["settings"]["autosave"] == str(mins) and close(g["defaults"]["grid"], mm) and g["defaults"]["units"] == expect_now["units"] and g["defaults"]["autojunction"] == flags["autojunction"]
    ok = ok and (g["autosave"]["timer"] == ("1" if mins > 0 else "0")) and (mins == 0 or g["autosave"]["interval"] == str(mins * 60000))
    if not ok: bad += 1; firstbad = firstbad or (units, val, flags, asnap, rng_, mins, g)
check(f"applying {n_apply} random combinations: the view, EVERY sheet of the design, the saved settings, what new designs start with and the timer all hold the values", bad == 0, f"{bad} wrong; first {firstbad}")
# ---------- keeping them: after a restart, and what a new or an opened design starts with ----------
o, rc, err = run(f'open "{psu}"\noptions units=in grid=0.25 showgrid=0 snap=0 autodrag=0 autosnap=0 autojunction=0 range=33 autosave=7\n', home="keep")
check("the options are applied once and the program ends", any("applied=1" in l for l in o), str(o[-4:]))
o, rc, err = run(f'optionsinfo\nnewdoc "ISO A4" landscape\noptionsinfo\nopen "{psu}"\noptionsinfo\n', home="keep")
g0, g1, g2 = info(o, 0), info(o, 1), info(o, 2)
check("after a restart the saved options are the program's (with no design open the dialog would show these)", (g0["settings"]["units"], g0["settings"]["autodrag"], g0["settings"]["range"], g0["settings"]["autosave"]) == ("1", "0", "33", "7") and close(g0["settings"]["grid"], 6.35) and g0["autosave"]["interval"] == "420000", f"{g0['settings']} {g0['autosave']}")
sh = g1["sheets"][0]
check("a new design starts with them: grid 6.35 mm, snap off, inches, auto options off, range 33", close(sh["grid"], 6.35) and sh["snap"] == "0" and sh["units"] == "1" and sh["autodrag"] == "0" and sh["autosnap"] == "0" and sh["autojunction"] == "0" and sh["range"] == "33" and g1["now"]["showgrid"] == "0", f"{sh} {g1['now']}")
sh = g2["sheets"][1] if len(g2["sheets"]) > 1 else g2["sheets"][-1]
sh = g2["sheets"][0]
file_units = [e.text for e in sheet0(psu).iter("UNITS")]
check("a design opened from a file keeps the grid its file says (the options are what a design starts with, not what overrides a file) and takes the auto options as set",
      close(sh["grid"], baseline["grid"]) and sh["snap"] == baseline["snap"] and sh["autodrag"] == "0" and sh["autojunction"] == "0" and sh["range"] == "33", f"{sh} vs {baseline}")
check("and its units are its file's", sh["units"] == (file_units[0].strip() if file_units else "0"), f"{sh['units']} vs {file_units}")
# ---------- what they do: where a shape lands, junctions, the units of the status bar ----------
def rect_corners(path):
    sh_ = sheet0(path); e = sh_.find("RECTANGLE")
    return [tuple(float(v) for v in e.get(k).split(",")) for k in ("a", "b")]
def on_grid(v, step): return abs(v / step - round(v / step)) < 1e-6
o, rc, err = run(f'newdoc "ISO A4" landscape\noptions grid=5 snap=1\ntool rect\nmouse down 61.3 42.7\nmouse move 99.1 71.9\nmouse up 99.1 71.9\nsave "{work}/r5.dsn"\n')
c5 = [v for corner in rect_corners(f"{work}/r5.dsn") for v in corner]
o, rc, err = run(f'newdoc "ISO A4" landscape\noptions grid=2 snap=1\ntool rect\nmouse down 61.3 42.7\nmouse move 99.1 71.9\nmouse up 99.1 71.9\nsave "{work}/r2.dsn"\n')
c2 = [v for corner in rect_corners(f"{work}/r2.dsn") for v in corner]
o, rc, err = run(f'newdoc "ISO A4" landscape\noptions grid=5 snap=0\ntool rect\nmouse down 61.3 42.7\nmouse move 99.1 71.9\nmouse up 99.1 71.9\nsave "{work}/r0.dsn"\n')
c0 = [v for corner in rect_corners(f"{work}/r0.dsn") for v in corner]
check("with a 5 mm grid and snapping on, a rectangle drawn at odd places has every corner on the 5 mm grid", all(on_grid(v, 5) for v in c5), str(c5))
check("with a 2 mm grid it is on the 2 mm grid (and not on the 5 mm one)", all(on_grid(v, 2) for v in c2) and not all(on_grid(v, 5) for v in c2), str(c2))
check("with snapping off the same rectangle is where the pointer was (not on the grid)", not all(on_grid(v, 5) for v in c0) and all(abs(v - w) < 1.0 for v, w in zip(c0, (61.3, 42.7, 99.1, 71.9))), str(c0))
def junctions(path):
    sh_ = sheet0(path); return len(sh_.findall("JUNCTION")), len(sh_.findall("WIRE"))
T = 'tool wire\nmouse down 20 20\nmouse down 60 20\nmouse rdown 60 20\ntool wire\nmouse down 40 40\nmouse down 40 20\nmouse rdown 40 20\n'
o, rc, err = run(f'newdoc "ISO A4" landscape\noptions autojunction=1\n{T}save "{work}/j1.dsn"\n')
o2, rc, err = run(f'newdoc "ISO A4" landscape\noptions autojunction=0\n{T}save "{work}/j0.dsn"\n')
check("with auto junctions a wire ending on another makes a junction (and splits the wire)", junctions(f"{work}/j1.dsn")[0] >= 1 and junctions(f"{work}/j1.dsn")[1] >= 3, str(junctions(f"{work}/j1.dsn")))
check("without them there is no junction and the wires are left whole", junctions(f"{work}/j0.dsn") == (0, 2), str(junctions(f"{work}/j0.dsn")))
o, rc, err = run(f'open "{psu}"\nmouse move 100 70\npositioninfo\noptions units=in\nmouse move 100 70\npositioninfo\n')
bars = [re.search(r"text=\[(.*?)\] grid=", l).group(1) for l in o if l.startswith("POSITIONINFO")]
mm = re.match(r"\s*(-?[\d.]+),\s*(-?[\d.]+) mm$", bars[0]); inch = re.match(r"\s*(-?[\d.]+),\s*(-?[\d.]+) ''$", bars[1])
check("the position bar shows the pointer in millimetres to a hundredth, and in inches to a thousandth once the units are inches (the same place)", mm and inch and abs(float(inch.group(1)) - float(mm.group(1)) / 25.4) < 0.004 and abs(float(inch.group(2)) - float(mm.group(2)) / 25.4) < 0.004 and len(inch.group(1).split(".")[1]) == 3 and len(mm.group(1).split(".")[1]) == 2, str(bars))
# ---------- the automatic save ----------
a_dir = os.path.join(work, "auto"); os.makedirs(a_dir)
named = os.path.join(a_dir, "PSU.dsn"); shutil.copy(sample, named)
before = hashlib.sha256(open(named, "rb").read()).hexdigest()
o, rc, err = run(f'open "{named}"\ndocs\nautosave\ndocs\ntool wire\nmouse down 20 20\nmouse down 60 20\nmouse rdown 60 20\ntool select\ndocs\nautosave\ndocs\nnewdoc "ISO A4" landscape\nautosave\n')
cnt = [int(l.split()[1]) for l in o if l.startswith("AUTOSAVE ")]; docs = [l for l in o if l.startswith("DOCS ")]
check("a named design is saved as <name>.autosave; the one that has never been saved is left out", cnt == [1, 1, 1] and os.path.exists(named + ".autosave") and not os.path.exists(named + ".autosave.new"), str(cnt))
orig = sheet0(named); auto = sheet0(named + ".autosave")
check("the copy holds what the design holds now, including a change that is not saved yet (the wire drawn since), and the original file is not touched", len(objects(auto)) == len(objects(orig)) + 1 and hashlib.sha256(open(named, "rb").read()).hexdigest() == before, f"{len(objects(auto))} vs {len(objects(orig))}")
check("the design's own state is untouched: it is not marked saved or changed by an autosave, and keeps its name", "*" not in docs[0] and "*" in docs[2] and docs[2] == docs[3] and docs[0] == docs[1], str(docs))
om = resource_maps(orig); am = resource_maps(auto)
o, rc, err = run(f'open "{named}"\nautosave\n'); second = sheet0(named + ".autosave")
check("an autosave of an unchanged design is the design itself, object for object (and a new one replaces the old copy)", [sig(e, resource_maps(second)) for e in objects(second)] == [sig(e, om) for e in objects(orig)], "")
two_a = os.path.join(work, "auto2a.dsn"); two_b = os.path.join(work, "auto2b.dsn"); shutil.copy(sample, two_a); shutil.copy(sample, two_b)
o, rc, err = run(f'open "{two_a}"\nopen "{two_b}"\nautosave\n')
check("every named design that is open is saved", [int(l.split()[1]) for l in o if l.startswith("AUTOSAVE ")] == [2] and os.path.exists(two_a + ".autosave") and os.path.exists(two_b + ".autosave"), "")
# a failure (here: a folder where the temporary file has to go, which works for any user, root included) is silent, and an earlier good copy is not lost by it
blocked = os.path.join(work, "blocked"); os.makedirs(blocked); bp = os.path.join(blocked, "PSU.dsn"); shutil.copy(sample, bp)
os.makedirs(bp + ".autosave.new"); open(bp + ".autosave", "w").write("AN EARLIER COPY")
o, rc, err = run(f'open "{bp}"\nautosave\nautosave\n')
check("when the copy cannot be written nothing is reported and the program goes on; the earlier copy is still there (a new one is only put in place once it is complete)",
      rc == 0 and [int(l.split()[1]) for l in o if l.startswith("AUTOSAVE ")] == [0, 0] and not any(l.startswith("ERROR") for l in o) and open(bp + ".autosave").read() == "AN EARLIER COPY", str(o[-3:]))
o, rc, err = run(f'open "{psu}"\noptions autosave=5\noptionsinfo\noptions autosave=0\noptionsinfo\noptions autosave=3\noptionsinfo\n')
a = [info(o, i)["autosave"] for i in range(3)]
check("the timer follows the minutes: 5 minutes is 300000 ms, none stops it, 3 starts it again at 180000", a[0]["timer"] == "1" and a[0]["interval"] == "300000" and a[1]["timer"] == "0" and a[2]["timer"] == "1" and a[2]["interval"] == "180000", str(a))
print(f"options: {checks} checks, {len(fails)} failures")
print("\nOPTIONS CHECKS PASSED" if not fails else f"\nOPTIONS CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
