"""TinyCAD's design rules check (CTinyCadView::DoSpecialCheck / DoSpecialVHDLCheck of Net.cpp) restated in Python for run_erc.py.
The nets come from nettest's node listing (the netlist build is checked against TinyCAD's own files by run_netlist.py); the placed symbols (reference, name,
position, field positions, parts per package) are read here from the design's XML; everything the check does with them is restated below from the C++."""
import os, re, subprocess, xml.etree.ElementTree as ET
from netoracle import unesc
from spiceoracle import bus

BUILD = os.environ.get("TC_BUILD", "build")
NT = os.path.join(BUILD, "nettest")

(ERR_UNCONNECT, ERR_POWER, ERR_NOCONNECT, ERR_NOUTPUT, ERR_DUPREF, ERR_OUTPUT, ERR_OUTPUTTOPWR, ERR_UNCONNECTED, ERR_OUTPUTBIDIR, ERR_POWERBIDIR) = range(1100, 1110)
ERR_NOERROR, ERR_UNASSIGNEDREFDES, ERR_NONDISTINCTNET, ERR_MULTIPLENETNAMES = 1110, 1117, 1118, 1119
ERR_BASE = 1099
UNK, PAS, INP, OUT, BID, PWR, NOC = range(7)
MSG = {
    ERR_DUPREF: "This reference is also used with another symbol",
    ERR_OUTPUT: "This output is connected to another output",
    ERR_OUTPUTTOPWR: "This output is connected to a power pin",
    ERR_UNCONNECTED: "This network is not connected to anything",
    ERR_OUTPUTBIDIR: "This TriState/Open Collector output is connected to another output pin",
    ERR_POWERBIDIR: "This TriState/Open Collector output is connected to a power pin",
    ERR_NOERROR: "No errors were found in this design.",
    ERR_UNASSIGNEDREFDES: "This reference designator has not been assigned",
    ERR_NONDISTINCTNET: "There are 2 or more nets that are spelled with different case letters only.  These will be treated as separate nets.",
    ERR_MULTIPLENETNAMES: "This net has more than one name",
    ERR_UNCONNECT: "This item is not connected to anything else",
    ERR_POWER: "This power is connected to a different value power",
    ERR_NOCONNECT: "More than one item is connected to a no-connect",
    ERR_NOUTPUT: "This network has no output driving it",
}
# rows: the net type so far; columns: unknown, passive, input, output, bidir, power, no-connect
TABLE = [
    [UNK, PAS, INP, OUT, BID, PWR, NOC],
    [PAS, PAS, PAS, OUT, BID, PWR, ERR_NOCONNECT],
    [INP, PAS, INP, OUT, BID, PWR, ERR_NOCONNECT],
    [OUT, OUT, OUT, ERR_OUTPUT, ERR_OUTPUTBIDIR, ERR_POWERBIDIR, ERR_NOCONNECT],
    [BID, BID, BID, ERR_OUTPUTBIDIR, BID, ERR_POWERBIDIR, ERR_NOCONNECT],
    [PWR, PWR, PWR, ERR_OUTPUTTOPWR, ERR_POWERBIDIR, PWR, ERR_NOCONNECT],
    [NOC, ERR_NOCONNECT, ERR_NOCONNECT, ERR_NOCONNECT, ERR_NOCONNECT, ERR_NOCONNECT, ERR_NOCONNECT],
]
FLAGS = ["dupref", "unconnect", "noconnect", "power", "outputpwr", "output", "nooutput", "unconnected", "multiple", "nondistinct", "unassigned"]
def flags(word): return {n: bool(word >> i & 1) for i, n in enumerate(FLAGS)}
def g(x): return "%g" % x
def lc(s): return "".join(c.lower() if "A" <= c <= "Z" else c for c in s)

def read_nodes(dsn):
    r = subprocess.run([NT, "ercnodes", dsn], capture_output=True, text=True)
    if r.returncode != 0: return None
    nets = []; last = None
    for line in r.stdout.split("\n"):
        if not line.startswith("E\t"): continue
        f = line.split("\t")
        n = dict(net=int(f[1]), kind=f[2], val=unesc(f[3]), power=unesc(f[4]), label=unesc(f[5]), a=(float(f[6]), float(f[7])), sheet=int(f[10]),
                 parent=(float(f[8]), float(f[9])), mname=unesc(f[12]), mref=unesc(f[13]), reference=unesc(f[14]), pname=unesc(f[15]), pnum=unesc(f[16]), elec=(int(f[17]) if f[2] == "PIN" else -1),
                 ispower=f[18] == "1", act=(float(f[19]), float(f[20])), hasmethod=f[12] != "" or f[13] != "")
        if n["net"] != last: nets.append([]); last = n["net"]
        nets[-1].append(n)
    return nets

def read_placed(path):
    """([sheet names], [placed symbols as dicts]) from the design's XML"""
    root = ET.parse(path).getroot()
    sheets = [root] if root.tag == "TinyCAD" else root.findall("TinyCAD")
    ppp = {}
    for sh in sheets:
        for d in sh.findall("SYMBOLDEF"):
            ppp.setdefault(d.get("id"), int((d.findtext("PPP") or "1").strip() or 1))
    names = [sh.findtext("NAME") or "" for sh in sheets]
    out = []
    for n, sh in enumerate(sheets):
        for s in sh.findall("SYMBOL"):
            fl = s.findall("FIELD")
            px, py = (5 * float(v) for v in s.get("pos").split(","))
            fx, fy = (5 * float(v) for v in fl[0].get("pos").split(","))
            raw = fl[0].get("value"); p = ppp[s.get("id")]
            ref = raw + (chr(ord("A") + int(s.get("part", "0"))) if p > 1 else "")
            out.append(dict(sheet=n + 1, name=fl[1].get("value"), raw=raw, ref=ref, ppp=p, pos=(px, py), refpos=(px + fx, py + fy)))
    return names, out

def erc(nets, placed, names, word, vhdl, always=True):
    """(messages, markers) markers as (number, sheet, x, y)"""
    O = flags(word); msgs = []; marks = []
    def mark(sheet, p): marks.append((len(marks), sheet, p[0], p[1]))
    # 1. unassigned reference designators
    if O["unassigned"]:
        for s in placed:
            if "?" in s["ref"]:
                msgs.append('%s:  [refdes=%s, page="%s", XY=(%s,%s)]\n' % (MSG[ERR_UNASSIGNEDREFDES], s["ref"], names[s["sheet"] - 1], g(s["pos"][0] / 5), g(s["pos"][1] / 5)))
                mark(s["sheet"], s["refpos"])
    # 2. net names
    if O["multiple"] or O["nondistinct"]:
        first_node = {}; first_name = {}
        for nodes in nets:
            here = {}
            for nd in nodes:
                if nd["kind"] not in ("POWER", "LABEL"): continue
                name = nd["power"] if nd["kind"] == "POWER" else nd["val"]
                if name in here: continue
                here[name] = nd
                key = lc(name)
                first_name.setdefault(key, name)
                if key not in first_node:
                    first_node[key] = nd
                else:
                    msgs.append('%s:  "%s", "%s"' % (MSG[ERR_NONDISTINCTNET], name, first_name[key])); mark(nd["sheet"], nd["a"])
                    old = first_node[key]
                    msgs.append('%s:  "%s", "%s"' % (MSG[ERR_NONDISTINCTNET], first_name[key], name)); mark(old["sheet"], old["a"])
            if len(here) > 1 and O["multiple"]:
                text = '%s:  [%s]' % (MSG[ERR_MULTIPLENETNAMES], ",".join('"%s"' % k for k in sorted(here)))
                for k in sorted(here):
                    mark(here[k]["sheet"], here[k]["a"]); msgs.append(text)
    # 3. duplicated references
    if O["dupref"]:
        seen = set()
        for s in placed:
            if s["ref"] in seen:
                msgs.append('%s:  [Object="%s", RefDes=%s, Page #%d]\n' % (MSG[ERR_DUPREF], s["name"], s["ref"], s["sheet"])); mark(s["sheet"], s["refpos"])
            else: seen.add(s["ref"])
    # 4. missing parts
    if O["unconnected"]:
        parts = {}
        for s in placed:
            if s["ppp"] > 1:
                if s["raw"] in parts: parts[s["raw"]]["n"] += 1
                else: parts[s["raw"]] = dict(ppp=s["ppp"], n=1, sheet=s["sheet"], pt=s["refpos"], name=s["name"])
        for k in sorted(parts):
            p = parts[k]
            if p["ppp"] != p["n"]:
                msgs.append('Not all parts in this package are in this design:  [Object="%s", RefDes=%s, Page #%d]\n' % (p["name"], k, p["sheet"])); mark(p["sheet"], p["pt"])
    # 5. the nets (or, for VHDL, sets of nets that are the same bus)
    if not vhdl: groups = [[n] for n in nets]
    else:
        groups = []; byname = {}
        for nodes in nets:
            label = None
            for nd in nodes:
                if nd["label"] != "" and label is None: label = nd["label"]
                if nd["hasmethod"] and nd["mname"] in ("INPUT", "OUTPUT"): label = nd["mref"]
            if label is not None:
                b = bus(label)
                if b["is_bus"]:
                    if b["name"] not in byname: byname[b["name"]] = len(groups); groups.append([nodes])
                    else: groups[byname[b["name"]]].append(nodes)
            else: groups.append([nodes])
    for group in groups:
        conns = 0; typ = UNK; last_power = ""; info = None; where = None; sheet = 0
        done = False
        for nodes in group:
            for nd in nodes:
                if typ >= ERR_BASE: done = True; break
                k = nd["kind"]
                if k == "NONE": continue
                nodetype = UNK
                if k == "POWER":
                    nodetype = PWR
                    if last_power == "": last_power = nd["val"]
                    elif last_power != nd["val"]: typ = ERR_POWER; nodetype = UNK
                    sheet = nd["sheet"]
                    info = ("Obj=Power", "RefDes=N/A", "Sheet=#%d" % nd["sheet"], "XY=(%s,%s)" % (g(nd["a"][0] / 5), g(nd["a"][1] / 5)))
                    where = nd["parent"]
                elif k == "NOCONNECT":
                    nodetype = PAS; conns += 1; sheet = nd["sheet"]
                    info = ("Obj=No Connect", "RefDes=N/A", "Sheet=#%d" % nd["sheet"], "XY=(%s,%s)" % (g(nd["a"][0] / 5), g(nd["a"][1] / 5)))
                    where = nd["parent"]
                elif k == "PIN":
                    nodetype = {0: INP, 1: OUT, 2: BID, 3: BID, 4: PAS, 5: BID, 6: NOC}.get(nd["elec"], UNK)
                    if nd["ispower"]: nodetype = PWR
                    where = nd["act"]; sheet = nd["sheet"]; conns += 1
                    info = ("Obj=Pin", 'RefDes=%s, Pin Number=%s, Pin Name="%s"' % (nd["reference"], nd["pnum"], nd["pname"]), 'Sheet="%s"' % names[nd["sheet"] - 1],
                            "XY=(%s,%s)" % (g(nd["act"][0] / 5), g(nd["act"][1] / 5)))
                if typ < ERR_BASE:
                    if vhdl and nodetype == OUT and typ == OUT: pass
                    else: typ = TABLE[typ][nodetype]
                else:
                    done = True; break
            if done: break
        if conns == 1 and typ != NOC: typ = ERR_UNCONNECT
        if typ == UNK: e = ERR_UNCONNECTED if conns > 0 else 0
        elif typ == INP: e = ERR_NOUTPUT
        else: e = typ
        off = {ERR_UNCONNECT: "unconnect", ERR_POWER: "power", ERR_NOCONNECT: "noconnect", ERR_NOUTPUT: "nooutput", ERR_DUPREF: "dupref", ERR_OUTPUT: "output",
               ERR_OUTPUTTOPWR: "outputpwr", ERR_UNCONNECTED: "unconnected", ERR_OUTPUTBIDIR: "output", ERR_POWERBIDIR: "outputpwr"}
        if e in off and not O[off[e]]: e = -1
        if e >= ERR_BASE:
            msgs.append("%s:  [%s, %s, %s, %s]" % ((MSG[e],) + info)); mark(sheet, where)
    if not marks and always: msgs.append(MSG[ERR_NOERROR])
    return msgs, marks


# ---------------------------------------------------------------- changed copies of the sample designs
import random
LABELS = ["VCC", "Vcc", "vcc", "GND", "Gnd", "A", "a", "B(3:0)", "B(1)", "B(0)", "CLK", "clk", "Q(2:0)", "Q(1)"]
POWERS = ["5V", "+5V", "0V", "GND", "VCC", "5V", "P(1)", "P(0)", "P(2:0)", ""]
def variant(src, seed, dst):
    """Write a changed copy of a design: pin types changed at random, labels, power and no-connect markers put on pins and wire ends, references made '?' or duplicated and parts per package changed."""
    rng = random.Random(seed)
    nets = read_nodes(src)
    root = ET.parse(src).getroot()
    sheets = [root] if root.tag == "TinyCAD" else root.findall("TinyCAD")
    for pn in root.iter("PIN"):
        if rng.random() < 0.3: pn.set("elec", str(rng.choice([0, 1, 1, 2, 3, 4, 5, 6, 6, 7])))
    pts = [(nd["sheet"], nd["a"]) for nodes in nets for nd in nodes if nd["kind"] in ("PIN", "OTHER")]
    for _ in range(rng.randint(0, 14)):
        if not pts: break
        sh, (x, y) = rng.choice(pts)
        if sh > len(sheets): continue
        k = rng.choice(["label", "label", "power", "noconnect"])
        if k == "label":
            e = ET.SubElement(sheets[sh - 1], "LABEL", dict(pos="%.5f,%.5f" % (x / 5, y / 5), direction="3", font="0", color="208000", style="0")); e.text = rng.choice(LABELS)
        elif k == "power":
            e = ET.SubElement(sheets[sh - 1], "POWER", dict(pos="%.5f,%.5f" % (x / 5, y / 5), which=str(rng.randint(0, 3)), direction="0")); e.text = rng.choice(POWERS)
        else:
            ET.SubElement(sheets[sh - 1], "NOCONNECT", dict(pos="%.5f,%.5f" % (x / 5, y / 5)))
    syms = [s for sh in sheets for s in sh.findall("SYMBOL")]
    for _ in range(rng.randint(0, 3)):
        if not syms: break
        f = rng.choice(syms).findall("FIELD")[0]
        r = rng.random()
        if r < 0.4: f.set("value", f.get("value").rstrip("?") + "?")
        elif r < 0.8: f.set("value", rng.choice(syms).findall("FIELD")[0].get("value"))
    chosen = {}    # a symbol used on several sheets gets one answer on all of them
    for d in root.iter("SYMBOLDEF"):
        if d.get("id") not in chosen:
            chosen[d.get("id")] = str(rng.choice([2, 3, 4])) if rng.random() < 0.25 else None
        pp = d.find("PPP")
        if chosen[d.get("id")] and pp is not None: pp.text = chosen[d.get("id")]
    ET.ElementTree(root).write(dst, encoding="UTF-8", xml_declaration=True)


def two_sheets(src, dst, second="Second", rename=False):
    """A copy of a design whose only sheet is repeated as a second sheet with another name (so every reference is a duplicate and there are markers on both sheets)"""
    import copy
    r = ET.parse(src).getroot()
    sheets = [r] if r.tag == "TinyCAD" else r.findall("TinyCAD")
    root = ET.Element("TinyCADSheets")
    a = copy.deepcopy(sheets[0]); b = copy.deepcopy(sheets[0])
    b.find("NAME").text = second
    if rename:
        for sy in b.findall("SYMBOL"):
            for f in sy.findall("FIELD")[:1]: f.set("value", f.get("value") + "b")
    root.append(a); root.append(b)
    ET.ElementTree(root).write(dst, encoding="UTF-8", xml_declaration=True)
