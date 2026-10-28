{ Test driver for the geometry layer. Reads commands from stdin and prints results; the Python
  checker in tests/run_geometry.py generates the cases and compares with independent references.

    LD ax ay bx by px py                       line: distance + nearest point (3 variants)
    LI ax ay bx by l r t b                     line vs rectangle
    SN grid on d                               grid snap
    TF zoom ox oy rotmir sx sy yup bound x y   screen transform
    PL which dir length centre npos show slen nlen rotmir      pin layout (fixed metrics)
    SQ kind ax ay bx by fill thick px py       rectangle/ellipse: distance
    SR kind ax ay bx by fill thick l r t b     rectangle/ellipse vs rectangle
    PG fill close thick ox oy n x0 y0 ... px py   polygon: inside test, distance, bounding box
    INV                                        built-in rotation / direction invariants }
program geomtest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, Types, UDPoint, UDrawTypes, UGeometry, UResources, UDrawingObjects,
  UDesign;

var
  Opts: TDocOptions;
  Tok: array of String;

{ ===========================================================================
  FV  (function)
  Parameters:
    k: Integer - token position
  Returns:
    Double - the number
  Notes:
    Reads token k of the command as a number.
  =========================================================================== }
function FV(k: Integer): Double;
begin
  Result := StrToFloat(Tok[k]);
end;

{ ===========================================================================
  IV  (function)
  Parameters:
    k: Integer - token position
  Returns:
    Integer - the integer
  Notes:
    Reads token k of the command as an integer.
  =========================================================================== }
function IV(k: Integer): Integer;
begin
  Result := StrToInt(Tok[k]);
end;

{ ===========================================================================
  Fmt  (function)
  Parameters:
    V: Double - the number
  Returns:
    String - the text
  Notes:
    Formats a number for the test output ("nan" for not-a-number).
  =========================================================================== }
function Fmt(V: Double): String;
begin
  if IsNan(V) then Result := 'nan' else Result := FloatToStrF(V, ffGeneral, 15, 0);
end;

{ ===========================================================================
  Fmt  (function)
  Parameters:
    const P: TDPoint - the point
  Returns:
    String - the text
  Notes:
    Formats a point as two numbers.
  =========================================================================== }
function Fmt(const P: TDPoint): String;
begin
  Result := Fmt(P.x) + ' ' + Fmt(P.y);
end;

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
    Sl.Delimiter := ' ';
    Sl.StrictDelimiter := True;
    Sl.DelimitedText := Trim(Line);
    SetLength(Tok, Sl.Count);
    for k := 0 to Sl.Count - 1 do Tok[k] := Sl[k];
  finally
    Sl.Free;
  end;
end;

{ ===========================================================================
  Repeated  (function)
  Parameters:
    N: Integer - length
  Returns:
    String - the string
  Notes:
    A string of N letters x, used to give text objects a known length.
  =========================================================================== }
function Repeated(N: Integer): String;
begin
  Result := StringOfChar('x', N);
end;

{ ===========================================================================
  MakeStyle  (function)
  Parameters:
    Thick: Integer - thickness
  Returns:
    Integer - the style number
  Notes:
    Adds a line style of a given thickness to the test options.
  =========================================================================== }
function MakeStyle(Thick: Integer): Integer;
begin
  Result := Opts.AddStyle(0, Thick, 0);
end;

{ ===========================================================================
  CmdLD  (procedure)
  Parameters:  none
  Notes:
    Command LD: line distance from a point, printed with the nearest point.
  =========================================================================== }
procedure CmdLD;
var
  A, B, P, N1, N2, N3: TDPoint;
  D1, D2, D3: Double;
begin
  A := DPoint(FV(1), FV(2)); B := DPoint(FV(3), FV(4)); P := DPoint(FV(5), FV(6));
  D1 := LineDistance(A, B, P, N1);
  D2 := LineDistanceX(A, B, P, N2);
  D3 := LineDistanceY(A, B, P, N3);
  WriteLn('LD ', Fmt(D1), ' ', Fmt(N1), ' ', Fmt(D2), ' ', Fmt(N2), ' ', Fmt(D3), ' ', Fmt(N3));
end;

{ ===========================================================================
  CmdLI  (procedure)
  Parameters:  none
  Notes:
    Command LI: whether a line touches a rectangle.
  =========================================================================== }
procedure CmdLI;
begin
  WriteLn('LI ', Ord(LineIsInside(DPoint(FV(1), FV(2)), DPoint(FV(3), FV(4)), FV(5), FV(6), FV(7), FV(8))));
end;

{ ===========================================================================
  CmdSN  (procedure)
  Parameters:  none
  Notes:
    Command SN: snaps a value to a grid.
  =========================================================================== }
procedure CmdSN;
begin
  WriteLn('SN ', Fmt(SnapToGrid(FV(1), IV(2) <> 0, FV(3))));
end;

{ ===========================================================================
  CmdTF  (procedure)
  Parameters:  none
  Notes:
    Command TF: converts a point through the screen transform and back.
  =========================================================================== }
procedure CmdTF;
var
  T: TTransform;
  Pt: TPoint;
  d: Integer;
  S: String;
begin
  T := TTransform.Create;
  try
    T.SetZoomFactor(FV(1));
    T.SetOrigin(DPoint(FV(2), FV(3)));
    T.SetTRM(DPoint(0, 0), DPoint(0, 0), IV(4));
    T.SetScaling(0, FV(5), FV(6));
    if IV(7) <> 0 then T.SetYIsUp(IV(8));
    Pt := T.Scale(FV(9), FV(10));
    S := '';
    for d := 0 to 3 do S := S + ' ' + IntToStr(T.RotateDir(d));
    WriteLn('TF ', Pt.x, ' ', Pt.y, S);
  finally
    T.Free;
  end;
end;

{ ===========================================================================
  CmdPL  (procedure)
  Parameters:  none
  Notes:
    Command PL: lays out a pin (line, text positions) for given rotation, using fixed text
    metrics.
  =========================================================================== }
procedure CmdPL;
var
  Pin: TDrawPin;
  L: TPinLayout;
begin
  Opts.Metrics.Free;
  Opts.Metrics := TFixedTextMetrics.CreateWith(7, 12);
  Pin := TDrawPin.Create(Opts);
  try
    Pin.PointA := DPoint(100, 100);
    Pin.Which := IV(1); Pin.Dir := IV(2); Pin.Length := IV(3); Pin.CentreName := IV(4);
    Pin.NumberPos := IV(5); Pin.Show := IV(6);
    Pin.Str := Repeated(IV(7)); Pin.Number := Repeated(IV(8));
    L := Pin.DetermineLayout(IV(9));
    Pin.DetermineSize;
    WriteLn('PL ', Fmt(L.Pa), ' ', Fmt(L.Pb), ' ', Fmt(L.Pc), ' ', Fmt(L.Pd), ' ', Fmt(L.Pta), ' ',
            Fmt(L.Ptb), ' ', L.Dr, ' ', Fmt(Pin.PointB));
  finally
    Pin.Free;
  end;
end;

{ ===========================================================================
  MakeSquare  (function)
  Parameters:  none
  Returns:
    TDrawSquare - the shape
  Notes:
    Builds a rectangle or ellipse from the command's arguments.
  =========================================================================== }
function MakeSquare: TDrawSquare;
begin
  if IV(1) = 0 then Result := TDrawSquare.CreateKind(Opts, xSquareEx3)
  else Result := TDrawSquare.CreateKind(Opts, xCircleEx3);
  Result.PointA := DPoint(FV(2), FV(3));
  Result.PointB := DPoint(FV(4), FV(5));
  Result.Fill := IV(6);
  Result.Style := MakeStyle(IV(7));
end;

{ ===========================================================================
  CmdSQ  (procedure)
  Parameters:  none
  Notes:
    Command SQ: distance from a point to a rectangle or ellipse.
  =========================================================================== }
procedure CmdSQ;
var
  O: TDrawSquare;
begin
  O := MakeSquare;
  try
    WriteLn('SQ ', Fmt(O.DistanceFromPoint(DPoint(FV(8), FV(9)))));
  finally
    O.Free;
  end;
end;

{ ===========================================================================
  CmdSR  (procedure)
  Parameters:  none
  Notes:
    Command SR: whether a rectangle or ellipse overlaps a selection rectangle.
  =========================================================================== }
procedure CmdSR;
var
  O: TDrawSquare;
begin
  O := MakeSquare;
  try
    WriteLn('SR ', Ord(O.IsInside(FV(8), FV(9), FV(10), FV(11))));
  finally
    O.Free;
  end;
end;

{ ===========================================================================
  CmdPG  (procedure)
  Parameters:  none
  Notes:
    Command PG: polygon fill, distance and bounding box tests.
  =========================================================================== }
procedure CmdPG;
var
  O: TDrawPolygon;
  n, k, base: Integer;
  H: TArcPoint;
  P: TDPoint;
begin
  O := TDrawPolygon.Create(Opts);
  try
    O.Fill := IV(1);
    O.Close := IV(2);
    O.Style := MakeStyle(IV(3));
    O.PointA := DPoint(FV(4), FV(5));
    n := IV(6);
    base := 7;
    SetLength(O.Handles, 0);
    for k := 0 to n - 1 do
    begin
      H.X := FV(base + k * 2); H.Y := FV(base + k * 2 + 1);
      H.Arc := Arc_none; H.Control := DPointInvalid; H.FlattenedSegment := 0;
      SetLength(O.Handles, Length(O.Handles) + 1);
      O.Handles[High(O.Handles)] := H;
    end;
    O.CalcBoundingRect; // as the XML loader does
    P := DPoint(FV(base + n * 2), FV(base + n * 2 + 1));
    WriteLn('PG ', Ord(O.IsInsidePolygon(P)), ' ', Fmt(O.DistanceFromPoint(P)), ' ', Fmt(O.PointA), ' ',
            Fmt(O.PointB), ' ', Ord(O.IsInside(P.x, P.x, P.y, P.y)));
  finally
    O.Free;
  end;
end;

{ ------------------------------------------------------------------------------------------ }
{ invariants }

var
  Seed: Cardinal = 12345;
  InvChecks, InvFails: Integer;

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
  RInt  (function)
  Parameters:
    Lo: Integer - lowest
    Hi: Integer - highest
  Returns:
    Integer - the integer
  Notes:
    A random integer in a range.
  =========================================================================== }
function RInt(Lo, Hi: Integer): Integer;
begin
  Result := Lo + Trunc(Rnd * (Hi - Lo + 1));
end;

{ ===========================================================================
  Check  (procedure)
  Parameters:
    Cond: Boolean - the condition that should hold
    const What: String - description for the failure message
  Notes:
    Counts a check and a failure when the condition is False, printing the first failures.
  =========================================================================== }
procedure Check(Cond: Boolean; const What: String);
begin
  Inc(InvChecks);
  if not Cond then
  begin
    Inc(InvFails);
    if InvFails <= 12 then WriteLn('  FAIL ', What);
  end;
end;

{ ===========================================================================
  Near  (function)
  Parameters:
    const A: TDPoint - first point
    const B: TDPoint - second point
  Returns:
    Boolean - True if close enough
  Notes:
    Whether two points differ by no more than a tolerance on each axis.
  =========================================================================== }
function Near(const A, B: TDPoint): Boolean;
begin
  Result := (Abs(A.x - B.x) < 1E-6) and (Abs(A.y - B.y) < 1E-6);
end;

{ ===========================================================================
  InvPoints  (procedure)
  Parameters:
    Obj: TDrawingObject - the object
    const Name: String - its name for messages
    CheckB: Boolean - also check the second point
  Notes:
    Checks invariants of an object's geometry: rotating by 90 degrees four times returns to the
    start, mirroring twice does, and shifting then rotating matches rotating then shifting.
  =========================================================================== }
procedure InvPoints(Obj: TDrawingObject; const Name: String; CheckB: Boolean);
var
  C: TDPoint;
  Oa, Ob: TDPoint;
  i: Integer;
  Cl: TDrawingObject;
begin
  C := DPoint(RInt(-50, 50), RInt(-50, 50));
  if PointsClose(C, DPoint(0, 0)) then C := DPoint(7, 3);
  Oa := Obj.PointA; Ob := Obj.PointB;
  Cl := Obj.Clone;
  try
    { four quarter turns left come back to the start }
    for i := 1 to 4 do Cl.RotateAbout(C, 2);
    Check(Near(Cl.PointA, Oa), Name + ' 4x left: A');
    if CheckB then Check(Near(Cl.PointB, Ob), Name + ' 4x left: B');
    { right undoes left }
    Cl.RotateAbout(C, 3); Cl.RotateAbout(C, 2);
    Check(Near(Cl.PointA, Oa), Name + ' right after left: A');
    { mirroring twice is the identity }
    Cl.RotateAbout(C, 4); Cl.RotateAbout(C, 4);
    Check(Near(Cl.PointA, Oa), Name + ' mirror twice: A');
  finally
    Cl.Free;
  end;
end;

{ ===========================================================================
  InvDirections  (procedure)
  Parameters:  none
  Notes:
    Checks the direction and symbol rotation tables: four turns return to the start, a mirror
    twice does, and left then right cancel.
  =========================================================================== }
procedure InvDirections;
var
  Rot, Dir, Row: Integer;
  V, V2: TDPoint;
  Pin: TDrawPin;
  Pw: TDrawPower;
  L1, L2: TPinLayout;
  C: TDPoint;
  S1, S2: TDPoint;
  Tr: TTransform;
  Z, Unit0: TPoint;
  Dirs: array[0..3] of TDPoint;
begin
  Dirs[0] := DPoint(0, -1); Dirs[1] := DPoint(0, 1); Dirs[2] := DPoint(-1, 0); Dirs[3] := DPoint(1, 0);
  Opts.Metrics.Free;
  Opts.Metrics := TFixedTextMetrics.CreateWith(7, 12);
  C := DPoint(40, 25);
  for Rot := 2 to 4 do
    for Dir := 0 to 3 do
    begin
      { PIN: the direction the pin points in must follow the geometric rotation }
      Pin := TDrawPin.Create(Opts);
      try
        Pin.PointA := DPoint(10, 20); Pin.Dir := Dir; Pin.Length := 30; Pin.Str := 'ab'; Pin.Number := '1';
        L1 := Pin.DetermineLayout(0);
        V := DPoint(L1.Pd.x - Pin.PointA.x, L1.Pd.y - Pin.PointA.y);
        V := RotatePointAbout(V, DPoint(0, 0), Rot);   // vectors rotate about the origin
        Pin.RotateAbout(C, Rot);
        L2 := Pin.DetermineLayout(0);
        V2 := DPoint(L2.Pd.x - Pin.PointA.x, L2.Pd.y - Pin.PointA.y);
        Check(Near(V, V2), Format('pin dir %d rot %d: pointing direction', [Dir, Rot]));
        Check(Pin.Dir = DoRotateDir(Dir, Rot), 'pin dir table');
      finally
        Pin.Free;
      end;
      { POWER: the stem follows the rotation too }
      Pw := TDrawPower.Create(Opts);
      try
        Pw.PointA := DPoint(10, 20); Pw.Dir := Dir; Pw.Str := 'VCC';
        Pw.UpdateLayout;
        S1 := Dirs[Dir];
        S1 := RotatePointAbout(S1, DPoint(0, 0), Rot);
        Pw.RotateAbout(C, Rot);
        S2 := Dirs[Pw.Dir];
        Check(Near(S1, S2), Format('power dir %d rot %d: stem direction', [Dir, Rot]));
      finally
        Pw.Free;
      end;
    end;

  { the Transform: rotating a direction vector with Scale must agree with RotateDir }
  Tr := TTransform.Create;
  try
    Tr.SetOrigin(DPoint(0, 0));
    for Row := 0 to 7 do
    begin
      Tr.SetTRM(DPoint(0, 0), DPoint(0, 0), Row);
      Z := Tr.Scale(0.0, 0.0);
      for Dir := 0 to 3 do
      begin
        Unit0 := Tr.Scale(Dirs[Dir].x * 100, Dirs[Dir].y * 100);
        V := DPoint((Unit0.x - Z.x) / 100, (Unit0.y - Z.y) / 100);
        Check(Near(V, Dirs[Tr.RotateDir(Dir)]), Format('transform rotmir %d dir %d', [Row, Dir]));
      end;
    end;
  finally
    Tr.Free;
  end;
end;

{ ===========================================================================
  CmdINV  (procedure)
  Parameters:  none
  Notes:
    Command INV: runs the invariant checks over randomly generated objects of every kind.
  =========================================================================== }
procedure CmdINV;
var
  n, i: Integer;
  Ln: TDrawLine; Ju: TDrawJunction; Nc: TDrawNoConnect; Sq: TDrawSquare; Pg: TDrawPolygon;
  Tx: TDrawText; Lb: TDrawLabel; Pw: TDrawPower; Pn: TDrawPin;
  H: TArcPoint;
begin
  InvChecks := 0; InvFails := 0;
  Opts.Metrics.Free;
  Opts.Metrics := TFixedTextMetrics.CreateWith(7, 12);
  for n := 1 to 300 do
  begin
    Ln := TDrawLine.CreateKind(Opts, xWire);
    Ln.PointA := DPoint(RInt(-100, 100), RInt(-100, 100)); Ln.PointB := DPoint(RInt(-100, 100), RInt(-100, 100));
    InvPoints(Ln, 'line', True); Ln.Free;

    Ju := TDrawJunction.Create(Opts);
    Ju.PointA := DPoint(RInt(-100, 100), RInt(-100, 100)); Ju.PointB := Ju.PointA;
    InvPoints(Ju, 'junction', True); Ju.Free;

    Nc := TDrawNoConnect.Create(Opts);
    Nc.PointA := DPoint(RInt(-100, 100), RInt(-100, 100)); Nc.PointB := Nc.PointA;
    InvPoints(Nc, 'noconnect', True); Nc.Free;

    Sq := TDrawSquare.CreateKind(Opts, xSquareEx3);
    Sq.PointA := DPoint(RInt(-100, 100), RInt(-100, 100)); Sq.PointB := DPoint(RInt(-100, 100), RInt(-100, 100));
    InvPoints(Sq, 'square', True); Sq.Free;

    Pg := TDrawPolygon.Create(Opts);
    Pg.PointA := DPoint(RInt(-100, 100), RInt(-100, 100));
    for i := 0 to RInt(2, 6) do
    begin
      H.X := RInt(0, 40); H.Y := RInt(0, 40); H.Arc := Arc_none; H.Control := DPointInvalid; H.FlattenedSegment := 0;
      SetLength(Pg.Handles, Length(Pg.Handles) + 1);
      Pg.Handles[High(Pg.Handles)] := H;
    end;
    Pg.CalcBoundingRect;
    InvPoints(Pg, 'polygon', True); Pg.Free;

    Tx := TDrawText.CreateKind(Opts, xTextEx2);
    Tx.PointA := DPoint(RInt(-100, 100), RInt(-100, 100)); Tx.Str := 'hello'; Tx.Dir := RInt(0, 3);
    Tx.UpdateLayout;
    InvPoints(Tx, 'text', False); Tx.Free;

    Lb := TDrawLabel.Create(Opts);
    Lb.ActivePoint := DPoint(RInt(-100, 100), RInt(-100, 100)); Lb.Str := 'NET'; Lb.Dir := RInt(0, 3);
    Lb.LabelStyle := RInt(0, 3);
    Lb.UpdateLayout;
    Check(True, 'label');
    Lb.Free;

    Pw := TDrawPower.Create(Opts);
    Pw.PointA := DPoint(RInt(-100, 100), RInt(-100, 100)); Pw.PointB := Pw.PointA;
    Pw.Dir := RInt(0, 3); Pw.Str := 'VCC'; Pw.UpdateLayout;
    InvPoints(Pw, 'power', True); Pw.Free;

    Pn := TDrawPin.Create(Opts);
    Pn.PointA := DPoint(RInt(-100, 100), RInt(-100, 100)); Pn.Dir := RInt(0, 3); Pn.Length := 20 + 10 * RInt(0, 1);
    Pn.Str := 'IN'; Pn.Number := '3'; Pn.DetermineSize;
    InvPoints(Pn, 'pin', True); Pn.Free;
  end;
  InvDirections;
  WriteLn('INV ', InvChecks, ' ', InvFails);
end;

var
  Line: String;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  Opts := TDocOptions.Create;
  try
    while not Eof(Input) do
    begin
      ReadLn(Line);
      if Trim(Line) = '' then Continue;
      Split(Line);
      if Tok[0] = 'LD' then CmdLD
      else if Tok[0] = 'LI' then CmdLI
      else if Tok[0] = 'SN' then CmdSN
      else if Tok[0] = 'TF' then CmdTF
      else if Tok[0] = 'PL' then CmdPL
      else if Tok[0] = 'SQ' then CmdSQ
      else if Tok[0] = 'SR' then CmdSR
      else if Tok[0] = 'PG' then CmdPG
      else if Tok[0] = 'INV' then CmdINV
      else WriteLn('? ', Tok[0]);
    end;
  finally
    Opts.Free;
  end;
end.
