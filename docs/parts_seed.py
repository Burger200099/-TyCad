#!/usr/bin/env python3
"""Builds a TCParts database: the schema (parts_schema.sql), the class tree, the kinds of child objects, their fields, and sample parts.
Usage: parts_seed.py <out.TCParts>.  The class tree below is the design; the tests (tests/run_partsschema.py) read it back through the inheritance views."""
import os, sqlite3, struct, sys, uuid, zlib
HERE = os.path.dirname(os.path.abspath(__file__))
def png(size, rgb, border=(0, 0, 0)):
    """a small square PNG (no imaging library needed): a filled square with a 1 pixel border; the sample glyphs"""
    rows = b"".join(b"\x00" + b"".join(bytes(border if x in (0, size - 1) or y in (0, size - 1) else rgb) for x in range(size)) for y in range(size))
    def chunk(t, b): return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
def symbol_xml(a, b, pins):
    """a symbol as TinyCAD XML (what a .TCLib keeps): a rectangle from a to b and pins [(x, y, direction 0 up / 1 down / 2 left / 3 right, number, name)]"""
    head = ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<TinyCAD>\n\t<FONT id='1'>\n\t\t<HEIGHT>-10</HEIGHT>\n\t\t<WIDTH>0</WIDTH>\n\t\t<WEIGHT>400</WEIGHT>\n\t\t<ITALIC>0</ITALIC>\n\t\t<UNDERLINE>0</UNDERLINE>\n"
            "\t\t<STRIKEOUT>0</STRIKEOUT>\n\t\t<CHARSET>0</CHARSET>\n\t\t<FACENAME>Arial</FACENAME>\n\t</FONT>\n\t<STYLE id='2'>\n\t\t<STYLE>0</STYLE>\n\t\t<COLOR>000000</COLOR>\n\t\t<THICKNESS>1</THICKNESS>\n\t</STYLE>\n"
            "\t<FILL id='0'>\n\t\t<INDEX>-1</INDEX>\n\t\t<COLOR>000000</COLOR>\n\t</FILL>\n")
    body = "\t<RECTANGLE a='%.5f,%.5f' b='%.5f,%.5f' style='2' fill='0'></RECTANGLE>\n" % (a + b)
    for x, y, d, num, name in pins:
        body += "\t<PIN pos='%.5f,%.5f' which='0' elec='4' direction='%d' part='0' number='%s' show='3' length='15' number_pos='0' centre_name='0'>%s</PIN>\n" % (x, y, d, num, name)
    return (head + body + "</TinyCAD>\n").encode("utf-8")
def build(path):
    if os.path.exists(path): os.remove(path)
    c = sqlite3.connect(path); c.execute("PRAGMA foreign_keys=ON"); c.executescript(open(os.path.join(HERE, "parts_schema.sql")).read())
    c.execute("insert into LibraryInfo(LibraryUID,Name,Created) values (?,?,datetime('now'))", (str(uuid.uuid4()), 'Sample parts'))
    c.execute("insert into FormatInfo values ('TyCAD-Parts',1,0,datetime('now'),'parts_seed.py')")
    cid, kid = {}, {}
    def cls(name, parent=None, abstract=0, desc=""):
        cid[name] = c.execute("insert into PartClass(Name,ParentID,Abstract,Description) values (?,?,?,?)", (name, cid.get(parent), abstract, desc)).lastrowid
    def fld(cname, name, typ, unit=None, enum=None, req=0, desc=""):
        c.execute("insert into FieldDef(ClassID,Name,Type,Unit,EnumValues,Required,Description) values (?,?,?,?,?,?,?)", (cid[cname], name, typ, unit, enum, req, desc))
    def kind(name, parent=None, abstract=0, desc=""):
        kid[name] = c.execute("insert into ObjectKind(Name,ParentID,Abstract,Description) values (?,?,?,?)", (name, kid.get(parent), abstract, desc)).lastrowid
    def kfld(kname, name, typ, unit=None, enum=None, req=0, desc=""):
        c.execute("insert into KindFieldDef(KindID,Name,Type,Unit,EnumValues,Required,Description) values (?,?,?,?,?,?,?)", (kid[kname], name, typ, unit, enum, req, desc))
    def allow(cname, kname, lo=0, hi=None):
        c.execute("insert into ClassAllowsKind values (?,?,?,?)", (cid[cname], kid[kname], lo, hi))
    # ---- kinds of child objects: everything electrical a part has
    kind("PartObject", abstract=1, desc="anything inside a part")
    kfld("PartObject", "Label", "text", desc="as printed on the part")
    kfld("PartObject", "Colour", "text"); kfld("PartObject", "Note", "text")
    kind("ActiveObject", "PartObject", 1, "consumes energy or makes heat")
    kfld("ActiveObject", "PowerW", "real", "W"); kfld("ActiveObject", "HeatW", "real", "W", desc="dissipated as heat")
    kfld("ActiveObject", "DutyCycle", "real", "%")
    kind("Coil", "ActiveObject", desc="relay / contactor / solenoid coil")
    kfld("Coil", "CoilType", "enum", enum="AC,DC,AC/DC", req=1); kfld("Coil", "PickupPct", "real", "%"); kfld("Coil", "DropoutPct", "real", "%")
    kfld("Coil", "InrushA", "real", "A"); kfld("Coil", "HoldingA", "real", "A")
    kind("PowerInput", "ActiveObject", desc="supply connection of a powered part")
    kfld("PowerInput", "SupplyType", "enum", enum="AC,DC,AC/DC,PoE,Loop", req=1); kfld("PowerInput", "Isolated", "bool")
    kind("Load", "ActiveObject", desc="an output that feeds a load (heater, lamp, motor winding)")
    kfld("Load", "LoadType", "enum", enum="resistive,inductive,capacitive,motor,lamp,general")
    kind("PassiveObject", "PartObject", 1, "carries or switches energy, consumes none of its own")
    kfld("PassiveObject", "WireMinMm2", "real", "mm2"); kfld("PassiveObject", "WireMaxMm2", "real", "mm2"); kfld("PassiveObject", "TorqueNm", "real", "Nm")
    kind("Terminal", "PassiveObject", desc="a connection point")
    kfld("Terminal", "Function", "enum", enum="power_in,power_out,signal,coil,contact,common,shield,PE,N,network", req=1)
    kfld("Terminal", "Connection", "enum", enum="screw,spring,push-in,ring,fast-on,plug,solder,M12,RJ45")
    kind("Pole", "PassiveObject", desc="a switching path; holds its contacts and terminals")
    kfld("Pole", "PoleNo", "int")
    kind("Contact", "PassiveObject", desc="a switching element")
    kfld("Contact", "Form", "enum", enum="NO,NC,CO,make-before-break,latching", req=1); kfld("Contact", "Material", "text"); kfld("Contact", "Mechanical life", "int", "ops")
    kind("Channel", "PassiveObject", desc="one input or output of an I/O part; holds its terminals")
    kfld("Channel", "Signal", "enum", enum="digital,analog_voltage,analog_current,relay,pulse,temperature,serial", req=1)
    kfld("Channel", "Direction", "enum", enum="input,output,bidirectional", req=1); kfld("Channel", "Addressing", "text")
    kfld("Channel", "IsolationGroup", "text"); kfld("Channel", "SinkSource", "enum", enum="sink,source,both")
    kind("SensorIO", "Channel", desc="sensor connection: supply, signal and return of a field device")
    kfld("SensorIO", "SensorSupplyV", "real", "V"); kfld("SensorIO", "SensorSupplyMaxmA", "real", "mA")
    kind("NetworkPort", "PassiveObject", desc="a communications port")
    kfld("NetworkPort", "Protocol", "text", req=1); kfld("NetworkPort", "SpeedMbps", "real", "Mbit/s"); kfld("NetworkPort", "ConnectorType", "text")
    kind("InternalLink", "PassiveObject", desc="a bridge or bus inside the part (see Link)")
    # ---- classes of parts
    cls("Part", abstract=1, desc="every part")
    for n, t, u in (("WidthMm", "real", "mm"), ("HeightMm", "real", "mm"), ("DepthMm", "real", "mm"), ("WeightG", "real", "g"), ("IPRating", "text", None),
                    ("TempMinC", "real", "C"), ("TempMaxC", "real", "C"), ("AltitudeMaxM", "real", "m"), ("Origin", "text", None), ("RoHS", "bool", None)):
        fld("Part", n, t, u)
    fld("Part", "Mounting", "enum", enum="DIN,panel,backplane,plug-in,inline,field,PCB")
    cls("ActivePart", "Part", 1, "consumes energy / generates heat")
    fld("ActivePart", "PowerW", "real", "W"); fld("ActivePart", "HeatW", "real", "W"); fld("ActivePart", "InrushA", "real", "A")
    cls("ControlModule", "ActivePart", 1, "controller or module of a controller system")
    fld("ControlModule", "BackplaneCurrentmA", "real", "mA", desc="drawn from the base / backplane supply"); fld("ControlModule", "Slots", "int")
    fld("ControlModule", "Firmware", "text")
    cls("IOModule", "ControlModule", 1, "input / output module")
    fld("IOModule", "ChannelCount", "int", req=1); fld("IOModule", "Hotswap", "bool")
    cls("AnalogInputModule", "IOModule", 0, "analog input module")
    fld("AnalogInputModule", "ResolutionBits", "int", "bit"); fld("AnalogInputModule", "ConversionMs", "real", "ms"); fld("AnalogInputModule", "Accuracy", "text")
    cls("DigitalIOModule", "IOModule"); fld("DigitalIOModule", "FilterMs", "real", "ms")
    cls("PowerSupply", "ActivePart"); fld("PowerSupply", "EfficiencyPct", "real", "%"); fld("PowerSupply", "OutputW", "real", "W")
    cls("PassivePart", "Part", 1, "switches or carries energy and makes none of its own heat beyond contact loss")
    fld("PassivePart", "Poles", "int")
    cls("SwitchingDevice", "PassivePart", 1, "contacts driven by a coil, a lever or a sensor")
    fld("SwitchingDevice", "Actuation", "enum", enum="coil,manual,limit,pressure,thermal,sensor"); fld("SwitchingDevice", "ElectricalLife", "int", "ops")
    cls("Contactor", "SwitchingDevice"); fld("Contactor", "Category", "text", desc="AC-1, AC-3 ...")
    cls("Relay", "SwitchingDevice")
    cls("Breaker", "SwitchingDevice"); fld("Breaker", "Curve", "text"); fld("Breaker", "BreakingKA", "real", "kA")
    cls("TerminalBlock", "PassivePart"); fld("TerminalBlock", "Pitch", "real", "mm")
    cls("Sensor", "ActivePart", desc="field device with a supply and a signal"); fld("Sensor", "SensingPrinciple", "text"); fld("Sensor", "Range", "text")
    # ---- which child kinds a class allows (inherited by every descendant)
    allow("Part", "Terminal"); allow("Part", "InternalLink"); allow("Part", "NetworkPort", 0, None)
    allow("ActivePart", "PowerInput"); allow("ActivePart", "ActiveObject")
    allow("IOModule", "Channel", 1, None)
    allow("SwitchingDevice", "Pole", 1, None); allow("SwitchingDevice", "Contact"); allow("SwitchingDevice", "Coil", 0, None)
    allow("Sensor", "SensorIO")
    # ---- what can be rated, and how a product is judged against a part's requirement
    for q in [("voltage", "V", "min", "operating or insulation voltage"), ("current", "A", "min", "load or switching current"),
              ("power", "W", "min", "power handled"), ("motor_power", "kW", "min", "motor power (HP x 0.7457)"),
              ("coil_voltage", "V", "match", "coil or supply voltage (must be the same)"), ("coil_power", "W", "max", "coil power (lower is better)"),
              ("input_current", "mA", "min", "analog current range"), ("ambient_max", "degC", "min", "highest ambient temperature")]:
        c.execute("insert into RatingQuantity values (?,?,?,?)", q)
    # ---- samples: a generic PART (what the design needs) and the PRODUCTS (catalog items) that can be chosen for it
    def part(cname, name, desc, **vals):
        pid = c.execute("insert into Part(UID,ClassID,Name,Description) values (?,?,?,?)", (str(uuid.uuid4()), cid[cname], name, desc)).lastrowid
        for k, v in vals.items():
            f = c.execute("select FieldID,Type from ClassFields where ClassID=? and Name=?", (cid[cname], k)).fetchone()
            c.execute("insert into PartValue values (?,?,?,?)", (pid, f[0], v if f[1] in ("int", "real", "bool") else None, None if f[1] in ("int", "real", "bool") else v))
        return pid
    def product(cname, mfr, mpn, desc, suits=(), **ratings):
        """ratings: quantity -> (value, unit, applies_to, condition)"""
        prid = c.execute("insert into Product(UID,ClassID,Manufacturer,MPN,Description) values (?,?,?,?,?)", (str(uuid.uuid4()), cid[cname], mfr, mpn, desc)).lastrowid
        for qn, (v, applies, cond) in ratings.items():
            c.execute("insert into Rating(ProductID,AppliesTo,Quantity,Max,Unit,Condition) select ?,?,Name,?,Unit,? from RatingQuantity where Name=?", (prid, applies, v, cond, qn))
        for p in suits: c.execute("insert into PartProduct(PartID,ProductID) values (?,?)", (p, prid))
        return prid
    def need(pid, qn, v, oname=None, cond=None):
        c.execute("insert into Rating(PartID,ObjectID,Quantity,Max,Unit,Condition) select ?,(select ObjectID from PartObject where PartID=? and Name=?),Name,?,Unit,? from RatingQuantity where Name=?", (pid, pid, oname, v, cond, qn))
    def obj(pid, kname, name, parent=None, des=None, **vals):
        oid = c.execute("insert into PartObject(PartID,ParentObjectID,KindID,Name,Designator) values (?,?,?,?,?)", (pid, parent, kid[kname], name, des)).lastrowid
        for k, v in vals.items():
            f = c.execute("select FieldID,Type from KindFields where KindID=? and Name=?", (kid[kname], k)).fetchone()
            c.execute("insert into ObjectValue values (?,?,?,?)", (oid, f[0], v if f[1] in ("int", "real", "bool") else None, None if f[1] in ("int", "real", "bool") else v))
        return oid
    p = part("AnalogInputModule", "Analog input module, 4 channels, current", "4-channel 4-20 mA analog input, 16 bit", ChannelCount=4, ResolutionBits=16,
             BackplaneCurrentmA=95, Mounting="backplane", WidthMm=25.4)
    obj(p, "PowerInput", "Field supply", des="24V", SupplyType="DC")
    for n in range(1, 5):
        ch = obj(p, "Channel", "CH%d" % n, des=str(n), Signal="analog_current", Direction="input", IsolationGroup="1")
        obj(p, "Terminal", "CH%d+" % n, ch, des="%d+" % n, Function="signal"); obj(p, "Terminal", "CH%d-" % n, ch, des="%d-" % n, Function="common")
        need(p, "input_current", 20, "CH%d" % n, "range")
    product("AnalogInputModule", "AutomationDirect", "P2-04AD-1", "Productivity2000 4-channel analog input, current", suits=[p], input_current=(20, "kind:Channel", "range"))
    k = part("Contactor", "Contactor 3P 25 A AC-3, 24 V DC coil", "3-pole contactor", Poles=3, Category="AC-3", Mounting="DIN")
    co = obj(k, "Coil", "A1/A2", CoilType="DC", PickupPct=80, HoldingA=0.12)
    for n in range(1, 4):
        pl = obj(k, "Pole", "Pole %d" % n, PoleNo=n)
        ct = obj(k, "Contact", "%dL%d-%dT%d" % (n, n, n, n), pl, Form="NO")
        obj(k, "Terminal", "%dL%d" % (n, n), pl, Function="power_in"); obj(k, "Terminal", "%dT%d" % (n, n), pl, Function="power_out")
        c.execute("insert into Link(PartID,FromObject,ToObject,Relation) values (?,?,?,'driven_by')", (k, ct, co))
        need(k, "current", 25, "%dL%d-%dT%d" % (n, n, n, n), "AC-3 400 V")
    need(k, "coil_voltage", 24, "A1/A2"); need(k, "coil_power", 3, "A1/A2")
    need(k, "motor_power", 11, None, "AC-3 400 V")
    product("Contactor", "Example Co", "CTR-25-24DC", "25 A contactor, 24 V DC coil", suits=[k], current=(25, "kind:Contact", "AC-3 400 V"), coil_voltage=(24, "A1/A2", None),
            coil_power=(2.4, "A1/A2", None), motor_power=(11, None, "AC-3 400 V"))
    product("Contactor", "Example Co", "CTR-32-24DC", "32 A contactor, 24 V DC coil (bigger than needed)", current=(32, "kind:Contact", "AC-3 400 V"), coil_voltage=(24, "A1/A2", None),
            coil_power=(2.4, "A1/A2", None), motor_power=(15, None, "AC-3 400 V"))
    product("Contactor", "Other Co", "OC-18-24DC", "18 A contactor, 24 V DC coil (too small)", current=(18, "kind:Contact", "AC-3 400 V"), coil_voltage=(24, "A1/A2", None),
            coil_power=(2.4, "A1/A2", None), motor_power=(7.5, None, "AC-3 400 V"))
    product("Contactor", "Other Co", "OC-25-110AC", "25 A contactor, 110 V coil (wrong coil)", current=(25, "kind:Contact", "AC-3 400 V"), coil_voltage=(110, "A1/A2", None),
            coil_power=(2.4, "A1/A2", None), motor_power=(11, None, "AC-3 400 V"))
    def symbol(nm, xml, prefix):
        c.execute("update Part set RefPrefix=? where Name=?", (prefix, nm))
        sid = c.execute("insert into Symbol(PartID,Standard,Purpose,Name,Drawing,OriginX,OriginY) select PartID,'IEC','schematic',Name,?,60,40 from Part where Name=?", (xml, nm)).lastrowid
        c.execute("update Part set BaseDefault=? where Name=?", (sid, nm))
    symbol("Contactor 3P 25 A AC-3, 24 V DC coil", symbol_xml((60, 40), (110, 80), [(70, 40, 0, "1/L1", "1/L1"), (85, 40, 0, "3/L2", "3/L2"), (100, 40, 0, "5/L3", "5/L3"),
           (70, 80, 1, "2/T1", "2/T1"), (85, 80, 1, "4/T2", "4/T2"), (100, 80, 1, "6/T3", "6/T3")]), "K")
    symbol("Analog input module, 4 channels, current", symbol_xml((60, 40), (120, 90), [(60, 55 + 10 * i, 2, "%d+" % (i + 1), "CH%d" % (i + 1)) for i in range(4)]), "U")
    for nm, rgb in (("Analog input module, 4 channels, current", (60, 140, 220)), ("Contactor 3P 25 A AC-3, 24 V DC coil", (230, 150, 40))):
        for size in (24, 48):      # (two sizes: the program takes the nearest one to what it needs)
            c.execute("insert into PartGlyph select PartID, ?, ? from Part where Name=?", (size, png(size, rgb), nm))
    c.commit(); return c
if __name__ == "__main__":
    build(sys.argv[1]).close()
