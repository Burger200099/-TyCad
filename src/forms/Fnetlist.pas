{ The PCB Export dialog (TinyCAD's CDlgPCBExport, Special > Create PCB Net List): the file format (TinyCAD, PADS-PCB, PADS-PCB-WITH-VALUE, Eagle SCR,
  Protel, gEDA PCB, XML), the file to write with a Browse button and the sheet-number prefix choice. Changing the format changes the
  extension of the file name (.net, .scr or .net.xml). The choices are kept between runs (the registry values TinyCAD uses: Netlist and
  PrefixNetlist). The dialog only holds the values; the main form writes the netlist.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fnetlist;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase, UNetWriters, USettings, consts;

type

  { TfrmNetlist }

  TfrmNetlist = class(TfrmBase)
    btnBrowse: TButton;
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
    procedure NetActivate(Sender: TObject);
  public
    { start with the remembered choices and the proposed file name }
    procedure LoadFromSettings(const ADesignFile: String);
    { remember the dialog's choices in the program settings (done when Export is pressed) }
    procedure KeepInSettings;
    function FileName: String;
    function Format: Integer;
    { choose a format as the list does, which changes the extension of the file name }
    procedure SelectType(AType: Integer);
  end;

var
  frmNetlist: TfrmNetlist;

implementation


uses UStrings;

{$R *.lfm}

{ ===========================================================================
  TfrmNetlist.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Fills the list of formats and makes the OK button say Export.
  =========================================================================== }
procedure TfrmNetlist.FormCreate(Sender: TObject);
var
  i: Integer;
begin
  OnActivate := @NetActivate;
  btnOK.Caption := rsExport;
  cbType.Items.Clear;
  for i := 0 to NETFMT_COUNT - 1 do cbType.Items.Add(NetListFormatName(i));
  cbType.ItemIndex := 0;
end;

{ ===========================================================================
  TfrmNetlist.NetActivate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Shows the Export and Cancel buttons (the base form's handler would show OK and Cancel).
  =========================================================================== }
procedure TfrmNetlist.NetActivate(Sender: TObject);
begin
  SetButtons([fcbOK, fcbCancel]);
  btnOK.Caption := rsExport;
end;

{ ===========================================================================
  TfrmNetlist.LoadFromSettings  (procedure)
  Parameters:
    const ADesignFile: String - text
  Notes:
    Fills the dialog as TinyCAD does: the format and prefix choice last used, and the design's
    file name with .net (or output.net for a design without a file), then the extension of the
    format.
  =========================================================================== }
procedure TfrmNetlist.LoadFromSettings(const ADesignFile: String);
begin
  cbType.ItemIndex := ProgramSettings.NetType;
  cbPrefix.Checked := ProgramSettings.NetPrefix;
  edFile.Text := NetListDefaultFileName(ADesignFile);
  TypeChange(nil);
end;

{ ===========================================================================
  TfrmNetlist.KeepInSettings  (procedure)
  Parameters:  none
  Notes:
    Puts the dialog's choices into the program settings (the caller saves the settings).
  =========================================================================== }
procedure TfrmNetlist.KeepInSettings;
begin
  ProgramSettings.NetType := cbType.ItemIndex;
  ProgramSettings.NetPrefix := cbPrefix.Checked;
end;

{ ===========================================================================
  TfrmNetlist.FileName  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    The file to write.
  =========================================================================== }
function TfrmNetlist.FileName: String;
begin
  Result := edFile.Text;
end;

{ ===========================================================================
  TfrmNetlist.Format  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    The format chosen.
  =========================================================================== }
function TfrmNetlist.Format: Integer;
begin
  Result := cbType.ItemIndex;
end;

{ ===========================================================================
  TfrmNetlist.SelectType  (procedure)
  Parameters:
    AType: Integer - whole number
  Notes:
    Chooses a format, which changes the extension of the file name as choosing it in the list
    does.
  =========================================================================== }
procedure TfrmNetlist.SelectType(AType: Integer);
begin
  cbType.ItemIndex := AType;
  TypeChange(nil);
end;

{ ===========================================================================
  TfrmNetlist.TypeChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    OnSelchangeFileType: a file name that has a dot gets the extension of the new format.
  =========================================================================== }
procedure TfrmNetlist.TypeChange(Sender: TObject);
begin
  edFile.Text := NetListChangeExtension(edFile.Text, cbType.ItemIndex);
end;

{ ===========================================================================
  TfrmNetlist.BrowseClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Lets the user pick the file to write, offering the extension of the format chosen.
  =========================================================================== }
procedure TfrmNetlist.BrowseClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  Ext: String;
begin
  Ext := NetListExtension(cbType.ItemIndex);
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := SysUtils.Format(rsNetlistAllFiles, [Ext, Ext]);
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
