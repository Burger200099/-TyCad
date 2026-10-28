#!/usr/bin/env python3
"""Opens a TCParts file at the version this program knows. RULES (the Pascal reader must do the same):
  1. version == CURRENT          : open as is.
  2. version <  CURRENT          : copy the file to <name>.v<old>.bak, then run every step old -> old+1 -> ... -> CURRENT, each in one transaction
                                   that also sets FormatInfo.SchemaVersion, PRAGMA user_version and adds a SchemaHistory row. A step that fails rolls back
                                   and the file stays at the version it had; the backup is kept.
  3. version >  CURRENT          : refuse (a newer program wrote it); never write to it.
  4. Format is not 'TyCAD-Parts' : refuse (not ours; this also keeps TinyCAD files out).
A step is SQL text or a function(connection). Add a new one to STEPS when the schema changes, raise CURRENT, and change parts_schema.sql to the new layout
so that new files and upgraded files end up identical (tests/run_partsupgrade.py compares them).
Usage: parts_upgrade.py <file.TCParts>"""
import os, shutil, sqlite3, sys, datetime
CURRENT = 2
STEPS = {1: "ALTER TABLE Symbol ADD COLUMN ShowsObject INTEGER REFERENCES PartObject(ObjectID);"}          # {from_version: sql text or callable(connection)}   e.g. STEPS[1] = "ALTER TABLE Part ADD COLUMN Gtin TEXT;"
class UpgradeError(Exception): pass
def read_version(c):
    try: f, v = c.execute("select Format, SchemaVersion from FormatInfo").fetchone()
    except sqlite3.DatabaseError as e: raise UpgradeError("not a TyCAD parts file (%s)" % e)
    if f != "TyCAD-Parts": raise UpgradeError("not a TyCAD parts file")
    return v
def upgrade(path, current=None, steps=None, program="parts_upgrade.py"):
    current = CURRENT if current is None else current; steps = STEPS if steps is None else steps
    c = sqlite3.connect(path); c.isolation_level = None
    try:
        v = read_version(c)
        if v == current: return v
        if v > current: raise UpgradeError("the file is version %d, newer than this program (%d): not opened" % (v, current))
        for k in range(v, current):
            if k not in steps: raise UpgradeError("no upgrade step from version %d" % k)
        c.close(); shutil.copyfile(path, "%s.v%d.bak" % (path, v)); c = sqlite3.connect(path); c.isolation_level = None
        for k in range(v, current):
            c.execute("BEGIN")
            try:
                st = steps[k]
                if callable(st): st(c)
                else:
                    for stmt in [x for x in st.split(";\n") if x.strip()]: c.execute(stmt)
                c.execute("update FormatInfo set SchemaVersion=?", (k + 1,))
                c.execute("insert into SchemaHistory values (?,?,?,?,?)", (k, k + 1, datetime.datetime.now().isoformat(timespec="seconds"), program, ""))
                c.execute("PRAGMA user_version=%d" % (k + 1)); c.execute("COMMIT")
            except Exception as e:
                c.execute("ROLLBACK"); raise UpgradeError("step %d -> %d failed and was undone: %s (backup %s.v%d.bak)" % (k, k + 1, e, path, v))
        return current
    finally: c.close()
if __name__ == "__main__":
    try: print("version", upgrade(sys.argv[1]))
    except UpgradeError as e: print("ERROR", e); sys.exit(1)
