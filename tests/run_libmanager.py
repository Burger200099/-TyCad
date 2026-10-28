"""Library manager (Library > Libraries..., TinyCAD's CDlgLibraryBox "Library Setup") on the real program, checked against Python's own sqlite3 and the file system:
  - the dialog: empty at first, Add and New enabled, Remove and Cleanup only with a library selected, Edit and Upgrade dimmed, OK alone, the list sorted by name
  - Add: several files at once, a library already in use not added twice, a file that is not a library (text, .mdb) refused with a message while the others are added
  - the libraries in use kept in the registry (Library1 ... in the order they were added) and opened again by the next run, without a file that is gone or no longer a library
  - Remove: the library leaves the list, the panel and the registry, the file stays; refused with TinyCAD's message while the library is in use
  - New: .TCLib put on the name, the tables TinyCAD makes (compared with the CREATE statements of TinyCAD's source), an existing file never touched, a message when it cannot be made
  - Cleanup: the file gets smaller after rows were deleted, the symbols stay the same; refused with TinyCAD's message while in use
Needs the built program, xvfb and sqlite3 (Python)."""
import glob, os, re, shutil, subprocess, sys, tempfile, sqlite3
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Library manager checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 14: print("  FAIL", n, str(d)[:900])
def run(script, home, timeout=280):
    h = os.path.join(tmp, "home_" + home); os.makedirs(h, exist_ok=True)
    path = os.path.join(tmp, "script_%s.txt" % home); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n"), r.returncode, r.stderr
def registry(home):
    f = glob.glob(os.path.join(tmp, "home_" + home, ".config", "*", "reg.xml"))
    if not f: return {}
    node = ET.parse(f[0]).getroot()
    for part in ("HKEY_CURRENT_USER", "SOFTWARE", "HPL Software", "TyCAD Electrical"):
        node = next(k for k in node.findall("Key") if k.get("Name") == part)
    return {v.get("Name"): v.text for v in node.findall("Value")}
def libkeys(home):
    r = registry(home)
    return [r[k] for k in sorted((k for k in r if re.fullmatch(r"Library\d+", k)), key=lambda k: int(k[7:]))]
def set_registry(home, name, value):
    f = glob.glob(os.path.join(tmp, "home_" + home, ".config", "*", "reg.xml"))[0]
    tree = ET.parse(f); node = tree.getroot()
    for part in ("HKEY_CURRENT_USER", "SOFTWARE", "HPL Software", "TyCAD Electrical"):
        node = next(k for k in node.findall("Key") if k.get("Name") == part)
    e = ET.SubElement(node, "Value", dict(Name=name)); e.text = str(value)
    tree.write(f)
def lines_of(o, tag): return [l[len(tag) + 1:] for l in o if l.startswith(tag + " ")]
def field(line, name):
    if name == "status": return line.split(" status=", 1)[1] if " status=" in line else None
    m = re.search(r"(?:^| )%s=\[(.*?)\](?= \w+=|$)" % name, line) or re.search(r"(?:^| )%s=(\S*)" % name, line)
    return m.group(1) if m else None
def items(line): return [x for x in field(line, "items").split("|") if x]
def symbols(path):
    c = sqlite3.connect(path)
    rows = c.execute("select NameID,Name,SymbolID,Type,Reference,ppp,Description from Name order by NameID").fetchall()
    data = c.execute("select SymbolID,Data from Symbol order by SymbolID").fetchall()
    c.close(); return rows, data

# --- the libraries to work with: copies of real ones under other names, in three folders
src = [os.path.join(EX, "libraries", n) for n in ("gen_passive.TCLib", "Analog.TCLib", "DISCRETE.TCLib")]
if not all(os.path.exists(s) for s in src):
    print("Library manager checks skipped: need the example libraries in", EX); sys.exit(0)
lib = os.path.join(tmp, "libs"); os.makedirs(lib)
zz, mm, aa = [os.path.join(lib, n) for n in ("zz_lib.TCLib", "Mm_lib.TCLib", "aa_lib.TCLib")]
shutil.copy(src[0], zz); shutil.copy(src[1], mm); shutil.copy(src[2], aa)
junk = os.path.join(lib, "junk.TCLib"); open(junk, "w").write("this is not a database, not even close\n" * 40)
old = os.path.join(lib, "old.mdb"); shutil.copy(src[0], old)
gone = os.path.join(lib, "gone.TCLib")

# ---- 1. the dialog, Add, the sorted list, duplicates, files that are not libraries
o, rc, err = run("\n".join([
    "libraries add=%s add=%s add=%s add=%s add=%s add=%s" % (zz, aa, aa, junk, old, gone),
    "libraries add=%s|%s select=Mm_lib select=aa_lib select=nothing ok=1" % (mm, mm),
    "libregistry", "libtree", "libsettings", ""]), "add")
check("add: ran", rc == 0 and err.strip() == "", (rc, err[-600:]))
start = lines_of(o, "LIBRARIES")[0]
check("start: caption", "caption=Library Setup items=" in start, start)
check("start: nothing listed", items(start) == [] and field(start, "items") == "", start)
check("start: Add and New enabled, the rest dimmed", (field(start, "add"), field(start, "new"), field(start, "remove"), field(start, "cleanup"), field(start, "edit"), field(start, "upgrade")) == ("1", "1", "0", "0", "0", "0"), start)
check("start: OK alone", field(start, "ok") == "&OK" and field(start, "cancel") == "0", start)
check("start: Edit says why", "hint_edit=TRUE" in start, start)
steps = [l for l in lines_of(o, "LIBRARIES") if " items=" in l]
adds = [l for l in steps if l.startswith("add ")]
# add 1: zz (ok) -> then aa ok, aa again (no change), junk refused, old.mdb refused, gone refused
exp_items = [["zz_lib"], ["aa_lib", "zz_lib"], ["aa_lib", "zz_lib"], ["aa_lib", "zz_lib"], ["aa_lib", "zz_lib"], ["aa_lib", "zz_lib"], ["aa_lib", "Mm_lib", "zz_lib"]]
check("add: the list after each step is sorted by name, without copies", [items(l) for l in adds] == exp_items[:len(adds)] and len(adds) == 7, [items(l) for l in adds])
check("add: a library already in use is not added twice (panel count)", [field(l, "panel") for l in adds] == ["1", "2", "2", "2", "2", "2", "3"], [field(l, "panel") for l in adds])
check("add: a text file named .TCLib is refused with a message", "junk.TCLib" in field(adds[3], "status") and "Cannot open library" in field(adds[3], "status"), adds[3])
check("add: an .mdb file is refused with a message", "old.mdb" in field(adds[4], "status") and ".TCLib" in field(adds[4], "status"), adds[4])
check("add: a file that is not there is refused with a message", "gone.TCLib" in field(adds[5], "status"), adds[5])
check("add: a good file leaves no message", field(adds[0], "status") == "" and field(adds[1], "status") == "" and field(adds[6], "status") == "", [field(a, "status") for a in adds])
sel = [l for l in steps if l.startswith("select ")]
check("select: a library enables Remove and Cleanup, Edit and Upgrade stay dimmed",
      [(field(l, "sel"), field(l, "remove"), field(l, "cleanup"), field(l, "edit"), field(l, "upgrade")) for l in sel[:2]] == [("Mm_lib", "1", "1", "0", "0"), ("aa_lib", "1", "1", "0", "0")], sel)
check("select: the file of the selected library", field(sel[0], "file") == "Mm_lib.TCLib", sel[0])
check("select: a name that is not listed finds nothing", "found=0" in [l for l in lines_of(o, "LIBRARIES") if l.startswith("select found")][-1], lines_of(o, "LIBRARIES"))
tree = [l for l in lines_of(o, "LIBNODE") if l.startswith("0 ")]
check("panel: the libraries are in the order they were added", len(tree) == 3, tree)
names = [re.sub(r"^0 open=\d ", "", l) for l in tree]
check("panel: each library once", sorted(os.path.basename(n).lower() for n in names) == sorted(["zz_lib.tclib", "aa_lib.tclib", "mm_lib.tclib"]) or len(set(names)) == 3, names)
ks = libkeys("add")
check("registry: Library1.. in the order added, full paths", ks == [zz, aa, mm], ks)
check("registry: written as soon as the list changes (read back while the program runs)", [l.split(" ", 1)[1] for l in lines_of(o, "LIBREGISTRY") if l != "done"] == [zz, aa, mm], lines_of(o, "LIBREGISTRY"))
check("settings: the same list", [l.split(" ", 1)[1] for l in lines_of(o, "LIBSETTING")] == [zz, aa, mm], lines_of(o, "LIBSETTING"))

# ---- 2. the next run opens them again; a file that went and one that is no longer a library are left out
shutil.copy(junk, aa)                      # aa is a file that is no longer a library, gone.TCLib one that is not there at all
set_registry("add", "Library4", gone)
o, rc, err = run("librestore\nlibtree\nlibsettings\nlibraries select=Mm_lib ok=1\nlibsettings\n", "add")
check("restore: ran", rc == 0 and err.strip() == "", (rc, err[-400:]))
check("restore: opens those that are still libraries, in order", lines_of(o, "LIBRESTORE") == ["2"] and [re.sub(r"^0 open=\d ", "", l) for l in lines_of(o, "LIBNODE") if l.startswith("0 ")] == [n for n in names if "aa_lib" not in n], (lines_of(o, "LIBRESTORE"), lines_of(o, "LIBNODE")))
st = lines_of(o, "LIBRARIES")[0]
check("restore: the dialog lists them", items(st) == ["Mm_lib", "zz_lib"], st)
check("restore: restoring does not rewrite the saved list", len(lines_of(o, "LIBSETTING")) >= 3, lines_of(o, "LIBSETTING"))

# ---- 3. Remove: in use is refused, otherwise it goes from the list, the panel and the registry, the file stays
o, rc, err = run("\n".join([
    "librestore", "libraries inuse=%s select=zz_lib remove=1 inuse= remove=1 ok=1" % zz,
    "libraries select=Mm_lib remove=1 ok=1", "libtree", "libsettings", ""]), "add")
check("remove: ran", rc == 0 and err.strip() == "", (rc, err[-400:]))
L = [l for l in lines_of(o, "LIBRARIES") if " items=" in l and l.split(" ")[0] in ("select", "inuse", "remove")]
check("remove in use: TinyCAD's message, nothing changes", field(L[2], "status") == "Cannot delete a library while it is being edited or while you are creating a new symbol for it.  Close the editing windows and try again" and items(L[2]) == ["Mm_lib", "zz_lib"] and field(L[2], "panel") == "2", L[2])
check("remove in use: the library stays selected", field(L[2], "sel") == "zz_lib", L[2])
check("remove: it goes from the list and the panel", items(L[4]) == ["Mm_lib"] and field(L[4], "panel") == "1" and field(L[4], "status") == "", L[4])
check("remove: nothing is selected afterwards", field(L[4], "sel") == "" and field(L[4], "remove") == "0" and field(L[4], "cleanup") == "0", L[4])
check("remove: the file is kept", os.path.exists(zz) and os.path.exists(mm))
check("remove: the last one removed empties the list and the registry", items([l for l in lines_of(o, "LIBRARIES") if l.startswith("remove items")][-1]) == [] and libkeys("add") == [] and not lines_of(o, "LIBSETTING"), (libkeys("add"), lines_of(o, "LIBSETTING")))
check("remove: nothing open in the panel", "libs=0" in " ".join(lines_of(o, "LIBTREE")), lines_of(o, "LIBTREE"))

# ---- 4. New
newdir = os.path.join(tmp, "newlibs"); os.makedirs(newdir)
n1, n2, n3 = os.path.join(newdir, "fresh.mdb"), os.path.join(newdir, "second"), os.path.join(newdir, "third.tclib")
exists = os.path.join(newdir, "have.TCLib"); shutil.copy(src[0], exists); before = open(exists, "rb").read()
nodir = os.path.join(tmp, "no_such_dir", "x")
o, rc, err = run("libraries new=%s new=%s new=%s new=%s new=%s ok=1\nlibtree\n" % (n1, n2, n3, exists, nodir), "new")
check("new: ran", rc == 0 and err.strip() == "", (rc, err[-400:]))
N = [l for l in lines_of(o, "LIBRARIES") if l.startswith("new items")]
made = [field(l, "made") for l in lines_of(o, "LIBRARIES") if l.startswith("new made")]
check("new: three made, the existing and the unwritable refused", made == ["1", "1", "1", "0", "0"], made)
check("new: .TCLib put on the name (an other extension replaced, .tclib kept)",
      os.path.exists(os.path.join(newdir, "fresh.TCLib")) and not os.path.exists(n1) and os.path.exists(os.path.join(newdir, "second.TCLib")) and os.path.exists(n3), os.listdir(newdir))
check("new: added to the list (sorted) and the panel", items(N[2]) == ["fresh", "second", "third"] and field(N[2], "panel") == "3", N[2])
check("new: an existing file is not touched, and the message says so", open(exists, "rb").read() == before and "have" in field(N[3], "status") and "already" in field(N[3], "status"), N[3])
check("new: a folder that is not there gives a message", "Cannot create library" in field(N[4], "status") and not os.path.exists(os.path.dirname(nodir)), N[4])
check("new: the registry lists the new libraries", libkeys("new") == [os.path.join(newdir, x) for x in ("fresh.TCLib", "second.TCLib", "third.tclib")], libkeys("new"))
# the tables TinyCAD creates (LibrarySQLite.cpp), read from the C++ source when it is at hand
c = sqlite3.connect(os.path.join(newdir, "fresh.TCLib"))
tabs = {r[0]: [x[1:3] for x in c.execute("pragma table_info([%s])" % r[0])] for r in c.execute("select name from sqlite_master where type='table'")}
idx = [r[0] for r in c.execute("select name from sqlite_master where type='index'")]
want = {"Name": [("NameID", "INTEGER"), ("Name", "TEXT"), ("SymbolID", "INTEGER"), ("Type", "INTEGER"), ("Reference", "TEXT"), ("ppp", "INTEGER"), ("Description", "TEXT"), ("ShowName", "INTEGER"), ("ShowRef", "INTEGER"), ("DefRotate", "INTEGER")],
        "Symbol": [("SymbolID", "INTEGER"), ("Data", "TEXT")], "Attribute": [("AttributeID", "INTEGER"), ("NameID", "INTEGER"), ("AttName", "TEXT"), ("AttValue", "TEXT"), ("ShowAtt", "INTEGER")]}
check("new: the tables TinyCAD makes", tabs == want, tabs)
check("new: the index on Attribute.NameID", "idx_NameID" in idx, idx)
check("new: no symbols", c.execute("select count(*) from Name").fetchone()[0] == 0); c.close()
tcsrc = glob.glob("/tmp/tcsrc/TinyCAD-master/src/LibrarySQLite.cpp")
if tcsrc:
    cpp = open(tcsrc[0], encoding="utf-8", errors="replace").read()
    cols = re.findall(r"\[(\w+)\] (INTEGER|TEXT)", cpp.split("CREATE TABLE [Name]")[1].split("execDML")[0])
    check("new: Name's columns are TinyCAD's own", [tuple(x) for x in cols] == want["Name"], cols)

# ---- 5. Cleanup: the file shrinks after rows were deleted, the symbols stay, in use is refused
big = os.path.join(tmp, "big.TCLib"); shutil.copy(os.path.join(EX, "libraries", "symbols.TCLib") if os.path.exists(os.path.join(EX, "libraries", "symbols.TCLib")) else src[0], big)
c = sqlite3.connect(big); c.execute("create table if not exists pad(x text)"); c.executemany("insert into pad values(?)", [("x" * 2000,)] * 3000); c.commit()
c.execute("drop table pad"); c.commit(); c.close()
grown = os.path.getsize(big); rows_before = symbols(big)
o, rc, err = run("libraries add=%s select=big inuse=%s cleanup=1 inuse= cleanup=1 ok=1\n" % (big, big), "clean")
check("cleanup: ran", rc == 0 and err.strip() == "", (rc, err[-400:]))
C = [l for l in lines_of(o, "LIBRARIES") if l.startswith("cleanup items")]
check("cleanup: refused in use with TinyCAD's message, the file untouched", field(C[0], "status") == "Cannot cleanup a library while it is being edited or while you are creating a new symbol for it.  Close the editing windows and try again", C[0])
shrunk = os.path.getsize(big)
check("cleanup: the file is smaller than before", shrunk < grown * 0.5, (grown, shrunk))
check("cleanup: the symbols are the same", symbols(big) == rows_before)
check("cleanup: no message and the selection stays", field(C[1], "status") == "" and field(C[1], "sel") == "big", C[1])
big2 = os.path.join(tmp, "big2.TCLib"); shutil.copy(big, big2)
c = sqlite3.connect(big2); c.execute("create table pad(x text)"); c.executemany("insert into pad values(?)", [("x" * 2000,)] * 3000); c.commit(); c.execute("drop table pad"); c.commit(); c.close()
grown2 = os.path.getsize(big2)
o, rc, err = run("libraries add=%s select=big2 inuse=%s cleanup=1 ok=1\n" % (big2, big2), "clean2")
check("cleanup in use: the file is not changed", os.path.getsize(big2) == grown2, (grown2, os.path.getsize(big2)))

# ---- 6. the menu
o, rc, err = run("menuselect mLibraries\nmenuselect mOpenLibs\n", "menu")
M = [l for l in o if l.startswith("MENUSELECT")]
check("menu: Libraries... has a hint shown in the status bar", len(M) == 2 and "hint=Add, remove and make the symbol libraries in use" in M[0] and "panel0=Add, remove and make the symbol libraries in use" in M[0] and "enabled=1" in M[0], M)

print("Library manager checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
