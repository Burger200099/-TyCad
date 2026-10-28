unit UStrings;

{ Every text the program shows (messages, undo names, file dialogs, names of objects ...) is a resourcestring here, grouped by the file that uses it.
  tools/mkpo.py reads this file to make languages/schematic.pot; LCLTranslator looks the strings up as  ustrings.<name>  in lower case.
  Notes: a text with a value in it is a Format template (%s, %d) - use Format(rsName, [value]), never 'text' + value + 'text'.
  New code: add a resourcestring here instead of writing a literal in the code, then run  python3 tools/mkpo.py. }

{$mode objfpc}{$H+}{$codepage utf8}

interface

resourcestring

  { UDesign.pas }
  rsNotASymbolDocument = 'Not a symbol document';
  rsTheDesignContainsNoObjects = 'The design contains no objects';
  rsUnrecognisedDesignFileExpectedTinyCAD = 'Unrecognised design file (expected TinyCAD or TinyCADSheets)';
  rsFileNotFound = 'File not found: %s';
  rsThisFileDoesNotHave = 'This file does not have a hierarchical symbol associated with it';

  { UDocs.pas }
  rsParts = '%s (parts)';
  rsSymbol3 = '%s (symbol)';
  rsNewSymbol = 'New symbol';
  rsConverted = '%s (converted)';
  rsUntitled2 = 'Untitled %d';

  { UDrawingObjects.pas }
  rsDesignsCannotBeReadHere = 'Designs cannot be read here';

  { UDsnBinary.pas }
  rsTheFileEndsInThe = 'The file ends in the middle of an item';
  rsATextIsLongerThan = 'A text is longer than the rest of the file';
  rsAPictureIsLongerThan = 'A picture is longer than the rest of the file';
  rsSymbolsAreNestedTooDeeply = 'Symbols are nested too deeply';
  rsASymbolStoredAsXML = 'A symbol stored as XML inside a binary file is not supported';
  rsASymbolClaimsMoreFields = 'A symbol claims more fields than the file holds';
  rsNotATinyCADBinaryDesign = 'Not a TinyCAD binary design';

  { UErc.pas }
  rsThisReferenceIsAlsoUsed = 'This reference is also used with another symbol';
  rsThisOutputIsConnectedTo = 'This output is connected to another output';
  rsThisOutputIsConnectedTo2 = 'This output is connected to a power pin';
  rsThisNetworkIsNotConnected = 'This network is not connected to anything';
  rsThisTriStateOpenCollectorOutput = 'This TriState/Open Collector output is connected to another output pin';
  rsThisTriStateOpenCollectorOutput2 = 'This TriState/Open Collector output is connected to a power pin';
  rsNoErrorsWereFoundIn = 'No errors were found in this design.';
  rsThisReferenceDesignatorHasNot = 'This reference designator has not been assigned';
  rsThereAreOrMoreNets = 'There are 2 or more nets that are spelled with different case letters only.  These will be treated as separate nets.';
  rsThisNetHasMoreThan = 'This net has more than one name';
  rsThisItemIsNotConnected = 'This item is not connected to anything else';
  rsThisPowerIsConnectedTo = 'This power is connected to a different value power';
  rsMoreThanOneItemIs = 'More than one item is connected to a no-connect';
  rsThisNetworkHasNoOutput = 'This network has no output driving it';

  { UExport.pas }
  rsSVGFilesNeedTheCairo = 'SVG files need the Cairo library, which this Windows build does not include. Save a PNG instead.';
  rsUnknownKindOfImage = 'Unknown kind of image';
  rsTheScaleMustBeA = 'The scale must be a whole number from %d to %d.';
  rsNoSuchSheet = 'No such sheet';
  rsColourPNGBitmap = 'Colour PNG bitmap';
  rsBWPNGBitmap = 'B&W PNG bitmap';
  rsColourScalableVectorGraphicsSVG = 'Colour Scalable Vector Graphics (SVG)';
  rsBWScalableVectorGraphics = 'B&W Scalable Vector Graphics (SVG)';

  { UImageLoad.pas }
  rsUnknownImageFileType = 'Unknown image file type';
  rsWindowsMetafilesEmfCannotBe = 'Windows metafiles (.emf) cannot be inserted by this version.';
  rsUnableToReadTheImage = 'Unable to read the image file';
  rsUnableToOpenImageFile = 'Unable to open image file';
  rsCannotOpenFile = 'Cannot open file';
  rsThatFileIsNotA2 = 'That file is not a valid %s picture';

  { ULibManager.pas }
  rsCannotOpenLibrary2 = 'Cannot open library %s.'#10'%s';
  rsTheFileIsNotThere = 'The file %s is not there.';
  rsIsNotATCLibLibrary = '%s is not a .TCLib library.  The old .mdb and .idx libraries cannot be read.';
  rsCannotCreateLibraryTheFile = 'Cannot create library %s.'#10'The file %s is already there.';
  rsCannotCreateLibrary2 = 'Cannot create library %s.'#10'%s';
  rsCannotCleanUpLibrary = 'Cannot clean up library %s.'#10'%s';

  { ULibXML.pas }
  rsCannotReplace = 'Cannot replace %s';
  rsCannotWrite = 'Cannot write %s';
  rsCannotOpen = 'Cannot open %s';

  { ULibrary.pas }
  rsCannotLoadTheSQLiteLibrary = 'Cannot load the SQLite library. %s';
  rsNoDatabase = 'no database';
  rsCannotPrepare = 'Cannot prepare "%s"';
  rsCannotExecute = 'Cannot execute "%s"';
  rsCannotOpenLibrary = 'Cannot open library %s';
  rsCannotCreateLibrary = 'Cannot create library %s';
  rsCannotStoreSymbolDrawing = 'Cannot store symbol drawing';
  rsCannotStoreSymbolName = 'Cannot store symbol name';
  rsCannotStoreSymbolAttribute = 'Cannot store symbol attribute';
  rsIsThereButCouldNot = '%s is there but could not be loaded';
  rsWindowsErrorItMayNeed = '%s (Windows error %d: %s). It may need the Visual C++ runtime, or another sqlite3.dll earlier on the path may be in the way';
  rsWasNotFoundNextTo = '%s was not found next to the program (%s) or anywhere on the path.';

  { UNetList.pas }
  rsTooManyLevelsOfHierarchy = '%sToo many levels of hierarchy (recursion?)'#10;

  { UNetWriters.pas }
  rsThisPartHasNoPackage = 'This part has no ''Package'' attribute';

  { UOptions.pas }
  rsTheGridSpacingMustBe = 'The grid spacing must be more than 0 and not more than %d mm.';
  rsTheUnitsMustBeMillimetres = 'The units must be millimetres or inches.';
  rsTheAutoSnapRangeMust = 'The auto-snap range must be from 1 to %d design units.';
  rsTheTimeBetweenAutomaticSaves2 = 'The time between automatic saves must be from 1 to %d minutes.';
  rsTheSymbolFontNeedsA = 'The symbol font needs a name.';
  rsTheSymbolFontSizeMust = 'The symbol font size must be from %d to %d points.';

  { UPainter.pas }
  rsTitle = 'Title';
  rsAuthor = 'Author';
  rsFile = 'File';
  rsDocument = 'Document';
  rsSheets = 'Sheets';
  rsDate = 'Date';
  rsRevision = 'Revision';
  rsInvalidImage = 'Invalid image';

  { UPartCheck.pas }
  rsProductIsLargerThanRequired = 'Product is larger than required (information)';
  rsPartDoesNotFit = 'Part does not fit';
  rsNeedHave = '%s:  %s, %s: %s, need %s, have %s]';
  rsProductTypedByHandRatings = 'Product typed by hand, ratings unknown';
  rsPartHasNoProductChosen = 'Part has no product chosen';
  rsError = '%s (error)';
  rsWarning = '%s (warning)';

  { UPartData.pas }
  rsNoRequirements = 'No requirements';
  rsFits = 'Fits';
  rsFitsOversized = 'Fits (oversized)';
  rsDoesNotFit = 'Does not fit:';
  rsUndersized = '%s %d undersized,';
  rsMissing = '%s %d missing,';
  rsMismatched = '%s %d mismatched,';

  { UPartsDb.pas }
  rsThePartsFileDoesNot = 'The parts file does not exist: %s';
  rsCannotOpenThePartsFile = 'Cannot open the parts file %s';
  rsUnknownError = 'unknown error';
  rsThisIsNotATyCAD = 'This is not a TyCAD parts file.';
  rsThePartsFileIsVersion = 'The parts file is version %d, newer than this program (%d): not opened.';
  rsNoUpgradeStepFromVersion = 'No upgrade step from version %d.';
  rsStepFailedAndWasUndone = 'Step %d -> %d failed and was undone: %s (backup %s.v%d.bak)';
  rsCannotReadThePartsFile = 'Cannot read the parts file: ';
  rsThePartIsNotIn = 'The part is not in this library.';
  rsAGlyphIsBetweenAnd = 'A glyph is between 8 and 512 pixels wide.';
  rsTheGlyphHasNoPicture = 'The glyph has no picture.';
  rsNoPartsLibraryIsOpen = 'No parts library is open.';
  rsTheClassAlreadyHasA = 'The class already has a part with that name.';
  rsThePartsFileCannotBe = 'The parts file cannot be written (it is read-only or locked).';
  rsChooseWhatIsRatedA = 'Choose what is rated (a quantity).';
  rsIsNotAQuantityOf = '"%s" is not a quantity of this library.';
  rsTheUnitOfIsNot = 'The unit of %s is %s, not %s.';
  rsGiveAtLeastOneOf = 'Give at least one of minimum, typical and maximum.';
  rsTheMinimumIsAboveThe = 'The minimum is above the typical value.';
  rsTheTypicalValueIsAbove = 'The typical value is above the maximum.';
  rsTheMinimumIsAboveThe2 = 'The minimum is above the maximum.';
  rsThatObjectIsNotA = 'That object is not a part of this part.';
  rsThePartAlreadyHasA = 'The part already has a requirement for %s with that condition on the same object.';
  rsThatRequirementIsNotIn = 'That requirement is not in this library.';
  rsTheObjectNeedsAName = 'The object needs a name.';
  rsThePartAlreadyHasAn = 'The part already has an object named %s.';
  rsChooseTheKindOfThe = 'Choose the kind of the object.';
  rsThatKindOnlyGroupsOther = 'That kind only groups other kinds; choose one of its sub-kinds.';
  rsThePartSClassDoes = 'The part''s class does not allow this kind of child object.';
  rsTheParentIsNotAn = 'The parent is not an object of this part.';
  rsAnObjectCannotBePlaced = 'An object cannot be placed below itself or below one of its own children.';
  rsTheObjectHoldsValuesOf = 'The object holds values of fields that the new kind does not have.';
  rsThatObjectIsNotIn = 'That object is not in this library.';
  rsASymbolPinOutlineTerminal = 'A symbol pin, outline terminal or 3D terminal uses this object or one inside it; remove that first.';
  rsTheProductIsNotIn = 'The product is not in this library.';
  rsTheProductBelongsToAnother = 'The product belongs to another class than the part, so it cannot be suggested for it.';
  rsTheProductNeedsAManufacturer = 'The product needs a manufacturer.';
  rsTheProductNeedsAModel = 'The product needs a model number.';
  rsTheStatusMustBeActive = 'The status must be active, obsolete, preview or custom.';
  rsChooseAClassForThe = 'Choose a class for the product (an abstract class cannot hold products).';
  rsTheLibraryAlreadyHasA = 'The library already has a product %s %s.';
  rsTheProductIsSuggestedFor = 'The product is suggested for parts of its class; remove those suggestions before moving it to another class.';
  rsIsNotAKindOf = '"%s" is not a kind of object in this library.';
  rsTheProductAlreadyHasA = 'The product already has a rating for %s with that condition on the same target.';
  rsThatRatingIsNotA = 'That rating is not a product rating of this library.';
  rsThatFieldIsNotA = 'That field is not a field of the part''s class.';
  rsThatObjectIsNotAn = 'That object is not an object of this part.';
  rsThatFieldIsNotA2 = 'That field is not a field of the object''s kind.';
  rsIsNotAWholeNumber = '"%s" is not a whole number.';
  rsIsNotANumber = '"%s" is not a number.';
  rsIsNotYesOrNo = '"%s" is not yes or no.';
  rsIsNotOneOf = '"%s" is not one of: %s.';
  rsIsNotANumber2 = '"%s" is not a number (%s).';
  rsTheManufacturerIsEmpty = 'The manufacturer is empty.';
  rsTheModelNumberMPNIs = 'The model number (MPN) is empty.';
  rsIsNotAPartOf = '"%s" is not a part of this library.';
  rsNamesPartsOfMoreThan = '"%s" names parts of more than one class.';
  rsIsNotAClassOf = '"%s" is not a class of this library.';
  rsTheProductIsNewSo = 'The product %s %s is new, so it needs a class (or a part to take it from).';
  rsARatingNeedsAQuantity = 'A rating needs a quantity.';
  rsTheFileHasNoLines = 'The file has no lines.';
  rsLineIsNotAColumn = 'Line 1: "%s" is not a column of the product import (columns: Manufacturer, MPN, Series, Class, Status, Description, Part, Preferred, Quantity, Unit, Condition, AppliesTo, Min, Typ, Max).';
  rsLineTheColumnIsThere = 'Line 1: the column "%s" is there twice.';
  rsLineTheColumnsManufacturerAnd = 'Line 1: the columns Manufacturer and MPN are needed.';
  rsLine = 'Line %d: %s';
  rsTheSymbolNeedsADrawing = 'The symbol needs a drawing standard (IEC, ANSI ...).';
  rsThePurposeMustBeSchematic = 'The purpose must be schematic, oneline, panel or block.';
  rsTheSymbolCouldNotBe = 'The symbol could not be written to the parts file.';
  rsTheSymbolHasNoDrawing = 'The symbol has no drawing.';
  rsThatSymbolIsNotIn = 'That symbol is not in this library.';
  rsThisIsThePartS = 'This is the part''s default symbol, which must be a schematic one; make another symbol the default first.';
  rsThatSymbolBelongsToAnother = 'That symbol belongs to another part.';
  rsOnlyASchematicSymbolCan = 'Only a schematic symbol can be the default.';
  rsThePartNeedsAName = 'The part needs a name.';
  rsChooseAClassForThe2 = 'Choose a class for the part (an abstract class cannot hold parts).';
  rsTheLibraryNeedsAName = 'The library needs a name.';
  rsThatChangeWouldLeaveFields = 'That change would leave fields with the same name in a class, or parts with values or child objects that the class would no longer have. Move or change those parts first.';
  rsAClassWithThatName = 'A class with that name exists already.';
  rsTheClassHasAField = 'The class has a field of that name already.';
  rsTheClassNeedsAName = 'The class needs a name.';
  rsTheParentClassIsNot = 'The parent class is not in this library.';
  rsTheClassIsNotIn = 'The class is not in this library.';
  rsAClassCannotBeMoved = 'A class cannot be moved under itself or one of its own subclasses.';
  rsTheClassHasPartsOr = 'The class has parts or products, so it cannot be abstract.';
  rsTheClassHasSubclassesDelete = 'The class has subclasses. Delete or move them first.';
  rsTheClassHasPartsDelete = 'The class has parts. Delete or move them first.';
  rsTheClassHasProducts = 'The class has products.';
  rsAPartRuleRefersTo = 'A part rule refers to the class.';
  rsAProductOptionChangesOne = 'A product option changes one of the fields of the class.';
  rsTheFieldNeedsAName = 'The field needs a name.';
  rsTheTypeMustBeText = 'The type must be text, int, real, bool, enum or ref.';
  rsAnEnumFieldNeedsIts = 'An enum field needs its values (separated by commas).';
  rsAFieldOfThatName = 'A field of that name exists in this class, one of its parents or one of its subclasses.';
  rsTheFieldIsNotIn = 'The field is not in this library.';
  rsPartsHaveValuesForThis = 'Parts have values for this field, so its type cannot change.';
  rsPartSHaveAValue = '%d part(s) have a value for this field.';
  rsAProductOptionChangesThis = 'A product option changes this field.';
  rsTheFileAlreadyExists = 'The file already exists: %s';
  rsCannotCreateThePartsFile = 'Cannot create the parts file %s';

  { UPrint.pas }
  rsPagesStartAt = 'Pages start at 1.';
  rsThereAreNoPagesTo = 'There are no pages to print.';
  rsPageDoesNotExistThe = 'Page %d does not exist: the print has 1 page.';
  rsPageDoesNotExistThe2 = 'Page %d does not exist: the print has %d pages.';
  rsTypeThePagesToPrint = 'Type the pages to print, for example 1-3, 6.';
  rsCannotBeReadInThe = '"%s" cannot be read in the pages to print.';
  rsAPageNumberWasExpected = 'A page number was expected here (for example 1-3, 6).';
  rsTheLastPageOfThe = 'The last page of the range is missing.';
  rsJoinPagesWithAComma = 'Join pages with a comma or "and", and the ends of a range with - or "to".';

  { UPrintRun.pas }
  rsA4PageNoPrinter = 'A4 page (no printer)';

  { UProps.pas }
  rsAngle = 'Angle';
  rsArc = 'Arc';
  rsText = 'Text';
  rsDirection = 'Direction';
  rsLabelType = 'Label type';
  rsSymbol = 'Symbol';
  rsFont = 'Font';
  rsSizePt = 'Size (pt)';
  rsBold = 'Bold';
  rsItalic = 'Italic';
  rsTextColor = 'Text color';
  rsColor = 'Color';
  rsWidth = 'Width';
  rsStyle = 'Style';
  rsFill = 'Fill';
  rsFillColor = 'Fill color';
  rsPhases = 'Phases';
  rsSpacingMm = 'Spacing (mm)';
  rsClosed = 'Closed';
  rsScallopMm = 'Scallop (mm)';
  rsUnits = 'Units';
  rsGraduations = 'Graduations';
  rsPositionMm = 'Position (mm)';
  rsShows = 'Shows';
  rsTargetObjectId = 'Target object id';
  rsPrefix = 'Prefix';
  rsSuffix = 'Suffix';
  rsLeftBusWireNo = 'Left bus wire no.';
  rsRightBusWireNo = 'Right bus wire no.';
  rsRows = 'Rows';
  rsFirstNumber = 'First number';
  rsIndentMm = 'Indent (mm)';
  rsPagesPerSheet = 'Pages per sheet';
  rsContinueNumbering = 'Continue numbering';
  rsShowRowHeight = 'Show row height';
  rsAboveTheTitleBlock = 'Above the title block';
  rsReference = 'Reference';
  rsName = 'Name';
  rsResizable = 'Resizable';
  rsScaleX = 'Scale X';
  rsScaleY = 'Scale Y';
  rsMirror = 'Mirror';
  rsShowReference = 'Show reference';
  rsShowPowerPins = 'Show power pins';
  rsManufacturer = 'Manufacturer';
  rsModelNumber = 'Model number';
  rsPinName = 'Pin name';
  rsPinNumber = 'Pin number';
  rsLength = 'Length';
  rsNumberPosition = 'Number position';
  rsPinType = 'Pin type';
  rsElectricalType = 'Electrical type';
  rsShowName = 'Show name';
  rsShowNumber = 'Show number';
  rsCentreName = 'Centre name';

  { USpiceVhdl.pas }
  rsOnSheetHasUnimplementedMacro = '%s: %s on sheet %d has unimplemented macro ''%s'''#10;
  rsOnSheetUnknownQueryOperand = '%s: %s on sheet %d unknown query operand ''%s'''#10;
  rsOnSheetPinNotFound = '%s: %s on sheet %d pin ''%s'' not found'#10;
  rsOnSheetAttributeNotFound = '%s: %s on sheet %d attribute ''%s'' not found'#10;
  rsPinOnSheetHasA = '%s: Pin on sheet %d has a blank pin name.  Pin number = "%s"'#10;
  rsPinOnSheetHasA2 = '%s: Pin on sheet %d has a blank pin number.  Pin name = "%s"'#10;
  rsPinOnSheetHasA3 = '%s: Pin on sheet %d has a duplicate pin name.  Pin name = "%s", Pin number = "%s"'#10;
  rsPinOnSheetHasA4 = '%s: Pin on sheet %d has a duplicate pin number.  Pin name = "%s", Pin number = "%s"'#10;
  rsOnSheetHasNoModel = '%s: %s on sheet %d has no model'#10;

  { USymEdit.pas }
  rsNameIsEmpty = 'Name %d is empty';
  rsTheNameIsUsedTwice = 'The name "%s" is used twice';
  rsTheNameHasNoReference = 'The name "%s" has no reference prefix';
  rsPinBelongsToPartBut = 'Pin %s belongs to part %d but the symbol has %d part(s)';
  rsAPinHasNoNumber = 'A pin%s has no number';
  rsPinNumberIsUsedMore = 'Pin number %s is used more than once';
  rsPinsAndAreOnTop = 'Pins %s and %s are on top of each other';
  rsPartHasNoPins = 'Part %d has no pins';
  rsPinIsNotOnThe = 'Pin %s is not on the grid, so wires will not snap to it cleanly';
  rsPinsAreNotOnThe = '%d pins are not on the grid (the first is pin %s), so wires will not snap to them cleanly';
  rsTheSymbolHasNoPins = 'The symbol has no pins';

  { UView.pas }
  rsChange = 'Change %s';
  rsDelete = 'Delete';
  rsTheOriginCanOnlyBe = 'The origin can only be set when a library symbol is being edited';
  rsPinsCanOnlyBePlaced = 'Pins can only be placed on the hierarchical symbol sheet or when a library symbol is being edited';
  rsThisToolCannotBeUsed = 'This tool cannot be used while a library symbol is being edited';
  rsAddRungNumbers = 'Add rung numbers';
  rsRemoveReference = 'Remove reference';
  rsAddReference = 'Add reference';
  rsDrawArc = 'Draw arc';
  rsDrawPolygon = 'Draw polygon';
  rsAddLabel = 'Add label';
  rsPinsCanOnlyBePlaced2 = 'Pins can only be placed on the hierarchical symbol sheet and the origin only when a library symbol is being edited';
  rsAddPin = 'Add pin';
  rsSetOrigin = 'Set origin';
  rsAddJunction = 'Add junction';
  rsAddNoConnect = 'Add no connect';
  rsAddPowerSymbol = 'Add power symbol';
  rsAddBusSlash = 'Add bus slash';
  rsAddText = 'Add text';
  rsAddSymbolText = 'Add symbol text';
  rsSymbolText = 'Symbol text';
  rsSymbolTextClickWhere = 'Symbol text: click where it goes, then type its text and fields in Properties';
  rsAddRuler = 'Add ruler';
  rsClickTheObjectTheText = 'Click the object the text should follow';
  rsNowClickWhereTheText = 'Now click where the text should go';
  rsAddLink = 'Add link';
  rsDraw = 'Draw';
  rsPlaceSymbol = 'Place symbol';
  rsPlaced = 'Placed %s %s';
  rsMoveField = 'Move field';
  rsResize = 'Resize';
  rsEditPolygon = 'Edit polygon';
  rsMove = 'Move';
  rsCopiedObjectS = 'Copied %d object(s)';
  rsPaste = 'Paste';
  rsTheClipboardDoesNotHold = 'The clipboard does not hold a TinyCAD drawing';
  rsClickToPlaceThePasted = 'Click to place the pasted objects (right click or Esc to cancel)';
  rsPasted = 'Pasted';
  rsImport = 'Import';
  rsThatFileIsNotA = 'That file is not a TinyCAD design that can be imported';
  rsClickToPlaceTheImported = 'Click to place the imported objects (right click or Esc to cancel)';
  rsImported = 'Imported';
  rsInsertPicture = 'Insert picture';
  rsClickToPlaceThePicture = 'Click to place the picture (right click or Esc to cancel)';
  rsPicturePlaced = 'Picture placed';
  rsRotateLeft = 'Rotate left';
  rsRotateRight = 'Rotate right';
  rsFlip = 'Flip';
  rsAlignToGrid = 'Align to grid';
  rsBringToFront = 'Bring to front';
  rsSendToBack = 'Send to back';
  rsFreeLine = 'Free line';
  rsArcIn = 'Arc in';
  rsArcOut = 'Arc out';
  rsCurve = 'Curve';
  rsAddHandle = 'Add handle';
  rsDeleteHandle = 'Delete handle';
  rsMakeVertical = 'Make vertical';
  rsMakeHorizontal = 'Make horizontal';
  rsAddWireCut = 'Add wire cut';
  rsSelectClickShiftClickOr = 'Select: click, shift-click or drag a box; drag to move';
  rsWireClickTheStartClick = 'Wire: click the start, click corners, double-click or right-click to finish';
  rsLineClickTheStartClick = 'Line: click the start, click to continue, double-click or right-click to finish';
  rsPolygonClickEachCornerDouble = 'Polygon: click each corner, double-click or right-click to finish';
  rsRectangleClickAndDragOr = 'Rectangle: click and drag, or click two corners';
  rsCircleClickAndDragOr = 'Circle: click and drag, or click two corners';
  rsArcClickTheStartAnd = 'Arc: click the start and the end';
  rsNoteClickAndDragA = 'Note: click and drag a box';
  rsCloudClickAndDragA = 'Cloud: click and drag a box';
  rsLabelClickOnAWire = 'Label: click on a wire';
  rsJunctionClickWhereWiresMeet = 'Junction: click where wires meet';
  rsHorizontalRulerClickToPlace = 'Horizontal ruler: click to place a guide line';
  rsVerticalRulerClickToPlace = 'Vertical ruler: click to place a guide line';
  rsMeasureClickPointAThen = 'Measure: click point A, then point B';
  rsLadderRailsDragARectangle = 'Ladder rails: drag a rectangle for the two rails';
  rsLineNumberLinkClickThe = 'Line-number link: click the object to follow, then click where the text goes';
  rsContactsLinkClickTheCoil = 'Contacts link: click the coil (or contact), then click where the text goes';
  rsPlaceSymbolClickToPlace = 'Place symbol: click to place, R rotates, X mirrors, Esc or right-click cancels';
  rsBusClickTheStartClick = 'Bus: click the start, click corners, double-click or right-click to finish';
  rsBusSlashClickWhereThe = 'Bus slash: click where the bus is joined';
  rsNoConnectClickOnA = 'No connect: click on a pin that is left unconnected';
  rsPowerSymbolClickToPlace = 'Power symbol: click to place it (choose its kind and direction in Properties)';
  rsTextClickWhereTheText = 'Text: click where the text goes, then type it in Properties';
  rsReferencePainterClickASymbol = 'Reference painter: click a symbol to give it the next reference, right-click to remove it, Esc to finish';
  rsPinClickWhereThePin = 'Pin: click where the pin connects (it starts as the last pin, counted on); set its name, number and direction in Properties';
  rsOriginClickToPutThe = 'Origin: click to put the origin of the symbol';
  rsRungNumbersTheSheetS = 'Rung numbers: the sheet''s rung number grid (made if the sheet has none, otherwise selected); set it up in Properties';

  { UXMLException.pas }
  rsErrorFirstDetectedOnLine = '%s.'#10'Error first detected on line #%d.'#10;

  { UXMLReader.pas }
  rsXMLReaderThereIsNo = 'XML reader: there is no current tag';

  { FSymDDD.pas }
  rsParameter = 'Parameter';
  rsShow = 'Show?';
  rsValue = 'Value';
  rsYes = 'Yes';
  rsNo = 'No';
  rsMixed = 'Mixed';

  { Fclassedit.pas }
  rsNoneARootClass = '(none - a root class)';
  rsClass = 'Class';
  rsClassProperties = 'Class Properties';
  rsAddClass = 'Add Class';

  { Fdetails.pas }
  rsREV = 'REV';
  rsDATE2 = 'DATE';
  rsDESCRIPTION = 'DESCRIPTION';
  rsBY = 'BY';
  rsDesignDetails = 'Design Details';
  rsTheNewestRevisionOfThe = '(the newest revision of the history)';
  rsGiveTheRevisionALabel = 'Give the revision a label, such as A or 2.1.';
  rsClickHereToAddA = 'Click here to add a revision';
  rsEveryRevisionNeedsALabel = 'Every revision needs a label in the REV column (row %d has none).';
  rsTheBorderMarginMustBe2 = 'The border margin must be a number of millimetres, 0 or more.';
  rsTheBorderMarginIsToo = 'The border margin is too big for the page.';

  { Fercopts.pas }
  rsCheck = '&Check';

  { Fexport.pas }
  rsExport = '&Export';
  rsTheSelectedObjectsAreSaved = 'The selected objects are saved.';
  rsTheWholeSheetIsSaved = 'The whole sheet is saved.';
  rsExportImage = 'Export Image';
  rsVectorDrawingAllFiles = 'Vector drawing (*%s)|*%s|All files (*.*)|*.*';
  rsBitmapAllFiles = 'Bitmap (*%s)|*%s|All files (*.*)|*.*';
  rsEnterTheNameOfThe = 'Enter the name of the file to write.';

  { Ffieldedit.pas }
  rsField = 'Field';
  rsAddField = 'Add Field';
  rsFieldProperties = 'Field Properties';

  { Finput.pas }
  rsInput = 'Input';
  rsPleaseEnterANumberBetween = 'Please enter a number between %s and %s.';

  { Flibraries.pas }
  rsTheSymbolLibrariesInUse = 'The symbol libraries in use';

  { Fnetlist.pas }
  rsNetlistAllFiles = 'Netlist (*%s)|*%s|All files (*.*)|*.*';

  { Fnewdoc.pas }
  rsAllSizes = 'All sizes';
  rsPageXUnitsMmPer = '%s'#10#10'Page: %d x %d units'#10'(0.2 mm per unit)';

  { Fobjectedit.pas }
  rsThePartItself = '(the part itself)';
  rsObject = 'Object';
  rsThePartSClassAllows = 'The part''s class allows no child objects, so there is no kind to choose.';
  rsTheOrderMustBeA = 'The order must be a whole number.';
  rsObjectProperties = 'Object Properties';
  rsAddObject = 'Add Object';

  { Foptions.pas }
  rsOptions = 'Options';
  rsCustom = 'Custom';
  rsTheGridSpacingIsNot = 'The grid spacing is not a number.';
  rsTheAutoSnapRangeIs = 'The auto-snap range is not a whole number.';
  rsTheTimeBetweenAutomaticSaves = 'The time between automatic saves is not a whole number of minutes.';
  rsNoConnectMarks = 'No-connect marks';
  rsPins = 'Pins';
  rsPowerSymbols = 'Power symbols';
  rsNoteBackground = 'Note background';
  rsNoteBorder = 'Note border';
  rsNoteText = 'Note text';

  { Fpagesetup.pas }
  rsPageXUnitsMmPer2 = '%s'#10'Page: %d x %d units'#10'(0.2 mm per unit)';
  rsEnterTheWidthAndHeight = 'Enter the width and height in millimetres.';
  rsPageSetup = 'Page Setup';
  rsTheWidthAndHeightMust = 'The width and height must be numbers of millimetres.';
  rsThePageIsTooSmall = 'The page is too small.';

  { Fpartedit.pas }
  rsPart = 'Part';
  rsChooseAClassForThe3 = 'Choose a class for the part.';
  rsPartProperties = 'Part Properties';
  rsAddPart = 'Add Part';

  { Fpartslist.pas }
  rsTextFile = 'Text file';
  rsCSVFile = 'CSV file';
  rsSpreadsheetCompatibleCSVFile = 'Spreadsheet compatible CSV file';
  rsPartsListAllFiles = 'Parts List (*%s)|*%s|All files (*.*)|*.*';

  { Fpreview.pas }
  rsOnePage = 'One &Page';
  rsTwoPage = 'Two &Page';
  rsPagesOf = 'Pages %d-%d of %d';
  rsPageOf = 'Page %d of %d';

  { Fprint.pas }
  rsNoPrinterIsInstalled = 'No printer is installed';
  rsPrint = '&Print';
  rsPrint2 = 'Print';
  rsShowingPageOfThePages = 'Showing page %d of the %d pages chosen';
  rsPagesAll = 'Pages: all';
  rsPages = 'Pages: %s';
  rsCopies = '     Copies: %d';
  rsCollated = '%s (collated)';
  rsXMmXIn = '%s x %s mm (%s x %s in)';
  rsSheet2 = 'Sheet: -';
  rsSheet3 = 'Sheet: %s';
  rsPrintablePage = '%s   Printable page: %s';
  rsPageAcrossAndDown = '%d page%s: %d across and %d down';
  rsOnEachOfSheets = ' on each of %d sheets';
  rsTheScaleMustBeA2 = 'The scale must be a number above 0.';
  rsTheScaleMustNotBe = 'The scale must not be more than %d.';
  rsNoPages = 'No pages';

  { Fproductedit.pas }
  rsProduct = 'Product';
  rsTheLibraryHasNoClass = 'The library has no class a product can belong to; add one on the Classes page first.';
  rsProductProperties = 'Product Properties';
  rsAddProduct = 'Add Product';

  { Fproductpick.pas }
  rsProductsFor = 'Products for %s';
  rsKeepTheProductAsIt = 'Keep the product as it is';
  rsUseTheSelectedProduct = 'Use the selected product';
  rsTheProductsOfThePart = 'The products of the part''s class and how well each fits';
  rsChooseProduct2 = 'Choose Product';
  rsFit = 'Fit';

  { Fratingedit.pas }
  rsTheWholePart = '(the whole part)';
  rsAppliesTo = 'Applies &to:';
  rsWhatTheRatingIsFor = 'What the rating is for: the whole product, every object of a kind (kind:Contact) or one object by its name (Pole 1)';
  rsTheWholeProduct = '(the whole product)';
  rsUnit = 'Unit: %s';
  rsARequirementIsComparedWith = 'A requirement is compared with the maximum, else the typical, else the minimum value given here.';
  rsAProductMustOfferAt = 'A product must offer at least this much.';
  rsAProductMustStayAt = 'A product must stay at or below this.';
  rsAProductMustMatchThis = 'A product must match this exactly.';
  rsRequirement = 'Requirement';
  rsChooseWhatIsRated = 'Choose what is rated.';
  rsTheMinimumTypicalAndMaximum = 'The minimum, typical and maximum must be numbers (or empty).';
  rsRequirementProperties = 'Requirement Properties';
  rsAddRequirement = 'Add Requirement';
  rsProductRatingProperties = 'Product Rating Properties';
  rsAddProductRating = 'Add Product Rating';

  { Fsymprops.pas }
  rsDisplayMethod = 'Display Method';
  rsDefaultValue = 'Default Value';
  rsLibrary = 'Library: %s';
  rsPartsPerPackage = 'Parts per package: %d';
  rsShowValueOnly = 'Show Value Only';
  rsHideValue = 'Hide Value';
  rsNeverShow = 'Never Show';
  rsShowValueExtraOnly = 'Show Value (Extra Only)';
  rsShowNameValueWhenPresent = 'Show Name=Value when present';
  rsShowNameValue = 'Show Name=Value';
  rsShowValueWhenPresent = 'Show Value when present';
  rsOther = 'Other';

  { Fvalueedit.pas }
  rsRequired = ', required';
  rsOfDeclaredBy = '%s (%s%s%s) of %s; declared by %s.';
  rsNone = '(none)';
  rsAWholeNumber = 'A whole number.';
  rsANumberAPointOr = 'A number; a point or a comma is the decimal mark.';
  rsTheNameOfWhatIt = 'The name of what it refers to.';
  rsText2 = 'Text.';
  rsThePart2 = 'the part';
  rsYes2 = 'yes';
  rsNo2 = 'no';
  rsValueOf = 'Value of %s';

  { fbusdropdown.pas }
  rsXGrid = '%d x grid';

  { mainform.pas }
  rsAddSheet = 'Add sheet';
  rsAddASheetToThe = 'Add a sheet to the drawing';
  rsNothingSelected = 'Nothing selected';
  rsWhatIsSelectedTheProperties = 'What is selected; the properties the selection shares are beside it';
  rsUndo = 'Undo %s';
  rsUndoCtrlZ = 'Undo (Ctrl+Z)';
  rsRedo = 'Redo %s';
  rsRedoCtrlY = 'Redo (Ctrl+Y)';
  rsGrid = 'Grid: %s';
  rsProperties = 'Properties';
  rsMixed2 = '(mixed)';
  rsFillMixed = 'Fill: mixed';
  rsFill2 = 'Fill %s %s';
  rsBusPhase = 'Bus: 3 phase';
  rsBusPhase2 = 'Bus: 1 phase';
  rsBusMixed = 'Bus: mixed';
  rsDesignDetailsAllSheets = 'Design details (all sheets)';
  rsDesignDetails2 = 'Design details';
  rsPageSetup2 = 'Page setup';
  rsTheFileIsNoLonger = 'The file %s is no longer there. It has been taken off the list.';
  rsCannotOpen2 = 'Cannot open %s:'#10'%s';
  rsNotFound = 'Not found';
  rsCannotFind = 'Cannot find "%s".';
  rsFound = '%d found';
  rsFound2 = '%d found.';
  rsCopyTheSelectionTo = 'Copy the selection to';
  rsDesignFilesDsnDsnAll = 'Design files (*.dsn)|*.dsn|All files (*.*)|*.*';
  rsCannotWrite2 = 'Cannot write %s:'#10'%s';
  rsThereIsNothingToCopy = 'There is nothing to copy: the selection holds no objects.';
  rsCopiedObjectTo = 'Copied 1 object to %s.';
  rsCopiedObjectsTo = 'Copied %d objects to %s.';
  rsImportADesign = 'Import a design';
  rsIsNotATinyCADDesign = '%s is not a TinyCAD design that can be imported.';
  rsInsertAPicture = 'Insert a picture';
  rsPicturesPngJpgJpegJpe = 'Pictures (*.png;*.jpg;*.jpeg;*.jpe;*.bmp)|*.png;*.jpg;*.jpeg;*.jpe;*.bmp|All files (*.*)|*.*';
  rsCannotInsert = 'Cannot insert %s:'#10'%s';
  rsAlreadyOnTheGrid = 'Already on the grid';
  rsObjectSMovedToThe = '%d object(s) moved to the grid';
  rsReachedTheEndOfThe = 'Reached the end of the %s: carried on from the start.';
  rsReachedTheStartOfThe = 'Reached the start of the %s: carried on from the end.';
  rsFoundIn = 'Found in %s: %s';
  rsReplaceAll = 'Replace all';
  rsReplacedOccurrence = 'Replaced 1 occurrence.';
  rsReplacedOccurrencesInObjects = 'Replaced %d occurrences in %d objects.';
  rsReplace = 'Replace';
  rsReplaceWithIn = 'Replace "%s" with "%s" in %s?';
  rsReplacedOfShownLeftAs = 'Replaced %d of %d shown; %d left as they were.';
  rsPart2 = 'Part %s';
  rsSheet = 'Sheet %d';
  rsTheSheetsOfASymbol = 'The sheets of a symbol are its parts: use Library > Parts per Package';
  rsUntitled = 'Untitled';
  rsSaveChangesTo = 'Save changes to %s?';
  rsReadTheOldBinaryDesign = 'Read the old binary design %s: use Save As to keep it in the current format';
  rsAddLadder = 'Add ladder';
  rsTinyCADDesignsDsnDsnDSN = 'TinyCAD designs (*.dsn)|*.dsn;*.DSN|All files|*.*';
  rsCannotSaveTheFile = 'Cannot save the file:'#10'%s';
  rsTheseCouldNotBeSaved = 'These could not be saved:'#10'%s';
  rsNoTwoSymbolsHaveThe = 'No two symbols have the same reference.';
  rsTheseReferencesAreUsedBy = 'These references are used by more than one symbol:'#10#10'%s';
  rsSymbolSHaveNoNumber = '%s'#10'%d symbol(s) have no number yet (Generate Symbol References numbers them).';
  rsCannotWriteTheBoMFile = 'Cannot write the BoM file.  Please try again with a different filename.';
  rsReferenceSAreUsedBy = '%d reference(s) are used by more than one symbol (Check Duplicate References lists them). ';
  rsSymbolSHaveNoNumber2 = '%s%d symbol(s) have no number yet. ';
  rsTheQuantitiesInTheBoM = '%sThe quantities in the BoM may be wrong.';
  rsExportSymbolBoM = 'Export Symbol BoM';
  rsExportSymbolData = 'Export Symbol Data';
  rsCannotWriteTheSymbolDataFile = 'Cannot write the symbol data file.  Please try again with a different filename.';
  rsCSVFileCsvCsvAll = 'CSV file (*.csv)|*.csv|All files (*.*)|*.*';
  rsCreateSpiceNetList = 'Create Spice Net List';
  rsSPICENetNetAllFiles = 'SPICE (*.net)|*.net|All files (*.*)|*.*';
  rsCreateVHDLFile = 'Create VHDL file';
  rsVHDLVhdVhdAllFiles = 'VHDL (*.vhd)|*.vhd|All files (*.*)|*.*';
  rsCannotWriteTheNetList = 'Cannot write the net list file.  Please try again with a different filename.';
  rsErrorWasFoundWhileMaking = '1 error was found while making the Spice net list.  It is listed in %s';
  rsErrorsWereFoundWhileMaking = '%d errors were found while making the Spice net list.  They are listed in %s';
  rsGenerateSymbolReferences = 'Generate symbol references';
  rsSomeSymbolsWereMissingFrom = 'Some symbols were missing from the libraries, and so could not be altered.';
  rsThatPrinterCannotBeUsed = 'That printer cannot be used: %s'#10#10'%s';
  rsThatPrinterCannotBeUsed2 = 'That printer cannot be used: %s';
  rsNoPrinterIsInstalled2 = 'No printer is installed.';
  rsThePrinterPropertiesCannotBe = 'The printer properties cannot be shown: %s';
  rsTheDesignCouldNotBe = 'The design could not be printed: %s';
  rsCannotWriteTheImageFile = 'Cannot write the image file.  Please try again with a different filename.';
  rsCannotWriteThePartsList = 'Cannot write the parts list file.  Please try again with a different filename.';
  rsSomeSymbolsDoNotHave = 'Some symbols do not have correct references, the parts list will be inaccurate.  Use Generate Symbol references.';
  rsTinyCADDesignsDsnDsn = 'TinyCAD designs (*.dsn)|*.dsn';
  rsCannotOpenTheSymbol = 'Cannot open the symbol:'#10'%s';
  rsTheSymbolCannotBeStored = 'The symbol cannot be stored:'#10'%s';
  rsCannotStoreTheSymbol = 'Cannot store the symbol:'#10'%s';
  rsSymbolStoredWarnings = 'Symbol stored. Warnings: %s';
  rsSymbolStored = 'Symbol stored';
  rsThisSymbolIsBeingEdited = 'This symbol is being edited. Close it before deleting it.';
  rsCannotDeleteTheSymbol = 'Cannot delete the symbol:'#10'%s';
  rsThereIsNoSuchLibrary = 'There is no such library.';
  rsCannotExportOverTheLibrary = 'Cannot export over the library file %s itself. Choose another name.';
  rsSymbolWrittenTo = '1 symbol written to %s';
  rsSymbolsWrittenTo = '%d symbols written to %s';
  rsCannotExportTheSymbols = 'Cannot export the symbols:'#10'%s';
  rsASymbolOfThisLibrary = 'A symbol of this library is being edited. Close or store it first.';
  rsSymbolAddedTo = '1 symbol added to %s';
  rsSymbolsAddedTo = '%d symbols added to %s';
  rsCannotImportTheSymbols = 'Cannot import the symbols:'#10'%s';
  rsXMLLibraryFileXmlXml = 'XML Library file (*.xml)|*.xml|All files|*.*';
  rsCopy = '%s copy';
  rsCannotDuplicateTheSymbol = 'Cannot duplicate the symbol:'#10'%s';
  rsCannotCopyTheSymbol = 'Cannot copy the symbol:'#10'%s';
  rsPartOf = 'Part %s of %d';
  rsDeleteThisSymbolFromIts = 'Delete this symbol from its library?';
  rsPartsLibrary = 'Parts library';
  rsChooseASymbolInThe = 'Choose a symbol in the library panel first.';
  rsTheChosenSymbolCannotBe = 'The chosen symbol cannot be read: %s';
  rsImportSymbol = 'Import Symbol';
  rsSymbolLibrariesTCLibTCLibTclib = 'Symbol libraries (*.TCLib)|*.TCLib;*.tclib|All files|*.*';
  rsCannotOpenTheLibrary = 'Cannot open the library:'#10'%s';
  rsCreateOrOpenADocument = 'Create or open a document first.';
  rsTinyCADFileDsnDsnAll = 'TinyCAD file (*.dsn)|*.dsn|All files (*.*)|*.*';
  rsOtherDesignsCannotBePlaced = 'Other designs cannot be placed while a library symbol is being edited';
  rsADesignCannotBePlaced = 'A design cannot be placed on the hierarchical symbol sheet';
  rsInsertAnotherDesignAsSymbol = 'Insert another design as symbol';
  rsThisDesignAlreadyHasA = 'This design already has a hierarchical symbol';
  rsAddHierarchicalSymbol = 'Add hierarchical symbol';
  rsChangeDesign = 'Change design';
  rsChooseTheDesignOfThe = 'Choose the design of the symbol';
  rsRenameSheet = 'Rename sheet';
  rsNameOfTheSheet = 'Name of the sheet:';
  rsADesignNeedsAtLeast = 'A design needs at least one sheet.';
  rsRemoveAndEverythingOnIt = 'Remove "%s" and everything on it?'#10'You can undo this.';
  rsRemoveSheet = 'Remove sheet';
  rsMoveSheet = 'Move sheet';
  rsLightMode = 'Light Mode';
  rsDarkMode = 'Dark Mode';
  rsReady = 'Ready';
  rsSnapToGridOn = 'Snap to grid: on';
  rsSnapToGridOff = 'Snap to grid: off';
  rsEnterANewGridSize = 'Enter a new grid size:';
  rsLadderRails = 'Ladder rails';
  rsRungNumbers = 'Rung numbers';
  rsSymbol2 = 'Symbol %s';
  rsWire = 'Wire';
  rsBus = 'Bus';
  rsLine2 = 'Line';
  rsPowerSymbol = 'Power symbol';
  rsBusSlash = 'Bus slash';
  rsNoConnect = 'No connect';
  rsPin = 'Pin';
  rsPicture = 'Picture';
  rsWireLabel = 'Wire label';
  rsPolygonArc = 'Polygon / arc';
  rsRectangleCircle = 'Rectangle / circle';
  rsNote = 'Note';
  rsCloud = 'Cloud';
  rsMeasure = 'Measure';
  rsRuler = 'Ruler';
  rsLinkedText = 'Linked text';
  rsJunction = 'Junction';
  rsDesignMarker = 'Design marker';
  rsObjectsChangesApplyToAll = '%d objects (changes apply to all)';
  rsChooseOneSymbolOnThe = 'Choose one symbol on the sheet first.';
  rsChooseTheNewSymbolIn = 'Choose the new symbol in the library list first.';
  rsThatSymbolCouldNotBe = 'That symbol could not be loaded.';
  rsReplaceSymbol = 'Replace symbol';
  rsReplacedWith = 'Replaced with %s';
  rsChooseTheNewSymbolIn2 = 'Choose the new symbol in the library list, then use Replace Symbol again.';
  rsReplaceSymbol2 = 'Replace Symbol';
  rsReplaceTheSymbolWithYes = 'Replace the symbol with %s?'#10#10'Yes keeps the field values of the old symbol, No uses those of the new one.';
  rsThisDesignWillNoLonger = 'This design will no longer open correctly in TinyCAD';
  rsPartsFromAPartsLibrary = 'Parts from a parts library keep their details (manufacturer, ratings and more) in the design in a form TinyCAD does not know. You can place the part, but TinyCAD will not read this design correctly any more.';
  rsDoNotShowThisAgain = 'Do not show this again';
  rsOtherSymbolsCannotBePlaced = 'Other symbols cannot be placed while a library symbol is being edited';
  rsThatPartHasNoSymbol = 'That part has no symbol yet.';
  rsThatPartSSymbolCould = 'That part''s symbol could not be loaded.';
  rsTheOpenPartsLibraryDoes = 'The open parts library does not have this part.';
  rsChooseProduct = 'Choose product';
  rsSelectASymbolToSee = 'Select a symbol to see its parameters.';
  rsSymbolParameters = 'Symbol parameters';
  rsRulers = 'Rulers';
  rsRulerColumns = 'Ruler columns';
  rsRulerRows = 'Ruler rows';
  rsBorder = 'Border';
  rsBorderMargin = 'Border margin';
  rsExtendedInformation = 'Extended information';
  rsTheNumberOfColumnsMust = 'The number of columns must be from 1 to 26.';
  rsTheLastRowMustBe = 'The last row must be a letter from A to Z.';
  rsTheMarginOfANew = 'The margin of a new sheet must be from 0 to %d millimetres.';
  rsTheBorderMarginMustBe = 'The border margin must be a number of millimetres that fits the page.';

  { QLibPanel.pas }
  rsSymbolLibrariesNoneOpen = ' Symbol libraries: (none open)';
  rsSymbolLibrary = ' Symbol library: %s';
  rsSymbolLibrariesOpen = ' Symbol libraries: %d open';
  rsTheExistingFileCannotBe = 'The existing file cannot be replaced: %s';
  rsPartsLibraryNoneOpen = 'Parts Library: (none open)';
  rsPartsLibrary2 = 'Parts Library: %s';

  { QPartsEditor.pas }
  rsGUID = '%s   (GUID %s)';
  rsDuplicatePart = 'Duplicate part';
  rsNameOfTheCopy = 'Name of the copy:';
  rsDeleteThePartWithIts = 'Delete the part "%s" with its fields, child objects, requirements and symbols?';
  rsProductSAreListedAs = '%s'#10#10'%d product(s) are listed as suitable for it; they stay in the library but lose that suggestion.';
  rsDesignsThatHavePlacedThe = '%s'#10#10'Designs that have placed the part keep their own copy. This cannot be undone.';
  rsDeletePart = 'Delete part';
  rsDeleteTheClass = 'Delete the class "%s"';
  rsAndItsFieldS = '%s and its %d field(s)';
  rsThisCannotBeUndone = '%s? This cannot be undone.';
  rsDeleteClass = 'Delete class';
  rsDeleteField = 'Delete field';
  rsDeleteTheFieldFromThe = 'Delete the field "%s" from the class "%s" (and so from its subclasses)? This cannot be undone.';
  rsDeleteRequirement = 'Delete requirement';
  rsDeleteTheRequirementForThis = 'Delete the requirement for %s (%s)? This cannot be undone.';
  rsDeleteTheObject = 'Delete the object %s?';
  rsTheObjectSInsideIt = '%s The %d object(s) inside it are deleted too.';
  rsItsRequirementsAndValuesGo = '%s Its requirements and values go with it. This cannot be undone.';
  rsDeleteObject = 'Delete object';
  rsNoPart = '(no part)';
  rsFits2 = 'fits';
  rsFitsOversized2 = 'fits, oversized';
  rsNoRequirements2 = 'no requirements';
  rsUndersized2 = 'undersized';
  rsMissing2 = 'missing';
  rsMismatch = 'mismatch';
  rsDoesNotFit2 = 'does not fit: %s';
  rsRemoveSuggestion = 'Remove &Suggestion';
  rsSuggestForPart = '&Suggest for Part';
  rsNotPreferred = 'Not &Preferred';
  rsPreferredForPart = '&Preferred for Part';
  rsDeleteProduct = 'Delete product';
  rsDeleteWithItsRatingsSuggestions = 'Delete %s %s with its ratings, suggestions, offers, documents and models? This cannot be undone.';
  rsDeleteRating = 'Delete rating';
  rsDeleteTheRatingForOf = 'Delete the rating for %s (%s) of this product? This cannot be undone.';
  rsThePart = '(the part)';
  rsRequiredMissing = 'required - missing';
  rsRequired2 = 'required';
  rsDefault = 'default';
  rsDeleteSymbol = 'Delete symbol';
  rsDeleteTheSymbolWithIts = 'Delete the symbol "%s" with its pin assignments? This cannot be undone.';
  rsTheFileCannotBeRead = 'The file cannot be read: %s';
  rsProductsAddedChangedRatingsAdded = 'Products added %d, changed %d; ratings added %d, changed %d; suggestions made or changed %d.';
  rsTheFileCannotBeWritten = 'The file cannot be written: %s';
  rsProductsWritten = 'Products written: %d.';
  rsImportProductsFromCSV = 'Import products from CSV';
  rsCSVFilesCsvCsvAll = 'CSV files (*.csv)|*.csv|All files|*';
  rsExportProductsToCSV = 'Export products to CSV';
  rsAbstract = '%s   (abstract)';
  rsPartSProductS = '%s   %d part(s), %d product(s)';
  rsOtherClass = '(other class)';

  { qsymbols.pas }
  rsMirror2 = '&Mirror';
  rsRotateSymbolUpRightDown = 'Rotate symbol (Up, Right, Down, Left)';
  rsNow = '%s: now %s%s';
  rsMirrored = ', mirrored';

  { Foptions.pas (units) }
  rsMillimetres = 'Millimetres';
  rsInches = 'Inches';

  { Fpagesetup.pas (orientation) }
  rsLandscape = 'Landscape';
  rsPortrait = 'Portrait';

implementation

end.
