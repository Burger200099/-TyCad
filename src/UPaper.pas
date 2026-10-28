// SPDX-License-Identifier: LGPL-2.1-or-later
{ Paper sizes and the page border.

  Internal units are 0.2 mm (CDetails::M_NPIXELSPERMM = 5 per mm), so an A4 landscape sheet is
  1485 x 1050 -- the default page size -- and 11 x 17 in (ANSI B) is 2159 x 1397.

  The border is a plain rectangle inset from the page edge by a margin that stands for the
  printer's unprintable edge. Written for the electrical-schematic version of this program; not
  part of the original TinyCAD.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UPaper;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, UGeometry;

const
  UNITS_PER_MM = 5;
  MM_PER_INCH = 25.4;
  DEFAULT_BORDER_MARGIN = 31.75; // 0.25 in, a common unprintable edge, in internal units

type
  TPaperSize = record
    Name: String;
    Family: String;            // 'ANSI', 'ARCH', 'ISO A', 'ISO B', 'ISO RA/SRA', 'Other'
    WidthMm, HeightMm: Double; // landscape: width >= height
  end;

function PaperCount: Integer;
function PaperInfo(Index: Integer): TPaperSize;
{ -1 when there is no paper of that name (case-insensitive) }
function PaperIndexByName(const Name: String): Integer;
{ "ANSI B (Tabloid) - 431.8 x 279.4 mm (17 x 11 in)" for pick lists }
function PaperDescription(Index: Integer): String;
{ The page size in internal units for a paper, in landscape or portrait }
procedure PaperUnits(Index: Integer; Landscape: Boolean; out W, H: Integer);
{ Which paper does a page size (internal units) match, to within Tol units per side? The
  closest one wins. -1 when it is a custom size. Landscape tells which way round it matched. }
function MatchPaper(W, H, Tol: Integer; out Landscape: Boolean): Integer;
{ "ANSI B (Tabloid) landscape" style description of a page size, or "Custom 200 x 140 mm" }
function DescribePage(W, H: Integer): String;

{ The border rectangle: the page inset by Margin on every side (internal units) }
function BorderRect(PageW, PageH: Integer; Margin: Double): TDRect;

implementation

const
  IN_ = MM_PER_INCH;
  { Standard sizes in landscape (width >= height). ANSI and ARCH are the North American office and
    plotter series, ISO A/B the international ones, RA/SRA the ISO printing-stock sizes. }
  Papers: array[0..40] of TPaperSize = (
    (Name: 'ANSI A (Letter)';  Family: 'ANSI';       WidthMm: 11 * IN_;   HeightMm: 8.5 * IN_),
    (Name: 'ANSI B (Tabloid)'; Family: 'ANSI';       WidthMm: 17 * IN_;   HeightMm: 11 * IN_),
    (Name: 'ANSI C';           Family: 'ANSI';       WidthMm: 22 * IN_;   HeightMm: 17 * IN_),
    (Name: 'ANSI D';           Family: 'ANSI';       WidthMm: 34 * IN_;   HeightMm: 22 * IN_),
    (Name: 'ANSI E';           Family: 'ANSI';       WidthMm: 44 * IN_;   HeightMm: 34 * IN_),
    (Name: 'ARCH A';           Family: 'ARCH';       WidthMm: 12 * IN_;   HeightMm: 9 * IN_),
    (Name: 'ARCH B';           Family: 'ARCH';       WidthMm: 18 * IN_;   HeightMm: 12 * IN_),
    (Name: 'ARCH C';           Family: 'ARCH';       WidthMm: 24 * IN_;   HeightMm: 18 * IN_),
    (Name: 'ARCH D';           Family: 'ARCH';       WidthMm: 36 * IN_;   HeightMm: 24 * IN_),
    (Name: 'ARCH E1';          Family: 'ARCH';       WidthMm: 42 * IN_;   HeightMm: 30 * IN_),
    (Name: 'ARCH E';           Family: 'ARCH';       WidthMm: 48 * IN_;   HeightMm: 36 * IN_),
    (Name: 'ISO A6';           Family: 'ISO A';      WidthMm: 148;      HeightMm: 105),
    (Name: 'ISO A5';           Family: 'ISO A';      WidthMm: 210;      HeightMm: 148),
    (Name: 'ISO A4';           Family: 'ISO A';      WidthMm: 297;      HeightMm: 210),
    (Name: 'ISO A3';           Family: 'ISO A';      WidthMm: 420;      HeightMm: 297),
    (Name: 'ISO A2';           Family: 'ISO A';      WidthMm: 594;      HeightMm: 420),
    (Name: 'ISO A1';           Family: 'ISO A';      WidthMm: 841;      HeightMm: 594),
    (Name: 'ISO A0';           Family: 'ISO A';      WidthMm: 1189;     HeightMm: 841),
    (Name: 'ISO B6';           Family: 'ISO B';      WidthMm: 176;      HeightMm: 125),
    (Name: 'ISO B5';           Family: 'ISO B';      WidthMm: 250;      HeightMm: 176),
    (Name: 'ISO B4';           Family: 'ISO B';      WidthMm: 353;      HeightMm: 250),
    (Name: 'ISO B3';           Family: 'ISO B';      WidthMm: 500;      HeightMm: 353),
    (Name: 'ISO B2';           Family: 'ISO B';      WidthMm: 707;      HeightMm: 500),
    (Name: 'ISO B1';           Family: 'ISO B';      WidthMm: 1000;     HeightMm: 707),
    (Name: 'ISO B0';           Family: 'ISO B';      WidthMm: 1414;     HeightMm: 1000),
    (Name: 'ISO RA2';          Family: 'ISO RA/SRA'; WidthMm: 610;      HeightMm: 430),
    (Name: 'ISO RA1';          Family: 'ISO RA/SRA'; WidthMm: 860;      HeightMm: 610),
    (Name: 'ISO RA0';          Family: 'ISO RA/SRA'; WidthMm: 1220;     HeightMm: 860),
    (Name: 'ISO SRA2';         Family: 'ISO RA/SRA'; WidthMm: 640;      HeightMm: 450),
    (Name: 'ISO SRA1';         Family: 'ISO RA/SRA'; WidthMm: 900;      HeightMm: 640),
    (Name: 'ISO SRA0';         Family: 'ISO RA/SRA'; WidthMm: 1280;     HeightMm: 900),
    (Name: 'Legal';            Family: 'Other';      WidthMm: 14 * IN_;   HeightMm: 8.5 * IN_),
    (Name: 'Executive';        Family: 'Other';      WidthMm: 10.5 * IN_; HeightMm: 7.25 * IN_),
    (Name: 'Statement';        Family: 'Other';      WidthMm: 8.5 * IN_;  HeightMm: 5.5 * IN_),
    (Name: 'ISO A7';           Family: 'ISO A';      WidthMm: 105;      HeightMm: 74),
    (Name: 'ISO A8';           Family: 'ISO A';      WidthMm: 74;       HeightMm: 52),
    (Name: 'ISO B7';           Family: 'ISO B';      WidthMm: 125;      HeightMm: 88),
    (Name: 'ISO B8';           Family: 'ISO B';      WidthMm: 88;       HeightMm: 62),
    (Name: 'ISO C4 envelope';  Family: 'Other';      WidthMm: 324;      HeightMm: 229),
    (Name: 'ISO C5 envelope';  Family: 'Other';      WidthMm: 229;      HeightMm: 162),
    (Name: 'ISO C6 envelope';  Family: 'Other';      WidthMm: 162;      HeightMm: 114));

{ ===========================================================================
  PaperCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    Number of standard paper sizes in the table.
  =========================================================================== }
function PaperCount: Integer;
begin
  Result := Length(Papers);
end;

{ ===========================================================================
  PaperInfo  (function)
  Parameters:
    Index: Integer - position in the table, 0-based
  Returns:
    TPaperSize - the table entry
  Notes:
    One entry of the paper table: name, family and size in millimetres (landscape, width not
    less than height).
  =========================================================================== }
function PaperInfo(Index: Integer): TPaperSize;
begin
  Result := Papers[Index];
end;

{ ===========================================================================
  PaperIndexByName  (function)
  Parameters:
    const Name: String - the paper name, e.g. "ANSI B (Tabloid)"
  Returns:
    Integer - its index, or -1 if there is no such paper
  Notes:
    Looks a paper up by its name, ignoring case.
  =========================================================================== }
function PaperIndexByName(const Name: String): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(Papers) do
    if SameText(Papers[i].Name, Name) then
    begin
      Result := i;
      Exit;
    end;
end;

{ ===========================================================================
  PaperDescription  (function)
  Parameters:
    Index: Integer - position in the table
  Returns:
    String - for example "ANSI B (Tabloid) - 431.8 x 279.4 mm (17 x 11 in)"
  Notes:
    A text for pick lists: name, size in millimetres and in inches.
  =========================================================================== }
function PaperDescription(Index: Integer): String;
var
  Fs: TFormatSettings;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  Result := Format('%s - %s x %s mm (%s x %s in)',
    [Papers[Index].Name, FormatFloat('0.#', Papers[Index].WidthMm, Fs), FormatFloat('0.#', Papers[Index].HeightMm, Fs),
     FormatFloat('0.##', Papers[Index].WidthMm / MM_PER_INCH, Fs), FormatFloat('0.##', Papers[Index].HeightMm / MM_PER_INCH, Fs)], Fs);
end;

{ ===========================================================================
  PaperUnits  (procedure)
  Parameters:
    Index: Integer - position in the table
    Landscape: Boolean - True for landscape, False for portrait
    out W: Integer - set to the page width
    out H: Integer - set to the page height
  Notes:
    The page size in internal units (0.2 mm each) for a paper, rounding halves up so every size
    is rounded the same way.
  =========================================================================== }
procedure PaperUnits(Index: Integer; Landscape: Boolean; out W, H: Integer);
var
  Wl, Hl: Integer;
begin
  { round halves up (Pascal's Round is banker's rounding, which would make 5.5 in and 8.5 in differ) }
  Wl := Floor(Papers[Index].WidthMm * UNITS_PER_MM + 0.5);
  Hl := Floor(Papers[Index].HeightMm * UNITS_PER_MM + 0.5);
  if Landscape then begin
    W := Wl;
    H := Hl;
  end
  else begin
    W := Hl;
    H := Wl;
  end;
end;

{ ===========================================================================
  MatchPaper  (function)
  Parameters:
    W: Integer - page width, internal units
    H: Integer - page height, internal units
    Tol: Integer - allowed difference per side, internal units
    out Landscape: Boolean - set True if it matched in landscape
  Returns:
    Integer - the paper's index, or -1 for a custom size
  Notes:
    Finds which standard paper a page size is, within a tolerance, in either orientation; when
    several fit the closest wins.
  =========================================================================== }
function MatchPaper(W, H, Tol: Integer; out Landscape: Boolean): Integer;
var
  i, Pw, Ph, Dev, Best: Integer;
begin
  Result := -1;
  Landscape := True;
  Best := MaxInt;
  for i := 0 to High(Papers) do
  begin
    PaperUnits(i, True, Pw, Ph);
    Dev := Abs(W - Pw) + Abs(H - Ph);
    if (Abs(W - Pw) <= Tol) and (Abs(H - Ph) <= Tol) and (Dev < Best) then
    begin
      Result := i; Landscape := True; Best := Dev;
    end;
    Dev := Abs(W - Ph) + Abs(H - Pw);
    if (Abs(W - Ph) <= Tol) and (Abs(H - Pw) <= Tol) and (Dev < Best) then
    begin
      Result := i; Landscape := False; Best := Dev;
    end;
  end;
end;

{ ===========================================================================
  DescribePage  (function)
  Parameters:
    W: Integer - page width, internal units
    H: Integer - page height, internal units
  Returns:
    String - the description
  Notes:
    Describes a page size for display: the paper name and orientation, or "Custom W x H mm".
  =========================================================================== }
function DescribePage(W, H: Integer): String;
var
  Idx: Integer;
  Land: Boolean;
  Fs: TFormatSettings;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  Idx := MatchPaper(W, H, 0, Land);
  if Idx >= 0 then
  begin
    Result := Papers[Idx].Name;
    if Land then
      Result := Result + ' landscape'
    else
      Result := Result + ' portrait';
  end
  else
    Result := Format('Custom %s x %s mm', [FormatFloat('0.#', W / UNITS_PER_MM, Fs),
                                           FormatFloat('0.#', H / UNITS_PER_MM, Fs)], Fs);
end;

{ ===========================================================================
  BorderRect  (function)
  Parameters:
    PageW: Integer - page width
    PageH: Integer - page height
    Margin: Double - inset on each side, internal units
  Returns:
    TDRect - the rectangle in internal units
  Notes:
    The border rectangle: the page inset by the same margin on every side (it stands for the
    printer's unprintable edge).
  =========================================================================== }
function BorderRect(PageW, PageH: Integer; Margin: Double): TDRect;
begin
  Result := DRect(Margin, Margin, PageW - Margin, PageH - Margin);
end;

end.
