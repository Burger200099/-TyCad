// SPDX-License-Identifier: LGPL-2.1-or-later
{ Document variables for title blocks and text: "$(SHEET) of $(SHEETCOUNT)" and friends.

  A variable is written $(NAME) (case-insensitive). "$$" is a literal dollar sign. An unknown
  name, or a "$(" with no closing ")", is left exactly as typed. The values come from the sheet
  being drawn and from its position in the design file, so sheet numbering never has to be typed.

    SHEET        this sheet's number (1-based)           SHEETCOUNT   number of sheets in the file
    SHEETOF      "2 of 7"                                SHEETS       the sheet's Sheets field: "N of M"
                                                                      when auto-numbering is on, else the typed text
                                                                      (automatic: the number of sheets; DOCNO is then this sheet's number)
    SHEETNAME    the sheet's name, or "Sheet N"          PAPER        e.g. "ANSI B (Tabloid) landscape"
    TITLE AUTHOR ORG DOCNO DATE                          the title-block fields
    REV          current revision label                  REVDATE REVBY REVAPPROVED REVNOTES   its other fields
    FILE         full path of the file                   FILENAME     the name without the folder

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UDocVars;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, UDesign, UPaper, URevisions;

{ Expand every variable in Text for the given sheet (0-based index) }
function ExpandVariables(Design: TDesignFile; SheetIndex: Integer; const Text: String): String;
{ "N of M": this sheet's number and how many sheets there are }
function SheetOfText(Design: TDesignFile; SheetIndex: Integer): String;
{ The sheet's Sheets field: the number of sheets in the file when auto-numbering is on, else the typed text }
function SheetsText(Design: TDesignFile; SheetIndex: Integer): String;
{ The sheet's Document number field: this sheet's number when auto-numbering is on, else the typed text }
function DocNoText(Design: TDesignFile; SheetIndex: Integer): String;
{ All variable names, for pick lists }
function VariableNames: TStringArray;

implementation

const
  Names: array[0..19] of String = (
    'SHEET', 'SHEETCOUNT', 'SHEETOF', 'SHEETS', 'SHEETNAME', 'PAPER', 'TITLE', 'AUTHOR', 'ORG',
    'DOCNO', 'DATE', 'REV', 'REVDATE', 'REVBY', 'REVAPPROVED', 'REVNOTES', 'FILE', 'FILENAME',
    'BORDERMARGIN', 'PAGESIZE');

{ ===========================================================================
  VariableNames  (function)
  Parameters:  none
  Returns:
    TStringArray - the names, without the $( )
  Notes:
    Lists the names of every title-block variable (SHEET, SHEETCOUNT, TITLE, REV ...) so a
    program can offer them in a pick list.
  =========================================================================== }
function VariableNames: TStringArray;
var
  i: Integer;
begin
  SetLength(Result, Length(Names));
  for i := 0 to High(Names) do Result[i] := Names[i];
end;

{ ===========================================================================
  SheetOfText  (function)
  Parameters:
    Design: TDesignFile - the design
    SheetIndex: Integer - zero-based index of the sheet
  Returns:
    String - e.g. "2 of 7"
  Notes:
    The text "N of M" for a sheet: its number and the number of sheets in the file.
  =========================================================================== }
function SheetOfText(Design: TDesignFile; SheetIndex: Integer): String;
begin
  Result := Format('%d of %d', [SheetIndex + 1, Design.SheetCount]);
end;

{ ===========================================================================
  SheetsText  (function)
  Parameters:
    Design: TDesignFile - the design
    SheetIndex: Integer - zero-based index of the sheet
  Returns:
    String - the text to show
  Notes:
    The sheet's Sheets field: "N of M" worked out automatically when auto-numbering is on,
    otherwise the text the user typed.
  =========================================================================== }
function SheetsText(Design: TDesignFile; SheetIndex: Integer): String;
begin
  if Design.Sheets[SheetIndex].Details.AutoSheets then
    Result := IntToStr(Design.SheetCount)
  else
    Result := Design.Sheets[SheetIndex].Details.Sheets;
end;

{ ===========================================================================
  DocNoText  (function)
  Parameters:
    Design: TDesignFile - the design
    SheetIndex: Integer - zero-based sheet number
  Returns:
    String
  Notes:
    The sheet's Document number field: this sheet's number ("N", counting from 1) when auto-
    numbering is on, otherwise the text the user typed. With SheetsText the title block then
    reads "N" and "M" without anything being typed.
  =========================================================================== }
function DocNoText(Design: TDesignFile; SheetIndex: Integer): String;
begin
  if Design.Sheets[SheetIndex].Details.AutoSheets then
    Result := IntToStr(SheetIndex + 1)
  else
    Result := Design.Sheets[SheetIndex].Details.DocNo;
end;

{ ===========================================================================
  Lookup  (function)
  Parameters:
    Design: TDesignFile - the design
    SheetIndex: Integer - zero-based sheet index
    const Name: String - variable name in upper case
    out Value: String - set to the variable's value
  Returns:
    Boolean - True if the name is a known variable
  Notes:
    Finds the value of one variable for a sheet (case already upper). Values come from the
    sheet's title block, revision history, paper, border and the file name.
  =========================================================================== }
function Lookup(Design: TDesignFile; SheetIndex: Integer; const Name: String; out Value: String): Boolean;
var
  Sh: TDesignSheet;
  D: TDetails;
  Last: TRevision;
  Fs: TFormatSettings;
begin
  Result := True;
  Sh := Design.Sheets[SheetIndex];
  D := Sh.Details;
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  Last.Rev := ''; Last.Date := ''; Last.Author := ''; Last.Approved := ''; Last.Notes := '';
  if Length(D.Revisions) > 0 then
    Last := D.NewestRevision;      // (the newest by the sheet's ordering: date, or revision label)
  if Name = 'SHEET' then
    Value := IntToStr(SheetIndex + 1)
  else if Name = 'SHEETCOUNT' then
    Value := IntToStr(Design.SheetCount)
  else if Name = 'SHEETOF' then
    Value := SheetOfText(Design, SheetIndex)
  else if Name = 'SHEETS' then
    Value := SheetsText(Design, SheetIndex)
  else if Name = 'SHEETNAME' then
  begin
    if Sh.SheetName <> '' then
      Value := Sh.SheetName
    else
      Value := 'Sheet ' + IntToStr(SheetIndex + 1);
  end
  else if Name = 'PAPER' then
    Value := DescribePage(D.PageWidth, D.PageHeight)
  else if Name = 'PAGESIZE' then
    Value := Format('%s x %s mm', [FormatFloat('0.#', D.PageWidth / UNITS_PER_MM, Fs),
                                   FormatFloat('0.#', D.PageHeight / UNITS_PER_MM, Fs)], Fs)
  else if Name = 'BORDERMARGIN' then
    Value := FormatFloat('0.##', D.BorderMargin / UNITS_PER_MM, Fs)
  else if Name = 'TITLE' then
    Value := D.Title
  else if Name = 'AUTHOR' then
    Value := D.Author
  else if Name = 'ORG' then
    Value := D.Org
  else if Name = 'DOCNO' then
    Value := DocNoText(Design, SheetIndex)
  else if Name = 'DATE' then
    Value := D.LastChange
  else if Name = 'REV' then
    Value := D.EffectiveRevision
  else if Name = 'REVDATE' then
    Value := D.EffectiveRevisionDate
  else if Name = 'REVBY' then
    Value := Last.Author
  else if Name = 'REVAPPROVED' then
    Value := Last.Approved
  else if Name = 'REVNOTES' then
    Value := Last.Notes
  else if Name = 'FILE' then
    Value := Design.FileName
  else if Name = 'FILENAME' then
    Value := ExtractFileName(Design.FileName)
  else
  begin
    Value := '';
    Result := False;
  end;
end;

{ ===========================================================================
  ExpandVariables  (function)
  Parameters:
    Design: TDesignFile - the design
    SheetIndex: Integer - zero-based sheet index
    const Text: String - text that may contain $(...) variables
  Returns:
    String - the expanded text (unchanged if the sheet index is out of range)
  Notes:
    Replaces every $(NAME) in Text with its value for the given sheet. "$$" gives a literal
    dollar sign; an unknown name or a "$(" with no closing bracket is left exactly as typed.
  =========================================================================== }
function ExpandVariables(Design: TDesignFile; SheetIndex: Integer; const Text: String): String;
var
  i, j: Integer;
  Name, Value: String;
begin
  if (SheetIndex < 0) or (SheetIndex >= Design.SheetCount) then
  begin
    Result := Text;
    Exit;
  end;
  Result := '';
  i := 1;
  while i <= Length(Text) do
  begin
    if Text[i] <> '$' then
    begin
      Result := Result + Text[i];
      Inc(i);
    end
    else if (i < Length(Text)) and (Text[i + 1] = '$') then
    begin
      Result := Result + '$';  // $$ is a literal dollar
      Inc(i, 2);
    end
    else if (i < Length(Text)) and (Text[i + 1] = '(') then
    begin
      j := i + 2;
      while (j <= Length(Text)) and (Text[j] <> ')') do Inc(j);
      if j > Length(Text) then
      begin
        Result := Result + Copy(Text, i, MaxInt); // no closing bracket: leave as typed
        Break;
      end;
      Name := Trim(Copy(Text, i + 2, j - i - 2));
      if Lookup(Design, SheetIndex, UpperCase(Name), Value) then
        Result := Result + Value
      else
        Result := Result + Copy(Text, i, j - i + 1); // unknown name: leave as typed
      i := j + 1;
    end
    else
    begin
      Result := Result + '$';
      Inc(i);
    end;
  end;
end;

end.
