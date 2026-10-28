{ Test driver for the netlist.
    nettest protel <in.dsn> <out.net>   write the Protel netlist of a design
    nettest dump <in.dsn>               print every net (number, preferred name, pins)
    nettest twice <in.dsn>              build the netlist twice (the second run sees the hints
                                        the first stored) and report whether the numbers are stable
    nettest nodes <in.dsn>              print every node of every net, one per line with tab separated columns (net, label, preferred
                                        label, reference, pin, then P and the pin's name, number and electrical type, or N and three dashes for a node that is not a pin)
                                        then the sheet number (from 1) and, for a node of a placed symbol, the symbol as sheet:number (both from 0, counting placed symbols
                                        in drawing order), or a dash
    nettest flatnodes <in.dsn>          the same with hierarchical symbols not followed (as the design rules check does)
    nettest ercnodes <in.dsn>           the nodes again with everything the design rules check reads of them: E, net, kind (POWER, NOCONNECT, PIN, LABEL, OTHER), the
                                        value of a power or label (for a power also its net name), the node's label, the node's point, the parent's point, the sheet, the
                                        sheet's name, the placed symbol's name and reference, the node's reference, then for a pin its name, number, electrical type,
                                        1 if it is a power pin and its active point; and as "SYM" lines every placed symbol (sheet, name, Ref field text with part letter,
                                        raw Ref field, reference point, parts per package)
    nettest symbols <in.dsn>            print every placed symbol (SYM, sheet, number, name, reference) followed by its pins as the netlist sees them (PIN, number, name,
                                        electrical type), in the symbol's drawing order
    nettest persist <in.dsn> <tmp.dsn>  build, save the design (hints become HINT tags), reload,
                                        build again and report whether the numbers survived }
program nettest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, UDPoint, UDrawTypes, UDrawingObjects, USymbols, UDesign, UNetList;

{ ===========================================================================
  DoProtel  (procedure)
  Parameters:
    const InName: String - the .dsn file
    const OutName: String - the netlist file
  Notes:
    Test mode: writes the design's Protel netlist to a file.
  =========================================================================== }
procedure DoProtel(const InName, OutName: String);
var
  D: TDesignFile;
  N: TNetList;
  FS: TFileStream;
begin
  D := TDesignFile.Create;
  N := TNetList.Create;
  try
    D.LoadFromFile(InName);
    FS := TFileStream.Create(OutName, fmCreate);
    try
      N.WriteProtel(D, FS);
    finally
      FS.Free;
    end;
  finally
    N.Free;
    D.Free;
  end;
end;

{ ===========================================================================
  Esc  (function)
  Parameters:
    const S: String - text
  Returns:
    String - the text on one line
  Notes:
    Line breaks of a message become " / " so that a script's output stays one line a step.
  =========================================================================== }
function Esc(const S: String): String;
begin
  Result := StringReplace(StringReplace(StringReplace(StringReplace(S, '\', '\\', [rfReplaceAll]), #9, '\t', [rfReplaceAll]), #10, '\n', [rfReplaceAll]), #13, '\r', [rfReplaceAll]);
end;

{ ===========================================================================
  SymbolId  (function)
  Parameters:
    D: TDesignFile
    M: TDrawMethod
  Returns:
    String
  Notes:
    Test mode: prints every node of every net in net order, as
    "NODE<TAB>net<TAB>label<TAB>preferred label<TAB>reference<TAB>pin<TAB> P<TAB>pin
    name<TAB>pin number<TAB>electrical type", or N and three dashes in place of the last four
    when the node is not a pin.
  =========================================================================== }
function SymbolId(D: TDesignFile; M: TDrawMethod): String;
var
  i, j, k: Integer;
begin
  Result := '-';
  if M = nil then
    Exit;
  for i := 0 to D.SheetCount - 1 do
  begin
    k := 0;
    for j := 0 to D.Sheets[i].Drawing.Count - 1 do
      if D.Sheets[i].Drawing[j].GetType = xMethodEx3 then
      begin
        if D.Sheets[i].Drawing[j] = M then
          Exit(IntToStr(i) + ':' + IntToStr(k));
        Inc(k);
      end;
  end;
end;

{ ===========================================================================
  DoSymbols  (procedure)
  Parameters:
    const InName: String - text
  Notes:
    Test mode "symbols": loads every named symbol of a library as a design symbol and places
    them all in one design, which it saves.
  =========================================================================== }
procedure DoSymbols(const InName: String);
var
  D: TDesignFile;
  i, j, k, q: Integer;
  Obj: TDrawingObject;
  M: TDrawMethod;
  Tr: TDPoint;
  L: TDrawingList;
begin
  D := TDesignFile.Create;
  try
    D.LoadFromFile(InName);
    for i := 0 to D.SheetCount - 1 do
    begin
      k := 0;
      for j := 0 to D.Sheets[i].Drawing.Count - 1 do
      begin
        Obj := D.Sheets[i].Drawing[j];
        if Obj.GetType <> xMethodEx3 then
          Continue;
        M := Obj as TDrawMethod;
        WriteLn('SYM'#9, i, #9, k, #9, Esc(M.GetName), #9, Esc(M.GetRef));
        M.ExtractSymbol(Tr, L);
        for q := 0 to L.Count - 1 do
          if L[q].GetType = xPinEx then
            WriteLn('PIN'#9, Esc((L[q] as TDrawPin).GetNumber), #9, Esc((L[q] as TDrawPin).GetPinName), #9, (L[q] as TDrawPin).Elec);
        Inc(k);
      end;
    end;
  finally
    D.Free;
  end;
end;

{ ===========================================================================
  DoNodes  (procedure)
  Parameters:
    const InName: String - the .dsn file
    Follow: Boolean = True - flag
  Notes:
    Test mode: prints every node of every net in net order, as NODE, net, label, preferred
    label, reference, pin, then P and the pin's name, number and electrical type (or N and three
    dashes when the node is not a pin), then the sheet number (from 1) and the placed symbol the
    node belongs to as sheet:number (or a dash).
  =========================================================================== }
procedure DoNodes(const InName: String; Follow: Boolean = True);
var
  D: TDesignFile;
  N: TNetList;
  Ni, k: Integer;
  V: TNodeVector;
  P: TDrawPin;
  Tail: String;
begin
  D := TDesignFile.Create;
  N := TNetList.Create;
  try
    D.LoadFromFile(InName);
    N.FollowImports := Follow;
    N.MakeNet(D);
    if N.ImportErrors <> '' then
      Write('IMPORTERRORS'#9, Esc(N.ImportErrors), #10);
    for Ni := 0 to N.Nets.Count - 1 do
    begin
      V := N.Nets.Vec(Ni);
      for k := 0 to High(V) do
      begin
        if (V[k].Parent <> nil) and (V[k].Parent.GetType = xPinEx) then
        begin
          P := V[k].Parent as TDrawPin;
          Tail := 'P'#9 + Esc(P.GetPinName) + #9 + Esc(P.GetNumber) + #9 + IntToStr(P.Elec);
        end
        else
          Tail := 'N'#9'-'#9'-'#9'-';
        WriteLn('NODE'#9, V[k].NetList, #9, Esc(NodeLabel(V[k])), #9, Esc(NodePreferredLabel(V[k])), #9, Esc(V[k].Reference), #9, Esc(V[k].Pin), #9, Tail, #9, V[k].Sheet, #9, SymbolId(D, V[k].Method));
      end;
    end;
  finally
    N.Free;
    D.Free;
  end;
end;

{ ===========================================================================
  Num  (function)
  Parameters:
    X: Double - number
  Returns:
    String - the number with all its digits, for a program that reads it back
  Notes:
    Test mode helper.
  =========================================================================== }
function Num(X: Double): String;
begin
  Result := FloatToStrF(X, ffExponent, 17, 3, DefaultFormatSettings);
end;

{ ===========================================================================
  DoErcNodes  (procedure)
  Parameters:
    const InName: String - the .dsn file
  Notes:
    Test mode: prints the nodes with the details the design rules check reads, and the placed
    symbols.
  =========================================================================== }
procedure DoErcNodes(const InName: String);
var
  D: TDesignFile;
  N: TNetList;
  Ni, k, i, j: Integer;
  V: TNodeVector;
  P: TDrawPin;
  Kind, Val, Power, Tail, MName, MRef: String;
  Ac, PA: TDPoint;
  M: TDrawMethod;
begin
  D := TDesignFile.Create;
  N := TNetList.Create;
  try
    D.LoadFromFile(InName);
    N.MakeNet(D);
    for Ni := 0 to N.Nets.Count - 1 do
    begin
      V := N.Nets.Vec(Ni);
      for k := 0 to High(V) do
      begin
        Kind := 'NONE'; Val := ''; Power := ''; Tail := '-'#9'-'#9'-'#9'0'#9'0'#9'0';
        if V[k].Parent <> nil then
        begin
          Kind := 'OTHER';
          case V[k].Parent.GetType of
            xPower:
              begin
                Kind := 'POWER';
                Val := (V[k].Parent as TDrawPower).GetValue;
                Power := TNetList.GetPowerLabel(V[k].Parent as TDrawPower);
              end;
            xNoConnect: Kind := 'NOCONNECT';
            xLabelEx2:
              begin
                Kind := 'LABEL';
                Val := (V[k].Parent as TDrawLabel).GetValue;
              end;
            xPin, xPinEx:
              begin
                Kind := 'PIN';
                P := V[k].Parent as TDrawPin;
                Ac := P.GetActivePoint(V[k].Method);
                Tail := Esc(P.GetPinName) + #9 + Esc(P.GetNumber) + #9 + IntToStr(P.Elec) + #9 + IntToStr(Ord(P.IsPower)) + #9 + Num(Ac.x) + #9 + Num(Ac.y);
              end;
          end;
        end;
        PA := DPoint(0, 0);
        if V[k].Parent <> nil then
          PA := V[k].Parent.PointA;
        MName := ''; MRef := '';
        if V[k].Method <> nil then begin MName := V[k].Method.GetName; MRef := V[k].Method.GetRef; end;
        WriteLn('E'#9, V[k].NetList, #9, Kind, #9, Esc(Val), #9, Esc(Power), #9, Esc(NodeLabel(V[k])), #9, Num(V[k].A.x), #9, Num(V[k].A.y), #9,
          Num(PA.x), #9, Num(PA.y), #9, V[k].Sheet, #9,
          Esc(D.Sheets[V[k].Sheet - 1].SheetName), #9, Esc(MName), #9, Esc(MRef), #9, Esc(V[k].Reference), #9, Tail);
      end;
    end;
    for i := 0 to D.SheetCount - 1 do
      for j := 0 to D.Sheets[i].Drawing.Count - 1 do
        if D.Sheets[i].Drawing[j].GetType = xMethodEx3 then
        begin
          M := D.Sheets[i].Drawing[j] as TDrawMethod;
          WriteLn('SYM'#9, i + 1, #9, Esc(M.GetName), #9, Esc(M.GetField(0)), #9, Esc(M.GetRef), #9, Num(M.PointA.x), #9, Num(M.PointA.y), #9, M.GetSymbolData.PartsPerPackage);
        end;
  finally
    N.Free;
    D.Free;
  end;
end;

{ ===========================================================================
  DoDump  (procedure)
  Parameters:
    const InName: String - the .dsn file
  Notes:
    Test mode: prints every net with its number, name and pins.
  =========================================================================== }
procedure DoDump(const InName: String);
var
  D: TDesignFile;
  N: TNetList;
begin
  D := TDesignFile.Create;
  N := TNetList.Create;
  try
    D.LoadFromFile(InName);
    N.MakeNet(D);
    Write(N.DumpText);
  finally
    N.Free;
    D.Free;
  end;
end;

{ ===========================================================================
  DoTwice  (procedure)
  Parameters:
    const InName: String - the .dsn file
  Notes:
    Test mode: builds the netlist twice and reports whether the numbering stays the same (it
    reads the hints the first run stored).
  =========================================================================== }
procedure DoTwice(const InName: String);
var
  D: TDesignFile;
  N1, N2: TNetList;
  A, B: String;
begin
  D := TDesignFile.Create;
  N1 := TNetList.Create;
  N2 := TNetList.Create;
  try
    D.LoadFromFile(InName);
    N1.MakeNet(D);
    A := N1.DumpText;
    N2.MakeNet(D);
    B := N2.DumpText;
    if A = B then
      WriteLn('stable')
    else
      WriteLn('CHANGED');
  finally
    N2.Free;
    N1.Free;
    D.Free;
  end;
end;

{ ===========================================================================
  DoPersist  (procedure)
  Parameters:
    const InName: String - the .dsn file
    const TmpName: String - temporary file to save to
  Notes:
    Test mode: builds the netlist, saves the design, reloads it and builds again, reporting
    whether the numbering survived.
  =========================================================================== }
procedure DoPersist(const InName, TmpName: String);
var
  D1, D2: TDesignFile;
  N1, N2: TNetList;
  A, B: String;
begin
  D1 := TDesignFile.Create;
  D2 := TDesignFile.Create;
  N1 := TNetList.Create;
  N2 := TNetList.Create;
  try
    D1.LoadFromFile(InName);
    N1.MakeNet(D1);
    A := N1.DumpText;
    D1.SaveToFile(TmpName);
    D2.LoadFromFile(TmpName);
    N2.MakeNet(D2);
    B := N2.DumpText;
    if A = B then
      WriteLn('persisted')
    else
      WriteLn('LOST');
  finally
    N2.Free; N1.Free; D2.Free; D1.Free;
  end;
end;

begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultSystemCodePage := CP_UTF8;
  LegacyPartExtents := GetEnvironmentVariable('TC_LEGACY_PARTS') = '1';
  if ParamCount < 2 then begin WriteLn('usage: see header'); Halt(2); end;
  if ParamStr(1) = 'protel' then
    DoProtel(ParamStr(2), ParamStr(3))
  else if ParamStr(1) = 'dump' then
    DoDump(ParamStr(2))
  else if ParamStr(1) = 'nodes' then
    DoNodes(ParamStr(2))
  else if ParamStr(1) = 'flatnodes' then
    DoNodes(ParamStr(2), False)
  else if ParamStr(1) = 'ercnodes' then
    DoErcNodes(ParamStr(2))
  else if ParamStr(1) = 'symbols' then
    DoSymbols(ParamStr(2))
  else if ParamStr(1) = 'twice' then
    DoTwice(ParamStr(2))
  else if ParamStr(1) = 'persist' then
    DoPersist(ParamStr(2), ParamStr(3));
end.
