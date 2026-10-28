// SPDX-License-Identifier: LGPL-2.1-or-later
unit FDetailsDropDown;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  FDropDownBase;

type

  { TfrmDesignDetailsDropDown }

  TfrmDesignDetailsDropDown = class(TfrmDropDownBase)
    cbSheetDetailsBorder: TCheckBox;
    cbSheetDetailsShowRuler: TCheckBox;
    edSheetDetailsCols: TEdit;
    edSheetDetailsMargin: TEdit;
    edSheetDetailsRows: TEdit;
    lbSheetDetailsCols: TLabel;
    lbSheetDetailsMargin: TLabel;
    lbSheetDetailsRows: TLabel;
    Panel1: TPanel;
  private

  public

  end;

var
  frmDesignDetailsDropDown: TfrmDesignDetailsDropDown;

implementation

{$R *.lfm}

end.

