// SPDX-License-Identifier: LGPL-2.1-or-later
{ Links between objects: text that follows another object around.

  A TDrawRefText names a target by its stable object id. Whenever the drawing changes,
  UpdateLinks recomputes what each one should say, so a coil's reference can show the ladder lines
  its contacts sit on and a contact can show the line of its coil, and moving any of them updates
  the text with no further action.

  A symbol's "line" is the ladder line it sits on: the row of the sheet's rung grid (TDrawRungGrid) that
  the point where its connections are falls in, and that row's rung number (TDrawRungGrid.LineNumberAt).

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit ULinks;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, UDPoint, UDrawTypes, UDrawingObjects, UDesign;

{ Recompute every linked text in the design (and its layout) }
procedure UpdateLinks(Design: TDesignFile);
{ The rung number an object sits on. False when the sheet has no rung grid or the object is in its indent. }
function LineNumberOfObject(Sheet: TDesignSheet; Obj: TDrawingObject; out Number: Integer): Boolean;

implementation

{ where an object "is" for the purpose of finding its line: the middle of its connection points, else
  the middle of its box }

{ ===========================================================================
  ReferencePoint  (function)
  Parameters:
    Obj: TDrawingObject - the object
  Returns:
    TDPoint - the reference point in design units
  Notes:
    Where an object "is" for finding its ladder line: the middle of a placed symbol's connection
    points, otherwise the middle of its box, otherwise its first point (junctions use their
    point).
  =========================================================================== }
function ReferencePoint(Obj: TDrawingObject): TDPoint;
var
  Act: TDPointArray;
  i: Integer;
  Sx, Sy: Double;
begin
  if Obj is TDrawMethod then
  begin
    Obj.UpdateLayout;
    Act := (Obj as TDrawMethod).ActivePoints;
    if Length(Act) > 0 then
    begin
      Sx := 0; Sy := 0;
      for i := 0 to High(Act) do begin
        Sx := Sx + Act[i].x;
        Sy := Sy + Act[i].y;
      end;
      Result := DPoint(Sx / Length(Act), Sy / Length(Act));
      Exit;
    end;
  end;
  if DPointHasValue(Obj.PointB) and (Obj.GetType <> xJunction) then
    Result := DPoint((Obj.PointA.x + Obj.PointB.x) / 2, (Obj.PointA.y + Obj.PointB.y) / 2)
  else
    Result := Obj.PointA;
end;

{ ===========================================================================
  LineNumberOfObject  (function)
  Parameters:
    Sheet: TDesignSheet - the sheet to look on
    Obj: TDrawingObject - the object
    out Number: Integer - set to the line number (0 when not on a ladder)
  Returns:
    Boolean - True when the object is between a ladder's rails
  Notes:
    Finds the ladder line an object sits on: the first ladder on the sheet whose rails enclose
    the object's reference point, and the line number at that height.
  =========================================================================== }
function LineNumberOfObject(Sheet: TDesignSheet; Obj: TDrawingObject; out Number: Integer): Boolean;
var
  P: TDPoint;
  i: Integer;
begin
  Result := False;
  Number := 0;
  P := ReferencePoint(Obj);
  for i := 0 to Sheet.Drawing.Count - 1 do
    if Sheet.Drawing[i] is TDrawRungGrid then
    begin
      Result := (Sheet.Drawing[i] as TDrawRungGrid).LineNumberAt(P, Number);
      Exit;
    end;
end;

type
  TLineRef = record
    SheetNo, Line: Integer; // line 0 = not on a ladder
  end;

{ ===========================================================================
  Where  (function)
  Parameters:
    OwnSheet: Integer - 1-based number of the sheet the text is on
    const R: TLineRef - the sheet number and line to show
  Returns:
    String - the text to show
  Notes:
    Formats a line reference for display: the plain line number on the same sheet, "sheet.line"
    on another sheet, or "?" when the object is not on a ladder.
  =========================================================================== }
function Where(OwnSheet: Integer; const R: TLineRef): String;
begin
  if R.Line = 0 then
    Result := '?'
  else if R.SheetNo = OwnSheet then
    Result := IntToStr(R.Line)
  else
    Result := IntToStr(R.SheetNo) + '.' + IntToStr(R.Line); // other sheet: "sheet.line"
end;

{ ===========================================================================
  TextFor  (function)
  Parameters:
    Design: TDesignFile - the design to search
    OwnSheet: Integer - zero-based index of the sheet the text is on
    X: TDrawRefText - the linked text object
  Returns:
    String - the resolved text without prefix or suffix
  Notes:
    Works out what a linked text should say. Mode 0 gives the ladder line of its target; mode 1
    gives the lines of the other symbols that share the target's reference, sorted by sheet then
    line and separated by commas ("-" when there are none, "?" when the target no longer
    exists).
  =========================================================================== }
function TextFor(Design: TDesignFile; OwnSheet: Integer; X: TDrawRefText): String;
var
  Target: TDrawingObject;
  TSheet, i, j, k, N, Ln: Integer;
  Refs: array of TLineRef;
  Tmp: TLineRef;
  Ref: String;
  M: TDrawMethod;
begin
  Result := '?';
  Target := Design.FindObject(X.TargetId, TSheet);
  if Target = nil then
    Exit;
  if X.Mode = 0 then
  begin
    if LineNumberOfObject(Design.Sheets[TSheet], Target, Ln) then
    begin
      Tmp.SheetNo := TSheet + 1; Tmp.Line := Ln;
      Result := Where(OwnSheet + 1, Tmp);
    end
    else
      Result := '?';
    Exit;
  end;
  { mode 1: the other symbols that share the target's reference }
  if not (Target is TDrawMethod) then begin
    Result := '-';
    Exit;
  end;
  Ref := (Target as TDrawMethod).GetRef;
  N := 0;
  for i := 0 to Design.SheetCount - 1 do
    for j := 0 to Design.Sheets[i].Drawing.Count - 1 do
      if Design.Sheets[i].Drawing[j] is TDrawMethod then
      begin
        M := Design.Sheets[i].Drawing[j] as TDrawMethod;
        if (M = Target) or (M.GetRef <> Ref) or (Ref = '') then
          Continue;
        SetLength(Refs, N + 1);
        Refs[N].SheetNo := i + 1;
        if LineNumberOfObject(Design.Sheets[i], M, Ln) then
          Refs[N].Line := Ln
        else
          Refs[N].Line := 0;
        Inc(N);
      end;
  if N = 0 then begin
    Result := '-';
    Exit;
  end;
  for i := 1 to N - 1 do // order by sheet, then line
  begin
    Tmp := Refs[i];
    k := i - 1;
    while (k >= 0) and ((Refs[k].SheetNo > Tmp.SheetNo) or ((Refs[k].SheetNo = Tmp.SheetNo) and (Refs[k].Line > Tmp.Line))) do
    begin
      Refs[k + 1] := Refs[k];
      Dec(k);
    end;
    Refs[k + 1] := Tmp;
  end;
  Result := '';
  for i := 0 to N - 1 do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + Where(OwnSheet + 1, Refs[i]);
  end;
end;

{ ===========================================================================
  UpdateLinks  (procedure)
  Parameters:
    Design: TDesignFile - the design to update
  Notes:
    Recomputes the text of every linked text object in the design and refreshes its layout. Call
    after anything that can change a line number: moving, adding or deleting objects, or editing
    a ladder.
  =========================================================================== }
procedure UpdateLinks(Design: TDesignFile);
var
  i, j: Integer;
  X: TDrawRefText;
begin
  for i := 0 to Design.SheetCount - 1 do
    for j := 0 to Design.Sheets[i].Drawing.Count - 1 do
      if Design.Sheets[i].Drawing[j] is TDrawRefText then
      begin
        X := Design.Sheets[i].Drawing[j] as TDrawRefText;
        X.CachedText := TextFor(Design, i, X);
        X.UpdateLayout;
      end;
end;

end.
