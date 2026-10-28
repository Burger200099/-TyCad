// SPDX-License-Identifier: LGPL-2.1-or-later
{ Port of TinyCAD's "Generate Symbol References" (Special.cpp: CTinyCadView::OnSpecialAnnotate and the AnnotateSetup class) and of the reference
  painter's two actions (DrawRefPainter.cpp).

  The command takes away and/or gives numbers to the references of the placed symbols (R? becomes R1, R2 ...). The choices are: add or remove
  references; which symbols (all, those without a number yet, or those whose symbol has a given reference prefix such as U?); where the numbers
  start (1, or a value that is typed); and one sheet or all of them. It makes two passes over the sheets. In the first, matching symbols that
  have a number lose it (when "start at" is chosen only those whose number is at least the start value). In the second, if the action is "add",
  each matching symbol is given the next free number, symbols being taken in order of the centre of their box, row by row from the top (the
  y of the centre first, then the x). A package of several parts that are alike in outline is given the next part of the last symbol of its
  kind before it is given a new number (see TDrawMethod.AddReference).

  Differences from TinyCAD:
   - The C++ sorts with std::sort, which does not keep the order of two symbols whose centres are exactly the same; this port keeps their
     order in the drawing.
   - The undo steps: the C++ opens one change set for each sheet, here the whole command is one step (the caller makes it).
   - Placed designs (hierarchical symbols) are numbered with the others, as in TinyCAD, whose Special.cpp treats them like placed symbols: their prefix comes from
     symbol number 0 of the sheet (H?), they count among the numbers already used by symbols of the same prefix, and one whose design gives nothing to draw is
     left alone (and reported). The reference painter works on placed symbols only, as in TinyCAD. The designs they place are not entered: TinyCAD does not either.

  Original: Copyright 1994-2019 Matt Pyne, LGPL 2.1+. This port keeps that licence. }
unit UAnnotate;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, UDPoint, UDrawTypes, UDrawingObjects, UDesign;

type
  TAnnotateAction = (aaAdd, aaRemove);
  TAnnotateWhich = (awAll, awUnnumbered, awMatching);
  TAnnotateStart = (asDefault, asSpecified);

  { AnnotateSetup }
  TAnnotateSetup = record
    Action: TAnnotateAction;
    Reference: TAnnotateWhich;
    Value: TAnnotateStart;
    MatchVal: String;
    StartVal: Integer;
    AllSheets: Boolean;
  end;

{ AnnotateSetup::AnnotateSetup: add, all references, default start, "U?", 1, one sheet }
function AnnotateDefaults: TAnnotateSetup;

{ OnSpecialAnnotate after the dialog: returns True if a symbol with no definition was met (the caller says so) }
function RunAnnotate(Design: TDesignFile; ActiveSheet: Integer; const S: TAnnotateSetup): Boolean;

{ The reference painter: gives the next number (from StartVal) to, or takes it from, every symbol under the point of the sheet's drawing;
  returns how many symbols were changed }
function PaintReference(Sheet: TDesignSheet; const P: TDPoint; StartVal: Integer; Remove: Boolean): Integer;

implementation

{ ===========================================================================
  AnnotateDefaults  (function)
  Parameters:  none
  Returns:
    TAnnotateSetup - the first choices
  Notes:
    AnnotateSetup::AnnotateSetup: add, all references, the default start value, matching "U?",
    start 1, and only the current sheet.
  =========================================================================== }
function AnnotateDefaults: TAnnotateSetup;
begin
  Result.Action := aaAdd;
  Result.Reference := awAll;
  Result.Value := asDefault;
  Result.MatchVal := 'U?';
  Result.StartVal := 1;
  Result.AllSheets := False;
end;

{ ===========================================================================
  RunAnnotate  (function)
  Parameters:
    Design: TDesignFile - the design
    ActiveSheet: Integer - the number of the sheet that is showing (0 is the first)
    const S: TAnnotateSetup - the choices
  Returns:
    Boolean - True if a symbol with no definition was met
  Notes:
    The two passes of CTinyCadView::OnSpecialAnnotate (see the unit's description). A symbol
    whose definition is missing (symbol number 0) cannot be changed; the caller tells the
    person.
  =========================================================================== }
function RunAnnotate(Design: TDesignFile; ActiveSheet: Integer; const S: TAnnotateSetup): Boolean;
var
  Pass, Sheet, I, J, K, Value: Integer;
  Lists: array of TDrawingList;
  Meths: array of TDrawMethod;
  Keys: array of TDPoint;
  M, Tmp: TDrawMethod;
  TmpKey: TDPoint;
  Draw: TDrawingList;
  IsSet, IsMatch: Boolean;
  Sym: TSymbolInfo;
begin
  Result := False;
  Lists := nil;
  SetLength(Lists, Design.SheetCount);
  for I := 0 to Design.SheetCount - 1 do
  begin
    Lists[I] := Design.Sheets[I].Drawing;
    Design.Sheets[I].UpdateLayout;     // (the C++ gives every symbol its box when the file is read; here a sheet nobody has shown yet may not have it)
  end;
  for Pass := 0 to 1 do
  begin
    if S.AllSheets then
      Sheet := 0
    else
      Sheet := ActiveSheet;
    repeat
      Draw := Design.Sheets[Sheet].Drawing;
      { the symbols of the sheet in order of the centre of their box: the y first, then the x }
      Meths := nil; Keys := nil;
      for I := 0 to Draw.Count - 1 do
        if (Draw[I].GetType = xMethodEx3) or (Draw[I].GetType = xHierarchicalSymbol) then
        begin
          J := Length(Meths);
          SetLength(Meths, J + 1); SetLength(Keys, J + 1);
          Meths[J] := Draw[I] as TDrawMethod;
          Keys[J] := DPoint((Draw[I].PointA.x + Draw[I].PointB.x) / 2, (Draw[I].PointA.y + Draw[I].PointB.y) / 2);
        end;
      for I := 1 to High(Meths) do      // (insertion sort: it keeps equal centres in drawing order)
      begin
        Tmp := Meths[I]; TmpKey := Keys[I];
        K := I - 1;
        while (K >= 0) and ((TmpKey.y < Keys[K].y) or ((TmpKey.y = Keys[K].y) and (TmpKey.x < Keys[K].x))) do
        begin
          Meths[K + 1] := Meths[K]; Keys[K + 1] := Keys[K];
          Dec(K);
        end;
        Meths[K + 1] := Tmp; Keys[K + 1] := TmpKey;
      end;
      for I := 0 to High(Meths) do
      begin
        M := Meths[I];
        { a placed design has no symbol of the library: it is "no symbol" when its design gives nothing to draw }
        if ((M is TDrawHierarchicalSymbol) and (M as TDrawHierarchicalSymbol).IsNoSymbol) or
           ((not (M is TDrawHierarchicalSymbol)) and (M.SymbolId = 0)) then
        begin
          Result := True;       // no symbol: it cannot be altered
          Continue;
        end;
        Sym := M.GetSymbolData;
        IsSet := M.HasRef;
        IsMatch := False;
        case S.Reference of
          awAll: IsMatch := True;
          awUnnumbered: IsMatch := not M.HasRef;
          awMatching: IsMatch := S.MatchVal = Sym.SymbolReference;
        end;
        if IsMatch then
        begin
          if Pass = 0 then
          begin
            { first pass: matching references that have a number lose it }
            if IsSet and ((S.Value <> asSpecified) or (M.GetRefVal >= S.StartVal)) then
              M.RemoveReference;
          end
          else if S.Action = aaAdd then
          begin
            { second pass: references are given back }
            if S.Value = asSpecified then
              Value := S.StartVal
            else
              Value := 1;
            if S.AllSheets then
              M.AddReference(Value, Lists, Draw)
            else
              M.AddReference(Value, [Draw], Draw);
          end;
        end;
      end;
      Inc(Sheet);
    until (not S.AllSheets) or (Sheet >= Design.SheetCount);
  end;
end;

{ ===========================================================================
  PaintReference  (function)
  Parameters:
    Sheet: TDesignSheet - the sheet clicked on
    const P: TDPoint - the point (not snapped to the grid)
    StartVal: Integer - the lowest number to give
    Remove: Boolean - True for the right button (take the number away)
  Returns:
    Integer - how many symbols were changed
  Notes:
    CDrawRefPainter::LButtonDown and RButtonUp: every placed symbol that the point is on gets
    the next number from StartVal (searching this sheet only), or goes back to its reference
    prefix.
  =========================================================================== }
function PaintReference(Sheet: TDesignSheet; const P: TDPoint; StartVal: Integer; Remove: Boolean): Integer;
var
  I: Integer;
  Obj: TDrawingObject;
begin
  Result := 0;
  for I := 0 to Sheet.Drawing.Count - 1 do
  begin
    Obj := Sheet.Drawing[I];
    if Obj.IsInside(P.x, P.x, P.y, P.y) and (Obj.GetType = xMethodEx3) then
    begin
      if Remove then
        (Obj as TDrawMethod).RemoveReference
      else
        (Obj as TDrawMethod).AddReference(StartVal, [Sheet.Drawing], Sheet.Drawing);
      Inc(Result);
    end;
  end;
end;

end.
