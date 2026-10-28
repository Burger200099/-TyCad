{ The Product dialog of the parts library editor: manufacturer, model number, series, class, status and description of one catalog product. Used to add a product
  and to change one. The rules (manufacturer + model number unique, class not abstract) are the library's.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fproductedit;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase, UPartsDb;

type

  { TfrmProductEdit }

  TfrmProductEdit = class(TfrmBase)
    cbClass: TComboBox;
    cbStatus: TComboBox;
    edDescription: TEdit;
    edManufacturer: TEdit;
    edMPN: TEdit;
    edSeries: TEdit;
    lblClass: TLabel;
    lblDescription: TLabel;
    lblManufacturer: TLabel;
    lblMPN: TLabel;
    lblSeries: TLabel;
    lblStatus: TLabel;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    function GetClassID: Int64;
  public
    { fills the dialog: AProductID 0 starts a new product of class ADefaultClass (0 = none chosen); otherwise the product is shown }
    procedure Setup(ALib: TPartsLibrary; AProductID, ADefaultClass: Int64);
    property ClassID: Int64 read GetClassID;
  end;

implementation


uses UStrings;

{$R *.lfm}

{ ===========================================================================
  TfrmProductEdit.Setup  (procedure)
  Parameters:
    ALib: TPartsLibrary - the open parts library
    AProductID: Int64 - the product to change, 0 for a new one
    ADefaultClass: Int64 - for a new product, the class to start with
  Notes:
    Lists every class that is not abstract (path from the root, sorted) and fills the entries of the product being changed.
  =========================================================================== }
procedure TfrmProductEdit.Setup(ALib: TPartsLibrary; AProductID, ADefaultClass: Int64);
var
  i, j, At, Guard: Integer;
  List: TStringList;
  Path: String;
  Rows: TProductRowArray;
  Want: Int64;
begin
  List := TStringList.Create;
  try
    for i := 0 to ALib.ClassCount - 1 do
    begin
      if ALib.Classes[i].Abstract then
        Continue;
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
    cbClass.Items.Clear;
    for i := 0 to List.Count - 1 do
      cbClass.Items.AddObject(List[i], List.Objects[i]);
  finally
    List.Free;
  end;
  cbStatus.ItemIndex := 0;
  Want := ADefaultClass;
  if AProductID <> 0 then
  begin
    Rows := ALib.ProductRows;
    for i := 0 to High(Rows) do
      if Rows[i].ID = AProductID then
      begin
        edManufacturer.Text := Rows[i].Manufacturer;
        edMPN.Text := Rows[i].MPN;
        edSeries.Text := Rows[i].Series;
        edDescription.Text := Rows[i].Description;
        cbStatus.ItemIndex := cbStatus.Items.IndexOf(Rows[i].Status);
        Want := Rows[i].ClassID;
      end;
    Caption := rsProductProperties;
  end
  else
    Caption := rsAddProduct;
  cbClass.ItemIndex := -1;
  for i := 0 to cbClass.Items.Count - 1 do
    if PtrInt(cbClass.Items.Objects[i]) = Want then
      cbClass.ItemIndex := i;
  if (cbClass.ItemIndex < 0) and (cbClass.Items.Count > 0) then
    cbClass.ItemIndex := 0;
end;

function TfrmProductEdit.GetClassID: Int64;
begin
  Result := 0;
  if cbClass.ItemIndex >= 0 then
    Result := PtrInt(cbClass.Items.Objects[cbClass.ItemIndex]);
end;

procedure TfrmProductEdit.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if ModalResult <> mrOK then
    Exit;
  if Trim(edManufacturer.Text) = '' then
  begin
    MessageDlg(rsProduct, rsTheProductNeedsAManufacturer, mtWarning, [mbOK], 0);
    CanClose := False;
    edManufacturer.SetFocus;
  end
  else if Trim(edMPN.Text) = '' then
  begin
    MessageDlg(rsProduct, rsTheProductNeedsAModel, mtWarning, [mbOK], 0);
    CanClose := False;
    edMPN.SetFocus;
  end
  else if cbClass.ItemIndex < 0 then
  begin
    MessageDlg(rsProduct, rsTheLibraryHasNoClass, mtWarning, [mbOK], 0);
    CanClose := False;
  end;
end;

end.
