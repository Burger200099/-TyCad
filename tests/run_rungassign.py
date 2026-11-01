#!/usr/bin/env python3
"""Which rung a symbol belongs to (ULinks.RungOfObject, Special/right-click Rung): the rung its connection points sit in; when they span several rungs, the one the symbol's box overlaps
most; a tie is flagged ambiguous and the lowest is used; a rung chosen on the symbol wins, is saved as the rung attribute of the SYMBOL, is one undo step and Automatic clears it.
Oracles: the rung grid's area and row height as the program reports them (rungs), the pins (pinsof) and the symbol's box (rung ... box=) - the rule restated here in Python;
the saved design read as text. Needs xvfb-run, the built program and the example libraries (TC_EXAMPLES)."""
import os, re, sys, shutil, sqlite3, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
LIB = os.path.join(EX, "libraries", "gen_passive.TCLib")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not os.path.exists(LIB):
    print("Rung assignment checks skipped: need xvfb-run, the built program and the example libraries"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:600])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    return subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=600, env=env).stdout.splitlines()
c = sqlite3.connect(LIB); names = sorted([r[0] for r in c.execute("select Name from Name where Type=0")], key=str.lower); c.close()
RES = names.index("R")
H = ["newdoc A4", "registerframe method all", "lib " + LIB, "rungs", "setrungs 10 1 10 1", "rungs"]
def model(pins, box, top, left, right, rh, rows, start):
    """the rule restated: rows of the pins inside the area; one -> it; several -> most overlap with the box, a tie -> lowest and ambiguous"""
    rs = sorted({int((y - top) // rh) for x, y in pins if left <= x <= right and top <= y <= top + rows * rh})
    if not rs: return None
    nums = [start + r for r in rs]
    if len(rs) == 1: return start + rs[0], False, nums
    rs = sorted(set(rs) | {r for r in range(rows) if min(box[1], top + (r + 1) * rh) - max(box[0], top + r * rh) > rh * 1e-6})   # (the rows the box crosses are candidates too)
    nums = [start + r for r in rs]
    ov = [max(0.0, min(box[1], top + (r + 1) * rh) - max(box[0], top + r * rh)) for r in rs]
    m = max(ov); best = [r for r, v in zip(rs, ov) if abs(v - m) < rh * 1e-6]
    return start + best[0], len(best) > 1, nums
# ---- sweep resistors down the sheet in one run: each is chosen in turn and its rung read
ys = [18 + 3.7 * i for i in range(48)]
lines = list(H) + ["libplace %d %s %s" % (RES, 40 + 4 * (i % 20), y) for i, y in enumerate(ys)]
for k in range(len(ys)): lines += ["selidx %d" % (k + 1), "rung"]
lines += ["pinsof"]
o = run(lines)
ar = [l for l in o if l.startswith("RUNGAREA")][-1].split()
left, top, right, bottom = float(ar[1]), float(ar[2]), float(ar[3]), float(ar[4]); rh = float(re.search(r"rowh=([\d.]+)", " ".join(ar)).group(1))
pins = {}
for l in o:
    if l.startswith("PIN "):
        q = l.split(); pins.setdefault(int(q[1]), []).append((float(q[3]) / 5, float(q[4]) / 5))
rl = [l for l in o if l.startswith("RUNG ") and "SET" not in l]
check("a rung line for each symbol", len(rl) == len(ys), (len(rl), len(ys)))
bad = 0; seen = {"one": 0, "span": 0, "amb": 0, "none": 0}
for k, l in enumerate(rl):
    m = re.match(r"RUNG (\d) (\d+) amb=(\d) over=(\d) cand=([\d,]*) box=([-\d.]+),([-\d.]+)", l)
    found, num, amb, over, cand, b0, b1 = int(m[1]), int(m[2]), int(m[3]), int(m[4]), m[5], float(m[6]), float(m[7])
    exp = model(pins.get(k, []), (b0, b1), top, left, right, rh, 10, 1)
    ok = (exp is None and not found) or (exp is not None and found and (num, bool(amb)) == exp[:2] and [int(x) for x in cand.split(",") if x] == exp[2] and not over)
    if exp is None: seen["none"] += 1
    else: seen["one" if len(exp[2]) == 1 else "span"] += 1
    if exp and exp[1]: seen["amb"] += 1
    if not ok:
        bad += 1
        if bad <= 3: print("   y", ys[k], "pins", pins.get(k), "box", (b0, b1), "got", l, "want", exp)
check("the sweep: every position gives the rung the rule gives", bad == 0, bad)
print("  sweep:", seen)
check("the sweep covered pins in one row and pins spanning rows", seen["one"] > 5 and seen["span"] > 3, seen)
# ---- a tie: with 6 rungs and a 10 mm margin the line between rungs 2 and 3 is at 77.5 mm (top 16.5 mm, rung height 30.5 mm); the resistor's box is 14 mm tall (the program reports
# it), so with its box 70.5..84.5 it overlaps both rungs by 7 mm (the placement lands on the grid, so the margin is chosen to put the line where a box can be centred on it)
T = ["newdoc A4", "registerframe method all", "lib " + LIB, "rungs", "setrungs 6 1 10.15 1", "gridmm 0.05"]
o = run(T + ["libplace %d 90 84.35" % RES, "selidx 1", "rung"])
r = [l for l in o if l.startswith("RUNG ")][-1]
check("equal overlap of two rungs is ambiguous and takes the lowest (rung 2)", "RUNG 1 2 amb=1 over=0 cand=2,3" in r and "box=70.5,84.5" in r, r)
o = run(T + ["libplace %d 90 86.35" % RES, "selidx 1", "rung"])
r = [l for l in o if l.startswith("RUNG ")][-1]
check("2 mm lower it overlaps rung 3 more: rung 3, no longer a tie", "RUNG 1 3 amb=0 over=0 cand=2,3" in r, r)
# ---- the right-click menu: a symbol that spans rungs has Rung > Automatic, 2, 3; choosing 3 keeps it; a symbol in one rung has no Rung item
o = run(T + ["libplace %d 90 84.35" % RES, "ctxmenu 90 77"] + ["ctxclick Rung/3", "rung", "ctxmenu 90 77"])
ctx = [l for l in o if l.startswith("CTX ") and "done" not in l]
first = ctx[:ctx.index("CTX 0 Undo enabled=1 key=[Ctrl+Z]")] if "CTX 0 Undo enabled=1 key=[Ctrl+Z]" in ctx else ctx
check("the Rung item lists Automatic and the two rungs the symbol is in", [l.split()[2] for l in first if (l.startswith("CTX 1 ") or " Rung " in l) and l.split()[2] != "-"] == ["Rung", "Automatic", "2", "3"], first)
r = [l for l in o if l.startswith("RUNG ")]
check("choosing 3 in the menu keeps rung 3 on the symbol", r and "RUNG 1 3 amb=0 over=1" in r[-1], r)
o = run(T + ["libplace %d 90 75" % RES, "ctxmenu 90 68"])
check("a symbol inside one rung has no Rung item", not any(" Rung " in l for l in o if l.startswith("CTX ")), [l for l in o if l.startswith("CTX ")][:3])
# ---- choose, save, undo, automatic
base = H + ["libplace %d 90 60" % RES, "selidx 1", "rung"]
o = run(base); r = [l for l in o if l.startswith("RUNG ") and "SET" not in l][-1]
m = re.match(r"RUNG 1 (\d+) amb=(\d) over=0 cand=([\d,]*)", r)
check("a placed resistor has a rung", m is not None, r)
f = os.path.join(tmp, "o.dsn")
other = (int(m[1]) % 10) + 1 if m else 3
o = run(base + ["rung set %d" % other, "rung", "savedocas " + f]); r = [l for l in o if l.startswith("RUNG ") and "SET" not in l]
t = open(f, encoding="utf-8", errors="replace").read() if os.path.exists(f) else ""
check("a chosen rung is used (over=1)", r and ("RUNG 1 %d " % other) in r[-1] and "over=1" in r[-1], r)
check("... and saved as the rung attribute of the SYMBOL", re.search(r"<SYMBOL [^>]*rung='%d'" % other, t) is not None, t[:200])
o = run(base + ["rung set %d" % other, "undo", "rung"]); r = [l for l in o if l.startswith("RUNG ") and "SET" not in l]
check("undo takes the choice back in one step", r and "over=0" in r[-1] and ("RUNG 1 %d " % int(m[1])) in r[-1], r)
o = run(base + ["rung set %d" % other, "rung auto", "rung", "savedocas " + f]); r = [l for l in o if l.startswith("RUNG ") and "SET" not in l]
t = open(f, encoding="utf-8", errors="replace").read()
check("Automatic follows the position again and removes the attribute", r and "over=0" in r[-1] and "rung='" not in t, (r, t[:100]))
if fails: print("rung assignment: %d checks, %d failed" % (n[0], len(fails))); sys.exit(1)
print("rung assignment: %d checks, 0 failed" % n[0])
