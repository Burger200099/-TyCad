"""Placed-symbol geometry checks on real files.

  1. REF_POINT oracle: every reference point saved by the C++ program is recomputed from scratch.
     Mismatches are re-tried with the settings the C++ program may have had at placement time
     (grid 10, snapping off); anything still different is reported as unexplained.
  2. Placements in the sample designs and, for every library symbol, in all 8 rotations with power
     pins on and off: draw path vs netlist path, rigid rotation, hit test, bounding box, replace.
  3. Field label positions (information only: users can drag shown labels).
Exit status is non-zero if anything is unexplained or any placement check fails."""
import os, sys, glob, subprocess

EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
BUILD = os.environ.get("TC_BUILD", "build")
DT = os.path.join(BUILD, "designtest")
LT = os.path.join(BUILD, "libtest")
env = dict(os.environ)
designs = sorted(os.path.join(r, f) for r, _, fs in os.walk(EXAMPLES) for f in fs if f.lower().endswith((".dsn", ".autosave")))
libs = sorted(glob.glob(os.path.join(EXAMPLES, "libraries", "*.TCLib")))
failed = False

# ---- 1. reference point oracle ----
def entries(args):
    d = {}
    for p in designs:
        o = subprocess.run([DT, "refs", p] + args, capture_output=True, text=True, env=env)
        for i, l in enumerate(o.stdout.split("\n")):
            if l.startswith("REF "):
                n, part, pw, fx, fy, cx, cy, het, nm = l[4:].split("|")
                d[(p, i)] = (n, float(fx), float(fy), float(cx), float(cy))
    return d
ok = lambda e: abs(e[1] - e[3]) < 1e-4 and abs(e[2] - e[4]) < 1e-4
base, g10, nosnap = entries(["0"]), entries(["0", "10"]), entries(["0", "0", "0"])
bad = [k for k, e in base.items() if not ok(e)]
fix10 = {k for k in bad if ok(g10[k])}; fixns = {k for k in bad if ok(nosnap[k])}
left = [k for k in bad if k not in fix10 | fixns]
print(f"REF_POINT oracle: {len(base)} saved points; {len(base) - len(bad)} reproduced with the file's own settings;")
print(f"   of {len(bad)} others: {len(fix10)} reproduced with grid 10, {len(fixns - fix10)} more with snapping off; unexplained {len(left)}")
for k in left[:5]: print("   unexplained:", os.path.basename(k[0]), base[k])
failed |= bool(left)

# ---- 2. placements ----
def total(cmd, items):
    tot = [0] * 8
    for p in items:
        o = subprocess.run([cmd[0], cmd[1], p], capture_output=True, text=True, env=env)
        last = [l for l in o.stdout.split("\n") if l.startswith("placed ")]
        if not last: print("  FAILED to run", p, (o.stdout + o.stderr)[-200:]); return None
        tot = [a + b for a, b in zip(tot, map(int, last[0].split()[1:]))]
    return tot
for label, cmd, items in (("sample designs", (DT, "placed"), designs), ("library symbols x 8 rotations x power on/off", (LT, "placed"), libs)):
    if not items: continue
    t = total(cmd, items)
    if t is None: failed = True; continue
    print(f"placements, {label}: {t[0]} placements, {t[1]} visible pins | draw-vs-netlist {t[2]} | rotation {t[3]} | hit {t[4]} | box {t[5]} | replace {t[6]} bad"
          f" | {t[7]} frame-inconsistent excluded from box/hit")
    failed |= any(t[2:7])

# ---- 3. field labels (information only) ----
tot = [0, 0]
for p in designs:
    o = subprocess.run([DT, "fields", p], capture_output=True, text=True, env=env)
    last = [l for l in o.stdout.split("\n") if l.startswith("fields ")]
    if last:
        v = list(map(int, last[0].split()[1:])); tot[0] += v[2]; tot[1] += v[3]
print(f"field label positions recomputed by NewRotation: {tot[1]}/{tot[0]} equal the saved ones (shown labels are often dragged by hand)")
print("\nPLACED-SYMBOL CHECKS PASSED" if not failed else "\nPLACED-SYMBOL CHECKS FAILED")
sys.exit(1 if failed else 0)
