// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Class dialog of the parts library editor: name, parent, abstract flag and description of one part class. Used to add a class (under the class chosen in the
  tree) and to change one, including moving it under another parent (a class cannot be moved under itself or its own subclasses, so those are not listed).

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fclassedit;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase, UPartsDb;

type

  { TfrmClassEdit }

  TfrmClassEdit = class(TfrmBase)
    cbParent: TComboBox;
    chAbstract: TCheckBox;
    edDescription: TEdit;
    edName: TEdit;
    lblDescription: TLabel;
    lblName: TLabel;
    lblParent: TLabel;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    function GetParentID: Int64;
  public
    { fills the dialog: AClassID 0 starts a new class under ADefaultParent (0 = a root); otherwise the class is shown and its subclasses and itself are left out of the parents }
    procedure Setup(ALib: TPartsLibrary; AClassID, ADefaultParent: Int64);
    function Valid: Boolean;
    property ParentID: Int64 read GetParentID;
  end;

implementation


uses UStrings;

{$R *.lfm}

{ ===========================================================================
  TfrmClassEdit.Setup  (procedure)
  Parameters:
    ALib: TPartsLibrary - the open parts library
    AClassID: Int64 - the class to change, 0 for a new class
    ADefaultParent: Int64 - for a new class, the parent to start with (0 = none)
  Notes:
    Lists "(none)" and every class that may be the parent (path from the root, sorted), and fills the entries of the class being changed.
  =========================================================================== }
procedure TfrmClassEdit.Setup(ALib: TPartsLibrary; AClassID, ADefaultParent: Int64);
var
  i, j, At, Guard: Integer;
  List: TStringList;
  Path: String;
  Idx: Integer;
  function Descends(AId, AAncestor: Int64): Boolean;
  var
    k, G: Integer;
  begin
    Result := False;
    G := 0;
    while (AId <> 0) and (G < 100) do
    begin
      if AId = AAncestor then
        Exit(True);
      k := ALib.ClassIndexOfID(AId);
      if k < 0 then
        Break;
      AId := ALib.Classes[k].ParentID;
      Inc(G);
    end;
  end;
begin
  List := TStringList.Create;
  try
    for i := 0 to ALib.ClassCount - 1 do
    begin
      if (AClassID <> 0) and Descends(ALib.Classes[i].ID, AClassID) then
        Continue;      // (itself and its subclasses)
      Path := ALib.Classes[i].Name;
      At := i;
      Guard := 0;
      while (ALib.Classes[At].ParentID <> 0) and (Guard < 100) do
      begin
        j := ALib.ClassIndexOfID(ALib.Classes[At].ParentID);
        if j < 0 then
          Break;
        At := j;
        Path := ALib.Classes[At].Name + ' > ' + Path;
        Inc(Guard);
      end;
      List.AddObject(Path, TObject(PtrInt(ALib.Classes[i].ID)));
    end;
    List.Sort;
    cbParent.Items.Clear;
    cbParent.Items.AddObject(rsNoneARootClass, TObject(PtrInt(0)));
    for i := 0 to List.Count - 1 do
      cbParent.Items.AddObject(List[i], List.Objects[i]);
  finally
    List.Free;
  end;
  cbParent.ItemIndex := 0;
  if AClassID <> 0 then
  begin
    Idx := ALib.ClassIndexOfID(AClassID);
    edName.Text := ALib.Classes[Idx].Name;
    edDescription.Text := ALib.Classes[Idx].Description;
    chAbstract.Checked := ALib.Classes[Idx].Abstract;
    for i := 0 to cbParent.Items.Count - 1 do
      if PtrInt(cbParent.Items.Objects[i]) = ALib.Classes[Idx].ParentID then
        cbParent.ItemIndex := i;
    Caption := rsClassProperties;
  end
  else
  begin
    for i := 0 to cbParent.Items.Count - 1 do
      if PtrInt(cbParent.Items.Objects[i]) = ADefaultParent then
        cbParent.ItemIndex := i;
    Caption := rsAddClass;
  end;
end;

function TfrmClassEdit.Valid: Boolean;
begin
  Result := Trim(edName.Text) <> '';
end;

function TfrmClassEdit.GetParentID: Int64;
begin
  if cbParent.ItemIndex >= 0 then
    Result := PtrInt(cbParent.Items.Objects[cbParent.ItemIndex])
  else
    Result := 0;
end;

procedure TfrmClassEdit.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if (ModalResult = mrOK) and (Trim(edName.Text) = '') then
  begin
    MessageDlg(rsClass, rsTheClassNeedsAName, mtWarning, [mbOK], 0);
    CanClose := False;
    edName.SetFocus;
  end;
end;

end.
