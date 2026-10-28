"""Hints, the menu hint in the status bar, and the light/dark theme kept in the registry.
  - every control and menu item a person can use (menu items other than separators, speed buttons, buttons, check and radio buttons, edits, lists, ...) has a Hint in its
    .lfm (read from the form files as text, independent of the program)
  - the cursor on a menu item shows its Hint in the first panel of the status bar (menuselect), and an item moved off leaves 'Ready' behind
  - Dark Mode / Light Mode: the menu item says what it will switch to, the choice is written to the registry (DarkMode) at once and read back at the next start; the default is light
Needs the built program and xvfb."""
import glob, os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n); print("  FAIL", n, str(d)[:400])
# ---------- 1. the .lfm files ----------
NEEDS = {"TMenuItem", "TSpeedButton", "TButton", "TBitBtn", "TCheckBox", "TRadioButton", "TEdit", "TComboBox", "TListBox", "TMemo", "TTreeView", "TStringGrid", "TToggleBox",
         "TRadioGroup", "TPageControl", "TSpinEdit", "TFloatSpinEdit"}
def scan(path):
    stack = []; out = []
    for l in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"(\s*)(object|inherited)\s+(\w+)\s*:\s*(\w+)", l)
        if m: stack.append(dict(ind=len(m.group(1)), name=m.group(3), cls=m.group(4), hint=None, cap=None, inh=m.group(2) == "inherited")); continue
        m = re.match(r"(\s*)end\s*$", l)
        if m and stack and len(m.group(1)) == stack[-1]["ind"]: out.append(stack.pop()); continue
        if stack:
            ind = len(l) - len(l.lstrip())
            if ind == stack[-1]["ind"] + 2:
                m = re.match(r"\s*Hint = '(.*)'", l)
                if m: stack[-1]["hint"] = m.group(1)
                m = re.match(r"\s*Caption = '(.*)'", l)
                if m: stack[-1]["cap"] = m.group(1)
    return out
DESIGNER_FRAMES = ('qpropbase.lfm', 'qpropwire.lfm', 'qrectcircle.lfm', 'qpolygon.lfm', 'qarc.lfm', 'qcloudnote.lfm', 'qproptext.lfm', 'qpropwirelabel.lfm', 'qpropnote.lfm', 'qpowersym.lfm', 'qmeasure.lfm', 'fproptester.lfm')
files = sorted(glob.glob(os.path.join(ROOT, "src", "forms", "*.lfm")) + glob.glob(os.path.join(ROOT, "src", "frames", "*.lfm")))
# the Properties frames the designer makes (QPropBase and its descendants, lower case file names) are laid out by hand: a hint on each is the designer's choice
files = [f for f in files if os.path.basename(f) not in DESIGNER_FRAMES]
check("lfm files found", len(files) >= 15, len(files))
total = 0
for f in files:
    for o in scan(f):
        if o["cls"] not in NEEDS or o["inh"]: continue        # (an inherited control has the hint of the form or frame it comes from, which is read too)
        if o["cls"] == "TMenuItem" and (o["cap"] == "-" or (o["cap"] is None and o["name"].lower().startswith(("sep", "msep")))): continue
        total += 1
        check("%s: %s %s has a hint" % (os.path.basename(f), o["cls"], o["name"]), bool(o["hint"] and o["hint"].strip()), o)
        if o["hint"]: check("%s: hint of %s is not just its name" % (os.path.basename(f), o["name"]), o["hint"].strip().lower() != o["name"].lower(), o)
check("many controls were checked", total > 250, total)
# ---------- 2. in the program ----------
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Hint checks (program part) skipped: need xvfb-run and the built program", BIN)
else:
    tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
    def run(script, home):
        h = os.path.join(tmp, "home_" + home); os.makedirs(h, exist_ok=True)
        p = os.path.join(tmp, "s.txt"); open(p, "w").write(script)
        r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", p], capture_output=True, text=True, timeout=120, env=dict(os.environ, HOME=h))
        return [l for l in r.stdout.split("\n") if l], h
    names = {}
    for f in files:
        if os.path.basename(f) == "mainform.lfm":
            for o in scan(f):
                if o["cls"] == "TMenuItem" and o["hint"]: names[o["name"]] = o["hint"]
    dyn = set()      # the Window menu is cleared and rebuilt as documents open (UpdateWindowMenu): its designed items are gone at run time
    for f in files:
        if os.path.basename(f) == "mainform.lfm":
            t = open(f, errors="replace").read(); a = t.find("object mWindow: TMenuItem")
            if a >= 0:
                b = t.find("\n    object ", a + 10); dyn |= set(re.findall(r"object (\w+): TMenuItem", t[a + 10:b if b > 0 else len(t)]))
    pick = [n for n in sorted(names) if n not in dyn][::7][:12]
    o, _ = run("".join("menuselect %s\n" % n for n in pick) + "menuselect nosuchitem\n", "hint")
    ms = [l for l in o if l.startswith("MENUSELECT")]
    check("menuselect answers every item", len(ms) == len(pick) + 1, o[:3])
    for n, l in zip(pick, ms):
        want = names[n].replace("''", "'")
        check("hovering %s shows its hint in panel 0" % n, l.startswith("MENUSELECT %s hint=%s panel0=%s enabled=" % (n, want, want)), l)
    # theme
    o, h = run("themeinfo\ndotheme\nthemeinfo\n", "theme")
    t = [l for l in o if l.startswith("THEMEINFO")]
    check("starts light; the item offers Dark Mode", t and t[0] == "THEMEINFO dark=0 caption=Dark Mode setting=0", o)
    check("after the choice: dark, the item offers Light Mode, the setting is set", len(t) == 2 and t[1] == "THEMEINFO dark=1 caption=Light Mode setting=1", t)
    reg = open(os.path.join(h, ".config", "TyCAD Electrical", "reg.xml"), encoding="utf-8", errors="replace").read() if os.path.exists(os.path.join(h, ".config", "TyCAD Electrical", "reg.xml")) else ""
    check("DarkMode is written to the registry", re.search(r'DarkMode[^>]*?(Value)?="?(1|True)', reg) is not None, reg[-400:])
    o, _ = run("themeinfo\ndotheme\nthemeinfo\n", "theme")
    t = [l for l in o if l.startswith("THEMEINFO")]
    check("next start: dark as left, choosing again goes back to light", len(t) == 2 and t[0] == "THEMEINFO dark=1 caption=Light Mode setting=1" and t[1] == "THEMEINFO dark=0 caption=Dark Mode setting=0", t)
    o, _ = run("themeinfo\n", "theme")
    t = [l for l in o if l.startswith("THEMEINFO")]
    check("and that is kept too", t == ["THEMEINFO dark=0 caption=Dark Mode setting=0"], t)
print("Hint and theme checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
