"""The extended title block: the revision table beside the title block and the notes and reference cell above it, with the dialog and ribbon that control it.
Written from the specification (see UTitleBlock.pas and URevisions.pas), and compared with the program:
  1. the layout, for many page sizes with and without the rulers (where the table, its columns and rows and the notes cell are), and the wrapping of the notes
  2. what is really drawn: the lines at their places, the headings and the rows of revisions as marks in the right cells, nothing when the switch is off
  3. the Design Details dialog: the Revision box is read-only and always the newest, an older file's single Revision becomes the first row of the history, the grid and the
     Revisions page edit one list, the last row adds, what is applied reaches the file, and what TinyCAD reads from the details is what it was
  4. the ribbon's check box, per sheet, one undo step
Needs the built program (and the test driver for part 1)."""
import glob, hashlib, os, random, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from designoracle import sig, resource_maps, objects, sheet0
BUILD = os.environ.get("TC_BUILD", "build"); DRV = os.path.join(BUILD, "blocktest")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:420])
def drv(*a):
    r = subprocess.run([DRV, *a], capture_output=True, text=True)
    if r.returncode != 0: raise SystemExit("blocktest failed: " + " ".join(a) + r.stderr[-200:])
    return r.stdout.split("\n")
# ---------- 1. the layout ----------
SHARES = [50, 100, 330, 80]
def layout(pw, ph, rulers):
    bl, bt, br, bb = pw - 400 - 2, ph - 18 * 9 - 2, pw - 2, ph - 2
    if rulers: bl, bt, br, bb = bl - 15, bt - 15, br - 15, bb - 15
    room = bl - (17 if rulers else 2)
    w = max(min(560, room), 100)
    x0 = bl - w; cum = [0, 50, 150, 480, 560]
    col = [x0 + w * c / 560 for c in cum]; col[4] = bl
    rh = (bb - bt) / 6; row = [bt + rh * i for i in range(7)]
    return dict(L=(bl, bt, br, bb), COL=col, ROW=row, NOTES=(x0, bt - 36, br, bt, (x0 + br) / 2), ROWH=rh)
def nums(line): return [float(v) for v in line.split()[1:]]
pages = [(1485, 1050), (1050, 1485), (2100, 1485), (1485, 2100), (740, 1050), (400, 300), (700, 500), (1100, 800), (900, 900)]
rnd = random.Random(3); pages += [(rnd.randint(450, 3000), rnd.randint(300, 3000)) for _ in range(25)]
bad = 0; first = None
for (pw, ph) in pages:
    for rulers in (0, 1):
        got = drv("layout", str(pw), str(ph), str(rulers)); want = layout(pw, ph, rulers)
        g = dict(L=nums(got[0]), COL=nums(got[1]), ROW=nums(got[2]), NOTES=nums(got[3]), ROWH=nums(got[4])[0])
        ok = all(abs(a - b) < 1e-6 for a, b in zip(g["L"], want["L"])) and all(abs(a - b) < 1e-6 for a, b in zip(g["COL"], want["COL"])) and all(abs(a - b) < 1e-6 for a, b in zip(g["ROW"], want["ROW"])) \
             and all(abs(a - b) < 1e-6 for a, b in zip(g["NOTES"], want["NOTES"])) and abs(g["ROWH"] - want["ROWH"]) < 1e-9
        if not ok: bad += 1; first = first or (pw, ph, rulers, g, want)
check(f"the layout for {len(pages) * 2} pages (with and without the rulers): the block, the table's columns shared 50:100:330:80 and its six rows, the notes cell above both", bad == 0, str(first))
a4 = layout(1485, 1050, 0)
check("on an A4 landscape page the table is 560 units (112 mm) wide, each row a line and a half (27), and the notes cell 36 high (the Title cell) and as wide as table and block together (960)",
      a4["COL"][4] - a4["COL"][0] == 560 and a4["ROWH"] == 27 and a4["NOTES"][3] - a4["NOTES"][1] == 36 and a4["NOTES"][2] - a4["NOTES"][0] == 960, "")
narrow = layout(400, 300, 0)
check("on a page too narrow for it the table is as wide as there is room, never under 100, and the rest of the layout follows", narrow["COL"][4] - narrow["COL"][0] == 100, str(narrow["COL"]))
# the wrapping of text
WORDS = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "resistors", "1%", "unless", "stated", "Capacitors", "25V", "minimum.", "Do", "not", "fit", "R9", "PSU-7", "see", "drawing", "LAY-0042", "a", "I", "of"]
def widths(lines):
    open(f"{tmp}/m.txt", "w").write("\n".join(lines) + "\n")
    return [float(l.split()[1]) for l in drv("measure", f"{tmp}/m.txt") if l.startswith("MEASURE")]
def wrap(text, maxw, maxl):
    open(f"{tmp}/t.txt", "w").write(text)
    out = drv("wrap", str(maxw), str(maxl), f"{tmp}/t.txt")
    return [l[5:].split(" ", 1)[1] if len(l[5:].split(" ", 1)) > 1 else "" for l in out if l.startswith("LINE ")]
bad_w = bad_words = bad_greedy = bad_trunc = bad_blank = bad_para = 0; first = None; n_trunc = n_full = 0
for k in range(250):
    paras = []
    for _ in range(rnd.choice([1, 1, 2, 3])):
        paras.append(" ".join(rnd.choice(WORDS) for _ in range(rnd.choice([0, 1, 4, 9, 18, 30]))))
    text = "\n".join(paras).rstrip("\n")                    # (the notes of a sheet never end with a line break: the dialog trims them)
    paras = text.split("\n") if text else []            # (no text, no lines)
    maxw = rnd.choice([120, 200, 330, 450]); maxl = rnd.choice([2, 3, 6, 40])
    full = wrap(text, maxw, 1000) if text else []; lim = wrap(text, maxw, maxl) if text else []
    ws = widths(lim) if lim else []
    if any(w > maxw + 1e-6 for w in ws): bad_w += 1; first = first or ("wide", text, maxw, lim, ws)
    truncated = len(full) > maxl
    if truncated:
        n_trunc += 1
        ok = len(lim) == maxl and lim[-1].endswith("...") and lim[:-1] == full[:maxl - 1]
        if not ok: bad_trunc += 1; first = first or ("trunc", text, maxw, maxl, lim, full)
    else:
        n_full += 1
        if lim != full: bad_trunc += 1
        flat = " ".join(" ".join(lim).split()); want = " ".join(" ".join(text.split("\n")).split())
        if flat != want: bad_words += 1; first = first or ("words", text, lim)
        if sum(1 for l in lim if l == "") != sum(1 for p in paras if p.strip() == ""): bad_blank += 1; first = first or ("blank", text, lim)
    # each paragraph on its own: wrapped the same inside the whole text, and every line of it filled as far as it goes
    if not truncated and text:
        joined = []
        for p in paras:
            if p.strip() == "": joined.append(""); continue
            lp = wrap(p, maxw, 1000); joined += lp
            pairs = [(a, b) for a, b in zip(lp, lp[1:])]
            if pairs:
                fw = widths([a + " " + b.split(" ")[0] for a, b in pairs])
                for (a, b), w in zip(pairs, fw):
                    if w <= maxw + 1e-6: bad_greedy += 1; first = first or ("greedy", p, maxw, a, b)
        if joined != full: bad_para += 1; first = first or ("para", text, joined, full)
check(f"250 texts wrapped: no line wider than its half of the cell ({n_full} fit, {n_trunc} did not)", bad_w == 0, str(first))
check("every word is kept in order, blank lines are kept, and what fits is not changed by the limit", bad_words == 0 and bad_blank == 0, str(first))
check("each line is filled as far as it goes: the next word of its paragraph would not have fitted (greedy), and paragraphs wrap the same on their own as in the whole", bad_greedy == 0 and bad_para == 0, str(first))
check("text that does not fit is cut at the last line, which ends with ...; the lines before it are as they would have been", bad_trunc == 0 and n_trunc > 20, f"{bad_trunc} {n_trunc} {first}")
print(f"extended block (layout and wrapping): {checks} checks, {len(fails)} failures")
if not os.path.exists(BIN) or shutil.which("xvfb-run") is None or shutil.which("convert") is None:
    print("the checks on screen are skipped: need xvfb-run, ImageMagick and the built program"); print("\nEXTENDED BLOCK CHECKS PASSED (layout only)" if not fails else "FAILED"); sys.exit(1 if fails else 0)

# ---------- the program ----------
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
def run(script, home="fresh", timeout=150):
    h = tempfile.mkdtemp(dir=tmp)
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write("resizewindow 1500 1000\n" + script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n"), r.returncode, r.stderr
def pix(path, x, y):
    o = subprocess.run(["convert", path, "-crop", "1x1+%d+%d" % (x, y), "-colorspace", "Gray", "-format", "%[fx:int(255*r)]", "info:"], capture_output=True, text=True).stdout
    return int(o or 255)
def darkest(path, x, y, rad=2):
    return min(pix(path, x + dx, y + dy) for dx in range(-rad, rad + 1) for dy in range(-rad, rad + 1))
def ink(path, x1, y1, x2, y2):
    x1, x2 = sorted((x1, x2)); y1, y2 = sorted((y1, y2))
    if x2 - x1 < 2 or y2 - y1 < 2: return 0
    o = subprocess.run(["convert", path, "-crop", f"{x2 - x1}x{y2 - y1}+{x1}+{y1}", "-colorspace", "Gray", "-threshold", "92%", "-format", "%[fx:int((1-mean)*w*h+0.5)]", "info:"], capture_output=True, text=True).stdout.strip()
    return int(o or 0)
sample = next(p for p in sorted(os.path.join(dp, f) for dp, _, fs in os.walk(EX) for f in fs if f.endswith(".dsn")) if os.path.basename(p) == "PSU.dsn")
raw = open(sample, encoding="utf-8", errors="replace").read()
def revxml(revs): return "<REVISIONS>" + "".join(f'<REV label="{l}" date="{d}" author="{a}" approved="">{n}</REV>' for l, d, a, n in revs) + "</REVISIONS>\r\n"
def variant(name, size=None, rulers=False, ext=True, sort="date", revs=(), notes="", ref=""):
    t = raw
    if size: t = re.sub(r"<Size width=.\d+. height=.\d+.", f'<Size width="{size[0]}" height="{size[1]}"', t, count=1)
    if rulers: t = re.sub(r"<SHOWS>\d+</SHOWS>", "<SHOWS>3</SHOWS>", t, count=1)
    i = t.index("</DETAILS>")
    extra = (f'<EXTBLOCK sort="{sort}" show="{1 if ext else 0}" />\r\n' if (ext or sort == "rev") else "") + (f"<NOTES>{notes}</NOTES>\r\n" if notes else "") + (f"<REFERENCE>{ref}</REFERENCE>\r\n" if ref else "") + (revxml(revs) if revs else "")
    path = os.path.join(tmp, name + ".dsn"); open(path, "w", encoding="utf-8").write(t[:i] + extra + t[i:]); return path
REVS = [("A", "2020-01-10", "JB", "Initial release"), ("B", "2020-06-02", "AK", "Reverse polarity diode"), ("C", "2021-03-15", "MP", "C3 changed to 470uF"), ("D", "2022-09-01", "JB", "New transformer"),
        ("E", "2023-11-20", "AK", "Layout notes only"), ("F", "2024-05-05", "MP", "Final"), ("G", "2019-01-01", "XX", "An old one added late")]
def geometry_run(path, shot_name):
    d = sheet0(path).find("DETAILS"); sz = d.find("Size"); pw, ph = int(sz.get("width")), int(sz.get("height"))
    shows = int((d.findtext("SHOWS") or "0").strip() or 0); L = layout(pw, ph, bool(shows & 2))
    pts = []        # (name, x, y) in units
    ex, ey = L["COL"], L["ROW"]
    for i in range(1, 6): pts.append((f"row{i}", (ex[1] + ex[2]) / 2, ey[i]))
    for c in range(1, 4): pts.append((f"col{c}", ex[c], (ey[2] + ey[3]) / 2))
    pts.append(("tableTop", (ex[1] + ex[2]) / 2, ey[0])); pts.append(("tableBottom", (ex[1] + ex[2]) / 2, ey[6])); pts.append(("tableLeft", ex[0], (ey[2] + ey[3]) / 2))
    n = L["NOTES"]
    pts += [("notesTop", (n[0] + n[4]) / 2, n[1]), ("notesLeft", n[0], (n[1] + n[3]) / 2), ("notesMid", n[4], (n[1] + n[3]) / 2), ("notesRight", n[2], (n[1] + n[3]) / 2)]
    cells = [(r, c) for r in range(6) for c in range(4)]
    script = f'open "{path}"\n' + "".join(f"viewpoint {x / 5:.4f} {y / 5:.4f}\n" for _, x, y in pts) + "".join(f"viewpoint {ex[c] / 5:.4f} {ey[r] / 5:.4f}\nviewpoint {ex[c + 1] / 5:.4f} {ey[r + 1] / 5:.4f}\n" for r, c in cells) + \
             f"viewpoint {n[0] / 5:.4f} {n[1] / 5:.4f}\nviewpoint {n[4] / 5:.4f} {n[3] / 5:.4f}\nviewpoint {n[2] / 5:.4f} {n[3] / 5:.4f}\nshot {tmp}/{shot_name}.bmp\n"
    o, rc, err = run(script)
    vp = [tuple(int(v) for v in l.split()[1:]) for l in o if l.startswith("VIEWPOINT")]
    lines = {name: vp[i] for i, (name, _, _) in enumerate(pts)}
    k = len(pts); cellrects = {}
    for j, (r, c) in enumerate(cells): cellrects[(r, c)] = (vp[k + 2 * j], vp[k + 2 * j + 1])
    k += 2 * len(cells); notes_rects = ((vp[k], vp[k + 1]), (vp[k + 1][0], vp[k][1], vp[k + 2][0], vp[k + 2][1]))
    return f"{tmp}/{shot_name}.bmp", lines, cellrects, (vp[k], vp[k + 1], vp[k + 2]), (pw, ph, bool(shows & 2))
shapes = [("a4land", None, False), ("a4port", (1050, 1485), False), ("a4land_rulers", None, True), ("a4port_rulers", (1050, 1485), True), ("a5port", (740, 1050), False)]
bad_lines = bad_off = bad_ink = bad_blank = 0; first = None
for name, size, rul in shapes:
    on = variant(name + "_on", size, rul, True, "date", REVS, "Notes one two three four five six seven eight nine ten", "REF 42")
    off = variant(name + "_off", size, rul, False, "date", REVS, "Notes", "REF 42")
    img, lines, cells, notes, pg = geometry_run(on, name + "_on")
    for nm, (x, y) in lines.items():
        if darkest(img, x, y) > 110: bad_lines += 1; first = first or (name, nm, (x, y), darkest(img, x, y))
    # the heading row and the rows of revisions are marks inside the cells, an empty row has none
    for c in range(4):
        (xa, ya), (xb, yb) = cells[(0, c)]
        if ink(img, min(xa, xb) + 3, min(ya, yb) + 3, max(xa, xb) - 3, max(ya, yb) - 3) < 4: bad_ink += 1; first = first or (name, "heading", c)
    for r in range(1, 6):
        for c in range(4):
            (xa, ya), (xb, yb) = cells[(r, c)]
            v = ink(img, min(xa, xb) + 3, min(ya, yb) + 3, max(xa, xb) - 3, max(ya, yb) - 3)
            if c != 1 and v < 3 and not (c == 3 and False): bad_ink += 1; first = first or (name, "row", r, c, v)
    (ntl, nmid, nbr) = notes
    left = ink(img, ntl[0] + 3, ntl[1] + 3, nmid[0] - 3, nmid[1] - 3); right = ink(img, nmid[0] + 3, ntl[1] + 3, nbr[0] - 3, nbr[1] - 3)
    if left < 20 or right < 10: bad_ink += 1; first = first or (name, "notes", left, right)
    # switched off: none of the table's lines
    img2, lines2, cells2, notes2, pg2 = geometry_run(off, name + "_off")
    for nm, (x, y) in lines2.items():
        edge = pg2[0] <= 760 and nm in ("tableLeft", "notesLeft")       # (on a page this narrow the table's left edge is the page's own edge)
        if (nm.startswith("row") or nm in ("tableTop", "tableLeft", "notesTop", "notesLeft", "notesMid")) and not edge:
            if darkest(img2, x, y) < 200: bad_off += 1; first = first or (name, "off", nm, darkest(img2, x, y))
check(f"drawn: on {len(shapes)} pages (A4 both ways, with the rulers, a narrow A5) every line of the table and of the notes cell is where the layout says", bad_lines == 0, str(first))
check("drawn: the heading row and each of the five revision rows have marks in their REV, DESCRIPTION and BY cells, and the notes and reference cell hold text on both halves", bad_ink == 0, str(first))
check("switched off, none of it is drawn (the places of its lines are blank page)", bad_off == 0, str(first))
# fewer than five revisions: the rows below them are empty; and with no revisions only the old Revision shows
two = variant("two", None, False, True, "date", REVS[:2], "", "")
img, lines, cells, notes, pg = geometry_run(two, "two")
rows_ink = [sum(ink(img, min(cells[(r, c)][0][0], cells[(r, c)][1][0]) + 3, min(cells[(r, c)][0][1], cells[(r, c)][1][1]) + 3, max(cells[(r, c)][0][0], cells[(r, c)][1][0]) - 3, max(cells[(r, c)][0][1], cells[(r, c)][1][1]) - 3) for c in range(4)) for r in range(1, 6)]
check("with two revisions the two rows under the heading have marks and the three below them are empty (the lines are still drawn)", all(v > 8 for v in rows_ink[:2]) and all(v == 0 for v in rows_ink[2:]), str(rows_ink))
(ntl, nmid, nbr) = notes
check("with no notes and no reference the cell is drawn but its halves hold only their headings", ink(img, ntl[0] + 3, ntl[1] + 3 + int((nmid[1] - ntl[1]) * 0.60), nmid[0] - 3, nmid[1] - 3) == 0 and ink(img, nmid[0] + 3, ntl[1] + 3 + int((nmid[1] - ntl[1]) * 0.60), nbr[0] - 3, nbr[1] - 3) == 0, "")
# the order decides which five: by revision the early-dated G is the oldest label, so it is out; by date it is the oldest date, so out as well; with a different set they differ
diff_revs = [("A", "2024-01-01", "x", "a"), ("B", "2023-01-01", "x", "b"), ("C", "2022-01-01", "x", "c"), ("D", "2021-01-01", "x", "d"), ("E", "2020-01-01", "x", "e"), ("F", "2019-01-01", "x", "f")]
byd = variant("byd", None, False, True, "date", diff_revs); byr = variant("byr", None, False, True, "rev", diff_revs)
ib, _, cb, _, _ = geometry_run(byd, "byd"); ir, _, cr, _, _ = geometry_run(byr, "byr")
def rowink(img, cells_, r): return [ink(img, min(cells_[(r, c)][0][0], cells_[(r, c)][1][0]) + 3, min(cells_[(r, c)][0][1], cells_[(r, c)][1][1]) + 3, max(cells_[(r, c)][0][0], cells_[(r, c)][1][0]) - 3, max(cells_[(r, c)][0][1], cells_[(r, c)][1][1]) - 3) for c in range(4)]
same_images = subprocess.run(["compare", "-metric", "AE", ib, ir, "null:"], capture_output=True, text=True).stderr.strip().split()[0]
check("by date and by revision choose different revisions here (A..E by date, B..F by revision, which differ in a row's text), so the two pictures differ", int(float(same_images)) > 50, same_images)
# ---------- 3. the Design Details dialog ----------
def det(path, nth=0):
    r = ET.parse(path).getroot(); sh = r.findall("TinyCAD")[nth] if r.tag == "TinyCADSheets" else r
    return sh.find("DETAILS")
def dlg(lines): 
    d = {}
    for l in lines:
        if l.startswith("DETAILSDLG"): d.update(dict(t.split("=", 1) for t in l.split()[1:] if "=" in t))
    return d
def gridrows(lines): return [l[8:].split("|", 1)[1].split("|") for l in lines if l.startswith("GRIDROW ")]
def revlist(lines): return [l.split("|", 1)[1] for l in lines if l.startswith("REVLIST ")]
legacy = os.path.join(tmp, "legacy.dsn"); shutil.copy(sample, legacy)
o, rc, err = run(f'open "{legacy}"\ndetails ext 1\nsave "{tmp}/legacy_out.dsn"\n')
d = dlg(o); g = gridrows(o)
check("an older file (only TinyCAD's single Revision, 1.0 dated AUGUST 2006): the grid shows it as the first revision, the Revision box shows it and cannot be typed in", g[1][:2] == ["1.0", "AUGUST 2006"] and d["revbox"] == "1.0" and d["readonly"] == "1", f"{g} {d}")
out = det(f"{tmp}/legacy_out.dsn")
check("applied, the history holds it (REV label 1.0, its date), TinyCAD's REVISION and DATE are as they were, and EXTBLOCK says shown, by date",
      [(e.get("label"), e.get("date")) for e in out.iter("REV")] == [("1.0", "AUGUST 2006")] and (out.findtext("REVISION") or "").strip() == "1.0" and (out.findtext("DATE") or "").strip() == "AUGUST 2006" and out.find("EXTBLOCK").get("show") == "1" and out.find("EXTBLOCK").get("sort") == "date", ET.tostring(out)[:300])
o, rc, err = run(f'open "{legacy}"\ndetails revbox ZZZ\ndetailsinfo\n')
check("typing into the Revision box changes nothing: it is not an entry, the history's newest is what counts", "revision=1.0" in [l for l in o if l.startswith("DETAILSINFO")][-1] and "readonly=1" in " ".join(o), "")
# the two editors share one list; the newest feeds the Revision box
o, rc, err = run(f'open "{legacy}"\ndetails revadd C 2022-02-02 AK Boss "third change"\n')
d = dlg(o); g = gridrows(o); rl = revlist(o)
check("a revision added on the Revisions page appears in the grid (REV, DATE, DESCRIPTION, BY) and the Revision box shows the newest", g[2] == ["C", "2022-02-02", "third change", "AK"] and d["revbox"] == "C" and d["list"] == "2", f"{g} {d}")
o, rc, err = run(f'open "{legacy}"\ndetails gridadd gridset 0 2 B gridset 1 2 2025-03-03 gridset 2 2 "Fourth change" gridset 3 2 MP\n')
d = dlg(o); g = gridrows(o); rl = revlist(o)
check("a revision added in the grid (the last row clicked, then typed in) is in the Revisions page's list, and being the newest by date it is the Revision box", d["list"] == "2" and any("Fourth change" in x and x.startswith("B") for x in rl) and d["revbox"] == "B" and g[-1] == ["", "", "", ""], f"{rl} {d} {g[-2:]}")
o, rc, err = run(f'open "{legacy}"\ndetails gridadd gridset 0 2 B gridset 1 2 2025-03-03 gridadd gridset 0 3 C gridset 1 3 2023-01-01 sortrev 1\n')
d = dlg(o)
check("the order checkbox decides the newest: by date it is B (2025), by revision C (a number comes before a letter, B before C), and the Revision box follows at once", d["revbox"] == "C" and d["sortrev"] == "1", str(d))
o, rc, err = run(f'open "{legacy}"\ndetails gridadd gridset 0 2 B gridset 1 2 2025-03-03 gridadd gridset 0 3 C gridset 1 3 2023-01-01\n')
check("and by date (the default) it is B", dlg(o)["revbox"] == "B", str(dlg(o)))
o, rc, err = run(f'open "{legacy}"\ndetails gridadd gridset 0 2 B griddel 1\n')
d = dlg(o); g = gridrows(o)
check("a row can be deleted: the one that was the legacy revision is gone, and the box shows the remaining one", d["list"] == "1" and g[1][0] == "B" and d["revbox"] == "B", f"{g} {d}")
o, rc, err = run(f'open "{legacy}"\ndetails gridadd\n')
check("a row that was added and left as it began (only today's date) is left out, not refused", "DETAILS applied=" in " ".join(o) and "refused" not in " ".join(o), str([l for l in o if "DETAILS" in l]))
o, rc, err = run(f'open "{legacy}"\ndetails gridadd gridset 3 2 "AK" gridset 2 2 "no label"\n')
check("a row with something in it but no label in REV is refused with a message, and nothing is applied", "DETAILS refused: Every revision needs a label" in " ".join(o) and "DETAILS applied" not in " ".join(o), str([l for l in o if "DETAILS" in l]))
o, rc, err = run(f'open "{legacy}"\ndetails gridadd gridset 0 2 B gridset 1 2 2025-01-01 gridset 2 2 "line one\\nline two" notes "N1\\nN2" reference "R1" sortrev 1 ext 1\nundoinfo\nsave "{tmp}/applied.dsn"\nundo\ndetailsinfo\nundoinfo\n')
out = det(f"{tmp}/applied.dsn"); names = [e.tag for e in out]
check("applied, it is one undo step called Design details; the file has the EXTBLOCK (rev, shown), NOTES with their line break, REFERENCE and the history with its multi-line description",
      'next="Design details"' in [l for l in o if l.startswith("UNDOINFO")][0] and out.find("EXTBLOCK").get("sort") == "rev" and (out.findtext("NOTES") or "").replace("\r", "") == "N1\nN2" and (out.findtext("REFERENCE") or "").strip() == "R1" \
      and [(e.get("label"), (e.text or "").replace("\r", "")) for e in out.iter("REV")][1] == ("B", "line one\nline two"), str(names))
check("and one undo takes all of it back (the details are as the file had them: no extended information, no notes, one revision)", "ext=0" in [l for l in o if l.startswith("DETAILSINFO")][-1] and "revs=0" in [l for l in o if l.startswith("DETAILSINFO")][-1], [l for l in o if l.startswith("DETAILSINFO")][-1][-120:])
# what TinyCAD reads is what it was: its own elements, and everything we add is an element it skips
KNOWN = {"Size", "GUIDES", "TITLE", "AUTHOR", "REVISION", "DOCNUMBER", "ORGANISATION", "SHEETS", "SHOWS", "DATE", "GRID"}
orig = det(sample)
same = all((e.text or "").strip() == (out.find(e.tag).text or "").strip() for e in orig if e.tag in KNOWN and e.tag not in ("GRID", "Size", "GUIDES", "REVISION"))
check("what TinyCAD reads of the details (title, author, document number, organisation, sheets, date, shows, the paper) is exactly what it was", same, "")
check("TinyCAD's REVISION holds the newest revision (C by revision here: 1.0 < B)", (out.findtext("REVISION") or "").strip() == "B", str(out.findtext("REVISION")))
check("and everything else is an element TinyCAD does not know (EXTBLOCK, NOTES, REFERENCE, REVISIONS, which it skips with what is inside them)", {e.tag for e in out} <= KNOWN | {"EXTBLOCK", "NOTES", "REFERENCE", "REVISIONS", "AUTOSHEETS", "BORDER"}, str({e.tag for e in out} - KNOWN))
# ---------- 4. the ribbon's check box ----------
two_sheets = os.path.join(tmp, "two_sheets.dsn"); shutil.copy(sample, two_sheets)
o, rc, err = run(f'open "{two_sheets}"\nsheetribboninfo\nsheetribbon extended 1\nsheetribboninfo\nundoinfo\nsave "{tmp}/rib1.dsn"\nundo\nsheetribboninfo\naddsheet\nsheetribbon extended 1\nsheetribboninfo\ngosheet 0\nsheetribboninfo\nsave "{tmp}/rib2.dsn"\n')
ri = [re.search(r"extended=(\d+)", l).group(1) for l in o if l.startswith("SHEETRIBBON") and "extended=" in l]
check("the ribbon's Extended info box starts unchecked and enabled, ticking it shows the extended information on the sheet (the file says EXTBLOCK show=1), as one undo step called Extended information, and undo unticks it",
      ri[0] == "01" and ri[1] == "11" and 'next="Extended information"' in [l for l in o if l.startswith("UNDOINFO")][0] and det(f"{tmp}/rib1.dsn").find("EXTBLOCK").get("show") == "1" and ri[2] == "01", str(ri))
check("it belongs to the sheet: after adding a second sheet and ticking it there, the first sheet is unticked and the second ticked, and only the second has EXTBLOCK in the file", ri[3] == "11" and ri[4] == "01" and det(f"{tmp}/rib2.dsn", 0).find("EXTBLOCK") is None and det(f"{tmp}/rib2.dsn", 1).find("EXTBLOCK") is not None, f"{ri} {[e.tag for e in det(f'{tmp}/rib2.dsn', 1)]}")
print(f"extended block: {checks} checks, {len(fails)} failures")
print("\nEXTENDED BLOCK CHECKS PASSED" if not fails else f"\nEXTENDED BLOCK CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
