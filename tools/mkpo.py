#!/usr/bin/env python3
"""Makes the translation template of the program and brings the translations up to date.

    python3 tools/mkpo.py              writes languages/schematic.pot and merges it into every languages/schematic.<lang>.po that exists
    python3 tools/mkpo.py --check      lists what is out of date and writes nothing (exit code 1 when something is)
    python3 tools/mkpo.py --pseudo F   writes F, a made-up language (every text in [brackets] with accents) for testing that nothing is left untranslated
    python3 tools/mkpo.py --new de     starts languages/schematic.de.po from the template

What goes into the template:
  - every resourcestring of src/UStrings.pas (messages, names of undo steps, file dialogs ...), identified as  ustrings.<name>
  - the Caption, Hint, Text, TextHint and Title of every control in src/forms/*.lfm and src/frames/*.lfm, identified as  <formclass>.<control>.<property>
    in lower case, the way LCLTranslator looks them up (an item of a collection: tfrmmain.sbmainbar.panels[0].text).
Each entry has a  msgctxt  equal to its identifier, so that the same English text may be translated differently in two places, and the usual .po editors accept the file.
Licence: LGPL 2.1 or later, as the rest of this port."""
import os, re, sys, glob, subprocess

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "src")
LANG = os.path.join(ROOT, "languages")
TEXT_PROPS = {"caption", "hint", "text", "texthint", "title", "title.caption", "editlabel.caption"}
TEXT_CLASSES = {"tedit", "tlabelededit", "tmemo", "tcombobox", "tmaskedit", "tcustomedit", "tspinedit"}      # classes whose Text is something a person reads
HEADER = '''# TyCAD Electrical - translation template
# Translate the msgstr lines (leave msgid and msgctxt as they are). Keep every %s, %d and & (the underlined key of a menu item) in a translation.
# In a text with several %s / %d the order of the values can be changed with %2:s ... %1:s.
msgid ""
msgstr ""
"Project-Id-Version: TyCAD Electrical\\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
"PO-Revision-Date: YEAR-MO-DA HO:MI+ZONE\\n"
"Last-Translator: \\n"
"Language-Team: \\n"
"Language: \\n"
'''


def po_quote(s):
    """msgid / msgstr value as .po lines"""
    def esc(t): return t.replace("\\", "\\\\").replace('"', '\\"').replace("\t", "\\t").replace("\r", "\\r")
    if "\n" not in s:
        return ['"%s"' % esc(s)]
    parts = s.split("\n"); out = []
    for i, p in enumerate(parts):
        piece = esc(p) + ("\\n" if i < len(parts) - 1 else "")
        if piece: out.append('"%s"' % piece)
    return ['""'] + out


def pas_value(lit):
    """the value of a Pascal string expression made of quoted pieces and #nn codes"""
    out = []
    for m in re.finditer(r"'((?:[^']|'')*)'|#(\d+)|#\$([0-9A-Fa-f]+)", lit):
        if m.group(1) is not None: out.append(m.group(1).replace("''", "'"))
        elif m.group(2) is not None: out.append(chr(int(m.group(2))))
        else: out.append(chr(int(m.group(3), 16)))
    return "".join(out)


def resource_strings():
    """[(identifier, text)] of src/UStrings.pas, in the order of the file"""
    res = []
    text = open(os.path.join(SRC, "UStrings.pas"), encoding="utf-8").read()
    for m in re.finditer(r"^\s*(rs\w+)\s*=\s*((?:'(?:[^']|'')*'|#\d+|#\$[0-9A-Fa-f]+)+)\s*;", text, re.M):
        res.append(("ustrings." + m.group(1).lower(), pas_value(m.group(2))))
    return res


class LfmParser:
    """just enough of the .lfm text format to find the strings of the controls"""
    def __init__(self, text):
        self.t = text.replace("\r\n", "\n"); self.i = 0; self.n = len(self.t)

    def line(self):
        j = self.t.find("\n", self.i)
        if j < 0: j = self.n
        s = self.t[self.i:j]; self.i = j + 1
        return s

    def value(self, first):
        """the value that starts after '=' on this line (first); reads on over the lines of a list, a collection or a long string"""
        v = first.strip()
        if v.startswith("(") and not v.endswith(")") or v.startswith("("):
            buf = [v]
            depth = v.count("(") - v.count(")")
            while depth > 0 and self.i < self.n:
                l = self.line(); buf.append(l.strip()); depth += l.count("(") - l.count(")")
            return " ".join(buf)
        if v.startswith("{"):
            while "}" not in v and self.i < self.n: v += self.line()
            return v
        while v.endswith("+") and self.i < self.n:
            v = v[:-1].rstrip() + self.line().strip()
        return v


def lfm_entries(path):
    """[(identifier, text)] of one form or frame file"""
    text = open(path, encoding="utf-8", errors="replace").read()
    P = LfmParser(text)
    out = []; stack = []; cls_stack = []; root = None
    while P.i < P.n:
        raw = P.line(); l = raw.strip()
        if not l: continue
        m = re.match(r"(object|inherited|inline)\s+(\w+)\s*:\s*(\w+)", l)
        if m:
            if root is None: root = m.group(3).lower()
            stack.append(m.group(2).lower()); cls_stack.append(m.group(3).lower()); continue
        m = re.match(r"(object|inherited|inline)\s+(\w+)\s*$", l)       # inherited without a class
        if m:
            stack.append(m.group(2).lower()); cls_stack.append(cls_stack[-1] if cls_stack else ""); continue
        if l == "end" or l == "end>":
            if stack: stack.pop(); cls_stack.pop()
            continue
        m = re.match(r"([\w.]+)\s*=\s*(.*)$", l)
        if not m: continue
        name, rest = m.group(1), m.group(2)
        if rest.startswith("<"):
            # a collection (Panels, Columns ...): read to its closing '>' and look at each item
            buf = rest[1:]
            while not buf.rstrip().endswith(">") and P.i < P.n: buf += "\n" + P.line()
            for idx, item in enumerate(re.split(r"\bitem\b", buf)[1:]):
                for mm in re.finditer(r"([A-Za-z_][\w.]*)\s*=\s*((?:'(?:[^']|'')*'|#\d+)+)", item):
                    if mm.group(1).lower() in TEXT_PROPS:
                        val = pas_value(mm.group(2))
                        if re.search(r"[A-Za-z]{2,}", val):
                            out.append((".".join([root] + stack[1:] + ["%s[%d]" % (name.lower(), idx), mm.group(1).lower()]), val))
            continue
        lname = name.lower()
        if lname in TEXT_PROPS and rest.startswith(("'", "#")):
            if lname == "text" and (not cls_stack or cls_stack[-1] not in TEXT_CLASSES): continue
            val = pas_value(rest)
            if not re.search(r"[A-Za-z]{2,}", val): continue
            out.append((".".join([root] + stack[1:] + [lname]), val))
    return out


def all_entries():
    entries = []
    for ident, text in resource_strings(): entries.append((ident, text))
    for f in sorted(glob.glob(os.path.join(SRC, "forms", "*.lfm")) + glob.glob(os.path.join(SRC, "frames", "*.lfm"))):
        if os.path.basename(f).lower() in ("fsharedctls.lfm", "fshared.lfm"): pass
        for ident, text in lfm_entries(f): entries.append((ident, text))
    seen = set(); res = []
    for ident, text in entries:
        if ident in seen: continue
        seen.add(ident); res.append((ident, text))
    return res


def entry_lines(ident, text, translation=""):
    out = ["#: " + ident]
    if re.search(r"%[sd]|%\d+:[sd]", text): out.append("#, object-pascal-format")
    out.append('msgctxt "%s"' % ident)
    q = po_quote(text); out.append("msgid " + q[0]); out += q[1:]
    q = po_quote(translation); out.append("msgstr " + q[0]); out += q[1:]
    out.append("")
    return out


def pot_text():
    lines = HEADER.split("\n")
    for ident, text in all_entries(): lines += entry_lines(ident, text)
    return "\n".join(lines)


def pseudo_of(s):
    """the made-up translation of one text: [ ... ] round it, vowels with accents; %s, %d, & and line breaks are kept"""
    table = str.maketrans("aeiouAEIOU", "àéîöüÀÉÎÖÜ")
    parts = re.split(r"(%\d*:?[sd]|&|\n)", s)
    return "[" + "".join(p if re.fullmatch(r"%\d*:?[sd]|&|\n", p) else p.translate(table) for p in parts) + "]"


def pseudo_text():
    """a made-up translation of the whole template (see pseudo_of)"""
    tr = pseudo_of
    lines = HEADER.split("\n")
    lines = [l.replace("translation template", "pseudo translation") for l in lines]
    for ident, text in all_entries(): lines += entry_lines(ident, text, tr(text))
    return "\n".join(lines)


def main(argv):
    check = "--check" in argv
    if "--pseudo" in argv:
        out = argv[argv.index("--pseudo") + 1]
        open(out, "w", encoding="utf-8", newline="\n").write(pseudo_text()); print("wrote", out); return 0
    os.makedirs(LANG, exist_ok=True)
    pot = os.path.join(LANG, "schematic.pot")
    new = pot_text()
    old = open(pot, encoding="utf-8").read() if os.path.exists(pot) else ""
    stale = []
    if new != old:
        stale.append(pot)
        if not check: open(pot, "w", encoding="utf-8", newline="\n").write(new)
    if "--new" in argv:
        lang = argv[argv.index("--new") + 1]
        po = os.path.join(LANG, "schematic.%s.po" % lang)
        if os.path.exists(po): print(po, "exists"); return 1
        text = new.replace("TyCAD Electrical - translation template", "TyCAD Electrical - %s translation" % lang).replace('"Language: \\n"', '"Language: %s\\n"' % lang, 1)
        open(po, "w", encoding="utf-8", newline="\n").write(text); print("wrote", po); return 0
    for po in sorted(glob.glob(os.path.join(LANG, "schematic.*.po"))):
        if check:
            r = subprocess.run(["msgmerge", "--no-fuzzy-matching", "--output-file=-", "--no-wrap", po, pot], capture_output=True, text=True)
            before = subprocess.run(["msgcat", "--no-wrap", po], capture_output=True, text=True).stdout
            if r.stdout != before: stale.append(po)
        else:
            subprocess.run(["msgmerge", "--update", "--backup=none", "--no-fuzzy-matching", "--no-wrap", po, pot], check=True, capture_output=True)
    for s in stale: print(("out of date: " if check else "written: ") + os.path.relpath(s, ROOT))
    if not stale: print("up to date")
    return 1 if (check and stale) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
