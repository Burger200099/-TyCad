{ Test driver for the netlist writers (UNetWriters); tests/run_netwriters.py checks what it writes against its own statement of NetList.cpp.
    netwtest write <format> <in.dsn> <out> [<design name for the heading>]    write the netlist (formats 0 to 6) with plain line feeds
    netwtest vhdl <in.dsn> <path the file is written to> <out>     the VHDL file (the path gives the entity its name)
    netwtest spice <in.dsn> <out> <stamp> <error file out> [<design name>]     the SPICE file and its error text, then "R <number of errors>"
    netwtest helpers <file>    each line "<kind><TAB><text>[<TAB><arg>]": atoi, bus (arg 0..3 = internal, input, output, dont_know), decl, ref, entity, vdefault, sdefault, errname, stamp
    netwtest names <file>      each line "<kind><TAB><text><TAB><number>": kind default, ext, change, name or escape (xml); printed as "R <result>" }
program netwtest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, UDrawTypes, UDrawingObjects, USymbols, UDesign, UNetList, UNetWriters, USpiceVhdl;

{ ===========================================================================
  DoWrite  (procedure)
  Parameters:
    Fmt: Integer - whole number
    const InName: String - text
    const OutName: String - text
    const Heading: String - text
  Notes:
    Test mode: writes the netlist of a design with line feeds.
  =========================================================================== }
procedure DoWrite(Fmt: Integer; const InName, OutName, Heading: String);
var
  D: TDesignFile;
  T: String;
  FS: TFileStream;
begin
  D := TDesignFile.Create;
  try
    D.LoadFromFile(InName);
    T := NetListText(Fmt, D, Heading, #10);
    FS := TFileStream.Create(OutName, fmCreate);
    try
      if T <> '' then FS.WriteBuffer(T[1], Length(T));
    finally
      FS.Free;
    end;
  finally
    D.Free;
  end;
end;

{ ===========================================================================
  DoNames  (procedure)
  Parameters:
    const FileName: String - path of the file
  Notes:
    Test mode: runs the file name helpers on the lines of a file and prints "R <result>" for
    each.
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
      if Kind = 'default' then WriteLn('R ', NetListDefaultFileName(Txt))
      else if Kind = 'ext' then WriteLn('R ', NetListExtension(StrToInt(Arg)))
      else if Kind = 'change' then WriteLn('R ', NetListChangeExtension(Txt, StrToInt(Arg)))
      else if Kind = 'name' then WriteLn('R ', NetListFormatName(StrToInt(Arg)))
      else if Kind = 'elec' then WriteLn('R ', ElectricalTypeName(StrToInt(Arg)))
      else if Kind = 'escape' then WriteLn('R ', XmlEscape(Txt));
    end;
  finally
    L.Free;
  end;
end;

{ ===========================================================================
  WriteTextFile  (procedure)
  Parameters:
    const OutName: String - the file
    const T: String - the text
  Notes:
    Writes a text to a file.
  =========================================================================== }
procedure WriteTextFile(const OutName, T: String);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(OutName, fmCreate);
  try
    if T <> '' then FS.WriteBuffer(T[1], Length(T));
  finally
    FS.Free;
  end;
end;

{ ===========================================================================
  DoVhdl  (procedure)
  Parameters:
    const InName: String - the design
    const PathName: String - the file name given to the writer
    const OutName: String - where the text is put
  Notes:
    Test mode: writes the VHDL file of a design as it would be written to PathName (which names
    the entity), with line feeds.
  =========================================================================== }
procedure DoVhdl(const InName, PathName, OutName: String);
var
  D: TDesignFile;
begin
  D := TDesignFile.Create;
  try
    D.LoadFromFile(InName);
    WriteTextFile(OutName, VhdlText(D, PathName, #10));
  finally
    D.Free;
  end;
end;

{ ===========================================================================
  DoSpice  (procedure)
  Parameters:
    const InName: String - the design
    const OutName: String - the SPICE file
    const Stamp: String - the date and time for the first line
    const ErrName: String - the error file
    const Heading: String - the design name in the error text
  Notes:
    Test mode: writes the SPICE file and its error text with line feeds, and prints R and the
    number of errors.
  =========================================================================== }
procedure DoSpice(const InName, OutName, Stamp, ErrName, Heading: String);
var
  D: TDesignFile;
  E: String;
  N: Integer;
begin
  D := TDesignFile.Create;
  try
    D.LoadFromFile(InName);
    WriteTextFile(OutName, SpiceText(D, Heading, Stamp, #10, E, N));
    WriteTextFile(ErrName, E);
    WriteLn('R ', N);
  finally
    D.Free;
  end;
end;

{ ===========================================================================
  DoHelpers  (procedure)
  Parameters:
    const FileName: String - the file of test lines
  Notes:
    Test mode: runs the helpers of the SPICE and VHDL writers on the lines of a file and prints
    each answer as R followed by the result. A line is the kind (atoi, bus, decl, ref, entity,
    vdefault, sdefault, errname or stamp), the text and a third value, separated by tabs.
  =========================================================================== }
procedure DoHelpers(const FileName: String);
var
  L: TStringList;
  i, p1, p2: Integer;
  Kind, Txt, Arg: String;
  B: TBusProps;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    for i := 0 to L.Count - 1 do
    begin
      p1 := Pos(#9, L[i]);
      if p1 = 0 then begin Kind := L[i]; Txt := ''; Arg := ''; end
      else
      begin
        Kind := Copy(L[i], 1, p1 - 1);
        p2 := p1 + 1;
        while (p2 <= Length(L[i])) and (L[i][p2] <> #9) do Inc(p2);
        Txt := Copy(L[i], p1 + 1, p2 - p1 - 1);
        Arg := Copy(L[i], p2 + 1, MaxInt);
      end;
      if Kind = 'atoi' then WriteLn('R ', CAtoi(Txt))
      else if Kind = 'bus' then
      begin
        B := ParseBus(Txt, TBusKind(StrToInt(Arg)));
        WriteLn('R ', B.Name, #9, B.Start, #9, B.EndN, #9, Ord(B.IsBus));
      end
      else if Kind = 'decl' then WriteLn('R ', SignalDeclaration(ParseBus(Txt, TBusKind(StrToInt(Arg)))))
      else if Kind = 'ref' then WriteLn('R ', SignalReference(Txt))
      else if Kind = 'entity' then WriteLn('R ', VhdlEntityName(Txt))
      else if Kind = 'vdefault' then WriteLn('R ', VhdlDefaultFileName(Txt))
      else if Kind = 'sdefault' then WriteLn('R ', SpiceDefaultFileName(Txt))
      else if Kind = 'errname' then WriteLn('R ', SpiceErrorFileName(Txt))
      else if Kind = 'stamp' then WriteLn('R ', SpiceStamp(Now));
    end;
  finally
    L.Free;
  end;
end;

begin
  if (ParamCount = 4) and (ParamStr(1) = 'vhdl') then DoVhdl(ParamStr(2), ParamStr(3), ParamStr(4))
  else if (ParamCount >= 5) and (ParamStr(1) = 'spice') then
  begin
    if ParamCount >= 6 then DoSpice(ParamStr(2), ParamStr(3), ParamStr(4), ParamStr(5), ParamStr(6))
    else DoSpice(ParamStr(2), ParamStr(3), ParamStr(4), ParamStr(5), ParamStr(2));
  end
  else if (ParamCount = 2) and (ParamStr(1) = 'helpers') then DoHelpers(ParamStr(2))
  else if (ParamCount >= 4) and (ParamStr(1) = 'write') then
  begin
    if ParamCount >= 5 then DoWrite(StrToInt(ParamStr(2)), ParamStr(3), ParamStr(4), ParamStr(5))
    else DoWrite(StrToInt(ParamStr(2)), ParamStr(3), ParamStr(4), ParamStr(3));
  end
  else if (ParamCount = 2) and (ParamStr(1) = 'names') then DoNames(ParamStr(2))
  else
  begin
    WriteLn(StdErr, 'usage: netwtest write <format> <in.dsn> <out> [heading] | netwtest names <file>');
    Halt(2);
  end;
end.
