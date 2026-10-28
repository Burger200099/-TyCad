// SPDX-License-Identifier: LGPL-2.1-or-later
unit consts;

{$mode ObjFPC}{$H+}

interface

uses Graphics;


const
  lAppName     = 'TyCAD Electrical';
  lTarget      = {$IFDEF CPU86} 'x86'; {$ELSE} {$IFDEF CPUAMD64} 'x64'; {$ELSE} {$IFDEF CPUX64} 'x64'; {$ELSE}
   {$IFDEF CPUX86_64} 'x64'; {$ELSE} {$IFDEF CPUARM} '32-bit ARM'; {$ELSE} {$IFDEF CPU64} '64-bit ARM'; {$ENDIF}
   {$ENDIF} {$ENDIF} {$ENDIF} {$ENDIF} {$ENDIF}
//  lCopyright   = lAppName + ' ' + lTarget + ' © Copyright 2022-2026' + sLineBreak + 'Eric Hoffman, HPL Software';
  lVerMajor    = 26;  //year
  lVerMinor    = 10;  //month
  lVerRev      = 25;  //day

  // where the printer's own properties window is put in the Print dialog: this far from the dialog's left and top edges (pixels; see osver.PrinterDlgTryPlace)
  PrinterPropertiesOffsetLeft = 30;
  PrinterPropertiesOffsetTop  = 40;

  // the strip of tabs above the open documents (UDocTabs), in pixels at 96 dpi
  ViewRulerSize    = 18;   // the thickness of the rulers round the drawing area (at 96 dpi)
  DocTabHeight     = 24;   // the tabs' height; the strip is two taller, so the current tab's top line has room
  DocTabMinWidth   = 70;
  DocTabMaxWidth   = 220;  // a longer name is cut with ...
  DocTabPadLeft    = 8;    // before the name
  DocTabGap        = 6;    // between the name and the close glyph
  DocTabPadRight   = 6;    // after the close glyph
  DocTabArrowWidth = 20;   // each of the two scroll arrows shown when the tabs do not all fit
  DocTabScrollStep = 90;   // what one click on an arrow or one turn of the mouse wheel moves the tabs



  sLineBreak = //AnsiString(#13#10);
               {$IFDEF LINUX} AnsiChar(#10); {$ENDIF}
               {$IFDEF MSWINDOWS} AnsiString(#13#10); {$ENDIF}
               {$IFDEF ANDROID} AnsiChar(#10); {$ENDIF}

  lCopyright = 'This program is a derivative of TinyCAD, which is licensed under the' + sLineBreak +
               'GNU Lesser General Public License (LGPL), version 2.1.' + sLineBreak + sLineBreak +
               'TyCAD Electrical Copyright © 2026 Eric Hoffman' + sLineBreak + sLineBreak +
               'This software includes translations of TinyCAD source. A copy of the' + sLineBreak +
               'LGPL license is included with this distribution/software.';



{*********** status bar percentages **********************}
const
  StatusBarWidth: array [0..5] of integer = (290, 140, 170, -1, 35, 15); // in px
  StatusBarScale: array [0..4] of byte = (25, 15, 23, 48, 4);  // in percentages

{*********** the Properties panels of the ribbon (TfrmMain.BuildEditors) **********************}
const
  TOOLPROP_BASE = 1000;      // the Tag of a tool property's editor is this plus its index (a selection's editors have the index alone)
  PropLeft = 5;              // the Properties panel: the first editor starts 5 pixels from its left
  PropTop = 5;               // ... and the first row starts 5 pixels from the top
  PropGap = 20;              // between one property (column) and the next
  PropPairGap = 8;           // between a property's caption and its editor
  PropRowsPerColumn = 2;     // properties are placed two to a column: one in the first row, one in the second
  PropRowHeight = 36;        // the height of a row: an editor or caption shorter than this is centred on the middle of the row
  PropRowStep = 51;          // from the top of one row to the top of the next (the second row starts at 56)
  PropCaptionPad = 4;        // added to the width of a caption's text, so the colon is not cut off
  PropCaptionHeightPad = 2;  // added to the height of a caption's text
  PropEditHeight = 28;       // the height of every editor except the check box
  PropTextWidth = 134;       // the width of a text box (TEdit)
  PropNumWidth = 60;         // the width of a number box (TSpinEdit and TFloatSpinEdit)
  PropComboWidth = 134;      // the width of a drop-down list
  PropLineStyleExtra = 60;   // a line style drop-down is as wide as the pictures of the line styles plus this (room for the arrow)
  PropCheckWidth = 30;       // the width of a check box (it has no caption of its own: the caption is the label before it)
  PropCheckHeight = 24;      // ... and its height
  PropColorWidth = 60;       // the width of a color button
  PropColorBorder = 2;       // the border round the color shown in a color button
  PropColorSwatch = 16;      // the size of the square of color in a color button
  PropIntMin = -100000;      // the smallest whole number a number box takes (the object clamps it to what suits the property)
  PropIntMax = 100000;       // ... and the largest
  PropIntStep = 1;           // how much an arrow of a whole number box changes it
  PropFloatMin = -100000;    // the smallest fractional number a number box takes
  PropFloatMax = 100000;     // ... and the largest
  PropFloatStep = 0.1;       // how much an arrow of a fractional number box changes it
  PropFloatDecimals = 3;     // decimals shown in a fractional number box
  PropSpinDelay = 600;       // milliseconds after the last change in a number box before it is applied (typing 12 does not apply 1 on the way; an arrow applies by itself)
  { the order a button for a direction goes through (clockwise), and the first picture of the directions in the image list of the frame that has the button (Up is that one, Right the next ...) }
  PropDirRotation = 'Up|Right|Down|Left';
  PropDirGlyph = 5;


  // Registry Keys and values
  REG_HPLSOFT_KEY = 'SOFTWARE\HPL Software\TyCAD Electrical';
  REG_AUTOSTRINGS = 'AutoComplete';
  REG_SETTINGS    = 'Settings';
  REG_MODE        = 'Mode';

type
  TRibbonTheme = record
    HeaderColor: TColor;
    HoverColor: TColor;
    SelectedColor: TColor;
    TextColor: TColor;
    SelectedTextColor: TColor;
    ContentColor: TColor;
    ContentTextColor: TColor;
  end;

  TLDTheme = (themeLight, themeDark);

const
  // TColor hexadecimal format: $00BBGGRR
  RibbonThemes: array[0..1] of TRibbonTheme = (
    // 0: Light
    (
      HeaderColor:       $009A572B;
      HoverColor:        $00B16F41;
      SelectedColor:     $00FFFFFF;
      TextColor:         $00FFFFFF;
      SelectedTextColor: $009A572B;
      ContentColor:      $00FFFFFF;
      ContentTextColor:  $00202020
    ),
    // 1: Dark
    (
      HeaderColor:       $00202020;
      HoverColor:        $003E3E3E;
      SelectedColor:     $002D2D2D;
      TextColor:         $00DCDCDC;
      SelectedTextColor: $00F5AF6E;
      ContentColor:      $002D2D2D;
      ContentTextColor:  $00DCDCDC
    )
  );

  GridSizeMM: array[0..6] of integer = (500, 1000, 1270, 2000, 2540, 5000, 10000);  // divided by 1000

{*********** program settings **********************}
{ Every setting of the program that is kept between runs is a field of ProgramSettings. USettings saves and loads
  them with TRegistry under HKEY_CURRENT_USER\REG_HPLSOFT_KEY, each field as a value of its own. }
const
  MRU_COUNT = 4;          // how many recently used files are remembered
  REG_MRU   = 'MRU';      // their values are MRU1 ... MRU4 (the newest is MRU1)
  { the options, under the names TinyCAD gives them in its own registry key }
  REG_SHOWGRID = 'ShowGrid';
  REG_SNAPGRID = 'SnapGrid';
  REG_GRID = 'Grid';                // the grid spacing in millimetres, as text
  REG_UNITS = 'Units';              // 0 millimetres, 1 inches
  REG_AUTODRAG = 'AutoDrag';
  REG_AUTOSNAP = 'AutoSnap';
  REG_AUTOJUNC = 'AutoJunc';
  REG_AUTOSNAPRANGE = 'AutoDragRange';   // (TinyCAD's own name for the auto-snap range)
  REG_AUTOSAVE = 'AutoSave';        // minutes between automatic saves; 0 for none
  REG_SHOWPOSITION = 'ShowPosition';  // the Position bar is shown
  REG_PARTSFILE = 'PartsFile';            // the parts library that was open last, opened again at start
  REG_PARTSWARNING = 'PartsWarningOff';   // the person asked not to be warned that a part from a parts library breaks TinyCAD compatibility
  REG_SHOWVIEWRULERS = 'ShowViewRulers';  // the rulers round the drawing area are shown
  REG_SYMFONTNAME = 'SymbolFontName';      // the symbol font of Options > Fonts
  REG_SYMFONTPOINTS = 'SymbolFontPoints';
  REG_SYMFONTBOLD = 'SymbolFontBold';
  REG_SYMFONTITALIC = 'SymbolFontItalic';
  REG_NEWSHEETBORDER = 'NewSheetBorder';   // Options > Sheets: what a new design's sheet starts with
  REG_NEWSHEETRULERS = 'NewSheetRulers';
  REG_NEWSHEETCOLS = 'NewSheetCols';
  REG_NEWSHEETROWS = 'NewSheetRows';
  REG_NEWSHEETMARGIN = 'NewSheetMarginMm';
  REG_REOPEN = 'ReopenDesigns';     // open again the designs that were open when the program was last closed
  REG_SESSION = 'Session';          // their files are Session1 ... (in the order they were open)
  REG_SESSIONACTIVE = 'SessionActive';    // the number (from 1) among them of the one that was showing
  REG_BOMTYPE = 'BOMNetlist';       // the parts list dialog (TinyCAD's own names): the file format, 0 text, 1 CSV, 2 spreadsheet CSV
  REG_BOMHIER = 'BOMHierarchical';  // include all hierarchical links
  REG_BOMPREFIX = 'BOMPrefixNetlist';    // prefix symbol references with the sheet number
  REG_BOMSHEETS = 'BOMAllSheets';   // include all sheets
  REG_BOMATTRS = 'BOMAllAttrs';     // include all attribute information
  REG_NETTYPE = 'Netlist';          // the PCB export dialog (TinyCAD's own names): the format, 0 TinyCAD ... 6 XML
  REG_NETPREFIX = 'PrefixNetlist';  // prefix symbol references with the sheet number
  REG_PARTCHECK = 'PartCheck';              // the parts check of the design rules check: on or off, default on
  REG_PARTCHECKUNRES = 'PartCheck.unresolved';   // a part with no product chosen: 0 not reported, 1 warning, 2 error; default 1
  REG_PARTCHECKOVER = 'PartCheck.oversized';     // report a product larger than required (information), default on
  REG_ERC = 'ERC';                  // the design rules check: which checks are on, as a WORD (default 0xffff)
  REG_ANNOTATE_TYPE = 'Annotate.type';          // Generate Symbol References: which references (0 all, 1 un-numbered, 2 matching), default 1
  REG_ANNOTATE_SHEETS = 'Annotate.allsheets';   // ... and whether it covers all the sheets, default on
  REG_PRINT_SCALE = 'PrintScaleFactor';         // Print: the scale, per cent, kept as text ("%lg"), default 100
  REG_DARK_MODE = 'DarkMode';                   // the ribbon theme: dark (1) or light (0, the default)
  REG_BITMAP_TYPE = 'BitmapType';               // Export Image (TinyCAD's own names): 0 colour PNG, 1 black and white PNG, 2 colour SVG, 3 black and white SVG (TinyCAD: 2 and 3 are metafiles)
  REG_BITMAP_SCALING = 'BitmapScaling';         // ... the scale of a PNG, per cent, 1 to 1000, default 100
  REG_BITMAP_ROTATION = 'BitmapRotation';       // ... a PNG turned a quarter turn, default off
  REG_NEWDOC_PAPER = 'NewDocPaper';             // New Document: the paper size last chosen (its name in the paper table), default ISO A4
  REG_WIN_LEFT = 'WindowLeft';                  // the main window as it was left: its place and size (restored, when it was maximized) ...
  REG_WIN_TOP = 'WindowTop';
  REG_WIN_WIDTH = 'WindowWidth';
  REG_WIN_HEIGHT = 'WindowHeight';
  REG_WIN_MAXIMIZED = 'WindowMaximized';        // ... whether it was maximized
  REG_SPLIT_LEFT = 'LeftPanelWidth';            // ... the width of the library panel (the splitter between it and the sheet)
  REG_SPLIT_PREVIEW = 'PreviewHeight';          // ... the height of the symbol preview in that panel (its splitter)
  REG_NEWDOC_LANDSCAPE = 'NewDocLandscape';     // ... and whether it was landscape, default on
  REG_PRINT_NOSYMFIELDS = 'PrintNoSymFields';    // Print: whether the fields of the symbols (reference, name, values) are left off the printout, default off
  REG_PRINT_NOSYMTEXT = 'PrintNoSymText';        // Print: whether symbol text is left off the printout, default off
  REG_PRINT_BANDW = 'PrintBandW';               // ... and whether it prints in black and white, default off
  REG_LIBRARY = 'Library';          // the symbol libraries in use: Library1 ... in order (TinyCAD keeps one comma separated value, "Libraries"; a path may hold a comma)
  LIBRARY_MAX = 100;                // how many libraries are remembered
  SESSION_MAX = 20;                 // how many designs are remembered
type
  TProgramSettings = record
    MRUFiles: array[0..MRU_COUNT - 1] of String;   // recently used files, newest first; unused entries are empty
    { the Options dialog: what a new design starts with (a design that is opened keeps what its file says where the file says it) }
    ShowGrid, SnapGrid: Boolean;
    GridMm: Double;                    // the grid spacing in millimetres
    Units: Integer;                    // 0 millimetres, 1 inches
    AutoDrag, AutoSnap, AutoJunction: Boolean;
    AutoSnapRange: Integer;            // how close counts as on a pin, in design units
    AutoSaveMinutes: Integer;          // 1 to 60 minutes between automatic saves; 0 for none
    ShowPosition: Boolean;             // the Position bar (pointer position, snap and grid size) is shown
    LastPartsFile: String;             // the parts library file that was open last ('' for none)
    PartsWarningOff: Boolean;          // do not warn before the first part of a parts library is placed
    ShowViewRulers: Boolean;           // the rulers along the top and left of the drawing area are shown
    SymbolFontName: String;            // Options > Fonts: the font of the text of symbols (TinyCAD's pin font), what a new design starts with
    SymbolFontPoints: Integer;         // ... its size in points
    SymbolFontBold, SymbolFontItalic: Boolean;
    NewSheetBorder, NewSheetRulers: Boolean;   // Options > Sheets: a new design's sheet has a border / rulers
    NewSheetCols, NewSheetRows: Integer;       // ... the number of columns (1 to 26) and of rows (1 to 26, shown as the letter A to Z) of the rulers
    NewSheetMarginMm: Double;                  // ... the distance of the border from the edge of the page, millimetres
    ReopenDesigns: Boolean;            // open the designs that were open last time when the program starts (an addition: TinyCAD does not)
    SessionFiles: array[0..SESSION_MAX - 1] of String;   // the files of the designs that were open when the program was last closed, in order; unused entries are empty
    LibraryFiles: array[0..LIBRARY_MAX - 1] of String;   // the symbol libraries in use (full paths of .TCLib files) in the order they were added; unused entries are empty
    SessionActive: Integer;            // which of them (from 1) was showing; 0 for none
    BomType: Integer;                  // the parts list dialog remembers its choices: 0 text file, 1 CSV file, 2 spreadsheet compatible CSV file
    BomHierarchical, BomPrefix, BomAllSheets, BomAllAttrs: Boolean;
    NetType: Integer;                  // the PCB export dialog remembers its format (0 TinyCAD, 1 PADS-PCB, 2 PADS-PCB-WITH-VALUE, 3 Eagle SCR, 4 Protel, 5 gEDA PCB, 6 XML)
    NetPrefix: Boolean;                // ... and the sheet-number prefix choice
    PartCheck: Boolean;                // the parts check (chosen products against what the parts require) is part of the design rules check
    PartCheckUnresolved: Integer;      // ... a part with no product chosen: 0 not reported, 1 warning, 2 error
    PartCheckOversized: Boolean;       // ... a product larger than required is reported (information)
    ErcWord: Integer;                  // the design rules check dialog's choices as TinyCAD's WORD (bit 0 duplicated references ... bit 10 unassigned reference designators); 65535 = all on
    AnnotateType: Integer;             // Generate Symbol References: 0 all references, 1 un-numbered, 2 matching
    AnnotateAllSheets: Boolean;        // ... and all the sheets
    PrintScale: Double;                // Print: the scale, per cent (100 = the sheet at its real size)
    PrintNoSymFields: Boolean;         // ... and whether the fields of the symbols are left off
    PrintNoSymText: Boolean;           // ... and whether symbol text (reference notes of the designer) is left off
    PrintBandW: Boolean;               // ... and whether it prints everything in black
    ExportType: Integer;               // Export Image: the kind of file, 0 to 3 (see REG_BITMAP_TYPE)
    ExportScale: Integer;              // ... the scale of a PNG, per cent
    ExportRotate: Boolean;             // ... and whether a PNG is turned a quarter turn
    DarkMode: Boolean;                 // the window is in the dark theme (False: light)
    NewDocPaper: String;               // New Document: the paper size chosen last time (a name from the paper table); the dialog starts on it
    NewDocLandscape: Boolean;          // ... and its orientation
    WinWidth, WinHeight: Integer;      // the main window when it was closed (restored size); 0 when none is kept
    WinLeft, WinTop: Integer;          // ... and its place on the screen
    WinMaximized: Boolean;             // ... and whether it was maximized
    SplitLeftWidth: Integer;           // the library panel's width in pixels; 0 when none is kept
    SplitPreviewHeight: Integer;       // the symbol preview's height in pixels; 0 when none is kept
  end;
var
  ProgramSettings: TProgramSettings;

implementation

end.
