"""Resize All and the right click commands on the Edit menu. Several objects chosen: the right click menu has Resize All, which gives the box round them eight handles; dragging the
bottom right handle scales every chosen object (two rectangles here, one of them is checked in the saved XML) as one undo step. The commands of the right click menu above Undo are
copied to the top of the Edit menu with a separator under them, and are gone (separator hidden) when nothing is chosen. Oracles: GRP / EDITCTX script output and the saved design.
Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Resize All checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:300])
def run(script):
    p = os.path.join(tmp, "s.txt"); open(p, "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", p], capture_output=True, text=True, timeout=300,
                       env=dict(os.environ, HOME=tmp, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.splitlines()
def rects(path):
    t = open(path, encoding="utf-8").read()
    return [tuple(float(v) for v in re.findall(r"[-\d.]+", a + " " + b)) for a, b in re.findall(r"<RECT[^>]*? a='([^']*)' b='([^']*)'", t)]
mk = "newdoc A4\ngridmm 2\ntool rect\nmouse down 101 63\nmouse move 143 95\nmouse up 143 95\ntool rect\nmouse down 101 123\nmouse move 143 155\nmouse up 143 155\n"
o = run(mk + "editctx\nselectall\nctxmenu 120 80\nctxclick Resize_All\ngrp\neditctx\n")
check("nothing chosen: no commands on the Edit menu, separator hidden", "EDITCTX sep=0 count=0" in o, o[:8])
check("the right click menu has Resize All with several objects chosen", any(l.startswith("CTX 0 Resize_All") for l in o), o[:12])
check("Resize All gives the group its handles", any(l.startswith("GRP on=1") for l in o), o[-4:])
check("the Edit menu has Resize All above Undo with its separator", "EDITCTX Resize All" in o and o[-1] == "EDITCTX sep=1 count=1", o[-3:])
o = run(mk + "ctxmenu 120 70\nEDITCTX\n")
check("one object: no Resize All", not any("Resize_All" in l for l in o), o[:6])
f1 = os.path.join(tmp, "r.dsn")
o = run(mk + f'selectall\nctxmenu 120 80\nctxclick Resize_All\ngrp\nmouse down 143 155\nmouse move 200 200\nmouse up 200 200\ngrp\nsave "{f1}"\nundo\ngrp\n')
g = [l for l in o if l.startswith("GRP")]
check("GRP lines", len(g) == 3, o[-8:])
if len(g) == 3:
    d = g[1].split()
    check("the box grew to the pointer (right and bottom now 200)", abs(float(d[4]) - 200) < 3 and abs(float(d[5]) - 200) < 3, g)
    check("the opposite corner stayed", abs(float(d[2]) - 100) < 1 and abs(float(d[3]) - 64) < 1, g)
    check("undo takes the whole resize back", abs(float(g[2].split()[4]) - 142) < 1, g)
R = rects(f1)
check("both rectangles saved", len(R) == 2, R)
if len(R) == 2:
    check("the second rectangle was scaled with the group (its right edge moved)", max(R[1][0], R[1][2]) > 150, R)
print("Resize All checks: %d run, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
