{ Test driver for the data model.
    designtest rt <in.dsn> <out.dsn>   load a design and write it back
    designtest stats <in.dsn>          print sheet / object / resource counts
    designtest geom <in.dsn>           UpdateLayout, then probe every object (and symbol object)
    designtest placed <in.dsn> [grid [snap]]
                                       check every placed symbol (draw path, rotation, hit, box, replace)
    designtest fields <in.dsn>         recompute each placed symbol's field label positions (NewRotation)
                                       and compare with the saved ones
    designtest refs <in.dsn> [empty [grid [snap]]]
                                       recompute every saved REF_POINT from scratch and compare
                                       (empty = 1: an empty string measures (0, height);
                                        grid / snap override the sheet's grid size and snap switch) }
program designtest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, UDPoint, UDrawTypes, UDrawingObjects, USymbols, UDesign, UXMLException,
  UGeomProbe, UGeometry, UPlacedProbe;

{ ===========================================================================
  DoStats  (procedure)
  Parameters:
    const FileName: String - the .dsn file
  Notes:
    Test mode: loads a design and prints counts of objects by type and of resources.
  =========================================================================== }
procedure DoStats(const FileName: String);
var
  D: TDesignFile;
  i, j: Integer;
  S: TDesignSheet;
begin
  D := TDesignFile.Create;
  try
    D.LoadFromFile(FileName);
    WriteLn('sheets ', D.SheetCount);
    for i := 0 to D.SheetCount - 1 do
    begin
      S := D.Sheets[i];
      WriteLn('sheet ', i, ' name=[', S.SheetName, '] objects=', S.Drawing.Count,
              ' fonts=', S.Options.Fonts.Count, ' styles=', S.Options.Styles.Count,
              ' fills=', S.Options.Fills.Count, ' symbols=', S.Options.Symbols.Count);
      for j := 0 to Min(2, S.Drawing.Count - 1) do
        WriteLn('   ', S.Drawing[j].ClassName);
    end;
  finally
    D.Free;
  end;
end;

{ ===========================================================================
  DoGeom  (procedure)
  Parameters:
    const FileName: String - the .dsn file
  Notes:
    Test mode "geom": updates layout, then probes the geometry of every object (including the
    objects inside symbols) and prints the totals.
  =========================================================================== }
procedure DoGeom(const FileName: String);
var
  D: TDesignFile;
  i, j, k, m: Integer;
  S: TDesignSheet;
  Stats: TProbeStats;
  Sym: TDesignFileSymbol;
begin
  Stats.Tested := 0; Stats.Failed := 0; Stats.BadBox := 0; Stats.Skipped := 0; Stats.OutsideBox := 0;
  D := TDesignFile.Create;
  try
    D.LoadFromFile(FileName);
    for i := 0 to D.SheetCount - 1 do
    begin
      S := D.Sheets[i];
      S.UpdateLayout;
      for j := 0 to S.Drawing.Count - 1 do
        ProbeObject(S.Drawing[j], Stats, ExtractFileName(FileName));
      { the objects inside each symbol definition }
      for k := 0 to S.Options.Symbols.Count - 1 do
      begin
        Sym := (S.Options.Symbols.Item(k) as TSymbolResource).Symbol;
        if Sym = nil then Continue;
        for m := 0 to Sym.MethodCount - 1 do
          for j := 0 to Sym.Methods[m].Count - 1 do
          begin
            Sym.Methods[m][j].UpdateLayout;
            ProbeObject(Sym.Methods[m][j], Stats, ExtractFileName(FileName) + ':' + Sym.Name);
          end;
      end;
    end;
    WriteLn('geom ', Stats.Tested, ' ', Stats.Failed, ' ', Stats.BadBox, ' ', Stats.Skipped, ' ', Stats.OutsideBox);
  finally
    D.Free;
  end;
end;

{ ===========================================================================
  DoRefs  (procedure)
  Parameters:
    const FileName: String - the .dsn file
    EmptyHeight: Boolean - measure empty text as height 0
    GridOverride: Double - grid to use instead of the file's (0 = the file's)
    SnapOverride: Integer - snap flag to use instead of the file's (-1 = the file's)
  Notes:
    Test mode: recomputes every reference point TinyCAD saved in a design from scratch and
    prints saved versus computed, so the program's result can be compared with the C++
    program's.
  =========================================================================== }
procedure DoRefs(const FileName: String; EmptyHeight: Boolean; GridOverride: Double; SnapOverride: Integer);
var
  D: TDesignFile;
  i, k, e, Part: Integer;
  S: TDesignSheet;
  Sym: TDesignFileSymbol;
  Power: Boolean;
  Ref, Calc: TDPoint;
begin
  D := TDesignFile.Create;
  try
    D.LoadFromFile(FileName);
    for i := 0 to D.SheetCount - 1 do
    begin
      S := D.Sheets[i];
      if S.Options.Metrics is TApproxTextMetrics then
        (S.Options.Metrics as TApproxTextMetrics).EmptyHasHeight := EmptyHeight;
      if GridOverride > 0 then S.Options.Snap.Grid := GridOverride;
      if SnapOverride >= 0 then S.Options.Snap.GridSnap := SnapOverride;
      for k := 0 to S.Options.Symbols.Count - 1 do
      begin
        Sym := (S.Options.Symbols.Item(k) as TSymbolResource).Symbol;
        if Sym = nil then Continue;
        for e := 0 to Sym.CachedRefCount - 1 do
        begin
          Sym.CachedRef(e, Part, Power, Ref);
          Calc := Sym.ComputeRefPoint(Part, Power);
          WriteLn('REF ', Sym.Name, '|', Part, '|', Ord(Power), '|', Ref.x:0:5, '|', Ref.y:0:5, '|', Calc.x:0:5, '|', Calc.y:0:5,
                  '|', Ord(Sym.Heterogeneous), '|', Sym.MethodCount);
        end;
      end;
    end;
  finally
    D.Free;
  end;
end;

{ ===========================================================================
  DoPlaced  (procedure)
  Parameters:
    const FileName: String - the .dsn file
    GridOverride: Double - grid to use instead of the file's
    SnapOverride: Integer - snap flag to use instead of the file's
  Notes:
    Test mode: runs the placed-symbol checks (draw path versus netlist path, rotation, hit test,
    box, replace) over every placed symbol of a design and prints the totals.
  =========================================================================== }
procedure DoPlaced(const FileName: String; GridOverride: Double; SnapOverride: Integer);
var
  D: TDesignFile;
  i, j: Integer;
  S: TDesignSheet;
  St: TPlacedStats;
begin
  FillChar(St, SizeOf(St), 0);
  D := TDesignFile.Create;
  try
    D.LoadFromFile(FileName);
    for i := 0 to D.SheetCount - 1 do
    begin
      S := D.Sheets[i];
      if GridOverride > 0 then S.Options.Snap.Grid := GridOverride;
      if SnapOverride >= 0 then S.Options.Snap.GridSnap := SnapOverride;
      S.UpdateLayout;
      for j := 0 to S.Drawing.Count - 1 do
        if S.Drawing[j] is TDrawMethod then
          ProbePlaced(S.Drawing[j] as TDrawMethod, St, ExtractFileName(FileName));
    end;
    WriteLn('placed ', St.Placements, ' ', St.PinPoints, ' ', St.DrawBad, ' ', St.RotateBad, ' ', St.HitBad, ' ', St.BoxBad, ' ', St.ReplaceBad, ' ', St.Inconsistent);
  finally
    D.Free;
  end;
end;

{ ===========================================================================
  DoFields  (procedure)
  Parameters:
    const FileName: String - the .dsn file
  Notes:
    Test mode: recomputes the field label positions of every placed symbol and compares them
    with the saved ones.
  =========================================================================== }
procedure DoFields(const FileName: String);
var
  D: TDesignFile;
  i, j, k: Integer;
  S: TDesignSheet;
  M, Cl: TDrawMethod;
  Same, Total, PlSame, PlTotal: Integer;
  AllSame: Boolean;
begin
  Same := 0; Total := 0; PlSame := 0; PlTotal := 0;
  D := TDesignFile.Create;
  try
    D.LoadFromFile(FileName);
    for i := 0 to D.SheetCount - 1 do
    begin
      S := D.Sheets[i];
      S.UpdateLayout;
      for j := 0 to S.Drawing.Count - 1 do
        if S.Drawing[j] is TDrawMethod then
        begin
          M := S.Drawing[j] as TDrawMethod;
          Cl := M.Clone as TDrawMethod;
          try
            Cl.NewRotation;
            AllSame := True;
            for k := 0 to High(M.Fields) do
            begin
              Inc(Total);
              if (k <= High(Cl.Fields)) and (Abs(Cl.Fields[k].Position.x - M.Fields[k].Position.x) < 1E-3) and
                 (Abs(Cl.Fields[k].Position.y - M.Fields[k].Position.y) < 1E-3) then
                Inc(Same)
              else
                AllSame := False;
            end;
            Inc(PlTotal);
            if AllSame then Inc(PlSame);
          finally
            Cl.Free;
          end;
        end;
    end;
    WriteLn('fields ', PlTotal, ' ', PlSame, ' ', Total, ' ', Same);
  finally
    D.Free;
  end;
end;

{ ===========================================================================
  DoRoundTrip  (procedure)
  Parameters:
    const InName: String - the file to read
    const OutName: String - the file to write
  Notes:
    Test mode: loads a design and writes it again (the round-trip test input).
  =========================================================================== }
procedure DoRoundTrip(const InName, OutName: String);
var
  D: TDesignFile;
begin
  D := TDesignFile.Create;
  try
    try
      D.LoadFromFile(InName);
    except
      on E: EXMLException do
      begin
        WriteLn('LOAD ERROR line ', E.Line, ': ', E.Message);
        Halt(3);
      end;
    end;
    D.VersionComment := 'TinyCAD (Lazarus port)';
    D.SaveToFile(OutName);
    WriteLn('ok sheets=', D.SheetCount);
  finally
    D.Free;
  end;
end;

var
  GridArg: Double;
  SnapArg: Integer;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultSystemCodePage := CP_UTF8;
  if ParamCount < 2 then begin WriteLn('usage: see header'); Halt(2); end;
  if ParamStr(1) = 'rt' then DoRoundTrip(ParamStr(2), ParamStr(3))
  else if ParamStr(1) = 'stats' then DoStats(ParamStr(2))
  else if ParamStr(1) = 'geom' then DoGeom(ParamStr(2))
  else if ParamStr(1) = 'fields' then DoFields(ParamStr(2))
  else if ParamStr(1) = 'placed' then
  begin
    GridArg := 0;
    SnapArg := -1;
    if ParamCount >= 3 then GridArg := StrToFloat(ParamStr(3));
    if ParamCount >= 4 then SnapArg := StrToInt(ParamStr(4));
    DoPlaced(ParamStr(2), GridArg, SnapArg);
  end
  else if ParamStr(1) = 'refs' then
  begin
    GridArg := 0;
    SnapArg := -1;
    if ParamCount >= 4 then GridArg := StrToFloat(ParamStr(4));
    if ParamCount >= 5 then SnapArg := StrToInt(ParamStr(5));
    DoRefs(ParamStr(2), (ParamCount >= 3) and (ParamStr(3) = '1'), GridArg, SnapArg);
  end;
end.
