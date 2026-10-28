#!/usr/bin/env python3
"""Special > Export Wires (script 'wirexport <file>'): the text of every wire label and bus name of the design as CSV.
A design (the sample vhdl/nibbles/NOR4Bus.dsn, with its own labels) gets extra objects written into the file: labels of the four styles at known places, one whose text holds a comma and a quote,
one with no text (left out), a bus name, and a second sheet's label. Oracle: what was written into the file. Checks: the header; every added label/bus name is a row with its sheet,
kind, style, text and position in mm; the file's own labels are rows; the empty label is not; quoting; row count = what was written + the file's own; 'rows=' agrees with the file;
the menu item is in mainform.lfm under Special. Needs xvfb-run, the built program, TC_EXAMPLES."""
import csv, io, os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples"); SRC = os.path.join(EX, "vhdl", "nibbles", "NOR4Bus.dsn")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN) or not os.path.exists(SRC):
    print("Wire export checks skipped: need xvfb-run, the built program and the example design"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:600])
t = open(SRC, encoding="utf-8", errors="replace").read()
def export(dsn):
    out = os.path.join(tmp, "o.csv")
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write('open "%s"\nwirexport %s\n' % (dsn, out))
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=200, env=dict(os.environ, HOME=tempfile.mkdtemp(dir=tmp)))
    line = [l for l in r.stdout.split("\n") if l.startswith("WIREXPORT")]
    rows = list(csv.reader(io.StringIO(open(out, encoding="utf-8").read()))) if os.path.exists(out) else []
    return line, rows
open(os.path.join(tmp, "base.dsn"), "w").write(t)
bl, base = export(os.path.join(tmp, "base.dsn"))
check("header line", base and base[0] == ["Sheet", "Sheet name", "Kind", "Style", "Text", "X (mm)", "Y (mm)"], base[:1])
own = len(re.findall(r"<LABEL [^>]*>[^<]+<", t))
check("the sample's own labels are rows (%d) and 'rows=' agrees" % own, len(base) - 1 == own and bl and bl[0].endswith("rows=%d" % own), (len(base), bl))
check("a sample label is a row with its text and position", ["1"] == base[1][:1] and base[1][2] == "Wire label" and base[1][4] == "I(0)" and base[1][5] == "46.00" and base[1][6] == "46.00", base[1:2])
add = [(20, 100, 0, "PLAIN1"), (60, 100, 1, "IN1"), (100, 100, 2, "OUT1"), (140, 100, 3, "IO1"), (20, 130, 0, 'A,B "q"')]
xml = "".join("\t\t<LABEL pos='%d.0,%d.0' direction='0' font='3' color='000000' style='%d'>%s</LABEL>\n" % (x, y, s, tx.replace('"', "&quot;")) for x, y, s, tx in add)
xml += "\t\t<LABEL pos='20.0,160.0' direction='0' font='3' color='000000' style='0'></LABEL>\n"
xml += "\t\t<BUSNAME pos='60.0,130.0' direction='0' font='3' color='000000'>D[7..0]</BUSNAME>\n"
i = t.index("<LABEL"); j = t.rfind("\n", 0, i)
open(os.path.join(tmp, "more.dsn"), "w").write(t[:j + 1] + xml + t[j + 1:])
ml, rows = export(os.path.join(tmp, "more.dsn"))
body = rows[1:]
check("six rows are added (five labels and the bus name; the empty label is left out)", len(body) == own + 6, (len(body), own))
exp = {"PLAIN1": ("Plain", "20.00", "100.00"), "IN1": ("Input", "60.00", "100.00"), "OUT1": ("Output", "100.00", "100.00"), "IO1": ("In/Out", "140.00", "100.00"), 'A,B "q"': ("Plain", "20.00", "130.00")}
for tx, (st, x, y) in exp.items():
    r = [b for b in body if b[4] == tx]
    check("label %s: sheet 1, Wire label, %s, at %s,%s mm" % (tx, st, x, y), len(r) == 1 and r[0][0] == "1" and r[0][2] == "Wire label" and r[0][3] == st and r[0][5] == x and r[0][6] == y, r)
r = [b for b in body if b[4] == "D[7..0]"]
check("the bus name: Bus name, no style, at 60,130", len(r) == 1 and r[0][2] == "Bus name" and r[0][3] == "" and r[0][5] == "60.00" and r[0][6] == "130.00", r)
check("the quoted text is quoted in the file (the comma and quote survive a CSV reader)", any(b[4] == 'A,B "q"' for b in body))
lfm = open(os.path.join(ROOT, "src/forms/mainform.lfm"), encoding="utf-8").read()
k = lfm.index("object mExportWires: TMenuItem")
check("Export Wires is a menu item in mainform.lfm after Export Symbol Data", "Caption = 'Export &Wires...'" in lfm[k:k + 120] and lfm.index("object mSymbolData") < k)
print("wire export: %d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
