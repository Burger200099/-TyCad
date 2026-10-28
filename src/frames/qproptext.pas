unit QPropText;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Buttons, ExtCtrls, QPropBase, Types,
  Graphics, LCLType, Dialogs, FSharedCtls, CFontNameCombo;

type

  { TfmPropText }

  TfmPropText = class(TfmPropertyBase)
    cbTextDirection: TComboBox;
    cbTextDirection1: TComboBox;
    cbFont: TFontNameCombo;
    cbFontSize: TComboBox;
    cbTextColor: TColorButton;
    edText: TEdit;
    lbFont: TLabel;
    lbWire: TLabel;
    lbDirection: TLabel;
    lbType: TLabel;
    lbSep1: TPanel;
    plFont: TPanel;
    plText: TPanel;
    sbBold: TSpeedButton;
    sbItalic: TSpeedButton;
    procedure cbTextDirectionChange(Sender: TObject);
    procedure cbTextDirectionDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
    procedure sbBoldClick(Sender: TObject);
  private
  public
    procedure AfterCreate; override;
  end;

implementation

{$R *.lfm}

{ ===========================================================================
  TfmPropText.sbBoldClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmPropText.sbBoldClick(Sender: TObject);
begin

end;

{ ===========================================================================
  TfmPropText.cbTextDirectionChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmPropText.cbTextDirectionChange(Sender: TObject);
begin

end;

{ ===========================================================================
  TfmPropText.cbTextDirectionDrawItem  (procedure)
  Parameters:
    Control: TWinControl - the direction box
    Index: Integer - the row (-1 or the chosen one for the box itself)
    ARect: TRect - where to draw
    State: TOwnerDrawState - selected, in the edit part and so on
  Notes:
    Draws the direction as a picture, 24 pixels wide, from frmSharedControls.ilFontGlyphs: image 4 text running down, 5 up, 6 left, 7 right; the rows are named Up,
    Down, Left and Right and are found by name. The selected row uses the highlight colors. Falls back to the plain name when the glyph list is not there.
  =========================================================================== }
procedure TfmPropText.cbTextDirectionDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
var
  Img: Integer;
  Cv: TCanvas;
  S: String;
begin
  Cv := cbTextDirection.Canvas;
  if odSelected in State then
  begin
    Cv.Brush.Color := clHighlight;
    Cv.Font.Color := clHighlightText;
  end
  else
  begin
    Cv.Brush.Color := clWindow;
    Cv.Font.Color := clWindowText;
  end;
  Cv.FillRect(ARect);
  if (Index < 0) or (Index >= cbTextDirection.Items.Count) then
    Exit;
  S := cbTextDirection.Items[Index];
  Img := -1;
  if SameText(S, 'Down') then
    Img := 4
  else if SameText(S, 'Up') then
    Img := 5
  else if SameText(S, 'Left') then
    Img := 6
  else if SameText(S, 'Right') then
    Img := 7;
  if (Img >= 0) and (frmSharedControls <> nil) and (frmSharedControls.ilFontGlyphs <> nil) then
    frmSharedControls.ilFontGlyphs.ResolutionForPPI[24, Font.PixelsPerInch, 1].Draw(Cv, ARect.Left + (ARect.Right - ARect.Left - 24) div 2,
      ARect.Top + (ARect.Bottom - ARect.Top - 24) div 2, Img)
  else
    Cv.TextOut(ARect.Left + 4, ARect.Top + 4, S);
end;

{ ===========================================================================
  TfmPropText.AfterCreate  (procedure)
  Parameters:  none
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmPropText.AfterCreate;
begin
  lbCaption.Visible := false;
end;

end.

