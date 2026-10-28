#!/usr/bin/env python3
"""Placing a generic part from the Parts tab (UPartsDb symbol XML -> the symbol loader -> a placed symbol). Oracle: Python's sqlite3 on the sample file gives the names, the reference
letters (Part.RefPrefix + '?') and the number of pins (counted in the XML text of the Symbol blob); the script reports the placed symbol's reference, name and pins (pinsof).
Cases: refused warning places nothing; accepted warning places; the warning is asked once per run; the 'do not show again' setting skips it; no sheet; a part without a symbol.
Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, sys, re, shutil, sqlite3, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, "..", "docs"))
import parts_seed
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Part placing checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:400])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    return subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env).stdout.splitlines()
f = os.path.join(tmp, "a.TCParts"); parts_seed.build(f).close(); db = sqlite3.connect(f)
parts = db.execute("select p.PartID, p.Name, coalesce(p.RefPrefix,''), (select Drawing from Symbol where PartID=p.PartID) from Part p join PartClass c using(ClassID) order by lower(c.Name), lower(p.Name)").fetchall()
pins = [len(re.findall(rb"<PIN ", d)) for *_x, d in parts]
check("the sample has symbols with different numbers of pins (so the check can fail)", len(set(pins)) == 2 and min(pins) > 0, pins)
o = run(["newdoc A4", "pdbtab open " + f, "pdbplace 1 80 60 no", "objects", "pdbplace 1 80 60 yes", "objects", "props", "pinsof"])
pl = [l for l in o if l.startswith("PDBPLACE")]
check("a warning answered No places nothing", pl[0] == "PDBPLACE 1 refused" and o[o.index("OBJ end 0")] == "OBJ end 0", pl)
check("answered Yes the part is placed as one symbol", pl[1] == "PDBPLACE 1 placed" and "OBJ end 1" in o and "OBJ TDrawMethod id=1" in o, o)
pr = [l for l in o if l.startswith("PROPS")]
check("the placed symbol has the part's name and its reference letters followed by ?", pr and "sym.ref=%s?;" % parts[1][2] in pr[0] and "sym.name=%s;" % parts[1][1] in pr[0], pr)
pn = [l for l in o if l.startswith("PIN 0 ")]
check("it has every pin of the part's symbol", len(pn) == pins[1], (len(pn), pins))
o = run(["newdoc A4", "pdbtab open " + f, "pdbplace 1 80 60 yes", "pdbplace 0 150 60 no", "objects", "selectall", "pinsof"])
pl = [l for l in o if l.startswith("PDBPLACE")]
check("the warning is asked once per run: after a Yes the next part is placed without asking (even when the script would answer No)", pl == ["PDBPLACE 1 placed", "PDBPLACE 0 placed"] and "OBJ end 2" in o, pl)
check("the second part has its own pins", len([l for l in o if l.startswith("PIN 1 ")]) == pins[0], pins)
o = run(["newdoc A4", "pdbtab open " + f, "pdbwarn off", "pdbplace 0 80 60 no", "objects"])
check("with 'do not show again' set the part is placed without asking", "PDBPLACE 0 placed" in o and "OBJ end 1" in o, o)
o = run(["pdbtab open " + f, "pdbplace 0 80 60 yes"])
check("with no document open nothing is placed", "PDBPLACE 0 nosheet" in o, o)
g = os.path.join(tmp, "nosym.TCParts"); shutil.copy(f, g); c = sqlite3.connect(g); c.execute("update Part set BaseDefault=null"); c.execute("delete from Symbol"); c.commit(); c.close()
o = run(["newdoc A4", "pdbtab open " + g, "pdbplace 0 80 60 yes", "objects"])
check("a part without a symbol is not placed", "PDBPLACE 0 nosymbol" in o and "OBJ end 0" in o, o)
print("%d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
