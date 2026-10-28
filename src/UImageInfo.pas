// SPDX-License-Identifier: LGPL-2.1-or-later
{ What can be learnt about a picture from its bytes alone, without decoding it: its kind and its size in pixels. A PNG file
  gives them in its first chunk; a JPEG in its start-of-frame marker. The picture itself is only decoded when it is drawn.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UImageInfo;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils;

const
  IMG_PNG = 'PNG';        // the type of a picture kept as PNG (a BMP is converted to PNG when it is inserted)
  IMG_JPEG = 'JPEG';      // the type of a picture kept as JPEG, byte for byte as the file was
  IMG_METAFILE = 'METAFILE';   // a Windows metafile: kept as it is, but not drawn by this port

{ the kind of picture the bytes are (IMG_PNG, IMG_JPEG), or '' if they are neither }
function DetectImageType(const Data: TBytes): String;
{ the size in pixels of a PNG or JPEG; False if the bytes are not a readable picture of that type }
function ReadImageSize(const Data: TBytes; const ImgType: String; out Width, Height: Integer): Boolean;
{ the size a picture is first given on a sheet, in design units: one unit a pixel, but never more than 500 either way, keeping the shape
  (CDrawMetaFile::determineSize, with the same whole-number arithmetic) }
procedure FitPictureSize(PixelWidth, PixelHeight: Integer; out Cx, Cy: Integer);

implementation

{ ===========================================================================
  DetectImageType  (function)
  Parameters:
    const Data: TBytes
  Returns:
    String
  Notes:
    Looks at the first bytes only: a PNG starts with its 8 byte signature, a JPEG with FF D8 FF.
  =========================================================================== }
function DetectImageType(const Data: TBytes): String;
const
  PNGSIG: array[0..7] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A);
var
  i: Integer;
  IsPng: Boolean;
begin
  Result := '';
  if Length(Data) >= 8 then
  begin
    IsPng := True;
    for i := 0 to 7 do
      if Data[i] <> PNGSIG[i] then
        IsPng := False;
    if IsPng then
      Exit(IMG_PNG);
  end;
  if (Length(Data) >= 3) and (Data[0] = $FF) and (Data[1] = $D8) and (Data[2] = $FF) then
    Result := IMG_JPEG;
end;

{ ===========================================================================
  ReadImageSize  (function)
  Parameters:
    const Data: TBytes
    const ImgType: String - text
    out Width: Integer - whole number (out: set by the call)
    out Height: Integer - whole number (out: set by the call)
  Returns:
    Boolean
  Notes:
    A PNG keeps its width and height as two big-endian numbers in the IHDR chunk that must come
    first. A JPEG keeps them in a start-of-frame marker (SOF0 to SOF15, apart from the three
    that are not frames); the markers are walked one segment at a time.
  =========================================================================== }
function ReadImageSize(const Data: TBytes; const ImgType: String; out Width, Height: Integer): Boolean;
var
  p, Len: Integer;
  M: Byte;
  function BE32(At: Integer): Integer;
  begin
    Result := (Data[At] shl 24) or (Data[At + 1] shl 16) or (Data[At + 2] shl 8) or Data[At + 3];
  end;
begin
  Result := False;
  Width := 0;
  Height := 0;
  if ImgType = IMG_PNG then
  begin
    { 8 byte signature, then a chunk: 4 bytes length, 'IHDR', width, height }
    if (Length(Data) >= 24) and (Data[12] = Ord('I')) and (Data[13] = Ord('H')) and (Data[14] = Ord('D')) and (Data[15] = Ord('R')) then
    begin
      Width := BE32(16);
      Height := BE32(20);
    end;
  end
  else if ImgType = IMG_JPEG then
  begin
    p := 2;                                  // after FF D8
    while p + 4 <= Length(Data) do
    begin
      if Data[p] <> $FF then begin
        Inc(p);
        Continue;
      end;
      M := Data[p + 1];
      if (M = $FF) then begin
        Inc(p);
        Continue;
      end;           // padding
      if (M = $D8) or (M = $01) or ((M >= $D0) and (M <= $D7)) then begin
        Inc(p, 2);
        Continue;
      end;   // markers with no length
      Len := (Data[p + 2] shl 8) or Data[p + 3];
      if (M >= $C0) and (M <= $CF) and (M <> $C4) and (M <> $C8) and (M <> $CC) then
      begin
        if p + 9 <= Length(Data) then
        begin
          Height := (Data[p + 5] shl 8) or Data[p + 6];
          Width := (Data[p + 7] shl 8) or Data[p + 8];
        end;
        Break;
      end;
      if M = $DA then
        Break;                 // start of the picture data: no frame header before it
      Inc(p, 2 + Len);
    end;
  end;
  Result := (Width > 0) and (Height > 0);
end;

{ ===========================================================================
  FitPictureSize  (procedure)
  Parameters:
    PixelWidth: Integer - whole number
    PixelHeight: Integer - whole number
    out Cx: Integer - whole number (out: set by the call)
    out Cy: Integer - whole number (out: set by the call)
  Notes:
    As TinyCAD sizes a new picture: a unit for each pixel, but if it is wider than 500 it is
    scaled down to 500 wide, and then if it is still taller than 500 it is scaled down to 500
    high, each time keeping its shape with whole-number division.
  =========================================================================== }
procedure FitPictureSize(PixelWidth, PixelHeight: Integer; out Cx, Cy: Integer);
const
  MAX_DIM = 500;
begin
  Cx := PixelWidth;
  Cy := PixelHeight;
  if Cx > MAX_DIM then
  begin
    Cy := (MAX_DIM * Cy) div Cx;
    Cx := MAX_DIM;
  end;
  if Cy > MAX_DIM then
  begin
    Cx := (MAX_DIM * Cx) div Cy;
    Cy := MAX_DIM;
  end;
end;

end.
