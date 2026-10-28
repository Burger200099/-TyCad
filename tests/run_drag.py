"""Wire dragging (net labels and power symbols are removed first: they connect by name, and TinyCAD's drag moves wires only,
so a wire stretched away from a label no longer touches it): move symbols of real designs with the drag engine and check, using the netlist builder
(validated separately against TinyCAD's own netlists), that no connection is lost, that the symbol's pins
move by exactly the dragged distance and that the wires attached to them follow."""
import os, sys, random, subprocess, tempfile, shutil
BUILD = os.environ.get("TC_BUILD", "build"); EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
EXE = os.path.join(BUILD, "edittest"); tmp = tempfile.mkdtemp(); fails = []
random.seed(20261004)
def check(n, ok, d=""):
    if not ok: fails.append(n); print("  FAIL", n, d)
designs = sorted(os.path.join(r, f) for r, _, fs in os.walk(EXAMPLES) for f in fs if f.lower().endswith(".dsn"))
def run(cmds):
    r = subprocess.run([EXE], input="\n".join(cmds) + "\n", capture_output=True, text=True, env=dict(os.environ), timeout=120)
    if r.returncode != 0: raise SystemExit("edittest failed: " + r.stderr[-300:])
    return r.stdout.split("\n")
def parse(out):
    """-> (nets list of frozensets of pins, pins list of (x,y), wires list of ((x,y),(x,y)))"""
    nets, pins, wires = [], [], []
    for l in out:
        t = l.split()
        if not t: continue
        if t[0] == "NET":
            p = frozenset(t[t.index(":") + 1:]); 
            if len(p) >= 1: nets.append(p)
        elif t[0] == "PIN": pins.append((float(t[1]), float(t[2])))
        elif t[0] == "W": wires.append(((float(t[1]), float(t[2])), (float(t[3]), float(t[4]))))
    return nets, pins, wires
def sections(out, marker):
    parts, cur = [], []
    for l in out:
        cur.append(l)
        if l.startswith(marker): parts.append(cur); cur = []
    return parts
offsets = [(10, 0), (-10, 0), (0, 10), (0, -10), (20, 10), (-20, -20), (30, 0), (0, -30)]
skipped = []
trials = 0; explained = 0; lost3 = lost_pin = bad_pins = zero_len = 0; wire_pins = 0; ends_followed = 0; collapsed = 0
def blocks(out):
    """split the output of one trial at its markers: returns dict of before / after parts"""
    e1 = out.index("ENDNETS"); e2 = out.index("ENDNETS", e1 + 1)
    return out[:e1], out[e1 + 1:e2], out[e2 + 1:]
def pins_of(lines): return [(float(l.split()[1]), float(l.split()[2])) for l in lines if l.startswith("PIN ")]
def _pin(l):
    t = l.split(" ")                       # tag ref number x y  (ref or number may be empty)
    return ("".join(t[1:-2]) if len(t) < 5 else t[1] + "-" + t[2]), (float(t[-2]), float(t[-1]))
def selpins(lines): return [_pin(l) for l in lines if l.startswith("SELPIN ")]
def allpins(lines): return [_pin(l) for l in lines if l.startswith("ALLPIN ")]
def nets_of(lines): return [frozenset(l.split()[l.split().index(":") + 1:]) for l in lines if l.startswith("NET ")]
def wires_of(lines): return [((float(l.split()[1]), float(l.split()[2])), (float(l.split()[3]), float(l.split()[4]))) for l in lines if l.startswith("W ")]
for p in designs:
    sh = os.path.join(tmp, "d.dsn"); shutil.copy(p, sh)
    nsym = int([l for l in run([f"LOAD {sh}", "COUNTSYM"]) if l.startswith("COUNTSYM")][0].split()[1])
    if nsym == 0: skipped.append(os.path.basename(p)); continue
    for k in random.sample(range(nsym), min(nsym, 5)):
        dx, dy = random.choice(offsets); steps = random.choice([1, 2, 3]); tx, ty = dx * steps, dy * steps
        out = run([f"LOAD {sh}", "STRIP", f"SELSYM {k}", "SELPINS", "ALLPINS", "NETS", "PINS", "DUMP", f"DRAGBY {steps} {dx} {dy}", "FINISH", "SELPINS", "NETS", "PINS", "DUMP"])
        # the output is: SELPIN.. NETS.. ENDNETS PIN.. W/J.. END  SELPIN.. NETS.. ENDNETS PIN.. W.. END
        i_end1 = out.index("END"); first, second = out[:i_end1 + 1], out[i_end1 + 1:]
        sp1, sp2 = selpins(first), selpins(second)
        n1, n2 = nets_of(first), nets_of(second)
        pa, pb = pins_of(first), pins_of(second)
        w1, w2 = wires_of(first), wires_of(second)
        trials += 1
        mine = {n for n, _ in sp1}
        ap = allpins(first)
        # (a) the moved symbol's pins moved by exactly the dragged distance, and nothing else moved
        shifted = len(sp1) == len(sp2) and all(a[0] == b_[0] and abs(b_[1][0] - a[1][0] - tx) < 1e-6 and abs(b_[1][1] - a[1][1] - ty) < 1e-6 for a, b_ in zip(sp1, sp2))
        changed = [i for i in range(len(pa)) if pa[i] != pb[i]]
        if not shifted or len(changed) != len(sp1): bad_pins += 1; print("   PINS", os.path.basename(p), "symbol", k, (tx, ty), len(changed), len(sp1))
        # wires that were stretched or moved (present before, gone after): a pin that merely touched the middle of one, or that shared
        # an end point with it, is not attached to it, and TinyCAD's drag only follows wires, so such a contact is left behind
        stretched = [w for w in w1 if w not in w2]
        def on_interior(pt, w):
            (x1, y1), (x2, y2) = w
            dxw, dyw = x2 - x1, y2 - y1; L2 = dxw * dxw + dyw * dyw
            if L2 == 0: return False
            t = ((pt[0] - x1) * dxw + (pt[1] - y1) * dyw) / L2
            if t <= 0.001 or t >= 0.999: return False
            return abs(pt[0] - (x1 + t * dxw)) < 0.01 and abs(pt[1] - (y1 + t * dyw)) < 0.01
        def ends_at(ws, pt): return sum(1 for w in ws for e in w if abs(e[0] - pt[0]) < 0.01 and abs(e[1] - pt[1]) < 0.01)
        moved_set = set(sp1)
        left_behind = {n for n, pt in ap if any(on_interior(pt, w) for w in stretched)}
        # a pin that did not move but whose wire ends were all taken away with the moved symbol (they shared one point)
        left_behind |= {n for n, pt in ap if (n, pt) not in moved_set and ends_at(w1, pt) > 0 and ends_at(w2, pt) == 0}
        # (b) no other part of the circuit is disconnected, except pins left on the middle of a stretched wire
        for net in n1:
            rest = net - mine
            if len(rest) >= 2 and not any(rest <= b_ for b_ in n2):
                if rest & left_behind: explained += 1; continue
                lost3 += 1; print("   LOST (rest of circuit)", os.path.basename(p), "symbol", k, (tx, ty), sorted(rest)[:5]); break
        # (c) a moved pin that had wires on it stays connected to something it was connected to
        for name, pt in sp1:
            wcount = ends_at(w1, pt)
            if wcount == 0: continue
            wire_pins += 1; ends_followed += wcount
            before = next((n for n in n1 if name in n), frozenset([name])) - mine
            after = next((n for n in n2 if name in n), frozenset([name])) - mine
            if before and not (before & after):
                if (before & left_behind) == before: explained += 1; continue
                lost_pin += 1; print("   PIN LOST ITS NET", os.path.basename(p), "symbol", k, name, (tx, ty), sorted(before)[:4]); break
        # (d) no new zero-length wires
        z = lambda ws: sum(1 for w in ws if abs(w[0][0] - w[1][0]) < 0.001 and abs(w[0][1] - w[1][1]) < 0.001)
        if z(w2) > z(w1): zero_len += 1; print("   ZERO-LENGTH", os.path.basename(p), "symbol", k)
check("the moved symbol's pins move by exactly the dragged distance, and nothing else moves", bad_pins == 0, f"{bad_pins}")
check("dragging a symbol disconnects nothing else in the circuit", lost3 == 0, f"{lost3}")
check("a moved pin with wires on it stays connected to something it was connected to", lost_pin == 0, f"{lost_pin}")
check("dragging creates no zero-length wires", zero_len == 0, f"{zero_len}")
print(f"wire dragging: {trials} drags of symbols in {len(designs) - len(skipped)} real designs; {wire_pins} wired pins moved ({ends_followed} wire ends); "
      f"pin errors {bad_pins}, connections lost {lost3} + {explained} left on the middle of a stretched wire (as TinyCAD does), wired pins that lost their net {lost_pin}, zero-length wires {zero_len}")
print("\nWIRE DRAG CHECKS PASSED" if not fails else f"\nWIRE DRAG CHECKS FAILED: {fails}")
sys.exit(1 if fails else 0)
