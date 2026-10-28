// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Save a Parts List dialog (TinyCAD's CDlgBOMExport): the file format (text, CSV, or CSV for a spreadsheet), the file to write
  with a Browse button, and four choices - all sheets, hierarchical links, all attribute information, and the sheet-number prefix.
  Changing the format changes the extension of the file name. The choices are remembered between runs (the registry values
  TinyCAD uses: BOMNetlist, BOMHierarchical, BOMPrefixNetlist, BOMAllSheets, BOMAllAttrs). The dialog only holds the values;
  the main form writes the list.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fpartslist;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase, UPartsList, USettings, consts;

type

  { TfrmPartsList }

  TfrmPartsList = class(TfrmBase)
    btnBrowse: TButton;
    cbAllSheets: TCheckBox;
    cbAttrs: TCheckBox;
    cbHier: TCheckBox;
    cbPrefix: TCheckBox;
    cbType: TComboBox;
    edFile: TEdit;
    lblFile: TLabel;
    lblFormat: TLabel;
    lblNote: TLabel;
    lblTitle: TLabel;
    procedure BrowseClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure TypeChange(Sender: TObject);
  private
    procedure PartsActivate(Sender: TObject);
  public
    { start with the remembered choices and the proposed file name }
    procedure LoadFromSettings(const ADesignFile: String);
    { remember the dialog's choices in the program settings (done when OK is pressed) }
    procedure KeepInSettings;
    function Options: TBomOptions;
    function FileName: String;
    { choose a format as the list does, which changes the extension of the file name }
    procedure SelectType(AType: Integer);
  end;

var
  frmPartsList: TfrmPartsList;

implementation


uses UStrings;

{$R *.lfm}

{ ===========================================================================
  TfrmPartsList.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Fills the list of formats and makes the OK button say Export.
  =========================================================================== }
procedure TfrmPartsList.FormCreate(Sender: TObject);
begin
  OnActivate := @PartsActivate;
  btnOK.Caption := rsExport;
  cbType.Items.Clear;
  cbType.Items.Add(rsTextFile);
  cbType.Items.Add(rsCSVFile);
  cbType.Items.Add(rsSpreadsheetCompatibleCSVFile);
  cbType.ItemIndex := 0;
end;

{ ===========================================================================
  TfrmPartsList.PartsActivate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Shows the Export and Cancel buttons (the base form's handler would show OK and Cancel).
  =========================================================================== }
procedure TfrmPartsList.PartsActivate(Sender: TObject);
begin
  SetButtons([fcbOK, fcbCancel]);
  btnOK.Caption := rsExport;
end;

{ ===========================================================================
  TfrmPartsList.LoadFromSettings  (procedure)
  Parameters:
    const ADesignFile: String - text
  Notes:
    Fills the dialog as TinyCAD's constructor and OnInitDialog do: the choices last used, and
    the design's file name with .txt (or output.txt for a design without a file), then the
    extension of the format that was last used.
  =========================================================================== }
procedure TfrmPartsList.LoadFromSettings(const ADesignFile: String);
begin
  cbType.ItemIndex := ProgramSettings.BomType;
  cbAllSheets.Checked := ProgramSettings.BomAllSheets;
  cbAttrs.Checked := ProgramSettings.BomAllAttrs;
  cbHier.Checked := ProgramSettings.BomHierarchical;
  cbPrefix.Checked := ProgramSettings.BomPrefix;
  edFile.Text := BomDefaultFileName(ADesignFile);
  TypeChange(nil);
end;

{ ===========================================================================
  TfrmPartsList.KeepInSettings  (procedure)
  Parameters:  none
  Notes:
    Puts the dialog's choices into the program settings, as TinyCAD's OnOK stores them in the
    registry (the caller saves the settings).
  =========================================================================== }
procedure TfrmPartsList.KeepInSettings;
begin
  ProgramSettings.BomType := cbType.ItemIndex;
  ProgramSettings.BomAllSheets := cbAllSheets.Checked;
  ProgramSettings.BomAllAttrs := cbAttrs.Checked;
  ProgramSettings.BomHierarchical := cbHier.Checked;
  ProgramSettings.BomPrefix := cbPrefix.Checked;
end;

{ ===========================================================================
  TfrmPartsList.Options  (function)
  Parameters:  none
  Returns:
    TBomOptions
  Notes:
    The choices as the generator takes them.
  =========================================================================== }
function TfrmPartsList.Options: TBomOptions;
begin
  Result.FileType := cbType.ItemIndex;
  Result.AllSheets := cbAllSheets.Checked;
  Result.AllAttrs := cbAttrs.Checked;
  Result.Hierarchical := cbHier.Checked;
  Result.PrefixSheet := cbPrefix.Checked;
  Result.PartColumns := True;      // (the columns only appear when the design has parts of a parts library)
end;

{ ===========================================================================
  TfrmPartsList.FileName  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    The file to write.
  =========================================================================== }
function TfrmPartsList.FileName: String;
begin
  Result := edFile.Text;
end;

{ ===========================================================================
  TfrmPartsList.SelectType  (procedure)
  Parameters:
    AType: Integer - whole number
  Notes:
    Chooses a format, which changes the extension of the file name as choosing it in the list
    does.
  =========================================================================== }
procedure TfrmPartsList.SelectType(AType: Integer);
begin
  cbType.ItemIndex := AType;
  TypeChange(nil);
end;

{ ===========================================================================
  TfrmPartsList.TypeChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    OnSelchangeFileType: a file name that has a dot gets the extension of the new format.
  =========================================================================== }
procedure TfrmPartsList.TypeChange(Sender: TObject);
begin
  edFile.Text := BomChangeExtension(edFile.Text, cbType.ItemIndex);
end;

{ ===========================================================================
  TfrmPartsList.BrowseClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Lets the user pick the file to write, offering the extension of the format chosen.
  =========================================================================== }
procedure TfrmPartsList.BrowseClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  Ext: String;
begin
  Ext := BomExtension(cbType.ItemIndex);
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := Format(rsPartsListAllFiles, [Ext, Ext]);
    Dlg.DefaultExt := Copy(Ext, 2, MaxInt);
    Dlg.FileName := edFile.Text;
    Dlg.Options := Dlg.Options + [ofHideReadOnly, ofOverwritePrompt];
    if Dlg.Execute then
      edFile.Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

end.
