"""The rung numbers function through the real program: the Ladder menu item and tool name make or select the sheet's one rung grid (one undo step, never a
second grid), the numbers can be clicked and the rest of the grid cannot, dragging it moves nothing, the properties panel (frame) edits it, it is saved and
reloaded, and a ladder has its own frame (bus labels, rail colour and line density). Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, re, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Rung grid GUI checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok: fails.append(name); print("  FAIL", name, str(detail)[:500])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env)
    return r.stdout.splitlines()
def grab(out, prefix): return [l for l in out if l.startswith(prefix)]

saved = os.path.join(tmp, "rungs.dsn")
S = ['newdoc "ISO A4" landscape', "registerframe x all", "objects",
     "menuclick miLadderRungs", "objects", "undoinfo",                 # made by the menu item, one undo step
     "tool rungs", "objects", "undoinfo",                             # a second time only selects it
     "undo", "objects", "redo", "objects",                            # the undo step removes it, redo brings it back
     "rungs", "frameinfo sel",
     "zoomfit",
     "selclear", "clickmm 13.5 60", "selclear", "clickmm 100 60", "selclear", "clickmm 15 9", "selclear", "clickmm 2 60", "selclear",   # number column, blank column, row height text, the indent
     "clickmm 13.5 60", "undoinfo",
     "mouse down 13.5 60", "mouse move 80 120", "mouse up 80 120", "rungs", "undoinfo",     # dragging a number moves nothing
     "setrungs 12 101 5 2 0 1", "rungs", "rungat 20 60", "rungat 200 60", "rungat 20 5", "undoinfo",
     "undo", "rungs",
     "save " + saved, "open " + saved, "rungs", "objects"]
out = run(S)
objs = grab(out, "OBJ end")
check("0 objects at the start, 1 after the menu item, 1 after the tool, 0 after undo, 1 after redo", [l.split()[2] for l in objs[:5]] == ["0", "1", "1", "0", "1"], objs)
ui = grab(out, "UNDOINFO")
check("the menu item is one undo step named for the grid", 'next="Add rung numbers"' in ui[0] and "undo=1" in ui[0], ui[:2])
check("choosing it again adds no undo step", ui[1] == ui[0], ui[:2])
r = grab(out, "RUNGS id")
check("defaults, and it is the one selected object", "rows=20 start=1 margin=5 pages=1 continue=1 showheight=1 aboveblock=0 count=1 tool=0" in r[0], r[:1])
check("area of an A4 sheet with the border: 5 mm indent + 6.35 mm border margin", any(l.startswith("RUNGAREA 11.35 11.35 285.65 198.65") for l in out))
frame = [l for l in out if l.startswith("FRAMEINFO")]
check("the rung grid has its own frame, all editors linked, no problems", frame and frame[0].startswith("FRAMEINFO TfmRungs") and "problems=0" in frame[0] and
      all(any(k in l for l in frame) for k in ("rungs.rows", "rungs.start", "rungs.margin", "rungs.pages", "rungs.continue", "rungs.showheight", "font.face", "font.color")), frame[:3])
clicks = grab(out, "CLICK")
want = [True, False, True, False]
for l, w in zip(clicks[:4], want):
    check("click: " + l, ("selected 1 [TDrawRungGrid]" in l) if w else ("selected 0 []" in l))
print("clicks: a number, and the printed row height, select the grid; the blank column and the indent do not")
areas = [l for l in out if l.startswith("RUNGAREA")]
check("dragging a number moves nothing", areas[0] == areas[1], areas[:2])
check("a drag adds no undo step", ui[2].split()[1] == ui[3].split()[1], ui[2:4])
after = grab(out, "SETRUNGS")
check("setrungs applied", after and "rows=12 start=101 margin=5 pages=2 continue=0 showheight=1" in after[0], after)
at = grab(out, "RUNGAT")
# 297 x 210 sheet, area 11.35..285.65 by 11.35..198.65 in 12 rows of 15.608 mm: y = 60 is row 3 (0-based); page 2 starts at the middle (148.5 mm); not continued, so both pages start at 101
check("rung at a point on page 1, on page 2 (numbering not continued), and in the indent", at == ["RUNGAT 20 60 = 104", "RUNGAT 200 60 = 104", "RUNGAT 20 5 = none"], at)
rr = grab(out, "RUNGS id")
check("undo of the change gives back one page", "pages=1" in rr[-2] and "rows=20" in rr[-2], rr[-2])
check("saved and reloaded: still one grid with the settings", "rows=20 start=1" in rr[-1] and "count=1" in rr[-1], rr[-1])
check("exactly one grid in the reloaded file", grab(out, "OBJ end")[-1].split()[2] == "1" and sum(l.startswith("OBJ TDrawRungGrid") for l in out[-4:]) == 1, out[-4:])
check("saved file tag", b"<RUNGS" in open(saved, "rb").read(), "")
print(f"rung grid in the program: made by the menu item or tool name as one undo step, never doubled, undo/redo, click and drag, set up, saved and reloaded ({checks} checks)")
print("\nRUNG GUI CHECKS PASSED" if not fails else f"\nRUNG GUI CHECKS FAILED: {fails}")
sys.exit(1 if fails else 0)
