// SPDX-License-Identifier: LGPL-2.1-or-later
{ Helpers shared by the XML reader and writer:
  - TinyCAD's (non-standard) uuencode variant, byte-compatible with XMLWriter.cpp / XMLReader.cpp
  - C-runtime style number parsing/formatting (atoi, atof, strtol(...,16), sscanf %lg, printf %.5f)
    so files round-trip exactly like the C++ build, independent of the user's locale. }
unit UXMLCodec;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, UDPoint;

{ ---- uuencode (TinyCAD variant: value 0 is encoded as ' ', not '`') ---- }

{ Encode up to 45 bytes as one text line, including the leading length character.
  No line terminator is added. }
function UUEncodeLine(P: PByte; Count: Integer): String;

type
  { State machine identical to CXMLReader::uudecode }
  TUUDecoder = class
  private
    FData: array of Byte;
    FPos: Integer;       // next write position in FData
    FRemaining: Integer; // m_uu_size
    FState: Integer;
    FLineSize: Integer;
    FBytes: array[0..3] of Integer;
  public
    constructor Create(ASize: Integer);
    procedure Feed(Ch: Byte);
    function Data: TBytes;
  end;

{ ---- C-style conversions ---- }
function CAtoI(const S: String): Integer;            // _tstoi
function CAtoF(const S: String): Double;             // _tstof
function CHexToInt(const S: String): Cardinal;       // _tcstol(s, &end, 16)
function CScanPoint(const S: String; var P: TDPoint): Boolean; // sscanf("%lg,%lg") + unit conversion
function FormatFixed5(V: Double): String;            // "%.5f" (exact, matches C printf)
function FormatPoint(const P: TDPoint): String;      // "%.5f,%.5f" in XML (mm) units

implementation

{ ===========================================================================
  UUEnc  (function)
  Parameters:
    C: Integer - value 0-63
  Returns:
    Char - the character
  Notes:
    UU-encodes one 6-bit value as a printable character (the ENC macro of uuencode).
  =========================================================================== }
function UUEnc(C: Integer): Char; inline;
begin
  Result := Chr((C and $3F) + 32); // ENC(c) = ((c) & 077) + ' '
end;

{ ===========================================================================
  UUEncodeLine  (function)
  Parameters:
    P: PByte - pointer to the bytes
    Count: Integer - number of bytes (limited to 45)
  Returns:
    String - the encoded line
  Notes:
    UU-encodes up to 45 bytes as one text line: a length character then groups of four
    characters for each three bytes.
  =========================================================================== }
function UUEncodeLine(P: PByte; Count: Integer): String;
var
  i, n, i0, i1, i2: Integer;
begin
  if Count > 45 then
    Count := 45;
  Result := UUEnc(Count);
  i := 0;
  n := Count;
  while n > 0 do
  begin
    i0 := P[i]; Inc(i);
    i1 := 0; i2 := 0;
    if i < Count then begin
      i1 := P[i];
      Inc(i);
    end;
    if i < Count then begin
      i2 := P[i];
      Inc(i);
    end;
    Result := Result + UUEnc(i0 shr 2)
                     + UUEnc(((i0 shl 4) and $30) or ((i1 shr 4) and $0F))
                     + UUEnc(((i1 shl 2) and $3C) or ((i2 shr 6) and $03))
                     + UUEnc(i2 and $3F);
    Dec(n, 3);
  end;
end;

{ ===========================================================================
  TUUDecoder.Create  (constructor)
  Parameters:
    ASize: Integer - whole number
  Notes:
    TUUDecoder
  =========================================================================== }
constructor TUUDecoder.Create(ASize: Integer);
begin
  inherited Create;
  SetLength(FData, ASize);
  FRemaining := ASize;
  FPos := 0;
  FState := 0;
end;

{ ===========================================================================
  UUDec  (function)
  Parameters:
    C: Integer - the character code
  Returns:
    Integer - value 0-63
  Notes:
    Decodes one UU character to its 6-bit value (the DEC macro).
  =========================================================================== }
function UUDec(C: Integer): Integer; inline;
begin
  Result := (C - 32) and $3F; // DEC(c) = (((c) - ' ') & 077)
end;

{ ===========================================================================
  TUUDecoder.Feed  (procedure)
  Parameters:
    Ch: Byte - the next character
  Notes:
    Feeds one character of UU-encoded text to the decoder, which collects the decoded bytes;
    handles the length character and the groups of four.
  =========================================================================== }
procedure TUUDecoder.Feed(Ch: Byte);
var
  c: array[0..2] of Integer;
  i: Integer;
begin
  case FState of
    0: begin
         if Ch in [9, 10, 13, 32] then
           Exit; // whitespace between lines
         FLineSize := UUDec(Ch);
         FState := 1;
       end;
    1..3: begin
         FBytes[FState - 1] := Ch;
         Inc(FState);
       end;
    4: begin
         FBytes[3] := Ch;
         c[0] := (UUDec(FBytes[0]) shl 2) or (UUDec(FBytes[1]) shr 4);
         c[1] := (UUDec(FBytes[1]) shl 4) or (UUDec(FBytes[2]) shr 2);
         c[2] := (UUDec(FBytes[2]) shl 6) or UUDec(FBytes[3]);
         for i := 0 to 2 do
           if (FLineSize > 0) and (FRemaining > 0) then
           begin
             FData[FPos] := Byte(c[i] and $FF); // C++ casts to BYTE (truncates)
             Inc(FPos);
             Dec(FLineSize);
             Dec(FRemaining);
           end;
         if FLineSize = 0 then
           FState := 0
         else
           FState := 1;
       end;
  end;
end;

{ ===========================================================================
  TUUDecoder.Data  (function)
  Parameters:  none
  Returns:
    TBytes - the decoded bytes
  Notes:
    The bytes decoded so far.
  =========================================================================== }
function TUUDecoder.Data: TBytes;
begin
  Result := FData;
end;

{ ---- C-style scanning ---- }

{ ===========================================================================
  IsWS  (function)
  Parameters:
    C: Char - the character
  Returns:
    Boolean - True for white space
  Notes:
    Whether a character is C white space (space, tab, newline, vertical tab, form feed, return).
  =========================================================================== }
function IsWS(C: Char): Boolean; inline;
begin
  Result := C in [' ', #9, #10, #11, #12, #13];
end;

{ Scan a C floating point literal starting at Pos (1-based). On success Pos moves
  past it. Mirrors what strtod/%lg accept for ordinary decimal input. }

{ ===========================================================================
  ScanDouble  (function)
  Parameters:
    const S: String - the text
    var Pos: Integer - 1-based position to start at; moved past the number on success
    out V: Double - set to the number
  Returns:
    Boolean - True if a number was found
  Notes:
    Scans a C-style decimal floating point number from a string, as strtod would for ordinary
    input, and moves the position past it.
  =========================================================================== }
function ScanDouble(const S: String; var Pos: Integer; out V: Double): Boolean;
var
  i, startPos, digits: Integer;
  Code: Integer;
begin
  Result := False;
  V := 0;
  i := Pos;
  while (i <= Length(S)) and IsWS(S[i]) do Inc(i);
  startPos := i;
  if (i <= Length(S)) and (S[i] in ['+', '-']) then
    Inc(i);
  digits := 0;
  while (i <= Length(S)) and (S[i] in ['0'..'9']) do begin
    Inc(i);
    Inc(digits);
  end;
  if (i <= Length(S)) and (S[i] = '.') then
  begin
    Inc(i);
    while (i <= Length(S)) and (S[i] in ['0'..'9']) do begin
      Inc(i);
      Inc(digits);
    end;
  end;
  if digits = 0 then
    Exit;
  if (i <= Length(S)) and (S[i] in ['e', 'E']) then
  begin
    // exponent only counts if followed by (sign) digits
    Code := i + 1;
    if (Code <= Length(S)) and (S[Code] in ['+', '-']) then
      Inc(Code);
    if (Code <= Length(S)) and (S[Code] in ['0'..'9']) then
    begin
      while (Code <= Length(S)) and (S[Code] in ['0'..'9']) do Inc(Code);
      i := Code;
    end;
  end;
  Val(Copy(S, startPos, i - startPos), V, Code);
  if Code <> 0 then begin
    V := 0;
    Exit;
  end;
  Pos := i;
  Result := True;
end;

{ ===========================================================================
  CAtoI  (function)
  Parameters:
    const S: String - the text
  Returns:
    Integer - the value (0 if there are no digits)
  Notes:
    Converts text to an integer the way C's atoi does: skips white space, accepts a sign, stops
    at the first non-digit.
  =========================================================================== }
function CAtoI(const S: String): Integer;
var
  i: Integer;
  Neg: Boolean;
  Acc: Int64;
begin
  i := 1;
  while (i <= Length(S)) and IsWS(S[i]) do Inc(i);
  Neg := False;
  if (i <= Length(S)) and (S[i] in ['+', '-']) then
  begin
    Neg := S[i] = '-';
    Inc(i);
  end;
  Acc := 0;
  while (i <= Length(S)) and (S[i] in ['0'..'9']) do
  begin
    if Acc < 2147483648 then
      Acc := Acc * 10 + (Ord(S[i]) - 48);
    Inc(i);
  end;
  if Neg then
    Acc := -Acc;
  if Acc > High(Integer) then
    Acc := High(Integer);
  if Acc < Low(Integer) then
    Acc := Low(Integer);
  Result := Integer(Acc);
end;

{ ===========================================================================
  CAtoF  (function)
  Parameters:
    const S: String - the text
  Returns:
    Double - the value
  Notes:
    Converts text to a number the way C's atof does (0 when there is no number).
  =========================================================================== }
function CAtoF(const S: String): Double;
var
  p: Integer;
  V: Double;
begin
  p := 1;
  if not ScanDouble(S, p, V) then
    V := 0;
  Result := V;
end;

{ ===========================================================================
  CHexToInt  (function)
  Parameters:
    const S: String - hex digits
  Returns:
    Cardinal - the value
  Notes:
    Converts hexadecimal text (as used for colors in XML) to a number like C's strtoul with base
    16.
  =========================================================================== }
function CHexToInt(const S: String): Cardinal;
var
  i: Integer;
  Neg: Boolean;
  Acc: QWord;
  d: Integer;
begin
  i := 1;
  while (i <= Length(S)) and IsWS(S[i]) do Inc(i);
  Neg := False;
  if (i <= Length(S)) and (S[i] in ['+', '-']) then
  begin
    Neg := S[i] = '-';
    Inc(i);
  end;
  if (i + 1 <= Length(S)) and (S[i] = '0') and (S[i + 1] in ['x', 'X']) then
    Inc(i, 2);
  Acc := 0;
  while i <= Length(S) do
  begin
    case S[i] of
      '0'..'9': d := Ord(S[i]) - 48;
      'a'..'f': d := Ord(S[i]) - 87;
      'A'..'F': d := Ord(S[i]) - 55;
    else
      Break;
    end;
    Acc := (Acc shl 4) or QWord(d);
    Inc(i);
  end;
  if Neg then
    Acc := QWord(-Int64(Acc));
  Result := Cardinal(Acc and $FFFFFFFF);
end;

{ ===========================================================================
  CScanPoint  (function)
  Parameters:
    const S: String - the text
    var P: TDPoint - the point to fill in (in/out)
  Returns:
    Boolean - True if both numbers were read
  Notes:
    Reads "x,y" in millimetres as sscanf would and stores it in internal units; a field that
    does not parse leaves that coordinate untouched.
  =========================================================================== }
function CScanPoint(const S: String; var P: TDPoint): Boolean;
var
  p0: Integer;
  X, Y: Double;
begin
  { sscanf semantics: fields that fail to parse leave the target untouched }
  Result := False;
  p0 := 1;
  if not ScanDouble(S, p0, X) then
  begin
    P.x := UnmakeXMLUnits(P.x);
    P.y := UnmakeXMLUnits(P.y);
    Exit;
  end;
  P.x := X;
  if (p0 <= Length(S)) and (S[p0] = ',') then
  begin
    Inc(p0);
    if ScanDouble(S, p0, Y) then
    begin
      P.y := Y;
      Result := True;
    end;
  end;
  P.x := UnmakeXMLUnits(P.x);
  P.y := UnmakeXMLUnits(P.y);
end;

{ ===========================================================================
  FormatFixed5  (function)
  Parameters:
    V: Double - the number
  Returns:
    String - the text with five decimals
  Notes:
    Formats a number exactly like C's printf("%.5f") whatever the locale: the double is split
    into mantissa and exponent and rounded exactly (ties to even), unlike Free Pascal's Str
    which can round the wrong way near a boundary.
  =========================================================================== }
function FormatFixed5(V: Double): String;
{ Exact equivalent of C's printf("%.5f"), locale independent.
  FPC's Str() converts through a ~17 digit decimal approximation and rounds that, which
  can round the wrong way for values near a rounding boundary (and rounds exact ties
  away from zero where C rounds to even).  Here the double is split into mantissa and
  exponent and A*10^5 is rounded exactly with 128-bit integer arithmetic.
  Values >= 1e9 and NaN/Inf fall back to Str(). }
var
  Bits, M, Hi, Lo, Q, Pl, Ph, Rl, Rh, HalfH, HalfL, Mask: QWord;
  Expo, Sh: Integer;
  A: Double;
  Neg, RoundUp: Boolean;
begin
  Bits := PQWord(@V)^;
  Neg := (Bits shr 63) <> 0;
  Expo := Integer((Bits shr 52) and $7FF);
  A := Abs(V);
  if (Expo = $7FF) or (A >= 1.0E9) then
  begin
    Str(V:0:5, Result);
    Exit;
  end;
  M := Bits and QWord($000FFFFFFFFFFFFF);
  if Expo = 0 then
    Sh := 1074
  else
  begin
    M := M or QWord($0010000000000000);
    Sh := 1075 - Expo;                // A = M / 2^Sh
  end;
  if (M = 0) then
    Q := 0
  else
  begin
    // 128-bit product P = M * 100000 as (Hi, Lo)
    Pl := (M and $FFFFFFFF) * 100000;
    Ph := (M shr 32) * 100000;
    Hi := Ph shr 32;
    Lo := (Ph and $FFFFFFFF) shl 32;
    Lo := Lo + Pl;
    if Lo < Pl then
      Inc(Hi);
    if Sh >= 128 then
    begin
      Q := 0; Rh := Hi; Rl := Lo;                  // remainder is the whole product
      HalfH := QWord(1) shl (Sh - 1 - 64); HalfL := 0;   // (only reached for Sh<=191, see below)
      if Sh > 191 then begin
        HalfH := High(QWord);
        HalfL := High(QWord);
      end;
    end
    else if Sh >= 64 then
    begin
      Q := Hi shr (Sh - 64);
      if Sh = 64 then
        Mask := 0
      else
        Mask := (QWord(1) shl (Sh - 64)) - 1;
      Rh := Hi and Mask; Rl := Lo;
      if Sh = 64 then begin
        HalfH := 0;
        HalfL := QWord(1) shl 63;
      end
      else begin
        HalfH := QWord(1) shl (Sh - 1 - 64);
        HalfL := 0;
      end;
    end
    else
    begin
      Q := (Lo shr Sh) or (Hi shl (64 - Sh));
      Mask := (QWord(1) shl Sh) - 1;
      Rh := 0; Rl := Lo and Mask;
      HalfH := 0; HalfL := QWord(1) shl (Sh - 1);
    end;
    RoundUp := (Rh > HalfH) or ((Rh = HalfH) and (Rl > HalfL));
    if (Rh = HalfH) and (Rl = HalfL) then
      RoundUp := Odd(Q);   // exact tie: round half to even
    if RoundUp then
      Inc(Q);
  end;
  Result := IntToStr(Q div 100000) + '.' + Format('%.5d', [Int64(Q mod 100000)]);
  if Neg then
    Result := '-' + Result;
end;

{ ===========================================================================
  FormatPoint  (function)
  Parameters:
    const P: TDPoint - the point in internal units
  Returns:
    String - the text
  Notes:
    Formats a point as "x,y" in millimetres with five decimals, as it is written in XML.
  =========================================================================== }
function FormatPoint(const P: TDPoint): String;
begin
  Result := FormatFixed5(MakeXMLUnits(P.x)) + ',' + FormatFixed5(MakeXMLUnits(P.y));
end;

end.
