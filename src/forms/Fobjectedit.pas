{ The Object dialog of the parts library editor: name, designator, kind, parent, order and description of one child object of a part (a terminal, pole,
  channel ...). Used to add an object to a part and to change one. Only the kinds the part's class allows are offered, and the parents offered leave out the
  object itself and everything inside it, so the choices cannot make a cycle.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fobjectedit;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase, UPartsDb;

type

  { TfrmObjectEdit }

  TfrmObjectEdit = class(TfrmBase)
    cbKind: TComboBox;
    cbParent: TComboBox;
    edDescription: TEdit;
    edDesignator: TEdit;
    edName: TEdit;
    edSort: TEdit;
    lblDescription: TLabel;
    lblDesignator: TLabel;
    lblKind: TLabel;
    lblName: TLabel;
    lblParent: TLabel;
    lblSort: TLabel;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    function GetParentID: Int64;
    function GetKindID: Int64;
    function GetSortValue: Integer;
  public
    { fills the dialog for a part: AObjectID 0 starts a new object inside ADefaultParent (0 = directly in the part); otherwise the object is shown }
    procedure Setup(ALib: TPartsLibrary; APartID, AObjectID, ADefaultParent: Int64);
    property ParentID: Int64 read GetParentID;
    property KindID: Int64 read GetKindID;
    property SortValue: Integer read GetSortValue;
  end;

implementation


uses UStrings;

{$R *.lfm}

{ ===========================================================================
  TfrmObjectEdit.Setup  (procedure)
  Parameters:
    ALib: TPartsLibrary - the open parts library
    APartID: Int64 - the part
    AObjectID: Int64 - the object to change, 0 for a new one
    ADefaultParent: Int64 - for a new object, the object it starts inside (0 = the part itself)
  Notes:
    Lists the part's allowed kinds and "(the part itself)" with every object that may hold this one (as a path from the top, in the part's order). A new object
    starts with an order one past the last. The entries of an existing object are filled in.
  =========================================================================== }
procedure TfrmObjectEdit.Setup(ALib: TPartsLibrary; APartID, AObjectID, ADefaultParent: Int64);
var
  Objs: TObjectRefArray;
  Kinds: TKindInfoArray;
  i, MaxSort, Idx: Integer;
  function IndexOfObj(AId: Int64): Integer;
  var
    k: Integer;
  begin
    Result := -1;
    for k := 0 to High(Objs) do
      if Objs[k].ID = AId then
        Exit(k);
  end;
  function Inside(AId, AAncestor: Int64): Boolean;       // AId is AAncestor or lies below it
  var
    k, G: Integer;
  begin
    Result := False;
    G := 0;
    while (AId <> 0) and (G < 100) do
    begin
      if AId = AAncestor then
        Exit(True);
      k := IndexOfObj(AId);
      if k < 0 then
        Break;
      AId := Objs[k].ParentID;
      Inc(G);
    end;
  end;
  function PathOf(k: Integer): String;
  var
    G, j: Integer;
  begin
    Result := Objs[k].Name;
    G := 0;
    while (Objs[k].ParentID <> 0) and (G < 100) do
    begin
      j := IndexOfObj(Objs[k].ParentID);
      if j < 0 then
        Break;
      k := j;
      Result := Objs[k].Name + ' > ' + Result;
      Inc(G);
    end;
  end;
begin
  Objs := ALib.PartObjects(APartID);
  Kinds := ALib.ObjectKinds(APartID);
  cbKind.Items.Clear;
  for i := 0 to High(Kinds) do
    cbKind.Items.AddObject(Kinds[i].Name, TObject(PtrInt(Kinds[i].ID)));
  cbParent.Items.Clear;
  cbParent.Items.AddObject(rsThePartItself, TObject(PtrInt(0)));
  MaxSort := -1;
  for i := 0 to High(Objs) do
  begin
    if Objs[i].Sort > MaxSort then
      MaxSort := Objs[i].Sort;
    if (AObjectID <> 0) and Inside(Objs[i].ID, AObjectID) then
      Continue;       // (itself and what lies inside it)
    cbParent.Items.AddObject(PathOf(i), TObject(PtrInt(Objs[i].ID)));
  end;
  cbParent.ItemIndex := 0;
  if cbKind.Items.Count > 0 then
    cbKind.ItemIndex := 0;
  if AObjectID <> 0 then
  begin
    Idx := IndexOfObj(AObjectID);
    edName.Text := Objs[Idx].Name;
    edDesignator.Text := Objs[Idx].Designator;
    edDescription.Text := Objs[Idx].Description;
    edSort.Text := IntToStr(Objs[Idx].Sort);
    for i := 0 to cbKind.Items.Count - 1 do
      if PtrInt(cbKind.Items.Objects[i]) = Objs[Idx].KindID then
        cbKind.ItemIndex := i;
    for i := 0 to cbParent.Items.Count - 1 do
      if PtrInt(cbParent.Items.Objects[i]) = Objs[Idx].ParentID then
        cbParent.ItemIndex := i;
    Caption := rsObjectProperties;
  end
  else
  begin
    edSort.Text := IntToStr(MaxSort + 1);
    for i := 0 to cbParent.Items.Count - 1 do
      if PtrInt(cbParent.Items.Objects[i]) = ADefaultParent then
        cbParent.ItemIndex := i;
    Caption := rsAddObject;
  end;
end;

function TfrmObjectEdit.GetParentID: Int64;
begin
  if cbParent.ItemIndex >= 0 then
    Result := PtrInt(cbParent.Items.Objects[cbParent.ItemIndex])
  else
    Result := 0;
end;

function TfrmObjectEdit.GetKindID: Int64;
begin
  if cbKind.ItemIndex >= 0 then
    Result := PtrInt(cbKind.Items.Objects[cbKind.ItemIndex])
  else
    Result := 0;
end;

function TfrmObjectEdit.GetSortValue: Integer;
begin
  Result := StrToIntDef(Trim(edSort.Text), 0);
end;

procedure TfrmObjectEdit.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  V: Integer;
begin
  if ModalResult <> mrOK then
    Exit;
  if Trim(edName.Text) = '' then
  begin
    MessageDlg(rsObject, rsTheObjectNeedsAName, mtWarning, [mbOK], 0);
    CanClose := False;
    edName.SetFocus;
  end
  else if cbKind.ItemIndex < 0 then
  begin
    MessageDlg(rsObject, rsThePartSClassAllows, mtWarning, [mbOK], 0);
    CanClose := False;
  end
  else if not TryStrToInt(Trim(edSort.Text), V) then
  begin
    MessageDlg(rsObject, rsTheOrderMustBeA, mtWarning, [mbOK], 0);
    CanClose := False;
    edSort.SetFocus;
  end;
end;

end.
