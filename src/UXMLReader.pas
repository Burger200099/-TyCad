{ Port of XMLReader.h/.cpp (CXMLReader).

  The C++ class was a hand-written streaming parser (plus xml_parse_tag.cpp, 496 lines).
  Here it is a thin cursor over FPC's standard DOM parser, which makes xml_parse_tag.*,
  libiconv and the line-by-line charset decoding unnecessary (the parser honours the
  encoding declared in <?xml ... ?>).  The calling convention is unchanged, so code that
  walks a file with nextTag / intoTag / outofTag ports one-to-one:

      while R.NextTag(Name) do
        if Name = 'TinyCAD' then begin R.IntoTag; ...; R.OutOfTag; end;

  Known behavioural differences:
  - The DOM parser is strict about well-formedness; the C++ parser was more forgiving.
    Files that rely on that will raise EXMLException with the parser's line number.
  - The whole document is loaded in memory before reading starts.
  - Text returned by GetChildData is the concatenated text of the tag and everything
    inside it, as in the C++ version. }
unit UXMLReader;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DOM, XMLRead, UDPoint, UXMLException, UXMLCodec;

type
  TXMLReader = class
  private
    type
      TFrame = record
        Parent: TDOMNode;  // node whose children this level iterates
        Cursor: TDOMNode;  // last element returned by NextTag (nil before the first)
      end;
  private
    FDoc: TXMLDocument;
    FFrames: array of TFrame;
    function Top: Integer;
    function CurrentElement: TDOMElement;
    function RawAttr(const Name: String; out Value: String): Boolean;
    function RawChildData: String;
  public
    constructor Create(AInput: TStream);
    destructor Destroy; override;

    { Advance to the next peer tag at this level. False when there are no more. }
    function NextTag(out Name: String): Boolean;
    { Move inside the current tag; NextTag then returns its children. }
    procedure IntoTag;
    { Move back up; NextTag then continues after the tag we were inside. }
    procedure OutOfTag;

    { Attributes of the current tag. Return False when absent (target left untouched). }
    function GetAttribute(const Name: String; var V: String): Boolean; overload;
    function GetAttribute(const Name: String; var V: Integer): Boolean; overload;
    function GetAttribute(const Name: String; var V: Double): Boolean; overload;
    function GetAttribute(const Name: String; var V: Boolean): Boolean; overload;
    function GetAttribute(const Name: String; var V: TDPoint): Boolean; overload;
    function GetAttributeUInt(const Name: String; var V: Cardinal): Boolean;
    function GetAttributeColor(const Name: String; var V: Cardinal): Boolean; // hex, as COLORREF

    { Text content of the current tag. }
    procedure GetChildData(var V: String); overload;
    procedure GetChildData(var V: Integer); overload;
    procedure GetChildData(var V: Double); overload;
    procedure GetChildData(var V: Boolean); overload;
    procedure GetChildData(var V: TDPoint); overload;
    procedure GetChildDataColor(var V: Cardinal);

    { Decode a <UUENCODE size='n'> tag (the current tag) into a byte array. }
    procedure GetChildDataUUDecode(out Data: TBytes);
  end;

implementation


uses UStrings;

{ ===========================================================================
  TXMLReader.Create  (constructor)
  Parameters:
    AInput: TStream - the stream to read
  Notes:
    Parses an XML stream into a document and positions the reader on the first top-level
    element. Parse errors become EXMLException.
  =========================================================================== }
constructor TXMLReader.Create(AInput: TStream);
var
  Parser: TDOMParser;
  Src: TXMLInputSource;
begin
  inherited Create;
  Parser := TDOMParser.Create;
  try
    Parser.Options.PreserveWhitespace := True; // uuencoded data is whitespace-sensitive
    Src := TXMLInputSource.Create(AInput);
    try
      try
        Parser.Parse(Src, FDoc);
      except
        on E: EXMLReadError do
          raise EXMLException.CreateXML(E.Message, E.Line);
      end;
    finally
      Src.Free;
    end;
  finally
    Parser.Free;
  end;
  { Equivalent of the C++ constructor calling intoTag(): we start inside the document. }
  SetLength(FFrames, 1);
  FFrames[0].Parent := FDoc;
  FFrames[0].Cursor := nil;
end;

{ ===========================================================================
  TXMLReader.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the parsed document.
  =========================================================================== }
destructor TXMLReader.Destroy;
begin
  FDoc.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TXMLReader.Top  (function)
  Parameters:  none
  Returns:
    Integer - the frame index
  Notes:
    Index of the innermost nesting frame.
  =========================================================================== }
function TXMLReader.Top: Integer;
begin
  Result := High(FFrames);
end;

{ ===========================================================================
  TXMLReader.CurrentElement  (function)
  Parameters:  none
  Returns:
    TDOMElement - the element
  Notes:
    The element the reader is on; raises an error if it is not on an element.
  =========================================================================== }
function TXMLReader.CurrentElement: TDOMElement;
var
  C: TDOMNode;
begin
  C := FFrames[Top].Cursor;
  if (C = nil) or (C.NodeType <> ELEMENT_NODE) then
    raise EXMLException.CreateXML(rsXMLReaderThereIsNo, 0);
  Result := TDOMElement(C);
end;

{ ===========================================================================
  TXMLReader.NextTag  (function)
  Parameters:
    out Name: String - set to the tag name
  Returns:
    Boolean - False when there are no more elements at this level
  Notes:
    Moves to the next element at the current level (the first one on the first call after
    IntoTag) and gives its name, like CXMLReader::nextTag.
  =========================================================================== }
function TXMLReader.NextTag(out Name: String): Boolean;
var
  N: TDOMNode;
begin
  Name := '';
  Result := False;
  with FFrames[Top] do
  begin
    if Cursor = nil then
      N := Parent.FirstChild
    else
      N := Cursor.NextSibling;
    while (N <> nil) and (N.NodeType <> ELEMENT_NODE) do
      N := N.NextSibling;
    if N = nil then
      Exit;
    Cursor := N;
    Name := UTF8Encode(N.NodeName);
    Result := True;
  end;
end;

{ ===========================================================================
  TXMLReader.IntoTag  (procedure)
  Parameters:  none
  Notes:
    Steps inside the current element so NextTag walks its children.
  =========================================================================== }
procedure TXMLReader.IntoTag;
var
  E: TDOMElement;
begin
  E := CurrentElement;
  SetLength(FFrames, Length(FFrames) + 1);
  FFrames[Top].Parent := E;
  FFrames[Top].Cursor := nil;
end;

{ ===========================================================================
  TXMLReader.OutOfTag  (procedure)
  Parameters:  none
  Notes:
    Steps back out to the parent level; an error if already at the top.
  =========================================================================== }
procedure TXMLReader.OutOfTag;
begin
  if Length(FFrames) <= 1 then
    raise EXMLException.CreateXML(ERR_XML_WRONG_CLOSE, 0);
  SetLength(FFrames, Length(FFrames) - 1);
end;

{ ===========================================================================
  TXMLReader.RawAttr  (function)
  Parameters:
    const Name: String - attribute name
    out Value: String - set to its text
  Returns:
    Boolean - True if the attribute exists
  Notes:
    Looks up an attribute of the current element as text.
  =========================================================================== }
function TXMLReader.RawAttr(const Name: String; out Value: String): Boolean;
var
  E: TDOMElement;
  WName: UnicodeString;
begin
  E := CurrentElement;
  WName := UTF8Decode(Name);
  Result := E.hasAttribute(WName);
  if Result then
    Value := UTF8Encode(E.getAttribute(WName))
  else
    Value := '';
end;

{ ===========================================================================
  TXMLReader.RawChildData  (function)
  Parameters:  none
  Returns:
    String - the text
  Notes:
    The text content of the current element.
  =========================================================================== }
function TXMLReader.RawChildData: String;
begin
  Result := UTF8Encode(CurrentElement.TextContent);
end;

{ ===========================================================================
  TXMLReader.GetAttribute  (function)
  Parameters:
    const Name: String - attribute name
    var V: String - receives the text
  Returns:
    Boolean - True if the attribute exists
  Notes:
    Reads a text attribute; V is unchanged when the attribute is missing.
  =========================================================================== }
function TXMLReader.GetAttribute(const Name: String; var V: String): Boolean;
var R: String;
begin
  Result := RawAttr(Name, R);
  if Result then
    V := R;
end;

{ ===========================================================================
  TXMLReader.GetAttribute  (function)
  Parameters:
    const Name: String - attribute name
    var V: Integer - receives the number
  Returns:
    Boolean - True if the attribute exists
  Notes:
    Reads an integer attribute (C atoi rules); V is unchanged when it is missing.
  =========================================================================== }
function TXMLReader.GetAttribute(const Name: String; var V: Integer): Boolean;
var R: String;
begin
  Result := RawAttr(Name, R);
  if Result then
    V := CAtoI(R);
end;

{ ===========================================================================
  TXMLReader.GetAttribute  (function)
  Parameters:
    const Name: String - attribute name
    var V: Double - receives the number
  Returns:
    Boolean - True if the attribute exists
  Notes:
    Reads a number attribute (C atof rules); V is unchanged when it is missing.
  =========================================================================== }
function TXMLReader.GetAttribute(const Name: String; var V: Double): Boolean;
var R: String;
begin
  Result := RawAttr(Name, R);
  if Result then
    V := CAtoF(R);
end;

{ ===========================================================================
  TXMLReader.GetAttribute  (function)
  Parameters:
    const Name: String - attribute name
    var V: Boolean - receives the value
  Returns:
    Boolean - True if the attribute exists
  Notes:
    Reads a Boolean attribute stored as 0 or 1; V is unchanged when it is missing.
  =========================================================================== }
function TXMLReader.GetAttribute(const Name: String; var V: Boolean): Boolean;
var R: String;
begin
  Result := RawAttr(Name, R);
  if Result then
    V := CAtoI(R) <> 0;
end;

{ ===========================================================================
  TXMLReader.GetAttribute  (function)
  Parameters:
    const Name: String - attribute name
    var V: TDPoint - receives the point
  Returns:
    Boolean - True if the attribute exists
  Notes:
    Reads a point attribute written as "x,y" in millimetres, converting to internal units; V is
    unchanged when it is missing.
  =========================================================================== }
function TXMLReader.GetAttribute(const Name: String; var V: TDPoint): Boolean;
var R: String;
begin
  Result := RawAttr(Name, R);
  if Result then
    CScanPoint(R, V);
end;

{ ===========================================================================
  TXMLReader.GetAttributeUInt  (function)
  Parameters:
    const Name: String - attribute name
    var V: Cardinal - receives the value
  Returns:
    Boolean - True if the attribute exists
  Notes:
    Reads an unsigned integer attribute.
  =========================================================================== }
function TXMLReader.GetAttributeUInt(const Name: String; var V: Cardinal): Boolean;
var R: String;
begin
  Result := RawAttr(Name, R);
  if Result then
    V := Cardinal(CAtoI(R)); // scanf %u; values above 2^31 are not used in .dsn files
end;

{ ===========================================================================
  TXMLReader.GetAttributeColor  (function)
  Parameters:
    const Name: String - attribute name
    var V: Cardinal - receives the color
  Returns:
    Boolean - True if the attribute exists
  Notes:
    Reads a color attribute written as hexadecimal.
  =========================================================================== }
function TXMLReader.GetAttributeColor(const Name: String; var V: Cardinal): Boolean;
var R: String;
begin
  Result := RawAttr(Name, R);
  if Result then
    V := CHexToInt(R);
end;

{ ===========================================================================
  TXMLReader.GetChildData  (procedure)
  Parameters:
    var V: String - receives the text
  Notes:
    Reads the current element's text content into V.
  =========================================================================== }
procedure TXMLReader.GetChildData(var V: String);
begin V := RawChildData; end;

{ ===========================================================================
  TXMLReader.GetChildData  (procedure)
  Parameters:
    var V: Integer - receives the number
  Notes:
    Reads the current element's text content as an integer.
  =========================================================================== }
procedure TXMLReader.GetChildData(var V: Integer);
begin V := CAtoI(RawChildData); end;

{ ===========================================================================
  TXMLReader.GetChildData  (procedure)
  Parameters:
    var V: Double - receives the number
  Notes:
    Reads the current element's text content as a number.
  =========================================================================== }
procedure TXMLReader.GetChildData(var V: Double);
begin V := CAtoF(RawChildData); end;

{ ===========================================================================
  TXMLReader.GetChildData  (procedure)
  Parameters:
    var V: Boolean - receives the value
  Notes:
    Reads the current element's text content as a Boolean (0 or 1).
  =========================================================================== }
procedure TXMLReader.GetChildData(var V: Boolean);
begin V := CAtoI(RawChildData) <> 0; end;

{ ===========================================================================
  TXMLReader.GetChildData  (procedure)
  Parameters:
    var V: TDPoint - receives the point
  Notes:
    Reads the current element's text content as an "x,y" point in millimetres, converting to
    internal units.
  =========================================================================== }
procedure TXMLReader.GetChildData(var V: TDPoint);
begin CScanPoint(RawChildData, V); end;

{ ===========================================================================
  TXMLReader.GetChildDataColor  (procedure)
  Parameters:
    var V: Cardinal - receives the color
  Notes:
    Reads the current element's text content as a hexadecimal color.
  =========================================================================== }
procedure TXMLReader.GetChildDataColor(var V: Cardinal);
begin V := CHexToInt(RawChildData); end;

{ ===========================================================================
  TXMLReader.GetChildDataUUDecode  (procedure)
  Parameters:
    out Data: TBytes - receives the decoded bytes
  Notes:
    Reads UU-encoded binary data from the element: a size line followed by encoded lines, as
    used for the symbol blobs inside .dsn files.
  =========================================================================== }
procedure TXMLReader.GetChildDataUUDecode(out Data: TBytes);
var
  Size: Cardinal;
  Dec: TUUDecoder;
  Text: String;
  i: Integer;
begin
  Size := 0;
  GetAttributeUInt('size', Size);
  Dec := TUUDecoder.Create(Integer(Size));
  try
    Text := RawChildData;
    for i := 1 to Length(Text) do
      Dec.Feed(Ord(Text[i]));
    Data := Dec.Data;
  finally
    Dec.Free;
  end;
end;

end.
