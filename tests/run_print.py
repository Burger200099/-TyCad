"""The arithmetic of printing (UPrint) against printoracle.py, which restates TinyCadView.cpp's OnBeginPrinting / OnPrepareDC and the Print dialog's scale text. Needs the built printtest.

 - the pages of a sheet: columns, rows, which sheet and which part of it each page shows, and the print zoom, for every paper size of the sample designs, several printers,
   scales from tiny to huge, one sheet and all of them
 - the scale that fits a sheet on a page
 - the scale text (printf "%3.3lg") and the number read back from text (atof)
 - the range of pages asked for
"""
import os, random, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import printoracle as po

BUILD = os.environ.get("TC_BUILD", "/tmp/rb")
PT = os.path.join(BUILD, "printtest")
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:600])

def run(*a):
    return subprocess.run([PT] + [str(x) for x in a], capture_output=True, text=True).stdout.split("\n")

def run_many(cmds):
    """many commands in one launch of the driver: the answer to each"""
    r = subprocess.run([PT, "batch"], input="\n".join("\t".join(str(x) for x in c) for c in cmds) + "\n", capture_output=True, text=True)
    out = r.stdout.split("\n--\n")
    return [o.rstrip("\n").split("\n") for o in out[:len(cmds)]]

def close(a, b, eps=1e-9): return abs(a - b) <= eps * max(1.0, abs(a), abs(b))

random.seed(11)
# sheets in internal units (5 to the millimetre): A4 to A1 landscape and portrait, Letter, Legal, Ledger, the smallest and the largest the Page Setup dialog allows
papers = [(w * 5, h * 5) for (w, h) in [(297, 210), (420, 297), (594, 420), (840, 594), (279, 216), (210, 297), (297, 420), (216, 356), (432, 280), (10, 10), (2500, 2500), (300, 300), (150, 200)]]
printers = [(297, 210, 600), (210, 297, 600), (279, 216, 300), (200, 277, 1200), (190, 270, 72), (355, 216, 600), (1, 1, 300), (290, 200, 96), (297, 210, 150)]
scales = [100, 100, 50, 25, 200, 400, 33.3, 97.3, 150, 12.5, 1, 0.5, 1000, 10000, 100.4, 100.5, 101, 99.999, 66.7, 5]

def pages_of(hz, vt, pw, ph, sc, al, ns):
    """how many pages (cheaply, to leave out the huge ones)"""
    w = max(hz, vt) * 5; h = min(hz, vt) * 5
    sx, sy = ((sc * pw / h) / 100.0, (sc * ph / w) / 100.0) if pw < ph else ((sc * pw / w) / 100.0, (sc * ph / h) / 100.0)
    c = int(sx) + (1 if sx - int(sx) > 0.01 else 0); r = int(sy) + (1 if sy - int(sy) > 0.01 else 0)
    return max(c, 1) * max(r, 1) * (ns if al and ns > 1 else 1)

# ---------------------------------------------------------------- 1. layouts
n = 0
cases = [(p, d, s, a, ns) for p in papers for d in printers for s in scales for a in (0, 1) for ns in (1, 3)]
random.shuffle(cases)
cases = [c for c in cases if pages_of(c[1][0], c[1][1], c[0][0], c[0][1], c[2], c[3], c[4]) <= 300][:1500]
outs = run_many([("layout", hz, vt, dpi, pw, ph, sc, al, ns) for (pw, ph), (hz, vt, dpi), sc, al, ns in cases])
for ((pw, ph), (hz, vt, dpi), sc, al, ns), out in zip(cases, outs):
    exp = po.layout(hz, vt, dpi, pw, ph, sc, al, ns)
    head = out[0].split()
    ok = head[0] == "L" and [int(x) for x in head[1:5]] == [exp["cols"], exp["rows"], exp["sheets"], exp["pages"]] and close(float(head[5]), exp["zoom"])
    check("layout head %s" % ((pw, ph, hz, vt, dpi, sc, al, ns),), ok, (out[0], exp["cols"], exp["rows"], exp["sheets"], exp["pages"], exp["zoom"]))
    got = [tuple(int(x) for x in l.split()[1:]) for l in out[1:] if l.startswith("P ")]
    check("layout pages %s" % ((pw, ph, hz, vt, dpi, sc, al, ns),), got == exp["list"], (got[:3], exp["list"][:3], len(got), len(exp["list"])))
    n += 1
print("  layouts:", n)

# the cases worth naming
e = run("layout", 297, 210, 600, 1485, 1050, 100, 0, 1)
check("an A4 landscape sheet at 100% on an A4 landscape page is one page", e[0].startswith("L 1 1 1 1 "), e[0])
e = run("layout", 297, 210, 600, 2100, 1485, 100, 0, 1)
pg = [tuple(l.split()[1:]) for l in e[1:5]]
check("an A3 sheet at 100% on A4 is four pages, going down a column and then across", e[0].startswith("L 2 2 1 4 ") and pg == [("1", "0", "0", "0", "0", "0"), ("2", "0", "0", "1", "0", "1050"), ("3", "0", "1", "0", "1485", "0"), ("4", "0", "1", "1", "1485", "1050")], (e[0], pg))
e = run("layout", 297, 210, 600, 1485, 1050, 100, 1, 3)
pg = [tuple(l.split()[1:4]) for l in e[1:4]]
check("all sheets: the sheets go round first", e[0].startswith("L 1 1 3 3 ") and pg == [("1", "0", "0"), ("2", "1", "0"), ("3", "2", "0")], (e[0], pg))
check("one sheet of a design of three prints once", run("layout", 297, 210, 600, 1485, 1050, 100, 0, 3)[0].startswith("L 1 1 1 1 "))
check("half a per cent over exact stays one page; 101% (a hundredth and a rounding error over) takes two columns and rows", run("layout", 297, 210, 600, 1485, 1050, 100.5, 0, 1)[0].startswith("L 1 1 1 1 ") and run("layout", 297, 210, 600, 1485, 1050, 101, 0, 1)[0].startswith("L 2 2 1 4 "), run("layout", 297, 210, 600, 1485, 1050, 101, 0, 1)[0])
check("a tiny scale still takes a page (TinyCAD would take none)", run("layout", 297, 210, 600, 1485, 1050, 0.3, 0, 1)[0].startswith("L 1 1 1 1 "))
check("the zoom of 600 dpi at 100% is 4.72 (the integer 472 over 100)", close(float(run("layout", 297, 210, 600, 1485, 1050, 100, 0, 1)[0].split()[5]), 4.72))
check("the zoom of 300 dpi at 50% is 1.18", close(float(run("layout", 297, 210, 300, 1485, 1050, 50, 0, 1)[0].split()[5]), 1.18))
check("a portrait sheet is laid against the page's short side across", run("layout", 210, 297, 600, 1050, 1485, 100, 0, 1)[0].startswith("L 1 1 1 1 "))

# ---------------------------------------------------------------- 2. fit
cmds = [("fit", hz, vt, pw, ph) for (pw, ph) in papers for (hz, vt, dpi) in printers]
for (pw, ph), (hz, vt, dpi), out in zip([p for p in papers for _ in printers], printers * len(papers), run_many(cmds)):
    exp = po.fit_scale(hz, vt, pw, ph)
    check("fit %s" % ((pw, ph, hz, vt),), close(float(out[0]), exp), (out[0], exp))
# a sheet printed at the fit scale as the dialog shows it: the 1% allowance keeps it on one page
for (pw, ph) in papers[:8]:
    for (hz, vt, dpi) in printers[:5]:
        f = po.fit_scale(hz, vt, pw, ph)
        t = po.atof(po.scale_text(f))
        exp = po.layout(hz, vt, dpi, pw, ph, t, 0, 1)
        out = run("layout", hz, vt, dpi, pw, ph, t, 0, 1)
        check("the fit scale, as the dialog shows it, gives %d pages" % exp["pages"], out[0].split()[1:5] == [str(exp["cols"]), str(exp["rows"]), "1", str(exp["pages"])], (out[0], exp["pages"]))
        if f >= 10 and pw != ph:
            check("the fit text of %s keeps a %dx%d mm sheet on one page" % (f, pw // 5, ph // 5), exp["pages"] == 1, (f, t, exp["pages"]))

# ---------------------------------------------------------------- 3. the scale text and the number read from it
vals = [0, 1, 5, 9.99, 10, 12.5, 33.333, 97.34, 97.35, 99.95, 100, 100.4, 150, 999, 999.5, 1000, 1234, 12345.6, 99999, 0.5, 0.05, 0.0001, 0.00012345, 0.00001, 1e-7, 1e10, 123456789, 2.5e-3, -5, -97.34, 0.1, 0.2, 0.3, 1.005, 2.675]
for _ in range(60): vals.append(random.choice([1, 10, 100, 1000, 0.1, 0.01]) * random.random() * random.choice([1, 1, 10, 1000]))
for v, out in zip(vals, run_many([("text", repr(v)) for v in vals])):
    check("scale text of %r" % v, out[0] == "[" + po.scale_text(v) + "]", (out[0], po.scale_text(v)))
texts = ["100", " 100", "97.3", "  5", "1.23e+03", "1e5", "1e", "1e+", "1e+x", ".5", "5.", "-3", "+4.5", "abc", "", "12abc", "1,5", "0x10", "1.2.3", "  -.5e1z", "e5", "-", ".", "5 5", "007", "1E2", "99999999999999999999", "0.000001"]
tt = [t for t in texts if t != ""]
for t, out in zip(tt, run_many([("value", t) for t in tt])):
    exp = po.atof(t)
    check("number read from %r" % t, close(float(out[0]), exp), (out[0], exp))
check("number read from nothing is 0", float(run("value", "")[0]) == 0)

# ---------------------------------------------------------------- 4. page ranges
rc = [(pages, a, b) for pages in (0, 1, 4, 13) for a in (0, 1, 2, 5, 20, -1) for b in (0, 1, 3, 4, 100, -1)]
for (pages, a, b), out in zip(rc, run_many([("range", p, a, b) for (p, a, b) in rc])):
    ok, f, l = po.page_range(pages, a, b)
    check("range of %d pages %d-%d" % (pages, a, b), out[0].split() == ["R", str(int(ok)), str(f), str(l)], (out, ok, f, l))

print("  %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
