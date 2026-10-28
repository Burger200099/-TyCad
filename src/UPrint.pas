// SPDX-License-Identifier: LGPL-2.1-or-later
{ The arithmetic of printing a design: how many pages a sheet takes at a print scale, which part
  of which sheet each page shows, the print zoom, and the scale text of the Print dialog. No
  drawing and no printer here; the printer (or the preview, or a test) only has to tell this unit
  how big its page is.

  This is CTinyCadView::OnBeginPrinting, OnPrepareDC and CTinyCadView::DoPreparePrinting's "fit to
  page" figure, and CSpecialPrintDlg's use of the scale text, with the same integer and floating
  point steps, so a design is cut into the same pages as in TinyCAD.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UPrint;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, UDPoint;

const
  { the Print dialog refuses a scale above this: TinyCAD takes any number and would try to make
    millions of pages }
  PRINT_MAX_SCALE = 10000;
  PRINT_DEFAULT_SCALE = 100.0;       // CTinyCadRegistry::GetPrintScale's default

type
  { page numbers, from 1 }
  TPageArray = array of Integer;

  { what a printer says about its page (GetDeviceCaps): the printable width and height in whole
    millimetres in the orientation it prints in, and its resolution in dots per inch }
  TPrintDevice = record
    HorzMm, VertMm: Integer;
    Dpi: Integer;
  end;

  TPrintLayout = record
    Cols, Rows: Integer;     // the pages across and down one sheet
    Sheets: Integer;         // the sheets printed: 1 for the current sheet, else all of them
    AllSheets: Boolean;
    Pages: Integer;          // Cols * Rows * Sheets
    Scale: Double;           // the print scale, per cent
    Zoom: Double;            // printer pixels per internal unit
  end;

  TPrintPage = record
    Sheet: Integer;          // index into the sheets printed (0 = the current sheet when not all)
    Col, Row: Integer;
    OriginX, OriginY: Integer;  // the internal position of the page's top left corner
  end;

function PrintDevice(HorzMm, VertMm, Dpi: Integer): TPrintDevice;
{ the scale that makes a whole sheet fit on one page (m_FitScale) }
function PrintFitScale(const Dev: TPrintDevice; PageW, PageH: Integer): Double;
{ printer pixels per internal unit at a scale, as OnBeginPrinting works it out }
function PrintZoom(Dpi: Integer; Scale: Double): Double;
{ the pages of a sheet at a scale; SheetCount is the number of sheets in the design }
function PrintLayoutFor(const Dev: TPrintDevice; PageW, PageH: Integer; Scale: Double;
  AllSheets: Boolean; SheetCount: Integer): TPrintLayout;
{ what page number PageNo (from 1) shows }
function PrintPageAt(const L: TPrintLayout; const Dev: TPrintDevice; PageNo: Integer): TPrintPage;
{ the scale as the Print dialog shows it, printf's "%3.3lg" }
function PrintScaleText(V: Double): String;
{ the scale as the Print dialog reads it, atof }
function PrintScaleValue(const S: String): Double;
{ printf's %g with a given number of significant digits and a minimum field width }
function FormatCG(V: Double; Prec, Width: Integer): String;
{ the number atof reads from the start of a string; 0 when there is none }
function CAtof(const S: String): Double;
{ the pages to print: the first and last, from a range the user chose (0 for no range) }
function PrintRangePages(Pages, FromPage, ToPage: Integer; out First, Last: Integer): Boolean;
{ the pages a typed page range names (1-2, 6 / 1 to 6 and 9 ...), in order and without repeats; False and Err when it cannot be read }
function ParsePageRange(const S: String; MaxPage: Integer; out Pages: TPageArray; out Err: String): Boolean;
{ pages as text, runs joined: 1-3, 6 }
function PageListText(const Pages: TPageArray): String;

implementation


uses UStrings;

{ ===========================================================================
  PrintDevice  (function)
  Parameters:
    HorzMm: Integer - printable width of the page, mm
    VertMm: Integer - printable height of the page, mm
    Dpi: Integer - printer resolution
  Returns:
    TPrintDevice - the three numbers together
  Notes:
    Builds the description of a printer's page.
  =========================================================================== }
function PrintDevice(HorzMm, VertMm, Dpi: Integer): TPrintDevice;
begin
  Result.HorzMm := HorzMm;
  Result.VertMm := VertMm;
  Result.Dpi := Dpi;
end;

{ ===========================================================================
  PrintFitScale  (function)
  Parameters:
    const Dev: TPrintDevice - the printer page
    PageW: Integer - sheet width, internal units
    PageH: Integer - sheet height, internal units
  Returns:
    Double - the scale, per cent
  Notes:
    The largest scale at which the whole sheet fits on one page (the longer printer side against
    the longer side of a landscape sheet, or against the height of a portrait one), as
    DoPreparePrinting works out m_FitScale. 100 when a size is nought.
  =========================================================================== }
function PrintFitScale(const Dev: TPrintDevice; PageW, PageH: Integer): Double;
var
  W, H: Integer;
begin
  W := Max(Dev.HorzMm, Dev.VertMm);
  H := Min(Dev.HorzMm, Dev.VertMm);
  if (PageW <= 0) or (PageH <= 0) then
    Exit(PRINT_DEFAULT_SCALE);
  if PageW < PageH then
    Result := Min((W * 100 * PIXELSPERMM) / PageH, (H * 100 * PIXELSPERMM) / PageW)
  else
    Result := Min((W * 100 * PIXELSPERMM) / PageW, (H * 100 * PIXELSPERMM) / PageH);
end;

{ ===========================================================================
  PrintZoom  (function)
  Parameters:
    Dpi: Integer - printer resolution
    Scale: Double - print scale, per cent
  Returns:
    Double - printer pixels for each internal unit
  Notes:
    The zoom OnBeginPrinting gives the transform: dpi * 1000 / (5 * 254) as an integer division
    (the pixels of a unit at 100 per cent, times 100), times the scale over 100, over 100.
  =========================================================================== }
function PrintZoom(Dpi: Integer; Scale: Double): Double;
var
  Z: Double;
begin
  Z := (Dpi * 1000) div (PIXELSPERMM * 254);
  Z := (Z * Scale) / 100.0;
  Result := Z / 100.0;
end;

{ ===========================================================================
  PrintLayoutFor  (function)
  Parameters:
    const Dev: TPrintDevice - the printer page
    PageW: Integer - sheet width, internal units
    PageH: Integer - sheet height, internal units
    Scale: Double - print scale, per cent
    AllSheets: Boolean - True to print every sheet
    SheetCount: Integer - number of sheets in the design
  Returns:
    TPrintLayout - columns, rows, pages and zoom
  Notes:
    OnBeginPrinting: the sheet's size at the scale, over the printer's page (its long side along
    the sheet's long side, whichever way the sheet is turned), gives the pages across and down;
    a part of a page left over counts as a page unless it is 0.01 of one or less. A scale so
    small that nothing is left still takes one page (TinyCAD would then print no pages and
    fail).
  =========================================================================== }
function PrintLayoutFor(const Dev: TPrintDevice; PageW, PageH: Integer; Scale: Double;
  AllSheets: Boolean; SheetCount: Integer): TPrintLayout;
var
  Width, Height, SX, SY: Double;
begin
  Width := Max(Dev.HorzMm, Dev.VertMm) * PIXELSPERMM;
  Height := Min(Dev.HorzMm, Dev.VertMm) * PIXELSPERMM;
  if Width < 1 then
    Width := 1;
  if Height < 1 then
    Height := 1;
  if PageW < PageH then
  begin
    SX := (Scale * PageW / Height) / 100.0;
    SY := (Scale * PageH / Width) / 100.0;
  end
  else
  begin
    SX := (Scale * PageW / Width) / 100.0;
    SY := (Scale * PageH / Height) / 100.0;
  end;
  Result.Cols := Trunc(SX);
  Result.Rows := Trunc(SY);
  if SX - Trunc(SX) > 0.01 then
    Inc(Result.Cols);
  if SY - Trunc(SY) > 0.01 then
    Inc(Result.Rows);
  if Result.Cols < 1 then
    Result.Cols := 1;
  if Result.Rows < 1 then
    Result.Rows := 1;
  Result.AllSheets := AllSheets;
  if AllSheets and (SheetCount > 1) then
    Result.Sheets := SheetCount
  else
    Result.Sheets := 1;
  Result.Pages := Result.Cols * Result.Rows * Result.Sheets;
  Result.Scale := Scale;
  Result.Zoom := PrintZoom(Dev.Dpi, Scale);
end;

{ ===========================================================================
  PrintPageAt  (function)
  Parameters:
    const L: TPrintLayout - the layout
    const Dev: TPrintDevice - the printer page
    PageNo: Integer - page number, from 1
  Returns:
    TPrintPage - which sheet and part of it the page shows
  Notes:
    OnPrepareDC. Printing all sheets, the sheets go round fastest (page 1 is the first part of
    sheet 1, page 2 the first part of sheet 2, ...); the parts of a sheet go down a column and
    then across. The part's corner is its column or row times the printer's page (whole mm times
    5 units) over the scale, as whole units.
  =========================================================================== }
function PrintPageAt(const L: TPrintLayout; const Dev: TPrintDevice; PageNo: Integer): TPrintPage;
var
  Width, Height, N, Page: Integer;
begin
  Width := Dev.HorzMm * PIXELSPERMM;
  Height := Dev.VertMm * PIXELSPERMM;
  N := PageNo - 1;
  if N < 0 then
    N := 0;
  if L.Sheets > 1 then
  begin
    Page := N div L.Sheets;
    Result.Sheet := N mod L.Sheets;
  end
  else
  begin
    Page := N;
    Result.Sheet := 0;
  end;
  Result.Col := Page div L.Rows;
  Result.Row := Page mod L.Rows;
  Result.OriginX := Trunc((Result.Col * Width / L.Scale) * 100);
  Result.OriginY := Trunc((Result.Row * Height / L.Scale) * 100);
end;

{ ===========================================================================
  FormatCG  (function)
  Parameters:
    V: Double - the number
    Prec: Integer - significant digits
    Width: Integer - least number of characters (padded with spaces on the left)
  Returns:
    String - the text
  Notes:
    printf("%*.*g"): the number to Prec significant digits, in plain form when its exponent is
    from -4 up to Prec - 1 and in the e+XX form otherwise, with trailing zeros dropped.
  =========================================================================== }
function FormatCG(V: Double; Prec, Width: Integer): String;
var
  E, Decs: Integer;
  Mant, Sign, T: String;
  A: Double;
begin
  if Prec < 1 then
    Prec := 1;
  if IsNan(V) then
    Result := 'nan'
  else if IsInfinite(V) then
  begin
    if V < 0 then
      Result := '-inf'
    else
      Result := 'inf';
  end
  else
  begin
    if V < 0 then begin
      Sign := '-';
      A := -V;
    end else begin
      Sign := '';
      A := V;
    end;
    if A = 0 then
      Result := Sign + '0'
    else
    begin
      { the exponent after rounding to Prec digits }
      T := FormatFloat('0.' + StringOfChar('0', Prec - 1) + 'E+00', A);
      E := StrToInt(Copy(T, Pos('E', T) + 1, 10));
      if (E < -4) or (E >= Prec) then
      begin
        Mant := Copy(T, 1, Pos('E', T) - 1);
        if Pos('.', Mant) > 0 then
        begin
          while Mant[Length(Mant)] = '0' do Delete(Mant, Length(Mant), 1);
          if Mant[Length(Mant)] = '.' then
            Delete(Mant, Length(Mant), 1);
        end;
        if E < 0 then
          T := '-'
        else
          T := '+';
        Result := Sign + Mant + 'e' + T + Format('%.2d', [Abs(E)]);
      end
      else
      begin
        Decs := Prec - 1 - E;
        if Decs > 0 then
          T := '0.' + StringOfChar('0', Decs)
        else
          T := '0';
        Result := FormatFloat(T, A);
        if Pos('.', Result) > 0 then
        begin
          while Result[Length(Result)] = '0' do Delete(Result, Length(Result), 1);
          if Result[Length(Result)] = '.' then
            Delete(Result, Length(Result), 1);
        end;
        Result := Sign + Result;
      end;
    end;
  end;
  while Length(Result) < Width do Result := ' ' + Result;
end;

{ ===========================================================================
  PrintScaleText  (function)
  Parameters:
    V: Double - the scale
  Returns:
    String - the text of the Scale box
  Notes:
    The Print dialog's _stprintf("%3.3lg"): three significant digits, at least three characters
    wide, so 5 reads "  5" and 97.34 reads "97.3".
  =========================================================================== }
function PrintScaleText(V: Double): String;
begin
  Result := FormatCG(V, 3, 3);
end;

{ ===========================================================================
  CAtof  (function)
  Parameters:
    const S: String - the text
  Returns:
    Double - the number at the start of the text, 0 if there is none
  Notes:
    atof: leading spaces, an optional sign, digits with an optional point, and an optional
    exponent; anything after that is ignored.
  =========================================================================== }
function CAtof(const S: String): Double;
var
  I, Start, N: Integer;
  Digits: Boolean;
  T: String;
  FS: TFormatSettings;
begin
  Result := 0;
  N := Length(S);
  I := 1;
  while (I <= N) and (S[I] in [' ', #9, #10, #11, #12, #13]) do Inc(I);
  Start := I;
  if (I <= N) and (S[I] in ['+', '-']) then
    Inc(I);
  Digits := False;
  while (I <= N) and (S[I] in ['0'..'9']) do begin
    Inc(I);
    Digits := True;
  end;
  if (I <= N) and (S[I] = '.') then
  begin
    Inc(I);
    while (I <= N) and (S[I] in ['0'..'9']) do begin
      Inc(I);
      Digits := True;
    end;
  end;
  if not Digits then
    Exit;
  if (I <= N) and (S[I] in ['e', 'E']) then
  begin
    { an exponent only counts when it has digits }
    N := I + 1;
    if (N <= Length(S)) and (S[N] in ['+', '-']) then
      Inc(N);
    if (N <= Length(S)) and (S[N] in ['0'..'9']) then
    begin
      while (N <= Length(S)) and (S[N] in ['0'..'9']) do Inc(N);
      I := N;
    end;
  end;
  T := Copy(S, Start, I - Start);
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if not TryStrToFloat(T, Result, FS) then
    Result := 0;
end;

{ ===========================================================================
  PrintScaleValue  (function)
  Parameters:
    const S: String - the text of the Scale box
  Returns:
    Double - the scale
  Notes:
    The Print dialog's _tstof of the box.
  =========================================================================== }
function PrintScaleValue(const S: String): Double;
begin
  Result := CAtof(S);
end;

{ ===========================================================================
  PrintRangePages  (function)
  Parameters:
    Pages: Integer - the number of pages in the print
    FromPage: Integer - first page asked for, 0 for no range
    ToPage: Integer - last page asked for
    out First: Integer - the first page to print
    out Last: Integer - the last page to print
  Returns:
    Boolean - True if there is anything to print
  Notes:
    A page range cut down to the pages that exist; a range turned the wrong way round is turned
    back; no range prints every page.
  =========================================================================== }
function PrintRangePages(Pages, FromPage, ToPage: Integer; out First, Last: Integer): Boolean;
var
  T: Integer;
begin
  First := 1;
  Last := Pages;
  if (FromPage > 0) or (ToPage > 0) then
  begin
    if FromPage < 1 then
      FromPage := 1;
    if ToPage < 1 then
      ToPage := Pages;
    if ToPage < FromPage then begin
      T := FromPage;
      FromPage := ToPage;
      ToPage := T;
    end;
    First := Max(1, FromPage);
    Last := Min(Pages, ToPage);
  end;
  Result := (Pages > 0) and (First <= Last);
end;

{ ===========================================================================
  ParsePageRange  (function)
  Parameters:
    const S: String - text
    MaxPage: Integer - whole number
    out Pages: TPageArray - out: set by the call
    out Err: String - text (out: set by the call)
  Returns:
    Boolean
  Notes:
    A range is two numbers joined by -, "to" or "through" (the pages between are included, and a
    range typed backwards is turned round: 6-1 is 1-6); single pages and ranges are added to the
    list with a comma, "&" or "and". Spaces are ignored everywhere and the words may be in any
    case, so "1 - 2", "1to6 and 9", "1,2, 6" and "1 through 6" all read. A page is a whole
    number from 1 to MaxPage. Differences from the system Print dialog: it takes one range only.
  =========================================================================== }
function ParsePageRange(const S: String; MaxPage: Integer; out Pages: TPageArray; out Err: String): Boolean;
type
  TTok = (tkNum, tkRange, tkAdd, tkEnd);
var
  T: String;
  Pos_: Integer;
  Tok: TTok;
  Num: Int64;
  Mark: array of Boolean;
  Bad: String;

  function Next: Boolean;
  var
    W: String;
  begin
    Result := True;
    Num := 0;
    if Pos_ > Length(T) then begin
      Tok := tkEnd;
      Exit;
    end;
    case T[Pos_] of
      '0'..'9':
        begin
          Tok := tkNum;
          while (Pos_ <= Length(T)) and (T[Pos_] in ['0'..'9']) do
          begin
            if Num < 100000000 then
              Num := Num * 10 + Ord(T[Pos_]) - Ord('0');
            Inc(Pos_);
          end;
        end;
      '-': begin
        Tok := tkRange;
        Inc(Pos_);
      end;
      ',', '&': begin
        Tok := tkAdd;
        Inc(Pos_);
      end;
      'a'..'z':
        begin
          if Copy(T, Pos_, 7) = 'through' then begin
            Tok := tkRange;
            Inc(Pos_, 7);
          end
          else if Copy(T, Pos_, 2) = 'to' then begin
            Tok := tkRange;
            Inc(Pos_, 2);
          end
          else if Copy(T, Pos_, 3) = 'and' then begin
            Tok := tkAdd;
            Inc(Pos_, 3);
          end
          else
          begin
            W := '';
            while (Pos_ <= Length(T)) and (T[Pos_] in ['a'..'z']) do begin
              W := W + T[Pos_];
              Inc(Pos_);
            end;
            Bad := W;
            Result := False;
          end;
        end;
    else
      Bad := T[Pos_];
      Result := False;
    end;
  end;

  function AddRange(A, B: Int64): Boolean;
  var
    K, X: Int64;
    {$IFDEF CPU64}
    J: Int64;      // 64-bit targets allow an Int64 loop counter
    {$ELSE}
    J: Integer;    // 32-bit targets need an ordinal no wider than Integer
    {$ENDIF}
    Bad: Boolean;
  begin
    Result := False;
    if A > B then begin
      K := A;
      A := B;
      B := K;
    end;
    Bad := True;
    X := A;
    if (A < 1) or (A > MaxPage) then
      X := A
    else if (B < 1) or (B > MaxPage) then
      X := B
    else
      Bad := False;
    if Bad then
    begin
      if X < 1 then
        Err := rsPagesStartAt
      else if MaxPage < 1 then
        Err := rsThereAreNoPagesTo
      else if MaxPage = 1 then
        Err := Format(rsPageDoesNotExistThe, [X])
      else
        Err := Format(rsPageDoesNotExistThe2, [X, MaxPage]);
      Exit;
    end;
    {$IFDEF CPU64}
    for J := A to B do
    {$ELSE}
    for J := Integer(A) to Integer(B) do
    {$ENDIF}
      Mark[J - 1] := True;
    Result := True;
  end;

var
  A, B: Int64;
  I, N: Integer;
  Ch: Char;
begin
  Pages := nil;
  Err := '';
  Result := False;
  T := '';
  for Ch in LowerCase(S) do
    if not (Ch in [' ', #9, #10, #13, #160]) then
      T := T + Ch;
  { the long dashes some editors type are a - }
  T := StringReplace(T, #$E2#$80#$93, '-', [rfReplaceAll]);
  T := StringReplace(T, #$E2#$80#$94, '-', [rfReplaceAll]);
  if T = '' then
  begin
    Err := rsTypeThePagesToPrint;
    Exit;
  end;
  SetLength(Mark, Max(0, MaxPage));
  Pos_ := 1;
  Bad := '';
  repeat
    if not Next then begin
      Err := Format(rsCannotBeReadInThe, [Bad]);
      Exit;
    end;
    if Tok <> tkNum then begin
      Err := rsAPageNumberWasExpected;
      Exit;
    end;
    A := Num;
    B := Num;
    if not Next then begin
      Err := Format(rsCannotBeReadInThe, [Bad]);
      Exit;
    end;
    if Tok = tkRange then
    begin
      if not Next then begin
        Err := Format(rsCannotBeReadInThe, [Bad]);
        Exit;
      end;
      if Tok <> tkNum then begin
        Err := rsTheLastPageOfThe;
        Exit;
      end;
      B := Num;
      if not Next then begin
        Err := Format(rsCannotBeReadInThe, [Bad]);
        Exit;
      end;
    end;
    if not AddRange(A, B) then
      Exit;
    case Tok of
      tkEnd: Break;
      tkAdd: ;
    else
      Err := rsJoinPagesWithAComma;
      Exit;
    end;
  until False;
  N := 0;
  for I := 0 to High(Mark) do
    if Mark[I] then
    begin
      SetLength(Pages, N + 1);
      Pages[N] := I + 1;
      Inc(N);
    end;
  Result := N > 0;
end;

{ ===========================================================================
  PageListText  (function)
  Parameters:
    const Pages: TPageArray
  Returns:
    String
  Notes:
    1,2,3,6 reads 1-3, 6. Two pages in a row stay a run (1-2).
  =========================================================================== }
function PageListText(const Pages: TPageArray): String;
var
  I, J: Integer;
begin
  Result := '';
  I := 0;
  while I <= High(Pages) do
  begin
    J := I;
    while (J < High(Pages)) and (Pages[J + 1] = Pages[J] + 1) do
      Inc(J);
    if Result <> '' then
      Result := Result + ', ';
    if J > I then
      Result := Result + IntToStr(Pages[I]) + '-' + IntToStr(Pages[J])
    else
      Result := Result + IntToStr(Pages[I]);
    I := J + 1;
  end;
end;

end.
