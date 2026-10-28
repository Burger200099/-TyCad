// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Choose Product window: the products the parts library offers for a placed generic part, each with how well it fits the part's requirements (Fits, Fits (oversized),
  Does not fit with the counts). A product is chosen by selecting its row and pressing OK or by double clicking it. The controls are in Fproductpick.lfm (a TfrmBase with OK and Cancel); only the rows are made in code.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fproductpick;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Fbase, UPartsDb;

type

  { TfrmProductPick }

  TfrmProductPick = class(TfrmBase)
    lbProductsFor: TLabel;
    lvProducts: TListView;
    procedure ListDblClick(Sender: TObject);
  private
    FProducts: TProductInfoArray;
    FPicked: Integer;      // the row chosen by SelectByName (a list that was never shown cannot report its selection)
  public
    constructor CreateFor(AOwner: TComponent; const PartName: String; const AProducts: TProductInfoArray; const CurrentMPN: String);
    { the row chosen as a click does; False when no product has that manufacturer and model number }
    function SelectByName(const Mfr, MPN: String): Boolean;
    { the product of the chosen row (index in the array given); -1 when none }
    function ChosenIndex: Integer;
    function RowCount: Integer;
    function RowText(Row: Integer): String;
  end;

function FitWords(const Verdict: String; Undersized, Missing, Mismatch: Integer): String;

implementation

{$R *.lfm}

uses UStrings;

{ ===========================================================================
  FitWords  (function)
  Parameters:
    Verdict: String - does_not_fit, fits_oversized, fits or no_requirements
    Undersized, Missing, Mismatch: Integer - the counts
  Returns:
    String - the verdict as a person reads it
  =========================================================================== }
function FitWords(const Verdict: String; Undersized, Missing, Mismatch: Integer): String;
begin
  if Verdict = 'fits' then
    Result := rsFits
  else if Verdict = 'fits_oversized' then
    Result := rsFitsOversized
  else if Verdict = 'no_requirements' then
    Result := rsNoRequirements
  else
  begin
    Result := rsDoesNotFit;
    if Undersized > 0 then
      Result := Format(rsUndersized, [Result, Undersized]);
    if Missing > 0 then
      Result := Format(rsMissing, [Result, Missing]);
    if Mismatch > 0 then
      Result := Format(rsMismatched, [Result, Mismatch]);
    Result := Copy(Result, 1, Length(Result) - 1);
  end;
end;

{ ===========================================================================
  TfrmProductPick.CreateFor  (constructor)
  Parameters:
    AOwner: TComponent - the owner
    PartName: String - the part, for the heading
    AProducts: TProductInfoArray - the products offered (Products of the library), in the order shown
    CurrentMPN: String - the model number now chosen, selected to begin with
  =========================================================================== }
constructor TfrmProductPick.CreateFor(AOwner: TComponent; const PartName: String; const AProducts: TProductInfoArray; const CurrentMPN: String);
var
  i: Integer;
  It: TListItem;
begin
  inherited Create(AOwner);
  SetButtons([fcbOK, fcbCancel]);
  FProducts := AProducts;
  FPicked := -1;
  Caption := rsChooseProduct2;
  lbProductsFor.Caption := Format(rsProductsFor, [PartName]);
  btnOK.Hint := rsUseTheSelectedProduct;
  btnCancel.Hint := rsKeepTheProductAsIt;
  lvProducts.Hint := rsTheProductsOfThePart;
  lvProducts.Columns[0].Caption := rsManufacturer;
  lvProducts.Columns[1].Caption := rsModelNumber;
  lvProducts.Columns[2].Caption := rsFit;
  for i := 0 to High(FProducts) do
  begin
    It := lvProducts.Items.Add;
    It.Caption := FProducts[i].Manufacturer;
    It.SubItems.Add(FProducts[i].MPN);
    It.SubItems.Add(FitWords(FProducts[i].Verdict, FProducts[i].Undersized, FProducts[i].Missing, FProducts[i].Mismatch));
    if (CurrentMPN <> '') and (FProducts[i].MPN = CurrentMPN) then
      lvProducts.Selected := It;
  end;
end;

{ ===========================================================================
  TfrmProductPick.ListDblClick  (procedure)
  Parameters:
    Sender: TObject
  Notes:
    A double click on a product chooses it.
  =========================================================================== }
procedure TfrmProductPick.ListDblClick(Sender: TObject);
begin
  if lvProducts.Selected <> nil then
    ModalResult := mrOk;
end;

{ ===========================================================================
  TfrmProductPick.SelectByName  (function)
  Parameters:
    Mfr, MPN: String - the product wanted
  Returns:
    Boolean - True when the row was found and selected
  =========================================================================== }
function TfrmProductPick.SelectByName(const Mfr, MPN: String): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(FProducts) do
    if (FProducts[i].Manufacturer = Mfr) and (FProducts[i].MPN = MPN) then
    begin
      lvProducts.Selected := lvProducts.Items[i];
      FPicked := i;
      Exit(True);
    end;
end;

{ ===========================================================================
  TfrmProductPick.ChosenIndex  (function)
  Returns:
    Integer - the index of the selected row in the products given, -1 when no row is selected
  =========================================================================== }
function TfrmProductPick.ChosenIndex: Integer;
begin
  if FPicked >= 0 then
    Result := FPicked
  else if lvProducts.Selected = nil then
    Result := -1
  else
    Result := lvProducts.Selected.Index;
end;

{ ===========================================================================
  TfrmProductPick.RowCount  (function)
  Returns:
    Integer - the number of rows listed
  =========================================================================== }
function TfrmProductPick.RowCount: Integer;
begin
  Result := lvProducts.Items.Count;
end;

{ ===========================================================================
  TfrmProductPick.RowText  (function)
  Parameters:
    Row: Integer - the row
  Returns:
    String - manufacturer|model number|fit as listed
  =========================================================================== }
function TfrmProductPick.RowText(Row: Integer): String;
begin
  Result := lvProducts.Items[Row].Caption + '|' + lvProducts.Items[Row].SubItems[0] + '|' + lvProducts.Items[Row].SubItems[1];
end;

end.
