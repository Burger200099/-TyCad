{ Test driver for pictures in a design (core only, no screen). Everything it prints or writes is checked by tests/run_image.py
  against an independent implementation of TinyCAD's uuencode.
    imagetest make <picture file> <out.dsn> [x1 y1 x2 y2]   a one-sheet design holding that picture (an IMAGE and a METAFILE object)
    imagetest dump <design.dsn> <prefix>                    every picture of the design written to <prefix><n>.bin; prints IMG id type bytes and OBJ a b id
    imagetest resave <in.dsn> <out.dsn>                     load and save again
    imagetest size <picture file>                           the type and size in pixels
    imagetest fit <width> <height>                          the size on the sheet for a picture of that many pixels }
program imagetest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, UDPoint, UDrawTypes, UResources, UDrawingObjects, UDesign, UImageInfo;

{ ===========================================================================
  ReadAll  (function)
  Parameters:
    const FileName: String - the file
  Returns:
    TBytes - its bytes
  Notes:
    Reads a whole file into memory (test driver).
  =========================================================================== }
function ReadAll(const FileName: String): TBytes;
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, FS.Size);
    if FS.Size > 0 then FS.ReadBuffer(Result[0], FS.Size);
  finally
    FS.Free;
  end;
end;

var
  Mode, T: String;
  D: TDesignFile;
  Sh: TDesignSheet;
  Data: TBytes;
  Id, i, k, w, h, cx, cy: Integer;
  Obj: TDrawMetaFile;
  Img: TImageResource;
  FS: TFileStream;
  Seen: array of Boolean;
begin
  Mode := ParamStr(1);
  if Mode = 'size' then
  begin
    Data := ReadAll(ParamStr(2));
    T := DetectImageType(Data);
    if (T <> '') and ReadImageSize(Data, T, w, h) then WriteLn('SIZE ', T, ' ', w, ' ', h) else WriteLn('SIZE none');
    Exit;
  end;
  if Mode = 'fit' then
  begin
    FitPictureSize(StrToInt(ParamStr(2)), StrToInt(ParamStr(3)), cx, cy);
    WriteLn('FIT ', cx, ' ', cy);
    Exit;
  end;
  D := TDesignFile.Create;
  try
    if Mode = 'make' then
    begin
      Data := ReadAll(ParamStr(2));
      T := DetectImageType(Data);
      Sh := D.AddSheet;
      Id := Sh.Options.AddImage(T, Data);
      Obj := TDrawMetaFile.Create(Sh.Options);
      Obj.Image := Id;
      if ReadImageSize(Data, T, w, h) then Obj.FitToPicture(w, h);
      if ParamCount >= 7 then
      begin
        Obj.PointA := DPoint(StrToFloat(ParamStr(4)), StrToFloat(ParamStr(5)));
        Obj.PointB := DPoint(StrToFloat(ParamStr(6)), StrToFloat(ParamStr(7)));
      end;
      Sh.Drawing.Add(Obj);
      D.SaveToFile(ParamStr(3));
      WriteLn('MADE ', T, ' ', Id);
    end
    else if (Mode = 'dump') or (Mode = 'resave') then
    begin
      D.LoadFromFile(ParamStr(2));
      for k := 0 to D.SheetCount - 1 do
      begin
        Sh := D.Sheets[k];
        for i := 0 to Sh.Drawing.Count - 1 do
          if Sh.Drawing[i] is TDrawMetaFile then
          begin
            Obj := TDrawMetaFile(Sh.Drawing[i]);
            WriteLn('OBJ ', k, ' ', Obj.PointA.x:0:3, ',', Obj.PointA.y:0:3, ' ', Obj.PointB.x:0:3, ',', Obj.PointB.y:0:3, ' ', Obj.Image);
            if Mode = 'dump' then
            begin
              Img := TImageResource(Sh.Options.Images.Get(Obj.Image));
              WriteLn('IMG ', Obj.Image, ' ', Img.ImgType, ' ', Length(Img.Data));
              FS := TFileStream.Create(ParamStr(3) + IntToStr(Obj.Image) + '.bin', fmCreate);
              try
                if Length(Img.Data) > 0 then FS.WriteBuffer(Img.Data[0], Length(Img.Data));
              finally
                FS.Free;
              end;
            end;
          end;
      end;
      if Mode = 'resave' then D.SaveToFile(ParamStr(3));
    end;
  finally
    D.Free;
  end;
end.
