"""Special > Generate Symbol References on the real program (the dialog, the reference painter, the Design Markers window's button), with the numbers compared with
annooracle.py (a separate statement of Special.cpp):
  - the menu: the item follows V&HDL Check Design Rules... and comes before Create Parts List..., usable only with a design open
  - the dialog: TinyCAD's title, group names, captions and buttons; the choice of references and of all sheets come from the registry (Annotate.type, default 1;
    Annotate.allsheets, default on) and are written by OK; the other choices are those of the last time; typing in the start box chooses "Start at value"; the box is
    read as GetDlgItemInt does
  - the result of OK on several designs and choices equals the oracle's; it is one undo step; a design is changed when OK is pressed and not when Cancel is
  - the reference painter: the button keeps the choices and starts the tool at the start value; a click on a symbol gives it the next number, a right click takes it
    away, a click on nothing does nothing; each click that does something is one undo step
  - the Design Markers window's Generate Symbol References button runs the command for the window's design
Needs the built program and xvfb."""
import glob, os, re, shutil, subprocess, sys, tempfile, random
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
os.environ.setdefault("TC_BUILD", "build")
import annooracle as ao
import ercoracle as eo
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Generate Symbol References dialog checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:900])
def run(script, home, timeout=250):
    h = os.path.join(tmp, "home_" + home); os.makedirs(h, exist_ok=True)
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n"), r.returncode, r.stderr
def kv(line):
    out = {}
    for m in re.finditer(r"(\w+)=(.*?)(?= \w+=|$)", line): out[m.group(1)] = m.group(2)
    return out
def lines_of(o, tag): return [l[len(tag) + 1:] for l in o if l.startswith(tag + " ")]
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
def dialog(line):
    """ANNOTATEDIALOG text -> (the refs printed before it is cut off, start, pressed, done)"""
    parts = line.split(" | ")
    return kv(parts[0].split("start ", 1)[1]) if False else None
def segs(line):
    m = re.search(r"start (.*?) \\| pressed (\\w+) (.*?) \\| done (.*)$".replace("\\\\", "\\"), line)
    return (kv(m.group(1)), m.group(2), kv(m.group(3)), kv(m.group(4))) if m else None
def refs_of(text):
    """'idx:ref:part:x:y;... | ...' -> list per sheet of (idx, ref, part, x, y)"""
    out = []
    for sh in text.split(" | "):
        cur = []
        for it in sh.split(";"):
            if not it.strip(): continue
            a = it.split(":")
            cur.append((int(a[0]), ":".join(a[1:-3]).replace("_", " "), int(a[-3]), float(a[-2]), float(a[-1])))
        out.append(cur)
    return out
def want_refs(ms):
    sheets = max(m["sheet"] for m in ms) + 1 if ms else 1
    return [[(m["idx"], m["ref"], m["part"], m["A"][0], m["A"][1]) for m in ms if m["sheet"] == s] for s in range(sheets)]
def same_refs(got, want):
    if len(got) != len(want): return False
    for g, w in zip(got, want):
        if len(g) != len(w): return False
        for a, b in zip(g, w):
            if a[:3] != b[:3] or abs(a[3] - b[3]) > 1e-3 or abs(a[4] - b[4]) > 1e-3: return False
    return True
def refs_line(o, tag="ANNOTATEREFS"):
    return [refs_of(l) for l in lines_of(o, tag)]

work = os.path.join(tmp, "work"); os.makedirs(work)
nib = os.path.join(EX, "vhdl", "nibbles")
def find(name): return next(p for dp, _, fs in os.walk(EX) for f in fs if f == name for p in [os.path.join(dp, f)])
fu = find("FunctionalUnit_v2.dsn")
focus = find("Focus Bipolar Motor Circuit.dsn")

# ---------------------------------------------------------------- the menu
o, rc, err = run(f'annotatemenu\nopen "{fu}"\nannotatemenu\n', "menu")
mm = [kv(l) for l in lines_of(o, "ANNOTATEMENU")]
check("the program starts", rc == 0 and not any(l.startswith("ERROR") for l in o), err[-200:])
check("Generate Symbol References... follows V&HDL Check Design Rules..., comes before Create Parts List..., usable only with a design",
      len(mm) == 2 and lines_of(o, "ANNOTATEMENU")[0].startswith("&Generate Symbol References...") and (mm[1]["check"], mm[1]["vhdlcheck"], mm[1]["index"], mm[1]["parts"]) == ("1", "2", "3", "4")
      and (mm[0]["enabled"], mm[1]["enabled"]) == ("0", "1") and mm[1]["hint"] == "Automatically create or remove the symbol references", str(mm))

# ---------------------------------------------------------------- the dialog
CAPS = "Add References|Remove References|All References|Un-numbered References|References matching:|All Sheets|Default start value|Start at value:|Use reference painter"
o, rc, err = run(f'open "{fu}"\nannotatedialog press=cancel\nannotatedialog press=cancel\n', "dlg")
d = [segs(l) for l in lines_of(o, "ANNOTATEDIALOG")]
check("the dialog's title, group names, captions and buttons are TinyCAD's", d[0] is not None and d[0][0]["title"] == "Generate Symbol References" and d[0][0]["groups"] == "Action|References|Value|Reference painter"
      and d[0][0]["captions"] == CAPS and d[0][0]["buttons"] == "&OK|&Cancel|Use reference painter", d[0])
st = d[0][0]
check("first choices: add, un-numbered references, default start value, \"U?\", 1, all sheets (the last two from the registry's defaults)",
      (st["action"], st["which"], st["match"], st["value"], st["start"], st["all"], st["startbox"]) == ("add", "unnum", "U?", "default", "1", "1", "1"), st)
check("Cancel keeps nothing", d[1][0]["which"] == "unnum" and d[1][0]["all"] == "1", d[1][0])
# each choice, and the registry
script = f'open "{fu}"\n'
combos = [("which=all all=0", "0", "0"), ("which=match all=1", "2", "1"), ("which=unnum all=0", "1", "0")]
for c, t, a in combos: script += f"annotatedialog {c} press=cancel\n"
o, rc, err = run(script, "dlg2")
d = [segs(l) for l in lines_of(o, "ANNOTATEDIALOG")]
check("the choices are those typed, shown when OK or Cancel is pressed", [(x[2]["which"], x[2]["all"]) for x in d] == [("all", "0"), ("match", "1"), ("unnum", "0")], [x[2] for x in d])
check("Cancel writes none of the choices that the dialog keeps in the registry", all(x[3]["type"] == "1" and x[3]["allsheets"] == "1" for x in d), [x[3] for x in d])
o, rc, err = run(f'open "{fu}"\nannotatedialog which=match match=R? all=0 action=remove value=start start=7 press=ok\nannotatedialog press=cancel\n', "dlg3")
d = [segs(l) for l in lines_of(o, "ANNOTATEDIALOG")]
check("OK keeps the choice of references and of all sheets in the settings (Annotate.type, Annotate.allsheets)", d[0][3]["type"] == "2" and d[0][3]["allsheets"] == "0"
      and registry("dlg3").get("Annotate.type") == "2" and registry("dlg3").get("Annotate.allsheets") == "0", (d[0][3], registry("dlg3")))
check("the next dialog shows the last choices (the action, the match, the value and start from the last time; the two kept in the registry from it)",
      (d[1][0]["action"], d[1][0]["which"], d[1][0]["match"], d[1][0]["value"], d[1][0]["start"], d[1][0]["all"]) == ("remove", "match", "R?", "start", "7", "0"), d[1][0])
o, rc, err = run(f'open "{fu}"\nannotatedialog press=cancel\n', "dlg3")
d = [segs(l) for l in lines_of(o, "ANNOTATEDIALOG")]
check("the registry's two values are read when the program starts again, the rest start as new", (d[0][0]["which"], d[0][0]["all"], d[0][0]["action"], d[0][0]["match"], d[0][0]["start"]) == ("match", "0", "add", "U?", "1"), d[0][0])
# typing the start value chooses Start at value; the box is read as GetDlgItemInt does
tests = [("5", 5), ("-5", -5), ("0", 0), ("12x", 0), ("", 0), (" 3", 0), ("+4", 0), ("2147483647", 2147483647), ("-2147483648", -2147483648), ("2147483648", 0), ("99999999999", 0), ("-", 0), ("007", 7)]
script = f'open "{fu}"\n'
for t, v in tests: script += f"annotatedialog start={t} press=cancel\n"
o, rc, err = run(script, "dlg4")
d = [segs(l) for l in lines_of(o, "ANNOTATEDIALOG")]
check("typing in the start box chooses Start at value, and it is read as GetDlgItemInt does", len(d) == len(tests) and all(x[2]["value"] == "start" and x[2]["start"] == str(v) for x, (t, v) in zip(d, tests)), [(x[2]["start"], v) for x, (t, v) in zip(d, tests)])

# ---------------------------------------------------------------- the result, against the oracle
random.seed(9)
srcs = [fu, find("ArithmeticUnit.dsn") if any(f == "ArithmeticUnit.dsn" for _, _, fs in os.walk(EX) for f in fs) else focus, focus]
designs = []
for i, s in enumerate(srcs):
    designs.append(s)
    v = os.path.join(work, f"v{i}.dsn"); ao.variant(s, 40 + i, v); designs.append(v)
two = os.path.join(work, "two.dsn"); v0 = os.path.join(work, "v0.dsn"); eo.two_sheets(v0, two); designs.append(two)
seen = dict(add=0, remove=0, sub=0, multi=0)
for di, d_ in enumerate(designs):
    ms = ao.dump(d_)
    sheets = max(m["sheet"] for m in ms) + 1
    prefs = sorted({m["prefix"] for m in ms})
    script = f'open "{d_}"\nannotaterefs\n'
    wants = []
    cases_ = []
    for k in range(5):
        add = random.random() < 0.75; which = random.choice([0, 1, 2]); value = random.choice([0, 1])
        match = random.choice(prefs) if which == 2 else "U?"; start = random.choice([1, 4, 20]) if value == 1 else 1
        alls = sheets > 1 and random.random() < 0.5; active = random.randrange(sheets)
        want, miss = ao.annotate(ms, add, which, value, match, start, alls, active)
        wants.append(want); cases_.append((add, which, value, match, start, alls, active))
        # each case is run on the design as opened: reopen (the design is a different file after the first change)
        script += f'closedoc 0\nopen "{d_}"\ngosheet {active}\n'
        script += "annotatedialog action=%s which=%s match=%s value=%s start=%s all=%d press=ok\nannotaterefs\nundo\nannotaterefs\nredo\nannotaterefs\n" % (
            "add" if add else "remove", ["all", "unnum", "match"][which], match, "start" if value else "default", start if value else 1, 1 if alls else 0)
        if value == 0: script = script.replace("start=1 all", "all") if False else script
        seen["add" if add else "remove"] += 1
        if alls: seen["multi"] += 1
        if any(m["ppp"] > 1 for m in ms): seen["sub"] += 1
    o, rc, err = run(script, f"res{di}")
    rr = [refs_of(l) for l in lines_of(o, "ANNOTATEREFS")]
    check(f"{os.path.basename(d_)}: the program ran", rc == 0 and len(rr) == 1 + 3 * len(wants), (rc, len(rr), err[-200:]))
    if rc == 0 and len(rr) == 1 + 3 * len(wants):
        orig = rr[0]
        check(f"{os.path.basename(d_)}: the opened design is the oracle's", same_refs(orig, want_refs(ms)))
        for k, w in enumerate(wants):
            add, which, value, match, start, alls, active = cases_[k]
            after, undone, redone = rr[1 + 3 * k], rr[2 + 3 * k], rr[3 + 3 * k]
            check(f"{os.path.basename(d_)} #{k}: the numbers equal the oracle's", same_refs(after, want_refs(w)), [(si, a, b) for si, (sa, sb) in enumerate(zip(after, want_refs(w))) for a, b in zip(sa, sb) if a[:3] != b[:3] or abs(a[3]-b[3]) > 1e-3 or abs(a[4]-b[4]) > 1e-3][:2] + [len(after), len(want_refs(w)), (add, which, value, match, start, alls, active)])
            check(f"{os.path.basename(d_)} #{k}: one undo takes all of it back, one redo puts it again", same_refs(undone, orig) and same_refs(redone, after), "")
print("choices:", seen)
check("coverage: adds, removes, several sheets, packages of several parts", seen["add"] > 10 and seen["remove"] > 3 and seen["multi"] > 1 and seen["sub"] > 10, seen)

# ---------------------------------------------------------------- Cancel changes nothing, OK marks the design as changed
o, rc, err = run(f'open "{fu}"\ndocs\nannotatedialog which=all press=cancel\ndocs\nundoinfo\nannotatedialog which=all press=ok\ndocs\n', "chg")
dl = lines_of(o, "DOCS")
check("Cancel leaves the design as it was, OK marks it as changed", "*" not in dl[0].split("list=")[1] and "*" not in dl[1].split("list=")[1] and "*" in dl[2].split("list=")[1], dl)

# ---------------------------------------------------------------- symbols without a definition
x = ET.parse(fu).getroot(); sy = x.findall(".//SYMBOL")
for s_ in sy[2:4]: s_.set("id", "9999")
mf = os.path.join(work, "missing.dsn"); ET.ElementTree(x).write(mf, encoding="UTF-8", xml_declaration=True)
mms = ao.dump(mf); want, miss = ao.annotate(mms, True, 0, 0, "U?", 1, False, 0)
o, rc, err = run(f'open "{mf}"\nannotatedialog which=all all=0 press=ok\nannotaterefs\n', "miss")
d = [segs(l) for l in lines_of(o, "ANNOTATEDIALOG")]
check("a symbol with no definition is left alone and the command says so", miss and d[0][3]["missing"] == "1" and same_refs(refs_of(lines_of(o, "ANNOTATEREFS")[0]), want_refs(want)), d[0][3])
o, rc, err = run(f'open "{fu}"\nannotatedialog which=all all=0 press=ok\n', "miss2")
d = [segs(l) for l in lines_of(o, "ANNOTATEDIALOG")]
check("with every symbol defined it says nothing", d[0][3]["missing"] == "0", d[0][3])

# ---------------------------------------------------------------- the reference painter
ms = ao.dump(fu); m0 = ms[0]
cx = ((m0["A"][0] + m0["B"][0]) / 2) / 5; cy = ((m0["A"][1] + m0["B"][1]) / 2) / 5
m1 = ms[1]; c1x = ((m1["A"][0] + m1["B"][0]) / 2) / 5; c1y = ((m1["A"][1] + m1["B"][1]) / 2) / 5
o, rc, err = run(f'open "{fu}"\nannotatedialog action=remove which=match match=Q? value=start start=60 all=0 press=painter\nannotatedialog press=cancel\nannotateclick 0 0\n', "paint0")
d = [segs(l) for l in lines_of(o, "ANNOTATEDIALOG")]
check("the painter button keeps the choices and starts the painter tool at the start value", d[0][3]["tool"] == "23" and d[0][3]["refstart"] == "60", d[0][3])
check("the next dialog shows the choices the painter was started with (not the two the registry holds: those are kept by OK only)", (d[1][0]["action"], d[1][0]["which"], d[1][0]["match"], d[1][0]["value"], d[1][0]["start"], d[1][0]["all"]) == ("remove", "unnum", "Q?", "start", "60", "1"), d[1][0])
check("starting the command puts any drawing tool away first, the painter included", d[1][3]["tool"] == "0", d[1][3])
PAINT = 'annotatedialog action=remove which=match match=Q? value=start start=60 all=0 press=painter\n'
script = f'open "{fu}"\n' + PAINT + f"annotateclick {cx} {cy}\nannotateclick {c1x} {c1y}\nannotateclick {cx} {cy} right\nannotateclick 2 2\ntool select\nannotateclick {cx} {cy}\n"
o, rc, err = run(script, "paint")
clicks = [refs_of(l.split(" ", 1)[1]) for l in lines_of(o, "ANNOTATECLICK")]
# the oracle: the symbols under a click are not restated (the hit test is checked elsewhere); the first click gives the symbol its number from 6
want1 = ao.paint(ms, 0, 60, [False, False], [[m0["idx"]], [m1["idx"]]])
first = [e for e in clicks[0][0] if e[0] == m0["idx"]][0]
check("a click on a symbol gives it the next number (from the start value, past those of its prefix)", first[1] == want1[0]["ref"] and first[2] == want1[0]["part"], (first, want1[0]["ref"]))
second = [e for e in clicks[1][0] if e[0] == m1["idx"]][0]
check("the next click gives the next number", second[1] == want1[1]["ref"] and second[1] != first[1], (second, want1[1]["ref"]))
check("a right click takes the number away, a click on nothing changes nothing", clicks[2][0][0][1] == m0["prefix"] and same_refs(clicks[3], clicks[2]), (clicks[2][0][0], clicks[3][0][0]))
check("the tool stays until another is chosen", all(l.split()[0] == "tool=23" for l in lines_of(o, "ANNOTATECLICK")[:4]) and lines_of(o, "ANNOTATECLICK")[4].split()[0] != "tool=23", [l[:10] for l in lines_of(o, "ANNOTATECLICK")])
check("with the tool put away a click on a symbol selects it and does not number it", same_refs(clicks[4], clicks[2]) or clicks[4][0][0][1] == m0["prefix"], clicks[4][0][0])
script = f'open "{fu}"\nannotaterefs\n' + PAINT + f"annotateclick {cx} {cy}\nundo\nannotaterefs\nredo\nannotaterefs\n"
script += PAINT + f"annotateclick 2 2\nundoinfo\n"
o, rc, err = run(script, "paint2")
rr = [refs_of(l) for l in lines_of(o, "ANNOTATEREFS")]
first = [e for e in refs_of(lines_of(o, "ANNOTATECLICK")[0].split(" ", 1)[1])[0] if e[0] == m0["idx"]][0]
check("one undo step takes a click's number away, one redo puts it back", rr[1][0][0][1] == m0["ref"] == rr[0][0][0][1] and rr[2][0][0][1] == first[1], (rr[0][0][0], rr[1][0][0], rr[2][0][0]))

# ---------------------------------------------------------------- the Design Markers window's button
mixed = os.path.join(work, "v0.dsn")
ms = ao.dump(mixed); want, miss = ao.annotate(ms, True, 1, 0, "U?", 1, False, 0)
o, rc, err = run(f'open "{mixed}"\nannotaterefs\ncheck show=1\nercwindow\nannotatenext which=unnum action=add all=0 press=ok\nercpress annotate\nannotatereport\nannotaterefs\n', "win")
w = lines_of(o, "ERCWINDOW")
check("the window's Generate Symbol References button is usable", w and kv(w[0])["annotate"] == "1", w)
rp = lines_of(o, "ANNOTATEREPORT")
rr = [refs_of(l) for l in lines_of(o, "ANNOTATEREFS")]
check("the button runs the command (it asks for the dialog and its answer is carried out)", rp and "pressed ok" in rp[0] and same_refs(rr[1], want_refs(want)), (rp, ))
# a window belonging to another document
two_ = os.path.join(work, "v1.dsn")
o, rc, err = run(f'open "{mixed}"\nopen "{two_}"\ncheck show=1\ngotodoc 0\nannotatenext which=all all=0 press=ok\nercpress annotate\ndocs\nannotaterefs\ngotodoc 1\nannotaterefs\n', "win2")
dl = lines_of(o, "DOCS")
rr = [refs_of(l) for l in lines_of(o, "ANNOTATEREFS")]
m_two = ao.dump(two_); want2, _ = ao.annotate(m_two, True, 0, 0, "U?", 1, False, 0)
check("the button works on the design the window belongs to", "current=1" in dl[-1] and same_refs(rr[0], want_refs(want2)), (dl, ))

print(f"{checks} checks, {len(fails)} failed")
sys.exit(1 if fails else 0)
