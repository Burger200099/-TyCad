{ Printing a design: drawing one printed page onto a canvas, where the pages go (a printer, or bitmaps for the print preview and for tests) and the print job that
  cuts a design into pages and sends them (the drawing half of CTinyCadView::OnBeginPrinting / OnPrepareDC / OnDraw while printing, and the loop MFC runs).

  The arithmetic (how many pages, which part of which sheet each shows) is in UPrint. A page is drawn as the screen is, with a transform whose origin is the part of
  the sheet the page shows and whose zoom is the print zoom, except that nothing is drawn behind the sheet (no paper, shadow or grid), construction objects are
  left out, nothing is selected, and everything can be black.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UPrintRun;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Math, Types, Printers, OSPrinters, UDPoint, UGeometry, UDesign, UDocVars, UPrint, UPainter;

const
  VIRTUAL_DPI = 300;               // the resolution of the page used when no printer is installed (for the preview)
  VIRTUAL_LONG_MM = 297;           // ... A4
  VIRTUAL_SHORT_MM = 210;

type
  { what the Print dialog decides }
  TPrintOptions = record
    Scale: Double;                 // per cent
    BlackWhite: Boolean;
    NoSymbolText: Boolean;         // symbol text (the designer's notes) is left off
    NoSymbolFields: Boolean;       // the fields of the symbols (reference, name, values) are left off
    AllSheets: Boolean;
    FromPage, ToPage: Integer;     // 0 and 0 for every page
    Pages: TPageArray;             // the pages to print, ascending (typed page ranges); empty to use FromPage/ToPage
    Copies: Integer;
    Collate: Boolean;
  end;

  { where printed pages go }
  TPrintSink = class
  public
    { the printer's page as the layout needs it }
    function Device: TPrintDevice; virtual; abstract;
    function PageWidth: Integer; virtual; abstract;       // the page in pixels
    function PageHeight: Integer; virtual; abstract;
    function Name: String; virtual; abstract;             // what to call it in the dialog
    function Available: Boolean; virtual; abstract;       // False when there is nothing to print on
    function RendersCopies: Boolean; virtual;
    procedure SetCopies(N: Integer); virtual;
    procedure BeginDoc(const Title: String); virtual; abstract;
    function Canvas: TCanvas; virtual; abstract;          // the canvas of the page being drawn
    procedure NewPage; virtual; abstract;
    procedure EndDoc; virtual; abstract;
    procedure Abort; virtual; abstract;
  end;

  { the installed printer (the default one, or the one chosen in the dialogs) }
  TPrinterSink = class(TPrintSink)
  public
    constructor Create(Portrait: Boolean);
    function Device: TPrintDevice; override;
    function PageWidth: Integer; override;
    function PageHeight: Integer; override;
    function Name: String; override;
    function Available: Boolean; override;
    function RendersCopies: Boolean; override;
    procedure SetCopies(N: Integer); override;
    procedure BeginDoc(const Title: String); override;
    function Canvas: TCanvas; override;
    procedure NewPage; override;
    procedure EndDoc; override;
    procedure Abort; override;
  end;

  { a page that is only a bitmap: the print preview, when no printer is installed, and tests. Each page is a bitmap kept in Pages; at EndDoc each is also
    written to OutDir as page_<n>.png when that is given }
  TVirtualSink = class(TPrintSink)
  private
    FHorzMm, FVertMm, FDpi: Integer;
    FOutDir: String;
    FPages: TList;
    FCanvas: TCanvas;
    procedure ClearPages;
  public
    constructor Create(Portrait: Boolean; ADpi: Integer = VIRTUAL_DPI; const AOutDir: String = '');
    destructor Destroy; override;
    function Device: TPrintDevice; override;
    function PageWidth: Integer; override;
    function PageHeight: Integer; override;
    function Name: String; override;
    function Available: Boolean; override;
    procedure BeginDoc(const Title: String); override;
    function Canvas: TCanvas; override;
    procedure NewPage; override;
    procedure EndDoc; override;
    procedure Abort; override;
    function PageCount: Integer;
    function Page(Index: Integer): TBitmap;
  end;

{ whether a sheet is printed with the printer turned the tall way (CDetails::IsPortrait) }
function SheetIsPortrait(Sheet: TDesignSheet): Boolean;
{ the pages a design will take at these options, on this sink }
function PrintLayoutOf(Design: TDesignFile; ActiveSheet: Integer; Sink: TPrintSink; const Opt: TPrintOptions): TPrintLayout;
{ draw page PageNo of the layout onto a canvas PxW by PxH; Factor scales the whole page (1 for the printer itself, less for a preview) }
procedure RenderPrintPage(Design: TDesignFile; ActiveSheet: Integer; const L: TPrintLayout; const Dev: TPrintDevice; PageNo: Integer; ACanvas: TCanvas;
  PxW, PxH: Integer; Black: Boolean; Factor: Double = 1.0; NoSymText: Boolean = False; NoSymFields: Boolean = False);
{ print a design on a sink; returns the number of pages sent (not counting copies the printer makes) }
function RunPrintJob(Design: TDesignFile; ActiveSheet: Integer; const Opt: TPrintOptions; Sink: TPrintSink; const Title: String): Integer;
function DefaultPrintOptions: TPrintOptions;

implementation


uses UStrings;

{ ===========================================================================
  TPrintSink.RendersCopies  (function)
  Parameters:  none
  Returns:
    Boolean - True if the printer makes the copies itself
  Notes:
    By default a sink does not, and the print job sends the pages again for each copy.
  =========================================================================== }
function TPrintSink.RendersCopies: Boolean;
begin
  Result := False;
end;

{ ===========================================================================
  TPrintSink.SetCopies  (procedure)
  Parameters:
    N: Integer - number of copies
  Notes:
    Asks the printer for that many copies; only used when it makes them itself.
  =========================================================================== }
procedure TPrintSink.SetCopies(N: Integer);
begin
end;

{ ===========================================================================
  TPrinterSink.Create  (constructor)
  Parameters:
    Portrait: Boolean - True to print the tall way
  Notes:
    The installed printer, turned to the sheet's orientation as TinyCAD does before it makes its
    device context.
  =========================================================================== }
constructor TPrinterSink.Create(Portrait: Boolean);
begin
  inherited Create;
  if Available then
  try
    if Portrait then
      Printer.Orientation := poPortrait
    else
      Printer.Orientation := poLandscape;
  except
    { a printer that cannot be turned prints the way it is set }
  end;
end;

{ ===========================================================================
  TPrinterSink.Available  (function)
  Parameters:  none
  Returns:
    Boolean - True if a printer is installed
  Notes:
    Whether there is a printer to print on.
  =========================================================================== }
function TPrinterSink.Available: Boolean;
begin
  try
    Result := Printer.Printers.Count > 0;
  except
    Result := False;
  end;
end;

{ ===========================================================================
  TPrinterSink.Device  (function)
  Parameters:  none
  Returns:
    TPrintDevice - the printer's page
  Notes:
    The width and height of the printable page in whole millimetres, and the resolution, as
    GetDeviceCaps gives them.
  =========================================================================== }
function TPrinterSink.Device: TPrintDevice;
var
  Dpi: Integer;
begin
  Dpi := Max(1, Printer.XDPI);
  Result := PrintDevice(Round(Printer.PageWidth / Dpi * 25.4), Round(Printer.PageHeight / Dpi * 25.4), Dpi);
end;

{ ===========================================================================
  TPrinterSink.PageWidth  (function)
  Parameters:  none
  Returns:
    Integer - width in pixels
  Notes:
    The printable width of the page in printer pixels.
  =========================================================================== }
function TPrinterSink.PageWidth: Integer;
begin
  Result := Printer.PageWidth;
end;

{ ===========================================================================
  TPrinterSink.PageHeight  (function)
  Parameters:  none
  Returns:
    Integer - height in pixels
  Notes:
    The printable height of the page in printer pixels.
  =========================================================================== }
function TPrinterSink.PageHeight: Integer;
begin
  Result := Printer.PageHeight;
end;

{ ===========================================================================
  TPrinterSink.Name  (function)
  Parameters:  none
  Returns:
    String - the printer's name
  Notes:
    The name of the printer in use.
  =========================================================================== }
function TPrinterSink.Name: String;
begin
  try
    Result := Printer.PrinterName;
  except
    Result := '';
  end;
end;

{ ===========================================================================
  TPrinterSink.RendersCopies  (function)
  Parameters:  none
  Returns:
    Boolean - True if the driver can make several copies
  Notes:
    Whether the printer makes the copies itself.
  =========================================================================== }
function TPrinterSink.RendersCopies: Boolean;
begin
  try
    Result := Printer.CanRenderCopies;
  except
    Result := False;
  end;
end;

{ ===========================================================================
  TPrinterSink.SetCopies  (procedure)
  Parameters:
    N: Integer - number of copies
  Notes:
    Tells the printer how many copies to make.
  =========================================================================== }
procedure TPrinterSink.SetCopies(N: Integer);
begin
  Printer.Copies := N;
end;

{ ===========================================================================
  TPrinterSink.BeginDoc  (procedure)
  Parameters:
    const Title: String - the name of the print job
  Notes:
    Starts the print job.
  =========================================================================== }
procedure TPrinterSink.BeginDoc(const Title: String);
begin
  Printer.Title := Title;
  Printer.BeginDoc;
end;

{ ===========================================================================
  TPrinterSink.Canvas  (function)
  Parameters:  none
  Returns:
    TCanvas - the page's canvas
  Notes:
    The canvas of the page being printed.
  =========================================================================== }
function TPrinterSink.Canvas: TCanvas;
begin
  Result := Printer.Canvas;
end;

{ ===========================================================================
  TPrinterSink.NewPage  (procedure)
  Parameters:  none
  Notes:
    Ends the page and starts the next.
  =========================================================================== }
procedure TPrinterSink.NewPage;
begin
  Printer.NewPage;
end;

{ ===========================================================================
  TPrinterSink.EndDoc  (procedure)
  Parameters:  none
  Notes:
    Ends the print job, which sends it to the printer.
  =========================================================================== }
procedure TPrinterSink.EndDoc;
begin
  Printer.EndDoc;
end;

{ ===========================================================================
  TPrinterSink.Abort  (procedure)
  Parameters:  none
  Notes:
    Stops a print job that failed part way.
  =========================================================================== }
procedure TPrinterSink.Abort;
begin
  if Printer.Printing then
    Printer.Abort;
end;

{ ===========================================================================
  TVirtualSink.Create  (constructor)
  Parameters:
    Portrait: Boolean - True for an A4 page the tall way
    ADpi: Integer - resolution of the page's bitmap
    const AOutDir: String - a folder to write each page to as a PNG file at the end ('' for none
      )
  Notes:
    A page of A4 paper that only exists as bitmaps.
  =========================================================================== }
constructor TVirtualSink.Create(Portrait: Boolean; ADpi: Integer; const AOutDir: String);
begin
  inherited Create;
  if Portrait then begin
    FHorzMm := VIRTUAL_SHORT_MM;
    FVertMm := VIRTUAL_LONG_MM;
  end
  else begin
    FHorzMm := VIRTUAL_LONG_MM;
    FVertMm := VIRTUAL_SHORT_MM;
  end;
  FDpi := Max(1, ADpi);
  FOutDir := AOutDir;
  FPages := TList.Create;
end;

{ ===========================================================================
  TVirtualSink.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the page bitmaps.
  =========================================================================== }
destructor TVirtualSink.Destroy;
begin
  ClearPages;
  FPages.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TVirtualSink.ClearPages  (procedure)
  Parameters:  none
  Notes:
    Frees every page bitmap.
  =========================================================================== }
procedure TVirtualSink.ClearPages;
var
  I: Integer;
begin
  for I := 0 to FPages.Count - 1 do TBitmap(FPages[I]).Free;
  FPages.Clear;
  FCanvas := nil;
end;

{ ===========================================================================
  TVirtualSink.Device  (function)
  Parameters:  none
  Returns:
    TPrintDevice - the page
  Notes:
    The page's size in millimetres and its resolution.
  =========================================================================== }
function TVirtualSink.Device: TPrintDevice;
begin
  Result := PrintDevice(FHorzMm, FVertMm, FDpi);
end;

{ ===========================================================================
  TVirtualSink.PageWidth  (function)
  Parameters:  none
  Returns:
    Integer - width in pixels
  Notes:
    The page's width at its resolution.
  =========================================================================== }
function TVirtualSink.PageWidth: Integer;
begin
  Result := Max(1, Round(FHorzMm / 25.4 * FDpi));
end;

{ ===========================================================================
  TVirtualSink.PageHeight  (function)
  Parameters:  none
  Returns:
    Integer - height in pixels
  Notes:
    The page's height at its resolution.
  =========================================================================== }
function TVirtualSink.PageHeight: Integer;
begin
  Result := Max(1, Round(FVertMm / 25.4 * FDpi));
end;

{ ===========================================================================
  TVirtualSink.Name  (function)
  Parameters:  none
  Returns:
    String - the name
  Notes:
    What this page is called.
  =========================================================================== }
function TVirtualSink.Name: String;
begin
  Result := rsA4PageNoPrinter;
end;

{ ===========================================================================
  TVirtualSink.Available  (function)
  Parameters:  none
  Returns:
    Boolean - always True
  Notes:
    A bitmap can always be drawn on.
  =========================================================================== }
function TVirtualSink.Available: Boolean;
begin
  Result := True;
end;

{ ===========================================================================
  TVirtualSink.BeginDoc  (procedure)
  Parameters:
    const Title: String - not used
  Notes:
    Starts a job: any pages of an earlier job are dropped and the first page is made.
  =========================================================================== }
procedure TVirtualSink.BeginDoc(const Title: String);
begin
  ClearPages;
  NewPage;
end;

{ ===========================================================================
  TVirtualSink.NewPage  (procedure)
  Parameters:  none
  Notes:
    Adds a white page and draws on that.
  =========================================================================== }
procedure TVirtualSink.NewPage;
var
  B: TBitmap;
begin
  B := TBitmap.Create;
  B.PixelFormat := pf24bit;
  B.SetSize(PageWidth, PageHeight);
  B.Canvas.Brush.Color := clWhite;
  B.Canvas.Brush.Style := bsSolid;
  B.Canvas.FillRect(0, 0, B.Width, B.Height);
  FPages.Add(B);
  FCanvas := B.Canvas;
end;

{ ===========================================================================
  TVirtualSink.Canvas  (function)
  Parameters:  none
  Returns:
    TCanvas - the canvas of the latest page
  Notes:
    The canvas to draw the current page on.
  =========================================================================== }
function TVirtualSink.Canvas: TCanvas;
begin
  Result := FCanvas;
end;

{ ===========================================================================
  TVirtualSink.EndDoc  (procedure)
  Parameters:  none
  Notes:
    Ends the job; the pages are written to the output folder if there is one.
  =========================================================================== }
procedure TVirtualSink.EndDoc;
var
  I: Integer;
  P: TPortableNetworkGraphic;
begin
  if FOutDir = '' then
    Exit;
  ForceDirectories(FOutDir);
  for I := 0 to FPages.Count - 1 do
  begin
    P := TPortableNetworkGraphic.Create;
    try
      P.Assign(TBitmap(FPages[I]));
      P.SaveToFile(IncludeTrailingPathDelimiter(FOutDir) + Format('page_%d.png', [I + 1]));
    finally
      P.Free;
    end;
  end;
end;

{ ===========================================================================
  TVirtualSink.Abort  (procedure)
  Parameters:  none
  Notes:
    Drops the pages of a job that failed.
  =========================================================================== }
procedure TVirtualSink.Abort;
begin
  ClearPages;
end;

{ ===========================================================================
  TVirtualSink.PageCount  (function)
  Parameters:  none
  Returns:
    Integer - the number of pages drawn
  Notes:
    How many pages the last job made.
  =========================================================================== }
function TVirtualSink.PageCount: Integer;
begin
  Result := FPages.Count;
end;

{ ===========================================================================
  TVirtualSink.Page  (function)
  Parameters:
    Index: Integer - page number from 0
  Returns:
    TBitmap - the page's bitmap (owned by the sink)
  Notes:
    One of the pages the last job made.
  =========================================================================== }
function TVirtualSink.Page(Index: Integer): TBitmap;
begin
  Result := TBitmap(FPages[Index]);
end;

{ ===========================================================================
  SheetIsPortrait  (function)
  Parameters:
    Sheet: TDesignSheet - the sheet
  Returns:
    Boolean - True if the sheet is taller than it is wide
  Notes:
    CDetails::IsPortrait: the page is turned the tall way when its width is less than its
    height.
  =========================================================================== }
function SheetIsPortrait(Sheet: TDesignSheet): Boolean;
begin
  Result := Sheet.Details.PageWidth < Sheet.Details.PageHeight;
end;

{ ===========================================================================
  DefaultPrintOptions  (function)
  Parameters:  none
  Returns:
    TPrintOptions - one copy of everything, at the scale in the settings
  Notes:
    The options of a print that asks nothing: every page, the sheet shown or all the sheets as
    asked.
  =========================================================================== }
function DefaultPrintOptions: TPrintOptions;
begin
  Result.Scale := PRINT_DEFAULT_SCALE;
  Result.BlackWhite := False;
  Result.NoSymbolText := False;
  Result.NoSymbolFields := False;
  Result.AllSheets := False;
  Result.FromPage := 0;
  Result.ToPage := 0;
  Result.Pages := nil;
  Result.Copies := 1;
  Result.Collate := False;
end;

{ ===========================================================================
  PrintLayoutOf  (function)
  Parameters:
    Design: TDesignFile - the design
    ActiveSheet: Integer - the sheet showing
    Sink: TPrintSink - where it will print
    const Opt: TPrintOptions - the options
  Returns:
    TPrintLayout - the pages
  Notes:
    OnBeginPrinting: the size of the sheet showing (not of the others) against the printer's
    page, at the scale chosen.
  =========================================================================== }
function PrintLayoutOf(Design: TDesignFile; ActiveSheet: Integer; Sink: TPrintSink; const Opt: TPrintOptions): TPrintLayout;
var
  D: TDetails;
begin
  D := Design.Sheets[ActiveSheet].Details;
  Result := PrintLayoutFor(Sink.Device, D.PageWidth, D.PageHeight, Opt.Scale, Opt.AllSheets, Design.SheetCount);
end;

{ ===========================================================================
  RenderPrintPage  (procedure)
  Parameters:
    Design: TDesignFile - the design
    ActiveSheet: Integer - the sheet showing (the one printed when not all are)
    const L: TPrintLayout - the layout
    const Dev: TPrintDevice - the printer's page
    PageNo: Integer - page number, from 1
    ACanvas: TCanvas - where to draw
    PxW: Integer - width of the canvas in pixels
    PxH: Integer - height of the canvas in pixels
    Black: Boolean - True to draw everything black
    Factor: Double - 1 on the printer; a smaller number draws the whole page smaller (a preview)
  Notes:
    Draws a printed page: the sheet's border, title block and rulers and then its objects, with
    the transform OnPrepareDC sets (the corner of the part of the sheet this page shows, and the
    print zoom). Nothing is drawn outside the page. The canvas is not cleared.
  =========================================================================== }
procedure RenderPrintPage(Design: TDesignFile; ActiveSheet: Integer; const L: TPrintLayout; const Dev: TPrintDevice; PageNo: Integer; ACanvas: TCanvas;
  PxW, PxH: Integer; Black: Boolean; Factor: Double; NoSymText: Boolean; NoSymFields: Boolean);
var
  Pg: TPrintPage;
  Idx: Integer;
  T: TTransform;
  Painter: TSchematicPainter;
  Sheet: TDesignSheet;
begin
  Pg := PrintPageAt(L, Dev, PageNo);
  if L.Sheets > 1 then
    Idx := Pg.Sheet
  else
    Idx := ActiveSheet;
  Sheet := Design.Sheets[Idx];
  T := TTransform.Create;
  try
    T.SetZoomFactor(L.Zoom * Factor);
    T.SetOriginX(Pg.OriginX);
    T.SetOriginY(Pg.OriginY);
    ACanvas.ClipRect := Rect(0, 0, PxW, PxH);
    ACanvas.Clipping := True;
    Painter := TSchematicPainter.Create(ACanvas, T);
    try
      Painter.Printing := True;
      Painter.AllBlack := Black;
      Painter.HideSymbolText := NoSymText;
      Painter.HideSymbolFields := NoSymFields;
      Painter.PaintPage(Sheet, False, Rect(0, 0, PxW, PxH), Design.FileName, SheetsText(Design, Idx),
        DocNoText(Design, Idx));
      Painter.PaintSheet(Sheet, nil);
    finally
      Painter.Free;
    end;
  finally
    ACanvas.Clipping := False;
    T.Free;
  end;
end;

{ ===========================================================================
  RunPrintJob  (function)
  Parameters:
    Design: TDesignFile - the design
    ActiveSheet: Integer - the sheet showing
    const Opt: TPrintOptions - what the Print dialog decided
    Sink: TPrintSink - where to print
    const Title: String - the name of the job
  Returns:
    Integer - the number of pages sent to the sink for one copy; 0 when the range asks for no
    page that exists
  Notes:
    The print: the pages of the range, once for each copy. When the printer makes the copies
    itself it is asked for them; otherwise a collated print sends the whole range again for each
    copy, and an uncollated one sends each page as many times as there are copies. A job that
    fails part way is aborted and the error passes on.
  =========================================================================== }
function RunPrintJob(Design: TDesignFile; ActiveSheet: Integer; const Opt: TPrintOptions; Sink: TPrintSink; const Title: String): Integer;
var
  L: TPrintLayout;
  Dev: TPrintDevice;
  First, Last, Copies, Pass, Passes, P, Per, K, I, N: Integer;
  Started, FirstPage: Boolean;
  List: array of Integer;
begin
  Result := 0;
  Dev := Sink.Device;
  L := PrintLayoutOf(Design, ActiveSheet, Sink, Opt);
  { the pages to print: the typed list (those that exist), else the first to the last }
  List := nil;
  N := 0;
  if Length(Opt.Pages) > 0 then
  begin
    for I := 0 to High(Opt.Pages) do
      if (Opt.Pages[I] >= 1) and (Opt.Pages[I] <= L.Pages) then
      begin
        SetLength(List, N + 1);
        List[N] := Opt.Pages[I];
        Inc(N);
      end;
  end
  else if PrintRangePages(L.Pages, Opt.FromPage, Opt.ToPage, First, Last) then
  begin
    SetLength(List, Last - First + 1);
    for I := 0 to High(List) do
      List[I] := First + I;
    N := Length(List);
  end;
  if N = 0 then
    Exit;
  Copies := Max(1, Opt.Copies);
  Passes := 1;
  Per := 1;
  if Sink.RendersCopies then
    Sink.SetCopies(Copies)
  else if Opt.Collate then
    Passes := Copies
  else
    Per := Copies;
  Started := False;
  FirstPage := True;
  try
    Sink.BeginDoc(Title);
    Started := True;
    for Pass := 1 to Passes do
      for I := 0 to N - 1 do
        for K := 1 to Per do
        begin
          P := List[I];
          if not FirstPage then
            Sink.NewPage;
          FirstPage := False;
          RenderPrintPage(Design, ActiveSheet, L, Dev, P, Sink.Canvas, Sink.PageWidth, Sink.PageHeight, Opt.BlackWhite, 1.0, Opt.NoSymbolText, Opt.NoSymbolFields);
        end;
    Sink.EndDoc;
    Started := False;
    Result := N;
  except
    if Started then
      Sink.Abort;
    raise;
  end;
end;

end.
