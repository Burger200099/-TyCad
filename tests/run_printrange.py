#!/usr/bin/env python3
"""The Print dialog's printer list, page range box and quick preview, on the real program under Xvfb.
Oracles that do not use the program's own code:
  - the page range box: the examples of the request written out by hand (1-2, 1 - 2, 1-2, 6, 1,2,6, 1, 2, 6, 1 to 6, 1 and 6, 1 through 6, 1 to 6 and 9) and a few hundred strings made
    from a grammar or spoiled, read by a second, regular-expression reader written here; errors are checked as errors, not by their text
  - what is printed: a print of "1,3" gives the pages 1 and 3 of the print of all the pages (found by where each sheet's green square is), in order, once each
  - the quick preview: the page drawn in the preview is compared (green squares of the design, in the shape of the printer's page) with the page the printer gets; a different page does not match
  - the slider, the < and > buttons and the label go through the pages asked for only
  - the printer drop down is filled, a pick reaches the main form, and without a printer it says so and is dimmed
Needs the built program and xvfb."""
import os, re, sys, random
HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "run_printdialog.py"), encoding="utf-8").read().split("# ---------------------------------------------------------------- 1. the menu")[0]
__file__ = os.path.join(HERE, "run_printdialog.py")
exec(compile(src, __file__, "exec"))
from PIL import Image
import numpy as np

def sized(n, w=1485, h=1050):
    return dict(w=w, h=h, rects=[(10 + 10 * n, 10 + 5 * n, 30 + 10 * n, 30 + 5 * n, 0, 1)], lines=[], rulers=[])
multi = os.path.join(tmp, "multi.dsn"); make_design(multi, [sized(0), sized(1), sized(2)])
def field(line, name):
    m = re.search(r"(?<![\w])%s=\[(.*?)\]( \w+=|$)" % name, line)
    return m.group(1) if m else None
def num(line, name):
    m = re.search(r"(?<![\w])%s=(-?\d+)" % name, line); return int(m.group(1)) if m else None

# ---- 1. the examples of the request
def pages_for(rng, opts="scale=300 sheets=all"):
    o, rc, err = run("open %s\nprintdialog %s range=%s press=cancel\n" % (multi, opts, rng.replace(" ", "~")), "rng%d" % abs(hash(rng + opts) % 100000))
    d = lines_of(o, "PRINTDIALOG")
    return d[0] if d else None
base = pages_for("1")
npages = int(re.search(r"pages=\[(\d+) page", base.split("| pressed")[1]).group(1))
check("the test print has many pages (scale 300, all sheets)", npages >= 20, npages)
EXAMPLES = [("1-2", [1, 2]), ("1 - 2", [1, 2]), ("1-2, 6", [1, 2, 6]), ("1,2,6", [1, 2, 6]), ("1, 2, 6", [1, 2, 6]), ("1 to 6", [1, 2, 3, 4, 5, 6]), ("1 and 6", [1, 6]),
            ("1 through 6", [1, 2, 3, 4, 5, 6]), ("1 to 6 and 9", [1, 2, 3, 4, 5, 6, 9]), ("1&3", [1, 3]), ("3-1", [1, 2, 3]), ("2 , 2 ,2", [2]), ("5", [5]),
            ("1 TO 3 AND 7", [1, 2, 3, 7]), ("4-6,1-2", [1, 2, 4, 5, 6]), ("1 ,2 and 3 & 5 to 6", [1, 2, 3, 5, 6])]
big = "scale=300 sheets=all"
script = "".join("printdialog %s range=%s press=cancel\n" % (big, r.replace(" ", "~")) for r, _ in EXAMPLES)
o, rc, err = run("open %s\n%s" % (multi, script), "examples")
d = lines_of(o, "PRINTDIALOG")
check("one answer for each example", len(d) == len(EXAMPLES), (len(d), err[-200:]))
for (r, want), line in zip(EXAMPLES, d):
    got = [int(x) for x in (field(line.split("| pressed")[1], "list") or "").split(",") if x]
    check("pages of %r" % r, got == want, (got, want, line[-300:]))

# ---- 2. fuzz against a second reader
def oracle(text, n):
    t = re.sub(r"\s+", "", text.lower())
    t = t.replace("through", "-").replace("to", "-").replace("and", ",").replace("&", ",")
    if not re.fullmatch(r"\d+(-\d+)?(,\d+(-\d+)?)*", t): return None
    pages = set()
    for part in t.split(","):
        a, b = (int(x) for x in part.split("-")) if "-" in part else (int(part),) * 2
        if a > b: a, b = b, a
        if a < 1 or b > n: return None
        pages.update(range(a, b + 1))
    return sorted(pages)
rnd = random.Random(20261017)
def gen_valid():
    k = rnd.randint(1, 4); parts = []
    for _ in range(k):
        a = rnd.randint(1, npages); b = rnd.randint(1, npages)
        sp = lambda: " " * rnd.randint(0, 2)
        if rnd.random() < 0.5: parts.append("%d" % a)
        else: parts.append("%d%s%s%s%d" % (a, sp(), rnd.choice(["-", " to ", "to", " through ", "through", "--"][:5]), sp(), b))
    seps = [rnd.choice([",", " , ", " and ", "&", " & ", "and", ", "]) for _ in parts]
    s = parts[0]
    for sep, p in zip(seps, parts[1:]): s += sep + p
    return s
def spoil(s):
    r = rnd.random()
    if r < .2: return s + rnd.choice([",", "-", " and", " to", "x"])
    if r < .4: return rnd.choice([",", "-", "and "]) + s
    if r < .6: i = rnd.randrange(len(s) + 1); return s[:i] + rnd.choice(["x", ";", "0", "a", "1-", ",,", "to to"]) + s[i:]
    if r < .8: return s.replace(" ", "", 1) + "9999"
    return rnd.choice(["", " ", "0", "-3", "1-0", "1..3", "all", "one", "1,,2", "1 2 to", "%d" % (npages + 1), "1-%d" % (npages + 5)])
cases = []
for _ in range(150): cases.append(gen_valid())
for _ in range(120): cases.append(spoil(gen_valid()))
script = "".join("printdialog %s range=%s press=cancel\n" % (big, c.replace(" ", "~") if c.strip() else "~") for c in cases)
o, rc, err = run("open %s\n%s" % (multi, script), "fuzz", timeout=900)
d = lines_of(o, "PRINTDIALOG")
check("fuzz: one answer for each string", len(d) == len(cases), (len(d), len(cases)))
bad = 0; nvalid = 0
for c, line in zip(cases, d):
    after = line.split("| pressed")[1]
    err_txt = field(after, "err") if False else re.search(r"err=\[(.*?)\]( \||$)", line)
    got_err = err_txt.group(1) if err_txt else None
    got = [int(x) for x in (field(after, "list") or "").split(",") if x]
    want = oracle(c, npages)
    if want is None:
        ok = (got_err is not None and got_err != "" and got == [])
    else:
        nvalid += 1
        ok = got_err == "" and got == want
    if not ok:
        bad += 1
        if bad <= 8: print("  FAIL fuzz %r: want %s got %s err=%r" % (c, want, got, got_err))
check("fuzz: every string read as the second reader reads it (%d valid, %d refused)" % (nvalid, len(cases) - nvalid), bad == 0, bad)
check("fuzz: both valid and refused strings were tried", nvalid > 100 and len(cases) - nvalid > 40, nvalid)

# ---- 3. what is printed
dr = os.path.join(tmp, "o_range")
variants = [("all", "scale=100 sheets=all"), ("r13", "scale=100 sheets=all range=1,3"), ("r31", "scale=100 sheets=all range=3~and~1"), ("r12", "scale=100 sheets=all range=1~to~2"),
            ("r2", "scale=100 sheets=all range=2"), ("bad", "scale=100 sheets=all range=1,9"), ("copies", "scale=100 sheets=all range=1,3 copies=2 collate=0")]
script = "".join("open %s\nprintsink %s_%s\ngosheet 1\nprintdialog %s press=ok\n" % (multi, dr, t, o_) for t, o_ in variants)
o, rc, err = run(script, "printed")
d = lines_of(o, "PRINTDIALOG")
def first_green(img):
    ys, xs = np.nonzero((img[..., 1] > 200) & (img[..., 0] < 60)); return (int(xs.min()), int(ys.min())) if len(xs) else None
pos = {t: [first_green(im) for im in pages_of("%s_%s" % (dr, t))] for t, _ in variants}
allp = pos["all"]
check("print of all pages: three different sheets", len(allp) == 3 and len(set(allp)) == 3, allp)
check("range 1,3 prints pages 1 and 3 only", pos["r13"] == [allp[0], allp[2]], pos["r13"])
check("range '3 and 1' prints them in page order", pos["r31"] == [allp[0], allp[2]], pos["r31"])
check("range 1 to 2 prints pages 1 and 2", pos["r12"] == allp[:2], pos["r12"])
check("range 2 prints page 2 only", pos["r2"] == [allp[1]], pos["r2"])
check("range 1,9: nothing printed, the dialog stays open", pos["bad"] == [] and "stays open" in d[5], d[5][-200:])
check("range 1,3 with two copies, not collated: 1 1 3 3", pos["copies"] == [allp[0], allp[0], allp[2], allp[2]], pos["copies"])

# ---- 4. slider, buttons, label
def states(opts, moves):
    script = "open %s\n" % multi
    for mv in moves: script += "printdialog %s %s press=cancel\n" % (opts, mv)
    o, rc, err = run(script, "mv%d" % abs(hash(opts + "".join(moves)) % 100000))
    out = []
    for l in lines_of(o, "PRINTDIALOG"):
        a = l.split("| pressed")[1]
        out.append(dict(shown=num(a, "shown"), of=field(a, "pageof"), sl=re.search(r"slider=(\d+)\.\.(\d+)@(\d+) slideron=(\d)", a).groups(), back=num(a, "back"), fwd=num(a, "fwd"), lst=field(a, "list")))
    return out
S = states("scale=100 sheets=all", ["range=2~to~3", "range=2~to~3 fwd=1", "range=2~to~3 fwd=1 back=1", "range=2~to~3 slider=2", "range=2~to~3 fwd=1 fwd=1", "range=1,3 page=3",
                                    "range=1,3 page=2", "range=2", "range=7", "", "page=3 back=1", "slider=3 back=1 back=1 back=1"])
check("range 2-3: the preview starts on page 2, the slider has two positions", S[0]["shown"] == 2 and S[0]["sl"] == ("1", "2", "1", "1") and S[0]["of"] == "Page 2 of 3", S[0])
check("range 2-3: > goes to page 3, then < and > are dimmed as they should be", S[1]["shown"] == 3 and S[1]["sl"][2] == "2" and S[1]["back"] == 1 and S[1]["fwd"] == 0 and S[0]["back"] == 0 and S[0]["fwd"] == 1, (S[0], S[1]))
check("range 2-3: > then < is back on page 2", S[2]["shown"] == 2, S[2])
check("range 2-3: the slider at 2 shows page 3", S[3]["shown"] == 3 and S[3]["of"] == "Page 3 of 3", S[3])
check("> past the last page chosen stays on it", S[4]["shown"] == 3, S[4])
check("range 1,3: going to page 3 works; page 2 is not one chosen, so it shows the next one chosen (3)", S[5]["shown"] == 3 and S[6]["shown"] == 3, (S[5], S[6]))
check("one page chosen: slider and buttons dimmed, label names the page", S[7]["sl"][3] == "0" and S[7]["back"] == 0 and S[7]["fwd"] == 0 and S[7]["of"] == "Page 2 of 3", S[7])
check("a page that does not exist: no pages, label says so, slider dimmed", S[8]["of"] == "No pages" and S[8]["sl"][3] == "0" and S[8]["lst"] == "", S[8])
check("all pages: three positions, on page 1", S[9]["shown"] == 1 and S[9]["sl"] == ("1", "3", "1", "1") and S[9]["of"] == "Page 1 of 3", S[9])
check("all pages: page 3 then < goes to 2", S[10]["shown"] == 2, S[10])
check("all pages: slider to 3 then < < < stops at page 1", S[11]["shown"] == 1 and S[11]["back"] == 0, S[11])

# ---- 5. the preview compared with the printed page
def preview_of(opts, tag):
    f = os.path.join(tmp, "pv_%s.png" % tag)
    o, rc, err = run("open %s\nprintdialog %s preview=%s press=cancel\n" % (multi, opts, f), "pv_" + tag)
    return np.array(Image.open(f).convert("RGB")) if os.path.exists(f) else None
def page_area(img):
    bg = img[0, 0]
    diff = np.any(img != bg, axis=2); ys, xs = np.nonzero(diff)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    return img[y0 + 1:y1 - 2, x0 + 1:x1 - 2], (x0, y0, x1, y1)
def green(img): return (img[..., 1] > 150) & (img[..., 0] < 120) & (img[..., 2] < 120)
def iou(a, b): return (a & b).sum() / max(1, (a | b).sum())
printed = pages_of("%s_all" % dr)
for pg in (1, 2, 3):
    pv = preview_of("scale=100 sheets=all range=%d" % pg, "p%d" % pg)
    if pv is None: check("preview %d saved" % pg, False); continue
    area, box = page_area(pv)
    h, w = area.shape[:2]
    ref = np.array(Image.fromarray(printed[pg - 1]).resize((w, h), Image.BOX))
    ref_green = green(ref) | (np.array(Image.fromarray(green(printed[pg - 1]).astype(np.uint8) * 255).resize((w, h), Image.BOX)) > 60)
    mine = green(area)
    other = [pp for pp in (1, 2, 3) if pp != pg][0]
    ref2 = np.array(Image.fromarray(green(printed[other - 1]).astype(np.uint8) * 255).resize((w, h), Image.BOX)) > 60
    same, diffp = iou(mine, ref_green), iou(mine, ref2)
    check("preview of page %d matches the printed page 1:1 in shape and content (IoU %.2f against %.2f for another page)" % (pg, same, diffp), same > 0.6 and same > diffp + 0.3, (same, diffp))
    asp = w / h
    check("preview of page %d is in the shape of the A4 page" % pg, abs(asp - 297 / 210) < 0.03, (w, h))
    check("preview of page %d is inside the box with a frame and a margin" % pg, box[0] >= 1 and box[1] >= 1 and box[2] < pv.shape[1] - 1 and box[3] < pv.shape[0] - 1, box)
empty = preview_of("scale=100 sheets=all range=9", "none")
check("no pages: the preview is the plain background", empty is not None and (empty == empty[0, 0]).all(), None if empty is None else np.unique(empty.reshape(-1, 3), axis=0)[:4])
bw = preview_of("scale=100 sheets=all range=1 bw=1", "bw")
col = preview_of("scale=100 sheets=all range=1 bw=0", "col")
check("black and white: the preview has no green; in colour it has", bw is not None and col is not None and green(page_area(bw)[0]).sum() == 0 and green(page_area(col)[0]).sum() > 20, None)

# ---- 5b. choosing Pages with an empty box fills it; a box that was cleared by hand stays empty
o, rc, err = run("open %s\nprintdialog scale=300 sheets=all radio=range press=cancel\nprintdialog scale=300 sheets=all radio=all press=cancel\nprintdialog scale=300 sheets=all range=~ press=cancel\n" % multi, "fill")
d = [x.split("| pressed")[1] for x in lines_of(o, "PRINTDIALOG")]
check("choosing Pages with the box empty fills it with every page", len(d) == 3 and field(d[0], "box") == "1-%d" % npages, d[:1])
check("choosing All leaves the box empty", field(d[1], "box") == "" and "Pages: all" in d[1], d[1][:200])
check("a box cleared by hand stays empty and asks for pages", field(d[2], "box") == " " and "Type the pages to print" in d[2], d[2][-300:])

# ---- 6. printer drop down and Printer Setup
o, rc, err = run("open %s\nprintdialog press=cancel\nprintdialog printers=Alpha|Beta|Gamma press=cancel\nprintdialog printers=Alpha|Beta|Gamma printer=2 press=cancel\n"
                 "printdialog printers=Alpha|Beta setup=1 press=cancel\nprintdialog setup=1 press=cancel\n" % multi, "printers")
d = lines_of(o, "PRINTDIALOG")
A = [x.split("| pressed")[1] for x in d]
check("no printer installed: the drop down says so and is dimmed, Printer Setup too", "printers=[No printer is installed|]" in A[0] and num(A[0], "listenabled") == 0 and num(A[0], "setupenabled") == 0, A[0][-300:])
check("a list of printers fills the drop down, the first is chosen, both are usable", "printers=[Alpha|Beta|Gamma|]" in A[1] and num(A[1], "sel") == 0 and num(A[1], "listenabled") == 1 and num(A[1], "setupenabled") == 1 and num(A[1], "picked") == -1, A[1][-300:])
check("choosing the third printer reaches the main form", num(A[2], "sel") == 2 and num(A[2], "picked") == 2, A[2][-300:])
check("Printer Setup with no printer in the system says so", "No printer is installed" in field(A[3], "status") , A[3][-200:])
check("the old Printer... button is gone: the dialog starts with the Printer Setup button", "captions=" in d[0] and "Printer Setup..." in d[0].split("captions=")[1].split(" buttons=")[0] and "P&rinter..." not in d[0], d[0][:260])
print("Print range checks: %d, failed %d" % (checks, len(fails))); sys.exit(1 if fails else 0)
