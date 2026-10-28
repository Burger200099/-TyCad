{ Test harness for the step-1 units.
    xmltest corpus <file>...   walk each XML file with the reader; print tag-name counts
    xmltest sample <file>      read a few known values from a .dsn
    xmltest fmt <file>         print "%.5f" of every number listed one per line
    xmltest uu <file>          UU-encode each hex line from the file (45-byte lines), verify decode
    xmltest roundtrip <out>    write a document with the writer, read it back, check values }
program xmltest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, UDPoint, UXMLException, UXMLCodec, UXMLWriter, UXMLReader;

{ ===========================================================================
  Walk  (procedure)
  Parameters:
    R: TXMLReader - the reader
    Counts: TStringList - receives tag names with counts
  Notes:
    Walks an XML document recursively and counts the tags by name.
  =========================================================================== }
procedure Walk(R: TXMLReader; Counts: TStringList);
var
  Name: String;
  Idx: Integer;
begin
  while R.NextTag(Name) do
  begin
    Idx := Counts.IndexOf(Name);
    if Idx < 0 then Idx := Counts.AddObject(Name, TObject(PtrInt(0)));
    Counts.Objects[Idx] := TObject(PtrInt(Counts.Objects[Idx]) + 1);
    R.IntoTag;
    Walk(R, Counts);
    R.OutOfTag;
  end;
end;

{ ===========================================================================
  DoCorpus  (procedure)
  Parameters:
    const FileName: String - the XML file
  Notes:
    Test mode: reads an XML file and prints its tag counts (to compare with an independent
    parser).
  =========================================================================== }
procedure DoCorpus(const FileName: String);
var
  FS: TFileStream;
  R: TXMLReader;
  Counts: TStringList;
  i: Integer;
begin
  Counts := TStringList.Create;
  try
    Counts.Sorted := True;
    Counts.CaseSensitive := True;
    FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      try
        R := TXMLReader.Create(FS);
        try
          Walk(R, Counts);
        finally
          R.Free;
        end;
      except
        on E: EXMLException do
        begin
          WriteLn('FILE ', FileName, ' ERROR line ', E.Line);
          Exit;
        end;
      end;
    finally
      FS.Free;
    end;
    WriteLn('FILE ', FileName, ' OK');
    for i := 0 to Counts.Count - 1 do
      WriteLn('  ', Counts[i], ' ', PtrInt(Counts.Objects[i]));
  finally
    Counts.Free;
  end;
end;

{ ===========================================================================
  DoSample  (procedure)
  Parameters:
    const FileName: String - the .dsn file
  Notes:
    Test mode "sample": reads a few known values from a .dsn file with the reader and prints
    them.
  =========================================================================== }
procedure DoSample(const FileName: String);
var
  FS: TFileStream;
  R: TXMLReader;
  Name, S: String;
  W, H: Integer;
  P: TDPoint;
  Done: Boolean;
begin
  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    R := TXMLReader.Create(FS);
    try
      Done := False;
      while R.NextTag(Name) do
        if Name = 'TinyCAD' then
        begin
          R.IntoTag;
          while R.NextTag(Name) do
            if Name = 'DETAILS' then
            begin
              R.IntoTag;
              while R.NextTag(Name) do
              begin
                if Name = 'Size' then
                begin
                  W := 0; H := 0;
                  R.GetAttribute('width', W);
                  R.GetAttribute('height', H);
                  WriteLn('size ', W, ' ', H);
                end
                else if Name = 'TITLE' then
                begin
                  R.GetChildData(S);
                  WriteLn('title [', S, ']');
                end;
              end;
              R.OutOfTag;
            end
            else if (Name = 'SYMBOLDEF') and not Done then
            begin
              R.IntoTag;
              while R.NextTag(Name) do
                if Name = 'TinyCAD' then
                begin
                  R.IntoTag;
                  while R.NextTag(Name) do
                    if (Name = 'POLYGON') and not Done then
                    begin
                      P := DPointInvalid;
                      R.GetAttribute('pos', P);
                      WriteLn('first polygon pos ', FormatFloat('0.###', P.x), ' ', FormatFloat('0.###', P.y));
                      Done := True;
                    end;
                  R.OutOfTag;
                end;
              R.OutOfTag;
            end;
          R.OutOfTag;
        end;
    finally
      R.Free;
    end;
  finally
    FS.Free;
  end;
end;

{ ===========================================================================
  DoFmt  (procedure)
  Parameters:
    const FileName: String - file of numbers
  Notes:
    Test mode: prints numbers formatted with the C-compatible formatter for comparison with C
    printf.
  =========================================================================== }
procedure DoFmt(const FileName: String);
var
  L: TStringList;
  i: Integer;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    for i := 0 to L.Count - 1 do
      WriteLn(FormatFixed5(CAtoF(L[i])));
  finally
    L.Free;
  end;
end;

{ ===========================================================================
  HexToBytes  (function)
  Parameters:
    const S: String - hex digits
  Returns:
    TBytes - the bytes
  Notes:
    Converts hex text to bytes.
  =========================================================================== }
function HexToBytes(const S: String): TBytes;
var
  i: Integer;
begin
  SetLength(Result, Length(S) div 2);
  for i := 0 to High(Result) do
    Result[i] := StrToInt('$' + Copy(S, i * 2 + 1, 2));
end;

{ ===========================================================================
  DoUU  (procedure)
  Parameters:
    const FileName: String - file with one hex string per line
  Notes:
    Test mode "uu": UU-encodes each line of hex from the file (45-byte lines), decodes it again
    and checks it matches.
  =========================================================================== }
procedure DoUU(const FileName: String);
var
  L: TStringList;
  i, j, n: Integer;
  B, Back: TBytes;
  Dec: TUUDecoder;
  Line: String;
  Text: String;
  Bad: Integer;
begin
  Bad := 0;
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    for i := 0 to L.Count - 1 do
    begin
      B := HexToBytes(Trim(L[i]));
      Text := '';
      j := 0;
      while j < Length(B) do
      begin
        n := Length(B) - j;
        if n > 45 then n := 45;
        Line := UUEncodeLine(@B[j], n);
        Text := Text + Line + #10;
        WriteLn('E ', i, ' ', StringReplace(Line, ' ', '~', [rfReplaceAll]));
        Inc(j, n);
      end;
      Dec := TUUDecoder.Create(Length(B));
      try
        for j := 1 to Length(Text) do Dec.Feed(Ord(Text[j]));
        Back := Dec.Data;
      finally
        Dec.Free;
      end;
      if (Length(Back) <> Length(B)) or ((Length(B) > 0) and not CompareMem(@Back[0], @B[0], Length(B))) then
      begin
        WriteLn('DECODE MISMATCH on vector ', i);
        Inc(Bad);
      end;
    end;
  finally
    L.Free;
  end;
  WriteLn('uu decode failures: ', Bad);
end;

{ ===========================================================================
  DoRoundTrip  (procedure)
  Parameters:
    const OutName: String - the file to write
  Notes:
    Test mode "roundtrip": writes a document with the writer, reads it back and checks the
    values.
  =========================================================================== }
procedure DoRoundTrip(const OutName: String);
var
  FS: TFileStream;
  W: TXMLWriter;
  R: TXMLReader;
  Name, S: String;
  I: Integer;
  D: Double;
  P: TDPoint;
  Col: Cardinal;
  U: Cardinal;
  Blob, Back: TBytes;
  k, Fail: Integer;
begin
  SetLength(Blob, 200);
  for k := 0 to High(Blob) do Blob[k] := Byte((k * 37 + 11) and $FF);
  Blob[3] := 0; Blob[4] := 0; Blob[5] := 0; // zero bytes -> spaces in this uuencode variant

  FS := TFileStream.Create(OutName, fmCreate);
  try
    W := TXMLWriter.Create(FS);
    try
      W.AddComment('round trip test');
      W.AddTag('TinyCAD');
      W.AddTag('DETAILS');
      W.AddTag('TITLE', 'A <b> & "q" ''s''');
      W.AddTag('COUNT', -42);
      W.AddTag('VALUE', 3.14159265);
      W.AddTag('PT', DPoint(12.5, -7));
      W.AddTagColor('COLOR', $00FF8000);
      W.AddTag('GRID');
      W.AddAttribute('spacing', 50);
      W.AddAttribute('name', 'x&y');
      W.AddAttributeUInt('big', 4000000000);
      W.AddAttribute('at', DPoint(-4, -10));
      W.CloseTag;
      W.CloseTag; // DETAILS
      W.AddTag('BLOB');
      W.AddChildDataUUEncode(@Blob[0], Length(Blob));
      W.CloseTag;
      W.CloseTag; // TinyCAD
      WriteLn('writer line counter: ', W.LineCounter);
    finally
      W.Free;
    end;
  finally
    FS.Free;
  end;

  Fail := 0;
  FS := TFileStream.Create(OutName, fmOpenRead);
  try
    R := TXMLReader.Create(FS);
    try
      while R.NextTag(Name) do
      begin
        R.IntoTag;
        while R.NextTag(Name) do
        begin
          if Name = 'DETAILS' then
          begin
            R.IntoTag;
            while R.NextTag(Name) do
            begin
              if Name = 'TITLE' then begin R.GetChildData(S); if S <> 'A <b> & "q" ''s''' then begin Inc(Fail); WriteLn('FAIL title [', S, ']'); end; end
              else if Name = 'COUNT' then begin R.GetChildData(I); if I <> -42 then begin Inc(Fail); WriteLn('FAIL count ', I); end; end
              else if Name = 'VALUE' then begin R.GetChildData(D); if Abs(D - 3.14159) > 1e-9 then begin Inc(Fail); WriteLn('FAIL value ', D); end; end
              else if Name = 'PT' then begin P := DPointInvalid; R.GetChildData(P); if (Abs(P.x - 12.5) > 1e-4) or (Abs(P.y + 7) > 1e-4) then begin Inc(Fail); WriteLn('FAIL pt'); end; end
              else if Name = 'COLOR' then begin Col := 0; R.GetChildDataColor(Col); if Col <> $00FF8000 then begin Inc(Fail); WriteLn('FAIL color ', IntToHex(Col, 6)); end; end
              else if Name = 'GRID' then
              begin
                I := 0; R.GetAttribute('spacing', I);
                S := ''; R.GetAttribute('name', S);
                U := 0; R.GetAttributeUInt('big', U);
                P := DPointInvalid; R.GetAttribute('at', P);
                WriteLn('grid spacing=', I, ' name=', S, ' at=', FormatFloat('0.###', P.x), ',', FormatFloat('0.###', P.y));
                if (I <> 50) or (S <> 'x&y') or (Abs(P.x + 4) > 1e-4) or (Abs(P.y + 10) > 1e-4) then begin Inc(Fail); WriteLn('FAIL grid'); end;
              end;
            end;
            R.OutOfTag;
          end
          else if Name = 'BLOB' then
          begin
            R.IntoTag;
            while R.NextTag(Name) do
              if Name = 'UUENCODE' then
              begin
                R.GetChildDataUUDecode(Back);
                if (Length(Back) <> Length(Blob)) or not CompareMem(@Back[0], @Blob[0], Length(Blob)) then
                begin Inc(Fail); WriteLn('FAIL uu blob'); end
                else WriteLn('uu blob ok (', Length(Back), ' bytes)');
              end;
            R.OutOfTag;
          end;
        end;
        R.OutOfTag;
      end;
    finally
      R.Free;
    end;
  finally
    FS.Free;
  end;
  WriteLn('roundtrip failures: ', Fail);
end;

var
  i: Integer;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultSystemCodePage := CP_UTF8;
  if ParamCount < 2 then begin WriteLn('usage: see header'); Halt(2); end;
  if ParamStr(1) = 'corpus' then
    for i := 2 to ParamCount do DoCorpus(ParamStr(i))
  else if ParamStr(1) = 'sample' then DoSample(ParamStr(2))
  else if ParamStr(1) = 'fmt' then DoFmt(ParamStr(2))
  else if ParamStr(1) = 'uu' then DoUU(ParamStr(2))
  else if ParamStr(1) = 'roundtrip' then DoRoundTrip(ParamStr(2));
end.
