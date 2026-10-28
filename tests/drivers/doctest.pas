{ Test driver for the document-model additions: object ids, paper sizes, title-block variables,
  revision history, border.
    doctest mkdesign <out.dsn>          build a 3-sheet design that uses all of the new features
    doctest dump <in.dsn>               print every sheet's details, revisions and ids
    doctest expand <in.dsn> <n> <text>  expand $(...) variables in <text> for sheet n (0-based)
    doctest ids <in.dsn> <out.dsn>      assign ids, save, reload and self-check
    doctest paper                       print the paper table and the 11 x 17 border }
program doctest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, UDPoint, UDrawTypes, UGeometry, UDrawingObjects, UDesign, UPaper, UDocVars;

{ ===========================================================================
  Esc  (function)
  Parameters:
    const S: String - the text
  Returns:
    String - the escaped text
  Notes:
    Escapes backslash, line feed and | so values can be printed on one line.
  =========================================================================== }
function Esc(const S: String): String;
begin
  Result := StringReplace(StringReplace(StringReplace(S, '\', '\\', [rfReplaceAll]),
            #10, '\n', [rfReplaceAll]), '|', '\p', [rfReplaceAll]);
end;

{ ===========================================================================
  F2  (function)
  Parameters:
    V: Double - the number
  Returns:
    String - the text
  Notes:
    Formats a number for the test output.
  =========================================================================== }
function F2(V: Double): String;
begin
  Result := FloatToStrF(V, ffGeneral, 12, 0);
end;

{ ===========================================================================
  AddObjects  (procedure)
  Parameters:
    Sh: TDesignSheet - the sheet
    N: Integer - how many wire-and-junction pairs
  Notes:
    Adds a few wires and junctions to a sheet so a test design has content.
  =========================================================================== }
procedure AddObjects(Sh: TDesignSheet; N: Integer);
var
  W: TDrawLine;
  J: TDrawJunction;
  i: Integer;
begin
  for i := 1 to N do
  begin
    W := TDrawLine.CreateKind(Sh.Options, xWire);
    W.PointA := DPoint(100 * i, 100);
    W.PointB := DPoint(100 * i + 50, 100);
    Sh.Drawing.Add(W);
    J := TDrawJunction.Create(Sh.Options);
    J.PointA := DPoint(100 * i + 50, 100);
    J.PointB := J.PointA;
    Sh.Drawing.Add(J);
  end;
end;

{ ===========================================================================
  DoMk  (procedure)
  Parameters:
    const OutName: String - the file to write
  Notes:
    Test mode: builds a three-sheet design that uses every document-model feature (11x17, A4,
    portrait; automatic numbering, border, revision history with multi-line notes) and saves it.
  =========================================================================== }
procedure DoMk(const OutName: String);
var
  D: TDesignFile;
  S: TDesignSheet;
  Pw, Ph: Integer;
begin
  D := TDesignFile.Create;
  try
    { sheet 1: 11 x 17 landscape, auto sheet numbers, border, three revisions }
    S := D.AddSheet;
    S.SheetName := 'Power distribution';
    PaperUnits(PaperIndexByName('ANSI B (Tabloid)'), True, Pw, Ph);
    S.Details.PageWidth := Pw; S.Details.PageHeight := Ph;
    S.Details.Title := 'Panel A <main> & "feeders"';
    S.Details.Author := 'J. Smith'; S.Details.Org := 'Acme Controls'; S.Details.DocNo := 'E-1001';
    S.Details.LastChange := '2026-10-02';
    S.Details.AutoSheets := True;
    S.Details.ShowBorder := True; S.Details.BorderMargin := 40;
    S.Details.AddRevision('A', '2026-01-05', 'JS', 'MK', 'Initial issue');
    S.Details.AddRevision('B', '2026-03-14', 'JS', 'MK', 'Added feeder F4' + #13#10 + 'Moved contactor K2 to rung 12' + #13#10 + 'Fixed "label" & <note>');
    S.Details.AddRevision('C', '2026-06-30', 'RT', '', '');
    AddObjects(S, 2);
    { sheet 2: A4, auto sheet numbers, no history (legacy Revision field) }
    S := D.AddSheet;
    PaperUnits(PaperIndexByName('ISO A4'), True, Pw, Ph);
    S.Details.PageWidth := Pw; S.Details.PageHeight := Ph;
    S.Details.Title := 'Controls'; S.Details.Revision := 'B2'; S.Details.AutoSheets := True;
    AddObjects(S, 1);
    { sheet 3: 11 x 17 portrait, typed sheets text, one revision }
    S := D.AddSheet;
    PaperUnits(PaperIndexByName('ANSI B (Tabloid)'), False, Pw, Ph);
    S.Details.PageWidth := Pw; S.Details.PageHeight := Ph;
    S.Details.Sheets := '3 of 9';
    S.Details.AddRevision('1.0', '2026-09-01', 'AB', 'CD', 'Single line note');
    AddObjects(S, 1);
    D.SaveToFile(OutName);
  finally
    D.Free;
  end;
end;

{ ===========================================================================
  DoDump  (procedure)
  Parameters:
    const InName: String - the .dsn file
  Notes:
    Test mode: prints each sheet's page size, flags, border rectangle and revisions of a design.
  =========================================================================== }
procedure DoDump(const InName: String);
var
  D: TDesignFile;
  i, j: Integer;
  Dt: TDetails;
  R: TDRect;
begin
  D := TDesignFile.Create;
  try
    D.LoadFromFile(InName);
    for i := 0 to D.SheetCount - 1 do
    begin
      Dt := D.Sheets[i].Details;
      R := Dt.BorderRectangle;
      WriteLn('SHEET ', i, '|', Esc(D.Sheets[i].SheetName), '|', Dt.PageWidth, '|', Dt.PageHeight, '|', Ord(Dt.AutoSheets), '|',
              Ord(Dt.ShowBorder), '|', F2(Dt.BorderMargin), '|', Esc(Dt.EffectiveRevision), '|', Esc(Dt.EffectiveRevisionDate), '|',
              Length(Dt.Revisions), '|', Esc(DescribePage(Dt.PageWidth, Dt.PageHeight)), '|', F2(R.Left), ' ', F2(R.Top), ' ', F2(R.Right), ' ', F2(R.Bottom));
      for j := 0 to High(Dt.Revisions) do
        WriteLn('REV ', i, ' ', j, '|', Esc(Dt.Revisions[j].Rev), '|', Esc(Dt.Revisions[j].Date), '|', Esc(Dt.Revisions[j].Author), '|',
                Esc(Dt.Revisions[j].Approved), '|', Esc(Dt.Revisions[j].Notes));
    end;
  finally
    D.Free;
  end;
end;

{ ===========================================================================
  DoExpand  (procedure)
  Parameters:
    const InName: String - the .dsn file
    Idx: Integer - zero-based sheet number
    const Text: String - the text to expand
  Notes:
    Test mode: expands $(...) variables in a text for one sheet and prints the result.
  =========================================================================== }
procedure DoExpand(const InName: String; Idx: Integer; const Text: String);
var
  D: TDesignFile;
begin
  D := TDesignFile.Create;
  try
    D.LoadFromFile(InName);
    WriteLn(Esc(ExpandVariables(D, Idx, Text)));
  finally
    D.Free;
  end;
end;

{ ===========================================================================
  DoIds  (procedure)
  Parameters:
    const InName: String - the file to read
    const OutName: String - where to save
  Notes:
    Test mode: assigns ids to a design, saves it and checks the ids survive a reload and a
    second save, that Clone gives no id and duplicates are repaired; prints a summary.
  =========================================================================== }
procedure DoIds(const InName, OutName: String);
var
  D, D2, D3, D4: TDesignFile;
  C: TMemoryStream;
  i, j, Assigned, Total, Bad: Integer;
  Obj, Found, Cl: TDrawingObject;
  Si: Integer;
  A, B: TMemoryStream;
  Same: Boolean;
  Dups: Integer;
begin
  D := TDesignFile.Create;
  D2 := TDesignFile.Create;
  A := TMemoryStream.Create;
  B := TMemoryStream.Create;
  try
    D.LoadFromFile(InName);
    Total := 0;
    for i := 0 to D.SheetCount - 1 do Inc(Total, D.Sheets[i].Drawing.Count);
    Assigned := D.AssignIds;
    Bad := 0;
    { every object has a unique id, FindObject finds it, Clone does not copy it }
    for i := 0 to D.SheetCount - 1 do
      for j := 0 to D.Sheets[i].Drawing.Count - 1 do
      begin
        Obj := D.Sheets[i].Drawing[j];
        if Obj.Id <= 0 then Inc(Bad);
        Found := D.FindObject(Obj.Id, Si);
        if (Found <> Obj) or (Si <> i) then Inc(Bad);
        Cl := Obj.Clone;
        try
          if Cl.Id <> 0 then Inc(Bad);
        finally
          Cl.Free;
        end;
      end;
    if D.AssignIds <> 0 then Inc(Bad); // a second call assigns nothing
    D.SaveToFile(OutName);
    D.SaveToStream(A);
    { reload: ids are the same object for object }
    D2.LoadFromFile(OutName);
    if D2.SheetCount <> D.SheetCount then Inc(Bad)
    else
      for i := 0 to D.SheetCount - 1 do
      begin
        if D2.Sheets[i].Drawing.Count <> D.Sheets[i].Drawing.Count then begin Inc(Bad); Continue; end;
        for j := 0 to D.Sheets[i].Drawing.Count - 1 do
          if D2.Sheets[i].Drawing[j].Id <> D.Sheets[i].Drawing[j].Id then Inc(Bad);
      end;
    { ids survive a second save/reload cycle too, and the file settles (resource numbers can need a
      second pass, as for any design, but the bytes must not keep changing after that) }
    D2.SaveToStream(B);
    C := TMemoryStream.Create;
    D3 := TDesignFile.Create;
    try
      B.Position := 0;
      D3.LoadFromStream(B);
      for i := 0 to D.SheetCount - 1 do
        for j := 0 to D.Sheets[i].Drawing.Count - 1 do
          if D3.Sheets[i].Drawing[j].Id <> D.Sheets[i].Drawing[j].Id then Inc(Bad);
      D3.SaveToStream(C);
      Same := True;
      D4 := TDesignFile.Create;
      try
        C.Position := 0;
        D4.LoadFromStream(C);
        B.Clear;
        D4.SaveToStream(B);
        Same := (B.Size = C.Size) and CompareMem(B.Memory, C.Memory, C.Size);
      finally
        D4.Free;
      end;
      if not Same then Inc(Bad);
    finally
      D3.Free;
      C.Free;
    end;
    { duplicate ids (as after a paste) are repaired }
    Dups := 0;
    if (D2.SheetCount > 0) and (D2.Sheets[0].Drawing.Count >= 2) then
    begin
      D2.Sheets[0].Drawing[1].Id := D2.Sheets[0].Drawing[0].Id;
      Dups := D2.FixDuplicateIds;
      if (Dups <> 1) or (D2.Sheets[0].Drawing[1].Id = D2.Sheets[0].Drawing[0].Id) then Inc(Bad);
      if D2.FixDuplicateIds <> 0 then Inc(Bad);
    end;
    WriteLn('ids ', Total, ' ', Assigned, ' ', D.MaxObjectId, ' ', Bad);
  finally
    B.Free; A.Free; D2.Free; D.Free;
  end;
end;

{ ===========================================================================
  DoPaper  (procedure)
  Parameters:  none
  Notes:
    Test mode: prints the paper table, the 11 x 17 border and a few matching cases.
  =========================================================================== }
procedure DoPaper;
var
  i, W, H, W2, H2: Integer;
  Land: Boolean;
  R: TDRect;
begin
  for i := 0 to PaperCount - 1 do
  begin
    PaperUnits(i, True, W, H);
    PaperUnits(i, False, W2, H2);
    WriteLn('PAPER ', PaperInfo(i).Name, '|', W, '|', H, '|', W2, '|', H2, '|', MatchPaper(W, H, 0, Land), '|', Ord(Land), '|', MatchPaper(W2, H2, 0, Land), '|', Ord(Land));
  end;
  PaperUnits(PaperIndexByName('ANSI B (Tabloid)'), True, W, H);
  R := BorderRect(W, H, DEFAULT_BORDER_MARGIN);
  WriteLn('BORDER ', W, ' ', H, ' ', F2(R.Left), ' ', F2(R.Top), ' ', F2(R.Right), ' ', F2(R.Bottom));
  WriteLn('MATCH_TOL ', MatchPaper(1430, 1015, 60, Land), ' ', Ord(Land), ' ', MatchPaper(1430, 1015, 10, Land), ' ', MatchPaper(1015, 1430, 60, Land), ' ', Ord(Land));
  WriteLn('DESCRIBE ', DescribePage(1485, 1050), '|', DescribePage(1000, 700), '|', DescribePage(1397, 2159));
end;

begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultSystemCodePage := CP_UTF8;
  DefaultFormatSettings.DecimalSeparator := '.';
  if ParamCount < 1 then begin WriteLn('usage: see header'); Halt(2); end;
  if ParamStr(1) = 'mkdesign' then DoMk(ParamStr(2))
  else if ParamStr(1) = 'dump' then DoDump(ParamStr(2))
  else if ParamStr(1) = 'expand' then DoExpand(ParamStr(2), StrToInt(ParamStr(3)), ParamStr(4))
  else if ParamStr(1) = 'ids' then DoIds(ParamStr(2), ParamStr(3))
  else if ParamStr(1) = 'paper' then DoPaper;
end.
