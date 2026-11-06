// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Excel workbook writer of UTableExport: an .xlsx file (Office Open XML: a zip of XML parts) with a tab for each sheet. Text is written as inline strings, numbers as
  numbers, bold cells (the headings) with a bold font; column widths are kept; a sheet whose first row is all bold is frozen under it so the headings stay in view. Made with
  the zipper unit of the FCL; opens in Excel, LibreOffice and OpenOffice.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UXLSXExport;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, UTableExport;

type
  TXLSXExport = class(TExportWriter)
  public
    class function Extension: String; override;
    class function Description: String; override;
    procedure SaveToStream(S: TStream); override;
  end;

{ the name of a cell: column 0 = A, 25 = Z, 26 = AA; row 0 = 1 }
function XlsxCellName(Row, Col: Integer): String;

implementation

uses zipper, UStrings;

const
  XmlHead = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + #10;

class function TXLSXExport.Extension: String;
begin
  Result := '.xlsx';
end;

class function TXLSXExport.Description: String;
begin
  Result := rsExcelWorkbookName;
end;

{ ===========================================================================
  XlsxCellName  (function)
  Parameters:
    Row, Col: Integer - 0 based
  Returns:
    String - A1 style
  =========================================================================== }
function XlsxCellName(Row, Col: Integer): String;
var
  N: Integer;
begin
  Result := '';
  N := Col;
  repeat
    Result := Chr(Ord('A') + N mod 26) + Result;
    N := N div 26 - 1;
  until N < 0;
  Result := Result + IntToStr(Row + 1);
end;

function SheetXml(Sh: TExportSheet): String;
var
  r, c, Cols: Integer;
  Cl: TExportCell;
  Ref, Sty: String;
  Frozen: Boolean;
  B: TStringBuilder;
  Wd: Double;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Cols := Sh.ColCount;
  Frozen := Sh.RowCount > 1;
  if Frozen then
    for c := 0 to Sh.RowLength(0) - 1 do
      if not Sh.Cell(0, c).Bold then
        Frozen := False;
  if Sh.RowLength(0) = 0 then
    Frozen := False;
  B := TStringBuilder.Create;
  try
    B.Append(XmlHead);
    B.Append('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
    if Frozen then
      B.Append('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>');
    Wd := 0;      // (the <cols> element only when some column has a width)
    for c := 0 to Cols - 1 do
      if Sh.ColWidth(c) > 0 then
        Wd := 1;
    if Wd > 0 then
    begin
      B.Append('<cols>');
      for c := 0 to Cols - 1 do
        if Sh.ColWidth(c) > 0 then
          B.Append('<col min="' + IntToStr(c + 1) + '" max="' + IntToStr(c + 1) + '" width="' + FloatToStr(Sh.ColWidth(c) + 1, FS) + '" customWidth="1"/>');
      B.Append('</cols>');
    end;
    B.Append('<sheetData>');
    for r := 0 to Sh.RowCount - 1 do
    begin
      B.Append('<row r="' + IntToStr(r + 1) + '">');
      for c := 0 to Sh.RowLength(r) - 1 do
      begin
        Cl := Sh.Cell(r, c);
        Ref := XlsxCellName(r, c);
        if Cl.Bold then
          Sty := ' s="1"'
        else
          Sty := '';
        if Cl.Kind = ecText then
        begin
          if Cl.Text <> '' then
            B.Append('<c r="' + Ref + '"' + Sty + ' t="inlineStr"><is><t xml:space="preserve">' + XmlText(Cl.Text) + '</t></is></c>')
          else if Cl.Bold then
            B.Append('<c r="' + Ref + '"' + Sty + '/>');
        end
        else
          B.Append('<c r="' + Ref + '"' + Sty + '><v>' + ExportNumberText(Cl) + '</v></c>');
      end;
      B.Append('</row>');
    end;
    B.Append('</sheetData></worksheet>');
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

{ ===========================================================================
  TXLSXExport.SaveToStream  (procedure)
  Parameters:
    S: TStream - where the zip goes
  Notes:
    A table with no sheet gets one empty tab (a workbook needs at least one). The parts are built in memory and zipped.
  =========================================================================== }
procedure TXLSXExport.SaveToStream(S: TStream);
const
  Ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';
var
  Z: TZipper;
  Parts: array of TStringStream;
  i, N: Integer;
  Names: TStringList;
  Empty: TExportTable;
  T: TExportTable;
  Ct, Wb, WbRels: String;

  procedure AddPart(const AName, AText: String);
  begin
    SetLength(Parts, Length(Parts) + 1);
    Parts[High(Parts)] := TStringStream.Create(AText);
    Z.Entries.AddFileEntry(Parts[High(Parts)], AName);
  end;

begin
  Empty := nil;
  T := Table;
  if T.SheetCount = 0 then
  begin
    Empty := TExportTable.Create;
    Empty.AddSheet('Sheet');
    T := Empty;
  end;
  Names := TStringList.Create;
  Z := TZipper.Create;
  SetLength(Parts, 0);
  try
    for i := 0 to T.SheetCount - 1 do
      Names.Add(SafeSheetName(T[i].Name, Names));
    N := T.SheetCount;
    Ct := XmlHead + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
      '<Default Extension="xml" ContentType="application/xml"/>' +
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>';
    for i := 1 to N do
      Ct := Ct + '<Override PartName="/xl/worksheets/sheet' + IntToStr(i) + '.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>';
    Ct := Ct + '</Types>';
    AddPart('[Content_Types].xml', Ct);
    AddPart('_rels/.rels', XmlHead + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>');
    Wb := XmlHead + '<workbook ' + Ns + ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>';
    WbRels := XmlHead + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">';
    for i := 1 to N do
    begin
      Wb := Wb + '<sheet name="' + XmlText(Names[i - 1]) + '" sheetId="' + IntToStr(i) + '" r:id="rId' + IntToStr(i) + '"/>';
      WbRels := WbRels + '<Relationship Id="rId' + IntToStr(i) + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet' + IntToStr(i) + '.xml"/>';
    end;
    Wb := Wb + '</sheets></workbook>';
    WbRels := WbRels + '<Relationship Id="rId' + IntToStr(N + 1) + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>';
    AddPart('xl/workbook.xml', Wb);
    AddPart('xl/_rels/workbook.xml.rels', WbRels);
    AddPart('xl/styles.xml', XmlHead + '<styleSheet ' + Ns + '><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>' +
      '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>' +
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
      '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>' +
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>');
    for i := 0 to N - 1 do
      AddPart('xl/worksheets/sheet' + IntToStr(i + 1) + '.xml', SheetXml(T[i]));
    Z.SaveToStream(S);
  finally
    Z.Free;
    for i := 0 to High(Parts) do
      Parts[i].Free;
    Names.Free;
    Empty.Free;
  end;
end;

initialization
  RegisterExportWriter(TXLSXExport);

end.
