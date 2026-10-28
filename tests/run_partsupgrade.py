#!/usr/bin/env python3
"""Schema versioning of the parts file (docs/parts_upgrade.py). Oracle: sqlite itself (sqlite_master, PRAGMA user_version) read back after each case.
Cases: current file untouched; old file upgraded through two steps with history, backup and version numbers; a failing step rolls back (nothing half done);
a newer file and a foreign file refused without being written; an upgraded file and a new file of the same version have the same tables and columns."""
import os, sys, sqlite3, tempfile, shutil, hashlib
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, "..", "docs"))
import parts_seed, parts_upgrade as U
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:300])
tmp = tempfile.mkdtemp(); f = os.path.join(tmp, "a.TCParts"); parts_seed.build(f).close()
sha = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
h = sha(f); check("a file at the current version is opened untouched (same bytes, no backup)", U.upgrade(f) == U.CURRENT and sha(f) == h and not os.path.exists(f + ".v1.bak"))
check("a new file has the version in both places", sqlite3.connect(f).execute("pragma user_version").fetchone()[0] == U.CURRENT == sqlite3.connect(f).execute("select SchemaVersion from FormatInfo").fetchone()[0])
steps = {1: "ALTER TABLE Part ADD COLUMN Gtin TEXT;\nCREATE INDEX idx_part_gtin ON Part(Gtin);", 2: lambda c: c.execute("update Product set Series='x' where Series is null")}
v = U.upgrade(f, current=3, steps=steps)
c = sqlite3.connect(f); cols = [r[1] for r in c.execute("pragma table_info(Part)")]
check("an old file goes through both steps: columns, data, version numbers and history", v == 3 and "Gtin" in cols and c.execute("select SchemaVersion from FormatInfo").fetchone()[0] == 3
      and c.execute("pragma user_version").fetchone()[0] == 3 and c.execute("select FromVersion,ToVersion from SchemaHistory order by 1").fetchall() == [(1, 2), (2, 3)]
      and c.execute("select count(*) from Product where Series is null").fetchone()[0] == 0, (v, cols))
check("the backup is the old file, at its old version", os.path.exists(f + ".v1.bak") and sqlite3.connect(f + ".v1.bak").execute("select SchemaVersion from FormatInfo").fetchone()[0] == 1)
g = os.path.join(tmp, "b.TCParts"); parts_seed.build(g).close()
bad = {1: "ALTER TABLE Part ADD COLUMN Ok1 TEXT;", 2: "ALTER TABLE NoSuchTable ADD COLUMN x TEXT;"}
try: U.upgrade(g, current=3, steps=bad); raised = False
except U.UpgradeError: raised = True
c = sqlite3.connect(g)
check("a failing step stops the upgrade; steps already done stay (version 2), the failed one leaves nothing", raised and c.execute("select SchemaVersion from FormatInfo").fetchone()[0] == 2
      and "Ok1" in [r[1] for r in c.execute("pragma table_info(Part)")] and c.execute("select count(*) from SchemaHistory").fetchone()[0] == 1)
d = os.path.join(tmp, "c.TCParts"); parts_seed.build(d).close(); hd = sha(d)
try: U.upgrade(d, current=0, steps={}); r2 = False
except U.UpgradeError: r2 = True
check("a file newer than the program is refused and not written", r2 and sha(d) == hd)
e = os.path.join(tmp, "e.sqlite"); x = sqlite3.connect(e); x.execute("create table t(a)"); x.commit(); x.close(); he = sha(e)
try: U.upgrade(e); r3 = False
except U.UpgradeError: r3 = True
check("a database that is not a TyCAD parts file (a TinyCAD library, say) is refused and not written", r3 and sha(e) == he)
try: U.upgrade(os.path.join(tmp, "a.TCParts"), current=5, steps={}); r4 = False
except U.UpgradeError: r4 = True
check("a missing step is refused before anything is written", r4)
print("%d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
