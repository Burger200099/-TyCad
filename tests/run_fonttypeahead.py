#!/usr/bin/env python3
"""Type-ahead of the font drop-down (TFontNameCombo), on the real program under Xvfb. The box is given a fixed list (Arial, Cambria, Comic Sans MS, Consolas,
Courier, Courier New, Verdana) and keys with their times. Oracle: the old font drop-downs' rule, worked out here by hand - a key within 1000 ms of the one
before adds to what was typed (C, O, U look for "COU"), a key after a longer pause is looked for alone; the first name starting with it (any case) is chosen.
Needs the built program and xvfb."""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Font type-ahead checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:400])
def type_(keys):
    f = os.path.join(tmp, "s.txt"); open(f, "w").write("newdoc \"ISO A4\" landscape\nfonttype " + " ".join(keys) + "\n")
    h = tempfile.mkdtemp(dir=tmp)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=280,
                       env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    for l in r.stdout.split("\n"):
        if l.startswith("FONTTYPE "): return l[9:].strip().rstrip("|").split("|")
LIST = ["Arial", "Cambria", "Comic Sans MS", "Consolas", "Courier", "Courier New", "Verdana"]
def model(keys):
    """the rule, written out again: (ms, char) pairs -> the choice after each"""
    cur = None; typed = ""; last = None; out = []
    for ms, ch in keys:
        ch = " " if ch == "_" else ch
        typed = typed + ch if (typed and last is not None and 0 <= ms - last <= 1000) else ch
        last = ms
        def find(p): return next((n for n in LIST if n.lower().startswith(p.lower())), None)
        hit = find(typed)
        if hit is None and len(typed) > 1:
            typed = ch; hit = find(typed)
        if hit is not None: cur = hit
        out.append(cur or "-")
    return out
def parse(keys): return [(int(k.split(":")[0]), k.split(":", 1)[1]) for k in keys]
CASES = {
    "C O U quickly: COU": ["0:C", "500:O", "900:U"],
    "C then A after a pause: A alone (not CA)": ["0:C", "2000:A"],
    "C then A quickly: CA": ["0:C", "500:A"],
    "Courier New typed with short gaps": ["0:C", "200:O", "400:U", "600:R", "800:I", "1000:E", "1200:R", "1400:_", "1600:N"],
    "the gap is measured from the last key, not the first": ["0:C", "900:O", "1800:U"],
    "exactly 1000 ms still counts": ["0:C", "1000:O"],
    "1001 ms starts again": ["0:C", "1001:O"],
    "a letter with no font keeps the choice": ["0:V", "100:Q", "2000:Z"],
    "lower case": ["0:c", "100:o", "200:u"],
}
for name, keys in CASES.items():
    got = type_(keys); want = model(parse(keys))
    check(name, got == want, (got, want))
check("COU really finds Courier (not the first C)", type_(CASES["C O U quickly: COU"])[-1] == "Courier")
check("C then A after a pause finds Arial", type_(CASES["C then A after a pause: A alone (not CA)"])[-1] == "Arial")
check("Courier New typed out", type_(CASES["Courier New typed with short gaps"])[-1] == "Courier New")
print("font type-ahead checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
