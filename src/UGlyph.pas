{ Glyphs of parts: the small picture of a part's default symbol that the Parts tab lists (PartGlyph holds one PNG per square size). The picture is drawn with the same painter as the
  library panel's preview.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UGlyph;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, UDPoint, UDrawTypes, UGeometry, UDrawingObjects, USymbols, UDesign, UPainter, UPartsDb;

const
  GLYPH_SIZES: array[0..3] of Integer = (16, 24, 32, 48);

{ the PNG bytes of a symbol (TinyCAD symbol XML) drawn into a Size x Size picture, '' when the text is not a symbol }
function RenderSymbolGlyph(const Xml, AName: String; Size: Integer): String;

{ Draws the default symbol of a part into every size of GLYPH_SIZES and stores them as the part's glyphs; a part without a symbol (or one that cannot be drawn) has none.
  Returns the number of sizes stored. }
function RegenerateGlyphs(Lib: TPartsLibrary; PartID: Int64): Integer;

implementation

{ ===========================================================================
  RenderSymbolGlyph  (function)
  Parameters:
    const Xml: String - the symbol's TinyCAD XML
    const AName: String - the name the symbol is given for the drawing
    Size: Integer - the side of the square picture in pixels
  Returns:
    String - the PNG file's bytes; '' when the XML is not a symbol
  Notes:
    White background, the symbol scaled to fit with a margin (never larger than twice its size). The picture is built in a sheet of its own; nothing outside is touched.
  =========================================================================== }
function RenderSymbolGlyph(const Xml, AName: String; Size: Integer): String;
var
  D: TDesignFile;
  Sheet: TDesignSheet;
  Sym: TDesignFileSymbol;
  M: TDrawMethod;
  Id: Integer;
  Bmp: TBitmap;
  Png: TPortableNetworkGraphic;
  Ms: TMemoryStream;
  T: TTransform;
  P: TSchematicPainter;
  L, Tp, R, B, W, H, Z: Double;
begin
  Result := '';
  D := TDesignFile.Create;
  try
    Sheet := D.AddSheet;
    Sym := TDesignFileSymbol.Create(Sheet.Options);
    Sym.Name := AName;
    Sym.Ppp := 1;
    if not LoadLibrarySymbolBlob(Sheet, Sym, Xml) then
    begin
      Sym.Free;
      Exit;
    end;
    Id := Sheet.Options.AddSymbol(Sym);
    M := TDrawMethod.CreateFromSymbol(Sheet.Options, Id, 0);
    Sheet.Drawing.Add(M);
    Sheet.UpdateLayout;
    Bmp := TBitmap.Create;
    try
      Bmp.SetSize(Size, Size);
      Bmp.Canvas.Brush.Color := clWhite;
      Bmp.Canvas.FillRect(0, 0, Size, Size);
      L := Min(M.PointA.x, M.PointB.x);
      R := Max(M.PointA.x, M.PointB.x);
      Tp := Min(M.PointA.y, M.PointB.y);
      B := Max(M.PointA.y, M.PointB.y);
      W := Max(20, R - L + 40);
      H := Max(20, B - Tp + 40);
      Z := Min((Size - 2) / W, (Size - 2) / H);
      Z := Min(Z, 2.0);
      T := TTransform.Create;
      try
        T.SetZoomFactor(Z);
        T.SetOrigin(DPoint(L - 20 - ((Size - 2) / Z - W) / 2, Tp - 20 - ((Size - 2) / Z - H) / 2));
        P := TSchematicPainter.Create(Bmp.Canvas, T);
        try
          P.PaintObject(M, False);
        finally
          P.Free;
        end;
      finally
        T.Free;
      end;
      Png := TPortableNetworkGraphic.Create;
      Ms := TMemoryStream.Create;
      try
        Png.Assign(Bmp);
        Png.SaveToStream(Ms);
        SetLength(Result, Ms.Size);
        if Ms.Size > 0 then
          Move(Ms.Memory^, Result[1], Ms.Size);
      finally
        Ms.Free;
        Png.Free;
      end;
    finally
      Bmp.Free;
    end;
  finally
    D.Free;
  end;
end;

{ ===========================================================================
  RegenerateGlyphs  (function)
  Parameters:
    Lib: TPartsLibrary - the parts file
    PartID: Int64 - the part
  Returns:
    Integer - how many sizes were stored (0 when the part has no symbol the loader can read; its old glyphs are removed then)
  Notes:
    Called after a symbol of the part was added, stored, made the default or deleted. The glyphs are derived data: the part's Revision is not touched.
  =========================================================================== }
function RegenerateGlyphs(Lib: TPartsLibrary; PartID: Int64): Integer;
var
  Xml, Nm, Png: String;
  i, Pi: Integer;
  Sizes: TInt64Array;
  Pngs: array of String;
begin
  Result := 0;
  Pi := Lib.PartIndexOfID(PartID);
  if Pi < 0 then
    Exit;
  Nm := Lib.Parts[Pi].Name;
  Xml := Lib.SymbolXml(PartID);
  SetLength(Sizes, 0);
  SetLength(Pngs, 0);
  if Xml <> '' then
    for i := 0 to High(GLYPH_SIZES) do
    begin
      Png := RenderSymbolGlyph(Xml, Nm, GLYPH_SIZES[i]);
      if Png = '' then
        Break;
      SetLength(Sizes, Length(Sizes) + 1);
      Sizes[High(Sizes)] := GLYPH_SIZES[i];
      SetLength(Pngs, Length(Pngs) + 1);
      Pngs[High(Pngs)] := Png;
    end;
  Lib.ClearGlyphs(PartID);
  for i := 0 to High(Sizes) do
    Lib.SetGlyph(PartID, Sizes[i], Pngs[i]);
  Result := Length(Sizes);
end;

end.
