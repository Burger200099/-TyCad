// SPDX-License-Identifier: LGPL-2.1-or-later
{ Tables out: one place that holds what the exports write and one family of writers that turn it into a file.

  An export fills a TExportTable (sheets of rows of cells: text, whole numbers, fractional numbers, a bold flag for headers) and knows nothing about files. A writer
  (TExportWriter and its descendants: TCSVExport in UCSVExport, TXLSXExport in UXLSXExport, TODSExport in UODSExport) turns the table into a stream; SaveToFile writes
  it to disk through a temporary file so a failed write never leaves half a file in place of a good one. Each writer registers itself (RegisterExportWriter) from its
  unit's initialization, so a program that lists the unit in its uses has the format, and ExportWriterFor / ExportFilter find it by the file extension.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UTableExport;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

type
  EExportError = class(Exception);

  TExportCellKind = (ecText, ecInt, ecFloat);

  { one cell: a text, a whole number or a fractional number (Decimals = digits after the point, -1 = as many as it takes); Bold is for headers }
  TExportCell = record
    Kind: TExportCellKind;
    Text: String;
    Int: Int64;
    Float: Double;
    Decimals: Integer;
    Bold: Boolean;
  end;
  TExportCellArray = array of TExportCell;

  { one sheet (a CSV file holds one; a workbook one tab for each) }
  TExportSheet = class
  private
    FName: String;
    FRows: array of TExportCellArray;
    FWidths: array of Double;
    function GetRowCount: Integer;
    function GetColCount: Integer;
  public
    constructor Create(const AName: String);
    { a row: strings are text cells, integers whole numbers, Double / Single / Extended fractional numbers, Boolean 1 / 0 as text 'TRUE' / 'FALSE' }
    procedure AddRow(const Cells: array of const);
    { a row of bold text cells (the column headings) }
    procedure AddHeaderRow(const Names: array of String);
    { a row made of cells built with TextCell / IntCell / FloatCell }
    procedure AddCells(const Cells: TExportCellArray);
    { the width of a column in characters (0 = the program's default); columns count from 0 }
    procedure SetColWidth(Col: Integer; Chars: Double);
    function ColWidth(Col: Integer): Double;
    { the cell at a row and column; an empty text cell beyond the end of a row }
    function Cell(Row, Col: Integer): TExportCell;
    { how many cells the row was given (0 beyond the last row) }
    function RowLength(Row: Integer): Integer;
    property Name: String read FName write FName;
    property RowCount: Integer read GetRowCount;
    property ColCount: Integer read GetColCount;
  end;

  { the sheets }
  TExportTable = class
  private
    FSheets: array of TExportSheet;
    function GetSheetCount: Integer;
    function GetSheet(Index: Integer): TExportSheet;
  public
    destructor Destroy; override;
    function AddSheet(const AName: String): TExportSheet;
    procedure Clear;
    property SheetCount: Integer read GetSheetCount;
    property Sheets[Index: Integer]: TExportSheet read GetSheet; default;
  end;

  TExportWriter = class;
  TExportWriterClass = class of TExportWriter;

  { the base of the writers: SaveToStream is what a format has to do; the rest is shared }
  TExportWriter = class
  private
    FTable: TExportTable;
  public
    constructor Create(ATable: TExportTable); virtual;
    { the extension with its dot ('.csv') and the name of the format for a file dialog ('CSV file') }
    class function Extension: String; virtual; abstract;
    class function Description: String; virtual; abstract;
    procedure SaveToStream(S: TStream); virtual; abstract;
    { writes the file (through a temporary file next to it, renamed over it when all of it was written); EExportError when it cannot be written }
    procedure SaveToFile(const AFileName: String);
    { the whole output as a string (the bytes of the file; for the text formats and the tests) }
    function SaveToString: String;
    property Table: TExportTable read FTable;
  end;

function TextCell(const S: String; ABold: Boolean = False): TExportCell;
function IntCell(V: Int64): TExportCell;
function FloatCell(V: Double; ADecimals: Integer = -1): TExportCell;

{ a number as text with a point for the decimal separator, whatever the system's settings are }
function ExportNumberText(const C: TExportCell): String;
{ text for an XML file: & < > and quotes escaped, characters XML 1.0 cannot hold dropped }
function XmlText(const S: String): String;

procedure RegisterExportWriter(AClass: TExportWriterClass);
{ the class for a file name's extension (nil when none is registered) }
function ExportWriterClassFor(const AFileName: String): TExportWriterClass;
{ a writer for the file name's extension, or nil }
function ExportWriterFor(const AFileName: String; ATable: TExportTable): TExportWriter;
{ the name of a tab: at most 31 characters, none of  [ ] : * ? / \  , not empty, not the same (ignoring case) as one of Used (what Excel and OpenOffice both accept) }
function SafeSheetName(const AName: String; Used: TStrings): String;
{ the filter of a save dialog for the formats named (extensions with their dot, '.csv;.xlsx'), in that order, then All files }
function ExportFilter(const Exts: String): String;
{ how many writers are registered (for the tests) }
function ExportWriterCount: Integer;

implementation

uses UStrings;

var
  Writers: array of TExportWriterClass;

{ ===========================================================================
  TextCell / IntCell / FloatCell  (functions)
  Returns:
    TExportCell - a cell of that kind
  =========================================================================== }
function TextCell(const S: String; ABold: Boolean): TExportCell;
begin
  Result := Default(TExportCell);
  Result.Kind := ecText;
  Result.Text := S;
  Result.Decimals := -1;
  Result.Bold := ABold;
end;

function IntCell(V: Int64): TExportCell;
begin
  Result := Default(TExportCell);
  Result.Kind := ecInt;
  Result.Int := V;
  Result.Decimals := -1;
end;

function FloatCell(V: Double; ADecimals: Integer): TExportCell;
begin
  Result := Default(TExportCell);
  Result.Kind := ecFloat;
  Result.Float := V;
  Result.Decimals := ADecimals;
end;

{ ===========================================================================
  ExportNumberText  (function)
  Parameters:
    const C: TExportCell - a whole or fractional number cell (a text cell gives its text)
  Returns:
    String - the number with a point as the decimal separator; a fractional number with Decimals set has that many digits, else as few as show the value (15 significant)
  =========================================================================== }
function ExportNumberText(const C: TExportCell): String;
var
  FS: TFormatSettings;
begin
  case C.Kind of
    ecInt: Result := IntToStr(C.Int);
    ecFloat:
      begin
        FS := DefaultFormatSettings;
        FS.DecimalSeparator := '.';
        if C.Decimals >= 0 then
          Result := FloatToStrF(C.Float, ffFixed, 15, C.Decimals, FS)
        else
        begin
          Result := FloatToStrF(C.Float, ffGeneral, 15, 0, FS);
          if Pos('E', Result) > 0 then
          begin
            { no exponent: spreadsheets and the other programs reading CSV all take plain digits }
            Result := FloatToStrF(C.Float, ffFixed, 15, 15, FS);
            while (Length(Result) > 1) and (Result[Length(Result)] = '0') do
              Delete(Result, Length(Result), 1);
            if Result[Length(Result)] = '.' then
              Delete(Result, Length(Result), 1);
          end;
        end;
      end;
  else
    Result := C.Text;
  end;
end;

{ ===========================================================================
  XmlText  (function)
  Parameters:
    const S: String - UTF-8 text
  Returns:
    String - S for the inside of an XML element or attribute
  Notes:
    Characters below space other than tab, line feed and carriage return are dropped (XML 1.0 has no way to write them).
  =========================================================================== }
function XmlText(const S: String): String;
var
  i: Integer;
  C: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    C := S[i];
    case C of
      '&': Result := Result + '&amp;';
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '"': Result := Result + '&quot;';
      #0..#8, #11, #12, #14..#31: ;
    else
      Result := Result + C;
    end;
  end;
end;

{ ---- TExportSheet ---- }

constructor TExportSheet.Create(const AName: String);
begin
  inherited Create;
  FName := AName;
end;

function TExportSheet.GetRowCount: Integer;
begin
  Result := Length(FRows);
end;

function TExportSheet.GetColCount: Integer;
var
  i: Integer;
begin
  Result := Length(FWidths);
  for i := 0 to High(FRows) do
    if Length(FRows[i]) > Result then
      Result := Length(FRows[i]);
end;

procedure TExportSheet.AddCells(const Cells: TExportCellArray);
begin
  SetLength(FRows, Length(FRows) + 1);
  FRows[High(FRows)] := Copy(Cells);
end;

procedure TExportSheet.AddRow(const Cells: array of const);
var
  R: TExportCellArray;
  i: Integer;
begin
  SetLength(R, Length(Cells));
  for i := 0 to High(Cells) do
    with Cells[i] do
      case VType of
        vtInteger: R[i] := IntCell(VInteger);
        vtInt64: R[i] := IntCell(VInt64^);
        vtQWord: R[i] := IntCell(Int64(VQWord^));
        vtBoolean: if VBoolean then R[i] := TextCell('TRUE') else R[i] := TextCell('FALSE');
        vtExtended: R[i] := FloatCell(VExtended^);
        vtCurrency: R[i] := FloatCell(VCurrency^);
        vtChar: R[i] := TextCell(VChar);
        vtString: R[i] := TextCell(VString^);
        vtAnsiString: R[i] := TextCell(AnsiString(VAnsiString));
        vtUnicodeString: R[i] := TextCell(UTF8Encode(UnicodeString(VUnicodeString)));
        vtWideString: R[i] := TextCell(UTF8Encode(WideString(VWideString)));
        vtPChar: R[i] := TextCell(StrPas(VPChar));
      else
        R[i] := TextCell('');
      end;
  AddCells(R);
end;

procedure TExportSheet.AddHeaderRow(const Names: array of String);
var
  R: TExportCellArray;
  i: Integer;
begin
  SetLength(R, Length(Names));
  for i := 0 to High(Names) do
    R[i] := TextCell(Names[i], True);
  AddCells(R);
end;

procedure TExportSheet.SetColWidth(Col: Integer; Chars: Double);
var
  i, Old: Integer;
begin
  if Col < 0 then
    Exit;
  if Col >= Length(FWidths) then
  begin
    Old := Length(FWidths);
    SetLength(FWidths, Col + 1);
    for i := Old to Col do
      FWidths[i] := 0;
  end;
  FWidths[Col] := Chars;
end;

function TExportSheet.ColWidth(Col: Integer): Double;
begin
  if (Col >= 0) and (Col < Length(FWidths)) then
    Result := FWidths[Col]
  else
    Result := 0;
end;

function TExportSheet.Cell(Row, Col: Integer): TExportCell;
begin
  if (Row >= 0) and (Row < Length(FRows)) and (Col >= 0) and (Col < Length(FRows[Row])) then
    Result := FRows[Row][Col]
  else
    Result := TextCell('');
end;

function TExportSheet.RowLength(Row: Integer): Integer;
begin
  if (Row >= 0) and (Row < Length(FRows)) then
    Result := Length(FRows[Row])
  else
    Result := 0;
end;

{ ---- TExportTable ---- }

destructor TExportTable.Destroy;
begin
  Clear;
  inherited Destroy;
end;

function TExportTable.GetSheetCount: Integer;
begin
  Result := Length(FSheets);
end;

function TExportTable.GetSheet(Index: Integer): TExportSheet;
begin
  Result := FSheets[Index];
end;

function TExportTable.AddSheet(const AName: String): TExportSheet;
begin
  Result := TExportSheet.Create(AName);
  SetLength(FSheets, Length(FSheets) + 1);
  FSheets[High(FSheets)] := Result;
end;

procedure TExportTable.Clear;
var
  i: Integer;
begin
  for i := 0 to High(FSheets) do
    FSheets[i].Free;
  SetLength(FSheets, 0);
end;

{ ---- TExportWriter ---- }

constructor TExportWriter.Create(ATable: TExportTable);
begin
  inherited Create;
  FTable := ATable;
end;

{ ===========================================================================
  TExportWriter.SaveToFile  (procedure)
  Parameters:
    const AFileName: String - the file to write
  Notes:
    Writes to AFileName + '.tmp' and renames it over the file when it is all there, so an error leaves the old file alone. EExportError (with the system's message) when the
    file or the folder cannot be written.
  =========================================================================== }
procedure TExportWriter.SaveToFile(const AFileName: String);
var
  Tmp: String;
  FS: TFileStream;
begin
  Tmp := AFileName + '.tmp';
  try
    FS := TFileStream.Create(Tmp, fmCreate);
    try
      SaveToStream(FS);
    finally
      FS.Free;
    end;
    if FileExists(AFileName) and not DeleteFile(AFileName) then
      raise EExportError.Create(AFileName);
    if not RenameFile(Tmp, AFileName) then
      raise EExportError.Create(AFileName);
  except
    on E: EExportError do
    begin
      DeleteFile(Tmp);
      raise;
    end;
    on E: Exception do
    begin
      DeleteFile(Tmp);
      raise EExportError.Create(E.Message);
    end;
  end;
end;

function TExportWriter.SaveToString: String;
var
  MS: TMemoryStream;
begin
  MS := TMemoryStream.Create;
  try
    SaveToStream(MS);
    SetLength(Result, MS.Size);
    if MS.Size > 0 then
      Move(MS.Memory^, Result[1], MS.Size);
  finally
    MS.Free;
  end;
end;

{ ===========================================================================
  SafeSheetName  (function)
  Parameters:
    const AName: String - the name wanted
    Used: TStrings - names the tabs have already
  Returns:
    String - a name Excel accepts: the forbidden characters are replaced by _, cut to 31 characters (by characters, not bytes), 'Sheet' when empty, and numbered (_2, _3 ...) when
    it repeats one of Used
  =========================================================================== }
function SafeSheetName(const AName: String; Used: TStrings): String;
var
  W: UnicodeString;
  i, N: Integer;
  Base, Try_: String;
  Dup: Boolean;
begin
  W := UTF8Decode(AName);
  for i := 1 to Length(W) do
    if W[i] in ['[', ']', ':', '*', '?', '/', '\'] then
      W[i] := '_';
  if Length(W) > 31 then
    SetLength(W, 31);
  Base := Trim(UTF8Encode(W));
  while (Base <> '') and (Base[1] = '''') do
    Delete(Base, 1, 1);
  if Base = '' then
    Base := 'Sheet';
  Result := Base;
  N := 1;
  repeat
    Dup := False;
    for i := 0 to Used.Count - 1 do
      if SameText(Used[i], Result) then
        Dup := True;
    if Dup then
    begin
      Inc(N);
      Try_ := '_' + IntToStr(N);
      W := UTF8Decode(Base);
      if Length(W) + Length(Try_) > 31 then
        SetLength(W, 31 - Length(Try_));
      Result := UTF8Encode(W) + Try_;
    end;
  until not Dup;
end;

{ ---- the registry ---- }

procedure RegisterExportWriter(AClass: TExportWriterClass);
var
  i: Integer;
begin
  for i := 0 to High(Writers) do
    if Writers[i] = AClass then
      Exit;
  SetLength(Writers, Length(Writers) + 1);
  Writers[High(Writers)] := AClass;
end;

function ExportWriterClassFor(const AFileName: String): TExportWriterClass;
var
  i: Integer;
  E: String;
begin
  Result := nil;
  E := LowerCase(ExtractFileExt(AFileName));
  for i := 0 to High(Writers) do
    if LowerCase(Writers[i].Extension) = E then
      Exit(Writers[i]);
end;

function ExportWriterFor(const AFileName: String; ATable: TExportTable): TExportWriter;
var
  C: TExportWriterClass;
begin
  C := ExportWriterClassFor(AFileName);
  if C = nil then
    Result := nil
  else
    Result := C.Create(ATable);
end;

function ExportFilter(const Exts: String): String;
var
  L: TStringList;
  i, k: Integer;
begin
  Result := '';
  L := TStringList.Create;
  try
    L.Delimiter := ';';
    L.StrictDelimiter := True;
    L.DelimitedText := Exts;
    for i := 0 to L.Count - 1 do
      for k := 0 to High(Writers) do
        if SameText(Writers[k].Extension, Trim(L[i])) then
          Result := Result + Writers[k].Description + ' (*' + Writers[k].Extension + ')|*' + Writers[k].Extension + '|';
  finally
    L.Free;
  end;
  Result := Result + rsAllFilesFilter;
end;

function ExportWriterCount: Integer;
begin
  Result := Length(Writers);
end;

end.
