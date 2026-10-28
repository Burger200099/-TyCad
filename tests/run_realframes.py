#!/usr/bin/env python3
"""The property frames made in the designer (QPropWire, QRectCircle, QCloudNote, QPropText, QPropWireLabel, QPropNote, QPowerSym, QMeasure), registered in
QPropFrameList and linked to the properties by the control=property lists: each frame is shown for its tool and for a selection of its kind, shows the values of the
object, and what is clicked, chosen or typed in it changes the object (or the tool). Needs xvfb-run and the built program (TC_GUI_BIN or ../bin/schematic)."""
import os, re, sys, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("TC_GUI_BIN", os.path.join(HERE, "..", "bin", "schematic"))
if shutil.which("xvfb-run") is None or not os.path.exists(BIN):
    print("Real frame checks skipped: need xvfb-run and the built program"); sys.exit(0)
tmp = tempfile.mkdtemp(); fails = []; checks = 0
def check(name, ok, detail=""):
    global checks; checks += 1
    if not ok:
        fails.append(name); print("  FAIL", name, str(detail)[:600])
exe = os.path.join(tmp, "schematic"); shutil.copy(BIN, exe); os.chmod(exe, 0o755)
home = os.path.join(tmp, "home"); os.makedirs(home)
env = dict(os.environ, HOME=home, FONTCONFIG_FILE=os.environ.get("FONTCONFIG_FILE", "/tmp/fc/fonts.conf"))
def run(lines):
    sp = os.path.join(tmp, "s.txt"); open(sp, "w").write("\n".join(lines) + "\n")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", exe, "--script", sp], capture_output=True, text=True, timeout=300, env=env)
    return r.stdout.splitlines()
def blocks(out, marker):
    """the FRAMEINFO lines after each line that starts with the marker, as one dict per block: header, and name -> line of each editor"""
    res = []
    for i, l in enumerate(out):
        if l == marker:
            d = {"lines": []}
            j = i + 1
            while j < len(out) and not out[j].startswith("FRAMEINFO ") and j < i + 8: j += 1      # (a PROPS line may come first)
            for m in out[j:]:
                if not m.startswith("FRAMEINFO "): break
                d["lines"].append(m[10:])
            d["head"] = d["lines"][0] if d["lines"] else ""
            for m in d["lines"][1:]: d[m.split(" ")[0]] = m
            res.append(d)
    return res
def shown(b, name):
    m = re.search(r"shown=\[(.*)\]", b.get(name, "")); return m.group(1) if m else None
def prop(l, key):
    for part in l[6:].split("; "):
        if part.startswith(key + "="): return part[len(key) + 1:]
    return None
def mark(n): return "echo M%d" % n
def draw(tool, a, b):
    return ["tool " + tool, "mouse move %d %d" % a, "mouse down %d %d" % a, "mouse move %d %d" % b, "mouse up %d %d" % b, "mouse rdown %d %d" % b, "mouse rdown %d %d" % b]
S = ["newdoc A4", "registerframe x all"]
# tool panels
for t in ["wire", "bus", "rect", "circle", "cloud", "text", "label", "note", "power", "measure", "polygon"]:
    S += ["tool " + t, mark(1), "frameinfo tool"]
S += ["tool wire", "typenumber tool line.width 3 done", "frameact tool cbWireType choose 2", mark(2), "frameinfo tool", "tool rect", "frameact tool sbFill pick 1 000000", mark(3), "frameinfo tool", "tool select"]
# objects: power(0) cloud(1) measure(2) note(3) rect(4) wire(5)
S += draw("power", (60, 60), (60, 60)) + draw("cloud", (100, 30), (150, 70)) + draw("measure", (30, 150), (90, 150)) + draw("note", (30, 100), (80, 120))
S += draw("rect", (110, 110), (150, 140)) + ["tool wire", "mouse move 20 20", "mouse down 20 20", "mouse move 60 20", "mouse down 60 20", "mouse rdown 60 20", "mouse rdown 60 20"]
S += ["objects", "sharedinfo OpenDlg SaveDlg PrintDlg dlgPrinterSetup dlgPageSetup ReplaceDlg ilSpeedBtn ilTinyIcons ilListBoxImages DlgColor ilNewDocument dlgExportSave dlgLibAdd dlgLibNew"]
# power: the direction button goes round Up, Right, Down, Left, Up; text; type
S += ["selidx 0", mark(10), "frameinfo sel", "props"]
for i in range(5): S += ["frameact sel sbOrientation click", "props", "frameinfo sel"]
S += ["frameact sel edText text GND", "frameact sel cbTextDirection choose 4", mark(11), "props", "frameinfo sel"]
# cloud
S += ["selidx 1", mark(12), "frameinfo sel", "typenumber sel cloud.bump 7.5 done", mark(13), "props", "frameinfo sel", "frameact sel cbWireType choose 3", "frameact sel cbWireColor color 00FF00", mark(14), "props"]
# measure
S += ["selidx 2", mark(15), "frameinfo sel", "frameact sel cbFontSize text 22", "frameact sel sbBold click", "frameact sel sbItalic click", "frameact sel cbGrads click", "frameact sel cbUnits choose 1", "typenumber sel line.width 4 done", mark(16), "props", "frameinfo sel",
      "frameact sel sbBold click", "frameact sel cbFontSize text abc", mark(17), "props", "frameinfo sel"]
# note
S += ["selidx 3", mark(18), "frameinfo sel", "frameact sel bbFill pick 0", mark(19), "props", "frameinfo sel", "frameact sel bbFill pick 3", "frameact sel cbWireType choose 2", "frameact sel edText text Hello",
      "frameact sel cbTextDirection choose 1", mark(20), "props", "frameinfo sel"]
# rect, wire, and a mixed selection
S += ["selidx 4", mark(21), "frameinfo sel", "props", "frameact sel sbFill pick 0", mark(27), "frameinfo sel", "props", "frameact sel sbFill pick 5", mark(22), "props", "frameinfo sel",
      "selidx 5", mark(23), "frameinfo sel", "frameact sel cbWireType choose 4", "typenumber sel line.width 6 done", mark(24), "props", "frameinfo sel",
      "selidx 4 5", mark(25), "frameinfo sel", "props", "selidx 0 4", mark(26), "frameinfo sel"]
S += ["tool polygon", "mouse down 200 40", "mouse down 240 40", "mouse down 240 80", "mouse dbl 200 80", "tool select", "objects"]
S += ["selidx 6", mark(30), "frameinfo sel", "props", "frameact sel bbFill pick 2", "frameact sel cbWireType choose 3", "typenumber sel line.width 5 done", "frameact sel cbWireColor color 0000FF", "frameact sel cbClosed click", mark(31), "props", "frameinfo sel"]
out = run(S)
def marked(n):
    return [i for i, l in enumerate(out) if l == "M%d" % n]
check("the script ran", any(l.startswith("OBJ end") for l in out), out[:6])
# ---- the dialogs and image lists live in the shared controls form only
sh = [l for l in out if l.startswith("SHARED ")]
check("14 shared components were reported", len(sh) == 14, len(sh))
check("every dialog and image list is owned by the shared controls form and not by the main form", all(" shared=1 main=0 " in l for l in sh), [l for l in sh if " shared=1 main=0 " not in l])
# ---- tool panels
tools = {}
for l_i, l in enumerate(out):
    pass
tb = blocks(out, "M1")
check("eleven tool panels were shown", len(tb) == 11, len(tb))
exp = ["TfmPropRibbonWire", "TfmBus", "TfmRectCircle", "TfmRectCircle", "TfmCloudRect", "TfmPropText", "TfmPropWireLabel", "TfmPropNote", "TfmPower", "TfmMeasure", "TfmPolygon"]
if len(tb) == 11:
    for i, n in enumerate(exp):
        check("tool %d uses %s" % (i, n), tb[i]["head"].startswith(n + " ") and "problems=0" in tb[i]["head"], tb[i]["head"])
    check("the wire tool: color, width and style are linked", all(k in tb[0] for k in ("cbWireColor", "seWireSize", "cbWireType")) and "line.color" in tb[0]["cbWireColor"] and "line.width" in tb[0]["seWireSize"] and "line.style" in tb[0]["cbWireType"], tb[0]["lines"])
    check("the rectangle tool has one Fill button (mode 3) for the fill, in place of the Fill box, type list and color button", "fill.type" in tb[2]["sbFill"] and "mode=3" in tb[2]["sbFill"] and not any(k in tb[2] for k in ("cbFill", "cbFillType", "cbFillColor")), tb[2]["lines"])
    check("the cloud tool has the scallop box (cloud.bump)", "cloud.bump" in tb[4].get("fseScallop", ""), tb[4]["lines"])
    check("the label tool has the label type, the text tool has not", "label.style" in tb[6].get("cbTextDirection1", "") and "cbTextDirection1" not in tb[5], (tb[5]["lines"], tb[6]["lines"]))
    check("the font controls are linked in the text frames (name, size, bold, italic)", all(k in tb[5] for k in ("cbFont", "cbFontSize", "sbBold", "sbItalic")) and "font.face" in tb[5]["cbFont"] and "font.height" in tb[5]["cbFontSize"], tb[5]["lines"])
    check("the measure tool: units and graduations", "measure.unit" in tb[9].get("cbUnits", "") and "measure.ticks" in tb[9].get("cbGrads", ""), tb[9]["lines"])
    check("the polygon tool: color, width (with its caption), style and the Fill button are linked", all(k in tb[10] for k in ("cbWireColor", "seWidth", "cbWireType", "bbFill")) and "line.color" in tb[10]["cbWireColor"] and "line.width" in tb[10]["seWidth"] and "line.style" in tb[10]["cbWireType"] and "fill.type" in tb[10]["bbFill"] and "mode=3" in tb[10]["bbFill"], tb[10]["lines"])
    check("the power tool: symbol type", "power.type" in tb[8].get("cbTextDirection", ""), tb[8]["lines"])
b2 = blocks(out, "M2")
if b2:
    check("a width typed in the wire tool's number box shows in it", shown(b2[0], "seWireSize") == "3", b2[0]["lines"])
    check("a style chosen in the wire tool's list is the tool's (Dot)", "item=2" in (shown(b2[0], "cbWireType") or ""), b2[0]["lines"])
b3 = blocks(out, "M3")
if b3:
    check("the rectangle tool: Solid picked on the Fill button shows on it", "Fill Solid" in (shown(b3[0], "sbFill") or ""), b3[0]["lines"])
# ---- power
def props_between(a, b):
    return [l[6:] if False else l for l in out[a:b] if l.startswith("PROPS ")]
mk = {n: marked(n)[0] for n in range(10, 28) if marked(n)}
if 10 in mk and 11 in mk:
    seg = out[mk[10]:mk[11]]
    pr = [l for l in seg if l.startswith("PROPS ")]
    fi = [l for l in seg if l.startswith("FRAMEINFO sbOrientation")]
    dirs = [prop(l, "dir") for l in pr]
    check("the power direction button goes Up, Right, Down, Left, Up, Right", dirs == ["Up", "Right", "Down", "Left", "Up", "Right"], dirs)
    imgs = [re.search(r"image=(\d+)", l).group(1) for l in fi]
    check("its picture follows the direction (images 5 to 8)", imgs == ["5", "6", "7", "8", "5", "6"], imgs)
    pb = blocks(out, "M11")
    p11 = [l for l in out[mk[11]:mk[11] + 40] if l.startswith("PROPS ")][0]
    check("the power text and type are changed from the frame (GND, type 4: Earth)", prop(p11, "text") == "GND" and prop(p11, "power.type") == "Earth", p11)
# ---- cloud
if 12 in mk:
    cb = blocks(out, "M12")[0]
    check("the cloud's frame shows its scallop (5)", shown(cb, "fseScallop") == "5", cb["lines"])
    p = [l for l in out[mk[13]:mk[13] + 12] if l.startswith("PROPS ")][0]
    check("a scallop typed in the frame is applied (7.5)", prop(p, "cloud.bump") == "7.5", p)
    p = [l for l in out[mk[14]:mk[14] + 6] if l.startswith("PROPS ")][0]
    check("the cloud's line style (Dash-dot, 4th) and color come from the frame", prop(p, "line.style") == "Dash-dot" and prop(p, "line.color") == "00FF00", p)
# ---- measure
if 15 in mk:
    mb = blocks(out, "M15")[0]
    check("the measure frame shows font size 10 (13 pixels) and graduations on", shown(mb, "cbFontSize").endswith("text=10") and shown(mb, "cbGrads") == "1" and re.fullmatch(r"down=0 image=\d+", shown(mb, "sbBold")) is not None, mb["lines"])
    p = [l for l in out[mk[16]:mk[16] + 40] if l.startswith("PROPS ")][0]
    check("size typed (22), bold, italic, graduations off, units Inches, width 4", prop(p, "font.height") == "22" and prop(p, "font.bold") == "1" and prop(p, "font.italic") == "1" and prop(p, "measure.ticks") == "0" and prop(p, "measure.unit") == "Inches" and prop(p, "line.width") == "4", p)
    mb2 = blocks(out, "M16")[0]
    check("the frame shows what was applied", re.fullmatch(r"down=1 image=\d+", shown(mb2, "sbBold")) is not None and shown(mb2, "cbGrads") == "0" and shown(mb2, "cbUnits").startswith("item=1") and shown(mb2, "seLineWidth") == "4", mb2["lines"])
    p = [l for l in out[mk[17]:mk[17] + 40] if l.startswith("PROPS ")][0]
    check("bold clicked again is off; text that is not a number is not applied (still 22)", prop(p, "font.bold") == "0" and prop(p, "font.height") == "22", p)
    mb3 = blocks(out, "M17")[0]
    check("and the size box goes back to 22", (shown(mb3, "cbFontSize") or "").endswith("text=22"), mb3["lines"])
# ---- note
if 18 in mk:
    nb = blocks(out, "M18")[0]
    check("the note frame shows its fill on the Fill button, Solid", "Fill Solid" in (shown(nb, "bbFill") or "") and not any(k in nb["lines"][0] for k in ("cbFill ", "cbFillType")), nb["lines"])
    p = [l for l in out[mk[19]:mk[19] + 40] if l.startswith("PROPS ")][0]
    nb2 = blocks(out, "M19")[0]
    check("picking None on the Fill button makes the note's fill None", prop(p, "fill.type") == "None" and "Fill None" in (shown(nb2, "bbFill") or ""), (p, nb2["lines"]))
    p = [l for l in out[mk[20]:mk[20] + 40] if l.startswith("PROPS ")][0]
    check("picking a type (Vertical), choosing a style (3rd), a text, a direction (Down)", prop(p, "fill.type") == "Vertical" and prop(p, "line.style") == "Dot" and prop(p, "text") == "Hello" and prop(p, "dir") == "Down", p)
# ---- rect
if 21 in mk:
    rb = blocks(out, "M21")[0]
    check("the rectangle drawn after the tool's fill was set to Solid is filled (Solid): the Fill button shows it", "Fill Solid" in (shown(rb, "sbFill") or ""), rb["lines"])
    rb0 = blocks(out, "M27")[0]
    p = [l for l in out[mk[27]:mk[27] + 40] if l.startswith("PROPS ")][0]
    check("picking None on the Fill button makes the rectangle's fill None", prop(p, "fill.type") == "None" and "Fill None" in (shown(rb0, "sbFill") or ""), (p, rb0["lines"]))
    p = [l for l in out[mk[22]:mk[22] + 40] if l.startswith("PROPS ")][0]
    rb2 = blocks(out, "M22")[0]
    check("then the 6th type picked (Forward diagonal)", prop(p, "fill.type") == "Forward diagonal" and "Fill Forward diagonal" in (shown(rb2, "sbFill") or ""), (p, rb2["lines"]))
# ---- wire
if 23 in mk:
    p = [l for l in out[mk[24]:mk[24] + 40] if l.startswith("PROPS ")][0]
    check("a wire: style chosen (5th: Dash-dot-dot) and width typed (6)", prop(p, "line.style") == "Dash-dot-dot" and prop(p, "line.width") == "6", p)
    wb = blocks(out, "M23")[0]
    check("a selected wire uses the wire frame", wb["head"].startswith("TfmPropRibbonWire "), wb["head"])
# ---- mixed
if 25 in mk:
    mx = blocks(out, "M25")[0]
    check("a rectangle and a wire together: the frame of neither, the built-in editors", mx["head"] == "none", mx["lines"])
    p = [l for l in out[mk[25]:mk[25] + 20] if l.startswith("PROPS ")][0]
    check("the built-in editors still list the shared properties", prop(p, "line.width") is not None, p)
    mx = blocks(out, "M26")[0]
    check("a power symbol and a rectangle: no frame either", mx["head"] == "none", mx["lines"])
if fails:
    print("%d of %d checks failed" % (len(fails), checks)); sys.exit(1)
# ---- polygon
if 30 in mk or marked(30):
    b30 = blocks(out, "M30")
    check("a selected polygon shows the polygon frame with its line width", bool(b30) and b30[0]["head"].startswith("TfmPolygon ") and "problems=0" in b30[0]["head"] and shown(b30[0], "seWidth") == "1" and "poly.closed" in b30[0].get("cbClosed", ""), b30[0]["lines"] if b30 else None)
    c0 = prop([l for l in out[marked(30)[0]:marked(30)[0] + 8] if l.startswith("PROPS ")][0], "poly.closed")
    pl = [l for l in out[marked(31)[0]:marked(31)[0] + 6] if l.startswith("PROPS ")]
    check("what is chosen in the polygon frame changes the polygon (fill Horizontal, style Dash-dot, width 5, blue)", bool(pl) and prop(pl[0], "line.width") == "5" and prop(pl[0], "line.color") == "0000FF" and prop(pl[0], "line.style") == "Dash-dot" and prop(pl[0], "fill.type") == "Horizontal" and prop(pl[0], "poly.closed") != c0, pl)
print("Real frame checks passed (%d)" % checks)
