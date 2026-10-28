// SPDX-License-Identifier: LGPL-2.1-or-later
{ The values of the Options dialog and what can be done with them away from the dialog: converting lengths between millimetres and
  inches, reading a number the way a person types it, checking the values, and moving them between the program's settings
  (what new designs start with, kept in the registry) and the dialog. The dialog itself is in Foptions, and the main form applies
  the result to the open designs.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UOptions;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Math, consts;

const
  UNITS_MM = 0;
  UNITS_INCHES = 1;
  MM_PER_INCH = 25.4;
  AUTOSAVE_MAX_MINUTES = 60;
  SNAP_RANGE_MAX = 200;
  SHEET_MARGIN_MAX_MM = 100;       // (the margin of a new sheet: a page cannot be smaller than twice this)
  GRID_MAX_MM = 1000;
  SYMBOL_FONT_MIN_POINTS = 4;
  SYMBOL_FONT_MAX_POINTS = 72;

type
  { everything the Options dialog shows }
  TOptionsData = record
    ShowGrid, SnapGrid: Boolean;
    GridMm: Double;                // the spacing of the grid, in millimetres whatever the units
    Units: Integer;                // UNITS_MM or UNITS_INCHES
    AutoDrag, AutoSnap, AutoJunction: Boolean;
    AutoSnapRange: Integer;        // in design units
    AutoSaveMinutes: Integer;      // 1 to 60; 0 for no automatic save
    ReopenDesigns: Boolean;        // open the designs that were open last time when the program starts
    SymbolFontName: String;        // the symbol font (what TinyCAD calls the pin font: the reference and the other fields of a symbol, and pin names and numbers)
    SymbolFontPoints: Integer;     // ... its size in points
    SymbolFontBold, SymbolFontItalic: Boolean;
    SheetBorder, SheetRulers: Boolean;   // what the sheet of a new design starts with: a border, rulers ...
    SheetCols, SheetRows: Integer;       // ... the rulers' columns and rows (1 to 26; the rows are shown as a letter)
    SheetMarginMm: Double;               // ... the distance of the border from the edge of the page, millimetres
    RulerUnits: Integer;                 // the units of the rulers round the drawing area: UNITS_MM, UNITS_INCHES, or -1 = those of the sheet
  end;

{ a length in millimetres as a number of the given units, and back }
function MmToUnits(Mm: Double; Units: Integer): Double;
{ the units the rulers round the drawing area show for a sheet: the one chosen for the rulers (ProgramSettings.RulerUnits), else the sheet's own }
function RulerUnitsFor(SheetUnits: Integer): Integer;
function UnitsToMm(Value: Double; Units: Integer): Double;
function UnitsSuffix(Units: Integer): String;
{ a length as text for the screen: "12.5 mm" or "0.492 in" }
function LengthText(Mm: Double; Units: Integer): String;
{ a position as TinyCAD's position bar shows it (COption::PointToUnit): two decimals and mm in millimetres, three decimals and an inch mark in inches; the numbers are
  padded to nine places and always have a point }
function PositionText(XMm, YMm: Double; Units: Integer): String;
{ the grid spacing as the position bar shows it (CDlgPositionBox::SetGridSize): in tenths of a millimetre or thousandths of an inch, four figures, from the spacing in
  design units }
function GridSizeText(GridUnits: Double; Units: Integer): String;
{ the label that goes with it: .1mm or .001" }
function GridSizeUnitsText(Units: Integer): String;
{ the next of the standard grid sizes (CTinyCadView::OnToggleGridSize): the normal grid (2 mm), the fine one (1 mm), then a half, a quarter and a tenth of that, and back to the
  normal one; any other spacing goes to the normal one. Spacings are in design units. }
function NextGridUnits(GridUnits: Double): Double;
{ a number as a person types it (a point or a comma for the decimals); False if it is not a number }
function ParseNumber(const S: String; out Value: Double): Boolean;
{ a number as text for an edit box: no more digits than mean anything, no trailing zeros }
function NumberText(Value: Double): String;
{ '' if the values can be used, otherwise what is wrong with them }
function OptionsError(const D: TOptionsData): String;
{ what a new design starts with: the program's settings }
function OptionsFromSettings: TOptionsData;
{ put the values into the program's settings (what is kept for next time) }
procedure OptionsToSettings(const D: TOptionsData);

implementation


uses UStrings;

{ ===========================================================================
  MmToUnits  (function)
  Parameters:
    Mm: Double - the length in millimetres
    Units: Integer - UNITS_MM or UNITS_INCHES
  Returns:
    Double - the length in those units
  Notes:
    A length in millimetres as a number of the given units.
  =========================================================================== }
function MmToUnits(Mm: Double; Units: Integer): Double;
begin
  if Units = UNITS_INCHES then
    Result := Mm / MM_PER_INCH
  else
    Result := Mm;
end;

{ ===========================================================================
  RulerUnitsFor  (function)
  Parameters:
    SheetUnits: Integer - the units of the sheet (UNITS_MM or UNITS_INCHES)
  Returns:
    Integer - UNITS_MM or UNITS_INCHES
  Notes:
    The rulers round the drawing area have a unit of their own, so the grid can be in millimetres and the rulers in inches. Until one is chosen (RulerUnits is -1) they
    follow the sheet.
  =========================================================================== }
function RulerUnitsFor(SheetUnits: Integer): Integer;
begin
  if ProgramSettings.RulerUnits in [UNITS_MM, UNITS_INCHES] then
    Result := ProgramSettings.RulerUnits
  else
    Result := SheetUnits;
end;

{ ===========================================================================
  UnitsToMm  (function)
  Parameters:
    Value: Double - the length
    Units: Integer - UNITS_MM or UNITS_INCHES
  Returns:
    Double - the length in millimetres
  Notes:
    A length in the given units as millimetres, rounded to a millionth so that 0.05 inch is 1.27
    mm and not 1.2700000000000002.
  =========================================================================== }
function UnitsToMm(Value: Double; Units: Integer): Double;
begin
  if Units = UNITS_INCHES then
    Result := Value * MM_PER_INCH
  else
    Result := Value;
  Result := RoundTo(Result, -6);          // (0.05 inch is 1.27 mm, not 1.2700000000000002)
end;

{ ===========================================================================
  UnitsSuffix  (function)
  Parameters:
    Units: Integer - UNITS_MM or UNITS_INCHES
  Returns:
    String - the abbreviation
  Notes:
    The abbreviation of the units: mm or in.
  =========================================================================== }
function UnitsSuffix(Units: Integer): String;
begin
  if Units = UNITS_INCHES then
    Result := 'in'
  else
    Result := 'mm';
end;

{ ===========================================================================
  LengthText  (function)
  Parameters:
    Mm: Double - number
    Units: Integer - whole number
  Returns:
    String
  Notes:
    Four significant figures are enough for a grid size; a point is always used for the
    decimals.
  =========================================================================== }
function LengthText(Mm: Double; Units: Integer): String;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := FloatToStrF(MmToUnits(Mm, Units), ffGeneral, 4, 0, FS) + ' ' + UnitsSuffix(Units);
end;

{ ===========================================================================
  PositionText  (function)
  Parameters:
    XMm: Double - x in millimetres
    YMm: Double - y in millimetres
    Units: Integer - the units to show it in
  Returns:
    String - the text
  Notes:
    A position for the status bar: "x, y" with the units after it, one decimal in millimetres
    and three in inches, always with a point.
  =========================================================================== }
function PositionText(XMm, YMm: Double; Units: Integer): String;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if Units = UNITS_INCHES then
    Result := Format('%9.3f,%9.3f ''''', [MmToUnits(XMm, Units), MmToUnits(YMm, Units)], FS)
  else
    Result := Format('%9.2f,%9.2f mm', [XMm, YMm], FS);
end;

{ ===========================================================================
  GridSizeText  (function)
  Parameters:
    GridUnits: Double - number
    Units: Integer - whole number
  Returns:
    String
  Notes:
    CDlgPositionBox::SetGridSize: tenths of a millimetre (a spacing of 2 mm is 20) or
    thousandths of an inch (78.74), with four figures as %.4g gives them.
  =========================================================================== }
function GridSizeText(GridUnits: Double; Units: Integer): String;
var
  FS: TFormatSettings;
  Scaled: Double;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  { (TinyCAD's accurate grid is ten times the spacing in design units) }
  if Units = UNITS_INCHES then
    Scaled := (1000.0 * GridUnits * 10.0) / (254.0 * 5.0)
  else
    Scaled := GridUnits * 10.0 / 5.0;
  Result := LowerCase(Format('%.4g', [Scaled], FS));
end;

{ ===========================================================================
  GridSizeUnitsText  (function)
  Parameters:
    Units: Integer - UNITS_MM or UNITS_INCHES
  Returns:
    String - the label
  Notes:
    The label that goes with the grid size on the position bar: .1mm (tenths of a millimetre) or
    .001" (thousandths of an inch).
  =========================================================================== }
function GridSizeUnitsText(Units: Integer): String;
begin
  if Units = UNITS_INCHES then
    Result := '.001"'
  else
    Result := '.1mm';
end;

{ ===========================================================================
  NextGridUnits  (function)
  Parameters:
    GridUnits: Double - number
  Returns:
    Double
  Notes:
    The normal grid is 10 design units (2 mm), the fine grid 5 (1 mm); from the fine grid the
    steps are a half, a quarter and a tenth of it, and the one after the tenth is the normal
    grid again. A spacing that is none of these (a custom grid) also goes to the normal grid.
  =========================================================================== }
function NextGridUnits(GridUnits: Double): Double;
const
  Normal = 10.0;
  Fine = 5.0;
  function Same(A, B: Double): Boolean;
  begin
    Result := Abs(A - B) < 1e-9;
  end;
begin
  if Same(GridUnits, Normal) then
    Result := Fine
  else if Same(GridUnits, Fine) then
    Result := Fine / 2.0
  else if Same(GridUnits, Fine / 2.0) then
    Result := Fine / 4.0
  else if Same(GridUnits, Fine / 4.0) then
    Result := Fine / 10.0
  else
    Result := Normal;
end;

{ ===========================================================================
  ParseNumber  (function)
  Parameters:
    const S: String - text
    out Value: Double - the value (out: set by the call)
  Returns:
    Boolean
  Notes:
    Spaces round it are ignored, and a comma is taken as a decimal point.
  =========================================================================== }
function ParseNumber(const S: String; out Value: Double): Boolean;
var
  FS: TFormatSettings;
  T: String;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  T := StringReplace(Trim(S), ',', '.', [rfReplaceAll]);
  Result := (T <> '') and TryStrToFloat(T, Value, FS);
end;

{ ===========================================================================
  NumberText  (function)
  Parameters:
    Value: Double - the number
  Returns:
    String - the text
  Notes:
    A number for an edit box: no digits that mean nothing (rounded to five decimals, seven
    figures) and no trailing zeros.
  =========================================================================== }
function NumberText(Value: Double): String;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := FloatToStrF(RoundTo(Value, -5), ffGeneral, 7, 0, FS);
end;

{ ===========================================================================
  OptionsError  (function)
  Parameters:
    const D: TOptionsData
  Returns:
    String
  Notes:
    The grid must have a size (and not an absurd one), the auto-snap range a distance, and the
    interval of the automatic save 1 to 60 minutes when it is on.
  =========================================================================== }
function OptionsError(const D: TOptionsData): String;
begin
  Result := '';
  if (D.GridMm <= 0) or (D.GridMm > GRID_MAX_MM) then
    Result := Format(rsTheGridSpacingMustBe, [GRID_MAX_MM])
  else if (D.Units < UNITS_MM) or (D.Units > UNITS_INCHES) then
    Result := rsTheUnitsMustBeMillimetres
  else if (D.AutoSnapRange < 1) or (D.AutoSnapRange > SNAP_RANGE_MAX) then
    Result := Format(rsTheAutoSnapRangeMust, [SNAP_RANGE_MAX])
  else if (D.AutoSaveMinutes < 0) or (D.AutoSaveMinutes > AUTOSAVE_MAX_MINUTES) then
    Result := Format(rsTheTimeBetweenAutomaticSaves2, [AUTOSAVE_MAX_MINUTES])
  else if (D.SheetCols < 1) or (D.SheetCols > 26) then
    Result := rsTheNumberOfColumnsMust
  else if (D.SheetRows < 1) or (D.SheetRows > 26) then
    Result := rsTheLastRowMustBe
  else if (D.SheetMarginMm < 0) or (D.SheetMarginMm > SHEET_MARGIN_MAX_MM) then
    Result := Format(rsTheMarginOfANew, [SHEET_MARGIN_MAX_MM])
  else if Trim(D.SymbolFontName) = '' then
    Result := rsTheSymbolFontNeedsA
  else if (D.SymbolFontPoints < SYMBOL_FONT_MIN_POINTS) or (D.SymbolFontPoints > SYMBOL_FONT_MAX_POINTS) then
    Result := Format(rsTheSymbolFontSizeMust, [SYMBOL_FONT_MIN_POINTS, SYMBOL_FONT_MAX_POINTS]);
end;

{ ===========================================================================
  OptionsFromSettings  (function)
  Parameters:  none
  Returns:
    TOptionsData - the values
  Notes:
    The program's settings (what a new design starts with) as the values of the Options dialog.
  =========================================================================== }
function OptionsFromSettings: TOptionsData;
begin
  with ProgramSettings do
  begin
    Result.ShowGrid := ShowGrid;
    Result.SnapGrid := SnapGrid;
    Result.GridMm := GridMm;
    Result.Units := Units;
    Result.AutoDrag := AutoDrag;
    Result.AutoSnap := AutoSnap;
    Result.AutoJunction := AutoJunction;
    Result.AutoSnapRange := AutoSnapRange;
    Result.AutoSaveMinutes := AutoSaveMinutes;
    Result.ReopenDesigns := ReopenDesigns;
    Result.SymbolFontName := SymbolFontName;
    Result.SymbolFontPoints := SymbolFontPoints;
    Result.SymbolFontBold := SymbolFontBold;
    Result.SymbolFontItalic := SymbolFontItalic;
    Result.SheetBorder := NewSheetBorder;
    Result.SheetRulers := NewSheetRulers;
    Result.SheetCols := NewSheetCols;
    Result.SheetRows := NewSheetRows;
    Result.SheetMarginMm := NewSheetMarginMm;
    Result.RulerUnits := RulerUnits;
  end;
end;

{ ===========================================================================
  OptionsToSettings  (procedure)
  Parameters:
    const D: TOptionsData - the values
  Notes:
    Puts the values of the Options dialog into the program's settings, which are what is kept
    for next time.
  =========================================================================== }
procedure OptionsToSettings(const D: TOptionsData);
begin
  with ProgramSettings do
  begin
    ShowGrid := D.ShowGrid;
    SnapGrid := D.SnapGrid;
    GridMm := D.GridMm;
    Units := D.Units;
    AutoDrag := D.AutoDrag;
    AutoSnap := D.AutoSnap;
    AutoJunction := D.AutoJunction;
    AutoSnapRange := D.AutoSnapRange;
    AutoSaveMinutes := D.AutoSaveMinutes;
    ReopenDesigns := D.ReopenDesigns;
    SymbolFontName := D.SymbolFontName;
    SymbolFontPoints := D.SymbolFontPoints;
    SymbolFontBold := D.SymbolFontBold;
    SymbolFontItalic := D.SymbolFontItalic;
    NewSheetBorder := D.SheetBorder;
    NewSheetRulers := D.SheetRulers;
    NewSheetCols := D.SheetCols;
    NewSheetRows := D.SheetRows;
    NewSheetMarginMm := D.SheetMarginMm;
    RulerUnits := D.RulerUnits;
  end;
end;

end.
