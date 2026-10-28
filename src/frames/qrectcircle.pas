// SPDX-License-Identifier: LGPL-2.1-or-later
unit QRectCircle;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Dialogs, StdCtrls, QPropWire, Types,
  Graphics, LCLType, Buttons, FSharedCtls;

type

  { TfmRectCircle }

  TfmRectCircle = class(TfmPropRibbonWire)
    sbFill: TSpeedButton;
    procedure WireTypeChange(Sender: TObject);
    procedure WireTypeDrawItem(Control: TWinControl; Index: Integer;
      ARect: TRect; State: TOwnerDrawState);
  private
  public
    procedure AfterCreate; override;

  end;

implementation

{$R *.lfm}

{ ===========================================================================
  TfmRectCircle.WireTypeDrawItem  (procedure)
  Parameters:
    Control: TWinControl
    Index: Integer - zero-based index
    ARect: TRect
    State: TOwnerDrawState
  Notes:
    TfmRectCircle
  =========================================================================== }
procedure TfmRectCircle.WireTypeDrawItem(Control: TWinControl;
  Index: Integer; ARect: TRect; State: TOwnerDrawState);
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
  TfmRectCircle.WireTypeChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmRectCircle.WireTypeChange(Sender: TObject);
begin

end;

{ ===========================================================================
  TfmRectCircle.AfterCreate  (procedure)
  Parameters:  none
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmRectCircle.AfterCreate;
begin
  inherited;
end;

end.

