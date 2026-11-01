// SPDX-License-Identifier: LGPL-2.1-or-later
unit UBusSnap;

{$mode ObjFPC}{$H+}

{ Snapping the poles of a device onto a bus (parts plan step 6).

  A multi-conductor bus (UPhases: the wires of a group side by side) and the two rails of a ladder are all buses here: parallel conductors a set distance apart. A device with N poles
  has N pins in a row across the bus, one pole pitch apart. When the pitch is the spacing of the bus the row can be put on the conductors: pole 1 on one conductor, pole 2 on the next,
  and so on. With more poles than conductors the extra poles stay off the bus (a 3 pole device on a 2 wire bus uses 2), with fewer, the poles use that many conductors in a row.

  PoleSnap is the whole rule, over plain numbers, so it is checked without a sheet; BusesOfSheet finds the buses of a sheet.

  Licence: LGPL 2.1 or later, as the rest of this port. }

interface

uses
  Classes, SysUtils, Math, UDPoint, UDrawTypes, UDrawingObjects, UDesign, UPhases;

type
  { one conductor: its place across the bus (Off, along the normal) and how far it reaches along the bus (T0..T1) }
  TBusConductor = record
    Off, T0, T1: Double;
  end;

  { a bus: the unit vector Dir along its conductors, the spacing between them and the conductors in order of Off }
  TBusDesc = record
    Dir: TDPoint;
    Spacing: Double;
    Conds: array of TBusConductor;
  end;
  TBusDescArray = array of TBusDesc;

const
  PoleTol = 1.5;        // design units (0.3 mm): how far a pole pitch may differ from the spacing of the bus
  PoleReach = 50;       // design units (10 mm): how far from a conductor's end the row of poles may be and still be put on it

{ Where to move a symbol with the pins Pins so that a row of its pins is on the conductors of one of Buses: the move is in Delta, Poles is how many pins land on a conductor, Bus is the
  bus used. False when no row of at least two pins fits any bus (Delta is 0 then). Several rows fit: the one with the most poles, then the shortest move, wins. }
function PoleSnap(const Pins: TDPointArray; const Buses: TBusDescArray; out Delta: TDPoint; out Poles, Bus: Integer): Boolean;
{ the buses of a sheet: each straight run of a multi-conductor bus, and each ladder (its two rails) }
function BusesOfSheet(ASheet: TDesignSheet): TBusDescArray;

implementation

function PoleSnap(const Pins: TDPointArray; const Buses: TBusDescArray; out Delta: TDPoint; out Poles, Bus: Integer): Boolean;
var
  bi, i, j, k, r, q, Cnt, M: Integer;
  D, Nm: TDPoint;
  A, B: array of Double;
  Used: array of Boolean;
  Row: array of Integer;        // the pins of one row, in order across the bus
  ShiftB, ShiftT, Best, Row0, T0, T1, Dist: Double;
  BestDelta: TDPoint;
  BestCnt: Integer;
  Tmp: Integer;

  function OnCond(const Bu: TBusDesc; X: Double): Boolean;
  var
    q: Integer;
  begin
    Result := False;
    for q := 0 to High(Bu.Conds) do
      if Abs(Bu.Conds[q].Off - X) <= PoleTol then
        Exit(True);
  end;

begin
  Delta := DPoint(0, 0); Poles := 0; Bus := -1;
  Result := False;
  BestCnt := 0; Best := 1e30;
  BestDelta := DPoint(0, 0);
  if Length(Pins) < 2 then
    Exit;
  for bi := 0 to High(Buses) do
  begin
    M := Length(Buses[bi].Conds);
    if M < 2 then
      Continue;
    D := Buses[bi].Dir; Nm := DPoint(-D.y, D.x);
    SetLength(A, Length(Pins)); SetLength(B, Length(Pins)); SetLength(Used, Length(Pins));
    for i := 0 to High(Pins) do
    begin
      A[i] := Pins[i].x * D.x + Pins[i].y * D.y;
      B[i] := Pins[i].x * Nm.x + Pins[i].y * Nm.y;
      Used[i] := False;
    end;
    { the rows: pins at the same place along the bus }
    for i := 0 to High(Pins) do
    begin
      if Used[i] then
        Continue;
      SetLength(Row, 0);
      for j := 0 to High(Pins) do
        if (not Used[j]) and (Abs(A[j] - A[i]) <= 0.25) then
        begin
          SetLength(Row, Length(Row) + 1);
          Row[High(Row)] := j;
          Used[j] := True;
        end;
      { in order across the bus }
      for j := 0 to High(Row) - 1 do
        for k := j + 1 to High(Row) do
          if B[Row[k]] < B[Row[j]] then
          begin
            Tmp := Row[j]; Row[j] := Row[k]; Row[k] := Tmp;
          end;
      if Length(Row) < 2 then
        Continue;
      Row0 := A[Row[0]];
      { try each pin of the row on each conductor: what that move puts on conductors is counted }
      for j := 0 to High(Row) do
        for k := 0 to M - 1 do
        begin
          ShiftB := Buses[bi].Conds[k].Off - B[Row[j]];
          Cnt := 0;
          for r := 0 to High(Row) do
            if OnCond(Buses[bi], B[Row[r]] + ShiftB) then
              Inc(Cnt);
          { the pitch has to be the bus's: the pins that land are one spacing apart, not just somewhere on conductors }
          if Cnt >= 2 then
            for r := 0 to High(Row) - 1 do
              if OnCond(Buses[bi], B[Row[r]] + ShiftB) and OnCond(Buses[bi], B[Row[r + 1]] + ShiftB) and
                 (Abs((B[Row[r + 1]] - B[Row[r]]) - Buses[bi].Spacing) > PoleTol) then
                Cnt := 0;
          if Cnt < 2 then
            Continue;
          { along the bus: inside what the landing conductors cover it stays, beyond an end (within the reach) it goes to the end }
          T0 := 1e30; T1 := -1e30;
          for r := 0 to High(Row) do
            for q := 0 to M - 1 do
              if Abs(Buses[bi].Conds[q].Off - (B[Row[r]] + ShiftB)) <= PoleTol then
              begin
                T0 := Min(T0, Buses[bi].Conds[q].T0);
                T1 := Max(T1, Buses[bi].Conds[q].T1);
              end;
          if Row0 < T0 then
            ShiftT := T0 - Row0
          else if Row0 > T1 then
            ShiftT := T1 - Row0
          else
            ShiftT := 0;
          if Abs(ShiftT) > PoleReach then
            Continue;
          Dist := Sqrt(ShiftB * ShiftB + ShiftT * ShiftT);
          if (Cnt > BestCnt) or ((Cnt = BestCnt) and (Dist < Best)) then
          begin
            BestCnt := Cnt; Best := Dist;
            BestDelta := DPoint(D.x * ShiftT + Nm.x * ShiftB, D.y * ShiftT + Nm.y * ShiftB);
            Bus := bi;
          end;
        end;
    end;
  end;
  if BestCnt >= 2 then
  begin
    Delta := BestDelta; Poles := BestCnt;
    Result := True;
  end
  else
    Bus := -1;
end;

function BusesOfSheet(ASheet: TDesignSheet): TBusDescArray;
var
  Dr: TDrawingList;
  i, j, n: Integer;
  Mid, L: TDrawLine;
  Len, Dx, Dy, Cross, T0, T1, S0, S1: Double;
  D, Nm: TDPoint;
  Lad: TDrawLadder;
  Cond: TBusConductor;

  procedure AddCond(var Bu: TBusDesc; const Cd: TBusConductor);
  var
    q, p: Integer;
    Dup: Boolean;
  begin
    Dup := False;
    for q := 0 to High(Bu.Conds) do
      if (Abs(Bu.Conds[q].Off - Cd.Off) < 0.05) then
        Dup := True;
    if Dup then
      Exit;
    SetLength(Bu.Conds, Length(Bu.Conds) + 1);
    p := High(Bu.Conds);
    while (p > 0) and (Bu.Conds[p - 1].Off > Cd.Off) do
    begin
      Bu.Conds[p] := Bu.Conds[p - 1];
      Dec(p);
    end;
    Bu.Conds[p] := Cd;
  end;

begin
  SetLength(Result, 0);
  if ASheet = nil then
    Exit;
  Dr := ASheet.Drawing;
  for i := 0 to Dr.Count - 1 do
  begin
    if (Dr[i] is TDrawLine) and ((Dr[i] as TDrawLine).Kind = xBus) and ((Dr[i] as TDrawLine).Group <> 0) and ((Dr[i] as TDrawLine).Phase = 0) and
       ((Dr[i] as TDrawLine).Phases >= 2) then
    begin
      Mid := Dr[i] as TDrawLine;
      Dx := Mid.PointB.x - Mid.PointA.x; Dy := Mid.PointB.y - Mid.PointA.y;
      Len := Sqrt(Dx * Dx + Dy * Dy);
      if Len < 1e-6 then
        Continue;
      D := DPoint(Dx / Len, Dy / Len); Nm := DPoint(-D.y, D.x);
      n := Length(Result);
      SetLength(Result, n + 1);
      Result[n].Dir := D; Result[n].Spacing := Mid.PhaseSpacing; SetLength(Result[n].Conds, 0);
      S0 := Min(Mid.PointA.x * D.x + Mid.PointA.y * D.y, Mid.PointB.x * D.x + Mid.PointB.y * D.y);
      S1 := Max(Mid.PointA.x * D.x + Mid.PointA.y * D.y, Mid.PointB.x * D.x + Mid.PointB.y * D.y);
      for j := 0 to Dr.Count - 1 do
      begin
        if not ((Dr[j] is TDrawLine) and ((Dr[j] as TDrawLine).Kind = xBus) and ((Dr[j] as TDrawLine).Group = Mid.Group)) then
          Continue;
        L := Dr[j] as TDrawLine;
        { parallel to the middle wire, and covering some of the same stretch of it }
        Cross := Abs((L.PointB.x - L.PointA.x) * D.y - (L.PointB.y - L.PointA.y) * D.x);
        if Cross > 0.01 then
          Continue;
        T0 := Min(L.PointA.x * D.x + L.PointA.y * D.y, L.PointB.x * D.x + L.PointB.y * D.y);
        T1 := Max(L.PointA.x * D.x + L.PointA.y * D.y, L.PointB.x * D.x + L.PointB.y * D.y);
        if (T1 < S0 - 0.01) or (T0 > S1 + 0.01) then
          Continue;
        Cond.Off := L.PointA.x * Nm.x + L.PointA.y * Nm.y; Cond.T0 := T0; Cond.T1 := T1;
        AddCond(Result[n], Cond);
      end;
    end
    else if Dr[i] is TDrawLadder then
    begin
      Lad := Dr[i] as TDrawLadder;
      n := Length(Result);
      SetLength(Result, n + 1);
      Result[n].Dir := DPoint(0, 1); Result[n].Spacing := Lad.RailRight - Lad.RailLeft; SetLength(Result[n].Conds, 0);
      { Dir (0,1): the normal is (-1,0), so Off is minus x }
      Cond.T0 := Lad.RailTop; Cond.T1 := Lad.RailBottom;
      Cond.Off := -Lad.RailLeft; AddCond(Result[n], Cond);
      Cond.Off := -Lad.RailRight; AddCond(Result[n], Cond);
    end;
  end;
end;

end.
