#!/usr/bin/env python3
"""The rulers round the drawing area (UViewRulers): a strip along the top and one down the left side of the view, in millimetres or inches (the sheet's units), measured from the
sheet's origin when it has one, following the zoom and the scroll. Show Rulers (the check box of the Position panel) and Show Viewport Rulers (the menu item) agree and are kept.
Oracle, all written again here: the pixel of a reading is (reading * 25.4 (inches) * 5 units per mm + origin - scroll) * zoom, the labelled marks are 1, 2 or 5 times a power of ten
and at least 60 pixels apart, the small marks are a tenth, a quarter or a fifth of the step; and the pixels of the form picture: a dark mark on the strip at the pixel of a labelled mark."""
import os, re, shutil, subprocess, sys, tempfile, math
import xml.etree.ElementTree as ET
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("View ruler checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:420])
def run(script, home=None):
    h = os.path.join(tmp, "home_" + home) if home else tempfile.mkdtemp(dir=tmp)
    os.makedirs(h, exist_ok=True)
    path = os.path.join(tmp, "s.txt"); open(path, "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=150,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.split("\n")
def info(o, nth=0):
    l = [x for x in o if x.startswith("RULERINFO")][nth]
    d = dict(re.findall(r"(\w+)=([^ ]+)", l))
    for k in ("top", "left", "view"): d[k] = tuple(int(v) for v in d[k].split(","))
    return d
def ticks(o, nth=0):
    """the RULERTICK lines that follow the nth RULERINFO: ([h...], [v...]) as (pos, value, major)"""
    idx = [i for i, x in enumerate(o) if x.startswith("RULERINFO")][nth]
    h, v = [], []
    for x in o[idx + 1:]:
        if not x.startswith("RULERTICK"): break
        _, ax, p, val, m = x.split()
        (h if ax == "h" else v).append((int(p), float(val), m == "1"))
    return h, v
def expect_pos(val, d, axis, edge_mm, inch):
    zoom = float(d["zoom"]); org = float(d["ox"] if axis == "h" else d["oy"])
    mm = val * (25.4 if inch else 1.0)
    return round((mm * 5 + edge_mm * 5 - org) * zoom)
def steps_ok(tk, inch):
    maj = [t for t in tk if t[2]]
    gaps = [b[0] - a[0] for a, b in zip(maj, maj[1:])]
    vg = [round(b[1] - a[1], 6) for a, b in zip(maj, maj[1:])]
    return gaps, vg

o = run('newdoc "ISO A4" landscape\nviewrulers 1\nrulerinfo\n')
d = info(o); h, v = ticks(o)
vr = [x for x in o if x.startswith("VIEWRULERS")][0]
check("rulers are shown to begin with (as TinyCAD): both strips, the menu tick, the check box and the saved option agree", "wanted=1 top=1 left=1 menu=1 box=1 saved=1" in vr, vr)
check("the top ruler is 18 pixels high (at the form's scale) and the left one as wide; the left one starts under the top one and the view starts after it",
      18 <= d["top"][3] <= 20 and d["left"][2] == d["top"][3] and d["left"][1] == d["top"][1] + d["top"][3] and d["view"][0] == d["left"][0] + d["left"][2] and d["view"][1] == d["left"][1], d)
check("the strips span the view: the top one is as wide as the view and the left one as high", d["top"][2] == d["left"][2] + d["view"][2] and d["left"][3] == d["view"][3], d)
ok = len(h) > 5 and len(v) > 5 and all(p == expect_pos(val, d, "h", 0, False) for p, val, m in h) and all(p == expect_pos(val, d, "v", 0, False) for p, val, m in v)
check("millimetres: every mark of both rulers is at the pixel its reading gives (zoom and scroll of the view)", ok, (d, h[:4], v[:4]))
gaps, vg = steps_ok(h, False)
step = vg[0]; mant = step / 10 ** math.floor(math.log10(step))
check("labelled marks are at least 60 pixels apart, equally spaced and 1, 2 or 5 times a power of ten", min(gaps) >= 60 and len(set(vg)) == 1 and round(mant, 6) in (1, 2, 5), (gaps, vg))
minor = sorted(set(round(b[1] - a[1], 6) for a, b in zip(h, h[1:])))
want_div = {1: 10, 2: 4, 5: 5}[round(mant, 6)]
check("small marks are a tenth, a quarter or a fifth of the step", len(minor) == 1 and abs(minor[0] * want_div - step) < 1e-6, (minor, step))
check("the marks cover the view from edge to edge", h[0][0] <= 0 and h[-1][0] >= d["view"][2] and v[0][0] <= 0 and v[-1][0] >= d["view"][3], (h[0], h[-1], v[0], v[-1], d["view"]))
# ---- inches, zoomed and with an origin
o = run('newdoc "ISO A4" landscape\noptions units=in\nsetorigin 20 10\nrulerinfo\nzoom 2.0\nrulerinfo\n')
d1 = info(o, 0); h1, v1 = ticks(o, 0); d2 = info(o, 1); h2, v2 = ticks(o, 1)
check("inches: the readings count inches from the sheet's origin and sit at the pixel the formula gives",
      d1["units"] == "1" and all(p == expect_pos(val, d1, "h", 20, True) for p, val, m in h1) and all(p == expect_pos(val, d1, "v", 10, True) for p, val, m in v1), (d1, h1[:3], v1[:3]))
check("the reading at the origin is 0: the mark labelled 0 is at the pixel of the origin", [p for p, val, m in h1 if abs(val) < 1e-9 and m] == [round((20 * 5 - float(d1["ox"])) * float(d1["zoom"]))], (d1, h1[:6]))
g1, vg1 = steps_ok(h1, True)
check("inch steps are 1, 2 or 5 times a power of ten of an inch, at least 60 pixels apart", min(g1) >= 60 and len(set(vg1)) == 1 and round(vg1[0] / 10 ** math.floor(math.log10(vg1[0])), 6) in (1, 2, 5), (g1, vg1))
check("after a zoom the marks are worked out again for the new zoom", d2["zoom"] != d1["zoom"] and all(p == expect_pos(val, d2, "h", 20, True) for p, val, m in h2) and h2 != h1, (d1["zoom"], d2["zoom"]))
# ---- hidden, menu and check box
o = run('newdoc "ISO A4" landscape\nviewrulers 0\nrulerinfo\nviewrulers 1\nviewrulers menu\nviewrulers menu\nviewrulers button\nviewrulers button\nrulerinfo\n')
vrs = [x for x in o if x.startswith("VIEWRULERS")]
check("hidden: both strips go and the menu tick, the check box and the option agree", "wanted=0 top=0 left=0 menu=0 box=0 saved=0" in vrs[0], vrs[0])
states = [x.split(" saved")[0] for x in vrs]
on = "VIEWRULERS wanted=1 top=1 left=1 menu=1 box=1"; off = "VIEWRULERS wanted=0 top=0 left=0 menu=0 box=0"
check("the menu item toggles the rulers and the check box follows; the check box toggles them and the menu tick follows (off, on, menu: off, menu: on, box: off, box: on)", states == [off, on, off, on, off, on], vrs)
dh = info(o, 0)
check("with the rulers hidden the view has the room: it starts where the left ruler did and is as much wider and higher as the strips were", dh["view"][0] == d["left"][0] and dh["view"][2] == d["view"][2] + d["left"][2] and dh["view"][3] == d["view"][3] + d["top"][3], (dh["view"], d["view"], d["top"], d["left"]))
# ---- kept for the next run
run('newdoc "ISO A4" landscape\nviewrulers 0\n', home="k")
o = run('newdoc "ISO A4" landscape\nrulerinfo\n', home="k")
check("hidden, they are hidden again next time (the choice is kept)", info(o)["visible"] == "00", info(o))
regs = [os.path.join(dp, f) for dp, _, fs in os.walk(os.path.join(tmp, "home_k")) for f in fs if f == "reg.xml"]
node = ET.parse(regs[0]).getroot()
for part in ("HKEY_CURRENT_USER", "SOFTWARE", "HPL Software", "TyCAD Electrical"): node = next(k for k in node.findall("Key") if k.get("Name") == part)
vals = {x.get("Name"): x.text for x in node.findall("Value")}
check("the registry holds it as ShowViewRulers = 0", vals.get("ShowViewRulers") == "0", vals)
# ---- the pixels
shot = os.path.join(tmp, "f.bmp")
o = run('newdoc "ISO A4" landscape\nviewrulers 1\nrulerinfo\nformshot %s\n' % shot)
d = info(o); h, v = ticks(o)
im = Image.open(shot).convert("RGB")
def dark(x, y):
    p = im.getpixel((x, y)); return sum(p) < 300
th = d["top"][3]
hm = [p for p, val, m in h if m and 0 <= p < d["view"][2] - 1]
vm = [p for p, val, m in v if m and 0 <= p < d["view"][3] - 1]
def vrun(x, y0, y1):
    """the longest run of dark pixels down column x between rows y0 and y1"""
    best = cur = 0
    for y in range(max(y0, 0), min(y1, im.height)):
        cur = cur + 1 if dark(x, y) else 0; best = max(best, cur)
    return best
def hrun(y, x0, x1):
    best = cur = 0
    for x in range(max(x0, 0), min(x1, im.width)):
        cur = cur + 1 if dark(x, y) else 0; best = max(best, cur)
    return best
# a labelled mark is a dark line of about 15 pixels across the strip; the picture is shifted as a whole by the window's menu bar on this display, so the
# shift is the one at which all the marks are lines: only that shift (along the strip) may fit
def fit(runs):
    return sorted(((sum(1 for r in runs(k) if r >= 12), k) for k in range(-40, 41)), reverse=True)
fh = fit(lambda dx: [vrun(d["top"][0] + th + p + dx, d["top"][1], d["top"][1] + d["top"][3] + 60) for p in hm])
# the whole form picture is a little squashed down the page on this display (the sheet itself is, too), so the vertical fit also tries a scale
def vfit():
    out = []
    for sc in [0.94 + i * 0.002 for i in range(41)]:
        for dy in range(-40, 41):
            n = sum(1 for p in vm if hrun(int(round((d["left"][1] + p) * sc)) + dy, d["left"][0] - 10, d["left"][0] + d["left"][2] + 10) >= 12)
            out.append((n, (round(sc, 3), dy)))
    out.sort(reverse=True)
    return out
fv = vfit()
bad = [] if (fh[0][0] == len(hm) and fv[0][0] == len(vm)) else [("h", fh[:3], len(hm)), ("v", fv[:3], len(vm))]
nmaj = len(hm) + len(vm)
bh2 = fh[1][0]; bv2 = max(n for n, (sc, dy) in fv if abs(dy - fv[0][1][1]) >= 8 and abs(sc - fv[0][1][0]) >= 0.02)
check("the picture of the form has a dark mark on the strip at the pixel of every labelled mark, both rulers (shifted as a whole by the menu bar on this display, and no other shift fits)", nmaj > 6 and not bad and bh2 < len(hm) * 0.6 and bv2 < len(vm) * 0.6, (nmaj, bad, fh[:3], fv[:3]))
print("View ruler checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
