// SPDX-License-Identifier: LGPL-2.1-or-later
unit QPropWireLabel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Buttons, ExtCtrls, QPropBase, Types,
  Graphics, LCLType, CFontNameCombo, FSharedCtls;

type

  { TfmPropWireLabel }

  TfmPropWireLabel = class(TfmPropertyBase)
    cbTextDirection: TComboBox;
    cbTextDirection1: TComboBox;
    cbFont: TFontNameCombo;
    cbFontSize: TComboBox;
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
    procedure cbTextDirectionDrawItem(Control: TWinControl; Index: Integer;
      ARect: TRect; State: TOwnerDrawState);
  private
  public
    procedure AfterCreate; override;
  end;

implementation

{$R *.lfm}

{ ===========================================================================
  TfmPropWireLabel.cbTextDirectionChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmPropWireLabel.cbTextDirectionChange(Sender: TObject);
begin

end;

procedure TfmPropWireLabel.cbTextDirectionDrawItem(Control: TWinControl;
  Index: Integer; ARect: TRect; State: TOwnerDrawState);
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
    Img := 8
  else if SameText(S, 'Up') then
    Img := 9
  else if SameText(S, 'Left') then
    Img := 10
  else if SameText(S, 'Right') then
    Img := 11;
  if (Img >= 0) and (frmSharedControls <> nil) and (frmSharedControls.ilFontGlyphs <> nil) then
    frmSharedControls.ilFontGlyphs.ResolutionForPPI[24, Font.PixelsPerInch, 1].Draw(Cv, ARect.Left + (ARect.Right - ARect.Left - 24) div 2,
      ARect.Top + (ARect.Bottom - ARect.Top - 24) div 2, Img)
  else
    Cv.TextOut(ARect.Left + 4, ARect.Top + 4, S);
end;

{ ===========================================================================
  TfmPropWireLabel.AfterCreate  (procedure)
  Parameters:  none
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmPropWireLabel.AfterCreate;
begin
  lbCaption.Visible := false;
end;

end.

