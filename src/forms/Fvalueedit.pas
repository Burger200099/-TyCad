{ The Field Value dialog of the parts library editor: the value of one field of a part (a field of its class) or of one of its child objects (a field of the object's
  kind). Text and ref fields are typed, int and real fields typed as numbers, bool and enum fields picked from a list. Empty / (none) removes the stored value. The
  checking of what is typed is the library's (TPartsLibrary.SetFieldValue), which explains a refusal.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fvalueedit;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase, UPartsDb;

type

  { TfrmValueEdit }

  TfrmValueEdit = class(TfrmBase)
    cbValue: TComboBox;
    edValue: TEdit;
    lblHint: TLabel;
    lblInfo: TLabel;
    lblValue: TLabel;
  private
    FPicked: Boolean;
    function GetValueText: String;
  public
    { fills the dialog for one row of TPartsLibrary.FieldValues }
    procedure Setup(const ARow: TValueRow);
    { what was entered: '' for nothing / (none) }
    property ValueText: String read GetValueText;
  end;

implementation


uses UStrings;

{$R *.lfm}

{ ===========================================================================
  TfrmValueEdit.Setup  (procedure)
  Parameters:
    const ARow: TValueRow - the field and its value now
  Notes:
    Shows what the field is (name, type, unit, who declares it, where it applies). enum fields offer their values and bool yes / no in a list, everything else is typed.
  =========================================================================== }
procedure TfrmValueEdit.Setup(const ARow: TValueRow);
var
  Items: TStringList;
  i: Integer;
  Where: String;
begin
  if ARow.ObjectID = 0 then
    Where := rsThePart2
  else
    Where := ARow.ObjectName;
  lblInfo.Caption := Format(rsOfDeclaredBy, [ARow.FieldName, ARow.FieldType, IfThen(ARow.Unit_ <> '', ', ' + ARow.Unit_, ''), IfThen(ARow.Required, rsRequired, ''), Where, ARow.DeclaredBy]);
  FPicked := (ARow.FieldType = 'enum') or (ARow.FieldType = 'bool');
  cbValue.Visible := FPicked;
  edValue.Visible := not FPicked;
  if FPicked then
  begin
    cbValue.Items.Clear;
    cbValue.Items.Add(rsNone);
    if ARow.FieldType = 'bool' then
    begin
      cbValue.Items.Add(rsYes2);
      cbValue.Items.Add(rsNo2);
    end
    else
    begin
      Items := TStringList.Create;
      try
        Items.Delimiter := ',';
        Items.StrictDelimiter := True;
        Items.DelimitedText := ARow.EnumValues;
        for i := 0 to Items.Count - 1 do
          cbValue.Items.Add(Trim(Items[i]));
      finally
        Items.Free;
      end;
    end;
    cbValue.ItemIndex := 0;
    if ARow.HasValue then
      cbValue.ItemIndex := cbValue.Items.IndexOf(ARow.ValueText);
    if cbValue.ItemIndex < 0 then
      cbValue.ItemIndex := 0;
    lblValue.FocusControl := cbValue;
  end
  else
  begin
    edValue.Text := ARow.ValueText;
    if ARow.FieldType = 'int' then
      lblHint.Caption := rsAWholeNumber
    else if ARow.FieldType = 'real' then
      lblHint.Caption := rsANumberAPointOr
    else if ARow.FieldType = 'ref' then
      lblHint.Caption := rsTheNameOfWhatIt
    else
      lblHint.Caption := rsText2;
  end;
  Caption := Format(rsValueOf, [ARow.FieldName]);
end;

function TfrmValueEdit.GetValueText: String;
begin
  if FPicked then
  begin
    if cbValue.ItemIndex <= 0 then
      Result := ''
    else
      Result := cbValue.Items[cbValue.ItemIndex];
  end
  else
    Result := Trim(edValue.Text);
end;

end.
