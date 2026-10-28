"""TinyCAD's netlist writers restated in Python (NetList.cpp: TinyCAD, PADS-PCB, Eagle, Protel, gEDA PCB and XML formats), shared by run_netwriters.py and
run_netdialog.py. The nets come from nettest's node listing (the build that run_netlist.py checks against TinyCAD's own Protel files); the parts from a separate
reading of the design's XML (bomoracle)."""
import os, re, subprocess
from bomoracle import read_design
BUILD = os.environ.get("TC_BUILD", "build")
NT = os.path.join(BUILD, "nettest")
# ---------------------------------------------------------------- the nets, from nettest
def unesc(s):
    return re.sub(r"\\(.)", lambda m: {"t": "\t", "n": "\n", "r": "\r", "\\": "\\"}.get(m.group(1), m.group(1)), s)
def read_nets(dsn):
    r = subprocess.run([NT, "nodes", dsn], capture_output=True, text=True)
    if r.returncode != 0: return None
    nets = []; last = None
    for line in r.stdout.split("\n"):
        if not line.startswith("NODE\t"): continue
        f = line.split("\t")
        ispin = f[6] == "P"
        node = dict(net=int(f[1]), label=unesc(f[2]), pref=unesc(f[3]), ref=unesc(f[4]), pin=unesc(f[5]), pname=unesc(f[7]) if ispin else None,
                    pnum=unesc(f[8]) if ispin else None, elec=int(f[9]) if ispin else None, ispin=ispin,
                    sheet=int(f[10]) if len(f) > 10 else None, sym=(None if f[11] == "-" else tuple(int(x) for x in f[11].split(":"))) if len(f) > 11 else None)
        if node["net"] != last: nets.append([]); last = node["net"]
        nets[-1].append(node)
    return nets
def netname(nodes):
    for n in nodes:
        if n["label"]: return n["label"]
    return "N%06d" % nodes[0]["net"]

# ---------------------------------------------------------------- the parts, from the design's XML
def parts_of(sheets):
    return [(ref, name, fl) for sh in sheets for (ref, name, dref, desc, fl) in sh]
def named(fl, key, default):
    r = default
    for t, dn, val in fl[2:]:
        if dn.lower() == key: r = val
    return r
def distinct(parts):
    seen = set(); out = []
    for p in parts:
        if p[0] in seen: continue
        seen.add(p[0]); out.append(p)
    return out

# ---------------------------------------------------------------- TinyCAD's writers restated
NOPKG = "This part has no 'Package' attribute"
def w_pads(parts, nets, value):
    out = ["*PADS-PCB*\n*PART*\n"]
    for ref, name, fl in distinct(parts):
        pkg = named(fl, "package", NOPKG); val = named(fl, "value", "")
        r = ref + " "
        while len(r) < 8: r += " "
        out.append(f"{r}{val}@{pkg}\n" if value and val else f"{r}{pkg}\n")
    out.append("\n*NET*\n")
    for nodes in nets:
        line = ""; first = True; ln = 0; count = 0
        for n in nodes:
            if n["ref"]:
                add = f"{n['ref']}.{n['pin']}"; ln += len(add)
                if ln > 127: line += "\n"; ln = len(add); first = True
                if first: first = False
                else: line += " "; ln += 1
                line += add; count += 1
        if count > 1: out.append(f"*SIGNAL*  {netname(nodes)}\n{line}\n")
    out.append("*END*\n")
    return "".join(out)
def w_protel(parts, nets):
    out = []
    for ref, name, fl in distinct(parts):
        out.append(f"[\n{ref}\n{named(fl, 'package', NOPKG)}\n{name}\n\n\n\n]\n")
    for nodes in nets:
        line = ""; first = True; ln = 0; count = 0
        for n in nodes:
            if n["ref"]:
                add = f"{n['ref']}-{n['pin']}"; ln += len(add)
                if ln > 127: line += "\n"; ln = len(add); first = True
                if first: first = False
                else: line += "\n"; ln += 1
                line += add; count += 1
        if count > 1: out.append(f"(\n{netname(nodes)}\n{line}\n)\n")
    return "".join(out)
def w_tinycad(parts, nets, design):
    out = [f"; ====+  Net List for {design}  +====\n\n; ======+ The component list\n\n"]
    for ref, name, fl in distinct(parts):
        out.append(f"COMPONENT '{ref}' = {name}\n")
        for t, dn, val in fl[2:]: out.append(f"\tOPTION '{dn}' = {val}\n")
    out.append("\n\n; ======+ The net list\n\n")
    for nodes in nets:
        items = []
        for n in nodes:
            if n["ref"]:
                add = f"({n['ref']},{n['pin']})"
                if n["label"] != add: items.append(add)
        if items: out.append(f"NET  '{netname(nodes)}' =  {','.join(items)}\n")
    return "".join(out)
def w_eagle(parts, nets):
    out = []; x = 1; y = 1
    for ref, name, fl in distinct(parts):
        out.append(f"ADD '{ref}' {named(fl, 'package', NOPKG)} R0 (0.{x} 0.{y});\n")
        x += 1
        if x == 10: y += 1; x = 1
    out.append("\n\n")
    for nodes in nets:
        line = "".join(f"   {n['ref']} {n['pin']}\n" for n in nodes if n["ref"])
        if line: out.append(f"SIGNAL {netname(nodes)}\n{line}   ;\n")
    return "".join(out)
def w_gedapcb(nets):
    out = []; count = 0
    for nodes in nets:
        line = ""; printed = False
        for n in nodes:
            if n["ref"]:
                add = f"{n['ref']}-{n['pin']} "
                if n["label"] != add:
                    line += add; count += 1
                    if count > 40: count = 0; line += " \\\n "
                    printed = True
        if printed:
            count = 0
            out.append(f" {netname(nodes)}   {line}\n")
    return "".join(out)
def xesc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;").replace("'", "&apos;")
def xattr(k, v):
    if '"' in v: return f" {k}='{xesc(v).replace('&quot;', chr(34))}'"
    return f' {k}="{xesc(v)}"'
ETYPES = ["Input", "Output", "Tristate", "Open Collector", "Passive", "Input/Output", "Not Connected"]
def w_xml(parts, nets, design):
    out = ['<?xml version="1.0" encoding="utf-8"?>\n', f"<netlist{xattr('design', design)}>\n"]
    if parts:
        out.append("\t<parts>\n")
        for ref, name, fl in parts:
            attrs = fl[2:]
            if not attrs: out.append(f"\t\t<part{xattr('ref', ref)}{xattr('name', name)}/>\n"); continue
            out.append(f"\t\t<part{xattr('ref', ref)}{xattr('name', name)}>\n")
            for t, dn, val in attrs:
                out.append(f"\t\t\t<attribute{xattr('name', dn)}>{xesc(val)}</attribute>\n" if val else f"\t\t\t<attribute{xattr('name', dn)}/>\n")
            out.append("\t\t</part>\n")
        out.append("\t</parts>\n")
    else: out.append("\t<parts/>\n")
    if nets:
        out.append("\t<nets>\n")
        for nodes in nets:
            name = next((n["pref"] for n in nodes if n["pref"]), "")
            pins = []
            for n in nodes:
                if n["ispin"]:
                    s = "\t\t\t<pin" + (xattr("part", n["ref"]) if n["ref"] else "") + xattr("name", n["pname"]) + xattr("number", n["pnum"])
                    if 0 <= n["elec"] < 7: s += xattr("type", ETYPES[n["elec"]])
                    pins.append(s + "/>\n")
            head = "\t\t<net" + (xattr("name", name) if name else "") + xattr("number", str(nodes[0]["net"]))
            out.append(head + (">\n" + "".join(pins) + "\t\t</net>\n" if pins else "/>\n"))
        out.append("\t</nets>\n")
    else: out.append("\t<nets/>\n")
    out.append("</netlist>\n")
    return "".join(out)

def oracle(fmt, parts, nets, design):
    if fmt == 1: return w_pads(parts, nets, False)
    if fmt == 2: return w_pads(parts, nets, True)
    if fmt == 3: return w_eagle(parts, nets)
    if fmt == 4: return w_protel(parts, nets)
    if fmt == 5: return w_gedapcb(nets)
    if fmt == 6: return w_xml(parts, nets, design)
    return w_tinycad(parts, nets, design)

