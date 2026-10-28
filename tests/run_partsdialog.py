"""The Special > Create Parts List dialog and command, on the real program (a script fills the dialog in and presses Export, or Cancel). What the program wrote is
compared with the parts list that TinyCAD's BOMGenerator would make (tests/bomoracle.py, a separate statement of its rules):
  - the menu: a Special menu with Create Parts List, usable only while a design is open
  - the dialog's start: the design's file name with .txt, or output.txt for a design with none; the format list (text, CSV, spreadsheet CSV); the four choices off; the
    button reading Export
  - choosing a format changes the extension of the name (.txt, .csv) only when the name has a dot, and only the part after the last dot
  - Export writes the list for the sheet shown or for all sheets, with or without the attributes, in each format; a text list is headed with the design's file name
  - the choices are kept between runs (the registry values TinyCAD uses), also when the file could not be written, but not when Cancel is pressed; Cancel writes nothing
  - a file that cannot be written (an empty name, a folder that is not there) gives TinyCAD's message and leaves nothing behind; symbols still on the reference they were
    defined with (R?) give the "references are not correct" warning but the list is still written; a good design gives no message
  - the sheet-number prefix is kept but changes nothing in the list; the hierarchical choice only matters with placed designs (tests/run_hierbom.py)
Needs the built program."""
import glob, os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from bomoracle import read_design, build, write
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Parts list dialog checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
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
    return [kv(l[len("PARTSLIST " + kind):]) for l in lines if l.startswith("PARTSLIST " + kind + " ") or l.startswith("PARTSLIST " + kind + "=")]
def registry(home):
    f = glob.glob(os.path.join(tmp, "home_" + home, ".config", "*", "reg.xml"))
    if not f: return {}
    node = ET.parse(f[0]).getroot()
    for part in ("HKEY_CURRENT_USER", "SOFTWARE", "HPL Software", "TyCAD Electrical"):
        node = next(k for k in node.findall("Key") if k.get("Name") == part)
    return {v.get("Name"): v.text for v in node.findall("Value")}

work = os.path.join(tmp, "work"); os.makedirs(work)
def copy_sample(name, to=None):
    src = next(p for p in sorted(os.path.join(dp, f) for dp, _, fs in os.walk(EX) for f in fs) if os.path.basename(p) == name)
    dst = os.path.join(work, to or name); shutil.copy(src, dst); return dst

# ---------- the menu ----------
focus = copy_sample("Focus Bipolar Motor Circuit.dsn", "Focus.dsn")
o, rc, err = run(f'partsmenu\nopen "{focus}"\npartsmenu\n', "menu")
pm = [kv(l[len("PARTSMENU "):]) for l in o if l.startswith("PARTSMENU")]
check("the program starts", rc == 0 and not any(l.startswith("ERROR") for l in o), err[-200:])
check("a Special menu holds Create Parts List..., usable only with a design open",
      len(pm) == 2 and pm[0]["menu"] == "S&pecial" and pm[0]["item"] == "Create &Parts List..." and pm[0]["enabled"] == "0" and pm[1]["enabled"] == "1", str(pm))

# ---------- the start of the dialog, and the format changing the extension ----------
o, rc, err = run(f'open "{focus}"\npartslist cancel=1\npartslist type=1 cancel=1\npartslist type=2 cancel=1\npartslist type=0 cancel=1\npartslist type=1 file=none cancel=1\n', "start")
st = parts(o, "start"); ex = parts(o, "export")
check("the dialog starts with the design's name and .txt, text format, the four choices off and an Export button",
      st[0] == dict(type="0", file=os.path.join(work, "Focus.txt"), sheets="0", attrs="0", prefix="0", hier="0", button="&Export"), str(st[0]))
check("choosing CSV or the spreadsheet format gives .csv, and back to text gives .txt again", [e["file"] for e in ex[1:4]] == [os.path.join(work, "Focus.csv")] * 2 + [os.path.join(work, "Focus.txt")], str([e["file"] for e in ex]))
check("an empty name stays empty when the format changes (nothing after a dot to replace)", ex[4]["file"] == "" or ex[4]["file"] == '""', str(ex[4]))
o, rc, err = run('newdoc A4\npartslist cancel=1\npartslist file=noext type=1 cancel=1\npartslist file=a.b.c type=2 cancel=1\n', "start2")
st = parts(o, "start"); ex = parts(o, "export")
check("a design with no file proposes output.txt", st[0]["file"] == "output.txt", str(st[0]))
check("a name without a dot is not changed; with several dots only the last part is", ex[1]["file"] == "noext" and ex[2]["file"] == "a.b.csv", str(ex))
check("no file is written when only looking", not os.path.exists(os.path.join(work, "Focus.txt")))

# ---------- exporting, every format and choice ----------
sheets = read_design(focus)
n = 0
for t in (0, 1, 2):
    for allsheets in (0, 1):
        for attrs in (0, 1):
            out = os.path.join(work, f"out_{t}{allsheets}{attrs}.dat")
            o, rc, err = run(f'open "{focus}"\npartslist type={t} file={out} sheets={allsheets} attrs={attrs}\n', "exp")
            w = parts(o, "wrote") if False else [l for l in o if l.startswith("PARTSLIST wrote=")]
            h, e = build(sheets, bool(allsheets), bool(attrs), 0, t)
            want, wmiss = write(h, e, t, focus)
            got = open(out, "rb").read().decode("utf-8") if os.path.exists(out) else None
            check(f"export type {t} sheets {allsheets} attrs {attrs} is the list TinyCAD makes", got == want and w and w[0].startswith("PARTSLIST wrote=1"), (w, (got or "")[:120], want[:120]))
            n += 1
check("a text list is headed with the design's file name", (got is not None) and n == 12)
txt = open(os.path.join(work, "out_000.dat"), encoding="utf-8").read()
check("the heading line", txt.startswith("====+  Parts List for " + focus + "  +====\n\n"), txt[:120])
check("lines end with a line feed here (the platform's line end)", "\r" not in txt)

# a design with several sheets: the sheet shown, or all of them
multi = os.path.join(work, "multi.dsn")
o, rc, err = run(f'open "{focus}"\naddsheet\nsave "{multi}"\n', "multi")
ms = read_design(multi)
check("the test design has two sheets, the second empty", len(ms) == 2 and ms[1] == [], len(ms))
o2 = os.path.join(work, "ms2.txt")
run(f'open "{multi}"\ngosheet 1\npartslist file={o2} sheets=0\n', "multi")
h, e = build(ms, False, False, 1, 0)
check("only the sheet being shown is listed (an empty sheet gives only the heading)", open(o2, encoding="utf-8").read() == write(h, e, 0, multi)[0] and e == [], open(o2, encoding="utf-8").read()[:100])
o3 = os.path.join(work, "ms3.txt")
run(f'open "{multi}"\ngosheet 1\npartslist file={o3} sheets=1\n', "multi")
h, e = build(ms, True, False, 1, 0)
check("with all sheets, the parts of every sheet are listed whichever is shown", open(o3, encoding="utf-8").read() == write(h, e, 0, multi)[0] and len(e) > 0)
# the sheet-number prefix changes nothing, nor does the hierarchical choice for a design with no placed designs
a = os.path.join(work, "pa.txt"); b = os.path.join(work, "pb.txt")
run(f'open "{focus}"\npartslist file={a} prefix=0 hier=0 attrs=1\n', "pfx")
run(f'open "{focus}"\npartslist file={b} prefix=1 hier=1 attrs=1\n', "pfx")
check("the sheet-number prefix and, with no placed designs, the hierarchical choice do not change the list (as TinyCAD's prefix never did)", open(a, "rb").read() == open(b, "rb").read())

# ---------- remembered choices ----------
o, rc, err = run(f'open "{focus}"\npartslist type=2 file={work}/r1.csv sheets=1 attrs=1 prefix=1 hier=1\n', "keep")
reg = registry("keep")
check("Export keeps the choices in the registry under TinyCAD's value names",
      {k: reg.get(k) for k in ("BOMNetlist", "BOMAllSheets", "BOMAllAttrs", "BOMPrefixNetlist", "BOMHierarchical")} == dict(BOMNetlist="2", BOMAllSheets="1", BOMAllAttrs="1", BOMPrefixNetlist="1", BOMHierarchical="1"), str(reg))
o, rc, err = run(f'open "{focus}"\npartslist cancel=1\n', "keep")
st = parts(o, "start")[0]
check("the next run starts with them, and the name takes the extension of the remembered format",
      (st["type"], st["sheets"], st["attrs"], st["prefix"], st["hier"], st["file"]) == ("2", "1", "1", "1", "1", os.path.join(work, "Focus.csv")), str(st))
o, rc, err = run(f'open "{focus}"\npartslist type=0 sheets=0 attrs=0 prefix=0 hier=0 file={work}/never.txt cancel=1\n', "keep")
reg = registry("keep")
check("Cancel keeps nothing and writes nothing", reg.get("BOMNetlist") == "2" and reg.get("BOMAllSheets") == "1" and not os.path.exists(os.path.join(work, "never.txt")), str(reg))
o, rc, err = run(f'open "{focus}"\npartslist type=1 attrs=0 sheets=0 prefix=0 hier=0 file={work}/nodir/none.csv\n', "keep")
reg = registry("keep")
check("choices are kept even when the file cannot be written", reg.get("BOMNetlist") == "1" and reg.get("BOMAllAttrs") == "0" and reg.get("BOMAllSheets") == "0", str(reg))

# ---------- failures and the warning ----------
MSG_CANT = "Cannot write the parts list file.  Please try again with a different filename."
MSG_MISS = "Some symbols do not have correct references, the parts list will be inaccurate.  Use Generate Symbol references."
o, rc, err = run(f'open "{focus}"\npartslist file=none\npartslist file={work}/nodir/x.txt\npartslist file={work}/ok.txt\n', "fail")
w = [kv(l[len("PARTSLIST "):]) for l in o if l.startswith("PARTSLIST wrote=")]
raw = [l for l in o if l.startswith("PARTSLIST wrote=")]
check("an empty name and a missing folder give TinyCAD's message and write nothing",
      [x.split("status=", 1)[1] for x in raw[:2]] == [MSG_CANT, MSG_CANT] and raw[0].startswith("PARTSLIST wrote=0") and raw[1].startswith("PARTSLIST wrote=0") and not os.path.exists(os.path.join(work, "nodir")), raw)
check("a good design gives no message", raw[2] == "PARTSLIST wrote=1 status=", raw[2])
# a design with a symbol on its own reference
bad = os.path.join(work, "bad.dsn")
src = open(focus, encoding="utf-8").read()
m = re.search(r"<FIELD type='0' description='Ref' value='(R39)'", src)
check("the test design has the reference to spoil", m is not None)
open(bad, "w", encoding="utf-8").write(src.replace("description='Ref' value='R39'", "description='Ref' value='R?'", 1))
defref = re.findall(r"<REF type='0'>(\S*?)</REF>", src)
o, rc, err = run(f'open "{bad}"\npartslist file={work}/bad.txt\n', "warn")
raw = [l for l in o if l.startswith("PARTSLIST wrote=")]
bs = read_design(bad); h, e = build(bs, False, False, 0, 0); want, wmiss = write(h, e, 0, bad)
check("a symbol still on the reference it was defined with gives the warning", wmiss and raw and raw[0] == "PARTSLIST wrote=1 status=" + MSG_MISS, (wmiss, raw))
check("... and the list is still written, as TinyCAD does", os.path.exists(f"{work}/bad.txt") and open(f"{work}/bad.txt", encoding="utf-8").read() == want)

print(f"{checks} checks, {len(fails)} failed")
sys.exit(1 if fails else 0)
