"""TinyCAD's BOMGenerator restated in Python (a separate reading of the design's XML and a separate statement of the rules), shared by run_partslist.py and
run_partsdialog.py."""
import xml.etree.ElementTree as ET
PAD = 25
def esc(s, d): return s if d not in s else '"' + s + '"'

def read_design(path):
    """[(sheet index, placed symbols)], where a symbol is (ref text, name, default ref, description, fields)"""
    root = ET.parse(path).getroot()
    sheets = [root] if root.tag == "TinyCAD" else root.findall("TinyCAD")
    defs = {}
    for sh in sheets:
        for d in sh.findall("SYMBOLDEF"):
            i = d.get("id")
            if i not in defs:
                defs[i] = dict(ref=(d.findtext("REF") or ""), desc=(d.findtext("DESCRIPTION") or ""), ppp=int((d.findtext("PPP") or "1").strip() or 1))
    out = []
    for n, sh in enumerate(sheets):
        syms = []
        for s in sh.findall("SYMBOL"):
            df = defs[s.get("id")]
            fl = [(int(f.get("type", "0")), f.get("description", ""), f.get("value", "")) for f in s.findall("FIELD")]
            ref = fl[0][2]                       # GetRef(): the field itself, no part letter (so U2A and U2B are one entry, U2)
            syms.append((ref, fl[1][2], df["ref"], df["desc"], fl))
        out.append(syms)
    return out

def build(sheets, allsheets, allattrs, active, ftype):
    delim = ";" if ftype == 2 else ","
    heads = ["Description", "Package"]
    chosen = range(len(sheets)) if allsheets else [active]
    items = {}
    for si in chosen:
        for ref, name, dref, desc, fl in sheets[si]:
            text = esc(name, delim)
            if allattrs:
                cols = [desc]
                for t, dn, val in fl[2:]:
                    if t == 2: continue
                    j = next((k for k, h in enumerate(heads) if h.lower() == dn.lower()), len(heads))
                    if j == len(heads): heads.append(dn)
                    while len(cols) <= j: cols.append("")
                    cols[j] = val
                for c in cols: text += delim + esc(c, delim)
            key = (text, ref)
            if key not in items: items[key] = dref
    return heads, sorted(items.items())

def write(heads, entries, ftype, heading):
    out = []; missing = False
    if ftype == 2:
        out.append("Reference;Quantity;Name" + "".join(";" + esc(h, ";") for h in heads) + "\n")
        lastref = lastname = ""; pieces = 0
        for (name, ref), dref in entries:
            if name != lastname and lastname != "":
                out.append(";%d;%s\n" % (pieces, lastname)); pieces = 0
            if ref != lastref:
                if pieces > 0: out.append(",")
                out.append(ref); pieces += 1
            if ref == dref: missing = True
            lastref, lastname = ref, name
        if pieces > 0: out.append(";%d;%s\n" % (pieces, lastname))
        return "".join(out), missing
    csv = ftype == 1
    if csv: out.append("Reference,Quantity,Name" + "".join("," + h for h in heads) + "\n")
    else: out.append("====+  Parts List for %s  +====\n\n" % heading)
    lastref = lastname = ""; xpos = 0; pieces = 0
    def endline(name):
        nonlocal xpos
        if csv: out.append('",%3d,%s\n' % (pieces, name))
        else:
            out.append(" " * max(0, PAD - xpos)); xpos = max(xpos, PAD)
            out.append("   %3d   %s\n" % (pieces, name)); xpos = 0
    def xinc(n):
        nonlocal xpos
        xpos += n
        if xpos >= PAD: out.append("\n"); xpos = n
    for (name, ref), dref in entries:
        if name != lastname and lastname != "":
            endline(lastname); pieces = 0
        if ref != lastref:
            if csv: out.append('"' if pieces == 0 else ",")
            else:
                if xpos != PAD - 1 and xpos != 0:
                    xinc(1); out.append(",")
                xinc(len(ref))
            out.append(ref); pieces += 1
        if ref == dref: missing = True
        lastref, lastname = ref, name
    if pieces > 0: endline(lastname)
    return "".join(out), missing

