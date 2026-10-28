{ Test driver for the ladder rail object. Reads commands from stdin:
    HIT  ax ay bx by width px py                 distance and "selected?" at a point
    BOX  ax ay bx by width l r t b               does a selection rectangle touch it?
    SIZE ax ay bx by handle dx dy                CanResize, then ResizeBy: prints the two corners afterwards
    XML                                          save a design with a ladder, reload, print fields
    OLDXML                                       load a ladder written by the first version (numbering attributes): prints fields
  The ladder has only rails and two bus labels: the line numbers belong to the rung grid (rungtest).
  Text is measured with fixed metrics (7 units per character, 12 high) so results are exact. }
program laddertest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, UDPoint, UDrawTypes, UGeometry, UResources, UDrawingObjects, UDesign;

var
  Opts: TDocOptions;
  Tok: array of String;

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
    Formats a number for the test output.
  =========================================================================== }
function Fmt(V: Double): String; begin Result := FloatToStrF(V, ffGeneral, 15, 0); end;

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
  MakeLadder  (function)
  Parameters:
    Base: Integer - position of the first argument
  Returns:
    TDrawLadder - the ladder
  Notes:
    Builds a ladder from the command's corner points, first and last line number and line count.
  =========================================================================== }
function MakeLadder(Base: Integer): TDrawLadder;
begin
  Result := TDrawLadder.Create(Opts);
  Result.PointA := DPoint(FV(Base), FV(Base + 1));
  Result.PointB := DPoint(FV(Base + 2), FV(Base + 3));
end;

{ ===========================================================================
  CmdHIT  (procedure)
  Parameters:  none
  Notes:
    Command HIT: prints the click distance and "selected" result at a point.
  =========================================================================== }
procedure CmdHIT;
var
  L: TDrawLadder;
  P: TDPoint;
begin
  L := MakeLadder(1);
  try
    L.LineWidth := IV(5);
    P := DPoint(FV(6), FV(7));
    WriteLn('HIT ', Fmt(L.DistanceFromPoint(P)), ' ', Ord(L.IsInside(P.x, P.x, P.y, P.y)));
  finally
    L.Free;
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
  L: TDrawLadder;
begin
  L := MakeLadder(1);
  try
    L.LineWidth := IV(5);
    WriteLn('BOX ', Ord(L.IsInside(FV(6), FV(7), FV(8), FV(9))));
  finally
    L.Free;
  end;
end;

{ ===========================================================================
  CmdSIZE  (procedure)
  Parameters:  none
  Notes:
    Command SIZE: resizes the ladder by one of its handles and prints whether it can be resized
    and where its two corners are afterwards.
  =========================================================================== }
procedure CmdSIZE;
var
  L: TDrawLadder;
begin
  L := MakeLadder(1);
  try
    L.ResizeBy(IV(5), DPoint(FV(6), FV(7)));
    WriteLn('SIZE ', Ord(L.CanResize), ' ', Fmt(L.PointA.x), ' ', Fmt(L.PointA.y), ' ', Fmt(L.PointB.x), ' ', Fmt(L.PointB.y));
  finally
    L.Free;
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
  L: TDrawLadder;
  MS: TMemoryStream;
  O: TDrawingObject;
begin
  D := TDesignFile.Create;
  D2 := TDesignFile.Create;
  MS := TMemoryStream.Create;
  try
    S := D.AddSheet;
    L := TDrawLadder.Create(S.Options);
    L.PointA := DPoint(200, 100); L.PointB := DPoint(1200, 900);
    L.LeftWire := 'L1 <A>'; L.RightWire := 'N&2';
    L.LineWidth := 4; L.LineColor := $0000FF; L.FontColor := $00FF00;
    S.Drawing.Add(L);
    D.AssignIds;
    D.SaveToStream(MS);
    MS.Position := 0;
    D2.LoadFromStream(MS);
    O := D2.Sheets[0].Drawing[0];
    if O is TDrawLadder then
      with O as TDrawLadder do
        WriteLn('XML ', Id, '|', Fmt(PointA.x), ' ', Fmt(PointA.y), ' ', Fmt(PointB.x), ' ', Fmt(PointB.y), '|', LeftWire, '|', RightWire, '|',
                LineWidth, '|', IntToHex(LineColor, 6), '|', IntToHex(FontColor, 6), '|', FontStyle)
    else WriteLn('XML not a ladder: ', O.ClassName);
  finally
    MS.Free; D2.Free; D.Free;
  end;
end;

{ ===========================================================================
  CmdOLDXML  (procedure)
  Parameters:  none
  Notes:
    Command OLDXML: loads a design whose ladder carries the attributes of the first version
    (start, stop, lines, numside, a rail width in internal units) and prints what is kept.
  =========================================================================== }
procedure CmdOLDXML;
var
  D, D2: TDesignFile;
  S: TDesignSheet;
  L: TDrawLadder;
  MS: TMemoryStream;
  T: String;
  P: Integer;
  O: TDrawingObject;
begin
  D := TDesignFile.Create;
  D2 := TDesignFile.Create;
  MS := TMemoryStream.Create;
  try
    S := D.AddSheet;
    L := TDrawLadder.Create(S.Options);
    L.PointA := DPoint(200, 100); L.PointB := DPoint(1200, 900);
    S.Drawing.Add(L);
    D.AssignIds;
    D.SaveToStream(MS);
    SetString(T, PAnsiChar(MS.Memory), MS.Size);
    P := Pos('<LADDER', T);
    { splice the old attributes in, and an old-style fractional width }
    Insert(' start="5" stop="9" lines="5" numside="2"', T, P + 7);
    T := StringReplace(T, 'width=''3''', 'width=''4.6''', []);
    MS.Clear;
    MS.WriteBuffer(T[1], Length(T));
    MS.Position := 0;
    D2.LoadFromStream(MS);
    O := D2.Sheets[0].Drawing[0];
    if O is TDrawLadder then
      with O as TDrawLadder do
        WriteLn('OLDXML ', Fmt(PointA.x), ' ', Fmt(PointB.y), '|', LineWidth)
    else WriteLn('OLDXML not a ladder: ', O.ClassName);
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
  try
    Opts.Metrics.Free;
    Opts.Metrics := TFixedTextMetrics.CreateWith(7, 12);
    while not Eof(Input) do
    begin
      ReadLn(Line);
      if Trim(Line) = '' then Continue;
      Split(Line);
      if Tok[0] = 'HIT' then CmdHIT
      else if Tok[0] = 'SIZE' then CmdSIZE
      else if Tok[0] = 'OLDXML' then CmdOLDXML
      else if Tok[0] = 'BOX' then CmdBOX
      else if Tok[0] = 'XML' then CmdXML
      else WriteLn('? ', Tok[0]);
    end;
  finally
    Opts.Free;
  end;
end.
