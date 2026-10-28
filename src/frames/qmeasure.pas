// SPDX-License-Identifier: LGPL-2.1-or-later
unit QMeasure;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls, QPropBase, Types, StdCtrls,
  Buttons, Graphics, LCLType, Dialogs, Spin, FSharedCtls, CFontNameCombo;

type

  { TfmMeasure }

  TfmMeasure = class(TfmPropertyBase)
    cbFont: TFontNameCombo;
    cbLineColor: TColorButton;
    cbFontSize: TComboBox;
    cbFontColor: TColorButton;
    cbUnits: TComboBox;
    cbGrads: TCheckBox;
    lbUnits: TLabel;
    lbWidth: TLabel;
    lbMeasure: TLabel;
    lbFont: TLabel;
    plSep1: TPanel;
    plMeasure: TPanel;
    plFont: TPanel;
    sbBold: TSpeedButton;
    sbItalic: TSpeedButton;
    seLineWidth: TSpinEdit;
  private

  public
    procedure AfterCreate; override;

  end;

implementation

{$R *.lfm}

{ ===========================================================================
  TfmMeasure.AfterCreate  (procedure)
  Parameters:  none
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmMeasure.AfterCreate;
begin
  lbCaption.Visible := false;
end;

end.

