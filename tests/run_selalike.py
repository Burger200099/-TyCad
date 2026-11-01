#!/usr/bin/env python3
"""Select All Alike submenu for a right clicked symbol (All Symbols / Identical References / Identical Names), built in code; a plain object keeps the plain command.
Needs xvfb-run and the built program."""
import os, re, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("select all alike checks skipped: need xvfb-run and the built program"); sys.exit(0)
sys.path.insert(0, os.path.join(HERE, "..", "docs")); import parts_seed
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name); print("  FAIL", name, str(detail)[:500])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
f = os.path.join(tmp, "p.TCParts"); parts_seed.build(f).close()
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env)
    return r.stdout.splitlines()
# four symbols down the sheet: the contactor (row 1 of the library) as K1, k12 and KM3, and the analog module (row 0) as K7: same letters as K1, another name
SET = ["newdoc A4", "registerframe x all", "ribbontab Draw", "pdbtab open " + f,
       "pdbplace 1 60 60 yes", "pdbplace 1 60 120 yes", "pdbplace 1 60 180 yes", "pdbplace 0 60 240 yes",
       "selidx 0", "setprop sym.ref K1", "selidx 1", "setprop sym.ref k12", "selidx 2", "setprop sym.ref KM3", "selidx 3", "setprop sym.ref K7"]
def at(row): return "%d %d" % (20, 60 * (row + 1) - 30)     # a point on a pin lead of the symbol in that row
def sel_after(click, row):
    out = run(SET + ["selidx %d" % row, "echo A", "ctxmenu " + at(row), "ctxclick " + click, "echo B", "ctxmenu " + at(row)])
    i = out.index("B"); return [l for l in out[i + 1:] if l.startswith("CTX done")], out
def menu_of(row):
    out = run(SET + ["selidx %d" % row, "echo A", "ctxmenu " + at(row), "echo B"])
    i = out.index("A"); j = out.index("B")
    return [l for l in out[i + 1:j] if l.startswith("CTX ")], out
m, out = menu_of(0)
alike = [l for l in m if "Select_All_Alike" in l]
sub = [l for l in m if re.match(r"CTX 1 (All_Symbols|Identical_References|Identical_Names) ", l)]
check("a right clicked symbol: Select All Alike has the three sub items", len(alike) == 1 and [l.split()[2] for l in sub] == ["All_Symbols", "Identical_References", "Identical_Names"], (alike, sub))
r, _ = sel_after("Select_All_Alike/All_Symbols", 0); check("All Symbols selects the four symbols", r and "sel=4" in r[-1], r)
r, _ = sel_after("Select_All_Alike/Identical_References", 0); check("Identical References for K1: K1, k12 and K7 (letters k), not KM3", r and "sel=3" in r[-1], r)
r, _ = sel_after("Select_All_Alike/Identical_References", 2); check("Identical References for KM3: itself only", r and "sel=1" in r[-1], r)
r, _ = sel_after("Select_All_Alike/Identical_Names", 0); check("Identical Names for the contactor: the three contactors, not the analog module", r and "sel=3" in r[-1], r)
r, _ = sel_after("Select_All_Alike/Identical_Names", 3); check("Identical Names for the analog module: itself only", r and "sel=1" in r[-1], r)
# a plain object keeps the plain command (no sub items), and it still works
out = run(["newdoc A4", "registerframe x all", "ribbontab Draw", "tool wire", "mouse down 60 60", "mouse down 120 60", "mouse dbl 120 60", "tool select", "echo A", "ctxmenu 90 60", "echo B"])
i = out.index("A"); j = out.index("B"); m = [l for l in out[i + 1:j] if l.startswith("CTX ")]
k = [n for n, l in enumerate(m) if "Select_All_Alike" in l]
check("a wire's menu has Select All Alike with no sub items", len(k) == 1 and not (k[0] + 1 < len(m) and m[k[0] + 1].startswith("CTX 1 ") and "Symbols" in m[k[0] + 1]), m[k[0]:k[0] + 3] if k else m)
out = run(["newdoc A4", "registerframe x all", "ribbontab Draw", "tool wire", "mouse down 60 60", "mouse down 120 60", "mouse dbl 120 60", "tool select", "ctxmenu 90 60", "ctxclick Select_All_Alike", "echo B", "ctxmenu 90 60"])
check("and clicking it still selects the alike objects", [l for l in out[out.index("B") + 1:] if l.startswith("CTX done")][0].endswith("sel=1"), out[-3:])
# a placed part also gets Insert Next Free Contact on its right click menu; a wire does not
m, _ = menu_of(0)
check("a placed part's menu has Insert Next Free Contact", any("Insert_Next_Free_Contact" in l for l in m), m[:6])
check("a wire's menu does not", not any("Insert_Next_Free_Contact" in l for l in [l for l in out if l.startswith("CTX ")]), "")
print("select all alike: %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
