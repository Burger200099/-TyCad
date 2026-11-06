// SPDX-License-Identifier: LGPL-2.1-or-later
{ The table editor: a small window that stays on top while a table is chosen (or floating on the pointer waiting to be placed). Its grid is the cells of the table,
  the first row being the column titles; it works like a spreadsheet (arrow keys, Tab, Enter, F2) and the pop-up menu inserts and deletes rows and columns. The check
  box shows or hides the titles, the drop-down chooses the lines (solid, dashed, hidden). Every change goes straight into the table; the owner is told before the
  first change of a step (to take the undo snapshot) and after it (to keep the step and redraw). Licence: LGPL 2.1 or later, as the rest of this port. }
unit Ftable;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Grids, Menus, LCLType, Math, UDrawingObjects, UTable, UTableLinks, UDesign, FtablePick, Registry, USettings;

type

  { TfrmTable }

  TfrmTable = class(TForm)
    cbAlwaysOnTop: TCheckBox;
    cbGrid: TComboBox;
    cbShowTitles: TCheckBox;
    lbGrid: TLabel;
    miAddColumn: TMenuItem;
    miAddRow: TMenuItem;
    miDeleteColumn: TMenuItem;
    miDeleteRow: TMenuItem;
    miInsertColumn: TMenuItem;
    miInsertRow: TMenuItem;
    miSepRows: TMenuItem;
    miSepLink: TMenuItem;
    miUnlink: TMenuItem;
    plTop: TPanel;
    pmGrid: TPopupMenu;
    sgTable: TStringGrid;
    procedure cbAlwaysOnTopChange(Sender: TObject);
    procedure cbGridChange(Sender: TObject);
    procedure cbShowTitlesChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormDestroy(Sender: TObject);
    procedure FormHide(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure miAddColumnClick(Sender: TObject);
    procedure miAddRowClick(Sender: TObject);
    procedure miDeleteColumnClick(Sender: TObject);
    procedure miDeleteRowClick(Sender: TObject);
    procedure miInsertColumnClick(Sender: TObject);
    procedure miInsertRowClick(Sender: TObject);
    procedure miUnlinkClick(Sender: TObject);
    procedure sgTableDrawCell(Sender: TObject; aCol, aRow: Integer; aRect: TRect; aState: TGridDrawState);
    procedure sgTableMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure sgTableMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure DropDownLater(Data: PtrInt);
    procedure sgTableExit(Sender: TObject);
    procedure sgTableKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure sgTablePrepareCanvas(Sender: TObject; aCol, aRow: Integer; aState: TGridDrawState);
    procedure sgTableSelectCell(Sender: TObject; aCol, aRow: Integer; var CanSelect: Boolean);
    procedure sgTableSetEditText(Sender: TObject; ACol, ARow: Integer; const Value: string);
  private
    FTable: TDrawTable;
    FLoading: Boolean;
    FSheet: TDesignSheet;                // the sheet the table is on: its texts are what a cell can be linked to
    FStepOpen: Boolean;                  // a change is under way (the owner has been told to take its snapshot)
    FOnBefore, FOnAfter, FOnLive: TNotifyEvent;
    FBoundsLoaded, FShownOnce: Boolean;
    FArrowCell: TPoint;                  // (column, row) the press on the arrow was in
    FArrowDown: Boolean;                 // the press was on the arrow: the list opens when the button is released
    procedure LoadBounds;
    procedure SaveBounds;
    procedure FitOnScreen;
    procedure BeginStep;
    procedure EndStep;
    procedure LoadFromTable;
    procedure Changed;
  public
    { shows the table in the grid; nil for none (the window is not hidden: the owner does that) }
    procedure SetTable(ATable: TDrawTable; ASheet: TDesignSheet = nil);
    { the cells show the texts of the objects as they are now (the drawing changed); not while a cell is being typed in }
    procedure RefreshCells;
    { the list of the arrow: what the sheet has that a cell can show (sorted); the self-test script and the arrow use it }
    function Sources: TTextSources;
    procedure DoLinkCell(ARow, ACol: Integer; const Src: TTextSource);
    procedure DoUnlinkCell(ARow, ACol: Integer);
    procedure DropDownList(ARow, ACol: Integer);
    property Table: TDrawTable read FTable;
    { before the first change of a step and after it }
    property OnBeforeChange: TNotifyEvent read FOnBefore write FOnBefore;
    property OnAfterChange: TNotifyEvent read FOnAfter write FOnAfter;
    { the table changed while a step is still open (a key typed in a cell): redraw only }
    property OnLiveChange: TNotifyEvent read FOnLive write FOnLive;
    { what typing in a cell, the pop-up menu and the two controls do (the self-test script calls them too) }
    procedure EditCell(ARow, ACol: Integer; const S: String);
    procedure DoInsertRow(At: Integer);
    procedure DoDeleteRow(At: Integer);
    procedure DoInsertColumn(At: Integer);
    procedure DoDeleteColumn(At: Integer);
    procedure DoShowTitles(Value: Boolean);
    procedure DoGridStyle(Value: Integer);
    { On: the window stays on top of every program (fsSystemStayOnTop); off: on top of this program only (the main window is its popup parent) }
    procedure DoAlwaysOnTop(Value: Boolean);
    procedure FinishEdit;
  end;

var
  frmTable: TfrmTable;

implementation

{$R *.lfm}

{ ===========================================================================
  TfrmTable.BeginStep  (procedure)
  Notes:
    The owner takes the undo snapshot before the first change of a step.
  =========================================================================== }
procedure TfrmTable.BeginStep;
begin
  if FStepOpen then
    Exit;
  FStepOpen := True;
  if Assigned(FOnBefore) then
    FOnBefore(Self);
end;

{ ===========================================================================
  TfrmTable.EndStep  (procedure)
  Notes:
    The owner keeps the step and redraws.
  =========================================================================== }
procedure TfrmTable.EndStep;
begin
  if not FStepOpen then
    Exit;
  FStepOpen := False;
  if Assigned(FOnAfter) then
    FOnAfter(Self);
end;

{ ===========================================================================
  TfrmTable.FinishEdit  (procedure)
  Notes:
    Ends the step of the cell being typed in (called when the cursor leaves the cell or the grid, and before any other change).
  =========================================================================== }
procedure TfrmTable.FinishEdit;
begin
  EndStep;
end;

{ ===========================================================================
  TfrmTable.Changed  (procedure)
  Notes:
    The table has changed: it fits its text again and the owner is told through the end of the step.
  =========================================================================== }
procedure TfrmTable.Changed;
begin
  if FTable <> nil then
    FTable.Fit;
end;

{ ===========================================================================
  TfrmTable.LoadFromTable  (procedure)
  Notes:
    Fills the grid and the two controls from the table.
  =========================================================================== }
procedure TfrmTable.LoadFromTable;
var
  r, c: Integer;
begin
  FLoading := True;
  try
    if FTable = nil then
    begin
      sgTable.RowCount := 1; sgTable.ColCount := 1; sgTable.Cells[0, 0] := '';
      Exit;
    end;
    sgTable.ColCount := FTable.Cols;
    sgTable.RowCount := FTable.Rows;
    for r := 0 to FTable.Rows - 1 do
      for c := 0 to FTable.Cols - 1 do
        sgTable.Cells[c, r] := FTable.Cells[r][c];
    cbShowTitles.Checked := FTable.ShowTitles <> 0;
    cbGrid.ItemIndex := FTable.GridStyle;
  finally
    FLoading := False;
  end;
end;

{ ===========================================================================
  TfrmTable.SetTable  (procedure)
  Parameters:
    ATable: TDrawTable - the table to edit, or nil
  =========================================================================== }
procedure TfrmTable.SetTable(ATable: TDrawTable; ASheet: TDesignSheet);
begin
  EndStep;
  FTable := ATable;
  FSheet := ASheet;
  LoadFromTable;
end;

procedure TfrmTable.RefreshCells;
begin
  if (FTable <> nil) and (not FStepOpen) and (not sgTable.EditorMode) then
    LoadFromTable;
end;

function TfrmTable.Sources: TTextSources;
begin
  Result := CollectTextSources(FSheet);
end;

{ ===========================================================================
  TfrmTable.DoLinkCell  (procedure)
  Parameters:
    ARow, ACol: Integer - the cell
    const Src: TTextSource - the text it is to show (its object and field)
  Notes:
    The cell now follows that text: it shows it and changes when the object's text does.
  =========================================================================== }
procedure TfrmTable.DoLinkCell(ARow, ACol: Integer; const Src: TTextSource);
var
  Txt: String;
begin
  if (FTable = nil) or (Src.Obj = nil) or (Src.Obj.Id = 0) then
    Exit;
  EndStep; BeginStep;
  FTable.SetLink(ARow, ACol, Src.Obj.Id, Src.Field);
  if SourceText(Src.Obj, Src.Field, Txt) then
    FTable.SetShown(ARow, ACol, Txt);
  Changed; LoadFromTable; EndStep;
end;

{ the cell keeps the text it shows but no longer follows the object }
procedure TfrmTable.DoUnlinkCell(ARow, ACol: Integer);
begin
  if (FTable = nil) or (not FTable.IsLinked(ARow, ACol)) then
    Exit;
  EndStep; BeginStep;
  FTable.SetLink(ARow, ACol, 0, -1);
  LoadFromTable; EndStep;
end;

{ ===========================================================================
  TfrmTable.DropDownList  (procedure)
  Parameters:
    ARow, ACol: Integer - the cell
  Notes:
    Drops the list of the texts of the sheet under the cell (Kind:"text", Symbol R1:Value:"10k" ...); the one chosen is linked to the cell.
  =========================================================================== }
procedure TfrmTable.DropDownList(ARow, ACol: Integer);
var
  Src: TTextSources;
  L: TStringList;
  R: TRect;
  P: TPoint;
  i, Chosen: Integer;
  Dlg: TfrmTablePick;
begin
  Src := Sources;
  if Length(Src) = 0 then
    Exit;
  L := TStringList.Create;
  Dlg := TfrmTablePick.Create(Self);
  try
    for i := 0 to High(Src) do
      L.Add(Src[i].Caption);
    R := sgTable.CellRect(ACol, ARow);
    P := sgTable.ClientToScreen(Point(R.Left, R.Bottom));
    Chosen := Dlg.Pick(L, P.x, P.y, Max(R.Right - R.Left, 320), R.Bottom - R.Top);
    if Chosen >= 0 then
      DoLinkCell(ARow, ACol, Src[Chosen]);
  finally
    Dlg.Free;
    L.Free;
  end;
end;

procedure TfrmTable.miUnlinkClick(Sender: TObject);
begin
  DoUnlinkCell(sgTable.Row, sgTable.Col);
end;

const
  ARROW_W = 17;

{ the arrow of the chosen cell: a small square with a triangle, at the right end of the cell }
procedure TfrmTable.sgTableDrawCell(Sender: TObject; aCol, aRow: Integer; aRect: TRect; aState: TGridDrawState);
var
  Cv: TCanvas;
  B: TRect;
  Cx, Cy: Integer;
begin
  if (aCol <> sgTable.Col) or (aRow <> sgTable.Row) or sgTable.EditorMode then
    Exit;
  Cv := sgTable.Canvas;
  B := Rect(aRect.Right - ARROW_W, aRect.Top + 1, aRect.Right - 1, aRect.Bottom - 1);
  Cv.Brush.Style := bsSolid;
  Cv.Brush.Color := clBtnFace;
  Cv.Pen.Color := clBtnShadow;
  Cv.Rectangle(B);
  Cx := (B.Left + B.Right) div 2; Cy := (B.Top + B.Bottom) div 2;
  Cv.Brush.Color := clWindowText;
  Cv.Pen.Color := clWindowText;
  Cv.Polygon([Point(Cx - 4, Cy - 2), Point(Cx + 4, Cy - 2), Point(Cx, Cy + 3)]);
end;

procedure TfrmTable.sgTableMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  c, r: Integer;
  R2: TRect;
begin
  if Button <> mbLeft then
    Exit;
  sgTable.MouseToCell(X, Y, c, r);
  if (c < 0) or (r < 0) or (c <> sgTable.Col) or (r <> sgTable.Row) or sgTable.EditorMode then
    Exit;
  R2 := sgTable.CellRect(c, r);
  FArrowDown := X >= R2.Right - ARROW_W;
  FArrowCell := Point(c, r);
end;

{ the list opens on the release, not the press: a modal window opened by the press takes the release away from the grid, which would stay in mouse-down mode }
procedure TfrmTable.sgTableMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  c, r: Integer;
  R2: TRect;
begin
  if (Button <> mbLeft) or (not FArrowDown) then
    Exit;
  FArrowDown := False;
  { (the grid may have opened its cell editor on this release: that is no reason to skip the list) }
  sgTable.MouseToCell(X, Y, c, r);
  if (c <> FArrowCell.x) or (r <> FArrowCell.y) then
    Exit;
  R2 := sgTable.CellRect(c, r);
  if X >= R2.Right - ARROW_W then
    Application.QueueAsyncCall(@DropDownLater, 0);
end;

procedure TfrmTable.DropDownLater(Data: PtrInt);
begin
  if Visible and (FArrowCell.y >= 0) then
  begin
    sgTable.EditorMode := False;
    DropDownList(FArrowCell.y, FArrowCell.x);
  end;
end;

{ ===========================================================================
  TfrmTable.EditCell  (procedure)
  Parameters:
    ARow, ACol: Integer - the cell (row 0 holds the titles)
    const S: String - the new text
  =========================================================================== }
procedure TfrmTable.EditCell(ARow, ACol: Integer; const S: String);
begin
  if (FTable = nil) or FLoading or (ARow < 0) or (ARow >= FTable.Rows) or (ACol < 0) or (ACol >= FTable.Cols) then
    Exit;
  if FTable.Cell(ARow, ACol) = S then
    Exit;
  BeginStep;
  FTable.SetCell(ARow, ACol, S);
  Changed;
  if Assigned(FOnLive) then
    FOnLive(Self);         // (the picture follows each key; the undo step is kept when the cell is left)
end;

{ ===========================================================================
  TfrmTable.DoInsertRow / DoDeleteRow / DoInsertColumn / DoDeleteColumn  (procedure)
  Parameters:
    At: Integer - the row or column (an insert goes before it; the titles row stays the first)
  =========================================================================== }
procedure TfrmTable.DoInsertRow(At: Integer);
begin
  if FTable = nil then Exit;
  EndStep; BeginStep;
  FTable.InsertRow(At);
  Changed; LoadFromTable; EndStep;
end;

procedure TfrmTable.DoDeleteRow(At: Integer);
begin
  if FTable = nil then Exit;
  EndStep; BeginStep;
  FTable.DeleteRow(At);
  Changed; LoadFromTable; EndStep;
end;

procedure TfrmTable.DoInsertColumn(At: Integer);
begin
  if FTable = nil then Exit;
  EndStep; BeginStep;
  FTable.InsertCol(At);
  Changed; LoadFromTable; EndStep;
end;

procedure TfrmTable.DoDeleteColumn(At: Integer);
begin
  if FTable = nil then Exit;
  EndStep; BeginStep;
  FTable.DeleteCol(At);
  Changed; LoadFromTable; EndStep;
end;

{ ===========================================================================
  TfrmTable.DoShowTitles  (procedure)
  Parameters:
    Value: Boolean - show the first row as the column titles
  =========================================================================== }
procedure TfrmTable.DoShowTitles(Value: Boolean);
begin
  if FTable = nil then Exit;
  EndStep; BeginStep;
  FTable.ShowTitles := Ord(Value);
  Changed; LoadFromTable; EndStep;
end;

{ ===========================================================================
  TfrmTable.DoGridStyle  (procedure)
  Parameters:
    Value: Integer - 0 solid, 1 dashed, 2 hidden
  =========================================================================== }
procedure TfrmTable.DoGridStyle(Value: Integer);
begin
  if FTable = nil then Exit;
  EndStep; BeginStep;
  FTable.GridStyle := Max(0, Min(2, Value));
  Changed; LoadFromTable; EndStep;
end;

procedure TfrmTable.DoAlwaysOnTop(Value: Boolean);
var
  Was: Boolean;
  B: TRect;
begin
  Was := Visible;
  B := BoundsRect;            { changing the style makes a new window, which the system may place elsewhere }
  if Value then
    FormStyle := fsSystemStayOnTop
  else
    FormStyle := fsNormal;
  if cbAlwaysOnTop.Checked <> Value then
  begin
    FLoading := True;
    cbAlwaysOnTop.Checked := Value;
    FLoading := False;
  end;
  if Was and (not Visible) then
    Show;
  if Visible and (not EqualRect(BoundsRect, B)) then
    BoundsRect := B;
end;

procedure TfrmTable.cbAlwaysOnTopChange(Sender: TObject);
begin
  if not FLoading then
    DoAlwaysOnTop(cbAlwaysOnTop.Checked);
end;

procedure TfrmTable.cbShowTitlesChange(Sender: TObject);
begin
  if not FLoading then
    DoShowTitles(cbShowTitles.Checked);
end;

procedure TfrmTable.cbGridChange(Sender: TObject);
begin
  if not FLoading then
    DoGridStyle(cbGrid.ItemIndex);
end;

procedure TfrmTable.sgTableSetEditText(Sender: TObject; ACol, ARow: Integer; const Value: string);
begin
  if not FLoading then
    EditCell(ARow, ACol, Value);
end;

procedure TfrmTable.sgTableSelectCell(Sender: TObject; aCol, aRow: Integer; var CanSelect: Boolean);
begin
  EndStep;                 // (leaving the cell: its typing is one undo step)
end;

procedure TfrmTable.sgTableExit(Sender: TObject);
begin
  EndStep;
end;

{ ===========================================================================
  TfrmTable.sgTableKeyDown  (procedure)
  Notes:
    Spreadsheet keys: Enter moves down a cell (and adds a row at the bottom); Ctrl+Insert / Ctrl+Delete insert and delete a row, with Shift a column.
  =========================================================================== }
procedure TfrmTable.sgTableKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (not (ssCtrl in Shift)) then
  begin
    EndStep;
    if sgTable.Row >= sgTable.RowCount - 1 then
      DoInsertRow(sgTable.RowCount);
    sgTable.Row := Min(sgTable.RowCount - 1, sgTable.Row + 1);
    Key := 0;
  end
  else if ((Key = VK_F4) or ((Key = VK_DOWN) and (ssAlt in Shift))) then
  begin
    DropDownList(sgTable.Row, sgTable.Col);
    Key := 0;
  end
  else if (Key = VK_INSERT) and (ssCtrl in Shift) then
  begin
    if ssShift in Shift then DoInsertColumn(sgTable.Col) else DoInsertRow(sgTable.Row);
    Key := 0;
  end
  else if (Key = VK_DELETE) and (ssCtrl in Shift) then
  begin
    if ssShift in Shift then DoDeleteColumn(sgTable.Col) else DoDeleteRow(sgTable.Row);
    Key := 0;
  end;
end;

{ ===========================================================================
  TfrmTable.sgTablePrepareCanvas  (procedure)
  Notes:
    The titles row is drawn in bold on a grey ground (dimmed when the titles are not shown).
  =========================================================================== }
procedure TfrmTable.sgTablePrepareCanvas(Sender: TObject; aCol, aRow: Integer; aState: TGridDrawState);
begin
  if (FTable <> nil) and FTable.IsLinked(aRow, aCol) and (not (gdSelected in aState)) then
    sgTable.Canvas.Font.Color := RGBToColor(0, 64, 192);          // (a linked cell is blue)
  if aRow = 0 then
  begin
    sgTable.Canvas.Font.Style := [fsBold];
    if not (gdSelected in aState) then
      sgTable.Canvas.Brush.Color := RGBToColor(224, 224, 224);
    if (FTable <> nil) and (FTable.ShowTitles = 0) then
      sgTable.Canvas.Font.Color := clGrayText;
  end;
end;

procedure TfrmTable.miInsertRowClick(Sender: TObject);
begin
  DoInsertRow(Max(1, sgTable.Row));
end;

procedure TfrmTable.miAddRowClick(Sender: TObject);
begin
  DoInsertRow(sgTable.RowCount);
end;

procedure TfrmTable.miDeleteRowClick(Sender: TObject);
begin
  DoDeleteRow(sgTable.Row);
end;

procedure TfrmTable.miInsertColumnClick(Sender: TObject);
begin
  DoInsertColumn(sgTable.Col);
end;

procedure TfrmTable.miAddColumnClick(Sender: TObject);
begin
  DoInsertColumn(sgTable.ColCount);
end;

procedure TfrmTable.miDeleteColumnClick(Sender: TObject);
begin
  DoDeleteColumn(sgTable.Col);
end;

procedure TfrmTable.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  EndStep;
  CloseAction := caHide;
end;

const
  REG_TABLE_LEFT = 'TableEditorLeft';
  REG_TABLE_TOP = 'TableEditorTop';
  REG_TABLE_WIDTH = 'TableEditorWidth';
  REG_TABLE_HEIGHT = 'TableEditorHeight';

{ the window's place and size from the registry (only once; the form's own if there are none) }
procedure TfrmTable.LoadBounds;
var
  R: TRegistry;
  L, T, W, H: Integer;
begin
  if FBoundsLoaded then
    Exit;
  FBoundsLoaded := True;
  R := TRegistry.Create;
  try
    try
      if R.OpenKeyReadOnly(SettingsRegistryKey) and R.ValueExists(REG_TABLE_WIDTH) then
      begin
        L := R.ReadInteger(REG_TABLE_LEFT);
        T := R.ReadInteger(REG_TABLE_TOP);
        W := R.ReadInteger(REG_TABLE_WIDTH);
        H := R.ReadInteger(REG_TABLE_HEIGHT);
        if (W >= 100) and (H >= 80) then
          SetBounds(L, T, W, H);
      end;
    except
    end;
  finally
    R.Free;
  end;
end;

procedure TfrmTable.SaveBounds;
var
  R: TRegistry;
begin
  if not FShownOnce then
    Exit;
  R := TRegistry.Create;
  try
    try
      if R.OpenKey(SettingsRegistryKey, True) then
      begin
        R.WriteInteger(REG_TABLE_LEFT, Left);
        R.WriteInteger(REG_TABLE_TOP, Top);
        R.WriteInteger(REG_TABLE_WIDTH, Width);
        R.WriteInteger(REG_TABLE_HEIGHT, Height);
      end;
    except
    end;
  finally
    R.Free;
  end;
end;

{ moves the window back on a screen if it is (partly) off all of them; the width and height are kept unless larger than the screen }
procedure TfrmTable.FitOnScreen;
var
  Mon: TMonitor;
  A: TRect;
  L, T, W, H: Integer;
begin
  Mon := Screen.MonitorFromRect(BoundsRect, mdNearest);
  if Mon = nil then
    Exit;
  A := Mon.WorkareaRect;
  W := Min(Width, A.Right - A.Left);
  H := Min(Height, A.Bottom - A.Top);
  L := Max(A.Left, Min(Left, A.Right - W));
  T := Max(A.Top, Min(Top, A.Bottom - H));
  if (L <> Left) or (T <> Top) or (W <> Width) or (H <> Height) then
    SetBounds(L, T, W, H);
end;

procedure TfrmTable.FormShow(Sender: TObject);
begin
  LoadBounds;
  FitOnScreen;
  FShownOnce := True;
end;

procedure TfrmTable.FormHide(Sender: TObject);
begin
  EndStep;
  SaveBounds;
end;

procedure TfrmTable.FormDestroy(Sender: TObject);
begin
  if Visible then
    SaveBounds;
end;

end.
