// SPDX-License-Identifier: LGPL-2.1-or-later
{ Port of the DATA side of Object.h / DrawingObject.* and the DrawXxx.cpp / Polygon.cpp / Power.cpp
  files: the schematic object classes, their fields, XML load/save, resource tagging and the
  polygon path flattening that load depends on.

  GEOMETRY: Shift, RotateAbout, DistanceFromPoint, IsInside, IsCompletelyInside, UpdateLayout and
  Clone for every class. Placed symbols (TDrawMethod) get their bounding box, hit testing,
  rotation, field-label layout and pin connection points from the symbol's cached drawing
  (TSymbolInfo/TSymbolView, implemented by USymbols).
  Loading never computes layout, so file loading stays independent of text metrics: call
  UpdateLayout (TDesignSheet.UpdateLayout) after loading, or after changing the metrics.

  NOT in this unit: painting, mouse/edit handling (LButtonDown, Move, BeginEdit...), netlist
  construction, word-wrapped note-text layout. None of that affects what is written to a file.

  Original: Copyright 1994-2019 Matt Pyne, LGPL 2.1+. This port keeps that licence.

  Conventions:
  - C++ BOOL fields (an int) are Integer here so a value such as 2 survives a round trip;
    C++ bool fields are Boolean.
  - Objects take a TDocOptionsBase: it owns the font/style/fill tables and user colors the
    objects remap their resource numbers through while loading. }
unit UDrawingObjects;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs, Math, UDPoint, UDrawTypes, UResources, UImageInfo, UXMLReader, UXMLWriter,
  UXMLCodec, UGeometry, UOrient, UPartData;

const
  NORMAL_GRID = 100;   // Revision.h NormalGrid (pixels)
  FIELD_REF = 0;       // indexes of a placed symbol's standard fields
  FIELD_NAME = 1;
  FIELD_OTHER = 2;
  DefaultPhaseSpacing = 20;   // the distance between the wires of a new 3-phase bus, in design units (4 mm: two steps of the normal grid)

type
  { What the user has chosen in the Options dialog for how editing works; every new set of sheet options starts with these (which is also what
    makes a sheet made by Undo, by loading a file or by adding a sheet behave as the others do). }
  TEditDefaults = record
    AutoDrag, AutoJunction, AutoSnap: Boolean;
    AutoSnapRange: Integer;
    Units: Integer;        // what a new design shows lengths in: 0 millimetres, 1 inches (a design keeps its own, in its file)
    ShowGrid, SnapGrid: Boolean;    // a new design shows the grid / snaps to it
    GridMm: Double;        // the spacing of a new design's grid, in millimetres
    SymbolFontName: String;      // the symbol font of a new design (Options > Fonts); '' leaves TinyCAD's own
    SymbolFontPoints: Integer;
    SymbolFontBold, SymbolFontItalic: Boolean;
  end;

var
  EditDefaults: TEditDefaults = (AutoDrag: True; AutoJunction: True; AutoSnap: True; AutoSnapRange: 15; Units: 0;
    ShowGrid: True; SnapGrid: True; GridMm: 2.0; SymbolFontName: ''; SymbolFontPoints: 0; SymbolFontBold: False; SymbolFontItalic: False);

type
  TDrawingObject = class;
  TDocOptionsBase = class;
  TSymbolInfo = class;

  { The sheet's page as the objects that cover it (the rung grid) need it: size and the extra inset of the border, internal units }
  TPageGeometry = record
    Width, Height: Double;
    BorderInset: Double;   // the border margin when the border is shown, else 0
    TitleBlockTop: Double; // the y of the top of the title block (with its extended cell when shown); -1 when the sheet shows no title block
  end;
  TPageGeometryEvent = function: TPageGeometry of object;

  { Grid / snap settings (TransformSnap) }
  TSnapSettings = class
  public
    Grid: Double;      // spacing of the grid (the file stores Grid * 10)
    GridSnap: Integer; // BOOL
    constructor Create;
    procedure SaveXML(W: TXMLWriter);
    procedure LoadXML(R: TXMLReader);
    { Snap coordinates to the grid (TransformSnap::Snap) }
    function Snap(D: Double): Double; overload;
    function Snap(const P: TDPoint): TDPoint; overload;
  end;

  { Per-sheet options: resource tables and colors (the part of COption that objects use). }
  TDocOptionsBase = class
  public
    Fonts: TFontList;
    Styles: TLineStyleList;
    Fills: TFillStyleList;
    Images: TImageResourceList;       // the pictures of the design
    Colors: TUserColors;
    { Geometry context (the parts of the C++ document the objects ask for) }
    Snap: TSnapSettings;      // grid settings (owned)
    Metrics: TTextMetrics;    // measures text; owned. Default: DefaultTextMetrics (TApproxTextMetrics, or the real-font one in the program)
    ZoomFactor: Double;       // view zoom, used for the click tolerance of some hit tests
    AutoJunction: Boolean;    // create/remove junctions and split wires automatically (default on)
    AutoSnap: Boolean;        // snap wires to pins and wires (default on)
    AutoSnapRange: Integer;   // how close counts as "on" a pin (default 15 units)
    AutoDrag: Boolean;        // moving objects drags the wires that are attached to them along (Ctrl then moves them alone; with this off it is the other way round)
    EditLibrary: Boolean;     // IsEditLibrary(): this sheet is a library symbol being edited
    EditPart: Integer;        // the part being edited (pins of other parts are invisible)
    OnPageGeometry: TPageGeometryEvent; // set by the sheet that owns these options: its page size and border (nil: A4 landscape, no border)
    function PageGeometry: TPageGeometry;
    constructor Create;
    destructor Destroy; override;
    procedure UnTagAll; virtual;
    function TextExtent(const Str: String; FontNumber: Integer): TDSize;
    function LineThickness(StyleNumber: Integer): Integer;
    { Add copies of a style/fill to the table (shared if identical), like COption::AddStyle }
    function AddStyle(AStyle, AThickness: Integer; AColor: Cardinal): Integer;
    function AddFillStyle(AIndex: Integer; AColor: Cardinal): Integer;
    { the width of a font's characters (0 for the font's own width) }
    function GetFontWidth(FontNumber: Integer): Integer;
    { a copy of a font made taller or shorter by DeltaHeight (whole units) and, unless Width is 0, given that character width; returns its number }
    function ChangeFontSize(FontNumber: Integer; DeltaHeight, Width: Double): Integer;
    { the symbol font (TinyCAD's pin font, fPIN: the reference and the other fields of a symbol, and the names and numbers of pins) as Options > Fonts shows it }
    procedure GetSymbolFont(out AName: String; out APoints: Integer; out ABold, AItalic: Boolean);
    procedure SetSymbolFont(const AName: String; APoints: Integer; ABold, AItalic: Boolean);
    { keep a picture in the design (identical pictures are kept once): returns its number }
    function AddImage(const AType: String; const AData: TBytes): Integer;
    { Symbol table hooks, implemented by TDocOptions (USymbols/UDesign) }
    function NewSymbolNumber(OldId: Integer): Integer; virtual; abstract;
    procedure TagSymbol(Id: Integer); virtual; abstract;
    procedure TagSymbolContents(Id, Part: Integer; IncludePower: Boolean); virtual; abstract;
    { The symbol definition with this number (the head entry for unknown numbers) }
    function SymbolInfo(Id: Integer): TSymbolInfo; virtual; abstract;
  end;

  TDrawingList = class(TObjectList)
  private
    function GetItem(Index: Integer): TDrawingObject;
  public
    constructor Create;
    property Items[Index: Integer]: TDrawingObject read GetItem; default;
  end;

  { A symbol's drawing as seen by one placed part: copies of its objects in symbol-local
    coordinates (shifted so the reference point is the origin), plus the extents. This is one
    entry of CDesignFileSymbol's m_filter_cache. }
  TSymbolView = class
  public
    Objects: TDrawingList;
    RefPoint: TDPoint;   // the snapped corner the copies were shifted by
    TopRight: TDPoint;   // size of the symbol (negative: the reference point is its far corner)
    Origin: TDPoint;     // the symbol's origin marker in local coordinates (invalid if none)
    constructor Create;
    destructor Destroy; override;
  end;

  { What a placed symbol needs to know about its definition (implemented by TDesignFileSymbol) }
  TSymbolInfo = class
  public
    function GetView(Part: Integer; IncludePower: Boolean): TSymbolView; virtual; abstract;
    function GetTr(Part: Integer; IncludePower: Boolean): TDPoint; virtual; abstract;
    function GetOrigin(Part: Integer; IncludePower: Boolean): TDPoint; virtual; abstract;
    function PartsPerPackage: Integer; virtual; abstract;
    function SymbolName: String; virtual; abstract;
    function SymbolReference: String; virtual; abstract;
    function SymbolNameType: Integer; virtual; abstract;
    function SymbolRefType: Integer; virtual; abstract;
    function IsHeterogeneous: Boolean; virtual; abstract;
    function FieldCount: Integer; virtual; abstract;
    function FieldName(Index: Integer): String; virtual; abstract;
    function FieldDefault(Index: Integer): String; virtual; abstract;
    function FieldType(Index: Integer): Integer; virtual; abstract;
  end;

const
  { the resize handles of a rectangle, numbered as MFC's CRectTracker numbers them (TinyCAD passes these numbers around) }
  HANDLE_TOPLEFT = 0;
  HANDLE_TOPRIGHT = 1;
  HANDLE_BOTTOMRIGHT = 2;
  HANDLE_BOTTOMLEFT = 3;
  HANDLE_TOP = 4;
  HANDLE_RIGHT = 5;
  HANDLE_BOTTOM = 6;
  HANDLE_LEFT = 7;
  HANDLE_NONE = -1;
  { a field of a symbol is passed around as FIELD_BASE + its number, so it cannot be mistaken for a handle }
  FIELD_BASE = 1000;

type
  TDrawingObject = class
  protected
    FOpts: TDocOptionsBase;
    { Start this object's XML element: the tag, plus its stable id when it has one }
    procedure BeginTag(W: TXMLWriter; const TagName: String);
  public
    { Stable identity, saved as the oid attribute. 0 = none assigned yet (old files); links
      between objects refer to this. Unique within a design file. Clone does NOT copy it. }
    Id: Integer;
    PointA, PointB: TDPoint;
    constructor Create(AOpts: TDocOptionsBase); virtual;
    function GetType: TObjType; virtual; abstract;
    procedure LoadXML(R: TXMLReader); virtual; abstract;
    procedure SaveXML(W: TXMLWriter); virtual; abstract;
    procedure TagResources; virtual;
    function IsEmpty: Boolean; virtual;
    function IsConstruction: Boolean; virtual;
    { C++ operator==: equal when they serialise identically }
    function SameAs(Other: TDrawingObject): Boolean;
    property Options: TDocOptionsBase read FOpts;
    { ---- geometry ---- }
    procedure Shift(const R: TDPoint); virtual;
    { Rotate about P: Dir 2 = left, 3 = right, 4 = mirror }
    procedure RotateAbout(const P: TDPoint; Dir: Integer); virtual;
    { Distance of a point from the object (100 = "far away" for objects without a shape) }
    function DistanceFromPoint(const P: TDPoint): Double; virtual;
    { Does the object overlap the rectangle? A point-sized rectangle tests that point. }
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; virtual;
    function IsCompletelyInside(Left, Right, Top, Bottom: Double): Boolean; virtual;
    { Recompute bounding boxes that depend on text metrics (CalcLayout / DetermineSize) }
    procedure UpdateLayout; virtual;
    function Clone: TDrawingObject; virtual; abstract;
    { ---- resizing with handles (CDrawRectOutline) ---- }
    { Does this object have handles to drag its rectangle by? (rectangle, ellipse, picture, note) }
    function CanResize: Boolean; virtual;
    { The rectangle of a handle, as MFC's tracker places them: eight squares just outside the object's rectangle. HandleSize is the
      side of a square in design units. }
    function ResizeHandleRect(Handle: Integer; HandleSize: Double): TDRect; virtual;
    { Which handle (HANDLE_*) is the point on, or HANDLE_NONE; corners are tried before the middles of the sides }
    function ResizeHandleAt(const P: TDPoint; HandleSize: Double): Integer; virtual;
    { Drag a handle by R (CDrawRectOutline::MoveField): the side or corner moves, the rest stays; Handle 8 or 11 moves the whole rectangle }
    procedure ResizeBy(Handle: Integer; const R: TDPoint); virtual;
    { |height / width| of the rectangle, for keeping its shape while a corner is dragged with Ctrl held (CDrawingObject::AspectRatio) }
    function ResizeAspectRatio: Double; virtual;
    { called when the object becomes the one selected, so it can note what it needs for being resized (a text notes the width of its box and font) }
    procedure PrepareResize; virtual;
    { ---- dragging a field of the object (CDrawingObject::IsInsideField / MoveField) ---- }
    { Is the point on a field of the object that can be dragged by itself? Returns FIELD_BASE + the field's number, or -1 }
    function FieldAt(const P: TDPoint): Integer; virtual;
    { Move a field of the object by R (a number as FieldAt gave) }
    procedure MoveFieldBy(Field: Integer; const R: TDPoint); virtual;
  end;

  { WIRE, BUS and LINE (CDrawLine) }
  TDrawLine = class(TDrawingObject)
  public
    Kind: TObjType; // xWire, xBus, xLineEx2, xDash
    UseDefaultStyle: Boolean;
    Style: Integer;
    Network: Integer;   // net number assigned by the netlister (not saved)
    { 3-phase bus (a TyCAD extension; TinyCAD sees three ordinary buses): the three wires of a 3-phase bus share Group (the id of the first of them; 0 = a bus of its
      own), and Phase says which one it is: 0 the middle wire that was drawn, -1 and 1 the wires either side of it (left and right of the way it was drawn).
      Phases is what the bus should be (1 or 3) and PhaseSpacing the distance in design units between the wires; UPhases makes the wires fit them. }
    Group: Integer;
    Phase: Integer;
    Phases: Integer;
    PhaseSpacing: Double;
    constructor CreateKind(AOpts: TDocOptionsBase; AKind: TObjType);
    class function XMLTagFor(T: TObjType): String;
    function GetType: TObjType; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function Clone: TDrawingObject; override;
  end;

  TArcPoint = record
    X, Y: Double;
    Arc: Integer;        // Arc_none / Arc_in / Arc_out / Arc_control
    Control: TDPoint;    // only meaningful when Arc = Arc_control
    FlattenedSegment: Integer;
  end;

  { what the polygon context menu can do (ID_CONTEXT_* in TinyCAD) }
  TPolyAction = (paFreeLine, paArcIn, paArcOut, paCurve, paAddHandle, paDeleteHandle);

  { POLYGON (CDrawPolygon) }
  TDrawPolygon = class(TDrawingObject)
  public
    Kind: TObjType;
    Style, Fill: Integer;
    Close: Integer;                 // BOOL
    Handles: array of TArcPoint;    // relative to PointA
    Points: array of TDPoint;       // flattened path, relative to PointA (derived)
    constructor Create(AOpts: TDocOptionsBase); override;
    function GetType: TObjType; override;
    function IsEmpty: Boolean; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    procedure FlattenPath;
    procedure CalcBoundingRect;
    function IsInsidePolygon(const P: TDPoint): Boolean;
    function IsInsideLine(Left, Right, Top, Bottom: Double): Boolean;
    procedure FindNearestSegment(const P: TDPoint; out Line, Handle: Integer);
    { ---- editing the handles (CDrawPolygon::IsInsideField, MoveField, ContextMenu) ---- }
    { which handle or curve control point is at P: 1000 + the handle's number, 5000 + the number of the handle
      whose control point it is, or -1 for none; Tol is how close, in design units }
    function HandleAt(const P: TDPoint; Tol: Double): Integer;
    { move the handle or control point that HandleAt returned by R }
    procedure MoveHandle(Code: Integer; const R: TDPoint);
    { do a context menu action at the click P (SnapP is P snapped to the grid); True if the polygon changed }
    function ApplyAction(Action: TPolyAction; const P, SnapP: TDPoint): Boolean;
    procedure RotateAbout(const P: TDPoint; Dir: Integer); override;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    function Clone: TDrawingObject; override;
  end;

  TDrawJunction = class(TDrawingObject)
  public
    function GetType: TObjType; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function Clone: TDrawingObject; override;
  end;

  TDrawNoConnect = class(TDrawingObject)
  public
    constructor Create(AOpts: TDocOptionsBase); override;
    function GetType: TObjType; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function Clone: TDrawingObject; override;
  end;

  { A design rules check marker (CDrawError): a circle drawn on a sheet where the check found a
    problem. ErrorNumber is the line of the check's result list it belongs to. Never saved. }
  TDrawError = class(TDrawingObject)
  public
    ErrorNumber: Integer;
    constructor Create(AOpts: TDocOptionsBase); override;
    function GetType: TObjType; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    function Clone: TDrawingObject; override;
  end;

  TDrawOrigin = class(TDrawingObject)
  public
    function GetType: TObjType; override;
    function IsConstruction: Boolean; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function Clone: TDrawingObject; override;
  end;

  TDrawBusSlash = class(TDrawingObject)
  public
    Dir: Integer; // BYTE
    constructor Create(AOpts: TDocOptionsBase); override;
    function GetType: TObjType; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    procedure RotateAbout(const P: TDPoint; NewDir: Integer); override;
    function Clone: TDrawingObject; override;
  end;

  { RECTANGLE and ELLIPSE (CDrawSquare) }
  TDrawSquare = class(TDrawingObject)
  public
    Kind: TObjType; // xSquareEx3 = rectangle, xCircleEx3 = ellipse
    Style, Fill: Integer;
    constructor CreateKind(AOpts: TDocOptionsBase; AKind: TObjType);
    function IsSquare: Boolean;
    function CanResize: Boolean; override;
    function GetType: TObjType; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    function EllipseDistanceFromPoint(const P: TDPoint; out Inside: Boolean): Double;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    function Clone: TDrawingObject; override;
  end;

  { TEXT and BUSNAME (CDrawText) }
  { METAFILE (CDrawMetaFile): a picture. Two corners and the number of the picture in the design's table of pictures. Like TinyCAD's
    it has no shape of its own for hit tests: it is picked anywhere inside its rectangle. }
  TDrawMetaFile = class(TDrawingObject)
  public
    Image: Integer;
    Orient: TOrient;          // which way up the picture is: turned and flipped with its corners (see UOrient); upright to begin with
    function CanResize: Boolean; override;
    constructor Create(AOpts: TDocOptionsBase); override;
    function GetType: TObjType; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    { turning or flipping the picture moves its corners as for any object, and turns or flips what is shown in them too }
    procedure RotateAbout(const P: TDPoint; Dir: Integer); override;
    { the size the picture is first given, from its size in pixels }
    procedure FitToPicture(PixelWidth, PixelHeight: Integer);
    function Clone: TDrawingObject; override;
  end;

  TDrawText = class(TDrawingObject)
  public
    Kind: TObjType; // xTextEx2 or xBusNameEx
    FontStyle: Integer;
    FontColor: Cardinal;
    Str: String;
    Dir: Integer; // BYTE
    { what resizing by the handles works from: the length of the box and the width of the font as they were when the text was selected,
      and the length the box is being dragged to }
    OriginalWidth, OriginalBoxWidth, TargetBoxWidth: Double;
    procedure SetScalingWidths;
    function CanResize: Boolean; override;
    procedure ResizeBy(Handle: Integer; const R: TDPoint); override;
    procedure PrepareResize; override;
    constructor CreateKind(AOpts: TDocOptionsBase; AKind: TObjType);
    function GetType: TObjType; override;
    function IsEmpty: Boolean; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    procedure UpdateLayout; override;
    procedure RotateAbout(const P: TDPoint; NewDir: Integer); override;
    function Clone: TDrawingObject; override;
  end;

  { LABEL (CDrawLabel). PointA/PointB (the text box) need font metrics and are not computed;
    ActivePoint is the connection point and is what gets saved. }
  TDrawLabel = class(TDrawingObject)
  public
    FontStyle: Integer;
    FontColor: Cardinal;
    LabelStyle: Integer;
    ActivePoint: TDPoint;
    Str: String;
    Dir: Integer; // BYTE
    OriginalWidth, OriginalBoxWidth, TargetBoxWidth: Double;     // as for a text
    procedure SetScalingWidths;
    function CanResize: Boolean; override;
    procedure ResizeBy(Handle: Integer; const R: TDPoint); override;
    procedure PrepareResize; override;
    constructor Create(AOpts: TDocOptionsBase); override;
    function GetType: TObjType; override;
    function IsEmpty: Boolean; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    procedure Shift(const R: TDPoint); override;
    procedure UpdateLayout; override;
    procedure RotateAbout(const P: TDPoint; NewDir: Integer); override;
    function Clone: TDrawingObject; override;
    function GetLabelPoint: TDPoint;
    function GetValue: String;
  end;

  TDrawPower = class(TDrawingObject)
  public
    Which: Integer; // BYTE
    Dir: Integer;   // BYTE
    Str: String;
    TextPos, TextEnd: TDPoint; // the label's box, set by UpdateLayout
    function GetValue: String;
    constructor Create(AOpts: TDocOptionsBase); override;
    function GetType: TObjType; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    procedure UpdateLayout; override;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    procedure RotateAbout(const P: TDPoint; NewDir: Integer); override;
    function Clone: TDrawingObject; override;
  end;

  { Where the parts of a pin are drawn (CDrawPin::DetermineLayout) }
  TPinLayout = record
    Pa, Pb, Pc, Pd: TDPoint;  // line end, dot corners, outer end
    Pta, Ptb: TDPoint;        // name and number text positions
    Dr: Integer;              // text direction
  end;

  TDrawPin = class(TDrawingObject)
  public
    Str: String;      // pin name
    Number: String;
    Show, Which, Elec, Part, Dir: Integer; // BYTEs
    Length: Integer;  // WORD
    NumberPos: Integer;
    CentreName: Integer; // BOOL
    ConvertedPower: Integer; // BYTE: a power pin converted to a normal one (not saved)
    constructor Create(AOpts: TDocOptionsBase); override;
    function GetType: TObjType; override;
    function IsPower: Boolean;
    function IsInvisible: Boolean;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    function DetermineLayout(RotMir: Integer): TPinLayout;
    function GetActivePoint(Parent: TObject): TDPoint;   // Parent is the TDrawMethod holding the pin
    function GetPinName: String;
    function GetNumber: String;
    procedure DetermineSize;
    procedure ConvertPowerToNormal;
    procedure UpdateLayout; override;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    procedure RotateAbout(const P: TDPoint; NewDir: Integer); override;
    function Clone: TDrawingObject; override;
  end;

  TDrawNoteText = class(TDrawingObject)
  public
    Style, Fill, FontStyle: Integer;
    FontColor: Cardinal;
    Str: String;
    Dir: Integer; // BYTE
    BorderStyle: Integer;
    constructor Create(AOpts: TDocOptionsBase); override;
    function CanResize: Boolean; override;
    function GetType: TObjType; override;
    function IsEmpty: Boolean; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    function Clone: TDrawingObject; override;
  end;

  { LADDER (schematic version, not in TinyCAD): the two vertical rails of a ladder diagram with
    the bus labels (L1, L2) above them. PointA/PointB are opposite corners of the rails' rectangle.
    Only the rails and the text can be clicked; the empty space between the rails cannot. The line
    numbers are not part of the ladder: they belong to the rung grid (TDrawRungGrid), which covers
    the whole sheet. When it is the one selected object a ladder has the eight resize handles. }
  TDrawLadder = class(TDrawingObject)
  public
    LeftWire, RightWire: String;    // wire number of the left / right bus, drawn above each rail
    LineWidth: Integer;             // line density of the rails, 1, 2, 3 ... as for every other line
    LineColor: Cardinal;            // colour of the rails
    FontStyle: Integer;             // font number for the bus labels
    FontColor: Cardinal;
    constructor Create(AOpts: TDocOptionsBase); override;
    function GetType: TObjType; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    function Clone: TDrawingObject; override;
    function CanResize: Boolean; override;
    { ---- the rails ---- }
    function RailLeft: Double;
    function RailRight: Double;
    function RailTop: Double;
    function RailBottom: Double;
    { ---- text boxes (need the text metrics) ---- }
    function LeftLabelBox: TDRect;
    function RightLabelBox: TDRect;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    procedure RotateAbout(const P: TDPoint; NewDir: Integer); override;
  end;

  { RUNG GRID (schematic version, not in TinyCAD): the sheet's hidden spreadsheet. It covers the whole
    sheet from 0,0 to width,height, less an indent on all four sides (MarginMm, plus the border
    margin when the sheet has a border). A "page" of it is two columns: the first holds the rung
    numbers, one per row (Rows of them, all the same height), the second is blank and takes up the rest
    of the page. With one page per sheet the second column ends at the right indent; with two pages the
    first page ends at the middle of the sheet and the second page (its own number column and blank
    column) runs from the middle to the right indent. Every method that needs the sheet's size asks
    the options (PageGeometry). A sheet has one rung grid; it cannot be moved, only clicked on its
    numbers to select it; its one handle (the middle of the bottom edge) sets where the table ends. The line a symbol sits on (ULinks) is the row of this grid. }
  TDrawRungGrid = class(TDrawingObject)
  public
    Rows: Integer;              // rungs per page
    StartNumber: Integer;       // the number of the first rung
    MarginMm: Double;           // indent from the sheet edge on all four sides, mm
    Pages: Integer;             // 1 or 2 pages on the sheet
    ContinueNumbers: Boolean;   // the second page goes on counting where the first stopped (else it starts again at StartNumber)
    ShowRowHeight: Boolean;     // print the row height in mm above the number column
    AboveBlock: Boolean;        // (older files) the bottom of the table is the top of the title block (the bottom indent is ignored), not the bottom of the sheet; dragging the bottom handle takes it over
    HasBottom: Boolean;         // the bottom edge was set by dragging its handle: BottomMm from the bottom of the sheet (instead of the margin, or the title block)
    BottomMm: Double;           // the distance of the bottom edge from the bottom of the sheet, mm; meaningful when HasBottom
    FontStyle: Integer;
    FontColor: Cardinal;
    constructor Create(AOpts: TDocOptionsBase); override;
    function GetType: TObjType; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    function Clone: TDrawingObject; override;
    procedure Shift(const R: TDPoint); override;
    procedure RotateAbout(const P: TDPoint; NewDir: Integer); override;
    { ---- the spreadsheet ---- }
    function AreaRect: TDRect;                         // the sheet less the indent
    function RowHeight: Double;                        // design units
    function RowHeightMm: Double;
    function NumberColumnWidth: Double;                // as wide as the widest number needs
    function ColumnRect(Page, Col: Integer): TDRect;   // Col 0 = rung numbers, 1 = blank
    function CellRect(Page, Row: Integer): TDRect;     // a rung number's cell
    function NumberAt(Page, Row: Integer): Integer;
    function PageAtX(X: Double): Integer;
    function RowAtY(Y: Double): Integer;               // 0-based, -1 outside the grid
    { The rung number at a point (False in the indent, outside the area) }
    function LineNumberAt(const P: TDPoint; out Number: Integer): Boolean;
    function HeightTextBox(Page: Integer): TDRect;     // where the row height is printed
    function HeightText: String;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    function IsCompletelyInside(Left, Right, Top, Bottom: Double): Boolean; override;
    { ---- the one handle: the middle of the bottom edge, dragged up or down to set the height of the table ---- }
    function CanResize: Boolean; override;
    function ResizeAspectRatio: Double; override;
    function ResizeHandleRect(Handle: Integer; HandleSize: Double): TDRect; override;
    function ResizeHandleAt(const P: TDPoint; HandleSize: Double): Integer; override;
    procedure ResizeBy(Handle: Integer; const R: TDPoint); override;
  end;

  { RULER: a horizontal or vertical guide line across the sheet (TinyCAD's ruler tool) }
  TDrawRuler = class(TDrawingObject)
  public
    Horizontal: Integer; // BOOL
    function GetType: TObjType; override;
    function IsConstruction: Boolean; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    function Clone: TDrawingObject; override;
  end;

  { MEASURE: a ruler from point A to point B that shows the distance between them }
  TDrawMeasure = class(TDrawingObject)
  public
    UnitMode: Integer;    // 0 = millimetres, 1 = inches
    Ticks: Integer;       // BOOL: draw graduations along the line
    LineWidth: Double;
    LineColor: Cardinal;
    FontStyle: Integer;
    FontColor: Cardinal;
    constructor Create(AOpts: TDocOptionsBase); override;
    function GetType: TObjType; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    function Clone: TDrawingObject; override;
    function LengthInUnits: Double;
    function DisplayText: String;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
  end;

  { CLOUD: a rectangle drawn with scalloped (cloud) edges, for marking up revisions }
  TDrawCloud = class(TDrawingObject)
  public
    Style: Integer;       // line style number
    Bump: Double;         // size of one scallop, internal units
    constructor Create(AOpts: TDocOptionsBase); override;
    function GetType: TObjType; override;
    function CanResize: Boolean; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    function Clone: TDrawingObject; override;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
  end;

  { XREF: text that shows information about another object, kept up to date by ULinks.
    Mode 0: the ladder line number the target sits on. Mode 1: the line numbers of the other
    symbols that share the target's reference (the contacts of a coil, or the coil of a contact). }
  TDrawRefText = class(TDrawingObject)
  public
    TargetId: Integer;
    Mode: Integer;
    Prefix, Suffix: String;
    FontStyle: Integer;
    FontColor: Cardinal;
    CachedText: String;   // the resolved text (not saved; recomputed by ULinks.UpdateLinks)
    constructor Create(AOpts: TDocOptionsBase); override;
    function GetType: TObjType; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    function Clone: TDrawingObject; override;
    function DisplayText: String;
    procedure UpdateLayout; override;
  end;

  TMethodField = record
    FieldType: Integer;
    Description, Value: String;
    Show: Integer; // BOOL
    Position: TDPoint;
  end;

  TNetlistHint = record
    Pin: String;
    Net: Integer;
  end;

  TDPointArray = array of TDPoint;

  { SYMBOL: a placed instance of a symbol definition (CDrawMethod) }
  TDrawMethod = class(TDrawingObject)
  public
    SymbolId: Integer;   // number in the sheet's symbol table
    Part, Rotate: Integer; // BYTEs
    CanScale, ShowPower: Integer; // BOOLs
    ScalingX, ScalingY: Double;
    Fields: array of TMethodField; // index 0 = Ref, 1 = Name, 2 = Other
    Hints: array of TNetlistHint;
    Product: TProductChoice;      // the product chosen for this placed part (manufacturer, model number, its ratings); empty when none (saved as <PRODUCT>)
    constructor Create(AOpts: TDocOptionsBase); override;
    { Place a symbol from the library (CDrawMethod(pDesign, symbol, rotation)) }
    constructor CreateFromSymbol(AOpts: TDocOptionsBase; ASymbolId, NewRot: Integer);
    function GetType: TObjType; override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    function Clone: TDrawingObject; override;
    { ---- geometry ---- }
    function GetSymbolData: TSymbolInfo;
    { size of the symbol with this part / power choice, scaled by the placement's scaling }
    function GetTr: TDPoint; virtual;
    { Fetch the symbol's drawing; sets PointB from its size (CDrawMethod::ExtractSymbol).
      Objects is borrowed from the symbol's cache. }
    function ExtractSymbol(out Tr: TDPoint; out Objects: TDrawingList): Boolean; virtual;
    procedure UpdateLayout; override;
    { symbol-local point -> design coordinates }
    function TranslatePointToDesign(P: TDPoint): TDPoint;
    procedure ScalePoint(var P: TDPoint);
    { connection points of the visible pins, in design coordinates }
    function ActivePoints: TDPointArray;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    procedure RotateAbout(const P: TDPoint; NewDir: Integer); override;
    { re-compute PointB and the field label positions after a rotation }
    procedure NewRotation;
    { a stationary reference point (origin, else upper-left visible pin, else centre), snapped }
    function GetFirstStaticPoint: TDPoint;
    procedure ReplaceSymbol(OldSymbol, NewSymbol: Integer; KeepOldFields: Boolean);
    { ---- netlist access ---- }
    function GetRef: String;
    { ---- symbol references (annotate) ---- }
    { True when the reference has no '?' left in it }
    function HasRef: Boolean;
    { the number in the reference: the digits from the first one (0 when there are none) }
    function GetRefVal: Integer;
    { the symbol's reference prefix with its last '?' replaced by the number }
    procedure SetRefVal(Value: Integer);
    procedure SetRef(const NewRef: String);
    { changes the part and moves the symbol so that its first static pin stays where it was }
    procedure SetPart(NewPart: Integer);
    { gives the symbol the next free number of its reference. Scan lists the drawings searched (the
      sheets), Own the one holding this symbol }
    procedure AddReference(MinRef: Integer; const Scan: array of TDrawingList; Own: TDrawingList);
    procedure RemoveReference;
    function GetName: String;
    function GetFieldCount: Integer;
    function GetFieldName(Which: Integer): String;
    { The net number remembered for a pin (0 if none); reading adds the pin, as in C++ }
    function GetNetlistHint(const Pin: String): Integer;
    procedure SetNetlistHint(const Pin: String; Net: Integer);
    { field text }
    function FieldAt(const P: TDPoint): Integer; override;
    procedure MoveFieldBy(Field: Integer; const R: TDPoint); override;
    { a symbol marked resizable (can_scale) has handles to scale it by }
    function CanResize: Boolean; override;
    procedure ResizeBy(Handle: Integer; const R: TDPoint); override;
    function GetField(Which: Integer): String;
    function GetDecoratedField(Which: Integer): String;
    class function IsFieldVisible(FieldType: Integer; const FieldValue: String): Boolean;
    { the XML element name this kind of object is saved under }
    function XmlTag: String; virtual;
  end;

  { SYMTEXT: "symbol text", not in TinyCAD. A placed text that has the fields of a symbol (reference, name, other and any
    more) but draws no symbol: it exists to hold symbol data for the reports. Its shown fields are painted as text. It is not
    a symbol to the netlist, the checks, the annotation or the parts list (its type code is xSymbolText, not xMethodEx3), but
    the symbol data report lists it. }
  TDrawSymbolText = class(TDrawMethod)
  private
    FNothing: TDrawingList;       // the empty drawing handed out as the symbol's drawing
  public
    constructor Create(AOpts: TDocOptionsBase); override;
    destructor Destroy; override;
    function GetType: TObjType; override;
    function XmlTag: String; override;
    function GetTr: TDPoint; override;
    function ExtractSymbol(out Tr: TDPoint; out Objects: TDrawingList): Boolean; override;
    procedure RotateAbout(const P: TDPoint; NewDir: Integer); override;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    function CanResize: Boolean; override;
    function Clone: TDrawingObject; override;
  end;

  { HIERARCHICAL_SYMBOL: a placed symbol that is another design file (CDrawHierarchicalSymbol, a CDrawMethod).
    Its drawing is the hierarchical symbol sheet of that design (what its pins and outline are), read the first time it is
    needed with HierarchicalLoader (set by UDesign) and kept until the symbol is reloaded. A design that cannot be read
    is drawn as the box TinyCAD draws (see ExtractSymbol). }
  TDrawHierarchicalSymbol = class(TDrawMethod)
  private
    FSymbol: TDrawingList;        // the child design's symbol sheet, moved so its lower left corner is the origin (nil until loaded)
    FLoaded: Boolean;             // a load has been tried (m_Loaded)
    FTr: TDPoint;                 // the far corner of the symbol (m_tr), before scaling
  public
    { the design file, as a full name in memory (see UXMLPath) }
    FileName: String;
    { why the last load failed ('' when it worked); the C++ shows a message at once, the port leaves that to the command that asked }
    LoadError: String;
    constructor Create(AOpts: TDocOptionsBase); override;
    destructor Destroy; override;
    function GetType: TObjType; override;
    function GetTr: TDPoint; override;
    function ExtractSymbol(out Tr: TDPoint; out Objects: TDrawingList): Boolean; override;
    { read the design AFile and use it as the drawing; False (and LoadError) when it cannot be read }
    function Load(const AFile: String): Boolean;
    { forget what was read, so the next use reads the file again (Reload symbol from design) }
    procedure Unload;
    { True when the design has nothing to draw: it is not there, or it has no symbol sheet }
    function IsNoSymbol: Boolean;
    { True when a load worked and gave a drawing }
    function HasSymbol: Boolean;
    { the Name field shows the design file }
    procedure SetFilenameField;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    function Clone: TDrawingObject; override;
  end;

  { Reads the hierarchical symbol sheet of the design file AFileName into List (the objects use AOpts, whose font,
    style, fill, picture and symbol tables take in what the file has). False, and Err, when the file is not there, is
    not a TinyCAD design or has no such sheet. Set by UDesign. }
  THierarchicalLoader = function(const AFileName: String; AOpts: TDocOptionsBase; List: TDrawingList; out Err: String): Boolean;

var
  HierarchicalLoader: THierarchicalLoader = nil;

{ Create the object for an XML tag, or nil when the tag is not a (supported) object.
  Unsupported but valid TinyCAD tags (TAG, RULER, METAFILE, HierarchicalSymbol) return nil
  and are skipped on load. }
{ does the object have corner points (PointA / PointB)? The rung grid has none (they stay not-a-number), so code that takes the extent of objects skips it }
function HasCorners(Obj: TDrawingObject): Boolean;
function CreateObjectForTag(const Tag: String; Opts: TDocOptionsBase): TDrawingObject;

{ If Tag names an object: create it, load it from the reader and add it to List (unless it is
  empty). Origin objects: only the first is kept; Origin receives its position.
  Returns True when Tag was an object tag (even if skipped). }
function LoadObjectTag(R: TXMLReader; const Tag: String; Opts: TDocOptionsBase;
  List: TDrawingList; var Origin: TDPoint): Boolean;

{ Write objects as CTinyCadDoc::SaveXML does (Details / SaveOriginObject switches) }
procedure SaveObjects(W: TXMLWriter; List: TDrawingList; Details, SaveOriginObject: Boolean;
  Only: TList = nil);

{ Serialised text of one object (for SameAs) }
function ObjectXMLText(Obj: TDrawingObject): String;

implementation

uses UStrings,
  UXMLPath;

{ ---- helpers for the C++ integer types the XML reader casts through ---- }

{ ===========================================================================
  HasCorners  (function)
  Parameters:
    Obj: TDrawingObject - the object
  Returns:
    Boolean - True if PointA and PointB hold numbers
  Notes:
    The rung grid covers the sheet by its own rule and never sets its corner points (they are
    not-a-number, and comparing them stops the program on Windows), so anything that works out
    the extent of a group of objects leaves out the ones that have none.
  =========================================================================== }
function HasCorners(Obj: TDrawingObject): Boolean;
begin
  Result := (not IsNan(Obj.PointA.x)) and (not IsNan(Obj.PointA.y)) and (not IsNan(Obj.PointB.x)) and (not IsNan(Obj.PointB.y));
end;

{ ===========================================================================
  ToByte  (function)
  Parameters:
    V: Integer - the number
  Returns:
    Integer - a value 0-255
  Notes:
    Truncates a number to the low 8 bits, as C stores a BYTE read from a file.
  =========================================================================== }
function ToByte(V: Integer): Integer; inline;
begin
  Result := V and $FF;
end;

{ ===========================================================================
  ToWord  (function)
  Parameters:
    V: Integer - the number
  Returns:
    Integer - a value 0-65535
  Notes:
    Truncates a number to the low 16 bits, as C stores a WORD.
  =========================================================================== }
function ToWord(V: Integer): Integer; inline;
begin
  Result := V and $FFFF;
end;

{ ===========================================================================
  ToInt16  (function)
  Parameters:
    V: Integer - the number
  Returns:
    Integer - a value -32768 to 32767
  Notes:
    Truncates a number to a signed 16 bit value, as C stores a short.
  =========================================================================== }
function ToInt16(V: Integer): Integer; inline;
begin
  Result := SmallInt(V and $FFFF);
end;

{ ---- options base ---- }

{ ===========================================================================
  TDocOptionsBase.Create  (constructor)
  Parameters:  none
  Notes:
    Creates the options every sheet carries: fonts, line styles, fill styles, user colors, snap
    grid, default text metrics, zoom and the editing settings (auto junction on, auto snap on,
    snap range 15).
  =========================================================================== }
constructor TDocOptionsBase.Create;
begin
  inherited Create;
  { COption::Init }
  Fonts := TFontList.Create(TFontResource.CreateSized(TEXT_HEIGHT, False));
  Fonts.Add(TFontResource.CreateSized(PIN_HEIGHT, False));
  Fonts.Add(TFontResource.CreateSized(RULE_HEIGHT, True));
  Styles := TLineStyleList.Create(TLineStyleResource.CreateWith(PS_SOLID, 1, cBLACK));
  Styles.Add(TLineStyleResource.CreateWith(PS_DASH, 1, cBLACK));
  Fills := TFillStyleList.Create(TFillStyleResource.CreateWith(-1, cBLACK));
  Fills.Add(TFillStyleResource.CreateWith(0, cBLACK));
  Images := TImageResourceList.Create(TImageResource.Create);
  Colors := TUserColors.Create;
  Snap := TSnapSettings.Create;
  Metrics := DefaultTextMetrics.Create;
  if EditDefaults.SymbolFontName <> '' then
    SetSymbolFont(EditDefaults.SymbolFontName, EditDefaults.SymbolFontPoints, EditDefaults.SymbolFontBold, EditDefaults.SymbolFontItalic);
  ZoomFactor := 1.0;
  { the user's own choices (the Options dialog), as COption reads them from the registry }
  AutoJunction := EditDefaults.AutoJunction;
  AutoSnap := EditDefaults.AutoSnap;
  AutoSnapRange := EditDefaults.AutoSnapRange;
  AutoDrag := EditDefaults.AutoDrag;
  EditLibrary := False;
  EditPart := 0;
end;

{ ===========================================================================
  TDocOptionsBase.TextExtent  (function)
  Parameters:
    const Str: String - the text
    FontNumber: Integer - font resource number
  Returns:
    TDSize - width and height in design units
  Notes:
    Measures text in a font resource with the sheet's text metrics.
  =========================================================================== }
function TDocOptionsBase.TextExtent(const Str: String; FontNumber: Integer): TDSize;
begin
  Result := Metrics.TextExtent(Str, Fonts.Get(FontNumber) as TFontResource);
end;

{ ===========================================================================
  TDocOptionsBase.LineThickness  (function)
  Parameters:
    StyleNumber: Integer - line style resource number
  Returns:
    Integer - thickness in design units
  Notes:
    Thickness of a line style.
  =========================================================================== }
function TDocOptionsBase.LineThickness(StyleNumber: Integer): Integer;
begin
  Result := (Styles.Get(StyleNumber) as TLineStyleResource).Thickness;
end;

{ ===========================================================================
  TDocOptionsBase.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the resource tables, snap settings and text metrics.
  =========================================================================== }
destructor TDocOptionsBase.Destroy;
begin
  Metrics.Free;
  Snap.Free;
  Colors.Free;
  Images.Free;
  Fills.Free;
  Styles.Free;
  Fonts.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TDocOptionsBase.UnTagAll  (procedure)
  Parameters:  none
  Notes:
    Marks all fonts, line styles and fill styles as unused before a save.
  =========================================================================== }
procedure TDocOptionsBase.UnTagAll;
begin
  Fonts.UnTag;
  Styles.UnTag;
  Fills.UnTag;
  Images.UnTag;
end;

{ ===========================================================================
  TDocOptionsBase.AddStyle  (function)
  Parameters:
    AStyle: Integer - Windows pen style 0-4
    AThickness: Integer - thickness in design units
    AColor: Cardinal - color
  Returns:
    Integer - the style number to store in an object
  Notes:
    Finds or adds a line style (dash style, thickness, color).
  =========================================================================== }
function TDocOptionsBase.AddStyle(AStyle, AThickness: Integer; AColor: Cardinal): Integer;
begin
  Result := Styles.Add(TLineStyleResource.CreateWith(AStyle, AThickness, AColor), -1);
end;

{ ===========================================================================
  TDocOptionsBase.AddImage  (function)
  Parameters:
    const AType: String - the kind of picture (PNG, JPEG)
    const AData: TBytes - the bytes of the picture
  Returns:
    Integer - the number of the picture in the design
  Notes:
    Keeps a picture in the design and returns its number. A picture that is already there (the
    same type and exactly the same bytes) is not added again, so inserting or pasting the same
    picture twice does not make the file bigger.
  =========================================================================== }
function TDocOptionsBase.AddImage(const AType: String; const AData: TBytes): Integer;
var
  Img: TImageResource;
begin
  Img := TImageResource.Create;
  Img.ImgType := AType;
  Img.Data := Copy(AData, 0, Length(AData));
  Result := Images.Add(Img, -1);
end;

{ ===========================================================================
  TDocOptionsBase.GetFontWidth  (function)
  Parameters:
    FontNumber: Integer - a font of the design
  Returns:
    Integer - the width
  Notes:
    The width of a font's characters in design units, or 0 when the font uses its natural width.
  =========================================================================== }
function TDocOptionsBase.GetFontWidth(FontNumber: Integer): Integer;
begin
  Result := (Fonts.Get(FontNumber) as TFontResource).Width;
end;

{ ===========================================================================
  TDocOptionsBase.ChangeFontSize  (function)
  Parameters:
    FontNumber: Integer - whole number
    DeltaHeight: Double - number
    Width: Double - number
  Returns:
    Integer
  Notes:
    COption::ChangeFontSize: the font is copied, its height changed by a whole number of units
    (a height is negative, so a positive change makes the characters smaller) and, if a width is
    given, its width; everything else about it stays. Used when a text or label is resized with
    its handles.
  =========================================================================== }
function TDocOptionsBase.ChangeFontSize(FontNumber: Integer; DeltaHeight, Width: Double): Integer;
var
  Old, New: TFontResource;
begin
  Old := Fonts.Get(FontNumber) as TFontResource;
  New := TFontResource.Create;
  New.Height := Old.Height + Trunc(DeltaHeight);
  New.Width := Old.Width;
  if Width <> 0 then
    New.Width := Trunc(Width);
  New.Weight := Old.Weight;
  New.Italic := Old.Italic;
  New.Underline := Old.Underline;
  New.StrikeOut := Old.StrikeOut;
  New.CharSet := Old.CharSet;
  New.FaceName := Old.FaceName;
  Result := Fonts.Add(New, -1);
end;

{ ===========================================================================
  TDocOptionsBase.GetSymbolFont  (procedure)
  Parameters:
    out AName: String - the face
    out APoints: Integer - the size in points
    out ABold, AItalic: Boolean
  Notes:
    Reads the font number fPIN as the Options dialog shows it. TinyCAD keeps a height in LOGFONT units and its font dialog shows points (MulDiv(points, 96, 72)), so the size is
    the height times 72 / 96, rounded; a weight above 400 is bold.
  =========================================================================== }
procedure TDocOptionsBase.GetSymbolFont(out AName: String; out APoints: Integer; out ABold, AItalic: Boolean);
var
  F: TFontResource;
begin
  F := Fonts.Get(fPIN) as TFontResource;
  AName := F.FaceName;
  APoints := Round(Abs(F.Height) * 72 / 96);
  ABold := F.Weight > 400;
  AItalic := F.Italic <> 0;
end;

{ ===========================================================================
  TDocOptionsBase.SetSymbolFont  (procedure)
  Parameters:
    const AName: String - the face
    APoints: Integer - the size in points
    ABold, AItalic: Boolean
  Notes:
    Changes the font number fPIN in place (a design's fonts are numbered, and the symbols and pins name font 1). When the size is the one the font has now (as points) the height
    is left alone, so that choosing the font TinyCAD starts with does not change it by a rounding (8 points is 11 units, the font has 10). The sign of the height is kept.
    Weight 700 is bold, 400 not; the width, underline, strike-out and character set are left as they are.
  =========================================================================== }
procedure TDocOptionsBase.SetSymbolFont(const AName: String; APoints: Integer; ABold, AItalic: Boolean);
var
  F: TFontResource;
  H: Integer;
begin
  F := Fonts.Get(fPIN) as TFontResource;
  F.FaceName := AName;
  if APoints <> Round(Abs(F.Height) * 72 / 96) then
  begin
    H := Round(APoints * 96 / 72);
    if F.Height < 0 then
      F.Height := -H
    else
      F.Height := H;
  end;
  if ABold then
    F.Weight := 700
  else
    F.Weight := 400;
  F.Italic := Ord(AItalic);
end;

{ ===========================================================================
  TDocOptionsBase.AddFillStyle  (function)
  Parameters:
    AIndex: Integer - -1 none, 0 solid, 1 and up hatches
    AColor: Cardinal - fill color
  Returns:
    Integer - the fill number to store in an object
  Notes:
    Finds or adds a fill style.
  =========================================================================== }
function TDocOptionsBase.AddFillStyle(AIndex: Integer; AColor: Cardinal): Integer;
begin
  Result := Fills.Add(TFillStyleResource.CreateWith(AIndex, AColor), -1);
end;

{ After remapping a file style number, the C++ loaders re-add a copy of the style so that
  the object ends up referring to an entry in the "-1" (unmerged) state. Port of:
      Style = GetNewStyleNumber(Style); lStyle = *GetStyle(Style); Style = AddStyle(&lStyle); }

{ ===========================================================================
  RemapAndReAddStyle  (function)
  Parameters:
    Opts: TDocOptionsBase - the sheet options
    FileStyle: Integer - the style number as written in the file
  Returns:
    Integer - the new style number
  Notes:
    Converts a style number from a file and re-adds that style as a new entry, as TinyCAD does
    so a loaded object gets its own style number.
  =========================================================================== }
function RemapAndReAddStyle(Opts: TDocOptionsBase; FileStyle: Integer): Integer;
var
  Src: TLineStyleResource;
begin
  Result := Opts.Styles.ConvertOld(FileStyle);
  Src := Opts.Styles.Get(Result) as TLineStyleResource;
  Result := Opts.AddStyle(Src.Style, Src.Thickness, Src.Color);
end;

{ ---- TDrawingList ---- }

{ ===========================================================================
  TDrawingList.Create  (constructor)
  Parameters:  none
  Notes:
    Creates a list that owns the objects in it.
  =========================================================================== }
constructor TDrawingList.Create;
begin
  inherited Create(True);
end;

{ ===========================================================================
  TDrawingList.GetItem  (function)
  Parameters:
    Index: Integer - position
  Returns:
    TDrawingObject - the object
  Notes:
    One object of the list.
  =========================================================================== }
function TDrawingList.GetItem(Index: Integer): TDrawingObject;
begin
  Result := TDrawingObject(inherited Items[Index]);
end;

{ ---- TDrawingObject ---- }

{ ===========================================================================
  TDrawingObject.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawingObject that belongs to the sheet whose options are AOpts, and gives
    its properties their default values.
  =========================================================================== }
constructor TDrawingObject.Create(AOpts: TDocOptionsBase);
begin
  inherited Create;
  FOpts := AOpts;
  PointA := DPointInvalid;
  PointB := DPointInvalid;
end;

{ ===========================================================================
  TDrawingObject.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawingObject.TagResources;
begin
end;

{ ===========================================================================
  TDrawingObject.BeginTag  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
    const TagName: String - the element name
  Notes:
    Starts an object's XML element and writes its stable id (oid) when it has one. Every
    object's SaveXML starts with this.
  =========================================================================== }
procedure TDrawingObject.BeginTag(W: TXMLWriter; const TagName: String);
begin
  W.AddTag(TagName);
  if Id <> 0 then
    W.AddAttribute('oid', Id);
end;

{ ===========================================================================
  TDrawingObject.IsEmpty  (function)
  Parameters:  none
  Returns:
    Boolean - True if the object should be discarded
  Notes:
    True when the object holds nothing worth keeping (for example a polygon with fewer than two
    points), so the loader discards it.
  =========================================================================== }
function TDrawingObject.IsEmpty: Boolean;
begin
  Result := False;
end;

{ ===========================================================================
  TDrawingObject.IsConstruction  (function)
  Parameters:  none
  Returns:
    Boolean - True for construction objects
  Notes:
    True for objects that only help while editing (such as ruler guides) and are not part of a
    symbol's drawing.
  =========================================================================== }
function TDrawingObject.IsConstruction: Boolean;
begin
  Result := False;
end;

{ ===========================================================================
  ObjectXMLText  (function)
  Parameters:
    Obj: TDrawingObject - the object
  Returns:
    String - the XML text
  Notes:
    An object's XML as text, used to compare objects.
  =========================================================================== }
function ObjectXMLText(Obj: TDrawingObject): String;
var
  MS: TMemoryStream;
  W: TXMLWriter;
begin
  MS := TMemoryStream.Create;
  try
    W := TXMLWriter.Create(MS);
    try
      Obj.SaveXML(W);
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
  TDrawingObject.SameAs  (function)
  Parameters:
    Other: TDrawingObject - the object to compare with
  Returns:
    Boolean - True if identical
  Notes:
    Whether another object is the same: identical XML.
  =========================================================================== }
function TDrawingObject.SameAs(Other: TDrawingObject): Boolean;
begin
  Result := ObjectXMLText(Self) = ObjectXMLText(Other);
end;

{ ---- TDrawLine ---- }

{ ===========================================================================
  TDrawLine.CreateKind  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
    AKind: TObjType
  Notes:
    Creates a new TDrawLine of the kind AKind (for example wire versus bus, or circle versus
    rectangle) belonging to the sheet options AOpts, with default properties.
  =========================================================================== }
constructor TDrawLine.CreateKind(AOpts: TDocOptionsBase; AKind: TObjType);
begin
  inherited Create(AOpts);
  Kind := AKind;
  case Kind of
    xBus: begin
      UseDefaultStyle := True;
      Style := fLINE;
      Phases := 1;
      PhaseSpacing := DefaultPhaseSpacing;
    end;
    xLineEx2: begin
      UseDefaultStyle := False;
      Style := 0;
    end; // GetCurrentStyle: 0 when nothing chosen
    xDash: begin
      UseDefaultStyle := False;
      Style := fDASH;
    end;
    xWire: begin
      UseDefaultStyle := True;
      Style := fLINE;
    end;
  else
    UseDefaultStyle := False;
    Style := fLINE;
  end;
end;

{ ===========================================================================
  TDrawLine.XMLTagFor  (function)
  Parameters:
    T: TObjType - the line kind
  Returns:
    String - the element name
  Notes:
    The XML element name for a kind of line: BUS, WIRE, or LINE.
  =========================================================================== }
class function TDrawLine.XMLTagFor(T: TObjType): String;
begin
  case T of
    xBus: Result := 'BUS';
    xWire: Result := 'WIRE';
  else
    Result := 'LINE';
  end;
end;

{ ===========================================================================
  TDrawLine.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code Kind
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawLine.GetType: TObjType;
begin
  Result := Kind;
end;

{ ===========================================================================
  TDrawLine.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawLine.TagResources;
begin
  if not UseDefaultStyle then
    FOpts.Styles.Tag(Style);
end;

{ ===========================================================================
  TDrawLine.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawLine as an XML element using W: opens the tag, adds its attributes (and any
    child elements), then closes it. Only non-default content that the file format knows about
    is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawLine.SaveXML(W: TXMLWriter);
begin
  BeginTag(W, XMLTagFor(Kind));
  case Kind of
    xBus, xWire:
      if not UseDefaultStyle then
        W.AddAttribute('style', Style);
  else
    W.AddAttribute('style', Style);
  end;
  W.AddAttribute('a', PointA);
  W.AddAttribute('b', PointB);
  if (Kind = xBus) and (Group <> 0) then
  begin
    W.AddAttribute('phgroup', Group);
    W.AddAttribute('phase', Phase);
  end;
  if (Kind = xBus) and ((Group <> 0) or (PhaseSpacing <> DefaultPhaseSpacing)) then
    W.AddAttribute('phgap', PhaseSpacing);      { (a 1 phase bus keeps the spacing it will have when it is made 3 phase) }
  W.CloseTag;
end;

{ ===========================================================================
  TDrawLine.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawLine from the XML element R is positioned on. An attribute that is missing
    leaves the default value set by the constructor. Resource numbers (fonts, line styles,
    fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawLine.LoadXML(R: TXMLReader);
var
  S: Integer;
begin
  case Kind of
    xBus, xWire:
      begin
        S := 0;
        if R.GetAttribute('style', S) then
        begin
          Style := FOpts.Styles.ConvertOld(ToWord(S));
          UseDefaultStyle := False;
        end
        else
          UseDefaultStyle := True;
      end;
  else
    UseDefaultStyle := False;
    S := Style;
    R.GetAttribute('style', S);
    Style := FOpts.Styles.ConvertOld(ToWord(S));
  end;
  R.GetAttribute('a', PointA);
  R.GetAttribute('b', PointB);
  if Kind = xBus then
  begin
    Group := 0; Phase := 0;
    R.GetAttribute('phgroup', Group);
    R.GetAttribute('phase', Phase);
    R.GetAttribute('phgap', PhaseSpacing);
    if Group <> 0 then
      Phases := 3;
  end;
end;

{ ---- TDrawPolygon ---- }

{ ===========================================================================
  TDrawPolygon.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawPolygon that belongs to the sheet whose options are AOpts, and gives its
    properties their default values.
  =========================================================================== }
constructor TDrawPolygon.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  Kind := xPolygon;
  Close := 0;
  Style := 0; // GetCurrentStyle
  Fill := fsNONE;
end;

{ ===========================================================================
  TDrawPolygon.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code Kind
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawPolygon.GetType: TObjType;
begin
  Result := Kind;
end;

{ ===========================================================================
  TDrawPolygon.IsEmpty  (function)
  Parameters:  none
  Returns:
    Boolean - True if the object should be discarded
  Notes:
    True when the object holds nothing worth keeping (for example a polygon with fewer than two
    points), so the loader discards it.
  =========================================================================== }
function TDrawPolygon.IsEmpty: Boolean;
begin
  Result := Length(Handles) <= 1;
end;

{ ===========================================================================
  TDrawPolygon.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawPolygon.TagResources;
begin
  FOpts.Styles.Tag(Style);
  FOpts.Fills.Tag(Fill);
end;

{ ===========================================================================
  TDrawPolygon.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawPolygon as an XML <POLYGON> element using W: opens the tag, adds its
    attributes (and any child elements), then closes it. Only non-default content that the file
    format knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawPolygon.SaveXML(W: TXMLWriter);
var
  i: Integer;
begin
  if IsEmpty then
    Exit;
  BeginTag(W, 'POLYGON');
  W.AddAttribute('pos', PointA);
  W.AddAttribute('style', Style);
  W.AddAttribute('fill', Fill);
  W.AddAttribute('polygon', Close);
  for i := 0 to High(Handles) do
  begin
    W.AddTag('POINT');
    W.AddAttribute('pos', DPoint(Handles[i].X, Handles[i].Y));
    if Handles[i].Arc = Arc_control then
    begin
      W.AddAttribute('arc', 0);
      W.AddAttribute('control', Handles[i].Control);
    end
    else
      W.AddAttribute('arc', Handles[i].Arc);
    W.CloseTag;
  end;
  W.CloseTag;
end;

{ ===========================================================================
  TDrawPolygon.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawPolygon from the XML element R is positioned on. An attribute that is
    missing leaves the default value set by the constructor. Resource numbers (fonts, line
    styles, fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawPolygon.LoadXML(R: TXMLReader);
var
  Name: String;
  S, F, ArcV: Integer;
  P, Ctl: TDPoint;
  H: TArcPoint;
begin
  R.GetAttribute('pos', PointA);
  S := Style;
  R.GetAttribute('style', S);
  F := Fill;
  R.GetAttribute('fill', F);
  F := ToWord(F);
  if F <> 0 then
    Close := 1
  else
    R.GetAttribute('polygon', Close);
  SetLength(Handles, 0);
  R.IntoTag;
  while R.NextTag(Name) do
    if Name = 'POINT' then
    begin
      P := DPointInvalid;
      Ctl := DPointInvalid;
      ArcV := 0;
      R.GetAttribute('pos', P);
      R.GetAttribute('arc', ArcV);
      if R.GetAttribute('control', Ctl) then
        ArcV := Arc_control; // a control point overrides the arc type
      H.X := P.x;
      H.Y := P.y;
      H.Arc := ArcV;
      H.Control := Ctl;
      H.FlattenedSegment := 0;
      SetLength(Handles, Length(Handles) + 1);
      Handles[High(Handles)] := H;
    end;
  R.OutOfTag;
  Style := RemapAndReAddStyle(FOpts, ToWord(S));
  Fill := FOpts.Fills.ConvertOld(F);
  Kind := xArcEx2;
  CalcBoundingRect;
end;

{ ===========================================================================
  AddPolyBezier  (procedure)
  Parameters:
    var CP: array of TDPoint - the point buffer
    var Count: Integer - number of points in the buffer (updated)
    const P1: TArcPoint - the arc start handle
    const P2: TArcPoint - the arc end handle
  Notes:
    Adds the flattened points of one curved polygon segment (a Bezier approximating an
    elliptical arc) to a point buffer, as TinyCAD flattens arcs.
  =========================================================================== }
procedure AddPolyBezier(var CP: array of TDPoint; var Count: Integer; const P1, P2: TArcPoint);
  procedure Push(const Pt: TDPoint);
  begin
    CP[Count] := Pt;
    Inc(Count);
  end;
var
  X, Y, T, T2, T3, A, B, C, MidX, MidY: Double;
  Np: array[0..3] of TDPoint;
begin
  Np[0] := DPoint(P1.X, P1.Y);
  Np[3] := DPoint(P2.X, P2.Y);
  Np[1] := DPoint(0, 0);
  Np[2] := DPoint(0, 0);
  MidX := (Np[0].x + Np[3].x) / 2.0;
  MidY := (Np[0].y + Np[3].y) / 2.0;
  case P2.Arc of
    Arc_in:
      begin
        Np[1].x := MidX;  Np[1].y := Np[0].y;
        Np[2].x := Np[3].x;  Np[2].y := MidY;
      end;
    Arc_out:
      begin
        Np[1].x := Np[0].x;  Np[1].y := MidY;
        Np[2].x := MidX;  Np[2].y := Np[3].y;
      end;
    Arc_control:
      begin
        Np[1].x := Np[0].x + 2.0 / 3.0 * (P2.Control.x - Np[0].x);
        Np[1].y := Np[0].y + 2.0 / 3.0 * (P2.Control.y - Np[0].y);
        Np[2].x := Np[3].x + 2.0 / 3.0 * (P2.Control.x - Np[3].x);
        Np[2].y := Np[3].y + 2.0 / 3.0 * (P2.Control.y - Np[3].y);
      end;
  end;
  Push(Np[0]);
  T := 0.0;
  while T <= 1.0 do // accumulates 0.05 steps exactly like the C++ for loop
  begin
    T2 := T * T;
    T3 := T2 * T;
    A := 1 - 3 * T + 3 * T2 - T3;
    B := 3 * (T - 2 * T2 + T3);
    C := 3 * (T2 - T3);
    X := A * Np[0].x + B * Np[1].x + C * Np[2].x + T3 * Np[3].x;
    Y := A * Np[0].y + B * Np[1].y + C * Np[2].y + T3 * Np[3].y;
    Push(DPoint(X, Y));
    T := T + 0.05;
  end;
  Push(Np[3]);
end;

{ ===========================================================================
  TDrawPolygon.FlattenPath  (procedure)
  Parameters:  none
  Notes:
    Converts the polygon's handles (corners and arcs) into the plain list of points used to draw
    and hit-test it.
  =========================================================================== }
procedure TDrawPolygon.FlattenPath;
var
  i, Count: Integer;
  Buf: array of TDPoint;
  Last: TArcPoint;
begin
  { each bezier adds at most 23 points }
  SetLength(Buf, Length(Handles) * 24 + 1);
  Count := 0;
  Last.X := 0; Last.Y := 0; Last.Arc := Arc_none; Last.Control := DPointInvalid;
  Last.FlattenedSegment := 0;
  for i := 0 to High(Handles) do
  begin
    if Handles[i].Arc <> Arc_none then
      AddPolyBezier(Buf, Count, Last, Handles[i])
    else
    begin
      Buf[Count] := DPoint(Handles[i].X, Handles[i].Y);
      Inc(Count);
    end;
    Handles[i].FlattenedSegment := Count;
    Last := Handles[i];
  end;
  SetLength(Buf, Count);
  Points := Buf;
end;

{ ===========================================================================
  TDrawPolygon.CalcBoundingRect  (procedure)
  Parameters:  none
  Notes:
    Flattens the path, makes the first handle the origin, and sets the object's bounding
    rectangle (PointA, PointB).
  =========================================================================== }
procedure TDrawPolygon.CalcBoundingRect;
var
  Left, Top, Right, Bottom: Double;
  Q, DiffA: TDPoint;
  i: Integer;
begin
  FlattenPath;
  if Length(Points) > 0 then
  begin
    Q := DPoint(Points[0].x + PointA.x, Points[0].y + PointA.y);
    Left := Trunc(Q.x); Top := Trunc(Q.y); Right := Left; Bottom := Top;
  end
  else
  begin
    Left := PointA.x; Top := PointA.y; Right := Left; Bottom := Top;
  end;
  for i := 0 to High(Points) do
  begin
    Q := DPoint(Points[i].x + PointA.x, Points[i].y + PointA.y);
    Left := Trunc(Min(Left, Q.x));
    Top := Trunc(Min(Top, Q.y));
    Right := Trunc(Max(Right, Q.x));
    Bottom := Trunc(Max(Bottom, Q.y));
  end;
  for i := 0 to High(Handles) do
    if Handles[i].Arc = Arc_control then
    begin
      Q := DPoint(Handles[i].Control.x + PointA.x, Handles[i].Control.y + PointA.y);
      Left := Trunc(Min(Left, Q.x));
      Top := Trunc(Min(Top, Q.y));
      Right := Trunc(Max(Right, Q.x));
      Bottom := Trunc(Max(Bottom, Q.y));
    end;
  { move everything so that A and B lie on the bounding rectangle }
  DiffA := DPoint(Left - PointA.x, Top - PointA.y);
  for i := 0 to High(Handles) do
  begin
    Handles[i].X := Handles[i].X - DiffA.x;
    Handles[i].Y := Handles[i].Y - DiffA.y;
    if Handles[i].Arc = Arc_control then
    begin
      Handles[i].Control.x := Handles[i].Control.x - DiffA.x;
      Handles[i].Control.y := Handles[i].Control.y - DiffA.y;
    end;
  end;
  PointA := DPoint(Left, Top);
  PointB := DPoint(Right, Bottom);
  FlattenPath;
end;

{ ---- simple point objects ---- }

{ ===========================================================================
  TDrawJunction.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xJunction
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawJunction.GetType: TObjType;
begin Result := xJunction; end;

{ ===========================================================================
  TDrawJunction.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawJunction as an XML <JUNCTION> element using W: opens the tag, adds its
    attributes (and any child elements), then closes it. Only non-default content that the file
    format knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawJunction.SaveXML(W: TXMLWriter);
begin
  BeginTag(W, 'JUNCTION');
  W.AddAttribute('pos', PointA);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawJunction.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawJunction from the XML element R is positioned on. An attribute that is
    missing leaves the default value set by the constructor. Resource numbers (fonts, line
    styles, fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawJunction.LoadXML(R: TXMLReader);
begin
  R.GetAttribute('pos', PointA);
  PointB := PointA;
end;

{ ===========================================================================
  TDrawNoConnect.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawNoConnect that belongs to the sheet whose options are AOpts, and gives
    its properties their default values.
  =========================================================================== }
constructor TDrawNoConnect.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  PointA := DPoint(0, 0);
  PointB := PointA;
end;

{ ===========================================================================
  TDrawNoConnect.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xNoConnect
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawNoConnect.GetType: TObjType;
begin Result := xNoConnect; end;

{ ===========================================================================
  TDrawNoConnect.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawNoConnect as an XML <NOCONNECT> element using W: opens the tag, adds its
    attributes (and any child elements), then closes it. Only non-default content that the file
    format knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawNoConnect.SaveXML(W: TXMLWriter);
begin
  BeginTag(W, 'NOCONNECT');
  W.AddAttribute('pos', PointA);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawNoConnect.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawNoConnect from the XML element R is positioned on. An attribute that is
    missing leaves the default value set by the constructor. Resource numbers (fonts, line
    styles, fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawNoConnect.LoadXML(R: TXMLReader);
begin
  R.GetAttribute('pos', PointA);
  PointB := PointA;
end;

{ ===========================================================================
  TDrawError.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options of the sheet the marker is on
  Notes:
    Creates a new TDrawError at the origin with error number 0. The design rules check sets the
    position and number after creating it.
  =========================================================================== }
constructor TDrawError.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  PointA := DPoint(0, 0);
  PointB := PointA;
  ErrorNumber := 0;
end;

{ ===========================================================================
  TDrawError.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xError
  Notes:
    Identifies this class's kind of object. The netlist ignores it and the file writer skips it.
  =========================================================================== }
function TDrawError.GetType: TObjType;
begin Result := xError; end;

{ ===========================================================================
  TDrawError.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
  Notes:
    Does nothing: a check marker is not part of the design and is never written to a file.
  =========================================================================== }
procedure TDrawError.SaveXML(W: TXMLWriter);
begin
end;

{ ===========================================================================
  TDrawError.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader
  Notes:
    Does nothing: a check marker is never read from a file.
  =========================================================================== }
procedure TDrawError.LoadXML(R: TXMLReader);
begin
end;

{ ===========================================================================
  TDrawError.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the marker is selected by that rectangle
  Notes:
    Selection test, copied from CDrawError::IsInside: the marker is a square of half-size 6
    (ERRORSIZE) around its point and counts as inside when that square touches the rectangle.
  =========================================================================== }
function TDrawError.IsInside(Left, Right, Top, Bottom: Double): Boolean;
const
  ERRORSIZE = 6;
begin
  Result := not (((PointA.x - ERRORSIZE < Left) and (PointA.x + ERRORSIZE <= Left)) or
                 ((PointA.x - ERRORSIZE > Right) and (PointA.x + ERRORSIZE >= Right)) or
                 ((PointA.y - ERRORSIZE < Top) and (PointA.y + ERRORSIZE <= Top)) or
                 ((PointA.y - ERRORSIZE > Bottom) and (PointA.y + ERRORSIZE >= Bottom)));
end;

{ ===========================================================================
  TDrawError.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it
  Notes:
    Makes a copy of this marker (same point and error number).
  =========================================================================== }
function TDrawError.Clone: TDrawingObject;
begin
  Result := TDrawError.Create(FOpts);
  Result.PointA := PointA;
  Result.PointB := PointB;
  (Result as TDrawError).ErrorNumber := ErrorNumber;
end;

{ ===========================================================================
  TDrawOrigin.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xOrigin
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawOrigin.GetType: TObjType;
begin Result := xOrigin; end;

{ ===========================================================================
  TDrawOrigin.IsConstruction  (function)
  Parameters:  none
  Returns:
    Boolean - True for construction objects
  Notes:
    True for objects that only help while editing (such as ruler guides) and are not part of a
    symbol's drawing.
  =========================================================================== }
function TDrawOrigin.IsConstruction: Boolean;
begin Result := True; end;

{ ===========================================================================
  TDrawOrigin.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawOrigin as an XML <ORIGIN> element using W: opens the tag, adds its
    attributes (and any child elements), then closes it. Only non-default content that the file
    format knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawOrigin.SaveXML(W: TXMLWriter);
begin
  if DPointHasValue(PointA) then
  begin
    BeginTag(W, 'ORIGIN');
    W.AddAttribute('pos', PointA);
    W.CloseTag;
  end;
end;

{ ===========================================================================
  TDrawOrigin.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawOrigin from the XML element R is positioned on. An attribute that is missing
    leaves the default value set by the constructor. Resource numbers (fonts, line styles,
    fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawOrigin.LoadXML(R: TXMLReader);
begin
  R.GetAttribute('pos', PointA);
  PointB := PointA;
end;

{ ===========================================================================
  TDrawBusSlash.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawBusSlash that belongs to the sheet whose options are AOpts, and gives its
    properties their default values.
  =========================================================================== }
constructor TDrawBusSlash.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  PointA := DPoint(0, 0);
  PointB := PointA;
  Dir := 0;
end;

{ ===========================================================================
  TDrawBusSlash.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xBusSlash
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawBusSlash.GetType: TObjType;
begin Result := xBusSlash; end;

{ ===========================================================================
  TDrawBusSlash.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawBusSlash as an XML <BUSSLASH> element using W: opens the tag, adds its
    attributes (and any child elements), then closes it. Only non-default content that the file
    format knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawBusSlash.SaveXML(W: TXMLWriter);
begin
  BeginTag(W, 'BUSSLASH');
  W.AddAttribute('pos', PointA);
  W.AddAttribute('direction', Dir);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawBusSlash.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawBusSlash from the XML element R is positioned on. An attribute that is
    missing leaves the default value set by the constructor. Resource numbers (fonts, line
    styles, fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawBusSlash.LoadXML(R: TXMLReader);
var
  D: Integer;
begin
  R.GetAttribute('pos', PointA);
  D := Dir;
  R.GetAttribute('direction', D);
  Dir := ToByte(D);
  PointB := PointA;
end;

{ ---- TDrawSquare ---- }

{ ===========================================================================
  TDrawSquare.CreateKind  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
    AKind: TObjType
  Notes:
    Creates a new TDrawSquare of the kind AKind (for example wire versus bus, or circle versus
    rectangle) belonging to the sheet options AOpts, with default properties.
  =========================================================================== }
constructor TDrawSquare.CreateKind(AOpts: TDocOptionsBase; AKind: TObjType);
begin
  inherited Create(AOpts);
  Kind := AKind;
  Style := 0; // GetCurrentStyle / GetCurrentFillStyle
  Fill := 0;
end;

{ ===========================================================================
  TDrawSquare.IsSquare  (function)
  Parameters:  none
  Returns:
    Boolean - True for a rectangle
  Notes:
    Whether this is a rectangle (True) or an ellipse (False).
  =========================================================================== }
function TDrawSquare.IsSquare: Boolean;
begin
  Result := Kind = xSquareEx3;
end;

{ ===========================================================================
  TDrawSquare.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code Kind
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawSquare.GetType: TObjType;
begin
  Result := Kind;
end;

{ ===========================================================================
  TDrawSquare.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawSquare.TagResources;
begin
  FOpts.Styles.Tag(Style);
  FOpts.Fills.Tag(Fill);
end;

{ ===========================================================================
  TDrawSquare.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawSquare as an XML <RECTANGLE> element using W: opens the tag, adds its
    attributes (and any child elements), then closes it. Only non-default content that the file
    format knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawSquare.SaveXML(W: TXMLWriter);
begin
  if IsSquare then
    BeginTag(W, 'RECTANGLE')
  else
    BeginTag(W, 'ELLIPSE');
  W.AddAttribute('a', PointA);
  W.AddAttribute('b', PointB);
  W.AddAttribute('style', Style);
  W.AddAttribute('fill', Fill);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawSquare.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawSquare from the XML element R is positioned on. An attribute that is missing
    leaves the default value set by the constructor. Resource numbers (fonts, line styles,
    fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawSquare.LoadXML(R: TXMLReader);
var
  S, F: Integer;
begin
  R.GetAttribute('a', PointA);
  R.GetAttribute('b', PointB);
  S := Style;
  R.GetAttribute('style', S);
  F := Fill;
  R.GetAttribute('fill', F);
  Style := RemapAndReAddStyle(FOpts, ToWord(S));
  Fill := FOpts.Fills.ConvertOld(ToWord(F));
end;

{ ---- TDrawText ---- }

{ ===========================================================================
  TDrawText.CreateKind  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
    AKind: TObjType
  Notes:
    Creates a new TDrawText of the kind AKind (for example wire versus bus, or circle versus
    rectangle) belonging to the sheet options AOpts, with default properties.
  =========================================================================== }
constructor TDrawText.CreateKind(AOpts: TDocOptionsBase; AKind: TObjType);
begin
  inherited Create(AOpts);
  Kind := AKind;
  Dir := 3;
  Str := '';
  PointA := DPoint(0, 0);
  PointB := PointA;
  FontStyle := 0; // GetCurrentFont
  if Kind = xBusNameEx then
    FontColor := FOpts.Colors.Get(UC_LABEL)
  else
    FontColor := cBLACK; // cTEXT
end;

{ ===========================================================================
  TDrawText.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code Kind
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawText.GetType: TObjType;
begin
  Result := Kind;
end;

{ ===========================================================================
  TDrawText.IsEmpty  (function)
  Parameters:  none
  Returns:
    Boolean - True if the object should be discarded
  Notes:
    True when the object holds nothing worth keeping (for example a polygon with fewer than two
    points), so the loader discards it.
  =========================================================================== }
function TDrawText.IsEmpty: Boolean;
begin
  Result := Str = '';
end;

{ ===========================================================================
  TDrawText.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawText.TagResources;
begin
  FOpts.Fonts.Tag(FontStyle);
end;

{ ===========================================================================
  TDrawText.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawText as an XML <BUSNAME> element using W: opens the tag, adds its
    attributes (and any child elements), then closes it. Only non-default content that the file
    format knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawText.SaveXML(W: TXMLWriter);
begin
  if IsEmpty then
    Exit;
  if Kind = xBusNameEx then
    BeginTag(W, 'BUSNAME')
  else
    BeginTag(W, 'TEXT');
  W.AddAttribute('pos', PointA);
  W.AddAttribute('direction', Dir);
  W.AddAttribute('font', FontStyle);
  W.AddAttributeColor('color', FontColor);
  W.AddChildData(Str);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawText.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawText from the XML element R is positioned on. An attribute that is missing
    leaves the default value set by the constructor. Resource numbers (fonts, line styles,
    fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawText.LoadXML(R: TXMLReader);
var
  D, F: Integer;
begin
  R.GetAttribute('pos', PointA);
  D := Dir;
  R.GetAttribute('direction', D);
  Dir := ToByte(D);
  F := FontStyle;
  R.GetAttribute('font', F);
  R.GetAttributeColor('color', FontColor);
  R.GetChildData(Str);
  FontStyle := FOpts.Fonts.ConvertOld(ToInt16(F));
  { PointB (text extent) needs font metrics: computed by the rendering layer }
end;

{ ---- TDrawLabel ---- }

{ ===========================================================================
  TDrawLabel.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawLabel that belongs to the sheet whose options are AOpts, and gives its
    properties their default values.
  =========================================================================== }
constructor TDrawLabel.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  Dir := 3;
  Str := '';
  PointA := DPoint(0, 0);
  PointB := PointA;
  ActivePoint := DPointInvalid;
  FontStyle := 0;
  FontColor := FOpts.Colors.Get(UC_LABEL);
  LabelStyle := label_normal;
end;

{ ===========================================================================
  TDrawLabel.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xLabelEx2
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawLabel.GetType: TObjType;
begin Result := xLabelEx2; end;

{ ===========================================================================
  TDrawLabel.IsEmpty  (function)
  Parameters:  none
  Returns:
    Boolean - True if the object should be discarded
  Notes:
    True when the object holds nothing worth keeping (for example a polygon with fewer than two
    points), so the loader discards it.
  =========================================================================== }
function TDrawLabel.IsEmpty: Boolean;
begin
  Result := (LabelStyle = label_normal) and (Str = '');
end;

{ ===========================================================================
  TDrawLabel.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawLabel.TagResources;
begin
  FOpts.Fonts.Tag(FontStyle);
end;

{ ===========================================================================
  TDrawLabel.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawLabel as an XML <LABEL> element using W: opens the tag, adds its attributes
    (and any child elements), then closes it. Only non-default content that the file format
    knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawLabel.SaveXML(W: TXMLWriter);
begin
  if IsEmpty then
    Exit;
  BeginTag(W, 'LABEL');
  W.AddAttribute('pos', ActivePoint);
  W.AddAttribute('direction', Dir);
  W.AddAttribute('font', FontStyle);
  W.AddAttributeColor('color', FontColor);
  W.AddAttribute('style', LabelStyle);
  W.AddChildData(Str);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawLabel.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawLabel from the XML element R is positioned on. An attribute that is missing
    leaves the default value set by the constructor. Resource numbers (fonts, line styles,
    fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawLabel.LoadXML(R: TXMLReader);
var
  D, F, S: Integer;
begin
  S := label_normal;
  R.GetAttribute('pos', ActivePoint);
  D := Dir;
  R.GetAttribute('direction', D);
  Dir := ToByte(D);
  F := FontStyle;
  R.GetAttribute('font', F);
  R.GetAttributeColor('color', FontColor);
  R.GetAttribute('style', S);
  R.GetChildData(Str);
  LabelStyle := S;
  FontStyle := FOpts.Fonts.ConvertOld(ToInt16(F));
  { CalcLayout (text box) needs font metrics: computed by the rendering layer }
end;

{ ---- TDrawPower ---- }

{ ===========================================================================
  TDrawPower.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawPower that belongs to the sheet whose options are AOpts, and gives its
    properties their default values.
  =========================================================================== }
constructor TDrawPower.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  PointA := DPoint(0, 0);
  PointB := PointA;
  Str := '';
  Dir := 1;
  Which := 0;
end;

{ ===========================================================================
  TDrawPower.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xPower
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawPower.GetType: TObjType;
begin Result := xPower; end;

{ ===========================================================================
  TDrawPower.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawPower.TagResources;
begin
  FOpts.Fonts.Tag(fPIN);
end;

{ ===========================================================================
  TDrawPower.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawPower as an XML <POWER> element using W: opens the tag, adds its attributes
    (and any child elements), then closes it. Only non-default content that the file format
    knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawPower.SaveXML(W: TXMLWriter);
begin
  BeginTag(W, 'POWER');
  W.AddAttribute('pos', PointA);
  W.AddAttribute('which', Which);
  W.AddAttribute('direction', Dir);
  W.AddChildData(Str);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawPower.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawPower from the XML element R is positioned on. An attribute that is missing
    leaves the default value set by the constructor. Resource numbers (fonts, line styles,
    fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawPower.LoadXML(R: TXMLReader);
var
  V: Integer;
begin
  R.GetAttribute('pos', PointA);
  V := Which; R.GetAttribute('which', V); Which := ToByte(V);
  V := Dir; R.GetAttribute('direction', V); Dir := ToByte(V);
  R.GetChildData(Str);
  PointB := PointA;
end;

{ ---- TDrawPin ---- }

{ ===========================================================================
  TDrawPin.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawPin that belongs to the sheet whose options are AOpts, and gives its
    properties their default values.
  =========================================================================== }
constructor TDrawPin.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  Which := 0;
  Dir := 0;
  Number := '1';
  Elec := 0;
  Str := '';
  Show := 3;
  Length := 30;     // registry default for "PinLength"
  Part := 0;
  NumberPos := 0;   // registry default for "PinNumberPos"
  CentreName := 0;
end;

{ ===========================================================================
  TDrawPin.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xPinEx
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawPin.GetType: TObjType;
begin Result := xPinEx; end;

{ ===========================================================================
  TDrawPin.IsPower  (function)
  Parameters:  none
  Returns:
    Boolean - True for a power pin
  Notes:
    Whether this is a hidden power pin (Which = 4).
  =========================================================================== }
function TDrawPin.IsPower: Boolean;
begin
  Result := Which = 4;
end;

{ ===========================================================================
  TDrawPin.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawPin.TagResources;
begin
  FOpts.Fonts.Tag(fPIN);
end;

{ ===========================================================================
  TDrawPin.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawPin as an XML <PIN> element using W: opens the tag, adds its attributes
    (and any child elements), then closes it. Only non-default content that the file format
    knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawPin.SaveXML(W: TXMLWriter);
begin
  BeginTag(W, 'PIN');
  W.AddAttribute('pos', PointA);
  W.AddAttribute('which', Which);
  W.AddAttribute('elec', Elec);
  W.AddAttribute('direction', Dir);
  W.AddAttribute('part', Part);
  W.AddAttribute('number', Number);
  W.AddAttribute('show', Show);
  W.AddAttribute('length', Length);
  W.AddAttribute('number_pos', NumberPos);
  W.AddAttribute('centre_name', CentreName);
  W.AddChildData(Str);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawPin.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawPin from the XML element R is positioned on. An attribute that is missing
    leaves the default value set by the constructor. Resource numbers (fonts, line styles,
    fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawPin.LoadXML(R: TXMLReader);
var
  V: Integer;
begin
  NumberPos := 0;
  R.GetAttribute('pos', PointA);
  V := Which; R.GetAttribute('which', V); Which := ToByte(V);
  V := Elec; R.GetAttribute('elec', V); Elec := ToByte(V);
  V := Dir; R.GetAttribute('direction', V); Dir := ToByte(V);
  V := Part; R.GetAttribute('part', V); Part := ToByte(V);
  R.GetAttribute('number', Number);
  V := Show; R.GetAttribute('show', V); Show := ToByte(V);
  V := Length; R.GetAttribute('length', V); Length := ToWord(V);
  R.GetAttribute('number_pos', NumberPos);
  if not R.GetAttribute('centre_name', CentreName) then
    CentreName := Ord(IsPower); // power pins default to centred names
  R.GetChildData(Str);
  { zero length pins are allowed; shorter than 5 is forced to 20 }
  if (Length < 5) and (Length <> 0) then
    Length := 20;
  { DetermineSize (PointB) needs symbol geometry: computed by the rendering layer }
end;

{ ---- TDrawNoteText ---- }

{ ===========================================================================
  TDrawNoteText.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawNoteText that belongs to the sheet whose options are AOpts, and gives its
    properties their default values.
  =========================================================================== }
constructor TDrawNoteText.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  Dir := 3;
  Str := 'Note';
  PointA := DPoint(0, 0);
  PointB := PointA;
  FontStyle := 0;
  FontColor := FOpts.Colors.Get(UC_NOTETEXT_TEXT);
  BorderStyle := BS_RoundedRectangle;
  { The C++ constructor registers a fill and a line style in the sheet's tables. This
    affects the numbers later resources receive, so it is reproduced. }
  Fill := FOpts.AddFillStyle(0, FOpts.Colors.Get(UC_NOTETEXT_FILL));
  Style := FOpts.AddStyle(PS_SOLID, 1, FOpts.Colors.Get(UC_NOTETEXT_LINE));
end;

{ ===========================================================================
  TDrawNoteText.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xNoteText
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawNoteText.GetType: TObjType;
begin Result := xNoteText; end;

{ ===========================================================================
  TDrawNoteText.IsEmpty  (function)
  Parameters:  none
  Returns:
    Boolean - True if the object should be discarded
  Notes:
    True when the object holds nothing worth keeping (for example a polygon with fewer than two
    points), so the loader discards it.
  =========================================================================== }
function TDrawNoteText.IsEmpty: Boolean;
begin
  Result := Str = '';
end;

{ ===========================================================================
  TDrawNoteText.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawNoteText.TagResources;
begin
  FOpts.Fonts.Tag(FontStyle);
  FOpts.Styles.Tag(Style);
  FOpts.Fills.Tag(Fill);
end;

{ ===========================================================================
  TDrawNoteText.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawNoteText as an XML <NOTE_TEXT> element using W: opens the tag, adds its
    attributes (and any child elements), then closes it. Only non-default content that the file
    format knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawNoteText.SaveXML(W: TXMLWriter);
begin
  BeginTag(W, 'NOTE_TEXT');
  W.AddAttribute('a', PointA);
  W.AddAttribute('b', PointB);
  W.AddAttribute('direction', Dir);
  W.AddAttribute('style', Style);
  W.AddAttribute('fill', Fill);
  W.AddAttribute('font', FontStyle);
  W.AddAttributeColor('color', FontColor);
  W.AddAttribute('border_style', BorderStyle);
  W.AddChildData(Str);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawNoteText.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawNoteText from the XML element R is positioned on. An attribute that is
    missing leaves the default value set by the constructor. Resource numbers (fonts, line
    styles, fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawNoteText.LoadXML(R: TXMLReader);
var
  D, S, F, Fo: Integer;
begin
  R.GetAttribute('a', PointA);
  R.GetAttribute('b', PointB);
  D := Dir; R.GetAttribute('direction', D); Dir := ToByte(D);
  S := Style; R.GetAttribute('style', S);
  F := Fill; R.GetAttribute('fill', F);
  Fo := FontStyle; R.GetAttribute('font', Fo);
  R.GetAttributeColor('color', FontColor);
  R.GetAttribute('border_style', BorderStyle);
  R.GetChildData(Str);
  Style := RemapAndReAddStyle(FOpts, ToWord(S));
  Fill := FOpts.Fills.ConvertOld(ToWord(F));
  FontStyle := FOpts.Fonts.ConvertOld(ToInt16(Fo));
end;

{ ---- TDrawMethod (SYMBOL) ---- }

{ ===========================================================================
  TDrawMethod.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawMethod that belongs to the sheet whose options are AOpts, and gives its
    properties their default values.
  =========================================================================== }
constructor TDrawMethod.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  SymbolId := 0;
  PointA := DPoint(0, 0);
  PointB := PointA;
  SetLength(Fields, 3);
  Fields[0].Description := 'Ref';   Fields[0].Value := ''; Fields[0].Show := 1;
  Fields[0].Position := DPoint(0, 0); Fields[0].FieldType := default_show;
  Fields[1].Description := 'Name';  Fields[1].Value := ''; Fields[1].Show := 1;
  Fields[1].Position := DPoint(0, 0); Fields[1].FieldType := default_show;
  Fields[2].Description := 'Other'; Fields[2].Value := ''; Fields[2].Show := 0;
  Fields[2].Position := DPoint(0, 0); Fields[2].FieldType := default_hidden;
  Rotate := 3;
  Part := 0;
  ScalingX := 1.0;
  ScalingY := 1.0;
  CanScale := 0;
  ShowPower := 0;
end;

{ ===========================================================================
  TDrawMethod.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xMethodEx3
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawMethod.GetType: TObjType;
begin Result := xMethodEx3; end;

{ ===========================================================================
  TDrawMethod.XmlTag  (function)
  Parameters:  none
  Returns:
    String - 'SYMBOL'
  Notes:
    The name of the XML element this object is saved as. A class that is saved the same way
    under another name overrides it.
  =========================================================================== }
function TDrawMethod.XmlTag: String;
begin Result := 'SYMBOL'; end;

{ ===========================================================================
  TDrawMethod.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawMethod.TagResources;
begin
  FOpts.Fonts.Tag(fPIN);
  FOpts.TagSymbol(SymbolId);
  FOpts.TagSymbolContents(SymbolId, Part, ShowPower <> 0);
end;

{ ===========================================================================
  TDrawMethod.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawMethod as an XML <SYMBOL> element using W: opens the tag, adds its
    attributes (and any child elements), then closes it. Only non-default content that the file
    format knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawMethod.SaveXML(W: TXMLWriter);
var
  i, j: Integer;
  Sorted: array of TNetlistHint;
  Tmp: TNetlistHint;
begin
  BeginTag(W, XmlTag);
  W.AddAttribute('id', SymbolId);
  W.AddAttribute('pos', PointA);
  W.AddAttribute('part', Part);
  W.AddAttribute('rotate', Rotate);
  W.AddAttribute('can_scale', CanScale);
  W.AddAttribute('show_power', ShowPower);
  W.AddAttribute('scale_x', ScalingX);
  W.AddAttribute('scale_y', ScalingY);
  for i := 0 to High(Fields) do
  begin
    W.AddTag('FIELD');
    W.AddAttribute('type', Fields[i].FieldType);
    W.AddAttribute('description', Fields[i].Description);
    W.AddAttribute('value', Fields[i].Value);
    W.AddAttribute('show', Fields[i].Show);
    W.AddAttribute('pos', Fields[i].Position);
    W.CloseTag;
  end;
  { hints live in a std::map<CString,int>: written in key order }
  Sorted := Copy(Hints, 0, Length(Hints));
  for i := 1 to High(Sorted) do
  begin
    Tmp := Sorted[i];
    j := i - 1;
    while (j >= 0) and (CompareStr(Sorted[j].Pin, Tmp.Pin) > 0) do
    begin
      Sorted[j + 1] := Sorted[j];
      Dec(j);
    end;
    Sorted[j + 1] := Tmp;
  end;
  for i := 0 to High(Sorted) do
  begin
    W.AddTag('HINT');
    W.AddAttribute('pin', Sorted[i].Pin);
    W.AddAttribute('net', Sorted[i].Net);
    W.CloseTag;
  end;
  if not Product.IsEmpty then
    SaveProductXml(W, Product);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawMethod.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawMethod from the XML element R is positioned on. An attribute that is missing
    leaves the default value set by the constructor. Resource numbers (fonts, line styles,
    fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawMethod.LoadXML(R: TXMLReader);
var
  Name, PinName: String;
  V, i, T, NetV, k: Integer;
begin
  R.GetAttribute('id', SymbolId);
  SymbolId := ToInt16(SymbolId);
  R.GetAttribute('pos', PointA);
  V := Part; R.GetAttribute('part', V); Part := ToByte(V);
  V := Rotate; R.GetAttribute('rotate', V); Rotate := ToByte(V);
  R.GetAttribute('can_scale', CanScale);
  R.GetAttribute('show_power', ShowPower);
  R.GetAttribute('scale_x', ScalingX);
  R.GetAttribute('scale_y', ScalingY);
  R.IntoTag;
  i := 0;
  while R.NextTag(Name) do
  begin
    if Name = 'FIELD' then
    begin
      { m_fields.resize(i+1): shrinks on the first FIELD, grows with blank entries after }
      if Length(Fields) <> i + 1 then
      begin
        k := Length(Fields);
        SetLength(Fields, i + 1);
        while k <= i do
        begin
          Fields[k].FieldType := 0;
          Fields[k].Description := '';
          Fields[k].Value := '';
          Fields[k].Show := 0;
          Fields[k].Position := DPointInvalid;
          Inc(k);
        end;
      end;
      T := 0;
      R.GetAttribute('type', T);
      R.GetAttribute('description', Fields[i].Description);
      R.GetAttribute('value', Fields[i].Value);
      R.GetAttribute('show', Fields[i].Show);
      R.GetAttribute('pos', Fields[i].Position);
      Fields[i].FieldType := T;
      Inc(i);
    end
    else if Name = 'PRODUCT' then
      LoadProductXml(R, Product)
    else if Name = 'HINT' then
    begin
      PinName := '';
      NetV := 0;
      R.GetAttribute('pin', PinName);
      R.GetAttribute('net', NetV);
      k := 0;
      while (k < Length(Hints)) and (Hints[k].Pin <> PinName) do Inc(k);
      if k = Length(Hints) then
        SetLength(Hints, k + 1);
      Hints[k].Pin := PinName;
      Hints[k].Net := NetV;
    end;
  end;
  R.OutOfTag;
  SymbolId := FOpts.NewSymbolNumber(SymbolId);
  { PointB (symbol bounding box) needs symbol geometry: computed by the rendering layer }
end;


{ =====================================================================================
  GEOMETRY
  ===================================================================================== }

const
  JUNCTION_SIZE = 3;   // color.h
  SLASH_SIZE = 20;     // DrawBusSlash.cpp
  POWER_SIZE = 14;     // Power.cpp

{ ===========================================================================
  CopyPoints  (procedure)
  Parameters:
    Src: TDrawingObject - the object to copy from
    Dst: TDrawingObject - the object to copy to
  Notes:
    Copies the two defining points from one object to another (used by Clone).
  =========================================================================== }
procedure CopyPoints(Src, Dst: TDrawingObject);
begin
  Dst.PointA := Src.PointA;
  Dst.PointB := Src.PointB;
end;

{ ---- TDrawingObject defaults (CDrawingObject) ---- }

{ ===========================================================================
  TDrawingObject.CanResize  (function)
  Parameters:  none
  Returns:
    Boolean - False
  Notes:
    Whether the object has resize handles. False for most objects.
  =========================================================================== }
function TDrawingObject.CanResize: Boolean;
begin
  Result := False;
end;

{ ===========================================================================
  TDrawMetaFile.CanResize  (function)
  Parameters:  none
  Returns:
    Boolean - True
  Notes:
    Yes: a picture has the eight handles of TinyCAD's rectangle tracker when it is the one
    selected object.
  =========================================================================== }
function TDrawMetaFile.CanResize: Boolean;
begin
  Result := True;
end;

{ ===========================================================================
  TDrawSquare.CanResize  (function)
  Parameters:  none
  Returns:
    Boolean - True
  Notes:
    Yes: a rectangle or ellipse has the eight handles of TinyCAD's rectangle tracker when it is
    the one selected object.
  =========================================================================== }
function TDrawSquare.CanResize: Boolean;
begin
  Result := True;
end;

{ ===========================================================================
  TDrawNoteText.CanResize  (function)
  Parameters:  none
  Returns:
    Boolean - True
  Notes:
    Yes: a note has the eight handles of TinyCAD's rectangle tracker when it is the one selected
    object.
  =========================================================================== }
function TDrawNoteText.CanResize: Boolean;
begin
  Result := True;
end;

{ ===========================================================================
  TDrawingObject.ResizeHandleRect  (function)
  Parameters:
    Handle: Integer - whole number
    HandleSize: Double - number
  Returns:
    TDRect
  Notes:
    MFC's CRectTracker with resizeOutside, which is how TinyCAD draws the handles of a selected
    rectangle: eight small squares set just outside the rectangle, at its four corners and the
    middles of its four sides.
  =========================================================================== }
function TDrawingObject.ResizeHandleRect(Handle: Integer; HandleSize: Double): TDRect;
var
  L, T, Rt, B, Cx, Cy, H: Double;
begin
  L := Min(PointA.x, PointB.x);
  Rt := Max(PointA.x, PointB.x);
  T := Min(PointA.y, PointB.y);
  B := Max(PointA.y, PointB.y);
  Cx := (L + Rt) / 2;
  Cy := (T + B) / 2;
  H := HandleSize / 2;
  case Handle of
    HANDLE_TOPLEFT:     Result := DRect(L - HandleSize, T - HandleSize, L, T);
    HANDLE_TOPRIGHT:    Result := DRect(Rt, T - HandleSize, Rt + HandleSize, T);
    HANDLE_BOTTOMRIGHT: Result := DRect(Rt, B, Rt + HandleSize, B + HandleSize);
    HANDLE_BOTTOMLEFT:  Result := DRect(L - HandleSize, B, L, B + HandleSize);
    HANDLE_TOP:         Result := DRect(Cx - H, T - HandleSize, Cx + H, T);
    HANDLE_RIGHT:       Result := DRect(Rt, Cy - H, Rt + HandleSize, Cy + H);
    HANDLE_BOTTOM:      Result := DRect(Cx - H, B, Cx + H, B + HandleSize);
    HANDLE_LEFT:        Result := DRect(L - HandleSize, Cy - H, L, Cy + H);
  else
    Result := DRect(0, 0, 0, 0);
  end;
end;

{ ===========================================================================
  TDrawingObject.ResizeHandleAt  (function)
  Parameters:
    const P: TDPoint - a point, in design units
    HandleSize: Double - number
  Returns:
    Integer
  Notes:
    A point is on a handle if it is in the handle's square, made a little larger so that it is
    easy to hit. The corners are tried first, then the sides, as the tracker does. HANDLE_NONE
    for an object without handles, and for the inside of the rectangle (a click there selects or
    moves the object as usual).
  =========================================================================== }
function TDrawingObject.ResizeHandleAt(const P: TDPoint; HandleSize: Double): Integer;
var
  i: Integer;
  R: TDRect;
  Slack: Double;
begin
  Result := HANDLE_NONE;
  if not CanResize then
    Exit;
  Slack := HandleSize / 3;
  for i := HANDLE_TOPLEFT to HANDLE_LEFT do
  begin
    R := ResizeHandleRect(i, HandleSize);
    if (P.x >= R.Left - Slack) and (P.x <= R.Right + Slack) and (P.y >= R.Top - Slack) and (P.y <= R.Bottom + Slack) then
      Exit(i);
  end;
end;

{ ===========================================================================
  TDrawingObject.ResizeBy  (procedure)
  Parameters:
    Handle: Integer - whole number
    const R: TDPoint - the XML reader, positioned on this element
  Notes:
    CDrawRectOutline::MoveField. The rectangle is taken in order (left < right, top < bottom);
    the side or corner that the handle is on moves by R and the opposite one stays; then the two
    corners are put back in the order they were in (A left of B or the other way round), so a
    rectangle that has been flipped stays flipped. Dragging a side past the opposite one turns
    the rectangle inside out, as it does in TinyCAD.
  =========================================================================== }
procedure TDrawingObject.ResizeBy(Handle: Integer; const R: TDPoint);
var
  L, T, Rt, B: Double;
  AFirstX, AFirstY: Boolean;
begin
  L := Min(PointA.x, PointB.x);
  Rt := Max(PointA.x, PointB.x);
  T := Min(PointA.y, PointB.y);
  B := Max(PointA.y, PointB.y);
  case Handle of
    HANDLE_TOPLEFT:     begin
      L := L + R.x;
      T := T + R.y;
    end;
    HANDLE_TOPRIGHT:    begin
      Rt := Rt + R.x;
      T := T + R.y;
    end;
    HANDLE_BOTTOMRIGHT: begin
      Rt := Rt + R.x;
      B := B + R.y;
    end;
    HANDLE_BOTTOMLEFT:  begin
      L := L + R.x;
      B := B + R.y;
    end;
    HANDLE_TOP:         T := T + R.y;
    HANDLE_RIGHT:       Rt := Rt + R.x;
    HANDLE_BOTTOM:      B := B + R.y;
    HANDLE_LEFT:        L := L + R.x;
    8, 11:              begin
      L := L + R.x;
      Rt := Rt + R.x;
      T := T + R.y;
      B := B + R.y;
    end;
  end;
  AFirstX := PointA.x < PointB.x;
  AFirstY := PointA.y < PointB.y;
  if AFirstX then begin
    PointA.x := L;
    PointB.x := Rt;
  end else begin
    PointB.x := L;
    PointA.x := Rt;
  end;
  if AFirstY then begin
    PointA.y := T;
    PointB.y := B;
  end else begin
    PointB.y := T;
    PointA.y := B;
  end;
end;

{ ===========================================================================
  TDrawingObject.ResizeAspectRatio  (function)
  Parameters:  none
  Returns:
    Double
  Notes:
    CDrawingObject::AspectRatio. A rectangle of no width has no ratio (0 is returned, so the
    shape is not forced).
  =========================================================================== }
function TDrawingObject.ResizeAspectRatio: Double;
begin
  if PointB.x = PointA.x then
    Result := 0
  else
    Result := Abs((PointB.y - PointA.y) / (PointB.x - PointA.x));
end;

{ ===========================================================================
  TDrawingObject.FieldAt  (function)
  Parameters:
    const P: TDPoint - a point of the sheet (not snapped)
  Returns:
    Integer - FIELD_BASE + the field's number, or -1
  Notes:
    Is the point on a field of the object that can be dragged by itself? Most objects have none,
    so this is always -1; a placed symbol answers for its shown fields.
  =========================================================================== }
function TDrawingObject.FieldAt(const P: TDPoint): Integer;
begin
  Result := -1;
end;

{ ===========================================================================
  TDrawingObject.MoveFieldBy  (procedure)
  Parameters:
    Field: Integer - FIELD_BASE + the field's number, as FieldAt gave it
    const R: TDPoint - how far to move it
  Notes:
    Moves a field of the object. Most objects have no fields, so nothing happens; a placed
    symbol moves the field's position (kept relative to the symbol).
  =========================================================================== }
procedure TDrawingObject.MoveFieldBy(Field: Integer; const R: TDPoint);
begin
  { nothing to move }
end;

{ ===========================================================================
  TDrawMethod.CanResize  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    A placed symbol has the tracker's handles only if it was marked resizable
    (CDrawMethod::PaintHandles and IsInsideField).
  =========================================================================== }
function TDrawMethod.CanResize: Boolean;
begin
  Result := CanScale <> 0;
end;

{ ===========================================================================
  TDrawMethod.ResizeBy  (procedure)
  Parameters:
    Handle: Integer - whole number
    const R: TDPoint - the XML reader, positioned on this element
  Notes:
    CDrawMethod::MoveField for the handles. The symbol's rectangle (its origin PointA and
    PointB, which can be on either side of it: the symbol's own size can be negative) is changed
    by the handle in the same way as any rectangle's, keeping A and B in the order they were in.
    Then the scale is worked out from it: the symbol's own size is found again with the scale
    put to 1, and the new width and height divided by that give the new scale, the two swapped
    for a symbol turned a quarter (rotate 2 or 3, whose width is the symbol's height). The
    corners are then those of the new rectangle. The fields keep their offsets from the origin
    (they are not scaled), and wires are not moved.
  =========================================================================== }
procedure TDrawMethod.ResizeBy(Handle: Integer; const R: TDPoint);
var
  NewA, NewB: TDPoint;
  DenX, DenY, Nx, Ny, Q: Double;
  Tr: TDPoint;
  Objs: TDrawingList;
begin
  if (Handle < HANDLE_TOPLEFT) or (Handle > HANDLE_LEFT) then
    Exit;
  inherited ResizeBy(Handle, R);          // the new rectangle, with the corners in their old order
  NewA := PointA;
  NewB := PointB;
  { the symbol's own size, with the scale at 1: ExtractSymbol puts PointB a native size from PointA }
  ScalingX := 1.0;
  ScalingY := 1.0;
  ExtractSymbol(Tr, Objs);
  DenX := Abs(PointA.x - PointB.x);
  DenY := Abs(PointA.y - PointB.y);
  if DenX > 0 then
    Nx := Abs((NewB.x - NewA.x) / DenX)
  else
    Nx := 1.0;      // (a symbol with no width or height cannot be scaled)
  if DenY > 0 then
    Ny := Abs((NewB.y - NewA.y) / DenY)
  else
    Ny := 1.0;
  if (Rotate and 3) >= 2 then
  begin
    Q := Nx; Nx := Ny; Ny := Q;
  end;
  ScalingX := Nx;
  ScalingY := Ny;
  PointA := NewA;
  PointB := NewB;
end;

{ ===========================================================================
  TDrawMethod.FieldAt  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Integer
  Notes:
    CDrawMethod::IsInsideField (the part for fields). A shown field is the box of its text: from
    the field's position, measured from the symbol's origin, to the right by the width of the
    text and up by its height (the text sits on the position). The first such field is the one.
    Fields that are not shown cannot be picked. (TinyCAD's same function also returns the
    scaling handles of a symbol that can be scaled; that is a separate feature, not done here.)
  =========================================================================== }
function TDrawMethod.FieldAt(const P: TDPoint): Integer;
var
  i: Integer;
  Q: TDPoint;
  Size: TDSize;
begin
  Result := -1;
  Q := DPoint(P.x - PointA.x, P.y - PointA.y);
  for i := 0 to High(Fields) do
  begin
    if Fields[i].Show = 0 then
      Continue;
    Size := FOpts.TextExtent(GetDecoratedField(i), fPIN);
    if (Q.x >= Fields[i].Position.x) and (Q.x <= Fields[i].Position.x + Size.cx) and
       (Q.y <= Fields[i].Position.y) and (Q.y >= Fields[i].Position.y - Size.cy) then
      Exit(FIELD_BASE + i);
  end;
end;

{ ===========================================================================
  TDrawMethod.MoveFieldBy  (procedure)
  Parameters:
    Field: Integer - whole number
    const R: TDPoint - the XML reader, positioned on this element
  Notes:
    CDrawMethod::MoveField for a field: its position, which is kept relative to the symbol's
    origin, changes by R. The symbol itself does not move, and the field keeps that place when
    the symbol is moved.
  =========================================================================== }
procedure TDrawMethod.MoveFieldBy(Field: Integer; const R: TDPoint);
var
  n: Integer;
begin
  n := Field - FIELD_BASE;
  if (n < 0) or (n > High(Fields)) then
    Exit;
  Fields[n].Position := DPoint(Fields[n].Position.x + R.x, Fields[n].Position.y + R.y);
end;

{ ===========================================================================
  TDrawingObject.Shift  (procedure)
  Parameters:
    const R: TDPoint - how far to move in x and y
  Notes:
    Moves the object by a vector (both points).
  =========================================================================== }
procedure TDrawingObject.Shift(const R: TDPoint);
begin
  PointA := PointAdd(PointA, R);
  PointB := PointAdd(PointB, R);
end;

{ ===========================================================================
  TDrawingObject.RotateAbout  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
    Dir: Integer - whole number
  Notes:
    Rotates or mirrors the object about the point P. NewDir is the rotation / mirror code (0 to
    7) used throughout TinyCAD.
  =========================================================================== }
procedure TDrawingObject.RotateAbout(const P: TDPoint; Dir: Integer);
begin
  PointA := RotatePointAbout(PointA, P, Dir);
  PointB := RotatePointAbout(PointB, P, Dir);
end;

{ ===========================================================================
  TDrawingObject.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawingObject.IsInside(Left, Right, Top, Bottom: Double): Boolean;
begin
  Result := not (((PointA.x < Left) and (PointB.x <= Left)) or
                 ((PointA.x > Right) and (PointB.x >= Right)) or
                 ((PointA.y < Top) and (PointB.y <= Top)) or
                 ((PointA.y > Bottom) and (PointB.y >= Bottom)));
end;

{ ===========================================================================
  TDrawingObject.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawingObject.DistanceFromPoint(const P: TDPoint): Double;
begin
  if IsInside(P.x, P.x, P.y, P.y) then
    Result := 0
  else
    Result := 100.0;
end;

{ ===========================================================================
  TDrawingObject.IsCompletelyInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if it is completely inside
  Notes:
    Whether the object's bounding box lies entirely inside a rectangle. A corner that has no value is
    replaced by the other one; an object with neither is never inside.
  =========================================================================== }
function TDrawingObject.IsCompletelyInside(Left, Right, Top, Bottom: Double): Boolean;
var
  A, B: TDPoint;
begin
  A := PointA;
  B := PointB;
  { an object with one corner not set (a point-like one) is judged by the corner it has; comparing "no value" would raise a floating point error }
  if not DPointHasValue(B) then
    B := A;
  if not DPointHasValue(A) then
    A := B;
  if not DPointHasValue(A) then
  begin
    Result := False;
    Exit;
  end;
  Result := (Left <= Min(A.x, B.x)) and (Right >= Max(B.x, A.x)) and
            (Top <= Min(A.y, B.y)) and (Bottom >= Max(B.y, A.y));
end;

{ ===========================================================================
  TDrawingObject.UpdateLayout  (procedure)
  Parameters:  none
  Notes:
    Recalculates geometry that depends on text sizes or on other data (text boxes, label and pin
    text positions) using the current text metrics.
  =========================================================================== }
procedure TDrawingObject.UpdateLayout;
begin
end;

{ ---- TDrawLine ---- }

{ ===========================================================================
  TDrawLine.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawLine.IsInside(Left, Right, Top, Bottom: Double): Boolean;
begin
  Result := LineIsInside(PointA, PointB, Left, Right, Top, Bottom);
end;

{ ===========================================================================
  TDrawLine.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawLine.DistanceFromPoint(const P: TDPoint): Double;
var
  D: TDPoint;
begin
  Result := LineDistance(PointA, PointB, P, D);
end;

{ ===========================================================================
  TDrawLine.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawLine (same geometry and properties). The copy has no
    object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawLine.Clone: TDrawingObject;
var
  O: TDrawLine;
begin
  O := TDrawLine.CreateKind(FOpts, Kind);
  CopyPoints(Self, O);
  O.UseDefaultStyle := UseDefaultStyle;
  O.Style := Style;
  O.Group := Group;
  O.Phase := Phase;
  O.Phases := Phases;
  O.PhaseSpacing := PhaseSpacing;
  Result := O;
end;

{ ---- TDrawPolygon ---- }

{ ===========================================================================
  TDrawPolygon.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawPolygon (same geometry and properties). The copy has
    no object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawPolygon.Clone: TDrawingObject;
var
  O: TDrawPolygon;
begin
  O := TDrawPolygon.Create(FOpts);
  CopyPoints(Self, O);
  O.Kind := Kind;
  O.Style := Style;
  O.Fill := Fill;
  O.Close := Close;
  O.Handles := Copy(Handles, 0, Length(Handles));
  O.Points := Copy(Points, 0, Length(Points));
  Result := O;
end;

{ ===========================================================================
  TDrawPolygon.HandleAt  (function)
  Parameters:
    const P: TDPoint - a point, in design units
    Tol: Double - number
  Returns:
    Integer
  Notes:
    Finds the handle (or the control point of a curve) under a point, as
    CDrawPolygon::IsInsideField does for its handles. The handles are tried in order, a handle
    before its own control point.
  =========================================================================== }
function TDrawPolygon.HandleAt(const P: TDPoint; Tol: Double): Integer;
var
  i: Integer;
  H: TDPoint;
begin
  Result := -1;
  for i := 0 to High(Handles) do
  begin
    H := DPoint(Handles[i].X + PointA.x, Handles[i].Y + PointA.y);
    if (Abs(P.x - H.x) <= Tol) and (Abs(P.y - H.y) <= Tol) then
    begin
      Result := 1000 + i;
      Exit;
    end;
    if Handles[i].Arc = Arc_control then
    begin
      H := DPoint(Handles[i].Control.x + PointA.x, Handles[i].Control.y + PointA.y);
      if (Abs(P.x - H.x) <= Tol) and (Abs(P.y - H.y) <= Tol) then
      begin
        Result := 5000 + i;
        Exit;
      end;
    end;
  end;
end;

{ ===========================================================================
  TDrawPolygon.MoveHandle  (procedure)
  Parameters:
    Code: Integer - whole number
    const R: TDPoint - the XML reader, positioned on this element
  Notes:
    Moves one handle, or one curve control point (CDrawPolygon::MoveField), and flattens the
    path again. The bounding box is worked out again too, which also makes the first handle the
    origin.
  =========================================================================== }
procedure TDrawPolygon.MoveHandle(Code: Integer; const R: TDPoint);
begin
  if Code >= 5000 then
  begin
    if Code - 5000 > High(Handles) then
      Exit;
    Handles[Code - 5000].Control := DPoint(Handles[Code - 5000].Control.x + R.x, Handles[Code - 5000].Control.y + R.y);
  end
  else if Code >= 1000 then
  begin
    if Code - 1000 > High(Handles) then
      Exit;
    Handles[Code - 1000].X := Handles[Code - 1000].X + R.x;
    Handles[Code - 1000].Y := Handles[Code - 1000].Y + R.y;
  end
  else
    Exit;
  CalcBoundingRect;
end;

{ ===========================================================================
  TDrawPolygon.ApplyAction  (function)
  Parameters:
    Action: TPolyAction
    const P: TDPoint - a point, in design units
    const SnapP: TDPoint - a point, in design units
  Returns:
    Boolean
  Notes:
    The polygon context menu (CDrawPolygon::ContextMenu). The nearest segment is found first;
    Free line, Arc in, Arc out and Curve set the kind of that segment (stored in the handle it
    ends at, so the first handle's segment cannot be changed); Curve also puts the control point
    at the click. Add handle splits the nearest segment at the click. Delete handle removes the
    nearest handle (a polygon keeps at least two) or, on a curve's control point, makes that
    segment straight.
  =========================================================================== }
function TDrawPolygon.ApplyAction(Action: TPolyAction; const P, SnapP: TDPoint): Boolean;
var
  Line, Handle, Hit, i: Integer;
  NewH: TArcPoint;
begin
  Result := False;
  if Length(Handles) = 0 then
    Exit;
  FindNearestSegment(P, Line, Handle);
  case Action of
    paArcIn, paArcOut, paFreeLine, paCurve:
      if (Line > 0) and (Line <= High(Handles)) then
      begin
        case Action of
          paArcIn: Handles[Line].Arc := Arc_in;
          paArcOut: Handles[Line].Arc := Arc_out;
          paFreeLine: Handles[Line].Arc := Arc_none;
          paCurve:
            begin
              Handles[Line].Arc := Arc_control;
              Handles[Line].Control := DPoint(SnapP.x - PointA.x, SnapP.y - PointA.y);
            end;
        end;
        Result := True;
      end;
    paDeleteHandle:
      begin
        Hit := HandleAt(P, 2);
        if Hit >= 5000 then
        begin
          Handles[Hit - 5000].Arc := Arc_none;     // over a control point: just make the segment straight
          Result := True;
        end
        else if (Length(Handles) > 2) and (Handle >= 0) and (Handle <= High(Handles)) then
        begin
          for i := Handle to High(Handles) - 1 do Handles[i] := Handles[i + 1];
          SetLength(Handles, Length(Handles) - 1);
          Result := True;
        end;
      end;
    paAddHandle:
      if (Line >= 0) and (Line <= Length(Handles)) then
      begin
        NewH.X := SnapP.x - PointA.x;
        NewH.Y := SnapP.y - PointA.y;
        NewH.Arc := Arc_none;
        NewH.Control := DPointInvalid;
        NewH.FlattenedSegment := 0;
        SetLength(Handles, Length(Handles) + 1);
        for i := High(Handles) downto Line + 1 do Handles[i] := Handles[i - 1];
        Handles[Line] := NewH;
        Result := True;
      end;
  end;
  if Result then
    CalcBoundingRect;
end;

{ ===========================================================================
  TDrawPolygon.IsInsidePolygon  (function)
  Parameters:
    const P: TDPoint - the point
  Returns:
    Boolean - True if the point is inside
  Notes:
    Point-in-polygon test using the flattened outline and a horizontal ray (even-odd rule).
  =========================================================================== }
function TDrawPolygon.IsInsidePolygon(const P: TDPoint): Boolean;
var
  i, Count: Integer;
  L1, L2: TDPoint;
  G, H, XInt: Double;
begin
  Result := False;
  if Length(Points) = 0 then
    Exit;
  Count := 0;
  { pre-load with the last point so the full round polygon is checked }
  L2 := PointAdd(Points[High(Points)], PointA);
  for i := 0 to High(Points) do
  begin
    L1 := L2;
    L2 := PointAdd(Points[i], PointA);
    if L1.y = L2.y then
      Continue; // horizontal lines are ignored
    if L1.x = L2.x then
    begin
      if (P.y < Min(L1.y, L2.y)) or (P.y > Max(L1.y, L2.y)) then
        Continue;
      XInt := L1.x;
    end
    else
    begin
      G := (L2.x - L1.x) / (L2.y - L1.y);
      H := L2.x - G * L2.y;
      { 0.5 is added so the test position can never lie on a vertex (their y is integral) }
      XInt := G * (P.y + 0.5) + H;
    end;
    if (XInt < Min(L1.x, L2.x)) or (XInt > Max(L1.x, L2.x)) then
      Continue;
    if XInt > P.x then
      Inc(Count);
  end;
  Result := (Count and 1) <> 0;
end;

{ ===========================================================================
  TDrawPolygon.IsInsideLine  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the outline touches it
  Notes:
    Whether any edge of the flattened outline touches a rectangle.
  =========================================================================== }
function TDrawPolygon.IsInsideLine(Left, Right, Top, Bottom: Double): Boolean;
var
  i: Integer;
  La, Np: TDPoint;
begin
  Result := False;
  La := DPoint(0, 0);
  for i := 0 to High(Points) do
  begin
    Np := PointAdd(Points[i], PointA);
    if i <> 0 then
      if LineIsInside(La, Np, Left, Right, Top, Bottom) then
      begin
        Result := True;
        Exit;
      end;
    La := Np;
  end;
end;

{ ===========================================================================
  TDrawPolygon.FindNearestSegment  (procedure)
  Parameters:
    const P: TDPoint - the point
    out Line: Integer - set to the nearest flattened line
    out Handle: Integer - set to the handle that line belongs to
  Notes:
    Finds which flattened line, and which handle, are nearest a point (used to insert a handle
    or pick a segment).
  =========================================================================== }
procedure TDrawPolygon.FindNearestSegment(const P: TDPoint; out Line, Handle: Integer);
var
  Distance, DistI: Double;
  S, H, i: Integer;
  La, Np, LocI: TDPoint;
begin
  Line := 0;
  Handle := 0;
  if Length(Points) = 0 then
    Exit;
  Distance := 1E10;
  S := 0;
  H := 0;
  { as in the C++ code, the starting point is the last flattened point truncated to
    integers, WITHOUT the polygon's origin added }
  La := DPoint(Trunc(Points[High(Points)].x), Trunc(Points[High(Points)].y));
  for i := 0 to High(Points) do
  begin
    Np := PointAdd(Points[i], PointA);
    DistI := LineDistance(La, Np, P, LocI);
    if DistI <= Distance then
    begin
      Distance := DistI;
      Line := H;
    end;
    Inc(S);
    if (H <= High(Handles)) and (S = Handles[H].FlattenedSegment) then
      Inc(H);
    La := Np;
  end;
  { now the nearest handle }
  Distance := 1E10;
  for i := 0 to High(Handles) do
  begin
    DistI := Sqr(Handles[i].X + PointA.x - P.x) + Sqr(Handles[i].Y + PointA.y - P.y);
    if DistI < Distance then
    begin
      Distance := DistI;
      Handle := i;
    end;
  end;
end;

{ ===========================================================================
  TDrawPolygon.RotateAbout  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
    Dir: Integer - whole number
  Notes:
    Rotates or mirrors the object about the point P. NewDir is the rotation / mirror code (0 to
    7) used throughout TinyCAD.
  =========================================================================== }
procedure TDrawPolygon.RotateAbout(const P: TDPoint; Dir: Integer);
var
  i: Integer;
  Q, Cp: TDPoint;
begin
  for i := 0 to High(Handles) do
  begin
    Q := DPoint(Handles[i].X + PointA.x - P.x, Handles[i].Y + PointA.y - P.y);
    case Dir of
      2: Q := DPoint(Q.y, -Q.x);
      3: Q := DPoint(-Q.y, Q.x);
      4: Q := DPoint(-Q.x, Q.y);
    end;
    if Handles[i].Arc = Arc_control then
    begin
      Cp := DPoint(Handles[i].Control.x + PointA.x - P.x, Handles[i].Control.y + PointA.y - P.y);
      case Dir of
        2: Cp := DPoint(Cp.y, -Cp.x);
        3: Cp := DPoint(-Cp.y, Cp.x);
        4: Cp := DPoint(-Cp.x, Cp.y);
      end;
      Handles[i].Control := DPoint(Cp.x + P.x - PointA.x, Cp.y + P.y - PointA.y);
    end;
    { rotating a quarter turn swaps in and out arcs (mirroring does not) }
    if (Dir = 2) or (Dir = 3) then
    begin
      if Handles[i].Arc = Arc_in then
        Handles[i].Arc := Arc_out
      else if Handles[i].Arc = Arc_out then
        Handles[i].Arc := Arc_in;
    end;
    { CArcPoint::operator= copies only x and y }
    Handles[i].X := Q.x + P.x - PointA.x;
    Handles[i].Y := Q.y + P.y - PointA.y;
  end;
  CalcBoundingRect;
end;

{ ===========================================================================
  TDrawPolygon.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawPolygon.DistanceFromPoint(const P: TDPoint): Double;
var
  Closest, Width: Double;
  i: Integer;
  La, Np, D: TDPoint;
begin
  { fast cut-off with a somewhat enlarged bounding box }
  if ((PointA.x < P.x - 10) and (PointB.x < P.x - 10)) or
     ((PointA.x > P.x + 10) and (PointB.x > P.x + 10)) or
     ((PointA.y < P.y - 10) and (PointB.y < P.y - 10)) or
     ((PointA.y > P.y + 10) and (PointB.y > P.y + 10)) then
  begin
    Result := 100.0;
    Exit;
  end;
  if (Fill <> fsNONE) and IsInsidePolygon(P) then
  begin
    Result := 0.0;
    Exit;
  end;
  Closest := 100.0;
  La := DPoint(0, 0);
  for i := 0 to High(Points) do
  begin
    Np := PointAdd(Points[i], PointA);
    if i <> 0 then
      Closest := Min(Closest, LineDistance(La, Np, P, D));
    La := Np;
  end;
  { for filled/closed polygons also the closing segment }
  if ((Fill <> fsNONE) or (Close <> 0)) and (Length(Points) > 2) then
  begin
    Np := PointAdd(Points[0], PointA);
    Closest := Min(Closest, LineDistance(La, Np, P, D));
  end;
  Width := Min(0, FOpts.LineThickness(Style));
  Result := Closest - Width;
end;

{ ===========================================================================
  TDrawPolygon.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawPolygon.IsInside(Left, Right, Top, Bottom: Double): Boolean;
var
  Width: Double;
begin
  Result := False;
  if ((PointA.x < Left) and (PointB.x <= Left)) or ((PointA.x > Right) and (PointB.x >= Right)) or
     ((PointA.y < Top) and (PointB.y <= Top)) or ((PointA.y > Bottom) and (PointB.y >= Bottom)) then
    Exit;
  if (Fill = fsNONE) and (Left = Right) and (Top = Bottom) then
  begin
    if (Length(Points) > 2) and (PointDistance(Points[0], Points[High(Points)]) < 0.5) and
       IsInsidePolygon(DPoint(Left, Top)) then
    begin
      Result := True;
      Exit;
    end;
    Width := Min(0, FOpts.LineThickness(Style)) + (10 / FOpts.ZoomFactor);
    Result := DistanceFromPoint(DPoint(Left, Top)) < Width;
    Exit;
  end;
  if IsInsideLine(Left, Right, Top, Bottom) then
  begin
    Result := True;
    Exit;
  end;
  { filled (or a point test): is any corner inside the polygon? (m_re_edit is UI state: false) }
  if (Fill <> fsNONE) or ((Left = Right) and (Top = Bottom)) then
    Result := IsInsidePolygon(DPoint(Left, Top)) or IsInsidePolygon(DPoint(Right, Top)) or
              IsInsidePolygon(DPoint(Right, Bottom)) or IsInsidePolygon(DPoint(Left, Bottom));
end;

{ ---- junction, no-connect, origin ---- }

{ ===========================================================================
  PointInRect  (function)
  Parameters:
    const P: TDPoint - the point
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if inside
  Notes:
    Whether a point is inside or on the edge of a rectangle given by its edges.
  =========================================================================== }
function PointInRect(const P: TDPoint; Left, Right, Top, Bottom: Double): Boolean;
begin
  Result := (P.x >= Left) and (P.x <= Right) and (P.y >= Top) and (P.y <= Bottom);
end;

{ ===========================================================================
  TDrawJunction.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawJunction.IsInside(Left, Right, Top, Bottom: Double): Boolean;
begin
  Result := PointInRect(PointA, Left, Right, Top, Bottom);
end;

{ ===========================================================================
  TDrawJunction.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawJunction.DistanceFromPoint(const P: TDPoint): Double;
var
  D: Double;
begin
  D := PointDistance(PointA, P);
  if D < JUNCTION_SIZE * 1.5 then
  begin
    { give very nearby objects (like wire ends) a chance to be selected }
    if D < JUNCTION_SIZE / 2 then
      D := 0.0
    else
      D := JUNCTION_SIZE / 2;
  end;
  Result := D;
end;

{ ===========================================================================
  TDrawJunction.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawJunction (same geometry and properties). The copy has
    no object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawJunction.Clone: TDrawingObject;
begin
  Result := TDrawJunction.Create(FOpts);
  CopyPoints(Self, Result);
end;

{ ===========================================================================
  TDrawNoConnect.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawNoConnect.IsInside(Left, Right, Top, Bottom: Double): Boolean;
begin
  Result := PointInRect(PointA, Left, Right, Top, Bottom);
end;

{ ===========================================================================
  TDrawNoConnect.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawNoConnect.DistanceFromPoint(const P: TDPoint): Double;
var
  D: Double;
begin
  D := PointDistance(P, PointA);
  if D < CONNECT_SIZE then
    Result := 0.0
  else
    Result := D;
end;

{ ===========================================================================
  TDrawNoConnect.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawNoConnect (same geometry and properties). The copy
    has no object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawNoConnect.Clone: TDrawingObject;
begin
  Result := TDrawNoConnect.Create(FOpts);
  CopyPoints(Self, Result);
end;

{ ===========================================================================
  TDrawOrigin.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawOrigin.IsInside(Left, Right, Top, Bottom: Double): Boolean;
begin
  Result := PointInRect(PointA, Left, Right, Top, Bottom);
end;

{ ===========================================================================
  TDrawOrigin.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawOrigin.DistanceFromPoint(const P: TDPoint): Double;
var
  D: Double;
begin
  if DPointHasValue(PointA) then
  begin
    D := PointDistance(P, PointA);
    if D < CONNECT_SIZE then
      Result := 0.0
    else
      Result := D;
  end
  else
    Result := 1E5;
end;

{ ===========================================================================
  TDrawOrigin.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawOrigin (same geometry and properties). The copy has
    no object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawOrigin.Clone: TDrawingObject;
begin
  Result := TDrawOrigin.Create(FOpts);
  CopyPoints(Self, Result);
end;

{ ---- bus slash ---- }

{ ===========================================================================
  TDrawBusSlash.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawBusSlash.IsInside(Left, Right, Top, Bottom: Double): Boolean;
begin
  Result := LineIsInside(PointA, PointB, Left, Right, Top, Bottom);
end;

{ ===========================================================================
  TDrawBusSlash.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawBusSlash.DistanceFromPoint(const P: TDPoint): Double;
var
  D: TDPoint;
begin
  Result := LineDistance(PointA, PointB, P, D);
end;

{ ===========================================================================
  TDrawBusSlash.RotateAbout  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
    NewDir: Integer - whole number
  Notes:
    Rotates or mirrors the object about the point P. NewDir is the rotation / mirror code (0 to
    7) used throughout TinyCAD.
  =========================================================================== }
procedure TDrawBusSlash.RotateAbout(const P: TDPoint; NewDir: Integer);
var
  A, B: TDPoint;
begin
  { rotate the bounding box only if there is a centre point }
  if not PointsClose(P, DPoint(0, 0)) then
  begin
    A := PointSub(PointA, P);
    B := PointSub(PointB, P);
    case NewDir of
      2: begin
           A := DPoint(A.y, -A.x);
           B := DPoint(B.y, -B.x);
           if Dir = 0 then
             A := PointAdd(A, DPoint(SLASH_SIZE, SLASH_SIZE));
         end;
      3: begin
           A := DPoint(-A.y, A.x);
           B := DPoint(-B.y, B.x);
           if Dir <> 0 then
             A := PointAdd(A, DPoint(SLASH_SIZE, -SLASH_SIZE));
         end;
      4: begin
           A := DPoint(-A.x, A.y);
           B := DPoint(-B.x, B.y);
           if Dir = 0 then
             A := PointAdd(A, DPoint(SLASH_SIZE, SLASH_SIZE))
           else
             A := PointAdd(A, DPoint(SLASH_SIZE, -SLASH_SIZE));
         end;
    end;
    PointA := PointAdd(A, P);
    PointB := PointAdd(B, P);
  end;
  if Dir <> 0 then
    Dir := 0
  else
    Dir := 1;
  { calculate layout }
  if Dir = 0 then
    PointB := DPoint(PointA.x - SLASH_SIZE, PointA.y + SLASH_SIZE)
  else
    PointB := DPoint(PointA.x - SLASH_SIZE, PointA.y - SLASH_SIZE);
end;

{ ===========================================================================
  TDrawBusSlash.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawBusSlash (same geometry and properties). The copy has
    no object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawBusSlash.Clone: TDrawingObject;
var
  O: TDrawBusSlash;
begin
  O := TDrawBusSlash.Create(FOpts);
  CopyPoints(Self, O);
  O.Dir := Dir;
  Result := O;
end;

{ ---- rectangle / ellipse ---- }

{ ===========================================================================
  TDrawSquare.EllipseDistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - the point
    out Inside: Boolean - set True when the point is inside the ellipse
  Returns:
    Double - the distance to the edge
  Notes:
    Distance from a point to the edge of the ellipse, found by mapping the ellipse onto a unit
    circle.
  =========================================================================== }
function TDrawSquare.EllipseDistanceFromPoint(const P: TDPoint; out Inside: Boolean): Double;
var
  C: TDPoint;
  Da, Db, D: Double;
begin
  { distance of the point to the edge of the ellipse: map the ellipse onto the unit circle }
  C := DPoint((PointA.x + PointB.x) / 2, (PointA.y + PointB.y) / 2);
  Da := Abs(PointA.x - PointB.x) / 2;
  Db := Abs(PointA.y - PointB.y) / 2;
  if (Da = 0) or (Db = 0) then
  begin
    { DEVIATION from the C++ code: a zero-width or zero-height ellipse (a dot or a line drawn as
      an ellipse, which does occur in libraries) divides by zero there and yields NaN, so it could
      never be hit. Treat it as the point or line segment it really is. }
    D := LineDistance(PointA, PointB, P, C);
    Inside := D < 1E-9;
    Result := D;
    Exit;
  end;
  C := DPoint((C.x - P.x) / Da, (C.y - P.y) / Db);
  D := Sqrt(C.x * C.x + C.y * C.y);
  Inside := D <= 1.0;
  Result := Abs(D - 1.0) * Sqrt(Da * Da + Db * Db);
end;

{ ===========================================================================
  TDrawSquare.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawSquare.DistanceFromPoint(const P: TDPoint): Double;
var
  Distance, Width: Double;
  D: TDPoint;
  Inside: Boolean;
begin
  if IsSquare then
  begin
    if (Fill <> fsNONE) and IsInside(P.x, P.x, P.y, P.y) then
    begin
      Result := 0.0;
      Exit;
    end;
    Distance := 100.0;
    Distance := Min(Distance, LineDistance(DPoint(PointA.x, PointA.y), DPoint(PointB.x, PointA.y), P, D));
    Distance := Min(Distance, LineDistance(DPoint(PointB.x, PointA.y), DPoint(PointB.x, PointB.y), P, D));
    Distance := Min(Distance, LineDistance(DPoint(PointB.x, PointB.y), DPoint(PointA.x, PointB.y), P, D));
    Distance := Min(Distance, LineDistance(DPoint(PointA.x, PointB.y), DPoint(PointA.x, PointA.y), P, D));
    Width := Min(0, FOpts.LineThickness(Style));
    Result := Distance - Width;
  end
  else
  begin
    Distance := EllipseDistanceFromPoint(P, Inside);
    if Inside and (Fill <> fsNONE) then
    begin
      Result := 0.0;
      Exit;
    end;
    Width := Min(0, FOpts.LineThickness(Style));
    Result := Distance - Width;
  end;
end;

{ ===========================================================================
  TDrawSquare.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawSquare.IsInside(Left, Right, Top, Bottom: Double): Boolean;
var
  R: TDRect;
  C, P1, P2, P3, P4: TDPoint;
  I1, I2, I3, I4: Boolean;
begin
  Result := False;
  if ((PointA.x < Left) and (PointB.x <= Left)) or ((PointA.x > Right) and (PointB.x >= Right)) or
     ((PointA.y < Top) and (PointB.y <= Top)) or ((PointA.y > Bottom) and (PointB.y >= Bottom)) then
    Exit;
  if IsSquare then
  begin
    if (Fill <> fsNONE) or ((Left = Right) and (Top = Bottom)) then
    begin
      Result := True; // filled rectangle
      Exit;
    end;
    Result := LineIsInside(DPoint(PointA.x, PointA.y), DPoint(PointB.x, PointA.y), Left, Right, Top, Bottom) or
              LineIsInside(DPoint(PointB.x, PointA.y), DPoint(PointB.x, PointB.y), Left, Right, Top, Bottom) or
              LineIsInside(DPoint(PointB.x, PointB.y), DPoint(PointA.x, PointB.y), Left, Right, Top, Bottom) or
              LineIsInside(DPoint(PointA.x, PointB.y), DPoint(PointA.x, PointA.y), Left, Right, Top, Bottom);
  end
  else
  begin
    { is the ellipse entirely inside the rectangle? }
    R := DRectNormalized(DRect(PointA.x, PointA.y, PointB.x, PointB.y));
    if (R.Left >= Left) and (R.Right <= Right) and (R.Top >= Top) and (R.Bottom <= Bottom) then
    begin
      Result := True;
      Exit;
    end;
    { does one of the rectangle's edges cut the ellipse? take the point of each edge nearest
      to the centre and see whether it is inside }
    C := DPoint((PointA.x + PointB.x) / 2, (PointA.y + PointB.y) / 2);
    LineDistance(DPoint(Left, Top), DPoint(Right, Top), C, P1);
    LineDistance(DPoint(Right, Top), DPoint(Right, Bottom), C, P2);
    LineDistance(DPoint(Right, Bottom), DPoint(Left, Bottom), C, P3);
    LineDistance(DPoint(Left, Bottom), DPoint(Left, Top), C, P4);
    EllipseDistanceFromPoint(P1, I1);
    EllipseDistanceFromPoint(P2, I2);
    EllipseDistanceFromPoint(P3, I3);
    EllipseDistanceFromPoint(P4, I4);
    Result := I1 or I2 or I3 or I4;
  end;
end;

{ ===========================================================================
  TDrawMetaFile.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawMetaFile that belongs to the sheet whose options are AOpts, and gives its
    properties their default values.
  =========================================================================== }
constructor TDrawMetaFile.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  Image := -1;
  Orient := OrientIdentity;
  PointA := DPoint(30, 30);
  PointB := DPoint(130, 130);
end;

{ ===========================================================================
  TDrawMetaFile.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xMetaFile
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawMetaFile.GetType: TObjType;
begin
  Result := xMetaFile;
end;

{ ===========================================================================
  TDrawMetaFile.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawMetaFile.TagResources;
begin
  FOpts.Images.Tag(Image);
end;

{ ===========================================================================
  TDrawMetaFile.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawMetaFile as an XML <METAFILE> element using W: opens the tag, adds its
    attributes (and any child elements), then closes it. Only non-default content that the file
    format knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawMetaFile.SaveXML(W: TXMLWriter);
var
  Turns: Integer;
  FlipFirst: Boolean;
begin
  BeginTag(W, 'METAFILE');
  W.AddAttribute('a', PointA);
  W.AddAttribute('b', PointB);
  W.AddAttribute('id', Image);
  { only when it is not upright: a picture that has not been turned is written exactly as TinyCAD writes it, and TinyCAD skips these two when it reads one that has }
  if OrientToTurns(Orient, Turns, FlipFirst) and (not OrientIsIdentity(Orient)) then
  begin
    if Turns <> 0 then
      W.AddAttribute('rot', Turns);
    if FlipFirst then
      W.AddAttribute('mirror', 1);
  end;
  W.CloseTag;
end;

{ ===========================================================================
  TDrawMetaFile.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawMetaFile from the XML element R is positioned on. An attribute that is
    missing leaves the default value set by the constructor. Resource numbers (fonts, line
    styles, fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawMetaFile.LoadXML(R: TXMLReader);
var
  Turns, Mirror: Integer;
begin
  R.GetAttribute('a', PointA);
  R.GetAttribute('b', PointB);
  R.GetAttribute('id', Image);
  Image := FOpts.Images.ConvertOld(Image);       // the file's number for the picture becomes this design's
  { which way up it is: optional, upright when the file says nothing (TinyCAD's files never do) }
  Turns := 0;
  Mirror := 0;
  R.GetAttribute('rot', Turns);
  R.GetAttribute('mirror', Mirror);
  Orient := OrientFromTurns(Turns, Mirror <> 0);
end;

{ ===========================================================================
  TDrawMetaFile.FitToPicture  (procedure)
  Parameters:
    PixelWidth: Integer - whole number
    PixelHeight: Integer - whole number
  Notes:
    Gives the object the size a new picture gets (CDrawMetaFile::determineSize): its corner A
    stays, and B is a unit for each pixel to the right and below, scaled down so that neither
    side is more than 500.
  =========================================================================== }
procedure TDrawMetaFile.FitToPicture(PixelWidth, PixelHeight: Integer);
var
  Cx, Cy: Integer;
begin
  FitPictureSize(PixelWidth, PixelHeight, Cx, Cy);
  PointB := DPoint(PointA.x + Cx, PointA.y + Cy);
end;

{ ===========================================================================
  TDrawMetaFile.RotateAbout  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
    Dir: Integer - whole number
  Notes:
    Rotates or mirrors the object about the point P. NewDir is the rotation / mirror code (0 to
    7) used throughout TinyCAD.
  =========================================================================== }
procedure TDrawMetaFile.RotateAbout(const P: TDPoint; Dir: Integer);
begin
  inherited RotateAbout(P, Dir);
  Orient := OrientMul(OrientOfOp(Dir), Orient);
end;

{ ===========================================================================
  TDrawMetaFile.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawMetaFile (same geometry and properties). The copy has
    no object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawMetaFile.Clone: TDrawingObject;
var
  O: TDrawMetaFile;
begin
  O := TDrawMetaFile.Create(FOpts);
  CopyPoints(Self, O);
  O.Image := Image;
  O.Orient := Orient;
  Result := O;
end;

{ ===========================================================================
  TDrawSquare.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawSquare (same geometry and properties). The copy has
    no object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawSquare.Clone: TDrawingObject;
var
  O: TDrawSquare;
begin
  O := TDrawSquare.CreateKind(FOpts, Kind);
  CopyPoints(Self, O);
  O.Style := Style;
  O.Fill := Fill;
  Result := O;
end;

{ ---- text ---- }

{ ===========================================================================
  TDrawingObject.PrepareResize  (procedure)
  Parameters:  none
  Notes:
    Nothing to note for most objects.
  =========================================================================== }
procedure TDrawingObject.PrepareResize;
begin
end;

{ ===========================================================================
  TDrawText.SetScalingWidths  (procedure)
  Parameters:  none
  Notes:
    CDrawText::SetScalingWidths: notes the length of the text's box (from A to B, along the line
    of the text) as the length it started with and the one it is being dragged to, and the width
    of the font's characters. Resizing then changes the font in proportion to these.
  =========================================================================== }
procedure TDrawText.SetScalingWidths;
begin
  if Dir >= 2 then
    OriginalBoxWidth := Abs(PointB.x - PointA.x)
  else
    OriginalBoxWidth := -Abs(PointB.y - PointA.y);
  TargetBoxWidth := OriginalBoxWidth;
  OriginalWidth := FOpts.GetFontWidth(FontStyle);
end;

{ ===========================================================================
  TDrawText.PrepareResize  (procedure)
  Parameters:  none
  Notes:
    Called when this text becomes the one selected object: notes the length of its box and the
    width of its font (SetScalingWidths), which is what resizing it with its handles works from.
  =========================================================================== }
procedure TDrawText.PrepareResize;
begin
  SetScalingWidths;
end;

{ ===========================================================================
  TDrawText.CanResize  (function)
  Parameters:  none
  Returns:
    Boolean - True
  Notes:
    Yes: a text has the eight handles of the tracker when it is the one selected object (a label
    has none on its middle).
  =========================================================================== }
function TDrawText.CanResize: Boolean;
begin
  Result := True;
end;

{ ===========================================================================
  TDrawText.ResizeBy  (procedure)
  Parameters:
    Handle: Integer - whole number
    const R: TDPoint - the XML reader, positioned on this element
  Notes:
    CDrawText::MoveField. The box is taken from the text's corners (and, along the line of the
    text, the length it is being dragged to), the handle moves its side or corner, and the
    text's position becomes the box's bottom-left (bottom-right for text that reads upwards). A
    text is resized by changing its font, not by stretching it: the height changes by the
    movement across the line of the text (in the sense that dragging the box bigger makes the
    characters bigger), and, if the font has a width of its own, the width in proportion to the
    length the box has been dragged to. The box itself is then worked out again from the new
    font when the text is laid out.
  =========================================================================== }
procedure TDrawText.ResizeBy(Handle: Integer; const R: TDPoint);
var
  L, T, Rt, B, Delta: Double;
  Rr: TDPoint;
begin
  if (Handle < HANDLE_TOPLEFT) or (Handle > HANDLE_LEFT) then
    Exit;
  Rr := R;
  if Dir >= 2 then
  begin
    if Dir = 3 then
      L := PointA.x
    else
      L := PointA.x - TargetBoxWidth;
    T := Min(PointA.y, PointB.y); Rt := L + TargetBoxWidth; B := Max(PointA.y, PointB.y);
  end
  else
  begin
    L := Min(PointA.x, PointB.x); Rt := Max(PointA.x, PointB.x);
    if Dir = 0 then begin
      T := PointA.y + TargetBoxWidth;
      B := PointA.y;
    end
    else begin
      T := PointA.y;
      B := PointA.y - TargetBoxWidth;
    end;
  end;
  case Handle of
    HANDLE_TOPLEFT:     begin
      L := L + R.x;
      T := T + R.y;
      Rr.y := -Rr.y;
    end;
    HANDLE_TOPRIGHT:    begin
      Rt := Rt + R.x;
      T := T + R.y;
      Rr.y := -Rr.y;
      Rr.x := -Rr.x;
    end;
    HANDLE_BOTTOMRIGHT: begin
      Rt := Rt + R.x;
      B := B + R.y;
      Rr.x := -Rr.x;
    end;
    HANDLE_BOTTOMLEFT:  begin
      L := L + R.x;
      B := B + R.y;
    end;
    HANDLE_TOP:         begin
      T := T + R.y;
      Rr.y := -Rr.y;
    end;
    HANDLE_RIGHT:       begin
      Rt := Rt + R.x;
      Rr.x := -Rr.x;
    end;
    HANDLE_BOTTOM:      B := B + R.y;
    HANDLE_LEFT:        L := L + R.x;
  end;
  if Dir >= 2 then
  begin
    if Dir = 3 then begin
      PointA := DPoint(L, B);
      PointB := DPoint(Rt, T);
    end
    else begin
      PointA := DPoint(Rt, B);
      PointB := DPoint(L, T);
    end;
    TargetBoxWidth := Rt - L;
  end
  else
  begin
    if Dir = 0 then begin
      PointB := DPoint(L, T);
      PointA := DPoint(Rt, B);
    end
    else begin
      PointA := DPoint(Rt, T);
      PointB := DPoint(L, B);
    end;
    TargetBoxWidth := -(B - T);
  end;
  if OriginalBoxWidth > 0 then
  begin
    if Dir < 2 then
      Delta := Rr.x
    else
      Delta := -Rr.y;
    FontStyle := FOpts.ChangeFontSize(FontStyle, Delta, (OriginalWidth * TargetBoxWidth) / OriginalBoxWidth);
  end;
end;

{ ===========================================================================
  TDrawLabel.SetScalingWidths  (procedure)
  Parameters:  none
  Notes:
    As for a text (CDrawLabel::SetScalingWidths).
  =========================================================================== }
procedure TDrawLabel.SetScalingWidths;
begin
  if Dir >= 2 then
    OriginalBoxWidth := PointB.x - PointA.x
  else
    OriginalBoxWidth := PointB.y - PointA.y;
  TargetBoxWidth := OriginalBoxWidth;
  OriginalWidth := FOpts.GetFontWidth(FontStyle);
end;

{ ===========================================================================
  TDrawLabel.PrepareResize  (procedure)
  Parameters:  none
  Notes:
    Called when this label becomes the one selected object: notes the length of its box and the
    width of its font (SetScalingWidths), which is what resizing it with its handles works from.
  =========================================================================== }
procedure TDrawLabel.PrepareResize;
begin
  SetScalingWidths;
end;

{ ===========================================================================
  TDrawLabel.CanResize  (function)
  Parameters:  none
  Returns:
    Boolean - True
  Notes:
    Yes: a label has the eight handles of the tracker when it is the one selected object (a
    label has none on its middle).
  =========================================================================== }
function TDrawLabel.CanResize: Boolean;
begin
  Result := True;
end;

{ ===========================================================================
  TDrawLabel.ResizeBy  (procedure)
  Parameters:
    Handle: Integer - whole number
    const R: TDPoint - the XML reader, positioned on this element
  Notes:
    CDrawLabel::MoveField: the same as for a text, except that what moves is the label's
    connection point (and only for a normal label, not an input, output or bidirectional one,
    whose connection point stays), and the layout is worked out again at once. A label has no
    handle on its middle to drag it by.
  =========================================================================== }
procedure TDrawLabel.ResizeBy(Handle: Integer; const R: TDPoint);
var
  L, T, Rt, B, Delta: Double;
  Rr: TDPoint;
begin
  if (Handle < HANDLE_TOPLEFT) or (Handle > HANDLE_LEFT) then
    Exit;
  Rr := R;
  if Dir >= 2 then begin
    L := PointA.x;
    T := PointB.y;
    Rt := PointA.x + TargetBoxWidth;
    B := PointA.y;
  end
  else begin
    L := PointB.x;
    T := PointA.y + TargetBoxWidth;
    Rt := PointA.x;
    B := PointA.y;
  end;
  case Handle of
    HANDLE_TOPLEFT:     begin
      L := L + R.x;
      T := T + R.y;
      Rr.y := -Rr.y;
    end;
    HANDLE_TOPRIGHT:    begin
      Rt := Rt + R.x;
      T := T + R.y;
      Rr.y := -Rr.y;
      Rr.x := -Rr.x;
    end;
    HANDLE_BOTTOMRIGHT: begin
      Rt := Rt + R.x;
      B := B + R.y;
      Rr.x := -Rr.x;
    end;
    HANDLE_BOTTOMLEFT:  begin
      L := L + R.x;
      B := B + R.y;
    end;
    HANDLE_TOP:         begin
      T := T + R.y;
      Rr.y := -Rr.y;
    end;
    HANDLE_RIGHT:       begin
      Rt := Rt + R.x;
      Rr.x := -Rr.x;
    end;
    HANDLE_BOTTOM:      B := B + R.y;
    HANDLE_LEFT:        L := L + R.x;
  end;
  if LabelStyle = label_normal then
  begin
    if Dir >= 2 then
      ActivePoint := DPoint(L, B)
    else
      ActivePoint := DPoint(Rt, B);
  end;
  if Dir >= 2 then
    TargetBoxWidth := Rt - L
  else
    TargetBoxWidth := -(B - T);
  if OriginalBoxWidth > 0 then
  begin
    if Dir < 2 then
      Delta := Rr.x
    else
      Delta := -Rr.y;
    FontStyle := FOpts.ChangeFontSize(FontStyle, Delta, (OriginalWidth * TargetBoxWidth) / OriginalBoxWidth);
  end;
  UpdateLayout;
end;

{ ===========================================================================
  TDrawText.UpdateLayout  (procedure)
  Parameters:  none
  Notes:
    Recalculates geometry that depends on text sizes or on other data (text boxes, label and pin
    text positions) using the current text metrics.
  =========================================================================== }
procedure TDrawText.UpdateLayout;
var
  Size: TDSize;
begin
  Size := FOpts.TextExtent(Str, FontStyle);
  { PointA is the attachment corner, where the text starts (ends, for Left) }
  case Dir of
    0: PointB := DPoint(PointA.x - Size.cy, PointA.y - Size.cx);   // up: reads upwards from A
    1: PointB := DPoint(PointA.x - Size.cy, PointA.y + Size.cx);   // down: reads downwards from A
    2: PointB := DPoint(PointA.x - Size.cx, PointA.y - Size.cy);   // left: ends at A
  else
    PointB := DPoint(PointA.x + Size.cx, PointA.y - Size.cy);      // right: starts at A
  end;
  { as CDrawText::Paint does after its layout: a text that has no widths yet (or whose font has no width of its own) notes them now }
  if OriginalWidth = 0 then
    SetScalingWidths;
end;

{ ===========================================================================
  TDrawText.RotateAbout  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
    NewDir: Integer - whole number
  Notes:
    Rotates or mirrors the object about the point P. NewDir is the rotation / mirror code (0 to
    7) used throughout TinyCAD.
  =========================================================================== }
procedure TDrawText.RotateAbout(const P: TDPoint; NewDir: Integer);
var
  La, A, B: TDPoint;
begin
  if NewDir <> 4 then
  begin
    if Dir >= 2 then
      Dir := 0
    else
      Dir := 3;
  end;
  if not PointsClose(P, DPoint(0, 0)) then
  begin
    A := PointSub(PointA, P);
    B := PointSub(PointB, P);
    case NewDir of
      2: begin
        A := DPoint(A.y, -A.x);
        B := DPoint(B.y, -B.x);
      end;
      3: begin
        A := DPoint(-A.y, A.x);
        B := DPoint(-B.y, B.x);
      end;
      4: begin
        A := DPoint(-A.x, A.y);
        B := DPoint(-B.x, B.y);
      end;
    end;
    A := PointAdd(A, P);
    B := PointAdd(B, P);
    La := A;
    { adjust for the rotation: the attachment corner depends on the direction }
    case Dir of
      0, 2: begin
              PointA := DPoint(Max(La.x, B.x), Max(La.y, B.y));
              PointB := DPoint(Min(La.x, B.x), Min(La.y, B.y));
            end;
      1:    begin
              PointA := DPoint(Max(La.x, B.x), Min(La.y, B.y));
              PointB := DPoint(Min(La.x, B.x), Max(La.y, B.y));
            end;
    else
      PointA := DPoint(Min(La.x, B.x), Max(La.y, B.y));
      PointB := DPoint(Max(La.x, B.x), Min(La.y, B.y));
    end;
  end;
  UpdateLayout;
end;

{ ===========================================================================
  TDrawText.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawText (same geometry and properties). The copy has no
    object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawText.Clone: TDrawingObject;
var
  O: TDrawText;
begin
  O := TDrawText.CreateKind(FOpts, Kind);
  CopyPoints(Self, O);
  O.FontStyle := FontStyle;
  O.FontColor := FontColor;
  O.Str := Str;
  O.Dir := Dir;
  Result := O;
end;

{ ---- label ---- }

{ ===========================================================================
  TDrawLabel.Shift  (procedure)
  Parameters:
    const R: TDPoint - the XML reader, positioned on this element
  Notes:
    Moves a label (CDrawLabel::Shift). Besides its text box (which the layout works out from it)
    the label's connection point, the place on the wire where it is attached and what is saved
    as its position, has to move, and then the layout is worked out again. Without this the box
    moved but the connection point stayed, so a moved, dragged, pasted or imported label went
    back to where it had been.
  =========================================================================== }
procedure TDrawLabel.Shift(const R: TDPoint);
begin
  inherited Shift(R);
  ActivePoint := PointAdd(ActivePoint, R);
  UpdateLayout;
end;

{ ===========================================================================
  TDrawLabel.UpdateLayout  (procedure)
  Parameters:  none
  Notes:
    Recalculates geometry that depends on text sizes or on other data (text boxes, label and pin
    text positions) using the current text metrics.
  =========================================================================== }
procedure TDrawLabel.UpdateLayout;
var
  Size: TDSize;
  Spacing, ArrowDistance, ExtraWidth: Double;
begin
  Size := FOpts.TextExtent(Str, FontStyle);
  if LabelStyle <> label_normal then
  begin
    { the surrounding lines of input and output labels }
    Spacing := Size.cy / 5;
    ArrowDistance := Size.cy;
    ExtraWidth := 0;
    case LabelStyle of
      label_in, label_out: ExtraWidth := ExtraWidth + ArrowDistance + Spacing;
      label_io: ExtraWidth := ExtraWidth + ArrowDistance * 2;
    end;
    case Dir of
      0: begin
           PointA := DPoint(ActivePoint.x + Size.cy / 2, ActivePoint.y + Size.cx + ExtraWidth);
           PointB := DPoint(PointA.x - Size.cy, PointA.y - Size.cx - ExtraWidth);
         end;
      1: begin
           PointA := DPoint(ActivePoint.x + Size.cy / 2, ActivePoint.y - Size.cx - ExtraWidth);
           PointB := DPoint(PointA.x - Size.cy, PointA.y + Size.cx + ExtraWidth);
         end;
      2: begin
           PointA := DPoint(ActivePoint.x, ActivePoint.y + Size.cy / 2);
           PointB := DPoint(PointA.x + Size.cx + ExtraWidth, ActivePoint.y - Size.cy / 2);
         end;
      3: begin
           PointA := DPoint(ActivePoint.x - Size.cx - ExtraWidth, ActivePoint.y + Size.cy / 2);
           PointB := DPoint(PointA.x + Size.cx + ExtraWidth, ActivePoint.y - Size.cy / 2);
         end;
    end;
  end
  else
  begin
    PointA := ActivePoint;
    case Dir of
      0: PointB := DPoint(PointA.x - Size.cy, PointA.y - Size.cx);
      1: PointB := DPoint(PointA.x - Size.cy, PointA.y + Size.cx);
      2: PointB := DPoint(PointA.x - Size.cx, PointA.y - Size.cy);
      3: PointB := DPoint(PointA.x + Size.cx, PointA.y - Size.cy);
    end;
  end;
  if OriginalWidth = 0 then
    SetScalingWidths;
end;

{ ===========================================================================
  TDrawLabel.RotateAbout  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
    NewDir: Integer - whole number
  Notes:
    Rotates or mirrors the object about the point P. NewDir is the rotation / mirror code (0 to
    7) used throughout TinyCAD.
  =========================================================================== }
procedure TDrawLabel.RotateAbout(const P: TDPoint; NewDir: Integer);
begin
  if not PointsClose(P, DPoint(0, 0)) then
    ActivePoint := RotatePointAbout(ActivePoint, P, NewDir);
  Dir := DoRotateDir(Dir, NewDir);
  UpdateLayout;
end;

{ ===========================================================================
  TDrawLabel.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawLabel (same geometry and properties). The copy has no
    object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawLabel.Clone: TDrawingObject;
var
  O: TDrawLabel;
begin
  O := TDrawLabel.Create(FOpts);
  CopyPoints(Self, O);
  O.FontStyle := FontStyle;
  O.FontColor := FontColor;
  O.LabelStyle := LabelStyle;
  O.ActivePoint := ActivePoint;
  O.Str := Str;
  O.Dir := Dir;
  Result := O;
end;

{ ---- power ---- }

{ ===========================================================================
  TDrawPower.UpdateLayout  (procedure)
  Parameters:  none
  Notes:
    Recalculates geometry that depends on text sizes or on other data (text boxes, label and pin
    text positions) using the current text metrics.
  =========================================================================== }
procedure TDrawPower.UpdateLayout;
var
  Spacing: Integer;
  Size: TDSize;
begin
  Size := FOpts.TextExtent(Str, fPIN);
  if Which <> 0 then
    Spacing := POWER_SIZE * 2 + POWER_SIZE div 4
  else
    Spacing := POWER_SIZE + POWER_SIZE div 4;
  case Dir of
    0: TextPos := DPoint(PointA.x - Size.cx / 2, PointA.y - Spacing);
    1: TextPos := DPoint(PointA.x - Size.cx / 2, PointA.y + Spacing + Size.cy);
    2: TextPos := DPoint(PointA.x - Size.cx - Spacing, PointA.y + Size.cy / 2);
    3: TextPos := DPoint(PointA.x + Spacing, PointA.y + Size.cy / 2);
  end;
  TextEnd := DPoint(TextPos.x + Size.cx, TextPos.y - Size.cy);
end;

{ ===========================================================================
  PowerStemEnd  (function)
  Parameters:
    Obj: TDrawPower - the power symbol
  Returns:
    TDPoint - the end of the stem
  Notes:
    Where a power symbol's stem ends (a fixed length from its connection point in its
    direction).
  =========================================================================== }
function PowerStemEnd(Obj: TDrawPower): TDPoint;
begin
  Result := Obj.PointA;
  case Obj.Dir of
    0: Result := DPoint(Obj.PointA.x, Obj.PointA.y - POWER_SIZE);
    1: Result := DPoint(Obj.PointA.x, Obj.PointA.y + POWER_SIZE);
    2: Result := DPoint(Obj.PointA.x - POWER_SIZE, Obj.PointA.y);
    3: Result := DPoint(Obj.PointA.x + POWER_SIZE, Obj.PointA.y);
  end;
end;

{ ===========================================================================
  TDrawPower.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawPower.DistanceFromPoint(const P: TDPoint): Double;
var
  D: TDPoint;
begin
  if (P.x > TextPos.x) and (P.x < TextEnd.x) and (P.y > TextEnd.y) and (P.y < TextPos.y) then
  begin
    Result := 0.0;
    Exit;
  end;
  Result := LineDistance(PointA, PowerStemEnd(Self), P, D);
end;

{ ===========================================================================
  TDrawPower.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawPower.IsInside(Left, Right, Top, Bottom: Double): Boolean;
var
  D, Range: Double;
begin
  if (Left = Right) and (Top = Bottom) then
  begin
    D := DistanceFromPoint(DPoint(Left, Top));
    Range := 10 / FOpts.ZoomFactor;
    Result := D < Range;
    Exit;
  end;
  Result := (not (((TextPos.x < Left) and (TextEnd.x <= Left)) or
                  ((TextPos.x > Right) and (TextEnd.x >= Right)) or
                  ((TextPos.y < Top) and (TextEnd.y <= Top)) or
                  ((TextPos.y > Bottom) and (TextEnd.y >= Bottom)))) or
            LineIsInside(PointA, PowerStemEnd(Self), Left, Right, Top, Bottom);
end;

{ ===========================================================================
  TDrawPower.RotateAbout  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
    NewDir: Integer - whole number
  Notes:
    Rotates or mirrors the object about the point P. NewDir is the rotation / mirror code (0 to
    7) used throughout TinyCAD.
  =========================================================================== }
procedure TDrawPower.RotateAbout(const P: TDPoint; NewDir: Integer);
begin
  if not PointsClose(P, DPoint(0, 0)) then
  begin
    PointA := RotatePointAbout(PointA, P, NewDir);
    PointB := RotatePointAbout(PointB, P, NewDir);
  end;
  Dir := DoRotateDir(Dir, NewDir);
  UpdateLayout;
end;

{ ===========================================================================
  TDrawPower.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawPower (same geometry and properties). The copy has no
    object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawPower.Clone: TDrawingObject;
var
  O: TDrawPower;
begin
  O := TDrawPower.Create(FOpts);
  CopyPoints(Self, O);
  O.Which := Which;
  O.Dir := Dir;
  O.Str := Str;
  O.TextPos := TextPos;
  O.TextEnd := TextEnd;
  Result := O;
end;

{ ---- pin ---- }

{ ===========================================================================
  TDrawPin.IsInvisible  (function)
  Parameters:  none
  Returns:
    Boolean - True if not shown
  Notes:
    Whether the pin is hidden: when editing a library symbol, pins of other parts; on a drawing,
    power pins.
  =========================================================================== }
function TDrawPin.IsInvisible: Boolean;
begin
  if FOpts.EditLibrary then
    { editing a library symbol: only the pins of the part being edited are shown }
    Result := Part <> FOpts.EditPart
  else
    { on a normal drawing power pins are not shown }
    Result := IsPower;
end;

{ ===========================================================================
  TDrawPin.DetermineLayout  (function)
  Parameters:
    RotMir: Integer - rotation / mirror state 0-7
  Returns:
    TPinLayout - the layout
  Notes:
    Works out where the pin's line, dot, clock mark, name and number go for a rotation / mirror
    state (a transcription of TinyCAD's pin layout code).
  =========================================================================== }
function TDrawPin.DetermineLayout(RotMir: Integer): TPinLayout;
var
  Sizing, DotSize, LineSize, TextSpace, Spacing: Integer;
  X, Y: Double;
  Size: TDSize;
begin
  { SIZING / DOT_SIZE / LINE_SIZE / TEXT_SPACE are integer expressions in the C++ code }
  if Length <= 20 then
    Sizing := 20
  else
    Sizing := 30;
  DotSize := Sizing div 6;
  LineSize := Length - DotSize * 2;
  TextSpace := Sizing div 8;
  X := PointA.x;
  Y := PointA.y;
  Result.Dr := 3;
  if (Which and 2) = 0 then
    Spacing := Length + TextSpace
  else
    Spacing := Length + (DotSize * 2) + TextSpace;
  Size := DSize(0, 0);
  Result.Pta := DPoint(0, 0);
  Result.Ptb := DPoint(0, 0);

  case Dir of
    0: begin // up
         Result.Pa := DPoint(X, Y - LineSize);
         Result.Pb := DPoint(X - DotSize, Y - Length);
         Result.Pc := DPoint(X + DotSize + 1, Y - Length);
         Result.Pd := DPoint(X, Y - Length);
         Size := FOpts.TextExtent(Str, fPIN);
         if CentreName <> 0 then
           Result.Pta := DPoint(X + Size.cy, Y - (Length - Size.cx) / 2)
         else
           Result.Pta := DPoint(X + Size.cy / 2, Y - Spacing);
         Size := FOpts.TextExtent(Str, fPIN); // (sic: the C++ code measures the name again here)
         Result.Ptb := DPoint(X, Y - TextSpace - NumberPos);
         Result.Dr := 0;
       end;
    1: begin // down
         Result.Pa := DPoint(X, Y + LineSize);
         Result.Pb := DPoint(X - DotSize, Y + Length);
         Result.Pc := DPoint(X + DotSize + 1, Y + Length);
         Result.Pd := DPoint(X, Y + Length);
         Size := FOpts.TextExtent(Str, fPIN);
         if CentreName <> 0 then
           Result.Pta := DPoint(X + Size.cy, Y + (Size.cx + Length) / 2)
         else
           Result.Pta := DPoint(X + Size.cy / 2, Y + Spacing + Size.cx);
         Size := FOpts.TextExtent(Number, fPIN);
         Result.Ptb := DPoint(X, Y + Size.cx + TextSpace + NumberPos);
         Result.Dr := 0;
       end;
    2: begin // left
         Result.Pa := DPoint(X - LineSize, Y);
         Result.Pb := DPoint(X - Length, Y - DotSize);
         Result.Pc := DPoint(X - Length, Y + DotSize + 1);
         Result.Pd := DPoint(X - Length, Y);
         Size := FOpts.TextExtent(Str, fPIN);
         if CentreName <> 0 then
           Result.Pta := DPoint(X - (Size.cx + Length) / 2, Y + Size.cy)
         else
           Result.Pta := DPoint(X - Size.cx - Spacing, Y + Size.cy / 2);
         Size := FOpts.TextExtent(Number, fPIN);
         Result.Ptb := DPoint(X - Size.cx - TextSpace - NumberPos, Y);
       end;
    3: begin // right
         Result.Pa := DPoint(X + LineSize, Y);
         Result.Pb := DPoint(X + Length, Y - DotSize);
         Result.Pc := DPoint(X + Length, Y + DotSize + 1);
         Result.Pd := DPoint(X + Length, Y);
         Size := FOpts.TextExtent(Str, fPIN);
         if CentreName <> 0 then
           Result.Pta := DPoint(X + (Length - Size.cx) / 2, Y + Size.cy)
         else
           Result.Pta := DPoint(X + Spacing, Y + Size.cy / 2);
         Result.Ptb := DPoint(X + TextSpace + NumberPos, Y);
       end;
  end;

  { corrections for bizarre rotations (uses the last measured size, as the C++ code does) }
  if (Dir = 2) or (Dir = 3) then
    case RotMir of
      1, 5, 7, 3:
        begin
          Result.Pta := DPoint(Result.Pta.x, Result.Pta.y - Size.cy);
          Result.Ptb := DPoint(Result.Ptb.x, Result.Ptb.y - Size.cy);
        end;
    end;
end;

{ ===========================================================================
  TDrawPin.DetermineSize  (procedure)
  Parameters:  none
  Notes:
    Sets the pin's second point so its box covers the line and the text; hidden pins and zero-
    length pins have no size.
  =========================================================================== }
procedure TDrawPin.DetermineSize;
var
  L: TPinLayout;
  Sz: TDSize;
begin
  { hidden pins and zero length pins have no size }
  if (Which = 4) or (Which = 5) or (Length = 0) then
  begin
    PointB := PointA;
    Exit;
  end;
  L := DetermineLayout(0);
  PointB := L.Pta;
  if (Show and 1) <> 0 then
  begin
    Sz := FOpts.TextExtent(Str, fPIN);
    case Dir of
      0: PointB := DPoint(L.Pd.x, Min(L.Pta.y - Sz.cx, L.Pd.y));
      1: PointB := DPoint(L.Pd.x, Max(L.Pta.y, L.Pd.y));
      2: PointB := DPoint(Min(L.Pta.x, L.Pd.x), L.Pd.y);
      3: PointB := DPoint(Max(L.Pta.x, L.Pd.x), L.Pd.y);
    end;
  end;
end;

{ ===========================================================================
  TDrawPin.ConvertPowerToNormal  (procedure)
  Parameters:  none
  Notes:
    Turns a hidden power pin into a normal pin and remembers it was converted (used when a
    symbol shows its power pins).
  =========================================================================== }
procedure TDrawPin.ConvertPowerToNormal;
begin
  Which := 0;
  ConvertedPower := 1;
  DetermineSize;
end;

{ ===========================================================================
  TDrawPin.UpdateLayout  (procedure)
  Parameters:  none
  Notes:
    Recalculates geometry that depends on text sizes or on other data (text boxes, label and pin
    text positions) using the current text metrics.
  =========================================================================== }
procedure TDrawPin.UpdateLayout;
begin
  DetermineSize;
end;

{ ===========================================================================
  TDrawPin.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawPin.DistanceFromPoint(const P: TDPoint): Double;
var
  L: TPinLayout;
  D: TDPoint;
begin
  if IsInvisible then begin
    Result := 100.0;
    Exit;
  end;
  L := DetermineLayout(0);
  Result := LineDistance(PointA, L.Pd, P, D);
end;

{ ===========================================================================
  TDrawPin.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawPin.IsInside(Left, Right, Top, Bottom: Double): Boolean;
var
  L: TPinLayout;
  D, Range: Double;
begin
  if IsInvisible then begin
    Result := False;
    Exit;
  end;
  if (Left = Right) and (Top = Bottom) then
  begin
    D := DistanceFromPoint(DPoint(Left, Top));
    Range := 10 / FOpts.ZoomFactor;
    Result := D < Range;
    Exit;
  end;
  L := DetermineLayout(0);
  Result := LineIsInside(PointA, L.Pd, Left, Right, Top, Bottom);
end;

{ ===========================================================================
  TDrawPin.RotateAbout  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
    NewDir: Integer - whole number
  Notes:
    Rotates or mirrors the object about the point P. NewDir is the rotation / mirror code (0 to
    7) used throughout TinyCAD.
  =========================================================================== }
procedure TDrawPin.RotateAbout(const P: TDPoint; NewDir: Integer);
begin
  PointA := RotatePointAbout(PointA, P, NewDir);
  PointB := RotatePointAbout(PointB, P, NewDir);
  Dir := DoRotateDir(Dir, NewDir);
end;

{ ===========================================================================
  TDrawPin.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawPin (same geometry and properties). The copy has no
    object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawPin.Clone: TDrawingObject;
var
  O: TDrawPin;
begin
  O := TDrawPin.Create(FOpts);
  CopyPoints(Self, O);
  O.Str := Str; O.Number := Number;
  O.Show := Show; O.Which := Which; O.Elec := Elec; O.Part := Part; O.Dir := Dir;
  O.Length := Length; O.NumberPos := NumberPos; O.CentreName := CentreName;
  O.ConvertedPower := ConvertedPower;
  Result := O;
end;

{ ---- note text ---- }

{ ===========================================================================
  TDrawNoteText.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawNoteText.DistanceFromPoint(const P: TDPoint): Double;
var
  Distance, Width: Double;
  D: TDPoint;
begin
  { always treated as filled, whether it is or not }
  if IsInside(P.x, P.x, P.y, P.y) then
  begin
    Result := 0.0;
    Exit;
  end;
  Distance := 100.0;
  Distance := Min(Distance, LineDistance(DPoint(PointA.x, PointA.y), DPoint(PointB.x, PointA.y), P, D));
  Distance := Min(Distance, LineDistance(DPoint(PointB.x, PointA.y), DPoint(PointB.x, PointB.y), P, D));
  Distance := Min(Distance, LineDistance(DPoint(PointB.x, PointB.y), DPoint(PointA.x, PointB.y), P, D));
  Distance := Min(Distance, LineDistance(DPoint(PointA.x, PointB.y), DPoint(PointA.x, PointA.y), P, D));
  Width := Min(0, FOpts.LineThickness(Style));
  Result := Distance - Width;
end;

{ ===========================================================================
  TDrawNoteText.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawNoteText.IsInside(Left, Right, Top, Bottom: Double): Boolean;
begin
  Result := not (((PointA.x < Left) and (PointB.x <= Left)) or
                 ((PointA.x > Right) and (PointB.x >= Right)) or
                 ((PointA.y < Top) and (PointB.y <= Top)) or
                 ((PointA.y > Bottom) and (PointB.y >= Bottom)));
end;

{ ===========================================================================
  TDrawNoteText.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawNoteText (same geometry and properties). The copy has
    no object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawNoteText.Clone: TDrawingObject;
var
  O: TDrawNoteText;
begin
  O := TDrawNoteText.Create(FOpts);
  CopyPoints(Self, O);
  O.Style := Style; O.Fill := Fill; O.FontStyle := FontStyle; O.FontColor := FontColor;
  O.Str := Str; O.Dir := Dir; O.BorderStyle := BorderStyle;
  Result := O;
end;


{ ---- grid / snap settings (TransformSnap) ---- }

{ ===========================================================================
  TSnapSettings.Create  (constructor)
  Parameters:  none
  Notes:
    Creates grid settings with TinyCAD's defaults.
  =========================================================================== }
constructor TSnapSettings.Create;
begin
  inherited Create;
  Grid := EditDefaults.GridMm * PIXELSPERMM;      // (the Options dialog's choice; 2 mm, TinyCAD's NormalGrid, until one is made)
  GridSnap := Ord(EditDefaults.SnapGrid);
end;

{ ===========================================================================
  TSnapSettings.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
  Notes:
    Writes the GRID element (spacing times ten, and the snap flag).
  =========================================================================== }
procedure TSnapSettings.SaveXML(W: TXMLWriter);
begin
  W.AddTag('GRID');
  W.AddAttribute('spacing', Grid * 10.0);
  W.AddAttribute('snap', GridSnap);
  W.CloseTag;
end;

{ ===========================================================================
  TSnapSettings.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader on GRID
  Notes:
    Reads the GRID element (spacing divided by ten, as TinyCAD does even when it is absent).
  =========================================================================== }
procedure TSnapSettings.LoadXML(R: TXMLReader);
begin
  R.GetAttribute('spacing', Grid);
  R.GetAttribute('snap', GridSnap);
  Grid := Grid / 10.0; // (applied even when spacing is absent, exactly as in the C++ code)
end;

{ ===========================================================================
  TSnapSettings.Snap  (function)
  Parameters:
    D: Double - the coordinate
  Returns:
    Double - the snapped value
  Notes:
    Snaps one coordinate to the grid (unchanged when snapping is off).
  =========================================================================== }
function TSnapSettings.Snap(D: Double): Double;
begin
  Result := SnapToGrid(Grid, GridSnap <> 0, D);
end;

{ ===========================================================================
  TSnapSettings.Snap  (function)
  Parameters:
    const P: TDPoint - the point
  Returns:
    TDPoint - the snapped point
  Notes:
    Snaps a point to the grid.
  =========================================================================== }
function TSnapSettings.Snap(const P: TDPoint): TDPoint;
begin
  Result := DPoint(Snap(P.x), Snap(P.y));
end;

{ ---- symbol view ---- }

{ ===========================================================================
  TSymbolView.Create  (constructor)
  Parameters:  none
  Notes:
    Creates an empty view: no objects and invalid reference point, size and origin.
  =========================================================================== }
constructor TSymbolView.Create;
begin
  inherited Create;
  Objects := TDrawingList.Create;
  RefPoint := DPointInvalid;
  TopRight := DPointInvalid;
  Origin := DPointInvalid;
end;

{ ===========================================================================
  TSymbolView.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the view's objects.
  =========================================================================== }
destructor TSymbolView.Destroy;
begin
  Objects.Free;
  inherited Destroy;
end;

{ ===========================================================================
  PointLess  (function)
  Parameters:
    const A: TDPoint - first point
    const B: TDPoint - second point
  Returns:
    Boolean - True if A sorts before B
  Notes:
    Tolerant point ordering (like CDPoint::operator<) used to sort points.
  =========================================================================== }
function PointLess(const A, B: TDPoint): Boolean; // CDPoint::operator<
const
  Close = 0.001;
begin
  if Abs(B.x - A.x) < Close then
    Result := A.y < B.y - Close
  else
    Result := A.x < B.x - Close;
end;

{ ===========================================================================
  SwapD  (procedure)
  Parameters:
    var A: Double - first value (in/out)
    var B: Double - second value (in/out)
  Notes:
    Exchanges two numbers.
  =========================================================================== }
procedure SwapD(var A, B: Double);
var
  T: Double;
begin
  T := A; A := B; B := T;
end;

{ ===========================================================================
  TDrawMethod.GetSymbolData  (function)
  Parameters:  none
  Returns:
    TSymbolInfo - the symbol information
  Notes:
    The symbol definition this placed symbol uses (from the sheet's symbol table).
  =========================================================================== }
function TDrawMethod.GetSymbolData: TSymbolInfo;
begin
  Result := FOpts.SymbolInfo(SymbolId);
end;

{ ===========================================================================
  TDrawMethod.GetTr  (function)
  Parameters:  none
  Returns:
    TDPoint - the size point
  Notes:
    The symbol's size for this placement: its definition's size times the placement's scaling.
  =========================================================================== }
function TDrawMethod.GetTr: TDPoint;
var
  T: TDPoint;
begin
  T := GetSymbolData.GetTr(Part, ShowPower <> 0);
  Result := DPoint(T.x * ScalingX, T.y * ScalingY);
end;

{ ===========================================================================
  TDrawMethod.ExtractSymbol  (function)
  Parameters:
    out Tr: TDPoint - set to the symbol's size
    out Objects: TDrawingList - set to the view's objects (owned by the symbol)
  Returns:
    Boolean - False if there is no drawing
  Notes:
    Gets the drawing to paint or connect for this symbol (the cached view for its part and power
    setting) and its size, and updates this object's bounding box.
  =========================================================================== }
function TDrawMethod.ExtractSymbol(out Tr: TDPoint; out Objects: TDrawingList): Boolean;
var
  Sym: TSymbolInfo;
  View: TSymbolView;
  T: TDPoint;
begin
  Sym := GetSymbolData;
  View := Sym.GetView(Part, ShowPower <> 0);
  Objects := View.Objects;
  T := Sym.GetTr(Part, ShowPower <> 0);
  Tr := DPoint(T.x * ScalingX, T.y * ScalingY);
  { the bounding box }
  if (Rotate and 3) < 2 then
    PointB := DPoint(Tr.x + PointA.x, Tr.y + PointA.y)
  else
    PointB := DPoint(Tr.y + PointA.x, Tr.x + PointA.y);
  Result := True;
end;

{ ===========================================================================
  TDrawMethod.UpdateLayout  (procedure)
  Parameters:  none
  Notes:
    Recalculates geometry that depends on text sizes or on other data (text boxes, label and pin
    text positions) using the current text metrics.
  =========================================================================== }
procedure TDrawMethod.UpdateLayout;
var
  Tr: TDPoint;
  L: TDrawingList;
begin
  ExtractSymbol(Tr, L);
end;

{ ===========================================================================
  TDrawMethod.ScalePoint  (procedure)
  Parameters:
    var P: TDPoint - the point (in/out)
  Notes:
    Applies this placement's x and y scaling to a point.
  =========================================================================== }
procedure TDrawMethod.ScalePoint(var P: TDPoint);
begin
  P.x := P.x * ScalingX;
  P.y := P.y * ScalingY;
end;

{ ===========================================================================
  TDrawMethod.TranslatePointToDesign  (function)
  Parameters:
    P: TDPoint - a point in the symbol's coordinates
  Returns:
    TDPoint - the sheet position
  Notes:
    Converts a point in the symbol's own coordinates to a position on the sheet, applying
    scaling, rotation, mirror and the placement position. Pin connection points use this.
  =========================================================================== }
function TDrawMethod.TranslatePointToDesign(P: TDPoint): TDPoint;
var
  Bound, S: TDPoint;
begin
  Bound := GetTr;
  S := PointA;
  ScalePoint(P);
  { has this object been mirrored? }
  if (Rotate and 4) <> 0 then
    P.x := Bound.x - P.x;
  case Rotate and 3 of
    0: Result := DPoint(P.x + S.x, P.y + S.y);                  // up
    1: Result := DPoint(P.x + S.x, (Bound.y - P.y) + S.y);      // down
    2: Result := DPoint(P.y + S.x, P.x + S.y);                  // left
  else
    Result := DPoint((Bound.y - P.y) + S.x, P.x + S.y);         // right
  end;
end;

{ ===========================================================================
  TDrawMethod.ActivePoints  (function)
  Parameters:  none
  Returns:
    TDPointArray - the points, one per visible pin
  Notes:
    The sheet positions of the symbol's visible pins (its connection points).
  =========================================================================== }
function TDrawMethod.ActivePoints: TDPointArray;
var
  Tr: TDPoint;
  L: TDrawingList;
  i, N: Integer;
  Pin: TDrawPin;
begin
  SetLength(Result, 0);
  ExtractSymbol(Tr, L);
  N := 0;
  for i := 0 to L.Count - 1 do
    if L[i].GetType = xPinEx then
    begin
      Pin := L[i] as TDrawPin;
      if not Pin.IsInvisible then
      begin
        SetLength(Result, N + 1);
        Result[N] := TranslatePointToDesign(Pin.PointA);
        Inc(N);
      end;
    end;
end;

{ ===========================================================================
  TDrawMethod.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawMethod.DistanceFromPoint(const P: TDPoint): Double;
var
  Tr: TDPoint;
  Objs: TDrawingList;
  Nl, Nt, Sx, Sy, Closest, Dist: Double;
  i: Integer;
begin
  Result := 100.0;
  { fast cut-off with a somewhat enlarged bounding box }
  if ((PointA.x < P.x - 10) and (PointB.x < P.x - 10)) or
     ((PointA.x > P.x + 10) and (PointB.x > P.x + 10)) or
     ((PointA.y < P.y - 10) and (PointB.y < P.y - 10)) or
     ((PointA.y > P.y + 10) and (PointB.y > P.y + 10)) then
    Exit;
  { definitely inside: the point is made a tiny rectangle }
  if IsInside(P.x - 0.0001, P.x + 0.0001, P.y - 0.0001, P.y + 0.0001) then
  begin
    Result := 0.0;
    Exit;
  end;
  ExtractSymbol(Tr, Objs);
  { translate the point into the symbol's own coordinates }
  Sx := ScalingX;
  Sy := ScalingY;
  if (Rotate and 3) >= 2 then
  begin
    Sy := ScalingX;
    Sx := ScalingY;
  end;
  Nl := (P.x - PointA.x) / Sx;
  Nt := (P.y - PointA.y) / Sy;
  case Rotate and 3 of
    1: Nt := -(Nt - Tr.y / Sy);
    2: SwapD(Nt, Nl);
    3: begin
         SwapD(Nt, Nl);
         Nt := -(Nt - Tr.y / Sx);
       end;
  end;
  if (Rotate and 4) <> 0 then
  begin
    if (Rotate and 3) >= 2 then
      Nl := -Nl + Tr.x / Sy
    else
      Nl := -Nl + Tr.x / Sx;
  end;
  Closest := 100.0;
  for i := 0 to Objs.Count - 1 do
  begin
    Dist := Objs[i].DistanceFromPoint(DPoint(Nl, Nt));
    if Dist < Closest then
      Closest := Dist;
    if Closest = 0 then
      Break;
  end;
  Result := Closest;
end;

{ ===========================================================================
  TDrawMethod.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawMethod.IsInside(Left, Right, Top, Bottom: Double): Boolean;
var
  Tr: TDPoint;
  Objs: TDrawingList;
  Nl, Nr, Nt, Nb, Sx, Sy: Double;
  i: Integer;
  P1, P2: TDPoint;
  Size: TDSize;
begin
  Result := False;
  { fast cut-off: is the bounding box outside the query box? }
  if not (((PointA.x < Left) and (PointB.x <= Left)) or ((PointA.x > Right) and (PointB.x >= Right)) or
          ((PointA.y < Top) and (PointB.y <= Top)) or ((PointA.y > Bottom) and (PointB.y >= Bottom))) then
  begin
    ExtractSymbol(Tr, Objs);
    { translate the query box into the symbol's coordinates }
    Sx := ScalingX;
    Sy := ScalingY;
    if (Rotate and 3) >= 2 then
    begin
      Sy := ScalingX;
      Sx := ScalingY;
    end;
    Nl := (Left - PointA.x) / Sx;
    Nr := (Right - PointA.x) / Sx;
    Nt := (Top - PointA.y) / Sy;
    Nb := (Bottom - PointA.y) / Sy;
    case Rotate and 3 of
      1: begin
           SwapD(Nt, Nb);
           Nt := -(Nt - Tr.y / Sy);
           Nb := -(Nb - Tr.y / Sy);
         end;
      2: begin
           SwapD(Nt, Nl);
           SwapD(Nb, Nr);
         end;
      3: begin
           SwapD(Nt, Nl);
           SwapD(Nb, Nr);
           SwapD(Nt, Nb);
           Nt := -(Nt - Tr.y / Sx);
           Nb := -(Nb - Tr.y / Sx);
         end;
    end;
    if (Rotate and 4) <> 0 then
    begin
      if (Rotate and 3) >= 2 then
      begin
        Nl := -Nl + Tr.x / Sy;
        Nr := -Nr + Tr.x / Sy;
      end
      else
      begin
        Nl := -Nl + Tr.x / Sx;
        Nr := -Nr + Tr.x / Sx;
      end;
      SwapD(Nl, Nr);
    end;
    for i := 0 to Objs.Count - 1 do
      if Objs[i].IsInside(Nl, Nr, Nt, Nb) then
      begin
        Result := True;
        Exit;
      end;
  end;
  { the field labels }
  for i := 0 to High(Fields) do
  begin
    if Fields[i].Show = 0 then
      Continue;
    Size := FOpts.TextExtent(GetDecoratedField(i), fPIN);
    P1 := DPoint(Fields[i].Position.x + PointA.x, Fields[i].Position.y + PointA.y);
    P2 := DPoint(Fields[i].Position.x + PointA.x + Size.cx, Fields[i].Position.y + PointA.y - Size.cy);
    if not (((P1.x < Left) and (P2.x <= Left)) or ((P1.x > Right) and (P2.x > Right)) or
            ((P1.y < Top) and (P2.y <= Top)) or ((P1.y > Bottom) and (P2.y > Bottom))) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

{ ===========================================================================
  TDrawMethod.RotateAbout  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
    NewDir: Integer - whole number
  Notes:
    Rotates or mirrors the object about the point P. NewDir is the rotation / mirror code (0 to
    7) used throughout TinyCAD.
  =========================================================================== }
procedure TDrawMethod.RotateAbout(const P: TDPoint; NewDir: Integer);
var
  La: TDPoint;
begin
  { rotate the bounding box only if there is a centre point }
  if not PointsClose(P, DPoint(0, 0)) then
  begin
    PointA := RotatePointAbout(PointA, P, NewDir);
    PointB := RotatePointAbout(PointB, P, NewDir);
    { set the a and b co-ordinates to their correct arrangement }
    La := PointA;
    PointA := DPoint(Max(La.x, PointB.x), Max(La.y, PointB.y));
    PointB := DPoint(Min(La.x, PointB.x), Min(La.y, PointB.y));
  end;
  Rotate := DoRotateMethod(Rotate, NewDir);
  NewRotation;
end;

{ ===========================================================================
  TDrawMethod.NewRotation  (procedure)
  Parameters:  none
  Notes:
    Recalculates where the reference, name and other field texts go after the symbol is placed
    or rotated: hidden fields are stacked beside the symbol (NewRotation in TinyCAD).
  =========================================================================== }
procedure TDrawMethod.NewRotation;
const
  Spacing = 5;
var
  Tr, P: TDPoint;
  L: TDrawingList;
  TextHeight, NextY, i: Integer;
begin
  ExtractSymbol(Tr, L);
  { the bounding box }
  if (Rotate and 3) < 2 then
    PointB := DPoint(Tr.x + PointA.x, Tr.y + PointA.y)
  else
    PointB := DPoint(Tr.y + PointA.x, Tr.x + PointA.y);
  { the text positions }
  TextHeight := -PIN_HEIGHT;
  NextY := TextHeight;
  if Fields[FIELD_NAME].Show <> 0 then
  begin
    if (Rotate and 3) < 2 then
    begin
      { to the right hand side if displayed up or down }
      Fields[FIELD_NAME].Position := DPoint(Spacing, PointB.y + NextY - PointA.y);
      NextY := NextY + TextHeight + Spacing div 2;
    end
    else
      { above if left or right }
      Fields[FIELD_NAME].Position := DPoint(PointB.x - PointA.x, PointB.y - PointA.y);
  end;
  if (Rotate and 3) < 2 then
    P := DPoint(Spacing, PointB.y + NextY - PointA.y)
  else
    P := DPoint(PointB.x - PointA.x, NextY);
  { first place the shown fields }
  for i := 0 to High(Fields) do
  begin
    if i = FIELD_NAME then
      Continue;
    if Fields[i].Show <> 0 then
    begin
      Fields[i].Position := P;
      P.y := P.y + TextHeight + Spacing div 2;
    end;
  end;
  { now place the hidden fields }
  for i := 0 to High(Fields) do
  begin
    if i = FIELD_NAME then
      Continue;
    if (Fields[i].Show = 0) and (Fields[i].FieldType <> always_hidden) then
    begin
      Fields[i].Position := P;
      P.y := P.y + TextHeight + Spacing div 2;
    end;
  end;
end;

{ ===========================================================================
  TDrawMethod.GetFirstStaticPoint  (function)
  Parameters:  none
  Returns:
    TDPoint - that position
  Notes:
    The position of the symbol's first pin on the sheet, the point that stays put when a symbol
    is replaced by another.
  =========================================================================== }
function TDrawMethod.GetFirstStaticPoint: TDPoint;
var
  Origin, A, Ap: TDPoint;
  Tr: TDPoint;
  L: TDrawingList;
  i: Integer;
  Pin: TDrawPin;
begin
  { use the symbol's origin as the static point }
  Origin := GetSymbolData.GetOrigin(Part, ShowPower <> 0);
  if DPointHasValue(Origin) then
    A := TranslatePointToDesign(Origin)
  else
    A := DPointInvalid;
  if not DPointHasValue(A) then
  begin
    { no origin: use the upper-left always-visible pin }
    ExtractSymbol(Tr, L);
    for i := 0 to L.Count - 1 do
      if L[i].GetType = xPinEx then
      begin
        Pin := L[i] as TDrawPin;
        if (not Pin.IsInvisible) and (not (Pin.IsPower or (Pin.ConvertedPower <> 0))) then
        begin
          Ap := TranslatePointToDesign(Pin.PointA);
          if not DPointHasValue(A) then
            A := Ap
          else if PointLess(Ap, A) then
            A := Ap;
        end;
      end;
    { a symbol without pins: its centre }
    if not DPointHasValue(A) then
      A := DPoint((PointA.x + PointB.x) / 2, (PointA.y + PointB.y) / 2);
  end;
  Result := FOpts.Snap.Snap(A);
end;

{ ===========================================================================
  TDrawMethod.ReplaceSymbol  (procedure)
  Parameters:
    OldSymbol: Integer - current symbol number
    NewSymbol: Integer - new symbol number
    KeepOldFields: Boolean - True to keep field values with matching names
  Notes:
    Swaps the placed symbol for another definition, keeping its first pin where it was and
    (optionally) its field values.
  =========================================================================== }
procedure TDrawMethod.ReplaceSymbol(OldSymbol, NewSymbol: Integer; KeepOldFields: Boolean);
var
  RefOld, RefNew: TDPoint;
  Sym: TSymbolInfo;
  i, j, k: Integer;
  F: TMethodField;
  Found: Boolean;
begin
  if OldSymbol <> SymbolId then
    Exit; // nothing to do
  RefOld := GetFirstStaticPoint;
  SymbolId := NewSymbol;
  RefNew := GetFirstStaticPoint;
  { move the symbol so the pins stay where they were }
  Shift(DPoint(RefOld.x - RefNew.x, RefOld.y - RefNew.y));
  Sym := GetSymbolData;
  { remove hidden and (as appropriate) the symbol-defined fields }
  j := 2;
  while j < Length(Fields) do
  begin
    if Fields[j].FieldType = always_hidden then
    begin
      for k := j to High(Fields) - 1 do Fields[k] := Fields[k + 1];
      SetLength(Fields, Length(Fields) - 1);
    end
    else if Fields[j].FieldType <> extra_parameter then
    begin
      if KeepOldFields then
      begin
        Found := False;
        for i := 0 to Sym.FieldCount - 1 do
          if Sym.FieldName(i) = Fields[j].Description then begin
            Found := True;
            Break;
          end;
        if not Found then
        begin
          for k := j to High(Fields) - 1 do Fields[k] := Fields[k + 1];
          SetLength(Fields, Length(Fields) - 1);
        end
        else
          Inc(j);
      end
      else
      begin
        for k := j to High(Fields) - 1 do Fields[k] := Fields[k + 1];
        SetLength(Fields, Length(Fields) - 1);
      end;
    end
    else
      Inc(j);
  end;
  { add any fields of the new symbol that are not already present }
  for i := 0 to Sym.FieldCount - 1 do
  begin
    F.Description := Sym.FieldName(i);
    F.Value := Sym.FieldDefault(i);
    F.FieldType := Sym.FieldType(i);
    F.Position := DPoint(0, 0);
    F.Show := Ord(IsFieldVisible(F.FieldType, F.Value));
    Found := False;
    for j := 0 to High(Fields) do
      if Fields[j].Description = F.Description then
      begin
        Fields[j].FieldType := F.FieldType; // enforce the same type
        Found := True;
        Break;
      end;
    if not Found then
    begin
      SetLength(Fields, Length(Fields) + 1);
      Fields[High(Fields)] := F;
    end;
  end;
end;

{ ===========================================================================
  TDrawMethod.GetField  (function)
  Parameters:
    Which: Integer - field number (0 reference, 1 name, then others)
  Returns:
    String - the text
  Notes:
    The text of a field (reference, name, others); the reference gets a part letter for multi-
    part symbols.
  =========================================================================== }
function TDrawMethod.GetField(Which: Integer): String;
begin
  Result := Fields[Which].Value;
  if (Which = FIELD_REF) and (GetSymbolData.PartsPerPackage <> 1) then
    if GetSymbolData.PartsPerPackage > 1 then
      Result := Result + Chr(Part + Ord('A'));
end;

{ ===========================================================================
  TDrawMethod.GetDecoratedField  (function)
  Parameters:
    Which: Integer - field number
  Returns:
    String - the text to draw, empty if not shown
  Notes:
    The text to show for a field, following its display type: hidden fields give empty text,
    others may include the field name or be shown only when not empty.
  =========================================================================== }
function TDrawMethod.GetDecoratedField(Which: Integer): String;
begin
  if Fields[Which].Show = 0 then
  begin
    Result := ''; // whether to show this field overrides the conditional controls
    Exit;
  end;
  case Fields[Which].FieldType of
    default_hidden, default_show, extra_parameter:
      Result := GetField(Which);
    default_show_name_and_value:
      Result := Fields[Which].Description + '=' + GetField(Which);
    default_show_name_and_value_only_if_value_not_empty,
    default_show_value_only_if_value_not_empty:
      if Fields[Which].Value = '' then
        Result := ''
      else
        Result := Fields[Which].Description + '=' + GetField(Which);
  else
    Result := ''; // hidden, optionally or always
  end;
end;

{ ===========================================================================
  TDrawMethod.IsFieldVisible  (function)
  Parameters:
    FieldType: Integer - the field display type
    const FieldValue: String - the field's value
  Returns:
    Boolean - True if shown
  Notes:
    Whether a field of a given display type is shown for a value (hidden types never; "if not
    empty" types only when there is a value).
  =========================================================================== }
class function TDrawMethod.IsFieldVisible(FieldType: Integer; const FieldValue: String): Boolean;
begin
  case FieldType of
    default_hidden, always_hidden: Result := False;
    default_show_name_and_value_only_if_value_not_empty,
    default_show_value_only_if_value_not_empty: Result := FieldValue <> '';
  else
    Result := True; // default_show, extra_parameter, default_show_name_and_value, unknown
  end;
end;

{ ===========================================================================
  TDrawMethod.CreateFromSymbol  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options
    ASymbolId: Integer - symbol number in the sheet's table
    NewRot: Integer - initial rotation / mirror state 0-7
  Notes:
    Creates a placed symbol from a symbol definition: its part, fields (from the definition's
    defaults) and rotation.
  =========================================================================== }
constructor TDrawMethod.CreateFromSymbol(AOpts: TDocOptionsBase; ASymbolId, NewRot: Integer);
var
  Sym: TSymbolInfo;
  i: Integer;
  F: TMethodField;
begin
  inherited Create(AOpts);
  Part := 0;
  ScalingX := 1.0;
  ScalingY := 1.0;
  CanScale := 0;
  ShowPower := 0;
  Rotate := NewRot and $FF;
  SymbolId := ASymbolId;
  Sym := GetSymbolData;
  PointA := DPoint(0, 0);
  PointB := GetTr;
  SetLength(Fields, 2);
  Fields[FIELD_NAME].Value := Sym.SymbolName;
  Fields[FIELD_NAME].Description := 'Name';
  Fields[FIELD_NAME].Position := DPoint(0, 0);
  Fields[FIELD_NAME].FieldType := Sym.SymbolNameType;
  Fields[FIELD_NAME].Show := Ord(IsFieldVisible(Sym.SymbolNameType, Sym.SymbolReference));
  Fields[FIELD_REF].Value := Sym.SymbolReference;
  Fields[FIELD_REF].Description := 'Ref';
  Fields[FIELD_REF].Position := DPoint(0, 0);
  Fields[FIELD_REF].FieldType := Sym.SymbolRefType;
  Fields[FIELD_REF].Show := Ord(IsFieldVisible(Sym.SymbolRefType, Sym.SymbolReference));
  { the symbol's other parameters }
  for i := 0 to Sym.FieldCount - 1 do
  begin
    F.Description := Sym.FieldName(i);
    F.Value := Sym.FieldDefault(i);
    F.FieldType := Sym.FieldType(i);
    F.Position := DPoint(0, 0);
    F.Show := Ord(IsFieldVisible(F.FieldType, F.Value));
    SetLength(Fields, Length(Fields) + 1);
    Fields[High(Fields)] := F;
  end;
  NewRotation;
end;


{ ---- netlist-facing accessors ---- }

{ ===========================================================================
  TDrawPin.GetActivePoint  (function)
  Parameters:
    Parent: TObject - the placed symbol (TDrawMethod)
  Returns:
    TDPoint - the sheet position
  Notes:
    The pin's connection point on the sheet, given the symbol that holds it.
  =========================================================================== }
function TDrawPin.GetActivePoint(Parent: TObject): TDPoint;
begin
  Result := (Parent as TDrawMethod).TranslatePointToDesign(PointA);
end;

{ ===========================================================================
  TDrawPin.GetPinName  (function)
  Parameters:  none
  Returns:
    String - the name
  Notes:
    The pin's name text.
  =========================================================================== }
function TDrawPin.GetPinName: String;
begin
  Result := Str;
end;

{ ===========================================================================
  TDrawPin.GetNumber  (function)
  Parameters:  none
  Returns:
    String - the number
  Notes:
    The pin's number text.
  =========================================================================== }
function TDrawPin.GetNumber: String;
begin
  Result := Number;
end;

{ ===========================================================================
  TDrawLabel.GetLabelPoint  (function)
  Parameters:  none
  Returns:
    TDPoint - the point
  Notes:
    The label's connection point.
  =========================================================================== }
function TDrawLabel.GetLabelPoint: TDPoint;
begin
  Result := ActivePoint;
end;

{ ===========================================================================
  TDrawLabel.GetValue  (function)
  Parameters:  none
  Returns:
    String - the text
  Notes:
    The label's text.
  =========================================================================== }
function TDrawLabel.GetValue: String;
begin
  Result := Str;
end;

{ ===========================================================================
  TDrawPower.GetValue  (function)
  Parameters:  none
  Returns:
    String - the text
  Notes:
    The power symbol's text (its net name when set).
  =========================================================================== }
function TDrawPower.GetValue: String;
begin
  Result := Str;
end;

{ ===========================================================================
  TDrawMethod.GetRef  (function)
  Parameters:  none
  Returns:
    String - the reference
  Notes:
    The reference field's raw value (e.g. R1) with no part letter; the netlist uses it.
  =========================================================================== }
function TDrawMethod.GetRef: String;
begin
  Result := Fields[FIELD_REF].Value;
end;

{ ===========================================================================
  CAtoi  (function)
  Parameters:
    const S: String - the text
  Returns:
    Integer - the number at the start of the text
  Notes:
    C's atoi: skips white space, takes an optional sign and the digits that follow, stops at
    anything else, and gives 0 when there are no digits. A number too large for an Integer gives
    the largest (or smallest) Integer, as the Microsoft run time does.
  =========================================================================== }
function CAtoi(const S: String): Integer;
var
  I: Integer;
  Neg: Boolean;
  V: Int64;
begin
  I := 1;
  while (I <= Length(S)) and (S[I] in [#9, #10, #11, #12, #13, ' ']) do Inc(I);
  Neg := False;
  if (I <= Length(S)) and (S[I] in ['+', '-']) then
  begin
    Neg := S[I] = '-';
    Inc(I);
  end;
  V := 0;
  while (I <= Length(S)) and (S[I] in ['0'..'9']) do
  begin
    V := V * 10 + (Ord(S[I]) - 48);
    if V > 2147483648 then
      V := 2147483648;
    Inc(I);
  end;
  if Neg then
    V := -V;
  if V > 2147483647 then
    V := 2147483647;
  if V < -2147483648 then
    V := -2147483648;
  Result := V;
end;

{ ===========================================================================
  TDrawMethod.HasRef  (function)
  Parameters:  none
  Returns:
    Boolean - True if the reference is complete
  Notes:
    CDrawMethod::HasRef: a reference with a "?" in it (R?, U?) has not been given its number
    yet.
  =========================================================================== }
function TDrawMethod.HasRef: Boolean;
begin
  Result := Pos('?', GetRef) = 0;
end;

{ ===========================================================================
  TDrawMethod.GetRefVal  (function)
  Parameters:  none
  Returns:
    Integer - the number
  Notes:
    CDrawMethod::GetRefVal: the number in the reference, read from its first digit (R12A gives
    12); a reference with no digit gives 0.
  =========================================================================== }
function TDrawMethod.GetRefVal: Integer;
var
  R: String;
  K: Integer;
begin
  R := GetRef;
  K := 1;
  while (K <= Length(R)) and not (R[K] in ['0'..'9']) do Inc(K);
  if K > Length(R) then
    K := 1;         // (FindOneOf gives -1 and Mid(-1) is the whole text)
  Result := CAtoi(Copy(R, K, MaxInt));
end;

{ ===========================================================================
  TDrawMethod.SetRefVal  (procedure)
  Parameters:
    Value: Integer - the number
  Notes:
    CDrawMethod::SetRefVal: the reference becomes the symbol's reference prefix with its last
    "?" replaced by the number (U? and 3 give U3; a prefix with no "?" gives just the number).
    The C++ keeps the number in ten characters, so a number of more than nine characters gives
    none.
  =========================================================================== }
procedure TDrawMethod.SetRefVal(Value: Integer);
var
  Buf, R: String;
  K: Integer;
begin
  Buf := IntToStr(Value);
  if Length(Buf) > 9 then
    Buf := '';
  R := GetSymbolData.SymbolReference;
  K := Length(R);
  while (K > 0) and (R[K] <> '?') do Dec(K);
  Fields[FIELD_REF].Value := Copy(R, 1, K - 1) + Buf;
end;

{ ===========================================================================
  TDrawMethod.SetRef  (procedure)
  Parameters:
    const NewRef: String - the reference text
  Notes:
    CDrawMethod::SetRef: replaces the reference field's text.
  =========================================================================== }
procedure TDrawMethod.SetRef(const NewRef: String);
begin
  Fields[FIELD_REF].Value := NewRef;
end;

{ ===========================================================================
  TDrawMethod.SetPart  (procedure)
  Parameters:
    NewPart: Integer - the part (0 is A)
  Notes:
    CDrawMethod::SetPart: changes the part and moves the symbol so that the first static point
    (the origin, or the upper-left visible pin) stays where it was.
  =========================================================================== }
procedure TDrawMethod.SetPart(NewPart: Integer);
var
  RefOld, RefNew: TDPoint;
begin
  RefOld := GetFirstStaticPoint;
  Part := ToByte(NewPart);
  RefNew := GetFirstStaticPoint;
  Shift(DPoint(RefOld.x - RefNew.x, RefOld.y - RefNew.y));
end;

{ ===========================================================================
  TDrawMethod.AddReference  (procedure)
  Parameters:
    MinRef: Integer - the lowest number to give
    const Scan: array of TDrawingList - the drawings searched: every sheet, or the active one
    Own: TDrawingList - the drawing that holds this symbol
  Notes:
    CDrawMethod::AddReference: gives the symbol the next free number for its reference prefix.
    The symbols of the searched sheets that have a number and the same prefix (not this one) are
    looked at: the next free number is one above the highest, but not below MinRef. A package of
    several parts that are alike in outline takes the next part of the last symbol of the same
    kind on its own sheet before it takes a new number.
  =========================================================================== }
procedure TDrawMethod.AddReference(MinRef: Integer; const Scan: array of TDrawingList; Own: TDrawingList);
var
  OurRef: String;
  Ppp, NextAvail, LastSameRef, LastPpp, L, J, RefNumber, PppNumber: Integer;
  FoundSame, AlterSub, OurSheet: Boolean;
  Obj: TDrawingObject;
  M: TDrawMethod;
begin
  OurRef := GetSymbolData.SymbolReference;
  Ppp := GetSymbolData.PartsPerPackage;
  NextAvail := MinRef;
  LastSameRef := MinRef;
  LastPpp := -1;
  FoundSame := False;
  AlterSub := (not GetSymbolData.IsHeterogeneous) and (Ppp > 1);
  for L := 0 to High(Scan) do
  begin
    OurSheet := Scan[L] = Own;
    for J := 0 to Scan[L].Count - 1 do
    begin
      Obj := Scan[L][J];
      if ((Obj.GetType = xMethodEx3) or (Obj.GetType = xHierarchicalSymbol)) and (Obj <> Self) then
      begin
        M := Obj as TDrawMethod;
        if M.HasRef and (M.GetSymbolData.SymbolReference = OurRef) then
        begin
          RefNumber := M.GetRefVal;
          PppNumber := M.Part;
          if NextAvail <= RefNumber then
            NextAvail := RefNumber + 1;
          if (M.SymbolId = SymbolId) and OurSheet then
          begin
            FoundSame := True;
            if (LastSameRef < RefNumber) or ((LastSameRef = RefNumber) and (LastPpp < PppNumber)) then
            begin
              LastSameRef := RefNumber;
              LastPpp := PppNumber;
            end;
          end;
        end;
      end;
    end;
  end;
  if AlterSub and FoundSame then
  begin
    Inc(LastPpp);
    if LastPpp >= Ppp then
    begin
      LastPpp := 0;
      LastSameRef := NextAvail;
    end;
    SetPart(LastPpp);
    SetRefVal(LastSameRef);
  end
  else
  begin
    SetRefVal(NextAvail);
    if AlterSub then
      SetPart(0);
  end;
end;

{ ===========================================================================
  TDrawMethod.RemoveReference  (procedure)
  Parameters:  none
  Notes:
    CDrawMethod::RemoveReference: the reference goes back to the symbol's prefix (U?), and, for
    a symbol whose parts are alike in outline, the part goes back to the first.
  =========================================================================== }
procedure TDrawMethod.RemoveReference;
begin
  SetRef(GetSymbolData.SymbolReference);
  if not GetSymbolData.IsHeterogeneous then
    SetPart(0);
end;

{ ===========================================================================
  TDrawMethod.GetName  (function)
  Parameters:  none
  Returns:
    String - the name
  Notes:
    The name field's value.
  =========================================================================== }
function TDrawMethod.GetName: String;
begin
  Result := Fields[FIELD_NAME].Value;
end;

{ ===========================================================================
  TDrawMethod.GetFieldCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    Number of fields (reference, name and the extras).
  =========================================================================== }
function TDrawMethod.GetFieldCount: Integer;
begin
  Result := Length(Fields);
end;

{ ===========================================================================
  TDrawMethod.GetFieldName  (function)
  Parameters:
    Which: Integer - field number
  Returns:
    String - the field's name
  Notes:
    The description (label) of a field.
  =========================================================================== }
function TDrawMethod.GetFieldName(Which: Integer): String;
begin
  Result := Fields[Which].Description;
end;

{ ===========================================================================
  TDrawMethod.GetNetlistHint  (function)
  Parameters:
    const Pin: String - the pin number text
  Returns:
    Integer - the net number
  Notes:
    The net number remembered for a pin (0 if none). As in TinyCAD, asking about a new pin adds
    it to the hint list with 0.
  =========================================================================== }
function TDrawMethod.GetNetlistHint(const Pin: String): Integer;
var
  k: Integer;
begin
  { std::map::operator[]: a missing pin is added with 0 }
  for k := 0 to High(Hints) do
    if Hints[k].Pin = Pin then
    begin
      Result := Hints[k].Net;
      Exit;
    end;
  SetLength(Hints, Length(Hints) + 1);
  Hints[High(Hints)].Pin := Pin;
  Hints[High(Hints)].Net := 0;
  Result := 0;
end;

{ ===========================================================================
  TDrawMethod.SetNetlistHint  (procedure)
  Parameters:
    const Pin: String - the pin number text
    Net: Integer - the net number
  Notes:
    Remembers the net number of a pin so net numbers stay stable between netlist runs; saved
    with the design as HINT.
  =========================================================================== }
procedure TDrawMethod.SetNetlistHint(const Pin: String; Net: Integer);
var
  k: Integer;
begin
  for k := 0 to High(Hints) do
    if Hints[k].Pin = Pin then
    begin
      Hints[k].Net := Net;
      Exit;
    end;
  SetLength(Hints, Length(Hints) + 1);
  Hints[High(Hints)].Pin := Pin;
  Hints[High(Hints)].Net := Net;
end;


{ ---- ladder rails (schematic version) ---- }

const
  LADDER_GAP = 12; // gap between the top of a rail and its bus label, internal units (clear of the corner resize handles)

{ ===========================================================================
  TDrawLadder.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawLadder that belongs to the sheet whose options are AOpts, and gives its
    properties their default values.
  =========================================================================== }
constructor TDrawLadder.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  PointA := DPoint(0, 0);
  PointB := DPoint(0, 0);
  LeftWire := 'L1';
  RightWire := 'L2';
  LineWidth := 3;
  LineColor := cBLACK;
  FontStyle := 0;
  FontColor := cBLACK;
end;

{ ===========================================================================
  TDrawLadder.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xLadder
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawLadder.GetType: TObjType;
begin
  Result := xLadder;
end;

{ ===========================================================================
  TDrawLadder.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawLadder.TagResources;
begin
  FOpts.Fonts.Tag(FontStyle);
end;

{ ===========================================================================
  TDrawLadder.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawLadder as an XML <LADDER> element using W: opens the tag, adds its
    attributes (and any child elements), then closes it. Only non-default content that the file
    format knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawLadder.SaveXML(W: TXMLWriter);
begin
  BeginTag(W, 'LADDER');
  W.AddAttribute('a', PointA);
  W.AddAttribute('b', PointB);
  W.AddAttribute('left', LeftWire);
  W.AddAttribute('right', RightWire);
  W.AddAttribute('width', LineWidth);
  W.AddAttributeColor('railcolor', LineColor);
  W.AddAttribute('font', FontStyle);
  W.AddAttributeColor('color', FontColor);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawLadder.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawLadder from the XML element R is positioned on. An attribute that is missing
    leaves the default value set by the constructor. Resource numbers (fonts, line styles,
    fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawLadder.LoadXML(R: TXMLReader);
var
  F: Integer;
  Wd: Double;
begin
  R.GetAttribute('a', PointA);
  R.GetAttribute('b', PointB);
  R.GetAttribute('left', LeftWire);
  R.GetAttribute('right', RightWire);
  { the start/stop/lines/numside attributes of older files are ignored: the numbers are the rung grid's now }
  { older files hold the width as a number of design units that may have decimals }
  Wd := LineWidth;
  R.GetAttribute('width', Wd);
  LineWidth := Max(1, Min(50, Round(Wd)));
  R.GetAttributeColor('railcolor', LineColor);
  F := FontStyle;
  R.GetAttribute('font', F);
  R.GetAttributeColor('color', FontColor);
  FontStyle := FOpts.Fonts.ConvertOld(ToInt16(F));
end;

{ ===========================================================================
  TDrawLadder.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawLadder (same geometry and properties). The copy has
    no object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawLadder.Clone: TDrawingObject;
var
  O: TDrawLadder;
begin
  O := TDrawLadder.Create(FOpts);
  CopyPoints(Self, O);
  O.LeftWire := LeftWire; O.RightWire := RightWire;
  O.LineWidth := LineWidth; O.LineColor := LineColor;
  O.FontStyle := FontStyle; O.FontColor := FontColor;
  Result := O;
end;

{ ===========================================================================
  TDrawLadder.CanResize  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    Yes: the rails' rectangle has the eight handles of TinyCAD's rectangle tracker when the
    ladder is the one selected object, so the rails can be made longer, shorter, wider or
    narrower (ResizeBy of TDrawingObject moves PointA/PointB).
  =========================================================================== }
function TDrawLadder.CanResize: Boolean;
begin
  Result := True;
end;

{ ===========================================================================
  TDrawLadder.RailLeft  (function)
  Parameters:  none
  Returns:
    Double - x in design units
  Notes:
    x of the left rail.
  =========================================================================== }
function TDrawLadder.RailLeft: Double;
begin
  Result := Min(PointA.x, PointB.x);
end;

{ ===========================================================================
  TDrawLadder.RailRight  (function)
  Parameters:  none
  Returns:
    Double - x in design units
  Notes:
    x of the right rail.
  =========================================================================== }
function TDrawLadder.RailRight: Double;
begin
  Result := Max(PointA.x, PointB.x);
end;

{ ===========================================================================
  TDrawLadder.RailTop  (function)
  Parameters:  none
  Returns:
    Double - y in design units
  Notes:
    y of the top of the rails.
  =========================================================================== }
function TDrawLadder.RailTop: Double;
begin
  Result := Min(PointA.y, PointB.y);
end;

{ ===========================================================================
  TDrawLadder.RailBottom  (function)
  Parameters:  none
  Returns:
    Double - y in design units
  Notes:
    y of the bottom of the rails.
  =========================================================================== }
function TDrawLadder.RailBottom: Double;
begin
  Result := Max(PointA.y, PointB.y);
end;

{ ===========================================================================
  TDrawLadder.LeftLabelBox  (function)
  Parameters:  none
  Returns:
    TDRect - the box
  Notes:
    The box of the left bus wire number, centred above the left rail.
  =========================================================================== }
function TDrawLadder.LeftLabelBox: TDRect;
var
  Sz: TDSize;
begin
  Sz := FOpts.TextExtent(LeftWire, FontStyle);
  Result := DRect(RailLeft - Sz.cx / 2, RailTop - LADDER_GAP - Sz.cy, RailLeft + Sz.cx / 2, RailTop - LADDER_GAP);
end;

{ ===========================================================================
  TDrawLadder.RightLabelBox  (function)
  Parameters:  none
  Returns:
    TDRect - the box
  Notes:
    The box of the right bus wire number, centred above the right rail.
  =========================================================================== }
function TDrawLadder.RightLabelBox: TDRect;
var
  Sz: TDSize;
begin
  Sz := FOpts.TextExtent(RightWire, FontStyle);
  Result := DRect(RailRight - Sz.cx / 2, RailTop - LADDER_GAP - Sz.cy, RailRight + Sz.cx / 2, RailTop - LADDER_GAP);
end;

{ ===========================================================================
  BoxContains  (function)
  Parameters:
    const B: TDRect - the box
    const P: TDPoint - the point
  Returns:
    Boolean - True if inside
  Notes:
    Whether a point is inside a box (edges included).
  =========================================================================== }
function BoxContains(const B: TDRect; const P: TDPoint): Boolean;
begin
  Result := (P.x >= B.Left) and (P.x <= B.Right) and (P.y >= B.Top) and (P.y <= B.Bottom);
end;

{ ===========================================================================
  BoxesOverlap  (function)
  Parameters:
    const B: TDRect - the box
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if they overlap
  Notes:
    Whether a box overlaps a rectangle given by its edges.
  =========================================================================== }
function BoxesOverlap(const B: TDRect; Left, Right, Top, Bottom: Double): Boolean;
begin
  Result := not ((B.Right < Left) or (B.Left > Right) or (B.Bottom < Top) or (B.Top > Bottom));
end;

{ ===========================================================================
  TDrawLadder.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawLadder.DistanceFromPoint(const P: TDPoint): Double;
var
  D1, D2, Best: Double;
  Nearest: TDPoint;
begin
  { the rails: a real distance to the nearest rail, less half its drawn width }
  D1 := LineDistance(DPoint(RailLeft, RailTop), DPoint(RailLeft, RailBottom), P, Nearest);
  D2 := LineDistance(DPoint(RailRight, RailTop), DPoint(RailRight, RailBottom), P, Nearest);
  if D2 < D1 then
    D1 := D2;
  Best := D1 - LineWidth / 2;
  if Best < 0 then
    Best := 0;
  { the bus labels count only when the point is on them }
  if (Best > 0) and (BoxContains(LeftLabelBox, P) or BoxContains(RightLabelBox, P)) then
    Best := 0;
  { everything else, including the empty space between the rails, is "far away" }
  if Best > 100 then
    Best := 100;
  Result := Best;
end;

{ ===========================================================================
  TDrawLadder.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawLadder.IsInside(Left, Right, Top, Bottom: Double): Boolean;
begin
  if (Left = Right) and (Top = Bottom) then
  begin
    Result := DistanceFromPoint(DPoint(Left, Top)) < 3 / FOpts.ZoomFactor;
    Exit;
  end;
  { a selection rectangle: does it touch a rail or a bus label? }
  Result := LineIsInside(DPoint(RailLeft, RailTop), DPoint(RailLeft, RailBottom), Left, Right, Top, Bottom) or
            LineIsInside(DPoint(RailRight, RailTop), DPoint(RailRight, RailBottom), Left, Right, Top, Bottom) or
            BoxesOverlap(LeftLabelBox, Left, Right, Top, Bottom) or
            BoxesOverlap(RightLabelBox, Left, Right, Top, Bottom);
end;

{ ===========================================================================
  TDrawLadder.RotateAbout  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
    NewDir: Integer - whole number
  Notes:
    Rotates or mirrors the object about the point P. NewDir is the rotation / mirror code (0 to
    7) used throughout TinyCAD.
  =========================================================================== }
procedure TDrawLadder.RotateAbout(const P: TDPoint; NewDir: Integer);
begin
  { ladder rails always stand upright, so rotating does nothing; a mirror swaps the two buses }
  if NewDir = 4 then
  begin
    PointA := RotatePointAbout(PointA, P, 4);
    PointB := RotatePointAbout(PointB, P, 4);
  end;
end;


{ ---- the rung grid ---- }

const
  RUNG_PAD = 5;        // space either side of a rung number inside its cell, internal units
  RUNG_MAX_ROWS = 200;
  RUNG_UNITS_PER_MM = 5; // design units per mm (UPaper.UNITS_PER_MM, which this unit cannot use)

{ ===========================================================================
  TDocOptionsBase.PageGeometry  (function)
  Parameters:  none
  Returns:
    TPageGeometry
  Notes:
    Asks the sheet that owns these options for its page. Options not owned by a sheet answer
    with an A4 landscape page without a border.
  =========================================================================== }
function TDocOptionsBase.PageGeometry: TPageGeometry;
begin
  if Assigned(OnPageGeometry) then
    Result := OnPageGeometry()
  else
  begin
    Result.Width := 297 * RUNG_UNITS_PER_MM;
    Result.Height := 210 * RUNG_UNITS_PER_MM;
    Result.BorderInset := 0;
  end;
end;

{ ===========================================================================
  TDrawRungGrid.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawRungGrid that belongs to the sheet whose options are AOpts, and gives its
    properties their default values.
  =========================================================================== }
constructor TDrawRungGrid.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  Rows := 20;
  StartNumber := 1;
  MarginMm := 5;
  Pages := 1;
  ContinueNumbers := True;
  ShowRowHeight := True;
  AboveBlock := False;
  HasBottom := False;
  BottomMm := 0;
  FontStyle := 0;
  FontColor := cBLACK;
end;

{ ===========================================================================
  TDrawRungGrid.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xRungGrid
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawRungGrid.GetType: TObjType;
begin
  Result := xRungGrid;
end;

{ ===========================================================================
  TDrawRungGrid.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawRungGrid.TagResources;
begin
  FOpts.Fonts.Tag(FontStyle);
end;

{ ===========================================================================
  TDrawRungGrid.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawRungGrid as an XML <RUNGS> element using W: opens the tag, adds its
    attributes (and any child elements), then closes it. Only non-default content that the file
    format knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawRungGrid.SaveXML(W: TXMLWriter);
begin
  BeginTag(W, 'RUNGS');
  W.AddAttribute('rows', Rows);
  W.AddAttribute('start', StartNumber);
  W.AddAttribute('margin', MarginMm);
  W.AddAttribute('pages', Pages);
  W.AddAttribute('continue', Ord(ContinueNumbers));
  W.AddAttribute('showheight', Ord(ShowRowHeight));
  if AboveBlock then
    W.AddAttribute('aboveblock', 1);
  if HasBottom then
    W.AddAttribute('bottom', BottomMm);
  W.AddAttribute('font', FontStyle);
  W.AddAttributeColor('color', FontColor);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawRungGrid.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawRungGrid from the XML element R is positioned on. An attribute that is
    missing leaves the default value set by the constructor. Resource numbers (fonts, line
    styles, fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawRungGrid.LoadXML(R: TXMLReader);
var
  F, B: Integer;
begin
  R.GetAttribute('rows', Rows);
  R.GetAttribute('start', StartNumber);
  R.GetAttribute('margin', MarginMm);
  R.GetAttribute('pages', Pages);
  B := Ord(ContinueNumbers);
  R.GetAttribute('continue', B);
  ContinueNumbers := B <> 0;
  B := Ord(ShowRowHeight);
  R.GetAttribute('showheight', B);
  ShowRowHeight := B <> 0;
  B := Ord(AboveBlock);
  R.GetAttribute('aboveblock', B);
  AboveBlock := B <> 0;
  BottomMm := -1;
  R.GetAttribute('bottom', BottomMm);
  HasBottom := BottomMm >= 0;
  F := FontStyle;
  R.GetAttribute('font', F);
  R.GetAttributeColor('color', FontColor);
  FontStyle := FOpts.Fonts.ConvertOld(ToInt16(F));
  Rows := Max(1, Min(RUNG_MAX_ROWS, Rows));
  Pages := Max(1, Min(2, Pages));
  MarginMm := Max(0, MarginMm);
end;

{ ===========================================================================
  TDrawRungGrid.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawRungGrid (same geometry and properties). The copy has
    no object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawRungGrid.Clone: TDrawingObject;
var
  O: TDrawRungGrid;
begin
  O := TDrawRungGrid.Create(FOpts);
  CopyPoints(Self, O);
  O.Rows := Rows; O.StartNumber := StartNumber; O.MarginMm := MarginMm; O.Pages := Pages;
  O.ContinueNumbers := ContinueNumbers; O.ShowRowHeight := ShowRowHeight; O.AboveBlock := AboveBlock;
  O.HasBottom := HasBottom; O.BottomMm := BottomMm;
  O.FontStyle := FontStyle; O.FontColor := FontColor;
  Result := O;
end;

{ ===========================================================================
  TDrawRungGrid.Shift  (procedure)
  Parameters:
    const R: TDPoint - the XML reader, positioned on this element
  Notes:
    Does nothing: the grid covers the sheet and cannot be moved.
  =========================================================================== }
procedure TDrawRungGrid.Shift(const R: TDPoint);
begin
end;

{ ===========================================================================
  TDrawRungGrid.RotateAbout  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
    NewDir: Integer - whole number
  Notes:
    Rotates or mirrors the object about the point P. NewDir is the rotation / mirror code (0 to
    7) used throughout TinyCAD.
  =========================================================================== }
procedure TDrawRungGrid.RotateAbout(const P: TDPoint; NewDir: Integer);
begin
end;

{ ===========================================================================
  TDrawRungGrid.AreaRect  (function)
  Parameters:  none
  Returns:
    TDRect
  Notes:
    The whole sheet less the indent on each side: the margin in mm, plus the border margin when
    the sheet shows its border. Never smaller than a point in the middle of the sheet. With
    HasBottom (the bottom handle was dragged) the bottom edge is BottomMm above the bottom of the
    sheet, whatever the margin and the title block say. With AboveBlock (and a title block shown) the bottom edge is instead the top of the title block,
    or of its extended cell when that is shown, and the bottom indent is ignored; it is asked of
    the sheet each time, so it follows changes to the title block. Never less than one unit
    high per row.
  =========================================================================== }
function TDrawRungGrid.AreaRect: TDRect;
var
  G: TPageGeometry;
  M: Double;
begin
  G := FOpts.PageGeometry;
  M := MarginMm * RUNG_UNITS_PER_MM + G.BorderInset;
  M := Min(M, Min(G.Width, G.Height) / 2);
  Result := DRect(M, M, G.Width - M, G.Height - M);
  if HasBottom then
    Result.Bottom := Max(G.Height - BottomMm * RUNG_UNITS_PER_MM, Result.Top + Max(1, Rows))
  else if AboveBlock and (G.TitleBlockTop >= 0) then
    Result.Bottom := Max(G.TitleBlockTop, Result.Top + Max(1, Rows));
end;

{ ===========================================================================
  TDrawRungGrid.RowHeight  (function)
  Parameters:  none
  Returns:
    Double
  Notes:
    The height of one row: the area's height divided by the number of rows.
  =========================================================================== }
function TDrawRungGrid.RowHeight: Double;
var
  A: TDRect;
begin
  A := AreaRect;
  Result := (A.Bottom - A.Top) / Max(1, Rows);
end;

{ ===========================================================================
  TDrawRungGrid.RowHeightMm  (function)
  Parameters:  none
  Returns:
    Double
  Notes:
    The row height in mm, as printed above the number column.
  =========================================================================== }
function TDrawRungGrid.RowHeightMm: Double;
begin
  Result := RowHeight / RUNG_UNITS_PER_MM;
end;

{ ===========================================================================
  TDrawRungGrid.HeightText  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    The row height printout: millimetres to at most two decimals, with the unit.
  =========================================================================== }
function TDrawRungGrid.HeightText: String;
var
  Fs: TFormatSettings;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  Result := FormatFloat('0.##', RowHeightMm, Fs) + ' mm';
end;

{ ===========================================================================
  TDrawRungGrid.NumberAt  (function)
  Parameters:
    Page: Integer - whole number
    Row: Integer - whole number
  Returns:
    Integer
  Notes:
    The number of a row: the start number plus the row; on the second page, plus the rows of the
    first when the numbering continues.
  =========================================================================== }
function TDrawRungGrid.NumberAt(Page, Row: Integer): Integer;
begin
  Result := StartNumber + Row;
  if (Page = 1) and ContinueNumbers then
    Result := Result + Rows;
end;

{ ===========================================================================
  TDrawRungGrid.NumberColumnWidth  (function)
  Parameters:  none
  Returns:
    Double
  Notes:
    The width of the number columns: the widest rung number of either page plus a pad each side
    (needs the text metrics), no wider than a page.
  =========================================================================== }
function TDrawRungGrid.NumberColumnWidth: Double;
var
  A: TDRect;
  W, X: Double;
  P, Last: Integer;
begin
  W := 0;
  for P := 0 to Pages - 1 do
  begin
    Last := NumberAt(P, Rows - 1);
    X := FOpts.TextExtent(IntToStr(Last), FontStyle).cx;
    if X > W then
      W := X;
    X := FOpts.TextExtent(IntToStr(NumberAt(P, 0)), FontStyle).cx;
    if X > W then
      W := X;
  end;
  Result := W + 2 * RUNG_PAD;
  A := AreaRect;
  X := (FOpts.PageGeometry.Width / Pages) - A.Left;
  if Result > X then
    Result := Max(0, X);
end;

{ ===========================================================================
  TDrawRungGrid.ColumnRect  (function)
  Parameters:
    Page: Integer - whole number
    Col: Integer - whole number
  Returns:
    TDRect
  Notes:
    The four columns of the spreadsheet. Page 0 starts at the area's left; page 1 starts exactly
    at the middle of the sheet. The blank column of page 0 ends at the area's right with one
    page, at the middle of the sheet with two; that of page 1 ends at the area's right.
  =========================================================================== }
function TDrawRungGrid.ColumnRect(Page, Col: Integer): TDRect;
var
  A: TDRect;
  G: TPageGeometry;
  L, Rt, W: Double;
begin
  A := AreaRect;
  G := FOpts.PageGeometry;
  if Page = 0 then
    L := A.Left
  else
    L := G.Width / 2;
  if (Pages = 2) and (Page = 0) then
    Rt := G.Width / 2
  else
    Rt := A.Right;
  W := NumberColumnWidth;
  if Col = 0 then
    Result := DRect(L, A.Top, Min(Rt, L + W), A.Bottom)
  else
    Result := DRect(Min(Rt, L + W), A.Top, Rt, A.Bottom);
end;

{ ===========================================================================
  TDrawRungGrid.CellRect  (function)
  Parameters:
    Page: Integer - whole number
    Row: Integer - whole number
  Returns:
    TDRect
  Notes:
    One rung number's cell: the number column's width by one row height.
  =========================================================================== }
function TDrawRungGrid.CellRect(Page, Row: Integer): TDRect;
var
  C: TDRect;
  H: Double;
begin
  C := ColumnRect(Page, 0);
  H := RowHeight;
  Result := DRect(C.Left, C.Top + Row * H, C.Right, C.Top + (Row + 1) * H);
end;

{ ===========================================================================
  TDrawRungGrid.PageAtX  (function)
  Parameters:
    X: Double - horizontal position or value
  Returns:
    Integer
  Notes:
    Which page a position is on: the second page starts at the middle of the sheet (and exists
    only when the grid has two pages).
  =========================================================================== }
function TDrawRungGrid.PageAtX(X: Double): Integer;
begin
  if (Pages = 2) and (X >= FOpts.PageGeometry.Width / 2) then
    Result := 1
  else
    Result := 0;
end;

{ ===========================================================================
  TDrawRungGrid.RowAtY  (function)
  Parameters:
    Y: Double - vertical position or value
  Returns:
    Integer
  Notes:
    Which row a height falls in; the bottom edge counts as the last row.
  =========================================================================== }
function TDrawRungGrid.RowAtY(Y: Double): Integer;
var
  A: TDRect;
begin
  A := AreaRect;
  Result := -1;
  if (Y < A.Top) or (Y > A.Bottom) or (A.Bottom <= A.Top) then
    Exit;
  Result := Min(Rows - 1, Floor((Y - A.Top) / RowHeight));
end;

{ ===========================================================================
  TDrawRungGrid.LineNumberAt  (function)
  Parameters:
    const P: TDPoint - a point, in design units
    out Number: Integer - whole number (out: set by the call)
  Returns:
    Boolean
  Notes:
    The rung number at a position anywhere in the area (not only over the number column): the
    basis of line number awareness.
  =========================================================================== }
function TDrawRungGrid.LineNumberAt(const P: TDPoint; out Number: Integer): Boolean;
var
  A: TDRect;
  Row: Integer;
begin
  Number := 0;
  A := AreaRect;
  Row := RowAtY(P.y);
  Result := (Row >= 0) and (P.x >= A.Left) and (P.x <= A.Right);
  if Result then
    Number := NumberAt(PageAtX(P.x), Row);
end;

{ ===========================================================================
  TDrawRungGrid.HeightTextBox  (function)
  Parameters:
    Page: Integer - whole number
  Returns:
    TDRect
  Notes:
    Where the row height is printed: in the indent above the number column, left aligned with
    it, its bottom a pad above the area.
  =========================================================================== }
function TDrawRungGrid.HeightTextBox(Page: Integer): TDRect;
var
  Sz: TDSize;
  C: TDRect;
begin
  Sz := FOpts.TextExtent(HeightText, FontStyle);
  C := ColumnRect(Page, 0);
  Result := DRect(C.Left, C.Top - RUNG_PAD - Sz.cy, C.Left + Sz.cx, C.Top - RUNG_PAD);
end;

{ ===========================================================================
  TDrawRungGrid.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawRungGrid.DistanceFromPoint(const P: TDPoint): Double;
var
  i: Integer;
begin
  Result := 100;
  for i := 0 to Pages - 1 do
    if BoxContains(ColumnRect(i, 0), P) or (ShowRowHeight and BoxContains(HeightTextBox(i), P)) then
    begin
      Result := 0;
      Exit;
    end;
end;

{ ===========================================================================
  TDrawRungGrid.ResizeAspectRatio  (function)
  Parameters:  none
  Returns:
    Double - 0
  Notes:
    The grid has no corner points (PointA / PointB are never set), so the base class ratio
    would divide unset values; the bottom handle never keeps a ratio anyway.
  =========================================================================== }
function TDrawRungGrid.ResizeAspectRatio: Double;
begin
  Result := 0;
end;

{ ===========================================================================
  TDrawRungGrid.CanResize  (function)
  Parameters:  none
  Returns:
    Boolean - True
  Notes:
    The grid has one handle, the middle of its bottom edge (ResizeHandleRect), so the view offers
    it while the grid is the one thing selected.
  =========================================================================== }
function TDrawRungGrid.CanResize: Boolean;
begin
  Result := True;
end;

{ ===========================================================================
  TDrawRungGrid.ResizeHandleRect  (function)
  Parameters:
    Handle: Integer - HANDLE_*
    HandleSize: Double - the side of the square, design units
  Returns:
    TDRect - the square of the handle just below the middle of the bottom edge of the table; empty for the other seven
  Notes:
    Only HANDLE_BOTTOM exists. The middle is the middle of the table's width, which is where the
    two pages of a two page grid meet.
  =========================================================================== }
function TDrawRungGrid.ResizeHandleRect(Handle: Integer; HandleSize: Double): TDRect;
var
  A: TDRect;
  Cx: Double;
begin
  if Handle <> HANDLE_BOTTOM then
    Exit(DRect(0, 0, 0, 0));
  A := AreaRect;
  Cx := (A.Left + A.Right) / 2;
  Result := DRect(Cx - HandleSize / 2, A.Bottom, Cx + HandleSize / 2, A.Bottom + HandleSize);
end;

{ ===========================================================================
  TDrawRungGrid.ResizeHandleAt  (function)
  Parameters:
    const P: TDPoint - a point, in design units
    HandleSize: Double - the side of a handle, design units
  Returns:
    Integer - HANDLE_BOTTOM when the point is on the handle (a little more generous than its square), else HANDLE_NONE
  =========================================================================== }
function TDrawRungGrid.ResizeHandleAt(const P: TDPoint; HandleSize: Double): Integer;
var
  R: TDRect;
  Slack: Double;
begin
  Result := HANDLE_NONE;
  R := ResizeHandleRect(HANDLE_BOTTOM, HandleSize);
  Slack := HandleSize / 3;
  if (P.x >= R.Left - Slack) and (P.x <= R.Right + Slack) and (P.y >= R.Top - Slack) and (P.y <= R.Bottom + Slack) then
    Result := HANDLE_BOTTOM;
end;

{ ===========================================================================
  TDrawRungGrid.ResizeBy  (procedure)
  Parameters:
    Handle: Integer - HANDLE_BOTTOM
    const R: TDPoint - how far the handle was dragged (only the vertical part counts)
  Notes:
    Moves the bottom edge of the table by R.y: it stays below the top by at least one unit for
    every row and inside the sheet. The new place is kept as BottomMm from the bottom of the
    sheet, and replaces "above the title block" (AboveBlock is cleared). The width, left and
    top of the table do not change; the rows share the new height, so the row height changes.
  =========================================================================== }
procedure TDrawRungGrid.ResizeBy(Handle: Integer; const R: TDPoint);
var
  A: TDRect;
  G: TPageGeometry;
  NewBottom: Double;
begin
  if Handle <> HANDLE_BOTTOM then
    Exit;
  G := FOpts.PageGeometry;
  A := AreaRect;
  NewBottom := Min(G.Height, Max(A.Top + Max(1, Rows), A.Bottom + R.y));
  HasBottom := True;
  AboveBlock := False;
  BottomMm := (G.Height - NewBottom) / RUNG_UNITS_PER_MM;
end;

{ ===========================================================================
  TDrawRungGrid.IsCompletelyInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the whole grid is inside the rectangle
  Notes:
    The grid has no corners of its own (they are not set), so it is judged by its columns and
    height texts. Without this a drag to the left over a sheet with a grid raised "invalid
    floating point operation" from comparing the missing corners.
  =========================================================================== }
function TDrawRungGrid.IsCompletelyInside(Left, Right, Top, Bottom: Double): Boolean;
  function Holds(const R: TDRect): Boolean;
  begin
    Result := (R.Left >= Left) and (R.Right <= Right) and (R.Top >= Top) and (R.Bottom <= Bottom);
  end;
var
  i: Integer;
begin
  Result := Pages > 0;
  for i := 0 to Pages - 1 do
    if not (Holds(ColumnRect(i, 0)) and Holds(ColumnRect(i, 1)) and (not ShowRowHeight or Holds(HeightTextBox(i)))) then
    begin
      Result := False;
      Exit;
    end;
end;

{ ===========================================================================
  TDrawRungGrid.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawRungGrid.IsInside(Left, Right, Top, Bottom: Double): Boolean;
var
  i: Integer;
begin
  if (Left = Right) and (Top = Bottom) then
  begin
    Result := DistanceFromPoint(DPoint(Left, Top)) < 3 / FOpts.ZoomFactor;
    Exit;
  end;
  Result := False;
  for i := 0 to Pages - 1 do
    if BoxesOverlap(ColumnRect(i, 0), Left, Right, Top, Bottom) or
       (ShowRowHeight and BoxesOverlap(HeightTextBox(i), Left, Right, Top, Bottom)) then
    begin
      Result := True;
      Exit;
    end;
end;


{ ---- guide ruler (TinyCAD's RULER) ---- }

{ ===========================================================================
  TDrawRuler.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xRuler
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawRuler.GetType: TObjType;
begin Result := xRuler; end;

{ ===========================================================================
  TDrawRuler.IsConstruction  (function)
  Parameters:  none
  Returns:
    Boolean - True for construction objects
  Notes:
    True for objects that only help while editing (such as ruler guides) and are not part of a
    symbol's drawing.
  =========================================================================== }
function TDrawRuler.IsConstruction: Boolean;
begin Result := True; end;

{ ===========================================================================
  TDrawRuler.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawRuler from the XML element R is positioned on. An attribute that is missing
    leaves the default value set by the constructor. Resource numbers (fonts, line styles,
    fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawRuler.LoadXML(R: TXMLReader);
begin
  R.GetAttribute('pos', PointA);
  R.GetAttribute('horizontal', Horizontal);
  PointB := PointA;
end;

{ ===========================================================================
  TDrawRuler.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawRuler as an XML <RULER> element using W: opens the tag, adds its attributes
    (and any child elements), then closes it. Only non-default content that the file format
    knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawRuler.SaveXML(W: TXMLWriter);
begin
  BeginTag(W, 'RULER');
  W.AddAttribute('pos', PointA);
  W.AddAttribute('horizontal', Horizontal);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawRuler.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawRuler.DistanceFromPoint(const P: TDPoint): Double;
begin
  if Horizontal <> 0 then
    Result := Abs(P.y - PointA.y)
  else
    Result := Abs(P.x - PointA.x);
end;

{ ===========================================================================
  TDrawRuler.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawRuler.IsInside(Left, Right, Top, Bottom: Double): Boolean;
begin
  if Horizontal <> 0 then
    Result := (Top <= PointA.y) and (Bottom >= PointA.y)
  else
    Result := (Left <= PointA.x) and (Right >= PointA.x);
end;

{ ===========================================================================
  TDrawRuler.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawRuler (same geometry and properties). The copy has no
    object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawRuler.Clone: TDrawingObject;
var
  O: TDrawRuler;
begin
  O := TDrawRuler.Create(FOpts);
  CopyPoints(Self, O);
  O.Horizontal := Horizontal;
  Result := O;
end;

{ ---- A-to-B measuring ruler ---- }

{ ===========================================================================
  TDrawMeasure.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawMeasure that belongs to the sheet whose options are AOpts, and gives its
    properties their default values.
  =========================================================================== }
constructor TDrawMeasure.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  PointA := DPoint(0, 0);
  PointB := DPoint(0, 0);
  UnitMode := 0;
  Ticks := 1;
  LineWidth := 1;
  LineColor := RGB(0, 128, 128);
  FontStyle := 0;
  FontColor := RGB(0, 128, 128);
end;

{ ===========================================================================
  TDrawMeasure.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xMeasure
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawMeasure.GetType: TObjType;
begin Result := xMeasure; end;

{ ===========================================================================
  TDrawMeasure.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawMeasure.TagResources;
begin
  FOpts.Fonts.Tag(FontStyle);
end;

{ ===========================================================================
  TDrawMeasure.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawMeasure as an XML <MEASURE> element using W: opens the tag, adds its
    attributes (and any child elements), then closes it. Only non-default content that the file
    format knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawMeasure.SaveXML(W: TXMLWriter);
begin
  BeginTag(W, 'MEASURE');
  W.AddAttribute('a', PointA);
  W.AddAttribute('b', PointB);
  W.AddAttribute('unit', UnitMode);
  W.AddAttribute('ticks', Ticks);
  W.AddAttribute('width', LineWidth);
  W.AddAttributeColor('linecolor', LineColor);
  W.AddAttribute('font', FontStyle);
  W.AddAttributeColor('color', FontColor);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawMeasure.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawMeasure from the XML element R is positioned on. An attribute that is
    missing leaves the default value set by the constructor. Resource numbers (fonts, line
    styles, fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawMeasure.LoadXML(R: TXMLReader);
var
  F: Integer;
begin
  R.GetAttribute('a', PointA);
  R.GetAttribute('b', PointB);
  R.GetAttribute('unit', UnitMode);
  R.GetAttribute('ticks', Ticks);
  R.GetAttribute('width', LineWidth);
  R.GetAttributeColor('linecolor', LineColor);
  F := FontStyle;
  R.GetAttribute('font', F);
  R.GetAttributeColor('color', FontColor);
  FontStyle := FOpts.Fonts.ConvertOld(ToInt16(F));
end;

{ ===========================================================================
  TDrawMeasure.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawMeasure (same geometry and properties). The copy has
    no object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawMeasure.Clone: TDrawingObject;
var
  O: TDrawMeasure;
begin
  O := TDrawMeasure.Create(FOpts);
  CopyPoints(Self, O);
  O.UnitMode := UnitMode; O.Ticks := Ticks; O.LineWidth := LineWidth; O.LineColor := LineColor;
  O.FontStyle := FontStyle; O.FontColor := FontColor;
  Result := O;
end;

{ ===========================================================================
  TDrawMeasure.LengthInUnits  (function)
  Parameters:  none
  Returns:
    Double - the length
  Notes:
    The distance between the two points in the object's units (millimetres or inches).
  =========================================================================== }
function TDrawMeasure.LengthInUnits: Double;
var
  Mm: Double;
begin
  Mm := Hypot(PointB.x - PointA.x, PointB.y - PointA.y) / 5.0; // 5 internal units per mm
  if UnitMode = 1 then
    Result := Mm / 25.4
  else
    Result := Mm;
end;

{ ===========================================================================
  TDrawMeasure.DisplayText  (function)
  Parameters:  none
  Returns:
    String - the text
  Notes:
    The distance as text with its unit, e.g. "125.4 mm" or "4.937 in".
  =========================================================================== }
function TDrawMeasure.DisplayText: String;
var
  Fs: TFormatSettings;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  if UnitMode = 1 then
    Result := FormatFloat('0.000', LengthInUnits, Fs) + ' in'
  else
    Result := FormatFloat('0.0', LengthInUnits, Fs) + ' mm';
end;

{ ===========================================================================
  TDrawMeasure.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawMeasure.DistanceFromPoint(const P: TDPoint): Double;
var
  D: TDPoint;
begin
  Result := LineDistance(PointA, PointB, P, D);
end;

{ ===========================================================================
  TDrawMeasure.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawMeasure.IsInside(Left, Right, Top, Bottom: Double): Boolean;
begin
  Result := LineIsInside(PointA, PointB, Left, Right, Top, Bottom);
end;

{ ---- revision cloud ---- }

{ ===========================================================================
  TDrawCloud.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawCloud that belongs to the sheet whose options are AOpts, and gives its
    properties their default values.
  =========================================================================== }
constructor TDrawCloud.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  PointA := DPoint(0, 0);
  PointB := DPoint(0, 0);
  Style := 0;
  Bump := 25; // 5 mm
end;

{ ===========================================================================
  TDrawCloud.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xCloud
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawCloud.GetType: TObjType;
begin Result := xCloud; end;

{ ===========================================================================
  TDrawCloud.CanResize  (function)
  Parameters:  none
  Returns:
    Boolean - True
  Notes:
    Yes: a revision cloud has the eight handles of the rectangle tracker (the four corners and the middles of the four sides) when it is the one selected object; the
    inherited ResizeHandleRect / ResizeHandleAt / ResizeBy work on its two corner points, and the scallops are drawn again to fit the new size.
  =========================================================================== }
function TDrawCloud.CanResize: Boolean;
begin
  Result := True;
end;

{ ===========================================================================
  TDrawCloud.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawCloud.TagResources;
begin
  FOpts.Styles.Tag(Style);
end;

{ ===========================================================================
  TDrawCloud.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawCloud as an XML <CLOUD> element using W: opens the tag, adds its attributes
    (and any child elements), then closes it. Only non-default content that the file format
    knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawCloud.SaveXML(W: TXMLWriter);
begin
  BeginTag(W, 'CLOUD');
  W.AddAttribute('a', PointA);
  W.AddAttribute('b', PointB);
  W.AddAttribute('style', Style);
  W.AddAttribute('bump', Bump);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawCloud.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawCloud from the XML element R is positioned on. An attribute that is missing
    leaves the default value set by the constructor. Resource numbers (fonts, line styles,
    fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawCloud.LoadXML(R: TXMLReader);
var
  S: Integer;
begin
  R.GetAttribute('a', PointA);
  R.GetAttribute('b', PointB);
  S := Style;
  R.GetAttribute('style', S);
  R.GetAttribute('bump', Bump);
  Style := FOpts.Styles.ConvertOld(ToWord(S));
  if Bump < 2 then
    Bump := 2;
end;

{ ===========================================================================
  TDrawCloud.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawCloud (same geometry and properties). The copy has no
    object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawCloud.Clone: TDrawingObject;
var
  O: TDrawCloud;
begin
  O := TDrawCloud.Create(FOpts);
  CopyPoints(Self, O);
  O.Style := Style; O.Bump := Bump;
  Result := O;
end;

{ ===========================================================================
  TDrawCloud.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units (capped at 100 for objects that are only hit
    directly)
  Notes:
    Distance from the point P to the object, in internal units, used to decide what a click
    hits: 0 means P is on the object, large values mean it is far away.
  =========================================================================== }
function TDrawCloud.DistanceFromPoint(const P: TDPoint): Double;
var
  D: TDPoint;
  L, T, R, B, Dist: Double;
begin
  L := Min(PointA.x, PointB.x); R := Max(PointA.x, PointB.x);
  T := Min(PointA.y, PointB.y); B := Max(PointA.y, PointB.y);
  Dist := 100.0;
  Dist := Min(Dist, LineDistance(DPoint(L, T), DPoint(R, T), P, D));
  Dist := Min(Dist, LineDistance(DPoint(R, T), DPoint(R, B), P, D));
  Dist := Min(Dist, LineDistance(DPoint(R, B), DPoint(L, B), P, D));
  Dist := Min(Dist, LineDistance(DPoint(L, B), DPoint(L, T), P, D));
  { the scallops stand outside the rectangle by about half a bump: count them as part of the outline }
  Dist := Dist - Bump / 2;
  if Dist < 0 then
    Dist := 0;
  Result := Dist;
end;

{ ===========================================================================
  TDrawCloud.IsInside  (function)
  Parameters:
    Left: Double - left edge
    Right: Double - right edge
    Top: Double - top edge
    Bottom: Double - bottom edge
  Returns:
    Boolean - True if the object is selected by that rectangle
  Notes:
    Selection test. True when the object touches the rectangle Left..Right by Top..Bottom
    (internal units). A rectangle that is a single point is a click test.
  =========================================================================== }
function TDrawCloud.IsInside(Left, Right, Top, Bottom: Double): Boolean;
var
  L, T, R, B, M: Double;
begin
  L := Min(PointA.x, PointB.x); R := Max(PointA.x, PointB.x);
  T := Min(PointA.y, PointB.y); B := Max(PointA.y, PointB.y);
  M := Bump / 2;
  if (Left = Right) and (Top = Bottom) then
  begin
    Result := DistanceFromPoint(DPoint(Left, Top)) < 3 / FOpts.ZoomFactor;
    Exit;
  end;
  if (R < Left - M) or (L > Right + M) or (B < Top - M) or (T > Bottom + M) then
  begin
    Result := False;
    Exit;
  end;
  Result := LineIsInside(DPoint(L, T), DPoint(R, T), Left, Right, Top, Bottom) or
            LineIsInside(DPoint(R, T), DPoint(R, B), Left, Right, Top, Bottom) or
            LineIsInside(DPoint(R, B), DPoint(L, B), Left, Right, Top, Bottom) or
            LineIsInside(DPoint(L, B), DPoint(L, T), Left, Right, Top, Bottom);
end;

{ ---- linked text ---- }

{ ===========================================================================
  TDrawRefText.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawRefText that belongs to the sheet whose options are AOpts, and gives its
    properties their default values.
  =========================================================================== }
constructor TDrawRefText.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  PointA := DPoint(0, 0);
  PointB := DPoint(0, 0);
  TargetId := 0;
  Mode := 0;
  Prefix := '';
  Suffix := '';
  FontStyle := 0;
  FontColor := cBLACK;
  CachedText := '?';
end;

{ ===========================================================================
  TDrawRefText.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xRefText
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawRefText.GetType: TObjType;
begin Result := xRefText; end;

{ ===========================================================================
  TDrawRefText.TagResources  (procedure)
  Parameters:  none
  Notes:
    Marks the fonts, line styles and fill styles this object uses as in use, so that they are
    written to the file and unused ones are dropped.
  =========================================================================== }
procedure TDrawRefText.TagResources;
begin
  FOpts.Fonts.Tag(FontStyle);
end;

{ ===========================================================================
  TDrawRefText.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawRefText as an XML <XREF> element using W: opens the tag, adds its
    attributes (and any child elements), then closes it. Only non-default content that the file
    format knows about is written. The object id is written as oid when it has one.
  =========================================================================== }
procedure TDrawRefText.SaveXML(W: TXMLWriter);
begin
  BeginTag(W, 'XREF');
  W.AddAttribute('pos', PointA);
  W.AddAttribute('target', TargetId);
  W.AddAttribute('mode', Mode);
  W.AddAttribute('prefix', Prefix);
  W.AddAttribute('suffix', Suffix);
  W.AddAttribute('font', FontStyle);
  W.AddAttributeColor('color', FontColor);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawRefText.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawRefText from the XML element R is positioned on. An attribute that is
    missing leaves the default value set by the constructor. Resource numbers (fonts, line
    styles, fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawRefText.LoadXML(R: TXMLReader);
var
  F: Integer;
begin
  R.GetAttribute('pos', PointA);
  R.GetAttribute('target', TargetId);
  R.GetAttribute('mode', Mode);
  R.GetAttribute('prefix', Prefix);
  R.GetAttribute('suffix', Suffix);
  F := FontStyle;
  R.GetAttribute('font', F);
  R.GetAttributeColor('color', FontColor);
  FontStyle := FOpts.Fonts.ConvertOld(ToInt16(F));
  PointB := PointA;
end;

{ ===========================================================================
  TDrawRefText.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawRefText (same geometry and properties). The copy has
    no object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawRefText.Clone: TDrawingObject;
var
  O: TDrawRefText;
begin
  O := TDrawRefText.Create(FOpts);
  CopyPoints(Self, O);
  O.TargetId := TargetId; O.Mode := Mode; O.Prefix := Prefix; O.Suffix := Suffix;
  O.FontStyle := FontStyle; O.FontColor := FontColor; O.CachedText := CachedText;
  Result := O;
end;

{ ===========================================================================
  TDrawRefText.DisplayText  (function)
  Parameters:  none
  Returns:
    String - the text
  Notes:
    The text shown: prefix, resolved value and suffix.
  =========================================================================== }
function TDrawRefText.DisplayText: String;
begin
  Result := Prefix + CachedText + Suffix;
end;

{ ===========================================================================
  TDrawRefText.UpdateLayout  (procedure)
  Parameters:  none
  Notes:
    Recalculates geometry that depends on text sizes or on other data (text boxes, label and pin
    text positions) using the current text metrics.
  =========================================================================== }
procedure TDrawRefText.UpdateLayout;
var
  Size: TDSize;
begin
  Size := FOpts.TextExtent(DisplayText, FontStyle);
  PointB := DPoint(PointA.x + Size.cx, PointA.y - Size.cy);
end;

{ ---- placed symbol: only Clone in this slice ---- }

{ ===========================================================================
  TDrawMethod.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawMethod (same geometry and properties). The copy has
    no object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawMethod.Clone: TDrawingObject;
var
  O: TDrawMethod;
begin
  O := TDrawMethod.Create(FOpts);
  CopyPoints(Self, O);
  O.SymbolId := SymbolId;
  O.Part := Part; O.Rotate := Rotate;
  O.CanScale := CanScale; O.ShowPower := ShowPower;
  O.ScalingX := ScalingX; O.ScalingY := ScalingY;
  O.Fields := Copy(Fields, 0, Length(Fields));
  O.Hints := Copy(Hints, 0, Length(Hints));
  O.Product := Product;
  Result := O;
end;

{ ---- TDrawSymbolText (SYMTEXT) ---- }

{ ===========================================================================
  TDrawSymbolText.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options
  Notes:
    A symbol text has no symbol (SymbolId 0). Its Ref field is hidden and its Name field, the
    text that is seen, is shown; Other is hidden as in a symbol. Further fields are added by
    the properties frame like those of any symbol.
  =========================================================================== }
constructor TDrawSymbolText.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  FNothing := TDrawingList.Create;
  SymbolId := 0;
  Rotate := 3;
  Fields[FIELD_REF].Show := 0;
  Fields[FIELD_REF].FieldType := default_hidden;
end;

{ ===========================================================================
  TDrawSymbolText.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the empty drawing and then calls the inherited destructor.
  =========================================================================== }
destructor TDrawSymbolText.Destroy;
begin
  FNothing.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TDrawSymbolText.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xSymbolText
  Notes:
    Not xMethodEx3, so that code which looks for symbols (netlist, checks, annotate, parts
    list) leaves symbol texts alone.
  =========================================================================== }
function TDrawSymbolText.GetType: TObjType;
begin Result := xSymbolText; end;

{ ===========================================================================
  TDrawSymbolText.XmlTag  (function)
  Parameters:  none
  Returns:
    String - 'SYMTEXT'
  Notes:
    The element the object is saved as.
  =========================================================================== }
function TDrawSymbolText.XmlTag: String;
begin Result := 'SYMTEXT'; end;

{ ===========================================================================
  TDrawSymbolText.GetTr  (function)
  Parameters:  none
  Returns:
    TDPoint - (0, 0)
  Notes:
    There is no symbol, so no size.
  =========================================================================== }
function TDrawSymbolText.GetTr: TDPoint;
begin Result := DPoint(0, 0); end;

{ ===========================================================================
  TDrawSymbolText.ExtractSymbol  (function)
  Parameters:
    out Tr: TDPoint - (0, 0)
    out Objects: TDrawingList - an empty list (owned by this object)
  Returns:
    Boolean - False (there is no drawing)
  Notes:
    Sets PointB to the far corner of the box that holds the shown fields (the text), so that
    selecting and hit testing work on the text.
  =========================================================================== }
function TDrawSymbolText.ExtractSymbol(out Tr: TDPoint; out Objects: TDrawingList): Boolean;
var
  i: Integer;
  Size: TDSize;
  X2, Y1: Double;
begin
  Tr := DPoint(0, 0);
  Objects := FNothing;
  X2 := 0; Y1 := 0;
  for i := 0 to High(Fields) do
    if Fields[i].Show <> 0 then
    begin
      Size := FOpts.TextExtent(GetDecoratedField(i), fPIN);
      X2 := Max(X2, Fields[i].Position.x + Size.cx);
      Y1 := Min(Y1, Fields[i].Position.y - Size.cy);
    end;
  PointB := DPoint(PointA.x + X2, PointA.y + Y1);
  Result := False;
end;

{ ===========================================================================
  TDrawSymbolText.RotateAbout  (procedure)
  Parameters:
    const P: TDPoint - the centre
    NewDir: Integer - the rotation / mirror code (0 to 7)
  Notes:
    The text stays horizontal and reads normally: only its position turns about P.
  =========================================================================== }
procedure TDrawSymbolText.RotateAbout(const P: TDPoint; NewDir: Integer);
begin
  if not PointsClose(P, DPoint(0, 0)) then
    PointA := RotatePointAbout(PointA, P, NewDir);
  PointB := PointA;
end;

{ ===========================================================================
  TDrawSymbolText.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - the distance in internal units
  Notes:
    The box that holds the text is worked out again first (ExtractSymbol): the symbol's own tests cut the search short with the box worked out when the object was last laid
    out, which is wrong once the text was changed or the view zoomed (the width of a text depends on the zoom the metrics are made at), and a click on the text then missed.
  =========================================================================== }
function TDrawSymbolText.DistanceFromPoint(const P: TDPoint): Double;
var
  Tr: TDPoint;
  L: TDrawingList;
begin
  ExtractSymbol(Tr, L);
  Result := inherited DistanceFromPoint(P);
end;

{ ===========================================================================
  TDrawSymbolText.IsInside  (function)
  Parameters:
    Left, Right, Top, Bottom: Double - the rectangle (internal units)
  Returns:
    Boolean - True when the text touches it
  Notes:
    As DistanceFromPoint: the box of the text is worked out again before the test.
  =========================================================================== }
function TDrawSymbolText.IsInside(Left, Right, Top, Bottom: Double): Boolean;
var
  Tr: TDPoint;
  L: TDrawingList;
begin
  ExtractSymbol(Tr, L);
  Result := inherited IsInside(Left, Right, Top, Bottom);
end;

{ ===========================================================================
  TDrawSymbolText.CanResize  (function)
  Parameters:  none
  Returns:
    Boolean - False
  Notes:
    A symbol text is sized by its font, not by handles.
  =========================================================================== }
function TDrawSymbolText.CanResize: Boolean;
begin Result := False; end;

{ ===========================================================================
  TDrawSymbolText.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it
  Notes:
    An independent copy (same position and fields). The copy has no object id.
  =========================================================================== }
function TDrawSymbolText.Clone: TDrawingObject;
var
  O: TDrawSymbolText;
begin
  O := TDrawSymbolText.Create(FOpts);
  CopyPoints(Self, O);
  O.SymbolId := SymbolId;
  O.Part := Part; O.Rotate := Rotate;
  O.Fields := Copy(Fields, 0, Length(Fields));
  O.Hints := Copy(Hints, 0, Length(Hints));
  Result := O;
end;

{ ---- TDrawHierarchicalSymbol (HIERARCHICAL_SYMBOL) ---- }

{ ===========================================================================
  TDrawHierarchicalSymbol.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    Creates a new TDrawHierarchicalSymbol that belongs to the sheet whose options are AOpts, and
    gives its properties their default values.
  =========================================================================== }
constructor TDrawHierarchicalSymbol.Create(AOpts: TDocOptionsBase);
begin
  inherited Create(AOpts);
  Rotate := 0;
  FileName := '';
  LoadError := '';
  FSymbol := TDrawingList.Create;
  FLoaded := False;
  FTr := DPoint(0, 0);
end;

{ ===========================================================================
  TDrawHierarchicalSymbol.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees what this TDrawHierarchicalSymbol owns and then calls the inherited destructor.
  =========================================================================== }
destructor TDrawHierarchicalSymbol.Destroy;
begin
  FSymbol.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TDrawHierarchicalSymbol.GetType  (function)
  Parameters:  none
  Returns:
    TObjType - the TObjType code xHierarchicalSymbol
  Notes:
    Identifies this class's kind of object. The file format, hit testing and the netlist use the
    code to tell objects apart.
  =========================================================================== }
function TDrawHierarchicalSymbol.GetType: TObjType;
begin Result := xHierarchicalSymbol; end;

{ ===========================================================================
  TDrawHierarchicalSymbol.SetFilenameField  (procedure)
  Parameters:  none
  Notes:
    CDrawHierarchicalSymbol::SetFilenameField: the Name field (made if the symbol has fewer
    fields) is described as "Design", shown, of the normal kind, and holds the file name as it
    is displayed.
  =========================================================================== }
procedure TDrawHierarchicalSymbol.SetFilenameField;
var
  k: Integer;
begin
  if Length(Fields) < FIELD_NAME + 1 then
  begin
    k := Length(Fields);
    SetLength(Fields, FIELD_NAME + 1);
    while k <= FIELD_NAME do
    begin
      Fields[k].FieldType := 0;
      Fields[k].Description := '';
      Fields[k].Value := '';
      Fields[k].Show := 0;
      Fields[k].Position := DPointInvalid;
      Inc(k);
    end;
  end;
  Fields[FIELD_NAME].Description := 'Design';
  Fields[FIELD_NAME].Value := FormatDisplayFilename(FileName);
  Fields[FIELD_NAME].FieldType := 0;
  Fields[FIELD_NAME].Show := 1;
end;

{ ===========================================================================
  TDrawHierarchicalSymbol.Unload  (procedure)
  Parameters:  none
  Notes:
    Drops the drawing read from the design; the next use of the symbol reads the file again
    (clearSymbol).
  =========================================================================== }
procedure TDrawHierarchicalSymbol.Unload;
begin
  FSymbol.Clear;
  FLoaded := False;
  FTr := DPoint(0, 0);
end;

{ ===========================================================================
  TDrawHierarchicalSymbol.Load  (function)
  Parameters:
    const AFile: String - text
  Returns:
    Boolean
  Notes:
    CDrawHierarchicalSymbol::Load. Reads the hierarchical symbol sheet of the file, works out
    the box round its objects (from 0,0 and the first object's corner out to the largest and
    smallest corners), snaps that box to the grid - keeping the first visible pin on the grid if
    there is one - and moves every object so the box's lower left corner is the origin; the far
    corner is kept as the symbol's size. On success the file name becomes the symbol's and the
    Name field shows it. Differences: the drawing of an earlier load is dropped at the start
    (the C++ keeps it when the new file fails); a symbol sheet with no objects is a failure (the
    C++ reads past the end of the list); the message is kept in LoadError for the command to
    show, not shown from here (the C++ shows a box whenever a design is first drawn).
  =========================================================================== }
function TDrawHierarchicalSymbol.Load(const AFile: String): Boolean;
var
  A, B, Pin, SnapA, SnapB, PinOffset: TDPoint;
  HasPins: Boolean;
  i: Integer;
  O: TDrawingObject;
  Grid: Double;
begin
  Result := False;
  Unload;
  FLoaded := True;
  LoadError := '';
  if not Assigned(HierarchicalLoader) then
  begin
    LoadError := rsDesignsCannotBeReadHere;
    FTr := DPoint(-50, -50);
    Exit;
  end;
  if not HierarchicalLoader(AFile, FOpts, FSymbol, LoadError) then
  begin
    FSymbol.Clear;
    FTr := DPoint(-50, -50);
    Exit;
  end;
  if FSymbol.Count = 0 then
  begin
    LoadError := rsThisFileDoesNotHave;
    FTr := DPoint(-50, -50);
    Exit;
  end;
  { the objects work out their size (a pin's depends on its name; the C++ does that as it reads) }
  for i := 0 to FSymbol.Count - 1 do FSymbol[i].UpdateLayout;
  { the box round the objects }
  A := DPoint(0, 0);
  B := FSymbol[0].PointA;
  HasPins := False;
  Pin := DPoint(0, 0);
  for i := 0 to FSymbol.Count - 1 do
  begin
    O := FSymbol[i];
    if (O.GetType = xPinEx) and (not HasPins) and (not (O as TDrawPin).IsInvisible) then
    begin
      Pin := O.PointA;
      HasPins := True;
    end;
    A.x := Max(A.x, Max(O.PointA.x, O.PointB.x));
    A.y := Max(A.y, Max(O.PointA.y, O.PointB.y));
    B.x := Min(B.x, Min(O.PointA.x, O.PointB.x));
    B.y := Min(B.y, Min(O.PointA.y, O.PointB.y));
  end;
  { snap the box to the grid, with the first visible pin on it }
  Grid := FOpts.Snap.Grid;
  SnapA := FOpts.Snap.Snap(A);
  SnapB := FOpts.Snap.Snap(B);
  PinOffset := DPoint(0, 0);
  if HasPins then
  begin
    PinOffset := DPoint(Pin.x - FOpts.Snap.Snap(Pin.x), Pin.y - FOpts.Snap.Snap(Pin.y));
    SnapA := DPoint(SnapA.x + PinOffset.x, SnapA.y + PinOffset.y);
    SnapB := DPoint(SnapB.x + PinOffset.x, SnapB.y + PinOffset.y);
  end;
  { the snapping always rounds outwards }
  if SnapA.x < A.x then
    SnapA.x := SnapA.x + Grid;
  if SnapA.y < A.y then
    SnapA.y := SnapA.y + Grid;
  if SnapB.x > B.x then
    SnapB.x := SnapB.x - Grid;
  if SnapB.y > B.y then
    SnapB.y := SnapB.y - Grid;
  { the lower left corner of the box is the origin }
  for i := 0 to FSymbol.Count - 1 do
  begin
    O := FSymbol[i];
    O.PointA := DPoint(O.PointA.x - SnapA.x, O.PointA.y - SnapA.y);
    O.PointB := DPoint(O.PointB.x - SnapA.x, O.PointB.y - SnapA.y);
  end;
  FTr := DPoint(SnapB.x - SnapA.x, SnapB.y - SnapA.y);
  FileName := AFile;
  SetFilenameField;
  Result := True;
end;

{ ===========================================================================
  TDrawHierarchicalSymbol.IsNoSymbol  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    Reads the design first if that has not been tried. Such a symbol is drawn as a plain box.
  =========================================================================== }
function TDrawHierarchicalSymbol.IsNoSymbol: Boolean;
begin
  if not FLoaded then
    Load(FileName);
  Result := FSymbol.Count = 0;
end;

{ ===========================================================================
  TDrawHierarchicalSymbol.HasSymbol  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    Does not read the design.
  =========================================================================== }
function TDrawHierarchicalSymbol.HasSymbol: Boolean;
begin
  Result := FLoaded and (FSymbol.Count > 0);
end;

{ ===========================================================================
  TDrawHierarchicalSymbol.GetTr  (function)
  Parameters:  none
  Returns:
    TDPoint
  Notes:
    The far corner of the design's box times the scaling. (The C++ asks the symbol table for
    this, which has nothing for a design, so its pin positions come out wrong; the port uses the
    design's own size.)
  =========================================================================== }
function TDrawHierarchicalSymbol.GetTr: TDPoint;
begin
  if not FLoaded then
    Load(FileName);
  if FSymbol.Count = 0 then
    Result := FTr
  else
    Result := DPoint(FTr.x * ScalingX, FTr.y * ScalingY);
end;

{ ===========================================================================
  TDrawHierarchicalSymbol.ExtractSymbol  (function)
  Parameters:
    out Tr: TDPoint - a point, in design units (out: set by the call)
    out Objects: TDrawingList - out: set by the call
  Returns:
    Boolean
  Notes:
    CDrawHierarchicalSymbol::ExtractSymbol. Reads the design the first time. When that works the
    size is the design's box times the scaling and the far corner of the symbol follows from the
    rotation. When it does not, the box goes from the placement point out by the unscaled size
    the failed load left (50 by 50 units from the placement point at minus 50, minus 50 for a
    missing file) and there is nothing to draw.
  =========================================================================== }
function TDrawHierarchicalSymbol.ExtractSymbol(out Tr: TDPoint; out Objects: TDrawingList): Boolean;
begin
  if not FLoaded then
    Load(FileName);
  Objects := FSymbol;
  if FSymbol.Count = 0 then
  begin
    Tr := FTr;
    PointB := DPoint(FTr.x + PointA.x, FTr.y + PointA.y);
    Result := False;
    Exit;
  end;
  Tr := DPoint(FTr.x * ScalingX, FTr.y * ScalingY);
  if (Rotate and 3) < 2 then
    PointB := DPoint(Tr.x + PointA.x, Tr.y + PointA.y)
  else
    PointB := DPoint(Tr.y + PointA.x, Tr.x + PointA.y);
  Result := True;
end;

{ ===========================================================================
  TDrawHierarchicalSymbol.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    Writes this TDrawHierarchicalSymbol as an XML <HIERARCHICAL_SYMBOL> element using W: opens
    the tag, adds its attributes (and any child elements), then closes it. Only non-default
    content that the file format knows about is written. The object id is written as oid when it
    has one.
  =========================================================================== }
procedure TDrawHierarchicalSymbol.SaveXML(W: TXMLWriter);
var
  i: Integer;
begin
  BeginTag(W, 'HIERARCHICAL_SYMBOL');
  W.AddAttribute('pos', PointA);
  W.AddAttribute('rotate', Rotate);
  W.AddAttribute('can_scale', CanScale);
  W.AddAttribute('scale_x', ScalingX);
  W.AddAttribute('scale_y', ScalingY);
  W.AddAttribute('file', FormatXMLFilename(FileName));
  for i := 0 to High(Fields) do
  begin
    W.AddTag('FIELD');
    W.AddAttribute('type', Fields[i].FieldType);
    W.AddAttribute('description', Fields[i].Description);
    if i = FIELD_NAME then
      W.AddAttribute('value', '')
    else
      W.AddAttribute('value', Fields[i].Value);
    W.AddAttribute('show', Fields[i].Show);
    W.AddAttribute('pos', Fields[i].Position);
    W.CloseTag;
  end;
  W.CloseTag;
end;

{ ===========================================================================
  TDrawHierarchicalSymbol.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads this TDrawHierarchicalSymbol from the XML element R is positioned on. An attribute
    that is missing leaves the default value set by the constructor. Resource numbers (fonts,
    line styles, fills) are converted to this sheet's numbering.
  =========================================================================== }
procedure TDrawHierarchicalSymbol.LoadXML(R: TXMLReader);
var
  Name, Raw: String;
  V, i, T, k: Integer;
begin
  R.GetAttribute('pos', PointA);
  V := Rotate; R.GetAttribute('rotate', V); Rotate := ToByte(V);
  R.GetAttribute('can_scale', CanScale);
  R.GetAttribute('scale_x', ScalingX);
  R.GetAttribute('scale_y', ScalingY);
  Raw := '';
  R.GetAttribute('file', Raw);
  FileName := UnformatXMLFilename(Raw);
  R.IntoTag;
  i := 0;
  while R.NextTag(Name) do
    if Name = 'FIELD' then
    begin
      if Length(Fields) <> i + 1 then
      begin
        k := Length(Fields);
        SetLength(Fields, i + 1);
        while k <= i do
        begin
          Fields[k].FieldType := 0;
          Fields[k].Description := '';
          Fields[k].Value := '';
          Fields[k].Show := 0;
          Fields[k].Position := DPointInvalid;
          Inc(k);
        end;
      end;
      T := 0;
      R.GetAttribute('type', T);
      R.GetAttribute('description', Fields[i].Description);
      R.GetAttribute('value', Fields[i].Value);
      R.GetAttribute('show', Fields[i].Show);
      R.GetAttribute('pos', Fields[i].Position);
      Fields[i].FieldType := T;
      Inc(i);
    end;
  R.OutOfTag;
  if (Length(Fields) > FIELD_NAME) and (FileName <> '') then
    Fields[FIELD_NAME].Value := FormatDisplayFilename(FileName);
end;

{ ===========================================================================
  TDrawHierarchicalSymbol.Clone  (function)
  Parameters:  none
  Returns:
    TDrawingObject - the new object; the caller owns it and must free it or add it to a list
    that does
  Notes:
    Makes an independent copy of this TDrawHierarchicalSymbol (same geometry and properties).
    The copy has no object id; whoever uses it adds it to a sheet.
  =========================================================================== }
function TDrawHierarchicalSymbol.Clone: TDrawingObject;
var
  O: TDrawHierarchicalSymbol;
begin
  O := TDrawHierarchicalSymbol.Create(FOpts);
  CopyPoints(Self, O);
  O.Part := Part; O.Rotate := Rotate;
  O.CanScale := CanScale;
  O.ScalingX := ScalingX; O.ScalingY := ScalingY;
  O.Fields := Copy(Fields, 0, Length(Fields));
  O.FileName := FileName;
  Result := O;
end;

{ ---- factory / load / save helpers ---- }

{ ===========================================================================
  CreateObjectForTag  (function)
  Parameters:
    const Tag: String - the element name
    Opts: TDocOptionsBase - the sheet options the object belongs to
  Returns:
    TDrawingObject - the object, or nil for an unknown tag
  Notes:
    Makes an empty object for an XML element name (WIRE, JUNCTION, SYMBOL, LADDER ...).
  =========================================================================== }
function CreateObjectForTag(const Tag: String; Opts: TDocOptionsBase): TDrawingObject;
begin
  Result := nil;
  if Tag = 'BUSSLASH' then
    Result := TDrawBusSlash.Create(Opts)
  else if Tag = 'JUNCTION' then
    Result := TDrawJunction.Create(Opts)
  else if Tag = 'BUS' then
    Result := TDrawLine.CreateKind(Opts, xBus)
  else if Tag = 'WIRE' then
    Result := TDrawLine.CreateKind(Opts, xWire)
  else if Tag = 'LINE' then
    Result := TDrawLine.CreateKind(Opts, xLineEx2)
  else if Tag = 'SYMBOL' then
    Result := TDrawMethod.Create(Opts)
  else if Tag = 'SYMTEXT' then
    Result := TDrawSymbolText.Create(Opts)
  else if (Tag = 'HIERARCHICAL_SYMBOL') or (Tag = 'HIERACHICAL_SYMBOL') then
    Result := TDrawHierarchicalSymbol.Create(Opts)
  else if Tag = 'NOCONNECT' then
    Result := TDrawNoConnect.Create(Opts)
  else if Tag = 'ORIGIN' then
    Result := TDrawOrigin.Create(Opts)
  else if Tag = 'PIN' then
    Result := TDrawPin.Create(Opts)
  else if Tag = 'RECTANGLE' then
    Result := TDrawSquare.CreateKind(Opts, xSquareEx3)
  else if Tag = 'NOTE_TEXT' then
    Result := TDrawNoteText.Create(Opts)
  else if Tag = 'METAFILE' then
    Result := TDrawMetaFile.Create(Opts)
  else if Tag = 'ELLIPSE' then
    Result := TDrawSquare.CreateKind(Opts, xCircleEx3)
  else if Tag = 'TEXT' then
    Result := TDrawText.CreateKind(Opts, xTextEx2)
  else if Tag = 'BUSNAME' then
    Result := TDrawText.CreateKind(Opts, xBusNameEx)
  else if Tag = 'LABEL' then
    Result := TDrawLabel.Create(Opts)
  else if Tag = 'POLYGON' then
    Result := TDrawPolygon.Create(Opts)
  else if Tag = 'POWER' then
    Result := TDrawPower.Create(Opts)
  else if Tag = 'LADDER' then
    Result := TDrawLadder.Create(Opts)
  else if Tag = 'RUNGS' then
    Result := TDrawRungGrid.Create(Opts)
  else if Tag = 'RULER' then
    Result := TDrawRuler.Create(Opts)
  else if Tag = 'MEASURE' then
    Result := TDrawMeasure.Create(Opts)
  else if Tag = 'CLOUD' then
    Result := TDrawCloud.Create(Opts)
  else if Tag = 'XREF' then
    Result := TDrawRefText.Create(Opts);
end;

{ ===========================================================================
  IsKnownUnsupportedObjectTag  (function)
  Parameters:
    const Tag: String - the element name
  Returns:
    Boolean - True if the tag is known but unsupported
  Notes:
    Whether a tag belongs to a TinyCAD object this port does not load (TAG, METAFILE,
    hierarchical symbols); such elements are skipped rather than reported as errors.
  =========================================================================== }
function IsKnownUnsupportedObjectTag(const Tag: String): Boolean;
begin
  Result := (Tag = 'TAG') or
            (Tag = 'HierarchicalSymbol') or (Tag = 'HierachicalSymbol');
end;

{ ===========================================================================
  LoadObjectTag  (function)
  Parameters:
    R: TXMLReader - the XML reader on the element
    const Tag: String - the element name
    Opts: TDocOptionsBase - the sheet options
    List: TDrawingList - receives the object
    var Origin: TDPoint - the origin found so far (in/out)
  Returns:
    Boolean - True normally; False if the element could not be read
  Notes:
    Reads one object element into a list: makes the object, reads its id and properties, and
    drops it if it turns out empty. Only the first ORIGIN is accepted.
  =========================================================================== }
function LoadObjectTag(R: TXMLReader; const Tag: String; Opts: TDocOptionsBase;
  List: TDrawingList; var Origin: TDPoint): Boolean;
var
  Obj: TDrawingObject;
begin
  Result := True;
  if (Tag = 'ORIGIN') and DPointHasValue(Origin) then
    Exit; // allow only a single origin object
  Obj := CreateObjectForTag(Tag, Opts);
  if Obj = nil then
  begin
    Result := IsKnownUnsupportedObjectTag(Tag);
    Exit;
  end;
  Obj.Id := 0;
  R.GetAttribute('oid', Obj.Id);
  Obj.LoadXML(R);
  if Obj.IsEmpty then
    Obj.Free
  else
  begin
    List.Add(Obj);
    if Obj.GetType = xOrigin then
      Origin := Obj.PointA;
  end;
end;

{ ===========================================================================
  SaveObjects  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
    List: TDrawingList - the objects
    Details: Boolean - True when saving a sheet (including construction objects), False for a sy
      mbol
    SaveOriginObject: Boolean - True to write the origin object
    Only: TList = nil
  Notes:
    Writes the objects of a list as XML; construction objects only in the details form and
    errors never; the origin object only when asked.
  =========================================================================== }
procedure SaveObjects(W: TXMLWriter; List: TDrawingList; Details, SaveOriginObject: Boolean;
  Only: TList = nil);
var
  i: Integer;
  Obj: TDrawingObject;
begin
  for i := 0 to List.Count - 1 do
  begin
    Obj := List[i];
    if (Obj.GetType <> xError) and
       (Details or (not Obj.IsConstruction) or (SaveOriginObject and (Obj.GetType = xOrigin))) and
       ((not Details) or (Obj.GetType <> xOrigin)) and
       ((Only = nil) or (Only.IndexOf(Obj) >= 0)) then
      Obj.SaveXML(W);
  end;
end;

end.
