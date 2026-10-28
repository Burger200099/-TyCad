{ Test driver for the editing engine. Commands on stdin:
    POLY x0 y0 x1 y1 ...     draw a wire through the points (click, then move + click for each next, right-click)
    LINE x0 y0 ...           the same with the plain line tool (no snapping to wires, no junctions)
    DRAG x0 y0 x1 y1         press at the first point, drag, release at the second
    DBL  x0 y0 x1 y1 ...     like POLY but ending with a double-click on the last point
    POWER x y                put a power symbol (a connection point) at x y
    SYM <lib> <row> x y rot  place a library symbol
    PINS                     print the connection points of the placed symbols
    JUNC x y                 put a junction object
    OPT autojunction|autosnap 0|1
    DUMP                     print RAW (as stored), W (wires) and J (junctions)
    LOAD <dsn>               replace the world by a design from a file
    SELSYM k                 select the k-th placed symbol (0-based)
    SELIDX i j ...           select objects by their position in the drawing
    DRAGBY n dx dy           drag the selection n times by (dx, dy), wires following
    MOVEBY n dx dy           move the selection n times without dragging wires
    FINISH                   end the drag (merge, clean, junctions)
    NETS                     print the nets, one line each, as Ref-Pin lists
    SELPINS                  print the visible pins of the selected symbol: SELPIN ref number x y
    ALLPINS                  print every visible pin of every symbol: ALLPIN ref number x y
    STRIP                    delete net labels and power symbols (they connect by name, not by wire)
    COUNTSYM                 print how many symbols are placed
    CLEAR }
program edittest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, UDPoint, UDrawTypes, UGeometry, UDrawingObjects, USymbols, UDesign, ULibrary,
  UEdit, UNetList;

var
  D: TDesignFile;
  S: TDesignSheet;
  Eng: TWireEngine;
  Tok: array of String;
  Sel: TList;

{ ===========================================================================
  FV  (function)
  Parameters:
    k: Integer - token position
  Returns:
    Double - the number
  Notes:
    Reads token k of the command as a number.
  =========================================================================== }
function FV(k: Integer): Double; begin Result := StrToFloat(Tok[k]); end;

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
  Split  (procedure)
  Parameters:
    const Line: String - the line
  Notes:
    Splits a command line into tokens.
  =========================================================================== }
procedure Split(const Line: String);
var
  Sl: TStringList;
  k: Integer;
begin
  Sl := TStringList.Create;
  try
    Sl.Delimiter := ' '; Sl.StrictDelimiter := True; Sl.DelimitedText := Trim(Line);
    SetLength(Tok, Sl.Count);
    for k := 0 to Sl.Count - 1 do Tok[k] := Sl[k];
  finally
    Sl.Free;
  end;
end;

{ ===========================================================================
  NewWorld  (procedure)
  Parameters:  none
  Notes:
    Starts a fresh design, sheet and wire engine for the next test scenario.
  =========================================================================== }
procedure NewWorld;
begin
  Eng.Free;
  D.Free;
  D := TDesignFile.Create;
  D.AllowEmptySheets := True;
  S := D.AddSheet;
  Eng := TWireEngine.Create(D, S);
  Eng.RecordRaw := True;
end;

{ ===========================================================================
  DoPoly  (procedure)
  Parameters:
    Kind: TObjType - xWire or xLineEx2
    Dbl: Boolean - True to finish with a double click
  Notes:
    Draws a wire (or line) through the given points with the real tool: click, then move and
    click for each next point, then finish (right click or double click).
  =========================================================================== }
procedure DoPoly(Kind: TObjType; Dbl: Boolean);
var
  T: TWireTool;
  k, n: Integer;
  P: TDPoint;
begin
  n := (Length(Tok) - 1) div 2;
  if n < 2 then Exit;
  T := TWireTool.Create(Eng, Kind);
  try
    T.Move(DPoint(FV(1), FV(2)));
    T.LButtonDown(DPoint(FV(1), FV(2)));
    for k := 1 to n - 1 do
    begin
      P := DPoint(FV(1 + 2 * k), FV(2 + 2 * k));
      T.Move(P);
      if Dbl and (k = n - 1) then T.DblLButtonDown(P) else T.LButtonDown(P);
    end;
    if not Dbl then T.RButtonDown;
  finally
    T.Free;
  end;
end;

{ ===========================================================================
  DoDrag  (procedure)
  Parameters:  none
  Notes:
    Draws a wire by press, drag and release.
  =========================================================================== }
procedure DoDrag;
var
  T: TWireTool;
begin
  T := TWireTool.Create(Eng, xWire);
  try
    T.Move(DPoint(FV(1), FV(2)));
    T.LButtonDown(DPoint(FV(1), FV(2)));
    T.Move(DPoint(FV(3), FV(4)));
    T.LButtonUp(DPoint(FV(3), FV(4)));
  finally
    T.Free;
  end;
end;

var
  Libs: array of TSymbolLibrary;

{ ===========================================================================
  DoSym  (procedure)
  Parameters:  none
  Notes:
    Places a library symbol (given library, row, position and rotation) on the test sheet.
  =========================================================================== }
procedure DoSym;
var
  L: TSymbolLibrary;
  Sym: TDesignFileSymbol;
  Row, i, j, K, Id: Integer;
  M: TDrawMethod;
begin
  L := TSymbolLibrary.Create;
  L.Open(Tok[1]);
  SetLength(Libs, Length(Libs) + 1);
  Libs[High(Libs)] := L;
  Row := StrToInt(Tok[2]);
  K := 0;
  for i := 0 to L.SetCount - 1 do
    for j := 0 to L.Sets[i].RecordCount - 1 do
    begin
      if K = Row then
      begin
        Sym := L.GetDesignSymbol(S, L.Sets[i], j);
        Id := S.Options.AddSymbol(Sym);
        M := TDrawMethod.CreateFromSymbol(S.Options, Id, StrToInt(Tok[5]));
        M.PointA := DPoint(FV(3), FV(4));
        M.NewRotation;
        Eng.AddObject(M);
        M.UpdateLayout;
        Exit;
      end;
      Inc(K);
    end;
end;

{ ===========================================================================
  DoPins  (procedure)
  Parameters:  none
  Notes:
    Prints the connection points of every placed symbol.
  =========================================================================== }
procedure DoPins;
var
  i, k: Integer;
  Act: TPointList;
begin
  for i := 0 to S.Drawing.Count - 1 do
    if S.Drawing[i] is TDrawMethod then
    begin
      Act := ActivePointsOf(S.Drawing[i]);
      for k := 0 to High(Act) do WriteLn('PIN ', Fmt(Act[k].x), ' ', Fmt(Act[k].y));
    end;
end;

{ ===========================================================================
  DoDump  (procedure)
  Parameters:  none
  Notes:
    Prints the segments as the tool stored them (RAW), the wires and junctions that resulted,
    then END.
  =========================================================================== }
procedure DoDump;
var
  i: Integer;
  O: TDrawingObject;
begin
  for i := 0 to High(Eng.RawA) do
    WriteLn('RAW ', Fmt(Eng.RawA[i].x), ' ', Fmt(Eng.RawA[i].y), ' ', Fmt(Eng.RawB[i].x), ' ', Fmt(Eng.RawB[i].y));
  for i := 0 to S.Drawing.Count - 1 do
  begin
    O := S.Drawing[i];
    if O.GetType = xWire then WriteLn('W ', Fmt(O.PointA.x), ' ', Fmt(O.PointA.y), ' ', Fmt(O.PointB.x), ' ', Fmt(O.PointB.y))
    else if O.GetType = xLineEx2 then WriteLn('L ', Fmt(O.PointA.x), ' ', Fmt(O.PointA.y), ' ', Fmt(O.PointB.x), ' ', Fmt(O.PointB.y))
    else if O.GetType = xJunction then WriteLn('J ', Fmt(O.PointA.x), ' ', Fmt(O.PointA.y));
  end;
  WriteLn('END');
end;

{ ===========================================================================
  DoLoad  (procedure)
  Parameters:  none
  Notes:
    Replaces the test world with a design from a file.
  =========================================================================== }
procedure DoLoad;
begin
  Eng.Free;
  D.Free;
  D := TDesignFile.Create;
  D.AllowEmptySheets := True;
  D.LoadFromFile(Tok[1]);
  D.AssignIds;
  S := D.Sheets[0];
  S.UpdateLayout;
  Eng := TWireEngine.Create(D, S);
  Sel.Clear;
end;

{ ===========================================================================
  DoSelSym  (procedure)
  Parameters:  none
  Notes:
    Selects the k-th placed symbol of the sheet.
  =========================================================================== }
procedure DoSelSym;
var
  i, k: Integer;
begin
  Sel.Clear;
  k := 0;
  for i := 0 to S.Drawing.Count - 1 do
    if S.Drawing[i] is TDrawMethod then
    begin
      if k = StrToInt(Tok[1]) then Sel.Add(S.Drawing[i]);
      Inc(k);
    end;
end;

{ ===========================================================================
  DoSelIdx  (procedure)
  Parameters:  none
  Notes:
    Selects objects by their position in the drawing.
  =========================================================================== }
procedure DoSelIdx;
var
  k: Integer;
begin
  Sel.Clear;
  for k := 1 to High(Tok) do
    if StrToInt(Tok[k]) < S.Drawing.Count then Sel.Add(S.Drawing[StrToInt(Tok[k])]);
end;

{ ===========================================================================
  DoDragBy  (procedure)
  Parameters:
    Plain: Boolean - True to move without stretching wires
  Notes:
    Drags (or, when Plain, only moves) the selection by a step, repeated n times, as a click on
    its first object would.
  =========================================================================== }
procedure DoDragBy(Plain: Boolean);
var
  k, n: Integer;
  A: TDPoint;
begin
  if Sel.Count = 0 then Exit;
  Eng.Selected.Clear;
  for k := 0 to Sel.Count - 1 do Eng.Selected.Add(Sel[k]);
  A := TDrawingObject(Sel[0]).PointA;
  Eng.BeginDrag(A, A);   // a click on the first object
  n := StrToInt(Tok[1]);
  for k := 1 to n do
    if Plain then Eng.MoveBy(DPoint(FV(2), FV(3))) else Eng.DragBy(DPoint(FV(2), FV(3)));
end;

{ ===========================================================================
  DoSelPins  (procedure)
  Parameters:  none
  Notes:
    Prints the visible pins of the selected symbol with their reference, number and position on
    the sheet.
  =========================================================================== }
procedure DoSelPins;
var
  M: TDrawMethod;
  Tr: TDPoint;
  L: TDrawingList;
  i: Integer;
  Pn: TDrawPin;
  A: TDPoint;
begin
  if (Sel.Count = 0) or not (TObject(Sel[0]) is TDrawMethod) then Exit;
  M := TObject(Sel[0]) as TDrawMethod;
  M.ExtractSymbol(Tr, L);
  for i := 0 to L.Count - 1 do
    if (L[i] is TDrawPin) and (not (L[i] as TDrawPin).IsInvisible) then
    begin
      Pn := L[i] as TDrawPin;
      A := Pn.GetActivePoint(M);
      WriteLn('SELPIN ', M.GetRef, ' ', Pn.Number, ' ', Fmt(A.x), ' ', Fmt(A.y));
    end;
end;

{ ===========================================================================
  DoAllPins  (procedure)
  Parameters:  none
  Notes:
    Prints every visible pin of every placed symbol with its reference, number and position.
  =========================================================================== }
procedure DoAllPins;
var
  i, j: Integer;
  M: TDrawMethod;
  Tr: TDPoint;
  L: TDrawingList;
  Pn: TDrawPin;
  A: TDPoint;
begin
  for i := 0 to S.Drawing.Count - 1 do
    if S.Drawing[i] is TDrawMethod then
    begin
      M := S.Drawing[i] as TDrawMethod;
      M.ExtractSymbol(Tr, L);
      for j := 0 to L.Count - 1 do
        if (L[j] is TDrawPin) and (not (L[j] as TDrawPin).IsInvisible) then
        begin
          Pn := L[j] as TDrawPin;
          A := Pn.GetActivePoint(M);
          WriteLn('ALLPIN ', M.GetRef, ' ', Pn.Number, ' ', Fmt(A.x), ' ', Fmt(A.y));
        end;
    end;
end;

{ ===========================================================================
  DoStrip  (procedure)
  Parameters:  none
  Notes:
    Deletes net labels and power symbols, which connect by name, so connectivity depends on
    wires, junctions and pins only.
  =========================================================================== }
procedure DoStrip;
var
  i: Integer;
begin
  for i := S.Drawing.Count - 1 downto 0 do
    if (S.Drawing[i] is TDrawLabel) or (S.Drawing[i] is TDrawPower) then S.Drawing.Remove(S.Drawing[i]);
end;

{ ===========================================================================
  DoCountSym  (procedure)
  Parameters:  none
  Notes:
    Prints how many symbols are placed on the sheet.
  =========================================================================== }
procedure DoCountSym;
var
  i, k: Integer;
begin
  k := 0;
  for i := 0 to S.Drawing.Count - 1 do
    if S.Drawing[i] is TDrawMethod then Inc(k);
  WriteLn('COUNTSYM ', k);
end;

{ ===========================================================================
  DoNets  (procedure)
  Parameters:  none
  Notes:
    Builds the netlist and prints one line per net.
  =========================================================================== }
procedure DoNets;
var
  N: TNetList;
begin
  N := TNetList.Create;
  try
    N.MakeNet(D);
    Write(N.DumpText);
    WriteLn('ENDNETS');
  finally
    N.Free;
  end;
end;

var
  Line: String;
  P: TDrawPower;
  J: TDrawJunction;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  DefaultSystemCodePage := CP_UTF8;
  Sel := TList.Create;
  NewWorld;
  while not Eof(Input) do
  begin
    ReadLn(Line);
    if Trim(Line) = '' then Continue;
    Split(Line);
    if Tok[0] = 'POLY' then DoPoly(xWire, False)
    else if Tok[0] = 'LINE' then DoPoly(xLineEx2, False)
    else if Tok[0] = 'DBL' then DoPoly(xWire, True)
    else if Tok[0] = 'DRAG' then DoDrag
    else if Tok[0] = 'POWER' then begin P := TDrawPower.Create(S.Options); P.PointA := DPoint(FV(1), FV(2)); P.PointB := P.PointA; Eng.AddObject(P); end
    else if Tok[0] = 'JUNC' then begin J := TDrawJunction.Create(S.Options); J.PointA := DPoint(FV(1), FV(2)); J.PointB := J.PointA; Eng.AddObject(J); end
    else if Tok[0] = 'SYM' then DoSym
    else if Tok[0] = 'PINS' then DoPins
    else if Tok[0] = 'OPT' then begin if Tok[1] = 'autojunction' then S.Options.AutoJunction := Tok[2] = '1' else if Tok[1] = 'autosnap' then S.Options.AutoSnap := Tok[2] = '1'; end
    else if Tok[0] = 'DUMP' then DoDump
    else if Tok[0] = 'LOAD' then DoLoad
    else if Tok[0] = 'SELSYM' then DoSelSym
    else if Tok[0] = 'SELIDX' then DoSelIdx
    else if Tok[0] = 'DRAGBY' then DoDragBy(False)
    else if Tok[0] = 'MOVEBY' then DoDragBy(True)
    else if Tok[0] = 'FINISH' then Eng.FinishDrag
    else if Tok[0] = 'NETS' then DoNets
    else if Tok[0] = 'SELPINS' then DoSelPins
    else if Tok[0] = 'ALLPINS' then DoAllPins
    else if Tok[0] = 'STRIP' then DoStrip
    else if Tok[0] = 'COUNTSYM' then DoCountSym
    else if Tok[0] = 'CLEAR' then NewWorld
    else WriteLn('? ', Tok[0]);
  end;
end.
