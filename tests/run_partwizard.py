#!/usr/bin/env python3
"""Add Part wizard (parts plan step 7): the presets, what the wizard shows for each, the parts and objects it makes (read back with sqlite3), a refusal that leaves nothing
behind, and the Advanced box that hides the Classes and Products pages.  Needs xvfb-run and the built program."""
import os, re, sys, shutil, subprocess, tempfile, sqlite3
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("part wizard checks skipped: need xvfb-run and the built program"); sys.exit(0)
sys.path.insert(0, os.path.join(HERE, "..", "docs")); import parts_seed
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name); print("  FAIL", name, str(detail)[:600])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
f = os.path.join(tmp, "p.TCParts"); parts_seed.build(f).close()
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(["peopen " + f] + lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env)
    return r.stdout.splitlines()
def lines(out, key): return [l for l in out if l.startswith(key)]
def part(name):
    c = sqlite3.connect(f)
    p = c.execute("select PartID, RefPrefix, (select Name from PartClass where ClassID = Part.ClassID) from Part where Name = ?", (name,)).fetchone()
    if not p: c.close(); return None
    objs = c.execute("select o.ObjectID, o.ParentObjectID, k.Name, o.Name, coalesce(o.Designator, '') from PartObject o join ObjectKind k using (KindID) where o.PartID = ? order by o.ObjectID", (p[0],)).fetchall()
    vals = {}
    for oid, fn, vt, vn in c.execute("select v.ObjectID, d.Name, v.ValueText, v.ValueNum from ObjectValue v join KindFieldDef d using (FieldID) join PartObject o on o.ObjectID = v.ObjectID where o.PartID = ?", (p[0],)):
        vals[(oid, fn)] = vt if vt is not None else vn
    c.close(); return p, objs, vals
def nparts():
    c = sqlite3.connect(f); n = c.execute("select count(*) from Part").fetchone()[0]; c.close(); return n
# --- the presets and what the wizard shows
out = run(["pe wiz presets", "pe wiz dlg|relay", "pe wiz dlg|contactor", "pe wiz dlg|timer", "pe wiz dlg|breaker", "pe wiz dlg|terminal", "pe wiz dlg|other"])
keys = [l.split()[2].split("|")[0] for l in lines(out, "PEWIZ preset")]
check("six presets, the blank one last", keys == ["relay", "contactor", "timer", "breaker", "terminal", "other"], keys)
d = lines(out, "PEWIZ dlg")
check("a relay asks NO, NC and the coil", "shown=011100" in d[0] and "name=[Relay 2 NO + 2 NC]" in d[0] and "letters=[K]" in d[0], d[0])
check("a contactor asks poles, NO, NC and the coil", "shown=111100" in d[1] and "name=[Contactor 3-pole + 1 NO + 1 NC]" in d[1] and "summary=[This makes: coil, 3 poles, 1 NO + 1 NC auxiliary contacts]" in d[1], d[1])
check("a timer relay also asks the delay", "shown=011110" in d[2] and "on-delay 5 s" in d[2], d[2])
check("a breaker asks only the poles and has letters Q", "shown=100000" in d[3] and "letters=[Q]" in d[3] and "name=[Breaker 3-pole]" in d[3], d[3])
check("a terminal block asks nothing", "shown=000000" in d[4] and "summary=[This makes: no objects]" in d[4], d[4])
check("the blank preset asks the class and has no letters", "shown=000001" in d[5] and "letters=[]" in d[5], d[5])
# --- the parts made
out = run(["pe wiz add|contactor||3|1|1|1|none|0||", "pe wiz add|timer||0|1|1|1|on-delay|5||", "pe wiz add|relay||0|2|1|1|none|0||", "pe wiz add|breaker||4|0|0|0|none|0||",
           "pe wiz add|terminal||0|0|0|0|none|0||", "pe wiz add|other|Sensor X|0|0|0|0|none|0|S|Sensor"])
ok = [l for l in lines(out, "PEWIZ add")]
check("every add was accepted", len(ok) == 6 and all(" ok " in l for l in ok), ok)
r = part("Contactor 3-pole + 1 NO + 1 NC")
check("the contactor is a Contactor with letters K, a coil A1/A2, 3 main poles, 2 auxiliary poles", r and r[0][1] == "K" and r[0][2] == "Contactor" and sum(1 for o in r[1] if o[2] == "Coil" and o[4] == "A1/A2") == 1
      and sum(1 for o in r[1] if o[2] == "Pole") == 5 and sum(1 for o in r[1] if o[2] == "Contact") == 5, r and (r[0], r[1]))
if r:
    cd = [o[4] for o in r[1] if o[2] == "Contact"]
    check("terminal numbers: 1/2 3/4 5/6 for the main poles, 13/14 and 21/22 for the auxiliary contacts", cd == ["1/2", "3/4", "5/6", "13/14", "21/22"], cd)
    forms = [r[2].get((o[0], "Form")) for o in r[1] if o[2] == "Contact"]
    check("the main poles and the first auxiliary are NO, the second auxiliary NC", [x or "NO" for x in forms] == ["NO", "NO", "NO", "NO", "NC"], forms)
r = part("On-delay relay 1 NO + 1 NC")
if r:
    dl = [(r[2].get((o[0], "Delay")), r[2].get((o[0], "DelaySecs"))) for o in r[1] if o[2] == "Contact"]
    check("a timer relay's contacts are on-delay 5 s", dl == [("on-delay", 5.0), ("on-delay", 5.0)], dl)
else: check("a timer relay was made", False)
r = part("Relay 2 NO + 1 NC")
check("a relay: a coil, 2 NO and 1 NC contacts, class Relay", r and r[0][2] == "Relay" and sum(1 for o in r[1] if o[2] == "Contact") == 3 and sum(1 for o in r[1] if o[2] == "Coil") == 1, r and r[1])
r = part("Breaker 4-pole")
check("a breaker has 4 poles, no coil, class Breaker, letters Q", r and r[0][1] == "Q" and r[0][2] == "Breaker" and sum(1 for o in r[1] if o[2] == "Pole") == 4 and not any(o[2] == "Coil" for o in r[1]), r and (r[0], r[1]))
r = part("Terminal block")
check("a terminal block has no objects", r and r[0][2] == "TerminalBlock" and r[1] == [], r)
r = part("Sensor X")
check("the blank preset makes an empty part of the chosen class with the letters given", r and r[0][2] == "Sensor" and r[0][1] == "S" and r[1] == [], r)
# --- a refusal leaves nothing behind: the name already exists in the class
n0 = nparts()
out = run(["pe wiz add|contactor|Contactor 3-pole + 1 NO + 1 NC|3|1|1|1|none|0||"])
e = lines(out, "PEWIZ add")
check("the same name again is refused with a reason", e and "error" in e[0], e)
check("and no part or object is left behind", nparts() == n0, (nparts(), n0))
c = sqlite3.connect(f); orphan = c.execute("select count(*) from PartObject where PartID not in (select PartID from Part)").fetchone()[0]; c.close()
check("no object without a part", orphan == 0, orphan)
# --- a name of the person's own is kept when the entries change
out = run(["pe wiz add|contactor|My K1|2|0|0|1|none|0|KM|"])
r = part("My K1")
check("a name typed by the person is used, and letters KM", r and r[0][1] == "KM" and sum(1 for o in r[1] if o[2] == "Pole") == 2, r and r[0])
# --- Advanced hides the Classes and Products pages
out = run(["pe wiz adv", "pe wiz adv|on", "pe page classes", "pe wiz adv", "pe wiz adv|off", "pe page products", "pe wiz adv", "pe wiz adv|off"])
a = lines(out, "PEWIZ adv")
check("Advanced is off at first and the two pages are hidden", "checked=0 classes=0 products=0" in a[0], a[0])
check("ticking it shows them", "checked=1 classes=1 products=1" in a[1], a[1])
check("choosing the Classes page ticks it", "checked=1 classes=1 products=1 page=classes" in a[2], a[2])
check("unticking it hides them and goes back to the Parts page", "checked=0 classes=0 products=0 page=parts" in a[3], a[3])
check("choosing the Products page (the script) ticks it again", "checked=1" in a[4] and "page=products" in a[4], a[4])
print("part wizard: %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
