"""Counting names and pin numbers when objects are placed one after another (TinyCAD's Repeat Directions), on the core functions. Written as a restatement of TinyCAD's C++
(CDrawLabel::LButtonDown, CDrawText::LButtonDown, CDrawPin::LButtonDown and IncrementNumber, with C's atoi) and compared with the program over thousands of generated strings:
  - label and text: from the first digit or minus sign to the end is a number, counted and written back (anything after its digits is dropped); no digit or minus sign, no change
  - pin number and name: the first run of digits is counted and kept between 1 and 999, the text round it kept; with no digits a last letter moves along the alphabet while it stays a letter
  - both directions, up and down, and the usual cases a person meets (A1 -> A2, R9 -> R10, 1 -> 2 and back, counting down to 1, D1-5, A-3, a pin A -> B)
Needs the built test driver."""
import os, random, re, subprocess, sys, tempfile
BUILD = os.environ.get("TC_BUILD", "build"); EXE = os.path.join(BUILD, "repeattest")
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:300])
def drv(mode, lines):
    open(f"{tmp}/in.txt", "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    r = subprocess.run([EXE, mode, f"{tmp}/in.txt"], capture_output=True, text=True)
    if r.returncode != 0: raise SystemExit("repeattest failed: " + r.stderr[-300:])
    return [l[2:] for l in r.stdout.split("\n") if l.startswith("R ")]
# ---------- TinyCAD's logic, restated ----------
def wrap32(n): return ((n + 2**31) % 2**32) - 2**31
def atoi(s):
    m = re.match(r"[ \t\n\v\f\r]*([+-]?)(\d*)", s)
    if not m.group(2): return 0
    v = min(int(m.group(2)), 2147483647)
    return -v if m.group(1) == "-" else v
def label_next(s, d):
    hold = next((i for i, c in enumerate(s) if c in "0123456789-"), -1)
    if hold == -1: return s
    return s[:hold] + str(wrap32(atoi(s[hold:]) + d))
def inc_number(s, step):
    pos = next((i for i, c in enumerate(s) if c.isdigit() and c.isascii()), -1)
    if pos >= 0:
        j = pos
        while j < len(s) and s[j].isdigit() and s[j].isascii(): j += 1
        n = wrap32(atoi(s[pos:j]) + step)
        n = max(1, min(999, n))
        return s[:pos] + str(n) + s[j:]
    if s:
        ch = ord(s[-1]) + step
        if (65 <= ch <= 90) or (97 <= ch <= 122): return s[:-1] + chr(ch)
    return s
rnd = random.Random(31)
ALPHA = list("ABCDRSZazxy") + list("0123456789") * 3 + list("-_ ./+")
def rand_text():
    return "".join(rnd.choice(ALPHA) for _ in range(rnd.choice([0, 1, 2, 3, 4, 6, 9])))
texts = [rand_text() for _ in range(4000)] + ["A1", "R9", "R99", "1", "0", "-1", "A-3", "D1-5", "NET-3", "VCC", "LABEL", "", "x", "10", "A0", "ZZ", "a1b2", "-", "--5", "1 2", "  7", "A 7x", "999", "R999", "2147483646", "R2147483647", "0000", "007", "A1B", "B", "Z", "a", "z", "A", "-A", "9z"]
for name, fn, drvname in (("label", label_next, "label"), ("pin number", inc_number, "number")):
    lines = []; want = []
    for t in texts:
        for d in (1, -1):
            lines.append(f"{d}\t{t}"); want.append(fn(t, d))
    got = drv(drvname, lines); bad = [(l, g, w) for l, g, w in zip(lines, got, want) if g != w]
    check(f"{len(lines)} {name} texts (both directions): the next one is what TinyCAD's rule gives", not bad and len(got) == len(lines), str(bad[:4]))
# the cases a person meets
def one(mode, d, t): return drv(mode, [f"{d}\t{t}"])[0]
check("labels count as a person expects: A1 -> A2 and back, R9 -> R10, 7 -> 8, VCC stays VCC, counting down goes through 0 and below (A1 -> A0 -> A-1), a minus sign starts the number (A-3 -> A-2)",
      [one("label", 1, "A1"), one("label", -1, "A2"), one("label", 1, "R9"), one("label", 1, "7"), one("label", 1, "VCC"), one("label", -1, "A1"), one("label", -1, "A0"), one("label", 1, "A-3")] == ["A2", "A1", "R10", "8", "VCC", "A0", "A-1", "A-2"], "")
check("and TinyCAD's quirks are kept: what follows the number is dropped (D1-5 -> D2), and the first minus sign counts as the start of the number (NET-3 -> NET-2, even in a name)", [one("label", 1, "D1-5"), one("label", 1, "NET-3")] == ["D2", "NET-2"], "")
check("pin numbers stay between 1 and 999: 1 counting down stays 1, 999 counting up stays 999, 9 -> 10, the text round the digits is kept (A1B -> A2B)", [one("number", -1, "1"), one("number", 1, "999"), one("number", 1, "9"), one("number", 1, "A1B")] == ["1", "999", "10", "A2B"], "")
check("pin letters move along the alphabet while they stay letters: A -> B, B -> A, Z up and A down stay, a -> b, and a name with no digits and a last non-letter is left alone", [one("number", 1, "A"), one("number", -1, "B"), one("number", 1, "Z"), one("number", -1, "A"), one("number", 1, "a"), one("number", 1, "A_")] == ["B", "A", "Z", "A", "b", "A_"], "")
# a pin as a whole: number by the pin direction, name by the name direction
pl = []; pw = []
for _ in range(1500):
    pd, nd = rnd.choice([1, -1]), rnd.choice([1, -1]); num, nm = rand_text(), rand_text()
    pl.append(f"{pd}\t{nd}\t{num}\t{nm}"); pw.append(inc_number(num, pd) + "\t" + inc_number(nm, nd))
got = drv("pin", pl); bad = [(l, g, w) for l, g, w in zip(pl, got, pw) if g != w]
check("1500 pins: the number is counted by the pin direction and the name by the name direction, independently, both by the pin rule", not bad and len(got) == len(pl), str(bad[:3]))
print(f"repeat (functions): {checks} checks, {len(fails)} failures")
# ---------- the menu and placing, in the program ----------
import shutil, glob
import xml.etree.ElementTree as ET
BIN = os.environ.get("TC_GUI_BIN", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "gui", "build", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("the checks in the program are skipped: need xvfb-run and the built program", BIN)
    print("\nREPEAT CHECKS PASSED (functions only)" if not fails else "\nREPEAT CHECKS FAILED"); sys.exit(1 if fails else 0)
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
def run(script, timeout=150):
    h = tempfile.mkdtemp(dir=tmp)
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n"), r.returncode, r.stderr
def rinfo(lines): return [dict(t.split("=") for t in l.split()[1:]) for l in lines if l.startswith("REPEATINFO ")]
o, rc, err = run('repeatinfo\nnewdoc "ISO A4" landscape\nrepeatinfo\n'); r = rinfo(o)
check("with no design open the menu items cannot be used; a new design starts counting up for names and pins, with Name Increment and Pin Increment ticked", r[0]["enabled"] == "0" and r[1] == {"name": "1", "pin": "1", "menu": "1010", "enabled": "1"}, str(r))
o, rc, err = run('newdoc "ISO A4" landscape\n' + "".join(f"repeatdir {d}\nrepeatinfo\n" for d in ("namedown", "pindown", "nameup", "pinup", "pindown", "namedown")))
r = rinfo(o)
check("each menu item sets its own direction and ticks only its own pair (Name Decrement, then Pin Decrement as well, Name Increment, Pin Increment, ...)", [(x["name"], x["pin"], x["menu"]) for x in r] == [("-1", "1", "0110"), ("-1", "-1", "0101"), ("1", "-1", "1001"), ("1", "1", "1010"), ("1", "-1", "1001"), ("-1", "-1", "0101")], str([(x["name"], x["pin"], x["menu"]) for x in r]))
o, rc, err = run('newdoc "ISO A4" landscape\nrepeatdir namedown\nrepeatdir pindown\nnewdoc "ISO A4" landscape\nrepeatinfo\ngotodoc 0\nrepeatinfo\ngotodoc 1\nrepeatinfo\n'); r = rinfo(o)
check("the directions belong to each design: a second design starts at Increment, and going back to the first finds its Decrement choices (and the menu ticks follow)", [(x["name"], x["pin"], x["menu"]) for x in r] == [("1", "1", "1010"), ("-1", "-1", "0101"), ("1", "1", "1010")], str(r))
# labels and texts placed one after another
def sheet_objs(path, tag):
    r_ = ET.parse(path).getroot(); sh = r_.findall("TinyCAD")[0] if r_.tag == "TinyCADSheets" else r_
    return [(float(e.get("pos").split(",")[1]), (e.text or "").strip()) for e in sh if e.tag == tag]
def sequence(tool, default, steps):
    """steps: ('place',) | ('edit', text) | ('dir', 'namedown') | ('other',) ; returns the script, and the texts expected in the order placed"""
    script = 'newdoc "ISO A4" landscape\n'; want = []; y = 20; last = None; nd = 1
    other_tool = "text" if tool == "label" else "label"
    for st in steps:
        if st[0] == "place":
            script += f"tool {tool}\nmouse down 40 {y}\n"
            text = default if last is None else label_next(last, nd)
            if not text: text = default
            want.append(text); last = text; y += 10
        elif st[0] == "edit":
            script += f"setprop text \"{st[1]}\"\n"; last = st[1]
            want[-1] = st[1]
        elif st[0] == "dir":
            script += f"repeatdir {st[1]}\n"; nd = 1 if st[1] == "nameup" else -1
        elif st[0] == "other":
            script += f"tool {other_tool}\nmouse down 150 {y}\nsetprop text \"Z99\"\n"; y += 10
    return script, want
nd = 1
cases = [[("place",), ("edit", "NET1"), ("place",), ("place",), ("place",)],
         [("place",), ("edit", "A9"), ("place",), ("place",), ("dir", "namedown"), ("place",), ("place",)],
         [("place",), ("place",), ("place",)],
         [("place",), ("edit", "R-3"), ("place",), ("place",)],
         [("place",), ("edit", "D1-5"), ("place",), ("edit", "VCC"), ("place",)],
         [("place",), ("edit", "N7"), ("place",), ("other",), ("place",), ("other",), ("place",)],
         [("dir", "namedown"), ("place",), ("edit", "X3"), ("place",), ("place",), ("place",), ("place",), ("dir", "nameup"), ("place",)]]
bad = []; total = 0
for tool, default, tag in (("label", "LABEL", "LABEL"), ("text", "Text", "TEXT")):
    for n, steps in enumerate(cases):
        nd = 1
        script, want = sequence(tool, default, steps)
        path = f"{tmp}/seq_{tool}_{n}.dsn"
        o, rc, err = run(script + f'save "{path}"\n')
        got = [t for y, t in sorted(sheet_objs(path, tag)) if t != "Z99"]
        total += len(want)
        if got != want: bad.append((tool, n, got, want))
check(f"{total} labels and texts placed one after another in 14 sequences (counting up and down, with the text edited between, directions changed in the middle, the other tool used between): each starts as the last one counted, as TinyCAD's rule says", not bad, str(bad[:2]))
# undo: the count carries on (TinyCAD's text box keeps its text when a placement is undone). B4 is typed; B5 is placed and undone; B6 is placed and undone; the next is B7.
# (an undo puts the tool back to Select, so the label tool is chosen again each time, as a person would)
o, rc, err = run(f'newdoc "ISO A4" landscape\ntool label\nmouse down 40 20\nsetprop text "B4"\nmouse down 40 30\nundo\ntool label\nmouse down 40 40\nundo\ntool label\nmouse down 40 50\nsave "{tmp}/undo.dsn"\n')
got = [t for y, t in sorted(sheet_objs(f"{tmp}/undo.dsn", "LABEL"))]
check("after undos the count carries on from the last one placed, as the text box of TinyCAD does: B4 typed, B5 and B6 placed and undone, and the next one placed is B7", got == ["B4", "B7"], str(got))
# pins
rnd2 = random.Random(5); bad = 0; first = None
for k in range(6):
    pd, nd2 = rnd2.choice(["pinup", "pindown"]), rnd2.choice(["nameup", "namedown"])
    pairs = [(rand_text().replace(" ", "_") or "1", rand_text().replace(" ", "_") or "A") for _ in range(10)]
    o, rc, err = run('newdoc "ISO A4" landscape\n' + f"repeatdir {pd}\nrepeatdir {nd2}\n" + "".join(f"nextpin {a} {b}\n" for a, b in pairs))
    gl = [l[8:].split(" ") for l in o if l.startswith("NEXTPIN ")]
    for (a, b), g in zip(pairs, gl):
        wa, wb = inc_number(a, 1 if pd == "pinup" else -1), inc_number(b, 1 if nd2 == "nameup" else -1)
        if g != [wa, wb]: bad += 1; first = first or (pd, nd2, a, b, g, wa, wb)
check("the next pin counts its number by the pin direction and its name by the name direction as chosen in the menu (60 pins; the symbol editor window that will place pins is not ported yet, so this is the function the menu feeds)", bad == 0, str(first))
print(f"repeat: {checks} checks, {len(fails)} failures")
print("\nREPEAT CHECKS PASSED" if not fails else f"\nREPEAT CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
