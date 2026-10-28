"""Usage: python3 tools/doccomments.py [--apply]
(without --apply it only reports which routines still need a note; routines with no note get
"TODO: describe." and are listed in tools/missing_notes.json. Add notes to tools/notes/*.json.)

Insert a documentation block above every procedure / function / constructor / destructor
implementation. Idempotent: it replaces blocks it wrote earlier. Notes come from, in order:
  1. a manual note (notes/*.json: key "File.pas::Owner.Name" or "Owner.Name" or "Name"),
  2. a template for the standard overrides,
  3. an existing comment that sat directly above the routine (folded into the block).
Routines without any note are reported so a note can be written."""
import re, os, sys, json, glob, textwrap

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # the project folder
RT = re.compile(r'^(class\s+)?(procedure|function|constructor|destructor)\s+([A-Za-z_][\w\.]*)', re.I)
BAR = '=' * 75
MARK_START = '{ ' + BAR
MARK_END = '  ' + BAR + ' }'

def load_notes():
    notes = {}
    for f in sorted(glob.glob(os.path.join(HERE, 'notes', '*.json'))):
        notes.update(json.load(open(f)))
    return notes

def strip_comments_line(s):
    s = re.sub(r"\{[^}]*\}", " ", s)
    s = re.sub(r"\(\*.*?\*\)", " ", s)
    s = s.split('//')[0] if "'" not in s.split('//')[0][-1:] else s
    return s

def split_params(s):
    parts, depth, cur = [], 0, ''
    for ch in s:
        if ch in '([': depth += 1
        elif ch in ')]': depth -= 1
        if ch == ';' and depth == 0: parts.append(cur); cur = ''
        else: cur += ch
    if cur.strip(): parts.append(cur)
    return parts

def parse_header(lines, i):
    """returns (kind, fullname, params, ret, header_end_index, is_class)"""
    text = ''; j = i
    while j < len(lines):
        text += ' ' + strip_comments_line(lines[j]).strip()
        t = text.strip()
        depth = t.count('(') - t.count(')')
        if depth <= 0 and t.endswith(';'): break
        j += 1
    t = re.sub(r'\s+', ' ', text.strip())
    m = re.match(r'^(class\s+)?(procedure|function|constructor|destructor)\s+([\w\.]+)\s*(.*)$', t, re.I)
    kind, name, rest = m.group(2).lower(), m.group(3), m.group(4)
    params, ret = [], ''
    if rest.startswith('('):
        depth = 0
        for k, ch in enumerate(rest):
            if ch == '(': depth += 1
            elif ch == ')':
                depth -= 1
                if depth == 0: break
        inner, after = rest[1:k], rest[k + 1:]
        for part in split_params(inner):
            part = part.strip()
            if not part: continue
            mod = ''
            mm = re.match(r'^(const|var|out|constref)\s+(.*)$', part, re.I)
            if mm: mod, part = mm.group(1).lower(), mm.group(2)
            default = ''
            if '=' in part: part, default = part.split('=', 1); default = default.strip()
            if ':' in part:
                names, typ = part.split(':', 1)
            else:
                names, typ = part, ''
            for n in names.split(','):
                params.append((mod, n.strip(), typ.strip(), default))
    else:
        after = rest
    if kind == 'function':
        mr = re.match(r'^\s*:\s*([^;]+);', after)
        if mr: ret = mr.group(1).strip()
    return kind, name, params, ret, j, bool(m.group(1))

PARAM_NAMES = {
 'w': 'the XML writer to save into', 'r': 'the XML reader, positioned on this element',
 'p': 'a point, in design units', 'q': 'a point, in design units', 'a': 'a point, in design units', 'b': 'a point, in design units',
 'aopts': 'the sheet options (fonts, styles, snap grid, text metrics)', 'opts': 'the sheet options',
 'left': 'left edge', 'right': 'right edge', 'top': 'top edge', 'bottom': 'bottom edge',
 'sender': 'the component that raised the event', 'obj': 'the drawing object', 'index': 'zero-based index',
 'name': 'the name', 'value': 'the value', 'aname': 'the name', 'avalue': 'the value',
 'filename': 'path of the file', 'afilename': 'path of the file', 'adesign': 'the design', 'design': 'the design',
 'asheet': 'the sheet', 'sheet': 'the sheet', 'asheetindex': 'zero-based sheet number', 'sheetindex': 'zero-based sheet number',
 'x': 'horizontal position or value', 'y': 'vertical position or value', 'key': 'key code', 'shift': 'modifier keys held down',
 'button': 'which mouse button', 'amsg': 'the message', 'msg': 'the message', 'dest': 'the stream to write to',
 'acaption': 'caption text', 'ahandler': 'event handler to call', 'canclose': 'set False to stop the window closing',
 'powerpoint': 'a point', 'str': 'the text', 'text': 'the text', 'acanvas': 'the canvas to draw on', 'atransform': 'the screen transform',
}

def describe_param(mod, name, typ):
    d = PARAM_NAMES.get(name.lower(), '')
    t = typ.lower()
    if not d:
        if t.startswith('tdpoint'): d = 'a point, in design units'
        elif t == 'boolean': d = 'flag'
        elif t == 'string': d = 'text'
        elif t == 'integer': d = 'whole number'
        elif t == 'double': d = 'number'
        elif t == 'tobject': d = 'the object that raised the event'
    mods = {'const': 'read-only', 'var': 'in/out: changed by the call', 'out': 'out: set by the call', 'constref': 'read-only'}
    extra = mods.get(mod, '')
    if d and extra and mod in ('var', 'out'): d = d + ' (' + extra + ')'
    elif not d and extra and mod in ('var', 'out'): d = extra
    return d

def wrap(text, indent, width=96):
    out = []
    for para in text.split('\n'):
        out += textwrap.wrap(para, width=width - len(indent), break_long_words=False) or ['']
    return [indent + l if l else '' for l in out]

def build_block(kind, name, params, ret, note, pdesc):
    L = [MARK_START, '  ' + name + '  (' + kind + ')']
    L.append('  Parameters:' + ('  none' if not params else ''))
    for mod, n, t, dflt in params:
        desc = pdesc.get(n) or describe_param(mod, n, t)
        head = '    ' + ((mod + ' ') if mod else '') + n + (': ' + t if t else '')
        if dflt: head += ' = ' + dflt
        line = head + (' - ' + desc if desc else '')
        L += wrap(line, '', 96) if len(line) <= 96 else [line[:96]] + wrap(line[96:], '      ', 96)
    if kind == 'function':
        r = ret or '?'
        L.append('  Returns:')
        L += wrap(r + (' - ' + note['returns'] if note.get('returns') else ''), '    ')
    L.append('  Notes:')
    L += wrap(note['text'], '    ')
    L.append(MARK_END)
    return L

def collect_existing(lines, i):
    """contiguous comment lines directly above line i (not section banners and not generated blocks)"""
    j = i - 1; got = []
    while j >= 0:
        s = lines[j].strip()
        if s == '': break
        if s.startswith('{') and ('----' in s or '====' in s): break
        if s.startswith('//') or (s.startswith('{') and s.endswith('}')) or s.endswith('}'):
            got.append(j); j -= 1
            if lines[j + 1].strip().startswith('{') or lines[j + 1].strip().startswith('//'): 
                if not lines[j + 1].strip().endswith('}') and not lines[j + 1].strip().startswith('//'): pass
            continue
        break
    return list(reversed(got))

def clean_comment(lines, idxs):
    txt = ' '.join(lines[k].strip() for k in idxs)
    txt = re.sub(r'^\{\s*', '', txt); txt = re.sub(r'\s*\}$', '', txt)
    txt = txt.replace('//', ' ').replace('{', ' ').replace('}', ' ')
    return re.sub(r'\s+', ' ', txt).strip()

def process(path, notes, templates, apply=True):
    src = open(path, encoding='utf-8', errors='replace').read().replace('\r', '')
    lines = src.split('\n')
    base = os.path.basename(path)
    impl = next((k for k, l in enumerate(lines) if l.strip().lower() == 'implementation'), 0)
    out, i, missing, count = [], 0, [], 0
    while i < len(lines):
        l = lines[i]
        if i >= impl and RT.match(l):
            # drop a generated block directly above (idempotence)
            while out and out[-1].strip() == '': out.pop(); 
            prev_note = ''
            if out and out[-1].rstrip().endswith('}') and MARK_END.strip() in out[-1]:
                blk = []
                while out and not out[-1].startswith(MARK_START): blk.append(out.pop())
                if out: blk.append(out.pop())
                blk = list(reversed(blk))
                if '  Notes:' in blk:
                    k0 = blk.index('  Notes:')
                    prev_note = ' '.join(x.strip() for x in blk[k0 + 1:-1]).strip()
            blank_before = bool(out)
            # fold an existing description sitting directly above
            ex_idx = []
            k = len(out) - 1
            while k >= 0:
                s = out[k].strip()
                if s == '' : break
                if s.startswith('{') and ('----' in s or '====' in s): break
                if s.startswith('{$'): break          # a compiler directive ({$R *.lfm}, {$IFDEF ...}) is code, not a comment
                if s.startswith('//') or (s.startswith('{') and s.endswith('}')): ex_idx.append(k); k -= 1; continue
                break
            existing = ''
            if ex_idx:
                existing = clean_comment(out, list(reversed(ex_idx)))
                for _ in ex_idx: out.pop()
            kind, name, params, ret, hend, isclass = parse_header(lines, i)
            body = '\n'.join(lines[hend + 1: hend + 40])
            key1, key2 = base + '::' + name, name
            kn = '#%d' % len(params)
            kt = ('@' + params[-1][2].lower()) if params else ''
            short = name.split('.')[-1]
            n = notes.get(base + '::' + name + kt) or notes.get(name + kt) or notes.get(base + '::' + name + kn) or notes.get(name + kn) or notes.get(key1) or notes.get(key2) or templates(name, short, kind, params, ret, body)
            if isinstance(n, str): n = {'text': n}
            if n is None and prev_note and prev_note != 'TODO: describe.': n = {'text': prev_note}
            elif n is None and existing: n = {'text': existing[0].upper() + existing[1:]}
            elif n is not None and existing and existing.lower() not in n['text'].lower() and not (notes.get(key1) or notes.get(key2) or notes.get(name + kn) or notes.get(base + '::' + name + kn) or notes.get(name + kt) or notes.get(base + '::' + name + kt)):
                n = dict(n); n['text'] = n['text'] + ' ' + existing[0].upper() + existing[1:]
            if n is None:
                missing.append((base, name, kind, params, ret, '\n'.join(lines[hend + 1: hend + 9])))
                n = {'text': 'TODO: describe.'}
            while out and out[-1].strip() == '': out.pop()   # (a previous run's blank line)
            if out: out.append('')   # exactly one blank line before the block
            out += build_block(kind, name, params, ret, n, n.get('params', {}))
            count += 1
        out.append(l)
        i += 1
    new = '\n'.join(out)
    if apply: open(path, 'w', encoding='utf-8').write(new)
    return count, missing

def all_files():
    fs = sorted(glob.glob(ROOT + '/src/*.pas') + glob.glob(ROOT + '/src/forms/*.pas') + glob.glob(ROOT + '/src/frames/*.pas') + glob.glob(ROOT + '/tests/drivers/*.pas') + glob.glob(ROOT + '/*.lpr'))
    return [f for f in fs]


def templates(name, short, kind, params, ret, body):
    owner = name.split('.')[0] if '.' in name else ''
    pnames = [p[1].lower() for p in params]
    isobj = owner.startswith('TDraw')
    tag = ''
    m = re.search(r"BeginTag\(W,\s*'(\w+)'", body) or re.search(r"W\.AddTag\('(\w+)'\)", body)
    if m: tag = m.group(1)
    if isobj and short == 'Create' and 'aopts' in pnames:
        return {'text': 'Creates a new %s that belongs to the sheet whose options are AOpts, and gives its properties their default values.' % owner}
    if isobj and short == 'CreateKind':
        return {'text': 'Creates a new %s of the kind AKind (for example wire versus bus, or circle versus rectangle) belonging to the sheet options AOpts, with default properties.' % owner}
    if isobj and short == 'Destroy':
        return {'text': 'Frees what this %s owns and then calls the inherited destructor.' % owner}
    if isobj and short == 'SaveXML':
        t = (' <%s>' % tag) if tag else ''
        return {'text': 'Writes this %s as an XML%s element using W: opens the tag, adds its attributes (and any child elements), then closes it. Only non-default content that the file format knows about is written. The object id is written as oid when it has one.' % (owner, t)}
    if isobj and short == 'LoadXML':
        return {'text': 'Reads this %s from the XML element R is positioned on. An attribute that is missing leaves the default value set by the constructor. Resource numbers (fonts, line styles, fills) are converted to this sheet\'s numbering.' % owner}
    if isobj and short == 'GetType':
        mm = re.search(r'Result\s*:=\s*(\w+)', body)
        return {'text': 'Identifies this class\'s kind of object. The file format, hit testing and the netlist use the code to tell objects apart.', 'returns': ('the TObjType code ' + mm.group(1)) if mm else 'the object kind'}
    if isobj and short == 'Clone':
        return {'text': 'Makes an independent copy of this %s (same geometry and properties). The copy has no object id; whoever uses it adds it to a sheet.' % owner, 'returns': 'the new object; the caller owns it and must free it or add it to a list that does'}
    if isobj and short == 'IsInside':
        return {'text': 'Selection test. True when the object touches the rectangle Left..Right by Top..Bottom (internal units). A rectangle that is a single point is a click test.', 'returns': 'True if the object is selected by that rectangle'}
    if isobj and short == 'DistanceFromPoint':
        return {'text': 'Distance from the point P to the object, in internal units, used to decide what a click hits: 0 means P is on the object, large values mean it is far away.', 'returns': 'the distance in internal units (capped at 100 for objects that are only hit directly)'}
    if isobj and short == 'TagResources':
        return {'text': 'Marks the fonts, line styles and fill styles this object uses as in use, so that they are written to the file and unused ones are dropped.'}
    if isobj and short == 'RotateAbout':
        return {'text': 'Rotates or mirrors the object about the point P. NewDir is the rotation / mirror code (0 to 7) used throughout TinyCAD.'}
    if isobj and short == 'UpdateLayout':
        return {'text': 'Recalculates geometry that depends on text sizes or on other data (text boxes, label and pin text positions) using the current text metrics.'}
    if isobj and short == 'IsEmpty':
        return {'text': 'True when the object holds nothing worth keeping (for example a polygon with fewer than two points), so the loader discards it.', 'returns': 'True if the object should be discarded'}
    if isobj and short == 'IsConstruction':
        return {'text': 'True for objects that only help while editing (such as ruler guides) and are not part of a symbol\'s drawing.', 'returns': 'True for construction objects'}
    return None

if __name__ == '__main__':
    notes = load_notes()
    apply = '--apply' in sys.argv
    total = miss = 0; rows = []
    for f in all_files():
        c, m = process(f, notes, templates, apply=apply)
        total += c; miss += len(m)
        rows += m
        print('%-24s routines=%4d  need a note=%4d' % (os.path.basename(f), c, len(m)))
    print('TOTAL', total, 'need a note', miss)
    if rows: json.dump([[a, b, c, d, e, f] for a, b, c, d, e, f in rows], open(os.path.join(HERE, 'missing_notes.json'), 'w'))
