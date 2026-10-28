// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Requirement dialog of the parts library editor: one rating a generic part requires - what it applies to (the whole part or one of its child objects), the
  quantity (its unit is fixed by the quantity), minimum / typical / maximum (any of them, empty = not given), and a condition. Used to add a requirement and to
  change one. The numbers are read with a point or a comma as the decimal mark; the rest of the rules (min <= typ <= max, no duplicate) are the library's.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fratingedit;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase, UPartsDb;

type

  { TfrmRatingEdit }

  TfrmRatingEdit = class(TfrmBase)
    cbObject: TComboBox;
    cbQuantity: TComboBox;
    edCondition: TEdit;
    edMax: TEdit;
    edMin: TEdit;
    edTyp: TEdit;
    lblCondition: TLabel;
    lblMax: TLabel;
    lblMin: TLabel;
    lblObject: TLabel;
    lblQuantity: TLabel;
    lblSense: TLabel;
    lblTyp: TLabel;
    lblUnit: TLabel;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure QuantityChange(Sender: TObject);
  private
    FQuantities: TQuantityInfoArray;
    FProductMode: Boolean;
    function GetObjectID: Int64;
    function GetQuantity: String;
  public
    { fills the dialog for the part: ARating is the requirement to change (ID 0 = a new one, starting on the object ADefaultObject, 0 = the whole part) }
    procedure Setup(ALib: TPartsLibrary; APartID: Int64; const ARating: TPartRating; ADefaultObject: Int64);
    { the same dialog for the rating of a PRODUCT: the first box is typed or picked (the whole product, 'kind:Contact', or the name of an object of the parts of the class) }
    procedure SetupProduct(ALib: TPartsLibrary; AProductID: Int64; const ARating: TPartRating);
    function AppliesTo: String;
    function Valid: Boolean;
    { the entries; HasX is False for an empty box }
    procedure Values(out HasMin, HasTyp, HasMax: Boolean; out AMin, ATyp, AMax: Double);
    property ObjectID: Int64 read GetObjectID;
    property Quantity: String read GetQuantity;
  end;

{ a number typed by a person: empty = not given (Has False, True returned); a point or a comma is the decimal mark; False for anything that is not a number }
function ParseRatingNumber(const S: String; out Has: Boolean; out V: Double): Boolean;
{ a value shown without trailing zeros, with a point }
function FormatRatingNumber(V: Double): String;

implementation


uses UStrings;

{$R *.lfm}

function ParseRatingNumber(const S: String; out Has: Boolean; out V: Double): Boolean;
var
  T: String;
  F: TFormatSettings;
begin
  V := 0;
  Has := False;
  T := Trim(S);
  if T = '' then
    Exit(True);
  F := DefaultFormatSettings;
  F.DecimalSeparator := '.';
  T := StringReplace(T, ',', '.', [rfReplaceAll]);
  Result := TryStrToFloat(T, V, F);
  Has := Result;
end;

function FormatRatingNumber(V: Double): String;
var
  F: TFormatSettings;
begin
  F := DefaultFormatSettings;
  F.DecimalSeparator := '.';
  Result := FloatToStrF(V, ffGeneral, 12, 0, F);
end;

{ ===========================================================================
  TfrmRatingEdit.Setup  (procedure)
  Parameters:
    ALib: TPartsLibrary - the open library
    APartID: Int64 - the part
    const ARating: TPartRating - the requirement to change (ID 0 for a new one)
    ADefaultObject: Int64 - for a new one, the object to start on (0 = the whole part)
  Notes:
    Lists "(the whole part)" and the part's child objects (name, designator and kind), and every quantity of the library with its unit.
  =========================================================================== }
procedure TfrmRatingEdit.Setup(ALib: TPartsLibrary; APartID: Int64; const ARating: TPartRating; ADefaultObject: Int64);
var
  Objs: TObjectRefArray;
  i, At: Integer;
  S: String;
  Want: Int64;
begin
  Objs := ALib.PartObjects(APartID);
  cbObject.Items.Clear;
  cbObject.Items.AddObject(rsTheWholePart, TObject(PtrInt(0)));
  for i := 0 to High(Objs) do
  begin
    S := Objs[i].Name;
    if (Objs[i].Designator <> '') and (Objs[i].Designator <> Objs[i].Name) then
      S := S + ' [' + Objs[i].Designator + ']';
    cbObject.Items.AddObject(S + '  - ' + Objs[i].Kind, TObject(PtrInt(Objs[i].ID)));
  end;
  FQuantities := ALib.Quantities;
  cbQuantity.Items.Clear;
  for i := 0 to High(FQuantities) do
    cbQuantity.Items.Add(FQuantities[i].Name);
  if ARating.ID <> 0 then
    Want := ARating.ObjectID
  else
    Want := ADefaultObject;
  cbObject.ItemIndex := 0;
  for i := 0 to cbObject.Items.Count - 1 do
    if PtrInt(cbObject.Items.Objects[i]) = Want then
      cbObject.ItemIndex := i;
  if ARating.ID <> 0 then
  begin
    At := cbQuantity.Items.IndexOf(ARating.Quantity);
    cbQuantity.ItemIndex := At;
    if ARating.HasMin then
      edMin.Text := FormatRatingNumber(ARating.Min);
    if ARating.HasTyp then
      edTyp.Text := FormatRatingNumber(ARating.Typ);
    if ARating.HasMax then
      edMax.Text := FormatRatingNumber(ARating.Max);
    edCondition.Text := ARating.Condition;
    Caption := rsRequirementProperties;
  end
  else
  begin
    if cbQuantity.Items.Count > 0 then
      cbQuantity.ItemIndex := 0;
    Caption := rsAddRequirement;
  end;
  QuantityChange(nil);
end;

procedure TfrmRatingEdit.SetupProduct(ALib: TPartsLibrary; AProductID: Int64; const ARating: TPartRating);
var
  Rows: TProductRowArray;
  Choices: TStringDynArray;
  i, At: Integer;
  ClassID: Int64;
begin
  FProductMode := True;
  ClassID := 0;
  Rows := ALib.ProductRows;
  for i := 0 to High(Rows) do
    if Rows[i].ID = AProductID then
      ClassID := Rows[i].ClassID;
  Choices := ALib.AppliesToChoices(ClassID);
  cbObject.Style := csDropDown;
  lblObject.Caption := rsAppliesTo;
  cbObject.Hint := rsWhatTheRatingIsFor;
  cbObject.Items.Clear;
  cbObject.Items.Add(rsTheWholeProduct);
  for i := 0 to High(Choices) do
    cbObject.Items.Add(Choices[i]);
  FQuantities := ALib.Quantities;
  cbQuantity.Items.Clear;
  for i := 0 to High(FQuantities) do
    cbQuantity.Items.Add(FQuantities[i].Name);
  cbObject.ItemIndex := 0;
  if ARating.ID <> 0 then
  begin
    if ARating.ObjectName <> '' then
      cbObject.Text := ARating.ObjectName;
    At := cbQuantity.Items.IndexOf(ARating.Quantity);
    cbQuantity.ItemIndex := At;
    if ARating.HasMin then
      edMin.Text := FormatRatingNumber(ARating.Min);
    if ARating.HasTyp then
      edTyp.Text := FormatRatingNumber(ARating.Typ);
    if ARating.HasMax then
      edMax.Text := FormatRatingNumber(ARating.Max);
    edCondition.Text := ARating.Condition;
    Caption := rsProductRatingProperties;
  end
  else
  begin
    if cbQuantity.Items.Count > 0 then
      cbQuantity.ItemIndex := 0;
    Caption := rsAddProductRating;
  end;
  QuantityChange(nil);
end;

function TfrmRatingEdit.AppliesTo: String;
begin
  Result := Trim(cbObject.Text);
  if Result = '(the whole product)' then
    Result := '';
end;

procedure TfrmRatingEdit.QuantityChange(Sender: TObject);
var
  i: Integer;
begin
  lblUnit.Caption := ' ';
  lblSense.Caption := ' ';
  i := cbQuantity.ItemIndex;
  if (i < 0) or (i > High(FQuantities)) then
    Exit;
  lblUnit.Caption := Format(rsUnit, [FQuantities[i].Unit_]);
  if FProductMode then
  begin
    lblSense.Caption := rsARequirementIsComparedWith;
    Exit;
  end;
  if FQuantities[i].Sense = 'min' then
    lblSense.Caption := rsAProductMustOfferAt
  else if FQuantities[i].Sense = 'max' then
    lblSense.Caption := rsAProductMustStayAt
  else
    lblSense.Caption := rsAProductMustMatchThis;
  if FQuantities[i].Description <> '' then
    lblSense.Caption := lblSense.Caption + '  ' + FQuantities[i].Description;
end;

procedure TfrmRatingEdit.Values(out HasMin, HasTyp, HasMax: Boolean; out AMin, ATyp, AMax: Double);
begin
  ParseRatingNumber(edMin.Text, HasMin, AMin);
  ParseRatingNumber(edTyp.Text, HasTyp, ATyp);
  ParseRatingNumber(edMax.Text, HasMax, AMax);
end;

function TfrmRatingEdit.Valid: Boolean;
var
  H: Boolean;
  V: Double;
begin
  Result := (cbQuantity.ItemIndex >= 0) and ParseRatingNumber(edMin.Text, H, V) and ParseRatingNumber(edTyp.Text, H, V) and ParseRatingNumber(edMax.Text, H, V);
end;

function TfrmRatingEdit.GetObjectID: Int64;
begin
  Result := 0;
  if cbObject.ItemIndex >= 0 then
    Result := PtrInt(cbObject.Items.Objects[cbObject.ItemIndex]);
end;

function TfrmRatingEdit.GetQuantity: String;
begin
  Result := '';
  if cbQuantity.ItemIndex >= 0 then
    Result := cbQuantity.Items[cbQuantity.ItemIndex];
end;

procedure TfrmRatingEdit.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  H: Boolean;
  V: Double;
begin
  if ModalResult <> mrOK then
    Exit;
  if cbQuantity.ItemIndex < 0 then
  begin
    MessageDlg(rsRequirement, rsChooseWhatIsRated, mtWarning, [mbOK], 0);
    CanClose := False;
  end
  else if not (ParseRatingNumber(edMin.Text, H, V) and ParseRatingNumber(edTyp.Text, H, V) and ParseRatingNumber(edMax.Text, H, V)) then
  begin
    MessageDlg(rsRequirement, rsTheMinimumTypicalAndMaximum, mtWarning, [mbOK], 0);
    CanClose := False;
  end;
end;

end.
