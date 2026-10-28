{ Randomised check of polygon handle editing. Random polygons (with arcs and curves) get thousands of random
  menu actions and handle drags; after each one the polygon must still be sound:
    - the other handles keep their absolute positions (the origin is rebased, the shape is not moved)
    - an added handle is exactly the snapped click, in order; a deleted one is exactly one of the old handles
    - a polygon never drops below two handles
    - the origin is the top left of the bounding box, which holds every handle and every flattened point
    - saving and loading gives back the same handles, arcs and control points
  Prints a summary; the checker in tests/run_poly.py reads it. }
program polytest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, UDPoint, UDrawTypes, UGeometry, UDrawingObjects, UDesign, UXMLReader, UXMLWriter;

var
  Seed: Cardinal = 20261004;
  Checks, Fails, Actions, Drags, RoundTrips: Integer;

{ ===========================================================================
  Rnd  (function)
  Parameters:  none
  Returns:
    Double - a number from 0 up to but not including 1
  Notes:
    A small deterministic random number generator, so tests repeat exactly.
  =========================================================================== }
function Rnd: Double;
begin
  Seed := Seed * 1664525 + 1013904223;
  Result := (Seed shr 8) / 16777216.0;
end;

{ ===========================================================================
  RI  (function)
  Parameters:
    Lo: Integer - lowest
    Hi: Integer - highest
  Returns:
    Integer - the number
  Notes:
    A random whole number from Lo to Hi.
  =========================================================================== }
function RI(Lo, Hi: Integer): Integer;
begin
  Result := Lo + Trunc(Rnd * (Hi - Lo + 1));
end;

{ ===========================================================================
  Check  (procedure)
  Parameters:
    Ok: Boolean - flag
    const What: String - description for the failure message
  Notes:
    Counts a check and a failure when the condition is False, printing the first failures.
  =========================================================================== }
procedure Check(Ok: Boolean; const What: String);
begin
  Inc(Checks);
  if not Ok then
  begin
    Inc(Fails);
    if Fails <= 12 then WriteLn('FAIL ', What);
  end;
end;

type
  TPts = array of TDPoint;

{ ===========================================================================
  Absolute  (function)
  Parameters:
    Pg: TDrawPolygon - the polygon
  Returns:
    TPts - one point per handle
  Notes:
    The positions of a polygon's handles on the sheet (their stored positions are relative to
    its origin).
  =========================================================================== }
function Absolute(Pg: TDrawPolygon): TPts;
var
  i: Integer;
begin
  SetLength(Result, Length(Pg.Handles));
  for i := 0 to High(Pg.Handles) do
    Result[i] := DPoint(Pg.Handles[i].X + Pg.PointA.x, Pg.Handles[i].Y + Pg.PointA.y);
end;

{ ===========================================================================
  Same  (function)
  Parameters:
    const A: TDPoint - first point
    const B: TDPoint - second point
  Returns:
    Boolean - True if they are
  Notes:
    Whether two points are the same to within a millionth.
  =========================================================================== }
function Same(const A, B: TDPoint): Boolean;
begin
  Result := (Abs(A.x - B.x) < 1e-6) and (Abs(A.y - B.y) < 1e-6);
end;

{ ===========================================================================
  Snap10  (function)
  Parameters:
    V: Double - the coordinate
  Returns:
    Double - the snapped value
  Notes:
    Snaps a coordinate to the 10 unit grid (halves round up).
  =========================================================================== }
function Snap10(V: Double): Double;
begin
  Result := Floor(V / 10 + 0.5) * 10;
end;

{ ===========================================================================
  MakePolygon  (function)
  Parameters:
    Opts: TDocOptionsBase - the sheet options
  Returns:
    TDrawPolygon - the polygon
  Notes:
    Makes a random polygon: three to eight handles on the grid, each (but the first) straight,
    an arc in, an arc out or a curve with a control point, open or closed.
  =========================================================================== }
function MakePolygon(Opts: TDocOptionsBase): TDrawPolygon;
var
  i, n: Integer;
  H: TArcPoint;
  Base: TDPoint;
begin
  Result := TDrawPolygon.Create(Opts);
  n := RI(3, 8);
  Base := DPoint(RI(5, 60) * 10, RI(5, 60) * 10);
  Result.PointA := Base;
  SetLength(Result.Handles, n);
  for i := 0 to n - 1 do
  begin
    if i = 0 then begin H.X := 0; H.Y := 0; end
    else begin H.X := RI(-20, 20) * 10; H.Y := RI(-20, 20) * 10; end;
    H.Arc := Arc_none;
    H.Control := DPointInvalid;
    H.FlattenedSegment := 0;
    if i > 0 then
      case RI(0, 3) of
        1: H.Arc := Arc_in;
        2: H.Arc := Arc_out;
        3: begin H.Arc := Arc_control; H.Control := DPoint(RI(-20, 20) * 10, RI(-20, 20) * 10); end;
      end;
    Result.Handles[i] := H;
  end;
  Result.Close := RI(0, 1);
  Result.CalcBoundingRect;
end;

{ ===========================================================================
  CheckSound  (procedure)
  Parameters:
    Pg: TDrawPolygon - the polygon
    const Where: String - what has just been done, for messages
  Notes:
    Checks that a polygon is in a sound state: two handles at least, its origin the top left of
    its bounding box, and every handle and flattened point inside the box.
  =========================================================================== }
procedure CheckSound(Pg: TDrawPolygon; const Where: String);
var
  i, k: Integer;
  A: TPts;
  L, R, T, B, MinX, MinY: Double;
begin
  Check(Length(Pg.Handles) >= 2, Where + ': at least two handles');
  { the origin is the top left of the bounding box: the smallest x and y of the shape (flattened points and control
    points, as TinyCAD works the box out) are 0, give or take the whole number the box is cut to }
  MinX := 1e9; MinY := 1e9;
  for k := 0 to High(Pg.Points) do begin MinX := Min(MinX, Pg.Points[k].x); MinY := Min(MinY, Pg.Points[k].y); end;
  for i := 0 to High(Pg.Handles) do
    if Pg.Handles[i].Arc = Arc_control then begin MinX := Min(MinX, Pg.Handles[i].Control.x); MinY := Min(MinY, Pg.Handles[i].Control.y); end;
  Check((MinX >= -1e-6) and (MinX < 1) and (MinY >= -1e-6) and (MinY < 1), Where + ': the origin is the top left of the box');
  A := Absolute(Pg);
  L := Min(Pg.PointA.x, Pg.PointB.x); R := Max(Pg.PointA.x, Pg.PointB.x);
  T := Min(Pg.PointA.y, Pg.PointB.y); B := Max(Pg.PointA.y, Pg.PointB.y);
  for i := 0 to High(A) do
    Check((A[i].x >= L - 1e-6) and (A[i].x <= R + 1e-6) and (A[i].y >= T - 1e-6) and (A[i].y <= B + 1e-6), Where + ': the box holds handle ' + IntToStr(i));
  for k := 0 to High(Pg.Points) do
    Check((Pg.Points[k].x + Pg.PointA.x >= L - 1e-6) and (Pg.Points[k].x + Pg.PointA.x <= R + 1e-6) and
          (Pg.Points[k].y + Pg.PointA.y >= T - 1e-6) and (Pg.Points[k].y + Pg.PointA.y <= B + 1e-6), Where + ': the box holds flattened point ' + IntToStr(k));
end;

{ ===========================================================================
  RoundTrip  (procedure)
  Parameters:
    Pg: TDrawPolygon - the polygon
    Opts: TDocOptionsBase - the sheet options
  Notes:
    Saves a polygon as XML, loads it again and checks the same handles, arc types and control
    points come back.
  =========================================================================== }
procedure RoundTrip(Pg: TDrawPolygon; Opts: TDocOptionsBase);
var
  MS: TMemoryStream;
  W: TXMLWriter;
  R: TXMLReader;
  Tag: String;
  Q: TDrawPolygon;
  A, B: TPts;
  i: Integer;
begin
  MS := TMemoryStream.Create;
  try
    W := TXMLWriter.Create(MS);
    try
      Pg.SaveXML(W);
    finally
      W.Free;
    end;
    MS.Position := 0;
    R := TXMLReader.Create(MS);
    Q := TDrawPolygon.Create(Opts);
    try
      R.NextTag(Tag);
      Q.LoadXML(R);
      Inc(RoundTrips);
      A := Absolute(Pg);
      B := Absolute(Q);
      Check(Length(A) = Length(B), 'round trip: same number of handles');
      if Length(A) = Length(B) then
        for i := 0 to High(A) do
        begin
          Check(Same(A[i], B[i]), 'round trip: handle ' + IntToStr(i) + ' position');
          Check(Pg.Handles[i].Arc = Q.Handles[i].Arc, 'round trip: handle ' + IntToStr(i) + ' arc type');
          if Pg.Handles[i].Arc = Arc_control then
            Check(Same(DPoint(Pg.Handles[i].Control.x + Pg.PointA.x, Pg.Handles[i].Control.y + Pg.PointA.y),
                       DPoint(Q.Handles[i].Control.x + Q.PointA.x, Q.Handles[i].Control.y + Q.PointA.y)), 'round trip: control point ' + IntToStr(i));
        end;
    finally
      Q.Free;
      R.Free;
    end;
  finally
    MS.Free;
  end;
end;

{ ===========================================================================
  OneRun  (procedure)
  Parameters:
    Opts: TDocOptionsBase - the sheet options
  Notes:
    One random polygon put through 25 random steps (a handle drag, or a menu action at a random
    click), with every rule of the file header checked after each step.
  =========================================================================== }
procedure OneRun(Opts: TDocOptionsBase);
var
  Pg: TDrawPolygon;
  Before, After: TPts;
  step, i, j, Code, n, Removed: Integer;
  Act: TPolyAction;
  P, SP, Sh: TDPoint;
  Changed, Found, Ok2: Boolean;
begin
  Pg := MakePolygon(Opts);
  try
    CheckSound(Pg, 'new polygon');
    for step := 1 to 25 do
    begin
      Before := Absolute(Pg);
      if (Rnd < 0.3) then
      begin
        { drag a handle or a control point }
        i := RI(0, High(Pg.Handles));
        Code := 1000 + i;
        if (Pg.Handles[i].Arc = Arc_control) and (Rnd < 0.5) then Code := 5000 + i;
        Sh := DPoint(RI(-5, 5) * 10, RI(-5, 5) * 10);
        if Code >= 5000 then
          Check(Pg.HandleAt(DPoint(Pg.Handles[i].Control.x + Pg.PointA.x, Pg.Handles[i].Control.y + Pg.PointA.y), 2) >= 0, 'a control point is found at its own point')
        else
          Check(Pg.HandleAt(Before[i], 2) >= 0, 'a handle is found at its own point');
        Pg.MoveHandle(Code, Sh);
        Inc(Drags);
        After := Absolute(Pg);
        Check(Length(After) = Length(Before), 'a drag does not change the number of handles');
        for j := 0 to High(After) do
          if (Code < 5000) and (j = i) then Check(Same(After[j], DPoint(Before[j].x + Sh.x, Before[j].y + Sh.y)), 'the dragged handle moved by the drag')
          else Check(Same(After[j], Before[j]), 'a drag moves no other handle');
      end
      else
      begin
        Act := TPolyAction(RI(0, 5));
        { click near a random handle or segment }
        if Rnd < 0.5 then
        begin
          j := RI(0, High(Before));
          P := DPoint(Before[j].x + RI(-1, 1), Before[j].y + RI(-1, 1));
        end
        else
        begin
          j := RI(0, High(Before)); i := RI(0, High(Before));
          P := DPoint((Before[j].x + Before[i].x) / 2 + RI(-3, 3), (Before[j].y + Before[i].y) / 2 + RI(-3, 3));
        end;
        SP := DPoint(Snap10(P.x), Snap10(P.y));
        n := Length(Pg.Handles);
        Changed := Pg.ApplyAction(Act, P, SP);
        Inc(Actions);
        After := Absolute(Pg);
        case Act of
          paAddHandle:
            begin
              Check(Changed and (Length(After) = n + 1), 'Add handle adds exactly one handle');
              if Length(After) = n + 1 then
              begin
                { removing the new handle (the snapped click) must give the old list back, in order; if the click
                  was on an existing handle there are two such points and either may be the new one }
                Found := False;
                for Removed := 0 to High(After) do
                  if Same(After[Removed], SP) then
                  begin
                    Ok2 := True;
                    j := 0;
                    for i := 0 to High(After) do
                      if i <> Removed then
                      begin
                        if (j > High(Before)) or (not Same(After[i], Before[j])) then Ok2 := False;
                        Inc(j);
                      end;
                    if Ok2 then Found := True;
                  end;
                Check(Found, 'Add handle: the new handle is the snapped click and the others keep their order and place');
              end;
            end;
          paDeleteHandle:
            begin
              Check(Length(After) in [n, n - 1], 'Delete handle removes at most one handle');
              if n <= 2 then Check(Length(After) = n, 'a polygon with two handles keeps them');
              if Length(After) = n - 1 then
              begin
                { exactly one of the old handles is gone, the others unchanged and in order }
                j := 0; Removed := -1;
                for i := 0 to High(Before) do
                  if (j <= High(After)) and Same(Before[i], After[j]) then Inc(j)
                  else if Removed < 0 then Removed := i
                  else Check(False, 'Delete handle: more than one handle changed');
                Check(j = Length(After), 'Delete handle: the remaining handles are the old ones in order');
              end
              else
                for j := 0 to High(After) do Check(Same(After[j], Before[j]), 'Delete on a control point moves no handle');
            end;
        else
          begin
            Check(Length(After) = n, 'an arc action does not change the number of handles');
            for j := 0 to High(After) do Check(Same(After[j], Before[j]), 'an arc action moves no handle');
          end;
        end;
      end;
      CheckSound(Pg, 'after step ' + IntToStr(step));
      if (step mod 5 = 0) then RoundTrip(Pg, Opts);
    end;
  finally
    Pg.Free;
  end;
end;

var
  Opts: TDocOptionsBase;
  run: Integer;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  Opts := TDocOptionsBase.Create;
  try
    for run := 1 to 400 do OneRun(Opts);
  finally
    Opts.Free;
  end;
  WriteLn('POLYTEST runs=400 actions=', Actions, ' drags=', Drags, ' roundtrips=', RoundTrips, ' checks=', Checks, ' fails=', Fails);
end.
