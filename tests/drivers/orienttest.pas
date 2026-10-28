{ Test driver for the picture orientation (core only); tests/run_orient.py checks what it prints against its own statement of how turning and flipping move a picture.
    orienttest ops <file>     each line a list of operations (2 left, 3 right, 4 flip), done in order: "M a b c d turns mirror index swaps"
    orienttest map <file>     each line "<a> <b> <c> <d> <w> <h>": "R <w'> <h'>" followed by, for each pixel of the oriented picture (row by row), the index (y * w + x) of the pixel it shows }
program orienttest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, UOrient;

var
  Mode: String;
  L, Parts: TStringList;
  i, k, T, Op, W, H, DW, DH, X, Y, Sx, Sy, Idx: Integer;
  O: TOrient;
  M: Boolean;
  S: String;
begin
  Mode := ParamStr(1);
  L := TStringList.Create;
  Parts := TStringList.Create;
  try
    L.LoadFromFile(ParamStr(2));
    for i := 0 to L.Count - 1 do
    begin
      Parts.Clear;
      Parts.Delimiter := ' '; Parts.StrictDelimiter := True; Parts.DelimitedText := L[i];
      if Mode = 'ops' then
      begin
        O := OrientIdentity;
        for k := 0 to Parts.Count - 1 do
          if Parts[k] <> '' then
          begin
            Op := StrToInt(Parts[k]);
            O := OrientMul(OrientOfOp(Op), O);
          end;
        if OrientToTurns(O, T, M) then Idx := OrientIndex(O) else begin T := -1; M := False; Idx := -1; end;
        WriteLn('M ', O.A, ' ', O.B, ' ', O.C, ' ', O.D, ' ', T, ' ', Ord(M), ' ', Idx, ' ', Ord(OrientSwapsAxes(O)));
      end
      else if Mode = 'map' then
      begin
        O.A := StrToInt(Parts[0]); O.B := StrToInt(Parts[1]); O.C := StrToInt(Parts[2]); O.D := StrToInt(Parts[3]);
        W := StrToInt(Parts[4]); H := StrToInt(Parts[5]);
        OrientedSize(O, W, H, DW, DH);
        S := 'R ' + IntToStr(DW) + ' ' + IntToStr(DH);
        for Y := 0 to DH - 1 do
          for X := 0 to DW - 1 do
          begin
            OrientedSource(O, X, Y, W, H, Sx, Sy);
            S := S + ' ' + IntToStr(Sy * W + Sx);
          end;
        WriteLn(S);
      end;
    end;
  finally
    Parts.Free;
    L.Free;
  end;
end.
