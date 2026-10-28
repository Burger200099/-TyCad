# TinyCAD -> Free Pascal / Lazarus port: data layer and schematic editor

Ported from the TinyCAD C++/MFC sources (original: Copyright 1994-2019 Matt Pyne, LGPL 2.1+;
this port keeps that licence). The non-visual data layer (file formats, the
data model, geometry, netlists) and the editor built on it are all in the project folder described under *Folder layout*. Licence for new work: it stays
LGPL 2.1 or later, so keep the headers and publish changes if you ever distribute it.

## Folder layout

    schematic.lpi / .lpr / .lps   the Lazarus project, in the root (target: bin/schematic, unit lib/<cpu>-<os>)
    build.sh                      command-line build (fpc), same paths as the project
    src/                          the U units (UXml, UDesign, UPrint, ...), consts.pas, osver.pas
    src/forms/                    the F units and their .lfm (Fprint, Foptions, ...) and mainform.pas/.lfm
    src/forms/deprecated/         Fcolors (moved into Foptions; kept for reference, not in the project)
    src/frames/                   the Q units (QFindPanel, QLibPanel) and their .lfm
    bin/                          the built program (schematic)
    tests/  tests/drivers/        the Python checkers, and the Pascal test programs they build
    tools/                        doccomments.py, check_comments_only.py and tools/notes/*.json

The project's `OtherUnitFiles` is `src;src/forms;src/frames`; `build.sh` passes the same as `-Fu`.

## Units

| Unit | Ports | What it does |
|---|---|---|
| `UDPoint` | `DPoint.h` | `TDPoint` (NaN = "no value"), pixel <-> mm XML units |
| `UXMLException`, `UXMLCodec` | `XMLException.*`, uuencode, printf/scanf use | exact C number formatting (`%.5f`), TinyCAD's uuencode variant |
| `UXMLWriter`, `UXMLReader` | `XMLWriter.*`, `XMLReader.*` | same file layout; same `NextTag/IntoTag/OutOfTag` API over FPC's DOM parser |
| `UDrawTypes` | `ObjType`, color/symbol/arc constants | enums stored in files stay Integers so unknown values round-trip |
| `UResources` | `DocResource`, `ListOf{Fonts,Styles,FillStyles}`, `UserColor` | font/style/fill tables with the C++ merge + renumber algorithm |
| `UGeometry` | `DRect`, `DSize`, `LineUtils`, `Transform`, `TransformSnap::Snap` | rectangles, exact line/point/rectangle maths, grid snap, the screen transform, direction tables, pluggable text metrics |
| `UDrawingObjects` | `Object.h`, `Draw*.cpp`, `Polygon.cpp`, `Power.cpp` | the 14 object types found in real files: fields, XML, resource tagging, polygon flattening, and (geometry step) `Shift`, `RotateAbout`, `DistanceFromPoint`, `IsInside`, `UpdateLayout`, `Clone` |
| `USymbols` | `Symbol.*`, `ListOfSymbols` | symbol definitions (single and multi-part), the symbol table, and the per-part drawing cache (`CreateSymbol`, `GetTr`, `GetOrigin`, reference points) |
| `UDesign` | `Details`, `Option`, `Io.cpp`, `TinyCadMultiDoc`, `TinyCadMultiSymbolDoc` | sheets, `.dsn` files (single and multi-sheet), symbol documents, library-blob loading |
| `UNetList` | `NetList.cpp` (core), `Net.h` | netlist construction: nodes, per-sheet nets, linking across sheets, net names, hints, and the Protel writer |
| `UNetWriters` | `NetList.cpp` (writers), `DlgPCBExport.*` | the other netlist writers - TinyCAD's own format, PADS-PCB (with and without values), Eagle script, gEDA PCB and XML - and the dispatch by format number of the PCB Export dialog (Protel stays in `UNetList`) |
| `USpiceVhdl` | `NetList.cpp` (`WriteSpiceFile`, `expand_spice`, `WriteVHDLFile`, `Bus_Properties`) | the SPICE writer with its macro language, prolog / epilog and error file, and the VHDL writer with buses, components and port maps |
| `UErc` | `NetList.cpp` / `TinyCadView.cpp` (`DoSpecialCheck`, `DoSpecialVHDLCheck`), `DlgERCListBox` | the design rules check: the options WORD, the state table over net and node types, the scans (unassigned references, net names, duplicated references, missing parts of a package, the nets), the VHDL variant, the messages and the markers |
| `UAnnotate` | `Special.cpp` (`OnSpecialAnnotate`, `AnnotateSetup`), `DrawRefPainter.cpp`; `DrawMethod.cpp` (`AddReference`, `RemoveReference`) is in `UDrawingObjects` | Generate Symbol References: the two passes that take away and give out the numbers of the references, and the reference painter's two actions |
| `UPrint` | `TinyCadView.cpp` (`OnBeginPrinting`, `OnPrepareDC`, `DoPreparePrinting`), `SpecialPrintDlg.cpp` | printing arithmetic with no GUI: the fit scale, the print zoom, how many pages across and down (and on how many sheets), which part of the sheet each page shows, the scale's text (`%3.3lg`) and value (`atof`), and the page range |
| `UExport` | `TinyCadDoc.cpp` (`SavePNG`, `CreateMetafile`), `DlgExportPNG.cpp` | Export Image: the region saved (the sheet or the selection, plus 10 units), the PNG at a scale with the turn, and the SVG (in place of the Windows metafile) drawn on the Cairo canvas |
| `ULibManager` | `DlgLibraryBox.cpp`, `LibrarySQLite.cpp` (`Attach`, `Create`), `LibraryCollection.cpp` (`Cleanup`) | Library manager rules: the name a library shows in the list, `.TCLib` put on a new library's name, checking that a file opens as a library, making an empty library with TinyCAD's tables, and the cleanup (VACUUM) |
| `UPartData` | (new, not in TinyCAD) | the part data a design keeps: the part copy and the chosen product with their ratings, the fit check (same rules as the ProductFit views) and their XML (`<PART>`, `<PRODUCT>`) |
| `UPartsList` | `BOMGenerator.*` | the parts list (bill of materials): the sorted set of symbols, the attribute columns, and the text, CSV and spreadsheet CSV writers |
| `UPaper` | (new) | standard paper sizes (ANSI, ARCH, ISO A/B/RA/SRA, Legal...), page border rectangle |
| `UDocVars` | (new) | title-block variables: `$(SHEET)`, `$(SHEETCOUNT)`, `$(REV)`, ... |
| `UEdit` | `CJunctionUtils`, `CDragUtils`, `CTinyCadDoc::GetStickyPoint`, `CDrawLine` tool | wire drawing: snap to pins and wires, merge, split, automatic junctions, the line tool's state machine |
| `UClip` | `CTinyCadView::OnEditCopy`, `OnEditPaste`, `CDrawBlockImport` | copy and paste in TinyCAD's clipboard format ("TinyCAD Design" = the sheet XML restricted to the selection), the paste block's reference point |
| `USymEdit` | `TinyCadMultiSymbolDoc.cpp` (the data side), `DlgUpdateBox.cpp`, `LibrarySQLite.cpp` (`Store`) | the symbol (.TCLib) editor's model: a symbol's names and drawing, `MakeDesign` / `TakeDesign` (the drawing as a symbol-mode design the view edits and back), `ApplyPartCount` / `ApplyHeterogeneous`, the checks (`Validate`), store / copy to / delete |
| `Fsymprops`, `Fsymparts` | `DlgUpdateBox.cpp` (`CDlgUpdateBox`), `TinyCadMultiSymbolDoc.cpp` (set parts per package, homogeneous / heterogeneous) | the Symbol Properties window (names, description, attributes with their display methods, SPICE data) and the Parts per Package window |
| `UProps` | (new) | object properties, shared properties of a selection, mass change |
| `ULinks` | (new) | text linked to another object by id (rung numbers of the rung grid, contact lists) |
| `UUndo` | (new) | undo/redo as design snapshots |
| `ULibrary` | `LibrarySQLite.*`, `CLibraryStoreNameSet` | read/write `.TCLib` libraries (SQLite) |

## Conventions

- `String` is UTF-8 (the Lazarus default). Console programs should set `DefaultSystemCodePage := CP_UTF8`.
- Turn FPU exceptions off at start-up, as MSVC does by default (`TDPoint` uses NaN):
  `SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);`
- C++ `BOOL` fields (an int) are `Integer`; C++ `bool` fields are `Boolean`.
- `ULibrary` loads SQLite at run time through `sqlite3dyn`: `libsqlite3` (Linux/macOS) or
  `sqlite3.dll` (Windows, next to the program) must be installed. If only `libsqlite3.so.0` exists,
  add a `libsqlite3.so` symlink or call `InitializeSQLite('libsqlite3.so.0')`.
- SQLDB (`sqlite3conn`) is deliberately **not** used for libraries: its memo-field handling
  re-encodes the XML blob (bytes are read as UTF-16), corrupting it.

## Building and testing

    mkdir build        # run from the project folder
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/xmltest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/designtest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/libtest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/geomtest.pas      # (designtest and libtest also hold the placed-symbol checks)
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/nettest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/doctest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/laddertest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/rungtest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/edittest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/dsnbintest.pas   # the old binary .dsn reader's converter
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/modeltest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/cliptest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/symedittest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/polytest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/findtest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/imagetest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/revtest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/repeattest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/orienttest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/blocktest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/bomtest.pas
    fpc -Mobjfpc -Sh -Fusrc -FUbuild -FEbuild tests/drivers/netwtest.pas      # (the netlist writers, SPICE and VHDL; nettest also lists nodes and symbols for them)
    (tests/drivers/settingstest.pas also needs the LCL paths (-Fu as in build.sh), as consts.pas uses Graphics)

Test programs: `xmltest` (XML layer), `designtest` (designs), `libtest` (libraries), `geomtest`
(geometry). The Python checkers in `tests/` compare results against independent references:

    export TC_EXAMPLES=/path/to/folder     # holds your .dsn files, and libraries/*.TCLib
    export TC_BUILD=build TC_WORK=work
    python3 tests/run_designs.py           # every .dsn / .autosave under TC_EXAMPLES
    python3 tests/run_libraries.py         # every libraries/*.TCLib
    python3 tests/run_geometry.py          # generated cases, no sample files needed
    python3 tests/run_placed.py            # placed-symbol geometry on real files (see below)
    python3 tests/run_netlist.py           # netlists vs the real Protel .net files, stability, persistence
    python3 tests/run_docmodel.py          # paper sizes, border, revisions, variables, object ids
    python3 tests/run_ladder.py            # ladder rail object
    python3 tests/run_rungs.py             # rung grid (needs tests/drivers/rungtest.pas built the same way)
    python3 tests/run_rungui.py            # rung grid in the program (xvfb)
    python3 tests/run_edit.py              # wire drawing engine: scenarios, random worlds, pin snapping
    python3 tests/run_model.py             # properties / mass change, links, undo / redo
    python3 tests/run_clip.py              # copy / paste in TinyCAD's clipboard format, resource merging
    python3 tests/run_drag.py              # wires following a dragged symbol, on real designs
    python3 tests/run_find.py              # Find and Replace, and TinyCAD's Find: UFind against an independent reading of every design's XML
    python3 tests/run_image.py             # pictures in a design (core): TinyCAD's uuencode, sizes, load and save (needs ImageMagick)
    python3 tests/run_partslist.py         # the parts list core against TinyCAD's BOMGenerator restated, the sample designs and TinyCAD's own lists (core only)
    python3 tests/run_partsdialog.py       # Special > Create Parts List: the dialog, the three formats, remembered choices, the messages (needs the built program)
    python3 tests/run_netwriters.py        # the PADS, TinyCAD, Eagle, gEDA PCB and XML writers (and Protel) against NetList.cpp restated, 46 samples x 7 formats and generated designs (core only)
    python3 tests/run_netdialog.py         # Special > Create PCB Net List: the dialog, the seven formats, remembered choices, the messages (needs the built program)
    python3 tests/run_spicevhdl.py         # the SPICE and VHDL writers against NetList.cpp restated, and against TinyCAD's own SPICE and VHDL outputs (core only)
    python3 tests/run_spicevhdldialog.py   # Special > Create Spice Net List and Create VHDL file: names, error file, messages, failures (needs the built program)
    python3 tests/run_erc.py               # the design rules check (plain and VHDL, every option) against the C++ restated in Python, on the samples and generated variants (core only; needs erctest and nettest)
    python3 tests/run_ercdialog.py         # Special > Check Design Rules..., V&HDL Check Design Rules..., the options dialog, the Design Markers window, choosing and clicking markers, the pre-checks (needs the built program)
    python3 tests/run_annotate.py          # Generate Symbol References and the reference painter against the C++ restated in Python (core only; needs annotest)
    python3 tests/run_annotatedialog.py    # Special > Generate Symbol References: the dialog, the result and its undo, the painter tool, the Design Markers window's button (needs the built program)
    python3 tests/run_print.py             # the printing arithmetic against TinyCAD's OnBeginPrinting / OnPrepareDC restated in Python (core only; needs printtest)
    python3 tests/run_printdialog.py       # File > Print, Print Preview, Print Setup and Page Setup's printer buttons: the dialogs, the pages and their pixels, black and white, ranges and copies (needs the built program)
    python3 tests/run_session.py           # Save All and reopening the designs that were open (needs the built program)
    python3 tests/run_orient.py            # the way up of a picture: the matrix algebra and the pixel arrangement (core only)
    python3 tests/run_picturerotate.py     # turning and flipping a picture on the screen, alone, in a selection, inside a symbol (needs the built program)
    python3 tests/run_repeat.py            # Repeat Directions: counting names and pin numbers when placing, the menu, per design (needs the built program)
    python3 tests/run_position.py          # Show Position: the position text, the grid size button, the controls in step, persistence (needs the built program)
    python3 tests/run_colors.py            # the Colors dialog: defaults, applying, keeping, persistence, and what is drawn (needs the built program)
    python3 tests/run_options.py           # Options: limits, units, applying to every sheet, keeping, autosave (needs the built program)
    python3 tests/run_revisions.py         # which revisions the extended title block shows, by date or revision, and the file's new elements
    python3 tests/run_extblock.py          # the extended title block: layout, drawing, the Details dialog's grid and the ribbon check box
    python3 tests/run_wireangle.py         # the angle list of the Wire, Bus and Line tools: its items, 90 / 45 degree drawing, kept for the session (needs the built program, numpy, PIL)
    python3 tests/run_dashzoom.py          # rectangle, circle, polygon, cloud and note keep their dashed line styles at 200% zoom (needs the built program, numpy, PIL, scipy)
    python3 tests/run_notewrap.py          # a note's text wraps at the words at the edge of its box (needs the built program, numpy, PIL)
    python3 tests/run_wireghost.py         # the wire / bus / line being drawn is as thick as the tool panel's width and follows changes (needs the built program, numpy, PIL)
    python3 tests/run_labelshapes.py       # label outlines, text directions, attachment boxes, text box focus / Del, floating text (needs the built program, numpy, PIL)
    python3 tests/run_textsize.py          # resizing text and labels with handles, against a port of TinyCAD's MoveField (needs the built program)
    python3 tests/run_scale.py             # scaling a placed symbol with handles, against a port of TinyCAD's rule (needs the built program)
    python3 tests/run_fields.py            # dragging the fields of a placed symbol, against the original design's XML (needs the built program)
    python3 tests/run_resize.py            # resizing with handles: dragged handles against a port of TinyCAD's MoveField (needs the built program)
    python3 tests/run_picture.py           # Insert picture on the screen: stored bytes, pixels drawn, undo, copy, import (needs the built program)
    python3 tests/run_import.py            # Import: the imported block against the original design's XML (needs the built program)
    python3 tests/run_copyto.py            # Copy to: the saved selection against the original design's XML (needs the built program)
    python3 tests/run_settings.py          # the program settings and the recently used files (registry)
    python3 tests/run_poly.py              # polygon handle editing: randomised check of the model
    python3 tests/run_symedit.py           # the symbol editor's data layer, checked in the saved .TCLib files
    python3 tests/run_gui.py               # the program itself under Xvfb (needs bin/schematic)
    python3 tests/run_dsnbinary.py         # the old binary .dsn reader: synthetic files written from the C++ read code (needs dsnbintest; the last group needs the built program)
    python3 tests/run_export.py            # Export Image: dialog, PNG and SVG files against numpy / XML statements, the Insert menu's tool group
    python3 tests/run_libmanager.py        # Library > Libraries...: Add, Remove, New, Cleanup, the saved list and its restore, against sqlite3 and the file system
    python3 tests/run_doctabs.py            # the document tab strip: layout, hover, click / close / middle / right click, scrolling, and its pixels
    python3 tests/run_symboleditor.py      # the symbol editor window: new / edit / properties / parts / duplicate / delete / copy to, against the .TCLib files read with sqlite3 and XML
    python3 tests/run_hints_theme.py       # hints on every usable control (from the .lfm files), menu hints in the status bar, the dark/light theme in the registry

`run_designs` loads and re-saves each design, then checks (a) the saved file is semantically identical
to the original (every font/style/fill/symbol ID resolved to its content, polygon coordinates
re-based, C++ defaults applied) and (b) a fixed point is reached.
`run_libraries` checks the dump of every name set, raw blobs, every symbol placed in a design,
blob round trips, and writing to a brand-new library.
`run_geometry` checks line/point/rectangle maths against textbook geometry and exact segment-
rectangle intersection, polygon fill against the even-odd rule, grid snap, the screen transform,
pin layout and rectangle/ellipse hit tests against transcriptions of the C++ formulas, and
9,000+ rotation/direction invariants. `designtest geom` and `libtest geom` additionally run
`UpdateLayout` on every real object and check that a point known to lie on it is hit.

`run_placed` recomputes every reference point the C++ program saved in `REF_POINT` tags and
compares them (the C++ program's own results are the oracle); then, for every placed symbol in
the designs and every library symbol in all 8 rotations with power pins on and off, checks that the
draw path (`Transform.SetTRM`) and the netlist path (`TranslatePointToDesign`) agree on every pin,
that rotating moves pins rigidly, that pins are hit, that they lie in the bounding box, and that
replacing a symbol with itself moves nothing.

`run_netlist` builds the Protel netlist of every sample design that ships with a real
TinyCAD-written `.net` and compares components (in order) and nets (as partitions of pins, plus
label names; net numbers are not compared because those files count from 0). It also checks, over
all designs, that building the netlist twice gives identical numbering and that the numbering
survives a save and reload.

## The schematic editor

Build with `sh build.sh` (the program is `bin/schematic`) (Free Pascal plus the Lazarus LCL, GTK2; set `LAZ` to your Lazarus
directory). `schematic.lpi` is provided for the Lazarus IDE but has **not** been tested (the
sandbox this was written in could not run `lazbuild`). Printing needs the Printer4Lazarus package (and CairoCanvas, which it uses), as a requirement of the project: `build.sh` takes their compiled units from `components/printers/lib/x86_64-linux/gtk2` and `components/cairocanvas/lib/x86_64-linux/gtk2` under `LAZ`. Nothing else third-party is used.

- **File naming:** units of dialogs and windows built in the form designer start with `F` (for example `Fnewdoc.pas`, class `TfrmNewDoc`; `Fbase` is the base dialog with the OK / Cancel / Apply buttons and `Fabout` the About box); frames start with `Q` (`QLibPanel.pas`, class `TfrLibraryPanel`); run-time and non-visual units start with `U`. The main window is `mainform.pas` (class `TfrmMain`). `TNewDocForm` in `UDialogs` is kept, commented out, for reference.
- **Window:** main menu; a top-aligned `TPageControl` that is the ribbon (tabs Home, Draw, Ladder,
  Library, View and Properties, built in `TMainForm.BuildRibbon`); a symbol library panel;
  the drawing area; sheet tabs; a status bar. The UI is built in code, so there are no `.lfm` files.
- **Files:** opens `.dsn` (single and multi-sheet) and `.TCLib` libraries (needs `libsqlite3`, or
  `sqlite3.dll` beside the program on Windows). Opening a design gives every object a stable id.
- **New document:** every size in `UPaper` (ANSI A-E, ARCH A-E, ISO A0-A8, B0-B8, RA/SRA, Legal,
  Executive, Statement, C-series envelopes), landscape or portrait, with border, automatic sheet
  numbers, title, drawing number, author and company. The dialog starts on the paper size and orientation chosen the last time it was accepted (`NewDocPaper` and `NewDocLandscape` in the program settings, `TfrmNewDoc.RememberChoice`; ISO A4 landscape the first time, and when the remembered paper is no longer in the table); cancelling it, or a script's `newdoc`, leaves them as they were. The border margin is a `TFloatSpinEdit` (two decimals, 0 to 100 mm; a whole-number spin edit could not hold the 6.35 mm default).
- **Ladder rails** (`TDrawLadder`, tag `LADDER`): the two vertical rails of a ladder diagram with a bus label above each (L1, L2).
  It is a rectangle-like object (PointA / PointB are the corners) with the eight resize handles of the rectangle tracker when it is the
  one selected object, so the rails can be made longer, shorter, wider or narrower. Properties (frame `QLadder`, registered as `ladder`):
  left and right bus wire numbers, rail colour and rail width as a **line density** (1, 2, 3 ... whole numbers, the same `line.width` /
  `line.color` as every other line tool; the drawn thickness is that many design units and grows with the zoom, one is a single pixel), and the
  text options of the labels (font, size, bold, italic, colour). Only the two rails and the two bus labels can be clicked; the space between the
  rails cannot. **The line numbers are no longer part of the ladder** (they were `ladder.start/stop/lines/numside`): they belong to the rung grid
  below. A file written by the first version still loads (the numbering attributes are ignored, a fractional width is rounded to the nearest whole
  density). The bus labels stand 12 units (2.4 mm) above the top of the rails so the corner handles do not hide them. `tests/run_ladder.py`
  (independent model of the rails and labels; rectangle select, click tolerance by line density, all 8 handles in either corner order, old files).
- **Rung numbers - the rung grid** (`TDrawRungGrid`, tag `RUNGS`, `xRungGrid` = 154; speed button on the Ladder panel, menu Insert > Ladder > Rung
  Numbers, script `tool rungs` / `rungs`): a sheet's invisible spreadsheet that covers the whole sheet from 0,0 to width,height less an indent on
  all four sides (*Indent*, mm, default 5; when the sheet shows its border the border margin is added to it). A "page" of the grid is two columns:
  column 1 holds the rung numbers (one cell per row, *Rows* of them, all of the same height; the column is as wide as its widest number needs) and
  column 2 is blank and takes up the rest of the page. With one page per sheet column 2 runs to the right indent; with two pages column 2 ends at the
  **middle of the sheet** and column 3 (the second page's numbers) starts exactly at the middle, column 4 running to the right indent. The row height
  in mm is printed above the number column (switch *Row mm* off to hide it). The second page goes on counting where the first stopped
  (*Continue*; off = it starts again at the first number). The grid cannot be moved, rotated or resized, it consumes the whole sheet: a click on a
  rung number (or the printed row height) selects it, the rest of the sheet (including the blank columns) stays free for the circuit, a press on the
  numbers only selects it and a drag moves nothing. The function (button, menu item, `BeginTool(vtRungs)`) is not a drawing mode: it makes the
  sheet's one rung grid (one undo step *Add rung numbers*) or selects the existing one and the Properties panel (frame `QRungs`, key `runggrid`)
  shows its rows, first number, indent, pages (1 / 2), continue, row height and the font. It is refused while a library symbol is being edited.
  **Line number awareness** (`ULinks.LineNumberOfObject`, the *Line link* / *Contacts link* texts): the line of an object is the rung number of
  the row its reference point falls in (page from its side of the sheet middle, row from its height anywhere in the grid's area); in the indent,
  or on a sheet with no rung grid, it is `?`. The grid asks the sheet for its paper size and border through `TDocOptionsBase.PageGeometry`
  (`TDesignSheet.PageGeometryNow`), so it follows page setup changes without being told. Properties `rungs.rows`, `rungs.start`,
  `rungs.margin`, `rungs.pages`, `rungs.continue`, `rungs.showheight`. Known limits: a second grid can be made by pasting one (the first one on
  the sheet is the one used); the button's picture is drawn by the program (`RungButtonIcon`) until there is one in the image list; the number
  column width comes from the widest number (no setting). `tests/run_rungs.py` (independent model of the spreadsheet: layout, numbering, the number
  at any point, clicks, rectangle select, no move, save/load/clone, properties) and `tests/run_rungui.py` (menu, tool name, undo / redo, clicks,
  drag, set-up, save and reload in the real program).
- **Select / move / delete / zoom / pan:** click, shift-click, rubber band, drag to move (grid snapped),
  Delete, mouse wheel zoom, right or middle drag to pan.
- **Placing symbols:** double-click a library entry, click to place, R rotates, X mirrors, Esc cancels.
- **Symbol libraries:** the library frame shows a tree: each open `.TCLib` file is a top-level node (with its symbol count) and its symbols are the children, so several libraries can be open at once. Select a symbol to preview it, double-click it to place it; right-click a library for Close library / Close all libraries. The filter box searches the symbols of every open library. Library > Open Libraries accepts several files at once; opening a file that is already open reads it again.
- **More placement tools:** power symbols, no-connects, buses, bus slashes and free text, on the Draw tab. Power
  symbols and no-connects stick to the pin under the mouse like a junction; a new power symbol, text or bus slash
  is selected so its kind, direction and text can be set in Properties.
- **Rotate, flip, Z-order:** Rotate left / right (Ctrl+L, Ctrl+R) and Flip turn the selection about the snapped centre
  of its extent, as TinyCAD does; wires attached to it do not follow. To front / To back change what is drawn on top.
- **Documents:** any number of designs can be open at once, each with its own view, undo history, zoom and
  selection. A tab per document sits above the drawing area; the Window menu lists them (Ctrl+Tab and
  Ctrl+Shift+Tab step through them, Ctrl+W closes one); a close glyph on each tab (or a middle click on it) closes
  it, a right click offers Close and Close all, and a document with unsaved changes shows a mark in place of the glyph
  until the pointer is on its tab (see *Document tab strip* below). New and Open add a document; opening a file that is already open shows it. Closing the program
  asks about the unsaved changes of each document. Copy and paste work between documents.
- **Options:** `DoOptions` (bind it to a button) shows TinyCAD's three Options pages: Grid (spacing typed in millimetres or inches or chosen from the usual sizes,
  shown, snapped to, units), Auto-snap (auto drag, auto snap and its range, auto junctions) and Auto-save. OK applies and closes, Apply applies and stays, and a
  value that cannot be used is refused with a message and changes nothing. The values are applied to **every sheet** of the open design (TinyCAD changes only the
  sheet showing), do not mark the design as changed (as in TinyCAD), and are kept in the registry as what a new design starts with: a new design takes the saved grid,
  snapping and auto settings, while a design opened from a file keeps the grid and units its file says. The status bar shows positions in the design's units. Switching
  units never changes the spacing (a 5 mm grid is exactly 5 mm in inches and back). Auto-save writes `<name>.autosave` beside every named design, as often as the minutes
  say (10 to begin with, as in TinyCAD): through `<name>.autosave.new` and a rename, without touching the design, its file or its unsaved-changes mark, and silently
  when it cannot.
- **Repeat Directions:** the View menu's *Repeat Directions* submenu (TinyCAD keeps it in its Options menu) has *Name Increment / Name Decrement* and *Pin Increment / Pin Decrement*,
  each pair a choice of its own, both Increment to begin with, kept for each open design and not saved in its file (as in TinyCAD). Place a label or a text and the **next** one you place
  starts as the previous one with its number counted by the name direction: A1, A2, A3 ... or A9, A8, A7 ... (CDrawLabel/CDrawText::LButtonDown). TinyCAD's text box that does the
  counting does not exist here, so the next one starts from the last one placed *as it reads now* (a text you typed over it is counted from), or as it was placed if that one is gone
  (after an undo the count carries on, as TinyCAD's box would). Labels and texts count separately. The rules are TinyCAD's, quirks included: the first digit **or minus sign** starts the
  number and everything after its digits is dropped (D1-5 gives D2; NET-3 gives NET-2), and text with no digit does not change. A pin counts its number by the pin direction and its name by
  the name direction by the other rule (`IncrementNumber`): the first run of digits, kept from 1 to 999, the text round it kept, and with no digits a last letter moves along the alphabet.
  The pin function and the pin direction are in place (`URepeat`, `NextPinValues`), and the Pin tool of the symbol editor uses them to count a pin's number and name on from the previous pin, as labels and texts do.
- **Select button, draw tools, Properties panel, wires, selection box:** the Draw ribbon starts with a *Select* button (`sbDrawSelect`, and the Home ribbon's Select button works the same way): both are pressed while Select is the tool and have groups of their own, and no draw button is pressed then (an earlier version left the last draw tool pressed, which was a misreading). The toolkit's button groups only reach buttons on the same panel, so `UpdateRibbonState` releases the other draw buttons itself (the tool buttons have `AllowAllUp` set so that it can). The Properties ribbon's editors are placed in `plPropsProperties`: the first row at 5, 5 and the second at 5, 56 (36 pixel rows; a shorter control is centred on 23 or 74), a caption and its editor 8 pixels apart, 20 pixels between one column (two properties) and the next; the panel is widened to hold them all, and `lbPropsProperties` (at its foot, as wide as the panel) says what is selected. (The 20 pixels is between properties, not between a caption and its editor.) A wire or bus being drawn is red and has the thickness of the confirmed one, which is blue (the wire colour); before it was a thin line in the wire colour, so it grew when confirmed. A selection box dragged to the right selects what it touches; dragged to the left, only what it holds completely (TinyCAD's rule; before both touched). The grid dots grow with the zoom: a dot is as many pixels wide as the zoom is in hundreds of per cent, rounded (one pixel at 100% and below, 3 at 300%); before they stayed one pixel and so looked smaller and smaller against the drawing. **Tool Properties panel:** while a draw tool is in use the Draw ribbon ends with a separator (2 wide, `alLeft`) and a panel (no caption, `alLeft`, `bvNone`) with a label at its foot captioned *Properties*, holding editors for what the tool draws, placed like the rest of the ribbon (`BuildEditors`, shared with the selection's Properties tab: rows at 5 and 56, 20 pixels between columns). They are made by `UpdateToolPanel` (called from `UpdateRibbonState`, so it follows `DoToolButton`, `DoToolMenu`, Esc and a right click alike) and freed when Select is the tool or the tool has nothing to choose. The properties are the ones `ObjectProps` gives a sample of the object (`ToolSampleOf`: wire, bus, line, polygon/arc, rectangle, circle, note, cloud, measure, text, label, power) without the per-object ones (text, direction, ruler position, closed, target); what is chosen is kept in the view (`SetToolDefault`) for the session and given to each new object (`AddNew`, and the wire tool's `OnNewLine` for each segment). **Dashed lines:** a pen wider than a pixel cannot be dashed by the system, so a dashed wire turned solid once the zoom made it two pixels thick (past 150%); `TSchematicPainter.DashedLn` now lays the dashes out itself (a dash is 5 pen widths, a dot 1, a gap 2); polygons, rectangles and circles with a dashed style are still solid when thick. **Line style lists:** any drop-down whose choices are the line styles (`DashChoices`: Solid, Dash, Dot, Dash-dot, Dash-dot-dot; the Line style editor of the tool and of the selection) is owner-drawn (`LineStyleDrawItem`, `PaintLineStyleItem`) with the pictures of `ilListBoxImages` (image N for item N: 0 solid, 1 dash, 2 dot, 3 dash dot, 4 dash dot dot) instead of text. **Properties tab:** selecting something with the Select tool brings the Properties tab forward and remembers the tab that was showing (`FTabBeforeProps`); when nothing is selected any more that tab comes back, unless the person chose another tab meanwhile (`ChooseRibbonTab`, what a click on a tab does) or chose the Properties tab by hand. **Colors and captions:** a color property is a `TColorButton` (its `OnColorChanged` applies the color, `PropColorChanged`) in both Properties panels, and the line properties are captioned *Color:*, *Width:* and *Style:* (the captions are the `Def(...)` calls in `UProps.ObjectProps`: `line.color`, `line.width`, `line.style`; the colon is added by `BuildEditors`). **Number boxes:** a whole-number property (`pkInt`: line width, font size, pin length, ladder lines ...) gets a `TSpinEdit` and a fractional one (`pkFloat`: scallop, rail width, scale ...) a `TFloatSpinEdit`, 60 pixels wide, in both Properties panels; a text property stays a 134 pixel `TEdit`. A change is applied when Enter is pressed or the box loses focus, or `PropSpinDelay` (600 ms) after the last arrow press or digit, so typing 12 does not apply 1 on the way; a box that still shows what it was given applies nothing (so passing through a box never rounds a value to the box's three decimals), and a box for properties that differ across the selection is empty (`ValueEmpty`). The limits of a box are generic (`PropIntMin` ... `PropFloatDecimals`); the object still clamps the value to what suits the property. Every position and size `BuildEditors` uses is a named constant in `consts.pas` (`PropLeft`, `PropTop`, `PropGap`, `PropPairGap`, `PropRowHeight`, `PropRowStep`, `PropNumWidth` ...), as is `TOOLPROP_BASE`. The Library menu moved to the right of Insert in the form designer. `tests/run_ribbontools.py` (53 checks) works these by script (`toolbuttons`, `selectbutton draw|home`, `propspanel`) and reads the pixels of `shot` pictures; four deliberate faults are each caught.
- **Zoom and the zoom percentage:** the mouse wheel zooms about the pointer at any window size (each notch is a factor of 1.2). The wheel handler had converted the pointer to the control's coordinates a second time (the toolkit already passes it in the control's own coordinates), which was invisible only while the drawing area started at the screen's top-left corner, as in a full-screen window. The zoom is shown in per cent (100% is one pixel to each 0.2 mm design unit) in `lbZoomPct` at the left of the Position bar (`lblPosition` is 40 pixels narrower and moved to Left 50) and in the fifth status-bar panel; `StatusBarScale` has five shares (20, 20, 8, 50 and 2 per cent), and showing the Position bar empties status panel 1. `tests/run_zoomwheel.py` (36 checks) works the wheel by script (`wheel <x> <y> <delta> [w h]`) at three window sizes; putting the second conversion back is caught.
- **Show Position:** the View menu's *Show Position* item and the *Show Position* button of the ribbon's View tab (bind `DoShowPosition`) show or hide TinyCAD's **Position bar**,
  a strip above the status bar with the pointer's position, a *Snap* button, a *Grid size* button and the grid size with its units. The position is TinyCAD's own text
  (COption::PointToUnit): the pointer snapped to the grid (when snapping is on) and measured from the sheet's origin (a sheet has an origin only while a symbol is edited, which
  is not ported yet, so for now it is the page corner), as two decimals and `mm` padded to nine places, or three decimals and an inch mark `''` in inches. The *Grid size* button goes
  through the standard sizes as TinyCAD's does (CTinyCadView::OnToggleGridSize): 2 mm, 1 mm, 0.5, 0.25, 0.1 and back to 2 mm; any other size goes to 2 mm. The size is shown in tenths
  of a millimetre or thousandths of an inch (2 mm is 20, or 78.74), with the label `.1mm` or `.001"`. The bar is shown to begin with and its state is kept in the registry
  (`ShowPosition`). **Deviation:** with the bar hidden, the position goes to the status message, so that it is never lost (TinyCAD shows it nowhere then). The snap button, the
  Show grid button and menu item, and the ribbon's *Grid: ...* caption (now in the sheet's units, it was always millimetres) are kept in step with the sheet whatever changes it,
  including the Options dialog (which did not update them before).
- **Hints and the status bar:** every control and menu item that a person can use has its `Hint` filled in the form designer (menu items, speed buttons, buttons, check and radio buttons, edits, lists, ...; separators have none). When the cursor moves onto a menu item the toolkit sets `Application.Hint` from the item's `Hint` and `TfrmMain.AppHint` (the `Application.OnHint` handler) shows it in panel 0 of `sbMainBar`, or `Ready` when there is none. `tests/run_hints_theme.py` reads every `.lfm` as text and fails for any usable control without a hint, and checks the display through the script command `menuselect <item>`.
- **Light / dark theme:** the View menu item `mTheme` says what it will switch to (`Dark Mode` / `Light Mode`); `ApplyTheme` sets the ribbon theme and the caption. The choice is the setting `DarkMode` (registry value `DarkMode`, default light), written as soon as the item is used and when the program closes, and read at the start (`FormCreate`). The old `FormActivate` call that toggled the theme on every activation was removed. The script commands `themeinfo` and `dotheme` drive it in the tests.
- **Colors:** The Define colors dialog is now a page of the Options window (`Foptions`, `pnlColors`, `ColorDlg`); `src/forms/deprecated/Fcolors` is the old stand-alone form, out of the project. `DoColors` shows TinyCAD's Define colors dialog: ten colors, each as a swatch with a Change button (the background of the drawing, wires,
  buses, junctions, no-connect marks, pins, power symbols, and the background, border and text of a note), and Defaults, OK and Cancel. OK applies the colors to **every sheet** of
  the open design (TinyCAD changes only the sheet showing), redraws, and does not mark the design as changed. Of the ten, only those that differ from TinyCAD's own colors are kept
  (in the registry) as what **new** designs start with; a color put back to the standard one stops being kept, and the two colors the dialog does not list (net labels and the pins
  of power symbols) are carried through but never kept. Defaults puts all twelve back to the standard colors. A design read from a file takes the colors its file says (and the
  standard ones where it says nothing, so a new choice does not recolor a drawing made before). What the colors do: the paper takes the background color; wires and buses drawn in
  the default style, junctions, no-connect marks, power symbols and pins are drawn in theirs (a wire with a line style of its own keeps that style's color); a note, a net label or a
  bus name made after the change *starts* with the note or label color, and keeps it when the colors change again. The spelling `color` is used throughout this port, in names, files (`Fcolors.pas`) and text
  (TinyCAD's own source uses the British spelling).
- **The extended title block:** a switch per sheet (the *Extended info* box on the ribbon's Sheet tab, or *Show the extended information on the sheet* on the Details
  page of the Design Details dialog) adds to the standard block: a **revision table** to its left, as high as the block, six rows (the headings REV, DATE, DESCRIPTION,
  BY and the five newest revisions, newest first), 560 units (112 mm) wide shared 50:100:330:80, and above the two a **notes and reference cell**, 135 units high, as wide
  as both and halved. On a page too narrow for it the table shrinks (never below 100 units). Which revisions are the newest is decided by the order checkbox on the new
  *Extended information* tab: by date (the default; dates are read as 2024-03-09, 9/3/2024, 9 Mar 2024, ...; the first number above 12 is the day, otherwise the day comes
  first; text that is not a date is the oldest) or by revision label (numbers by value, so 1.2 < 1.10; letters by length then alphabetically, so Z < AA; a number before a
  letter); equal ones keep the order of the list, the later being the newer. The same choice decides the Revision and Date boxes of the standard block, TinyCAD's own REVISION
  element of the file and the revision variables of text. The tab holds the sheet's revision history as a grid (REV, DATE, DESCRIPTION, BY) that is edited in its cells; the last
  row, which says so, adds a revision when clicked; Ctrl+Delete or the button removes one; a description with several lines shows them on one line with a paragraph sign.
  It is the **same list** as the Revisions page (which also keeps its Approved by field): both editors change one list and keep each other up to date. The Revision box of
  the Details page is read-only and always shows the newest revision; an older file that has only TinyCAD's single Revision becomes the first row of the history when the
  dialog is opened (and is written as such when it is applied). A new row that is left as it began is dropped; one with something in it but no REV is refused with a message.
  In the file, the new items are optional elements of `<DETAILS>` that TinyCAD does not know and skips (with whatever is inside them): `EXTBLOCK` (attributes `sort` and
  `show`; written when the block is shown or the order is by revision), `NOTES` and `REFERENCE`, and the history is the existing `REVISIONS`. Only TinyCAD's `REVISION`
  element is written differently: it holds the newest revision. A file that uses none of this is written exactly as before.
- **Resizing text and labels:** a single selected text or label has the same eight handles round its box (a label has none on its middle).
  A text is not stretched: dragging a handle changes its *font* (CDrawText::MoveField, CDrawLabel::MoveField, COption::ChangeFontSize). The
  height changes by the movement across the line of the text, in the sense that dragging the box bigger makes the characters bigger; if
  the font has a width of its own, the width changes in proportion to the length the box is dragged to. A text's position follows the
  box's corner; a normal label's connection point does (input, output and bidirectional labels keep theirs). Whole units only, so on a
  coarse grid one step changes the size a lot. The widths a resize works from are noted when the object is selected (TinyCAD's BeginEdit),
  and for a font with no width of its own at every layout (TinyCAD's Paint). A font that is made is shared with any identical one. The
  characters' width is kept in the file as TinyCAD keeps it, but the screen drawing here uses only the height.
- **Scaling a placed symbol:** a symbol marked Resizable (the property `Resizable`, saved as `can_scale`; some of the sample designs have such
  symbols) has the same eight handles as a rectangle when it is the one selected object. Dragging one changes the symbol's box and its
  scale together (CDrawMethod::MoveField): the new box is worked out as for any rectangle, and the scale is the new width and height
  divided by the symbol's own size at scale 1, the two swapped for a symbol turned a quarter. The symbol's other corner is then put right
  from its origin, scale and turning, as the next paint does in TinyCAD. Ctrl keeps the shape of the box on a corner. The fields keep their
  offsets from the origin (they are not scaled), and wires attached to the symbol are not moved. One undo step called Resize. Over the body of
  the selected symbol the pointer is the 4-way arrow, over a handle the arrow for that handle.
- **Dragging the fields of a symbol:** with one placed symbol selected, pressing on the text of one of its shown fields (reference, name,
  values) and dragging moves that field by itself (TinyCAD's CDrawMethod::IsInsideField / MoveField). The text's box is from the field's
  position to the right by the width of the text and up by its height; the first field whose box holds the point is the one. The
  field follows the grid, keeps its place relative to the symbol when the symbol is moved or turned, and a drag is one undo step called
  Move field. A field that is not shown, or has no text (its box is of no size), cannot be picked; with several objects selected a
  press on a field does not drag the field. Over the selected symbol, near it, or over one of its fields the pointer is the 4-way
  move arrow.
- **Resizing with handles:** select a rectangle, ellipse, picture or note (alone) and eight black handles appear just outside its
  rectangle, as MFC's tracker draws them in TinyCAD, with a dotted outline. The pointer shows the way a handle resizes (diagonal arrows on
  the corners, up-down on the top and bottom, left-right on the sides). Dragging a handle moves that side or corner and leaves the opposite
  one, following TinyCAD's CDrawRectOutline::MoveField exactly, including dragging past the opposite side (the rectangle turns inside
  out); with Ctrl held a corner keeps the shape. The drag follows the grid, and is one undo step called Resize. A press inside the
  object still moves it as before. A picture is drawn stretched to its new rectangle. Not done: text and labels (TinyCAD resizes those
  by scaling the text, a different mechanism), and wires, symbol fields and rulers, which have their own handles in TinyCAD.
- **Insert picture:** a PNG, JPEG or BMP file becomes a picture on the sheet (TinyCAD's Insert > Picture). It is given the size
  TinyCAD gives a new picture (a design unit for each pixel, at most 500 either way) and follows the mouse until a click places it,
  as a paste does (one undo step called Insert picture; right click or Esc cancels and takes the picture out of the design again).
  PNG and JPEG are kept in the design exactly as the file was; a BMP is converted to PNG. In the file a picture is an `IMAGE` element
  (its type and the bytes uuencoded in TinyCAD's own way) and each use of it a `METAFILE` object with two corners, so the files
  stay compatible with TinyCAD. The same picture is kept once however often it is used. A picture that cannot be drawn is shown
  as TinyCAD shows it: a white box with the words "Invalid image". Turning and flipping a picture is below. Not done: Windows metafiles (.emf, which are only carried along if a file has them).
- **Save All, and the designs that were open (two additions: TinyCAD has neither; its own `SaveAll` is only the helper of the automatic save):** *File > Save All* (Ctrl+Shift+S) and the *Save All*
  button of the ribbon's File group save every open design that has unsaved changes, to its own file, one after another. A design with no file name is asked for one in turn; a design that
  cannot be written does not stop the others and is named in one message at the end; the design that was showing is showing again afterwards, nothing is written for a design with no changes,
  and the undo histories are not touched. In Options (on the *Auto-save* page) *Open the designs that were open when I last closed the program* is **off to begin with**; when it is on, closing
  the program remembers the files of the designs that have one (in order, at most 20) and which of them was showing, and the next start opens them again before any file named on the command line
  (`--open`). They are kept in the registry as `ReopenDesigns`, `Session1` ... and `SessionActive`. A file that has gone, or cannot be read, is left out without a message; with the option off
  nothing is remembered and what was remembered is forgotten.
- **Parts list (Special > Create Parts List...):** TinyCAD's bill of materials, ported from `BOMGenerator.cpp` and `DlgBOMExport.cpp`. The dialog is TinyCAD's: a format (*Text file*,
  *CSV file*, *Spreadsheet compatible CSV file*), the file to write (proposed as the design's name with `.txt`, or `output.txt` for a design with no file; choosing a format changes the extension of
  the name, only after the last dot; *Browse...* picks a file) and four choices - *Include all sheets*, *Include all hierarchical links*, *Include all attribute information*, *Prefix symbol
  references with sheet number*. The choices are kept between runs under TinyCAD's own registry names (`BOMNetlist`, `BOMAllSheets`, `BOMAllAttrs`, `BOMHierarchical`, `BOMPrefixNetlist`), also
  when the file could not be written, but not when Cancel is pressed. Every placed symbol of the sheet shown (or of all sheets) goes into a set ordered by its text and then its reference, so equal
  parts come out together; a second symbol with the same text and reference is dropped, and the parts of a multi-part symbol are one entry (the reference is the field as typed, with no part letter,
  as TinyCAD's `GetRef`). The text is the symbol's name; with *all attribute information* it is followed by one column per heading - *Description* (the symbol's description), *Package*, then every
  other field name met, names compared ignoring case, fields that are always hidden left out, a symbol with fewer fields getting no trailing columns - each wrapped in quotes if it holds the
  separator (a comma, or a semicolon for the spreadsheet format; quotes inside are not doubled, as in TinyCAD). The text list is headed with the design's file name, then one entry per distinct
  text: its references wrapped at 25 columns, padded, the quantity and the text. The CSV file has a `Reference,Quantity,Name,...` heading line, then a quoted reference list, the quantity and the
  text. The spreadsheet file is semicolon separated with the references comma separated. If any symbol still has the reference it was defined with (`R?`) the list is written but a message says it
  will be inaccurate, as TinyCAD's; a file that cannot be written (for example an empty name) gives TinyCAD's message and nothing is written. Differences: the output is UTF-8 (TinyCAD wrote the ANSI
  code page); the sheet-number prefix does nothing (TinyCAD stores the choice but its generator never reads it); the hierarchical choice follows placed designs (see *Hierarchical designs*): each is read in full (every sheet, whatever *Include all sheets* says) and its parts are listed with the path of symbols in front of the reference (`H1_G1_R3`), a design placed twice twice; a design that cannot be read is skipped; more than 100 levels stops the following (the C++ shows a message and then loops on that symbol for ever, which this port does not);
  TinyCAD opens the finished file in a text editor, this program does not; the line ends are the platform's. `tests/run_partslist.py` compares the core, on every sample design with every combination of
  format, sheets and attributes, and on 120 generated designs full of awkward cases, with a separate Python statement of TinyCAD's code, and also reproduces three of TinyCAD's own sample parts
  lists byte for byte (the other three were made from designs that were edited afterwards); `tests/run_partsdialog.py` runs the real dialog.
- **Design rules check (Special > Check Design Rules..., V&HDL Check Design Rules...):** TinyCAD's ERC, ported into `UErc` with the options dialog (`Fercopts`) and the Design Markers window (`Fercwin`). The dialog has eleven boxes in TinyCAD's order - Errors: duplicated references, unconnected items, more than one item on a no-connect net, unassigned reference designators, power connected to power, power connected to an output, output connected to an output, no output driving input(s); Warnings: unconnected nets, multiple net names on the same net, non-case distinct net names - kept as the 16-bit registry value `ERC` (default `0xFFFF`; bits 0 to 10 in that order). *Check* builds the netlist, then scans in TinyCAD's order: unassigned references, net names, duplicated references, missing parts of a multi-part package (under *Unconnected nets*), then the nets, whose type is worked out by a table of net type against node type. Every problem becomes a line of the Design Markers list and a red circle (a real `TDrawError` object, never saved or counted as a change) at the item; choosing a line selects its circle, shows its sheet, brings it to the front and puts it in the middle of the window, and clicking a circle selects its line. *Re-check* repeats the plain check, also after the VHDL one, as TinyCAD does. The VHDL check joins the nets of a bus into one set, never checks a labelled net that is not a bus, and ignores an output joined to an output. The PCB net list, Spice and VHDL commands run the check first (the VHDL command with the VHDL rules) and open the list only when there are errors. Positions in the messages are the internal units divided by five, printed as C's `%g` does (`FormatG` is an exact `%g`). Differences: the circles of an earlier check are removed at the start of each run (TinyCAD leaves that to the window being closed); hierarchical symbols are not followed, as in TinyCAD, whose ERC turns following off (`FollowImports := False`); a window left open by a command that finds nothing new is closed; the list lines drop the trailing line end; the *Generate Symbol References* button runs the command described next; lower-casing for the non-case-distinct names is ASCII only; the registry value is always written when the settings are saved. `tests/run_erc.py` (3909 checks) compares the check with a Python statement of the C++ for all 65536 option words, the samples, generated variants and two-sheet designs, in both modes; ninety mutations of `UErc.pas` were all caught or shown equivalent. `tests/run_ercdialog.py` (191 checks) drives the dialog, the window, choosing and clicking, the pre-checks, closing and saving.
- **Export Image (File > Export Image...):** `miExportImage` calls the published `TfrmMain.DoExportImage`; `BeginExportImage` (any drawing tool is put away; the dialog is filled) and `ExportImageFile` (keeps the choices, then saves) are what the dialog's buttons do, and `UExport` does the work. The dialog (`Fexport`, TinyCAD's `CDlgExportPNG`) has a *File type* list (colour PNG, B&W PNG, colour SVG, B&W SVG), the output file with *Browse...* (a `TSaveDialog` named `dlgSave` on the form), *Scale (%)* and *Rotate*. The file proposed is the design's name with the last extension replaced by `.png` (`output.png` for a name with no dot) and choosing a kind changes the extension of any name that has a dot; the scale (1 to 1000, a whole number) and the turn are dimmed for an SVG. With something selected only the selected objects are saved, on the smallest area round their `PointA`/`PointB`; otherwise the whole sheet with its border, title block and rulers; either way 10 units are added at the right and bottom and the picture is on white (as printing: no paper, grid or construction objects, nothing highlighted). A PNG is 1 pixel per unit (0.2 mm) at 100% and can be turned a quarter turn clockwise. An SVG is always the real size (127 dpi, one unit to the pixel of its own page, so 72/127 points to a unit), whatever the scale and turn. The choices are the registry values TinyCAD uses, `BitmapType` (0 to 3), `BitmapScaling` (default 100) and `BitmapRotation`, kept when Export is pressed. Differences: TinyCAD's two metafile kinds (EMF, Windows only) are SVG here; a selection's PNG is the area times the scale (TinyCAD multiplies the right and bottom edges, which makes the picture too big when the selection is away from the corner); the turn is exact (TinyCAD reads one pixel too far in each row); a file that cannot be written gives *Cannot write the image file.* (TinyCAD says nothing); an empty file name or a PNG scale outside 1 to 1000 keeps the dialog open with the reason. On Windows the Cairo canvas is left out (define `USE_CAIRO` to include it): it is linked when the program starts, so without `libcairo-2.dll` and its companions the program would stop at once with *DLL not found* (exit code `$C0000135`); a Windows build says that SVG needs Cairo and saves PNG only. `tests/run_export.py` (122 checks) compares the sizes, colours and positions of PNG files with numpy statements of the same rules, the turn with `numpy.rot90`, the SVG's page size and colours from its XML, the dialog and the registry, and the Insert menu's tool group.
- **Symbol editor (library list pop-up menu and Library menu):** a symbol of a library is edited as a document of its own (`TDocument.Symbol`, a `TSymbolEditor`; the document's design is in *symbol mode*, `TDesignFile.SymbolMode`, so every sheet is a part of the symbol, has no title block, pins of the parts not showing are hidden, the origin is kept, and undo reloads it that way). The commands, on the library list's pop-up menu and in the Library menu, act on the symbol chosen in the list: *New symbol* (an empty symbol, reference prefix `U?`, no name yet), *Edit symbol* (a symbol already being edited is just shown), *Duplicate symbol* (a copy in the same library, its names followed by ` copy`), *Delete symbol* (after asking; refused while the symbol is being edited), *Symbol properties* (the dialog on its own, **no editor tab**: OK checks the symbol as Store in Library does and stores the change in the library at once, Cancel or a refused change leaves the library file untouched; the drawing is not touched, though a store writes it again, so a symbol's stored XML may gain attributes such as `polygon='0'` and the symbol gets a new number in the file. If the symbol is already open in a tab, that tab is brought forward and the dialog changes the tab's copy, unsaved, so the tab and the library cannot disagree) and *Copy to* (the other open libraries). The drawing is made with the usual shape, text and picture tools and two more: *Pin* (Library menu, `vtPin`: a pin that counts on from the previous one, copying its length, direction, type and settings; it belongs to the part showing) and *Origin* (`vtOrigin`: the point a placed symbol is held by, drawn as a pale cross); both are refused in a design, and the tools that make a circuit (wires, buses, labels, junctions, no-connects, power, ladders, cross references, placing symbols) and extra sheets are refused in a symbol. The pin's name, number, length, direction, type (Normal, Dot, Clock, ...), electrical type, number position, shown name/number and centred name are in the Properties panel. *Symbol Properties* (`Fsymprops`, TinyCAD's `CDlgUpdateBox`): the names of the symbol (aliases; Add name starts as a copy of the name showing, Delete name keeps at least one), the description of the name chosen, the default orientation, and a grid of its attributes (Reference and Name first, which keep their names, then the others, each with a display method chosen from a list and a default value; Add / Delete attribute) and a SPICE tab (model, prolog, epilog and their priorities, kept as the hidden fields `$$SPICE`, `$$SPICE_PROLOG`, `$$SPICE_EPILOG`, `$$SPICE_PROLOG_PRIORITY`, `$$SPICE_EPILOG_PRIORITY`). *Parts per Package* (`Fsymparts`): 1 to 26 parts, and whether each part has its own drawing (heterogeneous: a sheet per part, tabs *Part A*, *Part B* ..., drawn as part 0) or all share one drawing whose pins are told apart by their part (*Previous Part* / *Next Part* choose the part showing); as in TinyCAD the kind can only be changed while the package has one part, making a package smaller removes the pins of the parts that are gone. *Store in Library* (also File > Save, Save As and Save All for a symbol): the Update Library window is shown first (Save All stores without it), the symbol is checked (`TSymbolEditor.Validate`: an empty or repeated name, a pin of a part the symbol does not have or two pins on one spot stop the store; no reference prefix, a pin with no number, pins off the grid, a repeated pin number, a part without pins, no pins are warnings shown in the status bar) and it replaces the symbol it came from (`TSymbolLibrary.StoreSet`: the new symbol is last in the library, its old rows are removed). The library of an open symbol cannot be closed or removed. Differences from TinyCAD: the checks and the warnings are an addition; Duplicate symbol and the `Copy to` pop-up are this port's names for what TinyCAD does by dragging in the library window; Pin and Origin have menu items only (no ribbon buttons yet); export/import of libraries and symbols (XML) is not ported; the symbol editor is a tab of the main window, not a separate window. `tests/run_symboleditor.py` (117 checks) works it all by script (`sym new= edit= store= delete= dup= copy= part= cmd= close=`, `symprops [lib=<library>:<symbol>] select= addname= cell=r:c:text ... ok=1`, `symparts parts= hetero= ok=1`, `symsets`, `syminfo`, `symmenu`) and checks the `Name`, `Symbol` and `Attribute` rows and the stored XML with Python's `sqlite3` and `ElementTree`; 19 deliberate faults (a store that forgets the drawing, a pin on the wrong part, a delete of an open symbol, a Cancel that applies, ...) are each caught.
- **Library manager (Library > Libraries...):** `mLibraries` calls the published `TfrmMain.DoLibraries`, which shows the *Library Setup* dialog (`Flibraries`, TinyCAD's `CDlgLibraryBox`): *Libraries in Use* (sorted by name), and the buttons *Add...* (one or more `.TCLib` files), *Remove*, *New...*, *Cleanup* and OK. As in TinyCAD the buttons act at once on the library panel and OK only closes the window (there is no Cancel); *Remove* and *Cleanup* need a selected library. The panel's list is the list of libraries in use: whenever a library is opened (Library > Open Symbol Libraries too) or closed (its pop-up menu) `TfrmMain.LibrariesChanged` writes it to the registry as `Library1`, `Library2` ... in the order they were added, and `RestoreLibraries` (called by `schematic.lpr` at start, before the designs are restored) opens them again, leaving out a file that has gone or is no longer a library. *New* puts `.TCLib` on the name (an other extension is replaced) and makes the three tables and the index TinyCAD makes; it never touches a file that exists. *Cleanup* runs SQLite `VACUUM` on the open library. *Remove* and *Cleanup* give TinyCAD's messages (*Cannot delete / cleanup a library while it is being edited ...*) when the library is in use (`TfrmMain.LibraryIsInUse`: a symbol of the library is open in the symbol editor; tests can also list files in `TestLibInUse`). Differences: TinyCAD keeps one comma separated value, `Libraries`, which cannot hold a path with a comma, so this port keeps `Library1...`; the list shows the file name without its folder (the full path is the list's hint); a library already in use is not added again (TinyCAD compares names, so two libraries called alike in different folders could not both be used); *Edit* and *Upgrade* (the old `.mdb`/`.idx` formats) are in the window and dimmed (*Edit*'s hint says where symbols are edited now: the library list), and an `.mdb`/`.idx` file is refused by *Add* with a message; library export/import (XML) is not ported. `tests/run_libmanager.py` (50 checks) works the dialog by script (`libraries select=.. add=.. new=.. remove=1 cleanup=1 inuse=..`, `librestore`, `libregistry`) and checks the lists, the messages, the files and the registry against Python's `sqlite3` and the file system, the new library's tables against the `CREATE TABLE` statements of TinyCAD's source, and the file size before and after the cleanup.
- **Insert menu tools:** the tool items of the Insert menu (and Edit > Select) are one group across all the submenus: `UpdateRibbonState` checks the item of the active tool and no other, whichever way the tool was chosen (menu, ribbon button or the end of a placement). `DoToolMenu` only starts the tool. `SetToolButton(Button, Tool, MenuItem)` registers both in `FToolButtons` / `FToolMenus`.
- **Printing (File > Print..., Print Preview, Page Setup..., Print Setup...):** `UPrint` holds TinyCAD's arithmetic and `src/UPrintRun` draws and sends the pages (a `TPrintSink`: the installed printer through the `Printers` unit, or A4 bitmap pages used when there is no printer and by the tests). The menu items come after Save All (Ctrl+P prints); Print, Print Preview and Page Setup need a design, Print Setup does not. The three system dialogs are non-visual components on the main form: `dlgPrint` (`TPrintDialog`, reached by the Print dialog's *Printer...* button for the printer, the page range and the copies), `dlgPrinterSetup` (`TPrinterSetupDialog`, Print Setup) and `dlgPageSetup` (`TPageSetupDialog`, used by Page Setup's *Printer Setup...* button to choose the printer's paper). The Print dialog (`Fprint`) is TinyCAD's: *Print current sheet* / *Print all sheets*, *Print in black and white*, *Scale (%)* and *Fit on a single page* (the box then shows the fit scale as `%3.3lg` and is dimmed; unticking it brings back the scale it began with). The scale must be above 0 and at most 10000. Black and white is kept as soon as it is clicked (registry `PrintBandW`, default off) and the scale when OK is pressed (`PrintScaleFactor`, printed as `%lg`, default 100; a bad value in the registry gives 100). The pages are as TinyCAD cuts them: the sheet at the print zoom, `dpi*1000/(5*254)` (an integer division) times scale over 10000 printer pixels to an internal unit, laid out from the top left, down each column first; a part of a page left over counts as a page unless it is 0.01 of one or less; printing all sheets goes round the sheets fastest. A page shows the sheet's border, title block and objects but not the paper, grid, shadow or construction objects (rulers); in black and white everything is black, and a fill that is not white is black. Print Preview (`Fpreview`) shows the same pages in a window with Next/Prev Page, One/Two Page, Zoom In/Out (three steps) and Print... (which goes on to the Print dialog); the pages it draws are the ones printed, smaller. Page Setup's *Printer Paper* and *Printer Setup...* buttons put the printer's page (whole millimetres, the longer side along the sheet's longer side) into the width and height boxes and choose the matching paper; with no printer they say so. Differences: with several sheets of different sizes, printing all sheets uses the active sheet's size for the layout, as TinyCAD does; the C++ divides by zero for a scale so small that no page is wanted (here there is at least one page); the scale limits (above 0, at most 10000) are new (TinyCAD takes any number); with no printer OK is dimmed; the system's Print dialog is used for the printer, range and copies in place of the MFC one, so its look is the platform's; copies are sent as repeated passes (collated or not) unless the printer makes them itself. `tests/run_print.py` (3473 checks) compares the arithmetic with a Python statement of the C++ (1500 random layouts, fit scales, scale text and value, ranges); `tests/run_printdialog.py` (1569 checks) drives the dialogs and compares every printed page with where the design's coordinates, the page's corner and the zoom put its filled squares and lines: the fill is inside, and nothing else is on the page. **Pages box:** the Print dialog has a Pages group, *All pages* or *Pages from ... to ...* (the edits are enabled by the second choice and start at 1 and the number of pages); both ends must be whole numbers from 1 to the number of pages or the dialog stays open with a message (the pages are then printed from the lower to the higher if reversed). Differences from before: a range past the pages used to print nothing, it is now refused. `tests/run_printdialog.py` covers it (1578 checks).
- **Generate Symbol References (Special > Generate Symbol References...):** TinyCAD's annotate, ported into `UAnnotate` (with `AddReference`, `RemoveReference`, `SetRefVal`, `GetRefVal` and `SetPart` on the placed symbol) and the dialog `Fannotate`. The dialog has *Add References* / *Remove References*; *All References*, *Un-numbered References* or *References matching:* (a symbol's reference prefix such as `U?`, compared exactly) with *All Sheets*; *Default start value* or *Start at value:* (typing in the box chooses it; the box is read as Windows' `GetDlgItemInt` does: an optional minus and digits, anything else gives 0); and *Use reference painter*. The choice of references and *All Sheets* are kept as TinyCAD's registry values `Annotate.type` (default 1, un-numbered) and `Annotate.allsheets` (default on) by OK and are what the dialog shows next time whatever it was given; the rest is kept for the run of the program. OK makes two passes over the sheet (or all sheets), taking the symbols in order of the centre of their box, row by row from the top: the first takes away the number of the matching symbols that have one (with *Start at value*, only those numbered at least the start value), the second, if the action is *Add*, gives each matching symbol the next free number from 1 or from the start value, past the numbers that symbols with the same prefix on the searched sheets have. A package of several parts that are alike in outline gets the next part of the last symbol of its kind on its own sheet before it gets a new number (the symbol is moved so its first static pin stays put). A symbol with no definition is left alone and a message says so. The whole command is one undo step. The reference painter (the dialog's last button) is a tool: a click on a symbol gives it the next number from the start value, a right click takes its number away, Esc or another tool ends it; each click that changes something is one undo step. Starting the command puts any drawing tool away, including the painter. The Design Markers window's *Generate Symbol References* button runs the same command. Differences: the C++ sorts with `std::sort`, which does not keep the order of two symbols whose centres are the same (this port keeps their drawing order); the C++ opens an undo change for each sheet (here the command is one step); placed designs (hierarchical symbols) are numbered with the symbols, as TinyCAD does (prefix `H?` from symbol number 0, counted with other symbols of the same prefix; one whose design cannot be read is left alone and reported; the designs inside are not entered, as in TinyCAD; the reference painter is for placed symbols only); the registry values are written whenever the settings are saved (the C++ writes them on OK), and a value outside 0 to 2 is put right; the painter acts when the right button goes down (TinyCAD waits for it to come up, to tell a click from a pan, which this tool does not have); a number of more than nine characters gives an empty number, as the C++'s ten-character buffer would fail. `tests/run_annotate.py` (2218 checks) compares the command with a Python statement of the C++ on the samples, generated designs (references taken away or numbered twice, odd references such as `U0A5`, parts and parts per package changed, two sheets, symbols with no definition) and the painter's clicks; `tests/run_annotatedialog.py` (111 checks) drives the dialog, the undo, the painter tool and the window's button.
- **Netlist writers (Special > Create PCB Net List..., Create Spice Net List..., Create VHDL file):** the writers of `NetList.cpp` and TinyCAD's PCB Export dialog. *Create PCB Net List* asks for a
  format - *TinyCAD*, *PADS-PCB*, *PADS-PCB-WITH-VALUE*, *Eagle SCR*, *Protel*, *gEDA PCB*, *XML* - a file (proposed as the design's name with `.net`, or `output.net`; choosing a format changes the extension: `.net`,
  `.scr` for Eagle, `.net.xml` for XML, a `.net` before the last dot going first; *Browse...* picks a file) and the *Prefix symbol references with sheet number* choice. The choices are kept as TinyCAD's registry
  values `Netlist` and `PrefixNetlist`, also when the file could not be written, but not by Cancel. Every writer builds the netlist first (which, as in TinyCAD, stores the net numbers in the design), then
  writes the components - each distinct reference once, in drawing order (the XML lists every placed symbol) - and the nets in ascending number order, named by their first label or by `N` and six digits;
  PADS and Protel lines wrap after 127 characters (characters, not bytes), gEDA PCB after 41 pins, Eagle puts nine parts to a row, and XML is printed as rapidxml prints it. The prefix choice changes nothing,
  as in TinyCAD. *Create Spice Net List* and *Create VHDL file* ask for a file in an ordinary Save dialog (proposed with `.net` / `.vhd`). SPICE writes one line for each reference that has a pin on a net, by
  expanding the symbol's `$$SPICE` field (`$(field)`, `%(pin)` the net name at a pin number or pin name, `@(pin)` the net number, `?(test,then,else)` with `defined`, `not_defined`, `empty`, `not_empty`,
  `connected`, `not_connected`, `\` to quote), with the `$$SPICE_PROLOG` and `$$SPICE_EPILOG` lines before and after in order of priority, and a list of the problems found (a pin with no name or number, repeated
  pin names or numbers, a symbol with no model, a macro that cannot be resolved) in a file beside the netlist with `.txt` for its extension; a message says how many. VHDL writes an entity whose ports are the
  symbols named `INPUT` and `OUTPUT`, a component for every other symbol name (its input pins, then its output pins), a signal for every other net, and a port map for every reference; names and pin names
  such as `D(7:0)` and `Q(3)` are buses and bus members. Differences: the output is UTF-8 and has the platform's line ends; TinyCAD opens the file afterwards
  in an editor (this program does not; SPICE shows the error count in a message); one message, *Cannot write the net list file...*, serves the three writers (TinyCAD's text names the parts list); in the C++
  snapshot the SPICE model line prints an empty string where the expanded model belongs (the call to `expand_spice` is missing) and this port prints the expansion; the epilog lines are filed under the
  symbol's *prolog* priority, as in the C++; hierarchical symbols are followed (the nets pass through them, see *Hierarchical designs*), so the nodes of the designs they place are in the netlist; text with a percent sign in a VHDL name is written as it is. The date in the first line of
  a SPICE file is `mm/dd/yy at hh:mm:ss +zzzz`. `tests/run_netwriters.py` (561 checks) and `tests/run_spicevhdl.py` (230 checks) compare the writers with separate Python statements of the C++ on every sample design,
  hundreds of generated ones and 720 random SPICE macro texts, and the SPICE file TinyCAD itself wrote for `FunctionalUnit.dsn` and its error file match byte for byte (but for the date), as do its netlist in TinyCAD's own format and 14 VHDL
  files once net numbers are matched up (three of the VHDL files predate the shortened port map entries); `tests/run_netdialog.py` and `tests/run_spicevhdldialog.py` run the real dialogs.
- **Turning and flipping a picture:** Rotate left, Rotate right and Flip (the buttons of the ribbon's Home tab; Ctrl+L and Ctrl+R) now turn the picture itself, not only the corners of its box. TinyCAD moves the
  two corners and nothing else, so a picture that has been turned is squeezed upright into the turned box (and its picture painters guess the turn from the signs of the box, which is wrong for
  a flip); here each picture has an **orientation** (UOrient), a 2 x 2 matrix of 0, 1 and -1 that every turn or flip multiplies by that operation's matrix, exactly as the corners move, so
  what is shown in the box is the picture turned or flipped. Turning a selection that holds pictures and other things turns them all together about the selection's centre. The picture is
  drawn by an **exact rearrangement of its pixels** (none lost or blurred, once per orientation and then kept), then stretched into the box as before. The orientation is kept by undo and redo,
  copy and paste, Copy to and Import, and resizing by the handles; in the file the `METAFILE` element gets two optional attributes, `rot` (quarter turns to the right) and `mirror` (flipped
  left to right first), **written only when the picture is not upright**, so a picture that was never turned is written exactly as TinyCAD writes it, and TinyCAD, which does not know the two,
  skips them and shows the picture upright in the turned box as it always has. A picture that is part of a symbol is turned and flipped with the symbol, whatever way the symbol is placed.
- **Old binary .dsn files (File > Open, read-only conversion):** TinyCAD's files from before it wrote XML open as well. `UDsnBinary` is a port of the C++ loader (`CTinyCadDoc::ReadFile` and each object's `Load`/`OldLoad`): the file is recognised by its stamp (`TinyCAD`, a revision of at most 6 and the number 0x0C5A, which an XML file cannot have), so nothing about the name or extension matters, and the objects are read into the sheet in the new objects' form (so `xLine`, `xLineEx`, `xCircle`... become the newest kinds; the resource tables are renumbered as `CDocResource::Add`/`ConvertOld` would). The result opens as a new **unsaved document** named `<file> (converted)`: the original is never written, and Save writes the XML format (Save As starts from the original's name with the extension replaced). The status line says what was done. Strings may be one byte (Windows-1252) or UTF-16, lengths of any size, as `CArchive` writes them. A file that ends early, holds a symbol saved as XML, or nests symbols without end loads what came before and the status line says the file ended early; a file with nothing readable is refused. The oldest placed symbols store only a library symbol name: `LegacySymbolFinder` (set by the main form to look in the open libraries, first match by name ignoring case, as `GetSymbol` does) supplies the symbol, which is then kept with the design; a name that is not found becomes the "no symbol" stand-in and the status line names it. Title block dates are shown in UTC. Differences from the C++: `xLineEx` / `xArcEx` keep their thickness (the C++ converts the new style number as if it came from the file's table and loses it); a polygon handle of the control kind (never written by the old program, with no control point in the file) becomes a plain corner (the C++ leaves a NaN that only non-trapping floating point survives); a truncated file keeps the objects before the break (the C++ throws away the rest too but reports a failure). Quirks followed as written: `xCircleEx` has no thickness byte, note text with no text shows `Note`, polygons from the file are not closed, a font number nothing matches is font 0 (but -1 matches the last unclaimed default). `tests/run_dsnbinary.py` (240 checks) writes the files itself from the C++ field orders (`tests/dsnbin_gen.py`, not from the Pascal reader) and compares the XML that comes out with hand-derived values: every object kind, the stamp and the string forms, resource renumbering, symbols, every cut of a file, random damage, and the opening in the program. **No real old files were available:** this has been tested with synthetic files only, so real `.dsn` files from the old program would be the proper confirmation.
- **Import:** Ctrl+I reads another design into the sheet (TinyCAD's File > Import). Its objects follow the mouse, as a paste does
  (the same placement, one undo step called Import, right click or Esc to cancel, which puts the sheet back exactly as it was).
  Only the first sheet of a file with several sheets comes in, the file's page details (size, title, rulers) are not applied, and
  its fonts, styles, fills and symbol definitions are merged with the design's. Old binary designs can be opened (see below) but not imported.
- **Copy to:** Ctrl+E saves the selected objects of the sheet as a design file of their own (TinyCAD's "Copy to", "export
  selection to a file"): the sheet's name and details, the fonts, styles and symbol definitions the selection uses, and the
  objects themselves. It is the same data as Copy puts on the clipboard, and the file opens like any design. Differences from
  TinyCAD: only the resources the selection uses are written (TinyCAD writes every one the sheet uses), and the document is
  not marked as saved (TinyCAD clears its unsaved-changes mark, which looks like an oversight).
- **Find (the panel):** Ctrl+F is TinyCAD's Find. It hides the symbol library panel and shows the find panel
  (`frameFindPanel`, a `TfrFindPanel` from `QFindPanel`, created by `FormCreate` in code and owned by the form, so the form
  file does not need it) in the left panel. Type the text and press Enter or Find: every
  object of the design, on every sheet, that mentions the text is listed once in `lbFindResults` as `<name>: <text>`
  (not case sensitive, the text anywhere in it; what is searched is the text of labels, texts, notes and power symbols, pin names
  and every field of a placed symbol), as TinyCAD's Find lists them. Each gets a heavy red circle on the sheet, dark red,
  and bright red for the entry that is chosen. Clicking an entry brings its sheet (and its document) forward with the circle
  in the middle of the window; clicking a circle on the sheet chooses its entry; the red X in the upper corner (the first picture of the main form's `ilTinyIcons` image list, set
  with `UseCloseIcon`; or Esc in the entry) closes the find, takes the circles away and brings the library panel back. The circles belong to the view, not to
  the design: they are never saved, undone, copied or netlisted. A find belongs to the document it was made in.
- **Find and Replace:** Ctrl+H opens the dialog (the `ReplaceDlg` component), F3 finds the next and
  Shift+F3 the previous. It searches every sheet, in the order of the design, and wraps round, with the same searchable text
  as Find. Options: match case, whole words (a word has no letter, digit, underscore or non-ASCII character
  next to it) and direction. A hit is selected, its sheet shown and scrolled into sight. Replace changes the hit and
  moves to the next (one undo step each); Replace All changes the whole design as one undo step. (TinyCAD's own "Replace" is for
  replacing a symbol, which is separate.) The dialog's "Search entire file" box is hidden, since a search always covers the whole design.
- **Settings and recent files:** the settings that are kept between runs are the fields of one record,
  `ProgramSettings` in `consts.pas`, saved and loaded by `USettings` with TRegistry under
  `HKEY_CURRENT_USER\SOFTWARE\HPL Software\TyCAD Electrical` (`REG_HPLSOFT_KEY`), each field as a value of its own;
  a new setting is a new field and a new value. The first setting is the recently used files: the last four opened or
  saved, newest first, as the values `MRU1` to `MRU4`. They are listed in the File menu between Save As and Exit; a file
  opened again moves to the top; one that has been deleted is taken off the list when chosen. Off Windows the FPC
  Registry unit keeps the same keys in a file (`~/.config/TyCAD Electrical/reg.xml`).
- **Polygon editing:** select a polygon and its handles appear (small black squares, and the control point of a
  curve). Drag a handle or a control point to reshape it. Right-click the polygon for Add handle, Delete handle,
  Free line, Arc in, Arc out and Curve (Add handle splits the segment at the click; Delete handle removes the nearest
  handle, a polygon keeps at least two, or on a control point just makes the segment straight). While drawing a
  polygon, a right click offers Finish polygon, Cancel drawing and the kind of segment for the next points. Right-drag
  still scrolls; only a right click that did not move opens the menu. As in TinyCAD a curve is saved as `arc="0"` with
  a `control` point.
- **Rulers and border on the ribbon:** the details panel (Show rulers, columns, last row, Border, margin) shows the
  current sheet's settings and writes them back, so they can be changed without opening Design Details (which keeps
  the same settings on its Page frame page). The check boxes apply at once; the entries apply on Enter or when the box
  is left, by the same rules as the dialog (columns 1 to 26, a row letter A to Z, a margin in mm that fits the page);
  an entry that is refused goes back to the sheet's value and Esc reverts. Each is an undo step, and the panel follows
  undo and redo, the Design Details dialog, switching sheets and documents. With no document it is disabled.
- **Design Details and Page Setup:** Design Details (Ctrl+D) edits the current sheet's title block text, whether the
  title block is shown, the rulers (drawing frame), the border, automatic sheet numbers and the revision history;
  With automatic sheet numbers the title block's Document box shows this sheet's number and its Sheets box the number of sheets in the file; the two entries are greyed out in Design Details and in the New Document dialog (the texts typed there are kept in the file and come back when the numbering is switched off). `$(DOCNO)` and `$(SHEETS)` follow the same rule. Test: `tests/run_autonumber.py`, plus the DOCNO / SHEETS variables in `tests/run_docmodel.py`.
  Page Setup sets the paper and orientation (or a size in mm, up to 2500 mm a side), optionally for every sheet.
  The title block and rulers are drawn on the page as TinyCAD draws them. Both are one undo step each.
- **Grid:** the Snap and Grid size buttons, Grid size up (the next larger preset, wrapping to the smallest) and a custom
  size typed in the number dialog (`Finput`, a comma is accepted as the decimal point).
- **Sheets:** add (the + tab at the end of the sheet tabs, or the Add sheet command), rename (button or double-click the
  tab), move left or right, and remove (a design keeps at least one sheet). Each is one undo step and the tabs follow
  undo and redo.
- **Drawing tools** (ribbon, Draw tab): wire, wire label, junction, line, polygon, rectangle, circle,
  arc, note, cloud, horizontal and vertical ruler guides (TinyCAD's `RULER`), and an A-to-B measuring
  ruler that shows the distance. Wires are drawn by a port of TinyCAD's own line tool, so they snap to
  pins (and to power symbols, input/output labels and other wires), merge with collinear wires, split a
  wire when another starts in its middle, and get junctions automatically, as in TinyCAD. Click-click
  or press-drag-release both work; the 90 degree mode draws an L as two wires.
- **Grid:** Snap-to-grid toggle and a grid-size button (0.5 to 10 mm, or custom) on the Home tab.
- **Undo / redo:** every change is one step (Ctrl+Z / Ctrl+Y); history is whole-design snapshots.
- **Properties on the ribbon:** there is no Properties tab any more: the panel of the selection (`plPropsProperties`, behind a 2 pixel separator `pnlPropsSep`) is at the right end of the **View** ribbon, shown only while something is selected, so properties and the view settings (grid, snap, zoom) can be used together. Selecting something brings the View tab forward (`PROPS_TAB`). Selecting something opens the View tab with editors for it. With
  several objects selected it shows the properties they share (a differing value is blank or
  "(mixed)") and a change applies to all of them. Editors are created at run time from the selection.
- **Line-number links:** the Ladder tab's "Line link" and "Contacts link" tools make a text that shows
  the rung (of the sheet's rung grid) its target sits on, or the lines of the other symbols sharing its reference ("2.21" =
  sheet 2, line 21). It updates after every change (move, renumber, delete) and is stored by object id.
- **Moving and dragging:** dragging a selection moves it and the wires attached to it follow (a port of
  TinyCAD's `CDragUtils`): wires ending at a moved object's connection points stretch with it, wires attached
  to the middle of those wires follow along, and junctions are tidied when the mouse is released. Hold Ctrl to
  move the objects without dragging wires. As in TinyCAD a stretched wire may become diagonal, and a pin that only
  touches the middle of a stretched wire, or net labels, are left where they are.
- **Copy, cut, paste, duplicate:** Ctrl+C, X, V, U (Duplicate, as in TinyCAD) and buttons on the Home tab. The clipboard uses TinyCAD's own
  format (registered name "TinyCAD Design", the sheet XML for the selection), so you can copy in TinyCAD and paste
  here and the other way round; text on the clipboard is tried as drawing XML as TinyCAD does. After a paste the
  block follows the mouse (its bottom-right corner under the pointer) until a click drops it; a right click or Esc
  throws it away. Not done: TinyCAD also puts a picture (metafile) on the clipboard and pastes pictures; this does neither.
- **Not done yet:** the symbol (.TCLib) editor's window, printing and plotting, hierarchical designs beyond loading and saving (see *Hierarchical designs*), editing the
  handles of an existing polygon or arc, properties for pins/symbol fields beyond reference and name. Pin and
  power-symbol shapes, hatch fills and note-text wrapping are approximations of TinyCAD's drawing.
- **Behaviours inherited from TinyCAD's code** (read from the source, not compared with a running
  copy): drawing a wire exactly over another leaves overlapping wires; a polyline that doubles back
  over itself shortens the wire; a junction can be created twice at one point.
- **Source comments:** every procedure and function has a block above it (name, parameters, returns, notes). `tools/doccomments.py` regenerates them (notes in `tools/notes`); `tools/check_comments_only.py <backup folder>` proves a change touched only comments.
- **Testing without a person:** `schematic --script file` runs a script against the real window
  (see `UScript.pas`) and saves screenshots; `tests/run_gui.py` uses it.

## Property frames (your own layout of the Properties panel)

A frame designed in the Lazarus IDE replaces the built-in editors of a tool (Draw ribbon) or of the selection (Properties tab). The frames of this project are in
`src/frames`: `QPropBase` (the base: `lbCaption` and a virtual `AfterCreate`), `QPropWire` (wire, bus, line), `QBus` (bus: the wire panel and the Phases button, `bmDrop` mode, linked to `bus.phases`), `QRectCircle` (rect, circle), `QPolygon` (polygon), `QArc` (arc: the in / out radio buttons are `bmRadio` editors of `arc.type`, each captioned with its choice; the Arc tool is the Polygon tool with arc segments, every click after the first turning the next arc in or out), `QCloudNote` (cloud), `QPropText` (text),
`QPropWireLabel` (label), `QPropNote` (note), `QPowerSym` (power) and `QMeasure` (measure); `QPropFrameList.RegisterAllPropFrames` says which frame serves which key.

* **Linking a control to its property.** A control whose name ends with the property key (dot removed, case and underscores ignored, longest key wins) needs nothing:
  `edText` is `text`, `cbFillType` is `fill.type`, `seLineWidth` is `line.width`, `cbFontColor` is `font.color`. For other names the registration has a list:
  `'cbWireColor=line.color'`; `'fseScallop=cloud.bump:lbScallop'` also hides the caption `lbScallop` when the tool or object has no such property; `'cbFill='` says a control is not an editor.
* **Controls that fit a property** (anything else is disabled and listed in the problems): text TEdit or TComboBox (font name); integer TSpinEdit or TComboBox (font size, number as text);
  fractional TFloatSpinEdit; color TColorButton; yes/no TCheckBox or TSpeedButton (stays down, `GroupIndex` is set when it has none); choice TComboBox, or a TCheckBox that is ticked
  when the choice is not the first (Fill None / Solid ...; it may share the property with the combo box), or a TSpeedButton that steps through the choices (the power symbol's
  direction: Up, Right, Down, Left; its `ImageIndex` is `PropDirGlyph` + the position, see `consts.pas`).
* **Lists.** A choice list that has no items gets the choices; a list the frame filled with the right number of items (blank, drawn as pictures by `OnDrawItem`) is kept and the choice is
  taken by position. Line styles are drawn by the program unless the frame draws them.
* **Events** are attached by the program (OnSelect, OnClick, OnColorChanged, OnEditingDone ...); a button's own `OnClick` is still called first.
* **Hiding.** An editor for a property the tool or selection has not got is hidden (with the captions named in the list); a panel or group box whose editors are all hidden goes too.
  `AfterCreate` of a frame (derived from `TfmPropertyBase`) is called after it is made, before its controls are linked.
* **Caption.** A frame whose `lbCaption` is visible says what the panel is itself (for a selection, the caption shows what is selected) and the program's label is not shown;
  a frame that hides `lbCaption` keeps the program's label.
* **Which frame.** Tools by their name; a selection of one kind of object by that kind (`PropFrameKeyOfObject`); a tool or kind with no frame, and a selection of several kinds,
  use the built-in editors. The width of the panel is the width of the frame as designed.
* Keys: text, dir, label.style, power.type, font.face, font.height, font.bold, font.italic, font.color, line.color, line.width, line.style, fill.type, fill.color, poly.closed, cloud.bump,
  measure.unit, measure.ticks, ruler.pos, xref.mode, xref.target, xref.prefix, xref.suffix, ladder.left, ladder.right, rungs.rows, rungs.start, rungs.margin, rungs.pages, rungs.continue, rungs.showheight, sym.ref, sym.name, sym.canscale, sym.scalex, sym.scaley, pin.name, pin.number, pin.length, pin.numpos, pin.dir, pin.shape, pin.elec, pin.showname, pin.shownumber, pin.centre.
* Self-test script: a script starts with no frames (the built-in editors); `registerframe x all` registers the real ones, `registerframe <key> demo|bad|none` the demo frames, `frameinfo tool|sel`
  lists what is linked, `frameact tool|sel <control> click|choose|text|color <value>` does what a person does, `sharedinfo <names>`. `tests/run_propframes.py` tests the mechanism with the demo frames
  (`QDemoWireProps`, `QDemoBadProps`), `tests/run_realframes.py` the real ones.

## Shared controls

`FSharedCtls` (`frmSharedControls`, created first in `schematic.lpr`) holds the dialogs and image lists the forms use: `OpenDlg`, `SaveDlg`, `PrintDlg`, `dlgPrinterSetup`, `dlgPageSetup`, `ReplaceDlg`,
`ilSpeedBtn`, `ilTinyIcons`, `ilListBoxImages`, `ilPowerGlyph`, `ilFontGlyphs`, `ilNewDocument`, `DlgColor` (the Options colors), `dlgExportSave`, `dlgLibAdd`, `dlgLibNew`. A form file cannot name a component
of another form, so the main form takes them in `FormCreate` (fields of the same names, so the code that used them is unchanged), the speed buttons get `ilSpeedBtn` there, and the other forms use
`frmSharedControls.<name>` directly. Add a new dialog or image list there.

## Netlist notes

- Connectivity follows the C++ code step by step: a point-keyed node map (points within 0.001 are
  the same point), wires joining their end nets, junctions joining the wires they sit on, labels
  joining the wire they sit on and equal labels joining each other, power symbols and hidden power
  pins joining by name, then `Link` merging nets across sheets by label and choosing a name
  (a power name beats a label; otherwise `_N_<n>`).
- `ApplyHints` renumbers nets from the per-pin hints stored in the placed symbols and writes the
  numbers back, so building a netlist **changes the design** (it gains `HINT` tags when saved),
  exactly as in the C++ program. That is what keeps net numbers stable between runs.
- **Multi-part symbols and older files.** The sample designs and their real netlists were made by an
  older TinyCAD. For a multi-part symbol whose parts have different extents (a 74LS08 whose part 0
  carries the power pins), the current C++ source computes each part's reference point from that
  part's pins only, which moves the other parts' pins by one or more grid steps relative to the
  wires saved in the file. With that geometry only 125 of the 163 nets in the sample netlists are
  reproduced; with the older rule (other parts' pins also count towards the extent,
  `USymbols.LegacyPartExtents := True`) all 163 are, with identical net names and components.
  The default follows the current source; the file format does not say which rule a design was
  drawn with, and `REF_POINT` is only ever saved for part 0.
- Hierarchical sheets and symbols are loaded, saved and drawn (see *Hierarchical designs*); the netlist and the parts list follow the levels (see *Hierarchical designs*); annotate numbers the placed designs (`tests/run_annotatehier.py`, 112 checks plus two source mutations caught). The writers
  for the other formats are in `UNetWriters` and `USpiceVhdl`. The sample `FunctionalUnit - Spice.net`
  (and its `.txt`) and the VHDL files under `vhdl/nibbles` are real outputs of TinyCAD that the tests use;
  they were made by an older TinyCAD that numbered nets from 0, so VHDL names such as `N00` are matched
  up by order before comparing. `FunctionalUnit.net` (TinyCAD's own format) is compared the same way (net names
  `N000000` ... renumbered by order).

## Geometry notes

- Loading never computes layout, so files load and save the same whatever the text metrics.
  Call `TDesignSheet.UpdateLayout` after loading (and again when the metrics change).
- **Text metrics are pluggable** (`TDocOptionsBase.Metrics`). The C++ program measures text with
  Windows GDI, which cannot be reproduced exactly elsewhere. `TApproxTextMetrics` (Arial-like
  widths) is the default; `TFixedTextMetrics` is for tests; a Lazarus front end should supply one
  based on `TCanvas.TextExtent`. Pins, labels, text, power labels (and later symbol bounding
  boxes) are only as exact as the metrics given.
- `TDocOptionsBase.ZoomFactor` (click tolerance), `EditLibrary` and `EditPart` stand in for the
  view/document state the C++ objects read from their document.
- Faithful C++ behaviours worth knowing: a query exactly on an object's bounding-box edge counts
  as outside; polygon bounding boxes are truncated to integers (up to 1 unit smaller than a
  curve); rectangle and polygon distances are capped at 100; `CArcPoint::operator=` copies only
  x and y (so rotating a polygon swaps in/out arcs and rotates control points separately).
- **Placed symbols.** A symbol's drawing is copied per (part, power) choice, shifted so its
  reference point is the origin, and cached (`TSymbolInfo.GetView`). The reference point is the
  saved `REF_POINT` when there is one, otherwise the snapped far corner of the drawing kept on the
  first visible pin's grid. Saving after `UpdateLayout` writes any reference points created this
  way, as the C++ program does. The default text metrics emulate the C++ program's 5x "datum"
  font measuring, per-glyph rounding, `lfWidth` scaling, and an empty string measuring (0, 0).
- Validation of the above on the sample files: all 259 saved reference points are accounted for;
  230 are reproduced with the file's own settings, and the other 29 only when the grid is set to
  what it was at placement time (26 with grid 10, 3 with snapping off; the file does not record
  that). The two C++ coordinate paths agree on all 2,688 visible pins of the 1,182 placements.
- C++ inconsistencies that are reproduced rather than fixed: the reference point counts
  invisible (power) pins but the symbol size does not, so such a symbol's bounding box can be
  offset from its visible pins (130 placements across the sample designs and library symbols);
  a reference point saved under a different grid than the current one has the same effect;
  `GetTr` uses part 0's size for every part of a non-heterogeneous symbol.
- Deliberate deviation: a zero-width/height ellipse (a dot drawn as an ellipse; it occurs in the
  sample libraries) yields NaN in the C++ code and could never be selected; here it is treated as
  the point or line it is.

## Known limits

- Not yet ported: word-wrapped note-text layout, 
  and everything that paints or edits (mouse handling, undo, selection).
- Text metrics are an emulation, not GDI: widths can differ from the C++ program's by a pixel or
  so, and anything snapped to a grid can then land one grid step away. Plug in
  `TCanvas.TextExtent` in the Lazarus front end for exact on-screen agreement.
- `REF_POINT` entries are preserved as loaded; the C++ program also generates new ones while symbols are placed.
- Hierarchical symbols are kept on load and their designs are drawn (the netlist and the parts list follow the levels; annotate does not yet). (The legacy binary format is read, see *Old binary .dsn files*.)
- Resource numbers settle after two load/save passes (the loaders re-add a copy of each style, as in
  the C++ code); content never changes.
- Constructor defaults that come from UI state (current font/style, default pin length) use fixed values.
- `StoreSet` also deletes the superseded drawing row (the C++ code left it behind as an orphan).

Note for headless runs (`resizewindow <w> <h>` in a script gives the window a larger drawing area; the tests that read pixels use it): with GTK2 under Xvfb the main form can loop forever in size-allocate when the default font is wider than the one the form was designed with (seen with Inter; DejaVu Sans is fine). The tests were run with a fontconfig file that makes `sans` DejaVu Sans (`FONTCONFIG_FILE`). The main form is 1450 pixels wide at 120 PPI for the same reason (the menu and ribbon cannot fit in less).

## To do

Larger features: hierarchical designs, step 4 (tests with real hierarchical files; netlist, BOM and annotate are done).

## Hierarchical designs (steps 1 and 2: load, save, insert, draw; step 3: netlist and parts list)

A hierarchical design is a design with a *hierarchical symbol sheet*: a sheet that draws the design as a symbol (an outline and its pins) so that another design can place it. Step 1 keeps these files whole; step 2 adds the commands and reads the placed design so it is drawn with its pins.

- **The hierarchical sheet:** a `<HierarchicalSymbol>` (or the old spelling `<HierachicalSymbol>`) sheet inside `<TinyCADSheets>` is loaded as an ordinary sheet flagged `IsHierarchicalSymbol`. As in TinyCAD its name is always "Hierarchical Symbol" (the NAME in the file is ignored, and written as that name) and it cannot be renamed. Pins can be placed on it with the Library > Pin tool (a normal sheet refuses them; the origin tool stays for library symbols).
- **The placed design:** `<HIERARCHICAL_SYMBOL>` / `<HIERACHICAL_SYMBOL>` is loaded as `TDrawHierarchicalSymbol` (a `TDrawMethod` with a design file name): position, rotation, scaling, `can_scale`, the fields and `file`. The Name field is saved empty and shows the design's file name (a shown field called "Design"). Select, move, copy, paste, delete and undo work. The parts list and annotate skip it, as TinyCAD does; the netlist follows it (below).
- **Reading the design:** the first time it is needed (drawing, hit tests, pin positions) the placed design reads the hierarchical symbol sheet of its file (`HierarchicalLoader`, set by `UDesign`, `LoadHierarchicalObjects`): the file must be a `TinyCADSheets` design; the objects are read without the details block, with the fonts, styles, fills, pictures and symbols of the file merged into the design the symbol is in; a later symbol sheet in the same file replaces an earlier one. `TDrawHierarchicalSymbol.Load` then works out the box round the objects, snaps it to the grid (keeping the first visible pin on the grid) and moves the objects so the box's corner is the origin; the size it keeps is used for scaling and for turning, and `GetTr` gives the pin positions for a rotation. A design that is missing, is not a design, has no symbol sheet or has an empty one is drawn as TinyCAD draws one it cannot load: a 50 x 50 square outline; the reason is kept in `LoadError`.
- **Commands (Special menu):** *Insert another design as symbol...* asks for a design (TinyCAD file filter), reads it and makes it follow the mouse until it is clicked (not offered on the hierarchical sheet or while a symbol is edited); *Add hierarchical symbol* (also in the Sheet menu) adds the symbol sheet in front of the other sheets with the paper, title block and grid of the sheet shown, as one undo step (a design has only one); with one placed design selected, *Reload symbol from design* reads its file again, *Change design of symbol...* gives it another design file as one undo step (a file that cannot be read changes nothing) and *Open design of symbol* opens its file in a document. The items are enabled as in TinyCAD (`HierarchyMenuOpen`).
- **File names (`UXMLPath`):** saved relative to the design file with backslashes (`.\x`, `..\x`), turned back into full native paths on load (TinyCAD's `formatXMLFilename` / `unformatXMLFilename`). Windows drive and network names are kept as they are on Linux.
- **Differences from TinyCAD:** the message about a design that cannot be read is shown by the command that asked (insert, change, reload), not each time a design is first drawn; an earlier load is dropped when a reload fails (TinyCAD keeps it); a symbol sheet with no objects counts as not loaded (TinyCAD reads past the end of an empty list); `GetTr` is the design's own size (TinyCAD asks the symbol table, which has nothing for a design, so its pin positions come out wrong); a changed design has its labels laid out again for the new size; a missing design with no symbol sheet in an existing file draws the 50 x 50 box (TinyCAD leaves the size unset there).
- **The netlist follows the levels** (`UNetList`, a port of `CNetList::MakeNet` with `CImportFile`): every placed hierarchical symbol loads its design (`TDesignFile.LoadFromFile`) as a new *import* with the next context instance number (the root is 0; a design placed twice is two instances; numbers are handed out in the order found, level by level), and with the path of the symbols leading to it (`H1/G1`) as context. The symbol's pins become nodes of that instance, labelled with the pin name; every label inside an instance is made unique with its number (`_HN_<n>_<name>`), so the pin and the label of the same name inside the design meet in `Link`. The reference of a symbol's pins carries the path (`H1_G1`; `TNetList.GetReferencePath` / `GetPartialReferencePath`). The name a net is given is the one at the lowest level; a label below the root gets the path in front (`H1_Z`, `H1_G1_W`), root labels are unchanged; power symbols stay as the C++ has them (their names are made per instance too). More than 100 imports stops the following; designs that cannot be read are skipped and listed in `ImportErrors`. `FollowImports := False` keeps to the root design (ERC does that, as TinyCAD does). The designs read stay alive as long as the netlist (the nodes point into them). Differences: the C++ finds an import by using its instance number as a list position (wrong once a design fails to load); this port looks the number up. The Protel, PADS, Eagle, gEDA, XML and Spice/VHDL writers use the nets as they come, so they carry the hierarchical references.
- **The parts list follows the levels** (`UPartsList`, `AddLevel` = `GenerateBomForDesign(level, ...)`): with *Include all hierarchical links* a placed symbol loads its design and lists it before going on, with the same reference paths as the netlist (`TNetList.GetReferencePath`). `tests/run_hierbom.py` (34 checks: nested samples, all formats, attributes, sheets, the option off, a missing design, a design placed twice, changing a child, three source mutations caught) needs `bomtest` built.
- **Real files:** `tests/data/hier/tCad1.dsn` and `tCad2.dsn` (written by TinyCAD 3.00.04: a design with a one-pin symbol sheet, and a design placing it) read and behave as expected, and show that the 'No Symbol Defined' entry (symbol 0) really has the reference prefix `H?` that placed designs are numbered with; `tests/run_realhier.py` (4 checks). They have no labels or parts, so they do not exercise the nets across levels.
- **Not done yet:** following the levels in ERC (TinyCAD does not either) and annotate, and tests with real hierarchical files.
- **Tests:** `fpc -Mobjfpc -Sh -Fusrc -Fusrc/forms tests/drivers/hiertest.pas`, then `python3 tests/run_hierarchical.py` (file names, sheets, round trips and the program: 101 checks) and `python3 tests/run_hiernetlist.py` (the netlist across levels, needs `nettest` too: 23 checks - generated three-level designs with two copies of one design, nets, instance-qualified names, the net names, the references of pins, not following, a missing design, a design placing itself, and mutations of the design and of the source) and `python3 tests/run_hierarchical_load.py` (reading the design: 44 checks - 90 random designs against a Python statement of `Load`, `ExtractSymbol` and `TranslatePointToDesign`, the designs that cannot be read, and the menu commands in the program).


## Labels, text and the text box

- **Label outlines (`TSchematicPainter.PaintLabel`)** are TinyCAD's `CDrawLabel::Paint`, for all four directions: two long sides and, at each end, an arrowhead (one text height deep) or a flat closing side. An *input* has its arrowhead at the end that attaches to the wire, an *output* at the far end, an *input/output* at both; the other end is closed flat. (An earlier version drew a plain rectangle for Up and Down and open or wrong shapes for Left and Right.)
- **Attachment box:** a small red square (4 design units) is drawn on the point a label (its connection point) or a text (`PointA`) is attached to, as TinyCAD does.
- **Text direction (`TextDir`, `TDrawText.UpdateLayout`):** the attachment point is always where the text starts, except Left. *Up* reads upwards (rotated 90 degrees counterclockwise from horizontal) from the anchor; *Down* reads downwards (rotated 90 degrees clockwise) from the anchor; *Right* reads left to right starting at the anchor (anchor at 0); *Left* also reads left to right but ends at the anchor (anchor at the width). TinyCAD itself read both vertical directions bottom to top and put the box of a Down or Left text on the wrong side of its anchor; the box (selection handles, hit test) now follows the drawn text. Files from TinyCAD (direction 3, Right) are unchanged.
- **Properties text box:** selecting one text object puts the focus in the frame's `edText` with all the text selected (`FocusTextEditor`). Del removes the selected text only; Del in the empty box deletes the object (`PropEditKeyDown`).
- **Floating text:** with the Text tool chosen the next text follows the pointer (`TSchematicView.FloatingText`) until a left click places it, then the one after it follows; a right click (or Esc) cancels and returns to Select. The Text tool's Draw-ribbon panel shows the **text box and the direction list** (and font), so they can be set before placing: the floating text and the text placed use them, and after a placement the box shows the next text, counted on. The Label tool works the same way (text, direction and type in its panel, a floating label, counted on after each placement; the Properties tab is no longer forced forward when a label is placed). **Esc** drops the drawing tool also when the focus is not on the sheet (for instance in the tool's own text box); on the sheet it keeps its old order (first end what is being drawn).
- `tests/run_labelshapes.py` (83 checks) reads the rendered sheet (which end is an arrowhead and which is flat, for 3 styles x 4 directions; where each text's ink lies against its attachment box; Up and Down equal the horizontal text turned with PIL) and the focus / Del / floating behaviour by script (`addlabel`, `addtext x y text dir`, `focusinfo`, `editdel`, `floatinfo`).
- **Font name and size boxes:** Enter (or closing the list) applies what the box says, so a font found by typing no longer needs the list opened again (`PropComboKeyDown`, `OnCloseUp`).
- **Text / Label tool box:** choosing the tool (and each placement) puts the focus in the panel's text box with its text selected (`FocusToolText`), and every keystroke there becomes the text of the floating text or label at once (`PropEditChange`). The focus can only move when the Draw tab is the one showing.
- **Ghosts:** the Junction, No-connect, Power and Bus-slash tools show what a click will place, following the pointer (`MakeFloat`, drawn in `PaintPreview`), made as the placement makes it with the tool panel's choices. (They are drawn at the snapped point; the placement itself still sticks to a pin or wire end.)
- **User font (`TSchematicView.FUserFont`):** a `TFont` set to the design's default text font when a design is loaded or made (`InitUserFont`). Choosing a tool whose objects have a font (text, label, note ...) starts its panel with that font (`ApplyUserFont`); changing the font in a tool's panel updates it (`SetToolDefault`), and each object placed gives its font back to it (`TakeUserFont`, in `AddNew`), so the font asked for follows the person from tool to tool. The power symbol has no font of its own in this port, so it neither takes nor gives one.

- Wire tool ghost: the segment being drawn uses the tool panel's properties (width, style; line colour for the Line tool, red for wire and bus until confirmed) and the view repaints when a tool property changes, so the ghost follows the width. `tests/run_wireghost.py` (7 checks) measures the ghost's thickness in the rendered form against the placed wire. `frameact tool <spin> text N` sets a number box.

## Source style
- The statement after `then` or `else` goes on its own line, indented 2 more than the `if` (`then begin`, `else begin` and `else if` stay on the line). `python3 tools/fmt_ifthen.py file.pas ...` rewrites files to this style; it only changes white space (it refuses a file if anything else would change) and `--check` just lists the files it would change. The whole source was converted with it.
- Property frames: a frame that labels itself (lbCaption, or a caption on each panel as the Note frame has) never gets the form's own "Properties" / selection label added (`FrameLabelsItself`). The Note tool offers its text and direction like the Text and Label tools.

- Notes: the text wraps at the words when a line reaches the edge of the box (inside a 3 unit margin), and at its own line breaks; a word wider than the box is broken between letters (`TSchematicPainter.WrapText`). What is typed in the Note tool's text box is the text of the notes placed. `frameact` takes the rest of the line as its value, so a text may hold spaces. `tests/run_notewrap.py` (3 checks).

- Line styles at high zoom: a pen 2 pixels or wider (zoom 150% and more for a thin line) is drawn solid by the system, so the Line tool dashed it itself. Rectangle, circle, polygon / arc, note and cloud now do the same: the fill is drawn with no pen and the outline is laid over it in dashes (`DashedPen`, `DashedPath`, `EllipsePath`, `RoundRectPath` in UPainter.pas); the pattern runs on round the corners. `tests/run_dashzoom.py` (10 checks).

- Wire angle: the Wire, Bus and Line tools have an Angle list (Free, 90 degrees, 45 degrees = UEdit.TAngleMode; the text is UProps.AngleChoices, the property 'wire.angle' is the tool's own, `WireAngleDef`, linked to `cbAngle` in `WireLinks`). The choice is used by the tool at once and is kept for the whole program session in `WireAngles` (UView), so another tool, sheet or design still has it. A wire starts at 90 degrees, a bus and a line free. `tests/run_wireangle.py` (10 checks); script commands `comboitems tool|sel <control>` and `wireinfo`.

### Power tool panel and selection caption
The Power tool now shows its text box and direction button while the tool is active (they were hidden because the tool defaults only kept `text`/`dir` for Text, Label and Note). The typed text is used for the symbol placed. A selected power symbol (and bus, bus slash, no connect, pin, picture) is named in the frame caption instead of showing the class name (TDrawPower).

### The Fill button and its menu (Rectangle / Circle)
The Fill check box, the type list and the color button of the Rectangle / Circle panel are one button, `bbFill`, linked to `fill.type` (`'bbFill=fill.type'`; QPropFrame mode `bmFill`, any TBitBtn bound to a choice). It shows the fill as a 32 x 32 picture (`DrawFillGlyph` in FFillDropDown: white box, 1 pixel black outline, the pattern in the fill color) and drops `frmFillDropDown` down from itself.

- **Telling the menu:** `SetFill(choice, color)` (the style as the position in `UProps.FillChoices`, not the menu position: the menu has Vertical before Horizontal); it draws the color on `imgColor` and highlights the current style.
- **The answer:** `OnPick(Sender, AChoice, AColor)`; the main window applies what changed (color, then style; the Fill button's color is the tool's or the selection's `fill.color`). Choosing a color while the fill is None makes it Solid. Two properties are two undo steps.
- **Mouse wheel / keys:** wheel up/down and Up/Down move the highlight and stop at the first and last item; Home, End; Enter or Space chooses; Esc closes; pointing at an item highlights it. The menu closes when it loses the focus; a click on the button while it is open closes it (`JustClosed`).
- **Frames:** `FillChoices` is now in the UProps interface. The Note panel (`bbFill` in qpropnote) uses the same button.
- **Also fixed:** the new `cbViewPositionShow` check box called `DoShowPosition` from its own OnChange while `ShowPositionBar` set it, which recursed until the program crashed at start; the check box now says what is wanted, and setting it is not a request.
- **Test:** tests/run_filldrop.py (glyph pixels counted against the geometry, menu order, wheel, keys, Enter, Esc, color, objects and undo); script commands `filldrop`, `frameglyph`, `filldropshot`, `frameact ... bbFill pick <choice> [hex]`.


## Library export / import (XML) and the SQLite library

- Library ▸ **Export Symbol…**, **Export all Symbols…** and **Import Symbols…** (also in the library list's popup) read and write TinyCAD's XML library format (`<Library><SYMBOL>…`), so libraries can be exchanged with TinyCAD. Importing a file twice adds the symbols twice, as TinyCAD does. Import is refused while a symbol of that library is being edited; export is refused over the file of an open library. Code: `src/ULibXML.pas`; test: `tests/run_libxml.py`.
- The SQLite library is now loaded from the program's own folder by full path first, then from the system path. When it fails, the message says why: the file is missing, is the wrong bitness (a 32-bit `sqlite3.dll` needs a 32-bit program and a 64-bit one a 64-bit program), is not a DLL at all, or could not be loaded (Windows error number given; the Visual C++ runtime may be missing).

## Viewport rulers (`UViewRulers`)

The View tab's position panel has a **Show Rulers** check box (`cbShowViewRulers`) under Show Bar, and the View menu has **Show Viewport Rulers** (`miShowViewRulers`); both are the same switch and it is saved (`ShowViewRulers`, default on). Two strips (`TViewRuler`) sit on the outside edge of the drawing area, one above and one to the left, in mm or inches as the sheet's units say, counted from the sheet origin (so a set origin moves the zero). Marks are 1-2-5 steps at least 60 px apart for the numbers, with finer ticks of at least 4 px; a red line follows the pointer. The strips redraw whenever the view scrolls or zooms. Tests: `tests/run_viewrulers.py`.

## Right-click menu of the sheet

A right click (without dragging) in the Select tool opens TinyCAD's pop-up menu. The common commands are the design-time `pmSheet` of the main form (edit captions and keys in the Lazarus designer); `TfrmMain.BuildContextMenu` only puts the object-dependent items in front and sets what is enabled: Undo, Redo, Z-Order (Bring to Front, Send to Back), Cut, Copy, Paste, Duplicate, Select All, Delete, Rotate Left, Rotate Right, Flip, Zoom In, Zoom Out, with the keys that do the same. The object under the click is chosen first (a chosen group stays chosen). What depends on the object comes first, followed by a separator:
- a polygon (on a handle or near a side): Add handle, Delete handle, Free line, Arc in, Arc out, Curve — they act on the side nearest to the click;
- a placed symbol: **Replace Symbol...** — the new symbol is the one chosen in the library list; Yes keeps the old field values, No uses the new symbol's. The name follows the new symbol, an unnumbered reference (U?) takes its letters, a numbered one stays, the lowest pin stays where it was; one undo step.
- a line, wire or bus: **Make horizontal** / **Make vertical** — the end nearer the click stays, the other end lines up with it (one undo step; nothing happens if it is already straight);
- a placed design (hierarchical symbol): **Reload symbol from design** and **Open design** (no Replace Symbol); Test: `tests/run_contextmenu2.py`.
**Alignment panel and Align to Grid.** The Position ribbon panel is now Alignment: Show Bar, Show Rulers and a 1 px grid check box (grayed unless a symbol is being edited). 1 px grid only changes how the grid dots are drawn: one screen pixel at any zoom (dark grey, so it can be seen) instead of growing with it; a normal dot of 3 pixels or more has a darker centre pixel to show the exact grid point (`GridDotSize`, `TSchematicPainter.OnePxDots`, `TDocument.OnePxGrid`), for fine work on wire and pin alignment; the grid spacing and snapping are not touched (an earlier version wrongly set the grid to 1 unit, which hid the dots below 600% and filled the page grey above it). Z-Order > Align to Grid (`miAlignToGrid`, in the sheet pop-up, shown only in symbol editing) calls `TSchematicView.AlignSelectionToGrid`: each selected object is shifted, not reshaped, so its first end (`PointA`; the connection end for a pin) is on the nearest dot of the sheet's grid (the grid before 1 px grid was ticked). One undo step. Test: `tests/run_alignment.py`.

**3-phase bus.** The Phases button of the Bus panel (tool and selection) drops `frmBusDropDown` down: 1 phase / 3 phase, then the wire spacing as 1 to 5 times the grid, a custom whole-number multiplier of the grid, or a spacing typed in millimetres (bottom box). The panel (like the Fill menu, a `TfrmDropDownBase` in FDropDownBase, which holds the shared popup code) stays open after a choice and applies it at once. The user draws the middle wire; `ReconcilePhases` (UPhases, run in `CommitChange`) makes the other two as ordinary buses on either side (mitred at corners), all three sharing the group number `phgroup` (`phase` -1/0/+1, `phgap` the spacing, saved as extra attributes so TinyCAD reads three plain buses). Click or a drag to the right on any wire selects all three; a drag to the left must take in all three. A symbol put on the free end of a 3-phase bus is copied to the other two ends (independent symbols). Changing the spacing rebuilds the outer wires (symbols on their ends are not carried along); pasted / duplicated groups get new group numbers. Test: `tests/run_busphase.py`.

The **Arc tool** has its own right-click menu: Arc in / Arc out (the kind of arc it draws) and Cancel drawing. Test: `tests/run_contextmenu.py`.

## Font sizes are points

A font is kept as TinyCAD keeps it (LOGFONT height, pixels of a 96 dpi screen: 16 pt Courier New is height 21 in a file); the Size box and the `font.height` property show and take **points** (`FontPointsOf` / `FontHeightOf` in `UProps`: pt = round(height * 72 / 96), height = round(pt * 96 / 72)). Before, the pixel height was shown as the size, so 16 pt showed as 21 and 14 pt as 19. Typing the size the font already shows leaves its stored height alone. The default text (13 pixels) shows as 10 pt. Test: `tests/run_fontsize.py`.

**Text anchor:** a straight text shows TinyCAD's small red attachment square only while it is selected (`PaintText`, the box is always red even though a selected object is otherwise drawn in the selection colour); labels keep theirs all the time. `tests/run_labelshapes.py` checks both.

**Wire end squares:** a chosen wire, bus or line shows TinyCAD's small light gray squares (`PaintLineHandles`, painted by the view after the sheet, so printouts and exported pictures do not have them) at both ends. Test: `tests/run_wirehandles.py`.

**Connect ring:** the red ring shown where a wire being drawn sticks to a pin, wire end or wire (and while the wire tool hovers, before the first click) is TinyCAD's 10 design units from the centre (`HIGHLIGHT_SIZE`), i.e. 10 × zoom pixels, so it grows with the zoom; it was half that. The snapping range is the Auto-snap range of Options (15 design units, as TinyCAD). Test: `tests/run_connectring.py`.

**Pin hot spot:** every pin of a placed symbol (and of a symbol being edited) has TinyCAD's very light gray square (RGB 208, 2 design units across, `PaintPin`) on its connection end, on the screen only: not in a printout or an exported picture. Test: `tests/run_hotspot.py` (new script commands `centeron`, `zoomfactor`).

**Line widths and zoom:** as in TinyCAD (`CContext::SelectPen`), a pen of width 1 is one pixel at every zoom, so wires and the usual lines, polygons, circles and rectangles do not get thicker when you zoom in; only a wider pen (bus, a line given width 2 or more) grows with the zoom, and on a printout or exported picture every pen is scaled (`TSchematicPainter.SetPen`). Test: `tests/run_linezoom.py`.

**Text defaults and colour:** new text from the Text tool reads Right (direction 3) as in TinyCAD; before, only the Direction box said Right while the text was placed facing Up (`TDrawText.Create` starts at 0, so the tool sets it). The Text frame (`fmPropText`, shared by the Note frame) has a colour button right of the Italic button, bound to `font.color`; wire labels have no text colour, so it does nothing for them. On the View tab the 2 pixel separator is always left of the properties panel (`RebuildProps` sets their Left values). Test: `tests/run_textframe.py`.

**Sheet tab menu:** a right click on a sheet's tab at the bottom opens `pmSheetTabs` (a design-time `TPopupMenu` on the main form): Insert sheet, Delete sheet, Rename sheet..., Move Sheet left / right and Add hierarchical symbol, as in TinyCAD. The click first makes that sheet current, so the commands act on it. Items are off for the sheets of a symbol, Delete needs a second sheet, and Move left / right need a neighbour on that side. Test: `tests/run_tabmenu.py` (the Delete, Rename and hierarchical dialogs are not run by it).

**Current sheet marker:** the tab of the sheet the view is on carries an arrow. The pictures are `frmSharedControls.ilSheetTabs` (design time, 14 x 14; number 0 the arrow, drawn in the designer, number 1 empty; `MakeSheetTabMarks` makes a missing one in code, the empty one with the fuchsia transparent colour and one almost invisible pixel, because a picture that is nothing but the key colour came out black) and `tcSheetTabs.Images` points at it. The Windows tab control asks `OnGetImageIndex` (`SheetTabImage`: 0 for the view's sheet, 1 for the others, none for the "+" tab) only when it makes a tab, so after every change of sheet the tabs are made again (`QueueSheetTabRefresh` -> `RefreshSheetTabs` -> `RebuildSheetTabs`, run after the event that changed the sheet has finished). A single tab cannot be made bold or white (system tab control). Test: `tests/run_tabmarks.py` (which picture each tab asks for, not what Windows draws).

**Library preview:** a double click on the preview pane (`pbPreview.OnDblClick = ListDblClick`) places the chosen symbol, like a double click on the tree (it was a single click before). Test: `tests/run_previewdbl.py`. The unused empty `DoReplace` was removed from the main form.

## Window and splitter layout

On closing, the main window position and size (and whether it was maximised) and the splitter positions are saved in the registry (`HKCU\\...`, a file under HOME on Linux); on the next start they are applied once the window is shown, after the DPI rescale. A saved position that is off every screen is moved back (`FitSavedWindow`). Test: `tests/run_layout.py`.

**Design Markers window:** `TfrmErcList` is a plain `TForm` (it is not modal); its bottom panel `pnlButtons` (Close, Re-check) is drawn like `TfrmBase`'s button bar. Tests: `tests/run_ercdialog.py`, `tests/run_annotatedialog.py`.

**Print dialog: printers, pages and quick preview.** The *Printer* group is a drop down of the installed printers (`Printer.Printers`; with none it holds "No printer is installed" and is dimmed) and a *Printer Setup...* button that shows the system's printer setup dialog (`dlgPrinterSetup`, the one File > Print Setup uses); choosing another printer or accepting the setup lays the pages out again on that printer's page. The old *Printer...* button (the system Print dialog for page range and copies) is gone, so the number of copies is always 1 for now. The *Pages* box takes ranges and lists: `1-2`, `1 - 2`, `1-2, 6`, `1,2,6`, `1, 2, 6`, `1 to 6`, `1 and 6`, `1 through 6`, `1 to 6 and 9`. `-`, `to` and `through` join the ends of a range (a range typed backwards is turned round); `,`, `&` and `and` add pages; spaces and capitals do not matter. Every page must exist or the dialog stays open with a message; the pages are printed once each, in order (`ParsePageRange` and `PageListText` in `UPrint`, `TPrintOptions.Pages` in `UPrintRun`). The *quick preview* (`pbFastPreview`) draws the page showing with the same code that prints it (the main form's `PrintDialogPaintPage` calls `RenderPrintPage`), in the shape of the printer's page; the slider has one position for each page asked for, `<` and `>` step through them, and the label says "Page 6 of 12". Tests: `tests/run_printrange.py` (58 checks: the examples, 270 random and spoiled strings against a second reader, what is printed, the slider and buttons, the preview against the printed page, the printer list); `tests/run_printdialog.py` was updated for the new captions and menu places.


The Print dialog's Properties button opens the chosen printer's own properties window straight away on Windows (orientation, paper, quality), so the printer does not have to be picked again; on other systems it shows the system's printer setup dialog. Windows-only, not yet tried on a real printer.


**Color dialog under its button (Windows):** the color buttons of the property panels (`TColorButton`) call `osver.BeginColorDlgPlacement` from `TfrmMain.ColorButtonClick` (their OnClick, which runs just before the button shows its dialog); the hooks of the printer window placement (CBT hook, WinEvent hook, timer) then move the color dialog to the button's left edge with its top at the button's bottom, kept on the screen the button is on (above the button if it does not fit below). The hooks end by themselves once the window is placed. Color dialogs that come from a menu (or the Options dialog's Change buttons and the fill drop-down's Color... item) are not touched. Not testable on Linux (the button's click does nothing there).

**Text measuring (`UTextMetrics`, `TCanvasTextMetrics`):** TinyCAD measures text with GDI on a font made five times larger and divides by five; `UGeometry` only had a table of Arial widths (`TApproxTextMetrics`), so the box of a text, label or pin name (selection handles, hit testing, where the text sits) was only right for Arial. The program now measures with the real font of the sheet's font resource (face, bold, italic) on a scratch bitmap's canvas, at five times the size, divided by five, so the box covers the drawn text in any font. `schematic.lpr` turns it on (`UseRealTextMetrics`) unless it runs a script; scripts keep the table so that sizes do not depend on the machine's fonts (`metrics real|table`, `fontface <n> <name>` and `textbox <i>` are the script commands). A text's box is worked out when it is loaded or changed, so old files get the right boxes too. The test drivers still use the table. Test: `tests/run_textmetrics.py` (PIL measures the same TrueType files at five times the size).

**Select All Alike:** the sheet's pop-up menu has "Select All Alike" under "Select All": it selects every object on the sheet of the same kind (the same object type: wire, label, text, symbol, polygon ...) as the selected ones, which are what the right click chose; with two kinds selected, both kinds. Dimmed with nothing selected; no key; no undo step (a selection). Test: `tests/run_contextmenu.py` (the script command `selectalike`; counts against what the test put in).

**Del in a text box:** the Delete menu's shortcut (Del) is taken before the focused control sees the key, so it used to delete the selected object even while editing text. `FormKeyDown` now marks a plain Del pressed while a text box (edit, memo, editable combo box) has the focus, and `DoDelete` then edits the text instead: the selection, or the character to the right of the caret (Backspace, which is not a shortcut, takes the one to the left). Only in the empty text box of a single selected text, label or power symbol does Del delete the object. Test: `tests/run_labelshapes.py` (the script command `editdel` goes through the form's key preview, the menu shortcuts and then the box, as the keyboard does).

**Ribbon tab strip (`URibbon`, `TRibbonTabStrip`):** the headings above the ribbon (Home, Sheet, View ...) are drawn by the program on `pbRibbonDisplay`, moved out of `mainform.pas`. The strip knows the ribbon's page control (each page caption is a tab), the theme (`consts.RibbonThemes`) and which tab is under the pointer; it reports a left click through `OnChoose` (the main form's `ChooseRibbonTab`). `mainform.pas` keeps only the event handlers named in `mainform.lfm` (`RibbonTabsPaint`, `RibbonTabsMouseMove`, `RibbonTabsMouseLeave`, `RibbonTabsMouseDown`), which pass on to the strip. Same behaviour as before; checked by the `ribbonpaints` checks in `tests/run_gui.py`.

**Document tab strip (`UDocTabs`, `TDocTabStrip`):** the tabs above the drawing area are drawn by the program, not by the system tab control (which draws no close button on Windows). `frmSharedControls.ilDocTabs` (18 x 18) holds the pictures: 0 the close glyph, 1 the glyph with the pointer over it, 2 the document has unsaved changes. A tab shows the close glyph; a tab whose document has unsaved changes shows the mark instead until the pointer is over the tab (then the glyph, and picture 1 while the pointer is on the glyph; while the mouse button is held on the glyph picture 1 is drawn one pixel down and right, but only while the pointer is still on the glyph: moved off it with the button held the tab shows what it shows with no button held, moved back on it is pressed again; there is no picture for "pressed"). The tab's name is the document's name without the " *" (the Window menu still shows it). A left click on a tab makes it current (`OnChange`); button down and up on the glyph asks for the tab to be closed (`OnTabClose`: the main form closes it with the usual "Save changes?" question); down on the glyph and up anywhere else does nothing; a middle click down and up on one tab closes it; a right click makes the tab current before the pop-up menu (Close, Close all). Tabs are `DocTabHeight` (24) high on the bottom of a strip two pixels taller, 70 to 220 wide (a longer name is cut with ...), and the metrics are constants in `consts.pas` (`DocTabHeight`, `DocTabMinWidth`, `DocTabMaxWidth`, `DocTabPadLeft`, `DocTabGap`, `DocTabPadRight`, `DocTabArrowWidth`, `DocTabScrollStep`). The current tab is the window colour with a line of the highlight colour along its top and is open at the bottom; the others are a little darker, the one under the pointer lighter. When the tabs are wider than the strip two scroll arrows appear at its right end, the wheel scrolls too (90 pixels a step), and the current tab is always brought into view. Dragging a tab to change the order and a hint on the glyph are left out on purpose. Test: `tests/run_doctabs.py` (44 checks; the script commands `doctabs` and `doctab move|down|up|wheel|shot` work the real strip at real positions; layout arithmetic written again in the test, which documents are open, and the pixels of the saved pictures; deliberate faults in the click rule, the unsaved mark, the scroll into view and the pressed offset each fail it).

**Library panel order.** The symbols of each library are listed alphabetically by name, ignoring case (digits before letters, a plain character order: `R_VAR` comes before `RESONATOR` because `_` sorts before letters; `CompareLibNames` in `QLibPanel`). The libraries themselves stay in the order they were opened. Test: `tests/run_libsort.py` (43 checks over the example libraries; without the sort 24 fail).


### Wire end handles
A wire picked by a click, or only touched by a selection box, is stretched by dragging one of its end handles (the other end stays). A wire wholly inside the picking box (or after Select All) is moved by them, like the rest of the wire. Test: `python3 tests/run_wireends.py` (needs `TC_GUI_BIN`).

### Title block notes cell, Apply to All
The NOTES and REFERENCE cells above the extended block are now as high as the Title cell (two block lines, 36 units). The Details tab of Design Details has an **Apply to All** button: it copies that tab's settings (title, author, organisation, document number, date, sheet numbering, title block and extended information shown) to every sheet as one undo step, "Design details (all sheets)"; the other tabs (revisions, notes, rulers, border) are left as each sheet has them. Test: `python3 tests/run_applyall.py` (needs `TC_GUI_BIN`).

### Rotating a floating paste
Ctrl+L / Ctrl+R are now the shortcuts of the main menu's Rotate Left / Rotate Right (Ctrl+L was also on Open Symbol Libraries, which no longer has a shortcut), so they work while a pasted block floats; the block turns about its centre, stays under the pointer and the rotation is not an undo step of its own (the drop commits one "Paste"). A shortcut lives on a menu item only, never also in the view's key handler, so nothing fires twice. Test: `python3 tests/run_pasterotate.py`.

### Which text measuring runs
Help > About shows `Text measuring: real fonts` (the program's normal mode) or `table of Arial widths` (what scripts and tests use). If a text's box does not fit its text, check this line first.

The real-font measuring is now also the default set by `UTextMetrics` itself (its initialization), so a project file that does not call `UseRealTextMetrics` (a regenerated or older `schematic.lpr`) still gets it; `schematic.lpr` only switches back to the table for scripts.

### Rung grid above the title block
The rung grid is resized from a single **bottom-centre handle** (select tool, resize cursor): dragging it sets the table's bottom edge (saved as the `bottom` attribute of `<RUNGS>`, distance from the sheet bottom in mm; width, left and top are unchanged); the Properties frame no longer has an Above block check box. Test: `python3 tests/run_rungbottom.py`. The legacy **Above block** option (`rungs.aboveblock`, `setrungs ... <aboveblock>`, still read from old files; any bottom drag takes over from it): its bottom edge is then the top of the title block, or of the extended cell above it when that is shown, and the bottom indent is ignored. The block position is asked of the sheet every time the grid is measured or drawn, so changing the title block, the extended information, the rulers or the paper moves the table. When the sheet shows no title block the grid ends at the bottom indent as usual. Test: `python3 tests/run_rungabove.py`.

### Paste position, plain lines
Paste puts the objects exactly where they were copied from (as TinyCAD does; they show at once and follow the pointer from the first mouse move), so duplicating a page onto the next is a paste and a click. Test: `tests/run_pastepos.py`. A plain line (not a wire) now has the wire's end handles: a clicked or partly picked line is stretched by an end, a wholly picked one is moved by it (`tests/run_lineends.py`).

**Rung font across sheets.** A rung grid made on a sheet when another sheet already has one starts with that grid's font and colour (the sheets before it first, then the ones after), not Arial (`TSchematicView.TakeRungFontFromOtherSheet`). Only font and colour are carried; rows, margin and the rest keep their defaults. Test: `tests/run_rungfontsheets.py` (3 checks; without the call the second check fails).

**Clipboard keys in text boxes.** Ctrl+C, X, V, A, Z and Y are menu shortcuts, and a menu shortcut gets the key before the control with the focus, so a text box on the main window could not paste (the key went to the drawing's paste, which found nothing). `FormKeyDown` now marks the key when a text box or memo has the focus and the Cut, Copy, Paste, Select All, Undo and Redo handlers call `EditShortcutInBox` first, which does the command on the text (the same way Del already worked). Combo boxes are not covered. Only checked by build: scripts cannot send keys.

**Split button (`src/comp/CSplitButton.pas`, class `TSplitButton`; add `src/comp` to the unit search path).** A button with two parts: the main part runs `OnClick` (released over the main part, like any button), the arrow part opens `DownArrowPopup` (separate from the right click `PopupMenu`) at the left edge of the arrow part, 1 pixel below the button (after `OnDropDown`, so the menu can be filled first, and `OnDropDownClick`, the arrow-click event for an owner that shows a form instead of a menu: leave `DownArrowPopup` empty then; the arrow shows pressed while it is open). Drawn with the platform theme as one button frame with a divider between the parts (only the half the mouse is on is drawn hot or pressed); the arrow is a small triangle drawn in code (no symbol font; its size follows the button's height). Properties: `Caption`, `Color` (used only with `Transparent` off: the button is filled with it first), `Images`/`ImageIndex`/`ImageWidth` (which size of a multi-size image list to draw, 0 = the list's own), `ArrowWidth` (16), `Flat` (no frame until the mouse is over it, as a flat TSpeedButton), `Checked` (the main part shows pressed in, also when flat) and `AutoCheck` (a click on the main part toggles it before `OnClick`), `DownArrowPopup`, `Hint`, `Action`. Like a `TSpeedButton` it has no window of its own (`TGraphicControl`): `Transparent` (default) paints nothing behind it so the parent, a ribbon say, shows through, and it takes no keyboard focus (no keys). Use: `B := TSplitButton.Create(Self); B.Parent := ...; B.DownArrowPopup := PopupMenu1;` or register the unit in a package to put it on the palette (page "Additional"; the palette icon is in `CSplitButton.lrs`, included by the unit). Test: `tests/run_splitbutton.py` (builds `tests/drivers/splittest.pas` and drives the control's own mouse and key handlers; 21 checks, mutation checked). Not checked on Windows: how the theme draws the two halves side by side.

**Library panel tabs.** `QLibPanel` has a page control with two tabs: *Symbols* (the filter, the caption and the tree of the open symbol libraries, as before) and *Parts* (empty until the parts library is built; see `docs/parts_schema.sql`). The preview and the splitter stay below the tabs. The symbol tree's code and names are unchanged, so scripts and tests work as before.

**Ribbon: split buttons (24x24 glyphs).** The Close button (`sbCloseDocs`) has Close All in `pmCloseDocMenu`; Alignment (`sbView`, a check button: down = the Position bar is shown, `DoShowPosition`) opens `pmAlignmentOptions` (Show Rulers, 1 px grid: menu items now, toggled by their handlers). On the Details panel `sbSheetDetails` is a check button for the rulers (replacing the Show rulers box) and `sbExtendedInfo` a toggle speed button for the extended information (replacing the Extended info box); the arrow of `sbSheetDetails` (`OnDropDownClick`) shows `FDetailsDropDown` (`TfrmDesignDetailsDropDown`: Border, Margin, ruler Columns / Rows, and a Show rulers box that follows the button). Its controls are reached as `frmMain.DetailsDrop.*`; the Sheet ribbon tab no longer exists (merged into Home; `run_ribbontools.py` updated). Tests: hints_theme, alignment, ribbontools, extblock, position, viewrulers, splitbutton. Not checked on Windows.

**Parts database design (docs/parts_schema.sql, draft 3; no program code yet).** Two levels: a generic *Part* (class, symbol, child objects, the ratings the design requires) and a *Product* (manufacturer, model number, actual ratings, documents, 3D model, footprint, offers). A sheet places generic parts and the details name the product; a bigger product than required is fine, a smaller one, a missing rating or a different coil voltage is reported by the verify check (views `ProductFit` and `ProductFitSummary`, judged by each quantity's `Sense`: min / max / match). What the .dsn stores and the rules of the check are in `docs/parts_design_storage.md`. Symbols are the same TinyCAD XML as a .TCLib symbol; part icons are PNGs in several sizes (`PartGlyph`). Tests: `tests/run_partsschema.py` (22 checks, the verdicts are re-worked from the raw rating rows, mutation checked) and `tests/run_partsupgrade.py` (8).

**Parts database reader (`src/UPartsDb.pas`, `TPartsLibrary`).** Opens a TyCAD parts file through `sqlite3dyn` (the DLL is loaded only when a parts file is opened) by the rules of `docs/parts_upgrade.py`: current version as is; older: backup `<file>.v<old>.bak`, one transaction per step; newer, or not a TyCAD parts file (a TinyCAD `.TCLib`, a text file): refused without writing. Reads the library name and GUID, the class tree, the parts (sorted by class then name), a part's icon (`GlyphPng`: nearest size to the wanted one, the larger on a tie), its required ratings (`Ratings`) and the products of its class with their fit verdicts (`Products`, from the schema view `ProductFitSummary`). No UI yet (the Parts tab is the user's). Script commands for tests: `pdbopen`, `pdblist`, `pdbglyph`, `pdbratings`, `pdbproducts`, `pdbupgrade`. Test: `tests/run_partsdb.py` (14 checks against Python's sqlite3 on the sample file; mutation checked on the icon tie rule and on the newer-file refusal).

**Parts tab (placeholder controls in `QLibPanel`).** The Parts page has a label, an *Open parts library...* button (`btnPartsOpen`, dialog `dlgPartsOpen`, `*.TCParts`) and a list view `lvParts` (report view, columns Part and Class) with the 24x24 image list `ilParts`; restyle them as you like, the code only needs these names. `OpenPartsFile(file)` opens the file through `TPartsLibrary` and lists the parts with their icons (the stored size nearest to 24, scaled if it is another size; a damaged PNG leaves the part without an icon); a file that cannot be used leaves the list as it was and `PartsError` gives the reason (the button shows it in a message). Events `OnPartSelected(index)` and `OnPartPlace(index)` (double click) are there for the owner; nothing is placed yet. Script command `pdbtab open|rows|pixel|select`. Test: `tests/run_partstab.py` (7 checks; the icon colours are read back from the stored PNGs). The last parts file is not remembered between runs yet.

**Placing a part (Parts tab double click).** `TfrmMain.PlacePart` reads the part's schematic symbol (`Symbol.Drawing`, TinyCAD XML, the part's `BaseDefault` symbol first) with the same loader as a library symbol, gives it the part's name and reference letters (`Part.RefPrefix` + `?`, `U?` when empty) and the GUIDs of the part and of its library (`TDesignFileSymbol.PartUID` / `PartLibraryUID`: in memory only, not saved in the .dsn yet), and starts placing it. Before the first part of a run a task dialog warns that the design will no longer open correctly in TinyCAD (Cancel places nothing; "Do not show this again" is kept in the settings as `PartsWarningOff`); the warning is shown once per run. The warning is ahead of the storage: until the .dsn keeps the part details a design with parts still opens in TinyCAD. A part without a symbol is not placed. Script commands `pdbplace <row> <x> <y> [yes|no]` and `pdbwarn off|on|ask`. Test: `tests/run_partsplace.py` (10 checks, mutation checked on the refusal). Not checked: the dialog itself (the script answers it), the setting round trip through the registry / ini file.

    python3 tests/run_symbolframe.py       # the symbol property frame and parameter list (TinyCAD's symbol tool options): direction, mirror, Ref, power pins, resizing, parameters (needs the built program and the example libraries)
    python3 tests/run_i18n.py              # translation: template up to date, strings vs the compiler's list, Format counts, and the program run in a made-up language (needs the built program and xvfb)
    python3 tests/run_pinframe.py          # the pin property frame (TfmPin): bound editors, values, changes and undo, two pins together (needs the built program and the example libraries)
    python3 tests/run_symbolfont.py        # Options > Fonts: the symbol font (face, size, bold, italic) applied to the design, kept, given to new designs, refused when unusable (needs the built program and the examples)
    python3 tests/run_viewmenu.py          # View menu mirrors of ribbon tools: Snap to Grid, Show Rulers, Show Detailed Block, Grid Size submenu agree with the buttons (needs the built program and the examples)
    python3 tests/run_partsbom.py          # parts list columns for placed parts (manufacturer, model number, status, fit), grouped by product (needs the built program)
    python3 tests/run_partcheck.py         # the parts check of Check Design Rules: products against the part's requirements, warnings / errors / oversized info (needs the built program)
    python3 tests/run_partsdetails.py      # placed part details: Manufacturer / Model number, Choose Product window, fit words, remembered parts file (needs the built program)
    python3 tests/run_partsdsn.py          # part data in the .dsn (see docs/parts_design_storage.md)

Right click on a wire: **Add wire cut here** (first item of the menu, only when the wire is the one chosen and the click is not at an end): the wire becomes two wires that meet at the grid point nearest the click (or the nearest point of the wire when the grid point is off it), one undo step. Test: `python3 tests/run_wirecut.py`.

Arrow keys on the sheet (select tool): the chosen objects move one grid step (snap to grid on) or one screen pixel (snap off), as one undo step; attached wires follow like in a drag and a chosen wire moves whole. Test: `python3 tests/run_arrownudge.py`.

Find and Replace dialog: **Search entire file** ticked searches and replaces on every sheet of the open document (not the other documents), unticked only on the sheet shown (Find Next wraps within it; status bar says "sheet"). **Prompt on replace** ticked makes Replace All show each occurrence and ask Yes / No / Cancel; every replacement is its own undo step. Script: `replace <text> <with> all [sheet] [prompt:<y/n/c letters>]`. Test: `python3 tests/run_findscope.py`.

Find panel (Ctrl+F): the **Search all Sheets** box (`cbFindInAll`, ticked by default) lists the objects of every sheet of the document; unticked, only those of the sheet shown (and only those get red circles). Entries read `sheet name: object: text` (`Sheet 2: Label: VCC`; a sheet without a name is "Sheet N"). Test: `python3 tests/run_findpanelscope.py`.

Rotate Left / Right / Flip (Ctrl+L, Ctrl+R) while a symbol is being placed turn the symbol that follows the pointer (as R and X do). Test: `python3 tests/run_ghostrotate.py`.

Font drop-downs (TFontNameCombo) search as you type again: keys within 1 s of each other make one search (C, O, U finds Courier), a key after a longer pause is searched for alone. Test: `python3 tests/run_fonttypeahead.py`.

Double clicking a placed symbol puts the focus in the reference box (edRef) of its property frame with the reference selected (a single click only chooses it). Test: `python3 tests/run_symreffocus.py`.

A middle (or right) button press and release during a left button drag (rubber band, move) no longer cancels the drag or starts a pan. Test: `python3 tests/run_middlewhiledrag.py`.

Sheet tabs menu: **Insert sheet** puts the new sheet right after the one clicked (sheet 3 clicked: new sheet 4, old 4-9 become 5-10); the ribbon's Add Sheet still adds at the end. Test: `python3 tests/run_insertsheet.py`.

Copying / pasting / rotating / exporting a selection that holds the rung grid and other objects works: objects without corner points (the rung grid) are left out of extents (`HasCorners`). Test: `python3 tests/run_gridselectall.py` (runs with floating point invalid operations as errors, as on Windows).

While a pasted block floats: the middle button pans the view, and R / X turn / flip the block (as Ctrl+L, Ctrl+R and Flip do). Test: `python3 tests/run_pastekeys.py`.

Del with the reference box of a symbol whose box took the focus by a double click still as it was given (all selected, nothing typed or clicked) deletes the symbol; after a click, typing or caret move in the box it edits the text. Test: `python3 tests/run_symreffocus.py`.

### Menus made in the form file
The static menus are items of `mainform.lfm`, not built in code: the document tab menu (`pmDocTabs`: Close, Close all), the Grid Size menus (`miGridSize` in the View menu and the toolbar drop-down `pmGridSize`; the Tag is the size in hundredths of a millimetre, only the captions follow the unit and the tick follows the sheet), the Polygon and Arc tools' right click menus (`pmPolyDraw`, `pmArcDraw`; Tag 1 Finish, 2 Cancel, 3 Finish arc, 10 + kind for the radio items; the view marks the current kind and shows Finish arc only with two points), and the object items of the sheet's right click menu (`pmSheet`: polygon handles and sides, wire cut, Make horizontal/vertical, hierarchical Reload/Open, Replace Symbol...; hidden unless they fit the chosen object). Still made in code because their content is dynamic: the Window menu's document list, the recent files of the File menu, the library panel's Copy to list. The view's old polygon menu (used only without an owner) was removed. Script: `popup <doc|grid|draw|arc|sheet> [click <caption>]`. Test: `python3 tests/run_menusinlfm.py`.

### Parts > New Parts Library... (Phase B1)
The Parts menu has New Parts Library... before Open Parts Library...: a Save dialog (replacing a file is confirmed there), then `UPartsDb.CreatePartsFile` makes the file in one transaction: the tables, views and triggers of `docs/parts_schema.sql`, the starting taxonomy of `docs/parts_seed.py` (part classes with their fields, child object kinds, which kinds a class allows, rating quantities), FormatInfo (current version, Generator TyCAD) and LibraryInfo (name = the file name, a new GUID); no parts or products. The new library opens in the Parts tab. The schema and taxonomy are compiled in as `src/UPartsSchema.pas`, which `python3 tools/gen_partsschema.py` writes from the two docs files (run it when they change). Script: `pdbtab new <file>`. Test: `python3 tests/run_partsnew.py` (compares the new file with the schema and seed built by Python, 21 checks, mutation checked). Library name, description and author are not asked yet (the name is the file name); they come with the library/part editor (B2).

### Parts library editor, part list (Phase B2)
Parts > Edit Parts Library... opens the library of the Parts tab (or asks for a file) in an editor tab of its own in the document strip, after the designs and symbols ("<library name> (parts)"; a file already being edited is shown, not opened twice; New Parts Library opens its editor at once). It is a `TDocument` with `PartsEditor` set (no design, no file name, so it is neither saved with the designs nor reopened with the session; a hidden view stands in for the drawing area). The tab (`src/frames/QPartsEditor.pas/.lfm`, `TfrPartsEditor`) has the library's name, description and author (Apply) and the list of generic parts (name, class, ref letters, status, revision, modified, description) with Add Part..., Properties..., Duplicate, Delete (buttons, a right click menu, and the Parts menu: Add Part..., Part Properties..., Duplicate Part, Delete Part, enabled while the editor tab is shown and, for the last three, a part is chosen). The Part dialog is `Fpartedit`: name, class (non abstract classes by path from the root; fixed once the part exists), reference letters, status, description. Every action is one SQLite transaction in `TPartsLibrary` (AddPart, UpdatePart, DuplicatePart, DeletePart, SetLibraryInfo) and stamps the library's Modified; Update raises Revision by one (none counts as 1) and stamps the part; the editor has its own connection to the file and the Parts tab reads the list again after each change. Duplicate copies the values, child objects (parents, values), requirements, links, symbols with pins (the default symbol is the copy's), icons, tags, rules and suggested products under a new GUID and revision 1. Delete asks to confirm, mentioning the suggested-product links that go with the part (the products stay), also removes rules of other parts that name it and products' outline/3D terminals that point into it, and tells that designs keep their copy. Deviation from the roadmap text ("refuse when products reference it"): the part's suggestion links are removed on confirmation, since without a products editor (B6) they could not be removed otherwise. Script: `peopen <file>`, `pe rows|menu|select|add|prop|dup|del|info|dlg ...`. Test: `python3 tests/run_partsedit.py` (38 checks, four mutations caught). Not seen on Windows: the tab look, the dialogs, the right click menu.

### Parts library editor, requirements (Phase B4)

The parts editor tab has a third page, **Requirements** (after Parts and Classes): the ratings a generic part must have. A part box at the top (it follows the part chosen on the Parts page) says whose requirements are shown; the list has *Applies to* (the whole part, or one of its child objects: a terminal, channel or pole), *Quantity*, *Min*, *Typ*, *Max*, *Unit* and *Condition*; whole-part rows come first, then by object name and quantity.

- **Add Requirement... / Requirement Properties...** (`Fratingedit`): the object (the whole part, or any child object with its designator and kind), the quantity (every `RatingQuantity` of the library; its unit is shown and fixed by it, and so is how a product is judged: at least, at most or exactly), minimum / typical / maximum (any of them; empty = not given; a point or a comma is the decimal mark) and a condition such as `AC-15 230 V`.
- Refused by the library (`TPartsLibrary.AddRating / UpdateRating`, nothing changes): a unit that is not the quantity's (`TPartsLibrary` takes an empty unit as the quantity's), none of the three values, min > typ, typ > max, min > max, an unknown or empty quantity, an object that is not the part's, and a second requirement for the same quantity and condition on the same object (a product's rating is matched on those, so two would be ambiguous). The schema's trigger checks the unit on insert only; the update path checks it in code.
- **Delete Requirement** asks to confirm. Every change is one transaction, raises the part's Revision by one and stamps its Modified (as Part Properties does). The library's own view `ProductFitSummary` then judges the part's products against the new list (no requirements at all gives `no_requirements`).
- Menu: Parts > Add Requirement..., Requirement Properties..., Delete Requirement (in `mainform.lfm`; enabled on the Requirements page, Add when a part is shown, the others when a row is chosen).
- Deviation from the roadmap text ("applies-to whole part / object / kind"): the schema allows `kind:X` only for a product's ratings, so a part's requirement applies to the whole part or to one object. A requirement that must hold for every pole is entered once per pole.

Script: `pe page requirements`, `pe rat part|<name>`, `rows`, `select|<row>`, `add|<object>|<quantity>|<unit>|<min>|<typ>|<max>|<condition>`, `prop|<row>|<object>|...`, `del|<row>`, `dlg|<row or -1>`. `tests/run_partsrating.py` (41 checks): the list and every change are compared with the file read by Python's `sqlite3` (rows, revision, modified, the other part's ratings, `ProductFitSummary`); each refusal is shown to leave Rating and Part unchanged and names its reason. Twelve source mutations (each rule, the duplicate and self-exclusion tests, the revision stamps, the comma) were caught. Not seen on Windows: the page layout, the dialog and the pop-up menu.

### Parts library editor, child objects (Phase B5)

The parts editor tab has a fourth page, **Objects** (between Classes and Requirements): the terminals, poles, channels, coils and contacts of a generic part. A part box at the top (it follows the part chosen on the Parts page) says whose objects are shown; they are drawn as a tree, an object inside another hanging below it (a pole holds its contact and terminals, a channel its terminals), each as `name [designator] - kind`, children in the part's order (*Order*, then creation).

- **Add Object... / Object Properties...** (`Fobjectedit`): name, designator (the number or label printed on the product), kind, *Inside* (the part itself or any other object of the part) , order and description. Only the kinds the part's class allows are offered (its own and its ancestors', with their sub-kinds; kinds that only group others, such as PassiveObject, are left out), and the parents offered leave out the object itself and everything inside it. Add starts inside the object chosen in the tree, with an order one past the last.
- Refused by the library (`TPartsLibrary.AddObject / UpdateObject`, nothing changes): an empty name; a name another object of the part has (any case; a product's ratings are matched to objects by name); an unknown, abstract or not-allowed kind (checked on change too: the schema's trigger only looks at inserts); a parent that is not an object of the part; an object placed below itself or below its own child; and a change of kind while the object holds values of a field the new kind does not have.
- **Delete Object** asks to confirm and says how many objects inside go with it. They are deleted together with their requirements, their field values and the part's links (bridged, driven_by ...) that name them. It is refused while a symbol pin, an outline terminal or a 3D terminal uses the object or one inside it (that placement would be lost; remove it first).
- Every change is one transaction and raises the part's Revision by one and stamps its Modified. The MinCount / MaxCount a class gives a kind are not enforced yet.
- Menu: Parts > Add Object..., Object Properties..., Delete Object (in `mainform.lfm`; enabled on the Objects page, Add when the class allows a kind, the others when an object is chosen).
- Not done here (belongs to later phases): the values of an object's kind fields (ObjectValue) are not edited yet; links between objects (Link) are only deleted with their objects.

Script: `pe page objects`, `pe obj part|<name>`, `rows`, `select|<object>`, `add|<name>|<designator>|<kind>|<parent>|<order>|<description>`, `prop|<object>|<name>|<designator>|<kind>|<parent>|<order>|<description>`, `del|<object>`, `dlg|<object>|<default parent>`. `tests/run_partsobjects.py` (41 checks): the tree and every change are compared with the file read by Python's `sqlite3`, the allowed kinds with a walk of PartClass and ObjectKind written in the test; each refusal leaves the file unchanged and names its reason; deleting is checked for objects, links, requirements and values (and the other part), and with a symbol pin in the way. Nine source mutations (cycle, kind allowed on change, unique name, abstract, stranded values, parent in the part, link delete, pin guard, order) were caught; the first run found that an unknown parent was taken as "none", now refused. Not seen on Windows: the page layout, the dialog and the pop-up menu.

### Parts library editor, field values and products (Phases B5b and B6)

Two more pages of the parts editor tab. The tab now reads, left to right: Parts, Classes, Objects, Requirements, **Values**, **Products**.

**Values** (`Fvalueedit`): the part box (it follows the part chosen on the Parts page) says whose values are shown. The list has one row for every field the part can hold a value for: first the fields of its class (own and inherited, root first; *Applies to* "(the part)"), then, for each child object in the part's order, the fields of its kind. Columns: applies to, field, type, unit, value, required (`required - missing` when empty), declared by. **Set Field Value...** (double click) opens a dialog: text and ref are typed, int and real typed as numbers (a point or a comma is the decimal mark; an int must be whole), bool and enum are picked from a list; **Clear Field Value** removes the stored value. `TPartsLibrary.SetFieldValue` stores numbers (int, real, bool) in ValueNum and the rest in ValueText, writes enum values in the field's own spelling, and refuses: a fraction for an int, text for a real, anything but yes / no / true / false / 1 / 0 for a bool, a value outside the enum, a field the class (or the object's kind) does not have, an object of another part. Each change raises the part's Revision and stamps Modified. Required fields may be emptied (the list marks them). The fields themselves are edited on the Classes page; the kinds' fields (KindFieldDef) have no editor: object kinds are part of the library's fixed vocabulary for now.

**Products** (`Fproductedit`; the product rating uses the Requirement dialog in its product form): the list shows every product of the library: manufacturer, model number, series, class, status, revision, **Fit**, **Suggested** and description. The part box above it ("Fit for part") chooses the part the products are judged against: Fit then reads `fits`, `fits, oversized`, `does not fit: 4 undersized, 1 missing`, `no requirements`, or `(other class)`, taken from the library's own `ProductFitSummary`; Suggested shows the library author's short list for that part (`PartProduct`: *suggested*, or the one *preferred*). Below, a second list shows what the chosen product is rated for (*applies to* the whole product, an object name such as `Pole 1`, or `kind:Contact` for every object of that kind; quantity, min, typ, max, unit, condition); the Add Rating dialog offers the kinds and the object names of the class's parts and also accepts typing.
- **Add Product... / Product Properties...**: manufacturer + model number must be unique (any case), the class must not be abstract, status is active / obsolete / preview / custom. A product suggested for parts cannot move to another class until the suggestions are removed. New products get a GUID and revision 1; every change (and every rating change) raises the product's Revision and stamps Modified.
- **Delete Product** asks to confirm; its ratings, suggestions, offers, documents, outlines and models go with it; other products that named it as replacement or substitute lose that mention.
- **Suggest Product for Part / Make Product Preferred** (buttons and menu): need a part in the part box of the product's class; one preferred product per part.
- Product ratings follow the rules of requirements (unit fixed by the quantity, at least one value, min <= typ <= max, no second rating for the same target, quantity and condition); `kind:` must name a kind of the library (written with the kind's own spelling, which `ProductFit` needs). An object name cannot be checked, since a product is not tied to one part.
- Menu: Parts > Set Field Value..., Clear Field Value, Add Product..., Product Properties..., Delete Product, Suggest Product for Part, Make Product Preferred, Add Product Rating..., Product Rating Properties..., Delete Product Rating (all in `mainform.lfm`, enabled by page and choice).

Script: `pe page values|products`, `pe val part|rows|select|set|clear|raw|dlg`, `pe prod part|rows|select|add|prop|del|sug|rrows|rselect|radd|rprop|rdel|dlg|rdlg` (documented in `UScript.pas`). `tests/run_partsvalues.py` (16 checks) and `tests/run_partsproducts.py` (38 checks) compare every list and change with the file read by Python's `sqlite3`; the Fit column is compared with a verdict re-implemented in Python from the Rating rows (not with the views). Nine source mutations of the value rules and ten of the product rules were caught (see the todo). Not seen on Windows: the page layouts, the dialogs, the pop-up menus and the splitter between the product and rating lists.

### Parts library editor, symbols (Phase B7)

The Symbols page lists the symbols of one part (name, standard, purpose, default, size). New and Edit open the existing symbol editor as a document of its own; Store in library
writes the drawing back into the parts file (a new symbol is added only when it is stored, with the standard, purpose and name asked for first). Import takes the symbol chosen in
the library panel (any open symbol library) as a new symbol of the part. Properties changes standard (IEC, ANSI ...), purpose (schematic, oneline, panel, block) and name; Make Default
chooses the symbol placed from the Parts tab; Delete asks first. Rules: the first schematic symbol of a part becomes its default, only a schematic symbol can be the default (and the
default cannot become another purpose), deleting the default makes the part's lowest other schematic symbol the default, every change raises the part's revision, an empty drawing or
an unknown purpose is refused. Not done: assigning pins to the part's objects (SymbolPin), and a part with a drawing per part (several parts per package) is stored but placed as part 1.
Every change of a part's symbols draws the part's glyphs (the icons of the Parts tab, 16, 24, 32 and 48 pixels) again from its default symbol, or removes them when no symbol is left (UGlyph.pas); importing a PNG as glyph is not done. Script: `pe page symbols`, `pe sym part|rows|select|start|import|add|info|default|defraw|del|dlg`; test `tests/run_partssymbols.py` (43 checks, sqlite and Pillow oracle, seventeen mutations caught).

### Parts library editor, CSV import and export of products (Phase B12, products part)

Parts > Import Products from CSV... (Products page) reads a CSV file with a header line; Export Products to CSV... writes the same layout. Columns, in any order and any case:
Manufacturer and MPN (required; together they name the product), Series, Class (a class name; required for a product that is not in the file yet, unless Part is given), Status
(active when empty), Description, Part (a generic part to suggest the product for), Preferred (yes / no), Quantity, Unit, Condition, AppliesTo (empty = the whole product, an object
name, or kind:Name), Min, Typ, Max. A product with ratings takes one line per rating (repeat Manufacturer and MPN). The delimiter (comma, semicolon or tab) is found from the header,
quoted fields may hold commas, quotes and line breaks, a comma is accepted as the decimal mark. A product already in the file keeps what the line leaves empty; a rating with the
same AppliesTo, Quantity and Condition is replaced. The edits use the editor's own rules and messages; the import is all or nothing: the first bad line stops it with "Line n: reason"
and the file is unchanged. Script: `pe prod csvimport|<file>` / `csvexport|<file>`; test `tests/run_partsimport.py` (52 checks, Python csv writer and sqlite oracle).
Not done: importing .TCLib symbols as parts, a CSV import of parts, objects or field values.

### Symbol parameter list with several symbols selected

The Parameters button of the symbol frame drops down the parameter list for every selected symbol (or the symbol being placed). A label above the grid says how many symbols are selected.
Only the parameters every selected symbol has are listed (a parameter is a description; the n-th field of that description is the same parameter in each symbol). Show?, a value, a name,
Add and Delete are applied to all of them as one undo step; where the symbols differ Show? shows a dash box ("Mixed", a click shows it in all) and the value shows (varies) (left alone
unless something else is typed). The grip in the lower right corner resizes the list (not below 300 x 220 at 96 dpi, kept on screen); the Value column follows the width.
Test: `tests/run_symbolframe.py` (41 checks; the smallest-size clamp is also enforced by the form's constraints, so that mutation is equivalent).

### Duplicate reference check and symbol BoM (stop-gap until the parts library is in use)

Two items in the Special menu, after Create Parts List (`USymbolBom`, handlers in `mainform.pas`; the items are in `mainform.lfm`):

- **Check Duplicate References...** looks at every placed symbol of every sheet and lists each reference used by more than one symbol ("R3: 2 symbols (sheet 1 (Main) 10k, ...)"), in natural order (R2 before R10), references compared ignoring case. The parts of one package (the same symbol, each its own part: U1A, U1B) are not duplicates; two different symbols, or two with the same part, are. References that still have a `?` (R?) are not duplicates; their number is mentioned at the end of the message. This is separate from the design rules check, which needs the net list and its options.
- **Export Symbol BoM (CSV)...** asks for a file (the design's name + `_bom.csv`) and writes one row per kind of symbol: `Item, Quantity, References, Value, Symbol, Description`, then one column per attribute heading (headings shared by name, ignoring case, in the order met; hidden fields left out). A kind is the same symbol, value (the Name field), description and attribute values. Quantity counts distinct numbered references (the parts of a package, and a reference used twice, count once) plus every symbol not numbered yet. Quoting follows RFC 4180 (commas, quotes, line ends; quotes doubled), UTF-8. After writing, a message warns when some references are duplicated or not numbered, since the quantities would be wrong. Hierarchical symbols are not followed.

Script: `dupcheck` (prints `DUPREF <line>` per duplicate and `DUPCHECK status=...`), `symbom <file>` (prints `SYMBOM wrote=<0|1> status=...`). `tests/run_symbom.py` (35 checks): duplicates and the CSV compared with a separate Python statement written from the design's XML, over eight sample designs (multi-part packages, several attribute sets, many `?` references) and two edited ones (duplicates by case, an unnumbered one, a value with commas and quotes), the warning text, an unwritable path, the menu in the lfm. Source mutations of `USymbolBom.pas` (see the todo note) were caught.

### Symbol text and the symbol data report

- **Symbol text** (`TDrawSymbolText`, type code `xSymbolText` = 143, XML element `SYMTEXT`; not in TinyCAD): a text that has the fields of a symbol (Reference, Name, Other and any more) but draws no symbol, so a drawing can carry symbol data for reports. Draw > Wires ribbon (next to Text, it shares the Text icon until it has its own) and Draw > Symbol text. Click to place; its Properties use the symbol frame (reference, show reference, and a text box for the Name field, the text that is seen; a new one reads "Symbol text" when nothing was typed, so it can be seen and clicked); more fields are added in the parameter list. It is saved like a symbol (`SYMTEXT` with `FIELD` children, symbol 0). Because its type code is not `xMethodEx3`, the netlist, the checks, annotate, the BoM and the parts list leave it alone; Find and the symbol data report see it.
- **Export Symbol Data (CSV)...** (Special menu, after Export Symbol BoM) writes one row per symbol and symbol text of every sheet. The whole design is read twice: the first pass lists every field heading used anywhere (the order met, hidden fields included, headings shared by name ignoring case, a heading used twice by one object numbered `Tag`, `Tag (2)`), the second puts each value in the column of its heading. Columns: `Reference`, all the headings, then `Sheet`, `Sheet name`, `Kind` (Symbol or Symbol text), `Symbol` (library name). Rows are in natural reference order, those without a reference last. UTF-8, RFC 4180 quoting. Not yet: the editable report designer (Crystal-style); the table is the data it will use.
- Script: `tool symboltext`, `symdata <file>` (prints `SYMDATA wrote=<0|1>`). `tests/run_symdata.py` (30 checks): placing, saving, selecting, the frame and parameter list, the BoM and duplicate check unchanged, and the CSV compared with a two-pass Python statement written from the XML on a sample design with added symbol texts of different field sets. Mutations (columns by position, string sort, symbol texts left out of pass 1) were caught.

### Parts library editor, class tree (Phase B3)

The parts editor tab now has two pages, **Parts** (Phase B2) and **Classes**. The Classes page shows the tree of part classes on the left (children sorted by name, abstract classes in brackets) and, for the chosen class, the fields it has on the right: those it inherits from its parents first (grey, read-only, with the class that declares them in *Declared by*), then the ones it declares itself. Above the list a line gives the class path, whether it is abstract and how many parts and products it has.

- **Add Class... / Class Properties...** (`Fclassedit`): name, parent (every class except itself and its own subclasses, or none for a root), abstract flag, description. Refused: a taken or empty name, a parent that is the class itself or below it, abstract while the class has parts or products, and a move after which two fields of one class line would share a name (the change is rolled back, the file stays as it was).
- **Delete Class**: asks to confirm; refused while the class has subclasses, parts, products, a part rule that names it, or a product option that changes one of its fields. Its fields go with it.
- **Add Field... / Field Properties... / Delete Field** (`Ffieldedit`): name, type (text, int, real, bool, enum, ref), unit, enum values (only for enum), required, description. A name must be free along the whole class line (parents and subclasses). The type cannot change and the field cannot be deleted while a part has a value for it. Only a field the chosen class declares itself can be changed; inherited ones are changed on their own class.
- Menu: Parts > Add Class..., Class Properties..., Delete Class, Add Field..., Field Properties..., Delete Field (in `mainform.lfm`; the part items work on the Parts page, these on the Classes page).
- Every change is one transaction written at once (`TPartsLibrary.AddClass/UpdateClass/DeleteClass/AddField/UpdateField/DeleteField`; the inheritance views are checked before and after a change).

`tests/run_partsclass.py` (43 checks): the tree and the fields of every class are compared with a walk of the raw rows written in Python; each refusal is shown to leave PartClass and FieldDef unchanged; file integrity and foreign keys after every session. Source mutations of `UPartsDb.pas` (cycle check, abstract refusal, subclass check, rule-target check, field name check, type change and delete with values, empty class name) were caught (the error messages are checked as well, since the file's own foreign keys refuse some of the same cases). Not seen on Windows: the page layout, the dialogs and the pop-up menus.

## Pin property frame

A selected pin of a symbol being drawn uses the designer frame `src/frames/QPin` (`TfmPin`, registered as `pin`): name, number (a text), length, number position, pin type, electrical type and the show-name / show-number / centre-name buttons (images 72-74 of `ilSpeedBtn`). Every editor is named after its property, so the generic binding of `QPropFrame` fills it, applies changes as undo steps and fills the two lists. The direction is not on the frame (it is set by the symbol's rotation); the Pin tool has no panel of its own, as before. Test: `tests/run_pinframe.py` (17 checks; removing the registration fails 16 of them). The image list `fsharedctls.lfm` was replaced by the newest upload.


## Translating the program

Every text the program shows is either a `resourcestring` in `src/UStrings.pas` (messages, undo names, dialog titles ...) or a Caption / Hint / Text in a `.lfm` file. `schematic.lpr` calls `SetDefaultLang` of the `LCLTranslator` unit, which reads a `.po` file at start-up and swaps the texts. No text is read from the code.

**What a .po file is.** A plain UTF-8 text file with entries like

    #: ustrings.rsready
    msgctxt "ustrings.rsready"
    msgid "Ready"
    msgstr ""

`msgid` is the English text (never change it), `msgstr` is yours. An empty `msgstr` means "not translated", and the English text is shown.

**Starting a language** (example German, code `de`):

1. Copy `languages/schematic.pot` to `languages/schematic.de.po` (or run `python3 tools/mkpo.py --new de`).
2. Fill in the `msgstr` lines. Free editors that do this for you: Poedit, Lokalize, Virtaal; a text editor is enough if it saves UTF-8. Use the editor's "translations" view, not the raw file, if it offers one.
3. Keep `%s`, `%d` and `&` (the underlined key of a menu item) in the translation. When a text has several `%s` / `%d`, the order may be changed with `%2:s ... %1:s`. Lazarus' own PoChecker (Tools menu) checks this.
4. Put the `languages` folder next to the program (the program also finds `..\languages` when it runs from `bin`).

**Choosing the language.** The language of the system is used by default; `schematic.exe --lang de` or `-l de` or the environment variable `TYCAD_LANG=de` overrides it. Script runs (`--script`) stay English unless a language is named. A language without a file is English.

**After the code changed.** Run `python3 tools/mkpo.py`: it rewrites the template and merges it into every `languages/schematic.<lang>.po` (new texts get an empty `msgstr`; texts that were removed are kept as obsolete `#~` entries). `python3 tools/mkpo.py --check` only reports. `python3 tests/run_i18n.py` runs the program in a made-up language (`--pseudo FILE` of `mkpo.py`: every text in [brackets] with accents) so that anything still hard coded stands out.

**Rule for new code.** Never write a user-facing string in a `.pas` file: add a `resourcestring` to `src/UStrings.pas` (a text with values is a template, `Format(rsName, [value])`, not `'a ' + x + ' b'`), and give controls their text in the `.lfm`. A `resourcestring` cannot be used in a `const`; use a function.

**The Lazarus project option.** Lazarus has an i18n option (Project Options > i18n) that makes the IDE write `.po` files itself from the `.rsj` files. It is not used here: `mkpo.py` makes the same entries (and also reads the `.lfm` files), with the same identifiers LCLTranslator looks for. Turning the option on is harmless but not needed.

**The LCL's own texts** (the buttons of standard dialogs: OK, Cancel, Open ...) come from `lclstrconsts.<lang>.po` in the Lazarus folder `lcl/languages`; copy that file into `languages` as well.

**Not translated yet:** the choice lists whose words are also used as keys (Up/Down..., pin types, status words), the items of combo boxes written in `.lfm` files (status, standard, units in measure), paper names, generated outputs (XML, netlists, VHDL, CSV, the `$SHEET` fields of a drawing), file-dialog filters, and plural forms (two separate texts are used). A language choice in the Options dialog is also open. Not tried on Windows: loading of a language and the translated dialogs.


## Revision cloud handles, auto-show of the symbol parameters

- A selected revision cloud (the only selected object) has the eight resize handles of a rectangle (four corners, four side middles), like a rectangle or a note (`TDrawCloud.CanResize`; the rest is the inherited rectangle code). Test: the `revision cloud` kind of `tests/run_resize.py`.
- The parameter button of the symbol frame (`sbParameterList`, a `TSplitButton`) has two jobs. Its left part is a toggle (`AutoCheck`): pressed in, the list of the symbol's parameters opens by itself whenever a symbol is selected (the main form keeps the state in `FAutoShowParams` and gives it to every new frame; the list is dropped down a moment after the Properties panel was rebuilt). Its arrow drops the list down once. `TSplitButton.Checked` (the left part shown pressed in, with the button frame, also when Flat) was already there. Test: the last three checks of `tests/run_symbolframe.py` (script: `symlist sel autoclick|autostate`).


## Options > Sheets: what a new design starts with

The Sheets page of the Options dialog (`tsSheets`, the Sheets toggle button on the left) sets what the first sheet of a **new design** starts with: Show Border, its margin (mm), Show rulers, the number of columns and the last row (a letter, A to Z, as in the ribbon's Details drop-down). They are `NewSheetBorder / NewSheetRulers / NewSheetCols / NewSheetRows / NewSheetMarginMm` of the program settings (kept in the registry; defaults: border on at 6.35 mm, no rulers, 7 columns, 5 rows - what New Document always gave), `SheetBorder ...` of `TOptionsData` (checked by `OptionsError`: 1 to 26 columns and rows, a margin of 0 to 100 mm). `TfrmNewDoc` starts with the border box and margin of the settings and `BuildDesign` writes the rulers and their counts into the new sheet's details. OK / Apply keep the values only for later designs: the sheets that are open are not changed (the ribbon's Details does that). Add Sheet still copies the details of the sheet showing. Test: `tests/run_sheetdefaults.py` (14 checks; script `options sheetborder= sheetrulers= sheetcols= sheetrows= sheetmargin=`).


## Wire labels on a printout

Checked (the user reported that no wire labels printed): `RenderPrintPage` draws every object with `TSchematicPainter.PaintSheet` with `Printing := True`, and `PaintLabel` has no printing special case, so a label prints like any other text. `tests/run_printlabels.py` prints a design with 16 labels (all four styles and four directions) and the same design without them to the test bitmap sink and checks that the pages differ at each label, at 100 and 300 dpi, in black and white and at 50 % (4 checks; skipping the label drawing while printing fails all four). That passes: the labels do print through the test sink, so the cause of the missing labels on a real printer, or in the user's design, is not found yet (a sample design and how it was printed are needed).

### Moving the viewport during a drag

Holding the middle button while the left button drags (a symbol, an edge of a shape, a rubber band, a field) moves the viewport; the drag goes on when the middle button is let go and ends with the left release. `tests/run_midpan.py` (10 checks): the origin before and after, the drag mode, and the saved position of a dragged rectangle edge (the pointer's movement on the sheet, not shifted by the panning). Mutations (middle press ignored, release not noticed) were caught.

A press on a symbol while the symbol parameter button is on no longer opens the list under the held button (it took the release, and the symbol then followed the pointer): the list opens when the button is let go (`OnDragEnd` of the view). As a second guard, a pointer move reported with no button while the view still thinks one is down ends that drag (`mouse lost` in scripts). Tests: `run_symbolframe.py` (45) and `run_midpan.py` (12); both mutations were caught.

Symbol parameter list: naming an added parameter and then clicking its Show? box blanked the name. The grid reports a finished edit again after the click, when the list has been rebuilt and the editor is empty; the form now ignores a report for a cell it is not editing (`LateEntry` and `symlist ... stale <row> -` reproduce it). Test in `run_symbolframe.py` (46).


## Recent fixes
- Symbol text: clicking on its typed text now selects it (hit box recomputed from the shown fields); the properties drop-down opened after placing one is anchored at the visible tool button.
- Files dropped from the file explorer onto the document tab strip open as documents (drops elsewhere are ignored; folders skipped; failures reported in the status line). tests/run_dropfiles.py. Real Explorer drop on Windows not seen.
- Print window: new check box "Do not print symbol text" (kept in the settings; used by the print and the preview; exports are not affected). tests/run_printsymtext.py.
- Parameter list: the Value box now takes the keyboard (arrows, Backspace, Delete edit the text; Delete no longer deletes the symbol), and a list closed while its symbols were rebuilt no longer raises an access violation. tests/run_listkeys.py (real X key events; needs python-xlib).
- Parameter list: Ctrl+C, X, V, A, Z work on the text in its Value box (the shortcuts of the Edit menu took them before); the new parameter's row is selected after Add. Esc in any dialog made from the base form presses its Cancel button (TfrmBase.KeyDown, KeyPreview on).
- Wires: with several wires chosen (none wholly inside the picking box), pulling an end handle stretches the nearest end of every chosen wire by the same step (it was only the pressed wire). tests/run_wirepull.py.
- Panning (middle button, or right button in Select) while a text box has the focus: when the pan has moved the sheet the box gets the focus back. tests/run_panfocus.py.
- Print window now has two check boxes: "Do not print symbol text" (the Symbol Text objects) and "Do not print symbol properties" (reference, name and values of every symbol); both kept in the settings, used by print and preview, exports not affected.

## Licence

LGPL-2.1-or-later, as TinyCAD (see `LICENSE` and `NOTICE.md`). Source files carry `SPDX-License-Identifier: LGPL-2.1-or-later`.
