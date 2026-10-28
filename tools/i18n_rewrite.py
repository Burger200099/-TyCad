#!/usr/bin/env python3
"""One-off refactoring tool: moves the user-facing text of the Pascal sources into resourcestrings (src/UStrings.pas), so that it can be translated with a .po file.

    i18n_rewrite.py --report [files]     lists the strings that would be moved (with the call or assignment they are in) and the other strings that look like text
    i18n_rewrite.py --apply  [files]     rewrites the files and (re)writes src/UStrings.pas

How a string is chosen: by what it is given to.  A call such as ShowMessage('...'), MessageDlg, ReportProblem, FView.BeginChange or an assignment to .Caption, .Hint, .Title,
panel text and the like (see CALLS and TARGETS below) makes every string in its expression text for the user.  A chain  'Cannot open ' + Name + ':'  becomes
Format(rsCannotOpen, [Name]) with the template  'Cannot open %s:'  so that a translator gets a whole sentence; IntToStr(x) in a chain becomes %d.
Strings compared with = or <>, used as keys, SQL, XML names, script output and file formats are never touched.  EXTRA_LINES / SKIP_LINES at the end name single places by hand.
The tool is kept for reference and must not be run again: --apply rewrites src/UStrings.pas from scratch and loses its section comments and the hand-added strings; after the move a new message is written as a resourcestring straight away (see README, Translating)."""
import re, sys, os, glob

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "src")
SKIP_FILES = {"UScript.pas", "UStrings.pas", "UDialogs.pas", "fshared.pas", "consts.pas"}      # the script harness prints machine text; UDialogs is not part of the program

KEYWORDS = set("""and array as begin case class const constructor destructor div do downto else end except exports file finally for function goto if implementation in inherited initialization
inline interface is label mod nil not object of on or packed procedure program property raise record repeat resourcestring set shl shr string then threadvar to try type unit until uses var while with xor""".split())

# calls whose string arguments are shown to the user: name (lower case, the last dotted part counts when the whole name is not listed) -> argument numbers
CALLS = {
    "showmessage": {0}, "messagedlg": {0, 1}, "reportproblem": {0}, "findmessage": {0}, "beginchange": {0}, "inputquery": {0, 1},
    "askfiletowrite": {1, 2}, "choosedesignfile": {0}, "setresults": {1}, "addbutton": {2, 3}, "status": {0}, "beginpastefrom": {1, 2, 3, 4}, "startblock": {1, 2},
    "tfrmnuminput.create": {4}, "issue": {2}, "writeerror": {0}, "maker.writeerror": {0}, "problem": {0}, "fail": {0}, "addcustombutton": {0}, "def": {1}, "detailstext": {1},
    "items.add": {0}, "items.addobject": {0}, "subitems.add": {0}, "canvas.textwidth": {0}, "textwidth": {0},
}
for _c in ("exception", "epartserror", "elibraryerror", "edsntruncated", "exmlexception", "ereaderror"):
    CALLS[_c + ".create"] = {0}; CALLS[_c + ".createfmt"] = {0}
CALLS["exmlexception.createxml"] = {0}
TRANSPARENT = {"format": {0}, "ifthen": {1, 2}, "exception.createfmt": set()}      # the value goes on to wherever the call is used
# assignments: the target (lower case, without spaces) matches one of these patterns
TARGETS = [r".*\.caption", r".*\.hint", r".*\.title", r".*\.verificationtext", r".*\.filter", r".*panels\[\d+\]\.text", r".*\.statustext", r".*\.edlabel\.caption",
           r"msg", r"warn", r"err", r"loaderror", r"detail", r"importerrors", r"caption", r"td\.text", r".*\.texthint", r".*\.cells\[.*\]", r"statusmsg"]
# Hand lists: (file base name, line number) pairs, line numbers of the ORIGINAL file; the string(s) of the line are taken/not taken
EXTRA_LINES = set()
SKIP_LINES = set()
SKIP_TEXTS = set()
try:
    exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "i18n_hand.py"), encoding="utf-8").read())
except IOError:
    pass


class Tok:
    __slots__ = ("kind", "text", "s", "e", "val")
    def __init__(self, kind, text, s, e, val=None):
        self.kind = kind; self.text = text; self.s = s; self.e = e; self.val = val
    def __repr__(self): return "%s:%r" % (self.kind, self.text)


def tokenize(src):
    toks = []; i = 0; n = len(src)
    while i < n:
        c = src[i]
        if c in " \t\r\n": i += 1; continue
        if c == "/" and src.startswith("//", i):
            j = src.find("\n", i); i = n if j < 0 else j; continue
        if c == "{":
            j = src.find("}", i); i = n if j < 0 else j + 1; continue
        if c == "(" and src.startswith("(*", i):
            j = src.find("*)", i); i = n if j < 0 else j + 2; continue
        if c == "'" or c == "#":
            s = i; val = []
            while i < n:
                if src[i] == "'":
                    j = i + 1; buf = []
                    while j < n:
                        if src[j] == "'":
                            if j + 1 < n and src[j + 1] == "'": buf.append("'"); j += 2; continue
                            break
                        buf.append(src[j]); j += 1
                    val.append("".join(buf)); i = j + 1
                elif src[i] == "#":
                    m = re.match(r"#(\$[0-9A-Fa-f]+|\d+)", src[i:])
                    if not m: break
                    v = m.group(1); val.append(chr(int(v[1:], 16) if v[0] == "$" else int(v))); i += m.end()
                else:
                    break
            toks.append(Tok("str", src[s:i], s, i, "".join(val))); continue
        m = re.match(r"[A-Za-z_][A-Za-z_0-9]*", src[i:])
        if m:
            toks.append(Tok("id", m.group(0), i, i + m.end())); i += m.end(); continue
        m = re.match(r"\$[0-9A-Fa-f]+|\d+(\.\d+)?([eE][-+]?\d+)?", src[i:])
        if m:
            toks.append(Tok("num", m.group(0), i, i + m.end())); i += m.end(); continue
        two = src[i:i + 2]
        if two in (":=", "<>", "<=", ">=", "..", "+=", "-=", "*=", "/="):
            toks.append(Tok("sym", two, i, i + 2)); i += 2; continue
        toks.append(Tok("sym", c, i, i + 1)); i += 1
    return toks


def match_fwd(toks, k):
    """index of the bracket closing the one at k"""
    op = toks[k].text; cl = ")" if op == "(" else "]"; d = 0
    for j in range(k, len(toks)):
        t = toks[j]
        if t.kind == "sym":
            if t.text in "([": d += 1
            elif t.text in ")]":
                d -= 1
                if d == 0: return j
    return len(toks) - 1


def match_back(toks, k):
    d = 0
    for j in range(k, -1, -1):
        t = toks[j]
        if t.kind == "sym":
            if t.text in ")]": d += 1
            elif t.text in "([":
                d -= 1
                if d == 0: return j
    return 0


def atom_end(toks, k):
    """index of the last token of the operand that starts at k, or -1"""
    t = toks[k]
    if t.kind in ("str", "num"):
        return k
    if t.kind == "id" and t.text.lower() not in KEYWORDS - {"nil"}:
        e = k
    elif t.kind == "sym" and t.text == "(":
        e = match_fwd(toks, k)
    else:
        return -1
    while e + 1 < len(toks):
        n = toks[e + 1]
        if n.kind == "sym" and n.text in "([":
            e = match_fwd(toks, e + 1)
        elif n.kind == "sym" and n.text == "." and e + 2 < len(toks) and toks[e + 2].kind == "id":
            e += 2
        elif n.kind == "sym" and n.text == "^":
            e += 1
        else:
            break
    return e


def atom_start(toks, k):
    """index of the first token of the operand that ends at k, or -1"""
    t = toks[k]
    if t.kind in ("str", "num"):
        return k
    s = k
    if t.kind == "sym" and t.text in ")]":
        s = match_back(toks, k)
        # a call or an index: the name goes with it
        while s > 0 and toks[s - 1].kind == "id" and toks[s - 1].text.lower() not in KEYWORDS - {"nil"}:
            s -= 1
            if s > 0 and toks[s - 1].kind == "sym" and toks[s - 1].text == ".":
                s -= 1
                if s > 0: s -= 1
                continue
            break
        if t.text == ")" and s > 0 and toks[s - 1].kind == "sym" and toks[s - 1].text == "." and s > 1:
            pass
    elif t.kind == "id" and t.text.lower() not in KEYWORDS - {"nil"}:
        s = k
    else:
        return -1
    # qualifiers:  A.B.C(x)
    while s >= 2 and toks[s - 1].kind == "sym" and toks[s - 1].text == "." and (toks[s - 2].kind == "id" or toks[s - 2].text in ")]"):
        if toks[s - 2].kind == "id":
            s -= 2
        else:
            s = match_back(toks, s - 2)
            while s > 0 and toks[s - 1].kind == "id" and toks[s - 1].text.lower() not in KEYWORDS - {"nil"}:
                s -= 1
                break
    return s


def chain_around(toks, a, b):
    """the + chain that contains the tokens a..b (an operand): (first token, last token)"""
    s, e = a, b
    while s >= 2 and toks[s - 1].kind == "sym" and toks[s - 1].text == "+":
        st = atom_start(toks, s - 2)
        if st < 0: break
        s = st
    while e + 2 < len(toks) and toks[e + 1].kind == "sym" and toks[e + 1].text == "+":
        en = atom_end(toks, e + 2)
        if en < 0: break
        e = en
    return s, e


def operands(toks, s, e):
    res = []; k = s
    while k <= e:
        en = atom_end(toks, k)
        res.append((k, en)); k = en + 2
    return res


def callee_of(toks, k):
    """the dotted name in front of the '(' at k, lower case"""
    j = k - 1; parts = []
    while j >= 0 and toks[j].kind == "id" and toks[j].text.lower() not in KEYWORDS - {"nil"}:
        parts.insert(0, toks[j].text); j -= 1
        if j >= 1 and toks[j].kind == "sym" and toks[j].text == "." and toks[j - 1].kind in ("id",):
            j -= 1; continue
        if j >= 1 and toks[j].kind == "sym" and toks[j].text in ")]":
            break
        break
    return ".".join(parts).lower(), j + 1


def enclosing_call(toks, k):
    """for the token k that starts an expression: (callee, argument number, index of '(') or None"""
    d = 0; arg = 0; j = k - 1
    while j >= 0:
        t = toks[j]
        if t.kind == "sym":
            if t.text in ")]": d += 1
            elif t.text in "([":
                if d == 0:
                    if t.text == "[": return ("[", arg, j)
                    name, st = callee_of(toks, j)
                    return (name, arg, j) if name else ("(", arg, j)
                d -= 1
            elif t.text == "," and d == 0: arg += 1
            elif t.text in (";", ":=") and d == 0: return None
        elif t.kind == "id" and d == 0 and t.text.lower() in ("then", "else", "do", "begin", "of"):
            return None
        j -= 1
    return None


def target_before(toks, k):
    """text of the assignment target when the expression starting at k follows ':=' (lower case, no spaces), else None"""
    if k < 1 or not (toks[k - 1].kind == "sym" and toks[k - 1].text == ":="): return None
    j = k - 2; parts = []
    while j >= 0:
        t = toks[j]
        if t.kind == "id" and t.text.lower() not in KEYWORDS: parts.insert(0, t.text); j -= 1
        elif t.kind == "sym" and t.text == ".": parts.insert(0, "."); j -= 1
        elif t.kind == "sym" and t.text in ")]":
            m = match_back(toks, j); parts.insert(0, "".join(x.text for x in toks[m:j + 1])); j = m - 1
        else: break
    return "".join(parts).lower().replace(" ", "")


def context(toks, s, e, depth=0):
    """what the chain s..e is given to: ('call', name, argno) / ('assign', target) / None, following transparent calls outward"""
    prev = toks[s - 1] if s > 0 else None
    nxt = toks[e + 1] if e + 1 < len(toks) else None
    if nxt is not None and nxt.kind == "sym" and nxt.text in ("=", "<>", "<", ">", "<=", ">="):
        return ("compare",)
    if nxt is not None and nxt.kind == "id" and nxt.text.lower() in ("in", "is", "as"):
        return ("compare",)
    if prev is not None and prev.kind == "sym" and prev.text in ("=", "<>", "<", ">", "<=", ">="):
        return ("compare",)
    if prev is not None and prev.kind == "id" and prev.text.lower() in ("in", "of"):
        return ("compare",)
    t = target_before(toks, s)
    if t is not None:
        return ("assign", t)
    c = enclosing_call(toks, s)
    if c is None:
        return None
    name, arg, p = c
    last = name.split(".")[-1]
    if name in TRANSPARENT or last in TRANSPARENT:
        key = name if name in TRANSPARENT else last
        if arg in TRANSPARENT[key] and depth < 4:
            cs, ce = callee_of(toks, p)[1], match_fwd(toks, p)
            ccs, cce = chain_around(toks, cs, ce)
            sub = context(toks, ccs, cce, depth + 1)
            return sub
        if key == "format":
            return ("format-arg", arg)
        return ("call", name, arg)
    return ("call", name, arg)


def selected(ctx):
    if ctx is None: return None
    if ctx[0] == "call":
        name, arg = ctx[1], ctx[2]
        parts = name.split(".")
        for key in [".".join(parts[i:]) for i in range(len(parts))]:
            if key in CALLS and arg in CALLS[key]: return "call " + name
        return None
    if ctx[0] == "assign":
        for pat in TARGETS:
            if re.fullmatch(pat, ctx[1]): return "assign " + ctx[1]
    return None


def looks_like_text(v):
    return bool(re.search(r"[A-Za-z]{2,}", v))


def pas_literal(v):
    """Pascal source for a string value"""
    out = []; buf = ""
    for ch in v:
        if ch == "'" : buf += "''"
        elif ord(ch) < 32:
            if buf: out.append("'" + buf + "'"); buf = ""
            out.append("#%d" % ord(ch))
        else: buf += ch
    if buf or not out: out.append("'" + buf + "'")
    return "".join(out)


class Table:
    """the resource strings: template text -> name, in the order they were met"""
    def __init__(self):
        self.by_text = {}; self.names = {}; self.order = []; self.group = {}
    def name_for(self, text, group):
        if text in self.by_text: return self.by_text[text]
        w = re.sub(r"%[sd]", " ", text)
        words = re.findall(r"[A-Za-z][A-Za-z0-9]*", w)[:5]
        base = "rs" + "".join(x[:1].upper() + x[1:] for x in words)
        if base == "rs": base = "rsText"
        base = base[:44]
        name = base; n = 2
        while name.lower() in self.names:
            name = base + str(n); n += 1
        self.names[name.lower()] = text; self.by_text[text] = name; self.order.append(name); self.group[name] = group
        return name


def plan(path, table, report):
    src = open(path, encoding="utf-8", errors="surrogateescape", newline="").read()
    toks = tokenize(src)
    base = os.path.basename(path)
    line_of = lambda pos: src.count("\n", 0, pos) + 1
    edits = []; done = set(); shown = []
    for k, t in enumerate(toks):
        if t.kind != "str" or k in done: continue
        if not looks_like_text(t.val): continue
        s, e = chain_around(toks, k, k)
        for q in range(s, e + 1): done.add(q)
        ops = operands(toks, s, e)
        ctx = context(toks, s, e)
        why = selected(ctx)
        ln = line_of(toks[s].s)
        lines = set(line_of(toks[q].s) for q in range(s, e + 1))
        if any((base, l) in EXTRA_LINES for l in lines) and why is None and ctx != ("compare",): why = "hand"
        if any((base, l) in SKIP_LINES for l in lines): why = None
        if why is None:
            shown.append((ln, "-", ctx, src[toks[s].s:toks[e].e].replace("\n", " ")[:110]))
            continue
        # build the template
        parts = []; args = []; ok = True
        lits = [o for o in ops if toks[o[0]].kind == "str"]
        pure_format_arg = (ctx is not None and False)
        for (a, b) in ops:
            if a == b and toks[a].kind == "str":
                parts.append(toks[a].val)
            elif a == b and toks[a].kind == "id" and toks[a].text.lower() in ("lineending", "slinebreak"):
                parts.append("\n")
            elif toks[a].kind == "id" and toks[a].text.lower() == "inttostr" and b == match_fwd(toks, a + 1):
                parts.append("%d"); args.append((toks[a + 2].s, toks[b - 1].e) if b - 1 >= a + 2 else "0")
            else:
                parts.append("%s"); args.append((toks[a].s, toks[b].e))
        tmpl_parts = []
        # a lone literal given to Format(...) is already a template: '%' stays
        in_fmt = len(ops) == 1 and toks[ops[0][0]].kind == "str" and enclosing_call(toks, s) is not None and enclosing_call(toks, s)[0].split(".")[-1] in ("format", "createfmt") and enclosing_call(toks, s)[1] == 0
        for (a, b), p in zip(ops, parts):
            if a == b and toks[a].kind == "str" and not in_fmt and args:
                tmpl_parts.append(p.replace("%", "%%"))
            else:
                tmpl_parts.append(p)
        text = "".join(tmpl_parts)
        if not looks_like_text(re.sub(r"%[sd]", "", text)):
            shown.append((ln, "-", ctx, src[toks[s].s:toks[e].e].replace("\n", " ")[:110])); continue
        if text in SKIP_TEXTS:
            shown.append((ln, "-", ctx, text)); continue
        name = table.name_for(text, base)
        edits.append((toks[s].s, toks[e].e, (name, [] if in_fmt else args), ln, why, text))
        shown.append((ln, "+", why, text.replace("\n", "\\n")[:110]))
    return src, edits, shown


def render(src, edits, a, b, outer):
    """the text src[a:b] with the edits that lie inside it carried out (an edit inside another one is part of its argument text)"""
    inside = [x for x in edits if x[0] >= a and x[1] <= b and x is not outer and not (x[0] == a and x[1] == b and outer is not None)]
    # keep the outermost ones only
    top = [x for x in inside if not any(y is not x and y[0] <= x[0] and x[1] <= y[1] and (y[0], y[1]) != (x[0], x[1]) for y in inside)]
    top.sort(key=lambda x: x[0])
    out = []; pos = a
    for x in top:
        out.append(src[pos:x[0]])
        name, args = x[2]
        if not args:
            out.append(name)
        else:
            texts = [("0" if isinstance(t, str) else render(src, edits, t[0], t[1], x)) for t in args]
            out.append("Format(%s, [%s])" % (name, ", ".join(texts)))
        pos = x[1]
    out.append(src[pos:b])
    return "".join(out)


def add_uses(src):
    m = re.search(r"^implementation\s*$", src, re.M | re.I)
    if not m: return src
    after = src[m.end():]
    mu = re.match(r"(\s*(?:\{[^}]*\}\s*|//[^\n]*\n\s*)*)uses\b", after, re.I)
    if mu and not re.search(r"\bUStrings\b", src):
        pos = m.end() + mu.end()
        return src[:pos] + " UStrings," + src[pos:]
    if re.search(r"\bUStrings\b", src): return src
    return src[:m.end()] + "\n\nuses UStrings;\n" + src[m.end():]


def main(argv):
    apply = "--apply" in argv; report = "--report" in argv
    files = [a for a in argv if not a.startswith("--")]
    if not files:
        files = sorted(glob.glob(os.path.join(SRC, "*.pas")) + glob.glob(os.path.join(SRC, "*", "*.pas")))
    files = [f for f in files if os.path.basename(f) not in SKIP_FILES]
    table = Table()
    # strings already in UStrings keep their names
    us = os.path.join(SRC, "UStrings.pas")
    if os.path.exists(us):
        for m in re.finditer(r"^\s*(rs\w+)\s*=\s*((?:'(?:[^']|'')*'|#\d+)+)\s*;", open(us, encoding="utf-8").read(), re.M):
            val = "".join(m2.group(1).replace("''", "'") if m2.group(1) is not None else chr(int(m2.group(2))) for m2 in re.finditer(r"'((?:[^']|'')*)'|#(\d+)", m.group(2)))
            table.names[m.group(1).lower()] = val; table.by_text[val] = m.group(1); table.order.append(m.group(1)); table.group[m.group(1)] = "(earlier)"
    total = 0
    for f in files:
        src, edits, shown = plan(f, table, report)
        if report:
            print("==", os.path.relpath(f, SRC))
            for ln, mark, why, txt in shown: print("  %5d %s %-34s %s" % (ln, mark, str(why)[:34], txt))
        if not edits: continue
        total += len(edits)
        if apply:
            new = render(src, edits, 0, len(src), None)
            new = add_uses(new)
            open(f, "w", encoding="utf-8", errors="surrogateescape", newline="").write(new)
    if apply:
        write_ustrings(table, us)
    print("%d string(s) %s, %d distinct" % (total, "moved" if apply else "selected", len(table.order)))


def write_ustrings(table, path):
    out = ["{ Every text the program shows (messages, undo names, file dialogs, names of objects ...) is a resourcestring here, so that it can be translated: the compiler writes",
           "  UStrings.rsj, tools/mkpo.py makes languages/schematic.pot from it and from the captions in the .lfm files, and LCLTranslator reads languages/schematic.<lang>.po.",
           "  A template with %s / %d is used with Format; keep the order of the values in mind when translating (a translation may use %1:s style indexes: %2:s ... %1:s).",
           "  Licence: LGPL 2.1 or later, as the rest of this port. }",
           "unit UStrings;", "", "{$mode objfpc}{$H+}{$codepage utf8}", "", "interface", "", "resourcestring"]
    last = None
    for name in table.order:
        g = table.group.get(name)
        if g != last and g != "(earlier)":
            out.append(""); out.append("  { %s }" % g); last = g
        out.append("  %s = %s;" % (name, pas_literal(table.names[name.lower()])))
    out += ["", "implementation", "", "end.", ""]
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1:])
