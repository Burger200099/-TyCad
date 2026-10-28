#!/usr/bin/env python3
"""The Parts tab of the library panel (QLibPanel: pdbtab script commands). Oracle: Python's sqlite3 on the sample parts file gives the rows (name, class, in order) and the icon
stored for each part (decoded with PIL: the colour of its middle pixel is what the list's image must show). A file that cannot be used leaves the list as it was and gives
the reason; opening another file replaces the list; selecting a row reports the part's index. Needs xvfb-run, PIL and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, sys, io, shutil, sqlite3, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, "..", "docs"))
import parts_seed
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
try:
    from PIL import Image
except ImportError:
    print("Parts tab checks skipped: need PIL"); sys.exit(0)
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Parts tab checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:400])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    return subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env).stdout.splitlines()
f = os.path.join(tmp, "a.TCParts"); parts_seed.build(f).close(); db = sqlite3.connect(f)
parts = db.execute("select p.PartID, p.Name, c.Name from Part p join PartClass c using(ClassID) order by lower(c.Name), lower(p.Name)").fetchall()
newer = os.path.join(tmp, "newer.TCParts"); shutil.copy(f, newer); c = sqlite3.connect(newer); c.execute("update FormatInfo set SchemaVersion=9"); c.commit(); c.close()
o = run(["pdbtab open " + f, "pdbtab rows", "pdbtab pixel 0", "pdbtab pixel 1", "pdbtab select 1", "pdbtab open " + newer, "pdbtab rows", "pdbtab select 0"])
op = [l for l in o if l.startswith("PDBTAB ok") or l.startswith("PDBTAB error")]
check("the file opens and the caption has the library's name", op and op[0] == "PDBTAB ok rows=%d caption=Parts Library: Sample parts" % len(parts), op)
rows = [l[7:].split("|") for l in o if l.startswith("PDBROW ")]
check("the list has a row per part in the library's order, name and class", [r[1:3] for r in rows[:len(parts)]] == [[nm, cl] for _, nm, cl in parts], rows)
check("every row has its own image, and the image list is 24x24 with one image per part", [r[3] for r in rows[:len(parts)]] == [str(i) for i in range(len(parts))] and any(l == "PDBTAB images=%d size=24x24" % len(parts) for l in o), [l for l in o if "images" in l])
ok = True; det = []
for i, (pid, nm, cl) in enumerate(parts):
    png = db.execute("select Png from PartGlyph where PartID=? and Size=24", (pid,)).fetchone()[0]
    want = "%02X%02X%02X" % Image.open(io.BytesIO(png)).convert("RGB").getpixel((12, 12))
    got = [l for l in o if l.startswith("PDBPIXEL %d " % i)]
    # (the image list stores the colour as BGR in a TColor: ColorToRGB gives $00BBGGRR)
    g = got[0].split()[2] if got else ""
    if g[4:6] + g[2:4] + g[0:2] != want: ok = False; det.append((g, want))
check("the picture in the list is the part's 24 pixel icon (the middle pixel has the colour stored in the PNG)", ok and len(det) == 0, det)
check("the two icons differ (the check can fail)", len({l.split()[2] for l in o if l.startswith("PDBPIXEL")}) == 2)
check("choosing a row reports the part's index", "PDBTAB selected=1" in o, [l for l in o if "selected" in l])
er = [l for l in o if l.startswith("PDBTAB error")]
check("a file that cannot be used is refused with its reason, and the list stays as it was", len(er) == 1 and "newer" in er[0] and len([l for l in o if l.startswith("PDBROW ")]) == 2 * len(parts), er)
print("%d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
