"""TinyCAD's SPICE and VHDL netlist writers restated in Python (NetList.cpp: WriteSpiceFile, expand_spice, eval_spice_macro, get_attr, get_pin_by_number, WriteVHDLFile and
Bus_Properties), shared by the tests. The nodes of the nets come from nettest's node listing, the placed symbols and their fields from a separate reading of the design's XML,
and the pins of each symbol as the netlist sees them from nettest's symbols listing."""
import os, re, subprocess
from bomoracle import read_design
from netoracle import read_nets, unesc, BUILD
NT = os.path.join(BUILD, "nettest")

def read_syms(dsn):
    r = subprocess.run([NT, "symbols", dsn], capture_output=True, text=True)
    out = {}; cur = None
    for line in r.stdout.split("\n"):
        f = line.split("\t")
        if f[0] == "SYM":
            cur = (int(f[1]), int(f[2])); out[cur] = dict(name=unesc(f[3]), ref=unesc(f[4]), pins=[])
        elif f[0] == "PIN" and cur is not None:
            out[cur]["pins"].append((unesc(f[1]), unesc(f[2]), int(f[3])))
    return out

def methods_of(sheets):
    """{(sheet, number): fields} in drawing order"""
    return {(si, k): s[4] for si, sh in enumerate(sheets) for k, s in enumerate(sh)}

# ---------------------------------------------------------------- helpers
def atoi(s):
    m = re.match(r"[ \t\n\v\f\r]*([+-]?[0-9]+)", s)
    if not m: return 0
    return max(-2**31, min(2**31 - 1, int(m.group(1))))

def bus(ref, kind="dont_know"):
    """name, start, end, is_bus, kind"""
    i = ref.find("(")
    if i < 0:
        return dict(name=ref, start=0, end=0, is_bus=False, kind=kind)
    name = ref[:i]
    rest = ref[i + 1:]
    start = end = 0
    c = rest.find(":"); p = rest.find(")")
    # the first ':' or ')' after the '(' decides; the end is read only after a ':' and up to the next ')'
    first = min([x for x in (c, p) if x >= 0], default=-1)
    if first >= 0:
        if first == c:
            start = atoi(rest[:c])
            q = rest.find(")", c + 1)
            if q >= 0: end = atoi(rest[c + 1:q])
        else:
            start = atoi(rest[:p]); end = start
    if end > start: end = start
    return dict(name=name, start=start, end=end, is_bus=True, kind=kind)

def decl(b):
    io = {"input": "in", "output": "out"}.get(b["kind"], "")
    if b["is_bus"]: return f"{b['name']}: {io} std_logic_vector({b['start']} downto {b['end']})"
    return f"{b['name']}: {io} std_logic"

def sigref(ref):
    b = bus(ref)
    if not b["is_bus"]: return b["name"]
    if b["start"] == b["end"]: return f"{b['name']}({b['start']})"
    return f"{b['name']}({b['start']} downto {b['end']})"

def entity(path):
    name = re.split(r"[\\/]", path)[-1]
    if "." in name: name = name[:name.rindex(".")]
    return name[:254]

def default_name(p, ext):
    return p[:p.rindex(".")] + ext if "." in p else "output" + ext

def errname(p):
    if "." not in p: return ".txt"
    i = p.rindex(".")
    return p + ".txt" if i == 0 else p[:i] + ".txt"

# ---------------------------------------------------------------- VHDL
def vhdl(sheets, nets, syms, outpath):
    comps = [(si, k, s) for si, sh in enumerate(sheets) for k, s in enumerate(sh)]     # s = (ref, name, default ref, description, fields)
    short = entity(outpath)
    out = ["-- File Created by TinyCad VHDL\nlibrary ieee;\nuse ieee.std_logic_1164.all;\n\nentity %s is\n" % short]
    signals = {}                    # name -> the Bus_Properties first stored, its range widened by later ones
    def add(b):
        if b["name"] not in signals: signals[b["name"]] = dict(b)
        else:
            o = signals[b["name"]]; o["start"] = max(o["start"], b["start"]); o["end"] = min(o["end"], b["end"])
    ports = []
    for want, kind in (("INPUT", "input"), ("OUTPUT", "output")):
        for si, k, s in comps:
            if s[1] == want:
                b = bus(s[0], kind); ports.append(decl(b)); add(b)
    if ports: out.append("\tport(\t" + ";\n\t\t".join(ports) + ");\n")
    out.append("end %s;\n" % short)
    out.append("\narchitecture structural of %s is\n" % short)
    seen = set(); pos = {}; pname = {}; refname = {}
    for si, k, s in comps:
        ref, name = s[0], s[1]
        refname[ref] = name
        if name in seen or name in ("INPUT", "OUTPUT"): continue
        seen.add(name)
        out.append("\tcomponent %s\n \t\tport(\t" % name)
        pos.setdefault(name, {}); pname.setdefault(name, {})
        items = []; p = 0
        for elec, kind in ((0, "input"), (1, "output")):
            for num, nm, e in syms[(si, k)]["pins"]:
                if e != elec: continue
                msg = "ERROR: Duplicated pin number, %s pin number %s\n" % (name, num) if num in pos[name] else ""
                items.append(msg + decl(bus(nm, kind)))
                pos[name][num] = p; p += 1
                pname[name][num] = nm
        out.append(";\n\t\t\t".join(items) + ");\n \tend component;\n")
    labels = {}; msgs = []
    for nodes in nets:
        the = ""; labeled = False; inout = False; size = 0
        for n in nodes:
            if n["label"] and not labeled:
                the = n["label"]; labeled = True; b = bus(the)
                if size == 0: size = b["start"] - b["end"] + 1
                elif size != b["start"] - b["end"] + 1: msgs.append("ERROR: Different BUS sizes at label %s\n" % the)
            if n["sym"] is not None:
                sy = sheets[n["sym"][0]][n["sym"][1]]
                if sy[1] in ("INPUT", "OUTPUT"):
                    the = sy[0]; labeled = True; inout = True; b = bus(the)
                    if size == 0: size = b["start"] - b["end"] + 1
                    elif size != b["start"] - b["end"] + 1: msgs.append("ERROR: Different BUS sizes at IN/OUT %s\n" % the)
                elif n["pin"]:
                    pn = pname.setdefault(sy[1], {}).setdefault(n["pin"], ""); b = bus(pn)
                    if size == 0: size = b["start"] - b["end"] + 1
                    elif size != b["start"] - b["end"] + 1:
                        msgs.append("ERROR: Different BUS sizes: %s pin name %s, pin number %s\n" % (sy[0], pn, n["pin"]))
        if not labeled: the = "N%02d" % nodes[0]["net"] if size == 1 else "N%02d(%d:0)" % (nodes[0]["net"], size - 1)
        labels[nodes[0]["net"]] = the
        if not inout: add(bus(the, "internal"))
    out.extend(msgs)
    for name in sorted(signals):
        if signals[name]["kind"] == "internal": out.append("\tsignal " + decl(signals[name]) + ";\n")
    out.append("begin\n")
    portmaps = {}
    for nodes in nets:
        for n in nodes:
            if n["sym"] is None: continue
            sy = sheets[n["sym"][0]][n["sym"][1]]
            if sy[1] not in ("INPUT", "OUTPUT") and n["ref"]:
                p = pos.setdefault(sy[1], {}).setdefault(n["pin"], 0)
                portmaps.setdefault(n["ref"], {})[p] = labels[nodes[0]["net"]]
    for ref in sorted(portmaps):
        parts = []
        for p in sorted(portmaps[ref]):
            lab = portmaps[ref][p]; b = bus(lab)
            if b["is_bus"]:
                sb = signals.setdefault(b["name"], dict(name=b["name"], start=0, end=0, kind="internal", is_bus=False))
                if b["start"] == sb["start"] and b["end"] == sb["end"]: lab = b["name"]
            parts.append(sigref(lab))
        out.append("\t%s: %s port map (%s);\n" % (ref, refname[ref], ", ".join(parts)))
    out.append("end structural;\n")
    return "".join(out)

# ---------------------------------------------------------------- SPICE
class Fail(Exception): pass
def spice(sheets, nets, designname, stamp):
    """(the SPICE file, the error file, the number of errors)"""
    errs = []
    def err(m): errs.append("Netlist error #%d:  %s" % (len(errs) + 1, m))
    out = ["* Schematics Netlist created on %s *\n" % stamp]
    symbols = {}; labels = {}; pref = {}; nodecount = {}
    for nodes in nets:
        nodecount[nodes[0]["net"]] = sum(1 for n in nodes if n["sym"] is not None)
        for n in nodes:
            if n["ref"] and n["sym"] is not None:
                s = symbols.setdefault(n["ref"], dict(pins={}, names={}, sheet=0, sym=None))
                s["ref"] = n["ref"]; s["sheet"] = n["sheet"]
                if n["ispin"]:
                    if n["pname"] == "": err('%s: Pin on sheet %d has a blank pin name.  Pin number = "%s"\n' % (n["ref"], n["sheet"], n["pnum"]))
                    if n["pnum"] == "": err('%s: Pin on sheet %d has a blank pin number.  Pin name = "%s"\n' % (n["ref"], n["sheet"], n["pname"]))
                    if n["pname"] in s["names"]:
                        err('%s: Pin on sheet %d has a duplicate pin name.  Pin name = "%s", Pin number = "%s"\n' % (n["ref"], n["sheet"], n["pname"], n["pnum"]))
                    s["names"][n["pname"]] = n["pnum"]
                    if n["pnum"] in s["pins"]:
                        err('%s: Pin on sheet %d has a duplicate pin number.  Pin name = "%s", Pin number = "%s"\n' % (n["ref"], n["sheet"], n["pname"], n["pnum"]))
                s["pins"][n["pin"]] = n["net"]
                s["sym"] = n["sym"]
            if n["label"]: labels[n["net"]] = n["label"]
            if n["pref"]: pref[n["net"]] = n["pref"]
    def fields(sym): return sheets[sym[0]][sym[1]][4]
    def mref(sym): return sheets[sym[0]][sym[1]][0]
    def mname(sym): return sheets[sym[0]][sym[1]][1]
    def pin_by_number(s, pin):
        if pin not in s["pins"]: return None
        net = s["pins"][pin]
        if net in pref: r = pref[net]
        elif labels.get(net): r = "_N_%s_%d" % (labels[net], net)
        else: r = "_N_%d" % net
        return r, net, nodecount.get(net, 0)
    def pin_by_any(s, pin):
        r = pin_by_number(s, pin)
        if r is not None: return r
        if pin in s["names"]: return pin_by_number(s, s["names"][pin])
        return None
    def attr(s, a):
        if a.lower() in ("refnum", "ref"): return mref(s["sym"])
        for t, dn, val in fields(s["sym"]):
            if dn.lower() == a.lower(): return val
        return None
    def evalm(sheet, s, macro, buf):
        """returns (truth, text to append to the line first)"""
        b = macro.find("(")
        if b < 0: return False, "<Unknown query operation: " + macro + ">"
        op = macro[:b]; val = macro[b + 1:]
        if val.endswith(")"): val = val[:-1]
        op = op.strip(" \t\n\v\f\r"); val = val.strip(" \t\n\v\f\r")
        if op == "defined": return attr(s, val) is not None, ""
        if op == "not_defined": return attr(s, val) is None, ""
        if op == "empty": return (attr(s, val) or "") == "", ""
        if op == "not_empty": return (attr(s, val) or "") != "", ""
        if op in ("connected", "not_connected"):
            r = pin_by_number(s, val); nodes = r[2] if r else 0
            return (nodes > 1 if op == "connected" else nodes == 1), ""
        if op == "include":
            err("%s: %s on sheet %d has unimplemented macro '%s'\n" % (mref(s["sym"]), mname(s["sym"]), sheet, macro))
            return False, "<Not implemented yet: " + macro + ">"
        err("%s: %s on sheet %d unknown query operand '%s'\n" % (mref(s["sym"]), mname(s["sym"]), sheet, macro))
        return False, "<Unknown query operation: " + macro + ">"
    def expand(sheet, s, text):
        res = ""; i = 0; n = len(text)
        while i < n:
            c = text[i]
            if c == "\\":
                if i + 1 >= n: break
                res += text[i + 1]; i += 2; continue
            if c == "\r": i += 1; continue
            if c not in "%@$?": res += c; i += 1; continue
            if i + 1 >= n: break
            if text[i + 1] != "(": res += text[i + 1]; i += 2; continue
            if c in "%@$":
                j = text.find(")", i + 2)
                if j < 0: break
                look = text[i + 2:j]; i = j + 1
                if c == "$":
                    r = attr(s, look)
                    if r is None:
                        res += "<attr '" + look + "' not found>"
                        err("%s: %s on sheet %d attribute '%s' not found\n" % (mref(s["sym"]), mname(s["sym"]), sheet, look))
                    else: res += r
                else:
                    r = pin_by_any(s, look)
                    if r is None:
                        res += "<pin '" + look + "' not found>"
                        err("%s: %s on sheet %d pin '%s' not found\n" % (mref(s["sym"]), mname(s["sym"]), sheet, look))
                    else: res += r[0] if c == "%" else str(r[1])
                continue
            # a macro ?( ... )
            k = i + 2; depth = 1; look = ""; parts = []; done = False
            while k < n:
                ch = text[k]
                if ch == "\\":
                    if depth == 1:
                        k += 1
                        if k >= n: break
                        look += text[k]
                    else: look += "\\"
                elif ch == "," and depth == 1: parts.append(look); look = ""
                elif ch == ",": look += ch
                elif ch == "(": depth += 1; look += ch
                elif ch != ")": look += ch
                else:
                    depth -= 1
                    if depth == 0: parts.append(look); done = True; k += 1; break
                    look += ch
                k += 1
            if not done: break
            truth, extra = evalm(sheet, s, parts[0], res)
            res += extra
            ins = ""
            if truth and len(parts) > 1: ins = parts[1]
            if (not truth) and len(parts) > 2: ins = parts[2]
            res += expand(sheet, s, ins)
            i = k
        return res
    prolog = [set() for _ in range(10)]; epilog = [set() for _ in range(10)]
    for si, sh in enumerate(sheets):
        for k, m in enumerate(sh):
            fl = m[4]; pro = epi = ""; pp = 5
            tmp = dict(sym=(si, k), pins={}, names={})
            for t, dn, val in fl:
                u = dn.lower()
                if u == "$$spice_prolog": pro = expand(si, tmp, val)
                elif u == "$$spice_epilog": epi = expand(si, tmp, val)
                elif u == "$$spice_prolog_priority":
                    pp = atoi(val)
                    if pp < 0 or pp > 9: pp = 5
            prolog[pp].add(pro); epilog[pp].add(epi)
    for p in range(10):
        for t in sorted(prolog[p]): out.append(t + "\n")
    for ref in sorted(symbols):
        s = symbols[ref]
        model = ""
        for t, dn, val in fields(s["sym"]):
            if dn == "$$SPICE": model = val; break
        if model != "": out.append(expand(s["sheet"], s, model) + "\n")
        else:
            out.append("NO_MODEL found on %s\n" % mref(s["sym"]))
            err("%s: %s on sheet %d has no model\n" % (mref(s["sym"]), mname(s["sym"]), s["sheet"]))
    for p in range(9, -1, -1):
        for t in sorted(epilog[p]): out.append(t + "\n")
    errtext = "Results of Spice netlist generation for %s\n\n" % designname + "".join(errs) + "\n%d %s found\n" % (len(errs), "error" if len(errs) == 1 else "errors")
    return "".join(out), errtext, len(errs)
