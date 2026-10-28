{ Port of TinyCAD's design rules check (the electrical rules check, ERC) of Net.cpp: CTinyCadView::DoSpecialCheck and DoSpecialVHDLCheck, the
  ErrorTest options of the "Check Design Rules" dialog (CDlgERCBox) and the CDrawError markers.

  The check builds the netlist of the design (without following hierarchical imports) and looks for, in this order: reference designators that are
  not assigned (a "?" in the reference), nets with more than one name and net names that differ only in letter case, references used by more than
  one symbol, symbols of which not every part is in the design, and finally problems inside each net, found by running the net's nodes through a
  state machine (ErcTable) of net type against node type: items not connected to anything, more than one item on a no-connect, power joined to a
  power of another name, power joined to an output, an output joined to an output, a net with inputs and no driver, and nets with nothing on them.
  Every problem gives one line of text for the results list and one circle marker (TDrawError) on the sheet, numbered like its line.

  The VHDL variant first joins the nets whose labels are the same bus (name(7:0) and name(3) are parts of the bus "name") into one set and checks
  each set as if it were one net; and an output joined to an output is not an error there (the C++ comment says the check cannot know whether the
  net is a bus).

  Differences from TinyCAD:
   - Markers left by an earlier check are removed when a new check starts (the C++ only removes them when the results window is closed or
     "Re-check" is used, so running the check from the menu a second time with the window open stacked a second set of markers whose numbers
     collide with the first).
   - The hierarchy is not loaded, so "follow imports = false" changes nothing.
   - The messages list gets the "No errors" line only when the caller asks for the list to be always shown, as in the C++.
   - The C++ checks the "non-case distinct" flag nowhere inside the scan: with only "Multiple net names" ticked the case-only differences are
     still reported, and with only "Non-case distinct" ticked the scan runs but the multiple-name lines are not written. This port does the same.

  Names that sort (net names, references) are compared by bytes, as CString::operator< does.

  Original: Copyright 1994-2019 Matt Pyne, LGPL 2.1+. This port keeps that licence. }
unit UErc;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, UDPoint, UDrawTypes, UDrawingObjects, UDesign, UNetList, USpiceVhdl;

const
  { the numbers of the messages (resource.h); anything from ERR_BASE up is an error id }
  ERR_BASE = 1099;
  ERR_UNCONNECT = 1100;
  ERR_POWER = 1101;
  ERR_NOCONNECT = 1102;
  ERR_NOUTPUT = 1103;
  ERR_DUPREF = 1104;
  ERR_OUTPUT = 1105;
  ERR_OUTPUTTOPWR = 1106;
  ERR_UNCONNECTED = 1107;
  ERR_OUTPUTBIDIR = 1108;
  ERR_POWERBIDIR = 1109;
  ERR_NOERROR = 1110;
  ERR_UNASSIGNEDREFDES = 1117;
  ERR_NONDISTINCTNET = 1118;
  ERR_MULTIPLENETNAMES = 1119;

  { NetType }
  nUnknown = 0;
  nPassive = 1;
  nInput = 2;
  nOutput = 3;
  nBiDir = 4;
  nPower = 5;
  nNoConnect = 6;

type
  { ErrorTest: which checks are on }
  TErcOptions = record
    DupRef, UnConnect, NoConnect, Power, OutputPwr, Output, NoOutput, UnConnected,
    MultipleNetNames, NonCaseDistinctNetNames, UnAssignedRefDes: Boolean;
  end;

{ The options in the WORD the registry value "ERC" holds: bit 0 DupRef up to bit 10 UnAssignedRefDes, in the order of the record }
function ErcOptionsFromWord(W: Word): TErcOptions;
function ErcOptionsToWord(const O: TErcOptions): Word;
{ The registry's default 0xffff: everything on }
function ErcDefaultWord: Word;
{ The text of a message number (TinyCad.rc string table) }
function ErcMessage(Id: Integer): String;
{ ErcTable[netType][nodeType] }
function ErcTableLookup(NetType, NodeType: Integer): Integer;
{ printf("%g") of a number }
function FormatG(X: Double): String;
{ CTinyCadDoc::DeleteErrors for every sheet: remove all check markers; returns how many were removed }
function ClearErcMarkers(Design: TDesignFile): Integer;
{ How many markers the design has }
function CountErcMarkers(Design: TDesignFile): Integer;
{ DoSpecialCheck (Vhdl = False) or DoSpecialVHDLCheck (Vhdl = True). Adds markers to the sheets and one line per marker to Messages (which is
  not cleared first). With AlwaysShowList and no errors the "No errors were found" line is added (the return value stays 0). Returns the number
  of errors found. }
function RunErc(Design: TDesignFile; const O: TErcOptions; Vhdl, AlwaysShowList: Boolean; Messages: TStrings): Integer;

implementation


uses UStrings;

type
  { std::map<CString, int> with CString's order: sorted by bytes, the value is a number }
  TStrMap = class
  private
    FKeys: array of String;
    FVals: array of Integer;
    function Search(const K: String; out Index: Integer): Boolean;
  public
    function Find(const K: String; out Value: Integer): Boolean;
    function Has(const K: String): Boolean;
    procedure SetValue(const K: String; V: Integer);
    function Count: Integer;
    function KeyAt(I: Integer): String;
    function ValueAt(I: Integer): Integer;
  end;

{ ===========================================================================
  TStrMap.Search  (function)
  Parameters:
    const K: String - the key
    out Index: Integer - where the key is, or would be inserted
  Returns:
    Boolean - True if the key is in the map
  Notes:
    Binary search in byte order.
  =========================================================================== }
function TStrMap.Search(const K: String; out Index: Integer): Boolean;
var
  Lo, Hi, Mid, C: Integer;
begin
  Lo := 0;
  Hi := Length(FKeys) - 1;
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
  TStrMap.Find  (function)
  Parameters:
    const K: String - the key
    out Value: Integer - its value
  Returns:
    Boolean - True if the key is in the map
  Notes:
    Looks a key up.
  =========================================================================== }
function TStrMap.Find(const K: String; out Value: Integer): Boolean;
var
  I: Integer;
begin
  Result := Search(K, I);
  if Result then
    Value := FVals[I]
  else
    Value := 0;
end;

{ ===========================================================================
  TStrMap.Has  (function)
  Parameters:
    const K: String - the key
  Returns:
    Boolean - True if the key is in the map
  Notes:
    Membership test.
  =========================================================================== }
function TStrMap.Has(const K: String): Boolean;
var
  I: Integer;
begin
  Result := Search(K, I);
end;

{ ===========================================================================
  TStrMap.SetValue  (procedure)
  Parameters:
    const K: String - the key
    V: Integer - the value
  Notes:
    map[key] = value: adds the key or replaces its value.
  =========================================================================== }
procedure TStrMap.SetValue(const K: String; V: Integer);
var
  I, J: Integer;
begin
  if Search(K, I) then
    FVals[I] := V
  else
  begin
    SetLength(FKeys, Length(FKeys) + 1);
    SetLength(FVals, Length(FVals) + 1);
    for J := Length(FKeys) - 1 downto I + 1 do
    begin
      FKeys[J] := FKeys[J - 1];
      FVals[J] := FVals[J - 1];
    end;
    FKeys[I] := K;
    FVals[I] := V;
  end;
end;

{ ===========================================================================
  TStrMap.Count  (function)
  Parameters:  none
  Returns:
    Integer - the number of keys
  Notes:
    Size of the map.
  =========================================================================== }
function TStrMap.Count: Integer;
begin
  Result := Length(FKeys);
end;

{ ===========================================================================
  TStrMap.KeyAt  (function)
  Parameters:
    I: Integer - position in key order
  Returns:
    String - the key
  Notes:
    The key at a position in key order.
  =========================================================================== }
function TStrMap.KeyAt(I: Integer): String;
begin
  Result := FKeys[I];
end;

{ ===========================================================================
  TStrMap.ValueAt  (function)
  Parameters:
    I: Integer - position in key order
  Returns:
    Integer - the value
  Notes:
    The value at a position in key order.
  =========================================================================== }
function TStrMap.ValueAt(I: Integer): Integer;
begin
  Result := FVals[I];
end;

const
  { the rows are the net type so far, the columns the type of the next node (net.cpp ErcTable) }
  ErcTable: array[0..6, 0..6] of Integer = (
    (nUnknown, nPassive, nInput, nOutput, nBiDir, nPower, nNoConnect),
    (nPassive, nPassive, nPassive, nOutput, nBiDir, nPower, ERR_NOCONNECT),
    (nInput, nPassive, nInput, nOutput, nBiDir, nPower, ERR_NOCONNECT),
    (nOutput, nOutput, nOutput, ERR_OUTPUT, ERR_OUTPUTBIDIR, ERR_POWERBIDIR, ERR_NOCONNECT),
    (nBiDir, nBiDir, nBiDir, ERR_OUTPUTBIDIR, nBiDir, ERR_POWERBIDIR, ERR_NOCONNECT),
    (nPower, nPower, nPower, ERR_OUTPUTTOPWR, ERR_POWERBIDIR, nPower, ERR_NOCONNECT),
    (nNoConnect, ERR_NOCONNECT, ERR_NOCONNECT, ERR_NOCONNECT, ERR_NOCONNECT, ERR_NOCONNECT, ERR_NOCONNECT));

{ ===========================================================================
  ErcOptionsFromWord  (function)
  Parameters:
    W: Word - the registry value
  Returns:
    TErcOptions - the checks it turns on
  Notes:
    Unpacks the ErrorTest bit field: bit 0 is DupRef, then UnConnect, NoConnect, Power,
    OutputPwr, Output, NoOutput, UnConnected, MultipleNetNames, NonCaseDistinctNetNames,
    UnAssignedRefDes.
  =========================================================================== }
function ErcOptionsFromWord(W: Word): TErcOptions;
begin
  Result.DupRef := (W and 1) <> 0;
  Result.UnConnect := (W and 2) <> 0;
  Result.NoConnect := (W and 4) <> 0;
  Result.Power := (W and 8) <> 0;
  Result.OutputPwr := (W and 16) <> 0;
  Result.Output := (W and 32) <> 0;
  Result.NoOutput := (W and 64) <> 0;
  Result.UnConnected := (W and 128) <> 0;
  Result.MultipleNetNames := (W and 256) <> 0;
  Result.NonCaseDistinctNetNames := (W and 512) <> 0;
  Result.UnAssignedRefDes := (W and 1024) <> 0;
end;

{ ===========================================================================
  ErcOptionsToWord  (function)
  Parameters:
    const O: TErcOptions - the checks
  Returns:
    Word - the registry value
  Notes:
    Packs the checks into the ErrorTest bit field (the unused bits 11 to 15 are zero).
  =========================================================================== }
function ErcOptionsToWord(const O: TErcOptions): Word;
begin
  Result := 0;
  if O.DupRef then
    Result := Result or 1;
  if O.UnConnect then
    Result := Result or 2;
  if O.NoConnect then
    Result := Result or 4;
  if O.Power then
    Result := Result or 8;
  if O.OutputPwr then
    Result := Result or 16;
  if O.Output then
    Result := Result or 32;
  if O.NoOutput then
    Result := Result or 64;
  if O.UnConnected then
    Result := Result or 128;
  if O.MultipleNetNames then
    Result := Result or 256;
  if O.NonCaseDistinctNetNames then
    Result := Result or 512;
  if O.UnAssignedRefDes then
    Result := Result or 1024;
end;

{ ===========================================================================
  ErcDefaultWord  (function)
  Parameters:  none
  Returns:
    Word - $FFFF
  Notes:
    The registry default of the "ERC" value: every check on.
  =========================================================================== }
function ErcDefaultWord: Word;
begin
  Result := $FFFF;
end;

{ ===========================================================================
  ErcMessage  (function)
  Parameters:
    Id: Integer - the message number
  Returns:
    String - the text, empty for a number that is not a message
  Notes:
    The strings of TinyCad.rc for the check's messages.
  =========================================================================== }
function ErcMessage(Id: Integer): String;
begin
  case Id of
    ERR_DUPREF: Result := rsThisReferenceIsAlsoUsed;
    ERR_OUTPUT: Result := rsThisOutputIsConnectedTo;
    ERR_OUTPUTTOPWR: Result := rsThisOutputIsConnectedTo2;
    ERR_UNCONNECTED: Result := rsThisNetworkIsNotConnected;
    ERR_OUTPUTBIDIR: Result := rsThisTriStateOpenCollectorOutput;
    ERR_POWERBIDIR: Result := rsThisTriStateOpenCollectorOutput2;
    ERR_NOERROR: Result := rsNoErrorsWereFoundIn;
    ERR_UNASSIGNEDREFDES: Result := rsThisReferenceDesignatorHasNot;
    ERR_NONDISTINCTNET: Result := rsThereAreOrMoreNets;
    ERR_MULTIPLENETNAMES: Result := rsThisNetHasMoreThan;
    ERR_UNCONNECT: Result := rsThisItemIsNotConnected;
    ERR_POWER: Result := rsThisPowerIsConnectedTo;
    ERR_NOCONNECT: Result := rsMoreThanOneItemIs;
    ERR_NOUTPUT: Result := rsThisNetworkHasNoOutput;
  else
    Result := '';
  end;
end;

{ ===========================================================================
  ErcTableLookup  (function)
  Parameters:
    NetType: Integer - the net type so far (0..6)
    NodeType: Integer - the type of the next node (0..6)
  Returns:
    Integer - the new net type, or an error id of ERR_BASE + 1 or more
  Notes:
    One step of the state machine.
  =========================================================================== }
function ErcTableLookup(NetType, NodeType: Integer): Integer;
begin
  Result := ErcTable[NetType, NodeType];
end;

{ ===========================================================================
  SixDigits  (procedure)
  Parameters:
    X: Double - a finite number greater than zero
    out Digits: String - six digits
    out E10: Integer - the decimal exponent of the first digit
  Notes:
    Rounds the exact decimal value of X to six significant digits the way the C library does
    (exact ties go to the even digit). The exact value is built with whole-number arithmetic:
    the mantissa times 2^e is the mantissa times 5^-e shifted by -e places when e is negative.
  =========================================================================== }
procedure SixDigits(X: Double; out Digits: String; out E10: Integer);
var
  Bits, Mant: QWord;
  Ex, E2, I, J, Carry, T, L, Shift: Integer;
  Big: array of Byte;   // little-endian decimal digits
  S: String;
  Up: Boolean;
  AnyNonZero: Boolean;
begin
  Bits := PQWord(@X)^;
  Ex := Integer((Bits shr 52) and $7FF);
  Mant := Bits and QWord($000FFFFFFFFFFFFF);
  if Ex = 0 then
    E2 := -1074
  else begin
    Mant := Mant or QWord($0010000000000000);
    E2 := Ex - 1075;
  end;
  S := IntToStr(Mant);
  SetLength(Big, Length(S));
  for I := 0 to Length(S) - 1 do Big[I] := Ord(S[Length(S) - I]) - 48;
  Shift := 0;
  if E2 >= 0 then
    for J := 1 to E2 do
    begin
      Carry := 0;
      for I := 0 to High(Big) do
      begin
        T := Big[I] * 2 + Carry;
        Big[I] := T mod 10;
        Carry := T div 10;
      end;
      if Carry > 0 then begin
        SetLength(Big, Length(Big) + 1);
        Big[High(Big)] := Carry;
      end;
    end
  else
  begin
    Shift := E2;
    for J := 1 to -E2 do
    begin
      Carry := 0;
      for I := 0 to High(Big) do
      begin
        T := Big[I] * 5 + Carry;
        Big[I] := T mod 10;
        Carry := T div 10;
      end;
      if Carry > 0 then begin
        SetLength(Big, Length(Big) + 1);
        Big[High(Big)] := Carry;
      end;
    end;
  end;
  { big-endian text without leading zeros }
  S := '';
  for I := High(Big) downto 0 do S := S + Chr(48 + Big[I]);
  while (Length(S) > 1) and (S[1] = '0') do Delete(S, 1, 1);
  L := Length(S);
  E10 := L - 1 + Shift;
  if L <= 6 then
    Digits := S + StringOfChar('0', 6 - L)
  else
  begin
    Digits := Copy(S, 1, 6);
    AnyNonZero := False;
    for I := 8 to L do if S[I] <> '0' then
      AnyNonZero := True;
    if S[7] > '5' then
      Up := True
    else if S[7] < '5' then
      Up := False
    else if AnyNonZero then
      Up := True
    else
      Up := ((Ord(S[6]) - 48) mod 2) = 1;
    if Up then
    begin
      I := 6;
      while (I >= 1) and (Digits[I] = '9') do begin
        Digits[I] := '0';
        Dec(I);
      end;
      if I >= 1 then
        Digits[I] := Chr(Ord(Digits[I]) + 1)
      else begin
        Digits := '1' + Copy(Digits, 1, 5);
        Inc(E10);
      end;
    end;
  end;
end;

{ ===========================================================================
  FormatG  (function)
  Parameters:
    X: Double - the number
  Returns:
    String - the number as printf("%g") writes it
  Notes:
    Six significant digits, trailing zeros and a bare point removed, and the exponent form
    (1e+06, 1e-05) when the decimal exponent is below -4 or at least 6. The digits are exact
    (see SixDigits), so the result is the C library's for every number.
  =========================================================================== }
function FormatG(X: Double): String;
var
  Digits: String;
  E: Integer;
begin
  if X = 0 then
  begin
    if (PQWord(@X)^ shr 63) <> 0 then
      Exit('-0')
    else
      Exit('0');
  end;
  SixDigits(Abs(X), Digits, E);
  if (E < -4) or (E >= 6) then
  begin
    while (Length(Digits) > 1) and (Digits[Length(Digits)] = '0') do Delete(Digits, Length(Digits), 1);
    Result := Copy(Digits, 1, 1);
    if Length(Digits) > 1 then
      Result := Result + '.' + Copy(Digits, 2, Length(Digits));
    if E < 0 then
      Result := Result + 'e-' + Format('%.2d', [-E])
    else
      Result := Result + 'e+' + Format('%.2d', [E]);
  end
  else if E >= 0 then
  begin
    Result := Copy(Digits, 1, E + 1);
    Digits := Copy(Digits, E + 2, 10);
    while (Length(Digits) > 0) and (Digits[Length(Digits)] = '0') do Delete(Digits, Length(Digits), 1);
    if Digits <> '' then
      Result := Result + '.' + Digits;
  end
  else
  begin
    Digits := StringOfChar('0', -E - 1) + Digits;
    while (Length(Digits) > 0) and (Digits[Length(Digits)] = '0') do Delete(Digits, Length(Digits), 1);
    Result := '0.' + Digits;
  end;
  if X < 0 then
    Result := '-' + Result;
end;

{ ===========================================================================
  ClearErcMarkers  (function)
  Parameters:
    Design: TDesignFile - the design
  Returns:
    Integer - how many markers were removed
  Notes:
    Deletes every TDrawError object from every sheet (CTinyCadDoc::DeleteErrors).
  =========================================================================== }
function ClearErcMarkers(Design: TDesignFile): Integer;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 0 to Design.SheetCount - 1 do
    for J := Design.Sheets[I].Drawing.Count - 1 downto 0 do
      if Design.Sheets[I].Drawing[J].GetType = xError then
      begin
        Design.Sheets[I].Drawing.Delete(J);
        Inc(Result);
      end;
end;

{ ===========================================================================
  CountErcMarkers  (function)
  Parameters:
    Design: TDesignFile - the design
  Returns:
    Integer - the number of markers on all sheets
  Notes:
    Counts the TDrawError objects.
  =========================================================================== }
function CountErcMarkers(Design: TDesignFile): Integer;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 0 to Design.SheetCount - 1 do
    for J := 0 to Design.Sheets[I].Drawing.Count - 1 do
      if Design.Sheets[I].Drawing[J].GetType = xError then
        Inc(Result);
end;

{ ===========================================================================
  RawFieldByName  (function)
  Parameters:
    M: TDrawMethod
    const AName: String - the name
  Returns:
    String
  Notes:
    The C++ GetFieldByName("Ref"): the raw value of the first field called exactly that
  =========================================================================== }
function RawFieldByName(M: TDrawMethod; const AName: String): String;
var
  J: Integer;
begin
  Result := '';
  for J := 0 to Length(M.Fields) - 1 do
    if M.Fields[J].Description = AName then
    begin
      Result := M.Fields[J].Value;
      Exit;
    end;
end;

{ ===========================================================================
  RunErc  (function)
  Parameters:
    Design: TDesignFile - the design to check; markers are added to its sheets
    const O: TErcOptions - the checks that are on
    Vhdl: Boolean - True for the VHDL check (bus nets joined, output to output allowed)
    AlwaysShowList: Boolean - True to add the "No errors" line when nothing was found
    Messages: TStrings - receives the result lines (not cleared first)
  Returns:
    Integer - the number of errors (markers) found
  Notes:
    DoSpecialCheck / DoSpecialVHDLCheck without the window: the same scans in the same order.
    Marker k belongs to line k of the messages. Markers of an earlier check are removed first.
  =========================================================================== }
function RunErc(Design: TDesignFile; const O: TErcOptions; Vhdl, AlwaysShowList: Boolean; Messages: TStrings): Integer;
var
  NL: TNetList;
  CurrentError: Integer;

  procedure AddMarker(SheetIndex: Integer; const P: TDPoint);
  var
    E: TDrawError;
    Sh: TDesignSheet;
  begin
    Sh := Design.Sheets[SheetIndex];
    E := TDrawError.Create(Sh.Options);
    E.PointA := P;
    E.PointB := P;
    E.ErrorNumber := CurrentError;
    Inc(CurrentError);
    Sh.Drawing.Add(E);
  end;

  function FieldPosRef(M: TDrawMethod): TDPoint;
  begin
    Result := DPoint(M.PointA.x + M.Fields[FIELD_REF].Position.x, M.PointA.y + M.Fields[FIELD_REF].Position.y);
  end;

  procedure ScanUnassigned;
  var
    I, J: Integer;
    M: TDrawMethod;
    Ref: String;
  begin
    for I := 0 to Design.SheetCount - 1 do
      for J := 0 to Design.Sheets[I].Drawing.Count - 1 do
        if Design.Sheets[I].Drawing[J].GetType = xMethodEx3 then
        begin
          M := Design.Sheets[I].Drawing[J] as TDrawMethod;
          Ref := M.GetField(FIELD_REF);
          if Pos('?', Ref) > 0 then
          begin
            Messages.Add(ErcMessage(ERR_UNASSIGNEDREFDES) + ':  [refdes=' + Ref + ', page="' + Design.Sheets[I].SheetName +
              '", XY=(' + FormatG(M.PointA.x / 5) + ',' + FormatG(M.PointA.y / 5) + ')]'#10);
            AddMarker(I, FieldPosRef(M));
          end;
        end;
  end;

  procedure ScanNames;
  var
    AllNames: TStrMap;          // lower case name -> index into AllNodes
    AllNodes: array of TNetListNode;
    FirstName: TStrMap;         // lower case name -> index into FirstNames
    FirstNames: array of String;
    Ni, K, Idx, Q: Integer;
    V: TNodeVector;
    NetNames, NetNameNodes: TStrMap;   // name -> net, name -> index of the node in V
    Nd: TNetListNode;
    LabelName, LcName, Msg: String;
  begin
    FirstNames := nil;
    AllNodes := nil;
    AllNames := TStrMap.Create;
    FirstName := TStrMap.Create;
    try
      for Ni := 0 to NL.Nets.Count - 1 do
      begin
        V := NL.Nets.Vec(Ni);
        NetNames := TStrMap.Create;
        NetNameNodes := TStrMap.Create;
        try
          for K := 0 to High(V) do
          begin
            Nd := V[K];
            if (Nd.Parent <> nil) and ((Nd.Parent.GetType = xPower) or (Nd.Parent.GetType = xLabelEx2)) then
            begin
              if Nd.Parent.GetType = xPower then
                LabelName := TNetList.GetPowerLabel(Nd.Parent as TDrawPower)
              else
                LabelName := (Nd.Parent as TDrawLabel).GetValue;
              LcName := LowerCase(LabelName);
              if not NetNames.Has(LabelName) then
              begin
                NetNames.SetValue(LabelName, NL.Nets.Key(Ni));
                NetNameNodes.SetValue(LabelName, K);
                if not FirstName.Has(LcName) then
                begin
                  SetLength(FirstNames, Length(FirstNames) + 1);
                  FirstNames[High(FirstNames)] := LabelName;
                  FirstName.SetValue(LcName, High(FirstNames));
                end;
                if not AllNames.Has(LcName) then
                begin
                  SetLength(AllNodes, Length(AllNodes) + 1);
                  AllNodes[High(AllNodes)] := Nd;
                  AllNames.SetValue(LcName, High(AllNodes));
                end
                else
                begin
                  FirstName.Find(LcName, Idx);
                  Messages.Add(ErcMessage(ERR_NONDISTINCTNET) + ':  "' + LabelName + '", "' + FirstNames[Idx] + '"');
                  AddMarker(Nd.Sheet - 1, Nd.A);
                  AllNames.Find(LcName, Q);
                  Messages.Add(ErcMessage(ERR_NONDISTINCTNET) + ':  "' + FirstNames[Idx] + '", "' + LabelName + '"');
                  AddMarker(AllNodes[Q].Sheet - 1, AllNodes[Q].A);
                end;
              end;
            end;
          end;
          if NetNames.Count > 1 then
            if O.MultipleNetNames then
            begin
              Msg := ErcMessage(ERR_MULTIPLENETNAMES) + ':  ["' + NetNames.KeyAt(0) + '"';
              for K := 1 to NetNames.Count - 1 do Msg := Msg + ',"' + NetNames.KeyAt(K) + '"';
              Msg := Msg + ']';
              for K := 0 to NetNameNodes.Count - 1 do
              begin
                Nd := V[NetNameNodes.ValueAt(K)];
                AddMarker(Nd.Sheet - 1, Nd.A);
                Messages.Add(Msg);
              end;
            end;
        finally
          NetNames.Free;
          NetNameNodes.Free;
        end;
      end;
    finally
      AllNames.Free;
      FirstName.Free;
    end;
  end;

  procedure ScanDupRef;
  var
    Seen: TStrMap;
    I, J: Integer;
    M: TDrawMethod;
    Ref: String;
  begin
    Seen := TStrMap.Create;
    try
      for I := 0 to Design.SheetCount - 1 do
        for J := 0 to Design.Sheets[I].Drawing.Count - 1 do
          if Design.Sheets[I].Drawing[J].GetType = xMethodEx3 then
          begin
            M := Design.Sheets[I].Drawing[J] as TDrawMethod;
            Ref := M.GetField(FIELD_REF);
            if Seen.Has(Ref) then
            begin
              Messages.Add(ErcMessage(ERR_DUPREF) + ':  [Object="' + M.GetName + '", RefDes=' + Ref + ', Page #' + IntToStr(I + 1) + ']'#10);
              AddMarker(I, FieldPosRef(M));
            end
            else
              Seen.SetValue(Ref, 1);
          end;
    finally
      Seen.Free;
    end;
  end;

  procedure ScanMissingParts;
  type
    TPartRef = record
      Ppp, Parts, Sheet: Integer;
      Point: TDPoint;
      Name: String;
    end;
  var
    Map: TStrMap;
    Refs: array of TPartRef;
    I, J, Ppp, K: Integer;
    M: TDrawMethod;
    Key: String;
    PR: TPartRef;
  begin
    Refs := nil;
    Map := TStrMap.Create;
    try
      for I := 0 to Design.SheetCount - 1 do
        for J := 0 to Design.Sheets[I].Drawing.Count - 1 do
          if Design.Sheets[I].Drawing[J].GetType = xMethodEx3 then
          begin
            M := Design.Sheets[I].Drawing[J] as TDrawMethod;
            Ppp := M.GetSymbolData.PartsPerPackage;
            if Ppp > 1 then
            begin
              Key := RawFieldByName(M, 'Ref');
              if Map.Find(Key, K) then
                Inc(Refs[K].Parts)
              else
              begin
                PR.Ppp := Ppp;
                PR.Parts := 1;
                PR.Sheet := I;
                PR.Point := FieldPosRef(M);
                PR.Name := M.GetName;
                SetLength(Refs, Length(Refs) + 1);
                Refs[High(Refs)] := PR;
                Map.SetValue(Key, High(Refs));
              end;
            end;
          end;
      for K := 0 to Map.Count - 1 do
      begin
        PR := Refs[Map.ValueAt(K)];
        if PR.Ppp <> PR.Parts then
        begin
          Messages.Add('Not all parts in this package are in this design:  [Object="' + PR.Name + '", RefDes=' + Map.KeyAt(K) +
            ', Page #' + IntToStr(PR.Sheet + 1) + ']'#10);
          AddMarker(PR.Sheet, PR.Point);
        end;
      end;
    finally
      Map.Free;
    end;
  end;

  { the net scan: V is the nodes of the net (or of every net of a bus set, in order) }
  procedure ScanNetSet(const Nets: array of TNodeVector);
  var
    Connections, NetType, NodeType, Sheet, ErrorNumber, NI, K: Integer;
    ObjName, RefDes, SheetName, XY, LastPower: String;
    PosPt: TDPoint;
    Nd: TNetListNode;
    Obj: TDrawingObject;
    Pin: TDrawPin;
    Stop: Boolean;
    PowerValue: String;
  begin
    Connections := 0;
    NetType := nUnknown;
    LastPower := '';
    Sheet := 0;
    PosPt := DPoint(0, 0);
    ObjName := ''; RefDes := ''; SheetName := ''; XY := '';
    Stop := False;
    for NI := 0 to High(Nets) do
    begin
      if Stop then
        Break;
      K := 0;
      while (NetType < ERR_BASE) and (K <= High(Nets[NI])) do
      begin
        Nd := Nets[NI][K];
        Obj := Nd.Parent;
        if Obj <> nil then
        begin
          NodeType := nUnknown;
          case Obj.GetType of
            xPower:
              begin
                NodeType := nPower;
                PowerValue := (Obj as TDrawPower).GetValue;
                if LastPower = '' then
                  LastPower := PowerValue
                else if LastPower <> PowerValue then
                begin
                  NetType := ERR_POWER;
                  NodeType := nUnknown;
                end;
                PosPt := Obj.PointA;
                Sheet := Nd.Sheet;
                ObjName := 'Obj=Power';
                RefDes := 'RefDes=N/A';
                SheetName := 'Sheet=#' + IntToStr(Nd.Sheet);
                XY := 'XY=(' + FormatG(Nd.A.x / 5) + ',' + FormatG(Nd.A.y / 5) + ')';
              end;
            xNoConnect:
              begin
                NodeType := nPassive;
                Inc(Connections);
                PosPt := Obj.PointA;
                Sheet := Nd.Sheet;
                ObjName := 'Obj=No Connect';
                RefDes := 'RefDes=N/A';
                SheetName := 'Sheet=#' + IntToStr(Nd.Sheet);
                XY := 'XY=(' + FormatG(Nd.A.x / 5) + ',' + FormatG(Nd.A.y / 5) + ')';
              end;
            xPin, xPinEx:
              begin
                Pin := Obj as TDrawPin;
                case Pin.Elec of
                  0: NodeType := nInput;
                  1: NodeType := nOutput;
                  2: NodeType := nBiDir;
                  3: NodeType := nBiDir;
                  4: NodeType := nPassive;
                  5: NodeType := nBiDir;
                  6: NodeType := nNoConnect;
                end;
                if Pin.IsPower then
                  NodeType := nPower;
                PosPt := Pin.GetActivePoint(Nd.Method);
                Sheet := Nd.Sheet;
                Inc(Connections);
                ObjName := 'Obj=Pin';
                RefDes := 'RefDes=' + Nd.Reference + ', Pin Number=' + Pin.GetNumber + ', Pin Name="' + Pin.GetPinName + '"';
                SheetName := 'Sheet="' + Design.Sheets[Nd.Sheet - 1].SheetName + '"';
                XY := 'XY=(' + FormatG(PosPt.x / 5) + ',' + FormatG(PosPt.y / 5) + ')';
              end;
          else
            NodeType := nUnknown;
          end;

          if NetType < ERR_BASE then
          begin
            if Vhdl and (NodeType = nOutput) and (NetType = nOutput) then
              { VHDL: an output joined to an output is not reported }
            else
              NetType := ErcTable[NetType, NodeType];
          end
          else
          begin
            Stop := True;
            Break;
          end;
        end;
        Inc(K);
      end;
    end;

    if (Connections = 1) and (NetType <> nNoConnect) then
      NetType := ERR_UNCONNECT;

    ErrorNumber := 0;
    case NetType of
      nUnknown: if Connections > 0 then
                  ErrorNumber := ERR_UNCONNECTED;
      nInput: ErrorNumber := ERR_NOUTPUT;
    else
      ErrorNumber := NetType;
    end;

    case ErrorNumber of
      ERR_UNCONNECT: if not O.UnConnect then
                       ErrorNumber := -1;
      ERR_POWER: if not O.Power then
                   ErrorNumber := -1;
      ERR_NOCONNECT: if not O.NoConnect then
                       ErrorNumber := -1;
      ERR_NOUTPUT: if not O.NoOutput then
                     ErrorNumber := -1;
      ERR_DUPREF: if not O.DupRef then
                    ErrorNumber := -1;
      ERR_OUTPUT: if not O.Output then
                    ErrorNumber := -1;
      ERR_OUTPUTTOPWR: if not O.OutputPwr then
                         ErrorNumber := -1;
      ERR_UNCONNECTED: if not O.UnConnected then
                         ErrorNumber := -1;
      ERR_OUTPUTBIDIR: if not O.Output then
                         ErrorNumber := -1;
      ERR_POWERBIDIR: if not O.OutputPwr then
                        ErrorNumber := -1;
    end;

    if ErrorNumber >= ERR_BASE then
    begin
      Messages.Add(ErcMessage(ErrorNumber) + ':  [' + ObjName + ', ' + RefDes + ', ' + SheetName + ', ' + XY + ']');
      AddMarker(Sheet - 1, PosPt);
    end;
  end;

  procedure ScanNets;
  var
    Ni: Integer;
    One: array of TNodeVector;
  begin
    for Ni := 0 to NL.Nets.Count - 1 do
    begin
      SetLength(One, 1);
      One[0] := NL.Nets.Vec(Ni);
      ScanNetSet(One);
    end;
  end;

  procedure ScanBusSets;
  var
    Sets: array of array of Integer;
    Names: TStrMap;
    Ni, K, SetNo, N: Integer;
    V: TNodeVector;
    TheLabel: String;
    Labeled: Boolean;
    B: TBusProps;
    Group: array of TNodeVector;
    Nd: TNetListNode;
  begin
    Sets := nil;
    Names := TStrMap.Create;
    try
      for Ni := 0 to NL.Nets.Count - 1 do
      begin
        V := NL.Nets.Vec(Ni);
        TheLabel := '';
        Labeled := False;
        for K := 0 to High(V) do
        begin
          Nd := V[K];
          if (NodeLabel(Nd) <> '') and (not Labeled) then
          begin
            TheLabel := NodeLabel(Nd);
            Labeled := True;
          end;
          if Nd.Method <> nil then
            if (Nd.Method.GetName = 'INPUT') or (Nd.Method.GetName = 'OUTPUT') then
            begin
              TheLabel := Nd.Method.GetRef;
              Labeled := True;
            end;
        end;
        if Labeled then
        begin
          B := ParseBus(TheLabel, bkDontKnow);
          if B.IsBus then
          begin
            if not Names.Find(B.Name, SetNo) then
            begin
              Names.SetValue(B.Name, Length(Sets));
              SetLength(Sets, Length(Sets) + 1);
              SetLength(Sets[High(Sets)], 1);
              Sets[High(Sets)][0] := Ni;
            end
            else
            begin
              N := Length(Sets[SetNo]);
              SetLength(Sets[SetNo], N + 1);
              Sets[SetNo][N] := Ni;
            end;
          end;
        end
        else
        begin
          SetLength(Sets, Length(Sets) + 1);
          SetLength(Sets[High(Sets)], 1);
          Sets[High(Sets)][0] := Ni;
        end;
      end;
    finally
      Names.Free;
    end;
    for SetNo := 0 to High(Sets) do
    begin
      SetLength(Group, Length(Sets[SetNo]));
      for K := 0 to High(Sets[SetNo]) do Group[K] := NL.Nets.Vec(Sets[SetNo][K]);
      ScanNetSet(Group);
    end;
  end;

begin
  ClearErcMarkers(Design);
  NL := TNetList.Create;
  try
    NL.FollowImports := False; // ERC checks the root design only, as TinyCAD does
    NL.MakeNet(Design);
    CurrentError := 0;
    if O.UnAssignedRefDes then
      ScanUnassigned;
    if O.MultipleNetNames or O.NonCaseDistinctNetNames then
      ScanNames;
    if O.DupRef then
      ScanDupRef;
    if O.UnConnected then
      ScanMissingParts;
    if Vhdl then
      ScanBusSets
    else
      ScanNets;
    if (CurrentError = 0) and AlwaysShowList then
      Messages.Add(ErcMessage(ERR_NOERROR));
    Result := CurrentError;
  finally
    NL.Free;
  end;
end;

end.
