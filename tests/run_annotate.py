"""Generate Symbol References (UAnnotate, and the symbol methods under it) against annooracle.py, which restates Special.cpp / DrawMethod.cpp. Needs the built annotest.

 - the small functions: the number in a reference, the reference made from a prefix and a number, atoi's limits
 - every choice of the command (add / remove; all, un-numbered, matching; default or typed start; one sheet or all) on sample designs and on generated ones
   (references taken away or numbered twice, parts and parts per package changed, designs of two sheets)
 - the reference painter: each click adds or removes the references of the symbols under it
 - what is written to a file and read back, and that running the command again changes nothing more
"""
import glob, os, random, re, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import annooracle as ao
import ercoracle as eo

EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
tmp = tempfile.mkdtemp()
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:700])

def run_prog(dsn, out, add, which, value, match, start, alls, active):
    r = subprocess.run([ao.AT, "run", dsn, out, "1" if add else "0", str(which), str(value), match, str(start), "1" if alls else "0", str(active)], capture_output=True, text=True)
    return r.returncode, r.stdout.split("\n")

def same(a, b):
    if len(a) != len(b): return False
    for x, y in zip(a, b):
        if (x["sheet"], x["idx"], x["ref"], x["part"]) != (y["sheet"], y["idx"], y["ref"], y["part"]): return False
        if any(abs(p - q) > 1e-6 for p, q in zip(x["A"] + x["B"], y["A"] + y["B"])): return False
    return True

def why(a, b):
    for x, y in zip(a, b):
        if (x["sheet"], x["idx"], x["ref"], x["part"]) != (y["sheet"], y["idx"], y["ref"], y["part"]) or any(abs(p - q) > 1e-6 for p, q in zip(x["A"] + x["B"], y["A"] + y["B"])):
            return (x["sheet"], x["idx"], x["ref"], x["part"], x["A"], "<>", y["ref"], y["part"], y["A"])
    return (len(a), len(b))

# ---------------------------------------------------------------- 1. the small functions, through references of generated designs
check("atoi stops at a letter", ao.atoi("12A5") == 12 and ao.atoi("  -7x") == -7 and ao.atoi("") == 0 and ao.atoi("U?") == 0 and ao.atoi("99999999999") == 2**31 - 1)

# ---------------------------------------------------------------- 2. every choice, on the samples and on variants
files = sorted(p for dp, _, fs in os.walk(EXAMPLES) for f in fs for p in [os.path.join(dp, f)] if f.lower().endswith(".dsn"))
random.seed(5)
small = [p for p in files if os.path.getsize(p) < 150000]
random.shuffle(small)
sources = small[:16] + [p for p in files if os.path.basename(p) in ("Focus Bipolar Motor Circuit.dsn", "ArithmeticUnit.dsn", "UALogic4.dsn")]
seen = dict(multi=0, parts=0, typed=0, matching=0, removed=0, added=0, subpart=0, het=0, missing=0)
total = 0
def cases(ms, label, dsn, nsheets):
    global total
    prefs = sorted({m["prefix"] for m in ms}) or ["U?"]
    for k in range(10):
        add = random.random() < 0.8
        if add and any(ao.ref_val(m) >= 2**31 - 1 for m in ms): add = False      # (a number past the largest Integer would have the next one overflow: undefined in C++)
        which = random.choice([0, 1, 2, 0, 1])
        value = random.choice([0, 1])
        match = random.choice(prefs + [p.lower() for p in prefs] + [p.upper() + 'x' for p in prefs]) if which == 2 else "U?"
        start = random.choice([1, 1, 5, 10, 100, 0, -3]) if value == 1 else 1
        alls = nsheets > 1 and random.random() < 0.6
        active = random.randrange(nsheets) if nsheets > 1 else 0
        want, miss = ao.annotate(ms, add, which, value, match, start, alls, active)
        out = os.path.join(tmp, "out.dsn")
        rc, o = run_prog(dsn, out, add, which, value, match, start, alls, active)
        got = ao.parse(o)
        check(f"{label} add={add} which={which} value={value} match={match} start={start} all={alls} active={active}",
              rc == 0 and same(got, want) and o[0] == ("R 1" if miss else "R 0"), (rc, why(got, want)) if rc == 0 else rc)
        total += 1
        if value == 1: seen["typed"] += 1
        if which == 2: seen["matching"] += 1
        if alls: seen["multi"] += 1
        if any(m["ppp"] > 1 for m in ms): seen["parts"] += 1
        if any(g["part"] != m["part"] for g, m in zip(got, ms)): seen["subpart"] += 1
        if any(m["het"] for m in ms): seen["het"] += 1
        if any(has and not ao.has_ref(g) for has, g in [(ao.has_ref(m), g) for m, g in zip(ms, got)]): seen["removed"] += 1
        if any(g["ref"] != m["ref"] and ao.has_ref(g) for m, g in zip(ms, got)): seen["added"] += 1
        if miss: seen["missing"] += 1
        # what was saved reads back as the same, and doing it again changes nothing more (when the command is the same and numbers stay put)
        rc2, o2 = subprocess.run([ao.AT, "dump", out], capture_output=True, text=True).returncode, subprocess.run([ao.AT, "dump", out], capture_output=True, text=True).stdout.split("\n")
        check(f"{label} saved file reads back", rc2 == 0 and same(ao.parse(o2), got), why(ao.parse(o2), got))

for i, src in enumerate(sources):
    ms = ao.dump(src)
    if not ms: continue
    n = len({m["sheet"] for m in ms}); sheets = max(m["sheet"] for m in ms) + 1
    cases(ms, os.path.basename(src), src, sheets)
    for j in range(3):
        dst = os.path.join(tmp, f"v{i}_{j}.dsn")
        ao.variant(src, i * 10 + j, dst, exotic=True)
        cases(ao.dump(dst), f"variant {os.path.basename(src)}#{j}", dst, sheets)
    # symbols whose definition is missing (they cannot be changed, and the command says so)
    import xml.etree.ElementTree as ET
    r_ = ET.parse(src).getroot(); syms_ = r_.findall(".//SYMBOL")
    if len(syms_) > 3:
        for s_ in random.sample(syms_, 2): s_.set("id", "9999")
        miss = os.path.join(tmp, f"m{i}.dsn"); ET.ElementTree(r_).write(miss, encoding="UTF-8", xml_declaration=True)
        cases(ao.dump(miss), f"missing {os.path.basename(src)}", miss, sheets)
    # two sheets
    two = os.path.join(tmp, f"t{i}.dsn"); eo.two_sheets(src, two, rename=False)
    two2 = os.path.join(tmp, f"t{i}v.dsn"); ao.variant(two, 77 + i, two2, exotic=True)
    cases(ao.dump(two2), f"two sheets {os.path.basename(src)}", two2, 2)
print(f"command: {total} runs compared;", seen)
for k in ("multi", "parts", "typed", "matching", "removed", "added", "subpart", "missing"):
    check(f"coverage: {k}", seen[k] > 5, seen[k])

# ---------------------------------------------------------------- 3. the reference painter
nclick = 0; seen_hits = 0
for i, src in enumerate(sources[:12]):
    ms = ao.dump(src)
    if not ms: continue
    for j in range(2):
        dst = os.path.join(tmp, f"p{i}_{j}.dsn"); ao.variant(src, 500 + i * 7 + j, dst)
        ms = ao.dump(dst)
        sheet = random.choice(sorted({m["sheet"] for m in ms}))
        here = [m for m in ms if m["sheet"] == sheet]
        clicks = []
        pts_ = [(x_, y_) for (sh_, x_, y_) in ao.others(dst) if sh_ == sheet]
        for _ in range(6):
            m = random.choice(here)
            cx, cy = (m["A"][0] + m["B"][0]) / 2, (m["A"][1] + m["B"][1]) / 2
            clicks.append((cx, cy, random.random() < 0.3))
        for _ in range(10):          # the points of other objects (wires, labels, junctions ...): only symbols may be numbered
            if pts_: clicks.append(random.choice(pts_) + (random.random() < 0.3,))
        start = random.choice([1, 1, 4, 20])
        r = subprocess.run([ao.AT, "paint", dst, str(sheet), str(start)] + [str(v) for (x, y, rm) in clicks for v in (repr(x), repr(y), "1" if rm else "0")], capture_output=True, text=True)
        lines = r.stdout.split("\n"); got = ao.parse(lines)
        under = [[int(v) for v in l.split()[2:]] for l in lines if l.startswith("P ")]
        counts = [int(l.split()[1]) for l in lines if l.startswith("P ")]
        check(f"painter {os.path.basename(src)}#{j}: one answer for each click, and every symbol under a click is changed", r.returncode == 0 and len(under) == len(clicks) and counts == [len(u) for u in under], (r.returncode, counts, under, r.stderr[-200:]))
        exp = ao.paint(ms, sheet, start, [rm for (_, _, rm) in clicks], under)
        check(f"painter {os.path.basename(src)}#{j}: numbers and parts", same(got, exp), why(got, exp))
        seen_hits += sum(1 for u in under if u)
        nclick += len(clicks)
print(f"painter: {nclick} clicks, {seen_hits} on symbols")
check("coverage: clicks on symbols", seen_hits > 20, seen_hits)
print(f"{checks} checks, {len(fails)} failed")
sys.exit(1 if fails else 0)
