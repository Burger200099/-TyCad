{ Port of the netlist writers of NetList.cpp other than the Protel one (which is in UNetList): TinyCAD's own format, PADS-PCB (with
  and without values), Eagle script, gEDA PCB and XML, and CNetList::WriteNetListFile, which picks one by number.

  Every writer builds the netlist first (MakeNet), then writes two parts: the components, one for each distinct reference in drawing
  order (the XML writer lists every placed symbol, even when a reference repeats), and the nets in ascending net number, each named by
  the first label found on it or by N followed by six digits of the net number. A net with no pin that has a reference is left out
  (Protel and PADS need two pins; the others one).

  The formats by number, as TinyCAD's export dialog lists them: 0 TinyCAD, 1 PADS-PCB, 2 PADS-PCB-WITH-VALUE, 3 Eagle SCR, 4 Protel,
  5 gEDA PCB, 6 XML.

  Text is returned with line feeds (the platform's line ends are put in by the caller) and as UTF-8. Not ported: hierarchical symbols
  (they are not loaded), SPICE and VHDL (the other writers of NetList.cpp), and the ERC check TinyCAD runs before writing.

  Original: Copyright 1994-2019 Matt Pyne, LGPL 2.1+. This port keeps that licence. }
unit UNetWriters;

{$mode objfpc}{$H+}
{$modeswitch nestedprocvars}

interface

uses
  Classes, SysUtils, UDrawTypes, UDrawingObjects, USymbols, UDesign, UNetList;

const
  NETFMT_TINYCAD = 0;
  NETFMT_PADS = 1;
  NETFMT_PADS_VALUE = 2;
  NETFMT_EAGLE = 3;
  NETFMT_PROTEL = 4;
  NETFMT_PCB = 5;
  NETFMT_XML = 6;
  NETFMT_COUNT = 7;

{ CNetList::WriteNetListFile: the whole file for one of the formats (any other number gives the TinyCAD format) }
function NetListText(AFormat: Integer; Design: TDesignFile; const DesignFileName: String;
  const EOL: String = LineEnding): String;
function NetListFormatName(AFormat: Integer): String;
{ the extension the export dialog offers for a format }
function NetListExtension(AFormat: Integer): String;
{ the file name TinyCAD proposes: the design's with .net, or output.net when it has no extension }
function NetListDefaultFileName(const DesignFile: String): String;
{ the name after the format was changed: a .net before the last extension is dropped too, then the new extension is put on }
function NetListChangeExtension(const FileName: String; AFormat: Integer): String;
{ CDrawPin::GetElectricalTypeName: the name of an electrical type, empty for a number out of range }
function ElectricalTypeName(Elec: Integer): String;
{ rapidxml's escaping of text and attribute values }
function XmlEscape(const S: String): String;

implementation


uses UStrings;

const
  ELECTRICAL: array[0..6] of String = ('Input', 'Output', 'Tristate', 'Open Collector', 'Passive', 'Input/Output', 'Not Connected');

{ ===========================================================================
  ElectricalTypeName  (function)
  Parameters:
    Elec: Integer - whole number
  Returns:
    String
  Notes:
    CDrawPin::GetElectricalTypeName.
  =========================================================================== }
function ElectricalTypeName(Elec: Integer): String;
begin
  if (Elec < 0) or (Elec > High(ELECTRICAL)) then
    Result := ''
  else
    Result := ELECTRICAL[Elec];
end;

{ ===========================================================================
  NetListFormatName  (function)
  Parameters:
    AFormat: Integer - whole number
  Returns:
    String
  Notes:
    The seven names of the dialog's list; any other number gives the first.
  =========================================================================== }
function NetListFormatName(AFormat: Integer): String;
const
  NAMES: array[0..6] of String = ('TinyCAD', 'PADS-PCB', 'PADS-PCB-WITH-VALUE', 'Eagle SCR', 'Protel', 'gEDA PCB', 'XML');
begin
  if (AFormat < 0) or (AFormat > 6) then
    Result := NAMES[0]
  else
    Result := NAMES[AFormat];
end;

{ ===========================================================================
  NetListExtension  (function)
  Parameters:
    AFormat: Integer - whole number
  Returns:
    String
  Notes:
    GetExtension of the export dialog.
  =========================================================================== }
function NetListExtension(AFormat: Integer): String;
begin
  case AFormat of
    NETFMT_EAGLE: Result := '.scr';
    NETFMT_XML: Result := '.net.xml';
  else
    Result := '.net';
  end;
end;

{ ===========================================================================
  NetListDefaultFileName  (function)
  Parameters:
    const DesignFile: String - text
  Returns:
    String
  Notes:
    OnSpecialNet: the design's name with its last extension replaced by .net; a name without a
    dot gives "output.net".
  =========================================================================== }
function NetListDefaultFileName(const DesignFile: String): String;
var
  P: Integer;
begin
  P := Length(DesignFile);
  while (P > 0) and (DesignFile[P] <> '.') do Dec(P);
  if P = 0 then
    Result := 'output.net'
  else
    Result := Copy(DesignFile, 1, P - 1) + '.net';
end;

{ ===========================================================================
  NetListChangeExtension  (function)
  Parameters:
    const FileName: String - path of the file
    AFormat: Integer - whole number
  Returns:
    String
  Notes:
    OnSelchangeFileType of the PCB export dialog: only a name with a dot is changed; a ".net"
    just before the last dot (as in "x.net.xml", at least four characters in) goes as well, then
    the format's extension is put on.
  =========================================================================== }
function NetListChangeExtension(const FileName: String; AFormat: Integer): String;
var
  P: Integer;
begin
  P := Length(FileName);
  while (P > 0) and (FileName[P] <> '.') do Dec(P);
  if P = 0 then
    Exit(FileName);
  if (P - 1 >= 4) and (Copy(FileName, P - 4, 4) = '.net') then
    Dec(P, 4);
  Result := Copy(FileName, 1, P - 1) + NetListExtension(AFormat);
end;

{ ===========================================================================
  XmlEscape  (function)
  Parameters:
    const S: String - text
  Returns:
    String
  Notes:
    rapidxml's copy_and_expand_chars, which expands all five characters.
  =========================================================================== }
function XmlEscape(const S: String): String;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    case S[i] of
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '&': Result := Result + '&amp;';
      '"': Result := Result + '&quot;';
      '''': Result := Result + '&apos;';
    else
      Result := Result + S[i];
    end;
end;

{ ===========================================================================
  XmlAttr  (function)
  Parameters:
    const Name: String - the name
    const Value: String - the value
  Returns:
    String
  Notes:
    A value that holds a double quote is written in single quotes (and then the double quote
    itself is not escaped).
  =========================================================================== }
function XmlAttr(const Name, Value: String): String;
begin
  if Pos('"', Value) > 0 then
    Result := ' ' + Name + '=''' + StringReplace(XmlEscape(Value), '&quot;', '"', [rfReplaceAll]) + ''''
  else
    Result := ' ' + Name + '="' + XmlEscape(Value) + '"';
end;

{ ===========================================================================
  FieldNamed  (function)
  Parameters:
    M: TDrawMethod
    const AName: String - the name
    const ADefault: String - text
  Returns:
    String
  Notes:
    The loops of the writers: fields from the third on are searched and the last match wins.
  =========================================================================== }
function FieldNamed(M: TDrawMethod; const AName, ADefault: String): String;
var
  k: Integer;
begin
  Result := ADefault;
  for k := 2 to M.GetFieldCount - 1 do
    if SameText(M.GetFieldName(k), AName) then
      Result := M.GetField(k);
end;

{ ===========================================================================
  FirstLabel  (function)
  Parameters:
    const V: TNodeVector
    out ALabel: String - text (out: set by the call)
  Returns:
    Boolean
  Notes:
    The first non-empty label of the nodes, which names the net.
  =========================================================================== }
function FirstLabel(const V: TNodeVector; out ALabel: String): Boolean;
var
  k: Integer;
begin
  ALabel := '';
  for k := 0 to High(V) do
    if NodeLabel(V[k]) <> '' then
    begin
      ALabel := NodeLabel(V[k]);
      Exit(True);
    end;
  Result := False;
end;

{ ===========================================================================
  NetName  (function)
  Parameters:
    const V: TNodeVector
  Returns:
    String
  Notes:
    How the writers name a net.
  =========================================================================== }
function NetName(const V: TNodeVector): String;
var
  L: String;
begin
  if FirstLabel(V, L) then
    Result := L
  else
    Result := Format('N%.6d', [V[0].NetList]);
end;

{ ===========================================================================
  EachPart  (procedure)
  Parameters:
    Design: TDesignFile - the design
    OnlyFirst: Boolean - skip a reference already met
    Add: TPartProc - called for each part
  Notes:
    Visits the placed symbols of every sheet in drawing order; with OnlyFirst, a symbol whose reference has already been visited is
    skipped (the writers' "referenced" set).
  =========================================================================== }
type
  TPartProc = procedure(M: TDrawMethod; const Ref: String) is nested;

{ ===========================================================================
  EachPart  (procedure)
  Parameters:
    Design: TDesignFile - the design
    OnlyFirst: Boolean - skip a reference already met
    Add: TPartProc - called with each symbol and its reference
  Notes:
    Visits the placed symbols of every sheet in drawing order and calls Add for each; with
    OnlyFirst, a symbol whose reference has already been visited is skipped (the writers' set of
    references already written).
  =========================================================================== }
procedure EachPart(Design: TDesignFile; OnlyFirst: Boolean; Add: TPartProc);
var
  Seen: TStringList;
  i, j: Integer;
  Obj: TDrawingObject;
  Ref: String;
begin
  Seen := TStringList.Create;
  try
    Seen.CaseSensitive := True;
    Seen.Sorted := True;
    Seen.Duplicates := dupIgnore;
    for i := 0 to Design.SheetCount - 1 do
      for j := 0 to Design.Sheets[i].Drawing.Count - 1 do
      begin
        Obj := Design.Sheets[i].Drawing[j];
        if Obj.GetType <> xMethodEx3 then
          Continue;
        Ref := (Obj as TDrawMethod).GetRef;
        if OnlyFirst then
        begin
          if Seen.IndexOf(Ref) >= 0 then
            Continue;
          Seen.Add(Ref);
        end;
        Add(Obj as TDrawMethod, Ref);
      end;
  finally
    Seen.Free;
  end;
end;

{ ===========================================================================
  WritePads  (function)
  Parameters:
    Design: TDesignFile - the design
    N: TNetList
    WithValue: Boolean - flag
  Returns:
    String
  Notes:
    WriteNetListFilePADS: "*PADS-PCB*", a *PART* list (the reference padded with spaces to at
    least eight characters, then the package, or value@package when asked for and the part has a
    value), and a *NET* list with a "*SIGNAL*  name" line and the pins as ref.pin separated by
    spaces, wrapped after 127 characters, for each net of two or more pins; then "*END*".
  =========================================================================== }
function WritePads(Design: TDesignFile; N: TNetList; WithValue: Boolean): String;
var
  Out: String;
  procedure Part(M: TDrawMethod; const Ref: String);
  var
    Pkg, Value, R: String;
  begin
    Pkg := FieldNamed(M, 'package', rsThisPartHasNoPackage);
    Value := FieldNamed(M, 'value', '');
    R := Ref;
    repeat
      R := R + ' ';
    until CharLength(R) >= 8;
    if WithValue and (Value <> '') then
      Out := Out + R + Value + '@' + Pkg + #10
    else
      Out := Out + R + Pkg + #10;
  end;
var
  Ni, k, Len, Count: Integer;
  V: TNodeVector;
  TheLine, Add_: String;
  First: Boolean;
begin
  Out := '*PADS-PCB*'#10'*PART*'#10;
  EachPart(Design, True, @Part);
  Out := Out + #10'*NET*'#10;
  for Ni := 0 to N.Nets.Count - 1 do
  begin
    V := N.Nets.Vec(Ni);
    if Length(V) = 0 then
      Continue;
    TheLine := '';
    First := True;
    Len := 0;
    Count := 0;
    for k := 0 to High(V) do
      if V[k].Reference <> '' then
      begin
        Add_ := V[k].Reference + '.' + V[k].Pin;
        Len := Len + CharLength(Add_);
        if Len > 127 then
        begin
          TheLine := TheLine + #10;
          Len := CharLength(Add_);
          First := True;
        end;
        if First then
          First := False
        else
        begin
          TheLine := TheLine + ' ';
          Inc(Len);
        end;
        TheLine := TheLine + Add_;
        Inc(Count);
      end;
    if Count > 1 then
      Out := Out + '*SIGNAL*  ' + NetName(V) + #10 + TheLine + #10;
  end;
  Result := Out + '*END*'#10;
end;

{ ===========================================================================
  WriteTinyCADFormat  (function)
  Parameters:
    Design: TDesignFile - the design
    N: TNetList
    const DesignFileName: String - text
  Returns:
    String
  Notes:
    WriteNetListFileTinyCAD: comment lines starting with a semicolon, then "COMPONENT 'ref' =
    name" with a tab-indented "OPTION 'field' = value" for each other field, then "NET  'name' =
    (ref,pin),(ref,pin)..." for each net that has at least one pin (a pin whose entry equals the
    label of its node is left out).
  =========================================================================== }
function WriteTinyCADFormat(Design: TDesignFile; N: TNetList; const DesignFileName: String): String;
var
  Out: String;
  procedure Part(M: TDrawMethod; const Ref: String);
  var
    k: Integer;
  begin
    Out := Out + 'COMPONENT ''' + Ref + ''' = ' + M.GetField(FIELD_NAME) + #10;
    for k := 2 to M.GetFieldCount - 1 do
      Out := Out + #9'OPTION ''' + M.GetFieldName(k) + ''' = ' + M.GetField(k) + #10;
  end;
var
  Ni, k: Integer;
  V: TNodeVector;
  TheLine, Add_: String;
  First, PrintLine: Boolean;
begin
  Out := '; ====+  Net List for ' + DesignFileName + '  +===='#10#10'; ======+ The component list'#10#10;
  EachPart(Design, True, @Part);
  Out := Out + #10#10'; ======+ The net list'#10#10;
  for Ni := 0 to N.Nets.Count - 1 do
  begin
    V := N.Nets.Vec(Ni);
    if Length(V) = 0 then
      Continue;
    TheLine := '';
    First := True;
    PrintLine := False;
    for k := 0 to High(V) do
      if V[k].Reference <> '' then
      begin
        Add_ := '(' + V[k].Reference + ',' + V[k].Pin + ')';
        if NodeLabel(V[k]) <> Add_ then
        begin
          if First then
            First := False
          else
            TheLine := TheLine + ',';
          TheLine := TheLine + Add_;
          PrintLine := True;
        end;
      end;
    if PrintLine then
      Out := Out + 'NET  ''' + NetName(V) + ''' =  ' + TheLine + #10;
  end;
  Result := Out;
end;

{ ===========================================================================
  WriteEagle  (function)
  Parameters:
    Design: TDesignFile - the design
    N: TNetList
  Returns:
    String
  Notes:
    WriteNetListFileEagle: an "ADD 'ref' package R0 (0.x 0.y);" line for each part, laid out in
    rows of nine (x from 1 to 9, then y one more), two empty lines, then "SIGNAL name", a line "
    ref pin" for each pin and "   ;" for every net that has a pin.
  =========================================================================== }
function WriteEagle(Design: TDesignFile; N: TNetList): String;
var
  Out: String;
  XPos, YPos: Integer;
  procedure Part(M: TDrawMethod; const Ref: String);
  begin
    Out := Out + 'ADD ''' + Ref + ''' ' + FieldNamed(M, 'package', 'This part has no ''Package'' attribute') + ' R0 (0.' + IntToStr(XPos) + ' 0.' + IntToStr(YPos) + ');'#10;
    Inc(XPos);
    if XPos = 10 then
    begin
      Inc(YPos);
      XPos := 1;
    end;
  end;
var
  Ni, k: Integer;
  V: TNodeVector;
  TheLine: String;
  PrintLine: Boolean;
begin
  Out := '';
  XPos := 1;
  YPos := 1;
  EachPart(Design, True, @Part);
  Out := Out + #10#10;
  for Ni := 0 to N.Nets.Count - 1 do
  begin
    V := N.Nets.Vec(Ni);
    if Length(V) = 0 then
      Continue;
    TheLine := '';
    PrintLine := False;
    for k := 0 to High(V) do
      if V[k].Reference <> '' then
      begin
        TheLine := TheLine + '   ' + V[k].Reference + ' ' + V[k].Pin + #10;
        PrintLine := True;
      end;
    if PrintLine then
      Out := Out + 'SIGNAL ' + NetName(V) + #10 + TheLine + '   ;'#10;
  end;
  Result := Out;
end;

{ ===========================================================================
  WriteGedaPcb  (function)
  Parameters:
    N: TNetList
  Returns:
    String
  Notes:
    WriteNetListFilePCB (the "gEDA PCB" format): one entry for each net that has a pin, " name
    ref-pin ref-pin ..." with a space after every pin and a line continuation (" \" and a new
    line) after every 41st pin. The count carries on from one net to the next unless a net was
    written (which starts it again from zero).
  =========================================================================== }
function WriteGedaPcb(N: TNetList): String;
var
  Out, TheLine, Add_: String;
  Ni, k, Count: Integer;
  V: TNodeVector;
  PrintLine: Boolean;
begin
  Out := '';
  Count := 0;
  for Ni := 0 to N.Nets.Count - 1 do
  begin
    V := N.Nets.Vec(Ni);
    if Length(V) = 0 then
      Continue;
    TheLine := '';
    PrintLine := False;
    for k := 0 to High(V) do
      if V[k].Reference <> '' then
      begin
        Add_ := V[k].Reference + '-' + V[k].Pin + ' ';
        if NodeLabel(V[k]) <> Add_ then
        begin
          TheLine := TheLine + Add_;
          Inc(Count);
          if Count > 40 then
          begin
            Count := 0;
            TheLine := TheLine + ' \'#10' ';
          end;
          PrintLine := True;
        end;
      end;
    if PrintLine then
    begin
      Count := 0;
      Out := Out + ' ' + NetName(V) + ' ' + '  ' + TheLine + #10;
    end;
  end;
  Result := Out;
end;

{ ===========================================================================
  WriteXmlFormat  (function)
  Parameters:
    Design: TDesignFile - the design
    N: TNetList
    const DesignFileName: String - text
  Returns:
    String
  Notes:
    rawWriteNetListFileXML, printed as rapidxml prints it (a tab for each level, an empty
    element as <x/>, an element with only text on one line): a <netlist design="..."> holding
    <parts> - a <part ref="" name=""> for every placed symbol (a repeated reference is listed
    again) with an <attribute name="">value</attribute> for each other field - and <nets>: a
    <net name="" number=""> for every net, holding a <pin part="" name="" number="" type=""/>
    for each pin node (part only when it has a reference, type only for the seven known
    electrical types). A net is named by the first preferred label found on it.
  =========================================================================== }
function WriteXmlFormat(Design: TDesignFile; N: TNetList; const DesignFileName: String): String;
var
  Parts, Nets: String;
  procedure Part(M: TDrawMethod; const Ref: String);
  var
    k: Integer;
    Fv: String;
    Body: String;
  begin
    Body := '';
    for k := 2 to M.GetFieldCount - 1 do
    begin
      Fv := M.GetField(k);
      if Fv = '' then
        Body := Body + #9#9#9'<attribute' + XmlAttr('name', M.GetFieldName(k)) + '/>'#10
      else
        Body := Body + #9#9#9'<attribute' + XmlAttr('name', M.GetFieldName(k)) + '>' + XmlEscape(Fv) + '</attribute>'#10;
    end;
    if Body = '' then
      Parts := Parts + #9#9'<part' + XmlAttr('ref', Ref) + XmlAttr('name', M.GetField(FIELD_NAME)) + '/>'#10
    else
      Parts := Parts + #9#9'<part' + XmlAttr('ref', Ref) + XmlAttr('name', M.GetField(FIELD_NAME)) + '>'#10 + Body + #9#9'</part>'#10;
  end;
var
  Ni, k: Integer;
  V: TNodeVector;
  Body, NetNm, Pin: String;
  P: TDrawPin;
  TypeName: String;
begin
  Parts := '';
  Nets := '';
  EachPart(Design, False, @Part);
  for Ni := 0 to N.Nets.Count - 1 do
  begin
    V := N.Nets.Vec(Ni);
    if Length(V) = 0 then
      Continue;
    Body := '';
    NetNm := '';
    for k := 0 to High(V) do
    begin
      if (NetNm = '') and (NodePreferredLabel(V[k]) <> '') then
        NetNm := NodePreferredLabel(V[k]);
      if (V[k].Parent <> nil) and (V[k].Parent.GetType = xPinEx) then
      begin
        P := V[k].Parent as TDrawPin;
        Pin := #9#9#9'<pin';
        if V[k].Reference <> '' then
          Pin := Pin + XmlAttr('part', V[k].Reference);
        Pin := Pin + XmlAttr('name', P.GetPinName) + XmlAttr('number', P.GetNumber);
        TypeName := ElectricalTypeName(P.Elec);
        if TypeName <> '' then
          Pin := Pin + XmlAttr('type', TypeName);
        Body := Body + Pin + '/>'#10;
      end;
    end;
    Pin := #9#9'<net';
    if NetNm <> '' then
      Pin := Pin + XmlAttr('name', NetNm);
    Pin := Pin + XmlAttr('number', IntToStr(V[0].NetList));
    if Body = '' then
      Nets := Nets + Pin + '/>'#10
    else
      Nets := Nets + Pin + '>'#10 + Body + #9#9'</net>'#10;
  end;
  Result := '<?xml version="1.0" encoding="utf-8"?>'#10'<netlist' + XmlAttr('design', DesignFileName) + '>'#10;
  if Parts = '' then
    Result := Result + #9'<parts/>'#10
  else
    Result := Result + #9'<parts>'#10 + Parts + #9'</parts>'#10;
  if Nets = '' then
    Result := Result + #9'<nets/>'#10
  else
    Result := Result + #9'<nets>'#10 + Nets + #9'</nets>'#10;
  Result := Result + '</netlist>'#10;
end;

{ ===========================================================================
  NetListText  (function)
  Parameters:
    AFormat: Integer - whole number
    Design: TDesignFile - the design
    const DesignFileName: String - text
    const EOL: String - text
  Returns:
    String
  Notes:
    CNetList::WriteNetListFile. Builds the netlist (which also stores the net numbers in the
    design as hints) and writes the format.
  =========================================================================== }
function NetListText(AFormat: Integer; Design: TDesignFile; const DesignFileName: String; const EOL: String): String;
var
  N: TNetList;
  S: TStringStream;
  T: String;
begin
  N := TNetList.Create;
  try
    case AFormat of
      NETFMT_PADS: begin
        N.MakeNet(Design);
        T := WritePads(Design, N, False);
      end;
      NETFMT_PADS_VALUE: begin
        N.MakeNet(Design);
        T := WritePads(Design, N, True);
      end;
      NETFMT_EAGLE: begin
        N.MakeNet(Design);
        T := WriteEagle(Design, N);
      end;
      NETFMT_PROTEL:
        begin
          S := TStringStream.Create('');
          try
            N.WriteProtel(Design, S);
            T := StringReplace(S.DataString, #13#10, #10, [rfReplaceAll]);
          finally
            S.Free;
          end;
        end;
      NETFMT_PCB: begin
        N.MakeNet(Design);
        T := WriteGedaPcb(N);
      end;
      NETFMT_XML: begin
        N.MakeNet(Design);
        T := WriteXmlFormat(Design, N, DesignFileName);
      end;
    else
      N.MakeNet(Design);
      T := WriteTinyCADFormat(Design, N, DesignFileName);
    end;
  finally
    N.Free;
  end;
  if EOL = #10 then
    Result := T
  else
    Result := StringReplace(T, #10, EOL, [rfReplaceAll]);
end;

end.
