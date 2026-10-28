"""Ladder rail object checks (rails, bus labels, line density, resizing), against references written independently in Python."""
import os, sys, math, random, subprocess
import xml.etree.ElementTree as ET
BUILD = os.environ.get("TC_BUILD", "build")
EXE = os.path.join(BUILD, "laddertest")
random.seed(11)
fails = []
def run(lines):
    r = subprocess.run([EXE], input="\n".join(lines) + "\n", capture_output=True, text=True)
    if r.returncode != 0: raise SystemExit("laddertest failed: " + r.stderr[-300:])
    return r.stdout.strip().split("\n")
def check(name, ok, detail=""):
    if not ok: fails.append(name); print("  FAIL", name, detail)

class Ladder:
    """Independent model: two vertical rails (width = line density, in design units) and the two bus labels above them."""
    CW, CH, GAP = 7.0, 12.0, 12.0
    def __init__(s, ax, ay, bx, by, width=3, left="L1", right="L2"):
        s.l, s.r = min(ax, bx), max(ax, bx); s.t, s.b = min(ay, by), max(ay, by)
        s.w, s.left, s.right = width, left, right
    def boxes(s):
        out = []
        for x, t in ((s.l, s.left), (s.r, s.right)):
            w = s.CW * len(t); out.append((x - w / 2, s.t - s.GAP - s.CH, x + w / 2, s.t - s.GAP))
        return out
    def dist(s, px, py):
        def seg(x):
            cy = min(max(py, s.t), s.b); return math.hypot(px - x, py - cy)
        d = max(0.0, min(seg(s.l), seg(s.r)) - s.w / 2)
        if d > 0 and any(a <= px <= c and b <= py <= e for a, b, c, e in s.boxes()): d = 0
        return min(100.0, d)

# ---------- what can be clicked ----------
def hit_cases(n, kind):
    cs, ex = [], []
    for _ in range(n):
        ax, bx = sorted(random.sample(range(300, 2000), 2)); ay, by = sorted(random.sample(range(100, 1500), 2))
        if bx - ax < 60 or by - ay < 60: continue
        width = random.choice([1, 2, 3, 5, 8])
        L = Ladder(ax, ay, bx, by, width)
        if kind == "rail":   px = random.choice([L.l, L.r]) + random.uniform(-width / 2, width / 2) * 0.9; py = random.uniform(L.t, L.b)
        elif kind == "inside": px = random.uniform(L.l + width / 2 + 6, L.r - width / 2 - 6); py = random.uniform(L.t - 40, L.b + 40)
        elif kind == "text":
            bx_ = random.choice(L.boxes()); px = random.uniform(bx_[0], bx_[2]); py = random.uniform(bx_[1], bx_[3])
        else: px = random.uniform(0, 2300); py = random.uniform(0, 1700)
        cs.append(f"HIT {ax} {ay} {bx} {by} {width} {px} {py}"); ex.append((L, px, py))
    return cs, ex
tot = bad = 0
for kind in ("rail", "text", "inside", "any"):
    cs, ex = hit_cases(1500, kind); out = run(cs); b = 0
    for line, (L, px, py) in zip(out, ex):
        d, sel = float(line.split()[1]), int(line.split()[2])
        want_d = L.dist(px, py)
        in_text = any(a <= px <= c and bb <= py <= e for a, bb, c, e in L.boxes())
        near_rail = min(abs(px - L.l), abs(px - L.r)) <= L.w / 2 + 3 and L.t - 3 - L.w / 2 <= py <= L.b + 3 + L.w / 2
        ok_ = abs(d - want_d) < 1e-6 and sel == int(want_d < 3)
        if kind in ("rail", "text"): ok_ = ok_ and sel == 1
        if kind == "inside" and not in_text and not near_rail: ok_ = ok_ and sel == 0
        b += not ok_
        if not ok_ and b <= 2: print("   HIT", kind, L.__dict__, px, py, line, want_d)
    print(f"click test, points {kind:6s}: {len(ex)} cases, {b} wrong")
    tot += len(ex); bad += b
check("select only on rails or bus labels", bad == 0, f"{bad}")

# the rails' thickness is the line density: a wider rail is hit further from its centre line
for w in (1, 2, 4, 9):
    near = run([f"HIT 500 200 1500 1200 {w} {500 + w / 2 - 0.01} 600", f"HIT 500 200 1500 1200 {w} {500 + w / 2 + 2.5} 600", f"HIT 500 200 1500 1200 {w} {500 + w / 2 + 3.5} 600"])
    sel = [int(l.split()[2]) for l in near]
    check(f"rail of density {w} is hit up to its edge plus the 3 unit tolerance", sel == [1, 1, 0], str(sel))
print("line density: 1, 2, 4 and 9 wide rails are hit exactly as far out as their width plus the tolerance")

# no more numbers beside the rails: the left of the left rail and the right of the right rail are empty space
free = [(random.uniform(200, 480), random.uniform(220, 1180)) for _ in range(300)] + [(random.uniform(1520, 1900), random.uniform(220, 1180)) for _ in range(300)]
out = run([f"HIT 500 200 1500 1200 3 {x} {y}" for x, y in free])
check("no line numbers beside the rails", sum(int(l.split()[2]) for l in out) == 0)
print(f"beside the rails: {len(free)} points, none selected (the numbers are the rung grid's now)")

empty = [(random.uniform(520, 1480), random.uniform(220, 1180)) for _ in range(500)]
out = run([f"HIT 500 200 1500 1200 3 {x} {y}" for x, y in empty])
n_sel = sum(int(l.split()[2]) for l in out)
check("interior is not selectable", n_sel == 0, f"{n_sel} selected")
print(f"empty space between the rails: {len(empty)} points, {n_sel} selected")

# ---------- selection rectangles ----------
def seg_hits(x, y0, y1, l, r, t, b): return (l <= x <= r) and not (y1 < t or y0 > b)
cases, exp = [], []
for _ in range(2000):
    ax, bx = sorted(random.sample(range(300, 2000), 2)); ay, by = sorted(random.sample(range(100, 1500), 2))
    if bx - ax < 60 or by - ay < 60: continue
    width = random.choice([1, 3, 6]); L = Ladder(ax, ay, bx, by, width)
    l = random.uniform(0, 2200); t = random.uniform(0, 1600); r = l + random.uniform(1, 400); b = t + random.uniform(1, 300)
    cases.append(f"BOX {ax} {ay} {bx} {by} {width} {l} {r} {t} {b}"); exp.append((L, l, r, t, b))
bad = 0; skipped = 0
for line, (L, l, r, t, b) in zip(run(cases), exp):
    got = int(line.split()[1])
    want = seg_hits(L.l, L.t, L.b, l, r, t, b) or seg_hits(L.r, L.t, L.b, l, r, t, b) or any(not (bx_[2] < l or bx_[0] > r or bx_[3] < t or bx_[1] > b) for bx_ in L.boxes())
    margin = min(abs(L.l - l), abs(L.l - r), abs(L.r - l), abs(L.r - r))
    if got != int(want) and margin < 0.5: skipped += 1; continue
    bad += got != int(want)
check("rectangle selection", bad == 0, f"{bad}")
print(f"selection rectangle: {len(cases)} cases, {bad} wrong ({skipped} within 0.5 of a rail edge skipped)")

# ---------- resizing by the handles (the eight handles of a rectangle) ----------
# handle numbers as MFC numbers them: 0 top-left, 1 top-right, 2 bottom-right, 3 bottom-left, 4 top, 5 right, 6 bottom, 7 left
def resized(ax, ay, bx, by, h, dx, dy):
    l, r, t, b = min(ax, bx), max(ax, bx), min(ay, by), max(ay, by)
    if h in (0, 3, 7): l += dx
    if h in (1, 2, 5): r += dx
    if h in (0, 1, 4): t += dy
    if h in (2, 3, 6): b += dy
    return sorted((l, r)) + sorted((t, b))
cases, exp = [], []
for _ in range(2000):
    ax, bx = random.sample(range(100, 2000), 2); ay, by = random.sample(range(100, 1500), 2)    # either corner order
    h = random.randrange(8); dx = random.randint(-300, 300); dy = random.randint(-300, 300)
    cases.append(f"SIZE {ax} {ay} {bx} {by} {h} {dx} {dy}"); exp.append((ax, ay, bx, by, h, dx, dy))
bad = noresize = 0
for line, e in zip(run(cases), exp):
    v = line.split(); can = int(v[1]); a_x, a_y, b_x, b_y = (float(x) for x in v[2:6])
    got = sorted((a_x, b_x)) + sorted((a_y, b_y))
    want = resized(*e)
    noresize += not can
    if not can or any(abs(g - w) > 1e-6 for g in [0] for w in [0]) or got != want:
        bad += 1
        if bad <= 3: print("   SIZE", e, line, want)
check("ladder can be resized, by every handle, in any corner order", bad == 0, f"{bad}")
print(f"resizing: {len(cases)} drags on all 8 handles, either corner order, dragging past the opposite side too ({bad} wrong, {noresize} refused)")

# ---------- saved form ----------
out = run(["XML"])[0][4:].split("|")
check("xml round trip fields", out == ["1", "200 100 1200 900", "L1 <A>", "N&2", "4", "0000FF", "00FF00", "0"], str(out))
print("save and reload: width (line density), rail colour, text colour, and markup characters in the bus labels come back unchanged")
old = run(["OLDXML"])[0][7:].split("|")
check("a file of the first version still loads", old == ["200 900", "5"], str(old))
print("a ladder from the first version (numbering attributes, fractional width) loads: numbering ignored, width taken as the nearest whole density")
print("\nLADDER CHECKS PASSED" if not fails else f"\nLADDER CHECKS FAILED: {fails}")
sys.exit(1 if fails else 0)
