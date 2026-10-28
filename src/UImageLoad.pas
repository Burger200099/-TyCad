// SPDX-License-Identifier: LGPL-2.1-or-later
{ Reading a picture file to put in a design, and decoding a picture of a design to draw it (the part of pictures that needs the
  screen library; what is kept in the design is in UResources and UImageInfo).

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UImageLoad;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Graphics, GraphType, IntfGraphics, UImageInfo, UResources, UOrient;

{ Read a picture file for inserting. A PNG or JPEG is kept exactly as it is; a BMP is converted to PNG (as TinyCAD does). False, with
  Err saying why, if the file is missing, is not a picture of a kind that can be inserted, or cannot be read. }
function LoadPictureFile(const FileName: String; out ImgType: String; out Data: TBytes; out Err: String): Boolean;
{ A picture of the design as something that can be drawn: decoded the first time and kept in the picture's Cache. nil if it
  cannot be decoded (or is a kind this port does not draw), which is then not tried again. }
function PictureOf(Img: TImageResource): TGraphic;
{ the same picture turned and flipped as an orientation says (UOrient): its pixels rearranged, none lost or blurred; made when first wanted and kept }
function OrientedPictureOf(Img: TImageResource; const O: TOrient): TGraphic;

implementation


uses UStrings;

type
  { stands in the Cache of a picture that could not be decoded, so that the attempt is not repeated for every redraw }
  TUndecodable = class
  end;

{ ===========================================================================
  ReadFileBytes  (function)
  Parameters:
    const FileName: String - the file
    out Data: TBytes - receives the bytes
  Returns:
    Boolean - True if it was read
  Notes:
    Reads a whole file into memory; False (and empty data) if it cannot be read.
  =========================================================================== }
function ReadFileBytes(const FileName: String; out Data: TBytes): Boolean;
var
  FS: TFileStream;
begin
  Result := False;
  SetLength(Data, 0);
  try
    FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Data, FS.Size);
      if FS.Size > 0 then
        FS.ReadBuffer(Data[0], FS.Size);
      Result := True;
    finally
      FS.Free;
    end;
  except
    Result := False;
  end;
end;

{ ===========================================================================
  LoadPictureFile  (function)
  Parameters:
    const FileName: String - path of the file
    out ImgType: String - text (out: set by the call)
    out Data: TBytes - out: set by the call
    out Err: String - text (out: set by the call)
  Returns:
    Boolean
  Notes:
    Chosen by the file's extension, as TinyCAD does: .png and .jpg / .jpeg / .jpe are kept byte
    for byte (after checking that they are what they say and that their size can be read); .bmp
    is loaded and saved as a PNG. A Windows metafile (.emf) is not supported here; anything else
    is an unknown kind of picture.
  =========================================================================== }
function LoadPictureFile(const FileName: String; out ImgType: String; out Data: TBytes; out Err: String): Boolean;
var
  Ext: String;
  W, H: Integer;
  Bmp: TBitmap;
  Png: TPortableNetworkGraphic;
  MS: TMemoryStream;
begin
  Result := False;
  ImgType := '';
  SetLength(Data, 0);
  Err := '';
  Ext := LowerCase(ExtractFileExt(FileName));
  if Ext = '' then begin
    Err := rsUnknownImageFileType;
    Exit;
  end;
  if Ext = '.emf' then begin
    Err := rsWindowsMetafilesEmfCannotBe;
    Exit;
  end;
  if Ext = '.bmp' then
  begin
    Bmp := TBitmap.Create;
    Png := TPortableNetworkGraphic.Create;
    MS := TMemoryStream.Create;
    try
      try
        Bmp.LoadFromFile(FileName);
        Png.Assign(Bmp);
        Png.SaveToStream(MS);
        SetLength(Data, MS.Size);
        if MS.Size > 0 then
          Move(MS.Memory^, Data[0], MS.Size);
        ImgType := IMG_PNG;
        Result := ReadImageSize(Data, ImgType, W, H);
        if not Result then
          Err := rsUnableToReadTheImage;
      except
        Err := rsUnableToOpenImageFile;
      end;
    finally
      MS.Free;
      Png.Free;
      Bmp.Free;
    end;
    Exit;
  end;
  if (Ext <> '.png') and (Ext <> '.jpg') and (Ext <> '.jpeg') and (Ext <> '.jpe') then
  begin
    Err := rsUnknownImageFileType;
    Exit;
  end;
  if not ReadFileBytes(FileName, Data) then begin
    Err := rsCannotOpenFile;
    Exit;
  end;
  ImgType := DetectImageType(Data);
  if (ImgType = '') or ((Ext = '.png') <> (ImgType = IMG_PNG)) or (not ReadImageSize(Data, ImgType, W, H)) then
  begin
    Err := Format(rsThatFileIsNotA2, [UpperCase(Copy(Ext, 2, MaxInt))]);
    SetLength(Data, 0);
    ImgType := '';
    Exit;
  end;
  Result := True;
end;

{ ===========================================================================
  PictureOf  (function)
  Parameters:
    Img: TImageResource
  Returns:
    TGraphic
  Notes:
    PNG and JPEG are decoded with the screen library the first time they are needed; the result
    is kept in Img.Cache. A picture of any other type, an empty one, or one that does not decode
    is remembered as undecodable.
  =========================================================================== }
function PictureOf(Img: TImageResource): TGraphic;
var
  G: TGraphic;
  MS: TMemoryStream;
begin
  Result := nil;
  if Img = nil then
    Exit;
  if Img.Cache is TGraphic then
    Exit(TGraphic(Img.Cache));
  if Img.Cache <> nil then
    Exit;                   // already tried
  if (Length(Img.Data) = 0) or ((Img.ImgType <> IMG_PNG) and (Img.ImgType <> IMG_JPEG)) then
  begin
    Img.Cache := TUndecodable.Create;
    Exit;
  end;
  if Img.ImgType = IMG_PNG then
    G := TPortableNetworkGraphic.Create
  else
    G := TJPEGImage.Create;
  MS := TMemoryStream.Create;
  try
    try
      MS.WriteBuffer(Img.Data[0], Length(Img.Data));
      MS.Position := 0;
      G.LoadFromStream(MS);
      Img.Cache := G;
      Result := G;
    except
      G.Free;
      Img.Cache := TUndecodable.Create;
    end;
  finally
    MS.Free;
  end;
end;

{ ===========================================================================
  OrientedPictureOf  (function)
  Parameters:
    Img: TImageResource
    const O: TOrient
  Returns:
    TGraphic
  Notes:
    The picture's pixels are rearranged exactly as UOrient says (none lost or blurred), once for
    each orientation it is drawn in, and the result is kept in the picture's cache. A fast path
    copies whole 32 bit pixels; any other kind of picture goes pixel by pixel.
  =========================================================================== }
function OrientedPictureOf(Img: TImageResource; const O: TOrient): TGraphic;
var
  Idx, X, Y, W, H, DW, DH, Sx, Sy: Integer;
  Src: TGraphic;
  SrcBmp, DstBmp: TBitmap;
  SrcImg, DstImg: TLazIntfImage;
begin
  Result := PictureOf(Img);
  if Result = nil then
    Exit;
  Idx := OrientIndex(O);
  if Idx <= 0 then
    Exit;                                  // upright (or not one of the eight, which cannot happen)
  if Img.Oriented[Idx] is TGraphic then
    Exit(TGraphic(Img.Oriented[Idx]));
  Src := Result;
  SrcBmp := TBitmap.Create;
  DstBmp := TBitmap.Create;
  SrcImg := nil;
  DstImg := nil;
  try
    SrcBmp.Assign(Src);
    W := SrcBmp.Width; H := SrcBmp.Height;
    OrientedSize(O, W, H, DW, DH);
    SrcImg := SrcBmp.CreateIntfImage;
    DstImg := TLazIntfImage.Create(0, 0);
    DstImg.DataDescription := SrcImg.DataDescription;
    DstImg.SetSize(DW, DH);
    if SrcImg.DataDescription.BitsPerPixel = 32 then
    begin
      for Y := 0 to DH - 1 do
        for X := 0 to DW - 1 do
        begin
          OrientedSource(O, X, Y, W, H, Sx, Sy);
          PCardinal(DstImg.GetDataLineStart(Y))[X] := PCardinal(SrcImg.GetDataLineStart(Sy))[Sx];
        end;
    end
    else
      for Y := 0 to DH - 1 do
        for X := 0 to DW - 1 do
        begin
          OrientedSource(O, X, Y, W, H, Sx, Sy);
          DstImg.Colors[X, Y] := SrcImg.Colors[Sx, Sy];
        end;
    DstBmp.LoadFromIntfImage(DstImg);
    Img.Oriented[Idx] := DstBmp;
    DstBmp := nil;                                        // (now the picture's)
    Result := TGraphic(Img.Oriented[Idx]);
  finally
    DstBmp.Free;
    SrcBmp.Free;
    SrcImg.Free;
    DstImg.Free;
  end;
end;

end.
