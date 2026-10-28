import re, glob, os, sys
import sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OLD = sys.argv[1] if len(sys.argv) > 1 else ROOT + '_backup'   # a copy of the folder taken before the change
def strip(src):
    out = []; i = 0; n = len(src)
    while i < n:
        c = src[i]
        if c == "'":
            j = i + 1
            while j < n:
                if src[j] == "'":
                    if j + 1 < n and src[j + 1] == "'": j += 2; continue
                    break
                j += 1
            out.append(src[i:j + 1]); i = j + 1
        elif c == '{' and src.startswith('{$', i):
            j = src.index('}', i); out.append(src[i:j + 1]); i = j + 1     # a compiler directive is code
        elif c == '{':
            j = src.index('}', i); i = j + 1; out.append(' ')
        elif src.startswith('(*', i):
            j = src.index('*)', i); i = j + 2; out.append(' ')
        elif src.startswith('//', i):
            j = src.find('\n', i); i = n if j < 0 else j; out.append(' ')
        else:
            out.append(c); i += 1
    return re.sub(r'\s+', ' ', ''.join(out)).strip()
bad = 0; files = 0
for f in sorted(glob.glob(ROOT + '/src/*.pas') + glob.glob(ROOT + '/src/forms/*.pas') + glob.glob(ROOT + '/src/frames/*.pas') + glob.glob(ROOT + '/tests/drivers/*.pas') + glob.glob(ROOT + '/*.lpr')):
    rel = os.path.relpath(f, ROOT)
    o = os.path.join(OLD, rel)
    if not os.path.exists(o): print('no backup for', rel); continue
    a = strip(open(o, encoding='utf-8', errors='replace').read().replace('\r', ''))
    b = strip(open(f, encoding='utf-8', errors='replace').read().replace('\r', ''))
    files += 1
    if a != b:
        bad += 1; print('CODE CHANGED in', rel)
print(f'{files} files compared: code identical apart from comments in {files - bad}, changed in {bad}')
