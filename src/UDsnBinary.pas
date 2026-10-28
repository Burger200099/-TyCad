{ Reader for TinyCAD's old binary .dsn design files (the format used before the files became XML).

  Port of the legacy branch of CTinyCadDoc::ReadFile (Io.cpp) together with everything it calls:
  CHeaderStamp (HeaderStamp.cpp), CDetails::Read / ReadEx, TransformSnap::Load, COption::ReadNative,
  CDocResource::Load and the LoadItem / ReadNative of the font, line style, fill style, picture and
  symbol tables, CDesignFileSymbol::Load, and the Load / OldLoad / OldLoad2 / OldLoad3 of every
  drawing object. The data is read the way an MFC CArchive wrote it: little endian, no padding,
  strings with a one byte length prefix (0xFF and a word for longer ones, 0xFFFE marking UTF-16),
  and a raw copy of the C++ structures (LOGFONTA, LineStyle, FillStyle, CPoint).

  This is a read-only conversion: the objects go into the same model the XML reader fills, and the
  design is saved as XML. A file whose first bytes are not the TinyCAD stamp is not binary and is
  handed on to the XML reader, as the C++ loader does.

  Differences from the C++ loader are listed with each routine. In short: a file that ends early
  stops the load and keeps what was read (the C++ loader loops forever), old lines keep their
  thickness (the C++ loses it), old symbols that were
  stored by name are looked up through LegacySymbolFinder (the C++ loader asks the open libraries),
  tags and rulers follow what the XML reader keeps, and dates are formatted in UTC.

  Original: Copyright 1994-2019 Matt Pyne, LGPL 2.1+. This port keeps that licence. }
unit UDsnBinary;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, UDPoint, UGeometry, UDrawTypes, UResources, UDrawingObjects, USymbols, UDesign;

type
  { Raised inside the reader when the file ends in the middle of an item }
  EDsnTruncated = class(Exception);

  { Finds a library symbol by name (CLibraryCollection::GetSymbol + GetDesignSymbol(sheet, 0)): the
    first record of the first set with a record of that name, ignoring case, in the open libraries.
    Its resources are merged into Sheet's tables. Returns a new symbol (owned by the caller) or nil. Only the oldest object type (xMethod, xMethodEx)
    stores a symbol by name. }
  TLegacySymbolFinder = function(const Name: String; Sheet: TDesignSheet): TDesignFileSymbol of object;

var
  { Set by the application when libraries are open. Without it, those symbols become the "no symbol" stand-in. }
  LegacySymbolFinder: TLegacySymbolFinder = nil;

{ CHeaderStamp::Read + IsChecked: is this stream an old binary design? The position is restored. }
function IsLegacyDsn(S: TStream): Boolean;

{ CTinyCadDoc::ReadFile(stream, Details, drawing): read the binary design that starts at the
  stream's position into Sheet. Objects are appended to List. Returns True when List gained
  objects. Note receives a sentence when the load stopped early or skipped something, else ''. }
function LoadLegacyDsn(S: TStream; Sheet: TDesignSheet; List: TDrawingList;
  WithDetails: Boolean; out Note: String): Boolean;

{ CTime::Format("%d %B %Y") for a 32 bit time_t, in UTC with English month names }
function LegacyDateText(T: LongInt): String;

implementation


uses UStrings;

const
  { CHeaderStamp constants }
  STAMP_NAME = 'TinyCAD';
  STAMP_REVISION = 6;
  STAMP_MAGIC = $0C5A;

  { a symbol's drawing is a whole file that may hold symbols; real files go one level deep. A limit keeps a damaged file from running the stack out. }
  MAX_SYMBOL_NESTING = 32;

  MONTH_NAMES: array[1..12] of String = ('January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December');

  { the CP1252 code points of 0x80..0x9F (the others map to themselves) }
  CP1252_HIGH: array[0..31] of Word = (
    $20AC, $0081, $201A, $0192, $201E, $2026, $2020, $2021, $02C6, $2030, $0160, $2039, $0152, $008D, $017D, $008F,
    $0090, $2018, $2019, $201C, $201D, $2022, $2013, $2014, $02DC, $2122, $0161, $203A, $0153, $009D, $017E, $0178);

type
  { A CStream over a TStream: the primitive reads of the C++ code, with the truncation check }
  TLegacyStream = class
  private
    FS: TStream;
  public
    constructor Create(AStream: TStream);
    procedure ReadBuf(var Buf; Count: Integer);
    function Remaining: Int64;
    function ReadByte: Integer;       // BYTE
    function ReadWord: Integer;       // WORD
    function ReadInt16: Integer;      // hRESOURCE, short
    function ReadInt32: Integer;      // LONG, int, BOOL
    function ReadUInt32: Cardinal;    // DWORD, COLORREF, UINT32
    function ReadDouble: Double;
    function ReadPoint: TDPoint;      // CPoint: two LONGs
    function ReadString: String;      // CArchive >> CString
    property Stream: TStream read FS;
  end;

  { One load of a stream (the part of CTinyCadDoc the loader uses) }
  TLegacyLoader = class
  private
    FIn: TLegacyStream;
    FSheet: TDesignSheet;
    FOpts: TDocOptions;
    FNote: String;
    FDepth: Integer;
    function CP: TDPoint;
    procedure Note(const S: String);
    procedure LoadFontTable;
    procedure LoadStyleTable;
    procedure LoadFillTable;
    procedure LoadMetaFileTable;
    procedure LoadSymbolTable;
    procedure ReadSymbol(Sym: TDesignFileSymbol);
    procedure SkipLayerTable;
    function ReadFile(WithDetails: Boolean; List: TDrawingList): Boolean;
    procedure ReadDetails(Dest: TDetails; Extended: Boolean);
    procedure ReadSnap(Keep: Boolean);
    procedure ReadOptions(Keep: Boolean);
    function LoadObject(Tp: Integer): TDrawingObject;
    function LoadLine(Tp: Integer): TDrawingObject;
    function LoadPolygon(Tp: Integer): TDrawingObject;
    function LoadSquare(Tp: Integer): TDrawingObject;
    function LoadText(Tp: Integer): TDrawingObject;
    function LoadLabel(Tp: Integer): TDrawingObject;
    function LoadPin(Tp: Integer): TDrawingObject;
    function LoadMethod(Tp: Integer): TDrawingObject;
    function LoadNoteText: TDrawingObject;
    function FindSymbolByName(const Name: String): Integer;
    procedure SetFieldOld(var F: TMethodField; const Desc: String; AType: Integer);
  public
    constructor Create(AStream: TStream; ASheet: TDesignSheet);
    destructor Destroy; override;
    function Run(WithDetails: Boolean; List: TDrawingList): Boolean;
    property Notes: String read FNote;
  end;

{ ---- strings ---- }

{ ===========================================================================
  AtoF  (function)
  Parameters:
    const S: String - text
  Returns:
    Double
  Notes:
    C's atof (_tstof): blanks, a sign, digits with an optional fraction and exponent; anything
    after that is ignored.
  =========================================================================== }
function AtoF(const S: String): Double;
var
  P, Q, Code: Integer;
  Part: String;
begin
  Result := 0;
  P := 1;
  while (P <= Length(S)) and (S[P] in [' ', #9, #10, #11, #12, #13]) do Inc(P);
  Q := P;
  if (Q <= Length(S)) and (S[Q] in ['+', '-']) then
    Inc(Q);
  while (Q <= Length(S)) and (S[Q] in ['0'..'9']) do Inc(Q);
  if (Q <= Length(S)) and (S[Q] = '.') then
  begin
    Inc(Q);
    while (Q <= Length(S)) and (S[Q] in ['0'..'9']) do Inc(Q);
  end;
  if (Q < Length(S)) and (S[Q] in ['e', 'E']) then
  begin
    Code := Q + 1;
    if (Code <= Length(S)) and (S[Code] in ['+', '-']) then
      Inc(Code);
    if (Code <= Length(S)) and (S[Code] in ['0'..'9']) then
    begin
      while (Code <= Length(S)) and (S[Code] in ['0'..'9']) do Inc(Code);
      Q := Code;
    end;
  end;
  Part := Copy(S, P, Q - P);
  if (Part = '') or (Part = '+') or (Part = '-') or (Part = '.') then
    Exit;
  Val(Part, Result, Code);
  if Code <> 0 then
    Result := 0;
end;

{ ===========================================================================
  Cp1252ToUtf8  (function)
  Parameters:
    const S: String - text
  Returns:
    String
  Notes:
    MFC wrote single byte strings in the writer's ANSI code page; this assumes Windows-1252, the
    one every Western TinyCAD used.
  =========================================================================== }
function Cp1252ToUtf8(const S: String): String;
var
  i, C: Integer;
  U: UnicodeString;
begin
  SetLength(U, Length(S));
  for i := 1 to Length(S) do
  begin
    C := Ord(S[i]);
    if (C >= $80) and (C <= $9F) then
      C := CP1252_HIGH[C - $80];
    U[i] := WideChar(C);
  end;
  Result := UTF8Encode(U);
end;

{ ===========================================================================
  LegacyDateText  (function)
  Parameters:
    T: LongInt
  Returns:
    String
  Notes:
    CDetails::Read turns the stored time into text with CTime::Format("%d %B %Y"), in the local
    time zone and language of the machine. The writer's zone is not known, so UTC and English
    are used.
  =========================================================================== }
function LegacyDateText(T: LongInt): String;
var
  D: TDateTime;
  Y, M, Dy: Word;
begin
  D := EncodeDate(1970, 1, 1) + T / 86400.0;
  DecodeDate(D, Y, M, Dy);
  Result := Format('%.2d %s %d', [Dy, MONTH_NAMES[M], Y]);
end;

{ ---- TLegacyStream ---- }

{ ===========================================================================
  TLegacyStream.Create  (constructor)
  Parameters:
    AStream: TStream
  Notes:
    Wraps the file; the stream is not owned.
  =========================================================================== }
constructor TLegacyStream.Create(AStream: TStream);
begin
  inherited Create;
  FS := AStream;
end;

{ ===========================================================================
  TLegacyStream.ReadBuf  (procedure)
  Parameters:
    var Buf - in/out: changed by the call
    Count: Integer - whole number
  Notes:
    Reads exactly Count bytes or raises EDsnTruncated. (CArchive::Read returns a short count and
    the C++ loader goes on with whatever was in the variable.)
  =========================================================================== }
procedure TLegacyStream.ReadBuf(var Buf; Count: Integer);
begin
  if Count <= 0 then
    Exit;
  if FS.Read(Buf, Count) <> Count then
    raise EDsnTruncated.Create(rsTheFileEndsInThe);
end;

{ ===========================================================================
  TLegacyStream.Remaining  (function)
  Parameters:  none
  Returns:
    Int64
  Notes:
    Used to refuse lengths that cannot fit.
  =========================================================================== }
function TLegacyStream.Remaining: Int64;
begin
  Result := FS.Size - FS.Position;
end;

{ ===========================================================================
  TLegacyStream.ReadByte  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    A BYTE.
  =========================================================================== }
function TLegacyStream.ReadByte: Integer;
var
  B: Byte;
begin
  ReadBuf(B, 1);
  Result := B;
end;

{ ===========================================================================
  TLegacyStream.ReadWord  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    A WORD, little endian.
  =========================================================================== }
function TLegacyStream.ReadWord: Integer;
var
  W: Word;
begin
  ReadBuf(W, 2);
  Result := LEtoN(W);
end;

{ ===========================================================================
  TLegacyStream.ReadInt16  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    A short (hRESOURCE), little endian, sign extended.
  =========================================================================== }
function TLegacyStream.ReadInt16: Integer;
begin
  Result := SmallInt(Word(ReadWord));
end;

{ ===========================================================================
  TLegacyStream.ReadInt32  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    A LONG, int or BOOL, little endian.
  =========================================================================== }
function TLegacyStream.ReadInt32: Integer;
var
  V: LongInt;
begin
  ReadBuf(V, 4);
  Result := LEtoN(V);
end;

{ ===========================================================================
  TLegacyStream.ReadUInt32  (function)
  Parameters:  none
  Returns:
    Cardinal
  Notes:
    A DWORD, COLORREF or UINT32, little endian.
  =========================================================================== }
function TLegacyStream.ReadUInt32: Cardinal;
var
  V: Cardinal;
begin
  ReadBuf(V, 4);
  Result := LEtoN(V);
end;

{ ===========================================================================
  TLegacyStream.ReadDouble  (function)
  Parameters:  none
  Returns:
    Double
  Notes:
    A double (IEEE, little endian), as the scaling of a symbol is stored.
  =========================================================================== }
function TLegacyStream.ReadDouble: Double;
var
  Q: QWord;
begin
  ReadBuf(Q, 8);
  Q := LEtoN(Q);
  Move(Q, Result, 8);
end;

{ ===========================================================================
  TLegacyStream.ReadPoint  (function)
  Parameters:  none
  Returns:
    TDPoint
  Notes:
    A CPoint (two LONGs) as CDrawingObject::ReadPoint reads it.
  =========================================================================== }
function TLegacyStream.ReadPoint: TDPoint;
var
  X, Y: Integer;
begin
  X := ReadInt32;
  Y := ReadInt32;
  Result := DPoint(X, Y);
end;

{ ===========================================================================
  TLegacyStream.ReadString  (function)
  Parameters:  none
  Returns:
    String
  Notes:
    CArchive >> CString. The length is one byte, or 0xFF and a word, or 0xFF 0xFFFF and a dword;
    a leading 0xFF 0xFFFE says the characters are UTF-16 and the length follows again. Single
    byte text is taken as Windows-1252.
  =========================================================================== }
function TLegacyStream.ReadString: String;
var
  Len: Int64;
  Wide: Boolean;
  W: Word;
  B: Byte;
  Raw: String;
  U: UnicodeString;
  i: Integer;

  function ReadLength: Int64;
  begin
    ReadBuf(B, 1);
    if B < $FF then
      Exit(B);
    W := ReadWord;
    if W = $FFFE then
    begin
      Wide := True;
      Exit(ReadLength());
    end;
    if W = $FFFF then
      Exit(ReadUInt32);
    Result := W;
  end;

begin
  Wide := False;
  Len := ReadLength;
  if Len * (1 + Ord(Wide)) > Remaining then
    raise EDsnTruncated.Create(rsATextIsLongerThan);
  if Wide then
  begin
    SetLength(U, Len);
    for i := 1 to Len do U[i] := WideChar(ReadWord);
    Result := UTF8Encode(U);
  end
  else
  begin
    SetLength(Raw, Len);
    if Len > 0 then
      ReadBuf(Raw[1], Len);
    Result := Cp1252ToUtf8(Raw);
  end;
end;

{ ---- header stamp ---- }

{ ===========================================================================
  IsLegacyDsn  (function)
  Parameters:
    S: TStream
  Returns:
    Boolean
  Notes:
    CHeaderStamp::Read then IsChecked(false): the name is TinyCAD, the magic number is 0x0C5A
    and the revision is not newer than 6. An XML file fails at the first test because its first
    byte is not a length of 7. The stream position is put back.
  =========================================================================== }
function IsLegacyDsn(S: TStream): Boolean;
var
  Start: Int64;
  L: TLegacyStream;
  Name: String;
  Rev, Magic: Integer;
begin
  Result := False;
  Start := S.Position;
  L := TLegacyStream.Create(S);
  try
    try
      Name := L.ReadString;
      Rev := L.ReadByte;
      Magic := L.ReadInt16;
      Result := (Name = STAMP_NAME) and (Magic = STAMP_MAGIC) and (Rev <= STAMP_REVISION);
    except
      on EDsnTruncated do Result := False;
    end;
  finally
    L.Free;
    S.Position := Start;
  end;
end;

{ ---- TLegacyLoader ---- }

{ ===========================================================================
  TLegacyLoader.Create  (constructor)
  Parameters:
    AStream: TStream
    ASheet: TDesignSheet - the sheet
  Notes:
    Sets up one load.
  =========================================================================== }
constructor TLegacyLoader.Create(AStream: TStream; ASheet: TDesignSheet);
begin
  inherited Create;
  FIn := TLegacyStream.Create(AStream);
  FSheet := ASheet;
  FOpts := ASheet.Options;
end;

{ ===========================================================================
  TLegacyLoader.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the stream wrapper.
  =========================================================================== }
destructor TLegacyLoader.Destroy;
begin
  FIn.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TLegacyLoader.CP  (function)
  Parameters:  none
  Returns:
    TDPoint
  Notes:
    CDrawingObject::ReadPoint.
  =========================================================================== }
function TLegacyLoader.CP: TDPoint;
begin
  Result := FIn.ReadPoint;
end;

{ ===========================================================================
  TLegacyLoader.Note  (procedure)
  Parameters:
    const S: String - text
  Notes:
    Remembers something the user should be told; only the first is kept.
  =========================================================================== }
procedure TLegacyLoader.Note(const S: String);
begin
  if FNote = '' then
    FNote := S;
end;

{ ===========================================================================
  TLegacyLoader.LoadFontTable  (procedure)
  Parameters:  none
  Notes:
    CDocResource::Load with ListOfFonts::LoadItem: a word count, then for each a short number
    and a LOGFONTA (60 bytes: five LONGs, eight BYTEs, a 32 byte face name). The table is reset
    for merging first, and each font is added under its number in the file.
  =========================================================================== }
procedure TLegacyLoader.LoadFontTable;
var
  Count, n, Id: Integer;
  F: TFontResource;
  Face: array[0..31] of AnsiChar;
  Raw: String;
  i: Integer;
begin
  FOpts.Fonts.ResetMerge;
  Count := FIn.ReadWord;
  for n := 1 to Count do
  begin
    Id := FIn.ReadInt16;
    F := TFontResource.Create;
    F.Height := FIn.ReadInt32;
    F.Width := FIn.ReadInt32;
    FIn.ReadInt32;                      // lfEscapement
    FIn.ReadInt32;                      // lfOrientation
    F.Weight := FIn.ReadInt32;
    F.Italic := FIn.ReadByte;
    F.Underline := FIn.ReadByte;
    F.StrikeOut := FIn.ReadByte;
    F.CharSet := FIn.ReadByte;
    FIn.ReadByte;                       // lfOutPrecision
    FIn.ReadByte;                       // lfClipPrecision
    FIn.ReadByte;                       // lfQuality
    FIn.ReadByte;                       // lfPitchAndFamily
    FIn.ReadBuf(Face, 32);
    Raw := '';
    for i := 0 to 31 do
    begin
      if Face[i] = #0 then
        Break;
      Raw := Raw + Face[i];
    end;
    F.FaceName := Cp1252ToUtf8(Raw);
    FOpts.Fonts.Add(F, Id);
  end;
end;

{ ===========================================================================
  TLegacyLoader.LoadStyleTable  (procedure)
  Parameters:  none
  Notes:
    CDocResource::Load with ListOfStyles::LoadItem: a word count, then for each a short number
    and a LineStyle (Int32 style, Int32 thickness, COLORREF colour).
  =========================================================================== }
procedure TLegacyLoader.LoadStyleTable;
var
  Count, n, Id, St, Th: Integer;
  Col: Cardinal;
begin
  FOpts.Styles.ResetMerge;
  Count := FIn.ReadWord;
  for n := 1 to Count do
  begin
    Id := FIn.ReadInt16;
    St := FIn.ReadInt32;
    Th := FIn.ReadInt32;
    Col := FIn.ReadUInt32;
    FOpts.Styles.Add(TLineStyleResource.CreateWith(St, Th, Col), Id);
  end;
end;

{ ===========================================================================
  TLegacyLoader.LoadFillTable  (procedure)
  Parameters:  none
  Notes:
    CDocResource::Load with ListOfFillStyles::LoadItem: a word count, then for each a short
    number and a FillStyle (Int32 index, COLORREF colour).
  =========================================================================== }
procedure TLegacyLoader.LoadFillTable;
var
  Count, n, Id, Idx: Integer;
  Col: Cardinal;
begin
  FOpts.Fills.ResetMerge;
  Count := FIn.ReadWord;
  for n := 1 to Count do
  begin
    Id := FIn.ReadInt16;
    Idx := FIn.ReadInt32;
    Col := FIn.ReadUInt32;
    FOpts.Fills.Add(TFillStyleResource.CreateWith(Idx, Col), Id);
  end;
end;

{ ===========================================================================
  TLegacyLoader.LoadMetaFileTable  (procedure)
  Parameters:  none
  Notes:
    CDocResource::Load with ListOfMetaFiles::LoadItem: a word count, then for each a short
    number, a UINT32 size and that many bytes of Windows enhanced metafile. The bytes are kept
    as they are (type METAFILE), the way the XML reader keeps pictures it cannot decode.
  =========================================================================== }
procedure TLegacyLoader.LoadMetaFileTable;
var
  Count, n, Id: Integer;
  Size: Cardinal;
  Img: TImageResource;
begin
  FOpts.Images.ResetMerge;
  Count := FIn.ReadWord;
  for n := 1 to Count do
  begin
    Id := FIn.ReadInt16;
    Size := FIn.ReadUInt32;
    if Size > FIn.Remaining then
      raise EDsnTruncated.Create(rsAPictureIsLongerThan);
    Img := TImageResource.Create;
    Img.ImgType := 'METAFILE';
    SetLength(Img.Data, Size);
    if Size > 0 then
      FIn.ReadBuf(Img.Data[0], Size);
    FOpts.Images.Add(Img, Id);
  end;
end;

{ ===========================================================================
  TLegacyLoader.ReadSymbol  (procedure)
  Parameters:
    Sym: TDesignFileSymbol
  Notes:
    CDesignFileSymbol::Load. Name, description and reference strings, the parts-per-package
    byte, and a string holding the number of extra fields (low 16 bits) and the name/reference
    display types (high bits: type of the name above 3, of the reference in the low 3). Then the
    fields (three strings, a CPoint, a DWORD type) and the drawing of the symbol, which is a
    whole design file read the same way with Details off (CDesignFileSymbol::LoadSymbol). A
    symbol drawing stored as XML inside the binary file cannot be followed: the load stops.
  =========================================================================== }
procedure TLegacyLoader.ReadSymbol(Sym: TDesignFileSymbol);
var
  Dummy: String;
  NumFields, Flags: Cardinal;
  i: Integer;
  F: TSymbolFieldDef;
  Start: Int64;
  Ok: Boolean;
  L: TDrawingList;
  P: Integer;
  Neg: Boolean;
  V: Int64;
begin
  Sym.Name := FIn.ReadString;
  Sym.Description := FIn.ReadString;
  Sym.Reference := FIn.ReadString;
  Sym.Ppp := FIn.ReadByte;
  Dummy := FIn.ReadString;

  { _ttoi: blanks, a sign, digits; anything else is 0 }
  V := 0;
  P := 1;
  while (P <= Length(Dummy)) and (Dummy[P] in [' ', #9, #10, #11, #12, #13]) do Inc(P);
  Neg := False;
  if (P <= Length(Dummy)) and (Dummy[P] in ['+', '-']) then
  begin
    Neg := Dummy[P] = '-';
    Inc(P);
  end;
  while (P <= Length(Dummy)) and (Dummy[P] in ['0'..'9']) do
  begin
    V := (V * 10 + Ord(Dummy[P]) - 48) and $FFFFFFFF;
    Inc(P);
  end;
  if Neg then
    V := (-V) and $FFFFFFFF;
  NumFields := Cardinal(V);

  Flags := NumFields shr 16;
  NumFields := NumFields and $FFFF;
  for i := 1 to NumFields do
  begin
    F.Name := FIn.ReadString;
    F.Value := FIn.ReadString;
    F.Default := FIn.ReadString;
    F.Pos := CP;
    F.FieldType := FIn.ReadUInt32;
    SetLength(Sym.Fields, Length(Sym.Fields) + 1);
    Sym.Fields[High(Sym.Fields)] := F;
  end;
  Sym.NameType := Integer(Flags shr 3);
  Sym.RefType := Integer(Flags and 7);

  { LoadSymbol: a binary stamp means a nested design file }
  Start := FIn.Stream.Position;
  if IsLegacyDsn(FIn.Stream) then
  begin
    Sym.ClearMethods;
    L := Sym.AddMethod;
    Sym.Heterogeneous := False;
    Inc(FDepth);
    try
      if FDepth > MAX_SYMBOL_NESTING then
        raise EDsnTruncated.Create(rsSymbolsAreNestedTooDeeply);
      Ok := ReadFile(False, L);
    finally
      Dec(FDepth);
    end;
    if not Ok then
      ;   // (LoadSymbol returns FALSE and the symbol stays empty)
  end
  else
  begin
    FIn.Stream.Position := Start;
    raise EDsnTruncated.Create(rsASymbolStoredAsXML);
  end;
end;

{ ===========================================================================
  TLegacyLoader.LoadSymbolTable  (procedure)
  Parameters:  none
  Notes:
    CDocResource::Load with ListOfSymbols::LoadItem: a word count, then for each a short number
    and a symbol (ReadSymbol). The symbol is made and read before it is added to the table.
  =========================================================================== }
procedure TLegacyLoader.LoadSymbolTable;
var
  Count, n, Id: Integer;
  Sym: TDesignFileSymbol;
begin
  FOpts.Symbols.ResetMerge;
  Count := FIn.ReadWord;
  for n := 1 to Count do
  begin
    Id := FIn.ReadInt16;
    Sym := TDesignFileSymbol.Create(FOpts);
    try
      ReadSymbol(Sym);
    except
      Sym.Free;
      raise;
    end;
    FOpts.Symbols.Add(TSymbolResource.CreateFor(FOpts, Sym), Id);
  end;
end;

{ ===========================================================================
  TLegacyLoader.SkipLayerTable  (procedure)
  Parameters:  none
  Notes:
    xLayerTable: a word count of (short number, string) pairs that nothing uses; read and
    dropped.
  =========================================================================== }
procedure TLegacyLoader.SkipLayerTable;
var
  Count, n: Integer;
begin
  Count := FIn.ReadWord;
  for n := 1 to Count do
  begin
    FIn.ReadInt16;
    FIn.ReadString;
  end;
end;

{ ===========================================================================
  TLegacyLoader.ReadDetails  (procedure)
  Parameters:
    Dest: TDetails - the stream to write to
    Extended: Boolean - flag
  Notes:
    Page size (two LONGs), six strings (title, author, revision, document number, organisation,
    sheets), then the old form has a visible byte and a 32 bit time, the new one a flags byte
    (bit 0 title block shown, bit 1 rulers on, rulers then 5 by 7) and the date as a string. The
    old time is shown as text like the C++ does.
  =========================================================================== }
procedure TLegacyLoader.ReadDetails(Dest: TDetails; Extended: Boolean);
var
  Shows, T: Integer;
begin
  Dest.PageWidth := FIn.ReadInt32;
  Dest.PageHeight := FIn.ReadInt32;
  Dest.Title := FIn.ReadString;
  Dest.Author := FIn.ReadString;
  Dest.Revision := FIn.ReadString;
  Dest.DocNo := FIn.ReadString;
  Dest.Org := FIn.ReadString;
  Dest.Sheets := FIn.ReadString;
  Shows := FIn.ReadByte;
  if Extended then
  begin
    Dest.LastChange := FIn.ReadString;
    Dest.IsVisible := (Shows and 1) <> 0;
    Dest.HasRulers := (Shows and 2) <> 0;
    Dest.VertRulerSize := 5;
    Dest.HorizRulerSize := 7;
  end
  else
  begin
    T := FIn.ReadInt32;
    Dest.LastChange := LegacyDateText(T);
    Dest.IsVisible := Shows <> 0;
  end;
end;

{ ===========================================================================
  TLegacyLoader.ReadSnap  (procedure)
  Parameters:
    Keep: Boolean - flag
  Notes:
    TransformSnap::Load: a LONG grid spacing (tenths of a unit) and a BOOL snap flag.
  =========================================================================== }
procedure TLegacyLoader.ReadSnap(Keep: Boolean);
var
  G, S: Integer;
begin
  G := FIn.ReadInt32;
  S := FIn.ReadInt32;
  if Keep then
  begin
    FSheet.Snap.Grid := G / 10.0;
    FSheet.Snap.GridSnap := S;
  end;
end;

{ ===========================================================================
  TLegacyLoader.ReadOptions  (procedure)
  Parameters:
    Keep: Boolean - flag
  Notes:
    COption::ReadNative: current font and style numbers (two shorts, dropped), the grid-shown
    BOOL, the units LONG and the scroll bar LONG (dropped).
  =========================================================================== }
procedure TLegacyLoader.ReadOptions(Keep: Boolean);
var
  Show, Units: Integer;
begin
  FIn.ReadInt16;
  FIn.ReadInt16;
  Show := FIn.ReadInt32;
  Units := FIn.ReadInt32;
  FIn.ReadInt32;
  if Keep then
  begin
    FOpts.GridShow := Show;
    FOpts.Units := Units;
  end;
end;

{ ===========================================================================
  TLegacyLoader.SetFieldOld  (procedure)
  Parameters:
    var F: TMethodField - in/out: changed by the call
    const Desc: String - text
    AType: Integer - whole number
  Notes:
    Gives a field of an old symbol placement its description and type.
  =========================================================================== }
procedure TLegacyLoader.SetFieldOld(var F: TMethodField; const Desc: String; AType: Integer);
begin
  F.Description := Desc;
  F.FieldType := AType;
end;

{ ===========================================================================
  TLegacyLoader.FindSymbolByName  (function)
  Parameters:
    const Name: String - the name
  Returns:
    Integer
  Notes:
    CDrawMethod::GetSymbolByName. The C++ asks the open libraries and keeps a copy of the symbol
    with the design (COption::AddSymbol). Here LegacySymbolFinder does the asking; without one
    the placement shows the "no symbol" stand-in and the load notes it.
  =========================================================================== }
function TLegacyLoader.FindSymbolByName(const Name: String): Integer;
var
  Sym: TDesignFileSymbol;
begin
  Result := 0;
  Sym := nil;
  if Assigned(LegacySymbolFinder) then
    Sym := LegacySymbolFinder(Name, FSheet);
  if Sym = nil then
  begin
    Note('A symbol stored by name (' + Name + ') was not found in the libraries');
    Exit;
  end;
  Result := FOpts.AddSymbol(Sym);
end;

{ ===========================================================================
  TLegacyLoader.LoadLine  (function)
  Parameters:
    Tp: Integer - whole number
  Returns:
    TDrawingObject
  Notes:
    CDrawLine::Load for the two kinds the file loop makes lines of: two points, and the default
    wire/bus style.
  =========================================================================== }
function TLegacyLoader.LoadLine(Tp: Integer): TDrawingObject;
var
  Obj: TDrawLine;
begin
  Obj := TDrawLine.CreateKind(FOpts, TObjType(Tp));
  Result := Obj;
  Obj.PointA := CP;
  Obj.PointB := CP;
  Obj.UseDefaultStyle := True;
end;

{ ===========================================================================
  TLegacyLoader.LoadPolygon  (function)
  Parameters:
    Tp: Integer - whole number
  Returns:
    TDrawingObject
  Notes:
    CDrawPolygon::Load. Everything but xPolygon is a line or arc between two points: the handles
    are (0,0) and the end relative to the start, the end carrying the "arc out" mark for the two
    newer arcs. Then by kind: xLine / xDash keep their default style; xLineEx / xArcEx have a
    thickness byte that makes a black solid style of that thickness (added to the table; the C++
    then converts the new number as if it came from a table in the file, which gives style 0 and
    loses the thickness, so here the new number is used as it is); xLineEx2 / xArcEx2 have a
    style number; xPolygon has a version, a count, the first point, the handles (a version 0
    handle is a CPoint, later ones add an arc type), then style and fill numbers. Finally the
    style is re-added as a copy, the polygon is not closed (the binary file has no close flag)
    and the kind becomes the newest one for its shape: xLine, xDash and xLineEx give xLineEx2,
    xArc and xArcEx give xArcEx2. (The C++ meant to turn xLineEx into xLineEx2 too, but its test
    looks for xLine, so it stays xLineEx there; nothing tells them apart.)
  =========================================================================== }
function TLegacyLoader.LoadPolygon(Tp: Integer): TDrawingObject;
var
  Obj: TDrawPolygon;
  Kind: TObjType;
  P: TDPoint;
  H: TArcPoint;
  Version, Lines: Cardinal;
  Th, N: Integer;
  Src: TLineStyleResource;

  procedure AddHandle(X, Y: Double; Arc: Integer);
  begin
    H.X := X;
    H.Y := Y;
    H.Arc := Arc;
    { DEVIATION: the file holds no control point (the C++ leaves a NaN one, which only floating point that does not trap survives),
      so a handle of the control kind, which these old files never wrote, becomes a plain corner }
    if Arc = Arc_control then
      H.Arc := Arc_none;
    H.Control := DPointInvalid;
    H.FlattenedSegment := 0;
    SetLength(Obj.Handles, Length(Obj.Handles) + 1);
    Obj.Handles[High(Obj.Handles)] := H;
  end;

begin
  Kind := TObjType(Tp);
  Obj := TDrawPolygon.Create(FOpts);
  Result := Obj;
  Obj.Kind := Kind;
  { the constructor's style choice by kind }
  case Kind of
    xPolygon, xLineEx2: Obj.Style := 0;          // GetCurrentStyle: nothing chosen yet
    xDash: Obj.Style := fDASH;
  else
    Obj.Style := fLINE;
  end;
  Obj.Fill := fsNONE;
  Obj.Close := 0;
  SetLength(Obj.Handles, 0);

  if Kind <> xPolygon then
  begin
    Obj.PointA := CP;
    Obj.PointB := CP;
    AddHandle(0, 0, Arc_none);
    P := DPoint(Obj.PointB.x - Obj.PointA.x, Obj.PointB.y - Obj.PointA.y);
    if (Kind = xArcEx) or (Kind = xArcEx2) then
      AddHandle(P.x, P.y, Arc_out)
    else
      AddHandle(P.x, P.y, Arc_none);
  end;

  case Kind of
    xDash, xLine:
      Obj.Kind := xLineEx2;
    xArcEx, xLineEx:
      begin
        Th := FIn.ReadByte;
        { the new style's own number is used (the C++ runs it through ConvertOld as if it were a number from a
          table in the file, which finds nothing and gives style 0, so the line loses its thickness) }
        Obj.Style := FOpts.AddStyle(PS_SOLID, Th, 0);
        Obj.Fill := fsNONE;
        if Kind = xArcEx then
          Obj.Kind := xArcEx2
        else
          Obj.Kind := xLineEx2;
      end;
    xArcEx2, xLineEx2:
      begin
        Obj.Style := FOpts.Styles.ConvertOld(FIn.ReadWord);
        Obj.Fill := fsNONE;
      end;
    xPolygon:
      begin
        Version := FIn.ReadUInt32;
        Lines := FIn.ReadUInt32;
        Obj.PointA := CP;
        while Lines > 0 do
        begin
          if Version = 0 then
          begin
            P := CP;
            AddHandle(P.x, P.y, Arc_none);
          end
          else
          begin
            N := FIn.ReadInt32;
            Th := FIn.ReadInt32;
            AddHandle(N, Th, FIn.ReadInt32);
          end;
          Dec(Lines);
        end;
        Obj.Style := FOpts.Styles.ConvertOld(FIn.ReadWord);
        Obj.Fill := FOpts.Fills.ConvertOld(FIn.ReadWord);
      end;
    xArc:
      Obj.Kind := xArcEx2;
  end;

  { "Calculate the Style nr here": keep a copy of the chosen style and use that }
  Src := FOpts.Styles.Get(Obj.Style) as TLineStyleResource;
  Obj.Style := FOpts.AddStyle(Src.Style, Src.Thickness, Src.Color);
  Obj.CalcBoundingRect;
end;

{ ===========================================================================
  TLegacyLoader.LoadSquare  (function)
  Parameters:
    Tp: Integer - whole number
  Returns:
    TDrawingObject
  Notes:
    CDrawSquare::OldLoad (xSquare, xSquareEx, xCircle, xCircleEx): two points, and for xSquareEx
    only a thickness byte; the style is a new black solid one of that thickness (1 when there is
    no byte), no fill. OldLoad2 (xSquareEx2, xCircleEx2): two points and a style number, no
    fill. Load (xSquareEx3, xCircleEx3): a version word, two points, a style number and a fill
    number. Circles become ellipses (xCircleEx3), squares rectangles (xSquareEx3).
  =========================================================================== }
function TLegacyLoader.LoadSquare(Tp: Integer): TDrawingObject;
var
  Obj: TDrawSquare;
  Th: Integer;
  IsCircle: Boolean;
begin
  IsCircle := Tp in [Ord(xCircle), Ord(xCircleEx), Ord(xCircleEx2), Ord(xCircleEx3)];
  if IsCircle then
    Obj := TDrawSquare.CreateKind(FOpts, xCircleEx3)
  else
    Obj := TDrawSquare.CreateKind(FOpts, xSquareEx3);
  Result := Obj;
  case Tp of
    Ord(xSquare), Ord(xSquareEx), Ord(xCircle), Ord(xCircleEx):
      begin
        Th := 1;
        Obj.PointA := CP;
        Obj.PointB := CP;
        if Tp = Ord(xSquareEx) then
          Th := FIn.ReadByte;
        Obj.Style := FOpts.AddStyle(PS_SOLID, Th, 0);
        Obj.Fill := fsNONE;
      end;
    Ord(xCircleEx2), Ord(xSquareEx2):
      begin
        Obj.PointA := CP;
        Obj.PointB := CP;
        Obj.Style := FOpts.Styles.ConvertOld(FIn.ReadWord);
        Obj.Fill := fsNONE;
      end;
  else
    begin
      FIn.ReadWord;                       // version
      Obj.PointA := CP;
      Obj.PointB := CP;
      Obj.Style := FOpts.Styles.ConvertOld(FIn.ReadWord);
      Obj.Fill := FOpts.Fills.ConvertOld(FIn.ReadWord);
    end;
  end;
end;

{ ===========================================================================
  TLegacyLoader.LoadText  (function)
  Parameters:
    Tp: Integer - whole number
  Returns:
    TDrawingObject
  Notes:
    CDrawText::Load: a point, a direction byte and the string. xTextEx, xBusName then have a
    font number, xTextEx2 and xBusNameEx a font number and a colour; xText uses the first font.
    The colour of the older kinds is the text colour (black) or, for bus names, the label colour
    from the user colours. Old kinds become xTextEx2 / xBusNameEx.
  =========================================================================== }
function TLegacyLoader.LoadText(Tp: Integer): TDrawingObject;
var
  Obj: TDrawText;
  IsBus: Boolean;
begin
  IsBus := (Tp = Ord(xBusName)) or (Tp = Ord(xBusNameEx));
  if IsBus then
    Obj := TDrawText.CreateKind(FOpts, xBusNameEx)
  else
    Obj := TDrawText.CreateKind(FOpts, xTextEx2);
  Result := Obj;
  Obj.PointA := CP;
  Obj.Dir := FIn.ReadByte;
  Obj.Str := FIn.ReadString;
  case Tp of
    Ord(xTextEx), Ord(xBusName):
      begin
        Obj.FontStyle := FOpts.Fonts.ConvertOld(FIn.ReadInt16);
        if IsBus then
          Obj.FontColor := FOpts.Colors.Get(UC_LABEL)
        else
          Obj.FontColor := cBLACK;
      end;
    Ord(xTextEx2), Ord(xBusNameEx):
      begin
        Obj.FontStyle := FOpts.Fonts.ConvertOld(FIn.ReadInt16);
        Obj.FontColor := FIn.ReadUInt32;
      end;
  else
    begin
      Obj.FontStyle := fTEXT;
      Obj.FontColor := cBLACK;
    end;
  end;
  Obj.PointB := Obj.PointA;
end;

{ ===========================================================================
  TLegacyLoader.LoadLabel  (function)
  Parameters:
    Tp: Integer - whole number
  Returns:
    TDrawingObject
  Notes:
    CDrawLabel::Load: a point, a direction byte and the string; xLabelEx adds a font number,
    xLabelEx2 a font number and a colour; xLabel uses the first font. The older two get the
    label colour of the user colours. The point is the connection point of the label.
  =========================================================================== }
function TLegacyLoader.LoadLabel(Tp: Integer): TDrawingObject;
var
  Obj: TDrawLabel;
begin
  Obj := TDrawLabel.Create(FOpts);
  Result := Obj;
  Obj.LabelStyle := label_normal;
  Obj.ActivePoint := CP;
  Obj.PointA := Obj.ActivePoint;
  Obj.Dir := FIn.ReadByte;
  Obj.Str := FIn.ReadString;
  case Tp of
    Ord(xLabelEx):
      Obj.FontStyle := FOpts.Fonts.ConvertOld(FIn.ReadInt16);
    Ord(xLabelEx2):
      begin
        Obj.FontStyle := FOpts.Fonts.ConvertOld(FIn.ReadInt16);
        Obj.FontColor := FIn.ReadUInt32;
      end;
  else
    Obj.FontStyle := fTEXT;
  end;
  if (Tp = Ord(xLabel)) or (Tp = Ord(xLabelEx)) then
    Obj.FontColor := FOpts.Colors.Get(UC_LABEL);
  Obj.PointB := Obj.PointA;
end;

{ ===========================================================================
  TLegacyLoader.LoadPin  (function)
  Parameters:
    Tp: Integer - whole number
  Returns:
    TDrawingObject
  Notes:
    CDrawPin::Load: point, which, electrical type, direction, part, name, number, show (the
    bytes in that order) and a word length; lengths 1..4 become 20. The old form (OldLoad) has
    no length word: bit 7 of "which" says a small pin (20) else 30, and is cleared. The number
    position is 0 and the name is centred on the shaft for power pins.
  =========================================================================== }
function TLegacyLoader.LoadPin(Tp: Integer): TDrawingObject;
var
  Obj: TDrawPin;
  Small: Boolean;
begin
  Obj := TDrawPin.Create(FOpts);
  Result := Obj;
  Obj.PointA := CP;
  Obj.Which := FIn.ReadByte;
  Obj.Elec := FIn.ReadByte;
  Obj.Dir := FIn.ReadByte;
  Obj.Part := FIn.ReadByte;
  Obj.Str := FIn.ReadString;
  Obj.Number := FIn.ReadString;
  Obj.Show := FIn.ReadByte;
  Obj.NumberPos := 0;
  if Tp = Ord(xPin) then
  begin
    Small := (Obj.Which and 128) <> 0;
    Obj.Which := Obj.Which and (not 128);
    if Small then
      Obj.Length := 20
    else
      Obj.Length := 30;
  end
  else
  begin
    Obj.Length := FIn.ReadWord;
    if (Obj.Length < 5) and (Obj.Length <> 0) then
      Obj.Length := 20;
  end;
  Obj.CentreName := Ord(Obj.IsPower);
  Obj.PointB := Obj.PointA;
end;

{ ===========================================================================
  TLegacyLoader.LoadMethod  (function)
  Parameters:
    Tp: Integer - whole number
  Returns:
    TDrawingObject
  Notes:
    xMethodEx3 is CDrawMethod::Load: an int version, the symbol number (short), the point, part
    and rotation bytes, can-scale BOOL, two doubles for the scaling, a field count and for each
    field a type int, description and value strings, a show BOOL and a CPoint. The symbol number
    is converted through the sheet's symbol table. The three older kinds have three fixed
    fields. OldLoad (xMethod): the symbol by name, three strings (name, other, reference), three
    CPoints, a shows byte, rotation byte, point, part byte. OldLoad2 (xMethodEx) adds an
    attribute string after the three; OldLoad3 (xMethodEx2) has the symbol number (short) in
    place of the name and, after the part, a word count of symbol fields whose SCALING_X /
    SCALING_Y values become the scaling. The shows byte gives the name (1), other (2) and
    reference (4) visibility. The "other" field is hidden and described as Other.
  =========================================================================== }
function TLegacyLoader.LoadMethod(Tp: Integer): TDrawingObject;
var
  Obj: TDrawMethod;
  Shows, i, Cnt, FieldCount: Integer;
  SymName, Attrib: String;
  Fs: array of TSymbolFieldDef;
  F: TSymbolFieldDef;

  procedure ReadThreeValues;
  begin
    Obj.Fields[FIELD_NAME].Value := FIn.ReadString;
    Obj.Fields[2].Value := FIn.ReadString;
    Obj.Fields[FIELD_REF].Value := FIn.ReadString;
  end;

  procedure ReadThreePositions;
  begin
    Obj.Fields[FIELD_NAME].Position := CP;
    Obj.Fields[2].Position := CP;
    Obj.Fields[FIELD_REF].Position := CP;
  end;

  procedure ApplyShows;
  begin
    Obj.Fields[FIELD_NAME].Show := Ord((Shows and 1) <> 0);
    Obj.Fields[2].Show := Ord((Shows and 2) <> 0);
    Obj.Fields[FIELD_REF].Show := Ord((Shows and 4) <> 0);
  end;

begin
  Obj := TDrawMethod.Create(FOpts);
  Result := Obj;
  if Tp = Ord(xMethodEx3) then
  begin
    FIn.ReadInt32;                                    // load version
    Obj.SymbolId := FIn.ReadInt16;
    Obj.PointA := CP;
    Obj.Part := FIn.ReadByte;
    Obj.Rotate := FIn.ReadByte;
    Obj.CanScale := FIn.ReadInt32;
    Obj.ScalingX := FIn.ReadDouble;
    Obj.ScalingY := FIn.ReadDouble;
    FieldCount := FIn.ReadInt32;
    if (FieldCount < 0) or (FieldCount > FIn.Remaining) then
      raise EDsnTruncated.Create(rsASymbolClaimsMoreFields);
    SetLength(Obj.Fields, FieldCount);
    for i := 0 to FieldCount - 1 do
    begin
      Obj.Fields[i].FieldType := FIn.ReadInt32;
      Obj.Fields[i].Description := FIn.ReadString;
      Obj.Fields[i].Value := FIn.ReadString;
      Obj.Fields[i].Show := FIn.ReadInt32;
      Obj.Fields[i].Position := CP;
    end;
    Obj.SymbolId := FOpts.NewSymbolNumber(Obj.SymbolId);
    Obj.PointB := Obj.PointA;
    Exit;
  end;

  SetLength(Obj.Fields, 3);
  SetFieldOld(Obj.Fields[2], 'Other', default_hidden);
  case Tp of
    Ord(xMethod):
      begin
        SymName := FIn.ReadString;
        ReadThreeValues;
        ReadThreePositions;
        Shows := FIn.ReadByte;
        Obj.Rotate := FIn.ReadByte;
        Obj.PointA := CP;
        Obj.Part := FIn.ReadByte;
        ApplyShows;
        Obj.SymbolId := FindSymbolByName(SymName);
      end;
    Ord(xMethodEx):
      begin
        SymName := FIn.ReadString;
        ReadThreeValues;
        Attrib := FIn.ReadString;
        ReadThreePositions;
        Shows := FIn.ReadByte;
        Obj.Rotate := FIn.ReadByte;
        Obj.PointA := CP;
        Obj.Part := FIn.ReadByte;
        ApplyShows;
        Obj.SymbolId := FindSymbolByName(SymName);
      end;
  else
    begin
      Obj.SymbolId := FIn.ReadInt16;
      ReadThreeValues;
      Attrib := FIn.ReadString;
      ReadThreePositions;
      Shows := FIn.ReadByte;
      Obj.Rotate := FIn.ReadByte;
      Obj.PointA := CP;
      Obj.Part := FIn.ReadByte;
      Cnt := FIn.ReadWord;
      SetLength(Fs, 0);
      for i := 1 to Cnt do
      begin
        F.Name := FIn.ReadString;
        F.Value := FIn.ReadString;
        F.Default := FIn.ReadString;
        F.Pos := CP;
        F.FieldType := FIn.ReadUInt32;
        SetLength(Fs, Length(Fs) + 1);
        Fs[High(Fs)] := F;
      end;
      for i := 0 to High(Fs) do
        if Fs[i].Name = 'SCALING_X' then
        begin
          Obj.ScalingX := AtoF(Fs[i].Value);
        end
        else if Fs[i].Name = 'SCALING_Y' then
        begin
          Obj.ScalingY := AtoF(Fs[i].Value);
        end;
      ApplyShows;
      Obj.SymbolId := FOpts.NewSymbolNumber(Obj.SymbolId);
    end;
  end;
  if Attrib = '' then
    ;                               // (read and dropped, as in C++)
  Obj.PointB := Obj.PointA;
end;

{ ===========================================================================
  TLegacyLoader.LoadNoteText  (function)
  Parameters:  none
  Returns:
    TDrawingObject
  Notes:
    CDrawNoteText::Load: a version word, two points, the direction byte, style and fill words, a
    font number, the font colour and the border style (an int). The file holds no text, so the
    note keeps the default "Note", and, as in the C++, its box is then set to the size of that
    text.
  =========================================================================== }
function TLegacyLoader.LoadNoteText: TDrawingObject;
var
  Obj: TDrawNoteText;
  Sz: TDSize;
begin
  Obj := TDrawNoteText.Create(FOpts);
  Result := Obj;
  FIn.ReadWord;
  Obj.PointA := CP;
  Obj.PointB := CP;
  Obj.Dir := FIn.ReadByte;
  Obj.Style := FOpts.Styles.ConvertOld(FIn.ReadWord);
  Obj.Fill := FOpts.Fills.ConvertOld(FIn.ReadWord);
  Obj.FontStyle := FOpts.Fonts.ConvertOld(FIn.ReadInt16);
  Obj.FontColor := FIn.ReadUInt32;
  Obj.BorderStyle := FIn.ReadInt32;
  Sz := FOpts.TextExtent(Obj.Str, Obj.FontStyle);
  if Obj.Dir >= 2 then
    Obj.PointB := DPoint(Obj.PointA.x + Sz.cx, Obj.PointA.y - Sz.cy)
  else
    Obj.PointB := DPoint(Obj.PointA.x - Sz.cy, Obj.PointA.y - Sz.cx);
end;

{ ===========================================================================
  TLegacyLoader.LoadObject  (function)
  Parameters:
    Tp: Integer - whole number
  Returns:
    TDrawingObject
  Notes:
    The second switch of ReadFile: makes the object for the tag and reads it with the right
    Load. Objects that the model has no class for (xTag, drawn nowhere) are read and dropped so
    the rest of the file stays in step. Rulers keep their point as both corners, as in XML.
  =========================================================================== }
function TLegacyLoader.LoadObject(Tp: Integer): TDrawingObject;
var
  Ruler: TDrawRuler;
  Jn: TDrawJunction;
  NC: TDrawNoConnect;
  Slash: TDrawBusSlash;
  Pw: TDrawPower;
  Mf: TDrawMetaFile;
begin
  Result := nil;
  case Tp of
    Ord(xRuler):
      begin
        Ruler := TDrawRuler.Create(FOpts);
        Result := Ruler;
        Ruler.PointA := CP;
        Ruler.Horizontal := FIn.ReadInt32;
        Ruler.PointB := Ruler.PointA;
      end;
    Ord(xBus), Ord(xWire): Result := LoadLine(Tp);
    Ord(xBusName), Ord(xBusNameEx), Ord(xText), Ord(xTextEx), Ord(xTextEx2): Result := LoadText(Tp);
    Ord(xLabel), Ord(xLabelEx), Ord(xLabelEx2): Result := LoadLabel(Tp);
    Ord(xJunction):
      begin
        Jn := TDrawJunction.Create(FOpts);
        Result := Jn;
        Jn.PointA := CP;
        Jn.PointB := Jn.PointA;
      end;
    Ord(xNoConnect):
      begin
        NC := TDrawNoConnect.Create(FOpts);
        Result := NC;
        NC.PointA := CP;
        NC.PointB := NC.PointA;
      end;
    Ord(xBusSlash):
      begin
        Slash := TDrawBusSlash.Create(FOpts);
        Result := Slash;
        Slash.PointA := CP;
        Slash.Dir := FIn.ReadByte;
        Slash.PointB := Slash.PointA;
      end;
    Ord(xPower):
      begin
        Pw := TDrawPower.Create(FOpts);
        Result := Pw;
        Pw.PointA := CP;
        Pw.Which := FIn.ReadByte;
        Pw.Dir := FIn.ReadByte;
        Pw.Str := FIn.ReadString;
        Pw.PointB := Pw.PointA;
      end;
    Ord(xPin), Ord(xPinEx): Result := LoadPin(Tp);
    Ord(xLine), Ord(xLineEx), Ord(xLineEx2), Ord(xPolygon), Ord(xDash),
    Ord(xArc), Ord(xArcEx), Ord(xArcEx2): Result := LoadPolygon(Tp);
    Ord(xCircle), Ord(xCircleEx), Ord(xCircleEx2), Ord(xCircleEx3),
    Ord(xSquare), Ord(xSquareEx), Ord(xSquareEx2), Ord(xSquareEx3): Result := LoadSquare(Tp);
    Ord(xNoteText): Result := LoadNoteText;
    Ord(xMethod), Ord(xMethodEx), Ord(xMethodEx2), Ord(xMethodEx3): Result := LoadMethod(Tp);
    Ord(xTag):
      begin
        CP;                       // the tag object is not kept by the model (the XML reader drops it too)
        FIn.ReadString;
      end;
    Ord(xMetaFile):
      begin
        Mf := TDrawMetaFile.Create(FOpts);
        Result := Mf;
        Mf.PointA := CP;
        Mf.PointB := CP;
        Mf.Image := FOpts.Images.ConvertOld(FIn.ReadInt16);
      end;
  end;
end;

{ ===========================================================================
  TLegacyLoader.ReadFile  (function)
  Parameters:
    WithDetails: Boolean - flag
    List: TDrawingList
  Returns:
    Boolean
  Notes:
    The body of CTinyCadDoc::ReadFile for a binary file: the stamp (read again here, as the C++
    does for a symbol), then tag bytes until xEndFile. Tags: 3 and 129 the title block (129 also
    the grid), 131 options, 7 / 10 / 11 / 130 / 132 the font, line style, fill style, picture
    and symbol tables, 13 the layer table (dropped), and the object tags (LoadObject); any other
    tag byte is skipped without reading anything, which is how the C++ treats it. WithDetails
    False reads the options and grid and throws them away, and the title block goes to a scratch
    copy (the C++ writes it over the document's own, which a symbol never carries). An object
    that comes out empty is dropped.
  =========================================================================== }
function TLegacyLoader.ReadFile(WithDetails: Boolean; List: TDrawingList): Boolean;
var
  Tp, Before: Integer;
  Obj: TDrawingObject;
  Scratch: TDetails;
  Name: String;
  Rev, Magic: Integer;
begin
  Before := List.Count;
  Name := FIn.ReadString;
  Rev := FIn.ReadByte;
  Magic := FIn.ReadInt16;
  if (Name <> STAMP_NAME) or (Magic <> STAMP_MAGIC) or (Rev > STAMP_REVISION) then
    raise EDsnTruncated.Create(rsNotATinyCADBinaryDesign);
  repeat
    Tp := FIn.ReadByte;
    case Tp of
      Ord(xDesignInformation), Ord(xDesignInformation2):
        begin
          if WithDetails then
            ReadDetails(FSheet.Details, Tp = Ord(xDesignInformation2))
          else
          begin
            Scratch := TDetails.Create;
            try
              ReadDetails(Scratch, Tp = Ord(xDesignInformation2));
            finally
              Scratch.Free;
            end;
          end;
          if Tp = Ord(xDesignInformation2) then
            ReadSnap(WithDetails);
        end;
      Ord(xOptions): ReadOptions(WithDetails);
      Ord(xFont): LoadFontTable;
      Ord(xLineStyle): LoadStyleTable;
      Ord(xFillStyle): LoadFillTable;
      Ord(xMetaFiles): LoadMetaFileTable;
      Ord(xSymbols): LoadSymbolTable;
      Ord(xLayerTable): SkipLayerTable;
    else
      begin
        Obj := LoadObject(Tp);
        if Obj <> nil then
        begin
          if Obj.IsEmpty then
            Obj.Free
          else
            List.Add(Obj);
        end;
      end;
    end;
  until Tp = Ord(xEndFile);
  Result := List.Count > Before;
end;

{ ===========================================================================
  TLegacyLoader.Run  (function)
  Parameters:
    WithDetails: Boolean - flag
    List: TDrawingList
  Returns:
    Boolean
  Notes:
    ReadFile with the early-end handling: when the file stops in the middle of an item, the
    objects read so far are kept and a note says so.
  =========================================================================== }
function TLegacyLoader.Run(WithDetails: Boolean; List: TDrawingList): Boolean;
begin
  try
    Result := ReadFile(WithDetails, List);
  except
    on E: EDsnTruncated do
    begin
      Note('The file ended early (' + E.Message + '); what was read before that is shown');
      Result := List.Count > 0;
    end;
  end;
end;

{ ===========================================================================
  LoadLegacyDsn  (function)
  Parameters:
    S: TStream
    Sheet: TDesignSheet - the sheet
    List: TDrawingList
    WithDetails: Boolean - flag
    out Note: String - text (out: set by the call)
  Returns:
    Boolean
  Notes:
    See the unit header. The caller has already checked the stamp with IsLegacyDsn.
  =========================================================================== }
function LoadLegacyDsn(S: TStream; Sheet: TDesignSheet; List: TDrawingList;
  WithDetails: Boolean; out Note: String): Boolean;
var
  L: TLegacyLoader;
begin
  L := TLegacyLoader.Create(S, Sheet);
  try
    Result := L.Run(WithDetails, List);
    Note := L.Notes;
  finally
    L.Free;
  end;
end;

end.
