#!/usr/bin/env python3
"""Translation (src/UStrings.pas, languages/schematic.pot, tools/mkpo.py, LCLTranslator in schematic.lpr).
Checks:
  - the template is up to date, is a valid .po file (msgfmt), and every resourcestring of UStrings.pas is in it and is used by the program
  - the compiler's own list of the strings (lib/UStrings.rsj) is the one mkpo.py read, name for name and text for text
  - every Format template keeps its % codes in step with the code that uses it (the same number of %s / %d as arguments in the call)
  - the program (needs xvfb-run and the built program): English without a language, and with a made-up language (every text in [brackets] with accents) the captions and hints of the main
    window and of frames, a status text and a text with a value filled in are the translated ones; a language with no file stays English
Oracles: the English text is read from the .lfm / UStrings.pas files, the made-up translation is worked out here (mkpo.pseudo), and the program's answers come from the running window."""
import os, re, sys, json, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import mkpo
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name); print("  FAIL", name, str(detail)[:600])

# --- the template and the strings
pot = os.path.join(ROOT, "languages", "schematic.pot")
check("the template exists", os.path.exists(pot))
r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "mkpo.py"), "--check"], capture_output=True, text=True)
check("the template is up to date (python3 tools/mkpo.py makes it)", r.returncode == 0, r.stdout)
if shutil.which("msgfmt"):
    r = subprocess.run(["msgfmt", "-c", "--check-format", "-o", os.devnull, pot], capture_output=True, text=True)
    bad = [l for l in r.stderr.splitlines() if "warning" not in l]
    check("msgfmt accepts the template", r.returncode == 0 and not bad, r.stderr[:400])
rs = mkpo.resource_strings()
check("UStrings.pas holds several hundred strings", len(rs) > 500, len(rs))
names = [i for i, t in rs]
check("no resourcestring name is used twice", len(names) == len(set(names)))
text = open(pot, encoding="utf-8").read()
ids = set(re.findall(r"^#: (\S+)$", text, re.M))
check("every resourcestring is in the template", all(i in ids for i, t in rs), [i for i, t in rs if i not in ids][:5])
src_all = ""
for d, _, fs in os.walk(os.path.join(ROOT, "src")):
    for f in fs:
        if f.endswith(".pas") and f != "UStrings.pas":
            src_all += open(os.path.join(d, f), encoding="utf-8", errors="replace").read() + "\n"
src_all += open(os.path.join(ROOT, "schematic.lpr"), encoding="utf-8").read()
unused = [i for i, t in rs if not re.search(r"\b" + i.split(".")[1] + r"\b", src_all, re.I)]
check("every resourcestring is used by the program", not unused, unused[:8])
rsj = os.path.join(ROOT, "lib", "UStrings.rsj")
if os.path.exists(rsj):
    data = json.load(open(rsj, encoding="utf-8"))
    comp = {e["name"]: e["value"] for e in data["strings"]}
    mine = {i: t for i, t in rs}
    check("the compiler's list of strings (ustrings.rsj) is the one read from the source", comp == mine, (len(comp), len(mine), [k for k in comp if comp[k] != mine.get(k)][:3]))
# a template and its call: the number of %s / %d must be the number of values given to Format
bad = []
for m in re.finditer(r"Format\((rs\w+),\s*\[([^\]]*)\]\)", src_all):
    t = dict(rs).get("ustrings." + m.group(1).lower())
    if t is None: continue
    n_t = len(re.findall(r"%(?!%)[sd]|%\d+:[sd]", t))
    depth = 0; n_a = 1 if m.group(2).strip() else 0
    for ch in m.group(2):
        if ch in "([": depth += 1
        elif ch in ")]": depth -= 1
        elif ch == "," and depth == 0: n_a += 1
    if n_t != n_a: bad.append((m.group(1), n_t, n_a))
check("a Format call gives as many values as its text has %s / %d", not bad, bad[:5])

# --- the program
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Translation checks of the program skipped: need xvfb-run and the built program")
    print("translation: %d checks, %d failed" % (checks, len(fails))); sys.exit(1 if fails else 0)
tmp = tempfile.mkdtemp()
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
os.makedirs(os.path.join(tmp, "languages")); home = os.path.join(tmp, "home"); os.makedirs(home)
subprocess.run([sys.executable, os.path.join(ROOT, "tools", "mkpo.py"), "--pseudo", os.path.join(tmp, "languages", "schematic.qps.po")], check=True, capture_output=True)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
env.pop("TYCAD_LANG", None)
def run(lines, extra=()):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp] + list(extra), capture_output=True, text=True, timeout=200, env=env)
    return r.stdout.splitlines()
def ps(s): return mkpo.pseudo_of(s)
# what to ask: the entries of the main window and of a few frames
entries = dict(mkpo.all_entries())
main_ids = [i for i in entries if i.startswith("tfrmmain.") and "[" not in i and not i.endswith(".text") and i.count(".") >= 2]
step = max(1, len(main_ids) // 14)
sample = main_ids[::step][:14]
asks = []; want_en = []; want_ps = []
for i in sample:
    comp, prop = i.split(".")[-2:]
    asks.append("text %s %s" % (comp, prop))
# components are written in lower case in the identifiers; find their real spelling in the form file
lfm = open(os.path.join(ROOT, "src", "forms", "mainform.lfm"), encoding="utf-8", errors="replace").read()
real = {m.group(1).lower(): m.group(1) for m in re.finditer(r"(?:object|inherited|inline)\s+(\w+)\s*:", lfm)}
asks = ["text %s %s" % (real[i.split(".")[-2]], i.split(".")[-1]) for i in sample]
frame_asks = [("pin", "lbShape", "caption", "tfmpin.lbshape.caption"), ("pin", "edPinNumber", "hint", "tfmpin.edpinnumber.hint"), ("pin", "sbPinCentre", "hint", "tfmpin.sbpincentre.hint"),
              ("method", "sbShowRef", "hint", None), ("wire", "lbCaption", "caption", None)]
fr_cmds = []
for key, comp, prop, ident in frame_asks:
    fr_cmds.append("text frame %s %s %s" % (key, comp, prop))
script = ["newdoc A4", "registerframe x all", "rs ready", "rs snapon", "rs nothing", "rs grid 5", "rs undohint"] + asks + fr_cmds + ["snap on", "gridinfo"]
en = run(script)
tp = run(script, ["--lang", "qps"])
xx = run(script, ["--lang", "xx"])
check("the script ran in English", any(l.startswith("RS ready") for l in en), en[:5])
check("English: the resourcestrings are the ones of UStrings.pas", "RS ready=[Ready]" in en and "RS snapon=[Snap to grid: on]" in en and "RS nothing=[Nothing selected]" in en and "RS grid=[Grid: 5]" in en, [l for l in en if l.startswith("RS")])
check("a language with no file stays English", [l for l in xx if l.startswith(("RS", "TEXT"))] == [l for l in en if l.startswith(("RS", "TEXT"))])
check("the made-up language: resourcestrings are translated, a value is filled into its place", "RS ready=[%s]" % ps("Ready") in tp and "RS snapon=[%s]" % ps("Snap to grid: on") in tp
      and "RS nothing=[%s]" % ps("Nothing selected") in tp and "RS grid=[%s]" % ps("Grid: %s").replace("%s", "5") in tp and "RS undohint=[%s]" % ps("Undo (Ctrl+Z)") in tp, [l for l in tp if l.startswith("RS")])
bad = []
for i, a in zip(sample, asks):
    comp, prop = a.split()[1], a.split()[2]
    e = [l for l in en if l.startswith("TEXT %s %s" % (comp, prop))]
    t = [l for l in tp if l.startswith("TEXT %s %s" % (comp, prop))]
    if not e or not t: bad.append((i, "missing")); continue
    ev = e[0].split("=[", 1)[1][:-1] if "=[" in e[0] else None
    tv = t[0].split("=[", 1)[1][:-1] if "=[" in t[0] else None
    if ev is None or tv is None: bad.append((i, e[0], t[0])); continue
    # a text the program sets itself at start-up (the undo hint, the status bar ...) is not the one of the form file: it must be a translation of something, either way
    if ev == entries[i].replace("\n", "\\n"):
        if tv != ps(entries[i]).replace("\n", "\\n"): bad.append((i, ev, tv))
    else:
        if not (tv.startswith("[") and tv.endswith("]")) and tv != ev: bad.append((i, ev, tv))
check("main window: %d captions and hints are those of the form in English and translated in the made-up language" % len(sample), not bad and len(sample) >= 10, bad[:4])
fe = [l for l in en if l.startswith("TEXT") and l.split()[1] in ("lbShape", "edPinNumber", "sbPinCentre", "sbShowRef", "lbCaption")]
ft = [l for l in tp if l.startswith("TEXT") and l.split()[1] in ("lbShape", "edPinNumber", "sbPinCentre", "sbShowRef", "lbCaption")]
check("frames are made with their texts (5 asked)", len(fe) == 5 and len(ft) == 5, (fe, ft))
pin_en = {l.split()[1]: l.split("=[", 1)[1][:-1] for l in fe if "=[" in l}
pin_tp = {l.split()[1]: l.split("=[", 1)[1][:-1] for l in ft if "=[" in l}
check("pin frame: the caption and hints in English are those of QPin.lfm", pin_en.get("lbShape") == "Type" and pin_en.get("edPinNumber") == "The number of the pin" and pin_en.get("sbPinCentre") == "Centre the name on the pin", pin_en)
check("pin frame: translated in the made-up language", pin_tp.get("lbShape") == ps("Type") and pin_tp.get("edPinNumber") == ps("The number of the pin") and pin_tp.get("sbPinCentre") == ps("Centre the name on the pin"), pin_tp)
print("translation: %d checks, %d failed" % (checks, len(fails))); sys.exit(1 if fails else 0)
