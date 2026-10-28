"""Special > Create Spice Net List and Create VHDL file on the real program: a script answers the Save dialog (a file name, or Cancel). What is written is compared with the
files TinyCAD's writers would make (tests/spiceoracle.py, a separate statement of NetList.cpp):
  - the menu: both items in the Special menu after the parts list and its separator, usable only while a design is open
  - the name each dialog proposes: the design's name with .net (SPICE) or .vhd (VHDL), output.net / output.vhd for a design with no file
  - SPICE writes the netlist and, beside it under the netlist's name with .txt, the list of the problems found; the first line carries the date; a message says how many problems
    (one, several, and none: no message), and where they are listed
  - VHDL writes the file, the entity named after the file it is written to
  - Cancel writes nothing
  - a file that cannot be written (empty name, missing folder) gives a message and leaves nothing behind; for SPICE, an error file that cannot be written leaves the netlist
Needs the built program and netwtest/nettest."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from bomoracle import read_design
from netoracle import read_nets
import spiceoracle as O
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Spice/VHDL dialog checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:600])
def run(script, home="h", timeout=120):
    h = os.path.join(tmp, "home_" + home); os.makedirs(h, exist_ok=True)
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n"), r.returncode, r.stderr
def kv(line):
    return {m.group(1): m.group(2) for m in re.finditer(r"(\w+)=(.*?)(?= \w+=|$)", line)}
def lines(o, prefix): return [l[len(prefix):] for l in o if l.startswith(prefix)]
def read(p): return open(p, "rb").read().decode("utf-8") if os.path.exists(p) else None
work = os.path.join(tmp, "work"); os.makedirs(work)
src = next(p for p in sorted(os.path.join(dp, f) for dp, _, fs in os.walk(EX) for f in fs) if os.path.basename(p) == "Focus Bipolar Motor Circuit.dsn")
focus = os.path.join(work, "Focus.dsn"); shutil.copy(src, focus)
MSG = "Cannot write the net list file.  Please try again with a different filename."

# ---------- the menu ----------
o, rc, err = run(f'partsmenu\nopen "{focus}"\npartsmenu\n')
pm = [kv(l[len("PARTSMENU "):]) for l in o if l.startswith("PARTSMENU")]
check("the program starts", rc == 0 and not any(l.startswith("ERROR") for l in o), err[-200:])
check("the Spice and VHDL items follow the parts list (after the two design rule checks), separated as in TinyCAD, and need a design", len(pm) == 2 and pm[0]["spice"] == "Create Spice Net List..." and pm[0]["vhdl"] == "Create &VHDL file"
      and pm[0]["spiceenabled"] == "0" and pm[0]["vhdlenabled"] == "0" and pm[1]["spiceenabled"] == "1" and pm[1]["vhdlenabled"] == "1"
      and (pm[1]["netindex"], pm[1]["partsindex"], pm[1]["spiceindex"], pm[1]["vhdlindex"]) == ("0", "4", "6", "8"), str(pm))

# ---------- the proposed names ----------
o, rc, err = run(f'open "{focus}"\nspice cancel=1\nvhdl cancel=1\nnewdoc A4\nspice cancel=1\nvhdl cancel=1\n')
check("the dialogs propose the design's name with .net and .vhd, and output.net and output.vhd for a design with no file",
      lines(o, "SPICE start file=") == [os.path.join(work, "Focus.net"), "output.net"] and lines(o, "VHDL start file=") == [os.path.join(work, "Focus.vhd"), "output.vhd"],
      (lines(o, "SPICE start file="), lines(o, "VHDL start file=")))

# ---------- SPICE ----------
sheets = read_design(focus); nets = read_nets(focus); syms = O.read_syms(focus)
out = os.path.join(work, "Out.net")
o, rc, err = run(f'open "{focus}"\nspice file={out}\n')
w = lines(o, "SPICE wrote=")
text, errtext, n = O.spice(sheets, nets, focus, "S")
got = read(out); gerr = read(os.path.join(work, "Out.txt"))
check("the netlist is the one TinyCAD makes, with the date in the first line", got is not None and re.fullmatch(r"\* Schematics Netlist created on \d\d/\d\d/\d\d at \d\d:\d\d:\d\d [+-]\d{4} \*", got.split("\n")[0])
      and got.split("\n", 1)[1] == text.split("\n", 1)[1], (got or "")[:200])
check("the error file is beside it under the name with .txt and holds the design's name and the problems", gerr == errtext, (gerr or "")[:200])
check("a message says how many problems were found and where they are listed", w == [f"1 status={n} errors were found while making the Spice net list.  They are listed in {os.path.join(work, 'Out.txt')}"], (w, n))
check("there are many problems on this circuit", n > 5, n)
# one problem, none
txt = open(focus, encoding="utf-8", errors="replace").read()
m = re.search(r"<SYMBOL id='(\d+)'[^>]*>(?:(?!</SYMBOL>).)*?value='1 Pin Connector'.*?</SYMBOL>\n", txt, re.S)
syms_all = list(re.finditer(r"<SYMBOL id='[^']*'[^>]*>.*?</SYMBOL>\n", txt, re.S))
first = next(x for x in syms_all if "value='1 Pin Connector'" in x.group(0))
body = txt
for x in reversed(syms_all):
    if x.start() != first.start(): body = body[:x.start()] + body[x.end():]
body = body.replace("</SYMBOL>", "<FIELD type='2' description='$$SPICE' value='J%(1) $(Name)' show='0' pos='0,0'/>\n</SYMBOL>", 1)
def pin_text(b, name):
    return re.sub(r"(<PIN [^>]*number=')1('[^>]*>)[^<]*</PIN>", lambda m: m.group(1) + "1" + m.group(2) + name + "</PIN>", b)
one = os.path.join(work, "one.dsn"); open(one, "w", encoding="utf-8").write(pin_text(body, ""))
none_ = os.path.join(work, "none.dsn"); open(none_, "w", encoding="utf-8").write(pin_text(body, "P"))
for dsn, label in ((one, "one"), (none_, "none")):
    sh = read_design(dsn); ne = read_nets(dsn); t, e, k = O.spice(sh, ne, dsn, "S")
    check(f"the {label}-problem design really has {label} problems", k == (1 if label == "one" else 0), k)
o, rc, err = run(f'open "{one}"\nspice file={work}/one.net\nopen "{none_}"\nspice file={work}/none.net\n', "msgs")
w = lines(o, "SPICE wrote=")
check("one problem: the message is in the singular", w[0] == f"1 status=1 error was found while making the Spice net list.  It is listed in {work}/one.txt", w)
check("no problems: no message, and the error file still says so", w[1] == "1 status=" and read(f"{work}/none.txt") == f"Results of Spice netlist generation for {none_}\n\n\n0 errors found\n", (w, read(f"{work}/none.txt")))
check("the one problem is in its error file", read(f"{work}/one.txt").endswith("blank pin name.  Pin number = \"1\"\n\n1 error found\n"), read(f"{work}/one.txt"))
# cancel and failures
o, rc, err = run(f'open "{focus}"\nspice file={work}/never.net cancel=1\nvhdl file={work}/never.vhd cancel=1\n', "c")
check("Cancel writes nothing", not os.path.exists(f"{work}/never.net") and not os.path.exists(f"{work}/never.txt") and not os.path.exists(f"{work}/never.vhd") and not any("wrote" in l for l in o), o)
os.makedirs(f"{work}/e.txt")
o, rc, err = run(f'open "{focus}"\nspice file=none\nspice file={work}/nodir/x.net\nspice file={work}/e.net\nvhdl file=none\nvhdl file={work}/nodir/x.vhd\n', "f")
sp = lines(o, "SPICE wrote="); vh = lines(o, "VHDL wrote=")
check("an empty name and a missing folder give a message and write nothing; a good netlist whose error file cannot be written gives the message and leaves the netlist",
      sp == [f"0 status={MSG}"] * 3 and vh == [f"0 status={MSG}"] * 2 and not os.path.exists(f"{work}/nodir") and os.path.exists(f"{work}/e.net"), (sp, vh))

# ---------- VHDL ----------
nib = None
for r_, _, fs in os.walk(EX):
    if "Adder4.dsn" in fs: nib = os.path.join(r_, "Adder4.dsn")
for dsn in (nib, focus):
    sh = read_design(dsn); ne = read_nets(dsn); sy = O.read_syms(dsn)
    for name in ("Some_Entity.vhd", "e.v2.vhd"):
        outv = os.path.join(work, name)
        if os.path.exists(outv): os.remove(outv)
        o, rc, err = run(f'open "{dsn}"\nvhdl file={outv}\n', "v")
        w = lines(o, "VHDL wrote=")
        check(f"VHDL for {os.path.basename(dsn)} written to {name} is the file TinyCAD makes, the entity named after the file", w == ["1 status="] and read(outv) == O.vhdl(sh, ne, sy, outv), (w, (read(outv) or "")[:200]))
check("the entity takes the name of the file written to", "entity e.v2 is" in read(os.path.join(work, "e.v2.vhd")) and "entity Some_Entity is" in read(os.path.join(work, "Some_Entity.vhd")))

print(f"{checks} checks, {len(fails)} failed")
sys.exit(1 if fails else 0)
