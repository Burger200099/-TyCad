"""Table cells linked to the text of other objects (the arrow of the table editor's cell lists them): the list is Kind:"text", sorted alphabetically, of the current sheet; a
linked cell shows the object's text and follows it when it changes; typing in the cell cuts the link; unlink keeps the text; deleting the object gives #REF!; a table pasted
on another sheet loses its links and the linked cells are blank, a table duplicated on the same sheet keeps them; the links are saved and read back. Oracle: TABLESOURCE /
TABLECELL / TABLELINK script output. Needs xvfb-run and the built program."""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Table link checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
fails = []; n = [0]
def check(name, ok, d=""):
    n[0] += 1
    if not ok: fails.append(name); print("  FAIL", name, str(d)[:500])
def run(script):
    p = os.path.join(tmp, "s.txt"); open(p, "w").write(script)
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", p], capture_output=True, text=True, timeout=300,
                       env=dict(os.environ, HOME=tempfile.mkdtemp(dir=tmp), FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf")))
    return r.stdout.splitlines()
def cells(out):
    res = {}
    for l in out:
        m = re.match(r"TABLECELL (\d+) (\d+) ?(.*)", l)
        if m: res[(int(m.group(1)), int(m.group(2)))] = m.group(3)
    return res
def links(out):
    return [tuple(map(int, m.groups())) for l in out for m in [re.match(r"TABLELINK (\d+) (\d+) (\d+) (-?\d+)", l)] if m]
mk = "newdoc A4\ngridmm 2\nregisterframe x all\naddtext 80 120 Visible\naddtext 80 140 Alpha\ntable new\nmouse move 150 60\nmouse down 150 60\nmouse up 150 60\n"
out = run(mk + "table sources\n")
src = [l.split(" ", 2)[2] for l in out if l.startswith("TABLESOURCE")]
check("the list is Kind:\"text\", sorted alphabetically", src == ['Text:"Alpha"', 'Text:"Visible"'], src)
out = run(mk + 'table link 1 0 Text:"Visible"\ntable link 2 1 Text:"Alpha"\ntable info\n')
c = cells(out); lk = links(out)
check("linked cells show the texts of their objects", c.get((1, 0)) == "Visible" and c.get((2, 1)) == "Alpha", c)
check("two links are kept (row, column, object id, field -1)", len(lk) == 2 and lk[0][:2] == (1, 0) and lk[0][3] == -1, lk)
ch = 'selectobj 0\nframeact sel edText text Gamma\n'
out = run(mk + 'table link 1 0 Text:"Visible"\n' + ch + 'selectobj 2\ntable info\n')
check("the cell follows the object when its text changes", cells(out).get((1, 0)) == "Gamma", cells(out))
out = run(mk + 'table link 1 0 Text:"Visible"\ntable cell 1 0 typed\ntable info\n')
check("typing in a linked cell cuts the link", cells(out).get((1, 0)) == "typed" and links(out) == [], (cells(out), links(out)))
out = run(mk + 'table link 1 0 Text:"Visible"\ntable unlink 1 0\n' + ch + 'selectobj 2\ntable info\n')
check("unlink: the text stays and no longer follows", cells(out).get((1, 0)) == "Visible" and links(out) == [], (cells(out), links(out)))
out = run(mk + 'table link 1 0 Text:"Visible"\nselectobj 0\ndelete\nselectobj 1\ntable info\n')
check("the object deleted: the cell says #REF! and the link is gone", cells(out).get((1, 0)) == "#REF!" and links(out) == [], (cells(out), links(out)))
dsn = os.path.join(tmp, "l.dsn")
run(mk + 'table link 1 0 Text:"Visible"\nsave "%s"\n' % dsn)
t = open(dsn, encoding="utf-8").read(); m = re.search(r"<TABLE [^>]*>", t)
check("saved with links='row:col:id:field'", m and re.search(r"links='1:0:\d+:-1'", m.group(0)), m and m.group(0))
out = run('open "%s"\nselectobj 2\ntable info\n' % dsn)
check("read back: linked", links(out) and cells(out).get((1, 0)) == "Visible", (links(out), cells(out)))
out = run(mk + 'table link 1 0 Text:"Visible"\ntable info\ncopy\nduplicate\ntable info\n')
dup = [l for l in out if l.startswith("TABLELINK")]
check("duplicated on the same sheet: keeps its links", len(dup) >= 2, out[-12:])
out = run(mk + 'table link 1 0 Text:"Visible"\ntable link 2 1 Text:"Alpha"\nselectobj 2\ncopy\naddsheet\ngosheet 1\npaste\nmouse down 100 100\nmouse up 100 100\ntable info\n')
c = cells(out)
check("pasted on another sheet: links cut and the linked cells blank", links(out) == [] and c.get((1, 0)) == "" and c.get((2, 1)) == "" and c.get((0, 0)) == "A", (links(out), c, out[-14:]))
print("table links: %d checks, %d failed" % (n[0], len(fails))); sys.exit(1 if fails else 0)
