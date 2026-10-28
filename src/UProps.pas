{ Object properties for the ribbon: a uniform way to list, read and change what can be edited on an
  object, and to change one property on many objects at once (the multi-select mass change).

  Properties have the same name on every kind of object that has them (text, font.height, line.color,
  fill.type, ...), so a selection of mixed objects offers exactly the properties they all share and a
  change applies to all of them. Values travel as strings; colors are "RRGGBB".

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UProps;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, UDPoint, UDrawTypes, UResources, UDrawingObjects, UDesign, UPaper, USymbols, UPartData;

const
  { the choices of a line style property; any list showing them is drawn with pictures (ilListBoxImages) }
  DashChoices = 'Solid|Dash|Dot|Dash-dot|Dash-dot-dot';
  AngleChoices = 'Free|90 degrees|45 degrees';  // wire angle options
  PhaseChoices = '1 phase|3 phase';             // a bus of one wire or of three
  ArcChoices = 'in|out';                        // the two kinds of arc (Arc_in, Arc_out): the arc tool's and an arc's 'arc.type'
  FillChoices = 'None|Solid|Horizontal|Vertical|Backward diagonal|Forward diagonal|Cross|Diagonal cross';      // the fill styles (the Fill button and its menu use the positions)
const
  PagesChoices = '1 page|2 pages';         // pages of rungs on a sheet
  DirChoices = 'Up|Down|Left|Right';      // the directions of a text, label, power symbol, note or pin
  { Every property key ObjectProps can give (the names a property editor in a frame is recognised by: see QPropFrame) }
  PropKeys: array[0..56] of String = (
    'text', 'dir', 'label.style', 'power.type', 'font.face',
    'font.height', 'font.bold', 'font.italic', 'font.color', 'line.color',
    'line.width', 'line.style', 'fill.type', 'fill.color', 'poly.closed',
    'cloud.bump', 'measure.unit', 'measure.ticks', 'ruler.pos', 'xref.mode',
    'xref.target', 'xref.prefix', 'xref.suffix', 'ladder.left', 'ladder.right',
    'rungs.rows', 'rungs.start', 'rungs.margin', 'rungs.pages', 'rungs.continue',
    'rungs.showheight', 'rungs.aboveblock', 'sym.ref', 'sym.name', 'symtext.text', 'sym.canscale', 'sym.scalex',
    'sym.scaley', 'sym.dir', 'sym.mirror', 'sym.showref', 'sym.showpower', 'sym.mfr', 'sym.model', 'pin.name', 'pin.number', 'pin.length', 'pin.numpos',
    'pin.dir', 'pin.shape', 'pin.elec', 'pin.showname', 'pin.shownumber',
    'pin.centre', 'arc.type', 'bus.phases', 'bus.spacing');

type
  TPropKind = (pkText, pkMemo, pkInt, pkFloat, pkColor, pkChoice, pkBool);
  TPropDef = record
    Name: String;
    Caption: String;
    Kind: TPropKind;
    Choices: String;   // for pkChoice: the options separated by '|'
  end;
  TPropDefArray = array of TPropDef;

function ObjectProps(Obj: TDrawingObject): TPropDefArray;
{ The part data a placed symbol keeps (nil when it is not a placed generic part) }
function PartOf(M: TDrawMethod): TDesignFileSymbol;
{ The fit of a placed part's product to its part as words (FitSummaryText), '' when it is not a placed part }
function PartFitText(M: TDrawMethod): String;
{ The lines of the fit that are not met, for a hint (FitDetailText) }
function PartFitDetail(M: TDrawMethod): String;
{ The properties every object in the list has (same name and kind), in the first object's order }
function CommonProps(Objs: TList): TPropDefArray;
function GetProp(Obj: TDrawingObject; const Name: String; out Value: String): Boolean;
function SetProp(Obj: TDrawingObject; const Name, Value: String): Boolean;
{ The shared value of a property across a selection; Mixed is True when they differ }
function CommonValue(Objs: TList; const Name: String; out Mixed: Boolean): String;
{ Set a property on every object that has it; returns how many were changed }
function SetPropAll(Objs: TList; const Name, Value: String): Integer;
{ The description of the tool-only property 'wire.angle': the angle (free, 90, 45 degrees) a wire, bus or line is drawn at }
function WireAngleDef: TPropDef;
{ True for a polygon that is an arc: the old arc kind, or an open polygon whose segments are all arcs in or out (what the Arc tool makes) }
function IsArcPolygon(Obj: TDrawingObject): Boolean;
{ The description of the tool-only property 'arc.type' (an arc's own is the same): in or out }
function ArcTypeDef: TPropDef;
function ChoiceIndex(const Choices, Value: String): Integer;
function ChoiceCount(const Choices: String): Integer;
function ChoiceText(const Choices: String; Index: Integer): String;
{ A number as a property editor shows it (up to three decimals, a dot whatever the locale), and a typed one read back (a comma works too) }
function FloatText(V: Double): String;
function ParseFloat(const S: String; Default: Double): Double;

{ a font's height as TinyCAD keeps it (LOGFONT units: pixels of a 96 dpi screen, 21 for 16 pt) and as a person reads it (points) }
function FontPointsOf(AHeight: Integer): Integer;
function FontHeightOf(APoints: Integer): Integer;

implementation


uses UStrings;

const
  LabelChoices = 'Normal|Input|Output|Input/Output';
  PowerChoices = 'Bar|Circle|Wave|Arrow|Earth';

  UnitChoices = 'Millimetres|Inches';
  ModeChoices = 'Line number|Contact line numbers';
  PinShapeChoices = 'Normal|Dot|Clock|Dot Clock|Power|Hidden|Cross';                           // TinyCAD's pin types (CEditDlgPinEdit)
  PinElecChoices = 'Input|Output|Tristate|Open Collector|Passive|Input/Output|Not Connected';   // ... and electrical types

procedure SetProductText(M: TDrawMethod; IsMfr: Boolean; const Value: String); forward;
procedure SetSymbolDirection(M: TDrawMethod; NewRotate: Integer); forward;
procedure SetSymbolShowPower(M: TDrawMethod; Show: Boolean); forward;



{ ===========================================================================
  SetSymbolDirection  (procedure)
  Parameters:
    M: TDrawMethod - a placed symbol (or the one being placed)
    NewRotate: Integer - the direction (0 up, 1 down, 2 left, 3 right) plus 4 when mirrored
  Notes:
    CEditDlgMethodEdit::OnChangeRotation: the symbol's rotate byte is set and the places of its texts worked out again (NewRotation); the symbol itself is not moved.
  =========================================================================== }
procedure SetSymbolDirection(M: TDrawMethod; NewRotate: Integer);
begin
  M.Rotate := NewRotate and 7;
  M.NewRotation;
end;

{ ===========================================================================
  SetSymbolShowPower  (procedure)
  Parameters:
    M: TDrawMethod - a placed symbol (or the one being placed)
    Show: Boolean - show the power pins
  Notes:
    CEditDlgMethodEdit::OnBnClickedShowpower: the first visible pin that is not a power pin is remembered, the setting is applied and the texts placed again, and the symbol is
    shifted so that pin stays where it was (the symbol grows or shrinks by the power pins, which would otherwise move the whole symbol).
  =========================================================================== }
procedure SetSymbolShowPower(M: TDrawMethod; Show: Boolean);
var
  RefOld, RefNew: TDPoint;
begin
  RefOld := M.GetFirstStaticPoint;
  M.ShowPower := Ord(Show);
  M.NewRotation;
  RefNew := M.GetFirstStaticPoint;
  M.Shift(DPoint(RefOld.x - RefNew.x, RefOld.y - RefNew.y));
end;

{ ===========================================================================
  PartOf  (function)
  Parameters:
    M: TDrawMethod - a placed symbol
  Returns:
    TDesignFileSymbol - the symbol, when it came from a generic part (it holds a part copy), else nil
  =========================================================================== }
function PartOf(M: TDrawMethod): TDesignFileSymbol;
var
  Info: TSymbolInfo;
begin
  Result := nil;
  if M = nil then
    Exit;
  Info := M.GetSymbolData;
  if (Info is TDesignFileSymbol) and not TDesignFileSymbol(Info).PartInfo.IsEmpty then
    Result := TDesignFileSymbol(Info);
end;

{ ===========================================================================
  PartFitText  (function)
  Parameters:
    M: TDrawMethod - a placed symbol
  Returns:
    String - the verdict of its product against its part's requirements in words; '' for a symbol that is not a placed part
  Notes:
    A part with requirements and no product chosen reads 'Does not fit: n missing' (the product is not known yet).
  =========================================================================== }
function PartFitText(M: TDrawMethod): String;
var
  P: TDesignFileSymbol;
begin
  P := PartOf(M);
  if P = nil then
    Result := ''
  else
    Result := FitSummaryText(CheckFit(P.PartInfo.Needs, M.Product.Haves));
end;

{ ===========================================================================
  PartFitDetail  (function)
  Parameters:
    M: TDrawMethod - a placed symbol
  Returns:
    String - one line for each requirement not met exactly (FitDetailText); '' otherwise
  =========================================================================== }
function PartFitDetail(M: TDrawMethod): String;
var
  P: TDesignFileSymbol;
begin
  P := PartOf(M);
  if P = nil then
    Result := ''
  else
    Result := FitDetailText(CheckFit(P.PartInfo.Needs, M.Product.Haves));
end;

{ ===========================================================================
  SetProductText  (procedure)
  Parameters:
    M: TDrawMethod - a placed symbol
    IsMfr: Boolean - True for the manufacturer, False for the model number
    Value: String - the text typed
  Notes:
    Typing a manufacturer or model number by hand: when the text differs from the product chosen from the library, the product stops being that one (its GUID and ratings are
    dropped, only the typed text is kept), so a fit is never claimed for something that was not looked up.
  =========================================================================== }
procedure SetProductText(M: TDrawMethod; IsMfr: Boolean; const Value: String);
var
  P: TProductChoice;
begin
  P := M.Product;
  if IsMfr then
  begin
    if P.Manufacturer = Value then
      Exit;
    P.Manufacturer := Value;
  end
  else
  begin
    if P.MPN = Value then
      Exit;
    P.MPN := Value;
  end;
  P.UID := '';
  SetLength(P.Haves, 0);
  M.Product := P;
end;

{ ===========================================================================
  Def  (function)
  Parameters:
    const AName: String - the property's internal name, e.g. font.height
    const ACaption: String - the label shown on the ribbon
    AKind: TPropKind - the kind of editor to use
    const AChoices: String = '' - for a choice, the options separated by |
  Returns:
    TPropDef - the filled-in description
  Notes:
    Builds one property description (name, caption, kind and, for choices, the allowed values).
  =========================================================================== }
function Def(const AName, ACaption: String; AKind: TPropKind; const AChoices: String = ''): TPropDef;
begin
  Result.Name := AName;
  Result.Caption := ACaption;
  Result.Kind := AKind;
  Result.Choices := AChoices;
end;

{ ===========================================================================
  Add  (procedure)
  Parameters:
    var L: TPropDefArray - the list to extend
    const D: TPropDef - the description to add
  Notes:
    Appends a property description to a list.
  =========================================================================== }
procedure Add(var L: TPropDefArray; const D: TPropDef);
begin
  SetLength(L, Length(L) + 1);
  L[High(L)] := D;
end;

{ ===========================================================================
  WireAngleDef  (function)
  Parameters:  none
  Returns:
    TPropDef
  Notes:
    Not a property of any object: the Wire, Bus and Line tools offer it in their panels
    (TSchematicView.ToolPropDefs).
  =========================================================================== }
function WireAngleDef: TPropDef;
begin
  Result := Def('wire.angle', rsAngle, pkChoice, AngleChoices);
end;

{ ===========================================================================
  IsArcPolygon  (function)
  Parameters:
    Obj: TDrawingObject - the drawing object
  Returns:
    Boolean
  Notes:
    An arc is what the Arc tool draws (an open polygon whose segments are all arcs in or out) or
    a polygon of the old arc kind (xArcEx2). The Properties ribbon gives it the arc frame (the
    kind of arc, the line, the fill) in place of the polygon's.
  =========================================================================== }
function IsArcPolygon(Obj: TDrawingObject): Boolean;
var
  Pg: TDrawPolygon;
  i: Integer;
begin
  Result := False;
  if not (Obj is TDrawPolygon) then
    Exit;
  Pg := TDrawPolygon(Obj);
  if Pg.Kind = xArcEx2 then
    Exit(True);
  Result := (Pg.Close = 0) and (Length(Pg.Handles) >= 2);
  for i := 1 to High(Pg.Handles) do
    if not (Pg.Handles[i].Arc in [Arc_in, Arc_out]) then
      Result := False;
end;

{ ===========================================================================
  ArcTypeDef  (function)
  Parameters:  none
  Returns:
    TPropDef
  Notes:
    The Arc tool offers it in its panel (TSchematicView.ToolPropDefs) and an arc has it as a
    property of its own.
  =========================================================================== }
function ArcTypeDef: TPropDef;
begin
  Result := Def('arc.type', rsArc, pkChoice, ArcChoices);
end;

{ ===========================================================================
  ArcTypeText  (function)
  Parameters:
    Pg: TDrawPolygon
  Returns:
    String
  Notes:
    The kind its segments share; empty when they differ (the arcs of a wave alternate), which
    the editors show as mixed.
  =========================================================================== }
function ArcTypeText(Pg: TDrawPolygon): String;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to High(Pg.Handles) do
    if Pg.Handles[i].Arc in [Arc_in, Arc_out] then
    begin
      if Result = '' then
        Result := ChoiceText(ArcChoices, Ord(Pg.Handles[i].Arc = Arc_out))
      else if Result <> ChoiceText(ArcChoices, Ord(Pg.Handles[i].Arc = Arc_out)) then
        Exit('');
    end;
end;

{ ===========================================================================
  SetArcType  (procedure)
  Parameters:
    Pg: TDrawPolygon
    const Value: String - the value
  Notes:
    Every segment of the arc that is an arc in or out becomes that kind; the outline is worked
    out again.
  =========================================================================== }
procedure SetArcType(Pg: TDrawPolygon; const Value: String);
var
  i, T: Integer;
begin
  if ChoiceIndex(ArcChoices, Value) = 1 then
    T := Arc_out
  else
    T := Arc_in;
  for i := 1 to High(Pg.Handles) do
    if Pg.Handles[i].Arc in [Arc_in, Arc_out] then
      Pg.Handles[i].Arc := T;
  Pg.CalcBoundingRect;
end;

{ ===========================================================================
  ChoiceIndex  (function)
  Parameters:
    const Choices: String - the options separated by |
    const Value: String - the option to find
  Returns:
    Integer - the 0-based index, or -1 if it is not there
  Notes:
    Position of a value in a |-separated list of choices (case-sensitive).
  =========================================================================== }
function ChoiceIndex(const Choices, Value: String): Integer;
var
  Sl: TStringList;
begin
  Sl := TStringList.Create;
  try
    Sl.Delimiter := '|';
    Sl.StrictDelimiter := True;
    Sl.DelimitedText := Choices;
    Result := Sl.IndexOf(Value);
  finally
    Sl.Free;
  end;
end;

{ ===========================================================================
  ChoiceCount  (function)
  Parameters:
    const Choices: String - text
  Returns:
    Integer
  Notes:
    An empty list has none.
  =========================================================================== }
function ChoiceCount(const Choices: String): Integer;
var
  i: Integer;
begin
  Result := 0;
  if Choices = '' then
    Exit;
  Result := 1;
  for i := 1 to Length(Choices) do
    if Choices[i] = '|' then
      Inc(Result);
end;

{ ===========================================================================
  ChoiceText  (function)
  Parameters:
    const Choices: String - the options separated by |
    Index: Integer - 0-based position
  Returns:
    String - the option text
  Notes:
    The option at a position in a |-separated list; position 0 is used when the index is out of
    range.
  =========================================================================== }
function ChoiceText(const Choices: String; Index: Integer): String;
var
  Sl: TStringList;
begin
  Sl := TStringList.Create;
  try
    Sl.Delimiter := '|';
    Sl.StrictDelimiter := True;
    Sl.DelimitedText := Choices;
    if (Index >= 0) and (Index < Sl.Count) then
      Result := Sl[Index]
    else
      Result := Sl[0];
  finally
    Sl.Free;
  end;
end;

{ ===========================================================================
  ColorToHex  (function)
  Parameters:
    C: Cardinal - the color
  Returns:
    String - six hex digits, e.g. FF0000 for red
  Notes:
    Converts a Windows color (0x00BBGGRR) to the RRGGBB text used for properties.
  =========================================================================== }
function ColorToHex(C: Cardinal): String;
begin
  { COLORREF is 0x00BBGGRR; the property text is RRGGBB }
  Result := IntToHex(C and $FF, 2) + IntToHex((C shr 8) and $FF, 2) + IntToHex((C shr 16) and $FF, 2);
end;

{ ===========================================================================
  HexToColor  (function)
  Parameters:
    const S: String - the text
    Default: Cardinal - color to return when the text is not valid
  Returns:
    Cardinal - the color
  Notes:
    Converts RRGGBB text (with or without a leading #) to a Windows color; bad text gives the
    default.
  =========================================================================== }
function HexToColor(const S: String; Default: Cardinal): Cardinal;
var
  T: String;
  V: Cardinal;
begin
  T := Trim(S);
  if (Length(T) > 0) and (T[1] = '#') then
    Delete(T, 1, 1);
  if Length(T) <> 6 then begin
    Result := Default;
    Exit;
  end;
  V := StrToIntDef('$' + T, -1);
  if (V = Cardinal(-1)) then begin
    Result := Default;
    Exit;
  end;
  Result := RGB((V shr 16) and $FF, (V shr 8) and $FF, V and $FF);
end;

{ ===========================================================================
  FloatText  (function)
  Parameters:
    V: Double - the number
  Returns:
    String - the text
  Notes:
    Formats a number for a property editor: up to three decimals, a dot as the decimal separator
    whatever the locale.
  =========================================================================== }
function FloatText(V: Double): String;
var
  Fs: TFormatSettings;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  Result := FormatFloat('0.###', V, Fs);
end;

{ ===========================================================================
  ParseFloat  (function)
  Parameters:
    const S: String - the text
    Default: Double - value to return on failure
  Returns:
    Double - the value, or Default when the text is not a number
  Notes:
    Reads a number typed by the user (a comma is accepted as the decimal separator).
  =========================================================================== }
function ParseFloat(const S: String; Default: Double): Double;
var
  Fs: TFormatSettings;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  if not TryStrToFloat(StringReplace(Trim(S), ',', '.', []), Result, Fs) then
    Result := Default;
end;

{ ---------------------------------------------------------------- fonts }

{ ===========================================================================
  FontNumberOf  (function)
  Parameters:
    Obj: TDrawingObject - the object
  Returns:
    Integer - the font number, or -1 for objects without a font
  Notes:
    The font resource number of an object that has a font (text, label, note, ladder, linked
    text, measure).
  =========================================================================== }
function FontNumberOf(Obj: TDrawingObject): Integer;
begin
  Result := -1;
  if Obj is TDrawText then
    Result := (Obj as TDrawText).FontStyle
  else if Obj is TDrawLabel then
    Result := (Obj as TDrawLabel).FontStyle
  else if Obj is TDrawNoteText then
    Result := (Obj as TDrawNoteText).FontStyle
  else if Obj is TDrawLadder then
    Result := (Obj as TDrawLadder).FontStyle
  else if Obj is TDrawRungGrid then
    Result := (Obj as TDrawRungGrid).FontStyle
  else if Obj is TDrawRefText then
    Result := (Obj as TDrawRefText).FontStyle
  else if Obj is TDrawMeasure then
    Result := (Obj as TDrawMeasure).FontStyle;
end;

{ ===========================================================================
  SetFontNumber  (procedure)
  Parameters:
    Obj: TDrawingObject - the object
    N: Integer - the font resource number
  Notes:
    Stores a font resource number in an object that has a font; other objects are ignored.
  =========================================================================== }
procedure SetFontNumber(Obj: TDrawingObject; N: Integer);
begin
  if Obj is TDrawText then
    (Obj as TDrawText).FontStyle := N
  else if Obj is TDrawLabel then
    (Obj as TDrawLabel).FontStyle := N
  else if Obj is TDrawNoteText then
    (Obj as TDrawNoteText).FontStyle := N
  else if Obj is TDrawLadder then
    (Obj as TDrawLadder).FontStyle := N
  else if Obj is TDrawRungGrid then
    (Obj as TDrawRungGrid).FontStyle := N
  else if Obj is TDrawRefText then
    (Obj as TDrawRefText).FontStyle := N
  else if Obj is TDrawMeasure then
    (Obj as TDrawMeasure).FontStyle := N;
end;

{ ===========================================================================
  FontColorOf  (function)
  Parameters:
    Obj: TDrawingObject - the object
    out C: Cardinal - set to the color
  Returns:
    Boolean - False when the object has no text color
  Notes:
    Reads the text color of an object that has one.
  =========================================================================== }
function FontColorOf(Obj: TDrawingObject; out C: Cardinal): Boolean;
begin
  Result := True;
  if Obj is TDrawText then
    C := (Obj as TDrawText).FontColor
  else if Obj is TDrawLabel then
    C := (Obj as TDrawLabel).FontColor
  else if Obj is TDrawNoteText then
    C := (Obj as TDrawNoteText).FontColor
  else if Obj is TDrawLadder then
    C := (Obj as TDrawLadder).FontColor
  else if Obj is TDrawRungGrid then
    C := (Obj as TDrawRungGrid).FontColor
  else if Obj is TDrawRefText then
    C := (Obj as TDrawRefText).FontColor
  else if Obj is TDrawMeasure then
    C := (Obj as TDrawMeasure).FontColor
  else
    Result := False;
end;

{ ===========================================================================
  SetFontColor  (procedure)
  Parameters:
    Obj: TDrawingObject - the object
    C: Cardinal - the new color
  Notes:
    Sets the text color of an object that has one; other objects are ignored.
  =========================================================================== }
procedure SetFontColor(Obj: TDrawingObject; C: Cardinal);
begin
  if Obj is TDrawText then
    (Obj as TDrawText).FontColor := C
  else if Obj is TDrawLabel then
    (Obj as TDrawLabel).FontColor := C
  else if Obj is TDrawNoteText then
    (Obj as TDrawNoteText).FontColor := C
  else if Obj is TDrawLadder then
    (Obj as TDrawLadder).FontColor := C
  else if Obj is TDrawRungGrid then
    (Obj as TDrawRungGrid).FontColor := C
  else if Obj is TDrawRefText then
    (Obj as TDrawRefText).FontColor := C
  else if Obj is TDrawMeasure then
    (Obj as TDrawMeasure).FontColor := C;
end;

{ ===========================================================================
  FontPointsOf  (function)
  Parameters:
    AHeight: Integer - whole number
  Returns:
    Integer
  Notes:
    TinyCAD's font dialog shows points and keeps LOGFONT units (MulDiv(points, 96, 72)); the
    Size box shows points as TinyCAD does.
  =========================================================================== }
function FontPointsOf(AHeight: Integer): Integer;
begin
  Result := Round(Abs(AHeight) * 72 / 96);
end;

{ ===========================================================================
  FontHeightOf  (function)
  Parameters:
    APoints: Integer - whole number
  Returns:
    Integer
  Notes:
    The other way of FontPointsOf, rounded as TinyCAD's MulDiv.
  =========================================================================== }
function FontHeightOf(APoints: Integer): Integer;
begin
  Result := Round(APoints * 96 / 72);
end;

{ ===========================================================================
  ChangeFont  (procedure)
  Parameters:
    Obj: TDrawingObject - the drawing object
    const What: String - text
    const Value: String - the value
  Notes:
    Change one aspect of an object's font by finding or adding a font resource
  =========================================================================== }
procedure ChangeFont(Obj: TDrawingObject; const What, Value: String);
var
  Cur, New: TFontResource;
  N, H: Integer;
begin
  N := FontNumberOf(Obj);
  if N < 0 then
    Exit;
  Cur := Obj.Options.Fonts.Get(N) as TFontResource;
  New := TFontResource.Create;
  New.Height := Cur.Height; New.Width := Cur.Width; New.Weight := Cur.Weight;
  New.Italic := Cur.Italic; New.Underline := Cur.Underline; New.StrikeOut := Cur.StrikeOut;
  New.CharSet := Cur.CharSet; New.FaceName := Cur.FaceName;
  if What = 'height' then
  begin
    H := StrToIntDef(Trim(Value), FontPointsOf(Cur.Height));
    if H < 1 then
      H := 1;
    if H > 150 then
      H := 150;
    if H = FontPointsOf(Cur.Height) then
    begin
      New.Free;           // the size shown is the size it has: nothing to change (the height in pixels is not rounded through points)
      Exit;
    end;
    New.Height := -FontHeightOf(H);
    New.Width := 0; // a requested width no longer fits the new height
  end
  else if What = 'face' then
    New.FaceName := Value
  else if What = 'bold' then begin if Value = '1' then
    New.Weight := 700
  else
    New.Weight := 400; end
  else if What = 'italic' then
    New.Italic := Ord(Value = '1');
  SetFontNumber(Obj, Obj.Options.Fonts.Add(New, -1));
end;

{ ---------------------------------------------------------------- line and fill styles }

{ ===========================================================================
  LineStyleNumber  (function)
  Parameters:
    Obj: TDrawingObject - the object
    out N: Integer - set to the style number
  Returns:
    Boolean - False for objects without a line style
  Notes:
    The line-style resource number of a wire, line, polygon, rectangle/circle, cloud or note.
  =========================================================================== }
function LineStyleNumber(Obj: TDrawingObject; out N: Integer): Boolean;
begin
  Result := True;
  if Obj is TDrawLine then
    N := (Obj as TDrawLine).Style
  else if Obj is TDrawPolygon then
    N := (Obj as TDrawPolygon).Style
  else if Obj is TDrawSquare then
    N := (Obj as TDrawSquare).Style
  else if Obj is TDrawCloud then
    N := (Obj as TDrawCloud).Style
  else if Obj is TDrawNoteText then
    N := (Obj as TDrawNoteText).Style
  else
    Result := False;
end;

{ ===========================================================================
  SetLineStyleNumber  (procedure)
  Parameters:
    Obj: TDrawingObject - the object
    N: Integer - the line style number
  Notes:
    Stores a line-style number in an object (a wire or line stops using the default style).
  =========================================================================== }
procedure SetLineStyleNumber(Obj: TDrawingObject; N: Integer);
begin
  if Obj is TDrawLine then begin
    (Obj as TDrawLine).Style := N;
    (Obj as TDrawLine).UseDefaultStyle := False;
  end
  else if Obj is TDrawPolygon then
    (Obj as TDrawPolygon).Style := N
  else if Obj is TDrawSquare then
    (Obj as TDrawSquare).Style := N
  else if Obj is TDrawCloud then
    (Obj as TDrawCloud).Style := N
  else if Obj is TDrawNoteText then
    (Obj as TDrawNoteText).Style := N;
end;

{ ===========================================================================
  EffectiveLine  (procedure)
  Parameters:
    Obj: TDrawingObject - the drawing object
    out Col: Cardinal - out: set by the call
    out Width: Integer - whole number (out: set by the call)
    out Dash: Integer - whole number (out: set by the call)
  Notes:
    The line's effective color, width and dash (a default-style wire takes the sheet's wire
    color)
  =========================================================================== }
procedure EffectiveLine(Obj: TDrawingObject; out Col: Cardinal; out Width, Dash: Integer);
var
  N: Integer;
  St: TLineStyleResource;
begin
  Col := cBLACK; Width := 1; Dash := 0;
  if Obj is TDrawMeasure then
  begin
    Col := (Obj as TDrawMeasure).LineColor;
    Width := Max(1, Round((Obj as TDrawMeasure).LineWidth));
    Exit;
  end;
  if Obj is TDrawLadder then
  begin
    Col := (Obj as TDrawLadder).LineColor;
    Width := Max(1, (Obj as TDrawLadder).LineWidth);
    Exit;
  end;
  if not LineStyleNumber(Obj, N) then
    Exit;
  if (Obj is TDrawLine) and (Obj as TDrawLine).UseDefaultStyle then
  begin
    if Obj.GetType = xBus then begin
      Col := Obj.Options.Colors.Get(UC_BUS);
      Width := 3;
    end
    else begin
      Col := Obj.Options.Colors.Get(UC_WIRE);
      Width := 1;
    end;
    Exit;
  end;
  St := Obj.Options.Styles.Get(N) as TLineStyleResource;
  Col := St.Color; Width := St.Thickness; Dash := St.Style;
end;

{ ===========================================================================
  HasLine  (function)
  Parameters:
    Obj: TDrawingObject - the object
  Returns:
    Boolean - True for lines, wires, shapes, clouds, notes and measures
  Notes:
    Whether the object has a line whose color, width or style can be edited.
  =========================================================================== }
function HasLine(Obj: TDrawingObject): Boolean;
var
  N: Integer;
begin
  Result := (Obj is TDrawMeasure) or (Obj is TDrawLadder) or LineStyleNumber(Obj, N);
end;

{ ===========================================================================
  ChangeLine  (procedure)
  Parameters:
    Obj: TDrawingObject - the object
    const What: String - color, width or style
    const Value: String - the new value as text
  Notes:
    Changes one aspect of an object's line (color, width or dash style) by finding or adding a
    matching line-style resource, keeping the other two aspects.
  =========================================================================== }
procedure ChangeLine(Obj: TDrawingObject; const What, Value: String);
var
  Col: Cardinal;
  Width, Dash: Integer;
begin
  EffectiveLine(Obj, Col, Width, Dash);
  if What = 'color' then
    Col := HexToColor(Value, Col)
  else if What = 'width' then
    Width := Max(1, Min(50, StrToIntDef(Trim(Value), Width)))
  else if What = 'style' then
    Dash := Max(0, ChoiceIndex(DashChoices, Value));
  if Obj is TDrawMeasure then
  begin
    (Obj as TDrawMeasure).LineColor := Col;
    (Obj as TDrawMeasure).LineWidth := Width;
    Exit;
  end;
  if Obj is TDrawLadder then
  begin
    (Obj as TDrawLadder).LineColor := Col;
    (Obj as TDrawLadder).LineWidth := Width;
    Exit;
  end;
  SetLineStyleNumber(Obj, Obj.Options.AddStyle(Dash, Width, Col));
end;

{ ===========================================================================
  FillNumber  (function)
  Parameters:
    Obj: TDrawingObject - the object
    out N: Integer - set to the fill number
  Returns:
    Boolean - False for objects without a fill
  Notes:
    The fill-style resource number of a polygon, rectangle/circle or note.
  =========================================================================== }
function FillNumber(Obj: TDrawingObject; out N: Integer): Boolean;
begin
  Result := True;
  if Obj is TDrawPolygon then
    N := (Obj as TDrawPolygon).Fill
  else if Obj is TDrawSquare then
    N := (Obj as TDrawSquare).Fill
  else if Obj is TDrawNoteText then
    N := (Obj as TDrawNoteText).Fill
  else
    Result := False;
end;

{ ===========================================================================
  SetFillNumber  (procedure)
  Parameters:
    Obj: TDrawingObject - the object
    N: Integer - the fill style number
  Notes:
    Stores a fill-style number in an object that can be filled.
  =========================================================================== }
procedure SetFillNumber(Obj: TDrawingObject; N: Integer);
begin
  if Obj is TDrawPolygon then
    (Obj as TDrawPolygon).Fill := N
  else if Obj is TDrawSquare then
    (Obj as TDrawSquare).Fill := N
  else if Obj is TDrawNoteText then
    (Obj as TDrawNoteText).Fill := N;
end;

{ ===========================================================================
  ChangeFill  (procedure)
  Parameters:
    Obj: TDrawingObject - the object
    const What: String - type or color
    const Value: String - the new value as text
  Notes:
    Changes the fill type (none, solid or a hatch) or the fill color of an object by finding or
    adding a matching fill-style resource.
  =========================================================================== }
procedure ChangeFill(Obj: TDrawingObject; const What, Value: String);
var
  N, Idx: Integer;
  F: TFillStyleResource;
  Col: Cardinal;
begin
  if not FillNumber(Obj, N) then
    Exit;
  F := Obj.Options.Fills.Get(N) as TFillStyleResource;
  Idx := F.Index; Col := F.Color;
  if What = 'type' then
  begin
    Idx := ChoiceIndex(FillChoices, Value);
    if Idx <= 0 then
      Idx := -1
    else
      Dec(Idx); // None = -1, Solid = 0, then the hatches
  end
  else if What = 'color' then
    Col := HexToColor(Value, Col);
  SetFillNumber(Obj, Obj.Options.AddFillStyle(Idx, Col));
end;

{ ---------------------------------------------------------------- the catalogue }

{ ===========================================================================
  ObjectProps  (function)
  Parameters:
    Obj: TDrawingObject - the object
  Returns:
    TPropDefArray - the list of property descriptions
  Notes:
    Lists the properties that can be edited on one object, in ribbon order. Names are shared
    between kinds (text, font.height, line.color ...) so selections of mixed objects can be
    edited together.
  =========================================================================== }
function ObjectProps(Obj: TDrawingObject): TPropDefArray;
var
  N: Integer;
  C: Cardinal;
begin
  SetLength(Result, 0);
  if (Obj is TDrawText) or (Obj is TDrawLabel) or (Obj is TDrawPower) then
    Add(Result, Def('text', rsText, pkText));
  if Obj is TDrawNoteText then
    Add(Result, Def('text', rsText, pkMemo));
  if (Obj is TDrawText) or (Obj is TDrawLabel) or (Obj is TDrawPower) or (Obj is TDrawNoteText) then
    Add(Result, Def('dir', rsDirection, pkChoice, DirChoices));
  if Obj is TDrawLabel then
    Add(Result, Def('label.style', rsLabelType, pkChoice, LabelChoices));
  if Obj is TDrawPower then
    Add(Result, Def('power.type', rsSymbol, pkChoice, PowerChoices));
  if FontNumberOf(Obj) >= 0 then
  begin
    Add(Result, Def('font.face', rsFont, pkText));
    Add(Result, Def('font.height', rsSizePt, pkInt));
    Add(Result, Def('font.bold', rsBold, pkBool));
    Add(Result, Def('font.italic', rsItalic, pkBool));
  end;
  if FontColorOf(Obj, C) then
    Add(Result, Def('font.color', rsTextColor, pkColor));
  if HasLine(Obj) then
  begin
    Add(Result, Def('line.color', rsColor, pkColor));
    Add(Result, Def('line.width', rsWidth, pkInt));
    if not ((Obj is TDrawMeasure) or (Obj is TDrawLadder)) then
      Add(Result, Def('line.style', rsStyle, pkChoice, DashChoices));
  end;
  if FillNumber(Obj, N) then
  begin
    Add(Result, Def('fill.type', rsFill, pkChoice, FillChoices));
    Add(Result, Def('fill.color', rsFillColor, pkColor));
  end;
  if (Obj is TDrawLine) and ((Obj as TDrawLine).Kind = xBus) then
  begin
    Add(Result, Def('bus.phases', rsPhases, pkChoice, PhaseChoices));
    Add(Result, Def('bus.spacing', rsSpacingMm, pkFloat));
  end;
  if IsArcPolygon(Obj) then
    Add(Result, Def('arc.type', rsArc, pkChoice, ArcChoices))
  else if Obj is TDrawPolygon then
    Add(Result, Def('poly.closed', rsClosed, pkBool));
  if Obj is TDrawCloud then
    Add(Result, Def('cloud.bump', rsScallopMm, pkFloat));
  if Obj is TDrawMeasure then
  begin
    Add(Result, Def('measure.unit', rsUnits, pkChoice, UnitChoices));
    Add(Result, Def('measure.ticks', rsGraduations, pkBool));
  end;
  if Obj is TDrawRuler then
    Add(Result, Def('ruler.pos', rsPositionMm, pkFloat));
  if Obj is TDrawRefText then
  begin
    Add(Result, Def('xref.mode', rsShows, pkChoice, ModeChoices));
    Add(Result, Def('xref.target', rsTargetObjectId, pkInt));
    Add(Result, Def('xref.prefix', rsPrefix, pkText));
    Add(Result, Def('xref.suffix', rsSuffix, pkText));
  end;
  if Obj is TDrawLadder then
  begin
    Add(Result, Def('ladder.left', rsLeftBusWireNo, pkText));
    Add(Result, Def('ladder.right', rsRightBusWireNo, pkText));
  end;
  if Obj is TDrawRungGrid then
  begin
    Add(Result, Def('rungs.rows', rsRows, pkInt));
    Add(Result, Def('rungs.start', rsFirstNumber, pkInt));
    Add(Result, Def('rungs.margin', rsIndentMm, pkFloat));
    Add(Result, Def('rungs.pages', rsPagesPerSheet, pkChoice, PagesChoices));
    Add(Result, Def('rungs.continue', rsContinueNumbering, pkBool));
    Add(Result, Def('rungs.showheight', rsShowRowHeight, pkBool));
    Add(Result, Def('rungs.aboveblock', rsAboveTheTitleBlock, pkBool));
  end;
  if Obj is TDrawMethod then
  begin
    Add(Result, Def('sym.ref', rsReference, pkText));
    Add(Result, Def('sym.name', rsName, pkText));
    { a symbol text has no drawing: nothing to scale, turn or mirror, and no power pins; the text it shows is its Name field }
    if Obj is TDrawSymbolText then
      Add(Result, Def('symtext.text', rsText, pkText));
    if not (Obj is TDrawSymbolText) then
    begin
      Add(Result, Def('sym.canscale', rsResizable, pkBool));
      Add(Result, Def('sym.scalex', rsScaleX, pkFloat));
      Add(Result, Def('sym.scaley', rsScaleY, pkFloat));
      Add(Result, Def('sym.dir', rsDirection, pkChoice, DirChoices));
      Add(Result, Def('sym.mirror', rsMirror, pkBool));
    end;
    Add(Result, Def('sym.showref', rsShowReference, pkBool));
    if not (Obj is TDrawSymbolText) then
      Add(Result, Def('sym.showpower', rsShowPowerPins, pkBool));
    if (not (Obj is TDrawSymbolText)) and (PartOf(Obj as TDrawMethod) <> nil) then
    begin
      Add(Result, Def('sym.mfr', rsManufacturer, pkText));
      Add(Result, Def('sym.model', rsModelNumber, pkText));
    end;
  end;
  if Obj is TDrawPin then
  begin
    Add(Result, Def('pin.name', rsPinName, pkText));
    Add(Result, Def('pin.number', rsPinNumber, pkText));
    Add(Result, Def('pin.length', rsLength, pkInt));
    Add(Result, Def('pin.numpos', rsNumberPosition, pkInt));
    Add(Result, Def('pin.dir', rsDirection, pkChoice, DirChoices));
    Add(Result, Def('pin.shape', rsPinType, pkChoice, PinShapeChoices));
    Add(Result, Def('pin.elec', rsElectricalType, pkChoice, PinElecChoices));
    Add(Result, Def('pin.showname', rsShowName, pkBool));
    Add(Result, Def('pin.shownumber', rsShowNumber, pkBool));
    Add(Result, Def('pin.centre', rsCentreName, pkBool));
  end;
end;

{ ===========================================================================
  CommonProps  (function)
  Parameters:
    Objs: TList - the selected objects
  Returns:
    TPropDefArray - the shared property descriptions; empty if the list is empty
  Notes:
    The properties that every object in a selection has (same name and kind), in the first
    object's order. These are what the ribbon offers for a multiple selection.
  =========================================================================== }
function CommonProps(Objs: TList): TPropDefArray;
var
  i, j, k: Integer;
  First, Other: TPropDefArray;
  Found: Boolean;
begin
  SetLength(Result, 0);
  if (Objs = nil) or (Objs.Count = 0) then
    Exit;
  First := ObjectProps(TDrawingObject(Objs[0]));
  for k := 0 to High(First) do
  begin
    Found := True;
    for i := 1 to Objs.Count - 1 do
    begin
      Other := ObjectProps(TDrawingObject(Objs[i]));
      Found := False;
      for j := 0 to High(Other) do
        if (Other[j].Name = First[k].Name) and (Other[j].Kind = First[k].Kind) then
        begin
          Found := True;
          Break;
        end;
      if not Found then
        Break;
    end;
    if Found then
      Add(Result, First[k]);
  end;
end;

{ ===========================================================================
  BoolText  (function)
  Parameters:
    B: Boolean - the value
  Returns:
    String - "1" for True, "0" for False
  Notes:
    Property text for a Boolean.
  =========================================================================== }
function BoolText(B: Boolean): String;
begin
  if B then
    Result := '1'
  else
    Result := '0';
end;

{ ===========================================================================
  GetProp  (function)
  Parameters:
    Obj: TDrawingObject - the object
    const Name: String - the property name
    out Value: String - set to the property's value
  Returns:
    Boolean - False if the object does not have that property
  Notes:
    Reads one property of an object as text.
  =========================================================================== }
function GetProp(Obj: TDrawingObject; const Name: String; out Value: String): Boolean;
var
  Col: Cardinal;
  W, Dash, N: Integer;
  F: TFontResource;
  Fl: TFillStyleResource;
begin
  Result := True;
  Value := '';
  if Name = 'text' then
  begin
    if Obj is TDrawText then
      Value := (Obj as TDrawText).Str
    else if Obj is TDrawLabel then
      Value := (Obj as TDrawLabel).Str
    else if Obj is TDrawPower then
      Value := (Obj as TDrawPower).Str
    else if Obj is TDrawNoteText then
      Value := (Obj as TDrawNoteText).Str
    else
      Result := False;
  end
  else if Name = 'dir' then
  begin
    if Obj is TDrawText then
      Value := ChoiceText(DirChoices, (Obj as TDrawText).Dir)
    else if Obj is TDrawLabel then
      Value := ChoiceText(DirChoices, (Obj as TDrawLabel).Dir)
    else if Obj is TDrawPower then
      Value := ChoiceText(DirChoices, (Obj as TDrawPower).Dir)
    else if Obj is TDrawNoteText then
      Value := ChoiceText(DirChoices, (Obj as TDrawNoteText).Dir)
    else
      Result := False;
  end
  else if Name = 'label.style' then
  begin
    if Obj is TDrawLabel then
      Value := ChoiceText(LabelChoices, (Obj as TDrawLabel).LabelStyle)
    else
      Result := False;
  end
  else if Name = 'power.type' then
  begin
    if Obj is TDrawPower then
      Value := ChoiceText(PowerChoices, (Obj as TDrawPower).Which)
    else
      Result := False;
  end
  else if Copy(Name, 1, 5) = 'font.' then
  begin
    N := FontNumberOf(Obj);
    if N < 0 then begin
      Result := False;
      Exit;
    end;
    F := Obj.Options.Fonts.Get(N) as TFontResource;
    if Name = 'font.face' then
      Value := F.FaceName
    else if Name = 'font.height' then
      Value := IntToStr(FontPointsOf(F.Height))
    else if Name = 'font.bold' then
      Value := BoolText(F.Weight >= 700)
    else if Name = 'font.italic' then
      Value := BoolText(F.Italic <> 0)
    else if Name = 'font.color' then
    begin
      if FontColorOf(Obj, Col) then
        Value := ColorToHex(Col)
      else
        Result := False;
    end
    else
      Result := False;
  end
  else if Copy(Name, 1, 5) = 'line.' then
  begin
    if not HasLine(Obj) then begin
      Result := False;
      Exit;
    end;
    EffectiveLine(Obj, Col, W, Dash);
    if Name = 'line.color' then
      Value := ColorToHex(Col)
    else if Name = 'line.width' then
      Value := IntToStr(W)
    else if Name = 'line.style' then
      Value := ChoiceText(DashChoices, Dash)
    else
      Result := False;
  end
  else if Copy(Name, 1, 5) = 'fill.' then
  begin
    if not FillNumber(Obj, N) then begin
      Result := False;
      Exit;
    end;
    Fl := Obj.Options.Fills.Get(N) as TFillStyleResource;
    if Name = 'fill.type' then
    begin
      if Fl.Index < 0 then
        Value := ChoiceText(FillChoices, 0)
      else
        Value := ChoiceText(FillChoices, Fl.Index + 1);
    end
    else if Name = 'fill.color' then
      Value := ColorToHex(Fl.Color)
    else
      Result := False;
  end
  else if Name = 'arc.type' then
  begin
    if IsArcPolygon(Obj) then
      Value := ArcTypeText(Obj as TDrawPolygon)
    else
      Result := False;
  end
  else if (Name = 'bus.phases') or (Name = 'bus.spacing') then
  begin
    if (Obj is TDrawLine) and ((Obj as TDrawLine).Kind = xBus) then
    begin
      if Name = 'bus.phases' then
        Value := ChoiceText(PhaseChoices, Ord((Obj as TDrawLine).Phases = 3))
      else
        Value := FloatText((Obj as TDrawLine).PhaseSpacing / UNITS_PER_MM);
    end
    else
      Result := False;
  end
  else if Name = 'poly.closed' then
  begin
    if Obj is TDrawPolygon then
      Value := BoolText((Obj as TDrawPolygon).Close <> 0)
    else
      Result := False;
  end
  else if Name = 'cloud.bump' then
  begin
    if Obj is TDrawCloud then
      Value := FloatText((Obj as TDrawCloud).Bump / UNITS_PER_MM)
    else
      Result := False;
  end
  else if Name = 'measure.unit' then
  begin
    if Obj is TDrawMeasure then
      Value := ChoiceText(UnitChoices, (Obj as TDrawMeasure).UnitMode)
    else
      Result := False;
  end
  else if Name = 'measure.ticks' then
  begin
    if Obj is TDrawMeasure then
      Value := BoolText((Obj as TDrawMeasure).Ticks <> 0)
    else
      Result := False;
  end
  else if Name = 'ruler.pos' then
  begin
    if Obj is TDrawRuler then
    begin
      if (Obj as TDrawRuler).Horizontal <> 0 then
        Value := FloatText(Obj.PointA.y / UNITS_PER_MM)
      else
        Value := FloatText(Obj.PointA.x / UNITS_PER_MM);
    end
    else
      Result := False;
  end
  else if Copy(Name, 1, 5) = 'xref.' then
  begin
    if not (Obj is TDrawRefText) then begin
      Result := False;
      Exit;
    end;
    with Obj as TDrawRefText do
      if Name = 'xref.mode' then
        Value := ChoiceText(ModeChoices, Mode)
      else if Name = 'xref.target' then
        Value := IntToStr(TargetId)
      else if Name = 'xref.prefix' then
        Value := Prefix
      else if Name = 'xref.suffix' then
        Value := Suffix
      else
        Result := False;
  end
  else if Copy(Name, 1, 7) = 'ladder.' then
  begin
    if not (Obj is TDrawLadder) then begin
      Result := False;
      Exit;
    end;
    with Obj as TDrawLadder do
      if Name = 'ladder.left' then
        Value := LeftWire
      else if Name = 'ladder.right' then
        Value := RightWire
      else
        Result := False;
  end
  else if Copy(Name, 1, 6) = 'rungs.' then
  begin
    if not (Obj is TDrawRungGrid) then begin
      Result := False;
      Exit;
    end;
    with Obj as TDrawRungGrid do
      if Name = 'rungs.rows' then
        Value := IntToStr(Rows)
      else if Name = 'rungs.start' then
        Value := IntToStr(StartNumber)
      else if Name = 'rungs.margin' then
        Value := FloatText(MarginMm)
      else if Name = 'rungs.pages' then
        Value := ChoiceText(PagesChoices, Pages - 1)
      else if Name = 'rungs.continue' then
        Value := BoolText(ContinueNumbers)
      else if Name = 'rungs.showheight' then
        Value := BoolText(ShowRowHeight)
      else if Name = 'rungs.aboveblock' then
        Value := BoolText(AboveBlock)
      else
        Result := False;
  end
  else if Copy(Name, 1, 4) = 'sym.' then
  begin
    if not (Obj is TDrawMethod) then begin
      Result := False;
      Exit;
    end;
    with Obj as TDrawMethod do
      if Name = 'sym.ref' then
        Value := GetRef
      else if Name = 'sym.name' then
        Value := GetName
      else if Name = 'sym.canscale' then
        Value := BoolText(CanScale <> 0)
      else if Name = 'sym.scalex' then
        Value := FloatText(ScalingX)
      else if Name = 'sym.scaley' then
        Value := FloatText(ScalingY)
      else if Name = 'sym.dir' then
        Value := ChoiceText(DirChoices, Rotate and 3)
      else if Name = 'sym.mirror' then
        Value := BoolText((Rotate and 4) <> 0)
      else if Name = 'sym.showref' then
        Value := BoolText(Fields[FIELD_REF].Show <> 0)
      else if Name = 'sym.showpower' then
        Value := BoolText(ShowPower <> 0)
      else if Name = 'sym.mfr' then
        Value := Product.Manufacturer
      else if Name = 'sym.model' then
        Value := Product.MPN
      else
        Result := False;
  end
  else if Name = 'symtext.text' then
  begin
    if Obj is TDrawSymbolText then
      Value := TDrawSymbolText(Obj).GetName
    else
      Result := False;
  end
  else if Copy(Name, 1, 4) = 'pin.' then
  begin
    if not (Obj is TDrawPin) then begin
      Result := False;
      Exit;
    end;
    with Obj as TDrawPin do
      if Name = 'pin.name' then
        Value := Str
      else if Name = 'pin.number' then
        Value := Number
      else if Name = 'pin.length' then
        Value := IntToStr(Length)
      else if Name = 'pin.numpos' then
        Value := IntToStr(NumberPos)
      else if Name = 'pin.dir' then
        Value := ChoiceText(DirChoices, Dir)
      else if Name = 'pin.shape' then
        Value := ChoiceText(PinShapeChoices, Which)
      else if Name = 'pin.elec' then
        Value := ChoiceText(PinElecChoices, Elec)
      else if Name = 'pin.showname' then
        Value := BoolText((Show and 1) <> 0)
      else if Name = 'pin.shownumber' then
        Value := BoolText((Show and 2) <> 0)
      else if Name = 'pin.centre' then
        Value := BoolText(CentreName <> 0)
      else
        Result := False;
  end
  else
    Result := False;
end;

{ ===========================================================================
  SetProp  (function)
  Parameters:
    Obj: TDrawingObject - the object
    const Name: String - the property name
    const Value: String - the new value as text
  Returns:
    Boolean - True if the object has the property
  Notes:
    Sets one property of an object from text, refreshing its layout afterwards. Unknown
    properties are ignored and unusable text (such as letters for a number) leaves the value
    unchanged.
  =========================================================================== }
function SetProp(Obj: TDrawingObject; const Name, Value: String): Boolean;
var
  Old: String;
  I: Integer;
begin
  Result := GetProp(Obj, Name, Old);
  if not Result then
    Exit;
  if Name = 'text' then
  begin
    if Obj is TDrawText then
      (Obj as TDrawText).Str := Value
    else if Obj is TDrawLabel then
      (Obj as TDrawLabel).Str := Value
    else if Obj is TDrawPower then
      (Obj as TDrawPower).Str := Value
    else if Obj is TDrawNoteText then
      (Obj as TDrawNoteText).Str := Value;
  end
  else if Name = 'dir' then
  begin
    I := Max(0, ChoiceIndex(DirChoices, Value));
    if Obj is TDrawText then
      (Obj as TDrawText).Dir := I
    else if Obj is TDrawLabel then
      (Obj as TDrawLabel).Dir := I
    else if Obj is TDrawPower then
      (Obj as TDrawPower).Dir := I
    else if Obj is TDrawNoteText then
      (Obj as TDrawNoteText).Dir := I;
  end
  else if Name = 'label.style' then
    (Obj as TDrawLabel).LabelStyle := Max(0, ChoiceIndex(LabelChoices, Value))
  else if Name = 'power.type' then
    (Obj as TDrawPower).Which := Max(0, ChoiceIndex(PowerChoices, Value))
  else if Name = 'font.color' then
    SetFontColor(Obj, HexToColor(Value, cBLACK))
  else if Copy(Name, 1, 5) = 'font.' then
    ChangeFont(Obj, Copy(Name, 6, MaxInt), Value)
  else if Copy(Name, 1, 5) = 'line.' then
    ChangeLine(Obj, Copy(Name, 6, MaxInt), Value)
  else if Copy(Name, 1, 5) = 'fill.' then
    ChangeFill(Obj, Copy(Name, 6, MaxInt), Value)
  else if Name = 'arc.type' then
    SetArcType(Obj as TDrawPolygon, Value)
  else if Name = 'bus.phases' then
    (Obj as TDrawLine).Phases := 1 + 2 * Ord(ChoiceIndex(PhaseChoices, Value) = 1)
  else if Name = 'bus.spacing' then
    (Obj as TDrawLine).PhaseSpacing := Max(1, ParseFloat(Value, DefaultPhaseSpacing / UNITS_PER_MM) * UNITS_PER_MM)
  else if Name = 'poly.closed' then
    (Obj as TDrawPolygon).Close := Ord(Value = '1')
  else if Name = 'cloud.bump' then
    (Obj as TDrawCloud).Bump := Max(2, ParseFloat(Value, 5) * UNITS_PER_MM)
  else if Name = 'measure.unit' then
    (Obj as TDrawMeasure).UnitMode := Max(0, ChoiceIndex(UnitChoices, Value))
  else if Name = 'measure.ticks' then
    (Obj as TDrawMeasure).Ticks := Ord(Value = '1')
  else if Name = 'ruler.pos' then
  begin
    if (Obj as TDrawRuler).Horizontal <> 0 then
      Obj.PointA := DPoint(Obj.PointA.x, ParseFloat(Value, 0) * UNITS_PER_MM)
    else
      Obj.PointA := DPoint(ParseFloat(Value, 0) * UNITS_PER_MM, Obj.PointA.y);
    Obj.PointB := Obj.PointA;
  end
  else if Name = 'xref.mode' then
    (Obj as TDrawRefText).Mode := Max(0, ChoiceIndex(ModeChoices, Value))
  else if Name = 'xref.target' then
    (Obj as TDrawRefText).TargetId := StrToIntDef(Trim(Value), 0)
  else if Name = 'xref.prefix' then
    (Obj as TDrawRefText).Prefix := Value
  else if Name = 'xref.suffix' then
    (Obj as TDrawRefText).Suffix := Value
  else if Name = 'ladder.left' then
    (Obj as TDrawLadder).LeftWire := Value
  else if Name = 'ladder.right' then
    (Obj as TDrawLadder).RightWire := Value
  else if Name = 'rungs.rows' then
    (Obj as TDrawRungGrid).Rows := Max(1, Min(200, StrToIntDef(Trim(Value), (Obj as TDrawRungGrid).Rows)))
  else if Name = 'rungs.start' then
    (Obj as TDrawRungGrid).StartNumber := StrToIntDef(Trim(Value), (Obj as TDrawRungGrid).StartNumber)
  else if Name = 'rungs.margin' then
    (Obj as TDrawRungGrid).MarginMm := Max(0, ParseFloat(Value, (Obj as TDrawRungGrid).MarginMm))
  else if Name = 'rungs.pages' then
    (Obj as TDrawRungGrid).Pages := 1 + Max(0, Min(1, ChoiceIndex(PagesChoices, Value)))
  else if Name = 'rungs.continue' then
    (Obj as TDrawRungGrid).ContinueNumbers := Value = '1'
  else if Name = 'rungs.showheight' then
    (Obj as TDrawRungGrid).ShowRowHeight := Value = '1'
  else if Name = 'rungs.aboveblock' then
    (Obj as TDrawRungGrid).AboveBlock := Value = '1'
  else if Name = 'sym.ref' then
    (Obj as TDrawMethod).Fields[FIELD_REF].Value := Value
  else if Name = 'sym.name' then
    (Obj as TDrawMethod).Fields[FIELD_NAME].Value := Value
  else if (Name = 'symtext.text') and (Obj is TDrawSymbolText) then
    TDrawSymbolText(Obj).Fields[FIELD_NAME].Value := Value
  else if Name = 'sym.canscale' then
    (Obj as TDrawMethod).CanScale := Ord(Value = '1')
  else if Name = 'sym.scalex' then
    (Obj as TDrawMethod).ScalingX := ParseFloat(Value, 1)
  else if Name = 'sym.scaley' then
    (Obj as TDrawMethod).ScalingY := ParseFloat(Value, 1)
  else if Name = 'sym.dir' then
    SetSymbolDirection(Obj as TDrawMethod, (Obj as TDrawMethod).Rotate and 4 or Max(0, ChoiceIndex(DirChoices, Value)))
  else if Name = 'sym.mirror' then
    SetSymbolDirection(Obj as TDrawMethod, (Obj as TDrawMethod).Rotate and 3 or IfThen(Value = '1', 4, 0))
  else if Name = 'sym.showref' then
    (Obj as TDrawMethod).Fields[FIELD_REF].Show := Ord(Value = '1')
  else if Name = 'sym.showpower' then
    SetSymbolShowPower(Obj as TDrawMethod, Value = '1')
  else if (Name = 'sym.mfr') or (Name = 'sym.model') then
    SetProductText(Obj as TDrawMethod, Name = 'sym.mfr', Value)
  else if Name = 'pin.name' then
    (Obj as TDrawPin).Str := Value
  else if Name = 'pin.number' then
    (Obj as TDrawPin).Number := Value
  else if Name = 'pin.length' then
  begin
    { TinyCAD's pin box: a length is 0 (a pin that is only its connection point) or at least 5, and the number is never placed beyond the end of the pin }
    I := StrToIntDef(Trim(Value), (Obj as TDrawPin).Length);
    if I <> 0 then
      I := Max(5, I);
    (Obj as TDrawPin).Length := I;
    (Obj as TDrawPin).NumberPos := Min((Obj as TDrawPin).NumberPos, I);
  end
  else if Name = 'pin.numpos' then
    (Obj as TDrawPin).NumberPos := Max(0, Min(StrToIntDef(Trim(Value), (Obj as TDrawPin).NumberPos), (Obj as TDrawPin).Length))
  else if Name = 'pin.dir' then
    (Obj as TDrawPin).Dir := Max(0, ChoiceIndex(DirChoices, Value))
  else if Name = 'pin.shape' then
    (Obj as TDrawPin).Which := Max(0, ChoiceIndex(PinShapeChoices, Value))
  else if Name = 'pin.elec' then
    (Obj as TDrawPin).Elec := Max(0, ChoiceIndex(PinElecChoices, Value))
  else if Name = 'pin.showname' then
    (Obj as TDrawPin).Show := ((Obj as TDrawPin).Show and not 1) or Ord(Value = '1')
  else if Name = 'pin.shownumber' then
    (Obj as TDrawPin).Show := ((Obj as TDrawPin).Show and not 2) or (2 * Ord(Value = '1'))
  else if Name = 'pin.centre' then
    (Obj as TDrawPin).CentreName := Ord(Value = '1');
  if Obj is TDrawPin then
    (Obj as TDrawPin).DetermineSize;
  Obj.UpdateLayout;
end;

{ ===========================================================================
  CommonValue  (function)
  Parameters:
    Objs: TList - the selected objects
    const Name: String - the property name
    out Mixed: Boolean - set True when the values differ
  Returns:
    String - the shared value as text
  Notes:
    The value of a property across a selection; Mixed shows that the objects disagree (the first
    value is returned then).
  =========================================================================== }
function CommonValue(Objs: TList; const Name: String; out Mixed: Boolean): String;
var
  i: Integer;
  V: String;
  First: Boolean;
begin
  Result := '';
  Mixed := False;
  First := True;
  for i := 0 to Objs.Count - 1 do
    if GetProp(TDrawingObject(Objs[i]), Name, V) then
    begin
      if First then begin
        Result := V;
        First := False;
      end
      else if V <> Result then
        Mixed := True;
    end;
end;

{ ===========================================================================
  SetPropAll  (function)
  Parameters:
    Objs: TList - the selected objects
    const Name: String - the property name
    const Value: String - the new value as text
  Returns:
    Integer - how many objects were changed
  Notes:
    The mass change: sets one property on every object in the list that has it and skips the
    rest.
  =========================================================================== }
function SetPropAll(Objs: TList; const Name, Value: String): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to Objs.Count - 1 do
    if SetProp(TDrawingObject(Objs[i]), Name, Value) then
      Inc(Result);
end;

end.
