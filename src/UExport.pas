{ Export Image (File > Export Image..., TinyCAD's CTinyCadView::OnFileSaveasbitmap with CDlgExportPNG, CTinyCadDoc::SavePNG and CTinyCadDoc::CreateMetafile): the
  sheet on the screen, or the selected objects when something is selected, saved as a picture.

  The kinds are TinyCAD's four: a colour PNG, a black and white PNG, and the colour and black and white "enhanced metafile" - which only Windows can write, so here the
  vector kinds are SVG files (drawn by the same code on the Cairo canvas the printer uses). A PNG is drawn at a scale from 1 to 1000 per cent (100 is one pixel for
  each design unit, 0.2 mm) on white and can be turned a quarter turn clockwise; an SVG is always at the real size (the metafile of TinyCAD is too) and the scale and
  the turn do nothing to it.

  What is drawn: with nothing selected, the whole sheet (its border, title block and rulers and every object) on a page whose right and bottom edges are 10 units
  further out; with a selection, only the selected objects, on an area that holds them (the smallest rectangle round their PointA and PointB) with the same 10 units at
  the right and bottom. As when printing, construction objects are left out and nothing is highlighted.

  Differences from TinyCAD: the size of a PNG of a selection is the width and height of the area times the scale (TinyCAD multiplies the right and bottom edges, so
  a selection away from the corner gets a bigger picture with empty margin); the turn is exact (TinyCAD's reads one pixel too far to the right in each row); the
  metafiles are SVG files; and a file that cannot be written raises an error that the caller reports (TinyCAD ignores it).

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UExport;

{$mode objfpc}{$H+}

{ The Cairo canvas (SVG files) is linked in when the program starts, so on Windows the program would not start at all without the Cairo DLLs
  (libcairo-2.dll and what it needs): the loader stops with "DLL not found" (exit code $C0000135) before the first line runs. Windows builds
  are therefore made without it, and SVG export says so; define USE_CAIRO to include it (and ship the DLLs). }
{$IFDEF WINDOWS}{$IFNDEF USE_CAIRO}{$DEFINE NO_CAIRO}{$ENDIF}{$ENDIF}

interface

uses
  Classes, SysUtils, Graphics, Math, IntfGraphics, GraphType, FPImage, {$IFNDEF NO_CAIRO}CairoCanvas,{$ENDIF} UDPoint, UGeometry, UDrawingObjects, UDesign, UDocVars, UPainter, UPaper;

const
  EXPORT_KIND_COUNT = 4;             // 0 colour PNG, 1 black and white PNG, 2 colour SVG, 3 black and white SVG
  EXPORT_MIN_SCALE = 1;
  EXPORT_MAX_SCALE = 1000;
  EXPORT_DEFAULT_SCALE = 100;
  EXPORT_MARGIN = 10;                // design units added at the right and bottom
  EXPORT_SVG_DPI = 127;              // one design unit (0.2 mm) per pixel of the SVG's own page

function ExportKindName(AKind: Integer): String;
function ExportKindExtension(AKind: Integer): String;
function ExportKindIsSvg(AKind: Integer): Boolean;
function ExportKindIsBlackWhite(AKind: Integer): Boolean;
function ExportDefaultFileName(const DesignFile: String; AKind: Integer): String;
function ExportChangeExtension(const FileName: String; AKind: Integer): String;
function ExportRegion(Sheet: TDesignSheet; Selected: TList): TDRect;
procedure ExportPixelSize(const R: TDRect; AScale: Integer; out W, H: Integer);
procedure ExportImage(Design: TDesignFile; SheetIndex: Integer; Selected: TList; AKind, AScale: Integer; ARotate: Boolean; const AFileName: String);

implementation


uses UStrings;


{ ===========================================================================
  ExportKindName  (function)
  Parameters:
    AKind: Integer - whole number
  Returns:
    String
  Notes:
    CDlgExportPNG::OnInitDialog's four names, with the metafiles as SVG.
  =========================================================================== }
function ExportKindName(AKind: Integer): String;
begin
  if (AKind < 0) or (AKind >= EXPORT_KIND_COUNT) then
    Result := ''
  else
    case AKind of
      0: Result := rsColourPNGBitmap;
      1: Result := rsBWPNGBitmap;
      2: Result := rsColourScalableVectorGraphicsSVG;
      3: Result := rsBWScalableVectorGraphics;
    else
      Result := '';
    end;
end;

{ ===========================================================================
  ExportKindExtension  (function)
  Parameters:
    AKind: Integer - the kind, 0 to 3
  Returns:
    String - the extension with its dot
  Notes:
    The extension of the files of a kind: '.png' for the bitmaps and '.svg' for the vector kinds
    (CDlgExportPNG::getExtension gives '.png' or '.emf').
  =========================================================================== }
function ExportKindExtension(AKind: Integer): String;
begin
  if ExportKindIsSvg(AKind) then
    Result := '.svg'
  else
    Result := '.png';
end;

{ ===========================================================================
  ExportKindIsSvg  (function)
  Parameters:
    AKind: Integer - the kind, 0 to 3
  Returns:
    Boolean - True for the SVG kinds
  Notes:
    Tells the vector kinds from the bitmaps; the scale and the turn do nothing to an SVG.
  =========================================================================== }
function ExportKindIsSvg(AKind: Integer): Boolean;
begin
  Result := AKind >= 2;
end;

{ ===========================================================================
  ExportKindIsBlackWhite  (function)
  Parameters:
    AKind: Integer - the kind, 0 to 3
  Returns:
    Boolean - True for the black and white kinds
  Notes:
    Tells the black and white kinds from the colour ones.
  =========================================================================== }
function ExportKindIsBlackWhite(AKind: Integer): Boolean;
begin
  Result := AKind in [1, 3];
end;

{ ===========================================================================
  ExportDefaultFileName  (function)
  Parameters:
    const DesignFile: String - text
    AKind: Integer - whole number
  Returns:
    String
  Notes:
    OnFileSaveasbitmap: the design's name with its last extension replaced (any text after the
    last dot), or output.png for a name with no dot; then the extension of the kind
    (UpdateExtension).
  =========================================================================== }
function ExportDefaultFileName(const DesignFile: String; AKind: Integer): String;
var
  P: Integer;
begin
  P := Length(DesignFile);
  while (P > 0) and (DesignFile[P] <> '.') do Dec(P);
  if P = 0 then
    Result := 'output.png'
  else
    Result := Copy(DesignFile, 1, P - 1) + '.png';
  Result := ExportChangeExtension(Result, AKind);
end;

{ ===========================================================================
  ExportChangeExtension  (function)
  Parameters:
    const FileName: String - path of the file
    AKind: Integer - whole number
  Returns:
    String
  Notes:
    CDlgExportPNG::UpdateExtension.
  =========================================================================== }
function ExportChangeExtension(const FileName: String; AKind: Integer): String;
var
  P: Integer;
begin
  P := Length(FileName);
  while (P > 0) and (FileName[P] <> '.') do Dec(P);
  if P = 0 then
    Result := FileName
  else
    Result := Copy(FileName, 1, P - 1) + ExportKindExtension(AKind);
end;

{ ===========================================================================
  ExportRegion  (function)
  Parameters:
    Sheet: TDesignSheet - the sheet
    Selected: TList
  Returns:
    TDRect
  Notes:
    With a selection: the smallest rectangle round the PointA and PointB of the objects;
    without: the page, from 0,0. Then 10 units are added to the right and the bottom (SavePNG's
    InflateRect(0, 0, 10, 10)).
  =========================================================================== }
function ExportRegion(Sheet: TDesignSheet; Selected: TList): TDRect;
var
  I: Integer;
  O: TDrawingObject;
begin
  if (Selected <> nil) and (Selected.Count > 0) then
  begin
    Result := DRect(NaN, NaN, NaN, NaN);
    for I := 0 to Selected.Count - 1 do
    begin
      O := TDrawingObject(Selected[I]);
      if not HasCorners(O) then
        Continue;
      if IsNan(Result.Left) then
        Result := DRect(O.PointA.x, O.PointA.y, O.PointA.x, O.PointA.y);
      Result.Top := Min(Result.Top, Min(O.PointA.y, O.PointB.y));
      Result.Bottom := Max(Result.Bottom, Max(O.PointA.y, O.PointB.y));
      Result.Left := Min(Result.Left, Min(O.PointA.x, O.PointB.x));
      Result.Right := Max(Result.Right, Max(O.PointA.x, O.PointB.x));
    end;
    if IsNan(Result.Left) then
      Result := DRect(0, 0, Sheet.Details.PageWidth, Sheet.Details.PageHeight);      // (nothing chosen has corners)
  end
  else
    Result := DRect(0, 0, Sheet.Details.PageWidth, Sheet.Details.PageHeight);
  Result.Right := Result.Right + EXPORT_MARGIN;
  Result.Bottom := Result.Bottom + EXPORT_MARGIN;
end;

{ ===========================================================================
  ExportPixelSize  (procedure)
  Parameters:
    const R: TDRect - the XML reader, positioned on this element
    AScale: Integer - whole number
    out W: Integer - the XML writer to save into (out: set by the call)
    out H: Integer - whole number (out: set by the call)
  Notes:
    The size of the picture: the region times the scale, cut to whole pixels, at least 1.
  =========================================================================== }
procedure ExportPixelSize(const R: TDRect; AScale: Integer; out W, H: Integer);
begin
  W := Max(1, Trunc(DRectWidth(R) * AScale / 100));
  H := Max(1, Trunc(DRectHeight(R) * AScale / 100));
end;

{ ===========================================================================
  PaintExport  (procedure)
  Parameters:
    Design: TDesignFile - the design
    SheetIndex: Integer - zero-based sheet number
    Selected: TList
    ACanvas: TCanvas - the canvas to draw on
    W: Integer - the XML writer to save into
    H: Integer - whole number
    Zoom: Double - number
    const R: TDRect - the XML reader, positioned on this element
    BW: Boolean - flag
  Notes:
    Draws the region as a printed page is drawn: the sheet with its page details, or only the
    selected objects.
  =========================================================================== }
procedure PaintExport(Design: TDesignFile; SheetIndex: Integer; Selected: TList; ACanvas: TCanvas; W, H: Integer; Zoom: Double; const R: TDRect; BW: Boolean);
var
  T: TTransform;
  Painter: TSchematicPainter;
  Sheet: TDesignSheet;
begin
  Sheet := Design.Sheets[SheetIndex];
  T := TTransform.Create;
  try
    T.SetZoomFactor(Zoom);
    T.SetOriginX(R.Left);
    T.SetOriginY(R.Top);
    Painter := TSchematicPainter.Create(ACanvas, T);
    try
      Painter.Printing := True;
      Painter.AllBlack := BW;
      if (Selected <> nil) and (Selected.Count > 0) then
        Painter.PaintObjects(Sheet, Selected)
      else
      begin
        Painter.PaintPage(Sheet, False, Rect(0, 0, W, H), Design.FileName, SheetsText(Design, SheetIndex),
          DocNoText(Design, SheetIndex));
        Painter.PaintSheet(Sheet, nil);
      end;
    finally
      Painter.Free;
    end;
  finally
    T.Free;
  end;
end;

{ ===========================================================================
  SavePng  (procedure)
  Parameters:
    Design: TDesignFile - the design
    SheetIndex: Integer - zero-based sheet number
    Selected: TList
    AScale: Integer - whole number
    BW: Boolean - flag
    ARotate: Boolean - flag
    const AFileName: String - path of the file
  Notes:
    CTinyCadDoc::SavePNG: the region drawn on white at the scale, turned if asked, written as a
    PNG.
  =========================================================================== }
procedure SavePng(Design: TDesignFile; SheetIndex: Integer; Selected: TList; AScale: Integer; BW, ARotate: Boolean; const AFileName: String);
var
  R: TDRect;
  W, H, X, Y: Integer;
  Bmp: TBitmap;
  Png: TPortableNetworkGraphic;
  A, B: TLazIntfImage;
begin
  R := ExportRegion(Design.Sheets[SheetIndex], Selected);
  ExportPixelSize(R, AScale, W, H);
  Bmp := TBitmap.Create;
  Png := TPortableNetworkGraphic.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(W, H);
    Bmp.Canvas.Brush.Style := bsSolid;
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.Pen.Style := psSolid;
    Bmp.Canvas.Pen.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, W, H);
    PaintExport(Design, SheetIndex, Selected, Bmp.Canvas, W, H, AScale / 100, R, BW);
    if ARotate then
    begin
      A := TLazIntfImage.Create(0, 0);
      B := TLazIntfImage.Create(0, 0);
      try
        A.LoadFromBitmap(Bmp.Handle, Bmp.MaskHandle);
        B.DataDescription := A.DataDescription;
        B.SetSize(H, W);
        for Y := 0 to H - 1 do
          for X := 0 to W - 1 do
            B.Colors[H - 1 - Y, X] := A.Colors[X, Y];
        Png.LoadFromIntfImage(B);
      finally
        B.Free;
        A.Free;
      end;
    end
    else
      Png.Assign(Bmp);
    Png.SaveToFile(AFileName);
  finally
    Png.Free;
    Bmp.Free;
  end;
end;

{ ===========================================================================
  SaveSvg  (procedure)
  Parameters:
    Design: TDesignFile - the design
    SheetIndex: Integer - zero-based sheet number
    Selected: TList
    BW: Boolean - flag
    const AFileName: String - path of the file
  Notes:
    CTinyCadDoc::CreateMetafile as an SVG file: the region at its real size (one design unit for
    each pixel of a page of EXPORT_SVG_DPI dots per inch, so 0.2 mm), drawn by the same code on
    the Cairo canvas.
  =========================================================================== }
procedure SaveSvg(Design: TDesignFile; SheetIndex: Integer; Selected: TList; BW: Boolean; const AFileName: String);
{$IFDEF NO_CAIRO}
begin
  raise Exception.Create(rsSVGFilesNeedTheCairo);
end;
{$ELSE}
var
  R: TDRect;
  W, H: Integer;
  C: TCairoSvgCanvas;
begin
  R := ExportRegion(Design.Sheets[SheetIndex], Selected);
  ExportPixelSize(R, 100, W, H);
  C := TCairoSvgCanvas.Create(nil);
  try
    C.OutputFileName := AFileName;
    C.XDPI := EXPORT_SVG_DPI;
    C.YDPI := EXPORT_SVG_DPI;
    C.PaperWidth := W;
    C.PaperHeight := H;
    C.BeginDoc;
    PaintExport(Design, SheetIndex, Selected, C, W, H, 1.0, R, BW);
    C.EndDoc;
  finally
    C.Free;
  end;
end;
{$ENDIF}

{ ===========================================================================
  ExportImage  (procedure)
  Parameters:
    Design: TDesignFile - the design
    SheetIndex: Integer - zero-based sheet number
    Selected: TList
    AKind: Integer - whole number
    AScale: Integer - whole number
    ARotate: Boolean - flag
    const AFileName: String - path of the file
  Notes:
    Saves the picture. Raises an exception when the kind is out of range, a PNG's scale is, or
    the file cannot be written.
  =========================================================================== }
procedure ExportImage(Design: TDesignFile; SheetIndex: Integer; Selected: TList; AKind, AScale: Integer; ARotate: Boolean; const AFileName: String);
begin
  if (AKind < 0) or (AKind >= EXPORT_KIND_COUNT) then
    raise Exception.Create(rsUnknownKindOfImage);
  if (not ExportKindIsSvg(AKind)) and ((AScale < EXPORT_MIN_SCALE) or (AScale > EXPORT_MAX_SCALE)) then
    raise Exception.CreateFmt(rsTheScaleMustBeA, [EXPORT_MIN_SCALE, EXPORT_MAX_SCALE]);
  if (SheetIndex < 0) or (SheetIndex >= Design.SheetCount) then
    raise Exception.Create(rsNoSuchSheet);
  if ExportKindIsSvg(AKind) then
    SaveSvg(Design, SheetIndex, Selected, ExportKindIsBlackWhite(AKind), AFileName)
  else
    SavePng(Design, SheetIndex, Selected, AScale, ExportKindIsBlackWhite(AKind), ARotate, AFileName);
end;

end.
