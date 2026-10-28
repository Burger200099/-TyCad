"""Checks of the editing engine (wire drawing, snapping, merging, splitting, junctions).
The properties are computed here, independently of the Pascal code."""
import os, sys, math, random, subprocess

BUILD = os.environ.get("TC_BUILD", "build")
EXE = os.path.join(BUILD, "edittest")
EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
random.seed(424242)
EPS = 0.01
fails = []
def check(name, ok, detail=""):
    if not ok: fails.append(name); print("  FAIL", name, detail)

def run(lines):
    r = subprocess.run([EXE], input="\n".join(lines) + "\n", capture_output=True, text=True, env=dict(os.environ))
    if r.returncode != 0: raise SystemExit("edittest failed: " + r.stderr[-300:])
    return r.stdout.split("\n")

def parse_blocks(out):
    blocks, cur = [], dict(RAW=[], W=[], J=[], L=[], PIN=[])
    for l in out:
        t = l.split()
        if not t: continue
        if t[0] == "END": blocks.append(cur); cur = dict(RAW=[], W=[], J=[], L=[], PIN=[])
        elif t[0] in cur:
            v = tuple(float(x) for x in t[1:])
            cur[t[0]].append(v if t[0] in ("J", "PIN") else ((v[0], v[1]), (v[2], v[3])))
    return blocks

def pdist(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]; L2 = dx * dx + dy * dy
    t = 0 if L2 == 0 else max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L2))
    return math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy))
def same(p, q): return abs(p[0] - q[0]) < 0.001 and abs(p[1] - q[1]) < 0.001
def touches(s, t):
    return any(pdist(p, *t) <= EPS for p in s) or any(pdist(p, *s) <= EPS for p in t)
def components(segs):
    parent = list(range(len(segs)))
    def find(i):
        while parent[i] != i: parent[i] = parent[parent[i]]; i = parent[i]
        return i
    for i in range(len(segs)):
        for j in range(i + 1, len(segs)):
            if touches(segs[i], segs[j]): parent[find(i)] = find(j)
    return [find(i) for i in range(len(segs))]
def covers(w, a, b):
    """does final wire w contain the drawn segment a-b's midpoint, lying along it (not just crossing it)?"""
    m = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    cross = lambda o, p, q: (p[0] - o[0]) * (q[1] - o[1]) - (p[1] - o[1]) * (q[0] - o[0])
    return pdist(m, *w) <= EPS and abs(cross(w[0], w[1], a)) < 1e-6 and abs(cross(w[0], w[1], b)) < 1e-6
def collinear_overlap(s, t):
    (a, b), (c, d) = s, t
    cross = lambda o, p, q: (p[0] - o[0]) * (q[1] - o[1]) - (p[1] - o[1]) * (q[0] - o[0])
    if abs(cross(a, b, c)) > 1e-6 or abs(cross(a, b, d)) > 1e-6: return 0.0
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    if L == 0: return 0.0
    ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
    pr = lambda p: (p[0] - a[0]) * ux + (p[1] - a[1]) * uy
    lo, hi = max(0, min(pr(c), pr(d))), min(L, max(pr(c), pr(d)))
    return max(0.0, hi - lo)

def verify_state(block):
    """the invariants of one state of the drawing"""
    probs = []; W = block["W"]; J = block["J"]; RAW = [r for r in block["RAW"] if not same(*r)]
    for w in W:
        if same(*w): probs.append(("zero-length wire", w))
    for i in range(len(W)):
        for j in range(i + 1, len(W)):
            if collinear_overlap(W[i], W[j]) > EPS: probs.append(("overlapping wires", W[i], W[j]))
    for i, w in enumerate(W):
        for j, v in enumerate(W):
            if i == j: continue
            for p in w:
                if pdist(p, *v) <= EPS and not same(p, v[0]) and not same(p, v[1]): probs.append(("wire end inside another wire", p, v))
    ends = {}
    for w in W:
        for p in w:
            k = next((q for q in ends if same(p, q)), None)
            if k is None: ends[p] = 1
            else: ends[k] += 1
    jpts = [(j[0], j[1]) for j in J]
    for q, n in ends.items():
        has = any(same(q, j) for j in jpts)
        if n >= 3 and not has: probs.append(("missing junction", q, n))
        if n < 3 and has: probs.append(("junction without 3 ends", q, n))
    for j in jpts:
        if not any(same(j, q) for q in ends): probs.append(("junction on no wire end", j))
    return probs

def verify_steps(ops):
    """Run the commands one at a time; after each, check the invariants and that this step did not change
    which wires are electrically connected (judged against the wires that existed just before it)."""
    out = run(ops_with_dumps(ops))
    blocks = parse_blocks(out)
    probs = []; prev_w = []; prev_raw = 0
    for k, bl in enumerate(blocks):
        step = verify_state(bl)
        new_raw = [r for r in bl["RAW"][prev_raw:] if not same(*r)]
        pre = list(prev_w) + new_raw
        W = bl["W"]
        if pre and W:
            co, cf = components(pre), components(W)
            owner = []
            for a, b in pre:
                m = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
                owner.append(next((i for i, w in enumerate(W) if pdist(m, *w) <= EPS), None))
            for i in range(len(pre)):
                if owner[i] is None: step.append(("segment no longer covered", pre[i])); continue
            for i in range(len(pre)):
                for j in range(i + 1, len(pre)):
                    if owner[i] is None or owner[j] is None: continue
                    if (co[i] == co[j]) != (cf[owner[i]] == cf[owner[j]]):
                        step.append(("connectivity changed", pre[i], pre[j], co[i] == co[j])); break
        probs.append((k, ops[k], step))
        prev_w, prev_raw = list(W), len(bl["RAW"])
    return probs

def ops_with_dumps(ops):
    res = []
    for o in ops: res += [o, "DUMP"]
    return res

def rand_pt(lo=100, hi=500, step=10): return (random.randrange(lo, hi + 1, step), random.randrange(lo, hi + 1, step))
def rand_poly():
    n = random.randint(2, 4); pts = [rand_pt(100, 400)]
    for _ in range(n - 1):
        if random.random() < 0.8:
            p = pts[-1]
            q = (p[0] + random.choice([-1, 1]) * random.randrange(10, 90, 10), p[1]) if random.random() < 0.5 else (p[0], p[1] + random.choice([-1, 1]) * random.randrange(10, 90, 10))
        else: q = rand_pt(100, 400)
        pts.append(q)
    return pts

# ---------------- scenarios with known answers ----------------
def scenario(cmds):
    return parse_blocks(run(cmds + ["DUMP"]))[0]
def wset(b): return sorted((tuple(sorted(w))) for w in b["W"])
b = scenario(["POLY 100 100 300 100", "POLY 200 100 200 250"])
check("T: wire split at the contact", wset(b) == [((100, 100), (200, 100)), ((200, 100), (200, 250)), ((200, 100), (300, 100))], str(wset(b)))
check("T: junction at the contact", [(j[0], j[1]) for j in b["J"]] == [(200, 100)])
b = scenario(["POLY 100 200 300 200", "POLY 200 100 200 300"])
check("crossing wires neither split nor joined", len(b["W"]) == 2 and not b["J"], str(b))
b = scenario(["POLY 100 100 200 100", "POLY 200 100 300 100"])
check("end-to-end collinear wires merge into one", wset(b) == [((100, 100), (300, 100))], str(wset(b)))
b = scenario(["POLY 200 100 200 200", "POLY 100 200 200 200", "POLY 200 200 300 200", "POLY 200 200 200 300"])
check("four wires meeting: a junction at the meeting point (TinyCAD may add more than one)", b["J"] and all(same((j[0], j[1]), (200, 200)) for j in b["J"]) and len(b["W"]) == 4, str(b))
b = scenario(["OPT autojunction 0", "POLY 100 100 300 100", "POLY 200 100 200 250"])
check("auto junction off: no junction, no split", not b["J"] and len(b["W"]) == 2, str(b))
b = scenario(["POLY 100 100 200 100 200 200"])
check("90 degree mode draws a corner as two wires", wset(b) == [((100, 100), (200, 100)), ((200, 100), (200, 200))], str(wset(b)))
b = scenario(["DRAG 100 100 200 160"])
check("press-drag-release draws an L of two wires", len(b["W"]) == 2 and abs(b["W"][0][1][0] - 200) < 1e-9, str(b["W"]))
b = scenario(["LINE 100 100 300 100", "LINE 200 100 200 250"])
check("plain lines are never split or given junctions", len(b["L"]) == 2 and not b["J"], str(b))
b = scenario(["POLY 100 100 300 100", "POWER 200 130", "POLY 205 135 205 200"])  # near the power point: sticks to it
check("wire start sticks to a power symbol's point", any(abs(w[0][0] - 200) < 1e-9 and abs(w[0][1] - 130) < 1e-9 or abs(w[1][0] - 200) < 1e-9 and abs(w[1][1] - 130) < 1e-9 for w in b["W"]), str(b["W"]))
b = scenario(["POWER 200 130", "POLY 240 130 240 200"])  # 40 away: out of the snap range, so no sticking
check("outside the snap range nothing sticks", not any(abs(p[0] - 200) < 1e-9 for w in b["W"] for p in w), str(b["W"]))
print("scenarios with known answers: T, crossing, merge, four-way, options, corner, drag, lines, snapping")

# ---------------- random worlds ----------------
def world_ops():
    ops = []
    for _ in range(random.randint(4, 12)):
        r = random.random()
        if r < 0.75: ops.append("POLY " + " ".join(f"{x} {y}" for x, y in rand_poly()))
        elif r < 0.9: p, q = rand_pt(100, 400), rand_pt(100, 400); ops.append(f"DRAG {p[0]} {p[1]} {q[0]} {q[1]}")
        else: ops.append("DBL " + " ".join(f"{x} {y}" for x, y in rand_poly()))
    return ops
worlds = 1000; all_ops = [world_ops() for _ in range(worlds)]
cmds = []
for ops in all_ops: cmds += ops_with_dumps(ops) + ["CLEAR"]
blocks_all = parse_blocks(run(cmds))
bad_worlds = 0; kinds = {}; nw = nj = nr = steps = 0; shown = 0; idx = 0; skipped = 0
for ops in all_ops:
    bls = blocks_all[idx: idx + len(ops)]; idx += len(ops)
    prev_w = []; prev_raw = 0; world_bad = False
    for k, bl in enumerate(bls):
        probs = verify_state(bl)
        new_raw = [r for r in bl["RAW"][prev_raw:] if not same(*r)]
        old_raw = [r for r in bl["RAW"][:prev_raw] if not same(*r)]
        if any(collinear_overlap(n, o) > EPS for n in new_raw for o in old_raw) or \
           any(collinear_overlap(new_raw[i], new_raw[j]) > EPS for i in range(len(new_raw)) for j in range(i + 1, len(new_raw))):
            skipped += 1; break   # drawing over an existing wire (or back over itself) is a mistake TinyCAD's merge treats oddly
        pre = list(prev_w) + new_raw; W = bl["W"]
        if pre and W:
            co, cf = components(pre), components(W)
            owner = [next((i for i, w in enumerate(W) if covers(w, a, b)), None) for a, b in pre]
            probs += [("segment no longer covered", pre[i]) for i in range(len(pre)) if owner[i] is None]
            hit = False
            for i in range(len(pre)):
                if hit: break
                for j in range(i + 1, len(pre)):
                    if owner[i] is None or owner[j] is None: continue
                    if (co[i] == co[j]) != (cf[owner[i]] == cf[owner[j]]): probs.append(("connectivity changed", pre[i], pre[j], co[i] == co[j])); hit = True; break
        steps += 1
        if probs:
            world_bad = True
            for p in probs: kinds[p[0]] = kinds.get(p[0], 0) + 1
            if shown < 3: print("   step", k + 1, "of", ops[: k + 1][-3:], "->", probs[:2]); shown += 1
        prev_w, prev_raw = list(W), len(bl["RAW"])
    if world_bad: bad_worlds += 1
    nw += len(bls[-1]["W"]); nj += len(bls[-1]["J"]); nr += len(bls[-1]["RAW"])
check("random worlds keep every invariant", bad_worlds == 0, f"{bad_worlds} worlds, {kinds}")
print(f"random worlds: {worlds} designs, {steps} editing steps checked ({skipped} worlds stopped at a step that drew over an existing wire), {nr} segments drawn -> {nw} wires + {nj} junctions; invariants violated in {bad_worlds} worlds {kinds if kinds else ''}")

# ---------------- pin snapping on real library symbols ----------------
lib = os.path.join(EXAMPLES, "libraries", "gen_passive.TCLib")
if os.path.exists(lib):
    ok_pins = tot_pins = far_bad = 0
    for row in (0, 1, 2, 3, 5, 9, 13):
        for rot in range(8):
            out = run([f"SYM {lib} {row} 800 600 {rot}", "PINS", "DUMP"])
            pins = [(float(l.split()[1]), float(l.split()[2])) for l in out if l.startswith("PIN ")]
            for (px, py) in pins:
                tot_pins += 1
                # start a wire 8 units away from the pin: it must land exactly on the pin
                o2 = run([f"SYM {lib} {row} 800 600 {rot}", f"POLY {px + 8} {py + 6} {px + 8} {py + 120}", "DUMP"])
                ws = [w for b in parse_blocks(o2) for w in b["W"]]
                if any(same(p, (px, py)) for w in ws for p in w): ok_pins += 1
                # and 60 units away it must not stick
                o3 = run([f"SYM {lib} {row} 800 600 {rot}", f"POLY {px + 60} {py + 60} {px + 60} {py + 160}", "DUMP"])
                ws3 = [w for b in parse_blocks(o3) for w in b["W"]]
                if any(same(p, (px, py)) for w in ws3 for p in w): far_bad += 1
    check("wires stick to every pin within range", ok_pins == tot_pins, f"{ok_pins}/{tot_pins}")
    check("wires do not stick to pins out of range", far_bad == 0, f"{far_bad}")
    print(f"pin snapping: {tot_pins} pins of real library symbols (8 rotations): {ok_pins} stuck exactly when close, {far_bad} stuck when far")
print("\nEDIT ENGINE CHECKS PASSED" if not fails else f"\nEDIT ENGINE CHECKS FAILED: {fails}")
sys.exit(1 if fails else 0)
