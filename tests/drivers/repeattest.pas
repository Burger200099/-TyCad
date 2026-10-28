{ Test driver for the repeat functions (core only); tests/run_repeat.py checks what it prints against its own statement of TinyCAD's rules.
    repeattest label <file>    each line "<dir><TAB><text>": the text for the next label or text, as "R <text>"
    repeattest number <file>   each line "<step><TAB><text>": the next pin number or name
    repeattest pin <file>      each line "<pin dir><TAB><name dir><TAB><number><TAB><name>": the next pin's number and name, as "R <number><TAB><name>" }
program repeattest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, URepeat;

var
  Mode: String;
  L: TStringList;
  i, p1, p2, p3: Integer;
  Num, Nm, Line: String;
begin
  Mode := ParamStr(1);
  L := TStringList.Create;
  try
    L.LoadFromFile(ParamStr(2));
    for i := 0 to L.Count - 1 do
    begin
      Line := L[i];
      p1 := Pos(#9, Line);
      if Mode = 'label' then
        WriteLn('R ', IncrementLabelText(Copy(Line, p1 + 1, MaxInt), StrToInt(Copy(Line, 1, p1 - 1))))
      else if Mode = 'number' then
        WriteLn('R ', IncrementNumber(Copy(Line, p1 + 1, MaxInt), StrToInt(Copy(Line, 1, p1 - 1))))
      else if Mode = 'pin' then
      begin
        p2 := p1 + Pos(#9, Copy(Line, p1 + 1, MaxInt));
        p3 := p2 + Pos(#9, Copy(Line, p2 + 1, MaxInt));
        Num := Copy(Line, p2 + 1, p3 - p2 - 1);
        Nm := Copy(Line, p3 + 1, MaxInt);
        NextPinValues(Num, Nm, StrToInt(Copy(Line, 1, p1 - 1)), StrToInt(Copy(Line, p1 + 1, p2 - p1 - 1)));
        WriteLn('R ', Num, #9, Nm);
      end;
    end;
  finally
    L.Free;
  end;
end.
