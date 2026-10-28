"""Special > Create PCB Net List (TinyCAD's PCB Export dialog) on the real program: a script fills the dialog in and presses Export or Cancel. What is written is compared
with the netlist TinyCAD's writers would make (tests/netoracle.py, a separate statement of NetList.cpp):
  - the menu: Create PCB Net List... first in the Special menu, usable only while a design is open
  - the dialog's start: seven formats (TinyCAD, PADS-PCB, PADS-PCB-WITH-VALUE, Eagle SCR, Protel, gEDA PCB, XML), the design's name with .net (output.net for a design with
    no file), TinyCAD's format, the prefix choice off, an Export button
  - choosing a format changes the extension: .net, .scr for Eagle, .net.xml for XML; a .net before the last dot goes first (x.net.xml -> x.scr); only a name with a dot changes
  - Export writes the file of the chosen format, equal to the oracle's, for each of the seven formats
  - the format and the prefix are kept between runs (TinyCAD's registry values Netlist and PrefixNetlist), also when the file could not be written, but not by Cancel;
    Cancel writes nothing; the prefix changes nothing in the file
  - a file that cannot be written (empty name, missing folder) gives a message and leaves nothing behind
Needs the built program."""
import glob, os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from bomoracle import read_design
from netoracle import read_nets, parts_of, oracle
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Netlist dialog checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:420])
def run(script, home, timeout=120):
    h = os.path.join(tmp, "home_" + home); os.makedirs(h, exist_ok=True)
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n"), r.returncode, r.stderr
def kv(line):
    out = {}
    for m in re.finditer(r"(\w+)=(.*?)(?= \w+=|$)", line): out[m.group(1)] = m.group(2)
    return out
def parts(lines, kind):
    return [kv(l[len("NETLIST " + kind):]) for l in lines if l.startswith("NETLIST " + kind + " ")]
def registry(home):
    f = glob.glob(os.path.join(tmp, "home_" + home, ".config", "*", "reg.xml"))
    if not f: return {}
    node = ET.parse(f[0]).getroot()
    for part in ("HKEY_CURRENT_USER", "SOFTWARE", "HPL Software", "TyCAD Electrical"):
        node = next(k for k in node.findall("Key") if k.get("Name") == part)
    return {v.get("Name"): v.text for v in node.findall("Value")}
work = os.path.join(tmp, "work"); os.makedirs(work)
src = next(p for p in sorted(os.path.join(dp, f) for dp, _, fs in os.walk(EX) for f in fs) if os.path.basename(p) == "Focus Bipolar Motor Circuit.dsn")
focus = os.path.join(work, "Focus.dsn"); shutil.copy(src, focus)

# ---------- the menu ----------
o, rc, err = run(f'partsmenu\nopen "{focus}"\npartsmenu\n', "menu")
pm = [kv(l[len("PARTSMENU "):]) for l in o if l.startswith("PARTSMENU")]
check("the program starts", rc == 0 and not any(l.startswith("ERROR") for l in o), err[-200:])
check("Create PCB Net List... is in the Special menu above Create Parts List, usable only with a design open",
      len(pm) == 2 and pm[0]["net"] == "Create PCB &Net List..." and pm[0]["netenabled"] == "0" and pm[1]["netenabled"] == "1" and pm[1]["netindex"] == "0" and int(pm[1]["index"]) > 0, str(pm))

# ---------- the start of the dialog, and the extensions ----------
o, rc, err = run(f'open "{focus}"\nnetlist cancel=1\nnetlist type=3 cancel=1\nnetlist type=6 cancel=1\nnetlist file=a.net.xml type=3 cancel=1\nnetlist file=abcd.net type=6 cancel=1\nnetlist file=none type=1 cancel=1\n', "start")
st = parts(o, "start"); ex = parts(o, "export")
check("the dialog starts with the design's name and .net, TinyCAD's format, the prefix off and an Export button, and seven formats",
      st[0] == dict(type="0", file=os.path.join(work, "Focus.net"), prefix="0", button="&Export", formats="7"), str(st[0]))
check("Eagle gives .scr, XML gives .net.xml", [e["file"] for e in ex[1:3]] == [os.path.join(work, "Focus.scr"), os.path.join(work, "Focus.net.xml")], str(ex[1:3]))
check("a .net before the last dot goes first (a.net.xml -> a.scr); a four character name before .net is kept", ex[3]["file"] == "a.scr" and ex[4]["file"] == "abcd.net.xml", str(ex[3:5]))
check("an empty name stays empty", ex[5]["file"] == "", str(ex[5]))
o, rc, err = run('newdoc A4\nnetlist cancel=1\nnetlist file=noext type=5 cancel=1\n', "start2")
st = parts(o, "start"); ex = parts(o, "export")
check("a design with no file proposes output.net; a name without a dot is left alone", st[0]["file"] == "output.net" and ex[1]["file"] == "noext", str((st[0], ex[1])))

# ---------- exporting each format ----------
sheets = read_design(focus); nets = read_nets(focus); pl = parts_of(sheets)
names = ["TinyCAD", "PADS-PCB", "PADS-PCB-WITH-VALUE", "Eagle SCR", "Protel", "gEDA PCB", "XML"]
for t in range(7):
    out = os.path.join(work, f"out{t}.dat")
    o, rc, err = run(f'open "{focus}"\nnetlist type={t} file={out}\n', "exp")
    w = [l for l in o if l.startswith("NETLIST wrote=")]
    got = open(out, "rb").read().decode("utf-8") if os.path.exists(out) else None
    check(f"export {names[t]} is the netlist TinyCAD makes", got == oracle(t, pl, nets, focus) and w and w[0] == "NETLIST wrote=1 status=", (w, (got or "")[:100]))
tiny = open(os.path.join(work, "out0.dat"), encoding="utf-8").read()
check("the TinyCAD format is headed with the design's file name", tiny.startswith("; ====+  Net List for " + focus + "  +===="), tiny[:100])
check("no carriage returns on this platform", all("\r" not in open(os.path.join(work, f"out{t}.dat"), encoding="utf-8").read() for t in range(7)))
# the prefix choice changes nothing
a = os.path.join(work, "pa.net"); b = os.path.join(work, "pb.net")
run(f'open "{focus}"\nnetlist type=1 file={a} prefix=0\n', "pfx"); run(f'open "{focus}"\nnetlist type=1 file={b} prefix=1\n', "pfx")
check("the sheet-number prefix does not change the netlist (TinyCAD's writers no longer use it)", open(a, "rb").read() == open(b, "rb").read())

# ---------- remembered choices ----------
o, rc, err = run(f'open "{focus}"\nnetlist type=6 file={work}/r1.xml prefix=1\n', "keep")
reg = registry("keep")
check("Export keeps the format and prefix in the registry under TinyCAD's names Netlist and PrefixNetlist", (reg.get("Netlist"), reg.get("PrefixNetlist")) == ("6", "1"), str(reg))
o, rc, err = run(f'open "{focus}"\nnetlist cancel=1\n', "keep")
st = parts(o, "start")[0]
check("the next run starts with them, and the file name has the extension of the remembered format", (st["type"], st["prefix"], st["file"]) == ("6", "1", os.path.join(work, "Focus.net.xml")), str(st))
o, rc, err = run(f'open "{focus}"\nnetlist type=3 prefix=0 file={work}/never.scr cancel=1\n', "keep")
reg = registry("keep")
check("Cancel keeps nothing and writes nothing", (reg.get("Netlist"), reg.get("PrefixNetlist")) == ("6", "1") and not os.path.exists(os.path.join(work, "never.scr")), str(reg))
o, rc, err = run(f'open "{focus}"\nnetlist type=3 prefix=0 file={work}/nodir/x.scr\n', "keep")
reg = registry("keep")
check("the choices are kept even when the file cannot be written", (reg.get("Netlist"), reg.get("PrefixNetlist")) == ("3", "0"), str(reg))

# ---------- failures ----------
MSG = "Cannot write the net list file.  Please try again with a different filename."
o, rc, err = run(f'open "{focus}"\nnetlist file=none\nnetlist file={work}/nodir/x.net\nnetlist file={work}/ok.net\n', "fail")
raw = [l for l in o if l.startswith("NETLIST wrote=")]
check("an empty name and a missing folder give a message and write nothing", raw[0] == "NETLIST wrote=0 status=" + MSG and raw[1] == "NETLIST wrote=0 status=" + MSG and not os.path.exists(os.path.join(work, "nodir")), raw)
check("a good file gives no message", raw[2] == "NETLIST wrote=1 status=", raw[2])

print(f"{checks} checks, {len(fails)} failed")
sys.exit(1 if fails else 0)
