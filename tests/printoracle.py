"""An independent statement of how TinyCAD cuts a design into printed pages (TinyCadView.cpp OnBeginPrinting / OnPrepareDC / DoPreparePrinting and
SpecialPrintDlg.cpp), written from that source in Python, to check UPrint against. Python's own printf formatting stands in for _stprintf."""
import math, re
PX = 5

def fit_scale(horz, vert, pw, ph):
    width = max(horz, vert); height = min(horz, vert)
    if pw < ph:
        return min(width * 100 * PX / ph, height * 100 * PX / pw)
    return min(width * 100 * PX / pw, height * 100 * PX / ph)

def zoom(dpi, scale):
    nz = (dpi * 1000) // (PX * 254)          # an int expression in C++
    nz = (nz * scale) / 100.0
    return nz / 100.0

def layout(horz, vert, dpi, pw, ph, scale, all_sheets, nsheets):
    width = max(horz, vert) * PX; height = min(horz, vert) * PX
    if pw < ph:
        sx = (scale * pw / height) / 100.0; sy = (scale * ph / width) / 100.0
    else:
        sx = (scale * pw / width) / 100.0; sy = (scale * ph / height) / 100.0
    cols = int(sx); rows = int(sy)
    if sx - int(sx) > 0.01: cols += 1
    if sy - int(sy) > 0.01: rows += 1
    cols = max(cols, 1); rows = max(rows, 1)         # (TinyCAD would divide by zero)
    sheets = nsheets if (all_sheets and nsheets > 1) else 1
    pages = []
    w = horz * PX; h = vert * PX
    for cur in range(1, cols * rows * sheets + 1):
        if sheets > 1:
            page = (cur - 1) // sheets; sheet = (cur - 1) % sheets
        else:
            page = cur - 1; sheet = 0
        col = page // rows; row = page % rows
        pages.append((cur, sheet, col, row, int((col * w / scale) * 100), int((row * h / scale) * 100)))
    return dict(cols=cols, rows=rows, sheets=sheets, pages=len(pages), zoom=zoom(dpi, scale), list=pages)

def scale_text(v):
    return "%3.3g" % v

def atof(s):
    m = re.match(r"\s*([+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)", s)
    return float(m.group(1)) if m else 0.0

def page_range(pages, a, b):
    first, last = 1, pages
    if a > 0 or b > 0:
        if a < 1: a = 1
        if b < 1: b = pages
        if b < a: a, b = b, a
        first = max(1, a); last = min(pages, b)
    return (pages > 0 and first <= last), first, last
