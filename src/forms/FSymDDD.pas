// SPDX-License-Identifier: LGPL-2.1-or-later
{ The parameter list of a placed symbol, dropped down from the Parameters button of the symbol's property frame (TinyCAD's list in the symbol tool options, CEditDlgMethodEdit:
  Parameter, Show?, Value, with Add and Delete).
    - every field of the symbol except the reference and the always hidden ones is a row;
    - a click in the Show? column turns the field on or off; a click in the Value column edits the value, and in the Parameter column the name, but only of a parameter that was added
      here (the others come from the library and keep their names);
    - Add puts a new parameter 'Other' = '..' at the bottom; Delete takes the selected one away, and is enabled only for a parameter that was added here (extra_parameter).
  Several symbols can be selected: the list then holds the parameters of all of them, a parameter being one description (the n-th field of that description in each symbol); only the parameters every selected symbol has are listed. A change
  of Show?, a value, a name, Add or Delete is made to every selected symbol that has the parameter; where the symbols differ the value shows (varies) and Show? shows a dash box.
  Every change is one step: OnBeforeChange is called before it and OnAfterChange after, so the owner can make it one undo step (a symbol that is being placed has no undo).

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit FSymDDD;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math, Types, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls, Grids, ImgList,
  LCLType, LCLIntf, FDropDownBase, UDrawTypes, UDrawingObjects, UDPoint;

type
  TMethodArray = array of TDrawMethod;

  { one parameter of the list: the field of each selected symbol that has it }
  TParamRef = record
    M, F: Integer;                    // index of the symbol, index of its field
  end;

  TParamRow = record
    Refs: array of TParamRef;
    Extra: Boolean;                   // every one is a parameter added in the schematic editor (its name can change and it can be deleted)
  end;

  { TfrmSymbolPropList }

  TfrmSymbolPropList = class(TfrmDropDownBase)
    btnAdd: TButton;
    btnDelete: TButton;
    grdParams: TStringGrid;
    ilResize: TImage;
    lblCount: TLabel;
    Panel1: TPanel;
    procedure btnAddClick(Sender: TObject);
    procedure btnDeleteClick(Sender: TObject);
    procedure DoResizeWindow(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure grdParamsResize(Sender: TObject);
    procedure ilResizeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ilResizeMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure grdParamsMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure grdParamsSelectEditor(Sender: TObject; aCol, aRow: Integer; var Editor: TWinControl);
    procedure grdParamsDrawCell(Sender: TObject; aCol, aRow: Integer; aRect: TRect; aState: TGridDrawState);
    procedure grdParamsSelection(Sender: TObject; aCol, aRow: Integer);
    procedure grdParamsValidateEntry(Sender: TObject; aCol, aRow: Integer; const OldValue: string; var NewValue: String);
  private
    FMethods: TMethodArray;           // the symbols listed
    FRows: array of TParamRow;        // the fields behind each row
    FDragging: Boolean;               // the resize grip is held
    FDragFrom: TPoint;                // where (screen) and how big the form was when it was taken
    FDragSize: TPoint;
    FEditing: Boolean;                // a Parameter or Value cell is being edited in the grid
    FEditRow, FEditCol: Integer;      // (row of the list, 0 based)
    FPending: String;                 // the text typed when there is no editor on screen (the self-test script)
    FSkipValidate: Boolean;
    FSized: Boolean;
    FOnBeforeChange: TNotifyEvent;
    FOnAfterChange: TNotifyEvent;
    function CheckImages: TImageList;
    function GetMethod: TDrawMethod;
    function RowShow(Row: Integer): Integer;
    function RowValue(Row: Integer; out Varies: Boolean): String;
    function RowName(Row: Integer): String;
    procedure CommitCell(ARow, ACol: Integer; const AText: String);
    function CellEditable(ARow, ACol: Integer): Boolean;
    function EditorText: String;
    function RefsValid: Boolean;
    procedure UpdateDelete;
    procedure DoBefore;
    procedure DoAfter;
  protected
    procedure DoHide; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    { the symbol whose parameters are listed (the one selected or the one being placed) }
    procedure Attach(AMethod: TDrawMethod);
    procedure AttachMany(const AMethods: array of TDrawMethod);
    { the text of the label above the list ('3 symbols selected') }
    function CountText: String;
    { sets the size as the grip does: not below 300 x 220, not past the work area of the screen to the right or below }
    procedure ResizeTo(NW, NH: Integer);
    procedure ReadFields;
    { a click on a cell as a person makes it: selects the row; Show? turns over; the others begin editing where that is allowed. Returns what happened: 'show', 'edit' or 'none' }
    function ClickCell(Row, Col: Integer): String;
    procedure EndEdit(Accept: Boolean);
    { the grid's late 'entry finished' event for a cell that is no longer being edited, as it arrives after a click on Show? ended the edit (for the self-test script) }
    procedure LateEntry(Row, Col: Integer; const AText: String);
    function Editing: Boolean;
    function EditText: String;
    procedure SetEditText(const AText: String);
    procedure AddParameter;
    procedure DeleteParameter;
    function RowCount: Integer;
    function RowText(Row: Integer): String;
    function SelectedRow: Integer;
    function DeleteEnabled: Boolean;
    property Method: TDrawMethod read GetMethod;
    property OnBeforeChange: TNotifyEvent read FOnBeforeChange write FOnBeforeChange;
    property OnAfterChange: TNotifyEvent read FOnAfterChange write FOnAfterChange;
  end;

implementation


uses UStrings;

{$R *.lfm}

const
  SPACING = 5;        // the space between the symbol and its texts (CEditDlgMethodEdit)

{ ===========================================================================
  TfrmSymbolPropList.DoBefore / DoAfter  (procedures)
  Notes:
    Tell the owner a change is about to be made and has been made.
  =========================================================================== }
procedure TfrmSymbolPropList.DoBefore;
begin
  if Assigned(FOnBeforeChange) then
    FOnBeforeChange(Self);
end;

procedure TfrmSymbolPropList.DoAfter;
begin
  if Assigned(FOnAfterChange) then
    FOnAfterChange(Self);
end;

{ ===========================================================================
  TfrmSymbolPropList.Attach / AttachMany  (procedures)
  Parameters:
    AMethod: TDrawMethod - the symbol; AMethods: the selected symbols (nil entries are left out)
  Notes:
    Lists the parameters of the symbol, or of all the selected symbols together.
  =========================================================================== }
procedure TfrmSymbolPropList.Attach(AMethod: TDrawMethod);
begin
  if AMethod = nil then
    AttachMany([])
  else
    AttachMany([AMethod]);
end;

procedure TfrmSymbolPropList.AttachMany(const AMethods: array of TDrawMethod);
var
  i: Integer;
begin
  EndEdit(False);
  SetLength(FMethods, 0);
  for i := 0 to High(AMethods) do
    if AMethods[i] <> nil then
    begin
      SetLength(FMethods, Length(FMethods) + 1);
      FMethods[High(FMethods)] := AMethods[i];
    end;
  ReadFields;
end;

function TfrmSymbolPropList.GetMethod: TDrawMethod;
begin
  if Length(FMethods) > 0 then
    Result := FMethods[0]
  else
    Result := nil;
end;

function TfrmSymbolPropList.CountText: String;
begin
  if Length(FMethods) = 0 then
    Result := ''
  else if Length(FMethods) = 1 then
    Result := '1 symbol selected'
  else
    Result := IntToStr(Length(FMethods)) + ' symbols selected';
end;

{ ===========================================================================
  TfrmSymbolPropList.ReadFields  (procedure)
  Notes:
    CEditDlgMethodEdit::ReadFields: a row for each field but the reference and the always hidden ones: its description, Yes or No, and its value. With several symbols a row is
    one description (the n-th field of that description counts as the same parameter in each symbol) that every selected symbol has; Show? says Mixed and the value (varies) where the symbols differ. Nothing is
    selected, so Delete is off.
  =========================================================================== }
procedure TfrmSymbolPropList.ReadFields;
var
  i, m, f, At, Occ, R: Integer;
  Keys: TStringList;
  Key: String;
  Varies: Boolean;
begin
  if not FSized then
  begin
    FSized := True;
    grdParams.ColCount := 3;
    grdParams.FixedRows := 1;
    grdParams.FixedCols := 0;
    grdParams.ColWidths[0] := 90;
    grdParams.ColWidths[1] := 50;
    grdParamsResize(nil);
  end;
  lblCount.Caption := CountText;
  grdParams.RowCount := 1;
  grdParams.Cells[0, 0] := rsParameter;
  grdParams.Cells[1, 0] := rsShow;
  grdParams.Cells[2, 0] := rsValue;
  SetLength(FRows, 0);
  Keys := TStringList.Create;
  try
    Keys.CaseSensitive := True;
    for m := 0 to High(FMethods) do
    begin
      for f := 0 to High(FMethods[m].Fields) do
      begin
        if (f = FIELD_REF) or (FMethods[m].Fields[f].FieldType = always_hidden) then
          Continue;
        Occ := 0;
        for i := 0 to f - 1 do
          if (i <> FIELD_REF) and (FMethods[m].Fields[i].FieldType <> always_hidden) and (FMethods[m].Fields[i].Description = FMethods[m].Fields[f].Description) then
            Inc(Occ);
        Key := FMethods[m].Fields[f].Description + #1 + IntToStr(Occ);
        At := Keys.IndexOf(Key);
        if At < 0 then
        begin
          At := Keys.Add(Key);
          SetLength(FRows, At + 1);
          SetLength(FRows[At].Refs, 0);
          FRows[At].Extra := True;
        end;
        R := Length(FRows[At].Refs);
        SetLength(FRows[At].Refs, R + 1);
        FRows[At].Refs[R].M := m;
        FRows[At].Refs[R].F := f;
        if FMethods[m].Fields[f].FieldType <> extra_parameter then
          FRows[At].Extra := False;
      end;
    end;
  finally
    Keys.Free;
  end;
  R := 0;                         // (only the parameters every selected symbol has are listed)
  for i := 0 to High(FRows) do
    if Length(FRows[i].Refs) = Length(FMethods) then
    begin
      FRows[R] := FRows[i];
      Inc(R);
    end;
  SetLength(FRows, R);
  grdParams.RowCount := 1 + Length(FRows);
  for i := 0 to High(FRows) do
  begin
    grdParams.Cells[0, i + 1] := RowName(i);
    case RowShow(i) of
      1: grdParams.Cells[1, i + 1] := rsYes;
      0: grdParams.Cells[1, i + 1] := rsNo;
    else
      grdParams.Cells[1, i + 1] := rsMixed;
    end;
    grdParams.Cells[2, i + 1] := RowValue(i, Varies);
  end;
  UpdateDelete;
end;

{ ===========================================================================
  TfrmSymbolPropList.RowShow / RowValue / RowName  (functions)
  Parameters:
    Row: Integer - the row of the list (0 based)
  Returns:
    RowShow: 1 when every symbol shows the field, 0 when none does, -1 when they differ
    RowValue: the value the symbols share, (varies) when they differ (Varies true)
    RowName: the description the symbols share (the first one's when they differ)
  =========================================================================== }
function TfrmSymbolPropList.RowShow(Row: Integer): Integer;
var
  k, V: Integer;
begin
  Result := -2;
  for k := 0 to High(FRows[Row].Refs) do
  begin
    V := Ord(FMethods[FRows[Row].Refs[k].M].Fields[FRows[Row].Refs[k].F].Show <> 0);
    if Result = -2 then
      Result := V
    else if Result <> V then
      Exit(-1);
  end;
end;

function TfrmSymbolPropList.RowValue(Row: Integer; out Varies: Boolean): String;
var
  k: Integer;
  V: String;
begin
  Varies := False;
  Result := '';
  for k := 0 to High(FRows[Row].Refs) do
  begin
    V := FMethods[FRows[Row].Refs[k].M].Fields[FRows[Row].Refs[k].F].Value;
    if k = 0 then
      Result := V
    else if Result <> V then
      Varies := True;
  end;
  if Varies then
    Result := '(varies)';
end;

function TfrmSymbolPropList.RowName(Row: Integer): String;
begin
  Result := FMethods[FRows[Row].Refs[0].M].Fields[FRows[Row].Refs[0].F].Description;
end;

{ ===========================================================================
  TfrmSymbolPropList.UpdateDelete  (procedure)
  Notes:
    Delete is enabled for a selected parameter that was added in the schematic editor (extra_parameter) and for no other.
  =========================================================================== }
procedure TfrmSymbolPropList.UpdateDelete;
begin
  btnDelete.Enabled := DeleteEnabled;
end;

function TfrmSymbolPropList.DeleteEnabled: Boolean;
var
  R: Integer;
begin
  R := SelectedRow;
  Result := (R >= 0) and (R <= High(FRows)) and FRows[R].Extra;
end;

function TfrmSymbolPropList.SelectedRow: Integer;
begin
  if (grdParams.Row < 1) or (grdParams.Row > Length(FRows)) then
    Result := -1
  else
    Result := grdParams.Row - 1;
end;

function TfrmSymbolPropList.RowCount: Integer;
begin
  Result := grdParams.RowCount - 1;
end;

{ ===========================================================================
  TfrmSymbolPropList.RowText  (function)
  Parameters:
    Row: Integer
  Returns:
    String - parameter|show|value as listed
  =========================================================================== }
function TfrmSymbolPropList.RowText(Row: Integer): String;
begin
  Result := grdParams.Cells[0, Row + 1] + '|' + grdParams.Cells[1, Row + 1] + '|' + grdParams.Cells[2, Row + 1];
end;

{ ===========================================================================
  TfrmSymbolPropList.CellEditable  (function)
  Parameters:
    ARow, ACol: Integer - the cell (row of the list, 0 based)
  Returns:
    Boolean - True for a Value, and for the name of a parameter that was added here (the names that come from the library are fixed); never for Show?
  =========================================================================== }
function TfrmSymbolPropList.CellEditable(ARow, ACol: Integer): Boolean;
begin
  Result := (ARow >= 0) and (ARow <= High(FRows)) and ((ACol = 2) or ((ACol = 0) and FRows[ARow].Extra));
end;

{ ===========================================================================
  TfrmSymbolPropList.RefsValid  (function)
  Returns:
    Boolean - every row of the list points at a symbol and a field that still exist
  Notes:
    The list can be told to hide or reload while symbols were changed under it (a symbol text edited, then the window closed); a row that points at a symbol no longer held is never read.
  =========================================================================== }
function TfrmSymbolPropList.RefsValid: Boolean;
var
  i, k: Integer;
begin
  Result := False;
  for i := 0 to High(FRows) do
    for k := 0 to High(FRows[i].Refs) do
      if (FRows[i].Refs[k].M < 0) or (FRows[i].Refs[k].M > High(FMethods)) or (FMethods[FRows[i].Refs[k].M] = nil) or
         (FRows[i].Refs[k].F < 0) or (FRows[i].Refs[k].F > High(FMethods[FRows[i].Refs[k].M].Fields)) then
        Exit;
  Result := True;
end;

{ ===========================================================================
  TfrmSymbolPropList.EditorText  (function)
  Returns:
    String - the text in the cell being edited: what is in the editor on screen, or what the script typed
  =========================================================================== }
function TfrmSymbolPropList.EditorText: String;
begin
  if grdParams.EditorMode and (grdParams.Editor is TCustomEdit) then
    Result := TCustomEdit(grdParams.Editor).Text
  else
    Result := FPending;
end;

{ ===========================================================================
  TfrmSymbolPropList.CommitCell  (procedure)
  Parameters:
    ARow, ACol: Integer - the cell (row of the list, 0 based; column 0 the name, 2 the value)
    const AText: String - the text now in it
  Notes:
    CEditDlgMethodEdit::EndEdit: the text becomes the name or the value of the field, as one change (nothing when it is the same text).
  =========================================================================== }
procedure TfrmSymbolPropList.CommitCell(ARow, ACol: Integer; const AText: String);
var
  k: Integer;
  Same, Varies: Boolean;
  Cur: String;
begin
  if not CellEditable(ARow, ACol) then
    Exit;
  if ACol = 0 then
    Cur := RowName(ARow)
  else
    Cur := RowValue(ARow, Varies);
  if (ACol = 2) and Varies and (AText = '(varies)') then
    Exit;                                  // (left as it was: the symbols keep their own values)
  Same := True;
  for k := 0 to High(FRows[ARow].Refs) do
    with FMethods[FRows[ARow].Refs[k].M].Fields[FRows[ARow].Refs[k].F] do
      if ((ACol = 0) and (Description <> AText)) or ((ACol = 2) and (Value <> AText)) then
        Same := False;
  if Same then
    Exit;
  DoBefore;
  for k := 0 to High(FRows[ARow].Refs) do
    with FMethods[FRows[ARow].Refs[k].M].Fields[FRows[ARow].Refs[k].F] do
      if ACol = 0 then
        Description := AText
      else
        Value := AText;
  grdParams.Cells[ACol, ARow + 1] := AText;
  DoAfter;
end;

{ ===========================================================================
  TfrmSymbolPropList.ClickCell  (function)
  Parameters:
    Row, Col: Integer - the cell (row of the list, 0 based; -1 for no row)
  Returns:
    String - 'show' (the field was turned on or off), 'edit' (the cell is being edited right in the grid) or 'none'
  Notes:
    CEditDlgMethodEdit::OnClickList. An edit open on another cell ends first (its text is kept). Show? turns the field over; Parameter edits the name of an extra parameter only;
    Value edits any value. The editor is the grid's own, in the cell.
  =========================================================================== }
function TfrmSymbolPropList.ClickCell(Row, Col: Integer): String;
var
  k, NewShow: Integer;
begin
  Result := 'none';
  if Length(FMethods) = 0 then
    Exit;
  EndEdit(True);
  if (Row < 0) or (Row > High(FRows)) then
  begin
    UpdateDelete;
    Exit;
  end;
  grdParams.Row := Row + 1;
  grdParams.Col := Col;
  UpdateDelete;
  if Col = 1 then
  begin
    DoBefore;
    NewShow := Ord(RowShow(Row) <> 1);        // (all shown: hide them all; hidden or mixed: show them all)
    for k := 0 to High(FRows[Row].Refs) do
      FMethods[FRows[Row].Refs[k].M].Fields[FRows[Row].Refs[k].F].Show := NewShow;
    grdParams.Cells[1, Row + 1] := IfThen(NewShow <> 0, rsYes, rsNo);
    DoAfter;
    Result := 'show';
  end
  else if CellEditable(Row, Col) then
  begin
    FEditing := True;
    FEditRow := Row;
    FEditCol := Col;
    FPending := grdParams.Cells[Col, Row + 1];
    if Visible then
      grdParams.EditorMode := True;
    Result := 'edit';
  end;
end;

{ ===========================================================================
  TfrmSymbolPropList.EndEdit  (procedure)
  Parameters:
    Accept: Boolean - keep the text typed
  Notes:
    Ends the edit in the grid: the text becomes the name or the value of the field (one change), or, with Accept false, the cell shows what the field has again.
  =========================================================================== }
procedure TfrmSymbolPropList.EndEdit(Accept: Boolean);
var
  T: String;
  Varies: Boolean;
begin
  if not FEditing then
    Exit;
  FEditing := False;
  T := EditorText;
  FSkipValidate := True;
  try
    if grdParams.EditorMode then
      grdParams.EditorMode := False;
  finally
    FSkipValidate := False;
  end;
  if (Length(FMethods) = 0) or (FEditRow > High(FRows)) or (not RefsValid) then
    Exit;
  if Accept then
    CommitCell(FEditRow, FEditCol, T)
  else if FEditCol = 0 then
    grdParams.Cells[0, FEditRow + 1] := RowName(FEditRow)
  else
    grdParams.Cells[2, FEditRow + 1] := RowValue(FEditRow, Varies);
end;

function TfrmSymbolPropList.Editing: Boolean;
begin
  Result := FEditing;
end;

function TfrmSymbolPropList.EditText: String;
begin
  if FEditing then
    Result := EditorText
  else
    Result := '';
end;

procedure TfrmSymbolPropList.SetEditText(const AText: String);
begin
  if not FEditing then
    Exit;
  FPending := AText;
  if grdParams.EditorMode and (grdParams.Editor is TCustomEdit) then
    TCustomEdit(grdParams.Editor).Text := AText;
end;

{ ===========================================================================
  TfrmSymbolPropList.grdParamsSelectEditor  (procedure)
  Parameters:
    Sender: TObject
    aCol, aRow: Integer - the cell being entered (the grid's rows: 0 is the header)
    var Editor: TWinControl - the editor to use (in/out: nil gives none)
  Notes:
    Only a Value and the name of an added parameter have an editor; Show? is a yes/no turned over by a click, and the library's names are fixed.
  =========================================================================== }
procedure TfrmSymbolPropList.grdParamsSelectEditor(Sender: TObject; aCol, aRow: Integer; var Editor: TWinControl);
begin
  if not CellEditable(aRow - 1, aCol) then
    Editor := nil
  else
  begin
    FEditing := True;
    FEditRow := aRow - 1;
    FEditCol := aCol;
  end;
end;

{ ===========================================================================
  TfrmSymbolPropList.grdParamsValidateEntry  (procedure)
  Parameters:
    Sender: TObject
    aCol, aRow: Integer - the cell
    const OldValue: string - what it held
    var NewValue: String - what was typed
  Notes:
    The grid finished an edit (Enter, or another cell chosen): the text is kept as one change.
  =========================================================================== }
procedure TfrmSymbolPropList.grdParamsValidateEntry(Sender: TObject; aCol, aRow: Integer; const OldValue: string; var NewValue: String);
begin
  { the grid also reports an entry as finished when the cell is left by a click somewhere else, after this form has already taken the text (EndEdit) and the list has been
    rebuilt, when the editor holds nothing: that late report must not be taken as the text of the cell (it blanked the name of a parameter when Show? was clicked) }
  if FSkipValidate or (not FEditing) or (aRow - 1 <> FEditRow) or (aCol <> FEditCol) then
    Exit;
  FEditing := False;
  CommitCell(aRow - 1, aCol, NewValue);
end;

{ ===========================================================================
  TfrmSymbolPropList.LateEntry  (procedure)
  Parameters:
    Row: Integer - the row of the list (0 based)
    Col: Integer - the column
    const AText: String - what the grid reports as typed
  Notes:
    Delivers to the form what the grid's OnValidateEntry delivers after a click on another cell has ended an edit.
  =========================================================================== }
procedure TfrmSymbolPropList.LateEntry(Row, Col: Integer; const AText: String);
var
  V: String;
begin
  V := AText;
  grdParamsValidateEntry(grdParams, Col, Row + 1, '', V);
end;

{ ===========================================================================
  TfrmSymbolPropList.CheckImages  (function)
  Returns:
    TImageList - the check box pictures of the Show? column: index 0 is checked (on), 1 is unchecked (off)
  Notes:
    The shared control form's ilChecked when it has one (so the pictures can be changed there, keeping that order); otherwise two boxes drawn here, once.
  =========================================================================== }
var
  GBoxes: TImageList = nil;

function TfrmSymbolPropList.CheckImages: TImageList;
var
  C: TComponent;
  B: TBitmap;
  i: Integer;
begin
  C := nil;
  if Application.MainForm <> nil then
    C := Application.MainForm.FindComponent('ilChecked');
  if C is TImageList then
    Exit(TImageList(C));
  if GBoxes = nil then
  begin
    GBoxes := TImageList.Create(Application);
    GBoxes.Width := 14;
    GBoxes.Height := 14;
    for i := 0 to 1 do
    begin
      B := TBitmap.Create;
      try
        B.SetSize(14, 14);
        B.Canvas.Brush.Color := clWindow;
        B.Canvas.Pen.Color := clGray;
        B.Canvas.Rectangle(0, 0, 14, 14);
        if i = 0 then
        begin
          B.Canvas.Pen.Color := clBlack;
          B.Canvas.Pen.Width := 2;
          B.Canvas.MoveTo(3, 7);
          B.Canvas.LineTo(6, 10);
          B.Canvas.LineTo(11, 3);
        end;
        GBoxes.Add(B, nil);
      finally
        B.Free;
      end;
    end;
  end;
  Result := GBoxes;
end;

{ ===========================================================================
  TfrmSymbolPropList.grdParamsDrawCell  (procedure)
  Parameters:
    Sender: TObject
    aCol, aRow: Integer - the cell
    aRect: TRect - where it is
    aState: TGridDrawState
  Notes:
    The Show? column shows a check box instead of text: the picture is the field's Show cast to an Ord (0 checked, 1 not), centred in the cell.
  =========================================================================== }
procedure TfrmSymbolPropList.grdParamsDrawCell(Sender: TObject; aCol, aRow: Integer; aRect: TRect; aState: TGridDrawState);
var
  IL: TImageList;
begin
  if (aCol <> 1) or (aRow < 1) then
    Exit;
  IL := CheckImages;
  grdParams.Canvas.FillRect(aRect);
  IL.Draw(grdParams.Canvas, aRect.Left + (aRect.Right - aRect.Left - IL.Width) div 2, aRect.Top + (aRect.Bottom - aRect.Top - IL.Height) div 2,
    Ord(grdParams.Cells[1, aRow] <> 'Yes'));
  if grdParams.Cells[1, aRow] = 'Mixed' then      // (the symbols differ: an empty box with a dash)
  begin
    grdParams.Canvas.Pen.Color := clBlack;
    grdParams.Canvas.Pen.Width := 2;
    grdParams.Canvas.MoveTo((aRect.Left + aRect.Right) div 2 - 3, (aRect.Top + aRect.Bottom) div 2);
    grdParams.Canvas.LineTo((aRect.Left + aRect.Right) div 2 + 4, (aRect.Top + aRect.Bottom) div 2);
    grdParams.Canvas.Pen.Width := 1;
  end;
end;

procedure TfrmSymbolPropList.grdParamsSelection(Sender: TObject; aCol, aRow: Integer);
begin
  UpdateDelete;
end;

{ ===========================================================================
  TfrmSymbolPropList.grdParamsMouseDown  (procedure)
  Parameters:
    Sender: TObject
    Button: TMouseButton
    Shift: TShiftState
    X, Y: Integer - where the mouse is pressed
  Notes:
    A click on Show? turns the field over at once (the grid has no editor there); a click on a Value or an added name goes to the grid, which puts its editor right in the cell.
  =========================================================================== }
procedure TfrmSymbolPropList.grdParamsMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  C, R: Integer;
begin
  if Button <> mbLeft then
    Exit;
  grdParams.MouseToCell(X, Y, C, R);
  if (R >= 1) and (C = 1) then
    ClickCell(R - 1, 1);
end;

{ ===========================================================================
  TfrmSymbolPropList.AddParameter  (procedure)
  Notes:
    CEditDlgMethodEdit::OnAdd: a new field 'Other' with the value '..', shown, of the extra_parameter type, put below the lowest field.
  =========================================================================== }
procedure TfrmSymbolPropList.AddParameter;
var
  P: TDPoint;
  i, m: Integer;
  F: TMethodField;
begin
  if Length(FMethods) = 0 then
    Exit;
  EndEdit(True);
  DoBefore;
  for m := 0 to High(FMethods) do
  begin
    P := FMethods[m].Fields[0].Position;
    for i := 0 to High(FMethods[m].Fields) do
      if FMethods[m].Fields[i].Position.y > P.y then
        P := FMethods[m].Fields[i].Position;
    P.y := P.y - PIN_HEIGHT + (SPACING div 2);
    F.Description := 'Other';
    F.Position := P;
    F.Show := 1;
    F.FieldType := extra_parameter;
    F.Value := '..';
    SetLength(FMethods[m].Fields, Length(FMethods[m].Fields) + 1);
    FMethods[m].Fields[High(FMethods[m].Fields)] := F;
  end;
  DoAfter;
  ReadFields;
  grdParams.Row := grdParams.RowCount - 1;      // (the new parameter is the one selected)
end;

{ ===========================================================================
  TfrmSymbolPropList.DeleteParameter  (procedure)
  Notes:
    CEditDlgMethodEdit::OnDelete: takes the selected parameter away from every selected symbol (only one that was added here can be selected for it).
  =========================================================================== }
procedure TfrmSymbolPropList.DeleteParameter;
var
  i, k, F: Integer;
  Row: TParamRow;
begin
  if not DeleteEnabled then
    Exit;
  EndEdit(True);
  Row := FRows[SelectedRow];
  DoBefore;
  for k := 0 to High(Row.Refs) do
  begin
    F := Row.Refs[k].F;
    with FMethods[Row.Refs[k].M] do
    begin
      for i := F to High(Fields) - 1 do
        Fields[i] := Fields[i + 1];
      SetLength(Fields, Length(Fields) - 1);
    end;
  end;
  DoAfter;
  ReadFields;
end;

procedure TfrmSymbolPropList.btnAddClick(Sender: TObject);
begin
  AddParameter;
end;

procedure TfrmSymbolPropList.btnDeleteClick(Sender: TObject);
begin
  DeleteParameter;
end;

{ ===========================================================================
  TfrmSymbolPropList.ilResizeMouseDown / DoResizeWindow / ilResizeMouseUp  (procedures)
  Parameters:
    Sender: TObject; Button, Shift, X, Y: as for the mouse events of the grip (ilResize, the corner picture)
  Notes:
    The grip in the lower right corner resizes the form like a window: pressed, it remembers the form's size and the pointer's place on the screen (the pointer is followed on the
    screen, since the grip moves with the form); moved, the form gets the size at the press plus how far the pointer went, never below 300 x 220 and, when it would run off the work area of the screen, moved up and left to stay on it. The list drops down again at the size it was left at.
  =========================================================================== }
procedure TfrmSymbolPropList.ilResizeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then
    Exit;
  FDragging := True;
  FDragFrom := Mouse.CursorPos;
  FDragSize := Point(Width, Height);
  BeginKeepOpen;
end;

procedure TfrmSymbolPropList.DoResizeWindow(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
begin
  if not FDragging then
    Exit;
  P := Mouse.CursorPos;
  ResizeTo(FDragSize.X + (P.X - FDragFrom.X), FDragSize.Y + (P.Y - FDragFrom.Y));
end;

procedure TfrmSymbolPropList.ResizeTo(NW, NH: Integer);
var
  W: TRect;
  L, T: Integer;
begin
  W := Screen.MonitorFromPoint(Point(Left, Top)).WorkareaRect;
  if NW > W.Right - W.Left then
    NW := W.Right - W.Left;
  if NH > W.Bottom - W.Top then
    NH := W.Bottom - W.Top;
  if NW < Constraints.MinWidth then
    NW := Constraints.MinWidth;          // (300 x 220 at 96 dpi, set in the form file; the form scales its sizes to the screen's dpi, so does the minimum)
  if NH < Constraints.MinHeight then
    NH := Constraints.MinHeight;
  L := Left;
  T := Top;
  if L + NW > W.Right then
    L := W.Right - NW;       // (a list that would run off the screen moves up and left instead of being cut short, as Popup does)
  if T + NH > W.Bottom then
    T := W.Bottom - NH;
  SetBounds(L, T, NW, NH);
end;

procedure TfrmSymbolPropList.ilResizeMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if not FDragging then
    Exit;
  FDragging := False;
  EndKeepOpen;
end;

{ ===========================================================================
  TfrmSymbolPropList.grdParamsResize  (procedure)
  Notes:
    The Value column takes the width the other two leave.
  =========================================================================== }
procedure TfrmSymbolPropList.grdParamsResize(Sender: TObject);
begin
  if FSized and (grdParams.ColCount = 3) then
    grdParams.ColWidths[2] := Max(40, grdParams.ClientWidth - (grdParams.ColWidths[0] + grdParams.ColWidths[1] + 1));
end;

{ ===========================================================================
  TfrmSymbolPropList.DoHide  (procedure)
  Notes:
    An edit that is open when the list closes (a click somewhere else) is kept.
  =========================================================================== }
procedure TfrmSymbolPropList.DoHide;
begin
  { a list that is hidden because it is being destroyed (the Properties panel was rebuilt under it) holds symbols that may have been replaced: nothing is read from them }
  if csDestroying in ComponentState then
    FEditing := False;
  EndEdit(True);
  SetLength(FMethods, 0);      { (the symbols may be gone by the time the list opens again) }
  SetLength(FRows, 0);
  inherited DoHide;
end;

{ ===========================================================================
  TfrmSymbolPropList.KeyDown  (procedure)
  Parameters:
    var Key: Word
    Shift: TShiftState
  Notes:
    Esc while a value is being edited drops the edit (the form stays); otherwise it closes the form.
  =========================================================================== }
procedure TfrmSymbolPropList.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and FEditing then
  begin
    Key := 0;
    EndEdit(False);
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

end.
