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
  Classes, SysUtils, Math, UDPoint, UDrawTypes, UDrawingObjects, USymbols, UDesign;

{ Recompute every linked text in the design (and its layout) }
procedure UpdateLinks(Design: TDesignFile);
type
  { Which rung of the sheet's rung grid a symbol belongs to. Candidates are the rungs its connection points fall in (lowest first); Number is the one used. }
  TRungInfo = record
    Found: Boolean;                // the sheet has a rung grid and the symbol is inside it
    Number: Integer;               // the rung used (the chosen one when Overridden)
    Ambiguous: Boolean;            // the symbol spans several rungs and two overlap it equally: the lowest was taken, and the user can choose
    Overridden: Boolean;           // the rung was chosen (TDrawMethod.RungOverride)
    Candidates: array of Integer;  // the rung numbers its connection points fall in, ascending
  end;

{ Works out the rung of a symbol or other object: the rung its connection points sit in; when they span several, the one the symbol overlaps most (a tie is Ambiguous);
  a rung chosen on the symbol wins over both. False when the sheet has no rung grid or the object is outside it. }
function RungOfObject(Sheet: TDesignSheet; Obj: TDrawingObject; out Info: TRungInfo): Boolean;
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
  Info: TRungInfo;
begin
  Result := RungOfObject(Sheet, Obj, Info);
  if Result then
    Number := Info.Number
  else
    Number := 0;
end;

{ ===========================================================================
  RungOfObject  (function)
  Parameters:
    Sheet: TDesignSheet - the sheet to look on
    Obj: TDrawingObject - the object
    out Info: TRungInfo - the rung and how it was found
  Returns:
    Boolean - True when the object has a rung
  Notes:
    A symbol whose connection points all fall in one row of the rung grid has that rung. When they fall in several rows the symbol belongs to the row its body overlaps most
    (the vertical overlap of the symbol's box with each row; the rows the box crosses between the pins are candidates too); equal overlaps make it Ambiguous and the lowest-numbered row is used until a rung is chosen. A rung chosen on the
    symbol (RungOverride) is used whatever the position, while the sheet has a rung grid. A symbol with no connection points, or any other object, is where the middle of its box is.
    Only the first rung grid on the sheet counts (a sheet has one).
  =========================================================================== }
function RungOfObject(Sheet: TDesignSheet; Obj: TDrawingObject; out Info: TRungInfo): Boolean;
var
  Grid: TDrawRungGrid;
  Act: TDPointArray;
  P: TDPoint;
  Rows: array of Integer;
  i, k, n, Row, Best: Integer;
  Y0, Y1, Top, RH, Ov, BestOv, Second: Double;
  Pg: Integer;
  Dup: Boolean;
begin
  Result := False;
  Info.Found := False; Info.Number := 0; Info.Ambiguous := False; Info.Overridden := False;
  SetLength(Info.Candidates, 0);
  Grid := nil;
  for i := 0 to Sheet.Drawing.Count - 1 do
    if Sheet.Drawing[i] is TDrawRungGrid then
    begin
      Grid := Sheet.Drawing[i] as TDrawRungGrid;
      Break;
    end;
  if Grid = nil then
    Exit;
  SetLength(Rows, 0);
  Pg := -1;
  if Obj is TDrawMethod then
  begin
    Obj.UpdateLayout;
    Act := (Obj as TDrawMethod).ActivePoints;
    for i := 0 to High(Act) do
    begin
      Row := Grid.RowAtY(Act[i].y);
      if (Row < 0) or (Act[i].x < Grid.AreaRect.Left) or (Act[i].x > Grid.AreaRect.Right) then
        Continue;
      if Pg < 0 then
        Pg := Grid.PageAtX(Act[i].x);
      n := Length(Rows);
      Dup := False;
      for k := 0 to n - 1 do
        if Rows[k] = Row then
          Dup := True;
      if not Dup then
      begin
        SetLength(Rows, n + 1);
        Rows[n] := Row;
      end;
    end;
  end;
  if Length(Rows) = 0 then
  begin
    P := ReferencePoint(Obj);
    Row := Grid.RowAtY(P.y);
    if (Row < 0) or (P.x < Grid.AreaRect.Left) or (P.x > Grid.AreaRect.Right) then
      Exit;
    Pg := Grid.PageAtX(P.x);
    SetLength(Rows, 1);
    Rows[0] := Row;
  end;
  for i := 1 to High(Rows) do                 // ascending
  begin
    Row := Rows[i];
    k := i - 1;
    while (k >= 0) and (Rows[k] > Row) do
    begin
      Rows[k + 1] := Rows[k];
      Dec(k);
    end;
    Rows[k + 1] := Row;
  end;
  Best := Rows[0];
  if Length(Rows) > 1 then
  begin
    Y0 := Min(Obj.PointA.y, Obj.PointB.y);
    Y1 := Max(Obj.PointA.y, Obj.PointB.y);
    Top := Grid.AreaRect.Top;
    RH := Grid.RowHeight;
    { the connection points are in several rows: the rows the symbol's box crosses are candidates too (a pin on each side of a row it crosses fully) }
    for Row := 0 to Grid.Rows - 1 do
      if Min(Y1, Top + (Row + 1) * RH) - Max(Y0, Top + Row * RH) > RH * 1E-6 then
      begin
        Dup := False;
        for k := 0 to High(Rows) do
          if Rows[k] = Row then
            Dup := True;
        if not Dup then
        begin
          SetLength(Rows, Length(Rows) + 1);
          Rows[High(Rows)] := Row;
        end;
      end;
    for i := 1 to High(Rows) do                 // ascending
    begin
      Row := Rows[i];
      k := i - 1;
      while (k >= 0) and (Rows[k] > Row) do
      begin
        Rows[k + 1] := Rows[k];
        Dec(k);
      end;
      Rows[k + 1] := Row;
    end;
    BestOv := -1; Second := -1;
    for i := 0 to High(Rows) do
    begin
      Ov := Min(Y1, Top + (Rows[i] + 1) * RH) - Max(Y0, Top + Rows[i] * RH);
      if Ov > BestOv + RH * 1E-6 then
      begin
        Second := BestOv;
        BestOv := Ov;
        Best := Rows[i];
      end
      else if Ov > Second then
        Second := Ov;
    end;
    Info.Ambiguous := Abs(BestOv - Second) <= RH * 1E-6;
    if Info.Ambiguous then
      Best := Rows[0];
  end;
  SetLength(Info.Candidates, Length(Rows));
  for i := 0 to High(Rows) do
    Info.Candidates[i] := Grid.NumberAt(Pg, Rows[i]);
  Info.Number := Grid.NumberAt(Pg, Best);
  if (Obj is TDrawMethod) and ((Obj as TDrawMethod).RungOverride <> 0) then
  begin
    Info.Number := (Obj as TDrawMethod).RungOverride;
    Info.Overridden := True;
    Info.Ambiguous := False;
  end;
  Info.Found := True;
  Result := True;
end;

type
  TLineRef = record
    SheetNo, Line: Integer; // line 0 = not on a ladder
    Form: String;           // for a contact of a part: NO, NC ... ('' when not known)
  end;

{ ===========================================================================
  ObjectOfSymbol  (procedure)
  Parameters:
    M: TDrawMethod - a placed symbol
    out Kind, Form: String - what it shows of its part: Coil / Pole / Contact (and the contact's form NO / NC ...); both '' for a symbol that is not a part's object
  =========================================================================== }
procedure ObjectOfSymbol(M: TDrawMethod; out Kind, Form: String);
var
  D: TObject;
begin
  Kind := ''; Form := '';
  D := M.GetSymbolData;
  if D is TDesignFileSymbol then
  begin
    Kind := TDesignFileSymbol(D).PartInfo.ObjectKind;
    Form := TDesignFileSymbol(D).PartInfo.ObjectForm;
  end;
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
  RungReferenceText  (function)
  Parameters:
    Design: TDesignFile - the design to search
    OwnSheet: Integer - zero-based index of the sheet the text is on
    Target: TDrawingObject - the symbol the reference is for
  Returns:
    String - the text
  Notes:
    EPLAN style cross reference. For a coil (or a symbol that is not an object of a part) it lists the other symbols with the same reference that are contacts, each as its rung and its
    form: "5 NO  7 NC" (two spaces between entries, ordered by sheet then rung, "2.5 NO" for another sheet, "?" for a rung that is not on a ladder); "-" when there are none. For a
    contact it gives the rung of the coil, or the coils, of the same reference ("-" when there is none). "?" when the target is not a placed symbol.
  =========================================================================== }
function RungReferenceText(Design: TDesignFile; OwnSheet: Integer; Target: TDrawingObject): String;
var
  TKind, TForm, Kind, Form, Ref: String;
  List: array of TLineRef;
  i, j, k, Ln: Integer;
  M: TDrawMethod;
  Tmp: TLineRef;
  WantContacts: Boolean;
begin
  Result := '?';
  if not (Target is TDrawMethod) then
    Exit;
  Ref := (Target as TDrawMethod).GetRef;
  ObjectOfSymbol(Target as TDrawMethod, TKind, TForm);
  WantContacts := TKind <> 'Contact';         // a coil lists its contacts; a contact lists its coil
  SetLength(List, 0);
  if Ref <> '' then
    for i := 0 to Design.SheetCount - 1 do
      for j := 0 to Design.Sheets[i].Drawing.Count - 1 do
        if Design.Sheets[i].Drawing[j] is TDrawMethod then
        begin
          M := Design.Sheets[i].Drawing[j] as TDrawMethod;
          if (M = Target) or (not SameText(M.GetRef, Ref)) then
            Continue;
          ObjectOfSymbol(M, Kind, Form);
          if WantContacts and (Kind <> 'Contact') then
            Continue;
          if (not WantContacts) and (Kind <> 'Coil') then
            Continue;
          SetLength(List, Length(List) + 1);
          List[High(List)].SheetNo := i + 1;
          if LineNumberOfObject(Design.Sheets[i], M, Ln) then
            List[High(List)].Line := Ln
          else
            List[High(List)].Line := 0;
          if WantContacts then
            List[High(List)].Form := Form
          else
            List[High(List)].Form := '';
        end;
  if Length(List) = 0 then
  begin
    Result := '-';
    Exit;
  end;
  for i := 1 to High(List) do                  // by sheet, then rung
  begin
    Tmp := List[i];
    k := i - 1;
    while (k >= 0) and ((List[k].SheetNo > Tmp.SheetNo) or ((List[k].SheetNo = Tmp.SheetNo) and (List[k].Line > Tmp.Line))) do
    begin
      List[k + 1] := List[k];
      Dec(k);
    end;
    List[k + 1] := Tmp;
  end;
  Result := '';
  for i := 0 to High(List) do
  begin
    if i > 0 then
      Result := Result + '  ';
    Result := Result + Where(OwnSheet + 1, List[i]);
    if List[i].Form <> '' then
      Result := Result + ' ' + List[i].Form;
  end;
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
    Works out what a linked text should say. Mode 0 gives the ladder line of its target; mode 2 the cross reference of RungReferenceText; mode 1
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
  if X.Mode = 2 then
  begin
    Result := RungReferenceText(Design, OwnSheet, Target);
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
