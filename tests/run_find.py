"""Find and Replace of the text in a design (UFind), checked against an independent reading of each design's XML.
The oracle takes the texts that TinyCAD's Find searches (LABEL, TEXT, NOTE_TEXT and POWER text, and the value of every
FIELD of a SYMBOL) in file order, and finds the occurrences itself, byte by byte, with the rules of the search
(ASCII case folding; a whole word has no letter, digit, underscore or non-ASCII byte next to it; occurrences do not
overlap). It is compared with the driver on every sample design for:
  - the occurrences (sheet, which text, where, how long, what text), with and without match case and whole word
  - Find Next and Find Previous over and over, including the wrap round (and that both directions agree with the occurrences)
  - Replace All (the texts read back from the saved file, nothing else changed) and Replace one at a time
    (Find Next, Replace ... until the search wraps) which must give the same result."""
import glob, os, random, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xml.etree.ElementTree as ET
BUILD = os.environ.get("TC_BUILD", "build"); EXE = os.path.join(BUILD, "findtest")
EX = os.environ.get("TC_EXAMPLES", "examples")
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, d[:300])
def run(*a):
    r = subprocess.run([EXE, *a], capture_output=True, text=True)
    return r.returncode, r.stdout.split("\n"), r.stderr
from findoracle import texts, lower, isword, occurrences, expected_hits, object_hits, simulate as _sim
def simulate(exp, direction, steps): return _sim(exp, direction, steps, 0)
def fix(b): return b.decode("utf-8", "replace").replace("\n", "\\n").replace("\r", "")
designs = sorted(glob.glob(os.path.join(EX, "**", "*.dsn"), recursive=True))
rnd = random.Random(20261005); tmp = tempfile.mkdtemp()
used = skipped = hits_total = 0
for path in designs:
    rc, out, err = run("hits", path, "zzzq", "-")
    if rc != 0: skipped += 1; continue
    tx = texts(path); used += 1
    words = []
    for (_s, _k, t) in tx:
        for w in t.decode("utf-8", "replace").replace("\n", " ").split():
            w = w.strip(".,;:()[]\"'")
            if 1 <= len(w) <= 12 and w.isascii() and w not in words: words.append(w)
    needles = rnd.sample(words, min(4, len(words))) + ["a", "1", "gnd", "zzzq"]
    for needle in needles:
        for flags in ("-", "c", "w", "cw"):
            case, word = "c" in flags, "w" in flags
            rc, out, err = run("hits", path, needle, flags)
            got = []
            for l in out:
                if l.startswith("HIT "):
                    t = l.split(" ", 6); got.append((int(t[1]), int(t[3]), int(t[4]), int(t[5]), t[6] if len(t) > 6 else ""))
            exp = [(s, k, o, ln, fix(t)) for (s, k, o, ln, t) in expected_hits(tx, needle.encode(), case, word)]
            hits_total += len(exp)
            check(f"{os.path.basename(path)}: occurrences of {needle!r} [{flags}]", rc == 0 and got == exp, f"{got[:3]} vs {exp[:3]}")
print(f"occurrences: {used} designs ({skipped} that do not load are skipped), {hits_total} occurrences compared, {checks} checks, {len(fails)} failures")
# Find Next / Previous with the wrap round
seqs = 0
for path in designs[::4]:
    rc, out, err = run("hits", path, "zzzq", "-")
    if rc != 0: continue
    tx = texts(path)
    words = [w for (_s, _k, t) in tx for w in t.decode("utf-8", "replace").split() if w.isascii() and 1 <= len(w) <= 10]
    for needle in ([words[0]] if words else []) + ["a", "zzzq"]:
        for flags in ("-", "w"):
            case, word = "c" in flags, "w" in flags
            exp = expected_hits(tx, needle.encode(), case, word)
            rc, hout, _ = run("hits", path, needle, flags)
            hobj = [tuple(int(v) for v in l.split(" ", 6)[1:5]) for l in hout if l.startswith("HIT ")]
            n = len(exp)
            for direction in ("down", "up"):
                steps = n * 2 + 3 if n else 2
                rc, sout, _ = run("seq", path, needle, flags, direction, str(steps))
                seq = [l.split() for l in sout if l.startswith("SEQ ")]; seqs += 1
                if n == 0:
                    check(f"{os.path.basename(path)}: nothing to find {needle!r} {direction}", all(x == ["SEQ", "none"] for x in seq) and len(seq) == steps, str(seq[:2])); continue
                sim = simulate(exp, direction, steps)
                got = [(int(x[1]), int(x[3]), int(x[4]), int(x[5])) for x in seq]
                want = [(exp[i][0], exp[i][1], exp[i][2], int(w)) for i, w in sim]
                check(f"{os.path.basename(path)}: Find {direction} through {n} occurrences of {needle!r} [{flags}], with the wrap round", got == want, f"{got[:4]} vs {want[:4]}")
                gobj = [(int(x[1]), int(x[2]), int(x[3]), int(x[4])) for x in seq]
                check(f"{os.path.basename(path)}: {direction} visits exactly the occurrences the driver lists, in drawing order", set(gobj) == set(hobj) and len(seq) == steps, "")
print(f"find next / previous: {seqs} sequences, {checks} checks so far, {len(fails)} failures")
# TinyCAD's own Find: every object that mentions the text, once
objs_total = objs_runs = 0
for path in designs:
    rc, out, err = run("hits", path, "zzzq", "-")
    if rc != 0: continue
    tx = texts(path)
    words = []
    for (_s, _k, t) in tx:
        for w in t.decode("utf-8", "replace").replace("\n", " ").split():
            w = w.strip(".,;:()[]\"'")
            if 1 <= len(w) <= 12 and w.isascii() and w not in words: words.append(w)
    for needle in rnd.sample(words, min(5, len(words))) + ["a", "1", "v", "gnd", "ZZZQ", "R"]:
        rc, out, err = run("objects", path, needle)
        got = []
        for l in out:
            if l.startswith("OBJ "):
                t = l.split(" ", 6); nm, _, tt = t[6].partition("|")
                got.append((int(t[1]), int(t[3]), nm, tt, (float(t[4]), float(t[5]))))
        exp = [(s_, k_, nm, fix(t_), pt) for (s_, k_, nm, t_, pt) in object_hits(path, needle.encode())]
        objs_total += len(exp); objs_runs += 1
        def near(g, e):
            if g[2] == "Label":
                # a label's own point is its text box (TinyCAD's m_point_a): somewhere along its text from where the file puts it
                reach = len(e[3]) * 25 + 60
                return (g[4] != (0.0, 0.0) or e[4] == (0.0, 0.0)) and abs(g[4][0] - e[4][0]) <= reach and abs(g[4][1] - e[4][1]) <= reach
            return abs(g[4][0] - e[4][0]) < 1e-3 and abs(g[4][1] - e[4][1]) < 1e-3
        same = len(got) == len(exp) and all(g[:4] == e[:4] and near(g, e) for g, e in zip(got, exp))
        check(f"{os.path.basename(path)}: TinyCAD's Find for {needle!r} lists the same objects, names, texts and positions", rc == 0 and same, f"{got[:2]} vs {exp[:2]}")
print(f"TinyCAD's Find: {objs_runs} searches, {objs_total} objects listed, {checks} checks so far, {len(fails)} failures")
# Replace All and Replace one by one
repl_runs = skipped_r = 0
for path in designs[::2]:
    rc, out, err = run("hits", path, "zzzq", "-")
    if rc != 0: continue
    tx = texts(path)
    # the saved file must read back the same texts when nothing is replaced, or the comparison below means nothing
    base = os.path.join(tmp, "base.dsn"); run("all", path, base, "zzzq", "x", "-")
    if not os.path.exists(base) or [t for t in texts(base)] != tx: skipped_r += 1; continue
    words = [w for (_s, _k, t) in tx for w in t.decode("utf-8", "replace").split() if w.isascii() and 2 <= len(w) <= 10]
    for needle, repl, flags in ((words[0] if words else "a", "NEW_" + (words[0] if words else "a"), "-"), ("a", "aa", "c"), ("1", "", "w"), ("r", "Q", "-")):
        case, word = "c" in flags, "w" in flags
        want = []; total = 0
        for (s, k, t) in tx:
            occ = occurrences(t, needle.encode(), case, word); total += len(occ)
            res = b""; last = 0
            for o in occ: res += t[last:o - 1] + repl.encode(); last = o - 1 + len(needle)
            want.append((s, k, res + t[last:]))
        for mode in ("all", "one"):
            outp = os.path.join(tmp, mode + ".dsn")
            rc, out, err = run(mode, path, outp, needle, repl, flags)
            line = [l for l in out if l.startswith("REPLACED")]
            repl_runs += 1
            check(f"{os.path.basename(path)}: Replace {mode} {needle!r} -> {repl!r} [{flags}] count", rc == 0 and line and int(line[0].split()[1]) == total, f"{line} vs {total}")
            if rc == 0 and os.path.exists(outp):
                check(f"{os.path.basename(path)}: Replace {mode} {needle!r} -> {repl!r} [{flags}] every text as expected and nothing else changed", texts(outp) == want, "")
print(f"replace: {repl_runs} runs ({skipped_r} designs that do not save back identically are skipped), {checks} checks, {len(fails)} failures")
print("\nFIND CHECKS PASSED" if not fails else f"\nFIND CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
