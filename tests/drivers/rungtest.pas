{ Test driver for the rung grid (the sheet's hidden spreadsheet of rung numbers). Reads commands from stdin; the first eight numbers of every
  command describe the sheet and the grid:  pagew pageh inset margin rows start pages continue   (page size and border inset in design units,
  the indent in mm), and then the command's own arguments:
    LAYOUT <8>                  area, row height, number column width, the columns of each page, the row height text
    AT <8> x y                  the rung number at a point (or "none")
    NUM <8> page row            the number shown for a row of a page
    HIT <8> showheight x y      distance and "selected?" at a point
    BOX <8> showheight l r t b  does a selection rectangle touch it?
    MOVE <8>                    Shift and RotateAbout leave it where it is: prints the area before and after
    XML                         save a design with a grid, reload it, print every setting; also the Clone
    PROPS                       get and set the 'rungs.*' properties (UProps), with bad values
    BAD                         a file with out-of-range settings is brought into range
  Text is measured with fixed metrics (7 units per character, 12 high) so results are exact. }
program rungtest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, UDPoint, UDrawTypes, UGeometry, UResources, UDrawingObjects, UDesign, UProps;

type
  { answers the options' question about the page }
  TPageHolder = class
  public
    G: TPageGeometry;
    function Geo: TPageGeometry;
  end;

var
  Opts: TDocOptions;
  Holder: TPageHolder;
  Tok: array of String;

{ ===========================================================================
  TPageHolder.Geo  (function)
  Parameters:  none
  Returns:
    TPageGeometry - the page size and border inset
  Notes:
    Answers the options' question about the page with the geometry the current test command set.
  =========================================================================== }
function TPageHolder.Geo: TPageGeometry;
begin
  Result := G;
end;

{ ===========================================================================
  FV  (function)
  Parameters:
    k: Integer - token position
  Returns:
    Double - the number
  Notes:
    Reads token k of the command as a number.
  =========================================================================== }
function FV(k: Integer): Double; begin Result := StrToFloat(Tok[k]); end;

{ ===========================================================================
  IV  (function)
  Parameters:
    k: Integer - token position
  Returns:
    Integer - the integer
  Notes:
    Reads token k of the command as an integer.
  =========================================================================== }
function IV(k: Integer): Integer; begin Result := StrToInt(Tok[k]); end;

{ ===========================================================================
  Fmt  (function)
  Parameters:
    V: Double - the number
  Returns:
    String - the text
  Notes:
    Formats a number for the test output (up to 12 significant digits).
  =========================================================================== }
function Fmt(V: Double): String; begin Result := FloatToStrF(V, ffGeneral, 12, 0); end;

{ ===========================================================================
  Split  (procedure)
  Parameters:
    const Line: String - the line
  Notes:
    Splits a command line into tokens.
  =========================================================================== }
procedure Split(const Line: String);
var
  Sl: TStringList;
  k: Integer;
begin
  Sl := TStringList.Create;
  try
    Sl.Delimiter := ' '; Sl.StrictDelimiter := True; Sl.DelimitedText := Trim(Line);
    SetLength(Tok, Sl.Count);
    for k := 0 to Sl.Count - 1 do Tok[k] := Sl[k];
  finally
    Sl.Free;
  end;
end;

{ ===========================================================================
  MakeGrid  (function)
  Parameters:  none
  Returns:
    TDrawRungGrid
  Notes:
    Builds the grid described by tokens 1..8
  =========================================================================== }
function MakeGrid: TDrawRungGrid;
begin
  Holder.G.Width := FV(1); Holder.G.Height := FV(2); Holder.G.BorderInset := FV(3);
  Result := TDrawRungGrid.Create(Opts);
  Result.MarginMm := FV(4);
  Result.Rows := IV(5);
  Result.StartNumber := IV(6);
  Result.Pages := IV(7);
  Result.ContinueNumbers := IV(8) <> 0;
end;

{ ===========================================================================
  R  (function)
  Parameters:
    const B: TDRect - the rectangle
  Returns:
    String - the text
  Notes:
    Formats a rectangle as 'left top right bottom' for the test output.
  =========================================================================== }
function R(const B: TDRect): String;
begin
  Result := Fmt(B.Left) + ' ' + Fmt(B.Top) + ' ' + Fmt(B.Right) + ' ' + Fmt(B.Bottom);
end;

{ ===========================================================================
  CmdLAYOUT  (procedure)
  Parameters:  none
  Notes:
    Command LAYOUT: prints the grid's area, row height, number column width and row height text,
    then every column of every page.
  =========================================================================== }
procedure CmdLAYOUT;
var
  G: TDrawRungGrid;
  P, C: Integer;
begin
  G := MakeGrid;
  try
    WriteLn('AREA ', R(G.AreaRect), ' ', Fmt(G.RowHeight), ' ', Fmt(G.NumberColumnWidth), ' [', G.HeightText, ']');
    for P := 0 to G.Pages - 1 do
      for C := 0 to 1 do
        WriteLn('COL ', P, ' ', C, ' ', R(G.ColumnRect(P, C)));
    WriteLn('END');
  finally
    G.Free;
  end;
end;

{ ===========================================================================
  CmdAT  (procedure)
  Parameters:  none
  Notes:
    Command AT: prints the rung number at a point, or none.
  =========================================================================== }
procedure CmdAT;
var
  G: TDrawRungGrid;
  N: Integer;
begin
  G := MakeGrid;
  try
    if G.LineNumberAt(DPoint(FV(9), FV(10)), N) then
      WriteLn('AT ', N)
    else
      WriteLn('AT none');
  finally
    G.Free;
  end;
end;

{ ===========================================================================
  CmdNUM  (procedure)
  Parameters:  none
  Notes:
    Command NUM: prints the number shown for a row of a page and the rectangle of its cell.
  =========================================================================== }
procedure CmdNUM;
var
  G: TDrawRungGrid;
begin
  G := MakeGrid;
  try
    WriteLn('NUM ', G.NumberAt(IV(9), IV(10)), ' ', R(G.CellRect(IV(9), IV(10))));
  finally
    G.Free;
  end;
end;

{ ===========================================================================
  CmdHIT  (procedure)
  Parameters:  none
  Notes:
    Command HIT: prints the click distance and "selected" result at a point.
  =========================================================================== }
procedure CmdHIT;
var
  G: TDrawRungGrid;
  P: TDPoint;
begin
  G := MakeGrid;
  try
    G.ShowRowHeight := IV(9) <> 0;
    P := DPoint(FV(10), FV(11));
    WriteLn('HIT ', Fmt(G.DistanceFromPoint(P)), ' ', Ord(G.IsInside(P.x, P.x, P.y, P.y)));
  finally
    G.Free;
  end;
end;

{ ===========================================================================
  CmdBOX  (procedure)
  Parameters:  none
  Notes:
    Command BOX: whether a selection rectangle touches the ladder.
  =========================================================================== }
procedure CmdBOX;
var
  G: TDrawRungGrid;
begin
  G := MakeGrid;
  try
    G.ShowRowHeight := IV(9) <> 0;
    WriteLn('BOX ', Ord(G.IsInside(FV(10), FV(11), FV(12), FV(13))));
  finally
    G.Free;
  end;
end;

{ ===========================================================================
  CmdMOVE  (procedure)
  Parameters:  none
  Notes:
    Command MOVE: shifts and rotates the grid every way it can be asked to and prints whether
    anything changed, and whether it can be resized.
  =========================================================================== }
procedure CmdMOVE;
var
  G: TDrawRungGrid;
  A, B: String;
  D: Integer;
begin
  G := MakeGrid;
  try
    G.PointA := DPoint(10, 20); G.PointB := DPoint(30, 40);
    A := R(G.AreaRect) + '|' + Fmt(G.PointA.x) + ' ' + Fmt(G.PointA.y) + ' ' + Fmt(G.PointB.x) + ' ' + Fmt(G.PointB.y);
    G.Shift(DPoint(123, -77));
    for D := 0 to 7 do
      G.RotateAbout(DPoint(300, 200), D);
    B := R(G.AreaRect) + '|' + Fmt(G.PointA.x) + ' ' + Fmt(G.PointA.y) + ' ' + Fmt(G.PointB.x) + ' ' + Fmt(G.PointB.y);
    WriteLn('MOVE ', Ord(A = B), ' ', Ord(G.CanResize));
  finally
    G.Free;
  end;
end;

{ ===========================================================================
  CmdXML  (procedure)
  Parameters:  none
  Notes:
    Command XML: saves a design containing a ladder, reloads it and prints every property.
  =========================================================================== }
procedure CmdXML;
var
  D, D2: TDesignFile;
  S: TDesignSheet;
  G: TDrawRungGrid;
  MS: TMemoryStream;
  O: TDrawingObject;
  C: TDrawingObject;
begin
  D := TDesignFile.Create;
  D2 := TDesignFile.Create;
  MS := TMemoryStream.Create;
  try
    S := D.AddSheet;
    G := TDrawRungGrid.Create(S.Options);
    G.Rows := 33; G.StartNumber := 101; G.MarginMm := 7.5; G.Pages := 2; G.ContinueNumbers := False; G.ShowRowHeight := False;
    G.FontColor := $0000FF;
    S.Drawing.Add(G);
    D.AssignIds;
    D.SaveToStream(MS);
    MS.Position := 0;
    D2.LoadFromStream(MS);
    O := D2.Sheets[0].Drawing[0];
    if O is TDrawRungGrid then
      with O as TDrawRungGrid do
        WriteLn('XML ', Id, '|', Rows, '|', StartNumber, '|', Fmt(MarginMm), '|', Pages, '|', Ord(ContinueNumbers), '|', Ord(ShowRowHeight), '|', IntToHex(FontColor, 6), '|', FontStyle, '|', Ord(GetType = xRungGrid))
    else WriteLn('XML not a rung grid: ', O.ClassName);
    C := G.Clone;
    try
      with C as TDrawRungGrid do
        WriteLn('CLONE ', Id, '|', Rows, '|', StartNumber, '|', Fmt(MarginMm), '|', Pages, '|', Ord(ContinueNumbers), '|', Ord(ShowRowHeight), '|', IntToHex(FontColor, 6));
    finally
      C.Free;
    end;
  finally
    MS.Free; D2.Free; D.Free;
  end;
end;

{ ===========================================================================
  CmdPROPS  (procedure)
  Parameters:  none
  Notes:
    Command PROPS: lists the grid's properties, sets and reads each through UProps, and tries
    bad and out-of-range values.
  =========================================================================== }
procedure CmdPROPS;
var
  G: TDrawRungGrid;
  V: String;
  Defs: TPropDefArray;
  i: Integer;
  Names: String;
begin
  Holder.G.Width := 1485; Holder.G.Height := 1050; Holder.G.BorderInset := 0;
  G := TDrawRungGrid.Create(Opts);
  try
    Defs := ObjectProps(G);
    Names := '';
    for i := 0 to High(Defs) do
      Names := Names + Defs[i].Name + ',';
    WriteLn('DEFS ', Names);
    SetProp(G, 'rungs.rows', '35'); SetProp(G, 'rungs.start', '-3'); SetProp(G, 'rungs.margin', '12.5');
    SetProp(G, 'rungs.pages', '2 pages'); SetProp(G, 'rungs.continue', '0'); SetProp(G, 'rungs.showheight', '0');
    for i := 0 to 5 do
    begin
      case i of
        0: GetProp(G, 'rungs.rows', V);
        1: GetProp(G, 'rungs.start', V);
        2: GetProp(G, 'rungs.margin', V);
        3: GetProp(G, 'rungs.pages', V);
        4: GetProp(G, 'rungs.continue', V);
      else
        GetProp(G, 'rungs.showheight', V);
      end;
      Write('GET ', V, '|');
    end;
    WriteLn;
    { bad values leave the setting; out-of-range ones are brought into range }
    SetProp(G, 'rungs.rows', 'abc'); SetProp(G, 'rungs.start', 'x'); SetProp(G, 'rungs.margin', '-4'); SetProp(G, 'rungs.pages', 'nonsense');
    WriteLn('BADVALUES ', G.Rows, ' ', G.StartNumber, ' ', Fmt(G.MarginMm), ' ', G.Pages);
    SetProp(G, 'rungs.rows', '0'); WriteLn('ROWS0 ', G.Rows);
    SetProp(G, 'rungs.rows', '5000'); WriteLn('ROWS5000 ', G.Rows);
    SetProp(G, 'rungs.pages', '1 page'); WriteLn('PAGES1 ', G.Pages);
  finally
    G.Free;
  end;
end;

{ ===========================================================================
  CmdBAD  (procedure)
  Parameters:  none
  Notes:
    Command BAD: loads a file whose rung grid has out-of-range settings and prints what they
    were brought to.
  =========================================================================== }
procedure CmdBAD;
var
  D, D2: TDesignFile;
  S: TDesignSheet;
  G: TDrawRungGrid;
  MS: TMemoryStream;
  T: String;
  O: TDrawingObject;
begin
  D := TDesignFile.Create;
  D2 := TDesignFile.Create;
  MS := TMemoryStream.Create;
  try
    S := D.AddSheet;
    G := TDrawRungGrid.Create(S.Options);
    S.Drawing.Add(G);
    D.AssignIds;
    D.SaveToStream(MS);
    SetString(T, PAnsiChar(MS.Memory), MS.Size);
    T := StringReplace(T, 'rows=''20''', 'rows=''0''', []);
    T := StringReplace(T, 'pages=''1''', 'pages=''7''', []);
    T := StringReplace(T, 'margin=''5.00000''', 'margin=''-3''', []);
    T := StringReplace(T, 'margin=''5''', 'margin=''-3''', []);
    MS.Clear;
    MS.WriteBuffer(T[1], Length(T));
    MS.Position := 0;
    D2.LoadFromStream(MS);
    O := D2.Sheets[0].Drawing[0];
    with O as TDrawRungGrid do
      WriteLn('BAD ', Rows, ' ', Pages, ' ', Fmt(MarginMm));
  finally
    MS.Free; D2.Free; D.Free;
  end;
end;

var
  Line: String;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultFormatSettings.DecimalSeparator := '.';
  DefaultSystemCodePage := CP_UTF8;
  Opts := TDocOptions.Create;
  Holder := TPageHolder.Create;
  try
    Opts.Metrics.Free;
    Opts.Metrics := TFixedTextMetrics.CreateWith(7, 12);
    Opts.OnPageGeometry := @Holder.Geo;
    while not Eof(Input) do
    begin
      ReadLn(Line);
      if Trim(Line) = '' then Continue;
      Split(Line);
      if Tok[0] = 'LAYOUT' then CmdLAYOUT
      else if Tok[0] = 'AT' then CmdAT
      else if Tok[0] = 'NUM' then CmdNUM
      else if Tok[0] = 'HIT' then CmdHIT
      else if Tok[0] = 'BOX' then CmdBOX
      else if Tok[0] = 'MOVE' then CmdMOVE
      else if Tok[0] = 'XML' then CmdXML
      else if Tok[0] = 'PROPS' then CmdPROPS
      else if Tok[0] = 'BAD' then CmdBAD
      else WriteLn('? ', Tok[0]);
    end;
  finally
    Holder.Free;
    Opts.Free;
  end;
end.
