unit Fnewdoc;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Spin, UPaper, UDesign, Math, Fbase, consts, USettings;
type

  { TfrmNewDoc }

  TfrmNewDoc = class(TfrmBase)
    cbFamily: TComboBox;
    cbBorder: TCheckBox;
    cbAutoNumber: TCheckBox;
    edMargin: TFloatSpinEdit;
    edTitle: TEdit;
    edAuthor: TEdit;
    edDocNo: TEdit;
    edOrg: TEdit;
    GroupBox1: TGroupBox;
    rgOrient: TGroupBox;
    imgPortrait: TImage;
    imgLandscape: TImage;
    Label1: TLabel;
    Label2: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    lbInfo: TLabel;
    lbPapers: TListBox;
    pnlImg1: TPanel;
    pnlImg2: TPanel;
    rbPortrait: TRadioButton;
    rbLandscape: TRadioButton;
    procedure FamilyChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure rgOrientClick(Sender: TObject);
    procedure ImageClick(Sender: TObject);
    procedure PaperSelect(Sender: TObject);
    procedure PaperChange(Sender: TObject);
  private
    fIndexes: array of integer;
    FTypedDocNo: String;        // what was typed in Document (kept while automatic numbering is on)
    procedure FillPapers;
    procedure AutoNumberClick(Sender: TObject);
  public
    procedure SelectPaper(const AName: String; ALandscape: Boolean);
    { keep the paper size and orientation chosen now in the program settings, so the dialog starts on them next time }
    procedure RememberChoice;
    { A new design with one sheet set up from the dialog's choices }
    function BuildDesign: TDesignFile;
    function PaperIndex: Integer;
    function Landscape: Boolean;
  end;

var
  frmNewDoc: TfrmNewDoc;

implementation

uses UStrings, FSharedCtls;

{$R *.lfm}

{ TfrmNewDoc }

{ ===========================================================================
  TfrmNewDoc.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the form
  Notes:
    OnCreate handler: fills the family list ("All sizes" first, then each paper family), resets
    the title-block fields and the 6.35 mm border margin, lists the papers and selects ISO A4
    landscape.
  =========================================================================== }
procedure TfrmNewDoc.FormCreate(Sender: TObject);
var i: integer;
  Fam: string;
  PaperList: TStringList;
begin
  imgPortrait.Images := frmSharedControls.ilNewDocument;       // (a form file cannot name the image list of another form)
  imgLandscape.Images := frmSharedControls.ilNewDocument;
  cbFamily.Items.Clear;
  cbFamily.Items.Add(rsAllSizes);   // entry 0 means every family; FillPapers relies on it
  PaperList := TStringList.Create;
  try
    for i := 0 to PaperCount - 1 do
    begin
      Fam := PaperInfo(i).Family;
      if PaperList.IndexOf(Fam) < 0 then
        begin
          PaperList.Add(Fam);
          cbFamily.Items.Add(Fam);
        end;
    end;
  finally
    PaperList.Free;
  end;
  cbFamily.ItemIndex := 0;
  edMargin.Value := ProgramSettings.NewSheetMarginMm;      // (Options > Sheets)
  cbBorder.Checked := ProgramSettings.NewSheetBorder;
  edAuthor.Text := '';
  edTitle.Text := '';
  edOrg.Text := '';
  edDocNo.Text := '';
  FTypedDocNo := '';
  cbAutoNumber.OnClick := @AutoNumberClick;
  AutoNumberClick(nil);
  FillPapers;
  { the paper size and orientation chosen last time (ISO A4 landscape the first time, or when that paper is no longer in the table) }
  if PaperIndexByName(ProgramSettings.NewDocPaper) >= 0 then
    SelectPaper(ProgramSettings.NewDocPaper, ProgramSettings.NewDocLandscape)
  else
    SelectPaper('ISO A4', true);

  rbPortrait.Caption := '';
  rbLandscape.Caption := '';

end;

{ ===========================================================================
  TfrmNewDoc.rgOrientClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfrmNewDoc.rgOrientClick(Sender: TObject);
begin
  end;

{ ===========================================================================
  TfrmNewDoc.ImageClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfrmNewDoc.ImageClick(Sender: TObject);
begin
  if Sender = imgPortrait then
    rbPortrait.Checked := true
  else if Sender = imgLandscape then
    rbLandscape.Checked := true;
end;

{ ===========================================================================
  TfrmNewDoc.PaperSelect  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfrmNewDoc.PaperSelect(Sender: TObject);
begin
  ModalResult := mrOK;
end;

{ ===========================================================================
  TfrmNewDoc.PaperChange  (procedure)
  Parameters:
    Sender: TObject - the paper list or the orientation group
  Notes:
    Event handler: shows the selected paper's name and its page size in internal units (0.2 mm
    each).
  =========================================================================== }
procedure TfrmNewDoc.PaperChange(Sender: TObject);
var
  W, H: Integer;
begin
  PaperUnits(PaperIndex, Landscape, W, H);
  lbInfo.Caption := Format(rsPageXUnitsMmPer, [PaperInfo(PaperIndex).Name, W, H]);
end;

{ ===========================================================================
  TfrmNewDoc.FillPapers  (procedure)
  Parameters:  none
  Notes:
    Fills the size list with the papers of the chosen family ("All sizes" shows every paper) and
    selects the first.
  =========================================================================== }
procedure TfrmNewDoc.FillPapers;
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
  if lbPapers.Count > 0 then
    lbPapers.ItemIndex := 0;
  PaperChange(nil);
end;

{ ===========================================================================
  TfrmNewDoc.SelectPaper  (procedure)
  Parameters:
    const AName: String - paper name from the paper table
    ALandscape: Boolean - True for landscape, False for portrait
  Notes:
    Selects a paper and orientation in the dialog (used for defaults and by scripts); the family
    is reset to "All sizes" so every paper can be found.
  =========================================================================== }
procedure TfrmNewDoc.SelectPaper(const AName: String; ALandscape: Boolean);
var
  Idx, k: Integer;
begin
  cbFamily.ItemIndex := 0;
  FillPapers;
  Idx := PaperIndexByName(AName);
  for k := 0 to High(FIndexes) do
    if FIndexes[k] = Idx then
      lbPapers.ItemIndex := k;
  if ALandscape then
    rbLandscape.Checked := true
  else
    rbPortrait.Checked := true;
  PaperChange(nil);
end;

{ ===========================================================================
  TfrmNewDoc.RememberChoice  (procedure)
  Parameters:  none
  Notes:
    Puts the paper size and orientation now chosen in ProgramSettings (NewDocPaper and
    NewDocLandscape) and saves the settings; FormCreate starts the dialog on them. The caller
    does this when the dialog is accepted, so a cancelled dialog and a script's new document do
    not change what is remembered.
  =========================================================================== }
procedure TfrmNewDoc.RememberChoice;
begin
  ProgramSettings.NewDocPaper := PaperInfo(PaperIndex).Name;
  ProgramSettings.NewDocLandscape := Landscape;
  SaveSettings;
end;

{ ===========================================================================
  TfrmNewDoc.AutoNumberClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    With automatic sheet numbers the Document entry shows this sheet's number (1, the new design
    has one sheet) and is greyed out; the text typed there is kept and comes back when the
    numbering is switched off. The Sheets text is not in this dialog; the title block shows the
    total (1) by itself.
  =========================================================================== }
procedure TfrmNewDoc.AutoNumberClick(Sender: TObject);
begin
  if cbAutoNumber.Checked then
  begin
    if edDocNo.Enabled then
      FTypedDocNo := edDocNo.Text;
    edDocNo.Text := '1';
    edDocNo.Enabled := False;
  end
  else if not edDocNo.Enabled then
  begin
    edDocNo.Enabled := True;
    edDocNo.Text := FTypedDocNo;
  end;
end;

{ ===========================================================================
  TfrmNewDoc.BuildDesign  (function)
  Parameters:  none
  Returns:
    TDesignFile - the new design; the caller owns it
  Notes:
    Creates the new design from the dialog's choices: one sheet with the chosen paper size and
    orientation, the title-block text, automatic sheet numbers and border (with its margin) as
    ticked, and a first revision "A - Initial issue".
  =========================================================================== }
function TfrmNewDoc.BuildDesign: TDesignFile;
var
  S: TDesignSheet;
  W, H: Integer;
  Fs: TFormatSettings;
  M: Double;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  Result := TDesignFile.Create;
  S := Result.AddSheet;
  PaperUnits(PaperIndex, Landscape, W, H);
  S.Details.PageWidth := W;
  S.Details.PageHeight := H;
  S.Details.Title := edTitle.Text;
  S.Details.Author := edAuthor.Text;
  S.Details.Org := edOrg.Text;
  if cbAutoNumber.Checked then
    S.Details.DocNo := FTypedDocNo        // (kept for when the numbering is switched off; the title block shows the sheet's number)
  else
    S.Details.DocNo := edDocNo.Text;
  S.Details.AutoSheets := cbAutoNumber.Checked;
  S.Details.ShowBorder := cbBorder.Checked;
  S.Details.HasRulers := ProgramSettings.NewSheetRulers;      // (Options > Sheets: the rulers a new sheet starts with)
  S.Details.HorizRulerSize := ProgramSettings.NewSheetCols;
  S.Details.VertRulerSize := ProgramSettings.NewSheetRows;
  if not (TryStrToFloat(StringReplace(edMargin.Text, ',', '.', []), M, Fs)) then
    M := ProgramSettings.NewSheetMarginMm;
  S.Details.BorderMargin := Max(0, M) * UNITS_PER_MM;
  S.Details.AddRevision('A', '', S.Details.Author, '', 'Initial issue');
end;

{ ===========================================================================
  TfrmNewDoc.PaperIndex  (function)
  Parameters:  none
  Returns:
    Integer - index in the paper table
  Notes:
    The paper table index of the selected size (ISO A4 when nothing is selected).
  =========================================================================== }
function TfrmNewDoc.PaperIndex: Integer;
begin
  if (lbPapers.ItemIndex >= 0) and (lbPapers.ItemIndex <= High(FIndexes)) then
    Result := FIndexes[lbPapers.ItemIndex]
  else
    Result := PaperIndexByName('ISO A4');
end;

{ ===========================================================================
  TfrmNewDoc.Landscape  (function)
  Parameters:  none
  Returns:
    Boolean - True for landscape, False for portrait
  Notes:
    Whether landscape is chosen.
  =========================================================================== }
function TfrmNewDoc.Landscape: Boolean;
begin
  Result := rbLandscape.Checked;
end;

{ ===========================================================================
  TfrmNewDoc.FamilyChange  (procedure)
  Parameters:
    Sender: TObject - the family combo box
  Notes:
    Event handler: the paper family changed, so refill the size list.
  =========================================================================== }
procedure TfrmNewDoc.FamilyChange(Sender: TObject);
begin
  FillPapers;
end;

end.

