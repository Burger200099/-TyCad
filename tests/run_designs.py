import os
EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")   # folder holding your .dsn / .TCLib files
BUILD = os.environ.get("TC_BUILD", "build")             # folder with the compiled designtest / libtest
WORK = os.environ.get("TC_WORK", "work")                # scratch folder for outputs
import subprocess, sys, hashlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from canon import canon_file, diff
exe = os.path.join(BUILD, 'designtest')
root = EXAMPLES
files = sorted(os.path.join(r, f) for r, _, fs in os.walk(root) for f in fs if f.lower().endswith(('.dsn', '.autosave')))
os.makedirs(os.path.join(WORK, 'out'), exist_ok=True)
res = {'load_fail': [], 'sem_fail': [], 'idem_fail': [], 'ok': 0}
for p in files:
    tag = hashlib.md5(p.encode()).hexdigest()[:8]
    o1, o2 = os.path.join(WORK, 'out', f'{tag}.1.dsn'), os.path.join(WORK, 'out', f'{tag}.2.dsn')
    r = subprocess.run([exe, 'rt', p, o1], capture_output=True, text=True)
    if r.returncode != 0:
        res['load_fail'].append((p, (r.stdout + r.stderr).strip()[:200])); continue
    # semantic check: original vs saved
    try:
        a, b = canon_file(p), canon_file(o1)
        d = diff(a, b)
    except Exception as e:
        d = [('canon-exception', repr(e)[:200], '')]
    # idempotence: save(load(saved)) must equal saved byte for byte
    r2 = subprocess.run([exe, 'rt', o1, o2], capture_output=True, text=True)
    idem = r2.returncode == 0 and open(o1, 'rb').read() == open(o2, 'rb').read()
    if d: res['sem_fail'].append((os.path.relpath(p, root), d))
    if not idem: res['idem_fail'].append(os.path.relpath(p, root))
    if not d and idem: res['ok'] += 1
print(f"files: {len(files)}  fully OK: {res['ok']}  load failures: {len(res['load_fail'])}  semantic diffs: {len(res['sem_fail'])}  not idempotent: {len(res['idem_fail'])}")
for x in res['load_fail'][:5]: print('LOAD', x)
for name, d in res['sem_fail'][:8]:
    print('SEM', name)
    for e in d[:3]: print('     ', e)
for x in res['idem_fail'][:5]: print('IDEM', x)
