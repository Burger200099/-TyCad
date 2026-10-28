{ Test driver for the extended title block's layout (core only); tests/run_extblock.py checks what it prints.
    blocktest layout <page width> <page height> <rulers 0|1>
        L <block left> <top> <right> <bottom>, COL five numbers, ROW seven numbers, NOTES <left> <top> <right> <bottom> <mid>, ROWH <row height>
    blocktest measure <text file>
        one MEASURE <width> line for each line of the file
    blocktest wrap <max width> <max lines> <text file>
        FONTH <height of a line of text>, then one LINE <width> <text> for each line of the wrapped text (the text file's line ends are LF) }
program blocktest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, UGeometry, UDrawingObjects, UDesign, UTitleBlock, UDrawTypes;

var
  Mode: String;
  L: TExtendedLayout;
  i: Integer;
  Opts: TDocOptions;
  Lines: TStringArray;
  SL: TStringList;
  Txt: String;
  Fs: TFormatSettings;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  Mode := ParamStr(1);
  if Mode = 'layout' then
  begin
    L := ExtendedLayout(StrToInt(ParamStr(2)), StrToInt(ParamStr(3)), ParamStr(4) = '1');
    WriteLn('L ', FloatToStr(L.BlockLeft, Fs), ' ', FloatToStr(L.BlockTop, Fs), ' ', FloatToStr(L.BlockRight, Fs), ' ', FloatToStr(L.BlockBottom, Fs));
    Write('COL');
    for i := 0 to 4 do Write(' ', FloatToStr(L.ColX[i], Fs));
    WriteLn;
    Write('ROW');
    for i := 0 to TB_ROWS do Write(' ', FloatToStr(L.RowY[i], Fs));
    WriteLn;
    WriteLn('NOTES ', FloatToStr(L.NotesLeft, Fs), ' ', FloatToStr(L.NotesTop, Fs), ' ', FloatToStr(L.NotesRight, Fs), ' ', FloatToStr(L.NotesBottom, Fs), ' ', FloatToStr(L.NotesMid, Fs));
    WriteLn('ROWH ', FloatToStr(L.RowHeight, Fs));
  end
  else if Mode = 'measure' then
  begin
    Opts := TDocOptions.Create;
    SL := TStringList.Create;
    try
      SL.LoadFromFile(ParamStr(2));
      for i := 0 to SL.Count - 1 do
        if SL[i] = '' then WriteLn('MEASURE 0') else WriteLn('MEASURE ', FloatToStr(Opts.TextExtent(SL[i], fTEXT).cx, Fs));
    finally
      SL.Free;
      Opts.Free;
    end;
  end
  else if Mode = 'wrap' then
  begin
    Opts := TDocOptions.Create;
    SL := TStringList.Create;
    try
      SL.LoadFromFile(ParamStr(4));
      Txt := StringReplace(SL.Text, LineEnding, #10, [rfReplaceAll]);
      if (Txt <> '') and (Txt[Length(Txt)] = #10) then SetLength(Txt, Length(Txt) - 1);
      WriteLn('FONTH ', FloatToStr(Opts.TextExtent('Ag', fTEXT).cy, Fs));
      Lines := WrapToWidth(Txt, StrToFloat(ParamStr(2), Fs), Opts, fTEXT, StrToInt(ParamStr(3)));
      for i := 0 to High(Lines) do
        WriteLn('LINE ', FloatToStr(Opts.TextExtent(Lines[i], fTEXT).cx, Fs), ' ', Lines[i]);
    finally
      SL.Free;
      Opts.Free;
    end;
  end;
end.
