// SPDX-License-Identifier: LGPL-2.1-or-later
unit QPropWire;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Dialogs, Spin, StdCtrls, QPropBase, Types, Graphics,
  LCLType, FSharedCtls, UEdit, UProps;

type

  { TfmPropRibbonWire }

  TfmPropRibbonWire = class(TfmPropertyBase)
    cbWireColor: TColorButton;
    cbWireType: TComboBox;
    cbAngle: TComboBox;
    lbSize: TLabel;
    seWireSize: TSpinEdit;
    procedure cbWireTypeChange(Sender: TObject);
    procedure DrawWireChange(Sender: TObject);
    procedure DrawWireTypeItems(Control: TWinControl; Index: Integer;
      ARect: TRect; State: TOwnerDrawState);
  private

  public
    procedure AfterCreate; override;

  end;

implementation

{$R *.lfm}

{ ===========================================================================
  TfmPropRibbonWire.DrawWireTypeItems  (procedure)
  Parameters:
    Control: TWinControl
    Index: Integer - zero-based index
    ARect: TRect
    State: TOwnerDrawState
  Notes:
    TfmPropRibbonWire
  =========================================================================== }
procedure TfmPropRibbonWire.DrawWireTypeItems(Control: TWinControl;
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
  TfmPropRibbonWire.cbWireTypeChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmPropRibbonWire.cbWireTypeChange(Sender: TObject);
begin

end;

{ ===========================================================================
  TfmPropRibbonWire.DrawWireChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmPropRibbonWire.DrawWireChange(Sender: TObject);
begin

end;

{ ===========================================================================
  TfmPropRibbonWire.AfterCreate  (procedure)
  Parameters:  none
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmPropRibbonWire.AfterCreate;
var i: integer;
begin
  cbWireType.Items.Clear;
  for i := 0 to frmSharedControls.ilListBoxImages.Count - 1 do
    cbWireType.Items.Add('');
  { the angle list: one item for each way of drawing (UProps.AngleChoices, in the order of UEdit.TAngleMode) }
  cbAngle.Items.Clear;
  for i := 0 to ChoiceCount(AngleChoices) - 1 do
    cbAngle.Items.Add(ChoiceText(AngleChoices, i));
  cbAngle.ItemIndex := 0;
end;

end.

