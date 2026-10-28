{ Port of the SPICE and VHDL netlist writers of NetList.cpp (CNetList::WriteSpiceFile, expand_spice, eval_spice_macro, get_attr,
  get_pin_by_number and WriteVHDLFile with its Bus_Properties helpers).

  SPICE: every placed symbol that has a pin on some net is written as one line, in the order of its reference, by expanding the symbol's
  "$$SPICE" field: $(name) a field, %(pin) the net name at a pin (given by number, or else by name), @(pin) the net number, ?(test,then,else) a
  conditional, \ the next character literally. Fields "$$SPICE_PROLOG" and "$$SPICE_EPILOG" (with the priorities "$$SPICE_PROLOG_PRIORITY"
  and "$$SPICE_EPILOG_PRIORITY") add lines before and after, once each however many symbols carry them. Problems found on the way (a pin
  without a name or number, repeated pin names or numbers, a symbol without a model, a macro that cannot be resolved) are counted and
  listed in an error text that goes to a ".txt" file beside the netlist.

  VHDL: an entity whose ports are the symbols named INPUT and OUTPUT (by their reference), a component for every other symbol name (its pins
  of electrical type input, then output, in drawing order), a signal for every other net and one port map for every reference. Pins and
  labels written like name(7:0) or name(3) are buses.

  Both return text with line feeds; the caller puts the platform's line ends in and writes the files.

  Differences from TinyCAD, all small: in the C++ snapshot the SPICE model line prints an empty string where the expanded model belongs
  (the call to expand_spice is missing); this port prints the expansion. A macro that ends in an escaped "(" and so leaves an empty value
  reads past the end of a string in the C++ and gives an empty value here. VHDL text containing a percent sign is written as it is (the C++
  hands names to printf as the format). Sheets with no drawing are skipped (the C++ reads past the end of them). The hierarchy is not loaded,
  so every node comes from the root design and the reference path of a symbol is its reference.

  Original: Copyright 1994-2019 Matt Pyne, LGPL 2.1+. This port keeps that licence. }
unit USpiceVhdl;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs, UDPoint, UDrawTypes, UDrawingObjects, UDesign, UNetList;

type
  { Bus_Properties::bus_type }
  TBusKind = (bkInternal, bkInput, bkOutput, bkDontKnow);

  { Bus_Properties }
  TBusProps = record
    Name: String;
    Start, EndN: Integer;
    IsBus: Boolean;   // a bus with start = end is still a bus (a bus member)
    Kind: TBusKind;
  end;

{ _ttoi: leading white space, an optional sign, then digits; anything else stops it }
function CAtoi(const S: String): Integer;
{ Bus_Properties::Bus_Properties }
function ParseBus(const Ref: String; AKind: TBusKind): TBusProps;
{ print_signal_dec }
function SignalDeclaration(const B: TBusProps): String;
{ _ftprintf_signal_ref }
function SignalReference(const Ref: String): String;
{ getFileNameFromPath: the name between the last folder mark and the last dot, at most 254 characters }
function VhdlEntityName(const Path: String): String;
{ OnSpecialVHDL: the design's name with its last extension replaced by .vhd; "output.vhd" for a name with no dot }
function VhdlDefaultFileName(const DesignFile: String): String;
{ OnSpecialCreatespicefile: the same with .net; "output.net" for a name with no dot }
function SpiceDefaultFileName(const DesignFile: String): String;
{ CNetList::createErrorFile: the file the error text goes to (the netlist's name up to its last dot, then .txt; ".txt" if it has no dot) }
function SpiceErrorFileName(const OutputFile: String): String;
{ the date and time of the first line, as CTime::Format("%x at %X %z"): mm/dd/yy at hh:nn:ss +hhmm }
function SpiceStamp(T: TDateTime): String;

{ CNetList::WriteVHDLFile: the whole file for a design written to OutputPath (which gives the entity its name) }
function VhdlText(Design: TDesignFile; const OutputPath, EOL: String): String;
{ CNetList::WriteSpiceFile: the whole file; ErrorText is the content of the error file and ErrorCount the number of errors in it }
function SpiceText(Design: TDesignFile; const DesignFileName, Stamp, EOL: String; out ErrorText: String; out ErrorCount: Integer): String;

implementation


uses UStrings;

type
  { a std::map with String keys, ordered like CString's operator< (by character code, not by locale) }
  generic TOrdMap<T> = class
  private
    FKeys: array of String;
    FVals: array of T;
    FCount: Integer;
    function Search(const K: String; out Index: Integer): Boolean;
  public
    function Has(const K: String): Boolean;
    { operator[]: an absent key is added with the default value }
    function Get(const K: String): T;
    procedure SetValue(const K: String; const V: T);
    function Count: Integer;
    function KeyAt(I: Integer): String;
    function ValueAt(I: Integer): T;
  end;

{ ===========================================================================
  TOrdMap.Search  (function)
  Parameters:
    const K: String - the key
    out Index: Integer - its position, or the position to insert it at
  Returns:
    Boolean
  Notes:
    Binary search for a key among the sorted keys (compared by character code, as CString's
    operator< does). Index is where the key is, or where it would be inserted.
  =========================================================================== }
function TOrdMap.Search(const K: String; out Index: Integer): Boolean;
var
  Lo, Hi, Mid, C: Integer;
begin
  Lo := 0;
  Hi := FCount - 1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    C := CompareStr(FKeys[Mid], K);
    if C = 0 then begin
      Index := Mid;
      Exit(True);
    end;
    if C < 0 then
      Lo := Mid + 1
    else
      Hi := Mid - 1;
  end;
  Index := Lo;
  Result := False;
end;

{ ===========================================================================
  TOrdMap.Has  (function)
  Parameters:
    const K: String - the key
  Returns:
    Boolean
  Notes:
    True if the key is in the map.
  =========================================================================== }
function TOrdMap.Has(const K: String): Boolean;
var
  I: Integer;
begin
  Result := Search(K, I);
end;

{ ===========================================================================
  TOrdMap.Get  (function)
  Parameters:
    const K: String - the key
  Returns:
    T
  Notes:
    std::map's operator[]: the value stored for the key; a key that is not there is added with
    the default value (an empty string, 0 or nil) and that default is returned.
  =========================================================================== }
function TOrdMap.Get(const K: String): T;
var
  I, J: Integer;
begin
  if not Search(K, I) then
  begin
    if FCount = Length(FKeys) then
    begin
      SetLength(FKeys, FCount * 2 + 8);
      SetLength(FVals, FCount * 2 + 8);
    end;
    for J := FCount downto I + 1 do
    begin
      FKeys[J] := FKeys[J - 1];
      FVals[J] := FVals[J - 1];
    end;
    FKeys[I] := K;
    FVals[I] := Default(T);
    Inc(FCount);
  end;
  Result := FVals[I];
end;

{ ===========================================================================
  TOrdMap.SetValue  (procedure)
  Parameters:
    const K: String - the key
    const V: T - the value
  Notes:
    Stores a value for a key, adding the key if it is not there.
  =========================================================================== }
procedure TOrdMap.SetValue(const K: String; const V: T);
var
  I: Integer;
begin
  Get(K);
  Search(K, I);
  FVals[I] := V;
end;

{ ===========================================================================
  TOrdMap.Count  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    The number of keys.
  =========================================================================== }
function TOrdMap.Count: Integer;
begin
  Result := FCount;
end;

{ ===========================================================================
  TOrdMap.KeyAt  (function)
  Parameters:
    I: Integer - the position, from 0
  Returns:
    String
  Notes:
    The key at a position in key order.
  =========================================================================== }
function TOrdMap.KeyAt(I: Integer): String;
begin
  Result := FKeys[I];
end;

{ ===========================================================================
  TOrdMap.ValueAt  (function)
  Parameters:
    I: Integer - the position, from 0
  Returns:
    T
  Notes:
    The value at a position in key order.
  =========================================================================== }
function TOrdMap.ValueAt(I: Integer): T;
begin
  Result := FVals[I];
end;

type
  TStrMap = specialize TOrdMap<String>;
  TIntMap = specialize TOrdMap<Integer>;
  TBusMap = specialize TOrdMap<TBusProps>;
  TObjMap = specialize TOrdMap<TObject>;

{ ===========================================================================
  CAtoi  (function)
  Parameters:
    const S: String - text
  Returns:
    Integer
  Notes:
    _ttoi: skips white space, takes a sign and the digits after it; text after the digits is
    ignored.
  =========================================================================== }
function CAtoi(const S: String): Integer;
var
  I: Integer;
  Neg: Boolean;
  V: Int64;
begin
  I := 1;
  while (I <= Length(S)) and (S[I] in [' ', #9, #10, #11, #12, #13]) do Inc(I);
  Neg := False;
  if (I <= Length(S)) and (S[I] in ['+', '-']) then
  begin
    Neg := S[I] = '-';
    Inc(I);
  end;
  V := 0;
  while (I <= Length(S)) and (S[I] in ['0'..'9']) do
  begin
    V := V * 10 + Ord(S[I]) - 48;
    if V > 2147483648 then
      V := 2147483648;
    Inc(I);
  end;
  if Neg then
    V := -V;
  if V > 2147483647 then
    V := 2147483647;
  if V < -2147483648 then
    V := -2147483648;
  Result := Integer(V);
end;

{ ===========================================================================
  ParseBus  (function)
  Parameters:
    const Ref: String - text
    AKind: TBusKind
  Returns:
    TBusProps
  Notes:
    Bus_Properties::Bus_Properties. "name(a:b)" is a bus from a down to b, "name(a)" a bus
    member; a name with no "(" is not a bus. A bus whose end is above its start gets the start
    as its end. Missing numbers are 0.
  =========================================================================== }
function ParseBus(const Ref: String; AKind: TBusKind): TBusProps;
type
  TPos = (inName, inStart, inEnd, afterEnd);
var
  Position: TPos;
  I, StartOfStart, StartOfEnd: Integer;
  C: Char;
begin
  Result.Name := '';
  Result.Start := 0;
  Result.EndN := 0;
  Result.IsBus := False;
  Result.Kind := AKind;
  Position := inName;
  StartOfStart := 0;
  StartOfEnd := 0;
  for I := 0 to Length(Ref) - 1 do
  begin
    C := Ref[I + 1];
    case Position of
      inName:
        if C = '(' then
        begin
          Result.Name := Copy(Ref, 1, I);
          Result.IsBus := True;
          StartOfStart := I + 1;
          Position := inStart;
        end;
      inStart:
        if C = ':' then
        begin
          Result.Start := CAtoi(Copy(Ref, StartOfStart + 1, I - StartOfStart));
          StartOfEnd := I + 1;
          Position := inEnd;
        end
        else if C = ')' then
        begin
          Result.Start := CAtoi(Copy(Ref, StartOfStart + 1, I - StartOfStart));
          Result.EndN := Result.Start;
          Position := afterEnd;
        end;
      inEnd:
        if C = ')' then
        begin
          Result.EndN := CAtoi(Copy(Ref, StartOfEnd + 1, I - StartOfEnd));
          Position := afterEnd;
        end;
    end;
  end;
  if Result.EndN > Result.Start then
    Result.EndN := Result.Start;
  if not Result.IsBus then
    Result.Name := Ref;
end;

{ ===========================================================================
  SignalDeclaration  (function)
  Parameters:
    const B: TBusProps - a point, in design units
  Returns:
    String
  Notes:
    print_signal_dec.
  =========================================================================== }
function SignalDeclaration(const B: TBusProps): String;
var
  IO: String;
begin
  case B.Kind of
    bkInput: IO := 'in';
    bkOutput: IO := 'out';
  else
    IO := '';
  end;
  if B.IsBus then
    Result := B.Name + ': ' + IO + ' std_logic_vector(' + IntToStr(B.Start) + ' downto ' + IntToStr(B.EndN) + ')'
  else
    Result := B.Name + ': ' + IO + ' std_logic';
end;

{ ===========================================================================
  SignalReference  (function)
  Parameters:
    const Ref: String - text
  Returns:
    String
  Notes:
    _ftprintf_signal_ref.
  =========================================================================== }
function SignalReference(const Ref: String): String;
var
  B: TBusProps;
begin
  B := ParseBus(Ref, bkDontKnow);
  if B.IsBus then
  begin
    if B.Start = B.EndN then
      Result := B.Name + '(' + IntToStr(B.Start) + ')'
    else
      Result := B.Name + '(' + IntToStr(B.Start) + ' downto ' + IntToStr(B.EndN) + ')';
  end
  else
    Result := B.Name;
end;

{ ===========================================================================
  VhdlEntityName  (function)
  Parameters:
    const Path: String - text
  Returns:
    String
  Notes:
    getFileNameFromPath. The C++ looks for a backslash only; the folder marks / and \ both count
    here. The dot searched for is the last one after the folder.
  =========================================================================== }
function VhdlEntityName(const Path: String): String;
var
  I, S, E, N, Chars: Integer;
begin
  S := 0;
  for I := Length(Path) downto 1 do
    if Path[I] in ['/', '\'] then begin
      S := I;
      Break;
    end;
  Result := Copy(Path, S + 1, MaxInt);
  E := 0;
  for I := Length(Result) downto 1 do
    if Result[I] = '.' then begin
      E := I;
      Break;
    end;
  if E > 0 then
    Result := Copy(Result, 1, E - 1);
  { at most 254 characters (not cutting inside a UTF-8 character) }
  Chars := 0;
  N := 0;
  for I := 1 to Length(Result) do
  begin
    if (Ord(Result[I]) and $C0) <> $80 then
    begin
      Inc(Chars);
      if Chars > 254 then
        Break;
    end;
    N := I;
  end;
  Result := Copy(Result, 1, N);
end;

{ ===========================================================================
  DefaultWithExtension  (function)
  Parameters:
    const DesignFile: String - the design's file name, empty if it has none
    const Ext: String - the extension, with its dot
  Returns:
    String
  Notes:
    The design's file name with its last extension replaced by Ext; a name with no dot gives
    output followed by Ext.
  =========================================================================== }
function DefaultWithExtension(const DesignFile, Ext: String): String;
var
  P: Integer;
begin
  P := Length(DesignFile);
  while (P > 0) and (DesignFile[P] <> '.') do Dec(P);
  if P = 0 then
    Result := 'output' + Ext
  else
    Result := Copy(DesignFile, 1, P - 1) + Ext;
end;

{ ===========================================================================
  VhdlDefaultFileName  (function)
  Parameters:
    const DesignFile: String - the design's file name
  Returns:
    String
  Notes:
    The name the Create VHDL file dialog proposes: the design's name with .vhd, or output.vhd.
  =========================================================================== }
function VhdlDefaultFileName(const DesignFile: String): String;
begin
  Result := DefaultWithExtension(DesignFile, '.vhd');
end;

{ ===========================================================================
  SpiceDefaultFileName  (function)
  Parameters:
    const DesignFile: String - the design's file name
  Returns:
    String
  Notes:
    The name the Create Spice Net List dialog proposes: the design's name with .net, or
    output.net.
  =========================================================================== }
function SpiceDefaultFileName(const DesignFile: String): String;
begin
  Result := DefaultWithExtension(DesignFile, '.net');
end;

{ ===========================================================================
  SpiceErrorFileName  (function)
  Parameters:
    const OutputFile: String - text
  Returns:
    String
  Notes:
    createErrorFile: the name up to its last dot (wherever the dot is, even in a folder name)
    and ".txt"; a name that begins with its only dot keeps the whole name; a name with no dot
    gives ".txt" (CString::Left of -1 is empty).
  =========================================================================== }
function SpiceErrorFileName(const OutputFile: String): String;
var
  P: Integer;
begin
  P := Length(OutputFile);
  while (P > 0) and (OutputFile[P] <> '.') do Dec(P);
  if P = 0 then
    Result := '.txt'
  else if P = 1 then
    Result := OutputFile + '.txt'
  else
    Result := Copy(OutputFile, 1, P - 1) + '.txt';
end;

{ ===========================================================================
  SpiceStamp  (function)
  Parameters:
    T: TDateTime
  Returns:
    String
  Notes:
    The date, time and zone of the first line of a SPICE file.
  =========================================================================== }
function SpiceStamp(T: TDateTime): String;
var
  Off: Integer;
  Sign: Char;
begin
  Off := -GetLocalTimeOffset;   // minutes east of UTC
  if Off < 0 then begin
    Sign := '-';
    Off := -Off;
  end
  else
    Sign := '+';
  Result := FormatDateTime('mm"/"dd"/"yy" at "hh":"nn":"ss', T) + ' ' + Sign + Format('%.2d%.2d', [Off div 60, Off mod 60]);
end;

{ ---- the placed symbols of a design, in drawing order ---- }

{ ===========================================================================
  CollectMethods  (procedure)
  Parameters:
    Design: TDesignFile - the design
    List: TList - receives the symbols
  Notes:
    Puts every placed symbol of the design, sheet by sheet in drawing order, in a list (the C++
    walks them with componentsBegin and componentsNext).
  =========================================================================== }
procedure CollectMethods(Design: TDesignFile; List: TList);
var
  I, J: Integer;
  Obj: TDrawingObject;
begin
  for I := 0 to Design.SheetCount - 1 do
    for J := 0 to Design.Sheets[I].Drawing.Count - 1 do
    begin
      Obj := Design.Sheets[I].Drawing[J];
      if Obj.GetType = xMethodEx3 then
        List.Add(Obj);
    end;
end;

{ ===========================================================================
  VhdlText  (function)
  Parameters:
    Design: TDesignFile - the design
    const OutputPath: String - text
    const EOL: String - text
  Returns:
    String
  Notes:
    WriteVHDLFile. Messages the C++ writes into the file where it finds a problem are written
    the same way ("ERROR: Duplicated pin number", "ERROR: Different BUS sizes ..."). A pin that
    is not an input or an output of its component is given position 0 in the port map, as the
    C++ does through std::map's operator[].
  =========================================================================== }
function VhdlText(Design: TDesignFile; const OutputPath, EOL: String): String;
var
  Net: TNetList;
  Comps: TList;
  Garbage: TObjectList;
  Referenced: TStrMap;
  Signals: TBusMap;
  RefName: TStrMap;
  PosMaps, NameMaps: TObjMap;        // component name -> its map of pin number -> position / pin name
  SigLabels: TStrMap;                // net number -> label
  PortMaps: TObjMap;                 // reference -> (position -> label)
  Output, PortStr, Short: String;

  function IntKey(N: Integer): String;
  begin
    Result := Format('%.12d', [N]);
  end;

  function PosMapOf(const Name: String): TIntMap;
  var
    O: TObject;
  begin
    O := PosMaps.Get(Name);
    if O = nil then
    begin
      O := TIntMap.Create;
      Garbage.Add(O);
      PosMaps.SetValue(Name, O);
    end;
    Result := TIntMap(O);
  end;

  function NameMapOf(const Name: String): TStrMap;
  var
    O: TObject;
  begin
    O := NameMaps.Get(Name);
    if O = nil then
    begin
      O := TStrMap.Create;
      Garbage.Add(O);
      NameMaps.SetValue(Name, O);
    end;
    Result := TStrMap(O);
  end;

  procedure AddSignal(const B: TBusProps);
  var
    Old: TBusProps;
  begin
    if not Signals.Has(B.Name) then
      Signals.SetValue(B.Name, B)
    else
    begin
      Old := Signals.Get(B.Name);
      if B.Start > Old.Start then
        Old.Start := B.Start;
      if B.EndN < Old.EndN then
        Old.EndN := B.EndN;
      Signals.SetValue(B.Name, Old);
    end;
  end;

  procedure PinList(M: TDrawMethod; AElec: Integer; var FirstPin: Boolean; var Position: Integer; Kind: TBusKind);
  var
    Tr: TDPoint;
    L: TDrawingList;
    K: Integer;
    Pin: TDrawPin;
    PM: TIntMap;
  begin
    M.ExtractSymbol(Tr, L);
    PM := PosMapOf(M.GetName);
    for K := 0 to L.Count - 1 do
      if L[K].GetType = xPinEx then
      begin
        Pin := L[K] as TDrawPin;
        if Pin.Elec = AElec then
        begin
          if not FirstPin then
            Output := Output + ';'#10#9#9#9
          else
            FirstPin := False;
          if PM.Has(Pin.GetNumber) then
            Output := Output + 'ERROR: Duplicated pin number, ' + M.GetName + ' pin number ' + Pin.GetNumber + #10;
          Output := Output + SignalDeclaration(ParseBus(Pin.GetPinName, Kind));
          PM.SetValue(Pin.GetNumber, Position);
          Inc(Position);
          NameMapOf(M.GetName).SetValue(Pin.GetNumber, Pin.GetPinName);
        end;
      end;
  end;

var
  I, J, K, Ni, BusSize, Position, LabelNo: Integer;
  M: TDrawMethod;
  Nm, TheLabel, PinName, S, Ref: String;
  First, FirstPin, Labeled, InOut: Boolean;
  B, SigB: TBusProps;
  V: TNodeVector;
  Nd: TNetListNode;
  Inner: TStrMap;
begin
  Net := TNetList.Create;
  Comps := TList.Create;
  Garbage := TObjectList.Create(True);
  Referenced := TStrMap.Create;
  Signals := TBusMap.Create;
  RefName := TStrMap.Create;
  PosMaps := TObjMap.Create;
  NameMaps := TObjMap.Create;
  SigLabels := TStrMap.Create;
  PortMaps := TObjMap.Create;
  try
    Net.MakeNet(Design);
    CollectMethods(Design, Comps);
    Short := VhdlEntityName(OutputPath);
    Output := '-- File Created by TinyCad VHDL'#10'library ieee;'#10'use ieee.std_logic_1164.all;'#10#10'entity ' + Short + ' is'#10;

    { the ports: inputs, then outputs }
    PortStr := '';
    First := True;
    for I := 0 to Comps.Count - 1 do
    begin
      M := TDrawMethod(Comps[I]);
      if M.GetName = 'INPUT' then
      begin
        if not First then
          PortStr := PortStr + ';'#10#9#9
        else
          First := False;
        B := ParseBus(M.GetRef, bkInput);
        PortStr := PortStr + SignalDeclaration(B);
        AddSignal(B);
      end;
    end;
    for I := 0 to Comps.Count - 1 do
    begin
      M := TDrawMethod(Comps[I]);
      if M.GetName = 'OUTPUT' then
      begin
        if not First then
          PortStr := PortStr + ';'#10#9#9
        else
          First := False;
        B := ParseBus(M.GetRef, bkOutput);
        PortStr := PortStr + SignalDeclaration(B);
        AddSignal(B);
      end;
    end;
    if PortStr <> '' then
      Output := Output + #9'port('#9 + PortStr + ');'#10;
    Output := Output + 'end ' + Short + ';'#10;

    { the architecture, with a component for every symbol name }
    Output := Output + #10'architecture structural of ' + Short + ' is'#10;
    for I := 0 to Comps.Count - 1 do
    begin
      M := TDrawMethod(Comps[I]);
      Nm := M.GetName;
      RefName.SetValue(M.GetRef, Nm);
      if (not Referenced.Has(Nm)) and (Nm <> 'INPUT') and (Nm <> 'OUTPUT') then
      begin
        Referenced.SetValue(Nm, '');
        Output := Output + #9'component ' + Nm + #10' '#9#9'port('#9;
        Position := 0;
        FirstPin := True;
        PinList(M, 0, FirstPin, Position, bkInput);
        PinList(M, 1, FirstPin, Position, bkOutput);
        Output := Output + ');'#10' '#9'end component;'#10;
      end;
    end;

    { the signals: a label for every net }
    for Ni := 0 to Net.Nets.Count - 1 do
    begin
      V := Net.Nets.Vec(Ni);
      if Length(V) = 0 then
        Continue;
      TheLabel := '';
      Labeled := False;
      InOut := False;
      BusSize := 0;
      LabelNo := V[0].NetList;
      for K := 0 to High(V) do
      begin
        Nd := V[K];
        if (NodeLabel(Nd) <> '') and (not Labeled) then
        begin
          TheLabel := NodeLabel(Nd);
          Labeled := True;
          B := ParseBus(TheLabel, bkDontKnow);
          if BusSize = 0 then
            BusSize := B.Start - B.EndN + 1
          else if BusSize <> B.Start - B.EndN + 1 then
            Output := Output + 'ERROR: Different BUS sizes at label ' + TheLabel + #10;
        end;
        if Nd.Method <> nil then
        begin
          Nm := Nd.Method.GetName;
          if (Nm = 'INPUT') or (Nm = 'OUTPUT') then
          begin
            TheLabel := Nd.Method.GetRef;
            Labeled := True;
            InOut := True;
            B := ParseBus(TheLabel, bkDontKnow);
            if BusSize = 0 then
              BusSize := B.Start - B.EndN + 1
            else if BusSize <> B.Start - B.EndN + 1 then
              Output := Output + 'ERROR: Different BUS sizes at IN/OUT ' + TheLabel + #10;
          end
          else if Nd.Pin <> '' then
          begin
            PinName := NameMapOf(Nm).Get(Nd.Pin);
            B := ParseBus(PinName, bkDontKnow);
            if BusSize = 0 then
              BusSize := B.Start - B.EndN + 1
            else if BusSize <> B.Start - B.EndN + 1 then
              Output := Output + 'ERROR: Different BUS sizes: ' + Nd.Method.GetRef + ' pin name ' + PinName + ', pin number ' + Nd.Pin + #10;
          end;
        end;
      end;
      if not Labeled then
      begin
        if BusSize = 1 then
          TheLabel := Format('N%.2d', [LabelNo])
        else
          TheLabel := Format('N%.2d(%d:0)', [LabelNo, BusSize - 1]);
      end;
      SigLabels.SetValue(IntKey(V[0].NetList), TheLabel);
      if not InOut then
        AddSignal(ParseBus(TheLabel, bkInternal));
    end;
    for I := 0 to Signals.Count - 1 do
    begin
      B := Signals.ValueAt(I);
      if B.Kind = bkInternal then
        Output := Output + #9'signal ' + SignalDeclaration(B) + ';'#10;
    end;
    Output := Output + 'begin'#10;

    { the port maps: for every reference, the label of the net at each position }
    for Ni := 0 to Net.Nets.Count - 1 do
    begin
      V := Net.Nets.Vec(Ni);
      if Length(V) = 0 then
        Continue;
      TheLabel := SigLabels.Get(IntKey(V[0].NetList));
      for K := 0 to High(V) do
      begin
        Nd := V[K];
        if Nd.Method <> nil then
        begin
          Nm := Nd.Method.GetName;
          if (Nm <> 'INPUT') and (Nm <> 'OUTPUT') and (Nd.Reference <> '') then
          begin
            Position := PosMapOf(Nm).Get(Nd.Pin);
            if PortMaps.Get(Nd.Reference) = nil then
            begin
              Inner := TStrMap.Create;
              Garbage.Add(Inner);
              PortMaps.SetValue(Nd.Reference, Inner);
            end;
            TStrMap(PortMaps.Get(Nd.Reference)).SetValue(IntKey(Position), TheLabel);
          end;
        end;
      end;
    end;
    for I := 0 to PortMaps.Count - 1 do
    begin
      Ref := PortMaps.KeyAt(I);
      Inner := TStrMap(PortMaps.ValueAt(I));
      Output := Output + #9 + Ref + ': ' + RefName.Get(Ref) + ' port map (';
      for J := 0 to Inner.Count - 1 do
      begin
        if J > 0 then
          Output := Output + ', ';
        S := Inner.ValueAt(J);
        B := ParseBus(S, bkDontKnow);
        if B.IsBus then
        begin
          SigB := Signals.Get(B.Name);
          if (B.Start = SigB.Start) and (B.EndN = SigB.EndN) then
            S := B.Name;
        end;
        Output := Output + SignalReference(S);
      end;
      Output := Output + ');'#10;
    end;
    Output := Output + 'end structural;'#10;
  finally
    PortMaps.Free;
    SigLabels.Free;
    NameMaps.Free;
    PosMaps.Free;
    RefName.Free;
    Signals.Free;
    Referenced.Free;
    Garbage.Free;
    Comps.Free;
    Net.Free;
  end;
  if EOL = #10 then
    Result := Output
  else
    Result := StringReplace(Output, #10, EOL, [rfReplaceAll]);
end;

{ ===========================================================================
  SPICE
  =========================================================================== }
type
  { CNetListSymbol: the pins of one reference (pin number -> net) and the pin names (name -> number) }
  TSpiceSymbol = class
    RefCopy: String;
    Sheet: Integer;
    Method: TDrawMethod;
    FileIdx: Integer;
    Pins: TIntMap;
    PinNames: TStrMap;
    constructor Create(AFileIdx, ASheet: Integer; AMethod: TDrawMethod);
    destructor Destroy; override;
  end;

  TSpiceMaker = class
  private
    function NetKey(N: Integer): String;
    function GetPinByNumber(Sym: TSpiceSymbol; const Pin: String; out Nodes: Integer; out R: String; out NetNo: Integer): Boolean;
    function GetPinByNumberOrName(Sym: TSpiceSymbol; const Pin: String; out Nodes: Integer; out R: String; out NetNo: Integer): Boolean;
    function GetAttr(Sym: TSpiceSymbol; const Attr: String; out R: String): Boolean;
    function EvalMacro(Sheet: Integer; Sym: TSpiceSymbol; var SpiceLine: String; const Macro: String): Boolean;
  public
    FNet: TNetList;
    FLabels, FPreferred: TStrMap;      // net number -> label
    FNodeCount: TIntMap;               // net number -> nodes that belong to a symbol
    FErrors: String;
    FErrorCount: Integer;
    procedure WriteError(const Msg: String);
    function Expand(Sheet: Integer; Sym: TSpiceSymbol; const Spice: String): String;
  end;

{ ===========================================================================
  TSpiceSymbol.Create  (constructor)
  Parameters:
    AFileIdx: Integer - the file index (0, the root design)
    ASheet: Integer - the sheet number
    AMethod: TDrawMethod - the placed symbol
  Notes:
    CNetListSymbol: a symbol with no pins yet.
  =========================================================================== }
constructor TSpiceSymbol.Create(AFileIdx, ASheet: Integer; AMethod: TDrawMethod);
begin
  inherited Create;
  FileIdx := AFileIdx;
  Sheet := ASheet;
  Method := AMethod;
  Pins := TIntMap.Create;
  PinNames := TStrMap.Create;
end;

{ ===========================================================================
  TSpiceSymbol.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the pin maps.
  =========================================================================== }
destructor TSpiceSymbol.Destroy;
begin
  Pins.Free;
  PinNames.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TSpiceMaker.NetKey  (function)
  Parameters:
    N: Integer - the net number
  Returns:
    String
  Notes:
    The key under which a net number is kept in the maps.
  =========================================================================== }
function TSpiceMaker.NetKey(N: Integer): String;
begin
  Result := IntToStr(N);
end;

{ ===========================================================================
  TSpiceMaker.WriteError  (procedure)
  Parameters:
    const Msg: String - the message
  Notes:
    CNetList::writeError: one line "Netlist error #n: message" in the error text
  =========================================================================== }
procedure TSpiceMaker.WriteError(const Msg: String);
begin
  Inc(FErrorCount);
  FErrors := FErrors + 'Netlist error #' + IntToStr(FErrorCount) + ':  ' + Msg;
end;

{ ===========================================================================
  TSpiceMaker.GetPinByNumber  (function)
  Parameters:
    Sym: TSpiceSymbol
    const Pin: String - text
    out Nodes: Integer - whole number (out: set by the call)
    out R: String - the XML reader, positioned on this element (out: set by the call)
    out NetNo: Integer - whole number (out: set by the call)
  Returns:
    Boolean
  Notes:
    CNetList::get_pin_by_number: the name of the net at a pin (by pin number), the net's number
    and the number of symbol nodes on it
  =========================================================================== }
function TSpiceMaker.GetPinByNumber(Sym: TSpiceSymbol; const Pin: String; out Nodes: Integer; out R: String; out NetNo: Integer): Boolean;
begin
  Nodes := 0;
  R := '';
  NetNo := 0;
  if not Sym.Pins.Has(Pin) then
    Exit(False);
  NetNo := Sym.Pins.Get(Pin);
  if FPreferred.Has(NetKey(NetNo)) then
    R := FPreferred.Get(NetKey(NetNo))
  else if FLabels.Has(NetKey(NetNo)) and (FLabels.Get(NetKey(NetNo)) <> '') then
    R := '_N_' + FLabels.Get(NetKey(NetNo)) + '_' + IntToStr(NetNo)
  else
    R := '_N_' + IntToStr(NetNo);
  if FNodeCount.Has(NetKey(NetNo)) then
    Nodes := FNodeCount.Get(NetKey(NetNo));
  Result := True;
end;

{ ===========================================================================
  TSpiceMaker.GetPinByNumberOrName  (function)
  Parameters:
    Sym: TSpiceSymbol
    const Pin: String - text
    out Nodes: Integer - whole number (out: set by the call)
    out R: String - the XML reader, positioned on this element (out: set by the call)
    out NetNo: Integer - whole number (out: set by the call)
  Returns:
    Boolean
  Notes:
    CNetList::get_pin_by_number_or_name: the pin number first, then the pin name
  =========================================================================== }
function TSpiceMaker.GetPinByNumberOrName(Sym: TSpiceSymbol; const Pin: String; out Nodes: Integer; out R: String; out NetNo: Integer): Boolean;
begin
  if GetPinByNumber(Sym, Pin, Nodes, R, NetNo) then
    Exit(True);
  if Sym.PinNames.Has(Pin) then
    Exit(GetPinByNumber(Sym, Sym.PinNames.Get(Pin), Nodes, R, NetNo));
  Result := False;
end;

{ CNetList::get_attr: "refnum" and "ref" give the reference (the reference path of a symbol in the root design); any other name is
  looked up among all the fields of the symbol, ignoring case }

{ ===========================================================================
  TSpiceMaker.GetAttr  (function)
  Parameters:
    Sym: TSpiceSymbol - the symbol
    const Attr: String - the attribute name
    out R: String - the value
  Returns:
    Boolean
  Notes:
    CNetList::get_attr: "refnum" and "ref" give the symbol's reference (the reference path of a
    symbol of the root design is its reference); any other name is looked up among all the
    fields of the symbol, ignoring case.
  =========================================================================== }
function TSpiceMaker.GetAttr(Sym: TSpiceSymbol; const Attr: String; out R: String): Boolean;
var
  J: Integer;
begin
  R := '';
  if SameText(Attr, 'refnum') or SameText(Attr, 'ref') then
  begin
    R := Sym.Method.GetRef;
    Exit(True);
  end;
  for J := 0 to Sym.Method.GetFieldCount - 1 do
    if SameText(Sym.Method.GetFieldName(J), Attr) then
    begin
      R := Sym.Method.GetField(J);
      Exit(True);
    end;
  Result := False;
end;

{ ===========================================================================
  TrimWhite  (function)
  Parameters:
    const S: String - the text
  Returns:
    String
  Notes:
    CString::Trim: removes white space from both ends.
  =========================================================================== }
function TrimWhite(const S: String): String;
var
  A, B: Integer;
begin
  A := 1;
  B := Length(S);
  while (A <= B) and (S[A] in [' ', #9, #10, #11, #12, #13]) do Inc(A);
  while (B >= A) and (S[B] in [' ', #9, #10, #11, #12, #13]) do Dec(B);
  Result := Copy(S, A, B - A + 1);
end;

{ ===========================================================================
  TSpiceMaker.EvalMacro  (function)
  Parameters:
    Sheet: Integer - the sheet
    Sym: TSpiceSymbol
    var SpiceLine: String - text (in/out: changed by the call)
    const Macro: String - text
  Returns:
    Boolean
  Notes:
    CNetList::eval_spice_macro: the test of ?(test,then,else)
  =========================================================================== }
function TSpiceMaker.EvalMacro(Sheet: Integer; Sym: TSpiceSymbol; var SpiceLine: String; const Macro: String): Boolean;
var
  Brk, Nodes, NetNo: Integer;
  Op, Value, R: String;
begin
  Result := False;
  Brk := Pos('(', Macro);
  if Brk = 0 then
  begin
    SpiceLine := SpiceLine + '<Unknown query operation: ' + Macro + '>';
    Exit;
  end;
  Op := Copy(Macro, 1, Brk - 1);
  Value := Copy(Macro, Brk + 1, MaxInt);
  if (Value <> '') and (Value[Length(Value)] = ')') then
    Value := Copy(Value, 1, Length(Value) - 1);
  Op := TrimWhite(Op);
  Value := TrimWhite(Value);
  if Op = 'defined' then
    Result := GetAttr(Sym, Value, R)
  else if Op = 'not_defined' then
    Result := not GetAttr(Sym, Value, R)
  else if Op = 'empty' then
  begin
    GetAttr(Sym, Value, R);
    Result := R = '';
  end
  else if Op = 'not_empty' then
  begin
    GetAttr(Sym, Value, R);
    Result := R <> '';
  end
  else if Op = 'connected' then
  begin
    GetPinByNumber(Sym, Value, Nodes, R, NetNo);
    Result := Nodes > 1;
  end
  else if Op = 'not_connected' then
  begin
    GetPinByNumber(Sym, Value, Nodes, R, NetNo);
    Result := Nodes = 1;
  end
  else if Op = 'include' then
  begin
    SpiceLine := SpiceLine + '<Not implemented yet: ' + Macro + '>';
    WriteError(Format(rsOnSheetHasUnimplementedMacro, [Sym.Method.GetRef, Sym.Method.GetName, Sheet, Macro]));
  end
  else
  begin
    SpiceLine := SpiceLine + '<Unknown query operation: ' + Macro + '>';
    WriteError(Format(rsOnSheetUnknownQueryOperand, [Sym.Method.GetRef, Sym.Method.GetName, Sheet, Macro]));
  end;
end;

{ ===========================================================================
  TSpiceMaker.Expand  (function)
  Parameters:
    Sheet: Integer - the sheet
    Sym: TSpiceSymbol
    const Spice: String - text
  Returns:
    String
  Notes:
    expand_spice. $(attribute) a field, %(pin) the net name at a pin number or pin name, @(pin)
    its net number, ?(test,then,else) a conditional whose chosen text is expanded again, \ the
    next character as it is. A carriage return in the text is dropped. A macro that is not
    finished when the text ends writes nothing.
  =========================================================================== }
function TSpiceMaker.Expand(Sheet: Integer; Sym: TSpiceSymbol; const Spice: String): String;
type
  TMode = (mNormal, mAwaitingPin, mReadingPin, mAwaitingNet, mReadingNet, mAwaitingAttr, mReadingAttr, mAwaitingMacro, mReadingMacro,
    mAwaitingMacroEscape, mAwaitingEscape);
var
  Mode: TMode;
  Lookup, R, Insert, Line: String;
  Macros: array of String;
  Brackets, I, Nodes, NetNo: Integer;
  C: Char;
  Ok: Boolean;
begin
  Line := '';
  Mode := mNormal;
  Lookup := '';
  Brackets := 0;
  SetLength(Macros, 0);
  for I := 1 to Length(Spice) do
  begin
    C := Spice[I];
    case Mode of
      mNormal:
        begin
          if C = '%' then
            Mode := mAwaitingPin
          else if C = '@' then
            Mode := mAwaitingNet
          else if C = '$' then
            Mode := mAwaitingAttr
          else if C = '?' then
            Mode := mAwaitingMacro
          else if C = '\' then
            Mode := mAwaitingEscape
          else if C = #13 then { dropped }
          else
            Line := Line + C;
        end;
      mAwaitingEscape:
        begin
          Line := Line + C;
          Mode := mNormal;
        end;
      mAwaitingMacroEscape:
        begin
          Lookup := Lookup + C;
          Mode := mReadingMacro;
        end;
      mAwaitingPin:
        if C <> '(' then begin
          Line := Line + C;
          Mode := mNormal;
        end
        else begin
          Lookup := '';
          Mode := mReadingPin;
        end;
      mAwaitingNet:
        if C <> '(' then begin
          Line := Line + C;
          Mode := mNormal;
        end
        else begin
          Lookup := '';
          Mode := mReadingNet;
        end;
      mAwaitingAttr:
        if C <> '(' then begin
          Line := Line + C;
          Mode := mNormal;
        end
        else begin
          Lookup := '';
          Mode := mReadingAttr;
        end;
      mAwaitingMacro:
        if C <> '(' then begin
          Line := Line + C;
          Mode := mNormal;
        end
        else begin
          Lookup := '';
          Brackets := 1;
          Mode := mReadingMacro;
        end;
      mReadingPin, mReadingNet:
        if C <> ')' then
          Lookup := Lookup + C
        else
        begin
          if GetPinByNumberOrName(Sym, Lookup, Nodes, R, NetNo) then
          begin
            if Mode = mReadingPin then
              Line := Line + R
            else
              Line := Line + IntToStr(NetNo);
          end
          else
          begin
            Line := Line + '<pin ''' + Lookup + ''' not found>';
            WriteError(Format(rsOnSheetPinNotFound, [Sym.Method.GetRef, Sym.Method.GetName, Sheet, Lookup]));
          end;
          Mode := mNormal;
        end;
      mReadingAttr:
        if C <> ')' then
          Lookup := Lookup + C
        else
        begin
          if GetAttr(Sym, Lookup, R) then
            Line := Line + R
          else
          begin
            Line := Line + '<attr ''' + Lookup + ''' not found>';
            WriteError(Format(rsOnSheetAttributeNotFound, [Sym.Method.GetRef, Sym.Method.GetName, Sheet, Lookup]));
          end;
          Mode := mNormal;
        end;
      mReadingMacro:
        if C = '\' then
        begin
          if Brackets = 1 then
            Mode := mAwaitingMacroEscape
          else
            Lookup := Lookup + '\';
        end
        else if C = ',' then
        begin
          if Brackets = 1 then
          begin
            SetLength(Macros, Length(Macros) + 1);
            Macros[High(Macros)] := Lookup;
            Lookup := '';
          end
          else
            Lookup := Lookup + C;
        end
        else if C = '(' then
        begin
          Inc(Brackets);
          Lookup := Lookup + C;
        end
        else if C <> ')' then
          Lookup := Lookup + C
        else
        begin
          Dec(Brackets);
          if Brackets = 0 then
          begin
            SetLength(Macros, Length(Macros) + 1);
            Macros[High(Macros)] := Lookup;
            Ok := EvalMacro(Sheet, Sym, Line, Macros[0]);
            Insert := '';
            if Ok and (Length(Macros) > 1) then
              Insert := Macros[1];
            if (not Ok) and (Length(Macros) > 2) then
              Insert := Macros[2];
            SetLength(Macros, 0);
            Lookup := '';
            Mode := mNormal;
            Line := Line + Expand(Sheet, Sym, Insert);
          end
          else
            Lookup := Lookup + C;
        end;
    end;
  end;
  Result := Line;
end;

{ ===========================================================================
  FieldByName  (function)
  Parameters:
    M: TDrawMethod
    const AName: String - the name
  Returns:
    String
  Notes:
    CDrawMethod::GetFieldByName(name): the value of the first field with exactly that name,
    empty if there is none
  =========================================================================== }
function FieldByName(M: TDrawMethod; const AName: String): String;
var
  J: Integer;
begin
  Result := '';
  for J := 0 to M.GetFieldCount - 1 do
    if M.GetFieldName(J) = AName then
    begin
      if J = 0 then
        Result := M.GetRef
      else
        Result := M.GetField(J);
      Exit;
    end;
end;

{ ===========================================================================
  SpiceText  (function)
  Parameters:
    Design: TDesignFile - the design
    const DesignFileName: String - text
    const Stamp: String - text
    const EOL: String - text
    out ErrorText: String - text (out: set by the call)
    out ErrorCount: Integer - whole number (out: set by the call)
  Returns:
    String
  Notes:
    WriteSpiceFile. One line for every reference that has a pin on a net, in the order of the
    references (by character code); the prolog lines in order of priority (0 to 9), the epilog
    lines from 9 down to 0. As in the C++ the epilog lines are filed under the symbol's prolog
    priority (the epilog priority is read and not used), and every symbol files its prolog and
    its epilog even when empty; each set keeps one copy of a text, so a blank line comes out
    wherever some symbol has no text at that priority, the default being 5.
  =========================================================================== }
function SpiceText(Design: TDesignFile; const DesignFileName, Stamp, EOL: String; out ErrorText: String; out ErrorCount: Integer): String;
var
  Maker: TSpiceMaker;
  Net: TNetList;
  Symbols: TObjMap;
  Garbage: TObjectList;
  Prolog, Epilog: array[0..9] of TStrMap;
  Output, PinName, PinNumber, PrologText, EpilogText, Spice: String;
  Ni, K, P, SheetNo, J, ProPri, Count: Integer;
  V: TNodeVector;
  Nd: TNetListNode;
  Sym: TSpiceSymbol;
  Pin: TDrawPin;
  Obj: TDrawingObject;
  M: TDrawMethod;
  Fld: String;
  Tmp: TSpiceSymbol;
begin
  Maker := TSpiceMaker.Create;
  Net := TNetList.Create;
  Symbols := TObjMap.Create;
  Garbage := TObjectList.Create(True);
  for P := 0 to 9 do
  begin
    Prolog[P] := TStrMap.Create;
    Epilog[P] := TStrMap.Create;
  end;
  Maker.FLabels := TStrMap.Create;
  Maker.FPreferred := TStrMap.Create;
  Maker.FNodeCount := TIntMap.Create;
  try
    Maker.FNet := Net;
    Output := '* Schematics Netlist created on ' + Stamp + ' *'#10;
    Maker.FErrors := 'Results of Spice netlist generation for ' + DesignFileName + #10#10;
    Net.MakeNet(Design);

    { rotate the nets into one entry for each symbol }
    for Ni := 0 to Net.Nets.Count - 1 do
    begin
      V := Net.Nets.Vec(Ni);
      Count := 0;
      for K := 0 to High(V) do
        if V[K].Method <> nil then
          Inc(Count);
      Maker.FNodeCount.SetValue(IntToStr(Net.Nets.Key(Ni)), Count);
      for K := 0 to High(V) do
      begin
        Nd := V[K];
        if (Nd.Reference <> '') and (Nd.Method <> nil) then
        begin
          if Symbols.Get(Nd.Reference) = nil then
          begin
            Sym := TSpiceSymbol.Create(0, 0, nil);
            Garbage.Add(Sym);
            Symbols.SetValue(Nd.Reference, Sym);
          end;
          Sym := TSpiceSymbol(Symbols.Get(Nd.Reference));
          Sym.RefCopy := Nd.Reference;
          Sym.Sheet := Nd.Sheet;
          if (Nd.Parent <> nil) and (Nd.Parent.GetType = xPinEx) then
          begin
            Pin := Nd.Parent as TDrawPin;
            PinName := Pin.GetPinName;
            PinNumber := Pin.GetNumber;
            if PinName = '' then
              Maker.WriteError(Format(rsPinOnSheetHasA, [Sym.RefCopy, Nd.Sheet, PinNumber]));
            if PinNumber = '' then
              Maker.WriteError(Format(rsPinOnSheetHasA2, [Sym.RefCopy, Nd.Sheet, PinName]));
            if (Sym.PinNames.Count > 0) and Sym.PinNames.Has(PinName) then
              Maker.WriteError(Format(rsPinOnSheetHasA3, [Sym.RefCopy, Nd.Sheet, PinName, PinNumber]));
            Sym.PinNames.SetValue(PinName, PinNumber);
            if (Sym.Pins.Count > 0) and Sym.Pins.Has(PinNumber) then
              Maker.WriteError(Format(rsPinOnSheetHasA4, [Sym.RefCopy, Nd.Sheet, PinName, PinNumber]));
          end;
          Sym.Pins.SetValue(Nd.Pin, Nd.NetList);
          Sym.Method := Nd.Method;
          Sym.FileIdx := Nd.FileNameIndex;
        end;
        if NodeLabel(Nd) <> '' then
          Maker.FLabels.SetValue(IntToStr(Nd.NetList), NodeLabel(Nd));
        if NodePreferredLabel(Nd) <> '' then
          Maker.FPreferred.SetValue(IntToStr(Nd.NetList), NodePreferredLabel(Nd));
      end;
    end;

    { the prolog and epilog texts of every symbol of the design }
    for SheetNo := 0 to Design.SheetCount - 1 do
      for J := 0 to Design.Sheets[SheetNo].Drawing.Count - 1 do
      begin
        Obj := Design.Sheets[SheetNo].Drawing[J];
        if Obj.GetType <> xMethodEx3 then
          Continue;
        M := Obj as TDrawMethod;
        PrologText := '';
        EpilogText := '';
        ProPri := 5;
        for K := 0 to M.GetFieldCount - 1 do
        begin
          Fld := M.GetFieldName(K);
          if SameText(Fld, '$$SPICE_PROLOG') then
          begin
            Tmp := TSpiceSymbol.Create(0, SheetNo, M);
            try PrologText := Maker.Expand(SheetNo, Tmp, M.GetField(K)); finally Tmp.Free; end;
          end
          else if SameText(Fld, '$$SPICE_EPILOG') then
          begin
            Tmp := TSpiceSymbol.Create(0, SheetNo, M);
            try EpilogText := Maker.Expand(SheetNo, Tmp, M.GetField(K)); finally Tmp.Free; end;
          end
          else if SameText(Fld, '$$SPICE_PROLOG_PRIORITY') then
          begin
            ProPri := CAtoi(M.GetField(K));
            if (ProPri < 0) or (ProPri > 9) then
              ProPri := 5;
          end
          else if SameText(Fld, '$$SPICE_EPILOG_PRIORITY') then
          begin
            { read and range-checked, never used: the epilog is filed under the prolog priority }
          end;
        end;
        Prolog[ProPri].SetValue(PrologText, '');
        Epilog[ProPri].SetValue(EpilogText, '');
      end;

    for P := 0 to 9 do
      for K := 0 to Prolog[P].Count - 1 do
        Output := Output + Prolog[P].KeyAt(K) + #10;

    { one line for each symbol }
    for K := 0 to Symbols.Count - 1 do
    begin
      Sym := TSpiceSymbol(Symbols.ValueAt(K));
      Spice := FieldByName(Sym.Method, '$$SPICE');
      if Spice <> '' then
        Output := Output + Maker.Expand(Sym.Sheet, Sym, Spice) + #10
      else
      begin
        Output := Output + 'NO_MODEL found on ' + Sym.Method.GetRef + #10;
        Maker.WriteError(Format(rsOnSheetHasNoModel, [Sym.Method.GetRef, Sym.Method.GetName, Sym.Sheet]));
      end;
    end;

    for P := 9 downto 0 do
      for K := 0 to Epilog[P].Count - 1 do
        Output := Output + Epilog[P].KeyAt(K) + #10;

    ErrorCount := Maker.FErrorCount;
    ErrorText := Maker.FErrors + #10 + IntToStr(Maker.FErrorCount) + ' ';
    if Maker.FErrorCount = 1 then
      ErrorText := ErrorText + 'error'
    else
      ErrorText := ErrorText + 'errors';
    ErrorText := ErrorText + ' found'#10;
  finally
    Maker.FLabels.Free;
    Maker.FPreferred.Free;
    Maker.FNodeCount.Free;
    for P := 0 to 9 do
    begin
      Prolog[P].Free;
      Epilog[P].Free;
    end;
    Garbage.Free;
    Symbols.Free;
    Net.Free;
    Maker.Free;
  end;
  if EOL <> #10 then
  begin
    Output := StringReplace(Output, #10, EOL, [rfReplaceAll]);
    ErrorText := StringReplace(ErrorText, #10, EOL, [rfReplaceAll]);
  end;
  Result := Output;
end;

end.
