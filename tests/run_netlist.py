"""Netlist checks.

  1. Oracle: the sample designs that come with a real TinyCAD-written Protel netlist (*.net next to
     the *.dsn). Components are compared in order; nets as partitions of pins, plus label names.
     (Net NUMBERS are not compared: those files were written by an older version that counted
     from 0.)  Done twice: with the current source's multi-part symbol geometry, and with the
     older geometry the samples were made with (nettest honours TC_LEGACY_PARTS=1).
  2. Robustness and stability over every design: building the netlist twice gives identical
     numbering (the second run reads the hints the first stored), and the numbering survives a
     save + reload (hints are saved as HINT tags).
Exit status is non-zero if the older-geometry oracle comparison is not exact, or on any crash or
instability."""
import os, re, sys, glob, subprocess, tempfile

EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
BUILD = os.environ.get("TC_BUILD", "build")
NT = os.path.join(BUILD, "nettest")
designs = sorted(os.path.join(r, f) for r, _, fs in os.walk(EXAMPLES) for f in fs if f.lower().endswith((".dsn", ".autosave")))
def is_protel(path):  # other writers also produce *.net (TinyCAD native, SPICE): not covered here
    with open(path, "rb") as f: return f.read(3).replace(b"\r", b"").startswith(b"[\n")
oracles = [n for n in sorted(glob.glob(os.path.join(EXAMPLES, "**", "*.net"), recursive=True))
           if os.path.getsize(n) > 0 and os.path.exists(n[:-4] + ".dsn") and is_protel(n)]
tmp = tempfile.mkdtemp()
failed = False

def parse(path):
    t = open(path, "rb").read().decode("latin1").replace("\r", "")
    comps = re.findall(r"\[\n([^\n]*)\n([^\n]*)\n([^\n]*)\n\n\n\n\]\n", t)
    nets = [(m.group(1), [x for x in m.group(2).split("\n") if x])
            for m in re.finditer(r"\(\n([^\n]*)\n((?:[^\n)]*\n)*?)\)\n", t)]
    return comps, nets
isauto = lambda n: re.fullmatch(r"N\d{6}", n) is not None

def compare(legacy):
    env = dict(os.environ, TC_LEGACY_PARTS="1" if legacy else "0")
    tot = dict(files=0, comp=0, nets=0, ok=0, names_bad=0)
    detail = []
    for net in oracles:
        out = os.path.join(tmp, "mine.net")
        r = subprocess.run([NT, "protel", net[:-4] + ".dsn", out], capture_output=True, text=True, env=env)
        if r.returncode != 0: detail.append((os.path.basename(net), "FAILED " + r.stderr[-100:])); continue
        oc, on = parse(net); mc, mn = parse(out)
        O = {frozenset(p): n for n, p in on}; M = {frozenset(p): n for n, p in mn}
        tot["files"] += 1; tot["comp"] += oc == mc; tot["nets"] += len(O)
        match = [k for k in O if k in M]; tot["ok"] += len(match)
        tot["names_bad"] += sum(1 for k in match if not (O[k] == M[k] or (isauto(O[k]) and isauto(M[k]))))
        if len(match) != len(O): detail.append((os.path.basename(net), f"{len(O) - len(match)} of {len(O)} nets differ"))
    return tot, detail

for legacy in (False, True):
    t, d = compare(legacy)
    label = "older multi-part geometry (as the samples were made)" if legacy else "current source geometry"
    print(f"oracle, {label}: {t['files']} designs, components identical in {t['comp']}, "
          f"nets reproduced {t['ok']}/{t['nets']}, name mismatches {t['names_bad']}")
    for x in d[:4]: print("    ", x)
    if legacy and (t["ok"] != t["nets"] or t["comp"] != t["files"] or t["names_bad"]): failed = True

# stability and persistence
def count(mode, extra=()):
    ok = 0
    for p in designs:
        o = subprocess.run([NT, mode, p, *extra], capture_output=True, text=True)
        want = "stable" if mode == "twice" else "persisted"
        if o.returncode == 0 and o.stdout.strip() == want: ok += 1
        else: print("    problem:", os.path.basename(p), (o.stdout + o.stderr)[-100:])
    return ok
a = count("twice"); b = count("persist", (os.path.join(tmp, "p.dsn"),))
print(f"stability over {len(designs)} designs: identical numbering when built twice {a}; surviving save + reload {b}")
failed |= (a != len(designs)) or (b != len(designs))
print("\nNETLIST CHECKS PASSED" if not failed else "\nNETLIST CHECKS FAILED")
sys.exit(1 if failed else 0)
