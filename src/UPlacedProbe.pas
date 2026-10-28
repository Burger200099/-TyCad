{ Test helper for placed symbols (TDrawMethod). For one placement it checks:
    draw path    the symbol drawn through Transform.SetTRM puts each pin where
                 TranslatePointToDesign says (two independent C++ code paths)
    rotation     rotating the placement about a point moves every pin's connection point as a
                 rigid rotation of its old position (checks DoRotate tables + translation)
    hit          the symbol is hit at each of its pins' connection points
    box          every connection point lies inside the placement's bounding box
    replace      replacing a symbol with itself leaves the pins where they were

  The box and hit checks assume the symbol's visible far corner is its local origin. The C++
  code does not guarantee that: the reference point (CreateSymbol) counts invisible power pins and
  the size (GetTr) does not, and a saved REF_POINT may have been computed with another grid.
  Such placements are counted as Inconsistent and excluded from the box/hit checks. }
unit UPlacedProbe;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, Types, UDPoint, UDrawTypes, UGeometry, UDrawingObjects;

type
  TPlacedStats = record
    Placements, PinPoints: Integer;
    DrawBad, RotateBad, HitBad, BoxBad, ReplaceBad: Integer;
    Inconsistent: Integer; // placements whose reference frame disagrees with their size (see below)
  end;

procedure ProbePlaced(M: TDrawMethod; var St: TPlacedStats; const Where: String);

implementation

{ ===========================================================================
  CRound  (function)
  Parameters:
    D: Double - the number
  Returns:
    Integer - the rounded value
  Notes:
    Rounds to nearest, halves away from zero, as C does (used to compare with the C++ pin
    layout).
  =========================================================================== }
function CRound(D: Double): Integer; // Transform::Round: half away from zero
begin
  if D > -0.5 then
    Result := Trunc(D + 0.5)
  else
    Result := Trunc(D - 0.5);
end;

{ ===========================================================================
  Near  (function)
  Parameters:
    const A: TDPoint - first point
    const B: TDPoint - second point
    Tol: Double - allowed difference per axis
  Returns:
    Boolean - True if close enough
  Notes:
    Whether two points differ by no more than a tolerance on each axis.
  =========================================================================== }
function Near(const A, B: TDPoint; Tol: Double): Boolean;
begin
  Result := (Abs(A.x - B.x) <= Tol) and (Abs(A.y - B.y) <= Tol);
end;

{ ===========================================================================
  FrameConsistent  (function)
  Parameters:
    M: TDrawMethod
    L: TDrawingList
  Returns:
    Boolean
  Notes:
    Is the far corner of the visible objects, snapped outwards as GetTr does, the local origin?
  =========================================================================== }
function FrameConsistent(M: TDrawMethod; L: TDrawingList): Boolean;
var
  i: Integer;
  A, SnapA: TDPoint;
  First: Boolean;
  O: TDrawingObject;
  Grid: Double;
begin
  A := DPoint(0, 0);
  First := True;
  for i := 0 to L.Count - 1 do
  begin
    O := L[i];
    if (O.GetType = xPinEx) and (O as TDrawPin).IsInvisible then
      Continue;
    if First then
    begin
      A := DPoint(Max(O.PointA.x, O.PointB.x), Max(O.PointA.y, O.PointB.y));
      First := False;
    end
    else
      A := DPoint(Max(A.x, Max(O.PointA.x, O.PointB.x)), Max(A.y, Max(O.PointA.y, O.PointB.y)));
  end;
  if First then begin
    Result := True;
    Exit;
  end;
  Grid := M.Options.Snap.Grid;
  SnapA := M.Options.Snap.Snap(A);
  if SnapA.x < A.x then
    SnapA.x := SnapA.x + Grid;
  if SnapA.y < A.y then
    SnapA.y := SnapA.y + Grid;
  Result := (Abs(SnapA.x) < 1E-6) and (Abs(SnapA.y) < 1E-6);
end;

{ ===========================================================================
  Note  (procedure)
  Parameters:
    var Count: Integer - running count (updated)
    const Kind: String - the kind of finding
    const Where: String - where it was found
    const Detail: String - extra description
  Notes:
    Counts a finding and prints the first 40 of them.
  =========================================================================== }
procedure Note(var Count: Integer; const Kind, Where: String; const Detail: String);
begin
  Inc(Count);
  if Count <= 40 then
    WriteLn('  ', Kind, ' ', Where, ' ', Detail);
end;

{ ===========================================================================
  ProbePlaced  (procedure)
  Parameters:
    M: TDrawMethod - the placed symbol
    var St: TPlacedStats - running statistics (updated)
    const Where: String - where the symbol came from, for messages
  Notes:
    Test helper: checks a placed symbol against the C++ rules (draw path versus netlist path
    agree on every pin, rotation moves pins rigidly, pins are hit, pins lie in the box,
    replacing a symbol with itself moves nothing) and updates the statistics.
  =========================================================================== }
procedure ProbePlaced(M: TDrawMethod; var St: TPlacedStats; const Where: String);
var
  Tr: TDPoint;
  L: TDrawingList;
  i, k, Rot: Integer;
  T: TTransform;
  Px: TPoint;
  Ap, Ap2, Before: TDPointArray;
  Pin: TDrawPin;
  C, Want: TDPoint;
  Cl: TDrawingObject;
  Min_, Max_: TDPoint;
  W: String;
  Consistent: Boolean;
begin
  W := Where + ' rot=' + IntToStr(M.Rotate) + ' sc=' + FloatToStr(M.ScalingX) + ',' + FloatToStr(M.ScalingY) +
       ' part=' + IntToStr(M.Part) + ' ppp=' + IntToStr(M.GetSymbolData.PartsPerPackage);
  Inc(St.Placements);
  M.UpdateLayout;
  M.ExtractSymbol(Tr, L);
  Before := M.ActivePoints;
  Consistent := FrameConsistent(M, L);
  if not Consistent then
    Inc(St.Inconsistent);

  { ---- draw path vs TranslatePointToDesign ---- }
  T := TTransform.Create;
  try
    T.SetOrigin(DPoint(0, 0));
    T.SetScaling(M.Rotate, M.ScalingX, M.ScalingY);
    T.SetTRM(M.PointA, Tr, M.Rotate);
    for i := 0 to L.Count - 1 do
      if L[i].GetType = xPinEx then
      begin
        Pin := L[i] as TDrawPin;
        if Pin.IsInvisible then
          Continue;
        Inc(St.PinPoints);
        Px := T.Scale(Pin.PointA);
        Want := M.TranslatePointToDesign(Pin.PointA);
        if (Px.x <> CRound(Want.x)) or (Px.y <> CRound(Want.y)) then
          Note(St.DrawBad, 'DRAW', W, Format('pin local %g,%g: transform %d,%d vs translate %g,%g',
            [Pin.PointA.x, Pin.PointA.y, Px.x, Px.y, Want.x, Want.y]));
      end;
  finally
    T.Free;
  end;

  { ---- hit test and bounding box at each connection point ---- }
  Min_ := DPoint(Min(M.PointA.x, M.PointB.x) - 1E-6, Min(M.PointA.y, M.PointB.y) - 1E-6);
  Max_ := DPoint(Max(M.PointA.x, M.PointB.x) + 1E-6, Max(M.PointA.y, M.PointB.y) + 1E-6);
  for k := 0 to High(Before) do
  begin
    if not Consistent then
      Break;
    if (Before[k].x < Min_.x) or (Before[k].x > Max_.x) or (Before[k].y < Min_.y) or (Before[k].y > Max_.y) then
      Note(St.BoxBad, 'BOX', W, Format('active point %g,%g outside box %g,%g .. %g,%g',
        [Before[k].x, Before[k].y, M.PointA.x, M.PointA.y, M.PointB.x, M.PointB.y]));
    if M.DistanceFromPoint(Before[k]) > 1E-6 then
      Note(St.HitBad, 'HIT', W, Format('active point %g,%g distance %g', [Before[k].x, Before[k].y, M.DistanceFromPoint(Before[k])]));
  end;

  { ---- rotating about a point rotates the pins rigidly ---- }
  C := DPoint(37, 23);
  for Rot := 2 to 4 do
  begin
    Cl := M.Clone;
    try
      Cl.RotateAbout(C, Rot);
      Ap := (Cl as TDrawMethod).ActivePoints;
      if Length(Ap) <> Length(Before) then
        Note(St.RotateBad, 'ROT', W, 'pin count changed')
      else
        for k := 0 to High(Ap) do
        begin
          Want := RotatePointAbout(Before[k], C, Rot);
          if not Near(Ap[k], Want, 1E-6) then
          begin
            Note(St.RotateBad, 'ROT', W, Format('rotation %d pin %d: got %g,%g want %g,%g',
              [Rot, k, Ap[k].x, Ap[k].y, Want.x, Want.y]));
            Break;
          end;
        end;
    finally
      Cl.Free;
    end;
  end;

  { ---- replacing a symbol with itself must not move the pins ---- }
  Cl := M.Clone;
  try
    (Cl as TDrawMethod).ReplaceSymbol(M.SymbolId, M.SymbolId, True);
    Ap2 := (Cl as TDrawMethod).ActivePoints;
    if Length(Ap2) <> Length(Before) then
      Note(St.ReplaceBad, 'REPL', W, 'pin count changed')
    else
      for k := 0 to High(Ap2) do
        if not Near(Ap2[k], Before[k], 1E-6) then
        begin
          Note(St.ReplaceBad, 'REPL', W, Format('pin %d moved to %g,%g from %g,%g', [k, Ap2[k].x, Ap2[k].y, Before[k].x, Before[k].y]));
          Break;
        end;
  finally
    Cl.Free;
  end;
end;

end.
