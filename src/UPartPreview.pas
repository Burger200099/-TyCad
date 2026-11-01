// SPDX-License-Identifier: LGPL-2.1-or-later
{ A symbol drawn into a paint box: the preview of the Parts tab (the default symbol of the chosen part) and the glyph of the Part ribbon (the symbol that shows the chosen object).
  The symbol is made from its TinyCAD XML in a design of its own; nothing outside is touched. Painted as the library panel's preview is: scaled to fit, never above twice its size.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UPartPreview;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, Types, UDPoint, UDrawTypes, UGeometry, UDrawingObjects, USymbols, UDesign, UPainter;

type
  TSymbolPreview = class
  private
    FDesign: TDesignFile;
    FMethod: TDrawMethod;
  public
    destructor Destroy; override;
    { throws the picture away }
    procedure Clear;
    { makes the picture from a symbol's XML (the text of a part's symbol); False, and no picture, when the text is not a symbol }
    function SetXml(const Xml, AName: String): Boolean;
    { true when there is something to paint }
    function HasSymbol: Boolean;
    { paints the symbol in the rectangle, on a white ground with a silver edge }
    procedure Paint(C: TCanvas; const R: TRect);
  end;

implementation

{ ===========================================================================
  TSymbolPreview.Destroy  (destructor)
  Notes:
    Frees the design the picture is made in.
  =========================================================================== }
destructor TSymbolPreview.Destroy;
begin
  Clear;
  inherited Destroy;
end;

{ ===========================================================================
  TSymbolPreview.Clear  (procedure)
  Notes:
    No picture.
  =========================================================================== }
procedure TSymbolPreview.Clear;
begin
  FMethod := nil;
  FreeAndNil(FDesign);
end;

{ ===========================================================================
  TSymbolPreview.SetXml  (function)
  Parameters:
    const Xml, AName: String - the symbol's XML and the name it is given
  Returns:
    Boolean - True when the symbol could be read
  =========================================================================== }
function TSymbolPreview.SetXml(const Xml, AName: String): Boolean;
var
  Sheet: TDesignSheet;
  Sym: TDesignFileSymbol;
  Id: Integer;
begin
  Clear;
  Result := False;
  if Xml = '' then
    Exit;
  FDesign := TDesignFile.Create;
  Sheet := FDesign.AddSheet;
  Sym := TDesignFileSymbol.Create(Sheet.Options);
  Sym.Name := AName;
  Sym.Ppp := 1;
  if not LoadLibrarySymbolBlob(Sheet, Sym, Xml) then
  begin
    Sym.Free;
    Clear;
    Exit;
  end;
  Id := Sheet.Options.AddSymbol(Sym);
  FMethod := TDrawMethod.CreateFromSymbol(Sheet.Options, Id, 0);
  Sheet.Drawing.Add(FMethod);
  Sheet.UpdateLayout;
  Result := True;
end;

function TSymbolPreview.HasSymbol: Boolean;
begin
  Result := FMethod <> nil;
end;

{ ===========================================================================
  TSymbolPreview.Paint  (procedure)
  Parameters:
    C: TCanvas - where to paint
    const R: TRect - the rectangle (the paint box's client area)
  =========================================================================== }
procedure TSymbolPreview.Paint(C: TCanvas; const R: TRect);
var
  T: TTransform;
  P: TSchematicPainter;
  L, Tp, Rt, B, W, H, Z: Double;
  PW, PH: Integer;
begin
  C.Brush.Color := clWhite;
  C.Pen.Color := clSilver;
  C.Rectangle(R);
  if FMethod = nil then
    Exit;
  PW := R.Right - R.Left;
  PH := R.Bottom - R.Top;
  L := Min(FMethod.PointA.x, FMethod.PointB.x);
  Rt := Max(FMethod.PointA.x, FMethod.PointB.x);
  Tp := Min(FMethod.PointA.y, FMethod.PointB.y);
  B := Max(FMethod.PointA.y, FMethod.PointB.y);
  W := Max(20, Rt - L + 40);
  H := Max(20, B - Tp + 40);
  Z := Min((PW - 10) / W, (PH - 10) / H);
  Z := Min(Z, 2.0);
  if Z <= 0 then
    Exit;
  T := TTransform.Create;
  try
    T.SetZoomFactor(Z);
    T.SetOrigin(DPoint(L - 20 - ((PW - 10) / Z - W) / 2, Tp - 20 - ((PH - 10) / Z - H) / 2));
    P := TSchematicPainter.Create(C, T);
    try
      P.PaintObject(FMethod, False);
    finally
      P.Free;
    end;
  finally
    T.Free;
  end;
end;

end.
