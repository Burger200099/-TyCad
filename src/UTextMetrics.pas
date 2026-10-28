{ Text measuring with the real fonts, for the program (the tests keep the table-driven measurer of UGeometry, which is the same everywhere).

  TinyCAD measures text with Windows GDI: a font DatumScale (5) times larger is made, the string is measured in it and the result divided by 5, so
  that the width is nearly exact at any zoom. This does the same with the fonts of the widget set (a scratch bitmap's canvas), for the face, the
  weight and the slant the sheet's font resource names, so a text object's box (selection handles, hit test, the position of the text) is as wide
  as the text that is drawn, whatever the font. The table of Arial widths only fitted Arial.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UTextMetrics;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Graphics, UGeometry, UResources;

type
  { TCanvasTextMetrics }

  TCanvasTextMetrics = class(TTextMetrics)
  public
    DatumScale: Double;       // CContext::m_datum_scaling (5.0)
    constructor Create; override;
    function TextExtent(const Str: String; Font: TFontResource): TDSize; override;
  end;

{ makes the program's sheets measure with the real fonts (True) or with the table of Arial widths (False; what the tests use) }
procedure UseRealTextMetrics(AUse: Boolean);
{ which measurer new sheets get, in words (shown in the About box) }
function TextMetricsName: String;

implementation

var
  Scratch: TBitmap = nil;        // where the measuring is done: a bitmap's canvas needs no window

{ ===========================================================================
  UseRealTextMetrics  (procedure)
  Parameters:
    AUse: Boolean - flag
  Notes:
    Chooses what the sheets made from now on measure text with (DefaultTextMetrics); a sheet
    that exists keeps its measurer. The program turns it on when it starts; a test script turns
    it off so that sizes do not depend on the fonts of the machine.
  =========================================================================== }
procedure UseRealTextMetrics(AUse: Boolean);
begin
  if AUse then
    DefaultTextMetrics := TCanvasTextMetrics
  else
    DefaultTextMetrics := TApproxTextMetrics;
end;

{ ===========================================================================
  TextMetricsName  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    "real fonts" when the sheets made now measure text with the fonts of the machine, otherwise
    "table of Arial widths". The About box shows it, so a wrong text box can be traced to it.
  =========================================================================== }
function TextMetricsName: String;
begin
  if DefaultTextMetrics = TCanvasTextMetrics then
    Result := 'real fonts'
  else
    Result := 'table of Arial widths';
end;

{ ===========================================================================
  TCanvasTextMetrics.Create  (constructor)
  Parameters:  none
  Notes:
    The datum scale is 5, as in the C++ program (CContext::m_datum_scaling).
  =========================================================================== }
constructor TCanvasTextMetrics.Create;
begin
  inherited Create;
  DatumScale := 5.0;
end;

{ ===========================================================================
  TCanvasTextMetrics.TextExtent  (function)
  Parameters:
    const Str: String - the text
    Font: TFontResource
  Returns:
    TDSize
  Notes:
    The size of the text drawn in the font: the font is made DatumScale times as large as its
    height in design units (the painter makes it Height times the zoom pixels high), the string
    is measured on a canvas and both numbers are divided by DatumScale. The overbar marker is
    not measured, and an empty string is 0 by 0 as before. A font's requested width is not used
    (the painter does not use it either), so the box is what is drawn.
  =========================================================================== }
function TCanvasTextMetrics.TextExtent(const Str: String; Font: TFontResource): TDSize;
var
  S: String;
  Em: Double;
  H: Integer;
  Styles: TFontStyles;
  C: TCanvas;
begin
  S := StringReplace(Str, '`', '', [rfReplaceAll]);
  if S = '' then
  begin
    Result.cx := 0;
    Result.cy := 0;
    Exit;
  end;
  if Scratch = nil then
  begin
    Scratch := TBitmap.Create;
    Scratch.SetSize(8, 8);
  end;
  Em := Abs(Font.Height);
  if Em = 0 then
    Em := 13;
  H := Trunc(Em * DatumScale);
  if H < 1 then
    H := 1;
  Styles := [];
  if Font.Weight >= 700 then
    Include(Styles, fsBold);
  if Font.Italic <> 0 then
    Include(Styles, fsItalic);
  C := Scratch.Canvas;
  C.Font.Name := Font.FaceName;
  C.Font.Height := -H;
  C.Font.Style := Styles;
  Result.cx := C.TextWidth(S) / DatumScale;
  Result.cy := C.TextHeight(S) / DatumScale;
end;

initialization
  { the program measures with the real fonts whatever its project file does or does not call (a project file that was regenerated, or an
    older one, left the table of Arial widths in use); schematic.lpr switches back to the table when it runs a script }
  DefaultTextMetrics := TCanvasTextMetrics;

finalization
  Scratch.Free;

end.
