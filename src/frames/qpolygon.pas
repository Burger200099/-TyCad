// SPDX-License-Identifier: LGPL-2.1-or-later
unit QPolygon;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Dialogs, StdCtrls, Buttons, Spin,
  QPropBase, Types, Graphics, LCLType, FSharedCtls;

type

  { TfmPolygon }

  TfmPolygon = class(TfmPropertyBase)
    bbFill: TSpeedButton;
    cbWireColor: TColorButton;
    cbClosed: TCheckBox;
    cbWireType: TComboBox;
    lbWidth: TLabel;
    seWidth: TSpinEdit;
    procedure DrawWireTypeItems(Control: TWinControl; Index: Integer;
      ARect: TRect; State: TOwnerDrawState);
    procedure FrameClick(Sender: TObject);
  private

  public

  end;

implementation

{$R *.lfm}

{ ===========================================================================
  TfmPolygon.FrameClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TfmPolygon
  =========================================================================== }
procedure TfmPolygon.FrameClick(Sender: TObject);
begin

end;

{ ===========================================================================
  TfmPolygon.DrawWireTypeItems  (procedure)
  Parameters:
    Control: TWinControl
    Index: Integer - zero-based index
    ARect: TRect
    State: TOwnerDrawState
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmPolygon.DrawWireTypeItems(Control: TWinControl; Index: Integer;
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

end.

