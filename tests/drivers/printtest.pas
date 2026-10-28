{ Test driver for the printing arithmetic (UPrint); tests/run_print.py checks what it prints against its own statement of TinyCadView.cpp and SpecialPrintDlg.cpp.
    printtest layout <horz mm> <vert mm> <dpi> <sheet width> <sheet height> <scale> <all sheets 0/1> <sheet count>
        prints "L <cols> <rows> <sheets> <pages> <zoom>" and then, for every page, "P <number> <sheet> <col> <row> <origin x> <origin y>"
    printtest fit <horz mm> <vert mm> <sheet width> <sheet height>     prints the scale that fits the sheet on a page
    printtest text <number>      prints the scale text of the number between [ and ]
    printtest value <text>       prints the number read from the text
    printtest range <pages> <from> <to>      prints "R <1 if anything> <first> <last>"
    printtest batch              reads such commands from the input, the words separated by tabs, and ends each answer with a line "--" }
program printtest;

{$mode objfpc}{$H+}

uses
  SysUtils, UDPoint, UPrint;

{ ===========================================================================
  Num  (function)
  Parameters:
    X: Double - horizontal position or value
  Returns:
    String - the number
  Notes:
    Converts script text to a number using a dot as the decimal separator.
  =========================================================================== }
function Num(X: Double): String;
begin
  Result := FloatToStrF(X, ffGeneral, 17, 0);
end;

var
  Args: array of String;

{ ===========================================================================
  Arg  (function)
  Parameters:
    N: Integer - whole number
  Returns:
    String
  Notes:
    One word of the command being run.
  =========================================================================== }
function Arg(N: Integer): String;
begin
  if N <= High(Args) then Result := Args[N] else Result := '';
end;

{ ===========================================================================
  Handle  (procedure)
  Parameters:  none
  Notes:
    Runs the command held in Args and prints its answer.
  =========================================================================== }
procedure Handle;
var
  Dev: TPrintDevice;
  L: TPrintLayout;
  P: TPrintPage;
  I, F, T: Integer;
  Any: Boolean;
begin
  if Arg(0) = 'layout' then
  begin
    Dev := PrintDevice(StrToInt(Arg(1)), StrToInt(Arg(2)), StrToInt(Arg(3)));
    L := PrintLayoutFor(Dev, StrToInt(Arg(4)), StrToInt(Arg(5)), StrToFloat(Arg(6)), Arg(7) = '1', StrToInt(Arg(8)));
    WriteLn('L ', L.Cols, ' ', L.Rows, ' ', L.Sheets, ' ', L.Pages, ' ', Num(L.Zoom));
    for I := 1 to L.Pages do
    begin
      P := PrintPageAt(L, Dev, I);
      WriteLn('P ', I, ' ', P.Sheet, ' ', P.Col, ' ', P.Row, ' ', P.OriginX, ' ', P.OriginY);
    end;
  end
  else if Arg(0) = 'fit' then
  begin
    Dev := PrintDevice(StrToInt(Arg(1)), StrToInt(Arg(2)), 300);
    WriteLn(Num(PrintFitScale(Dev, StrToInt(Arg(3)), StrToInt(Arg(4)))));
  end
  else if Arg(0) = 'text' then
    WriteLn('[', PrintScaleText(StrToFloat(Arg(1))), ']')
  else if Arg(0) = 'value' then
    WriteLn(Num(PrintScaleValue(Arg(1))))
  else if Arg(0) = 'range' then
  begin
    Any := PrintRangePages(StrToInt(Arg(1)), StrToInt(Arg(2)), StrToInt(Arg(3)), F, T);
    WriteLn('R ', Ord(Any), ' ', F, ' ', T);
  end
  else Halt(2);
end;

var
  Line: String;
  I: Integer;
begin
  DefaultFormatSettings.DecimalSeparator := '.';
  if ParamCount < 1 then Halt(2);
  if ParamStr(1) = 'batch' then
  begin
    { one command a line (the words after the first tab are one word, so text with spaces can be sent), each answer ends with a line "--" }
    while not EOF do
    begin
      ReadLn(Line);
      SetLength(Args, 0);
      while Line <> '' do
      begin
        I := Pos(#9, Line);
        SetLength(Args, Length(Args) + 1);
        if I = 0 then begin Args[High(Args)] := Line; Line := ''; end
        else begin Args[High(Args)] := Copy(Line, 1, I - 1); Delete(Line, 1, I); end;
      end;
      if Length(Args) > 0 then Handle;
      WriteLn('--');
    end;
  end
  else
  begin
    SetLength(Args, ParamCount);
    for I := 1 to ParamCount do Args[I - 1] := ParamStr(I);
    Handle;
  end;
end.
