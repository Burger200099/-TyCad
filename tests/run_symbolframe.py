#!/usr/bin/env python3
"""The symbol property frame (src/frames/qsymbols) and the parameter list (src/forms/FSymDDD): TinyCAD's symbol tool options (CEditDlgMethodEdit) as ribbon controls, for the symbol being
placed (the tool's frame) and for the selected symbol.
Oracles: the saved design read as text (the SYMBOL's rotate / can_scale / show_power attributes and its FIELD elements), TinyCAD's numbering of the directions (rotate and 3: 0 Up, 1 Down,
2 Left, 3 Right; 4 added for Mirror) restated here, the field list of the library symbol (read with sqlite3) for the rows of the list, the pins the program reports (pinsof) for the power pins.
Cases: the frame's controls; the rotate button turns Up > Right > Down > Left and its menu sets each direction; Mirror; Ref / Show reference / Show power pins / Allow resizing for the
tool and for a selection (undo takes them back); the power pins keep the other pins where they are; the parameter list shows the fields as the C++ lists them, Show? turns a field over, a
Value is edited (Esc drops the edit), only an added parameter can be renamed or deleted, Add puts a new one below the lowest, and every change of a selected symbol is one undo step.
Needs xvfb-run, the built program and the example libraries (TC_EXAMPLES)."""
import os, re, sys, shutil, sqlite3, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
LIB = os.path.join(EX, "libraries", "gen_passive.TCLib")
LIB74 = os.path.join(EX, "libraries", "74TTL.TCLib")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not os.path.exists(LIB) or not os.path.exists(LIB74):
    print("Symbol frame checks skipped: need xvfb-run, the built program and the example libraries"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:700])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    return subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env).stdout.splitlines()
def row_of(lib, name):
    c = sqlite3.connect(lib); names = [r[0] for r in c.execute("select Name from Name where Type=0")]; c.close()
    return sorted(names, key=str.lower).index(name)
def library_fields(lib, name):
    c = sqlite3.connect(lib); d = c.execute("select s.Data from Name n join Symbol s on s.SymbolID=n.SymbolID where n.Name=? and n.Type=0", (name,)).fetchone()[0]; c.close()
    return d if isinstance(d, str) else d.decode("latin1")
cnt = [0]
def saved(lines):
    """runs the script, saves the design and returns (output, symbol attributes, list of fields (type, description, value, show, y))"""
    cnt[0] += 1; f = os.path.join(tmp, "d%d.dsn" % cnt[0])
    o = run(lines + ["savedocas " + f]); t = open(f, encoding="utf-8", errors="replace").read() if os.path.exists(f) else ""
    m = re.search(r"<SYMBOL [^>]*>", t); attrs = dict(re.findall(r"(\w+)='([^']*)'", m.group(0))) if m else {}
    fields = [(int(a["type"]), a["description"], a["value"], int(a["show"]), float(a["pos"].split(",")[1])) for a in (dict(re.findall(r"(\w+)='([^']*)'", x)) for x in re.findall(r"<FIELD [^>]*>", t))]
    return o, attrs, fields
H = ["newdoc A4", "registerframe method all", "lib " + LIB]
R0 = row_of(LIB, "BUZZER")
DIRS = {"Up": 0, "Down": 1, "Left": 2, "Right": 3}      # TinyCAD's numbering: rotate & 3
MENU = ["Up", "Right", "Down", "Left"]
# 1. the tool's frame
o = run(H + ["libbegin %d" % R0, "frameinfo tool", "symframe tool state"])
fi = [l for l in o if l.startswith("FRAMEINFO")]
check("placing a symbol shows the symbol frame with its four bound controls and the symbol text box hidden", fi and "TfmSymbols" in fi[0] and "problems=0" in fi[0] and len(fi) == 6
      and any("edSymbolText" in l and "hidden" in l for l in fi) and all(any(c in l for l in fi) for c in ("sbAllowResize", "sbShowRef", "sbShowPowerPins", "edRef")), fi)
# 2. the rotate button and its menu
o = run(H + ["libbegin %d" % R0] + ["symframe tool state", "symframe tool rotate"] * 5)
st = [l.split(" hint")[0][len("SYMFRAME state "):] for l in o if l.startswith("SYMFRAME state")]
check("the rotate button goes Up > Right > Down > Left > Up", st == ["dir=%s mirror=0" % d for d in ("Up", "Right", "Down", "Left", "Up")], st)
for i, d in enumerate(MENU):
    o, a, f = saved(H + ["libbegin %d" % R0, "symframe tool dir %d" % i, "symframe tool state", "clickmm 90 70"])
    check("the menu item %s sets the direction of the symbol placed (rotate = %d)" % (d, DIRS[d]), a.get("rotate") == str(DIRS[d]) and ("dir=" + d) in " ".join(o), (a, o[-3:]))
o, a, f = saved(H + ["libbegin %d" % R0, "symframe tool dir 1", "symframe tool mirror", "symframe tool state", "clickmm 90 70"])
check("Mirror adds 4 to the rotation and is ticked in the menu", a.get("rotate") == "7" and "mirror=1" in " ".join(o), (a, o))
o, a, f = saved(H + ["libbegin %d" % R0, "symframe tool mirror", "symframe tool mirror", "clickmm 90 70"])
check("Mirror twice is no mirror", a.get("rotate") == "0", a)
# 3. the other controls, for the tool
o, a, f = saved(H + ["libbegin %d" % R0, "frameact tool sbShowRef click", "frameact tool sbAllowResize click", "frameact tool edRef text K7?", "clickmm 90 70"])
check("the tool's Show reference, Allow re-sizing and Ref reach the symbol placed", a.get("can_scale") == "1" and f[0][2] == "K7?" and f[0][3] == 1, (a, f[:2]))
base_o, base_a, base_f = saved(H + ["libbegin %d" % R0, "clickmm 90 70"])
check("without them the symbol is as the library has it (reference hidden, not resizable)", base_a.get("can_scale") == "0" and base_f[0][3] == 0, (base_a, base_f[:2]))
# 4. a selected symbol: same controls, undone by Undo
o, a, f = saved(H + ["libbegin %d" % R0, "clickmm 90 70", "selectall", "symframe sel dir 3", "symframe sel mirror", "frameact sel sbShowRef click", "frameact sel sbAllowResize click", "frameact sel edRef text M1?"])
check("the selection's frame sets direction, mirror, Show reference, Allow re-sizing and Ref", a.get("rotate") == "6" and a.get("can_scale") == "1" and f[0][2] == "M1?" and f[0][3] == 1, (a, f[:1]))
o, a, f = saved(H + ["libbegin %d" % R0, "clickmm 90 70", "selectall", "symframe sel dir 3", "symframe sel mirror", "frameact sel sbShowRef click", "frameact sel sbAllowResize click", "frameact sel edRef text M1?", "undo", "undo", "undo", "undo", "undo"])
check("five undos take them all back", a.get("rotate") == base_a.get("rotate") and a.get("can_scale") == "0" and f[0][2] == base_f[0][2] and f[0][3] == base_f[0][3], (a, f[:1], base_a))
# 5. the power pins
H74 = ["newdoc A4", "registerframe method all", "lib " + LIB74]
R74 = row_of(LIB74, "00")
o = run(H74 + ["libplace %d 90 70" % R74, "selectall", "pinsof", "frameact sel sbShowPowerPins click", "pinsof"])
pins = [l for l in o if l.startswith("PIN ")]
before = [tuple(l.split()[3:5]) for l in pins[:len(pins)] if l.split()[2] == "0" or True]
k = [i for i, l in enumerate(o) if l.startswith("FRAMEACT sbShowPowerPins")][0]
pb = [tuple(l.split()[3:5]) for l in o[:k] if l.startswith("PIN ")]; pa = [tuple(l.split()[3:5]) for l in o[k:] if l.startswith("PIN ")]
check("showing the power pins adds two pins (Vcc and ground)", len(pa) == len(pb) + 2, (len(pb), len(pa)))
check("... and every other pin stays where it was", set(pb) <= set(pa), (pb, pa))
# 6. the parameter list
lib_xml = library_fields(LIB, "BUZZER")
o = run(H + ["libplace %d 90 70" % R0, "selectall", "symlist sel open", "symlist sel rows", "symlist sel state"])
rows = [l for l in o if l.startswith("SYMLIST rows")]
_o, _a, fields = saved(H + ["libplace %d 90 70" % R0])
want = " ## ".join("%s|%s|%s" % (d, "Yes" if s else "No", v) for (t, d, v, s, y) in fields[1:] if t != 4)
check("the list has a row for every field but the reference: Parameter | Show? | Value", rows and rows[0] == "SYMLIST rows " + want, (rows, want))
o, a, f = saved(H + ["libplace %d 90 70" % R0, "selectall", "symlist sel open", "symlist sel click 2 1", "symlist sel close"])
check("a click on Show? turns the field on", f[3][3] == 1 - fields[3][3] and [x[3] for i, x in enumerate(f) if i != 3] == [x[3] for i, x in enumerate(fields) if i != 3], (f[3], fields[3]))
o, a, f = saved(H + ["libplace %d 90 70" % R0, "selectall", "symlist sel open", "symlist sel click 2 1", "symlist sel close", "undo"])
check("Undo turns it back (one step)", f == fields, (f[3], fields[3]))
o, a, f = saved(H + ["libplace %d 90 70" % R0, "selectall", "symlist sel open", "symlist sel click 3 2", "symlist sel type 12 V", "symlist sel enter", "symlist sel close"])
check("a click on a Value edits it (Enter keeps it)", f[4][2] == "12 V" and f[3][2] == fields[3][2], f[:6])
o, a, f = saved(H + ["libplace %d 90 70" % R0, "selectall", "symlist sel open", "symlist sel click 3 2", "symlist sel type 12 V", "symlist sel escape", "symlist sel close"])
check("Esc drops the edit (the list stays open: one Esc for the edit)", f == fields and any(l.startswith("SYMLIST escape") for l in o), (f[3:5], fields[3:5]))
o = run(H + ["libplace %d 90 70" % R0, "selectall", "symlist sel open", "symlist sel click 3 0", "symlist sel state", "symlist sel click 3 1"])
check("the name of a parameter that comes from the library cannot be edited, and Delete is off for it", "SYMLIST click none" in o and any("delete=0 editing=0" in l for l in o), o[-4:])
ymax = max(y for (_t, _d, _v, _s, y) in fields)
o, a, f = saved(H + ["libplace %d 90 70" % R0, "selectall", "symlist sel open", "symlist sel add", "symlist sel state", "symlist sel close"])
check("Add puts a parameter 'Other' = '..' (shown, added here) one line below the lowest", len(f) == len(fields) + 1 and f[-1][:4] == (3, "Other", "..", 1) and abs(f[-1][4] - (ymax + 2.4)) < 0.01, (f[-1], ymax))
last = len(fields) - 2      # the row of the new parameter (the reference has none)
o, a, f = saved(H + ["libplace %d 90 70" % R0, "selectall", "symlist sel open", "symlist sel add", "symlist sel click %d 0" % (last + 1), "symlist sel type Voltage", "symlist sel enter",
                     "symlist sel click %d 2" % (last + 1), "symlist sel type 24 V", "symlist sel enter", "symlist sel state", "symlist sel close"])
check("an added parameter can be renamed and given a value", f[-1][1:3] == ("Voltage", "24 V"), f[-1])
check("... and Delete is on only for it", any("delete=1" in l for l in o if l.startswith("SYMLIST state")), o[-3:])
o, a, f = saved(H + ["libplace %d 90 70" % R0, "selectall", "symlist sel open", "symlist sel add", "symlist sel click %d 0" % (last + 1), "symlist sel delete", "symlist sel close"])
check("Delete takes the added parameter away", f == fields, (len(f), len(fields)))
o, a, f = saved(H + ["libplace %d 90 70" % R0, "selectall", "symlist sel open", "symlist sel add", "symlist sel close", "undo"])
check("Undo takes the added parameter away (one step)", f == fields, (len(f), len(fields)))
# 7. the list of the symbol being placed
o, a, f = saved(H + ["libbegin %d" % R0, "symlist tool open", "symlist tool click 2 1", "symlist tool add", "symlist tool close", "clickmm 90 70"])
check("the symbol being placed can have its parameters changed before it is put down", len(f) == len(fields) + 1 and f[3][3] == 1 - fields[3][3] and f[-1][1] == "Other", (len(f), f[3]))
# 8. several symbols selected: only the parameters they all have, changes go to all of them, the label counts them, the grip resizes
def listable(fl):
    """(description, occurrence) -> (show, value) of the fields the list shows: not the reference (the first), not the always hidden (type 4)"""
    out = {}; seen = {}
    for i, (t, d, v, sh, y) in enumerate(fl):
        if i == 0 or t == 4: continue
        k = seen.get(d, 0); seen[d] = k + 1; out[(d, k)] = (sh, v, t)
    return out
two = H + ["libplace %d 90 70" % R0, "libplace %d 90 140" % R0, "selectall"]
o = run(two + ["symlist sel open", "symlist sel count", "symlist sel rows", "symlist sel size"])
cnt2 = [l for l in o if l.startswith("SYMLIST count")]; rows2 = [l for l in o if l.startswith("SYMLIST rows")]
check("the label above the list says how many symbols are selected", cnt2 == ["SYMLIST count 2 symbols selected"], cnt2)
check("two of the same symbol list the same parameters as one", rows2 and rows2[0] == rows[0], (rows2, rows))
sz = [l for l in o if l.startswith("SYMLIST size")]
check("the label is above the grid", sz and int(re.search(r"labelTop=(\d+) gridTop=(\d+)", sz[0]).group(1)) < int(re.search(r"gridTop=(\d+)", sz[0]).group(1)), sz)
o, a, f2 = saved(two + ["symlist sel open", "symlist sel click 2 1", "symlist sel close"])
n1 = len(fields)
check("Show? on two symbols turns the field over in both", len(f2) == 2 * n1 and f2[3][3] == 1 - fields[3][3] and f2[n1 + 3][3] == 1 - fields[3][3] and [x[3] for i, x in enumerate(f2) if i not in (3, n1 + 3)] == [x[3] for i, x in enumerate(fields + fields) if i not in (3, n1 + 3)], (f2[3], f2[n1 + 3]))
o, a, f2 = saved(two + ["symlist sel open", "symlist sel click 3 2", "symlist sel type 12 V", "symlist sel enter", "symlist sel close"])
check("a value typed for two symbols goes to both", len(f2) == 2 * n1 and f2[4][2] == "12 V" and f2[n1 + 4][2] == "12 V", (f2[4], f2[n1 + 4]))
o, a, f2 = saved(two + ["symlist sel open", "symlist sel add", "symlist sel close"])
check("Add puts the new parameter on both", len(f2) == 2 * n1 + 2 and f2[n1][1] == "Other" and f2[-1][1] == "Other", [x[1] for x in f2][-4:])
o, a, f2 = saved(two + ["symlist sel open", "symlist sel add", "symlist sel click %d 0" % (last + 1), "symlist sel delete", "symlist sel close"])
check("Delete takes it from both", f2 == fields + fields, (len(f2), 2 * n1))
o, a, f2 = saved(two + ["symlist sel open", "symlist sel click 2 1", "symlist sel close", "undo"])
check("all of it is one undo step", f2 == fields + fields, None)
# different symbols: only what both have
c = sqlite3.connect(LIB); names = [r[0] for r in c.execute("select Name from Name where Type=0")]; c.close()
other = None; fb_all = None
for nm in sorted(names, key=str.lower):
    if nm == "BUZZER": continue
    _o, _a, fl = saved(H + ["libplace %d 90 70" % row_of(LIB, nm)])
    if set(k for k in listable(fl)) != set(k for k in listable(fields)) and len(fl) > 2: other = nm; fb_all = fl; break
check("(a second symbol with other parameters was found for the test)", other is not None)
R1 = row_of(LIB, other)
fa, fb = listable(fields), listable(fb_all)
common = [k for k in fa if k in fb]
want = []
for k in fa:
    if k not in fb: continue
    (sa, va, ta), (sb, vb, tb) = fa[k], fb[k]
    want.append("%s|%s|%s" % (k[0], "Yes" if sa and sb else ("No" if not sa and not sb else "Mixed"), va if va == vb else "(varies)"))
o = run(H + ["libplace %d 90 70" % R0, "libplace %d 90 140" % R1, "selectall", "symlist sel open", "symlist sel rows"])
rr = [l for l in o if l.startswith("SYMLIST rows")]
check("two different symbols (%s, %s): only the parameters both have are listed, with Mixed / (varies) where they differ" % ("BUZZER", other), rr and rr[0] == "SYMLIST rows " + " ## ".join(want) and len(want) < max(len(fa), len(fb)), (rr, want))
pk = [i for i, w in enumerate(want) if w.startswith("Package|No|")]
check("(a common parameter, Package, is hidden in both)", bool(pk), want)
if pk:
    seq = H + ["libplace %d 90 70" % R0, "selectall", "symlist sel open", "symlist sel click %d 1" % pk[0], "symlist sel close", "libplace %d 90 140" % R1, "selectall", "symlist sel open", "symlist sel rows",
               "symlist sel click %d 1" % pk[0], "symlist sel rows", "symlist sel close"]
    o, a_, fm = saved(seq)
    rr = [l for l in o if l.startswith("SYMLIST rows")]
    r1 = rr[-2].split(" ## ")[pk[0]]; r2 = rr[-1].split(" ## ")[pk[0]]
    check("one symbol shows Package, the other does not: the list says Mixed; a click shows it in both", r1.startswith("Package|Mixed|") and r2.startswith("Package|Yes|") and [x[3] for x in fm if x[1] == "Package"] == [1, 1], (r1, r2, [x for x in fm if x[1] == "Package"]))
# the grip
o = run(two + ["symlist sel open", "symlist sel size 100 100", "symlist sel size", "symlist sel size 420 330", "symlist sel size 300 220", "symlist sel size 3000 3000"])
S = [re.match(r"SYMLIST size (\d+)x(\d+) .*value=(\d+) .*minw=(\d+)", l).groups() for l in o if l.startswith("SYMLIST size")]
mw = int(S[0][3]); mh = round(mw * 220 / 300)
check("the list cannot be made smaller than 300 x 220 (scaled to the screen's dpi: %dx%d here)" % (mw, mh), 300 <= mw <= 360 and [x[:2] for x in S[:2]] == [(str(mw), str(mh))] * 2 and S[3][:2] == (str(mw), str(mh)), S)
check("... and grows to a size asked for, but not past the screen", S[2][:2] == ("420", "330") and int(S[4][0]) <= 1600 and int(S[4][1]) <= 1000, S)
check("the Value column follows the width (it gains at least the width, more when the taller list needs no scroll bar)", int(S[2][2]) - int(S[3][2]) >= 420 - mw, S)
# the parameter button: the left part switches auto-show on and off, the arrow opens the list once
o = run(H + ["libplace %d 90 70" % R0, "selectall", "symlist sel autostate", "symlist sel autoclick", "symlist sel autoclick", "symlist sel open", "symlist sel autostate"])
A = [l for l in o if l.startswith("SYMLIST auto")]
check("the button starts off; a click on its main part turns it on and opens the list, the next click turns it off and closes it, the arrow (open) leaves it off",
      A[:3] == ["SYMLIST autostate off closed nolist", "SYMLIST autoclick on open list", "SYMLIST autoclick off closed list"] and A[3].startswith("SYMLIST autostate off"), A)
# a parameter added here is named, then Show? is clicked: the grid reports the edit finished once more when the list has been rebuilt, with nothing in the editor; that must not blank the name
o = run(H + ["libplace %d 90 70" % R0, "tool select", "selectall", "symlist sel open", "symlist sel add", "symlist sel click 10 0", "symlist sel type Fuse Type", "symlist sel click 10 1", "symlist sel rows",
             "symlist sel stale 10 -", "symlist sel rows"])
R = [l for l in o if l.startswith("SYMLIST rows")]
check("naming an added parameter and then hiding it keeps the name, also when the grid's late empty report arrives", len(R) == 2 and R[0].endswith("Fuse Type|No|..") and R[1] == R[0], R)
# a symbol pressed on with the list switched on: the list must not open under the held button (it would take the release and leave the sheet dragging the symbol); it opens at the release
o = run(H + ["libplace %d 90 70" % R0, "tool select", "selectall", "symlist sel autoclick", "symlist sel close", "selclear", "mouse move 86 50", "mouse down 86 50", "dragmode", "symlist sel state",
             "mouse move 90 55", "symlist sel state", "mouse up 90 55", "dragmode", "symlist sel state"])
A = [l[len("SYMLIST "):] for l in o if l.startswith("SYMLIST state")]; D = [l for l in o if l.startswith("DRAGMODE")]
check("pressing on a symbol with the list switched on: the drag begins, the list waits while the button is down, then opens at the release", D == ["DRAGMODE 1", "DRAGMODE 0"] and A[0] == "state nolist" and A[1] == "state nolist" and A[2].startswith("state visible=1"), (D, A))
o = run(H + ["libplace %d 90 70" % R0, "libplace %d 150 70" % R0, "selectall", "symlist sel autoclick", "symlist sel close", "undo", "selectall", "symlist sel autostate"])
A = [l for l in o if l.startswith("SYMLIST auto")]
check("switched on, the list opens by itself when a symbol is selected (and the state is kept for the new frame)", A[-1:] == ["SYMLIST autostate on open list"], A)
o = run(H + ["libplace %d 90 70" % R0, "libplace %d 150 70" % R0, "selectall", "symlist sel autostate", "undo", "selectall", "symlist sel autostate"])
A = [l for l in o if l.startswith("SYMLIST auto")]
check("switched off, selecting does not open it", A[-1:] == ["SYMLIST autostate off closed nolist"], A)
print("%d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
