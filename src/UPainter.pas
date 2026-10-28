// SPDX-License-Identifier: LGPL-2.1-or-later
{ Draws a design sheet onto a TCanvas. This is the "Paint" half of the TinyCAD object classes,
  rewritten for the LCL canvas. Everything is positioned with the same TTransform the C++ code
  uses (zoom, origin, and the rotate/mirror/scale set up for a placed symbol), so symbols are drawn
  exactly where the data layer's geometry says they are.

  Fidelity notes: pin and power-symbol shapes, hatch patterns and note-text wrapping are close
  approximations of TinyCAD's, not pixel copies; text is drawn with whatever font the platform has
  in place of the named one (the data layer still measures text with its Arial-like metrics so
  that geometry matches the saved files).

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UPainter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Math, Types, UDPoint, UDrawTypes, UGeometry, UResources,
  UDrawingObjects, USymbols, UDesign, UPaper, UImageLoad, URevisions, UTitleBlock, UOrient;

{ The width in pixels of a grid dot: one screen pixel in the 1 px grid mode, else as many as the zoom is hundreds of per cent (at least 1) }
function GridDotSize(Zoom: Double; OnePx: Boolean): Integer;

type
  TPxArray = array of TPoint;      // points in pixels

  TSchematicPainter = class
  private
    FCanvas: TCanvas;
    FT: TTransform;
    FOpts: TDocOptionsBase;
    FSel: Boolean;
    FSelColor: TColor;
    FPageW, FPageH: Integer;
    FPrinting, FAllBlack, FHideSymbolText, FHideSymbolFields: Boolean;
    FForceColor: Boolean;
    FPenW, FPenDash: Integer;      // the width in pixels and the style (0 solid .. 4) the last SetPen asked for
    FForcedColor: Cardinal;
    function Px(const D: TDPoint): TPoint;
    function Dist(D: Double): Integer;
    function Col(C: Cardinal): TColor;
    procedure SetPen(Color: Cardinal; Thickness: Double; PenStyle: Integer);
    procedure Ln(const A, B: TDPoint);
    procedure DashedLn(const P1, P2: TPoint);
    function DashedPen: Boolean;
    procedure DashedPath(const Pts: array of TPoint; Closed: Boolean);
    procedure EllipsePath(L, T, R, B: Integer; out Pts: TPxArray);
    procedure RoundRectPath(L, T, R, B, Rad: Integer; out Pts: TPxArray);
    procedure Poly(const Pts: array of TPoint; Closed: Boolean);
    procedure FillBrush(FillNumber: Integer);
    procedure SetFont(FontNumber: Integer; Color: Cardinal; out ScreenHeight: Integer);
    procedure TextBox(const Str: String; const A, B: TDPoint; Rotated: Boolean; FontNumber: Integer; Color: Cardinal);
    procedure TextAt(const Str: String; const Anchor: TDPoint; Rotated: Boolean; FontNumber: Integer; Color: Cardinal);
    procedure PaintLine(O: TDrawLine);
    function MinDotRadius: Integer;
    procedure PaintJunction(O: TDrawJunction);
    procedure PaintNoConnect(O: TDrawNoConnect);
    procedure PaintError(O: TDrawError);
    procedure PaintSquare(O: TDrawSquare);
    procedure PaintPolygon(O: TDrawPolygon);
    procedure TextDir(const Str: String; const Anchor: TDPoint; Dir: Integer; FontNumber: Integer; Color: Cardinal);
    procedure AttachBox(const P: TDPoint);
    procedure PaintText(O: TDrawText);
    procedure PaintLabel(O: TDrawLabel);
    procedure PaintPower(O: TDrawPower);
    procedure PaintPin(O: TDrawPin);
    procedure PaintNote(O: TDrawNoteText);
    function WrapText(const S: String; Width: Integer): TStringList;
    procedure PaintMethod(O: TDrawMethod);
    procedure PaintHierarchicalSymbol(O: TDrawHierarchicalSymbol);
    procedure PaintLadder(O: TDrawLadder);
    procedure PaintRungGrid(O: TDrawRungGrid);
    procedure PaintBusSlash(O: TDrawBusSlash);
    procedure PaintRuler(O: TDrawRuler);
    procedure PaintMeasure(O: TDrawMeasure);
    procedure PaintCloud(O: TDrawCloud);
    procedure PaintRefText(O: TDrawRefText);
  private
    FOnePxDots: Boolean;
  public
    constructor Create(ACanvas: TCanvas; ATransform: TTransform);
    procedure PaintObject(Obj: TDrawingObject; Selected: Boolean);
    procedure PaintSheet(Sheet: TDesignSheet; Selected: TList);
    procedure PaintObjects(Sheet: TDesignSheet; Objects: TList);
    { The paper, its shadow, the border rectangle and a dot grid; the sheet's own objects are not drawn }
    procedure PaintPage(Sheet: TDesignSheet; ShowGrid: Boolean; const Viewport: TRect;
      const AFileName: String = ''; const ASheetsText: String = ''; const ADocNoText: String = '');
    procedure PaintTitleBlock(Sheet: TDesignSheet; const AFileName, ASheetsText, ADocNoText: String);
    procedure PaintExtendedBlock(Sheet: TDesignSheet);
    procedure PaintRulers(Sheet: TDesignSheet);
    procedure PaintPolygonHandles(Pg: TDrawPolygon);
    procedure PaintLineHandles(L: TDrawLine);
    procedure PaintMetaFile(O: TDrawMetaFile);
    function ContextOrient: TOrient;
    procedure PaintResizeHandles(O: TDrawingObject; HandleSize: Double);
    procedure PaintErrorMarker(const P: TDPoint; Selected: Boolean);
    procedure PaintOriginMarker(const P: TDPoint);
    procedure DetailsText(Sheet: TDesignSheet; const Str: String; X, Y: Double; Centre, Vertical: Boolean; FontNumber: Integer; MaxWidth: Double = 0);
    property Transform: TTransform read FT;
    { when set, lines are drawn in this color instead of their own (the wire being drawn is red until it is confirmed) }
    procedure ForceLineColor(AColor: Cardinal);
    { drawing for a printer: no paper, shadow or grid, and no construction objects }
    property Printing: Boolean read FPrinting write FPrinting;
    { True: the grid dots are one screen pixel at any zoom (for fine work on a symbol); False: as many pixels as the zoom is hundreds of per cent }
    property OnePxDots: Boolean read FOnePxDots write FOnePxDots;
    { every color drawn black (white fills stay white), as TinyCAD's "Print in black and white" }
    property AllBlack: Boolean read FAllBlack write FAllBlack;
    { True: symbol text objects (the designer's notes) are not drawn: the Print window's "Do not print symbol text" }
    property HideSymbolText: Boolean read FHideSymbolText write FHideSymbolText;
    { True: the fields of the symbols (reference, name, values) are not drawn: the Print window's "Do not print symbol fields" }
    property HideSymbolFields: Boolean read FHideSymbolFields write FHideSymbolFields;
  end;

implementation


uses UStrings;

{ ===========================================================================
  GridDotSize  (function)
  Parameters:
    Zoom: Double - number
    OnePx: Boolean - flag
  Returns:
    Integer
  Notes:
    TinyCAD draws a dot as many pixels wide as the zoom is whole hundreds of per cent. The 1 px
    grid mode keeps it one pixel at any zoom, so the dots stay small when working close up on
    wire and pin alignment. It changes how the grid is drawn only, not the grid spacing or where
    things snap.
  =========================================================================== }
function GridDotSize(Zoom: Double; OnePx: Boolean): Integer;
begin
  if OnePx then
    Result := 1
  else
    Result := Max(1, Round(Zoom));
end;

const
  cRULER_GUIDE = $C8C8C8;   // RGB(200,200,200) as in color.h
  cRULER_CLK = $808080;
  POWER_SIZE = 14;
  JUNCTION_R = 3;
  CONNECT_R = 4;

{ ===========================================================================
  TSchematicPainter.Create  (constructor)
  Parameters:
    ACanvas: TCanvas - the canvas to draw on
    ATransform: TTransform - converts design units to pixels; the painter does not own it
  Notes:
    Creates a painter that draws onto a canvas through a screen transform (zoom and origin).
  =========================================================================== }
constructor TSchematicPainter.Create(ACanvas: TCanvas; ATransform: TTransform);
begin
  inherited Create;
  FCanvas := ACanvas;
  FT := ATransform;
  FSelColor := TColor($0080FF); // orange (BGR)
end;

{ ===========================================================================
  TSchematicPainter.Px  (function)
  Parameters:
    const D: TDPoint - design point
  Returns:
    TPoint - the pixel position
  Notes:
    Converts a design point to a pixel position with the current transform.
  =========================================================================== }
function TSchematicPainter.Px(const D: TDPoint): TPoint;
begin
  Result := FT.Scale(D);
end;

{ ===========================================================================
  TSchematicPainter.Dist  (function)
  Parameters:
    D: Double - length in design units
  Returns:
    Integer - the length in pixels
  Notes:
    Converts a length in design units to pixels at the current zoom.
  =========================================================================== }
function TSchematicPainter.Dist(D: Double): Integer;
begin
  Result := Round(D * FT.GetZoomFactor);
end;

{ ===========================================================================
  TSchematicPainter.Col  (function)
  Parameters:
    C: Cardinal - the object's own color (Windows 0x00BBGGRR)
  Returns:
    TColor - the canvas color
  Notes:
    The color to draw with: the given color, or the orange selection color while drawing a
    selected object.
  =========================================================================== }
function TSchematicPainter.Col(C: Cardinal): TColor;
begin
  if FAllBlack then
    Result := clBlack
  else if FSel then
    Result := FSelColor
  else
    Result := TColor(C and $FFFFFF);
end;

{ ===========================================================================
  TSchematicPainter.SetPen  (procedure)
  Parameters:
    Color: Cardinal - pen color
    Thickness: Double - thickness in design units
    PenStyle: Integer - 0 solid, 1 dash, 2 dot, 3 dash-dot, 4 dash-dot-dot
  Notes:
    Sets the canvas pen from a color, thickness in design units and Windows dash style. The pen
    is at least 1 pixel wide; dashed styles only show on 1 pixel pens, as on Windows.
  =========================================================================== }
procedure TSchematicPainter.SetPen(Color: Cardinal; Thickness: Double; PenStyle: Integer);
var
  W: Integer;
begin
  { as TinyCAD's CContext::SelectPen: a pen of width 1 is one pixel at every zoom (wires, and the lines, polygons, circles and rectangles of the usual width), only
    a wider pen grows with the zoom - and on a printout or an exported picture (FPrinting) every pen does }
  if (Thickness > 1) or FPrinting then
    W := Max(1, Round(Thickness * FT.GetZoomFactor))
  else
    W := 1;
  FCanvas.Pen.Color := Col(Color);
  FCanvas.Pen.Width := W;
  FPenW := W; FPenDash := PenStyle;
  { Windows pen styles: 0 solid, 1 dash, 2 dot, 3 dash-dot, 4 dash-dot-dot (dashes need a 1 px pen) }
  if (W > 1) or (PenStyle = 0) then
    FCanvas.Pen.Style := psSolid
  else
    case PenStyle of
      1: FCanvas.Pen.Style := psDash;
      2: FCanvas.Pen.Style := psDot;
      3: FCanvas.Pen.Style := psDashDot;
      4: FCanvas.Pen.Style := psDashDotDot;
    else
      FCanvas.Pen.Style := psSolid;
    end;
end;

{ ===========================================================================
  TSchematicPainter.DashedLn  (procedure)
  Parameters:
    const P1: TPoint
    const P2: TPoint
  Notes:
    Draws a dashed, dotted, dash-dot or dash-dot-dot line with a pen wider than one pixel, which
    the system draws solid: the dashes are laid end to end along the line with the pen's width,
    each dash or gap a multiple of that width (a dash 5 widths long, a dot 1, a gap 2).
  =========================================================================== }
procedure TSchematicPainter.DashedLn(const P1, P2: TPoint);
begin
  DashedPath([P1, P2], False);
end;

{ ===========================================================================
  TSchematicPainter.DashedPen  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    The system draws such a pen solid (this happens when the zoom makes a thin line 2 pixels or
    more wide), so the shapes that are drawn with the system's rectangle, ellipse and polygon
    calls are outlined with DashedPath instead.
  =========================================================================== }
function TSchematicPainter.DashedPen: Boolean;
begin
  Result := (FPenW > 1) and (FPenDash in [1..4]);
end;

{ ===========================================================================
  TSchematicPainter.DashedPath  (procedure)
  Parameters:
    const Pts: array of TPoint
    Closed: Boolean - flag
  Notes:
    Draws the path with the pen's dash style the way DashedLn draws a line, but the pattern runs
    on from one side to the next round the corners instead of starting again on each.
  =========================================================================== }
procedure TSchematicPainter.DashedPath(const Pts: array of TPoint; Closed: Boolean);
const
  { on, off, on, off ... in pen widths }
  PATTERN: array[1..4, 0..5] of Integer = ((5, 2, 5, 2, 5, 2), (1, 2, 1, 2, 1, 2), (5, 2, 1, 2, 5, 2), (5, 2, 1, 2, 1, 2));
  NPAT: array[1..4] of Integer = (2, 2, 4, 6);
var
  i, n, K: Integer;
  A, B: TPoint;
  Len, Pos, SegLen, Dx, Dy, Left: Double;
  Ink: Boolean;
begin
  n := Length(Pts);
  if n < 2 then
    Exit;
  FCanvas.Pen.Style := psSolid;
  K := 0; Ink := True;
  Left := PATTERN[FPenDash, 0] * FPenW;      // what is left of the dash or gap being drawn
  if Closed then
    Inc(n);
  for i := 0 to n - 2 do
  begin
    A := Pts[i];
    B := Pts[(i + 1) mod Length(Pts)];
    Dx := B.x - A.x; Dy := B.y - A.y;
    Len := Sqrt(Dx * Dx + Dy * Dy);
    if Len < 1 then
      Continue;
    Dx := Dx / Len; Dy := Dy / Len;
    Pos := 0;
    while Pos < Len do
    begin
      SegLen := Left;
      if Pos + SegLen > Len then
        SegLen := Len - Pos;
      if Ink then
      begin
        FCanvas.MoveTo(A.x + Round(Dx * Pos), A.y + Round(Dy * Pos));
        FCanvas.LineTo(A.x + Round(Dx * (Pos + SegLen)), A.y + Round(Dy * (Pos + SegLen)));
      end;
      Pos := Pos + SegLen;
      Left := Left - SegLen;
      if Left <= 0.0001 then
      begin
        K := (K + 1) mod NPAT[FPenDash];
        Ink := not Ink;
        Left := PATTERN[FPenDash, K] * FPenW;
      end;
    end;
  end;
end;

{ ===========================================================================
  TSchematicPainter.EllipsePath  (procedure)
  Parameters:
    L: Integer - whole number
    T: Integer - whole number
    R: Integer - the XML reader, positioned on this element
    B: Integer - a point, in design units
    out Pts: TPxArray - out: set by the call
  Notes:
    A closed outline of straight pieces, enough of them to look round at this size.
  =========================================================================== }
procedure TSchematicPainter.EllipsePath(L, T, R, B: Integer; out Pts: TPxArray);
var
  i, n: Integer;
  Cx, Cy, Rx, Ry: Double;
begin
  Cx := (L + R) / 2; Cy := (T + B) / 2;
  Rx := (R - L) / 2; Ry := (B - T) / 2;
  n := Max(24, Round(Pi * (Rx + Ry) / 3));
  SetLength(Pts, n);
  for i := 0 to n - 1 do
  begin
    Pts[i].x := Round(Cx + Rx * Cos(2 * Pi * i / n));
    Pts[i].y := Round(Cy + Ry * Sin(2 * Pi * i / n));
  end;
end;

{ ===========================================================================
  TSchematicPainter.RoundRectPath  (procedure)
  Parameters:
    L: Integer - whole number
    T: Integer - whole number
    R: Integer - the XML reader, positioned on this element
    B: Integer - a point, in design units
    Rad: Integer - whole number
    out Pts: TPxArray - out: set by the call
  Notes:
    A closed outline: straight sides and a quarter circle of 6 pieces on each corner. A radius
    too big for the box is made smaller.
  =========================================================================== }
procedure TSchematicPainter.RoundRectPath(L, T, R, B, Rad: Integer; out Pts: TPxArray);
var
  c, k, n: Integer;
  Cx, Cy: array[0..3] of Integer;
  Ang: Double;
begin
  Rad := Max(0, Min(Rad, Min((R - L) div 2, (B - T) div 2)));
  { centres of the corners: top left, top right, bottom right, bottom left }
  Cx[0] := L + Rad; Cy[0] := T + Rad;
  Cx[1] := R - Rad; Cy[1] := T + Rad;
  Cx[2] := R - Rad; Cy[2] := B - Rad;
  Cx[3] := L + Rad; Cy[3] := B - Rad;
  SetLength(Pts, 28);
  n := 0;
  for c := 0 to 3 do
    for k := 0 to 6 do
    begin
      Ang := Pi * (180 + 90 * c + 15 * k) / 180;
      Pts[n].x := Cx[c] + Round(Rad * Cos(Ang));
      Pts[n].y := Cy[c] + Round(Rad * Sin(Ang));
      Inc(n);
    end;
end;

{ ===========================================================================
  TSchematicPainter.Ln  (procedure)
  Parameters:
    const A: TDPoint - start
    const B: TDPoint - end
  Notes:
    Draws a line between two design points, including its last pixel (which LineTo leaves out).
  =========================================================================== }
procedure TSchematicPainter.Ln(const A, B: TDPoint);
var
  P1, P2: TPoint;
begin
  P1 := Px(A);
  P2 := Px(B);
  if (FPenW > 1) and (FPenDash in [1..4]) then
  begin
    DashedLn(P1, P2);      // (a pen wider than a pixel cannot be dashed by the system: the dashes are drawn one by one)
    Exit;
  end;
  FCanvas.MoveTo(P1.x, P1.y);
  FCanvas.LineTo(P2.x, P2.y);
  FCanvas.Pixels[P2.x, P2.y] := FCanvas.Pen.Color; // LineTo leaves out the last pixel
end;

{ ===========================================================================
  TSchematicPainter.Poly  (procedure)
  Parameters:
    const Pts: array of TPoint - the points in pixels
    Closed: Boolean - True for a closed polygon
  Notes:
    Draws a polyline, or a closed polygon with the current brush.
  =========================================================================== }
procedure TSchematicPainter.Poly(const Pts: array of TPoint; Closed: Boolean);
begin
  if Length(Pts) < 2 then
    Exit;
  if Closed then
    FCanvas.Polygon(Pts)
  else
    FCanvas.Polyline(Pts);
end;

{ ===========================================================================
  TSchematicPainter.FillBrush  (procedure)
  Parameters:
    FillNumber: Integer - whole number
  Notes:
    Fill style number -> brush. Index -1 = none, 0 = solid, 1.. = hatch patterns (Windows HS_*)
  =========================================================================== }
procedure TSchematicPainter.FillBrush(FillNumber: Integer);
var
  F: TFillStyleResource;
begin
  F := FOpts.Fills.Get(FillNumber) as TFillStyleResource;
  if F.Index < 0 then
    FCanvas.Brush.Style := bsClear
  else
  begin
    FCanvas.Brush.Color := TColor(F.Color and $FFFFFF);   // a fill keeps its own color when selected
    if FAllBlack and ((F.Color and $FFFFFF) <> $FFFFFF) then
      FCanvas.Brush.Color := clBlack;   // (CContext::SelectBrush: all but white)
    case F.Index of
      0: FCanvas.Brush.Style := bsSolid;
      1: FCanvas.Brush.Style := bsHorizontal;
      2: FCanvas.Brush.Style := bsVertical;
      3: FCanvas.Brush.Style := bsFDiagonal;
      4: FCanvas.Brush.Style := bsBDiagonal;
      5: FCanvas.Brush.Style := bsCross;
      6: FCanvas.Brush.Style := bsDiagCross;
    else
      FCanvas.Brush.Style := bsSolid;
    end;
  end;
end;

{ ===========================================================================
  TSchematicPainter.SetFont  (procedure)
  Parameters:
    FontNumber: Integer - font resource number
    Color: Cardinal - text color
    out ScreenHeight: Integer - set to the font height in pixels
  Notes:
    Selects a font resource on the canvas, scaled to the zoom (name, bold, italic, underline) in
    the given color with a transparent background.
  =========================================================================== }
procedure TSchematicPainter.SetFont(FontNumber: Integer; Color: Cardinal; out ScreenHeight: Integer);
var
  F: TFontResource;
begin
  F := FOpts.Fonts.Get(FontNumber) as TFontResource;
  ScreenHeight := Max(2, Round(Abs(F.Height) * FT.GetZoomFactor));
  FCanvas.Font.Name := F.FaceName;
  FCanvas.Font.Height := -ScreenHeight;
  FCanvas.Font.Color := Col(Color);
  FCanvas.Font.Orientation := 0;
  FCanvas.Font.Style := [];
  if F.Weight >= 700 then
    FCanvas.Font.Style := FCanvas.Font.Style + [fsBold];
  if F.Italic <> 0 then
    FCanvas.Font.Style := FCanvas.Font.Style + [fsItalic];
  if F.Underline <> 0 then
    FCanvas.Font.Style := FCanvas.Font.Style + [fsUnderline];
  FCanvas.Brush.Style := bsClear;
end;

{ ===========================================================================
  TSchematicPainter.TextBox  (procedure)
  Parameters:
    const Str: String - the text
    const A: TDPoint - a point, in design units
    const B: TDPoint - a point, in design units
    Rotated: Boolean - flag
    FontNumber: Integer - whole number
    Color: Cardinal
  Notes:
    Text inside a design-space box. Normal text sits in the box; rotated text reads upwards.
  =========================================================================== }
procedure TSchematicPainter.TextBox(const Str: String; const A, B: TDPoint; Rotated: Boolean;
  FontNumber: Integer; Color: Cardinal);
var
  P1, P2: TPoint;
  L, T, Bm, H: Integer;
  S: String;
begin
  S := StringReplace(Str, '`', '', [rfReplaceAll]);
  if S = '' then
    Exit;
  P1 := Px(A);
  P2 := Px(B);
  L := Min(P1.x, P2.x);
  T := Min(P1.y, P2.y);
  Bm := Max(P1.y, P2.y);
  SetFont(FontNumber, Color, H);
  if Rotated then
  begin
    FCanvas.Font.Orientation := 900;
    FCanvas.TextOut(L, Bm, S);
  end
  else
    FCanvas.TextOut(L, T, S);
  FCanvas.Font.Orientation := 0;
end;

{ Text anchored at a point: bottom-left for normal text; for rotated text the point is the start
  (bottom) and the right-hand edge of the line. }

{ ===========================================================================
  TSchematicPainter.TextAt  (procedure)
  Parameters:
    const Str: String - the text
    const Anchor: TDPoint - the anchor point
    Rotated: Boolean - True to read upwards
    FontNumber: Integer - font resource number
    Color: Cardinal - text color
  Notes:
    Draws text anchored at a point: normal text sits above the anchor, rotated text reads
    upwards beside it. A backquote in the text (TinyCAD's overbar mark) is dropped.
  =========================================================================== }
procedure TSchematicPainter.TextAt(const Str: String; const Anchor: TDPoint; Rotated: Boolean;
  FontNumber: Integer; Color: Cardinal);
var
  P: TPoint;
  H: Integer;
  S: String;
begin
  S := StringReplace(Str, '`', '', [rfReplaceAll]);
  if S = '' then
    Exit;
  P := Px(Anchor);
  SetFont(FontNumber, Color, H);
  H := FCanvas.TextHeight('Ag');
  if Rotated then
  begin
    FCanvas.Font.Orientation := 900;
    FCanvas.TextOut(P.x - H, P.y, S);
  end
  else
    FCanvas.TextOut(P.x, P.y - H, S);
  FCanvas.Font.Orientation := 0;
end;

{ ===========================================================================
  TSchematicPainter.ForceLineColor  (procedure)
  Parameters:
    AColor: Cardinal
  Notes:
    From now on every line this painter draws has this color, with its own thickness. Used to
    show the wire or bus being drawn (red in TinyCAD) before it is confirmed.
  =========================================================================== }
procedure TSchematicPainter.ForceLineColor(AColor: Cardinal);
begin
  FForceColor := True;
  FForcedColor := AColor;
end;

{ ===========================================================================
  TSchematicPainter.PaintLine  (procedure)
  Parameters:
    O: TDrawLine - the line object
  Notes:
    Draws a wire, bus or line. Objects using the default style take the sheet's wire or bus
    color.
  =========================================================================== }
procedure TSchematicPainter.PaintLine(O: TDrawLine);
var
  St: TLineStyleResource;
  C: Cardinal;
  T: Double;
  Ps: Integer;
begin
  St := FOpts.Styles.Get(O.Style) as TLineStyleResource;
  C := St.Color; T := St.Thickness; Ps := St.Style;
  if O.UseDefaultStyle then
    case O.Kind of
      xBus: begin
        C := FOpts.Colors.Get(UC_BUS);
        T := 3;
        Ps := 0;
      end;
      xWire: begin
        C := FOpts.Colors.Get(UC_WIRE);
        Ps := 0;
      end;
    end;
  if FForceColor then
    C := FForcedColor;
  SetPen(C, T, Ps);
  Ln(O.PointA, O.PointB);
end;

{ ===========================================================================
  TSchematicPainter.MinDotRadius  (function)
  Returns:
    Integer - the smallest radius, in pixels, a dot (junction, circle end) is drawn with
  Notes:
    2 on screen so a dot stays visible when zoomed out; 1 when printing, exporting or previewing,
    where the page is scaled down and a fixed minimum would make the dots far too big.
  =========================================================================== }
function TSchematicPainter.MinDotRadius: Integer;
begin
  if FPrinting then
    Result := 1
  else
    Result := 2;
end;

{ ===========================================================================
  TSchematicPainter.PaintJunction  (procedure)
  Parameters:
    O: TDrawJunction - the junction
  Notes:
    Draws the junction dot in the junction color.
    Notes: on screen the dot is never smaller than 2 pixels; on a printout, an export or the print
    preview (FPrinting) it is true to scale (at least 1 pixel), or it would swell on a reduced page.
  =========================================================================== }
procedure TSchematicPainter.PaintJunction(O: TDrawJunction);
var
  P: TPoint;
  R: Integer;
begin
  P := Px(O.PointA);
  R := Max(MinDotRadius, Dist(JUNCTION_R));
  FCanvas.Pen.Style := psSolid;
  FCanvas.Pen.Width := 1;
  FCanvas.Pen.Color := Col(FOpts.Colors.Get(UC_JUNCTION));
  FCanvas.Brush.Style := bsSolid;
  FCanvas.Brush.Color := Col(FOpts.Colors.Get(UC_JUNCTION));
  FCanvas.Ellipse(P.x - R, P.y - R, P.x + R + 1, P.y + R + 1);
  FCanvas.Brush.Style := bsClear;
end;

{ ===========================================================================
  TSchematicPainter.PaintNoConnect  (procedure)
  Parameters:
    O: TDrawNoConnect - the no-connect
  Notes:
    Draws the no-connect cross.
  =========================================================================== }
procedure TSchematicPainter.PaintNoConnect(O: TDrawNoConnect);
var
  P: TPoint;
  R: Integer;
begin
  P := Px(O.PointA);
  R := Max(3, Dist(CONNECT_R));
  SetPen(FOpts.Colors.Get(UC_NOCONNECT), 1, 0);
  FCanvas.MoveTo(P.x - R, P.y - R); FCanvas.LineTo(P.x + R + 1, P.y + R + 1);
  FCanvas.MoveTo(P.x - R, P.y + R); FCanvas.LineTo(P.x + R + 1, P.y - R - 1);
end;

{ ===========================================================================
  TSchematicPainter.PaintError  (procedure)
  Parameters:
    O: TDrawError - the design rules check marker
  Notes:
    Draws the marker as CDrawError::Paint does: an empty circle of radius 6 with a 5 unit pen,
    dark red (127,0,0), or in the bus color when it is the selected marker.
  =========================================================================== }
procedure TSchematicPainter.PaintError(O: TDrawError);
var
  A, B: TPoint;
begin
  if FSel then
    SetPen(FOpts.Colors.Get(UC_BUS), 5, 0)
  else
    SetPen($00007F, 5, 0);
  FCanvas.Brush.Style := bsClear;
  A := Px(DPoint(O.PointA.x - 6, O.PointA.y - 6));
  B := Px(DPoint(O.PointA.x + 6, O.PointA.y + 6));
  FCanvas.Ellipse(Min(A.x, B.x), Min(A.y, B.y), Max(A.x, B.x) + 1, Max(A.y, B.y) + 1);
end;

{ ===========================================================================
  TSchematicPainter.PaintSquare  (procedure)
  Parameters:
    O: TDrawSquare - the shape
  Notes:
    Draws a rectangle or ellipse with its line style and fill.
  =========================================================================== }
procedure TSchematicPainter.PaintSquare(O: TDrawSquare);
var
  St: TLineStyleResource;
  P1, P2: TPoint;
  L, T, R, B: Integer;
  Pts: TPxArray;
  Dashed: Boolean;
begin
  St := FOpts.Styles.Get(O.Style) as TLineStyleResource;
  SetPen(St.Color, St.Thickness, St.Style);
  FillBrush(O.Fill);
  P1 := Px(O.PointA);
  P2 := Px(O.PointB);
  Dashed := DashedPen;
  if Dashed then
    FCanvas.Pen.Style := psClear;      // the fill first, then the outline in dashes (a wide pen is solid to the system)
  if O.IsSquare then
    FCanvas.Rectangle(Min(P1.x, P2.x), Min(P1.y, P2.y), Max(P1.x, P2.x) + 1, Max(P1.y, P2.y) + 1)
  else
    FCanvas.Ellipse(Min(P1.x, P2.x), Min(P1.y, P2.y), Max(P1.x, P2.x) + 1, Max(P1.y, P2.y) + 1);
  FCanvas.Brush.Style := bsClear;
  if Dashed then
  begin
    L := Min(P1.x, P2.x); T := Min(P1.y, P2.y); R := Max(P1.x, P2.x); B := Max(P1.y, P2.y);
    if O.IsSquare then
      DashedPath([Point(L, T), Point(R, T), Point(R, B), Point(L, B)], True)
    else
    begin
      EllipsePath(L, T, R, B, Pts);
      DashedPath(Pts, True);
    end;
  end;
end;

{ ===========================================================================
  TSchematicPainter.PaintPolygon  (procedure)
  Parameters:
    O: TDrawPolygon - the polygon
  Notes:
    Draws a polygon or arc from its flattened outline, filled when it has a fill, closed when
    marked closed.
  =========================================================================== }
procedure TSchematicPainter.PaintPolygon(O: TDrawPolygon);
var
  St: TLineStyleResource;
  Pts: array of TPoint;
  i: Integer;
  Filled: Boolean;
  F: TFillStyleResource;
  Dashed: Boolean;
begin
  if Length(O.Points) < 2 then
    Exit;
  St := FOpts.Styles.Get(O.Style) as TLineStyleResource;
  SetPen(St.Color, St.Thickness, St.Style);
  SetLength(Pts, Length(O.Points));
  for i := 0 to High(O.Points) do
    Pts[i] := Px(DPoint(O.Points[i].x + O.PointA.x, O.Points[i].y + O.PointA.y));
  F := FOpts.Fills.Get(O.Fill) as TFillStyleResource;
  Filled := F.Index >= 0;
  Dashed := DashedPen;      // (a wide pen is solid to the system: the outline is drawn in dashes after the fill)
  if Filled then
  begin
    FillBrush(O.Fill);
    if Dashed then
      FCanvas.Pen.Style := psClear;
    FCanvas.Polygon(Pts);
    FCanvas.Brush.Style := bsClear;
    if Dashed then
      DashedPath(Pts, True);
  end
  else if Dashed then
    DashedPath(Pts, O.Close <> 0)
  else
  begin
    FCanvas.Polyline(Pts);
    if O.Close <> 0 then
      FCanvas.Line(Pts[High(Pts)].x, Pts[High(Pts)].y, Pts[0].x, Pts[0].y);
  end;
end;

{ ===========================================================================
  TSchematicPainter.TextDir  (procedure)
  Parameters:
    const Str: String - the text
    const Anchor: TDPoint - a point, in design units
    Dir: Integer - whole number
    FontNumber: Integer - whole number
    Color: Cardinal
  Notes:
    Draws text that starts or ends at its attachment point (the corner of its box that the
    object is placed by). Up reads upwards (rotated 90 degrees counterclockwise from the
    horizontal) and starts at the anchor; Down reads downwards (rotated 90 degrees clockwise)
    and also starts at the anchor; Right reads left to right starting at the anchor; Left also
    reads left to right but ends at the anchor. The rotated cases keep the glyph cell to the
    left of the anchor, as the box of the object is laid out. A backquote (overbar mark) is
    dropped.
  =========================================================================== }
procedure TSchematicPainter.TextDir(const Str: String; const Anchor: TDPoint; Dir: Integer;
  FontNumber: Integer; Color: Cardinal);
var
  P: TPoint;
  H, W: Integer;
  S: String;
begin
  S := StringReplace(Str, '`', '', [rfReplaceAll]);
  if S = '' then
    Exit;
  P := Px(Anchor);
  SetFont(FontNumber, Color, H);
  H := FCanvas.TextHeight('Ag');
  W := FCanvas.TextWidth(S);
  case FT.RotateDir(Dir) of
    0: begin
      FCanvas.Font.Orientation := 900;
      FCanvas.TextOut(P.x - H, P.y, S);
    end;
    1: begin
      FCanvas.Font.Orientation := 2700;
      FCanvas.TextOut(P.x, P.y, S);
    end;
    2: FCanvas.TextOut(P.x - W, P.y - H, S);
  else
    FCanvas.TextOut(P.x, P.y - H, S);
  end;
  FCanvas.Font.Orientation := 0;
end;

{ ===========================================================================
  TSchematicPainter.AttachBox  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
  Notes:
    The little red square TinyCAD draws on the point a text or label is attached to (4 design
    units across, centred on the point, not filled), always red.
  =========================================================================== }
procedure TSchematicPainter.AttachBox(const P: TDPoint);
var
  A, B: TPoint;
  WasSel: Boolean;
begin
  A := Px(DPoint(P.x - 2, P.y - 2));
  B := Px(DPoint(P.x + 2, P.y + 2));
  WasSel := FSel;
  FSel := False;                       // the box is red also on a selected object (which is otherwise drawn in the selection colour)
  SetPen(cRED, 1, 0);
  FSel := WasSel;
  FCanvas.Brush.Style := bsClear;
  FCanvas.Rectangle(Min(A.x, B.x), Min(A.y, B.y), Max(A.x, B.x) + 1, Max(A.y, B.y) + 1);
end;

{ ===========================================================================
  TSchematicPainter.PaintText  (procedure)
  Parameters:
    O: TDrawText - the text object
  Notes:
    Draws a text object in its box, upright or rotated.
  =========================================================================== }
procedure TSchematicPainter.PaintText(O: TDrawText);
begin
  TextDir(O.Str, O.PointA, O.Dir, O.FontStyle, O.FontColor);
  if FSel and (O.Kind <> xBusNameEx) then
    AttachBox(O.PointA);
end;

{ ===========================================================================
  TSchematicPainter.PaintLabel  (procedure)
  Parameters:
    O: TDrawLabel - the label
  Notes:
    Draws a wire label: its text, plus an outline for input and output labels.
  =========================================================================== }
procedure TSchematicPainter.PaintLabel(O: TDrawLabel);
var
  Sz: TDSize;
  A, B: TDPoint;
  Ad, Sp, ISp, OSp: Double;
  IsIn, IsOut: Boolean;
begin
  if O.LabelStyle = label_normal then
    TextDir(O.Str, O.PointA, O.Dir, O.FontStyle, O.FontColor)
  else
  begin
    Sz := FOpts.TextExtent(O.Str, O.FontStyle);
    A := O.PointA;
    B := O.PointB;
    Ad := Sz.cy;
    Sp := Sz.cy / 5;
    IsIn := O.LabelStyle in [label_in, label_io];
    IsOut := O.LabelStyle in [label_out, label_io];
    ISp := 0; OSp := 0;
    case O.Dir of
      0, 3: begin if IsIn then
        ISp := -Ad; if IsOut then
        OSp := -Ad; end;
    else
      begin if IsIn then
        ISp := Ad; if IsOut then
        OSp := Ad; end;
    end;
    SetPen(O.FontColor, 1, 0);
    { the two long sides }
    case O.Dir of
      0, 1: begin
              Ln(DPoint(B.x, A.y + OSp), DPoint(B.x, B.y - ISp));
              Ln(DPoint(A.x, A.y + OSp), DPoint(A.x, B.y - ISp));
            end;
      2:    begin
              Ln(DPoint(B.x - OSp, B.y), DPoint(A.x + ISp, B.y));
              Ln(DPoint(B.x - OSp, A.y), DPoint(A.x + ISp, A.y));
            end;
    else
      begin
        Ln(DPoint(A.x - OSp, B.y), DPoint(B.x + ISp, B.y));
        Ln(DPoint(A.x - OSp, A.y), DPoint(B.x + ISp, A.y));
      end;
    end;
    { the input end: an arrowhead, or a flat side }
    case O.Dir of
      0: if IsIn then begin
           Ln(DPoint(A.x, B.y + Ad), DPoint(A.x - Ad / 2, B.y));
           Ln(DPoint(A.x - Ad / 2, B.y), DPoint(B.x, B.y + Ad));
         end else
           Ln(DPoint(A.x, B.y), DPoint(B.x, B.y));
      1: if IsIn then begin
           Ln(DPoint(A.x, B.y - Ad), DPoint(A.x - Ad / 2, B.y));
           Ln(DPoint(A.x - Ad / 2, B.y), DPoint(B.x, B.y - Ad));
         end else
           Ln(DPoint(A.x, B.y), DPoint(B.x, B.y));
      2: if IsIn then begin
           Ln(DPoint(A.x + Ad, B.y), DPoint(A.x, A.y - Ad / 2));
           Ln(DPoint(A.x, A.y - Ad / 2), DPoint(A.x + Ad, A.y));
         end else
           Ln(DPoint(A.x, A.y), DPoint(A.x, B.y));
    else
      if IsIn then begin
        Ln(DPoint(B.x - Ad, A.y), DPoint(B.x, A.y - Ad / 2));
        Ln(DPoint(B.x, A.y - Ad / 2), DPoint(B.x - Ad, B.y));
      end else
        Ln(DPoint(B.x, A.y), DPoint(B.x, B.y));
    end;
    { the output end }
    case O.Dir of
      0: if IsOut then begin
           Ln(DPoint(A.x, A.y - Ad), DPoint(A.x - Ad / 2, A.y));
           Ln(DPoint(A.x - Ad / 2, A.y), DPoint(B.x, A.y - Ad));
         end else
           Ln(DPoint(A.x, A.y), DPoint(B.x, A.y));
      1: if IsOut then begin
           Ln(DPoint(A.x, A.y + Ad), DPoint(A.x - Ad / 2, A.y));
           Ln(DPoint(A.x - Ad / 2, A.y), DPoint(B.x, A.y + Ad));
         end else
           Ln(DPoint(A.x, A.y), DPoint(B.x, A.y));
      2: if IsOut then begin
           Ln(DPoint(B.x - Ad, B.y), DPoint(B.x, A.y - Ad / 2));
           Ln(DPoint(B.x, A.y - Ad / 2), DPoint(B.x - Ad, A.y));
         end else
           Ln(DPoint(B.x, A.y), DPoint(B.x, B.y));
    else
      if IsOut then begin
        Ln(DPoint(A.x + Ad, A.y), DPoint(A.x, A.y - Ad / 2));
        Ln(DPoint(A.x, A.y - Ad / 2), DPoint(A.x + Ad, B.y));
      end else
        Ln(DPoint(A.x, A.y), DPoint(A.x, B.y));
    end;
    { the text, inset from the output end (or by the spacing at a flat end) }
    if OSp = 0 then
    begin
      if O.Dir in [0, 3] then
        OSp := -Sp
      else
        OSp := Sp;
    end;
    case O.Dir of
      0, 1: TextDir(O.Str, DPoint(A.x, A.y + OSp), O.Dir, O.FontStyle, O.FontColor);
      2:    TextDir(O.Str, DPoint(B.x - OSp, A.y), O.Dir, O.FontStyle, O.FontColor);
    else
      TextDir(O.Str, DPoint(A.x - OSp, A.y), O.Dir, O.FontStyle, O.FontColor);
    end;
  end;
  if DPointHasValue(O.ActivePoint) then
    AttachBox(O.ActivePoint);
end;

{ ===========================================================================
  TSchematicPainter.PaintPower  (procedure)
  Parameters:
    O: TDrawPower - the power symbol
  Notes:
    Draws a power symbol: the stem, the symbol (bar, circle, wave, arrow or earth) and its text.
  =========================================================================== }
procedure TSchematicPainter.PaintPower(O: TDrawPower);
var
  A, E, D: TDPoint;
  Pa, Pe: TPoint;
  R, k: Integer;
  Perp: TDPoint;
begin
  A := O.PointA;
  case O.Dir of
    0: E := DPoint(A.x, A.y - POWER_SIZE);
    1: E := DPoint(A.x, A.y + POWER_SIZE);
    2: E := DPoint(A.x - POWER_SIZE, A.y);
  else
    E := DPoint(A.x + POWER_SIZE, A.y);
  end;
  SetPen(FOpts.Colors.Get(UC_POWER), 1, 0);
  Ln(A, E);
  Pa := Px(A); Pe := Px(E);
  { direction of the stem, as a unit vector, and the one across it }
  D := DPoint(Sign(E.x - A.x), Sign(E.y - A.y));
  Perp := DPoint(D.y, D.x);
  FCanvas.Brush.Style := bsClear;
  case O.Which of
    0: Ln(DPoint(E.x - Perp.x * 5, E.y - Perp.y * 5), DPoint(E.x + Perp.x * 5, E.y + Perp.y * 5)); // bar
    1: begin                                                                                         // circle
         R := Max(MinDotRadius, Dist(4));
         FCanvas.Ellipse(Pe.x - R, Pe.y - R, Pe.x + R + 1, Pe.y + R + 1);
       end;
    2: begin                                                                                         // wave
         Ln(DPoint(E.x - Perp.x * 5, E.y - Perp.y * 5), DPoint(E.x - Perp.x * 2.5 + D.x * 3, E.y - Perp.y * 2.5 + D.y * 3));
         Ln(DPoint(E.x - Perp.x * 2.5 + D.x * 3, E.y - Perp.y * 2.5 + D.y * 3), DPoint(E.x, E.y));
         Ln(DPoint(E.x, E.y), DPoint(E.x + Perp.x * 2.5 - D.x * 3, E.y + Perp.y * 2.5 - D.y * 3));
         Ln(DPoint(E.x + Perp.x * 2.5 - D.x * 3, E.y + Perp.y * 2.5 - D.y * 3), DPoint(E.x + Perp.x * 5, E.y + Perp.y * 5));
       end;
    3: begin                                                                                         // arrow
         Ln(DPoint(E.x - Perp.x * 4, E.y - Perp.y * 4), DPoint(E.x + D.x * 5, E.y + D.y * 5));
         Ln(DPoint(E.x + Perp.x * 4, E.y + Perp.y * 4), DPoint(E.x + D.x * 5, E.y + D.y * 5));
         Ln(DPoint(E.x - Perp.x * 4, E.y - Perp.y * 4), DPoint(E.x + Perp.x * 4, E.y + Perp.y * 4));
       end;
    4: for k := 0 to 2 do                                                                            // earth
         Ln(DPoint(E.x + D.x * k * 2.5 - Perp.x * (6 - 2 * k), E.y + D.y * k * 2.5 - Perp.y * (6 - 2 * k)),
            DPoint(E.x + D.x * k * 2.5 + Perp.x * (6 - 2 * k), E.y + D.y * k * 2.5 + Perp.y * (6 - 2 * k)));
  end;
  { the label }
  if O.Str <> '' then
    TextBox(O.Str, DPoint(O.TextPos.x, O.TextEnd.y), DPoint(O.TextEnd.x, O.TextPos.y), False, fPIN, FOpts.Colors.Get(UC_POWER));
end;

{ ===========================================================================
  TSchematicPainter.PaintPin  (procedure)
  Parameters:
    O: TDrawPin - the pin
  Notes:
    Draws a pin of a symbol: the line (with a dot or a clock triangle when set), a cross for a
    not-connected pin, and the pin name and number according to what is shown. Hidden pins are
    not drawn.
  =========================================================================== }
procedure TSchematicPainter.PaintPin(O: TDrawPin);
var
  L: TPinLayout;
  Mid: TDPoint;
  Pm, P1, P2, P3: TPoint;
  R, Rot: Integer;
  Rotated, WasSel: Boolean;
  Color: Cardinal;
begin
  if O.IsInvisible then
    Exit;
  if (O.Which = 5) then
    Exit; // hidden pins are not drawn on a design
  Rot := FT.GetRotMir;
  L := O.DetermineLayout(Rot);
  if O.IsPower then
    Color := FOpts.Colors.Get(UC_HIDDEN_PIN)
  else
    Color := FOpts.Colors.Get(UC_PIN);
  SetPen(Color, 1, 0);
  FCanvas.Brush.Style := bsClear;
  if O.Which = 6 then
  begin
    { a cross at the connection point }
    P1 := Px(O.PointA);
    R := Max(3, Dist(4));
    FCanvas.MoveTo(P1.x - R, P1.y - R); FCanvas.LineTo(P1.x + R + 1, P1.y + R + 1);
    FCanvas.MoveTo(P1.x - R, P1.y + R); FCanvas.LineTo(P1.x + R + 1, P1.y - R - 1);
  end
  else
  begin
    Ln(O.PointA, L.Pa);
    Mid := DPoint((L.Pa.x + L.Pd.x) / 2, (L.Pa.y + L.Pd.y) / 2);
    if (O.Which and 1) <> 0 then   // dot
    begin
      Pm := Px(Mid);
      R := Max(2, Dist(Hypot(L.Pd.x - L.Pa.x, L.Pd.y - L.Pa.y) / 2));
      FCanvas.Ellipse(Pm.x - R, Pm.y - R, Pm.x + R + 1, Pm.y + R + 1);
    end
    else
      Ln(L.Pa, L.Pd);
    if (O.Which and 2) <> 0 then   // clock triangle
    begin
      P1 := Px(L.Pb); P2 := Px(L.Pc); P3 := Px(L.Pa);
      FCanvas.Polyline([P1, P3, P2]);
    end;
  end;
  { the name and the number (the layout says where; dir 0/1 pins read upwards) }
  Rotated := L.Dr < 2;
  if (O.Show and 1) <> 0 then
    TextAt(O.Str, L.Pta, Rotated, fPIN, Color);
  if (O.Show and 2) <> 0 then
    TextAt(O.Number, L.Ptb, Rotated, fPIN, Color);
  { the "hot spot": a very light gray square (2 design units across) on the connection end of the pin, on the screen but not on a printout or an
    exported picture (CDrawPin::Paint; it helps to see where a wire will join and which way a pin points) }
  if not FPrinting then
  begin
    WasSel := FSel;
    FSel := False;                       // light gray also on a chosen symbol, as AttachBox is red
    SetPen(TColor($D0D0D0), 1, 0);
    FSel := WasSel;
    FCanvas.Brush.Style := bsClear;
    P1 := Px(DPoint(O.PointA.x - 1, O.PointA.y - 1));
    P2 := Px(DPoint(O.PointA.x + 1, O.PointA.y + 1));
    FCanvas.Rectangle(Min(P1.x, P2.x), Min(P1.y, P2.y), Max(P1.x, P2.x) + 1, Max(P1.y, P2.y) + 1);
  end;
end;

{ ===========================================================================
  TSchematicPainter.WrapText  (function)
  Parameters:
    const S: String - text
    Width: Integer - whole number
  Returns:
    TStringList
  Notes:
    Breaks the text at the line breaks and then at the spaces so that no line is wider than
    Width, as DrawTextEx with DT_WORDBREAK does for a note; a word wider than the width is
    broken between letters. A line that is empty stays as an empty line.
  =========================================================================== }
function TSchematicPainter.WrapText(const S: String; Width: Integer): TStringList;
var
  Paras: TStringList;
  p, k: Integer;
  Cur, Word, Test: String;
begin
  Result := TStringList.Create;
  Paras := TStringList.Create;
  try
    Paras.Text := S;
    for p := 0 to Paras.Count - 1 do
    begin
      Cur := '';
      Test := Paras[p];
      while Test <> '' do
      begin
        k := Pos(' ', Test);
        if k = 0 then
        begin
          Word := Test; Test := '';
        end
        else
        begin
          Word := Copy(Test, 1, k - 1); Test := Copy(Test, k + 1, MaxInt);
        end;
        if (Cur <> '') and (FCanvas.TextWidth(Cur + ' ' + Word) > Width) then
        begin
          Result.Add(Cur);
          Cur := '';
        end;
        if Cur <> '' then
          Cur := Cur + ' ' + Word
        else
          Cur := Word;
        while (Length(Cur) > 1) and (FCanvas.TextWidth(Cur) > Width) do
        begin
          { a single word that is too wide: as many letters as fit, the rest goes on }
          k := Length(Cur) - 1;
          while (k > 1) and (FCanvas.TextWidth(Copy(Cur, 1, k)) > Width) do
            Dec(k);
          Result.Add(Copy(Cur, 1, k));
          Cur := Copy(Cur, k + 1, MaxInt);
        end;
      end;
      Result.Add(Cur);
    end;
  finally
    Paras.Free;
  end;
end;

{ ===========================================================================
  TSchematicPainter.PaintNote  (procedure)
  Parameters:
    O: TDrawNoteText - the note
  Notes:
    Draws a note: its rectangle (square, rounded or none), fill and text one line per line
    break. Word wrapping is not done yet.
  =========================================================================== }
procedure TSchematicPainter.PaintNote(O: TDrawNoteText);
var
  St: TLineStyleResource;
  P1, P2: TPoint;
  L, T, R, B, H, Inset: Integer;
  NoteBox: TRect;
  Pts: TPxArray;
  Dashed: Boolean;
  Lines: TStringList;
  LineH, Y, i: Integer;
begin
  St := FOpts.Styles.Get(O.Style) as TLineStyleResource;
  SetPen(St.Color, St.Thickness, St.Style);
  FillBrush(O.Fill);
  P1 := Px(O.PointA);
  P2 := Px(O.PointB);
  L := Min(P1.x, P2.x); R := Max(P1.x, P2.x); T := Min(P1.y, P2.y); B := Max(P1.y, P2.y);
  Dashed := DashedPen and (O.BorderStyle <> BS_NoBorder);
  if (O.BorderStyle = BS_NoBorder) or Dashed then
    FCanvas.Pen.Style := psClear;      // (dashed: the fill first, then the outline in dashes, a wide pen being solid to the system)
  if O.BorderStyle = BS_RoundedRectangle then
    FCanvas.RoundRect(L, T, R + 1, B + 1, 8, 8)
  else
    FCanvas.Rectangle(L, T, R + 1, B + 1);
  if Dashed then
  begin
    if O.BorderStyle = BS_RoundedRectangle then
    begin
      RoundRectPath(L, T, R, B, 4, Pts);
      DashedPath(Pts, True);
    end
    else
      DashedPath([Point(L, T), Point(R, T), Point(R, B), Point(L, B)], True);
  end;
  FCanvas.Brush.Style := bsClear;
  { the text is wrapped at the words to the width of the box, inside a margin of 3 units, as CDrawNoteText::Paint does
    (DrawTextEx with DT_WORDBREAK); the margin is not used if the box is too small for it }
  Inset := Abs(Px(DPoint(3, 3)).x - Px(DPoint(0, 0)).x);
  NoteBox := Rect(L + Inset, T + Inset, R - Inset, B - Inset);
  if (NoteBox.Right <= NoteBox.Left) or (NoteBox.Bottom <= NoteBox.Top) then
    NoteBox := Rect(L, T, R, B);
  SetFont(O.FontStyle, O.FontColor, H);
  Lines := WrapText(StringReplace(O.Str, '`', '', [rfReplaceAll]), NoteBox.Right - NoteBox.Left);
  try
    LineH := FCanvas.TextHeight('Ag');
    Y := NoteBox.Top;
    for i := 0 to Lines.Count - 1 do
    begin
      FCanvas.TextRect(NoteBox, NoteBox.Left, Y, Lines[i]);      // (clipped to the box)
      Inc(Y, LineH);
    end;
  finally
    Lines.Free;
  end;
end;

{ ===========================================================================
  TSchematicPainter.PaintBusSlash  (procedure)
  Parameters:
    O: TDrawBusSlash - the bus slash
  Notes:
    Draws a bus slash as a thick bus-colored line.
  =========================================================================== }
procedure TSchematicPainter.PaintBusSlash(O: TDrawBusSlash);
begin
  SetPen(FOpts.Colors.Get(UC_BUS), 2, 0);
  Ln(O.PointA, O.PointB);
end;

{ ===========================================================================
  TSchematicPainter.PaintMethod  (procedure)
  Parameters:
    O: TDrawMethod - the placed symbol
  Notes:
    Draws a placed symbol: its drawing through a transform that applies its position, rotation,
    mirror and scale, then its reference, name and other field texts.
  =========================================================================== }
procedure TSchematicPainter.PaintMethod(O: TDrawMethod);
var
  Tr, OldOrigin: TDPoint;
  Objs: TDrawingList;
  i, fi: Integer;
  OldSx, OldSy: Double;
  Sx, Sy: Double;
  Txt: String;
begin
  O.ExtractSymbol(Tr, Objs);
  { like CDrawMethod::Paint: scale for this placement, then draw the symbol's own objects through a
    transform that applies the symbol's position, rotation and mirror }
  FT.GetScaling(O.Rotate, OldSx, OldSy);
  FT.SetScaling(O.Rotate, O.ScalingX, O.ScalingY);
  OldOrigin := FT.SetTRM(O.PointA, Tr, O.Rotate);
  for i := 0 to Objs.Count - 1 do
    PaintObject(Objs[i], FSel);
  FT.SetScaling(O.Rotate, OldSx, OldSy);
  FT.EndTRM(OldOrigin);
  { the field texts (reference, name, values) }
  for fi := 0 to High(O.Fields) do
    if (O.Fields[fi].Show <> 0) and (not FHideSymbolFields) then
    begin
      Txt := O.GetDecoratedField(fi);
      TextAt(Txt, DPoint(O.Fields[fi].Position.x + O.PointA.x, O.Fields[fi].Position.y + O.PointA.y + 0),
             False, fPIN, FOpts.Colors.Get(UC_PIN));
    end;
end;

{ ===========================================================================
  TSchematicPainter.PaintHierarchicalSymbol  (procedure)
  Parameters:
    O: TDrawHierarchicalSymbol
  Notes:
    CDrawHierarchicalSymbol::Paint: the design's drawing and the fields, then, when the design
    gave no drawing, a black box from the placement point to the far corner.
  =========================================================================== }
procedure TSchematicPainter.PaintHierarchicalSymbol(O: TDrawHierarchicalSymbol);
var
  P1, P2: TPoint;
begin
  PaintMethod(O);
  if not O.IsNoSymbol then
    Exit;
  SetPen(0, 0, PS_SOLID);
  FCanvas.Brush.Style := bsClear;
  P1 := Px(O.PointA);
  P2 := Px(O.PointB);
  FCanvas.Rectangle(Min(P1.x, P2.x), Min(P1.y, P2.y), Max(P1.x, P2.x) + 1, Max(P1.y, P2.y) + 1);
end;

{ ===========================================================================
  TSchematicPainter.PaintLadder  (procedure)
  Parameters:
    O: TDrawLadder - the ladder
  Notes:
    Draws ladder rails: the two rails, the bus labels above them and the line numbers beside
    them (thinned out when the lines are closer than the text height). When selected, outlines
    the rails' rectangle.
  =========================================================================== }
procedure TSchematicPainter.PaintLadder(O: TDrawLadder);
var
  R: TDRect;
  P1, P2: TPoint;
begin
  { the two rails }
  SetPen(O.LineColor, O.LineWidth, 0);
  Ln(DPoint(O.RailLeft, O.RailTop), DPoint(O.RailLeft, O.RailBottom));
  Ln(DPoint(O.RailRight, O.RailTop), DPoint(O.RailRight, O.RailBottom));
  { bus labels above the rails }
  R := O.LeftLabelBox;
  TextBox(O.LeftWire, DPoint(R.Left, R.Top), DPoint(R.Right, R.Bottom), False, O.FontStyle, O.FontColor);
  R := O.RightLabelBox;
  TextBox(O.RightWire, DPoint(R.Left, R.Top), DPoint(R.Right, R.Bottom), False, O.FontStyle, O.FontColor);
  { when selected, outline the rails' rectangle so the object is visible as one thing }
  if FSel then
  begin
    P1 := Px(DPoint(O.RailLeft, O.RailTop));
    P2 := Px(DPoint(O.RailRight, O.RailBottom));
    FCanvas.Pen.Style := psDot;
    FCanvas.Pen.Width := 1;
    FCanvas.Pen.Color := FSelColor;
    FCanvas.Brush.Style := bsClear;
    FCanvas.Rectangle(P1.x, P1.y, P2.x + 1, P2.y + 1);
    FCanvas.Pen.Style := psSolid;
  end;
end;

{ ===========================================================================
  TSchematicPainter.PaintRungGrid  (procedure)
  Parameters:
    O: TDrawRungGrid
  Notes:
    Draws the rung numbers, each centred in its cell of the number column, and the row height in
    mm above the column (when that is on). The rest of the spreadsheet is invisible; when the
    grid is selected its columns are outlined with dots and the row boundaries marked so it can
    be seen.
  =========================================================================== }
procedure TSchematicPainter.PaintRungGrid(O: TDrawRungGrid);
var
  Pg, Row, N: Integer;
  C: TDRect;
  Sz: TDSize;
  S: String;
  P1, P2: TPoint;
  H: TDRect;
begin
  for Pg := 0 to O.Pages - 1 do
  begin
    for Row := 0 to O.Rows - 1 do
    begin
      C := O.CellRect(Pg, Row);
      S := IntToStr(O.NumberAt(Pg, Row));
      Sz := FOpts.TextExtent(S, O.FontStyle);
      { centred in the cell }
      TextBox(S, DPoint((C.Left + C.Right - Sz.cx) / 2, (C.Top + C.Bottom - Sz.cy) / 2),
        DPoint((C.Left + C.Right + Sz.cx) / 2, (C.Top + C.Bottom + Sz.cy) / 2), False, O.FontStyle, O.FontColor);
    end;
    if O.ShowRowHeight then
    begin
      H := O.HeightTextBox(Pg);
      TextBox(O.HeightText, DPoint(H.Left, H.Top), DPoint(H.Right, H.Bottom), False, O.FontStyle, O.FontColor);
    end;
  end;
  if FSel then
  begin
    FCanvas.Pen.Style := psDot;
    FCanvas.Pen.Width := 1;
    FCanvas.Pen.Color := FSelColor;
    FCanvas.Brush.Style := bsClear;
    for Pg := 0 to O.Pages - 1 do
      for N := 0 to 1 do
      begin
        C := O.ColumnRect(Pg, N);
        P1 := Px(DPoint(C.Left, C.Top));
        P2 := Px(DPoint(C.Right, C.Bottom));
        FCanvas.Rectangle(P1.x, P1.y, P2.x + 1, P2.y + 1);
      end;
    for Pg := 0 to O.Pages - 1 do
      for Row := 1 to O.Rows - 1 do
      begin
        C := O.CellRect(Pg, Row);
        P1 := Px(DPoint(C.Left, C.Top));
        P2 := Px(DPoint(C.Right, C.Top));
        FCanvas.MoveTo(P1.x, P1.y);
        FCanvas.LineTo(P2.x, P2.y);
      end;
    FCanvas.Pen.Style := psSolid;
  end;
end;

{ ===========================================================================
  TSchematicPainter.PaintRuler  (procedure)
  Parameters:
    O: TDrawRuler - the ruler
  Notes:
    Draws a guide ruler as a dotted line across the sheet with its position in millimetres.
  =========================================================================== }
procedure TSchematicPainter.PaintRuler(O: TDrawRuler);
var
  P1, P2: TDPoint;
  Pos: Double;
  Txt: String;
  Fs: TFormatSettings;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  if FSel then
    SetPen(cRULER_CLK, 1, 0)
  else
    SetPen(cRULER_GUIDE, 1, 2);
  if O.Horizontal <> 0 then
  begin
    P1 := DPoint(-200, O.PointA.y);
    P2 := DPoint(FPageW + 200, O.PointA.y);
    Pos := O.PointA.y;
  end
  else
  begin
    P1 := DPoint(O.PointA.x, -200);
    P2 := DPoint(O.PointA.x, FPageH + 200);
    Pos := O.PointA.x;
  end;
  { dotted needs a 1 pixel pen }
  FCanvas.Pen.Width := 1;
  FCanvas.Pen.Style := psDot;
  Ln(P1, P2);
  Txt := FormatFloat('0.0', Pos / 5.0, Fs) + ' mm';
  if O.Horizontal <> 0 then
    TextAt(Txt, DPoint(0, O.PointA.y - 1), False, fPIN, cRULER_GUIDE)
  else
    TextAt(Txt, DPoint(O.PointA.x + 11, 0), True, fPIN, cRULER_GUIDE);
end;

{ ===========================================================================
  TSchematicPainter.PaintMeasure  (procedure)
  Parameters:
    O: TDrawMeasure - the measure
  Notes:
    Draws a measuring ruler: the line, end stops, graduations at a spacing that suits the zoom,
    and the distance beside the middle.
  =========================================================================== }
procedure TSchematicPainter.PaintMeasure(O: TDrawMeasure);
var
  Len, Ux, Uy, Nx, Ny, Step, T, Tk: Double;
  Zm: Double;
  P: TDPoint;
  Mid: TPoint;
  Txt: String;
  H, Cnt, i: Integer;
  Ang: Integer;
begin
  SetPen(O.LineColor, O.LineWidth, 0);
  Ln(O.PointA, O.PointB);
  Len := Hypot(O.PointB.x - O.PointA.x, O.PointB.y - O.PointA.y);
  if Len < 0.001 then
    Exit;
  Ux := (O.PointB.x - O.PointA.x) / Len; Uy := (O.PointB.y - O.PointA.y) / Len;
  Nx := -Uy; Ny := Ux;
  { end stops }
  Ln(DPoint(O.PointA.x - Nx * 6, O.PointA.y - Ny * 6), DPoint(O.PointA.x + Nx * 6, O.PointA.y + Ny * 6));
  Ln(DPoint(O.PointB.x - Nx * 6, O.PointB.y - Ny * 6), DPoint(O.PointB.x + Nx * 6, O.PointB.y + Ny * 6));
  { graduations: a nice step (1, 2, 5, 10 ... of the chosen unit) that is at least ~6 pixels apart }
  if O.Ticks <> 0 then
  begin
    Zm := FT.GetZoomFactor;
    if O.UnitMode = 1 then
      Step := 25.4 * 5 / 16
    else
      Step := 5.0;   // 1/16 inch or 1 mm, in internal units
    while Step * Zm < 6 do
      if O.UnitMode = 1 then
        Step := Step * 2
      else
        Step := Step * 2;
    T := Step; Cnt := 0;
    while (T < Len) and (Cnt < 2000) do
    begin
      Inc(Cnt);
      if Cnt mod 5 = 0 then
        Tk := 4
      else
        Tk := 2.5;
      P := DPoint(O.PointA.x + Ux * T, O.PointA.y + Uy * T);
      Ln(DPoint(P.x - Nx * Tk, P.y - Ny * Tk), DPoint(P.x + Nx * Tk, P.y + Ny * Tk));
      T := T + Step;
    end;
  end;
  { the distance, beside the middle of the line }
  Txt := O.DisplayText;
  SetFont(O.FontStyle, O.FontColor, H);
  Mid := Px(DPoint((O.PointA.x + O.PointB.x) / 2 + Nx * 9, (O.PointA.y + O.PointB.y) / 2 + Ny * 9));
  Ang := Round(ArcTan2(-(O.PointB.y - O.PointA.y), O.PointB.x - O.PointA.x) * 1800 / Pi);
  if (Ang > 900) then
    Ang := Ang - 1800;
  if (Ang < -900) then
    Ang := Ang + 1800;
  FCanvas.Font.Orientation := Ang;
  FCanvas.TextOut(Mid.x, Mid.y, Txt);
  FCanvas.Font.Orientation := 0;
  i := 0; if i = 1 then
    ;
end;

{ ===========================================================================
  TSchematicPainter.PaintCloud  (procedure)
  Parameters:
    O: TDrawCloud - the cloud
  Notes:
    Draws a revision cloud: each edge of the rectangle as a row of outward semicircular
    scallops.
  =========================================================================== }
procedure TSchematicPainter.PaintCloud(O: TDrawCloud);
var
  St: TLineStyleResource;
  L, T, R, B: Double;
  Pts: array of TPoint;
  Edges: array[0..3] of record A, Bp, Nrm: TDPoint end;
  e, n, k, j, Total: Integer;
  Len, Seg, Rad, Phi: Double;
  Ux, Uy: Double;
  C: TDPoint;
begin
  St := FOpts.Styles.Get(O.Style) as TLineStyleResource;
  SetPen(St.Color, St.Thickness, St.Style);
  L := Min(O.PointA.x, O.PointB.x); R := Max(O.PointA.x, O.PointB.x);
  T := Min(O.PointA.y, O.PointB.y); B := Max(O.PointA.y, O.PointB.y);
  { four edges, clockwise from the top left, each with its outward normal }
  Edges[0].A := DPoint(L, T); Edges[0].Bp := DPoint(R, T); Edges[0].Nrm := DPoint(0, -1);
  Edges[1].A := DPoint(R, T); Edges[1].Bp := DPoint(R, B); Edges[1].Nrm := DPoint(1, 0);
  Edges[2].A := DPoint(R, B); Edges[2].Bp := DPoint(L, B); Edges[2].Nrm := DPoint(0, 1);
  Edges[3].A := DPoint(L, B); Edges[3].Bp := DPoint(L, T); Edges[3].Nrm := DPoint(-1, 0);
  Total := 0;
  SetLength(Pts, 0);
  for e := 0 to 3 do
  begin
    Len := Hypot(Edges[e].Bp.x - Edges[e].A.x, Edges[e].Bp.y - Edges[e].A.y);
    if Len < 1 then
      Continue;
    n := Max(1, Round(Len / Max(2, O.Bump)));
    Seg := Len / n;
    Rad := Seg / 2;
    Ux := (Edges[e].Bp.x - Edges[e].A.x) / Len;
    Uy := (Edges[e].Bp.y - Edges[e].A.y) / Len;
    for k := 0 to n - 1 do
    begin
      C := DPoint(Edges[e].A.x + Ux * (k + 0.5) * Seg, Edges[e].A.y + Uy * (k + 0.5) * Seg);
      for j := 0 to 12 do
      begin
        Phi := Pi * j / 12;
        { a semicircle from one end of the scallop to the other, bulging outwards }
        SetLength(Pts, Total + 1);
        Pts[Total] := Px(DPoint(C.x + Rad * (-Cos(Phi) * Ux + Sin(Phi) * Edges[e].Nrm.x),
                                C.y + Rad * (-Cos(Phi) * Uy + Sin(Phi) * Edges[e].Nrm.y)));
        Inc(Total);
      end;
    end;
  end;
  FCanvas.Brush.Style := bsClear;
  if (Total > 1) and DashedPen then
    DashedPath(Pts, False)
  else if Total > 1 then
    FCanvas.Polyline(Pts);
end;

{ ===========================================================================
  TSchematicPainter.PaintRefText  (procedure)
  Parameters:
    O: TDrawRefText - the linked text
  Notes:
    Draws linked text (prefix, resolved value, suffix), with a frame when selected.
  =========================================================================== }
procedure TSchematicPainter.PaintRefText(O: TDrawRefText);
begin
  TextBox(O.DisplayText, O.PointA, O.PointB, False, O.FontStyle, O.FontColor);
  if FSel then
  begin
    SetPen(0, 1, 0);
    FCanvas.Pen.Color := FSelColor;
    FCanvas.Frame(Px(O.PointA).x - 1, Px(O.PointB).y - 1, Px(O.PointB).x + 2, Px(O.PointA).y + 2);
  end;
end;

{ ===========================================================================
  TSchematicPainter.PaintObject  (procedure)
  Parameters:
    Obj: TDrawingObject - the object
    Selected: Boolean - True to draw it highlighted
  Notes:
    Draws any drawing object by finding its class, in the selection color when selected. Used
    for sheets, the placement ghost and previews.
  =========================================================================== }
procedure TSchematicPainter.PaintObject(Obj: TDrawingObject; Selected: Boolean);
var
  WasSel: Boolean;
begin
  WasSel := FSel;
  FSel := Selected;
  FOpts := Obj.Options;
  FCanvas.Brush.Style := bsClear;
  try
    if Obj is TDrawLine then
      PaintLine(Obj as TDrawLine)
    else if Obj is TDrawJunction then
      PaintJunction(Obj as TDrawJunction)
    else if Obj is TDrawNoConnect then
      PaintNoConnect(Obj as TDrawNoConnect)
    else if Obj is TDrawError then
      PaintError(Obj as TDrawError)
    else if Obj is TDrawSquare then
      PaintSquare(Obj as TDrawSquare)
    else if Obj is TDrawPolygon then
      PaintPolygon(Obj as TDrawPolygon)
    else if Obj is TDrawMetaFile then
      PaintMetaFile(Obj as TDrawMetaFile)
    else if Obj is TDrawText then
      PaintText(Obj as TDrawText)
    else if Obj is TDrawLabel then
      PaintLabel(Obj as TDrawLabel)
    else if Obj is TDrawPower then
      PaintPower(Obj as TDrawPower)
    else if Obj is TDrawPin then
      PaintPin(Obj as TDrawPin)
    else if Obj is TDrawNoteText then
      PaintNote(Obj as TDrawNoteText)
    else if Obj is TDrawHierarchicalSymbol then
      PaintHierarchicalSymbol(Obj as TDrawHierarchicalSymbol)
    else if Obj is TDrawMethod then
      PaintMethod(Obj as TDrawMethod)
    else if Obj is TDrawLadder then
      PaintLadder(Obj as TDrawLadder)
    else if Obj is TDrawRungGrid then
      PaintRungGrid(Obj as TDrawRungGrid)
    else if Obj is TDrawBusSlash then
      PaintBusSlash(Obj as TDrawBusSlash)
    else if Obj is TDrawRuler then
      PaintRuler(Obj as TDrawRuler)
    else if Obj is TDrawMeasure then
      PaintMeasure(Obj as TDrawMeasure)
    else if Obj is TDrawCloud then
      PaintCloud(Obj as TDrawCloud)
    else if Obj is TDrawRefText then
      PaintRefText(Obj as TDrawRefText);
  finally
    FSel := WasSel;
  end;
end;

{ ===========================================================================
  TSchematicPainter.PaintSheet  (procedure)
  Parameters:
    Sheet: TDesignSheet - the sheet
    Selected: TList - the selected objects (may be nil)
  Notes:
    Draws every object of a sheet in order, highlighting those in the selection.
  =========================================================================== }
procedure TSchematicPainter.PaintSheet(Sheet: TDesignSheet; Selected: TList);
var
  i: Integer;
begin
  FOpts := Sheet.Options;
  FPageW := Sheet.Details.PageWidth;
  FPageH := Sheet.Details.PageHeight;
  for i := 0 to Sheet.Drawing.Count - 1 do
    if not ((FPrinting and Sheet.Drawing[i].IsConstruction) or (FHideSymbolText and (Sheet.Drawing[i] is TDrawSymbolText))) then
      PaintObject(Sheet.Drawing[i], (Selected <> nil) and (Selected.IndexOf(Sheet.Drawing[i]) >= 0));
end;

{ ===========================================================================
  TSchematicPainter.PaintObjects  (procedure)
  Parameters:
    Sheet: TDesignSheet - the sheet the objects are on
    Objects: TList - the objects to draw (TDrawingObject), in order
  Notes:
    Draws only these objects of a sheet, none of them highlighted and nothing else (no page,
    border or title block): what Export Image draws of a selection.
  =========================================================================== }
procedure TSchematicPainter.PaintObjects(Sheet: TDesignSheet; Objects: TList);
var
  i: Integer;
begin
  FOpts := Sheet.Options;
  FPageW := Sheet.Details.PageWidth;
  FPageH := Sheet.Details.PageHeight;
  for i := 0 to Objects.Count - 1 do
    if not ((FPrinting and TDrawingObject(Objects[i]).IsConstruction) or (FHideSymbolText and (TObject(Objects[i]) is TDrawSymbolText))) then
      PaintObject(TDrawingObject(Objects[i]), False);
end;

{ ===========================================================================
  TSchematicPainter.PaintPage  (procedure)
  Parameters:
    Sheet: TDesignSheet - the sheet
    ShowGrid: Boolean - True to draw grid dots
    const Viewport: TRect - the visible pixel area, to skip dots outside it
    const AFileName: String - path of the file
    const ASheetsText: String - text
    const ADocNoText: String - text
  Notes:
    Draws the paper with its shadow, the grid dots (only when they are at least 6 pixels apart),
    and the border rectangle if the sheet has one.
  =========================================================================== }
procedure TSchematicPainter.PaintPage(Sheet: TDesignSheet; ShowGrid: Boolean; const Viewport: TRect;
  const AFileName: String; const ASheetsText: String; const ADocNoText: String);
var
  D: TDetails;
  P1, P2: TPoint;
  R: TDRect;
  Grid, X, Y: Double;
  DotSize: Integer;
  Gx, Gy: Integer;
begin
  FOpts := Sheet.Options;     // (the fonts of the title block and rulers come from the sheet)
  D := Sheet.Details;
  P1 := Px(DPoint(0, 0));
  P2 := Px(DPoint(D.PageWidth, D.PageHeight));
  if not FPrinting then   // (on a printer there is the page itself, and nothing behind it)
  begin
    { shadow, then the paper }
    FCanvas.Brush.Style := bsSolid;
    FCanvas.Pen.Style := psClear;
    FCanvas.Brush.Color := TColor($808080);
    FCanvas.Rectangle(P1.x + 4, P1.y + 4, P2.x + 5, P2.y + 5);
    FCanvas.Pen.Style := psSolid;
    FCanvas.Pen.Width := 1;
    FCanvas.Pen.Color := clBlack;
    FCanvas.Brush.Color := TColor(FOpts.Colors.Get(UC_BACKGROUND) and $FFFFFF);       // the paper: the background color of the sheet
    FCanvas.Rectangle(P1.x, P1.y, P2.x + 1, P2.y + 1);
    { the grid, as dots, only when it is not too dense }
    Grid := Sheet.Snap.Grid;
    if ShowGrid and (Grid > 0) and (Grid * FT.GetZoomFactor >= 6) then
    begin
      DotSize := GridDotSize(FT.GetZoomFactor, FOnePxDots);
      X := 0;
      while X <= D.PageWidth do
      begin
        Y := 0;
        while Y <= D.PageHeight do
        begin
          Gx := Px(DPoint(X, Y)).x; Gy := Px(DPoint(X, Y)).y;
          if (Gx >= Viewport.Left) and (Gx <= Viewport.Right) and (Gy >= Viewport.Top) and (Gy <= Viewport.Bottom) then
          begin
            { a dot is as many pixels wide as the zoom is whole hundreds of per cent (300% = 3 pixels), or one pixel in the 1 px grid mode; centred on the grid point }
            FCanvas.Brush.Style := bsSolid;
            if FOnePxDots then
              FCanvas.Brush.Color := TColor($404040)       // one pixel: dark, so it can be seen
            else
              FCanvas.Brush.Color := TColor($B0B0B0);
            FCanvas.FillRect(Gx - (DotSize - 1) div 2, Gy - (DotSize - 1) div 2, Gx - (DotSize - 1) div 2 + DotSize, Gy - (DotSize - 1) div 2 + DotSize);
            if DotSize >= 3 then
            begin
              { a big dot gets a darker pixel at its centre: the exact grid point, for placing things by hand }
              FCanvas.Brush.Color := TColor($606060);
              FCanvas.FillRect(Gx, Gy, Gx + 1, Gy + 1);
            end;
            FCanvas.Brush.Style := bsClear;
          end;
          Y := Y + Grid;
        end;
        X := X + Grid;
      end;
    end;
  end;
  { the border: a rectangle round the printable area }
  if D.ShowBorder then
  begin
    R := D.BorderRectangle;
    P1 := Px(DPoint(R.Left, R.Top));
    P2 := Px(DPoint(R.Right, R.Bottom));
    FCanvas.Pen.Color := clBlack;
    FCanvas.Pen.Width := Max(1, Dist(2));
    FCanvas.Brush.Style := bsClear;
    FCanvas.Rectangle(P1.x, P1.y, P2.x + 1, P2.y + 1);
    FCanvas.Pen.Width := 1;
  end;
  { the title block and the rulers (CDetails::Display) }
  PaintTitleBlock(Sheet, AFileName, ASheetsText, ADocNoText);
  PaintExtendedBlock(Sheet);
  PaintRulers(Sheet);
end;


const
  BOX_WIDTH = 400;          // CDetails::M_NBOXWIDTH
  LINE_HEIGHT = 18;         // M_NLINEHEIGHT
  RULER_HEIGHT = 15;        // M_NRULERHEIGHT

{ ===========================================================================
  TSchematicPainter.DetailsText  (procedure)
  Parameters:
    Sheet: TDesignSheet - the sheet (its fonts and text sizes)
    const Str: String - the text
    X: Double - x of the anchor, design units
    Y: Double - y of the anchor, design units
    Centre: Boolean - True to centre the text on the anchor
    Vertical: Boolean - True to draw it reading upwards
    FontNumber: Integer - font resource number
    MaxWidth: Double - widest the text may be, 0 for no limit
  Notes:
    Draws one piece of title block or ruler text with TinyCAD's alignment: the bottom of the
    text at Y (TA_BOTTOM), left aligned or centred on X, or standing upright and reading
    upwards. Text longer than MaxWidth is cut to fit.
  =========================================================================== }
procedure TSchematicPainter.DetailsText(Sheet: TDesignSheet; const Str: String; X, Y: Double; Centre, Vertical: Boolean;
  FontNumber: Integer; MaxWidth: Double);
var
  S: String;
  W: Double;
begin
  S := Str;
  if S = '' then
    Exit;
  W := Sheet.Options.TextExtent(S, FontNumber).cx;
  { TextOut with a width: the text is cut so it fits }
  if MaxWidth > 0 then
    while (Length(S) > 0) and (W > MaxWidth) do
    begin
      SetLength(S, Length(S) - 1);
      W := Sheet.Options.TextExtent(S, FontNumber).cx;
    end;
  if S = '' then
    Exit;
  if Vertical then
  begin
    { reads upwards, its centre at Y and its right edge (the bottom of the letters) at X }
    if Centre then
      Y := Y + W / 2;
    TextAt(S, DPoint(X, Y), True, FontNumber, 0);
  end
  else
  begin
    { the bottom of the text is at Y, as TA_BOTTOM does; TA_CENTER puts the middle of it at X }
    if Centre then
      X := X - W / 2;
    TextAt(S, DPoint(X, Y), False, FontNumber, 0);
  end;
end;

{ ===========================================================================
  TSchematicPainter.PaintTitleBlock  (procedure)
  Parameters:
    Sheet: TDesignSheet - the sheet
    const AFileName: String - path of the file
    const ASheetsText: String - text
    const ADocNoText: String - text
  Notes:
    Draws the title block in the bottom right corner of the page when the sheet's details are
    visible (CDetails::DisplayBox): the outline and its dividing lines, the captions Title,
    Author, File, Document, Sheets, Date and Revision, and the sheet's own text in the boxes.
    The block moves in from the edge when the rulers are on. With a revision history the
    revision and date shown are those of the current revision.
  =========================================================================== }
procedure TSchematicPainter.PaintTitleBlock(Sheet: TDesignSheet; const AFileName, ASheetsText, ADocNoText: String);
var
  D: TDetails;
  TLx, TLy, BRx, BRy, BottomRow, MiddleRow, TextSpace: Double;
begin
  D := Sheet.Details;
  if not D.IsVisible then
    Exit;
  SetPen(0, 1, 0);
  TLx := D.PageWidth - BOX_WIDTH - 2;
  TLy := D.PageHeight - LINE_HEIGHT * 9 - 2;
  BRx := D.PageWidth - 2;
  BRy := D.PageHeight - 2;
  if D.HasRulers then
  begin
    TLx := TLx - RULER_HEIGHT; TLy := TLy - RULER_HEIGHT;
    BRx := BRx - RULER_HEIGHT; BRy := BRy - RULER_HEIGHT;
  end;
  TextSpace := LINE_HEIGHT / 2;
  BottomRow := (BRx - TLx) / 3;
  MiddleRow := BRx - (BRx - TLx) / 5;
  { the outline }
  Ln(DPoint(TLx, TLy), DPoint(BRx, TLy));
  Ln(DPoint(BRx, TLy), DPoint(BRx, BRy));
  Ln(DPoint(BRx, BRy), DPoint(TLx, BRy));
  Ln(DPoint(TLx, BRy), DPoint(TLx, TLy));
  { the horizontal lines }
  Ln(DPoint(TLx, TLy + LINE_HEIGHT * 2), DPoint(BRx, TLy + LINE_HEIGHT * 2));
  Ln(DPoint(TLx, TLy + LINE_HEIGHT * 5), DPoint(BRx, TLy + LINE_HEIGHT * 5));
  Ln(DPoint(TLx, TLy + LINE_HEIGHT * 7), DPoint(BRx, TLy + LINE_HEIGHT * 7));
  { the vertical lines }
  Ln(DPoint(MiddleRow, TLy + LINE_HEIGHT * 5), DPoint(MiddleRow, TLy + LINE_HEIGHT * 7));
  Ln(DPoint(TLx + BottomRow, TLy + LINE_HEIGHT * 7), DPoint(TLx + BottomRow, TLy + LINE_HEIGHT * 9));
  Ln(DPoint(MiddleRow, TLy + LINE_HEIGHT * 7), DPoint(MiddleRow, TLy + LINE_HEIGHT * 9));
  { the captions }
  DetailsText(Sheet, rsTitle, TLx + TextSpace, TLy + LINE_HEIGHT, False, False, fTEXT);
  DetailsText(Sheet, rsAuthor, TLx + TextSpace, TLy + LINE_HEIGHT * 3, False, False, fTEXT);
  DetailsText(Sheet, rsFile, TLx + TextSpace, TLy + LINE_HEIGHT * 6, False, False, fTEXT);
  DetailsText(Sheet, rsDocument, TLx + TextSpace, TLy + LINE_HEIGHT * 8, False, False, fTEXT);
  DetailsText(Sheet, rsSheets, MiddleRow + TextSpace, TLy + LINE_HEIGHT * 6, False, False, fTEXT);
  DetailsText(Sheet, rsDate, TLx + BottomRow + TextSpace, TLy + LINE_HEIGHT * 8, False, False, fTEXT);
  DetailsText(Sheet, rsRevision, MiddleRow + TextSpace, TLy + LINE_HEIGHT * 8, False, False, fTEXT);
  { the sheet's own text }
  DetailsText(Sheet, D.Title, TLx + TextSpace * 2, TLy + LINE_HEIGHT * 2, False, False, fTEXT);
  DetailsText(Sheet, D.Author, TLx + TextSpace * 2, TLy + LINE_HEIGHT * 4, False, False, fTEXT);
  DetailsText(Sheet, D.Org, TLx + TextSpace * 2, TLy + LINE_HEIGHT * 5, False, False, fTEXT);
  DetailsText(Sheet, AFileName, TLx + TextSpace * 2, TLy + LINE_HEIGHT * 7, False, False, fTEXT, MiddleRow - TLx - TextSpace * 4);
  if ADocNoText <> '' then
    DetailsText(Sheet, ADocNoText, TLx + TextSpace * 2, TLy + LINE_HEIGHT * 9, False, False, fTEXT)
  else
    DetailsText(Sheet, D.DocNo, TLx + TextSpace * 2, TLy + LINE_HEIGHT * 9, False, False, fTEXT);
  DetailsText(Sheet, ASheetsText, MiddleRow + TextSpace * 2, TLy + LINE_HEIGHT * 7, False, False, fTEXT);
  DetailsText(Sheet, D.EffectiveRevisionDate, TLx + BottomRow + TextSpace * 2, TLy + LINE_HEIGHT * 9, False, False, fTEXT);
  DetailsText(Sheet, D.EffectiveRevision, MiddleRow + TextSpace * 2, TLy + LINE_HEIGHT * 9, False, False, fTEXT);
end;

{ ===========================================================================
  TSchematicPainter.PaintExtendedBlock  (procedure)
  Parameters:
    Sheet: TDesignSheet - the sheet
  Notes:
    The extended information of the title block, when the sheet shows its title block and has
    the extended information switched on (see UTitleBlock for where everything is): a table to
    the left of the block with a heading row (REV, DATE, DESCRIPTION, BY) and the five newest
    revisions below it, newest first by date or by revision label as the sheet says; and above
    the two together a cell halved into NOTES and REFERENCE with the text the sheet holds,
    filled out to the width of its half. A revision's description is its notes on one line; text
    too long for its column is cut at the column's edge, and notes too long for the cell end in
    "...".
  =========================================================================== }
procedure TSchematicPainter.PaintExtendedBlock(Sheet: TDesignSheet);
var
  D: TDetails;
  L: TExtendedLayout;
  Revs: TRevisionArray;
  i, k: Integer;
  TextSpace, FontH, ColW, Capacity: Double;
  Lines: TStringArray;
  Heads: array[0..3] of String;
  Cells: array[0..3] of String;
  function Base(Row: Integer): Double;      // where the text of a row stands: centred in its height
  begin
    Result := L.RowY[Row] + (L.RowHeight + FontH) / 2;
  end;
  function Flat(const S: String): String;
  begin
    Result := Trim(StringReplace(StringReplace(StringReplace(S, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]), #9, ' ', [rfReplaceAll]));
  end;
  procedure Cell(const Str: String; Col, Row: Integer);
  begin
    DetailsText(Sheet, Str, L.ColX[Col] + TextSpace, Base(Row), False, False, fTEXT, L.ColX[Col + 1] - L.ColX[Col] - TextSpace * 2);
  end;
  procedure Part(const Caption, Text: String; Left, Right: Double);
  var
    j: Integer;
  begin
    DetailsText(Sheet, Caption, Left + TextSpace, L.NotesTop + TB_LINE_HEIGHT, False, False, fTEXT);
    Capacity := Int((L.NotesBottom - 2 - (L.NotesTop + TB_LINE_HEIGHT * 2)) / TB_LINE_HEIGHT) + 1;
    Lines := WrapToWidth(Text, Right - Left - TextSpace * 2, Sheet.Options, fTEXT, Trunc(Capacity));
    for j := 0 to High(Lines) do
      DetailsText(Sheet, Lines[j], Left + TextSpace, L.NotesTop + TB_LINE_HEIGHT * 2 + TB_LINE_HEIGHT * j, False, False, fTEXT);
  end;
begin
  D := Sheet.Details;
  if not (D.IsVisible and D.ExtendedInfo) then
    Exit;
  L := ExtendedLayout(D.PageWidth, D.PageHeight, D.HasRulers);
  SetPen(0, 1, 0);
  TextSpace := TB_LINE_HEIGHT / 2;
  FontH := Sheet.Options.TextExtent('Ag', fTEXT).cy;
  { the revision table: its outline, the lines between its rows and its columns }
  Ln(DPoint(L.ColX[0], L.RowY[0]), DPoint(L.ColX[4], L.RowY[0]));
  Ln(DPoint(L.ColX[4], L.RowY[0]), DPoint(L.ColX[4], L.RowY[TB_ROWS]));
  Ln(DPoint(L.ColX[4], L.RowY[TB_ROWS]), DPoint(L.ColX[0], L.RowY[TB_ROWS]));
  Ln(DPoint(L.ColX[0], L.RowY[TB_ROWS]), DPoint(L.ColX[0], L.RowY[0]));
  for i := 1 to TB_ROWS - 1 do Ln(DPoint(L.ColX[0], L.RowY[i]), DPoint(L.ColX[4], L.RowY[i]));
  for i := 1 to 3 do Ln(DPoint(L.ColX[i], L.RowY[0]), DPoint(L.ColX[i], L.RowY[TB_ROWS]));
  { the headings and the five newest revisions }
  Heads[0] := 'REV'; Heads[1] := 'DATE'; Heads[2] := 'DESCRIPTION'; Heads[3] := 'BY';
  for i := 0 to 3 do Cell(Heads[i], i, 0);
  Revs := NewestRevisions(D.Revisions, D.Revision, D.LastChange, D.SortByRevision, EXTENDED_ROWS);
  for i := 0 to High(Revs) do
  begin
    Cells[0] := Revs[i].Rev; Cells[1] := Revs[i].Date; Cells[2] := Flat(Revs[i].Notes); Cells[3] := Revs[i].Author;
    for k := 0 to 3 do Cell(Cells[k], k, i + 1);
  end;
  { the cell above the block and the table: notes on the left, reference on the right }
  Ln(DPoint(L.NotesLeft, L.NotesTop), DPoint(L.NotesRight, L.NotesTop));
  Ln(DPoint(L.NotesRight, L.NotesTop), DPoint(L.NotesRight, L.NotesBottom));
  Ln(DPoint(L.NotesRight, L.NotesBottom), DPoint(L.NotesLeft, L.NotesBottom));
  Ln(DPoint(L.NotesLeft, L.NotesBottom), DPoint(L.NotesLeft, L.NotesTop));
  Ln(DPoint(L.NotesMid, L.NotesTop), DPoint(L.NotesMid, L.NotesBottom));
  Part('NOTES', D.Notes, L.NotesLeft, L.NotesMid);
  Part('REFERENCE', D.Reference, L.NotesMid, L.NotesRight);
end;

{ ===========================================================================
  TSchematicPainter.PaintRulers  (procedure)
  Parameters:
    Sheet: TDesignSheet - the sheet
  Notes:
    Draws the drawing frame when the sheet has rulers on (CDetails::DisplayRulers): an outer and
    an inner rectangle joined at the corners, divided into columns numbered 1, 2, 3 ... along
    the top and bottom and rows lettered A, B, C ... down the sides. A portrait page always has
    5 columns and 7 rows; a landscape page has the numbers set in its details.
  =========================================================================== }
procedure TSchematicPainter.PaintRulers(Sheet: TDesignSheet);
var
  D: TDetails;
  TL1x, TL1y, TL2x, TL2y, BR1x, BR1y, BR2x, BR2y, Split: Double;
  Cols, Rows, ColNo, RowNo: Integer;
begin
  D := Sheet.Details;
  if not D.HasRulers then
    Exit;
  SetPen(0, 1, 0);
  TL1x := 0; TL1y := 0;
  TL2x := RULER_HEIGHT + 2; TL2y := RULER_HEIGHT + 2;
  BR2x := D.PageWidth - RULER_HEIGHT - 2; BR2y := D.PageHeight - RULER_HEIGHT - 2;
  BR1x := D.PageWidth - 2; BR1y := D.PageHeight - 2;
  { the outer border }
  Ln(DPoint(TL1x, TL1y), DPoint(BR1x, TL1y));
  Ln(DPoint(BR1x, TL1y), DPoint(BR1x, BR1y));
  Ln(DPoint(BR1x, BR1y), DPoint(TL1x, BR1y));
  Ln(DPoint(TL1x, BR1y), DPoint(TL1x, TL1y));
  { the inner border }
  Ln(DPoint(TL2x, TL2y), DPoint(BR2x, TL2y));
  Ln(DPoint(BR2x, TL2y), DPoint(BR2x, BR2y));
  Ln(DPoint(BR2x, BR2y), DPoint(TL2x, BR2y));
  Ln(DPoint(TL2x, BR2y), DPoint(TL2x, TL2y));
  { the cross bracing at the corners }
  Ln(DPoint(TL1x, TL1y), DPoint(TL2x, TL2y));
  Ln(DPoint(BR1x, BR1y), DPoint(BR2x, BR2y));
  Ln(DPoint(BR1x, TL1y), DPoint(BR2x, TL2y));
  Ln(DPoint(TL1x, BR1y), DPoint(TL2x, BR2y));
  Cols := D.HorizRulerSize;
  Rows := D.VertRulerSize;
  if D.PageWidth < D.PageHeight then     // a portrait page
  begin
    Cols := 5;
    Rows := 7;
  end;
  if (Cols < 1) or (Rows < 1) then
    Exit;
  Split := (BR1x - TL1x) / Cols;
  for ColNo := 0 to Cols - 1 do
  begin
    Ln(DPoint(ColNo * Split, TL1y), DPoint(ColNo * Split, TL2y));
    DetailsText(Sheet, IntToStr(ColNo + 1), Split * ColNo + Split / 2, TL2y - 2, True, False, fPIN);
    Ln(DPoint(ColNo * Split, BR1y), DPoint(ColNo * Split, BR2y));
    DetailsText(Sheet, IntToStr(ColNo + 1), Split * ColNo + Split / 2, BR1y - 2, True, False, fPIN);
  end;
  Split := (BR1y - TL1y) / Rows;
  for RowNo := 0 to Rows - 1 do
  begin
    Ln(DPoint(TL1x, RowNo * Split), DPoint(TL2x, RowNo * Split));
    DetailsText(Sheet, Chr(Ord('A') + RowNo), TL2x - 2, Split * RowNo + Split / 2, True, True, fPIN);
    Ln(DPoint(BR1x, RowNo * Split), DPoint(BR2x, RowNo * Split));
    DetailsText(Sheet, Chr(Ord('A') + RowNo), BR1x - 1, Split * RowNo + Split / 2, True, True, fPIN);
  end;
end;

{ ===========================================================================
  TSchematicPainter.PaintPolygonHandles  (procedure)
  Parameters:
    Pg: TDrawPolygon
  Notes:
    Draws the handles of a selected polygon as small black squares (CDrawPolygon::PaintHandles),
    and the control point of a curved segment the same way. The squares are at least 2 pixels
    each side of the point so they can still be seen and picked when the sheet is zoomed out.
  =========================================================================== }
procedure TSchematicPainter.PaintPolygonHandles(Pg: TDrawPolygon);
var
  i, Half: Integer;
  Pt: TPoint;
begin
  Half := Max(2, Dist(2));
  FCanvas.Pen.Style := psSolid;
  FCanvas.Pen.Width := 1;
  FCanvas.Pen.Color := clBlack;
  FCanvas.Brush.Style := bsSolid;
  FCanvas.Brush.Color := clBlack;
  for i := 0 to High(Pg.Handles) do
  begin
    Pt := Px(DPoint(Pg.Handles[i].X + Pg.PointA.x, Pg.Handles[i].Y + Pg.PointA.y));
    FCanvas.Rectangle(Pt.x - Half, Pt.y - Half, Pt.x + Half + 1, Pt.y + Half + 1);
    if Pg.Handles[i].Arc = Arc_control then
    begin
      Pt := Px(DPoint(Pg.Handles[i].Control.x + Pg.PointA.x, Pg.Handles[i].Control.y + Pg.PointA.y));
      FCanvas.Rectangle(Pt.x - Half, Pt.y - Half, Pt.x + Half + 1, Pt.y + Half + 1);
    end;
  end;
  FCanvas.Brush.Style := bsClear;
end;

{ ===========================================================================
  TSchematicPainter.PaintLineHandles  (procedure)
  Parameters:
    L: TDrawLine
  Notes:
    Draws the small light gray squares TinyCAD shows at both ends of a chosen wire
    (CDrawLine::PaintHandles: 4 design units across, centred on the end), at least 2 pixels each
    side so they can be seen when the sheet is zoomed out. Screen only: a printout or a picture
    does not have them (the view paints them after the sheet).
  =========================================================================== }
procedure TSchematicPainter.PaintLineHandles(L: TDrawLine);
var
  k, Half: Integer;
  Pt: TPoint;
begin
  Half := Max(2, Dist(2));
  FCanvas.Pen.Style := psSolid;
  FCanvas.Pen.Width := 1;
  FCanvas.Pen.Color := TColor($808080);
  FCanvas.Brush.Style := bsSolid;
  FCanvas.Brush.Color := TColor($C0C0C0);
  for k := 0 to 1 do
  begin
    if k = 0 then
      Pt := Px(L.PointA)
    else
      Pt := Px(L.PointB);
    FCanvas.Rectangle(Pt.x - Half, Pt.y - Half, Pt.x + Half + 1, Pt.y + Half + 1);
  end;
  FCanvas.Brush.Style := bsClear;
end;

{ ===========================================================================
  TSchematicPainter.PaintErrorMarker  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
    Selected: Boolean - flag
  Notes:
    The red circle TinyCAD puts on what Find (and the design rules check) has found
    (CDrawError::Paint): a ring of radius 6 units drawn with a heavy pen, red-brown (127, 0, 0),
    and bright red (255, 32, 32) for the one that is chosen. The ring and the pen are never
    smaller than a few pixels, so the circles can still be seen when the sheet is zoomed out.
  =========================================================================== }
procedure TSchematicPainter.PaintErrorMarker(const P: TDPoint; Selected: Boolean);
var
  C: TPoint;
  R: Integer;
begin
  C := Px(P);
  R := Max(Dist(6), 6);
  FCanvas.Brush.Style := bsClear;
  FCanvas.Pen.Style := psSolid;
  FCanvas.Pen.Width := Max(Dist(5), 2);
  if Selected then
    FCanvas.Pen.Color := RGBToColor(255, 32, 32)
  else
    FCanvas.Pen.Color := RGBToColor(127, 0, 0);
  FCanvas.Ellipse(C.x - R, C.y - R, C.x + R + 1, C.y + R + 1);
  FCanvas.Pen.Width := 1;
end;

{ ===========================================================================
  TSchematicPainter.PaintOriginMarker  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
  Notes:
    The mark TinyCAD puts on the origin of a library symbol that is being edited
    (CDrawOrigin::Paint): a cross 6 units each way in very light grey (208, 208, 208).
  =========================================================================== }
procedure TSchematicPainter.PaintOriginMarker(const P: TDPoint);
var
  A, B: TPoint;
begin
  FCanvas.Pen.Style := psSolid;
  FCanvas.Pen.Width := 1;
  FCanvas.Pen.Color := RGBToColor(208, 208, 208);
  A := Px(DPoint(P.x - 6, P.y));
  B := Px(DPoint(P.x + 6, P.y));
  FCanvas.MoveTo(A.x, A.y);
  FCanvas.LineTo(B.x, B.y);
  A := Px(DPoint(P.x, P.y - 6));
  B := Px(DPoint(P.x, P.y + 6));
  FCanvas.MoveTo(A.x, A.y);
  FCanvas.LineTo(B.x, B.y);
end;

{ ===========================================================================
  TSchematicPainter.ContextOrient  (function)
  Parameters:  none
  Returns:
    TOrient
  Notes:
    Where the picture's own directions go on the screen: along it and down it, found by
    following two steps in the design's directions through the transform. For a sheet that is
    the upright orientation; inside a symbol that is placed turned or flipped it is the symbol's
    turn and flip (the zoom only scales and has no effect on which way is which).
  =========================================================================== }
function TSchematicPainter.ContextOrient: TOrient;
var
  Z, U, V: TPoint;
  function Dir(Dx, Dy: Integer; out Ax, Ay: Integer): Boolean;
  begin
    Ax := 0; Ay := 0;
    if Abs(Dx) >= Abs(Dy) then begin if Dx > 0 then
      Ax := 1
    else
      Ax := -1; end
    else begin if Dy > 0 then
      Ay := 1
    else
      Ay := -1; end;
    Result := True;
  end;
begin
  Z := Px(DPoint(0, 0));
  U := Px(DPoint(1000, 0));
  V := Px(DPoint(0, 1000));
  Dir(U.x - Z.x, U.y - Z.y, Result.A, Result.C);
  Dir(V.x - Z.x, V.y - Z.y, Result.B, Result.D);
end;

{ ===========================================================================
  TSchematicPainter.PaintMetaFile  (procedure)
  Parameters:
    O: TDrawMetaFile
  Notes:
    Draws a picture stretched into the rectangle between its two corners (CDrawMetaFile::Paint),
    turned and flipped as it has been (its own orientation) and as the symbol it may be part of
    is turned and flipped: the picture's pixels are rearranged (UOrient), never blurred, and
    then stretched into the box. (TinyCAD itself draws it upright, squeezed into the turned
    box.) A picture that cannot be drawn (it is missing, damaged, or of a kind this port does
    not draw) is shown as TinyCAD shows it: a white rectangle with a black outline and the words
    "Invalid image". A selected picture also gets an outline in the selection color.
  =========================================================================== }
procedure TSchematicPainter.PaintMetaFile(O: TDrawMetaFile);
var
  P1, P2: TPoint;
  R: TRect;
  G: TGraphic;
begin
  P1 := Px(O.PointA);
  P2 := Px(O.PointB);
  R := Rect(Min(P1.x, P2.x), Min(P1.y, P2.y), Max(P1.x, P2.x) + 1, Max(P1.y, P2.y) + 1);
  G := OrientedPictureOf(TImageResource(FOpts.Images.Get(O.Image)), OrientMul(ContextOrient, O.Orient));
  if G <> nil then
    FCanvas.StretchDraw(R, G)
  else
  begin
    FCanvas.Pen.Style := psSolid;
    FCanvas.Pen.Width := 1;
    FCanvas.Pen.Color := clBlack;
    FCanvas.Brush.Style := bsSolid;
    FCanvas.Brush.Color := clWhite;
    FCanvas.Rectangle(R);
    FCanvas.Font.Color := clBlack;
    FCanvas.Font.Height := -Max(8, Min(14, (R.Bottom - R.Top) div 3));
    FCanvas.TextRect(R, R.Left + 5, R.Top + 5, rsInvalidImage);
    FCanvas.Brush.Style := bsClear;
  end;
  if FSel then
  begin
    FCanvas.Pen.Style := psSolid;
    FCanvas.Pen.Width := 1;
    FCanvas.Pen.Color := FSelColor;
    FCanvas.Brush.Style := bsClear;
    FCanvas.Rectangle(R);
  end;
end;

{ ===========================================================================
  TSchematicPainter.PaintResizeHandles  (procedure)
  Parameters:
    O: TDrawingObject
    HandleSize: Double - number
  Notes:
    What MFC's tracker draws round a selected rectangle (CContext::PaintTracker): a dotted
    outline a pixel outside the rectangle and eight black squares just outside it, at the
    corners and the middles of the sides.
  =========================================================================== }
procedure TSchematicPainter.PaintResizeHandles(O: TDrawingObject; HandleSize: Double);
var
  P1, P2, H1, H2: TPoint;
  i: Integer;
  R: TDRect;
begin
  if O is TDrawRungGrid then
  begin
    { the rung grid has no corners of its own: its outline is the area of the table, its one handle is the middle of its bottom edge }
    P1 := Px(DPoint(TDrawRungGrid(O).AreaRect.Left, TDrawRungGrid(O).AreaRect.Top));
    P2 := Px(DPoint(TDrawRungGrid(O).AreaRect.Right, TDrawRungGrid(O).AreaRect.Bottom));
    FCanvas.Brush.Style := bsClear;
    FCanvas.Pen.Style := psDot;
    FCanvas.Pen.Width := 1;
    FCanvas.Pen.Color := clBlack;
    FCanvas.Rectangle(Min(P1.x, P2.x), Min(P1.y, P2.y), Max(P1.x, P2.x) + 1, Max(P1.y, P2.y) + 1);
    FCanvas.Pen.Style := psSolid;
    FCanvas.Brush.Style := bsSolid;
    FCanvas.Brush.Color := clBlack;
    R := O.ResizeHandleRect(HANDLE_BOTTOM, HandleSize);
    H1 := Px(DPoint(R.Left, R.Top));
    H2 := Px(DPoint(R.Right, R.Bottom));
    FCanvas.Rectangle(Min(H1.x, H2.x), Min(H1.y, H2.y), Max(H1.x, H2.x) + 1, Max(H1.y, H2.y) + 1);
    FCanvas.Brush.Style := bsClear;
    Exit;
  end;
  P1 := Px(O.PointA);
  P2 := Px(O.PointB);
  FCanvas.Brush.Style := bsClear;
  FCanvas.Pen.Style := psDot;
  FCanvas.Pen.Width := 1;
  FCanvas.Pen.Color := clBlack;
  FCanvas.Rectangle(Min(P1.x, P2.x) - 1, Min(P1.y, P2.y) - 1, Max(P1.x, P2.x) + 2, Max(P1.y, P2.y) + 2);
  FCanvas.Pen.Style := psSolid;
  FCanvas.Brush.Style := bsSolid;
  FCanvas.Brush.Color := clBlack;
  for i := HANDLE_TOPLEFT to HANDLE_LEFT do
  begin
    R := O.ResizeHandleRect(i, HandleSize);
    H1 := Px(DPoint(R.Left, R.Top));
    H2 := Px(DPoint(R.Right, R.Bottom));
    FCanvas.Rectangle(Min(H1.x, H2.x), Min(H1.y, H2.y), Max(H1.x, H2.x) + 1, Max(H1.y, H2.y) + 1);
  end;
  FCanvas.Brush.Style := bsClear;
end;

end.
