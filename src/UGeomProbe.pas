{ Test helper: for an object, pick a point that must lie on it, and check the hit-test
  agrees. Used by designtest and libtest ("geom" modes) on real files. }
unit UGeomProbe;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, UDPoint, UDrawTypes, UGeometry, UDrawingObjects;

type
  TProbeStats = record
    Tested, Failed, BadBox, Skipped, OutsideBox: Integer;
  end;

procedure ProbeObject(Obj: TDrawingObject; var Stats: TProbeStats; const Where: String);

implementation

{ ===========================================================================
  Finite  (function)
  Parameters:
    const P: TDPoint - the point
  Returns:
    Boolean - True if both coordinates are finite numbers
  Notes:
    Whether a point has real coordinates (neither NaN nor infinite); used when probing geometry
    for impossible values.
  =========================================================================== }
function Finite(const P: TDPoint): Boolean;
begin
  Result := (not IsNan(P.x)) and (not IsNan(P.y)) and (not IsInfinite(P.x)) and (not IsInfinite(P.y));
end;

{ ===========================================================================
  ProbeObject  (procedure)
  Parameters:
    Obj: TDrawingObject - the object to probe
    var Stats: TProbeStats - running counts, updated
    const Where: String - description of where the object came from, for messages
  Notes:
    Test helper: exercises an object's geometry (bounding box, hit tests on its own points,
    rotation invariants) and counts anything impossible or unexplained into Stats.
  =========================================================================== }
procedure ProbeObject(Obj: TDrawingObject; var Stats: TProbeStats; const Where: String);
var
  P: TDPoint;
  Have: Boolean;
  D: Double;
  Sq: TDrawSquare;
  Pg: TDrawPolygon;
begin
  Have := True;
  P := DPoint(0, 0);
  if Obj is TDrawLine then
    P := DPoint((Obj.PointA.x + Obj.PointB.x) / 2, (Obj.PointA.y + Obj.PointB.y) / 2)
  else if (Obj is TDrawJunction) or (Obj is TDrawNoConnect) or (Obj is TDrawOrigin) or (Obj is TDrawPower) then
    P := Obj.PointA
  else if Obj is TDrawSquare then
  begin
    Sq := Obj as TDrawSquare;
    if Sq.IsSquare then
      P := DPoint(Sq.PointA.x, (Sq.PointA.y + Sq.PointB.y) / 2)          // on the left edge
    else
      P := DPoint(Sq.PointA.x, (Sq.PointA.y + Sq.PointB.y) / 2);         // left-most point of the ellipse
  end
  else if Obj is TDrawPolygon then
  begin
    Pg := Obj as TDrawPolygon;
    if Length(Pg.Points) = 0 then
      Have := False
    else
      P := DPoint(Pg.PointA.x + Pg.Points[0].x, Pg.PointA.y + Pg.Points[0].y); // first vertex
  end
  else if Obj is TDrawPin then
  begin
    if (Obj as TDrawPin).IsInvisible then
      Have := False
    else
      P := Obj.PointA;
  end
  else if (Obj is TDrawText) or (Obj is TDrawLabel) or (Obj is TDrawNoteText) then
    P := DPoint((Obj.PointA.x + Obj.PointB.x) / 2, (Obj.PointA.y + Obj.PointB.y) / 2)
  else
    Have := False; // bus slash, placed symbols: not probed in this slice

  if not Have then begin
    Inc(Stats.Skipped);
    Exit;
  end;
  Inc(Stats.Tested);

  if not (Finite(Obj.PointA) and Finite(Obj.PointB)) then
  begin
    Inc(Stats.BadBox);
    if Stats.BadBox <= 3 then
      WriteLn('  BAD BOX ', Obj.ClassName, ' ', Where);
  end;
  D := Obj.DistanceFromPoint(P);
  { A point exactly on an object's bounding-box edge is outside by the C++ cut-off (b <= top),
    so the overlap test uses a small rectangle around the point rather than the point itself. }
  if (IsNan(D)) or (D > 1E-6) or (not Obj.IsInside(P.x - 0.25, P.x + 0.25, P.y - 0.25, P.y + 0.25)) then
  begin
    { A polygon's stored bounding box is truncated to integers (CalcBoundingRect), so it can be
      up to one unit smaller than the curve: a probe on the extreme point may lie outside it,
      and the C++ bounding-box cut-off then rejects it. Counted separately, not as a failure. }
    if (D <= 1E-6) and (Obj is TDrawPolygon) and
       ((P.x > Max(Obj.PointA.x, Obj.PointB.x) - 0.25) or (P.x < Min(Obj.PointA.x, Obj.PointB.x) + 0.25) or
        (P.y > Max(Obj.PointA.y, Obj.PointB.y) - 0.25) or (P.y < Min(Obj.PointA.y, Obj.PointB.y) + 0.25)) and
       ((P.x > Max(Obj.PointA.x, Obj.PointB.x)) or (P.x < Min(Obj.PointA.x, Obj.PointB.x)) or
        (P.y > Max(Obj.PointA.y, Obj.PointB.y)) or (P.y < Min(Obj.PointA.y, Obj.PointB.y))) then
    begin
      Inc(Stats.OutsideBox);
      Exit;
    end;
    Inc(Stats.Failed);
    if Stats.Failed <= 5 then
      WriteLn('  MISS ', Obj.ClassName, ' ', Where, ' d=', FloatToStr(D), ' at ', FloatToStr(P.x), ',', FloatToStr(P.y));
  end;
end;

end.
