unit QPowerSym;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Buttons, QPropBase, Types,
  Graphics, LCLType, FSharedCtls;

type

  { TfmPower }

  TfmPower = class(TfmPropertyBase)
    cbTextDirection: TComboBox;
    edText: TEdit;
    lbType: TLabel;
    sbOrientation: TSpeedButton;
    procedure ChangeOrientation(Sender: TObject);
    procedure DrawType(Control: TWinControl; Index: Integer; ARect: TRect;
      State: TOwnerDrawState);
  private
    FOrientation: byte;

  public
    procedure AfterCreate; override;

  end;

implementation

{$R *.lfm}

{ ===========================================================================
  TfmPower.DrawType  (procedure)
  Parameters:
    Control: TWinControl
    Index: Integer - zero-based index
    ARect: TRect
    State: TOwnerDrawState
  Notes:
    TfmPower
  =========================================================================== }
procedure TfmPower.DrawType(Control: TWinControl; Index: Integer; ARect: TRect;
  State: TOwnerDrawState);
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

//  if (Index >= 0) and (Index < ilPowerGlyph.Count) then
  begin
    X := ARect.Left +
      ((ARect.Right - ARect.Left) - frmSharedControls.ilPowerGlyph.Width) div 2;

    Y := ARect.Top +
      ((ARect.Bottom - ARect.Top) - frmSharedControls.ilPowerGlyph.Height) div 2;

    frmSharedControls.ilPowerGlyph.Draw(C, X, Y, Index, True);
  end;
end;

{ ===========================================================================
  TfmPower.AfterCreate  (procedure)
  Parameters:  none
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmPower.AfterCreate;
begin
  FOrientation := 0;  // 0 up 1 right 2 down 3 left
end;

{ ===========================================================================
  TfmPower.ChangeOrientation  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmPower.ChangeOrientation(Sender: TObject);
begin
  if FOrientation = 3 then
    FOrientation := 0
  else
    inc(FOrientation);
  sbOrientation.ImageIndex := FOrientation + 5;
end;

end.

