"""Rung grid (the sheet's hidden spreadsheet of rung numbers): layout, numbering, line awareness, clicking, saving and properties,
against references written independently in Python (a model of the spreadsheet as the specification describes it)."""
import os, sys, math, random, subprocess
BUILD = os.environ.get("TC_BUILD", "build")
EXE = os.path.join(BUILD, "rungtest")
random.seed(23)
fails = []
CW, CH, PAD = 7.0, 12.0, 5.0         # fixed test metrics; the pad between a number and its cell edge
def run(lines):
    r = subprocess.run([EXE], input="\n".join(lines) + "\n", capture_output=True, text=True)
    if r.returncode != 0: raise SystemExit("rungtest failed: " + r.stderr[-300:])
    return r.stdout.strip().split("\n")
def check(name, ok, detail=""):
    if not ok: fails.append(name); print("  FAIL", name, detail)

class Grid:
    """The spreadsheet of the specification: the sheet less an indent; per page a number column and a blank column."""
    def __init__(s, w, h, inset, margin, rows, start, pages, cont):
        s.w, s.h, s.inset, s.margin, s.rows, s.start, s.pages, s.cont = w, h, inset, margin, rows, start, pages, cont
        m = min(margin * 5 + inset, min(w, h) / 2)
        s.l, s.t, s.r, s.b = m, m, w - m, h - m
        s.rowh = (s.b - s.t) / rows
    def number(s, page, row): return s.start + row + (s.rows if page == 1 and s.cont else 0)
    def shown(s):                                   # every number printed on the sheet
        return [s.number(p, r) for p in range(s.pages) for r in range(s.rows)]
    def colw(s):
        wide = max(len(str(n)) for n in s.shown()) * CW + 2 * PAD
        return min(wide, s.w / s.pages - s.l)
    def cols(s):
        out = []
        for p in range(s.pages):
            left = s.l if p == 0 else s.w / 2
            right = s.w / 2 if (s.pages == 2 and p == 0) else s.r
            c = min(right, left + s.colw())
            out.append(((left, s.t, c, s.b), (c, s.t, right, s.b)))
        return out
    def text(s):
        v = s.rowh / 5
        t = f"{v:.2f}".rstrip("0").rstrip(".")
        return t + " mm"
    def text_ties(s): return abs((s.rowh / 5) * 100 % 1 - 0.5) < 1e-6
    def text_box(s, p):
        c0 = s.cols()[p][0]; w = CW * len(s.text())
        return (c0[0], c0[1] - PAD - CH, c0[0] + w, c0[1] - PAD)
    def at(s, x, y):
        if y < s.t or y > s.b or x < s.l or x > s.r: return None
        row = min(s.rows - 1, math.floor((y - s.t) / s.rowh))
        page = 1 if (s.pages == 2 and x >= s.w / 2) else 0
        return s.number(page, row)
    def clickable(s, x, y, showh):
        for p in range(s.pages):
            c = s.cols()[p][0]
            if c[0] <= x <= c[2] and c[1] <= y <= c[3]: return True
            if showh:
                t = s.text_box(p)
                if t[0] <= x <= t[2] and t[1] <= y <= t[3]: return True
        return False

def random_grid(big_start=True):
    w = random.choice([1485, 1050, 1000, 1700, 2100, 600 + random.randint(0, 1500)]); h = random.choice([1050, 740, 800, 1200, 500 + random.randint(0, 800)])
    inset = random.choice([0, 0, 31.75, 25, 12.5]); margin = random.choice([0, 1, 5, 5, 7.5, 12.25, 20.3, 90, 250])   # (the large ones are wider than the sheet allows: the indent stops at the middle)
    rows = random.randint(1, 60); start = random.choice([1, 1, 0, 101, -20, 9990, 1]) if big_start else 1
    return Grid(w, h, inset, margin, rows, start, random.choice([1, 2]), random.choice([0, 1]))
def args(g): return f"{g.w} {g.h} {g.inset} {g.margin} {g.rows} {g.start} {g.pages} {int(g.cont)}"
def close(a, b, eps=1e-6): return all(abs(float(x) - y) < eps for x, y in zip(a, b)) and len(a) == len(b)

# ---------- layout: the area, the columns, the row height ----------
bad = 0; N = 1500
for _ in range(N):
    g = random_grid()
    if g.text_ties(): continue
    out = run([f"LAYOUT {args(g)}"])
    head = out[0].split(None, 1)[1]
    nums, txt = head.split(" [")
    v = nums.split()
    want = [g.l, g.t, g.r, g.b, g.rowh, g.colw()]
    ok_ = close(v, want) and txt.rstrip("]") == g.text()
    cols = [l.split() for l in out[1:-1]]
    flat = [c for pair in g.cols() for c in pair]
    ok_ = ok_ and len(cols) == len(flat) and all(close(c[3:], w) for c, w in zip(cols, flat))
    bad += not ok_
    if not ok_ and bad <= 3: print("   LAYOUT", g.__dict__, out, want, flat)
check("layout: area, row height, number column width, four columns", bad == 0, str(bad))
print(f"layout: {N} sheets (paper sizes, border insets, indents, 1..60 rows, 1 or 2 pages, negative and big numbers): area, row height, columns, row height text ({bad} differ)")

# the specification's own sentences, with plain numbers
out = run(["LAYOUT 1485 1050 0 5 20 1 1 1"])
check("one page: second column reaches the right indent", out[2].split()[3:] == ["49", "25", "1460", "1025"], str(out))
out = run(["LAYOUT 1485 1050 0 5 20 1 2 1"])
cols = {(l.split()[1], l.split()[2]): [float(x) for x in l.split()[3:]] for l in out[1:-1]}
check("two pages: column 2 ends at the middle of the sheet", cols[("0", "1")][2] == 742.5, str(cols))
check("two pages: column 3 starts at the middle of the sheet", cols[("1", "0")][0] == 742.5, str(cols))
check("two pages: column 4 reaches the right indent", cols[("1", "1")][2] == 1460, str(cols))
check("indent on all four sides", cols[("0", "0")][:2] == [25, 25] and cols[("1", "1")][2:] == [1460, 1025], str(cols))
out = run(["LAYOUT 1485 1050 31.75 5 20 1 1 1"]); area = out[0].split()[1:5]
check("border adds its margin to the indent", [float(x) for x in area] == [56.75, 56.75, 1428.25, 993.25], str(area))
print("specified layout: 1 page = number column + blank to the right indent; 2 pages = columns 1/2 to the middle, 3/4 from the middle; the border margin adds to the indent")

# ---------- numbering ----------
cases, exp = [], []
for _ in range(1500):
    g = random_grid(); p = random.randrange(g.pages); r = random.randrange(g.rows)
    cases.append(f"NUM {args(g)} {p} {r}"); exp.append((g, p, r))
bad = 0
for line, (g, p, r) in zip(run(cases), exp):
    v = line.split(); cell = g.cols()[p][0]
    want_cell = (cell[0], g.t + r * g.rowh, cell[2], g.t + (r + 1) * g.rowh)
    ok_ = int(v[1]) == g.number(p, r) and close(v[2:], want_cell)
    bad += not ok_
    if not ok_ and bad <= 3: print("   NUM", g.__dict__, p, r, line, want_cell)
check("rung numbers and cells", bad == 0, str(bad))
print(f"numbering: 1500 cells, number = first + row (+ rows of page 1 when continuing), cell = column width by one row height ({bad} differ)")

# ---------- line number awareness: the number at any point of the area ----------
cases, exp = [], []
for _ in range(4000):
    g = random_grid(); x = random.uniform(-20, g.w + 20); y = random.uniform(-20, g.h + 20)
    if random.random() < 0.5: x = random.uniform(g.l - 8, g.r + 8); y = random.uniform(g.t - 8, g.b + 8)
    cases.append(f"AT {args(g)} {x} {y}"); exp.append((g, x, y))
bad = inside = 0
for line, (g, x, y) in zip(run(cases), exp):
    want = g.at(x, y); got = line.split()[1]
    if want is not None: inside += 1
    ok_ = (got == "none") if want is None else (got == str(want))
    bad += not ok_
    if not ok_ and bad <= 3: print("   AT", g.__dict__, x, y, line, want)
check("line number at a point", bad == 0, str(bad))
print(f"line awareness: 4000 points ({inside} inside the area, the rest in the indent or off the sheet): rung by height, page by side of the sheet middle ({bad} differ)")
# on the rungs' boundaries
g = Grid(1485, 1050, 0, 5, 20, 1, 2, 1)
bounds = [f"AT {args(g)} 100 {g.t + k * g.rowh}" for k in range(0, 21)] + [f"AT {args(g)} {x} 500" for x in (742.4999, 742.5, 742.5001)]
got = [l.split()[1] for l in run(bounds)]
want = [str(g.at(100, g.t + k * g.rowh)) for k in range(21)] + [str(g.at(x, 500)) for x in (742.4999, 742.5, 742.5001)]
check("row and page boundaries", got == want, f"{got} {want}")
check("the middle of the sheet belongs to page 2", got[-2] == str(g.at(742.5, 500)) and got[-2] != got[-3], str(got[-3:]))
print("boundaries: the top edge of a rung is that rung, the bottom edge of the area is the last rung, the middle of the sheet is page 2")

# ---------- clicking: only the number columns (and the row height text) ----------
cases, exp = [], []
for _ in range(4000):
    g = random_grid()
    if g.text_ties(): continue
    showh = random.choice([0, 1]); kind = random.choice(["col", "col", "blank", "text", "any"])
    c = g.cols()[random.randrange(g.pages)]
    if kind == "col": x = random.uniform(c[0][0], c[0][2]); y = random.uniform(c[0][1], c[0][3])
    elif kind == "blank": x = random.uniform(c[1][0], c[1][2]); y = random.uniform(c[1][1], c[1][3])
    elif kind == "text":
        t = g.text_box(random.randrange(g.pages)); x = random.uniform(t[0], t[2]); y = random.uniform(t[1], t[3])
    else: x = random.uniform(0, g.w); y = random.uniform(0, g.h)
    cases.append(f"HIT {args(g)} {showh} {x} {y}"); exp.append((g, showh, x, y, kind))
bad = 0; hits = 0
for line, (g, showh, x, y, kind) in zip(run(cases), exp):
    v = line.split(); d = float(v[1]); sel = int(v[2])
    want = g.clickable(x, y, showh); hits += want
    ok_ = (abs(d) < 1e-9 if want else abs(d - 100) < 1e-9) and sel == (1 if want else 0)
    if not want:                                  # a point inside 3 units of the area of a column is not a hit either: tolerance applies to distance 0 only
        ok_ = ok_ and sel == 0
    bad += not ok_
    if not ok_ and bad <= 3: print("   HIT", g.__dict__, showh, x, y, kind, line, want)
check("only the number columns and the printed height can be clicked", bad == 0, str(bad))
print(f"click test: {len(cases)} points ({hits} on a number column or the printed height; the blank columns and the rest of the sheet are not selectable) ({bad} wrong)")

cases, exp = [], []
for _ in range(2500):
    g = random_grid()
    if g.text_ties(): continue
    showh = random.choice([0, 1])
    l = random.uniform(0, g.w); t = random.uniform(0, g.h); r = l + random.uniform(1, 400); b = t + random.uniform(1, 300)
    cases.append(f"BOX {args(g)} {showh} {l} {r} {t} {b}"); exp.append((g, showh, l, r, t, b))
bad = 0
for line, (g, showh, l, r, t, b) in zip(run(cases), exp):
    boxes = [c[0] for c in g.cols()] + ([g.text_box(p) for p in range(g.pages)] if showh else [])
    want = any(not (bx[2] < l or bx[0] > r or bx[3] < t or bx[1] > b) for bx in boxes)
    bad += int(line.split()[1]) != int(want)
check("rectangle selection", bad == 0, str(bad))
print(f"selection rectangle: {len(cases)} cases, selected only when it touches a number column or the height text ({bad} wrong)")

# ---------- cannot be moved or rotated (bottom resize only) ----------
out = run(["MOVE 1485 1050 0 5 20 1 2 1", "MOVE 1000 700 31.75 3 7 1 1 0"])
check("grid does not move or rotate; it resizes from the bottom handle only", out == ["MOVE 1 1", "MOVE 1 1"], str(out))
print("shift and every rotation / mirror leave the grid where it is; its only resize handle is the bottom one")

# ---------- saved form ----------
out = run(["XML"])
check("xml round trip", out[0] == "XML 1|33|101|7.5|2|0|0|0000FF|0|1", out[0])
check("clone copies the settings", out[1] == "CLONE 0|33|101|7.5|2|0|0|0000FF", out[1])
print("save and reload: rows, first number, indent, pages, continue, show height, text colour come back; a clone copies them")
out = run(["BAD"])
check("out-of-range file values are brought into range", out[0] == "BAD 1 2 0", out[0])
print("a file with 0 rows, 7 pages and a negative indent loads as 1 row, 2 pages, indent 0")

# ---------- properties ----------
out = run(["PROPS"])
want_defs = "DEFS font.face,font.height,font.bold,font.italic,font.color,rungs.rows,rungs.start,rungs.margin,rungs.pages,rungs.continue,rungs.showheight,rungs.aboveblock,"
check("property list", out[0] == want_defs, out[0])
check("set and get properties", out[1] == "GET 35|GET -3|GET 12.5|GET 2 pages|GET 0|GET 0|", out[1])
check("bad property values", out[2] == "BADVALUES 35 -3 0 1" and out[3] == "ROWS0 1" and out[4] == "ROWS5000 200" and out[5] == "PAGES1 1", str(out[2:]))
print("properties: font, text colour, rows (1..200), first number, indent (>= 0), pages (1 or 2), continue, show height; bad text leaves the old number")
print("\nRUNG GRID CHECKS PASSED" if not fails else f"\nRUNG GRID CHECKS FAILED: {fails}")
sys.exit(1 if fails else 0)
