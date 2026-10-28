#!/usr/bin/env python3
"""Source style for the Pascal files: the statement after `then` or `else` goes on its own line, indented 2 more than the `if`.

    if a = 1 then inc(a) else a := 1;      becomes      if a = 1 then
                                                          inc(a)
                                                        else
                                                          a := 1;

`then begin`, `else begin` and `else if` are left on the line, but a block that holds several statements and is written on one line is opened out:

    if a then begin b; c; end;             becomes      if a then begin
                                                          b;
                                                          c;
                                                        end;

(a block of one statement stays on its line; a block with a nested begin / case / try, or with a comment inside, is left alone). Usage: fmt_ifthen.py [--check] file.pas ...
Only white space is changed (the tool checks that the text without white space is identical before it writes), so it is safe to run again.
Comments ({ }, (* *), //) and strings are never looked into. --check lists the files that would change and writes nothing."""
import re, sys

WORD = re.compile(r"[A-Za-z_][A-Za-z_0-9]*")

def masks(lines):
    """for each line a copy of the same length with comments blanked and string contents replaced by 'S' (so no keyword is found in them)"""
    out = []; brace = False; star = False
    for L in lines:
        m = list(L); i = 0; n = len(L)
        while i < n:
            c = L[i]
            if brace:
                m[i] = " "
                if c == "}": brace = False
                i += 1
            elif star:
                m[i] = " "
                if c == "*" and i + 1 < n and L[i + 1] == ")":
                    m[i + 1] = " "; i += 1; star = False
                i += 1
            elif c == "'":
                j = i + 1
                while j < n:
                    if L[j] == "'":
                        if j + 1 < n and L[j + 1] == "'": j += 2; continue
                        break
                    j += 1
                for k in range(i + 1, min(j, n)): m[k] = "S"
                i = j + 1
            elif c == "{": brace = True; m[i] = " "; i += 1
            elif c == "(" and i + 1 < n and L[i + 1] == "*": star = True; m[i] = m[i + 1] = " "; i += 2
            elif c == "/" and i + 1 < n and L[i + 1] == "/":
                for k in range(i, n): m[k] = " "
                break
            else: i += 1
        out.append("".join(m))
    return out

def keywords(M):
    """(position, lowercase word) of every word of the masked line that is outside brackets"""
    res = []; depth = 0; i = 0
    while i < len(M):
        c = M[i]
        if c in "([": depth += 1
        elif c in ")]": depth -= 1
        elif c.isalpha() or c == "_":
            w = WORD.match(M, i).group(0)
            if depth == 0: res.append((i, w.lower()))
            i += len(w); continue
        i += 1
    return res

def split_once(L, M, base):
    """split a line at the first place that needs it; returns the list of new lines, or None when the line is fine"""
    kw = keywords(M)
    for idx, (p, w) in enumerate(kw):
        if w == "then":
            rest = M[p + 4:]
            if rest.strip() == "": continue
            nxt = rest.split()[0].lower() if rest.split() else ""
            if re.match(r"begin\b", rest.strip(), re.I): continue
            return [L[:p + 4].rstrip(), " " * (base + 2) + L[p + 4:].strip()]
        if w == "else":
            rest = M[p + 4:]
            if rest.strip() == "": continue
            if re.match(r"(begin|if)\b", rest.strip(), re.I): continue
            before = M[:p].strip().lower()
            if before not in ("", "end"):
                return [L[:p].rstrip(), " " * base + L[p:].strip()]
            return [L[:p + 4].rstrip(), " " * (base + 2) + L[p + 4:].strip()]
    return None


OPENERS = {"begin", "case", "try", "record", "asm"}

def open_blocks(lines):
    """one pass: opens out the first one-line `begin a; b; end` of each line that holds several statements; returns (lines, changed)"""
    M = masks(lines); out = []; changed = False
    for L, m in zip(lines, M):
        done = False
        for p, w in keywords(m):
            if w != "begin": continue
            # find the matching end on this line
            depth = 0; endpos = None; semis = []; bad = False; br = 0
            i = p + 5
            kws = {q: x for q, x in keywords(m) if q >= p + 5}
            while i < len(m):
                c = m[i]
                if c in "([": br += 1
                elif c in ")]": br -= 1
                elif c.isalpha() or c == "_":
                    wd = WORD.match(m, i).group(0); lw = wd.lower()
                    if br == 0:
                        if lw in OPENERS: bad = True
                        elif lw == "end": endpos = i; break
                    i += len(wd); continue
                elif c == ";" and br == 0: semis.append(i)
                i += 1
            if endpos is None or bad: continue
            inner_m = m[p + 5:endpos]; inner_l = L[p + 5:endpos]
            if any(a != " " and b == " " for a, b in zip(inner_l, inner_m)): continue      # a comment inside
            parts = []; start = p + 5
            for q in semis + [endpos]:
                seg = L[start:q].strip()
                if seg: parts.append(seg + ("" if q == endpos else ";"))
                start = q + 1
            if len(semis) < 1 or len(parts) < 2: continue
            ind = len(L) - len(L.lstrip(" "))
            out.append(L[:p + 5].rstrip())
            for t in parts: out.append(" " * (ind + 2) + t)
            out.append(" " * ind + L[endpos:].strip())
            done = True; changed = True; break
        if not done: out.append(L)
    return out, changed

def fix(text):
    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.replace("\r\n", "\n").split("\n")
    for _ in range(12):
        lines, ch = open_blocks(lines)
        if not ch: break
    out = []; pending = None
    M = masks(lines)
    for L, m in zip(lines, M):
        ind = len(L) - len(L.lstrip(" "))
        nif = len(re.findall(r"\bif\b", m, re.I)); nthen = len(re.findall(r"\bthen\b", m, re.I))
        base = ind
        if pending is not None and nthen: base = pending
        lab = re.match(r"(\s*[\w.,' ]+:\s*)if\b", m, re.I)      # a case label in front of the if: the if lines up after it
        if lab and pending is None: base = len(lab.group(1))
        if pending is None and nif > nthen: pending = base
        elif pending is not None and nthen and nthen >= 1: pending = None
        work = [(L, m, base)]
        while work:
            l, mm, b = work.pop(0)
            r = split_once(l, mm, b)
            if r is None: out.append(l); continue
            out.append(r[0])
            tail = r[1]
            # the tail is code on a line of its own: mask it again as the beginning of a fresh line (comments cannot be open here: a split never follows an open comment)
            tm = masks([tail])[0]
            # an `else` still in the tail belongs to the `if` it came from; a nested `if` starts a level of its own
            nb = b + 2 if re.match(r"\s*if\b", tm, re.I) else b
            work.insert(0, (tail, tm, nb))
    return nl.join(out)

def squeeze(t): return "".join(t.split())

def main(argv):
    check = "--check" in argv
    files = [a for a in argv if not a.startswith("--")]
    changed = 0
    for f in files:
        raw = open(f, "rb").read().decode("utf-8", "surrogateescape")
        new = fix(raw)
        if new == raw: continue
        if squeeze(new) != squeeze(raw):
            print("REFUSED (more than white space would change):", f); continue
        changed += 1
        print(("would change " if check else "changed ") + f)
        if not check: open(f, "wb").write(new.encode("utf-8", "surrogateescape"))
    print("%d file(s) %s" % (changed, "to change" if check else "changed"))
    return 0

if __name__ == "__main__": sys.exit(main(sys.argv[1:]))
