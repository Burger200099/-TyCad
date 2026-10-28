"""Design Details > Details tab > Apply to All: the Details tab's settings go to every sheet, the other tabs' settings stay as each sheet had them,
and it is one undo step. Expected values are the ones typed in the script."""
import os, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
exe = os.environ.get("TC_GUI_BIN", "/tmp/sch")
tmp = tempfile.mkdtemp()
out_dsn = tmp + "/aa.dsn"
script = f"""newdoc "ISO A4" landscape
addsheet
addsheet
gosheet 1
details horiz 7 notes "sheet two notes"
gosheet 2
details horiz 9
gosheet 0
details title "Plant X" author "Me" org "Org" date "Oct 21, 2026" ext 1 visible 0 horiz 5 all
undoinfo
save {out_dsn}
"""
open(tmp + "/s.txt", "w").write(script)
r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", tmp + "/s.txt"], capture_output=True, text=True, timeout=240)
bad = []
def check(n, ok, d=""):
    print(("ok   " if ok else "FAIL ") + n + ("" if ok else " " + str(d)))
    if not ok: bad.append(n)
sheets = ET.parse(out_dsn).getroot().findall("TinyCAD")
check("three sheets", len(sheets) == 3, len(sheets))
for i, sh in enumerate(sheets):
    d = sh.find("DETAILS")
    got = (d.findtext("TITLE"), d.findtext("AUTHOR"), d.findtext("ORGANISATION"), d.findtext("DATE"), d.findtext("SHOWS"), (d.find("EXTBLOCK").get("show") if d.find("EXTBLOCK") is not None else None))
    check(f"sheet {i + 1} has the Details tab's title, author, organisation, date, title block hidden, extended info on", got == ("Plant X", "Me", "Org", "Oct 21, 2026", "0", "1"), got)
check("the other tabs are not copied: sheet 2 keeps its own rulers (7) and notes, sheet 3 its rulers (9)",
      sheets[1].find("DETAILS/GUIDES").get("horiz") == "7" and sheets[1].findtext("DETAILS/NOTES") == "sheet two notes" and sheets[2].find("DETAILS/GUIDES").get("horiz") == "9", "")
check("sheet 1, the one in the dialog, got everything (rulers 5)", sheets[0].find("DETAILS/GUIDES").get("horiz") == "5", "")
check("one undo step named Design details (all sheets)", 'next="Design details (all sheets)"' in r.stdout, r.stdout[-300:])
sys.exit(1 if bad else 0)
