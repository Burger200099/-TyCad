// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Print dialog (TinyCAD's CSpecialPrintDlg, IDD_PRINT): the printer (a drop down of the installed printers and a Properties button: the printer's own properties window on Windows, the system's setup
  dialog), the pages to print (typed in the Pages box: 1-3, 6 / 2 to 4 and 9 ...), whether to print the current sheet or all of them, black and white, and the scale of
  the print with a "Fit on a single page" box that puts the scale that fits the sheet on one page in the Scale box. The dialog shows how many pages the print will take
  and a quick preview of the pages asked for, with a slider and < > buttons to go from one to another (the main form draws the page, see OnPaintPage).

  The black and white box is kept in the settings the moment it is clicked and the scale when OK is pressed, as TinyCAD does (the box is not undone by Cancel). The
  Fit box shows the fit scale as the text "%3.3lg" (three digits), and unticking it shows the scale the dialog started with.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fprint;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Fbase, UPrint, UPrintRun, UPaper, USettings, consts;

type
  { draws page PageNo of the print on a canvas (the main form knows the design): the same drawing the printer gets, at Factor of the printer's size }
  TPrintPagePaint = procedure(Sender: TObject; const L: TPrintLayout; const Dev: TPrintDevice; PageNo: Integer; ACanvas: TCanvas; PxW, PxH: Integer; Black: Boolean;
    Factor: Double) of object;
  TPrinterPick = procedure(Sender: TObject; Index: Integer) of object;
  TPrinterSetupEvent = function(Sender: TObject): Boolean of object;

  { TfrmPrint }

  TfrmPrint = class(TfrmBase)
    btnPreviewFwd: TButton;
    btnPrinterSetup: TButton;
    btnPreviewBack: TButton;
    cbBW: TCheckBox;
    cbNoSymText: TCheckBox;
    cbNoSymFields: TCheckBox;
    cbFit: TCheckBox;
    cbPrinterList: TComboBox;
    edScale: TEdit;
    gbOptions: TGroupBox;
    edPageRange: TEdit;
    gbPages: TGroupBox;
    gbPrinter: TGroupBox;
    gbSheets: TGroupBox;
    gbPreview: TGroupBox;
    Label1: TLabel;
    lbPageOf: TLabel;
    lbPages: TLabel;
    lbRange: TLabel;
    lbScale: TLabel;
    pbFastPreview: TPaintBox;
    plPreview: TPanel;
    RadioButton1: TRadioButton;
    rbAll: TRadioButton;
    rbCurrent: TRadioButton;
    rbPagesAll: TRadioButton;
    rbPagesRange: TRadioButton;
    tbPageSlider: TTrackBar;
    procedure btnPreviewBackClick(Sender: TObject);
    procedure btnPreviewFwdClick(Sender: TObject);
    procedure btnPrinterSetupClick(Sender: TObject);
    procedure cbBWClick(Sender: TObject);
    procedure cbNoSymTextClick(Sender: TObject);
    procedure cbNoSymFieldsClick(Sender: TObject);
    procedure cbFitClick(Sender: TObject);
    procedure FastPreviewPaint(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure OptionChanged(Sender: TObject);
    procedure PageRangeChanged(Sender: TObject);
    procedure PagesRadioClick(Sender: TObject);
    procedure PageSliderChange(Sender: TObject);
    procedure PrinterListChange(Sender: TObject);
  public
    { a printer that was chosen but cannot be used: the list shows the one that was in use again }
    procedure RevertPrinter;
  private
  private
    FDev: TPrintDevice;
    FSheetW, FSheetH, FSheetCount: Integer;
    FInitScale: Double;
    FCopies: Integer;
    FCollate: Boolean;
    FPrinterName: String;
    FStarting: Boolean;
    FLastPrinter: Integer;         // the entry of the printer list that is in use (a change to it again is no change; a refused pick goes back to it)
    FChosen: TPageArray;           // the pages the Pages box asks for (every page when it is on All); the preview goes through these
    FChosenError: String;          // why the Pages box cannot be read ('' when it can)
    FShown: Integer;               // the page number in the quick preview
    FSyncing: Boolean;             // the slider is being set by the program
    FPreviewBmp: TBitmap;          // the page drawn, kept until something that changes it changes
    FPreviewKey: String;
    FOnPaintPage: TPrintPagePaint;
    FOnPrinterSetup: TPrinterSetupEvent;
    FOnPrinterPick: TPrinterPick;
    function GetFromPage: Integer;
    function GetToPage: Integer;
    function CurrentLayout: TPrintLayout;
    procedure UpdateTexts;
    procedure RefreshChosen;
    procedure RefreshPreview;
    procedure GoToIndex(AIndex: Integer);
    procedure CloseQuery(Sender: TObject; var CanClose: Boolean);
  public
    destructor Destroy; override;
    { draws the quick preview on any canvas of the given size (the paint box's own paint does this; tests draw it on a bitmap) }
    procedure DrawPreview(C: TCanvas; AW, AH: Integer);
    { the Printer Setup button: shows the system's printer setup dialog; True if it was accepted (the handler gives the new page with SetDevice) }
    property OnPrinterSetup: TPrinterSetupEvent read FOnPrinterSetup write FOnPrinterSetup;
    { a printer was chosen in the drop down (its position in the list given to SetPrinters) }
    property OnPrinterPick: TPrinterPick read FOnPrinterPick write FOnPrinterPick;
    { draws a page for the quick preview }
    property OnPaintPage: TPrintPagePaint read FOnPaintPage write FOnPaintPage;
    { the names for the printer drop down and the one chosen (-1 for none); with no names the drop down and the Printer Setup button are dimmed }
    procedure SetPrinters(Names: TStrings; AIndex: Integer);
    { the page numbers the quick preview goes through: those the Pages box names, every page when it is on All, none when the box cannot be read }
    function PreviewPages: TPageArray;
    { show a page (its number) in the quick preview; a page that is not one of PreviewPages shows the nearest one that is }
    procedure ShowPage(PageNo: Integer);
    { the text of the label under the preview ("Page 6 of 12") }
    function PageOfText: String;
    { CSpecialPrintDlg::OnInitDialog and CTinyCadView::DoPreparePrinting: the printer's page, the sheet's size, how many sheets there are, the name of the printer
      (empty when there is none, and then OK is dimmed), and the scale and black and white of the settings }
    procedure SetPrint(const ADev: TPrintDevice; ASheetW, ASheetH, ASheetCount: Integer; const APrinterName: String; AAvailable: Boolean; AScale: Double; BW: Boolean;
      NoSymText: Boolean = False; NoSymFields: Boolean = False);
    procedure SetRange(AFrom, ATo, ACopies: Integer; ACollate: Boolean);
    { the printer's page and name after the printer was changed }
    procedure SetDevice(const ADev: TPrintDevice; const APrinterName: String);
    { what the dialog says to print }
    function GetOptions: TPrintOptions;
    { the reason the scale or the pages are not usable, empty when they are }
    function ValidationError: String;
    { CSpecialPrintDlg::OnOK: keeps the scale (and black and white) in the settings }
    procedure KeepInSettings;
    function PageCount: Integer;
    function PagesText: String;
    function RangeText: String;
    function SizeText: String;
    property FromPage: Integer read GetFromPage;
    property ToPage: Integer read GetToPage;
    property Copies: Integer read FCopies;
    property Collate: Boolean read FCollate;
    property PrinterName: String read FPrinterName;
    property Device: TPrintDevice read FDev;
    property InitScale: Double read FInitScale;
    property ShownPage: Integer read FShown;
  end;

var
  frmPrint: TfrmPrint;

implementation


uses UStrings;

{$R *.lfm}

{ ===========================================================================
  TfrmPrint.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Hooks up the check made when OK is pressed.
  =========================================================================== }
procedure TfrmPrint.FormCreate(Sender: TObject);
begin
  FLastPrinter := -1;
  OnCloseQuery := @CloseQuery;
  FCopies := 1;
  FInitScale := PRINT_DEFAULT_SCALE;
  FShown := 1;
  FPreviewBmp := TBitmap.Create;
end;

{ ===========================================================================
  TfrmPrint.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the picture of the page kept for the quick preview.
  =========================================================================== }
destructor TfrmPrint.Destroy;
begin
  FPreviewBmp.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TfrmPrint.SetPrinters  (procedure)
  Parameters:
    Names: TStrings
    AIndex: Integer - whole number
  Notes:
    Fills the drop down. With no printers it holds one line saying so, and it and the Printer
    Setup button are dimmed.
  =========================================================================== }
procedure TfrmPrint.SetPrinters(Names: TStrings; AIndex: Integer);
var
  Was: Boolean;
begin
  Was := FStarting;
  FStarting := True;
  try
    cbPrinterList.Items.Clear;
    if (Names <> nil) and (Names.Count > 0) then
    begin
      cbPrinterList.Items.AddStrings(Names);
      if (AIndex >= 0) and (AIndex < Names.Count) then
        cbPrinterList.ItemIndex := AIndex
      else
        cbPrinterList.ItemIndex := 0;
      cbPrinterList.Enabled := True;
      btnPrinterSetup.Enabled := True;
      FLastPrinter := cbPrinterList.ItemIndex;
    end
    else
    begin
      cbPrinterList.Items.Add(rsNoPrinterIsInstalled);
      cbPrinterList.ItemIndex := 0;
      cbPrinterList.Enabled := False;
      btnPrinterSetup.Enabled := False;
    end;
  finally
    FStarting := Was;
  end;
end;

{ ===========================================================================
  TfrmPrint.SetPrint  (procedure)
  Parameters:
    const ADev: TPrintDevice - the printer's page
    ASheetW: Integer - width of the sheet showing, internal units
    ASheetH: Integer - height of the sheet showing
    ASheetCount: Integer - the number of sheets in the design
    const APrinterName: String - the name of the printer
    AAvailable: Boolean - True if there is a printer to print on
    AScale: Double - the scale kept in the settings
    BW: Boolean - the black and white choice kept in the settings
  Notes:
    Fills the dialog as it starts: the scale as text, black and white, the current sheet chosen
    (TinyCAD's radio buttons start at the first), no Fit.
  =========================================================================== }
procedure TfrmPrint.SetPrint(const ADev: TPrintDevice; ASheetW, ASheetH, ASheetCount: Integer; const APrinterName: String; AAvailable: Boolean; AScale: Double;
  BW: Boolean; NoSymText: Boolean = False; NoSymFields: Boolean = False);
begin
  FStarting := True;
  try
    FDev := ADev;
    FSheetW := ASheetW;
    FSheetH := ASheetH;
    FSheetCount := ASheetCount;
    FPrinterName := APrinterName;
    FInitScale := AScale;
    cbBW.Checked := BW;
    cbNoSymText.Checked := NoSymText;
    cbNoSymFields.Checked := NoSymFields;
    edScale.Text := PrintScaleText(AScale);
    cbFit.Checked := False;
    edScale.Enabled := True;
    rbCurrent.Checked := True;
    rbPagesAll.Checked := True;
    edPageRange.Text := '1';
    edPageRange.Enabled := False;
    rbAll.Enabled := ASheetCount > 1;
    btnOK.Enabled := AAvailable;
  finally
    FStarting := False;
  end;
  UpdateTexts;
end;

{ ===========================================================================
  TfrmPrint.SetRange  (procedure)
  Parameters:
    AFrom: Integer - first page, 0 for all pages
    ATo: Integer - last page
    ACopies: Integer - number of copies
    ACollate: Boolean - True to collate them
  Notes:
    Sets the pages and copies (what the Printer button's dialog decided) and shows them.
  =========================================================================== }
procedure TfrmPrint.SetRange(AFrom, ATo, ACopies: Integer; ACollate: Boolean);
begin
  FStarting := True;
  try
    if (AFrom = 0) and (ATo = 0) then
    begin
      rbPagesAll.Checked := True;
      edPageRange.Text := '';
    end
    else
    begin
      rbPagesRange.Checked := True;
      if AFrom = ATo then
        edPageRange.Text := IntToStr(AFrom)
      else
        edPageRange.Text := IntToStr(AFrom) + '-' + IntToStr(ATo);
    end;
    edPageRange.Enabled := rbPagesRange.Checked;
  finally
    FStarting := False;
  end;
  if ACopies < 1 then
    ACopies := 1;
  FCopies := ACopies;
  FCollate := ACollate;
  UpdateTexts;
end;

{ ===========================================================================
  TfrmPrint.SetDevice  (procedure)
  Parameters:
    const ADev: TPrintDevice - the printer's page
    const APrinterName: String - its name
  Notes:
    The printer was changed in the system's Print dialog: the pages are laid out again on its
    page.
  =========================================================================== }
procedure TfrmPrint.SetDevice(const ADev: TPrintDevice; const APrinterName: String);
begin
  FDev := ADev;
  FPrinterName := APrinterName;
  UpdateTexts;
end;

{ ===========================================================================
  TfrmPrint.RangeText  (function)
  Parameters:  none
  Returns:
    String - the pages and copies as the dialog shows them
  Notes:
    "Pages: all" or "Pages: 2-3", then the copies, and "collated" when they are.
  =========================================================================== }
function TfrmPrint.RangeText: String;
begin
  if not rbPagesRange.Checked then
    Result := rsPagesAll
  else if FChosenError = '' then
    Result := Format(rsPages, [PageListText(FChosen)])
  else
    Result := Format(rsPages, [Trim(edPageRange.Text)]);
  Result := Result + Format(rsCopies, [FCopies]);
  if (FCopies > 1) and FCollate then
    Result := Format(rsCollated, [Result]);
end;

{ ===========================================================================
  TfrmPrint.SizeText  (function)
  Parameters:  none
  Returns:
    String - 'Sheet: 297 x 210 mm (11.69 x 8.27 in)   Printable page: 210 x 297 mm (8.27 x 11.69 in)'
  Notes:
    The size the sheet comes out at (the sheet showing, at the scale in the box, so a sheet
    printed at 50% reads half its size; with all the sheets printed it is the sheet showing, as
    the page count measures it) and the printable page of the printer (its page in the orientation it
    prints in; the library gives the printable area, not the paper's edges), both in millimetres and inches. The sheet reads '-' while the scale is no use.
  =========================================================================== }
function TfrmPrint.SizeText: String;
var
  V, W, H: Double;

  function Both(AW, AH: Double): String;
  begin
    Result := Format(rsXMmXIn, [FormatFloat('0.#', AW), FormatFloat('0.#', AH), FormatFloat('0.##', AW / 25.4), FormatFloat('0.##', AH / 25.4)]);
  end;

begin
  V := PrintScaleValue(edScale.Text);
  if (V <= 0) or (V > PRINT_MAX_SCALE) or (UNITS_PER_MM <= 0) then
    Result := rsSheet2
  else
  begin
    W := FSheetW / UNITS_PER_MM * V / 100;
    H := FSheetH / UNITS_PER_MM * V / 100;
    Result := Format(rsSheet3, [Both(W, H)]);
  end;
  if (FDev.HorzMm > 0) and (FDev.VertMm > 0) then
    Result := Format(rsPrintablePage, [Result, Both(FDev.HorzMm, FDev.VertMm)]);
end;

{ ===========================================================================
  TfrmPrint.GetOptions  (function)
  Parameters:  none
  Returns:
    TPrintOptions - what the dialog says to print
  Notes:
    The scale is read from its box as _tstof does (0 when it is no number); the other choices
    come from the boxes and from the Printer button's dialog.
  =========================================================================== }
function TfrmPrint.GetOptions: TPrintOptions;
begin
  Result.Scale := PrintScaleValue(edScale.Text);
  Result.BlackWhite := cbBW.Checked;
  Result.NoSymbolText := cbNoSymText.Checked;
  Result.NoSymbolFields := cbNoSymFields.Checked;
  Result.AllSheets := rbAll.Checked;
  Result.FromPage := GetFromPage;
  Result.ToPage := GetToPage;
  Result.Pages := nil;
  if rbPagesRange.Checked and (FChosenError = '') then
    Result.Pages := Copy(FChosen);
  Result.Copies := FCopies;
  Result.Collate := FCollate;
end;

{ ===========================================================================
  TfrmPrint.PageCount  (function)
  Parameters:  none
  Returns:
    Integer - the number of pages the print takes (0 when the scale is no use)
  Notes:
    How many pages the whole print is at the scale in the box.
  =========================================================================== }
function TfrmPrint.PageCount: Integer;
var
  V: Double;
begin
  V := PrintScaleValue(edScale.Text);
  if (V <= 0) or (V > PRINT_MAX_SCALE) then
    Exit(0);
  Result := PrintLayoutFor(FDev, FSheetW, FSheetH, V, rbAll.Checked, FSheetCount).Pages;
end;

{ ===========================================================================
  TfrmPrint.PagesText  (function)
  Parameters:  none
  Returns:
    String - the line that says how many pages the print takes
  Notes:
    "4 pages: 2 across and 2 down" for each sheet, with "on each of 3 sheets" when all the
    sheets are printed, or the reason the scale is no use.
  =========================================================================== }
function TfrmPrint.PagesText: String;
var
  O: TPrintOptions;
  L: TPrintLayout;
begin
  Result := ValidationError;
  if Result <> '' then
    Exit;
  O := GetOptions;
  L := PrintLayoutFor(FDev, FSheetW, FSheetH, O.Scale, O.AllSheets, FSheetCount);
  if L.Pages = 1 then
    Result := ''
  else
    Result := 's';
  Result := Format(rsPageAcrossAndDown, [L.Pages, Result, L.Cols, L.Rows]);
  if L.Sheets > 1 then
    Result := Result + Format(rsOnEachOfSheets, [L.Sheets]);
end;

{ ===========================================================================
  TfrmPrint.UpdateTexts  (procedure)
  Parameters:  none
  Notes:
    Shows the printer, the pages and copies, and the number of pages.
  =========================================================================== }
procedure TfrmPrint.UpdateTexts;
begin
{  if FPrinterName = '' then
    lbPrinterName.Caption := 'Printer: none is installed'
  else
    lbPrinterName.Caption := 'Printer: ' + FPrinterName;}
  RefreshChosen;
  lbRange.Caption := RangeText + LineEnding + SizeText;
  lbPages.Caption := PagesText;
  RefreshPreview;
end;

{ ===========================================================================
  TfrmPrint.ValidationError  (function)
  Parameters:  none
  Returns:
    String - the message, empty when the scale will do
  Notes:
    The scale must be above 0 and at most 10000 per cent (TinyCAD takes any number; a scale of 0
    stops it, and a huge one makes it try for millions of pages).
  =========================================================================== }
function TfrmPrint.ValidationError: String;
var
  V: Double;
  Pages: TPageArray;
  Err: String;
begin
  V := PrintScaleValue(edScale.Text);
  if V <= 0 then
    Result := rsTheScaleMustBeA2
  else if V > PRINT_MAX_SCALE then
    Result := Format(rsTheScaleMustNotBe, [PRINT_MAX_SCALE])
  else
    Result := '';
  if (Result = '') and rbPagesRange.Checked then
  begin
    ParsePageRange(edPageRange.Text, PageCount, Pages, Err);
    Result := Err;
  end;
end;

{ ===========================================================================
  TfrmPrint.GetFromPage  (function)
  Parameters:  none
  Returns:
    Integer - the first page to print, 0 when all the pages are printed (or the box is no
    number)
  Notes:
    Read from the Pages box.
  =========================================================================== }
function TfrmPrint.GetFromPage: Integer;
begin
  Result := 0;
  if rbPagesRange.Checked and (FChosenError = '') and (Length(FChosen) > 0) then
    Result := FChosen[0];
end;

{ ===========================================================================
  TfrmPrint.GetToPage  (function)
  Parameters:  none
  Returns:
    Integer - the last page to print, 0 when all the pages are printed (or the box is no number)
  Notes:
    Read from the Pages box.
  =========================================================================== }
function TfrmPrint.GetToPage: Integer;
begin
  Result := 0;
  if rbPagesRange.Checked and (FChosenError = '') and (Length(FChosen) > 0) then
    Result := FChosen[High(FChosen)];
end;

{ ===========================================================================
  TfrmPrint.PageRangeChanged  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The pages typed in the Pages box (or the choice between All and Pages made by a program):
    the box can be typed in only for a range, and the texts and the quick preview are made
    again.
  =========================================================================== }
procedure TfrmPrint.PageRangeChanged(Sender: TObject);
begin
  if FStarting then
    Exit;
  edPageRange.Enabled := rbPagesRange.Checked;
  UpdateTexts;
end;

{ ===========================================================================
  TfrmPrint.PagesRadioClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    All pages or Pages was chosen. Choosing Pages with the box empty fills it with every page
    (1-12) to start from. (Typing in the box does not do this: a box the person has cleared
    stays cleared.)
  =========================================================================== }
procedure TfrmPrint.PagesRadioClick(Sender: TObject);
begin
  if FStarting then
    Exit;
  if rbPagesRange.Checked and (Trim(edPageRange.Text) = '') then
  begin
    FStarting := True;
    try
      if PageCount > 1 then
        edPageRange.Text := '1-' + IntToStr(PageCount)
      else
        edPageRange.Text := '1';
    finally
      FStarting := False;
    end;
  end;
  PageRangeChanged(Sender);
end;

{ ===========================================================================
  TfrmPrint.OptionChanged  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Updates the number of pages after the scale or the sheets chosen change.
  =========================================================================== }
procedure TfrmPrint.OptionChanged(Sender: TObject);
begin
  if FStarting then
    Exit;
  UpdateTexts;
end;

{ ===========================================================================
  TfrmPrint.cbBWClick  (procedure)
  Parameters:
    Sender: TObject - the check box
  Notes:
    CSpecialPrintDlg::OnBandw: the choice is kept in the settings at once.
  =========================================================================== }
procedure TfrmPrint.cbBWClick(Sender: TObject);
begin
  if FStarting then
    Exit;
  ProgramSettings.PrintBandW := cbBW.Checked;
  SaveSettings;
  RefreshPreview;
end;

{ ===========================================================================
  TfrmPrint.cbNoSymTextClick  (procedure)
  Parameters:
    Sender: TObject - the check box
  Notes:
    "Do not print symbol text": the choice is kept in the settings at once (as Print in black and white is), and the preview is drawn again without the symbol text.
  =========================================================================== }
procedure TfrmPrint.cbNoSymTextClick(Sender: TObject);
begin
  if FStarting then
    Exit;
  ProgramSettings.PrintNoSymText := cbNoSymText.Checked;
  SaveSettings;
  RefreshPreview;
end;

{ ===========================================================================
  TfrmPrint.cbNoSymFieldsClick  (procedure)
  Parameters:
    Sender: TObject - the check box
  Notes:
    "Do not print symbol properties": the text of every symbol's properties (reference, name, values) is left off; kept in the settings at once, and the preview is drawn again.
  =========================================================================== }
procedure TfrmPrint.cbNoSymFieldsClick(Sender: TObject);
begin
  if FStarting then
    Exit;
  ProgramSettings.PrintNoSymFields := cbNoSymFields.Checked;
  SaveSettings;
  RefreshPreview;
end;

{ ===========================================================================
  TfrmPrint.cbFitClick  (procedure)
  Parameters:
    Sender: TObject - the check box
  Notes:
    CSpecialPrintDlg::OnFit: ticked, the box shows the scale that fits the sheet on one page and
    cannot be typed in; unticked, it can be and shows the scale the dialog started with.
  =========================================================================== }
procedure TfrmPrint.cbFitClick(Sender: TObject);
begin
  if FStarting then
    Exit;
  if cbFit.Checked then
  begin
    edScale.Text := PrintScaleText(PrintFitScale(FDev, FSheetW, FSheetH));
    edScale.Enabled := False;
  end
  else
  begin
    edScale.Enabled := True;
    edScale.Text := PrintScaleText(FInitScale);
  end;
  UpdateTexts;
end;

{ ===========================================================================
  TfrmPrint.FormActivate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfrmPrint.FormActivate(Sender: TObject);
begin
  inherited;
  AddCustomButton(rsPrint, mrOK);
  SetButtons([fcbCancel]);
end;

{ ===========================================================================
  TfrmPrint.btnPrinterSetupClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The Printer Setup button: shows the system's setup dialog for the printer (the handler does
    that); the pages are laid out again on the page it leaves.
  =========================================================================== }
procedure TfrmPrint.btnPrinterSetupClick(Sender: TObject);
begin
  if Assigned(FOnPrinterSetup) then
    if FOnPrinterSetup(Self) then
      UpdateTexts;
end;

{ ===========================================================================
  TfrmPrint.RevertPrinter  (procedure)
  Parameters:  none
  Notes:
    Puts the printer list back on the entry that was in use, without a change event (a printer
    that was chosen and refused).
  =========================================================================== }
procedure TfrmPrint.RevertPrinter;
begin
  FStarting := True;
  try
    if (FLastPrinter >= 0) and (FLastPrinter < cbPrinterList.Items.Count) then
      cbPrinterList.ItemIndex := FLastPrinter;
  finally
    FStarting := False;
  end;
end;

{ ===========================================================================
  TfrmPrint.PrinterListChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    A printer was chosen: the handler makes it the printer in use and gives the dialog its page
    (SetDevice).
  =========================================================================== }
procedure TfrmPrint.PrinterListChange(Sender: TObject);
begin
  if FStarting or (not cbPrinterList.Enabled) then
    Exit;
  if cbPrinterList.ItemIndex = FLastPrinter then
    Exit;      // (the list can report a change to the entry it already shows, as Windows does when the dialog opens: nothing to do)
  if Assigned(FOnPrinterPick) then
    FOnPrinterPick(Self, cbPrinterList.ItemIndex);
  if cbPrinterList.ItemIndex >= 0 then
    FLastPrinter := cbPrinterList.ItemIndex;
  UpdateTexts;
end;

{ ===========================================================================
  TfrmPrint.CloseQuery  (procedure)
  Parameters:
    Sender: TObject - the form
    var CanClose: Boolean - set False to keep the dialog open
  Notes:
    Pressing OK checks the scale first and keeps the dialog open with a message if it is no use.
  =========================================================================== }
procedure TfrmPrint.CloseQuery(Sender: TObject; var CanClose: Boolean);
var
  Err: String;
begin
  if (ModalResult <> mrOK) then
    Exit;
  Err := ValidationError;
  if Err <> '' then
  begin
    MessageDlg(rsPrint2, Err, mtWarning, [mbOK], 0);
    CanClose := False;
    ModalResult := mrNone;
  end;
end;

{ ===========================================================================
  TfrmPrint.KeepInSettings  (procedure)
  Parameters:  none
  Notes:
    CSpecialPrintDlg::OnOK: the scale in the box is kept in the settings (with the black and
    white choice, which was kept when it was clicked).
  =========================================================================== }
procedure TfrmPrint.KeepInSettings;
begin
  ProgramSettings.PrintScale := PrintScaleValue(edScale.Text);
  ProgramSettings.PrintBandW := cbBW.Checked;
  ProgramSettings.PrintNoSymFields := cbNoSymFields.Checked;
  ProgramSettings.PrintNoSymText := cbNoSymText.Checked;
  SaveSettings;
end;

{ ===========================================================================
  TfrmPrint.CurrentLayout  (function)
  Parameters:  none
  Returns:
    TPrintLayout
  Notes:
    What the quick preview draws from; Pages is 0 when the scale cannot be used.
  =========================================================================== }
function TfrmPrint.CurrentLayout: TPrintLayout;
var
  V: Double;
begin
  V := PrintScaleValue(edScale.Text);
  if (V <= 0) or (V > PRINT_MAX_SCALE) then
  begin
    FillChar(Result, SizeOf(Result), 0);
    Exit;
  end;
  Result := PrintLayoutFor(FDev, FSheetW, FSheetH, V, rbAll.Checked, FSheetCount);
end;

{ ===========================================================================
  TfrmPrint.RefreshChosen  (procedure)
  Parameters:  none
  Notes:
    Reads the Pages box: FChosen holds the pages it names (every page when the box is on All)
    and FChosenError why it cannot be read.
  =========================================================================== }
procedure TfrmPrint.RefreshChosen;
var
  N, I: Integer;
begin
  FChosen := nil;
  FChosenError := '';
  N := PageCount;
  if rbPagesRange.Checked then
  begin
    if not ParsePageRange(edPageRange.Text, N, FChosen, FChosenError) then
      FChosen := nil;
  end
  else
  begin
    SetLength(FChosen, N);
    for I := 0 to N - 1 do
      FChosen[I] := I + 1;
  end;
end;

{ ===========================================================================
  TfrmPrint.PreviewPages  (function)
  Parameters:  none
  Returns:
    TPageArray
  Notes:
    The pages the Pages box names (every page when it is on All); none when the box or the scale
    cannot be used.
  =========================================================================== }
function TfrmPrint.PreviewPages: TPageArray;
begin
  Result := FChosen;
end;

{ ===========================================================================
  TfrmPrint.PageOfText  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    "Page 6 of 12": the page showing and the number of pages in the print; "No pages" when the
    scale or the pages cannot be used.
  =========================================================================== }
function TfrmPrint.PageOfText: String;
begin
  if Length(FChosen) = 0 then
    Result := rsNoPages
  else
    Result := Format(rsPageOf, [FShown, PageCount]);
end;

{ ===========================================================================
  TfrmPrint.RefreshPreview  (procedure)
  Parameters:  none
  Notes:
    Called when anything that changes the pages has changed: keeps the page showing when it is
    still one of the pages (else the nearest one after it, or the last), sets the slider (one
    position for each page asked for), the buttons and the label, and has the preview painted
    again.
  =========================================================================== }
procedure TfrmPrint.RefreshPreview;
var
  I, Idx: Integer;
begin
  if FPreviewBmp = nil then
    Exit;
  Idx := -1;
  for I := 0 to High(FChosen) do
    if FChosen[I] >= FShown then begin
      Idx := I;
      Break;
    end;
  if (Idx < 0) and (Length(FChosen) > 0) then
    Idx := High(FChosen);
  if Idx >= 0 then
    FShown := FChosen[Idx];
  FSyncing := True;
  try
    tbPageSlider.Min := 1;
    tbPageSlider.Max := Max(1, Length(FChosen));
    tbPageSlider.Position := Max(1, Idx + 1);
  finally
    FSyncing := False;
  end;
  tbPageSlider.Enabled := Length(FChosen) > 1;
  btnPreviewBack.Enabled := Idx > 0;
  btnPreviewFwd.Enabled := (Idx >= 0) and (Idx < High(FChosen));
  lbPageOf.Caption := PageOfText;
  if Length(FChosen) > 1 then
    lbPageOf.Hint := Format(rsShowingPageOfThePages, [Idx + 1, Length(FChosen)])
  else
    lbPageOf.Hint := '';
  pbFastPreview.Invalidate;
end;

{ ===========================================================================
  TfrmPrint.GoToIndex  (procedure)
  Parameters:
    AIndex: Integer - whole number
  Notes:
    Shows that one of the pages chosen (nothing happens for a position that is not there).
  =========================================================================== }
procedure TfrmPrint.GoToIndex(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FChosen)) then
    Exit;
  FShown := FChosen[AIndex];
  RefreshPreview;
end;

{ ===========================================================================
  TfrmPrint.ShowPage  (procedure)
  Parameters:
    PageNo: Integer - whole number
  Notes:
    For tests and the main form: shows that page in the quick preview, or the next page chosen
    after it (the last one if there is none).
  =========================================================================== }
procedure TfrmPrint.ShowPage(PageNo: Integer);
begin
  FShown := PageNo;
  RefreshPreview;
end;

{ ===========================================================================
  TfrmPrint.btnPreviewBackClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The page before the one showing, among the pages chosen.
  =========================================================================== }
procedure TfrmPrint.btnPreviewBackClick(Sender: TObject);
begin
  GoToIndex(tbPageSlider.Position - 2);
end;

{ ===========================================================================
  TfrmPrint.btnPreviewFwdClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The page after the one showing, among the pages chosen.
  =========================================================================== }
procedure TfrmPrint.btnPreviewFwdClick(Sender: TObject);
begin
  GoToIndex(tbPageSlider.Position);
end;

{ ===========================================================================
  TfrmPrint.PageSliderChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The slider was moved: shows the page at that position among the pages chosen.
  =========================================================================== }
procedure TfrmPrint.PageSliderChange(Sender: TObject);
begin
  if FSyncing then
    Exit;
  GoToIndex(tbPageSlider.Position - 1);
end;

{ ===========================================================================
  TfrmPrint.DrawPreview  (procedure)
  Parameters:
    C: TCanvas
    AW: Integer - whole number
    AH: Integer - whole number
  Notes:
    The quick preview: the page showing, drawn small by the same code that prints it (the main
    form's OnPaintPage), in the shape of the printer's page and as big as fits the box, with a
    shadow and a frame. The picture is kept until the page, the scale, the sheets, black and
    white, the printer's page or the size of the box change. Nothing is drawn but the grey
    background when there are no pages to show.
  =========================================================================== }
procedure TfrmPrint.DrawPreview(C: TCanvas; AW, AH: Integer);
var
  L: TPrintLayout;
  PgW, PgH, W, H, X, Y: Integer;
  F: Double;
  Key: String;
begin
  C.Brush.Color := clAppWorkspace;
  C.FillRect(0, 0, AW, AH);
  if (Length(FChosen) = 0) or (not Assigned(FOnPaintPage)) or (FDev.Dpi < 1) then
    Exit;
  L := CurrentLayout;
  if (L.Pages < 1) or (FShown < 1) or (FShown > L.Pages) then
    Exit;
  PgW := Max(1, Round(FDev.HorzMm / 25.4 * FDev.Dpi));
  PgH := Max(1, Round(FDev.VertMm / 25.4 * FDev.Dpi));
  F := Min((AW - 8) / PgW, (AH - 8) / PgH);
  if F <= 0 then
    Exit;
  W := Max(1, Round(PgW * F));
  H := Max(1, Round(PgH * F));
  Key := Format('%d|%s|%d|%d|%d|%d|%d|%d|%d|%d', [FShown, edScale.Text, Ord(cbBW.Checked) + 2 * Ord(cbNoSymText.Checked) + 4 * Ord(cbNoSymFields.Checked), Ord(rbAll.Checked), FDev.HorzMm, FDev.VertMm, FDev.Dpi, W, H, FSheetCount]);
  if (Key <> FPreviewKey) or (FPreviewBmp.Width <> W) or (FPreviewBmp.Height <> H) then
  begin
    FPreviewBmp.SetSize(W, H);
    FPreviewBmp.Canvas.Brush.Color := clWhite;
    FPreviewBmp.Canvas.FillRect(0, 0, W, H);
    FOnPaintPage(Self, L, FDev, FShown, FPreviewBmp.Canvas, W, H, cbBW.Checked, F);
    FPreviewKey := Key;
  end;
  X := (AW - W) div 2;
  Y := (AH - H) div 2;
  C.Brush.Color := clBlack;
  C.FillRect(X + 3, Y + 3, X + W + 3, Y + H + 3);
  C.Draw(X, Y, FPreviewBmp);
  C.Brush.Style := bsClear;
  C.Pen.Color := clBlack;
  C.Rectangle(X - 1, Y - 1, X + W + 1, Y + H + 1);
end;

{ ===========================================================================
  TfrmPrint.FastPreviewPaint  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    OnPaint of the quick preview: draws it on the box (see DrawPreview).
  =========================================================================== }
procedure TfrmPrint.FastPreviewPaint(Sender: TObject);
begin
  DrawPreview(pbFastPreview.Canvas, pbFastPreview.Width, pbFastPreview.Height);
end;

end.
