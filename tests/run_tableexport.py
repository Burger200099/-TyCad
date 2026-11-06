#!/usr/bin/env python3
"""Table export (src/UTableExport.pas and the writers UCSVExport, UXLSXExport, UODSExport): a test table with awkward cells (commas, quotes, line ends, leading and doubled
spaces, a tab, accented and Asian letters, & < >, whole and fractional numbers, an empty cell, a bold heading row, column widths, a second sheet named with forbidden characters)
is written by the program's own script command `tableexport <file>` with the writer the extension names, and read back by programs that are not ours:
  - .csv: the bytes are compared with the file written out here (RFC 4180)
  - .xlsx: read with openpyxl: sheet names (the forbidden characters replaced), every value and its type, bold heading, frozen first row, column widths; then LibreOffice
    converts it to CSV and the first sheet must equal the table
  - .ods: LibreOffice converts it to CSV and the first sheet must equal the table; odfpy reads the sheet names and the value types
  - an extension nobody registered, and a folder that does not exist, give an error and no file
Needs xvfb-run and the built program (openpyxl, odfpy and LibreOffice are used when installed)."""
import os, shutil, subprocess, sys, tempfile, zipfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("table export checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:600])
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300,
                       env=dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.splitlines()
fc, fx, fo = (os.path.join(tmp, "t" + e) for e in (".csv", ".xlsx", ".ods"))
out = run(["newdoc A4", "tableexport " + fc, "tableexport " + fx, "tableexport " + fo, "tableexport " + os.path.join(tmp, "t.xyz"), "tableexport " + os.path.join(tmp, "nodir", "t.csv")])
res = [l for l in out if l.startswith("TABLEEXPORT")]
check("the three formats are written, an unknown extension and a missing folder are errors", len(res) == 5 and all(l.startswith("TABLEEXPORT ok") for l in res[:3]) and all("error" in l for l in res[3:]), res)
check("no file is left by the failures (no .tmp either)", not os.path.exists(os.path.join(tmp, "t.xyz")) and not os.path.exists(os.path.join(tmp, "nodir")) and not [f for f in os.listdir(tmp) if f.endswith(".tmp")], os.listdir(tmp))
want_rows = [["Name", "Qty", "Value", "Note"], ["plain", "3", "1.5", "ok"], ["a,b", "10", "0.1", 'say "hi"'], ["two\nlines", "-4", "1234567.125", "  leading and  double"],
             ["Ω µ é 日本", "0", "2", "tab\there"], ["fixed", "7", "3.14", ""], ["<&>", "1", "0.0000001", "semi;colon"]]
def q(s): return '"' + s.replace('"', '""') + '"' if any(c in s for c in ',"\n\r') else s
want_csv = "".join(",".join(q(c) for c in r) + "\n" for r in want_rows)
check("csv: the bytes are RFC 4180 with UTF-8 and no byte order mark", open(fc, "rb").read() == want_csv.encode("utf-8"), open(fc, "rb").read())
import csv, io
def csv_rows(p):
    return [r for r in csv.reader(open(p, encoding="utf-8", newline=""))]
def lo_csv(src, sub):
    """LibreOffice's own CSV of the first sheet of a file"""
    if shutil.which("soffice") is None: return None
    d = os.path.join(tmp, sub); os.makedirs(d, exist_ok=True)
    subprocess.run(["soffice", "--headless", "--convert-to", "csv", "--outdir", d, src], capture_output=True, timeout=200, env=dict(os.environ, HOME=os.path.join(tmp, "lohome")))
    p = os.path.join(d, os.path.splitext(os.path.basename(src))[0] + ".csv")
    return csv_rows(p) if os.path.exists(p) else None
try:
    import openpyxl
    wb = openpyxl.load_workbook(fx)
    check("xlsx: two tabs, the forbidden characters of the second name replaced", wb.sheetnames == ["Parts & <things>", "Sheet_2_"], wb.sheetnames)
    ws = wb.worksheets[0]
    got = [list(r) for r in ws.iter_rows(values_only=True)]
    exp = [["Name", "Qty", "Value", "Note"], ["plain", 3, 1.5, "ok"], ["a,b", 10, 0.1, 'say "hi"'], ["two\nlines", -4, 1234567.125, "  leading and  double"],
           ["Ω µ é 日本", 0, 2, "tab\there"], ["fixed", 7, 3.14, None], ["<&>", 1, 1e-07, "semi;colon"]]
    check("xlsx: every value, numbers as numbers and text as text (spaces, tab and line end kept)", got == exp, got)
    check("xlsx: the heading is bold and the rest is not, the first row is frozen", ws["A1"].font.b and ws["D1"].font.b and not ws["A2"].font.b and ws.freeze_panes == "A2", (ws["A1"].font.b, ws.freeze_panes))
    check("xlsx: column widths", abs(ws.column_dimensions["A"].width - 21) < 0.01 and abs(ws.column_dimensions["D"].width - 41) < 0.01, (ws.column_dimensions["A"].width, ws.column_dimensions["D"].width))
    ws2 = wb.worksheets[1]
    check("xlsx: the second tab", [list(r) for r in ws2.iter_rows(values_only=True)] == [["A", "B"], ["x", 1]], [list(r) for r in ws2.iter_rows(values_only=True)])
except ImportError:
    print("  (xlsx read-back skipped: openpyxl is not installed)")
r = lo_csv(fx, "lox")
if r is None: print("  (LibreOffice not available: the conversions are skipped)")
else: check("LibreOffice reads the xlsx and gives the table", r == want_rows, r)
r = lo_csv(fo, "loo")
if r is not None: check("LibreOffice reads the ods and gives the table", r == want_rows, r)
z = zipfile.ZipFile(fo)
check("ods: the mimetype comes first and is stored, not compressed", z.namelist()[0] == "mimetype" and z.getinfo("mimetype").compress_type == 0 and z.read("mimetype") == b"application/vnd.oasis.opendocument.spreadsheet", (z.namelist(), z.getinfo("mimetype").compress_type))
try:
    from odf.opendocument import load
    from odf.table import Table, TableRow, TableCell
    d = load(fo); tabs = d.spreadsheet.getElementsByType(Table)
    check("ods: two tables, the forbidden characters replaced", [t.getAttribute("name") for t in tabs] == ["Parts & <things>", "Sheet_2_"], [t.getAttribute("name") for t in tabs])
    row = tabs[0].getElementsByType(TableRow)[1].getElementsByType(TableCell)
    check("ods: numbers are float cells and text string cells", [c.getAttribute("valuetype") for c in row] == ["string", "float", "float", "string"], [c.getAttribute("valuetype") for c in row])
except ImportError:
    print("  (ods read-back skipped: odfpy is not installed)")
print("table export: %d checks, %d failed" % (checks, len(fails)))
sys.exit(1 if fails else 0)
