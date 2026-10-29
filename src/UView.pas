// SPDX-License-Identifier: LGPL-2.1-or-later
{ The drawing area: shows one sheet of a design and is where every tool lives.

  Wires and lines are drawn by the data layer's TWireTool (a port of TinyCAD's own line tool) through
  a TWireEngine, so snapping to pins and wires, merging, splitting and automatic junctions behave as
  in TinyCAD. Hit testing and selection rectangles are the objects' own (DistanceFromPoint /
  IsInside), so what can be clicked is decided by the objects; for ladder rails that is the two
  rails and the text, never the space between them.

  Every change goes through BeginChange / CommitChange so it can be undone, and linked text is
  refreshed after each one.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UView;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Forms, StdCtrls, Graphics, Math, Types, LCLType, ExtCtrls, Menus, UDPoint, UDrawTypes,
  UGeometry, UResources, UDrawingObjects, USymbols, UDesign, UPaper, UPainter, UEdit, UUndo, ULinks,
  UProps, UClip, UDocVars, UImageInfo, UImageLoad, UOptions, URepeat, UAnnotate, UPhases, Clipbrd;

type
  TViewTool = (vtSelect, vtWire, vtLine, vtPolygon, vtRect, vtCircle, vtArc, vtNote, vtCloud,
    vtLabel, vtJunction, vtRulerH, vtRulerV, vtMeasure, vtLadder, vtXRefLine, vtXRefContacts, vtPlace,
    vtBus, vtBusSlash, vtNoConnect, vtPower, vtText, vtRefPainter, vtPin, vtOrigin, vtRungs, vtSymbolText);

const
  { the tools a symbol cannot be drawn with: the ones that make a circuit (wires, buses, labels, junctions, power, ladders, cross references) and placing other symbols }
  SYMBOL_EDITOR_REFUSED = [vtWire, vtLabel, vtJunction, vtLadder, vtRungs, vtSymbolText, vtXRefLine, vtXRefContacts, vtPlace, vtBus, vtBusSlash, vtNoConnect, vtPower, vtRefPainter];

type
  TViewEvent = procedure(Sender: TObject) of object;
  { names the first version of the view used; kept so forms written against it still compile }
  TSelectionEvent = TViewEvent;
  TLadderEvent = procedure(Sender: TObject; Ladder: TDrawLadder) of object;
  TStatusEvent = procedure(Sender: TObject; const Msg: String) of object;
  TObjectEvent = procedure(Sender: TObject; Obj: TDrawingObject) of object;

  { a red circle that Find puts on an object it has found; it belongs to the view, not to the design, so it is never saved,
    undone, copied or netlisted }
  TFindMarker = record
    Sheet: Integer;
    Point: TDPoint;
  end;
  TMarkerEvent = procedure(Sender: TObject; Index: Integer) of object;
  { a right click on the sheet with nothing being drawn: where (window position and sheet point) so the owner can show its menu }
  TContextEvent = procedure(Sender: TObject; X, Y: Integer; const P: TDPoint) of object;

  TSchematicView = class(TCustomControl)
  private
    FDesign: TDesignFile;
    FSheetIndex: Integer;
    FT: TTransform;
    FZoom: Double;
    FOrigin: TDPoint;
    FSelected: TList;
    FShowGrid: Boolean;
    FOnePxDots: Boolean;
    FTool: TViewTool;
    FRefStart: Integer;      // the number the reference painter starts from
    FGhost: TDrawMethod;
    FEngine: TWireEngine;
    FWire: TWireTool;
    FUndo: TUndoManager;
    FPoly: array of TDPoint;
    FStage: Integer;            // 0 = nothing placed yet, 1 = first point placed
    FShapeStart, FShapeEnd: TDPoint;
    FShapeScreen: TPoint;
    FXTarget: TDrawingObject;
    FMouseDesign: TDPoint;
    FUserFont: TFont;          // the font the person last asked for: what the next text, label or power symbol starts with (carried from object to object)
    FOnViewMoved: TNotifyEvent;
    FOnArcTypeChanged: TNotifyEvent;
    FPointerPixel: TPoint;
    FHasPointer: Boolean;
    FHaveMouse: Boolean;       // the pointer has been over the view (so a floating text can be shown)
    FDownButton: TMouseButton;  // the button that began the drag in progress (a press or release of another button meanwhile is ignored)
    FMidPan: Boolean;           // the middle button is held to move the viewport while another button's drag (a move, a rubber band ...) goes on
    FPanFocus: TWinControl;     // the text box that had the focus when a pan began (the sheet takes the focus for the pan); it gets it back when the pan is over, or nil
    FMidLast: TPoint;           // where the pointer was at the last step of that pan (pixels)
    FDragMode: Integer;         // 0 none, 1 move selection, 2 rubber band, 3 pan, 4 two-corner shape, 5 polygon handle, 6 resize handle, 7 a field of a symbol
    FEndFirst: Boolean;         // which end of FEndLine is being pulled: the first (PointA) or the second
    FEndLine: TDrawLine;        // a chosen wire whose end is being pulled (only that wire and end move), or nil
    FResizeRatio: Double;       // height / width of the rectangle being resized, for keeping its shape with Ctrl
    FDragStart, FDragLast: TDPoint;
    FDragScreen: TPoint;
    FOriginAtDrag: TDPoint;
    FMoved: Boolean;
    FToolDefaults: array[TViewTool] of TStringList;      // the properties chosen for what each tool draws (name=value)
    FOnDragEnd: TViewEvent;     // a button was let go (whatever the drag was)
    FOnSelection, FOnModified, FOnToolChanged, FOnUndoChanged, FOnZoomChanged: TViewEvent;
    FOnStatus: TStatusEvent;
    FNameDir, FPinDir: Integer;       // Repeat Directions: names and pin numbers count up (+1) or down (-1) as things are placed one after another
    FLastLabelId, FLastTextId, FLastPinId: Integer;       // the label, the text and the pin placed last (by their ids, which survive an undo) ...
    FLastLabelText, FLastTextText: String;    // ... and what they said when they were placed, for the next one to start from
    FOnPosition: TStatusEvent;        // the pointer's position as text (for the position bar); without one it goes to the status message
    FOnPlaced: TObjectEvent;
    FOnLadder: TLadderEvent;
    FDragEng: TWireEngine;       // moves the selection and stretches the wires attached to it
    FAutoFit: Boolean;           // the page is kept fitted to the window until the user zooms or scrolls
    FFieldCode: Integer;         // the polygon handle (1000 + n) or control point (5000 + n) being dragged
    FPolyArc: Integer;           // the arc type given to the next segments of a polygon being drawn
    FPolyArcs: array of Integer; // the arc type of each point of the polygon being drawn
    FDrawPopup: TPopupMenu;          // the Polygon tool's right click menu (items in the form file; set by the owner)
    FArcPopup: TPopupMenu;           // the Arc tool's right click menu (items in the form file; set by the owner)
    FOnContext: TContextEvent;
    FArcToolType: Integer;       // the kind of arc the Arc tool draws (Arc_in or Arc_out)
    FMarkers: array of TFindMarker;   // the red circles of what Find found
    FMarkerSel: Integer;              // the one that is chosen, -1 for none
    FOnMarkerClick: TMarkerEvent;
    FMenuPoint: TDPoint;         // where the polygon menu was opened
    FAreaA, FAreaB: TDPoint;     // the area the selection was picked with (CDragUtils::m_a, m_b)
    FPasting: Boolean;           // a pasted block is following the mouse
    FPasteDone: String;          // what the status line says when it has been placed
    FBlockRef: TDPoint;          // the point of the block that follows the mouse
    FClipFmt: TClipboardFormat;
    function ClipFormat: TClipboardFormat;
    procedure StartDragEngine;
    procedure PruneSelection;
    procedure DropPaste;
    procedure CancelPaste;
    function BeginPasteFrom(Src: TStream; const UndoName, FailMsg, PlaceMsg, DoneMsg: String): Integer;
    function StartBlock(Imp: TList; const PlaceMsg, DoneMsg: String): Integer;
    procedure ClipboardToStream(S: TStream);
    function GetSheet: TDesignSheet;
    procedure SetZoomAt(NewZoom: Double; const Focus: TPoint);
    procedure ApplyTransform;
    function SnapPoint(const P: TDPoint): TDPoint;
    procedure ReportPosition(const P: TDPoint);
    function FloatTextFor(ATool: TViewTool): String;
    function MakeFloat(ATool: TViewTool; const P: TDPoint): TDrawingObject;
    procedure InitUserFont;
    procedure ApplyUserFont(ATool: TViewTool);
    procedure TakeUserFont(Obj: TDrawingObject);
    function FloatTextString: String;
    function NextPlacedText(const DefaultText: String; Id: Integer; const LastText: String): String;
    procedure SetNameDir(Value: Integer);
    procedure SetPinDir(Value: Integer);
    procedure Status(const Msg: String);
    procedure SelectionChanged;
    function GetSnapEnabled: Boolean;
    procedure SetSnapEnabled(Value: Boolean);
    function GetGridMm: Double;
    procedure SetGridMm(Value: Double);
    function SelectedIds: TIntArray;
    procedure RestoreSelection(const Ids: TIntArray);
    procedure FreeTool;
    procedure AddNew(Obj: TDrawingObject);
    procedure WireLineMade(L: TDrawLine);
    procedure FinishPolygon(Closed: Boolean);
    procedure CommitShape(const A, B: TDPoint);
    procedure PlaceLabel(const NoSnap: TDPoint);
    procedure PlaceSimple(const NoSnap: TDPoint);
    procedure XRefClick(const P: TDPoint);
    procedure WireDown(const P: TDPoint; Shift: TShiftState);
    procedure WireUp(const P: TDPoint);
    procedure PaintPreview(C: TCanvas);
    procedure RenderTo(ABitmap: TBitmap);
    function ToolIsTwoCorner: Boolean;
  protected
    procedure Paint; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure Resize; override;
    procedure MouseLeave; override;
    function SelectedPolygon: TDrawPolygon;
    function CursorForHandle(AHandle: Integer): TCursor;
    function PolygonTolerance: Double;
    procedure ShowDrawMenu(X, Y: Integer);
    procedure ShowArcMenu(X, Y: Integer);
    procedure SetArcToolType(AValue: Integer);
    procedure ExpandPhaseGroups;
    procedure ReconcileBuses;
    function PhaseGroupInside(AGroup: Integer; L, R, T, B: Double): Boolean;
    procedure PlacePhaseCopies(APlaced: TDrawMethod);
    function MarkerAt(const P: TDPoint): Integer;
  public
    function FloatingText: String;
    function UserFontInfo: String;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetDesign(ADesign: TDesignFile; ASheetIndex: Integer);
    procedure SetSheetIndex(AIndex: Integer);
    procedure ZoomFit;
    procedure ZoomBy(Factor: Double);
    procedure ZoomActual;
    function ScreenToDesign(const P: TPoint): TDPoint;
    function DesignToScreen(const P: TDPoint): TPoint;
    function HitTest(const P: TDPoint): TDrawingObject;
    procedure ClearSelection;
    procedure SelectObject(Obj: TDrawingObject; Add: Boolean);
    procedure SelectAll;
    procedure SelectAllAlike;
    { scroll the sheet, if it needs it, so the object can be seen (at the zoom it has now) }
    procedure ShowObject(Obj: TDrawingObject);
    { ---- resizing with handles ---- }
    { the one selected object that has resize handles (rectangle, ellipse, picture, note), or nil: handles are for a single object }
    function SelectedResizable: TDrawingObject;
    { the side of a handle in design units (a handle is 6 pixels on the screen at any zoom) }
    function ResizeHandleSize: Double;
    { is the whole wire in the area the selection was picked with? (then its end handles move it, otherwise they stretch it) }
    function WireWhollyPicked(L: TDrawLine): Boolean;
    { the chosen wire (not wholly picked) that has an end at P, or nil; End1 says which end }
    function WholeWireEndAt(const P: TDPoint): Boolean;
    function WireEndAt(const P: TDPoint; out End1: Boolean): TDrawLine;
    { where a pointer at that point of the sheet would snap to: the point is turned into a window position (whole pixels) and back, then snapped }
    function ProbeSnap(const P: TDPoint): TDPoint;
    { ---- the red circles of Find ---- }
    procedure SetMarkers(const AMarkers: array of TFindMarker);
    procedure ClearMarkers;
    procedure SelectMarker(Index: Integer);
    function MarkerCount: Integer;
    { scroll the sheet so that a point is in the middle of the window (the zoom is not changed) }
    procedure CenterOnPoint(const P: TDPoint);
    property MarkerSelected: Integer read FMarkerSel;
    { the user clicked a circle on the sheet }
    property OnMarkerClick: TMarkerEvent read FOnMarkerClick write FOnMarkerClick;
    procedure DeleteSelection;
    function SelectedCount: Integer;
    function SelectedObject(Index: Integer): TDrawingObject;
    function SelectedList: TList;
    { tools }
    procedure BeginTool(ATool: TViewTool);
    procedure PaintRef(const P: TDPoint; Remove: Boolean);
    procedure BeginPlace(Meth: TDrawMethod);
    { the reference painter (Generate Symbol References > Use reference painter): a click on a symbol gives it the next number from StartVal, a right click
      takes its number away }
    procedure BeginRefPainter(StartVal: Integer);
    property RefPainterStart: Integer read FRefStart;
    { compatibility: the first version's way to start the ladder tool (same as BeginTool(vtLadder)) }
    procedure BeginLadderTool;
    { The sheet's rung number grid: the existing one, or a new one (one undo step) when the sheet has none; either way it becomes the selection. Nil when no sheet is open or in the symbol editor. }
    function EnsureRungGrid: TDrawRungGrid;
    procedure TakeRungFontFromOtherSheet(AGrid: TDrawRungGrid);
    { The sheet's rung grid, nil when it has none }
    function FindRungGrid: TDrawRungGrid;
    procedure CancelTool;
    { undo / redo }
    procedure BeginChange(const ACaption: String);
    procedure CommitChange(DidChange: Boolean);
    function DoUndo: Boolean;
    function DoRedo: Boolean;
    property Undo: TUndoManager read FUndo;
    { Everything that must follow a change: layout, links, repaint, "modified" }
    procedure AfterEdit;
    { Change one property on every selected object (the mass change) as one undo step }
    function ApplyProperty(const PropName, Value: String): Integer;
    { simulated input, in screen pixels, for the self-test script; the same paths as real events }
    procedure ClickAt(X, Y: Integer; Shift: TShiftState);
    procedure RightClickAt(X, Y: Integer);
    procedure SimMouse(Kind: Integer; X, Y: Integer; Shift: TShiftState; Button: TMouseButton);
    { the mouse wheel turned at X, Y of the view (client coordinates, as the LCL delivers them); a positive Delta zooms in }
    procedure SimWheel(X, Y, Delta: Integer);
    procedure RelayoutAll;
    procedure SaveSnapshot(const FileName: String);
    property Design: TDesignFile read FDesign;
    property Sheet: TDesignSheet read GetSheet;
    property SheetIndex: Integer read FSheetIndex;
    property Zoom: Double read FZoom;
    property ShowGrid: Boolean read FShowGrid write FShowGrid;
    { the grid dots are drawn one pixel wide whatever the zoom (the symbol editor's 1 px grid); the grid itself is not changed }
    property OnePxDots: Boolean read FOnePxDots write FOnePxDots;
    property SnapEnabled: Boolean read GetSnapEnabled write SetSnapEnabled;
    property GridMm: Double read GetGridMm write SetGridMm;
    property Tool: TViewTool read FTool;
    { the symbol that follows the mouse while a symbol is being placed (nil otherwise) }
    property PlaceGhost: TDrawMethod read FGhost;
    property DragMode: Integer read FDragMode;      // for tests: 0 none, 1 move, 2 rubber band, 3 pan ...
    property OnSelectionChange: TViewEvent read FOnSelection write FOnSelection;
    property OnStatus: TStatusEvent read FOnStatus write FOnStatus;
    property OnPosition: TStatusEvent read FOnPosition write FOnPosition;
    { Repeat Directions: +1 or -1 }
    property NameDir: Integer read FNameDir write SetNameDir;
    property PinDir: Integer read FPinDir write SetPinDir;
    property OnModified: TViewEvent read FOnModified write FOnModified;
    property OnToolChanged: TViewEvent read FOnToolChanged write FOnToolChanged;
    property OnDragEnd: TViewEvent read FOnDragEnd write FOnDragEnd;
    { the zoom changed (the wheel, the zoom commands, fitting the page) }
    property OnZoomChanged: TViewEvent read FOnZoomChanged write FOnZoomChanged;
    { the view was drawn, or the pointer moved over it or left it: what the rulers beside it follow }
    property OnViewMoved: TNotifyEvent read FOnViewMoved write FOnViewMoved;
    { the scroll: the design point at the top left of the view }
    property Origin: TDPoint read FOrigin;
    { where the pointer is over the view, in the view's pixels (HasPointer is False when it is not over it) }
    property PointerPixel: TPoint read FPointerPixel;
    property HasPointer: Boolean read FHasPointer;
    { the zoom in per cent: 100 is one pixel to each design unit (0.2 mm) }
    function ZoomPercent: Integer;
    { the properties a draw tool can be given (line colour and style, fill, font ...) and the ones chosen so far }
    function ToolPropDefs(ATool: TViewTool): TPropDefArray;
    function ToolPropValue(ATool: TViewTool; const AName: String): String;
    { gives a pin the values the next pin will have: those of the pin placed last (its number and name counted on) with what was chosen in the Pin tool's panel over them }
    procedure FillPendingPin(Pn: TDrawPin);
    procedure SetToolDefault(ATool: TViewTool; const AName, AValue: String);
    procedure ClearToolDefaults;
    function WireAngleNow: Integer;
    property OnUndoChanged: TViewEvent read FOnUndoChanged write FOnUndoChanged;
    property OnObjectPlaced: TObjectEvent read FOnPlaced write FOnPlaced;
    { compatibility: fired when a ladder has been drawn (OnObjectPlaced also fires, for every kind of object) }
    property OnLadderCreated: TLadderEvent read FOnLadder write FOnLadder;
    { ---- clipboard (TinyCAD's format, "TinyCAD Design") ---- }
    procedure CopyToClipboard;
    { Copy to: write the selected objects to a design file (what Copy puts on the clipboard); returns how many objects were written }
    function CopySelectionToFile(const AFileName: String): Integer;
    procedure CutSelection;
    procedure PasteFromClipboard;
    { Import: read another design (its first sheet) into this sheet; its objects follow the mouse until a click places them.
      Returns how many objects were read, 0 if the file holds no TinyCAD design. Errors opening the file are raised. }
    function ImportFromFile(const AFileName: String): Integer;
    { Insert picture: a picture file becomes an object of the sheet that follows the mouse until a click places it. False, with Err
      saying why, if the file cannot be inserted (nothing is changed then). }
    function InsertPictureFile(const AFileName: String; out Err: String): Boolean;
    procedure DuplicateSelection;
    { ---- the Edit menu's rotate, flip and Z-order (CTinyCadView::ChangeDir, CTinyCadDoc::BringToFront / SendToBack) ---- }
    procedure RotateSelection(NewDir: Integer);
    function AlignSelectionToGrid(AGrid: Double): Integer;
    procedure BringToFront;
    procedure SendToBack;
    function ClipboardHasDrawing: Boolean;
    { for tests: the clipboard's drawing data as text, and replace it with the given text }
    function ClipboardText: String;
    procedure SetClipboardText(const Data: String);
    property Pasting: Boolean read FPasting;
    { ---- editing a polygon: its handles can be dragged and its segments changed from a menu ---- }
    { do one of the polygon menu's actions on the selected polygon, at the clicked point, as one undo step }
    function PolygonAction(PolyAct: TPolyAction; const P: TDPoint): Boolean;
    { the kind of segment given to the points of a polygon that is drawn from now on (Arc_none, Arc_in, Arc_out) }
    procedure SetDrawArcType(Arc: Integer);
    property DrawArcType: Integer read FPolyArc;
    { when True the polygon menus are not shown (a script has no one to choose from them) }
    class var SuppressMenus: Boolean;
    { ---- the pop-up menu of a right click ---- }
    { a right click at a point of the sheet: the object under it is chosen when it is not chosen already (as TinyCAD does) }
    procedure ContextSelectAt(const P: TDPoint);
    { the chosen polygon, when the point is on one of its handles or close to one of its sides: its handle and arc commands apply there }
    function PolygonAt(const P: TDPoint): Boolean;
    { the symbol that is the only object chosen, or nil }
    function SelectedSymbol: TDrawMethod;
    { the rung of the chosen symbol (False when there is none, or it is not in a rung grid) }
    function SymbolRung(out Info: TRungInfo): Boolean;
    { choose the rung of the chosen symbol (0 = work it out from where it is again), as one undo step }
    function SetSymbolRung(Number: Integer): Boolean;
    { Add Rung Reference: a cross reference text (XREF mode 2) under the chosen symbol; returns 'added', 'exists' (the one already there is chosen), 'nosel' or 'noref' (the symbol has no reference) }
    function AddRungReference: String;
    function SelectedLine: TDrawLine;
    function LineMakeStraight(Vertical: Boolean; const P: TDPoint): Boolean;
    function NudgeSelection(DX, DY: Integer): Boolean;
    procedure PressKey(Key: Word; Shift: TShiftState);
    function ArrowKey(var Key: Word; Shift: TShiftState): Boolean;
    function WireCanCut(const P: TDPoint): Boolean;
    function WireCutAt(const P: TDPoint): Boolean;
    { the kind of arc the Arc tool draws: Arc_in or Arc_out (the right click menu of the tool) }
    property ArcToolType: Integer read FArcToolType write SetArcToolType;
    property OnArcTypeChanged: TNotifyEvent read FOnArcTypeChanged write FOnArcTypeChanged;
    { set by the owner: the right click menus of the Polygon and Arc tools; their items (Tag 1 Finish, 2 Cancel,
      3 Finish arc, 10 + kind of arc for the radio items) are made in the form file, and the owner forwards
      their clicks to DrawMenuClick / ArcMenuClick }
    property DrawPopup: TPopupMenu read FDrawPopup write FDrawPopup;
    property ArcPopup: TPopupMenu read FArcPopup write FArcPopup;
    procedure PrepareDrawPopup;
    procedure PrepareArcPopup;
    procedure DrawMenuClick(Sender: TObject);
    procedure ArcMenuClick(Sender: TObject);
    { set by the owner: shows the menu of a right click (without it nothing opens) }
    property OnContext: TContextEvent read FOnContext write FOnContext;
    property OnDblClick;
  end;

implementation


uses UStrings;

var
  { the angle a wire, bus or line is drawn at (free, 90 or 45 degrees): kept for the whole program session, so a new tool,
    a new sheet or a new design still has what was last chosen. A wire starts at 90 degrees, as TinyCAD does. }
  WireAngles: array[TViewTool] of TAngleMode;

{ ===========================================================================
  ToolHint  (function)
  Parameters:
    ATool: TViewTool
  Returns:
    String - what the status bar says while the tool is in use
  Notes:
    A function and not a constant array, because a resourcestring cannot be used in a constant: the text is read when it is shown, so a translation applies.
  =========================================================================== }
function ToolHint(ATool: TViewTool): String;
begin
  case ATool of
    vtSelect: Result := rsSelectClickShiftClickOr;
    vtWire: Result := rsWireClickTheStartClick;
    vtLine: Result := rsLineClickTheStartClick;
    vtPolygon: Result := rsPolygonClickEachCornerDouble;
    vtRect: Result := rsRectangleClickAndDragOr;
    vtCircle: Result := rsCircleClickAndDragOr;
    vtArc: Result := rsArcClickTheStartAnd;
    vtNote: Result := rsNoteClickAndDragA;
    vtCloud: Result := rsCloudClickAndDragA;
    vtLabel: Result := rsLabelClickOnAWire;
    vtJunction: Result := rsJunctionClickWhereWiresMeet;
    vtRulerH: Result := rsHorizontalRulerClickToPlace;
    vtRulerV: Result := rsVerticalRulerClickToPlace;
    vtMeasure: Result := rsMeasureClickPointAThen;
    vtLadder: Result := rsLadderRailsDragARectangle;
    vtXRefLine: Result := rsLineNumberLinkClickThe;
    vtXRefContacts: Result := rsContactsLinkClickTheCoil;
    vtPlace: Result := rsPlaceSymbolClickToPlace;
    vtBus: Result := rsBusClickTheStartClick;
    vtBusSlash: Result := rsBusSlashClickWhereThe;
    vtNoConnect: Result := rsNoConnectClickOnA;
    vtPower: Result := rsPowerSymbolClickToPlace;
    vtText: Result := rsTextClickWhereTheText;
    vtRefPainter: Result := rsReferencePainterClickASymbol;
    vtPin: Result := rsPinClickWhereThePin;
    vtOrigin: Result := rsOriginClickToPutThe;
    vtRungs: Result := rsRungNumbersTheSheetS;
    vtSymbolText: Result := rsSymbolTextClickWhere;
  else
    Result := '';
  end;
end;


{ ===========================================================================
  TSchematicView.Create  (constructor)
  Parameters:
    AOwner: TComponent - the owning component
  Notes:
    Creates the drawing area: transform, selection list, default zoom, double buffering, select
    tool.
  =========================================================================== }
constructor TSchematicView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FT := TTransform.Create;
  FSelected := TList.Create;
  FMarkerSel := -1;
  FArcToolType := Arc_in;
  FZoom := 0.5;
  FOrigin := DPoint(-30, -30);
  FShowGrid := EditDefaults.ShowGrid;
  FNameDir := 1;
  FPinDir := 1;
  FUserFont := TFont.Create;
  FTool := vtSelect;
  FSheetIndex := 0;
  TabStop := True;
  DoubleBuffered := True;
  Color := TColor($C8C8C8);
  ControlStyle := ControlStyle + [csOpaque];
end;

{ ===========================================================================
  TSchematicView.Destroy  (destructor)
  Parameters:  none
  Notes:
    Drops any active tool, then frees the placement symbol, the undo manager, the selection list
    and the transform.
  =========================================================================== }
destructor TSchematicView.Destroy;
begin
  FUserFont.Free;
  FreeTool;
  FGhost.Free;
  FUndo.Free;
  FSelected.Free;
  FT.Free;
  ClearToolDefaults;
  inherited Destroy;
end;

{ ===========================================================================
  TSchematicView.GetSheet  (function)
  Parameters:  none
  Returns:
    TDesignSheet - the sheet, or nil when no document is open
  Notes:
    The sheet being shown (design plus sheet index).
  =========================================================================== }
function TSchematicView.GetSheet: TDesignSheet;
begin
  if (FDesign <> nil) and (FSheetIndex >= 0) and (FSheetIndex < FDesign.SheetCount) then
    Result := FDesign.Sheets[FSheetIndex]
  else
    Result := nil;
end;

{ ===========================================================================
  TSchematicView.Status  (procedure)
  Parameters:
    const Msg: String - the message
  Notes:
    Passes a message to the status-bar handler, if there is one.
  =========================================================================== }
procedure TSchematicView.Status(const Msg: String);
begin
  if Assigned(FOnStatus) then
    FOnStatus(Self, Msg);
end;

{ ===========================================================================
  TSchematicView.ExpandPhaseGroups  (procedure)
  Parameters:  none
  Notes:
    The three wires of a 3-phase bus are picked together: when one of them is selected the other
    two are too (UPhases). Done whenever the selection changes, so a click, a box dragged to the
    right, Select All Alike and an undo all give the whole bus.
  =========================================================================== }
procedure TSchematicView.ExpandPhaseGroups;
var
  i, g: Integer;
  Groups: array of Integer;
  Have: Boolean;
  Members: TList;
  k: Integer;
begin
  if Sheet = nil then
    Exit;
  SetLength(Groups, 0);
  for i := 0 to FSelected.Count - 1 do
  begin
    g := PhaseGroupOf(TDrawingObject(FSelected[i]));
    if g <> 0 then
    begin
      Have := False;
      for k := 0 to High(Groups) do
        if Groups[k] = g then
          Have := True;
      if not Have then
      begin
        SetLength(Groups, Length(Groups) + 1);
        Groups[High(Groups)] := g;
      end;
    end;
  end;
  if Length(Groups) = 0 then
    Exit;
  Members := TList.Create;
  try
    for k := 0 to High(Groups) do
    begin
      PhaseGroupMembers(Sheet.Drawing, Groups[k], Members);
      for i := 0 to Members.Count - 1 do
        if FSelected.IndexOf(Members[i]) < 0 then
          FSelected.Add(Members[i]);
    end;
  finally
    Members.Free;
  end;
end;

{ ===========================================================================
  TSchematicView.PhaseGroupInside  (function)
  Parameters:
    AGroup: Integer - whole number
    L: Double - number
    R: Double - the XML reader, positioned on this element
    T: Double - number
    B: Double - a point, in design units
  Returns:
    Boolean
  Notes:
    A box dragged to the left only takes what it holds completely: for a 3-phase bus that is all
    three wires.
  =========================================================================== }
function TSchematicView.PhaseGroupInside(AGroup: Integer; L, R, T, B: Double): Boolean;
var
  i: Integer;
begin
  Result := True;
  for i := 0 to Sheet.Drawing.Count - 1 do
    if PhaseGroupOf(Sheet.Drawing[i]) = AGroup then
      if not Sheet.Drawing[i].IsCompletelyInside(L, R, T, B) then
        Result := False;
end;

{ ===========================================================================
  TSchematicView.ReconcileBuses  (procedure)
  Parameters:  none
  Notes:
    Makes the 3-phase buses of the sheet agree with what they say they are
    (UPhases.ReconcilePhases): the outer wires of a bus just drawn, made again when the spacing
    was changed, taken away when the bus was changed to one phase. Part of ending a change, so
    it is one undo step with what caused it.
  =========================================================================== }
procedure TSchematicView.ReconcileBuses;
var
  Gone: TList;
begin
  if (FDesign = nil) or (Sheet = nil) then
    Exit;
  Gone := TList.Create;
  try
    if ReconcilePhases(FDesign, Sheet, Gone) then
      PruneSelection;
  finally
    Gone.Free;
  end;
  ExpandPhaseGroups;
end;

{ ===========================================================================
  TSchematicView.PlacePhaseCopies  (procedure)
  Parameters:
    APlaced: TDrawMethod
  Notes:
    When a pin of the symbol is on the free end of a wire of a 3-phase bus, the symbol is copied
    to the free ends of the other two wires, so a fuse put on a 3-phase bus is three fuses. The
    copies are symbols of their own: they can be moved and deleted one at a time. Each pin is
    looked at; the first one on such an end decides.
  =========================================================================== }
procedure TSchematicView.PlacePhaseCopies(APlaced: TDrawMethod);
var
  Pts: TDPointArray;
  Shifts: TPhaseSegments;
  i, k: Integer;
  C: TDrawMethod;
begin
  Pts := APlaced.ActivePoints;
  for i := 0 to High(Pts) do
    if PhaseCompanionEnds(Sheet.Drawing, Pts[i], Shifts) then
    begin
      for k := 0 to High(Shifts) do
      begin
        C := APlaced.Clone as TDrawMethod;
        C.PointA := DPoint(APlaced.PointA.x + Shifts[k].A.x, APlaced.PointA.y + Shifts[k].A.y);
        AddNew(C);
        C.UpdateLayout;
        FSelected.Add(C);
      end;
      Exit;
    end;
end;

{ ===========================================================================
  TSchematicView.SelectionChanged  (procedure)
  Parameters:  none
  Notes:
    Tells the owner the selection changed (so the ribbon can rebuild its property editors) and
    repaints.
  =========================================================================== }
procedure TSchematicView.SelectionChanged;
begin
  ExpandPhaseGroups;
  { an object that is the only one selected notes what it needs for being resized by its handles (TinyCAD does this in BeginEdit) }
  if (FSelected.Count = 1) and (not FPasting) then
    TDrawingObject(FSelected[0]).PrepareResize;
  if Assigned(FOnSelection) then
    FOnSelection(Self);
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.ApplyTransform  (procedure)
  Parameters:  none
  Notes:
    Loads the current zoom and origin into the screen transform and hands the zoom to the sheet
    options (hit tests use it).
  =========================================================================== }
procedure TSchematicView.ApplyTransform;
begin
  FT.SetZoomFactor(FZoom);
  FT.SetOrigin(FOrigin);
  if Sheet <> nil then
    Sheet.Options.ZoomFactor := FZoom;
end;

{ ===========================================================================
  TSchematicView.ScreenToDesign  (function)
  Parameters:
    const P: TPoint - pixel position inside the control
  Returns:
    TDPoint - the design point
  Notes:
    Converts a pixel position to design units using the current zoom and origin.
  =========================================================================== }
function TSchematicView.ScreenToDesign(const P: TPoint): TDPoint;
begin
  Result := DPoint(P.x / FZoom + FOrigin.x, P.y / FZoom + FOrigin.y);
end;

{ ===========================================================================
  TSchematicView.DesignToScreen  (function)
  Parameters:
    const P: TDPoint - design point
  Returns:
    TPoint - the pixel position
  Notes:
    Converts a design point to a pixel position.
  =========================================================================== }
function TSchematicView.DesignToScreen(const P: TDPoint): TPoint;
begin
  Result := Point(Round((P.x - FOrigin.x) * FZoom), Round((P.y - FOrigin.y) * FZoom));
end;

{ ===========================================================================
  TSchematicView.ReportPosition  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
  Notes:
    What TinyCAD's position bar shows (CTinyCadView::OnMouseMove): the pointer's position
    snapped to the grid (when snapping is on) and measured from the sheet's origin (when it has
    one), as text in the units of the sheet. It goes to the position bar through OnPosition, or
    to the status message when nothing shows the bar.
  =========================================================================== }
procedure TSchematicView.ReportPosition(const P: TDPoint);
var
  Q: TDPoint;
  Msg: String;
begin
  if Sheet = nil then
    Exit;
  Q := SnapPoint(P);
  if Sheet.Options.HasOrigin then
    Q := DPoint(Q.x - Sheet.Options.Origin.x, Q.y - Sheet.Options.Origin.y);
  Msg := PositionText(Q.x / UNITS_PER_MM, Q.y / UNITS_PER_MM, Sheet.Options.Units);
  if Assigned(FOnPosition) then
    FOnPosition(Self, Msg)
  else
    Status(Msg);
end;

{ ===========================================================================
  TSchematicView.SetNameDir  (procedure)
  Parameters:
    Value: Integer - the value
  Notes:
    Repeat Directions, Name Increment / Name Decrement: the way the number in the next label or
    text to place counts (TinyCAD keeps this per sheet; here it is per open design).
  =========================================================================== }
procedure TSchematicView.SetNameDir(Value: Integer);
begin
  if Value >= 0 then
    FNameDir := 1
  else
    FNameDir := -1;
end;

{ ===========================================================================
  TSchematicView.SetPinDir  (procedure)
  Parameters:
    Value: Integer - the value
  Notes:
    Repeat Directions, Pin Increment / Pin Decrement: used when pins are placed one after
    another (in the symbol editor, whose window is not part of this port yet).
  =========================================================================== }
procedure TSchematicView.SetPinDir(Value: Integer);
begin
  if Value >= 0 then
    FPinDir := 1
  else
    FPinDir := -1;
end;

{ ===========================================================================
  TSchematicView.NextPlacedText  (function)
  Parameters:
    const DefaultText: String - text
    Id: Integer - whole number
    const LastText: String - text
  Returns:
    String
  Notes:
    TinyCAD's label and text tools keep the text in a box that is counted each time one is
    placed. Here the next label or text starts as the one placed last, counted by the name
    direction (URepeat.IncrementLabelText): as it reads now if it is still there (so a text
    typed over it is counted from), otherwise as it was when placed (after an undo, say). The
    first one has the default text, and so has one that would have no text at all.
  =========================================================================== }
function TSchematicView.NextPlacedText(const DefaultText: String; Id: Integer; const LastText: String): String;
var
  i: Integer;
  Base: String;
begin
  if LastText = '' then
    Exit(DefaultText);
  Base := LastText;
  if (Id <> 0) and (Sheet <> nil) then
    for i := 0 to Sheet.Drawing.Count - 1 do
      if Sheet.Drawing[i].Id = Id then
      begin
        if Sheet.Drawing[i] is TDrawLabel then
          Base := TDrawLabel(Sheet.Drawing[i]).Str
        else if Sheet.Drawing[i] is TDrawText then
          Base := TDrawText(Sheet.Drawing[i]).Str;
        Break;
      end;
  Result := IncrementLabelText(Base, FNameDir);
  if Result = '' then
    Result := DefaultText;
end;

{ ===========================================================================
  TSchematicView.FloatTextString  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    With the Text tool chosen a text follows the pointer until it is placed; this is what it
    says, the same text that clicking will place (the last one counted on).
  =========================================================================== }
function TSchematicView.FloatTextString: String;
begin
  Result := FloatTextFor(FTool);
end;

{ ===========================================================================
  TSchematicView.FloatTextFor  (function)
  Parameters:
    ATool: TViewTool
  Returns:
    String
  Notes:
    What was typed in the tool's text box, otherwise the last one placed counted on (the default
    text for the first).
  =========================================================================== }
function TSchematicView.FloatTextFor(ATool: TViewTool): String;
begin
  if (FToolDefaults[ATool] <> nil) and (FToolDefaults[ATool].Values['text'] <> '') then
    Result := FToolDefaults[ATool].Values['text']       // typed in the tool's text box
  else if ATool = vtLabel then
    Result := NextPlacedText('LABEL', FLastLabelId, FLastLabelText)
  else
    Result := NextPlacedText('Text', FLastTextId, FLastTextText);
end;

{ ===========================================================================
  TSchematicView.UserFontInfo  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    For the self-test script.
  =========================================================================== }
function TSchematicView.UserFontInfo: String;
begin
  Result := FUserFont.Name + '|' + IntToStr(FUserFont.Height) + '|' + IntToStr(Ord(fsBold in FUserFont.Style)) + '|' + IntToStr(Ord(fsItalic in FUserFont.Style));
end;

{ ===========================================================================
  TSchematicView.FloatingText  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    A text follows the pointer while the Text tool is chosen and the pointer has been over the
    view; after one is placed the next one (counted on) follows in its turn.
  =========================================================================== }
function TSchematicView.FloatingText: String;
begin
  if (FTool in [vtText, vtLabel]) and FHaveMouse then
    Result := FloatTextString
  else
    Result := '';
end;

{ ===========================================================================
  TSchematicView.SnapPoint  (function)
  Parameters:
    const P: TDPoint - design point
  Returns:
    TDPoint - the snapped point
  Notes:
    Snaps a point to the sheet's grid (unchanged when grid snapping is off).
  =========================================================================== }
function TSchematicView.SnapPoint(const P: TDPoint): TDPoint;
begin
  if Sheet <> nil then
    Result := Sheet.Snap.Snap(P)
  else
    Result := P;
end;

{ ---------------------------------------------------------------- grid }

{ ===========================================================================
  TSchematicView.GetSnapEnabled  (function)
  Parameters:  none
  Returns:
    Boolean - True when on
  Notes:
    Whether snapping to the grid is on for the current sheet.
  =========================================================================== }
function TSchematicView.GetSnapEnabled: Boolean;
begin
  Result := (Sheet <> nil) and (Sheet.Snap.GridSnap <> 0);
end;

{ ===========================================================================
  TSchematicView.SetSnapEnabled  (procedure)
  Parameters:
    Value: Boolean - True to snap
  Notes:
    Turns snapping to the grid on or off for the current sheet.
  =========================================================================== }
procedure TSchematicView.SetSnapEnabled(Value: Boolean);
begin
  if Sheet = nil then
    Exit;
  Sheet.Snap.GridSnap := Ord(Value);
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.GetGridMm  (function)
  Parameters:  none
  Returns:
    Double - the spacing in mm (2 when there is no sheet)
  Notes:
    The grid spacing of the current sheet in millimetres.
  =========================================================================== }
function TSchematicView.GetGridMm: Double;
begin
  if Sheet <> nil then
    Result := Sheet.Snap.Grid / UNITS_PER_MM
  else
    Result := 2;
end;

{ ===========================================================================
  TSchematicView.SetGridMm  (procedure)
  Parameters:
    Value: Double - spacing in mm
  Notes:
    Sets the grid spacing of the current sheet; zero or negative sizes are ignored.
  =========================================================================== }
procedure TSchematicView.SetGridMm(Value: Double);
begin
  if (Sheet = nil) or (Value <= 0) then
    Exit;
  Sheet.Snap.Grid := Value * UNITS_PER_MM;
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.RelayoutAll  (procedure)
  Parameters:  none
  Notes:
    Recalculates layout of every object on the sheet and repaints.
  =========================================================================== }
procedure TSchematicView.RelayoutAll;
begin
  if Sheet <> nil then
    Sheet.UpdateLayout;
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.AfterEdit  (procedure)
  Parameters:  none
  Notes:
    Everything that must follow a change: object layout, linked text, repaint, and the modified
    and undo-state notifications.
  =========================================================================== }
procedure TSchematicView.AfterEdit;
begin
  if (FDesign <> nil) and (Sheet <> nil) then
  begin
    Sheet.UpdateLayout;
    UpdateLinks(FDesign);
  end;
  Invalidate;
  if Assigned(FOnModified) then
    FOnModified(Self);
  if Assigned(FOnUndoChanged) then
    FOnUndoChanged(Self);
end;

{ ---------------------------------------------------------------- undo }

{ ===========================================================================
  TSchematicView.SelectedIds  (function)
  Parameters:  none
  Returns:
    TIntArray - the ids
  Notes:
    The object ids of the selection, kept in undo snapshots because object pointers do not
    survive an undo.
  =========================================================================== }
function TSchematicView.SelectedIds: TIntArray;
var
  i: Integer;
begin
  SetLength(Result, FSelected.Count);
  for i := 0 to FSelected.Count - 1 do Result[i] := TDrawingObject(FSelected[i]).Id;
end;

{ ===========================================================================
  TSchematicView.RestoreSelection  (procedure)
  Parameters:
    const Ids: TIntArray - the ids to select
  Notes:
    Re-selects objects by id after an undo, redo or reload; ids that no longer exist or are on
    another sheet are skipped.
  =========================================================================== }
procedure TSchematicView.RestoreSelection(const Ids: TIntArray);
var
  i, Si: Integer;
  O: TDrawingObject;
begin
  FSelected.Clear;
  for i := 0 to High(Ids) do
  begin
    O := FDesign.FindObject(Ids[i], Si);
    if (O <> nil) and (Si = FSheetIndex) then
      FSelected.Add(O);
  end;
end;

{ ===========================================================================
  TSchematicView.BeginChange  (procedure)
  Parameters:
    const ACaption: String - name of the action for Undo
  Notes:
    Starts an undoable action: takes the pending snapshot. Pair with CommitChange.
  =========================================================================== }
procedure TSchematicView.BeginChange(const ACaption: String);
begin
  if FUndo <> nil then
    FUndo.BeginChange(ACaption, SelectedIds, FSheetIndex);
end;

{ ===========================================================================
  TSchematicView.CommitChange  (procedure)
  Parameters:
    DidChange: Boolean - True if the design changed
  Notes:
    Ends an undoable action: keeps the snapshot as an undo step and refreshes everything when
    something changed, otherwise discards it.
  =========================================================================== }
procedure TSchematicView.CommitChange(DidChange: Boolean);
begin
  if FUndo = nil then
    Exit;
  if DidChange then
  begin
    ReconcileBuses;
    FUndo.CommitChange;
    AfterEdit;
  end
  else
    FUndo.DiscardChange;
end;

{ ===========================================================================
  TSchematicView.DoUndo  (function)
  Parameters:  none
  Returns:
    Boolean - True if something was undone
  Notes:
    Undoes the last action: cancels any tool, restores the previous design, re-selects what was
    selected and refreshes.
  =========================================================================== }
function TSchematicView.DoUndo: Boolean;
var
  Back: TIntArray;
  Sh: Integer;
begin
  Result := False;
  if (FUndo = nil) or (not FUndo.CanUndo) then
    Exit;
  FreeTool;
  FTool := vtSelect;
  Result := FUndo.Undo(SelectedIds, FSheetIndex, Back, Sh);
  if Result then
  begin
    FSheetIndex := Max(0, Min(Sh, FDesign.SheetCount - 1));
    RestoreSelection(Back);
    Sheet.UpdateLayout;
    UpdateLinks(FDesign);
    if Assigned(FOnToolChanged) then
      FOnToolChanged(Self);
    SelectionChanged;
    if Assigned(FOnModified) then
      FOnModified(Self);
    if Assigned(FOnUndoChanged) then
      FOnUndoChanged(Self);
  end;
end;

{ ===========================================================================
  TSchematicView.DoRedo  (function)
  Parameters:  none
  Returns:
    Boolean - True if something was redone
  Notes:
    Redoes the last undone action, in the same way as DoUndo.
  =========================================================================== }
function TSchematicView.DoRedo: Boolean;
var
  Back: TIntArray;
  Sh: Integer;
begin
  Result := False;
  if (FUndo = nil) or (not FUndo.CanRedo) then
    Exit;
  FreeTool;
  FTool := vtSelect;
  Result := FUndo.Redo(SelectedIds, FSheetIndex, Back, Sh);
  if Result then
  begin
    FSheetIndex := Max(0, Min(Sh, FDesign.SheetCount - 1));
    RestoreSelection(Back);
    Sheet.UpdateLayout;
    UpdateLinks(FDesign);
    if Assigned(FOnToolChanged) then
      FOnToolChanged(Self);
    SelectionChanged;
    if Assigned(FOnModified) then
      FOnModified(Self);
    if Assigned(FOnUndoChanged) then
      FOnUndoChanged(Self);
  end;
end;

{ ===========================================================================
  TSchematicView.ApplyProperty  (function)
  Parameters:
    const PropName: String - the property name
    const Value: String - the new value as text
  Returns:
    Integer - how many objects changed
  Notes:
    The mass change from the ribbon: sets one property on every selected object as a single undo
    step.
  =========================================================================== }
function TSchematicView.ApplyProperty(const PropName, Value: String): Integer;
begin
  Result := 0;
  if (Sheet = nil) or (FSelected.Count = 0) then
    Exit;
  BeginChange(Format(rsChange, [PropName]));
  Result := SetPropAll(FSelected, PropName, Value);
  CommitChange(Result > 0);
end;

{ ---------------------------------------------------------------- document / view }

{ ===========================================================================
  TSchematicView.SetDesign  (procedure)
  Parameters:
    ADesign: TDesignFile - the design, or nil
    ASheetIndex: Integer - the sheet to show
  Notes:
    Shows a design (or none): drops tools and selection, creates a fresh undo manager, updates
    links, fits the page.
  =========================================================================== }
procedure TSchematicView.SetDesign(ADesign: TDesignFile; ASheetIndex: Integer);
begin
  FreeTool;
  FTool := vtSelect;
  FSelected.Clear;
  FreeAndNil(FUndo);
  FDesign := ADesign;
  FSheetIndex := ASheetIndex;
  if FDesign <> nil then
  begin
    InitUserFont;
    FUndo := TUndoManager.Create(FDesign);
    UpdateLinks(FDesign);
  end;
  RelayoutAll;
  ZoomFit;
  SelectionChanged;
  if Assigned(FOnUndoChanged) then
    FOnUndoChanged(Self);
end;

{ ===========================================================================
  TSchematicView.SetSheetIndex  (procedure)
  Parameters:
    AIndex: Integer - zero-based sheet number
  Notes:
    Switches to another sheet of the same design: drops tools and selection and fits the page.
  =========================================================================== }
procedure TSchematicView.SetSheetIndex(AIndex: Integer);
begin
  FreeTool;
  FTool := vtSelect;
  FSelected.Clear;
  FSheetIndex := AIndex;
  RelayoutAll;
  ZoomFit;
  SelectionChanged;
end;

{ ===========================================================================
  TSchematicView.ZoomFit  (procedure)
  Parameters:  none
  Notes:
    Zooms and centres so the whole page fits in the control.
  =========================================================================== }
procedure TSchematicView.ZoomFit;
var
  W, H: Integer;
begin
  if Sheet = nil then
    Exit;
  W := Max(50, ClientWidth - 40);
  H := Max(50, ClientHeight - 40);
  FZoom := Min(W / Sheet.Details.PageWidth, H / Sheet.Details.PageHeight);
  FOrigin := DPoint(-(ClientWidth / FZoom - Sheet.Details.PageWidth) / 2,
                    -(ClientHeight / FZoom - Sheet.Details.PageHeight) / 2);
  FAutoFit := True;
  Invalidate;
  if Assigned(FOnZoomChanged) then
    FOnZoomChanged(Self);
end;

{ ===========================================================================
  TSchematicView.SetZoomAt  (procedure)
  Parameters:
    NewZoom: Double - the requested zoom factor
    const Focus: TPoint - pixel position that must not move
  Notes:
    Sets the zoom (limited to 5% to 800%) keeping the design point under Focus where it is on
    screen.
  =========================================================================== }
procedure TSchematicView.SetZoomAt(NewZoom: Double; const Focus: TPoint);
var
  Before: TDPoint;
begin
  NewZoom := Max(0.05, Min(8.0, NewZoom));
  Before := ScreenToDesign(Focus);
  FZoom := NewZoom;
  FOrigin := DPoint(Before.x - Focus.x / FZoom, Before.y - Focus.y / FZoom);
  FAutoFit := False;
  Invalidate;
  if Assigned(FOnZoomChanged) then
    FOnZoomChanged(Self);
end;

{ ===========================================================================
  TSchematicView.ZoomBy  (procedure)
  Parameters:
    Factor: Double - e.g. 1.25 to zoom in
  Notes:
    Multiplies the zoom by a factor about the centre of the control.
  =========================================================================== }
procedure TSchematicView.ZoomBy(Factor: Double);
begin
  SetZoomAt(FZoom * Factor, Point(ClientWidth div 2, ClientHeight div 2));
end;

{ ===========================================================================
  TSchematicView.ZoomActual  (procedure)
  Parameters:  none
  Notes:
    Sets 100% zoom about the centre of the control.
  =========================================================================== }
procedure TSchematicView.ZoomActual;
begin
  SetZoomAt(1.0, Point(ClientWidth div 2, ClientHeight div 2));
end;

{ ===========================================================================
  TSchematicView.Resize  (procedure)
  Parameters:  none
  Notes:
    Repaints when the control changes size.
  =========================================================================== }
procedure TSchematicView.Resize;
begin
  inherited Resize;
  if FAutoFit and (Sheet <> nil) and (ClientWidth > 0) then
    ZoomFit;      // still showing the whole page: keep it that way
  Invalidate;
end;

{ ---------------------------------------------------------------- painting }

{ ===========================================================================
  TSchematicView.PaintPreview  (procedure)
  Parameters:
    C: TCanvas - the canvas to draw on
  Notes:
    Draws what the active tool is showing on top of the drawing: the wire rubber band with its
    sticking ring and junction dot, the polygon in progress, the shape outline, the link target,
    or the symbol being placed.
  =========================================================================== }
procedure TSchematicView.PaintPreview(C: TCanvas);
var
  Corner, Q: TDPoint;
  P1, P2, P3: TPoint;
  i, R: Integer;
  WireCol: Cardinal;
  Pts: array of TPoint;
  ArcsUsed: Boolean;
  Tmp: TDrawPolygon;
  Tmp2: TDrawText;
  TmpL: TDrawLabel;
  Tmp3: TDrawingObject;
  TmpPainter: TSchematicPainter;
  Painter: TSchematicPainter;
  RubberLine: TDrawLine;
begin
  if Sheet = nil then
    Exit;
  C.Brush.Style := bsClear;
  case FTool of
    vtWire, vtLine, vtBus:
      if FWire <> nil then
      begin
        FWire.Preview(Corner);
        if FTool = vtWire then
          WireCol := Sheet.Options.Colors.Get(UC_WIRE)
        else if FTool = vtBus then
          WireCol := Sheet.Options.Colors.Get(UC_BUS)
        else
          WireCol := 0;
        C.Pen.Style := psSolid;
        C.Pen.Width := 1;
        C.Pen.Color := TColor(WireCol);
        if FWire.Segment = 0 then
        begin
          { drawn with the properties chosen in the tool panel (width, style), as it will be once confirmed;
            a wire or bus is red until then, as TinyCAD does }
          case FTool of
            vtWire: RubberLine := TDrawLine.CreateKind(Sheet.Options, xWire);
            vtBus: RubberLine := TDrawLine.CreateKind(Sheet.Options, xBus);
          else
            RubberLine := TDrawLine.CreateKind(Sheet.Options, xLineEx2);
          end;
          if FToolDefaults[FTool] <> nil then
            for i := 0 to FToolDefaults[FTool].Count - 1 do
              SetProp(RubberLine, FToolDefaults[FTool].Names[i], FToolDefaults[FTool].ValueFromIndex[i]);
          TmpPainter := TSchematicPainter.Create(C, FT);
          try
            if FTool in [vtWire, vtBus] then
              TmpPainter.ForceLineColor(cRED);
            RubberLine.PointA := FWire.A; RubberLine.PointB := Corner;
            TmpPainter.PaintObject(RubberLine, False);
            RubberLine.PointA := Corner; RubberLine.PointB := FWire.B;
            TmpPainter.PaintObject(RubberLine, False);
          finally
            TmpPainter.Free;
            RubberLine.Free;
          end;
        end;
        if FWire.IsStuck then
        begin
          { a ring shows that the end has stuck to a pin or wire (TinyCAD's PaintConnectPoint: HIGHLIGHT_SIZE, 10 design units, from the centre, so it grows
            and shrinks with the zoom); a dot that a junction will be made }
          P3 := FT.Scale(FWire.B);
          R := Max(4, Round(10 * FZoom));
          C.Pen.Color := TColor($0000FF);
          C.Ellipse(P3.x - R, P3.y - R, P3.x + R + 1, P3.y + R + 1);
          if FWire.IsJunction then
          begin
            C.Brush.Style := bsSolid;
            C.Brush.Color := TColor(Sheet.Options.Colors.Get(UC_JUNCTION));
            C.Pen.Color := C.Brush.Color;
            R := Max(2, Round(3 * FZoom));
            C.Ellipse(P3.x - R, P3.y - R, P3.x + R + 1, P3.y + R + 1);
            C.Brush.Style := bsClear;
          end;
        end;
      end;
    vtPolygon, vtArc:
      if Length(FPoly) > 0 then
      begin
        SetLength(Pts, Length(FPoly) + 1);
        for i := 0 to High(FPoly) do Pts[i] := FT.Scale(FPoly[i]);
        Pts[High(Pts)] := FT.Scale(FShapeEnd);
        C.Pen.Style := psSolid; C.Pen.Width := 1; C.Pen.Color := clBlack;
        C.Polyline(Pts);
        { with arcs the real shape is curved: show it as it will be drawn }
        if (FTool = vtArc) or (FPolyArc <> Arc_none) then
          ArcsUsed := True else begin ArcsUsed := False; for i := 0 to High(FPolyArcs) do if FPolyArcs[i] <> Arc_none then
          ArcsUsed := True; end;
        if ArcsUsed then
        begin
          Tmp := TDrawPolygon.Create(Sheet.Options);
          try
            Tmp.PointA := FPoly[0];
            SetLength(Tmp.Handles, Length(FPoly) + 1);
            for i := 0 to High(Tmp.Handles) do
            begin
              if i <= High(FPoly) then
                Tmp.Handles[i].X := FPoly[i].x - FPoly[0].x
              else
                Tmp.Handles[i].X := FShapeEnd.x - FPoly[0].x;
              if i <= High(FPoly) then
                Tmp.Handles[i].Y := FPoly[i].y - FPoly[0].y
              else
                Tmp.Handles[i].Y := FShapeEnd.y - FPoly[0].y;
              if i = 0 then
                Tmp.Handles[i].Arc := Arc_none
              else if i <= High(FPolyArcs) then
                Tmp.Handles[i].Arc := FPolyArcs[i]
              else if FTool = vtArc then
                Tmp.Handles[i].Arc := FArcToolType
              else
                Tmp.Handles[i].Arc := FPolyArc;
              Tmp.Handles[i].Control := DPointInvalid;
              Tmp.Handles[i].FlattenedSegment := 0;
            end;
            Tmp.CalcBoundingRect;
            TmpPainter := TSchematicPainter.Create(C, FT);
            try
              TmpPainter.PaintObject(Tmp, False);
            finally
              TmpPainter.Free;
            end;
          finally
            Tmp.Free;
          end;
        end;
      end;
    vtRect, vtCircle, vtNote, vtCloud, vtMeasure, vtLadder:
      if FStage = 1 then
      begin
        P1 := FT.Scale(FShapeStart);
        P2 := FT.Scale(FShapeEnd);
        C.Pen.Style := psDot; C.Pen.Width := 1; C.Pen.Color := TColor($0080FF);
        if FTool = vtMeasure then
        begin
          C.MoveTo(P1.x, P1.y); C.LineTo(P2.x, P2.y);
        end
        else if FTool = vtCircle then
          C.Ellipse(Min(P1.x, P2.x), Min(P1.y, P2.y), Max(P1.x, P2.x), Max(P1.y, P2.y))
        else
          C.Rectangle(Min(P1.x, P2.x), Min(P1.y, P2.y), Max(P1.x, P2.x), Max(P1.y, P2.y));
      end;
    vtXRefLine, vtXRefContacts:
      if FXTarget <> nil then
      begin
        Painter := TSchematicPainter.Create(C, FT);
        try
          Painter.PaintObject(FXTarget, True);
        finally
          Painter.Free;
        end;
      end;
    vtText:
      if FHaveMouse then
      begin
        { the text about to be placed follows the pointer }
        Tmp2 := TDrawText.Create(Sheet.Options);
        try
          Tmp2.Dir := 3;
          Tmp2.PointA := SnapPoint(FMouseDesign);
          if FToolDefaults[vtText] <> nil then
            for i := 0 to FToolDefaults[vtText].Count - 1 do
              SetProp(Tmp2, FToolDefaults[vtText].Names[i], FToolDefaults[vtText].ValueFromIndex[i]);
          Tmp2.Str := FloatTextString;
          Tmp2.UpdateLayout;
          Painter := TSchematicPainter.Create(C, FT);
          try
            Painter.PaintObject(Tmp2, True);
          finally
            Painter.Free;
          end;
        finally
          Tmp2.Free;
        end;
      end;
    vtJunction, vtNoConnect, vtPower, vtBusSlash:
      if FHaveMouse then
      begin
        { a ghost of what a click will place follows the pointer }
        Tmp3 := MakeFloat(FTool, SnapPoint(FMouseDesign));
        try
          Painter := TSchematicPainter.Create(C, FT);
          try
            Painter.PaintObject(Tmp3, True);
          finally
            Painter.Free;
          end;
        finally
          Tmp3.Free;
        end;
      end;
    vtLabel:
      if FHaveMouse then
      begin
        { the label about to be placed follows the pointer }
        TmpL := TDrawLabel.Create(Sheet.Options);
        try
          TmpL.Dir := 3;
          if FToolDefaults[vtLabel] <> nil then
            for i := 0 to FToolDefaults[vtLabel].Count - 1 do
              SetProp(TmpL, FToolDefaults[vtLabel].Names[i], FToolDefaults[vtLabel].ValueFromIndex[i]);
          TmpL.Str := FloatTextString;
          TmpL.ActivePoint := SnapPoint(FMouseDesign);
          TmpL.PointA := TmpL.ActivePoint;
          TmpL.UpdateLayout;
          Painter := TSchematicPainter.Create(C, FT);
          try
            Painter.PaintObject(TmpL, True);
          finally
            Painter.Free;
          end;
        finally
          TmpL.Free;
        end;
      end;
  end;
  if (FTool = vtPlace) and (FGhost <> nil) then
  begin
    Painter := TSchematicPainter.Create(C, FT);
    try
      Painter.PaintObject(FGhost, True);
    finally
      Painter.Free;
    end;
  end;
  Q := Q; Corner := Corner;
end;

{ ===========================================================================
  TSchematicView.RenderTo  (procedure)
  Parameters:
    ABitmap: TBitmap - the bitmap, resized to the control
  Notes:
    Draws everything (page, border, objects, tool preview, selection box) into a bitmap; used
    both for painting and for saving screenshots.
  =========================================================================== }
procedure TSchematicView.RenderTo(ABitmap: TBitmap);
var
  Painter: TSchematicPainter;
  i: Integer;
begin
  ABitmap.SetSize(Max(1, ClientWidth), Max(1, ClientHeight));
  ABitmap.Canvas.Brush.Color := Color;
  ABitmap.Canvas.FillRect(0, 0, ABitmap.Width, ABitmap.Height);
  if Sheet = nil then
    Exit;
  ApplyTransform;
  Painter := TSchematicPainter.Create(ABitmap.Canvas, FT);
  try
    Painter.OnePxDots := FOnePxDots;
    Painter.PaintPage(Sheet, FShowGrid, Rect(0, 0, ABitmap.Width, ABitmap.Height), FDesign.FileName,
      SheetsText(FDesign, FSheetIndex), DocNoText(FDesign, FSheetIndex));
    Painter.PaintSheet(Sheet, FSelected);
    if (FTool = vtSelect) and (SelectedPolygon <> nil) and (not FPasting) then
      Painter.PaintPolygonHandles(SelectedPolygon);
    if (FTool = vtSelect) and (not FPasting) then
      for i := 0 to FSelected.Count - 1 do
        if TObject(FSelected[i]) is TDrawLine then
          Painter.PaintLineHandles(TDrawLine(FSelected[i]));      { the small squares at the two ends of a chosen wire, bus or line }
    if SelectedResizable <> nil then
      Painter.PaintResizeHandles(SelectedResizable, ResizeHandleSize);
    if Sheet.Options.EditLibrary and Sheet.Options.HasOrigin then
      Painter.PaintOriginMarker(Sheet.Options.Origin);
    for i := 0 to High(FMarkers) do
      if FMarkers[i].Sheet = FSheetIndex then
        Painter.PaintErrorMarker(FMarkers[i].Point, i = FMarkerSel);
  finally
    Painter.Free;
  end;
  PaintPreview(ABitmap.Canvas);
  { rubber band for the select tool }
  if FDragMode = 2 then
  begin
    ABitmap.Canvas.Pen.Style := psDot;
    ABitmap.Canvas.Pen.Color := TColor($0080FF);
    ABitmap.Canvas.Pen.Width := 1;
    ABitmap.Canvas.Brush.Style := bsClear;
    ABitmap.Canvas.Rectangle(Min(FT.Scale(FDragStart).x, FT.Scale(FDragLast).x), Min(FT.Scale(FDragStart).y, FT.Scale(FDragLast).y),
                             Max(FT.Scale(FDragStart).x, FT.Scale(FDragLast).x), Max(FT.Scale(FDragStart).y, FT.Scale(FDragLast).y));
  end;
end;

{ ===========================================================================
  TSchematicView.Paint  (procedure)
  Parameters:  none
  Notes:
    Paints the control: renders into an off-screen bitmap and copies it, so there is no flicker.
  =========================================================================== }
procedure TSchematicView.Paint;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    RenderTo(Bmp);
    Canvas.Draw(0, 0, Bmp);
  finally
    Bmp.Free;
  end;
  if Assigned(FOnViewMoved) then
    FOnViewMoved(Self);          // (the rulers beside the view look at the zoom and the scroll again)
end;

{ ===========================================================================
  TSchematicView.MouseLeave  (procedure)
  Parameters:  none
  Notes:
    The pointer has left the view: the rulers stop marking it.
  =========================================================================== }
procedure TSchematicView.MouseLeave;
begin
  inherited MouseLeave;
  FHasPointer := False;
  if Assigned(FOnViewMoved) then
    FOnViewMoved(Self);
end;

{ ===========================================================================
  TSchematicView.SaveSnapshot  (procedure)
  Parameters:
    const FileName: String - where to save it
  Notes:
    Saves what the control currently shows as a bitmap file (used by the self-test script).
  =========================================================================== }
procedure TSchematicView.SaveSnapshot(const FileName: String);
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    RenderTo(Bmp);
    Bmp.SaveToFile(FileName);
  finally
    Bmp.Free;
  end;
end;

{ ---------------------------------------------------------------- selection }

{ ===========================================================================
  TSchematicView.HitTest  (function)
  Parameters:
    const P: TDPoint - design point
  Returns:
    TDrawingObject - the object, or nil
  Notes:
    Finds the object under a point, topmost first, using each object's own DistanceFromPoint
    within a 4 pixel tolerance (so ladder rails only hit on a rail or text).
  =========================================================================== }
function TSchematicView.HitTest(const P: TDPoint): TDrawingObject;
var
  i: Integer;
  Tol: Double;
  Obj: TDrawingObject;
begin
  Result := nil;
  if Sheet = nil then
    Exit;
  Tol := 4 / FZoom;
  Sheet.Options.ZoomFactor := FZoom;
  for i := Sheet.Drawing.Count - 1 downto 0 do // topmost (last drawn) first
  begin
    Obj := Sheet.Drawing[i];
    if Obj.GetType = xOrigin then
      Continue;
    if Obj.DistanceFromPoint(P) < Tol then
    begin
      Result := Obj;
      Exit;
    end;
  end;
end;

{ ===========================================================================
  TSchematicView.ClearSelection  (procedure)
  Parameters:  none
  Notes:
    Deselects everything (and notifies only if something was selected).
  =========================================================================== }
procedure TSchematicView.ClearSelection;
begin
  if FSelected.Count > 0 then
  begin
    FSelected.Clear;
    SelectionChanged;
  end;
end;

{ ===========================================================================
  TSchematicView.SelectObject  (procedure)
  Parameters:
    Obj: TDrawingObject - the object (nil just clears when not adding)
    Add: Boolean - True to add to / toggle in the current selection, False to replace it
  Notes:
    Selects an object, or toggles it when adding to the selection.
  =========================================================================== }
procedure TSchematicView.SelectObject(Obj: TDrawingObject; Add: Boolean);
var
  Idx, i: Integer;
begin
  if not Add then
    FSelected.Clear;
  if Obj <> nil then
  begin
    Idx := FSelected.IndexOf(Obj);
    if Idx >= 0 then
    begin
      if Add then
      begin
        FSelected.Delete(Idx);
        if PhaseGroupOf(Obj) <> 0 then      { (the three wires of a 3-phase bus go together) }
          for i := FSelected.Count - 1 downto 0 do
            if PhaseGroupOf(TDrawingObject(FSelected[i])) = PhaseGroupOf(Obj) then
              FSelected.Delete(i);
      end;
    end
    else
      FSelected.Add(Obj);
  end;
  SelectionChanged;
end;

{ ===========================================================================
  TSchematicView.SelectAll  (procedure)
  Parameters:  none
  Notes:
    Selects every object on the sheet.
  =========================================================================== }
procedure TSchematicView.SelectAll;
var
  i: Integer;
begin
  FSelected.Clear;
  if Sheet <> nil then
    for i := 0 to Sheet.Drawing.Count - 1 do
      if Sheet.Drawing[i].GetType <> xOrigin then
        FSelected.Add(Sheet.Drawing[i]);
  if Sheet <> nil then
  begin
    FAreaA := DPoint(0, 0);
    FAreaB := DPoint(Sheet.Details.PageWidth, Sheet.Details.PageHeight);
  end;
  SelectionChanged;
end;

{ ===========================================================================
  TSchematicView.SelectAllAlike  (procedure)
  Parameters:  none
  Notes:
    Selects every object on the sheet of the same kind (wire, label, text, symbol ...) as the
    selected ones: with a wire and a label selected, all wires and all labels. Nothing happens
    when nothing is selected. The origin marker is never selected, as in SelectAll, and, as
    there, no undo step is made (a selection is not a change).
  =========================================================================== }
procedure TSchematicView.SelectAllAlike;
var
  i: Integer;
  Kinds: set of TObjType;
begin
  if (Sheet = nil) or (FSelected.Count = 0) then
    Exit;
  Kinds := [];
  for i := 0 to FSelected.Count - 1 do
    Include(Kinds, TDrawingObject(FSelected[i]).GetType);
  FSelected.Clear;
  for i := 0 to Sheet.Drawing.Count - 1 do
    if (Sheet.Drawing[i].GetType in Kinds) and (Sheet.Drawing[i].GetType <> xOrigin) then
      FSelected.Add(Sheet.Drawing[i]);
  FAreaA := DPoint(0, 0);
  FAreaB := DPoint(Sheet.Details.PageWidth, Sheet.Details.PageHeight);
  SelectionChanged;
end;

{ ===========================================================================
  TSchematicView.SelectedCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    How many objects are selected.
  =========================================================================== }
function TSchematicView.SelectedCount: Integer;
begin
  Result := FSelected.Count;
end;

{ ===========================================================================
  TSchematicView.SelectedObject  (function)
  Parameters:
    Index: Integer - position in the selection
  Returns:
    TDrawingObject - the object
  Notes:
    One of the selected objects.
  =========================================================================== }
function TSchematicView.SelectedObject(Index: Integer): TDrawingObject;
begin
  Result := TDrawingObject(FSelected[Index]);
end;

{ ===========================================================================
  TSchematicView.SelectedList  (function)
  Parameters:  none
  Returns:
    TList - the list (owned by the view; do not free or keep)
  Notes:
    The selection itself, for the property editors.
  =========================================================================== }
function TSchematicView.SelectedList: TList;
begin
  Result := FSelected;
end;

{ ===========================================================================
  TSchematicView.DeleteSelection  (procedure)
  Parameters:  none
  Notes:
    Deletes the selected objects as one undo step and re-checks junctions where wires were
    removed.
  =========================================================================== }
procedure TSchematicView.DeleteSelection;
var
  i: Integer;
  Eng: TWireEngine;
begin
  if (Sheet = nil) or (FSelected.Count = 0) then
    Exit;
  BeginChange(rsDelete);
  Eng := TWireEngine.Create(FDesign, Sheet);
  try
    for i := 0 to FSelected.Count - 1 do
    begin
      Eng.AddObjectToTodo(TDrawingObject(FSelected[i]));   // junctions may no longer be needed
      Sheet.Drawing.Remove(TDrawingObject(FSelected[i]));  // the list owns and frees them
    end;
    FSelected.Clear;
    Eng.CheckTodoList(False);
  finally
    Eng.Free;
  end;
  SelectionChanged;
  CommitChange(True);
end;

{ ---------------------------------------------------------------- tools }

{ ===========================================================================
  TSchematicView.FreeTool  (procedure)
  Parameters:  none
  Notes:
    Drops everything the active tool holds: finishes a wire in progress, frees the wire tool,
    engine and placement symbol, clears polygon points and stages.
  =========================================================================== }
procedure TSchematicView.FreeTool;
begin
  if FWire <> nil then
  begin
    FWire.EndEdit;
    FreeAndNil(FWire);
  end;
  FreeAndNil(FEngine);
  FreeAndNil(FDragEng);
  FPasting := False;
  FreeAndNil(FGhost);
  SetLength(FPoly, 0); SetLength(FPolyArcs, 0);
  FStage := 0;
  FXTarget := nil;
  FDragMode := 0;
  FMidPan := False;
end;

{ ===========================================================================
  TSchematicView.BeginTool  (procedure)
  Parameters:
    ATool: TViewTool - which tool
  Notes:
    Makes a drawing tool the active one (cursor, status hint, wire tool and engine for wires and
    lines).
  =========================================================================== }
procedure TSchematicView.BeginTool(ATool: TViewTool);
begin
  if Sheet = nil then
    Exit;
  if (not Sheet.Options.EditLibrary) and (ATool = vtOrigin) then
  begin
    Status(rsTheOriginCanOnlyBe);
    Exit;
  end;
  if (not Sheet.Options.EditLibrary) and (not Sheet.IsHierarchicalSymbol) and (ATool = vtPin) then
  begin
    Status(rsPinsCanOnlyBePlaced);
    Exit;
  end;
  if Sheet.Options.EditLibrary and (ATool in SYMBOL_EDITOR_REFUSED) then
  begin
    Status(rsThisToolCannotBeUsed);
    Exit;
  end;
  if ATool = vtRungs then
  begin
    { not a drawing mode: the sheet's one rung grid is made if it has none, then selected, and the select tool stays active }
    FreeTool;
    FTool := vtSelect;
    Cursor := crDefault;
    EnsureRungGrid;
    Status(ToolHint(vtRungs));
    if Assigned(FOnToolChanged) then
      FOnToolChanged(Self);
    Invalidate;
    Exit;
  end;
  FreeTool;
  FTool := ATool;
  if ATool = vtSelect then
    Cursor := crDefault
  else
    Cursor := crCross;
  if ATool in [vtWire, vtLine, vtBus] then
  begin
    ClearSelection;
    FEngine := TWireEngine.Create(FDesign, Sheet);
    if ATool = vtWire then
      FWire := TWireTool.Create(FEngine, xWire)
    else if ATool = vtBus then
      FWire := TWireTool.Create(FEngine, xBus)
    else
      FWire := TWireTool.Create(FEngine, xLineEx2);
    FWire.Angle := WireAngles[ATool];      // what was last chosen for this tool
    FWire.OnNewLine := @WireLineMade;
  end;
  if ATool <> vtSelect then
    ApplyUserFont(ATool);
  Status(ToolHint(ATool));
  if Assigned(FOnToolChanged) then
    FOnToolChanged(Self);
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.BeginLadderTool  (procedure)
  Parameters:  none
  Notes:
    Compatibility name for BeginTool(vtLadder), used by forms written for the first version of
    this view.
  =========================================================================== }
procedure TSchematicView.BeginLadderTool;
begin
  BeginTool(vtLadder);
end;

{ ===========================================================================
  TSchematicView.FindRungGrid  (function)
  Parameters:  none
  Returns:
    TDrawRungGrid
  Notes:
    A sheet has at most one rung grid; this finds it.
  =========================================================================== }
function TSchematicView.FindRungGrid: TDrawRungGrid;
var
  i: Integer;
begin
  Result := nil;
  if Sheet = nil then
    Exit;
  for i := 0 to Sheet.Drawing.Count - 1 do
    if Sheet.Drawing[i] is TDrawRungGrid then
      Exit(Sheet.Drawing[i] as TDrawRungGrid);
end;

{ ===========================================================================
  TSchematicView.TakeRungFontFromOtherSheet  (procedure)
  Parameters:
    AGrid: TDrawRungGrid - a new rung grid
  Notes:
    A new rung grid starts with the font and colour of the rung grid on the nearest other sheet
    of the document (the sheets before this one first), so the numbers look alike on every
    sheet. Each sheet keeps its own font list, so the font is added to this sheet's list.
    Nothing changes when no other sheet has a grid.
  =========================================================================== }
procedure TSchematicView.TakeRungFontFromOtherSheet(AGrid: TDrawRungGrid);
var
  i, k, j, d: Integer;
  Src: TDrawRungGrid;
  Cur, New: TFontResource;
begin
  if (FDesign = nil) or (Sheet = nil) then
    Exit;
  Src := nil;
  for d := 1 to FDesign.SheetCount do
    for k := 0 to 1 do
    begin
      if k = 0 then
        i := FSheetIndex - d
      else
        i := FSheetIndex + d;
      if (Src = nil) and (i >= 0) and (i < FDesign.SheetCount) then
        for j := 0 to FDesign.Sheets[i].Drawing.Count - 1 do
          if FDesign.Sheets[i].Drawing[j] is TDrawRungGrid then
          begin
            Src := FDesign.Sheets[i].Drawing[j] as TDrawRungGrid;
            Break;
          end;
    end;
  if Src = nil then
    Exit;
  Cur := Src.Options.Fonts.Get(Src.FontStyle) as TFontResource;
  if Cur = nil then
    Exit;
  New := TFontResource.Create;
  New.Height := Cur.Height; New.Width := Cur.Width; New.Weight := Cur.Weight;
  New.Italic := Cur.Italic; New.Underline := Cur.Underline; New.StrikeOut := Cur.StrikeOut;
  New.CharSet := Cur.CharSet; New.FaceName := Cur.FaceName;
  AGrid.FontStyle := Sheet.Options.Fonts.Add(New, -1);
  AGrid.FontColor := Src.FontColor;
end;

{ ===========================================================================
  TSchematicView.EnsureRungGrid  (function)
  Parameters:  none
  Returns:
    TDrawRungGrid
  Notes:
    The rung numbers function. Makes the sheet's rung grid (as one undo step "Add rung numbers")
    when the sheet has none, and selects it either way so that its properties show on the
    ribbon. A second grid is never made.
  =========================================================================== }
function TSchematicView.EnsureRungGrid: TDrawRungGrid;
begin
  Result := nil;
  if (Sheet = nil) or Sheet.Options.EditLibrary then
    Exit;
  Result := FindRungGrid;
  if Result = nil then
  begin
    BeginChange(rsAddRungNumbers);
    Result := TDrawRungGrid.Create(Sheet.Options);
    TakeRungFontFromOtherSheet(Result);
    AddNew(Result);
    CommitChange(True);
    if Assigned(FOnPlaced) then
      FOnPlaced(Self, Result);
  end;
  FSelected.Clear;
  FSelected.Add(Result);
  SelectionChanged;
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.BeginPlace  (procedure)
  Parameters:
    Meth: TDrawMethod - the symbol to place; the view takes ownership
  Notes:
    Starts placing a symbol: it follows the mouse until clicked.
  =========================================================================== }
procedure TSchematicView.BeginPlace(Meth: TDrawMethod);
begin
  FreeTool;
  FGhost := Meth;
  FTool := vtPlace;
  Cursor := crCross;
  Status(ToolHint(vtPlace));
  if Assigned(FOnToolChanged) then
    FOnToolChanged(Self);
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.BeginRefPainter  (procedure)
  Parameters:
    StartVal: Integer - the lowest number to give
  Notes:
    Starts the reference painter (CDrawRefPainter): clicks give references, right clicks take
    them away, until another tool is chosen or Esc is pressed.
  =========================================================================== }
procedure TSchematicView.BeginRefPainter(StartVal: Integer);
begin
  BeginTool(vtRefPainter);
  FRefStart := StartVal;
end;

{ ===========================================================================
  TSchematicView.PaintRef  (procedure)
  Parameters:
    const P: TDPoint - the point clicked (not snapped to the grid)
    Remove: Boolean - True for the right button
  Notes:
    CDrawRefPainter::LButtonDown and RButtonUp: every symbol under the point gets the next
    number from the start value, or loses its number. Each click is one undo step.
  =========================================================================== }
procedure TSchematicView.PaintRef(const P: TDPoint; Remove: Boolean);
var
  N: Integer;
begin
  if Sheet = nil then
    Exit;
  Sheet.Options.ZoomFactor := FZoom;
  if Remove then
    BeginChange(rsRemoveReference)
  else
    BeginChange(rsAddReference);
  N := PaintReference(Sheet, P, FRefStart, Remove);
  CommitChange(N > 0);
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.CancelTool  (procedure)
  Parameters:  none
  Notes:
    Returns to the select tool.
  =========================================================================== }
procedure TSchematicView.CancelTool;
begin
  FreeTool;
  FTool := vtSelect;
  Cursor := crDefault;
  if Assigned(FOnToolChanged) then
    FOnToolChanged(Self);
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.ToolIsTwoCorner  (function)
  Parameters:  none
  Returns:
    Boolean - True for those tools
  Notes:
    Whether the active tool draws by two corner points (rectangle, circle, arc, note, cloud,
    measure, ladder).
  =========================================================================== }
function TSchematicView.ToolIsTwoCorner: Boolean;
begin
  Result := FTool in [vtRect, vtCircle, vtNote, vtCloud, vtMeasure, vtLadder];
end;

{ ===========================================================================
  TSchematicView.AddNew  (procedure)
  Parameters:
    Obj: TDrawingObject - the object
  Notes:
    Adds a newly created object to the sheet with a new id.
  =========================================================================== }
procedure TSchematicView.AddNew(Obj: TDrawingObject);
var
  i: Integer;
begin
  Obj.Id := FDesign.NextObjectId;
  if (FToolDefaults[FTool] <> nil) and (FTool <> vtPlace) then
    for i := 0 to FToolDefaults[FTool].Count - 1 do
      SetProp(Obj, FToolDefaults[FTool].Names[i], FToolDefaults[FTool].ValueFromIndex[i]);      // what was chosen for this tool
  if not (FTool in [vtSelect, vtPlace]) then
    TakeUserFont(Obj);       // the font of what is placed is the one asked for from now on
  Sheet.Drawing.Add(Obj);
end;

{ ===========================================================================
  TSchematicView.WireLineMade  (procedure)
  Parameters:
    L: TDrawLine
  Notes:
    Gives the segment the properties chosen for the tool (line colour, width, style).
  =========================================================================== }
procedure TSchematicView.WireLineMade(L: TDrawLine);
var
  i: Integer;
begin
  if FToolDefaults[FTool] <> nil then
    for i := 0 to FToolDefaults[FTool].Count - 1 do
      SetProp(L, FToolDefaults[FTool].Names[i], FToolDefaults[FTool].ValueFromIndex[i]);
end;

{ ===========================================================================
  TSchematicView.FinishPolygon  (procedure)
  Parameters:
    Closed: Boolean - True when the shape was closed
  Notes:
    Turns the points clicked so far into a polygon object as one undo step and selects it; fewer
    than two points just cancels.
  =========================================================================== }
procedure TSchematicView.FinishPolygon(Closed: Boolean);
var
  Pg: TDrawPolygon;
  i, n: Integer;
  H: TArcPoint;
begin
  n := Length(FPoly);
  if n < 2 then
  begin
    SetLength(FPoly, 0); SetLength(FPolyArcs, 0);
    FStage := 0;
    Exit;
  end;
  if FTool = vtArc then
    BeginChange(rsDrawArc)
  else
    BeginChange(rsDrawPolygon);
  Pg := TDrawPolygon.Create(Sheet.Options);
  Pg.PointA := FPoly[0];
  SetLength(Pg.Handles, n);
  for i := 0 to n - 1 do
  begin
    H.X := FPoly[i].x - FPoly[0].x;
    H.Y := FPoly[i].y - FPoly[0].y;
    if (i > 0) and (i < Length(FPolyArcs)) then
      H.Arc := FPolyArcs[i]
    else
      H.Arc := Arc_none;
    H.Control := DPointInvalid;
    H.FlattenedSegment := 0;
    Pg.Handles[i] := H;
  end;
  Pg.Close := Ord(Closed);
  Pg.CalcBoundingRect;
  AddNew(Pg);
  SetLength(FPoly, 0); SetLength(FPolyArcs, 0);
  FStage := 0;
  FSelected.Clear;
  FSelected.Add(Pg);
  CommitChange(True);
  SelectionChanged;
  if Assigned(FOnPlaced) then
    FOnPlaced(Self, Pg);
end;

{ ===========================================================================
  TSchematicView.CommitShape  (procedure)
  Parameters:
    const A: TDPoint - first corner
    const B: TDPoint - second corner
  Notes:
    Creates the object for the active two-corner tool (rectangle, circle, note, cloud, measure,
    arc or ladder) from the two corner points, as one undo step, and selects it. Degenerate
    shapes are dropped.
  =========================================================================== }
procedure TSchematicView.CommitShape(const A, B: TDPoint);
var
  Obj: TDrawingObject;
  Sq: TDrawSquare;
  Pg: TDrawPolygon;
  H: TArcPoint;
  Cap: String;
begin
  Obj := nil;
  Cap := 'Draw';
  case FTool of
    vtRect, vtCircle:
      begin
        if FTool = vtRect then
          Sq := TDrawSquare.CreateKind(Sheet.Options, xSquareEx3)
        else
          Sq := TDrawSquare.CreateKind(Sheet.Options, xCircleEx3);
        Sq.PointA := A; Sq.PointB := B;
        Obj := Sq;
      end;
    vtNote:
      begin
        Obj := TDrawNoteText.Create(Sheet.Options);
        Obj.PointA := DPoint(Min(A.x, B.x), Min(A.y, B.y));
        Obj.PointB := DPoint(Max(A.x, B.x), Max(A.y, B.y));
        (Obj as TDrawNoteText).Str := 'Note';
      end;
    vtCloud:
      begin
        Obj := TDrawCloud.Create(Sheet.Options);
        Obj.PointA := DPoint(Min(A.x, B.x), Min(A.y, B.y));
        Obj.PointB := DPoint(Max(A.x, B.x), Max(A.y, B.y));
      end;
    vtMeasure:
      begin
        Obj := TDrawMeasure.Create(Sheet.Options);
        Obj.PointA := A; Obj.PointB := B;
      end;
    vtLadder:
      begin
        Obj := TDrawLadder.Create(Sheet.Options);
        Obj.PointA := DPoint(Min(A.x, B.x), Min(A.y, B.y));
        Obj.PointB := DPoint(Max(A.x, B.x), Max(A.y, B.y));
      end;
  end;
  if Obj = nil then
    Exit;
  { reject degenerate shapes }
  if (Abs(A.x - B.x) < 1) and (Abs(A.y - B.y) < 1) then
  begin
    Obj.Free;
    Exit;
  end;
  BeginChange(Cap);
  AddNew(Obj);
  FSelected.Clear;
  FSelected.Add(Obj);
  FStage := 0;
  CommitChange(True);
  SelectionChanged;
  if Assigned(FOnPlaced) then
    FOnPlaced(Self, Obj);
  if (Obj is TDrawLadder) and Assigned(FOnLadder) then
    FOnLadder(Self, Obj as TDrawLadder);
end;

{ ===========================================================================
  TSchematicView.PlaceLabel  (procedure)
  Parameters:
    const NoSnap: TDPoint - the raw click position
  Notes:
    Places a wire label (default text LABEL) at the point on a wire nearest the click, and
    selects it so its text can be edited on the ribbon.
  =========================================================================== }
procedure TSchematicView.PlaceLabel(const NoSnap: TDPoint);
var
  Eng: TWireEngine;
  P: TDPoint;
  Stuck, Junc: Boolean;
  L: TDrawLabel;
begin
  Eng := TWireEngine.Create(FDesign, Sheet);
  try
    P := Eng.StickyPoint(NoSnap, False, True, Stuck, Junc); // labels stick to wires
  finally
    Eng.Free;
  end;
  BeginChange(rsAddLabel);
  L := TDrawLabel.Create(Sheet.Options);
  L.Str := FloatTextFor(vtLabel);       // (the last label's text, counted, once one has been placed; or what was typed in the tool's box)
  L.Dir := 3;
  L.PointA := P;
  L.ActivePoint := P;
  AddNew(L);
  L.Str := FloatTextFor(vtLabel);
  FLastLabelId := L.Id;
  FLastLabelText := L.Str;
  if FToolDefaults[vtLabel] <> nil then
    FToolDefaults[vtLabel].Values['text'] := '';
  L.UpdateLayout;
  FSelected.Clear;
  FSelected.Add(L);
  CommitChange(True);
  SelectionChanged;
  if Assigned(FOnPlaced) then
    FOnPlaced(Self, L);
end;

{ ===========================================================================
  TSchematicView.PlaceSimple  (procedure)
  Parameters:
    const NoSnap: TDPoint - the raw click position
  Notes:
    Places a junction (sticking to pins and wires) or a horizontal / vertical ruler guide at the
    click.
  =========================================================================== }
procedure TSchematicView.PlaceSimple(const NoSnap: TDPoint);
var
  Eng: TWireEngine;
  P: TDPoint;
  Stuck, Junc: Boolean;
  J: TDrawJunction;
  R: TDrawRuler;
  NC: TDrawNoConnect;
  Pw: TDrawPower;
  BS: TDrawBusSlash;
  Tx: TDrawText;
  St: TDrawSymbolText;
  Pn: TDrawPin;
begin
  if ((FTool = vtOrigin) and (not Sheet.Options.EditLibrary)) or
     ((FTool = vtPin) and (not Sheet.Options.EditLibrary) and (not Sheet.IsHierarchicalSymbol)) then
  begin
    Status(rsPinsCanOnlyBePlaced2);
    Exit;
  end;
  case FTool of
    vtPin:
      begin
        P := SnapPoint(NoSnap);
        BeginChange(rsAddPin);
        Pn := TDrawPin.Create(Sheet.Options);
        FillPendingPin(Pn);
        if FToolDefaults[vtPin] <> nil then
          FToolDefaults[vtPin].Clear;      // (what was chosen in the panel was for this pin; the next one counts on from it)
        Pn.Part := Sheet.Options.EditPart;
        Pn.PointA := P;
        Pn.DetermineSize;
        AddNew(Pn);
        FLastPinId := Pn.Id;
        FSelected.Clear;
        FSelected.Add(Pn);
        CommitChange(True);
        SelectionChanged;
        if Assigned(FOnPlaced) then
          FOnPlaced(Self, Pn);
      end;
    vtOrigin:
      begin
        P := SnapPoint(NoSnap);
        BeginChange(rsSetOrigin);
        Sheet.Options.Origin := P;
        CommitChange(True);
      end;
    vtJunction:
      begin
        Eng := TWireEngine.Create(FDesign, Sheet);
        try
          P := Eng.StickyPoint(NoSnap, True, True, Stuck, Junc);
        finally
          Eng.Free;
        end;
        BeginChange(rsAddJunction);
        J := TDrawJunction.Create(Sheet.Options);
        J.PointA := P; J.PointB := P;
        AddNew(J);
        CommitChange(True);
      end;
    vtNoConnect, vtPower:
      begin
        { these stick to a pin (or wire end) under the mouse, like a junction }
        Eng := TWireEngine.Create(FDesign, Sheet);
        try
          P := Eng.StickyPoint(NoSnap, True, True, Stuck, Junc);
        finally
          Eng.Free;
        end;
        if FTool = vtNoConnect then
        begin
          BeginChange(rsAddNoConnect);
          NC := TDrawNoConnect.Create(Sheet.Options);
          NC.PointA := P; NC.PointB := P;
          AddNew(NC);
          CommitChange(True);
        end
        else
        begin
          BeginChange(rsAddPowerSymbol);
          Pw := TDrawPower.Create(Sheet.Options);
          Pw.PointA := P; Pw.PointB := P;
          Pw.Which := 0;       // the first kind in the list; changed in Properties
          Pw.Dir := 0;
          Pw.Str := 'VCC';
          AddNew(Pw);
          FSelected.Clear;
          FSelected.Add(Pw);
          CommitChange(True);
          SelectionChanged;
        end;
      end;
    vtBusSlash:
      begin
        P := SnapPoint(NoSnap);
        BeginChange(rsAddBusSlash);
        BS := TDrawBusSlash.Create(Sheet.Options);
        BS.PointA := P;
        BS.PointB := DPoint(P.x + 10, P.y - 10);
        BS.Dir := 0;
        AddNew(BS);
        FSelected.Clear;
        FSelected.Add(BS);
        CommitChange(True);
        SelectionChanged;
      end;
    vtText:
      begin
        P := SnapPoint(NoSnap);
        BeginChange(rsAddText);
        Tx := TDrawText.Create(Sheet.Options);
        Tx.Dir := 3;                      { text reads Right unless the tool's Direction says otherwise (AddNew applies that) }
        Tx.PointA := P; Tx.PointB := P;
        Tx.Str := FloatTextString;
        AddNew(Tx);
        Tx.Str := FloatTextString;
        Tx.UpdateLayout;
        FLastTextId := Tx.Id;
        FLastTextText := Tx.Str;
        { the next one is counted on from this one, unless a text is typed in the tool's box again }
        if FToolDefaults[vtText] <> nil then
          FToolDefaults[vtText].Values['text'] := '';
        FSelected.Clear;
        FSelected.Add(Tx);
        CommitChange(True);
        SelectionChanged;
        if Assigned(FOnPlaced) then
          FOnPlaced(Self, Tx);
      end;
    vtSymbolText:
      begin
        P := SnapPoint(NoSnap);
        BeginChange(rsAddSymbolText);
        St := TDrawSymbolText.Create(Sheet.Options);
        St.PointA := P; St.PointB := P;
        AddNew(St);
        if St.GetName = '' then
          St.Fields[FIELD_NAME].Value := rsSymbolText;      { an empty text shows nothing: there would be nothing to see or to click on }
        St.UpdateLayout;
        FSelected.Clear;
        FSelected.Add(St);
        CommitChange(True);
        SelectionChanged;
      end;
    vtRulerH, vtRulerV:
      begin
        P := SnapPoint(NoSnap);
        BeginChange(rsAddRuler);
        R := TDrawRuler.Create(Sheet.Options);
        R.PointA := P; R.PointB := P;
        if FTool = vtRulerH then
          R.Horizontal := 1
        else
          R.Horizontal := 0;
        AddNew(R);
        FSelected.Clear;
        FSelected.Add(R);
        CommitChange(True);
        SelectionChanged;
      end;
  end;
end;

{ ===========================================================================
  TSchematicView.XRefClick  (procedure)
  Parameters:
    const P: TDPoint - click position
  Notes:
    Two-step link tool: the first click picks the object to follow, the second click places the
    linked text.
  =========================================================================== }
procedure TSchematicView.XRefClick(const P: TDPoint);
var
  Hit: TDrawingObject;
  X: TDrawRefText;
begin
  if FStage = 0 then
  begin
    Hit := HitTest(P);
    if Hit = nil then
    begin
      Status(rsClickTheObjectTheText);
      Exit;
    end;
    FXTarget := Hit;
    FStage := 1;
    Status(rsNowClickWhereTheText);
    Invalidate;
    Exit;
  end;
  BeginChange(rsAddLink);
  X := TDrawRefText.Create(Sheet.Options);
  X.TargetId := FXTarget.Id;
  if FTool = vtXRefContacts then
    X.Mode := 1
  else
    X.Mode := 0;
  X.PointA := SnapPoint(P);
  AddNew(X);
  FSelected.Clear;
  FSelected.Add(X);
  FXTarget := nil;
  FStage := 0;
  CommitChange(True);
  SelectionChanged;
end;

{ ---------------------------------------------------------------- wire tool glue }

{ ===========================================================================
  TSchematicView.WireDown  (procedure)
  Parameters:
    const P: TDPoint - click position
    Shift: TShiftState - modifier keys (a double click finishes the wire)
  Notes:
    Passes a left click to the wire tool inside an undoable action, which is kept only if
    something was stored.
  =========================================================================== }
procedure TSchematicView.WireDown(const P: TDPoint; Shift: TShiftState);
var
  N0, S0: Integer;
begin
  if FWire = nil then
    Exit;
  N0 := Sheet.Drawing.Count;
  S0 := FWire.Stored;
  BeginChange(rsDraw);
  if ssDouble in Shift then
    FWire.DblLButtonDown(P)
  else
    FWire.LButtonDown(P);
  CommitChange((Sheet.Drawing.Count <> N0) or (FWire.Stored <> S0));
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.WireUp  (procedure)
  Parameters:
    const P: TDPoint - release position
  Notes:
    Passes the mouse release to the wire tool, which places a dragged wire.
  =========================================================================== }
procedure TSchematicView.WireUp(const P: TDPoint);
var
  N0, S0: Integer;
begin
  if FWire = nil then
    Exit;
  N0 := Sheet.Drawing.Count;
  S0 := FWire.Stored;
  BeginChange(rsDraw);
  FWire.LButtonUp(P);
  CommitChange((Sheet.Drawing.Count <> N0) or (FWire.Stored <> S0));
  Invalidate;
end;

{ ---------------------------------------------------------------- mouse }

{ the shift state flag the toolkit reports while a mouse button is held }
function ShiftOfButton(B: TMouseButton): TShiftStateEnum;
begin
  case B of
    mbRight: Result := ssRight;
    mbMiddle: Result := ssMiddle;
  else
    Result := ssLeft;
  end;
end;

{ ===========================================================================
  TSchematicView.SimMouse  (procedure)
  Parameters:
    Kind: Integer - 0 = press, 1 = move, 2 = release
    X: Integer - pixel x
    Y: Integer - pixel y
    Shift: TShiftState - modifier keys
    Button: TMouseButton - mouse button
  Notes:
    Sends a mouse event through the control's real handlers; used by the self-test script.
  =========================================================================== }
procedure TSchematicView.SimMouse(Kind: Integer; X, Y: Integer; Shift: TShiftState; Button: TMouseButton);
begin
  case Kind of
    0: MouseDown(Button, Shift, X, Y);
    1:
      begin
        { a move as the toolkit reports it: with the buttons that are held }
        if FDragMode <> 0 then
          Shift := Shift + [ShiftOfButton(FDownButton)];
        if FMidPan then
          Shift := Shift + [ssMiddle];
        MouseMove(Shift, X, Y);
      end;
    2: MouseUp(Button, Shift, X, Y);
    3: MouseMove(Shift, X, Y);      { a move with no button held, whatever the view thinks: the release was lost }
  end;
end;

{ ===========================================================================
  TSchematicView.ClickAt  (procedure)
  Parameters:
    X: Integer - pixel x
    Y: Integer - pixel y
    Shift: TShiftState - modifier keys
  Notes:
    A press and release at a pixel position through the real handlers.
  =========================================================================== }
procedure TSchematicView.ClickAt(X, Y: Integer; Shift: TShiftState);
begin
  MouseDown(mbLeft, Shift, X, Y);
  MouseUp(mbLeft, Shift, X, Y);
end;

{ ===========================================================================
  TSchematicView.RightClickAt  (procedure)
  Parameters:
    X: Integer - pixel x
    Y: Integer - pixel y
  Notes:
    For scripted tests: a press and release of the right button at a pixel position through the
    real handlers.
  =========================================================================== }
procedure TSchematicView.RightClickAt(X, Y: Integer);
begin
  MouseDown(mbRight, [], X, Y);
  MouseUp(mbRight, [], X, Y);
end;

{ ===========================================================================
  TSchematicView.Notification  (procedure)
  Parameters:
    AComponent: TComponent - the component that is going away
    Operation: TOperation
  Notes:
    Forgets the text box a pan will give the focus back to when that box is freed.
  =========================================================================== }
procedure TSchematicView.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FPanFocus) then
    FPanFocus := nil;
end;

{ ===========================================================================
  TSchematicView.MouseDown  (procedure)
  Parameters:
    Button: TMouseButton - which button
    Shift: TShiftState - modifier keys
    X: Integer - pixel x
    Y: Integer - pixel y
  Notes:
    Handles a mouse press for the active tool: pans on the middle or (in select) right button;
    right click finishes or cancels a tool; a left click draws, places, selects or starts a drag
    depending on the tool.
  =========================================================================== }
procedure TSchematicView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  P: TDPoint;
  Hit: TDrawingObject;
  EndFirst: Boolean;
  Placed: TDrawMethod;
  i: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  { a drag is under way with another button held (a rubber band, a move): this press does not cancel it or start a pan }
  if (FDragMode <> 0) and (Button <> FDownButton) then
  begin
    { the middle button moves the viewport while another button's drag goes on; the drag is not disturbed }
    if (Button = mbMiddle) and (not FMidPan) then
    begin
      FMidPan := True;
      FMidLast := Point(X, Y);
    end;
    Exit;
  end;
  FDownButton := Button;
  FPanFocus := nil;
  if (Button = mbMiddle) or ((Button = mbRight) and (FTool = vtSelect)) then
    if (Screen.ActiveControl <> nil) and (Screen.ActiveControl <> Self) and (Screen.ActiveControl is TCustomEdit) then
    begin
      FPanFocus := Screen.ActiveControl;
      FPanFocus.FreeNotification(Self);
    end;
  if CanFocus then
    SetFocus;
  if Sheet = nil then
    Exit;
  ApplyTransform;
  P := ScreenToDesign(Point(X, Y));
  FMouseDesign := P;
  FDragScreen := Point(X, Y);
  FMoved := False;

  if FPasting and (Button <> mbMiddle) then       // (the middle button pans the sheet while the block floats)
  begin
    { the block follows the mouse: a left click drops it, a right click throws it away }
    if Button = mbLeft then
      DropPaste
    else if Button = mbRight then
      CancelPaste;
    Exit;
  end;
  if FTool = vtRefPainter then
  begin
    if Button = mbLeft then
      PaintRef(P, False)
    else if Button = mbRight then
      PaintRef(P, True);
    Exit;
  end;
  if (Button = mbMiddle) or ((Button = mbRight) and (FTool = vtSelect)) then
  begin
    FDragMode := 3;
    FOriginAtDrag := FOrigin;
    Cursor := crSizeAll;
    Exit;
  end;
  if (Button = mbRight) and (FTool = vtPolygon) and (Length(FPoly) >= 1) and (not SuppressMenus) then
  begin
    ShowDrawMenu(X, Y);       // finish or cancel the polygon, or choose the arc type of the next segments
    Exit;
  end;
  if (Button = mbRight) and (FTool = vtArc) and (not SuppressMenus) then
  begin
    ShowArcMenu(X, Y);        // arc in or arc out, or cancel
    Exit;
  end;
  if Button = mbRight then
  begin
    { right-click finishes what is being drawn, or, if nothing is, drops the tool }
    if FTool in [vtWire, vtLine, vtBus] then
    begin
      if (FWire <> nil) and (FWire.Segment = 0) then
      begin
        BeginChange(rsDraw);
        FWire.RButtonDown;
        CommitChange(True);
        Invalidate;
      end
      else
        CancelTool;
    end
    else if (FTool = vtPolygon) and (Length(FPoly) >= 2) then
      FinishPolygon(False)
    else if FStage = 1 then begin
      FStage := 0;
      SetLength(FPoly, 0);
      SetLength(FPolyArcs, 0);
      FXTarget := nil;
      Invalidate;
    end
    else
      CancelTool;
    Exit;
  end;
  if Button <> mbLeft then
    Exit;

  case FTool of
    vtWire, vtLine, vtBus: WireDown(P, Shift);
    vtPolygon, vtArc:
      begin
        if ssDouble in Shift then
        begin
          FinishPolygon(False);
          Exit;
        end;
        SetLength(FPoly, Length(FPoly) + 1);
        FPoly[High(FPoly)] := SnapPoint(P);
        SetLength(FPolyArcs, Length(FPoly));
        if Length(FPoly) = 1 then
          FPolyArcs[High(FPoly)] := Arc_none
        else if FTool = vtArc then
        begin
          FPolyArcs[High(FPoly)] := FArcToolType;
          ArcToolType := IfThen(FArcToolType = Arc_in, Arc_out, Arc_in);      // every click after the first turns the next arc the other way round: a wave, not a half circle and its mirror
        end
        else
          FPolyArcs[High(FPoly)] := FPolyArc;
        if (Length(FPoly) > 2) and (Hypot(FPoly[High(FPoly)].x - FPoly[0].x, FPoly[High(FPoly)].y - FPoly[0].y) < 3) then
        begin
          SetLength(FPoly, Length(FPoly) - 1);   // back on the first point: close the shape
          SetLength(FPolyArcs, Length(FPoly));
          FinishPolygon(True);
          Exit;
        end;
        FStage := 1;
        FShapeEnd := FPoly[High(FPoly)];
        Invalidate;
      end;
    vtRect, vtCircle, vtNote, vtCloud, vtMeasure, vtLadder:
      begin
        if FStage = 0 then
        begin
          FShapeStart := SnapPoint(P);
          FShapeEnd := FShapeStart;
          FShapeScreen := Point(X, Y);
          FStage := 1;
          FDragMode := 4;   // a press: if it turns into a drag, release will finish the shape
          Invalidate;
        end
        else
        begin
          FShapeEnd := SnapPoint(P);
          CommitShape(FShapeStart, FShapeEnd);
        end;
      end;
    vtLabel: PlaceLabel(P);
    vtJunction, vtRulerH, vtRulerV, vtBusSlash, vtNoConnect, vtPower, vtText, vtPin, vtOrigin, vtSymbolText: PlaceSimple(P);
    vtXRefLine, vtXRefContacts: XRefClick(P);
    vtPlace:
      if FGhost <> nil then
      begin
        BeginChange(rsPlaceSymbol);
        FGhost.PointA := SnapPoint(P);
        FGhost.NewRotation;
        Placed := FGhost.Clone as TDrawMethod;
        AddNew(Placed);
        Placed.UpdateLayout;
        Status(Format(rsPlaced, [Placed.GetRef, Placed.GetName]));
        FSelected.Clear;
        FSelected.Add(Placed);
        PlacePhaseCopies(Placed);
        CommitChange(True);
        SelectionChanged;
        if Assigned(FOnPlaced) then
          FOnPlaced(Self, Placed);
      end;
  else
    begin
      { a red circle of Find is chosen (and its entry in the list with it) }
      if (Button = mbLeft) and (Length(FMarkers) > 0) then
      begin
        i := MarkerAt(P);
        if i >= 0 then
        begin
          SelectMarker(i);
          if Assigned(FOnMarkerClick) then
            FOnMarkerClick(Self, i);
          Exit;
        end;
      end;
      { a handle of the one selected rectangle, ellipse, picture or note: dragging it resizes the object (these handles are outside the
        rectangle, so they are tried before anything under them) }
      if (Button = mbLeft) and (not (ssShift in Shift)) and (SelectedResizable <> nil) then
      begin
        FFieldCode := SelectedResizable.ResizeHandleAt(P, ResizeHandleSize);
        if FFieldCode >= 0 then
        begin
          FDragMode := 6;
          FDragStart := P;
          FDragLast := SnapPoint(P);
          FResizeRatio := SelectedResizable.ResizeAspectRatio;
          Exit;
        end;
      end;
      { a field (reference, name, value ...) of the one selected symbol is dragged by itself, and keeps its new place relative to the symbol }
      { (a symbol text is one block of text: a press on any line of it moves all of it, the lines are not dragged out of it) }
      if (Button = mbLeft) and (not (ssShift in Shift)) and (FSelected.Count = 1) and (not (TObject(FSelected[0]) is TDrawSymbolText)) then
      begin
        FFieldCode := TDrawingObject(FSelected[0]).FieldAt(P);
        if FFieldCode >= FIELD_BASE then
        begin
          FDragMode := 7;
          FDragStart := P;
          FDragLast := SnapPoint(P);
          Exit;
        end;
      end;
      { a handle (or curve control point) of the one selected polygon is dragged on its own }
      if (Button = mbLeft) and (not (ssShift in Shift)) and (SelectedPolygon <> nil) then
      begin
        FFieldCode := SelectedPolygon.HandleAt(P, PolygonTolerance);
        if FFieldCode >= 0 then
        begin
          FDragMode := 5;          // (4 is a two-corner shape being dragged out)
          FDragStart := P;
          FDragLast := SnapPoint(P);
          Exit;
        end;
      end;
      { an end handle of a chosen wire that was clicked, or only partly picked, stretches it (TinyCAD); when the whole wire was picked
        the handle moves the wire like any other part of it }
      if (Button = mbLeft) and (not (ssShift in Shift)) then
      begin
        FEndLine := WireEndAt(P, EndFirst);
        FEndFirst := EndFirst;
        if FEndLine <> nil then
        begin
          if EndFirst then
            FAreaA := FEndLine.PointA
          else
            FAreaA := FEndLine.PointB;
          FAreaB := FAreaA;
          FDragMode := 1;
          FDragStart := P;
          FDragLast := SnapPoint(P);
          Exit;
        end;
      end;
      { a handle of a wholly picked wire also wins over whatever lies under it (a junction dot, a symbol): the press moves the selection }
      if (Button = mbLeft) and (not (ssShift in Shift)) and WholeWireEndAt(P) then
      begin
        FDragMode := 1;
        FDragStart := P;
        FDragLast := SnapPoint(P);
        Exit;
      end;
      Hit := HitTest(P);
      if Hit <> nil then
      begin
        if ssShift in Shift then
          SelectObject(Hit, True)
        else
        begin
          if FSelected.IndexOf(Hit) < 0 then
          begin
            SelectObject(Hit, False);
            FAreaA := P;      // picked with a click: the area is that point
            FAreaB := P;
          end;
          if not (Hit is TDrawRungGrid) then       // the rung grid covers the sheet and stays where it is: a press on its numbers only selects it
          begin
            FDragMode := 1;
            FDragStart := P;
            FDragLast := SnapPoint(P);   // moves are measured between snapped points, so objects stay on the grid
          end;
        end;
      end
      else
      begin
        if not (ssShift in Shift) then
          ClearSelection;
        FDragMode := 2;
        FDragStart := P;
        FDragLast := P;
      end;
    end;
  end;
end;

{ ===========================================================================
  TSchematicView.MouseMove  (procedure)
  Parameters:
    Shift: TShiftState - modifier keys
    X: Integer - pixel x
    Y: Integer - pixel y
  Notes:
    Handles mouse movement: shows the position, pans, moves the selection (as one undo step,
    grid snapped), grows the rubber band, and updates the wire tool and shape previews.
  =========================================================================== }
procedure TSchematicView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  P, S, Delta: TDPoint;
  i: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  FPointerPixel := Point(X, Y);
  FHasPointer := True;
  if Assigned(FOnViewMoved) then
    FOnViewMoved(Self);
  if Sheet = nil then
    Exit;
  { a release that never came (the drop-down list of a symbol's parameters opened under the pointer on the press and took the release): the pointer
    moves with the button up, so the drag is over }
  if FMidPan and (not (ssMiddle in Shift)) then
    FMidPan := False;
  if (FDragMode <> 0) and (not (ShiftOfButton(FDownButton) in Shift)) then
    MouseUp(FDownButton, Shift, X, Y);
  if FMidPan then
  begin
    { the viewport follows the pointer (what is being dragged stays where it is on the sheet) }
    FOrigin := DPoint(FOrigin.x - (X - FMidLast.x) / FZoom, FOrigin.y - (Y - FMidLast.y) / FZoom);
    FMidLast := Point(X, Y);
    FAutoFit := False;
    Invalidate;
    Exit;
  end;
  ApplyTransform;
  P := ScreenToDesign(Point(X, Y));
  FMouseDesign := P;
  FHaveMouse := True;
  ReportPosition(P);
  if FPasting and (FDragMode <> 3) then       // (while the middle button pans the sheet the block stays where it is)
  begin
    S := SnapPoint(P);
    Delta := DPoint(S.x - FBlockRef.x, S.y - FBlockRef.y);
    if (Delta.x <> 0) or (Delta.y <> 0) then
    begin
      FDragEng.MoveBy(Delta);
      FBlockRef := S;
      Sheet.UpdateLayout;
      Invalidate;
    end;
    Exit;
  end;
  { over a handle of the selected rectangle the pointer shows which way it will resize }
  if (FDragMode = 0) and (FTool = vtSelect) then
  begin
    if (SelectedResizable <> nil) and (SelectedResizable.ResizeHandleAt(P, ResizeHandleSize) >= 0) then
      Cursor := CursorForHandle(SelectedResizable.ResizeHandleAt(P, ResizeHandleSize))
    else if (FSelected.Count = 1) and (TObject(FSelected[0]) is TDrawMethod) and (not FPasting) then
    begin
      { over the one selected symbol, or near it, or over one of its fields, the pointer shows that it can be moved (CDrawMethod::SetCursorEdit) }
      with TDrawMethod(FSelected[0]) do
        if (FieldAt(P) >= FIELD_BASE) or IsInside(P.x, P.x, P.y, P.y) or (DistanceFromPoint(P) <= 10 / Max(FZoom, 0.01)) then
          Cursor := crSizeAll
        else
          Cursor := crDefault;
    end
    else if SelectedResizable <> nil then
      Cursor := crDefault
    else if (Cursor = crSizeNWSE) or (Cursor = crSizeNESW) or (Cursor = crSizeNS) or (Cursor = crSizeWE) or (Cursor = crSizeAll) then
      Cursor := crDefault;
  end;
  case FDragMode of
    3:
      begin
        FOrigin := DPoint(FOriginAtDrag.x - (X - FDragScreen.x) / FZoom, FOriginAtDrag.y - (Y - FDragScreen.y) / FZoom);
        FAutoFit := False;
        if Abs(X - FDragScreen.x) + Abs(Y - FDragScreen.y) >= 4 then
          FMoved := True;   // (a right click that did not drag opens the menu)
        Invalidate;
      end;
    7:
      begin
        S := SnapPoint(P);
        Delta := DPoint(S.x - FDragLast.x, S.y - FDragLast.y);
        if ((Delta.x <> 0) or (Delta.y <> 0)) and (FSelected.Count = 1) then
        begin
          if not FMoved then
            BeginChange(rsMoveField);
          FMoved := True;
          TDrawingObject(FSelected[0]).MoveFieldBy(FFieldCode, Delta);
          FDragLast := S;
          Invalidate;
        end;
      end;
    6:
      begin
        S := SnapPoint(P);
        Delta := DPoint(S.x - FDragLast.x, S.y - FDragLast.y);
        if ((Delta.x <> 0) or (Delta.y <> 0)) and (SelectedResizable <> nil) then
        begin
          { with Ctrl held a corner keeps the shape of the rectangle (CDrawEditItem::Move) }
          if (ssCtrl in Shift) and (FResizeRatio > 0) then
            case FFieldCode of
              HANDLE_TOPRIGHT, HANDLE_BOTTOMLEFT:
                if Abs(Delta.x) > Abs(Delta.y) then
                  Delta.y := -Delta.x * FResizeRatio
                else
                  Delta.x := -Delta.y / FResizeRatio;
              HANDLE_TOPLEFT, HANDLE_BOTTOMRIGHT:
                if Abs(Delta.x) > Abs(Delta.y) then
                  Delta.y := Delta.x * FResizeRatio
                else
                  Delta.x := Delta.y / FResizeRatio;
            end;
          if not FMoved then
            BeginChange(rsResize);
          FMoved := True;
          SelectedResizable.ResizeBy(FFieldCode, Delta);
          FDragLast := S;
          Sheet.UpdateLayout;
          Invalidate;
        end;
      end;
    5:
      begin
        S := SnapPoint(P);
        Delta := DPoint(S.x - FDragLast.x, S.y - FDragLast.y);
        if ((Delta.x <> 0) or (Delta.y <> 0)) and (SelectedPolygon <> nil) then
        begin
          if not FMoved then
            BeginChange(rsEditPolygon);
          FMoved := True;
          SelectedPolygon.MoveHandle(FFieldCode, Delta);
          FDragLast := S;
          Invalidate;
        end;
      end;
    1:
      begin
        S := SnapPoint(P);
        Delta := DPoint(S.x - FDragLast.x, S.y - FDragLast.y);
        if (Delta.x <> 0) or (Delta.y <> 0) then
        begin
          if (not FMoved) and (Abs(X - FDragScreen.x) + Abs(Y - FDragScreen.y) < 4) then
            Exit;
          if not FMoved then
          begin
            BeginChange(rsMove);
            StartDragEngine;
          end;
          FMoved := True;
          if (FEndLine <> nil) and (FEndLine.GetType <> xWire) and (FEndLine.GetType <> xBus) then
          begin
            { a plain line (not a wire) has nothing attached to follow: its end just moves, as a wire's does }
            if FEndFirst then
              FEndLine.PointA := DPoint(FEndLine.PointA.x + Delta.x, FEndLine.PointA.y + Delta.y)
            else
              FEndLine.PointB := DPoint(FEndLine.PointB.x + Delta.x, FEndLine.PointB.y + Delta.y);
          end
          else if ssCtrl in Shift then
            FDragEng.MoveBy(Delta)      // Ctrl: move the objects only
          else
            FDragEng.DragBy(Delta);                        // wires attached to them follow
          PruneSelection;
          if FEndLine = nil then
          begin
            FAreaA := DPoint(FAreaA.x + Delta.x, FAreaA.y + Delta.y);   // the area the selection was picked with goes along with it
            FAreaB := DPoint(FAreaB.x + Delta.x, FAreaB.y + Delta.y);
          end;
          FDragLast := S;
          Sheet.UpdateLayout;
          UpdateLinks(FDesign);
          Invalidate;
        end;
      end;
    2:
      begin
        FDragLast := P;
        Invalidate;
      end;
  end;
  case FTool of
    vtWire, vtLine, vtBus:
      if FWire <> nil then
      begin
        FWire.Move(P);
        Invalidate;
      end;
    vtPolygon, vtArc:
      if FStage = 1 then
      begin
        FShapeEnd := SnapPoint(P);
        Invalidate;
      end;
    vtRect, vtCircle, vtNote, vtCloud, vtMeasure, vtLadder:
      if FStage = 1 then
      begin
        FShapeEnd := SnapPoint(P);
        Invalidate;
      end;
    vtPlace:
      if FGhost <> nil then
      begin
        FGhost.PointA := SnapPoint(P);
        FGhost.NewRotation;
        Invalidate;
      end;
    vtText, vtLabel, vtJunction, vtNoConnect, vtPower, vtBusSlash: Invalidate;
  end;
end;

{ ===========================================================================
  TSchematicView.MouseUp  (procedure)
  Parameters:
    Button: TMouseButton - which button
    Shift: TShiftState - modifier keys
    X: Integer - pixel x
    Y: Integer - pixel y
  Notes:
    Handles the release: finishes a pan, a move or a rubber-band selection, lets the wire tool
    place a dragged wire, or finishes a two-corner shape that was press-dragged.
  =========================================================================== }
procedure TSchematicView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  L, R, T, B: Double;
  i: Integer;
  P: TDPoint;
begin
  inherited MouseUp(Button, Shift, X, Y);
  { the release of a button that did not start the drag in progress does not end it }
  if (FDragMode <> 0) and (Button <> FDownButton) then
  begin
    if (Button = mbMiddle) and FMidPan then
      FMidPan := False;
    Exit;
  end;
  if Sheet = nil then
    Exit;
  ApplyTransform;
  P := ScreenToDesign(Point(X, Y));
  if (Button = mbLeft) and (FTool in [vtWire, vtLine, vtBus]) then
  begin
    WireUp(P);
    Exit;
  end;
  case FDragMode of
    3:
      begin
        Cursor := crDefault;
        { a pan that moved the sheet gives the focus back to the text box that had it (a click that did not move anything leaves it on the sheet, as before) }
        if FMoved and (FPanFocus <> nil) and FPanFocus.CanFocus then
          FPanFocus.SetFocus;
        FPanFocus := nil;
        if (Button = mbRight) and (not FMoved) and (not SuppressMenus) and (FTool = vtSelect) then
        begin
          ContextSelectAt(P);
          if Assigned(FOnContext) then
            FOnContext(Self, X, Y, P);
        end;
      end;
    5: if FMoved then
         CommitChange(True);
    6: if FMoved then
         CommitChange(True);
    7: if FMoved then
         CommitChange(True);
    1: if FMoved then
       begin
         if FDragEng <> nil then
         begin
           FDragEng.FinishDrag;      // merge, clean and re-check junctions
           FreeAndNil(FDragEng);
           PruneSelection;
         end;
         CommitChange(True);
       end;
    2:
      begin
        L := Min(FDragStart.x, FDragLast.x); R := Max(FDragStart.x, FDragLast.x);
        T := Min(FDragStart.y, FDragLast.y); B := Max(FDragStart.y, FDragLast.y);
        if (R - L > 2) or (B - T > 2) then
        begin
          Sheet.Options.ZoomFactor := FZoom;
          FAreaA := DPoint(L, T);
          FAreaB := DPoint(R, B);
          for i := 0 to Sheet.Drawing.Count - 1 do
            { dragging to the right selects what the box touches; dragging to the left only what it holds completely (as in TinyCAD) }
            if (Sheet.Drawing[i].GetType <> xOrigin) and
               ((FDragLast.x >= FDragStart.x) and Sheet.Drawing[i].IsInside(L, R, T, B) or
                (FDragLast.x < FDragStart.x) and Sheet.Drawing[i].IsCompletelyInside(L, R, T, B) and
                ((PhaseGroupOf(Sheet.Drawing[i]) = 0) or PhaseGroupInside(PhaseGroupOf(Sheet.Drawing[i]), L, R, T, B))) then
              if FSelected.IndexOf(Sheet.Drawing[i]) < 0 then
                FSelected.Add(Sheet.Drawing[i]);
          SelectionChanged;
        end;
      end;
    4:
      begin
        { press, drag, release finishes a two-corner shape; a plain click leaves the first corner placed }
        if (FStage = 1) and (Abs(X - FShapeScreen.x) + Abs(Y - FShapeScreen.y) > 6) then
        begin
          FShapeEnd := SnapPoint(P);
          FDragMode := 0;
          CommitShape(FShapeStart, FShapeEnd);
        end;
      end;
  end;
  FEndLine := nil;
  FDragMode := 0;
  Invalidate;
  if Assigned(FOnDragEnd) then
    FOnDragEnd(Self);
end;

{ ===========================================================================
  TSchematicView.DoMouseWheel  (function)
  Parameters:
    Shift: TShiftState - modifier keys
    WheelDelta: Integer - scroll direction
    MousePos: TPoint - mouse position in screen coordinates
  Returns:
    Boolean - True (the event was handled)
  Notes:
    Zooms in or out about the mouse position.
  =========================================================================== }
function TSchematicView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta > 0 then
    SetZoomAt(FZoom * 1.2, MousePos)
  else
    SetZoomAt(FZoom / 1.2, MousePos);
  Result := True;
end;

{ ===========================================================================
  TSchematicView.SimWheel  (procedure)
  Parameters:
    X: Integer - horizontal position or value
    Y: Integer - vertical position or value
    Delta: Integer - whole number
  Notes:
    Delivers a wheel event the way the LCL does, for the script commands and tests.
  =========================================================================== }
procedure TSchematicView.SimWheel(X, Y, Delta: Integer);
begin
  DoMouseWheel([], Delta, Point(X, Y));
end;

{ ===========================================================================
  ToolSampleOf  (function)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
    ATool: TViewTool
  Returns:
    TDrawingObject
  Notes:
    An object like the ones the tool makes, to find out which properties it has and their
    starting values.
  =========================================================================== }
function ToolSampleOf(AOpts: TDocOptionsBase; ATool: TViewTool): TDrawingObject;
begin
  case ATool of
    vtWire: Result := TDrawLine.CreateKind(AOpts, xWire);
    vtBus: Result := TDrawLine.CreateKind(AOpts, xBus);
    vtLine: Result := TDrawLine.CreateKind(AOpts, xLineEx2);
    vtPolygon, vtArc: Result := TDrawPolygon.Create(AOpts);
    vtRect: Result := TDrawSquare.CreateKind(AOpts, xSquareEx3);
    vtCircle: Result := TDrawSquare.CreateKind(AOpts, xCircleEx3);
    vtNote: Result := TDrawNoteText.Create(AOpts);
    vtCloud: Result := TDrawCloud.Create(AOpts);
    vtMeasure: Result := TDrawMeasure.Create(AOpts);
    vtText:
      begin
        Result := TDrawText.Create(AOpts);
        TDrawText(Result).Dir := 3;       { the default direction of a new text is Right }
      end;
    vtSymbolText: Result := TDrawSymbolText.Create(AOpts);
    vtLabel: Result := TDrawLabel.Create(AOpts);
    vtPower: Result := TDrawPower.Create(AOpts);
  else
    Result := nil;
  end;
end;

{ ===========================================================================
  TSchematicView.ToolPropDefs  (function)
  Parameters:
    ATool: TViewTool
  Returns:
    TPropDefArray
  Notes:
    The look of the new object (line, fill, font, label type ...) and not what is particular to
    one object (its text, its position, the number of a pin).
  =========================================================================== }
function TSchematicView.ToolPropDefs(ATool: TViewTool): TPropDefArray;
const
  PER_OBJECT: array[0..4] of String = ('text', 'ruler.pos', 'poly.closed', 'xref.target', 'dir');
var
  Sample: TDrawingObject;
  All: TPropDefArray;
  i, j, n: Integer;
  Skip: Boolean;
begin
  SetLength(Result, 0);
  if Sheet = nil then
    Exit;
  if ATool = vtPlace then
  begin
    { the symbol being placed: CEditDlgMethodEdit's choices (direction, mirror, reference and whether it shows, power pins, resizing); the texts of the parameters are
      the symbol's own and are in its parameter list }
    if FGhost = nil then
      Exit;
    All := ObjectProps(FGhost);
    for i := 0 to High(All) do
      if (All[i].Name = 'sym.dir') or (All[i].Name = 'sym.mirror') or (All[i].Name = 'sym.ref') or (All[i].Name = 'sym.showref') or (All[i].Name = 'sym.showpower') or (All[i].Name = 'sym.canscale') then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := All[i];
      end;
    Exit;
  end;
  if ATool = vtPin then
  begin
    { the pin about to be placed: all of its properties (a pin can only be placed while a symbol is edited) }
    if Sheet.Options.EditLibrary or Sheet.IsHierarchicalSymbol then
    begin
      Sample := TDrawPin.Create(Sheet.Options);
      try
        Result := ObjectProps(Sample);
      finally
        Sample.Free;
      end;
    end;
    Exit;
  end;
  Sample := ToolSampleOf(Sheet.Options, ATool);
  if Sample = nil then
    Exit;
  try
    All := ObjectProps(Sample);
  finally
    Sample.Free;
  end;
  n := 0;
  SetLength(Result, Length(All));
  for i := 0 to High(All) do
  begin
    Skip := False;
    for j := 0 to High(PER_OBJECT) do if All[i].Name = PER_OBJECT[j] then
      Skip := True;
    { the Text, Label, Note and Power tools offer what the text will say and the way it will read, to be chosen before it is placed }
    if (ATool in [vtText, vtLabel, vtNote, vtPower]) and ((All[i].Name = 'text') or (All[i].Name = 'dir')) then
      Skip := False;
    if not Skip then begin
      Result[n] := All[i];
      Inc(n);
    end;
  end;
  { the way a wire, bus or line is drawn is the tool's, not a property of the object }
  if ATool in [vtWire, vtLine, vtBus] then
  begin
    SetLength(Result, n + 1);
    Result[n] := WireAngleDef;
    Inc(n);
  end;
  { the kind of arc the Arc tool draws next is the tool's, not a property of the object }
  if ATool = vtArc then
  begin
    SetLength(Result, n + 1);
    Result[n] := ArcTypeDef;
    Inc(n);
  end;
  SetLength(Result, n);
end;

{ ===========================================================================
  TSchematicView.FillPendingPin  (procedure)
  Parameters:
    Pn: TDrawPin - a new pin
  Notes:
    The pin starts as the one placed last (if it is still there): its direction, length, shape and so on, with its number and name counted on; a first pin starts as a new
    pin does. What was chosen in the Pin tool's panel before the pin is put down (FToolDefaults) is applied over that. Used for the panel's values and for the pin placed.
  =========================================================================== }
procedure TSchematicView.FillPendingPin(Pn: TDrawPin);
var
  Prev: TDrawPin;
  i: Integer;
  Num, PName: String;
begin
  Prev := nil;
  if FLastPinId <> 0 then
    for i := 0 to Sheet.Drawing.Count - 1 do
      if (Sheet.Drawing[i].Id = FLastPinId) and (Sheet.Drawing[i] is TDrawPin) then
        Prev := TDrawPin(Sheet.Drawing[i]);
  if Prev <> nil then
  begin
    Pn.Dir := Prev.Dir; Pn.Length := Prev.Length; Pn.NumberPos := Prev.NumberPos; Pn.Which := Prev.Which;
    Pn.Elec := Prev.Elec; Pn.Show := Prev.Show; Pn.CentreName := Prev.CentreName;
    Num := Prev.Number; PName := Prev.Str;
    NextPinValues(Num, PName, FPinDir, FNameDir);
    Pn.Number := Num; Pn.Str := PName;
  end
  else
  begin
    Pn.Number := '1'; Pn.Str := '';
  end;
  if FToolDefaults[vtPin] <> nil then
    for i := 0 to FToolDefaults[vtPin].Count - 1 do
      SetProp(Pn, FToolDefaults[vtPin].Names[i], FToolDefaults[vtPin].ValueFromIndex[i]);
end;

{ ===========================================================================
  TSchematicView.ToolPropValue  (function)
  Parameters:
    ATool: TViewTool
    const AName: String - the name
  Returns:
    String
  Notes:
    Used to fill the editors of the tool's Properties panel.
  =========================================================================== }
function TSchematicView.ToolPropValue(ATool: TViewTool; const AName: String): String;
var
  Sample: TDrawingObject;
  i: Integer;
begin
  Result := '';
  if Sheet = nil then
    Exit;
  if (ATool in [vtText, vtLabel]) and (AName = 'text') then begin
    Result := FloatTextFor(ATool);
    Exit;
  end;
  if (ATool = vtPlace) and (FGhost <> nil) then
  begin
    GetProp(FGhost, AName, Result);      { (the symbol being placed holds what was chosen for it) }
    Exit;
  end;
  if ATool = vtPin then
  begin
    Sample := TDrawPin.Create(Sheet.Options);       { (the pin as the next one will be) }
    try
      FillPendingPin(TDrawPin(Sample));
      GetProp(Sample, AName, Result);
    finally
      Sample.Free;
    end;
    Exit;
  end;
  if AName = 'wire.angle' then
  begin
    Result := ChoiceText(AngleChoices, Ord(WireAngles[ATool]));
    Exit;
  end;
  if AName = 'arc.type' then
  begin
    Result := ChoiceText(ArcChoices, Ord(FArcToolType = Arc_out));
    Exit;
  end;
  Sample := ToolSampleOf(Sheet.Options, ATool);
  if Sample = nil then
    Exit;
  try
    if FToolDefaults[ATool] <> nil then
      for i := 0 to FToolDefaults[ATool].Count - 1 do
        SetProp(Sample, FToolDefaults[ATool].Names[i], FToolDefaults[ATool].ValueFromIndex[i]);
    GetProp(Sample, AName, Result);
  finally
    Sample.Free;
  end;
end;

{ ===========================================================================
  TSchematicView.InitUserFont  (procedure)
  Parameters:  none
  Notes:
    Gives FUserFont the default font of a new text of this design (face, height, bold, italic):
    done whenever a design is loaded or made, so every design starts from its own defaults.
  =========================================================================== }
procedure TSchematicView.InitUserFont;
var
  Sample: TDrawingObject;
  V: String;
begin
  FUserFont.Name := 'Arial';
  FUserFont.Height := 10;
  FUserFont.Style := [];
  if Sheet = nil then
    Exit;
  Sample := TDrawText.Create(Sheet.Options);
  try
    if GetProp(Sample, 'font.face', V) then
      FUserFont.Name := V;
    if GetProp(Sample, 'font.height', V) then
      FUserFont.Height := StrToIntDef(V, 10);
    if GetProp(Sample, 'font.bold', V) and (V = '1') then
      FUserFont.Style := FUserFont.Style + [fsBold];
    if GetProp(Sample, 'font.italic', V) and (V = '1') then
      FUserFont.Style := FUserFont.Style + [fsItalic];
  finally
    Sample.Free;
  end;
end;

{ ===========================================================================
  TSchematicView.ApplyUserFont  (procedure)
  Parameters:
    ATool: TViewTool
  Notes:
    When a tool whose objects have a font is chosen, the tool starts with FUserFont: the font
    last asked for, whichever tool it was asked in.
  =========================================================================== }
procedure TSchematicView.ApplyUserFont(ATool: TViewTool);
var
  Sample: TDrawingObject;
  V: String;
begin
  Sample := ToolSampleOf(Sheet.Options, ATool);
  if Sample = nil then
    Exit;
  try
    if not GetProp(Sample, 'font.face', V) then
      Exit;
  finally
    Sample.Free;
  end;
  SetToolDefault(ATool, 'font.face', FUserFont.Name);
  SetToolDefault(ATool, 'font.height', IntToStr(FUserFont.Height));
  SetToolDefault(ATool, 'font.bold', IntToStr(Ord(fsBold in FUserFont.Style)));
  SetToolDefault(ATool, 'font.italic', IntToStr(Ord(fsItalic in FUserFont.Style)));
end;

{ ===========================================================================
  TSchematicView.TakeUserFont  (procedure)
  Parameters:
    Obj: TDrawingObject - the drawing object
  Notes:
    If the object has a font, that font becomes FUserFont, so the next one placed (with this or
    another tool) has it. Objects with no font change nothing.
  =========================================================================== }
procedure TSchematicView.TakeUserFont(Obj: TDrawingObject);
var
  V: String;
begin
  if not GetProp(Obj, 'font.face', V) then
    Exit;
  FUserFont.Name := V;
  if GetProp(Obj, 'font.height', V) then
    FUserFont.Height := StrToIntDef(V, FUserFont.Height);
  if GetProp(Obj, 'font.bold', V) then
    if V = '1' then
      FUserFont.Style := FUserFont.Style + [fsBold]
    else
      FUserFont.Style := FUserFont.Style - [fsBold];
  if GetProp(Obj, 'font.italic', V) then
    if V = '1' then
      FUserFont.Style := FUserFont.Style + [fsItalic]
    else
      FUserFont.Style := FUserFont.Style - [fsItalic];
end;

{ ===========================================================================
  TSchematicView.MakeFloat  (function)
  Parameters:
    ATool: TViewTool
    const P: TDPoint - a point, in design units
  Returns:
    TDrawingObject
  Notes:
    Made as PlaceSimple makes it, with what was chosen in the tool's panel.
  =========================================================================== }
function TSchematicView.MakeFloat(ATool: TViewTool; const P: TDPoint): TDrawingObject;
var
  Pw: TDrawPower;
  BS: TDrawBusSlash;
  i: Integer;
begin
  case ATool of
    vtJunction: begin
      Result := TDrawJunction.Create(Sheet.Options);
      Result.PointA := P;
      Result.PointB := P;
    end;
    vtNoConnect: begin
      Result := TDrawNoConnect.Create(Sheet.Options);
      Result.PointA := P;
      Result.PointB := P;
    end;
    vtPower:
      begin
        Pw := TDrawPower.Create(Sheet.Options);
        Pw.PointA := P; Pw.PointB := P; Pw.Which := 0; Pw.Dir := 0; Pw.Str := 'VCC';
        Result := Pw;
      end;
    vtBusSlash:
      begin
        BS := TDrawBusSlash.Create(Sheet.Options);
        BS.PointA := P; BS.PointB := DPoint(P.x + 10, P.y - 10); BS.Dir := 0;
        Result := BS;
      end;
  else
    Result := nil;
  end;
  if (Result <> nil) and (FToolDefaults[ATool] <> nil) then
    for i := 0 to FToolDefaults[ATool].Count - 1 do
      SetProp(Result, FToolDefaults[ATool].Names[i], FToolDefaults[ATool].ValueFromIndex[i]);
  if Result <> nil then
    Result.UpdateLayout;
end;

{ ===========================================================================
  TSchematicView.SetToolDefault  (procedure)
  Parameters:
    ATool: TViewTool
    const AName: String - the name
    const AValue: String - the value
  Notes:
    From now on the tool gives every new object this value for this property. The view repaints
    when it is the current tool so that the ghost (e.g. the wire being drawn) follows the
    choice. 'wire.angle' is the exception: the angle a wire, bus or line is drawn at is kept for
    the whole program session (WireAngles) and given to the tool at once.
  =========================================================================== }
procedure TSchematicView.SetToolDefault(ATool: TViewTool; const AName, AValue: String);
begin
  if (ATool = vtPlace) and (FGhost <> nil) then
  begin
    SetProp(FGhost, AName, AValue);      { the next click puts down a copy of the symbol as it is now }
    Invalidate;
    Exit;
  end;
  if AName = 'arc.type' then
  begin
    ArcToolType := IfThen(ChoiceIndex(ArcChoices, AValue) = 1, Arc_out, Arc_in);
    Invalidate;
    Exit;
  end;
  if AName = 'wire.angle' then
  begin
    { not a property of the objects: remembered for the session, and used by the tool at once }
    WireAngles[ATool] := TAngleMode(Max(0, Min(ChoiceIndex(AngleChoices, AValue), Ord(High(TAngleMode)))));
    if (ATool = FTool) and (FWire <> nil) then
      FWire.Angle := WireAngles[ATool];
    Invalidate;
    Exit;
  end;
  if FToolDefaults[ATool] = nil then
  begin
    FToolDefaults[ATool] := TStringList.Create;
    FToolDefaults[ATool].NameValueSeparator := '=';
  end;
  FToolDefaults[ATool].Values[AName] := AValue;
  if ATool = FTool then
    Invalidate;                  // the ghost follows what was chosen
  { a font chosen in the tool's panel is the one asked for }
  if AName = 'font.face' then
    FUserFont.Name := AValue
  else if AName = 'font.height' then
    FUserFont.Height := StrToIntDef(AValue, FUserFont.Height)
  else if AName = 'font.bold' then begin if AValue = '1' then
    FUserFont.Style := FUserFont.Style + [fsBold]
  else
    FUserFont.Style := FUserFont.Style - [fsBold]; end
  else if AName = 'font.italic' then begin if AValue = '1' then
    FUserFont.Style := FUserFont.Style + [fsItalic]
  else
    FUserFont.Style := FUserFont.Style - [fsItalic]; end;
end;

{ ===========================================================================
  TSchematicView.WireAngleNow  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    For the self-test script.
  =========================================================================== }
function TSchematicView.WireAngleNow: Integer;
begin
  if FWire = nil then
    Result := -1
  else
    Result := Ord(FWire.Angle);
end;

{ ===========================================================================
  TSchematicView.ClearToolDefaults  (procedure)
  Parameters:  none
  Notes:
    Forgets the properties chosen for the tools.
  =========================================================================== }
procedure TSchematicView.ClearToolDefaults;
var
  T: TViewTool;
begin
  for T := Low(TViewTool) to High(TViewTool) do FreeAndNil(FToolDefaults[T]);
end;

{ ===========================================================================
  TSchematicView.ZoomPercent  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    100 is one pixel to each design unit (0.2 mm), the scale of a 100% PNG export.
  =========================================================================== }
function TSchematicView.ZoomPercent: Integer;
begin
  Result := Round(FZoom * 100);
end;

{ ===========================================================================
  TSchematicView.KeyDown  (procedure)
  Parameters:
    var Key: Word - the key code (var)
    Shift: TShiftState - modifier keys
  Notes:
    Keyboard commands: Esc finishes or cancels what is being drawn, Delete deletes the
    selection, Ctrl+Z and Ctrl+Y undo and redo, R and X rotate and mirror a symbol being placed.
  =========================================================================== }
procedure TSchematicView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_ESCAPE:
      begin
        if FPasting then
          CancelPaste
        else if (FTool in [vtWire, vtLine, vtBus]) and (FWire <> nil) and (FWire.Segment = 0) then
        begin
          BeginChange(rsDraw);
          FWire.RButtonDown;
          CommitChange(True);
        end
        else if FStage = 1 then
        begin
          FStage := 0; SetLength(FPoly, 0); SetLength(FPolyArcs, 0); FXTarget := nil;
        end
        else if FTool <> vtSelect then
          CancelTool
        else
          ClearSelection;
        Invalidate;
      end;
    VK_DELETE: if FTool = vtSelect then
                 DeleteSelection;
    { the arrow keys move what is chosen (one grid step with snap, one pixel without) }
    VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN: ArrowKey(Key, Shift);
    { Ctrl+Z, Y, C, V, X, U, L and R are the shortcuts of the Edit menu items: the form handles them, so the view must not do them a second time
      (a paste done twice put the first copy down where it was cut from) }
    { while a pasted block floats, R and X turn / flip it as Ctrl+L / Ctrl+R / Flip do }
    VK_R: if (not (ssCtrl in Shift)) and FPasting then
            RotateSelection(2)
          else if (not (ssCtrl in Shift)) and (FTool = vtPlace) and (FGhost <> nil) then begin FGhost.RotateAbout(DPoint(0, 0), 2); Invalidate; if Assigned(FOnToolChanged) then
            FOnToolChanged(Self); end;
    VK_X: if (not (ssCtrl in Shift)) and FPasting then
            RotateSelection(4)
          else if (not (ssCtrl in Shift)) and (FTool = vtPlace) and (FGhost <> nil) then begin FGhost.RotateAbout(DPoint(0, 0), 4); Invalidate; if Assigned(FOnToolChanged) then
            FOnToolChanged(Self); end;
  end;
end;

{ ===========================================================================
  TSchematicView.ClipFormat  (function)
  Parameters:  none
  Returns:
    TClipboardFormat - the format id
  Notes:
    The clipboard format that carries TinyCAD drawings, registered under the name "TinyCAD
    Design" the first time it is needed.
  =========================================================================== }
function TSchematicView.ClipFormat: TClipboardFormat;
begin
  if FClipFmt = 0 then
    FClipFmt := RegisterClipboardFormat(CLIPBOARD_FORMAT_NAME);
  Result := FClipFmt;
end;

{ ===========================================================================
  TSchematicView.StartDragEngine  (procedure)
  Parameters:  none
  Notes:
    Creates the wire engine for a move of the current selection, using the area the selection
    was picked with.
  =========================================================================== }
procedure TSchematicView.StartDragEngine;
var
  i: Integer;
begin
  FreeAndNil(FDragEng);
  FDragEng := TWireEngine.Create(FDesign, Sheet);
  if FEndLine <> nil then
    FDragEng.Selected.Add(FEndLine)
  else
    for i := 0 to FSelected.Count - 1 do FDragEng.Selected.Add(FSelected[i]);
  if FDragEng.Selected.Count = 1 then
    FDragEng.SingleSelected := TDrawingObject(FDragEng.Selected[0]);
  FDragEng.BeginDrag(FAreaA, FAreaB);
  if (FEndLine <> nil) and ((FEndLine.GetType = xWire) or (FEndLine.GetType = xBus)) then
  begin
    { several wires chosen (and not wholly picked): the end handle pulls the end of each of them that lies nearest to the handle, not only the one that was pressed }
    SetLength(FDragEng.PullPoints, 1);
    FDragEng.PullPoints[0] := FAreaA;
    for i := 0 to FSelected.Count - 1 do
      if (TObject(FSelected[i]) is TDrawLine) and (TObject(FSelected[i]) <> FEndLine) and
         ((TDrawLine(TObject(FSelected[i])).GetType = xWire) or (TDrawLine(TObject(FSelected[i])).GetType = xBus)) and (not WireWhollyPicked(TDrawLine(TObject(FSelected[i])))) then
      begin
        with TDrawLine(TObject(FSelected[i])) do
        begin
          FDragEng.Selected.Add(FSelected[i]);
          SetLength(FDragEng.PullPoints, Length(FDragEng.PullPoints) + 1);
          if Sqr(PointA.x - FAreaA.x) + Sqr(PointA.y - FAreaA.y) <= Sqr(PointB.x - FAreaA.x) + Sqr(PointB.y - FAreaA.y) then
            FDragEng.PullPoints[High(FDragEng.PullPoints)] := PointA
          else
            FDragEng.PullPoints[High(FDragEng.PullPoints)] := PointB;
        end;
      end;
    if FDragEng.Selected.Count > 1 then
      FDragEng.SingleSelected := nil;
  end;
end;

{ ===========================================================================
  TSchematicView.PruneSelection  (procedure)
  Parameters:  none
  Notes:
    Removes from the selection any object that is no longer on the sheet (merging or cleaning
    wires can delete selected ones).
  =========================================================================== }
procedure TSchematicView.PruneSelection;
var
  i: Integer;
begin
  for i := FSelected.Count - 1 downto 0 do
    if Sheet.Drawing.IndexOf(TDrawingObject(FSelected[i])) < 0 then
      FSelected.Delete(i);
end;

{ ===========================================================================
  TSchematicView.CopySelectionToFile  (function)
  Parameters:
    const AFileName: String - path of the file
  Returns:
    Integer
  Notes:
    TinyCAD's "Copy to": the selected objects of the sheet are saved as a design file of their
    own, in the same form as what Copy puts on the clipboard (the sheet's name and details, the
    fonts, styles and symbols they use, and the objects themselves). The data is made in memory
    first, so a failure never leaves an empty file or spoils an existing one. The document
    itself is not changed (it keeps its name and its unsaved-changes mark). Errors are raised.
  =========================================================================== }
function TSchematicView.CopySelectionToFile(const AFileName: String): Integer;
var
  MS: TMemoryStream;
begin
  Result := 0;
  if (Sheet = nil) or (FSelected.Count = 0) then
    Exit;
  MS := TMemoryStream.Create;
  try
    Result := CopySelection(Sheet, FSelected, MS);
    if Result > 0 then
      MS.SaveToFile(AFileName);
  finally
    MS.Free;
  end;
end;

{ ===========================================================================
  TSchematicView.CopyToClipboard  (procedure)
  Parameters:  none
  Notes:
    Puts the selected objects on the clipboard in TinyCAD's format ("TinyCAD Design"), so they
    can be pasted here or into TinyCAD.
  =========================================================================== }
procedure TSchematicView.CopyToClipboard;
var
  MS: TMemoryStream;
begin
  if (Sheet = nil) or (FSelected.Count = 0) then
    Exit;
  MS := TMemoryStream.Create;
  try
    if CopySelection(Sheet, FSelected, MS) = 0 then
      Exit;
    MS.Position := 0;
    Clipboard.Open;
    try
      Clipboard.Clear;
      Clipboard.AddFormat(ClipFormat, MS);
    finally
      Clipboard.Close;
    end;
    Status(Format(rsCopiedObjectS, [FSelected.Count]));
  finally
    MS.Free;
  end;
end;

{ ===========================================================================
  TSchematicView.CutSelection  (procedure)
  Parameters:  none
  Notes:
    Copies the selection to the clipboard and deletes it.
  =========================================================================== }
procedure TSchematicView.CutSelection;
begin
  if (Sheet = nil) or (FSelected.Count = 0) then
    Exit;
  CopyToClipboard;
  DeleteSelection;
end;

{ ===========================================================================
  TSchematicView.ClipboardHasDrawing  (function)
  Parameters:  none
  Returns:
    Boolean - True if a paste could be tried
  Notes:
    Whether the clipboard holds TinyCAD data or text that might be drawing XML.
  =========================================================================== }
function TSchematicView.ClipboardHasDrawing: Boolean;
begin
  Result := Clipboard.HasFormat(ClipFormat) or Clipboard.HasFormat(CF_TEXT);
end;

{ ===========================================================================
  TSchematicView.ClipboardToStream  (procedure)
  Parameters:
    S: TStream - receives the data, positioned at the start
  Notes:
    Reads the clipboard into a stream: the "TinyCAD Design" data, or, as TinyCAD does, plain
    text tried as drawing XML.
  =========================================================================== }
procedure TSchematicView.ClipboardToStream(S: TStream);
var
  T: String;
begin
  if Clipboard.HasFormat(ClipFormat) then
    Clipboard.GetFormat(ClipFormat, S)
  else if Clipboard.HasFormat(CF_TEXT) then
  begin
    { as TinyCAD does, text on the clipboard is tried as drawing XML }
    T := Clipboard.AsText;
    if T <> '' then
      S.WriteBuffer(T[1], Length(T));
  end;
  S.Position := 0;
end;

{ ===========================================================================
  TSchematicView.ClipboardText  (function)
  Parameters:  none
  Returns:
    String - the data, empty when there is none
  Notes:
    The clipboard's drawing data as text (for tests).
  =========================================================================== }
function TSchematicView.ClipboardText: String;
var
  MS: TMemoryStream;
begin
  Result := '';
  MS := TMemoryStream.Create;
  try
    ClipboardToStream(MS);
    if MS.Size > 0 then
    begin
      SetLength(Result, MS.Size);
      MS.ReadBuffer(Result[1], MS.Size);
    end;
  finally
    MS.Free;
  end;
end;

{ ===========================================================================
  TSchematicView.SetClipboardText  (procedure)
  Parameters:
    const Data: String - the data
  Notes:
    Replaces the clipboard's contents with the given text as TinyCAD data (for tests, to stand
    in for a copy made in TinyCAD).
  =========================================================================== }
procedure TSchematicView.SetClipboardText(const Data: String);
var
  MS: TMemoryStream;
begin
  MS := TMemoryStream.Create;
  try
    if Data <> '' then
      MS.WriteBuffer(Data[1], Length(Data));
    MS.Position := 0;
    Clipboard.Open;
    try
      Clipboard.Clear;
      Clipboard.AddFormat(ClipFormat, MS);
    finally
      Clipboard.Close;
    end;
  finally
    MS.Free;
  end;
end;

{ ===========================================================================
  TSchematicView.PasteFromClipboard  (procedure)
  Parameters:  none
  Notes:
    Pastes the clipboard: the data's resources are merged into the sheet, the new objects are
    added and selected, and the block follows the mouse (its bottom-right corner under the
    pointer) until a click drops it. Data that is not a TinyCAD drawing leaves everything
    unchanged and says so in the status line.
  =========================================================================== }
procedure TSchematicView.PasteFromClipboard;
var
  MS: TMemoryStream;
begin
  if Sheet = nil then
    Exit;
  MS := TMemoryStream.Create;
  try
    ClipboardToStream(MS);
    BeginPasteFrom(MS, rsPaste, rsTheClipboardDoesNotHold,
      rsClickToPlaceThePasted, rsPasted);
  finally
    MS.Free;
  end;
end;

{ ===========================================================================
  TSchematicView.ImportFromFile  (function)
  Parameters:
    const AFileName: String - path of the file
  Returns:
    Integer
  Notes:
    TinyCAD's Import (CTinyCadDoc::Import): the objects of another design are brought into this
    sheet and follow the mouse until a click places them, exactly as a paste does. Only the
    first sheet of a file with several sheets is read, and the file's page details (size, title,
    rulers) are not applied; its fonts, styles, fills and symbol definitions are merged with
    this design's. The whole import is one undo step named Import. Errors opening the file are
    raised.
  =========================================================================== }
function TSchematicView.ImportFromFile(const AFileName: String): Integer;
var
  MS: TMemoryStream;
begin
  Result := 0;
  if Sheet = nil then
    Exit;
  MS := TMemoryStream.Create;
  try
    MS.LoadFromFile(AFileName);
    Result := BeginPasteFrom(MS, rsImport, rsThatFileIsNotA,
      rsClickToPlaceTheImported, rsImported);
  finally
    MS.Free;
  end;
end;

{ ===========================================================================
  TSchematicView.BeginPasteFrom  (function)
  Parameters:
    Src: TStream
    const UndoName: String - text
    const FailMsg: String - text
    const PlaceMsg: String - text
    const DoneMsg: String - text
  Returns:
    Integer
  Notes:
    The part that pasting and importing share: the data's resources are merged into the sheet,
    the new objects are added and selected, and the block follows the mouse (its bottom-right
    corner under the pointer) until a click drops it. A block that was still following the mouse
    is placed first.
  =========================================================================== }
function TSchematicView.BeginPasteFrom(Src: TStream; const UndoName, FailMsg, PlaceMsg, DoneMsg: String): Integer;
var
  Imp: TList;
  i: Integer;
begin
  Result := 0;
  if Sheet = nil then
    Exit;
  if FPasting then
    DropPaste;
  CancelTool;
  Imp := TList.Create;
  try
    BeginChange(UndoName);
    if not PasteStream(FDesign, Sheet, Src, Imp) then
    begin
      CommitChange(False);
      Status(FailMsg);
      Exit;
    end;
    Result := StartBlock(Imp, PlaceMsg, DoneMsg);
  finally
    Imp.Free;
  end;
end;

{ ===========================================================================
  TSchematicView.StartBlock  (function)
  Parameters:
    Imp: TList
    const PlaceMsg: String - text
    const DoneMsg: String - text
  Returns:
    Integer
  Notes:
    The objects are selected and made into a block whose bottom-right corner follows the mouse
    until a click drops it (right click or Esc cancels, putting the sheet back as it was).
    Shared by paste, import and insert picture (CDrawBlockImport). The 3-phase buses among the
    objects get group numbers of their own, so a copy is not part of the bus it was copied from.
  =========================================================================== }
function TSchematicView.StartBlock(Imp: TList; const PlaceMsg, DoneMsg: String): Integer;
var
  i, k: Integer;
  Olds, News: array of Integer;
  L: TDrawLine;
begin
  { the 3-phase buses brought in are groups of their own, not part of the ones they were copied from }
  SetLength(Olds, 0); SetLength(News, 0);
  for i := 0 to Imp.Count - 1 do
    if (TObject(Imp[i]) is TDrawLine) and (TDrawLine(Imp[i]).Kind = xBus) and (TDrawLine(Imp[i]).Group <> 0) then
    begin
      L := TDrawLine(Imp[i]);
      k := High(Olds);
      while (k >= 0) and (Olds[k] <> L.Group) do
        Dec(k);
      if k < 0 then
      begin
        SetLength(Olds, Length(Olds) + 1); SetLength(News, Length(News) + 1);
        Olds[High(Olds)] := L.Group; News[High(News)] := FDesign.NextObjectId;
        k := High(Olds);
      end;
      L.Group := News[k];
    end;
  FSelected.Clear;
  for i := 0 to Imp.Count - 1 do FSelected.Add(Imp[i]);
  Result := Imp.Count;
  FBlockRef := BlockReference(Sheet, Imp);
  FPasting := True;
  FPasteDone := DoneMsg;
  FAreaA := FBlockRef;
  FAreaB := FBlockRef;
  StartDragEngine;
  { as in TinyCAD the block first stands exactly where it was copied from (so it shows at once, and a copy to the same place on the next page is
    just a click); it follows the pointer from the first mouse move }
  Sheet.UpdateLayout;
  { moving or laying out may merge or delete wires: never keep a selected object that is gone }
  k := FSelected.Count;
  PruneSelection;
  if FSelected.Count <> k then
    StartDragEngine;
  SelectionChanged;
  Status(PlaceMsg);
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.InsertPictureFile  (function)
  Parameters:
    const AFileName: String - path of the file
    out Err: String - text (out: set by the call)
  Returns:
    Boolean
  Notes:
    TinyCAD's Insert picture: the picture is kept in the design (identical pictures once), a
    picture object of the size it is first given (a unit a pixel, at most 500 either way) is
    added to the sheet, and it follows the mouse until a click places it. One undo step named
    Insert picture; a right click or Esc cancels it and takes the picture out of the design
    again.
  =========================================================================== }
function TSchematicView.InsertPictureFile(const AFileName: String; out Err: String): Boolean;
var
  ImgType: String;
  Data: TBytes;
  W, H: Integer;
  Obj: TDrawMetaFile;
  Imp: TList;
begin
  Result := False;
  if Sheet = nil then
    Exit;
  if not LoadPictureFile(AFileName, ImgType, Data, Err) then
    Exit;
  if FPasting then
    DropPaste;
  CancelTool;
  BeginChange(rsInsertPicture);
  Obj := TDrawMetaFile.Create(Sheet.Options);
  Obj.Image := Sheet.Options.AddImage(ImgType, Data);
  if ReadImageSize(Data, ImgType, W, H) then
    Obj.FitToPicture(W, H);
  AddNew(Obj);
  Imp := TList.Create;
  try
    Imp.Add(Obj);
    StartBlock(Imp, rsClickToPlaceThePicture, rsPicturePlaced);
  finally
    Imp.Free;
  end;
  Result := True;
end;

{ ===========================================================================
  TSchematicView.DropPaste  (procedure)
  Parameters:  none
  Notes:
    Places the pasted block where it is: joins wires that now meet, adds or removes junctions,
    and keeps the whole paste as one undo step.
  =========================================================================== }
procedure TSchematicView.DropPaste;
begin
  if not FPasting then
    Exit;
  FPasting := False;
  if FDragEng <> nil then
  begin
    FDragEng.FinishDrag;        // join wires that now meet, and add or remove junctions
    FreeAndNil(FDragEng);
  end;
  PruneSelection;
  CommitChange(True);
  if FPasteDone <> '' then
    Status(FPasteDone)
  else
    Status(rsPasted);
end;

{ ===========================================================================
  TSchematicView.CancelPaste  (procedure)
  Parameters:  none
  Notes:
    Throws the pasted block away (right click or Esc while it follows the mouse): the objects
    are deleted and no undo step is kept.
  =========================================================================== }
procedure TSchematicView.CancelPaste;
var
  i, Sh: Integer;
  Back: TIntArray;
begin
  if not FPasting then
    Exit;
  FPasting := False;
  FreeAndNil(FDragEng);
  FSelected.Clear;
  if (FUndo <> nil) and FUndo.Rollback(Back, Sh) then
  begin
    { the sheet goes back to exactly what it was before the paste began, not just minus the objects that came in }
    FSheetIndex := Max(0, Min(Sh, FDesign.SheetCount - 1));
    RestoreSelection(Back);
    Sheet.UpdateLayout;
    UpdateLinks(FDesign);
    if Assigned(FOnUndoChanged) then
      FOnUndoChanged(Self);
  end
  else
  begin
    for i := FSelected.Count - 1 downto 0 do Sheet.Drawing.Remove(TDrawingObject(FSelected[i]));
    FSelected.Clear;
    CommitChange(False);
  end;
  SelectionChanged;
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.DuplicateSelection  (procedure)
  Parameters:  none
  Notes:
    Copies the selection and pastes it, so the copy follows the mouse until dropped.
  =========================================================================== }
procedure TSchematicView.DuplicateSelection;
begin
  if (Sheet = nil) or (FSelected.Count = 0) then
    Exit;
  CopyToClipboard;
  PasteFromClipboard;
end;

{ ===========================================================================
  TSchematicView.RotateSelection  (procedure)
  Parameters:
    NewDir: Integer - 2 = rotate left, 3 = rotate right, 4 = flip left to right
  Notes:
    While a symbol is being placed (the Place tool, a ghost following the pointer) the ghost is
    turned instead, about its own origin, as the R and X keys do.
    Rotates or flips the selected objects about the centre of their extent
    (CDrawEditItem::ChangeDir): the centre is the middle of the selection's bounding box snapped
    to the grid, with TinyCAD's correction when snapping moved it off the middle. Construction
    objects such as rulers are left alone. Junctions are re-checked afterwards but wires
    attached to the objects do not follow. One undo step.
  =========================================================================== }
procedure TSchematicView.RotateSelection(NewDir: Integer);
var
  i: Integer;
  O: TDrawingObject;
  L, R, T, B, X1, X2, Y1, Y2, Grid: Double;
  Found: Boolean;
  Centre, TopLeft, BottomRight: TDPoint;
  Eng: TWireEngine;
begin
  { while a symbol is being placed the commands turn the symbol that follows the pointer (as the R and X keys do) }
  if (FTool = vtPlace) and (FGhost <> nil) and (not FPasting) then
  begin
    FGhost.RotateAbout(DPoint(0, 0), NewDir);
    Invalidate;
    if Assigned(FOnToolChanged) then
      FOnToolChanged(Self);
    Exit;
  end;
  if (Sheet = nil) or (FSelected.Count = 0) then
    Exit;
  { the extent of the selected objects (construction objects such as rulers stay out of it) }
  Found := False;
  L := 0; R := 0; T := 0; B := 0;
  for i := 0 to FSelected.Count - 1 do
  begin
    O := TDrawingObject(FSelected[i]);
    if O.IsConstruction or (not HasCorners(O)) then
      Continue;
    X1 := Min(O.PointA.x, O.PointB.x); X2 := Max(O.PointA.x, O.PointB.x);
    Y1 := Min(O.PointA.y, O.PointB.y); Y2 := Max(O.PointA.y, O.PointB.y);
    if not Found then begin
      L := X1;
      R := X2;
      T := Y1;
      B := Y2;
      Found := True;
    end
    else begin
      L := Min(L, X1);
      R := Max(R, X2);
      T := Min(T, Y1);
      B := Max(B, Y2);
    end;
  end;
  if not Found then
    Exit;
  { the centre of rotation: the middle of the extent, snapped to the grid, with TinyCAD's
    correction for when snapping moved it off the true middle }
  Centre := Sheet.Snap.Snap(DPoint((L + R) / 2, (T + B) / 2));
  Grid := Sheet.Snap.Grid;
  if Grid <> 0 then
  begin
    TopLeft := Sheet.Snap.Snap(DPoint(L, T));
    BottomRight := Sheet.Snap.Snap(DPoint(R, B));
    if Centre.x <> (TopLeft.x + BottomRight.x) / 2 then
    begin
      if Centre.y = (TopLeft.y + BottomRight.y) / 2 then
        Centre := DPoint(Centre.x + Grid, Centre.y);
    end
    else if Centre.y <> (TopLeft.y + BottomRight.y) / 2 then
    begin
      if Centre.x = (TopLeft.x + BottomRight.x) / 2 then
        Centre := DPoint(Centre.x, Centre.y + Grid);
    end;
  end;
  { a floating pasted block is part of the paste's own undo step, which the drop commits: no step of its own }
  if not FPasting then
    case NewDir of
      2: BeginChange(rsRotateLeft);
      3: BeginChange(rsRotateRight);
    else
      BeginChange(rsFlip);
    end;
  Eng := TWireEngine.Create(FDesign, Sheet);
  try
    for i := 0 to FSelected.Count - 1 do
    begin
      O := TDrawingObject(FSelected[i]);
      if O.IsConstruction then
        Continue;
      Eng.AddObjectToTodo(O);
      O.RotateAbout(Centre, NewDir);
      Eng.AddObjectToTodo(O);
    end;
    if not FPasting then
      Eng.CheckTodoList(False);     // (a floating paste is joined to what it meets when it is dropped)
  finally
    Eng.Free;
  end;
  if FPasting then
  begin
    { the block keeps following the pointer: its reference corner is worked out again and put back under the pointer }
    FBlockRef := BlockReference(Sheet, FSelected);
    FAreaA := FBlockRef;
    FAreaB := FBlockRef;
    StartDragEngine;
    Sheet.UpdateLayout;
    Invalidate;
    Exit;
  end;
  CommitChange(True);
  AfterEdit;
end;

{ ===========================================================================
  TSchematicView.AlignSelectionToGrid  (function)
  Parameters:
    AGrid: Double - number
  Returns:
    Integer
  Notes:
    Moves each selected object, without changing its shape, so that its first end (PointA; for a
    pin the end that connects) is on the nearest grid dot. Only x and y are shifted; an object
    already on the grid is left alone. One undo step named Align to grid, and nothing is
    recorded when nothing moved.
  =========================================================================== }
function TSchematicView.AlignSelectionToGrid(AGrid: Double): Integer;
var
  i: Integer;
  O: TDrawingObject;
  D: TDPoint;
begin
  Result := 0;
  if (Sheet = nil) or (FSelected.Count = 0) then
    Exit;
  if AGrid <= 0 then
    AGrid := Sheet.Snap.Grid;
  if AGrid <= 0 then
    Exit;
  BeginChange(rsAlignToGrid);
  for i := 0 to FSelected.Count - 1 do
  begin
    O := TDrawingObject(FSelected[i]);
    if O.IsConstruction then
      Continue;
    D := DPoint(Floor(O.PointA.x / AGrid + 0.5) * AGrid - O.PointA.x, Floor(O.PointA.y / AGrid + 0.5) * AGrid - O.PointA.y);
    if (Abs(D.x) > 1E-9) or (Abs(D.y) > 1E-9) then
    begin
      O.Shift(D);
      Inc(Result);
    end;
  end;
  CommitChange(Result > 0);
  if Result > 0 then
    AfterEdit;
end;

{ ===========================================================================
  TSchematicView.BringToFront  (procedure)
  Parameters:  none
  Notes:
    Moves the selected objects to the end of the drawing, so they are drawn on top, keeping
    their order among themselves (CTinyCadDoc::BringToFront). One undo step.
  =========================================================================== }
procedure TSchematicView.BringToFront;
var
  i: Integer;
  Moved: TList;
  O: TDrawingObject;
begin
  if (Sheet = nil) or (FSelected.Count = 0) then
    Exit;
  BeginChange(rsBringToFront);
  Moved := TList.Create;
  try
    { take the selected objects out (the list would free them), then put them back at the end in their old order }
    Sheet.Drawing.OwnsObjects := False;
    try
      for i := Sheet.Drawing.Count - 1 downto 0 do
        if FSelected.IndexOf(Sheet.Drawing[i]) >= 0 then
        begin
          Moved.Insert(0, Sheet.Drawing[i]);
          Sheet.Drawing.Delete(i);
        end;
      for i := 0 to Moved.Count - 1 do Sheet.Drawing.Add(TDrawingObject(Moved[i]));
    finally
      Sheet.Drawing.OwnsObjects := True;
    end;
  finally
    Moved.Free;
  end;
  CommitChange(True);
  AfterEdit;
end;

{ ===========================================================================
  TSchematicView.SendToBack  (procedure)
  Parameters:  none
  Notes:
    Moves the selected objects to the start of the drawing, so they are drawn underneath,
    keeping their order among themselves (CTinyCadDoc::SendToBack). One undo step.
  =========================================================================== }
procedure TSchematicView.SendToBack;
var
  i: Integer;
  Moved: TList;
begin
  if (Sheet = nil) or (FSelected.Count = 0) then
    Exit;
  BeginChange(rsSendToBack);
  Moved := TList.Create;
  try
    Sheet.Drawing.OwnsObjects := False;
    try
      for i := Sheet.Drawing.Count - 1 downto 0 do
        if FSelected.IndexOf(Sheet.Drawing[i]) >= 0 then
        begin
          Moved.Insert(0, Sheet.Drawing[i]);
          Sheet.Drawing.Delete(i);
        end;
      for i := Moved.Count - 1 downto 0 do Sheet.Drawing.Insert(0, TDrawingObject(Moved[i]));
    finally
      Sheet.Drawing.OwnsObjects := True;
    end;
  finally
    Moved.Free;
  end;
  CommitChange(True);
  AfterEdit;
end;

{ ===========================================================================
  TSchematicView.SelectedPolygon  (function)
  Parameters:  none
  Returns:
    TDrawPolygon - the polygon, or nil
  Notes:
    The selected polygon, when exactly one object is selected and it is a polygon.
  =========================================================================== }
function TSchematicView.SelectedPolygon: TDrawPolygon;
begin
  Result := nil;
  if (FSelected.Count = 1) and (TObject(FSelected[0]) is TDrawPolygon) then
    Result := TDrawPolygon(FSelected[0]);
end;

{ ===========================================================================
  TSchematicView.PolygonTolerance  (function)
  Parameters:  none
  Returns:
    Double - the distance in design units
  Notes:
    How close to a handle a click has to be to pick it: 2 design units, but never less than 4
    pixels, so a handle can still be picked when the sheet is zoomed out.
  =========================================================================== }
function TSchematicView.PolygonTolerance: Double;
begin
  { a handle is 2 design units either side of its point, but never smaller than 4 pixels, so it can be picked when zoomed out }
  Result := Max(2.0, 4.0 / FZoom);
end;

{ ===========================================================================
  TSchematicView.PolygonAction  (function)
  Parameters:
    PolyAct: TPolyAction - what to do
    const P: TDPoint - the point that was clicked
  Returns:
    Boolean - True if the polygon changed
  Notes:
    Does one of the polygon menu's actions (Add handle, Delete handle, Free line, Arc in, Arc
    out, Curve) on the selected polygon, at the clicked point, as one undo step. Nothing is
    recorded if it changed nothing.
  =========================================================================== }
function TSchematicView.PolygonAction(PolyAct: TPolyAction; const P: TDPoint): Boolean;
var
  Pg: TDrawPolygon;
begin
  Result := False;
  Pg := SelectedPolygon;
  if Pg = nil then
    Exit;
  case PolyAct of
    paFreeLine: BeginChange(rsFreeLine);
    paArcIn: BeginChange(rsArcIn);
    paArcOut: BeginChange(rsArcOut);
    paCurve: BeginChange(rsCurve);
    paAddHandle: BeginChange(rsAddHandle);
    paDeleteHandle: BeginChange(rsDeleteHandle);
  end;
  Result := Pg.ApplyAction(PolyAct, P, SnapPoint(P));
  CommitChange(Result);
end;

{ ===========================================================================
  TSchematicView.SetDrawArcType  (procedure)
  Parameters:
    Arc: Integer - Arc_none, Arc_in or Arc_out
  Notes:
    Chooses the kind of segment (straight, arc in, arc out) given to the points of a polygon
    that is drawn from now on.
  =========================================================================== }
procedure TSchematicView.SetDrawArcType(Arc: Integer);
begin
  FPolyArc := Arc;
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.ShowDrawMenu  (procedure)
  Parameters:
    X: Integer - mouse x in the view
    Y: Integer - mouse y in the view
  Notes:
    Opens the menu for a polygon that is being drawn: Finish polygon, Cancel drawing, and the
    kind of segment for the points still to come (Free line, Arc in, Arc out, the current one
    marked). The items are in the form file (the owner gives the menu to DrawPopup); here only
    the mark of the current kind is set.
  =========================================================================== }
procedure TSchematicView.PrepareDrawPopup;
var
  i: Integer;
begin
  if FDrawPopup = nil then
    Exit;
  for i := 0 to FDrawPopup.Items.Count - 1 do
    if FDrawPopup.Items[i].RadioItem then
      FDrawPopup.Items[i].Checked := (FPolyArc = FDrawPopup.Items[i].Tag - 10);
end;

procedure TSchematicView.ShowDrawMenu(X, Y: Integer);
var
  Scr: TPoint;
begin
  if FDrawPopup = nil then
    Exit;
  PrepareDrawPopup;
  Scr := ClientToScreen(Point(X, Y));
  FDrawPopup.PopUp(Scr.x, Scr.y);
end;

{ ===========================================================================
  TSchematicView.DrawMenuClick  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Handler for the items of the drawing menu: finish the polygon, cancel it, or choose the kind
    of segment.
  =========================================================================== }
procedure TSchematicView.DrawMenuClick(Sender: TObject);
var
  T: Integer;
begin
  T := (Sender as TMenuItem).Tag;
  case T of
    1: if Length(FPoly) >= 2 then
         FinishPolygon(False);
    2: begin
      FStage := 0;
      SetLength(FPoly, 0);
      SetLength(FPolyArcs, 0);
      Invalidate;
    end;
  else
    SetDrawArcType(T - 10);
  end;
end;

{ ===========================================================================
  TSchematicView.ContextSelectAt  (procedure)
  Parameters:
    const P: TDPoint - a point, in design units
  Notes:
    The object under the point becomes the chosen one when it is not chosen already, so that the
    commands of the menu act on what was clicked. An object that is already chosen keeps the
    choice (and so do the others chosen with it); a click on nothing leaves the choice as it is.
    A polygon is found by its handles as well as its sides.
  =========================================================================== }
procedure TSchematicView.ContextSelectAt(const P: TDPoint);
var
  Obj: TDrawingObject;
begin
  if PolygonAt(P) then
    Exit;
  Obj := HitTest(P);
  if (Obj <> nil) and (FSelected.IndexOf(Obj) < 0) then
    SelectObject(Obj, False);
end;

{ ===========================================================================
  TSchematicView.PolygonAt  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Boolean
  Notes:
    "Close" is as for picking a handle (twice the polygon tolerance for a side): the polygon
    commands of the menu then apply to the nearest side.
  =========================================================================== }
function TSchematicView.PolygonAt(const P: TDPoint): Boolean;
var
  Pg: TDrawPolygon;
begin
  Pg := SelectedPolygon;
  Result := (Pg <> nil) and ((Pg.HandleAt(P, PolygonTolerance) >= 0) or (Pg.DistanceFromPoint(P) <= PolygonTolerance * 2));
end;

{ ===========================================================================
  TSchematicView.SelectedSymbol  (function)
  Parameters:  none
  Returns:
    TDrawMethod
  Notes:
    What "Replace Symbol..." works on.
  =========================================================================== }
function TSchematicView.SelectedSymbol: TDrawMethod;
begin
  Result := nil;
  if (FSelected.Count = 1) and (TObject(FSelected[0]) is TDrawMethod) then
    Result := TDrawMethod(FSelected[0]);
end;

{ ===========================================================================
  TSchematicView.SymbolRung  (function)
  Parameters:
    out Info: TRungInfo - the rung and how it was found
  Returns:
    Boolean - True when one symbol is chosen and it is inside the sheet's rung grid
  Notes:
    See RungOfObject in ULinks for the rule.
  =========================================================================== }
function TSchematicView.SymbolRung(out Info: TRungInfo): Boolean;
var
  S: TDrawMethod;
begin
  S := SelectedSymbol;
  Result := (S <> nil) and (Sheet <> nil) and RungOfObject(Sheet, S, Info);
end;

{ ===========================================================================
  TSchematicView.SetSymbolRung  (function)
  Parameters:
    Number: Integer - the rung number to keep on the symbol, or 0 to let it follow its position again
  Returns:
    Boolean - True when something changed
  Notes:
    Stores the choice on the chosen symbol (TDrawMethod.RungOverride) as one undo step; the ladder references that show its line are updated. Notes: a chosen rung stays when the
    symbol is moved, so choose Automatic to follow the position again.
  =========================================================================== }
function TSchematicView.SetSymbolRung(Number: Integer): Boolean;
var
  S: TDrawMethod;
begin
  S := SelectedSymbol;
  Result := (S <> nil) and (S.RungOverride <> Number);
  if not Result then
    Exit;
  BeginChange(rsSetRung);
  S.RungOverride := Number;
  CommitChange(True);
end;

{ ===========================================================================
  TSchematicView.AddRungReference  (function)
  Parameters:  none
  Returns:
    String - added, exists, nosel or noref
  Notes:
    Right click a symbol > Add Rung Reference: puts a cross reference text (TDrawRefText, mode 2) under the chosen symbol. On a coil it reads like "5 NO  7 NC" (the rung and form of each contact
    with the same reference), on a contact it gives the rung of the coil. It follows the symbols as they are moved or renumbered. One undo step. A symbol that already has one under mode 2
    gets no second: that one is chosen instead. Notes: the text is put 2 mm below the symbol's box, left aligned with it, on the grid.
  =========================================================================== }
function TSchematicView.AddRungReference: String;
var
  S: TDrawMethod;
  X: TDrawRefText;
  i: Integer;
  P: TDPoint;
begin
  S := SelectedSymbol;
  if (S = nil) or (Sheet = nil) then
  begin
    Result := 'nosel';
    Exit;
  end;
  if S.GetRef = '' then
  begin
    Result := 'noref';
    Exit;
  end;
  for i := 0 to Sheet.Drawing.Count - 1 do
    if (Sheet.Drawing[i] is TDrawRefText) and ((Sheet.Drawing[i] as TDrawRefText).Mode = 2) and ((Sheet.Drawing[i] as TDrawRefText).TargetId = S.Id) then
    begin
      FSelected.Clear;
      FSelected.Add(Sheet.Drawing[i]);
      SelectionChanged;
      Invalidate;
      Result := 'exists';
      Exit;
    end;
  BeginChange(rsAddRungReference);
  X := TDrawRefText.Create(Sheet.Options);
  X.TargetId := S.Id;
  X.Mode := 2;
  P := DPoint(Min(S.PointA.x, S.PointB.x), Max(S.PointA.y, S.PointB.y) + 2 * UNITS_PER_MM);
  X.PointA := P;
  AddNew(X);
  UpdateLinks(Design);                    // (the text is known now: put its baseline one text height below the start)
  X.PointA := SnapPoint(DPoint(P.x, P.y + (X.PointA.y - X.PointB.y)));
  X.UpdateLayout;
  FSelected.Clear;
  FSelected.Add(X);
  CommitChange(True);
  SelectionChanged;
  Result := 'added';
end;

{ ===========================================================================
  TSchematicView.SelectedLine  (function)
  Parameters:  none
  Returns:
    TDrawLine
  Notes:
    What "Make horizontal" and "Make vertical" work on (TinyCAD's line context menu,
    IDR_LINETOOL_EDIT).
  =========================================================================== }
function TSchematicView.SelectedLine: TDrawLine;
begin
  Result := nil;
  if (FSelected.Count = 1) and (TObject(FSelected[0]) is TDrawLine) then
    Result := TDrawLine(FSelected[0]);
end;

{ ===========================================================================
  TSchematicView.LineMakeStraight  (function)
  Parameters:
    Vertical: Boolean - flag
    const P: TDPoint - a point, in design units
  Returns:
    Boolean
  Notes:
    CDrawLine::ContextMenu. The end of the line nearer to P stays where it is and the other end
    moves across to line up with it (same x for vertical, same y for horizontal), as one undo
    step. Nothing is recorded when the line is already straight that way or has no length.
    Differences from TinyCAD: none known; the nearer end is told by where the projection of P on
    the line falls (under half way is the first end).
  =========================================================================== }
function TSchematicView.LineMakeStraight(Vertical: Boolean; const P: TDPoint): Boolean;
var
  L: TDrawLine;
  DX, DY, Len2, T: Double;
begin
  Result := False;
  L := SelectedLine;
  if L = nil then
    Exit;
  if Vertical then
    Result := L.PointA.X <> L.PointB.X
  else
    Result := L.PointA.Y <> L.PointB.Y;
  if not Result then
    Exit;
  DX := L.PointB.X - L.PointA.X;
  DY := L.PointB.Y - L.PointA.Y;
  Len2 := DX * DX + DY * DY;
  T := 0;
  if Len2 > 0 then
    T := ((P.X - L.PointA.X) * DX + (P.Y - L.PointA.Y) * DY) / Len2;
  if Vertical then
    BeginChange(rsMakeVertical)
  else
    BeginChange(rsMakeHorizontal);
  if T < 0.5 then
  begin
    if Vertical then
      L.PointB.X := L.PointA.X
    else
      L.PointB.Y := L.PointA.Y;
  end
  else
  begin
    if Vertical then
      L.PointA.X := L.PointB.X
    else
      L.PointA.Y := L.PointB.Y;
  end;
  CommitChange(True);
end;

{ ===========================================================================
  TSchematicView.PressKey  (procedure)
  Parameters:
    Key: Word - the virtual key
    Shift: TShiftState - the shift keys held
  Notes:
    A key pressed on the sheet, through the real handler (for the self-test script).
  =========================================================================== }
procedure TSchematicView.PressKey(Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

{ ===========================================================================
  TSchematicView.NudgeSelection  (function)
  Parameters:
    DX: Integer - -1 for left, 1 for right, 0 for no horizontal move
    DY: Integer - -1 for up, 1 for down, 0 for no vertical move
  Returns:
    Boolean - True if the selection was moved
  Notes:
    An arrow key with the select tool: the chosen objects move one grid step when snap to grid
    is on, one screen pixel (1 / zoom design units) when it is off, as one undo step. It moves
    like a drag does - the wires attached to the objects follow, and junctions are checked
    afterwards. Differences from TinyCAD: this command is new.
  =========================================================================== }
function TSchematicView.NudgeSelection(DX, DY: Integer): Boolean;
var
  Step: Double;
  Delta: TDPoint;
  Box: TDRect;
  First: Boolean;
  i: Integer;
begin
  Result := False;
  if (Sheet = nil) or (FTool <> vtSelect) or (FSelected.Count = 0) or (FZoom <= 0) or (FDragMode <> 0) or FPasting then
    Exit;
  if SnapEnabled and (Sheet.Snap.Grid > 0) then
    Step := Sheet.Snap.Grid
  else
    Step := 1 / FZoom;
  Delta := DPoint(DX * Step, DY * Step);
  BeginChange(rsMove);
  StartDragEngine;
  { a chosen wire moves whole (both its ends count as inside the area), the wires attached to it or to other chosen objects stretch }
  First := True;
  for i := 0 to FSelected.Count - 1 do
    if TDrawingObject(FSelected[i]).GetType in [xWire, xBus] then
      with TDrawingObject(FSelected[i]) do
      begin
        if First then
          Box := DRect(Min(PointA.x, PointB.x), Min(PointA.y, PointB.y), Max(PointA.x, PointB.x), Max(PointA.y, PointB.y))
        else
          Box := DRect(Min(Box.Left, Min(PointA.x, PointB.x)), Min(Box.Top, Min(PointA.y, PointB.y)), Max(Box.Right, Max(PointA.x, PointB.x)), Max(Box.Bottom, Max(PointA.y, PointB.y)));
        First := False;
      end;
  if not First then
    FDragEng.BeginDrag(DPoint(Box.Left, Box.Top), DPoint(Box.Right, Box.Bottom));
  FDragEng.DragBy(Delta);
  FDragEng.FinishDrag;
  FreeAndNil(FDragEng);
  PruneSelection;
  FAreaA := DPoint(FAreaA.x + Delta.x, FAreaA.y + Delta.y);
  FAreaB := DPoint(FAreaB.x + Delta.x, FAreaB.y + Delta.y);
  CommitChange(True);
  Sheet.UpdateLayout;
  UpdateLinks(FDesign);
  Invalidate;
  Result := True;
end;

{ ===========================================================================
  TSchematicView.ArrowKey  (function)
  Parameters:
    var Key: Word - the key; set to 0 when it moved the selection
    Shift: TShiftState - the shift keys held
  Returns:
    Boolean - True if the key moved the selection
  Notes:
    An arrow key on the sheet, alone or with Shift: NudgeSelection in that direction. Ctrl and Alt
    with an arrow are left to whoever uses them.
  =========================================================================== }
function TSchematicView.ArrowKey(var Key: Word; Shift: TShiftState): Boolean;
begin
  Result := False;
  if not (Key in [VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN]) then
    Exit;
  if (Shift - [ssShift]) <> [] then
    Exit;
  Result := NudgeSelection(Ord(Key = VK_RIGHT) - Ord(Key = VK_LEFT), Ord(Key = VK_DOWN) - Ord(Key = VK_UP));
  if Result then
    Key := 0;
end;

{ ===========================================================================
  WireCutPoint  (function)
  Parameters:
    L: TDrawLine - the wire
    const P: TDPoint - a point, in design units
    out Q: TDPoint - where the wire would be cut
  Returns:
    Boolean - True if there is a place to cut
  Notes:
    The cut goes on the grid point nearest P when that lies on the wire, otherwise at the point
    of the wire nearest P. A place at (or next to) either end is no place: a wire has to keep
    some length on both sides.
  =========================================================================== }
function WireCutPoint(L: TDrawLine; const SnapQ, P: TDPoint; out Q: TDPoint): Boolean;
var
  Near: TDPoint;
begin
  Q := SnapQ;
  if LineDistance(L.PointA, L.PointB, Q, Near) > 0.01 then
  begin
    LineDistance(L.PointA, L.PointB, P, Near);
    Q := Near;
  end;
  Result := (Hypot(Q.x - L.PointA.x, Q.y - L.PointA.y) > 0.01) and (Hypot(Q.x - L.PointB.x, Q.y - L.PointB.y) > 0.01);
end;

{ ===========================================================================
  TSchematicView.WireCanCut  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Boolean - True if "Add wire cut here" can be offered
  Notes:
    The one chosen object is a wire and P is a place it can be cut at (WireCutPoint).
  =========================================================================== }
function TSchematicView.WireCanCut(const P: TDPoint): Boolean;
var
  L: TDrawLine;
  Q: TDPoint;
begin
  L := SelectedLine;
  Result := (L <> nil) and (L.GetType = xWire) and WireCutPoint(L, SnapPoint(P), P, Q);
end;

{ ===========================================================================
  TSchematicView.WireCutAt  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Boolean - True if the wire was cut
  Notes:
    Add wire cut here: the chosen wire becomes two wires that meet at the cut point (the first
    keeps the first end, the new one gets the rest and the same style and width), as one undo
    step. Junction dots are not asked for: two wires that only meet end to end need none.
    Differences from TinyCAD: this command is new.
  =========================================================================== }
function TSchematicView.WireCutAt(const P: TDPoint): Boolean;
var
  L, NewLine: TDrawLine;
  Q: TDPoint;
begin
  Result := False;
  L := SelectedLine;
  if (L = nil) or (L.GetType <> xWire) or (not WireCutPoint(L, SnapPoint(P), P, Q)) then
    Exit;
  BeginChange(rsAddWireCut);
  NewLine := L.Clone as TDrawLine;
  NewLine.Id := FDesign.NextObjectId;
  NewLine.PointA := Q;
  NewLine.PointB := L.PointB;
  L.PointB := Q;
  Sheet.Drawing.Add(NewLine);
  CommitChange(True);
  Result := True;
end;

{ ===========================================================================
  TSchematicView.SetArcToolType  (procedure)
  Parameters:
    AValue: Integer - the value
  Notes:
    Chooses the kind of arc the Arc tool draws next (from its menu, its panel, or by turning
    after each arc) and tells the panel.
  =========================================================================== }
procedure TSchematicView.SetArcToolType(AValue: Integer);
begin
  if not (AValue in [Arc_in, Arc_out]) then
    Exit;
  FArcToolType := AValue;
  if Assigned(FOnArcTypeChanged) then
    FOnArcTypeChanged(Self);
end;

{ ===========================================================================
  TSchematicView.ShowArcMenu  (procedure)
  Parameters:
    X: Integer - horizontal position or value
    Y: Integer - vertical position or value
  Notes:
    The right click menu of the Arc tool: Arc in or Arc out (the kind of arc drawn, the current
    one marked) and Cancel drawing. An arc that is being drawn is not cut short by the menu.
    The items are in the form file (the owner gives the menu to ArcPopup); here only the mark
    of the current kind and the visibility of Finish arc (two points or more) are set.
  =========================================================================== }
procedure TSchematicView.PrepareArcPopup;
var
  i: Integer;
begin
  if FArcPopup = nil then
    Exit;
  for i := 0 to FArcPopup.Items.Count - 1 do
    if FArcPopup.Items[i].RadioItem then
      FArcPopup.Items[i].Checked := (FArcToolType = FArcPopup.Items[i].Tag - 10)
    else if FArcPopup.Items[i].Tag = 3 then
      FArcPopup.Items[i].Visible := Length(FPoly) >= 2;      // Finish arc: only with two points or more
end;

procedure TSchematicView.ShowArcMenu(X, Y: Integer);
var
  Scr: TPoint;
begin
  if FArcPopup = nil then
    Exit;
  PrepareArcPopup;
  Scr := ClientToScreen(Point(X, Y));
  FArcPopup.PopUp(Scr.x, Scr.y);
end;

{ ===========================================================================
  TSchematicView.ArcMenuClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler for the Arc tool's menu: sets the kind of arc, or drops the arc being drawn and the
    tool.
  =========================================================================== }
procedure TSchematicView.ArcMenuClick(Sender: TObject);
var
  T: Integer;
begin
  T := (Sender as TMenuItem).Tag;
  if T = 1 then
    CancelTool
  else if T = 3 then
    FinishPolygon(False)
  else
    ArcToolType := T - 10;
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.ShowObject  (procedure)
  Parameters:
    Obj: TDrawingObject - an object of the sheet being shown
  Notes:
    Makes sure an object can be seen, as Find does for what it has found: if any part of it is
    off screen the sheet is scrolled so that it is in the middle; the zoom is not changed.
  =========================================================================== }
procedure TSchematicView.ShowObject(Obj: TDrawingObject);
var
  L, T, R, B, VW, VH: Double;
begin
  if (Obj = nil) or (ClientWidth <= 0) or (ClientHeight <= 0) or (FZoom <= 0) or (not HasCorners(Obj)) then
    Exit;
  L := Min(Obj.PointA.x, Obj.PointB.x); R := Max(Obj.PointA.x, Obj.PointB.x);
  T := Min(Obj.PointA.y, Obj.PointB.y); B := Max(Obj.PointA.y, Obj.PointB.y);
  VW := ClientWidth / FZoom;
  VH := ClientHeight / FZoom;
  if (L < FOrigin.x) or (R > FOrigin.x + VW) or (T < FOrigin.y) or (B > FOrigin.y + VH) then
  begin
    FOrigin := DPoint((L + R) / 2 - VW / 2, (T + B) / 2 - VH / 2);
    FAutoFit := False;
  end;
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.MarkerAt  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Integer
  Notes:
    As TinyCAD's CDrawError::IsInside, a circle is picked by a click within 6 units of its
    centre (never less than 4 pixels).
  =========================================================================== }
function TSchematicView.MarkerAt(const P: TDPoint): Integer;
var
  i: Integer;
  Reach, D, Best: Double;
begin
  Result := -1;
  Best := 1e30;
  Reach := Max(6.0, 4.0 / FZoom);
  for i := 0 to High(FMarkers) do
    if FMarkers[i].Sheet = FSheetIndex then
    begin
      if (Abs(P.x - FMarkers[i].Point.x) <= Reach) and (Abs(P.y - FMarkers[i].Point.y) <= Reach) then
      begin
        D := Sqr(P.x - FMarkers[i].Point.x) + Sqr(P.y - FMarkers[i].Point.y);
        if D < Best then begin
          Best := D;
          Result := i;
        end;
      end;
    end;
end;

{ ===========================================================================
  TSchematicView.SetMarkers  (procedure)
  Parameters:
    const AMarkers: array of TFindMarker - the circles
  Notes:
    Gives the view the red circles of what Find found (each with its sheet and its place). The
    circles belong to the view and not to the design, so they are never saved, undone, copied or
    netlisted. No circle is chosen.
  =========================================================================== }
procedure TSchematicView.SetMarkers(const AMarkers: array of TFindMarker);
var
  i: Integer;
begin
  SetLength(FMarkers, Length(AMarkers));
  for i := 0 to High(AMarkers) do FMarkers[i] := AMarkers[i];
  FMarkerSel := -1;
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.ClearMarkers  (procedure)
  Parameters:  none
  Notes:
    Takes all the red circles away.
  =========================================================================== }
procedure TSchematicView.ClearMarkers;
begin
  SetLength(FMarkers, 0);
  FMarkerSel := -1;
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.SelectMarker  (procedure)
  Parameters:
    Index: Integer - its number in the list given to SetMarkers
  Notes:
    Chooses one of the circles, which is then drawn bright red (-1 chooses none).
  =========================================================================== }
procedure TSchematicView.SelectMarker(Index: Integer);
begin
  if (Index < -1) or (Index > High(FMarkers)) then
    Exit;
  FMarkerSel := Index;
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.MarkerCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    How many red circles the view has.
  =========================================================================== }
function TSchematicView.MarkerCount: Integer;
begin
  Result := Length(FMarkers);
end;

{ ===========================================================================
  TSchematicView.CenterOnPoint  (procedure)
  Parameters:
    const P: TDPoint - a point of the sheet being shown
  Notes:
    Scrolls the sheet so that a point is in the middle of the window, as TinyCAD does for what
    the list of found items is showing. The zoom stays as the user has it.
  =========================================================================== }
procedure TSchematicView.CenterOnPoint(const P: TDPoint);
begin
  if (ClientWidth <= 0) or (ClientHeight <= 0) or (FZoom <= 0) then
    Exit;
  FOrigin := DPoint(P.x - ClientWidth / FZoom / 2, P.y - ClientHeight / FZoom / 2);
  FAutoFit := False;
  Invalidate;
end;

{ ===========================================================================
  TSchematicView.SelectedResizable  (function)
  Parameters:  none
  Returns:
    TDrawingObject
  Notes:
    TinyCAD shows handles only when a single object is selected (IsSingleItemSelected). They are
    not offered while a block is being placed or when a drawing tool is in use.
  =========================================================================== }
function TSchematicView.SelectedResizable: TDrawingObject;
begin
  Result := nil;
  if (Sheet = nil) or FPasting or (FTool <> vtSelect) or (FSelected.Count <> 1) then
    Exit;
  if TDrawingObject(FSelected[0]).CanResize then
    Result := TDrawingObject(FSelected[0]);
end;

{ ===========================================================================
  TSchematicView.ResizeHandleSize  (function)
  Parameters:  none
  Returns:
    Double
  Notes:
    A handle is 6 pixels on the screen whatever the zoom, so it is 6 / zoom design units.
  =========================================================================== }
function TSchematicView.ResizeHandleSize: Double;
begin
  Result := 6 / Max(FZoom, 0.01);
end;

{ ===========================================================================
  TSchematicView.WireWhollyPicked  (function)
  Parameters:
    L: TDrawLine - a wire
  Returns:
    Boolean - True if both ends are inside the picking area
  Notes:
    A wire picked with a click, or only touched by a selection box, is not wholly picked; one
    with both ends inside the box is. The area travels with the selection when it is moved.
  =========================================================================== }
function TSchematicView.WireWhollyPicked(L: TDrawLine): Boolean;
var
  X0, X1, Y0, Y1: Double;
begin
  X0 := Min(FAreaA.x, FAreaB.x); X1 := Max(FAreaA.x, FAreaB.x);
  Y0 := Min(FAreaA.y, FAreaB.y); Y1 := Max(FAreaA.y, FAreaB.y);
  Result := (L.PointA.x >= X0) and (L.PointA.x <= X1) and (L.PointA.y >= Y0) and (L.PointA.y <= Y1) and
            (L.PointB.x >= X0) and (L.PointB.x <= X1) and (L.PointB.y >= Y0) and (L.PointB.y <= Y1);
end;

{ ===========================================================================
  TSchematicView.WholeWireEndAt  (function)
  Parameters:
    const P: TDPoint - a point of the sheet
  Returns:
    Boolean - True if P is on an end handle of a chosen, wholly picked wire
  Notes:
    Used so that such a handle takes the press before the objects beneath it (a junction dot).
  =========================================================================== }
function TSchematicView.WholeWireEndAt(const P: TDPoint): Boolean;
var
  i: Integer;
  L: TDrawLine;
  Tol: Double;
begin
  Result := False;
  Tol := ResizeHandleSize / 2 + 1;
  for i := 0 to FSelected.Count - 1 do
    if TObject(FSelected[i]) is TDrawLine then
    begin
      L := TDrawLine(FSelected[i]);
      if WireWhollyPicked(L) and
         (((Abs(L.PointA.x - P.x) <= Tol) and (Abs(L.PointA.y - P.y) <= Tol)) or
          ((Abs(L.PointB.x - P.x) <= Tol) and (Abs(L.PointB.y - P.y) <= Tol))) then
        Exit(True);
    end;
end;

{ ===========================================================================
  TSchematicView.WireEndAt  (function)
  Parameters:
    const P: TDPoint - a point of the sheet
    out End1: Boolean - True for the first end, False for the second
  Returns:
    TDrawLine - the wire, or nil
  Notes:
    Finds the chosen wire whose end handle is under P, provided the wire was not wholly picked
    (see WireWhollyPicked). Dragging such a handle stretches that wire from that end; for a
    wholly picked wire the handle is just part of the wire and the selection moves.
  =========================================================================== }
function TSchematicView.WireEndAt(const P: TDPoint; out End1: Boolean): TDrawLine;
var
  i: Integer;
  L: TDrawLine;
  Tol: Double;
begin
  Result := nil;
  End1 := True;
  Tol := ResizeHandleSize / 2 + 1;
  for i := 0 to FSelected.Count - 1 do
    if TObject(FSelected[i]) is TDrawLine then
    begin
      L := TDrawLine(FSelected[i]);
      if WireWhollyPicked(L) then
        Continue;
      if (Abs(L.PointA.x - P.x) <= Tol) and (Abs(L.PointA.y - P.y) <= Tol) then
      begin
        End1 := True;
        Exit(L);
      end;
      if (Abs(L.PointB.x - P.x) <= Tol) and (Abs(L.PointB.y - P.y) <= Tol) then
      begin
        End1 := False;
        Exit(L);
      end;
    end;
end;

{ ===========================================================================
  TSchematicView.CursorForHandle  (function)
  Parameters:
    AHandle: Integer - whole number
  Returns:
    TCursor
  Notes:
    As TinyCAD's table of pointers: the diagonal arrows for the corners, up-down for the top and
    bottom, left-right for the sides; the ordinary pointer when the point is on no handle.
  =========================================================================== }
function TSchematicView.CursorForHandle(AHandle: Integer): TCursor;
begin
  case AHandle of
    HANDLE_TOPLEFT, HANDLE_BOTTOMRIGHT: Result := crSizeNWSE;
    HANDLE_TOPRIGHT, HANDLE_BOTTOMLEFT: Result := crSizeNESW;
    HANDLE_TOP, HANDLE_BOTTOM: Result := crSizeNS;
    HANDLE_RIGHT, HANDLE_LEFT: Result := crSizeWE;
  else
    Result := crDefault;
  end;
end;

{ ===========================================================================
  TSchematicView.ProbeSnap  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    TDPoint
  Notes:
    The pointer is at a whole pixel of the window, which is not exactly the point asked for, so
    this follows the same path: to a window position and back, then snapped. For tests, which
    need to know what a drag really started from.
  =========================================================================== }
function TSchematicView.ProbeSnap(const P: TDPoint): TDPoint;
begin
  ApplyTransform;
  Result := SnapPoint(ScreenToDesign(DesignToScreen(P)));
end;

initialization
  FillChar(WireAngles, SizeOf(WireAngles), 0);      // free
  WireAngles[vtWire] := am90;

end.
