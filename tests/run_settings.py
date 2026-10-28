"""The program settings: the recently used files (the first setting), kept with TRegistry under
HKEY_CURRENT_USER\\SOFTWARE\\HPL Software\\TyCAD Electrical, one value for each (MRU1 to MRU4, newest first).
Every call of the driver is a separate run, so what is read is what the registry really held. Where the store is a
file (the FPC Registry unit off Windows) it is also read back with an independent XML parser."""
import os, re, subprocess, sys, tempfile, glob
import xml.etree.ElementTree as ET
BUILD = os.environ.get("TC_BUILD", "build"); EXE = os.path.join(BUILD, "settingstest")
home = tempfile.mkdtemp(); fails = []
env = dict(os.environ, HOME=home)
def check(n, ok, d=""):
    if not ok: fails.append(n); print("  FAIL", n, d)
def run(*a):
    r = subprocess.run([EXE, *a], capture_output=True, text=True, env=env)
    if r.returncode != 0: raise SystemExit("settingstest failed: " + " ".join(a) + "\n" + r.stdout[-300:] + r.stderr[-300:])
    return r.stdout.strip()
def mru(out):
    m = re.match(r"MRU (\d+)((?: \[[^\]]*\])*)", out); n = int(m.group(1))
    return n, re.findall(r"\[([^\]]*)\]", m.group(2))
def mruvals(d): return {k: v for k, v in (d or {}).items() if k.startswith("MRU")}
def opts(out):
    """the OPTS and COLORS lines of the driver as dictionaries"""
    o = {}; c = {}
    for l in out.split("\n"):
        if l.startswith("OPTS "): o = dict(kv.split("=", 1) for kv in l.split()[1:])
        if l.startswith("COLORS"): c = {int(kv.split("=")[0]): int(kv.split("=")[1]) for kv in l.split()[1:]}
    return o, c
def store():
    """the stored values of the key, read with a separate XML parser"""
    files = glob.glob(os.path.join(home, ".config", "*", "reg.xml"))
    if not files: return None
    node = ET.parse(files[0]).getroot()
    for part in ("HKEY_CURRENT_USER", "SOFTWARE", "HPL Software", "TyCAD Electrical"):
        node = next((k for k in node.findall("Key") if k.get("Name") == part), None)
        if node is None: return {}
    return {v.get("Name"): (v.text or "") for v in node.findall("Value")}
P = lambda n: "/data/designs/" + n
n, l = mru(run("show"))
check("a first run has no recently used files and no stored settings", n == 0 and l == ["", "", "", ""] and store() is None, f"{n} {l} {store()}")
n, l = mru(run("add", P("a.dsn")))
check("one file is the only entry", n == 1 and l[0] == P("a.dsn") and l[1:] == ["", "", ""], str(l))
n, l = mru(run("add", P("b.dsn"), P("c.dsn")))
check("newest first: c, b, a", n == 3 and l[:3] == [P("c.dsn"), P("b.dsn"), P("a.dsn")], str(l))
check("each is kept as a value of its own in the registry key, named MRU1 to MRU4", mruvals(store()) == {"MRU1": P("c.dsn"), "MRU2": P("b.dsn"), "MRU3": P("a.dsn")}, str(store()))
n, l = mru(run("add", P("a.dsn")))
check("a file used again moves to the top and is not listed twice", n == 3 and l[:3] == [P("a.dsn"), P("c.dsn"), P("b.dsn")], str(l))
n, l = mru(run("add", P("d.dsn"), P("e.dsn")))
check("only four are kept: the oldest drops off", n == 4 and l == [P("e.dsn"), P("d.dsn"), P("a.dsn"), P("c.dsn")], str(l))
check("and the stored values are those four, newest first", mruvals(store()) == {"MRU1": P("e.dsn"), "MRU2": P("d.dsn"), "MRU3": P("a.dsn"), "MRU4": P("c.dsn")}, str(store()))
n, l = mru(run("remove", P("d.dsn")))
check("removing a file closes the gap", n == 3 and l == [P("e.dsn"), P("a.dsn"), P("c.dsn"), ""], str(l))
check("and the stored value that is no longer needed is deleted", mruvals(store()) == {"MRU1": P("e.dsn"), "MRU2": P("a.dsn"), "MRU3": P("c.dsn")}, str(store()))
n, l = mru(run("remove", P("nothere.dsn")))
check("removing a file that is not listed changes nothing", n == 3 and l[:3] == [P("e.dsn"), P("a.dsn"), P("c.dsn")], str(l))
n, l = mru(run("add", ""))
check("an empty name is ignored", n == 3, str(l))
# a relative name is stored in full
cwd = os.getcwd(); os.chdir(home)
n, l = mru(run("add", "rel.dsn")); os.chdir(cwd)
check("a relative file name is stored as the full name", l[0] == os.path.join(home, "rel.dsn"), str(l))
# a damaged store: a gap, a value that is empty, a fifth value, text that is not a file
run("del", "MRU1"); run("put", "MRU4", ""); run("put", "MRU5", "/ignored/five.dsn")
n, l = mru(run("show"))
check("entries with a gap or an empty value are packed to the front when loaded (MRU2 and MRU3 remain, as the first two), and a fifth value is ignored",
      n == 2 and l == [P("e.dsn"), P("a.dsn"), "", ""] and "/ignored/five.dsn" not in l, str(l))
# another key does not touch this one
before = mruvals(store())
run("key", "SOFTWARE\\Somebody Else\\Other App", "add", P("z.dsn"))
check("settings under another key are kept apart", store() is not None and mruvals(store()) == before, str(store()))
# the key path is the one that was asked for
files = glob.glob(os.path.join(home, ".config", "*", "reg.xml")); root = ET.parse(files[0]).getroot()
paths = []
def walk(node, prefix):
    for k in node.findall("Key"):
        p = prefix + [k.get("Name")]
        if k.findall("Value"): paths.append("\\".join(p))
        walk(k, p)
walk(root, [])
check("the values are under HKEY_CURRENT_USER\\SOFTWARE\\HPL Software\\TyCAD Electrical", "HKEY_CURRENT_USER\\SOFTWARE\\HPL Software\\TyCAD Electrical" in paths, str(paths))
print(f"program settings: recently used files, 4 kept, newest first, one registry value each ({len(paths)} keys written in the test)")
# ---------------- the options ----------------
FACTORY = {"showgrid": "1", "snapgrid": "1", "grid": "2", "units": "0", "autodrag": "1", "autosnap": "1", "autojunc": "1", "range": "15", "autosave": "10"}
o, c = opts(run("opts"))
check("the options start as TinyCAD's defaults (grid shown and snapped, 2 mm, millimetres, auto-drag, auto-snap and auto-junctions on, range 15, save every 10 minutes) and no color is the user's own", o == FACTORY and all(v == -1 for v in c.values()) and len(c) == 12, f"{o} {c}")
o, c = opts(run("setopts", "showgrid=0", "snapgrid=0", "grid=1.27", "units=1", "autodrag=0", "autosnap=0", "autojunc=0", "range=22", "autosave=25"))
CHANGED = {"showgrid": "0", "snapgrid": "0", "grid": "1.27", "units": "1", "autodrag": "0", "autosnap": "0", "autojunc": "0", "range": "22", "autosave": "25"}
check("every option can be changed and is kept", o == CHANGED, str(o))
o, c = opts(run("opts"))
check("and a later run of the program finds them all as they were left", o == CHANGED, str(o))
st = store()
check("each is a value of its own in the registry key, under the names TinyCAD uses (Grid is text in mm, AutoDragRange is the auto-snap range)",
      all(k in st for k in ("ShowGrid", "SnapGrid", "Grid", "Units", "AutoDrag", "AutoSnap", "AutoJunc", "AutoDragRange", "AutoSave")) and st["Grid"] == "1.27" and st["Units"] == "1" and st["AutoDragRange"] == "22" and st["AutoSave"] == "25", str(st))
check("and the recently used files are still there beside them", len(mruvals(st)) >= 1, str(st))
o, c = opts(run("setopts", "autosave=0"))
check("an interval of 0 means no automatic save", o["autosave"] == "0" and opts(run("opts"))[0]["autosave"] == "0", str(o))
# stored nonsense is put right when it is loaded
run("put", "Grid", "-5"); run("put", "AutoDragRange", "0"); run("put", "AutoSave", "90")
o, c = opts(run("opts"))
check("a grid that is not a size, a range that is not a distance and an interval over 60 minutes are put right (2 mm, 15, 60)", o["grid"] == "2" and o["range"] == "15" and o["autosave"] == "60", str(o))
run("put", "Units", "7"); run("put", "Grid", "not a number")
o, c = opts(run("opts"))
check("units that are neither millimetres nor inches, and a grid that is not a number, give the defaults", o["units"] == "0" and o["grid"] == "2", str(o))
# the colors: only the ones the user has changed are kept
o, c = opts(run("setcolor", "1", "255"))
check("a color the user has chosen is kept as theirs (the wire color 1 as 255, red)", c[1] == 255 and all(c[k] == -1 for k in c if k != 1), str(c))
st = store()
check("and it is stored under TinyCAD's name for it (COLOR_WIRE), the others not at all", st.get("COLOR_WIRE") == "255" and not [k for k in st if k.startswith("COLOR_") and k != "COLOR_WIRE"], str({k: v for k, v in st.items() if k.startswith("COLOR")}))
o, c = opts(run("setcolor", "9", "8421504"))
c2 = opts(run("opts"))[1]
check("two colors can be the user's own, and a later run finds both", c2[1] == 255 and c2[9] == 8421504, str(c2))
o, c = opts(run("clearcolor", "1"))
check("going back to the factory color forgets it, and deletes its stored value", c[1] == -1 and c[9] == 8421504 and "COLOR_WIRE" not in store() and "COLOR_BACKGROUND" in store(), str(c))

print("\nSETTINGS CHECKS PASSED" if not fails else f"\nSETTINGS CHECKS FAILED: {fails}")
sys.exit(1 if fails else 0)
