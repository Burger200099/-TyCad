"""Pictures in a design, core only: the image table, the METAFILE object, TinyCAD's uuencoding and the sizes. An independent
implementation of TinyCAD's own encoder and decoder (CXMLWriter::addChildDataUUencode, CXMLReader::uudecode, written here from reading
the C++) is compared with the program:
  - what the program writes: the UUENCODE text must be, character for character, what TinyCAD's encoder gives for the same bytes
  - what the program reads: a design whose picture was encoded here, with other picture numbers than the program would choose
  - the sizes read from the bytes of PNG and JPEG files agree with ImageMagick's, and a picture's size on the sheet follows TinyCAD's rule
  - a picture survives load and save unchanged, and an unknown type is carried along
Needs ImageMagick (convert, identify) to make the test pictures."""
import os, random, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
BUILD = os.environ.get("TC_BUILD", "build"); EXE = os.path.join(BUILD, "imagetest")
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("convert") is None or shutil.which("identify") is None:
    print("Picture checks skipped: need ImageMagick (convert, identify)"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:300])
def run(*a):
    r = subprocess.run([EXE, *a], capture_output=True, text=True)
    if r.returncode != 0: raise SystemExit("imagetest failed: " + " ".join(a) + "\n" + r.stdout[-300:] + r.stderr[-300:])
    return r.stdout.strip().split("\n")
from uuoracle import enc, uu_lines, dec, uu_decode, fit
# ---- test pictures ----
pics = {}
def mk(name, args):
    p = os.path.join(tmp, name); subprocess.run(["convert", *args, p], check=True); pics[name] = p
mk("small.png", ["-size", "100x60", "xc:red", "-fill", "blue", "-draw", "rectangle 50,0 99,59"])
mk("wide.png", ["-size", "800x300", "gradient:green-yellow"])
mk("tall.png", ["-size", "300x900", "gradient:white-black"])
mk("huge.png", ["-size", "1000x2000", "xc:orange"])
mk("one.png", ["-size", "1x1", "xc:black"])
mk("odd.png", ["-size", "37x41", "plasma:fractal"])
mk("small.jpg", ["-size", "64x48", "gradient:red-blue"])
mk("big.jpg", ["-size", "1000x700", "plasma:fractal"])
mk("line.jpg", ["-size", "640x1", "xc:gray"])
# ---- sizes ----
for name, p in pics.items():
    ident = subprocess.run(["identify", "-format", "%w %h", p], capture_output=True, text=True).stdout.split()
    got = run("size", p)[0].split()
    check(f"{name}: type and size read from the bytes agree with ImageMagick", got[1] == ("PNG" if name.endswith("png") else "JPEG") and got[2:] == ident, f"{got} vs {ident}")
bad = os.path.join(tmp, "notes.txt"); open(bad, "w").write("not a picture")
check("a file that is not a picture has no type", run("size", bad)[0] == "SIZE none", "")
trunc = os.path.join(tmp, "trunc.png"); open(trunc, "wb").write(open(pics["small.png"], "rb").read()[:20])
check("a truncated PNG is not read", run("size", trunc)[0] == "SIZE none", run("size", trunc)[0])
truncj = os.path.join(tmp, "trunc.jpg"); open(truncj, "wb").write(open(pics["small.jpg"], "rb").read()[:12])
check("a truncated JPEG is not read", run("size", truncj)[0] == "SIZE none", run("size", truncj)[0])
for w, h in ((1, 1), (100, 60), (500, 500), (501, 10), (800, 300), (300, 900), (1000, 2000), (2000, 1000), (7, 3000), (3000, 7), (499, 501)):
    check(f"size on the sheet of a {w} x {h} picture", run("fit", str(w), str(h))[0] == "FIT %d %d" % fit(w, h), run("fit", str(w), str(h))[0] + f" vs {fit(w, h)}")
# ---- what the program writes ----
rnd = random.Random(7)
for name, p in pics.items():
    data = open(p, "rb").read(); out = os.path.join(tmp, name + ".dsn")
    run("make", p, out)
    root = ET.parse(out).getroot(); sh = root.findall("TinyCAD")[0] if root.tag == "TinyCADSheets" else root
    imgs = sh.findall("IMAGE"); objs = sh.findall("METAFILE")
    check(f"{name}: one IMAGE and one METAFILE are written", len(imgs) == 1 and len(objs) == 1, f"{len(imgs)} {len(objs)}")
    im = imgs[0]; uu = im.find("UUENCODE")
    check(f"{name}: the IMAGE has its type and a UUENCODE of the right size", im.get("type") == ("PNG" if name.endswith("png") else "JPEG") and uu is not None and int(uu.get("size")) == len(data), str(im.attrib))
    text = (uu.text or "").replace("\r", "")
    body = text[1:] if text.startswith("\n") else text
    exp = uu_lines(data)
    got_lines = body.split("\n")
    while got_lines and got_lines[-1].strip() == "" and (len(got_lines) > len(exp)): got_lines.pop()
    check(f"{name}: the encoded text is character for character what TinyCAD's encoder writes", got_lines == exp, f"{len(got_lines)} lines vs {len(exp)}; first differing: " + str(next(((a, b) for a, b in zip(got_lines, exp) if a != b), None)))
    check(f"{name}: and an independent decoder gives back the file", uu_decode(text, len(data)) == data, "")
    w, h = (int(v) for v in subprocess.run(["identify", "-format", "%w %h", p], capture_output=True, text=True).stdout.split())
    cx, cy = fit(w, h); ob = objs[0]
    a = tuple(float(v) for v in ob.get("a").split(",")); b = tuple(float(v) for v in ob.get("b").split(","))
    check(f"{name}: the METAFILE refers to the IMAGE and has the size TinyCAD gives a new picture (at 30,30 design units; the file counts in mm: 6,6)", ob.get("id") == im.get("id") and a == (6.0, 6.0) and all(abs(p - q) < 1e-9 for p, q in zip(b, ((30.0 + cx) / 5, (30.0 + cy) / 5))), f"{ob.attrib} {cx}x{cy}")
    d = run("dump", out, os.path.join(tmp, name + "_d")); got = open(os.path.join(tmp, name + "_d1.bin"), "rb").read()
    check(f"{name}: the program reads back what it wrote", got == data and d[1].split()[2:] == [im.get("type"), str(len(data))], str(d))
# random bytes of every length, so the line ends and the padding are all met (and the characters that XML must escape)
for n in list(range(0, 140)) + [255, 256, 1000, 4097]:
    data = bytes(rnd.randrange(256) for _ in range(n)); f = os.path.join(tmp, "r.bin"); open(f, "wb").write(data)
    # a "picture" of random bytes: give it a PNG signature so it is accepted, then the rest is arbitrary
    data = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + data; open(f, "wb").write(data)
    out = os.path.join(tmp, "r.dsn"); run("make", f, out)
    sh = ET.parse(out).getroot(); sh = sh.findall("TinyCAD")[0] if sh.tag == "TinyCADSheets" else sh
    uu = sh.find("IMAGE").find("UUENCODE"); text = (uu.text or "").replace("\r", "")
    exp = uu_lines(data); body = text[1:] if text.startswith("\n") else text; got_lines = body.split("\n")
    while got_lines and got_lines[-1].strip() == "" and len(got_lines) > len(exp): got_lines.pop()
    check(f"{len(data)} random bytes: written as TinyCAD's encoder writes them, and decoded back", got_lines == exp and uu_decode(text, len(data)) == data, f"{len(got_lines)} vs {len(exp)}")
    run("dump", out, os.path.join(tmp, "rd")); check(f"{len(data)} random bytes: the program decodes them", open(os.path.join(tmp, "rd1.bin"), "rb").read() == data, "")
print(f"what the program writes: {checks} checks so far, {len(fails)} failures")
# ---- what the program reads: a design that a different program made ----
sample = next(p for p in sorted(os.path.join(dp, f) for dp, _, fs in os.walk(EX) for f in fs if f.endswith(".dsn")) if "LED Flasher" in p)
raw = open(sample, encoding="utf-8", errors="replace").read()
data = open(pics["odd.png"], "rb").read(); lines = uu_lines(data)
image = f'<IMAGE id="7" type="PNG"><UUENCODE size="{len(data)}">\r\n' + "".join(escape(l, {"'": "&#039;", '"': "&quot;"}) + "\n" for l in lines) + "</UUENCODE></IMAGE>\r\n"
obj = '<METAFILE a="10,12" b="47,53" id="7" />\r\n'
i = raw.index("<SYMBOLDEF") if "<SYMBOLDEF" in raw else raw.index("<SYMBOL ")
j = raw.index("<SYMBOL ")
foreign = raw[:i] + image + raw[i:j] + obj + raw[j:]
fp = os.path.join(tmp, "foreign.dsn"); open(fp, "w", encoding="utf-8").write(foreign)
d = run("dump", fp, os.path.join(tmp, "fd"))
objline = [l for l in d if l.startswith("OBJ")][0].split()
imgline = [l for l in d if l.startswith("IMG")][0].split()
check("a design with a picture encoded by another implementation, under another number, is read (corners 10,12 and 47,53 mm = 50,60 and 235,265 design units)", objline[2:4] == ["50.000,60.000", "235.000,265.000"] and imgline[2] == "PNG" and int(imgline[3]) == len(data) and open(os.path.join(tmp, "fd" + imgline[1] + ".bin"), "rb").read() == data, str(d))
check("and the object follows its picture to the number the program gave it", objline[4] == imgline[1], str(d))
# the picture is carried through a load and a save, and the rest of the design with it
rs = os.path.join(tmp, "resaved.dsn"); run("resave", fp, rs)
d2 = run("dump", rs, os.path.join(tmp, "rd2")); img2 = [l for l in d2 if l.startswith("IMG")][0].split()
check("load then save keeps the picture, its type and every byte", img2[2] == "PNG" and open(os.path.join(tmp, "rd2" + img2[1] + ".bin"), "rb").read() == data, str(d2))
so = ET.parse(sample).getroot(); so = so.findall("TinyCAD")[0] if so.tag == "TinyCADSheets" else so
sr = ET.parse(rs).getroot(); sr = sr.findall("TinyCAD")[0] if sr.tag == "TinyCADSheets" else sr
check("the rest of the design is untouched (every symbol, wire and junction is still there)", all(len(so.findall(t)) == len(sr.findall(t)) for t in ("SYMBOL", "WIRE", "JUNCTION", "SYMBOLDEF")), "")
# a type this port does not draw is carried along
meta = foreign.replace('type="PNG"', 'type="METAFILE"'); mp = os.path.join(tmp, "meta.dsn"); open(mp, "w", encoding="utf-8").write(meta)
mr = os.path.join(tmp, "meta_re.dsn"); run("resave", mp, mr)
d3 = run("dump", mr, os.path.join(tmp, "rd3")); img3 = [l for l in d3 if l.startswith("IMG")][0].split()
check("a picture of a type this port cannot draw (a metafile) is kept as it was, not lost", img3[2] == "METAFILE" and open(os.path.join(tmp, "rd3" + img3[1] + ".bin"), "rb").read() == data, str(d3))
# two identical pictures in the file stay two (as in TinyCAD); pictures that are not in use are not written
two = foreign.replace(image, image + image.replace('id="7"', 'id="9"')).replace(obj, obj + '<METAFILE a="60,12" b="97,53" id="9" />\r\n')
tp = os.path.join(tmp, "two.dsn"); open(tp, "w", encoding="utf-8").write(two); tr_ = os.path.join(tmp, "two_re.dsn"); run("resave", tp, tr_)
sr2 = ET.parse(tr_).getroot(); sr2 = sr2.findall("TinyCAD")[0] if sr2.tag == "TinyCADSheets" else sr2
check("two objects with two pictures keep two pictures in the file", len(sr2.findall("IMAGE")) == 2 and len(sr2.findall("METAFILE")) == 2, f"{len(sr2.findall('IMAGE'))} {len(sr2.findall('METAFILE'))}")
unused = foreign.replace(obj, ""); up = os.path.join(tmp, "unused.dsn"); open(up, "w", encoding="utf-8").write(unused); ur = os.path.join(tmp, "unused_re.dsn"); run("resave", up, ur)
sr3 = ET.parse(ur).getroot(); sr3 = sr3.findall("TinyCAD")[0] if sr3.tag == "TinyCADSheets" else sr3
check("a picture no object uses is not written back", len(sr3.findall("IMAGE")) == 0, f"{len(sr3.findall('IMAGE'))}")
print(f"pictures: {checks} checks, {len(fails)} failures")
print("\nPICTURE CHECKS PASSED" if not fails else f"\nPICTURE CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
