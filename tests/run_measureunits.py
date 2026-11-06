"""Measure A-B ruler units: mm, in (dec), in (frac: whole inches and 32nds, reduced), ft (3'-4 15/32"). Oracle: MEASURETEXT script output. (The earlier checks are in run_measurescale.py.) Needs xvfb-run and the built program.

 makes the ruler level or plumb (towards the axis the pointer is nearer to), and the scale: the drop down of the button (Scale: _x, Set Scale, Reset Scale),
Set Scale draws a ruler over a known distance (the ruler is not kept) and the scale is that distance / the drawn one; rulers drawn afterwards carry it, it is saved with the sheet
(OPTIONS MEASURESCALE, and scale= on each ruler; none in the file: 1). Oracles: the saved XML, MEASURE / MEASUREMENU script output. Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Measure scale checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
def meas(path):
    t = open(path, encoding="utf-8").read()
    return re.findall(r"<MEASURE ([^>]*)>", t), t
def pt(attrs, k):
    m = re.search(k + r"='([^']*)'", attrs); return [float(v) for v in re.findall(r"[-\d.]+", m.group(1))] if m else None
draw = lambda a, b: f"tool measure\nmouse down {a[0]} {a[1]}\nmouse move {b[0]} {b[1]}\nmouse up {b[0]} {b[1]}\n"
cases = [("Millimetres", None, "40.0 mm"), ("Inches (decimal)", None, "1.575 in"), ("Inches (fractional)", None, '1 9/16"'), ("Feet and inches", None, "0'-1 9/16\""),
         ("Inches (decimal)", 2000, "78.740 in"), ("Inches (fractional)", 2000, '78 3/4"'), ("Feet and inches", 2000, "6'-6 3/4\""),
         ("Inches (fractional)", 508, '20"'), ("Feet and inches", 3048, "10'-0\"")]
for mode, sc, want in cases:
    pre = f"measure setscale {sc}\n" + draw((100, 100), (140, 100)) if sc else ""
    if sc == 508: pre = f"measure setscale 508\n" + draw((100, 100), (140, 100))
    o = run("newdoc A4\ngridmm 2\n" + pre + draw((100, 150), (140, 150)) + f'setprop measure.unit "{mode}"\nmeasure text\n')
    t = [l[len("MEASURETEXT "):] for l in o if l.startswith("MEASURETEXT ")]
    if sc == 508 or sc == 3048: want = want
    check("%s (scale %s) -> %s" % (mode, sc, want), t and t[0] == want, (t, o[-3:]))
print("Measure unit checks: %d run, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
