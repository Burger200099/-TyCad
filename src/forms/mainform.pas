// SPDX-License-Identifier: LGPL-2.1-or-later
{ The main window: main menu, a top-aligned page control that is the ribbon, the symbol library
  panel, the drawing area, sheet tabs and a status bar. Built entirely in code.

  The ribbon tabs hold plain buttons (Home, Draw, Ladder, Library, View) and a Properties tab whose
  editors are made from whatever is selected: one object shows its properties; several objects show
  the properties they share and a change applies to all of them (the mass change). Nothing pops up.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls, ExtCtrls, StdCtrls, Buttons,
  LCLType, LCLProc, TypInfo, Math, Spin, UDPoint, UDrawTypes, UGeometry, UResources, UDrawingObjects, USymbols, UDesign, UDsnBinary, ULibrary, ULibXML, UPaper,
  UProps, UUndo, UView, UDialogs, consts, Fnewdoc, Fabout, QLibPanel, QFindPanel, UDocs, USettings, UOptions, Foptions, {Fcolors,}
  UFind, Fdetails, Fpagesetup, Fpartslist, UPartsList, USymbolBom, UWireExport, UContacts, ULinks, Fnetlist, UNetWriters,
  USpiceVhdl, UErc, UPartCheck, Fercopts, Fercwin, UAnnotate, Fannotate, Types, Finput,
  Fbase, Fsymbolinfo, QPropFrame, QPropFrameList, StrUtils, Printers, PrintersDlgs, UPrint,
  UPrintRun, Fprint, Fpreview, UExport, Fexport, Flibraries, ULibManager,
  USymEdit, Fsymprops, Fsymparts, FPropTester, QPropBase, FFillDropDown,
  FDropDownBase, FBusDropDown, osver, UDocTabs, URibbon, UViewRulers,
  CSplitButton, FDetailsDropDown, UPartsDb, UPartData, Fproductpick, qsymbols, FSymDDD, QPartsEditor;

const
  PROPS_TAB = 'View';          // the ribbon page that holds the Properties panel of the selection (there is no Properties page)
  CHOOSE_ACTION: array[TAnnotateAction] of String = ('add', 'remove');
  CHOOSE_WHICH: array[TAnnotateWhich] of String = ('all', 'unnum', 'match');
  CHOOSE_VALUE: array[TAnnotateStart] of String = ('default', 'start');

type
  { which setting of the sheet's details panel on the ribbon is being applied }
  { Where a symbol drawn in the symbol editor goes when it is stored: into a part of a parts file (not into a symbol library). The editor document owns it. }
  TPartSymbolSink = class
  public
    FileName: String;
    PartID: Int64;
    Standard, Purpose, SymName: String;
    function SaveBlob(const Blob: String; Ed: TSymbolEditor): Int64;
  end;

  TSheetDetail = (sdRulers, sdCols, sdRows, sdBorder, sdMargin, sdExtended);

  TPropEditor = record
    Def: TPropDef;
    Control: TControl;
    Mixed: Boolean;
    Shown: Double;       // for a number box: the value it was last given, so an edit that changed nothing is not applied (and rounded)
    ShownText: String;   // for a box holding text or a number as text (a font name, a size): the text it was last given
    Mode: TBindMode;     // how the control edits its choice or yes/no (bmNormal for every control BuildEditors makes)
    OldClick: TNotifyEvent;   // the frame's own OnClick of a button, which is still called
  end;

  TControlCracker = class(TControl);      // (Click is protected)
  PPropEditor = ^TPropEditor;
  TPropEditorArray = array of TPropEditor;

  { TfrmMain }

  TfrmMain = class(TForm)
    edFilter: TEdit;
    frameLibraryPanel: TfrLibraryPanel;
    Label1: TLabel;
    lbCaption: TLabel;
    lbPropsProperties: TLabel;
    lbDrawMeasure: TLabel;
    lbDrawLadder: TLabel;
    lbDrawWires: TLabel;
    lbSheetDetails: TLabel;
    lbSheetSheets: TLabel;
    lbViewGrid: TLabel;
    lbViewView: TLabel;
    lbSheetDoc: TLabel;
    lbHomeFile: TLabel;
    lbHomeSelection: TLabel;
    lbHomeEdit: TLabel;
    mEdit: TMenuItem;
    mDelete: TMenuItem;
    mAddSheet: TMenuItem;
    MenuItem1: TMenuItem;
    miExtendedInfo: TMenuItem;
    miShowRulers: TMenuItem;
    Separator14: TMenuItem;
    miGridSize: TMenuItem;
    pmSheetAddHandle: TMenuItem;
    pmSheetDelHandle: TMenuItem;
    pmSheetPolySep1: TMenuItem;
    pmSheetFreeLine: TMenuItem;
    pmSheetArcIn: TMenuItem;
    pmSheetArcOut: TMenuItem;
    pmSheetCurve: TMenuItem;
    pmSheetPolySep2: TMenuItem;
    pmSheetWireCut: TMenuItem;
    pmSheetMakeHoriz: TMenuItem;
    pmSheetRung: TMenuItem;
    pmSheetRungRef: TMenuItem;
    pmSheetRungAuto: TMenuItem;
    pmSheetRungSep: TMenuItem;
    pmSheetMakeVert: TMenuItem;
    pmSheetLineSep: TMenuItem;
    pmSheetReloadHier: TMenuItem;
    pmSheetOpenHier: TMenuItem;
    pmSheetHierSep: TMenuItem;
    pmSheetReplaceSym: TMenuItem;
    pmSheetSymSep: TMenuItem;
    miGrid500: TMenuItem;
    miGrid1000: TMenuItem;
    miGrid1270: TMenuItem;
    miGrid2000: TMenuItem;
    miGrid2540: TMenuItem;
    miGrid5000: TMenuItem;
    miGrid10000: TMenuItem;
    miGridSep: TMenuItem;
    miGridCustom: TMenuItem;
    pmGrid500: TMenuItem;
    pmGrid1000: TMenuItem;
    pmGrid1270: TMenuItem;
    pmGrid2000: TMenuItem;
    pmGrid2540: TMenuItem;
    pmGrid5000: TMenuItem;
    pmGrid10000: TMenuItem;
    pmGridSep: TMenuItem;
    pmGridCustom: TMenuItem;
    pmGridSize: TPopupMenu;
    pmDocTabs: TPopupMenu;
    pmDocClose: TMenuItem;
    pmDocCloseAll: TMenuItem;
    pmPolyDraw: TPopupMenu;
    pmPolyFinish: TMenuItem;
    pmPolyCancel: TMenuItem;
    pmPolySep: TMenuItem;
    pmPolyFree: TMenuItem;
    pmPolyArcIn: TMenuItem;
    pmPolyArcOut: TMenuItem;
    pmArcDraw: TPopupMenu;
    pmArcFinish: TMenuItem;
    pmArcCancel: TMenuItem;
    pmArcSep: TMenuItem;
    pmArcIn: TMenuItem;
    pmArcOut: TMenuItem;
    miGridSnap: TMenuItem;
    Separator13: TMenuItem;
    miCloseAllDoc: TMenuItem;
    miAlign1pxgrid: TMenuItem;
    miAlignShowRulers: TMenuItem;
    Panel3: TPanel;
    pmAlignmentOptions: TPopupMenu;
    pmCloseDocMenu: TPopupMenu;
    rpSheetDetails: TPanel;
    rpSheetSheets: TPanel;
    sbSheetSheetsLeft: TSpeedButton;
    sbSheetSheetsRemove: TSpeedButton;
    sbSheetSheetsRename: TSpeedButton;
    sbSheetSheetsRight: TSpeedButton;
    Separator7: TMenuItem;
    miRotateL: TMenuItem;
    miRotateR: TMenuItem;
    miFlip: TMenuItem;
    miBringFront: TMenuItem;
    miSendBack: TMenuItem;
    miColors: TMenuItem;
    miReplaceSymbol: TMenuItem;
    miCloseDoc: TMenuItem;
    miCloseAllDocs: TMenuItem;
    miPrevDoc: TMenuItem;
    miNextDoc: TMenuItem;
    miDrawInsertPicture: TSpeedButton;
    miDrawPin: TSpeedButton;
    Separator12: TMenuItem;
    miZoomOut: TMenuItem;
    miZoomIn: TMenuItem;
    miObjProps: TMenuItem;
    miInsertPicture: TMenuItem;
    Separator11: TMenuItem;
    miCopyTo: TMenuItem;
    miFindPrev: TMenuItem;
    miFindNext: TMenuItem;
    miFindReplace: TMenuItem;
    miFind: TMenuItem;
    miSearch: TMenuItem;
    miFileImport: TMenuItem;
    miDrawContact: TMenuItem;
    miDrawRefLine: TMenuItem;
    plPropsProperties: TPanel;
    plSep13: TPanel;
    plSelect: TPanel;
    sbDrawSelect: TSpeedButton;
    Separator10: TMenuItem;
    miExportImage: TMenuItem;
    Separator2: TMenuItem;
    miShowPositionBar: TMenuItem;
    miShowViewRulers: TMenuItem;
    miLadderRails: TMenuItem;
    miLadderRungs: TMenuItem;
    miDrawRulerAB: TMenuItem;
    miDrawRulerH: TMenuItem;
    miDrawRulerV: TMenuItem;
    miDrawCloud: TMenuItem;
    miDrawNote: TMenuItem;
    miDrawArc: TMenuItem;
    miDrawCircle: TMenuItem;
    miDrawRect: TMenuItem;
    miDrawPolygon: TMenuItem;
    miDrawLine: TMenuItem;
    miDrawText: TMenuItem;
    miDrawSymbolText: TMenuItem;
    miSymNew, miSymEdit, miSymDelete, miSymDuplicate, miSymCommandProps, miSymPin, miSymOrigin, miSymStore, miSymProps, miSymParts, miSymPrevPart, miSymNextPart, miSymExport, miSymExportLib, miSymImport: TMenuItem;
    sepSymbol1, sepSymbol2, sepSymbol3: TMenuItem;
    miDrawBusSlash: TMenuItem;
    miDrawBus: TMenuItem;
    miDrawPower: TMenuItem;
    miDrawWireNoCon: TMenuItem;
    miDrawJunction: TMenuItem;
    miDrawLabel: TMenuItem;
    miDrawWire: TMenuItem;
    miMeasure: TMenuItem;
    miShapes: TMenuItem;
    miWires: TMenuItem;
    miMoveSheetRight: TMenuItem;
    miMoveSheetLeft: TMenuItem;
    Panel1: TPanel;
    plDrawLadder: TPanel;
    plSep12: TPanel;
    plSep11: TPanel;
    plDrawShapes: TPanel;
    plDrawMeasure: TPanel;
    plSep10: TPanel;
    rpDrawWires: TPanel;
    sbDrawLadderAdd: TSpeedButton;
    sbDrawLadderLink: TSpeedButton;
    sbDrawLadderContact: TSpeedButton;
    sbDrawLadderRungs: TSpeedButton;
    sbDrawShapesArc: TSpeedButton;
    sbDrawMeasureRulerV: TSpeedButton;
    sbDrawShapesNote: TSpeedButton;
    sbDrawShapesCloud: TSpeedButton;
    sbDrawMeasureRulerH: TSpeedButton;
    sbDrawShapesRect: TSpeedButton;
    sbDrawShapesPoly: TSpeedButton;
    sbDrawShapesCircle: TSpeedButton;
    sbDrawMeasureRulerAB: TSpeedButton;
    sbDrawWiresText: TSpeedButton;
    sbDrawWiresSymbolText: TSpeedButton;
    sbDrawWiresJunction: TSpeedButton;
    sbDrawWiresPower: TSpeedButton;
    sbDrawWiresNoConnect: TSpeedButton;
    sbDrawWiresBus: TSpeedButton;
    sbDrawWiresBusSlash: TSpeedButton;
    sbDrawShapesLine: TSpeedButton;
    sbDrawWiresWireLabel: TSpeedButton;
    sbHomeFilePrint: TSpeedButton;
    sbHomeFilePrintPreview: TSpeedButton;
    sbHomeFilePageSetup: TSpeedButton;
    sbHomeFilePrintSetup: TSpeedButton;
    sbDrawWiresWire: TSpeedButton;
    Separator9: TMenuItem;
    miRenameSheet: TMenuItem;
    miCloseAll: TMenuItem;
    miClose: TMenuItem;
    miDetails: TMenuItem;
    Separator8: TMenuItem;
    miSelect: TMenuItem;
    Separator6: TMenuItem;
    miDupe: TMenuItem;
    miPaste: TMenuItem;
    miCopy: TMenuItem;
    miCut: TMenuItem;
    mTheme: TMenuItem;
    mWindow: TMenuItem;
    mOpenLibs: TMenuItem;
    mLibraries: TMenuItem;
    sepLibraries: TMenuItem;
    mRedo: TMenuItem;
    mUndo: TMenuItem;
    mSepPrint: TMenuItem;
    mPrint: TMenuItem;
    mPrintPreview: TMenuItem;
    mPageSetup: TMenuItem;
    miPropTest: TMenuItem;
    mPrintSetup: TMenuItem;
    FRibbon: TPageControl;
    rpSep6: TPanel;
    rpSep7: TPanel;
    rpViewGrid: TPanel;
    rpViewPosition: TPanel;
    miAlignToGrid: TMenuItem;
    rpViewView: TPanel;
    rpSep4: TPanel;
    rpSheetDoc: TPanel;
    rpHomeSelection: TPanel;
    rpSep2: TPanel;
    rpHomeEdit: TPanel;
    rpSep1: TPanel;
    rpHomeFile: TPanel;
    pbRibbonDisplay: TPaintBox;
    pnlLeft: TPanel;
    pnlMain: TPanel;
    sbHomeDocFindReplace: TSpeedButton;
    sbHomeEditCut: TSpeedButton;
    sbHomeEditCopy: TSpeedButton;
    sbHomeEditDupe: TSpeedButton;
    sbHomeEditPaste: TSpeedButton;
    sbHomeFileNew1: TSpeedButton;
    sbHomeDocFind: TSpeedButton;
    sbHomeFileSave: TSpeedButton;
    sbViewGridSize: TSpeedButton;
    sbViewGridSizeUp: TSpeedButton;
    sbViewGridSnapTo: TSpeedButton;
    sbViewGridShow: TSpeedButton;
    pnlPosition: TPanel;
    lbZoomPct, lblPosition: TLabel;
    sbPosSnap: TSpeedButton;
    sbPosGridSize: TSpeedButton;
    edPosGrid: TEdit;
    lblPosUnits: TLabel;
    lbViewPosition: TLabel;
    mShowPosition: TMenuItem;
    mSaveAll: TMenuItem;
    mSpecial: TMenuItem;
    mPartsList: TMenuItem;
    mSymbolBom: TMenuItem;
    mSymbolData: TMenuItem;
    mExportWires: TMenuItem;
    pmRulerUnits: TPopupMenu;
    miRulerMM: TMenuItem;
    miRulerIN: TMenuItem;
    mInsertContactNO: TMenuItem;
    mInsertContactNC: TMenuItem;
    mInsertContactFree: TMenuItem;
    mDupRefs: TMenuItem;
    mNetList: TMenuItem;
    mCheckRules: TMenuItem;
    mVhdlCheck: TMenuItem;
    mAnnotate: TMenuItem;
    mSpecialSep1: TMenuItem;
    mSpice: TMenuItem;
    mSpecialSep2: TMenuItem;
    mVhdl: TMenuItem;
    mSpecialSep3, mSpecialSep4, mSheetSep3, mInsertDesign, mAddHierSymbol, mReloadHier, mChangeHier, mOpenHier, mAddHierSheet: TMenuItem;
    sbHomeFileSaveAll: TSpeedButton;
    mRepeatDirections: TMenuItem;
    mRepeatNameUp: TMenuItem;
    mRepeatNameDown: TMenuItem;
    mRepeatPinUp: TMenuItem;
    mRepeatPinDown: TMenuItem;
    mSepRepeat: TMenuItem;
    mSepRepeatPin: TMenuItem;
    sbViewViewZoomIn: TSpeedButton;
    sbHomeDocDetails: TSpeedButton;
    sbHomeDocSetup: TSpeedButton;
    sbViewViewZoomFit: TSpeedButton;
    sbViewViewZoomPage: TSpeedButton;
    sbViewViewZoomOut: TSpeedButton;
    Separator4: TMenuItem;
    mLibSymbol: TMenuItem;
    mParts: TMenuItem;
    mPartsNew: TMenuItem;
    mPartsEdit: TMenuItem;
    mPartsSep1: TMenuItem;
    mPartsAdd: TMenuItem;
    mPartsProps: TMenuItem;
    mPartsDup: TMenuItem;
    mPartsDel: TMenuItem;
    mPartsSep2: TMenuItem;
    mPartsClassAdd: TMenuItem;
    mPartsClassProps: TMenuItem;
    mPartsClassDel: TMenuItem;
    mPartsSep3: TMenuItem;
    mPartsFieldAdd: TMenuItem;
    mPartsFieldProps: TMenuItem;
    mPartsFieldDel: TMenuItem;
    mPartsSep4: TMenuItem;
    mPartsObjAdd: TMenuItem;
    mPartsObjProps: TMenuItem;
    mPartsObjDel: TMenuItem;
    mPartsSep5: TMenuItem;
    mPartsRatAdd: TMenuItem;
    mPartsRatProps: TMenuItem;
    mPartsRatDel: TMenuItem;
    mPartsSep6: TMenuItem;
    mPartsSep7: TMenuItem;
    mPartsValSet: TMenuItem;
    mPartsValClear: TMenuItem;
    mPartsSep8: TMenuItem;
    mPartsSep9: TMenuItem;
    mPartsProdImport: TMenuItem;
    mPartsProdExport: TMenuItem;
    mPartsSymNew: TMenuItem;
    mPartsSymEdit: TMenuItem;
    mPartsSymImport: TMenuItem;
    mPartsSymProps: TMenuItem;
    mPartsSymDefault: TMenuItem;
    mPartsSymDel: TMenuItem;
    mPartsProdAdd: TMenuItem;
    mPartsProdProps: TMenuItem;
    mPartsProdDel: TMenuItem;
    mPartsProdSuggest: TMenuItem;
    mPartsProdPrefer: TMenuItem;
    mPartsProdRatAdd: TMenuItem;
    mPartsProdRatProps: TMenuItem;
    mPartsProdRatDel: TMenuItem;
    mPartsOpen: TMenuItem;
    mSymbol: TMenuItem;
    mHelp: TMenuItem;
    mAbout: TMenuItem;
    Separator3: TMenuItem;
    mShowGrid: TMenuItem;
    mZoom100: TMenuItem;
    mZoomPage: TMenuItem;
    mZoomOut: TMenuItem;
    mZoomIn: TMenuItem;
    mView: TMenuItem;
    mRemoveSheet: TMenuItem;
    mSheet: TMenuItem;
    mLadder: TMenuItem;
    Separator1: TMenuItem;
    mInsert: TMenuItem;
    mOptions: TMenuItem;
    mSelectAll: TMenuItem;
    mExit: TMenuItem;
    mSep1: TMenuItem;
    mSaveAs: TMenuItem;
    mSave: TMenuItem;
    mOpenFile: TMenuItem;
    mNewProject: TMenuItem;
    mMain: TMainMenu;
    pmSheet: TPopupMenu;
    pmSheetUndo: TMenuItem;
    pmSheetRedo: TMenuItem;
    pmSheetSep1: TMenuItem;
    pmSheetZOrder: TMenuItem;
    pmSheetBringFront: TMenuItem;
    pmSheetSendBack: TMenuItem;
    pmSheetSep2: TMenuItem;
    pmSheetCut: TMenuItem;
    pmSheetCopy: TMenuItem;
    pmSheetPaste: TMenuItem;
    pmSheetDuplicate: TMenuItem;
    pmSheetSelectAll: TMenuItem;
    pmSheetSelectAllAlike: TMenuItem;
    pmSheetSep3: TMenuItem;
    pmSheetDelete: TMenuItem;
    pmSheetSep4: TMenuItem;
    pmSheetRotateLeft: TMenuItem;
    pmSheetRotateRight: TMenuItem;
    pmSheetFlip: TMenuItem;
    pmSheetSep5: TMenuItem;
    pmSheetZoomIn: TMenuItem;
    pmSheetZoomOut: TMenuItem;
    mFile: TMenuItem;
    Separator5: TMenuItem;
    sbMainBar: TStatusBar;
    sbHomeFileNew: TSpeedButton;
    sbHomeFileOpen: TSpeedButton;
    sbHomeEditUndo: TSpeedButton;
    sbHomeEditRedo: TSpeedButton;
    sbHomeEditDelete: TSpeedButton;
    sbHomeSelectOne: TSpeedButton;
    sbHomeSelectAll: TSpeedButton;
    sbHomeSelectRLeft: TSpeedButton;
    sbHomeSelectRRight: TSpeedButton;
    sbHomeSelectFlip: TSpeedButton;
    sbHomeSelectBackward: TSpeedButton;
    sbHomeSelectForward: TSpeedButton;
    sbExtendedInfo: TSpeedButton;
    sbView: TSplitButton;
    Panel2: TPanel;
    sbCloseDocs: TSplitButton;
    sbSheetDetails: TSplitButton;
    Splitter1: TSplitter;
    FTabHome: TTabSheet;
    FTabView: TTabSheet;
    FTabDraw: TTabSheet;
    pnlPropsSep: TPanel;
    tcSheetTabs: TTabControl;
    pmSheetTabs: TPopupMenu;
    pmTabInsert, pmTabDelete, pmTabRename, pmTabSep1, pmTabMoveLeft, pmTabMoveRight, pmTabSep2, pmTabHier: TMenuItem;
    tvLib: TTreeView;
    procedure Panel1Click(Sender: TObject);
    procedure rpSheetSheetsClick(Sender: TObject);
    procedure SheetTabImage(Sender: TObject; TabIndex: Integer; var ImageIndex: Integer);
    procedure MakeSheetTabMarks;
    procedure QueueSheetTabRefresh;
    procedure RememberLayout;
    procedure ApplyLayout;
    procedure FormShow(Sender: TObject);
    procedure RefreshSheetTabs(Data: PtrInt);
    procedure tcSheetTabsMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure pmSheetTabsPopup(Sender: TObject);
    procedure SheetTabRightClick(Index: Integer);
    { form handlers }
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    function EditDeleteForward(AControl: TWinControl): Boolean;
    function EditShortcutInBox(ACmd: Char): Boolean;
    procedure DoTheme(Sender: TObject);
    procedure ApplyTheme(Dark: Boolean);
    procedure AppHint(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure mAboutClick(Sender: TObject);
    { menu handlers }
    procedure DoProperties(Sender: TObject);
    procedure DoInsertLadder(Sender: TObject);
    procedure DoRemoveSheet(Sender: TObject);
    procedure DoNew(Sender: TObject);
    procedure DoOpen(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of String);
    procedure DoSave(Sender: TObject);
    procedure DoSaveAs(Sender: TObject);
    procedure DoSaveAll(Sender: TObject);
    procedure DoPartsList(Sender: TObject);
    procedure DoSymbolBom(Sender: TObject);
    procedure DoSymbolData(Sender: TObject);
    procedure DoExportWires(Sender: TObject);
    procedure DoCheckDupRefs(Sender: TObject);
    procedure DoNetList(Sender: TObject);
    procedure DoCheckRules(Sender: TObject);
    procedure DoVhdlCheckRules(Sender: TObject);
    procedure DoAnnotate(Sender: TObject);
    procedure ErcAnnotate(Sender: TObject);
    procedure DoSpiceNetList(Sender: TObject);
    procedure DoVhdlFile(Sender: TObject);
    procedure ErcItemChosen(Sender: TObject; Index: Integer);
    procedure ErcRecheck(Sender: TObject);
    procedure ErcCloseRequest(Sender: TObject);
    procedure ErcPcbNetlist(Sender: TObject);
    procedure ErcSpiceNetlist(Sender: TObject);
    procedure pnlMainClick(Sender: TObject);
    procedure ShowErcList(ADoc: TDocument; Lines: TStrings);
    procedure CloseErcWindow(DoClear: Boolean);
    procedure DoOpenLibrary(Sender: TObject);
    procedure DoLibraries(Sender: TObject);
    procedure DoSymbolCommand(Sender: TObject; Cmd: TSymbolCommand);
    procedure DoSymbolCopyTo(Sender: TObject; TargetIndex: Integer);
    procedure LibraryQueryClose(Sender: TObject; const FileName: String; var Allow: Boolean);
    procedure DoSymbolMenuCommand(Sender: TObject);
    procedure DoStoreSymbol(Sender: TObject);
    procedure DoSymbolProps(Sender: TObject);
    procedure DoSymbolParts(Sender: TObject);
    procedure DoSymbolPart(Sender: TObject);
    procedure BuildSymbolMenu;
    procedure DoOpenPartsLibrary(Sender: TObject);
    procedure DoNewPartsLibrary(Sender: TObject);
    procedure DoEditPartsLibrary(Sender: TObject);
    procedure DoPartAdd(Sender: TObject);
    procedure DoPartProperties(Sender: TObject);
    procedure DoPartDuplicate(Sender: TObject);
    procedure DoPartDelete(Sender: TObject);
    procedure DoClassAdd(Sender: TObject);
    procedure DoClassProperties(Sender: TObject);
    procedure DoClassDelete(Sender: TObject);
    procedure DoFieldAdd(Sender: TObject);
    procedure DoFieldProperties(Sender: TObject);
    procedure DoFieldDelete(Sender: TObject);
    procedure DoObjectAdd(Sender: TObject);
    procedure DoObjectProperties(Sender: TObject);
    procedure DoObjectDelete(Sender: TObject);
    procedure DoProductAdd(Sender: TObject);
    procedure DoProductProps(Sender: TObject);
    procedure DoProductDel(Sender: TObject);
    procedure DoProductSuggest(Sender: TObject);
    procedure DoProductPrefer(Sender: TObject);
    procedure DoProductRatAdd(Sender: TObject);
    procedure DoProductRatProps(Sender: TObject);
    procedure DoProductRatDel(Sender: TObject);
    procedure DoValueSet(Sender: TObject);
    procedure DoValueClear(Sender: TObject);
    procedure DoProductImport(Sender: TObject);
    procedure DoProductExport(Sender: TObject);
    procedure DoPartSymNew(Sender: TObject);
    procedure DoPartSymEdit(Sender: TObject);
    procedure DoPartSymImport(Sender: TObject);
    procedure DoPartSymProps(Sender: TObject);
    procedure DoPartSymDefault(Sender: TObject);
    procedure DoPartSymDelete(Sender: TObject);
    procedure PartSymbolEdit(Sender: TObject; PartID, SymbolID: Int64);
    procedure PartSymbolImport(Sender: TObject; PartID, SymbolID: Int64);
    procedure DoRatingAdd(Sender: TObject);
    procedure DoRatingProperties(Sender: TObject);
    procedure DoRatingDelete(Sender: TObject);
    procedure PartsMenuOpen(Sender: TObject);
    function IsSymbolDoc: Boolean;
    function SheetTabCaption(Index: Integer): String;
    function SymbolSheetsLocked: Boolean;
    function StartSymbolDoc(Ed: TSymbolEditor; const LibFile: String): TDocument;
    procedure UpdateSymbolMenu;
    procedure DoFileExit(Sender: TObject);
    procedure DoDelete(Sender: TObject);
    procedure DoSelectAll(Sender: TObject);
    procedure DoSelectAllAlike(Sender: TObject);
    procedure ColorButtonClick(Sender: TObject);
    procedure DoPlaceSymbol(Sender: TObject);
    procedure DoAddSheet(Sender: TObject);
    procedure DoInsertSheet(Sender: TObject);
    procedure AddSheetAt(APos: Integer);
    procedure DoInsertDesign(Sender: TObject);
    procedure DoAddHierarchicalSymbol(Sender: TObject);
    procedure DoReloadHierSymbol(Sender: TObject);
    procedure DoChangeHierDesign(Sender: TObject);
    procedure DoOpenHierDesign(Sender: TObject);
    procedure HierarchyMenuOpen(Sender: TObject);
    function ChooseDesignFile(const ATitle: String): String;
    procedure DoZoomIn(Sender: TObject);
    procedure DoZoomOut(Sender: TObject);
    procedure DoZoomFit(Sender: TObject);
    procedure DoZoom100(Sender: TObject);
    procedure DoToggleGrid(Sender: TObject);
    procedure DoAbout(Sender: TObject);
    procedure DoUndo(Sender: TObject);
    procedure DoRedo(Sender: TObject);
    procedure DoCut(Sender: TObject);
    procedure DoCopy(Sender: TObject);
    procedure DoPaste(Sender: TObject);
    procedure DoDuplicate(Sender: TObject);
    procedure DoDesignDetails(Sender: TObject);
    procedure DoPageSetup(Sender: TObject);
    procedure DoPrint(Sender: TObject);
    procedure DoPrintPreview(Sender: TObject);
    procedure DoPrintSetup(Sender: TObject);
    procedure DoExportImage(Sender: TObject);
    procedure DoTestPropRibbon(Sender: TObject);
    procedure ReplaceDlgFind(Sender: TObject);
    procedure ReplaceDlgReplace(Sender: TObject);
    procedure ReplaceAllPrompted;
    function AskReplace(const Where: String): Char;
    procedure DoFind(Sender: TObject);
    procedure DoOptions(Sender: TObject);
    procedure DoColors(Sender: TObject);
    procedure DoShowPosition(Sender: TObject);
    procedure DoShowViewRulers(Sender: TObject);
    procedure DoRulerUnits(Sender: TObject);
    procedure RulerUnitsPopup(Sender: TObject);
    procedure ViewMovedForRulers(Sender: TObject);
    procedure ArcTypeChangedByView(Sender: TObject);
    procedure DoRepeatNameUp(Sender: TObject);
    procedure DoRepeatNameDown(Sender: TObject);
    procedure DoRepeatPinUp(Sender: TObject);
    procedure DoRepeatPinDown(Sender: TObject);
    procedure DoToggleGridSize(Sender: TObject);
    procedure DoCopyTo(Sender: TObject);
    procedure DoImport(Sender: TObject);
    procedure DoInsertPicture(Sender: TObject);
    procedure DoFindReplace(Sender: TObject);
    procedure DoFindNext(Sender: TObject);
    procedure DoFindPrevious(Sender: TObject);
    procedure DoCloseDocument(Sender: TObject);
    procedure ContextPolyClick(Sender: TObject);
    procedure ContextLineClick(Sender: TObject);
    procedure ContextWireCutClick(Sender: TObject);
    procedure ContextRungClick(Sender: TObject);
    procedure ContextRungRefClick(Sender: TObject);
    procedure BuildRungMenu(Sym: Boolean);
    procedure PolyDrawMenuClick(Sender: TObject);
    procedure ArcDrawMenuClick(Sender: TObject);
    procedure DoCloseAllDocuments(Sender: TObject);
    procedure DoNextDocument(Sender: TObject);
    procedure DoPrevDocument(Sender: TObject);
    procedure DoWindowItem(Sender: TObject);
    procedure DoRenameSheet(Sender: TObject);
    procedure DoMoveSheetLeft(Sender: TObject);
    procedure DoMoveSheetRight(Sender: TObject);
    procedure DoRotateLeft(Sender: TObject);
    procedure DoRotateRight(Sender: TObject);
    procedure DoFlip(Sender: TObject);
    procedure DoBringToFront(Sender: TObject);
    procedure DoAlignToGrid(Sender: TObject);
    procedure DoOnePxGrid(Sender: TObject);
    procedure ApplyOnePxGrid(AOn: Boolean);
    function GridForAlign: Double;
    procedure DoSendToBack(Sender: TObject);
    procedure pnlLeftClick(Sender: TObject);
    procedure SheetTabChange(Sender: TObject);
    { ribbon handlers }
    procedure RibbonTabsPaint(Sender: TObject);
    procedure RibbonTabsMouseMove(Sender: TObject;
      Shift: TShiftState; X, Y: Integer);
    procedure RibbonTabsMouseLeave(Sender: TObject);
    procedure RibbonTabsMouseDown(Sender: TObject;
      Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure RibbonPageChange(Sender: TObject);
    procedure DoToolButton(Sender: TObject);
    procedure DoToolMenu(Sender: TObject);
    procedure DoToggleSnap(Sender: TObject);
    procedure DoGridButton(Sender: TObject);
    procedure DoGridSize(Sender: TObject);
    procedure DoGridCustom(Sender: TObject);
    procedure ViewSelection(Sender: TObject);
    procedure DoDesignDetailsBorder(Sender: TObject);
    procedure DoDesignDetailsExtended(Sender: TObject);
    procedure DoDetailsDropDown(Sender: TObject);
    procedure PartPlace(Sender: TObject; PartIndex: Integer);
    function PartsWarningAccepted: Boolean;
    function PlacePart(PartIndex: Integer): String;
    function BeginPlacePart(PL: TPartsLibrary; PartIndex: Integer; const Xml, Ref: String; const Copy: TPartCopy): String;
    function InsertContactOf(const Form: String; out Chosen: String): String;
    procedure DoInsertContactNO(Sender: TObject);
    procedure DoInsertContactNC(Sender: TObject);
    procedure DoInsertContactFree(Sender: TObject);
    function ChooseProduct: String;
    procedure HookSymbolFrame(AFrame: TfmSymbols);
    procedure SymbolAutoShowChange(Sender: TObject);
    procedure AutoShowSymbolList(Data: PtrInt);
    procedure SymbolRotate(Sender: TObject);
    procedure SymbolPickDirection(Sender: TObject; ADir: Integer);
    procedure SymbolMirror(Sender: TObject);
    function SymbolParameters(Sender: TObject): TMethodArray;
    procedure SymbolListChange(Sender: TObject; ABefore: Boolean);
    procedure ShowSymbolFrames;
    function SymbolFrameTag(AFrame: TObject): Integer;
    function SymbolValue(ATag: Integer; const AName: String): String;
    function SymbolTarget(ATag: Integer): TDrawMethod;
    procedure PartsFileChanged(Sender: TObject);
    procedure DoDesignDetailsRuler(Sender: TObject);
    procedure DoGridSizeUp(Sender: TObject);
    procedure DoReplaceSymbol(Sender: TObject);
  private
//    FRibbon: TPageControl;
//    FStatus: TStatusBar;
//    FSheetTabs: TTabControl;
//    FLibPanel: TLibraryPanel;
//    FSplitter: TSplitter;
    FRibbonTabs: TRibbonTabStrip;    // the painted tab headings of the ribbon (URibbon); the *_Ribbon* handlers below only pass the paint box's events to it
    { the open documents; FView, FDesign, FFileName and FModified are those of the current one }
    FDocs: TDocumentList;
    FCurrent: Integer;               // index of the current document, -1 when none is open
    FPartsEditorError: String;       // why OpenPartsEditor failed
    FPlaceholder: TSchematicView;    // the empty drawing area shown while no document is open
    tcDocs: TDocTabStrip;            // one tab per open document, above the drawing area (UDocTabs)
    FEditKey: Char;                  // Ctrl+C, X, V, A, Z or Y was pressed while a text box has the focus (set by FormKeyDown, cleared when the key is up); the menu command then works on the text
    FRefAutoEdit: TEdit;             // the reference box that took the focus when a symbol was chosen (while it still holds the text and selection it was given, Del deletes the symbol)
    FRefAutoText: String;
    FDelKeyInEdit: Boolean;          // Del was pressed while a text box has the focus (set by FormKeyDown, cleared when the key is up); DoDelete then edits the text
    FTabRefreshQueued: Boolean;        // a rebuild of the sheet tabs is waiting (QueueSheetTabRefresh)
    FContextPoint: TDPoint;          // where on the sheet it was opened
    FUpdatingTabs: Boolean;
    FWindowDocItems: TList;          // the separator and document entries of the Window menu made at run time (the rest of the menu is in the form file)
    FFind: TFindSession;             // what Find and Replace is looking for, and where it found it last
    FFindOpen: Boolean;              // the Find and Replace dialog is on screen
    FindPromptScript: String;        // for tests: the answers (y, n, c) to the questions of Replace All with "Prompt on replace"
    FindPromptScripted: Boolean;     // for tests: no box is shown, a question not answered by the script is answered with Cancel
    FAutoSaveTimer: TTimer;          // saves a copy of every named design now and then (Options)
    FPrinterPicked: Integer;         // the printer last chosen in the Print dialog's drop down (for tests), -1 before
    FErcForm: TfrmErcList;           // the Design Markers window (the result list of the design rules check), nil until a check has shown it
    FAnnotate: TAnnotateSetup;       // Generate Symbol References: the choices of the last time
    FErcDoc: TDocument;              // the document the markers and the list belong to, nil if the window is not showing
    FFindDoc: TDocument;             // the document the find results (and their red circles) belong to, nil if the find panel is closed
    FFindHits: TObjectHitArray;      // what the list of the find panel shows
    frameFindPanel: TfrFindPanel;    // the find panel, made by FormCreate (not by the form file) and owned by the form
    FRecentItems: TList;             // the menu items of the recently used files (owned by the File menu)
    FQuiet: Boolean;                 // messages go to the status bar instead of a dialog (scripts)
    FUpdatingRibbon: Boolean;        // the ribbon's details controls are being set from the sheet, not by the user
    FToolButtons: array[TViewTool] of TSpeedButton;
    FToolMenus: array[TViewTool] of TMenuItem;
    {FBtnUndo, FBtnRedo, FBtnSnap, FBtnGrid: TSpeedButton;}
//    {FTabHome,} {FTabDraw, }{FTabLadder, }{FTabLibrary, }{FTabView,} FTabProps: TTabSheet;
    FPropLabel: TLabel;
    FPropFrame: TFrame;            // the property frame shown in plPropsProperties for the selection (nil: the editors BuildEditors made)
    FPropBind: TFrameBindings;
    FPropProblems: TStringList;    // what was wrong with the frame of the selection (see QPropFrame.BindPropFrame)
    FToolFrame: TFrame;            // the same for the tool's panel on the Draw ribbon
    FToolBind: TFrameBindings;
    FToolProblems: TStringList;
    FAutoShowWait: Boolean;        // the list is to open as soon as the mouse button is let go (a symbol was pressed on: opening under the pointer would take the release)
    FAutoShowParams: Boolean;      // the parameter button of the symbol frames is on: the list opens whenever a symbol is selected
    FPropTimer: TTimer;            // applies a number box a moment after its last change (PropSpinDelay)
    FSpinPending: TControl;        // the number box waiting for it
    FTabBeforeProps: String;       // the ribbon tab that was showing when selecting brought the Properties tab forward ("" when none to go back to)
    FProps: TPropEditorArray;
    FUpdatingProps: Boolean;
    FRulerTop, FRulerLeft: TViewRuler;  // the rulers along the top and left of the drawing area (UViewRulers)
    FShowingRulers: Boolean;          // ShowViewRulers is setting the check box (its OnChange is not a request)
    FRulersWanted: Boolean;           // the option: the rulers are shown while a document is open
    FShowingPosition: Boolean;        // ShowPositionBar is setting the check box of the ribbon (its OnChange is not a request)
    FFillDrop: TfrmFillDropDown;      // the menu of the Fill button of the property panels (made when first needed)
    FPartsWarned: Boolean;            // the warning about parts was agreed to in this run
    FProductPickAnswer: String;       // for the self-test script: '' ask, 'mfr|model' choose that product, 'cancel' cancel the window
    FPartsWarnMode: Integer;          // for the self-test script: 0 ask, 1 answer yes, 2 answer no
    FDetailsDrop: TfrmDesignDetailsDropDown;      // the sheet details form of the Details button (made at start)
    FBusDrop: TfrmBusDropDown;        // the panel of the Phases button of the bus property panels (made when first needed)
    FUpdatingPosition: Boolean;       // the 1 px grid check box is being set from the document, not clicked
    FDestroying: Boolean;             // the window is being freed: a view letting go of its design must not rebuild the property panel
    FBusTag: Integer;                 // the Tag of the editor it was dropped down from
    FFillTag: Integer;                // the Tag of the editor it was dropped down from
    FToolSep, FToolPanel: TPanel;       // the Draw ribbon's Properties panel of the tool in use (made when a draw tool is chosen, freed when Select is)
    FToolLabel: TLabel;
    FToolEditors: TPropEditorArray;
    FToolOf: TViewTool;
    FTheme: TLDTheme;
    FActivated: Boolean;               // the form has been activated once (the ribbon was put on its first page)
    function AddButton(ATab: TTabSheet; var X: Integer; const ACaption, AHint: String;
      AHandler: TNotifyEvent; AWidth: Integer = 64): TSpeedButton;
    function AddToolButton(ATab: TTabSheet; var X: Integer; ATool: TViewTool; const ACaption: String): TSpeedButton;
    function SetToolButton(Button: TSpeedButton; ATool: TViewTool; MenuItem: TMenuItem = nil): boolean;
    procedure Gap(var X: Integer);
    procedure BuildRibbon;
    procedure BuildLayout;
    function GetCurDoc: TDocument;
    function GetView: TSchematicView;
    function GetDesign: TDesignFile;
    function GetFileName: String;
    procedure SetFileName(const Value: String);
    function GetModified: Boolean;
    procedure SetModified(Value: Boolean);
    function CreateView: TSchematicView;
    function AddDocument(ADesign: TDesignFile; const AFileName: String): TDocument;
    procedure ShowNoDocument;
    procedure RefreshAfterDocumentChange;
    procedure UpdateDocTabs;
    procedure RebuildWindowMenu;
    procedure FocusView;
    function ConfirmCloseDocument(Index: Integer): Boolean;
    procedure DocTabChange(Sender: TObject);
    procedure DetailsApplyRequest(Sender: TObject);
    procedure DocTabClose(Sender: TObject; Index: Integer);
    property CurDoc: TDocument read GetCurDoc;
    property FView: TSchematicView read GetView;
    property FDesign: TDesignFile read GetDesign;
    property FFileName: String read GetFileName write SetFileName;
    property FModified: Boolean read GetModified write SetModified;
    procedure RebuildSheetTabs;
    procedure AddSheetFromTab(Data: PtrInt);
    function SheetTabsMatch: Boolean;
    procedure UpdateFormTitle(NewTitle: string = '');
    procedure UpdatePaperStatus;
    procedure UpdateRibbonState;
    function DescribeSelection: String;
    function ShowFrame(AParent: TWinControl; AOwner: TComponent; const AKey: String; const Defs: TPropDefArray; ATagBase: Integer; var Items: TPropEditorArray;
      var AFrame: TFrame; var ABind: TFrameBindings; AProblems: TStringList): Integer;
    function FrameOwnsCaption(AFrame: TFrame): Boolean;
    function FrameLabelsItself(AFrame: TFrame): Boolean;
    function ToolFrameKey(ATool: TViewTool): String;
    function SelectionFrameKey: String;
    procedure ShowEditorValue(var AEditor: TPropEditor; const AValue: String; AMixed: Boolean);
    function EditorOfTag(ATag: Integer): PPropEditor;
    function CurrentChoice(ATag: Integer): String;
    procedure PropComboDone(Sender: TObject);
    procedure PropComboKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PropSpeedClick(Sender: TObject);
    procedure PropFillClick(Sender: TObject);
    procedure PropBusClick(Sender: TObject);
    function IsBusButton(AControl: TComponent): Boolean;
    procedure BusPicked(Sender: TObject; APhases: Integer; ASpacingMm: Double);
    procedure ShowBusGlyph(AButton: TSpeedButton; APhases: Integer; ASpacingMm: Double);
    function IsFillButton(AControl: TComponent): Boolean;
    procedure FillPicked(Sender: TObject; AChoice: Integer; AColor: TColor);
    function FillColorOf(ATag: Integer): String;
    procedure CommitNamed(ATag: Integer; const AName, AValue: String);
    procedure ShowFillGlyph(AButton: TSpeedButton; AChoice: Integer; AColor: TColor);
    function BuildEditors(APanel: TPanel; const Defs: TPropDefArray; ATagBase: Integer; var Items: TPropEditorArray): Integer;
    procedure RebuildProps;
    procedure UpdateToolPanel;
    procedure FreeToolPanel;
    procedure ShowToolPropValues;
    procedure CommitToolProp(Index: Integer; const Value: String);
    procedure CommitAny(Index: Integer; const Value: String);
    procedure SizePropsPanel(ANeeded: Integer);
    procedure ClearPropEditors;
    procedure ShowPropValues;
    procedure PropEditDone(Sender: TObject);
    procedure PropEditChange(Sender: TObject);
    procedure FocusToolText;
    procedure FocusPropEditor(const AName: String);
    procedure ViewDblClick(Sender: TObject);
    procedure FocusToolTextAsync(Data: PtrInt);
    procedure PropChoiceChange(Sender: TObject);
    procedure PaintLineStyleItem(ACanvas: TCanvas; const ARect: TRect; AIndex: Integer; ASelected: Boolean);
    procedure LineStyleDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
    procedure PropBoolClick(Sender: TObject);
    procedure PropColorChanged(Sender: TObject);
    procedure PropNumberChange(Sender: TObject);
    procedure PropNumberDone(Sender: TObject);
    procedure PropTimerTick(Sender: TObject);
    procedure CommitNumber(ABox: TCustomFloatSpinEdit);
    procedure ShowNumberValue(var AEditor: TPropEditor; const AValue: String; AMixed: Boolean);
    procedure CommitProp(Index: Integer; const Value: String);
    { handlers }
    procedure ViewStatus(Sender: TObject; const Msg: String);
    procedure ViewModified(Sender: TObject);
    procedure ViewToolChanged(Sender: TObject);
    procedure ViewDragEnd(Sender: TObject);
    procedure ViewZoomChanged(Sender: TObject);
    procedure UpdateZoomDisplay;
    procedure ViewUndoChanged(Sender: TObject);
    procedure ViewPlaced(Sender: TObject; Obj: TDrawingObject);
    procedure LibPlace(Sender: TObject; Lib: TSymbolLibrary; SetIndex, RecIndex: Integer);
    procedure UpdateRibbonFromView;
    procedure SyncFindFromDialog;
    function FindStep(Down: Boolean): Boolean;
    procedure ShowFound;
    procedure FindMessage(const Msg: String);
    procedure ReplaceDlgClose(Sender: TObject);
    procedure FindPanelFind(Sender: TObject);
    procedure FindPanelResultSelected(Sender: TObject; Index: Integer);
    procedure FindPanelClose(Sender: TObject);
    procedure FindMarkerClicked(Sender: TObject; Index: Integer);
    procedure CloseFindPanel;
    procedure AutoSaveTick(Sender: TObject);
    procedure ViewPosition(Sender: TObject; const Msg: String);
    procedure UpdatePositionBar;
    procedure UpdateRepeatMenu;
    procedure SetupAutoSave;
    procedure UseSettingsAsDefaults;
    procedure OptionsApplyRequest(Sender: TObject);
    procedure RefreshGridMenuCaptions(Units: Integer);
    procedure SyncGridSizeMenus;
    procedure CloseFindDocMarkers;
    procedure RebuildRecentMenu;
    procedure NoteFileUsed(const AFileName: String);
    procedure DoOpenRecent(Sender: TObject);
    procedure ReportProblem(const Msg: String);
    procedure LibrariesChanged(Sender: TObject);
    procedure ApplySheetDetail(What: TSheetDetail);
    function DetailFor(Sender: TObject): TSheetDetail;
    procedure DetailsFieldExit(Sender: TObject);
    procedure DetailsFieldKeyPress(Sender: TObject; var Key: Char);
  public
    { what the program shares between its forms lives in FSharedCtls (frmSharedControls, created first): these are the same objects, taken from it when this form is made }
    OpenDlg: TOpenDialog;
    SaveDlg: TSaveDialog;
    PrintDlg: TPrintDialog;
    dlgPrinterSetup: TPrinterSetupDialog;
    dlgPageSetup: TPageSetupDialog;
    ReplaceDlg: TReplaceDialog;
    ilSpeedBtn: TImageList;
    ilTinyIcons: TImageList;
    ilListBoxImages: TImageList;
    AnnotateScript: TStrings;          // for tests: answers for the Generate Symbol References dialog (nil: the dialog is shown)
    AnnotateReport: String;            // ... and what the last answered dialog showed and did
    PrintSinkDir: String;              // for tests: not empty prints on A4 bitmap pages (written to this folder as page_<n>.png) instead of the printer
    PrintTestDpi: Integer;             // ... and the resolution of those pages
    PrintScript: TStrings;             // for tests: answers for the Print dialog (nil: the dialog is shown)
    PrintReport: String;               // ... and what the last answered dialog showed and did
    PreviewScript: TStrings;           // for tests: what is done in the Print Preview window (nil: the window is shown)
    PreviewReport: String;
    PrinterPageScript: String;         // for tests: the answer of the printer for the Page Setup dialog's Printer buttons: 'none' or '<width>x<height>' (mm); empty asks the printer
    TestLibInUse: TStrings;            // for tests: the files of libraries that count as in use (being edited); nil for none
    { Library > Libraries...: the Library Setup dialog filled as it starts (BeginLibraries); a library is in use when it is being edited (no editor yet, so only
      TestLibInUse). RestoreLibraries opens the libraries of the last run (those that cannot be opened are left out) and returns how many are open }
    function BeginLibraries: TfrmLibraries;
    property CurrentDocument: TDocument read GetCurDoc;
    procedure LibraryMenuOpen(Sender: TObject);
    function SheetTabsAreRight: Boolean;
    function LibraryIsInUse(const FileName: String): Boolean;
    function RestoreLibraries: Integer;
    { ---- the symbol editor: a library symbol is a document of its own (TDocument.Symbol), drawn with the pin and origin tools and stored back in its library ---- }
    { the document of a symbol being edited (library file and the symbol's id in it), or -1 }
    function SymbolDocIndex(const LibFile: String; SymbolId: Int64): Integer;
    { Edit symbol: opens a symbol of the library at LibIndex of the panel (a symbol already open is shown); nil when it cannot be opened }
    function OpenSymbolDoc(LibIndex, SetIndex: Integer): TDocument;
    { New symbol: an empty symbol for the library at LibIndex }
    function NewSymbolDoc(LibIndex: Integer): TDocument;
    { Store in library: checks the symbol and stores it, replacing the symbol it came from. False with the errors in Msg when it has any; Msg holds the warnings otherwise }
    function StoreSymbolDoc(Doc: TDocument; out Msg: String): Boolean;
    { starts the symbol editor on a symbol of a part of a parts file (SymbolID 0: a new one with these properties); stored back into the file }
    function StartPartSymbol(Ed: TfrPartsEditor; PartID, SymbolID: Int64; const AStandard, APurpose, AName: String): TDocument;
    { takes the symbol chosen in the library panel as a new symbol of the part }
    function ImportPanelSymbol(Ed: TfrPartsEditor; PartID: Int64; const AStandard, APurpose, AName: String; out Msg: String): Boolean;
    function DeleteLibrarySymbol(LibIndex, SetIndex: Integer; out Msg: String): Boolean;
    function ExportLibrarySymbols(LibIndex, SetIndex: Integer; const AFileName: String; out Msg: String): Boolean;
    function ImportLibrarySymbols(LibIndex: Integer; const AFileName: String; out Msg: String): Boolean;
    procedure ExportLibraryDialog(ALibIndex, ASetIndex: Integer);
    procedure ImportLibraryDialog(ALibIndex: Integer);
    { ---- the pop-up menu of a right click on the sheet ---- }
    function BuildContextMenu(const P: TDPoint): TPopupMenu;
    function ContextMenuNow: TPopupMenu;
    procedure ViewContext(Sender: TObject; X, Y: Integer; const P: TDPoint);
    function ReplaceSymbolWith(LibIndex, SetIndex, RecIndex: Integer; KeepFields: Boolean; out Msg: String): Boolean;
    function DuplicateLibrarySymbol(LibIndex, SetIndex: Integer; out Msg: String): Boolean;
    function CopyLibrarySymbol(LibIndex, SetIndex, TargetIndex: Integer; out Msg: String): Boolean;
    { Symbol Properties (names, description, attributes, SPICE) of the symbol being edited: the dialog filled, and what OK or Cancel does }
    function BeginSymbolProps: TfrmSymbolProps;
    procedure EndSymbolProps(F: TfrmSymbolProps; Accept: Boolean);
    { Symbol properties of a symbol chosen in the library list: the dialog on its own (no editor tab), OK stores the change in the library }
    function BeginLibraryProps(LibIndex, SetIndex: Integer; out Ed: TSymbolEditor): TfrmSymbolProps;
    function EndLibraryProps(F: TfrmSymbolProps; Ed: TSymbolEditor; Accept: Boolean; out Msg: String): Boolean;
    procedure LibrarySymbolProps(LibIndex, SetIndex: Integer);
    { Parts per Package }
    function BeginSymbolParts: TfrmSymbolParts;
    procedure EndSymbolParts(F: TfrmSymbolParts; Accept: Boolean);
    { the part drawn on a drawing the parts share (0-based) and the text for the status bar; a symbol with a drawing for each part has a sheet for each instead }
    procedure ShowSymbolPart(Part: Integer);
    function SymbolPartText: String;
    function RibbonPaintCount: Integer;
    function RecentMenuText: String;
    { Find and Replace: where the last search stands, as text (for tests) }
    function FindInfoText: String;
    procedure SetFindPrompt(const Answers: String);
    { the find panel (TinyCAD's Find: every object that mentions a text, listed, with a red circle on each) }
    procedure RunFindPanel(const AText: String);
    procedure ChooseFindResult(Index: Integer);
    function FindPanelText: String;
    { ---- Options ---- }
    { what the Options dialog shows now: the open design's settings (or the program's, with no design open) }
    function CurrentOptions: TOptionsData;
    { apply options to the open design (every sheet of it), keep them as what new designs start with and restart the automatic save; False if they cannot be used }
    function ApplyOptions(const D: TOptionsData): Boolean;
    { save a copy of every named design as <name>.autosave; returns how many were saved }
    function AutoSaveAll: Integer;
    { the automatic save as text, for tests }
    function AutoSaveInfo: String;
    { Save All: every design with unsaved changes is saved to its file; returns how many were saved (see the notes of the routine) }
    function SaveAllDocuments(AskNames: Boolean; out Skipped: Integer; out FailedNames: String): Integer;
    { the designs that are open, remembered when the program closes and opened again at the next start if Options says so }
    procedure SaveSession;
    function RestoreSession: Integer;
    { show or hide the Position bar (and, if Keep, keep the choice for the next run) }
    procedure ShowPositionBar(AShow, Keep: Boolean);
    procedure ShowViewRulers(AShow, Keep: Boolean);
    procedure UpdateViewRulers;
    function WritePartsList(const AFileName: String; const Opt: TBomOptions): Boolean;
    function WriteSymbolBom(const AFileName: String): Boolean;
    function WriteSymbolData(const AFileName: String): Boolean;
    function WriteWires(const AFileName: String; out Count: Integer): Boolean;
    function CheckDuplicateRefs(Quiet: Boolean): String;
    function CurrentFileName: String;
    function ExportNetList(F: TfrmNetlist): Boolean;
    { File > Export Image...: the dialog filled as it starts and what Export does (it writes the picture of the selection, or of the sheet when nothing is selected) }
    function BeginExportImage: TfrmExportImage;
    function ExportImageFile(F: TfrmExportImage): Boolean;
    { Special > Check Design Rules / V&HDL Check Design Rules: the options dialog filled as it starts (BeginErcDialog), then what Check does with it (FinishErcDialog);
      RunCheck is the check itself (TinyCAD's DoSpecialCheck / DoSpecialVHDLCheck): it returns the number of errors and shows the Design Markers window when there
      are some, or when AlwaysShow. The commands that make a netlist check first without showing anything unless there are errors (the BeginNetList, BeginSpice and
      BeginVhdl methods do that and then give what the command's own dialog starts with) }
    function BeginErcDialog: TfrmErcOptions;
    function FinishErcDialog(F: TfrmErcOptions; Vhdl: Boolean): Integer;
    function RunCheck(Vhdl, AlwaysShow: Boolean): Integer;
    { Special > Generate Symbol References: the dialog filled as it starts (BeginAnnotateDialog) and what its buttons do (FinishAnnotateDialog: mrOK numbers the
      symbols and returns True when a symbol had no definition; mrYes starts the reference painter). The choices of the last time are kept in FAnnotate for this run
      of the program, as the C++ keeps theASetup }
    function BeginAnnotateDialog: TfrmAnnotate;
    function FinishAnnotateDialog(F: TfrmAnnotate; Res: TModalResult): Boolean;
    { for tests: the dialog filled as a person would fill it from the options (name=value), a button pressed, and a report of what it showed and what happened;
      while AnnotateScript is set the command's dialog is answered this way in place of being shown (the report is kept in AnnotateReport) }
    function AnnotateScriptRun(Opts: TStrings): String;
    function AnnotateRefsText: String;
    { File > Print...: the dialog filled as it starts (BeginPrintDialog: any drawing tool is put away) and what its buttons do (FinishPrintDialog: OK keeps the scale and
      prints, returning the number of pages sent, or -1 when nothing was printed). The Printer button shows the system's own Print dialog (PrintDlg) for the printer,
      pages and copies. MakePrintSink gives the printer (or, for tests, bitmap pages); with no printer installed the dialog shows an A4 page to lay the pages out on and
      OK is dimmed }
    function PrinterInstalled: Boolean;
    function MakePrintSink(Portrait: Boolean): TPrintSink;
    function BeginPrintDialog: TfrmPrint;
    function FinishPrintDialog(F: TfrmPrint; Res: TModalResult): Integer;
    function PrinterSetupInDialog(Sender: TObject): Boolean;
    procedure PrinterPickedInDialog(Sender: TObject; Index: Integer);
    procedure PrintDialogPaintPage(Sender: TObject; const L: TPrintLayout; const Dev: TPrintDevice; PageNo: Integer; ACanvas: TCanvas; PxW, PxH: Integer; Black: Boolean;
      Factor: Double);
    function PrinterNames(out AIndex: Integer): TStringList;
    function PrintScriptRun(Opts: TStrings): String;
    { File > Print Preview: the window made for the sheet showing, and the same worked by a list of actions for tests }
    function BeginPreview: TfrmPreview;
    function PreviewScriptRun(Ops: TStrings): String;
    { the Printer Paper and Printer Setup buttons of the Page Setup dialog: the size of the printer's page in mm, after the printer's page setup dialog when Choose }
    function PrinterPageFor(Choose: Boolean; out HorzMm, VertMm: Integer): Boolean;
    function BeginNetList: TfrmNetlist;
    function BeginSpice: String;
    function BeginVhdl: String;
    { the Design Markers window as text for tests: whether it is open, which document, the lines, the selected line, the markers by sheet and which is selected }
    function ErcWindowText: String;
    function ErcMarkersText: String;
    procedure ErcChoose(Index: Integer);
    procedure ErcPress(const AButton: String);
    function ErcWindowOpen: Boolean;
    { Special > Create Spice Net List / Create VHDL file: the name the Save dialog proposes, and what happens once a name is chosen }
    function SpiceProposedName: String;
    function VhdlProposedName: String;
    function ExportSpice(const AFileName: String): Boolean;
    function ExportVhdl(const AFileName: String): Boolean;
    function WriteNetList(const AFileName: String; AFormat: Integer): Boolean;
    { the Position bar as text, for tests }
    function PositionInfo: String;
    procedure SetOnePxGridBox(AChecked: Boolean);
    procedure RefreshSymbolControls;
    function OnePxGridChecked: Boolean;
    function OnePxGridEnabled: Boolean;
    function AlignGridUnits: Double;
    procedure AlignMenuOpen;
    function AlignItemVisible: Boolean;
    function AlignItemEnabled: Boolean;
    { the Repeat Directions as text, for tests }
    function RepeatInfo: String;
    { ---- the Colors dialog ---- }
    { apply the colors a Colors dialog holds to every sheet of the open design, keep the ten it lists that differ from the factory colors as the ones new designs
      start with, and redraw }
    procedure ApplyColors(F: TfrmOptions);
    { Copy to: save the selected objects as a design file of their own; returns how many were written }
    function CopySelectionTo(const AFileName: String): Integer;
    { Import: bring another design into this sheet as a block that follows the mouse; returns how many objects were read }
    function ImportDesign(const AFileName: String): Integer;
    { Insert picture: a PNG, JPEG or BMP file becomes a picture that follows the mouse until it is placed; False if it cannot be inserted }
    function InsertPicture(const AFileName: String): Boolean;
    { Special > Insert another design as symbol: reads the design and starts placing it on this sheet; False (with a message) when it cannot be read }
    function InsertDesign(const AFileName: String): Boolean;
    { Special > Add hierarchical symbol: adds the sheet that draws this design as a symbol, in front, and shows it; False when the design has one }
    function AddHierarchicalSymbol: Boolean;
    { the one placed design that is selected, or nil }
    function SelectedHierarchical: TDrawHierarchicalSymbol;
    { Special > Reload symbol from design; False when no placed design is selected or it cannot be read }
    function ReloadSelectedDesign: Boolean;
    { Special > Change design of symbol: the selected placed design is given another design file (one undo step) }
    function ChangeSelectedDesign(const AFileName: String): Boolean;
    { Special > Open design of symbol: opens the selected placed design's file in a document of its own }
    function OpenSelectedDesign: Boolean;
    function FindHitsText: String;
    { open the n-th recently used file (0 is the newest), as choosing it in the File menu does }
    procedure OpenRecentFile(Index: Integer);
    function DropFilesAt(const FileNames: array of String; const ScreenPt: TPoint): Integer;
    property Quiet: Boolean read FQuiet write FQuiet;
    property FindPanel: TfrFindPanel read frameFindPanel;
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenDesignFile(const FileName: String);
    { documents: switch to one, close one (Confirm asks about unsaved changes), how many are open }
    procedure ActivateDocument(Index: Integer);
    procedure ApplyDocVisibility;
    procedure PartsEditorChanged(Sender: TObject);
    function CloseDocument(Index: Integer; Confirm: Boolean): Boolean;
    { apply what the Design Details / Page Setup dialog holds to the current sheet, as one undo step;
      False if it changed nothing }
    function ApplyDesignDetails(F: TfrmDetails): Boolean;
    procedure DetailsApplyAllRequest(Sender: TObject);
    function ApplyDetailsTabToAll(F: TfrmDetails): Boolean;
    function ApplyPageSetup(F: TfrmPageSetup): Boolean;
    function DetailsInfoText: String;
    { save the current document under a name without asking (what Save As does after the dialog) }
    procedure SaveCurrentAs(const AFileName: String);
    function DocumentCount: Integer;
    function DocumentIndex: Integer;
    function DocumentCaption(Index: Integer): String;
    function WindowMenuText: String;
    { the strip of document tabs (tests click on it) }
    property DocTabs: TDocTabStrip read tcDocs;
    property PartsEditorError: String read FPartsEditorError;
    { opens the parts library editor for a file as a tab (or shows the one that is open); nil with PartsEditorError set when the file cannot be used }
    function OpenPartsEditor(const AFile: String): TDocument;
    function PartsEditorOfCurrent: TfrPartsEditor;
    property RulerTop: TViewRuler read FRulerTop;
    property RulerLeft: TViewRuler read FRulerLeft;
    property RulersWanted: Boolean read FRulersWanted;
    { sheets: remove the current one, give it a name, move it left or right among the others }
    function RemoveCurrentSheet(Confirm: Boolean): Boolean;
    procedure RenameCurrentSheet(const NewName: String);
    procedure MoveCurrentSheet(Delta: Integer);
    procedure NewDesignWith(const PaperName: String; Landscape: Boolean);
    procedure OpenLibraryFile(const FileName: String);
    function InsertLadderMm(X1, Y1, X2, Y2: Double): TDrawLadder;
    procedure PlaceLibraryRow(Row: Integer; Xmm, Ymm: Double);
    { used by the self-test script: the same handlers a click or an edit would reach }
    function PressRibbon(const ACaption: String): Boolean;
    function SetPropertyText(const PropName, Value: String): Boolean;
    function LineStyleItemStats(AIndex: Integer): String;
    function LineStyleComboInfo: String;
    function ToolPanelInfo: Boolean;
    function ToolEditorNames: TStringArray;
    function TypeNumber(const AName: String; AValue: Double; AToolPanel, AFinish: Boolean): Boolean;
    procedure PropFramesChanged;
    function FrameInfo(ATool: Boolean): TStringArray;
    function FrameComboItems(ATool: Boolean; const AName: String): String;
    function BusDropAct(const AAct: String): String;
    function BusDropForm: TForm;
    function FillDropAct(const AAct: String): String;
    function FillDropForm: TForm;
    function FrameGlyph(ATool: Boolean; const AName: String): String;
    procedure FocusTextEditor;
    procedure PropEditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    function ControlShown(AControl: TControl): String;
    function FrameAct(ATool: Boolean; const AName, AAction, AValue: String): Boolean;
    function SetToolPropertyText(const AName, AValue: String): Boolean;
    function PropertyDump: String;
    procedure ShowRibbonTab(const ATitle: String);
    procedure ChooseRibbonTab(const ATitle: String);
    function RibbonTabTitle: String;
    procedure SetGridMmFromScript(Mm: Double);
    procedure SetRibbonTheme(RibbonTheme: TLDTheme);
    function SymbolFrameAct(ATool: Boolean; const AAct: String; AArg: Integer): String;
    function SymbolListAct(ATool: Boolean; const AAct, AArg: String): String;
    property ProductPickAnswer: String read FProductPickAnswer write FProductPickAnswer;
    property PartsWarnMode: Integer read FPartsWarnMode write FPartsWarnMode;
    function PlacePartRow(Row: Integer; Xmm, Ymm: Double): String;
    property DetailsDrop: TfrmDesignDetailsDropDown read FDetailsDrop;      // the form of the Details button (for the self-test script)
    property View: TSchematicView read GetView;
//    property LibPanel: TfrLibraryPanel read FLibPanel;
    property Design: TDesignFile read GetDesign;
    property RibbonTabs: TPageControl read FRibbon;
    property Theme: TLDTheme read FTheme write SetRibbonTheme;
  end;

implementation

uses UStrings, LazUTF8, FSharedCtls{$IFDEF WINDOWS}, OSPrinters{$ENDIF};

{ ===========================================================================
  RadioChoice  (function)
  Parameters:
    ARadio: TRadioButton
    const AChoices: String - text
  Returns:
    Integer
  Notes:
    The caption is the choice ('in', 'out'); an accelerator mark & is ignored and so is the
    case.
  =========================================================================== }
function RadioChoice(ARadio: TRadioButton; const AChoices: String): Integer;
begin
  Result := ChoiceIndex(AChoices, Trim(StringReplace(ARadio.Caption, '&', '', [rfReplaceAll])));
end;

{ ===========================================================================
  PropRowTop  (function)
  Parameters:
    ARow: Integer - whole number
  Returns:
    Integer
  Notes:
    Rows of the Properties panel are PropRowHeight (36) pixels high: the first starts at PropTop
    (5), the second PropRowStep (51) below it, at 56.
  =========================================================================== }
function PropRowTop(ARow: Integer): Integer;
begin
  Result := PropTop + ARow * PropRowStep;      // rows of PropRowHeight pixels: the first at 5, the second at 56
end;

{$R *.lfm}

const
  ADD_SHEET_TAB = '+';       // the caption of the last sheet tab, which adds a sheet

type
  { gives access to the protected OnDblClick of a control }
  TCrackControl = class(TControl)
  end;

const
//  APP_NAME = 'Schematic';
  BTN_H = 58;

{ ------------------------------------------------------------------ construction }

{ ===========================================================================
  TfrmMain.Create  (constructor)
  Parameters:
    TheOwner: TComponent - owner (the application)
  Notes:
    Creates the main window by loading the designed form (menus, status bar, file dialogs) from
    mainform.lfm; the run-time setup is done in FormCreate.
  =========================================================================== }
constructor TfrmMain.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);   // Create (not CreateNew) so that frmMain.lfm is read and the menu and dialogs exist
end;

{ ===========================================================================
  TfrmMain.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the property editors and the documents (each detaches and frees its own view and
    design). Safe if construction failed part way.
  =========================================================================== }
destructor TfrmMain.Destroy;
var
  i: Integer;
begin
  FDestroying := True;
  Application.RemoveAsyncCalls(Self);
  SaveSettings;
  ClearPropEditors;
  FPropProblems.Free;
  FToolProblems.Free;
  if FDocs <> nil then
    for i := 0 to FDocs.Count - 1 do
      if FDocs[i].View <> nil then
      begin
        FDocs[i].View.OnSelectionChange := nil;      { (freeing a document makes its view let go of the design; nothing of this window is wanted then) }
        FDocs[i].View.OnStatus := nil;
        FDocs[i].View.OnPosition := nil;
        FDocs[i].View.OnModified := nil;
        FDocs[i].View.OnToolChanged := nil;
        FDocs[i].View.OnDragEnd := nil;
        FDocs[i].View.OnZoomChanged := nil;
        FDocs[i].View.OnUndoChanged := nil;
        FDocs[i].View.OnObjectPlaced := nil;
        FDocs[i].View.OnContext := nil;
        FDocs[i].View.OnViewMoved := nil;
        FDocs[i].View.OnArcTypeChanged := nil;
      end;
  FDocs.Free;
  FWindowDocItems.Free;
  FRecentItems.Free;
  FFind.Free;      // each document detaches and frees its own view and design
  inherited Destroy;
end;

{ ===========================================================================
  TfrmMain.BuildLayout  (procedure)
  Parameters:  none
  Notes:
    Creates the run-time controls: ribbon page control, status bar, sheet tabs, symbol library
    panel, splitter and the drawing view, and connects their events.
  =========================================================================== }
procedure TfrmMain.BuildLayout;
var
  Panel: TPanel;
begin
{  FRibbon := TPageControl.Create(Self);
  FRibbon.Parent := Self;
  FRibbon.Align := alTop;
  FRibbon.Height := 108;
  FRibbon.TabPosition := tpTop;}

{  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := False;
  with FStatus.Panels.Add do begin Width := 620; Text := 'Ready'; end;
  with FStatus.Panels.Add do begin Width := 420; Text := ''; end;
  with FStatus.Panels.Add do begin Width := 300; Text := ''; end;}

{  FSheetTabs := TTabControl.Create(Self);
  FSheetTabs.Parent := Self;
  FSheetTabs.Align := alBottom;
  FSheetTabs.Height := 28;
  FSheetTabs.TabPosition := tpBottom;
  FSheetTabs.OnChange := @SheetTabChange;}

{  Panel := TPanel.Create(Self);
  Panel.Parent := Self;
  Panel.Align := alLeft;
  Panel.Width := 260;
  Panel.BevelOuter := bvNone;}
{  FLibPanel := TLibraryPanel.Create(Self);
  FLibPanel.Parent := pnlLeft;
  FLibPanel.Align := alClient;
  FLibPanel.OnPlace := @LibPlace;}

{  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := Self;
  FSplitter.Align := alLeft;
  FSplitter.Left := Panel.Width + 1;
  FSplitter.Width := 5;}
  FRibbon.Height := Scale96ToForm(108);

  FPlaceholder := CreateView;       // shown while no document is open
  FPlaceholder.Visible := True;
  { one tab per open document, above the drawing area }
  tcDocs := TDocTabStrip.Create(Self);
  tcDocs.Parent := pnlMain;
  tcDocs.Align := alTop;
  tcDocs.Images := frmSharedControls.ilDocTabs;
  tcDocs.Visible := False;
  tcDocs.OnChange := @DocTabChange;
  tcDocs.OnTabClose := @DocTabClose;
  { the rulers along the top and left of the drawing area: the top one under the tabs, the left one down the side; the view takes what is left }
  FRulerTop := TViewRuler.Create(Self, False);
  FRulerTop.Parent := pnlMain;
  FRulerTop.Align := alTop;
  FRulerTop.Top := tcDocs.Top + tcDocs.Height;
  FRulerTop.Height := Scale96ToForm(ViewRulerSize);
  FRulerTop.Thickness := FRulerTop.Height;
  FRulerTop.Visible := False;
  FRulerLeft := TViewRuler.Create(Self, True);
  FRulerLeft.Parent := pnlMain;
  FRulerLeft.Align := alLeft;
  FRulerLeft.Width := Scale96ToForm(ViewRulerSize);
  FRulerLeft.Thickness := FRulerLeft.Width;
  FRulerLeft.Visible := False;
  FRulerTop.Font.Name := 'Segoe UI';
  FRulerLeft.Font.Name := 'Segoe UI';
  FRulerTop.PopupMenu := pmRulerUnits;      // (the rulers are only there to click on while they are shown)
  FRulerLeft.PopupMenu := pmRulerUnits;
  tcDocs.PopupMenu := pmDocTabs;
  frameLibraryPanel.OnPlace := @LibPlace;
  frameLibraryPanel.OnPartPlace := @PartPlace;
  frameLibraryPanel.OnPartsFileChanged := @PartsFileChanged;
  frameLibraryPanel.OnChanged := @LibrariesChanged;
  frameLibraryPanel.OnSymbolCommand := @DoSymbolCommand;
  frameLibraryPanel.OnCopyTo := @DoSymbolCopyTo;
  frameLibraryPanel.OnQueryClose := @LibraryQueryClose;
  frameLibraryPanel.OnLibraries := @DoLibraries;
  BuildSymbolMenu;
  mSymbol.OnClick := @LibraryMenuOpen;
  mSpecial.OnClick := @HierarchyMenuOpen;
  mSheet.OnClick := @HierarchyMenuOpen;
  MakeSheetTabMarks;
  TCrackControl(tcSheetTabs).OnDblClick := @DoRenameSheet;      // double-click a sheet tab to rename the sheet     // a symbol chosen in the library tree starts placing it
end;

{ ------------------------------------------------------------------ the ribbon }

{ ===========================================================================
  TfrmMain.AddButton  (function)
  Parameters:
    ATab: TTabSheet - the ribbon tab
    var X: Integer - left position (advanced past the button)
    const ACaption: String - button text
    const AHint: String - tooltip
    AHandler: TNotifyEvent - click handler
    AWidth: Integer - button width
  Returns:
    TSpeedButton - the button
  Notes:
    Adds a ribbon button to a tab at the position X and moves X along for the next one.
  =========================================================================== }
function TfrmMain.AddButton(ATab: TTabSheet; var X: Integer; const ACaption, AHint: String;
  AHandler: TNotifyEvent; AWidth: Integer): TSpeedButton;
begin
  Result := TSpeedButton.Create(Self);
  Result.Parent := ATab;
  Result.SetBounds(X, 2, AWidth, BTN_H);
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.OnClick := AHandler;
  Result.Font.Size := 9;
  Inc(X, AWidth + 3);
end;

{ ===========================================================================
  TfrmMain.AddToolButton  (function)
  Parameters:
    ATab: TTabSheet - the ribbon tab
    var X: Integer - left position (advanced)
    ATool: TViewTool - the tool it starts
    const ACaption: String - button text
  Returns:
    TSpeedButton - the button
  Notes:
    Adds a ribbon button that selects a drawing tool; it joins the group of tool buttons so one
    stays pressed, and its Tag holds the tool number.
  =========================================================================== }
function TfrmMain.AddToolButton(ATab: TTabSheet; var X: Integer; ATool: TViewTool;
  const ACaption: String): TSpeedButton;
begin
  Result := AddButton(ATab, X, ACaption, ACaption, @DoToolButton, 62);
  Result.GroupIndex := 1;
  Result.AllowAllUp := True;
  Result.Tag := Ord(ATool);
  FToolButtons[ATool] := Result;
end;

{ ===========================================================================
  TfrmMain.SetToolButton  (function)
  Parameters:
    Button: TSpeedButton - which mouse button
    ATool: TViewTool - TViewTool
    MenuItem: TMenuItem
  Returns:
    boolean - boolean
  Notes:
    Sets everything AddToolButton does, but does not create the button; it joins the group of
    tool buttons so one stays pressed, and its Tag holds the tool number.
  =========================================================================== }
function TfrmMain.SetToolButton(Button: TSpeedButton; ATool: TViewTool;
  MenuItem: TMenuItem): boolean;
begin
  if Assigned(Button) then
    try
      Button.GroupIndex := 1;
      Button.AllowAllUp := true;      // (so UpdateRibbonState can release it: the buttons sit in different panels, where the toolkit's own group does not reach)
      Button.Tag := Ord(ATool);
      FToolButtons[ATool] := Button;
      if Assigned(MenuItem) then
        begin
            MenuItem.GroupIndex := 2;
            MenuItem.AutoCheck := false;      // the check follows the active tool (UpdateRibbonState), whichever way it was chosen
            MenuItem.Tag := Ord(ATool);
            MenuItem.RadioItem := true;
            FToolMenus[ATool] := MenuItem;
        end;
      Result := true;
    except
      Result := false;  // why though?
    end
  else
    Result := false;  // why though?
end;

{ ===========================================================================
  TfrmMain.Gap  (procedure)
  Parameters:
    var X: Integer - left position (advanced)
  Notes:
    Leaves a small gap between groups of ribbon buttons.
  =========================================================================== }
procedure TfrmMain.Gap(var X: Integer);
begin
  Inc(X, 12);
end;

{ ===========================================================================
  TfrmMain.BuildRibbon  (procedure)
  Parameters:  none
  Notes:
    Fills the ribbon: Home (undo, redo, snap, grid size, select, delete), Draw, Ladder, Library
    and View buttons, the grid-size menu, and the Properties tab's scrolling editor area.
  =========================================================================== }
procedure TfrmMain.BuildRibbon;
var
  X, i: Integer;
  Item: TMenuItem;
//  Sizes: array[0..6] of Double;
begin
//  FTabHome := FRibbon.AddTabSheet; FTabHome.Caption := 'Home';
//  FTabDraw := FRibbon.AddTabSheet; FTabDraw.Caption := 'Draw';
//  FTabLadder := FRibbon.AddTabSheet; FTabLadder.Caption := 'Ladder';
//  FTabLibrary := FRibbon.AddTabSheet; FTabLibrary.Caption := 'Library';
//  FTabView := FRibbon.AddTabSheet; FTabView.Caption := 'View';

  { Home: undo, redo, grid, select, delete }
  X := 804;
{  FBtnUndo := AddButton(FTabHome, X, 'Undo', 'Undo (Ctrl+Z)', @DoUndo);
  FBtnRedo := AddButton(FTabHome, X, 'Redo', 'Redo (Ctrl+Y)', @DoRedo);
  Gap(X);}
//  FBtnSnap := AddButton(FTabHome, X, 'Snap to grid', 'Turn snapping to the grid on or off', @DoToggleSnap, 84);
//  FBtnSnap.GroupIndex := 2;
//  FBtnSnap.AllowAllUp := True;
//  FBtnGrid := AddButton(FTabHome, X, 'Grid size', 'Change the grid size', @DoGridButton, 76);
  Gap(X);
//  AddToolButton(FTabHome, X, vtSelect, 'Select');
  sbHomeSelectOne.Tag := Ord(vtSelect);
  miSelect.Tag := Ord(vtSelect);
  { the Select button is one of the tool buttons: pressed while Select is the tool, released when another is chosen }
//  sbHomeSelectOne.OnClick := @DoToolButton;
//  sbHomeSelectOne.GroupIndex := 1;
//  sbHomeSelectOne.AllowAllUp := False;
  FToolButtons[vtSelect] := sbHomeSelectOne;
  FToolMenus[vtSelect] := miSelect;
  { the two Select buttons (Home and Draw ribbons) have groups of their own, so the draw tool last chosen stays pressed while Select is the tool }
  sbHomeSelectOne.GroupIndex := 8; sbHomeSelectOne.AllowAllUp := True;
  sbDrawSelect.GroupIndex := 9; sbDrawSelect.AllowAllUp := True;      // (Down is set by UpdateRibbonState; a click on it is put right in DoToolButton)
  sbDrawSelect.Tag := Ord(vtSelect);
//  AddButton(FTabHome, X, 'Delete', 'Delete the selection (Del)', @DoDelete);
//  AddButton(FTabHome, X, 'Select all', 'Select everything (Ctrl+A)', @DoSelectAll);
//  Gap(X);
//  AddButton(FTabHome, X, 'Rotate left', 'Rotate the selection left (Ctrl+L)', @DoRotateLeft, 84);
//  AddButton(FTabHome, X, 'Rotate right', 'Rotate the selection right (Ctrl+R)', @DoRotateRight, 88);
//  AddButton(FTabHome, X, 'Flip', 'Flip the selection left to right', @DoFlip, 56);
//  AddButton(FTabHome, X, 'To front', 'Bring the selection to the front', @DoBringToFront, 70);
//  AddButton(FTabHome, X, 'To back', 'Send the selection to the back', @DoSendToBack, 70);
//  Gap(X);
//  AddButton(FTabHome, X, 'Rename sheet', 'Rename the current sheet (or double-click its tab)', @DoRenameSheet, 90);
//  AddButton(FTabHome, X, 'Remove sheet', 'Remove the current sheet', @DoRemoveSheet, 90);
//  AddButton(FTabHome, X, 'Sheet <', 'Move the current sheet left', @DoMoveSheetLeft, 60);
//  AddButton(FTabHome, X, 'Sheet >', 'Move the current sheet right', @DoMoveSheetRight, 60);
//  Gap(X);
//  AddButton(FTabHome, X, 'Close', 'Close this document (Ctrl+W)', @DoCloseDocument, 56);
//  AddButton(FTabHome, X, 'Next doc', 'Show the next open document (Ctrl+Tab)', @DoNextDocument, 70);
//  Gap(X);
//  AddButton(FTabHome, X, 'Design details', 'Title block, rulers, border and revisions of this sheet (Ctrl+D)', @DoDesignDetails, 100);
//  AddButton(FTabHome, X, 'Page setup', 'Paper size and orientation of this sheet', @DoPageSetup, 84);
{  Gap(X);
  AddButton(FTabHome, X, 'Cut', 'Cut the selection (Ctrl+X)', @DoCut, 56);
  AddButton(FTabHome, X, 'Copy', 'Copy the selection (Ctrl+C)', @DoCopy, 56);
  AddButton(FTabHome, X, 'Paste', 'Paste, then click to place (Ctrl+V)', @DoPaste, 56);
  AddButton(FTabHome, X, 'Duplicate', 'Copy and paste the selection (Ctrl+U)', @DoDuplicate, 76);}

  // check the default grid so size up button works.
  for i := 0 to pmGridSize.Items.Count - 2 do
    pmGridSize.Items[i].Checked := Abs(pmGridSize.Items[i].Tag / 100 - FView.GridMm) < 0.001;
  SyncGridSizeMenus;

  { Draw }
  X := 4;
//  AddToolButton(FTabDraw, X, vtWire, 'Wire');
  SetToolButton(sbDrawWiresWire, vtWire, miDrawWire);
//  AddToolButton(FTabDraw, X, vtLabel, 'Wire label');
  SetToolButton(sbDrawWiresWirelabel, vtLabel, miDrawLabel);
//  AddToolButton(FTabDraw, X, vtJunction, 'Junction');
  SetToolButton(sbDrawWiresJunction, vtJunction, miDrawJunction);
//  AddToolButton(FTabDraw, X, vtNoConnect, 'No connect');
  SetToolButton(sbDrawWiresNoConnect, vtNoConnect, miDrawWireNoCon);
//  AddToolButton(FTabDraw, X, vtPower, 'Power');
  SetToolButton(sbDrawWiresPower, vtPower, miDrawPower);
//  AddToolButton(FTabDraw, X, vtBus, 'Bus');
  SetToolButton(sbDrawWiresBus, vtBus, miDrawBus);
//  AddToolButton(FTabDraw, X, vtBusSlash, 'Bus slash');
  SetToolButton(sbDrawWiresBusSlash, vtBusSlash, miDrawBusSlash);
//  AddToolButton(FTabDraw, X, vtText, 'Text');
  SetToolButton(sbDrawWiresText, vtText, miDrawText);
  SetToolButton(sbDrawWiresSymbolText, vtSymbolText, miDrawSymbolText);
//  Gap(X);
//  AddToolButton(FTabDraw, X, vtLine, 'Line');
  SetToolButton(sbDrawShapesLine, vtLine, miDrawLine);
  SetToolButton(miDrawPin, vtPin, nil);      { (the Pin tool: its button is shown only while a symbol is being edited, UpdateSymbolMenu) }
//  AddToolButton(FTabDraw, X, vtPolygon, 'Polygon');
  SetToolButton(sbDrawShapesPoly, vtPolygon, miDrawPolygon);
//  AddToolButton(FTabDraw, X, vtRect, 'Rectangle');
  SetToolButton(sbDrawShapesRect, vtRect, miDrawRect);
//  AddToolButton(FTabDraw, X, vtCircle, 'Circle');
  SetToolButton(sbDrawShapesCircle, vtCircle, miDrawCircle);
//  AddToolButton(FTabDraw, X, vtArc, 'Arc');
  SetToolButton(sbDrawShapesArc, vtArc, miDrawArc);
//  AddToolButton(FTabDraw, X, vtNote, 'Note');
  SetToolButton(sbDrawShapesNote, vtNote, miDrawNote);
//  AddToolButton(FTabDraw, X, vtCloud, 'Cloud');
  SetToolButton(sbDrawShapesCloud, vtCloud, miDrawCloud);
//  Gap(X);
//  AddToolButton(FTabDraw, X, vtRulerH, 'Ruler ---');
  SetToolButton(sbDrawMeasureRulerH, vtRulerH, miDrawRulerH);
//  AddToolButton(FTabDraw, X, vtRulerV, 'Ruler |');
  SetToolButton(sbDrawMeasureRulerV, vtRulerV, miDrawRulerV);
//  AddToolButton(FTabDraw, X, vtMeasure, 'Measure A-B');
  SetToolButton(sbDrawmeasureRulerAB, vtMeasure, miDrawRulerAB);

  { Ladder }
//  X := 4;
//  AddToolButton(FTabLadder, X, vtLadder, 'Ladder rails');
  SetToolButton(sbDrawLadderAdd, vtLadder, miLadderRails);
//  Gap(X);
//  AddToolButton(FTabLadder, X, vtXRefLine, 'Line link');
  SetToolButton(sbDrawLadderLink, vtXRefLine, miDrawRefLine);
//  AddToolButton(FTabLadder, X, vtXRefContacts, 'Contacts link');
  SetToolButton(sbDrawLadderContact, vtXRefContacts, miDrawContact);
  SetToolButton(sbDrawLadderRungs, vtRungs, miLadderRungs);

  { Library }
//  X := 4;
//  AddButton(FTabLibrary, X, 'Open library', 'Open a .TCLib symbol library', @DoOpenLibrary, 88);
//  AddButton(FTabLibrary, X, 'Place symbol', 'Place the selected symbol', @DoPlaceSymbol, 88);

  { View }
{  X := 4;
  AddButton(FTabView, X, 'Zoom in', 'Zoom in', @DoZoomIn);
  AddButton(FTabView, X, 'Zoom out', 'Zoom out', @DoZoomOut);
  AddButton(FTabView, X, 'Fit page', 'Show the whole page', @DoZoomFit);
  AddButton(FTabView, X, '100%', 'Actual size', @DoZoom100);}
  Gap(X);
//  AddButton(FTabView, X, 'Show grid', 'Show or hide the grid dots', @DoToggleGrid, 76);
  AddButton(FTabView, X, rsAddSheet, rsAddASheetToThe, @DoAddSheet, 76);

  { Properties: filled in from the selection }
  FPropProblems := TStringList.Create;
  FToolProblems := TStringList.Create;
  RegisterAllPropFrames;
  FPropTimer := TTimer.Create(Self);
  FPropTimer.Enabled := False;
  FPropTimer.Interval := PropSpinDelay;
  FPropTimer.OnTimer := @PropTimerTick;
  FPropLabel := lbPropsProperties;      // the panel plPropsProperties holds the editors; this label (at its foot) says what is selected
  FPropLabel.Caption := rsNothingSelected;
  FPropLabel.Font.Style := [fsBold];
  FPropLabel.Hint := rsWhatIsSelectedTheProperties;
  FPropLabel.ShowHint := True;
  SizePropsPanel(0);

  { set default look }
  FDetailsDrop.edSheetDetailsCols.Text := '';
  FDetailsDrop.edSheetDetailsRows.Text := '';
  FDetailsDrop.edSheetDetailsMargin.Text := '';
  DoDesignDetailsRuler(Self);
  DoDesignDetailsBorder(Self);
end;

{ ===========================================================================
  TfrmMain.UpdateRibbonState  (procedure)
  Parameters:  none
  Notes:
    Brings ribbon buttons in line with the program: undo / redo enabled and their hints, snap
    toggle, grid size caption, and which tool button is pressed.
  =========================================================================== }
procedure TfrmMain.UpdateRibbonState;
var
  T: TViewTool;
begin
  sbHomeEditUndo.Enabled := (FView.Undo <> nil) and FView.Undo.CanUndo;
  sbHomeEditRedo.Enabled := (FView.Undo <> nil) and FView.Undo.CanRedo;
  if (FView.Undo <> nil) and FView.Undo.CanUndo then
    sbHomeEditUndo.Hint := Format(rsUndo, [FView.Undo.UndoCaption])
  else
    sbHomeEditUndo.Hint := rsUndoCtrlZ;
  if (FView.Undo <> nil) and FView.Undo.CanRedo then
    sbHomeEditRedo.Hint := Format(rsRedo, [FView.Undo.RedoCaption])
  else
    sbHomeEditRedo.Hint := rsRedoCtrlY;
  sbViewGridSnapTo.Down := FView.SnapEnabled;
  mPartsList.Enabled := FDesign <> nil;
  mSymbolBom.Enabled := FDesign <> nil;
  mSymbolData.Enabled := FDesign <> nil;
  mExportWires.Enabled := FDesign <> nil;
  mInsertContactNO.Enabled := FDesign <> nil;
  mInsertContactNC.Enabled := FDesign <> nil;
  mInsertContactFree.Enabled := FDesign <> nil;
  mDupRefs.Enabled := FDesign <> nil;
  mNetList.Enabled := FDesign <> nil;
  mCheckRules.Enabled := FDesign <> nil;
  mVhdlCheck.Enabled := FDesign <> nil;
  mAnnotate.Enabled := FDesign <> nil;
  mPrint.Enabled := FDesign <> nil;
  mPrintPreview.Enabled := FDesign <> nil;
  mPageSetup.Enabled := FDesign <> nil;
  mSpice.Enabled := FDesign <> nil;
  mVhdl.Enabled := FDesign <> nil;
  if FView.Sheet <> nil then
    sbViewGridSize.Caption := Format(rsGrid, [LengthText(FView.GridMm, FView.Sheet.Options.Units)])
  else
    sbViewGridSize.Caption := Format(rsGrid, [LengthText(FView.GridMm, EditDefaults.Units)]);
  for T := Low(TViewTool) to High(TViewTool) do
  begin
    { only the button of the tool in use is pressed (none of the draw buttons while Select is the tool: its own buttons are).
      The toolkit's group only reaches buttons on the same panel, so the others are released here }
    if (FToolButtons[T] <> nil) and (T <> vtSelect) then
      FToolButtons[T].Down := T = FView.Tool;
    if FToolMenus[T] <> nil then
      FToolMenus[T].Checked := T = FView.Tool;     // the Insert menu's tools are one group over all its submenus
  end;
  miExportImage.Enabled := FDesign <> nil;
  sbHomeSelectOne.Down := FView.Tool = vtSelect;
  sbDrawSelect.Down := FView.Tool = vtSelect;
  UpdateToolPanel;           // the Properties panel of the draw tool in use
  UpdateRibbonFromView;      // the rulers and border of this sheet
  UpdatePositionBar;         // the grid size, snap and units of the Position bar
  UpdateRepeatMenu;          // the Repeat Directions of this design
  UpdateSymbolMenu;          // the symbol editor's commands
end;

{ ------------------------------------------------------------------ properties on the ribbon }

{ ===========================================================================
  DisconnectEvents  (procedure)
  Parameters:
    AComponent: TComponent
  Notes:
    Sets every event (OnClick, OnChange, OnExit ...) of the component and of everything it owns
    to nil, so that a control that lives a little longer (it is freed when the event being
    handled is over) cannot call the main form's handlers again, which would act on the editors
    that replaced it.
  =========================================================================== }
procedure DisconnectEvents(AComponent: TComponent);
var
  List: PPropList;
  N, I: Integer;
  NoMethod: TMethod;
begin
  NoMethod.Code := nil;
  NoMethod.Data := nil;
  N := GetPropList(AComponent, List);
  if List <> nil then
  begin
    try
      for I := 0 to N - 1 do
        if List^[I]^.PropType^.Kind = tkMethod then
          try
            SetMethodProp(AComponent, List^[I], NoMethod);
          except
            // (a read-only event: left as it is)
          end;
    finally
      FreeMem(List);
    end;
  end;
  for I := 0 to AComponent.ComponentCount - 1 do
    DisconnectEvents(AComponent.Components[I]);
end;

{ ===========================================================================
  TfrmMain.ClearPropEditors  (procedure)
  Parameters:  none
  Notes:
    Removes all property editors from the Properties tab.
  =========================================================================== }
procedure TfrmMain.ClearPropEditors;
var
  i: Integer;
  Fr: TFrame;
begin
  FPropTimer.Enabled := False;      // (a number box waiting to be applied goes with the editors)
  FSpinPending := nil;
  if FPropFrame <> nil then
  begin
    SetLength(FProps, 0);           // (the editors are the frame's: they go with it)
    SetLength(FPropBind, 0);
    { not freed here and now: this can run inside an event of the frame's own boxes (a click on the sheet takes the focus from the text box, whose
      exit event can end in a new selection), and a control freed under its own event is an access violation when the event returns; the frame is
      taken off the panel at once and the application frees it when the event is over }
    Fr := FPropFrame;
    FPropFrame := nil;
    DisconnectEvents(Fr);
    Fr.Visible := False;
    Fr.Parent := nil;
    Application.ReleaseComponent(Fr);
  end;
  for i := High(FProps) downto 0 do
  begin
    FProps[i].Control.Free;
  end;
  SetLength(FProps, 0);
  i := plPropsProperties.ControlCount - 1;      // the captions (everything but the label at the foot)
  while i >= 0 do
  begin
    if plPropsProperties.Controls[i] <> lbPropsProperties then
      plPropsProperties.Controls[i].Free;
    Dec(i);
  end;
end;

{ ===========================================================================
  HexOfColor  (function)
  Parameters:
    C: TColor - the color
  Returns:
    String - six hex digits
  Notes:
    Converts a Lazarus color to RRGGBB text for properties.
  =========================================================================== }
function HexOfColor(C: TColor): String;
var
  V: Integer;
begin
  V := ColorToRGB(C);
  Result := IntToHex(V and $FF, 2) + IntToHex((V shr 8) and $FF, 2) + IntToHex((V shr 16) and $FF, 2);
end;

{ ===========================================================================
  ColorOfHex  (function)
  Parameters:
    const S: String - six hex digits
  Returns:
    TColor - the color
  Notes:
    Converts RRGGBB text to a Lazarus color.
  =========================================================================== }
function ColorOfHex(const S: String): TColor;
var
  V: Integer;
begin
  V := StrToIntDef('$' + S, 0);
  Result := TColor(((V shr 16) and $FF) or (V and $FF00) or ((V and $FF) shl 16));
end;

{ ===========================================================================
  TfrmMain.FrameOwnsCaption  (function)
  Parameters:
    AFrame: TFrame
  Returns:
    Boolean
  Notes:
    Then the label the program puts at the foot of the panel is not shown as well: the frame's
    caption says what the panel is.
  =========================================================================== }
function TfrmMain.FrameOwnsCaption(AFrame: TFrame): Boolean;
begin
  Result := (AFrame is TfmPropertyBase) and TfmPropertyBase(AFrame).lbCaption.Visible;
end;

{ ===========================================================================
  TfrmMain.FillDropAct  (function)
  Parameters:
    const AAct: String - text
  Returns:
    String
  Notes:
    For the self-test script: turns the wheel and presses the keys on the menu the Fill button
    dropped down, through the handlers a person's wheel and keys run.
  =========================================================================== }
function TfrmMain.FillDropAct(const AAct: String): String;
var
  Handled: Boolean;
  Key: Word;
begin
  Result := 'visible=0';
  if FFillDrop = nil then
    Exit;
  Handled := False;
  Key := 0;
  if AAct = 'wheel-up' then
    FFillDrop.MouseWheel(FFillDrop, [], 120, Point(0, 0), Handled)
  else if AAct = 'wheel-down' then
    FFillDrop.MouseWheel(FFillDrop, [], -120, Point(0, 0), Handled)
  else if AAct = 'up' then
    Key := VK_UP
  else if AAct = 'down' then
    Key := VK_DOWN
  else if AAct = 'home' then
    Key := VK_HOME
  else if AAct = 'end' then
    Key := VK_END
  else if AAct = 'enter' then
    Key := VK_RETURN
  else if AAct = 'esc' then
    Key := VK_ESCAPE
  else if AAct = 'close' then
    FFillDrop.Close
  else if Copy(AAct, 1, 6) = 'color ' then
    FFillDrop.ColorChosen(ColorOfHex(Trim(Copy(AAct, 7, MaxInt))));      { (what the color dialog gives back) }
  if Key <> 0 then
    FFillDrop.PressKey(Key, []);
  Result := Format('visible=%d sel=%d choice=%d color=%s', [Ord(FFillDrop.Visible), FFillDrop.Selected, FFillDrop.Choice, HexOfColor(FFillDrop.Color)]);
end;

{ ===========================================================================
  TfrmMain.FillDropForm  (function)
  Parameters:  none
  Returns:
    TForm
  Notes:
    For the self-test script, which takes a picture of it.
  =========================================================================== }
function TfrmMain.FillDropForm: TForm;
begin
  Result := FFillDrop;
end;

{ ===========================================================================
  TfrmMain.FrameGlyph  (function)
  Parameters:
    ATool: Boolean - flag
    const AName: String - the name
  Returns:
    String
  Notes:
    For the self-test script: counts the pixels of the picture on the Fill button (the outline
    is black, the box white, the fill another color).
  =========================================================================== }
function TfrmMain.FrameGlyph(ATool: Boolean; const AName: String): String;
var
  Fr: TFrame;
  C: TComponent;
  G: TBitmap;
  X, Y, Black, White, Ink: Integer;
  Px, InkColor: TColor;
begin
  Result := '(none)';
  if ATool then
    Fr := FToolFrame
  else
    Fr := FPropFrame;
  if Fr = nil then
    Exit;
  C := Fr.FindComponent(AName);
  if not IsFillButton(C) then
    Exit;
  G := TSpeedButton(C).Glyph;
  Black := 0; White := 0; Ink := 0; InkColor := clNone;
  for Y := 0 to G.Height - 1 do
    for X := 0 to G.Width - 1 do
    begin
      Px := G.Canvas.Pixels[X, Y];
      if Px = clBlack then
        Inc(Black)
      else if Px = clWhite then
        Inc(White)
      else
      begin
        Inc(Ink);
        InkColor := Px;
      end;
    end;
  Result := Format('size=%dx%d black=%d white=%d ink=%d inkcolor=%s', [G.Width, G.Height, Black, White, Ink, HexOfColor(InkColor)]);
end;

{ ===========================================================================
  TfrmMain.FrameComboItems  (function)
  Parameters:
    ATool: Boolean - flag
    const AName: String - the name
  Returns:
    String
  Notes:
    For the self-test script (a list that holds an item twice shows up here).
  =========================================================================== }
function TfrmMain.FrameComboItems(ATool: Boolean; const AName: String): String;
var
  Fr: TFrame;
  C: TComponent;
begin
  Result := '(none)';
  if ATool then
    Fr := FToolFrame
  else
    Fr := FPropFrame;
  if Fr = nil then
    Exit;
  C := Fr.FindComponent(AName);
  if C is TComboBox then
    Result := TComboBox(C).Items.DelimitedText;
end;

{ ===========================================================================
  TfrmMain.FrameLabelsItself  (function)
  Parameters:
    AFrame: TFrame
  Returns:
    Boolean
  Notes:
    A frame either shows lbCaption or (lbCaption hidden) puts a caption on each of its panels,
    as the Note frame does with Font and Note. In both cases the label the program adds at the
    foot of the panel is not wanted.
  =========================================================================== }
function TfrmMain.FrameLabelsItself(AFrame: TFrame): Boolean;
begin
  Result := AFrame is TfmPropertyBase;
end;

{ ===========================================================================
  TfrmMain.ToolFrameKey  (function)
  Parameters:
    ATool: TViewTool
  Returns:
    String
  Notes:
    wire, bus, line, polygon, arc, rect, circle, note, cloud, measure, text, label or power.
  =========================================================================== }
function TfrmMain.ToolFrameKey(ATool: TViewTool): String;
begin
  case ATool of
    vtWire: Result := 'wire';
    vtBus: Result := 'bus';
    vtLine: Result := 'line';
    vtPolygon: Result := 'polygon';
    vtArc: Result := 'arc';
    vtRect: Result := 'rect';
    vtCircle: Result := 'circle';
    vtNote: Result := 'note';
    vtCloud: Result := 'cloud';
    vtMeasure: Result := 'measure';
    vtText: Result := 'text';
    vtSymbolText: Result := 'symboltext';
    vtLabel: Result := 'label';
    vtPower: Result := 'power';
    vtPlace: Result := 'method';
    vtPin: Result := 'pin';
  else
    Result := '';
  end;
end;

{ ===========================================================================
  TfrmMain.SelectionFrameKey  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    A selection of one kind of object (several wires, say) uses the frame of that kind.
  =========================================================================== }
function TfrmMain.SelectionFrameKey: String;
var
  i: Integer;
  K: String;
begin
  Result := '';
  if (FView = nil) or (FView.SelectedCount = 0) then
    Exit;
  Result := PropFrameKeyOfObject(FView.SelectedObject(0));
  for i := 1 to FView.SelectedCount - 1 do
  begin
    K := PropFrameKeyOfObject(FView.SelectedObject(i));
    if K <> Result then
      Exit('');
  end;
end;

{ ===========================================================================
  TfrmMain.ShowFrame  (function)
  Parameters:
    AParent: TWinControl
    AOwner: TComponent
    const AKey: String - text
    const Defs: TPropDefArray
    ATagBase: Integer - whole number
    var Items: TPropEditorArray - in/out: changed by the call
    var AFrame: TFrame - in/out: changed by the call
    var ABind: TFrameBindings - in/out: changed by the call
    AProblems: TStringList
  Returns:
    Integer
  Notes:
    Makes the registered frame of the designer in place of BuildEditors: the frame fills the
    panel (above the label at its foot), its editors are found by their names
    (QPropFrame.BindPropFrame), and each is given what BuildEditors gives its editors: a Tag,
    the event that applies a change, the choices of a drop-down.
  =========================================================================== }
function TfrmMain.ShowFrame(AParent: TWinControl; AOwner: TComponent; const AKey: String; const Defs: TPropDefArray; ATagBase: Integer; var Items: TPropEditorArray;
  var AFrame: TFrame; var ABind: TFrameBindings; AProblems: TStringList): Integer;
var
  Cls: TPropFrameClass;
  i, Groups: Integer;      // (Groups: counts the blank items)
  C: TControl;
  Sl: TStringList;
  Cb: TComboBox;
begin
  Result := -1;
  Cls := PropFrameFor(AKey);
  if Cls = nil then
    Exit;
  AProblems.Clear;
  AFrame := Cls.Create(AOwner);
  Result := AFrame.Width;      { the width it was designed with, before it is made to fill the panel }
  AFrame.Parent := AParent;
  AFrame.Align := alClient;
  if AFrame is TfmPropertyBase then
    TfmPropertyBase(AFrame).AfterCreate;      { (the frame's own set-up: the font list, the pictures of a list) }
  BindPropFrame(AFrame, Defs, PropFrameAliases(AKey), ABind, AProblems);
  if AFrame is TfmSymbols then
    HookSymbolFrame(TfmSymbols(AFrame));
  SetLength(Items, Length(ABind));
  for i := 0 to High(ABind) do
  begin
    C := ABind[i].Control;
    Items[i].Def := ABind[i].Def;
    Items[i].Control := C;
    Items[i].Mixed := False;
    Items[i].Mode := ABind[i].Mode;
    Items[i].OldClick := nil;
    C.Tag := ATagBase + i;
    if C is TCustomFloatSpinEdit then
    begin
      TCustomFloatSpinEdit(C).OnChange := @PropNumberChange;
      if C is TSpinEdit then
        TSpinEdit(C).OnEditingDone := @PropNumberDone
      else if C is TFloatSpinEdit then
        TFloatSpinEdit(C).OnEditingDone := @PropNumberDone;
    end
    else if C is TColorButton then
      begin
        TColorButton(C).OnColorChanged := @PropColorChanged;
        TColorButton(C).OnClick := @ColorButtonClick;
      end
    else if C is TComboBox then
    begin
      Cb := TComboBox(C);
      if ABind[i].Def.Kind = pkChoice then
      begin
        { the list is the choices of the property, unless the frame made one of its own of the right length (blank items drawn as pictures, say) }
        Sl := TStringList.Create;
        try
          Sl.Delimiter := '|'; Sl.StrictDelimiter := True; Sl.DelimitedText := ABind[i].Def.Choices;
          if Cb.Items.Count <> Sl.Count then
          begin
            if Assigned(Cb.OnDrawItem) then
            begin
              Sl.Clear;
              for Groups := 1 to ChoiceCount(ABind[i].Def.Choices) do Sl.Add('');      { (the frame draws pictures, not words) }
            end;
            Cb.Items.Assign(Sl);
          end;
        finally
          Sl.Free;
        end;
        if (ABind[i].Def.Choices = DashChoices) and not Assigned(Cb.OnDrawItem) then
        begin
          Cb.Style := csOwnerDrawFixed;
          Cb.ItemHeight := ilListBoxImages.Height;
          Cb.OnDrawItem := @LineStyleDrawItem;
        end;
        Cb.OnSelect := @PropChoiceChange;
      end
      else
      begin
        Cb.OnSelect := @PropComboDone;      { a font name or a size: chosen from the list or typed }
        Cb.OnCloseUp := @PropComboDone;     { (the list closed with Enter after typing, which selects nothing) }
        Cb.OnKeyDown := @PropComboKeyDown;
        Cb.OnExit := @PropComboDone;
      end;
    end
    else if C is TRadioButton then
      TRadioButton(C).OnClick := @PropBoolClick      { (one of the radio buttons of a choice) }
    else if C is TCheckBox then
    begin
      TCheckBox(C).AllowGrayed := False;
      TCheckBox(C).OnClick := @PropBoolClick;
    end
    else if (C is TSpeedButton) and (ABind[i].Mode = bmDrop) then
      TSpeedButton(C).OnClick := @PropBusClick      { (the phases of the bus: the picture, and the panel it drops down) }
    else if (C is TSpeedButton) and (ABind[i].Mode = bmFill) then
      TSpeedButton(C).OnClick := @PropFillClick      { (the whole fill editor: the picture of the fill, and the menu it drops down) }
    else if C is TSpeedButton then
    begin
      Items[i].OldClick := TSpeedButton(C).OnClick;
      if ABind[i].Mode = bmNormal then
      begin
        if TSpeedButton(C).GroupIndex = 0 then
          TSpeedButton(C).GroupIndex := 100 + i;      { a button that stays down }
        TSpeedButton(C).AllowAllUp := True;
      end;
      TSpeedButton(C).OnClick := @PropSpeedClick;
    end
    else if C is TEdit then
      begin
        TEdit(C).OnEditingDone := @PropEditDone;
        TEdit(C).OnKeyDown := @PropEditKeyDown;
        TEdit(C).OnChange := @PropEditChange;
      end;
  end;
end;

{ ===========================================================================
  TfrmMain.PropFramesChanged  (procedure)
  Parameters:  none
  Notes:
    The registered frames changed (the self-test script registers some): make the tool's panel
    and the selection's editors again.
  =========================================================================== }
procedure TfrmMain.PropFramesChanged;
begin
  FreeToolPanel;
  UpdateToolPanel;
  RebuildProps;
end;

{ ===========================================================================
  TfrmMain.ControlShown  (function)
  Parameters:
    AControl: TControl
  Returns:
    String
  Notes:
    For the self-test script.
  =========================================================================== }
function TfrmMain.ControlShown(AControl: TControl): String;
begin
  if AControl is TCustomFloatSpinEdit then
  begin
    if TCustomFloatSpinEdit(AControl).ValueEmpty then
      Result := ''
    else
      Result := FloatText(TCustomFloatSpinEdit(AControl).Value);
  end
  else if AControl is TColorButton then
    Result := HexOfColor(TColorButton(AControl).ButtonColor)
  else if AControl is TComboBox then
    Result := 'item=' + IntToStr(TComboBox(AControl).ItemIndex) + ' text=' + TComboBox(AControl).Text
  else if AControl is TCheckBox then
    Result := IntToStr(Ord(TCheckBox(AControl).Checked))
  else if AControl is TRadioButton then
    Result := IntToStr(Ord(TRadioButton(AControl).Checked))
  else if IsFillButton(AControl) or IsBusButton(AControl) then
    Result := 'glyph=' + IntToStr(TSpeedButton(AControl).Glyph.Width) + 'x' + IntToStr(TSpeedButton(AControl).Glyph.Height) + ' ' + AControl.Hint
  else if AControl is TSpeedButton then
    Result := 'down=' + IntToStr(Ord(TSpeedButton(AControl).Down)) + ' image=' + IntToStr(TSpeedButton(AControl).ImageIndex)
  else if AControl is TCustomEdit then
    Result := TCustomEdit(AControl).Text
  else
    Result := '';
end;

{ ===========================================================================
  TfrmMain.FrameAct  (function)
  Parameters:
    ATool: Boolean - flag
    const AName: String - the name
    const AAction: String - text
    const AValue: String - the value
  Returns:
    Boolean
  Notes:
    For the self-test script: does to a control of a frame what a person does with the mouse and
    keyboard, so the events the program attached run.
  =========================================================================== }
function TfrmMain.FrameAct(ATool: Boolean; const AName, AAction, AValue: String): Boolean;
var
  Fr: TFrame;
  C: TComponent;
  Kc: Word;
begin
  Result := False;
  if ATool then
    Fr := FToolFrame
  else
    Fr := FPropFrame;
  if Fr = nil then
    Exit;
  C := Fr.FindComponent(AName);
  if not (C is TControl) then
    Exit;
  if (AAction = 'click') and (C is TRadioButton) then
  begin
    TRadioButton(C).Checked := True;      { (a click ticks it, and clears the others of its group, then the event) }
    TControlCracker(C).Click;
    Result := True;
  end
  else if (AAction = 'click') and (C is TCheckBox) then
  begin
    TCheckBox(C).Checked := not TCheckBox(C).Checked;      { (a mouse click changes the state, then the event) }
    TControlCracker(C).Click;
    Result := True;
  end
  else if (AAction = 'click') and (C is TSpeedButton) then
  begin
    if (FBusDrop <> nil) and IsBusButton(C) then
      FBusDrop.ForgetClose;
    if (FFillDrop <> nil) and IsFillButton(C) then
      FFillDrop.ForgetClose;      { (a person's second click comes later than the script's) }
    if TSpeedButton(C).GroupIndex <> 0 then
      TSpeedButton(C).Down := not TSpeedButton(C).Down;      { (a mouse click presses it before the event) }
    TControlCracker(C).Click;
    Result := True;
  end
  else if (AAction = 'pick') and IsFillButton(C) then
  begin
    { a style (and color) chosen on the Fill menu: 'pick 4' or 'pick 4 #FF0000' }
    FFillTag := C.Tag;
    if Pos(' ', AValue) > 0 then
      FillPicked(nil, StrToIntDef(Copy(AValue, 1, Pos(' ', AValue) - 1), 0), ColorOfHex(Trim(Copy(AValue, Pos(' ', AValue) + 1, MaxInt))))
    else
      FillPicked(nil, StrToIntDef(AValue, 0), ColorOfHex(FillColorOf(C.Tag)));
    Result := True;
  end
  else if (AAction = 'choose') and (C is TComboBox) then
  begin
    TComboBox(C).ItemIndex := StrToIntDef(AValue, -1);
    if Assigned(TComboBox(C).OnSelect) then
      TComboBox(C).OnSelect(C);
    Result := True;
  end
  else if (AAction = 'enter') and (C is TComboBox) then
  begin
    { the text typed in the box and Enter pressed, with the focus still in the box (no Exit) }
    TComboBox(C).Text := AValue;
    if Assigned(TComboBox(C).OnKeyDown) then
    begin
      Kc := 13;
      TComboBox(C).OnKeyDown(C, Kc, []);
    end;
    Result := True;
  end
  else if (AAction = 'text') and (C is TComboBox) then
  begin
    TComboBox(C).Text := AValue;
    if Assigned(TComboBox(C).OnExit) then
      TComboBox(C).OnExit(C);
    Result := True;
  end
  else if (AAction = 'type') and (C is TEdit) then
  begin
    TEdit(C).Text := AValue;       // (the box's OnChange runs, as with each keystroke)
    Result := True;
  end
  else if (AAction = 'text') and (C is TEdit) then
  begin
    TEdit(C).Text := AValue;
    if Assigned(TEdit(C).OnEditingDone) then
      TEdit(C).OnEditingDone(C);
    Result := True;
  end
  else if (AAction = 'text') and (C is TSpinEdit) then
  begin
    TSpinEdit(C).Value := StrToIntDef(AValue, TSpinEdit(C).Value);       // a number typed and committed
    if Assigned(TSpinEdit(C).OnEditingDone) then
      TSpinEdit(C).OnEditingDone(C);
    Result := True;
  end
  else if (AAction = 'color') and (C is TColorButton) then
  begin
    TColorButton(C).ButtonColor := ColorOfHex(AValue);
    if Assigned(TColorButton(C).OnColorChanged) then
      TColorButton(C).OnColorChanged(C);
    Result := True;
  end;
end;

{ ===========================================================================
  IsBound  (function)
  Parameters:
    const ABind: TFrameBindings
    AControl: TControl
  Returns:
    Boolean
  Notes:
    For FrameInfo: a control that was linked and is disabled by the frame itself is not one that
    BindPropFrame disabled.
  =========================================================================== }
function IsBound(const ABind: TFrameBindings; AControl: TControl): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(ABind) do
    if ABind[i].Control = AControl then
      Exit(True);
end;

{ ===========================================================================
  TfrmMain.FrameInfo  (function)
  Parameters:
    ATool: Boolean - flag
  Returns:
    TStringArray
  Notes:
    For the self-test script.
  =========================================================================== }
function TfrmMain.FrameInfo(ATool: Boolean): TStringArray;
var
  Fr: TFrame;
  Problems: TStringList;
  Bind: TFrameBindings;
  i: Integer;
  C: TControl;
begin
  SetLength(Result, 0);
  if ATool then begin
    Fr := FToolFrame;
    Problems := FToolProblems;
    Bind := FToolBind;
  end else begin
    Fr := FPropFrame;
    Problems := FPropProblems;
    Bind := FPropBind;
  end;
  if Fr = nil then
  begin
    SetLength(Result, 1);
    Result[0] := 'none';
    Exit;
  end;
  SetLength(Result, 1);
  Result[0] := Fr.ClassName + ' width=' + IntToStr(Fr.Parent.ClientWidth) + ' align=' + IntToStr(Ord(Fr.Align)) + ' problems=' + IntToStr(Problems.Count)
    + ' captionvisible=' + IntToStr(Ord(FrameOwnsCaption(Fr)));
  { every editor that is bound, in the order of the bindings }
  for i := 0 to High(Bind) do
  begin
    C := Bind[i].Control;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := C.Name + ' ' + C.ClassName + ' ' + Bind[i].Def.Name + ' mode=' + IntToStr(Ord(Bind[i].Mode)) + ' visible=' + IntToStr(Ord(C.Visible and C.Parent.Visible))
      + ' enabled=' + IntToStr(Ord(C.Enabled)) + ' tag=' + IntToStr(C.Tag) + ' shown=[' + ControlShown(C) + ']';
  end;
  for i := 0 to Fr.ComponentCount - 1 do      { an editor named after a property the tool or selection has not got: hidden }
    if (Fr.Components[i] is TControl) and not TControl(Fr.Components[i]).Visible and (PropKeyOfControlName(TControl(Fr.Components[i]).Name) <> '') then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := TControl(Fr.Components[i]).Name + ' ' + Fr.Components[i].ClassName + ' ' + PropKeyOfControlName(TControl(Fr.Components[i]).Name) + ' hidden';
    end;
  for i := 0 to Fr.ComponentCount - 1 do      { an editor named after a property that could not be linked and was disabled }
    if (Fr.Components[i] is TControl) and not TControl(Fr.Components[i]).Enabled and (PropKeyOfControlName(TControl(Fr.Components[i]).Name) <> '')
      and not IsBound(Bind, TControl(Fr.Components[i])) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := TControl(Fr.Components[i]).Name + ' ' + Fr.Components[i].ClassName + ' ' + PropKeyOfControlName(TControl(Fr.Components[i]).Name) + ' disabled';
    end;
  for i := 0 to Problems.Count - 1 do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := 'PROBLEM ' + Problems[i];
  end;
end;

{ ===========================================================================
  TfrmMain.BuildEditors  (function)
  Parameters:
    APanel: TPanel
    const Defs: TPropDefArray
    ATagBase: Integer - whole number
    var Items: TPropEditorArray - in/out: changed by the call
  Returns:
    Integer
  Notes:
    Makes a caption and an editor (text box, number box, drop-down, check box or color button)
    for each property and places them: PropRowsPerColumn (two) to a column, the first row at 5,
    5 and the second at 5, 56 (36 pixel rows, a shorter control centred on the row), PropGap
    pixels between columns. The values are filled in by the caller.
  =========================================================================== }
function TfrmMain.BuildEditors(APanel: TPanel; const Defs: TPropDefArray; ATagBase: Integer; var Items: TPropEditorArray): Integer;
var
  i, Row, Col, X, LabW, CtlW, CtlH, RightEnd: Integer;
  Lab: TLabel;
  Ed: TEdit;
  Cb: TComboBox;
  Ck: TCheckBox;
  Bt: TColorButton;
  Si: TSpinEdit;
  Fl: TFloatSpinEdit;
  Sl: TStringList;
  W: array of Integer;      // the widest of each column (caption, gap and editor)
  Ctl: array of TControl;
  Cap: array of TLabel;
begin
  SetLength(Items, Length(Defs));
  SetLength(Ctl, Length(Defs));
  SetLength(Cap, Length(Defs));
  SetLength(W, (Length(Defs) + PropRowsPerColumn - 1) div PropRowsPerColumn);
  for i := 0 to High(W) do W[i] := 0;
  APanel.Canvas.Font.Assign(APanel.Font);
  { make the controls, with their sizes }
  for i := 0 to High(Defs) do
  begin
    Items[i].Def := Defs[i];
    Lab := TLabel.Create(APanel);
    Lab.Parent := APanel;
    Lab.AutoSize := False;
    Lab.Caption := Defs[i].Caption + ':';
    LabW := APanel.Canvas.TextWidth(Lab.Caption) + PropCaptionPad;
    Lab.SetBounds(0, 0, LabW, APanel.Canvas.TextHeight('Wg') + PropCaptionHeightPad);
    Cap[i] := Lab;
    case Defs[i].Kind of
      pkChoice:
        begin
          Cb := TComboBox.Create(APanel);
          Cb.Parent := APanel;
          Cb.Style := csDropDownList;
          if Defs[i].Choices = DashChoices then
          begin
            { any list of line styles (the choices are Solid, Dash, Dot, Dash-dot, Dash-dot-dot) shows them as pictures (ilListBoxImages: dash, dot, dash-dot, dash-dot-dot; Solid is drawn) }
            Cb.Style := csOwnerDrawFixed;
            Cb.ItemHeight := ilListBoxImages.Height;
            Cb.OnDrawItem := @LineStyleDrawItem;
          end;
          Sl := TStringList.Create;
          try
            Sl.Delimiter := '|'; Sl.StrictDelimiter := True; Sl.DelimitedText := Defs[i].Choices;
            Cb.Items.Assign(Sl);
          finally
            Sl.Free;
          end;
          Cb.Tag := ATagBase + i;
          Cb.OnChange := @PropChoiceChange;
          if Defs[i].Choices = DashChoices then
            Cb.SetBounds(0, 0, ilListBoxImages.Width + PropLineStyleExtra, PropEditHeight)
          else
            Cb.SetBounds(0, 0, PropComboWidth, PropEditHeight);
          Items[i].Control := Cb;
        end;
      pkBool:
        begin
          Ck := TCheckBox.Create(APanel);
          Ck.Parent := APanel;
          Ck.AllowGrayed := False;
          Ck.Tag := ATagBase + i;
          Ck.OnClick := @PropBoolClick;
          Ck.SetBounds(0, 0, PropCheckWidth, PropCheckHeight);
          Items[i].Control := Ck;
        end;
      pkColor:
        begin
          Bt := TColorButton.Create(APanel);      { the standard color button: it shows the color and asks for another when pressed }
          Bt.Parent := APanel;
          Bt.BorderWidth := PropColorBorder;
          Bt.ButtonColorSize := PropColorSwatch;
          Bt.Tag := ATagBase + i;
          Bt.OnColorChanged := @PropColorChanged;
          Bt.OnClick := @ColorButtonClick;
          Bt.SetBounds(0, 0, PropColorWidth, PropEditHeight);
          Items[i].Control := Bt;
        end;
      pkInt:
        begin
          Si := TSpinEdit.Create(APanel);       { a whole number: a number box with arrows }
          Si.Parent := APanel;
          Si.MinValue := PropIntMin;
          Si.MaxValue := PropIntMax;
          Si.Increment := PropIntStep;
          Si.Tag := ATagBase + i;
          Si.OnChange := @PropNumberChange;
          Si.OnEditingDone := @PropNumberDone;
          Si.SetBounds(0, 0, PropNumWidth, PropEditHeight);
          Items[i].Control := Si;
        end;
      pkFloat:
        begin
          Fl := TFloatSpinEdit.Create(APanel);  { a fractional number: the same with decimals }
          Fl.Parent := APanel;
          Fl.DecimalPlaces := PropFloatDecimals;
          Fl.MinValue := PropFloatMin;
          Fl.MaxValue := PropFloatMax;
          Fl.Increment := PropFloatStep;
          Fl.Tag := ATagBase + i;
          Fl.OnChange := @PropNumberChange;
          Fl.OnEditingDone := @PropNumberDone;
          Fl.SetBounds(0, 0, PropNumWidth, PropEditHeight);
          Items[i].Control := Fl;
        end;
    else
      begin
        Ed := TEdit.Create(APanel);
        Ed.Parent := APanel;
        Ed.Tag := ATagBase + i;
        Ed.OnEditingDone := @PropEditDone;
        Ed.OnKeyDown := @PropEditKeyDown;
        Ed.OnChange := @PropEditChange;
        Ed.SetBounds(0, 0, PropTextWidth, PropEditHeight);
        Items[i].Control := Ed;
      end;
    end;
    Ctl[i] := Items[i].Control;
    Col := i div PropRowsPerColumn;
    if Cap[i].Width + PropPairGap + Ctl[i].Width > W[Col] then
      W[Col] := Cap[i].Width + PropPairGap + Ctl[i].Width;
  end;
  { place them: two rows (the first starts at 5, 5 and the second at 5, 56, in 36 pixel high rows); a control
    shorter than that is centred on the row's middle; PropGap pixels between the columns }
  X := PropLeft;
  RightEnd := X;
  for Col := 0 to High(W) do
  begin
    for Row := 0 to PropRowsPerColumn - 1 do
    begin
      i := Col * PropRowsPerColumn + Row;
      if i > High(Defs) then
        Break;
      CtlH := Ctl[i].Height;
      Cap[i].SetBounds(X, PropRowTop(Row) + (PropRowHeight - Cap[i].Height) div 2, Cap[i].Width, Cap[i].Height);
      CtlW := Ctl[i].Width;
      Ctl[i].SetBounds(X + Cap[i].Width + PropPairGap, PropRowTop(Row) + (PropRowHeight - CtlH) div 2, CtlW, CtlH);
    end;
    Inc(X, W[Col] + PropGap);
  end;
  if Length(W) > 0 then
    RightEnd := X - PropGap;
  if Length(Defs) = 0 then
    Result := 0
  else
    Result := RightEnd + PropLeft;
end;

{ ===========================================================================
  TfrmMain.RebuildProps  (procedure)
  Parameters:  none
  Notes:
    Rebuilds the Properties tab for the current selection: one editor per property the selected
    objects share (text box, drop-down, check box or color swatch), two per column, then fills
    in their values.
  =========================================================================== }
procedure TfrmMain.RebuildProps;
var
  Defs: TPropDefArray;
  Need: Integer;
begin
  FUpdatingProps := True;
  try
    ClearPropEditors;
    if FView.SelectedCount = 0 then
    begin
      FPropLabel.Caption := rsNothingSelected;
      FPropLabel.Visible := True;
      SizePropsPanel(0);
      pnlPropsSep.Visible := False;       { nothing to show: the separator and the panel are off the View ribbon }
      plPropsProperties.Visible := False;
      Exit;
    end;
    Defs := CommonProps(FView.SelectedList);
    pnlPropsSep.Left := 5000;             { alLeft controls line up by Left: the separator first (after Position), then the panel }
    plPropsProperties.Left := 5002;
    pnlPropsSep.Visible := True;          { the properties are shown: a 2 pixel separator and then the panel, at the right of the View ribbon }
    plPropsProperties.Visible := True;
    FPropLabel.Caption := DescribeSelection;
    Need := ShowFrame(plPropsProperties, nil, SelectionFrameKey, Defs, 0, FProps, FPropFrame, FPropBind, FPropProblems);
    FPropLabel.Visible := not FrameLabelsItself(FPropFrame);      { a frame labels itself (lbCaption, or a caption on each panel), so the form's label is not added }
    if FrameOwnsCaption(FPropFrame) then
      TfmPropertyBase(FPropFrame).lbCaption.Caption := FPropLabel.Caption;
    if Need >= 0 then
      SizePropsPanel(Need + (plPropsProperties.Width - plPropsProperties.ClientWidth))      { the frame as it was designed, and the panel's border }
    else
      SizePropsPanel(BuildEditors(plPropsProperties, Defs, 0, FProps));
  finally
    FUpdatingProps := False;
  end;
  ShowPropValues;
  if FAutoShowParams and (FPropFrame is TfmSymbols) then
    Application.QueueAsyncCall(@AutoShowSymbolList, 0);
end;

{ ===========================================================================
  TfrmMain.SizePropsPanel  (procedure)
  Parameters:
    ANeeded: Integer - whole number
  Notes:
    Gives plPropsProperties (the panel on the Properties ribbon that holds the editors) the
    width of the editors, or at least what the label at its foot (lbPropsProperties, which says
    what is selected) needs; the label is as wide as the panel.
  =========================================================================== }
procedure TfrmMain.SizePropsPanel(ANeeded: Integer);
var
  W: Integer;
begin
  lbPropsProperties.Canvas.Font.Assign(lbPropsProperties.Font);
  W := lbPropsProperties.Canvas.TextWidth(lbPropsProperties.Caption) + 2 * PropLeft + 4;
  if ANeeded > W then
    W := ANeeded;
  plPropsProperties.Width := W;
end;

{ ===========================================================================
  TfrmMain.FreeToolPanel  (procedure)
  Parameters:  none
  Notes:
    Removes the Properties panel (and its separator) of a draw tool from the Draw ribbon.
  =========================================================================== }
procedure TfrmMain.FreeToolPanel;
begin
  if FPropTimer <> nil then
    FPropTimer.Enabled := False;
  FSpinPending := nil;
  SetLength(FToolEditors, 0);
  SetLength(FToolBind, 0);
  FToolFrame := nil;           // (it goes with the panel)
  FreeAndNil(FToolPanel);      // (its label and editors go with it)
  FreeAndNil(FToolSep);
  FToolLabel := nil;
end;

{ ===========================================================================
  TfrmMain.UpdateToolPanel  (procedure)
  Parameters:  none
  Notes:
    While a draw tool is in use, the Draw ribbon ends with a separator and a panel captioned
    Properties that holds editors for what the tool draws (line colour, width and style; fill;
    font; label type ...), placed like the rest of the ribbon. Choosing Select, or a tool with
    nothing to choose, removes them. The values chosen are kept by the view and given to every
    new object.
  =========================================================================== }
procedure TfrmMain.UpdateToolPanel;
var
  Defs: TPropDefArray;
  Need, W: Integer;
begin
  if (FView = nil) or (FView.Sheet = nil) or (FView.Tool = vtSelect) then
  begin
    FreeToolPanel;
    Exit;
  end;
  Defs := FView.ToolPropDefs(FView.Tool);
  if Length(Defs) = 0 then
  begin
    FreeToolPanel;
    Exit;
  end;
  if (FToolPanel <> nil) and (FToolOf = FView.Tool) and ((FToolFrame <> nil) or (Length(FToolEditors) = Length(Defs))) then
  begin
    ShowToolPropValues;      // the same tool again
    Exit;
  end;
  FreeToolPanel;
  FToolOf := FView.Tool;
  FToolSep := TPanel.Create(Self);
  FToolSep.Caption := '';
  FToolSep.Width := 2;
  FToolSep.Align := alLeft;
  FToolSep.Left := 100000;      // (after everything else on the sheet)
  FToolSep.Parent := FTabDraw;
  FToolPanel := TPanel.Create(Self);
  FToolPanel.Caption := '';
  FToolPanel.BevelOuter := bvNone;
  FToolPanel.Align := alLeft;
  FToolPanel.Left := 100001;
  FToolPanel.Parent := FTabDraw;
  FToolLabel := TLabel.Create(FToolPanel);
  FToolLabel.Parent := FToolPanel;
  FToolLabel.Align := alBottom;
  FToolLabel.Alignment := taCenter;
  FToolLabel.Caption := rsProperties;
  FUpdatingProps := True;
  try
    Need := ShowFrame(FToolPanel, FToolPanel, ToolFrameKey(FView.Tool), Defs, TOOLPROP_BASE, FToolEditors, FToolFrame, FToolBind, FToolProblems);
    FToolLabel.Visible := not FrameLabelsItself(FToolFrame);
    if Need < 0 then
      Need := BuildEditors(FToolPanel, Defs, TOOLPROP_BASE, FToolEditors);
  finally
    FUpdatingProps := False;
  end;
  FToolPanel.Canvas.Font.Assign(FToolPanel.Font);
  W := FToolPanel.Canvas.TextWidth(rsProperties) + 2 * PropLeft;
  if Need > W then
    W := Need;
  FToolPanel.Width := Scale96ToForm(W);
  ShowToolPropValues;
  if FView.Tool in [vtText, vtLabel, vtSymbolText] then
    FocusToolText;
end;

{ ===========================================================================
  TfrmMain.LineStyleItemStats  (function)
  Parameters:
    AIndex: Integer - whole number
  Returns:
    String
  Notes:
    For the self-test script.
  =========================================================================== }
function TfrmMain.LineStyleItemStats(AIndex: Integer): String;
var
  B: TBitmap;
  x, y, N, First, Last: Integer;
  C: TColor;
begin
  B := TBitmap.Create;
  try
    B.SetSize(ilListBoxImages.Width + 40, ilListBoxImages.Height);
    PaintLineStyleItem(B.Canvas, Rect(0, 0, B.Width, B.Height), AIndex, False);
    N := 0; First := -1; Last := -1;
    for x := 0 to B.Width - 1 do
      for y := 0 to B.Height - 1 do
      begin
        C := ColorToRGB(B.Canvas.Pixels[x, y]);
        if (C and $FF) + ((C shr 8) and $FF) + ((C shr 16) and $FF) < 3 * 100 then
        begin
          Inc(N);
          if First < 0 then
            First := x;
          Last := x;
        end;
      end;
    Result := IntToStr(N) + ' ' + IntToStr(First) + ' ' + IntToStr(Last);
  finally
    B.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.LineStyleComboInfo  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    For the self-test script.
  =========================================================================== }
function TfrmMain.LineStyleComboInfo: String;
var
  i: Integer;
begin
  Result := 'none';
  for i := 0 to High(FToolEditors) do
    if (FToolEditors[i].Def.Choices = DashChoices) and (FToolEditors[i].Control is TComboBox) then
      with FToolEditors[i].Control as TComboBox do
        Result := 'style=' + IntToStr(Ord(Style)) + ' itemheight=' + IntToStr(ItemHeight) + ' ownerdraw=' + IntToStr(Ord(Assigned(OnDrawItem))) + ' width=' + IntToStr(Width) + ' images=' + IntToStr(ilListBoxImages.Count) + ' imgw=' + IntToStr(ilListBoxImages.Width);
end;

{ ===========================================================================
  TfrmMain.ToolPanelInfo  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    For the self-test script: prints one line about the panel and the separator before it.
  =========================================================================== }
function TfrmMain.ToolPanelInfo: Boolean;
var
  k: Integer;
  Caps: String;
begin
  Result := FToolPanel <> nil;
  Caps := '';
  if Result then
    for k := 0 to FToolPanel.ControlCount - 1 do
      if (FToolPanel.Controls[k] is TLabel) and (FToolPanel.Controls[k] <> FToolLabel) then
      begin
        if Caps <> '' then
          Caps := Caps + '|';
        Caps := Caps + TLabel(FToolPanel.Controls[k]).Caption;
      end;
  if Result then
    WriteLn('TOOLPANEL tool=', Ord(FToolOf), ' sepwidth=', FToolSep.Width, ' sepalign=', Ord(FToolSep.Align), ' sepcaption=[', FToolSep.Caption, '] sepleft=', FToolSep.Left,
      ' panelalign=', Ord(FToolPanel.Align), ' bevel=', Ord(FToolPanel.BevelOuter), ' caption=[', FToolPanel.Caption, '] left=', FToolPanel.Left, ' width=', FToolPanel.Width,
      ' parent=', FToolPanel.Parent.Name, ' label=[', FToolLabel.Caption, '] labelalign=', Ord(FToolLabel.Align), ' labelalignment=', Ord(FToolLabel.Alignment),
      ' ladderright=', plDrawLadder.Left + plDrawLadder.Width, ' editors=', Length(FToolEditors), ' captions=[', Caps, ']')
  else
    WriteLn('TOOLPANEL none');
end;

{ ===========================================================================
  TfrmMain.ToolEditorNames  (function)
  Parameters:  none
  Returns:
    TStringArray
  Notes:
    For the self-test script.
  =========================================================================== }
function TfrmMain.ToolEditorNames: TStringArray;
var
  i: Integer;
begin
  SetLength(Result, Length(FToolEditors));
  for i := 0 to High(FToolEditors) do
    with FToolEditors[i].Control do
      Result[i] := FToolEditors[i].Def.Name + ' ' + ClassName + ' ' + IntToStr(Left) + ' ' + IntToStr(Top) + ' ' + IntToStr(Width) + ' ' + IntToStr(Height);
end;

{ ===========================================================================
  TfrmMain.SetToolPropertyText  (function)
  Parameters:
    const AName: String - the name
    const AValue: String - the value
  Returns:
    Boolean
  Notes:
    For the self-test script: the same as choosing the value in the tool's Properties panel.
  =========================================================================== }
function TfrmMain.SetToolPropertyText(const AName, AValue: String): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(FToolEditors) do
    if FToolEditors[i].Def.Name = AName then
    begin
      CommitToolProp(i, AValue);
      Result := True;
    end;
end;

{ ===========================================================================
  TfrmMain.ShowToolPropValues  (procedure)
  Parameters:  none
  Notes:
    Puts the values the tool in use will give new objects into its editors on the Draw ribbon.
  =========================================================================== }
procedure TfrmMain.ShowToolPropValues;
var
  i: Integer;
begin
  FUpdatingProps := True;
  try
    for i := 0 to High(FToolEditors) do
      ShowEditorValue(FToolEditors[i], FView.ToolPropValue(FToolOf, FToolEditors[i].Def.Name), False);
  finally
    FUpdatingProps := False;
  end;
  ShowSymbolFrames;
end;

{ ===========================================================================
  TfrmMain.CommitToolProp  (procedure)
  Parameters:
    Index: Integer - zero-based index
    const Value: String - the value
  Notes:
    A value was chosen in the tool's Properties panel: new objects of that tool get it from now
    on.
  =========================================================================== }
procedure TfrmMain.CommitToolProp(Index: Integer; const Value: String);
begin
  if FUpdatingProps or (Index < 0) or (Index > High(FToolEditors)) then
    Exit;
  FView.SetToolDefault(FToolOf, FToolEditors[Index].Def.Name, Value);
  ShowToolPropValues;
end;

{ ===========================================================================
  TfrmMain.CommitAny  (procedure)
  Parameters:
    Index: Integer - zero-based index
    const Value: String - the value
  Notes:
    Sends a value from an editor of the selection (Tag below TOOLPROP_BASE) or of the tool in
    use to where it belongs.
  =========================================================================== }
procedure TfrmMain.CommitAny(Index: Integer; const Value: String);
begin
  if Index >= TOOLPROP_BASE then
    CommitToolProp(Index - TOOLPROP_BASE, Value)
  else
    CommitProp(Index, Value);
end;

{ ===========================================================================
  TfrmMain.ShowPropValues  (procedure)
  Parameters:  none
  Notes:
    Put the current values into the editors (a "mixed" value is shown empty)
  =========================================================================== }
procedure TfrmMain.ShowPropValues;
var
  i: Integer;
  V: String;
  Mixed: Boolean;
begin
  FUpdatingProps := True;
  try
    for i := 0 to High(FProps) do
    begin
      V := CommonValue(FView.SelectedList, FProps[i].Def.Name, Mixed);
      FProps[i].Mixed := Mixed;
      ShowEditorValue(FProps[i], V, Mixed);
    end;
  finally
    FUpdatingProps := False;
  end;
  ShowSymbolFrames;
end;

{ ===========================================================================
  TfrmMain.ShowEditorValue  (procedure)
  Parameters:
    var AEditor: TPropEditor - in/out: changed by the call
    const AValue: String - the value
    AMixed: Boolean - flag
  Notes:
    Puts a value into an editor of the selection or of the tool (the caller has FUpdatingProps
    set). What is shown depends on the control: a choice in a drop-down is selected by its
    position, in a check box it is ticked when the choice is not the first, on a button the
    picture of the direction is chosen; a yes/no in a check box is ticked, on a toggle button
    the button is pressed; a number in a number box (or as text in a drop-down); a color on a
    color button; text in a box or a drop-down.
  =========================================================================== }
procedure TfrmMain.ShowEditorValue(var AEditor: TPropEditor; const AValue: String; AMixed: Boolean);
var
  C: TControl;
  K: Integer;
begin
  C := AEditor.Control;
  AEditor.ShownText := '';
  case AEditor.Def.Kind of
    pkChoice:
      begin
        K := -1;
        if not AMixed then
          K := ChoiceIndex(AEditor.Def.Choices, AValue);
        if C is TComboBox then
          TComboBox(C).ItemIndex := K
        else if C is TRadioButton then
          TRadioButton(C).Checked := (K >= 0) and (K = RadioChoice(TRadioButton(C), AEditor.Def.Choices))
        else if C is TCheckBox then
          TCheckBox(C).Checked := K > 0
        else if (C is TSpeedButton) and (AEditor.Mode = bmDrop) then
          ShowBusGlyph(TSpeedButton(C), IfThen(K = 1, 3, IfThen(K = 0, 1, 0)), 0)
        else if (C is TSpeedButton) and (AEditor.Mode = bmFill) then
          ShowFillGlyph(TSpeedButton(C), K, ColorOfHex(FillColorOf(C.Tag)))
        else if C is TSpeedButton then
        begin
          if AEditor.Def.Choices = DirChoices then
            K := ChoiceIndex(PropDirRotation, AValue)
          else
            K := ChoiceIndex(AEditor.Def.Choices, AValue);
          if K >= 0 then
            TSpeedButton(C).ImageIndex := PropDirGlyph + K;      { (the pictures of the directions, in the frame's own image list) }
        end;
      end;
    pkInt, pkFloat:
      if C is TCustomComboBox then
      begin
        if AMixed then
          AEditor.ShownText := ''
        else
          AEditor.ShownText := IntToStr(Round(ParseFloat(AValue, 0)));
        TCustomComboBox(C).Text := AEditor.ShownText;
      end
      else
        ShowNumberValue(AEditor, AValue, AMixed);
    pkBool:
      begin
        if C is TCheckBox then
        begin
          if AMixed then
            TCheckBox(C).State := cbGrayed
          else
            TCheckBox(C).Checked := AValue = '1';
        end
        else if C is TSpeedButton then
          TSpeedButton(C).Down := (not AMixed) and (AValue = '1');
      end;
    pkColor:
      begin
        if AMixed then
          (C as TColorButton).ButtonColor := clBtnFace
        else
          (C as TColorButton).ButtonColor := ColorOfHex(AValue);
        (C as TColorButton).Hint := AValue;
        (C as TColorButton).ShowHint := True;
      end;
  else
    begin
      if AMixed then
        AEditor.ShownText := ''
      else
        AEditor.ShownText := StringReplace(AValue, #10, '\n', [rfReplaceAll]);
      if C is TCustomComboBox then
      begin
        TCustomComboBox(C).Text := AEditor.ShownText;
        K := TCustomComboBox(C).Items.IndexOf(AEditor.ShownText);
        if K >= 0 then
          TCustomComboBox(C).ItemIndex := K;
      end
      else if C is TCustomEdit then
      begin
        TCustomEdit(C).Text := AEditor.ShownText;
        TCustomEdit(C).TextHint := rsMixed2;
      end;
    end;
  end;
end;

{ ===========================================================================
  TfrmMain.CommitProp  (procedure)
  Parameters:
    Index: Integer - which editor
    const Value: String - the new value
  Notes:
    Applies a value typed or chosen in a property editor to all selected objects as one undo
    step, then refreshes the editors and the status line.
  =========================================================================== }
procedure TfrmMain.CommitProp(Index: Integer; const Value: String);
begin
  if FUpdatingProps then
    Exit;
  if FView.ApplyProperty(FProps[Index].Def.Name, Value) > 0 then
  begin
    FModified := True;
    UpdateFormTitle;
  end;
  ShowPropValues;
  sbMainBar.Panels[1].Text := DescribeSelection;
end;

{ ===========================================================================
  TfrmMain.PropEditChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Each change of the text box of the Text or Label tool's panel (a keystroke) becomes the text
    of the tool at once, so the floating text on the sheet follows what is typed. Nothing is
    done for the boxes of a selection, which apply when editing is done.
  =========================================================================== }
procedure TfrmMain.PropEditChange(Sender: TObject);
var
  I: Integer;
begin
  if FUpdatingProps or (FView = nil) then
    Exit;
  I := (Sender as TControl).Tag;
  if (I < TOOLPROP_BASE) or (I - TOOLPROP_BASE > High(FToolEditors)) then
    Exit;
  if (FToolEditors[I - TOOLPROP_BASE].Def.Name <> 'text') or not (FView.Tool in [vtText, vtLabel, vtNote, vtPower]) then
    Exit;
  FView.SetToolDefault(FToolOf, 'text', (Sender as TEdit).Text);
  FView.Invalidate;
end;

{ ===========================================================================
  TfrmMain.FocusToolTextAsync  (procedure)
  Parameters:
    Data: PtrInt
  Notes:
    FocusToolText, called once the events that follow a placement have been handled (they set
    the boxes' text again, which would drop the selection).
  =========================================================================== }
procedure TfrmMain.FocusToolTextAsync(Data: PtrInt);
begin
  if (FView <> nil) and (FView.Tool in [vtText, vtLabel, vtSymbolText]) then
    FocusToolText;
end;

{ ===========================================================================
  TfrmMain.FocusToolText  (procedure)
  Parameters:  none
  Notes:
    Puts the focus in the text box of the tool's panel with all its text selected, so what is
    typed replaces the text of the next text or label. Does nothing when there is no such box or
    it cannot take the focus.
  =========================================================================== }
procedure TfrmMain.FocusToolText;
var
  i: Integer;
begin
  for i := 0 to High(FToolEditors) do
    if ((FToolEditors[i].Def.Name = 'text') or (FToolEditors[i].Def.Name = 'symtext.text')) and (FToolEditors[i].Control is TEdit) and FToolEditors[i].Control.Visible then
    begin
      { CanFocus is asked first: SetFocus on a box that cannot take it (its tab is not showing, the window is not shown yet) raises an exception,
        which stops the program in the debugger even though it is caught here }
      if (FToolEditors[i].Control as TEdit).CanFocus then
      begin
        try
          (FToolEditors[i].Control as TEdit).SetFocus;
          (FToolEditors[i].Control as TEdit).SelectAll;
        except
          // (still not focusable)
        end;
      end;
      Exit;
    end;
end;

{ ===========================================================================
  TfrmMain.PropEditDone  (procedure)
  Parameters:
    Sender: TObject - the edit box
  Notes:
    Event handler: a text editor lost focus or Enter was pressed, so apply its text (an
    untouched "mixed" field is left alone).
  =========================================================================== }
procedure TfrmMain.PropEditDone(Sender: TObject);
var
  I: Integer;
  V: String;
begin
  if FUpdatingProps then
    Exit;
  I := (Sender as TControl).Tag;
  V := StringReplace((Sender as TEdit).Text, '\n', #10, [rfReplaceAll]);
  if I >= TOOLPROP_BASE then begin
    CommitToolProp(I - TOOLPROP_BASE, V);
    Exit;
  end;
  if (I < 0) or (I > High(FProps)) then
    Exit;
  { a box that still shows what it was given applies nothing (the box takes the focus when a text is selected, and gives it up again at the next click) }
  if (Sender as TEdit).Text = FProps[I].ShownText then
    Exit;
  { an untouched "mixed" field stays as it is }
  if FProps[I].Mixed and (V = '') then
    Exit;
  CommitProp(I, V);
end;

{ ===========================================================================
  TfrmMain.PaintLineStyleItem  (procedure)
  Parameters:
    ACanvas: TCanvas - the canvas to draw on
    const ARect: TRect
    AIndex: Integer - whole number
    ASelected: Boolean - flag
  Notes:
    Draws a line style as a picture: item N is image N of ilListBoxImages (0 solid, 1 dashed, 2
    dot, 3 dash dot, 4 dash dot dot).
  =========================================================================== }
procedure TfrmMain.PaintLineStyleItem(ACanvas: TCanvas; const ARect: TRect; AIndex: Integer; ASelected: Boolean);
var
  X, Y: Integer;
begin
  if ASelected then
    ACanvas.Brush.Color := clHighlight
  else
    ACanvas.Brush.Color := clWindow;
  ACanvas.FillRect(ARect);
  X := ARect.Left + ((ARect.Right - ARect.Left) - ilListBoxImages.Width) div 2;
  Y := ARect.Top + ((ARect.Bottom - ARect.Top) - ilListBoxImages.Height) div 2;
  if (AIndex >= 0) and (AIndex < ilListBoxImages.Count) then
    ilListBoxImages.Draw(ACanvas, X, Y, AIndex);
end;

{ ===========================================================================
  TfrmMain.LineStyleDrawItem  (procedure)
  Parameters:
    Control: TWinControl
    Index: Integer - zero-based index
    ARect: TRect
    State: TOwnerDrawState
  Notes:
    OnDrawItem of the Line style drop-downs: shows the style as a picture instead of its name.
  =========================================================================== }
procedure TfrmMain.LineStyleDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
begin
  if Index < 0 then
  begin
    (Control as TComboBox).Canvas.Brush.Color := clWindow;
    (Control as TComboBox).Canvas.FillRect(ARect);
    Exit;
  end;
  PaintLineStyleItem((Control as TComboBox).Canvas, ARect, Index, (odSelected in State) and not (odComboBoxEdit in State));
end;

{ ===========================================================================
  TfrmMain.PropChoiceChange  (procedure)
  Parameters:
    Sender: TObject - the combo box
  Notes:
    Event handler: a drop-down choice changed, so apply it.
  =========================================================================== }
procedure TfrmMain.PropChoiceChange(Sender: TObject);
var
  I: Integer;
begin
  if FUpdatingProps then
    Exit;
  I := (Sender as TControl).Tag;
  with Sender as TComboBox do
    if ItemIndex >= 0 then
      CommitAny(I, ChoiceText(EditorOfTag(I)^.Def.Choices, ItemIndex));      { (by position: a list drawn as pictures has no words) }
end;

{ ===========================================================================
  TfrmMain.EditorOfTag  (function)
  Parameters:
    ATag: Integer - whole number
  Returns:
    PPropEditor
  Notes:
    Finds the editor record of a control.
  =========================================================================== }
function TfrmMain.EditorOfTag(ATag: Integer): PPropEditor;
begin
  if ATag >= TOOLPROP_BASE then
    Result := @FToolEditors[ATag - TOOLPROP_BASE]
  else
    Result := @FProps[ATag];
end;

{ ===========================================================================
  TfrmMain.PropComboKeyDown  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    var Key: Word - key code (in/out: changed by the call)
    Shift: TShiftState - modifier keys held down
  Notes:
    Key handling of the font name and size boxes: Enter applies what the box says (a font typed
    to find it, or chosen with the arrow keys), as choosing it with the mouse does, without the
    list having to be opened again.
  =========================================================================== }
procedure TfrmMain.PropComboKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
    PropComboDone(Sender);
end;

{ ===========================================================================
  TfrmMain.PropComboDone  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Event handler: something was chosen or typed in the box. A number that is not one, an empty
    box that was mixed and a text that is the one shown are not applied.
  =========================================================================== }
procedure TfrmMain.PropComboDone(Sender: TObject);
var
  I: Integer;
  V: String;
  Ed: PPropEditor;
begin
  if FUpdatingProps then
    Exit;
  I := (Sender as TControl).Tag;
  Ed := EditorOfTag(I);
  V := Trim((Sender as TCustomComboBox).Text);
  if (V = '') or (V = Ed^.ShownText) then
    Exit;
  if (Ed^.Def.Kind = pkInt) and (StrToIntDef(V, MaxInt) = MaxInt) then
  begin
    FUpdatingProps := True;
    try (Sender as TCustomComboBox).Text := Ed^.ShownText; finally FUpdatingProps := False; end;
    Exit;
  end;
  CommitAny(I, V);
end;

{ ===========================================================================
  TfrmMain.PropSpeedClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Event handler: a toggle button (bold, italic) applies 1 or 0; a button for a choice (the
    direction of a power symbol) goes on to the next choice of PropDirRotation. The frame's own
    OnClick is called first.
  =========================================================================== }
procedure TfrmMain.PropSpeedClick(Sender: TObject);
var
  I: Integer;
  Rot: String;
  Ed: PPropEditor;
begin
  I := (Sender as TControl).Tag;
  Ed := EditorOfTag(I);
  if Assigned(Ed^.OldClick) then
    Ed^.OldClick(Sender);
  if FUpdatingProps then
    Exit;
  if Ed^.Mode = bmCycle then
  begin
    Rot := Ed^.Def.Choices;
    if Rot = DirChoices then
      Rot := PropDirRotation;      { (Up, Right, Down, Left: turning clockwise) }
    CommitAny(I, ChoiceText(Rot, (ChoiceIndex(Rot, CurrentChoice(I)) + 1) mod ChoiceCount(Rot)));
  end
  else if (Sender as TSpeedButton).Down then
    CommitAny(I, '1')
  else
    CommitAny(I, '0');
end;

{ ===========================================================================
  TfrmMain.FillColorOf  (function)
  Parameters:
    ATag: Integer - whole number
  Returns:
    String
  Notes:
    The Fill button edits the fill type; the color it shows and changes is the 'fill.color' of
    the same tool or selection.
  =========================================================================== }
function TfrmMain.FillColorOf(ATag: Integer): String;
var
  Mixed: Boolean;
begin
  if ATag >= TOOLPROP_BASE then
    Result := FView.ToolPropValue(FToolOf, 'fill.color')
  else
  begin
    Result := CommonValue(FView.SelectedList, 'fill.color', Mixed);
    if Mixed then
      Result := '';
  end;
  if Result = '' then
    Result := HexOfColor(clBlack);
end;

{ ===========================================================================
  TfrmMain.ShowFillGlyph  (procedure)
  Parameters:
    AButton: TSpeedButton
    AChoice: Integer - whole number
    AColor: TColor
  Notes:
    Draws the fill on the button as a 32 x 32 picture (DrawFillGlyph: the pattern in the color
    inside a 1 pixel black outline), and puts what it shows in the hint.
  =========================================================================== }
procedure TfrmMain.ShowFillGlyph(AButton: TSpeedButton; AChoice: Integer; AColor: TColor);
var
  B: TBitmap;
begin
  B := TBitmap.Create;
  try
    B.SetSize(32, 32);
    DrawFillGlyph(B.Canvas, Rect(0, 0, 32, 32), AChoice, AColor);
    AButton.Glyph.Assign(B);
  finally
    B.Free;
  end;
  if AChoice < 0 then
    AButton.Hint := rsFillMixed
  else
    AButton.Hint := Format(rsFill2, [ChoiceText(FillChoices, AChoice), HexOfColor(AColor)]);
  AButton.ShowHint := True;
end;

{ ===========================================================================
  TfrmMain.IsFillButton  (function)
  Parameters:
    AControl: TComponent
  Returns:
    Boolean
  Notes:
    TODO: describe.
  =========================================================================== }
function TfrmMain.IsFillButton(AControl: TComponent): Boolean;
var
  T: Integer;
begin
  Result := False;
  if not (AControl is TSpeedButton) then
    Exit;
  T := TControl(AControl).Tag;
  if T >= TOOLPROP_BASE then
    Result := (T - TOOLPROP_BASE <= High(FToolEditors)) and (FToolEditors[T - TOOLPROP_BASE].Control = AControl) and (FToolEditors[T - TOOLPROP_BASE].Mode = bmFill)
  else
    Result := (T >= 0) and (T <= High(FProps)) and (FProps[T].Control = AControl) and (FProps[T].Mode = bmFill);
end;

{ ===========================================================================
  TfrmMain.PropFillClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Event handler: drops the menu of fill styles down from the button, telling it the fill the
    tool or the selection has now. A click on the button while the menu is open closes it.
  =========================================================================== }
procedure TfrmMain.PropFillClick(Sender: TObject);
var
  I: Integer;
begin
  if FUpdatingProps then
    Exit;
  if FFillDrop = nil then
  begin
    FFillDrop := TfrmFillDropDown.Create(Self);
    FFillDrop.OnPick := @FillPicked;
  end;
  if FFillDrop.Visible then
  begin
    FFillDrop.Close;
    Exit;
  end;
  if FFillDrop.JustClosed then
    Exit;      { (the click that closed it) }
  I := (Sender as TControl).Tag;
  FFillTag := I;
  FFillDrop.SetFill(ChoiceIndex(FillChoices, CurrentChoice(I)), ColorOfHex(FillColorOf(I)));
  FFillDrop.Popup(Sender as TControl);
end;

{ ===========================================================================
  TfrmMain.IsBusButton  (function)
  Parameters:
    AControl: TComponent
  Returns:
    Boolean
  Notes:
    TODO: describe.
  =========================================================================== }
function TfrmMain.IsBusButton(AControl: TComponent): Boolean;
var
  T: Integer;
begin
  Result := False;
  if not (AControl is TSpeedButton) then
    Exit;
  T := TControl(AControl).Tag;
  if T >= TOOLPROP_BASE then
    Result := (T - TOOLPROP_BASE <= High(FToolEditors)) and (FToolEditors[T - TOOLPROP_BASE].Control = AControl) and (FToolEditors[T - TOOLPROP_BASE].Mode = bmDrop)
  else
    Result := (T >= 0) and (T <= High(FProps)) and (FProps[T].Control = AControl) and (FProps[T].Mode = bmDrop);
end;

{ ===========================================================================
  TfrmMain.ShowBusGlyph  (procedure)
  Parameters:
    AButton: TSpeedButton
    APhases: Integer - whole number
    ASpacingMm: Double - number
  Notes:
    Draws one line, or three side by side, as a 32 x 32 picture on the button, and puts what it
    shows in the hint.
  =========================================================================== }
procedure TfrmMain.ShowBusGlyph(AButton: TSpeedButton; APhases: Integer; ASpacingMm: Double);
var
  B: TBitmap;
  X: Integer;
begin
  B := TBitmap.Create;
  try
    B.SetSize(32, 32);
    B.Canvas.Brush.Color := clWhite;
    B.Canvas.FillRect(0, 0, 32, 32);
    B.Canvas.Pen.Color := clBlue;
    B.Canvas.Pen.Width := 3;
    if APhases = 3 then
    begin
      for X := 0 to 2 do
      begin
        B.Canvas.MoveTo(5 + X * 11, 3);
        B.Canvas.LineTo(5 + X * 11, 28);
      end;
    end
    else
    begin
      B.Canvas.MoveTo(16, 3);
      B.Canvas.LineTo(16, 28);
    end;
    AButton.Glyph.Assign(B);
  finally
    B.Free;
  end;
  if APhases = 3 then
    AButton.Hint := rsBusPhase
  else if APhases = 1 then
    AButton.Hint := rsBusPhase2
  else
    AButton.Hint := rsBusMixed;
  AButton.ShowHint := True;
end;

{ ===========================================================================
  TfrmMain.PropBusClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Event handler: drops the panel of phases and wire spacing down from the button, telling it
    what the tool or the selected buses have now. A click on the button while the panel is open
    closes it.
  =========================================================================== }
procedure TfrmMain.PropBusClick(Sender: TObject);
var
  I: Integer;
  Mixed: Boolean;
  Sp: String;
  Mm: Double;
begin
  if FUpdatingProps then
    Exit;
  if FBusDrop = nil then
  begin
    FBusDrop := TfrmBusDropDown.Create(Self);
    FBusDrop.OnPick := @BusPicked;
  end;
  if FBusDrop.Visible then
  begin
    FBusDrop.Close;
    Exit;
  end;
  if FBusDrop.JustClosed then
    Exit;      { (the click that closed it) }
  I := (Sender as TControl).Tag;
  FBusTag := I;
  if I >= TOOLPROP_BASE then
    Sp := FView.ToolPropValue(FToolOf, 'bus.spacing')
  else
    Sp := CommonValue(FView.SelectedList, 'bus.spacing', Mixed);
  Mm := ParseFloat(Sp, DefaultPhaseSpacing / UNITS_PER_MM);
  if Mm <= 0 then
    Mm := DefaultPhaseSpacing / UNITS_PER_MM;
  FBusDrop.SetBus(IfThen(ChoiceIndex(PhaseChoices, CurrentChoice(I)) = 1, 3, 1), Mm, FView.Sheet.Snap.Grid / UNITS_PER_MM, FView.Sheet.Options.Units);
  FBusDrop.Popup(Sender as TControl);
end;

{ ===========================================================================
  TfrmMain.BusPicked  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    APhases: Integer - whole number
    ASpacingMm: Double - number
  Notes:
    Callback of the panel: what differs from what the tool or the selected buses have is applied
    (the spacing, then the phases).
  =========================================================================== }
procedure TfrmMain.BusPicked(Sender: TObject; APhases: Integer; ASpacingMm: Double);
var
  I: Integer;
  Mixed: Boolean;
  Sp: String;
begin
  I := FBusTag;
  if ((I >= TOOLPROP_BASE) and (I - TOOLPROP_BASE > High(FToolEditors))) or ((I < TOOLPROP_BASE) and (I > High(FProps))) then
    Exit;      { (the panel was made again while it was open) }
  if I >= TOOLPROP_BASE then
    Sp := FView.ToolPropValue(FToolOf, 'bus.spacing')
  else
    Sp := CommonValue(FView.SelectedList, 'bus.spacing', Mixed);
  if (Sp = '') or (Abs(ParseFloat(Sp, 0) - ASpacingMm) > 0.0005) then
    CommitNamed(I, 'bus.spacing', FloatText(ASpacingMm));
  if ChoiceIndex(PhaseChoices, CurrentChoice(I)) <> IfThen(APhases = 3, 1, 0) then
    CommitAny(I, ChoiceText(PhaseChoices, IfThen(APhases = 3, 1, 0)));
end;

{ ===========================================================================
  TfrmMain.BusDropAct  (function)
  Parameters:
    const AAct: String - text
  Returns:
    String
  Notes:
    For the self-test script.
  =========================================================================== }
function TfrmMain.BusDropAct(const AAct: String): String;
var
  Key: Word;
begin
  if FBusDrop = nil then
  begin
    Result := 'none';
    Exit;
  end;
  if AAct = 'close' then
    FBusDrop.Close
  else if AAct = 'esc' then
  begin
    Key := VK_ESCAPE;
    FBusDrop.PressKey(Key, []);
  end;
  Result := FBusDrop.Act(IfThen((AAct = 'close') or (AAct = 'esc'), '', AAct));
end;

{ ===========================================================================
  TfrmMain.BusDropForm  (function)
  Parameters:  none
  Returns:
    TForm
  Notes:
    TODO: describe.
  =========================================================================== }
function TfrmMain.BusDropForm: TForm;
begin
  Result := FBusDrop;
end;

{ ===========================================================================
  TfrmMain.CommitNamed  (procedure)
  Parameters:
    ATag: Integer - whole number
    const AName: String - the name
    const AValue: String - the value
  Notes:
    Applies a property that has no editor of its own (the fill color, which the Fill button
    edits with the fill type) to the tool or to the selected objects.
  =========================================================================== }
procedure TfrmMain.CommitNamed(ATag: Integer; const AName, AValue: String);
begin
  if ATag >= TOOLPROP_BASE then
  begin
    FView.SetToolDefault(FToolOf, AName, AValue);
    ShowToolPropValues;
  end
  else if FView.ApplyProperty(AName, AValue) > 0 then
  begin
    FModified := True;
    UpdateFormTitle;
    ShowPropValues;
    sbMainBar.Panels[1].Text := DescribeSelection;
  end;
end;

{ ===========================================================================
  TfrmMain.FillPicked  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    AChoice: Integer - whole number
    AColor: TColor
  Notes:
    Callback of the menu: what differs from what the tool or the selection has is applied (the
    color, then the style), so choosing the style it already has does nothing.
  =========================================================================== }
procedure TfrmMain.FillPicked(Sender: TObject; AChoice: Integer; AColor: TColor);
var
  I: Integer;
  Hex: String;
begin
  I := FFillTag;
  if ((I >= TOOLPROP_BASE) and (I - TOOLPROP_BASE > High(FToolEditors))) or ((I < TOOLPROP_BASE) and (I > High(FProps))) then
    Exit;      { (the panel was made again while the menu was open) }
  Hex := HexOfColor(AColor);
  if Hex <> FillColorOf(I) then
    CommitNamed(I, 'fill.color', Hex);
  if (AChoice <> ChoiceIndex(FillChoices, CurrentChoice(I))) then
    CommitAny(I, ChoiceText(FillChoices, AChoice));
end;

{ ===========================================================================
  TfrmMain.CurrentChoice  (function)
  Parameters:
    ATag: Integer - whole number
  Returns:
    String
  Notes:
    For a button that steps through the choices.
  =========================================================================== }
function TfrmMain.CurrentChoice(ATag: Integer): String;
var
  Mixed: Boolean;
begin
  if ATag >= TOOLPROP_BASE then
    Result := FView.ToolPropValue(FToolOf, FToolEditors[ATag - TOOLPROP_BASE].Def.Name)
  else
    Result := CommonValue(FView.SelectedList, FProps[ATag].Def.Name, Mixed);
end;

{ ===========================================================================
  TfrmMain.PropBoolClick  (procedure)
  Parameters:
    Sender: TObject - the check box
  Notes:
    Event handler: a check box was clicked, so apply 1 or 0.
  =========================================================================== }
procedure TfrmMain.PropBoolClick(Sender: TObject);
var
  I: Integer;
  Ed: PPropEditor;
begin
  if FUpdatingProps then
    Exit;
  I := (Sender as TControl).Tag;
  Ed := EditorOfTag(I);
  if Ed^.Mode = bmRadio then
  begin
    { the radio button that was ticked: its choice is the value (clearing another one of the group says nothing) }
    if (Sender as TRadioButton).Checked then
      CommitAny(I, ChoiceText(Ed^.Def.Choices, RadioChoice(Sender as TRadioButton, Ed^.Def.Choices)));
    Exit;
  end;
  if Ed^.Mode = bmSwitch then
  begin
    { ticked: the second choice (Solid), not: the first (None) }
    if (Sender as TCheckBox).Checked then
      CommitAny(I, ChoiceText(Ed^.Def.Choices, 1))
    else
      CommitAny(I, ChoiceText(Ed^.Def.Choices, 0));
    Exit;
  end;
  if (Sender as TCheckBox).Checked then
    CommitAny(I, '1')
  else
    CommitAny(I, '0');
end;

{ ===========================================================================
  TfrmMain.PropColorChanged  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    OnColorChanged of the color buttons of the Properties panels: the person chose a color in
    the button's dialog, so apply it. Showing a value (FUpdatingProps) does not come here.
  =========================================================================== }
procedure TfrmMain.PropColorChanged(Sender: TObject);
begin
  if FUpdatingProps then
    Exit;
  CommitAny((Sender as TControl).Tag, HexOfColor((Sender as TColorButton).ButtonColor));
end;

{ ===========================================================================
  TfrmMain.ShowNumberValue  (procedure)
  Parameters:
    var AEditor: TPropEditor - in/out: changed by the call
    const AValue: String - the value
    AMixed: Boolean - flag
  Notes:
    Shows a value in a number box (the caller has FUpdatingProps set, so this is not taken for
    an edit) and remembers it in AEditor.Shown, which is what CommitNumber compares with.
  =========================================================================== }
procedure TfrmMain.ShowNumberValue(var AEditor: TPropEditor; const AValue: String; AMixed: Boolean);
var
  Box: TCustomFloatSpinEdit;
begin
  Box := AEditor.Control as TCustomFloatSpinEdit;
  AEditor.Shown := ParseFloat(AValue, 0);
  Box.ValueEmpty := AMixed;
  if not AMixed then
    Box.Value := AEditor.Shown;
end;

{ ===========================================================================
  TfrmMain.CommitNumber  (procedure)
  Parameters:
    ABox: TCustomFloatSpinEdit
  Notes:
    Applies the value of a number box of the selection or of the tool. Nothing is done for a box
    that is still empty (mixed values) or whose value is the one it was shown with, so passing
    through a box never rounds or changes what an object has.
  =========================================================================== }
procedure TfrmMain.CommitNumber(ABox: TCustomFloatSpinEdit);
var
  I: Integer;
  V, Shown: Double;
begin
  if FUpdatingProps or ABox.ValueEmpty then
    Exit;
  I := ABox.Tag;
  if I >= TOOLPROP_BASE then
  begin
    if (I - TOOLPROP_BASE < 0) or (I - TOOLPROP_BASE > High(FToolEditors)) then
      Exit;
    Shown := FToolEditors[I - TOOLPROP_BASE].Shown;
  end
  else
  begin
    if (I < 0) or (I > High(FProps)) then
      Exit;
    Shown := FProps[I].Shown;
  end;
  V := ABox.Value;
  if ABox.DecimalPlaces = 0 then
  begin
    if Round(V) = Round(Shown) then
      Exit;
    CommitAny(I, IntToStr(Round(V)));
  end
  else
  begin
    if Abs(V - Shown) < 0.5 / IntPower(10, ABox.DecimalPlaces) then
      Exit;
    CommitAny(I, FloatText(V));
  end;
end;

{ ===========================================================================
  TfrmMain.TypeNumber  (function)
  Parameters:
    const AName: String - the name
    AValue: Double - the value
    AToolPanel: Boolean - flag
    AFinish: Boolean - flag
  Returns:
    Boolean
  Notes:
    For the self-test script: does to a number box what typing in it or pressing its arrow does.
  =========================================================================== }
function TfrmMain.TypeNumber(const AName: String; AValue: Double; AToolPanel, AFinish: Boolean): Boolean;
var
  i: Integer;
  Ctl: TControl;
begin
  Result := False;
  Ctl := nil;
  if AToolPanel then
  begin
    for i := 0 to High(FToolEditors) do
      if FToolEditors[i].Def.Name = AName then
        Ctl := FToolEditors[i].Control;
  end
  else
    for i := 0 to High(FProps) do
      if FProps[i].Def.Name = AName then
        Ctl := FProps[i].Control;
  if not (Ctl is TCustomFloatSpinEdit) then
    Exit;
  (Ctl as TCustomFloatSpinEdit).ValueEmpty := False;
  (Ctl as TCustomFloatSpinEdit).Value := AValue;
  if AFinish then
    PropNumberDone(Ctl);
  Result := True;
end;

{ ===========================================================================
  TfrmMain.PropNumberChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    OnChange of the number boxes: an arrow was pressed or a digit typed. The value is applied
    PropSpinDelay milliseconds after the last change (PropTimerTick), so typing 12 does not
    apply 1 on the way.
  =========================================================================== }
procedure TfrmMain.PropNumberChange(Sender: TObject);
begin
  if FUpdatingProps then
    Exit;
  FSpinPending := Sender as TControl;
  FPropTimer.Enabled := False;
  FPropTimer.Enabled := True;
end;

{ ===========================================================================
  TfrmMain.PropNumberDone  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    OnEditingDone of the number boxes (Enter, or the box lost focus): applies the value at once.
  =========================================================================== }
procedure TfrmMain.PropNumberDone(Sender: TObject);
begin
  FPropTimer.Enabled := False;
  FSpinPending := nil;
  CommitNumber(Sender as TCustomFloatSpinEdit);
end;

{ ===========================================================================
  TfrmMain.PropTimerTick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The pause after the last change of a number box is over: apply its value.
  =========================================================================== }
procedure TfrmMain.PropTimerTick(Sender: TObject);
var
  Box: TControl;
begin
  FPropTimer.Enabled := False;
  Box := FSpinPending;
  FSpinPending := nil;
  if Box is TCustomFloatSpinEdit then
    CommitNumber(TCustomFloatSpinEdit(Box));
end;

{ ===========================================================================
  TfrmMain.SetPropertyText  (function)
  Parameters:
    const PropName: String - the property name
    const Value: String - the new value
  Returns:
    Boolean - False if the selection has no such property
  Notes:
    Sets a property through the same path as typing it into its editor (used by the self-test
    script).
  =========================================================================== }
function TfrmMain.SetPropertyText(const PropName, Value: String): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(FProps) do
    if FProps[i].Def.Name = PropName then
    begin
      Result := True;
      CommitProp(i, Value);
      Exit;
    end;
end;

{ ===========================================================================
  TfrmMain.PropertyDump  (function)
  Parameters:  none
  Returns:
    String - text like name=value; name=value
  Notes:
    Lists the properties on the ribbon with their values, "(mixed)" where selected objects
    differ; for tests.
  =========================================================================== }
function TfrmMain.PropertyDump: String;
var
  i: Integer;
  V: String;
  Mixed: Boolean;
begin
  Result := '';
  for i := 0 to High(FProps) do
  begin
    if FProps[i].Mode = bmSwitch then
      Continue;      { (a second control for a property that is already listed) }
    if (FProps[i].Mode = bmRadio) and (i > 0) and (FProps[i - 1].Mode = bmRadio) and (FProps[i - 1].Def.Name = FProps[i].Def.Name) then
      Continue;      { (the radio buttons of one property: listed once) }
    V := CommonValue(FView.SelectedList, FProps[i].Def.Name, Mixed);
    if Mixed then
      V := '(mixed)';
    if Result <> '' then
      Result := Result + '; ';
    Result := Result + FProps[i].Def.Name + '=' + StringReplace(V, #10, '\n', [rfReplaceAll]);
  end;
end;

{ ===========================================================================
  TfrmMain.ShowRibbonTab  (procedure)
  Parameters:
    const ATitle: String - the page caption, e.g. Properties
  Notes:
    Brings a ribbon page forward by its caption and repaints the tab strip, which is not done by
    itself when the page is chosen from code.
  =========================================================================== }
procedure TfrmMain.ShowRibbonTab(const ATitle: String);
var
  i: Integer;
begin
  for i := 0 to FRibbon.PageCount - 1 do
    if SameText(FRibbon.Pages[i].Caption, ATitle) then
      FRibbon.ActivePageIndex := i;
  { setting the page in code does not fire the page control's OnChange, which is what repaints the tab strip }
  pbRibbonDisplay.Invalidate;
end;

{ ===========================================================================
  TfrmMain.RibbonTabTitle  (function)
  Parameters:  none
  Returns:
    String - the caption
  Notes:
    Caption of the ribbon tab showing now.
  =========================================================================== }
function TfrmMain.RibbonTabTitle: String;
begin
  if FRibbon.ActivePage <> nil then
    Result := FRibbon.ActivePage.Caption
  else
    Result := '';
end;

{ ===========================================================================
  TfrmMain.PressRibbon  (function)
  Parameters:
    const ACaption: String - the button text
  Returns:
    Boolean - False if no button has that caption
  Notes:
    Presses a ribbon button found by its caption, as if clicked (used by the self-test script).
  =========================================================================== }
function TfrmMain.PressRibbon(const ACaption: String): Boolean;
var
  i, j: Integer;
  B: TControl;
begin
  Result := False;
  for i := 0 to FRibbon.PageCount - 1 do
    for j := 0 to FRibbon.Pages[i].ControlCount - 1 do
    begin
      B := FRibbon.Pages[i].Controls[j];
      if (B is TSpeedButton) and (SameText((B as TSpeedButton).Caption, ACaption) or
         SameText(StringReplace((B as TSpeedButton).Caption, #10, ' ', [rfReplaceAll]), ACaption)) then
      begin
        if (B as TSpeedButton).GroupIndex = 1 then
          (B as TSpeedButton).Down := True;
        (B as TSpeedButton).Click;
        Result := True;
        Exit;
      end;
    end;
end;

{ ===========================================================================
  TfrmMain.SetGridMmFromScript  (procedure)
  Parameters:
    Mm: Double - grid spacing in millimetres
  Notes:
    Sets the grid size and updates the ribbon (used by the self-test script).
  =========================================================================== }
procedure TfrmMain.SetGridMmFromScript(Mm: Double);
begin
  FView.GridMm := Mm;
  UpdateRibbonState;
end;

{ ===========================================================================
  TfrmMain.SetRibbonTheme  (procedure)
  Parameters:
    RibbonTheme: TLDTheme
  Notes:
    Sets the ribbon theme based on light/dark).
  =========================================================================== }
procedure TfrmMain.SetRibbonTheme(RibbonTheme: TLDTheme);
var
  I: Integer;
  Colors: TRibbonTheme;
begin
  FTheme := RibbonTheme;
  if RibbonTheme = themeLight then
    Colors := RibbonThemes[0]
  else if RibbonTheme = themeDark then
    Colors := RibbonThemes[1];
  if FRibbonTabs <> nil then
    FRibbonTabs.Theme := RibbonTheme;

//  FRibbon.ParentColor := False;
  FRibbon.Color := Colors.ContentColor;
  FRibbon.Font.Color := Colors.ContentTextColor;

  for I := 0 to FRibbon.PageCount - 1 do
  begin
//    FRibbon.Pages[I].ParentColor := False;
    FRibbon.Pages[I].Color := Colors.ContentColor;
    FRibbon.Pages[I].Font.Color := Colors.ContentTextColor;
    FRibbon.Pages[I].Invalidate;
  end;
  pbRibbonDisplay.Invalidate;
end;

{ ------------------------------------------------------------------ document handling }

{ ===========================================================================
  TfrmMain.GetCurDoc  (function)
  Parameters:  none
  Returns:
    TDocument - the document, or nil when none is open
  Notes:
    The document being shown.
  =========================================================================== }
function TfrmMain.GetCurDoc: TDocument;
begin
  Result := nil;
  if (FDocs <> nil) and (FCurrent >= 0) and (FCurrent < FDocs.Count) then
    Result := FDocs[FCurrent];
end;

{ ===========================================================================
  TfrmMain.GetView  (function)
  Parameters:  none
  Returns:
    TSchematicView - the view (never nil once the form is built)
  Notes:
    The drawing area of the current document; while no document is open, the empty placeholder
    view.
  =========================================================================== }
function TfrmMain.GetView: TSchematicView;
begin
  if GetCurDoc <> nil then
    Result := GetCurDoc.View
  else
    Result := FPlaceholder;
end;

{ ===========================================================================
  TfrmMain.GetDesign  (function)
  Parameters:  none
  Returns:
    TDesignFile - the design, or nil when none is open
  Notes:
    The design of the current document.
  =========================================================================== }
function TfrmMain.GetDesign: TDesignFile;
begin
  if GetCurDoc <> nil then
    Result := GetCurDoc.Design
  else
    Result := nil;
end;

{ ===========================================================================
  TfrmMain.GetFileName  (function)
  Parameters:  none
  Returns:
    String - the name, empty if it has never been saved or none is open
  Notes:
    The file name of the current document.
  =========================================================================== }
function TfrmMain.GetFileName: String;
begin
  if GetCurDoc <> nil then
    Result := GetCurDoc.FileName
  else
    Result := '';
end;

{ ===========================================================================
  TfrmMain.SetFileName  (procedure)
  Parameters:
    const Value: String - the new file name
  Notes:
    Gives the current document a file name and updates its tab and the Window menu.
  =========================================================================== }
procedure TfrmMain.SetFileName(const Value: String);
begin
  if GetCurDoc = nil then
    Exit;
  GetCurDoc.FileName := Value;
  UpdateDocTabs;
end;

{ ===========================================================================
  TfrmMain.GetModified  (function)
  Parameters:  none
  Returns:
    Boolean - True if it has
  Notes:
    Whether the current document has unsaved changes.
  =========================================================================== }
function TfrmMain.GetModified: Boolean;
begin
  if GetCurDoc <> nil then
    Result := GetCurDoc.Modified
  else
    Result := False;
end;

{ ===========================================================================
  TfrmMain.SetModified  (procedure)
  Parameters:
    Value: Boolean - True when there are unsaved changes
  Notes:
    Sets or clears the current document's unsaved-changes mark and updates its tab.
  =========================================================================== }
procedure TfrmMain.SetModified(Value: Boolean);
begin
  if GetCurDoc = nil then
    Exit;
  GetCurDoc.Modified := Value;
  UpdateDocTabs;
end;

{ ===========================================================================
  TfrmMain.CreateView  (function)
  Parameters:  none
  Returns:
    TSchematicView - the new view
  Notes:
    Makes a drawing area (hidden) inside the work area and connects its events to the main form.
    Each document has its own, so its undo history, zoom and selection stay with it.
  =========================================================================== }
function TfrmMain.CreateView: TSchematicView;
begin
  Result := TSchematicView.Create(Self);
  Result.Parent := pnlMain;
  Result.Align := alClient;
  Result.Visible := False;
  Result.OnSelectionChange := @ViewSelection;
  Result.OnStatus := @ViewStatus;
  Result.OnPosition := @ViewPosition;
  Result.OnModified := @ViewModified;
  Result.OnToolChanged := @ViewToolChanged;
  Result.OnDragEnd := @ViewDragEnd;
  Result.OnZoomChanged := @ViewZoomChanged;
  Result.OnUndoChanged := @ViewUndoChanged;
  Result.OnMarkerClick := @FindMarkerClicked;
  Result.OnObjectPlaced := @ViewPlaced;
  Result.OnContext := @ViewContext;
  Result.OnDblClick := @ViewDblClick;
  Result.OnViewMoved := @ViewMovedForRulers;
  Result.OnArcTypeChanged := @ArcTypeChangedByView;
  Result.DrawPopup := pmPolyDraw;
  Result.ArcPopup := pmArcDraw;
end;

{ ===========================================================================
  TfrmMain.FocusView  (procedure)
  Parameters:  none
  Notes:
    Gives the keyboard focus to the current drawing area, when it can take it.
  =========================================================================== }
procedure TfrmMain.FocusView;
begin
  if FView.CanFocus then
    FView.SetFocus;
end;

{ ===========================================================================
  TfrmMain.AddDocument  (function)
  Parameters:
    ADesign: TDesignFile - the design; the document owns it
    const AFileName: String - the file it came from, or empty for a new design
  Returns:
    TDocument - the new document
  Notes:
    Opens a design as a new document: gives it a view of its own, makes it the current one and
    shows it.
  =========================================================================== }
function TfrmMain.AddDocument(ADesign: TDesignFile; const AFileName: String): TDocument;
var
  i: Integer;
begin
  ADesign.AllowEmptySheets := True;
  Result := FDocs.Add(ADesign, AFileName);
  Result.View := CreateView;
  FCurrent := FDocs.Count - 1;
  ApplyDocVisibility;
  FPlaceholder.Visible := False;
  { the design goes in after the view is shown, so the page is fitted to the real size }
  Result.View.SetDesign(ADesign, 0);
  RefreshAfterDocumentChange;
  FocusView;
end;

{ ===========================================================================
  TfrmMain.ActivateDocument  (procedure)
  Parameters:
    Index: Integer - position in the list of documents
  Notes:
    Makes an open document the current one: shows its view and hides the others, then refreshes
    everything that depends on the current document (sheet tabs, title, paper status, ribbon,
    properties, tabs, Window menu). An index out of range is ignored.
  =========================================================================== }
procedure TfrmMain.ActivateDocument(Index: Integer);
var
  i: Integer;
begin
  if (FDocs = nil) or (Index < 0) or (Index >= FDocs.Count) then
    Exit;
  FCurrent := Index;
  ApplyDocVisibility;
  FPlaceholder.Visible := False;
  RefreshAfterDocumentChange;
  FocusView;
end;

{ ===========================================================================
  TfrmMain.ApplyDocVisibility  (procedure)
  Parameters:  none
  Notes:
    Shows what belongs to the current document and hides the rest: the drawing view of a design or symbol, or the editor of a parts library (whose own view stays
    hidden).
  =========================================================================== }
procedure TfrmMain.ApplyDocVisibility;
var
  i: Integer;
begin
  for i := 0 to FDocs.Count - 1 do
  begin
    FDocs[i].View.Visible := (i = FCurrent) and (FDocs[i].PartsEditor = nil);
    if FDocs[i].PartsEditor <> nil then
      FDocs[i].PartsEditor.Visible := (i = FCurrent);
  end;
end;

{ ===========================================================================
  TfrmMain.OpenPartsEditor  (function)
  Parameters:
    const AFile: String - the parts file
  Returns:
    TDocument - the tab of the editor, nil when the file cannot be used (PartsEditorError says why)
  Notes:
    Opens the parts library editor for a file as a tab after the other documents, or shows the tab that edits that file already. The editor has its own
    connection to the file; when it changes the file the Parts tab of the library panel reads the list again (PartsEditorChanged).
  =========================================================================== }
function TfrmMain.OpenPartsEditor(const AFile: String): TDocument;
var
  At: Integer;
  Ed: TfrPartsEditor;
begin
  Result := nil;
  FPartsEditorError := '';
  At := FDocs.IndexOfParts(AFile);
  if At >= 0 then
  begin
    ActivateDocument(At);
    Exit(FDocs[At]);
  end;
  Ed := TfrPartsEditor.Create(Self);
  try
    Ed.Parent := pnlMain;
    Ed.Align := alClient;
    Ed.Visible := False;
    Ed.LoadFile(AFile);
  except
    on E: EPartsError do
    begin
      Ed.Free;
      FPartsEditorError := E.Message;
      Exit;
    end;
  end;
  Ed.OnChanged := @PartsEditorChanged;
  Ed.OnEditSymbol := @PartSymbolEdit;
  Ed.OnImportSymbol := @PartSymbolImport;
  Result := FDocs.AddParts(AFile);
  Result.PartsEditor := Ed;
  Result.View := CreateView;
  Result.View.Visible := False;
  FCurrent := FDocs.Count - 1;
  ApplyDocVisibility;
  FPlaceholder.Visible := False;
  RefreshAfterDocumentChange;
end;

{ ===========================================================================
  TfrmMain.PartsEditorOfCurrent  (function)
  Returns:
    TfrPartsEditor - the editor of the tab shown, nil when the tab is a design or symbol (or none is open)
  Notes:
    What the Parts menu's editing commands work on.
  =========================================================================== }
function TfrmMain.PartsEditorOfCurrent: TfrPartsEditor;
begin
  if CurDoc <> nil then
    Result := CurDoc.PartsEditor
  else
    Result := nil;
end;

{ ===========================================================================
  TfrmMain.PartsEditorChanged  (procedure)
  Parameters:
    Sender: TObject - the editor
  Notes:
    The library editor changed a parts file: when the Parts tab shows that file its list is read again, and the tab captions follow a renamed library.
  =========================================================================== }
procedure TfrmMain.PartsEditorChanged(Sender: TObject);
begin
  if (Sender is TfrPartsEditor) and (TfrPartsEditor(Sender).Lib <> nil) and
     SameFileName(frameLibraryPanel.PartsFileName, TfrPartsEditor(Sender).Lib.FileName) then
    frameLibraryPanel.ReloadParts;
  UpdateDocTabs;
end;

{ ===========================================================================
  TfrmMain.ShowNoDocument  (procedure)
  Parameters:  none
  Notes:
    Goes to the state with no document open: shows the empty placeholder view and refreshes the
    window.
  =========================================================================== }
procedure TfrmMain.ShowNoDocument;
var
  i: Integer;
begin
  FCurrent := -1;
  if FDocs <> nil then
    for i := 0 to FDocs.Count - 1 do
    begin
      FDocs[i].View.Visible := False;
      if FDocs[i].PartsEditor <> nil then
        FDocs[i].PartsEditor.Visible := False;
    end;
  FPlaceholder.SetDesign(nil, 0);
  FPlaceholder.Visible := True;
  RefreshAfterDocumentChange;
end;

{ ===========================================================================
  TfrmMain.RefreshAfterDocumentChange  (procedure)
  Parameters:  none
  Notes:
    Brings everything that shows the current document up to date after a document was added,
    switched to or closed.
  =========================================================================== }
procedure TfrmMain.RefreshAfterDocumentChange;
begin
  if FFind <> nil then
    FFind.Reset;       // the last place found belongs to the other document
  RebuildSheetTabs;
  UpdateFormTitle;
  UpdatePaperStatus;
  UpdateRibbonState;
  RebuildProps;
  UpdateDocTabs;
  UpdateViewRulers;
end;

{ ===========================================================================
  TfrmMain.UpdateDocTabs  (procedure)
  Parameters:  none
  Notes:
    Makes the document tabs match the list of documents (names, modified marks, which one is
    current), shows the strip only while a document is open, and rebuilds the Window menu.
  =========================================================================== }
procedure TfrmMain.UpdateDocTabs;
var
  i: Integer;
begin
  if (tcDocs = nil) or (FDocs = nil) then
    Exit;
  FUpdatingTabs := True;
  try
    tcDocs.TabCount := FDocs.Count;
    for i := 0 to FDocs.Count - 1 do
      tcDocs.SetTab(i, FDocs[i].DisplayName, FDocs[i].Modified);
    tcDocs.TabIndex := FCurrent;
    tcDocs.Visible := FDocs.Count > 0;
  finally
    FUpdatingTabs := False;
  end;
  RebuildWindowMenu;
end;

{ ===========================================================================
  TfrmMain.RebuildWindowMenu  (procedure)
  Parameters:  none
  Notes:
    Brings the Window menu up to date. Its fixed items (next and previous document, close
    document, close all) are in the form file and only get enabled or dimmed; while any document
    is open a separator and one numbered entry per document (the current one ticked) are added
    after them, and with no document open they are all taken away again.
  =========================================================================== }
procedure TfrmMain.RebuildWindowMenu;
var
  i: Integer;
  Item: TMenuItem;

  function AddItem(const ACaption: String; AHandler: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(mWindow);
    Result.Caption := ACaption;
    Result.OnClick := AHandler;
    mWindow.Add(Result);
    FWindowDocItems.Add(Result);
  end;

begin
  if (mWindow = nil) or (FDocs = nil) then
    Exit;
  if FWindowDocItems = nil then
    FWindowDocItems := TList.Create;
  { the document entries of an earlier build (and the separator in front of them) go; the other items are the form's }
  for i := FWindowDocItems.Count - 1 downto 0 do
    TMenuItem(FWindowDocItems[i]).Free;
  FWindowDocItems.Clear;
  miNextDoc.Enabled := FDocs.Count > 1;
  miPrevDoc.Enabled := FDocs.Count > 1;
  miCloseDoc.Enabled := FDocs.Count > 0;
  miCloseAllDocs.Enabled := FDocs.Count > 0;
  if FDocs.Count = 0 then
    Exit;
  AddItem('-', nil);
  for i := 0 to FDocs.Count - 1 do
  begin
    if i < 9 then
      Item := AddItem('&' + IntToStr(i + 1) + ' ' + FDocs[i].TabCaption, @DoWindowItem)
    else
      Item := AddItem(FDocs[i].TabCaption, @DoWindowItem);
    Item.Tag := i;
    Item.GroupIndex := 1;
    Item.RadioItem := True;
    Item.Checked := (i = FCurrent);
  end;
end;

{ ===========================================================================
  TfrmMain.DocTabChange  (procedure)
  Parameters:
    Sender: TObject - the tab strip
  Notes:
    Event handler: another document tab was chosen, so show that document. Ignored while the
    tabs are being updated by the program.
  =========================================================================== }
procedure TfrmMain.DocTabChange(Sender: TObject);
begin
  if FUpdatingTabs then
    Exit;
  ActivateDocument(tcDocs.TabIndex);
end;

{ ===========================================================================
  TfrmMain.DocTabClose  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    Index: Integer - zero-based index
  Notes:
    Event handler: closes that document, asking about unsaved changes first (Cancel keeps it).
  =========================================================================== }
procedure TfrmMain.DocTabClose(Sender: TObject; Index: Integer);
begin
  CloseDocument(Index, True);
end;

{ ===========================================================================
  TfrmMain.DocumentCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    How many documents are open.
  =========================================================================== }
function TfrmMain.DocumentCount: Integer;
begin
  Result := FDocs.Count;
end;

{ ===========================================================================
  TfrmMain.DocumentIndex  (function)
  Parameters:  none
  Returns:
    Integer - its position, or -1 when none is open
  Notes:
    Which document is current.
  =========================================================================== }
function TfrmMain.DocumentIndex: Integer;
begin
  Result := FCurrent;
end;

{ ===========================================================================
  TfrmMain.DocumentCaption  (function)
  Parameters:
    Index: Integer - position in the list of documents
  Returns:
    String - the caption
  Notes:
    The tab caption of a document.
  =========================================================================== }
function TfrmMain.DocumentCaption(Index: Integer): String;
begin
  Result := FDocs[Index].TabCaption;
end;

{ ===========================================================================
  TfrmMain.WindowMenuText  (function)
  Parameters:  none
  Returns:
    String - one entry after another, separated by semicolons
  Notes:
    The Window menu as text (caption, ticked, enabled for each entry), for tests.
  =========================================================================== }
function TfrmMain.WindowMenuText: String;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to mWindow.Count - 1 do
    Result := Result + mWindow.Items[i].Caption + '|' + IntToStr(Ord(mWindow.Items[i].Checked)) + '|' + IntToStr(Ord(mWindow.Items[i].Enabled)) + ';';
end;

{ ===========================================================================
  TfrmMain.CloseDocument  (function)
  Parameters:
    Index: Integer - position in the list of documents
    Confirm: Boolean - True to ask about unsaved changes first
  Returns:
    Boolean - False if the user cancelled or the index is out of range
  Notes:
    Closes a document, with its view and design, and shows the one that takes its place (or the
    empty window when it was the last).
  =========================================================================== }
function TfrmMain.CloseDocument(Index: Integer; Confirm: Boolean): Boolean;
var
  NewIndex: Integer;
begin
  Result := False;
  if (FDocs = nil) or (Index < 0) or (Index >= FDocs.Count) then
    Exit;
  if Confirm and (not ConfirmCloseDocument(Index)) then
    Exit;
  { which one is shown afterwards: the one that took its place, or the one before it }
  if FCurrent > Index then
    NewIndex := FCurrent - 1
  else if FCurrent = Index then
    NewIndex := Index
  else
    NewIndex := FCurrent;
  if FDocs[Index] = FFindDoc then
    CloseFindPanel;      // its find results and red circles go with it
  if FDocs[Index] = FErcDoc then
    CloseErcWindow(False); // its design markers window goes with it (the markers go with the design)
  FCurrent := -1;                  // (FView must not point at the document being freed)
  FDocs.Delete(Index);
  if NewIndex >= FDocs.Count then
    NewIndex := FDocs.Count - 1;
  if NewIndex < 0 then
    ShowNoDocument
  else
    ActivateDocument(NewIndex);
  Result := True;
end;

{ ===========================================================================
  TfrmMain.SaveCurrentAs  (procedure)
  Parameters:
    const AFileName: String - the file to write
  Notes:
    Saves the current document under a name without asking, as Save As does once the file is
    chosen; it then has that name and no unsaved-changes mark.
  =========================================================================== }
procedure TfrmMain.SaveCurrentAs(const AFileName: String);
begin
  if FDesign = nil then
    Exit;
  FFileName := ExpandFileName(AFileName);
  DoSave(nil);
end;

{ ===========================================================================
  TfrmMain.DoDesignDetails  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler (button, Ctrl+D): shows the Design Details dialog for the current sheet. OK applies
    it; Apply applies it and leaves the dialog open.
  =========================================================================== }
procedure TfrmMain.DoDesignDetails(Sender: TObject);
var
  F: TfrmDetails;
begin
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  F := TfrmDetails.Create(Self);
  try
    F.LoadFromSheet(FView.Sheet, FDesign, FView.SheetIndex);
    F.OnApplyRequest := @DetailsApplyRequest;
    F.OnApplyAllRequest := @DetailsApplyAllRequest;
    if F.ShowModal = mrOK then
      ApplyDesignDetails(F);
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.DetailsApplyRequest  (procedure)
  Parameters:
    Sender: TObject - the dialog
  Notes:
    Event handler for the Apply button of the Design Details dialog: applies its values to the
    sheet while the dialog stays open.
  =========================================================================== }
procedure TfrmMain.DetailsApplyRequest(Sender: TObject);
begin
  ApplyDesignDetails(Sender as TfrmDetails);
end;

{ ===========================================================================
  TfrmMain.DetailsApplyAllRequest  (procedure)
  Parameters:
    Sender: TObject - the dialog
  Notes:
    Event handler for the Apply to All button of the Design Details dialog: the sheet gets all
    of the dialog's values (as Apply does) and every other sheet gets those of the Details tab.
  =========================================================================== }
procedure TfrmMain.DetailsApplyAllRequest(Sender: TObject);
begin
  ApplyDetailsTabToAll(Sender as TfrmDetails);
end;

{ ===========================================================================
  TfrmMain.ApplyDetailsTabToAll  (function)
  Parameters:
    F: TfrmDetails - the dialog
  Returns:
    Boolean - True if something changed
  Notes:
    One undo step named "Design details (all sheets)": the current sheet takes everything the
    dialog holds, every other sheet only the settings of the Details tab (title, author,
    organisation, document number, date, sheet numbering, title block and extended information
    shown). Nothing is recorded if no value changed.
  =========================================================================== }
function TfrmMain.ApplyDetailsTabToAll(F: TfrmDetails): Boolean;
var
  i: Integer;
begin
  Result := False;
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  FView.BeginChange(rsDesignDetailsAllSheets);
  for i := 0 to FDesign.SheetCount - 1 do
    if FDesign.Sheets[i] = FView.Sheet then
    begin
      if F.SaveToSheet(FDesign.Sheets[i]) then
        Result := True;
    end
    else if F.SaveDetailsTab(FDesign.Sheets[i]) then
      Result := True;
  FView.CommitChange(Result);
  if Result then
  begin
    for i := 0 to FDesign.SheetCount - 1 do
      FDesign.Sheets[i].UpdateLayout;
    FView.RelayoutAll;
    UpdatePaperStatus;
  end;
end;

{ ===========================================================================
  TfrmMain.ApplyDesignDetails  (function)
  Parameters:
    F: TfrmDetails - the dialog
  Returns:
    Boolean - True if something changed
  Notes:
    Applies what a Design Details dialog holds to the current sheet as one undo step named
    "Design details", then re-lays out the sheet (text can show title block variables) and
    updates the paper status. Nothing is recorded if no value changed.
  =========================================================================== }
function TfrmMain.ApplyDesignDetails(F: TfrmDetails): Boolean;
begin
  Result := False;
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  FView.BeginChange(rsDesignDetails2);
  Result := F.SaveToSheet(FView.Sheet);
  FView.CommitChange(Result);
  if Result then
  begin
    FView.RelayoutAll;          // text that shows title block variables
    UpdatePaperStatus;
  end;
end;

{ ===========================================================================
  TfrmMain.DoPageSetup  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler: shows the Page Setup dialog for the current sheet and applies it on OK.
  =========================================================================== }
procedure TfrmMain.DoPageSetup(Sender: TObject);
var
  F: TfrmPageSetup;
begin
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  F := TfrmPageSetup.Create(Self);
  try
    F.OnPrinterPage := @PrinterPageFor;
    F.LoadFromSheet(FView.Sheet);
    if F.ShowModal = mrOK then
      ApplyPageSetup(F);
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.ApplyPageSetup  (function)
  Parameters:
    F: TfrmPageSetup - the dialog
  Returns:
    Boolean - True if a page size changed
  Notes:
    Applies the dialog's page size to the current sheet, or to every sheet when "Use for all
    sheets" is ticked, as one undo step named "Page setup"; the page is then fitted to the
    window again. Refused (nothing changes) when the size is not valid.
  =========================================================================== }
function TfrmMain.ApplyPageSetup(F: TfrmPageSetup): Boolean;
var
  i, W, H: Integer;
  procedure SetSheet(Sh: TDesignSheet);
  begin
    if (Sh.Details.PageWidth <> W) or (Sh.Details.PageHeight <> H) then
    begin
      Sh.Details.PageWidth := W;
      Sh.Details.PageHeight := H;
      Result := True;
    end;
  end;
begin
  Result := False;
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  if F.ValidationError <> '' then
    Exit;
  W := F.PageWidthUnits;
  H := F.PageHeightUnits;
  FView.BeginChange(rsPageSetup2);
  if F.ApplyToAllSheets then
    for i := 0 to FDesign.SheetCount - 1 do SetSheet(FDesign.Sheets[i])
  else
    SetSheet(FView.Sheet);
  FView.CommitChange(Result);
  if Result then
  begin
    FView.RelayoutAll;
    FView.ZoomFit;
    UpdatePaperStatus;
  end;
end;

{ ===========================================================================
  TfrmMain.FormKeyDown  (procedure)
  Parameters:
    Sender: TObject - the form
    var Key: Word - the key code (set to 0 when handled)
    Shift: TShiftState - modifier keys
  Notes:
    Key handler for the whole window: Ctrl+D opens Design Details, as in TinyCAD.
  =========================================================================== }
procedure TfrmMain.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  { Del in a text box: the form sees the key first and the Delete menu's shortcut would take it from the box (deleting the object);
    the mark makes DoDelete edit the text instead. A plain Del only: Shift or Ctrl with it are the box's own (cut) }
  FDelKeyInEdit := (Key = VK_DELETE) and (Shift = []) and (ActiveControl <> nil) and (ActiveControl is TWinControl) and
    ((ActiveControl is TCustomEdit) or (ActiveControl is TCustomMemo) or (ActiveControl is TCustomComboBox));
  { the reference box of a chosen symbol took the focus by itself, with all its text selected: Del then deletes the symbol, not the text; once the
    person has clicked in the box, typed or moved the caret, Del edits the text }
  if FDelKeyInEdit and (ActiveControl is TEdit) and (ActiveControl = FRefAutoEdit) and (TEdit(ActiveControl).Text = FRefAutoText) and
     (FRefAutoText <> '') and (TEdit(ActiveControl).SelStart = 0) and (TEdit(ActiveControl).SelLength = UTF8Length(FRefAutoText)) then
    FDelKeyInEdit := False;
  { Ctrl+C/X/V/A/Z/Y in a text box: the Edit menu's shortcut would take the key from the box (and paste, say, into the drawing); the mark makes the command work on the text }
  FEditKey := #0;
  if (Shift = [ssCtrl]) and (Key in [VK_C, VK_X, VK_V, VK_A, VK_Z, VK_Y]) and (ActiveControl <> nil) and
     ((ActiveControl is TCustomEdit) or (ActiveControl is TCustomMemo)) then
    FEditKey := Chr(Key);
  { Esc drops the drawing tool when the focus is somewhere else than on the sheet (the tool's own text box, say); the sheet handles its own Esc, which first ends what is being drawn }
  if (Key = VK_ESCAPE) and (Shift = []) and (FView <> nil) and (FView.Tool <> vtSelect) and (ActiveControl <> FView) then
  begin
    Key := 0;
    FView.CancelTool;
    Exit;
  end;
  { Ctrl+F is Find (the panel that lists everything found), Ctrl+H is Find and Replace; F3 finds the next, Shift+F3 the previous }
  if (FDesign <> nil) and (Key = VK_F) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    DoFind(nil);
    Exit;
  end;
  if (FDesign <> nil) and (Key = VK_I) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    DoImport(nil);
    Exit;
  end;
  if (FDesign <> nil) and (Key = VK_E) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    DoCopyTo(nil);
    Exit;
  end;
  if (FDesign <> nil) and (Key = VK_H) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    DoFindReplace(nil);
    Exit;
  end;
  if (FDesign <> nil) and (Key = VK_F3) and ((Shift = []) or (Shift = [ssShift])) then
  begin
    if Shift = [] then
      DoFindNext(nil)
    else
      DoFindPrevious(nil);
    Key := 0;
    Exit;
  end;
  { Ctrl+D is Design Details, as in TinyCAD }
  if (Key = VK_D) and (Shift = [ssCtrl]) and (FDesign <> nil) then
  begin
    Key := 0;
    DoDesignDetails(nil);
  end;
end;

{ ===========================================================================
  TfrmMain.DetailsInfoText  (function)
  Parameters:  none
  Returns:
    String - the text, or "no document"
  Notes:
    The current sheet's details on one line (title, author, organisation, document number,
    revision, date, sheets, automatic numbering, title block shown, rulers and their counts,
    border and margin, revision count, page size), for tests.
  =========================================================================== }
function TfrmMain.DetailsInfoText: String;
var
  D: TDetails;
begin
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit('no document');
  D := FView.Sheet.Details;
  Result := Format('title=%s|author=%s|org=%s|docno=%s|revision=%s|date=%s|sheets=%s|auto=%d|visible=%d|rulers=%d|h=%d|v=%d|border=%d|margin=%.3f|revs=%d|page=%dx%d|ext=%d|sortrev=%d|notes=%s|reference=%s',
    [D.Title, D.Author, D.Org, D.DocNo, D.EffectiveRevision, D.LastChange, D.Sheets, Ord(D.AutoSheets), Ord(D.IsVisible), Ord(D.HasRulers),
     D.HorizRulerSize, D.VertRulerSize, Ord(D.ShowBorder), D.BorderMargin, Length(D.Revisions), D.PageWidth, D.PageHeight, Ord(D.ExtendedInfo), Ord(D.SortByRevision),
     StringReplace(D.Notes, #10, '\n', [rfReplaceAll]), StringReplace(D.Reference, #10, '\n', [rfReplaceAll])], DefaultFormatSettings);
end;

{ ===========================================================================
  TfrmMain.ReportProblem  (procedure)
  Parameters:
    const Msg: String - the message
  Notes:
    Tells the person something went wrong: a warning box, or, when the program is run from a
    script (quiet), the status bar's first panel, so that scripts and tests can read it.
  =========================================================================== }
procedure TfrmMain.ReportProblem(const Msg: String);
begin
  if FQuiet then
    sbMainBar.Panels[0].Text := Msg
  else
    MessageDlg(lAppName, Msg, mtWarning, [mbOK], 0);
end;

{ ===========================================================================
  TfrmMain.RebuildRecentMenu  (procedure)
  Parameters:  none
  Notes:
    The recently used files go in the File menu between Save As and Exit: a separator, then 1 to
    4 entries
  =========================================================================== }
procedure TfrmMain.RebuildRecentMenu;
  function Short(const AName: String): String;
  begin
    if Length(AName) <= 56 then
      Result := AName
    else
      Result := Copy(AName, 1, 18) + '...' + Copy(AName, Length(AName) - 34, 35);
  end;
var
  i, At: Integer;
  Item: TMenuItem;
begin
  if (FRecentItems = nil) or (mFile = nil) then
    Exit;
  for i := FRecentItems.Count - 1 downto 0 do TMenuItem(FRecentItems[i]).Free;
  FRecentItems.Clear;
  if MRUCount = 0 then
    Exit;
  At := mFile.IndexOf(mSep1);
  if At < 0 then
    At := mFile.Count;
  Item := TMenuItem.Create(mFile);
  Item.Caption := '-';
  mFile.Insert(At, Item);
  FRecentItems.Add(Item);
  for i := 0 to MRUCount - 1 do
  begin
    Item := TMenuItem.Create(mFile);
    Item.Caption := '&' + IntToStr(i + 1) + ' ' + Short(MRUFile(i));
    Item.Hint := MRUFile(i);
    Item.Tag := i;
    Item.OnClick := @DoOpenRecent;
    mFile.Insert(At + 1 + i, Item);
    FRecentItems.Add(Item);
  end;
end;

{ ===========================================================================
  TfrmMain.NoteFileUsed  (procedure)
  Parameters:
    const AFileName: String - the file
  Notes:
    Records that a file was opened or saved: it goes to the top of the recently used files, the
    list is saved to the registry, and the File menu entries are rebuilt.
  =========================================================================== }
procedure TfrmMain.NoteFileUsed(const AFileName: String);
begin
  MRUAdd(AFileName);
  SaveSettings;
  RebuildRecentMenu;
end;

{ ===========================================================================
  TfrmMain.DoOpenRecent  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Click handler of the recently used files in the File menu: opens the file the item stands
    for (its number is in the item's Tag).
  =========================================================================== }
procedure TfrmMain.DoOpenRecent(Sender: TObject);
begin
  OpenRecentFile((Sender as TMenuItem).Tag);
end;

{ ===========================================================================
  TfrmMain.OpenRecentFile  (procedure)
  Parameters:
    Index: Integer - position in the list, 0 for the newest
  Notes:
    Opens the n-th recently used file as a document, as choosing it in the File menu does. A
    file that is no longer there is not opened: it is taken off the list (and the registry), and
    a message says so. Any other error opening it is reported and the list is left alone.
  =========================================================================== }
procedure TfrmMain.OpenRecentFile(Index: Integer);
var
  Path: String;
begin
  Path := MRUFile(Index);
  if Path = '' then
    Exit;
  if not FileExists(Path) then
  begin
    ReportProblem(Format(rsTheFileIsNoLonger, [Path]));
    MRURemove(Path);
    SaveSettings;
    RebuildRecentMenu;
    Exit;
  end;
  try
    OpenDesignFile(Path);
  except
    on E: Exception do ReportProblem(Format(rsCannotOpen2, [Path, E.Message]));
  end;
end;

{ ===========================================================================
  TfrmMain.RecentMenuText  (function)
  Parameters:  none
  Returns:
    String - the entries, each followed by a semicolon; the separator shows as "-"
  Notes:
    The File menu entries made from the recently used files, as text (caption, then the full
    file name, for each), for tests.
  =========================================================================== }
function TfrmMain.RecentMenuText: String;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to FRecentItems.Count - 1 do
    Result := Result + TMenuItem(FRecentItems[i]).Caption + '|' + TMenuItem(FRecentItems[i]).Hint + ';';
end;

{ ===========================================================================
  TfrmMain.FindMessage  (procedure)
  Parameters:
    const Msg: String - the message
  Notes:
    Puts a message in the status bar.
  =========================================================================== }

{ ===========================================================================
  TfrmMain.DoFind  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The find panel replaces the library panel in the left panel until it is closed
  =========================================================================== }
procedure TfrmMain.DoFind(Sender: TObject);
begin
  if FDesign = nil then
    Exit;
  frameLibraryPanel.Visible := False;
  frameFindPanel.Visible := True;
  frameFindPanel.FocusEntry;
end;

{ ===========================================================================
  TfrmMain.CloseFindPanel  (procedure)
  Parameters:  none
  Notes:
    Close the find: the red circles go, and the library panel comes back
  =========================================================================== }
procedure TfrmMain.CloseFindPanel;
var
  i: Integer;
begin
  if (FFindDoc <> nil) and (FDocs <> nil) then
    for i := 0 to FDocs.Count - 1 do
      if FDocs[i] = FFindDoc then
        FFindDoc.View.ClearMarkers;
  FFindDoc := nil;
  SetLength(FFindHits, 0);
  frameFindPanel.ClearResults(' ');
  frameFindPanel.Visible := False;
  frameLibraryPanel.Visible := True;
end;

{ ===========================================================================
  TfrmMain.FindPanelClose  (procedure)
  Parameters:
    Sender: TObject - the panel
  Notes:
    Event handler: the find panel's red X (or Esc) was pressed, so close the find.
  =========================================================================== }
procedure TfrmMain.FindPanelClose(Sender: TObject);
begin
  CloseFindPanel;
end;

{ ===========================================================================
  TfrmMain.FindPanelFind  (procedure)
  Parameters:
    Sender: TObject - the panel
  Notes:
    Event handler: Enter or the Find button of the find panel, so search for the text in its
    entry.
  =========================================================================== }
procedure TfrmMain.FindPanelFind(Sender: TObject);
begin
  RunFindPanel(frameFindPanel.FindText);
end;

{ TinyCAD's Find (CTinyCadView::OnFindFind): every object of the design (all sheets) that mentions the text is listed as
  "<name>: <the text found>", and gets a red circle on the sheet }

{ ===========================================================================
  TfrmMain.RunFindPanel  (procedure)
  Parameters:
    const AText: String - the text to look for
  Notes:
    TinyCAD's Find: lists every object that mentions the text, once each, as "sheet name: object:
    text" ("Sheet 2: Label: VCC"), in every sheet of the design when the panel's Search all Sheets box
    is ticked and only in the sheet shown when it is not; puts a red circle on each, and shows how many were found. Nothing is
    chosen. A find made in another document earlier loses its circles.
  =========================================================================== }
procedure TfrmMain.RunFindPanel(const AText: String);
var
  Items: TStringList;
  Marks: array of TFindMarker;
  i, Kept: Integer;
begin
  if FDesign = nil then
    Exit;
  frameFindPanel.FindText := AText;
  if (FFindDoc <> nil) and (FFindDoc <> CurDoc) then
    CloseFindDocMarkers;
  if AText = '' then
    Exit;
  FFindDoc := CurDoc;
  FFindHits := FindObjects(FDesign, AText);
  if not frameFindPanel.FindInAll then
  begin
    { "Search all Sheets" not ticked: only what is on the sheet shown }
    Kept := 0;
    for i := 0 to High(FFindHits) do
      if FFindHits[i].Sheet = FView.SheetIndex then
      begin
        FFindHits[Kept] := FFindHits[i];
        Inc(Kept);
      end;
    SetLength(FFindHits, Kept);
  end;
  Items := TStringList.Create;
  try
    SetLength(Marks, Length(FFindHits));
    for i := 0 to High(FFindHits) do
    begin
      Items.Add(SheetTabCaption(FFindHits[i].Sheet) + ': ' + FFindHits[i].Name + ': ' + StringReplace(StringReplace(FFindHits[i].Text, #13, '', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
      Marks[i].Sheet := FFindHits[i].Sheet;
      Marks[i].Point := FFindHits[i].Point;
    end;
    FView.SetMarkers(Marks);
    if Length(FFindHits) = 0 then
    begin
      frameFindPanel.SetResults(Items, rsNotFound);
      FindMessage(Format(rsCannotFind, [AText]));
    end
    else
    begin
      frameFindPanel.SetResults(Items, Format(rsFound, [Length(FFindHits)]));
      FindMessage(Format(rsFound2, [Length(FFindHits)]));
    end;
  finally
    Items.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.CloseFindDocMarkers  (procedure)
  Parameters:  none
  Notes:
    Take away the red circles of an earlier find in another document
  =========================================================================== }
procedure TfrmMain.CloseFindDocMarkers;
var
  i: Integer;
begin
  for i := 0 to FDocs.Count - 1 do
    if FDocs[i] = FFindDoc then
      FFindDoc.View.ClearMarkers;
  FFindDoc := nil;
end;

{ ===========================================================================
  TfrmMain.FindPanelResultSelected  (procedure)
  Parameters:
    Sender: TObject - the panel
    Index: Integer - the entry
  Notes:
    Event handler: an entry of the find list was clicked.
  =========================================================================== }
procedure TfrmMain.FindPanelResultSelected(Sender: TObject; Index: Integer);
begin
  ChooseFindResult(Index);
end;

{ ===========================================================================
  TfrmMain.ChooseFindResult  (procedure)
  Parameters:
    Index: Integer - zero-based index
  Notes:
    An entry of the list was chosen: show the sheet with the red circle of that entry, bright
    red, in the middle of the window
  =========================================================================== }
procedure TfrmMain.ChooseFindResult(Index: Integer);
var
  H: TObjectHit;
  At: Integer;
begin
  if (FFindDoc = nil) or (Index < 0) or (Index > High(FFindHits)) then
    Exit;
  At := FDocs.IndexOf(FFindDoc);
  if At < 0 then
    Exit;
  if At <> FCurrent then
    ActivateDocument(At);
  H := FFindHits[Index];
  FView.BeginTool(vtSelect);                 // (as TinyCAD does, any drawing tool is put away first)
  if H.Sheet <> FView.SheetIndex then
  begin
    tcSheetTabs.TabIndex := H.Sheet;         // as clicking that sheet's tab
    SheetTabChange(tcSheetTabs);
  end;
  FView.ClearSelection;
  FView.SelectMarker(Index);
  FView.CenterOnPoint(H.Point);
end;

{ ===========================================================================
  TfrmMain.FindMarkerClicked  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    Index: Integer - zero-based index
  Notes:
    A red circle was clicked on the sheet: its entry in the list is chosen
  =========================================================================== }
procedure TfrmMain.FindMarkerClicked(Sender: TObject; Index: Integer);
begin
  frameFindPanel.SelectResult(Index);
end;

{ ===========================================================================
  TfrmMain.FindHitsText  (function)
  Parameters:  none
  Returns:
    String - the text
  Notes:
    Where each red circle is, as text, for tests: the size of the window, then for each its
    sheet, its position in mm, and its place in the window.
  =========================================================================== }
function TfrmMain.FindHitsText: String;
var
  i: Integer;
  Sc: TPoint;
begin
  { where each red circle is, for tests: the size of the window, then for each its sheet, its position in mm and (for the sheet shown)
    its place in the window }
  Result := Format('%dx%d ', [FView.ClientWidth, FView.ClientHeight]);
  for i := 0 to High(FFindHits) do
  begin
    Sc := FView.DesignToScreen(FFindHits[i].Point);
    Result := Result + Format('%d:%d:%.3f:%.3f:%d:%d;', [i, FFindHits[i].Sheet, FFindHits[i].Point.x / 5, FFindHits[i].Point.y / 5, Sc.x, Sc.y], DefaultFormatSettings);
  end;
end;

{ ===========================================================================
  TfrmMain.FindPanelText  (function)
  Parameters:  none
  Returns:
    String - the text
  Notes:
    The find panel as text, for tests: whether it is shown, the text searched for, the count,
    which entry and circle are chosen, how many circles the view has, which document the find
    belongs to, where the close button is and which picture it shows, and the entries.
  =========================================================================== }
function TfrmMain.FindPanelText: String;
var
  i: Integer;
begin
  { the panel as text, for tests: whether it is shown, the entry and the count, the chosen entry, and the entries }
  Result := Format('shown=%d library=%d text=%s count=%s chosen=%d marker=%d markers=%d doc=%d',
    [Ord(frameFindPanel.Visible), Ord(frameLibraryPanel.Visible), frameFindPanel.FindText, frameFindPanel.lblCount.Caption,
     frameFindPanel.SelectedResult, FView.MarkerSelected, FView.MarkerCount, FDocs.IndexOf(FFindDoc)]);
  with frameFindPanel.btnClose do
    Result := Result + Format(' closebtn=%d,%d,%d,%d visible=%d image=%d panel=%dx%d', [Left, Top, Width, Height, Ord(Visible), ImageIndex,
      frameFindPanel.Width, frameFindPanel.Height]);
  for i := 0 to frameFindPanel.ResultCount - 1 do Result := Result + ' [' + frameFindPanel.ResultText(i) + ']';
end;

{ ===========================================================================
  TfrmMain.FindMessage  (procedure)
  Parameters:
    const Msg: String - the message
  Notes:
    Puts a message in the status bar.
  =========================================================================== }

{ ===========================================================================
  TfrmMain.DoCopyTo  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler (Ctrl+E): Copy to. Asks for a file name (the Design files filter, .dsn added if left
    off, asking before an existing file is replaced) and saves the selected objects there as a
    design file of their own. Nothing happens with nothing selected. The Save dialog's settings
    are put back afterwards, so Save As is not affected.
  =========================================================================== }
procedure TfrmMain.DoCopyTo(Sender: TObject);
var
  OldFilter, OldTitle, OldExt, OldName: String;
  OldOptions: TOpenOptions;
  Target: String;
begin
  if (FDesign = nil) or (FView.SelectedCount = 0) then
    Exit;       // as in TinyCAD, only with something selected
  OldFilter := SaveDlg.Filter; OldTitle := SaveDlg.Title; OldExt := SaveDlg.DefaultExt;
  OldName := SaveDlg.FileName; OldOptions := SaveDlg.Options;
  try
    SaveDlg.Title := rsCopyTheSelectionTo;
    SaveDlg.Filter := rsDesignFilesDsnDsnAll;
    SaveDlg.DefaultExt := 'dsn';
    SaveDlg.FileName := '';
    SaveDlg.Options := SaveDlg.Options + [ofOverwritePrompt, ofHideReadOnly];
    if not SaveDlg.Execute then
      Exit;
    Target := SaveDlg.FileName;
  finally
    SaveDlg.Filter := OldFilter; SaveDlg.Title := OldTitle; SaveDlg.DefaultExt := OldExt;
    SaveDlg.FileName := OldName; SaveDlg.Options := OldOptions;
  end;
  if ExtractFileExt(Target) = '' then
    Target := Target + '.dsn';
  CopySelectionTo(Target);
end;

{ ===========================================================================
  TfrmMain.CopySelectionTo  (function)
  Parameters:
    const AFileName: String - the file to write
  Returns:
    Integer - how many objects were written, 0 if none
  Notes:
    Copy to without the dialog: saves the selected objects of the current sheet as a design file
    and says in the status bar how many were written. If nothing is selected, or the file cannot
    be written, nothing is written (an existing file is left as it was); an error is reported
    rather than raised.
  =========================================================================== }
function TfrmMain.CopySelectionTo(const AFileName: String): Integer;
begin
  Result := 0;
  if (FDesign = nil) or (FView.SelectedCount = 0) then
    Exit;
  try
    Result := FView.CopySelectionToFile(AFileName);
  except
    on E: Exception do
    begin
      ReportProblem(Format(rsCannotWrite2, [AFileName, E.Message]));
      Exit;
    end;
  end;
  if Result = 0 then
    FindMessage(rsThereIsNothingToCopy)
  else if Result = 1 then
    FindMessage(Format(rsCopiedObjectTo, [AFileName]))
  else
    FindMessage(Format(rsCopiedObjectsTo, [Result, AFileName]));
end;

{ ===========================================================================
  TfrmMain.DoImport  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler (Ctrl+I): Import. Asks for a design file (the Design files filter) and brings its
    first sheet into this sheet as a block that follows the mouse until it is placed. The Open
    dialog's settings are put back afterwards, so Open is not affected.
  =========================================================================== }
procedure TfrmMain.DoImport(Sender: TObject);
var
  OldFilter, OldTitle, OldName, Target: String;
  OldOptions: TOpenOptions;
begin
  if FDesign = nil then
    Exit;
  OldFilter := OpenDlg.Filter; OldTitle := OpenDlg.Title; OldName := OpenDlg.FileName; OldOptions := OpenDlg.Options;
  Target := '';
  try
    OpenDlg.Title := rsImportADesign;
    OpenDlg.Filter := rsDesignFilesDsnDsnAll;
    OpenDlg.FileName := '';
    OpenDlg.Options := OpenDlg.Options - [ofAllowMultiSelect];        // one design at a time
    if OpenDlg.Execute then
      Target := OpenDlg.FileName;
  finally
    OpenDlg.Filter := OldFilter; OpenDlg.Title := OldTitle; OpenDlg.FileName := OldName; OpenDlg.Options := OldOptions;
  end;
  if Target <> '' then
    ImportDesign(Target);
end;

{ ===========================================================================
  TfrmMain.ImportDesign  (function)
  Parameters:
    const AFileName: String - the design file
  Returns:
    Integer - how many objects were read, 0 if none
  Notes:
    Import without the dialog: puts any drawing tool away and clears the selection (as TinyCAD
    does), then reads the design into this sheet as a block that follows the mouse. A file that
    cannot be opened is reported; one that is not a TinyCAD design that can be imported (not
    XML, empty) is reported and changes nothing.
  =========================================================================== }
function TfrmMain.ImportDesign(const AFileName: String): Integer;
begin
  Result := 0;
  if FDesign = nil then
    Exit;
  FView.BeginTool(vtSelect);                // (as TinyCAD does, any drawing tool is put away and the selection cleared first)
  FView.ClearSelection;
  try
    Result := FView.ImportFromFile(AFileName);
  except
    on E: Exception do
    begin
      ReportProblem(Format(rsCannotOpen2, [AFileName, E.Message]));
      Exit;
    end;
  end;
  if Result = 0 then
    ReportProblem(Format(rsIsNotATinyCADDesign, [AFileName]));
end;

{ ===========================================================================
  TfrmMain.DoInsertPicture  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler: Insert picture. Asks for a PNG, JPEG or BMP file (the Open dialog's settings are
    put back afterwards) and inserts it as a picture that follows the mouse until it is placed.
  =========================================================================== }
procedure TfrmMain.DoInsertPicture(Sender: TObject);
var
  OldFilter, OldTitle, OldName, Target: String;
  OldOptions: TOpenOptions;
begin
  if FDesign = nil then
    Exit;
  OldFilter := OpenDlg.Filter; OldTitle := OpenDlg.Title; OldName := OpenDlg.FileName; OldOptions := OpenDlg.Options;
  Target := '';
  try
    OpenDlg.Title := rsInsertAPicture;
    OpenDlg.Filter := rsPicturesPngJpgJpegJpe;
    OpenDlg.FileName := '';
    OpenDlg.Options := OpenDlg.Options - [ofAllowMultiSelect];
    if OpenDlg.Execute then
      Target := OpenDlg.FileName;
  finally
    OpenDlg.Filter := OldFilter; OpenDlg.Title := OldTitle; OpenDlg.FileName := OldName; OpenDlg.Options := OldOptions;
  end;
  if Target <> '' then
    InsertPicture(Target);
end;

{ ===========================================================================
  TfrmMain.InsertPicture  (function)
  Parameters:
    const AFileName: String - the picture file
  Returns:
    Boolean - True if the picture was inserted
  Notes:
    Insert picture without the dialog: puts any drawing tool away and clears the selection, then
    inserts the file as a picture that follows the mouse. A file that cannot be inserted (not a
    picture, missing, damaged, a Windows metafile) is reported and changes nothing.
  =========================================================================== }
function TfrmMain.InsertPicture(const AFileName: String): Boolean;
var
  Err: String;
begin
  Result := False;
  if FDesign = nil then
    Exit;
  FView.BeginTool(vtSelect);                // (any drawing tool is put away and the selection cleared first)
  FView.ClearSelection;
  try
    Result := FView.InsertPictureFile(AFileName, Err);
  except
    on E: Exception do
    begin
      ReportProblem(Format(rsCannotInsert, [AFileName, E.Message]));
      Exit;
    end;
  end;
  if not Result then
    ReportProblem(Err);
end;

{ ===========================================================================
  The Position bar (TinyCAD's View > Show Position): the pointer's position, a snap button, a button that goes through the standard grid sizes, and the grid size and its
  units. It is brought up to date whenever the ribbon is (every change of the grid, of the snap, of the sheet or of the units goes through UpdateRibbonState).
  =========================================================================== }

{ ===========================================================================
  TfrmMain.ViewPosition  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    const Msg: String - the message
  Notes:
    The position goes to the bar when it is shown, and to the status message when it is hidden,
    so that it can always be seen somewhere.
  =========================================================================== }
procedure TfrmMain.ViewPosition(Sender: TObject; const Msg: String);
begin
  if pnlPosition.Visible then
    lblPosition.Caption := Msg
  else
    sbMainBar.Panels[1].Text := Msg;
end;

{ ===========================================================================
  TfrmMain.ShowPositionBar  (procedure)
  Parameters:
    AShow: Boolean - flag
    Keep: Boolean - flag
  Notes:
    Shows or hides the bar and brings the View menu item and the ribbon button into line with
    it.
  =========================================================================== }
procedure TfrmMain.ShowPositionBar(AShow, Keep: Boolean);
begin
  pnlPosition.Visible := AShow;
  mShowPosition.Checked := AShow;
  FShowingPosition := True;
  try
//    cbViewPositionShow.Checked := AShow;      // (its OnChange is DoShowPosition: not a request now)
    sbView.Checked := AShow;      // (setting it in code is not a click)
  finally
    FShowingPosition := False;
  end;
  miShowPositionBar.Checked := AShow;
  if AShow then
    sbMainBar.Panels[1].Text := '';
  if Keep then
  begin
    ProgramSettings.ShowPosition := AShow;
    SaveSettings;
  end;
  UpdatePositionBar;
end;

{ ===========================================================================
  TfrmMain.DoShowPosition  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler (View > Show Position, the ribbon): shows the bar if it is hidden and hides it if it
    is shown. The choice is kept for the next run.
  =========================================================================== }
procedure TfrmMain.DoShowPosition(Sender: TObject);
begin
  if FShowingPosition then
    Exit;
  if Sender = sbView then
    ShowPositionBar(sbView.Checked, True)      // (the button turned over by itself on the click: it says what is wanted)
  else
    ShowPositionBar(not pnlPosition.Visible, True);
end;

{ ===========================================================================
  TfrmMain.ShowViewRulers  (procedure)
  Parameters:
    AShow: Boolean - flag
    Keep: Boolean - flag
  Notes:
    Turns the rulers along the top and left of the drawing area on or off and brings the View
    menu item and the ribbon's check box into line with it. They are only seen while a document
    is open (UpdateViewRulers).
  =========================================================================== }
procedure TfrmMain.ShowViewRulers(AShow, Keep: Boolean);
begin
  FRulersWanted := AShow;
  miShowViewRulers.Checked := AShow;
  FShowingRulers := True;
  try
//    cbShowViewRulers.Checked := AShow;      // (its OnChange is DoShowViewRulers: not a request now)
    miAlignShowRulers.Checked := AShow;
  finally
    FShowingRulers := False;
  end;
  if Keep then
  begin
    ProgramSettings.ShowViewRulers := AShow;
    SaveSettings;
  end;
  UpdateViewRulers;
end;

{ ===========================================================================
  TfrmMain.RulerUnitsPopup  (procedure)
  Parameters:
    Sender: TObject - the ruler menu
  Notes:
    The menu of the rulers (right click on a ruler): the units the rulers show now are ticked.
  =========================================================================== }
procedure TfrmMain.RulerUnitsPopup(Sender: TObject);
var
  U: Integer;
begin
  U := UNITS_MM;
  if (FDesign <> nil) and (FView.Sheet <> nil) then
    U := FView.Sheet.Options.Units;
  U := RulerUnitsFor(U);
  miRulerMM.Checked := U = UNITS_MM;
  miRulerIN.Checked := U = UNITS_INCHES;
end;

{ ===========================================================================
  TfrmMain.DoRulerUnits  (procedure)
  Parameters:
    Sender: TObject - the millimetres or the inches item of the ruler menu
  Notes:
    The rulers show the chosen units from now on (and at the next start): the grid and the position bar keep the sheet's units. The choice is the same one Options > Sheets >
    Ruler Units makes.
  =========================================================================== }
procedure TfrmMain.DoRulerUnits(Sender: TObject);
begin
  if Sender = miRulerIN then
    ProgramSettings.RulerUnits := UNITS_INCHES
  else
    ProgramSettings.RulerUnits := UNITS_MM;
  SaveSettings;
  UpdateViewRulers;
end;

{ ===========================================================================
  TfrmMain.DoShowViewRulers  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler: shows the rulers if they are hidden and hides them if they are shown. The choice is
    kept for the next run.
  =========================================================================== }
procedure TfrmMain.DoShowViewRulers(Sender: TObject);
begin
  if FShowingRulers then
    Exit;
  if Sender = miAlignShowRulers {cbShowViewRulers} then
    begin
      miAlignShowRulers.Checked := not miAlignShowRulers.Checked;
      ShowViewRulers(miAlignShowRulers.Checked {cbShowViewRulers.Checked}, True)      // (the check box says what is wanted)
    end
  else
    ShowViewRulers(not FRulersWanted, True);
end;

{ ===========================================================================
  TfrmMain.UpdateViewRulers  (procedure)
  Parameters:  none
  Notes:
    Points both rulers at the current document's view and shows them if they are wanted and a
    document is open. The view gets the room that is left when they come or go and fits the page
    again if it was showing the whole page.
  =========================================================================== }
procedure TfrmMain.UpdateViewRulers;
var
  Want: Boolean;
begin
  if FRulerTop = nil then
    Exit;
  Want := FRulersWanted and (FDesign <> nil);
  FRulerTop.View := FView;
  FRulerLeft.View := FView;
  if FRulerTop.Visible <> Want then
  begin
    FRulerTop.Visible := Want;
    FRulerLeft.Visible := Want;
  end;
  FRulerTop.Sync;
  FRulerLeft.Sync;
end;

{ ===========================================================================
  TfrmMain.ArcTypeChangedByView  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The Arc tool's kind of arc changed (its menu, or the turn after each arc drawn): the in /
    out buttons of its panel show it.
  =========================================================================== }
procedure TfrmMain.ArcTypeChangedByView(Sender: TObject);
begin
  if (Sender = FView) and (FToolPanel <> nil) and (FToolOf = vtArc) then
    ShowToolPropValues;
end;

{ ===========================================================================
  TfrmMain.ViewMovedForRulers  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The rulers follow the current view's zoom, scroll and pointer; what other views do does not
    matter.
  =========================================================================== }
procedure TfrmMain.ViewMovedForRulers(Sender: TObject);
begin
  if (FRulerTop = nil) or (Sender <> FView) then
    Exit;
  FRulerTop.Sync;
  FRulerLeft.Sync;
end;

{ ===========================================================================
  TfrmMain.DoToggleGridSize  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler of the bar's grid size button (CTinyCadView::OnToggleGridSize): the sheet's grid
    goes to the next of the standard sizes (see NextGridUnits).
  =========================================================================== }
procedure TfrmMain.DoToggleGridSize(Sender: TObject);
begin
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  FView.GridMm := NextGridUnits(FView.Sheet.Snap.Grid) / UNITS_PER_MM;
  FView.Invalidate;
  UpdateRibbonState;
end;

{ ===========================================================================
  TfrmMain.GridForAlign  (function)
  Parameters:  none
  Returns:
    Double
  Notes:
    The sheet's grid. The 1 px grid check box only changes how the dots are drawn, not the grid.
  =========================================================================== }
function TfrmMain.GridForAlign: Double;
begin
  if FView.Sheet <> nil then
    Result := FView.Sheet.Snap.Grid
  else
    Result := 0;
end;

{ ===========================================================================
  TfrmMain.ApplyOnePxGrid  (procedure)
  Parameters:
    AOn: Boolean - flag
  Notes:
    Changes only the drawing of the grid dots (they otherwise grow with the zoom), for fine work
    on wire and pin alignment. The grid spacing and snapping are not touched. Does nothing for a
    design.
  =========================================================================== }
procedure TfrmMain.ApplyOnePxGrid(AOn: Boolean);
begin
  if (not IsSymbolDoc) or (FDesign = nil) or (FView.Sheet = nil) or (CurDoc.OnePxGrid = AOn) then
    Exit;
  CurDoc.OnePxGrid := AOn;
  FView.OnePxDots := AOn;
  FView.Invalidate;
  UpdateRibbonState;
end;

{ ===========================================================================
  TfrmMain.AlignMenuOpen  (procedure)
  Parameters:  none
  Notes:
    As the sheet pop-up menu opens: Align to Grid is there only while a symbol is being edited,
    and can be used when something is selected.
  =========================================================================== }
procedure TfrmMain.AlignMenuOpen;
begin
  miAlignToGrid.Visible := IsSymbolDoc;
  miAlignToGrid.Enabled := FView.SelectedCount > 0;
end;

{ ===========================================================================
  TfrmMain.RefreshSymbolControls  (procedure)
  Parameters:  none
  Notes:
    The next functions only read or set the controls above, for the self-test script.
  =========================================================================== }
procedure TfrmMain.RefreshSymbolControls;
begin
  UpdateSymbolMenu;
end;

{ ===========================================================================
  TfrmMain.SetOnePxGridBox  (procedure)
  Parameters:
    AChecked: Boolean - flag
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfrmMain.SetOnePxGridBox(AChecked: Boolean);
begin
  UpdatePositionBar;
  if miAlign1pxgrid.Enabled then
  begin
    miAlign1pxgrid.Checked := AChecked;
    ApplyOnePxGrid(AChecked);      // (a menu item has no OnChange: the choice is applied here, as a click on the item does)
  end;
end;

{ ===========================================================================
  TfrmMain.OnePxGridChecked  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    TODO: describe.
  =========================================================================== }
function TfrmMain.OnePxGridChecked: Boolean;
begin
  Result := miAlign1pxgrid.checked; //cbOnePxGrid.Checked;
end;

{ ===========================================================================
  TfrmMain.OnePxGridEnabled  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    TODO: describe.
  =========================================================================== }
function TfrmMain.OnePxGridEnabled: Boolean;
begin
  Result := miAlign1pxgrid.Enabled; //cbOnePxGrid.Enabled;
end;

{ ===========================================================================
  TfrmMain.AlignGridUnits  (function)
  Parameters:  none
  Returns:
    Double
  Notes:
    TODO: describe.
  =========================================================================== }
function TfrmMain.AlignGridUnits: Double;
begin
  Result := GridForAlign;
end;

{ ===========================================================================
  TfrmMain.AlignItemVisible  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    TODO: describe.
  =========================================================================== }
function TfrmMain.AlignItemVisible: Boolean;
begin
  Result := miAlignToGrid.Visible;
end;

{ ===========================================================================
  TfrmMain.AlignItemEnabled  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    TODO: describe.
  =========================================================================== }
function TfrmMain.AlignItemEnabled: Boolean;
begin
  Result := miAlignToGrid.Enabled;
end;

{ ===========================================================================
  TfrmMain.DoOnePxGrid  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler: draws the grid dots one pixel wide, or back to the usual size.
  =========================================================================== }
procedure TfrmMain.DoOnePxGrid(Sender: TObject);
begin
  if FUpdatingPosition then
    Exit;
  if Sender = miAlign1pxgrid then
    miAlign1pxgrid.Checked := not miAlign1pxgrid.Checked;      // (a menu item does not turn over by itself: the click says what is wanted)
  ApplyOnePxGrid(miAlign1pxgrid.Checked);
end;

{ ===========================================================================
  TfrmMain.DoAlignToGrid  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler of Z-Order > Align to Grid (symbol editing): each selected object is shifted so its
    first end, or a pin's connection end, is on the nearest grid dot. Its shape is not changed.
  =========================================================================== }
procedure TfrmMain.DoAlignToGrid(Sender: TObject);
var
  N: Integer;
begin
  N := FView.AlignSelectionToGrid(GridForAlign);
  if N = 0 then
    sbMainBar.Panels[1].Text := rsAlreadyOnTheGrid
  else
    sbMainBar.Panels[1].Text := Format(rsObjectSMovedToThe, [N]);
end;

{ ===========================================================================
  TfrmMain.UpdatePositionBar  (procedure)
  Parameters:  none
  Notes:
    Shows the sheet's grid size (in tenths of a millimetre or thousandths of an inch, as TinyCAD
    does) and its units, and puts the snap buttons and the Show grid button and menu item in
    line with the sheet. With no design open the bar is empty and its buttons cannot be used.
  =========================================================================== }
procedure TfrmMain.UpdatePositionBar;
var
  Have: Boolean;
  U: Integer;
begin
  Have := (FDesign <> nil) and (FView.Sheet <> nil);
  sbPosSnap.Enabled := Have;
  miGridSnap.Enabled := Have;
  sbPosGridSize.Enabled := Have;
  FUpdatingPosition := True;
  try
    miAlign1pxgrid.Enabled {cbOnePxGrid.Enabled} := Have and IsSymbolDoc;
    miALign1pxgrid.Checked {cbOnePxGrid.Checked} := Have and IsSymbolDoc and CurDoc.OnePxGrid;
    FView.OnePxDots := Have and IsSymbolDoc and CurDoc.OnePxGrid;
  finally
    FUpdatingPosition := False;
  end;
  if Have then
  begin
    U := FView.Sheet.Options.Units;
    edPosGrid.Text := GridSizeText(FView.Sheet.Snap.Grid, U);
    lblPosUnits.Caption := GridSizeUnitsText(U);
    sbPosSnap.Down := FView.SnapEnabled;
    sbViewGridSnapTo.Down := FView.SnapEnabled;
    miGridSnap.Checked := FView.SnapEnabled;
    SyncGridSizeMenus;
    mShowGrid.Checked := FView.ShowGrid;
    sbViewGridShow.Down := FView.ShowGrid;
  end
  else
  begin
    edPosGrid.Text := '';
    lblPosUnits.Caption := GridSizeUnitsText(EditDefaults.Units);
    sbPosSnap.Down := False;
    miGridSnap.Checked := False;
    SyncGridSizeMenus;
    lblPosition.Caption := ' ';
  end;
end;

{ ===========================================================================
  TfrmMain.PositionInfo  (function)
  Parameters:  none
  Returns:
    String - the text
  Notes:
    The position bar as text, for tests: whether it is shown, the position and grid size it
    shows with the units, the state of the snap and Show grid controls, the View menu tick and
    the ribbon button.
  =========================================================================== }
function TfrmMain.PositionInfo: String;
begin
  UpdatePositionBar;
  Result := Format('visible=%d text=[%s] grid=%s units=%s snap=%d%d grid_show=%d%d%d size_enabled=%d snap_enabled=%d menu=%d ribbon=%d status=[%s] caption=[%s]',
    [Ord(pnlPosition.Visible), lblPosition.Caption, edPosGrid.Text, lblPosUnits.Caption, Ord(sbPosSnap.Down), Ord(sbViewGridSnapTo.Down),
     Ord(mShowGrid.Checked), Ord(sbViewGridShow.Down), Ord(FView.ShowGrid), Ord(sbPosGridSize.Enabled), Ord(sbPosSnap.Enabled), Ord(mShowPosition.Checked),
     Ord(sbView.Checked), sbMainBar.Panels[1].Text, sbViewGridSize.Caption]);
end;

{ ===========================================================================
  Repeat Directions (TinyCAD's Options > Repeat Directions): which way names and pin numbers count when things are placed one after another. There are two choices, each
  Increment or Decrement, kept for each open design (and not saved in its file, as in TinyCAD); both start as Increment.
  =========================================================================== }

{ ===========================================================================
  TfrmMain.DoRepeatNameUp  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler (Repeat Directions > Name Increment): the number in the next label or text counts
    up.
  =========================================================================== }
procedure TfrmMain.DoRepeatNameUp(Sender: TObject);
begin
  if FDesign <> nil then
    FView.NameDir := 1;
  UpdateRepeatMenu;
end;

{ ===========================================================================
  TfrmMain.DoRepeatNameDown  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Handler (Repeat Directions > Name Decrement): the number in the next label or text counts
    down.
  =========================================================================== }
procedure TfrmMain.DoRepeatNameDown(Sender: TObject);
begin
  if FDesign <> nil then
    FView.NameDir := -1;
  UpdateRepeatMenu;
end;

{ ===========================================================================
  TfrmMain.DoRepeatPinUp  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Handler (Repeat Directions > Pin Increment): pin numbers count up as pins are placed one
    after another.
  =========================================================================== }
procedure TfrmMain.DoRepeatPinUp(Sender: TObject);
begin
  if FDesign <> nil then
    FView.PinDir := 1;
  UpdateRepeatMenu;
end;

{ ===========================================================================
  TfrmMain.DoRepeatPinDown  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Handler (Repeat Directions > Pin Decrement): pin numbers count down as pins are placed one
    after another.
  =========================================================================== }
procedure TfrmMain.DoRepeatPinDown(Sender: TObject);
begin
  if FDesign <> nil then
    FView.PinDir := -1;
  UpdateRepeatMenu;
end;

{ ===========================================================================
  TfrmMain.UpdateRepeatMenu  (procedure)
  Parameters:  none
  Notes:
    Ticks the choices of the open design (Increment for both when no design is open, as for a
    new one), and makes the menu items unusable with no design.
  =========================================================================== }
procedure TfrmMain.UpdateRepeatMenu;
var
  N, P: Integer;
  Have: Boolean;
begin
  Have := (FDesign <> nil) and (FView <> nil);
  if Have then begin
    N := FView.NameDir;
    P := FView.PinDir;
  end else begin
    N := 1;
    P := 1;
  end;
  mRepeatNameUp.Checked := N = 1;
  mRepeatNameDown.Checked := N = -1;
  mRepeatPinUp.Checked := P = 1;
  mRepeatPinDown.Checked := P = -1;
  mRepeatNameUp.Enabled := Have;
  mRepeatNameDown.Enabled := Have;
  mRepeatPinUp.Enabled := Have;
  mRepeatPinDown.Enabled := Have;
end;

{ ===========================================================================
  TfrmMain.RepeatInfo  (function)
  Parameters:  none
  Returns:
    String - the text
  Notes:
    The Repeat Directions as text, for tests: the name and pin directions, which menu items are
    ticked, and whether they can be used.
  =========================================================================== }
function TfrmMain.RepeatInfo: String;
var
  N, P: Integer;
begin
  UpdateRepeatMenu;
  if (FDesign <> nil) and (FView <> nil) then begin
    N := FView.NameDir;
    P := FView.PinDir;
  end else begin
    N := 1;
    P := 1;
  end;
  Result := Format('name=%d pin=%d menu=%d%d%d%d enabled=%d', [N, P, Ord(mRepeatNameUp.Checked), Ord(mRepeatNameDown.Checked),
    Ord(mRepeatPinUp.Checked), Ord(mRepeatPinDown.Checked), Ord(mRepeatNameUp.Enabled)]);
end;

{ ===========================================================================
  TfrmMain.UseSettingsAsDefaults  (procedure)
  Parameters:  none
  Notes:
    Makes what the program has saved the start of every new design: the grid spacing, snapping
    and showing, the units and the auto drag, snap and junction settings.
  =========================================================================== }
procedure TfrmMain.UseSettingsAsDefaults;
begin
  with ProgramSettings do
  begin
    EditDefaults.ShowGrid := ShowGrid;
    EditDefaults.SnapGrid := SnapGrid;
    EditDefaults.GridMm := GridMm;
    EditDefaults.Units := Units;
    EditDefaults.AutoDrag := AutoDrag;
    EditDefaults.AutoSnap := AutoSnap;
    EditDefaults.AutoJunction := AutoJunction;
    EditDefaults.AutoSnapRange := AutoSnapRange;
    EditDefaults.SymbolFontName := SymbolFontName;
    EditDefaults.SymbolFontPoints := SymbolFontPoints;
    EditDefaults.SymbolFontBold := SymbolFontBold;
    EditDefaults.SymbolFontItalic := SymbolFontItalic;
  end;
end;

{ ===========================================================================
  TfrmMain.CurrentOptions  (function)
  Parameters:  none
  Returns:
    TOptionsData - the values
  Notes:
    What the Options dialog should show now: the open design's own settings, or the program's
    when no design is open.
  =========================================================================== }
function TfrmMain.CurrentOptions: TOptionsData;
begin
  Result := OptionsFromSettings;
  if (FDesign <> nil) and (FView.Sheet <> nil) then
  begin
    Result.ShowGrid := FView.ShowGrid;
    Result.SnapGrid := FView.SnapEnabled;
    Result.GridMm := FView.GridMm;
    with FView.Sheet.Options do
    begin
      Result.Units := Units;
      Result.AutoDrag := AutoDrag;
      Result.AutoSnap := AutoSnap;
      Result.AutoJunction := AutoJunction;
      Result.AutoSnapRange := AutoSnapRange;
      GetSymbolFont(Result.SymbolFontName, Result.SymbolFontPoints, Result.SymbolFontBold, Result.SymbolFontItalic);
    end;
  end;
end;

{ ===========================================================================
  TfrmMain.RefreshGridMenuCaptions  (procedure)
  Parameters:
    Units: Integer - UNITS_MM or UNITS_INCHES
  Notes:
    Writes the usual grid sizes of the grid menu in the units the design now shows lengths in.
  =========================================================================== }
procedure TfrmMain.RefreshGridMenuCaptions(Units: Integer);
var
  i: Integer;
begin
  if pmGridSize = nil then
    Exit;
  for i := 0 to Min(High(GridSizeMM), pmGridSize.Items.Count - 3) do
    pmGridSize.Items[i].Caption := LengthText(GridSizeMM[i] / 1000, Units);
  SyncGridSizeMenus;
end;

{ ===========================================================================
  TfrmMain.SyncGridSizeMenus  (procedure)
  Parameters:  none
  Notes:
    Puts the captions and the tick of the Grid Size submenu in line with the grid-size popup
    (the popup follows the unit and the size of the sheet).
  =========================================================================== }
procedure TfrmMain.SyncGridSizeMenus;
var
  i, N: Integer;
begin
  if (pmGridSize = nil) or (miGridSize = nil) then
    Exit;
  N := Min(pmGridSize.Items.Count, miGridSize.Count);
  for i := 0 to N - 1 do
  begin
    miGridSize.Items[i].Caption := pmGridSize.Items[i].Caption;
    if (pmGridSize.Items[i].Tag <> 0) and (pmGridSize.Items[i].Caption <> '-') and (pmGridSize.Items[i].RadioItem) then
    begin
      pmGridSize.Items[i].Checked := Abs(pmGridSize.Items[i].Tag / 100 - FView.GridMm) < 0.001;
      miGridSize.Items[i].Checked := pmGridSize.Items[i].Checked;
    end;
  end;
  miGridSize.Enabled := (FDesign <> nil) and (FView.Sheet <> nil);
end;

{ ===========================================================================
  TfrmMain.ApplyOptions  (function)
  Parameters:
    const D: TOptionsData
  Returns:
    Boolean
  Notes:
    The open design takes the values for every one of its sheets (TinyCAD applies them to the
    sheet showing; a design whose sheets differed would be confusing): the grid spacing,
    snapping and showing, the units, the auto drag, snap and junction settings, and the symbol font (the font of the reference and the other text of symbols, and of pin text). They are
    then kept as what new designs start with (and saved in the registry), and the automatic save
    is restarted. As in TinyCAD, this does not mark the design as changed.
  =========================================================================== }
function TfrmMain.ApplyOptions(const D: TOptionsData): Boolean;
var
  i: Integer;
  Sh: TDesignSheet;
begin
  Result := False;
  if OptionsError(D) <> '' then
    Exit;
  if FDesign <> nil then
  begin
    for i := 0 to FDesign.SheetCount - 1 do
    begin
      Sh := FDesign.Sheets[i];
      Sh.Snap.Grid := D.GridMm * UNITS_PER_MM;
      Sh.Snap.GridSnap := Ord(D.SnapGrid);
      with Sh.Options do
      begin
        Units := D.Units;
        GridShow := Ord(D.ShowGrid);
        AutoDrag := D.AutoDrag;
        AutoSnap := D.AutoSnap;
        AutoJunction := D.AutoJunction;
        AutoSnapRange := D.AutoSnapRange;
        SetSymbolFont(D.SymbolFontName, D.SymbolFontPoints, D.SymbolFontBold, D.SymbolFontItalic);
      end;
    end;
    FView.ShowGrid := D.ShowGrid;
    FView.SnapEnabled := D.SnapGrid;
    FView.Invalidate;
  end;
  OptionsToSettings(D);
  UseSettingsAsDefaults;
  SaveSettings;
  SetupAutoSave;
  RefreshGridMenuCaptions(D.Units);
  RefreshAfterDocumentChange;
  Result := True;
end;

{ ===========================================================================
  TfrmMain.OptionsApplyRequest  (procedure)
  Parameters:
    Sender: TObject - the dialog
  Notes:
    The Apply button of the Options dialog: applies the dialog's values now, if they can be
    used.
  =========================================================================== }
procedure TfrmMain.OptionsApplyRequest(Sender: TObject);
var
  D: TOptionsData;
begin
  if (Sender as TfrmOptions).ReadData(D) = '' then
    ApplyOptions(D);
end;

{ ===========================================================================
  TfrmMain.DoOptions  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Shows the Options dialog with the open design's values (or the program's, with no design
    open). OK applies them and closes; Apply applies them and leaves the dialog open; Cancel
    changes nothing.
  =========================================================================== }
procedure TfrmMain.DoOptions(Sender: TObject);
var
  F: TfrmOptions;
  D: TOptionsData;
  Src: TUserColors;
begin
  F := TfrmOptions.Create(Self);
  try
    F.LoadFromData(CurrentOptions);
    F.OnApplyRequest := @OptionsApplyRequest;
    if (FDesign <> nil) and (FView.Sheet <> nil) then
      F.LoadColors(FView.Sheet.Options.Colors)
    else
      begin
        Src := TUserColors.Create;
        try
          F.LoadColors(Src);
        finally
          Src.Free;
        end;
      end;
    if (F.ShowModal = mrOK) and (F.ReadData(D) = '') then
      begin
        ApplyOptions(D);
        ApplyColors(F);
      end;
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.DoColors  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TinyCAD's Options > Colors: shows the Colors dialog with the colors of the open design (the
    program's own colors when no design is open). OK applies them.
  =========================================================================== }
procedure TfrmMain.DoColors(Sender: TObject);
{var
  F: TfrmColors;
  Src: TUserColors;}
begin
  //depreciated
{  F := TfrmColors.Create(Self);
  try
    if (FDesign <> nil) and (FView.Sheet <> nil) then F.LoadColors(FView.Sheet.Options.Colors)
    else
    begin
      Src := TUserColors.Create;
      try
        F.LoadColors(Src);
      finally
        Src.Free;
      end;
    end;
    if F.ShowModal = mrOK then ApplyColors(F);
  finally
    F.Free;
  end;     }
end;

{ ===========================================================================
  TfrmMain.ApplyColors  (procedure)
  Parameters:
    F: TfrmOptions
  Notes:
    The open design takes all the colors of the dialog for every one of its sheets (TinyCAD
    changes the sheet showing; the sheets of a design should match), and the ten colors the
    dialog lists are kept as what new designs start with, but only those that differ from the
    factory colors (the others are forgotten, so a color put back to the factory one stops being
    an override), as TinyCAD's WriteRegistry does. The two colors the dialog does not list (net
    labels and the pins of power symbols) are carried through and not kept. As in TinyCAD this
    does not mark the design as changed; the view is redrawn.
  =========================================================================== }
procedure TfrmMain.ApplyColors(F: TfrmOptions);
var
  i, k, Id: Integer;
  Factory: TUserColors;
  Ids: TColorIds;
begin
  if FDesign <> nil then
    for i := 0 to FDesign.SheetCount - 1 do
      for Id := UC_WIRE to UC_NOTETEXT_TEXT do FDesign.Sheets[i].Options.Colors.SetColor(Id, F.ColorOf(Id));
  Factory := TUserColors.Create;
  try
    Factory.Init;
    Ids := TfrmOptions.ListedIds;
    for k := 0 to High(Ids) do
      if F.ColorOf(Ids[k]) = Factory.Get(Ids[k]) then
        UserColorOverride[Ids[k]] := -1
      else
        UserColorOverride[Ids[k]] := F.ColorOf(Ids[k]);
  finally
    Factory.Free;
  end;
  SaveSettings;
  if FView <> nil then
    FView.Invalidate;
end;

{ ===========================================================================
  TfrmMain.SetupAutoSave  (procedure)
  Parameters:  none
  Notes:
    Makes the timer of the automatic save as often as the settings say (minutes), or stops it
    when they say none.
  =========================================================================== }
procedure TfrmMain.SetupAutoSave;
begin
  if FAutoSaveTimer = nil then
  begin
    FAutoSaveTimer := TTimer.Create(Self);
    FAutoSaveTimer.Enabled := False;
    FAutoSaveTimer.OnTimer := @AutoSaveTick;
  end;
  FAutoSaveTimer.Enabled := False;
  if ProgramSettings.AutoSaveMinutes > 0 then
  begin
    FAutoSaveTimer.Interval := ProgramSettings.AutoSaveMinutes * 60 * 1000;
    FAutoSaveTimer.Enabled := True;
  end;
end;

{ ===========================================================================
  TfrmMain.AutoSaveTick  (procedure)
  Parameters:
    Sender: TObject - the timer
  Notes:
    The automatic save timer ran out: saves a copy of every named design (the timer is stopped
    while it does and started again after).
  =========================================================================== }
procedure TfrmMain.AutoSaveTick(Sender: TObject);
begin
  FAutoSaveTimer.Enabled := False;           // (stopped while it saves, as TinyCAD does)
  try
    AutoSaveAll;
  finally
    if ProgramSettings.AutoSaveMinutes > 0 then
      FAutoSaveTimer.Enabled := True;
  end;
end;

{ ===========================================================================
  TfrmMain.AutoSaveAll  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    TinyCAD's CTinyCadMultiDoc::AutoSave for every open design: one that has a file name is
    written beside it as <name>.autosave (to <name>.autosave.new first, which then replaces the
    old copy, so a failure never leaves half a copy). The design itself is untouched: its file
    name, its unsaved-changes mark and the original file are as they were. A design that has
    never been saved has nowhere to go and is left out. A failure is not reported (it must not
    interrupt the work); the design is simply left out.
  =========================================================================== }
function TfrmMain.AutoSaveAll: Integer;
var
  i: Integer;
  Target, Tmp: String;
  FS: TFileStream;
begin
  Result := 0;
  if FDocs = nil then
    Exit;
  for i := 0 to FDocs.Count - 1 do
  begin
    Target := FDocs[i].FileName;
    if Target = '' then
      Continue;
    Tmp := Target + '.autosave.new';
    try
      FS := TFileStream.Create(Tmp, fmCreate);
      try
        FDocs[i].Design.SaveToStream(FS);
      finally
        FS.Free;
      end;
      if FileExists(Target + '.autosave') then
        DeleteFile(Target + '.autosave');
      if RenameFile(Tmp, Target + '.autosave') then
        Inc(Result)
      else
        DeleteFile(Tmp);
    except
      if FileExists(Tmp) then
        DeleteFile(Tmp);
    end;
  end;
end;

{ ===========================================================================
  TfrmMain.AutoSaveInfo  (function)
  Parameters:  none
  Returns:
    String - the text
  Notes:
    The automatic save as text, for tests: the minutes, whether the timer runs and its interval
    in milliseconds.
  =========================================================================== }
function TfrmMain.AutoSaveInfo: String;
begin
  Result := Format('minutes=%d timer=%d interval=%d', [ProgramSettings.AutoSaveMinutes, Ord(FAutoSaveTimer.Enabled), FAutoSaveTimer.Interval]);
end;

{ ===========================================================================
  TfrmMain.FindMessage  (procedure)
  Parameters:
    const Msg: String - the message
  Notes:
    Puts a message in the status bar.
  =========================================================================== }
procedure TfrmMain.FindMessage(const Msg: String);
begin
  sbMainBar.Panels[0].Text := Msg;
end;

{ ===========================================================================
  TfrmMain.SyncFindFromDialog  (procedure)
  Parameters:  none
  Notes:
    Takes what the dialog holds as what to look for: the text, the replacement, the Match
    case and Whole words options, and the scope: every sheet with "Search entire file" ticked,
    otherwise only the sheet shown.
  =========================================================================== }
procedure TfrmMain.SyncFindFromDialog;
begin
  FFind.Needle := ReplaceDlg.FindText;
  FFind.Replacement := ReplaceDlg.ReplaceText;
  FFind.Options := [];
  if (frEntireScope in ReplaceDlg.Options) or (FView = nil) then
    FFind.OnlySheet := -1
  else
    FFind.OnlySheet := FView.SheetIndex;
  if frMatchCase in ReplaceDlg.Options then
    Include(FFind.Options, foMatchCase);
  if frWholeWord in ReplaceDlg.Options then
    Include(FFind.Options, foWholeWord);
end;

{ ===========================================================================
  TfrmMain.ShowFound  (procedure)
  Parameters:  none
  Notes:
    Shows the occurrence that was found: switches to its sheet as clicking that sheet's tab
    would, selects the object and scrolls it into sight.
  =========================================================================== }
procedure TfrmMain.ShowFound;
var
  H: TFindHit;
begin
  H := FFind.Current;
  if H.Sheet <> FView.SheetIndex then
  begin
    tcSheetTabs.TabIndex := H.Sheet;           // as clicking that sheet's tab
    SheetTabChange(tcSheetTabs);
  end;
  FView.SelectObject(H.Obj, False);
  FView.ShowObject(H.Obj);
end;

{ ===========================================================================
  TfrmMain.FindStep  (function)
  Parameters:
    Down: Boolean - True to search forwards, False for backwards
  Returns:
    Boolean - True if something was found
  Notes:
    Finds the next (or previous) occurrence of the text in the Find and Replace dialog, shows it
    (its sheet, selected and in sight) and reports in the status bar where it is, that the
    search wrapped round, or that the text cannot be found. A drawing tool is put away first, as
    TinyCAD does.
  =========================================================================== }
function TfrmMain.FindStep(Down: Boolean): Boolean;
var
  H: TFindHit;
  ScopeWord: String;
begin
  Result := False;
  if (FDesign = nil) or (FFind.Needle = '') then
    Exit;
  if FFind.OnlySheet >= 0 then
    ScopeWord := 'sheet'
  else
    ScopeWord := 'design';
  FView.BeginTool(vtSelect);                  // (as TinyCAD does, a drawing tool is put away first)
  if FFind.FindNext(FDesign, Down, FView.SheetIndex) then
  begin
    ShowFound;
    H := FFind.Current;
    if FFind.Wrapped then
    begin
      if Down then
        FindMessage(Format(rsReachedTheEndOfThe, [ScopeWord]))
      else
        FindMessage(Format(rsReachedTheStartOfThe, [ScopeWord]));
    end
    else
      FindMessage(Format(rsFoundIn, [SlotName(H.Obj, H.Slot), StringReplace(SlotText(H.Obj, H.Slot), #10, ' ', [rfReplaceAll])]));
    Result := True;
  end
  else
    FindMessage(Format(rsCannotFind, [FFind.Needle]));
end;

{ ===========================================================================
  TfrmMain.ReplaceDlgFind  (procedure)
  Parameters:
    Sender: TObject - the dialog
  Notes:
    Event handler of the dialog's Find Next button: takes what the dialog holds and finds the
    next occurrence in the direction it says.
  =========================================================================== }
procedure TfrmMain.ReplaceDlgFind(Sender: TObject);
begin
  SyncFindFromDialog;
  FindStep(frDown in ReplaceDlg.Options);
end;

{ ===========================================================================
  TfrmMain.ReplaceDlgReplace  (procedure)
  Parameters:
    Sender: TObject - the dialog
  Notes:
    Event handler of the dialog's Replace and Replace All buttons. Replace All changes every
    occurrence in the whole design as one undo step (Replace all) and says how many. Replace
    changes the occurrence found last, if there is one and it is still there, as one undo step
    (Replace), then finds the next.
  =========================================================================== }
procedure TfrmMain.ReplaceDlgReplace(Sender: TObject);
var
  N, Objs: Integer;
  Done: Boolean;
begin
  if FDesign = nil then
    Exit;
  SyncFindFromDialog;
  if FFind.Needle = '' then
    Exit;
  FView.BeginTool(vtSelect);
  if (frReplaceAll in ReplaceDlg.Options) and (frPromptOnReplace in ReplaceDlg.Options) then
    ReplaceAllPrompted
  else if frReplaceAll in ReplaceDlg.Options then
  begin
    FView.BeginChange(rsReplaceAll);
    N := FFind.ReplaceAll(FDesign, Objs);
    FView.CommitChange(N > 0);
    if N = 0 then
      FindMessage(Format(rsCannotFind, [FFind.Needle]))
    else if N = 1 then
      FindMessage(rsReplacedOccurrence)
    else
      FindMessage(Format(rsReplacedOccurrencesInObjects, [N, Objs]));
  end
  else
  begin
    { Replace: the occurrence found last is replaced (if there is one and it is still there), then the next is found }
    Done := False;
    if FFind.HasCurrent then
    begin
      FView.BeginChange(rsReplace);
      Done := FFind.ReplaceCurrent(FDesign);
      if Done then
        FDesign.Sheets[FFind.Current.Sheet].UpdateLayout;
      FView.CommitChange(Done);
    end;
    FindStep(frDown in ReplaceDlg.Options);
  end;
end;

{ ===========================================================================
  TfrmMain.SetFindPrompt  (procedure)
  Parameters:
    const Answers: String - one letter for each question of Replace All with "Prompt on replace": y, n or c
  Notes:
    For the self-test script: the questions are answered from this list and no box is shown (a
    question after the list has run out is answered with Cancel).
  =========================================================================== }
procedure TfrmMain.SetFindPrompt(const Answers: String);
begin
  FindPromptScript := Answers;
  FindPromptScripted := True;
end;

{ ===========================================================================
  TfrmMain.AskReplace  (function)
  Parameters:
    const Where: String - what is about to be replaced, for the question
  Returns:
    Char - 'y' replace it, 'n' leave it, 'c' stop
  Notes:
    The question of "Prompt on replace". A test script puts its answers in FindPromptScript (one
    letter per question, 'c' when they run out) and no box is shown.
  =========================================================================== }
function TfrmMain.AskReplace(const Where: String): Char;
begin
  if FindPromptScript <> '' then
  begin
    Result := FindPromptScript[1];
    Delete(FindPromptScript, 1, 1);
    Exit;
  end;
  if FindPromptScripted then
    Exit('c');
  case MessageDlg(rsReplace, Format(rsReplaceWithIn, [FFind.Needle, FFind.Replacement, Where]), mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes: Result := 'y';
    mrNo: Result := 'n';
  else
    Result := 'c';
  end;
end;

{ ===========================================================================
  TfrmMain.ReplaceAllPrompted  (procedure)
  Parameters:  none
  Notes:
    Replace All with "Prompt on replace" ticked: each occurrence in the sheets the search covers
    is shown (its sheet, selected, in sight) and asked about - Yes replaces it, No leaves it,
    Cancel stops. Each replacement is its own undo step (the sheet may change from one question to
    the next); the status bar says how many were replaced and how many were left.
  =========================================================================== }
procedure TfrmMain.ReplaceAllPrompted;
var
  Done, Kept: Integer;
  Ans: Char;
  s: Integer;
  Ok: Boolean;
begin
  Done := 0;
  Kept := 0;
  FFind.Reset;
  while FFind.FindNext(FDesign, True, 0) and (not FFind.Wrapped) do
  begin
    ShowFound;
    Ans := AskReplace(SlotName(FFind.Current.Obj, FFind.Current.Slot));
    if Ans = 'c' then
      Break;
    if Ans = 'y' then
    begin
      FView.BeginChange(rsReplace);
      Ok := FFind.ReplaceCurrent(FDesign);
      if Ok then
      begin
        FDesign.Sheets[FFind.Current.Sheet].UpdateLayout;
        Inc(Done);
      end;
      FView.CommitChange(Ok);
    end
    else
      Inc(Kept);
  end;
  for s := 0 to FDesign.SheetCount - 1 do
    FDesign.Sheets[s].UpdateLayout;
  FView.Invalidate;
  if (Done = 0) and (Kept = 0) then
    FindMessage(Format(rsCannotFind, [FFind.Needle]))
  else
    FindMessage(Format(rsReplacedOfShownLeftAs, [Done, Done + Kept, Kept]));
end;

{ ===========================================================================
  TfrmMain.ReplaceDlgClose  (procedure)
  Parameters:
    Sender: TObject - the dialog
  Notes:
    Event handler: the Find and Replace dialog was closed.
  =========================================================================== }
procedure TfrmMain.ReplaceDlgClose(Sender: TObject);
begin
  FFindOpen := False;
end;

{ ===========================================================================
  TfrmMain.DoFindReplace  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler (Ctrl+F, Ctrl+H): opens the Find and Replace dialog (the ReplaceDlg component), with
    its "Search entire file" box (ticked: every sheet of the design, not the other open documents;
    not ticked: only the sheet shown) and "Prompt on replace" box (Replace All asks about each
    occurrence).
  =========================================================================== }
procedure TfrmMain.DoFindReplace(Sender: TObject);
begin
  if FDesign = nil then
    Exit;
  if not FFindOpen then
  begin
    FFindOpen := True;
    ReplaceDlg.Execute;
  end;
end;

{ ===========================================================================
  TfrmMain.DoFindNext  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler (F3): finds the next occurrence of the text last put in the dialog; if there is none
    yet the dialog is opened.
  =========================================================================== }
procedure TfrmMain.DoFindNext(Sender: TObject);
begin
  if FDesign = nil then
    Exit;
  if ReplaceDlg.FindText = '' then
  begin
    DoFindReplace(Sender);        // nothing to look for yet: ask
    Exit;
  end;
  SyncFindFromDialog;
  FindStep(True);
end;

{ ===========================================================================
  TfrmMain.DoFindPrevious  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler (Shift+F3): finds the previous occurrence of the text last put in the dialog; if
    there is none yet the dialog is opened.
  =========================================================================== }
procedure TfrmMain.DoFindPrevious(Sender: TObject);
begin
  if FDesign = nil then
    Exit;
  if ReplaceDlg.FindText = '' then
  begin
    DoFindReplace(Sender);
    Exit;
  end;
  SyncFindFromDialog;
  FindStep(False);
end;

{ ===========================================================================
  TfrmMain.FindInfoText  (function)
  Parameters:  none
  Returns:
    String - the text
  Notes:
    Where the last search stands, as text: the sheet shown, how many objects are selected, the
    place found (sheet, object, text, offset, length), whether the search wrapped, the selected
    object's class and the text found, and the status bar message (for tests).
  =========================================================================== }
function TfrmMain.FindInfoText: String;
var
  H: TFindHit;
  Cls, Txt: String;
begin
  Cls := '-';
  Txt := '';
  if (FView <> nil) and (FView.SelectedCount > 0) then
    Cls := FView.SelectedObject(0).ClassName;
  if FFind.HasCurrent then
  begin
    H := FFind.Current;
    Txt := StringReplace(SlotText(H.Obj, H.Slot), #10, '\n', [rfReplaceAll]);
    Result := Format('sheet=%d sel=%d hit=%d:%d:%d:%d:%d wrapped=%d class=%s text=%s msg=%s',
      [FView.SheetIndex, FView.SelectedCount, H.Sheet, H.ObjIndex, H.Slot, H.Offset, H.Len, Ord(FFind.Wrapped), Cls, Txt, sbMainBar.Panels[0].Text]);
  end
  else
    Result := Format('sheet=%d sel=%d hit=none wrapped=0 class=%s text= msg=%s', [FView.SheetIndex, FView.SelectedCount, Cls, sbMainBar.Panels[0].Text]);
end;

{ ===========================================================================
  TfrmMain.DoCloseDocument  (procedure)
  Parameters:
    Sender: TObject - the menu item or button
  Notes:
    Handler (Window menu, Ctrl+W, ribbon, pop-up menu): closes the current document, asking
    about unsaved changes.
  =========================================================================== }
procedure TfrmMain.DoCloseDocument(Sender: TObject);
begin
  CloseDocument(FCurrent, True);
end;

{ ===========================================================================
  TfrmMain.DoCloseAllDocuments  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Handler: closes every document one by one, from the last, asking about unsaved changes; it
    stops if the user cancels.
  =========================================================================== }
procedure TfrmMain.DoCloseAllDocuments(Sender: TObject);
begin
  while FDocs.Count > 0 do
    if not CloseDocument(FDocs.Count - 1, True) then
      Exit;
end;

{ ===========================================================================
  TfrmMain.DoNextDocument  (procedure)
  Parameters:
    Sender: TObject - the menu item or button
  Notes:
    Handler (Ctrl+Tab): shows the next document, going round to the first after the last.
  =========================================================================== }
procedure TfrmMain.DoNextDocument(Sender: TObject);
begin
  if FDocs.Count > 1 then
    ActivateDocument((FCurrent + 1) mod FDocs.Count);
end;

{ ===========================================================================
  TfrmMain.DoPrevDocument  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Handler (Ctrl+Shift+Tab): shows the previous document, going round to the last from the
    first.
  =========================================================================== }
procedure TfrmMain.DoPrevDocument(Sender: TObject);
begin
  if FDocs.Count > 1 then
    ActivateDocument((FCurrent + FDocs.Count - 1) mod FDocs.Count);
end;

{ ===========================================================================
  TfrmMain.DoWindowItem  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Handler: a document entry of the Window menu was chosen, so show that document (its position
    is in the item's Tag).
  =========================================================================== }
procedure TfrmMain.DoWindowItem(Sender: TObject);
begin
  ActivateDocument((Sender as TMenuItem).Tag);
end;

{ ===========================================================================
  TfrmMain.IsSymbolDoc  (function)
  Parameters:  none
  Returns:
    Boolean - True if the current document is a library symbol being edited
  Notes:
    Tells a symbol being edited from a design.
  =========================================================================== }
function TfrmMain.IsSymbolDoc: Boolean;
begin
  Result := (CurDoc <> nil) and (CurDoc.Symbol <> nil);
end;

{ ===========================================================================
  TfrmMain.SheetTabCaption  (function)
  Parameters:
    Index: Integer - the sheet
  Returns:
    String - the text of its tab
  Notes:
    A sheet's name, or "Sheet N"; the sheets of a symbol with a drawing for each part are "Part
    A", "Part B" and so on.
  =========================================================================== }
function TfrmMain.SheetTabCaption(Index: Integer): String;
begin
  if IsSymbolDoc then
    Result := Format(rsPart2, [Chr(Ord('A') + Index)])
  else if FDesign.Sheets[Index].SheetName <> '' then
    Result := FDesign.Sheets[Index].SheetName
  else
    Result := Format(rsSheet, [Index + 1]);
end;

{ ===========================================================================
  TfrmMain.SymbolSheetsLocked  (function)
  Parameters:  none
  Returns:
    Boolean - True if the sheets cannot be changed (a symbol is being edited)
  Notes:
    The sheets of a symbol are its parts, changed with Parts per Package only; says so in the
    status bar.
  =========================================================================== }
function TfrmMain.SymbolSheetsLocked: Boolean;
begin
  Result := IsSymbolDoc;
  if Result then
    sbMainBar.Panels[0].Text := rsTheSheetsOfASymbol;
end;

{ ===========================================================================
  TfrmMain.RebuildSheetTabs  (procedure)
  Parameters:  none
  Notes:
    Rebuilds the sheet tabs from the sheets of the current document (a name, or "Sheet N"),
    followed by the + tab that adds a sheet, and selects the tab of the sheet being shown. The
    tabs are hidden while no document is open.
  =========================================================================== }
procedure TfrmMain.RebuildSheetTabs;
var
  i: Integer;
begin
  tcSheetTabs.Tabs.Clear;
  if FDesign <> nil then
  begin
    for i := 0 to FDesign.SheetCount - 1 do tcSheetTabs.Tabs.Add(SheetTabCaption(i));
    if not IsSymbolDoc then
      tcSheetTabs.Tabs.Add(ADD_SHEET_TAB);          // the last tab adds a sheet (a symbol has the sheets of its parts only)
    tcSheetTabs.TabIndex := Min(FView.SheetIndex, FDesign.SheetCount - 1);
  end;
  tcSheetTabs.Visible := (FDesign <> nil) and ((not IsSymbolDoc) or (FDesign.SheetCount > 1));
end;

{ ===========================================================================
  TfrmMain.UpdateFormTitle  (procedure)
  Parameters:
    NewTitle: string = '' - text to show instead of the file name; empty to work it out from the
       document
  Notes:
    Sets the window title: "Schematic - [file name]" (Untitled for an unsaved document, a * when
    modified), or just the application name when no document is open. A non-empty NewTitle is
    shown as given.
  =========================================================================== }
procedure TfrmMain.UpdateFormTitle(NewTitle: string = '');
var
  N: String;
begin
  if length(NewTitle) = 0 then
    begin
      if FDesign = nil then
        N := '' //'(no document)'
      else if IsSymbolDoc then
        N := CurDoc.DisplayName
      else if (FFileName = '') and (CurDoc.ConvertedFrom <> '') then
        N := CurDoc.DisplayName
      else if FFileName = '' then
        N := rsUntitled
      else
        N := ExtractFileName(FFileName);
      if FModified then
        N := N + ' *';
      if length(n) > 0 then
        Caption := lAppName + ' - [' + N + ']'
      else
        Caption := lAppName;
    end
  else
    Caption := lAppName + ' - [' + NewTitle + ']';
end;

{ ===========================================================================
  TfrmMain.UpdatePaperStatus  (procedure)
  Parameters:  none
  Notes:
    Shows the current sheet's paper size in the status bar.
  =========================================================================== }
procedure TfrmMain.UpdatePaperStatus;
begin
  UpdateZoomDisplay;
  if FView.Sheet <> nil then
    sbMainBar.Panels[2].Text := DescribePage(FView.Sheet.Details.PageWidth, FView.Sheet.Details.PageHeight)
  else
    sbMainBar.Panels[2].Text := '';
end;

{ ===========================================================================
  TfrmMain.ConfirmCloseDocument  (function)
  Parameters:
    Index: Integer - position in the list of documents
  Returns:
    Boolean - True if it may be closed
  Notes:
    Asks whether to save a document before it is closed, when it has unsaved changes: Yes saves
    it (and the close goes on only if the save happened), No discards, Cancel stops. The
    document is brought to the front first so the user can see which one it is.
  =========================================================================== }
function TfrmMain.ConfirmCloseDocument(Index: Integer): Boolean;
var
  R: Integer;
begin
  Result := True;
  if (Index < 0) or (Index >= FDocs.Count) or (not FDocs[Index].Modified) then
    Exit;
  ActivateDocument(Index);        // so the user sees which document it is, and Save acts on it
  R := MessageDlg(lAppName, Format(rsSaveChangesTo, [FDocs[Index].DisplayName]), mtConfirmation, [mbYes, mbNo, mbCancel], 0);
  case R of
    mrYes: begin
      DoSave(nil);
      Result := not FDocs[Index].Modified;
    end;
    mrNo: Result := True;
  else
    Result := False;
  end;
end;

{ ===========================================================================
  TfrmMain.OpenDesignFile  (procedure)
  Parameters:
    const FileName: String - path of the design
  Notes:
    Opens a design file as a new document. A file that is already open is just shown instead of
    being opened twice. Errors are raised.
  =========================================================================== }
procedure TfrmMain.OpenDesignFile(const FileName: String);
var
  D: TDesignFile;
  Doc: TDocument;
  Full, Msg: String;
  At: Integer;
begin
  Full := ExpandFileName(FileName);
  At := FDocs.IndexOfFile(Full);
  if At >= 0 then
  begin
    ActivateDocument(At);          // already open: just show it
    NoteFileUsed(Full);            // (and it moves to the top of the recent files)
    Exit;
  end;
  D := TDesignFile.Create;
  try
    D.AllowEmptySheets := True;
    LegacySymbolFinder := @frameLibraryPanel.FindSymbolByName;  // (the oldest binary files store symbols by name)
    D.LoadFromFile(Full);
    D.AssignIds;
  except
    D.Free;
    raise;
  end;
  if D.LoadedLegacy then
  begin
    { an old binary design is a conversion: it opens as a new, unsaved document that remembers where it came from, so that
      Save cannot write the new format over the original (Save As starts from the original's name with "(converted)") }
    Doc := AddDocument(D, '');
    Doc.ConvertedFrom := Full;
    Doc.Modified := True;
    UpdateDocTabs;
    Msg := Format(rsReadTheOldBinaryDesign, [ExtractFileName(Full)]);
    if D.LoadNote <> '' then
      Msg := Msg + '. ' + D.LoadNote;
    sbMainBar.Panels[0].Text := Msg;
    Exit;
  end;
  AddDocument(D, Full);
  NoteFileUsed(Full);
end;

{ ===========================================================================
  TfrmMain.NewDesignWith  (procedure)
  Parameters:
    const PaperName: String - name from the paper table
    Landscape: Boolean - orientation
  Notes:
    Creates a new document with a paper size without showing the dialog (used by scripts).
  =========================================================================== }
procedure TfrmMain.NewDesignWith(const PaperName: String; Landscape: Boolean);
var
  F: TfrmNewDoc;
  D: TDesignFile;
begin
  F := TfrmNewDoc.Create(Self);
  try
    F.SelectPaper(PaperName, Landscape);
    D := F.BuildDesign;
  finally
    F.Free;
  end;
  AddDocument(D, '');
end;

{ ===========================================================================
  TfrmMain.OpenLibraryFile  (procedure)
  Parameters:
    const FileName: String - path of the .TCLib
  Notes:
    Opens a symbol library in the library panel.
  =========================================================================== }
procedure TfrmMain.OpenLibraryFile(const FileName: String);
begin
  frameLibraryPanel.OpenLibrary(FileName);
end;

{ ===========================================================================
  TfrmMain.InsertLadderMm  (function)
  Parameters:
    X1: Double - left, mm
    Y1: Double - top, mm
    X2: Double - right, mm
    Y2: Double - bottom, mm
  Returns:
    TDrawLadder - the new ladder, or nil if no document is open
  Notes:
    Adds a ladder to the current sheet from a rectangle given in millimetres, as one undo step.
  =========================================================================== }
function TfrmMain.InsertLadderMm(X1, Y1, X2, Y2: Double): TDrawLadder;
begin
  Result := nil;
  if FView.Sheet = nil then
    Exit;
  FView.BeginChange(rsAddLadder);
  Result := TDrawLadder.Create(FView.Sheet.Options);
  Result.PointA := DPoint(Min(X1, X2) * UNITS_PER_MM, Min(Y1, Y2) * UNITS_PER_MM);
  Result.PointB := DPoint(Max(X1, X2) * UNITS_PER_MM, Max(Y1, Y2) * UNITS_PER_MM);
  Result.Id := FDesign.NextObjectId;
  FView.Sheet.Drawing.Add(Result);
  FView.CommitChange(True);
end;

{ ===========================================================================
  TfrmMain.PlaceLibraryRow  (procedure)
  Parameters:
    Row: Integer - row in the library list
    Xmm: Double - x position, mm
    Ymm: Double - y position, mm
  Notes:
    Selects a library row and places the symbol with a click at a position (used by scripts).
  =========================================================================== }
procedure TfrmMain.PlaceLibraryRow(Row: Integer; Xmm, Ymm: Double);
begin
  frameLibraryPanel.SelectRow(Row);
  frameLibraryPanel.PlaceSelected;
  FView.ClickAt(FView.DesignToScreen(DPoint(Xmm * UNITS_PER_MM, Ymm * UNITS_PER_MM)).x,
                FView.DesignToScreen(DPoint(Xmm * UNITS_PER_MM, Ymm * UNITS_PER_MM)).y, []);
end;

{ ------------------------------------------------------------------ handlers }

{ ===========================================================================
  TfrmMain.DoNew  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Menu handler: shows the New Document dialog and opens the new design as an extra document;
    the others stay open.
  =========================================================================== }
procedure TfrmMain.DoNew(Sender: TObject);
var
  F: TfrmNewDoc;
begin
  F := TfrmNewDoc.Create(Self);
  try
    if (F.ShowModal = mrOK) then
    begin
      F.RememberChoice;
      AddDocument(F.BuildDesign, '');
    end;
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.DoOpen  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Menu handler: lets the user pick one or more .dsn files and opens each as a document of its
    own (one that is already open is shown instead). A file that cannot be read is reported and
    the others still open.
  =========================================================================== }
procedure TfrmMain.DoOpen(Sender: TObject);
var
  i: Integer;
begin
  OpenDlg.Filter := rsTinyCADDesignsDsnDsnDSN;
  OpenDlg.Options := OpenDlg.Options + [ofAllowMultiSelect];      // several designs can be opened at once
  try
    if OpenDlg.Execute then
      for i := 0 to OpenDlg.Files.Count - 1 do
      try
        OpenDesignFile(OpenDlg.Files[i]);
      except
        on E: Exception do MessageDlg(lAppName, Format(rsCannotOpen2, [OpenDlg.Files[i], E.Message]), mtError, [mbOK], 0);
      end;
  finally
    OpenDlg.Options := OpenDlg.Options - [ofAllowMultiSelect];
  end;
end;

{ ===========================================================================
  TfrmMain.DropFilesAt  (function)
  Parameters:
    const FileNames: array of String - the files dropped
    const ScreenPt: TPoint - where they were dropped (screen pixels)
  Returns:
    Integer - how many files were opened; 0 when the drop was not on the strip of document tabs
  Notes:
    Files dropped from the file explorer open as documents, but only when dropped on the document tab strip: a drop anywhere else on the window does nothing. A file that cannot
    be opened gives a message and the others go on; a folder is skipped.
  =========================================================================== }
function TfrmMain.DropFilesAt(const FileNames: array of String; const ScreenPt: TPoint): Integer;
var
  i: Integer;
  P: TPoint;
begin
  Result := 0;
  P := tcDocs.ScreenToClient(ScreenPt);
  if not PtInRect(tcDocs.ClientRect, P) then
    Exit;
  for i := 0 to High(FileNames) do
  begin
    if DirectoryExists(FileNames[i]) then
      Continue;
    try
      OpenDesignFile(FileNames[i]);
      Inc(Result);
    except
      on E: Exception do ReportProblem(Format(rsCannotOpen2, [FileNames[i], E.Message]));
    end;
  end;
end;

{ ===========================================================================
  TfrmMain.FormDropFiles  (procedure)
  Parameters:
    Sender: TObject - the form
    const FileNames: array of String - the files dropped on the window
  Notes:
    Form event: files dragged from the file explorer. They open when dropped on the document tab strip (DropFilesAt) and are ignored anywhere else.
  =========================================================================== }
procedure TfrmMain.FormDropFiles(Sender: TObject; const FileNames: array of String);
begin
  DropFilesAt(FileNames, Mouse.CursorPos);
end;

{ ===========================================================================
  TfrmMain.DoSave  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Menu handler: saves to the current file, or asks for a name if untitled.
  =========================================================================== }
procedure TfrmMain.DoSave(Sender: TObject);
begin
  if FDesign = nil then
    Exit;
  if IsSymbolDoc then begin
    DoStoreSymbol(Sender);
    Exit;
  end;       // a symbol is stored in its library
  if FFileName = '' then
    DoSaveAs(Sender)
  else
  try
    FDesign.SaveToFile(FFileName);
    FModified := False;
    UpdateFormTitle;
    NoteFileUsed(FFileName);
  except
    on E: Exception do MessageDlg(lAppName, Format(rsCannotSaveTheFile, [E.Message]), mtError, [mbOK], 0);
  end;
end;

{ ===========================================================================
  Save All, and the designs that were open (additions: TinyCAD has neither; its own SaveAll is only the helper of the automatic save)
  =========================================================================== }

{ ===========================================================================
  TfrmMain.SaveAllDocuments  (function)
  Parameters:
    AskNames: Boolean - flag
    out Skipped: Integer - whole number (out: set by the call)
    out FailedNames: String - text (out: set by the call)
  Returns:
    Integer
  Notes:
    Saves every open design that has unsaved changes, to its own file, one after another; a
    design that cannot be written does not stop the others. The design that was showing is
    showing again afterwards. A design without changes is not written again.
  =========================================================================== }
function TfrmMain.SaveAllDocuments(AskNames: Boolean; out Skipped: Integer; out FailedNames: String): Integer;
var
  i, Keep: Integer;
  StoreMsg: String;
begin
  Result := 0;
  Skipped := 0;
  FailedNames := '';
  Keep := FCurrent;
  for i := 0 to FDocs.Count - 1 do
    if FDocs[i].Modified then
    begin
      if FDocs[i].Symbol <> nil then
      begin
        { a symbol is stored in its library, as it is (names and attributes as they are now) }
        if StoreSymbolDoc(FDocs[i], StoreMsg) then
          Inc(Result) else begin
            Inc(Skipped);
            FailedNames := FailedNames + FDocs[i].DisplayName + #10;
          end;
      end
      else if FDocs[i].FileName = '' then
      begin
        if AskNames then
        begin
          ActivateDocument(i);
          DoSaveAs(nil);
          if not FDocs[i].Modified then
            Inc(Result)
          else
            Inc(Skipped);
        end
        else
          Inc(Skipped);
      end
      else
        try
          FDocs[i].Design.SaveToFile(FDocs[i].FileName);
          FDocs[i].Modified := False;
          NoteFileUsed(FDocs[i].FileName);
          Inc(Result);
        except
          FailedNames := FailedNames + FDocs[i].FileName + #10;
        end;
    end;
  if (Keep >= 0) and (Keep < FDocs.Count) then
    ActivateDocument(Keep);
  UpdateDocTabs;
  UpdateFormTitle;
end;

{ ===========================================================================
  TfrmMain.DoSaveAll  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler (File > Save All, Ctrl+Shift+S, the ribbon): saves every design that has unsaved
    changes. A design with no file name is asked for one; if some could not be written they are
    named in one message.
  =========================================================================== }
procedure TfrmMain.DoSaveAll(Sender: TObject);
var
  Skipped: Integer;
  Failed: String;
begin
  if FDocs.Count = 0 then
    Exit;
  SaveAllDocuments(True, Skipped, Failed);
  if Failed <> '' then
    MessageDlg(lAppName, Format(rsTheseCouldNotBeSaved, [Failed]), mtError, [mbOK], 0);
end;

{ ===========================================================================
  TfrmMain.DoPartsList  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler (Special > Create Parts List): drops any drawing tool, shows the Save a Parts List
    dialog and, on Export, writes the list of the current design. The choices are remembered
    when Export is pressed, whether or not the file could be written.
  =========================================================================== }
procedure TfrmMain.DoPartsList(Sender: TObject);
var
  F: TfrmPartsList;
begin
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  FView.CancelTool;
  F := TfrmPartsList.Create(Self);
  try
    F.LoadFromSettings(GetFileName);
    if F.ShowModal <> mrOK then
      Exit;
    F.KeepInSettings;
    SaveSettings;
    WritePartsList(F.FileName, F.Options);
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.DoNetList  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler (Special > Create PCB Net List): drops any drawing tool, checks the design rules
    (the Design Markers window opens when there are errors), shows the PCB Export dialog and, on
    Export, writes the netlist of the current design. The choices are remembered when Export is
    pressed, whether or not the file could be written.
  =========================================================================== }
procedure TfrmMain.DoNetList(Sender: TObject);
var
  F: TfrmNetlist;
begin
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  F := BeginNetList;
  try
    if F.ShowModal <> mrOK then
      Exit;
    ExportNetList(F);
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  AskFileToWrite  (function)
  Parameters:
    ADlg: TSaveDialog
    const ATitle: String - text
    const AFilter: String - text
    const ADefExt: String - text
    const AName: String - the name
  Returns:
    String
  Notes:
    TinyCAD's CFileDialog for a file to write (no question about replacing a file, as TinyCAD
    asks none here).
  =========================================================================== }
function AskFileToWrite(ADlg: TSaveDialog; const ATitle, AFilter, ADefExt, AName: String): String;
var
  OldFilter, OldTitle, OldExt, OldName: String;
  OldOptions: TOpenOptions;
begin
  Result := '';
  OldFilter := ADlg.Filter; OldTitle := ADlg.Title; OldExt := ADlg.DefaultExt;
  OldName := ADlg.FileName; OldOptions := ADlg.Options;
  try
    ADlg.Title := ATitle;
    ADlg.Filter := AFilter;
    ADlg.DefaultExt := ADefExt;
    ADlg.FileName := AName;
    ADlg.Options := ADlg.Options + [ofHideReadOnly] - [ofOverwritePrompt];
    if ADlg.Execute then
      Result := ADlg.FileName;
  finally
    ADlg.Filter := OldFilter; ADlg.Title := OldTitle; ADlg.DefaultExt := OldExt;
    ADlg.FileName := OldName; ADlg.Options := OldOptions;
  end;
end;

{ ===========================================================================
  TfrmMain.CheckDuplicateRefs  (function)
  Parameters:
    Quiet: Boolean - True gives the report without showing any message
  Returns:
    String - one line per duplicated reference, '' when there are none
  Notes:
    Looks at every placed symbol of every sheet of the current design (USymbolBom): symbols that share a reference are reported, except the parts of one package. The result is
    shown in a message (with how many symbols are not numbered yet, when some are); from a script the first status panel carries it instead.
  =========================================================================== }
function TfrmMain.CheckDuplicateRefs(Quiet: Boolean): String;
var
  S: TSymbolSurvey;
  Msg: String;
begin
  Result := '';
  if FDesign = nil then
    Exit;
  S := TSymbolSurvey.Create;
  try
    S.Collect(FDesign);
    Result := S.DuplicateReport;
    if Quiet then
      Exit;
    if Result = '' then
      Msg := rsNoTwoSymbolsHaveThe
    else
      Msg := Format(rsTheseReferencesAreUsedBy, [Result]);
    if S.UnnumberedCount > 0 then
      Msg := Format(rsSymbolSHaveNoNumber, [Msg, S.UnnumberedCount]);
    if FQuiet then
      sbMainBar.Panels[0].Text := Trim(StringReplace(Msg, LineEnding, ' | ', [rfReplaceAll]))
    else
      MessageDlg(lAppName, Msg, mtInformation, [mbOK], 0);
  finally
    S.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.DoCheckDupRefs  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Special > Check Duplicate References...: the report of CheckDuplicateRefs.
  =========================================================================== }
procedure TfrmMain.DoCheckDupRefs(Sender: TObject);
begin
  if FDesign = nil then
    Exit;
  FView.CancelTool;
  CheckDuplicateRefs(False);
end;

{ ===========================================================================
  TfrmMain.WriteSymbolBom  (function)
  Parameters:
    const AFileName: String - the file to write
  Returns:
    Boolean - True when the file was written
  Notes:
    Writes the table of the symbols of the current design (USymbolBom.WriteCsv, UTF-8) and warns, after writing, when some references are used twice or some symbols have no number
    yet, since the quantities would be wrong. A file that cannot be written gives a message and nothing else happens.
  =========================================================================== }
function TfrmMain.WriteSymbolBom(const AFileName: String): Boolean;
var
  S: TSymbolSurvey;
  FS: TFileStream;
  Csv: String;
  Warn: String;
begin
  Result := False;
  if FDesign = nil then
    Exit;
  S := TSymbolSurvey.Create;
  try
    S.Collect(FDesign);
    Csv := S.WriteCsv;
    try
      FS := TFileStream.Create(AFileName, fmCreate);
      try
        if Csv <> '' then
          FS.WriteBuffer(Csv[1], Length(Csv));
      finally
        FS.Free;
      end;
    except
      ReportProblem(rsCannotWriteTheBoMFile);
      Exit;
    end;
    Result := True;
    Warn := '';
    if S.DuplicateCount > 0 then
      Warn := Format(rsReferenceSAreUsedBy, [S.DuplicateCount]);
    if S.UnnumberedCount > 0 then
      Warn := Format(rsSymbolSHaveNoNumber2, [Warn, S.UnnumberedCount]);
    if Warn <> '' then
      ReportProblem(Format(rsTheQuantitiesInTheBoM, [Warn]));
  finally
    S.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.DoSymbolBom  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Special > Export Symbol BoM (CSV)...: asks for a file (the design's name with .csv to start with) and writes the table of the symbols used.
  =========================================================================== }
procedure TfrmMain.DoSymbolBom(Sender: TObject);
var
  Target, Def: String;
begin
  if FDesign = nil then
    Exit;
  FView.CancelTool;
  Def := ChangeFileExt(GetFileName, '');
  if Def = '' then
    Def := 'bom'
  else
    Def := Def + '_bom';
  Target := AskFileToWrite(SaveDlg, rsExportSymbolBoM, rsCSVFileCsvCsvAll, 'csv', Def + '.csv');
  if Target <> '' then
    WriteSymbolBom(Target);
end;

{ ===========================================================================
  SaveTextFile  (function)
  Parameters:
    const AFileName: String - the file
    const AText: String - what to put in it
  Returns:
    Boolean
  Notes:
    Writes a text to a file, replacing it; False if the file cannot be written.
  =========================================================================== }
function SaveTextFile(const AFileName, AText: String): Boolean;
var
  FS: TFileStream;
begin
  Result := False;
  try
    FS := TFileStream.Create(AFileName, fmCreate);
    try
      if AText <> '' then
        FS.WriteBuffer(AText[1], Length(AText));
    finally
      FS.Free;
    end;
    Result := True;
  except
    on E: Exception do Result := False;
  end;
end;

{ ===========================================================================
  TfrmMain.WriteSymbolData  (function)
  Parameters:
    const AFileName: String - the file to write
  Returns:
    Boolean - True when the file was written
  Notes:
    Writes the symbol data report of the current design (USymbolBom.TSymbolDataReport: the whole design is read once to list every field name, then again to put each value in
    the column of its name), UTF-8. A file that cannot be written gives a message and False.
  =========================================================================== }
function TfrmMain.WriteSymbolData(const AFileName: String): Boolean;
var
  R: TSymbolDataReport;
begin
  Result := False;
  if FDesign = nil then
    Exit;
  R := TSymbolDataReport.Create;
  try
    R.Collect(FDesign);
    Result := SaveTextFile(AFileName, R.WriteCsv);
    if not Result then
      ReportProblem(rsCannotWriteTheSymbolDataFile);
  finally
    R.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.DoSymbolData  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Special > Export Symbol Data (CSV)...: asks for a file (the design's name with _symbols.csv to start with) and writes the symbol data report.
  =========================================================================== }
procedure TfrmMain.DoSymbolData(Sender: TObject);
var
  Target, Def: String;
begin
  if FDesign = nil then
    Exit;
  FView.CancelTool;
  Def := ChangeFileExt(GetFileName, '');
  if Def = '' then
    Def := 'symbols'
  else
    Def := Def + '_symbols';
  Target := AskFileToWrite(SaveDlg, rsExportSymbolData, rsCSVFileCsvCsvAll, 'csv', Def + '.csv');
  if Target <> '' then
    WriteSymbolData(Target);
end;

{ ===========================================================================
  TfrmMain.WriteWires  (function)
  Parameters:
    const AFileName: String - the file to write
    out Count: Integer - the number of wire labels and bus names written
  Returns:
    Boolean - True when the file was written
  Notes:
    Writes the text on the wires of the current design (UWireExport.WireTextCsv), UTF-8. A file that cannot be written gives a message and False.
  =========================================================================== }
function TfrmMain.WriteWires(const AFileName: String; out Count: Integer): Boolean;
begin
  Count := 0;
  Result := False;
  if FDesign = nil then
    Exit;
  Result := SaveTextFile(AFileName, WireTextCsv(FDesign, Count));
  if not Result then
    ReportProblem(rsCannotWriteTheWiresFile);
end;

{ ===========================================================================
  TfrmMain.DoExportWires  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Special > Export Wires...: asks for a file (the design's name with _wires.csv to start with) and writes the text of every wire label and bus name.
  =========================================================================== }
procedure TfrmMain.DoExportWires(Sender: TObject);
var
  Target, Def: String;
  N: Integer;
begin
  if FDesign = nil then
    Exit;
  FView.CancelTool;
  Def := ChangeFileExt(GetFileName, '');
  if Def = '' then
    Def := 'wires'
  else
    Def := Def + '_wires';
  Target := AskFileToWrite(SaveDlg, rsExportWires, rsCSVFileCsvCsvAll, 'csv', Def + '.csv');
  if Target <> '' then
    WriteWires(Target, N);
end;

{ ===========================================================================
  TfrmMain.SpiceProposedName  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    The name the Create Spice Net List dialog proposes: the design's name with .net, or
    output.net for a design with no dot in its name.
  =========================================================================== }
function TfrmMain.SpiceProposedName: String;
begin
  Result := SpiceDefaultFileName(GetFileName);
end;

{ ===========================================================================
  TfrmMain.VhdlProposedName  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    The name the Create VHDL file dialog proposes: the design's name with .vhd, or output.vhd
    for a design with no dot in its name.
  =========================================================================== }
function TfrmMain.VhdlProposedName: String;
begin
  Result := VhdlDefaultFileName(GetFileName);
end;

{ ===========================================================================
  TfrmMain.DoSpiceNetList  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler (Special > Create Spice Net List): drops any drawing tool, checks the design rules,
    asks for the file and writes the SPICE netlist of the current design. TinyCAD opens the file
    in an editor afterwards (not done here).
  =========================================================================== }
procedure TfrmMain.DoSpiceNetList(Sender: TObject);
var
  Target: String;
begin
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  Target := AskFileToWrite(SaveDlg, rsCreateSpiceNetList, rsSPICENetNetAllFiles, 'net', BeginSpice);
  if Target = '' then
    Exit;
  ExportSpice(Target);
end;

{ ===========================================================================
  TfrmMain.DoVhdlFile  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler (Special > Create VHDL file): as DoSpiceNetList, for the VHDL file (the check made
    first is VHDL's own set of design rules).
  =========================================================================== }
procedure TfrmMain.DoVhdlFile(Sender: TObject);
var
  Target: String;
begin
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  Target := AskFileToWrite(SaveDlg, rsCreateVHDLFile, rsVHDLVhdVhdAllFiles, 'vhd', BeginVhdl);
  if Target = '' then
    Exit;
  ExportVhdl(Target);
end;

{ ===========================================================================
  TfrmMain.ExportSpice  (function)
  Parameters:
    const AFileName: String - path of the file
  Returns:
    Boolean
  Notes:
    WriteSpiceFile: the netlist goes to the file and a list of the problems found to the file's
    name with .txt. A file that cannot be written gives a message and nothing else happens (the
    netlist file is opened first; the error file is only made after it). When problems were
    found a message says how many and where they are listed (TinyCAD opens the list in an
    editor).
  =========================================================================== }
function TfrmMain.ExportSpice(const AFileName: String): Boolean;
var
  Listing, ErrText, ErrFile: String;
  ErrCount: Integer;
begin
  Result := False;
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  Listing := SpiceText(FDesign, GetFileName, SpiceStamp(Now), LineEnding, ErrText, ErrCount);
  if not SaveTextFile(AFileName, Listing) then
  begin
    ReportProblem(rsCannotWriteTheNetList);
    Exit;
  end;
  ErrFile := SpiceErrorFileName(AFileName);
  if not SaveTextFile(ErrFile, ErrText) then
  begin
    ReportProblem(rsCannotWriteTheNetList);
    Exit;
  end;
  if ErrCount > 0 then
  begin
    if ErrCount = 1 then
      ReportProblem(Format(rsErrorWasFoundWhileMaking, [ErrFile]))
    else
      ReportProblem(Format(rsErrorsWereFoundWhileMaking, [ErrCount, ErrFile]));
  end;
  Result := True;
end;

{ ===========================================================================
  TfrmMain.ExportVhdl  (function)
  Parameters:
    const AFileName: String - path of the file
  Returns:
    Boolean
  Notes:
    WriteVHDLFile. A file that cannot be written gives a message and nothing else happens.
  =========================================================================== }
function TfrmMain.ExportVhdl(const AFileName: String): Boolean;
begin
  Result := False;
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  if not SaveTextFile(AFileName, VhdlText(FDesign, AFileName, LineEnding)) then
  begin
    ReportProblem(rsCannotWriteTheNetList);
    Exit;
  end;
  Result := True;
end;

{ ===========================================================================
  TfrmMain.BeginErcDialog  (function)
  Parameters:  none
  Returns:
    TfrmErcOptions - the dialog, filled with the choices kept; the caller shows it and frees it
  Notes:
    The start of Special > Check Design Rules (CTinyCadView::OnSpecialCheck): any drawing tool
    is put away and the dialog gets the checks that are on (the registry WORD "ERC").
  =========================================================================== }
function TfrmMain.BeginErcDialog: TfrmErcOptions;
begin
  FView.CancelTool;
  Result := TfrmErcOptions.Create(Self);
  Result.LoadFromSettings;
end;

{ ===========================================================================
  TfrmMain.FinishErcDialog  (function)
  Parameters:
    F: TfrmErcOptions - the dialog, after Check was pressed
    Vhdl: Boolean - True for the VHDL check
  Returns:
    Integer - the number of errors found
  Notes:
    What Check does: the choices are kept, then the check runs and its list is shown.
  =========================================================================== }
function TfrmMain.FinishErcDialog(F: TfrmErcOptions; Vhdl: Boolean): Integer;
begin
  F.KeepInSettings;
  SaveSettings;
  Result := RunCheck(Vhdl, True);
end;

{ ===========================================================================
  TfrmMain.DoCheckRules  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler (Special > Check Design Rules): shows the options and, on Check, runs the check.
  =========================================================================== }
procedure TfrmMain.DoCheckRules(Sender: TObject);
var
  F: TfrmErcOptions;
begin
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  F := BeginErcDialog;
  try
    if F.ShowModal <> mrOK then
      Exit;
    FinishErcDialog(F, False);
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.DoVhdlCheckRules  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler (Special > VHDL Check Design Rules): as DoCheckRules, for the VHDL check.
  =========================================================================== }
procedure TfrmMain.DoVhdlCheckRules(Sender: TObject);
var
  F: TfrmErcOptions;
begin
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  F := BeginErcDialog;
  try
    if F.ShowModal <> mrOK then
      Exit;
    FinishErcDialog(F, True);
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.RunCheck  (function)
  Parameters:
    Vhdl: Boolean - True for the VHDL check
    AlwaysShow: Boolean - True to show the list even when nothing was found
  Returns:
    Integer - the number of errors
  Notes:
    DoSpecialCheck / DoSpecialVHDLCheck of the current design: the markers of an earlier check
    are taken away, the check puts its markers on the sheets and the Design Markers window shows
    the lines when there are errors or AlwaysShow (then with the line "No errors were found").
    When nothing is to be shown an open window for this design is closed (TinyCAD would leave
    the earlier list there). The checks that are on are the ones kept in the settings.
  =========================================================================== }
function TfrmMain.RunCheck(Vhdl, AlwaysShow: Boolean): Integer;
var
  PO: TPartCheckOptions;
  Msgs: TStringList;
  Doc: TDocument;
begin
  Result := 0;
  Doc := GetCurDoc;
  if (Doc = nil) or (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  FView.CancelTool;
  if (FErcDoc <> nil) and (FErcDoc <> Doc) then
    CloseErcWindow(True);
  FView.ClearSelection;                  // (the markers it may hold are about to be replaced)
  Msgs := TStringList.Create;
  try
    Result := RunErc(FDesign, ErcOptionsFromWord(Word(ProgramSettings.ErcWord)), Vhdl, False, Msgs);
    PO.Enabled := ProgramSettings.PartCheck;
    PO.Unresolved := ProgramSettings.PartCheckUnresolved;
    PO.ShowOversized := ProgramSettings.PartCheckOversized;
    Inc(Result, RunPartCheck(FDesign, PO, Msgs, Msgs.Count));      // (the parts check goes after the ERC's lines; marker k is line k)
    if (Result = 0) and AlwaysShow then
      Msgs.Add(ErcMessage(ERR_NOERROR));
    if (Result > 0) or AlwaysShow then
      ShowErcList(Doc, Msgs)
    else if FErcDoc = Doc then
      CloseErcWindow(False);
    FView.Invalidate;
  finally
    Msgs.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.ShowErcList  (procedure)
  Parameters:
    ADoc: TDocument - the document the markers are in
    Lines: TStrings - the lines of the result
  Notes:
    Opens the Design Markers window (or reuses it) with the lines (CDlgERCListBox::Open).
  =========================================================================== }
procedure TfrmMain.ShowErcList(ADoc: TDocument; Lines: TStrings);
begin
  if FErcForm = nil then
  begin
    FErcForm := TfrmErcList.Create(Self);
    FErcForm.PopupParent := Self;
    FErcForm.OnItemChosen := @ErcItemChosen;
    FErcForm.OnRecheck := @ErcRecheck;
    FErcForm.OnCloseRequest := @ErcCloseRequest;
    FErcForm.OnPcbNetlist := @ErcPcbNetlist;
    FErcForm.OnAnnotate := @ErcAnnotate;
    FErcForm.OnSpiceNetlist := @ErcSpiceNetlist;
  end;
  FErcForm.Fill(Lines);
  FErcDoc := ADoc;
  if not FErcForm.Visible then
  begin
    FErcForm.Left := Left + 217;
    FErcForm.Top := Top + 120;
    FErcForm.Show;
  end;
end;

{ ===========================================================================
  TfrmMain.CloseErcWindow  (procedure)
  Parameters:
    DoClear: Boolean - True to take the markers off the sheets
  Notes:
    Closes the Design Markers window (CDlgERCListBox::Close): the markers are taken off the
    document's sheets. Not cleared when the document is being closed.
  =========================================================================== }
procedure TfrmMain.CloseErcWindow(DoClear: Boolean);
var
  Doc: TDocument;
begin
  Doc := FErcDoc;
  FErcDoc := nil;
  if (Doc <> nil) and DoClear and (FDocs.IndexOf(Doc) >= 0) then
  begin
    Doc.View.ClearSelection;
    ClearErcMarkers(Doc.Design);
    Doc.View.Invalidate;
  end;
  if FErcForm <> nil then
  begin
    FErcForm.Fill(nil);
    FErcForm.Hide;
  end;
end;

{ ===========================================================================
  TfrmMain.ErcCloseRequest  (procedure)
  Parameters:
    Sender: TObject - the window
  Notes:
    The Close button or the window's close button.
  =========================================================================== }
procedure TfrmMain.ErcCloseRequest(Sender: TObject);
begin
  CloseErcWindow(True);
end;

{ ===========================================================================
  TfrmMain.ErcRecheck  (procedure)
  Parameters:
    Sender: TObject - the window
  Notes:
    The Re-check button: the markers are taken off and the plain check is run again, whichever
    check made the list (as TinyCAD does).
  =========================================================================== }
procedure TfrmMain.ErcRecheck(Sender: TObject);
var
  At: Integer;
begin
  if FErcDoc = nil then
    Exit;
  At := FDocs.IndexOf(FErcDoc);
  if At < 0 then
    Exit;
  if At <> FCurrent then
    ActivateDocument(At);
  RunCheck(False, True);
end;

{ ===========================================================================
  TfrmMain.BeginAnnotateDialog  (function)
  Parameters:  none
  Returns:
    TfrmAnnotate - the dialog, filled as it starts; the caller shows it and frees it
  Notes:
    The start of Special > Generate Symbol References (CTinyCadView::OnSpecialAnnotate): any
    drawing tool is put away and the dialog is filled with the choices of the last time.
  =========================================================================== }
function TfrmMain.BeginAnnotateDialog: TfrmAnnotate;
begin
  FView.CancelTool;
  Result := TfrmAnnotate.Create(Self);
  Result.SetSetup(FAnnotate);
end;

{ ===========================================================================
  TfrmMain.FinishAnnotateDialog  (function)
  Parameters:
    F: TfrmAnnotate - the dialog, after a button was pressed
    Res: TModalResult - the button: mrOK, mrYes (use the reference painter) or anything else
  Returns:
    Boolean - True if a symbol with no definition was met
  Notes:
    What the buttons do: Cancel changes nothing. The painter button keeps the choices and starts
    the reference painter at the start value. OK keeps the choices (and the two kept in the
    settings), numbers the symbols as one undo step and, when a symbol had no definition, says
    that some symbols could not be altered.
  =========================================================================== }
function TfrmMain.FinishAnnotateDialog(F: TfrmAnnotate; Res: TModalResult): Boolean;
begin
  Result := False;
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  if Res = mrYes then
  begin
    FAnnotate := F.GetSetup;
    FView.BeginRefPainter(FAnnotate.StartVal);
    Exit;
  end;
  if Res <> mrOK then
    Exit;
  FAnnotate := F.GetSetup;
  F.KeepInSettings;
  SaveSettings;
  FView.BeginChange(rsGenerateSymbolReferences);
  Result := RunAnnotate(FDesign, FView.SheetIndex, FAnnotate);
  FView.CommitChange(True);
  if Result then
    ReportProblem(rsSomeSymbolsWereMissingFrom);
end;

{ ===========================================================================
  TfrmMain.AnnotateScriptRun  (function)
  Parameters:
    Opts: TStrings - name=value answers: action (add, remove), which (all, unnum, match), match 
      (text), value (default, start), start (text typed in the start box, which chooses "Start
      at value" as typing does), all (0 or 1) and press (ok, painter, cancel)
  Returns:
    String - what the dialog showed when it started, the choices when the button was pressed,
    and what happened
  Notes:
    For tests: Special > Generate Symbol References answered the way a person does, without
    showing the dialog.
  =========================================================================== }
function TfrmMain.AnnotateScriptRun(Opts: TStrings): String;
var
  F: TfrmAnnotate;
  I: Integer;
  Key, Val, Press, Start: String;
  Res: TModalResult;
  Miss: Boolean;

  function Describe: String;
  var
    S: TAnnotateSetup;
  begin
    S := F.GetSetup;
    Result := Format('action=%s which=%s match=%s value=%s start=%s all=%d startbox=%s', [CHOOSE_ACTION[S.Action], CHOOSE_WHICH[S.Reference], S.MatchVal,
      CHOOSE_VALUE[S.Value], IntToStr(S.StartVal), Ord(S.AllSheets), F.edStart.Text]);
  end;

begin
  Result := '';
  F := BeginAnnotateDialog;
  try
    Press := 'ok';
    Start := Format('title=%s groups=%s|%s|%s|%s captions=%s|%s|%s|%s|%s|%s|%s|%s|%s buttons=%s|%s|%s', [F.Caption, F.gbAction.Caption, F.gbRefs.Caption, F.gbValue.Caption,
      F.gbPainter.Caption, F.rbAdd.Caption, F.rbRemove.Caption, F.rbAll.Caption, F.rbUnnum.Caption, F.rbMatch.Caption, F.cbAllSheets.Caption, F.rbDefault.Caption,
      F.rbStart.Caption, F.btnPainter.Caption, F.btnOK.Caption, F.btnCancel.Caption, F.btnPainter.Caption]) + ' ' + Describe;
    for I := 0 to Opts.Count - 1 do
    begin
      Key := LowerCase(Copy(Opts[I], 1, Pos('=', Opts[I]) - 1));
      Val := Copy(Opts[I], Pos('=', Opts[I]) + 1, MaxInt);
      if Key = 'action' then begin
        F.rbAdd.Checked := Val = 'add';
        F.rbRemove.Checked := Val = 'remove';
      end
      else if Key = 'which' then begin
        F.rbAll.Checked := Val = 'all';
        F.rbUnnum.Checked := Val = 'unnum';
        F.rbMatch.Checked := Val = 'match';
      end
      else if Key = 'match' then
        F.edMatch.Text := Val
      else if Key = 'value' then begin
        F.rbDefault.Checked := Val = 'default';
        F.rbStart.Checked := Val = 'start';
      end
      else if (Key = 'start') or (Key = 'startbox') then
        F.edStart.Text := Val
      else if Key = 'all' then
        F.cbAllSheets.Checked := Val = '1'
      else if Key = 'press' then
        Press := LowerCase(Val)
      else
        Result := Result + 'unknown name: ' + Key + ' ';
    end;
    if Press = 'ok' then
      Res := mrOK else if Press = 'painter' then
      Res := mrYes
    else
      Res := mrCancel;
    Result := Result + 'start ' + Start + ' | pressed ' + Press + ' ' + Describe;
    Miss := FinishAnnotateDialog(F, Res);
    Result := Result + Format(' | done missing=%d type=%d allsheets=%d tool=%d refstart=%d', [Ord(Miss), ProgramSettings.AnnotateType, Ord(ProgramSettings.AnnotateAllSheets),
      Ord(FView.Tool), FView.RefPainterStart]);
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.AnnotateRefsText  (function)
  Parameters:  none
  Returns:
    String - the symbols of every sheet
  Notes:
    For tests: each sheet's placed symbols as index:reference:part:x:y, separated by semicolons,
    the sheets by " | ".
  =========================================================================== }
function TfrmMain.AnnotateRefsText: String;
var
  I, J: Integer;
  M: TDrawMethod;
begin
  Result := '';
  if FDesign = nil then
    Exit;
  for I := 0 to FDesign.SheetCount - 1 do
  begin
    if I > 0 then
      Result := Result + ' | ';
    for J := 0 to FDesign.Sheets[I].Drawing.Count - 1 do
      if FDesign.Sheets[I].Drawing[J].GetType = xMethodEx3 then
      begin
        M := FDesign.Sheets[I].Drawing[J] as TDrawMethod;
        Result := Result + Format('%d:%s:%d:%.6g:%.6g;', [J, StringReplace(M.GetRef, ' ', '_', [rfReplaceAll]), M.Part, M.PointA.x, M.PointA.y], DefaultFormatSettings);
      end;
  end;
end;

{ ===========================================================================
  TfrmMain.DoAnnotate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler (Special > Generate Symbol References): shows the dialog and does what the button
    pressed asks.
  =========================================================================== }
procedure TfrmMain.DoAnnotate(Sender: TObject);
var
  F: TfrmAnnotate;
begin
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  if AnnotateScript <> nil then
  begin
    AnnotateReport := AnnotateScriptRun(AnnotateScript);
    Exit;
  end;
  F := BeginAnnotateDialog;
  try
    FinishAnnotateDialog(F, F.ShowModal);
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.PrinterInstalled  (function)
  Parameters:  none
  Returns:
    Boolean - True if the system has a printer
  Notes:
    Whether there is a printer to print on.
  =========================================================================== }
function TfrmMain.PrinterInstalled: Boolean;
begin
  try
    Result := Printer.Printers.Count > 0;
  except
    Result := False;
  end;
end;

{ ===========================================================================
  TfrmMain.MakePrintSink  (function)
  Parameters:
    Portrait: Boolean - True for the tall way (the sheet's orientation)
  Returns:
    TPrintSink - where the pages go; the caller frees it
  Notes:
    The installed printer turned to the orientation, or an A4 page that is only a bitmap when
    there is no printer (or when a test has asked for bitmap pages).
  =========================================================================== }
function TfrmMain.MakePrintSink(Portrait: Boolean): TPrintSink;
begin
  if PrintSinkDir <> '' then
    Result := TVirtualSink.Create(Portrait, PrintTestDpi, PrintSinkDir)
  else if PrinterInstalled then
    Result := TPrinterSink.Create(Portrait)
  else
    Result := TVirtualSink.Create(Portrait);
end;

{ ===========================================================================
  TfrmMain.BeginPrintDialog  (function)
  Parameters:  none
  Returns:
    TfrmPrint - the dialog, filled as it starts; the caller shows it and frees it
  Notes:
    The start of File > Print (CTinyCadView::OnPreparePrinting and DoPreparePrinting): any
    drawing tool is put away, the printer's page is found for the way the sheet is turned, and
    the dialog gets the sheet's size, the scale and black and white of the settings, the current
    sheet, and every page once.
  =========================================================================== }
function TfrmMain.BeginPrintDialog: TfrmPrint;
var
  Sink: TPrintSink;
  Sheet: TDesignSheet;
  PName: String;
  Names: TStringList;
  PIdx: Integer;
begin
  FView.CancelTool;
  Sheet := FDesign.Sheets[FView.SheetIndex];
  Sink := MakePrintSink(SheetIsPortrait(Sheet));
  try
    Result := TfrmPrint.Create(Self);
    Result.OnPrinterSetup := @PrinterSetupInDialog;
    Result.OnPrinterPick := @PrinterPickedInDialog;
    Result.OnPaintPage := @PrintDialogPaintPage;
    if (PrintSinkDir <> '') or PrinterInstalled then
      PName := Sink.Name
    else
      PName := '';
    Result.SetPrint(Sink.Device, Sheet.Details.PageWidth, Sheet.Details.PageHeight, FDesign.SheetCount, PName, PName <> '', ProgramSettings.PrintScale,
      ProgramSettings.PrintBandW, ProgramSettings.PrintNoSymText, ProgramSettings.PrintNoSymFields);
    Result.SetRange(0, 0, 1, False);
    Names := PrinterNames(PIdx);
    try
      Result.SetPrinters(Names, PIdx);
    finally
      Names.Free;
    end;
  finally
    Sink.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.PrinterNames  (function)
  Parameters:
    out AIndex: Integer - whole number (out: set by the call)
  Returns:
    TStringList
  Notes:
    What the Print dialog's printer drop down lists. Empty with no printer (or when the system
    cannot say).
  =========================================================================== }
function TfrmMain.PrinterNames(out AIndex: Integer): TStringList;
begin
  Result := TStringList.Create;
  AIndex := -1;
  try
    Result.Assign(Printer.Printers);
    if Result.Count > 0 then
      AIndex := Printer.PrinterIndex;
  except
    Result.Clear;
    AIndex := -1;
  end;
end;

{$IFDEF WINDOWS}
function ProbeOpenPrinter(pName: PWideChar; var H: PtrUInt; pDefault: Pointer): LongBool; stdcall; external 'winspool.drv' name 'OpenPrinterW';
function ProbeLastError: LongWord; stdcall; external 'kernel32.dll' name 'GetLastError';
function ProbeClosePrinter(H: PtrUInt): LongBool; stdcall; external 'winspool.drv' name 'ClosePrinter';
function ProbeDocumentProperties(hWnd: PtrUInt; H: PtrUInt; pName: PWideChar; pOut, pIn: Pointer; fMode: LongWord): LongInt; stdcall; external 'winspool.drv' name 'DocumentPropertiesW';
{$ENDIF}

{ ===========================================================================
  PrinterProbe  (function)
  Parameters:
    const AName: String - the printer's name
  Returns:
    String - what Windows says when the printer is opened and asked for its settings; '' when that works (and always off Windows)
  Notes:
    The library selects a printer by opening it and asking the driver for its DEVMODE; when that
    fails it only says the printer "doesn't exist". This repeats the two calls to give the real
    reason (the error number and its text), which goes into the message.
  =========================================================================== }
function PrinterProbe(const AName: String): String;
{$IFDEF WINDOWS}
var
  H: PtrUInt;
  N: LongInt;
  W: UnicodeString;
begin
  Result := '';
  W := UTF8Decode(AName);
  H := 0;
  if not ProbeOpenPrinter(PWideChar(W), H, nil) then
    Exit('OpenPrinter failed: ' + SysErrorMessage(Integer(ProbeLastError)) + ' (error ' + IntToStr(ProbeLastError) + ')');
  try
    N := ProbeDocumentProperties(0, H, PWideChar(W), nil, nil, 0);
    if N <= 0 then
      Result := 'The driver gave no settings (DocumentProperties returned ' + IntToStr(N) + ', error ' + IntToStr(ProbeLastError) + ': ' + SysErrorMessage(Integer(ProbeLastError)) + ')';
  finally
    ProbeClosePrinter(H);
  end;
end;
{$ELSE}
begin
  Result := '';
end;
{$ENDIF}

{ ===========================================================================
  TfrmMain.PrinterPickedInDialog  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    Index: Integer - zero-based index
  Notes:
    Makes that printer the one in use and gives the dialog the page it prints on (the sheet
    showing decides the way the page is turned). A printer that cannot be chosen says why and
    leaves the dialog as it was.
  =========================================================================== }
procedure TfrmMain.PrinterPickedInDialog(Sender: TObject; Index: Integer);
var
  Sink: TPrintSink;
begin
  FPrinterPicked := Index;
  try
    if PrinterInstalled and (Index >= 0) and (Index < Printer.Printers.Count) and (Printer.PrinterIndex <> Index) then
      Printer.PrinterIndex := Index;
  except
    on E: Exception do
    begin
      (Sender as TfrmPrint).RevertPrinter;      // (the list shows the printer that is still in use)
      if (Index >= 0) and (Index < Printer.Printers.Count) and (PrinterProbe(Printer.Printers[Index]) <> '') then
        ReportProblem(Format(rsThatPrinterCannotBeUsed, [E.Message, PrinterProbe(Printer.Printers[Index])]))
      else
        ReportProblem(Format(rsThatPrinterCannotBeUsed2, [E.Message]));
      Exit;
    end;
  end;
  Sink := MakePrintSink(SheetIsPortrait(FDesign.Sheets[FView.SheetIndex]));
  try
    (Sender as TfrmPrint).SetDevice(Sink.Device, Sink.Name);
  finally
    Sink.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.PrinterSetupInDialog  (function)
  Parameters:
    Sender: TObject - the component that raised the event
  Returns:
    Boolean
  Notes:
    The Properties button of the Print dialog. On Windows it opens the properties window of the
    printer chosen in the drop down directly (the driver's own: orientation, paper, quality...),
    so the printer need not be picked again; the window gives no OK/Cancel answer, so the page
    is always read again afterwards. Elsewhere it is the system's printer setup dialog (the one
    File > Print Setup... shows), which has no direct route to the properties. Then the page the
    printer now has is the one the dialog lays pages out on. With no printer it says so.
  =========================================================================== }
function TfrmMain.PrinterSetupInDialog(Sender: TObject): Boolean;
var
  F: TfrmPrint;
  Sink: TPrintSink;
  Names: TStringList;
  PIdx: Integer;
begin
  Result := False;
  F := Sender as TfrmPrint;
  if not PrinterInstalled then
  begin
    ReportProblem(rsNoPrinterIsInstalled2);
    Exit;
  end;
  {$IFDEF WINDOWS}
  if Printer is TWinPrinter then
  begin
    try
      if (FPrinterPicked >= 0) and (FPrinterPicked < Printer.Printers.Count) and (Printer.PrinterIndex <> FPrinterPicked) then
        Printer.PrinterIndex := FPrinterPicked;
      // the properties window comes up inside the Print dialog (see osver.PrinterCBTHook)
      BeginPrinterDlgPlacement(Rect(F.Left, F.Top, F.Left + F.Width, F.Top + F.Height), F.Handle);
      try
        TWinPrinter(Printer).AdvancedProperties;
      finally
        EndPrinterDlgPlacement;
      end;
    except
      on E: Exception do
      begin
        ReportProblem(Format(rsThePrinterPropertiesCannotBe, [E.Message]));
        Exit;
      end;
    end;
  end
  else
  {$ENDIF}
  if not dlgPrinterSetup.Execute then
    Exit;
  Sink := MakePrintSink(SheetIsPortrait(FDesign.Sheets[FView.SheetIndex]));       // (the printer may have another page now)
  try
    F.SetDevice(Sink.Device, Sink.Name);
  finally
    Sink.Free;
  end;
  Names := PrinterNames(PIdx);
  try
    F.SetPrinters(Names, PIdx);
  finally
    Names.Free;
  end;
  Result := True;
end;

{ ===========================================================================
  TfrmMain.PrintDialogPaintPage  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    const L: TPrintLayout
    const Dev: TPrintDevice
    PageNo: Integer - whole number
    ACanvas: TCanvas - the canvas to draw on
    PxW: Integer - whole number
    PxH: Integer - whole number
    Black: Boolean - flag
    Factor: Double - number
  Notes:
    The quick preview of the Print dialog: the page drawn by the code that prints it
    (RenderPrintPage) for the sheet showing (the sheets of the design when all are printed).
  =========================================================================== }
procedure TfrmMain.PrintDialogPaintPage(Sender: TObject; const L: TPrintLayout; const Dev: TPrintDevice; PageNo: Integer; ACanvas: TCanvas; PxW, PxH: Integer;
  Black: Boolean; Factor: Double);
begin
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  RenderPrintPage(FDesign, FView.SheetIndex, L, Dev, PageNo, ACanvas, PxW, PxH, Black, Factor, ProgramSettings.PrintNoSymText, ProgramSettings.PrintNoSymFields);
end;

{ ===========================================================================
  TfrmMain.FinishPrintDialog  (function)
  Parameters:
    F: TfrmPrint - the dialog, after a button was pressed
    Res: TModalResult - the button
  Returns:
    Integer - the pages sent to the printer for one copy, or -1 when nothing was printed
  Notes:
    OK (when it is not dimmed) keeps the scale in the settings and prints the pages asked for on
    the printer (the printer is turned the way the sheet showing is; the layout is made from
    that sheet, as TinyCAD does). A print that fails says why. Cancel prints nothing.
  =========================================================================== }
function TfrmMain.FinishPrintDialog(F: TfrmPrint; Res: TModalResult): Integer;
var
  Sink: TPrintSink;
  Title: String;
begin
  Result := -1;
  if (Res <> mrOK) or (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  if not F.btnOK.Enabled then
    Exit;          // (with no printer the OK button is dimmed and cannot be pressed)
  F.KeepInSettings;
  Title := ExtractFileName(FDesign.FileName);
  if Title = '' then
    Title := rsUntitled;
  Sink := MakePrintSink(SheetIsPortrait(FDesign.Sheets[FView.SheetIndex]));
  try
    try
      Result := RunPrintJob(FDesign, FView.SheetIndex, F.GetOptions, Sink, Title);
    except
      on E: Exception do
      begin
        ReportProblem(Format(rsTheDesignCouldNotBe, [E.Message]));
        Result := -1;
      end;
    end;
  finally
    Sink.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.BeginExportImage  (function)
  Parameters:  none
  Returns:
    TfrmExportImage - the dialog, filled as it starts; the caller shows it and frees it
  Notes:
    The start of File > Export Image: any drawing tool is put away, then the dialog gets the
    remembered kind, scale and turn, the design's name for the file, and whether a selection or
    the whole sheet will be saved.
  =========================================================================== }
function TfrmMain.BeginExportImage: TfrmExportImage;
begin
  FView.CancelTool;
  Result := TfrmExportImage.Create(Self);
  Result.LoadFromSettings(GetFileName, FView.SelectedCount > 0);
end;

{ ===========================================================================
  TfrmMain.ExportImageFile  (function)
  Parameters:
    F: TfrmExportImage - the dialog, after Export
  Returns:
    Boolean - True when the file was written
  Notes:
    Keeps the dialog's choices (whether or not the file could be written) and saves the picture
    of the selected objects, or of the sheet showing when nothing is selected. A file that
    cannot be written gives a message and nothing else happens.
  =========================================================================== }
function TfrmMain.ExportImageFile(F: TfrmExportImage): Boolean;
var
  Sel: TList;
  I: Integer;
begin
  Result := False;
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  F.KeepInSettings;
  SaveSettings;
  Sel := TList.Create;
  try
    for I := 0 to FView.SelectedCount - 1 do Sel.Add(FView.SelectedObject(I));
    try
      ExportImage(FDesign, FView.SheetIndex, Sel, F.Kind, F.Scale, F.Rotate, F.FileName);
    except
      on E: Exception do
      begin
        ReportProblem(rsCannotWriteTheImageFile);
        Exit;
      end;
    end;
  finally
    Sel.Free;
  end;
  Result := True;
end;

{ ===========================================================================
  TfrmMain.DoExportImage  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Handler (File > Export Image...): shows the Export Image dialog and, on Export, saves the
    picture.
  =========================================================================== }
procedure TfrmMain.DoExportImage(Sender: TObject);
var
  F: TfrmExportImage;
begin
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  F := BeginExportImage;
  try
    if F.ShowModal <> mrOK then
      Exit;
    ExportImageFile(F);
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.DoPrint  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Handler (File > Print...): shows the Print dialog and prints what it asks for.
  =========================================================================== }
procedure TfrmMain.DoPrint(Sender: TObject);
var
  F: TfrmPrint;
begin
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  if PrintScript <> nil then
  begin
    PrintReport := PrintScriptRun(PrintScript);
    Exit;
  end;
  F := BeginPrintDialog;
  try
    FinishPrintDialog(F, F.ShowModal);
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.PrintScriptRun  (function)
  Parameters:
    Opts: TStrings - name=value answers: scale (text typed in the Scale box), bw (0 or 1), sheet
      s (current, all), fit (0 or 1), from, to, copies, collate (the pages and copies the
      system's Print dialog would give) and press (ok, cancel)
  Returns:
    String - what the dialog showed when it started, the choices when the button was pressed,
    and what happened
  Notes:
    For tests: File > Print answered the way a person does, without showing the dialog.
  =========================================================================== }
function TfrmMain.PrintScriptRun(Opts: TStrings): String;
var
  F: TfrmPrint;
  I, From, To_, Cop, Pages: Integer;
  Key, Val, Press, Start, Err: String;
  Coll: Boolean;
  O: TPrintOptions;
  RangeVal, PreviewFile, Printers: String;
  HaveRange: Boolean;
  Moves: TStringList;
  Names: TStringList;
  Bmp: TBitmap;
  Png: TPortableNetworkGraphic;
  K: Integer;

  function PageListOf(const A: TPageArray): String;
  var
    J: Integer;
  begin
    Result := '';
    for J := 0 to High(A) do
      Result := Result + IfThen(J > 0, ',', '') + IntToStr(A[J]);
  end;

  function Describe: String;
  begin
    O := F.GetOptions;
    Result := Format('printer=%s scale=%s bw=%d nosymtext=%d nosymfields=%d sheets=%s fit=%d edit=%d range=[%s] pages=[%s] ok=%d', [F.PrinterName, F.edScale.Text, Ord(F.cbBW.Checked), Ord(F.cbNoSymText.Checked), Ord(F.cbNoSymFields.Checked),
      IfThen(O.AllSheets, 'all', 'current'), Ord(F.cbFit.Checked), Ord(F.edScale.Enabled), F.RangeText, F.PagesText, Ord(F.btnOK.Enabled)]);
    Result := Result + Format(' list=[%s] box=[%s] printers=[%s] sel=%d listenabled=%d setupenabled=%d picked=%d shown=%d pageof=[%s] slider=%d..%d@%d slideron=%d back=%d fwd=%d ' +
      'status=[%s]', [PageListOf(O.Pages), F.edPageRange.Text, StringReplace(F.cbPrinterList.Items.Text, LineEnding, '|', [rfReplaceAll]), F.cbPrinterList.ItemIndex,
      Ord(F.cbPrinterList.Enabled), Ord(F.btnPrinterSetup.Enabled), FPrinterPicked, F.ShownPage, F.PageOfText, F.tbPageSlider.Min, F.tbPageSlider.Max, F.tbPageSlider.Position,
      Ord(F.tbPageSlider.Enabled), Ord(F.btnPreviewBack.Enabled), Ord(F.btnPreviewFwd.Enabled), sbMainBar.Panels[0].Text]);
  end;

begin
  Result := '';
  if FDesign = nil then begin
    Result := 'ERROR no design is open';
    Exit;
  end;
  Result := '';
  F := BeginPrintDialog;
  try
    Press := 'ok';
    From := 0; To_ := 0; Cop := 1; Coll := False;
    HaveRange := False; RangeVal := ''; PreviewFile := ''; Printers := '';
    Moves := TStringList.Create;
    FPrinterPicked := -1;
    Start := Format('title=%s groups=%s|%s|%s|%s captions=%s|%s|%s|%s|%s|%s buttons=%s|%s|%s sheetsenabled=%d ', [F.Caption, F.gbPrinter.Caption, F.gbSheets.Caption,
      F.gbPages.Caption, F.gbOptions.Caption, F.rbCurrent.Caption, F.rbAll.Caption, F.cbBW.Caption, F.lbScale.Caption, F.cbFit.Caption, F.btnPrinterSetup.Caption, F.cbPrinterList.Text,
      F.btnOK.Caption, F.btnCancel.Caption, Ord(F.rbAll.Enabled)]) + Describe;
    for I := 0 to Opts.Count - 1 do
    begin
      Key := LowerCase(Copy(Opts[I], 1, Pos('=', Opts[I]) - 1));
      Val := Copy(Opts[I], Pos('=', Opts[I]) + 1, MaxInt);
      if Key = 'scale' then
        F.edScale.Text := Val
      else if Key = 'bw' then
        F.cbBW.Checked := Val = '1'
      else if Key = 'nosymtext' then
        F.cbNoSymText.Checked := Val = '1'
      else if Key = 'nosymfields' then
        F.cbNoSymFields.Checked := Val = '1'
      else if Key = 'sheets' then begin
        F.rbAll.Checked := Val = 'all';
        F.rbCurrent.Checked := Val <> 'all';
      end
      else if Key = 'fit' then
        F.cbFit.Checked := Val = '1'
      else if Key = 'from' then
        From := StrToIntDef(Val, 0)
      else if Key = 'to' then
        To_ := StrToIntDef(Val, 0)
      else if Key = 'copies' then
        Cop := StrToIntDef(Val, 1)
      else if Key = 'collate' then
        Coll := Val = '1'
      else if Key = 'range' then begin
        HaveRange := True;
        RangeVal := StringReplace(Val, '~', ' ', [rfReplaceAll]);
      end
      else if Key = 'printers' then
        Printers := Val
      else if Key = 'preview' then
        PreviewFile := Val
      else if (Key = 'printer') or (Key = 'radio') or (Key = 'setup') or (Key = 'page') or (Key = 'slider') or (Key = 'back') or (Key = 'fwd') then
        Moves.Add(Key + '=' + Val)
      else if Key = 'press' then
        Press := LowerCase(Val)
      else
        Result := Result + 'unknown name: ' + Key + ' ';
    end;
    F.SetRange(From, To_, Cop, Coll);
    if HaveRange then
    begin
      F.rbPagesRange.Checked := True;
      F.edPageRange.Text := RangeVal;
      F.PageRangeChanged(nil);
    end;
    if Printers <> '' then
    begin
      Names := TStringList.Create;
      try
        Names.Delimiter := '|';
        Names.StrictDelimiter := True;
        Names.DelimitedText := Printers;
        F.SetPrinters(Names, 0);
      finally
        Names.Free;
      end;
    end;
    for K := 0 to Moves.Count - 1 do
    begin
      Key := Copy(Moves[K], 1, Pos('=', Moves[K]) - 1);
      Val := Copy(Moves[K], Pos('=', Moves[K]) + 1, MaxInt);
      if Key = 'radio' then begin
        F.rbPagesRange.Checked := Val = 'range';
        F.rbPagesAll.Checked := Val <> 'range';
        F.PagesRadioClick(nil);
      end
      else if Key = 'printer' then begin
        F.cbPrinterList.ItemIndex := StrToIntDef(Val, 0);
        F.PrinterListChange(nil);
      end
      else if Key = 'setup' then
        F.btnPrinterSetup.Click
      else if Key = 'page' then
        F.ShowPage(StrToIntDef(Val, 1))
      else if Key = 'slider' then
        F.tbPageSlider.Position := StrToIntDef(Val, 1)
      else if Key = 'back' then
        F.btnPreviewBack.Click
      else if Key = 'fwd' then
        F.btnPreviewFwd.Click;
    end;
    Moves.Free;
    if PreviewFile <> '' then
    begin
      Bmp := TBitmap.Create;
      Png := TPortableNetworkGraphic.Create;
      try
        Bmp.SetSize(F.pbFastPreview.Width, F.pbFastPreview.Height);
        F.DrawPreview(Bmp.Canvas, Bmp.Width, Bmp.Height);
        Png.Assign(Bmp);
        Png.SaveToFile(PreviewFile);
      finally
        Png.Free;
        Bmp.Free;
      end;
    end;
    Err := F.ValidationError;
    Result := Result + 'start ' + Start + ' | pressed ' + Press + ' ' + Describe + ' err=[' + Err + ']';
    if (Press = 'ok') and (Err <> '') then
      Result := Result + ' | stays open'
    else
    begin
      Pages := FinishPrintDialog(F, IfThen(Press = 'ok', mrOK, mrCancel));
      Result := Result + Format(' | done printed=%d scalekept=%s bwkept=%d tool=%d', [Pages, FormatCG(ProgramSettings.PrintScale, 6, 0), Ord(ProgramSettings.PrintBandW),
        Ord(FView.Tool)]);
    end;
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.BeginPreview  (function)
  Parameters:  none
  Returns:
    TfrmPreview - the window, with its pages laid out; the caller shows it and frees it
  Notes:
    The start of File > Print Preview: any drawing tool is put away (OnPreparePrinting), and the
    pages are those of every sheet at the scale and black and white of the settings, on the
    printer's page (an A4 page with no printer).
  =========================================================================== }
function TfrmMain.BeginPreview: TfrmPreview;
var
  O: TPrintOptions;
begin
  FView.CancelTool;
  O := DefaultPrintOptions;
  O.Scale := ProgramSettings.PrintScale;
  O.BlackWhite := ProgramSettings.PrintBandW;
  O.NoSymbolText := ProgramSettings.PrintNoSymText;
  O.NoSymbolFields := ProgramSettings.PrintNoSymFields;
  O.AllSheets := True;
  Result := TfrmPreview.Create(Self);
  Result.SetPreview(FDesign, FView.SheetIndex, MakePrintSink(SheetIsPortrait(FDesign.Sheets[FView.SheetIndex])), O);
end;

{ ===========================================================================
  TfrmMain.DoPrintPreview  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Handler (File > Print Preview): shows the preview; its Print button goes on to the Print
    dialog.
  =========================================================================== }
procedure TfrmMain.DoPrintPreview(Sender: TObject);
var
  F: TfrmPreview;
  Res: TModalResult;
begin
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  if PreviewScript <> nil then
  begin
    PreviewReport := PreviewScriptRun(PreviewScript);
    Exit;
  end;
  F := BeginPreview;
  try
    Res := F.ShowModal;
  finally
    F.Free;
  end;
  if Res = mrYes then
    DoPrint(nil);
end;

{ ===========================================================================
  TfrmMain.PreviewScriptRun  (function)
  Parameters:
    Ops: TStrings - what is done, in order: next, prev, two, zoomin, zoomout, page=<n> (the page
       is drawn and kept as page_<n>.png in PrintSinkDir), info (nothing) and last press=close
      or press=print
  Returns:
    String - the window's state when it opened and after each action
  Notes:
    For tests: File > Print Preview worked like a person, without showing the window.
  =========================================================================== }
function TfrmMain.PreviewScriptRun(Ops: TStrings): String;
var
  F: TfrmPreview;
  I: Integer;
  Op, Arg: String;
  Res: TModalResult;
  B: TBitmap;
  PNG: TPortableNetworkGraphic;
begin
  Result := '';
  if FDesign = nil then begin
    Result := 'ERROR no design is open';
    Exit;
  end;
  Result := '';
  Res := mrOK;
  F := BeginPreview;
  try
    Result := 'start ' + F.InfoText;
    for I := 0 to Ops.Count - 1 do
    begin
      Op := LowerCase(Ops[I]);
      Arg := '';
      if Pos('=', Op) > 0 then begin
        Arg := Copy(Op, Pos('=', Op) + 1, MaxInt);
        Op := Copy(Op, 1, Pos('=', Op) - 1);
      end;
      if Op = 'next' then
        F.NextPage
      else if Op = 'prev' then
        F.PrevPage
      else if Op = 'two' then
        F.ToggleTwoPage
      else if Op = 'zoomin' then
        F.ZoomIn
      else if Op = 'zoomout' then
        F.ZoomOut
      else if Op = 'page' then
      begin
        B := F.PageBitmap(StrToIntDef(Arg, 0));
        if (B <> nil) and (PrintSinkDir <> '') then
        begin
          ForceDirectories(PrintSinkDir);
          PNG := TPortableNetworkGraphic.Create;
          try
            PNG.Assign(B);
            PNG.SaveToFile(IncludeTrailingPathDelimiter(PrintSinkDir) + Format('preview_%s.png', [Arg]));
          finally
            PNG.Free;
          end;
        end;
        if B <> nil then
          Result := Result + Format(' | page %s %dx%d', [Arg, B.Width, B.Height])
        else
          Result := Result + Format(' | page %s none', [Arg]);
        Continue;
      end
      else if Op = 'press' then
      begin
        if Arg = 'print' then
          Res := mrYes
        else
          Res := mrOK;
        Result := Result + ' | press ' + Arg;
        Continue;
      end
      else if Op <> 'info' then
      begin
        Result := Result + ' | unknown: ' + Op;
        Continue;
      end;
      Result := Result + ' | ' + Op + ' ' + F.InfoText;
    end;
  finally
    F.Free;
  end;
  if Res = mrYes then
    DoPrint(nil);
end;

{ ===========================================================================
  TfrmMain.DoPrintSetup  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Handler (File > Print Setup...): the system's dialog for the printer and its settings (a
    TPrinterSetupDialog). With no printer it says so.
  =========================================================================== }
procedure TfrmMain.DoPrintSetup(Sender: TObject);
begin
  if not PrinterInstalled then
  begin
    ReportProblem(rsNoPrinterIsInstalled2);
    Exit;
  end;
  dlgPrinterSetup.Execute;
end;

{ ===========================================================================
  TfrmMain.PrinterPageFor  (function)
  Parameters:
    Choose: Boolean - True to show the printer's page setup dialog (a TPageSetupDialog) first
    out HorzMm: Integer - the printer's page width in whole millimetres
    out VertMm: Integer - and its height
  Returns:
    Boolean - True if there is a printer page to use
  Notes:
    What the Printer Paper and Printer Setup buttons of the Page Setup dialog ask for
    (CDlgPageSizeBox::SetPrinter). With no printer it says so and returns False; a cancelled
    dialog also returns False.
  =========================================================================== }
function TfrmMain.PrinterPageFor(Choose: Boolean; out HorzMm, VertMm: Integer): Boolean;
var
  Sink: TPrinterSink;
  P: Integer;
begin
  Result := False;
  HorzMm := 0;
  VertMm := 0;
  if PrinterPageScript <> '' then
  begin
    P := Pos('x', PrinterPageScript);
    if P > 0 then
    begin
      HorzMm := StrToIntDef(Copy(PrinterPageScript, 1, P - 1), 0);
      VertMm := StrToIntDef(Copy(PrinterPageScript, P + 1, MaxInt), 0);
      Result := (HorzMm > 0) and (VertMm > 0);
    end
    else
      ReportProblem(rsNoPrinterIsInstalled2);
    Exit;
  end;
  if not PrinterInstalled then
  begin
    ReportProblem(rsNoPrinterIsInstalled2);
    Exit;
  end;
  if Choose and (not dlgPageSetup.Execute) then
    Exit;
  Sink := TPrinterSink.Create(False);
  try
    HorzMm := Sink.Device.HorzMm;
    VertMm := Sink.Device.VertMm;
  finally
    Sink.Free;
  end;
  Result := (HorzMm > 0) and (VertMm > 0);
end;

{ ===========================================================================
  TfrmMain.ErcAnnotate  (procedure)
  Parameters:
    Sender: TObject - the window
  Notes:
    The Generate Symbol References button of the Design Markers window: the command of the
    Special menu, for the design the markers are in.
  =========================================================================== }
procedure TfrmMain.ErcAnnotate(Sender: TObject);
var
  At: Integer;
begin
  if FErcDoc = nil then
    Exit;
  At := FDocs.IndexOf(FErcDoc);
  if At < 0 then
    Exit;
  if At <> FCurrent then
    ActivateDocument(At);
  DoAnnotate(Sender);
end;

{ ===========================================================================
  TfrmMain.ErcPcbNetlist  (procedure)
  Parameters:
    Sender: TObject - the window
  Notes:
    The Generate PCB Netlist button: Special > Create PCB Net List for the design.
  =========================================================================== }
procedure TfrmMain.ErcPcbNetlist(Sender: TObject);
var
  At: Integer;
begin
  if FErcDoc = nil then
    Exit;
  At := FDocs.IndexOf(FErcDoc);
  if At < 0 then
    Exit;
  if At <> FCurrent then
    ActivateDocument(At);
  DoNetList(nil);
end;

{ ===========================================================================
  TfrmMain.ErcSpiceNetlist  (procedure)
  Parameters:
    Sender: TObject - the window
  Notes:
    The Generate SPICE Netlist button: Special > Create Spice Net List for the design.
  =========================================================================== }
procedure TfrmMain.ErcSpiceNetlist(Sender: TObject);
var
  At: Integer;
begin
  if FErcDoc = nil then
    Exit;
  At := FDocs.IndexOf(FErcDoc);
  if At < 0 then
    Exit;
  if At <> FCurrent then
    ActivateDocument(At);
  DoSpiceNetList(nil);
end;

{ ===========================================================================
  TfrmMain.pnlMainClick  (procedure)
  Parameters:
    Sender: TObject - the panel
  Notes:
    Handler for a click on the main panel; the user's design wired it but it does nothing yet.
  =========================================================================== }
procedure TfrmMain.pnlMainClick(Sender: TObject);
begin

end;

{ ===========================================================================
  TfrmMain.ErcItemChosen  (procedure)
  Parameters:
    Sender: TObject - the window
    Index: Integer - the line chosen
  Notes:
    CDlgERCListBox::OnClick: shows the marker with that number: the document and the sheet it is
    on, the sheet scrolled to put the marker in the middle (the zoom is the user's), the marker
    selected and brought to the front of the sheet's objects.
  =========================================================================== }
procedure TfrmMain.ErcItemChosen(Sender: TObject; Index: Integer);
var
  At, Si, Oi: Integer;
  Sh: TDesignSheet;
  Obj: TDrawingObject;
begin
  if FErcDoc = nil then
    Exit;
  At := FDocs.IndexOf(FErcDoc);
  if At < 0 then
    Exit;
  if At <> FCurrent then
    ActivateDocument(At);
  FView.BeginTool(vtSelect);                 // (any drawing tool is put away first)
  for Si := 0 to FDesign.SheetCount - 1 do
  begin
    Sh := FDesign.Sheets[Si];
    for Oi := 0 to Sh.Drawing.Count - 1 do
    begin
      Obj := Sh.Drawing[Oi];
      if (Obj.GetType = xError) and ((Obj as TDrawError).ErrorNumber = Index) then
      begin
        if Si <> FView.SheetIndex then
        begin
          tcSheetTabs.TabIndex := Si;        // as clicking that sheet's tab
          SheetTabChange(tcSheetTabs);
        end;
        FView.ClearSelection;
        Sh.Drawing.Move(Oi, Sh.Drawing.Count - 1);       // BringToFront: it must be on top to show as chosen
        FView.CenterOnPoint(Obj.PointA);
        FView.SelectObject(Obj, False);
        FView.Invalidate;
        Exit;
      end;
    end;
  end;
end;

{ ===========================================================================
  TfrmMain.BeginNetList  (function)
  Parameters:  none
  Returns:
    TfrmNetlist - the PCB Export dialog, filled as it starts; the caller shows it and frees it
  Notes:
    The start of Special > Create PCB Net List (CTinyCadView::OnSpecialNet): any drawing tool is
    put away, the design rules are checked (the list shows only when there are errors), then the
    dialog is made.
  =========================================================================== }
function TfrmMain.BeginNetList: TfrmNetlist;
begin
  FView.CancelTool;
  RunCheck(False, False);
  Result := TfrmNetlist.Create(Self);
  Result.LoadFromSettings(GetFileName);
end;

{ ===========================================================================
  TfrmMain.BeginSpice  (function)
  Parameters:  none
  Returns:
    String - the file name the Save dialog proposes
  Notes:
    The start of Special > Create Spice Net List: any drawing tool is put away and the design
    rules are checked, then the name to propose is worked out.
  =========================================================================== }
function TfrmMain.BeginSpice: String;
begin
  FView.CancelTool;
  RunCheck(False, False);
  Result := SpiceProposedName;
end;

{ ===========================================================================
  TfrmMain.BeginVhdl  (function)
  Parameters:  none
  Returns:
    String - the file name the Save dialog proposes
  Notes:
    The start of Special > Create VHDL file: any drawing tool is put away and the VHDL design
    rules are checked, then the name to propose is worked out.
  =========================================================================== }
function TfrmMain.BeginVhdl: String;
begin
  FView.CancelTool;
  RunCheck(True, False);
  Result := VhdlProposedName;
end;

{ ===========================================================================
  TfrmMain.ErcWindowOpen  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    Whether the Design Markers window is showing.
  =========================================================================== }
function TfrmMain.ErcWindowOpen: Boolean;
begin
  Result := (FErcForm <> nil) and FErcForm.Visible and (FErcDoc <> nil);
end;

{ ===========================================================================
  TfrmMain.ErcChoose  (procedure)
  Parameters:
    Index: Integer - the line
  Notes:
    For tests: chooses a line of the Design Markers window as a click does.
  =========================================================================== }
procedure TfrmMain.ErcChoose(Index: Integer);
begin
  if FErcForm <> nil then
    FErcForm.ChooseItem(Index);
end;

{ ===========================================================================
  TfrmMain.ErcPress  (procedure)
  Parameters:
    const AButton: String - close, recheck or annotate
  Notes:
    For tests: presses a button of the Design Markers window (a dimmed button does nothing).
  =========================================================================== }
procedure TfrmMain.ErcPress(const AButton: String);
var
  B: TButton;
begin
  if FErcForm = nil then
    Exit;
  if AButton = 'close' then
    B := FErcForm.btnClose
  else if AButton = 'recheck' then
    B := FErcForm.btnRecheck
  else if AButton = 'annotate' then
    B := FErcForm.btnAnnotate
  else
    Exit;
  if B.Enabled then
  begin
    if (AButton = 'annotate') and (AnnotateScript = nil) then
    begin
      { the command's dialog would wait for a person: it is answered with Cancel (annotatenext says otherwise) }
      AnnotateScript := TStringList.Create;
      try
        AnnotateScript.Add('press=cancel');
        B.Click;
      finally
        FreeAndNil(AnnotateScript);
      end;
    end
    else
      B.Click;
  end;
end;

{ ===========================================================================
  TfrmMain.ErcWindowText  (function)
  Parameters:  none
  Returns:
    String - the text
  Notes:
    For tests: the Design Markers window: open, the document it belongs to, the number of lines,
    the line selected, whether the symbol reference button is enabled, and the lines (separated
    by |).
  =========================================================================== }
function TfrmMain.ErcWindowText: String;
var
  i: Integer;
begin
  if FErcForm = nil then
    Exit('open=0 doc=-1 items=0 selected=-1 annotate=0 lines=');
  Result := Format('open=%d doc=%d items=%d selected=%d annotate=%d title=%s lines=', [Ord(ErcWindowOpen), FDocs.IndexOf(FErcDoc), FErcForm.ItemCount,
    FErcForm.Selected, Ord(FErcForm.btnAnnotate.Enabled), FErcForm.Caption]);
  for i := 0 to FErcForm.ItemCount - 1 do Result := Result + FErcForm.ItemText(i) + '|';
end;

{ ===========================================================================
  TfrmMain.ErcMarkersText  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    For tests: the markers on the current design's sheets as sheet:number:x:y in mm (in the
    order the sheet holds them, the last is on top), then the sheet shown, how many objects are
    selected, the number of the marker if it is the one selected, where that marker is in the
    window and the window's size.
  =========================================================================== }
function TfrmMain.ErcMarkersText: String;
var
  Si, Oi, Sel: Integer;
  Obj: TDrawingObject;
  Sc: TPoint;
begin
  Result := '';
  if FDesign = nil then
    Exit;
  for Si := 0 to FDesign.SheetCount - 1 do
    for Oi := 0 to FDesign.Sheets[Si].Drawing.Count - 1 do
    begin
      Obj := FDesign.Sheets[Si].Drawing[Oi];
      if Obj.GetType = xError then
        Result := Result + Format('%d:%d:%s:%s;', [Si, (Obj as TDrawError).ErrorNumber, FormatG(Obj.PointA.x / 5), FormatG(Obj.PointA.y / 5)]);
    end;
  Sel := -1;
  Sc := Point(-1, -1);
  if (FView.SelectedCount = 1) and (FView.SelectedObject(0) is TDrawError) then
  begin
    Sel := (FView.SelectedObject(0) as TDrawError).ErrorNumber;
    Sc := FView.DesignToScreen(FView.SelectedObject(0).PointA);
  end;
  Result := Result + Format(' sheet=%d selected=%d selectedmarker=%d at=%d,%d size=%dx%d', [FView.SheetIndex, FView.SelectedCount, Sel, Sc.x, Sc.y, FView.ClientWidth, FView.ClientHeight]);
end;

{ ===========================================================================
  TfrmMain.ExportNetList  (function)
  Parameters:
    F: TfrmNetlist
  Returns:
    Boolean
  Notes:
    What Export does: the choices are kept (also when the file then cannot be written), then the
    file is written in the chosen format. Used by the menu and by the test script.
  =========================================================================== }
function TfrmMain.ExportNetList(F: TfrmNetlist): Boolean;
begin
  F.KeepInSettings;
  SaveSettings;
  Result := WriteNetList(F.FileName, F.Format);
end;

{ ===========================================================================
  TfrmMain.WriteNetList  (function)
  Parameters:
    const AFileName: String - path of the file
    AFormat: Integer - whole number
  Returns:
    Boolean
  Notes:
    Makes the netlist of the current design in a format and writes it with the platform's line
    ends. A file that cannot be written gives a message and nothing else happens. Making the
    netlist also stores the net numbers in the design's symbols (as hints, as TinyCAD does).
  =========================================================================== }
function TfrmMain.WriteNetList(const AFileName: String; AFormat: Integer): Boolean;
var
  FS: TFileStream;
  Listing: String;
begin
  Result := False;
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  Listing := NetListText(AFormat, FDesign, GetFileName);
  try
    FS := TFileStream.Create(AFileName, fmCreate);
    try
      if Listing <> '' then
        FS.WriteBuffer(Listing[1], Length(Listing));
    finally
      FS.Free;
    end;
  except
    on E: Exception do
    begin
      ReportProblem(rsCannotWriteTheNetList);
      Exit;
    end;
  end;
  Result := True;
end;

{ ===========================================================================
  TfrmMain.CurrentFileName  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    The file name of the current design, empty when it has none (or none is open).
  =========================================================================== }
function TfrmMain.CurrentFileName: String;
begin
  Result := GetFileName;
end;

{ ===========================================================================
  TfrmMain.WritePartsList  (function)
  Parameters:
    const AFileName: String - path of the file
    const Opt: TBomOptions
  Returns:
    Boolean
  Notes:
    Makes the parts list of the current design (the sheet being shown, or all sheets) and writes
    it with the platform's line ends. A file that cannot be written gives TinyCAD's message and
    nothing else happens. When some symbol still has the reference it was defined with (such as
    "U?") the list is written but a warning says it will be inaccurate and to generate the
    symbol references. TinyCAD then opens the file in a text editor; this program does not.
  =========================================================================== }
function TfrmMain.WritePartsList(const AFileName: String; const Opt: TBomOptions): Boolean;
var
  B: TBomList;
  FS: TFileStream;
  Listing: String;
begin
  Result := False;
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  B := TBomList.Create;
  try
    B.Generate(FDesign, FView.SheetIndex, Opt, GetFileName);
    Listing := B.WriteFor(Opt.FileType);
    try
      FS := TFileStream.Create(AFileName, fmCreate);
      try
        if Listing <> '' then
          FS.WriteBuffer(Listing[1], Length(Listing));
      finally
        FS.Free;
      end;
    except
      on E: Exception do
      begin
        ReportProblem(rsCannotWriteThePartsList);
        Exit;
      end;
    end;
    Result := True;
    if B.MissingRef then
      ReportProblem(rsSomeSymbolsDoNotHave);
  finally
    B.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.SaveSession  (procedure)
  Parameters:  none
  Notes:
    Remembers which designs are open: the files of those that have one, in order, and which of
    them was showing, kept in the registry with the other settings. Done when the program is
    closed. When "open the designs that were open" is not turned on in Options nothing is
    remembered (and what was remembered is forgotten, so turning it on later does not bring back
    an old list).
  =========================================================================== }
procedure TfrmMain.SaveSession;
var
  i, n: Integer;
begin
  for i := 0 to SESSION_MAX - 1 do ProgramSettings.SessionFiles[i] := '';
  ProgramSettings.SessionActive := 0;
  if ProgramSettings.ReopenDesigns then
  begin
    n := 0;
    for i := 0 to FDocs.Count - 1 do
      if (FDocs[i].FileName <> '') and (n < SESSION_MAX) then
      begin
        ProgramSettings.SessionFiles[n] := FDocs[i].FileName;
        Inc(n);
        if i = FCurrent then
          ProgramSettings.SessionActive := n;
      end;
  end;
  SaveSettings;
end;

{ ===========================================================================
  TfrmMain.RestoreSession  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    When "open the designs that were open" is on, opens again the designs remembered by
    SaveSession, in their order, and shows the one that was showing. A file that is no longer
    there or cannot be read is left out without a message (the others still open); a design that
    is already open is not opened twice.
  =========================================================================== }
function TfrmMain.RestoreSession: Integer;
var
  i, k: Integer;
  ActiveFile: String;
begin
  Result := 0;
  if not ProgramSettings.ReopenDesigns then
    Exit;
  ActiveFile := '';
  with ProgramSettings do
    if (SessionActive >= 1) and (SessionActive <= SESSION_MAX) then
      ActiveFile := SessionFiles[SessionActive - 1];
  for i := 0 to SESSION_MAX - 1 do
    if (ProgramSettings.SessionFiles[i] <> '') and FileExists(ProgramSettings.SessionFiles[i]) then
      try
        OpenDesignFile(ProgramSettings.SessionFiles[i]);
        Inc(Result);
      except
      end;
  if ActiveFile <> '' then
    for k := 0 to FDocs.Count - 1 do
      if SameFileName(FDocs[k].FileName, ActiveFile) then
      begin
        ActivateDocument(k);
        Break;
      end;
end;

{ ===========================================================================
  TfrmMain.DoSaveAs  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Menu handler: asks for a file name and saves there.
  =========================================================================== }
procedure TfrmMain.DoSaveAs(Sender: TObject);
begin
  if FDesign = nil then
    Exit;
  if IsSymbolDoc then begin
    DoStoreSymbol(Sender);
    Exit;
  end;
  SaveDlg.Filter := rsTinyCADDesignsDsnDsn;
  SaveDlg.DefaultExt := 'dsn';
  if (GetCurDoc <> nil) and (GetCurDoc.ConvertedFrom <> '') then
  begin
    { a design read from an old binary file: offer a new name next to the original, never the original itself }
    SaveDlg.InitialDir := ExtractFilePath(GetCurDoc.ConvertedFrom);
    SaveDlg.FileName := ChangeFileExt(ExtractFileName(GetCurDoc.ConvertedFrom), '') + ' (converted).dsn';
  end;
  if SaveDlg.Execute then
  begin
    FFileName := SaveDlg.FileName;
    if GetCurDoc <> nil then
      GetCurDoc.ConvertedFrom := '';
    DoSave(Sender);
  end;
end;

{ ===========================================================================
  TfrmMain.LibrariesChanged  (procedure)
  Parameters:
    Sender: TObject - the library panel
  Notes:
    A library was opened or closed: the libraries in use are kept in the settings, in the order
    they were added, for the next run.
  =========================================================================== }
procedure TfrmMain.LibrariesChanged(Sender: TObject);
var
  i: Integer;
begin
  for i := 0 to LIBRARY_MAX - 1 do
    if i < frameLibraryPanel.LibCount then
      ProgramSettings.LibraryFiles[i] := frameLibraryPanel.LibFileName(i)
    else
      ProgramSettings.LibraryFiles[i] := '';
  SaveSettings;
end;

{ ===========================================================================
  TfrmMain.LibraryIsInUse  (function)
  Parameters:
    const FileName: String - path of the file
  Returns:
    Boolean - True when it is being edited
  Notes:
    TinyCAD's IsLibInUse: a library cannot be removed or cleaned up while an editing window has
    it: a symbol of it open in the symbol editor, or a file a test lists.
  =========================================================================== }
function TfrmMain.LibraryIsInUse(const FileName: String): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to FDocs.Count - 1 do
    if (FDocs[i].Symbol <> nil) and SameFileName(FDocs[i].SymbolLibFile, FileName) then
      Result := True;
  if TestLibInUse = nil then
    Exit;
  for i := 0 to TestLibInUse.Count - 1 do
    if SameFileName(TestLibInUse[i], FileName) then
      Result := True;
end;

{ ===========================================================================
  TfrmMain.RestoreLibraries  (function)
  Parameters:  none
  Returns:
    Integer - how many libraries are open afterwards
  Notes:
    Opens the libraries that were in use when the program was last closed (TinyCAD loads its
    "Libraries" at start). A file that is gone or cannot be read is left out, and drops off the
    saved list the next time the list changes.
  =========================================================================== }
function TfrmMain.RestoreLibraries: Integer;
var
  i: Integer;
  Files: array[0..LIBRARY_MAX - 1] of String;
begin
  for i := 0 to LIBRARY_MAX - 1 do Files[i] := ProgramSettings.LibraryFiles[i];
  frameLibraryPanel.OnChanged := nil;          // (the list is not saved for every one that is opened)
  try
    for i := 0 to LIBRARY_MAX - 1 do
      if (Files[i] <> '') and FileExists(Files[i]) then
        try
          frameLibraryPanel.OpenLibrary(Files[i]);
        except
          on E: Exception do ;                // (not a library any more: left out)
        end;
  finally
    frameLibraryPanel.OnChanged := @LibrariesChanged;
  end;
  Result := frameLibraryPanel.LibCount;
end;

{ ===========================================================================
  TfrmMain.BeginLibraries  (function)
  Parameters:  none
  Returns:
    TfrmLibraries - the dialog, listing the libraries in use; the caller shows it and frees it
  Notes:
    The start of Library > Libraries...: any drawing tool is put away. Problems the dialog
    reports are shown as the program shows its others (the status bar when run from a script).
  =========================================================================== }
function TfrmMain.BeginLibraries: TfrmLibraries;
begin
  FView.CancelTool;
  Result := TfrmLibraries.Create(Self);
  Result.OnInUse := @LibraryIsInUse;
  Result.OnProblem := @ReportProblem;
  Result.Attach(frameLibraryPanel);
end;

{ ===========================================================================
  TfrmMain.DoLibraries  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Menu handler (Library > Libraries...): shows the Library Setup dialog. Its changes are made
    as they are asked for, as in TinyCAD.
  =========================================================================== }
procedure TfrmMain.DoLibraries(Sender: TObject);
var
  F: TfrmLibraries;
begin
  F := BeginLibraries;
  try
    F.ShowModal;
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  The symbol editor (TinyCAD's CTinyCadMultiSymbolDoc and the Update Library dialog): a symbol of a library is opened as a document of its own, drawn with the usual
  shape tools and the pin and origin tools, and stored back in its library
  =========================================================================== }

{ ===========================================================================
  TfrmMain.SymbolDocIndex  (function)
  Parameters:
    const LibFile: String - text
    SymbolId: Int64 - the symbol's id in that library
  Returns:
    Integer - the position in the list of documents, -1 when it is not open
  Notes:
    Finds the document in which a symbol of a library is being edited.
  =========================================================================== }
function TfrmMain.SymbolDocIndex(const LibFile: String; SymbolId: Int64): Integer;
var
  i: Integer;
begin
  Result := -1;
  if SymbolId < 0 then
    Exit;
  for i := 0 to FDocs.Count - 1 do
    if (FDocs[i].Symbol <> nil) and (FDocs[i].Symbol.SourceID = SymbolId) and SameFileName(FDocs[i].SymbolLibFile, LibFile) then
      Exit(i);
end;

{ ===========================================================================
  TfrmMain.StartSymbolDoc  (function)
  Parameters:
    Ed: TSymbolEditor - the symbol (owned by the document afterwards)
    const LibFile: String - text
  Returns:
    TDocument - the new document
  Notes:
    Makes the document for a symbol and shows it; the sheet is the symbol's drawing.
  =========================================================================== }
function TfrmMain.StartSymbolDoc(Ed: TSymbolEditor; const LibFile: String): TDocument;
var
  D: TDesignFile;
begin
  try
    D := Ed.MakeDesign;
  except
    Ed.Free;
    raise;
  end;
  Result := AddDocument(D, '');
  Result.Symbol := Ed;
  Result.SymbolLibFile := LibFile;
  UpdateDocTabs;
  UpdateFormTitle;
  RebuildSheetTabs;
  UpdateRibbonState;
end;

{ ===========================================================================
  TfrmMain.OpenSymbolDoc  (function)
  Parameters:
    LibIndex: Integer - which open library
    SetIndex: Integer - which symbol of it
  Returns:
    TDocument - the document, nil when it cannot be opened
  Notes:
    Edit symbol: opens the symbol for drawing as a document of its own. A symbol that is already
    being edited is just shown.
  =========================================================================== }
function TfrmMain.OpenSymbolDoc(LibIndex, SetIndex: Integer): TDocument;
var
  Lib: TSymbolLibrary;
  Ed: TSymbolEditor;
  At: Integer;
begin
  Result := nil;
  if (LibIndex < 0) or (LibIndex >= frameLibraryPanel.LibCount) then
    Exit;
  Lib := frameLibraryPanel.LibAt(LibIndex);
  if (SetIndex < 0) or (SetIndex >= Lib.SetCount) then
    Exit;
  At := SymbolDocIndex(Lib.FileName, Lib.Sets[SetIndex].SymbolID);
  if At >= 0 then
  begin
    ActivateDocument(At);
    Exit(FDocs[At]);
  end;
  Ed := TSymbolEditor.Create(Lib);
  try
    Ed.OpenSet(Lib.Sets[SetIndex]);
  except
    on E: Exception do
    begin
      Ed.Free;
      ReportProblem(Format(rsCannotOpenTheSymbol, [E.Message]));
      Exit;
    end;
  end;
  Result := StartSymbolDoc(Ed, Lib.FileName);
end;

{ ===========================================================================
  TfrmMain.NewSymbolDoc  (function)
  Parameters:
    LibIndex: Integer - which open library
  Returns:
    TDocument - the document, nil when there is no such library
  Notes:
    New symbol: an empty symbol with one part, no name yet (the Update Library dialog asks for
    it when the symbol is stored) and the reference prefix U?.
  =========================================================================== }
function TfrmMain.NewSymbolDoc(LibIndex: Integer): TDocument;
var
  Lib: TSymbolLibrary;
  Ed: TSymbolEditor;
begin
  Result := nil;
  if (LibIndex < 0) or (LibIndex >= frameLibraryPanel.LibCount) then
    Exit;
  Lib := frameLibraryPanel.LibAt(LibIndex);
  Ed := TSymbolEditor.Create(Lib);
  Ed.NewSymbol('', 'U?', '', 1, False);
  Result := StartSymbolDoc(Ed, Lib.FileName);
end;

{ ===========================================================================
  TfrmMain.StoreSymbolDoc  (function)
  Parameters:
    Doc: TDocument - the document of a symbol
    out Msg: String - the message (out: set by the call)
  Returns:
    Boolean - True if the symbol was stored
  Notes:
    Store in library: the drawing the view made goes into the symbol, the symbol is checked
    (errors stop it: no name, a repeated name, a pin of a part that is not there, two pins on
    one spot; warnings do not), and it is stored in its library in place of the symbol it came
    from. The library list shows it again and the document has no unsaved changes.
  =========================================================================== }
function TfrmMain.StoreSymbolDoc(Doc: TDocument; out Msg: String): Boolean;
var
  Issues: TSymbolIssues;
  i, Li: Integer;
  Id: Int64;
begin
  Result := False;
  Msg := '';
  if (Doc = nil) or (Doc.Symbol = nil) then
    Exit;
  Doc.Symbol.TakeDesign(Doc.Design);
  Issues := Doc.Symbol.Validate;
  for i := 0 to High(Issues) do
    if Issues[i].Severity = 0 then
    begin
      if Msg <> '' then
        Msg := Msg + LineEnding;
      Msg := Msg + Issues[i].Text;
    end;
  if Msg <> '' then
  begin
    Msg := Format(rsTheSymbolCannotBeStored, [Msg]);
    Exit;
  end;
  try
    Id := Doc.Symbol.Save;
  except
    on E: Exception do
    begin
      Msg := Format(rsCannotStoreTheSymbol, [E.Message]);
      Exit;
    end;
  end;
  for i := 0 to High(Issues) do
  begin
    if Msg <> '' then
      Msg := Msg + '; ';
    Msg := Msg + Issues[i].Text;
  end;
  if Msg <> '' then
    Msg := Format(rsSymbolStoredWarnings, [Msg])
  else
    Msg := rsSymbolStored;
  Doc.Modified := False;
  if Doc.Symbol.Sink is TPartSymbolSink then
  begin
    i := FDocs.IndexOfParts(TPartSymbolSink(Doc.Symbol.Sink).FileName);
    if i >= 0 then
    begin
      FDocs[i].PartsEditor.Lib.Reread;
      FDocs[i].PartsEditor.ReloadAfterSymbolStore(TPartSymbolSink(Doc.Symbol.Sink).PartID);
    end;
    UpdateDocTabs;
    UpdateFormTitle;
    Exit(True);
  end;
  Li := frameLibraryPanel.IndexOfFile(Doc.SymbolLibFile);
  frameLibraryPanel.Reload;
  if Li >= 0 then
    frameLibraryPanel.SelectSymbolId(Li, Id);
  UpdateDocTabs;
  UpdateFormTitle;
  Result := True;
end;

{ ===========================================================================
  TfrmMain.DeleteLibrarySymbol  (function)
  Parameters:
    LibIndex: Integer - which open library
    SetIndex: Integer - which symbol
    out Msg: String - the message (out: set by the call)
  Returns:
    Boolean - True if it was deleted
  Notes:
    Delete symbol: removes the symbol with its names and fields from the library file. A symbol
    that is being edited is not deleted.
  =========================================================================== }
function TfrmMain.DeleteLibrarySymbol(LibIndex, SetIndex: Integer; out Msg: String): Boolean;
var
  Lib: TSymbolLibrary;
  Ed: TSymbolEditor;
begin
  Result := False;
  Msg := '';
  if (LibIndex < 0) or (LibIndex >= frameLibraryPanel.LibCount) then
    Exit;
  Lib := frameLibraryPanel.LibAt(LibIndex);
  if (SetIndex < 0) or (SetIndex >= Lib.SetCount) then
    Exit;
  if SymbolDocIndex(Lib.FileName, Lib.Sets[SetIndex].SymbolID) >= 0 then
  begin
    Msg := rsThisSymbolIsBeingEdited;
    Exit;
  end;
  Ed := TSymbolEditor.Create(Lib);
  try
    try
      Ed.OpenSet(Lib.Sets[SetIndex]);
      Ed.DeleteFromLibrary;
      Result := True;
    except
      on E: Exception do Msg := Format(rsCannotDeleteTheSymbol, [E.Message]);
    end;
  finally
    Ed.Free;
  end;
  frameLibraryPanel.Reload;
end;

{ ===========================================================================
  TfrmMain.ExportLibrarySymbols  (function)
  Parameters:
    LibIndex: Integer - whole number
    SetIndex: Integer - whole number
    const AFileName: String - path of the file
    out Msg: String - the message (out: set by the call)
  Returns:
    Boolean
  Notes:
    File > Export all symbols (CLibraryDoc::OnFileExportlibrary) and the context command Export
    symbol of TinyCAD's library window. The file is the XML library file of TinyCAD (ULibXML).
  =========================================================================== }
function TfrmMain.ExportLibrarySymbols(LibIndex, SetIndex: Integer; const AFileName: String; out Msg: String): Boolean;
var
  Lib: TSymbolLibrary;
  Id: Int64;
  N: Integer;
begin
  Result := False;
  Msg := '';
  if (LibIndex < 0) or (LibIndex >= frameLibraryPanel.LibCount) then
  begin
    Msg := rsThereIsNoSuchLibrary;
    Exit;
  end;
  Lib := frameLibraryPanel.LibAt(LibIndex);
  for N := 0 to frameLibraryPanel.LibCount - 1 do
    if SameFileName(ExpandFileName(AFileName), ExpandFileName(frameLibraryPanel.LibAt(N).FileName)) then
    begin
      Msg := Format(rsCannotExportOverTheLibrary, [ExtractFileName(AFileName)]);
      Exit;
    end;
  Id := -1;
  if SetIndex >= 0 then
  begin
    if SetIndex >= Lib.SetCount then
      Exit;
    Id := Lib.Sets[SetIndex].SymbolID;
  end;
  try
    N := ExportLibraryXML(Lib, AFileName, Id);
    Result := True;
    if N = 1 then
      Msg := Format(rsSymbolWrittenTo, [ExtractFileName(AFileName)])
    else
      Msg := Format(rsSymbolsWrittenTo, [N, ExtractFileName(AFileName)]);
  except
    on E: Exception do Msg := Format(rsCannotExportTheSymbols, [E.Message]);
  end;
end;

{ ===========================================================================
  TfrmMain.ImportLibrarySymbols  (function)
  Parameters:
    LibIndex: Integer - whole number
    const AFileName: String - path of the file
    out Msg: String - the message (out: set by the call)
  Returns:
    Boolean
  Notes:
    File > Import symbols (CLibraryDoc::OnFileImportlibrary). The symbols are added to the
    library (importing a file twice adds them twice, as in TinyCAD). Refused while a symbol of
    the library is being edited: the library is read again afterwards, which the editor's symbol
    could not survive.
  =========================================================================== }
function TfrmMain.ImportLibrarySymbols(LibIndex: Integer; const AFileName: String; out Msg: String): Boolean;
var
  Lib: TSymbolLibrary;
  N: Integer;
begin
  Result := False;
  Msg := '';
  if (LibIndex < 0) or (LibIndex >= frameLibraryPanel.LibCount) then
  begin
    Msg := rsThereIsNoSuchLibrary;
    Exit;
  end;
  Lib := frameLibraryPanel.LibAt(LibIndex);
  if LibraryIsInUse(Lib.FileName) then
  begin
    Msg := rsASymbolOfThisLibrary;
    Exit;
  end;
  N := 0;
  try
    try
      N := ImportLibraryXML(Lib, AFileName);
      Result := True;
      if N = 1 then
        Msg := Format(rsSymbolAddedTo, [LibraryName(Lib.FileName)])
      else
        Msg := Format(rsSymbolsAddedTo, [N, LibraryName(Lib.FileName)]);
    except
      on E: Exception do Msg := Format(rsCannotImportTheSymbols, [E.Message]);
    end;
  finally
    frameLibraryPanel.Reload;      { (symbols stored before a problem stay stored) }
  end;
end;

{ ===========================================================================
  TfrmMain.ExportLibraryDialog  (procedure)
  Parameters:
    ALibIndex: Integer - whole number
    ASetIndex: Integer - whole number
  Notes:
    Asks for the XML file (it starts as the name of the library, or of the symbol, with .xml:
    CFileDialog in TinyCAD) and writes it; the result or the problem is shown in the status bar
    or a message.
  =========================================================================== }
procedure TfrmMain.ExportLibraryDialog(ALibIndex, ASetIndex: Integer);
var
  Msg, Base: String;
  Lib: TSymbolLibrary;
begin
  if (ALibIndex < 0) or (ALibIndex >= frameLibraryPanel.LibCount) then
    Exit;
  Lib := frameLibraryPanel.LibAt(ALibIndex);
  Base := LibraryName(Lib.FileName);
  if (ASetIndex >= 0) and (ASetIndex < Lib.SetCount) and (Lib.Sets[ASetIndex].RecordCount > 0) then
    Base := Lib.Sets[ASetIndex].Records[0].Name;
  SaveDlg.Filter := rsXMLLibraryFileXmlXml;
  SaveDlg.DefaultExt := 'xml';
  SaveDlg.FileName := ExportFileName(Base);
  SaveDlg.Options := SaveDlg.Options + [ofOverwritePrompt];
  if not SaveDlg.Execute then
    Exit;
  if ExportLibrarySymbols(ALibIndex, ASetIndex, SaveDlg.FileName, Msg) then
    sbMainBar.Panels[0].Text := Msg
  else
    ReportProblem(Msg);
end;

{ ===========================================================================
  TfrmMain.ImportLibraryDialog  (procedure)
  Parameters:
    ALibIndex: Integer - whole number
  Notes:
    Asks for the XML file and adds its symbols to the library; the result or the problem is
    shown.
  =========================================================================== }
procedure TfrmMain.ImportLibraryDialog(ALibIndex: Integer);
var
  Msg: String;
begin
  if (ALibIndex < 0) or (ALibIndex >= frameLibraryPanel.LibCount) then
    Exit;
  OpenDlg.Filter := rsXMLLibraryFileXmlXml;
  if not OpenDlg.Execute then
    Exit;
  if ImportLibrarySymbols(ALibIndex, OpenDlg.FileName, Msg) then
    sbMainBar.Panels[0].Text := Msg
  else
    ReportProblem(Msg);
end;

{ ===========================================================================
  TfrmMain.DuplicateLibrarySymbol  (function)
  Parameters:
    LibIndex: Integer - which open library
    SetIndex: Integer - which symbol
    out Msg: String - the message (out: set by the call)
  Returns:
    Boolean - True if it was done
  Notes:
    Duplicate symbol: stores a copy of the symbol in the same library, its names followed by "
    copy" so that the two can be told apart; the copy is selected.
  =========================================================================== }
function TfrmMain.DuplicateLibrarySymbol(LibIndex, SetIndex: Integer; out Msg: String): Boolean;
var
  Lib: TSymbolLibrary;
  Ed: TSymbolEditor;
  i: Integer;
  Id: Int64;
begin
  Result := False;
  Msg := '';
  if (LibIndex < 0) or (LibIndex >= frameLibraryPanel.LibCount) then
    Exit;
  Lib := frameLibraryPanel.LibAt(LibIndex);
  if (SetIndex < 0) or (SetIndex >= Lib.SetCount) then
    Exit;
  Ed := TSymbolEditor.Create(Lib);
  try
    try
      Ed.OpenSet(Lib.Sets[SetIndex]);
      for i := 0 to Ed.LibrarySet.RecordCount - 1 do
        Ed.LibrarySet.Records[i].Name := Format(rsCopy, [Ed.LibrarySet.Records[i].Name]);
      Id := Ed.CopyTo(Lib);
      Result := True;
    except
      on E: Exception do Msg := Format(rsCannotDuplicateTheSymbol, [E.Message]);
    end;
  finally
    Ed.Free;
  end;
  frameLibraryPanel.Reload;
  if Result then
    frameLibraryPanel.SelectSymbolId(LibIndex, Id);
end;

{ ===========================================================================
  TfrmMain.CopyLibrarySymbol  (function)
  Parameters:
    LibIndex: Integer - the library the symbol is in
    SetIndex: Integer - which symbol
    TargetIndex: Integer - the library to copy it to
    out Msg: String - the message (out: set by the call)
  Returns:
    Boolean - True if it was done
  Notes:
    Copy to: stores a copy of the symbol, with its names and fields, in another open library.
  =========================================================================== }
function TfrmMain.CopyLibrarySymbol(LibIndex, SetIndex, TargetIndex: Integer; out Msg: String): Boolean;
var
  Lib: TSymbolLibrary;
  Ed: TSymbolEditor;
begin
  Result := False;
  Msg := '';
  if (LibIndex < 0) or (LibIndex >= frameLibraryPanel.LibCount) or (TargetIndex < 0) or (TargetIndex >= frameLibraryPanel.LibCount) then
    Exit;
  Lib := frameLibraryPanel.LibAt(LibIndex);
  if (SetIndex < 0) or (SetIndex >= Lib.SetCount) then
    Exit;
  Ed := TSymbolEditor.Create(Lib);
  try
    try
      Ed.OpenSet(Lib.Sets[SetIndex]);
      Ed.CopyTo(frameLibraryPanel.LibAt(TargetIndex));
      Result := True;
    except
      on E: Exception do Msg := Format(rsCannotCopyTheSymbol, [E.Message]);
    end;
  finally
    Ed.Free;
  end;
  frameLibraryPanel.Reload;
end;

{ ===========================================================================
  TfrmMain.BeginSymbolProps  (function)
  Parameters:  none
  Returns:
    TfrmSymbolProps - the dialog filled from the symbol being edited, nil when the current
    document is not a symbol; the caller shows it and frees it
  Notes:
    The start of Library > Symbol Properties and of storing a symbol (TinyCAD's Update Library
    dialog).
  =========================================================================== }
function TfrmMain.BeginSymbolProps: TfrmSymbolProps;
begin
  Result := nil;
  if (CurDoc = nil) or (CurDoc.Symbol = nil) then
    Exit;
  Result := TfrmSymbolProps.Create(Self);
  Result.Load(CurDoc.Symbol, LibraryName(CurDoc.SymbolLibFile));
end;

{ ===========================================================================
  TfrmMain.EndSymbolProps  (procedure)
  Parameters:
    F: TfrmSymbolProps - the dialog
    Accept: Boolean - True for OK
  Notes:
    OK puts the edited names, description, attributes and orientation into the symbol, which
    then has unsaved changes. Cancel changes nothing. The caller frees the dialog.
  =========================================================================== }
procedure TfrmMain.EndSymbolProps(F: TfrmSymbolProps; Accept: Boolean);
var
  S: TLibrarySymbolSet;
begin
  if (not Accept) or (CurDoc = nil) or (CurDoc.Symbol = nil) then
    Exit;
  S := F.Edited;
  try
    CurDoc.Symbol.ReplaceSet(S);
  finally
    S.Free;
  end;
  CurDoc.Modified := True;
  UpdateDocTabs;
  UpdateFormTitle;
end;

{ ===========================================================================
  TfrmMain.BeginLibraryProps  (function)
  Parameters:
    LibIndex: Integer - whole number
    SetIndex: Integer - whole number
    out Ed: TSymbolEditor - out: set by the call
  Returns:
    TfrmSymbolProps
  Notes:
    The start of Symbol properties in the library list. No editor tab is made.
  =========================================================================== }
function TfrmMain.BeginLibraryProps(LibIndex, SetIndex: Integer; out Ed: TSymbolEditor): TfrmSymbolProps;
var
  Lib: TSymbolLibrary;
begin
  Result := nil;
  Ed := nil;
  if (LibIndex < 0) or (LibIndex >= frameLibraryPanel.LibCount) then
    Exit;
  Lib := frameLibraryPanel.LibAt(LibIndex);
  if (SetIndex < 0) or (SetIndex >= Lib.SetCount) then
    Exit;
  Ed := TSymbolEditor.Create(Lib);
  try
    Ed.OpenSet(Lib.Sets[SetIndex]);
  except
    FreeAndNil(Ed);
    raise;
  end;
  Result := TfrmSymbolProps.Create(Self);
  Result.Load(Ed, LibraryName(Lib.FileName));
end;

{ ===========================================================================
  TfrmMain.EndLibraryProps  (function)
  Parameters:
    F: TfrmSymbolProps
    Ed: TSymbolEditor
    Accept: Boolean - flag
    out Msg: String - the message (out: set by the call)
  Returns:
    Boolean
  Notes:
    OK puts the dialog's names, description, attributes and orientation into the symbol, checks
    it as Store in Library does and stores it in its library under the same number, then the
    list is read again with the symbol still chosen. The drawing is untouched.
  =========================================================================== }
function TfrmMain.EndLibraryProps(F: TfrmSymbolProps; Ed: TSymbolEditor; Accept: Boolean; out Msg: String): Boolean;
var
  S: TLibrarySymbolSet;
  Issues: TSymbolIssues;
  i, Li: Integer;
  Id: Int64;
begin
  Result := False;
  Msg := '';
  if (not Accept) or (Ed = nil) then
    Exit;
  S := F.Edited;
  try
    Ed.ReplaceSet(S);
  finally
    S.Free;
  end;
  Issues := Ed.Validate;
  for i := 0 to High(Issues) do
    if Issues[i].Severity = 0 then
    begin
      if Msg <> '' then
        Msg := Msg + LineEnding;
      Msg := Msg + Issues[i].Text;
    end;
  if Msg <> '' then
  begin
    Msg := Format(rsTheSymbolCannotBeStored, [Msg]);
    Exit;
  end;
  try
    Id := Ed.Save;
  except
    on E: Exception do
    begin
      Msg := Format(rsCannotStoreTheSymbol, [E.Message]);
      Exit;
    end;
  end;
  for i := 0 to High(Issues) do
  begin
    if Msg <> '' then
      Msg := Msg + '; ';
    Msg := Msg + Issues[i].Text;
  end;
  if Msg <> '' then
    Msg := Format(rsSymbolStoredWarnings, [Msg])
  else
    Msg := rsSymbolStored;
  Li := frameLibraryPanel.IndexOfFile(Ed.StoreLibrary.FileName);
  frameLibraryPanel.Reload;
  if Li >= 0 then
    frameLibraryPanel.SelectSymbolId(Li, Id);
  Result := True;
end;

{ ===========================================================================
  TfrmMain.LibrarySymbolProps  (procedure)
  Parameters:
    LibIndex: Integer - whole number
    SetIndex: Integer - whole number
  Notes:
    Symbol properties on a symbol chosen in the library list: only the dialog is shown, and OK
    stores the change in the library. Problems are shown and the dialog is not asked again. A
    symbol that is already open in an editor tab is a different matter, the tab holds the
    current copy: that tab is brought forward and the dialog changes the tab's symbol (unsaved
    until it is stored), so the library and the tab cannot disagree.
  =========================================================================== }
procedure TfrmMain.LibrarySymbolProps(LibIndex, SetIndex: Integer);
var
  Lib: TSymbolLibrary;
  Ed: TSymbolEditor;
  F: TfrmSymbolProps;
  At: Integer;
  Msg: String;
begin
  if (LibIndex < 0) or (LibIndex >= frameLibraryPanel.LibCount) then
    Exit;
  Lib := frameLibraryPanel.LibAt(LibIndex);
  if (SetIndex < 0) or (SetIndex >= Lib.SetCount) then
    Exit;
  At := SymbolDocIndex(Lib.FileName, Lib.Sets[SetIndex].SymbolID);
  if At >= 0 then
  begin
    ActivateDocument(At);
    DoSymbolProps(nil);
    Exit;
  end;
  try
    F := BeginLibraryProps(LibIndex, SetIndex, Ed);
  except
    on E: Exception do
    begin
      ReportProblem(Format(rsCannotOpenTheSymbol, [E.Message]));
      Exit;
    end;
  end;
  if F = nil then
    Exit;
  try
    if EndLibraryProps(F, Ed, F.ShowModal = mrOK, Msg) then
      sbMainBar.Panels[0].Text := Msg
    else if Msg <> '' then
      ReportProblem(Msg);
  finally
    F.Free;
    Ed.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.BeginSymbolParts  (function)
  Parameters:  none
  Returns:
    TfrmSymbolParts - the dialog filled from the symbol, nil when the current document is not a
    symbol; the caller shows it and frees it
  Notes:
    The start of Library > Parts per Package.
  =========================================================================== }
function TfrmMain.BeginSymbolParts: TfrmSymbolParts;
begin
  Result := nil;
  if (CurDoc = nil) or (CurDoc.Symbol = nil) then
    Exit;
  Result := TfrmSymbolParts.Create(Self);
  Result.Load(CurDoc.Symbol.PartCount, CurDoc.Design.Heterogeneous);
end;

{ ===========================================================================
  TfrmMain.EndSymbolParts  (procedure)
  Parameters:
    F: TfrmSymbolParts - the dialog
    Accept: Boolean - True for OK
  Notes:
    OK sets the number of parts and the kind of symbol. The kind is changed while the symbol has
    one part (before the count when it grows, after it when it shrinks to one). A symbol with a
    drawing for each part gains or loses sheets; a shared drawing loses the pins of the parts
    that are gone. The view starts again on the changed design (its undo history is cleared).
  =========================================================================== }
procedure TfrmMain.EndSymbolParts(F: TfrmSymbolParts; Accept: Boolean);
var
  Ed: TSymbolEditor;
  D: TDesignFile;
  Did: Boolean;
begin
  if (not Accept) or (CurDoc = nil) or (CurDoc.Symbol = nil) then
    Exit;
  Ed := CurDoc.Symbol;
  D := CurDoc.Design;
  Did := False;
  if (F.Hetero <> D.Heterogeneous) and (Ed.PartCount = 1) then
    Did := Ed.ApplyHeterogeneous(D, F.Hetero) or Did;
  if F.Parts <> Ed.PartCount then
  begin
    Ed.ApplyPartCount(D, F.Parts);
    Did := True;
  end;
  if (F.Hetero <> D.Heterogeneous) and (Ed.PartCount = 1) then
    Did := Ed.ApplyHeterogeneous(D, F.Hetero) or Did;
  if (not Did) and (F.Hetero = D.Heterogeneous) then
    Exit;
  CurDoc.Modified := True;
  FView.SetDesign(D, Min(FView.SheetIndex, D.SheetCount - 1));
  RebuildSheetTabs;
  UpdateDocTabs;
  UpdateFormTitle;
  UpdateRibbonState;
end;

{ ===========================================================================
  TfrmMain.SymbolPartText  (function)
  Parameters:  none
  Returns:
    String - for the status bar
  Notes:
    "Part B of 3" for the part being drawn; empty when the symbol is not being edited or has one
    part.
  =========================================================================== }
function TfrmMain.SymbolPartText: String;
var
  P: Integer;
begin
  Result := '';
  if (CurDoc = nil) or (CurDoc.Symbol = nil) or (CurDoc.Symbol.PartCount < 2) then
    Exit;
  if CurDoc.Design.Heterogeneous then
    P := FView.SheetIndex
  else
    P := CurDoc.Design.EditPart;
  Result := Format(rsPartOf, [Chr(Ord('A') + P), CurDoc.Symbol.PartCount]);
end;

{ ===========================================================================
  TfrmMain.ShowSymbolPart  (procedure)
  Parameters:
    Part: Integer - the part, 0-based (kept within the symbol's parts)
  Notes:
    Chooses the part drawn: a symbol with a drawing for each part shows that part's sheet; a
    shared drawing shows only the pins of that part, and new pins belong to it.
  =========================================================================== }
procedure TfrmMain.ShowSymbolPart(Part: Integer);
var
  D: TDesignFile;
begin
  if (CurDoc = nil) or (CurDoc.Symbol = nil) then
    Exit;
  D := CurDoc.Design;
  Part := Max(0, Min(CurDoc.Symbol.PartCount - 1, Part));
  FView.CancelTool;
  if D.Heterogeneous then
  begin
    FView.SetSheetIndex(Part);
    QueueSheetTabRefresh;
    RebuildSheetTabs;
  end
  else
  begin
    D.EditPart := Part;
    D.Sheets[0].Options.EditPart := Part;
    FView.ClearSelection;
    FView.Invalidate;
  end;
  sbMainBar.Panels[0].Text := SymbolPartText;
end;

{ ===========================================================================
  TfrmMain.DoSymbolPart  (procedure)
  Parameters:
    Sender: TObject - the menu item (Tag -1 for the previous part, 1 for the next)
  Notes:
    Library > Previous Part / Next Part.
  =========================================================================== }
procedure TfrmMain.DoSymbolPart(Sender: TObject);
var
  Cur: Integer;
begin
  if (CurDoc = nil) or (CurDoc.Symbol = nil) then
    Exit;
  if CurDoc.Design.Heterogeneous then
    Cur := FView.SheetIndex
  else
    Cur := CurDoc.Design.EditPart;
  ShowSymbolPart(Cur + (Sender as TComponent).Tag);
end;

{ ===========================================================================
  TfrmMain.DoSymbolCommand  (procedure)
  Parameters:
    Sender: TObject - the library panel
    Cmd: TSymbolCommand - the command chosen in its pop-up menu or the Library menu
  Notes:
    New symbol, Edit symbol, Delete symbol (after asking), Duplicate symbol and Symbol
    properties (the symbol is opened for editing and the dialog shown) on the symbol chosen in
    the library list.
  =========================================================================== }
procedure TfrmMain.DoSymbolCommand(Sender: TObject; Cmd: TSymbolCommand);
var
  Li, Si: Integer;
  Msg: String;
begin
  Li := frameLibraryPanel.SelectedLibIndex;
  Si := frameLibraryPanel.SelectedSetIndex;
  case Cmd of
    scNew: NewSymbolDoc(Li);
    scEdit: OpenSymbolDoc(Li, Si);
    scDelete:
      if (Li >= 0) and (Si >= 0) and
         (MessageDlg(lAppName, rsDeleteThisSymbolFromIts, mtConfirmation, [mbYes, mbNo], 0) = mrYes) then
        if not DeleteLibrarySymbol(Li, Si, Msg) then
          ReportProblem(Msg);
    scDuplicate:
      if not DuplicateLibrarySymbol(Li, Si, Msg) then
        ReportProblem(Msg);
    scProperties:
      LibrarySymbolProps(Li, Si);
    scExportSymbol: ExportLibraryDialog(Li, Si);
    scExportLibrary: ExportLibraryDialog(Li, -1);
    scImport: ImportLibraryDialog(Li);
  end;
end;

{ ===========================================================================
  TfrmMain.DoSymbolCopyTo  (procedure)
  Parameters:
    Sender: TObject - the library panel
    TargetIndex: Integer - the library chosen
  Notes:
    Copy to: the symbol chosen in the list is copied to another open library.
  =========================================================================== }
procedure TfrmMain.DoSymbolCopyTo(Sender: TObject; TargetIndex: Integer);
var
  Msg: String;
begin
  if not CopyLibrarySymbol(frameLibraryPanel.SelectedLibIndex, frameLibraryPanel.SelectedSetIndex, TargetIndex, Msg) then
    if Msg <> '' then
      ReportProblem(Msg);
end;

{ ===========================================================================
  TfrmMain.LibraryQueryClose  (procedure)
  Parameters:
    Sender: TObject - the library panel
    const FileName: String - path of the file
    var Allow: Boolean - flag (in/out: changed by the call)
  Notes:
    A library cannot be closed while one of its symbols is being edited.
  =========================================================================== }
procedure TfrmMain.LibraryQueryClose(Sender: TObject; const FileName: String; var Allow: Boolean);
begin
  if LibraryIsInUse(FileName) then
  begin
    Allow := False;
    ReportProblem(rsASymbolOfThisLibrary);
  end;
end;

{ ===========================================================================
  TfrmMain.DoSymbolMenuCommand  (procedure)
  Parameters:
    Sender: TObject - the Library menu item (its Tag is the TSymbolCommand)
  Notes:
    The symbol commands of the Library menu act on the symbol chosen in the library list, as the
    list's pop-up menu does.
  =========================================================================== }
procedure TfrmMain.DoSymbolMenuCommand(Sender: TObject);
begin
  frameLibraryPanel.Command(TSymbolCommand((Sender as TComponent).Tag));
end;

{ ===========================================================================
  TfrmMain.DoStoreSymbol  (procedure)
  Parameters:
    Sender: TObject - the menu item or Save
  Notes:
    Store in library (and File > Save of a symbol): the Update Library dialog is shown first
    (names, description, attributes); OK stores the symbol. Problems are shown.
  =========================================================================== }
procedure TfrmMain.DoStoreSymbol(Sender: TObject);
var
  F: TfrmSymbolProps;
  Msg: String;
begin
  if (CurDoc = nil) or (CurDoc.Symbol = nil) then
    Exit;
  F := BeginSymbolProps;
  try
    if F.ShowModal <> mrOK then
      Exit;
    EndSymbolProps(F, True);
  finally
    F.Free;
  end;
  if StoreSymbolDoc(CurDoc, Msg) then
    sbMainBar.Panels[0].Text := Msg
  else
    ReportProblem(Msg);
end;

{ ===========================================================================
  TfrmMain.DoSymbolProps  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Library > Symbol Properties...: shows the dialog for the symbol being edited.
  =========================================================================== }
procedure TfrmMain.DoSymbolProps(Sender: TObject);
var
  F: TfrmSymbolProps;
begin
  F := BeginSymbolProps;
  if F = nil then
    Exit;
  try
    EndSymbolProps(F, F.ShowModal = mrOK);
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.DoSymbolParts  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Library > Parts per Package...: shows the dialog for the symbol being edited.
  =========================================================================== }
procedure TfrmMain.DoSymbolParts(Sender: TObject);
var
  F: TfrmSymbolParts;
begin
  F := BeginSymbolParts;
  if F = nil then
    Exit;
  try
    EndSymbolParts(F, F.ShowModal = mrOK);
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.BuildSymbolMenu  (procedure)
  Parameters:  none
  Notes:
    The symbol editor's commands of the Symbols menu (the symbol commands of the library list,
    the Pin and Origin tools, and for the symbol being edited its properties, parts and Store in
    library) are made in the form file; this ties the Pin and Origin items to their tools.
  =========================================================================== }
procedure TfrmMain.BuildSymbolMenu;
begin
  { the items themselves are in the form file (mSymbol); only the tool items are tied to their tools }
  FToolMenus[vtPin] := miSymPin;
  FToolMenus[vtOrigin] := miSymOrigin;
end;

{ ===========================================================================
  TfrmMain.DoOpenPartsLibrary  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Open Parts Library...: the same as the Open button of the Parts tab (asks for a file and opens it; a file that cannot be used is explained).
  =========================================================================== }
procedure TfrmMain.DoOpenPartsLibrary(Sender: TObject);
begin
  frameLibraryPanel.PartsOpenClick(Sender);
end;

{ ===========================================================================
  TfrmMain.DoNewPartsLibrary  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > New Parts Library...: asks where to save an empty parts library, makes it and shows it in the Parts tab.
  =========================================================================== }
procedure TfrmMain.DoNewPartsLibrary(Sender: TObject);
begin
  if frameLibraryPanel.NewPartsLibrary and (OpenPartsEditor(frameLibraryPanel.PartsFileName) = nil) then
    MessageDlg(rsPartsLibrary, FPartsEditorError, mtError, [mbOK], 0);
end;

{ ===========================================================================
  TfrmMain.DoEditPartsLibrary  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Edit Parts Library...: opens the editor tab for the library shown in the Parts tab; with none open it asks for a file first.
  =========================================================================== }
procedure TfrmMain.DoEditPartsLibrary(Sender: TObject);
begin
  if frameLibraryPanel.PartsFileName = '' then
    frameLibraryPanel.PartsOpenClick(Sender);
  if frameLibraryPanel.PartsFileName = '' then
    Exit;
  if OpenPartsEditor(frameLibraryPanel.PartsFileName) = nil then
    MessageDlg(rsPartsLibrary, FPartsEditorError, mtError, [mbOK], 0);
end;

{ ===========================================================================
  TfrmMain.DoPartAdd  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Add Part...: the editor tab's Add Part command.
  =========================================================================== }
procedure TfrmMain.DoPartAdd(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdAdd;
end;

{ ===========================================================================
  TfrmMain.DoPartProperties  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Part Properties...: the editor tab's Properties command for the chosen part.
  =========================================================================== }
procedure TfrmMain.DoPartProperties(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdProperties;
end;

{ ===========================================================================
  TfrmMain.DoPartDuplicate  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Duplicate Part: the editor tab's Duplicate command for the chosen part.
  =========================================================================== }
procedure TfrmMain.DoPartDuplicate(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdDuplicate;
end;

{ ===========================================================================
  TfrmMain.DoPartDelete  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Delete Part: the editor tab's Delete command for the chosen part.
  =========================================================================== }
procedure TfrmMain.DoPartDelete(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdDelete;
end;

{ ===========================================================================
  TfrmMain.PartsMenuOpen  (procedure)
  Parameters:
    Sender: TObject - the Parts menu
  Notes:
    The Parts menu is opening: the editing commands are available while a parts library editor tab is shown (Properties, Duplicate and Delete also need a chosen
    part); Edit Parts Library... is always available.
  =========================================================================== }
procedure TfrmMain.PartsMenuOpen(Sender: TObject);
var
  Ed: TfrPartsEditor;
  OnParts, OnClasses, OnRatings, OnObjects, OnProducts, OnValues, OnSymbols: Boolean;
begin
  Ed := PartsEditorOfCurrent;
  OnParts := (Ed <> nil) and (Ed.PageName = 'parts');
  OnClasses := (Ed <> nil) and (Ed.PageName = 'classes');
  mPartsAdd.Enabled := OnParts;
  mPartsProps.Enabled := OnParts and Ed.CanChangeSelected;
  mPartsDup.Enabled := mPartsProps.Enabled;
  mPartsDel.Enabled := mPartsProps.Enabled;
  mPartsClassAdd.Enabled := OnClasses;
  mPartsClassProps.Enabled := OnClasses and (Ed.SelectedClassID <> 0);
  mPartsClassDel.Enabled := mPartsClassProps.Enabled;
  mPartsFieldAdd.Enabled := mPartsClassProps.Enabled;
  mPartsFieldProps.Enabled := OnClasses and Ed.SelectedFieldIsOwn;
  mPartsFieldDel.Enabled := mPartsFieldProps.Enabled;
  OnObjects := (Ed <> nil) and (Ed.PageName = 'objects');
  mPartsObjAdd.Enabled := OnObjects and (Ed.CurrentObjPartID <> 0);
  mPartsObjProps.Enabled := OnObjects and (Ed.SelectedObjectID <> 0);
  mPartsObjDel.Enabled := mPartsObjProps.Enabled;
  OnValues := (Ed <> nil) and (Ed.PageName = 'values');
  mPartsValSet.Enabled := OnValues and (Ed.SelectedValueRow >= 0);
  mPartsValClear.Enabled := OnValues and Ed.btnValClear.Enabled;
  OnProducts := (Ed <> nil) and (Ed.PageName = 'products');
  mPartsProdAdd.Enabled := OnProducts;
  mPartsProdProps.Enabled := OnProducts and (Ed.SelectedProductID <> 0);
  mPartsProdDel.Enabled := mPartsProdProps.Enabled;
  mPartsProdSuggest.Enabled := OnProducts and Ed.btnProdSuggest.Enabled;
  mPartsProdPrefer.Enabled := mPartsProdSuggest.Enabled;
  mPartsProdRatAdd.Enabled := mPartsProdProps.Enabled;
  mPartsProdRatProps.Enabled := OnProducts and (Ed.SelectedProdRatingID <> 0);
  mPartsProdRatDel.Enabled := mPartsProdRatProps.Enabled;
  mPartsProdImport.Enabled := OnProducts;
  mPartsProdExport.Enabled := OnProducts;
  OnSymbols := (Ed <> nil) and (Ed.PageName = 'symbols');
  mPartsSymNew.Enabled := OnSymbols and Ed.btnSymNew.Enabled;
  mPartsSymEdit.Enabled := OnSymbols and Ed.btnSymEdit.Enabled;
  mPartsSymImport.Enabled := OnSymbols and Ed.btnSymImport.Enabled;
  mPartsSymProps.Enabled := OnSymbols and Ed.btnSymProps.Enabled;
  mPartsSymDefault.Enabled := OnSymbols and Ed.btnSymDefault.Enabled;
  mPartsSymDel.Enabled := OnSymbols and Ed.btnSymDelete.Enabled;
  OnRatings := (Ed <> nil) and (Ed.PageName = 'requirements');
  mPartsRatAdd.Enabled := OnRatings and (Ed.CurrentRatPartID <> 0);
  mPartsRatProps.Enabled := OnRatings and (Ed.SelectedRatingID <> 0);
  mPartsRatDel.Enabled := mPartsRatProps.Enabled;
end;

{ ===========================================================================
  TfrmMain.DoClassAdd  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts menu: the editor tab's CmdAddClass command (the Classes page).
  =========================================================================== }
procedure TfrmMain.DoClassAdd(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdAddClass;
end;

{ ===========================================================================
  TfrmMain.DoClassProperties  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts menu: the editor tab's CmdClassProperties command (the Classes page).
  =========================================================================== }
procedure TfrmMain.DoClassProperties(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdClassProperties;
end;

{ ===========================================================================
  TfrmMain.DoClassDelete  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts menu: the editor tab's CmdDeleteClass command (the Classes page).
  =========================================================================== }
procedure TfrmMain.DoClassDelete(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdDeleteClass;
end;

{ ===========================================================================
  TfrmMain.DoFieldAdd  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts menu: the editor tab's CmdAddField command (the Classes page).
  =========================================================================== }
procedure TfrmMain.DoFieldAdd(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdAddField;
end;

{ ===========================================================================
  TfrmMain.DoFieldProperties  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts menu: the editor tab's CmdFieldProperties command (the Classes page).
  =========================================================================== }
procedure TfrmMain.DoFieldProperties(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdFieldProperties;
end;

{ ===========================================================================
  TfrmMain.DoFieldDelete  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts menu: the editor tab's CmdDeleteField command (the Classes page).
  =========================================================================== }
procedure TfrmMain.DoFieldDelete(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdDeleteField;
end;

{ ===========================================================================
  TfrmMain.DoObjectAdd  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Add Object...: the editor tab's CmdAddObject command (the Objects page).
  =========================================================================== }
procedure TfrmMain.DoObjectAdd(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdAddObject;
end;

{ ===========================================================================
  TfrmMain.DoObjectProperties  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Object Properties...: the editor tab's CmdObjectProperties command (the Objects page).
  =========================================================================== }
procedure TfrmMain.DoObjectProperties(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdObjectProperties;
end;

{ ===========================================================================
  TfrmMain.DoObjectDelete  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Delete Object: the editor tab's CmdDeleteObject command (the Objects page).
  =========================================================================== }
procedure TfrmMain.DoObjectDelete(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdDeleteObject;
end;

{ ===========================================================================
  TfrmMain.DoProductAdd  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Add Product...: the editor tab's CmdAddProduct command (the Products page).
  =========================================================================== }
procedure TfrmMain.DoProductAdd(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdAddProduct;
end;

{ ===========================================================================
  TfrmMain.DoProductProps  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Product Properties...: the editor tab's CmdProductProperties command (the Products page).
  =========================================================================== }
procedure TfrmMain.DoProductProps(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdProductProperties;
end;

{ ===========================================================================
  TfrmMain.DoProductDel  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Delete Product: the editor tab's CmdDeleteProduct command (the Products page).
  =========================================================================== }
procedure TfrmMain.DoProductDel(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdDeleteProduct;
end;

{ ===========================================================================
  TfrmMain.DoProductSuggest  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Suggest Product for Part: the editor tab's CmdSuggestProduct command (the Products page).
  =========================================================================== }
procedure TfrmMain.DoProductSuggest(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdSuggestProduct;
end;

{ ===========================================================================
  TfrmMain.DoProductPrefer  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Make Product Preferred: the editor tab's CmdPreferProduct command (the Products page).
  =========================================================================== }
procedure TfrmMain.DoProductPrefer(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdPreferProduct;
end;

{ ===========================================================================
  TfrmMain.DoProductRatAdd  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Add Product Rating...: the editor tab's CmdAddProdRating command (the Products page).
  =========================================================================== }
procedure TfrmMain.DoProductRatAdd(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdAddProdRating;
end;

{ ===========================================================================
  TfrmMain.DoProductRatProps  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Product Rating Properties...: the editor tab's CmdProdRatingProperties command (the Products page).
  =========================================================================== }
procedure TfrmMain.DoProductRatProps(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdProdRatingProperties;
end;

{ ===========================================================================
  TfrmMain.DoProductRatDel  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Delete Product Rating: the editor tab's CmdDeleteProdRating command (the Products page).
  =========================================================================== }
procedure TfrmMain.DoProductRatDel(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdDeleteProdRating;
end;

{ ===========================================================================
  TfrmMain.DoValueSet  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Set Field Value...: the editor tab's CmdEditValue command (the Values page).
  =========================================================================== }
procedure TfrmMain.DoValueSet(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdEditValue;
end;

{ ===========================================================================
  TfrmMain.DoValueClear  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Clear Field Value: the editor tab's CmdClearValue command (the Values page).
  =========================================================================== }
procedure TfrmMain.DoValueClear(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdClearValue;
end;

{ ===========================================================================
  TPartSymbolSink.SaveBlob  (function)
  Parameters:
    const Blob: String - the drawing (symbol XML)
    Ed: TSymbolEditor - the editor storing it
  Returns:
    Int64 - the SymbolID in the parts file
  Notes:
    The symbol editor's Store for a part symbol: a symbol that is not stored yet (SourceID -1) is added to the part with the chosen standard, purpose and name, an
    existing one gets its drawing replaced. Works through a connection of its own, so it does not matter whether the editor tab is still open. Raises EPartsError.
  =========================================================================== }
function TPartSymbolSink.SaveBlob(const Blob: String; Ed: TSymbolEditor): Int64;
var
  Lib: TPartsLibrary;
begin
  Lib := TPartsLibrary.Create;
  try
    Lib.Open(FileName);
    if Ed.SourceID = -1 then
      Result := Lib.AddSymbol(PartID, Standard, Purpose, SymName, Blob)
    else
    begin
      Lib.UpdateSymbolDrawing(Ed.SourceID, Blob);
      Result := Ed.SourceID;
    end;
  finally
    Lib.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.StartPartSymbol  (function)
  Parameters:
    Ed: TfrPartsEditor - the parts library editor
    PartID, SymbolID: Int64 - the part and the symbol to edit; SymbolID 0 starts a new symbol
    const AStandard, APurpose, AName: String - properties of a new symbol
  Returns:
    TDocument - the symbol document, nil when the symbol cannot be edited
  Notes:
    Parts > New / Edit Part Symbol: the symbol is opened for drawing as a document of its own (a symbol being edited already is just shown); Store in library writes it back
    into the parts file. A new symbol is added to the part only when it is stored.
  =========================================================================== }
function TfrmMain.StartPartSymbol(Ed: TfrPartsEditor; PartID, SymbolID: Int64; const AStandard, APurpose, AName: String): TDocument;
var
  i, Pi: Integer;
  Sym: TSymbolEditor;
  Sink: TPartSymbolSink;
  Blob, Nm, Ref, Desc: String;
  Rows: TSymbolRowArray;
begin
  Result := nil;
  Pi := Ed.Lib.PartIndexOfID(PartID);
  if Pi < 0 then
    Exit;
  if SymbolID <> 0 then
    for i := 0 to FDocs.Count - 1 do
      if (FDocs[i].Symbol <> nil) and (FDocs[i].Symbol.Sink is TPartSymbolSink) and (FDocs[i].Symbol.SourceID = SymbolID) and
         SameFileName(TPartSymbolSink(FDocs[i].Symbol.Sink).FileName, Ed.Lib.FileName) then
      begin
        ActivateDocument(i);
        Exit(FDocs[i]);
      end;
  Sink := TPartSymbolSink.Create;
  Sink.FileName := Ed.Lib.FileName;
  Sink.PartID := PartID;
  Sink.Standard := AStandard;
  Sink.Purpose := APurpose;
  Sink.SymName := AName;
  Blob := '';
  Nm := AName;
  if SymbolID <> 0 then
  begin
    Rows := Ed.Lib.SymbolRows(PartID);
    for i := 0 to High(Rows) do
      if Rows[i].ID = SymbolID then
      begin
        Sink.Standard := Rows[i].Standard;
        Sink.Purpose := Rows[i].Purpose;
        Nm := Rows[i].Name;
      end;
    Blob := Ed.Lib.SymbolDrawing(SymbolID);
  end;
  if Nm = '' then
    Nm := Ed.Lib.Parts[Pi].Name;
  Ref := Ed.Lib.Parts[Pi].RefPrefix;
  Desc := Ed.Lib.Parts[Pi].Description;
  Sym := TSymbolEditor.Create(nil);
  try
    Sym.OpenBlob(Blob, Nm, Ref, Desc, IfThen(SymbolID = 0, Int64(-1), SymbolID));
  except
    Sym.Free;
    Sink.Free;
    raise;
  end;
  Sym.Sink := Sink;
  Sym.OnSaveBlob := @Sink.SaveBlob;
  Result := StartSymbolDoc(Sym, 'parts:' + Ed.Lib.FileName);
end;

{ ===========================================================================
  TfrmMain.ImportPanelSymbol  (function)
  Parameters:
    Ed: TfrPartsEditor - the parts library editor
    PartID: Int64 - the part
    const AStandard, APurpose, AName: String - the new symbol's properties (empty name takes the library symbol's)
    out Msg: String - why nothing was imported
  Returns:
    Boolean - True when the symbol was added to the part
  Notes:
    Parts > Import Symbol from Library Panel: the drawing of the symbol chosen in the library panel (any open symbol library) becomes a new symbol of the part. The drawing
    is read by the symbol loader first, so a damaged one is refused.
  =========================================================================== }
function TfrmMain.ImportPanelSymbol(Ed: TfrPartsEditor; PartID: Int64; const AStandard, APurpose, AName: String; out Msg: String): Boolean;
var
  Li, Si: Integer;
  Lib: TSymbolLibrary;
  Blob, Nm: String;
  Doc: TSymbolDocument;
  NewID: Int64;
begin
  Result := False;
  Msg := '';
  Li := frameLibraryPanel.SelectedLibIndex;
  Si := frameLibraryPanel.SelectedSetIndex;
  if (Li < 0) or (Li >= frameLibraryPanel.LibCount) then
  begin
    Msg := rsChooseASymbolInThe;
    Exit;
  end;
  Lib := frameLibraryPanel.LibAt(Li);
  if (Si < 0) or (Si >= Lib.SetCount) then
  begin
    Msg := rsChooseASymbolInThe;
    Exit;
  end;
  Blob := Lib.GetSymbolBlob(Lib.Sets[Si]);
  Doc := TSymbolDocument.Create;
  try
    try
      Doc.LoadFromBlob(Blob);
    except
      on E: Exception do
      begin
        Msg := Format(rsTheChosenSymbolCannotBe, [E.Message]);
        Exit;
      end;
    end;
  finally
    Doc.Free;
  end;
  Nm := AName;
  if (Nm = '') and (Lib.Sets[Si].RecordCount > 0) then
    Nm := Lib.Sets[Si].Records[0].Name;
  Result := Ed.AddSymbolDrawing(PartID, AStandard, APurpose, Nm, Blob, NewID);
  if not Result then
    Msg := Ed.LastError;
end;

{ ===========================================================================
  TfrmMain.PartSymbolEdit  (procedure)
  Parameters:
    Sender: TObject - the parts library editor
    PartID, SymbolID: Int64 - the part and symbol; 0 for a new symbol
  Notes:
    The Symbols page's New and Edit: a new symbol asks for its standard, purpose and name first.
  =========================================================================== }
procedure TfrmMain.PartSymbolEdit(Sender: TObject; PartID, SymbolID: Int64);
var
  Ed: TfrPartsEditor;
  Dlg: TfrmSymbolInfo;
  Pi: Integer;
begin
  Ed := Sender as TfrPartsEditor;
  if SymbolID <> 0 then
  begin
    StartPartSymbol(Ed, PartID, SymbolID, '', '', '');
    Exit;
  end;
  Pi := Ed.Lib.PartIndexOfID(PartID);
  if Pi < 0 then
    Exit;
  Dlg := TfrmSymbolInfo.Create(Self);
  try
    Dlg.Setup('IEC', 'schematic', Ed.Lib.Parts[Pi].Name);
    if Dlg.ShowModal = mrOK then
      StartPartSymbol(Ed, PartID, 0, Dlg.Standard, Dlg.Purpose, Dlg.SymName);
  finally
    Dlg.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.PartSymbolImport  (procedure)
  Parameters:
    Sender: TObject - the parts library editor
    PartID, SymbolID: Int64 - the part (the symbol is unused)
  Notes:
    The Symbols page's Import: asks for the standard, purpose and name, then takes the symbol chosen in the library panel; a refusal is explained.
  =========================================================================== }
procedure TfrmMain.PartSymbolImport(Sender: TObject; PartID, SymbolID: Int64);
var
  Ed: TfrPartsEditor;
  Dlg: TfrmSymbolInfo;
  Msg: String;
begin
  Ed := Sender as TfrPartsEditor;
  Dlg := TfrmSymbolInfo.Create(Self);
  try
    Dlg.Setup('IEC', 'schematic', '');
    Dlg.Caption := rsImportSymbol;
    while Dlg.ShowModal = mrOK do
    begin
      if ImportPanelSymbol(Ed, PartID, Dlg.Standard, Dlg.Purpose, Dlg.SymName, Msg) then
        Break;
      MessageDlg(rsPartsLibrary, Msg, mtError, [mbOK], 0);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrmMain.DoProductImport(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdImportProducts;
end;

procedure TfrmMain.DoProductExport(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdExportProducts;
end;

procedure TfrmMain.DoPartSymNew(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdSymNew;
end;

procedure TfrmMain.DoPartSymEdit(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdSymEdit;
end;

procedure TfrmMain.DoPartSymImport(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdSymImport;
end;

procedure TfrmMain.DoPartSymProps(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdSymProps;
end;

procedure TfrmMain.DoPartSymDefault(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdSymDefault;
end;

procedure TfrmMain.DoPartSymDelete(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdSymDelete;
end;

{ ===========================================================================
  TfrmMain.DoRatingAdd  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Add Requirement...: the editor tab's CmdAddRating command (the Requirements page).
  =========================================================================== }
procedure TfrmMain.DoRatingAdd(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdAddRating;
end;

{ ===========================================================================
  TfrmMain.DoRatingProperties  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Requirement Properties...: the editor tab's CmdRatingProperties command (the Requirements page).
  =========================================================================== }
procedure TfrmMain.DoRatingProperties(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdRatingProperties;
end;

{ ===========================================================================
  TfrmMain.DoRatingDelete  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Parts > Delete Requirement: the editor tab's CmdDeleteRating command (the Requirements page).
  =========================================================================== }
procedure TfrmMain.DoRatingDelete(Sender: TObject);
begin
  if PartsEditorOfCurrent <> nil then
    PartsEditorOfCurrent.CmdDeleteRating;
end;

{ ===========================================================================
  TfrmMain.LibraryMenuOpen  (procedure)
  Parameters:
    Sender: TObject - the Library menu
  Notes:
    The Library menu is opening: its symbol commands are brought up to date.
  =========================================================================== }
procedure TfrmMain.LibraryMenuOpen(Sender: TObject);
begin
  UpdateSymbolMenu;
end;

{ ===========================================================================
  TfrmMain.UpdateSymbolMenu  (procedure)
  Parameters:  none
  Notes:
    Enables the symbol commands that can be used now: the library list's commands as the list's
    pop-up menu does, the others only while a symbol is the current document.
  =========================================================================== }
procedure TfrmMain.UpdateSymbolMenu;
var
  Sym: Boolean;
begin
  if miSymNew = nil then
    Exit;
  Sym := (CurDoc <> nil) and (CurDoc.Symbol <> nil);
  miSymNew.Enabled := frameLibraryPanel.CommandEnabled(scNew);
  miSymEdit.Enabled := frameLibraryPanel.CommandEnabled(scEdit);
  miSymDuplicate.Enabled := frameLibraryPanel.CommandEnabled(scDuplicate);
  miSymDelete.Enabled := frameLibraryPanel.CommandEnabled(scDelete);
  miSymCommandProps.Enabled := frameLibraryPanel.CommandEnabled(scProperties);
  miSymExport.Enabled := frameLibraryPanel.CommandEnabled(scExportSymbol);
  miSymExportLib.Enabled := frameLibraryPanel.CommandEnabled(scExportLibrary);
  miSymImport.Enabled := frameLibraryPanel.CommandEnabled(scImport);
  miSymPin.Enabled := Sym or ((FView <> nil) and (FView.Sheet <> nil) and FView.Sheet.IsHierarchicalSymbol);
  miDrawPin.Visible := miSymPin.Enabled;      { (the Draw tab's Pin button is there only where a pin can be placed) }
  miSymOrigin.Enabled := Sym;
  miSymProps.Enabled := Sym;
  miSymParts.Enabled := Sym;
  miSymStore.Enabled := Sym;
  miSymPrevPart.Enabled := Sym and (CurDoc.Symbol.PartCount > 1);
  miSymNextPart.Enabled := miSymPrevPart.Enabled;
end;

{ ===========================================================================
  TfrmMain.DoOpenLibrary  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Menu handler: lets the user pick a .TCLib library and opens it in the library panel.
  =========================================================================== }
procedure TfrmMain.DoOpenLibrary(Sender: TObject);
var
  i: Integer;
begin
  OpenDlg.Filter := rsSymbolLibrariesTCLibTCLibTclib;
  OpenDlg.Options := OpenDlg.Options + [ofAllowMultiSelect];      // several libraries can be opened at once
  try
    if OpenDlg.Execute then
      for i := 0 to OpenDlg.Files.Count - 1 do
        OpenLibraryFile(OpenDlg.Files[i]);
  except
    on E: Exception do
      MessageDlg(lAppName, Format(rsCannotOpenTheLibrary, [E.Message]), mtError, [mbOK], 0);
  end;
  OpenDlg.Options := OpenDlg.Options - [ofAllowMultiSelect];
end;

{ ===========================================================================
  TfrmMain.DoFileExit  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Menu handler: closes the window (asking about unsaved changes).
  =========================================================================== }
procedure TfrmMain.DoFileExit(Sender: TObject);
begin
  Close;
end;

{ ===========================================================================
  TfrmMain.DoDelete  (procedure)
  Parameters:
    Sender: TObject - the menu item or button
  Notes:
    Menu handler: deletes the selected objects.
  =========================================================================== }
procedure TfrmMain.DoDelete(Sender: TObject);
begin
  { Del pressed in the editor of a window dropped from the Properties panel (the parameter list): the menu's shortcut got the key, not the editor, so the text is edited here
    (the symbol is not deleted) }
  if (Screen.ActiveCustomForm <> nil) and (Screen.ActiveCustomForm <> Self) and (Screen.ActiveCustomForm.ActiveControl is TCustomEdit) then
  begin
    EditDeleteForward(Screen.ActiveCustomForm.ActiveControl);
    Exit;
  end;
  { Del pressed in a text box: the menu's shortcut gets the key before the box does, so the box's editing is done here }
  if FDelKeyInEdit and (ActiveControl <> nil) then
  begin
    FDelKeyInEdit := False;
    if (ActiveControl is TEdit) and (TEdit(ActiveControl).Text = '') and (TEdit(ActiveControl).Tag >= 0) and (TEdit(ActiveControl).Tag <= High(FProps)) and
       (FProps[TEdit(ActiveControl).Tag].Def.Name = 'text') then
    begin
      { the empty text box of a selected text, label or power symbol: Del deletes the object }
      if (FView <> nil) and (FView.SelectedCount = 1) then
        FView.DeleteSelection;
    end
    else
      EditDeleteForward(ActiveControl);
    Exit;
  end;
  FView.DeleteSelection;
end;

{ ===========================================================================
  TfrmMain.EditDeleteForward  (function)
  Parameters:
    AControl: TWinControl
  Returns:
    Boolean
  Notes:
    What Del does in a text box: removes the selected text, or the character to the right of the
    caret (Backspace removes the one to the left; that key is not a shortcut, so the box does it
    itself). Counts characters, not bytes, so accented letters and the like go whole. A box that
    cannot be typed in (read only, or a list-only combo box) is left alone.
  =========================================================================== }
function TfrmMain.EditDeleteForward(AControl: TWinControl): Boolean;
begin
  Result := True;
  if AControl is TCustomEdit then
    with TCustomEdit(AControl) do
    begin
      if ReadOnly then
        Exit;
      if SelLength > 0 then
        SelText := ''
      else if SelStart < UTF8Length(Text) then
      begin
        SelLength := 1;
        SelText := '';
      end;
    end
  else if AControl is TCustomMemo then
    with TCustomMemo(AControl) do
    begin
      if ReadOnly then
        Exit;
      if SelLength > 0 then
        SelText := ''
      else if SelStart < UTF8Length(Text) then
      begin
        SelLength := 1;
        SelText := '';
      end;
    end
  else if (AControl is TCustomComboBox) and (TCustomComboBox(AControl).Style in [csDropDown, csSimple, csOwnerDrawFixed, csOwnerDrawVariable]) and
          (TCustomComboBox(AControl).Style <> csDropDownList) then
    with TCustomComboBox(AControl) do
    begin
      if SelLength > 0 then
        SelText := ''
      else if SelStart < UTF8Length(Text) then
      begin
        SelLength := 1;
        SelText := '';
      end;
    end
  else
    Result := False;
end;

{ ===========================================================================
  TfrmMain.FormKeyUp  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    var Key: Word - key code (in/out: changed by the call)
    Shift: TShiftState - modifier keys held down
  Notes:
    Ends the "Del pressed in a text box" mark set by FormKeyDown, so a Del that no menu took
    cannot affect a later Delete command.
  =========================================================================== }
procedure TfrmMain.FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_DELETE then
    FDelKeyInEdit := False;
  FEditKey := #0;
end;

{ ===========================================================================
  TfrmMain.EditShortcutInBox  (function)
  Parameters:
    ACmd: Char - the command letter: C copy, X cut, V paste, A select all, Z undo, Y redo
  Returns:
    Boolean - True when the key was Ctrl+ACmd in a text box and the box has done it
  Notes:
    The Edit menu's shortcuts get Ctrl+C, X, V, A, Z and Y before a text box does, so the
    command handlers call this first: when the key came from a text box, the text is edited
    (clipboard text goes in and out of the box) and the drawing is left alone. A read only box
    only copies and selects.
  =========================================================================== }
function TfrmMain.EditShortcutInBox(ACmd: Char): Boolean;
var
  Ctl: TWinControl;
begin
  Ctl := nil;
  { a window dropped from the Properties panel (the parameter list) is active, with a text box in it: the shortcut is for that box }
  if (Screen.ActiveCustomForm <> nil) and (Screen.ActiveCustomForm <> Self) and (Screen.ActiveCustomForm.ActiveControl is TCustomEdit) then
    Ctl := Screen.ActiveCustomForm.ActiveControl
  else if (FEditKey = ACmd) and (ActiveControl <> nil) then
    Ctl := ActiveControl;
  Result := Ctl <> nil;
  if not Result then
    Exit;
  FEditKey := #0;
  if Ctl is TCustomEdit then
    with TCustomEdit(Ctl) do
      case ACmd of
        'C': CopyToClipboard;
        'X': if not ReadOnly then
               CutToClipboard;
        'V': if not ReadOnly then
               PasteFromClipboard;
        'A': SelectAll;
        'Z', 'Y': if not ReadOnly then
                    Undo;
      end
  else if Ctl is TCustomMemo then
    with TCustomMemo(Ctl) do
      case ACmd of
        'C': CopyToClipboard;
        'X': if not ReadOnly then
               CutToClipboard;
        'V': if not ReadOnly then
               PasteFromClipboard;
        'A': SelectAll;
        'Z', 'Y': if not ReadOnly then
                    Undo;
      end
  else
    Result := False;
end;

{ ===========================================================================
  TfrmMain.DoSelectAll  (procedure)
  Parameters:
    Sender: TObject - the menu item or button
  Notes:
    Menu handler: selects everything on the sheet.
  =========================================================================== }
procedure TfrmMain.DoSelectAll(Sender: TObject);
begin
  if EditShortcutInBox('A') then
    Exit;
  FView.SelectAll;
end;

{ ===========================================================================
  TfrmMain.ColorButtonClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    OnClick of the color buttons of the property panels, which runs just before the button shows
    its color dialog: on Windows the dialog is then put at the left edge of the button with its
    top at the button's bottom (osver.BeginColorDlgPlacement). Elsewhere nothing is done. Color
    dialogs that come from a menu are not touched.
  =========================================================================== }
procedure TfrmMain.ColorButtonClick(Sender: TObject);
{$IFDEF WINDOWS}
var
  B: TControl;
  P: TPoint;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  B := Sender as TControl;
  P := B.ClientToScreen(Point(0, 0));
  BeginColorDlgPlacement(Rect(P.X, P.Y, P.X + B.Width, P.Y + B.Height), Handle);
  {$ENDIF}
end;

{ ===========================================================================
  TfrmMain.DoSelectAllAlike  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Menu handler (the sheet's pop-up menu): selects every object of the same kind as the
    selected ones (what the right click chose), instead of everything on the sheet.
  =========================================================================== }
procedure TfrmMain.DoSelectAllAlike(Sender: TObject);
begin
  FView.SelectAllAlike;
end;

{ ===========================================================================
  TfrmMain.DoUndo  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler: undoes the last action.
  =========================================================================== }
procedure TfrmMain.DoUndo(Sender: TObject);
begin
  if EditShortcutInBox('Z') then
    Exit;
  FView.DoUndo;
end;

{ ===========================================================================
  TfrmMain.DoRedo  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler: redoes the last undone action.
  =========================================================================== }
procedure TfrmMain.DoRedo(Sender: TObject);
begin
  if EditShortcutInBox('Y') then
    Exit;
  FView.DoRedo;
end;

{ ===========================================================================
  TfrmMain.DoCut  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler: copies the selection to the clipboard and deletes it.
  =========================================================================== }
procedure TfrmMain.DoCut(Sender: TObject);
begin
  if EditShortcutInBox('X') then
    Exit;
  FView.CutSelection;
end;

{ ===========================================================================
  TfrmMain.DoCopy  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler: copies the selection to the clipboard in TinyCAD's format.
  =========================================================================== }
procedure TfrmMain.DoCopy(Sender: TObject);
begin
  if EditShortcutInBox('C') then
    Exit;
  FView.CopyToClipboard;
end;

{ ===========================================================================
  TfrmMain.DoPaste  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler: pastes what is on the clipboard (from this program or from TinyCAD); the pasted
    objects follow the mouse until a click drops them.
  =========================================================================== }
procedure TfrmMain.DoPaste(Sender: TObject);
begin
  if EditShortcutInBox('V') then
    Exit;
  FView.PasteFromClipboard;
end;

{ ===========================================================================
  TfrmMain.DoDuplicate  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler: copies and pastes the selection in one step.
  =========================================================================== }
procedure TfrmMain.DoDuplicate(Sender: TObject);
begin
  FView.DuplicateSelection;
end;

{ ===========================================================================
  TfrmMain.DoRotateLeft  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler: rotates the selection left.
  =========================================================================== }
procedure TfrmMain.DoRotateLeft(Sender: TObject);
begin
  FView.RotateSelection(2);
end;

{ ===========================================================================
  TfrmMain.DoRotateRight  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler: rotates the selection right.
  =========================================================================== }
procedure TfrmMain.DoRotateRight(Sender: TObject);
begin
  FView.RotateSelection(3);
end;

{ ===========================================================================
  TfrmMain.DoFlip  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler: flips the selection left to right.
  =========================================================================== }
procedure TfrmMain.DoFlip(Sender: TObject);
begin
  FView.RotateSelection(4);
end;

{ ===========================================================================
  TfrmMain.DoBringToFront  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler: draws the selection on top of everything else.
  =========================================================================== }
procedure TfrmMain.DoBringToFront(Sender: TObject);
begin
  FView.BringToFront;
end;

{ ===========================================================================
  TfrmMain.DoSendToBack  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler: draws the selection underneath everything else.
  =========================================================================== }
procedure TfrmMain.DoSendToBack(Sender: TObject);
begin
  FView.SendToBack;
end;

{ ===========================================================================
  TfrmMain.pnlLeftClick  (procedure)
  Parameters:
    Sender: TObject - the panel
  Notes:
    Click handler of the left panel; nothing to do.
  =========================================================================== }
procedure TfrmMain.pnlLeftClick(Sender: TObject);
begin

end;

{ ===========================================================================
  TfrmMain.DoToolButton  (procedure)
  Parameters:
    Sender: TObject - the tool button
  Notes:
    Ribbon handler: starts the drawing tool whose number is in the button's Tag (or returns to
    select).
  =========================================================================== }
procedure TfrmMain.DoToolButton(Sender: TObject);
var
  T: TViewTool;
begin
  T := TViewTool((Sender as TComponent).Tag);      // a speed button or a menu item whose Tag is the tool
  if FView.Sheet = nil then
  begin
    ShowMessage(rsCreateOrOpenADocument);
    Exit;
  end;
  if T = vtSelect then
    FView.CancelTool
  else
    FView.BeginTool(T);
  UpdateRibbonState;      // (a click on a pressed button lifts it; it is pressed again if it is the tool)
end;

{ ===========================================================================
  TfrmMain.DoToolMenu  (procedure)
  Parameters:
    Sender: TObject - the tool button
  Notes:
    Ribbon handler: starts the drawing tool whose number is in the button's Tag (or returns to
    select).
  =========================================================================== }
procedure TfrmMain.DoToolMenu(Sender: TObject);
var
  T: TViewTool;
begin
  T := TViewTool((Sender as TComponent).Tag);      // a speed button or a menu item whose Tag is the tool
  if FView.Sheet = nil then
  begin
    ShowMessage(rsCreateOrOpenADocument);
    Exit;
  end;
  if T = vtSelect then
    FView.CancelTool
  else
    FView.BeginTool(T);      // (the Insert menu's checks follow the tool: UpdateRibbonState)
end;

{ ===========================================================================
  TfrmMain.DoPlaceSymbol  (procedure)
  Parameters:
    Sender: TObject - the menu item or button
  Notes:
    Handler: starts placing the symbol selected in the library panel, opening a library first if
    none is open.
  =========================================================================== }
procedure TfrmMain.DoPlaceSymbol(Sender: TObject);
begin
  if frameLibraryPanel.Lib = nil then
    DoOpenLibrary(Sender);
  if frameLibraryPanel.Lib <> nil then
    frameLibraryPanel.PlaceSelected;
end;

{ ===========================================================================
  TfrmMain.AddSheetAt  (procedure)
  Parameters:
    APos: Integer - where the new sheet goes (0 is the first place); the number of sheets or more puts it last
  Notes:
    Adds a sheet with the same paper, border, title block and grid as the current one at that
    place in the order, the sheets from there on moving up by one, as one undo step, and shows
    it. A design with a hierarchical symbol sheet keeps that one first.
  =========================================================================== }
procedure TfrmMain.AddSheetAt(APos: Integer);
var
  S, Src: TDesignSheet;
begin
  if FDesign = nil then
    Exit;
  if SymbolSheetsLocked then
    Exit;
  Src := FView.Sheet;
  FView.BeginChange(rsAddSheet);
  S := FDesign.AddSheet;
  if FDesign.HasHierarchicalSheet and (APos < 1) then
    APos := 1;
  if (APos < 0) or (APos >= FDesign.SheetCount) then
    APos := FDesign.SheetCount - 1
  else
    FDesign.MoveSheet(FDesign.SheetCount - 1, APos);
  if Src <> nil then
  begin
    S.Details.PageWidth := Src.Details.PageWidth;
    S.Details.PageHeight := Src.Details.PageHeight;
    S.Details.AutoSheets := Src.Details.AutoSheets;
    S.Details.ShowBorder := Src.Details.ShowBorder;
    S.Details.BorderMargin := Src.Details.BorderMargin;
    S.Details.Title := Src.Details.Title;
    S.Details.Org := Src.Details.Org;
    S.Details.DocNo := Src.Details.DocNo;
    S.Snap.Grid := Src.Snap.Grid;
    S.Snap.GridSnap := Src.Snap.GridSnap;
  end;
  FView.CommitChange(True);
  RebuildSheetTabs;
  tcSheetTabs.TabIndex := APos;
  FView.SetSheetIndex(APos);
  QueueSheetTabRefresh;
end;

{ ===========================================================================
  TfrmMain.DoAddSheet  (procedure)
  Parameters:
    Sender: TObject - the menu item or button
  Notes:
    Handler: adds a sheet at the end, with the same paper, border, title block and grid as the
    current one, as one undo step, and shows it.
  =========================================================================== }
procedure TfrmMain.DoAddSheet(Sender: TObject);
begin
  if FDesign <> nil then
    AddSheetAt(FDesign.SheetCount);
end;

{ ===========================================================================
  TfrmMain.DoInsertSheet  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Handler of "Insert sheet" in the menu of the sheet tabs (a right click made the sheet clicked
    the current one): the new sheet goes right after it, so with sheet 3 clicked it becomes
    sheet 4 and the old sheets 4 to 9 become 5 to 10.
  =========================================================================== }
procedure TfrmMain.DoInsertSheet(Sender: TObject);
begin
  if (FDesign <> nil) and (FView <> nil) then
    AddSheetAt(FView.SheetIndex + 1);
end;

{ ===========================================================================
  TfrmMain.HierarchyMenuOpen  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The menu is opening: the hierarchical commands are enabled as TinyCAD does - inserting a
    design needs a sheet that is not the hierarchical symbol itself, adding the symbol sheet
    needs a design that does not have one, and the commands on a placed design need one
    selected.
  =========================================================================== }
procedure TfrmMain.HierarchyMenuOpen(Sender: TObject);
var
  Sheet: TDesignSheet;
  Have, Sel: Boolean;
begin
  Sheet := nil;
  if FView <> nil then
    Sheet := FView.Sheet;
  Have := (FDesign <> nil) and (Sheet <> nil) and (not IsSymbolDoc);
  Sel := Have and (SelectedHierarchical <> nil);
  mInsertDesign.Enabled := Have and (not Sheet.IsHierarchicalSymbol);
  mAddHierSymbol.Enabled := Have and (not FDesign.HasHierarchicalSheet);
  mAddHierSheet.Enabled := mAddHierSymbol.Enabled;
  mReloadHier.Enabled := Sel;
  mChangeHier.Enabled := Sel;
  mOpenHier.Enabled := Sel;
end;

{ ===========================================================================
  TfrmMain.ChooseDesignFile  (function)
  Parameters:
    const ATitle: String - text
  Returns:
    String
  Notes:
    The Open dialog set to design files (TinyCAD's "TinyCAD file (*.dsn)" and all files); its
    settings are put back afterwards so Open is not affected.
  =========================================================================== }
function TfrmMain.ChooseDesignFile(const ATitle: String): String;
var
  OldFilter, OldTitle, OldName: String;
  OldOptions: TOpenOptions;
begin
  Result := '';
  OldFilter := OpenDlg.Filter; OldTitle := OpenDlg.Title; OldName := OpenDlg.FileName; OldOptions := OpenDlg.Options;
  try
    OpenDlg.Title := ATitle;
    OpenDlg.Filter := rsTinyCADFileDsnDsnAll;
    OpenDlg.FileName := '';
    OpenDlg.Options := OpenDlg.Options - [ofAllowMultiSelect];
    if OpenDlg.Execute then
      Result := OpenDlg.FileName;
  finally
    OpenDlg.Filter := OldFilter; OpenDlg.Title := OldTitle; OpenDlg.FileName := OldName; OpenDlg.Options := OldOptions;
  end;
end;

{ ===========================================================================
  TfrmMain.InsertDesign  (function)
  Parameters:
    const AFileName: String - path of the file
  Returns:
    Boolean
  Notes:
    OnSelectHierarchical: puts any drawing tool away, reads the design (its hierarchical symbol
    sheet) and, when that works, makes the symbol the thing that follows the mouse until it is
    clicked. A design that cannot be read is reported and nothing is placed. Not offered on the
    hierarchical symbol sheet or while a library symbol is being edited.
  =========================================================================== }
function TfrmMain.InsertDesign(const AFileName: String): Boolean;
var
  H: TDrawHierarchicalSymbol;
begin
  Result := False;
  if (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  if IsSymbolDoc or FView.Sheet.Options.EditLibrary then begin
    sbMainBar.Panels[0].Text := rsOtherDesignsCannotBePlaced;
    Exit;
  end;
  if FView.Sheet.IsHierarchicalSymbol then begin
    sbMainBar.Panels[0].Text := rsADesignCannotBePlaced;
    Exit;
  end;
  FView.BeginTool(vtSelect);
  H := TDrawHierarchicalSymbol.Create(FView.Sheet.Options);
  if not H.Load(ExpandFileName(AFileName)) then
  begin
    ReportProblem(H.LoadError);
    H.Free;
    Exit;
  end;
  H.NewRotation;
  FView.BeginPlace(H);
  Result := True;
end;

{ ===========================================================================
  TfrmMain.DoInsertDesign  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler: Special > Insert another design as symbol...: asks for the design, then places it.
  =========================================================================== }
procedure TfrmMain.DoInsertDesign(Sender: TObject);
var
  F: String;
begin
  if (FDesign = nil) or (FView.Sheet = nil) then begin
    ShowMessage(rsCreateOrOpenADocument);
    Exit;
  end;
  F := ChooseDesignFile(rsInsertAnotherDesignAsSymbol);
  if F <> '' then
    InsertDesign(F);
end;

{ ===========================================================================
  TfrmMain.AddHierarchicalSymbol  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    OnContextAddhierarchicalsymbol: puts any drawing tool away and adds the hierarchical symbol
    sheet in front of the others, with the paper and title block of the sheet being shown, as
    one undo step, and shows it. The design can have only one.
  =========================================================================== }
function TfrmMain.AddHierarchicalSymbol: Boolean;
var
  S, Src: TDesignSheet;
begin
  Result := False;
  if FDesign = nil then
    Exit;
  if SymbolSheetsLocked then
    Exit;
  if FDesign.HasHierarchicalSheet then begin
    sbMainBar.Panels[0].Text := rsThisDesignAlreadyHasA;
    Exit;
  end;
  Src := FView.Sheet;
  FView.BeginTool(vtSelect);
  FView.BeginChange(rsAddHierarchicalSymbol);
  S := FDesign.AddHierarchicalSheet;
  if Src <> nil then
  begin
    S.Details.PageWidth := Src.Details.PageWidth;
    S.Details.PageHeight := Src.Details.PageHeight;
    S.Details.AutoSheets := Src.Details.AutoSheets;
    S.Details.ShowBorder := Src.Details.ShowBorder;
    S.Details.BorderMargin := Src.Details.BorderMargin;
    S.Details.Title := Src.Details.Title;
    S.Details.Org := Src.Details.Org;
    S.Details.DocNo := Src.Details.DocNo;
    S.Snap.Grid := Src.Snap.Grid;
    S.Snap.GridSnap := Src.Snap.GridSnap;
  end;
  FView.CommitChange(True);
  RebuildSheetTabs;
  tcSheetTabs.TabIndex := 0;
  FView.SetSheetIndex(0);
  QueueSheetTabRefresh;
  Result := True;
end;

{ ===========================================================================
  TfrmMain.DoAddHierarchicalSymbol  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler: Special > Add hierarchical symbol, and the same command in the Sheet menu.
  =========================================================================== }
procedure TfrmMain.DoAddHierarchicalSymbol(Sender: TObject);
begin
  AddHierarchicalSymbol;
end;

{ ===========================================================================
  TfrmMain.SelectedHierarchical  (function)
  Parameters:  none
  Returns:
    TDrawHierarchicalSymbol
  Notes:
    What the commands on a placed design act on.
  =========================================================================== }
function TfrmMain.SelectedHierarchical: TDrawHierarchicalSymbol;
begin
  Result := nil;
  if (FView <> nil) and (FView.SelectedCount = 1) and (FView.SelectedObject(0) is TDrawHierarchicalSymbol) then
    Result := FView.SelectedObject(0) as TDrawHierarchicalSymbol;
end;

{ ===========================================================================
  TfrmMain.ReloadSelectedDesign  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    ID_CONTEXT_RELOADSYMBOLFROMDESIGN: forgets what was read from the selected placed design and
    reads its file again, so changes made to that design show. Not an edit of this design, so
    not an undo step. A design that can no longer be read is reported and drawn as the plain
    box.
  =========================================================================== }
function TfrmMain.ReloadSelectedDesign: Boolean;
var
  H: TDrawHierarchicalSymbol;
begin
  Result := False;
  H := SelectedHierarchical;
  if H = nil then
    Exit;
  Result := H.Load(H.FileName);
  if not Result then
    ReportProblem(H.LoadError);
  H.UpdateLayout;
  FView.Invalidate;
end;

{ ===========================================================================
  TfrmMain.ChangeSelectedDesign  (function)
  Parameters:
    const AFileName: String - path of the file
  Returns:
    Boolean
  Notes:
    The Design... button of TinyCAD's symbol panel: the selected placed design is given another
    design file, as one undo step. If the file cannot be read the symbol keeps the one it had
    (and the reason is reported). The labels are laid out again for the new size (the C++ leaves
    them).
  =========================================================================== }
function TfrmMain.ChangeSelectedDesign(const AFileName: String): Boolean;
var
  H, Test: TDrawHierarchicalSymbol;
  Old: String;
begin
  Result := False;
  H := SelectedHierarchical;
  if H = nil then
    Exit;
  Test := TDrawHierarchicalSymbol.Create(FView.Sheet.Options);
  try
    if not Test.Load(ExpandFileName(AFileName)) then
    begin
      ReportProblem(Test.LoadError);
      Exit;
    end;
  finally
    Test.Free;
  end;
  Old := H.FileName;
  FView.BeginChange(rsChangeDesign);
  Result := H.Load(ExpandFileName(AFileName));
  if Result then
    H.NewRotation
  else
    H.Load(Old);
  FView.CommitChange(Result);
  FView.Invalidate;
end;

{ ===========================================================================
  TfrmMain.OpenSelectedDesign  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    ID_CONTEXT_OPENDESIGN: opens the selected placed design's file as a document (a file that is
    already open is shown).
  =========================================================================== }
function TfrmMain.OpenSelectedDesign: Boolean;
var
  H: TDrawHierarchicalSymbol;
begin
  Result := False;
  H := SelectedHierarchical;
  if H = nil then
    Exit;
  if not FileExists(H.FileName) then begin
    ReportProblem(Format(rsFileNotFound, [H.FileName]));
    Exit;
  end;
  try
    OpenDesignFile(H.FileName);
    Result := True;
  except
    on E: Exception do ReportProblem(Format(rsCannotOpen2, [H.FileName, E.Message]));
  end;
end;

{ ===========================================================================
  TfrmMain.DoReloadHierSymbol  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler: Special > Reload symbol from design.
  =========================================================================== }
procedure TfrmMain.DoReloadHierSymbol(Sender: TObject);
begin
  ReloadSelectedDesign;
end;

{ ===========================================================================
  TfrmMain.DoChangeHierDesign  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler: Special > Change design of symbol...: asks for the design.
  =========================================================================== }
procedure TfrmMain.DoChangeHierDesign(Sender: TObject);
var
  F: String;
begin
  if SelectedHierarchical = nil then
    Exit;
  F := ChooseDesignFile(rsChooseTheDesignOfThe);
  if F <> '' then
    ChangeSelectedDesign(F);
end;

{ ===========================================================================
  TfrmMain.DoOpenHierDesign  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler: Special > Open design of symbol.
  =========================================================================== }
procedure TfrmMain.DoOpenHierDesign(Sender: TObject);
begin
  OpenSelectedDesign;
end;

{ ===========================================================================
  TfrmMain.DoProperties  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Menu handler: properties are on the ribbon now, so bring the Properties tab forward.
  =========================================================================== }
procedure TfrmMain.DoProperties(Sender: TObject);
begin
  { the properties are on the View ribbon }
  ShowRibbonTab(PROPS_TAB);
end;

{ ===========================================================================
  TfrmMain.DoInsertLadder  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Menu handler: starts the ladder rails tool.
  =========================================================================== }
procedure TfrmMain.DoInsertLadder(Sender: TObject);
begin
  if FView.Sheet = nil then begin
    ShowMessage(rsCreateOrOpenADocument);
    Exit;
  end;
  FView.BeginTool(vtLadder);
end;

{ ===========================================================================
  TfrmMain.DoRemoveSheet  (procedure)
  Parameters:
    Sender: TObject - the menu item or button
  Notes:
    Menu handler: removes the current sheet after asking, with an undo available.
  =========================================================================== }
procedure TfrmMain.DoRemoveSheet(Sender: TObject);
begin
  if SymbolSheetsLocked then
    Exit;
  RemoveCurrentSheet(True);
end;

{ ===========================================================================
  TfrmMain.DoRenameSheet  (procedure)
  Parameters:
    Sender: TObject - the button, menu item or tab
  Notes:
    Handler (also a double click on a sheet tab): asks for a new name for the current sheet.
  =========================================================================== }
procedure TfrmMain.DoRenameSheet(Sender: TObject);
var
  Cur: String;
begin
  if SymbolSheetsLocked then
    Exit;
  if (FDesign = nil) or (tcSheetTabs.TabIndex < 0) or (tcSheetTabs.TabIndex >= FDesign.SheetCount) then
    Exit;      // (not the "+" tab)
  Cur := tcSheetTabs.Tabs[tcSheetTabs.TabIndex];
  if InputQuery(rsRenameSheet, rsNameOfTheSheet, Cur) then
    RenameCurrentSheet(Cur);
end;

{ ===========================================================================
  TfrmMain.DoMoveSheetLeft  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler: moves the current sheet one place to the left.
  =========================================================================== }
procedure TfrmMain.DoMoveSheetLeft(Sender: TObject);
begin
  if SymbolSheetsLocked then
    Exit;
  MoveCurrentSheet(-1);
end;

{ ===========================================================================
  TfrmMain.DoMoveSheetRight  (procedure)
  Parameters:
    Sender: TObject - the button or menu item
  Notes:
    Handler: moves the current sheet one place to the right.
  =========================================================================== }
procedure TfrmMain.DoMoveSheetRight(Sender: TObject);
begin
  if SymbolSheetsLocked then
    Exit;
  MoveCurrentSheet(1);
end;

{ ===========================================================================
  TfrmMain.RemoveCurrentSheet  (function)
  Parameters:
    Confirm: Boolean - True to ask first (and to explain when it cannot be done)
  Returns:
    Boolean - True if a sheet was removed
  Notes:
    Removes the sheet being shown, with everything on it, as one undo step, and shows the sheet
    that took its place. A design keeps at least one sheet.
  =========================================================================== }
function TfrmMain.RemoveCurrentSheet(Confirm: Boolean): Boolean;
var
  Idx, NewIdx: Integer;
begin
  Result := False;
  if FDesign = nil then
    Exit;
  if FDesign.SheetCount <= 1 then
  begin
    if Confirm then
      ShowMessage(rsADesignNeedsAtLeast);
    Exit;
  end;
  Idx := FView.SheetIndex;
  if Confirm and (MessageDlg(Format(rsRemoveAndEverythingOnIt, [tcSheetTabs.Tabs[Idx]]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  FView.BeginChange(rsRemoveSheet);
  Result := FDesign.RemoveSheet(Idx);
  NewIdx := Min(Idx, FDesign.SheetCount - 1);
  FView.SetSheetIndex(NewIdx);
  QueueSheetTabRefresh;
  FView.CommitChange(Result);
  RebuildSheetTabs;
end;

{ ===========================================================================
  TfrmMain.RenameCurrentSheet  (procedure)
  Parameters:
    const NewName: String - the new name
  Notes:
    Gives the sheet being shown a name (an empty name goes back to "Sheet N") as one undo step.
  =========================================================================== }
procedure TfrmMain.RenameCurrentSheet(const NewName: String);
var
  Idx: Integer;
begin
  if FDesign = nil then
    Exit;
  Idx := FView.SheetIndex;
  if FDesign.Sheets[Idx].IsHierarchicalSymbol then
    Exit;       // (its name is fixed, as TinyCAD's is)
  if FDesign.Sheets[Idx].SheetName = Trim(NewName) then
    Exit;
  FView.BeginChange(rsRenameSheet);
  FDesign.Sheets[Idx].SheetName := Trim(NewName);
  FView.CommitChange(True);
  RebuildSheetTabs;
end;

{ ===========================================================================
  TfrmMain.MoveCurrentSheet  (procedure)
  Parameters:
    Delta: Integer - -1 for one place left, 1 for one place right
  Notes:
    Moves the sheet being shown among the others, keeping it shown, as one undo step. Moving
    past either end does nothing.
  =========================================================================== }
procedure TfrmMain.MoveCurrentSheet(Delta: Integer);
var
  Idx, NewIdx: Integer;
begin
  if FDesign = nil then
    Exit;
  Idx := FView.SheetIndex;
  NewIdx := Idx + Delta;
  if (NewIdx < 0) or (NewIdx >= FDesign.SheetCount) then
    Exit;
  FView.BeginChange(rsMoveSheet);
  FDesign.MoveSheet(Idx, NewIdx);
  FView.SetSheetIndex(NewIdx);
  QueueSheetTabRefresh;
  FView.CommitChange(True);
  RebuildSheetTabs;
end;

{ ===========================================================================
  TfrmMain.SheetTabsAreRight  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    Whether the sheet tabs show exactly the design's sheets (count, names and the one being
    shown).
  =========================================================================== }
function TfrmMain.SheetTabsAreRight: Boolean;
begin
  Result := SheetTabsMatch;
end;

{ ===========================================================================
  TfrmMain.SheetTabsMatch  (function)
  Parameters:  none
  Returns:
    Boolean - True if they agree
  Notes:
    Whether the sheet tabs show exactly the design's sheets (count, names and the one being
    shown).
  =========================================================================== }
function TfrmMain.SheetTabsMatch: Boolean;
var
  i, Extra: Integer;
begin
  Result := False;
  if FDesign = nil then
    Exit;
  if IsSymbolDoc then
    Extra := 0
  else
    Extra := 1;
  if tcSheetTabs.Tabs.Count <> FDesign.SheetCount + Extra then
    Exit;          // the sheets and the "+" tab
  if (Extra = 1) and (tcSheetTabs.Tabs[FDesign.SheetCount] <> ADD_SHEET_TAB) then
    Exit;
  for i := 0 to FDesign.SheetCount - 1 do
    if tcSheetTabs.Tabs[i] <> SheetTabCaption(i) then
      Exit;
  Result := tcSheetTabs.TabIndex = FView.SheetIndex;
end;

{ ===========================================================================
  TfrmMain.mAboutClick  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Menu handler: same as DoAbout.
  =========================================================================== }
procedure TfrmMain.mAboutClick(Sender: TObject);
begin
  DoAbout(Sender);
end;

{ ===========================================================================
  TfrmMain.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the form
  Notes:
    OnCreate handler: sets the caption, makes the window big enough for the ribbon if the
    designed size is smaller, then builds the run-time controls (layout and ribbon) and starts
    with no document.
  =========================================================================== }
procedure TfrmMain.FormCreate(Sender: TObject);
var
  i: Integer;
begin
  FPrinterPicked := -1;
  OpenDlg := frmSharedControls.OpenDlg;            // the shared dialogs and image lists (the form file no longer holds them)
  SaveDlg := frmSharedControls.SaveDlg;
  PrintDlg := frmSharedControls.PrintDlg;
  dlgPrinterSetup := frmSharedControls.dlgPrinterSetup;
  dlgPageSetup := frmSharedControls.dlgPageSetup;
  ReplaceDlg := frmSharedControls.ReplaceDlg;
  ilSpeedBtn := frmSharedControls.ilSpeedBtn;
  ilTinyIcons := frmSharedControls.ilTinyIcons;
  ilListBoxImages := frmSharedControls.ilListBoxImages;
  for i := 0 to ComponentCount - 1 do              // the buttons' pictures (a form file cannot name an image list of another form)
    if (Components[i] is TSpeedButton) and (TSpeedButton(Components[i]).Images = nil) then
      TSpeedButton(Components[i]).Images := ilSpeedBtn;
  PrintTestDpi := 100;
  FAnnotate := AnnotateDefaults;
  FFind := TFindSession.Create;
  { the find panel is made here and not by the form file: an inline frame in the .lfm is only kept by the designer while it knows the
    frame's unit, and a form file without it would leave the field nil. It sits in the left panel beside the library panel. }
  if frameFindPanel = nil then
  begin
    frameFindPanel := TfrFindPanel.Create(Self);
    frameFindPanel.Name := 'frameFindPanel';
    frameFindPanel.Parent := pnlLeft;
    frameFindPanel.Align := alClient;
    frameFindPanel.Visible := False;
  end;
  Caption := lAppName;
  if Width < 1200 then
    Width := 1360;      // the ribbon needs room; a bigger designed size is kept
  if Height < 700 then
    Height := 820;
  Position := poScreenCenter;
  KeyPreview := True;
  OnKeyUp := @FormKeyUp;
//  OnKeyDown := @FormKeyDown;
//  OnCloseQuery := @FormCloseQuery;
  FDocs := TDocumentList.Create;
  FCurrent := -1;
  FDetailsDrop := TfrmDesignDetailsDropDown.Create(Self);
  FDetailsDrop.cbSheetDetailsShowRuler.OnClick := @DoDesignDetailsRuler;
  FDetailsDrop.cbSheetDetailsBorder.OnClick := @DoDesignDetailsBorder;
  sbSheetDetails.AutoCheck := True;
  sbSheetDetails.OnDropDownClick := @DoDetailsDropDown;
  BuildLayout;
  BuildRibbon;
  { the counts, last row and border margin of the details panel are applied when Enter is pressed or the box is left }
  FDetailsDrop.edSheetDetailsCols.OnExit := @DetailsFieldExit;
  FDetailsDrop.edSheetDetailsRows.OnExit := @DetailsFieldExit;
  FDetailsDrop.edSheetDetailsMargin.OnExit := @DetailsFieldExit;
  FDetailsDrop.edSheetDetailsCols.OnKeyPress := @DetailsFieldKeyPress;
  FDetailsDrop.edSheetDetailsRows.OnKeyPress := @DetailsFieldKeyPress;
  FDetailsDrop.edSheetDetailsMargin.OnKeyPress := @DetailsFieldKeyPress;
  ShowNoDocument;
  pnlLeft.BevelOuter := bvNone;
  pnlMain.BevelOuter := bvNone;
  pnlLeft.Caption := '';
  pnlMain.Caption := '';
  // ribbon setup
  FRibbonTabs := TRibbonTabStrip.Create(Self, pbRibbonDisplay, FRibbon);
  FRibbonTabs.OnChoose := @ChooseRibbonTab;
  FRibbon.ShowTabs := False;
  pbRibbonDisplay.Font.Name := 'Segoe UI';
  pbRibbonDisplay.Font.Size := 11;
  sbViewGridShow.Down := mShowGrid.Checked;
  { the Find and Replace dialog is the ReplaceDlg component: its buttons call these }
  ReplaceDlg.OnFind := @ReplaceDlgFind;
  ReplaceDlg.OnReplace := @ReplaceDlgReplace;
  ReplaceDlg.OnClose := @ReplaceDlgClose;
  frameFindPanel.UseCloseIcon(ilTinyIcons, 0);        // the red X of the image list closes the find
  frameFindPanel.OnFindRequest := @FindPanelFind;
  frameFindPanel.OnResultSelected := @FindPanelResultSelected;
  frameFindPanel.OnCloseRequest := @FindPanelClose;
  FRecentItems := TList.Create;
  LoadSettings;              // the settings kept in the registry: the recently used files and the options
  UseSettingsAsDefaults;     // new designs start with the saved options
  if (ProgramSettings.LastPartsFile <> '') and FileExists(ProgramSettings.LastPartsFile) then
    frameLibraryPanel.OpenPartsFile(ProgramSettings.LastPartsFile);      // the parts library that was open last
  Application.OnHint := @AppHint;                             // menu and control hints go to the status bar
  ApplyTheme(ProgramSettings.DarkMode);                       // the light or dark theme as it was left
  ShowPositionBar(ProgramSettings.ShowPosition, False);       // the Position bar as it was left
  ShowViewRulers(ProgramSettings.ShowViewRulers, False);      // the rulers as they were left
  SetupAutoSave;
  RebuildRecentMenu;
  OnShow := @FormShow;       // the window and its splitters are put as they were left once the window is shown (the form is scaled to the screen before that)
end;

{ ===========================================================================
  TfrmMain.DoTheme  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Menu handler: switches between the light and dark ribbon theme and changes the menu item's
    caption to offer the other one.
  =========================================================================== }
procedure TfrmMain.DoTheme(Sender: TObject);
begin
  ApplyTheme(FTheme = themeLight);       // light: change to dark; dark: change to light
  ProgramSettings.DarkMode := FTheme = themeDark;
  SaveSettings;
end;

{ ===========================================================================
  TfrmMain.ApplyTheme  (procedure)
  Parameters:
    Dark: Boolean - flag
  Notes:
    Sets the ribbon theme and makes the Theme menu item offer the other one. It does not change
    the saved setting (DoTheme and the settings do that).
  =========================================================================== }
procedure TfrmMain.ApplyTheme(Dark: Boolean);
begin
  if Dark then
  begin
    mTheme.Caption := rsLightMode;
    Theme := themeDark;
  end
  else
  begin
    mTheme.Caption := rsDarkMode;
    Theme := themeLight;
  end;
end;

{ ===========================================================================
  TfrmMain.AppHint  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Application.OnHint handler: the hint of the menu item under the cursor (or of a control that
    shows one) goes into the first panel of the status bar; when there is none the panel says
    Ready. A menu item's hint is the text after any | in its Hint property, as the LCL gives it.
  =========================================================================== }
procedure TfrmMain.AppHint(Sender: TObject);
begin
  if Application.Hint <> '' then
    sbMainBar.Panels[0].Text := Application.Hint
  else
    sbMainBar.Panels[0].Text := rsReady;
end;

{ ===========================================================================
  TfrmMain.FormActivate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Setup controls etc.
  =========================================================================== }
procedure TfrmMain.FormActivate(Sender: TObject);
begin
  if not FActivated then
  begin
    FActivated := True;
    FRibbon.ActivePageIndex := 0;     // regardless of where it's left in design time, set to the first sheet (the first time only)
  end;
  { the centre and spacer panels have placeholder text in the form file; nothing is shown in them yet }
  if sbMainBar.Panels.Count > 5 then
    sbMainBar.Panels.Items[5].Text := '';
  if sbMainBar.Panels.Count > 3 then
    sbMainBar.Panels.Items[3].Text := '';
end;

{ ===========================================================================
  TfrmMain.DoGridSizeUp  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    Handler (grid size up button): sets the grid to the next larger of the preset sizes than it
    has now, going back to the smallest after the largest. It works from the grid actually in
    use, so it also works from a custom size and after changing document.
  =========================================================================== }
procedure TfrmMain.DoGridSizeUp(Sender: TObject);
var
  i, NextIdx: Integer;
  Mm: Double;
begin
  { the sizes are the first items of the menu (a separator and Custom... follow them). Go to the next
    larger size than the grid has now, which also works from a custom size or after changing document;
    after the largest, go back to the smallest. }
  Mm := FView.GridMm;
  NextIdx := 0;
  for i := 0 to Length(GridSizeMM) - 1 do
    if GridSizeMM[i] / 1000 > Mm + 0.0005 then
    begin
      NextIdx := i;
      Break;
    end;
  DoGridSize(pmGridSize.Items[NextIdx]);
end;

{ ===========================================================================
  TfrmMain.DoDesignDetailsExtended  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Handler of the Extended info box of the ribbon: shows or hides the extended information of
    the title block (the revision table beside it and the notes and reference cell above it) on
    the current sheet, as one undo step.
  =========================================================================== }
procedure TfrmMain.DoDesignDetailsExtended(Sender: TObject);
begin
  if FUpdatingRibbon then
    Exit;
  if Sender = miExtendedInfo then
    sbExtendedInfo.Down := not sbExtendedInfo.Down;      // (the menu item asked: it toggles, the button follows)
  miExtendedInfo.Checked := sbExtendedInfo.Down;
  ApplySheetDetail(sdExtended);
end;

{ ===========================================================================
  TfrmMain.DoDetailsDropDown  (procedure)
  Parameters:
    Sender: TObject - the Details split button
  Notes:
    OnDropDownClick of the Details button: shows the form with the other sheet details (border,
    margin, ruler counts) just below it; a click on the arrow while it is open closes it (the
    click that closed it does not open it again).
  =========================================================================== }
procedure TfrmMain.DoDetailsDropDown(Sender: TObject);
begin
  if FDetailsDrop.Visible then
  begin
    FDetailsDrop.Close;
    Exit;
  end;
  if FDetailsDrop.JustClosed then
    Exit;
  FDetailsDrop.Popup(Sender as TControl);
end;

{ ===========================================================================
  TfrmMain.DoDesignDetailsBorder  (procedure)
  Parameters:
    Sender: TObject - the check box
  Notes:
    Handler of the Border box on the ribbon: enables or disables the margin and writes the
    setting to the current sheet.
  =========================================================================== }
procedure TfrmMain.DoDesignDetailsBorder(Sender: TObject);
begin
  if FUpdatingRibbon then
    Exit;
  FDetailsDrop.edSheetDetailsMargin.Enabled := FDetailsDrop.cbSheetDetailsBorder.Checked;
  ApplySheetDetail(sdBorder);
end;

{ ===========================================================================
  TfrmMain.DoDesignDetailsRuler  (procedure)
  Parameters:
    Sender: TObject - the check box
  Notes:
    Handler of the Details button of the ribbon (a check button: down = rulers on), of the
    Show rulers box of its drop-down form and of the View > Show Rulers item, which all say the same: enables or disables the counts
    and writes the setting to the current sheet.
  =========================================================================== }
procedure TfrmMain.DoDesignDetailsRuler(Sender: TObject);
begin
  if FUpdatingRibbon then
    Exit;
  if Sender = miShowRulers then
  begin
    sbSheetDetails.Checked := not sbSheetDetails.Checked;      // (the menu item asked: it toggles, the button and the box follow)
    FDetailsDrop.cbSheetDetailsShowRuler.Checked := sbSheetDetails.Checked;
  end
  else if Sender = FDetailsDrop.cbSheetDetailsShowRuler then
    sbSheetDetails.Checked := FDetailsDrop.cbSheetDetailsShowRuler.Checked      // (the box asked for it: the button follows)
  else
    FDetailsDrop.cbSheetDetailsShowRuler.Checked := sbSheetDetails.Checked;      // (the button asked: the box follows)
  FDetailsDrop.edSheetDetailsCols.Enabled := sbSheetDetails.Checked;
  FDetailsDrop.edSheetDetailsRows.Enabled := sbSheetDetails.Checked;
  miShowRulers.Checked := sbSheetDetails.Checked;
  ApplySheetDetail(sdRulers);
end;

{ ===========================================================================
  TfrmMain.FormResize  (procedure)
  Parameters:
    Sender: TObject - the form
  Notes:
    OnResize handler: gives the three status-bar panels their share of the window width
    (StatusBarScale in consts).
  =========================================================================== }
procedure TfrmMain.FormResize(Sender: TObject);

  procedure SetPanelWidth(fPanel: TStatusPanel; fWidth: integer);
  var i, tWidth: integer;
  begin
    if fWidth = -1 then
      begin
        tWidth := 0;
        for i := 0 to TStatusBar(fPanel.Collection.Owner).Panels.Count - 1 do
          begin
            if not (TStatusBar(fPanel.Collection.Owner).Panels.Items[i] = fPanel) then
              inc(tWidth, TStatusBar(fPanel.Collection.Owner).Panels.Items[i].Width);
          end;
        fPanel.Width := TStatusBar(fPanel.Collection.Owner).Width - tWidth;
      end
    else
      fPanel.Width := fWidth;
  end;

begin
  try
    { (a panel the form does not have is skipped, so an older form file does not stop the resize) }
    if sbMainBar.Panels.Count > 0 then
      SetPanelWidth(sbMainBar.Panels.Items[0], StatusBarWidth[0]);
    if sbMainBar.Panels.Count > 1 then
      SetPanelWidth(sbMainBar.Panels.Items[1], StatusBarWidth[1]);
    if sbMainBar.Panels.Count > 2 then
      SetPanelWidth(sbMainBar.Panels.Items[2], StatusBarWidth[2]);
    if sbMainBar.Panels.Count > 4 then
      SetPanelWidth(sbMainBar.Panels.Items[4], StatusBarWidth[4]);
    if sbMainBar.Panels.Count > 5 then
      SetPanelWidth(sbMainBar.Panels.Items[5], StatusBarWidth[5]);
    if sbMainBar.Panels.Count > 3 then
      SetPanelWidth(sbMainBar.Panels.Items[3], StatusBarWidth[3]);  // do this one last, it's sized to what's left.

{    sbMainBar.Panels.Items[0].Width := round(Self.Width * (StatusBarScale[0] / 100));
    sbMainBar.Panels.Items[1].Width := round(Self.Width * (StatusBarScale[1] / 100));
    sbMainBar.Panels.Items[2].Width := round(Self.Width * (StatusBarScale[2] / 100));
    sbMainBar.Panels.Items[3].Width := round(Self.Width * (StatusBarScale[3] / 100));
    sbMainBar.Panels.Items[4].Width := round(Self.Width * (StatusBarScale[4] / 100));}
  except
    raise;  // something is badly broken
  end;
end;

{ ===========================================================================
  TfrmMain.DoZoomIn  (procedure)
  Parameters:
    Sender: TObject - the menu item or button
  Notes:
    Handler: zooms in by 25%.
  =========================================================================== }
procedure TfrmMain.DoZoomIn(Sender: TObject);  begin FView.ZoomBy(1.25); end;

{ ===========================================================================
  TfrmMain.DoZoomOut  (procedure)
  Parameters:
    Sender: TObject - the menu item or button
  Notes:
    Handler: zooms out by 20%.
  =========================================================================== }
procedure TfrmMain.DoZoomOut(Sender: TObject); begin FView.ZoomBy(0.8); end;

{ ===========================================================================
  TfrmMain.DoZoomFit  (procedure)
  Parameters:
    Sender: TObject - the menu item or button
  Notes:
    Handler: shows the whole page.
  =========================================================================== }
procedure TfrmMain.DoZoomFit(Sender: TObject); begin FView.ZoomFit; end;

{ ===========================================================================
  TfrmMain.DoZoom100  (procedure)
  Parameters:
    Sender: TObject - the menu item or button
  Notes:
    Handler: actual size.
  =========================================================================== }
procedure TfrmMain.DoZoom100(Sender: TObject); begin FView.ZoomActual; end;

{ ===========================================================================
  TfrmMain.DoToggleGrid  (procedure)
  Parameters:
    Sender: TObject - the menu item or button
  Notes:
    Handler: shows or hides the grid dots and ticks the menu item.
  =========================================================================== }
procedure TfrmMain.DoToggleGrid(Sender: TObject);
begin
  FView.ShowGrid := not FView.ShowGrid;
  mShowGrid.Checked := FView.ShowGrid;
  sbViewGridShow.Down := mShowGrid.Checked;
  FView.Invalidate;
  UpdatePositionBar;
end;

{ ===========================================================================
  TfrmMain.DoToggleSnap  (procedure)
  Parameters:
    Sender: TObject - the snap button
  Notes:
    Handler of the ribbon snap buttons and of the View > Snap to Grid item: turns snapping to the
    grid on or off and puts the buttons and the menu tick in line.
  =========================================================================== }
procedure TfrmMain.DoToggleSnap(Sender: TObject);
begin
  FView.SnapEnabled := not FView.SnapEnabled;
  sbViewGridSnapTo.Down := FView.SnapEnabled;
  miGridSnap.Checked := FView.SnapEnabled;
  UpdatePositionBar;
  if FView.SnapEnabled then
    sbMainBar.Panels[0].Text := rsSnapToGridOn
  else
    sbMainBar.Panels[0].Text := rsSnapToGridOff;
end;

{ ===========================================================================
  TfrmMain.DoGridButton  (procedure)
  Parameters:
    Sender: TObject - the grid button
  Notes:
    Ribbon handler: pops up the grid-size menu under the button with the current size ticked.
  =========================================================================== }
procedure TfrmMain.DoGridButton(Sender: TObject);
var
  P: TPoint;
  i: Integer;
begin
  for i := 0 to pmGridSize.Items.Count - 2 do
    pmGridSize.Items[i].Checked := Abs(pmGridSize.Items[i].Tag / 100 - FView.GridMm) < 0.001;
  SyncGridSizeMenus;
  P := sbViewGridSize.ClientToScreen(Point(0, sbViewGridSize.Height));
  pmGridSize.PopUp(P.x, P.y);
end;

{ ===========================================================================
  TfrmMain.DoGridSize  (procedure)
  Parameters:
    Sender: TObject - the chosen menu item
  Notes:
    Grid-size menu handler: applies the size held in the menu item's Tag (hundredths of a
    millimetre).
  =========================================================================== }
procedure TfrmMain.DoGridSize(Sender: TObject);
begin
  FView.GridMm := (Sender as TMenuItem).Tag / 100;
  (Sender as TMenuItem).Checked := true;
  SyncGridSizeMenus;
  UpdateRibbonState;
end;

{ ===========================================================================
  TfrmMain.DoGridCustom  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Grid-size menu handler: asks for a custom grid size in millimetres (0.05 to 100).
  =========================================================================== }
procedure TfrmMain.DoGridCustom(Sender: TObject);
var
  S: String;
  V: Double;
  Fs: TFormatSettings;
  FormInput: TfrmNumInput;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  S := FloatToStr(FView.GridMm, Fs);
  FormInput := TfrmNumInput.Create(Self, [fcbOK, fcbCancel], 0.05, 100, rsEnterANewGridSize);
  try
    FormInput.edInput.Text := S;      // start from the grid size now in use
    if FormInput.ShowModal = mrOK then
{  if InputQuery('Grid size', 'Grid size in millimetres:', S) then}
{      if TryStrToFloat(StringReplace(Trim(S), ',', '.', []), V, Fs) and (V > 0.05) and (V <= 100) then}
      begin
//        v := StrToFloat(FormInput.FInput, Fs);
        FView.GridMm := StrToFloat(FormInput.FInput, Fs);  // should be checked in the dialog for format
        SyncGridSizeMenus;
        UpdateRibbonState;
      end;
  finally
    FormInput.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.DoAbout  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Handler: shows the About message.
  =========================================================================== }
procedure TfrmMain.DoAbout(Sender: TObject);
var
  form: TfrmAbout;
begin
  form := TfrmAbout.Create(Self);
  try
    form.ShowModal;
  finally
    form.Free;
  end;
{  ShowMessage(APP_NAME + ' - an electrical schematic editor'#10#10 +
    'Based on TinyCAD by Matt Pyne (LGPL 2.1 or later), ported to Free Pascal / Lazarus.');}
end;

{ ------------------------------------------------------------------ view and panel events }

{ ===========================================================================
  TfrmMain.DescribeSelection  (function)
  Parameters:  none
  Returns:
    String - the description, empty when nothing is selected
  Notes:
    A short description of the selection for the status bar and ribbon (the kind of object, or
    "N objects").
  =========================================================================== }
function TfrmMain.DescribeSelection: String;
var
  O: TDrawingObject;
  N: String;
begin
  if Assigned(FView) then
    case FView.SelectedCount of
      0: Result := '';
      1:
        begin
          O := FView.SelectedObject(0);
          if O is TDrawLadder then
            N := rsLadderRails
          else if O is TDrawRungGrid then
            N := rsRungNumbers
          else if O is TDrawMethod then
            N := Format(rsSymbol2, [(O as TDrawMethod).GetRef])
          else if O is TDrawLine then
          begin
            if O.GetType = xWire then
              N := rsWire
            else if O.GetType = xBus then
              N := rsBus
            else
              N := rsLine2;
          end
          else if O is TDrawPower then
            N := rsPowerSymbol
          else if O is TDrawBusSlash then
            N := rsBusSlash
          else if O is TDrawNoConnect then
            N := rsNoConnect
          else if O is TDrawPin then
            N := rsPin
          else if O is TDrawMetaFile then
            N := rsPicture
          else if O is TDrawText then
            N := rsText
          else if O is TDrawLabel then
            N := rsWireLabel
          else if O is TDrawPolygon then
            N := rsPolygonArc
          else if O is TDrawSquare then
            N := rsRectangleCircle
          else if O is TDrawNoteText then
            N := rsNote
          else if O is TDrawCloud then
            N := rsCloud
          else if O is TDrawMeasure then
            N := rsMeasure
          else if O is TDrawRuler then
            N := rsRuler
          else if O is TDrawRefText then
            N := rsLinkedText
          else if O is TDrawJunction then
            N := rsJunction
          else if O is TDrawError then
            N := rsDesignMarker
          else
            N := O.ClassName;
          Result := N;
        end;
    else
      Result := Format(rsObjectsChangesApplyToAll, [FView.SelectedCount]);
    end;
end;

{ ===========================================================================
  TfrmMain.ViewSelection  (procedure)
  Parameters:
    Sender: TObject - the view
  Notes:
    View event: the selection changed. Updates the status bar, rebuilds the property editors,
    and brings the Properties tab forward when the select tool is active. One text, label or note
    chosen: its text box takes the focus; one placed symbol: its reference box (edRef) takes it on a double click (ViewDblClick).
  =========================================================================== }
procedure TfrmMain.ViewSelection(Sender: TObject);
begin
  if FDestroying then
    Exit;      { (freeing the documents makes each view let go of its design, which reports an empty selection) }
  sbMainBar.Panels[1].Text := DescribeSelection;
  { a marker picked on the sheet is the line chosen in the Design Markers window (CDrawError::BeginEdit) }
  if (FErcForm <> nil) and (FErcDoc <> nil) and (FErcDoc = GetCurDoc) and (FView.SelectedCount = 1) and (FView.SelectedObject(0) is TDrawError) then
    FErcForm.SetSelect((FView.SelectedObject(0) as TDrawError).ErrorNumber);
  RebuildProps;
  { one text object (text, wire label or note) selected: its text box takes the focus with the whole text selected }
  if (FView.SelectedCount = 1) and (FView.Tool = vtSelect) and
     ((FView.SelectedObject(0) is TDrawText) or (FView.SelectedObject(0) is TDrawLabel) or (FView.SelectedObject(0) is TDrawNoteText)) then
  begin
    ShowRibbonTab(PROPS_TAB);
    FocusTextEditor;
  end;
  { selecting something brings its properties forward, unless a drawing tool is in use; the tab that was showing is remembered, and comes back
    when nothing is selected any more (if the person has not moved to another tab meanwhile) }
  if (FView.SelectedCount > 0) and (FView.Tool = vtSelect) then
  begin
    if not SameText(RibbonTabTitle, PROPS_TAB) then
    begin
      FTabBeforeProps := RibbonTabTitle;
      ShowRibbonTab(PROPS_TAB);
    end;
  end
  else if FView.SelectedCount = 0 then
  begin
    if (FTabBeforeProps <> '') and SameText(RibbonTabTitle, PROPS_TAB) then
      ShowRibbonTab(FTabBeforeProps);
    FTabBeforeProps := '';
  end;
end;

{ ===========================================================================
  TfrmMain.ViewStatus  (procedure)
  Parameters:
    Sender: TObject - the view
    const Msg: String - the message
  Notes:
    View event: shows a message in the first status panel.
  =========================================================================== }
procedure TfrmMain.ViewStatus(Sender: TObject; const Msg: String);
begin
  sbMainBar.Panels[0].Text := Msg;
end;

{ ===========================================================================
  TfrmMain.ViewModified  (procedure)
  Parameters:
    Sender: TObject - the view
  Notes:
    View event: a design changed. Marks the document that owns the view as modified, updates its
    tab, and (for the current document) the title and property values.
  =========================================================================== }
procedure TfrmMain.ViewModified(Sender: TObject);
var
  At: Integer;
begin
  At := FDocs.IndexOfView(Sender);       // the document whose view raised it
  if At < 0 then
    Exit;
  FDocs[At].Modified := True;
  UpdateDocTabs;
  if At = FCurrent then
  begin
    UpdateFormTitle;
    ShowPropValues;
  end;
end;

{ ===========================================================================
  TfrmMain.ViewToolChanged  (procedure)
  Parameters:
    Sender: TObject - the view
  Notes:
    View event: the active tool changed, so refresh the pressed tool button.
  =========================================================================== }
procedure TfrmMain.ViewToolChanged(Sender: TObject);
begin
  UpdateRibbonState;
end;

{ ===========================================================================
  TfrmMain.ViewUndoChanged  (procedure)
  Parameters:
    Sender: TObject - the view
  Notes:
    View event: undo state changed. An undo or redo can add, remove or reorder sheets, so the
    sheet tabs are rebuilt when they no longer match, and the undo and redo buttons are
    refreshed.
  =========================================================================== }
procedure TfrmMain.ViewUndoChanged(Sender: TObject);
begin
  if (FDesign <> nil) and (not SheetTabsMatch) then
    RebuildSheetTabs;     // an undo or redo may have added or removed a sheet
  UpdateRibbonState;
end;

{ ===========================================================================
  TfrmMain.ViewDblClick  (procedure)
  Parameters:
    Sender: TObject - the view
  Notes:
    View event: a double click on the sheet. When one placed symbol is chosen (the first click
    of the double click chose it) the reference box of its frame takes the focus with the
    reference selected, so typing replaces it; choosing a symbol with a single click no longer
    moves the focus.
  =========================================================================== }
procedure TfrmMain.ViewDblClick(Sender: TObject);
begin
  if (FView.SelectedCount = 1) and (FView.Tool = vtSelect) and (FView.SelectedObject(0) is TDrawMethod) then
  begin
    ShowRibbonTab(PROPS_TAB);
    FocusPropEditor('sym.ref');
  end;
end;

{ ===========================================================================
  TfrmMain.FocusTextEditor  (procedure)
  Parameters:  none
  Notes:
    Puts the focus in the text box of the Properties panel or frame (the editor of the "text" property)
    with all of its text selected, so typing replaces the text. Does nothing when the frame has
    no such box showing or the window cannot take the focus yet.
  =========================================================================== }
procedure TfrmMain.FocusTextEditor;
begin
  FocusPropEditor('text');
end;

{ ===========================================================================
  TfrmMain.FocusPropEditor  (procedure)
  Parameters:
    const AName: String - the property whose box takes the focus ('text', 'sym.ref' ...)
  Notes:
    Puts the focus in the text box of the Properties panel or frame that edits that property,
    with all of its text selected, so typing replaces it. Does nothing when there is no such
    box showing or it cannot take the focus yet (CanFocus is asked first: SetFocus on a box that
    cannot take it raises an exception that stops the program in the debugger).
  =========================================================================== }
procedure TfrmMain.FocusPropEditor(const AName: String);
  function TryFocus(C: TControl): Boolean;
  begin
    Result := False;
    if not ((C is TEdit) and C.Visible) then
      Exit;
    Result := True;
    if (C as TEdit).CanFocus then
    begin
      try
        (C as TEdit).SetFocus;
        (C as TEdit).SelectAll;
        if AName = 'sym.ref' then
        begin
          FRefAutoEdit := C as TEdit;
          FRefAutoText := (C as TEdit).Text;
        end;
      except
        // (still not focusable)
      end;
    end;
  end;
var
  i: Integer;
begin
  for i := 0 to High(FProps) do
    if (FProps[i].Def.Name = AName) and TryFocus(FProps[i].Control) then
      Exit;
  { the editor of a property frame (the label, text, note and symbol frames) }
  for i := 0 to High(FPropBind) do
    if (FPropBind[i].Def.Name = AName) and TryFocus(FPropBind[i].Control) then
      Exit;
end;

{ ===========================================================================
  TfrmMain.PropEditKeyDown  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    var Key: Word - key code (in/out: changed by the call)
    Shift: TShiftState - modifier keys held down
  Notes:
    Key handling of the text box of a single selected text, label or power symbol. Del works on
    the text in the box (the usual editing of a box) as long as there is text in it; pressing
    Del when the box is empty deletes the selected object instead.
  =========================================================================== }
procedure TfrmMain.PropEditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  I: Integer;
begin
  if (Key <> VK_DELETE) or (Shift <> []) then
    Exit;
  I := (Sender as TControl).Tag;
  if (I < 0) or (I > High(FProps)) or (FProps[I].Def.Name <> 'text') then
    Exit;
  if (Sender as TEdit).Text <> '' then
    Exit;
  if (FView <> nil) and (FView.SelectedCount = 1) then
  begin
    Key := 0;
    FView.DeleteSelection;
  end;
end;

{ ===========================================================================
  TfrmMain.ViewPlaced  (procedure)
  Parameters:
    Sender: TObject - the view
    Obj: TDrawingObject - the new object
  Notes:
    View event: an object was created. One-shot tools return to select; a new label brings the
    Properties tab forward and focuses its text box.
  =========================================================================== }
procedure TfrmMain.ViewPlaced(Sender: TObject; Obj: TDrawingObject);
begin
  { shapes are one-shot: back to the select tool, with the new object selected and its properties showing }
  if FView.Tool in [vtPolygon, vtRect, vtCircle, vtArc, vtNote, vtCloud, vtMeasure, vtLadder, vtRulerH, vtRulerV, vtXRefLine, vtXRefContacts] then
    FView.CancelTool;
  { a text placed with the Text tool: the tool's text box shows the next one }
  if ((Obj is TDrawText) and (FView.Tool = vtText)) or ((Obj is TDrawLabel) and (FView.Tool = vtLabel)) then
  begin
    ShowToolPropValues;
    Application.QueueAsyncCall(@FocusToolTextAsync, 0);       // (ready to type the next one, once what follows the placement has refreshed the boxes)
  end;
end;

{ ===========================================================================
  TfrmMain.SheetTabChange  (procedure)
  Parameters:
    Sender: TObject - the tab control
  Notes:
    Event handler: another sheet tab was chosen, so show that sheet. The last tab, "+", instead
    keeps the current sheet shown and adds a new one. Nothing is done when the tab chosen is the
    sheet already shown (the tabs were only rebuilt).
  =========================================================================== }
procedure TfrmMain.SheetTabChange(Sender: TObject);
begin
  if FDesign = nil then
    Exit;
  if tcSheetTabs.TabIndex >= FDesign.SheetCount then
  begin
    { the "+" tab was chosen: keep showing the current sheet and add a new one }
    tcSheetTabs.TabIndex := FView.SheetIndex;
    Application.QueueAsyncCall(@AddSheetFromTab, 0);
    Exit;
  end;
  if tcSheetTabs.TabIndex = FView.SheetIndex then
    Exit;      // already showing it (the tabs were just rebuilt)
  FView.SetSheetIndex(tcSheetTabs.TabIndex);
  QueueSheetTabRefresh;      // the tabs are made again, so the blue triangle is asked for again (see SheetTabImage)
  UpdatePaperStatus;
  UpdateRibbonState;
end;

{ ===========================================================================
  TfrmMain.MakeSheetTabMarks  (procedure)
  Parameters:  none
  Notes:
    The pictures a sheet tab can carry are in frmSharedControls.ilSheetTabs, made at design
    time, 14 x 14: number 0 is the arrow of the sheet the view is on (drawn in the designer, so
    it can be changed there) and number 1 a picture with nothing in it for the other tabs, so no
    tab changes width when the sheet changes. A missing number 1 is made here (transparent
    colour fuchsia, with one almost invisible pixel, because a picture that holds nothing but
    the transparent colour came out black); a missing arrow is made as a blue triangle. Gives
    the tabs the list.
  =========================================================================== }
procedure TfrmMain.MakeSheetTabMarks;
var
  L: TImageList;
  B: TBitmap;
  k: Integer;
begin
  L := frmSharedControls.ilSheetTabs;
  for k := L.Count to 0 do      { only the arrow is needed: the other tabs have no picture }
  begin
    B := TBitmap.Create;
    try
      B.SetSize(14, 14);
      B.Canvas.Brush.Color := clFuchsia;      { the transparent colour: the brush fills the picture, the pen would not }
      B.Canvas.Pen.Color := clFuchsia;
      B.Canvas.FillRect(0, 0, 14, 14);
      if k = 0 then
      begin
        B.Canvas.Brush.Color := TColor($D77800);      { blue (RGB 0, 120, 215) }
        B.Canvas.Pen.Color := TColor($D77800);
        B.Canvas.Polygon([Point(2, 1), Point(12, 7), Point(2, 13)]);
      end
      else
        B.Canvas.Pixels[0, 0] := TColor($F0F0F0);      { one almost invisible pixel: a picture that is only the transparent colour is not made transparent }
      L.AddMasked(B, clFuchsia);
    finally
      B.Free;
    end;
  end;
  tcSheetTabs.Images := L;
end;

{ ===========================================================================
  TfrmMain.SheetTabImage  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    TabIndex: Integer - whole number
    var ImageIndex: Integer - whole number (in/out: changed by the call)
  Notes:
    The tab of the sheet the view is on carries the arrow (0), every other tab none (-1: a tab
    without a picture takes no room for one, so only the current tab is wider). The tab control
    (Windows) asks for this only when it makes the tab, never again, and the sheet being shown
    is the view's: so the tabs are made again after a change of sheet (QueueSheetTabRefresh).
    The tabs cannot be drawn in another colour or in bold one by one (the tab control is the
    system's own), so this is what shows the current sheet.
  =========================================================================== }
procedure TfrmMain.SheetTabImage(Sender: TObject; TabIndex: Integer; var ImageIndex: Integer);
begin
  if (FDesign <> nil) and (TabIndex >= FDesign.SheetCount) then
    ImageIndex := -1
  else if (FView <> nil) and (TabIndex = FView.SheetIndex) then
    ImageIndex := 0
  else
    ImageIndex := -1;      { no picture at all, so the tab takes no room for one }
end;

procedure TfrmMain.rpSheetSheetsClick(Sender: TObject);
begin

end;

procedure TfrmMain.Panel1Click(Sender: TObject);
begin

end;

{ ===========================================================================
  TfrmMain.QueueSheetTabRefresh  (procedure)
  Parameters:  none
  Notes:
    Has the sheet tabs made again (RefreshSheetTabs) once the event that is running has
    finished, so the arrow is on the tab of the sheet now shown. Asking twice before it happens
    is one rebuild.
  =========================================================================== }
procedure TfrmMain.QueueSheetTabRefresh;
begin
  if FTabRefreshQueued then
    Exit;
  FTabRefreshQueued := True;
  Application.QueueAsyncCall(@RefreshSheetTabs, 0);
end;

{ ===========================================================================
  TfrmMain.RefreshSheetTabs  (procedure)
  Parameters:
    Data: PtrInt
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfrmMain.RefreshSheetTabs(Data: PtrInt);
begin
  FTabRefreshQueued := False;
  if (FDesign <> nil) and (FView <> nil) then
    RebuildSheetTabs;
end;

{ ===========================================================================
  TfrmMain.tcSheetTabsMouseDown  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    Button: TMouseButton - which mouse button
    Shift: TShiftState - modifier keys held down
    X: Integer - horizontal position or value
    Y: Integer - vertical position or value
  Notes:
    A right click on a sheet's tab first makes that sheet the current one, so the commands of
    the pop-up menu (pmSheetTabs, made at design time) act on the sheet that was clicked. The
    "+" tab and the empty space beside the tabs leave the current sheet as it is.
  =========================================================================== }
procedure TfrmMain.tcSheetTabsMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbRight then
    SheetTabRightClick(tcSheetTabs.IndexOfTabAt(X, Y));
end;

{ ===========================================================================
  TfrmMain.SheetTabRightClick  (procedure)
  Parameters:
    Index: Integer - zero-based index
  Notes:
    Makes the sheet of that tab the current one; not the "+" tab, nothing, or a tab already
    current.
  =========================================================================== }
procedure TfrmMain.SheetTabRightClick(Index: Integer);
begin
  if (FDesign <> nil) and (Index >= 0) and (Index < FDesign.SheetCount) and (Index <> tcSheetTabs.TabIndex) then
  begin
    tcSheetTabs.TabIndex := Index;
    SheetTabChange(tcSheetTabs);
  end;
end;

{ ===========================================================================
  TfrmMain.pmSheetTabsPopup  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The sheet tabs' menu is opening: the sheets of a symbol are its parts, so nothing changes
    them here; Delete needs a second sheet, Move Sheet left / right a neighbour on that side,
    and Add hierarchical symbol is enabled as in the Sheet menu.
  =========================================================================== }
procedure TfrmMain.pmSheetTabsPopup(Sender: TObject);
var
  Ok: Boolean;
  n, i: Integer;
begin
  Ok := (FDesign <> nil) and (not IsSymbolDoc);
  n := 0;
  if FDesign <> nil then
    n := FDesign.SheetCount;
  i := tcSheetTabs.TabIndex;
  pmTabInsert.Enabled := Ok;
  pmTabDelete.Enabled := Ok and (n > 1);
  pmTabRename.Enabled := Ok and (i >= 0) and (i < n);
  pmTabMoveLeft.Enabled := Ok and (i > 0);
  pmTabMoveRight.Enabled := Ok and (i >= 0) and (i < n - 1);
  HierarchyMenuOpen(Sender);
  pmTabHier.Enabled := mAddHierSymbol.Enabled;
end;

{ ===========================================================================
  TfrmMain.AddSheetFromTab  (procedure)
  Parameters:
    Data: PtrInt - unused
  Notes:
    Adds a sheet (queued from the sheet tabs' change event, because the tabs are rebuilt by
    adding one) when the + tab was chosen.
  =========================================================================== }
procedure TfrmMain.AddSheetFromTab(Data: PtrInt);
begin
  DoAddSheet(nil);
end;

{ ===========================================================================
  TfrmMain.RibbonTabsPaint  (procedure)
  Parameters:
    Sender: TObject - the paint box
  Notes:
    Paints the ribbon tab strip: the header color as background, each page caption as a tab, the
    active tab highlighted and the one under the mouse in the hover color, all from the current
    theme.
  =========================================================================== }
procedure TfrmMain.RibbonTabsPaint(Sender: TObject);
begin
  FRibbonTabs.Paint;
end;

{ ===========================================================================
  TfrmMain.RibbonTabsMouseMove  (procedure)
  Parameters:
    Sender: TObject - the paint box
    Shift: TShiftState - modifier keys
    X: Integer - x in the strip
    Y: Integer - y in the strip
  Notes:
    Remembers which tab the mouse is over and repaints the strip when that changes.
  =========================================================================== }
procedure TfrmMain.RibbonTabsMouseMove(Sender: TObject; Shift: TShiftState; X,
  Y: Integer);
begin
  FRibbonTabs.MouseMove(X, Y);
end;

{ ===========================================================================
  TfrmMain.RibbonTabsMouseLeave  (procedure)
  Parameters:
    Sender: TObject - the paint box
  Notes:
    The mouse left the tab strip: no tab is hot any more.
  =========================================================================== }
procedure TfrmMain.RibbonTabsMouseLeave(Sender: TObject);
begin
  FRibbonTabs.MouseLeave;
end;

{ ===========================================================================
  TfrmMain.RibbonTabsMouseDown  (procedure)
  Parameters:
    Sender: TObject - the paint box
    Button: TMouseButton - which button
    Shift: TShiftState - modifier keys
    X: Integer - x in the strip
    Y: Integer - y in the strip
  Notes:
    A left click on a tab makes that ribbon page the active one.
  =========================================================================== }
procedure TfrmMain.RibbonTabsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FRibbonTabs.MouseDown(Button, X, Y);
end;

{ ===========================================================================
  TfrmMain.ChooseRibbonTab  (procedure)
  Parameters:
    const ATitle: String - text
  Notes:
    What a click on a ribbon tab does (scripts use it too): brings that page forward. Choosing a
    tab other than Properties by hand ends the automatic switch of ViewSelection, so deselecting
    does not move the ribbon from where the person put it.
  =========================================================================== }
procedure TfrmMain.ChooseRibbonTab(const ATitle: String);
begin
  if not SameText(ATitle, PROPS_TAB) then
    FTabBeforeProps := '';
  ShowRibbonTab(ATitle);
end;

{ ===========================================================================
  TfrmMain.RibbonPageChange  (procedure)
  Parameters:
    Sender: TObject - the page control
  Notes:
    The active ribbon page changed, so repaint the tab strip to highlight it.
  =========================================================================== }
procedure TfrmMain.RibbonPageChange(Sender: TObject);
begin
  pbRibbonDisplay.Invalidate;
end;

{ ===========================================================================
  TfrmMain.BuildContextMenu  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    TPopupMenu
  Notes:
    TinyCAD's pop-up menu of the sheet. The commands of every object are the items of pmSheet in
    the designer (captions, keys, order); what depends on the object chosen is made here and
    comes first and a separator follows it - Add handle, Delete handle, Free line, Arc in, Arc
    out and Curve for a polygon (they act on the side nearest to P), Make horizontal and Make
    vertical for a line, wire or bus (the end nearer the click stays), Reload symbol from design
    and Open design for a placed design, Replace Symbol... for a placed symbol - then Undo,
    Redo, Z-Order, Cut, Copy, Paste, Duplicate, Select All, Select All Alike, Delete, Rotate
    Left, Rotate Right, Flip, Zoom In and Zoom Out, with the keys that do the same (the menu
    only shows them). Differences from TinyCAD: the keys are those this program already uses
    (Duplicate is Ctrl+U, Rotate Left Ctrl+L, Rotate Right Ctrl+R); the commands that need a
    selection are dimmed without one.
  =========================================================================== }
function TfrmMain.BuildContextMenu(const P: TDPoint): TPopupMenu;
var
  Sel, Any, Poly, Line, Hier, Sym: Boolean;
begin
  FContextPoint := P;
  { what depends on the object: the items are in the form file and are shown only for that kind of object }
  Poly := FView.PolygonAt(P);
  Line := FView.SelectedLine <> nil;
  Hier := SelectedHierarchical <> nil;
  Sym := (FView.SelectedSymbol <> nil) and (not IsSymbolDoc) and (not Hier);
  pmSheetAddHandle.Visible := Poly;
  pmSheetDelHandle.Visible := Poly;
  pmSheetPolySep1.Visible := Poly;
  pmSheetFreeLine.Visible := Poly;
  pmSheetArcIn.Visible := Poly;
  pmSheetArcOut.Visible := Poly;
  pmSheetCurve.Visible := Poly;
  pmSheetPolySep2.Visible := Poly;
  pmSheetWireCut.Visible := Line and FView.WireCanCut(P);
  pmSheetMakeHoriz.Visible := Line;
  pmSheetMakeVert.Visible := Line;
  pmSheetLineSep.Visible := Line;
  pmSheetReloadHier.Visible := Hier;
  pmSheetOpenHier.Visible := Hier;
  pmSheetHierSep.Visible := Hier;
  pmSheetReplaceSym.Visible := Sym;
  BuildRungMenu(Sym);
  pmSheetRungRef.Visible := Sym and (FView.SelectedSymbol.GetRef <> '');
  pmSheetSymSep.Visible := Sym;
  { the commands of every object are the items of pmSheet; here only what can be done now is set }
  Sel := FView.SelectedCount > 0;
  Any := (FView.Sheet <> nil) and (FView.Sheet.Drawing.Count > 0);
  pmSheetUndo.Enabled := (FView.Undo <> nil) and FView.Undo.CanUndo;
  pmSheetRedo.Enabled := (FView.Undo <> nil) and FView.Undo.CanRedo;
  pmSheetZOrder.Enabled := Sel;
  pmSheetBringFront.Enabled := Sel;
  pmSheetSendBack.Enabled := Sel;
  AlignMenuOpen;
  pmSheetCut.Enabled := Sel;
  pmSheetCopy.Enabled := Sel;
  pmSheetPaste.Enabled := FView.ClipboardHasDrawing;
  pmSheetDuplicate.Enabled := Sel;
  pmSheetSelectAll.Enabled := Any;
  pmSheetSelectAllAlike.Enabled := Sel;
  pmSheetDelete.Enabled := Sel;
  pmSheetRotateLeft.Enabled := Sel;
  pmSheetRotateRight.Enabled := Sel;
  pmSheetFlip.Enabled := Sel;
  pmSheetZoomIn.Enabled := FView.Sheet <> nil;
  pmSheetZoomOut.Enabled := FView.Sheet <> nil;
  Result := pmSheet;
end;

{ ===========================================================================
  TfrmMain.ContextMenuNow  (function)
  Parameters:  none
  Returns:
    TPopupMenu
  Notes:
    For tests: the menu whose items a script lists and chooses.
  =========================================================================== }
function TfrmMain.ContextMenuNow: TPopupMenu;
begin
  Result := pmSheet;
end;

{ ===========================================================================
  TfrmMain.ViewContext  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    X: Integer - horizontal position or value
    Y: Integer - vertical position or value
    const P: TDPoint - a point, in design units
  Notes:
    View event: a right click on the sheet with nothing being drawn. The object under it has
    been chosen; shows the menu of BuildContextMenu there.
  =========================================================================== }
procedure TfrmMain.ViewContext(Sender: TObject; X, Y: Integer; const P: TDPoint);
var
  Scr: TPoint;
begin
  if FView.Sheet = nil then
    Exit;
  BuildContextMenu(P);
  Scr := FView.ClientToScreen(Point(X, Y));
  pmSheet.PopUp(Scr.x, Scr.y);
end;

{ ===========================================================================
  TfrmMain.PolyDrawMenuClick  (procedure)
  Parameters:
    Sender: TObject - the chosen item of the Polygon tool's menu (pmPolyDraw)
  Notes:
    Hands the choice to the view that opened the menu (the one now shown).
  =========================================================================== }
procedure TfrmMain.PolyDrawMenuClick(Sender: TObject);
begin
  FView.DrawMenuClick(Sender);
end;

{ ===========================================================================
  TfrmMain.ArcDrawMenuClick  (procedure)
  Parameters:
    Sender: TObject - the chosen item of the Arc tool's menu (pmArcDraw)
  Notes:
    Hands the choice to the view that opened the menu (the one now shown).
  =========================================================================== }
procedure TfrmMain.ArcDrawMenuClick(Sender: TObject);
begin
  FView.ArcMenuClick(Sender);
end;

{ ===========================================================================
  TfrmMain.ContextPolyClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Menu handler: does a polygon command (handle or kind of side) at the point where the menu
    was opened, on the side nearest to it.
  =========================================================================== }
procedure TfrmMain.ContextPolyClick(Sender: TObject);
begin
  FView.PolygonAction(TPolyAction((Sender as TMenuItem).Tag), FContextPoint);
end;

{ ===========================================================================
  TfrmMain.ContextLineClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Menu handler: straightens the chosen line, wire or bus about the point where the menu was
    opened.
  =========================================================================== }
procedure TfrmMain.ContextLineClick(Sender: TObject);
begin
  FView.LineMakeStraight((Sender as TMenuItem).Tag = 1, FContextPoint);
end;

{ ===========================================================================
  TfrmMain.BuildRungMenu  (procedure)
  Parameters:
    Sym: Boolean - a placed symbol is the chosen object
  Notes:
    The Rung item of the sheet's pop-up menu: shown for a symbol that is inside the rung grid and either spans several rungs or has a rung chosen. Its items are Automatic and one for each
    rung the symbol's connection points are in (made here, their Tag is the rung number); the one in use is ticked.
  =========================================================================== }
procedure TfrmMain.BuildRungMenu(Sym: Boolean);
var
  Info: TRungInfo;
  i: Integer;
  M: TMenuItem;
begin
  while pmSheetRung.Count > 2 do
    pmSheetRung.Delete(2);
  pmSheetRung.Visible := False;
  if (not Sym) or (not FView.SymbolRung(Info)) or ((Length(Info.Candidates) < 2) and (not Info.Overridden)) then
    Exit;
  pmSheetRungAuto.Tag := 0;
  pmSheetRungAuto.Checked := not Info.Overridden;
  for i := 0 to High(Info.Candidates) do
  begin
    M := TMenuItem.Create(pmSheetRung);
    M.Caption := IntToStr(Info.Candidates[i]);
    M.Tag := Info.Candidates[i];
    M.RadioItem := True;
    M.Checked := Info.Overridden and (Info.Number = Info.Candidates[i]);
    M.OnClick := @ContextRungClick;
    pmSheetRung.Add(M);
  end;
  pmSheetRung.Visible := True;
end;

{ ===========================================================================
  TfrmMain.ContextRungClick  (procedure)
  Parameters:
    Sender: TObject - the chosen item of the Rung menu
  Notes:
    Keeps the rung chosen (its Tag) on the symbol, or 0 for Automatic.
  =========================================================================== }
procedure TfrmMain.ContextRungClick(Sender: TObject);
begin
  FView.SetSymbolRung((Sender as TMenuItem).Tag);
end;

{ ===========================================================================
  TfrmMain.ContextRungRefClick  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Add Rung Reference: see TSchematicView.AddRungReference.
  =========================================================================== }
procedure TfrmMain.ContextRungRefClick(Sender: TObject);
begin
  FView.AddRungReference;
end;

{ ===========================================================================
  TfrmMain.ContextWireCutClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Menu handler: cuts the chosen wire in two at the point where the menu was opened.
  =========================================================================== }
procedure TfrmMain.ContextWireCutClick(Sender: TObject);
begin
  FView.WireCutAt(FContextPoint);
end;

{ ===========================================================================
  TfrmMain.ReplaceSymbolWith  (function)
  Parameters:
    LibIndex: Integer - whole number
    SetIndex: Integer - whole number
    RecIndex: Integer - whole number
    KeepFields: Boolean - flag
    out Msg: String - the message (out: set by the call)
  Returns:
    Boolean
  Notes:
    Replace Symbol: the symbol chosen on the sheet is swapped for the one in the library, as one
    undo step, with the first pin where it was (TDrawMethod.ReplaceSymbol). The name becomes the
    new symbol's; a reference with no number yet takes the new symbol's letters, a numbered one
    stays; the other fields stay as they were when KeepFields is True.
  =========================================================================== }
function TfrmMain.ReplaceSymbolWith(LibIndex, SetIndex, RecIndex: Integer; KeepFields: Boolean; out Msg: String): Boolean;
var
  Lib: TSymbolLibrary;
  Sym: TDesignFileSymbol;
  M: TDrawMethod;
  OldId, NewId: Integer;
begin
  Result := False;
  Msg := '';
  M := FView.SelectedSymbol;
  if M = nil then
  begin
    Msg := rsChooseOneSymbolOnThe;
    Exit;
  end;
  if (LibIndex < 0) or (LibIndex >= frameLibraryPanel.LibCount) then
  begin
    Msg := rsChooseTheNewSymbolIn;
    Exit;
  end;
  Lib := frameLibraryPanel.LibAt(LibIndex);
  if (SetIndex < 0) or (SetIndex >= Lib.SetCount) or (RecIndex < 0) or (RecIndex >= Lib.Sets[SetIndex].RecordCount) then
  begin
    Msg := rsChooseTheNewSymbolIn;
    Exit;
  end;
  Sym := Lib.GetDesignSymbol(FView.Sheet, Lib.Sets[SetIndex], RecIndex);
  if Sym = nil then
  begin
    Msg := rsThatSymbolCouldNotBe;
    Exit;
  end;
  FView.BeginChange(rsReplaceSymbol);
  OldId := M.SymbolId;
  NewId := FView.Sheet.Options.AddSymbol(Sym);
  M.ReplaceSymbol(OldId, NewId, KeepFields);
  { the name is the new symbol's, and a reference that has no number yet (U?) takes the new symbol's letters; a numbered one (R5) is kept }
  M.Fields[FIELD_NAME].Value := Lib.Sets[SetIndex].Records[RecIndex].Name;
  if Pos('?', M.GetRef) > 0 then
    M.Fields[FIELD_REF].Value := Lib.Sets[SetIndex].Records[RecIndex].Reference;
  M.UpdateLayout;
  FView.CommitChange(True);
  Msg := Format(rsReplacedWith, [Lib.Sets[SetIndex].Records[RecIndex].Name]);
  Result := True;
end;

{ ===========================================================================
  TfrmMain.DoReplaceSymbol  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Menu handler of Replace Symbol...: the new symbol is the one chosen in the library list; the
    person is asked whether the field values of the old symbol are kept (Yes) or the new
    symbol's own are used (No).
  =========================================================================== }
procedure TfrmMain.DoReplaceSymbol(Sender: TObject);
var
  Li, Si, Ri, Ans: Integer;
  Msg, NewName: String;
begin
  Li := frameLibraryPanel.SelectedLibIndex;
  Si := frameLibraryPanel.SelectedSetIndex;
  Ri := frameLibraryPanel.SelectedRecIndex;
  if (Li < 0) or (Si < 0) or (Ri < 0) then
  begin
    ShowMessage(rsChooseTheNewSymbolIn2);
    Exit;
  end;
  NewName := frameLibraryPanel.LibAt(Li).Sets[Si].Records[Ri].Name;
  Ans := MessageDlg(rsReplaceSymbol2, Format(rsReplaceTheSymbolWithYes, [NewName]), mtConfirmation, [mbYes, mbNo, mbCancel], 0);
  if Ans = mrCancel then
    Exit;
  if not ReplaceSymbolWith(Li, Si, Ri, Ans = mrYes, Msg) then
    ShowMessage(Msg)
  else
    sbMainBar.Panels[0].Text := Msg;
end;

{ ===========================================================================
  TfrmMain.PartsWarningAccepted  (function)
  Parameters:  none
  Returns:
    Boolean - True when the part may be placed
  Notes:
    The warning before the first part of a parts library is placed: a design with parts can no longer be opened correctly in TinyCAD. It is shown once per run
    and not at all once the person ticked "Do not show this again" (kept in the settings). Cancel places nothing.
  =========================================================================== }
function TfrmMain.PartsWarningAccepted: Boolean;
var
  TD: TTaskDialog;
begin
  if ProgramSettings.PartsWarningOff or FPartsWarned then
    Exit(True);
  case FPartsWarnMode of
    1: begin
      FPartsWarned := True;
      Exit(True);
    end;
    2: Exit(False);
  end;
  TD := TTaskDialog.Create(Self);
  try
    TD.Caption := lAppName;
    TD.Title := rsThisDesignWillNoLonger;
    TD.Text := rsPartsFromAPartsLibrary;
    TD.MainIcon := tdiWarning;
    TD.CommonButtons := [tcbOk, tcbCancel];
    TD.DefaultButton := tcbCancel;
    TD.VerificationText := rsDoNotShowThisAgain;
    Result := TD.Execute and (TD.ModalResult = mrOk);
    if Result then
    begin
      FPartsWarned := True;
      if tfVerificationFlagChecked in TD.Flags then
      begin
        ProgramSettings.PartsWarningOff := True;
        SaveSettings;
      end;
    end;
  finally
    TD.Free;
  end;
end;

{ ===========================================================================
  TfrmMain.PlacePart  (function)
  Parameters:
    PartIndex: Integer - the part in the open parts library
  Returns:
    String - 'placed', 'refused' (the warning was answered No), 'nosheet', 'blocked' (a library symbol is being edited) or 'nosymbol' (the part has no symbol)
  Notes:
    Starts placing a generic part of the Parts tab, as LibPlace does for a symbol: the symbol XML of the part is read by the same loader as a library symbol, with the
    part's name and reference letters, and the part's GUID and the library's GUID are put on the symbol so the placed part can find its part again.
  =========================================================================== }
function TfrmMain.PlacePart(PartIndex: Integer): String;
var
  PL: TPartsLibrary;
  Xml: String;
begin
  PL := frameLibraryPanel.PartsLibrary;
  if (PL = nil) or (PartIndex < 0) or (PartIndex >= PL.PartCount) then
    Exit('nosymbol');
  if FView.Sheet = nil then
    Exit('nosheet');
  if FView.Sheet.Options.EditLibrary then
  begin
    sbMainBar.Panels[0].Text := rsOtherSymbolsCannotBePlaced;
    Exit('blocked');
  end;
  Xml := PL.SymbolXml(PL.Parts[PartIndex].ID);
  if Xml = '' then
  begin
    sbMainBar.Panels[0].Text := rsThatPartHasNoSymbol;
    Exit('nosymbol');
  end;
  if not PartsWarningAccepted then
    Exit('refused');
  Result := BeginPlacePart(PL, PartIndex, Xml, '', PL.PartCopyOf(PartIndex));
end;

{ ===========================================================================
  TfrmMain.BeginPlacePart  (function)
  Parameters:
    PL: TPartsLibrary - the library
    PartIndex: Integer - the part
    const Xml: String - the symbol drawing to place
    const Ref: String - the reference to give; '' = the part's reference letters followed by ?
    const Copy: TPartCopy - the part data the placed symbol keeps (PartCopyOf, with what it shows set by the caller if different)
  Returns:
    String - 'placed' or 'nosymbol' (the drawing could not be read)
  Notes:
    Shared by PlacePart and InsertContactOf: makes the symbol from the drawing with the part's name and description and puts it on the cursor to be put down.
  =========================================================================== }
function TfrmMain.BeginPlacePart(PL: TPartsLibrary; PartIndex: Integer; const Xml, Ref: String; const Copy: TPartCopy): String;
var
  Sym: TDesignFileSymbol;
  Id: Integer;
  M: TDrawMethod;
begin
  Sym := TDesignFileSymbol.Create(FView.Sheet.Options);
  Sym.Name := PL.Parts[PartIndex].Name;
  Sym.Description := PL.Parts[PartIndex].Description;
  if Ref <> '' then
    Sym.Reference := Ref
  else if PL.Parts[PartIndex].RefPrefix <> '' then
    Sym.Reference := PL.Parts[PartIndex].RefPrefix + '?'
  else
    Sym.Reference := 'U?';
  Sym.Ppp := 1;
  Sym.NameType := default_show;
  Sym.RefType := default_show;
  Sym.PartInfo := Copy;
  if not LoadLibrarySymbolBlob(FView.Sheet, Sym, Xml) then
  begin
    Sym.Free;
    ShowMessage(rsThatPartSSymbolCould);
    Exit('nosymbol');
  end;
  Id := FView.Sheet.Options.AddSymbol(Sym);
  M := TDrawMethod.CreateFromSymbol(FView.Sheet.Options, Id, 0);
  FView.BeginPlace(M);
  Result := 'placed';
end;

{ ===========================================================================
  TfrmMain.InsertContactOf  (function)
  Parameters:
    const Form: String - NO or NC wanted; '' = the next free contact of any form
    out Chosen: String - the name of the contact chosen (when 'placed')
  Returns:
    String - 'placed', 'nosheet', 'blocked', 'nosel' (no single part symbol is selected), 'nolibrary' (its parts library is not the open one), 'nosymbol' (the part has no
    contact symbol), 'none' (no free contact of that form is left) or 'refused' (the warning was answered No)
  Notes:
    Parts plan step 2. The selected symbol (the coil) names the device: its part and its reference. The contacts of the part that are already placed with that reference
    are looked for in the whole design (UContacts), the next unused one of the wanted form is taken, and the contact symbol of the part is put on the cursor with the
    coil's reference and the chosen contact in its part data. When none is left the status bar says so and nothing is placed.
  =========================================================================== }
function TfrmMain.InsertContactOf(const Form: String; out Chosen: String): String;
var
  PL: TPartsLibrary;
  M: TDrawMethod;
  Info: TPartCopy;
  Idx, K: Integer;
  Contacts: TContactInfoArray;
  Xml, Ref: String;
begin
  Chosen := '';
  if FView.Sheet = nil then
    Exit('nosheet');
  if FView.Sheet.Options.EditLibrary then
    Exit('blocked');
  M := FView.SelectedSymbol;
  if (M = nil) or not (M.GetSymbolData is TDesignFileSymbol) or TDesignFileSymbol(M.GetSymbolData).PartInfo.IsEmpty then
  begin
    sbMainBar.Panels[0].Text := rsSelectTheCoilFirst;
    Exit('nosel');
  end;
  Info := TDesignFileSymbol(M.GetSymbolData).PartInfo;
  Ref := M.GetRef;
  PL := frameLibraryPanel.PartsLibrary;
  if PL <> nil then
    Idx := PL.FindPart(Info.UID)
  else
    Idx := -1;
  if Idx < 0 then
  begin
    sbMainBar.Panels[0].Text := rsThePartsLibraryOfThat;
    Exit('nolibrary');
  end;
  Contacts := PL.ContactObjects(PL.Parts[Idx].ID);
  K := NextFreeContact(Contacts, UsedContactNames(FDesign, Info.UID, Ref), Form);
  if K < 0 then
  begin
    sbMainBar.Panels[0].Text := Format(rsHasNoFreeContact, [Ref, Form]);
    Exit('none');
  end;
  Xml := PL.ContactSymbolXml(PL.Parts[Idx].ID, Contacts[K].Form);
  if Xml = '' then
  begin
    sbMainBar.Panels[0].Text := rsThatPartHasNoContactSymbol;
    Exit('nosymbol');
  end;
  if not PartsWarningAccepted then
    Exit('refused');
  Info := PL.PartCopyOf(Idx);
  Info.ObjectName := Contacts[K].Name;
  Info.ObjectKind := 'Contact';
  Info.ObjectForm := Contacts[K].Form;
  Chosen := Contacts[K].Name;
  Result := BeginPlacePart(PL, Idx, Xml, Ref, Info);
end;

procedure TfrmMain.DoInsertContactNO(Sender: TObject);
var
  C: String;
begin
  InsertContactOf('NO', C);
end;

procedure TfrmMain.DoInsertContactNC(Sender: TObject);
var
  C: String;
begin
  InsertContactOf('NC', C);
end;

procedure TfrmMain.DoInsertContactFree(Sender: TObject);
var
  C: String;
begin
  InsertContactOf('', C);
end;

{ ===========================================================================
  TfrmMain.PartsFileChanged  (procedure)
  Parameters:
    Sender: TObject - the library panel
  Notes:
    A parts file was opened: its name is kept in the settings so the program opens it again next time.
  =========================================================================== }
procedure TfrmMain.PartsFileChanged(Sender: TObject);
begin
  if frameLibraryPanel.PartsLibrary <> nil then
    ProgramSettings.LastPartsFile := frameLibraryPanel.PartsLibrary.FileName
  else
    ProgramSettings.LastPartsFile := '';
  SaveSettings;
end;

{ ===========================================================================
  TfrmMain.ChooseProduct  (function)
  Returns:
    String - 'chosen', 'cancelled', 'noselection' (not exactly one placed generic part selected), 'nolibrary' (no parts file is open and none was opened), 'nopart' (the open
    library does not have the part) or 'noproduct' (a scripted answer named a product the part does not offer)
  Notes:
    Lets the person choose the product of the selected placed part from the open parts library (A2). With no library open the person is asked for a parts file first. The choice
    copies the product's GUID, manufacturer, model number and ratings into the placement and can be undone. The self-test script answers through ProductPickAnswer.
  =========================================================================== }
function TfrmMain.ChooseProduct: String;
var
  M: TDrawMethod;
  P: TDesignFileSymbol;
  PL: TPartsLibrary;
  Pi, Ix: Integer;
  Prods: TProductInfoArray;
  Dlg: TfrmProductPick;
  Ans: Boolean;
  Bar: Integer;
begin
  if (FView.SelectedCount <> 1) or (not (FView.SelectedObject(0) is TDrawMethod)) then
    Exit('noselection');
  M := TDrawMethod(FView.SelectedObject(0));
  P := PartOf(M);
  if P = nil then
    Exit('noselection');
  PL := frameLibraryPanel.PartsLibrary;
  if (PL = nil) and (FProductPickAnswer = '') and frameLibraryPanel.dlgPartsOpen.Execute then
  begin
    frameLibraryPanel.OpenPartsFile(frameLibraryPanel.dlgPartsOpen.FileName);
    PL := frameLibraryPanel.PartsLibrary;
  end;
  if PL = nil then
    Exit('nolibrary');
  Pi := PL.FindPart(P.PartInfo.UID);
  if Pi < 0 then
  begin
    sbMainBar.Panels[0].Text := rsTheOpenPartsLibraryDoes;
    Exit('nopart');
  end;
  Prods := PL.Products(PL.Parts[Pi].ID);
  Dlg := TfrmProductPick.CreateFor(Self, PL.Parts[Pi].Name, Prods, M.Product.MPN);
  try
    if FProductPickAnswer = '' then
      Ans := Dlg.ShowModal = mrOk
    else if FProductPickAnswer = 'cancel' then
      Ans := False
    else
    begin
      Bar := Pos('|', FProductPickAnswer);
      if (Bar = 0) or (not Dlg.SelectByName(Copy(FProductPickAnswer, 1, Bar - 1), Copy(FProductPickAnswer, Bar + 1, MaxInt))) then
        Exit('noproduct');
      Ans := True;
    end;
    Ix := Dlg.ChosenIndex;
  finally
    Dlg.Free;
  end;
  if (not Ans) or (Ix < 0) then
    Exit('cancelled');
  FView.BeginChange(rsChooseProduct);
  M.Product := PL.ProductChoiceOf(Prods[Ix].ID);
  FView.CommitChange(True);
  Result := 'chosen';
end;

{ ===========================================================================
  TfrmMain.HookSymbolFrame  (procedure)
  Parameters:
    AFrame: TfmSymbols - the symbol frame just made (for the tool or for the selection)
  Notes:
    Connects what the frame cannot apply by itself: the rotate button, the direction and mirror items of its menu, and the parameter list button.
  =========================================================================== }
procedure TfrmMain.HookSymbolFrame(AFrame: TfmSymbols);
begin
  AFrame.OnRotate := @SymbolRotate;
  AFrame.OnPickDirection := @SymbolPickDirection;
  AFrame.OnMirror := @SymbolMirror;
  AFrame.OnGetSymbol := @SymbolParameters;
  AFrame.OnParameterChange := @SymbolListChange;
  AFrame.OnAutoShowChange := @SymbolAutoShowChange;
  AFrame.AutoShow := FAutoShowParams;
end;

{ ===========================================================================
  TfrmMain.SymbolAutoShowChange  (procedure)
  Parameters:
    Sender: TObject - the symbol frame whose parameter button was clicked
  Notes:
    Keeps the state of the button (the frame is made again for every selection) and shows it on the frame of the tool or of the selection, whichever the other is.
  =========================================================================== }
procedure TfrmMain.SymbolAutoShowChange(Sender: TObject);
begin
  FAutoShowParams := (Sender as TfmSymbols).AutoShow;
  if FToolFrame is TfmSymbols then
    TfmSymbols(FToolFrame).AutoShow := FAutoShowParams;
  if FPropFrame is TfmSymbols then
    TfmSymbols(FPropFrame).AutoShow := FAutoShowParams;
end;

{ ===========================================================================
  TfrmMain.AutoShowSymbolList  (procedure)
  Parameters:
    Data: PtrInt - not used
  Notes:
    Run a moment after the Properties panel was rebuilt for a selected symbol, when the parameter button is on: drops the parameter list down.
  =========================================================================== }
procedure TfrmMain.AutoShowSymbolList(Data: PtrInt);
begin
  if FAutoShowParams and (FView <> nil) and (FView.SelectedCount > 0) and (FPropFrame is TfmSymbols) then
  begin
    { a symbol that is pressed on is selected while the button is still down: a list opened now would sit under the pointer and take the release,
      leaving the sheet in a drag (the symbol following the pointer). It opens when the button is let go. }
    if FView.DragMode <> 0 then
      FAutoShowWait := True
    else
    begin
      { the list drops from the parameter button that is on the screen: the one of the selection's panel, or, when that panel is on a ribbon tab that is not showing
        (a symbol text has just been placed with the draw tool still on), the one of the tool's panel }
      if TfmSymbols(FPropFrame).sbParameterList.IsVisible then
        TfmSymbols(FPropFrame).ShowParameters
      else if (FToolFrame is TfmSymbols) and TfmSymbols(FToolFrame).sbParameterList.IsVisible then
        TfmSymbols(FPropFrame).ShowParameters(TfmSymbols(FToolFrame).sbParameterList);
    end;
  end;
end;

{ ===========================================================================
  TfrmMain.ViewDragEnd  (procedure)
  Parameters:
    Sender: TObject - the view
  Notes:
    View event: a mouse button was let go. A parameter list that was waiting for that (AutoShowSymbolList) opens now.
  =========================================================================== }
procedure TfrmMain.ViewDragEnd(Sender: TObject);
begin
  if FAutoShowWait then
  begin
    FAutoShowWait := False;
    Application.QueueAsyncCall(@AutoShowSymbolList, 0);
  end;
end;

{ ===========================================================================
  TfrmMain.SymbolFrameTag  (function)
  Parameters:
    AFrame: TObject - a symbol frame, or one of its controls
  Returns:
    Integer - TOOLPROP_BASE when it is the frame of the tool (the symbol being placed), 0 for the frame of the selection
  =========================================================================== }
function TfrmMain.SymbolFrameTag(AFrame: TObject): Integer;
begin
  if (AFrame is TComponent) and ((AFrame = FToolFrame) or (TComponent(AFrame).Owner = FToolFrame)) and (FToolFrame <> nil) then
    Result := TOOLPROP_BASE
  else
    Result := 0;
end;

{ ===========================================================================
  TfrmMain.SymbolValue  (function)
  Parameters:
    ATag: Integer - TOOLPROP_BASE for the symbol being placed, else the selection
    const AName: String - the property
  Returns:
    String - its value for the tool, or the value the selection shares ('' when they differ)
  =========================================================================== }
function TfrmMain.SymbolValue(ATag: Integer; const AName: String): String;
var
  Mixed: Boolean;
begin
  if ATag >= TOOLPROP_BASE then
    Result := FView.ToolPropValue(FToolOf, AName)
  else
  begin
    Result := CommonValue(FView.SelectedList, AName, Mixed);
    if Mixed then
      Result := '';
  end;
end;

{ ===========================================================================
  TfrmMain.SymbolTarget  (function)
  Parameters:
    ATag: Integer - TOOLPROP_BASE for the symbol being placed, else the selection
  Returns:
    TDrawMethod - the symbol the parameter list is for: the one being placed, or the single selected one; nil when there is none
  =========================================================================== }
function TfrmMain.SymbolTarget(ATag: Integer): TDrawMethod;
begin
  Result := nil;
  if ATag >= TOOLPROP_BASE then
    Result := FView.PlaceGhost
  else if (FView.SelectedCount = 1) and (FView.SelectedObject(0) is TDrawMethod) then
    Result := TDrawMethod(FView.SelectedObject(0));
end;

{ ===========================================================================
  TfrmMain.SymbolRotate  (procedure)
  Parameters:
    Sender: TObject - the symbol frame
  Notes:
    A click on the rotate button: the symbol turns to the next direction, Up, Right, Down, Left.
  =========================================================================== }
procedure TfrmMain.SymbolRotate(Sender: TObject);
var
  T: Integer;
  Cur: String;
begin
  if FUpdatingProps then
    Exit;
  T := SymbolFrameTag(Sender);
  Cur := SymbolValue(T, 'sym.dir');
  CommitNamed(T, 'sym.dir', ChoiceText(PropDirRotation, (ChoiceIndex(PropDirRotation, Cur) + 1) mod ChoiceCount(PropDirRotation)));
end;

{ ===========================================================================
  TfrmMain.SymbolPickDirection  (procedure)
  Parameters:
    Sender: TObject - the symbol frame
    ADir: Integer - 0 up, 1 right, 2 down, 3 left (the order of the menu)
  =========================================================================== }
procedure TfrmMain.SymbolPickDirection(Sender: TObject; ADir: Integer);
begin
  if FUpdatingProps then
    Exit;
  CommitNamed(SymbolFrameTag(Sender), 'sym.dir', ChoiceText(PropDirRotation, ADir));
end;

{ ===========================================================================
  TfrmMain.SymbolMirror  (procedure)
  Parameters:
    Sender: TObject - the symbol frame
  Notes:
    The Mirror item of the menu turns the mirroring over.
  =========================================================================== }
procedure TfrmMain.SymbolMirror(Sender: TObject);
var
  T: Integer;
begin
  if FUpdatingProps then
    Exit;
  T := SymbolFrameTag(Sender);
  CommitNamed(T, 'sym.mirror', IfThen(SymbolValue(T, 'sym.mirror') = '1', '0', '1'));
end;

{ ===========================================================================
  TfrmMain.ShowSymbolFrames  (procedure)
  Notes:
    Shows the direction and the mirroring of the symbol (being placed, or selected) in the menu and the hint of the symbol frames.
  =========================================================================== }
procedure TfrmMain.ShowSymbolFrames;
begin
  if (FToolFrame is TfmSymbols) and (FView <> nil) then
    TfmSymbols(FToolFrame).ShowDirection(SymbolValue(TOOLPROP_BASE, 'sym.dir'), SymbolValue(TOOLPROP_BASE, 'sym.mirror') = '1');
  if (FPropFrame is TfmSymbols) and (FView <> nil) then
    TfmSymbols(FPropFrame).ShowDirection(SymbolValue(0, 'sym.dir'), SymbolValue(0, 'sym.mirror') = '1');
end;

{ ===========================================================================
  TfrmMain.SymbolParameters  (function)
  Parameters:
    Sender: TObject - the symbol frame whose Parameters button was pressed
  Returns:
    TDrawMethod - the symbols whose parameters are listed: the one being placed (tool frame) or the selected symbols; empty, with a message, when there is none
  Notes:
    The frame drops the list down itself (TfmSymbols.ParametersClick); this only names the symbol.
  =========================================================================== }
function TfrmMain.SymbolParameters(Sender: TObject): TMethodArray;
var
  i: Integer;
begin
  SetLength(Result, 0);
  if SymbolFrameTag(Sender) >= TOOLPROP_BASE then
  begin
    if FView.PlaceGhost <> nil then
    begin
      SetLength(Result, 1);
      Result[0] := FView.PlaceGhost;
    end;
  end
  else
    for i := 0 to FView.SelectedCount - 1 do
      if FView.SelectedObject(i) is TDrawMethod then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := TDrawMethod(FView.SelectedObject(i));
      end;
  if Length(Result) = 0 then
    sbMainBar.Panels[0].Text := rsSelectASymbolToSee;
end;

{ ===========================================================================
  TfrmMain.SymbolListChange  (procedure)
  Parameters:
    Sender: TObject - the symbol frame
    ABefore: Boolean - the change is about to be made (else it was made)
  Notes:
    A selected symbol gets an undo step for a change of its parameters (the symbol being placed has none); after it the sheet is drawn again.
  =========================================================================== }
procedure TfrmMain.SymbolListChange(Sender: TObject; ABefore: Boolean);
var
  Tool: Boolean;
begin
  Tool := SymbolFrameTag(Sender) >= TOOLPROP_BASE;
  if ABefore then
  begin
    if not Tool then
      FView.BeginChange(rsSymbolParameters);
    Exit;
  end;
  if not Tool then
  begin
    FView.CommitChange(True);
    FModified := True;
    UpdateFormTitle;
  end;
  FView.Invalidate;
end;

{ ===========================================================================
  TfrmMain.SymbolFrameAct  (function)
  Parameters:
    ATool: Boolean - the frame of the tool (the symbol being placed) or of the selection
    const AAct: String - rotate, dir, mirror or state
    AArg: Integer - the direction for dir (0 up, 1 right, 2 down, 3 left)
  Returns:
    String - 'ok', or for state: dir=<name> mirror=<0|1> hint=<hint of the rotate button>; 'noframe' when the symbol frame is not shown
  Notes:
    For the self-test script: does to the symbol frame what a person does with the rotate button and its menu.
  =========================================================================== }
function TfrmMain.SymbolFrameAct(ATool: Boolean; const AAct: String; AArg: Integer): String;
var
  Fr: TFrame;
begin
  if ATool then
    Fr := FToolFrame
  else
    Fr := FPropFrame;
  if not (Fr is TfmSymbols) then
    Exit('noframe');
  Result := 'ok';
  with TfmSymbols(Fr) do
    if AAct = 'rotate' then
      sbRotateSymbol.OnClick(sbRotateSymbol)
    else if AAct = 'dir' then
      begin
        if (AArg = miUp.Tag) then
          miUp.Click
        else if AArg = miRight.Tag then
          miRight.Click
        else if AArg = miDown.Tag then
          miDown.Click
        else
          miLeft.Click;
      end
    else if AAct = 'mirror' then
      miMirror.Click
    else if AAct = 'state' then
      Result := 'dir=' + IfThen(miUp.Checked, 'Up', IfThen(miRight.Checked, 'Right', IfThen(miDown.Checked, 'Down', IfThen(miLeft.Checked, 'Left', '')))) +
        ' mirror=' + IntToStr(Ord(miMirror.Checked)) + ' hint=' + sbRotateSymbol.Hint;
end;

{ ===========================================================================
  TfrmMain.SymbolListAct  (function)
  Parameters:
    ATool: Boolean - the list of the symbol being placed or of the selected symbol
    const AAct: String - open, close, rows, click, type, enter, escape, add, delete, state
    const AArg: String - 'row col' for click, the text for type
  Returns:
    String - what happened
  Notes:
    For the self-test script: does to the parameter list what a person does: the Parameters button, a click on a cell, typing and Enter or Esc, Add and Delete.
  =========================================================================== }
function TfrmMain.SymbolListAct(ATool: Boolean; const AAct, AArg: String): String;
var
  Fr: TFrame;
  L: TfrmSymbolPropList;
  i, Sp: Integer;
begin
  Result := 'ok';
  if ATool then
    Fr := FToolFrame
  else
    Fr := FPropFrame;
  if not (Fr is TfmSymbols) then
    Exit('noframe');
  if AAct = 'open' then
  begin
    if TfmSymbols(Fr).ParameterList <> nil then
      TfmSymbols(Fr).ParameterList.ForgetClose;      { (a person waits longer than the 300 ms in which a click on the button would only have closed the list) }
    TfmSymbols(Fr).ShowParameters;
    L := TfmSymbols(Fr).ParameterList;
    Exit(IfThen((L <> nil) and L.Visible, 'open', 'closed'));
  end;
  if AAct = 'autoclick' then
  begin
    { a click on the left part of the parameter button: AutoCheck turns Checked over, then OnClick runs }
    if TfmSymbols(Fr).ParameterList <> nil then
      TfmSymbols(Fr).ParameterList.ForgetClose;
    TfmSymbols(Fr).sbParameterList.Checked := not TfmSymbols(Fr).sbParameterList.Checked;
    TfmSymbols(Fr).sbParameterList.OnClick(TfmSymbols(Fr).sbParameterList);
  end;
  if (AAct = 'autoclick') or (AAct = 'autostate') then
  begin
    L := TfmSymbols(Fr).ParameterList;
    Exit(IfThen(TfmSymbols(Fr).AutoShow, 'on', 'off') + ' ' + IfThen((L <> nil) and L.Visible, 'open', 'closed') + ' ' + IfThen(L = nil, 'nolist', 'list'));
  end;
  L := TfmSymbols(Fr).ParameterList;
  if L = nil then
    Exit('nolist');
  if AAct = 'close' then
    L.Close
  else if AAct = 'count' then
    Result := L.CountText
  else if AAct = 'size' then
  begin
    if AArg <> '' then
      L.ResizeTo(StrToInt(Copy(AArg, 1, Pos(' ', AArg) - 1)), StrToInt(Copy(AArg, Pos(' ', AArg) + 1, 9)));
    Result := IntToStr(L.Width) + 'x' + IntToStr(L.Height) + ' grid=' + IntToStr(L.grdParams.Width) + ' value=' + IntToStr(L.grdParams.ColWidths[2]) + ' client=' + IntToStr(L.ClientWidth) + 'x' + IntToStr(L.ClientHeight) + ' minw=' + IntToStr(L.Constraints.MinWidth) + ' bs=' + IntToStr(Ord(L.BorderStyle)) + ' labelTop=' + IntToStr(L.lblCount.Top) +
      ' gridTop=' + IntToStr(L.grdParams.Top);
  end
  else if AAct = 'rows' then
  begin
    Result := '';
    for i := 0 to L.RowCount - 1 do
      Result := Result + IfThen(i > 0, ' ## ', '') + L.RowText(i);
  end
  else if AAct = 'click' then
  begin
    Sp := Pos(' ', AArg);
    Result := L.ClickCell(StrToInt(Copy(AArg, 1, Sp - 1)), StrToInt(Copy(AArg, Sp + 1, 9)));
  end
  else if AAct = 'pos' then
  begin
    { where the list is (left, top) and where the parameter buttons it can drop from are (left and bottom, screen pixels): the selection's panel, then the tool's panel }
    Result := Format('list=%d,%d', [L.Left, L.Top]);
    Result := Result + Format(' button=%d,%d', [TfmSymbols(Fr).sbParameterList.ClientToScreen(Point(0, 0)).X, TfmSymbols(Fr).sbParameterList.ClientToScreen(Point(0, TfmSymbols(Fr).sbParameterList.Height)).Y]);
    if FToolFrame is TfmSymbols then
      Result := Result + Format(' toolbutton=%d,%d', [TfmSymbols(FToolFrame).sbParameterList.ClientToScreen(Point(0, 0)).X,
        TfmSymbols(FToolFrame).sbParameterList.ClientToScreen(Point(0, TfmSymbols(FToolFrame).sbParameterList.Height)).Y]);
  end
  else if AAct = 'stale' then
  begin
    Sp := Pos(' ', AArg);
    L.LateEntry(StrToInt(Copy(AArg, 1, Sp - 1)), 0, StringReplace(Copy(AArg, Sp + 1, MaxInt), '-', '', []));      // 'stale <row> -': the grid's late report of an empty editor for the name cell
  end
  else if AAct = 'text' then
    Result := L.EditText + '|focused=' + IntToStr(Ord(L.grdParams.EditorMode and (L.grdParams.Editor <> nil) and L.grdParams.Editor.Focused))
  else if AAct = 'type' then
    L.SetEditText(AArg)
  else if AAct = 'enter' then
    L.EndEdit(True)
  else if AAct = 'escape' then
  begin
    if L.Editing then
      L.EndEdit(False)
    else
      L.Close;
  end
  else if AAct = 'add' then
    L.AddParameter
  else if AAct = 'delete' then
    L.DeleteParameter
  else if AAct = 'state' then
    Result := 'visible=' + IntToStr(Ord(L.Visible)) + ' delete=' + IntToStr(Ord(L.DeleteEnabled)) + ' editing=' + IntToStr(Ord(L.Editing)) + ' rows=' + IntToStr(L.RowCount);
end;

{ ===========================================================================
  TfrmMain.PartPlace  (procedure)
  Parameters:
    Sender: TObject - the library panel
    PartIndex: Integer - the part chosen on the Parts tab
  Notes:
    Handler of OnPartPlace (a double click on a part): starts placing it. A message says why when it cannot be.
  =========================================================================== }
procedure TfrmMain.PartPlace(Sender: TObject; PartIndex: Integer);
begin
  if PlacePart(PartIndex) = 'nosheet' then
    ShowMessage(rsCreateOrOpenADocument);
end;

{ ===========================================================================
  TfrmMain.PlacePartRow  (function)
  Parameters:
    Row: Integer - the row of the Parts tab list
    Xmm, Ymm: Double - where the click that puts it down is, in millimetres
  Returns:
    String - what PlacePart returned
  Notes:
    For the self-test script: chooses the row, double clicks it (PlacePart) and clicks the sheet to put the part down.
  =========================================================================== }
function TfrmMain.PlacePartRow(Row: Integer; Xmm, Ymm: Double): String;
begin
  frameLibraryPanel.SelectPartRow(Row);
  Result := PlacePart(frameLibraryPanel.SelectedPartIndex);
  if Result = 'placed' then
    FView.ClickAt(FView.DesignToScreen(DPoint(Xmm * UNITS_PER_MM, Ymm * UNITS_PER_MM)).x,
                  FView.DesignToScreen(DPoint(Xmm * UNITS_PER_MM, Ymm * UNITS_PER_MM)).y, []);
end;

{ ===========================================================================
  TfrmMain.LibPlace  (procedure)
  Parameters:
    Sender: TObject - the panel
    Lib: TSymbolLibrary - the library
    SetIndex: Integer - which set in it
    RecIndex: Integer - which record in the set
  Notes:
    Library panel event: starts placing the chosen symbol on the current sheet.
  =========================================================================== }
procedure TfrmMain.LibPlace(Sender: TObject; Lib: TSymbolLibrary; SetIndex, RecIndex: Integer);
var
  Sym: TDesignFileSymbol;
  Id: Integer;
  M: TDrawMethod;
begin
  if FView.Sheet = nil then begin
    ShowMessage(rsCreateOrOpenADocument);
    Exit;
  end;
  if FView.Sheet.Options.EditLibrary then begin
    sbMainBar.Panels[0].Text := rsOtherSymbolsCannotBePlaced;
    Exit;
  end;
  Sym := Lib.GetDesignSymbol(FView.Sheet, Lib.Sets[SetIndex], RecIndex);
  if Sym = nil then begin
    ShowMessage(rsThatSymbolCouldNotBe);
    Exit;
  end;
  Id := FView.Sheet.Options.AddSymbol(Sym);
  M := TDrawMethod.CreateFromSymbol(FView.Sheet.Options, Id, 0);
  FView.BeginPlace(M);
end;

{ ===========================================================================
  TfrmMain.UpdateRibbonFromView  (procedure)
  Parameters:  none
  Notes:
    Shows the current sheet's settings in the details panel of the ribbon: Show rulers, the
    number of columns, the last row letter, Border and its margin (the counts only enabled with
    rulers on, the margin only with a border), and the Snap button. With no document open the
    panel is empty and disabled. Setting a control here does not write back to the sheet.
  =========================================================================== }
procedure TfrmMain.UpdateRibbonFromView;
var
  Dot: TFormatSettings;
  D: TDetails;
  Have: Boolean;
begin
  Dot := DefaultFormatSettings;
  Dot.DecimalSeparator := '.';
  Have := (FDesign <> nil) and (FView.Sheet <> nil);
  FUpdatingRibbon := True;       // (setting a check box in code fires its OnClick: that must not write back to the sheet)
  try
    sbSheetDetails.Enabled := Have;
    FDetailsDrop.cbSheetDetailsBorder.Enabled := Have;
    sbExtendedInfo.Enabled := Have;
    miExtendedInfo.Enabled := Have;
    miShowRulers.Enabled := Have;
    FDetailsDrop.cbSheetDetailsShowRuler.Enabled := Have;
    if not Have then
    begin
      sbExtendedInfo.Down := False;
      miExtendedInfo.Checked := false;
      miShowRulers.Checked := False;
      sbSheetDetails.Checked := False;
      FDetailsDrop.cbSheetDetailsShowRuler.Checked := False;
      FDetailsDrop.cbSheetDetailsBorder.Checked := False;
      FDetailsDrop.edSheetDetailsCols.Text := '';
      FDetailsDrop.edSheetDetailsRows.Text := '';
      FDetailsDrop.edSheetDetailsMargin.Text := '';
      FDetailsDrop.edSheetDetailsCols.Enabled := False;
      FDetailsDrop.edSheetDetailsRows.Enabled := False;
      FDetailsDrop.edSheetDetailsMargin.Enabled := False;
      sbViewGridSnapTo.Down := False;
      Exit;
    end;
    D := FView.Sheet.Details;
    sbViewGridSnapTo.Down := (FView.Sheet.Snap.GridSnap = 1);
    sbSheetDetails.Checked := D.HasRulers;
    miShowRulers.Checked := D.HasRulers;
    FDetailsDrop.cbSheetDetailsShowRuler.Checked := D.HasRulers;
    FDetailsDrop.edSheetDetailsCols.Text := IntToStr(D.HorizRulerSize);
    if (D.VertRulerSize >= 1) and (D.VertRulerSize <= 26) then
      FDetailsDrop.edSheetDetailsRows.Text := Chr(Ord('A') + D.VertRulerSize - 1)
    else
      FDetailsDrop.edSheetDetailsRows.Text := '';
    FDetailsDrop.cbSheetDetailsBorder.Checked := D.ShowBorder;
    sbExtendedInfo.Down := D.ExtendedInfo;
    miExtendedInfo.Checked := D.ExtendedInfo;
    FDetailsDrop.edSheetDetailsMargin.Text := FormatFloat('0.##', D.BorderMargin / UNITS_PER_MM, Dot);
    { the counts only matter with rulers on, the margin only with a border }
    FDetailsDrop.edSheetDetailsCols.Enabled := D.HasRulers;
    FDetailsDrop.edSheetDetailsRows.Enabled := D.HasRulers;
    FDetailsDrop.edSheetDetailsMargin.Enabled := D.ShowBorder;
  finally
    FUpdatingRibbon := False;
  end;
end;

{ ===========================================================================
  TfrmMain.DetailFor  (function)
  Parameters:
    Sender: TObject - the control
  Returns:
    TSheetDetail - the setting
  Notes:
    Which setting of the details panel a control stands for (the Show rulers box, the columns,
    rows or margin entry, or the Border box).
  =========================================================================== }
function TfrmMain.DetailFor(Sender: TObject): TSheetDetail;
begin
  if Sender = FDetailsDrop.edSheetDetailsCols then
    Result := sdCols
  else if Sender = FDetailsDrop.edSheetDetailsRows then
    Result := sdRows
  else if Sender = FDetailsDrop.edSheetDetailsMargin then
    Result := sdMargin
  else if Sender = FDetailsDrop.cbSheetDetailsBorder then
    Result := sdBorder
  else if Sender = sbExtendedInfo then
    Result := sdExtended
  else
    Result := sdRulers;
end;

{ one setting of the details panel is written to the current sheet, as one undo step, by the same rules as the
  Page frame page of the Design Details dialog; an entry that is refused is put back as the sheet has it }

{ ===========================================================================
  TfrmMain.ApplySheetDetail  (procedure)
  Parameters:
    What: TSheetDetail - which setting to apply
  Notes:
    Writes one setting of the details panel (Show rulers, columns, rows, Border or margin) to
    the current sheet as one undo step, by the same rules as the Page frame page of the Design
    Details dialog: a column count must be 1 to 26, the last row a letter A to Z, the margin a
    number of millimetres that fits the page. An entry that is refused leaves a message in the
    status bar and is put back as the sheet has it.
  =========================================================================== }
procedure TfrmMain.ApplySheetDetail(What: TSheetDetail);
var
  D: TDetails;
  DidChange: Boolean;
  H, V: Integer;
  M: Double;
  S: String;
  Dot: TFormatSettings;
begin
  if FUpdatingRibbon or (FDesign = nil) or (FView.Sheet = nil) then
    Exit;
  Dot := DefaultFormatSettings;
  Dot.DecimalSeparator := '.';
  D := FView.Sheet.Details;
  DidChange := False;
  case What of
    sdRulers: FView.BeginChange(rsRulers);
    sdCols: FView.BeginChange(rsRulerColumns);
    sdRows: FView.BeginChange(rsRulerRows);
    sdBorder: FView.BeginChange(rsBorder);
    sdMargin: FView.BeginChange(rsBorderMargin);
    sdExtended: FView.BeginChange(rsExtendedInformation);
  end;
  case What of
    sdExtended:
      if D.ExtendedInfo <> sbExtendedInfo.Down then
      begin
        D.ExtendedInfo := sbExtendedInfo.Down;
        DidChange := True;
      end;
    sdRulers:
      if D.HasRulers <> sbSheetDetails.Checked then
      begin
        D.HasRulers := sbSheetDetails.Checked;
        DidChange := True;
      end;
    sdCols:
      begin
        H := StrToIntDef(Trim(FDetailsDrop.edSheetDetailsCols.Text), 0);
        if (H >= 1) and (H <= 26) then
        begin
          if H <> D.HorizRulerSize then
          begin
            D.HorizRulerSize := H;
            DidChange := True;
          end;
        end
        else
          sbMainBar.Panels[0].Text := rsTheNumberOfColumnsMust;
      end;
    sdRows:
      begin
        V := 0;
        S := Trim(FDetailsDrop.edSheetDetailsRows.Text);
        if S <> '' then
          V := Ord(UpCase(S[1])) - Ord('A') + 1;
        if (V >= 1) and (V <= 26) then
        begin
          if V <> D.VertRulerSize then
          begin
            D.VertRulerSize := V;
            DidChange := True;
          end;
        end
        else
          sbMainBar.Panels[0].Text := rsTheLastRowMustBe;
      end;
    sdBorder:
      if D.ShowBorder <> FDetailsDrop.cbSheetDetailsBorder.Checked then
      begin
        D.ShowBorder := FDetailsDrop.cbSheetDetailsBorder.Checked;
        DidChange := True;
      end;
    sdMargin:
      begin
        S := StringReplace(Trim(FDetailsDrop.edSheetDetailsMargin.Text), ',', '.', []);
        if TryStrToFloat(S, M, Dot) and (M >= 0) and (M * UNITS_PER_MM * 2 < Min(D.PageWidth, D.PageHeight)) then
        begin
          if Abs(D.BorderMargin - M * UNITS_PER_MM) > 1e-9 then
          begin
            D.BorderMargin := M * UNITS_PER_MM;
            DidChange := True;
          end;
        end
        else
          sbMainBar.Panels[0].Text := rsTheBorderMarginMustBe;
      end;
  end;
  FView.CommitChange(DidChange);
  UpdateRibbonFromView;       // show what the sheet has now (which puts back an entry that was refused)
end;

{ ===========================================================================
  TfrmMain.DetailsFieldExit  (procedure)
  Parameters:
    Sender: TObject - the box
  Notes:
    Event handler: leaving a box of the details panel applies what was typed in it.
  =========================================================================== }
procedure TfrmMain.DetailsFieldExit(Sender: TObject);
begin
  ApplySheetDetail(DetailFor(Sender));       // leaving a box applies what was typed
end;

{ ===========================================================================
  TfrmMain.DetailsFieldKeyPress  (procedure)
  Parameters:
    Sender: TObject - the entry
    var Key: Char - the key typed (set to 0 when handled)
  Notes:
    Event handler for the entries of the details panel: Enter applies what was typed; Esc puts
    back what the sheet has.
  =========================================================================== }
procedure TfrmMain.DetailsFieldKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    ApplySheetDetail(DetailFor(Sender));
  end
  else if Key = #27 then
  begin
    Key := #0;
    UpdateRibbonFromView;                    // Esc: back to what the sheet has
  end;
end;

{ ===========================================================================
  TfrmMain.RibbonPaintCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    How many times the ribbon's tab strip has been painted (for tests, to check it is repainted
    when a tab is chosen from code).
  =========================================================================== }
function TfrmMain.RibbonPaintCount: Integer;
begin
  Result := FRibbonTabs.Paints;
end;

{ ===========================================================================
  TfrmMain.FormShow  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Event handler: the first time the window is shown the layout kept in the registry is applied
    (ApplyLayout). It is not done in FormCreate because the form is scaled to the screen's
    resolution after that, which would change the pixels saved.
  =========================================================================== }
procedure TfrmMain.FormShow(Sender: TObject);
begin
  OnShow := nil;
  ApplyLayout;
end;

{ ===========================================================================
  TfrmMain.RememberLayout  (procedure)
  Parameters:  none
  Notes:
    Puts into ProgramSettings where the main window is (its restored place and size when it is
    maximized or minimized, and whether it is maximized) and the places of the two splitters:
    the width of the library panel and the height of the symbol preview in it. SaveSettings then
    keeps them in the registry.
  =========================================================================== }
procedure TfrmMain.RememberLayout;
begin
  with ProgramSettings do
  begin
    WinMaximized := WindowState = wsMaximized;
    if WindowState = wsNormal then
    begin
      WinLeft := Left;
      WinTop := Top;
      WinWidth := Width;
      WinHeight := Height;
    end
    else
    begin
      WinLeft := RestoredLeft;
      WinTop := RestoredTop;
      WinWidth := RestoredWidth;
      WinHeight := RestoredHeight;
    end;
    SplitLeftWidth := pnlLeft.Width;
    SplitPreviewHeight := frameLibraryPanel.pbPreview.Height;
  end;
end;

{ ===========================================================================
  TfrmMain.ApplyLayout  (procedure)
  Parameters:  none
  Notes:
    Puts the main window and the two splitters where they were left (ProgramSettings, read by
    LoadSettings). The window goes where it was only when its title bar is on a screen now
    (FitSavedWindow), otherwise it keeps the designed place and the saved size; it is maximized
    when it was. The splitters are kept to a sensible range: the library panel 100 pixels or
    more and 300 less than the window's width, the preview 40 pixels or more and 100 less than
    the panel's height. Nothing is changed when no layout was saved.
  =========================================================================== }
procedure TfrmMain.ApplyLayout;
var
  Works: array of TRect;
  Fit: TRect;
  i: Integer;
begin
  with ProgramSettings do
  begin
    if (WinWidth > 0) and (WinHeight > 0) then
    begin
      SetLength(Works, Screen.MonitorCount);
      for i := 0 to Screen.MonitorCount - 1 do
        Works[i] := Screen.Monitors[i].WorkareaRect;
      if FitSavedWindow(Rect(WinLeft, WinTop, WinLeft + WinWidth, WinTop + WinHeight), Works, 800, 500, Fit) then
      begin
        Position := poDesigned;
        SetBounds(Fit.Left, Fit.Top, Fit.Right - Fit.Left, Fit.Bottom - Fit.Top);
      end
      else
        SetBounds(Left, Top, Fit.Right - Fit.Left, Fit.Bottom - Fit.Top);
      if WinMaximized then
        WindowState := wsMaximized;
    end;
    if SplitLeftWidth > 0 then
      pnlLeft.Width := Max(100, Min(SplitLeftWidth, Max(100, ClientWidth - 300)));
    if SplitPreviewHeight > 0 then
      frameLibraryPanel.pbPreview.Height := Max(40, Min(SplitPreviewHeight, Max(40, pnlLeft.Height - 100)));
  end;
end;

{ ===========================================================================
  TfrmMain.FormCloseQuery  (procedure)
  Parameters:
    Sender: TObject - the form
    var CanClose: Boolean - set False to cancel the close
  Notes:
    Event handler: asks about the unsaved changes of every document before the program closes;
    the close is cancelled if the user cancels for any of them.
  =========================================================================== }
procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  i: Integer;
begin
  CanClose := True;
  for i := FDocs.Count - 1 downto 0 do
    if not ConfirmCloseDocument(i) then
    begin
      CanClose := False;
      Exit;
    end;
  SaveSession;                // (the program is going: remember which designs were open)
  RememberLayout;             // ... where the window and its splitters are
  ProgramSettings.DarkMode := FTheme = themeDark;
  SaveSettings;               // ... and the theme
end;

{ ===========================================================================
  TfrmMain.ViewZoomChanged  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    View event: the zoom changed; the percentage shown is brought up to date.
  =========================================================================== }
procedure TfrmMain.ViewZoomChanged(Sender: TObject);
begin
  UpdateZoomDisplay;
end;

{ ===========================================================================
  TfrmMain.UpdateZoomDisplay  (procedure)
  Parameters:  none
  Notes:
    Shows the zoom in per cent (100% is one pixel to a design unit) in the position bar's
    lbZoomPct and in the last status-bar panel; both are empty while no sheet is shown.
  =========================================================================== }
procedure TfrmMain.UpdateZoomDisplay;
var
  T: String;
begin
  if (FView <> nil) and (FView.Sheet <> nil) then
    T := IntToStr(FView.ZoomPercent) + '%'
  else
    T := '';
  lbZoomPct.Caption := T;
  sbMainBar.Panels[4].Text := T;
end;

{ ===========================================================================
  TfrmMain.DoTestPropRibbon  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Menu item "Property Ribbon Test...": shows every Properties frame side by side in a form
    (FPropTester) so a frame can be looked at while it is designed.
  =========================================================================== }
procedure TfrmMain.DoTestPropRibbon(Sender: TObject);
var
  frm: TfrmPropertyTester;
begin
  frm := TfrmPropertyTester.Create(Self);
  try
    frm.ShowModal;
  finally
    frm.Free;
  end;
end;

end.
