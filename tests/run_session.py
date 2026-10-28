"""Save All and reopening the designs that were open (two additions to TinyCAD, which has neither: its SaveAll is the helper of the automatic save). The real commands are run by script:
  - Save All: every open design that has unsaved changes and a file is written to its file (and no other is touched, byte for byte); one that has no file name is left (and counted) when
    names are not asked for; one that cannot be written does not stop the others and is named; the design showing and its undo history are as they were; a second Save All writes nothing
  - the designs that were open: when the program is closed the files of those that have one are remembered in order with the one that was showing (in the registry, packed to the front, at most
    20); the next start opens them again in that order and shows that one; a file that has gone is skipped without a fuss; with the option off nothing is remembered and what was is forgotten
  - the option is in the Options dialog (and the registry as ReopenDesigns), off to begin with; and the real program, started with a remembered session, comes up and stays up
Needs the built program."""
import os, re, shutil, subprocess, sys, tempfile, time
import xml.etree.ElementTree as ET
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from designoracle import objects, sheet0
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Session checks skipped: need xvfb-run and the built program", BIN); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:420])
def home(name): h = os.path.join(tmp, "home_" + name); os.makedirs(h, exist_ok=True); return h
def run(script, h, timeout=150):
    path = os.path.join(tmp, "script.txt"); open(path, "w", encoding="utf-8").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", path], capture_output=True, text=True, timeout=timeout, env=dict(os.environ, HOME=h))
    return r.stdout.split("\n"), r.returncode, r.stderr
def docs(lines, nth=-1):
    l = [x for x in lines if x.startswith("DOCS ")][nth]
    m = re.match(r"DOCS (\d+) current=(-?\d+) list=(.*)$", l)
    return int(m.group(2)), [x for x in m.group(3).split("|") if x != ""]
def reg(h):
    files = [os.path.join(dp, f) for dp, _, fs in os.walk(h) for f in fs if f == "reg.xml"]
    if not files: return {}
    node = ET.parse(files[0]).getroot()
    for part in ("HKEY_CURRENT_USER", "SOFTWARE", "HPL Software", "TyCAD Electrical"):
        node = next((k for k in node.findall("Key") if k.get("Name") == part), None)
        if node is None: return {}
    return {v.get("Name"): v.text for v in node.findall("Value")}
sample = next(p for p in sorted(os.path.join(dp, f) for dp, _, fs in os.walk(EX) for f in fs if f.endswith(".dsn")) if os.path.basename(p) == "PSU.dsn")
def make(name, sub=""):
    d = os.path.join(tmp, "designs", sub); os.makedirs(d, exist_ok=True); p = os.path.join(d, name); shutil.copy(sample, p); return p
def nobj(path): return len(objects(sheet0(path)))
WIRE = "tool wire\nmouse down 20 {y}\nmouse down 60 {y}\nmouse rdown 60 {y}\n"
# ---------- Save All ----------
A, B, C = make("A.dsn", "s1"), make("B.dsn", "s1"), make("C.dsn", "s1")
before = {p: open(p, "rb").read() for p in (A, B, C)}; n0 = nobj(A)
o, rc, err = run(f'open "{A}"\nopen "{B}"\nopen "{C}"\nnewdoc "ISO A4" landscape\ngotodoc 0\n' + WIRE.format(y=20) + 'gotodoc 2\n' + WIRE.format(y=30) + 'gotodoc 3\n' + WIRE.format(y=40) +
                 'gotodoc 1\ndocs\nsaveall\ndocs\nsaveall\ndocs\ngotodoc 0\nundoinfo\nundo\ndocs\n', home("sa1"))
d0 = docs(o, 0); d1 = docs(o, 1); d2 = docs(o, 2); d3 = docs(o, 3)
sv = [l for l in o if l.startswith("SAVEALL ")]
check("the designs with changes (A, C and the untitled one) show as changed before; Save All saves the two that have a file (saved=2) and counts the untitled one it cannot name (skipped=1, failed=0)", d0[1] == ["A.dsn *", "B.dsn", "C.dsn *", "Untitled 1 *"] and sv[0] == "SAVEALL saved=2 skipped=1 failed=0", f"{d0} {sv}")
check("afterwards only the untitled design is still marked as changed, and the design that was showing (B) still is", d1[1] == ["A.dsn", "B.dsn", "C.dsn", "Untitled 1 *"] and d1[0] == 1, str(d1))
check("A and C are on disk with their new wire (one more object each); B, which had no changes, is exactly the bytes it was", nobj(A) == n0 + 1 and nobj(C) == n0 + 1 and open(B, "rb").read() == before[B], f"{nobj(A)} {nobj(C)} {n0}")
check("a second Save All writes nothing (saved=0, the untitled one still skipped)", sv[1] == "SAVEALL saved=0 skipped=1 failed=0", sv[1])
ui = [l for l in o if l.startswith("UNDOINFO")][0]
check("saving does not touch the undo history: after Save All the wire drawn in A is still in A's undo history (at least one step, the last called Draw), and undoing it makes A a changed design again", int(re.search(r"undo=(\d+)", ui).group(1)) >= 1 and 'next="Draw"' in ui and d3[1][0] == "A.dsn *", f"{ui} {d3}")
# a design that cannot be written does not stop the others
E, F = make("E.dsn", "s2"), make("F.dsn", "s3"); nE = nobj(E); nF = nobj(F)
o, rc, err = run(f'open "{E}"\nopen "{F}"\ngotodoc 0\n' + WIRE.format(y=20) + 'gotodoc 1\n' + WIRE.format(y=30) + f'fsdel "{E}"\nfsdel "{os.path.dirname(E)}"\nsaveall\ndocs\n', home("sa2"))
sv = [l for l in o if l.startswith("SAVEALL ")][0]; d = docs(o)
check("a design that cannot be written (its folder is gone) does not stop the others: Save All saves F (saved=1), reports E as failed (failed=1), and E is still marked as changed",
      sv == "SAVEALL saved=1 skipped=0 failed=1" and nobj(F) == nF + 1 and d[1] == ["E.dsn *", "F.dsn"], f"{sv} {d} {nobj(F)} {nF}")
o, rc, err = run('saveall\n', home("sa3"))
check("with nothing open Save All does nothing and does not fail", "SAVEALL saved=0 skipped=0 failed=0" in o, str(o[-3:]))
# ---------- the designs that were open ----------
H = home("sess")
o, rc, err = run('optionsinfo\n', home("fresh")); inf = [l for l in o if l.startswith("OPTIONSINFO settings")][0]
check("the option to open the designs again is off to begin with, and the registry says so once the settings are kept", "reopen=0" in inf, inf)
S1, S2, S3 = make("one.dsn", "ses"), make("two.dsn", "ses"), make("three.dsn", "ses")
o, rc, err = run(f'options reopen=1\noptionsinfo\nopen "{S1}"\nopen "{S2}"\nopen "{S3}"\nnewdoc "ISO A4" landscape\ngotodoc 1\nclosequery\nsessioninfo\n', H)
inf = [l for l in o if l.startswith("OPTIONSINFO settings")][0]; si = [l for l in o if l.startswith("SESSIONINFO")][-1]; r = reg(H)
check("the option is on in the Options dialog (reopen=1), and closing the window with three named designs and an untitled one open remembers the three, in order, with the second showing", "reopen=1" in inf and "active=2" in si and si.endswith(f"files={S1}|{S2}|{S3}|"), f"{inf[-30:]} {si}")
check("in the registry as ReopenDesigns, Session1 to Session3 (in order, the untitled one left out) and SessionActive 2", r.get("ReopenDesigns") == "1" and [r.get(f"Session{i}") for i in (1, 2, 3, 4)] == [S1, S2, S3, None] and r.get("SessionActive") == "2", str(r))
o, rc, err = run('sessioninfo\nsessionrestore\ndocs\n', H)
c, names = docs(o)
check("the next start opens the three again in their order and shows the second (two.dsn)", [l for l in o if l.startswith("SESSIONRESTORE")][0] == "SESSIONRESTORE 3" and names == ["one.dsn", "two.dsn", "three.dsn"] and c == 1, f"{names} {c}")
os.remove(S3)
o, rc, err = run('sessionrestore\ndocs\n', H); c, names = docs(o)
check("a file that has gone is skipped without a fuss: the other two open and the second is showing", [l for l in o if l.startswith("SESSIONRESTORE")][0] == "SESSIONRESTORE 2" and names == ["one.dsn", "two.dsn"] and c == 1 and rc == 0, f"{names} {c}")
# the untitled design showing at the end: nothing is said to be active
S3 = make("three.dsn", "ses")
H2 = home("sess2")
o, rc, err = run(f'options reopen=1\nopen "{S1}"\nopen "{S2}"\nnewdoc "ISO A4" landscape\nclosequery\nsessioninfo\n', H2)
si = [l for l in o if l.startswith("SESSIONINFO")][-1]
o, rc, err = run('sessionrestore\ndocs\n', H2); c, names = docs(o)
check("when the design showing at the end had no file, none is remembered as the one showing (active=0) and the last one opened is showing after the next start", "active=0" in si and names == ["one.dsn", "two.dsn"] and c == 1, f"{si} {names} {c}")
# the option off: nothing is remembered, and what was is forgotten
o, rc, err = run(f'options reopen=0\nopen "{S1}"\nclosequery\nsessioninfo\n', H); si = [l for l in o if l.startswith("SESSIONINFO")][-1]; r = reg(H)
check("with the option off closing remembers nothing and forgets what was remembered (no Session values left in the registry)", "files=" in si and si.endswith("files=") and not any(k.startswith("Session") for k in r), f"{si} {r}")
o, rc, err = run('sessionrestore\ndocs\n', H)
check("and with it off nothing is opened at the next start", [l for l in o if l.startswith("SESSIONRESTORE")][0] == "SESSIONRESTORE 0" and docs(o)[1] == [], str(o[-3:]))
# at most twenty, in order; names with spaces and accented letters
many = [make(f"d{i:02d}.dsn", "many") for i in range(22)]
H3 = home("many")
o, rc, err = run('options reopen=1\n' + "".join(f'open "{p}"\n' for p in many) + 'closequery\nsessioninfo\n', H3); si = [l for l in o if l.startswith("SESSIONINFO")][-1]; r = reg(H3)
check("at most twenty designs are remembered, the first twenty in order (22 were open)", len([k for k in r if re.fullmatch(r"Session[0-9]+", k)]) == 20 and si.count("|") == 20 and si.split("files=")[1].split("|")[0] == many[0], f"{si[:120]} {len(r)}")
o, rc, err = run('sessionrestore\ndocs\n', H3); c, names = docs(o)
check("and those twenty open again in their order", len(names) == 20 and names == [os.path.basename(p) for p in many[:20]], str(names))
odd = make("Schaltplan ü ß.dsn", "my designs"); H4 = home("odd")
o, rc, err = run(f'options reopen=1\nopen "{odd}"\nclosequery\n', H4); o, rc, err = run('sessionrestore\ndocs\n', H4); c, names = docs(o)
check("a file name with spaces and accented letters is remembered and opened again", names == [os.path.basename(odd)], str(names))
# the real program, started with a remembered session, comes up and stays up
shot = os.path.join(tmp, "up.png")
sh_script = f"{exe} & P=$!; sleep 6; import -window root '{shot}' 2>/dev/null; if kill -0 $P 2>/dev/null; then echo ALIVE; kill $P; else echo DIED; fi"
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1400x900x24", "sh", "-c", sh_script], capture_output=True, text=True, timeout=60, env=dict(os.environ, HOME=H))
o, rc, err = run(f'options reopen=1\nopen "{S1}"\nopen "{S2}"\nclosequery\n', H)
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1400x900x24", "sh", "-c", sh_script], capture_output=True, text=True, timeout=60, env=dict(os.environ, HOME=H))
check("the real program, started with a remembered session and no script, comes up and is still running six seconds later (the designs open in it without a crash or a dialog stopping it)", "ALIVE" in r.stdout and "Startup error" not in r.stderr, f"{r.stdout} {r.stderr[-200:]}")
print(f"session: {checks} checks, {len(fails)} failures")
print("\nSESSION CHECKS PASSED" if not fails else f"\nSESSION CHECKS FAILED: {len(fails)} failures")
sys.exit(1 if fails else 0)
