import os
EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")   # folder holding your .dsn / .TCLib files
BUILD = os.environ.get("TC_BUILD", "build")             # folder with the compiled designtest / libtest
WORK = os.environ.get("TC_WORK", "work")                # scratch folder for outputs
import sys, glob, subprocess, sqlite3, shutil, hashlib
import xml.etree.ElementTree as ET
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from canon import Ctx, canon_objects, canon_symbol, pt, diff
exe = os.path.join(BUILD, 'libtest')
env = dict(os.environ)  # set LD_LIBRARY_PATH if libsqlite3.so is not on the default path
libs = sorted(glob.glob(EXAMPLES + '/libraries/*.TCLib'))
work = os.path.join(WORK, 'lib'); shutil.rmtree(work, ignore_errors=True); os.makedirs(work)
def run(*a): return subprocess.run([exe, *a], capture_output=True, env=env)
def esc(s): return s.replace('\\', '\\\\').replace('\r', '\\r').replace('\n', '\\n').replace('|', '\\p')

def py_dump(path):
    c = sqlite3.connect(path); out = []
    rows = c.execute("SELECT NameID,Name,SymbolID,Reference,ppp,Description,ShowName,ShowRef,DefRotate FROM Name WHERE Type=0 ORDER BY NameID").fetchall()
    sets = {}
    for r in rows: sets.setdefault(r[2], []).append(r)
    for sid in sorted(sets):
        rs = sets[sid]
        out.append(f"SET {sid} {(rs[0][4] or 0) & 255} {rs[0][8]} {len(rs)}")
        for r in rs:
            out.append(f"REC {r[0]}|{esc(r[1] or '')}|{esc(r[3] or '')}|{esc(r[5] or '')}|{r[6]}|{r[7]}")
            for a in c.execute("SELECT AttName,AttValue,ShowAtt FROM Attribute WHERE NameID=? ORDER BY AttributeID", (r[0],)):
                out.append(f"FLD {esc(a[0] or '')}|{esc(a[1] or '')}|{a[2]}")
    return out

def sheets_of(root):
    return root.findall('TinyCAD') if root.tag == 'TinyCADSheets' else [root]

def canon_symdoc(data):
    root = ET.fromstring(data)
    res = []
    for sh in sheets_of(root):
        origin = None
        for e in sh:
            if e.tag == 'ORIGIN': origin = pt(e.get('pos')); break
        res.append((origin, canon_objects(sh, Ctx(sh), False)))
    return (root.tag == 'TinyCADSheets', tuple(res))

stats = dict(libs=0, sets=0, recs=0, dump_bad=0, blob_bad=0, sym_bad=0, sym_placed=0, rt_bad=0, rt_idem_bad=0, rt_never_converge=0, rt_byte_same=0, rt_n=0, copy_bad=0, copy_blob_bad=0, errors=[])
first_diffs = []
for lib in libs:
    name = os.path.basename(lib); stats['libs'] += 1
    c = sqlite3.connect(lib)
    # 1. dump
    r = run('dump', lib)
    if r.returncode != 0: stats['errors'].append((name, 'dump', r.stdout[-200:] + r.stderr[-200:])); continue
    got = r.stdout.decode('utf-8', 'replace').splitlines(); exp = py_dump(lib)
    stats['sets'] += sum(1 for l in exp if l.startswith('SET')); stats['recs'] += sum(1 for l in exp if l.startswith('REC'))
    if got != exp: stats['dump_bad'] += 1; first_diffs.append((name, 'dump', next(((a, b) for a, b in zip(got, exp) if a != b), (len(got), len(exp)))))
    # 2. raw blobs
    bd = f'{work}/{name}.blobs'; os.makedirs(bd)
    run('blobs', lib, bd)
    sids = sorted(set(x[0] for x in c.execute("SELECT SymbolID FROM Name WHERE Type=0")))
    for sid in sids:
        raw = c.execute("SELECT Data FROM Symbol WHERE SymbolID=?", (sid,)).fetchone()[0]
        if not os.path.exists(f'{bd}/{sid}.xml') or open(f'{bd}/{sid}.xml', 'rb').read() != raw:
            stats['blob_bad'] += 1
    # 3. symbols placed into a design: canonical content vs DB + blob
    out = f'{work}/{name}.dsn'; r = run('symbols', lib, out)
    if r.returncode != 0: stats['errors'].append((name, 'symbols', (r.stdout + r.stderr)[-300:])); stats['sym_bad'] += 1
    else:
        root = ET.parse(out).getroot(); sheet = root.find('TinyCAD'); ctx = Ctx(sheet)
        symobjs = [e for e in sheet if e.tag == 'SYMBOL']
        # expected, in placement order: sets by SymbolID, records by NameID
        expected = []
        for sid in sids:
            raw = c.execute("SELECT Data FROM Symbol WHERE SymbolID=?", (sid,)).fetchone()[0]
            broot = ET.fromstring(raw); het = broot.tag == 'TinyCADSheets'
            blocks = tuple(canon_objects(sh, Ctx(sh), True) for sh in sheets_of(broot))
            for (nid, nm, ref, ppp, desc, sn, sr) in c.execute("SELECT NameID,Name,Reference,ppp,Description,ShowName,ShowRef FROM Name WHERE SymbolID=? AND Type=0 ORDER BY NameID", (sid,)):
                flds = tuple((a or '', v or '', t, '', (0.0, 0.0)) for a, v, t in c.execute("SELECT AttName,AttValue,ShowAtt FROM Attribute WHERE NameID=? ORDER BY AttributeID", (nid,)))
                expected.append(('SYM', nm or '', sn, ref or '', sr, desc or '', (ppp or 0) & 255, '', flds, (), het, blocks))
        if len(symobjs) != len(expected): stats['sym_bad'] += 1; first_diffs.append((name, 'symbols', f'{len(symobjs)} placed vs {len(expected)} expected'))
        else:
            stats['sym_placed'] += len(symobjs); bad = 0
            for so, ex in zip(symobjs, expected):
                got_sym = canon_symbol(ctx.symdefs[int(so.get('id'))], ctx)
                if got_sym != ex:
                    bad += 1
                    if len(first_diffs) < 6: first_diffs.append((name, 'symbol ' + ex[1], diff(ex, got_sym, limit=2)))
            stats['sym_bad'] += bad
    # 4. blob round trip through the symbol document
    rd = f'{work}/{name}.rt'; os.makedirs(rd); run('blobrt', lib, rd)
    for sid in sids:
        raw = open(f'{bd}/{sid}.xml', 'rb').read(); stats['rt_n'] += 1
        try:
            rt1 = open(f'{rd}/{sid}.rt.xml', 'rb').read(); rt2 = open(f'{rd}/{sid}.rt2.xml', 'rb').read()
            if canon_symdoc(raw) != canon_symdoc(rt1):
                stats['rt_bad'] += 1
                if len(first_diffs) < 6: first_diffs.append((name, f'blobrt {sid}', diff(canon_symdoc(raw), canon_symdoc(rt1), limit=2)))
            rt3 = open(f'{rd}/{sid}.rt3.xml', 'rb').read()
            if rt1 != rt2: stats['rt_idem_bad'] += 1
            if rt2 != rt3: stats['rt_never_converge'] += 1
            if rt1 == raw: stats['rt_byte_same'] += 1
        except Exception as e: stats['rt_bad'] += 1; stats['errors'].append((name, 'blobrt', repr(e)[:200]))
    # 5. write path: copy into a brand new library
    dst = f'{work}/{name}.copy.TCLib'; r = run('copylib', lib, dst)
    if r.returncode != 0: stats['copy_bad'] += 1; stats['errors'].append((name, 'copylib', (r.stdout + r.stderr)[-300:])); continue
    d = sqlite3.connect(dst)
    schema = lambda cc: sorted(x for x in cc.execute("select type,name,sql from sqlite_master where name not like 'sqlite_%'"))
    if schema(c) != schema(d): stats['copy_bad'] += 1; first_diffs.append((name, 'copy schema', 'differs'))
    if d.execute("pragma integrity_check").fetchone()[0] != 'ok': stats['copy_bad'] += 1
    def logical(cc):
        res = []
        for sid in sorted(set(x[0] for x in cc.execute("SELECT SymbolID FROM Name WHERE Type=0"))):
            names = []
            for (nid, nm, ref, ppp, desc, sn, sr, rot) in cc.execute("SELECT NameID,Name,Reference,ppp,Description,ShowName,ShowRef,DefRotate FROM Name WHERE SymbolID=? ORDER BY NameID", (sid,)):
                flds = tuple(cc.execute("SELECT AttName,AttValue,ShowAtt FROM Attribute WHERE NameID=? ORDER BY AttributeID", (nid,)).fetchall())
                names.append((nm, ref, ppp, desc, sn, sr, rot, flds))
            blob = cc.execute("SELECT Data FROM Symbol WHERE SymbolID=?", (sid,)).fetchone()[0]
            res.append((tuple(names), canon_symdoc(blob)))
        return res
    a, b = logical(c), logical(d)
    if a != b:
        stats['copy_bad'] += 1
        k = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), 'len'); first_diffs.append((name, 'copy content', k))
    # orphan check: the new library must have exactly one Symbol row per set
    if d.execute("select count(*) from Symbol").fetchone()[0] != len(a): stats['copy_bad'] += 1; first_diffs.append((name, 'orphans', 'Symbol row count'))
    stats['sets_copied'] = stats.get('sets_copied', 0) + len(a)

print({k: v for k, v in stats.items() if k != 'errors'})
for e in stats['errors'][:6]: print('ERR', e)
for d_ in first_diffs[:8]: print('DIFF', d_)
