"""TinyCAD's uuencode and uudecode (CXMLWriter::addChildDataUUencode, CXMLReader::uudecode) and its rule for the size of a new picture,
written from reading the C++ and shared by run_image.py and run_picture.py, as an independent check of the program."""
# ---- TinyCAD's uuencode and uudecode, as the C++ does them ----
def enc(c): return chr((c & 0o77) + 32)
def uu_lines(data):
    out = []; i = 0; n = len(data)
    while i < n:
        ls = min(n - i, 45); chars = [enc(ls)]
        while ls > 0:
            i0 = data[i]; i += 1
            i1 = 0
            if i < n: i1 = data[i]; i += 1
            i2 = 0
            if i < n: i2 = data[i]; i += 1
            chars += [enc(i0 >> 2), enc(((i0 << 4) & 0o60) | ((i1 >> 4) & 0o17)), enc(((i1 << 2) & 0o74) | ((i2 >> 6) & 0o3)), enc(i2 & 0o77)]
            ls -= 3
        out.append("".join(chars))
    return out
def dec(c): return (ord(c) - 32) & 0o77
def uu_decode(text, size):
    out = bytearray(); state = 0; line = 0; bs = [0, 0, 0, 0]
    for ch in text:
        if state == 0:
            if ch in " \t\r\n": continue
            line = dec(ch); state = 1
        elif state in (1, 2, 3):
            bs[state - 1] = ch; state += 1
        else:
            bs[3] = ch
            c = [(dec(bs[0]) << 2 | dec(bs[1]) >> 4) & 255, (dec(bs[1]) << 4 | dec(bs[2]) >> 2) & 255, (dec(bs[2]) << 6 | dec(bs[3])) & 255]
            for v in c:
                if line > 0 and len(out) < size: out.append(v); line -= 1
            state = 0 if line == 0 else 1
    return bytes(out)
def fit(w, h):
    cx, cy = w, h
    if cx > 500: cy = (500 * cy) // cx; cx = 500
    if cy > 500: cx = (500 * cx) // cy; cy = 500
    return cx, cy
