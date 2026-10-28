{ Test driver for the parts list (UPartsList); tests/run_partslist.py checks what it writes against its own statement of TinyCAD's BOMGenerator.
    bomtest <in.dsn> <out> <type> <allsheets 0|1> <allattrs 0|1> <active sheet, 0-based> [<name shown in the heading> [<hierarchical 0|1>]]
    bomtest names <file>      each line "<kind><TAB><text><TAB><type>", kind default / ext / change / escape (text escaped with
                              the separator given in the third column), printed as "R <result>"
  type is 0 text, 1 CSV, 2 spreadsheet CSV. The file is written with plain LF line ends; the line "MISSING 0|1" printed
  tells whether TinyCAD would warn about symbols without a proper reference, and "ENTRIES n" how many entries the set held. }
program bomtest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, UDrawTypes, UDrawingObjects, USymbols, UDesign, UPartsList;

{ ===========================================================================
  DoNames  (procedure)
  Parameters:
    const FileName: String - the file of test lines
  Notes:
    Test mode: runs the file name helpers of the parts list on the lines of a file and prints
    each answer as "R <result>". A line is the kind (default, ext, change or escape), the text
    and a third value (the format number, or the separator for escape), separated by tabs.
  =========================================================================== }
procedure DoNames(const FileName: String);
var
  L: TStringList;
  i, p1, p2: Integer;
  Kind, Txt, Arg: String;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    for i := 0 to L.Count - 1 do
    begin
      p1 := Pos(#9, L[i]);
      Kind := Copy(L[i], 1, p1 - 1);
      p2 := p1 + 1;
      while (p2 <= Length(L[i])) and (L[i][p2] <> #9) do Inc(p2);
      Txt := Copy(L[i], p1 + 1, p2 - p1 - 1);
      Arg := Copy(L[i], p2 + 1, MaxInt);
      if Kind = 'default' then
        WriteLn('R ', BomDefaultFileName(Txt))
      else if Kind = 'ext' then
        WriteLn('R ', BomExtension(StrToInt(Arg)))
      else if Kind = 'change' then
        WriteLn('R ', BomChangeExtension(Txt, StrToInt(Arg)))
      else if Kind = 'escape' then
        WriteLn('R ', EscapeForCSV(Txt, Arg[1]));
    end;
  finally
    L.Free;
  end;
end;

var
  D: TDesignFile;
  B: TBomList;
  O: TBomOptions;
  S: String;
  FS: TFileStream;
  Heading: String;
begin
  if (ParamCount = 2) and (ParamStr(1) = 'names') then
  begin
    DoNames(ParamStr(2));
    Exit;
  end;
  if ParamCount < 6 then
  begin
    WriteLn(StdErr, 'usage: bomtest in.dsn out type allsheets allattrs sheet [heading]');
    Halt(2);
  end;
  D := TDesignFile.Create;
  B := TBomList.Create;
  try
    D.LoadFromFile(ParamStr(1));
    O.FileType := StrToInt(ParamStr(3));
    O.AllSheets := ParamStr(4) = '1';
    O.AllAttrs := ParamStr(5) = '1';
    O.PrefixSheet := False;
    O.PartColumns := (ParamCount >= 9) and (ParamStr(9) = '1');
    O.Hierarchical := (ParamCount >= 8) and (ParamStr(8) = '1');
    if ParamCount >= 7 then
      Heading := ParamStr(7)
    else
      Heading := ParamStr(1);
    B.Generate(D, StrToInt(ParamStr(6)), O, Heading);
    S := B.WriteFor(O.FileType, #10);
    FS := TFileStream.Create(ParamStr(2), fmCreate);
    try
      if S <> '' then
        FS.WriteBuffer(S[1], Length(S));
    finally
      FS.Free;
    end;
    WriteLn('ENTRIES ', B.Count);
    WriteLn('MISSING ', Ord(B.MissingRef));
    if B.ImportErrors <> '' then
      WriteLn('IMPORTERRORS ', StringReplace(Trim(B.ImportErrors), LineEnding, '|', [rfReplaceAll]));
  finally
    B.Free;
    D.Free;
  end;
end.
