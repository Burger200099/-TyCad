// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Export Image dialog (TinyCAD's CDlgExportPNG, File > Export Image): the kind of picture (colour or black and white PNG, colour or black and white SVG - TinyCAD's
  metafile kinds), the file to write with a Browse button, and for a PNG the scale (1 to 1000 per cent) and whether to turn it a quarter turn. The scale and the turn are
  dimmed for an SVG. Changing the kind changes the extension of the file name. The choices are kept between runs (the registry values TinyCAD uses: BitmapType,
  BitmapScaling and BitmapRotation). The dialog only holds the values; the main form writes the picture.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fexport;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase, UExport, USettings, consts;

type

  { TfrmExportImage }

  TfrmExportImage = class(TfrmBase)
    btnBrowse: TButton;
    cbRotate: TCheckBox;
    cbType: TComboBox;
    edFile: TEdit;
    edScale: TEdit;
    lblFile: TLabel;
    lblNote: TLabel;
    lblScale: TLabel;
    lblType: TLabel;
    lblWhat: TLabel;
    procedure BrowseClick(Sender: TObject);
    procedure CloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure TypeChange(Sender: TObject);
  private
    procedure ExportActivate(Sender: TObject);
    procedure UpdateEnabled;
  public
    { start with the remembered choices and the proposed file name; HasSelection says what will be saved }
    procedure LoadFromSettings(const ADesignFile: String; HasSelection: Boolean);
    { remember the dialog's choices in the program settings (done when OK is pressed) }
    procedure KeepInSettings;
    function FileName: String;
    function Kind: Integer;
    function Scale: Integer;
    function Rotate: Boolean;
    { choose a kind as the list does, which changes the extension of the file name }
    procedure SelectKind(AKind: Integer);
    { the reason OK is refused ('' when the choices will do) }
    function ValidationError: String;
  end;

var
  frmExportImage: TfrmExportImage;

implementation

uses UStrings, FSharedCtls;

{$R *.lfm}

{ ===========================================================================
  TfrmExportImage.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Fills the list of kinds and makes the OK button say Export.
  =========================================================================== }
procedure TfrmExportImage.FormCreate(Sender: TObject);
var
  I: Integer;
begin
  OnActivate := @ExportActivate;
  btnOK.Caption := rsExport;
  cbType.Items.Clear;
  for I := 0 to EXPORT_KIND_COUNT - 1 do cbType.Items.Add(ExportKindName(I));
  cbType.ItemIndex := 0;
end;

{ ===========================================================================
  TfrmExportImage.ExportActivate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Shows the Export and Cancel buttons (the base form's handler would show OK and Cancel).
  =========================================================================== }
procedure TfrmExportImage.ExportActivate(Sender: TObject);
begin
  SetButtons([fcbOK, fcbCancel]);
  btnOK.Caption := rsExport;
end;

{ ===========================================================================
  TfrmExportImage.UpdateEnabled  (procedure)
  Parameters:  none
  Notes:
    The scale and the turn are for a PNG only (CDlgExportPNG::UpdateExtension dims them for a
    metafile).
  =========================================================================== }
procedure TfrmExportImage.UpdateEnabled;
begin
  edScale.Enabled := not ExportKindIsSvg(cbType.ItemIndex);
  lblScale.Enabled := edScale.Enabled;
  cbRotate.Enabled := edScale.Enabled;
end;

{ ===========================================================================
  TfrmExportImage.LoadFromSettings  (procedure)
  Parameters:
    const ADesignFile: String - text
    HasSelection: Boolean - flag
  Notes:
    Fills the dialog as TinyCAD does: the kind, scale and turn last used, and the design's file
    name with the extension of the kind (output.png for a design without a file).
  =========================================================================== }
procedure TfrmExportImage.LoadFromSettings(const ADesignFile: String; HasSelection: Boolean);
begin
  cbType.ItemIndex := ProgramSettings.ExportType;
  edScale.Text := IntToStr(ProgramSettings.ExportScale);
  cbRotate.Checked := ProgramSettings.ExportRotate;
  edFile.Text := ExportDefaultFileName(ADesignFile, cbType.ItemIndex);
  if HasSelection then
    lblWhat.Caption := rsTheSelectedObjectsAreSaved
  else
    lblWhat.Caption := rsTheWholeSheetIsSaved;
  UpdateEnabled;
end;

{ ===========================================================================
  TfrmExportImage.KeepInSettings  (procedure)
  Parameters:  none
  Notes:
    Puts the dialog's choices into the program settings (the caller saves the settings). An
    unusable scale is not kept.
  =========================================================================== }
procedure TfrmExportImage.KeepInSettings;
begin
  ProgramSettings.ExportType := cbType.ItemIndex;
  if (Scale >= EXPORT_MIN_SCALE) and (Scale <= EXPORT_MAX_SCALE) then
    ProgramSettings.ExportScale := Scale;
  ProgramSettings.ExportRotate := cbRotate.Checked;
end;

{ ===========================================================================
  TfrmExportImage.FileName  (function)
  Parameters:  none
  Returns:
    String - the file name
  Notes:
    The file the picture is written to, as typed (without spaces at its ends).
  =========================================================================== }
function TfrmExportImage.FileName: String;
begin
  Result := Trim(edFile.Text);
end;

{ ===========================================================================
  TfrmExportImage.Kind  (function)
  Parameters:  none
  Returns:
    Integer - 0 colour PNG, 1 B&W PNG, 2 colour SVG, 3 B&W SVG
  Notes:
    The kind of picture chosen in the list.
  =========================================================================== }
function TfrmExportImage.Kind: Integer;
begin
  Result := cbType.ItemIndex;
end;

{ ===========================================================================
  TfrmExportImage.Scale  (function)
  Parameters:  none
  Returns:
    Integer - the scale in per cent, 0 when the box holds no whole number
  Notes:
    The scale typed in the Scale box.
  =========================================================================== }
function TfrmExportImage.Scale: Integer;
begin
  Result := StrToIntDef(Trim(edScale.Text), 0);
end;

{ ===========================================================================
  TfrmExportImage.Rotate  (function)
  Parameters:  none
  Returns:
    Boolean - True when a PNG is to be turned a quarter turn
  Notes:
    Whether the Rotate box is ticked.
  =========================================================================== }
function TfrmExportImage.Rotate: Boolean;
begin
  Result := cbRotate.Checked;
end;

{ ===========================================================================
  TfrmExportImage.SelectKind  (procedure)
  Parameters:
    AKind: Integer - whole number
  Notes:
    Chooses a kind as the list does: the extension of the file name follows and the scale and
    turn are dimmed or not.
  =========================================================================== }
procedure TfrmExportImage.SelectKind(AKind: Integer);
begin
  cbType.ItemIndex := AKind;
  TypeChange(nil);
end;

{ ===========================================================================
  TfrmExportImage.TypeChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    OnSelchangeFileType: a file name that has a dot gets the extension of the new kind.
  =========================================================================== }
procedure TfrmExportImage.TypeChange(Sender: TObject);
begin
  edFile.Text := ExportChangeExtension(edFile.Text, cbType.ItemIndex);
  UpdateEnabled;
end;

{ ===========================================================================
  TfrmExportImage.ValidationError  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    There must be a file name, and for a PNG the scale must be a whole number from 1 to 1000
    (DDV_MinMaxInt).
  =========================================================================== }
function TfrmExportImage.ValidationError: String;
begin
  Result := '';
  if FileName = '' then
    Result := rsEnterTheNameOfThe
  else if (not ExportKindIsSvg(cbType.ItemIndex)) and ((Scale < EXPORT_MIN_SCALE) or (Scale > EXPORT_MAX_SCALE)) then
    Result := Format(rsTheScaleMustBeA, [EXPORT_MIN_SCALE, EXPORT_MAX_SCALE]);
end;

{ ===========================================================================
  TfrmExportImage.CloseQuery  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    var CanClose: Boolean - set False to stop the window closing (in/out: changed by the call)
  Notes:
    Pressing Export checks the choices first and keeps the dialog open with a message if they
    are no use.
  =========================================================================== }
procedure TfrmExportImage.CloseQuery(Sender: TObject; var CanClose: Boolean);
var
  Err: String;
begin
  if ModalResult <> mrOK then
    Exit;
  Err := ValidationError;
  if Err <> '' then
  begin
    MessageDlg(rsExportImage, Err, mtWarning, [mbOK], 0);
    CanClose := False;
    ModalResult := mrNone;
  end;
end;

{ ===========================================================================
  TfrmExportImage.BrowseClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Lets the user pick the file to write, offering the extension of the kind chosen (OnBrowse).
  =========================================================================== }
procedure TfrmExportImage.BrowseClick(Sender: TObject);
var
  Ext: String;
begin
  Ext := ExportKindExtension(cbType.ItemIndex);
  if ExportKindIsSvg(cbType.ItemIndex) then
    frmSharedControls.dlgExportSave.Filter := Format(rsVectorDrawingAllFiles, [Ext, Ext])
  else
    frmSharedControls.dlgExportSave.Filter := Format(rsBitmapAllFiles, [Ext, Ext]);
  frmSharedControls.dlgExportSave.DefaultExt := Copy(Ext, 2, MaxInt);
  frmSharedControls.dlgExportSave.FileName := edFile.Text;
  if frmSharedControls.dlgExportSave.Execute then
    edFile.Text := frmSharedControls.dlgExportSave.FileName;
end;

end.
