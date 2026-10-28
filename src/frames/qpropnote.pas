// SPDX-License-Identifier: LGPL-2.1-or-later
unit QPropNote;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, QPropText, Types, StdCtrls, Dialogs,
  ExtCtrls, Spin, Graphics, LCLType, Buttons, FSharedCtls, CFontNameCombo;

type

  { TfmPropNote }

  TfmPropNote = class(TfmPropText)
    bbFill: TSpeedButton;
    cbTextColor1: TColorButton;
    cbWireType: TComboBox;
    lbStyle: TLabel;
    lbWidth: TLabel;
    lbFrameColor: TLabel;
    lbNote: TLabel;
    pnlNote: TPanel;
    pnlSep2: TPanel;
    seFrameWidth: TSpinEdit;
    procedure DrawWireTypeItems(Control: TWinControl; Index: Integer; ARect: TRect;
      State: TOwnerDrawState);
  private

  public
    procedure AfterCreate; override;

  end;

implementation

{$R *.lfm}

{ ===========================================================================
  TfmPropNote.DrawWireTypeItems  (procedure)
  Parameters:
    Control: TWinControl
    Index: Integer - zero-based index
    ARect: TRect
    State: TOwnerDrawState
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmPropNote.DrawWireTypeItems(Control: TWinControl; Index: Integer;
  ARect: TRect; State: TOwnerDrawState);
var
  X, Y: Integer;
  C: TCanvas;
begin
  if not (Control is TComboBox) then
    Exit;

  C := TComboBox(Control).Canvas;

  if odSelected in State then
  begin
    C.Brush.Color := clHighlight;
    C.Font.Color := clHighlightText;
  end
  else
  begin
    C.Brush.Color := clWindow;
    C.Font.Color := clWindowText;
  end;

  C.FillRect(ARect);

  if (Index >= 0) and (Index < frmSharedControls.ilListBoxImages.Count) then
  begin
    X := ARect.Left +
      ((ARect.Right - ARect.Left) - frmSharedControls.ilListBoxImages.Width) div 2;

    Y := ARect.Top +
      ((ARect.Bottom - ARect.Top) - frmSharedControls.ilListBoxImages.Height) div 2;

    frmSharedControls.ilListBoxImages.Draw(C, X, Y, Index, True);
  end;
end;

{ ===========================================================================
  TfmPropNote.AfterCreate  (procedure)
  Parameters:  none
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmPropNote.AfterCreate;
begin
  inherited;
end;

end.

