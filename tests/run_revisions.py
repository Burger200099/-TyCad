"""The ordering of revisions for the extended title block, and the sheet details that belong to it, on the core only. Written from the rules (see the top of
URevisions.pas), not from the code, and compared with the program over many generated cases:
  - how a date is read, from the forms people type (year first, day or month first, with the month as a word, two or four figure years), and what is no date
  - how revision labels are compared (numbers by value, letters by length then alphabetically, Z before AA, a number before a letter, 1 before 1.1)
  - which five are chosen and in what order, by date or by revision, with ties kept in list order and a sheet that has only the old Revision field showing that
  - the file: the new elements are written only when used, TinyCAD's REVISION element carries the newest revision, ordinary files come out unchanged,
    and everything TinyCAD reads from the details is the same as before (what TinyCAD does not know is only ever added, as elements it skips)
Needs the built test driver."""
import itertools, os, random, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
BUILD = os.environ.get("TC_BUILD", "build"); EXE = os.path.join(BUILD, "revtest")
EX = os.environ.get("TC_EXAMPLES", "examples")
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:300])
def run(*a):
    r = subprocess.run([EXE, *a], capture_output=True, text=True)
    if r.returncode != 0: raise SystemExit("revtest failed: " + " ".join(a) + "\n" + r.stdout[-300:] + r.stderr[-300:])
    return r.stdout.split("\n")
# ---------- the rules, written out ----------
MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
def valid(y, m, d):
    if not (y >= 1 and 1 <= m <= 12 and d >= 1): return False
    dim = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
    if d > dim: return False
    if m == 2 and d == 29: return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
    return True
def fullyear(v, digits): return v if digits > 2 else (2000 + v if v < 70 else 1900 + v)
def date_key(s):
    t = s.strip()
    if not t: return -1
    if len(t) == 8 and t.isdigit():
        y, m, d = int(t[:4]), int(t[4:6]), int(t[6:])
        return y * 10000 + m * 100 + d if valid(y, m, d) else -1
    parts = re.findall(r"\d+|[A-Za-z]+", t)
    if re.search(r"[^0-9A-Za-z \-/.,]", t): return -1
    # a number run directly next to a letter run counts as separate pieces, as splitting does
    if len(parts) != 3: return -1
    isn = [p.isdigit() for p in parts]
    if all(isn):
        if len(parts[0]) == 4: y, m, d = int(parts[0]), int(parts[1]), int(parts[2])
        elif len(parts[0]) <= 2 and len(parts[1]) <= 2 and len(parts[2]) in (2, 4):
            a, b = int(parts[0]), int(parts[1]); y = fullyear(int(parts[2]), len(parts[2]))
            if a > 12: d, m = a, b
            elif b > 12: m, d = a, b
            else: d, m = a, b
        else: return -1
        return y * 10000 + m * 100 + d if valid(y, m, d) else -1
    def mon(w):
        u = w.upper()
        return next((i + 1 for i, mm in enumerate(MONTHS) if len(u) >= 3 and u[:3] == mm), 0)
    if isn == [True, False, True]: d, m, yy = int(parts[0]), mon(parts[1]), parts[2]
    elif isn == [False, True, True]: m, d, yy = mon(parts[0]), int(parts[1]), parts[2]
    else: return -1
    if m and len(yy) in (2, 4):
        y = fullyear(int(yy), len(yy))
        if valid(y, m, d): return y * 10000 + m * 100 + d
    return -1
def chunks(s):
    out = []
    for m in re.finditer(r"\d+|[A-Za-z]+|.", s):
        t = m.group()
        out.append((0, int(t), "") if t.isdigit() else ((1, len(t), t.upper()) if t[0].isalpha() and t.isascii() else (2, ord(t[0]), t)))
    return out
def cmp_labels(a, b):
    ca, cb = chunks(a), chunks(b)
    for x, y in zip(ca, cb):
        if x != y:
            return -1 if x < y else 1
    return (len(ca) > len(cb)) - (len(ca) < len(cb))
def newest(revs, legacy_rev, legacy_date, by_rev, count):
    items = list(revs)
    if not items and legacy_rev: items = [(legacy_rev, legacy_date, "")]
    idx = list(range(len(items)))
    import functools
    def order(i, j):          # negative: i is newer than j
        a, b = items[i], items[j]
        c = cmp_labels(a[0], b[0]) if by_rev else date_key(a[1]) - date_key(b[1])
        if c == 0: c = i - j
        return -1 if c > 0 else 1
    idx.sort(key=functools.cmp_to_key(order))
    return [items[i] for i in idx[:count]]
rnd = random.Random(2024)
def make_date(rnd):
    y, m, d = rnd.randint(1995, 2035), rnd.randint(1, 12), rnd.randint(1, 31)
    name = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"][m - 1]
    f = rnd.randrange(14)
    sep = rnd.choice(["-", "/", "."])
    return [f"{y}-{m:02d}-{d:02d}", f"{y}/{m}/{d}", f"{y}.{m:02d}.{d:02d}", f"{y}{m:02d}{d:02d}", f"{d}{sep}{m}{sep}{y}", f"{d:02d}{sep}{m:02d}{sep}{y % 100:02d}",
            f"{d} {name[:3]} {y}", f"{d} {name} {y}", f"{name[:3]} {d} {y}", f"{name} {d}, {y}", f"{d}-{name[:3]}-{y % 100:02d}", f"{m}/{d}/{y}", f" {y}-{m}-{d} ", f"{d}.{m}.{y}"][f]
dates = [make_date(rnd) for _ in range(2500)] + ["", " ", "n/a", "tbd", "2024-13-01", "2023-02-29", "2024-02-29", "31/04/2024", "1900-01-01", "12:30", "2024-03-09 10:00", "Mar 2024", "9 Foo 2024", "9/3", "9/3/224", "0/0/00", "00-00-0000", "1/1/69", "1/1/70", "13/12/2020", "12/13/2020", "5/6/2020", "Sept 4 2021", "4 SEPT 2021", "4 Sep 21"]
open(f"{tmp}/dates.txt", "w").write("\n".join(dates) + "\n")
got = run("date", f"{tmp}/dates.txt")[:len(dates)]
bad = [(d, g, date_key(d)) for d, g in zip(dates, got) if int(g) != date_key(d)]
check(f"{len(dates)} dates (every form, and text that is no date): read as the rules say", not bad, str(bad[:4]))
check("some of them really are dates and some really are not (so the check can fail)", sum(date_key(d) > 0 for d in dates) > 2000 and sum(date_key(d) < 0 for d in dates) > 15, "")
def make_label(rnd):
    return rnd.choice(["A", "B", "Z", "AA", "AB", "a", "b", "1", "2", "9", "10", "11", "1.0", "1.2", "1.10", "2.1", "01", "1a", "1b", "A1", "A10", "A2", "B1", "REV1", "Rev 2", "R-3", "V1.2.3", "V1.2.10", "X", "", "0", "00", "1.", "A.", "-"])
pairs = [(make_label(rnd), make_label(rnd)) for _ in range(4000)] + [("Z", "AA"), ("AA", "Z"), ("1.2", "1.10"), ("1", "1.1"), ("1", "A"), ("A", "1"), ("a", "A"), ("B", "b"), ("2", "10"), ("02", "2")]
open(f"{tmp}/pairs.txt", "w").write("\n".join(a + "\t" + b for a, b in pairs) + "\n")
got = run("cmp", f"{tmp}/pairs.txt")[:len(pairs)]
bad = [(a, b, g, cmp_labels(a, b)) for (a, b), g in zip(pairs, got) if int(g) != cmp_labels(a, b)]
check(f"{len(pairs)} pairs of revision labels compare as the rules say (1.2 < 1.10, Z < AA, 1 < 1.1, a number before a letter)", not bad, str(bad[:4]))
check("and the usual cases come out as a person expects", all(cmp_labels(a, b) == w for a, b, w in (("A", "B", -1), ("Z", "AA", -1), ("1.2", "1.10", -1), ("1", "1.1", -1), ("2", "10", -1), ("A", "a", 0), ("1", "A", -1), ("B", "A", 1))), "")
# ---------- which five, and in what order ----------
lines = []; cases = []
for k in range(1500):
    n = rnd.choice([0, 0, 1, 2, 3, 5, 6, 7, 9, 12]); by_rev = rnd.random() < 0.5; count = rnd.choice([5, 5, 5, 3, 1, 8])
    revs = []
    for _ in range(n):
        base = make_date(rnd) if rnd.random() < 0.85 else rnd.choice(["", "n/a", "tbd"])
        revs.append((make_label(rnd) or "?", base, rnd.choice(["JB", "AK", "MP", ""])))
    if rnd.random() < 0.3 and n > 2:       # duplicates, so the tie rule matters
        revs[rnd.randrange(n)] = revs[rnd.randrange(n)]
    lrev = rnd.choice(["", "", "C", "1.4"]); ldate = rnd.choice(["", "2020-01-01"])
    lines.append(f"{'rev' if by_rev else 'date'} {count} {lrev.replace(' ', '~')} {ldate.replace(' ', '~')}")
    lines += [f"{a}\t{b}\t{c}" for a, b, c in revs]; lines.append("")
    cases.append((revs, lrev, ldate, by_rev, count))
open(f"{tmp}/newest.txt", "w").write("\n".join(lines) + "\n")
out = run("newest", f"{tmp}/newest.txt"); bad = 0; first = None; k = -1; rows = []
groups = []
for l in out:
    if l.startswith("GROUP"): groups.append([]); 
    elif l.startswith("ROW "): groups[-1].append(tuple(l[4:].split("\t")))
for (revs, lrev, ldate, by_rev, count), g in zip(cases, groups):
    want = newest(revs, lrev, ldate, by_rev, count)
    if [tuple(x) for x in g] != [tuple(w) for w in want]: bad += 1; first = first or (revs, lrev, ldate, by_rev, count, g, want)
check(f"{len(cases)} sets of revisions: the newest (at most 3, 5 or 8, or only 1), newest first, by date or by revision, ties in list order, the old Revision field when there is no history",
      bad == 0 and len(groups) == len(cases), f"{bad} wrong; first {first}")
check("and in the cases that were generated the choice differs between date and revision often enough to mean something", sum(1 for c in cases if len(c[0]) > 5) > 200, "")
# ---------- the file ----------
sample = next(p for p in sorted(os.path.join(dp, f) for dp, _, fs in os.walk(EX) for f in fs if f.endswith(".dsn")) if os.path.basename(p) == "PSU.dsn")
def det(path):
    r = ET.parse(path).getroot(); sh = r.findall("TinyCAD")[0] if r.tag == "TinyCADSheets" else r
    return sh.find("DETAILS")
KNOWN = {"Size", "GUIDES", "TITLE", "AUTHOR", "REVISION", "DOCNUMBER", "ORGANISATION", "SHEETS", "SHOWS", "DATE", "GRID"}
out1 = f"{tmp}/plain_out.dsn"; run("resave", sample, out1)
d0, d1 = det(sample), det(out1)
check("an ordinary file comes out with none of the new elements (EXTBLOCK, NOTES, REFERENCE)", not any(e.tag in ("EXTBLOCK", "NOTES", "REFERENCE") for e in d1), str([e.tag for e in d1]))
check("and TinyCAD's own elements of the details are as they were (everything TinyCAD reads is unchanged)", all((e.text or "").strip() == (d1.find(e.tag).text or "").strip() for e in d0 if e.tag in KNOWN and e.tag not in ("GRID", "Size", "GUIDES")), "")
raw = open(sample, encoding="utf-8", errors="replace").read()
i = raw.index("</DETAILS>")
mod = raw[:i] + '<EXTBLOCK sort="rev" />\r\n<NOTES>First line\nSecond line</NOTES>\r\n<REFERENCE>PSU-7</REFERENCE>\r\n' + raw[i:]
mp = f"{tmp}/ext.dsn"; open(mp, "w", encoding="utf-8").write(mod)
dump = run("dump", mp)
check("the new elements are read: the switch, the order, the notes (with their line break) and the reference", dump[0] == "EXT 1 sort=1" and dump[1] == "NOTES First line\\nSecond line" and dump[2] == "REFERENCE PSU-7", str(dump[:3]))
mo = f"{tmp}/ext_out.dsn"; run("resave", mp, mo); d2 = det(mo)
ext = d2.find("EXTBLOCK")
check("and written back: EXTBLOCK with its sort, NOTES and REFERENCE, once each, and nowhere but in the details",
      ext is not None and ext.get("sort") == "rev" and [e.tag for e in d2].count("NOTES") == 1 and [e.tag for e in d2].count("REFERENCE") == 1 and (d2.find("NOTES").text or "") .replace("\r", "") == "First line\nSecond line", str([e.tag for e in d2]))
names = {e.tag for e in d2}
check("the details hold nothing that is not TinyCAD's, ours already (AUTOSHEETS, BORDER, REVISIONS) or the three new ones, so TinyCAD finds all it reads and skips the rest",
      names <= KNOWN | {"AUTOSHEETS", "BORDER", "REVISIONS", "EXTBLOCK", "NOTES", "REFERENCE"}, str(names))
# the REVISION element carries the newest revision by the sheet's own ordering (what TinyCAD reads), once there is a history
def with_hist(extra, revs):
    body = "".join(f'<REV label="{l}" date="{d}" author="JB" approved="">n</REV>' for l, d in revs)
    return raw[:i] + extra + f"<REVISIONS>{body}</REVISIONS>\r\n" + raw[i:]
def resaved(text, name):
    src = f"{tmp}/{name}.dsn"; out = f"{tmp}/{name}_out.dsn"; open(src, "w", encoding="utf-8").write(text); dmp = run("dump", src); run("resave", src, out)
    return dmp, det(out)
revs = [("A", "2022-01-01"), ("C", "2020-05-05"), ("B", "2021-06-01")]
dmp, d = resaved(with_hist("", revs), "byDate")
check("by date (the default) the newest of A (2022), C (2020) and B (2021) is A: that is the Revision shown, written to TinyCAD's REVISION element, and given for the date",
      "effective=A date=2022-01-01" in dmp[3] and (d.find("REVISION").text or "").strip() == "A" and d.find("EXTBLOCK") is None, f"{dmp[3]} {d.find('REVISION').text}")
dmp, d = resaved(with_hist('<EXTBLOCK sort="rev" show="0" />\r\n', revs), "byRev")
check("by revision it is C, whatever the dates say; and with the extended block not shown the order is still kept in the file (EXTBLOCK sort=rev show=0)",
      dmp[0] == "EXT 0 sort=1" and "effective=C date=2020-05-05" in dmp[3] and (d.find("REVISION").text or "").strip() == "C" and d.find("EXTBLOCK").get("sort") == "rev" and d.find("EXTBLOCK").get("show") == "0", f"{dmp[:4]} {d.find('EXTBLOCK').attrib if d.find('EXTBLOCK') is not None else None}")
dmp, d = resaved(with_hist('<EXTBLOCK sort="date" show="1" />\r\n', revs), "shown")
check("with the block shown the file says so (show=1), and the choice of date order survives", dmp[0] == "EXT 1 sort=0" and d.find("EXTBLOCK").get("show") == "1" and d.find("EXTBLOCK").get("sort") == "date", f"{dmp[0]}")
dmp, d = resaved(with_hist("", [("A", ""), ("B", ""), ("C", "")]), "nodates")
check("revisions with no dates at all: the last in the list is the newest, as before", "effective=C" in dmp[3], dmp[3])
# a file that has only the old single Revision keeps it (and its date) as the newest
legacy = raw.replace("<REVISION>", "<REVISION>").replace("</REVISION>", "</REVISION>")
dmp = run("dump", sample)
orig_rev = (det(sample).find("REVISION").text or "").strip(); orig_date = (det(sample).find("DATE").text or "").strip()
check("a file with no history keeps its single Revision and its date as what is shown", f"effective={orig_rev} date={orig_date}" in dmp[3], f"{dmp[3]} vs {orig_rev!r} {orig_date!r}")
print(f"revisions: {checks} checks, {len(fails)} failures")
print("\nREVISION CHECKS PASSED" if not fails else f"\nREVISION CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
