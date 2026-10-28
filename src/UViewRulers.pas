{ The rulers round the drawing area (TinyCAD shows them on the viewport): a strip along the top and one down the left side of the view, in the units of the sheet
  (millimetres or inches, the user's choice), measured from the sheet's origin when it has one, as the position bar is. They follow the zoom and the scrolling of
  the view and mark where the pointer is.

  The strips are plain controls beside the view; they hold no state of the drawing, only the view they are looking at (View), which changes with the document.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UViewRulers;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Math, Types, UView, UOptions, UDPoint, UGeometry, UPaper, consts;

type
  TRulerTick = record
    Pos: Integer;        // pixel along the ruler (in the view's own pixels: 0 is the view's left or top edge)
    Value: Double;       // the ruler's reading there, in the sheet's units
    Major: Boolean;      // has a label
  end;
  TRulerTicks = array of TRulerTick;

  { TViewRuler }

  TViewRuler = class(TCustomControl)
  private
    FVertical: Boolean;
    FView: TSchematicView;
    FThickness: Integer;
    FSig: array[0..9] of Double;     // what the ruler showed last (see Sync)
    FSigOk: Boolean;
    function Signature(out ASig: array of Double): Boolean;
    procedure SetView(AValue: TSchematicView);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent; AVertical: Boolean); reintroduce;
    { the marks the ruler draws now (empty without a design) }
    function Ticks: TRulerTicks;
    { draws the ruler again if what it shows (zoom, scroll, size, units, the sheet's origin) has changed }
    procedure Sync;
    property View: TSchematicView read FView write SetView;
    property Vertical: Boolean read FVertical;
    { the strip's width (vertical) or height (horizontal) in pixels }
    property Thickness: Integer read FThickness write FThickness;
  end;

{ the step between the labelled marks (in the sheet's units) that is at least MinPixels wide at the given pixels per unit, and the step between marks }
procedure RulerSteps(PixelsPerUnit, MinPixels: Double; out Major, Minor: Double);

implementation

{ ===========================================================================
  RulerSteps  (procedure)
  Parameters:
    PixelsPerUnit: Double - number
    MinPixels: Double - number
    out Major: Double - number (out: set by the call)
    out Minor: Double - number (out: set by the call)
  Notes:
    The smallest 1-2-5 step that is at least MinPixels wide; the small marks are a tenth of a 1
    step, a quarter of a 2 step and a fifth of a 5 step, so that they fall on round numbers.
  =========================================================================== }
procedure RulerSteps(PixelsPerUnit, MinPixels: Double; out Major, Minor: Double);
var
  Decade, M: Double;
  I: Integer;
const
  Mantissas: array[0..2] of Double = (1, 2, 5);
  Divisions: array[0..2] of Double = (10, 4, 5);
begin
  if PixelsPerUnit <= 0 then
    PixelsPerUnit := 1e-6;
  Decade := Power(10, Floor(Log10(MinPixels / PixelsPerUnit)) - 1);
  Major := Decade * 10;
  Minor := Major / 10;
  repeat
    for I := 0 to 2 do
    begin
      M := Decade * Mantissas[I];
      if M * PixelsPerUnit >= MinPixels then
      begin
        Major := M;
        Minor := M / Divisions[I];
        Exit;
      end;
    end;
    Decade := Decade * 10;
  until False;
end;

{ ===========================================================================
  TViewRuler.Create  (constructor)
  Parameters:
    AOwner: TComponent
    AVertical: Boolean - flag
  Notes:
    The strip is 18 pixels thick (set Thickness for another scale), in the colours of the
    buttons so it looks like part of the frame.
  =========================================================================== }
constructor TViewRuler.Create(AOwner: TComponent; AVertical: Boolean);
begin
  inherited Create(AOwner);
  FVertical := AVertical;
  FThickness := ViewRulerSize;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  Color := clBtnFace;
end;

{ ===========================================================================
  TViewRuler.SetView  (procedure)
  Parameters:
    AValue: TSchematicView - the value
  Notes:
    Changes the view and draws the ruler for it.
  =========================================================================== }
procedure TViewRuler.SetView(AValue: TSchematicView);
begin
  FView := AValue;
  FSigOk := False;
  Invalidate;
end;

{ ===========================================================================
  TViewRuler.Ticks  (function)
  Parameters:  none
  Returns:
    TRulerTicks
  Notes:
    The reading at a pixel p of the view is (p / zoom + scroll - the sheet's origin) in
    millimetres, divided by 25.4 for inches. The labelled marks are at least 60 pixels apart (at
    least 40 on a short strip); the small marks are not drawn closer than 4 pixels.
  =========================================================================== }
function TViewRuler.Ticks: TRulerTicks;
var
  Zoom, Scale, Org, Edge, Len, Lo, Hi, Major, Minor, V: Double;
  N, Cnt: Integer;
begin
  SetLength(Result, 0);
  if (FView = nil) or (FView.Sheet = nil) then
    Exit;
  Zoom := FView.Zoom;
  Scale := 1;                                        // millimetres per unit of the ruler
  if FView.Sheet.Options.Units = UNITS_INCHES then
    Scale := 25.4;
  if FVertical then
  begin
    Len := FView.ClientHeight;
    Org := FView.Origin.y;
  end
  else
  begin
    Len := FView.ClientWidth;
    Org := FView.Origin.x;
  end;
  Edge := 0;                                         // the sheet's origin, in design units, along this axis
  if FView.Sheet.Options.HasOrigin then
  begin
    if FVertical then
      Edge := FView.Sheet.Options.Origin.y
    else
      Edge := FView.Sheet.Options.Origin.x;
  end;
  RulerSteps(UNITS_PER_MM * Scale * Zoom, 60, Major, Minor);
  while Minor * UNITS_PER_MM * Scale * Zoom < 4 do
    Minor := Minor * 2;
  Lo := ((Org - Edge) / UNITS_PER_MM) / Scale;
  Hi := ((Org + Len / Zoom - Edge) / UNITS_PER_MM) / Scale;
  N := Floor(Lo / Minor) - 1;
  Cnt := 0;
  repeat
    V := N * Minor;
    SetLength(Result, Cnt + 1);
    Result[Cnt].Value := V;
    Result[Cnt].Pos := Round((V * Scale * UNITS_PER_MM + Edge - Org) * Zoom);
    Result[Cnt].Major := Abs(V / Major - Round(V / Major)) * Major < Minor * 0.01;
    Inc(Cnt);
    Inc(N);
  until V > Hi + Minor;
end;

{ ===========================================================================
  TViewRuler.Signature  (function)
  Parameters:
    out ASig: array of Double - out: set by the call
  Returns:
    Boolean
  Notes:
    The zoom, the scroll, the length of the view, the units, the sheet's origin and the pointer:
    when none of them has changed the ruler need not be drawn again.
  =========================================================================== }
function TViewRuler.Signature(out ASig: array of Double): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(ASig) do
    ASig[I] := 0;
  Result := (FView <> nil) and (FView.Sheet <> nil);
  if not Result then
    Exit;
  ASig[0] := FView.Zoom;
  ASig[1] := FView.Origin.x;
  ASig[2] := FView.Origin.y;
  if FVertical then
    ASig[3] := FView.ClientHeight
  else
    ASig[3] := FView.ClientWidth;
  ASig[4] := FView.Sheet.Options.Units;
  if FView.Sheet.Options.HasOrigin then
  begin
    ASig[5] := FView.Sheet.Options.Origin.x;
    ASig[6] := FView.Sheet.Options.Origin.y;
  end;
  if FView.HasPointer then
  begin
    ASig[7] := 1;
    if FVertical then
      ASig[8] := FView.PointerPixel.y
    else
      ASig[8] := FView.PointerPixel.x;
  end;
  ASig[9] := Width + Height;
end;

{ ===========================================================================
  TViewRuler.Sync  (procedure)
  Parameters:  none
  Notes:
    The view calls this (through the main form) whenever it has been drawn or the pointer has
    moved: the ruler is drawn again only if what it shows (Signature) has changed since it was
    last drawn.
  =========================================================================== }
procedure TViewRuler.Sync;
var
  Sig: array[0..9] of Double;
  Have: Boolean;
  I: Integer;
  Same: Boolean;
begin
  Have := Signature(Sig);
  Same := FSigOk = Have;
  if Same and Have then
    for I := 0 to High(Sig) do
      if Sig[I] <> FSig[I] then
        Same := False;
  if Same then
    Exit;
  FSigOk := Have;
  for I := 0 to High(Sig) do
    FSig[I] := Sig[I];
  Invalidate;
end;

{ ===========================================================================
  TViewRuler.Paint  (procedure)
  Parameters:  none
  Notes:
    Draws the ruler: the marks and the numbers at the labelled ones (turned to read upwards on
    the vertical ruler), the edge next to the view, and a red mark where the pointer is over the
    view. The top ruler's left end (as wide as the left ruler) is the empty corner, so the marks
    line up with the view, which starts after the left ruler.
  =========================================================================== }
procedure TViewRuler.Paint;
var
  T: TRulerTicks;
  I, P, Th, Len, Off, MinorLen, MajorLen: Integer;
  S: String;
  Frac: Boolean;
  Major, Minor: Double;
  C: TCanvas;
begin
  C := Canvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := clBtnFace;
  C.FillRect(ClientRect);
  Th := FThickness;
  if (FView = nil) or (FView.Sheet = nil) then
    Exit;
  Off := 0;
  if not FVertical then
    Off := FThickness;                 // the corner
  C.Font.Assign(Font);
  C.Font.Size := 7;
  C.Font.Color := clWindowText;
  C.Pen.Color := clWindowText;
  C.Pen.Width := 1;
  T := Ticks;
  Len := IfThen(FVertical, Height, Width);
  MajorLen := Th - 3;
  MinorLen := Th div 3;
  RulerSteps(UNITS_PER_MM * FView.Zoom * IfThen(FView.Sheet.Options.Units = UNITS_INCHES, 25.4, 1.0), 60, Major, Minor);
  Frac := Major < 1;
  C.Brush.Style := bsClear;
  for I := 0 to High(T) do
  begin
    P := T[I].Pos + Off;
    if (T[I].Pos < 0) or (P > Len) then
      Continue;
    if FVertical then
    begin
      if T[I].Major then
        C.Line(Th - MajorLen, P, Th, P)
      else
        C.Line(Th - MinorLen, P, Th, P);
    end
    else
    begin
      if T[I].Major then
        C.Line(P, Th - MajorLen, P, Th)
      else
        C.Line(P, Th - MinorLen, P, Th);
    end;
    if T[I].Major then
    begin
      if Frac then
        S := FormatFloat('0.###', T[I].Value)
      else
        S := FormatFloat('0', T[I].Value);
      if S = '-0' then
        S := '0';
      if FVertical then
      begin
        C.Font.Orientation := 900;
        C.TextOut(1, P - 2, S);
        C.Font.Orientation := 0;
      end
      else
        C.TextOut(P + 2, 1, S);
    end;
  end;
  { the edge next to the view }
  C.Pen.Color := clGrayText;
  if FVertical then
    C.Line(Th - 1, 0, Th - 1, Height)
  else
    C.Line(0, Th - 1, Width, Th - 1);
  { the pointer }
  if FView.HasPointer then
  begin
    C.Pen.Color := clRed;
    if FVertical then
    begin
      P := FView.PointerPixel.y;
      C.Line(0, P, Th, P);
    end
    else
    begin
      P := FView.PointerPixel.x + Off;
      C.Line(P, 0, P, Th);
    end;
  end;
end;

end.
