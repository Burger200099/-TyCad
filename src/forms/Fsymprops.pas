// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Update Library dialog (TinyCAD's CDlgUpdateBox, IDD_UPDATE), shown when a symbol is stored in its library and for Symbol Properties: the library, the number of
  parts per package, the default orientation, the names of the symbol (a symbol can have several, the aliases), and for the name chosen its description, its attributes
  (Reference and Name first, which cannot be deleted or renamed, then the others, each with a display method and a default value) and its SPICE data (model, prolog,
  epilog and their priorities, kept as the fields $$SPICE, $$SPICE_PROLOG, $$SPICE_EPILOG, $$SPICE_PROLOG_PRIORITY and $$SPICE_EPILOG_PRIORITY).
  The dialog works on a copy of the symbol's names and fields (CloneSet); OK gives the copy back (Edited) and Cancel leaves the symbol as it was.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fsymprops;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, ComCtrls, Grids, Fbase, ULibrary, USymbols, USymEdit;

const
  SPICE_MODEL = '$$SPICE';
  SPICE_PROLOG = '$$SPICE_PROLOG';
  SPICE_EPILOG = '$$SPICE_EPILOG';
  SPICE_PROLOG_PRI = '$$SPICE_PROLOG_PRIORITY';
  SPICE_EPILOG_PRI = '$$SPICE_EPILOG_PRIORITY';
  { TinyCAD's display methods, in the order of the SymbolFieldType values 0 to 6 }
  FIELD_TYPE_COUNT = 7;      // (the names are FieldTypeName: resourcestrings cannot be in a constant)

type

  { TfrmSymbolProps }

  TfrmSymbolProps = class(TfrmBase)
    btnAddField: TButton;
    btnAddName: TButton;
    btnDeleteField: TButton;
    btnDeleteName: TButton;
    cbOrientation: TComboBox;
    edDescription: TEdit;
    edEpilog: TEdit;
    edEpilogPri: TEdit;
    edModel: TEdit;
    edProlog: TEdit;
    edPrologPri: TEdit;
    lbNames: TListBox;
    lblDescription: TLabel;
    lblEpilog: TLabel;
    lblEpilogPri: TLabel;
    lblLibrary: TLabel;
    lblModel: TLabel;
    lblNames: TLabel;
    lblOrientation: TLabel;
    lblParts: TLabel;
    lblProlog: TLabel;
    lblPrologPri: TLabel;
    pcTabs: TPageControl;
    sgFields: TStringGrid;
    tsAttributes: TTabSheet;
    tsSpice: TTabSheet;
    procedure AddFieldClick(Sender: TObject);
    procedure AddNameClick(Sender: TObject);
    procedure DeleteFieldClick(Sender: TObject);
    procedure DeleteNameClick(Sender: TObject);
    procedure FieldSelect(Sender: TObject; aCol, aRow: Integer; var CanSelect: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure NameSelect(Sender: TObject; User: Boolean);
  private
    FWork: TLibrarySymbolSet;     // the copy being edited (owned)
    FCur: Integer;                // the name showing
    FLoading: Boolean;
    FRowSelected: Integer;
    procedure ShowRecord;
    procedure StoreRecord;
    procedure UpdateButtons;
    function FieldTypeIndex(const S: String): Integer;
  public
    destructor Destroy; override;
    { fill from a symbol: its library's name and the dialog's copy of its names and fields }
    procedure Load(Ed: TSymbolEditor; const LibName: String);
    { the edited names and fields (a copy; the caller owns it), after the current name was stored }
    function Edited: TLibrarySymbolSet;
    { what a person does with the controls, for tests and for the buttons }
    procedure SelectName(Index: Integer);
    procedure AddName;
    procedure DeleteName;
    procedure AddField;
    procedure DeleteField(Row: Integer);
    procedure SetCell(Row, Col: Integer; const Value: String);
    function Cell(Row, Col: Integer): String;
    function NameCount: Integer;
    function CurrentName: Integer;
  end;

var
  frmSymbolProps: TfrmSymbolProps;

implementation


uses UStrings;

{$R *.lfm}

{ the name of a display method (SymbolFieldType 0 to 6) as the list and the grid show it }
function FieldTypeName(AType: Integer): String;
begin
  case AType of
    0: Result := rsShowValueOnly;
    1: Result := rsHideValue;
    2: Result := rsNeverShow;
    3: Result := rsShowValueExtraOnly;
    4: Result := rsShowNameValueWhenPresent;
    5: Result := rsShowNameValue;
    6: Result := rsShowValueWhenPresent;
  else
    Result := '';
  end;
end;


{ ===========================================================================
  TfrmSymbolProps.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Fills the lists and sets up the attribute grid (Parameter, Display Method with a drop-down
    list, Default Value).
  =========================================================================== }
procedure TfrmSymbolProps.FormCreate(Sender: TObject);
var
  i: Integer;
  C: TGridColumn;
begin
  cbOrientation.Items.CommaText := 'Up,Down,Left,Right';
  cbOrientation.ItemIndex := 0;
  sgFields.Columns.Clear;
  C := sgFields.Columns.Add;
  C.Title.Caption := rsParameter;
  C.Width := 150;
  C := sgFields.Columns.Add;
  C.Title.Caption := rsDisplayMethod;
  C.Width := 230;
  C.ButtonStyle := cbsPickList;
  for i := 0 to FIELD_TYPE_COUNT - 1 do C.PickList.Add(FieldTypeName(i));
  C := sgFields.Columns.Add;
  C.Title.Caption := rsDefaultValue;
  C.Width := 240;
  sgFields.FixedRows := 1;
  sgFields.RowCount := 1;
  FRowSelected := -1;
end;

{ ===========================================================================
  TfrmSymbolProps.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the copy being edited.
  =========================================================================== }
destructor TfrmSymbolProps.Destroy;
begin
  FWork.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TfrmSymbolProps.FieldTypeIndex  (function)
  Parameters:
    const S: String - text
  Returns:
    Integer - the display method's number (0 to 6), 0 when the text is none of them
  Notes:
    Turns the text of a Display Method cell back into the SymbolFieldType value.
  =========================================================================== }
function TfrmSymbolProps.FieldTypeIndex(const S: String): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to FIELD_TYPE_COUNT - 1 do
    if SameText(S, FieldTypeName(i)) then
      Exit(i);
end;

{ ===========================================================================
  TfrmSymbolProps.Load  (procedure)
  Parameters:
    Ed: TSymbolEditor - the symbol
    const LibName: String - text
  Notes:
    Takes a copy of the symbol's names and fields to edit and shows the first name, with the
    library, the number of parts and the default orientation.
  =========================================================================== }
procedure TfrmSymbolProps.Load(Ed: TSymbolEditor; const LibName: String);
var
  i: Integer;
begin
  FWork.Free;
  FWork := Ed.CloneSet;
  lblLibrary.Caption := Format(rsLibrary, [LibName]);
  lblParts.Caption := Format(rsPartsPerPackage, [FWork.Ppp]);
  cbOrientation.ItemIndex := Max(0, Min(3, FWork.Orientation));
  lbNames.Items.Clear;
  for i := 0 to FWork.RecordCount - 1 do lbNames.Items.Add(FWork.Records[i].Name);
  FCur := 0;
  lbNames.ItemIndex := 0;
  ShowRecord;
end;

{ ===========================================================================
  TfrmSymbolProps.ShowRecord  (procedure)
  Parameters:  none
  Notes:
    Shows the name chosen (InitFromRecord): its description; the grid with Reference and Name
    first (their display methods and defaults), then its other fields (its package field is
    added, hidden, when it has none); and its SPICE data, whose fields are not in the grid.
  =========================================================================== }
procedure TfrmSymbolProps.ShowRecord;
var
  R: TLibraryRecord;
  i, Row: Integer;
  HavePackage: Boolean;
  ProPri, EpiPri: Integer;
  F: TSymbolFieldDef;

  procedure AddRow(const AName: String; AType: Integer; const ADefault: String);
  begin
    sgFields.RowCount := sgFields.RowCount + 1;
    Row := sgFields.RowCount - 1;
    sgFields.Cells[0, Row] := AName;
    if (AType >= 0) and (AType <= FIELD_TYPE_COUNT - 1) then
      sgFields.Cells[1, Row] := FieldTypeName(AType)
    else
      sgFields.Cells[1, Row] := '';
    sgFields.Cells[2, Row] := ADefault;
  end;

begin
  FLoading := True;
  try
    R := FWork.Records[FCur];
    edDescription.Text := R.Description;
    sgFields.RowCount := 1;
    AddRow('Reference', R.RefType, R.Reference);
    AddRow('Name', R.NameType, R.Name);
    edModel.Text := '';
    edProlog.Text := '';
    edEpilog.Text := '';
    ProPri := 5;
    EpiPri := 5;
    HavePackage := False;
    for i := 0 to High(R.Fields) do
    begin
      F := R.Fields[i];
      if SameText(F.Name, SPICE_MODEL) then
        edModel.Text := F.Default
      else if SameText(F.Name, SPICE_PROLOG) then
        edProlog.Text := F.Default
      else if SameText(F.Name, SPICE_EPILOG) then
        edEpilog.Text := F.Default
      else if SameText(F.Name, SPICE_PROLOG_PRI) then
      begin
        ProPri := StrToIntDef(Trim(F.Default), 0);
        if (ProPri < 0) or (ProPri > 10) then
          ProPri := 5;
      end
      else if SameText(F.Name, SPICE_EPILOG_PRI) then
      begin
        EpiPri := StrToIntDef(Trim(F.Default), 0);
        if (EpiPri < 0) or (EpiPri > 10) then
          EpiPri := 5;
      end
      else
      begin
        AddRow(F.Name, F.FieldType, F.Default);
        if SameText(F.Name, 'Package') then
          HavePackage := True;
      end;
    end;
    edPrologPri.Text := IntToStr(ProPri);
    edEpilogPri.Text := IntToStr(EpiPri);
    if not HavePackage then
      AddRow('Package', 1, 'package name for PCB layout');       // (default_hidden)
    FRowSelected := -1;
  finally
    FLoading := False;
  end;
  UpdateButtons;
end;

{ ===========================================================================
  TfrmSymbolProps.StoreRecord  (procedure)
  Parameters:  none
  Notes:
    Writes what the dialog shows back into the name chosen (UpdateToRecord): reference and name
    with their display methods, the description, then the fields - the SPICE ones first (only
    those that have text, always hidden), then the other rows of the grid.
  =========================================================================== }
procedure TfrmSymbolProps.StoreRecord;
var
  R: TLibraryRecord;
  Row, N: Integer;

  procedure AddFld(const AName, ADefault: String; AType: Integer);
  begin
    SetLength(R.Fields, N + 1);
    R.Fields[N].Name := AName;
    R.Fields[N].Value := '';
    R.Fields[N].Default := ADefault;
    R.Fields[N].FieldType := Cardinal(AType);
    Inc(N);
  end;

begin
  if (FWork = nil) or (FCur < 0) or (FCur >= FWork.RecordCount) then
    Exit;
  R := FWork.Records[FCur];
  R.Reference := sgFields.Cells[2, 1];
  R.RefType := FieldTypeIndex(sgFields.Cells[1, 1]);
  R.Name := sgFields.Cells[2, 2];
  R.NameType := FieldTypeIndex(sgFields.Cells[1, 2]);
  R.Description := edDescription.Text;
  FWork.Orientation := cbOrientation.ItemIndex;
  SetLength(R.Fields, 0);
  N := 0;
  if edModel.Text <> '' then
    AddFld(SPICE_MODEL, edModel.Text, 2);
  if edProlog.Text <> '' then
    AddFld(SPICE_PROLOG, edProlog.Text, 2);
  if edEpilog.Text <> '' then
    AddFld(SPICE_EPILOG, edEpilog.Text, 2);
  if Trim(edPrologPri.Text) <> '' then
    AddFld(SPICE_PROLOG_PRI, Trim(edPrologPri.Text), 2);
  if Trim(edEpilogPri.Text) <> '' then
    AddFld(SPICE_EPILOG_PRI, Trim(edEpilogPri.Text), 2);
  for Row := 3 to sgFields.RowCount - 1 do
    AddFld(sgFields.Cells[0, Row], sgFields.Cells[2, Row], FieldTypeIndex(sgFields.Cells[1, Row]));
  R.FieldsLoaded := True;
  lbNames.Items[FCur] := R.Name;           // (the list shows a name as it was typed)
end;

{ ===========================================================================
  TfrmSymbolProps.UpdateButtons  (procedure)
  Parameters:  none
  Notes:
    Delete name needs more than one name; Delete attribute needs a row after Reference and Name.
  =========================================================================== }
procedure TfrmSymbolProps.UpdateButtons;
begin
  btnDeleteName.Enabled := (FWork <> nil) and (FWork.RecordCount > 1);
  btnDeleteField.Enabled := (FRowSelected >= 3);
end;

{ ===========================================================================
  TfrmSymbolProps.NameCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    How many names the list shows.
  =========================================================================== }
function TfrmSymbolProps.NameCount: Integer;
begin
  Result := lbNames.Items.Count;
end;

{ ===========================================================================
  TfrmSymbolProps.CurrentName  (function)
  Parameters:  none
  Returns:
    Integer - the position of the name showing
  Notes:
    Which name the rest of the dialog shows.
  =========================================================================== }
function TfrmSymbolProps.CurrentName: Integer;
begin
  Result := FCur;
end;

{ ===========================================================================
  TfrmSymbolProps.SelectName  (procedure)
  Parameters:
    Index: Integer - position in the list of names
  Notes:
    OnSelchangeListNames: the name showing is written back and the chosen one is shown.
  =========================================================================== }
procedure TfrmSymbolProps.SelectName(Index: Integer);
begin
  if (Index < 0) or (Index >= FWork.RecordCount) or (Index = FCur) then
    Exit;
  StoreRecord;
  FCur := Index;
  lbNames.ItemIndex := Index;
  ShowRecord;
end;

{ ===========================================================================
  TfrmSymbolProps.NameSelect  (procedure)
  Parameters:
    Sender: TObject - the list
    User: Boolean - True when the person chose
  Notes:
    The list of names was clicked.
  =========================================================================== }
procedure TfrmSymbolProps.NameSelect(Sender: TObject; User: Boolean);
begin
  if User and (not FLoading) then
    SelectName(lbNames.ItemIndex);
end;

{ ===========================================================================
  TfrmSymbolProps.AddName  (procedure)
  Parameters:  none
  Notes:
    OnAddName: another name for the symbol (an alias), starting as a copy of the name showing
    and called "New Symbol"; it is shown for editing.
  =========================================================================== }
procedure TfrmSymbolProps.AddName;
var
  Cur, R: TLibraryRecord;
  j: Integer;
begin
  StoreRecord;
  Cur := FWork.Records[FCur];
  R := FWork.AddRecord;
  R.Name := 'New Symbol';
  R.Reference := Cur.Reference;
  R.Description := Cur.Description;
  R.NameType := Cur.NameType;
  R.RefType := Cur.RefType;
  R.NameID := -1;
  R.FieldsLoaded := True;
  SetLength(R.Fields, Length(Cur.Fields));
  for j := 0 to High(Cur.Fields) do R.Fields[j] := Cur.Fields[j];
  lbNames.Items.Add(R.Name);
  FCur := FWork.RecordCount - 1;
  lbNames.ItemIndex := FCur;
  ShowRecord;
end;

{ ===========================================================================
  TfrmSymbolProps.AddNameClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    Add name.
  =========================================================================== }
procedure TfrmSymbolProps.AddNameClick(Sender: TObject);
begin
  AddName;
end;

{ ===========================================================================
  TfrmSymbolProps.DeleteName  (procedure)
  Parameters:  none
  Notes:
    OnDeleteName: removes the name showing (never the last one); the one before it is shown.
  =========================================================================== }
procedure TfrmSymbolProps.DeleteName;
var
  Keep: TLibrarySymbolSet;
  i, j: Integer;
  R, NewR: TLibraryRecord;
begin
  if FWork.RecordCount <= 1 then
    Exit;
  StoreRecord;
  Keep := TLibrarySymbolSet.Create;
  Keep.SymbolID := FWork.SymbolID;
  Keep.Ppp := FWork.Ppp;
  Keep.Orientation := FWork.Orientation;
  for i := 0 to FWork.RecordCount - 1 do
    if i <> FCur then
    begin
      R := FWork.Records[i];
      NewR := Keep.AddRecord;
      NewR.Name := R.Name; NewR.Reference := R.Reference; NewR.Description := R.Description;
      NewR.NameType := R.NameType; NewR.RefType := R.RefType; NewR.NameID := -1; NewR.FieldsLoaded := True;
      SetLength(NewR.Fields, Length(R.Fields));
      for j := 0 to High(R.Fields) do NewR.Fields[j] := R.Fields[j];
    end;
  FWork.Free;
  FWork := Keep;
  lbNames.Items.Delete(FCur);
  if FCur > FWork.RecordCount - 1 then
    FCur := FWork.RecordCount - 1;
  lbNames.ItemIndex := FCur;
  ShowRecord;
end;

{ ===========================================================================
  TfrmSymbolProps.DeleteNameClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    Delete name.
  =========================================================================== }
procedure TfrmSymbolProps.DeleteNameClick(Sender: TObject);
begin
  DeleteName;
end;

{ ===========================================================================
  TfrmSymbolProps.AddField  (procedure)
  Parameters:  none
  Notes:
    OnAdd: a new attribute at the end of the grid: "Other", shown by default, with the value
    "..".
  =========================================================================== }
procedure TfrmSymbolProps.AddField;
begin
  sgFields.RowCount := sgFields.RowCount + 1;
  sgFields.Cells[0, sgFields.RowCount - 1] := rsOther;
  sgFields.Cells[1, sgFields.RowCount - 1] := FieldTypeName(0);
  sgFields.Cells[2, sgFields.RowCount - 1] := '..';
end;

{ ===========================================================================
  TfrmSymbolProps.AddFieldClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    Add attribute.
  =========================================================================== }
procedure TfrmSymbolProps.AddFieldClick(Sender: TObject);
begin
  AddField;
end;

{ ===========================================================================
  TfrmSymbolProps.DeleteField  (procedure)
  Parameters:
    Row: Integer - the row of the grid
  Notes:
    OnDelete: removes an attribute; Reference and Name (the first two) cannot be removed.
  =========================================================================== }
procedure TfrmSymbolProps.DeleteField(Row: Integer);
begin
  if (Row < 3) or (Row >= sgFields.RowCount) then
    Exit;
  sgFields.DeleteRow(Row);
  FRowSelected := -1;
  UpdateButtons;
end;

{ ===========================================================================
  TfrmSymbolProps.DeleteFieldClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    Delete attribute.
  =========================================================================== }
procedure TfrmSymbolProps.DeleteFieldClick(Sender: TObject);
begin
  DeleteField(FRowSelected);
end;

{ ===========================================================================
  TfrmSymbolProps.FieldSelect  (procedure)
  Parameters:
    Sender: TObject - the grid
    aCol: Integer - column
    aRow: Integer - row
    var CanSelect: Boolean - flag (in/out: changed by the call)
  Notes:
    A cell of the grid was chosen: Delete attribute follows the row. Reference and Name keep
    their names (the first column of those rows is not edited).
  =========================================================================== }
procedure TfrmSymbolProps.FieldSelect(Sender: TObject; aCol, aRow: Integer; var CanSelect: Boolean);
begin
  FRowSelected := aRow;
  sgFields.Options := sgFields.Options + [goEditing];
  if (aRow < 3) and (aCol = 0) then
    sgFields.Options := sgFields.Options - [goEditing];
  UpdateButtons;
end;

{ ===========================================================================
  TfrmSymbolProps.SetCell  (procedure)
  Parameters:
    Row: Integer - row of the grid
    Col: Integer - column (0 parameter, 1 display method, 2 default value)
    const Value: String - the value
  Notes:
    Types into a cell as a person does. The first column of Reference and Name cannot be
    changed; the name's default value is the name.
  =========================================================================== }
procedure TfrmSymbolProps.SetCell(Row, Col: Integer; const Value: String);
begin
  if (Row < 1) or (Row >= sgFields.RowCount) or (Col < 0) or (Col > 2) then
    Exit;
  if (Row < 3) and (Col = 0) then
    Exit;
  sgFields.Cells[Col, Row] := Value;
  if (Row = 2) and (Col = 2) then
    lbNames.Items[FCur] := Value;
end;

{ ===========================================================================
  TfrmSymbolProps.Cell  (function)
  Parameters:
    Row: Integer - row of the grid
    Col: Integer - column
  Returns:
    String - the text
  Notes:
    What a cell shows.
  =========================================================================== }
function TfrmSymbolProps.Cell(Row, Col: Integer): String;
begin
  Result := sgFields.Cells[Col, Row];
end;

{ ===========================================================================
  TfrmSymbolProps.Edited  (function)
  Parameters:  none
  Returns:
    TLibrarySymbolSet - a copy of the edited names and fields; the caller owns it
  Notes:
    Writes the name showing back and gives an independent copy of the edited names, with the
    default orientation chosen.
  =========================================================================== }
function TfrmSymbolProps.Edited: TLibrarySymbolSet;
var
  i, j: Integer;
  R, N: TLibraryRecord;
begin
  StoreRecord;
  Result := TLibrarySymbolSet.Create;
  Result.SymbolID := FWork.SymbolID;
  Result.Ppp := FWork.Ppp;
  Result.Orientation := FWork.Orientation;
  for i := 0 to FWork.RecordCount - 1 do
  begin
    R := FWork.Records[i];
    N := Result.AddRecord;
    N.Name := R.Name; N.Reference := R.Reference; N.Description := R.Description;
    N.NameType := R.NameType; N.RefType := R.RefType; N.NameID := R.NameID; N.FieldsLoaded := True;
    SetLength(N.Fields, Length(R.Fields));
    for j := 0 to High(R.Fields) do N.Fields[j] := R.Fields[j];
  end;
end;

end.
