#!/usr/bin/env python3
"""Print window check boxes "Do not print symbol text" and "Do not print symbol properties" (printdialog nosymtext=0|1) on the test bitmap sink, A4 pages, 100 dpi.
A sheet with one Symbol Text and a line of ordinary text is printed with the box off and on. Oracle: with it off the symbol text's place on the page (80 mm, 60 mm; mm x 100 / 25.4 pixels)
has dark pixels; with it on that box is empty while every other pixel of the page is the same as the page with it off (only the symbol text goes); the dialog reports the choice.
Needs xvfb-run, the built program and Pillow."""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
try:
    from PIL import Image, ImageChops
except ImportError:
    Image = None
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or Image is None:
    print("Print symbol text checks skipped: need xvfb-run, the built program and Pillow"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:500])
def printed(flag):
    out = os.path.join(tmp, "o%s" % flag); os.makedirs(out, exist_ok=True)
    sp = os.path.join(tmp, "s%s.txt" % flag)
    open(sp, "w").write("newdoc A4\nregisterframe x all\ntool symboltext\nframeinfo tool\nframeact tool edSymbolText text REFERENCE NOTE\nclickmm 80 60\ntool text\nframeact tool edText text Visible\nclickmm 80 120\ntool select\n"
                        "printsink %s 100\nprintdialog scale=100 nosymtext=%s press=ok\n" % (out, flag))
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=dict(os.environ, HOME=tempfile.mkdtemp(dir=tmp)))
    return Image.open(os.path.join(out, "page_1.png")).convert("L"), r.stdout
a, oa = printed("0"); b, ob = printed("1")
k = 100 / 25.4; box = (int(80 * k) - 60, int(60 * k) - 60, int(80 * k) + 300, int(60 * k) + 60)
dark = lambda im: sum(1 for p in im.crop(box).tobytes() if p < 220)   # (symbol text is drawn in red: a light grey in L)
check("symbol text prints with the box off (dark pixels at its place)", dark(a) > 40, dark(a))
check("symbol text is left off with the box on (nothing at its place)", dark(b) == 0, dark(b))
diff = ImageChops.difference(a, b); diff.paste(0, box)
check("nothing else on the page changes (all other pixels equal)", diff.getbbox() is None, diff.getbbox())
check("the other text (Visible) is on both pages", sum(1 for p in a.crop((int(80 * k) - 20, int(120 * k) - 40, int(80 * k) + 200, int(120 * k) + 20)).tobytes() if p < 128) > 20)
check("dialog reports the choice", "nosymtext=0" in oa and "nosymtext=1" in ob, (oa[:300], ob[:300]))
# ---- "Do not print symbol properties": the fields (reference, name, values) of a placed symbol. Oracle: the design saved with every field hidden (show='0' in the file), printed with the box off.
import re, sqlite3
EX = os.environ.get("TC_EXAMPLES", "examples"); LIB = os.path.join(EX, "libraries", "gen_passive.TCLib")
if os.path.exists(LIB):
    c = sqlite3.connect(LIB); names = sorted([r[0] for r in c.execute("select Name from Name where Type=0")], key=str.lower); c.close()
    R0 = names.index("BUZZER")
    dsn = os.path.join(tmp, "sym.dsn")
    def printed2(opening, extra, tag):
        out = os.path.join(tmp, "p_" + tag); os.makedirs(out, exist_ok=True); sp = os.path.join(tmp, "p_%s.txt" % tag)
        open(sp, "w").write("\n".join(opening) + "\nprintsink %s 100\nprintdialog scale=100 %s press=ok\n" % (out, extra))
        subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=dict(os.environ, HOME=tempfile.mkdtemp(dir=tmp)))
        return Image.open(os.path.join(out, "page_1.png")).convert("L")
    mk = ["newdoc A4", "registerframe method all", "lib " + LIB, "libbegin %d" % R0, "frameact tool edRef text K7", "clickmm 140 60", "tool select",
          "tool symboltext", "frameinfo tool", "frameact tool edSymbolText text NOTE", "clickmm 80 60", "tool select", "savedocas " + dsn]
    open(os.path.join(tmp, "mk.txt"), "w").write("\n".join(mk) + "\n")
    subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "mk.txt")], capture_output=True, text=True, timeout=300, env=dict(os.environ, HOME=tempfile.mkdtemp(dir=tmp)))
    t = open(dsn, encoding="utf-8", errors="replace").read()
    hidden = re.sub(r"(<FIELD [^>]*?)show='1'", r"\1show='0'", t)
    check("the symbol has fields shown in the saved design (test premise)", hidden != t)
    hf = os.path.join(tmp, "hidden.dsn"); open(hf, "w", encoding="utf-8").write(hidden)
    P_off = printed2(['open "%s"' % dsn], "nosymfields=0 nosymtext=0", "off")
    P_fld = printed2(['open "%s"' % dsn], "nosymfields=1 nosymtext=0", "fld")
    P_ref = printed2(['open "%s"' % hf], "nosymfields=0 nosymtext=0", "ref")
    P_txt = printed2(['open "%s"' % dsn], "nosymfields=0 nosymtext=1", "txt")
    check("properties box on: the page equals the page of the design with every field hidden (and the symbol text object still prints)", ImageChops.difference(P_fld.crop((0, 0, P_fld.width, 780)), P_ref.crop((0, 0, P_ref.width, 780))).getbbox() is None, ImageChops.difference(P_fld.crop((0, 0, P_fld.width, 780)), P_ref.crop((0, 0, P_ref.width, 780))).getbbox())   # (the file name in the page footer differs)
    check("properties box on: the page differs from the full page (the fields were there)", ImageChops.difference(P_fld, P_off).getbbox() is not None)
    d2 = ImageChops.difference(P_txt, P_off); check("symbol text box on leaves the symbol's fields (differs from full page only at the symbol text)", d2.getbbox() is not None and d2.getbbox()[0] < int(100 / 25.4 * 120) and d2.getbbox()[2] < int(100 / 25.4 * 120), d2.getbbox())
print("print symbol text: %d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
