# TyCAD Electrical – what is left (as of the printing delivery)

Checked against the original `TinyCad.rc` menus, `UView.TViewTool`, the `Do*` handlers in `gui/mainform.pas`, `mainform.lfm` and `BuildRibbon`.

## A. UI functions still to connect (Do* handlers)

### A1. ~~Written, tested, but on no menu item or button~~ – done
All on a menu item now: Options, Colors (Edit menu), Find / Find Next / Find Previous / Replace (Search menu), Import (File, Ctrl+I), Copy To (Edit, Ctrl+E – the menu item was missing its OnClick, wired), Insert Picture (Insert menu and a Draw-ribbon button).

### A2. ~~On a ribbon button but missing from the menu bar~~ – done
Cut, Copy, Paste, Duplicate, Rotate Left / Right, Flip, Bring to Front / Send to Back (Edit ▸ Translate), Zoom In / Out (Edit; Zoom Out and Rotate Right were missing their OnClick, wired), Design Details, Close / Close All (File), Rename / Move Sheet (Sheet menu). Left: `DoToggleSnap` has only buttons (the status panel and the View ribbon), no menu item.

### A3. On a menu item but without a speed button (optional)

~~`DoPrint`, `DoPrintPreview`, `DoPrintSetup`~~ (done: Home ribbon, File group, with Page Setup), `DoProperties`, `DoAnnotate`, `DoCheckRules`, `DoVhdlCheckRules`, `DoNetList`, `DoSpiceNetList`, `DoVhdlFile`, `DoPartsList` (a "Special" ribbon tab would be natural), `DoInsertLadder` (the Ladder tab has the tool button), `DoRepeat*` (4, a check-style toggle group), `DoTheme`, `DoAbout`.

### A4. Handlers not needed on a menu

`DoToolButton`, `DoGridSize`, `DoGridCustom`, `DoGridSizeUp`, `DoGridButton`, `DoToggleGridSize`, `DoOpenRecent`, `DoWindowItem`, `DocTabChange`, `DocTabMouseDown` are wired from code or events.

### A5. Menu commands in the original with no `Do*` handler at all yet

| Original menu command | Needs |
|---|---|
| Edit ▸ Zoom In/Out (Pg Up/Pg Dn) | keys only; add shortcuts |
| ~~Library ▸ Libraries… (`IDM_LIBLIB`)~~ | **done** – Library Setup dialog (Add / Remove / New / Cleanup, list kept in the registry); its Edit and Upgrade buttons wait for the symbol editor and the legacy `.mdb`/`.idx` readers |
| ~~Library ▸ Set parts per package…~~ | **done** – Parts per Package window (`Fsymparts`) |
| ~~Library ▸ Homogeneous / Heterogeneous symbol~~ | **done** – the check box of the Parts per Package window (only at one part, as in TinyCAD) |
| ~~Library ▸ New / Edit / Delete Symbol, Symbol Properties…, Duplicate symbol…~~ | **done** – the symbol editor (a tab of the main window, `Fsymprops`, Pin and Origin tools, Store in Library, Copy to); Pin / Origin have menu items only (ribbon buttons still to do) |
| ~~Library ▸ Export all symbols… / Import symbols…~~ | done (also Export symbol…, and the library list's popup) |
| Window ▸ Cascade / Tile / Arrange Icons | document window layout (the port uses tabs; decide whether to keep tabs only) |
| Options ▸ Toolbars (File, Annotation, Block, Bus, Drawing, Symbol) | show/hide ribbon groups |
| Help ▸ User Manual, Support Forum, Tutorials, Go to web site, Check for Updates | open URLs / help file |

## B. Feature task list ("still to do" bin)

1. ~~**Symbol (.TCLib) editor window**~~ – done (`USymEdit`, `Fsymprops`, `Fsymparts`, the Pin and Origin tools, Library menu, `tests/run_symboleditor.py`). Symbol properties in the library list is now a dialog on its own (no tab). Library/symbol export and import (XML) is done (`ULibXML`, `tests/run_libxml.py`). Left over: ribbon buttons for Pin and Origin, opening the editor in a window of its own if wanted.
2. **Hierarchical designs** – steps 1 and 2 done (sheet and placed design load, save, edit and draw with the child's outline and pins; Special ▸ Insert another design as symbol… / Add hierarchical symbol / Reload / Change design / Open design; pins on the symbol sheet; `UXMLPath`, `tests/run_hierarchical.py`, `tests/run_hierarchical_load.py`). Step 3 done: netlist (`UNetList`, `tests/run_hiernetlist.py`), BOM (`UPartsList.AddLevel`, `tests/run_hierbom.py`), annotate numbers the placed designs (`tests/run_annotatehier.py`); ERC stays flat and annotate does not enter child files, both as in TinyCAD. Left: step 4 tests with real hierarchical files (**needed from the user**); not verified against a real TinyCAD hierarchical netlist.
3. ~~**Image export**~~ – done: File ▸ Export Image… (`UExport`, `Fexport`): colour / B&W PNG at 1–1000 % with optional quarter turn, colour / B&W SVG in place of EMF, the selection or the whole sheet. Possible extras: BMP / JPEG / PDF kinds, exporting all sheets.
4. ~~**Old binary `.dsn` format**~~ – done (`UDsnBinary`, opens as an unsaved "(converted)" document; `tests/run_dsnbinary.py`). Tested with synthetic files written from the C++ read code only – **real old `.dsn` files are still needed to confirm it.**
5. **Library manager** – Library ▸ Libraries… and the symbol editor are done; library export/import (XML) is done too.
6. **Word-wrapped note-text layout** (noted in the README as not ported).
7. **Window menu / toolbars menu / Help menu** – see A5.
8. **Test the build in the Lazarus IDE** – `schematic.lpi` has never been opened in Lazarus (the sandbox only ran `build.sh`); check the Printer4Lazarus requirement and the form files.
9. **Real printer test** – printing was tested against bitmap pages only; try a real printer/PDF printer on GTK2 and Windows (Printer4Lazarus / CairoCanvas).
10. **Housekeeping** – remove the commented-out `AddButton` block in `BuildRibbon`, keep the README to-do list in step.

- Property frames: loader done and the user's frames (wire, rect/circle, cloud, text, label, note, power, measure) are linked (QPropFrame aliases). Not yet: frames for polygon, arc, bus differences, ruler/xref (pin done: `QPin`; ladder and rung grid done); the font list is shown blank when the font is not installed; fill type 'None' with the Fill box versus the combo box when the combo is chosen as None (box unticks).\n- Shared controls form (FSharedCtls) holds dialogs and image lists; the unused src/forms/fshared.pas of the upload is not part of the project.

- Labels/text: outlines of input/output/io labels, attachment box, text directions, edText focus + Del, floating text done (tests/run_labelshapes.py). Not done: floating label for the Label tool; resizing a Left/Down text by handles is only lightly tested; the label's stuck-junction circle is not drawn.

- Wire tool: ghost width follows the tool panel (done, tests/run_wireghost.py).

- Source style: if/then/else statements on their own lines (tools/fmt_ifthen.py); Note tool panel shows all three panels, no extra caption label.

- Note text wraps at the box edge (done, tests/run_notewrap.py). Not done: tab stops in note text.

- Dashed line styles of shapes at zoom >= 150% (done, tests/run_dashzoom.py). The arc shares the polygon's path but has no test of its own.

- Status bar: panel widths in pixels from consts.StatusBarWidth (the -1 panel takes what is left); FormResize skips panels the form does not have.

- Wire angle option (free / 90 / 45) done and kept for the session; not saved in the settings file, so it starts again with the program.

- Script runs start with the main window at 1417x854 whatever size the form was saved at (the forms are now saved at 120 dpi).
- [x] Power tool: text box and direction shown while drawing; selected power symbol caption reads 'Power symbol' (tests in run_labelshapes.py)
- [x] Fill button (bbFill) with the Fill menu (frmFillDropDown): glyph of the fill, wheel/arrow/Enter/Esc, OnPick callback; replaces the Fill box, type list and color button of Rectangle/Circle (Note panel still has its own) (tests/run_filldrop.py)
- [x] Note panel: uses the Fill button and menu as the Rectangle / Circle panel does

- ~~Right-click pop-up menu of the sheet (common commands, polygon handle/arc commands, Replace Symbol..., Arc tool arc in/out)~~ – done (`tests/run_contextmenu.py`). Line Make horizontal/vertical and placed-design Reload/Open design added (`tests/run_contextmenu2.py`). TinyCAD has no other object menus; Z-Order Forward/Backward are not in its menu.

- Font sizes are now points (TinyCAD's numbers); the Properties ribbon tab is gone, its panel is on the View ribbon.
- Text tool places text Right; colour button on the Text frame; View-tab separator is left of the properties (tests/run_textframe.py).
- Right-click menu on the sheet tabs (design-time pmSheetTabs; tests/run_tabmenu.py).
- Arrow on the current sheet tab: pictures in frmSharedControls.ilSheetTabs (0 arrow, 1 empty), tabs rebuilt after each sheet change because Windows asks for a tab picture only when it makes the tab (tests/run_tabmarks.py); not seen drawn on Linux, check on Windows.
- Main window position/size and splitter positions saved in the registry on close and applied on open (tests/run_layout.py).

- Screen scale is 100% now: mainform.lfm has no DesignTimePPI (96). Still saved at 120 and to be re-saved at 96 in the IDE: Fannotate, Fercopts, Fercwin, Fexport, Flibraries, Fnetlist, Fpagesetup, Fpartslist, Fpreview, Fprint (forms) and QFindPanel, QLibPanel (frames). They load and scale correctly meanwhile.
- Design Markers window (frmErcList) stays a plain TForm (it is not modal) with its own pnlButtons (Close, Re-check) laid out like TfrmBase's button bar. Fbase gained a `CustomButton` property for AddCustomButton users.
- Print dialog: printer drop down, Printer Setup button, Pages box with ranges (1-2, 6 / 1 to 6 and 9 ...), quick preview with slider, < > and page label (tests/run_printrange.py). Left: copies/collate have no control now (the system Print dialog button was removed; copies = 1); the unnamed RadioButton1 (Current) in the Pages group is not wired.

- Print dialog Properties button: Windows route (TWinPrinter.AdvancedProperties) is written but untested on a real printer; other systems use the setup dialog.

- Properties window placement (osver.PrinterCBTHook, Windows): moves only the first #32770 dialog to the Print dialog's top left + 40,40 (kept inside its bounds); untested on a real printer.

- Properties window placement: now also a WinEvent hook (EVENT_OBJECT_SHOW, any thread of the program) beside the thread hook, since a driver (Brother) can make its window on another thread; works on the Brother and CutePDF drivers (tested by the user).

- Document tabs are a custom strip now (UDocTabs; close glyph, hover glyph and unsaved mark from ilDocTabs; tests/run_doctabs.py). Dragging a tab to reorder and a hint on the glyph are left out on purpose; the Windows look not seen (drawn with system colours). Older checks that fail and are not about the tabs: run_gui ("placing a label brings the View tab forward", the settings keys now include the window layout keys), run_symboleditor (a Library menu item without a hint) - to be brought up to date.
- Ribbon tab strip moved out of mainform.pas into src/URibbon.pas (TRibbonTabStrip); mainform keeps thin handlers. Further splits proposed: printing (~740 lines), documents (~960 lines).
- Automatic sheet numbers now fill Document with this sheet's number and Sheets with the sheet count (both greyed out); before, Sheets showed "N of M". The old duplicate dialog class TNewDocForm in UDialogs.pas (not the one used by the program) was not changed. The title-block painting of the new texts is not checked by pixels (the text functions are).
- Del in a text box edits the text (right of the caret) instead of deleting the object; only in an empty text box of a selected text/label/power does it delete the object. Not covered: spin boxes (Del there still reaches the Delete menu). Windows path not seen by me.
- Select All Alike (sheet pop-up): same object type only (a symbol is any symbol, not only the same library part); could be refined to the same part, and given a key / the Edit menu / the ribbon.
- Access violation at address 0 freeing the property frame (ClearPropEditors) after selecting / unselecting texts (user report, Windows): not reproduced here. Cause thought to be the frame being freed inside one of its own events (the text box losing the focus); now it is taken off the panel with its events cleared and freed by Application.ReleaseComponent. If it still happens, the stack at the access violation is wanted.
- Text boxes now use real font measuring in the program (UTextMetrics). Not seen on Windows: the pixel height of a line comes from the canvas (ascent + descent), where GDI's tmHeight may differ by a pixel at the 5x size. The painter's own text placement inside the box is unchanged; look at a text in a wide font and at rotated texts. Other users of the metrics (labels, pin names, symbol bounds) change size with it: library symbols may shift slightly.
- Color dialog opens under its TColorButton (Windows only, by the printer-window hooks; not seen by me; the Windows block of osver.pas was not compiled here, so a compile error there is possible - send the message). Options dialog Change buttons and the fill drop-down's Color... are left as they were.
- Viewport rulers (UViewRulers; Show Rulers check box + View menu item, saved). Look on Windows not seen (fonts/sizes from system, ruler thickness 18 px scaled). No ruler unit of its own: follows the sheet's units. Not done: dragging guides out of the rulers, a corner box.
- Polygon property frame (QPolygon, designed by the user) wired: registered as 'polygon' (color, width + caption, style, Fill button), tool and selection; tests in run_realframes. A Closed check box (cbClosed, poly.closed) sits right of the width box; it shows for a selected polygon only (the tool has no such property). Added FSharedCtls to its uses (it names frmSharedControls).
- Arc property frame (QArc, designed by the user) wired as 'arc' (tool and selection): line, width, style, Fill button and the in / out radio buttons (new bind mode bmRadio: a TRadioButton is ticked when its caption is the property's choice; new property arc.type 'in|out': tool-only for the Arc tool, and a property of an arc = IsArcPolygon: an open polygon whose segments are all arcs in/out, or the old xArcEx2). The Arc tool now works like the Polygon tool: click after click (each arc starts at the last point), ghost of the arc being drawn, Esc drops it all, double click commits (right click: Finish arc / Cancel / Arc in / Arc out); every click after the first turns the next arc the other way (in, out, in ...) and the radio buttons follow. A selected arc polygon uses the arc frame (no Closed box); its arc.type is empty (mixed) when its arcs alternate, and choosing in or out sets all of them. A drawing closed on its first point becomes a closed polygon (polygon frame). Mixed in/out on GTK: a radio group cannot show none ticked (Windows not seen).
- 3-phase bus (Phases button + frmBusDropDown, FDropDownBase shared by both drop-downs, UPhases): done, tests/run_busphase.py. Not seen on Windows: the drop-down may lose focus and close after a pick when the ribbon is rebuilt. Changing the spacing recreates the outer wires, so symbols on their ends stay behind; dragging/moving one wire of a group is not handled specially. Bus panel hints/pictures are first drafts.
- Alignment panel / Align to Grid: first end only (PointA; for polygons PointA may be the bounding corner, not the first handle); Align to Grid is only in the sheet pop-up Z-Order submenu, not the Edit menu; 1 px grid is not kept when the symbol is closed. Look on Windows not seen.
- Closing the program with several documents open could crash (access violation in RebuildProps from TDocument.Destroy: freed views reported an empty selection to the main form). Fixed with an FDestroying flag and by detaching the views' events in TfrmMain.Destroy. Not reproduced in the sandbox; check on Windows.
- Pin button (miDrawPin, Draw tab, Select panel): ImageIndex 63 is a push pin placeholder in the user's image list (check it is in fsharedctls.lfm); visible only while a symbol (or hierarchical symbol sheet) is being edited; chooses the Pin tool.


## Ladder rework (done) and follow-ups
- Done: ladder rails now have line density width + colour + bus label text options + 8 resize handles; line numbers removed from the ladder; new rung grid (hidden whole-sheet spreadsheet with the rung numbers, 1 or 2 pages, indent + border margin, row height printout) with its own button, menu item, frame, tests (`run_ladder.py`, `run_rungs.py`, `run_rungui.py`).
- To do: pasting a rung grid onto a sheet that has one should replace / refuse (today a second one can exist; the first is used); an icon for the rung numbers button in `ilSpeedBtn` (now drawn at run time); bus label positions could be dragged separately; row height printout position and "numbers on the right side too" are open design questions; the wire/symbol "line number" shown in the status bar or on the Properties panel is not done; rung grid in the printed title area (not drawn yet in the print path beyond normal painting - checked by `PaintObjects` only); rung grid in hierarchical child sheets uses the child's own page.
- Needs checking on Windows: the new button's runtime icon, the two new frames (`qladder.lfm`, `qrungs.lfm`: widths and fonts) in the Lazarus designer, and `schematic.lpi` (two units added).

- [x] Wire end handles stretch a clicked/partly picked wire, move a wholly picked one (tests/run_wireends.py)
- [x] Paste: guard against vanished objects staying selected (cross-sheet crash not reproduced)
- [ ] Paste right after copying nothing in an empty document gives an access violation

- [x] NOTES/REFERENCE cells as high as the Title cell
- [x] Design Details: Apply to All on the Details tab (tests/run_applyall.py)
- [ ] Apply to All: the Revision box is not copied (it is the newest of each sheet's own revision history); say if it should be

- [x] Rotate shortcuts on the main menu; rotate works on a floating paste (tests/run_pasterotate.py); Ctrl+L taken from Open Symbol Libraries

- [x] Imported text box too wide on Windows: the user's project file did not select the real-font measuring; it is now the default of UTextMetrics itself

- [x] Rung grid: Above block option (tests/run_rungabove.py)
- [ ] Above block: the extended cell spans the page's bottom right, so with two pages the left page is also lifted by it (the whole table moves together)

## Full regression, 2026-10-21 (106 scripts)
Passing: all but those below. Fixed: missing hints on 50 menu items/controls (run_hints_theme).
Open, not caused by this session's changes as far as traced:
- [ ] run_gui: 3 checks left (label brings the View tab forward: the ribbon stays on Home after the label tool; every shape tool made its object: the two-click arc makes nothing; startup options expectation). Fixed: wire split and paste-back checks (stale: libplace row and drop position)
- [x] run_contextmenu / run_contextmenu2 / run_symboleditor / run_busphase: not a placement bug. The library panel lists symbols alphabetically (BUZZER first), the tests assumed file order (R first). Tests now find the first-by-NameID symbol's row; contextmenu2's common list gained Select All Alike; symboleditor's libselect and hint count updated. All four pass.
- [ ] run_zoomwheel: status bar panel widths are 290/140/170/350/35 of 1000, the test expects 20/20/8/50/2 per cent (stale test or a layout change)
- [ ] run_notewrap: narrow note box wraps to 2 lines, the test expects 3 or more (table metrics narrower than the font drawn: environment sensitive)
- [ ] run_wireghost: widths 1 and 3 both measure as 1 pixel at the test's zoom (test too coarse)
- [ ] settingstest driver needs the LCL paths to build (README says so)
- [ ] Pasting right after copying nothing in an empty document gives an access violation
- [ ] The tests copy the 9 MB program into a new temp folder each run and never remove it: the disk fills up on a full run

## 2026-10-21 late
- [x] "Invalid floating point operation" in IsCompletelyInside when dragging a box to the left on a sheet with a rung grid: the grid has no corners (NaN). Fixed: TDrawRungGrid.IsCompletelyInside (columns and height texts) and a NaN guard in the base. Test tests/run_leftdrag_rungs.py (Linux does not raise the floating point error, so the test checks the result, not the crash; mutation not meaningful here). Other objects with unset corners (check any object type that leaves PointB invalid) not audited.
- [x] A new rung grid on another sheet started in Arial: it now takes font and colour from the nearest other sheet's grid (TSchematicView.TakeRungFontFromOtherSheet). Test tests/run_rungfontsheets.py (mutation checked). Not done: the other grid settings (rows, margin...) and fonts of other tools (text, ladder) are not carried between sheets.
- [x] (confirmed working on Windows by the user, 2026-10-21) Ctrl+C/X/V/A/Z/Y in a text box went to the Edit menu (the drawing) instead of the box: fixed with TfrmMain.EditShortcutInBox (mark set in FormKeyDown, same way as Del). NOT tested: script mode cannot send key events; check on Windows by pasting text into the property text box, the find box and a dialog. Combo boxes are not covered.

## Parts database (TCParts), draft 1 - design only, no program code yet
- [x] docs/parts_schema.sql (classes + inherited fields + child-object kinds + values, ratings, links, symbols, 3D, documents, offers, substitutes, rules, options; inheritance views and triggers), docs/parts_seed.py (class tree, kinds, sample P2-04AD-1 and a contactor), tests/run_partsschema.py (11 checks, mutation checked)
- [ ] Decide: ratings as rows (done in draft) plus fixed columns for the common ones? 3D model inside the file or beside it? One part with several electrical views?
- [ ] Reader/writer unit in Pascal, the "breaking compatibility" warning on first placement, symbol editor writing Symbol/SymbolPin, a parts browser, import of TinyCAD libraries (symbol only, electrical data empty)
- [ ] Per-design copy of the parts used (like TinyCAD's embedded symbols) and a version stamp
- [x] Parts file schema versioning: FormatInfo.SchemaVersion + PRAGMA user_version + SchemaHistory table; docs/parts_upgrade.py (rules at the top: backup, one transaction per step, refuse newer/foreign files); tests/run_partsupgrade.py (8 checks, mutation checked). The Pascal reader must follow the same rules. Rule for every schema change: add a step, raise CURRENT, update parts_schema.sql.
- [x] Parts schema draft 2: Part.UID (GUID), LibraryInfo, Outline2D + OutlineTerminal (2D footprint), PartTag. tests/run_partsschema.py now 13 checks.
- [ ] User builds the library viewer tabs (Symbols / Parts); program then: loads the DLL only when a library is opened; warns on first part pick that TinyCAD compatibility is broken, with "don't show again" (an app setting, not in the parts file); Pascal reader/writer following docs/parts_upgrade.py rules.
- [ ] Still to map: how a placed part is stored in a .dsn (UID + library UID + a copy of the data used), and how the part's symbol replaces TinyCAD's symbol placement.
- [x] CSplitButton / TSplitButton (main click + arrow popup), tests/run_splitbutton.py. Not seen on Windows; not yet used anywhere in the program (candidates: the parts picker, Insert buttons).
- [x] CSplitButton: palette icon merged (CSplitButton.lrs, LResources in uses, {$I CSplitButton.lrs} in initialization), palette page "Additional" as in the user's copy.
- [x] Library panel with Symbols / Parts tabs merged from the user's QLibPanel.pas/.lfm (Parts tab empty). Changes to the user's .lfm: ActivePage = tsSymbols (it was saved with Parts active), a Hint on the page control (the hints test needs one). hints_theme, libsort, contextmenu, hotspot, symboleditor pass.
- [x] TSplitButton.OnDropDownClick; Details panel: sbSheetDetails (rulers, check button) + sbExtendedInfo wired, other details on FDetailsDropDown; Close All and Alignment as split-button menus; user's mainform/fsharedctls merged. Not seen on Windows (drop-down form position, 24x24 look).
- [x] Parts schema draft 3 (decided with the user): generic Part (requirements) vs Product (manufacturer, MPN, actual ratings, documents, 3D model, footprint, offers); Rating is a part's requirement or a product's rating; RatingQuantity (unit + min/max/match sense); views ProductFit / ProductFitSummary (oversized allowed, undersized / missing / mismatch flagged). tests/run_partsschema.py 20 checks (independent oracle, mutation checked), run_partsupgrade.py 8. Still schema version 1 (nothing has shipped).
- [x] docs/parts_design_storage.md: what the .dsn keeps (part copy, product snapshot, typed details) and the rules of the verify check and BoM.
- [ ] Pascal: the design verify check for chosen products (follow ProductFit rules); placed-part details for manufacturer / model number; BoM resolved / unresolved; store part copy + product snapshot in the .dsn.
- [x] Parts schema: PartGlyph (one PNG per size, multi-resolution) for the lists / trees; Symbol.Drawing is the same TinyCAD XML blob as a .TCLib symbol (decided). run_partsschema 22 checks.
- [ ] Pascal parts reader + sample file, Parts tab as a list view with 24x24 glyphs (user builds the control, program fills the image list from PartGlyph), then placing a part, then editing.
- [x] Pascal parts reader src/UPartsDb.pas (open with the upgrade rules, classes, parts, glyph by nearest size, required ratings, products + fit verdict), script commands pdb*, tests/run_partsdb.py 14 checks.
- [ ] Next: Parts tab list (icons from GlyphPng into the image list) once the user's control exists; placing a generic part (Symbol XML -> existing symbol loader, compatibility warning with 'don't show again'); part copy + product snapshot in the .dsn; editing (add / edit / delete).
- [x] Parts tab: placeholder list view + 24x24 image list + Open button in QLibPanel (OpenPartsFile, OnPartSelected / OnPartPlace), tests/run_partstab.py 7 checks. Not seen on screen (the tab was not switched in a screenshot).
- [ ] Next: place a generic part on double click (Symbol XML -> symbol loader) with the compatibility warning; remember the parts file; then .dsn part copy + product snapshot; editing.
- [x] Placing a generic part from the Parts tab (symbol XML via the symbol loader, name + reference prefix, PartUID / PartLibraryUID in memory), compatibility warning (task dialog, once per run, 'do not show again' = settings PartsWarningOff), tests/run_partsplace.py 10 checks. Schema: Part.RefPrefix; sample parts now have symbols.
- [x] Part copy (`<PART>`: GUIDs, name, class, requirements) on the placed symbol and product choice (`<PRODUCT>`: manufacturer, model, ratings, or just typed text) on the placement are saved in the .dsn and loaded back; fit is judged from the file alone (`UPartData.CheckFit`, same rules as the SQL views); undo and paste keep them (`tests/run_partsdsn.py`).
- [ ] Next: details UI for the product (choose from the library / type manufacturer + model) in the property frame; design verify check (undersized / missing / mismatch); BoM resolved / unresolved; editing; remember the parts file.
- [ ] Not verified: the task dialog on Windows (verification check box), that PartsWarningOff survives a restart.

# ROADMAP: parts database and electrical design (fleshed out 2026-10-23)
Order matters: each phase builds on the one before. Every item follows the standing rules (faithful to TinyCAD where TinyCAD has the feature, tests with an independent oracle plus a mutation check, doc-comment headers with Notes, README + this list updated). [ ] open, [x] done.

## Phase A - parts in the design (.dsn)  [in progress]
- [x] A1 Part copy + product choice saved/loaded in the .dsn, undo and paste keep them, CheckFit in Pascal = SQL views (run_partsdsn)
- [~] A2 (done: properties sym.mfr / sym.model for a placed part, Choose Product window (Fproductpick) with fit words, fit text + detail lines (UProps.PartFitText / PartFitDetail), last parts file remembered and reopened, nopart/nolibrary handling; tests/run_partsdetails.py 23 checks. Left: the user's property frame controls (edMfr / edModel / button / fit label named per QPropFrame) and the 'Choose...' button wiring to TfrmMain.ChooseProduct; A2d, A2e) Property frame for a placed part: show part name/class, "Product" group: manufacturer, model number (typed), and a "Choose from library..." button (dialog listing the part's products with verdict column: fits / oversized / does not fit)
  - [x] A2a choosing a product copies its ratings into the placement (undoable); typing only manufacturer/model clears ratings (unresolved)
  - [x] A2b choosing needs an open parts file: if none, offer to open one; remember the last parts file in settings and reopen it at start (also fixes "remember the parts file")
  - [~] A2c (logic done; label control is the user's) a "fit" read-only line under the group: verdict + count of undersized/missing/mismatch, with a tooltip listing each requirement (need vs have)
  - [ ] A2d multi-select: the details of several placed parts at once (set manufacturer for all of the same part)
  - [ ] A2e library-changed warning: if the part in the library has a newer Revision than the copy in the design, say so (the design keeps its copy; offer "update copy" that re-reads needs, shows what changed, undoable)
  - [x] A2f library file missing / different LibraryUID: the placed part still works from its copy; show "(library not found)" and never block opening
- [~] A3 (done: UPartCheck, run inside Special > Check Design Rules after the ERC lines, settings PartCheck / PartCheckUnresolved / PartCheckOversized, tests/run_partcheck.py 26 checks; left: the options dialog controls, A3d) Design verify check (Special > Check, next to ERC): one message per undersized/missing/mismatch line, with the part reference, quantity, need, have; double click jumps to the part; oversized reported as info only (setting to hide); unresolved products (no model chosen) reported as a warning (setting to turn off)
  - [x] A3a markers on the sheet like ERC markers; clear on re-run (the ERC clears and renumbers; marker k = line k)
  - [ ] A3b options in the ERC options dialog (unresolved = error/warning/ignore; oversized = show/hide)
  - [x] A3c test against the sample parts: all five products of the two parts give the SQL verdicts; message count oracle from sqlite
  - [ ] A3d hierarchical designs: check placed sub-designs too, with the path prefix like the BoM
- [x] A4 (done 2026-10-24: UPartsList part columns Manufacturer, Model number, Status resolved / typed only / unresolved, Fit; only when the design has placed parts; tests/run_partsbom.py 32 checks; the run_partslist output is unchanged) BoM (Create Parts List): new columns Manufacturer, Model number, Status (resolved / unresolved / typed only); group lines by (part, manufacturer, model); unresolved lines grouped by generic part name with the count; CSV/text/spreadsheet writers updated; TinyCAD's own columns unchanged when no part data
- [ ] A5 Netlist/SPICE/VHDL: confirm placed generic parts export like ordinary symbols (reference, name); add the manufacturer/model as attributes for the netlist writers that take attributes
- [ ] A6 Copy to another design / paste across designs: the part copy travels with it (done via XML); check pasting into a design that opens the library later
- [ ] A7 Replace symbol / update symbol (ReplaceSymbol) keeps or drops PartInfo deliberately; test
- [ ] A8 Old TinyCAD reading a new .dsn: unknown <PART>/<PRODUCT> elements must be skipped by TinyCAD's reader - verify from the C++ reader source and document the result in the warning text (the warning is currently ahead of the storage: make it truthful)
- [ ] A9 Binary .dsn writer: n/a (new data is XML only); state it in the README

## Phase B - the parts library editor (add / edit / delete)
- [x] B1 New parts file (Parts > New Parts Library..., done 2026-10-24; name/description/author dialog still to come with B2): schema, LibraryInfo with a fresh GUID, empty class tree; Save As / copy
- [x] B2 (done 2026-10-24; editor is a tab of the document strip; see README "Parts library editor, part list") Part list: Add part (name, class, ref prefix, description), Rename, Delete (confirm; refuse when products reference it), Duplicate, Revision bump on every save, Modified stamp
- [x] B3 (done 2026-10-24; Classes page of the parts editor tab; see README "Parts library editor, class tree") Class tree editor: add/rename/delete classes, parent, inherited fields shown read-only; own fields added/changed/deleted
- [x] B4 (done 2026-10-24; Requirements page of the parts editor tab; part ratings apply to the whole part or one object, `kind:` only exists for product ratings) Requirements (ratings of a part): grid editor with quantity pick list (RatingQuantity), unit, min/typ/max, condition, applies-to (whole part / object / kind); validation (unit must match the quantity; min<=typ<=max)
- [x] B5 (done 2026-10-24; Objects page of the parts editor tab; object field values and class MinCount/MaxCount not covered) Child objects of a part (terminals, channels, poles) editor with kind, designator, parent
- [x] B6 (done 2026-10-24; Products page with Fit and Suggested columns, ratings grid, Values page for part and object field values: run_partsproducts 38 checks, run_partsvalues 16 checks; ten product and nine value mutations caught; the Fit oracle re-implements the verdict in Python) Products editor: manufacturer, MPN, series, description, status; their ratings (same grid, AppliesTo object or kind:X); PartProduct suggestions (link a product to the generic parts it is meant for); live ProductFit verdict column for the selected part
- [x] B7 (done 2026-10-24; Symbols page, run_partssymbols 38 checks, thirteen mutations caught; SymbolPin mapping NOT done; multi-part symbols are stored but placed as part 1) Symbol editing: "Edit symbol" opens the existing symbol editor on the part's Symbol blob and writes back (TinyCAD XML) with pin <-> PartObject mapping; new symbol from scratch; import symbol from a .TCLib
- [x] B8 (done 2026-10-24; glyphs 16/24/32/48 are drawn again whenever a symbol of the part is added, stored, made default or deleted; importing a PNG NOT done; checked in run_partssymbols) Glyph: generate the PartGlyph PNG rows (20/24/36/48/100...) from the symbol drawing automatically on save; or import a PNG
- [ ] B9 Outline2D (footprint), Model3D (STEP/WRL/etc. as blob or file reference), Document (datasheet PDF as blob or link), Offer (supplier, SKU, price breaks, date), Substitute (product A can replace B): editors, each optional
- [ ] B10 Concurrent safety: file opened read-only by default; "Edit" takes a write lock; refuse if SQLite is busy; always back up before schema upgrade (done) and before bulk edits
- [ ] B11 Undo for library edits (transaction per user action; Edit > Undo inside the editor)
- [~] B12 (CSV import of products with ratings and suggestions, and CSV export, done 2026-10-24: run_partsimport 52 checks; import of .TCLib symbols as parts NOT done) Import: CSV of products (manufacturer, MPN, ratings) into an existing generic part; import TinyCAD .TCLib symbols as parts with empty electrical data; export part as CSV
- [ ] B13 Merge two parts files (by UID; conflicts reported, never silently overwritten)
- [ ] B14 Library integrity check command (foreign keys, orphan ratings, unit/quantity mismatches, products without class) with a report dialog

## Phase C - Parts tab polish
- [ ] C1 Grouping by class (tree-like indentation or group headers in the list view), column sort, search box filter (name, class, description, MPN)
- [ ] C2 Hint/tooltip on a row: description, ref prefix, product count; icon from the nearest PartGlyph size when the user resizes the list (re-pick when the image list size changes)
- [ ] C3 Right-click menu: Place, Edit part..., Show products, Copy GUID
- [ ] C4 Several parts files open at once (a combo of open libraries) and a Recent list
- [ ] C5 Drag a part from the tab onto the sheet (drag/drop), in addition to double click
- [ ] C6 Large library performance: lazy glyph loading for thousands of rows; test with a generated 5000-part file
- [ ] C7 Screenshot test of the tab (the earlier screenshot showed the Symbols tab): switch the tab, check the icons visible
- [ ] C8 Windows check: icon scaling at high DPI (24x24 at 150 percent picks the 36 glyph)

## Phase D - electrical design features that use the data
- [ ] D1 Terminal-level checks: a wire connected to a pin whose PartObject rating (e.g. max voltage) is below the net's declared voltage; needs net voltage/current annotations first
- [ ] D2 Net attributes (voltage, current, signal type: analog 4-20 mA, 24 V DC, 120 V AC...) and a check that connected channels match (mismatch status already exists in the rating model)
- [ ] D3 Wire/cable sizing from currents (ampacity table as a library table, not code)
- [ ] D4 Channel/terminal assignment for modules: pin number labels from PartObject.Designator ("channel 1 terminal 3") shown on the placed symbol
- [ ] D5 Cross references: coil <-> contact of the same device (K1) using the part's child objects (needs the electrical views decision below)
- [ ] D6 Several electrical views of one part (open decision): coil view + contact views + terminal strip view as separate symbols of one device; how the BoM counts it once
- [ ] D7 Terminal strips / cable schedules / wiring lists reports from the .dsn
- [ ] D8 Panel layout (using Outline2D) - far future

## Phase E - schema and file decisions still open
- [ ] E1 Ratings as rows plus fixed columns for the common ones? Current: rows only. Decide after A3/A4 show the real query cost
- [ ] E2 3D model inside the file (blob) or beside it (path): current schema allows both; pick the default and document
- [ ] E3 Several electrical views of one part (see D6)
- [ ] E4 Units: store SI and convert on display? Current: unit text per rating with RatingQuantity.Unit; add a conversion table (mA -> A) so a 4-20 mA module and a 0.02 A product compare
- [ ] E5 Currency/price storage for Offer (decimal as integer minor units)
- [x] E6 Schema version 2 shipped with Symbol.ShowsObject (parts plan step 1). Old note: nothing shipped yet; the moment a parts file leaves the test folder, raise CURRENT with a step and keep docs/parts_upgrade.py in sync
- [ ] E7 Localisation of class and quantity names (Name stays the key; add display names)

## Phase F - things to verify on Windows (cannot be done here)
- [ ] F1 Split button look and drop-down form position; Details drop-down; 24x24 look
- [ ] F2 TTaskDialog with the verification check box; PartsWarningOff survives a restart
- [ ] F3 Parts tab appearance and the glyph icons; sqlite3.dll found next to the exe (loaded only on opening a library); error text when it is missing
- [ ] F4 Tests with hard-coded pixel positions after the ribbon height change (run all pixel tests on the Linux build and recalibrate)
- [ ] F5 Old .dsn from real TinyCAD still opens and saves unchanged when no part is placed (byte-level comparison of the sheets section)

## Phase G - open items carried from earlier (see the sections above for detail)
- [ ] G1 run_gui 3 failures, run_zoomwheel, run_notewrap, run_wireghost, settingstest driver LCL paths
- [ ] G2 Paste after copying nothing in an empty document: access violation
- [ ] G3 Tests leave 9 MB temp binaries: clean up in every runner (shared helper) so the disk does not fill
- [ ] G4 Cross-sheet paste crash (never reproduced): add a stress script
- [ ] G5 Full regression (106 scripts) after Phase A, then after Phase B
- [ ] G6 Real old binary .dsn files to confirm UDsnBinary
- [ ] G7 Audit other objects with unset corners (NaN guard follow-up)
- [ ] G8 Above-block extended cell with two pages

## Working rules for every item (checklist)
1. Read the C++ first when TinyCAD has the feature; port faithfully, note deliberate deviations in README.
2. Test with an independent oracle (sqlite3/Python), then break the code and see the test fail (mutation).
3. Doc-comment header with Notes on each new function; run tools/fmt_ifthen.py on changed files.
4. Delete stale lib/*.ppu when an interface changes; run only the relevant tests and say that the full regression was skipped.
5. Update README.md and this list (also TyCAD/TyCAD_todo.md), zip, send with a short caption.

## Symbol properties (qsymbols frame, FSymDDD parameter list), 2026-10-24
- [x] Symbol frame (TfmSymbols, registered as 'method') for the symbol being placed (tool panel) and the selected symbol: rotate button (Up > Right > Down > Left) with menu (four directions, Mirror), Ref text, Show reference, Show power pins (the symbol is shifted so the other pins stay put, as OnBnClickedShowpower), Allow resizing. New properties sym.dir / sym.mirror / sym.showref / sym.showpower. tests/run_symbolframe.py 26 checks, three mutations caught.
- [x] Parameter list (TfmSymbolPropList in FSymDDD.pas) as TinyCAD's list: Parameter / Show? / Value, click Show? to toggle, click Value to edit (Enter keeps, Esc drops), name editable and Delete enabled only for parameters added here, Add = 'Other' / '..' one line below the lowest; one undo step per change for a selected symbol.
- [ ] Not seen on Windows: the drop-down position and look of the list, the inline edit box over the list view, the menu of the rotate button.
- [ ] The part-in-package letter (TinyCAD's small box next to Ref, sym.part) has no control in the frame yet; property not added.
- [ ] The list is for one symbol (the placed or the single selected one); a multi-selection says to select one.
- [ ] The rotate button's picture does not change with the direction (the hint says it); needs four images in ilSpeedBtn.
- [ ] Keyboard: Up/Down in the list, Tab from cell to cell, Delete key.
- [ ] Hierarchical symbols have their own options dialog in TinyCAD (EditDlgHierarchicalEdit): same layout without the list; not done.

- 2026-10-24: the parameter list (FSymDDD) is now a TStringGrid: Show? is a Yes/No turned over by a click, Value (and the name of an added parameter) is edited right in the cell with the grid's own editor, so the drop-down no longer closes mid-edit. Verified on Linux only; run_symbolframe 26/26 with a mutation check.
- 2026-10-24: Show? column draws a check box from ilChecked (index 0 = on, 1 = off; looked up on the main form by name, with two built-in boxes as a fallback). Linux-checked only for build/tests; the look is unverified.
- 2026-10-24: (1) parameter list instantly hiding: TSplitButton now opens an owner's drop-down form on the arrow's release, not its press (a menu still opens on press); unverified on Windows. (2) The ladder rung button no longer appends its drawn icon to ilSpeedBtn at run time (it landed on the index used by sbAllowResize); its design-time ImageIndex 60 is used.
- 2026-10-24: TfmSymbols.AfterCreate gives its speed/split buttons frmSharedControls.ilSpeedBtn and turns ShowHint on for those with a hint (the frame's .lfm names the image list of another form, which only the designer resolves; at run time Images was nil, so no pictures). Other frames with such buttons may have the same problem (check Images in their .lfm). Unverified on Windows.
- 2026-10-24: the parameter drop-down moved onto TfmSymbols: the frame makes and pops its own TfmSymbolPropList (ParametersClick); the owner supplies the symbol (OnGetSymbol) and makes the undo step (OnParameterChange). Tool frame and selection frame each have their own list.
- 2026-10-24: renamed TfmSymbolPropList to TfrmSymbolPropList (a form, not a frame); FSymDDD.lfm root must read 'inherited frmSymbolPropList: TfrmSymbolPropList' (the nil grdParams access violation came from the old name in the form file). User's new qsymbols.lfm layout adopted. Check ilSpeedBtn.Count > 67 in the user's fsharedctls.lfm (sbAllowResize ImageIndex 66).
- 2026-10-24: TSplitButton.Click is overridden so OnClick runs only for a release on the main part (csClickEvents also sent a Click for the arrow, so OnClick and OnDropDownClick both fired).
- 2026-10-24: Options > Fonts: the Symbol Font (face, size in points, bold, italic) is TinyCAD's pin font (font 1): applied in place to every sheet, kept in the registry (SymbolFontName/Points/Bold/Italic), given to new designs (EditDefaults). It draws the reference and the other symbol fields AND pin names/numbers (as TinyCAD does); a REF-only font would need a separate font resource (decision for the user). New control TFontNameCombo (src/comp/CFontNameCombo.pas, in tycad_components.lpk: also needs the LCL package now; install the package again). qproptext's cbFont could use it. Verified on Linux only (run_symbolfont.py 12 checks).
- 2026-10-24: every font combo of the property frames (text, note, wire label, measure, ladder, rungs) is now a TFontNameCombo (the custom DrawFonts / type-ahead code is gone; the control lists and draws the fonts itself). Foptions uses sbBold/sbItalic speed buttons (GroupIndex 1/2, AllowAllUp). run_realframes no longer pins the bold button's image index.

2026-10-24: View menu mirrors wired. `DoDesignDetailsRuler` handles miShowRulers (toggles the ribbon Details button and the drop-down box), `DoDesignDetailsExtended` handles miExtendedInfo, `DoToggleSnap` handles miGridSnap (ticked from UpdatePositionBar). Grid Size submenu (miGridSize) is filled by BuildGridSizeMenu as a one-for-one copy of the grid popup; SyncGridSizeMenus keeps captions (units) and the tick current. New script commands viewmenuinfo / gridmenuclick; new tests/run_viewmenu.py (36 checks, mutation-checked). Windows: check the submenu tick and the Show Rulers tick on a real menu.

2026-10-24: Print preview junction dots were huge: PaintJunction (and the arrow-end circle) used a fixed 2 px minimum radius, which dominates on the reduced preview page. New TSchematicPainter.MinDotRadius: 2 on screen, 1 when FPrinting (print, export, preview). run_export passes; no dedicated pixel test yet (todo: count junction pixels at preview scale).

2026-10-24: Help > About no longer shows the 'Text measuring: real fonts' line (TextMetricsName is still available).

2026-10-24: A3 + A4 done. A4: TBomEntry.Extra is part of the sort key, so lines group by (part, product); unresolved parts group by generic name with their count; Fit is shown for resolved products only. A3: UPartCheck.RunPartCheck; undersized/missing/mismatch = 'Part does not fit' (error), no product / typed only = warning (setting: ignore / warning / error), oversized = information (setting to hide); numbered after the ERC lines (RunCheck now asks RunErc for no 'No errors' line and adds it itself). Left for A3: the three settings have no dialog controls yet (script `partcheck on= unresolved= oversized=`), A3d hierarchical designs. Editor decision (user): the parts editor is a window in the main workspace with its own top workspace tab (with open documents and symbols).

2026-10-24: Print dialog on Windows raised 'Printer ... doesn't exist' (SetPrinter) when the printer list reported a change to the entry it already showed. Now ignored (TfrmPrint.FLastPrinter), the pick is skipped when Printer.PrinterIndex already is that entry, and a refused pick puts the list back (RevertPrinter). Not verified on Windows; run_printdialog passes.

2026-10-24: Windows: selecting the Brother MFC-J6960DW fails inside LCL (TWinPrinter.DoSetPrinter returns -1 when DocumentPropertiesW gives no DEVMODE, reported as 'doesn't exist'). The error message now adds Windows' own reason (PrinterProbe: OpenPrinter / DocumentProperties error number); the Windows branch is not compiled here. User is trying a different driver.

2026-10-24: Print dialog line 'Pages: all  Copies: 1' now ends with 'Size: W x H mm' (TfrmPrint.SizeText: the sheet showing at the scale in the box; halves at 50%). lbRange widened to 440 in Fprint.lfm. run_printdialog passes; checked by hand at 100% and 50%.

2026-10-24: Print dialog: second line under 'Pages / Copies': 'Sheet: W x H mm (W x H in)   Printable page: W x H mm (W x H in)' (TfrmPrint.SizeText). The printable page is what the printer library reports (not the paper's edges). lbRange is now 545 x 36. Not seen on screen.

2026-10-24: Ribbon height 108 -> 92 (mainform line 1132, user's request). Symbol frame width 168 is set in the user's own qsymbols.lfm (our copy still says 403 until it is sent again).

2026-10-24: Menus moved to the .lfm (rule from now on: every static menu item is made in the .lfm, only run-time items in code). The Library menu is now `mSymbol` ('S&ymbols' - the request said "S&mbols", assumed a typo; change the caption in the lfm if "Smbols" was meant): its 18 items (miSym*, sepSymbol*) are in mainform.lfm, BuildSymbolMenu only ties Pin / Origin to their tools. New `mParts` ('&Parts', between Symbols and View) with Open Parts Library... (same as the Parts tab's Open button); the rest of its mirror (new library, new / edit / duplicate / delete part, import / export) comes with Phase B. Window menu: Next / Previous / Close Document / Close All Documents are static in the lfm (Ctrl+Tab, Ctrl+Shift+Tab, Ctrl+W); a separator and one entry per document are added at run time and all removed when no document is open (RebuildWindowMenu no longer clears the menu; 'Document List...' removed, the entries replace it). Ribbon height 92 made run_contextmenu's click point (120,100) miss the symbol: it now uses 118,88. hints added for the new items (run_hints_theme passes). run_gui: 4 failures remain (click on ladder, label tab, shape tools, options defaults) - known from before, not looked at.

2026-10-24: fsharedctls.lfm updated by the user (glyph list); sbDrawLadderRungs ImageIndex 60 -> 70 (mainform.lfm).

2026-10-24: FRibbon.Height back to Scale96ToForm(108) (two rows of labels on some property frames); run_contextmenu click point back to 120,100.

2026-10-24: Rung grid bottom handle. TDrawRungGrid.CanResize is True with one handle (HANDLE_BOTTOM, bottom centre; ResizeHandleRect/At virtual now); ResizeBy sets HasBottom/BottomMm (saved as `bottom` in <RUNGS>) and clears AboveBlock; the 'Above block' check box is gone from the frame (property kept for old files / tests). Tests: run_rungbottom (11 checks, mutation checked), run_rungabove, run_rungs (MOVE expectation updated: CanResize=1), run_rungui, run_realframes, run_hints_theme pass. Not seen on Windows (cursor is crSizeNS via CursorForHandle).
2026-10-24: fix - clicking the rung grid's bottom handle faulted in TDrawingObject.ResizeAspectRatio (grid has no PointA/B); ResizeAspectRatio is virtual, TDrawRungGrid returns 0.
2026-10-24: fix - with a rung grid on the sheet, the wire tool faulted (DRectNormalized on NaN): the grid has no PointA/B (NaN); TWireEngine.StickyPoint and the two wire hit loops in UEdit now skip objects without corner points. Not reproducible on Linux (NaN compares do not trap there); not seen on Windows.
2026-10-24: Wire right-click menu: 'Add wire cut here' (TSchematicView.WireCanCut/WireCutAt, TfrmMain.ContextWireCutClick; run-time item as it depends on the object). run_wirecut.py (21 checks, mutation checked); run_contextmenu2 updated for the extra first item on wires. Not seen on Windows.
2026-10-24: Arrow keys move the selection (TSchematicView.NudgeSelection/ArrowKey; script 'arrowkey'): one grid step with snap, one pixel (1/zoom) without; run_arrownudge.py (11 checks, mutation checked). Not seen on Windows: whether the sheet gets the arrow keys when it has the focus (ribbon controls keep theirs); Shift+arrow is the same as the arrow, Ctrl/Alt+arrow are left alone.
2026-10-24: Find/Replace dialog: frEntireScope (default ticked = every sheet of the current document; off = the sheet shown only; TFindSession.OnlySheet) and frPromptOnReplace (Replace All asks Yes/No/Cancel per occurrence: TfrmMain.ReplaceAllPrompted/AskReplace; one undo step per replacement). Both in fsharedctls.lfm Options. run_findscope.py (9 checks, mutation checked); run_find passes. Not seen on Windows: how the native replace dialog lays out the two boxes.
2026-10-24: QFindPanel.pas/.lfm taken from the user's edit (cbFindInAll 'Search all Sheets', ticked by default; the lfm now has no DesignTimePPI and references frmSharedControls.ilTinyIcons). Find panel: unticked lists only the sheet shown; entries are 'sheet name: object: text' (found text, not the search text). TfrFindPanel.FindInAll, TfrmMain.RunFindPanel; script 'finder <text> [sheet]'. run_findpanelscope.py (5 checks, mutation checked); run_gui's find-panel check updated for the new entry text (its 3 known failures remain, none in find).
2026-10-24: Ctrl+L / Ctrl+R / Flip did nothing while a symbol was being placed (they only rotated a selection): TSchematicView.RotateSelection now turns the placement ghost when the Place tool is active. Script commands libghost/ghostinfo; run_ghostrotate.py (8 checks, mutation checked). Not seen on Windows.
2026-10-24: Font drop-down type-ahead restored (TFontNameCombo.TypeAhead/KeyPress: keys within 1000 ms combine, after that the key alone; no match for the combined text tries the key alone; no match at all keeps the choice). Script 'fonttype'. run_fonttypeahead.py (12 checks, mutation checked) drives TypeAhead with given times; the real KeyPress path and Windows' own first-letter jump are not seen.
2026-10-24: FocusToolText asks CanFocus before SetFocus (placing a text object stopped the debugger at the exception SetFocus raised when the box could not take the focus, though it was caught). Unchanged behaviour otherwise; run_labelshapes passes.
2026-10-24: Selecting one placed symbol focuses edRef (property 'sym.ref') with the text selected: TfrmMain.FocusPropEditor (FocusTextEditor now calls it with 'text'), called from ViewSelection. NOTE: with the focus in the box the arrow keys move the caret, not the symbol, and Del edits the text - click the sheet (or Esc) to give the keys back to the sheet. run_symreffocus.py (5 checks, mutation checked).
2026-10-24: Another button pressed/released during a drag is ignored (TSchematicView.FDownButton; MouseDown/MouseUp): a middle click used to start a pan (drag mode 3) and drop the left button's rubber band. Script 'mouse mdown|mup'. run_middlewhiledrag.py (4 checks, mutation checked). Not seen on Windows.
(addendum) middle-click fix verified properly: with the guard removed run_middlewhiledrag fails 2 checks (band lost), with it all 4 pass. Script commands: 'mouse mdown|mup <x> <y>', 'dragmode'.
2026-10-24: 'Insert sheet' in the sheet tabs' menu now inserts after the clicked sheet (TfrmMain.DoInsertSheet/AddSheetAt; it used DoAddSheet = append). Hint changed from 'before this one'. run_insertsheet.py (6 checks, mutation checked); run_tabmenu passes. A hierarchical symbol sheet stays first.
2026-10-24: Paste of a selection with the rung grid + other objects faulted in BlockReference (Max on the grid's NaN PointA/B). New HasCorners(Obj) (UDrawingObjects) used by BlockReference, the export extent (UExport), RotateSelection's extent and ShowObject. Script 'fpuexceptions on|off' (makes the invalid-operation trap work on Linux too). run_gridselectall.py (3 checks; reproduces the exact fault when the guard is removed). Other loops over every object's PointA/B (UPlacedProbe, UGeomProbe, USymbols: symbol editing) not touched.
2026-10-24: Floating pasted block: middle button pans (MouseDown/MouseMove no longer swallow it while FPasting) and plain R / X rotate / flip it (KeyDown). Floating symbol (Place tool): the middle pan already worked, now tested. Script 'viewkey', 'vieworigin'. run_pastekeys.py (9 checks, mutation checked).
2026-10-24: Del in the auto-focused reference box (FRefAutoEdit/FRefAutoText in TfrmMain.FormKeyDown): deletes the symbol while the box is untouched (text unchanged, all selected), otherwise edits the text as before. Script 'formdel'. run_symreffocus now 7 checks (mutation checked).
2026-10-24: Static menus moved from code to mainform.lfm (pmDocTabs, pmGridSize + miGridSize items, pmPolyDraw, pmArcDraw, object items of pmSheet; FDocPopup/FGridMenu/BuildGridSizeMenu/FContextExtra and the view's ShowPolygonMenu removed). Dynamic menus stay in code (Window list, recent files, Copy to). New script command 'popup', run_menusinlfm (20 checks, mutation-checked). About form: user's layout (no 120 PPI) merged.
2026-10-24: Symbol reference box (edRef) takes the focus on a double click of the symbol (TfrmMain.ViewDblClick) instead of on selection. Script 'viewdblclick'; run_symreffocus 9 checks, mutation-checked.
2026-10-24: Phase B1 done: Parts > New Parts Library... (mPartsNew, DoNewPartsLibrary, TfrLibraryPanel.NewPartsLibrary/NewPartsFile + dlgPartsNew in QLibPanel.lfm, UPartsDb.CreatePartsFile, generated src/UPartsSchema.pas via tools/gen_partsschema.py). Script 'pdbtab new'. run_partsnew 21 checks, mutation checked. Not seen on Windows: the Save dialog.
2026-10-24: Phase B2 done: parts library editor tab (TDocument.PartsEditor, TfrmMain.OpenPartsEditor/ApplyDocVisibility, QPartsEditor frame, Fpartedit dialog), TPartsLibrary AddPart/UpdatePart/DuplicatePart/DeletePart/SetLibraryInfo/Reload, Parts menu: Edit Parts Library..., Add Part..., Part Properties..., Duplicate Part, Delete Part (all in the lfm). run_partsedit 38 checks, mutations caught. run_docmodel could not run here (build/doctest is not executable in this sandbox; it does not use the changed units). Not seen on Windows. Next: B3 class tree editor, B4 requirements grid.
2026-10-24: Phase B3 done: Classes page in QPartsEditor (tree + fields list, buttons, pop-ups), dialogs Fclassedit / Ffieldedit, TPartsLibrary AddClass/UpdateClass/DeleteClass/AddField/UpdateField/DeleteField (+ ClassFieldList, counts), Parts menu: Add Class..., Class Properties..., Delete Class, Add Field..., Field Properties..., Delete Field (all in the lfm). run_partsclass 43 checks, mutations caught (see README). Not seen on Windows. Next: B4 requirements grid.
2026-10-24: Stop-gap BoM and duplicate check (asked for until the parts feature is in use): Special > Check Duplicate References... and Export Symbol BoM (CSV)... (USymbolBom, run_symbom 35 checks). Not seen on Windows: the menu items, the save dialog and the message boxes. Also merged the user's UI changes (lfm files, qladder.pas, schematic.lpr, schematic.lpi) and the text direction box drawn from ilFontGlyphs 4-7.
2026-10-24: Fixed a crash when copying (Ctrl+drag) or moving a selection that holds a wire of no length: TWireEngine.AddAttachedObjects divided by the wire's length (EInvalidOp on Windows, where FP exceptions are on). It now skips a wire of no length, as C++ does through a NaN, and LineIsPointOnLine gives 0 for such a segment. Test: run_zerowire (4 checks, runs with `fpuexceptions on`; the crash was reproduced by removing both guards). Not found: how a wire of no length gets made by repeated copy/paste (the wire may need to be removed or refused when it is made).
2026-10-24: Phase B4 done: Requirements page in QPartsEditor, dialog Fratingedit, TPartsLibrary Quantities/PartObjects/AddRating/UpdateRating/DeleteRating (+ ID/ObjectID in TPartRating), Parts menu: Add Requirement..., Requirement Properties..., Delete Requirement. run_partsrating 41 checks, twelve mutations caught. Not seen on Windows. Next: B5 child objects editor (terminals, channels, poles).
2026-10-24: Phase B5 done: Objects page in QPartsEditor (tree), dialog Fobjectedit, TPartsLibrary ObjectKinds/KindIDOfName/AddObject/UpdateObject/DeleteObject/ObjectSubtreeCount (+ TObjectRef gained ParentID/KindID/Sort/Description), Parts menu: Add Object..., Object Properties..., Delete Object. run_partsobjects 41 checks, nine mutations caught. Not seen on Windows. Next: B6 products editor.
2026-10-24: Phases B5b/B6 done: Values page (field values of parts and objects) and Products page (catalog, ratings, suggestions, live fit). Phase B7 done: Symbols page (new / edit through the symbol editor with Store writing into the parts file / import from the library panel / properties / default / delete), TPartsLibrary symbol calls, Fsymbolinfo. Not seen on Windows. Next: B8 glyphs, B12 CSV import of products, SymbolPin mapping.
2026-10-24: Phase B12 (products part) done: Parts > Import Products from CSV... / Export Products to CSV... on the Products page; TPartsLibrary.ImportProductsCsv (all or nothing, 'Line n: reason') / ExportProductsCsv. Next: B8 glyphs, .TCLib symbols as parts, SymbolPin mapping.
2026-10-24: Phase B8 done: UGlyph.pas draws the part's default symbol into PartGlyph (16, 24, 32, 48 px) after every symbol change in the editor. Next: .TCLib symbols as parts, SymbolPin mapping, B9 (outline / model / document / offer / substitute).

## Translation (i18n)
- Done: user-facing text moved to src/UStrings.pas (about 750 resourcestrings) and the .lfm files; languages/schematic.pot (mkpo.py); LCLTranslator in schematic.lpr (--lang, -l, TYCAD_LANG); tests/run_i18n.py; README "Translating the program".
- Left: choice lists that double as keys, combo items in .lfm (status, standard, units), paper names, a language setting in the Options dialog, plural forms, check on Windows.

- Done: revision cloud resize handles; symbol parameter button toggles auto-show (arrow = once).

- Done: Options > Sheets (new sheet border, rulers, columns, rows, margin) wired to settings and New Document.

- Done: Symbol text object (SYMTEXT, tool + Draw menu + ribbon button) and Special > Export Symbol Data (CSV) with the two-pass column union (run_symdata 28 checks). Needs: its own ribbon icon (uses the Text icon); not seen on Windows. Deferred: editable Crystal-style report designer; paint check of the text on screen/print; rotating symbol text only moves its position.

- Done: text and wire-label frames re-laid out from the user's lfm files (wire label now uses the shared font glyph list, its own ImageList1 removed); removed a dangling `OnClick = plTextClick` from qpropnote.lfm (no such handler; the Note tool's panel would not load).

- Done: Choose Product window (TfrmProductPick) now has its controls in src/forms/Fproductpick.lfm (a TfrmBase; only the product rows and the translated texts are set in code); added to schematic.lpi; rsOK/rsCancel removed (the base buttons come from Fbase.lfm). run_partsdetails 23 checks pass. Not seen on Windows.

- Done: Symbol text had no text box and read as nothing when placed (an empty text is invisible): the symbol frame now has edSymbolText (symtext.text, symbol text only; focused when the tool is chosen), a placed one reads "Symbol text" if none typed; rpDrawWires width 163; middle-button viewport pan during a left drag (run_midpan 10 checks). Not seen on Windows.

- Done: symbol dragged around after clicking it with the parameter list on (the list opened under the held button and took the release): the list now waits for the release; a move with no button ends a lost drag. Not seen on Windows.

- Done: parameter name blanked when Show? is clicked after naming it (late grid entry report ignored); repaired copy of the user's Tongrun_Powder.dsn (the one fuse whose last parameter name was empty). Not seen on Windows.

- DONE: symbol text hit detection; auto-show list anchor; file drop on document tab strip (Windows drop untested).
- DONE: Do not print symbol text (print window); parameter list text editing keys + access violation on close. Not done: the option for exports (Export Image/PDF) - ask if wanted.
- DONE: Ctrl shortcuts in the parameter list box; Esc = Cancel in TfrmBase; Add selects the new row. Esc in base-form dialogs not covered by a test.
- DONE: stretching several chosen wires together by one end handle (the end nearest the handle on each wire).
- DONE: focus returns to the text box after a pan.
- DONE: second print check box for symbol property text.
- DONE: Special > Export Wires (wire labels and bus names, CSV). Assumed 'wire marker text' = wire labels + bus names; power symbol net names are not included.
- DONE: parameter list remembers its size for the session.
- DONE: parts plan step 1: part symbols record the Coil/Pole/Contact they draw (schema v2), placed part keeps it in the .dsn. NEXT: step 2 'Insert contact of K1' (docs/parts_review_and_roadmap.md). Not seen on Windows: the Shows drop-down layout.
- DONE: parts plan step 2 (Insert NO/NC/Next Free Contact of selected coil). NEXT: step 3 (rung assignment) / step 4 (cross-reference text with NO/NC and Add Rung Reference). Open: contact numbering across sheets is by reference text only; a coil with more contacts than the part has is just refused with a message.
- DONE: ruler units (right-click menu on the rulers, Options > Sheets > Ruler Units). The choice is program-wide, not per design; say if it should be saved in each design.
- DONE: pin property frame shown while the Pin tool is active. Open: a ghost of the pin under the cursor before the click (none is drawn today).
- [x] Symbol parameter list: a name typed (with or without Enter) is kept when Add is clicked, and a parameter can no longer be left with a blank name (src/forms/FSymDDD.pas; tests/run_symbolframe.py).
- [x] Layout changes from the user's .lfm files (mainform, fsharedctls, FSymDDD) taken in; plMain field added to TfrmSymbolPropList; languages/schematic.pot regenerated.
- DECISION (step 6, multi-pole bus): a multi-conductor bus is drawn as individual bus wires (one per conductor, at the pole spacing) grouped together internally as one multi-phase bus.
- [x] Parts plan step 3: rung assignment with the most-overlap rule, ambiguity flag, stored override and right-click Rung menu (ULinks, UView, mainform; tests/run_rungassign.py).
- [ ] run_gui.py: 3 checks already failing before step 3 (label View tab, shape tool objects, options defaults list) - look at when next in that file.
- [ ] Rung: a chosen rung does not follow the symbol when moved; consider clearing it when the symbol is moved to another rung.
- [x] Parts plan step 4: Add Rung Reference (XREF mode 2) with NO/NC forms; tests/run_rungref.py.
- [ ] Rung reference: choose the separator / a format (e.g. NO before the number), and a way to refresh position after moving the symbol.
- [x] Parts plan step 5: Poles and Contacts dialog (poles/contacts as part data, form, delay); tests/run_partsswitch.py. NEXT: step 6 (bus: individual wires grouped as one multi-phase bus, conductor count + spacing, right click Change to bus).
