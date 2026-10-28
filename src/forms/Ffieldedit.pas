// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Field dialog of the parts library editor: one field declared by a part class (name, type, unit, the values of an enum, whether parts must have it and a
  description). Subclasses inherit the field.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Ffieldedit;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase, UPartsDb;

type

  { TfrmFieldEdit }

  TfrmFieldEdit = class(TfrmBase)
    cbType: TComboBox;
    chRequired: TCheckBox;
    edDescription: TEdit;
    edEnum: TEdit;
    edName: TEdit;
    edUnit: TEdit;
    lblDescription: TLabel;
    lblEnum: TLabel;
    lblName: TLabel;
    lblType: TLabel;
    lblUnit: TLabel;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure TypeChange(Sender: TObject);
  public
    { the entries of a new field, or of the field to change }
    procedure Setup(const AField: TFieldInfo; ANew: Boolean);
    function Valid: Boolean;
    function FieldName: String;
    function FieldType: String;
    function FieldUnit: String;
    function FieldEnum: String;
    function FieldRequired: Boolean;
    function FieldDescription: String;
  end;

implementation


uses UStrings;

{$R *.lfm}

{ ===========================================================================
  TfrmFieldEdit.Setup  (procedure)
  Parameters:
    const AField: TFieldInfo - the field (ignored for a new one)
    ANew: Boolean - True to add a field
  Notes:
    Fills the entries; the values box is available for an enum only.
  =========================================================================== }
procedure TfrmFieldEdit.Setup(const AField: TFieldInfo; ANew: Boolean);
begin
  if ANew then
  begin
    edName.Text := '';
    cbType.ItemIndex := 0;
    Caption := rsAddField;
  end
  else
  begin
    edName.Text := AField.Name;
    cbType.ItemIndex := cbType.Items.IndexOf(AField.FieldType);
    edUnit.Text := AField.Unit_;
    edEnum.Text := AField.EnumValues;
    chRequired.Checked := AField.Required;
    edDescription.Text := AField.Description;
    Caption := rsFieldProperties;
  end;
  TypeChange(nil);
end;

function TfrmFieldEdit.Valid: Boolean;
begin
  Result := (Trim(edName.Text) <> '') and (cbType.ItemIndex >= 0) and ((cbType.Text <> 'enum') or (Trim(edEnum.Text) <> ''));
end;

function TfrmFieldEdit.FieldName: String;
begin
  Result := Trim(edName.Text);
end;

function TfrmFieldEdit.FieldType: String;
begin
  Result := cbType.Text;
end;

function TfrmFieldEdit.FieldUnit: String;
begin
  Result := Trim(edUnit.Text);
end;

function TfrmFieldEdit.FieldEnum: String;
begin
  Result := '';
  if cbType.Text = 'enum' then
    Result := Trim(edEnum.Text);
end;

function TfrmFieldEdit.FieldRequired: Boolean;
begin
  Result := chRequired.Checked;
end;

function TfrmFieldEdit.FieldDescription: String;
begin
  Result := edDescription.Text;
end;

procedure TfrmFieldEdit.TypeChange(Sender: TObject);
begin
  edEnum.Enabled := cbType.Text = 'enum';
  lblEnum.Enabled := edEnum.Enabled;
end;

procedure TfrmFieldEdit.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if ModalResult <> mrOK then
    Exit;
  if not Valid then
  begin
    if Trim(edName.Text) = '' then
      MessageDlg(rsField, rsTheFieldNeedsAName, mtWarning, [mbOK], 0)
    else
      MessageDlg(rsField, rsAnEnumFieldNeedsIts, mtWarning, [mbOK], 0);
    CanClose := False;
  end;
end;

end.
