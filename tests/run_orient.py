"""The way up of a picture (UOrient), on the core. Written from the geometry, not from the code:
  - the matrix a sequence of Rotate left, Rotate right and Flip leaves is found by following the picture's two directions through TinyCAD's own formulas for moving a point
    (left (x,y) -> (y,-x), right (x,y) -> (-y,x), flip (x,y) -> (-x,y), y down the screen), and compared with the program's, for every sequence of up to 6 operations
  - every sequence ends in one of eight orientations, each reached as a flip (or not) followed by 0 to 3 turns to the right, which is how it is kept in the file
  - a picture drawn in an orientation is an exact rearrangement of its pixels: found by moving each pixel forward to where it lands (the oriented picture's size, and the pixel that
    shows each place), for pictures of many shapes (including 1 pixel wide and 1 pixel high) in all eight orientations
Needs the built test driver."""
import itertools, os, random, subprocess, sys, tempfile
BUILD = os.environ.get("TC_BUILD", "build"); EXE = os.path.join(BUILD, "orienttest")
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:300])
def drv(mode, lines):
    open(f"{tmp}/in.txt", "w").write("\n".join(lines) + "\n")
    r = subprocess.run([EXE, mode, f"{tmp}/in.txt"], capture_output=True, text=True)
    if r.returncode != 0: raise SystemExit("orienttest failed: " + r.stderr[-300:])
    return [l for l in r.stdout.split("\n") if l]
# ---------- TinyCAD's movements of a point ----------
def move(p, op):
    x, y = p
    return {2: (y, -x), 3: (-y, x), 4: (-x, y)}[op]
def matrix_of(ops):
    """follow the picture's two directions, (1,0) along it and (0,1) down it, through the operations; the matrix has them as its columns"""
    cx, cy = (1, 0), (0, 1)
    for op in ops: cx, cy = move(cx, op), move(cy, op)
    return (cx[0], cy[0], cx[1], cy[1])           # (A, B, C, D): x' = A x + B y, y' = C x + D y
seqs = [()] + [s for n in range(1, 7) for s in itertools.product((2, 3, 4), repeat=n)]
lines = [" ".join(map(str, s)) for s in seqs]
out = drv("ops", lines); bad = []
for s, l in zip(seqs, out):
    t = l.split(); got = tuple(int(v) for v in t[1:5]); want = matrix_of(s)
    if got != want: bad.append((s, got, want))
check(f"{len(seqs)} sequences of up to 6 left, right and flip operations: the orientation they leave is the one the points' movements give", not bad and len(out) == len(seqs), str(bad[:3]))
# the eight orientations: a flip, then 0 to 3 turns right
def from_turns(t, m):
    ops = ([4] if m else []) + [3] * t
    return matrix_of(ops)
seen = {}; bad = []
for s, l in zip(seqs, out):
    t = l.split(); mat = tuple(int(v) for v in t[1:5]); turns, mirror, idx, swaps = int(t[5]), int(t[6]), int(t[7]), int(t[8])
    if turns < 0 or from_turns(turns, bool(mirror)) != mat or idx != turns + 4 * mirror or swaps != (1 if mat[1] != 0 else 0): bad.append((s, t))
    seen[mat] = (turns, mirror)
check("every sequence ends in one of the eight orientations, each as a flip (or none) and then 0 to 3 turns to the right, numbered turns + 4 if flipped; it swaps width and height exactly when a quarter turn is in it", not bad and len(seen) == 8, f"{len(seen)} {bad[:2]}")
check("turning left three times is turning right once, left and right undo each other, a flip twice is nothing, and a flip then a turn is not a turn then a flip (the order matters)",
      matrix_of((2, 2, 2)) == matrix_of((3,)) and matrix_of((2, 3)) == matrix_of(()) and matrix_of((4, 4)) == matrix_of(()) and matrix_of((4, 3)) != matrix_of((3, 4)), "")
# ---------- the pixels ----------
def oracle_map(mat, w, h):
    a, b, c, d = mat
    dw, dh = (h, w) if b != 0 else (w, h)
    dst = [None] * (dw * dh)
    for y in range(h):
        for x in range(w):
            sx, sy = (x + 0.5) / w - 0.5, (y + 0.5) / h - 0.5
            px, py = a * sx + b * sy, c * sx + d * sy
            X, Y = int((px + 0.5) * dw), int((py + 0.5) * dh)
            dst[Y * dw + X] = y * w + x
    return dw, dh, dst
shapes = [(1, 1), (2, 1), (1, 2), (3, 2), (2, 3), (4, 4), (5, 3), (3, 5), (6, 4), (7, 1), (1, 7), (9, 6), (16, 11)]
rnd = random.Random(4); shapes += [(rnd.randint(1, 20), rnd.randint(1, 20)) for _ in range(20)]
mats = sorted(set(matrix_of(s) for s in seqs)); cases = [(m, w, h) for m in mats for (w, h) in shapes]
out = drv("map", [f"{m[0]} {m[1]} {m[2]} {m[3]} {w} {h}" for m, w, h in cases]); bad = []
for (m, w, h), l in zip(cases, out):
    t = l.split(); gw, gh = int(t[1]), int(t[2]); got = [int(v) for v in t[3:]]
    ow, oh, want = oracle_map(m, w, h)
    if (gw, gh) != (ow, oh) or got != want or sorted(got) != list(range(w * h)): bad.append((m, w, h, got[:12], want[:12]))
check(f"{len(cases)} pictures (8 orientations, {len(shapes)} shapes from 1 x 1 to 20 x 20): the size is right and every place shows the pixel that moving the pixels forward puts there, with no pixel lost or repeated", not bad and len(out) == len(cases), str(bad[:2]))
check("a picture of 1 pixel wide or high, and of odd and even sizes, is among them", any(w == 1 or h == 1 for w, h in shapes) and any(w % 2 for w, h in shapes) and any(w % 2 == 0 for w, h in shapes), "")
print(f"orient: {checks} checks, {len(fails)} failures")
print("\nORIENT CHECKS PASSED" if not fails else f"\nORIENT CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
