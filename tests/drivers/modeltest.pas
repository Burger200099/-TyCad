{ Test driver for properties / mass change, links and undo.
    modeltest props                       mass change over mixed objects; prints what happened
    modeltest links <lib>                 rung grid line numbers and linked text, with objects moving
    modeltest undo <in.dsn> <outdir>      a series of edits, then undo and redo back through them }
program modeltest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, UDPoint, UDrawTypes, UGeometry, UResources, UDrawingObjects, USymbols,
  UDesign, ULibrary, UProps, ULinks, UUndo, UEdit;

{ ===========================================================================
  Fmt  (function)
  Parameters:
    V: Double - the number
  Returns:
    String - the text
  Notes:
    Formats a number for the test output.
  =========================================================================== }
function Fmt(V: Double): String; begin Result := FloatToStrF(V, ffGeneral, 12, 0); end;

{ ===========================================================================
  PropLine  (function)
  Parameters:
    const Title: String - label for the line
    Objs: TList - the selected objects
  Returns:
    String - title and property names
  Notes:
    Lists the properties a selection shares, as a line of text.
  =========================================================================== }
function PropLine(const Title: String; Objs: TList): String;
var
  P: TPropDefArray;
  i: Integer;
begin
  P := CommonProps(Objs);
  Result := Title + ':';
  for i := 0 to High(P) do Result := Result + ' ' + P[i].Name;
end;

{ ===========================================================================
  DoProps  (procedure)
  Parameters:  none
  Notes:
    Test mode: builds objects of several kinds, checks which properties mixed selections share,
    does mass changes and saves the result.
  =========================================================================== }
procedure DoProps;
var
  D: TDesignFile;
  S: TDesignSheet;
  T: TDrawText;
  L: TDrawLabel;
  N: TDrawNoteText;
  W: TDrawLine;
  Pg: TDrawPolygon;
  Sq: TDrawSquare;
  Lad: TDrawLadder;
  Objs: TList;
  Mixed: Boolean;
  V: String;
  Cnt, i: Integer;
  H: TArcPoint;
begin
  D := TDesignFile.Create;
  D.AllowEmptySheets := True;
  S := D.AddSheet;
  T := TDrawText.CreateKind(S.Options, xTextEx2); T.Str := 'hello'; S.Drawing.Add(T);
  L := TDrawLabel.Create(S.Options); L.Str := 'NET1'; S.Drawing.Add(L);
  N := TDrawNoteText.Create(S.Options); N.Str := 'note'; S.Drawing.Add(N);
  W := TDrawLine.CreateKind(S.Options, xWire); W.PointA := DPoint(0, 0); W.PointB := DPoint(100, 0); S.Drawing.Add(W);
  Pg := TDrawPolygon.Create(S.Options);
  SetLength(Pg.Handles, 3);
  for i := 0 to 2 do begin H.X := i * 10; H.Y := (i mod 2) * 10; H.Arc := 0; H.Control := DPointInvalid; H.FlattenedSegment := 0; Pg.Handles[i] := H; end;
  Pg.CalcBoundingRect; S.Drawing.Add(Pg);
  Sq := TDrawSquare.CreateKind(S.Options, xSquareEx3); Sq.PointA := DPoint(0, 0); Sq.PointB := DPoint(50, 50); S.Drawing.Add(Sq);
  Lad := TDrawLadder.Create(S.Options); Lad.PointA := DPoint(0, 0); Lad.PointB := DPoint(100, 400); S.Drawing.Add(Lad);

  Objs := TList.Create;
  try
    { which properties do mixed selections share? }
    Objs.Add(T); Objs.Add(L); WriteLn(PropLine('text+label', Objs));
    Objs.Clear; Objs.Add(T); Objs.Add(Lad); WriteLn(PropLine('text+ladder', Objs));
    Objs.Clear; Objs.Add(W); Objs.Add(Pg); Objs.Add(Sq); WriteLn(PropLine('wire+polygon+rect', Objs));
    Objs.Clear; Objs.Add(T); Objs.Add(W); WriteLn(PropLine('text+wire', Objs));
    { mass change of the font size over text, label, note and ladder }
    Objs.Clear; Objs.Add(T); Objs.Add(L); Objs.Add(N); Objs.Add(Lad);
    V := CommonValue(Objs, 'font.height', Mixed); WriteLn('before font.height=', V, ' mixed=', Ord(Mixed));
    Cnt := SetPropAll(Objs, 'font.height', '20'); V := CommonValue(Objs, 'font.height', Mixed);
    WriteLn('changed ', Cnt, ' font.height now=', V, ' mixed=', Ord(Mixed));
    Cnt := SetPropAll(Objs, 'font.bold', '1'); WriteLn('bold: ', Cnt, ' ', CommonValue(Objs, 'font.bold', Mixed), ' mixed=', Ord(Mixed));
    Cnt := SetPropAll(Objs, 'font.italic', '1'); WriteLn('italic: ', Cnt, ' ', CommonValue(Objs, 'font.italic', Mixed));
    Cnt := SetPropAll(Objs, 'font.face', 'Courier New'); WriteLn('face: ', Cnt, ' ', CommonValue(Objs, 'font.face', Mixed));
    Cnt := SetPropAll(Objs, 'font.color', 'FF0000'); WriteLn('font color: ', Cnt, ' ', CommonValue(Objs, 'font.color', Mixed), ' raw=', IntToHex(T.FontColor, 6), ' ', IntToHex(Lad.FontColor, 6));
    { text objects only: other kinds are skipped }
    Objs.Clear; Objs.Add(T); Objs.Add(W); Objs.Add(L);
    Cnt := SetPropAll(Objs, 'text', 'changed'); WriteLn('text on text,wire,label: changed ', Cnt, ' -> ', T.Str, ' / ', L.Str);
    { lines and fills over several kinds }
    Objs.Clear; Objs.Add(W); Objs.Add(Pg); Objs.Add(Sq);
    Cnt := SetPropAll(Objs, 'line.color', '00FF00'); WriteLn('line color: ', Cnt, ' ', CommonValue(Objs, 'line.color', Mixed), ' mixed=', Ord(Mixed));
    Cnt := SetPropAll(Objs, 'line.width', '4'); WriteLn('line width: ', Cnt, ' ', CommonValue(Objs, 'line.width', Mixed));
    Cnt := SetPropAll(Objs, 'line.style', 'Dash'); WriteLn('line style: ', Cnt, ' ', CommonValue(Objs, 'line.style', Mixed), ' wire default style now=', Ord(W.UseDefaultStyle));
    Objs.Clear; Objs.Add(Pg); Objs.Add(Sq);
    Cnt := SetPropAll(Objs, 'fill.type', 'Solid'); WriteLn('fill type: ', Cnt, ' ', CommonValue(Objs, 'fill.type', Mixed));
    Cnt := SetPropAll(Objs, 'fill.color', '0000FF'); WriteLn('fill color: ', Cnt, ' ', CommonValue(Objs, 'fill.color', Mixed));
    { ladder properties }
    Objs.Clear; Objs.Add(Lad);
    SetPropAll(Objs, 'ladder.left', 'N'); SetPropAll(Objs, 'ladder.right', 'M'); SetPropAll(Objs, 'line.width', '5'); SetPropAll(Objs, 'line.color', '123456');
    WriteLn('ladder: ', Lad.LeftWire, ' ', Lad.RightWire, ' width=', Lad.LineWidth, ' color=', IntToHex(Lad.LineColor, 6), ' common=', CommonValue(Objs, 'line.width', Mixed));
    { the old numbering properties are gone }
    WriteLn('old keys: ', Ord(SetProp(Lad, 'ladder.lines', '9')), Ord(SetProp(Lad, 'ladder.start', '9')), Ord(SetProp(Lad, 'ladder.railwidth', '9')));
    { bad input is ignored, not applied }
    SetPropAll(Objs, 'line.width', 'abc'); WriteLn('bad number leaves width=', Lad.LineWidth);
    SetPropAll(Objs, 'line.width', '0'); WriteLn('width 0 becomes ', Lad.LineWidth);
    { the saved file keeps what was set }
    D.AssignIds;
    S.UpdateLayout;
    D.SaveToFile(ParamStr(2));
    WriteLn('saved');
  finally
    Objs.Free;
    D.Free;
  end;
end;

{ ===========================================================================
  DoLinks  (procedure)
  Parameters:
    const LibName: String - a library with at least one symbol
  Notes:
    Test mode: builds ladders and symbols on two sheets, adds linked texts and prints what they
    say as objects move, are renumbered and are deleted.
  =========================================================================== }
procedure DoLinks(const LibName: String);
var
  Lib: TSymbolLibrary;
  D: TDesignFile;
  S1, S2: TDesignSheet;
  G1, G2: TDrawRungGrid;
  Sym: TDesignFileSymbol;
  Id, i, j, k: Integer;
  K1a, K1b, K1c: TDrawMethod;
  X1, X2, X3: TDrawRefText;

  function PlaceRow(Sh: TDesignSheet; Row: Integer; X, Y: Double; const Ref: String): TDrawMethod;
  var
    a, b, kk: Integer;
    Sy: TDesignFileSymbol;
  begin
    kk := 0;
    Result := nil;
    for a := 0 to Lib.SetCount - 1 do
      for b := 0 to Lib.Sets[a].RecordCount - 1 do
      begin
        if kk = Row then
        begin
          Sy := Lib.GetDesignSymbol(Sh, Lib.Sets[a], b);
          Result := TDrawMethod.CreateFromSymbol(Sh.Options, Sh.Options.AddSymbol(Sy), 0);
          Result.PointA := DPoint(X, Y);
          Result.Fields[FIELD_REF].Value := Ref;
          Result.NewRotation;
          Result.Id := D.NextObjectId;
          Sh.Drawing.Add(Result);
          Result.UpdateLayout;
        end;
        Inc(kk);
      end;
  end;

  function XRef(Sh: TDesignSheet; Target: TDrawingObject; Mode: Integer): TDrawRefText;
  begin
    Result := TDrawRefText.Create(Sh.Options);
    Result.TargetId := Target.Id;
    Result.Mode := Mode;
    Result.PointA := DPoint(50, 50);
    Result.Id := D.NextObjectId;
    Sh.Drawing.Add(Result);
  end;

  function MidY(M: TDrawMethod): Double;
  var
    Act: TDPointArray;
    t: Integer;
    Sm: Double;
  begin
    Act := M.ActivePoints;
    Sm := 0;
    for t := 0 to High(Act) do Sm := Sm + Act[t].y;
    Result := Sm / Length(Act);
  end;

begin
  Lib := TSymbolLibrary.Create;
  D := TDesignFile.Create;
  D.AllowEmptySheets := True;
  try
    Lib.Open(LibName);
    S1 := D.AddSheet;
    S2 := D.AddSheet;
    { each sheet has a rung grid: a 20 mm indent on a 297 x 210 mm sheet leaves 100..950 high; sheet 1 has 10 rows (85 high) numbered from 1, sheet 2 has 4 rows (212.5 high) numbered from 20 }
    G1 := TDrawRungGrid.Create(S1.Options); G1.MarginMm := 20; G1.Rows := 10; G1.StartNumber := 1; G1.Id := D.NextObjectId; S1.Drawing.Add(G1);
    G2 := TDrawRungGrid.Create(S2.Options); G2.MarginMm := 20; G2.Rows := 4; G2.StartNumber := 20; G2.Id := D.NextObjectId; S2.Drawing.Add(G2);

    { two parts sharing the reference K1 on lines 3 and 7 of sheet 1; one more on sheet 2 }
    K1a := PlaceRow(S1, 0, 400, 100 + 2.5 * 85 + 10, 'K1');
    K1b := PlaceRow(S1, 0, 400, 100 + 6.5 * 85 + 10, 'K1');
    K1c := PlaceRow(S2, 0, 400, 100 + 1.5 * 212.5 + 10, 'K1');
    WriteLn('mid y of parts: ', Fmt(MidY(K1a)), ' ', Fmt(MidY(K1b)), ' ', Fmt(MidY(K1c)));
    X1 := XRef(S1, K1a, 0);   { the line of K1a }
    X2 := XRef(S1, K1a, 1);   { the other K1 parts }
    X3 := XRef(S2, K1b, 0);   { a line on another sheet }
    UpdateLinks(D);
    WriteLn('line of K1a = [', X1.DisplayText, ']  contacts of K1a = [', X2.DisplayText, ']  from sheet 2, K1b = [', X3.DisplayText, ']');
    { move K1b to line 5: the text follows }
    K1b.Shift(DPoint(0, -2 * 85));
    UpdateLinks(D);
    WriteLn('after moving K1b up two lines: contacts of K1a = [', X2.DisplayText, ']  K1b seen from sheet 2 = [', X3.DisplayText, ']');
    { move K1a out of the grid (into the indent) }
    K1a.Shift(DPoint(-500, 0));
    UpdateLinks(D);
    WriteLn('K1a in the indent: its line = [', X1.DisplayText, ']');
    K1a.Shift(DPoint(500, 0));
    { change the numbering: the displayed numbers follow }
    G1.StartNumber := 101;
    UpdateLinks(D);
    WriteLn('grid renumbered from 101: line of K1a = [', X1.DisplayText, ']');
    { delete the target: the text says so }
    S1.Drawing.Remove(K1a);
    UpdateLinks(D);
    WriteLn('target deleted: [', X1.DisplayText, ']');
    { links survive a save and reload (they are stored by object id) }
    D.SaveToFile(ParamStr(3));
    WriteLn('saved');
  finally
    D.Free;
    Lib.Free;
  end;
  i := 0; j := 0; k := 0; if i + j + k = 1 then ;
  Sym := nil; Id := 0; if (Sym <> nil) or (Id = 1) then ;
end;

{ ===========================================================================
  SaveState  (procedure)
  Parameters:
    D: TDesignFile - the design
    const Path: String - file to write
  Notes:
    Saves the design to a file so a state can be compared later.
  =========================================================================== }
procedure SaveState(D: TDesignFile; const Path: String);
begin
  D.SaveToFile(Path);
end;

{ ===========================================================================
  Ids  (function)
  Parameters:
    Sh: TDesignSheet - the sheet
    From: Integer - first object position
    Count: Integer - how many
  Returns:
    TIntArray - the ids
  Notes:
    The ids of a run of objects on a sheet.
  =========================================================================== }
function Ids(Sh: TDesignSheet; From, Count: Integer): TIntArray;
var
  i: Integer;
begin
  SetLength(Result, 0);
  for i := From to Min(Sh.Drawing.Count - 1, From + Count - 1) do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Sh.Drawing[i].Id;
  end;
end;

{ ===========================================================================
  DoUndo  (procedure)
  Parameters:
    const InName: String - design to edit
    const OutDir: String - folder for the state files
  Notes:
    Test mode: makes four edits (draw, delete, mass change, move) saving each state, then undoes
    and redoes them one at a time saving each state reached.
  =========================================================================== }
procedure DoUndo(const InName, OutDir: String);
var
  D: TDesignFile;
  U: TUndoManager;
  S: TDesignSheet;
  Eng: TWireEngine;
  Dir: String;
  Sel, Back: TIntArray;
  Sheet, n: Integer;
  T: TWireTool;
  Objs: TList;
  i: Integer;
  Ok: Boolean;
begin
  Dir := IncludeTrailingPathDelimiter(OutDir);
  D := TDesignFile.Create;
  D.LoadFromFile(InName);
  D.AllowEmptySheets := True;
  D.AssignIds;
  S := D.Sheets[0];
  U := TUndoManager.Create(D);
  Eng := TWireEngine.Create(D, S);
  SetLength(Sel, 0);
  try
    SaveState(D, Dir + 'state0.dsn');
    { step 1: draw a wire }
    U.Push('draw wire', Sel, 0);
    T := TWireTool.Create(Eng, xWire);
    T.Move(DPoint(100, 100)); T.LButtonDown(DPoint(100, 100)); T.Move(DPoint(300, 100)); T.LButtonDown(DPoint(300, 100)); T.RButtonDown;
    T.Free;
    SaveState(D, Dir + 'state1.dsn');
    { step 2: delete three objects }
    Sel := Ids(S, 0, 3);
    U.Push('delete', Sel, 0);
    for i := 0 to High(Sel) do S.Drawing.Remove(D.FindObject(Sel[i], Sheet));
    SetLength(Sel, 0);
    SaveState(D, Dir + 'state2.dsn');
    { step 3: mass change on everything text-like }
    Objs := TList.Create;
    for i := 0 to S.Drawing.Count - 1 do Objs.Add(S.Drawing[i]);
    U.Push('mass change', Sel, 0);
    SetPropAll(Objs, 'line.width', '4');   // the wires (and any shapes) in the design
    SetPropAll(Objs, 'line.color', 'FF00FF');
    Objs.Free;
    SaveState(D, Dir + 'state3.dsn');
    { step 4: move everything }
    U.Push('move all', Sel, 0);
    for i := 0 to S.Drawing.Count - 1 do S.Drawing[i].Shift(DPoint(50, 25));
    SaveState(D, Dir + 'state4.dsn');
    WriteLn('undo steps: ', U.UndoCount);
    { undo, one at a time, saving each state reached }
    for n := 3 downto 0 do
    begin
      Ok := U.Undo(Sel, 0, Back, Sheet);
      if not Ok then WriteLn('UNDO FAILED at ', n);
      S := D.Sheets[0];
      SaveState(D, Dir + 'undone' + IntToStr(n) + '.dsn');
      WriteLn('undone to state ', n, ' captions left=', U.UndoCount, ' redo=', U.RedoCount, ' selection restored=', Length(Back));
    end;
    WriteLn('can undo now: ', Ord(U.CanUndo), ' can redo: ', Ord(U.CanRedo));
    { redo all of it }
    for n := 1 to 4 do
    begin
      Ok := U.Redo(Sel, 0, Back, Sheet);
      if not Ok then WriteLn('REDO FAILED at ', n);
      SaveState(D, Dir + 'redone' + IntToStr(n) + '.dsn');
    end;
    WriteLn('after redo: can redo=', Ord(U.CanRedo), ' can undo=', Ord(U.CanUndo));
    { a new change clears the redo history }
    U.Undo(Sel, 0, Back, Sheet);
    U.Push('new change', Sel, 0);
    WriteLn('a new change clears redo: ', Ord(not U.CanRedo));
  finally
    Eng.Free;
    U.Free;
    D.Free;
  end;
end;

begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  DefaultSystemCodePage := CP_UTF8;
  if ParamCount < 1 then Halt(2);
  if ParamStr(1) = 'props' then DoProps
  else if ParamStr(1) = 'links' then DoLinks(ParamStr(2))
  else if ParamStr(1) = 'undo' then DoUndo(ParamStr(2), ParamStr(3));
end.
