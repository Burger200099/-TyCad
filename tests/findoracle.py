"""An independent reading of what Find and Replace should do, used by run_find.py and run_gui.py. It takes the texts
that TinyCAD's Find searches (LABEL, TEXT, NOTE_TEXT and POWER text, and the value of every FIELD of a SYMBOL) straight
from a design's XML, in file order, and finds the occurrences itself, byte by byte: ASCII case folding, a whole word has
no letter, digit, underscore or non-ASCII byte next to it, occurrences do not overlap."""
import xml.etree.ElementTree as ET
CLASS_OF = {"LABEL": "TDrawLabel", "TEXT": "TDrawText", "BUSNAME": "TDrawText", "NOTE_TEXT": "TDrawNoteText", "POWER": "TDrawPower", "SYMBOL": "TDrawMethod"}
NAME_OF = {"LABEL": "Label", "TEXT": "Text", "BUSNAME": "BusName", "NOTE_TEXT": "NoteText", "POWER": "Power"}   # (what TinyCAD calls them in its list)
def _sheets(path):
    root = ET.parse(path).getroot()
    return root.findall("TinyCAD") if root.tag == "TinyCADSheets" else [root]
def texts(path):
    """[(sheet, slot, text as bytes)] in file order"""
    out = []
    for si, sh in enumerate(_sheets(path)):
        for e in sh:
            if e.tag in ("LABEL", "TEXT", "BUSNAME", "NOTE_TEXT", "POWER"): out.append((si, 0, (e.text or "").encode("utf-8")))
            elif e.tag == "SYMBOL":
                for k, f in enumerate(e.findall("FIELD")): out.append((si, k, (f.get("value") or "").encode("utf-8")))
    return out
def classes(path):
    """the class of the object that holds each text of texts(), in the same order"""
    out = []
    for sh in _sheets(path):
        for e in sh:
            if e.tag in ("LABEL", "TEXT", "BUSNAME", "NOTE_TEXT", "POWER"): out.append(CLASS_OF[e.tag])
            elif e.tag == "SYMBOL": out.extend([CLASS_OF["SYMBOL"]] * len(e.findall("FIELD")))
    return out
def lower(b): return bytes(c + 32 if 65 <= c <= 90 else c for c in b)
def isword(c): return (48 <= c <= 57) or (65 <= c <= 90) or (97 <= c <= 122) or c == 95 or c > 127
def occurrences(t, needle, case, word):
    h, n = (t, needle) if case else (lower(t), lower(needle)); out = []; p = 0
    while n and p <= len(h) - len(n):
        if h[p:p + len(n)] == n and not (word and ((p > 0 and isword(h[p - 1])) or (p + len(n) < len(h) and isword(h[p + len(n)])))):
            out.append(p + 1); p += len(n)       # (1-based, and the next one starts after this one)
        else: p += 1
    return out
def expected_hits(tx, needle, case, word):
    """[(sheet, slot, offset, len, text)] for every occurrence, in the order of the design"""
    return [(s, k, o, len(needle), t) for (s, k, t) in tx for o in occurrences(t, needle, case, word)]
def simulate(exp, direction, steps, start_sheet=0):
    """what Find Next / Previous visits, step by step from a fresh start in sheet start_sheet: (index of the occurrence, wrapped)"""
    n = len(exp); res = []
    if direction == "down":
        cand = [i for i in range(n) if exp[i][0] >= start_sheet]
        idx, w = (cand[0], False) if cand else (0, True)
    else:
        cand = [i for i in range(n) if exp[i][0] <= start_sheet]
        idx, w = (cand[-1], False) if cand else (n - 1, True)
    res.append((idx, w))
    for _ in range(steps - 1):
        if direction == "down": idx, w = (idx + 1, False) if idx + 1 < n else (0, True)
        else: idx, w = (idx - 1, False) if idx - 1 >= 0 else (n - 1, True)
        res.append((idx, w))
    return res
def replace_in(tx, needle, repl, case, word, only_first=None):
    """the texts after replacing: every occurrence, or only the first `only_first` occurrences in design order"""
    out = []; done = 0
    for (s, k, t) in tx:
        res = b""; last = 0
        for o in occurrences(t, needle, case, word):
            if only_first is not None and done >= only_first: break
            res += t[last:o - 1] + repl; last = o - 1 + len(needle); done += 1
        out.append((s, k, res + t[last:]))
    return out

def _point(e):
    """where an object is (design units: the file's units times 5): its pos, or for a note its first corner a"""
    v = e.get("pos") or e.get("a") or "0,0"
    x, y = (float(c) for c in v.split(","))
    return (x * 5, y * 5)
def object_hits(path, needle):
    """TinyCAD's own Find: [(sheet, slot, name, text, (x, y))] for each object that has the text in any of its texts (not
    case sensitive), once, with the first of its texts that has it"""
    out = []
    for si, sh in enumerate(_sheets(path)):
        for e in sh:
            if e.tag in NAME_OF: slots = [(0, (e.text or "").encode("utf-8"))]; name = NAME_OF[e.tag]
            elif e.tag == "SYMBOL":
                fields = e.findall("FIELD"); slots = [(k, (f.get("value") or "").encode("utf-8")) for k, f in enumerate(fields)]
                name = (fields[1].get("value") or "") if len(fields) > 1 else ""      # a symbol is called by its Name field
            else: continue
            for k, t in slots:
                if occurrences(t, needle, False, False):
                    out.append((si, k, name, t, _point(e))); break
    return out
