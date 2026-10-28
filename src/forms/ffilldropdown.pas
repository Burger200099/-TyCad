// SPDX-License-Identifier: LGPL-2.1-or-later
unit FFillDropDown;

{$mode ObjFPC}{$H+}

{ The menu that drops down from the Fill button of a property panel (the rectangle, the circle ...): the fill styles with their pictures, and Color... to choose the color
  the fill is drawn in. The button tells it the fill it has now (SetFill); the choice comes back through OnPick, and the menu closes. The menu can be driven from the mouse
  (point and click, the wheel), and from the keyboard (Up, Down, Home, End, Enter, Space, Esc).

  The style is told and returned as the position in UProps.FillChoices (0 None, 1 Solid, 2 Horizontal, 3 Vertical, 4 Backward diagonal, 5 Forward diagonal, 6 Cross,
  7 Diagonal cross), not as the position in the menu (where Vertical comes before Horizontal, as the pictures of ilFillStyles do).

  Licence: LGPL 2.1 or later, as the rest of this port. }

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, LCLType,
  FSharedCtls, Types, FDropDownBase;

type
  { the items of the menu, in the order they are shown }
  TFillMenuItems = (fmiNone, fmiFill, fmiVertical, fmiHorizontal, fmiBackDiagonal,
   fmiFwdDiagonal, fmiCross, fmiDiagCross, fmiColor);

  { a choice was made: AChoice is the position in FillChoices of the fill style (what the menu had, when only the color was chosen), AColor the fill color }
  TFillPickEvent = procedure(Sender: TObject; AChoice: Integer; AColor: TColor) of object;

const
  NumFillMenuItems = 9;

{ draws a fill on a canvas: a white box with a 1 pixel black outline, the pattern of the fill style (a position in FillChoices) in the color inside it }
procedure DrawFillGlyph(ACanvas: TCanvas; const ARect: TRect; AChoice: Integer; AColor: TColor);

type

{ TfrmFillDropDown }

  TfrmFillDropDown = class(TfrmDropDownBase)
    imgFillNone: TImage;
    imgFill: TImage;
    imgVert: TImage;
    imgHoriz: TImage;
    imgBDiag: TImage;
    imgFDiag: TImage;
    imgCross: TImage;
    imgDCross: TImage;
    imgColor: TImage;
    lbFillNone: TLabel;
    lbFill: TLabel;
    lbFIllVert: TLabel;
    lbFillHoriz: TLabel;
    lbFillBDiag: TLabel;
    lbFillFDiag: TLabel;
    lbFillCross: TLabel;
    lbFillDCross: TLabel;
    lbColor: TLabel;
    plColor: TPanel;
    plSep1: TPanel;
    plFillNone: TPanel;
    plFill: TPanel;
    plVert: TPanel;
    plHoriz: TPanel;
    plBDiag: TPanel;
    plFDiag: TPanel;
    plCross: TPanel;
    plDCross: TPanel;
    plMenuItems: TPanel;
    procedure DoColorSelection(Sender: TObject);
    procedure DoFillPattern(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure MouseEnter(Sender: TObject);
    procedure MouseLeave(Sender: TObject);
    procedure MouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
  protected
    function HandleKey(var Key: Word; Shift: TShiftState): Boolean; override;
  private
    FMenuItems: array[0..NumFillMenuItems - 1] of TPanel;
    FChoice: Integer;               // the fill style (position in FillChoices) the menu was told, or the last one picked
    FColor: TColor;                 // the fill color
    FSel: Integer;                  // the highlighted item of the menu (a TFillMenuItems)
    FOnPick: TFillPickEvent;
    function ItemOf(Sender: TObject): Integer;
    procedure SetSelected(AValue: Integer);
    procedure ShowSelection;
    procedure ShowColorSwatch;
  public
    procedure SetFill(AChoice: Integer; AColor: TColor);
    procedure MoveSelection(ADelta: Integer);
    procedure ActivateSelection;
    procedure ColorChosen(AColor: TColor);
    property Color: TColor read FColor;
    property Choice: Integer read FChoice;
    property Selected: Integer read FSel write SetSelected;
    property OnPick: TFillPickEvent read FOnPick write FOnPick;
  end;

var
  frmFillDropDown: TfrmFillDropDown;

implementation

{$R *.lfm}

const
  { menu position -> position in FillChoices (the menu has Vertical before Horizontal; the same table turns it back). Color... is not a fill style. }
  MenuToChoice: array[0..7] of Integer = (0, 1, 3, 2, 4, 5, 6, 7);

{ ===========================================================================
  FillPixel  (function)
  Parameters:
    AChoice: Integer - whole number
    U: Integer - whole number
    V: Integer - whole number
  Returns:
    Boolean
  Notes:
    The patterns are lines 1 pixel wide every 4 pixels (as the hatch brushes). Solid is all ink;
    None has none.
  =========================================================================== }
function FillPixel(AChoice, U, V: Integer): Boolean;
var
  D: Integer;
begin
  D := ((U - V) mod 4 + 4) mod 4;
  case AChoice of
    1: Result := True;
    2: Result := V mod 4 = 2;                                  // horizontal lines
    3: Result := U mod 4 = 2;                                  // vertical lines
    4: Result := D = 0;                                        // backward diagonal: \
    5: Result := (U + V) mod 4 = 0;                            // forward diagonal: //
    6: Result := (V mod 4 = 2) or (U mod 4 = 2);               // cross
    7: Result := (D = 0) or ((U + V) mod 4 = 0);               // diagonal cross
  else
    Result := False;
  end;
end;

{ ===========================================================================
  DrawFillGlyph  (procedure)
  Parameters:
    ACanvas: TCanvas - the canvas to draw on
    const ARect: TRect
    AChoice: Integer - whole number
    AColor: TColor
  Notes:
    The picture on the Fill button of the property panels, and the swatch of the Color... item:
    a white box with a 1 pixel black outline, with the fill inside.
  =========================================================================== }
procedure DrawFillGlyph(ACanvas: TCanvas; const ARect: TRect; AChoice: Integer; AColor: TColor);
var
  X, Y: Integer;
begin
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := clWhite;
  ACanvas.FillRect(ARect);
  if AChoice = 1 then
  begin
    ACanvas.Brush.Color := AColor;
    ACanvas.FillRect(ARect.Left + 1, ARect.Top + 1, ARect.Right - 1, ARect.Bottom - 1);
  end
  else if AChoice > 1 then
    for Y := ARect.Top + 1 to ARect.Bottom - 2 do
      for X := ARect.Left + 1 to ARect.Right - 2 do
        if FillPixel(AChoice, X - ARect.Left, Y - ARect.Top) then
          ACanvas.Pixels[X, Y] := AColor;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Width := 1;
  ACanvas.Pen.Color := clBlack;
  ACanvas.Rectangle(ARect);
end;

{ TfrmFillDropDown }

{ ===========================================================================
  TfrmFillDropDown.ItemOf  (function)
  Parameters:
    Sender: TObject - the component that raised the event
  Returns:
    Integer
  Notes:
    TODO: describe.
  =========================================================================== }
function TfrmFillDropDown.ItemOf(Sender: TObject): Integer;
var
  P: TObject;
  i: Integer;
begin
  Result := -1;
  P := Sender;
  if (P is TControl) and not (P is TPanel) then
    P := TControl(P).Parent;
  for i := 0 to NumFillMenuItems - 1 do
    if FMenuItems[i] = P then
      Result := i;
end;

{ ===========================================================================
  TfrmFillDropDown.SetSelected  (procedure)
  Parameters:
    AValue: Integer - the value
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfrmFillDropDown.SetSelected(AValue: Integer);
begin
  if AValue < 0 then
    AValue := 0;
  if AValue > NumFillMenuItems - 1 then
    AValue := NumFillMenuItems - 1;
  FSel := AValue;
  ShowSelection;
end;

{ ===========================================================================
  TfrmFillDropDown.ShowSelection  (procedure)
  Parameters:  none
  Notes:
    Paints the highlighted item in the highlight colors and all the others as a menu item.
  =========================================================================== }
procedure TfrmFillDropDown.ShowSelection;
var
  i: Integer;
begin
  for i := 0 to NumFillMenuItems - 1 do
    if FMenuItems[i] <> nil then
      if i = FSel then
      begin
        FMenuItems[i].Color := clMenuHighlight;
        FMenuItems[i].Font.Color := clHighlightText;
      end
      else
      begin
        FMenuItems[i].Color := clMenuBar;
        FMenuItems[i].Font.Color := clMenuText;
      end;
end;

{ ===========================================================================
  TfrmFillDropDown.ShowColorSwatch  (procedure)
  Parameters:  none
  Notes:
    Draws the fill color on imgColor, in the box the Fill button uses (a solid fill).
  =========================================================================== }
procedure TfrmFillDropDown.ShowColorSwatch;
var
  B: TBitmap;
begin
  B := TBitmap.Create;
  try
    B.SetSize(imgColor.Width, imgColor.Height);
    B.Canvas.Brush.Color := clMenuBar;
    B.Canvas.FillRect(0, 0, B.Width, B.Height);
    DrawFillGlyph(B.Canvas, Rect(2, 2, B.Width - 2, B.Height - 2), 1, FColor);
    imgColor.Picture.Assign(B);
  finally
    B.Free;
  end;
end;

{ ===========================================================================
  TfrmFillDropDown.SetFill  (procedure)
  Parameters:
    AChoice: Integer - whole number
    AColor: TColor
  Notes:
    Tell the menu before it is shown: the color is drawn on imgColor, and the item of the style
    is highlighted, where the arrow keys and the wheel start from.
  =========================================================================== }
procedure TfrmFillDropDown.SetFill(AChoice: Integer; AColor: TColor);
begin
  if (AChoice < 0) or (AChoice > 7) then
    AChoice := 0;
  FChoice := AChoice;
  FColor := AColor;
  FSel := 0;
  while (FSel < 7) and (MenuToChoice[FSel] <> AChoice) do
    Inc(FSel);
  ShowColorSwatch;
  ShowSelection;
end;

{ ===========================================================================
  TfrmFillDropDown.MoveSelection  (procedure)
  Parameters:
    ADelta: Integer - whole number
  Notes:
    The wheel and the arrow keys: stops at the first and the last item.
  =========================================================================== }
procedure TfrmFillDropDown.MoveSelection(ADelta: Integer);
begin
  Selected := FSel + ADelta;
end;

{ ===========================================================================
  TfrmFillDropDown.ActivateSelection  (procedure)
  Parameters:  none
  Notes:
    Enter: chooses the highlighted item as a click on it does.
  =========================================================================== }
procedure TfrmFillDropDown.ActivateSelection;
begin
  if FSel = Ord(fmiColor) then
    DoColorSelection(plColor)
  else
    DoFillPattern(FMenuItems[FSel]);
end;

{ ===========================================================================
  TfrmFillDropDown.ColorChosen  (procedure)
  Parameters:
    AColor: TColor
  Notes:
    The fill style stays, except that None becomes Solid (a color for no fill would not show).
    The choice goes to OnPick and the menu closes.
  =========================================================================== }
procedure TfrmFillDropDown.ColorChosen(AColor: TColor);
begin
  FColor := AColor;
  if FChoice = 0 then
    FChoice := 1;
  ShowColorSwatch;
  if Assigned(FOnPick) then
    FOnPick(Self, FChoice, FColor);
  Close;
end;

{ ===========================================================================
  TfrmFillDropDown.DoColorSelection  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Opens the color dialog (shared with the other panels) with the fill color; the menu stays
    open while it is, and a color chosen goes to ColorChosen.
  =========================================================================== }
procedure TfrmFillDropDown.DoColorSelection(Sender: TObject);
begin
  frmSharedControls.DlgColor.Color := FColor;
  BeginKeepOpen;
  try
    if not frmSharedControls.DlgColor.Execute then
      Exit;
  finally
    EndKeepOpen;
  end;
  ColorChosen(frmSharedControls.DlgColor.Color);
end;

{ ===========================================================================
  TfrmFillDropDown.DoFillPattern  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Click on an item (or Enter on it): the style is chosen with the color the menu was told, and
    the menu closes.
  =========================================================================== }
procedure TfrmFillDropDown.DoFillPattern(Sender: TObject);
var
  I: Integer;
begin
  I := ItemOf(Sender);
  if (I < 0) or (I > 7) then
    Exit;
  FSel := I;
  FChoice := MenuToChoice[I];
  if Assigned(FOnPick) then
    FOnPick(Self, FChoice, FColor);
  Close;
end;

{ ===========================================================================
  TfrmFillDropDown.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Lists the items in menu order, and attaches the wheel handler (the keyboard, deactivate and
    hide handling is the base class's).
  =========================================================================== }
procedure TfrmFillDropDown.FormCreate(Sender: TObject);
begin
  FMenuItems[0] := plFillNone;
  FMenuItems[1] := plFill;
  FMenuItems[2] := plVert;
  FMenuItems[3] := plHoriz;
  FMenuItems[4] := plBDiag;
  FMenuItems[5] := plFDiag;
  FMenuItems[6] := plCross;
  FMenuItems[7] := plDCross;
  FMenuItems[8] := plColor;
  FColor := clBlack;
  FChoice := 1;
  FSel := 1;
  OnMouseWheel := @MouseWheel;      // (the controls on the menu have the same handler: the wheel works wherever the pointer is)
  ShowSelection;
end;

{ ===========================================================================
  TfrmFillDropDown.FormShow  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Centers the text of each item on its row and paints the highlight.
  =========================================================================== }
procedure TfrmFillDropDown.FormShow(Sender: TObject);
begin
  lbFillNone.Top := (TPanel(lbFillNone.Parent).Height - lbFillNone.Height) div 2;
  lbFill.Top := (TPanel(lbFill.Parent).Height - lbFill.Height) div 2;
  lbFillVert.Top := (TPanel(lbFillVert.Parent).Height - lbFillVert.Height) div 2;
  lbFillHoriz.Top := (TPanel(lbFillHoriz.Parent).Height - lbFillHoriz.Height) div 2;
  lbFillBDiag.Top := (TPanel(lbFillBDiag.Parent).Height - lbFillBDiag.Height) div 2;
  lbFillFDiag.Top := (TPanel(lbFillFDiag.Parent).Height - lbFillFDiag.Height) div 2;
  lbFillCross.Top := (TPanel(lbFillCross.Parent).Height - lbFillCross.Height) div 2;
  lbFillDCross.Top := (TPanel(lbFillDCross.Parent).Height - lbFillDCross.Height) div 2;
  lbColor.Top := (TPanel(lbColor.Parent).Height - lbColor.Height) div 2;
  ShowSelection;
end;

{ ===========================================================================
  TfrmFillDropDown.MouseEnter  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The pointer moved onto an item: it is the highlighted one now (the keys and the wheel go on
    from there).
  =========================================================================== }
procedure TfrmFillDropDown.MouseEnter(Sender: TObject);
var
  I: Integer;
begin
  I := ItemOf(Sender);
  if I >= 0 then
    Selected := I;
end;

{ ===========================================================================
  TfrmFillDropDown.MouseLeave  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Nothing: the highlight stays on the last item the pointer or a key was on, as in a menu.
  =========================================================================== }
procedure TfrmFillDropDown.MouseLeave(Sender: TObject);
begin
end;

{ ===========================================================================
  TfrmFillDropDown.MouseWheel  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    Shift: TShiftState - modifier keys held down
    WheelDelta: Integer - whole number
    MousePos: TPoint
    var Handled: Boolean - flag (in/out: changed by the call)
  Notes:
    Wheel up moves the highlight to the previous item and stops at the first, wheel down to the
    next and stops at the last.
  =========================================================================== }
procedure TfrmFillDropDown.MouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  if WheelDelta > 0 then
    MoveSelection(-1)
  else if WheelDelta < 0 then
    MoveSelection(1);
  Handled := True;
end;

{ ===========================================================================
  TfrmFillDropDown.HandleKey  (function)
  Parameters:
    var Key: Word - key code (in/out: changed by the call)
    Shift: TShiftState - modifier keys held down
  Returns:
    Boolean
  Notes:
    Up and Down (as the wheel), Home and End (first and last item), Enter and Space (choose the
    highlighted item). Esc closes the menu (the base class).
  =========================================================================== }
function TfrmFillDropDown.HandleKey(var Key: Word; Shift: TShiftState): Boolean;
begin
  Result := True;
  case Key of
    VK_UP: MoveSelection(-1);
    VK_DOWN: MoveSelection(1);
    VK_HOME: Selected := 0;
    VK_END: Selected := NumFillMenuItems - 1;
    VK_RETURN, VK_SPACE: ActivateSelection;
  else
    Result := False;
  end;
end;

end.
