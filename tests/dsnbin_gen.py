"""Writes TinyCAD's old binary .dsn format, for the reader's tests.

It follows what an MFC CArchive does and what the C++ classes' Load functions read (written here from the C++ source's
field order, not from the Pascal reader): little endian, no padding; a CString is a length byte (0xFF + word, or 0xFF 0xFFFF +
dword, for long ones) then the characters, or 0xFF then the WORD 0xFFFE (bytes FE FF) first for UTF-16; a CPoint is two LONGs; LOGFONTA, LineStyle and
FillStyle are raw structures.  Every function returns bytes; join them in a list and wrap with design()."""
import struct

# ObjType values (DrawingObject.h)
X = dict(EndFile=0, DesignInformation=3, Font=7, LineStyle=10, FillStyle=11, LayerTable=13, BusName=15, NoConnect=16, Junction=17,
         Label=18, Wire=19, Bus=20, Method=21, Power=22, Pin=23, BusSlash=24, LabelEx=25, MethodEx=26, MethodEx2=27, PinEx=28, Origin=29,
         Line=32, Dash=33, Text=34, Circle=35, Square=36, Arc=37, LineEx=38, TextEx=39, CircleEx=40, SquareEx=41, ArcEx=42,
         LineEx2=43, CircleEx2=44, SquareEx2=45, ArcEx2=46, MetaFile=47, Tag=48, Ruler=49, MethodEx3=50, Polygon=51, NoteText=64,
         DesignInformation2=129, MetaFiles=130, Options=131, Symbols=132, CircleEx3=135, SquareEx3=136, TextEx2=137, LabelEx2=138,
         BusNameEx=139)

def u8(v): return struct.pack("<B", v & 0xFF)
def u16(v): return struct.pack("<H", v & 0xFFFF)
def i16(v): return struct.pack("<h", v)
def i32(v): return struct.pack("<i", v)
def u32(v): return struct.pack("<I", v & 0xFFFFFFFF)
def f64(v): return struct.pack("<d", v)
def pt(x, y): return i32(x) + i32(y)

def _len(n, wide):
    out = b"\xff\xfe\xff" if wide else b""
    if n < 255: return out + u8(n)
    if n < 0xFFFE: return out + b"\xff" + u16(n)
    return out + b"\xff\xff\xff" + u32(n)

def s(text, wide=False):
    """a CString; wide=True writes the UTF-16 form a UNICODE build of MFC writes"""
    if wide:
        raw = text.encode("utf-16-le")
        return _len(len(raw) // 2, True) + raw
    raw = text.encode("cp1252")
    return _len(len(raw), False) + raw

def stamp(rev=6, name="TinyCAD", magic=0x0C5A): return s(name) + u8(rev) + i16(magic)

def design(*parts, end=True, **kw):
    return stamp(**kw) + b"".join(parts) + (u8(X["EndFile"]) if end else b"")

# ---- title block, grid, options
def details_old(cx, cy, title, author, rev, docno, org, sheets, visible, t):
    return u8(X["DesignInformation"]) + i32(cx) + i32(cy) + s(title) + s(author) + s(rev) + s(docno) + s(org) + s(sheets) + u8(visible) + i32(t)
def details_ex(cx, cy, title, author, rev, docno, org, sheets, shows, date, grid=None, snap=1, wide=False):
    out = u8(X["DesignInformation2"]) + i32(cx) + i32(cy) + s(title, wide) + s(author, wide) + s(rev, wide) + s(docno, wide) + s(org, wide) + s(sheets, wide) + u8(shows) + s(date, wide)
    return out + (i32(grid if grid is not None else 50) + i32(snap))
def options(font=0, style=0, grid_show=0, units=0, scroll=0): return u8(X["Options"]) + i16(font) + i16(style) + i32(grid_show) + i32(units) + i32(scroll)

# ---- resource tables
def font(face="Arial", height=-10, width=0, weight=400, italic=0, underline=0, strike=0, charset=0):
    f = face.encode("cp1252")[:31].ljust(32, b"\0")
    return i32(height) + i32(width) + i32(0) + i32(0) + i32(weight) + u8(italic) + u8(underline) + u8(strike) + u8(charset) + u8(3) + u8(2) + u8(1) + u8(34) + f
def fonts(items): return u8(X["Font"]) + u16(len(items)) + b"".join(i16(i) + f for i, f in items)
def style(st=0, thick=1, color=0): return i32(st) + i32(thick) + u32(color)
def styles(items): return u8(X["LineStyle"]) + u16(len(items)) + b"".join(i16(i) + f for i, f in items)
def fill(index=-1, color=0): return i32(index) + u32(color)
def fills(items): return u8(X["FillStyle"]) + u16(len(items)) + b"".join(i16(i) + f for i, f in items)
def metafiles(items): return u8(X["MetaFiles"]) + u16(len(items)) + b"".join(i16(i) + u32(len(d)) + d for i, d in items)
def layer_table(items): return u8(X["LayerTable"]) + u16(len(items)) + b"".join(i16(i) + s(n) for i, n in items)

# ---- symbols (CDesignFileSymbol::Save order: name, description, reference, ppp, field-count string, fields, drawing)
def symbol_def(name, desc, ref, ppp, fields, objs, name_type=0, ref_type=0):
    cnt = str(len(fields) | (((name_type << 3) | ref_type) << 16))
    out = s(name) + s(desc) + s(ref) + u8(ppp) + s(cnt)
    for fn, fv, fd, fp, ft in fields: out += s(fn) + s(fv) + s(fd) + pt(*fp) + u32(ft)
    return out + design(*objs)
def symbols(items): return u8(X["Symbols"]) + u16(len(items)) + b"".join(i16(i) + d for i, d in items)

# ---- objects
def wire(a, b): return u8(X["Wire"]) + pt(*a) + pt(*b)
def bus(a, b): return u8(X["Bus"]) + pt(*a) + pt(*b)
def junction(p): return u8(X["Junction"]) + pt(*p)
def noconnect(p): return u8(X["NoConnect"]) + pt(*p)
def busslash(p, d): return u8(X["BusSlash"]) + pt(*p) + u8(d)
def power(p, which, d, text): return u8(X["Power"]) + pt(*p) + u8(which) + u8(d) + s(text)
def ruler(p, horiz): return u8(X["Ruler"]) + pt(*p) + i32(horiz)
def tag(p, name): return u8(X["Tag"]) + pt(*p) + s(name)
def label(kind, p, d, text, fnt=None, color=None):
    out = u8(X[kind]) + pt(*p) + u8(d) + s(text)
    if kind in ("LabelEx", "LabelEx2"): out += i16(fnt)
    if kind == "LabelEx2": out += u32(color)
    return out
def text(kind, p, d, txt, fnt=None, color=None):
    out = u8(X[kind]) + pt(*p) + u8(d) + s(txt)
    if kind in ("TextEx", "BusName", "TextEx2", "BusNameEx"): out += i16(fnt)
    if kind in ("TextEx2", "BusNameEx"): out += u32(color)
    return out
def pin_old(p, which, elec, d, part, name, number, show): return u8(X["Pin"]) + pt(*p) + u8(which) + u8(elec) + u8(d) + u8(part) + s(name) + s(number) + u8(show)
def pin(p, which, elec, d, part, name, number, show, length): return u8(X["PinEx"]) + pt(*p) + u8(which) + u8(elec) + u8(d) + u8(part) + s(name) + s(number) + u8(show) + u16(length)
def line2(kind, a, b, extra=b""): return u8(X[kind]) + pt(*a) + pt(*b) + extra
def polygon(ver, first, handles, st, fl):
    out = u8(X["Polygon"]) + u32(ver) + u32(len(handles)) + pt(*first)
    for h in handles:
        out += pt(h[0], h[1]) if ver == 0 else pt(h[0], h[1]) + i32(h[2])
    return out + u16(st) + u16(fl)
def square_old(kind, a, b, thick=None):
    return u8(X[kind]) + pt(*a) + pt(*b) + (u8(thick) if kind == "SquareEx" else b"")
def square2(kind, a, b, st): return u8(X[kind]) + pt(*a) + pt(*b) + u16(st)
def square3(kind, a, b, st, fl, version=1): return u8(X[kind]) + u16(version) + pt(*a) + pt(*b) + u16(st) + u16(fl)
def notetext(a, b, d, st, fl, fnt, color, border, version=1):
    return u8(X["NoteText"]) + u16(version) + pt(*a) + pt(*b) + u8(d) + u16(st) + u16(fl) + i16(fnt) + u32(color) + i32(border)
def metafile_obj(a, b, mid): return u8(X["MetaFile"]) + pt(*a) + pt(*b) + i16(mid)

def method_old(kind, symref, vals, positions, shows, rot, p, part, attrib=None):
    """xMethod (symref = symbol name), xMethodEx (name + attribute string), xMethodEx2 (symref = number; use method_ex2)"""
    out = u8(X[kind]) + s(symref) + s(vals[0]) + s(vals[1]) + s(vals[2])
    if kind == "MethodEx": out += s(attrib or "")
    for q in positions: out += pt(*q)
    return out + u8(shows) + u8(rot) + pt(*p) + u8(part)
def method_ex2(symnum, vals, positions, shows, rot, p, part, specials, attrib=""):
    out = u8(X["MethodEx2"]) + i16(symnum) + s(vals[0]) + s(vals[1]) + s(vals[2]) + s(attrib)
    for q in positions: out += pt(*q)
    out += u8(shows) + u8(rot) + pt(*p) + u8(part) + u16(len(specials))
    for fn, fv, fd, fp, ft in specials: out += s(fn) + s(fv) + s(fd) + pt(*fp) + u32(ft)
    return out
def method(symnum, p, part, rot, can_scale, sx, sy, fields, version=1):
    out = u8(X["MethodEx3"]) + i32(version) + i16(symnum) + pt(*p) + u8(part) + u8(rot) + i32(can_scale) + f64(sx) + f64(sy) + i32(len(fields))
    for ft, desc, val, show, pos in fields: out += i32(ft) + s(desc) + s(val) + i32(show) + pt(*pos)
    return out
