"""Colors (TinyCAD's Options > Colors, the Define colors dialog): ten colors listed (the background of the drawing, wires, buses, junctions, no-connect marks, pins, power symbols and the
three of a note), a button to change each, Defaults, OK and Cancel; every design has its own colors, and the ones the user changes are kept for new designs. The real dialog is filled in
and OK'd by script; what the program then holds and draws is compared with an independent statement of the rules:
  - TinyCAD's own default colors (CUserColor::Init) for all twelve, and what a new design starts with
  - applying: every sheet of the open design takes the colors; the design is not marked as changed (as in TinyCAD)
  - keeping: of the ten listed, only those that differ from the factory colors are kept for new designs (put back to the factory color, one stops being kept), net labels and the pins of
    power symbols are never kept; Defaults puts all twelve back to the factory colors and forgets the ten
  - after a restart: the kept colors are what a new design starts with (a design read from a file takes what its file says, and the factory colors where it says nothing); a design that is
    saved with its colors comes back with them
  - what is drawn: the paper takes the background color, and each kind of object is drawn in its color (counted as pixels of exactly that color where the object is, none of the old color);
    a note and a label made after the change start with the note and label colors
Needs the built program and ImageMagick."""
import os, random, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or shutil.which("convert") is None:
    print("Color checks skipped: need xvfb-run, ImageMagick and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:420])
def run(script, home=None, timeout=120):
    h = os.path.join(tmp, "home_" + home) if home else tempfile.mkdtemp(dir=tmp)
    os.makedirs(h, exist_ok=True)
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n"), r.returncode, r.stderr
# ---------- TinyCAD's colors (CUserColor::Init), as RRGGBB, by id ----------
FACTORY = {1: "0000FF", 2: "FF0000", 3: "000000", 4: "000000", 5: "008020", 6: "000000", 7: "C04040", 8: "208020", 9: "FFFFFF", 10: "FFFFAF", 11: "0000FF", 12: "0000FF"}
NAMES = {1: "wire", 2: "bus", 3: "junction", 4: "noconnect", 5: "label", 6: "power", 7: "pin", 8: "hiddenpin", 9: "background", 10: "notefill", 11: "noteline", 12: "notetext"}
LISTED = [1, 2, 3, 4, 6, 7, 9, 10, 11, 12]            # the ten the dialog lists
def info(lines):
    sheets = []; kept = new = None
    for l in lines:
        t = l.split()
        if l.startswith("COLORSINFO sheet"): sheets.append({int(k): v for k, v in (x.split("=") for x in t[3:])})
        elif l.startswith("COLORSINFO kept"): kept = {int(k): v for k, v in (x.split("=") for x in t[2:])}
        elif l.startswith("COLORSINFO newdesign"): new = {int(k): v for k, v in (x.split("=") for x in t[2:])}
    return sheets, kept, new
def bgr(rgb): return rgb[4:6] + rgb[2:4] + rgb[0:2]
sample = next(p for p in sorted(os.path.join(dp, f) for dp, _, fs in os.walk(EX) for f in fs if f.endswith(".dsn")) if os.path.basename(p) == "PSU.dsn")
work = os.path.join(tmp, "work"); os.makedirs(work); psu = os.path.join(work, "PSU.dsn"); shutil.copy(sample, psu)
# ---------- the defaults ----------
o, rc, err = run(f'open "{psu}"\ncolorsinfo\n')
sheets, kept, new = info(o)
check("the program starts", rc == 0 and not any(l.startswith("ERROR") for l in o), err[-200:])
check("a design starts with TinyCAD's colors: wires blue, buses red, junctions and no-connects and power black, labels (0,128,32), pins (192,64,64), hidden pins (32,128,32), white paper, notes light yellow with blue line and text", sheets[0] == FACTORY, str(sheets[0]))
check("nothing is kept for new designs to begin with, and a new design starts with the same", all(v == "-" for v in kept.values()) and new == FACTORY, f"{kept} {new}")
# ---------- applying: every sheet, not marked as changed, what is kept ----------
rnd = random.Random(8)
def rand_rgb(): return "%02X%02X%02X" % (rnd.randrange(256), rnd.randrange(256), rnd.randrange(256))
bad = 0; first = None
for k in range(12):
    chosen = {i: rand_rgb() for i in rnd.sample(LISTED, rnd.choice([1, 2, 4, 10]))}
    if rnd.random() < 0.4:                       # put one back to the factory color: it must not be kept
        i = rnd.choice(LISTED); chosen[i] = FACTORY[i]
    args = " ".join(f"{NAMES[i]}={v}" for i, v in chosen.items())
    o, rc, err = run(f'open "{psu}"\naddsheet\ndocs\ncolors {args}\ncolorsinfo\ndocs\n')
    sheets, kept, new = info(o); dl = [l for l in o if l.startswith("DOCS ")]; docs = dl[-1]
    want = {i: chosen.get(i, FACTORY[i]) for i in FACTORY}
    want_kept = {i: (chosen[i] if (i in chosen and i in LISTED and chosen[i] != FACTORY[i]) else "-") for i in FACTORY}
    ok = len(sheets) == 2 and sheets[0] == want and sheets[1] == want and kept == want_kept and new == want and dl[0] == dl[1]
    if not ok: bad += 1; first = first or (chosen, sheets, kept, docs)
check("12 random choices: both sheets of the design take every color, the new-design colors follow, only the listed colors that differ from the factory's are kept, the design's changed mark is as it was (applying colors does not change it)", bad == 0, str(first))
# defaults: all twelve back to the factory colors, the ten forgotten
o, rc, err = run(f'open "{psu}"\ncolors wire=123456 bus=654321 label=ABCDEF\ncolorsinfo\ncolors reset\ncolorsinfo\n')
a = info(o[:o.index("COLORS applied") + 1] + [l for l in o[o.index("COLORS applied") + 1:] if False]); allinfo = [l for l in o if l.startswith("COLORSINFO")]
first_sheet = {int(k): v for k, v in (x.split("=") for x in allinfo[0].split()[3:])}; last_sheet = {int(k): v for k, v in (x.split("=") for x in allinfo[3].split()[3:])}; last_kept = {int(k): v for k, v in (x.split("=") for x in allinfo[4].split()[2:])}
check("Defaults puts all twelve colors back to the factory colors (even the label color, set here as a program could but the dialog cannot) and everything kept is forgotten", first_sheet[1] == "123456" and first_sheet[5] == "ABCDEF" and last_sheet == FACTORY and all(v == "-" for v in last_kept.values()), f"{first_sheet} {last_sheet} {last_kept}")
# net labels and the pins of power symbols are carried, not kept
o, rc, err = run(f'open "{psu}"\ncolors label=AB1234 hiddenpin=3456AB wire=00AA00\ncolorsinfo\n')
s, kp, nw = info(o)
check("the two colors the dialog does not list (labels, pins of power symbols) are carried through if something sets them, but never kept for new designs", s[0][5] == "AB1234" and s[0][8] == "3456AB" and kp[5] == "-" and kp[8] == "-" and kp[1] == "00AA00" and nw[5] == FACTORY[5], f"{s[0]} {kp} {nw}")
o, rc, err = run(f'open "{psu}"\ncolors wire=00AA00 bus=AA00AA\ncolors wire=0000FF\ncolorsinfo\n')
s, kp, nw = info(o)
check("a color put back to the factory's stops being kept, and the others stay", kp[1] == "-" and kp[2] == "AA00AA" and nw[1] == "0000FF" and nw[2] == "AA00AA", f"{kp} {nw}")
# ---------- after a restart, and in the file ----------
o, rc, err = run(f'open "{psu}"\ncolors wire=00AA00 background=FFFFD0 pin=7700BB notefill=DDEEFF\n', home="keep")
o, rc, err = run(f'newdoc "ISO A4" landscape\ncolorsinfo\nopen "{psu}"\ncolorsinfo\n', home="keep")
sheets, kept, new = info(o)
expect_new = dict(FACTORY); expect_new.update({1: "00AA00", 9: "FFFFD0", 7: "7700BB", 10: "DDEEFF"})
check("after a restart a new design starts with the colors that were kept", sheets[0] == expect_new and kept == {i: (expect_new[i] if i in (1, 9, 7, 10) else "-") for i in FACTORY}, f"{sheets[0]} {kept}")
check("a design read from a file that says nothing of colors has the factory colors (the kept ones are what a NEW design starts with, they do not recolor a drawing that was made before)", sheets[1] == FACTORY, str(sheets[1]))
o, rc, err = run(f'open "{psu}"\ncolors wire=00AA00 background=FFFFD0 notetext=112233\nsave "{work}/colored.dsn"\n')
r = ET.parse(f"{work}/colored.dsn").getroot(); sh = r.findall("TinyCAD")[0] if r.tag == "TinyCADSheets" else r
tags = {e.tag: (e.text or "").strip() for e in sh.iter() if e.tag.startswith("COLOR_")}
check("saved, the design holds its colors in the file (COLOR_WIRE, COLOR_BACKGROUND, COLOR_NOTETEXT_TEXT ... as TinyCAD names them, in the file's own byte order)", tags.get("COLOR_WIRE") == bgr("00AA00") and tags.get("COLOR_BACKGROUND") == bgr("FFFFD0") and tags.get("COLOR_NOTETEXT_TEXT") == bgr("112233"), str(tags))
o, rc, err = run(f'open "{work}/colored.dsn"\ncolorsinfo\n')
s, kp, nw = info(o)
want = dict(FACTORY); want.update({1: "00AA00", 9: "FFFFD0", 12: "112233"})
check("and it comes back with them when opened", s[0] == want, str(s[0]))
# ---------- what is drawn ----------
raw = open(sample, encoding="utf-8", errors="replace").read()
objs = ('<WIRE a="20,12" b="60,12" />\r\n<BUS a="20,20" b="60,20" />\r\n<JUNCTION pos="30,28" />\r\n<NOCONNECT pos="45,28" />\r\n'
        '<POWER pos="60,38" direction="3" which="0">VCC</POWER>\r\n<WIRE a="20,15" b="60,15" style="0" />\r\n')
j = raw.index("<SYMBOL ")
paint = os.path.join(work, "paint.dsn"); open(paint, "w", encoding="utf-8").write(raw[:j] + objs + raw[j:])
def count_color(img, x1, y1, x2, y2, rgb):
    x1, x2 = sorted((x1, x2)); y1, y2 = sorted((y1, y2))
    out = subprocess.run(["convert", img, "-crop", f"{max(1, x2 - x1)}x{max(1, y2 - y1)}+{x1}+{y1}", "+repage", "-depth", "8", "txt:-"], capture_output=True, text=True).stdout
    return out.count("#" + rgb.upper())
def px(img, x, y):
    return subprocess.run(["convert", img, "-crop", "1x1+%d+%d" % (x, y), "-depth", "8", "-format", "%[hex:u.p{0,0}]", "info:"], capture_output=True, text=True).stdout.strip().upper()
REGIONS = {1: (18, 11, 62, 13.2), 2: (18, 18.5, 62, 21.5), 3: (28.5, 26.5, 31.5, 29.5), 4: (43.5, 26.5, 46.5, 29.5), 6: (52, 30, 70, 42), 13: (18, 14.4, 62, 15.6)}
vp_lines = "".join(f"viewpoint {a} {b}\nviewpoint {c} {d}\n" for (a, b, c, d) in REGIONS.values()) + "viewpoint 5 5\nviewpoint 15 140\n"
def render(args, name):
    o, rc, err = run(f'open "{paint}"\n{("colors " + args) if args else ""}\n{vp_lines}shot {tmp}/{name}.bmp\n')
    vp = [tuple(int(v) for v in l.split()[1:]) for l in o if l.startswith("VIEWPOINT")]
    return f"{tmp}/{name}.bmp", vp
img0, vp0 = render("", "plain")
NEWC = {1: "00B000", 2: "FF8800", 3: "CC00CC", 4: "00CCCC", 6: "880000", 9: "FFFFC8", 7: "7700BB"}
img1, vp1 = render(" ".join(f"{NAMES[i]}={v}" for i, v in NEWC.items()), "recolored")
bad_old = []; bad_new = []
PXMM = (vp0[2 * 4 + 1][0] - vp0[2 * 4][0]) / 18.0           # pixels per mm on the screen (the window's size decides it): marks are fewer on a smaller view
SCALE = min(1.0, PXMM / 3.9)
for n, (rid, reg) in enumerate(REGIONS.items()):
    if rid == 13: continue
    (xa, ya), (xb, yb) = vp0[2 * n], vp0[2 * n + 1]
    before_old = count_color(img0, xa, ya, xb, yb, FACTORY[rid]) if FACTORY[rid] != "000000" or rid in (3, 4, 6) else 0
    (xa1, ya1), (xb1, yb1) = vp1[2 * n], vp1[2 * n + 1]
    after_new = count_color(img1, xa1, ya1, xb1, yb1, NEWC[rid]); after_old = count_color(img1, xa1, ya1, xb1, yb1, FACTORY[rid])
    min_n = 3 if rid in (3, 4) else max(4, int(12 * SCALE))
    if before_old < min_n: bad_old.append((NAMES[rid], "default", before_old))
    if after_new < min_n or after_old != 0: bad_new.append((NAMES[rid], after_new, after_old))
check("drawn with the factory colors, each kind of object (wire and bus drawn in the default style, junction, no-connect mark, power symbol) shows marks of its factory color where it is", not bad_old, str(bad_old))
check("recolored, each is drawn in its new color there, and nothing of the old color is left where it is", not bad_new, str(bad_new))
n13 = list(REGIONS).index(13); (xa, ya), (xb, yb) = vp0[2 * n13], vp0[2 * n13 + 1]; (xc, yc), (xd, yd) = vp1[2 * n13], vp1[2 * n13 + 1]
styled = (count_color(img0, xa, ya, xb, yb, "000000"), count_color(img1, xc, yc, xd, yd, "000000"), count_color(img1, xc, yc, xd, yd, NEWC[1]))
check("a wire that carries its own line style (black here) is not recolored: it is black before and after, and never the new wire color", styled[0] >= 12 and styled[1] >= 12 and styled[2] == 0, str(styled))
bgp = [px(img0, *vp0[-2]), px(img1, *vp1[-2])]
check("the paper takes the background color: white at first, then the chosen one", bgp[0] == "FFFFFF" and bgp[1] == "FFFFC8", str(bgp))
# the pins of the symbols (PSU has many): their factory color is gone from the whole sheet and the chosen one is there
allp0 = count_color(img0, 0, 0, 1235, 619, FACTORY[7]); allp1 = count_color(img1, 0, 0, 1235, 619, FACTORY[7]); newp = count_color(img1, 0, 0, 1235, 619, NEWC[7])
check("the pins of the placed symbols change color too: the factory pin color is on the sheet at first and none of it afterwards, the new one is", allp0 > 30 and allp1 == 0 and newp > 30, f"{allp0} {allp1} {newp}")
# a note and a label made after the change start with the note and label colors
o, rc, err = run(f'newdoc "ISO A4" landscape\ncolors notefill=FF00FF noteline=00FFFF notetext=FF8000 label=00FF00\ntool note\nmouse down 60 40\nmouse move 100 70\nmouse up 100 70\nsetprop text "A note"\ntool label\nmouse down 120 80\nsetprop text "LBL"\nsave "{work}/new_objects.dsn"\nviewpoint 98 68\nshot {tmp}/note.bmp\n')
r = ET.parse(f"{work}/new_objects.dsn").getroot(); sh = r.findall("TinyCAD")[0] if r.tag == "TinyCADSheets" else r
nt = sh.find("NOTE_TEXT"); lb = sh.find("LABEL")
fill = [f for f in sh.findall("FILL") if f.get("id") == nt.get("fill")][0].findtext("COLOR").strip(); line = [f for f in sh.findall("STYLE") if f.get("id") == nt.get("style")][0].findtext("COLOR").strip()
check("a note made after the change starts with the note colors (text FF8000, fill FF00FF, line 00FFFF) and a label with the label color (00FF00)", nt.get("color") == bgr("FF8000") and fill == bgr("FF00FF") and line == bgr("00FFFF") and lb.get("color") == bgr("00FF00"), f"{nt.attrib} {fill} {line} {lb.attrib}")
vpn = [tuple(int(v) for v in l.split()[1:]) for l in o if l.startswith("VIEWPOINT")][0]
check("and the note is drawn with that fill (a pixel inside it is exactly that color)", px(f"{tmp}/note.bmp", *vpn) == "FF00FF", px(f"{tmp}/note.bmp", *vpn))
# the notes and labels that were there are left as they were
o, rc, err = run(f'open "{work}/new_objects.dsn"\ncolors notefill=111111 label=222222\nsave "{work}/after.dsn"\n')
r = ET.parse(f"{work}/after.dsn").getroot(); sh2 = r.findall("TinyCAD")[0] if r.tag == "TinyCADSheets" else r
check("changing the colors afterwards does not recolor a note or label that exists: they keep the colors they were made with", sh2.find("NOTE_TEXT").get("color") == nt.get("color") and sh2.find("LABEL").get("color") == lb.get("color"), f"{sh2.find('NOTE_TEXT').attrib}")

# the dialog's rows are made in the form designer: a name, a swatch and a Change button for each of the ten listed colors, and the color chooser is the form's ColorDlg
o, rc, err = run('newdoc "ISO A4" landscape\ncolorcontrols\n')
ctl = {}
for l in o:
    if l.startswith("COLORCTL "):
        t = l.split(" ", 3); ctl.setdefault(t[1], []).append((t[2], dict(re.findall(r"(\w+)=(.*?)(?= \w+=|$)", t[3]))))
want = {9: ("Background", "Background"), 1: ("Wires", "Wires"), 2: ("Buses", "Buses"), 3: ("Junctions", "Junctions"), 4: ("NoConnect", "No-connect marks"), 7: ("Pins", "Pins"),
        6: ("Power", "Power symbols"), 10: ("NoteFill", "Note background"), 11: ("NoteLine", "Note border"), 12: ("NoteText", "Note text")}
check("colors dialog: ten labels, ten swatches, ten Change buttons and the Defaults button", [len(ctl.get(k, [])) for k in ("TLabel", "TPanel", "TButton")] == [10, 10, 11], {k: len(v) for k, v in ctl.items()})
byname = {n: a for k in ctl for n, a in ctl[k]}
for cid, (nm, cap) in want.items():
    lb, pn, bt = byname.get("lbl" + nm), byname.get("pnl" + nm), byname.get("btn" + nm)
    check("colors dialog row %s: design-time label, swatch and button, in the same row" % nm, bool(lb and pn and bt and lb["caption"] == cap and pn["tag"] == str(cid) and bt["tag"] == str(cid) and bt["caption"] == "Change..."
          and bt["click"] == "1" and abs(int(pn["top"]) - int(bt["top"])) <= 1 and int(lb["left"]) < int(pn["left"]) < int(bt["left"]) and pn["parent"] == "pnlColors"), (nm, lb, pn, bt))
check("colors dialog: the shared TColorDialog (DlgColor of the shared controls form) is the one it uses", any(l.startswith("COLORDLG TColorDialog DlgColor owner=frmSharedControls") for l in o), [l for l in o if "COLORDLG" in l])
print(f"colors: {checks} checks, {len(fails)} failures")
print("\nCOLOR CHECKS PASSED" if not fails else f"\nCOLOR CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
