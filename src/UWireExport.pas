// SPDX-License-Identifier: LGPL-2.1-or-later
{ UWireExport - the text on the wires of a design as a table: every wire label and bus name of every sheet, for a spreadsheet or another tool (Special > Export Wires).

  Columns: Sheet (1-based), Sheet name, Kind (Wire label or Bus name), Style (a wire label's style: Plain, Input, Output or In/Out; empty for a bus name), Text, X (mm) and Y (mm)
  (where the label connects to its wire, or where the bus name stands; from the sheet's origin, as the Position fields show them). Rows are in the order of the sheets, then of
  the drawing. A label or bus name with no text is left out.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UWireExport;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, UDPoint, UDrawTypes, UDrawingObjects, UDesign;

{ the table as CSV (header line first), lines ended with EOL; Count gets the number of rows written }
function WireTextCsv(Design: TDesignFile; out Count: Integer; const EOL: String = LineEnding): String;

implementation

uses UPaper;

{ CSV text: quoted when it holds a comma, a quote or a line end, with the quotes in it doubled (RFC 4180) }
function CsvText(const S: String): String;
begin
  if (Pos(',', S) = 0) and (Pos('"', S) = 0) and (Pos(#10, S) = 0) and (Pos(#13, S) = 0) then
    Result := S
  else
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"';
end;

{ ===========================================================================
  LabelStyleName  (function)
  Parameters:
    AStyle: Integer - a wire label's style (label_normal ... label_io)
  Returns:
    String - Plain, Input, Output or In/Out
  =========================================================================== }
function LabelStyleName(AStyle: Integer): String;
begin
  case AStyle of
    label_in: Result := 'Input';
    label_out: Result := 'Output';
    label_io: Result := 'In/Out';
  else
    Result := 'Plain';
  end;
end;

{ ===========================================================================
  MmText  (function)
  Parameters:
    V: Double - a length in design units
  Returns:
    String - the length in mm, with a point as the decimal separator and no more than two decimals
  =========================================================================== }
function MmText(V: Double): String;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := FloatToStrF(V / UNITS_PER_MM, ffFixed, 15, 2, FS);
end;

{ ===========================================================================
  WireTextCsv  (function)
  Parameters:
    Design: TDesignFile - the design
    out Count: Integer - the number of rows written (not counting the header)
    const EOL: String - the line end
  Returns:
    String - the CSV text
  Notes:
    Reads every sheet's wire labels (TDrawLabel) and bus names (a TDrawText of the bus name kind). A value is quoted when it holds a comma, a quote or a line end.
  =========================================================================== }
function WireTextCsv(Design: TDesignFile; out Count: Integer; const EOL: String): String;
var
  s, i: Integer;
  Obj: TDrawingObject;
  Kind, Style, Txt: String;
  P: TDPoint;
begin
  Count := 0;
  Result := 'Sheet,Sheet name,Kind,Style,Text,X (mm),Y (mm)' + EOL;
  if Design = nil then
    Exit;
  for s := 0 to Design.SheetCount - 1 do
    for i := 0 to Design.Sheets[s].Drawing.Count - 1 do
    begin
      Obj := Design.Sheets[s].Drawing[i];
      if Obj is TDrawLabel then
      begin
        Kind := 'Wire label';
        Style := LabelStyleName(TDrawLabel(Obj).LabelStyle);
        Txt := TDrawLabel(Obj).Str;
        P := TDrawLabel(Obj).ActivePoint;
        if (P.x = DPointInvalid.x) and (P.y = DPointInvalid.y) then
          P := Obj.PointA;
      end
      else if (Obj is TDrawText) and (TDrawText(Obj).Kind = xBusNameEx) then
      begin
        Kind := 'Bus name';
        Style := '';
        Txt := TDrawText(Obj).Str;
        P := Obj.PointA;
      end
      else
        Continue;
      if Txt = '' then
        Continue;
      Result := Result + IntToStr(s + 1) + ',' + CsvText(Design.Sheets[s].SheetName) + ',' + Kind + ',' + Style + ',' + CsvText(Txt) + ',' + MmText(P.x) + ',' + MmText(P.y) + EOL;
      Inc(Count);
    end;
end;

end.
