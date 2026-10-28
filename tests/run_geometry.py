"""Independent checks of the geometry layer. Cases are generated here, answered by
build/geomtest, and compared with reference implementations written separately in Python:
textbook point/segment geometry, exact segment-rectangle intersection, even-odd polygon fill,
and straight transcriptions of the C++ layout formulas."""
import os, sys, math, random, subprocess

BUILD = os.environ.get("TC_BUILD", "build")
EXE = os.path.join(BUILD, "geomtest")
random.seed(20260101)

def run(lines):
    r = subprocess.run([EXE], input="\n".join(lines) + "\n", capture_output=True, text=True)
    if r.returncode != 0: raise SystemExit("geomtest failed: " + r.stderr[-300:])
    return r.stdout.strip().split("\n")

def close(a, b, tol=1e-6):
    return abs(a - b) <= tol * max(1.0, abs(a), abs(b))

# ---------------- reference geometry ----------------
def seg_nearest(a, b, p):
    dx, dy = b[0] - a[0], b[1] - a[1]
    L2 = dx * dx + dy * dy
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L2))
    q = (a[0] + t * dx, a[1] + t * dy)
    return math.hypot(p[0] - q[0], p[1] - q[1]), q

def seg_axis(a, b, p, axis):
    """distance along one axis: horizontal/vertical lines use the true nearest point"""
    if a[1] == b[1] or a[0] == b[0]: return seg_nearest(a, b, p)
    if axis == 'x': t = (p[1] - a[1]) / (b[1] - a[1])
    else:           t = (p[0] - a[0]) / (b[0] - a[0])
    t = max(0.0, min(1.0, t))
    q = (a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1]))
    return math.hypot(p[0] - q[0], p[1] - q[1]), q

def seg_hits_rect(a, b, l, r, t, bt):
    """exact segment / closed rectangle intersection (Liang-Barsky)"""
    x0, y0, dx, dy = a[0], a[1], b[0] - a[0], b[1] - a[1]
    u0, u1 = 0.0, 1.0
    for p_, q_ in ((-dx, x0 - l), (dx, r - x0), (-dy, y0 - t), (dy, bt - y0)):
        if p_ == 0:
            if q_ < 0: return False
        else:
            u = q_ / p_
            if p_ < 0:
                if u > u1: return False
                u0 = max(u0, u)
            else:
                if u < u0: return False
                u1 = min(u1, u)
    return True

def margin_class(a, b, l, r, t, bt, eps):
    """(hits with rect shrunk, hits with rect grown): if they differ the case is borderline"""
    return (seg_hits_rect(a, b, l + eps, r - eps, t + eps, bt - eps) if (r - l) > 2 * eps and (bt - t) > 2 * eps else False,
            seg_hits_rect(a, b, l - eps, r + eps, t - eps, bt + eps))

results = {}
def report(name, n, bad, extra=""):
    results[name] = (n, bad)
    print(f"{name:34s} {n:7d} cases  mismatches: {bad} {extra}")

def rnd(lo=-100, hi=100): return round(random.uniform(lo, hi), 3)

# ---------------- 1. line distance ----------------
cases, exp = [], []
for _ in range(20000):
    k = random.random()
    a = (rnd(), rnd()); b = (rnd(), rnd())
    if k < 0.15: b = (b[0], a[1])          # horizontal
    elif k < 0.30: b = (a[0], b[1])        # vertical
    elif k < 0.33: b = a                   # degenerate
    p = (rnd(-150, 150), rnd(-150, 150))
    cases.append(f"LD {a[0]} {a[1]} {b[0]} {b[1]} {p[0]} {p[1]}")
    exp.append((a, b, p))
out = run(cases); bad = 0
for line, (a, b, p) in zip(out, exp):
    v = list(map(float, line.split()[1:]))
    d0, q0 = seg_nearest(a, b, p); dx_, qx = seg_axis(a, b, p, 'x'); dy_, qy = seg_axis(a, b, p, 'y')
    ok = close(v[0], d0, 1e-7) and close(v[3], dx_, 1e-7) and close(v[6], dy_, 1e-7)
    ok = ok and close(v[1], q0[0], 1e-6) and close(v[2], q0[1], 1e-6)
    bad += not ok
    if not ok and bad <= 3: print("   LD", a, b, p, v[:3], d0, q0)
report("line distance (3 variants + point)", len(cases), bad)

# ---------------- 2. line vs rectangle ----------------
cases, exp = [], []
for _ in range(20000):
    a = (rnd(), rnd()); b = (rnd(), rnd())
    l = rnd(-120, 100); w = random.choice([0, rnd(0.5, 60)]); t = rnd(-120, 100); h = 0 if w == 0 else rnd(0.5, 60)
    cases.append(f"LI {a[0]} {a[1]} {b[0]} {b[1]} {l} {l+w} {t} {t+h}")
    exp.append((a, b, l, l + w, t, t + h))
out = run(cases); bad = border = borderbad = 0; pts = 0
for line, (a, b, l, r, t, bt) in zip(out, exp):
    got = bool(int(line.split()[1]))
    if l == r and t == bt:
        pts += 1
        d, _ = seg_nearest(a, b, (l, t))
        if abs(d - 0.01) < 1e-6: continue
        want = d < 0.01
        bad += got != want
        continue
    lo, hi = margin_class(a, b, l, r, t, bt, 0.05)
    if lo == hi:
        bad += got != lo
        if got != lo and bad <= 3: print("   LI", a, b, (l, r, t, bt), got, lo)
    else:
        border += 1; borderbad += got != seg_hits_rect(a, b, l, r, t, bt)
report("line vs rectangle (non-borderline)", len(cases) - border, bad, f"[{pts} point tests; {border} borderline cases skipped, {borderbad} of them differ]")

# ---------------- 3. snap ----------------
def snap(grid, on, d):
    if not on or grid == 0: return d
    a = math.floor(d / grid) * grid
    if (d - a) * 2 > grid: a += grid
    return a
cases, exp = [], []
for _ in range(5000):
    g = random.choice([0, 1, 2.5, 5, 10, 12.5, 50]); on = random.random() < 0.85; d = rnd(-300, 300)
    cases.append(f"SN {g} {int(on)} {d}"); exp.append(snap(g, on, d))
bad = sum(not close(float(l.split()[1]), e, 1e-9) for l, e in zip(run(cases), exp))
report("grid snap", len(cases), bad)

# ---------------- 4. transform ----------------
def rnd_i(a, b): return random.randint(a, b)
def rd(x): return int(x + 0.5) if x > -0.5 else int(x - 0.5)
def transform(zoom, ox, oy, rm, sx, sy, yup, bound, x, y):
    if rm & 4: x = -x
    k = rm & 3
    if k == 1: y = -y
    elif k == 2: x, y = y, x
    elif k == 3: x, y = -y, x
    sx_, sy_ = (sx, sy)  # SetScaling(0, sx, sy)
    X = rd((x * sx_ - ox) * zoom)
    Y = rd(-((y * sy_ - oy) * zoom)) - bound if yup else rd((y * sy_ - oy) * zoom)
    return X, Y
cases, exp = [], []
for _ in range(5000):
    z = random.choice([0.25, 0.5, 1, 1.5, 2, 3.7]); ox, oy = rnd(-50, 50), rnd(-50, 50); rm = rnd_i(0, 7)
    sx, sy = random.choice([1, 1, 2, 0.5]), random.choice([1, 1, 2, 0.5]); yup = random.random() < 0.3; bound = rnd_i(0, 500)
    x, y = rnd(-80, 80), rnd(-80, 80)
    cases.append(f"TF {z} {ox} {oy} {rm} {sx} {sy} {int(yup)} {bound} {x} {y}")
    exp.append(transform(z, ox, oy, rm, sx, sy, yup, bound, x, y))
bad = 0
for l, e in zip(run(cases), exp):
    v = list(map(int, l.split()[1:3]))
    bad += (v[0], v[1]) != e
    if (v[0], v[1]) != e and bad <= 3: print("   TF", l, e)
report("screen transform (Scale)", len(cases), bad)

# ---------------- 5. pin layout (transcription of DetermineLayout) ----------------
def ext(n): return (7.0 * n, 12.0)
def pin_layout(which, d, length, centre, npos, show, slen, nlen, rotmir):
    px, py = 100.0, 100.0
    sizing = 20 if length <= 20 else 30
    dot = sizing // 6; line = length - dot * 2; ts = sizing // 8
    spacing = length + ts if (which & 2) == 0 else length + dot * 2 + ts
    dr = 3
    if d == 0:
        pa = (px, py - line); pb = (px - dot, py - length); pc = (px + dot + 1, py - length); pd = (px, py - length)
        s = ext(slen)
        pta = (px + s[1], py - (length - s[0]) / 2) if centre else (px + s[1] / 2, py - spacing)
        s = ext(slen); ptb = (px, py - ts - npos); dr = 0
    elif d == 1:
        pa = (px, py + line); pb = (px - dot, py + length); pc = (px + dot + 1, py + length); pd = (px, py + length)
        s = ext(slen)
        pta = (px + s[1], py + (s[0] + length) / 2) if centre else (px + s[1] / 2, py + spacing + s[0])
        s = ext(nlen); ptb = (px, py + s[0] + ts + npos); dr = 0
    elif d == 2:
        pa = (px - line, py); pb = (px - length, py - dot); pc = (px - length, py + dot + 1); pd = (px - length, py)
        s = ext(slen)
        pta = (px - (s[0] + length) / 2, py + s[1]) if centre else (px - s[0] - spacing, py + s[1] / 2)
        s = ext(nlen); ptb = (px - s[0] - ts - npos, py)
    else:
        pa = (px + line, py); pb = (px + length, py - dot); pc = (px + length, py + dot + 1); pd = (px + length, py)
        s = ext(slen)
        pta = (px + (length - s[0]) / 2, py + s[1]) if centre else (px + spacing, py + s[1] / 2)
        ptb = (px + ts + npos, py)
    if d in (2, 3) and rotmir in (1, 5, 7, 3):
        pta = (pta[0], pta[1] - s[1]); ptb = (ptb[0], ptb[1] - s[1])
    return pa, pb, pc, pd, pta, ptb, dr

def pin_size(which, d, length, centre, npos, show, slen, nlen):
    pa = (100.0, 100.0)
    if which in (4, 5) or length == 0: return pa
    L = pin_layout(which, d, length, centre, npos, show, slen, nlen, 0)
    pd, pta = L[3], L[4]; b = pta
    if show & 1:
        s = ext(slen)
        if d == 0: b = (pd[0], min(pta[1] - s[0], pd[1]))
        elif d == 1: b = (pd[0], max(pta[1], pd[1]))
        elif d == 2: b = (min(pta[0], pd[0]), pd[1])
        else: b = (max(pta[0], pd[0]), pd[1])
    return b
cases, exp = [], []
for _ in range(6000):
    a = (random.choice([0, 1, 2, 3, 4, 5, 6]), rnd_i(0, 3), random.choice([0, 5, 10, 15, 20, 25, 30, 40]), rnd_i(0, 1),
         rnd_i(-5, 10), rnd_i(0, 3), rnd_i(0, 12), rnd_i(0, 4), rnd_i(0, 7))
    cases.append("PL " + " ".join(map(str, a))); exp.append(a)
bad = 0
for l, a in zip(run(cases), exp):
    v = list(map(float, l.split()[1:]))
    L = pin_layout(*a)
    want = [c for p in L[:6] for c in p] + [L[6]] + list(pin_size(*a[:8]))
    ok = all(close(x, y, 1e-9) for x, y in zip(v, want))
    bad += not ok
    if not ok and bad <= 3: print("   PL", a, v, want)
report("pin layout + size (transcription)", len(cases), bad)

# ---------------- 6. rectangle / ellipse ----------------
def ellipse_dist(a, b, p):
    cx, cy = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    da, db = abs(a[0] - b[0]) / 2, abs(a[1] - b[1]) / 2
    nx, ny = (cx - p[0]) / da, (cy - p[1]) / db
    d = math.hypot(nx, ny)
    return abs(d - 1) * math.hypot(da, db), d <= 1.0
def rect_dist(a, b, p):
    c = [(a[0], a[1]), (b[0], a[1]), (b[0], b[1]), (a[0], b[1]), (a[0], a[1])]
    return min(seg_nearest(c[i], c[i + 1], p)[0] for i in range(4))
cases, exp = [], []
for _ in range(8000):
    kind = rnd_i(0, 1); a = (rnd(-60, 60), rnd(-60, 60)); b = (a[0] + random.choice([-1, 1]) * rnd(2, 80), a[1] + random.choice([-1, 1]) * rnd(2, 80))
    fill = rnd_i(0, 2); th = rnd_i(1, 4); p = (rnd(-100, 100), rnd(-100, 100))
    cases.append(f"SQ {kind} {a[0]} {a[1]} {b[0]} {b[1]} {fill} {th} {p[0]} {p[1]}"); exp.append((kind, a, b, fill, p))
bad = 0
for l, (kind, a, b, fill, p) in zip(run(cases), exp):
    got = float(l.split()[1])
    if kind == 0:
        inside = min(a[0], b[0]) <= p[0] <= max(a[0], b[0]) and min(a[1], b[1]) <= p[1] <= max(a[1], b[1])
        want = 0.0 if (fill and inside) else min(100.0, rect_dist(a, b, p))  # the C++ code starts from 100
    else:
        d, inside = ellipse_dist(a, b, p); want = 0.0 if (inside and fill) else d
    bad += not close(got, want, 1e-7)
    if not close(got, want, 1e-7) and bad <= 3: print("   SQ", kind, a, b, fill, p, got, want)
report("rectangle/ellipse distance", len(cases), bad)

cases, exp = [], []
for _ in range(8000):
    a = (rnd(-60, 60), rnd(-60, 60)); b = (a[0] + random.choice([-1, 1]) * rnd(5, 80), a[1] + random.choice([-1, 1]) * rnd(5, 80))
    fill = rnd_i(0, 1); l = rnd(-100, 80); t = rnd(-100, 80); r = l + rnd(0.5, 70); bt = t + rnd(0.5, 70)
    cases.append(f"SR 0 {a[0]} {a[1]} {b[0]} {b[1]} {fill} 1 {l} {r} {t} {bt}"); exp.append((a, b, fill, l, r, t, bt))
bad = border = 0
for ln, (a, b, fill, l, r, t, bt) in zip(run(cases), exp):
    got = bool(int(ln.split()[1]))
    bb = not ((a[0] < l and b[0] <= l) or (a[0] > r and b[0] >= r) or (a[1] < t and b[1] <= t) or (a[1] > bt and b[1] >= bt))
    if not bb: want = False
    elif fill: want = True
    else:
        corners = [(a[0], a[1]), (b[0], a[1]), (b[0], b[1]), (a[0], b[1]), (a[0], a[1])]
        lo = any(margin_class(corners[i], corners[i + 1], l, r, t, bt, 0.05)[0] for i in range(4))
        hi = any(margin_class(corners[i], corners[i + 1], l, r, t, bt, 0.05)[1] for i in range(4))
        if lo != hi: border += 1; continue
        want = lo
    bad += got != want
    if got != want and bad <= 3: print("   SR", a, b, fill, (l, r, t, bt), got, want)
report("rectangle vs rectangle", len(cases) - border, bad, f"[{border} borderline skipped]")

# ---------------- 7. polygon ----------------
def even_odd(poly, p):
    inside = False; n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]; x2, y2 = poly[(i + 1) % n]
        if (y1 > p[1]) != (y2 > p[1]) and p[0] < (x2 - x1) * (p[1] - y1) / (y2 - y1) + x1: inside = not inside
    return inside
def star_polygon(n):
    cx, cy = random.randint(10, 60), random.randint(10, 60); pts = []
    for i in range(n):
        ang = 2 * math.pi * i / n + random.uniform(-0.2, 0.2) / n
        rad = random.randint(8, 40)
        pts.append((round(cx + rad * math.cos(ang)), round(cy + rad * math.sin(ang))))
    return pts
cases, exp = [], []
for _ in range(6000):
    n = rnd_i(3, 9); pts = star_polygon(n)
    ox, oy = rnd_i(-50, 50), rnd_i(-50, 50)
    fill = rnd_i(0, 1); close_ = rnd_i(0, 1); th = rnd_i(1, 3)
    absp = [(ox + x, oy + y) for x, y in pts]
    if len(set(absp)) < 3: continue
    ys = {y for _, y in absp}
    for _try in range(20):
        p = (ox + rnd(0, 100), oy + rnd(0, 100))
        if all(abs(p[1] - y) > 0.75 for y in ys): break
    flat = " ".join(f"{x} {y}" for x, y in pts)
    cases.append(f"PG {fill} {close_} {th} {ox} {oy} {len(pts)} {flat} {p[0]} {p[1]}"); exp.append((absp, fill, close_, p))
out = run(cases); bad = badd = badb = 0
for ln, (absp, fill, close_, p) in zip(out, exp):
    t = ln.split()[1:]
    got_in = bool(int(t[0])); got_d = float(t[1]); pa = (float(t[2]), float(t[3])); pb = (float(t[4]), float(t[5]))
    want_in = even_odd(absp, p)
    # the C++ test is a crossing count towards +x with a 0.5 offset: skip points within 0.5 of an edge's x-range ends
    near_edge = min(seg_nearest(absp[i], absp[(i + 1) % len(absp)], p)[0] for i in range(len(absp))) < 0.6
    if not near_edge: bad += got_in != want_in
    # distance
    segs = [(absp[i], absp[i + 1]) for i in range(len(absp) - 1)]
    cl = min([100.0] + [seg_nearest(a, b, p)[0] for a, b in segs])
    if (fill or close_) and len(absp) > 2: cl = min(cl, seg_nearest(absp[-1], absp[0], p)[0])
    far = not (min(x for x, _ in absp) - 10 <= p[0] <= max(x for x, _ in absp) + 10 and min(y for _, y in absp) - 10 <= p[1] <= max(y for _, y in absp) + 10)
    want_d = 100.0 if far else (0.0 if (fill and want_in and not near_edge) else cl)
    if not (near_edge and fill) and not close(got_d, want_d, 1e-7):
        badd += 1
        if badd <= 3: print("   PG dist", ln[:80], got_d, want_d)
    # bounding box
    exp_a = (min(x for x, _ in absp), min(y for _, y in absp)); exp_b = (max(x for x, _ in absp), max(y for _, y in absp))
    badb += not (pa == exp_a and pb == exp_b)
report("polygon inside (even-odd)", len(cases), bad)
report("polygon distance", len(cases), badd)
report("polygon bounding box", len(cases), badb)

# ---------------- 8. built-in invariants ----------------
r = run(["INV"])[-1].split()
report("rotation/direction invariants", int(r[1]), int(r[2]))

total_bad = sum(b for _, b in results.values())
print("\nALL GEOMETRY CHECKS PASSED" if total_bad == 0 else f"\n{total_bad} mismatches")
