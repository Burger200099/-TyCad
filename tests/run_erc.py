"""The design rules check (UErc), against TinyCAD's Net.cpp (DoSpecialCheck / DoSpecialVHDLCheck) restated in ercoracle.py.
The program under test is erctest (the check) and nettest ercnodes (the netlist's nodes, which the oracle uses as its nets; the netlist build itself is checked
against TinyCAD's own files by run_netlist.py). The oracle reads the placed symbols from the design's XML itself. What is compared, for each design, for the
plain check and the VHDL check, and for several option words (the checks that are on):
  - the number of errors, every marker (its number, sheet and point) and every line of the result list, in order
  - that running the check twice does not stack the markers and that clearing removes them all
Also: printf's %g (six digits, exact ties to even, the exponent form), the packing of the options into the registry WORD, and the coverage of the samples and of
the variants made from them (output and pin types changed at random, labels, power and no-connect markers put on pins and wire ends, references made "?" or
duplicated, parts per package changed): every kind of message must occur, and the VHDL check must differ from the plain one where the C++ says it does.
Needs the built erctest and nettest."""
import glob, os, random, re, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ercoracle as eo

EXAMPLES = os.environ.get("TC_EXAMPLES", "examples")
BUILD = os.environ.get("TC_BUILD", "build")
ET_ = os.path.join(BUILD, "erctest")
tmp = tempfile.mkdtemp()
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok:
        fails.append(n)
        if len(fails) <= 12: print("  FAIL", n, str(d)[:600])

def program(dsn, vhdl, word):
    r = subprocess.run([ET_, "check", "1" if vhdl else "0", str(word), dsn], capture_output=True, text=True)
    return r.returncode, r.stdout.split("\n")

kinds_seen = {False: set(), True: set()}
def compare(dsn, label, words, modes=(False, True)):
    try:
        nets = eo.read_nodes(dsn); names, placed = eo.read_placed(dsn)
    except Exception as e:
        return 0
    if nets is None: return 0
    n = 0
    for vhdl in modes:
        for word in words:
            rc, out = program(dsn, vhdl, word)
            msgs, marks = eo.erc(nets, placed, names, word, vhdl)
            want = ["N %d" % len(marks)] + ["M %d %d %s %s" % (m[0], m[1], eo.g(m[2]), eo.g(m[3])) for m in marks] + ["L " + l.replace("\n", "\\n") for l in msgs]
            got = [l for l in out if l[:1] in ("N", "M", "L")]
            gm = sorted([l for l in got if l[0] == "M"], key=lambda l: int(l.split()[1]))
            got = [l for l in got if l[0] == "N"] + gm + [l for l in got if l[0] == "L"]
            check(f"{label} vhdl={vhdl} word={word}", rc == 0 and got == want, (rc, [a for a, b in zip(got, want) if a != b][:1], [b for a, b in zip(got, want) if a != b][:1], len(got), len(want)))
            # the second run replaces the markers; clearing removes them
            n_err = len(marks)
            a = [l for l in out if l[:1] == "A"]; c = [l for l in out if l[:1] == "C"]
            sm, sk = eo.erc(nets, placed, names, word, vhdl, always=False); second = len(sk)
            check(f"{label} vhdl={vhdl} word={word} second run", a == [f"A {second} {second} {len(sm)}"], a)
            check(f"{label} vhdl={vhdl} word={word} clear", c == [f"C {second} 0"], c)
            for l in msgs: kinds_seen[vhdl].add(re.sub(r":  .*", "", l, flags=re.S))
            n += 1
    return n

# ---------------------------------------------------------------- 1. %g
random.seed(11)
vals = [0.0, -0.0, 1e-5, 1e-4, 0.0001234565, 123456.0, 999999.5, 999999.4, 1e6, 1e-300, 5e-324, 1.7976931348623157e308, 0.1, 100.0, 644462.5, 1540565.0, 0.5, 2.5, 1234.125]
for _ in range(6000):
    k = random.choice(range(6))
    if k == 0: vals.append(random.uniform(-1000, 1000))
    elif k == 1: vals.append(round(random.uniform(0, 2000), random.choice([1, 2, 3, 4, 5, 6, 7])))
    elif k == 2: vals.append(random.randint(-100000, 100000000) / 5)
    elif k == 3: vals.append(random.choice([1, 10, 100]) * random.randint(1, 9999999) / 10 ** random.randint(0, 9))
    elif k == 4: vals.append(random.uniform(-1, 1) * 10 ** random.randint(-12, 12))
    else: vals.append(random.randint(1, 99999999) / random.choice([2, 4, 8, 16]))
p = os.path.join(tmp, "g.txt"); open(p, "w").write("\n".join(repr(v) for v in vals) + "\n")
out = subprocess.run([ET_, "g", p], capture_output=True, text=True).stdout.split("\n")
bad = [(v, o) for v, o in zip(vals, out) if o != "R " + ("%g" % v)]
check("%g of 6000 numbers", not bad and len(out) >= len(vals), bad[:3])

# ---------------------------------------------------------------- 2. the options word
p = os.path.join(tmp, "w.txt"); open(p, "w").write("\n".join(str(i) for i in range(65536)) + "\n")
out = subprocess.run([ET_, "word", p], capture_output=True, text=True).stdout.split("\n")
check("every word packs back to its low eleven bits", all(out[i] == "R %d" % (i & 0x7FF) for i in range(65536)), out[:3])

# ---------------------------------------------------------------- 3. every sample design
WORDS = [0xFFFF, 0, 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 0x3FF, 0x500, 0x2AA]
files = sorted(glob.glob(os.path.join(EXAMPLES, "**", "*.dsn"), recursive=True))
used = total = 0
for pth in files:
    k = compare(pth, os.path.basename(pth), [0xFFFF, 0, random.choice(WORDS), random.choice(WORDS)])
    if k: used += 1; total += k
print(f"sample designs: {used}, {total} checks compared")
check("samples were found", used >= 30, used)

# ---------------------------------------------------------------- 4. variants
SMALL = [pth for pth in files if os.path.getsize(pth) < 120000]
random.shuffle(SMALL)
SMALL = SMALL[:14] + [pth for pth in files if os.path.basename(pth) in ("NOR4Bus.dsn", "UALogic4.dsn", "ArithmeticUnit.dsn")]
nv = 0
for i, src in enumerate(SMALL):
    for j in range(8):
        dst = os.path.join(tmp, f"v{i}_{j}.dsn")
        try: eo.variant(src, i * 100 + j, dst)
        except Exception as e: print("variant failed", src, e); continue
        words = [0xFFFF, random.choice(WORDS), random.randint(0, 0x7FF)]
        nv += compare(dst, f"variant {os.path.basename(src)}#{j}", words)
print(f"variants: {nv} checks compared")
# two sheets whose references differ, so that a package can have its first part on the second sheet
n2 = 0
for i, src in enumerate(SMALL[:10]):
    for j in range(3):
        dst = os.path.join(tmp, f"t{i}_{j}.dsn"); dst2 = os.path.join(tmp, f"t{i}_{j}v.dsn")
        try:
            eo.two_sheets(src, dst, rename=True); eo.variant(dst, 5000 + i * 10 + j, dst2)
        except Exception as e: print("two-sheet variant failed", src, e); continue
        n2 += compare(dst2, f"two sheets {os.path.basename(src)}#{j}", [0xFFFF, 0x80, random.randint(0, 0x7FF)])
print(f"two-sheet variants: {n2} checks compared")

# ---------------------------------------------------------------- 5. coverage
want_kinds = [eo.MSG[k] for k in (eo.ERR_UNCONNECT, eo.ERR_POWER, eo.ERR_NOCONNECT, eo.ERR_NOUTPUT, eo.ERR_DUPREF, eo.ERR_OUTPUT, eo.ERR_OUTPUTTOPWR,
              eo.ERR_UNCONNECTED, eo.ERR_OUTPUTBIDIR, eo.ERR_POWERBIDIR, eo.ERR_UNASSIGNEDREFDES, eo.ERR_NONDISTINCTNET, eo.ERR_MULTIPLENETNAMES, eo.ERR_NOERROR)]
want_kinds.append("Not all parts in this package are in this design")
for k in want_kinds:
    check(f"message occurs in the plain check: {k[:50]}", k in kinds_seen[False], k)
for k in want_kinds:
    if k != eo.MSG[eo.ERR_OUTPUT]:
        check(f"message occurs in the VHDL check: {k[:50]}", k in kinds_seen[True], k)
check("the VHDL check never reports output to output", eo.MSG[eo.ERR_OUTPUT] not in kinds_seen[True])

print(f"{checks} checks, {len(fails)} failed")
sys.exit(1 if fails else 0)
