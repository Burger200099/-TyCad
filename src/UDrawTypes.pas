// SPDX-License-Identifier: LGPL-2.1-or-later
{ Constants and small types from DrawingObject.h, color.h, Symbol.h, ArcPoint.h and UserColor.h.
  Original: Copyright 1994-2019 Matt Pyne, LGPL 2.1+. This port keeps that licence.

  Enumerations that are written into design files are kept as plain Integers in the
  model (not Pascal enums) so that unknown values from newer files survive a load/save
  round trip unchanged; the constants below give them names. }
unit UDrawTypes;

{$mode objfpc}{$H+}

interface

type
  { ObjType from DrawingObject.h. Values must not change: some appear in old binary files. }
  TObjType = (
    xEndFile = 0, xNoDraw = 1, xAnnotation = 2, xDesignInformation = 3, xIndexInformation = 4,
    xSymbol = 5, xError = 6, xFont = 7, xSymbolEx = 8, xLayerOld = 9, xLineStyle = 10,
    xFillStyle = 11, xLayer = 12, xLayerTable = 13, xSymbolEx2 = 14,
    xBusName = 15, xNoConnect = 16, xJunction = 17, xLabel = 18, xWire = 19, xBus = 20,
    xMethod = 21, xPower = 22, xPin = 23, xBusSlash = 24, xLabelEx = 25, xMethodEx = 26,
    xMethodEx2 = 27, xPinEx = 28, xOrigin = 29,
    xLine = 32, xDash = 33, xText = 34, xCircle = 35, xSquare = 36, xArc = 37, xLineEx = 38,
    xTextEx = 39, xCircleEx = 40, xSquareEx = 41, xArcEx = 42,
    xLineEx2 = 43, xCircleEx2 = 44, xSquareEx2 = 45, xArcEx2 = 46, xMetaFile = 47,
    xTag = 48, xRuler = 49, xMethodEx3 = 50, xPolygon = 51,
    xNoteText = 64,
    xEditItem = 128, xDesignInformation2 = 129, xMetaFiles = 130, xOptions = 131,
    xSymbols = 132, xSymbolMethod = 133, xSymbolDelete = 134, xCircleEx3 = 135,
    xSquareEx3 = 136, xTextEx2 = 137, xLabelEx2 = 138, xBusNameEx = 139, xImage = 140,
    xHierarchicalSymbol = 141, xRefPoint = 142,
    xSymbolText = 143, // not in TinyCAD: text with symbol fields (reference, name, other ...) that draws no symbol, for reports (tag SYMTEXT)
    xLadder = 150,   // not in TinyCAD: the schematic version's ladder rails (tag LADDER)
    xMeasure = 151,  // A-to-B ruler (tag MEASURE)
    xCloud = 152,    // revision-cloud rectangle (tag CLOUD)
    xRungGrid = 154, // the sheet's rung number grid: the hidden spreadsheet whose first column holds the rung numbers (tag RUNGS)
    xRefText = 153,  // text linked to another object, e.g. its ladder line number (tag XREF)
    xNULL = 255
  );

const
  { color.h resource handles for the built-in tables }
  fTEXT = 0;   // font numbers
  fPIN = 1;
  fRULE = 2;
  fLINE = 0;   // line style numbers
  fDASH = 1;
  fsNONE = 0;  // fill style number

  PS_SOLID = 0;  // Windows pen styles used in the style table
  PS_DASH = 1;

  { SymbolFieldType (Symbol.h). Written to files; values must not change. }
  default_show = 0;
  default_hidden = 1;
  always_hidden = 2;
  extra_parameter = 3;
  default_show_name_and_value_only_if_value_not_empty = 4;
  default_show_name_and_value = 5;
  default_show_value_only_if_value_not_empty = 6;

  { CArcPoint::arc_type }
  Arc_none = 0;
  Arc_in = 1;
  Arc_out = 2;
  Arc_control = 3;

  { CDrawLabel::label_style, CDrawNoteText::BorderStyle }
  label_normal = 0;
  label_in = 1;
  label_out = 2;
  label_io = 3;
  BS_Rectangle = 0;
  BS_RoundedRectangle = 1;
  BS_NoBorder = 2;

  { CUserColor ids (UserColor.cpp) }
  UC_WIRE = 1;
  UC_BUS = 2;
  UC_JUNCTION = 3;
  UC_NOCONNECT = 4;
  UC_LABEL = 5;
  UC_POWER = 6;
  UC_PIN = 7;
  UC_HIDDEN_PIN = 8;
  UC_BACKGROUND = 9;
  UC_NOTETEXT_FILL = 10;
  UC_NOTETEXT_LINE = 11;
  UC_NOTETEXT_TEXT = 12;

  { ListOfFonts constants }
  TEXT_HEIGHT = -13;
  PIN_HEIGHT = -10;
  RULE_HEIGHT = -10;
  DEFAULT_FONT = 'Arial';

  CONNECT_SIZE = 4;

{ Windows COLORREF: 0x00BBGGRR }
function RGB(R, G, B: Byte): Cardinal;

const
  cBLACK = 0;
  cRED = $0000FF;   // RGB(255,0,0)
  cBLUE = $FF0000;  // RGB(0,0,255)

implementation

{ ===========================================================================
  RGB  (function)
  Parameters:
    R: Byte - red 0-255
    G: Byte - green 0-255
    B: Byte - blue 0-255
  Returns:
    Cardinal - the color
  Notes:
    Builds a Windows color value (0x00BBGGRR) from red, green and blue.
  =========================================================================== }
function RGB(R, G, B: Byte): Cardinal;
begin
  Result := Cardinal(R) or (Cardinal(G) shl 8) or (Cardinal(B) shl 16);
end;

end.
