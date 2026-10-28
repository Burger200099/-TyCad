// SPDX-License-Identifier: LGPL-2.1-or-later
unit FSharedCtls;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, PrintersDlgs, ImgList;

type

  { TfrmSharedControls }

  TfrmSharedControls = class(TForm)
    DlgColor: TColorDialog;
    ilFillStyles: TImageList;
    ilSheetTabs: TImageList;
    ilDocTabs: TImageList;
    OpenDlg: TOpenDialog;
    SaveDlg: TSaveDialog;
    PrintDlg: TPrintDialog;
    dlgPrinterSetup: TPrinterSetupDialog;
    dlgPageSetup: TPageSetupDialog;
    ilSpeedBtn: TImageList;
    ReplaceDlg: TReplaceDialog;
    ilTinyIcons: TImageList;
    dlgExportSave: TSaveDialog;
    dlgLibAdd: TOpenDialog;
    dlgLibNew: TSaveDialog;
    ilNewDocument: TImageList;
    ilListBoxImages: TImageList;
    ilPowerGlyph: TImageList;
    ilFontGlyphs: TImageList;
    procedure FormCreate(Sender: TObject);
  private

  public

  end;

var
  frmSharedControls: TfrmSharedControls;

implementation

{$R *.lfm}

{ TfrmSharedControls }

procedure TfrmSharedControls.FormCreate(Sender: TObject);
begin

end;

initialization
  RegisterClasses([TPrintDialog, TPrinterSetupDialog, TPageSetupDialog]);

end.

