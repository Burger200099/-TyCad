{ Port of the document layer: Details.*, TransformSnap (Context.h), COption (Option.*),
  CTinyCadDoc's XML load/save (Io.cpp) and CTinyCadMultiDoc's file handling.

  A .dsn file is either a single <TinyCAD> sheet or a <TinyCADSheets> list of them. Each sheet
  has its own resource tables and symbol definitions. Loading and saving follow the C++
  sequence exactly, so numbering of fonts/styles/fills/symbols comes out the same.

  The old binary format (before TinyCAD wrote XML) is read by UDsnBinary: LoadFromStream tries
  its stamp first and LoadedLegacy / LoadNote tell the program what happened.

  Hierarchical designs are kept: a HierarchicalSymbol sheet is a sheet flagged IsHierarchicalSymbol and the
  HIERARCHICAL_SYMBOL object is TDrawHierarchicalSymbol; both are written back as read. The designs they refer to
  are not read yet.

  Original: Copyright 1994-2019 Matt Pyne, LGPL 2.1+. This port keeps that licence. }
unit UDesign;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs, Math, UDPoint, UDrawTypes, UResources, UDrawingObjects, USymbols,
  UXMLReader, UXMLWriter, UXMLException, UGeometry, UPaper, URevisions, UXMLPath, UTitleBlock;

const
  { the element of a hierarchical symbol sheet (CTinyCadHierarchicalDoc::GetXMLTag), its old misspelling, and the sheet's fixed name }
  HIERARCHICAL_SHEET_TAG = 'HierarchicalSymbol';
  HIERARCHICAL_SHEET_TAG_OLD = 'HierachicalSymbol';
  HIERARCHICAL_SHEET_NAME = 'Hierarchical Symbol';
  PAGE_WIDTH_DEFAULT = 297 * 5;
  PAGE_HEIGHT_DEFAULT = 210 * 5;

type
  { One entry of a sheet's revision history }

  { Title block and page settings (CDetails) }
  TDetails = class
  public
    PageWidth, PageHeight: Integer;
    Title, Author, Revision, DocNo, Org, Sheets, LastChange: String;
    IsVisible: Boolean;
    HasRulers: Boolean;
    HorizRulerSize, VertRulerSize: Integer;
    { ---- additions for the schematic version (all optional in the file) ---- }
    Revisions: TRevisionArray;  // oldest first; the last entry is the current revision
    AutoSheets: Boolean;        // the Sheets text is computed as "N of M" instead of typed
    ShowBorder: Boolean;        // draw a rectangle round the printable area
    BorderMargin: Double;       // its inset from the page edge, internal units
    { ---- the extended title block (all optional in the file; TinyCAD does not know them and skips them) ---- }
    ExtendedInfo: Boolean;      // draw the revision table beside the title block and the notes and reference cell above it
    SortByRevision: Boolean;    // the table's newest revisions are judged by revision label, not by date
    Notes, Reference: String;   // the two halves of the cell above the title block (lines separated by LF)
    constructor Create;
    procedure ReadXML(R: TXMLReader; Snap: TSnapSettings);
    procedure WriteXML(W: TXMLWriter);
    function AddRevision(const ARev, ADate, AAuthor, AApproved, ANotes: String): Integer;
    { the current revision's label, or the old single Revision field when there is no history }
    function EffectiveRevision: String;
    function EffectiveRevisionDate: String;
    { the newest revision of the history by the sheet's own ordering (date, or revision label), or the old single Revision with the sheet's date when there is no history }
    function NewestRevision: TRevision;
    function BorderRectangle: TDRect;
  end;

  { Per-sheet options (COption), including the symbol table }
  TDocOptions = class(TDocOptionsBase)
  public
    Symbols: TSymbolList;
    GridShow: Integer; // Bool8
    Units: Integer;
    Origin: TDPoint;
    constructor Create;
    destructor Destroy; override;
    procedure UnTagAll; override;
    procedure ResetMerge;
    { COption::AddSymbol: take ownership of Sym and return its number in the table }
    function AddSymbol(Sym: TDesignFileSymbol): Integer;
    function NewSymbolNumber(OldId: Integer): Integer; override;
    function SymbolInfo(Id: Integer): TSymbolInfo; override;
    procedure TagSymbol(Id: Integer); override;
    procedure TagSymbolContents(Id, Part: Integer; IncludePower: Boolean); override;
    function HasOrigin: Boolean;
    procedure ReadXML(R: TXMLReader);   // <OPTIONS>
    procedure WriteXML(W: TXMLWriter);
  end;

  { One schematic sheet (CTinyCadDoc) }
  TDesignSheet = class
  public
    SheetName: String;
    { the sheet that draws the design as a symbol to place in another design (CTinyCadHierarchicalDoc): saved as HierarchicalSymbol, always named
      'Hierarchical Symbol' }
    IsHierarchicalSymbol: Boolean;
    Details: TDetails;
    Options: TDocOptions;
    Drawing: TDrawingList;
    constructor Create;
    destructor Destroy; override;
    { the page as the rung grid needs it (the options ask for it)}
    function PageGeometryNow: TPageGeometry;
    { Reader is positioned on the sheet's <TinyCAD> tag (CTinyCadDoc::ReadFileXML with
      AlreadyStarted = TRUE). Returns True when the sheet contains objects. }
    function LoadXML(R: TXMLReader): Boolean;
    procedure SaveXML(W: TXMLWriter);
    { General forms (CTinyCadDoc::ReadFileXML / SaveXML with all their switches).
      LoadXMLInto merges resources into this sheet's tables and appends objects to List.
      EditLibrary mirrors IsEditLibrary(): the ORIGIN object becomes the sheet's origin. }
    function LoadXMLInto(R: TXMLReader; List: TDrawingList; WithDetails, EditLibrary: Boolean): Boolean;
    procedure SaveXMLEx(W: TXMLWriter; WithDetails, SaveResources, SaveOriginObject: Boolean;
      Only: TList = nil);
    { Recompute every object's text-dependent bounding box with the options' text metrics.
      Call after loading, and again whenever the metrics change. }
    procedure UpdateLayout;
    { the grid settings live in the options so symbols can see them }
    function Snap: TSnapSettings;
  end;

  { A symbol being edited / stored in a library (CTinyCadMultiSymbolDoc): one sheet, or one
    sheet per part for heterogeneous symbols. Its XML is what a library's Symbol.Data holds. }
  TSymbolDocument = class
  private
    FSheets: TObjectList;
    function GetSheet(Index: Integer): TDesignSheet;
  public
    Heterogeneous: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function SheetCount: Integer;
    function AddSheet: TDesignSheet;
    { Remove the last part's sheet (used when a symbol is given fewer parts) }
    procedure RemoveLastSheet;
    property Sheets[Index: Integer]: TDesignSheet read GetSheet;
    { Reader on the root tag (TinyCAD, or TinyCADSheets when Hetero) }
    procedure LoadXML(R: TXMLReader; Hetero: Boolean);
    procedure SaveXML(W: TXMLWriter);
    procedure LoadFromBlob(const Blob: String);
    function SaveToBlob: String;
  end;

{ CDesignFileSymbol::LoadSymbol: parse a library blob, merging its resources into Target's
  tables and its objects into Sym's drawing(s). False when the blob is not a symbol. }
function LoadLibrarySymbolBlob(Target: TDesignSheet; Sym: TDesignFileSymbol;
  const Blob: String): Boolean;

type
  { A whole design file (CTinyCadMultiDoc) }
  TDesignFile = class
  private
    FSheets: TObjectList;
    function GetSheet(Index: Integer): TDesignSheet;
  public
    VersionComment: String; // "<name> <version>" shown in the file's header comment
    FileName: String;       // the file last loaded or saved (used by title-block variables)
    LastAssignedId: Integer; // ids only go up within a session, so a deleted object's id is never reused
    AllowEmptySheets: Boolean; // accept a single sheet with no objects (the editor needs this for undo)
    Heterogeneous: Boolean; // ... with a sheet of its own for each part (every sheet then draws part 0 of its own)
    SymbolMode: Boolean;    // the file is a library symbol being edited: every sheet is made as a symbol's part (pins of other parts hidden, the origin kept), and undo reloads it so
    EditPart: Integer;      // ... the part being drawn on a drawing shared by the parts (a sheet of its own per part draws its own)
    LoadNote: String;       // set by LoadFromStream: what could not be read from an old binary file ('' when all was)
    LoadedLegacy: Boolean;  // the last load read TinyCAD's old binary format (saving writes XML, so the file is a conversion)
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    { ---- stable object ids (saved as oid) ---- }
    function MaxObjectId: Integer;
    function NextObjectId: Integer;
    { give every object that has no id one; returns how many were assigned }
    function AssignIds: Integer;
    { objects after the first that share an id (e.g. pasted copies) get fresh ones }
    function FixDuplicateIds: Integer;
    function FindObject(AId: Integer; out SheetIndex: Integer): TDrawingObject;
    function SheetCount: Integer;
    function AddSheet: TDesignSheet;
    { Remove a sheet (a design always keeps at least one); False if there is nothing to remove }
    { the sheet that draws the design as a symbol (CTinyCadHierarchicalDoc): put first, as TinyCAD does; nil when the design has one }
    function AddHierarchicalSheet: TDesignSheet;
    function HasHierarchicalSheet: Boolean;
    function RemoveSheet(Index: Integer): Boolean;
    { Move a sheet to another position in the order of the sheets }
    procedure MoveSheet(FromIndex, ToIndex: Integer);
    property Sheets[Index: Integer]: TDesignSheet read GetSheet;
    procedure LoadFromStream(S: TStream);
    procedure LoadFromFile(const AFileName: String);
    procedure SaveToStream(S: TStream);
    procedure SaveToFile(const AFileName: String);
  end;

{ The loader TDrawHierarchicalSymbol uses (see HierarchicalLoader in UDrawingObjects): the objects of the design file's
  hierarchical symbol sheet, whose resources are merged into AOpts. }
function LoadHierarchicalObjects(const AFileName: String; AOpts: TDocOptionsBase; List: TDrawingList; out Err: String): Boolean;

implementation

uses UStrings,
  UDsnBinary;

{ ---- TDetails ---- }

{ ===========================================================================
  TDetails.Create  (constructor)
  Parameters:  none
  Notes:
    Creates the page details with TinyCAD's defaults (A4 landscape page, title block fields
    empty, sheets "1 of 1") and no border, history or auto numbering.
  =========================================================================== }
constructor TDetails.Create;
begin
  inherited Create;
  IsVisible := True;
  LastChange := '';
  HasRulers := False;
  HorizRulerSize := 7;
  VertRulerSize := 5;
  PageWidth := PAGE_WIDTH_DEFAULT;
  PageHeight := PAGE_HEIGHT_DEFAULT;
  Title := '';
  Author := '';
  Revision := '1.0';
  DocNo := '';
  Org := '';
  Sheets := '1 of 1';
  AutoSheets := False;
  ShowBorder := False;
  BorderMargin := DEFAULT_BORDER_MARGIN;
end;

{ ===========================================================================
  NormalizeNewlines  (function)
  Parameters:
    const S: String - the text
  Returns:
    String - the text with LF line ends
  Notes:
    Turns CRLF and CR into LF, because XML readers do, so notes round-trip exactly.
  =========================================================================== }
function NormalizeNewlines(const S: String): String;
begin
  { XML parsers turn CR and CRLF into LF, so notes are kept with LF to round-trip exactly }
  Result := StringReplace(StringReplace(S, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
end;

{ ===========================================================================
  TDetails.AddRevision  (function)
  Parameters:
    const ARev: String - revision label, e.g. A
    const ADate: String - date text
    const AAuthor: String - who made it
    const AApproved: String - who approved it
    const ANotes: String - what changed (may span several lines)
  Returns:
    Integer - its position in the history
  Notes:
    Appends a revision (label, date, author, approver, notes) to the sheet's history.
  =========================================================================== }
function TDetails.AddRevision(const ARev, ADate, AAuthor, AApproved, ANotes: String): Integer;
begin
  Result := Length(Revisions);
  SetLength(Revisions, Result + 1);
  Revisions[Result].Rev := ARev;
  Revisions[Result].Date := ADate;
  Revisions[Result].Author := AAuthor;
  Revisions[Result].Approved := AApproved;
  Revisions[Result].Notes := NormalizeNewlines(ANotes);
end;

{ ===========================================================================
  TDetails.EffectiveRevision  (function)
  Parameters:  none
  Returns:
    String - the label
  Notes:
    The current revision: the last history entry's label, or the old single Revision field when
    there is no history.
  =========================================================================== }
function TDetails.EffectiveRevision: String;
begin
  Result := NewestRevision.Rev;
end;

{ ===========================================================================
  TDetails.EffectiveRevisionDate  (function)
  Parameters:  none
  Returns:
    String - the date text
  Notes:
    The date of the current revision (last history entry), or the last-change date when there is
    no history.
  =========================================================================== }
function TDetails.EffectiveRevisionDate: String;
begin
  Result := NewestRevision.Date;
end;

{ ===========================================================================
  TDetails.NewestRevision  (function)
  Parameters:  none
  Returns:
    TRevision
  Notes:
    What the Revision and Date boxes of the title block show, what is written to TinyCAD's own
    REVISION element, and what the revision variables of the text give.
  =========================================================================== }
function TDetails.NewestRevision: TRevision;
var
  R: TRevisionArray;
begin
  R := NewestRevisions(Revisions, Revision, LastChange, SortByRevision, 1);
  if Length(R) > 0 then
    Result := R[0]
  else
  begin
    Result.Rev := Revision; Result.Date := LastChange; Result.Author := ''; Result.Approved := ''; Result.Notes := '';
  end;
end;

{ ===========================================================================
  TDetails.BorderRectangle  (function)
  Parameters:  none
  Returns:
    TDRect - the rectangle in internal units
  Notes:
    The border rectangle for this sheet's page size and margin.
  =========================================================================== }
function TDetails.BorderRectangle: TDRect;
begin
  Result := BorderRect(PageWidth, PageHeight, BorderMargin);
end;

{ ===========================================================================
  TDetails.ReadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader on DETAILS
    Snap: TSnapSettings - receives the grid settings
  Notes:
    Reads the DETAILS element: page size, title block fields, shown flags, date, and the
    additions (automatic sheet numbers, border, revision history). The grid element is passed on
    to Snap.
  =========================================================================== }
procedure TDetails.ReadXML(R: TXMLReader; Snap: TSnapSettings);
var
  Name: String;
  Shows: Integer;
  Rv: TRevision;
  Cur: String;
begin
  R.IntoTag;
  while R.NextTag(Name) do
  begin
    if Name = 'Size' then
    begin
      R.GetAttribute('width', PageWidth);
      R.GetAttribute('height', PageHeight);
    end
    else if Name = 'TITLE' then
      R.GetChildData(Title)
    else if Name = 'AUTHOR' then
      R.GetChildData(Author)
    else if Name = 'REVISION' then
      R.GetChildData(Revision)
    else if Name = 'DOCNUMBER' then
      R.GetChildData(DocNo)
    else if Name = 'ORGANISATION' then
      R.GetChildData(Org)
    else if Name = 'SHEETS' then
      R.GetChildData(Sheets)
    else if Name = 'SHOWS' then
    begin
      Shows := 0;
      R.GetChildData(Shows);
      HasRulers := (Shows and 2) <> 0;
      IsVisible := (Shows and 1) <> 0;
    end
    else if Name = 'GUIDES' then
    begin
      R.GetAttribute('horiz', HorizRulerSize);
      R.GetAttribute('vert', VertRulerSize);
    end
    else if Name = 'DATE' then
      R.GetChildData(LastChange)
    else if Name = 'AUTOSHEETS' then
    begin
      Shows := 0;
      R.GetChildData(Shows);
      AutoSheets := Shows <> 0;
    end
    else if Name = 'EXTBLOCK' then
    begin
      Shows := 1;
      R.GetAttribute('show', Shows);
      ExtendedInfo := Shows <> 0;
      Cur := '';
      R.GetAttribute('sort', Cur);
      SortByRevision := LowerCase(Cur) = 'rev';
    end
    else if Name = 'NOTES' then
      R.GetChildData(Notes)
    else if Name = 'REFERENCE' then
      R.GetChildData(Reference)
    else if Name = 'BORDER' then
    begin
      ShowBorder := True;
      R.GetAttribute('margin', BorderMargin);
    end
    else if Name = 'REVISIONS' then
    begin
      SetLength(Revisions, 0);
      R.IntoTag;
      while R.NextTag(Name) do
        if Name = 'REV' then
        begin
          Rv.Rev := ''; Rv.Date := ''; Rv.Author := ''; Rv.Approved := ''; Rv.Notes := '';
          R.GetAttribute('label', Rv.Rev);
          R.GetAttribute('date', Rv.Date);
          R.GetAttribute('author', Rv.Author);
          R.GetAttribute('approved', Rv.Approved);
          R.GetChildData(Rv.Notes);
          AddRevision(Rv.Rev, Rv.Date, Rv.Author, Rv.Approved, Rv.Notes);
        end;
      R.OutOfTag;
    end
    else if Name = 'GRID' then
      Snap.LoadXML(R);
  end;
  R.OutOfTag;
end;

{ ===========================================================================
  TDetails.WriteXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
  Notes:
    Writes the DETAILS element. Automatic sheet numbers, border and revision history are only
    written when they are used, so ordinary files stay unchanged.
  =========================================================================== }
procedure TDetails.WriteXML(W: TXMLWriter);
var
  Shows, i: Integer;
begin
  Shows := 0;
  if IsVisible then
    Shows := Shows or 1;
  if HasRulers then
    Shows := Shows or 2;
  W.AddTag('Size');
  W.AddAttribute('width', PageWidth);
  W.AddAttribute('height', PageHeight);
  W.CloseTag;
  W.AddTag('GUIDES');
  W.AddAttribute('horiz', HorizRulerSize);
  W.AddAttribute('vert', VertRulerSize);
  W.CloseTag;
  W.AddTag('TITLE', Title);
  W.AddTag('AUTHOR', Author);
  W.AddTag('REVISION', EffectiveRevision);       // (TinyCAD reads this one: it is the newest revision when there is a history)
  W.AddTag('DOCNUMBER', DocNo);
  W.AddTag('ORGANISATION', Org);
  W.AddTag('SHEETS', Sheets);
  W.AddTag('SHOWS', Shows);
  W.AddTag('DATE', LastChange);
  { the schematic additions are only written when used, so ordinary files are unchanged }
  if AutoSheets then
    W.AddTag('AUTOSHEETS', 1);
  if ShowBorder then
  begin
    W.AddTag('BORDER');
    W.AddAttribute('margin', BorderMargin);
    W.CloseTag;
  end;
  if ExtendedInfo or SortByRevision then
  begin
    { the order is kept even when the extended block is not shown: it decides which revision is the newest }
    W.AddTag('EXTBLOCK');
    if SortByRevision then
      W.AddAttribute('sort', 'rev')
    else
      W.AddAttribute('sort', 'date');
    if ExtendedInfo then
      W.AddAttribute('show', 1)
    else
      W.AddAttribute('show', 0);
    W.CloseTag;
  end;
  if Notes <> '' then
    W.AddTag('NOTES', Notes);
  if Reference <> '' then
    W.AddTag('REFERENCE', Reference);
  if Length(Revisions) > 0 then
  begin
    W.AddTag('REVISIONS');
    for i := 0 to High(Revisions) do
    begin
      W.AddTag('REV');
      W.AddAttribute('label', Revisions[i].Rev);
      W.AddAttribute('date', Revisions[i].Date);
      W.AddAttribute('author', Revisions[i].Author);
      W.AddAttribute('approved', Revisions[i].Approved);
      W.AddChildData(Revisions[i].Notes);
      W.CloseTag;
    end;
    W.CloseTag;
  end;
end;

{ ---- TDocOptions ---- }

{ ===========================================================================
  TDocOptions.Create  (constructor)
  Parameters:  none
  Notes:
    Creates a sheet's options, including its symbol table.
  =========================================================================== }
constructor TDocOptions.Create;
begin
  inherited Create;
  Symbols := TSymbolList.CreateFor(Self);
  GridShow := 0;
  Units := EditDefaults.Units;                // (a design that is read from a file takes the file's)
  Origin := DPointInvalid;
end;

{ ===========================================================================
  TDocOptions.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the symbol table and the options.
  =========================================================================== }
destructor TDocOptions.Destroy;
begin
  Symbols.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TDocOptions.UnTagAll  (procedure)
  Parameters:  none
  Notes:
    Marks fonts, styles, fills and symbols as unused before a save.
  =========================================================================== }
procedure TDocOptions.UnTagAll;
begin
  inherited UnTagAll;
  Symbols.UnTag;
end;

{ ===========================================================================
  TDocOptions.ResetMerge  (procedure)
  Parameters:  none
  Notes:
    Forgets merge matching of fonts, styles, fills and symbols before loading another file.
  =========================================================================== }
procedure TDocOptions.ResetMerge;
begin
  Fonts.ResetMerge;
  Styles.ResetMerge;
  Fills.ResetMerge;
  Images.ResetMerge;
  Symbols.ResetMerge;
end;

{ ===========================================================================
  TDocOptions.AddSymbol  (function)
  Parameters:
    Sym: TDesignFileSymbol - the symbol
  Returns:
    Integer - the symbol number to use in placed symbols
  Notes:
    Adds a symbol to the sheet's symbol table (sharing an identical one already there).
  =========================================================================== }
function TDocOptions.AddSymbol(Sym: TDesignFileSymbol): Integer;
begin
  Result := Symbols.Add(TSymbolResource.CreateFor(Self, Sym), -1);
end;

{ ===========================================================================
  TDocOptions.SymbolInfo  (function)
  Parameters:
    Id: Integer - symbol number
  Returns:
    TSymbolInfo - the symbol information
  Notes:
    The symbol data for a symbol number.
  =========================================================================== }
function TDocOptions.SymbolInfo(Id: Integer): TSymbolInfo;
begin
  Result := Symbols.Symbol(Id);
end;

{ ===========================================================================
  TDocOptions.NewSymbolNumber  (function)
  Parameters:
    OldId: Integer - the number as written in the file
  Returns:
    Integer - the sheet's symbol number
  Notes:
    Converts a symbol number from a file to this sheet's number.
  =========================================================================== }
function TDocOptions.NewSymbolNumber(OldId: Integer): Integer;
begin
  Result := Symbols.ConvertOld(OldId);
end;

{ ===========================================================================
  TDocOptions.TagSymbol  (procedure)
  Parameters:
    Id: Integer - symbol number
  Notes:
    Marks a symbol as in use so it is saved.
  =========================================================================== }
procedure TDocOptions.TagSymbol(Id: Integer);
begin
  Symbols.Tag(Id);
end;

{ ===========================================================================
  TDocOptions.TagSymbolContents  (procedure)
  Parameters:
    Id: Integer - symbol number
    Part: Integer - part number
    IncludePower: Boolean - whether power pins are shown
  Notes:
    Marks the fonts, styles and fills used inside a symbol's drawing for a part, so they are
    saved with it.
  =========================================================================== }
procedure TDocOptions.TagSymbolContents(Id, Part: Integer; IncludePower: Boolean);
var
  L: TList;
  i: Integer;
begin
  L := TList.Create;
  try
    Symbols.Symbol(Id).GetMethodObjects(Part, IncludePower, L);
    for i := 0 to L.Count - 1 do
      TDrawingObject(L[i]).TagResources;
  finally
    L.Free;
  end;
end;

{ ===========================================================================
  TDocOptions.HasOrigin  (function)
  Parameters:  none
  Returns:
    Boolean - True if an origin is set
  Notes:
    Whether the sheet has a user-set origin.
  =========================================================================== }
function TDocOptions.HasOrigin: Boolean;
begin
  Result := DPointHasValue(Origin);
end;

{ ===========================================================================
  TDocOptions.WriteXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
  Notes:
    Writes the OPTIONS element: grid settings, origin and colors.
  =========================================================================== }
procedure TDocOptions.WriteXML(W: TXMLWriter);
begin
  W.AddTag('OPTIONS');
  W.AddTag('GRID', GridShow);
  W.AddTag('UNITS', Units);
  Colors.WriteXML(W);
  W.CloseTag;
end;

{ ===========================================================================
  TDocOptions.ReadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader on OPTIONS
  Notes:
    Reads the OPTIONS element, starting from default colors.
  =========================================================================== }
procedure TDocOptions.ReadXML(R: TXMLReader);
var
  Name: String;
begin
  R.IntoTag;
  Colors.Init; // defaults first (ignoring any user registry)
  while R.NextTag(Name) do
  begin
    if (Name = 'FONT') or (Name = 'STYLE') then
      { current font/style are not restored (commented out in the C++ code) }
    else if Name = 'GRID' then
      R.GetChildData(GridShow)
    else if Name = 'UNITS' then
      R.GetChildData(Units)
    else
      Colors.ReadXML(R, Name);
  end;
  R.OutOfTag;
end;

{ ---- TDesignSheet ---- }

{ ===========================================================================
  TDesignSheet.Create  (constructor)
  Parameters:  none
  Notes:
    Creates an empty sheet with its own options, details and drawing list.
  =========================================================================== }
constructor TDesignSheet.Create;
begin
  inherited Create;
  SheetName := '';
  IsHierarchicalSymbol := False;
  Details := TDetails.Create;
  Options := TDocOptions.Create;
  Drawing := TDrawingList.Create;
  Options.OnPageGeometry := @PageGeometryNow;
end;

{ ===========================================================================
  TDesignSheet.PageGeometryNow  (function)
  Parameters:  none
  Returns:
    TPageGeometry
  Notes:
    Answers the options' question about the page, so objects that cover the sheet (the rung
    grid) always see the current paper size and border without being told when they change.
  =========================================================================== }
function TDesignSheet.PageGeometryNow: TPageGeometry;
var
  L: TExtendedLayout;
begin
  Result.Width := Details.PageWidth;
  Result.Height := Details.PageHeight;
  if Details.ShowBorder then
    Result.BorderInset := Details.BorderMargin
  else
    Result.BorderInset := 0;
  Result.TitleBlockTop := -1;
  if Details.IsVisible then
  begin
    L := ExtendedLayout(Details.PageWidth, Details.PageHeight, Details.HasRulers);
    if Details.ExtendedInfo then
      Result.TitleBlockTop := L.NotesTop
    else
      Result.TitleBlockTop := L.BlockTop;
  end;
end;

{ ===========================================================================
  TDesignSheet.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the drawing and the options.
  =========================================================================== }
destructor TDesignSheet.Destroy;
begin
  Drawing.Free;
  Options.Free;
  Details.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TDesignSheet.LoadXML  (function)
  Parameters:
    R: TXMLReader - the XML reader on the element
  Returns:
    Boolean - True if the sheet has any objects
  Notes:
    Reads a whole sheet (details, options, resources, objects) from its TinyCAD element.
  =========================================================================== }
function TDesignSheet.LoadXML(R: TXMLReader): Boolean;
begin
  Result := LoadXMLInto(R, Drawing, True, False);
end;

{ ===========================================================================
  TDesignSheet.LoadXMLInto  (function)
  Parameters:
    R: TXMLReader - the XML reader
    List: TDrawingList - where objects go
    WithDetails: Boolean - read the DETAILS block
    EditLibrary: Boolean - True when reading a library symbol
  Returns:
    Boolean - True if any object was read
  Notes:
    Reads a sheet's content into a given list, optionally with the details block and in library-
    editing mode; unknown elements are skipped.
  =========================================================================== }
function TDesignSheet.LoadXMLInto(R: TXMLReader; List: TDrawingList;
  WithDetails, EditLibrary: Boolean): Boolean;
var
  Name: String;
  ResetDone: Boolean;
  Origin: TDPoint;
  Before: Integer;

  procedure ResetOnce;
  begin
    if not ResetDone then
    begin
      Options.ResetMerge;
      ResetDone := True;
    end;
  end;

begin
  ResetDone := False;
  Origin := DPointInvalid;
  Before := List.Count;
  R.IntoTag;
  while R.NextTag(Name) do
  begin
    if Name = 'DETAILS' then begin if WithDetails then
      Details.ReadXML(R, Snap); end
    else if Name = 'NAME' then begin if WithDetails then
      R.GetChildData(SheetName); end
    else if Name = 'GRID' then begin if WithDetails then
      Snap.LoadXML(R); end
    else if Name = 'FONT' then begin
      ResetOnce;
      Options.Fonts.LoadItemXML(R);
    end
    else if Name = 'STYLE' then begin
      ResetOnce;
      Options.Styles.LoadItemXML(R);
    end
    else if Name = 'FILL' then begin
      ResetOnce;
      Options.Fills.LoadItemXML(R);
    end
    else if (Name = 'META') or (Name = 'IMAGE') then begin
      ResetOnce;
      Options.Images.LoadItemXML(R);
    end
    else if Name = 'SYMBOLDEF' then begin
      ResetOnce;
      Options.Symbols.LoadItemXML(R);
    end
    else if Name = 'OPTIONS' then
      Options.ReadXML(R)
    else
      LoadObjectTag(R, Name, Options, List, Origin);
  end;
  R.OutOfTag;
  if EditLibrary then
    Options.Origin := Origin; // only while editing symbols
  Result := List.Count > Before;
end;

{ ===========================================================================
  TDesignSheet.Snap  (function)
  Parameters:  none
  Returns:
    TSnapSettings - the settings
  Notes:
    The sheet's grid and snap settings.
  =========================================================================== }
function TDesignSheet.Snap: TSnapSettings;
begin
  Result := Options.Snap;
end;

{ ===========================================================================
  TDesignSheet.UpdateLayout  (procedure)
  Parameters:  none
  Notes:
    Recalculates the layout of every object on the sheet (text boxes, pin text).
  =========================================================================== }
procedure TDesignSheet.UpdateLayout;
var
  i: Integer;
begin
  for i := 0 to Drawing.Count - 1 do
    Drawing[i].UpdateLayout;
end;

{ ===========================================================================
  TDesignSheet.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
  Notes:
    Writes the sheet as a TinyCAD element with details and resources.
  =========================================================================== }
procedure TDesignSheet.SaveXML(W: TXMLWriter);
begin
  SaveXMLEx(W, True, True, False);
end;

{ ===========================================================================
  TDesignSheet.SaveXMLEx  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
    WithDetails: Boolean - write the DETAILS block
    SaveResources: Boolean - write the fonts, styles and fills
    SaveOriginObject: Boolean - write the origin as an object (library symbols)
    Only: TList
  Notes:
    Writes the sheet with choices: details block, fonts/styles/fills, and the origin object.
    Only the resources the objects use are written.
  =========================================================================== }
procedure TDesignSheet.SaveXMLEx(W: TXMLWriter; WithDetails, SaveResources, SaveOriginObject: Boolean;
  Only: TList);
var
  i: Integer;
begin
  if IsHierarchicalSymbol then
    W.AddTag(HIERARCHICAL_SHEET_TAG)
  else
    W.AddTag('TinyCAD');

  if WithDetails then
  begin
    W.AddTag('NAME');
    if IsHierarchicalSymbol then
      W.AddChildData(HIERARCHICAL_SHEET_NAME)
    else
      W.AddChildData(SheetName);
    W.CloseTag;

    W.AddTag('DETAILS');
    Details.WriteXML(W);
    Snap.SaveXML(W);
    W.CloseTag;
  end;

  if SaveResources then
  begin
    { find out which resources are in use, then save them }
    for i := 0 to Drawing.Count - 1 do
      if (Only = nil) or (Only.IndexOf(Drawing[i]) >= 0) then
        Drawing[i].TagResources;
    Options.Fonts.SaveXML('FONT', W);
    Options.Styles.SaveXML('STYLE', W);
    Options.Fills.SaveXML('FILL', W);
    Options.Images.SaveXML('IMAGE', W);
  end;

  if WithDetails then
  begin
    Options.Symbols.SaveXML('SYMBOLDEF', W);
    Options.WriteXML(W);
  end;

  { the document origin is written as an ORIGIN tag unless origin objects are saved as such }
  if (not SaveOriginObject) and Options.HasOrigin then
  begin
    W.AddTag('ORIGIN');
    W.AddAttribute('pos', Options.Origin);
    W.CloseTag;
  end;

  SaveObjects(W, Drawing, WithDetails, SaveOriginObject, Only);
  W.CloseTag;
end;

{ ---- TSymbolDocument ---- }

{ ===========================================================================
  TSymbolDocument.Create  (constructor)
  Parameters:  none
  Notes:
    Creates an empty symbol document (one sheet per part).
  =========================================================================== }
constructor TSymbolDocument.Create;
begin
  inherited Create;
  FSheets := TObjectList.Create(True);
end;

{ ===========================================================================
  TSymbolDocument.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the part sheets.
  =========================================================================== }
destructor TSymbolDocument.Destroy;
begin
  FSheets.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TSymbolDocument.Clear  (procedure)
  Parameters:  none
  Notes:
    Removes every part sheet.
  =========================================================================== }
procedure TSymbolDocument.Clear;
begin
  FSheets.Clear;
end;

{ ===========================================================================
  TSymbolDocument.SheetCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    Number of part sheets.
  =========================================================================== }
function TSymbolDocument.SheetCount: Integer;
begin
  Result := FSheets.Count;
end;

{ ===========================================================================
  TSymbolDocument.GetSheet  (function)
  Parameters:
    Index: Integer - part number, 0-based
  Returns:
    TDesignSheet - the sheet
  Notes:
    One part's sheet.
  =========================================================================== }
function TSymbolDocument.GetSheet(Index: Integer): TDesignSheet;
begin
  Result := TDesignSheet(FSheets[Index]);
end;

{ ===========================================================================
  TSymbolDocument.RemoveLastSheet  (procedure)
  Parameters:  none
  Notes:
    Removes the last part's sheet and its objects (used when a heterogeneous symbol is given
    fewer parts).
  =========================================================================== }
procedure TSymbolDocument.RemoveLastSheet;
begin
  if FSheets.Count > 0 then
    FSheets.Delete(FSheets.Count - 1);
end;

{ ===========================================================================
  TSymbolDocument.AddSheet  (function)
  Parameters:  none
  Returns:
    TDesignSheet - the new sheet
  Notes:
    Adds a part sheet in library-editing mode (pins of other parts hidden).
  =========================================================================== }
function TSymbolDocument.AddSheet: TDesignSheet;
begin
  Result := TDesignSheet.Create;
  Result.Options.EditLibrary := True; // IsEditLibrary(): pins of other parts are not shown
  Result.Options.EditPart := 0;       // (a sheet of a heterogeneous symbol draws part 0 of its own; a shared one is shown part by part)
  FSheets.Add(Result);
end;

{ ===========================================================================
  TSymbolDocument.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader
    Hetero: Boolean - whether the parts have different drawings
  Notes:
    Reads a symbol (all its parts) from XML.
  =========================================================================== }
procedure TSymbolDocument.LoadXML(R: TXMLReader; Hetero: Boolean);
var
  Tag: String;
  Sh: TDesignSheet;
begin
  Heterogeneous := Hetero;
  Clear;
  if Hetero then
  begin
    R.IntoTag;
    while R.NextTag(Tag) do
      if Tag = 'TinyCAD' then
      begin
        Sh := AddSheet;
        Sh.LoadXMLInto(R, Sh.Drawing, True, True);
      end;
    R.OutOfTag;
  end
  else
  begin
    Sh := AddSheet;
    Sh.LoadXMLInto(R, Sh.Drawing, True, True);
  end;
end;

{ ===========================================================================
  TSymbolDocument.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
  Notes:
    Writes a symbol (all its parts) as XML, writing only the resources it uses.
  =========================================================================== }
procedure TSymbolDocument.SaveXML(W: TXMLWriter);
var
  i: Integer;
begin
  for i := 0 to FSheets.Count - 1 do
    Sheets[i].Options.UnTagAll;
  if Heterogeneous then
  begin
    W.AddTag('TinyCADSheets');
    for i := 0 to FSheets.Count - 1 do
      Sheets[i].SaveXMLEx(W, False, True, False);
    W.CloseTag;
  end
  else if FSheets.Count > 0 then
    Sheets[0].SaveXMLEx(W, False, True, False);
end;

{ ===========================================================================
  TSymbolDocument.LoadFromBlob  (procedure)
  Parameters:
    const Blob: String - the symbol text from the .TCLib
  Notes:
    Reads a symbol from the text stored in a library record.
  =========================================================================== }
procedure TSymbolDocument.LoadFromBlob(const Blob: String);
var
  MS: TMemoryStream;
  R: TXMLReader;
  Tag: String;
begin
  MS := TMemoryStream.Create;
  try
    if Length(Blob) > 0 then
      MS.WriteBuffer(Blob[1], Length(Blob));
    MS.Position := 0;
    R := TXMLReader.Create(MS);
    try
      R.NextTag(Tag);
      if Tag = 'TinyCADSheets' then
        LoadXML(R, True)
      else if Tag = 'TinyCAD' then
        LoadXML(R, False)
      else
        raise EXMLException.CreateXML(rsNotASymbolDocument, 0);
    finally
      R.Free;
    end;
  finally
    MS.Free;
  end;
end;

{ ===========================================================================
  TSymbolDocument.SaveToBlob  (function)
  Parameters:  none
  Returns:
    String - the symbol text
  Notes:
    Writes the symbol as the text stored in a library record.
  =========================================================================== }
function TSymbolDocument.SaveToBlob: String;
var
  MS: TMemoryStream;
  W: TXMLWriter;
begin
  MS := TMemoryStream.Create;
  try
    W := TXMLWriter.Create(MS);
    try
      SaveXML(W);
    finally
      W.Free;
    end;
    SetLength(Result, MS.Size);
    if MS.Size > 0 then
      Move(MS.Memory^, Result[1], MS.Size);
  finally
    MS.Free;
  end;
end;

{ ===========================================================================
  LoadLibrarySymbolBlob  (function)
  Parameters:
    Target: TDesignSheet - the sheet it is loaded into
    Sym: TDesignFileSymbol - the symbol to fill in
    const Blob: String - the symbol text from the library
  Returns:
    Boolean - True if the blob was read
  Notes:
    Loads a library symbol's drawing into a sheet's symbol data, merging its fonts, styles and
    fills.
  =========================================================================== }
function LoadLibrarySymbolBlob(Target: TDesignSheet; Sym: TDesignFileSymbol;
  const Blob: String): Boolean;
var
  MS: TMemoryStream;
  R: TXMLReader;
  Tag, Next: String;
begin
  Result := False;
  MS := TMemoryStream.Create;
  try
    if Length(Blob) > 0 then
      MS.WriteBuffer(Blob[1], Length(Blob));
    MS.Position := 0;
    try
      R := TXMLReader.Create(MS);
      try
        R.NextTag(Tag);
        if Tag = 'TinyCADSheets' then
        begin
          R.IntoTag;
          Sym.ClearMethods;
          while R.NextTag(Next) do
            if Next = 'TinyCAD' then
              Target.LoadXMLInto(R, Sym.AddMethod, True, False);
          R.OutOfTag;
          Sym.Heterogeneous := True;
          Result := True;
        end
        else if Tag = 'TinyCAD' then
        begin
          Sym.ClearMethods;
          Target.LoadXMLInto(R, Sym.AddMethod, True, False);
          Sym.Heterogeneous := False;
          Result := True;
        end;
      finally
        R.Free;
      end;
    except
      on Exception do Result := False; // the C++ code swallows any failure here
    end;
  finally
    MS.Free;
  end;
end;

{ ---- TDesignFile ---- }

{ ===========================================================================
  TDesignFile.Create  (constructor)
  Parameters:  none
  Notes:
    Creates an empty design (no sheets).
  =========================================================================== }
constructor TDesignFile.Create;
begin
  inherited Create;
  FSheets := TObjectList.Create(True);
  VersionComment := 'TinyCAD (Lazarus port)';
end;

{ ===========================================================================
  TDesignFile.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees all sheets.
  =========================================================================== }
destructor TDesignFile.Destroy;
begin
  FSheets.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TDesignFile.Clear  (procedure)
  Parameters:  none
  Notes:
    Removes every sheet.
  =========================================================================== }
procedure TDesignFile.Clear;
begin
  FSheets.Clear;
end;

{ ===========================================================================
  TDesignFile.SheetCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    Number of sheets.
  =========================================================================== }
function TDesignFile.SheetCount: Integer;
begin
  Result := FSheets.Count;
end;

{ ===========================================================================
  TDesignFile.AddSheet  (function)
  Parameters:  none
  Returns:
    TDesignSheet - the new sheet
  Notes:
    Adds an empty sheet at the end (a part of the symbol, in symbol mode).
  =========================================================================== }
function TDesignFile.AddSheet: TDesignSheet;
begin
  Result := TDesignSheet.Create;
  FSheets.Add(Result);
  if SymbolMode then
  begin
    Result.Options.EditLibrary := True;
    Result.Details.IsVisible := False;      // (a symbol's sheet has no title block)
    if Heterogeneous then
      Result.Options.EditPart := 0
    else
      Result.Options.EditPart := EditPart;
  end;
end;

{ ===========================================================================
  TDesignFile.HasHierarchicalSheet  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    TinyCAD keeps that sheet first and only allows one (the menu command is off once it is
    there).
  =========================================================================== }
function TDesignFile.HasHierarchicalSheet: Boolean;
begin
  Result := (SheetCount > 0) and Sheets[0].IsHierarchicalSymbol;
end;

{ ===========================================================================
  TDesignFile.AddHierarchicalSheet  (function)
  Parameters:  none
  Returns:
    TDesignSheet
  Notes:
    CTinyCadMultiDoc::OnContextAddhierarchicalsymbol: a new empty sheet that draws the design as
    a symbol - its outline and its pins - to be placed in another design. It goes in front of
    the other sheets and has the fixed name Hierarchical Symbol. The caller gives it the paper
    and title block of the sheet being shown.
  =========================================================================== }
function TDesignFile.AddHierarchicalSheet: TDesignSheet;
begin
  Result := nil;
  if HasHierarchicalSheet then
    Exit;
  Result := TDesignSheet.Create;
  Result.IsHierarchicalSymbol := True;
  Result.SheetName := HIERARCHICAL_SHEET_NAME;
  FSheets.Insert(0, Result);
  if SymbolMode then
  begin
    Result.Options.EditLibrary := True;
    Result.Details.IsVisible := False;
    if Heterogeneous then
      Result.Options.EditPart := 0
    else
      Result.Options.EditPart := EditPart;
  end;
end;

{ ===========================================================================
  TDesignFile.RemoveSheet  (function)
  Parameters:
    Index: Integer - zero-based sheet number
  Returns:
    Boolean - True if the sheet was removed
  Notes:
    Removes a sheet and everything on it. A design always keeps at least one sheet, so nothing
    is removed from a one-sheet design.
  =========================================================================== }
function TDesignFile.RemoveSheet(Index: Integer): Boolean;
begin
  Result := (SheetCount > 1) and (Index >= 0) and (Index < SheetCount);
  if Result then
    FSheets.Delete(Index);     // the list frees the sheet and what is on it
end;

{ ===========================================================================
  TDesignFile.MoveSheet  (procedure)
  Parameters:
    FromIndex: Integer - where the sheet is now
    ToIndex: Integer - where it should be
  Notes:
    Moves a sheet to another place in the order of the sheets. An index out of range is ignored.
  =========================================================================== }
procedure TDesignFile.MoveSheet(FromIndex, ToIndex: Integer);
begin
  if (FromIndex < 0) or (FromIndex >= SheetCount) or (ToIndex < 0) or (ToIndex >= SheetCount) then
    Exit;
  FSheets.Move(FromIndex, ToIndex);
end;

{ ===========================================================================
  TDesignFile.GetSheet  (function)
  Parameters:
    Index: Integer - zero-based sheet number
  Returns:
    TDesignSheet - the sheet
  Notes:
    A sheet by position.
  =========================================================================== }
function TDesignFile.GetSheet(Index: Integer): TDesignSheet;
begin
  Result := TDesignSheet(FSheets[Index]);
end;

{ ===========================================================================
  TDesignFile.LoadFromStream  (procedure)
  Parameters:
    S: TStream - the stream
  Notes:
    Loads a design from a stream: a single sheet file, or a multi-sheet file (TinyCADSheets). A
    single sheet with no objects is rejected unless AllowEmptySheets is set.
  =========================================================================== }
procedure TDesignFile.LoadFromStream(S: TStream);
var
  R: TXMLReader;
  Name: String;
  Sheet: TDesignSheet;

  { a sheet for the file: as a part of a symbol when the file is one }
  function NewSheet: TDesignSheet;
  begin
    Result := TDesignSheet.Create;
    FSheets.Add(Result);
    if SymbolMode then
    begin
      Result.Options.EditLibrary := True;
      Result.Details.IsVisible := False;      // (a symbol's sheet has no title block)
      if Heterogeneous then
        Result.Options.EditPart := 0
      else
        Result.Options.EditPart := EditPart;
    end;
  end;

begin
  Clear;
  LoadNote := '';
  LoadedLegacy := False;
  if IsLegacyDsn(S) then
  begin
    { the old binary format (Io.cpp tries the header stamp before it tries XML) }
    Sheet := NewSheet;
    LoadedLegacy := True;
    if (not LoadLegacyDsn(S, Sheet, Sheet.Drawing, True, LoadNote)) and (not AllowEmptySheets) then
    begin
      Clear;
      LoadedLegacy := False;
      raise EXMLException.CreateXML(rsTheDesignContainsNoObjects, 0);
    end;
    if SymbolMode then
      Sheet.Details.IsVisible := False;
    Exit;
  end;
  R := TXMLReader.Create(S);
  try
    R.NextTag(Name);
    if Name = 'TinyCAD' then
    begin
      { single sheet file }
      Sheet := NewSheet;
      if (not Sheet.LoadXMLInto(R, Sheet.Drawing, True, SymbolMode)) and (not AllowEmptySheets) then
      begin
        Clear; // the C++ loader rejects a single sheet that has no objects
        raise EXMLException.CreateXML(rsTheDesignContainsNoObjects, 0);
      end;
      if SymbolMode then
        Sheet.Details.IsVisible := False;      // (a symbol's sheet has no title block, whatever the file says)
      Exit;
    end;
    if Name <> 'TinyCADSheets' then
      raise EXMLException.CreateXML(rsUnrecognisedDesignFileExpectedTinyCAD, 0);
    R.IntoTag;
    while R.NextTag(Name) do
      if Name = 'TinyCAD' then
      begin
        Sheet := NewSheet;
        Sheet.LoadXMLInto(R, Sheet.Drawing, True, SymbolMode);
        if SymbolMode then
          Sheet.Details.IsVisible := False;
      end
      else if (Name = HIERARCHICAL_SHEET_TAG) or (Name = HIERARCHICAL_SHEET_TAG_OLD) then
      begin
        { the sheet that is the design drawn as a symbol (CTinyCadHierarchicalDoc): it keeps the fixed name whatever the file says }
        Sheet := NewSheet;
        Sheet.IsHierarchicalSymbol := True;
        Sheet.LoadXMLInto(R, Sheet.Drawing, True, SymbolMode);
        Sheet.SheetName := HIERARCHICAL_SHEET_NAME;
        if SymbolMode then
          Sheet.Details.IsVisible := False;
      end;
      { DETAILS is ignored }
    R.OutOfTag;
  finally
    R.Free;
  end;
end;

{ ===========================================================================
  TDesignFile.MaxObjectId  (function)
  Parameters:  none
  Returns:
    Integer - the id
  Notes:
    The highest object id on any sheet (0 when none have one).
  =========================================================================== }
function TDesignFile.MaxObjectId: Integer;
var
  i, j: Integer;
begin
  Result := 0;
  for i := 0 to FSheets.Count - 1 do
    for j := 0 to Sheets[i].Drawing.Count - 1 do
      if Sheets[i].Drawing[j].Id > Result then
        Result := Sheets[i].Drawing[j].Id;
end;

{ ===========================================================================
  TDesignFile.NextObjectId  (function)
  Parameters:  none
  Returns:
    Integer - the new id
  Notes:
    A new object id that is higher than any in use and higher than any given out this session,
    so deleted objects' ids are never reused.
  =========================================================================== }
function TDesignFile.NextObjectId: Integer;
begin
  Result := Max(MaxObjectId, LastAssignedId) + 1;
  LastAssignedId := Result;
end;

{ ===========================================================================
  TDesignFile.AssignIds  (function)
  Parameters:  none
  Returns:
    Integer - how many were assigned
  Notes:
    Gives an id to every object that has none.
  =========================================================================== }
function TDesignFile.AssignIds: Integer;
var
  i, j, Next: Integer;
begin
  Result := 0;
  Next := Max(MaxObjectId, LastAssignedId) + 1;
  for i := 0 to FSheets.Count - 1 do
    for j := 0 to Sheets[i].Drawing.Count - 1 do
      if (Sheets[i].Drawing[j].Id = 0) and (Sheets[i].Drawing[j].GetType <> xError) then
      begin
        Sheets[i].Drawing[j].Id := Next;
        Inc(Next);
        Inc(Result);
      end;
end;

{ ===========================================================================
  TDesignFile.FixDuplicateIds  (function)
  Parameters:  none
  Returns:
    Integer - how many were changed
  Notes:
    After the first, objects sharing an id (e.g. pasted copies) are given fresh ones.
  =========================================================================== }
function TDesignFile.FixDuplicateIds: Integer;
var
  Seen: TStringList;
  i, j, Next: Integer;
  Key: String;
begin
  Result := 0;
  Next := MaxObjectId + 1;
  Seen := TStringList.Create;
  try
    Seen.Sorted := True;
    Seen.Duplicates := dupIgnore;
    for i := 0 to FSheets.Count - 1 do
      for j := 0 to Sheets[i].Drawing.Count - 1 do
        if Sheets[i].Drawing[j].Id <> 0 then
        begin
          Key := IntToStr(Sheets[i].Drawing[j].Id);
          if Seen.IndexOf(Key) >= 0 then
          begin
            Sheets[i].Drawing[j].Id := Next;
            Inc(Next);
            Inc(Result);
          end
          else
            Seen.Add(Key);
        end;
  finally
    Seen.Free;
  end;
end;

{ ===========================================================================
  TDesignFile.FindObject  (function)
  Parameters:
    AId: Integer - the object id
    out SheetIndex: Integer - set to the sheet it is on (-1 if not found)
  Returns:
    TDrawingObject - the object, or nil
  Notes:
    Finds an object by its id on any sheet.
  =========================================================================== }
function TDesignFile.FindObject(AId: Integer; out SheetIndex: Integer): TDrawingObject;
var
  i, j: Integer;
begin
  Result := nil;
  SheetIndex := -1;
  if AId = 0 then
    Exit;
  for i := 0 to FSheets.Count - 1 do
    for j := 0 to Sheets[i].Drawing.Count - 1 do
      if Sheets[i].Drawing[j].Id = AId then
      begin
        Result := Sheets[i].Drawing[j];
        SheetIndex := i;
        Exit;
      end;
end;

{ ===========================================================================
  TDesignFile.LoadFromFile  (procedure)
  Parameters:
    const AFileName: String - path of the .dsn
  Notes:
    Loads a design from a file and remembers its name.
  =========================================================================== }
procedure TDesignFile.LoadFromFile(const AFileName: String);
var
  FS: TFileStream;
  OldPath: String;
begin
  FileName := AFileName;
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  OldPath := XMLPathName;
  XMLPathName := ExpandFileName(AFileName);      // (the file names inside are relative to this file)
  try
    LoadFromStream(FS);
  finally
    XMLPathName := OldPath;
    FS.Free;
  end;
end;

{ ===========================================================================
  TDesignFile.SaveToStream  (procedure)
  Parameters:
    S: TStream - the stream
  Notes:
    Writes the design as XML: a single sheet as TinyCAD, several as TinyCADSheets; resources are
    re-tagged first so only used ones are written.
  =========================================================================== }
procedure TDesignFile.SaveToStream(S: TStream);
var
  W: TXMLWriter;
  i: Integer;
begin
  { the multi-doc untags every sheet's resources before saving }
  for i := 0 to FSheets.Count - 1 do
    Sheets[i].Options.UnTagAll;
  W := TXMLWriter.Create(S);
  try
    W.AddComment('This file was written by ' + VersionComment + #10 +
      'If you wish to view this file go to https://www.tinycad.net to' + #10 +
      'download the executable.');
    W.AddTag('TinyCADSheets');
    for i := 0 to FSheets.Count - 1 do
      Sheets[i].SaveXML(W);
    W.CloseTag;
  finally
    W.Free;
  end;
end;

{ ===========================================================================
  TDesignFile.SaveToFile  (procedure)
  Parameters:
    const AFileName: String - path to write
  Notes:
    Writes the design to a file and remembers its name.
  =========================================================================== }
procedure TDesignFile.SaveToFile(const AFileName: String);
var
  FS: TFileStream;
  OldPath: String;
begin
  FileName := AFileName;
  FS := TFileStream.Create(AFileName, fmCreate);
  OldPath := XMLPathName;
  XMLPathName := ExpandFileName(AFileName);
  try
    SaveToStream(FS);
  finally
    XMLPathName := OldPath;
    FS.Free;
  end;
end;

{ ===========================================================================
  LoadHierarchicalObjects  (function)
  Parameters:
    const AFileName: String - path of the file
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
    List: TDrawingList
    out Err: String - text (out: set by the call)
  Returns:
    Boolean
  Notes:
    The loading part of CDrawHierarchicalSymbol::Load: the file must be a TinyCADSheets design;
    its first HierarchicalSymbol (or HierachicalSymbol) sheet gives the objects, without the
    details block. Fonts, styles, fills, pictures and symbols of the file are merged into AOpts,
    as the C++ reads the objects through the design the symbol is in. A later such sheet in the
    same file replaces an earlier one. Messages are those of the C++.
  =========================================================================== }
function LoadHierarchicalObjects(const AFileName: String; AOpts: TDocOptionsBase; List: TDrawingList; out Err: String): Boolean;
var
  FS: TFileStream;
  R: TXMLReader;
  Name: String;
  Tmp: TDesignSheet;
begin
  Result := False;
  Err := '';
  if not FileExists(AFileName) then
  begin
    Err := Format(rsFileNotFound, [AFileName]);
    Exit;
  end;
  try
    FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  except
    on E: Exception do
    begin
      Err := Format(rsFileNotFound, [AFileName]);
      Exit;
    end;
  end;
  try
    try
      R := TXMLReader.Create(FS);
      try
        if (not R.NextTag(Name)) or (Name <> 'TinyCADSheets') then
        begin
          Err := rsThisFileDoesNotHave;
          Exit;
        end;
        R.IntoTag;
        while R.NextTag(Name) do
          if (Name = HIERARCHICAL_SHEET_TAG) or (Name = HIERARCHICAL_SHEET_TAG_OLD) then
          begin
            List.Clear;
            Tmp := TDesignSheet.Create;
            try
              Tmp.Options.Free;
              Tmp.Options := AOpts as TDocOptions;      // (the sheet reads into the options of the design it is placed in)
              try
                Tmp.LoadXMLInto(R, List, False, False);
              finally
                Tmp.Options := nil;
              end;
            finally
              Tmp.Free;
            end;
            Result := True;
          end;
        R.OutOfTag;
      finally
        R.Free;
      end;
    except
      on E: Exception do
      begin
        List.Clear;
        Result := False;
        Err := Trim(StringReplace(StringReplace(E.Message, #13, '', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));      // (one line)
        Exit;
      end;
    end;
    if not Result then
      Err := rsThisFileDoesNotHave;
  finally
    FS.Free;
  end;
end;

initialization
  HierarchicalLoader := @LoadHierarchicalObjects;
end.
