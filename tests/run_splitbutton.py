#!/usr/bin/env python3
"""TSplitButton (src/CSplitButton.pas): the main part clicks, the arrow part drops the menu (no keyboard: like a TSpeedButton it takes no focus). The driver (tests/drivers/splittest.pas) calls the control's own mouse and key
handlers; the oracle is the list of what each action must do: main press+release = 1 click and no drop down; press on main and release over the arrow = no click;
arrow press = OnDropDown, no click; disabled = nothing. Needs fpc with the LCL (build line in the README) and xvfb;
LAZ is the Lazarus folder (default /usr/lib/lazarus/3.0)."""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
LAZ = os.environ.get("LAZ", "/usr/lib/lazarus/3.0")
if shutil.which("fpc") is None or shutil.which("xvfb-run") is None or not os.path.isdir(LAZ + "/lcl/units/x86_64-linux/gtk2"):
    print("Split button checks skipped: need fpc, the LCL (gtk2) and xvfb"); sys.exit(0)
tmp = tempfile.mkdtemp()
r = subprocess.run(["fpc", "-Mobjfpc", "-Sh", "-dLCL", "-dLCLgtk2", "-Fu" + ROOT + "/src/comp", "-Fu%s/lcl/units/x86_64-linux/gtk2" % LAZ, "-Fu%s/lcl/units/x86_64-linux" % LAZ,
                    "-Fu%s/components/lazutils/lib/x86_64-linux" % LAZ, "-FU" + tmp, "-FE" + tmp, ROOT + "/tests/drivers/splittest.pas"], capture_output=True, text=True)
exe = os.path.join(tmp, "splittest")
if not os.path.exists(exe): print("FAIL build", r.stdout[-600:]); sys.exit(1)
o = subprocess.run(["xvfb-run", "-a", exe], capture_output=True, text=True, timeout=90, env=dict(os.environ, HOME=tmp)).stdout.split("\n")
fails = []; n = 0
def check(name, ok, d=""):
    global n; n += 1
    if not ok: fails.append(name); print("  FAIL", name, d)
want = ["MAIN clicks=1 drops=0", "AUTO1 checked=1 clicks=2", "AUTO2 checked=1", "AUTO3 checked=1", "AUTO4 checked=0", "SLIDEOFF clicks=1 drops=0", "ARROWNOMENU clicks=1 drops=2 down=0", "DDCMAIN dropclicks=0", "DDCARROW dropclicks=1 drops=3 clicks=2", "DISABLED clicks=2", "DONE"]
import re
m = [re.match(r"DROPPT (-?\d+),(-?\d+) w=(\d+) h=(\d+) arrow=(\d+)", l) for l in o]; m = [x for x in m if x]
if m:
    x, y, w, h, a = [int(v) for v in m[0].groups()]
    check("the arrow's menu opens at the left edge of the arrow part, 1 pixel below the button", (x, y) == (w - a, h + 1) and a > 0 and h > 0, m[0].group(0))
else: check("the arrow's menu position was reported", False, o[-4:])
for w in want: check(w, w in o, [l for l in o if l.split(" ")[0] == w.split(" ")[0]])
# Flat: no frame at rest (the pixels on the button's border are the background's), a frame when the mouse is over it; a normal button always has one
try:
    from PIL import Image
    shots = {}
    for tag, extra in (("n", []), ("f", ["flat"]), ("h", ["flat", "hot"]), ("c", ["color"]), ("t", ["colortrans"]), ("k", ["checked"]), ("i24", ["img24"]), ("i32", ["img32"])):
        bmp = os.path.join(tmp, tag + ".bmp"); subprocess.run(["xvfb-run", "-a", exe, bmp] + extra, capture_output=True, text=True, timeout=90, env=dict(os.environ, HOME=tmp)); shots[tag] = Image.open(bmp).convert("RGB")
    bg = lambda im: im.getpixel((2, 2)); edge = lambda im: [im.getpixel((x, 10 + 28 - 1)) for x in range(20, 100, 7)]   # the bottom border of the button (10,10,120,28)
    check("a checked flat button shows pressed in even at rest (a frame, where an unchecked flat one has none)", any(p != bg(shots["k"]) for p in edge(shots["k"])) and all(p == bg(shots["f"]) for p in edge(shots["f"])))
    from PIL import ImageChops
    main = lambda im: im.crop((12, 12, 100, 36))
    check("the checked main part is drawn pressed in: it differs from the normal unchecked button", ImageChops.difference(main(shots["k"]), main(shots["n"])).getbbox() is not None)
    check("a normal button has a frame (its bottom border differs from the background)", any(p != bg(shots["n"]) for p in edge(shots["n"])))
    check("a flat button at rest has none", all(p == bg(shots["f"]) for p in edge(shots["f"])), edge(shots["f"])[:3])
    check("a flat button with the mouse over it has the frame again", any(p != bg(shots["h"]) for p in edge(shots["h"])))
    def count(im, col): return sum(1 for x in range(im.width) for y in range(im.height) if im.getpixel((x, y)) == col)
    RED, BLUE = (255, 0, 0), (0, 0, 255)
    check("a transparent button (the default) paints nothing behind itself: its Color does not show", count(shots["t"], RED) == 0, count(shots["t"], RED))
    check("with Transparent off a flat button at rest shows its Color (filled red)", count(shots["c"], RED) > 1000, count(shots["c"], RED))
    check("ImageWidth 24 draws the 24 x 24 image: 576 red pixels and no blue", count(shots["i24"], RED) == 576 and count(shots["i24"], BLUE) == 0, (count(shots["i24"], RED), count(shots["i24"], BLUE)))
    # (the list is made by AddImages, which scales the first image to the other size, so the 32 pixel picture is red too: its size, 32 x 32 = 1024 pixels, shows which size was drawn)
    check("ImageWidth 32 draws the 32 x 32 size: 1024 pixels of the image", count(shots["i32"], BLUE) + count(shots["i32"], RED) == 1024, (count(shots["i32"], RED), count(shots["i32"], BLUE)))
except ImportError:
    print("  (Flat checks skipped: PIL is missing)")
print("%d checks, %d failed" % (n, len(fails))); sys.exit(1 if fails else 0)
