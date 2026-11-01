#!/usr/bin/env python3
"""Pasting a placed symbol into the symbol editor of a part: it comes in as the lines and pins it is drawn with (not as a symbol inside the symbol, which is stored without pins and
shows as a box when opened again), and a symbol pasted into a design stays a symbol.  Needs xvfb-run and the built program."""
import os, re, sys, shutil, subprocess, tempfile, sqlite3
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("symbol paste checks skipped: need xvfb-run and the built program"); sys.exit(0)
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
CT = "Contactor 3P 25 A AC-3, 24 V DC coil"
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines).replace("\\\n", "\n") + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env)
    return r.stdout.splitlines()
out = run(["newdoc A4", "registerframe x all", "pdbtab open " + f, "pdbplace 1 80 80 yes", "selidx 0", "copy",
           "peopen " + f, "pe page symbols", "pe sym part|" + CT, "pe sym start|-1|ANSI|schematic|Pasted", "paste", "echo P", "objects", "sym store=1", "echo S"])
i = out.index("P"); objs = [l.split()[1] for l in out[i + 1:] if l.startswith("OBJ ") and l.split()[1] != "end"]
check("the pasted symbol is its lines and pins, not a symbol object", "TDrawMethod" not in objs and objs.count("TDrawPin") == 6 and "TDrawSquare" in objs, objs)
store = [l for l in out if l.startswith("SYM store")]
check("it is stored with no 'no pins' warning", store and "has no pins" not in store[0], store)
c = sqlite3.connect(f); row = c.execute("select Drawing from Symbol where Name = 'Pasted'").fetchone(); c.close()
x = row[0].decode() if isinstance(row[0], bytes) else row[0]
check("the stored drawing has the six pins and no symbol object", x.count("<PIN ") == 6 and "<METHOD" not in x and "<SYMBOL" not in x, re.findall(r"<([A-Z]+)[ >]", x))
# a symbol pasted into an ordinary design stays a symbol
out = run(["newdoc A4", "registerframe x all", "pdbtab open " + f, "pdbplace 1 80 80 yes", "selidx 0", "copy", "paste", "echo P", "objects"])
i = out.index("P"); objs = [l.split()[1] for l in out[i + 1:] if l.startswith("OBJ ") and l.split()[1] != "end"]
check("in a design the pasted symbol is still a symbol", objs.count("TDrawMethod") == 2, objs)
# wires copied from a drawing come into the symbol editor as plain lines (the editor refuses wires)
out = run(["newdoc A4", "registerframe x all", "ribbontab Draw", "tool wire", "mouse down 60 60", "mouse down 100 60", "mouse dbl 100 60", "tool select", "selidx 0", "copy",
           "peopen " + f, "pe page symbols", "pe sym part|" + CT, "pe sym start|-1|ANSI|schematic|Wired", "paste", "echo P", "objects", "sym store=1"])
i = out.index("P"); objs = [l for l in out[i + 1:] if l.startswith("OBJ ") and l.split()[1] != "end"]
c = sqlite3.connect(f); row = c.execute("select Drawing from Symbol where Name = 'Wired'").fetchone(); c.close()
x = (row[0].decode() if isinstance(row[0], bytes) else row[0]) if row else ""
check("a pasted wire is a line, not a wire", any("TDrawLine" in l for l in objs) and "<LINE" in x and "<WIRE" not in x, (objs, x[:300]))
# Symbol Properties of a part's symbol: a new symbol stores with what it shows, and a renamed / re-shown one is updated in the parts file when it is stored
g = os.path.join(tmp, "q.TCParts"); parts_seed.build(g).close()
c = sqlite3.connect(g); pole = c.execute("select ObjectID from PartObject where PartID = 2 and Name = 'Pole 1'").fetchone()[0]; pole2 = c.execute("select ObjectID from PartObject where PartID = 2 and Name = 'Pole 2'").fetchone()[0]; c.close()
out = run(["peopen " + g, "pe page symbols", "pe sym part|" + CT, "pe sym start|-1|ANSI|schematic|First|%d" % pole, "tool line", "clickmm 40 40", "clickmm 80 40", "tool select", "sym store=1", "echo S1",
           "gotodoc 0", "pe page symbols", "pe sym part|" + CT, "pe sym start|1|||", "partsyminfo JIC schematic Renamed %d" % pole2, "sym store=1", "echo S2"])
c = sqlite3.connect(g); rows = c.execute("select Standard, Name, ShowsObject from Symbol where PartID = 2 order by SymbolID").fetchall(); c.close()
i1 = out.index("S1"); r1 = [l for l in out[:i1] if l.startswith("PE sym start") or l.startswith("SYM store")]
c = sqlite3.connect(g); n_before = c.execute("select count(*) from Symbol where PartID = 2").fetchone()[0]; c.close()
check("one symbol was added (the contactor's own and the new one), the second store changed it and added nothing", n_before == 2 and len(rows) == 2 and rows.count(("JIC", "Renamed", pole2)) == 1 and not any(r[1] == "First" for r in rows), (rows, r1))
check("the changed standard, name and object are written when the symbol is stored", ("JIC", "Renamed", pole2) in rows, rows)
print("symbol paste: %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
