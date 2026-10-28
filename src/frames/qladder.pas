// SPDX-License-Identifier: LGPL-2.1-or-later
unit QLadder;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls, QPropBase, Types, StdCtrls,
  Buttons, Graphics, LCLType, Dialogs, Spin, FSharedCtls, CFontNameCombo;

type

  { TfmLadder }

  TfmLadder = class(TfmPropertyBase)
    cbFont: TFontNameCombo;
    cbLineColor: TColorButton;
    cbFontSize: TComboBox;
    cbFontColor: TColorButton;
    edLeft: TEdit;
    edRight: TEdit;
    lbLeft: TLabel;
    lbRight: TLabel;
    lbWidth: TLabel;
    lbLadder: TLabel;
    lbFont: TLabel;
    plSep1: TPanel;
    plLadder: TPanel;
    plFont: TPanel;
    sbBold: TSpeedButton;
    sbItalic: TSpeedButton;
    seLineWidth: TSpinEdit;
    procedure sbBoldClick(Sender: TObject);
  private

  public
    procedure AfterCreate; override;

  end;

implementation

{$R *.lfm}

procedure TfmLadder.sbBoldClick(Sender: TObject);
begin

end;

{ ===========================================================================
  TfmLadder.AfterCreate  (procedure)
  Parameters:  none
  Notes:
    Frame set-up: hides the caption label and fills the font list with the installed fonts,
    drawn in their own faces.
  =========================================================================== }
procedure TfmLadder.AfterCreate;
begin
  lbCaption.Visible := false;
end;

end.

