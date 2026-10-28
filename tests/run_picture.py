"""Insert picture, on the screen: a PNG, JPEG or BMP file becomes a picture object that follows the mouse until a click places it
(TinyCAD's Insert picture). Checked against independent readings: the saved file's IMAGE and METAFILE elements, the picture's
bytes (an independent uudecode, and ImageMagick for the BMP conversion), the pixels that are really drawn in the window, and the
editing around it:
  - what is stored: the file's bytes for PNG and JPEG, a lossless PNG for a BMP; the size TinyCAD gives a new picture; where a click puts it
  - what is drawn: the two halves of a red and blue picture, the right way round, and TinyCAD's "Invalid image" box for one that cannot be drawn
  - one undo step called Insert picture (undo takes the picture out of the design too, redo puts it back), a right click cancels cleanly
  - the same picture twice is kept once; two different pictures are kept as two
  - clicking inside a picture selects it and it can be dragged; copy and paste, Copy to and Import carry the picture
  - files that cannot be inserted (not a picture, missing, damaged, a metafile) change nothing."""
import os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from uuoracle import uu_decode, fit
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or shutil.which("convert") is None:
    print("Picture checks on screen skipped: need xvfb-run, ImageMagick and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
env = dict(os.environ, HOME=os.path.join(tmp, "home")); os.makedirs(env["HOME"])
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:400])
def run(script):
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=120, env=env)
    return r.stdout.split("\n"), r.returncode, r.stderr
def pick(lines, start, nth=0): return [l for l in lines if l.startswith(start)][nth]
def objs_of(line): return int(re.search(r"objects=(\d+)", line).group(1))
def sheet(path):
    r = ET.parse(path).getroot(); return r.findall("TinyCAD")[0] if r.tag == "TinyCADSheets" else r
def images(sh):
    out = {}
    for e in sh.findall("IMAGE"):
        uu = e.find("UUENCODE"); out[e.get("id")] = (e.get("type"), uu_decode((uu.text or "").replace("\r", ""), int(uu.get("size"))))
    return out
def pix(path, x, y):
    o = subprocess.run(["convert", path, "-crop", "1x1+%d+%d" % (x, y), "-format", "%[fx:int(255*r)],%[fx:int(255*g)],%[fx:int(255*b)]", "info:"], capture_output=True, text=True).stdout
    return tuple(int(v) for v in o.split(","))
def near(c, want, tol=40): return all(abs(a - b) <= tol for a, b in zip(c, want))
pics = os.path.join(tmp, "pics"); os.makedirs(pics)
def mk(name, args): subprocess.run(["convert", *args, os.path.join(pics, name)], check=True); return os.path.join(pics, name)
two = mk("two.png", ["-size", "100x60", "xc:red", "-fill", "blue", "-draw", "rectangle 50,0 99,59"])
grad = mk("grad.jpg", ["-size", "64x48", "gradient:red-blue"])
bmp = mk("two.bmp", ["-size", "100x60", "xc:red", "-fill", "blue", "-draw", "rectangle 50,0 99,59"])
other = mk("other.png", ["-size", "40x40", "xc:green"])
big = mk("big.png", ["-size", "1000x2000", "xc:orange"])
junk = os.path.join(pics, "junk.png"); open(junk, "w").write("this is not a png at all")
notes = os.path.join(pics, "notes.txt"); open(notes, "w").write("text")
emf = os.path.join(pics, "x.emf"); open(emf, "wb").write(b"\x01\x00\x00\x00" + bytes(40))
noext = os.path.join(pics, "noext"); open(noext, "wb").write(open(two, "rb").read())
out = os.path.join(tmp, "out"); os.makedirs(out)
# ---- a PNG, placed with a click ----
o, rc, err = run(f'''newdoc "ISO A4" landscape
undoinfo
info
picture "{two}"
info
save "{out}/pre.dsn"
mouse move 120 100
viewpoint 105 94
viewpoint 115 94
viewpoint 100 94
viewpoint 99 90
mouse down 120 100
mouse up 120 100
info
undoinfo
save "{out}/placed.dsn"
shot "{out}/placed.bmp"
undo
info
save "{out}/undone.dsn"
redo
info
save "{out}/redone.dsn"
''')
check("a PNG: ran cleanly", rc == 0 and not any(l.startswith("ERROR") for l in o), "\n".join(l for l in o if l.startswith("ERROR")) + err[-200:])
data = open(two, "rb").read()
pre = sheet(f"{out}/pre.dsn"); placed = sheet(f"{out}/placed.dsn")
imgs = images(placed)
check("the picture is kept in the design as PNG with exactly the file's bytes", len(imgs) == 1 and list(imgs.values())[0] == ("PNG", data), str({k: (v[0], len(v[1])) for k, v in imgs.items()}))
m = placed.findall("METAFILE"); mp = pre.findall("METAFILE")
cx, cy = fit(100, 60)
check("before it is placed it has the size TinyCAD gives a new picture, a unit a pixel (100 x 60 units = 20 x 12 mm)", len(mp) == 1 and mp[0].get("a") == "6.00000,6.00000" and mp[0].get("b") == "26.00000,18.00000", str(mp[0].attrib if mp else None))
check("and refers to its picture", len(m) == 1 and m[0].get("id") in imgs, str(m[0].attrib if m else None))
check("a click puts its bottom-right corner under the pointer, and it keeps its size", m[0].get("b") == "120.00000,100.00000" and m[0].get("a") == "100.00000,88.00000", str(m[0].attrib))
ud = pick(o, "UNDOINFO", 1)
check("it is one undo step named Insert picture", 'next="Insert picture"' in ud and "undo=1 " in ud, ud)
vp = [tuple(int(v) for v in l.split()[1:]) for l in o if l.startswith("VIEWPOINT")]
c_left, c_right, c_edge_in, c_edge_out = (pix(f"{out}/placed.bmp", *p) for p in vp)
check("it is drawn: the left half of the picture is red and the right half blue, the right way round", near(c_left, (255, 0, 0)) and near(c_right, (0, 0, 255)), f"{c_left} {c_right}")
check("and it ends where its rectangle ends (just outside the left edge, between the handles of the selected picture, is the white page)", near(c_edge_out, (255, 255, 255)), str(c_edge_out))
im = [objs_of(l) for l in o if l.startswith("INFO ")]
check("undo takes the picture away, and out of the design (no IMAGE is left in the file)", im[3] == 0 and not sheet(f"{out}/undone.dsn").findall("IMAGE") and not sheet(f"{out}/undone.dsn").findall("METAFILE"), str(im))
check("redo puts it back with its picture", im[4] == 1 and len(images(sheet(f"{out}/redone.dsn"))) == 1, str(im))
# ---- cancel ----
o, rc, err = run(f'''newdoc "ISO A4" landscape
info
undoinfo
picture "{two}"
mouse move 90 90
mouse rdown 90 90
mouse rup 90 90
info
undoinfo
save "{out}/cancel.dsn"
docs
''')
im = [objs_of(l) for l in o if l.startswith("INFO ")]; uds = [l for l in o if l.startswith("UNDOINFO")]
cs = sheet(f"{out}/cancel.dsn")
check("a right click cancels: no object, no undo step, no picture left in the design, the document not marked as changed",
      rc == 0 and im[0] == im[1] and uds[0] == uds[1] and not cs.findall("IMAGE") and not cs.findall("METAFILE") and "*" not in pick(o, "DOCS "), f"{im} {uds}")
# ---- JPEG and BMP ----
o, rc, err = run(f'''newdoc "ISO A4" landscape
picture "{grad}"
mouse move 120 100
mouse down 120 100
mouse up 120 100
save "{out}/jpg.dsn"
newdoc "ISO A4" landscape
picture "{bmp}"
mouse move 120 100
mouse down 120 100
mouse up 120 100
save "{out}/bmp.dsn"
''')
jd = open(grad, "rb").read(); ji = images(sheet(f"{out}/jpg.dsn")); jm = sheet(f"{out}/jpg.dsn").findall("METAFILE")[0]
check("a JPEG is kept as JPEG, byte for byte", len(ji) == 1 and list(ji.values())[0] == ("JPEG", jd), str({k: (v[0], len(v[1])) for k, v in ji.items()}))
# TinyCAD (CDrawBlockImport) moves the block by the distance of the pointer from the block's far corner *snapped to the grid* (10 units here), so a
# picture whose size is not a whole number of grid steps keeps the remainder: its corner is not exactly under the pointer
def snap10(v): return int(v / 10 + 0.5) * 10
b0 = (30 + 64, 30 + 48); move = (600 - snap10(b0[0]), 500 - snap10(b0[1]))
want_b = ((b0[0] + move[0]) / 5, (b0[1] + move[1]) / 5); want_a = ((30 + move[0]) / 5, (30 + move[1]) / 5)
got_a = tuple(float(v) for v in jm.get("a").split(",")); got_b = tuple(float(v) for v in jm.get("b").split(","))
check("a 64 x 48 picture is 64 x 48 units (12.8 x 9.6 mm) and goes where TinyCAD's block placement puts it (the pointer's distance from the grid-snapped corner)",
      all(abs(x - y) < 1e-6 for x, y in zip(got_a + got_b, want_a + want_b)) and abs((got_b[0] - got_a[0]) - 12.8) < 1e-6 and abs((got_b[1] - got_a[1]) - 9.6) < 1e-6, f"{jm.attrib} wanted a={want_a} b={want_b}")
bi = images(sheet(f"{out}/bmp.dsn")); btype, bdata = list(bi.values())[0] if bi else (None, b"")
check("a BMP is stored as a PNG", btype == "PNG" and bdata[:8] == b"\x89PNG\r\n\x1a\n", btype)
sp = os.path.join(out, "stored.png"); open(sp, "wb").write(bdata)
cmp = subprocess.run(["compare", "-metric", "AE", bmp, sp, "null:"], capture_output=True, text=True)
check("and the PNG is the same picture as the BMP, pixel for pixel", cmp.stderr.strip().split()[0] == "0", cmp.stderr)
# ---- the same picture twice, and two pictures ----
o, rc, err = run(f'''newdoc "ISO A4" landscape
picture "{two}"
mouse move 60 60
mouse down 60 60
mouse up 60 60
picture "{two}"
mouse move 120 100
mouse down 120 100
mouse up 120 100
picture "{other}"
mouse move 180 100
mouse down 180 100
mouse up 180 100
save "{out}/multi.dsn"
''')
ms = sheet(f"{out}/multi.dsn"); mi = images(ms)
check("the same picture inserted twice is kept once, and a different picture is kept as well", len(mi) == 2 and len(ms.findall("METAFILE")) == 3, f"{len(mi)} pictures, {len(ms.findall('METAFILE'))} objects")
ids = [e.get("id") for e in ms.findall("METAFILE")]
check("the first two objects use the same picture, the third another", ids[0] == ids[1] != ids[2], str(ids))
# ---- select, drag, copy, paste, Copy to, Import ----
o, rc, err = run(f'''newdoc "ISO A4" landscape
picture "{two}"
mouse move 120 100
mouse down 120 100
mouse up 120 100
selclear
mouse down 110 94
mouse up 110 94
findinfo
mouse down 110 94
mouse move 130 104
mouse up 130 104
save "{out}/moved.dsn"
copy
newdoc "ISO A4" landscape
paste
mouse move 80 60
mouse down 80 60
mouse up 80 60
save "{out}/pasted.dsn"
open "{out}/moved.dsn"
selectclass TDrawMetaFile
copyto "{out}/copyto.dsn"
newdoc "ISO A4" landscape
import "{out}/copyto.dsn"
mouse move 140 90
mouse down 140 90
mouse up 140 90
save "{out}/imported.dsn"
''')
check("select, drag, copy, paste, Copy to and Import: ran cleanly", rc == 0 and not any(l.startswith("ERROR") for l in o), "\n".join(l for l in o if l.startswith("ERROR")) + err[-200:])
check("clicking inside a picture selects it (the whole rectangle is clickable, as in TinyCAD)", " sel=1 " in pick(o, "FINDINFO"), pick(o, "FINDINFO"))
mv = sheet(f"{out}/moved.dsn").findall("METAFILE")[0]
check("dragging it by (20, 10) mm moves it by exactly that and keeps its size", mv.get("a") == "120.00000,98.00000" and mv.get("b") == "140.00000,110.00000", str(mv.attrib))
ps = sheet(f"{out}/pasted.dsn"); pi_ = images(ps)
check("copy and paste into another document brings the picture with it (the same bytes)", len(pi_) == 1 and list(pi_.values())[0] == ("PNG", data) and len(ps.findall("METAFILE")) == 1, str({k: (v[0], len(v[1])) for k, v in pi_.items()}))
cs2 = sheet(f"{out}/copyto.dsn"); ci = images(cs2)
check("Copy to writes the picture with the selected picture object", len(ci) == 1 and list(ci.values())[0] == ("PNG", data) and len(cs2.findall("METAFILE")) == 1, str({k: (v[0], len(v[1])) for k, v in ci.items()}))
ims = sheet(f"{out}/imported.dsn"); ii = images(ims)
check("and Import brings it into another design", len(ii) == 1 and list(ii.values())[0] == ("PNG", data) and len(ims.findall("METAFILE")) == 1, str({k: (v[0], len(v[1])) for k, v in ii.items()}))
# ---- big pictures are scaled to the sheet ----
o, rc, err = run(f'''newdoc "ISO A4" landscape
picture "{big}"
save "{out}/big.dsn"
''')
bm = sheet(f"{out}/big.dsn").findall("METAFILE")[0]; bcx, bcy = fit(1000, 2000)
check("a 1000 x 2000 picture is scaled down to 250 x 500 units, keeping its shape", bm.get("b") == "%.5f,%.5f" % ((30 + bcx) / 5, (30 + bcy) / 5) and (bcx, bcy) == (250, 500), str(bm.attrib))
# ---- what cannot be inserted ----
o, rc, err = run(f'''newdoc "ISO A4" landscape
info
undoinfo
picture "{notes}"
picture "{pics}/missing.png"
picture "{junk}"
picture "{emf}"
picture "{noext}"
info
undoinfo
''')
res = [int(l.split()[1]) for l in o if l.startswith("PICTURE ")]; inf = [objs_of(l) for l in o if l.startswith("INFO ")]; uds = [l for l in o if l.startswith("UNDOINFO")]
check("files that are not pictures, missing, damaged, a metafile or without an extension are refused, reported, and not a crash", rc == 0 and res == [0, 0, 0, 0, 0] and not any(l.startswith("ERROR") for l in o), f"{res} {[l for l in o if l.startswith('ERROR')]}")
check("and they change nothing: no object, no undo step", inf[0] == inf[1] and uds[0] == uds[1], f"{inf} {uds}")
# ---- a picture the program cannot draw is shown as TinyCAD shows it ----
sample = next(p for p in sorted(os.path.join(dp, f) for dp, _, fs in os.walk(os.environ.get("TC_EXAMPLES", "examples")) for f in fs if f.endswith(".dsn")) if "LED Flasher" in p)
raw = open(sample, encoding="utf-8", errors="replace").read()
from uuoracle import uu_lines
from xml.sax.saxutils import escape
lines = uu_lines(open(two, "rb").read())
image = '<IMAGE id="7" type="METAFILE"><UUENCODE size="%d">\r\n' % len(open(two, "rb").read()) + "".join(escape(l, {"'": "&#039;", '"': "&quot;"}) + "\n" for l in lines) + "</UUENCODE></IMAGE>\r\n"
j = raw.index("<SYMBOL ")
bad = raw[:j] + image + '<METAFILE a="150,40" b="190,64" id="7" />\r\n' + raw[j:]
bp = os.path.join(out, "invalid.dsn"); open(bp, "w", encoding="utf-8").write(bad)
o, rc, err = run(f'''open "{bp}"
viewpoint 150 52
viewpoint 170 52
viewpoint 170 46
shot "{out}/invalid.bmp"
''')
vp = [tuple(int(v) for v in l.split()[1:]) for l in o if l.startswith("VIEWPOINT")]
edge = pix(f"{out}/invalid.bmp", vp[0][0], vp[0][1]); inside = pix(f"{out}/invalid.bmp", vp[1][0], vp[1][1])
check("a picture that cannot be drawn is shown as a white box with a black outline (TinyCAD's Invalid image), not left blank or crashed", rc == 0 and near(edge, (0, 0, 0), 60) and near(inside, (255, 255, 255), 30), f"edge {edge} inside {inside}")
print(f"picture: {checks} checks, {len(fails)} failures")
print("\nPICTURE ON SCREEN CHECKS PASSED" if not fails else f"\nPICTURE ON SCREEN CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
