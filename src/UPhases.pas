unit UPhases;

{$mode ObjFPC}{$H+}

{ 3-phase buses (a TyCAD extension of TinyCAD's bus).

  A 3-phase bus is three ordinary bus wires side by side. The one the person draws is the middle wire (Phase 0); the program makes the other two (Phase -1 and 1) at
  a set distance (PhaseSpacing) either side of it, left and right of the way it was drawn, with the corners mitred. The three share a Group, which is what makes
  a click on one of them select all three. Nothing else ties them together, so a program that does not know about phases (TinyCAD) sees three buses.

  The wires say what they should be (Phases 1 or 3, PhaseSpacing) and ReconcilePhases makes the drawing agree: a new bus that was drawn for 3 phases gets a Group and its
  two companions, a group whose spacing was changed has its outer wires made again, a group changed to 1 phase loses its outer wires. A new bus that touches the middle
  wire of a group joins that group (it is the same bus, going on).

  Licence: LGPL 2.1 or later, as the rest of this port. }

interface

uses
  Classes, SysUtils, Math, UDPoint, UGeometry, UDrawTypes, UDrawingObjects, UDesign;

type
  TPhaseSegment = record
    A, B: TDPoint;
  end;
  TPhaseSegments = array of TPhaseSegment;

{ the segments Side (-1 left, 1 right of the way the chain runs) of a chain of segments, Spacing away, corners mitred where exactly two segments meet; the result has the
  same order and the same direction of each segment as Mid }
function OffsetSegments(const Mid: TPhaseSegments; Spacing: Double; Side: Integer): TPhaseSegments;
{ Makes the drawing agree with what the buses of the sheet say they are (see the unit's comment). Objects it removes are freed and put in Removed (if given) first, so the
  caller can drop them from its selection. Returns True when anything changed. }
function ReconcilePhases(ADesign: TDesignFile; ASheet: TDesignSheet; Removed: TList): Boolean;
{ every wire of the group, in the order of the drawing }
procedure PhaseGroupMembers(ADrawing: TDrawingList; AGroup: Integer; AList: TList);
{ the group of an object, 0 when it is not a wire of a 3-phase bus }
function PhaseGroupOf(Obj: TDrawingObject): Integer;
{ the distance between the middle wire and the others in a group as drawn (0 when there are no others) }
function PhaseSpacingDrawn(ADrawing: TDrawingList; AGroup: Integer): Double;
{ P is the free end of a wire of a 3-phase bus: Shifts are the moves from P to the free end of each of the other wires of the group at that end (two of them). False when
  it is not. }
function PhaseCompanionEnds(ADrawing: TDrawingList; const P: TDPoint; out Shifts: TPhaseSegments): Boolean;

implementation

const
  Tol = 0.01;       // design units: points closer than this are the same point

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
  Result := (Abs(A.x - B.x) < Tol) and (Abs(A.y - B.y) < Tol);
end;

{ ===========================================================================
  PhaseGroupOf  (function)
  Parameters:
    Obj: TDrawingObject - the drawing object
  Returns:
    Integer
  Notes:
    TODO: describe.
  =========================================================================== }
function PhaseGroupOf(Obj: TDrawingObject): Integer;
begin
  Result := 0;
  if (Obj is TDrawLine) and ((Obj as TDrawLine).Kind = xBus) then
    Result := (Obj as TDrawLine).Group;
end;

{ ===========================================================================
  PhaseGroupMembers  (procedure)
  Parameters:
    ADrawing: TDrawingList
    AGroup: Integer - whole number
    AList: TList
  Notes:
    TODO: describe.
  =========================================================================== }
procedure PhaseGroupMembers(ADrawing: TDrawingList; AGroup: Integer; AList: TList);
var
  i: Integer;
begin
  AList.Clear;
  if AGroup = 0 then
    Exit;
  for i := 0 to ADrawing.Count - 1 do
    if PhaseGroupOf(ADrawing[i]) = AGroup then
      AList.Add(ADrawing[i]);
end;

{ ===========================================================================
  OffsetSegments  (function)
  Parameters:
    const Mid: TPhaseSegments
    Spacing: Double - number
    Side: Integer - whole number
  Returns:
    TPhaseSegments
  Notes:
    The way the chain runs is worked out from how the segments meet: each is turned to start
    where the one before it ends (the first one keeps its own direction). Where exactly two
    segments meet and are not in line, the two offset lines are cut at the point where they
    cross (so the corner stays sharp), unless that is far away (a very sharp turn), where each
    keeps its own end. Where three or more meet, or a segment ends alone, the end is just moved
    sideways.
  =========================================================================== }
function OffsetSegments(const Mid: TPhaseSegments; Spacing: Double; Side: Integer): TPhaseSegments;
var
  N, i, j, c, Touch, Succ: Integer;
  Flip: array of Boolean;      // the segment is turned round: it starts at its B
  Seen: array of Boolean;
  Queue: array of Integer;
  QH, QT: Integer;
  P, Q, OP, OQ: array of TDPoint;      // the oriented segments and their offset ends
  Dx, Dy, L, Cr, T1: Double;
  F: Double;
  X: TDPoint;
  Dir: array of TDPoint;

  procedure Orient(k: Integer);
  begin
    if Flip[k] then begin
      P[k] := Mid[k].B;
      Q[k] := Mid[k].A;
    end
    else begin
      P[k] := Mid[k].A;
      Q[k] := Mid[k].B;
    end;
  end;

begin
  N := Length(Mid);
  SetLength(Result, N);
  SetLength(Flip, N); SetLength(Seen, N); SetLength(Queue, N);
  SetLength(P, N); SetLength(Q, N); SetLength(OP, N); SetLength(OQ, N); SetLength(Dir, N);
  for i := 0 to N - 1 do
  begin
    Flip[i] := False; Seen[i] := False;
  end;
  { the way the chain runs: walk out from each segment not seen yet }
  for i := 0 to N - 1 do
  begin
    if Seen[i] then
      Continue;
    Seen[i] := True;
    Orient(i);
    QH := 0; QT := 0; Queue[QT] := i; Inc(QT);
    while QH < QT do
    begin
      c := Queue[QH]; Inc(QH);
      for j := 0 to N - 1 do
      begin
        if Seen[j] then
          Continue;
        if Near(Mid[j].A, Q[c]) then
          Flip[j] := False
        else if Near(Mid[j].B, Q[c]) then
          Flip[j] := True
        else if Near(Mid[j].B, P[c]) then
          Flip[j] := False      // it ends where this one starts
        else if Near(Mid[j].A, P[c]) then
          Flip[j] := True
        else
          Continue;
        Seen[j] := True;
        Orient(j);
        Queue[QT] := j; Inc(QT);
      end;
    end;
  end;
  for i := 0 to N - 1 do
  begin
    Dx := Q[i].x - P[i].x; Dy := Q[i].y - P[i].y;
    L := Sqrt(Dx * Dx + Dy * Dy);
    if L < 1e-9 then
    begin
      Dir[i] := DPoint(1, 0);
      OP[i] := P[i]; OQ[i] := Q[i];
      Continue;
    end;
    Dir[i] := DPoint(Dx / L, Dy / L);
    { the left of the way it runs on the screen (y grows downwards) is (dy, -dx); Side -1 is the left }
    OP[i] := DPoint(P[i].x - Side * Spacing * Dir[i].y, P[i].y + Side * Spacing * Dir[i].x);
    OQ[i] := DPoint(Q[i].x - Side * Spacing * Dir[i].y, Q[i].y + Side * Spacing * Dir[i].x);
  end;
  { the corners: the end of one segment and the start of the one that follows it }
  for i := 0 to N - 1 do
  begin
    Touch := 0; Succ := -1;
    for j := 0 to N - 1 do
      if j <> i then
      begin
        if Near(P[j], Q[i]) or Near(Q[j], Q[i]) then
          Inc(Touch);
        if Near(P[j], Q[i]) then
          Succ := j;
      end;
    if (Touch <> 1) or (Succ < 0) then
      Continue;
    Cr := Dir[i].x * Dir[Succ].y - Dir[i].y * Dir[Succ].x;
    if Abs(Cr) < 1e-6 then
      Continue;                              // in line: nothing to cut
    { the point on both offset lines: OP[i] + t Dir[i] = OP[Succ] + u Dir[Succ] }
    T1 := ((OP[Succ].x - OP[i].x) * Dir[Succ].y - (OP[Succ].y - OP[i].y) * Dir[Succ].x) / Cr;
    X := DPoint(OP[i].x + T1 * Dir[i].x, OP[i].y + T1 * Dir[i].y);
    F := Sqrt(Sqr(X.x - OQ[i].x) + Sqr(X.y - OQ[i].y));
    if F > 3 * Spacing then
      Continue;                              // a very sharp turn: leave the ends as they are
    OQ[i] := X;
    OP[Succ] := X;
  end;
  for i := 0 to N - 1 do
    if Flip[i] then
    begin
      Result[i].A := OQ[i]; Result[i].B := OP[i];
    end
    else
    begin
      Result[i].A := OP[i]; Result[i].B := OQ[i];
    end;
end;

{ ===========================================================================
  PhaseSpacingDrawn  (function)
  Parameters:
    ADrawing: TDrawingList
    AGroup: Integer - whole number
  Returns:
    Double
  Notes:
    TODO: describe.
  =========================================================================== }
function PhaseSpacingDrawn(ADrawing: TDrawingList; AGroup: Integer): Double;
var
  i, j: Integer;
  O, M: TDrawLine;
  Dx, Dy, L, D: Double;
begin
  Result := 0;
  for i := 0 to ADrawing.Count - 1 do
  begin
    if PhaseGroupOf(ADrawing[i]) <> AGroup then
      Continue;
    O := ADrawing[i] as TDrawLine;
    if O.Phase = 0 then
      Continue;
    for j := 0 to ADrawing.Count - 1 do
    begin
      if PhaseGroupOf(ADrawing[j]) <> AGroup then
        Continue;
      M := ADrawing[j] as TDrawLine;
      if M.Phase <> 0 then
        Continue;
      Dx := M.PointB.x - M.PointA.x; Dy := M.PointB.y - M.PointA.y;
      L := Sqrt(Dx * Dx + Dy * Dy);
      if L < 1e-9 then
        Continue;
      { parallel, and the outer wire's start within the length of the middle one }
      if Abs((O.PointB.x - O.PointA.x) * Dy - (O.PointB.y - O.PointA.y) * Dx) / L > 0.5 then
        Continue;
      D := Abs((O.PointA.x - M.PointA.x) * Dy - (O.PointA.y - M.PointA.y) * Dx) / L;
      if D > 0.01 then
        Exit(D);
    end;
  end;
end;

{ ===========================================================================
  ReconcilePhases  (function)
  Parameters:
    ADesign: TDesignFile - the design
    ASheet: TDesignSheet - the sheet
    Removed: TList
  Returns:
    Boolean
  Notes:
    See the unit's comment. The groups are found again each time from the wires, so nothing is
    kept between calls.
  =========================================================================== }
function ReconcilePhases(ADesign: TDesignFile; ASheet: TDesignSheet; Removed: TList): Boolean;
var
  Dr: TDrawingList;
  Pending, Mids, All, Groups: TList;
  i, j, k, g, Side, Cnt: Integer;
  L, C: TDrawLine;
  Comp: array of Integer;      // the component of each pending wire
  NC, Old: Integer;
  Id: Integer;
  S, Drawn: Double;
  Segs, Res: TPhaseSegments;
  Rebuild, AnyOne: Boolean;
  Outers: array[0..1] of Integer;

  procedure Join(a, b: Integer);
  var
    x, y, m: Integer;
  begin
    x := Comp[a]; y := Comp[b];
    if x = y then
      Exit;
    for m := 0 to High(Comp) do
      if Comp[m] = y then
        Comp[m] := x;
  end;

  function Touches(A1, B1, A2, B2: TDPoint): Boolean;
  begin
    Result := Near(A1, A2) or Near(A1, B2) or Near(B1, A2) or Near(B1, B2);
  end;

begin
  Result := False;
  Dr := ASheet.Drawing;
  AnyOne := False;
  for i := 0 to Dr.Count - 1 do
    if (Dr[i] is TDrawLine) and ((Dr[i] as TDrawLine).Kind = xBus) then
      if ((Dr[i] as TDrawLine).Phases = 3) or ((Dr[i] as TDrawLine).Group <> 0) then
        AnyOne := True;
  if not AnyOne then
    Exit;
  Pending := TList.Create; Mids := TList.Create; All := TList.Create; Groups := TList.Create;
  try
    { 1. the buses drawn for 3 phases that are not in a group yet, in groups: the ones that meet (or meet a group's middle wire) are one bus }
    for i := 0 to Dr.Count - 1 do
      if (Dr[i] is TDrawLine) and ((Dr[i] as TDrawLine).Kind = xBus) then
      begin
        L := Dr[i] as TDrawLine;
        if (L.Group = 0) and (L.Phases = 3) then
          Pending.Add(L);
      end;
    if Pending.Count > 0 then
    begin
      SetLength(Comp, Pending.Count);
      for i := 0 to Pending.Count - 1 do
        Comp[i] := i;
      for i := 0 to Pending.Count - 1 do
        for j := i + 1 to Pending.Count - 1 do
        begin
          L := TDrawLine(Pending[i]); C := TDrawLine(Pending[j]);
          if Touches(L.PointA, L.PointB, C.PointA, C.PointB) then
            Join(i, j);
        end;
      for i := 0 to Pending.Count - 1 do
      begin
        if Comp[i] <> i then
          Continue;                    // handled with the first wire of its component
        Id := 0;
        S := TDrawLine(Pending[i]).PhaseSpacing;
        for j := 0 to Pending.Count - 1 do
          if Comp[j] = i then
            for k := 0 to Dr.Count - 1 do
              if (PhaseGroupOf(Dr[k]) <> 0) and ((Dr[k] as TDrawLine).Phase = 0) and (Id = 0) then
                if Touches(TDrawLine(Pending[j]).PointA, TDrawLine(Pending[j]).PointB, TDrawLine(Dr[k]).PointA, TDrawLine(Dr[k]).PointB) then
                  Id := (Dr[k] as TDrawLine).Group;
        if Id = 0 then
          Id := ADesign.NextObjectId;
        for j := 0 to Pending.Count - 1 do
          if Comp[j] = i then
          begin
            TDrawLine(Pending[j]).Group := Id;
            TDrawLine(Pending[j]).Phase := 0;
            TDrawLine(Pending[j]).PhaseSpacing := S;
          end;
      end;
      Result := True;
    end;
    { 2. each group }
    for i := 0 to Dr.Count - 1 do
    begin
      g := PhaseGroupOf(Dr[i]);
      if (g <> 0) and (Groups.IndexOf(Pointer(PtrInt(g))) < 0) then
        Groups.Add(Pointer(PtrInt(g)));
    end;
    for k := 0 to Groups.Count - 1 do
    begin
      g := PtrInt(Groups[k]);
      PhaseGroupMembers(Dr, g, All);
      Mids.Clear;
      Cnt := 0;
      Rebuild := False;
      S := 0;
      for i := 0 to All.Count - 1 do
      begin
        L := TDrawLine(All[i]);
        if L.Phase = 0 then
        begin
          Mids.Add(L);
          if S = 0 then
            S := L.PhaseSpacing;
        end;
      end;
      { a group that lost its middle wires (deleted): nothing to make the others from, they are plain buses now }
      if Mids.Count = 0 then
      begin
        for i := 0 to All.Count - 1 do
        begin
          TDrawLine(All[i]).Group := 0; TDrawLine(All[i]).Phase := 0; TDrawLine(All[i]).Phases := 1;
        end;
        Result := True;
        Continue;
      end;
      { one phase wanted: the outer wires go, the middle one is an ordinary bus }
      for i := 0 to All.Count - 1 do
        if TDrawLine(All[i]).Phases = 1 then
          Rebuild := True;
      if Rebuild then
      begin
        for i := All.Count - 1 downto 0 do
        begin
          L := TDrawLine(All[i]);
          if L.Phase <> 0 then
          begin
            if Removed <> nil then
              Removed.Add(L);
            Dr.Remove(L);
          end
          else
          begin
            L.Group := 0; L.Phases := 1;
          end;
        end;
        Result := True;
        Continue;
      end;
      for i := 0 to All.Count - 1 do
        if TDrawLine(All[i]).Phase <> 0 then
          Inc(Cnt);
      Drawn := PhaseSpacingDrawn(Dr, g);
      Rebuild := (Cnt <> 2 * Mids.Count) or (Abs(Drawn - S) > 0.01);
      for i := 0 to All.Count - 1 do
      begin
        TDrawLine(All[i]).Phases := 3;
        TDrawLine(All[i]).PhaseSpacing := S;
      end;
      if not Rebuild then
        Continue;
      { make the outer wires again from the middle ones }
      for i := All.Count - 1 downto 0 do
        if TDrawLine(All[i]).Phase <> 0 then
        begin
          if Removed <> nil then
            Removed.Add(All[i]);
          Dr.Remove(TObject(All[i]));
        end;
      SetLength(Segs, Mids.Count);
      for i := 0 to Mids.Count - 1 do
      begin
        Segs[i].A := TDrawLine(Mids[i]).PointA;
        Segs[i].B := TDrawLine(Mids[i]).PointB;
      end;
      for Side := -1 to 1 do
      begin
        if Side = 0 then
          Continue;
        Res := OffsetSegments(Segs, S, Side);
        for i := 0 to Mids.Count - 1 do
        begin
          C := TDrawLine(Mids[i]).Clone as TDrawLine;
          C.PointA := Res[i].A;
          C.PointB := Res[i].B;
          C.Group := g;
          C.Phase := Side;
          C.Phases := 3;
          C.PhaseSpacing := S;
          C.Id := ADesign.NextObjectId;
          Dr.Add(C);
        end;
      end;
      Result := True;
    end;
  finally
    Pending.Free; Mids.Free; All.Free; Groups.Free;
  end;
end;

{ ===========================================================================
  PhaseCompanionEnds  (function)
  Parameters:
    ADrawing: TDrawingList
    const P: TDPoint - a point, in design units
    out Shifts: TPhaseSegments - out: set by the call
  Returns:
    Boolean
  Notes:
    A free end is an end no other wire of the group meets. The other wires' ends are the ends of
    the other wires of the group nearest to P that lie across the wire (in the direction at
    right angles to it), within twice the spacing.
  =========================================================================== }
function PhaseCompanionEnds(ADrawing: TDrawingList; const P: TDPoint; out Shifts: TPhaseSegments): Boolean;
var
  i, j, g, Found: Integer;
  L, M: TDrawLine;
  E, Other, Dr: TDPoint;
  Len, Ax, Ay: Double;
  Gap: Integer;
  Free: Boolean;
  Ends: array of TDPoint;

  function EndOf(AL: TDrawLine; AEnd: Integer): TDPoint;
  begin
    if AEnd = 0 then
      Result := AL.PointA
    else
      Result := AL.PointB;
  end;

begin
  Result := False;
  SetLength(Shifts, 0);
  for i := 0 to ADrawing.Count - 1 do
  begin
    g := PhaseGroupOf(ADrawing[i]);
    if g = 0 then
      Continue;
    L := ADrawing[i] as TDrawLine;
    for Found := 0 to 1 do
    begin
      E := EndOf(L, Found);
      Other := EndOf(L, 1 - Found);
      if not Near(E, P) then
        Continue;
      { is the end free: no other wire of the same phase of the group meets it }
      Free := True;
      for j := 0 to ADrawing.Count - 1 do
        if (j <> i) and (PhaseGroupOf(ADrawing[j]) = g) and ((ADrawing[j] as TDrawLine).Phase = L.Phase) then
        begin
          M := ADrawing[j] as TDrawLine;
          if Near(M.PointA, E) or Near(M.PointB, E) then
            Free := False;
        end;
      if not Free then
        Continue;
      Len := Sqrt(Sqr(E.x - Other.x) + Sqr(E.y - Other.y));
      if Len < 1e-9 then
        Continue;
      Dr := DPoint((E.x - Other.x) / Len, (E.y - Other.y) / Len);
      SetLength(Ends, 0);
      for j := 0 to ADrawing.Count - 1 do
      begin
        if (j = i) or (PhaseGroupOf(ADrawing[j]) <> g) then
          Continue;
        M := ADrawing[j] as TDrawLine;
        if M.Phase = L.Phase then
          Continue;
        for Gap := 0 to 1 do
        begin
          Other := EndOf(M, Gap);
          Ax := Other.x - E.x; Ay := Other.y - E.y;
          { across the wire: no distance along it, and within two spacings }
          if (Abs(Ax * Dr.x + Ay * Dr.y) < 0.5) and (Sqrt(Ax * Ax + Ay * Ay) <= 2 * L.PhaseSpacing + 0.5) and (Sqrt(Ax * Ax + Ay * Ay) > 0.01) then
          begin
            SetLength(Ends, Length(Ends) + 1);
            Ends[High(Ends)] := DPoint(Ax, Ay);
          end;
        end;
      end;
      if Length(Ends) = 2 then
      begin
        SetLength(Shifts, 2);
        Shifts[0].A := Ends[0]; Shifts[1].A := Ends[1];
        Exit(True);
      end;
    end;
  end;
end;

end.
