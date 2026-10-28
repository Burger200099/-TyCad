// SPDX-License-Identifier: LGPL-2.1-or-later
{ Port of XMLWriter.h/.cpp (CXMLWriter).
  Differences from the C++ original:
  - Writes to a TStream and assumes Strings are UTF-8 (the Lazarus convention), so
    libiconv is not needed.
  - C++ templates become explicit method names where Pascal cannot overload by type
    (UInt, Color).
  - LineCounter counts real line feeds written (the C++ version incremented once per
    SendString call, which was not a true line count).
  Output layout (CRLF line endings, tabs, quoting) is otherwise identical. }
unit UXMLWriter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, UDPoint, UXMLException, UXMLCodec;

type
  TXMLWriter = class
  private
    FOutput: TStream;
    FChildData: Boolean;
    FTags: TStringList;      // index 0 = innermost open tag
    FNestingLevel: Integer;
    FNeedsNewline: Boolean;
    FNeedsTabs: Boolean;
    FLineCounter: Integer;
    procedure SendString(const S: String);
    procedure CloseOpenTag;
    procedure InternalAddChildData(const Data: String);
    procedure InternalAddAttribute(const Name, Value: String);
    procedure InternalAddTag(const TagName, Data: String);
  public
    constructor Create(AOutput: TStream);
    destructor Destroy; override;

    class function Escape(const S: String): String;

    procedure AddComment(const Comment: String);
    procedure AddTag(const TagName: String); overload;
    procedure CloseTag;

    { name + value forms (add the tag, its data and close it in one go) }
    procedure AddTag(const TagName, Value: String); overload;
    procedure AddTag(const TagName: String; Value: Integer); overload;
    procedure AddTag(const TagName: String; Value: Double); overload;
    procedure AddTag(const TagName: String; const Value: TDPoint); overload;
    procedure AddTagUInt(const TagName: String; Value: Cardinal);
    procedure AddTagColor(const TagName: String; Value: Cardinal);

    procedure AddAttribute(const Name, Value: String); overload;
    procedure AddAttribute(const Name: String; Value: Integer); overload;
    procedure AddAttribute(const Name: String; Value: Double); overload;
    procedure AddAttribute(const Name: String; const Value: TDPoint); overload;
    procedure AddAttributeUInt(const Name: String; Value: Cardinal);
    procedure AddAttributeColor(const Name: String; Value: Cardinal);

    procedure AddChildData(const Value: String); overload;
    procedure AddChildData(Value: Integer); overload;
    procedure AddChildData(Value: Double); overload;
    procedure AddChildData(const Value: TDPoint); overload;
    procedure AddChildDataUInt(Value: Cardinal);
    procedure AddChildDataColor(Value: Cardinal);

    procedure AddChildDataUUEncode(Data: PByte; Size: Integer);

    property LineCounter: Integer read FLineCounter;
  end;

implementation

const
  CRLF = #13#10;

{ ===========================================================================
  TXMLWriter.Create  (constructor)
  Parameters:
    AOutput: TStream - the stream to write to; not owned
  Notes:
    Creates a writer that sends XML to a stream; tags are tracked so closing and indentation
    come out as in TinyCAD.
  =========================================================================== }
constructor TXMLWriter.Create(AOutput: TStream);
begin
  inherited Create;
  FOutput := AOutput;
  FTags := TStringList.Create;
  FChildData := False;
  FNestingLevel := -1;
  FNeedsNewline := False;
  FNeedsTabs := False;
  FLineCounter := 1;
  SendString('<?xml version="1.0" encoding="UTF-8"?>' + CRLF);
end;

{ ===========================================================================
  TXMLWriter.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the tag stack. The output stream is not closed.
  =========================================================================== }
destructor TXMLWriter.Destroy;
begin
  FTags.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TXMLWriter.SendString  (procedure)
  Parameters:
    const S: String - the text
  Notes:
    Writes text to the output and counts the lines written (used in error messages).
  =========================================================================== }
procedure TXMLWriter.SendString(const S: String);
var
  i: Integer;
begin
  if S = '' then
    Exit;
  FOutput.WriteBuffer(S[1], Length(S));
  for i := 1 to Length(S) do
    if S[i] = #10 then
      Inc(FLineCounter);
end;

{ ===========================================================================
  TXMLWriter.Escape  (function)
  Parameters:
    const S: String - the text
  Returns:
    String - the escaped text
  Notes:
    Escapes text for XML (& < > and quotes) so it can go in an attribute or element.
  =========================================================================== }
class function TXMLWriter.Escape(const S: String): String;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    case S[i] of
      '<':  Result := Result + '&lt;';
      '>':  Result := Result + '&gt;';
      '&':  Result := Result + '&amp;';
      '''': Result := Result + '&#039;';
      '"':  Result := Result + '&quot;';
    else
      Result := Result + S[i];
    end;
end;

{ ===========================================================================
  TXMLWriter.AddComment  (procedure)
  Parameters:
    const Comment: String - the comment text
  Notes:
    Writes an XML comment on its own line.
  =========================================================================== }
procedure TXMLWriter.AddComment(const Comment: String);
begin
  SendString(CRLF + '<!--');
  SendString(Comment);
  SendString('-->' + CRLF);
end;

{ ===========================================================================
  TXMLWriter.CloseOpenTag  (procedure)
  Parameters:  none
  Notes:
    Finishes the start tag that is still open by writing ">".
  =========================================================================== }
procedure TXMLWriter.CloseOpenTag;
begin
  SendString('>');
end;

{ ===========================================================================
  TXMLWriter.AddTag  (procedure)
  Parameters:
    const TagName: String - the element name
  Notes:
    Starts an element: closes the previous start tag if needed, indents, and writes "<name";
    attributes may follow until content is added or the tag is closed.
  =========================================================================== }
procedure TXMLWriter.AddTag(const TagName: String);
var
  i: Integer;
begin
  // Do we need to close the previous tag?
  if (not FChildData) and (FTags.Count <> 0) then
    CloseOpenTag;

  FTags.Insert(0, TagName);
  Inc(FNestingLevel);
  if FNeedsNewline then
    SendString(CRLF);
  FNeedsNewline := True;
  FNeedsTabs := False;

  for i := FNestingLevel downto 1 do
    SendString(#9);

  SendString('<');
  SendString(TagName);
  FChildData := False;
end;

{ ===========================================================================
  TXMLWriter.CloseTag  (procedure)
  Parameters:  none
  Notes:
    Ends the innermost open element, as "/>" when it has no content or with a closing tag
    otherwise.
  =========================================================================== }
procedure TXMLWriter.CloseTag;
var
  i: Integer;
begin
  if FNeedsTabs then
    for i := FNestingLevel downto 1 do
      SendString(#9);

  if FChildData then
    SendString('</' + FTags[0] + '>' + CRLF)
  else
    SendString('/>' + CRLF);

  FTags.Delete(0);
  FChildData := FTags.Count <> 0;
  Dec(FNestingLevel);
  FNeedsNewline := False;
  FNeedsTabs := True;
end;

{ ===========================================================================
  TXMLWriter.InternalAddTag  (procedure)
  Parameters:
    const TagName: String - element name
    const Data: String - already formatted text content
  Notes:
    Writes a complete element with text content in one step (open, content, close).
  =========================================================================== }
procedure TXMLWriter.InternalAddTag(const TagName, Data: String);
begin
  AddTag(TagName);
  InternalAddChildData(Data);
  CloseTag;
end;

{ ===========================================================================
  TXMLWriter.InternalAddAttribute  (procedure)
  Parameters:
    const Name: String - attribute name
    const Value: String - already formatted value (escaped here)
  Notes:
    Adds an attribute to the open start tag; an error if the tag already has content or none is
    open.
  =========================================================================== }
procedure TXMLWriter.InternalAddAttribute(const Name, Value: String);
begin
  if FChildData then
    raise EXMLException.CreateXML(ERR_XML_HAVE_CHILD_DATA, FLineCounter);
  if FTags.Count = 0 then
    raise EXMLException.CreateXML(ERR_XML_NO_TAG, FLineCounter);
  SendString(' ' + Name + '=''' + Value + '''');
end;

{ ===========================================================================
  TXMLWriter.InternalAddChildData  (procedure)
  Parameters:
    const Data: String - already formatted text
  Notes:
    Adds text content to the open element (closing its start tag first); an error if no element
    is open.
  =========================================================================== }
procedure TXMLWriter.InternalAddChildData(const Data: String);
begin
  if FTags.Count = 0 then
    raise EXMLException.CreateXML(ERR_XML_NO_TAG, FLineCounter);
  if not FChildData then
    CloseOpenTag;
  FChildData := True;
  SendString(Data);
end;

{ ---- typed front ends: formats match XMLWriter::makeString ---- }

{ ===========================================================================
  TXMLWriter.AddTag  (procedure)
  Parameters:
    const TagName: String - element name
    const Value: String - the text
  Notes:
    Writes a complete element whose text content is a string.
  =========================================================================== }
procedure TXMLWriter.AddTag(const TagName, Value: String);
begin InternalAddTag(TagName, Escape(Value)); end;

{ ===========================================================================
  TXMLWriter.AddTag  (procedure)
  Parameters:
    const TagName: String - element name
    Value: Integer - the number
  Notes:
    Writes a complete element whose content is an integer.
  =========================================================================== }
procedure TXMLWriter.AddTag(const TagName: String; Value: Integer);
begin InternalAddTag(TagName, IntToStr(Value)); end;

{ ===========================================================================
  TXMLWriter.AddTag  (procedure)
  Parameters:
    const TagName: String - element name
    Value: Double - the number
  Notes:
    Writes a complete element whose content is a number formatted like C "%.5f".
  =========================================================================== }
procedure TXMLWriter.AddTag(const TagName: String; Value: Double);
begin InternalAddTag(TagName, FormatFixed5(Value)); end;

{ ===========================================================================
  TXMLWriter.AddTag  (procedure)
  Parameters:
    const TagName: String - element name
    const Value: TDPoint - the point in internal units
  Notes:
    Writes a complete element whose content is a point as "x,y" in millimetres.
  =========================================================================== }
procedure TXMLWriter.AddTag(const TagName: String; const Value: TDPoint);
begin InternalAddTag(TagName, FormatPoint(Value)); end;

{ ===========================================================================
  TXMLWriter.AddTagUInt  (procedure)
  Parameters:
    const TagName: String - element name
    Value: Cardinal - the number
  Notes:
    Writes a complete element whose content is an unsigned integer.
  =========================================================================== }
procedure TXMLWriter.AddTagUInt(const TagName: String; Value: Cardinal);
begin InternalAddTag(TagName, IntToStr(Int64(Value))); end;

{ ===========================================================================
  TXMLWriter.AddTagColor  (procedure)
  Parameters:
    const TagName: String - element name
    Value: Cardinal - the color
  Notes:
    Writes a complete element whose content is a color as hexadecimal.
  =========================================================================== }
procedure TXMLWriter.AddTagColor(const TagName: String; Value: Cardinal);
begin InternalAddTag(TagName, IntToHex(Int64(Value), 6)); end;

{ ===========================================================================
  TXMLWriter.AddAttribute  (procedure)
  Parameters:
    const Name: String - attribute name
    const Value: String - the text
  Notes:
    Adds a text attribute to the open element.
  =========================================================================== }
procedure TXMLWriter.AddAttribute(const Name, Value: String);
begin InternalAddAttribute(Name, Escape(Value)); end;

{ ===========================================================================
  TXMLWriter.AddAttribute  (procedure)
  Parameters:
    const Name: String - attribute name
    Value: Integer - the number
  Notes:
    Adds an integer attribute to the open element.
  =========================================================================== }
procedure TXMLWriter.AddAttribute(const Name: String; Value: Integer);
begin InternalAddAttribute(Name, IntToStr(Value)); end;

{ ===========================================================================
  TXMLWriter.AddAttribute  (procedure)
  Parameters:
    const Name: String - attribute name
    Value: Double - the number
  Notes:
    Adds a number attribute (C "%.5f" formatting) to the open element.
  =========================================================================== }
procedure TXMLWriter.AddAttribute(const Name: String; Value: Double);
begin InternalAddAttribute(Name, FormatFixed5(Value)); end;

{ ===========================================================================
  TXMLWriter.AddAttribute  (procedure)
  Parameters:
    const Name: String - attribute name
    const Value: TDPoint - the point in internal units
  Notes:
    Adds a point attribute written "x,y" in millimetres to the open element.
  =========================================================================== }
procedure TXMLWriter.AddAttribute(const Name: String; const Value: TDPoint);
begin InternalAddAttribute(Name, FormatPoint(Value)); end;

{ ===========================================================================
  TXMLWriter.AddAttributeUInt  (procedure)
  Parameters:
    const Name: String - attribute name
    Value: Cardinal - the number
  Notes:
    Adds an unsigned integer attribute to the open element.
  =========================================================================== }
procedure TXMLWriter.AddAttributeUInt(const Name: String; Value: Cardinal);
begin InternalAddAttribute(Name, IntToStr(Int64(Value))); end;

{ ===========================================================================
  TXMLWriter.AddAttributeColor  (procedure)
  Parameters:
    const Name: String - attribute name
    Value: Cardinal - the color
  Notes:
    Adds a color attribute (hexadecimal) to the open element.
  =========================================================================== }
procedure TXMLWriter.AddAttributeColor(const Name: String; Value: Cardinal);
begin InternalAddAttribute(Name, IntToHex(Int64(Value), 6)); end;

{ ===========================================================================
  TXMLWriter.AddChildData  (procedure)
  Parameters:
    const Value: String - the text
  Notes:
    Adds text content to the open element (escaped).
  =========================================================================== }
procedure TXMLWriter.AddChildData(const Value: String);
begin InternalAddChildData(Escape(Value)); end;

{ ===========================================================================
  TXMLWriter.AddChildData  (procedure)
  Parameters:
    Value: Integer - the number
  Notes:
    Adds an integer as the open element's content.
  =========================================================================== }
procedure TXMLWriter.AddChildData(Value: Integer);
begin InternalAddChildData(IntToStr(Value)); end;

{ ===========================================================================
  TXMLWriter.AddChildData  (procedure)
  Parameters:
    Value: Double - the number
  Notes:
    Adds a number (C "%.5f") as the open element's content.
  =========================================================================== }
procedure TXMLWriter.AddChildData(Value: Double);
begin InternalAddChildData(FormatFixed5(Value)); end;

{ ===========================================================================
  TXMLWriter.AddChildData  (procedure)
  Parameters:
    const Value: TDPoint - the point in internal units
  Notes:
    Adds a point "x,y" in millimetres as the open element's content.
  =========================================================================== }
procedure TXMLWriter.AddChildData(const Value: TDPoint);
begin InternalAddChildData(FormatPoint(Value)); end;

{ ===========================================================================
  TXMLWriter.AddChildDataUInt  (procedure)
  Parameters:
    Value: Cardinal - the number
  Notes:
    Adds an unsigned integer as the open element's content.
  =========================================================================== }
procedure TXMLWriter.AddChildDataUInt(Value: Cardinal);
begin InternalAddChildData(IntToStr(Int64(Value))); end;

{ ===========================================================================
  TXMLWriter.AddChildDataColor  (procedure)
  Parameters:
    Value: Cardinal - the color
  Notes:
    Adds a color (hexadecimal) as the open element's content.
  =========================================================================== }
procedure TXMLWriter.AddChildDataColor(Value: Cardinal);
begin InternalAddChildData(IntToHex(Int64(Value), 6)); end;

{ ===========================================================================
  TXMLWriter.AddChildDataUUEncode  (procedure)
  Parameters:
    Data: PByte - pointer to the bytes
    Size: Integer - number of bytes
  Notes:
    Adds binary data as UU-encoded text: the size, then lines of up to 45 bytes each, as TinyCAD
    writes symbol blobs.
  =========================================================================== }
procedure TXMLWriter.AddChildDataUUEncode(Data: PByte; Size: Integer);
var
  i, LineSize: Integer;
begin
  if FTags.Count = 0 then
    raise EXMLException.CreateXML(ERR_XML_NO_TAG, FLineCounter);

  if not FChildData then
    CloseOpenTag;
  FChildData := True;

  AddTag('UUENCODE');
  AddAttributeUInt('size', Cardinal(Size));
  CloseOpenTag;
  FChildData := True;
  SendString(CRLF);

  i := 0;
  while i < Size do
  begin
    LineSize := Size - i;
    if LineSize > 45 then
      LineSize := 45;
    // the C++ code terminates each uuencoded line with a bare LF
    SendString(Escape(UUEncodeLine(Data + i, LineSize)) + #10);
    Inc(i, LineSize);
  end;

  CloseTag;
end;

end.
