{ The editing engine: how wires are drawn, snapped, merged, split and given junctions.

  A faithful port of TinyCAD's CTinyCadDoc::GetStickyPoint, CJunctionUtils, CDragUtils::Merge /
  Clean / End / MergeLinePoint and the CDrawLine tool (its click / move / drag / finish state
  machine and its 90 degree and 45 degree angle modes). No user interface in here: a view feeds it
  mouse positions in design coordinates and draws what it reports.

  Licence: LGPL 2.1 or later, as the rest of this port. Original: Copyright Matt Pyne. }
unit UEdit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs, Math, UDPoint, UDrawTypes, UGeometry, UDrawingObjects, UDesign;

const
  POINT_ON_LINE = 0.01; // CLineUtils::pointOnLineDistance

type
  { A wire taking part in a drag (CDragUtils::dragWire): which of its ends move with the drag, and
    when an end is attached to the middle of another dragged wire, which wire and how far along it. }
  TDragWire = class
  public
    Obj: TDrawingObject;
    MoveA, MoveB: Boolean;
    AttLineA, AttLineB: TDrawingObject;
    DistA, DistB: Double;
    DoneA, DoneB: Boolean;
    constructor Create(AObj: TDrawingObject; AMoveA, AMoveB: Boolean);
  end;

  { ---------------------------------------------------------------- engine }
  TWireEngine = class
  private
    FDWires: TObjectList;   // the TDragWire list (CDragUtils::m_draggedWires)
    FDStarted: Boolean;
    FDA, FDB: TDPoint;      // the selection area of the drag (CDragUtils::m_a, m_b)
    function FindDWire(Obj: TDrawingObject): TDragWire;
    function DW(Index: Integer): TDragWire;
    procedure AddWireToCollection(N: TDragWire);
    procedure AddWiresAtPoint(const P: TDPoint);
    procedure AddAttachedObjects(Wire: TDrawingObject; WireMoveA, WireMoveB: Boolean);
    procedure MoveAttachedObjects(Wire: TDrawingObject);
    procedure DisplayDraggedWires;
    procedure CollectDragged;
  private
    FDesign: TDesignFile;
    FSheet: TDesignSheet;
    FJDiscards: TList;   // CJunctionUtils::m_discards
    FDDiscards: TList;   // CDragUtils::m_discards
    FDragged: TList;     // CDragUtils::m_draggedWires
    FTodoA, FTodoB: array of TDPoint;
    FTodoIsPoint: array of Boolean;
    function Opts: TDocOptionsBase;
    function IndexInDrawing(Obj: TDrawingObject): Integer;
    procedure DeleteObject(Obj: TDrawingObject);
    procedure TodoAdd(const A, B: TDPoint; IsPoint: Boolean);
    procedure Merge;
    procedure Clean;
    procedure EndDrag;
  public
    SingleSelected: TDrawingObject;   // CTinyCadDoc::GetSingleSelectedItem: never merged into
    Selected: TList;                  // the objects being dragged or moved (not owned)
    PullPoints: array of TDPoint;           // end handles being pulled (several chosen wires stretched together): a selected wire's end at one of these points moves, whatever the area; empty for a move
    RecordRaw: Boolean;               // test hook: remember each segment as the tool stored it
    RawA, RawB: array of TDPoint;
    constructor Create(ADesign: TDesignFile; ASheet: TDesignSheet);
    destructor Destroy; override;
    { The point the cursor "sticks" to: a pin, a power or label connection point, or a point on a
      wire, when within the snap range; otherwise the grid point. IsJunction: sticking here would
      join three or more things. }
    function StickyPoint(const NoSnap: TDPoint; Pins, Wires: Boolean; out IsStuck, IsJunction: Boolean): TDPoint;
    function AddNewJunction(const Q: TDPoint): TDrawJunction;
    { Does a junction belong at Q? Adds, removes or (PerformSplit) splits wires to make it so. }
    procedure CheckJunctionRequirement(const Q: TDPoint; PerformSplit: Boolean); overload;
    { The same for every point along the line A-B }
    procedure CheckJunctionRequirement(const A, B: TDPoint; PerformSplit: Boolean); overload;
    procedure AddObjectToTodo(Obj: TDrawingObject);
    procedure CheckTodoList(PerformSplit: Boolean);
    { Run the merge / clean / junction pass for a wire that has just been stored }
    procedure MergeLinePoint(Obj: TDrawingObject);
    { Add an object to the sheet with a new id }
    procedure AddObject(Obj: TDrawingObject);
    { ---- moving the selection (CDragUtils) ----
      BeginDrag: start a move of Selected; the area is the rectangle the selection was picked with
      (wires of the selection with an end inside it only have that end moved, the rest stay).
      DragBy: move by a step and stretch the wires attached to the objects' connection points,
      dragging along wires attached to those wires; MoveBy: move the objects only.
      FinishDrag: merge, clean and re-check junctions; call once when the mouse is released. }
    procedure BeginDrag(const AreaA, AreaB: TDPoint);
    procedure DragBy(const R: TDPoint);
    procedure MoveBy(const R: TDPoint);
    procedure FinishDrag;
    property Sheet: TDesignSheet read FSheet;
  end;

  { The connection points of an object: pins, power, input/output labels, bus slashes (GetActive) }
  TPointList = array of TDPoint;
function ActivePointsOf(Obj: TDrawingObject): TPointList;

type
  TAngleMode = (amFree, am90, am45);

  { a segment the wire tool has just made, before it goes in the drawing (the view gives it the tool's chosen properties) }
  TNewLineEvent = procedure(L: TDrawLine) of object;

  { ---------------------------------------------------------------- the line / wire tool }
  TWireTool = class
  private
    FEngine: TWireEngine;
    FKind: TObjType;
    function StickyFor(const NoSnap: TDPoint): TDPoint;
    procedure ToAngle;
    function Store: TDrawLine;
  public
    A, B: TDPoint;
    Segment: Integer;       // 1 = waiting for the first point, 0 = a segment is being drawn
    Mode: Integer;          // 90 degree mode: 1 = horizontal leg first, 2 = vertical leg first
    IsStuck, IsJunction, HasPlaced: Boolean;
    UseDefaultStyle: Boolean;
    Style: Integer;
    Angle: TAngleMode;
    Stored: Integer;        // how many segments this tool has stored so far
    OnNewLine: TNewLineEvent;
    constructor Create(AEngine: TWireEngine; AKind: TObjType);
    procedure BeginEdit;
    procedure EndEdit;
    procedure LButtonDown(const NoSnap: TDPoint);
    procedure LButtonUp(const NoSnap: TDPoint);
    function RButtonDown: Boolean;
    procedure DblLButtonDown(const NoSnap: TDPoint);
    procedure Move(const NoSnap: TDPoint);
    { The rubber band: A -> Corner -> B (Corner = A when it is one straight piece) }
    procedure Preview(out Corner: TDPoint);
    property Kind: TObjType read FKind;
  end;

implementation

{ ===========================================================================
  ActivePointsOf  (function)
  Parameters:
    Obj: TDrawingObject - the object to ask
  Returns:
    TPointList - array of points; empty when the object has no connection points
  Notes:
    The connection points of an object, i.e. TinyCAD's GetActive: the visible pins of a placed
    symbol, a power symbol's point, the point of an input/output label, or both ends of a bus
    slash. Wires, junctions and shapes have none. Wire snapping and junction checks use these.
  =========================================================================== }
function ActivePointsOf(Obj: TDrawingObject): TPointList;
begin
  SetLength(Result, 0);
  if Obj is TDrawMethod then
    Result := TPointList((Obj as TDrawMethod).ActivePoints)
  else if Obj is TDrawPower then
  begin
    SetLength(Result, 1);
    Result[0] := Obj.PointA;
  end
  else if (Obj is TDrawLabel) and ((Obj as TDrawLabel).LabelStyle <> label_normal) then
  begin
    SetLength(Result, 1);
    Result[0] := (Obj as TDrawLabel).ActivePoint;
  end
  else if Obj is TDrawBusSlash then
  begin
    SetLength(Result, 2);
    Result[0] := Obj.PointA;
    Result[1] := Obj.PointB;
  end;
end;

{ ===========================================================================
  PointNotEqual  (function)
  Parameters:
    const A: TDPoint - a point, in design units
    const B: TDPoint - a point, in design units
  Returns:
    Boolean - True if the points are different
  Notes:
    True when two points differ by more than the 0.001 tolerance TinyCAD uses when comparing
    points (the opposite of PointsClose).
  =========================================================================== }
function PointNotEqual(const A, B: TDPoint): Boolean;
begin
  Result := not PointsClose(A, B);
end;

{ ===========================================================================
  PointOrderLess  (function)
  Parameters:
    const A: TDPoint - a point, in design units
    const B: TDPoint - a point, in design units
  Returns:
    Boolean
  Notes:
    CDPoint::operator< (the order of a std::set<CDPoint>)
  =========================================================================== }
function PointOrderLess(const A, B: TDPoint): Boolean;
const
  Close = 0.001;
begin
  if Abs(B.x - A.x) < Close then
    Result := A.y < B.y - Close
  else
    Result := A.x < B.x - Close;
end;

{ ================================================================ TWireEngine }

{ ===========================================================================
  TWireEngine.Create  (constructor)
  Parameters:
    ADesign: TDesignFile - the design (used to give new objects ids)
    ASheet: TDesignSheet - the sheet being edited
  Notes:
    Creates the engine for editing one sheet of a design. It keeps the lists the merge and
    junction passes use (discarded wires, dragged wires, the junction to-do list).
  =========================================================================== }
constructor TWireEngine.Create(ADesign: TDesignFile; ASheet: TDesignSheet);
begin
  inherited Create;
  FDesign := ADesign;
  FSheet := ASheet;
  FJDiscards := TList.Create;
  FDDiscards := TList.Create;
  FDragged := TList.Create;
  FDWires := TObjectList.Create(True);
  Selected := TList.Create;
end;

{ ===========================================================================
  TWireEngine.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the working lists. The sheet and its objects are not owned by the engine.
  =========================================================================== }
destructor TWireEngine.Destroy;
begin
  Selected.Free;
  FDWires.Free;
  FDragged.Free;
  FDDiscards.Free;
  FJDiscards.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TWireEngine.Opts  (function)
  Parameters:  none
  Returns:
    TDocOptionsBase - the sheet's option object
  Notes:
    The options of the sheet being edited (snap grid, auto-junction and auto-snap settings,
    zoom).
  =========================================================================== }
function TWireEngine.Opts: TDocOptionsBase;
begin
  Result := FSheet.Options;
end;

{ ===========================================================================
  TWireEngine.IndexInDrawing  (function)
  Parameters:
    Obj: TDrawingObject - the object to look for
  Returns:
    Integer - position in the list, or -1 when the object is not on the sheet
  Notes:
    Finds an object in the sheet's drawing list; used to forget wires that a merge or discard
    has already removed.
  =========================================================================== }
function TWireEngine.IndexInDrawing(Obj: TDrawingObject): Integer;
begin
  Result := FSheet.Drawing.IndexOf(Obj);
end;

{ ===========================================================================
  TWireEngine.DeleteObject  (procedure)
  Parameters:
    Obj: TDrawingObject - the object to delete
  Notes:
    Removes an object from the sheet (the list frees it) and clears the single-selection
    reference if it pointed at that object.
  =========================================================================== }
procedure TWireEngine.DeleteObject(Obj: TDrawingObject);
begin
  if Obj = SingleSelected then
    SingleSelected := nil;
  if Selected <> nil then
    Selected.Remove(Obj);   // a deleted object leaves the selection
  FSheet.Drawing.Remove(Obj); // the list owns its objects
end;

{ ===========================================================================
  TWireEngine.AddObject  (procedure)
  Parameters:
    Obj: TDrawingObject - the object to add; the sheet takes ownership
  Notes:
    Adds an object to the sheet, giving it a new object id first if it has none.
  =========================================================================== }
procedure TWireEngine.AddObject(Obj: TDrawingObject);
begin
  if Obj.Id = 0 then
    Obj.Id := FDesign.NextObjectId;
  FSheet.Drawing.Add(Obj);
end;

{ ===========================================================================
  TWireEngine.AddNewJunction  (function)
  Parameters:
    const Q: TDPoint - where the junction goes
  Returns:
    TDrawJunction - the new junction
  Notes:
    Creates a junction dot at Q and adds it to the sheet (TinyCAD's AddNewJunction). It does not
    check whether one is already there, as in TinyCAD.
  =========================================================================== }
function TWireEngine.AddNewJunction(const Q: TDPoint): TDrawJunction;
begin
  Result := TDrawJunction.Create(Opts);
  Result.PointA := Q;
  Result.PointB := Q;
  AddObject(Result);
end;

{ ===========================================================================
  TWireEngine.StickyPoint  (function)
  Parameters:
    const NoSnap: TDPoint - the raw mouse position
    Pins: Boolean - consider connection points of symbols, power symbols and labels
    Wires: Boolean - consider points on existing wires
    out IsStuck: Boolean - set True when the result is a pin or wire point
    out IsJunction: Boolean - set True when a junction would be needed there
  Returns:
    TDPoint - the point to use
  Notes:
    Where the cursor "sticks" while drawing (a port of GetStickyPoint): a pin or other
    connection point, or the nearest point on a wire, when within the snap range; otherwise the
    grid point. Also reports whether sticking here would join three or more things so a junction
    is wanted. With auto-snap off it returns the grid point.
  =========================================================================== }
function TWireEngine.StickyPoint(const NoSnap: TDPoint; Pins, Wires: Boolean;
  out IsStuck, IsJunction: Boolean): TDPoint;
var
  R, Q, QSnapX, QSnapY, D, D2, Dpt: TDPoint;
  First: Boolean;
  Items, i, k: Integer;
  MinDist, Range, Distance, Distance2, Dx, Dy: Double;
  Obj: TDrawingObject;
  Act: TPointList;
  S: TDRect;
begin
  R := DPoint(0, 0);
  First := True;
  Items := 0;
  MinDist := 0;
  Range := Opts.AutoSnapRange;
  Q := FSheet.Snap.Snap(NoSnap);
  QSnapX := DPoint(Q.x, NoSnap.y);
  QSnapY := DPoint(NoSnap.x, Q.y);
  if Opts.ZoomFactor > 1.0 then
  begin
    Range := Range / Opts.ZoomFactor;
    { the range must cover the farthest a point can be from its grid point }
    if Range < FSheet.Snap.Grid * 0.71 then
      Range := FSheet.Snap.Grid * 0.71;
  end;
  if not Opts.AutoSnap then
  begin
    IsStuck := False;
    IsJunction := False;
    Result := Q;
    Exit;
  end;
  for i := 0 to FSheet.Drawing.Count - 1 do
  begin
    Obj := FSheet.Drawing[i];
    if Obj.GetType = xWire then
    begin
      if Wires then
      begin
        if LineIsDiagonal(Obj.PointA, Obj.PointB) then
        begin
          { snap on X or Y, whichever is closest to the line }
          Distance := LineDistanceY(Obj.PointA, Obj.PointB, QSnapX, D);
          Distance2 := LineDistanceX(Obj.PointA, Obj.PointB, QSnapY, D2);
          if Distance2 < Distance then
          begin
            Distance := Distance2;
            D := D2;
          end;
        end
        else
          Distance := LineDistance(Obj.PointA, Obj.PointB, Q, D);
        { the real distance from the sticky point to the mouse }
        Dx := D.x - NoSnap.x;
        Dy := D.y - NoSnap.y;
        Distance := Sqrt(Dx * Dx + Dy * Dy);
        if PointsClose(D, R) then
          Inc(Items);
        if First or (Distance < MinDist) then
        begin
          if PointNotEqual(R, D) then
          begin
            { have we split this wire? }
            if PointNotEqual(D, Obj.PointA) and PointNotEqual(D, Obj.PointB) then
              Items := 2
            else
              Items := 1;
          end;
          R := D;
          First := False;
          MinDist := Distance;
        end;
      end;
    end
    else if Pins and (not IsNan(Obj.PointA.x)) and (not IsNan(Obj.PointB.x)) then      // objects without corner points (the rung grid) have none to stick to
    begin
      S := DRectNormalized(DRect(Obj.PointA.x, Obj.PointA.y, Obj.PointB.x, Obj.PointB.y));
      S.Left := S.Left - Range;  S.Right := S.Right + Range;
      S.Bottom := S.Bottom + Range;  S.Top := S.Top - Range;
      if DRectContains(S, NoSnap) then
      begin
        Act := ActivePointsOf(Obj);
        for k := 0 to High(Act) do
        begin
          Dpt := Act[k];
          Dx := Dpt.x - NoSnap.x;
          Dy := Dpt.y - NoSnap.y;
          Distance := Sqrt(Dx * Dx + Dy * Dy);
          if PointsClose(R, Dpt) then
            Inc(Items);
          if First or (Distance < MinDist) then
          begin
            if PointNotEqual(R, Dpt) then
              Items := 1;
            R := Dpt;
            First := False;
            MinDist := Distance;
          end;
        end;
      end;
    end;
  end;
  if (not First) and (MinDist <= Range) then
  begin
    IsStuck := True;
    if Opts.AutoJunction then
      IsJunction := Items > 1
    else
      IsJunction := False;
    Result := R;
  end
  else
  begin
    IsJunction := False;
    IsStuck := False;
    Result := Q;
  end;
end;

{ ===========================================================================
  TWireEngine.TodoAdd  (procedure)
  Parameters:
    const A: TDPoint - the point, or the line's start
    const B: TDPoint - the line's end (ignored for a point)
    IsPoint: Boolean - True when only A matters
  Notes:
    Appends a point or a line to the list of places whose junction requirement must be re-
    checked.
  =========================================================================== }
procedure TWireEngine.TodoAdd(const A, B: TDPoint; IsPoint: Boolean);
var
  n: Integer;
begin
  n := Length(FTodoA);
  SetLength(FTodoA, n + 1);
  SetLength(FTodoB, n + 1);
  SetLength(FTodoIsPoint, n + 1);
  FTodoA[n] := A;
  FTodoB[n] := B;
  FTodoIsPoint[n] := IsPoint;
end;

{ ===========================================================================
  TWireEngine.AddObjectToTodo  (procedure)
  Parameters:
    Obj: TDrawingObject - the object that was added, moved or removed
  Notes:
    Notes what needs a junction check because of this object: a wire's whole line, a junction's
    point, or an object's connection points. Does nothing when auto-junction is off.
  =========================================================================== }
procedure TWireEngine.AddObjectToTodo(Obj: TDrawingObject);
var
  Act: TPointList;
  k: Integer;
begin
  if not Opts.AutoJunction then
    Exit;
  case Obj.GetType of
    xWire: TodoAdd(Obj.PointA, Obj.PointB, False);
    xJunction: TodoAdd(Obj.PointA, Obj.PointA, True);
  else
    Act := ActivePointsOf(Obj);
    for k := 0 to High(Act) do TodoAdd(Act[k], Act[k], True);
  end;
end;

{ ===========================================================================
  TWireEngine.CheckJunctionRequirement  (procedure)
  Parameters:
    const A: TDPoint - start of the line
    const B: TDPoint - end of the line
    PerformSplit: Boolean - allow wires to be split and merged, not just junctions added or remo
      ved
  Notes:
    Checks every point along the line A-B where something touches it (wire ends, junctions,
    connection points) and applies the single-point check at each, in the order TinyCAD does
    (sorted points, no duplicates).
  =========================================================================== }
procedure TWireEngine.CheckJunctionRequirement(const A, B: TDPoint; PerformSplit: Boolean);
var
  Check: array of TDPoint;
  i, k, n, j: Integer;
  Obj: TDrawingObject;
  D, R: TDPoint;
  S: TDRect;
  Act: TPointList;

  procedure AddCheck(const P: TDPoint);
  var
    t: Integer;
  begin
    for t := 0 to High(Check) do
      if PointsClose(Check[t], P) then
        Exit; // a std::set keeps one of each
    SetLength(Check, Length(Check) + 1);
    Check[High(Check)] := P;
  end;

begin
  if not Opts.AutoJunction then
    Exit;
  SetLength(Check, 0);
  for i := 0 to FSheet.Drawing.Count - 1 do
  begin
    Obj := FSheet.Drawing[i];
    case Obj.GetType of
      xJunction:
        if LineDistance(A, B, Obj.PointA, R) <= POINT_ON_LINE then
          AddCheck(Obj.PointA);
      xWire:
        begin
          if LineDistance(A, B, Obj.PointA, R) <= POINT_ON_LINE then
            AddCheck(Obj.PointA);
          if LineDistance(A, B, Obj.PointB, R) <= POINT_ON_LINE then
            AddCheck(Obj.PointB);
        end;
    else
      if not IsNan(Obj.PointA.x) then      // no corner points (rung grid): nothing to hit
      begin
        S := DRectNormalized(DRect(Obj.PointA.x, Obj.PointA.y, Obj.PointB.x, Obj.PointB.y));
        if LineIsInside(A, B, S.Left - POINT_ON_LINE, S.Right + POINT_ON_LINE, S.Top - POINT_ON_LINE, S.Bottom + POINT_ON_LINE) then
        begin
          Act := ActivePointsOf(Obj);
          for k := 0 to High(Act) do
            if LineDistance(A, B, Act[k], R) <= POINT_ON_LINE then
              AddCheck(Act[k]);
        end;
      end;
    end;
  end;
  { process in std::set<CDPoint> order }
  n := Length(Check);
  for i := 1 to n - 1 do
  begin
    D := Check[i];
    j := i - 1;
    while (j >= 0) and PointOrderLess(D, Check[j]) do
    begin
      Check[j + 1] := Check[j];
      Dec(j);
    end;
    Check[j + 1] := D;
  end;
  for i := 0 to High(Check) do
    CheckJunctionRequirement(Check[i], PerformSplit);
end;

{ ===========================================================================
  TWireEngine.CheckJunctionRequirement  (procedure)
  Parameters:
    const Q: TDPoint - the point to check
    PerformSplit: Boolean - allow wires to be split and merged
  Notes:
    Decides whether a junction belongs at Q: adds one when three or more things meet at a wire
    end, removes one that is no longer needed (merging the two collinear wires it joined), and
    with PerformSplit splits a wire that another wire ends in the middle of. A port of TinyCAD's
    CJunctionUtils.
  =========================================================================== }
procedure TWireEngine.CheckJunctionRequirement(const Q: TDPoint; PerformSplit: Boolean);
var
  Items, i, k: Integer;
  LineEnd, HaveJunc: Boolean;
  LineA, LineB, SplitLine, Junc, Obj: TDrawingObject;
  D: TDPoint;
  Distance: Double;
  S: TDRect;
  Act: TPointList;
  VertA, HorizA, VertB, HorizB: Boolean;
  Mn, Mx: Double;
  NewLine: TDrawLine;
  Src: TDrawLine;
begin
  Items := 0;
  LineEnd := False;
  LineA := nil;
  LineB := nil;
  SplitLine := nil;
  Junc := nil;
  HaveJunc := False;
  if not Opts.AutoJunction then
    Exit;
  for i := 0 to FSheet.Drawing.Count - 1 do
  begin
    Obj := FSheet.Drawing[i];
    case Obj.GetType of
      xWire:
        if (FJDiscards.IndexOf(Obj) < 0) and PointNotEqual(Obj.PointA, Obj.PointB) then
        begin
          Distance := LineDistance(Obj.PointA, Obj.PointB, Q, D);
          if Distance <= POINT_ON_LINE then
          begin
            Inc(Items);
            if LineA = nil then
              LineA := Obj
            else
              LineB := Obj;
            if PointNotEqual(Q, Obj.PointA) and PointNotEqual(Q, Obj.PointB) then
            begin
              Inc(Items);
              SplitLine := Obj;
            end
            else
              LineEnd := True;
          end;
        end;
      xJunction:
        if PointsClose(Obj.PointA, Q) then
        begin
          Junc := Obj;
          HaveJunc := True;
        end;
    else
      if not IsNan(Obj.PointA.x) then      // no corner points (rung grid): nothing to hit
      begin
        S := DRectNormalized(DRect(Obj.PointA.x, Obj.PointA.y, Obj.PointB.x, Obj.PointB.y));
        S.Left := S.Left - POINT_ON_LINE; S.Right := S.Right + POINT_ON_LINE;
        S.Bottom := S.Bottom + POINT_ON_LINE; S.Top := S.Top - POINT_ON_LINE;
        if DRectContains(S, Q) then
        begin
          Act := ActivePointsOf(Obj);
          for k := 0 to High(Act) do
            if PointsClose(Act[k], Q) then
            begin
              Inc(Items);
              LineEnd := True;
            end;
        end;
      end;
    end;
  end;

  if ((Items <= 2) or (not LineEnd)) and HaveJunc then
  begin
    DeleteObject(Junc);
    if PerformSplit and (LineA <> nil) and (LineB <> nil) then
    begin
      VertA := LineA.PointA.x = LineA.PointB.x;
      HorizA := LineA.PointA.y = LineA.PointB.y;
      VertB := LineB.PointA.x = LineB.PointB.x;
      HorizB := LineB.PointA.y = LineB.PointB.y;
      if HorizA and (HorizA = HorizB) then
      begin
        Mn := Min(Min(LineA.PointA.x, LineA.PointB.x), Min(LineB.PointA.x, LineB.PointB.x));
        Mx := Max(Max(LineA.PointA.x, LineA.PointB.x), Max(LineB.PointA.x, LineB.PointB.x));
        if LineA.PointA.x < LineA.PointB.x then
        begin
          LineA.PointA.x := Mn;
          LineA.PointB.x := Mx;
        end
        else
        begin
          LineA.PointB.x := Mn;
          LineA.PointA.x := Mx;
        end;
        FJDiscards.Add(LineB);
      end
      else if VertA and (VertA = VertB) then
      begin
        Mn := Min(Min(LineA.PointA.y, LineA.PointB.y), Min(LineB.PointA.y, LineB.PointB.y));
        Mx := Max(Max(LineA.PointA.y, LineA.PointB.y), Max(LineB.PointA.y, LineB.PointB.y));
        if LineA.PointA.y < LineA.PointB.y then
        begin
          LineA.PointA.y := Mn;
          LineA.PointB.y := Mx;
        end
        else
        begin
          LineA.PointB.y := Mn;
          LineA.PointA.y := Mx;
        end;
        FJDiscards.Add(LineB);
      end;
    end;
  end
  else if (Items > 2) and (not HaveJunc) and LineEnd then
    AddNewJunction(Q);

  if PerformSplit and (Items > 2) and LineEnd and (SplitLine <> nil) then
  begin
    { split the wire the junction sits in the middle of }
    Src := SplitLine as TDrawLine;
    NewLine := Src.Clone as TDrawLine;
    NewLine.PointA := Src.PointA;
    NewLine.PointB := Q;
    AddObject(NewLine);
    SplitLine.PointA := Q;
  end;
end;

{ ===========================================================================
  TWireEngine.CheckTodoList  (procedure)
  Parameters:
    PerformSplit: Boolean - allow splitting and merging
  Notes:
    Runs the junction check for everything on the to-do list, empties the list, and (when
    splitting) deletes the wires the checks marked as merged away.
  =========================================================================== }
procedure TWireEngine.CheckTodoList(PerformSplit: Boolean);
var
  i: Integer;
begin
  if not Opts.AutoJunction then
    Exit;
  i := 0;
  while i < Length(FTodoA) do
  begin
    if FTodoIsPoint[i] then
      CheckJunctionRequirement(FTodoA[i], PerformSplit)
    else
      CheckJunctionRequirement(FTodoA[i], FTodoB[i], PerformSplit);
    Inc(i);
  end;
  SetLength(FTodoA, 0);
  SetLength(FTodoB, 0);
  SetLength(FTodoIsPoint, 0);
  if PerformSplit then
  begin
    for i := 0 to FJDiscards.Count - 1 do
      DeleteObject(TDrawingObject(FJDiscards[i]));
    FJDiscards.Clear;
  end;
end;

{ ===========================================================================
  TWireEngine.Merge  (procedure)
  Parameters:  none
  Notes:
    CDragUtils::Merge: join a dragged wire to collinear wires that continue it
  =========================================================================== }
procedure TWireEngine.Merge;
var
  w, i: Integer;
  Pointer_, Test, MergeA, MergeB: TDrawingObject;
  Vert, Horiz, IsJuncA, IsJuncB, TestVert, TestHoriz, DoMergeA, DoMergeB: Boolean;
  Dd: Double;
  NewA, NewB: TDPoint;
  LenTest, LenPtr: Double;
begin
  for w := 0 to FDragged.Count - 1 do
  begin
    Pointer_ := TDrawingObject(FDragged[w]);
    if (Pointer_.GetType = xWire) and PointsClose(Pointer_.PointA, Pointer_.PointB) then
      if FDDiscards.IndexOf(Pointer_) < 0 then
        FDDiscards.Add(Pointer_);
    if (Pointer_.GetType = xWire) and (FDDiscards.IndexOf(Pointer_) < 0) then
    begin
      Vert := Pointer_.PointA.x = Pointer_.PointB.x;
      Horiz := Pointer_.PointA.y = Pointer_.PointB.y;
      MergeA := nil;
      MergeB := nil;
      IsJuncA := False;
      IsJuncB := False;
      for i := 0 to FSheet.Drawing.Count - 1 do
      begin
        Test := FSheet.Drawing[i];
        if Test.GetType = xJunction then
        begin
          if PointsClose(Test.PointA, Pointer_.PointA) then
            IsJuncA := True;
          if PointsClose(Test.PointA, Pointer_.PointB) then
            IsJuncB := True;
        end;
        if (Test <> Pointer_) and (FDDiscards.IndexOf(Test) < 0) then
          if (Test.GetType = xWire) and PointNotEqual(Test.PointA, Test.PointB) then
          begin
            DoMergeA := LineIsPointOnLine(Test.PointA, Test.PointB, Pointer_.PointA, Dd);
            DoMergeB := LineIsPointOnLine(Test.PointA, Test.PointB, Pointer_.PointB, Dd);
            if DoMergeA or DoMergeB then
            begin
              TestVert := Test.PointA.x = Test.PointB.x;
              TestHoriz := Test.PointA.y = Test.PointB.y;
              LenTest := LineLength(Test.PointA, Test.PointB);
              LenPtr := LineLength(Pointer_.PointA, Pointer_.PointB);
              if DoMergeA and DoMergeB and (LenTest <= LenPtr) then
                FDDiscards.Add(Test) // lies entirely under the new wire
              else if (TestVert and (TestVert = Vert)) or (TestHoriz and (TestHoriz = Horiz)) then
              begin
                if SingleSelected <> Test then
                begin
                  if DoMergeA then
                    MergeA := Test
                  else
                    MergeB := Test;
                end;
              end;
            end;
          end;
      end;
      if (MergeA <> nil) and (not IsJuncA) then
      begin
        NewB := Pointer_.PointB;
        if PointsClose(MergeA.PointA, Pointer_.PointA) then
          NewA := MergeA.PointB
        else
          NewA := MergeA.PointA;
        if not LineIsPointOnLine(Pointer_.PointA, Pointer_.PointB, NewA, Dd) then
        begin
          Pointer_.PointA := NewA;
          Pointer_.PointB := NewB;
        end;
        FDDiscards.Add(MergeA);
      end;
      if (MergeB <> nil) and (not IsJuncB) then
      begin
        NewA := Pointer_.PointA;
        if PointsClose(MergeB.PointA, Pointer_.PointB) then
          NewB := MergeB.PointB
        else
          NewB := MergeB.PointA;
        if not LineIsPointOnLine(Pointer_.PointA, Pointer_.PointB, NewB, Dd) then
        begin
          Pointer_.PointA := NewA;
          Pointer_.PointB := NewB;
        end;
        FDDiscards.Add(MergeB);
      end;
    end;
  end;
end;

{ ===========================================================================
  TWireEngine.Clean  (procedure)
  Parameters:  none
  Notes:
    CDragUtils::Clean: drop zero-length wires and discarded ones, and note what needs a junction
    check
  =========================================================================== }
procedure TWireEngine.Clean;
var
  w, i: Integer;
  Pointer_: TDrawingObject;
begin
  for w := 0 to FDragged.Count - 1 do
  begin
    Pointer_ := TDrawingObject(FDragged[w]);
    if (Pointer_.GetType = xWire) and PointsClose(Pointer_.PointA, Pointer_.PointB) then
    begin
      if FDDiscards.IndexOf(Pointer_) < 0 then
        FDDiscards.Add(Pointer_);
    end
    else
      AddObjectToTodo(Pointer_);
  end;
  for i := 0 to FDDiscards.Count - 1 do
  begin
    AddObjectToTodo(TDrawingObject(FDDiscards[i]));
    DeleteObject(TDrawingObject(FDDiscards[i]));
  end;
end;

{ ===========================================================================
  TWireEngine.EndDrag  (procedure)
  Parameters:  none
  Notes:
    Finishes an edit of the wires in the dragged list (CDragUtils::End): drops wires that are
    gone, merges them with collinear neighbours, cleans zero-length ones, then runs the junction
    checks.
  =========================================================================== }
procedure TWireEngine.EndDrag;
var
  i: Integer;
begin
  FDDiscards.Clear;
  { forget wires that are no longer in the drawing }
  for i := FDragged.Count - 1 downto 0 do
    if IndexInDrawing(TDrawingObject(FDragged[i])) < 0 then
      FDragged.Delete(i);
  Merge;
  Clean;
  FDDiscards.Clear; // (the objects were deleted by Clean)
  CheckTodoList(True);
  FDragged.Clear;
end;

{ ===========================================================================
  TWireEngine.MergeLinePoint  (procedure)
  Parameters:
    Obj: TDrawingObject - the wire just added to the sheet
  Notes:
    Entry point used after a wire has been stored: treats it as the dragged wire and runs the
    merge, clean and junction pass so it joins neighbouring wires and gets junctions and splits.
  =========================================================================== }
procedure TWireEngine.MergeLinePoint(Obj: TDrawingObject);
begin
  FDDiscards.Clear;
  FDragged.Clear;
  FDragged.Add(Obj);
  EndDrag;
end;

{ ================================================================ dragging }

{ ===========================================================================
  TDragWire.Create  (constructor)
  Parameters:
    AObj: TDrawingObject - the wire
    AMoveA: Boolean - True if its first end moves with the drag
    AMoveB: Boolean - True if its second end moves with the drag
  Notes:
    Creates the record for a wire taking part in a drag: which of its ends move, with no
    attachment to another wire yet.
  =========================================================================== }
constructor TDragWire.Create(AObj: TDrawingObject; AMoveA, AMoveB: Boolean);
begin
  inherited Create;
  Obj := AObj;
  MoveA := AMoveA;
  MoveB := AMoveB;
  AttLineA := nil;
  AttLineB := nil;
  DistA := 0;
  DistB := 0;
  DoneA := False;
  DoneB := False;
end;

{ ===========================================================================
  TWireEngine.DW  (function)
  Parameters:
    Index: Integer - position
  Returns:
    TDragWire - the entry
  Notes:
    One entry of the dragged-wire list.
  =========================================================================== }
function TWireEngine.DW(Index: Integer): TDragWire;
begin
  Result := TDragWire(FDWires[Index]);
end;

{ ===========================================================================
  TWireEngine.FindDWire  (function)
  Parameters:
    Obj: TDrawingObject - the wire
  Returns:
    TDragWire - the entry, or nil if the wire is not dragged
  Notes:
    Finds the entry for a wire in the dragged-wire list.
  =========================================================================== }
function TWireEngine.FindDWire(Obj: TDrawingObject): TDragWire;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to FDWires.Count - 1 do
    if DW(i).Obj = Obj then
    begin
      Result := DW(i);
      Exit;
    end;
end;

{ ===========================================================================
  IsWireOrBus  (function)
  Parameters:
    Obj: TDrawingObject - the object
  Returns:
    Boolean - True for wires and buses
  Notes:
    Whether an object is a wire or a bus (the objects that stretch when something attached
    moves).
  =========================================================================== }
function IsWireOrBus(Obj: TDrawingObject): Boolean;
begin
  Result := (Obj.GetType = xWire) or (Obj.GetType = xBus);
end;

{ ===========================================================================
  TWireEngine.AddWireToCollection  (procedure)
  Parameters:
    N: TDragWire - the entry to add; the list takes it, or frees it when the wire was already th
      ere
  Notes:
    Adds a wire to the drag, or, if it is already there, makes both of its ends move that were
    asked to (CDragUtils::AddWireToCollection). A newly added wire brings along the wires
    attached to it.
  =========================================================================== }
procedure TWireEngine.AddWireToCollection(N: TDragWire);
var
  Old: TDragWire;
begin
  Old := FindDWire(N.Obj);
  if Old = nil then
  begin
    FDWires.Add(N);
    { any wires attached to this one come along too }
    if IsWireOrBus(N.Obj) then
      AddAttachedObjects(N.Obj, N.MoveA, N.MoveB);
  end
  else
  begin
    if N.MoveA and (not Old.MoveA) then
    begin
      Old.MoveA := True;
      Old.AttLineA := N.AttLineA;
      Old.DistA := N.DistA;
    end;
    if N.MoveB and (not Old.MoveB) then
    begin
      Old.MoveB := True;
      Old.AttLineB := N.AttLineB;
      Old.DistB := N.DistB;
    end;
    N.Free;
  end;
end;

{ ===========================================================================
  TWireEngine.AddWiresAtPoint  (procedure)
  Parameters:
    const P: TDPoint - the connection point
  Notes:
    Adds every wire that is not selected and ends at a point (a pin, say) to the drag, with that
    end moving.
  =========================================================================== }
procedure TWireEngine.AddWiresAtPoint(const P: TDPoint);
var
  i: Integer;
  O: TDrawingObject;
begin
  for i := 0 to FSheet.Drawing.Count - 1 do
  begin
    O := FSheet.Drawing[i];
    if (Selected.IndexOf(O) < 0) and IsWireOrBus(O) and (PointsClose(O.PointA, P) or PointsClose(O.PointB, P)) then
      AddWireToCollection(TDragWire.Create(O, PointsClose(O.PointA, P), PointsClose(O.PointB, P)));
  end;
end;

{ Wires that start or end on the middle of a dragged wire move with it (the end stays at the same
  fraction of the wire's length) }

{ ===========================================================================
  TWireEngine.AddAttachedObjects  (procedure)
  Parameters:
    Wire: TDrawingObject - the wire being dragged
    WireMoveA: Boolean - True if its first end moves
    WireMoveB: Boolean - True if its second end moves
  Notes:
    Adds the wires that start or end on the middle of a dragged wire, remembering how far along
    it they are, so they are put back at the same fraction when it moves
    (CDragUtils::AddAttachedObjects).
  =========================================================================== }
procedure TWireEngine.AddAttachedObjects(Wire: TDrawingObject; WireMoveA, WireMoveB: Boolean);
var
  i: Integer;
  O: TDrawingObject;
  DA, DB: Double;
  MA, MB, Use: Boolean;
  N: TDragWire;
begin
  { a wire of no length has nothing attached to it that could move along it: C++ gets a NaN fraction there, for which both tests below are false, so nothing is
    added; here the division would raise an exception (a copy pasted again and again can leave such a wire) }
  if (Wire.PointA.x = Wire.PointB.x) and (Wire.PointA.y = Wire.PointB.y) then
    Exit;
  for i := 0 to FSheet.Drawing.Count - 1 do
  begin
    O := FSheet.Drawing[i];
    if (O = Wire) or (not IsWireOrBus(O)) then
      Continue;
    DA := 0; DB := 0;
    MA := LineIsPointOnLine(Wire.PointA, Wire.PointB, O.PointA, DA);
    MB := LineIsPointOnLine(Wire.PointA, Wire.PointB, O.PointB, DB);
    if MA or MB then
    begin
      Use := False;
      N := TDragWire.Create(O, MA, MB);
      if MA then
      begin
        if (WireMoveA and (DA < 1.0)) or (WireMoveB and (DA > 0)) then
          Use := True;
        N.DistA := DA;
        N.AttLineA := Wire;
      end;
      if MB then
      begin
        if (WireMoveA and (DB < 1.0)) or (WireMoveB and (DB > 0)) then
          Use := True;
        N.DistB := DB;
        N.AttLineB := Wire;
      end;
      if Use then
        AddWireToCollection(N)
      else
        N.Free;
    end;
  end;
end;

{ ===========================================================================
  TWireEngine.MoveAttachedObjects  (procedure)
  Parameters:
    Wire: TDrawingObject - the wire that moved
  Notes:
    After a wire has moved, puts the wires attached to it back at the same fraction along it,
    and does the same for wires attached to those (CDragUtils::MoveAttachedObjects).
  =========================================================================== }
procedure TWireEngine.MoveAttachedObjects(Wire: TDrawingObject);
var
  i: Integer;
  Updated: Boolean;
  D: TDragWire;
begin
  i := 0;
  while i < FDWires.Count do
  begin
    D := DW(i);
    Updated := False;
    if (not D.DoneA) and D.MoveA and (D.AttLineA = Wire) then
    begin
      Updated := True;
      D.Obj.PointA := LinePointAt(Wire.PointA, Wire.PointB, D.DistA);
      D.DoneA := True;
    end;
    if (not D.DoneB) and D.MoveB and (D.AttLineB = Wire) then
    begin
      Updated := True;
      D.Obj.PointB := LinePointAt(Wire.PointA, Wire.PointB, D.DistB);
      D.DoneB := True;
    end;
    if Updated then
      MoveAttachedObjects(D.Obj);
    Inc(i);
  end;
end;

{ ===========================================================================
  TWireEngine.DisplayDraggedWires  (procedure)
  Parameters:  none
  Notes:
    Marks every dragged wire for the junction check and clears its "already moved" flags, ready
    for the next step.
  =========================================================================== }
procedure TWireEngine.DisplayDraggedWires;
var
  i: Integer;
begin
  for i := 0 to FDWires.Count - 1 do
  begin
    AddObjectToTodo(DW(i).Obj);
    DW(i).DoneA := False;
    DW(i).DoneB := False;
  end;
end;

{ ===========================================================================
  TWireEngine.CollectDragged  (procedure)
  Parameters:  none
  Notes:
    Finds every wire that has to follow the selection (CDragUtils::Begin): wires ending at the
    connection points of the selected objects, and for selected wires the ends inside the
    selection area (if neither end is inside, both move).
  =========================================================================== }
procedure TWireEngine.CollectDragged;
var
  i, k: Integer;
  O: TDrawingObject;
  Act: TPointList;
  MoveA, MoveB: Boolean;
  L, R, T, B: Double;
begin
  FDStarted := True;
  FDWires.Clear;
  { wires attached to the connection points of the selected objects }
  for i := 0 to Selected.Count - 1 do
  begin
    Act := ActivePointsOf(TDrawingObject(Selected[i]));
    for k := 0 to High(Act) do AddWiresAtPoint(Act[k]);
  end;
  { selected wires: the ends inside the selection area move; if neither is inside, both move }
  L := Min(FDA.x, FDB.x); R := Max(FDA.x, FDB.x);
  T := Min(FDA.y, FDB.y); B := Max(FDA.y, FDB.y);
  for i := 0 to Selected.Count - 1 do
  begin
    O := TDrawingObject(Selected[i]);
    if not IsWireOrBus(O) then
      Continue;
    MoveA := (O.PointA.x >= L) and (O.PointA.x <= R) and (O.PointA.y >= T) and (O.PointA.y <= B);
    MoveB := (O.PointB.x >= L) and (O.PointB.x <= R) and (O.PointB.y >= T) and (O.PointB.y <= B);
    if Length(PullPoints) > 0 then
    begin
      { end handles pulled together: only the wire ends at the pulled points move }
      MoveA := False;
      MoveB := False;
      for k := 0 to High(PullPoints) do
      begin
        if (O.PointA.x = PullPoints[k].x) and (O.PointA.y = PullPoints[k].y) then
          MoveA := True;
        if (O.PointB.x = PullPoints[k].x) and (O.PointB.y = PullPoints[k].y) then
          MoveB := True;
      end;
      if not (MoveA or MoveB) then
        Continue;
    end;
    if (not MoveA) and (not MoveB) then
    begin
      MoveA := True;
      MoveB := True;
      AddWiresAtPoint(O.PointA);
      AddWiresAtPoint(O.PointB);
    end;
    AddWireToCollection(TDragWire.Create(O, MoveA, MoveB));
  end;
end;

{ ===========================================================================
  TWireEngine.BeginDrag  (procedure)
  Parameters:
    const AreaA: TDPoint - first corner of the area
    const AreaB: TDPoint - opposite corner
  Notes:
    Starts a move of the selected objects. The area is the rectangle the selection was picked
    with: a selected wire with an end inside it only has that end moved, so it stretches; a
    click picks with a point, a selection box with its rectangle.
  =========================================================================== }
procedure TWireEngine.BeginDrag(const AreaA, AreaB: TDPoint);
begin
  FDWires.Clear;
  FDStarted := False;
  SetLength(PullPoints, 0);
  FDA := AreaA;
  FDB := AreaB;
end;

{ ===========================================================================
  TWireEngine.DragBy  (procedure)
  Parameters:
    const R: TDPoint - how far to move, in design units
  Notes:
    Moves the selection by a step and stretches the wires attached to it (CDragUtils::Drag): the
    objects shift, wire ends at their connection points follow, wires attached to the middle of
    those wires follow along, and junctions that are needed or no longer needed are added or
    removed.
  =========================================================================== }
procedure TWireEngine.DragBy(const R: TDPoint);
var
  i: Integer;
  O: TDrawingObject;
  Moved: Boolean;
  D: TDragWire;
begin
  if not FDStarted then
    CollectDragged;
  if (R.x = 0) and (R.y = 0) then
    Exit;
  { the objects that are not wires being stretched just move }
  for i := 0 to Selected.Count - 1 do
  begin
    O := TDrawingObject(Selected[i]);
    if FindDWire(O) = nil then
    begin
      AddObjectToTodo(O);
      O.Shift(R);
      AddObjectToTodo(O);
    end;
  end;
  DisplayDraggedWires;
  for i := 0 to FDWires.Count - 1 do
  begin
    D := DW(i);
    Moved := False;
    if D.MoveA and (D.AttLineA = nil) then
    begin
      D.DoneA := True;
      D.Obj.PointA := DPoint(D.Obj.PointA.x + R.x, D.Obj.PointA.y + R.y);
      Moved := True;
    end;
    if D.MoveB and (D.AttLineB = nil) then
    begin
      D.DoneB := True;
      D.Obj.PointB := DPoint(D.Obj.PointB.x + R.x, D.Obj.PointB.y + R.y);
      Moved := True;
    end;
    if Moved then
      MoveAttachedObjects(D.Obj);
  end;
  DisplayDraggedWires;
  FDA := DPoint(FDA.x + R.x, FDA.y + R.y);
  FDB := DPoint(FDB.x + R.x, FDB.y + R.y);
  CheckTodoList(False);   // junctions that are needed or no longer needed; no splitting while dragging
end;

{ ===========================================================================
  TWireEngine.MoveBy  (procedure)
  Parameters:
    const R: TDPoint - how far to move, in design units
  Notes:
    Moves the selection by a step without dragging wires along (CDragUtils::Move), then re-
    checks junctions. The view uses it for Ctrl-drag and while a pasted block follows the mouse.
  =========================================================================== }
procedure TWireEngine.MoveBy(const R: TDPoint);
var
  i: Integer;
  O: TDrawingObject;
begin
  if not FDStarted then
    CollectDragged;
  if (R.x = 0) and (R.y = 0) then
    Exit;
  for i := 0 to Selected.Count - 1 do
  begin
    O := TDrawingObject(Selected[i]);
    AddObjectToTodo(O);
    O.Shift(R);
    AddObjectToTodo(O);
  end;
  FDA := DPoint(FDA.x + R.x, FDA.y + R.y);
  FDB := DPoint(FDB.x + R.x, FDB.y + R.y);
  CheckTodoList(False);
end;

{ ===========================================================================
  TWireEngine.FinishDrag  (procedure)
  Parameters:  none
  Notes:
    Ends a move: merges collinear wires, removes zero-length ones, and re-checks junctions with
    splitting allowed (CDragUtils::End). Call once, when the mouse is released.
  =========================================================================== }
procedure TWireEngine.FinishDrag;
var
  i: Integer;
begin
  if not FDStarted then
    CollectDragged;   // a move that was never dragged still gets its junctions tidied
  FDragged.Clear;
  for i := 0 to FDWires.Count - 1 do FDragged.Add(DW(i).Obj);
  EndDrag;
  FDWires.Clear;
  FDStarted := False;
end;

{ ================================================================ TWireTool }

{ ===========================================================================
  TWireTool.Create  (constructor)
  Parameters:
    AEngine: TWireEngine - the engine for the sheet being drawn on
    AKind: TObjType - xWire for wires, xLineEx2 for lines
  Notes:
    Creates a wire or line tool bound to an engine and sets it up as TinyCAD does: wires use the
    90 degree angle mode and the default wire style; plain lines draw at any angle.
  =========================================================================== }
constructor TWireTool.Create(AEngine: TWireEngine; AKind: TObjType);
begin
  inherited Create;
  FEngine := AEngine;
  FKind := AKind;
  if FKind = xWire then
    Angle := am90
  else
    Angle := amFree;
  UseDefaultStyle := FKind in [xWire, xBus];
  Style := 0;
  BeginEdit;
end;

{ ===========================================================================
  TWireTool.BeginEdit  (procedure)
  Parameters:  none
  Notes:
    Resets the tool to "waiting for the first point": no segment in progress, no sticking, no
    segments stored yet.
  =========================================================================== }
procedure TWireTool.BeginEdit;
begin
  Segment := 1;
  Mode := 0;
  IsStuck := False;
  IsJunction := False;
  HasPlaced := False;
  Stored := 0;
  A := DPoint(0, 0);
  B := DPoint(0, 0);
end;

{ ===========================================================================
  TWireTool.StickyFor  (function)
  Parameters:
    const NoSnap: TDPoint - the raw mouse position
  Returns:
    TDPoint - the point to use
  Notes:
    The point to use for a mouse position: wires stick to pins and wires through the engine;
    plain lines just snap to the grid.
  =========================================================================== }
function TWireTool.StickyFor(const NoSnap: TDPoint): TDPoint;
begin
  if FKind <> xWire then
  begin
    Result := FEngine.Sheet.Snap.Snap(NoSnap);
    Exit;
  end;
  Result := FEngine.StickyPoint(NoSnap, True, True, IsStuck, IsJunction);
end;

{ ===========================================================================
  TWireTool.ToAngle  (procedure)
  Parameters:  none
  Notes:
    Applies the angle rule to the end point B of the segment being drawn: in 90 degree mode it
    picks horizontal-first or vertical-first for the dog-leg; in 45 degree mode it forces B onto
    the nearest 45 degree line; otherwise it does nothing.
  =========================================================================== }
procedure TWireTool.ToAngle;
var
  FromX, FromY, FromC: Double;
begin
  case Angle of
    am90:
      begin
        if A.x = B.x then
          Mode := 2;
        if A.y = B.y then
          Mode := 1;
        if Mode = 0 then
          Mode := 1;
      end;
    am45:
      begin
        Mode := 0;
        { which 45 degree slope is it closest to? }
        FromX := Abs(A.x - B.x);
        FromY := Abs(A.y - B.y);
        FromC := Abs(FromX - FromY);
        if (FromX < FromY) and (FromX < FromC) then
          B.x := A.x
        else if FromY < FromC then
          B.y := A.y
        else if B.x > A.x then
          B.x := A.x + FromY
        else
          B.x := A.x - FromY;
      end;
  else
    Mode := 0;
  end;
end;

{ ===========================================================================
  TWireTool.Store  (function)
  Parameters:  none
  Returns:
    TDrawLine
  Notes:
    CDrawLine::Store: put the current segment in the drawing
  =========================================================================== }
function TWireTool.Store: TDrawLine;
begin
  Segment := 1;
  Result := TDrawLine.CreateKind(FEngine.Sheet.Options, FKind);
  Result.PointA := A;
  Result.PointB := B;
  Result.UseDefaultStyle := UseDefaultStyle;
  Result.Style := Style;
  if Assigned(OnNewLine) then
    OnNewLine(Result);
  FEngine.AddObject(Result);
  if FEngine.RecordRaw then
  begin
    SetLength(FEngine.RawA, Length(FEngine.RawA) + 1);
    SetLength(FEngine.RawB, Length(FEngine.RawB) + 1);
    FEngine.RawA[High(FEngine.RawA)] := A;
    FEngine.RawB[High(FEngine.RawB)] := B;
  end;
  Inc(Stored);
end;

{ ===========================================================================
  TWireTool.LButtonDown  (procedure)
  Parameters:
    const NoSnap: TDPoint - the raw mouse position
  Notes:
    Handles a left click as TinyCAD's line tool does. The first click starts a segment (adding a
    junction if it starts on a wire or pin junction and copying the style of a wire under it).
    Later clicks store the segment (as an L of two wires in 90 degree mode when the end sticks)
    and carry on from the end, or finish when the end stuck to a pin or wire.
  =========================================================================== }
procedure TWireTool.LButtonDown(const NoSnap: TDPoint);
var
  P, C: TDPoint;
  WasStuck, OldJunction: Boolean;
  i: Integer;
  Obj: TDrawingObject;
  Dd: Double;
begin
  P := StickyFor(NoSnap);
  if Segment <> 0 then
  begin
    { first point of a new segment }
    A := P;
    B := P;
    if Segment <> 0 then
      Segment := 0
    else
      Segment := 1;
    if IsJunction then
      FEngine.AddNewJunction(A);
    { if there was an object of the same type under this point, take its color and style }
    for i := 0 to FEngine.Sheet.Drawing.Count - 1 do
    begin
      Obj := FEngine.Sheet.Drawing[i];
      if Obj.GetType = FKind then
        if LineIsPointOnLine(Obj.PointA, Obj.PointB, P, Dd) then
        begin
          UseDefaultStyle := (Obj as TDrawLine).UseDefaultStyle;
          Style := (Obj as TDrawLine).Style;
          Break;
        end;
    end;
  end
  else
  begin
    B := P;
    ToAngle;
    C := B;
    case Mode of
      1: B := DPoint(B.x, A.y);
      2: B := DPoint(A.x, B.y);
    end;
    WasStuck := IsStuck;
    if IsStuck and (Mode > 0) then
    begin
      OldJunction := IsJunction;
      IsJunction := False;
      { place two lines: the first leg, then the second }
      IsStuck := False;
      if PointNotEqual(A, B) then
        FEngine.MergeLinePoint(Store);
      A := B;
      B := C;
      IsJunction := OldJunction;
    end;
    IsStuck := False;
    if PointNotEqual(A, B) then
      FEngine.MergeLinePoint(Store);
    if not WasStuck then
    begin
      { carry on from the corner }
      A := B;
      B := C;
      Segment := 0;
      ToAngle;
    end
    else
      RButtonDown;
  end;
end;

{ ===========================================================================
  TWireTool.RButtonDown  (function)
  Parameters:  none
  Returns:
    Boolean - True when a segment was in progress
  Notes:
    Ends the wire being drawn (right click or finish): removes junctions that are no longer
    needed at its ends and goes back to waiting for a first point.
  =========================================================================== }
function TWireTool.RButtonDown: Boolean;
begin
  Result := Segment = 0;
  { remove any junctions we may have had in place }
  FEngine.CheckJunctionRequirement(A, False);
  FEngine.CheckJunctionRequirement(B, False);
  Segment := 1;
  A := B;
  HasPlaced := False;
  IsStuck := False;
end;

{ ===========================================================================
  TWireTool.DblLButtonDown  (procedure)
  Parameters:
    const NoSnap: TDPoint - the raw mouse position
  Notes:
    A double click: places the last segment and ends the wire.
  =========================================================================== }
procedure TWireTool.DblLButtonDown(const NoSnap: TDPoint);
begin
  LButtonDown(NoSnap); // the second line ...
  RButtonDown;         // ... and end
end;

{ ===========================================================================
  TWireTool.LButtonUp  (procedure)
  Parameters:
    const NoSnap: TDPoint - the raw mouse position
  Notes:
    On releasing the mouse: if the user pressed and dragged a real distance (more than 10 units)
    the wire is placed and ended, so press-drag-release draws a wire; otherwise the tool stays
    in click-click mode.
  =========================================================================== }
procedure TWireTool.LButtonUp(const NoSnap: TDPoint);
var
  Ox, Oy: Double;
begin
  { only for the first segment: if the user dragged a good way, this is a "press, drag, release" wire }
  if HasPlaced then
    Exit;
  Ox := Abs(A.x - B.x);
  Oy := Abs(A.y - B.y);
  if (Ox > 10) or (Oy > 10) then
  begin
    if (Segment = 0) and (not IsStuck) then
      LButtonDown(NoSnap); // first line (the C++ test is !m_segment)
    LButtonDown(NoSnap); // second line ...
    RButtonDown;         // ... and end
  end
  else
    HasPlaced := True;
end;

{ ===========================================================================
  TWireTool.Move  (procedure)
  Parameters:
    const NoSnap: TDPoint - the raw mouse position
  Notes:
    Follows the mouse: while a segment is being drawn it updates the end point (with sticking)
    and applies the angle rule; while waiting for the first point it just tracks where a click
    would land.
  =========================================================================== }
procedure TWireTool.Move(const NoSnap: TDPoint);
var
  P: TDPoint;
  NewStuck, NewJunction: Boolean;
begin
  if Segment = 0 then
  begin
    NewStuck := False;
    NewJunction := False;
    if FKind = xWire then
      P := FEngine.StickyPoint(NoSnap, True, True, NewStuck, NewJunction)
    else
      P := FEngine.Sheet.Snap.Snap(NoSnap);
    if PointNotEqual(P, B) then
    begin
      IsStuck := NewStuck;
      IsJunction := NewJunction;
      B := P;
      ToAngle;
    end;
  end
  else
  begin
    B := StickyFor(NoSnap);
    A := B;
  end;
end;

{ ===========================================================================
  TWireTool.EndEdit  (procedure)
  Parameters:  none
  Notes:
    Called when the tool is dropped: finishes any wire in progress.
  =========================================================================== }
procedure TWireTool.EndEdit;
begin
  RButtonDown;
end;

{ ===========================================================================
  TWireTool.Preview  (procedure)
  Parameters:
    out Corner: TDPoint - set to the corner point of the rubber band
  Notes:
    Gives the middle point of the rubber band to draw: the corner of the dog-leg in 90 degree
    mode, or the start point when the band is one straight piece.
  =========================================================================== }
procedure TWireTool.Preview(out Corner: TDPoint);
begin
  Corner := A;
  if Segment = 0 then
    case Mode of
      1: Corner := DPoint(B.x, A.y);
      2: Corner := DPoint(A.x, B.y);
    end;
end;

end.
