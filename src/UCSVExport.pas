// SPDX-License-Identifier: LGPL-2.1-or-later
{ The CSV writer of UTableExport: the first sheet of the table as comma (or other) separated text, UTF-8, one line for each row (RFC 4180: a field that holds the delimiter, a
  quote or a line end is quoted, quotes inside it doubled). Numbers are written with a point. A table with several sheets writes only the one named by SheetIndex.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UCSVExport;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, UTableExport;

type
  TCSVExport = class(TExportWriter)
  public
    Delimiter: Char;          // the separator of the fields (default ,)
    EOL: String;              // the line end (default LineEnding)
    WithBom: Boolean;         // start the file with the UTF-8 byte order mark, which Excel wants for accented letters (default off)
    SheetIndex: Integer;      // the sheet written (default 0)
    constructor Create(ATable: TExportTable); override;
    class function Extension: String; override;
    class function Description: String; override;
    procedure SaveToStream(S: TStream); override;
  end;

{ the field as CSV text: quoted when it holds the delimiter, a quote or a line end, with the quotes in it doubled }
function CsvField(const S: String; Delimiter: Char = ','): String;

implementation

uses UStrings;

{ ===========================================================================
  CsvField  (function)
  Parameters:
    const S: String - the text of one field
    Delimiter: Char - the separator in use
  Returns:
    String
  =========================================================================== }
function CsvField(const S: String; Delimiter: Char): String;
begin
  if (Pos(Delimiter, S) = 0) and (Pos('"', S) = 0) and (Pos(#10, S) = 0) and (Pos(#13, S) = 0) then
    Result := S
  else
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"';
end;

constructor TCSVExport.Create(ATable: TExportTable);
begin
  inherited Create(ATable);
  Delimiter := ',';
  EOL := LineEnding;
  WithBom := False;
  SheetIndex := 0;
end;

class function TCSVExport.Extension: String;
begin
  Result := '.csv';
end;

class function TCSVExport.Description: String;
begin
  Result := rsCsvFileName;
end;

{ ===========================================================================
  TCSVExport.SaveToStream  (procedure)
  Parameters:
    S: TStream - where the text goes
  Notes:
    A row is as long as its cells; rows are not padded to the widest. A table with no sheet writes nothing.
  =========================================================================== }
procedure TCSVExport.SaveToStream(S: TStream);
var
  Sh: TExportSheet;
  r, c: Integer;
  Line, Cell: String;
  Cl: TExportCell;
  Bom: String;
  Last: Integer;
begin
  if Table.SheetCount = 0 then
    Exit;
  if (SheetIndex < 0) or (SheetIndex >= Table.SheetCount) then
    raise EExportError.Create('sheet');
  if WithBom then
  begin
    Bom := #$EF#$BB#$BF;
    S.WriteBuffer(Bom[1], 3);
  end;
  Sh := Table[SheetIndex];
  for r := 0 to Sh.RowCount - 1 do
  begin
    Line := '';
    Last := Sh.RowLength(r) - 1;
    for c := 0 to Last do
    begin
      Cl := Sh.Cell(r, c);
      if Cl.Kind = ecText then
        Cell := CsvField(Cl.Text, Delimiter)
      else
        Cell := ExportNumberText(Cl);
      if c > 0 then
        Line := Line + Delimiter;
      Line := Line + Cell;
    end;
    Line := Line + EOL;
    S.WriteBuffer(Line[1], Length(Line));
  end;
end;

initialization
  RegisterExportWriter(TCSVExport);

end.
