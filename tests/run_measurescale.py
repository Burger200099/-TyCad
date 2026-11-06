"""Measure A-B ruler: Shift makes the ruler level or plumb (towards the axis the pointer is nearer to), and the scale: the drop down of the button (Scale: _x, Set Scale, Reset Scale),
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
f1 = os.path.join(tmp, "a.dsn")
o = run(f"newdoc A4\ngridmm 2\nmeasure popup\n" + draw((100, 100), (140, 110)) + draw((100, 150), (110, 190)) + 'measure shift on\n' + draw((100, 60), (140, 66)) + draw((160, 60), (166, 100)) + f'save "{f1}"\n')
check("the drop down shows Scale: 1x, Set Scale on, Reset Scale off", any(l.startswith("MEASUREMENU Scale: 1x") and "set=1 reset=0" in l for l in o), o[:6])
M, t = meas(f1)
check("four rulers saved", len(M) == 4, len(M))
if len(M) == 4:
    a, b = pt(M[0], "a"), pt(M[0], "b")
    check("without Shift the ruler goes where the pointer is", abs(b[1] - a[1]) > 5, (a, b))
    a, b = pt(M[2], "a"), pt(M[2], "b")
    check("Shift, pointer nearer the horizontal: level", abs(b[1] - a[1]) < 1e-6 and abs(b[0] - a[0]) > 10, (a, b))
    a, b = pt(M[3], "a"), pt(M[3], "b")
    check("Shift, pointer nearer the vertical: plumb", abs(b[0] - a[0]) < 1e-6 and abs(b[1] - a[1]) > 10, (a, b))
    check("no scale written when it is 1", "scale=" not in M[0] and "MEASURESCALE" not in t, M[0])
f2 = os.path.join(tmp, "b.dsn")
o = run(f"newdoc A4\ngridmm 2\nmeasure setscale 80\n" + draw((100, 100), (140, 100)) + f'measure info\n' + draw((100, 150), (120, 150)) + f'save "{f2}"\nmeasure popup\n')
mi = [l for l in o if l.startswith("MEASURE scale=")]
check("Set Scale: the scale is actual / drawn (80 mm over 40 mm = 2)", mi and mi[-1].startswith("MEASURE scale=2 "), mi)
check("Set Scale ends the tool", mi and "tool=0" in mi[-1], mi)
check("the drop down shows Scale: 2x with Reset Scale on", any(l.startswith("MEASUREMENU Scale: 2x") and "reset=1" in l for l in o), o[-3:])
M, t = meas(f2)
check("the calibration ruler is not kept, the next one is, with the scale", len(M) == 1 and pt(M[0], "a") is not None and "scale='2.00000'" in M[0], M)
check("the sheet's scale is saved", "<MEASURESCALE>2.00000</MEASURESCALE>" in t, re.findall(r"<MEASURESCALE>.*?</", t))
o = run(f'open "{f2}"\nmeasure popup\nmeasure reset\nmeasure popup\n')
check("reloaded: Scale 2x; Reset Scale: 1x", any(l.startswith("MEASUREMENU Scale: 2x") for l in o) and any(l.startswith("MEASUREMENU Scale: 1x") for l in o), o[-6:])
print("Measure scale checks: %d run, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
