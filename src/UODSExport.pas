// SPDX-License-Identifier: LGPL-2.1-or-later
{ The OpenDocument spreadsheet writer of UTableExport: an .ods file (what OpenOffice and LibreOffice save by themselves: a zip with the mimetype first and stored, content.xml,
  styles.xml, meta.xml and META-INF/manifest.xml) with a table for each sheet. Text is written as strings (a line end starts a new paragraph, runs of spaces and tabs are kept),
  numbers as floats, bold cells with a bold style, column widths are kept. Opens in LibreOffice, OpenOffice and Excel.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UODSExport;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, UTableExport;

type
  TODSExport = class(TExportWriter)
  public
    class function Extension: String; override;
    class function Description: String; override;
    procedure SaveToStream(S: TStream); override;
  end;

{ the text of a cell as ODF paragraphs: <text:p> for each line, <text:s text:c="n"/> for spaces after the first of a run, <text:tab/> for a tab }
function OdsParagraphs(const S: String): String;

implementation

uses zipper, zstream, UStrings;

const
  XmlHead = '<?xml version="1.0" encoding="UTF-8"?>' + #10;
  MimeType = 'application/vnd.oasis.opendocument.spreadsheet';

class function TODSExport.Extension: String;
begin
  Result := '.ods';
end;

class function TODSExport.Description: String;
begin
  Result := rsOpenDocumentSheetName;
end;

{ ===========================================================================
  OdsParagraphs  (function)
  Parameters:
    const S: String - UTF-8 text, lines ended with #10, #13#10 or #13
  Returns:
    String - one <text:p> element for each line
  =========================================================================== }
function OdsParagraphs(const S: String): String;
var
  i, Run: Integer;
  Line: String;
  Lines: TStringList;
  k: Integer;

  function LineXml(const L: String): String;
  var
    j: Integer;
  begin
    Result := '';
    j := 1;
    while j <= Length(L) do
    begin
      if L[j] = ' ' then
      begin
        Run := 0;
        while (j <= Length(L)) and (L[j] = ' ') do
        begin
          Inc(Run);
          Inc(j);
        end;
        Result := Result + ' ';
        if Run > 1 then
          Result := Result + '<text:s text:c="' + IntToStr(Run - 1) + '"/>';
      end
      else if L[j] = #9 then
      begin
        Result := Result + '<text:tab/>';
        Inc(j);
      end
      else
      begin
        k := j;
        while (j <= Length(L)) and (L[j] <> ' ') and (L[j] <> #9) do
          Inc(j);
        Result := Result + XmlText(Copy(L, k, j - k));
      end;
    end;
  end;

begin
  Result := '';
  Lines := TStringList.Create;
  try
    Line := StringReplace(StringReplace(S, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
    Lines.Text := Line;
    if (Lines.Count = 0) then
      Lines.Add('');
    for i := 0 to Lines.Count - 1 do
      Result := Result + '<text:p>' + LineXml(Lines[i]) + '</text:p>';
  finally
    Lines.Free;
  end;
end;

function IfThenBold(B: Boolean): String;
begin
  if B then
    Result := ' table:style-name="ceB"'
  else
    Result := '';
end;

function TableXml(Sh: TExportSheet; Index: Integer; const AName: String): String;
var
  r, c, Cols: Integer;
  Cl: TExportCell;
  B: TStringBuilder;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Cols := Sh.ColCount;
  B := TStringBuilder.Create;
  try
    B.Append('<table:table table:name="' + XmlText(AName) + '">');
    for c := 0 to Cols - 1 do
      if Sh.ColWidth(c) > 0 then
        B.Append('<table:table-column table:style-name="co' + IntToStr(Index) + '_' + IntToStr(c) + '"/>')
      else
        B.Append('<table:table-column/>');
    for r := 0 to Sh.RowCount - 1 do
    begin
      B.Append('<table:table-row>');
      for c := 0 to Sh.RowLength(r) - 1 do
      begin
        Cl := Sh.Cell(r, c);
        case Cl.Kind of
          ecText:
            if Cl.Text = '' then
              B.Append('<table:table-cell' + IfThenBold(Cl.Bold) + '/>')
            else
              B.Append('<table:table-cell' + IfThenBold(Cl.Bold) + ' office:value-type="string">' + OdsParagraphs(Cl.Text) + '</table:table-cell>');
        else
          B.Append('<table:table-cell' + IfThenBold(Cl.Bold) + ' office:value-type="float" office:value="' + ExportNumberText(Cl) + '"><text:p>' + ExportNumberText(Cl) + '</text:p></table:table-cell>');
        end;
      end;
      B.Append('</table:table-row>');
    end;
    B.Append('</table:table>');
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

procedure TODSExport.SaveToStream(S: TStream);
const
  Ns = 'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" ' +
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" ' +
    'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0" ' +
    'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"';
var
  Z: TZipper;
  Parts: array of TStringStream;
  T, Empty: TExportTable;
  i, c: Integer;
  Content, Auto: String;
  Names: TStringList;
  FS: TFormatSettings;

  procedure AddPart(const AName, AText: String; Stored: Boolean);
  var
    E: TZipFileEntry;
  begin
    SetLength(Parts, Length(Parts) + 1);
    Parts[High(Parts)] := TStringStream.Create(AText);
    E := Z.Entries.AddFileEntry(Parts[High(Parts)], AName);
    if Stored then
      E.CompressionLevel := clnone;
  end;

begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
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
    begin
      Names.Add(SafeSheetName(T[i].Name, Names));
    end;
    Auto := '<office:automatic-styles><style:style style:name="ceB" style:family="table-cell"><style:text-properties fo:font-weight="bold" style:font-weight-asian="bold" style:font-weight-complex="bold"/></style:style>';
    for i := 0 to T.SheetCount - 1 do
      for c := 0 to T[i].ColCount - 1 do
        if T[i].ColWidth(c) > 0 then
          Auto := Auto + '<style:style style:name="co' + IntToStr(i) + '_' + IntToStr(c) + '" style:family="table-column"><style:table-column-properties style:column-width="' +
            FloatToStr((T[i].ColWidth(c) + 1) * 0.19, FS) + 'cm"/></style:style>';
    Auto := Auto + '</office:automatic-styles>';
    Content := XmlHead + '<office:document-content ' + Ns + ' office:version="1.2">' + Auto + '<office:body><office:spreadsheet>';
    for i := 0 to T.SheetCount - 1 do
      Content := Content + TableXml(T[i], i, Names[i]);
    Content := Content + '</office:spreadsheet></office:body></office:document-content>';
    AddPart('mimetype', MimeType, True);
    AddPart('content.xml', Content, False);
    AddPart('styles.xml', XmlHead + '<office:document-styles ' + Ns + ' office:version="1.2"><office:styles/></office:document-styles>', False);
    AddPart('meta.xml', XmlHead + '<office:document-meta ' + Ns + ' office:version="1.2"><office:meta><meta:generator>TyCAD</meta:generator></office:meta></office:document-meta>', False);
    AddPart('META-INF/manifest.xml', XmlHead + '<manifest:manifest ' + Ns + ' manifest:version="1.2">' +
      '<manifest:file-entry manifest:full-path="/" manifest:version="1.2" manifest:media-type="' + MimeType + '"/>' +
      '<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>' +
      '<manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>' +
      '<manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/></manifest:manifest>', False);
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
  RegisterExportWriter(TODSExport);

end.
