// SPDX-License-Identifier: LGPL-2.1-or-later
unit QRungs;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls, QPropBase, Types, StdCtrls,
  Buttons, Graphics, LCLType, Dialogs, Spin, FSharedCtls, CFontNameCombo;

type

  { TfmRungs }

  TfmRungs = class(TfmPropertyBase)
    cbFont: TFontNameCombo;
    cbFontSize: TComboBox;
    cbFontColor: TColorButton;
    cbPages: TComboBox;
    cbContinue: TCheckBox;
    cbShowHeight: TCheckBox;
    fseMargin: TFloatSpinEdit;
    seRows: TSpinEdit;
    seStart: TSpinEdit;
    lbRows: TLabel;
    lbStart: TLabel;
    lbMargin: TLabel;
    lbRungs: TLabel;
    lbFont: TLabel;
    plSep1: TPanel;
    plRungs: TPanel;
    plFont: TPanel;
    sbBold: TSpeedButton;
    sbItalic: TSpeedButton;
  private

  public
    procedure AfterCreate; override;

  end;

implementation

{$R *.lfm}

{ ===========================================================================
  TfmRungs.AfterCreate  (procedure)
  Parameters:  none
  Notes:
    Frame set-up: hides the caption label and fills the font list with the installed fonts,
    drawn in their own faces.
  =========================================================================== }
procedure TfmRungs.AfterCreate;
begin
  lbCaption.Visible := false;
end;

end.

