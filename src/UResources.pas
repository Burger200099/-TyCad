// SPDX-License-Identifier: LGPL-2.1-or-later
{ Port of DocResource.*, ListOfFonts.*, ListOfStyles.*, ListOfFillStyles.* and UserColor.*

  Fonts, line styles and fill styles are kept in per-sheet tables. Objects refer to them by
  number. On load, numbers in the file are remapped ("merged") onto the table, identical
  entries are shared, and on save only entries in use are written, renumbered. The merge
  algorithm below is a line-for-line port of CDocResource::Add / ConvertOld so that
  numbering comes out exactly as in the C++ program. }
unit UResources;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs, UDrawTypes, UXMLReader, UXMLWriter;

type
  { ---- generic resource table ---- }
  TResourceItem = class
  private
    FNumber: Integer;
    FMergeNumber: Integer;
    FInUse: Boolean;
  public
    constructor Create; virtual;
    { Same content? (used to share identical entries) }
    function Compare(Other: TResourceItem): Boolean; virtual; abstract;
    { Write / read the item's content (inside the already-open outer tag) }
    procedure WriteItem(W: TXMLWriter); virtual; abstract;
    procedure ReadItem(R: TXMLReader); virtual; abstract;
    property Number: Integer read FNumber;
    property MergeNumber: Integer read FMergeNumber write FMergeNumber;
    property InUse: Boolean read FInUse write FInUse;
  end;

  TResourceList = class
  private
    FItems: TObjectList; // owns the items; item 0 is the default ("head") entry
  protected
    function CreateItem: TResourceItem; virtual; abstract;
  public
    constructor Create(AHead: TResourceItem);
    destructor Destroy; override;
    function Add(NewItem: TResourceItem; NewMerge: Integer = -1): Integer;
    function ConvertOld(OldId: Integer): Integer;
    function Get(Id: Integer): TResourceItem;
    procedure Tag(Id: Integer);
    procedure UnTag;
    procedure ResetMerge;
    function Count: Integer;
    function Item(Index: Integer): TResourceItem;
    procedure SaveXML(const TagName: String; W: TXMLWriter);
    { Read one <FONT>/<STYLE>/... tag (reader positioned on it) and merge it in }
    procedure LoadItemXML(R: TXMLReader); virtual;
  end;

  { ---- fonts ---- }
  TFontResource = class(TResourceItem)
  public
    Height, Width, Weight, Italic, Underline, StrikeOut, CharSet: Integer;
    FaceName: String;
    constructor Create; override;
    constructor CreateSized(AHeight: Integer; AItalic: Boolean);
    function Compare(Other: TResourceItem): Boolean; override;
    procedure WriteItem(W: TXMLWriter); override;
    procedure ReadItem(R: TXMLReader); override;
  end;

  { ---- line styles ---- }
  TLineStyleResource = class(TResourceItem)
  public
    Style, Thickness: Integer;
    Color: Cardinal;
    constructor Create; override;
    constructor CreateWith(AStyle, AThickness: Integer; AColor: Cardinal);
    function Compare(Other: TResourceItem): Boolean; override;
    procedure WriteItem(W: TXMLWriter); override;
    procedure ReadItem(R: TXMLReader); override;
  end;

  { ---- fill styles ---- }
  TFillStyleResource = class(TResourceItem)
  public
    Index: Integer;
    Color: Cardinal;
    constructor Create; override;
    constructor CreateWith(AIndex: Integer; AColor: Cardinal);
    function Compare(Other: TResourceItem): Boolean; override;
    procedure WriteItem(W: TXMLWriter); override;
    procedure ReadItem(R: TXMLReader); override;
  end;

  TFontList = class(TResourceList)
  protected
    function CreateItem: TResourceItem; override;
  end;
  TLineStyleList = class(TResourceList)
  protected
    function CreateItem: TResourceItem; override;
  end;
  TFillStyleList = class(TResourceList)
  protected
    function CreateItem: TResourceItem; override;
  end;

  { ---- pictures ---- }
  { A picture kept in the design: the bytes of the picture file (PNG or JPEG; a Windows metafile is only carried along), written to
    the file uuencoded as TinyCAD does. Identical pictures are kept once. Cache belongs to the layer that draws: the decoded picture,
    thrown away with the resource. }
  TImageResource = class(TResourceItem)
  public
    ImgType: String;
    Data: TBytes;
    Cache: TObject;
    Oriented: array[0..7] of TObject;      // the picture drawn in each of the eight orientations (turned and flipped), made when first wanted (see UOrient)
    destructor Destroy; override;
    function Compare(Other: TResourceItem): Boolean; override;
    procedure WriteItem(W: TXMLWriter); override;
    procedure ReadItem(R: TXMLReader); override;
  end;
  TImageResourceList = class(TResourceList)
  protected
    function CreateItem: TResourceItem; override;
  end;

  { ---- user colors (UserColor.*) ---- }
  TUserColors = class
  private
    FColor: array[UC_WIRE..UC_NOTETEXT_TEXT] of Cardinal;
  public
    constructor Create;
    procedure Init;  // factory defaults
    function Get(Id: Integer): Cardinal;
    procedure SetColor(Id: Integer; C: Cardinal);
    { If TagName is one of the COLOR_* tags, read it and return True }
    function ReadXML(R: TXMLReader; const TagName: String): Boolean;
    procedure WriteXML(W: TXMLWriter);
    class function TagNameOf(Id: Integer): String;
  end;

var
  { The colors the user has chosen to start new designs with (the ones that differ from the factory colors), -1 where there is none.
    A new set of colors takes these on top of the factory colors, as TinyCAD's CUserColor reads the registry when it is made; a set
    that is read from a file starts from the factory colors and takes what the file says. }
  UserColorOverride: array[UC_WIRE..UC_NOTETEXT_TEXT] of Int64;

implementation

{ ---- TResourceItem ---- }

{ ===========================================================================
  TResourceItem.Create  (constructor)
  Parameters:  none
  Notes:
    Creates a resource entry that is not yet numbered, not in use, and not merged.
  =========================================================================== }
constructor TResourceItem.Create;
begin
  inherited Create;
  FNumber := 0;
  FMergeNumber := 0; // as CDocResource::CDocResource
  FInUse := False;
end;

{ ---- TResourceList ---- }

{ ===========================================================================
  TResourceList.Create  (constructor)
  Parameters:
    AHead: TResourceItem - the default entry, always present
  Notes:
    Creates a list of resources (fonts, line styles or fill styles) whose first entry is the
    default one.
  =========================================================================== }
constructor TResourceList.Create(AHead: TResourceItem);
begin
  inherited Create;
  FItems := TObjectList.Create(True);
  FItems.Add(AHead);
end;

{ ===========================================================================
  TResourceList.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the list and its entries.
  =========================================================================== }
destructor TResourceList.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TResourceList.Count  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    Number of entries.
  =========================================================================== }
function TResourceList.Count: Integer;
begin
  Result := FItems.Count;
end;

{ ===========================================================================
  TResourceList.Item  (function)
  Parameters:
    Index: Integer - position (0 is the default)
  Returns:
    TResourceItem - the entry
  Notes:
    The entry at a position.
  =========================================================================== }
function TResourceList.Item(Index: Integer): TResourceItem;
begin
  Result := TResourceItem(FItems[Index]);
end;

{ ===========================================================================
  TResourceList.Add  (function)
  Parameters:
    NewItem: TResourceItem - the resource to add (the list takes it or frees it if a duplicate)
    NewMerge: Integer - merge number for resources loaded from a file, -1 for new ones
  Returns:
    Integer - the number of the entry that now represents it
  Notes:
    Adds a resource, reusing an equal entry that has not been merged yet (CDocResource::Add);
    otherwise appends it with the next free number.
  =========================================================================== }
function TResourceList.Add(NewItem: TResourceItem; NewMerge: Integer): Integer;
var
  i, NextNumber: Integer;
  P: TResourceItem;
begin
  { CDocResource::Add: find the first entry that has no merge number yet and equals
    the new one; otherwise append with the next free number. }
  NextNumber := 0;
  for i := 0 to FItems.Count - 1 do
  begin
    P := Item(i);
    if (P.MergeNumber = -1) and P.Compare(NewItem) then
    begin
      P.MergeNumber := NewMerge;
      NewItem.Free;
      Result := P.Number;
      Exit;
    end;
    if P.Number >= NextNumber then
      NextNumber := P.Number + 1;
  end;
  NewItem.FNumber := NextNumber;
  NewItem.FMergeNumber := NewMerge;
  FItems.Add(NewItem);
  Result := NextNumber;
end;

{ ===========================================================================
  TResourceList.ConvertOld  (function)
  Parameters:
    OldId: Integer - the number as written in the file
  Returns:
    Integer - the sheet's resource number
  Notes:
    Converts a number read from a file to this sheet's number for the same resource; unknown
    numbers give the default entry (0).
  =========================================================================== }
function TResourceList.ConvertOld(OldId: Integer): Integer;
var
  i: Integer;
begin
  Result := 0; // out of range -> default entry
  for i := 0 to FItems.Count - 1 do
    if Item(i).MergeNumber = OldId then
      Result := Item(i).Number; // last match wins, as in the C++ loop
end;

{ ===========================================================================
  TResourceList.Get  (function)
  Parameters:
    Id: Integer - resource number
  Returns:
    TResourceItem - the entry
  Notes:
    The entry with a given number, or the default entry if there is none.
  =========================================================================== }
function TResourceList.Get(Id: Integer): TResourceItem;
var
  i: Integer;
begin
  Result := Item(0);
  for i := 0 to FItems.Count - 1 do
    if Item(i).Number = Id then
      Result := Item(i);
end;

{ ===========================================================================
  TResourceList.Tag  (procedure)
  Parameters:
    Id: Integer - resource number
  Notes:
    Marks the entry with that number as in use so it is saved.
  =========================================================================== }
procedure TResourceList.Tag(Id: Integer);
var
  i: Integer;
begin
  for i := 0 to FItems.Count - 1 do
    if Item(i).Number = Id then
      Item(i).InUse := True;
end;

{ ===========================================================================
  TResourceList.UnTag  (procedure)
  Parameters:  none
  Notes:
    Marks every entry as not in use (done before tagging what an object uses, so unused ones are
    not saved).
  =========================================================================== }
procedure TResourceList.UnTag;
var
  i: Integer;
begin
  for i := 0 to FItems.Count - 1 do
    Item(i).InUse := False;
end;

{ ===========================================================================
  TResourceList.ResetMerge  (procedure)
  Parameters:  none
  Notes:
    Forgets which file entries have been matched, ready for loading another file.
  =========================================================================== }
procedure TResourceList.ResetMerge;
var
  i: Integer;
begin
  for i := 0 to FItems.Count - 1 do
    Item(i).MergeNumber := -1;
end;

{ ===========================================================================
  TResourceList.SaveXML  (procedure)
  Parameters:
    const TagName: String - the element name, e.g. FONT
    W: TXMLWriter - the XML writer
  Notes:
    Writes every in-use entry as an element named TagName, each with its number.
  =========================================================================== }
procedure TResourceList.SaveXML(const TagName: String; W: TXMLWriter);
var
  i: Integer;
begin
  for i := 0 to FItems.Count - 1 do
    if Item(i).InUse then
    begin
      W.AddTag(TagName);
      W.AddAttribute('id', Item(i).Number);
      Item(i).WriteItem(W);
      W.CloseTag;
    end;
end;

{ ===========================================================================
  TResourceList.LoadItemXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader on the entry
  Notes:
    Reads one saved entry and adds it to the list, remembering its file number so objects can
    refer to it.
  =========================================================================== }
procedure TResourceList.LoadItemXML(R: TXMLReader);
var
  NewItem: TResourceItem;
  FileId: Integer;
begin
  NewItem := CreateItem;
  FileId := 0;
  R.GetAttribute('id', FileId);
  NewItem.ReadItem(R);
  Add(NewItem, FileId);
end;

{ ---- fonts ---- }

{ ===========================================================================
  TFontResource.Create  (constructor)
  Parameters:  none
  Notes:
    Creates a font entry with the standard text height and default face.
  =========================================================================== }
constructor TFontResource.Create;
begin
  inherited Create;
  Height := TEXT_HEIGHT;
  Width := 0;
  Weight := 400;
  Italic := 0;
  Underline := 0;
  StrikeOut := 0;
  CharSet := 0; // ANSI_CHARSET
  FaceName := DEFAULT_FONT;
end;

{ ===========================================================================
  TFontResource.CreateSized  (constructor)
  Parameters:
    AHeight: Integer - height in design units
    AItalic: Boolean - True for italic
  Notes:
    Creates a font entry with a given height and optionally italic.
  =========================================================================== }
constructor TFontResource.CreateSized(AHeight: Integer; AItalic: Boolean);
begin
  Create;
  Height := AHeight;
  Italic := Ord(AItalic);
end;

{ ===========================================================================
  TFontResource.Compare  (function)
  Parameters:
    Other: TResourceItem - the entry to compare with
  Returns:
    Boolean - True if equal
  Notes:
    Whether another font entry is identical (height, width, weight, italic, underline, strike-
    out, character set, face name).
  =========================================================================== }
function TFontResource.Compare(Other: TResourceItem): Boolean;
var
  O: TFontResource;
begin
  O := Other as TFontResource;
  Result := (O.Height = Height) and (O.Width = Width) and (O.Weight = Weight) and
            (O.Italic = Italic) and (O.Underline = Underline) and (O.StrikeOut = StrikeOut) and
            (O.CharSet = CharSet) and (O.FaceName = FaceName);
end;

{ ===========================================================================
  TFontResource.WriteItem  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
  Notes:
    Writes the font's fields as child elements.
  =========================================================================== }
procedure TFontResource.WriteItem(W: TXMLWriter);
begin
  W.AddTag('HEIGHT', Height);
  W.AddTag('WIDTH', Width);
  W.AddTag('WEIGHT', Weight);
  W.AddTag('ITALIC', Italic);
  W.AddTag('UNDERLINE', Underline);
  W.AddTag('STRIKEOUT', StrikeOut);
  W.AddTag('CHARSET', CharSet);
  W.AddTag('FACENAME', FaceName);
end;

{ ===========================================================================
  TFontResource.ReadItem  (procedure)
  Parameters:
    R: TXMLReader - the XML reader on the entry
  Notes:
    Reads the font's fields from its child elements.
  =========================================================================== }
procedure TFontResource.ReadItem(R: TXMLReader);
var
  Name: String;
begin
  R.IntoTag;
  while R.NextTag(Name) do
  begin
    if Name = 'HEIGHT' then
      R.GetChildData(Height)
    else if Name = 'WIDTH' then
      R.GetChildData(Width)
    else if Name = 'WEIGHT' then
      R.GetChildData(Weight)
    else if Name = 'ITALIC' then
      R.GetChildData(Italic)
    else if Name = 'UNDERLINE' then
      R.GetChildData(Underline)
    else if Name = 'STRIKEOUT' then
      R.GetChildData(StrikeOut)
    else if Name = 'CHARSET' then
      R.GetChildData(CharSet)
    else if Name = 'FACENAME' then
      R.GetChildData(FaceName);
  end;
  R.OutOfTag;
end;

{ ---- line styles ---- }

{ ===========================================================================
  TLineStyleResource.Create  (constructor)
  Parameters:  none
  Notes:
    Creates a line style entry: solid, thickness 1, black.
  =========================================================================== }
constructor TLineStyleResource.Create;
begin
  inherited Create;
  Style := PS_SOLID;
  Thickness := 1;
  Color := cBLACK;
end;

{ ===========================================================================
  TLineStyleResource.CreateWith  (constructor)
  Parameters:
    AStyle: Integer - Windows pen style (0 solid ... 4 dash-dot-dot)
    AThickness: Integer - thickness in design units
    AColor: Cardinal - color
  Notes:
    Creates a line style entry with the given dash style, thickness and color.
  =========================================================================== }
constructor TLineStyleResource.CreateWith(AStyle, AThickness: Integer; AColor: Cardinal);
begin
  inherited Create;
  Style := AStyle;
  Thickness := AThickness;
  Color := AColor;
end;

{ ===========================================================================
  TLineStyleResource.Compare  (function)
  Parameters:
    Other: TResourceItem - the entry to compare with
  Returns:
    Boolean - True if equal
  Notes:
    Whether another line style is identical.
  =========================================================================== }
function TLineStyleResource.Compare(Other: TResourceItem): Boolean;
var
  O: TLineStyleResource;
begin
  O := Other as TLineStyleResource;
  Result := (O.Style = Style) and (O.Thickness = Thickness) and (O.Color = Color);
end;

{ ===========================================================================
  TLineStyleResource.WriteItem  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
  Notes:
    Writes style, thickness and color as child elements.
  =========================================================================== }
procedure TLineStyleResource.WriteItem(W: TXMLWriter);
begin
  W.AddTag('STYLE', Style);
  W.AddTagColor('COLOR', Color);
  W.AddTag('THICKNESS', Thickness);
end;

{ ===========================================================================
  TLineStyleResource.ReadItem  (procedure)
  Parameters:
    R: TXMLReader - the XML reader on the entry
  Notes:
    Reads style, thickness and color from child elements.
  =========================================================================== }
procedure TLineStyleResource.ReadItem(R: TXMLReader);
var
  Name: String;
begin
  R.IntoTag;
  while R.NextTag(Name) do
  begin
    if Name = 'STYLE' then
      R.GetChildData(Style)
    else if Name = 'COLOR' then
      R.GetChildDataColor(Color)
    else if Name = 'THICKNESS' then
      R.GetChildData(Thickness);
  end;
  R.OutOfTag;
end;

{ ---- fill styles ---- }

{ ===========================================================================
  TFillStyleResource.Create  (constructor)
  Parameters:  none
  Notes:
    Creates a fill entry with no fill (index -1).
  =========================================================================== }
constructor TFillStyleResource.Create;
begin
  inherited Create;
  Index := -1;
  Color := cBLACK;
end;

{ ===========================================================================
  TFillStyleResource.CreateWith  (constructor)
  Parameters:
    AIndex: Integer - -1 none, 0 solid, 1 and up the hatch patterns
    AColor: Cardinal - fill color
  Notes:
    Creates a fill entry with a hatch index and color.
  =========================================================================== }
constructor TFillStyleResource.CreateWith(AIndex: Integer; AColor: Cardinal);
begin
  inherited Create;
  Index := AIndex;
  Color := AColor;
end;

{ ===========================================================================
  TFillStyleResource.Compare  (function)
  Parameters:
    Other: TResourceItem - the entry to compare with
  Returns:
    Boolean - True if equal
  Notes:
    Whether another fill style is identical.
  =========================================================================== }
function TFillStyleResource.Compare(Other: TResourceItem): Boolean;
var
  O: TFillStyleResource;
begin
  O := Other as TFillStyleResource;
  Result := (O.Color = Color) and (O.Index = Index);
end;

{ ===========================================================================
  TFillStyleResource.WriteItem  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
  Notes:
    Writes index and color as child elements.
  =========================================================================== }
procedure TFillStyleResource.WriteItem(W: TXMLWriter);
begin
  W.AddTag('INDEX', Index);
  W.AddTagColor('COLOR', Color);
end;

{ ===========================================================================
  TFillStyleResource.ReadItem  (procedure)
  Parameters:
    R: TXMLReader - the XML reader on the entry
  Notes:
    Reads index and color from child elements.
  =========================================================================== }
procedure TFillStyleResource.ReadItem(R: TXMLReader);
var
  Name: String;
begin
  R.IntoTag;
  while R.NextTag(Name) do
  begin
    if Name = 'INDEX' then
      R.GetChildData(Index)
    else if Name = 'COLOR' then
      R.GetChildDataColor(Color);
  end;
  R.OutOfTag;
end;

{ ===========================================================================
  TFontList.CreateItem  (function)
  Parameters:  none
  Returns:
    TResourceItem - a new font resource
  Notes:
    Makes an empty font entry for the loader.
  =========================================================================== }
function TFontList.CreateItem: TResourceItem;
begin Result := TFontResource.Create; end;

{ ===========================================================================
  TLineStyleList.CreateItem  (function)
  Parameters:  none
  Returns:
    TResourceItem - a new line style resource
  Notes:
    Makes an empty line style entry for the loader.
  =========================================================================== }
function TLineStyleList.CreateItem: TResourceItem;
begin Result := TLineStyleResource.Create; end;

{ ===========================================================================
  TFillStyleList.CreateItem  (function)
  Parameters:  none
  Returns:
    TResourceItem - a new fill style resource
  Notes:
    Makes an empty fill style entry for the loader.
  =========================================================================== }
function TFillStyleList.CreateItem: TResourceItem;
begin Result := TFillStyleResource.Create; end;

{ ---- pictures ---- }

{ ===========================================================================
  TImageResource.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the decoded picture kept for drawing (Cache) with the resource.
  =========================================================================== }
destructor TImageResource.Destroy;
var
  i: Integer;
begin
  FreeAndNil(Cache);
  for i := 0 to 7 do FreeAndNil(Oriented[i]);
  inherited Destroy;
end;

{ ===========================================================================
  TImageResource.Compare  (function)
  Parameters:
    Other: TResourceItem
  Returns:
    Boolean
  Notes:
    TinyCAD never treats two pictures as the same (it compares addresses); here identical
    pictures are kept once, so pasting or inserting the same picture again does not make the
    file bigger. The file format is unchanged.
  =========================================================================== }
function TImageResource.Compare(Other: TResourceItem): Boolean;
var
  O: TImageResource;
begin
  Result := False;
  if not (Other is TImageResource) then
    Exit;
  O := TImageResource(Other);
  if (O.ImgType <> ImgType) or (Length(O.Data) <> Length(Data)) then
    Exit;
  Result := (Length(Data) = 0) or CompareMem(@Data[0], @O.Data[0], Length(Data));
end;

{ ===========================================================================
  TImageResource.WriteItem  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    As CListOfMetaFiles::SaveItemXML: the type as an attribute, then the file's bytes uuencoded
    in a UUENCODE element.
  =========================================================================== }
procedure TImageResource.WriteItem(W: TXMLWriter);
begin
  W.AddAttribute('type', ImgType);
  if Length(Data) > 0 then
    W.AddChildDataUUEncode(@Data[0], Length(Data))
  else
    W.AddChildDataUUEncode(nil, 0);
end;

{ ===========================================================================
  TImageResource.ReadItem  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  Notes:
    Reads the type and decodes the UUENCODE child. A type that is not PNG or JPEG is kept as it
    was written (TinyCAD treats it as a Windows metafile) so the picture is not lost when the
    design is saved again.
  =========================================================================== }
procedure TImageResource.ReadItem(R: TXMLReader);
var
  Name: String;
begin
  ImgType := '';
  R.GetAttribute('type', ImgType);
  if ImgType = '' then
    ImgType := 'METAFILE';
  SetLength(Data, 0);
  R.IntoTag;
  while R.NextTag(Name) do
    if Name = 'UUENCODE' then
      R.GetChildDataUUDecode(Data);
  R.OutOfTag;
end;

{ ===========================================================================
  TImageResourceList.CreateItem  (function)
  Parameters:  none
  Returns:
    TResourceItem - the new item
  Notes:
    Makes an empty picture to be read from a file.
  =========================================================================== }
function TImageResourceList.CreateItem: TResourceItem;
begin Result := TImageResource.Create; end;

{ ---- user colors ---- }

{ ===========================================================================
  TUserColors.Create  (constructor)
  Parameters:  none
  Notes:
    Creates the set of sheet colors with TinyCAD's defaults.
  =========================================================================== }
constructor TUserColors.Create;
var
  Id: Integer;
begin
  inherited Create;
  Init;
  for Id := UC_WIRE to UC_NOTETEXT_TEXT do
    if UserColorOverride[Id] >= 0 then
      FColor[Id] := Cardinal(UserColorOverride[Id]);
end;

{ ===========================================================================
  TUserColors.Init  (procedure)
  Parameters:  none
  Notes:
    Resets every user color to its default (wire blue, bus red, junction, pin, power, and so
    on).
  =========================================================================== }
procedure TUserColors.Init;
begin
  FColor[UC_WIRE] := cBLUE;
  FColor[UC_BUS] := cRED;
  FColor[UC_JUNCTION] := cBLACK;
  FColor[UC_NOCONNECT] := cBLACK;
  FColor[UC_LABEL] := RGB(0, 128, 32);
  FColor[UC_POWER] := cBLACK;
  FColor[UC_PIN] := RGB(192, 64, 64);
  FColor[UC_HIDDEN_PIN] := RGB(32, 128, 32);
  FColor[UC_BACKGROUND] := RGB(255, 255, 255);
  FColor[UC_NOTETEXT_FILL] := RGB(255, 255, 175);
  FColor[UC_NOTETEXT_LINE] := cBLUE;
  FColor[UC_NOTETEXT_TEXT] := cBLUE;
end;

{ ===========================================================================
  TUserColors.Get  (function)
  Parameters:
    Id: Integer - color id such as UC_WIRE
  Returns:
    Cardinal - the color
  Notes:
    The color for a purpose.
  =========================================================================== }
function TUserColors.Get(Id: Integer): Cardinal;
begin
  Result := FColor[Id];
end;

{ ===========================================================================
  TUserColors.SetColor  (procedure)
  Parameters:
    Id: Integer - color id
    C: Cardinal - the new color
  Notes:
    Changes the color for a purpose.
  =========================================================================== }
procedure TUserColors.SetColor(Id: Integer; C: Cardinal);
begin
  FColor[Id] := C;
end;

{ ===========================================================================
  TUserColors.TagNameOf  (function)
  Parameters:
    Id: Integer - color id
  Returns:
    String - for example COLOR_WIRE
  Notes:
    The XML element name used to save a color id.
  =========================================================================== }
class function TUserColors.TagNameOf(Id: Integer): String;
begin
  case Id of
    UC_WIRE: Result := 'COLOR_WIRE';
    UC_BUS: Result := 'COLOR_BUS';
    UC_JUNCTION: Result := 'COLOR_JUNCTION';
    UC_NOCONNECT: Result := 'COLOR_NOCONNECT';
    UC_LABEL: Result := 'COLOR_LABEL';
    UC_POWER: Result := 'COLOR_POWER';
    UC_PIN: Result := 'COLOR_PIN';
    UC_HIDDEN_PIN: Result := 'COLOR_HIDDEN_PIN';
    UC_BACKGROUND: Result := 'COLOR_BACKGROUND';
    UC_NOTETEXT_FILL: Result := 'COLOR_NOTETEXT_FILL';
    UC_NOTETEXT_LINE: Result := 'COLOR_NOTETEXT_LINE';
    UC_NOTETEXT_TEXT: Result := 'COLOR_NOTETEXT_TEXT';
  else
    Result := '';
  end;
end;

{ ===========================================================================
  TUserColors.ReadXML  (function)
  Parameters:
    R: TXMLReader - the XML reader
    const TagName: String - the element name just read
  Returns:
    Boolean - True if the tag was a color and was read
  Notes:
    Reads one color element if its name is a known color tag.
  =========================================================================== }
function TUserColors.ReadXML(R: TXMLReader; const TagName: String): Boolean;
var
  Id: Integer;
  C: Cardinal;
begin
  Result := False;
  for Id := UC_WIRE to UC_NOTETEXT_TEXT do
    if TagName = TagNameOf(Id) then
    begin
      C := 0;
      R.GetChildDataColor(C);
      FColor[Id] := C;
      Result := True;
      Exit;
    end;
end;

{ ===========================================================================
  TUserColors.WriteXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
  Notes:
    Writes every user color, in id order.
  =========================================================================== }
procedure TUserColors.WriteXML(W: TXMLWriter);
var
  Id: Integer;
begin
  for Id := UC_WIRE to UC_NOTETEXT_TEXT do // std::map order = id order
    W.AddTagColor(TagNameOf(Id), FColor[Id]);
end;

var
  OvId: Integer;
initialization
  for OvId := UC_WIRE to UC_NOTETEXT_TEXT do UserColorOverride[OvId] := -1;

end.
