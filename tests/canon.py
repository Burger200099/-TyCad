"""Semantic canonicalisation of TinyCAD designs, written from the C++ semantics (not from the Pascal port)."""
import xml.etree.ElementTree as ET
import math

HEAD_FONT = (-13, 0, 400, 0, 0, 0, 0, 'Arial')
HEAD_STYLE = (0, 1, 0)
HEAD_FILL = (-1, 0)
DEFAULT_COLORS = {'WIRE': 0xFF0000, 'BUS': 0x0000FF, 'JUNCTION': 0, 'NOCONNECT': 0, 'LABEL': 0x208000,
                  'POWER': 0, 'PIN': 0x4040C0, 'HIDDEN_PIN': 0x208020, 'BACKGROUND': 0xFFFFFF,
                  'NOTETEXT_FILL': 0xAFFFFF, 'NOTETEXT_LINE': 0xFF0000, 'NOTETEXT_TEXT': 0xFF0000}

def f(x):
    v = round(float(x), 5) + 0.0
    return v

def pt(s, default=(0.0, 0.0)):
    if s is None: return default
    a, b = s.split(',')
    return (f(a), f(b))

def toint(s, d=0):
    if s is None: return d
    try: return int(s.strip().split('.')[0]) if s.strip() else d
    except ValueError: return d

def hexint(s, d=0):
    if s is None or not s.strip(): return d
    return int(s.strip(), 16)

def text(el, tag, d=''):
    c = el.find(tag)
    return (c.text or '') if c is not None else d

class Ctx:
    def __init__(self, sheet):
        self.fonts, self.styles, self.fills, self.symdefs = {}, {}, {}, {}
        self.colors = dict(DEFAULT_COLORS)
        for el in sheet:
            if el.tag == 'FONT':
                self.fonts[toint(el.get('id'))] = (toint(text(el,'HEIGHT','-13')), toint(text(el,'WIDTH','0')),
                    toint(text(el,'WEIGHT','400')), toint(text(el,'ITALIC','0')), toint(text(el,'UNDERLINE','0')),
                    toint(text(el,'STRIKEOUT','0')), toint(text(el,'CHARSET','0')), text(el,'FACENAME','Arial'))
            elif el.tag == 'STYLE':
                self.styles[toint(el.get('id'))] = (toint(text(el,'STYLE','0')), toint(text(el,'THICKNESS','1')), hexint(text(el,'COLOR','0')))
            elif el.tag == 'FILL':
                self.fills[toint(el.get('id'))] = (toint(text(el,'INDEX','-1')), hexint(text(el,'COLOR','0')))
            elif el.tag == 'SYMBOLDEF':
                self.symdefs[toint(el.get('id'))] = el
            elif el.tag == 'OPTIONS':
                for c in el:
                    if c.tag.startswith('COLOR_'): self.colors[c.tag[6:]] = hexint(c.text)
        self._symcache = {}
    def font(self, s):  return self.fonts.get(toint(s), HEAD_FONT)
    def style(self, s): return self.styles.get(toint(s), HEAD_STYLE)
    def fill(self, s):  return self.fills.get(toint(s), HEAD_FILL)
    def symbol(self, s):
        i = toint(s)
        if i in self._symcache: return self._symcache[i]
        el = self.symdefs.get(i)
        r = ('NOSYMBOL',) if el is None else canon_symbol(el, self)
        self._symcache[i] = r
        return r

def canon_obj(el, ctx):
    t, a = el.tag, el.attrib
    txt = el.text or ''
    if t in ('WIRE', 'BUS'):
        return (t, ctx.style(a['style']) if 'style' in a else 'default', pt(a.get('a')), pt(a.get('b')))
    if t == 'LINE':
        return (t, ctx.style(a.get('style', '0')), pt(a.get('a')), pt(a.get('b')))
    if t in ('JUNCTION', 'NOCONNECT'):
        return (t, pt(a.get('pos')))
    if t == 'BUSSLASH':
        return (t, pt(a.get('pos')), toint(a.get('direction'), 0) & 255)
    if t == 'ORIGIN':
        return (t, pt(a.get('pos')))
    if t in ('RECTANGLE', 'ELLIPSE'):
        return (t, pt(a.get('a')), pt(a.get('b')), ctx.style(a.get('style', '0')), ctx.fill(a.get('fill', '0')))
    if t == 'POLYGON':
        pos = pt(a.get('pos'))
        pts = []
        for p in el.findall('POINT'):
            q = pt(p.get('pos'))
            arc = toint(p.get('arc'), 0)
            ctl = None
            if p.get('control') is not None:
                arc = 3; c = pt(p.get('control')); ctl = (f(c[0] + pos[0]), f(c[1] + pos[1]))
            pts.append((f(q[0] + pos[0]), f(q[1] + pos[1]), arc, ctl))
        fillraw = toint(a.get('fill', '0')) & 0xFFFF
        close = 1 if fillraw != 0 else toint(a.get('polygon'), 0)
        return (t, ctx.style(a.get('style', '0')), ctx.fill(a.get('fill', '0')), close, tuple(pts))
    if t in ('TEXT', 'BUSNAME'):
        defcol = ctx.colors['LABEL'] if t == 'BUSNAME' else 0
        return (t, pt(a.get('pos')), toint(a.get('direction'), 3) & 255, ctx.font(a.get('font', '0')), hexint(a.get('color'), defcol), txt)
    if t == 'LABEL':
        return (t, pt(a.get('pos')), toint(a.get('direction'), 3) & 255, ctx.font(a.get('font', '0')),
                hexint(a.get('color'), ctx.colors['LABEL']), toint(a.get('style'), 0), txt)
    if t == 'POWER':
        return (t, pt(a.get('pos')), toint(a.get('which'), 0) & 255, toint(a.get('direction'), 1) & 255, txt)
    if t == 'PIN':
        which = toint(a.get('which'), 0) & 255
        length = (toint(a.get('length'), 30) & 0xFFFF)
        if length < 5 and length != 0: length = 20
        centre = toint(a.get('centre_name')) if a.get('centre_name') is not None else (1 if which == 4 else 0)
        return (t, pt(a.get('pos')), which, toint(a.get('elec'), 0) & 255, toint(a.get('direction'), 0) & 255,
                toint(a.get('part'), 0) & 255, a.get('number', '1'), toint(a.get('show'), 3) & 255, length,
                toint(a.get('number_pos'), 0), centre, txt)
    if t == 'NOTE_TEXT':
        return (t, pt(a.get('a')), pt(a.get('b')), toint(a.get('direction'), 3) & 255, ctx.style(a.get('style', '0')),
                ctx.fill(a.get('fill', '0')), ctx.font(a.get('font', '0')), hexint(a.get('color'), ctx.colors['NOTETEXT_TEXT']),
                toint(a.get('border_style'), 1), txt)
    if t == 'SYMBOL':
        fields = []
        fl = el.findall('FIELD')
        defaults = [(0, 'Ref', '', 1, (0.0, 0.0)), (0, 'Name', '', 1, (0.0, 0.0)), (1, 'Other', '', 0, (0.0, 0.0))]
        if not fl:
            fields = defaults
        else:
            for i, fe in enumerate(fl):
                d = defaults[i] if i < 3 else (0, '', '', 0, (float('nan'), float('nan')))
                fa = fe.attrib
                fields.append((toint(fa['type']) if 'type' in fa else 0, fa.get('description', d[1]), fa.get('value', d[2]),
                               toint(fa['show']) if 'show' in fa else d[3], pt(fa.get('pos'), d[4])))
        hints = sorted((h.get('pin', ''), toint(h.get('net'), 0)) for h in el.findall('HINT'))
        return (t, ctx.symbol(a.get('id', '0')), pt(a.get('pos')), toint(a.get('part'), 0) & 255, toint(a.get('rotate'), 3) & 255,
                toint(a.get('can_scale'), 0), toint(a.get('show_power'), 0), f(a.get('scale_x', '1')), f(a.get('scale_y', '1')),
                tuple(fields), tuple(hints))
    return ('UNSUPPORTED', t)

def canon_objects(parent, ctx, keep_origin):
    out = []; seen_origin = False
    for el in parent:
        if el.tag in ('DETAILS','NAME','GRID','FONT','STYLE','FILL','META','IMAGE','SYMBOLDEF','OPTIONS','TinyCAD','TinyCADSheets'):
            continue
        if el.tag == 'ORIGIN':
            if seen_origin: continue
            seen_origin = True
            if not keep_origin: continue
        o = canon_obj(el, ctx)
        # objects the C++ loader discards as empty
        if o[0] in ('TEXT','BUSNAME') and o[-1] == '': continue
        if o[0] == 'LABEL' and o[-1] == '' and o[-2] == 0: continue
        if o[0] == 'NOTE_TEXT' and o[-1] == '': continue
        if o[0] == 'POLYGON' and len(o[4]) <= 1: continue
        out.append(o)
    return tuple(out)

def canon_symbol(el, ctx):
    hetero = el.find('TinyCADSheets') is not None
    fields = []
    for fe in el.findall('FIELD'):
        fields.append((text(fe,'NAME'), text(fe,'DEFAULT'), hexint(text(fe,'FT','0')), text(fe,'VALUE'), pt(text(fe,'POS','0,0') or '0,0')))
    refs = {}
    for rp in el.findall('REF_POINT'):
        k = (toint(rp.get('part'),0), 1 if toint(rp.get('power'),0) else 0)
        if k not in refs: refs[k] = pt(rp.get('pos'))
    refs = {k: v for k, v in refs.items() if k[0] == 0 or hetero}
    if hetero:
        blocks = tuple(canon_objects(b, ctx, True) for b in el.find('TinyCADSheets').findall('TinyCAD'))
    else:
        b = el.find('TinyCAD')
        blocks = (canon_objects(b, ctx, True) if b is not None else (),)
    n = el.find('NAME'); r = el.find('REF')
    return ('SYM', (n.text or '') if n is not None else '', toint(n.get('type')) if n is not None else 0,
            (r.text or '') if r is not None else '', toint(r.get('type')) if r is not None else 0,
            text(el, 'DESCRIPTION'), toint(text(el, 'PPP', '1')) & 255, text(el, 'GUID'), tuple(fields),
            tuple(sorted(refs.items())), hetero, blocks)

def canon_sheet(sheet):
    ctx = Ctx(sheet)
    d = sheet.find('DETAILS')
    grid = None
    if d is not None and d.find('GRID') is not None: grid = d.find('GRID')
    elif sheet.find('GRID') is not None: grid = sheet.find('GRID')
    if grid is not None:
        spacing = f(grid.get('spacing')) if grid.get('spacing') is not None else 10.0
        snap = toint(grid.get('snap'), 1)
    else:
        spacing, snap = 100.0, 1
    if d is not None:
        size = d.find('Size'); gd = d.find('GUIDES'); sh = d.find('SHOWS')
        shows = toint(sh.text) if sh is not None else None
        details = (toint(size.get('width')) if size is not None else 1485, toint(size.get('height')) if size is not None else 1050,
                   text(d,'TITLE'), text(d,'AUTHOR'), text(d,'REVISION','1.0'), text(d,'DOCNUMBER'), text(d,'ORGANISATION'),
                   text(d,'SHEETS','1 of 1'), text(d,'DATE'),
                   toint(gd.get('horiz'),7) if gd is not None else 7, toint(gd.get('vert'),5) if gd is not None else 5,
                   (True, False) if shows is None else ((shows & 1) != 0, (shows & 2) != 0))
    else:
        details = (1485, 1050, '', '', '1.0', '', '', '1 of 1', '', 7, 5, (True, False))
    o = sheet.find('OPTIONS')
    gridshow = toint(text(o,'GRID','0')) if o is not None else 0
    units = toint(text(o,'UNITS','0')) if o is not None else 0
    name = text(sheet, 'NAME')
    return {'name': name, 'details': details, 'grid': (spacing, snap), 'options': (gridshow, units, tuple(sorted(ctx.colors.items()))),
            'objects': canon_objects(sheet, ctx, False), 'nsymdefs': len(ctx.symdefs)}

def canon_file(path):
    root = ET.parse(path).getroot()
    if root.tag == 'TinyCAD': return [canon_sheet(root)]
    return [canon_sheet(s) for s in root.findall('TinyCAD')]

def diff(a, b, path='', out=None, limit=4):
    out = out if out is not None else []
    if len(out) >= limit: return out
    if type(a) != type(b): out.append((path, str(a)[:120], str(b)[:120])); return out
    if isinstance(a, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a or k not in b: out.append((path + '/' + k, 'missing' if k not in a else '', 'missing' if k not in b else ''))
            else: diff(a[k], b[k], path + '/' + k, out, limit)
    elif isinstance(a, (tuple, list)):
        if len(a) != len(b):
            out.append((path + ' len', len(a), len(b)))
            for i, (x, y) in enumerate(zip(a, b)):
                if x != y: diff(x, y, f'{path}[{i}]', out, limit); break
        else:
            for i, (x, y) in enumerate(zip(a, b)):
                if x != y: diff(x, y, f'{path}[{i}]', out, limit)
    elif a != b:
        if isinstance(a, float) and isinstance(b, float) and math.isnan(a) and math.isnan(b): return out
        out.append((path, str(a)[:120], str(b)[:120]))
    return out
