"""An independent statement of TinyCAD's Generate Symbol References (Special.cpp OnSpecialAnnotate, DrawMethod.cpp AddReference / RemoveReference / SetRefVal / GetRefVal /
SetPart, DrawRefPainter.cpp) in Python. The placed symbols come from annotest dump (their boxes, parts, and where SetPart would move them); everything the command does
with them is restated here."""
import os, re, subprocess, random, copy, xml.etree.ElementTree as ET

BUILD = os.environ.get("TC_BUILD", "build")
AT = os.path.join(BUILD, "annotest")

def atoi(s):
    m = re.match(r"[ \t\n\v\f\r]*([+-]?)([0-9]*)", s)
    if not m or m.group(2) == "": return 0
    v = int(m.group(2)); v = -v if m.group(1) == "-" else v
    return max(-2**31, min(2**31 - 1, v))

def num(t): return float(t)

def parse(lines):
    ms = []
    for l in lines:
        if not l.startswith("M "): continue
        t = l.split(" ")
        st = [tuple(float(v) for v in p.split(",")) for p in t[13].rstrip(";").split(";")] if t[13] != "-" else []
        # a placed design (hierarchical symbol) ends with "H0" or "H1" (1: nothing to draw); it takes part like a symbol that has no parts to move
        hier = len(t) > 14 and t[14][:1] == "H"
        ms.append(dict(sheet=int(t[1]), idx=int(t[2]), sym=int(t[3]), ref=t[4].replace("_", " "), part=int(t[5]), A=[num(t[6]), num(t[7])], B=[num(t[8]), num(t[9])],
                       prefix=t[10].replace("_", " "), ppp=int(t[11]), het=t[12] == "1", statics=st, hier=hier, nosym=hier and t[14] == "H1"))
    return ms

def dump(dsn):
    r = subprocess.run([AT, "dump", dsn], capture_output=True, text=True)
    return parse(r.stdout.split("\n"))

def others(dsn):
    """the points of the objects that are not placed symbols: (sheet, x, y)"""
    r = subprocess.run([AT, "dump", dsn], capture_output=True, text=True)
    return [(int(l.split()[1]), float(l.split()[4]), float(l.split()[5])) for l in r.stdout.split("\n") if l.startswith("O ")]

def has_ref(m): return "?" not in m["ref"]
def ref_val(m):
    r = m["ref"]; k = re.search(r"[0-9]", r)
    return atoi(r[k.start():] if k else r)
def set_ref_val(m, v):
    buf = str(v)
    if len(buf) > 9: buf = ""
    p = m["prefix"]; k = p.rfind("?")
    m["ref"] = (p[:k] if k >= 0 else "") + buf
def set_part(m, p):
    if not m["statics"]:           # (a placed design: the first static point is the same for every part, so nothing moves)
        m["part"] = p; return
    # GetFirstStaticPoint makes the box the size of the part it is asked about, so after the move the far corner is the new part's box away
    old = m["statics"][m["part"]]; new = m["statics"][p]
    d = (old[0] - new[0], old[1] - new[1])
    m["A"][0] += d[0]; m["A"][1] += d[1]
    m["B"][0] = m["A"][0] + new[2]; m["B"][1] = m["A"][1] + new[3]
    m["part"] = p
def remove_ref(m):
    m["ref"] = m["prefix"]
    if not m["het"]: set_part(m, 0)
def add_ref(m, min_ref, scan):
    ours = m["prefix"]; ppp = m["ppp"]
    nxt = min_ref; last_ref = min_ref; last_ppp = -1; found = False
    alter = (not m["het"]) and ppp > 1
    for sheet in scan:
        our_sheet = sheet == m["sheet"]
        for o in MS:
            if o["sheet"] != sheet: continue
            if o is not m and has_ref(o) and o["prefix"] == ours:
                rn = ref_val(o); pn = o["part"]
                if nxt <= rn: nxt = rn + 1
                if o["sym"] == m["sym"] and our_sheet:
                    found = True
                    if last_ref < rn or (last_ref == rn and last_ppp < pn):
                        last_ref = rn; last_ppp = pn
    if alter and found:
        last_ppp += 1
        if last_ppp >= ppp:
            last_ppp = 0; last_ref = nxt
        set_part(m, last_ppp); set_ref_val(m, last_ref)
    else:
        set_ref_val(m, nxt)
        if alter: set_part(m, 0)

MS = []
def annotate(ms, add, which, value, match, start, all_sheets, active):
    """add: True add / False remove; which 0 all, 1 unnumbered, 2 matching; value 0 default 1 start. Returns (symbols after, missing)"""
    global MS
    MS = copy.deepcopy(ms); missing = False
    nsheets = max(m["sheet"] for m in MS) + 1 if MS else 1
    nsheets = max(nsheets, active + 1)
    for p in range(2):
        sheet = 0 if all_sheets else active
        while True:
            objs = sorted([m for m in MS if m["sheet"] == sheet], key=lambda m: ((m["A"][1] + m["B"][1]) / 2, (m["A"][0] + m["B"][0]) / 2))
            for m in objs:
                if (m["nosym"] if m.get("hier") else m["sym"] == 0): missing = True; continue
                is_set = has_ref(m)
                if which == 0: ok = True
                elif which == 1: ok = not has_ref(m)
                else: ok = match == m["prefix"]
                if not ok: continue
                if p == 0:
                    if is_set and (value != 1 or ref_val(m) >= start): remove_ref(m)
                elif add:
                    v = start if value == 1 else 1
                    add_ref(m, v, list(range(nsheets)) if all_sheets else [sheet])
            sheet += 1
            if not (all_sheets and sheet < nsheets): break
    return MS, missing

def paint(ms, sheet, start, clicks, hits):
    """clicks: list of (remove) with hits the list of indexes of the symbols under each click (the geometry of the hit test is not restated)"""
    global MS
    MS = copy.deepcopy(ms)
    for rem, hit in zip(clicks, hits):
        for idx in hit:
            m = next(x for x in MS if x["sheet"] == sheet and x["idx"] == idx)
            if rem: remove_ref(m)
            else: add_ref(m, start, [sheet])
    return MS

def variant(src, seed, dst, with_parts=True, exotic=False):
    """A changed copy of a design: references unnumbered, numbered (some twice), parts and parts per package changed"""
    rng = random.Random(seed)
    root = ET.parse(src).getroot()
    sheets = [root] if root.tag == "TinyCAD" else root.findall("TinyCAD")
    prefix = {d.get("id"): (d.findtext("REF") or "?") for sh in sheets for d in sh.findall("SYMBOLDEF")}
    for sh in sheets:
        for d in sh.findall("SYMBOLDEF"):
            if with_parts and rng.random() < 0.3:
                pp = d.find("PPP")
                if pp is not None: pp.text = str(rng.choice([2, 3, 4]))
    for sh in sheets:
        for s in sh.findall("SYMBOL"):
            f = s.findall("FIELD")[0]; pre = prefix.get(s.get("id"), "?")
            r = rng.random()
            if r < 0.3: f.set("value", pre)
            elif r < 0.5: f.set("value", (pre[:pre.rfind("?")] if "?" in pre else pre) + str(rng.randint(1, 12)))
            elif r < 0.6: f.set("value", pre.replace("?", "") + str(rng.choice([0, 7, 99, 120])) + rng.choice(["", "A"]))
            elif exotic and r < 0.7: f.set("value", rng.choice(["U99999999999", "U0A5", "U0 5", "U-5", "U 5", "5U", "U1U2", "U00", "U007", "U999999999", "U?5", "U5?", "-3", "U+4", "R 12", "0", "U0A"]))
            if with_parts and rng.random() < 0.3: s.set("part", str(rng.randint(0, 3)))
    ET.ElementTree(root).write(dst, encoding="UTF-8", xml_declaration=True)
