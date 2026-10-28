"""An independent reading of a design's XML, shared by run_copyto.py and run_import.py. Objects are compared by what they mean:
numbers as numbers, and the references an object holds (its font, line style, fill and, for a symbol, its definition) replaced by what
they refer to in that file, because the program renumbers these when it loads a design and they are written back in its own numbering.
Only what the program is known to add (see ALLOWED_EXTRA and EXTRA_CHILD) and what the loader leaves out (see dropped) is allowed
to differ."""
import xml.etree.ElementTree as ET
HEADER = {"NAME", "DETAILS", "FONT", "STYLE", "FILL", "SYMBOLDEF", "OPTIONS", "METAFILE", "ORIGIN"}
# attributes the program writes that older files do not have: the object's id, a symbol's show_power, a polygon's polygon (worked
# out from its fill), a pin's centre_name (TinyCAD works it out when it is not there: a power pin has its name centred). Every one
# of them was found by listing every attribute of the copies that the originals lack.
ALLOWED_EXTRA = {"oid", "show_power", "polygon", "centre_name"}
CLASS_OF = {"SYMBOL": "TDrawMethod", "LABEL": "TDrawLabel", "TEXT": "TDrawText", "POWER": "TDrawPower", "JUNCTION": "TDrawJunction",
            "NOCONNECT": "TDrawNoConnect", "NOTE_TEXT": "TDrawNoteText", "POLYGON": "TDrawPolygon"}
REFS = {"BUS": {"style": "STYLE"}, "WIRE": {"style": "STYLE"}, "ELLIPSE": {"style": "STYLE", "fill": "FILL"}, "RECTANGLE": {"style": "STYLE", "fill": "FILL"},
        "POLYGON": {"style": "STYLE", "fill": "FILL"}, "LABEL": {"font": "FONT"}, "TEXT": {"font": "FONT"}, "BUSNAME": {"font": "FONT"},
        "NOTE_TEXT": {"font": "FONT", "style": "STYLE", "fill": "FILL", "border_style": "STYLE"}, "SYMBOL": {"id": "SYMBOLDEF"}}
EXTRA_CHILD = {"GUID", "REF_POINT"}            # elements the program writes that older files do not have
def tok(v):
    try: return round(float(v), 3)
    except ValueError: return v
def norm(v): return tuple(tok(x) for x in v.split(","))
def sig(e, maps):
    """what an element means: its tag, attributes, text and children, with numbers as numbers, the references (font, style, fill, the
    definition of a symbol) replaced by what they refer to in this file, and what the program adds left out"""
    attrs = []
    for k, v in e.attrib.items():
        if k in ALLOWED_EXTRA: continue
        if e.tag in ("FONT", "STYLE", "FILL", "SYMBOLDEF") and k == "id": continue
        ref = REFS.get(e.tag, {}).get(k)
        attrs.append((k, ("ref", maps.get(ref, {}).get(v)) if ref else norm(v)))
    if e.tag == "LABEL" and "style" not in e.attrib: attrs.append(("style", norm("0")))       # (a normal label: the style is written even when it is 0)
    text = norm((e.text or "").strip())
    if e.tag == "SHOWS": text = (float(int(float(text[0])) & 3),)        # (only bits 1 and 2 mean anything, and only those are written back, as TinyCAD does)
    # the objects inside a symbol definition are loaded by the same rule as those of the sheet: an empty text is not kept
    return (e.tag, tuple(sorted(attrs)), text, tuple(sig(c, maps) for c in e if c.tag not in EXTRA_CHILD and not (e.tag == "TinyCAD" and dropped(c))))
def resource_maps(sh):
    """id -> meaning, for the fonts, styles, fills and (once those are known) symbol definitions of a sheet"""
    maps = {r: {} for r in ("FONT", "STYLE", "FILL", "SYMBOLDEF")}
    for r in ("FONT", "STYLE", "FILL"):
        for e in sh.findall(r): maps[r][e.get("id")] = sig(e, maps)
    for e in sh.findall("SYMBOLDEF"): maps["SYMBOLDEF"][e.get("id")] = sig(e, maps)
    return maps
def sheet0(path):
    r = ET.parse(path).getroot()
    return r.findall("TinyCAD")[0] if r.tag == "TinyCADSheets" else r
def dropped(e):
    """objects that the loader does not keep, as TinyCAD's IsEmpty says: an empty text or note, a normal label with no text, a polygon of fewer than two points"""
    if e.tag in ("TEXT", "BUSNAME", "NOTE_TEXT"): return not (e.text or "")
    if e.tag == "LABEL": return (not (e.text or "")) and e.get("style", "0") == "0"
    if e.tag == "POLYGON": return len(e.findall("POINT")) <= 1
    return False
def objects(sh): return [e for e in sh if e.tag not in HEADER and not dropped(e)]
