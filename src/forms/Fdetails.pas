{ The Design Details dialog: the title block text of a sheet (title, author, organisation, document
  number, revision, date, sheets), whether the title block is shown, the rulers (the drawing
  frame), the border, the automatic sheet numbers and the revision history. TinyCAD's own dialog
  (CDetailsPropertySheet) has two pages, the text and the rulers; the border, the automatic sheet
  numbers and the revision history are additions of this port. Like TinyCAD's it changes the
  current sheet.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fdetails;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, ComCtrls, Grids, LCLType, Math,
  UDesign, UDocVars, URevisions, Fbase;

type

  { TfrmDetails }

  TfrmDetails = class(TfrmBase)
    btnApplyAll: TButton;
    btnRevAdd: TButton;
    btnRevChange: TButton;
    btnRevRemove: TButton;
    btnRowDelete: TButton;
    cbExtended: TCheckBox;
    cbSortRev: TCheckBox;
    lbExtHelp: TLabel;
    lbNotes: TLabel;
    lbRef: TLabel;
    memNotes: TMemo;
    memReference: TMemo;
    sgRevs: TStringGrid;
    tsExtended: TTabSheet;
    cbAutoSheets: TCheckBox;
    cbBorder: TCheckBox;
    cbRulers: TCheckBox;
    cbVisible: TCheckBox;
    edAuthor: TEdit;
    edDate: TEdit;
    edDocNo: TEdit;
    edHoriz: TEdit;
    edMargin: TEdit;
    edOrg: TEdit;
    edRevApproved: TEdit;
    edRevAuthor: TEdit;
    edRevDate: TEdit;
    edRevision: TEdit;
    edRevLabel: TEdit;
    edSheets: TEdit;
    edTitle: TEdit;
    edVert: TEdit;
    gbBorder: TGroupBox;
    gbRulers: TGroupBox;
    Label1: TLabel;
    Label10: TLabel;
    Label11: TLabel;
    Label12: TLabel;
    Label13: TLabel;
    Label14: TLabel;
    Label15: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    Label8: TLabel;
    Label9: TLabel;
    lbPortrait: TLabel;
    lbRevisions: TListBox;
    lbRevNote: TLabel;
    memRevNotes: TMemo;
    pcDetails: TPageControl;
    tsDetails: TTabSheet;
    tsFrame: TTabSheet;
    tsRevisions: TTabSheet;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure RevAdd(Sender: TObject);
    procedure RevChange(Sender: TObject);
    procedure RevRemove(Sender: TObject);
    procedure RevSelect(Sender: TObject);
    procedure RowDeleteClick(Sender: TObject);
    procedure sgRevsDrawCell(Sender: TObject; aCol, aRow: Integer; aRect: TRect; aState: TGridDrawState);
    procedure sgRevsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure sgRevsResize(Sender: TObject);
    procedure sgRevsSelectCell(Sender: TObject; aCol, aRow: Integer; var CanSelect: Boolean);
    procedure sgRevsSetEditText(Sender: TObject; ACol, ARow: Integer; const Value: String);
    procedure StateChange(Sender: TObject);
  private
    FRevs: TRevisionArray;      // the dialog's own copy of the revision history
    FTypedSheets: String;       // what was typed in Sheets (kept while automatic numbering is on)
    FAutoText: String;          // the number of sheets (M), shown in Sheets while the numbering is automatic
    FTypedDocNo: String;        // what was typed in Document (kept while automatic numbering is on)
    FAutoDocNo: String;         // this sheet's number (N), shown in Document while the numbering is automatic
    FPageW, FPageH: Integer;    // the page, to check the border margin against
    FUpdating: Boolean;
    FGridBusy: Boolean;         // the grid is being filled by the dialog, not edited by the user
    procedure DetailsActivate(Sender: TObject);
    procedure ApplyClicked(Sender: TObject);
    procedure ApplyAllClicked(Sender: TObject);
    procedure FillRevisionList;
    procedure FillGrid;
    procedure UpdateRevisionBox;
    procedure AddRowAsync(Data: PtrInt);
    function IsBlankRevision(const R: TRevision): Boolean;
    function CleanRevisions: TRevisionArray;
    procedure UpdateEnables;
    function RevisionFromEntries: TRevision;
    function ReadMm(const S: String; out V: Double): Boolean;
  public
    OnApplyAllRequest: TNotifyEvent; // the Apply to All button: copy the Details tab to every sheet
    OnApplyRequest: TNotifyEvent;   // the Apply button: apply the dialog's values now
    procedure LoadFromSheet(Sheet: TDesignSheet; Design: TDesignFile; SheetIndex: Integer);
    function SaveDetailsTab(Sheet: TDesignSheet): Boolean;   // only the Details tab (what Apply to All copies to every sheet)
    function SaveToSheet(Sheet: TDesignSheet): Boolean;
    function ValidationError: String;
    function RevisionCount: Integer;
    procedure AddRevisionEntry(const ALabel, ADate, AAuthor, AApproved, ANotes: String);
    { the grid of the extended information, as a person uses it (the tests use these) }
    function GridAddRow: Integer;                       // clicking the last row: a new revision is added; its number
    procedure GridSetCell(ACol, ARow: Integer; const AText: String);    // typing in a cell
    function GridCell(ACol, ARow: Integer): String;
    function GridRowCount: Integer;                     // all rows, the heading and the row for adding one included
    procedure DeleteGridRow(ARow: Integer);
    function NewestLabel: String;                       // what the (read-only) Revision box shows: the label of the newest revision
  end;

var
  frmDetails: TfrmDetails;

implementation


uses UStrings;

{$R *.lfm}

const
  UNITS_PER_MM = 5;

{ ===========================================================================
  Dot  (function)
  Parameters:  none
  Returns:
    TFormatSettings - the format settings
  Notes:
    Number formatting that always uses a full stop as the decimal separator, whatever the system
    language, so margins read and write the same everywhere.
  =========================================================================== }
function Dot: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
end;

{ ===========================================================================
  TfrmDetails.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the form
  Notes:
    OnCreate handler: makes the dialog show Apply as well as OK and Cancel (the base dialog
    resets to two buttons each time it is activated), connects the Apply button, and starts on
    the first page.
  =========================================================================== }
procedure TfrmDetails.FormCreate(Sender: TObject);
begin
  OnActivate := @DetailsActivate;       // (the base form shows only OK and Cancel; this one also has Apply)
  btnApply.OnClick := @ApplyClicked;
  btnApplyAll.OnClick := @ApplyAllClicked;
  pcDetails.ActivePage := tsDetails;
  { the Revision box is not typed in: it shows the newest revision of the history (kept in TinyCAD's own Revision field of the file) }
  edRevision.ReadOnly := True;
  edRevision.Color := clBtnFace;
  sgRevs.Cells[0, 0] := rsREV; sgRevs.Cells[1, 0] := rsDATE2; sgRevs.Cells[2, 0] := rsDESCRIPTION; sgRevs.Cells[3, 0] := rsBY;
end;

{ ===========================================================================
  TfrmDetails.DetailsActivate  (procedure)
  Parameters:
    Sender: TObject - the form
  Notes:
    OnActivate handler: shows the OK, Cancel and Apply buttons.
  =========================================================================== }
procedure TfrmDetails.DetailsActivate(Sender: TObject);
begin
  SetButtons([fcbOK, fcbCancel, fcbApply]);
end;

{ ===========================================================================
  TfrmDetails.ApplyClicked  (procedure)
  Parameters:
    Sender: TObject - the Apply button
  Notes:
    Apply button: checks the values and, if they are acceptable, asks the owner to apply them to
    the sheet now (OnApplyRequest), leaving the dialog open.
  =========================================================================== }
procedure TfrmDetails.ApplyClicked(Sender: TObject);
var
  Err: String;
begin
  Err := ValidationError;
  if Err <> '' then
  begin
    MessageDlg(rsDesignDetails, Err, mtWarning, [mbOK], 0);
    Exit;
  end;
  if Assigned(OnApplyRequest) then
    OnApplyRequest(Self);
end;

{ ===========================================================================
  TfrmDetails.ApplyAllClicked  (procedure)
  Parameters:
    Sender: TObject - the Apply to All button
  Notes:
    Checks the values and, if they are acceptable, asks the owner to copy what the Details tab
    holds to every sheet of the document (OnApplyAllRequest), leaving the dialog open.
  =========================================================================== }
procedure TfrmDetails.ApplyAllClicked(Sender: TObject);
var
  Err: String;
begin
  Err := ValidationError;
  if Err <> '' then
  begin
    MessageDlg(rsDesignDetails, Err, mtWarning, [mbOK], 0);
    Exit;
  end;
  if Assigned(OnApplyAllRequest) then
    OnApplyAllRequest(Self);
end;

{ ===========================================================================
  TfrmDetails.ReadMm  (function)
  Parameters:
    const S: String - the text
    out V: Double - receives the number
  Returns:
    Boolean - True if the text is a number
  Notes:
    Reads a number of millimetres typed in an edit box (a comma is accepted as the decimal
    point).
  =========================================================================== }
function TfrmDetails.ReadMm(const S: String; out V: Double): Boolean;
begin
  Result := TryStrToFloat(StringReplace(Trim(S), ',', '.', []), V, Dot);
end;

{ ===========================================================================
  TfrmDetails.UpdateEnables  (procedure)
  Parameters:  none
  Notes:
    Enables only the entries that apply: the ruler counts only when the rulers are on, the
    margin only when there is a border, the Sheets text only when the sheets are not numbered
    automatically, and the single Revision field only while there is no revision history.
  =========================================================================== }
procedure TfrmDetails.UpdateEnables;
begin
  edHoriz.Enabled := cbRulers.Checked;
  edVert.Enabled := cbRulers.Checked;
  edMargin.Enabled := cbBorder.Checked;
  edSheets.Enabled := not cbAutoSheets.Checked;
  edDocNo.Enabled := not cbAutoSheets.Checked;
  lbRevNote.Caption := rsTheNewestRevisionOfThe;
  btnRowDelete.Enabled := (sgRevs.Row >= 1) and (sgRevs.Row <= Length(FRevs));
end;

{ ===========================================================================
  TfrmDetails.StateChange  (procedure)
  Parameters:
    Sender: TObject - the check box that changed
  Notes:
    Event handler for the check boxes. Turning automatic sheet numbers on shows "N of M" in
    place of the typed text (which is kept and comes back when it is turned off); the dependent
    entries are enabled or disabled.
  =========================================================================== }
procedure TfrmDetails.StateChange(Sender: TObject);
begin
  if FUpdating then
    Exit;
  { automatic sheet numbers show "N of M" instead of the typed text, and give it back when switched off }
  if Sender = cbAutoSheets then
  begin
    FUpdating := True;
    try
      if cbAutoSheets.Checked then
      begin
        { (only while the entries still hold typed text: asked twice, the automatic numbers must not be taken for what was typed) }
        if edSheets.Enabled then
          FTypedSheets := edSheets.Text;
        if edDocNo.Enabled then
          FTypedDocNo := edDocNo.Text;
        edSheets.Text := FAutoText;
        edDocNo.Text := FAutoDocNo;
      end
      else
      begin
        edSheets.Text := FTypedSheets;
        edDocNo.Text := FTypedDocNo;
      end;
    finally
      FUpdating := False;
    end;
  end;
  if Sender = cbSortRev then
    UpdateRevisionBox;
  UpdateEnables;
end;

{ ===========================================================================
  TfrmDetails.FillRevisionList  (procedure)
  Parameters:  none
  Notes:
    Fills the revision list: each line shows the label, date, author and the first line of the
    notes (with "..." when there are more).
  =========================================================================== }
procedure TfrmDetails.FillRevisionList;
var
  i, p: Integer;
  S, Notes: String;
begin
  lbRevisions.Items.Clear;
  for i := 0 to High(FRevs) do
  begin
    Notes := FRevs[i].Notes;
    p := Pos(#10, Notes);
    if p > 0 then
      Notes := Copy(Notes, 1, p - 1) + ' ...';
    S := FRevs[i].Rev + '    ' + FRevs[i].Date + '    ' + FRevs[i].Author;
    if Notes <> '' then
      S := S + '    ' + Notes;
    lbRevisions.Items.Add(S);
  end;
end;

{ ===========================================================================
  TfrmDetails.LoadFromSheet  (procedure)
  Parameters:
    Sheet: TDesignSheet - the sheet
    Design: TDesignFile - the design (to work out "N of M" for the sheet)
    SheetIndex: Integer - zero-based number of the sheet
  Notes:
    Fills every entry of the dialog from a sheet's details and takes a copy of its revision
    history, so nothing changes until the values are saved back.
  =========================================================================== }
procedure TfrmDetails.LoadFromSheet(Sheet: TDesignSheet; Design: TDesignFile; SheetIndex: Integer);
var
  D: TDetails;
begin
  D := Sheet.Details;
  FUpdating := True;
  try
    FPageW := D.PageWidth;
    FPageH := D.PageHeight;
    edTitle.Text := D.Title;
    edAuthor.Text := D.Author;
    edOrg.Text := D.Org;
    edDate.Text := D.LastChange;
    cbVisible.Checked := D.IsVisible;
    FRevs := Copy(D.Revisions, 0, Length(D.Revisions));
    { an older file has only the single Revision field: it becomes the first line of the history (with the sheet's date), and the Revision box then
      shows the newest of the history, as it always will }
    if (Length(FRevs) = 0) and (D.Revision <> '') then
    begin
      SetLength(FRevs, 1);
      FRevs[0].Rev := D.Revision; FRevs[0].Date := D.LastChange; FRevs[0].Author := ''; FRevs[0].Approved := ''; FRevs[0].Notes := '';
    end;
    cbSortRev.Checked := D.SortByRevision;
    cbExtended.Checked := D.ExtendedInfo;
    memNotes.Text := StringReplace(D.Notes, #10, LineEnding, [rfReplaceAll]);
    memReference.Text := StringReplace(D.Reference, #10, LineEnding, [rfReplaceAll]);
    FTypedSheets := D.Sheets;
    FTypedDocNo := D.DocNo;
    if Design <> nil then
    begin
      FAutoText := IntToStr(Design.SheetCount);
      FAutoDocNo := IntToStr(SheetIndex + 1);
    end
    else
    begin
      FAutoText := '1';
      FAutoDocNo := '1';
    end;
    cbAutoSheets.Checked := D.AutoSheets;
    if D.AutoSheets then
    begin
      edSheets.Text := FAutoText;
      edDocNo.Text := FAutoDocNo;
    end
    else
    begin
      edSheets.Text := D.Sheets;
      edDocNo.Text := D.DocNo;
    end;
    cbRulers.Checked := D.HasRulers;
    edHoriz.Text := IntToStr(D.HorizRulerSize);
    if (D.VertRulerSize >= 1) and (D.VertRulerSize <= 26) then
      edVert.Text := Chr(Ord('A') + D.VertRulerSize - 1)
    else
      edVert.Text := '';
    cbBorder.Checked := D.ShowBorder;
    edMargin.Text := FormatFloat('0.##', D.BorderMargin / UNITS_PER_MM, Dot);
    FillRevisionList;
    FillGrid;
    UpdateRevisionBox;
    edRevLabel.Text := ''; edRevDate.Text := ''; edRevAuthor.Text := ''; edRevApproved.Text := ''; memRevNotes.Text := '';
  finally
    FUpdating := False;
  end;
  UpdateEnables;
end;

{ ===========================================================================
  TfrmDetails.RevisionFromEntries  (function)
  Parameters:  none
  Returns:
    TRevision - the revision
  Notes:
    The revision described by the entries below the revision list (notes stored with LF line
    ends, as in the file).
  =========================================================================== }
function TfrmDetails.RevisionFromEntries: TRevision;
begin
  Result.Rev := Trim(edRevLabel.Text);
  Result.Date := Trim(edRevDate.Text);
  Result.Author := Trim(edRevAuthor.Text);
  Result.Approved := Trim(edRevApproved.Text);
  { notes are kept with LF line ends, as in the file }
  Result.Notes := StringReplace(StringReplace(memRevNotes.Text, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
  while (Result.Notes <> '') and (Result.Notes[Length(Result.Notes)] = #10) do SetLength(Result.Notes, Length(Result.Notes) - 1);
end;

{ ===========================================================================
  TfrmDetails.RevSelect  (procedure)
  Parameters:
    Sender: TObject - the list
  Notes:
    Event handler: a revision was chosen in the list, so show it in the entries.
  =========================================================================== }
procedure TfrmDetails.RevSelect(Sender: TObject);
var
  i: Integer;
begin
  i := lbRevisions.ItemIndex;
  if (i < 0) or (i > High(FRevs)) then
    Exit;
  edRevLabel.Text := FRevs[i].Rev;
  edRevDate.Text := FRevs[i].Date;
  edRevAuthor.Text := FRevs[i].Author;
  edRevApproved.Text := FRevs[i].Approved;
  memRevNotes.Text := StringReplace(FRevs[i].Notes, #10, LineEnding, [rfReplaceAll]);
end;

{ ===========================================================================
  TfrmDetails.AddRevisionEntry  (procedure)
  Parameters:
    const ALabel: String - revision label, e.g. A or 2.1
    const ADate: String - date
    const AAuthor: String - author
    const AApproved: String - who approved it
    const ANotes: String - what changed
  Notes:
    Adds a revision to the dialog's copy of the history and to the list.
  =========================================================================== }
procedure TfrmDetails.AddRevisionEntry(const ALabel, ADate, AAuthor, AApproved, ANotes: String);
var
  R: TRevision;
begin
  R.Rev := ALabel; R.Date := ADate; R.Author := AAuthor; R.Approved := AApproved; R.Notes := ANotes;
  SetLength(FRevs, Length(FRevs) + 1);
  FRevs[High(FRevs)] := R;
  FillRevisionList;
  FillGrid;
  UpdateRevisionBox;
  UpdateEnables;
end;

{ ===========================================================================
  TfrmDetails.RevAdd  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    Add button: appends the revision in the entries to the history; it needs a label.
  =========================================================================== }
procedure TfrmDetails.RevAdd(Sender: TObject);
var
  R: TRevision;
begin
  R := RevisionFromEntries;
  if R.Rev = '' then
  begin
    MessageDlg(rsDesignDetails, rsGiveTheRevisionALabel, mtInformation, [mbOK], 0);
    Exit;
  end;
  AddRevisionEntry(R.Rev, R.Date, R.Author, R.Approved, R.Notes);
  lbRevisions.ItemIndex := High(FRevs);
end;

{ ===========================================================================
  TfrmDetails.RevChange  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    Change button: replaces the selected revision with what is in the entries.
  =========================================================================== }
procedure TfrmDetails.RevChange(Sender: TObject);
var
  i: Integer;
begin
  i := lbRevisions.ItemIndex;
  if (i < 0) or (i > High(FRevs)) then
    Exit;
  FRevs[i] := RevisionFromEntries;
  FillRevisionList;
  lbRevisions.ItemIndex := i;
  FillGrid;
  UpdateRevisionBox;
end;

{ ===========================================================================
  TfrmDetails.RevRemove  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    Remove button: deletes the selected revision from the history.
  =========================================================================== }
procedure TfrmDetails.RevRemove(Sender: TObject);
var
  i, k: Integer;
begin
  i := lbRevisions.ItemIndex;
  if (i < 0) or (i > High(FRevs)) then
    Exit;
  for k := i to High(FRevs) - 1 do FRevs[k] := FRevs[k + 1];
  SetLength(FRevs, Length(FRevs) - 1);
  FillRevisionList;
  FillGrid;
  UpdateRevisionBox;
  UpdateEnables;
end;

{ ===========================================================================
  TfrmDetails.RevisionCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    How many revisions the dialog's history holds.
  =========================================================================== }
function TfrmDetails.RevisionCount: Integer;
begin
  Result := Length(FRevs);
end;

{ ===========================================================================
  The grid of the extended information: the same revision list as the Revisions page, in the form of a table (REV, DATE, DESCRIPTION, BY) that is edited
  in its cells; the last row, which only says that, adds a revision when it is clicked. A description with several lines is shown on one line with a
  paragraph sign between them (and keeps its lines).
  =========================================================================== }
const
  PILCROW = #$C2#$B6;          // the paragraph sign, in UTF-8

{ ===========================================================================
  NotesToCell  (function)
  Parameters:
    const N: String - the notes, lines separated by LF
  Returns:
    String - the text for the cell
  Notes:
    A revision's notes as the grid shows them on one line: each line break becomes a paragraph
    sign with a space either side.
  =========================================================================== }
function NotesToCell(const N: String): String;
begin
  Result := StringReplace(N, #10, ' ' + PILCROW + ' ', [rfReplaceAll]);
end;

{ ===========================================================================
  CellToNotes  (function)
  Parameters:
    const C: String - the text of the cell
  Returns:
    String - the notes with LF between lines
  Notes:
    What was typed in a description cell back as notes: a paragraph sign (with or without the
    spaces round it) is a line break again.
  =========================================================================== }
function CellToNotes(const C: String): String;
begin
  Result := StringReplace(StringReplace(C, ' ' + PILCROW + ' ', #10, [rfReplaceAll]), PILCROW, #10, [rfReplaceAll]);
end;

{ ===========================================================================
  MemoToNotes  (function)
  Parameters:
    const M: String - text
  Returns:
    String
  Notes:
    A memo's text as the notes of the file keep it: LF between lines, no empty lines at the end
  =========================================================================== }
function MemoToNotes(const M: String): String;
begin
  Result := StringReplace(StringReplace(M, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
  while (Result <> '') and (Result[Length(Result)] = #10) do SetLength(Result, Length(Result) - 1);
end;

{ ===========================================================================
  TfrmDetails.IsBlankRevision  (function)
  Parameters:
    const R: TRevision - the XML reader, positioned on this element
  Returns:
    Boolean
  Notes:
    A row that was added and not filled in: nothing in it, or only the date a new row starts
    with (today's); it is left out when the dialog is applied
  =========================================================================== }
function TfrmDetails.IsBlankRevision(const R: TRevision): Boolean;
begin
  Result := (Trim(R.Rev) = '') and (Trim(R.Author) = '') and (Trim(R.Approved) = '') and (Trim(R.Notes) = '') and
    ((Trim(R.Date) = '') or (Trim(R.Date) = FormatDateTime('yyyy-mm-dd', Now)));
end;

{ ===========================================================================
  TfrmDetails.CleanRevisions  (function)
  Parameters:  none
  Returns:
    TRevisionArray
  Notes:
    The history without the rows that were added and never filled in
  =========================================================================== }
function TfrmDetails.CleanRevisions: TRevisionArray;
var
  i, n: Integer;
begin
  SetLength(Result, Length(FRevs));
  n := 0;
  for i := 0 to High(FRevs) do
    if not IsBlankRevision(FRevs[i]) then
    begin
      Result[n] := FRevs[i];
      Result[n].Rev := Trim(Result[n].Rev);
      Inc(n);
    end;
  SetLength(Result, n);
end;

{ ===========================================================================
  TfrmDetails.NewestLabel  (function)
  Parameters:  none
  Returns:
    String - the label
  Notes:
    The label of the newest revision of what the dialog holds, judged by date or by revision as
    the order checkbox says (rows left empty are not counted); empty if there is none. This is
    what the read-only Revision box shows.
  =========================================================================== }
function TfrmDetails.NewestLabel: String;
var
  R: TRevisionArray;
begin
  R := NewestRevisions(CleanRevisions, '', '', cbSortRev.Checked, 1);
  if Length(R) > 0 then
    Result := R[0].Rev
  else
    Result := '';
end;

{ ===========================================================================
  TfrmDetails.UpdateRevisionBox  (procedure)
  Parameters:  none
  Notes:
    The Revision box shows the newest revision of the history (it cannot be typed in)
  =========================================================================== }
procedure TfrmDetails.UpdateRevisionBox;
begin
  edRevision.Text := NewestLabel;
end;

{ ===========================================================================
  TfrmDetails.FillGrid  (procedure)
  Parameters:  none
  Notes:
    Fills the grid of the extended information from the revision list: the heading, a row for
    each revision, and the empty last row that adds one when it is clicked.
  =========================================================================== }
procedure TfrmDetails.FillGrid;
var
  i: Integer;
  Was: Boolean;
begin
  Was := FGridBusy;
  FGridBusy := True;
  try
    sgRevs.RowCount := Length(FRevs) + 2;
    sgRevs.Cells[0, 0] := rsREV; sgRevs.Cells[1, 0] := rsDATE2; sgRevs.Cells[2, 0] := rsDESCRIPTION; sgRevs.Cells[3, 0] := rsBY;
    for i := 0 to High(FRevs) do
    begin
      sgRevs.Cells[0, i + 1] := FRevs[i].Rev;
      sgRevs.Cells[1, i + 1] := FRevs[i].Date;
      sgRevs.Cells[2, i + 1] := NotesToCell(FRevs[i].Notes);
      sgRevs.Cells[3, i + 1] := FRevs[i].Author;
    end;
    for i := 0 to 3 do sgRevs.Cells[i, sgRevs.RowCount - 1] := '';
  finally
    FGridBusy := Was;
  end;
  sgRevs.Invalidate;
end;

{ ===========================================================================
  TfrmDetails.sgRevsSetEditText  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    ACol: Integer - whole number
    ARow: Integer - whole number
    const Value: String - the value
  Notes:
    A cell was typed in: the revision takes the text, and everything that shows the history is
    brought up to date
  =========================================================================== }
procedure TfrmDetails.sgRevsSetEditText(Sender: TObject; ACol, ARow: Integer; const Value: String);
begin
  if FGridBusy or (ARow < 1) or (ARow > Length(FRevs)) then
    Exit;
  case ACol of
    0: FRevs[ARow - 1].Rev := Value;
    1: FRevs[ARow - 1].Date := Value;
    2: FRevs[ARow - 1].Notes := CellToNotes(Value);
    3: FRevs[ARow - 1].Author := Value;
  end;
  FillRevisionList;
  UpdateRevisionBox;
end;

{ ===========================================================================
  TfrmDetails.sgRevsSelectCell  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    aCol: Integer - whole number
    aRow: Integer - whole number
    var CanSelect: Boolean - flag (in/out: changed by the call)
  Notes:
    The last row only adds: choosing it makes a new revision (later, since the grid is busy
    choosing) and does not stay on it
  =========================================================================== }
procedure TfrmDetails.sgRevsSelectCell(Sender: TObject; aCol, aRow: Integer; var CanSelect: Boolean);
begin
  if FGridBusy then
    Exit;
  if (aRow > 0) and (aRow = Length(FRevs) + 1) then
  begin
    CanSelect := False;
    Application.QueueAsyncCall(@AddRowAsync, 0);
  end;
  UpdateEnables;
end;

{ ===========================================================================
  TfrmDetails.AddRowAsync  (procedure)
  Parameters:
    Data: PtrInt - not used
  Notes:
    Adds a revision a moment after the last row was chosen (the grid cannot be changed while it
    is choosing), and leaves the new row ready to be typed in.
  =========================================================================== }
procedure TfrmDetails.AddRowAsync(Data: PtrInt);
begin
  GridAddRow;
  sgRevs.SetFocus;
  sgRevs.EditorMode := True;
end;

{ ===========================================================================
  TfrmDetails.GridAddRow  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    What clicking the last row does: a new revision is added to the history with today's date
    (in the form 2024-03-09) and nothing else; the grid then stands on its REV cell, ready to be
    typed in. A row left empty is dropped when the dialog is applied.
  =========================================================================== }
function TfrmDetails.GridAddRow: Integer;
var
  R: TRevision;
begin
  R.Rev := ''; R.Date := FormatDateTime('yyyy-mm-dd', Now); R.Author := ''; R.Approved := ''; R.Notes := '';
  SetLength(FRevs, Length(FRevs) + 1);
  FRevs[High(FRevs)] := R;
  Result := High(FRevs);
  FillGrid;
  FillRevisionList;
  UpdateRevisionBox;
  FGridBusy := True;
  try
    sgRevs.Row := Result + 1;
    sgRevs.Col := 0;
  finally
    FGridBusy := False;
  end;
  UpdateEnables;
end;

{ ===========================================================================
  TfrmDetails.GridSetCell  (procedure)
  Parameters:
    ACol: Integer - the column: 0 REV, 1 DATE, 2 DESCRIPTION, 3 BY
    ARow: Integer - the row
    const AText: String - the text
  Notes:
    Types text into a cell of the grid, as a person does: the revision takes it and everything
    that shows the list is brought up to date. Row 1 is the first revision.
  =========================================================================== }
procedure TfrmDetails.GridSetCell(ACol, ARow: Integer; const AText: String);
begin
  if (ARow < 1) or (ARow > Length(FRevs)) or (ACol < 0) or (ACol > 3) then
    Exit;
  sgRevs.Cells[ACol, ARow] := AText;
  sgRevsSetEditText(sgRevs, ACol, ARow, AText);
  FillGrid;                      // (a description with lines is then shown as it is when it is read from the file)
end;

{ ===========================================================================
  TfrmDetails.GridCell  (function)
  Parameters:
    ACol: Integer - the column
    ARow: Integer - the row
  Returns:
    String - the text
  Notes:
    The text of a cell of the grid.
  =========================================================================== }
function TfrmDetails.GridCell(ACol, ARow: Integer): String;
begin
  Result := sgRevs.Cells[ACol, ARow];
end;

{ ===========================================================================
  TfrmDetails.GridRowCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    How many rows the grid has: the heading, the revisions and the row that adds one.
  =========================================================================== }
function TfrmDetails.GridRowCount: Integer;
begin
  Result := sgRevs.RowCount;
end;

{ ===========================================================================
  TfrmDetails.DeleteGridRow  (procedure)
  Parameters:
    ARow: Integer - the row
  Notes:
    Removes the revision of a row of the grid (not the heading or the row that adds one) from
    the list.
  =========================================================================== }
procedure TfrmDetails.DeleteGridRow(ARow: Integer);
var
  k: Integer;
begin
  if (ARow < 1) or (ARow > Length(FRevs)) then
    Exit;
  for k := ARow - 1 to High(FRevs) - 1 do FRevs[k] := FRevs[k + 1];
  SetLength(FRevs, Length(FRevs) - 1);
  FillGrid;
  FillRevisionList;
  UpdateRevisionBox;
  UpdateEnables;
end;

{ ===========================================================================
  TfrmDetails.RowDeleteClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    The Delete row button: removes the revision of the row the grid stands on.
  =========================================================================== }
procedure TfrmDetails.RowDeleteClick(Sender: TObject);
begin
  DeleteGridRow(sgRevs.Row);
end;

{ ===========================================================================
  TfrmDetails.sgRevsKeyDown  (procedure)
  Parameters:
    Sender: TObject - the grid
    var Key: Word - the key (set to 0 when it was used)
    Shift: TShiftState - the shift keys
  Notes:
    Ctrl and Delete in the grid remove the revision of the row it stands on.
  =========================================================================== }
procedure TfrmDetails.sgRevsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_DELETE) and (ssCtrl in Shift) then
  begin
    DeleteGridRow(sgRevs.Row);
    Key := 0;
  end;
end;

{ ===========================================================================
  TfrmDetails.sgRevsResize  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The columns share the grid's width: REV a tenth, DATE a fifth, BY a seventh, DESCRIPTION the
    rest
  =========================================================================== }
procedure TfrmDetails.sgRevsResize(Sender: TObject);
var
  W: Integer;
begin
  W := sgRevs.ClientWidth - 4;
  if W < 200 then
    Exit;
  sgRevs.ColWidths[0] := W * 10 div 100;
  sgRevs.ColWidths[1] := W * 20 div 100;
  sgRevs.ColWidths[3] := W * 14 div 100;
  sgRevs.ColWidths[2] := W - sgRevs.ColWidths[0] - sgRevs.ColWidths[1] - sgRevs.ColWidths[3];
end;

{ ===========================================================================
  TfrmDetails.sgRevsDrawCell  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    aCol: Integer - whole number
    aRow: Integer - whole number
    aRect: TRect
    aState: TGridDrawState
  Notes:
    The last row says what clicking it does
  =========================================================================== }
procedure TfrmDetails.sgRevsDrawCell(Sender: TObject; aCol, aRow: Integer; aRect: TRect; aState: TGridDrawState);
begin
  if (aRow > 0) and (aRow = sgRevs.RowCount - 1) then
  begin
    sgRevs.Canvas.Brush.Color := RGBToColor(238, 238, 238);
    sgRevs.Canvas.FillRect(aRect);
    if aCol = 2 then
    begin
      sgRevs.Canvas.Font.Color := clGray;
      sgRevs.Canvas.Font.Style := [fsItalic];
      sgRevs.Canvas.TextOut(aRect.Left + 4, aRect.Top + 3, rsClickHereToAddA);
      sgRevs.Canvas.Font.Style := [];
    end;
  end;
end;

{ ===========================================================================
  TfrmDetails.ValidationError  (function)
  Parameters:  none
  Returns:
    String - the message to show, empty when all is well
  Notes:
    Checks the entries: with a border, the margin must be 0 or more millimetres and small enough
    for the page.
  =========================================================================== }
function TfrmDetails.ValidationError: String;
var
  V: Double;
  i: Integer;
begin
  Result := '';
  for i := 0 to High(FRevs) do
    if (Trim(FRevs[i].Rev) = '') and not IsBlankRevision(FRevs[i]) then
    begin
      Result := Format(rsEveryRevisionNeedsALabel, [i + 1]);
      Exit;
    end;
  if cbBorder.Checked then
  begin
    if not ReadMm(edMargin.Text, V) or (V < 0) then
      Result := rsTheBorderMarginMustBe2
    else if V * UNITS_PER_MM * 2 >= Min(FPageW, FPageH) then
      Result := rsTheBorderMarginIsToo;
  end;
end;

{ ===========================================================================
  SameRevisions  (function)
  Parameters:
    const A: TRevisionArray - first history
    const B: TRevisionArray - second history
  Returns:
    Boolean - True if they are the same
  Notes:
    Whether two revision histories are identical (every field of every revision).
  =========================================================================== }
function SameRevisions(const A, B: TRevisionArray): Boolean;
var
  i: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for i := 0 to High(A) do
      if (A[i].Rev <> B[i].Rev) or (A[i].Date <> B[i].Date) or (A[i].Author <> B[i].Author) or
         (A[i].Approved <> B[i].Approved) or (A[i].Notes <> B[i].Notes) then
      begin
        Result := False;
        Exit;
      end;
end;

{ ===========================================================================
  TfrmDetails.SaveDetailsTab  (function)
  Parameters:
    Sheet: TDesignSheet - the sheet
  Returns:
    Boolean - True if anything differed from what the sheet had
  Notes:
    Writes only what the Details tab holds into the sheet: title, author, organisation, document
    number, date, the sheet numbering (automatic or typed), and whether the title block and the
    extended information are shown. Used by OK/Apply (through SaveToSheet) and by Apply to All.
    The revision, which is not typed in (it is the newest of the history), is left alone.
  =========================================================================== }
function TfrmDetails.SaveDetailsTab(Sheet: TDesignSheet): Boolean;
var
  D: TDetails;
  NewSheets, NewDocNo: String;
begin
  D := Sheet.Details;
  Result := False;
  if D.IsVisible <> cbVisible.Checked then begin
    D.IsVisible := cbVisible.Checked;
    Result := True;
  end;
  if D.Title <> edTitle.Text then begin
    D.Title := edTitle.Text;
    Result := True;
  end;
  if D.Author <> edAuthor.Text then begin
    D.Author := edAuthor.Text;
    Result := True;
  end;
  if D.Org <> edOrg.Text then begin
    D.Org := edOrg.Text;
    Result := True;
  end;
  if cbAutoSheets.Checked then
    NewDocNo := FTypedDocNo
  else
    NewDocNo := edDocNo.Text;
  if D.DocNo <> NewDocNo then begin
    D.DocNo := NewDocNo;
    Result := True;
  end;
  if D.LastChange <> edDate.Text then begin
    D.LastChange := edDate.Text;
    Result := True;
  end;
  if D.ExtendedInfo <> cbExtended.Checked then begin
    D.ExtendedInfo := cbExtended.Checked;
    Result := True;
  end;
  if D.AutoSheets <> cbAutoSheets.Checked then begin
    D.AutoSheets := cbAutoSheets.Checked;
    Result := True;
  end;
  if cbAutoSheets.Checked then
    NewSheets := FTypedSheets
  else
    NewSheets := edSheets.Text;
  if D.Sheets <> NewSheets then begin
    D.Sheets := NewSheets;
    Result := True;
  end;
end;

{ ===========================================================================
  TfrmDetails.SaveToSheet  (function)
  Parameters:
    Sheet: TDesignSheet - the sheet
  Returns:
    Boolean - True if anything differed from what the sheet had
  Notes:
    Writes everything the dialog holds into the sheet: the Details tab (SaveDetailsTab), the
    revision history, the notes and reference and the page frame.
  =========================================================================== }
function TfrmDetails.SaveToSheet(Sheet: TDesignSheet): Boolean;
var
  D: TDetails;
  H, V: Integer;
  M: Double;
  NewLabel: String;
  Clean, NewRev: TRevisionArray;
begin
  D := Sheet.Details;
  Result := SaveDetailsTab(Sheet);
  { the history, without rows that were added and left empty; TinyCAD's own Revision field then holds the newest of it (it is not typed in any more) }
  Clean := CleanRevisions;
  if not SameRevisions(D.Revisions, Clean) then begin
    D.Revisions := Copy(Clean, 0, Length(Clean));
    Result := True;
  end;
  NewRev := NewestRevisions(Clean, '', '', cbSortRev.Checked, 1);
  if Length(NewRev) > 0 then
    NewLabel := NewRev[0].Rev
  else
    NewLabel := '';
  if D.Revision <> NewLabel then begin
    D.Revision := NewLabel;
    Result := True;
  end;
  if D.SortByRevision <> cbSortRev.Checked then begin
    D.SortByRevision := cbSortRev.Checked;
    Result := True;
  end;
  if D.Notes <> MemoToNotes(memNotes.Text) then begin
    D.Notes := MemoToNotes(memNotes.Text);
    Result := True;
  end;
  if D.Reference <> MemoToNotes(memReference.Text) then begin
    D.Reference := MemoToNotes(memReference.Text);
    Result := True;
  end;
  { rulers: as TinyCAD's SetRulers, a count outside 1 to 26 (or a letter outside A to Z) is ignored }
  if D.HasRulers <> cbRulers.Checked then begin
    D.HasRulers := cbRulers.Checked;
    Result := True;
  end;
  H := StrToIntDef(Trim(edHoriz.Text), 0);
  if (H >= 1) and (H <= 26) and (H <> D.HorizRulerSize) then begin
    D.HorizRulerSize := H;
    Result := True;
  end;
  V := 0;
  if Trim(edVert.Text) <> '' then
    V := Ord(UpCase(Trim(edVert.Text)[1])) - Ord('A') + 1;
  if (V >= 1) and (V <= 26) and (V <> D.VertRulerSize) then begin
    D.VertRulerSize := V;
    Result := True;
  end;
  if D.ShowBorder <> cbBorder.Checked then begin
    D.ShowBorder := cbBorder.Checked;
    Result := True;
  end;
  if ReadMm(edMargin.Text, M) and (M >= 0) and (Abs(D.BorderMargin - M * UNITS_PER_MM) > 1e-9) then
  begin
    D.BorderMargin := M * UNITS_PER_MM;
    Result := True;
  end;
end;

{ ===========================================================================
  TfrmDetails.FormCloseQuery  (procedure)
  Parameters:
    Sender: TObject - the form
    var CanClose: Boolean - set False to keep the dialog open
  Notes:
    Event handler: pressing OK checks the entries first and keeps the dialog open with a message
    if they are not acceptable.
  =========================================================================== }
procedure TfrmDetails.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  Err: String;
begin
  if ModalResult <> mrOK then
    Exit;
  Err := ValidationError;
  if Err <> '' then
  begin
    MessageDlg(rsDesignDetails, Err, mtWarning, [mbOK], 0);
    CanClose := False;
    ModalResult := mrNone;
  end;
end;

end.
