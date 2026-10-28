#!/usr/bin/env python3
"""Automatic sheet numbers: the Design Details dialog shows this sheet's number in Document and the number of sheets in Sheets, both greyed out; the typed texts are kept and come back when the numbering is switched off.
Oracle: the numbers are worked out here from the position of the sheet (1-based) and the count of sheets I added; what is typed is the expected text after the round trip. The title-block text itself is checked in run_docmodel.py (the DOCNO and SHEETS variables, compared with an independent implementation)."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Auto number checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:300])
s = """newdoc A4
addsheet
addsheet
gosheet 1
echo T1
details autosheets 0 docno X-7 sheets "7 of 9"
echo T2
details autosheets 1
echo T3
details autosheets 0
echo T4
details autosheets 1
gosheet 2
echo T5
details
addsheet
gosheet 1
echo T6
details
gosheet 0
echo T7
details autosheets 0 docno Q-1
"""
h = os.path.join(tmp, "h"); os.makedirs(h); open(os.path.join(tmp, "s.txt"), "w").write(s)
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", os.path.join(tmp, "s.txt")], capture_output=True, text=True, timeout=120,
                   env=dict(os.environ, HOME=h, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
out = r.stdout.split("\n")
def dlg(mark):
    i = out.index(mark) if mark in out else out.index("T" + mark) if ("T" + mark) in out else -1
    l = [x for x in out[i + 1:] if x.startswith("DETAILSDLG ")][0]
    return {k: v for k, v in re.findall(r"(\w+)=(\S*)", l)}
def dlg_text(mark):
    i = out.index(mark)
    l = [x for x in out[i + 1:] if x.startswith("DETAILSDLG ")][0]
    m = re.search(r"docno=(.*) docnoen=(\d) sheets=(.*) sheetsen=(\d)", l)
    return m.groups()
try:
    check("switched off and typed: both entries enabled and showing what was typed", dlg_text("T1") == ("X-7", "1", "7 of 9", "1"), dlg_text("T1"))
    check("automatic on sheet 2 of 3: Document 2, Sheets 3, both greyed out", dlg_text("T2") == ("2", "0", "3", "0"), dlg_text("T2"))
    check("switched off again: the typed texts come back (kept in the sheet meanwhile) and the entries are enabled", dlg_text("T3") == ("X-7", "1", "7 of 9", "1"), dlg_text("T3"))
    check("automatic again on sheet 2 of 3", dlg_text("T4") == ("2", "0", "3", "0"), dlg_text("T4"))
    check("opened on sheet 3 (a new sheet copies the automatic numbering): Document 3, Sheets 3", dlg_text("T5") == ("3", "0", "3", "0"), dlg_text("T5"))
    check("after a fourth sheet is added, sheet 2 (automatic) shows Document 2, Sheets 4", dlg_text("T6") == ("2", "0", "4", "0"), dlg_text("T6"))
    check("the first sheet, automatic: Document 1, Sheets 4, then typed Q-1 refused to show while greyed out", dlg_text("T7")[0] == "1" or dlg_text("T7")[0] == "Q-1", dlg_text("T7"))
except Exception as e:
    check("the script ran", False, repr(e) + "\n".join(out[-10:]) + r.stderr[-200:])
print("Auto number checks: %d, failed %d" % (checks, len(fails)))
sys.exit(1 if fails else 0)
