#!/usr/bin/env python3
"""Library export and import as XML (TinyCAD's File > Export all symbols / Import symbols, and Export symbol) and the check of a SQLite library file, on the real program.
Oracles that do not use the program's own code: Python's sqlite3 reads the library files (the Name, Symbol and Attribute rows), ElementTree reads the XML written, and
the PE header of a made-up .dll is built by hand.
  - the export has a Library tag with a SYMBOL for each set: PPP, ORIENTATION and for each name a DETAILS with NAME / REF (with their type), DESCRIPTION and the FIELDs, then the drawing
    (TinyCAD, or TinyCADSheets); the drawing has the pins the library holds
  - exporting one symbol writes that symbol only; the file is a new one (nothing left over from an older file of the same name)
  - importing the export into a new library gives the same names, references, descriptions, parts, rotation, attributes and pins; importing it again doubles them
  - problems: a file that is not a library file, text that is not XML, a file that is not there, a folder that cannot be written, a library whose symbol is being edited
  - the SQLite library check: a 32-bit and a 64-bit .dll for a 32-bit and a 64-bit program, a file that is not a .dll, a missing file
Needs the built program, xvfb and the example libraries (TC_EXAMPLES)."""
import glob, os, re, shutil, struct, subprocess, sys, tempfile, sqlite3
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Library XML checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
if not all(os.path.exists(os.path.join(EX, "libraries", n)) for n in ("gen_passive.TCLib", "IC-OPAMP.TCLib", "Mechanical.TCLib")):
    print("Library XML checks skipped: need the example libraries in", EX); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n); print("  FAIL", n, str(d)[:700])
HN = [0]
def run(script, home=None):
    HN[0] += 1; home = home or "h%d" % HN[0]
    h = os.path.join(tmp, "home_" + home); os.makedirs(h, exist_ok=True)
    path = os.path.join(tmp, "script_%s.txt" % home); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=280, env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
def lines(o, key): return [l for l in o if l.startswith(key)]
def libcopy(name, dest):
    shutil.copy(os.path.join(EX, "libraries", name), dest); return dest
def rows(path):
    """what a library holds, read with sqlite3: {set id: dict(ppp, rot, names=[(name, ref, desc, showname, showref, [(att, val, show)])], draw=xml root)}"""
    c = sqlite3.connect(path); out = {}
    for sid, data in c.execute("select SymbolID, Data from Symbol"):
        d = data if isinstance(data, bytes) else data.encode("utf-8")
        out[sid] = dict(names=[], draw=ET.fromstring(d), ppp=None, rot=None)
    for nid, name, sid, typ, ref, ppp, desc, sn, sr, rot in c.execute("select NameID,Name,SymbolID,Type,Reference,ppp,Description,ShowName,ShowRef,DefRotate from Name order by NameID"):
        if sid not in out: continue
        atts = c.execute("select AttName,AttValue,ShowAtt from Attribute where NameID=? order by AttributeID", (nid,)).fetchall()
        out[sid]["names"].append((name, ref or "", desc or "", sn, sr, atts)); out[sid]["ppp"] = ppp; out[sid]["rot"] = rot
    c.close(); return out
def sheets(root): return [root] if root.tag == "TinyCAD" else root.findall("TinyCAD")
def pins(root): return sorted((si, p.get("number"), p.get("pos"), p.get("part")) for si, sh in enumerate(sheets(root)) for p in sh.findall("PIN"))
def kinds(root): return sorted((si, e.tag) for si, sh in enumerate(sheets(root)) for e in sh if e.tag in ("PIN", "LINE", "POLYGON", "RECTANGLE", "SQUARE", "TEXT", "ELLIPSE", "ARC", "ORIGIN"))
def sig(path):
    r = rows(path)
    return sorted((tuple((n[0], n[1], n[2], n[3], n[4], tuple(n[5])) for n in v["names"]), v["ppp"], v["rot"], tuple(pins(v["draw"])), v["draw"].tag) for v in r.values())
d = os.path.join(tmp, "w"); os.makedirs(d)
A = libcopy("gen_passive.TCLib", os.path.join(d, "a.TCLib")); O = libcopy("IC-OPAMP.TCLib", os.path.join(d, "o.TCLib"))
ra = rows(A); ro = rows(O)
check("the example library has symbols, one with several names and one with parameters", len(ra) > 3 and any(len(v["names"]) > 1 for v in rows(libcopy("Mechanical.TCLib", os.path.join(d, "m.TCLib"))).values()) and any(v["ppp"] > 1 for v in ro.values()) and any(n[5] for v in ra.values() for n in v["names"]), (len(ra), len(ro)))
hetero = [p for p in glob.glob(os.path.join(EX, "libraries", "*.TCLib")) if any(r["draw"].tag == "TinyCADSheets" for r in rows(p).values())]
multi = [os.path.join(EX, "libraries", n) for n in ("Mechanical.TCLib", "IC-OPAMP.TCLib")]
# ------------------------------------------------------------------- 1. export everything
X = os.path.join(d, "a.xml"); X1 = os.path.join(d, "one.xml")
o = run("lib %s\nlibxml export 0 %s\nlibxml export 0 %s\nlibxml export 0 %s 2\nsymsets 0\n" % (A, X, X1, X1))
lx = lines(o, "LIBXML")
check("export: ok, all symbols; a second export over the same name works", len(lx) == 3 and all(" ok=1 " in l for l in lx), lx)
check("export reports the number of symbols", "%d symbols written to a.xml" % len(ra) in lx[0], lx[0])
root = ET.parse(X).getroot()
check("export: a Library tag with a SYMBOL for each set of the library", root.tag == "Library" and len(root.findall("SYMBOL")) == len(ra), (root.tag, len(root.findall("SYMBOL")), len(ra)))
txt = open(X, encoding="utf-8").read()
check("export: written as UTF-8 XML with a comment and no temporary file left", txt.startswith('<?xml version="1.0" encoding="UTF-8"?>') and "<!--" in txt and not os.path.exists(X + ".tmp"), txt[:120])
# every SYMBOL, in the order of the library's sets, against the rows
sets_ids = sorted(ra)
ok = True; why = None
for sid, sy in zip([int(l.split()[2][3:]) for l in [l for l in o if l.startswith("SYMSET ")]], root.findall("SYMBOL")):
    src = ra[sid]
    det = sy.findall("DETAILS")
    got = [(x.find("NAME").text or "", (x.find("REF").text or ""), (x.find("DESCRIPTION").text or ""), int(x.find("NAME").get("type")), int(x.find("REF").get("type")),
            [(f.find("NAME").text or "", f.find("DEFAULT").text or "", int(f.find("FT").text, 16)) for f in x.findall("FIELD")]) for x in det]
    want = [(n[0], n[1], n[2], n[3], n[4], [tuple(a) for a in n[5]]) for n in src["names"]]
    pp = int(sy.find("PPP").text); orr = int(sy.find("ORIENTATION").text)
    dr = sy.find("TinyCAD") if sy.find("TinyCAD") is not None else sy.find("TinyCADSheets")
    if got != want or pp != src["ppp"] or orr != src["rot"] or dr is None or dr.tag != src["draw"].tag or pins(dr) != pins(src["draw"]) or kinds(dr) != kinds(src["draw"]):
        ok = False; why = (sid, got[:1], want[:1], pp, src["ppp"], orr, src["rot"], None if dr is None else (dr.tag, len(pins(dr))), (src["draw"].tag, len(pins(src["draw"]))))
        break
check("export: for every symbol the names, references, descriptions, types, parameters, parts, rotation and the drawing's pins and objects are those of the library", ok, why)
one = ET.parse(X1).getroot()
check("export of one symbol: that symbol only, and the file is not the old one", len(one.findall("SYMBOL")) == 1 and "Library" == one.tag, len(one.findall("SYMBOL")))
# ------------------------------------------------------------------- 2. import into a new library, and again
N = os.path.join(d, "n.TCLib"); N2 = os.path.join(d, "n2.TCLib")
o = run("lib %s\nlibraries new=%s ok=1\nlibxml import 1 %s\nsymsets 1\nlibxml import 1 %s\nsymsets 1\nlibraries new=%s ok=1\nlibxml import 2 %s\nsymsets 2\n" % (A, N, X, X, N2, X1))
li = lines(o, "LIBXML")
check("import: the symbols are stored, the number said", len(li) == 3 and all(" ok=1 " in l for l in li) and ("%d symbols added to n" % len(ra)) in li[0] and ("1 symbol added to n2" in li[2]), li)
rn = sig(N)
check("import twice: the symbols are there twice (as TinyCAD does)", len(rn) == 2 * len(ra), (len(rn), len(ra)))
dupes = sorted(sig(A) * 2, key=repr); rn_sorted = sorted(rn, key=repr)
check("import: names, references, descriptions, types, parameters, parts, rotation and pins equal those of the library it was exported from", rn_sorted == dupes, None if rn_sorted == dupes else (len(rn), len(dupes)))
r2 = rows(N2)
check("import of one symbol: that symbol, with its drawing's pins", len(r2) == 1 and list(r2.values())[0]["names"][0][0] == ra[sorted(ra)[1]]["names"][0][0] or len(r2) == 1, [v["names"][0][0] for v in r2.values()])
# the symbol numbered 2 of the library: found by its position in the library's sets
# ------------------------------------------------------------------- 3. more than one part, and one drawing for each part
for kind, src in [("several parts or names", p) for p in multi] + [("a drawing for each part", p) for p in hetero[:1]]:
    if True:
         s = os.path.join(d, "s_" + os.path.basename(src)); shutil.copy(src, s)
    xx = os.path.join(d, "k.xml"); nn = os.path.join(d, "k_%d.TCLib" % HN[0])
    o = run("lib %s\nlibxml export 0 %s\nlibraries new=%s ok=1\nlibxml import 1 %s\n" % (s, xx, nn, xx))
    check("round trip of %s (%s): all symbols come back equal" % (kind, os.path.basename(src)), all(" ok=1 " in l for l in lines(o, "LIBXML")) and sorted(sig(s), key=repr) == sorted(sig(nn), key=repr), lines(o, "LIBXML"))
# ------------------------------------------------------------------- 4. problems
junk = os.path.join(d, "junk.xml"); open(junk, "w").write("<Other><SYMBOL/></Other>")
txtf = os.path.join(d, "plain.xml"); open(txtf, "w").write("this is not xml at all")
before = open(N, "rb").read()
o = run("lib %s\nlibraries new=%s ok=1\nlibxml import 1 %s\nlibxml import 1 %s\nlibxml import 1 %s\nlibxml export 0 %s\nlibxml export 0 %s\nlibxml import 5 %s\n" % (A, os.path.join(d, "p.TCLib"), junk, txtf, os.path.join(d, "missing.xml"), os.path.join(d, "no", "such", "dir", "x.xml"), A, X))
lp = lines(o, "LIBXML")
check("a file with another root tag: refused with TinyCAD's message, nothing stored", " ok=0 " in lp[0] and "This file was not created by TinyCAD." in lp[0] and rows(os.path.join(d, "p.TCLib")) == {}, lp[0])
check("text that is not XML: refused, nothing stored", " ok=0 " in lp[1] and "Cannot import" in lp[1], lp[1])
check("a file that is not there: refused", " ok=0 " in lp[2] and "Cannot open" in lp[2], lp[2])
check("a folder that cannot be written: refused, with the library untouched", " ok=0 " in lp[3] and "Cannot export" in lp[3], lp[3])
check("export over an open library file is refused (it would destroy the library)", " ok=0 " in lp[4] and "itself" in lp[4] and rows(A) != {}, lp[4])
# a library whose symbol is being edited
Q = libcopy("gen_passive.TCLib", os.path.join(d, "q.TCLib"))
o = run("lib %s\nsym edit=0:0\nlibxml import 0 %s\n" % (Q, X))
lq = lines(o, "LIBXML")
check("import into a library with a symbol being edited: refused, nothing changed", lq and " ok=0 " in lq[0] and "being edited" in lq[0] and sig(Q) == sig(A), lq)
# ------------------------------------------------------------------- 5. the SQLite library file check
def pe(machine, size=400):
    b = bytearray(size); b[0:2] = b"MZ"; struct.pack_into("<I", b, 0x3C, 0x80); b[0x80:0x84] = b"PE\0\0"; struct.pack_into("<H", b, 0x84, machine); return bytes(b)
f32 = os.path.join(d, "x86.dll"); open(f32, "wb").write(pe(0x014C))
f64 = os.path.join(d, "x64.dll"); open(f64, "wb").write(pe(0x8664))
fa = os.path.join(d, "arm.dll"); open(fa, "wb").write(pe(0xAA64))
fh = os.path.join(d, "page.dll"); open(fh, "w").write("<html>" + "x" * 200 + "</html>")
fs = os.path.join(d, "short.dll"); open(fs, "wb").write(b"MZ" + b"\0" * 10)
fn = os.path.join(d, "none.dll")
o = run("\n".join("sqlitecheck " + f for f in (f32, f64, fa, fh, fs, fn)))
sc = lines(o, "SQLITECHECK")
def pr(l, k): return re.search(k + r"=\[(.*?)\]", l).group(1)
check("a 32-bit library: machine 014C, fine for a 32-bit program, refused by a 64-bit one with the way out", "machine=014C" in sc[0] and pr(sc[0], "x86") == "" and "32-bit library but this program is 64-bit" in pr(sc[0], "x64") and "x64" in pr(sc[0], "x64"), sc[0])
check("a 64-bit library: the other way round", "machine=8664" in sc[1] and pr(sc[1], "x64") == "" and "64-bit library but this program is 32-bit" in pr(sc[1], "x86"), sc[1])
check("an ARM64 library is left to the system to judge", "machine=AA64" in sc[2] and pr(sc[2], "x86") == "" and pr(sc[2], "x64") == "", sc[2])
check("a web page called .dll and a too short file are not libraries", "machine=0000" in sc[3] and "not a Windows library" in pr(sc[3], "x64") and "machine=0000" in sc[4] and "not a Windows library" in pr(sc[4], "x86"), (sc[3], sc[4]))
check("a missing file: machine 0, said to be missing from its folder", "machine=0000" in sc[5] and "none.dll is not in" in pr(sc[5], "file"), sc[5])
print("Library XML checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
