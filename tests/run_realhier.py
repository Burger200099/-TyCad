#!/usr/bin/env python3
"""Two designs written by TinyCAD 3.00.04 (tests/data/hier: tCad2 places tCad1, which has a symbol sheet with one pin and an empty sheet). Checks what is known of
TinyCAD's behaviour for them: both read; the placed design's symbol is the 'No Symbol Defined' entry whose reference prefix is H? (so annotate gives it H1);
the netlist has one node, the pin, alone on its own net with the reference empty (the placed design's Ref field is empty); the parts list has no parts.
Needs the built annotest, nettest and bomtest."""
import os, subprocess, sys, tempfile
BUILD = os.environ.get("TC_BUILD", "build"); HERE = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(HERE, "data", "hier", "tCad2.dsn")
for n in ("annotest", "nettest", "bomtest"):
    if not os.path.exists(os.path.join(BUILD, n)): print("Real hierarchical checks skipped: build", n); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:300])
def run(*a): return subprocess.run([os.path.join(BUILD, a[0])] + list(a[1:]), capture_output=True, text=True)
r = run("annotest", "dump", src)
check("the placed design is listed with prefix H?", " H? 1 0 - H0" in r.stdout and r.stdout.startswith("M 0 0 0  0 "), r.stdout + r.stderr)
r = run("annotest", "run", src, os.path.join(tmp, "o.dsn"), "1", "0", "0", "U?", "1", "0", "0")
check("annotate numbers it H1", "R 0" in r.stdout and " H1 0 " in r.stdout, r.stdout + r.stderr)
r = run("nettest", "nodes", src)
rows = [l.split("\t") for l in r.stdout.split("\n") if l.startswith("NODE")]
check("one node: the pin, on net 1, with an empty reference", len(rows) == 1 and rows[0][1] == "1" and rows[0][4] == "" and rows[0][6] == "P", r.stdout)
r = run("bomtest", src, os.path.join(tmp, "b.csv"), "1", "1", "1", "0", src, "1")
check("the parts list has no parts", "ENTRIES 0" in r.stdout, r.stdout + r.stderr)
print("real TinyCAD hierarchical files: %d checks, %d failed" % (checks, len(fails))); sys.exit(1 if fails else 0)
