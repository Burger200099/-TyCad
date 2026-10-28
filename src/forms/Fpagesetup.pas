{ The Page Setup dialog: the paper size and orientation of a sheet, as TinyCAD's CDlgPageSizeBox: a
  standard paper or a width and height in millimetres, landscape or portrait. TinyCAD applies it to
  the current sheet only; "Use for all sheets" is an addition.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fpagesetup;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Math,
  UPaper, UDesign, Fbase;

type

  { TfrmPageSetup }

  TfrmPageSetup = class(TfrmBase)
    btnPrinterPaper: TButton;
    btnPrinterSetup: TButton;
    cbAllSheets: TCheckBox;
    cbFamily: TComboBox;
    edHeight: TEdit;
    edWidth: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    lbInfo: TLabel;
    lbPapers: TListBox;
    rgOrient: TRadioGroup;
    procedure btnPrinterPaperClick(Sender: TObject);
    procedure btnPrinterSetupClick(Sender: TObject);
    procedure FamilyChange(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure OrientChange(Sender: TObject);
    procedure PaperSelect(Sender: TObject; User: Boolean);
    procedure SizeEdited(Sender: TObject);
  private
    FIndexes: array of Integer;    // paper table index of each line of the list
    FUpdating: Boolean;
    function ReadMm(Ed: TEdit; out V: Double): Boolean;
    function MmText(V: Double): String;
    function MmToUnits(V: Double): Integer;
    procedure FillPapers;
    procedure ShowInfo;
    procedure MatchPaperFromEntries;
    procedure ShowChosenPaper(Data: PtrInt);
  public
    { the printer's page, as the Printer buttons use it: asks for the size in millimetres of the printer's page (after showing the printer's own setup dialog when Choose
      is True); False when there is no printer or the setup was cancelled }
    OnPrinterPage: function(Choose: Boolean; out HorzMm, VertMm: Integer): Boolean of object;
    destructor Destroy; override;
    { CDlgPageSizeBox::OnChange for the "Printer Setup" paper and OnPrinterSet: the size of the printer's page (the longer side along the sheet's long side, as
      the orientation says) goes into the width and height boxes }
    function UsePrinterPage(Choose: Boolean): Boolean;
    procedure LoadFromSheet(Sheet: TDesignSheet);
    procedure SelectPaper(const AName: String; ALandscape: Boolean);
    function PageWidthUnits: Integer;
    function PageHeightUnits: Integer;
    function ApplyToAllSheets: Boolean;
    function ValidationError: String;
  end;

var
  frmPageSetup: TfrmPageSetup;

implementation


uses UStrings;

{$R *.lfm}

const
  MAX_MM = 2500;       // TinyCAD limits a side of the page to 2500 mm
  MIN_UNITS = 10;      // and refuses a page smaller than 10 units (2 mm) a side
  UNITS_PER_MM = 5;

{ ===========================================================================
  Dot  (function)
  Parameters:  none
  Returns:
    TFormatSettings - the format settings
  Notes:
    Number formatting that always uses a full stop as the decimal separator, whatever the system
    language.
  =========================================================================== }
function Dot: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
end;

{ ===========================================================================
  TfrmPageSetup.MmText  (function)
  Parameters:
    V: Double - the number
  Returns:
    String - the text
  Notes:
    A number of millimetres as text, up to two decimals and no trailing zeros.
  =========================================================================== }
function TfrmPageSetup.MmText(V: Double): String;
begin
  Result := FormatFloat('0.##', V, Dot);
end;

{ ===========================================================================
  TfrmPageSetup.ReadMm  (function)
  Parameters:
    Ed: TEdit - the edit box
    out V: Double - receives the number
  Returns:
    Boolean - True if the text is a valid size
  Notes:
    Reads a number of millimetres from an edit box (a comma is accepted as the decimal point);
    it must be above zero.
  =========================================================================== }
function TfrmPageSetup.ReadMm(Ed: TEdit; out V: Double): Boolean;
var
  S: String;
begin
  S := StringReplace(Trim(Ed.Text), ',', '.', []);
  Result := TryStrToFloat(S, V, Dot) and (V > 0);
end;

{ ===========================================================================
  TfrmPageSetup.MmToUnits  (function)
  Parameters:
    V: Double - millimetres
  Returns:
    Integer - whole units
  Notes:
    Converts millimetres to internal units (0.2 mm each), halves rounding up as the paper table
    does, with a side limited to 2500 mm as in TinyCAD.
  =========================================================================== }
function TfrmPageSetup.MmToUnits(V: Double): Integer;
begin
  Result := Floor(Min(V, MAX_MM) * UNITS_PER_MM + 0.5);     // halves round up, as the paper table does
end;

{ ===========================================================================
  TfrmPageSetup.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the form
  Notes:
    OnCreate handler: fills the family list ("All sizes" first, then each paper family) and the
    paper list.
  =========================================================================== }
procedure TfrmPageSetup.FormCreate(Sender: TObject);
var
  Fam: TStringList;
  i: Integer;
begin
  rgOrient.Items[0] := rsLandscape;      // (the radio group's items are not translated with the form's captions)
  rgOrient.Items[1] := rsPortrait;
  cbFamily.Items.Clear;
  cbFamily.Items.Add(rsAllSizes);
  Fam := TStringList.Create;
  try
    for i := 0 to PaperCount - 1 do
      if Fam.IndexOf(PaperInfo(i).Family) < 0 then
        Fam.Add(PaperInfo(i).Family);
    cbFamily.Items.AddStrings(Fam);
  finally
    Fam.Free;
  end;
  cbFamily.ItemIndex := 0;
  FillPapers;
  OnShow := @FormShow;
end;

{ ===========================================================================
  TfrmPageSetup.FormShow  (procedure)
  Parameters:
    Sender: TObject - the form
  Notes:
    OnShow handler: arranges for the chosen paper to be scrolled into view once the dialog is on
    screen.
  =========================================================================== }
procedure TfrmPageSetup.FormShow(Sender: TObject);
begin
  { the list can only scroll once it is on screen, so this is done just after it appears }
  Application.QueueAsyncCall(@ShowChosenPaper, 0);
end;

{ ===========================================================================
  TfrmPageSetup.ShowChosenPaper  (procedure)
  Parameters:
    Data: PtrInt - unused
  Notes:
    Scrolls the paper list so the chosen paper is visible (queued from FormShow, because a list
    can only scroll once it is displayed).
  =========================================================================== }
procedure TfrmPageSetup.ShowChosenPaper(Data: PtrInt);
begin
  if lbPapers.ItemIndex >= 0 then
    lbPapers.TopIndex := Max(0, lbPapers.ItemIndex - 2);
end;

{ ===========================================================================
  TfrmPageSetup.Destroy  (destructor)
  Parameters:  none
  Notes:
    Cancels any queued scroll and frees the dialog.
  =========================================================================== }
destructor TfrmPageSetup.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  inherited Destroy;
end;

{ ===========================================================================
  TfrmPageSetup.FillPapers  (procedure)
  Parameters:  none
  Notes:
    Fills the paper list with the papers of the chosen family (all of them for "All sizes").
  =========================================================================== }
procedure TfrmPageSetup.FillPapers;
var
  i: Integer;
  Fam: String;
begin
  lbPapers.Items.Clear;
  SetLength(FIndexes, 0);
  if cbFamily.ItemIndex <= 0 then
    Fam := ''
  else
    Fam := cbFamily.Items[cbFamily.ItemIndex];
  for i := 0 to PaperCount - 1 do
    if (Fam = '') or (PaperInfo(i).Family = Fam) then
    begin
      lbPapers.Items.Add(PaperDescription(i));
      SetLength(FIndexes, Length(FIndexes) + 1);
      FIndexes[High(FIndexes)] := i;
    end;
end;

{ ===========================================================================
  TfrmPageSetup.FamilyChange  (procedure)
  Parameters:
    Sender: TObject - the family combo box
  Notes:
    Event handler: the family changed, so list its papers and choose the first.
  =========================================================================== }
procedure TfrmPageSetup.FamilyChange(Sender: TObject);
begin
  if FUpdating then
    Exit;
  FillPapers;
  if lbPapers.Count > 0 then
  begin
    lbPapers.ItemIndex := 0;
    PaperSelect(nil, False);
  end;
end;

{ ===========================================================================
  TfrmPageSetup.PaperSelect  (procedure)
  Parameters:
    Sender: TObject - the paper list
    User: Boolean - True when the user chose it
  Notes:
    Event handler: a paper was chosen, so show its width and height in millimetres for the
    current orientation.
  =========================================================================== }
procedure TfrmPageSetup.PaperSelect(Sender: TObject; User: Boolean);
var
  W, H: Integer;
begin
  if FUpdating or (lbPapers.ItemIndex < 0) then
    Exit;
  FUpdating := True;
  try
    PaperUnits(FIndexes[lbPapers.ItemIndex], rgOrient.ItemIndex = 0, W, H);
    edWidth.Text := MmText(W / UNITS_PER_MM);
    edHeight.Text := MmText(H / UNITS_PER_MM);
  finally
    FUpdating := False;
  end;
  ShowInfo;
end;

{ ===========================================================================
  TfrmPageSetup.OrientChange  (procedure)
  Parameters:
    Sender: TObject - the orientation group
  Notes:
    Event handler: the orientation changed. As TinyCAD's Make Landscape and Make Portrait, the
    width and height are swapped only if they are the wrong way round.
  =========================================================================== }
procedure TfrmPageSetup.OrientChange(Sender: TObject);
var
  W, H: Double;
  S: String;
begin
  if FUpdating then
    Exit;
  { as TinyCAD's Make Landscape / Make Portrait: swap the sides only if they are the wrong way round }
  if ReadMm(edWidth, W) and ReadMm(edHeight, H) then
    if ((rgOrient.ItemIndex = 0) and (W < H)) or ((rgOrient.ItemIndex = 1) and (W > H)) then
    begin
      FUpdating := True;
      try
        S := edWidth.Text;
        edWidth.Text := edHeight.Text;
        edHeight.Text := S;
      finally
        FUpdating := False;
      end;
    end;
  MatchPaperFromEntries;
  ShowInfo;
end;

{ ===========================================================================
  TfrmPageSetup.SizeEdited  (procedure)
  Parameters:
    Sender: TObject - the width or height box
  Notes:
    Event handler: a width or height was typed. The orientation follows (taller than wide is
    portrait) and the paper that has that size is chosen in the list, or none for a custom size.
  =========================================================================== }
procedure TfrmPageSetup.SizeEdited(Sender: TObject);
var
  W, H: Double;
begin
  if FUpdating then
    Exit;
  if ReadMm(edWidth, W) and ReadMm(edHeight, H) then
  begin
    FUpdating := True;
    try
      if W < H then
        rgOrient.ItemIndex := 1
      else
        rgOrient.ItemIndex := 0;
    finally
      FUpdating := False;
    end;
    MatchPaperFromEntries;
  end;
  ShowInfo;
end;

{ ===========================================================================
  TfrmPageSetup.MatchPaperFromEntries  (procedure)
  Parameters:  none
  Notes:
    Select the list line that is this size, if there is one; otherwise no line is selected (a
    custom size)
  =========================================================================== }
procedure TfrmPageSetup.MatchPaperFromEntries;
var
  W, H: Double;
  Idx, i, Line: Integer;
  Land: Boolean;
begin
  if not (ReadMm(edWidth, W) and ReadMm(edHeight, H)) then
    Exit;
  FUpdating := True;
  try
    Idx := MatchPaper(MmToUnits(W), MmToUnits(H), 5, Land);
    Line := -1;
    if Idx >= 0 then
    begin
      for i := 0 to High(FIndexes) do if FIndexes[i] = Idx then
        Line := i;
      if Line < 0 then
      begin
        { it is in another family than the one listed: list them all }
        cbFamily.ItemIndex := 0;
        FillPapers;
        for i := 0 to High(FIndexes) do if FIndexes[i] = Idx then
          Line := i;
      end;
    end;
    lbPapers.ItemIndex := Line;
    if Line >= 0 then
      lbPapers.MakeCurrentVisible;      // scroll so the chosen paper can be seen
  finally
    FUpdating := False;
  end;
end;

{ ===========================================================================
  TfrmPageSetup.ShowInfo  (procedure)
  Parameters:  none
  Notes:
    Shows what the entries amount to: the page described as a paper or "Custom", and its size in
    internal units.
  =========================================================================== }
procedure TfrmPageSetup.ShowInfo;
var
  W, H: Double;
begin
  if ReadMm(edWidth, W) and ReadMm(edHeight, H) then
    lbInfo.Caption := Format(rsPageXUnitsMmPer2, [DescribePage(MmToUnits(W), MmToUnits(H)), MmToUnits(W), MmToUnits(H)])
  else
    lbInfo.Caption := rsEnterTheWidthAndHeight;
end;

{ ===========================================================================
  TfrmPageSetup.LoadFromSheet  (procedure)
  Parameters:
    Sheet: TDesignSheet - the sheet
  Notes:
    Fills the dialog from a sheet's page size: millimetres, orientation, and the paper if the
    size is a standard one.
  =========================================================================== }
procedure TfrmPageSetup.LoadFromSheet(Sheet: TDesignSheet);
begin
  FUpdating := True;
  try
    edWidth.Text := MmText(Sheet.Details.PageWidth / UNITS_PER_MM);
    edHeight.Text := MmText(Sheet.Details.PageHeight / UNITS_PER_MM);
    if Sheet.Details.PageWidth < Sheet.Details.PageHeight then
      rgOrient.ItemIndex := 1
    else
      rgOrient.ItemIndex := 0;
    cbAllSheets.Checked := False;
  finally
    FUpdating := False;
  end;
  MatchPaperFromEntries;
  ShowInfo;
end;

{ ===========================================================================
  TfrmPageSetup.SelectPaper  (procedure)
  Parameters:
    const AName: String - paper name from the paper table
    ALandscape: Boolean - True for landscape, False for portrait
  Notes:
    Chooses a paper and orientation in the dialog (used for scripts), listing all families so
    the paper can be found.
  =========================================================================== }
procedure TfrmPageSetup.SelectPaper(const AName: String; ALandscape: Boolean);
var
  Idx, i: Integer;
begin
  Idx := PaperIndexByName(AName);
  if Idx < 0 then
    Exit;
  FUpdating := True;
  try
    cbFamily.ItemIndex := 0;
    FillPapers;
    for i := 0 to High(FIndexes) do if FIndexes[i] = Idx then
      lbPapers.ItemIndex := i;
    lbPapers.MakeCurrentVisible;
    if ALandscape then
      rgOrient.ItemIndex := 0
    else
      rgOrient.ItemIndex := 1;
  finally
    FUpdating := False;
  end;
  PaperSelect(nil, False);
end;

{ ===========================================================================
  TfrmPageSetup.PageWidthUnits  (function)
  Parameters:  none
  Returns:
    Integer - units, or 0 if the entry is not a number
  Notes:
    The page width the entries give, in internal units.
  =========================================================================== }
function TfrmPageSetup.PageWidthUnits: Integer;
var
  V: Double;
begin
  if ReadMm(edWidth, V) then
    Result := MmToUnits(V)
  else
    Result := 0;
end;

{ ===========================================================================
  TfrmPageSetup.PageHeightUnits  (function)
  Parameters:  none
  Returns:
    Integer - units, or 0 if the entry is not a number
  Notes:
    The page height the entries give, in internal units.
  =========================================================================== }
function TfrmPageSetup.PageHeightUnits: Integer;
var
  V: Double;
begin
  if ReadMm(edHeight, V) then
    Result := MmToUnits(V)
  else
    Result := 0;
end;

{ ===========================================================================
  TfrmPageSetup.ApplyToAllSheets  (function)
  Parameters:  none
  Returns:
    Boolean - True if ticked
  Notes:
    Whether "Use for all sheets" is ticked (TinyCAD changes only the current sheet).
  =========================================================================== }
function TfrmPageSetup.ApplyToAllSheets: Boolean;
begin
  Result := cbAllSheets.Checked;
end;

{ ===========================================================================
  TfrmPageSetup.ValidationError  (function)
  Parameters:  none
  Returns:
    String - the message to show, empty when all is well
  Notes:
    Checks the entries: both must be numbers of millimetres and each side at least 10 units (2
    mm), as TinyCAD requires.
  =========================================================================== }
function TfrmPageSetup.ValidationError: String;
begin
  Result := '';
  if (PageWidthUnits = 0) or (PageHeightUnits = 0) then
    Result := rsTheWidthAndHeightMust
  else if (PageWidthUnits < MIN_UNITS) or (PageHeightUnits < MIN_UNITS) then
    Result := rsThePageIsTooSmall;
end;

{ ===========================================================================
  TfrmPageSetup.UsePrinterPage  (function)
  Parameters:
    Choose: Boolean - True to show the printer's setup dialog first
  Returns:
    Boolean - True if the boxes were filled from the printer
  Notes:
    The printer's page (CDlgPageSizeBox: the larger side against the smaller, in whole
    millimetres) becomes the sheet's size, the larger side being the width for landscape and the
    height for portrait. Does nothing when there is no printer or the setup is cancelled.
  =========================================================================== }
function TfrmPageSetup.UsePrinterPage(Choose: Boolean): Boolean;
var
  Hz, Vt, A, B: Integer;
begin
  Result := False;
  if not Assigned(OnPrinterPage) then
    Exit;
  if not OnPrinterPage(Choose, Hz, Vt) then
    Exit;
  A := Max(Hz, Vt);
  B := Min(Hz, Vt);
  FUpdating := True;
  try
    if rgOrient.ItemIndex = 1 then
    begin
      edWidth.Text := IntToStr(B);
      edHeight.Text := IntToStr(A);
    end
    else
    begin
      edWidth.Text := IntToStr(A);
      edHeight.Text := IntToStr(B);
    end;
  finally
    FUpdating := False;
  end;
  MatchPaperFromEntries;
  ShowInfo;
  Result := True;
end;

{ ===========================================================================
  TfrmPageSetup.btnPrinterPaperClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    The Printer Paper button: the size of the printer's page, with no dialog.
  =========================================================================== }
procedure TfrmPageSetup.btnPrinterPaperClick(Sender: TObject);
begin
  UsePrinterPage(False);
end;

{ ===========================================================================
  TfrmPageSetup.btnPrinterSetupClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    The Printer Setup button: the printer's own page setup dialog, then the size of its page.
  =========================================================================== }
procedure TfrmPageSetup.btnPrinterSetupClick(Sender: TObject);
begin
  UsePrinterPage(True);
end;

{ ===========================================================================
  TfrmPageSetup.FormCloseQuery  (procedure)
  Parameters:
    Sender: TObject - the form
    var CanClose: Boolean - set False to keep the dialog open
  Notes:
    Event handler: pressing OK checks the entries first and keeps the dialog open with a message
    if they are not acceptable.
  =========================================================================== }
procedure TfrmPageSetup.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  Err: String;
begin
  if ModalResult <> mrOK then
    Exit;
  Err := ValidationError;
  if Err <> '' then
  begin
    MessageDlg(rsPageSetup, Err, mtWarning, [mbOK], 0);
    CanClose := False;
    ModalResult := mrNone;
  end;
end;

end.
