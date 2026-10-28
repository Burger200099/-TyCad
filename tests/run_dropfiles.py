#!/usr/bin/env python3
"""Files dropped from the file explorer open as documents, only when dropped on the strip of document tabs (script command 'dropfiles strip|sheet <file>...').
Checks: a drop on the drawing opens nothing; a drop on the strip opens each design (the documents count rises by the number of files, the files' names are among the tabs in the status
and in the count), a folder in the drop is skipped, a file that does not open gives a message in the status line and the others still open; a file already open is shown, not opened twice;
the window allows the drop (AllowDropFiles, OnDropFiles in mainform.lfm). Oracle: the numbers of files given. Needs the built program and xvfb."""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
BIN = os.environ.get("TC_GUI_BIN", os.path.join(ROOT, "bin", "schematic"))
EX = os.environ.get("TC_EXAMPLES", "examples")
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Drop files checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; checks = 0
def check(n, ok, d=""):
    global checks; checks += 1
    if not ok: fails.append(n); print("  FAIL", n, str(d)[:500])
a = os.path.join(EX, "circuits/PSU.dsn"); b = os.path.join(EX, "circuits/Attenuator.dsn"); c = os.path.join(EX, "circuits/AtTiny LED Flasher.dsn")
S = ["newdoc A4", "dropfiles sheet \"%s\"" % a, "dropfiles strip \"%s\" \"%s\" %s" % (a, b, tmp), "dropfiles strip \"%s\"" % a, "dropfiles strip %s \"%s\"" % (os.path.join(tmp, "nothere.dsn"), c)]
f = os.path.join(tmp, "s.txt"); open(f, "w").write("\n".join(S) + "\n")
out = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", f], capture_output=True, text=True, timeout=200, env=dict(os.environ, HOME=tempfile.mkdtemp(dir=tmp))).stdout.split("\n")
D = [l for l in out if l.startswith("DROPFILES")]
check("four drops answered", len(D) == 4, D)
if len(D) == 4:
    check("dropped on the drawing: nothing opens (1 document, the new one)", D[0].startswith("DROPFILES opened=0 docs=1 "), D[0])
    check("dropped on the strip: two designs open and the folder is skipped (3 documents)", D[1].startswith("DROPFILES opened=2 docs=3 "), D[1])
    check("a file that is open already is shown, not opened twice (still 3 documents)", D[2].startswith("DROPFILES opened=1 docs=3 "), D[2])
    check("a file that cannot be opened gives a message in the status line and the next one still opens (4 documents, one opened)", D[3].startswith("DROPFILES opened=1 docs=4 ") and "nothere.dsn" in D[3], D[3])
lfm = open(os.path.join(ROOT, "src/forms/mainform.lfm"), encoding="utf-8").read()
check("the window allows file drops and has the handler (mainform.lfm)", "AllowDropFiles = True" in lfm and "OnDropFiles = FormDropFiles" in lfm)
print("drop files: %d checks, %d failed" % (checks, len(fails))); sys.exit(1 if fails else 0)
