"""Special > Check Design Rules and V&HDL Check Design Rules on the real program (the options dialog, the Design Markers window, the markers on the sheets), with
the check's own results compared with ercoracle.py (a separate statement of Net.cpp):
  - the menu: Create PCB Net List..., Check Design Rules..., V&HDL Check Design Rules..., Create Parts List... in TinyCAD's order, usable only with a design open
  - the dialog: TinyCAD's title, group names and eleven box captions in its order, all on to begin with, a Check button; the choices are kept as the registry WORD
    "ERC" when Check is pressed and not when Cancel is; the bits above the eleventh are ignored
  - the result: the lines of the window and the markers on the sheets equal the oracle's for several designs, option words and both checks; a design with no errors
    shows "No errors were found in this design."; running the check again does not stack markers
  - the checks the netlist, Spice and VHDL commands run first: the window opens only when there are errors, the VHDL command runs the VHDL check, a clean design
    leaves the window closed (and closes one that was open)
  - choosing a line: the document and the sheet it is on are shown, the marker is selected, brought to the front and in the middle of the window; clicking a
    marker on the sheet chooses its line; the "No errors" line chooses nothing
  - Re-check runs the plain check again (also after the VHDL check), Close and the closing of the document take the markers away, the markers are never
    saved and do not mark the design as changed
Needs the built program and xvfb."""
import glob, os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import ercoracle as eo
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Design rules check dialog checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:700])
def run(script, home, timeout=200):
    h = os.path.join(tmp, "home_" + home); os.makedirs(h, exist_ok=True)
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n"), r.returncode, r.stderr
def kv(line):
    out = {}
    for m in re.finditer(r"(\w+)=(.*?)(?= \w+=|$)", line): out[m.group(1)] = m.group(2)
    return out
def lines_of(o, tag): return [l[len(tag) + 1:] for l in o if l.startswith(tag + " ") or l == tag]
def registry(home):
    f = glob.glob(os.path.join(tmp, "home_" + home, ".config", "*", "reg.xml"))
    if not f: return {}
    node = ET.parse(f[0]).getroot()
    for part in ("HKEY_CURRENT_USER", "SOFTWARE", "HPL Software", "TyCAD Electrical"):
        node = next(k for k in node.findall("Key") if k.get("Name") == part)
    return {v.get("Name"): v.text for v in node.findall("Value")}
def set_registry(home, name, value):
    f = glob.glob(os.path.join(tmp, "home_" + home, ".config", "*", "reg.xml"))[0]
    tree = ET.parse(f); node = tree.getroot()
    for part in ("HKEY_CURRENT_USER", "SOFTWARE", "HPL Software", "TyCAD Electrical"):
        node = next(k for k in node.findall("Key") if k.get("Name") == part)
    for v in node.findall("Value"):
        if v.get("Name") == name: v.text = str(value); break
    else:
        e = ET.SubElement(node, "Value", dict(Name=name)); e.text = str(value)
    tree.write(f)
def raw_markers(line):
    return [(int(m.group(1)), int(m.group(2)), m.group(3), m.group(4)) for m in re.finditer(r"(\d+):(\d+):([^:;]+):([^:;]+);", line)]
def parse_markers(line):
    marks = []
    for m in re.finditer(r"(\d+):(\d+):([^:;]+):([^:;]+);", line): marks.append((int(m.group(1)), int(m.group(2)), m.group(3), m.group(4)))
    return sorted(marks, key=lambda t: t[1]), kv(re.sub(r"^.*?; ?", "", line) if ";" in line else line)
def window(line):
    d = kv(line.split(" lines=")[0]); body = line.split(" lines=", 1)[1] if " lines=" in line else ""
    d["lines"] = body.split("|")[:-1] if body else []
    return d
def expected(path, word, vhdl, always=True):
    nets = eo.read_nodes(path); names, placed = eo.read_placed(path)
    msgs, marks = eo.erc(nets, placed, names, word & 0x7FF, vhdl, always)
    return [m.rstrip("\n\r") for m in msgs], [(m[1] - 1, m[0], eo.g(m[2] / 5), eo.g(m[3] / 5)) for m in marks]

work = os.path.join(tmp, "work"); os.makedirs(work)
focus = os.path.join(work, "Focus.dsn")
shutil.copy(next(p for p in sorted(os.path.join(dp, f) for dp, _, fs in os.walk(EX) for f in fs) if os.path.basename(p) == "Focus Bipolar Motor Circuit.dsn"), focus)
nib = os.path.join(EX, "vhdl", "nibbles")
# designs with errors: changed copies of the nibbles and of a circuit, one with two sheets
designs = []
for i, (src, seed) in enumerate([("UALogic4.dsn", 3), ("NOR4Bus.dsn", 1), ("ArithmeticUnit.dsn", 2), ("MUX2to1_4.dsn", 5), ("Shifter.dsn", 7), ("FullAdder.dsn", 4)]):
    d = os.path.join(work, f"v{i}.dsn"); eo.variant(os.path.join(nib, src), seed, d); designs.append(d)
two = os.path.join(work, "two.dsn"); eo.two_sheets(designs[0], two)
mixed = designs[0]       # plain and VHDL checks differ here
nm, nk = expected(mixed, 0xFFFF, False); vm, vk = expected(mixed, 0xFFFF, True)
check("the main test design has errors, and the two checks differ on it", len(nk) > 5 and nm != vm, (len(nk), len(vk)))

# ---------------------------------------------------------------- the menu
o, rc, err = run(f'ercmenu\nopen "{focus}"\nercmenu\n', "menu")
mm = [kv(l) for l in lines_of(o, "ERCMENU")]
check("the program starts", rc == 0 and not any(l.startswith("ERROR") for l in o), err[-200:])
check("Check Design Rules... and V&HDL Check Design Rules... follow Create PCB Net List..., before Generate Symbol References... and Create Parts List..., enabled only with a design",
      len(mm) == 2 and mm[1]["check"] == "&Check Design Rules..." and mm[1]["vhdlcheck"] == "V&HDL Check Design Rules..." and (mm[1]["net"], mm[1]["checkindex"], mm[1]["vhdlcheckindex"], mm[1]["parts"]) == ("0", "1", "2", "4")
      and (mm[0]["checkenabled"], mm[0]["vhdlcheckenabled"], mm[1]["checkenabled"], mm[1]["vhdlcheckenabled"]) == ("0", "0", "1", "1"), str(mm))
check("the VHDL check has TinyCAD's hint", mm[1]["hint"] == "Check the design against VHDL layout rules", mm[1])

# ---------------------------------------------------------------- the dialog
CAPS = ["Duplicated references", "Unconnected items", "More than one item on a no-connect net", "Unassigned reference designators", "Power connected to Power",
        "Power connected to an output", "Output connected to an output", "No output driving input(s)", "Unconnected nets", "Multiple net names on same net", "Non-case distinct net names"]
o, rc, err = run(f'open "{focus}"\nercdialog cancel=1\nercdialog word=5 cancel=1\n', "dlg")
st = [kv(l) for l in lines_of(o, "ERCDIALOG") if l.startswith("start")]
check("the dialog's title, group names, button and eleven captions in TinyCAD's order", st and (st[0]["title"], st[0]["errors"], st[0]["warnings"], st[0]["button"]) ==
      ("Check Design Rules", "Design errors to check", "Design warnings to check", "&Check") and st[0]["captions"].split("|") == CAPS, str(st[:1]))
check("all eleven checks are on to begin with", st[0]["boxes"] == "1" * 11 and st[0]["word"] == "2047", (st[0]["boxes"],))
check("Cancel keeps nothing", st[1]["word"] == "2047" and registry("dlg").get("ERC") in (None, "65535", "2047"), (st[1]["word"], registry("dlg").get("ERC")))
# each box on its own: the bit and the box line up (boxes are in dialog order: dupref unconnect noconnect unassigned power outputpwr output nooutput unconnected multiple nondistinct)
names = ["dupref", "unconnect", "noconnect", "unassigned", "power", "outputpwr", "output", "nooutput", "unconnected", "multiple", "nondistinct"]
bits = {"dupref": 0, "unconnect": 1, "noconnect": 2, "power": 3, "outputpwr": 4, "output": 5, "nooutput": 6, "unconnected": 7, "multiple": 8, "nondistinct": 9, "unassigned": 10}
script = f'open "{focus}"\n'
for n in names: script += "ercdialog word=0 %s=1 cancel=1\n" % n
o, rc, err = run(script, "dlg2")
pr = [kv(l) for l in lines_of(o, "ERCDIALOG") if l.startswith("pressed")]
check("each box sets its own bit of the WORD", [int(p["word"]) for p in pr] == [1 << bits[n] for n in names], [p["word"] for p in pr])
o, rc, err = run(f'open "{focus}"\nercdialog word=1285\nercdialog cancel=1\nercdialog word=1024 power=1 unassigned=0 vhdl=1\nercdialog cancel=1\n', "dlg3")
st = [kv(l) for l in lines_of(o, "ERCDIALOG") if l.startswith("start")]; er = [kv(l) for l in lines_of(o, "ERCDIALOG") if l.startswith("errors")]
check("Check keeps the choices as the WORD (the registry value ERC), for the plain and the VHDL check", [s["word"] for s in st] == ["2047", "1285", "1285", "8"] and [e["word"] for e in er] == ["1285", "8"]
      and registry("dlg3").get("ERC") == "8", ([s["word"] for s in st], er, registry("dlg3").get("ERC")))
check("the boxes of word 1285 (bits 0, 2, 8, 10)", st[1]["boxes"] == "".join("1" if (1285 >> bits[n]) & 1 else "0" for n in names), st[1]["boxes"])
set_registry("dlg3", "ERC", 0xF805)
o, rc, err = run(f'open "{focus}"\nercdialog cancel=1\nercdialog\nercdialog cancel=1\n', "dlg3")
st = [kv(l) for l in lines_of(o, "ERCDIALOG") if l.startswith("start")]
check("bits above the eleventh in the registry are ignored, and the WORD is written without them", [s["word"] for s in st] == ["5", "5", "5"] and registry("dlg3").get("ERC") in ("5", str(0xF805 & 0x7FF)), ([s["word"] for s in st], registry("dlg3").get("ERC")))

# ---------------------------------------------------------------- the result, against the oracle
total = 0
WORDS = [0xFFFF, 0, 0x0001, 0x0002, 0x0004, 0x0008, 0x0010, 0x0020, 0x0040, 0x0080, 0x0100, 0x0200, 0x0400, 0x01FF, 0x0300, 0x0555]
for i, d in enumerate(designs + [two, focus]):
    combos = [(w, v) for w in WORDS[:2] + WORDS[2 + (i % 7)::5] for v in (0, 1)]
    script = f'open "{d}"\n'
    for (w, v) in combos: script += f"ercdialog word={w} vhdl={v}\nercwindow\nercmarkers\n"
    o, rc, err = run(script, f"res{i}")
    wins = [window(l) for l in lines_of(o, "ERCWINDOW")]; mk = lines_of(o, "ERCMARKERS")
    check(f"{os.path.basename(d)}: the program ran", rc == 0 and len(wins) == len(combos) and len(mk) == len(combos), (rc, len(wins), err[-200:]))
    for (w, v), win, m in zip(combos, wins, mk):
        want_msgs, want_marks = expected(d, w, v)
        marks, extra = parse_markers(m)
        got_marks = [(a, b, c, e) for (a, b, c, e) in marks]
        check(f"{os.path.basename(d)} word={w} vhdl={v}: the window's lines", win["open"] == "1" and win["lines"] == want_msgs and win["items"] == str(len(want_msgs)) and win["title"] == "Design Markers", (win["lines"][:2], want_msgs[:2], len(win["lines"]), len(want_msgs)))
        check(f"{os.path.basename(d)} word={w} vhdl={v}: the markers", got_marks == sorted(want_marks, key=lambda t: t[1]), (got_marks[:3], want_marks[:3], len(got_marks), len(want_marks)))
        total += 1
print(f"results: {total} runs compared")
o, rc, err = run(f'open "{focus}"\nercdialog word=2047\nercwindow\nercdialog word=2047\nercwindow\nercmarkers\n', "clean")
w = [window(l) for l in lines_of(o, "ERCWINDOW")]
check("a design with no errors shows the 'No errors were found' line and no markers, and nothing is selected", w[0]["lines"] == ["No errors were found in this design."] and w[0]["selected"] == "-1" and lines_of(o, "ERCMARKERS")[0].startswith(" sheet="), (w[0], lines_of(o, "ERCMARKERS")))

# ---------------------------------------------------------------- the check the netlist, Spice and VHDL commands make first
mx = f'"{mixed}"'
o, rc, err = run(f'open {mx}\nnetlist cancel=1\nercwindow\nercmarkers\nercpress close\nspice cancel=1\nercwindow\nercpress close\nvhdl cancel=1\nercwindow\nercmarkers\nercpress close\nercwindow\nercmarkers\n', "pre")
w = [window(l) for l in lines_of(o, "ERCWINDOW")]; mk = lines_of(o, "ERCMARKERS")
check("the PCB netlist and Spice commands run the plain check first and show its list", w[0]["lines"] == nm and w[1]["lines"] == nm and w[0]["open"] == "1", (w[0]["lines"][:2], nm[:2]))
check("the VHDL command runs the VHDL check first", w[2]["lines"] == vm and len(vm) != len(nm), (len(w[2]["lines"]), len(vm), len(nm)))
check("the markers of the commands are the check's markers", parse_markers(mk[0])[0] == sorted([(a, b, c, e) for (a, b, c, e) in nk], key=lambda t: t[1]) and parse_markers(mk[1])[0] == sorted(vk, key=lambda t: t[1]), (parse_markers(mk[0])[0][:2], nk[:2]))
check("Close takes the window and the markers away", w[3]["open"] == "0" and w[3]["items"] == "0" and parse_markers(mk[2])[0] == [], (w[3], mk[2]))
o, rc, err = run(f'open "{focus}"\nnetlist cancel=1\nercwindow\nspice cancel=1\nvhdl cancel=1\nercwindow\n', "pre2")
w = [window(l) for l in lines_of(o, "ERCWINDOW")]
check("a design with no errors leaves the window closed", [x["open"] for x in w] == ["0", "0"], w)
o, rc, err = run(f'open {mx}\nercdialog word=2047\nercwindow\nercdialog word=0\nercwindow\nnetlist cancel=1\nercwindow\nercmarkers\n', "pre3")
w = [window(l) for l in lines_of(o, "ERCWINDOW")]
check("with every check off, the dialog's Check shows 'No errors' but a netlist command shows nothing, and closes the earlier list", w[0]["items"] == str(len(nm)) and w[1]["lines"] == ["No errors were found in this design."] and w[2]["open"] == "0" and w[2]["items"] == "0", [(x["open"], x["items"]) for x in w])
o, rc, err = run(f'open {mx}\ncheck\nercwindow\ncheck show=1 vhdl=1\nercwindow\ncheck\nercwindow\n', "pre4")
w = [window(l) for l in lines_of(o, "ERCWINDOW")]; ch = lines_of(o, "CHECK")
check("the check on its own", ch == [f"errors={len(nk)}", f"errors={len(vk)}", f"errors={len(nk)}"] and w[0]["lines"] == nm and w[1]["lines"] == vm and w[2]["lines"] == nm, (ch, len(nk), len(vk)))
KW = next(w_ for w_ in (1, 2, 8, 16, 32, 64, 128, 256, 1024) if expected(mixed, w_, False)[1])
o, rc, err = run(f'open {mx}\nercdialog word={KW}\ncheck\nercwindow\n', "pre5")
w = [window(l) for l in lines_of(o, "ERCWINDOW")]; wn, wk = expected(mixed, KW, False)
check("a command's check uses the kept WORD", w[0]["lines"] == wn, (w[0]["lines"][:2], wn[:2]))

# ---------------------------------------------------------------- choosing a line
d = designs[0]; msgs, marks = expected(d, 0xFFFF, False)
script = f'open "{d}"\nercdialog word=2047\n'
picks = [0, 3, 7, len(msgs) - 1, 2]
for k in picks: script += f"ercchoose {k}\nercwindow\n"
o, rc, err = run(script, "choose")
cm = lines_of(o, "ERCCHOOSE"); wins = [window(l) for l in lines_of(o, "ERCWINDOW")]
ok = True; detail = []
for k, line, win in zip(picks, cm, wins):
    ms, ex = parse_markers(line)
    cx, cy = (int(v) for v in ex["at"].split(",")); sw, sh = (int(v) for v in ex["size"].split("x"))
    rw = raw_markers(line); last = rw[-1] if rw else None
    good = (ex["selected"] == "1" and ex["selectedmarker"] == str(k) and last is not None and last[1] == k and abs(cx - sw / 2) <= 1 and abs(cy - sh / 2) <= 1 and win["selected"] == str(k) and len(ms) == len(marks))
    ok = ok and good
    if not good: detail.append((k, ex, last, win["selected"]))
check("choosing a line selects its marker (and only it), brings it to the front of the sheet, puts it in the middle of the window and keeps the line chosen", ok, detail[:2])
ms_all = sorted(parse_markers(cm[-1])[0])
check("the other markers are where they were", sorted([(a, b, c, e) for (a, b, c, e) in parse_markers(cm[-1])[0]], key=lambda t: t[1]) == sorted(marks, key=lambda t: t[1]), (ms_all[:2], marks[:2]))
# a design with errors on two sheets: choosing one on the other sheet changes the sheet shown
msgs2, marks2 = expected(two, 0xFFFF, False)
first_other = next(m for m in marks2 if m[0] == 0); on_second = next(m for m in marks2 if m[0] == 1)
o, rc, err = run(f'open "{two}"\nercdialog word=2047\nercchoose {on_second[1]}\nercchoose {first_other[1]}\nercchoose {on_second[1]}\nsheetinfo\n', "choose2")
cm = lines_of(o, "ERCCHOOSE")
exs = [parse_markers(l)[1] for l in cm]
check("choosing a marker on another sheet shows that sheet; the sheet is the marker's", [e["sheet"] for e in exs] == [str(on_second[0]), str(first_other[0]), str(on_second[0])] and all(e["selected"] == "1" for e in exs), exs)
check("the sheet tabs follow", "current=1" in lines_of(o, "SHEETS")[-1], lines_of(o, "SHEETS"))
# the line that says there are no errors chooses nothing
o, rc, err = run(f'open "{focus}"\nercdialog word=2047\nercchoose 0\nercwindow\n', "choose3")
check("the 'No errors' line chooses nothing", parse_markers(lines_of(o, "ERCCHOOSE")[0])[1]["selected"] == "0", lines_of(o, "ERCCHOOSE"))

# ---------------------------------------------------------------- clicking a marker on the sheet chooses its line
picks = [1, 4, 9]
script = f'open "{d}"\nercdialog word=2047\n'
for k in picks:
    script += f"ercchoose {k}\nercmarkers\n"
o, rc, err = run(script, "click0")
pts = [m for m in [parse_markers(l)[0] for l in lines_of(o, "ERCMARKERS")]]
script = f'open "{d}"\nercdialog word=2047\n'
for k, mk_ in zip(picks, pts):
    mm_ = next(m for m in mk_ if m[1] == k)
    script += f"ercchoose {k}\nercchoose 0\nselclear\nclickmm {mm_[2]} {mm_[3]}\nercwindow\nercmarkers\n"
o, rc, err = run(script, "click1")
w = [window(l) for l in lines_of(o, "ERCWINDOW")]; ex = [parse_markers(l)[1] for l in lines_of(o, "ERCMARKERS")]
check("clicking a marker on the sheet selects its line in the window", [x["selected"] for x in w] == [str(k) for k in picks] and [e["selectedmarker"] for e in ex] == [str(k) for k in picks], ([x["selected"] for x in w], ex))

# ---------------------------------------------------------------- Re-check, Close, closing the document
o, rc, err = run(f'open {mx}\nercdialog word=2047 vhdl=1\nercwindow\nercpress recheck\nercwindow\nercmarkers\nercpress annotate\nercwindow\n', "recheck")
w = [window(l) for l in lines_of(o, "ERCWINDOW")]
check("Re-check runs the plain check again, also after the VHDL check", len(w[0]["lines"]) == len(vm) and w[1]["lines"] == nm and len(parse_markers(lines_of(o, "ERCMARKERS")[0])[0]) == len(nk), ([len(x["lines"]) for x in w], len(nm), len(vm)))
check("Generate Symbol References is usable; its dialog (answered with Cancel here) changes nothing in the list", w[0]["annotate"] == "1" and w[2]["lines"] == nm, w[0]["annotate"])
d1 = f'"{designs[1]}"'
o, rc, err = run(f'open {mx}\nopen {d1}\ngotodoc 0\nercdialog word=2047\nercwindow\ngotodoc 1\nercwindow\nercmarkers\nercdialog word=2047\nercwindow\ngotodoc 0\nercmarkers\ngotodoc 1\nclosedoc 1\nercwindow\n', "docs")
w = [window(l) for l in lines_of(o, "ERCWINDOW")]; mk = lines_of(o, "ERCMARKERS")
check("the window belongs to the document it was made for", w[0]["doc"] == "0" and w[1]["doc"] == "0", [(x["doc"], x["open"]) for x in w])
check("a check in another document moves the window there and takes the first document's markers away", w[2]["doc"] == "1" and parse_markers(mk[1])[0] == [], (w[2]["doc"], mk))
o, rc, err = run(f'open {mx}\nopen "{focus}"\ngotodoc 0\nercdialog word=2047\nercchoose 2\ndocs\nercchoose 2\ngotodoc 1\nercchoose 3\ndocs\nercmarkers\n', "docs2")
dl = lines_of(o, "DOCS"); cm = lines_of(o, "ERCCHOOSE")
check("choosing a line shows the document it belongs to", "current=0" in dl[0] and "current=0" in dl[1] and parse_markers(cm[-1])[1]["selectedmarker"] == "3", (dl, cm[-1]))
o, rc, err = run(f'open {mx}\nopen "{focus}"\ngotodoc 0\nercdialog word=2047\nclosedoc 0\nercwindow\nercmarkers\n', "docs3")
w = [window(l) for l in lines_of(o, "ERCWINDOW")]
check("closing the document closes its window", w[-1]["open"] == "0" and rc == 0, (w, err[-200:]))

# ---------------------------------------------------------------- the markers are not part of the design
def unhint(t): return re.sub(rb"[ \t]*<HINT [^>]*/>\r?\n?", b"", t)  # MakeNet leaves net hints in the file, as in TinyCAD
a = os.path.join(work, "saved_a.dsn"); b = os.path.join(work, "saved_b.dsn")
o, rc, err = run(f'open {mx}\nsave "{b}"\nopen {mx}\nercdialog word=2047\ndocs\nsave "{a}"\ndocs\n', "save")
dl = lines_of(o, "DOCS")
check("a check does not mark the design as changed", all("*" not in x.split("list=")[1] for x in dl), dl)
check("the markers are not saved", unhint(open(a, "rb").read()) == unhint(open(b, "rb").read()) and b"ERROR" not in open(a, "rb").read(), (os.path.getsize(a), os.path.getsize(b)))
o, rc, err = run(f'open "{a}"\nercmarkers\nsheetinfo\n', "save")
check("a design opened from the saved file has no markers", parse_markers(lines_of(o, "ERCMARKERS")[0])[0] == [], lines_of(o, "ERCMARKERS"))

print(f"{checks} checks, {len(fails)} failed")
sys.exit(1 if fails else 0)
