{ The Print Preview window (MFC's preview mode of TinyCAD): the pages the Print command would print, drawn on the printer's page at the scale and black and white
  of the settings, with buttons for Print..., Next Page, Prev Page, One/Two Page, Zoom In, Zoom Out and Close. The preview shows every sheet of the design, as
  TinyCAD's does (its print-all-sheets choice only changes when the Print dialog is used). Pages are drawn when they are first shown and kept until the zoom
  changes.

  The printer's page is the installed printer's, or an A4 page when there is none. The window ends with mrYes when Print... is pressed (the caller then shows the
  Print dialog) and mrOK for Close.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fpreview;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Math, LCLType, UDesign, UPrint, UPrintRun;

const
  PREVIEW_ZOOM_STEPS = 3;            // Zoom In goes this many steps above the whole page
  PREVIEW_ZOOM_FACTOR = 1.5;         // ... each making the page this much bigger

type

  { TfrmPreview }

  TfrmPreview = class(TForm)
    btnClose: TButton;
    btnNext: TButton;
    btnPrev: TButton;
    btnPrint: TButton;
    btnTwo: TButton;
    btnZoomIn: TButton;
    btnZoomOut: TButton;
    lbStatus: TLabel;
    pbPage: TPaintBox;
    pnlBottom: TPanel;
    pnlTop: TPanel;
    sbPages: TScrollBox;
    procedure btnNextClick(Sender: TObject);
    procedure btnPrevClick(Sender: TObject);
    procedure btnTwoClick(Sender: TObject);
    procedure btnZoomInClick(Sender: TObject);
    procedure btnZoomOutClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormResize(Sender: TObject);
    procedure pbPageMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure pbPagePaint(Sender: TObject);
  private
    FDesign: TDesignFile;
    FActive: Integer;
    FSink: TPrintSink;           // owned: it only tells the size of the printer's page
    FOpt: TPrintOptions;
    FLayout: TPrintLayout;
    FCurrent: Integer;           // the first page showing, from 1
    FTwo: Boolean;
    FZoomStep: Integer;
    FFactor: Double;             // the size of a shown page over the printer's page
    FCache: array of TBitmap;
    procedure ClearCache;
    procedure Relayout;
    procedure UpdateButtons;
    function Shown: Integer;
    function BitmapOf(PageNo: Integer): TBitmap;
    function FitFactor: Double;
  public
    destructor Destroy; override;
    { the design, the sheet showing, the printer's page (the window owns the sink) and the options of the preview (the scale and black and white of the settings) }
    procedure SetPreview(ADesign: TDesignFile; AActive: Integer; ASink: TPrintSink; const AOpt: TPrintOptions);
    procedure NextPage;
    procedure PrevPage;
    procedure ToggleTwoPage;
    procedure ZoomIn;
    procedure ZoomOut;
    { the preview as text, for tests: the page showing, the pages shown, the page count, two-page mode, the zoom step, the state of the buttons and the status line }
    function InfoText: String;
    { a page as the preview draws it, for tests (a bitmap kept by the window) }
    function PageBitmap(PageNo: Integer): TBitmap;
    property Current: Integer read FCurrent;
    property TwoPage: Boolean read FTwo;
    property ZoomStep: Integer read FZoomStep;
    property Layout: TPrintLayout read FLayout;
    property Factor: Double read FFactor;
  end;

var
  frmPreview: TfrmPreview;

implementation


uses UStrings;

{$R *.lfm}

const
  MARGIN = 16;          // round the pages
  GAP = 16;             // between two pages

{ ===========================================================================
  TfrmPreview.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the form
  Notes:
    Starts with the first page, one page at a time, the whole page showing.
  =========================================================================== }
procedure TfrmPreview.FormCreate(Sender: TObject);
begin
  FCurrent := 1;
  FZoomStep := 0;
  FFactor := 0.1;
end;

{ ===========================================================================
  TfrmPreview.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the page bitmaps and the printer's page.
  =========================================================================== }
destructor TfrmPreview.Destroy;
begin
  ClearCache;
  FSink.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TfrmPreview.ClearCache  (procedure)
  Parameters:  none
  Notes:
    Drops every page that was drawn, so they are drawn again at the new size.
  =========================================================================== }
procedure TfrmPreview.ClearCache;
var
  I: Integer;
begin
  for I := 0 to High(FCache) do FreeAndNil(FCache[I]);
end;

{ ===========================================================================
  TfrmPreview.SetPreview  (procedure)
  Parameters:
    ADesign: TDesignFile - the design
    AActive: Integer - the sheet showing
    ASink: TPrintSink - the printer's page (the window keeps it)
    const AOpt: TPrintOptions - scale, black and white and sheets
  Notes:
    Lays the pages out (OnBeginPrinting) and shows the first.
  =========================================================================== }
procedure TfrmPreview.SetPreview(ADesign: TDesignFile; AActive: Integer; ASink: TPrintSink; const AOpt: TPrintOptions);
begin
  ClearCache;
  FDesign := ADesign;
  FActive := AActive;
  FSink.Free;
  FSink := ASink;
  FOpt := AOpt;
  FLayout := PrintLayoutOf(FDesign, FActive, FSink, FOpt);
  SetLength(FCache, FLayout.Pages + 1);
  FCurrent := 1;
  FTwo := False;
  FZoomStep := 0;
  Relayout;
end;

{ ===========================================================================
  TfrmPreview.Shown  (function)
  Parameters:  none
  Returns:
    Integer - how many pages are showing
  Notes:
    One, or two in two-page mode when there is a page after the current.
  =========================================================================== }
function TfrmPreview.Shown: Integer;
begin
  if FTwo and (FCurrent < FLayout.Pages) then
    Result := 2
  else
    Result := 1;
end;

{ ===========================================================================
  TfrmPreview.FitFactor  (function)
  Parameters:  none
  Returns:
    Double - the size of a page that fits the window, over the printer's page
  Notes:
    The largest pages (one, or two side by side) that fit the window with a margin round them.
  =========================================================================== }
function TfrmPreview.FitFactor: Double;
var
  AW, AH, N: Integer;
begin
  N := Shown;
  AW := Max(1, sbPages.ClientWidth - 2 * MARGIN - (N - 1) * GAP);
  AH := Max(1, sbPages.ClientHeight - 2 * MARGIN);
  Result := Min(AW / (N * Max(1, FSink.PageWidth)), AH / Max(1, FSink.PageHeight));
end;

{ ===========================================================================
  TfrmPreview.Relayout  (procedure)
  Parameters:  none
  Notes:
    Works out the size of the pages from the zoom and the window, sizes the paint box to hold
    them (the window scrolls when they are larger) and redraws.
  =========================================================================== }
procedure TfrmPreview.Relayout;
var
  F: Double;
  W, H, N: Integer;
begin
  if FSink = nil then
    Exit;
  F := FitFactor;
  if F <= 0 then
    F := 0.01;
  F := F * Power(PREVIEW_ZOOM_FACTOR, FZoomStep);
  if Abs(F - FFactor) > 1e-9 then
    ClearCache;
  FFactor := F;
  N := Shown;
  W := 2 * MARGIN + (N - 1) * GAP + N * Round(FSink.PageWidth * F);
  H := 2 * MARGIN + Round(FSink.PageHeight * F);
  pbPage.SetBounds(0, 0, Max(W, sbPages.ClientWidth), Max(H, sbPages.ClientHeight));
  UpdateButtons;
  pbPage.Invalidate;
end;

{ ===========================================================================
  TfrmPreview.UpdateButtons  (procedure)
  Parameters:  none
  Notes:
    Dims what cannot be done (no next page after the last, no more zoom) and says which page is
    showing.
  =========================================================================== }
procedure TfrmPreview.UpdateButtons;
begin
  btnNext.Enabled := FCurrent + Shown - 1 < FLayout.Pages;
  btnPrev.Enabled := FCurrent > 1;
  btnZoomIn.Enabled := FZoomStep < PREVIEW_ZOOM_STEPS;
  btnZoomOut.Enabled := FZoomStep > 0;
  btnTwo.Enabled := FLayout.Pages > 1;
  if FTwo then
    btnTwo.Caption := rsOnePage
  else
    btnTwo.Caption := rsTwoPage;
  if Shown = 2 then
    lbStatus.Caption := Format(rsPagesOf, [FCurrent, FCurrent + 1, FLayout.Pages])
  else
    lbStatus.Caption := Format(rsPageOf, [FCurrent, FLayout.Pages]);
end;

{ ===========================================================================
  TfrmPreview.BitmapOf  (function)
  Parameters:
    PageNo: Integer - page number from 1
  Returns:
    TBitmap - the page, drawn on white paper at the size of the shown pages
  Notes:
    Draws the page on first use and keeps it until the size changes.
  =========================================================================== }
function TfrmPreview.BitmapOf(PageNo: Integer): TBitmap;
var
  W, H: Integer;
begin
  if (PageNo < 1) or (PageNo > FLayout.Pages) then
    Exit(nil);
  if FCache[PageNo] = nil then
  begin
    W := Max(1, Round(FSink.PageWidth * FFactor));
    H := Max(1, Round(FSink.PageHeight * FFactor));
    Result := TBitmap.Create;
    Result.PixelFormat := pf24bit;
    Result.SetSize(W, H);
    Result.Canvas.Brush.Color := clWhite;
    Result.Canvas.Brush.Style := bsSolid;
    Result.Canvas.FillRect(0, 0, W, H);
    RenderPrintPage(FDesign, FActive, FLayout, FSink.Device, PageNo, Result.Canvas, W, H, FOpt.BlackWhite, FFactor, FOpt.NoSymbolText, FOpt.NoSymbolFields);
    FCache[PageNo] := Result;
  end;
  Result := FCache[PageNo];
end;

{ ===========================================================================
  TfrmPreview.PageBitmap  (function)
  Parameters:
    PageNo: Integer - page number from 1
  Returns:
    TBitmap - the page as the preview draws it, nil if there is no such page
  Notes:
    For tests.
  =========================================================================== }
function TfrmPreview.PageBitmap(PageNo: Integer): TBitmap;
begin
  Result := BitmapOf(PageNo);
end;

{ ===========================================================================
  TfrmPreview.pbPagePaint  (procedure)
  Parameters:
    Sender: TObject - the paint box
  Notes:
    Draws the shown page or pages with a shadow, on the grey background.
  =========================================================================== }
procedure TfrmPreview.pbPagePaint(Sender: TObject);
var
  C: TCanvas;
  I, X, Y, W, H, TotalW: Integer;
  B: TBitmap;
begin
  C := pbPage.Canvas;
  C.Brush.Color := clAppWorkspace;
  C.FillRect(0, 0, pbPage.Width, pbPage.Height);
  if (FSink = nil) or (FLayout.Pages < 1) then
    Exit;
  W := Max(1, Round(FSink.PageWidth * FFactor));
  H := Max(1, Round(FSink.PageHeight * FFactor));
  TotalW := Shown * W + (Shown - 1) * GAP;
  X := Max(MARGIN, (pbPage.Width - TotalW) div 2);
  Y := Max(MARGIN, (pbPage.Height - H) div 2);
  for I := 0 to Shown - 1 do
  begin
    C.Brush.Color := clBlack;
    C.FillRect(X + 4, Y + 4, X + W + 4, Y + H + 4);
    B := BitmapOf(FCurrent + I);
    if B <> nil then
      C.Draw(X, Y, B);
    C.Brush.Style := bsClear;
    C.Pen.Color := clBlack;
    C.Rectangle(X - 1, Y - 1, X + W + 1, Y + H + 1);
    Inc(X, W + GAP);
  end;
end;

{ ===========================================================================
  TfrmPreview.NextPage  (procedure)
  Parameters:  none
  Notes:
    The Next Page button: the pages after the ones showing (nothing at the end).
  =========================================================================== }
procedure TfrmPreview.NextPage;
begin
  if FCurrent + Shown - 1 >= FLayout.Pages then
    Exit;
  FCurrent := FCurrent + Shown;
  Relayout;
end;

{ ===========================================================================
  TfrmPreview.PrevPage  (procedure)
  Parameters:  none
  Notes:
    The Prev Page button: the pages before the ones showing (nothing at the start).
  =========================================================================== }
procedure TfrmPreview.PrevPage;
begin
  if FCurrent <= 1 then
    Exit;
  if FTwo then
    FCurrent := Max(1, FCurrent - 2)
  else
    FCurrent := Max(1, FCurrent - 1);
  Relayout;
end;

{ ===========================================================================
  TfrmPreview.ToggleTwoPage  (procedure)
  Parameters:  none
  Notes:
    The One Page / Two Page button. The page showing stays the first of those shown.
  =========================================================================== }
procedure TfrmPreview.ToggleTwoPage;
begin
  if FLayout.Pages < 2 then
    Exit;
  FTwo := not FTwo;
  Relayout;
end;

{ ===========================================================================
  TfrmPreview.ZoomIn  (procedure)
  Parameters:  none
  Notes:
    The Zoom In button: the pages one step larger (up to three steps over the whole page).
  =========================================================================== }
procedure TfrmPreview.ZoomIn;
begin
  if FZoomStep >= PREVIEW_ZOOM_STEPS then
    Exit;
  Inc(FZoomStep);
  Relayout;
end;

{ ===========================================================================
  TfrmPreview.ZoomOut  (procedure)
  Parameters:  none
  Notes:
    The Zoom Out button: the pages one step smaller (down to the whole page).
  =========================================================================== }
procedure TfrmPreview.ZoomOut;
begin
  if FZoomStep <= 0 then
    Exit;
  Dec(FZoomStep);
  Relayout;
end;

{ ===========================================================================
  TfrmPreview.btnNextClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    Next Page.
  =========================================================================== }
procedure TfrmPreview.btnNextClick(Sender: TObject);
begin
  NextPage;
end;

{ ===========================================================================
  TfrmPreview.btnPrevClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    Prev Page.
  =========================================================================== }
procedure TfrmPreview.btnPrevClick(Sender: TObject);
begin
  PrevPage;
end;

{ ===========================================================================
  TfrmPreview.btnTwoClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    One Page / Two Page.
  =========================================================================== }
procedure TfrmPreview.btnTwoClick(Sender: TObject);
begin
  ToggleTwoPage;
end;

{ ===========================================================================
  TfrmPreview.btnZoomInClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    Zoom In.
  =========================================================================== }
procedure TfrmPreview.btnZoomInClick(Sender: TObject);
begin
  ZoomIn;
end;

{ ===========================================================================
  TfrmPreview.btnZoomOutClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    Zoom Out.
  =========================================================================== }
procedure TfrmPreview.btnZoomOutClick(Sender: TObject);
begin
  ZoomOut;
end;

{ ===========================================================================
  TfrmPreview.pbPageMouseUp  (procedure)
  Parameters:
    Sender: TObject - the paint box
    Button: TMouseButton - the button
    Shift: TShiftState - modifier keys
    X: Integer - position
    Y: Integer - position
  Notes:
    A click on the pages zooms in a step, and from the largest size goes back to the whole page
    (MFC's preview does the same).
  =========================================================================== }
procedure TfrmPreview.pbPageMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then
    Exit;
  if FZoomStep < PREVIEW_ZOOM_STEPS then
    ZoomIn
  else begin
    FZoomStep := 0;
    Relayout;
  end;
end;

{ ===========================================================================
  TfrmPreview.FormResize  (procedure)
  Parameters:
    Sender: TObject - the form
  Notes:
    The pages are made to fit the new window size.
  =========================================================================== }
procedure TfrmPreview.FormResize(Sender: TObject);
begin
  Relayout;
end;

{ ===========================================================================
  TfrmPreview.FormKeyDown  (procedure)
  Parameters:
    Sender: TObject - the form
    var Key: Word - the key
    Shift: TShiftState - modifier keys
  Notes:
    Page Down / Page Up change pages, Escape closes the window.
  =========================================================================== }
procedure TfrmPreview.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_NEXT: begin
      NextPage;
      Key := 0;
    end;
    VK_PRIOR: begin
      PrevPage;
      Key := 0;
    end;
    VK_ESCAPE: begin
      ModalResult := mrOK;
      Key := 0;
    end;
  end;
end;

{ ===========================================================================
  TfrmPreview.FormCloseQuery  (procedure)
  Parameters:
    Sender: TObject - the form
    var CanClose: Boolean - set False to keep the window open
  Notes:
    The window can always be closed.
  =========================================================================== }
procedure TfrmPreview.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
end;

{ ===========================================================================
  TfrmPreview.InfoText  (function)
  Parameters:  none
  Returns:
    String - the window's state
  Notes:
    For tests: "page=3 shown=2 pages=8 two=1 zoom=0 next=1 prev=1 zoomin=1 zoomout=0
    twocaption=... status=...".
  =========================================================================== }
function TfrmPreview.InfoText: String;
begin
  Result := Format('page=%d shown=%d pages=%d cols=%d rows=%d two=%d zoom=%d next=%d prev=%d zoomin=%d zoomout=%d twobutton=%d twocaption=%s status=%s',
    [FCurrent, Shown, FLayout.Pages, FLayout.Cols, FLayout.Rows, Ord(FTwo), FZoomStep, Ord(btnNext.Enabled), Ord(btnPrev.Enabled), Ord(btnZoomIn.Enabled),
     Ord(btnZoomOut.Enabled), Ord(btnTwo.Enabled), StringReplace(btnTwo.Caption, '&', '', []), lbStatus.Caption]);
end;

end.
