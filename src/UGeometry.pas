// SPDX-License-Identifier: LGPL-2.1-or-later
{ Geometry foundation: port of DRect.*, DSize.h, LineUtils.cpp, TransformSnap::Snap and the
  Transform class (Transform.cpp / Context.h), the direction tables used by the objects'
  rotate code, and the text-metrics interface the layout code needs.

  Original: Copyright 1994-2019 Matt Pyne, LGPL 2.1+. This port keeps that licence.

  TEXT METRICS. The C++ program measures text with Windows GDI (GetTextExtentPoint32 on a scaled
  "datum" font). That cannot be reproduced exactly elsewhere, so measurement is a plug-in:
  TTextMetrics. This unit supplies
    - TApproxTextMetrics  Arial-like widths from a built-in table; deterministic, no UI needed
    - TFixedTextMetrics   constant width per character and constant height (for tests)
  A Lazarus front end should supply one based on TCanvas.TextExtent. Everything that depends on
  text (pin names, labels, text boxes, power labels, symbol bounding boxes) is therefore only as
  exact as the metrics given. }
unit UGeometry;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, Types, UDPoint, UResources;

type
  TDSize = record
    cx, cy: Double;
  end;

  TDRect = record
    Left, Top, Right, Bottom: Double;
  end;

function DSize(ACx, ACy: Double): TDSize;
function DRect(L, T, R, B: Double): TDRect;
function DRectWidth(const R: TDRect): Double;
function DRectHeight(const R: TDRect): Double;
function DRectNormalized(const R: TDRect): TDRect;
function DRectContains(const R: TDRect; const P: TDPoint): Boolean; // CDRect::PtInRect

{ ---- CDPoint helpers ---- }
function PointAdd(const A, B: TDPoint): TDPoint;
function PointSub(const A, B: TDPoint): TDPoint;
function PointDistance(const A, B: TDPoint): Double;
{ CDPoint::operator== : equal within 0.001 on both axes }
function PointsClose(const A, B: TDPoint): Boolean;

{ ---- CLineUtils (a line from A to B) ---- }
const
  POINT_ON_LINE_DISTANCE = 0.01; // CLineUtils::pointOnLineDistance

function LineDistance(const A, B, P: TDPoint; out Nearest: TDPoint): Double;
function LineDistanceX(const A, B, P: TDPoint; out Nearest: TDPoint): Double;
function LineDistanceY(const A, B, P: TDPoint; out Nearest: TDPoint): Double;
{ Is the line inside, or does it cross, the rectangle? For a point-sized rectangle it
  tests whether the point is on the line. }
function LineIsInside(const A, B: TDPoint; Left, Right, Top, Bottom: Double): Boolean;
function LineIsPointOnLine(const A, B, P: TDPoint; out DistanceAlong: Double): Boolean;
function LinePointAt(const A, B: TDPoint; DistanceAlong: Double): TDPoint;
function LineLength(const A, B: TDPoint): Double;
function LineIsDiagonal(const A, B: TDPoint): Boolean;

{ ---- grid snapping (TransformSnap::Snap) ---- }
function SnapToGrid(Grid: Double; GridSnapOn: Boolean; D: Double): Double;

{ ---- rotation ---- }
{ Rotate a point about C. Dir: 2 = left, 3 = right, 4 = mirror (x); other values leave it. }
function RotatePointAbout(const P, C: TDPoint; Dir: Integer): TDPoint;
{ New direction (0 up, 1 down, 2 left, 3 right) after rotating with NewDir (2, 3 or 4):
  the table shared by pins, power objects and labels. }
function DoRotateDir(OldDir, NewDir: Integer): Integer;
{ Same for placed symbols: rotation/mirror codes 0..7 }
function DoRotateMethod(OldDir, NewDir: Integer): Integer;

{ ---- the screen transform (Transform) ---- }
type
  TTransform = class
  private
    FZoom: Double;
    FScalingX, FScalingY: Double;
    FX, FY: Double;      // internal coordinates of the top left corner (the origin)
    FRotMir: Integer;
    FPixelOffset: TPoint;
    FIsYUp: Boolean;
    FBoundY: Integer;
    function Round(D: Double): Integer;
    function ScaleX(A: Double): Integer;
    function ScaleY(A: Double): Integer;
    function DoubleScale(A: Double): Double;
  public
    constructor Create;
    procedure SetZoomFactor(Z: Double);
    procedure SetOriginX(NewX: Double);
    procedure SetOriginY(NewY: Double);
    procedure SetOrigin(const P: TDPoint);
    procedure SetYIsUp(NewBoundY: Integer);
    procedure SetScaling(Rot: Integer; X, Y: Double);
    procedure GetScaling(Rot: Integer; out X, Y: Double);
    procedure SetPixelOffset(const P: TPoint);
    { Make the transform draw a rotated/mirrored part; returns the old origin }
    function SetTRM(const Os, Bound: TDPoint; Rotate: Integer): TDPoint;
    procedure EndTRM(const Os: TDPoint);
    function RotateDir(Dir: Integer): Integer;
    function GetOrigin: TDPoint;
    function GetScaledOrigin: TDPoint;
    function GetZoomFactor: Double;
    function GetRotMir: Integer;
    function GetIsYUp: Boolean;
    function GetPixelOffset: TPoint;
    { internal coordinates -> window pixels }
    function Scale(X, Y: Double): TPoint; overload;
    function Scale(const P: TDPoint): TPoint; overload;
    function Scale(const R: TDRect): TRect; overload;
    function ScaleDist(Dist: Double): Integer;
    { window pixels -> internal coordinates }
    function DeScaleX(A: Integer): Double;
    function DeScaleY(A: Integer): Double;
    function DeScale(const P: TPoint): TDPoint; overload;
    function DeScale(A: Double): Double; overload;
    function DeScaleSnapped(Grid: Double; GridSnapOn: Boolean; const P: TPoint): TDPoint;
  end;

{ ---- text metrics ---- }
type
  TTextMetrics = class
  public
    constructor Create; virtual;
    { Size of Str drawn in Font, in internal (unzoomed) units. The overbar marker '`' is not
      part of the measured text. }
    function TextExtent(const Str: String; Font: TFontResource): TDSize; virtual; abstract;
  end;

  { Arial-like proportional widths, emulating how the C++ program measures: the font is created
    DatumScale times larger, measured, and the result divided by DatumScale. Per-glyph advances
    and the ascent/descent are rounded to whole pixels at the datum size, as GDI does for hinted
    TrueType text. lfWidth (a font's requested average character width) scales the glyphs
    horizontally the way GDI does. Approximate by design (no kerning, no hinting tables). }
  TApproxTextMetrics = class(TTextMetrics)
  public
    DatumScale: Double;       // CContext::m_datum_scaling (5.0)
    AscentFactor: Double;     // Arial ascent  / em  (1854/2048)
    DescentFactor: Double;    // Arial descent / em  (434/2048)
    AveCharWidthFactor: Double; // Arial xAvgCharWidth / em (904/2048): natural average width
    EmptyHasHeight: Boolean;  // does an empty string measure as (0, height) rather than (0, 0)?
    constructor Create; override;
    function TextExtent(const Str: String; Font: TFontResource): TDSize; override;
  end;

  { Constant advance per character and constant height: for tests }
  TFixedTextMetrics = class(TTextMetrics)
  public
    CharWidth, CharHeight: Double;
    constructor CreateWith(AWidth, AHeight: Double);
    function TextExtent(const Str: String; Font: TFontResource): TDSize; override;
  end;

  TTextMetricsClass = class of TTextMetrics;

var
  { the measurer every new sheet gets (TDocOptionsBase.Create). The Approx one unless the program (unit UTextMetrics) puts the one that measures the real fonts here }
  DefaultTextMetrics: TTextMetricsClass;

implementation

{ ===========================================================================
  TTextMetrics.Create  (constructor)
  Parameters:  none
  Notes:
    Virtual, so that a sheet can make whichever measurer DefaultTextMetrics names.
  =========================================================================== }
constructor TTextMetrics.Create;
begin
  inherited Create;
end;

{ ===========================================================================
  DSize  (function)
  Parameters:
    ACx: Double - width
    ACy: Double - height
  Returns:
    TDSize - the size
  Notes:
    Makes a size from a width and a height.
  =========================================================================== }
function DSize(ACx, ACy: Double): TDSize;
begin
  Result.cx := ACx;
  Result.cy := ACy;
end;

{ ===========================================================================
  DRect  (function)
  Parameters:
    L: Double - left
    T: Double - top
    R: Double - right
    B: Double - bottom
  Returns:
    TDRect - the rectangle
  Notes:
    Makes a rectangle from its edges.
  =========================================================================== }
function DRect(L, T, R, B: Double): TDRect;
begin
  Result.Left := L; Result.Top := T; Result.Right := R; Result.Bottom := B;
end;

{ ===========================================================================
  DRectWidth  (function)
  Parameters:
    const R: TDRect - the rectangle
  Returns:
    Double - the width
  Notes:
    Width of a rectangle (right minus left; negative if it is not normalised).
  =========================================================================== }
function DRectWidth(const R: TDRect): Double;
begin Result := R.Right - R.Left; end;

{ ===========================================================================
  DRectHeight  (function)
  Parameters:
    const R: TDRect - the rectangle
  Returns:
    Double - the height
  Notes:
    Height of a rectangle (bottom minus top; negative if it is not normalised).
  =========================================================================== }
function DRectHeight(const R: TDRect): Double;
begin Result := R.Bottom - R.Top; end;

{ ===========================================================================
  DRectNormalized  (function)
  Parameters:
    const R: TDRect - the rectangle
  Returns:
    TDRect - the normalised rectangle
  Notes:
    Swaps edges where needed so left is not greater than right and top is not greater than
    bottom.
  =========================================================================== }
function DRectNormalized(const R: TDRect): TDRect;
begin
  Result := R;
  if Result.Right < Result.Left then begin
    Result.Left := R.Right;
    Result.Right := R.Left;
  end;
  if Result.Bottom < Result.Top then begin
    Result.Top := R.Bottom;
    Result.Bottom := R.Top;
  end;
end;

{ ===========================================================================
  DRectContains  (function)
  Parameters:
    const R: TDRect - the rectangle
    const P: TDPoint - the point
  Returns:
    Boolean - True if the point is inside
  Notes:
    Whether a point lies inside or on the edge of a rectangle (normalised first).
  =========================================================================== }
function DRectContains(const R: TDRect; const P: TDPoint): Boolean;
var
  N: TDRect;
begin
  N := DRectNormalized(R);
  Result := not ((P.x < N.Left) or (P.x > N.Right) or (P.y < N.Top) or (P.y > N.Bottom));
end;

{ ===========================================================================
  PointAdd  (function)
  Parameters:
    const A: TDPoint - first point
    const B: TDPoint - second point
  Returns:
    TDPoint - A + B
  Notes:
    Adds two points as vectors.
  =========================================================================== }
function PointAdd(const A, B: TDPoint): TDPoint;
begin
  Result := DPoint(A.x + B.x, A.y + B.y);
end;

{ ===========================================================================
  PointSub  (function)
  Parameters:
    const A: TDPoint - first point
    const B: TDPoint - second point
  Returns:
    TDPoint - A - B
  Notes:
    Subtracts one point from another.
  =========================================================================== }
function PointSub(const A, B: TDPoint): TDPoint;
begin
  Result := DPoint(A.x - B.x, A.y - B.y);
end;

{ ===========================================================================
  PointDistance  (function)
  Parameters:
    const A: TDPoint - first point
    const B: TDPoint - second point
  Returns:
    Double - the distance
  Notes:
    Straight-line distance between two points.
  =========================================================================== }
function PointDistance(const A, B: TDPoint): Double;
begin
  Result := Sqrt((B.x - A.x) * (B.x - A.x) + (B.y - A.y) * (B.y - A.y));
end;

{ ===========================================================================
  PointsClose  (function)
  Parameters:
    const A: TDPoint - first point
    const B: TDPoint - second point
  Returns:
    Boolean - True if the points count as the same point
  Notes:
    TinyCAD's point equality: both coordinates within 0.001. The C++ operator== on CDPoint.
  =========================================================================== }
function PointsClose(const A, B: TDPoint): Boolean;
const
  CloseDistance = 0.001;
begin
  Result := (Abs(B.x - A.x) < CloseDistance) and (Abs(B.y - A.y) < CloseDistance);
end;

{ ---- CLineUtils ---- }

{ The three DistanceFromPoint variants share the clamping to the end points; they differ only
  in how the candidate point on the infinite line is chosen. Mode: 0 nearest, 1 same y (find x),
  2 same x (find y). }

{ ===========================================================================
  LineDistanceMode  (function)
  Parameters:
    const A: TDPoint - segment start
    const B: TDPoint - segment end
    const P: TDPoint - the point
    Mode: Integer - 0 normal, 1 measure along X only, 2 measure along Y only
    out Nearest: TDPoint - set to the closest point on the segment
  Returns:
    Double - the distance
  Notes:
    Distance from a point to a line segment (a port of CLineUtils): horizontal and vertical
    lines, diagonals, and the X-only and Y-only variants used when snapping to diagonal wires.
    Also gives the nearest point on the line.
  =========================================================================== }
function LineDistanceMode(const A, B, P: TDPoint; Mode: Integer; out Nearest: TDPoint): Double;
var
  X, Y, G, H, Dx, Dy: Double;
begin
  if A.y = B.y then
  begin
    X := P.x; Y := A.y;           // horizontal
  end
  else if A.x = B.x then
  begin
    X := A.x; Y := P.y;           // vertical
  end
  else if Mode = 2 then
  begin
    G := (B.y - A.y) / (B.x - A.x);   // y = g * x + h
    H := B.y - G * B.x;
    X := P.x;
    Y := G * X + H;
  end
  else
  begin
    G := (B.x - A.x) / (B.y - A.y);   // x = g * y + h
    H := B.x - G * B.y;
    if Mode = 1 then
    begin
      Y := P.y;
      X := G * Y + H;
    end
    else
    begin
      Y := (P.y + P.x * G - G * H) / (G * G + 1.0);
      X := G * Y + H;
    end;
  end;

  { we have computed against an infinite line: bring points beyond the ends back onto it }
  if X < Min(A.x, B.x) then
  begin
    if A.x < B.x then begin
      X := A.x;
      Y := A.y;
    end else begin
      X := B.x;
      Y := B.y;
    end;
  end
  else if X > Max(A.x, B.x) then
  begin
    if A.x > B.x then begin
      X := A.x;
      Y := A.y;
    end else begin
      X := B.x;
      Y := B.y;
    end;
  end;
  if Y < Min(A.y, B.y) then
  begin
    if A.y < B.y then begin
      X := A.x;
      Y := A.y;
    end else begin
      X := B.x;
      Y := B.y;
    end;
  end
  else if Y > Max(A.y, B.y) then
  begin
    if A.y > B.y then begin
      X := A.x;
      Y := A.y;
    end else begin
      X := B.x;
      Y := B.y;
    end;
  end;

  Nearest := DPoint(X, Y);
  Dx := P.x - X;
  Dy := P.y - Y;
  Result := Sqrt(Dx * Dx + Dy * Dy);
end;

{ ===========================================================================
  LineDistance  (function)
  Parameters:
    const A: TDPoint - segment start
    const B: TDPoint - segment end
    const P: TDPoint - the point
    out Nearest: TDPoint - set to the closest point on the segment
  Returns:
    Double - the distance
  Notes:
    Distance from a point to a line segment, with the nearest point.
  =========================================================================== }
function LineDistance(const A, B, P: TDPoint; out Nearest: TDPoint): Double;
begin
  Result := LineDistanceMode(A, B, P, 0, Nearest);
end;

{ ===========================================================================
  LineDistanceX  (function)
  Parameters:
    const A: TDPoint - segment start
    const B: TDPoint - segment end
    const P: TDPoint - the point
    out Nearest: TDPoint - set to the nearest point
  Returns:
    Double - the distance
  Notes:
    Like LineDistance but measured horizontally (used to snap to diagonal wires).
  =========================================================================== }
function LineDistanceX(const A, B, P: TDPoint; out Nearest: TDPoint): Double;
begin
  Result := LineDistanceMode(A, B, P, 1, Nearest);
end;

{ ===========================================================================
  LineDistanceY  (function)
  Parameters:
    const A: TDPoint - segment start
    const B: TDPoint - segment end
    const P: TDPoint - the point
    out Nearest: TDPoint - set to the nearest point
  Returns:
    Double - the distance
  Notes:
    Like LineDistance but measured vertically (used to snap to diagonal wires).
  =========================================================================== }
function LineDistanceY(const A, B, P: TDPoint; out Nearest: TDPoint): Double;
begin
  Result := LineDistanceMode(A, B, P, 2, Nearest);
end;

{ ===========================================================================
  WhichArea  (function)
  Parameters:
    const P: TDPoint - a point, in design units
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Integer
  Notes:
    Which of the nine areas around the rectangle a point lies in (CLineUtils::WhichArea)
  =========================================================================== }
function WhichArea(const P: TDPoint; Left, Right, Top, Bottom: Double): Integer;
begin
  Result := 0;
  if P.x < Left then
    Result := Result or 1
  else if P.x > Right then
    Result := Result or 2;
  if P.y > Bottom then
    Result := Result or 4
  else if P.y < Top then
    Result := Result or 8;
end;

{ ===========================================================================
  RIsInside  (function)
  Parameters:
    const P1: TDPoint - segment start
    const P2: TDPoint - segment end
    Left: Double - rectangle left
    Right: Double - rectangle right
    Top: Double - rectangle top
    Bottom: Double - rectangle bottom
  Returns:
    Boolean - True if the segment crosses or touches the rectangle
  Notes:
    Recursive test of whether a segment passes through a rectangle (CLineUtils::IsInside):
    classifies both ends by area and, when undecided, splits the segment in two.
  =========================================================================== }
function RIsInside(const P1, P2: TDPoint; Left, Right, Top, Bottom: Double): Boolean;
var
  Aa, Ab: Integer;
  Mid: TDPoint;
begin
  Aa := WhichArea(P1, Left, Right, Top, Bottom);
  Ab := WhichArea(P2, Left, Right, Top, Bottom);
  if (Aa = 0) or (Ab = 0) then begin
    Result := True;
    Exit;
  end;  // trivially accepted
  if (Aa and Ab) <> 0 then begin
    Result := False;
    Exit;
  end;     // trivially rejected
  { cannot be decided: split in two and try each half }
  Mid := DPoint((P1.x + P2.x) / 2.0, (P1.y + P2.y) / 2.0);
  Result := ((not PointsClose(Mid, P2)) and RIsInside(P1, Mid, Left, Right, Top, Bottom)) or
            ((not PointsClose(Mid, P1)) and RIsInside(Mid, P2, Left, Right, Top, Bottom));
end;

{ ===========================================================================
  LineIsInside  (function)
  Parameters:
    const A: TDPoint - segment start
    const B: TDPoint - segment end
    Left: Double - rectangle left
    Right: Double - rectangle right
    Top: Double - rectangle top
    Bottom: Double - rectangle bottom
  Returns:
    Boolean - True if they touch
  Notes:
    Whether a segment touches a rectangle; a degenerate rectangle (one point) is a click test
    within the point-on-line distance.
  =========================================================================== }
function LineIsInside(const A, B: TDPoint; Left, Right, Top, Bottom: Double): Boolean;
var
  D: TDPoint;
begin
  if (Left = Right) and (Top = Bottom) then
    Result := LineDistance(A, B, DPoint(Right, Top), D) < POINT_ON_LINE_DISTANCE
  else
    Result := RIsInside(A, B, Left, Right, Top, Bottom);
end;

{ ===========================================================================
  LineIsPointOnLine  (function)
  Parameters:
    const A: TDPoint - segment start
    const B: TDPoint - segment end
    const P: TDPoint - the point
    out DistanceAlong: Double - set to the fraction along the segment
  Returns:
    Boolean - True if the point is on the segment
  Notes:
    Whether a point lies on a segment (within the point-on-line distance, 0.01) and how far
    along it, from 0 at A to 1 at B.  A segment of no length gives 0 (the caller must not use it as a fraction).
  =========================================================================== }
function LineIsPointOnLine(const A, B, P: TDPoint; out DistanceAlong: Double): Boolean;
var
  D: TDPoint;
  Len, Mid: Double;
begin
  Result := False;
  DistanceAlong := 0;
  if LineDistance(A, B, P, D) <= POINT_ON_LINE_DISTANCE then
  begin
    Len := Sqrt((A.x - B.x) * (A.x - B.x) + (A.y - B.y) * (A.y - B.y));
    Mid := Sqrt((A.x - P.x) * (A.x - P.x) + (A.y - P.y) * (A.y - P.y));
    if Len = 0 then
      DistanceAlong := 0      { a segment of no length (C++ divides 0 by 0 and gets a NaN; Pascal would raise EZeroDivide/EInvalidOp) }
    else
      DistanceAlong := Mid / Len;
    Result := True;
  end;
end;

{ ===========================================================================
  LinePointAt  (function)
  Parameters:
    const A: TDPoint - segment start
    const B: TDPoint - segment end
    DistanceAlong: Double - 0 = A, 1 = B
  Returns:
    TDPoint - the point
  Notes:
    The point a fraction of the way along a segment (clamped to the ends).
  =========================================================================== }
function LinePointAt(const A, B: TDPoint; DistanceAlong: Double): TDPoint;
begin
  if DistanceAlong <= 0.0 then begin
    Result := A;
    Exit;
  end;
  if DistanceAlong >= 1.0 then begin
    Result := B;
    Exit;
  end;
  Result := DPoint((B.x - A.x) * DistanceAlong + A.x, (B.y - A.y) * DistanceAlong + A.y);
end;

{ ===========================================================================
  LineLength  (function)
  Parameters:
    const A: TDPoint - segment start
    const B: TDPoint - segment end
  Returns:
    Double - the length
  Notes:
    Length of a segment.
  =========================================================================== }
function LineLength(const A, B: TDPoint): Double;
begin
  Result := Sqrt((A.x - B.x) * (A.x - B.x) + (A.y - B.y) * (A.y - B.y));
end;

{ ===========================================================================
  LineIsDiagonal  (function)
  Parameters:
    const A: TDPoint - segment start
    const B: TDPoint - segment end
  Returns:
    Boolean - True if diagonal
  Notes:
    Whether a segment is neither horizontal nor vertical.
  =========================================================================== }
function LineIsDiagonal(const A, B: TDPoint): Boolean;
begin
  Result := (A.x <> B.x) and (A.y <> B.y);
end;

{ ---- snapping ---- }

{ ===========================================================================
  SnapToGrid  (function)
  Parameters:
    Grid: Double - grid spacing
    GridSnapOn: Boolean - whether snapping is enabled
    D: Double - the coordinate
  Returns:
    Double - the snapped value
  Notes:
    Rounds a coordinate to the nearest grid line (halves round up); unchanged when snapping is
    off or the grid is 0. TinyCAD's Transform::Snap.
  =========================================================================== }
function SnapToGrid(Grid: Double; GridSnapOn: Boolean; D: Double): Double;
var
  A: Double;
begin
  if (not GridSnapOn) or (Grid = 0) then begin
    Result := D;
    Exit;
  end;
  A := Floor(D / Grid) * Grid;
  if (D - A) * 2 > Grid then
    A := A + Grid;
  Result := A;
end;

{ ---- rotation ---- }

{ ===========================================================================
  RotatePointAbout  (function)
  Parameters:
    const P: TDPoint - the point
    const C: TDPoint - the centre
    Dir: Integer - rotation / mirror code
  Returns:
    TDPoint - the new position
  Notes:
    Rotates or mirrors a point about a centre point: 2 and 3 turn it left and right, 4 mirrors
    left to right, and so on for the codes TinyCAD uses.
  =========================================================================== }
function RotatePointAbout(const P, C: TDPoint; Dir: Integer): TDPoint;
var
  Q: TDPoint;
begin
  Q := DPoint(P.x - C.x, P.y - C.y);
  case Dir of
    2: Q := DPoint(Q.y, -Q.x);
    3: Q := DPoint(-Q.y, Q.x);
    4: Q := DPoint(-Q.x, Q.y);
  end;
  Result := DPoint(Q.x + C.x, Q.y + C.y);
end;

{ ===========================================================================
  DoRotateDir  (function)
  Parameters:
    OldDir: Integer - current direction 0-3
    NewDir: Integer - rotation 2, 3 or 4
  Returns:
    Integer - the new direction 0-3 (up, down, left, right)
  Notes:
    The new direction of a pin, power symbol or label after a rotation or mirror (table taken
    from TinyCAD).
  =========================================================================== }
function DoRotateDir(OldDir, NewDir: Integer): Integer;
const
  { rows: current direction 0..3 (up, down, left, right); columns: new rotation 2, 3, 4 }
  Table: array[0..11] of Integer = (2, 3, 0,
                                    3, 2, 1,
                                    1, 0, 3,
                                    0, 1, 2);
begin
  Result := Table[(NewDir - 2) + OldDir * 3];
end;

{ ===========================================================================
  DoRotateMethod  (function)
  Parameters:
    OldDir: Integer - current state 0-7
    NewDir: Integer - rotation 2, 3 or 4
  Returns:
    Integer - the new state
  Notes:
    The new rotation / mirror state (0-7) of a placed symbol after a further rotation or mirror
    (table taken from TinyCAD).
  =========================================================================== }
function DoRotateMethod(OldDir, NewDir: Integer): Integer;
const
  Table: array[0..23] of Integer = (6, 3, 4,   // 0 up
                                    7, 2, 5,   // 1 down
                                    1, 4, 3,   // 2 left
                                    0, 5, 2,   // 3 right
                                    2, 7, 0,   // 4 up + mirror
                                    3, 6, 1,   // 5 down + mirror
                                    5, 0, 7,   // 6 left + mirror
                                    4, 1, 6);  // 7 right + mirror
begin
  Result := Table[(NewDir - 2) + OldDir * 3];
end;

{ ---- TTransform ---- }

{ ===========================================================================
  TTransform.Create  (constructor)
  Parameters:  none
  Notes:
    Creates a transform with no origin offset, zoom 1 and no scaling, as TinyCAD's Transform
    does.
  =========================================================================== }
constructor TTransform.Create;
begin
  inherited Create;
  SetOriginX(-1);
  SetOriginY(-1);
  FZoom := 1.0;
  FRotMir := 0;
  FIsYUp := False;
  FBoundY := 0;
  FScalingX := 1.0;
  FScalingY := 1.0;
  FPixelOffset := Point(0, 0);
end;

{ ===========================================================================
  TTransform.Round  (function)
  Parameters:
    D: Double - the number
  Returns:
    Integer - the rounded value
  Notes:
    Rounds to the nearest integer, halves away from zero, as the C++ code does.
  =========================================================================== }
function TTransform.Round(D: Double): Integer;
begin
  { Efficient round to nearest: static_cast<int> truncates towards zero }
  if D > -0.5 then
    Result := Trunc(D + 0.5)
  else
    Result := Trunc(D - 0.5);
end;

{ ===========================================================================
  TTransform.DoubleScale  (function)
  Parameters:
    A: Double - length in design units
  Returns:
    Double - the scaled length
  Notes:
    Multiplies a length by the zoom factor without rounding.
  =========================================================================== }
function TTransform.DoubleScale(A: Double): Double;
begin
  Result := A * FZoom;
end;

{ ===========================================================================
  TTransform.ScaleX  (function)
  Parameters:
    A: Double - design x
  Returns:
    Integer - pixel x
  Notes:
    Design x to pixel x: applies the symbol scaling, subtracts the origin, multiplies by the
    zoom and adds the pixel offset.
  =========================================================================== }
function TTransform.ScaleX(A: Double): Integer;
begin
  Result := Round(DoubleScale(A * FScalingX - FX)) + FPixelOffset.x;
end;

{ ===========================================================================
  TTransform.ScaleY  (function)
  Parameters:
    A: Double - design y
  Returns:
    Integer - pixel y
  Notes:
    Design y to pixel y (flipped when the y axis points up, as inside a symbol view).
  =========================================================================== }
function TTransform.ScaleY(A: Double): Integer;
begin
  if FIsYUp then
    Result := Round(-DoubleScale(A * FScalingY - FY)) - FBoundY
  else
    Result := Round(DoubleScale(A * FScalingY - FY));
  Result := Result + FPixelOffset.y;
end;

{ ===========================================================================
  TTransform.SetZoomFactor  (procedure)
  Parameters:
    Z: Double - the zoom factor
  Notes:
    Sets the zoom (pixels per design unit).
  =========================================================================== }
procedure TTransform.SetZoomFactor(Z: Double); begin FZoom := Z; end;

{ ===========================================================================
  TTransform.SetOriginX  (procedure)
  Parameters:
    NewX: Double - the x
  Notes:
    Sets the design x that is at the left edge of the view.
  =========================================================================== }
procedure TTransform.SetOriginX(NewX: Double); begin FX := NewX; end;

{ ===========================================================================
  TTransform.SetOriginY  (procedure)
  Parameters:
    NewY: Double - the y
  Notes:
    Sets the design y that is at the top edge of the view.
  =========================================================================== }
procedure TTransform.SetOriginY(NewY: Double); begin FY := NewY; end;

{ ===========================================================================
  TTransform.SetOrigin  (procedure)
  Parameters:
    const P: TDPoint - the point
  Notes:
    Sets the design point at the top left of the view.
  =========================================================================== }
procedure TTransform.SetOrigin(const P: TDPoint); begin
  FX := P.x;
  FY := P.y;
end;

{ ===========================================================================
  TTransform.SetYIsUp  (procedure)
  Parameters:
    NewBoundY: Integer - the symbol's height in pixels
  Notes:
    Makes y point upwards (used while drawing inside a symbol view).
  =========================================================================== }
procedure TTransform.SetYIsUp(NewBoundY: Integer); begin
  FIsYUp := True;
  FBoundY := NewBoundY;
end;

{ ===========================================================================
  TTransform.SetPixelOffset  (procedure)
  Parameters:
    const P: TPoint - the offset in pixels
  Notes:
    Adds a fixed pixel offset to every converted position.
  =========================================================================== }
procedure TTransform.SetPixelOffset(const P: TPoint); begin FPixelOffset := P; end;

{ ===========================================================================
  TTransform.GetPixelOffset  (function)
  Parameters:  none
  Returns:
    TPoint - the offset in pixels
  Notes:
    The fixed pixel offset.
  =========================================================================== }
function TTransform.GetPixelOffset: TPoint; begin Result := FPixelOffset; end;

{ ===========================================================================
  TTransform.GetOrigin  (function)
  Parameters:  none
  Returns:
    TDPoint - the origin
  Notes:
    The design point at the top left of the view.
  =========================================================================== }
function TTransform.GetOrigin: TDPoint; begin Result := DPoint(FX, FY); end;

{ ===========================================================================
  TTransform.GetScaledOrigin  (function)
  Parameters:  none
  Returns:
    TDPoint - the scaled origin
  Notes:
    The origin after the symbol scaling is applied.
  =========================================================================== }
function TTransform.GetScaledOrigin: TDPoint; begin Result := DPoint(DoubleScale(FX), DoubleScale(FY)); end;

{ ===========================================================================
  TTransform.GetZoomFactor  (function)
  Parameters:  none
  Returns:
    Double - the zoom factor
  Notes:
    The zoom (pixels per design unit).
  =========================================================================== }
function TTransform.GetZoomFactor: Double; begin Result := FZoom; end;

{ ===========================================================================
  TTransform.GetRotMir  (function)
  Parameters:  none
  Returns:
    Integer - the state
  Notes:
    The current rotation / mirror state (0-7) set up by SetTRM.
  =========================================================================== }
function TTransform.GetRotMir: Integer; begin Result := FRotMir; end;

{ ===========================================================================
  TTransform.GetIsYUp  (function)
  Parameters:  none
  Returns:
    Boolean - True when y points up
  Notes:
    Whether y is currently inverted (true while drawing a symbol view).
  =========================================================================== }
function TTransform.GetIsYUp: Boolean; begin Result := FIsYUp; end;

{ ===========================================================================
  TTransform.SetScaling  (procedure)
  Parameters:
    Rot: Integer - rotation / mirror state
    X: Double - x scale
    Y: Double - y scale
  Notes:
    Sets the x and y scaling of a placed symbol, swapped when the symbol is rotated a quarter
    turn.
  =========================================================================== }
procedure TTransform.SetScaling(Rot: Integer; X, Y: Double);
begin
  case Rot and 3 of
    0, 1: begin
      FScalingX := X;
      FScalingY := Y;
    end;
    2, 3: begin
      FScalingX := Y;
      FScalingY := X;
    end;
  end;
end;

{ ===========================================================================
  TTransform.GetScaling  (procedure)
  Parameters:
    Rot: Integer - rotation / mirror state
    out X: Double - set to the x scale
    out Y: Double - set to the y scale
  Notes:
    Reads the current x and y scaling the way SetScaling stored it.
  =========================================================================== }
procedure TTransform.GetScaling(Rot: Integer; out X, Y: Double);
begin
  case Rot and 3 of
    0, 1: begin
      X := FScalingX;
      Y := FScalingY;
    end;
  else
    begin
      Y := FScalingX;
      X := FScalingY;
    end;
  end;
end;

{ ===========================================================================
  TTransform.SetTRM  (function)
  Parameters:
    const Os: TDPoint - where the symbol is placed
    const Bound: TDPoint - the symbol's size (its top right)
    Rotate: Integer - rotation / mirror state 0-7
  Returns:
    TDPoint - the previous origin
  Notes:
    Starts drawing inside a placed symbol: sets translation, rotation and mirror from the
    symbol's position, size and state, and returns the previous origin to restore with EndTRM.
  =========================================================================== }
function TTransform.SetTRM(const Os, Bound: TDPoint; Rotate: Integer): TDPoint;
begin
  Result := DPoint(FX, FY);
  FX := FX - Os.x;
  FY := FY - Os.y;
  FRotMir := Rotate;
  { offset given the rotation and bounding box }
  case FRotMir and 3 of
    1: FY := FY - Bound.y;  // down
    3: FX := FX - Bound.y;  // right
  end;
  if (FRotMir and 4) <> 0 then
    case FRotMir and 3 of
      0, 1: FX := FX - Bound.x;
      2, 3: FY := FY - Bound.x;
    end;
end;

{ ===========================================================================
  TTransform.EndTRM  (procedure)
  Parameters:
    const Os: TDPoint - the origin SetTRM returned
  Notes:
    Ends drawing inside a symbol by restoring the previous origin and clearing the rotation.
  =========================================================================== }
procedure TTransform.EndTRM(const Os: TDPoint);
begin
  FRotMir := 0;
  FX := Os.x;
  FY := Os.y;
end;

{ ===========================================================================
  TTransform.Scale  (function)
  Parameters:
    X: Double - design x
    Y: Double - design y
  Returns:
    TPoint - the pixel position
  Notes:
    Design position to pixel position.
  =========================================================================== }
function TTransform.Scale(X, Y: Double): TPoint;
var
  T: Double;
begin
  if (FRotMir and 4) <> 0 then
    X := -X;  // mirror
  case FRotMir and 3 of
    1: Y := -Y;
    2: begin
      T := X;
      X := Y;
      Y := T;
    end;
    3: begin
      T := X;
      X := -Y;
      Y := T;
    end;
  end;
  Result := Point(ScaleX(X), ScaleY(Y));
end;

{ ===========================================================================
  TTransform.Scale  (function)
  Parameters:
    const P: TDPoint - the design point
  Returns:
    TPoint - the pixel position
  Notes:
    Design point to pixel position.
  =========================================================================== }
function TTransform.Scale(const P: TDPoint): TPoint;
begin
  Result := Scale(P.x, P.y);
end;

{ ===========================================================================
  TTransform.Scale  (function)
  Parameters:
    const R: TDRect - the design rectangle
  Returns:
    TRect - the pixel rectangle
  Notes:
    Design rectangle to pixel rectangle.
  =========================================================================== }
function TTransform.Scale(const R: TDRect): TRect;
var
  A, B: TPoint;
begin
  A := Scale(DPoint(R.Left, R.Top));
  B := Scale(DPoint(R.Right, R.Bottom));
  Result := Rect(A.x, A.y, B.x, B.y);
end;

{ ===========================================================================
  TTransform.ScaleDist  (function)
  Parameters:
    Dist: Double - length in design units
  Returns:
    Integer - pixels
  Notes:
    A length in design units as whole pixels.
  =========================================================================== }
function TTransform.ScaleDist(Dist: Double): Integer;
begin
  Result := ScaleX(Dist);
end;

{ ===========================================================================
  TTransform.RotateDir  (function)
  Parameters:
    Dir: Integer - direction 0-3 in the symbol
  Returns:
    Integer - the direction to draw with
  Notes:
    A direction after the current rotation / mirror, so pins and text keep reading correctly
    inside a rotated symbol.
  =========================================================================== }
function TTransform.RotateDir(Dir: Integer): Integer;
const
  { rows: dir 0..3, columns: current rotation 0..3 }
  Table: array[0..15] of Integer = (0, 1, 2, 3,
                                    1, 0, 3, 2,
                                    2, 2, 0, 0,
                                    3, 3, 1, 1);
begin
  if (FRotMir and 4) <> 0 then
  begin
    if Dir = 3 then
      Dir := 2
    else if Dir = 2 then
      Dir := 3;
  end;
  Result := Table[(FRotMir and 3) + (Dir and 3) * 4];
end;

{ ===========================================================================
  TTransform.DeScaleX  (function)
  Parameters:
    A: Integer - pixel x
  Returns:
    Double - design x
  Notes:
    Pixel x to design x.
  =========================================================================== }
function TTransform.DeScaleX(A: Integer): Double;
begin
  Result := (A / FZoom) + FX;
end;

{ ===========================================================================
  TTransform.DeScaleY  (function)
  Parameters:
    A: Integer - pixel y
  Returns:
    Double - design y
  Notes:
    Pixel y to design y.
  =========================================================================== }
function TTransform.DeScaleY(A: Integer): Double;
begin
  Result := (A / FZoom) + FY;
end;

{ ===========================================================================
  TTransform.DeScale  (function)
  Parameters:
    const P: TPoint - pixel position
  Returns:
    TDPoint - the design point
  Notes:
    Pixel position to design point.
  =========================================================================== }
function TTransform.DeScale(const P: TPoint): TDPoint;
begin
  Result := DPoint(DeScaleX(P.x), DeScaleY(P.y));
end;

{ ===========================================================================
  TTransform.DeScale  (function)
  Parameters:
    A: Double - length in pixels
  Returns:
    Double - length in design units
  Notes:
    A length in pixels to design units.
  =========================================================================== }
function TTransform.DeScale(A: Double): Double;
begin
  Result := A / FZoom;
end;

{ ===========================================================================
  TTransform.DeScaleSnapped  (function)
  Parameters:
    Grid: Double - grid spacing
    GridSnapOn: Boolean - whether snapping is on
    const P: TPoint - pixel position
  Returns:
    TDPoint - the snapped design point
  Notes:
    Pixel position to design point, snapped to the grid.
  =========================================================================== }
function TTransform.DeScaleSnapped(Grid: Double; GridSnapOn: Boolean; const P: TPoint): TDPoint;
begin
  Result := DPoint(SnapToGrid(Grid, GridSnapOn, DeScaleX(P.x)),
                   SnapToGrid(Grid, GridSnapOn, DeScaleY(P.y)));
end;

{ ---- text metrics ---- }

const
  { Arial advance widths for ASCII 32..126, in 1/1000 em }
  ArialWidths: array[32..126] of Integer = (
    278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,   // space .. /
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,   // 0 .. ?
    1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,  // @ .. O
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,   // P .. _
    333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,   // ` .. o
    556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584);       // p .. ~

{ ===========================================================================
  RoundHalfUp  (function)
  Parameters:
    X: Double - the number
  Returns:
    Double - the rounded value
  Notes:
    Rounds halves up (toward positive infinity), unlike Pascal's Round which rounds halves to
    even.
  =========================================================================== }
function RoundHalfUp(X: Double): Double;
begin
  Result := Floor(X + 0.5); // (Pascal's Round is banker's rounding; GDI rounds halves up)
end;

{ ===========================================================================
  TApproxTextMetrics.Create  (constructor)
  Parameters:  none
  Notes:
    Creates the default text measurer, which approximates Windows' Arial measuring: character
    advance widths, the 5x "datum" scale and per-glyph rounding.
  =========================================================================== }
constructor TApproxTextMetrics.Create;
begin
  inherited Create;
  DatumScale := 5.0;
  AscentFactor := 1854 / 2048;
  DescentFactor := 434 / 2048;
  AveCharWidthFactor := 904 / 2048;
  EmptyHasHeight := False;
end;

{ ===========================================================================
  TApproxTextMetrics.TextExtent  (function)
  Parameters:
    const Str: String - the text
    Font: TFontResource - the font resource
  Returns:
    TDSize - width and height in design units
  Notes:
    Measures text in a font: width from per-character advances (scaled by the font height and
    any requested width) and height from the font height. An empty string measures 0 by 0, as
    GDI does. Geometry that depends on text size (reference points, label boxes) uses this.
  =========================================================================== }
function TApproxTextMetrics.TextExtent(const Str: String; Font: TFontResource): TDSize;
var
  Em, EmD, W, WidthScale, Natural: Double;
  i, C, N: Integer;
begin
  Em := Abs(Font.Height);
  if Em = 0 then
    Em := 13;
  EmD := Trunc(Em * DatumScale);   // the datum font height in pixels
  if EmD < 1 then
    EmD := 1;
  { lfWidth asks for an average character width: GDI scales the glyphs to match it }
  WidthScale := 1.0;
  if Font.Width <> 0 then
  begin
    Natural := RoundHalfUp(AveCharWidthFactor * EmD);
    if Natural > 0 then
      WidthScale := Trunc(Font.Width * DatumScale) / Natural;
  end;
  W := 0;
  N := 0;
  for i := 1 to Length(Str) do
  begin
    if Str[i] = '`' then
      Continue; // overbar marker is not measured
    Inc(N);
    C := Ord(Str[i]);
    if (C >= 32) and (C <= 126) then
      W := W + RoundHalfUp(ArialWidths[C] / 1000.0 * EmD * WidthScale)  // hinted advance: whole pixels
    else
      W := W + RoundHalfUp(556 / 1000.0 * EmD * WidthScale);
  end;
  if (N = 0) and (not EmptyHasHeight) then
  begin
    Result.cx := 0;
    Result.cy := 0;
    Exit;
  end;
  Result.cx := W / DatumScale;
  Result.cy := (RoundHalfUp(AscentFactor * EmD) + RoundHalfUp(DescentFactor * EmD)) / DatumScale;
end;

{ ===========================================================================
  TFixedTextMetrics.CreateWith  (constructor)
  Parameters:
    AWidth: Double - width of one character
    AHeight: Double - height of a line
  Notes:
    Creates a test measurer where every character has the same width and every line the same
    height.
  =========================================================================== }
constructor TFixedTextMetrics.CreateWith(AWidth, AHeight: Double);
begin
  inherited Create;
  CharWidth := AWidth;
  CharHeight := AHeight;
end;

{ ===========================================================================
  TFixedTextMetrics.TextExtent  (function)
  Parameters:
    const Str: String - the text
    Font: TFontResource - the font resource (ignored)
  Returns:
    TDSize - the size
  Notes:
    Width is characters times the fixed width; height is the fixed height. Used so tests get
    exact, predictable results.
  =========================================================================== }
function TFixedTextMetrics.TextExtent(const Str: String; Font: TFontResource): TDSize;
var
  i, N: Integer;
begin
  N := 0;
  for i := 1 to Length(Str) do
    if Str[i] <> '`' then
      Inc(N);
  Result.cx := N * CharWidth;
  Result.cy := CharHeight;
end;

initialization
  DefaultTextMetrics := TApproxTextMetrics;

end.
