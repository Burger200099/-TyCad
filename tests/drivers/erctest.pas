{ Test driver for the design rules check (UErc); tests/run_erc.py checks what it prints against its own statement of Net.cpp.
    erctest check <vhdl 0/1> <options word> <in.dsn>   runs the check; prints "N <errors>", then for every marker "M <number> <sheet> <x> <y>" and then
                                                       every message line as "L <text>" (line ends shown as \n)
    erctest g <file>        each line a number: prints "R <%g of it>"
    erctest word <file>     each line a number: prints "R <word after unpack and pack>" }
program erctest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, UDPoint, UDrawTypes, UDrawingObjects, USymbols, UDesign, UNetList, UErc;

{ ===========================================================================
  DoCheck  (procedure)
  Parameters:
    Vhdl: Boolean - True for the VHDL check
    W: Word - the options word
    const InName: String - path of the design
  Notes:
    Test mode: runs the check on a design and prints the count, the markers and the lines.
  =========================================================================== }
procedure DoCheck(Vhdl: Boolean; W: Word; const InName: String);
var
  D: TDesignFile;
  Msgs: TStringList;
  N, I, J, Again: Integer;
  E: TDrawError;
  S: String;
begin
  D := TDesignFile.Create;
  Msgs := TStringList.Create;
  try
    D.LoadFromFile(InName);
    N := RunErc(D, ErcOptionsFromWord(W), Vhdl, True, Msgs);
    WriteLn('N ', N);
    for I := 0 to D.SheetCount - 1 do
      for J := 0 to D.Sheets[I].Drawing.Count - 1 do
        if D.Sheets[I].Drawing[J] is TDrawError then
        begin
          E := D.Sheets[I].Drawing[J] as TDrawError;
          WriteLn('M ', E.ErrorNumber, ' ', I + 1, ' ', FormatG(E.PointA.x), ' ', FormatG(E.PointA.y));
        end;
    for I := 0 to Msgs.Count - 1 do
    begin
      S := StringReplace(Msgs[I], #10, '\n', [rfReplaceAll]);
      WriteLn('L ', S);
    end;
    { a second run replaces the markers instead of stacking them }
    Msgs.Clear;
    Again := RunErc(D, ErcOptionsFromWord(W), Vhdl, False, Msgs);
    WriteLn('A ', Again, ' ', CountErcMarkers(D), ' ', Msgs.Count);
    WriteLn('C ', ClearErcMarkers(D), ' ', CountErcMarkers(D));
  finally
    Msgs.Free;
    D.Free;
  end;
end;

var
  L: TStringList;
  i: Integer;
  X: Double;
begin
  if ParamCount < 2 then begin WriteLn('usage'); Halt(2); end;
  if ParamStr(1) = 'check' then
    DoCheck(ParamStr(2) = '1', Word(StrToInt(ParamStr(3))), ParamStr(4))
  else
  begin
    L := TStringList.Create;
    try
      L.LoadFromFile(ParamStr(2));
      for i := 0 to L.Count - 1 do
        if ParamStr(1) = 'g' then
        begin
          X := StrToFloat(L[i], DefaultFormatSettings);
          WriteLn('R ', FormatG(X));
        end
        else if ParamStr(1) = 'word' then
          WriteLn('R ', ErcOptionsToWord(ErcOptionsFromWord(Word(StrToInt(L[i])))));
    finally
      L.Free;
    end;
  end;
end.
