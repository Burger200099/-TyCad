// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Part dialog of the parts library editor: name, class, reference letters, status and description of one generic part. It is used to add a part (the class
  is chosen here) and to change one (the class is shown but cannot be changed: values and child objects belong to the class). OK is refused while the name is empty.
  Setup fills it from a parts library; the properties give the entries back.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fpartedit;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase, UPartsDb;

type

  { TfrmPartEdit }

  TfrmPartEdit = class(TfrmBase)
    cbClass: TComboBox;
    cbStatus: TComboBox;
    edDescription: TEdit;
    edName: TEdit;
    edRef: TEdit;
    lblClass: TLabel;
    lblDescription: TLabel;
    lblName: TLabel;
    lblRef: TLabel;
    lblStatus: TLabel;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    function GetClassID: Int64;
    function GetPartName: String;
    function GetRefPrefix: String;
    function GetDescription: String;
    function GetStatus: String;
  public
    { fills the dialog: the classes that can hold parts (path from the root, as 'Part > PassivePart > Relay'); with APart >= 0 the dialog edits that part (class fixed) }
    procedure Setup(ALib: TPartsLibrary; APart: Integer);
    { true when the entries can be used: a name and a class }
    function Valid: Boolean;
    property PartName: String read GetPartName;
    property ClassID: Int64 read GetClassID;
    property RefPrefix: String read GetRefPrefix;
    property Description: String read GetDescription;
    property Status: String read GetStatus;
  end;

implementation


uses UStrings;

{$R *.lfm}

{ ===========================================================================
  TfrmPartEdit.Setup  (procedure)
  Parameters:
    ALib: TPartsLibrary - the open parts library
    APart: Integer - index in ALib.Parts of the part to change, -1 for a new part
  Notes:
    Lists the classes that are not abstract (the path from the root, sorted) in the class box. A new part starts empty with status "active"; a part to change shows its
    entries and the class box is dimmed.
  =========================================================================== }
procedure TfrmPartEdit.Setup(ALib: TPartsLibrary; APart: Integer);
var
  i, k, At: Integer;
  Path: String;
  List: TStringList;
  function ClassPath(Idx: Integer): String;
  var
    j, Guard: Integer;
  begin
    Result := ALib.Classes[Idx].Name;
    Guard := 0;
    while (ALib.Classes[Idx].ParentID <> 0) and (Guard < 50) do
    begin
      At := -1;
      for j := 0 to ALib.ClassCount - 1 do
        if ALib.Classes[j].ID = ALib.Classes[Idx].ParentID then
          At := j;
      if At < 0 then
        Break;
      Idx := At;
      Result := ALib.Classes[Idx].Name + ' > ' + Result;
      Inc(Guard);
    end;
  end;
begin
  List := TStringList.Create;
  try
    for i := 0 to ALib.ClassCount - 1 do
      if not ALib.Classes[i].Abstract then
        List.AddObject(ClassPath(i), TObject(PtrInt(ALib.Classes[i].ID)));
    List.Sort;
    cbClass.Items.Clear;
    for k := 0 to List.Count - 1 do
      cbClass.Items.AddObject(List[k], List.Objects[k]);
  finally
    List.Free;
  end;
  cbStatus.ItemIndex := 0;
  if APart >= 0 then
  begin
    edName.Text := ALib.Parts[APart].Name;
    edRef.Text := ALib.Parts[APart].RefPrefix;
    edDescription.Text := ALib.Parts[APart].Description;
    cbStatus.ItemIndex := cbStatus.Items.IndexOf(ALib.Parts[APart].Status);
    for k := 0 to cbClass.Items.Count - 1 do
      if PtrInt(cbClass.Items.Objects[k]) = ALib.Parts[APart].ClassID then
        cbClass.ItemIndex := k;
    cbClass.Enabled := False;
    Caption := rsPartProperties;
  end
  else
  begin
    if cbClass.Items.Count > 0 then
      cbClass.ItemIndex := 0;
    Caption := rsAddPart;
  end;
  if cbStatus.ItemIndex < 0 then
    cbStatus.ItemIndex := 0;
  Path := '';
end;

{ ===========================================================================
  TfrmPartEdit.Valid  (function)
  Returns:
    Boolean - True when there is a name and a class
  Notes:
    What OK needs.
  =========================================================================== }
function TfrmPartEdit.Valid: Boolean;
begin
  Result := (Trim(edName.Text) <> '') and (cbClass.ItemIndex >= 0);
end;

{ ===========================================================================
  TfrmPartEdit.FormCloseQuery  (procedure)
  Parameters:
    Sender: TObject - the form
    var CanClose: Boolean - set to False to keep the dialog
  Notes:
    OK with an empty name or no class is refused with a message; Cancel and the close box are not asked.
  =========================================================================== }
procedure TfrmPartEdit.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if ModalResult <> mrOK then
    Exit;
  if Trim(edName.Text) = '' then
  begin
    MessageDlg(rsPart, rsThePartNeedsAName, mtWarning, [mbOK], 0);
    CanClose := False;
    edName.SetFocus;
  end
  else if cbClass.ItemIndex < 0 then
  begin
    MessageDlg(rsPart, rsChooseAClassForThe3, mtWarning, [mbOK], 0);
    CanClose := False;
  end;
end;

function TfrmPartEdit.GetClassID: Int64;
begin
  if cbClass.ItemIndex >= 0 then
    Result := PtrInt(cbClass.Items.Objects[cbClass.ItemIndex])
  else
    Result := 0;
end;

function TfrmPartEdit.GetPartName: String;
begin
  Result := Trim(edName.Text);
end;

function TfrmPartEdit.GetRefPrefix: String;
begin
  Result := Trim(edRef.Text);
end;

function TfrmPartEdit.GetDescription: String;
begin
  Result := edDescription.Text;
end;

function TfrmPartEdit.GetStatus: String;
begin
  Result := cbStatus.Text;
end;

end.
