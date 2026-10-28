{ Port of XMLException.h/.cpp and the ERR_XML_* messages in xml_parse_tag.h. }
unit UXMLException;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

const
  ERR_XML_EXPECTING_NAME   = 'XML parse error: Expecting tag name';
  ERR_XML_EXPECTING_ATTR   = 'XML parse error: Expecting attribute name or end of tag';
  ERR_XML_EXPECTING_EQUALS = 'XML parse error: Expecting =';
  ERR_XML_EXPECTING_VALUE  = 'XML parse error: Expecting attribute value';
  ERR_XML_EXPECTING_END    = 'XML parse error: Expecting end of XML tag';
  ERR_XML_WRONG_CLOSE      = 'XML parse error: The closing XML tag does not match the opening tag';
  ERR_XML_HAVE_CHILD_DATA  = 'XML output error: Cannot add attributes after child data';
  ERR_XML_NO_TAG           = 'XML output error: There is no open tag';

type
  EXMLException = class(Exception)
  private
    FLine: Integer;
  public
    constructor CreateXML(const AName: String; ALine: Integer);
    property Line: Integer read FLine;
  end;

implementation


uses UStrings;

{ ===========================================================================
  EXMLException.CreateXML  (constructor)
  Parameters:
    const AName: String - the message
    ALine: Integer - the line number where it was detected
  Notes:
    Builds the error with the same wording as TinyCAD's CXMLException: the message, then "Error
    first detected on line #n".
  =========================================================================== }
constructor EXMLException.CreateXML(const AName: String; ALine: Integer);
begin
  { Same text as CXMLException: "<msg>.\nError first detected on line #<n>.\n" }
  inherited Create(Format(rsErrorFirstDetectedOnLine, [AName, ALine]));
  FLine := ALine;
end;

end.
