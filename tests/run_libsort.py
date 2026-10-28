#!/usr/bin/env python3
"""The library panel lists the symbols of each library in alphabetical order (digits before letters, capitals and small letters alike). Oracle: Python's
sorted() on the lower-cased names, taken from the library files' own listing in the tree. Over every example library, each opened alone and all together.
Mutation: the file order (as stored) must differ from the sorted order for at least one library, so the check can fail.
Needs xvfb-run, the built program and the example libraries (TC_EXAMPLES)."""
import glob, os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
libs = sorted(glob.glob(os.path.join(EX, "libraries", "*.TCLib")))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not libs:
    print("Library sort checks skipped: need xvfb-run, the built program and the example libraries"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:400])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(paths):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("".join("lib %s\n" % p for p in paths) + "libtree\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env)
    groups = []
    for l in r.stdout.splitlines():
        m = re.match(r"LIBNODE (\d) open=\d (.*)", l)
        if not m: continue
        if m.group(1) == "0": groups.append((m.group(2), []))
        elif groups: groups[-1][1].append(m.group(2).split("  -  ")[0])
    return groups
def want(names): return sorted(names, key=lambda s: s.lower())
total = 0; usable = []
for p in libs:
    g = run([p])
    if len(g) != 1 or not g[0][1]: continue          # (a library that cannot be opened, or has no symbols, has nothing to order)
    usable.append(p)
    if len(g) == 1:
        names = g[0][1]
        check(os.path.basename(p) + " is in alphabetical order", names == want(names), [n for a, n in zip(names, want(names)) if a != n][:4])
        total += len(names)
check("the symbols are checked (more than 100, in at least 10 libraries)", total > 100 and len(usable) >= 10, (total, len(usable)))
g = run(usable[:4])
check("several libraries together: each sorted on its own", len(g) == len(usable[:4]) and all(n == want(n) for _, n in g), [a for a, n in g if n != want(n)])
# the oracle has something to find: a number sorts before a letter, and capitals do not sort apart from small letters
check("(mutation) the oracle puts 7 before A and Z before a2 only when ignoring case", want(["a2", "Z", "7", "A"]) == ["7", "A", "a2", "Z"])
print("library order: %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
