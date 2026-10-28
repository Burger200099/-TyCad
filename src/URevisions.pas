// SPDX-License-Identifier: LGPL-2.1-or-later
{ Which revisions the extended title block shows, and in what order: the five newest, newest first, judged by date or by revision label as the sheet's
  setting says. Dates and labels are free text, so both comparisons have to read what people type.

  A date is read in these forms: year first (2024-03-09, 2024/3/9, 2024.03.09, 20240309), day or month first with a four or two figure year
  (9/3/2024, 9-3-24, 9.3.2024; the first number above 12 is the day, the second above 12 the month, and when both could be either the day is first), and with the month
  as a word (9 Mar 2024, 9 March 2024, Mar 9 2024, March 9, 2024). A two figure year is 2000 to 2069 or 1970 to 1999. Anything else is no date, and counts as older than
  every date.

  A revision label is compared the way a person reads it: runs of digits as numbers (1.2 is before 1.10), runs of letters by length and then alphabetically without regard
  to case (Z is before AA, since after Z comes AA), a number before a letter, and a label that is only the beginning of another before it (1 before 1.1).

  Where two revisions compare as equal the one later in the list is the newer.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit URevisions;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils;

const
  EXTENDED_ROWS = 5;      // how many revisions the extended title block shows

type
  { one entry of a sheet's revision history }
  TRevision = record
    Rev: String;       // revision label, e.g. 'A', '2.1'
    Date: String;
    Author: String;
    Approved: String;
    Notes: String;     // what changed; may span several lines (stored with LF line ends)
  end;
  TRevisionArray = array of TRevision;

{ the date as a number that sorts (year * 10000 + month * 100 + day), or -1 if the text is not a date }
function RevisionDateKey(const S: String): Integer;
{ -1, 0 or 1: label A is before, the same as, or after label B }
function CompareRevisionLabels(const A, B: String): Integer;
{ the revisions to show, newest first: at most Count of them, chosen from a revision history by date or by label. With no history but a revision typed
  into the old single Revision field (LegacyRev, with the sheet's date LegacyDate) that is the only revision. }
function NewestRevisions(const Revs: TRevisionArray; const LegacyRev, LegacyDate: String; ByRevision: Boolean; Count: Integer): TRevisionArray;

implementation

const
  MONTHS: array[1..12] of String = ('JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC');

{ ===========================================================================
  MonthOfWord  (function)
  Parameters:
    const W: String - the XML writer to save into
  Returns:
    Integer
  Notes:
    The month a word names (its first three letters are enough: Mar, March, Sept), or 0
  =========================================================================== }
function MonthOfWord(const W: String): Integer;
var
  i: Integer;
  U: String;
begin
  Result := 0;
  U := UpperCase(W);
  if Length(U) < 3 then
    Exit;
  for i := 1 to 12 do
    if Copy(U, 1, 3) = MONTHS[i] then
    begin
      { the rest must be the rest of the month's name (March, Sept, Sep), or nothing }
      Result := i;
      Exit;
    end;
end;

{ ===========================================================================
  ValidDate  (function)
  Parameters:
    Y: Integer - the year
    M: Integer - the month, 1 to 12
    D: Integer - the day
  Returns:
    Boolean - True if it is a real date
  Notes:
    Whether a year, month and day make a date that exists (a day of 29 February only in a leap
    year).
  =========================================================================== }
function ValidDate(Y, M, D: Integer): Boolean;
const
  DAYS: array[1..12] of Integer = (31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
begin
  Result := (Y >= 1) and (M >= 1) and (M <= 12) and (D >= 1) and (D <= DAYS[M]);
  if Result and (M = 2) and (D = 29) then
    Result := ((Y mod 4 = 0) and (Y mod 100 <> 0)) or (Y mod 400 = 0);
end;

{ ===========================================================================
  FullYear  (function)
  Parameters:
    Y: Integer - the year as typed
    Digits: Integer - how many figures it was typed with
  Returns:
    Integer - the year
  Notes:
    A year as the full number: a two figure year is 2000 to 2069 (below 70) or 1970 to 1999; a
    four figure one is as it is.
  =========================================================================== }
function FullYear(Y, Digits: Integer): Integer;
begin
  if Digits <= 2 then
  begin
    if Y < 70 then
      Result := 2000 + Y
    else
      Result := 1900 + Y;
  end
  else
    Result := Y;
end;

{ ===========================================================================
  RevisionDateKey  (function)
  Parameters:
    const S: String - text
  Returns:
    Integer
  Notes:
    See the description at the top of the unit for the forms that are read. Text round the date
    is ignored only as spaces; a time or other words make it no date.
  =========================================================================== }
function RevisionDateKey(const S: String): Integer;
var
  T: String;
  Words: array of String;     // the pieces: runs of digits, and runs of letters
  IsNum: array of Boolean;
  i, n, Y, M, D, A, B, DY, DM: Integer;
  Cur: String;
  CurNum: Boolean;
  procedure Flush;
  begin
    if Cur <> '' then
    begin
      SetLength(Words, n + 1); SetLength(IsNum, n + 1);
      Words[n] := Cur; IsNum[n] := CurNum; Inc(n);
      Cur := '';
    end;
  end;
begin
  Result := -1;
  T := Trim(S);
  if T = '' then
    Exit;
  { a run of eight digits is year month day }
  if (Length(T) = 8) and (StrToIntDef(T, -1) >= 0) then
  begin
    Y := StrToInt(Copy(T, 1, 4)); M := StrToInt(Copy(T, 5, 2)); D := StrToInt(Copy(T, 7, 2));
    if ValidDate(Y, M, D) then
      Result := Y * 10000 + M * 100 + D;
    Exit;
  end;
  { split into numbers and words; the separators may be spaces, - / . and a comma }
  n := 0; Cur := ''; CurNum := False;
  for i := 1 to Length(T) do
  begin
    if T[i] in ['0'..'9'] then
    begin
      if (Cur <> '') and not CurNum then
        Flush;
      CurNum := True; Cur := Cur + T[i];
    end
    else if T[i] in ['A'..'Z', 'a'..'z'] then
    begin
      if (Cur <> '') and CurNum then
        Flush;
      CurNum := False; Cur := Cur + T[i];
    end
    else if T[i] in [' ', '-', '/', '.', ','] then
      Flush
    else
      Exit;                                   // anything else (a colon, a letter in a number ...): no date
  end;
  Flush;
  { three numbers: year first, or day / month first }
  if (n = 3) and IsNum[0] and IsNum[1] and IsNum[2] then
  begin
    if Length(Words[0]) = 4 then
    begin
      Y := StrToInt(Words[0]); M := StrToInt(Words[1]); D := StrToInt(Words[2]);
    end
    else if (Length(Words[0]) <= 2) and (Length(Words[1]) <= 2) and (Length(Words[2]) in [2, 4]) then
    begin
      A := StrToInt(Words[0]); B := StrToInt(Words[1]); Y := FullYear(StrToInt(Words[2]), Length(Words[2]));
      if (A > 12) then begin
        D := A;
        M := B;
      end                 // the first can only be the day
      else if (B > 12) then begin
        M := A;
        D := B;
      end             // the second can only be the day
      else begin
        D := A;
        M := B;
      end;                              // either: the day first
    end
    else
      Exit;
    if ValidDate(Y, M, D) then
      Result := Y * 10000 + M * 100 + D;
    Exit;
  end;
  { a month as a word: day month year, or month day year }
  if (n = 3) and (Length(Words[1]) >= 3) and not IsNum[1] and IsNum[0] and IsNum[2] then
  begin
    DM := MonthOfWord(Words[1]); D := StrToInt(Words[0]); DY := StrToInt(Words[2]);
    if (DM > 0) and (Length(Words[2]) in [2, 4]) and ValidDate(FullYear(DY, Length(Words[2])), DM, D) then
      Result := FullYear(DY, Length(Words[2])) * 10000 + DM * 100 + D;
    Exit;
  end;
  if (n = 3) and not IsNum[0] and IsNum[1] and IsNum[2] then
  begin
    DM := MonthOfWord(Words[0]); D := StrToInt(Words[1]); DY := StrToInt(Words[2]);
    if (DM > 0) and (Length(Words[2]) in [2, 4]) and ValidDate(FullYear(DY, Length(Words[2])), DM, D) then
      Result := FullYear(DY, Length(Words[2])) * 10000 + DM * 100 + D;
    Exit;
  end;
end;

{ ===========================================================================
  CompareRevisionLabels  (function)
  Parameters:
    const A: String - a point, in design units
    const B: String - a point, in design units
  Returns:
    Integer
  Notes:
    Chunk by chunk, where a chunk is a run of digits, a run of letters or a single other
    character: two numbers by value, two words by length and then without regard to case, two
    other characters by code; a number is before a word, a word before another character; and a
    label that ends first is the earlier.
  =========================================================================== }
function CompareRevisionLabels(const A, B: String): Integer;
type
  TKind = (kNum, kWord, kOther);
  function Chunk(const S: String; var P: Integer; out Kind: TKind): String;
  var
    Q: Integer;
  begin
    Q := P;
    if S[P] in ['0'..'9'] then
    begin
      Kind := kNum;
      while (Q <= Length(S)) and (S[Q] in ['0'..'9']) do Inc(Q);
    end
    else if S[P] in ['A'..'Z', 'a'..'z'] then
    begin
      Kind := kWord;
      while (Q <= Length(S)) and (S[Q] in ['A'..'Z', 'a'..'z']) do Inc(Q);
    end
    else
    begin
      Kind := kOther;
      Inc(Q);
    end;
    Result := Copy(S, P, Q - P);
    P := Q;
  end;
  function TrimZeros(const N: String): String;
  var
    i: Integer;
  begin
    i := 1;
    while (i < Length(N)) and (N[i] = '0') do Inc(i);
    Result := Copy(N, i, Length(N));
  end;
var
  Pa, Pb: Integer;
  Ca, Cb, Na, Nb: String;
  Ka, Kb: TKind;
begin
  Result := 0;
  Pa := 1; Pb := 1;
  while (Pa <= Length(A)) and (Pb <= Length(B)) do
  begin
    Ca := Chunk(A, Pa, Ka);
    Cb := Chunk(B, Pb, Kb);
    if Ka <> Kb then
    begin
      if Ord(Ka) < Ord(Kb) then
        Result := -1
      else
        Result := 1;
      Exit;
    end;
    case Ka of
      kNum:
        begin
          Na := TrimZeros(Ca); Nb := TrimZeros(Cb);
          if Length(Na) <> Length(Nb) then
          begin
            if Length(Na) < Length(Nb) then
              Result := -1
            else
              Result := 1;
            Exit;
          end;
          if Na <> Nb then
          begin
            if Na < Nb then
              Result := -1
            else
              Result := 1;
            Exit;
          end;
        end;
      kWord:
        begin
          if Length(Ca) <> Length(Cb) then
          begin
            if Length(Ca) < Length(Cb) then
              Result := -1
            else
              Result := 1;
            Exit;
          end;
          Na := UpperCase(Ca); Nb := UpperCase(Cb);
          if Na <> Nb then
          begin
            if Na < Nb then
              Result := -1
            else
              Result := 1;
            Exit;
          end;
        end;
      kOther:
        if Ca <> Cb then
        begin
          if Ca < Cb then
            Result := -1
          else
            Result := 1;
          Exit;
        end;
    end;
  end;
  if (Pa > Length(A)) and (Pb <= Length(B)) then
    Result := -1
  else if (Pa <= Length(A)) and (Pb > Length(B)) then
    Result := 1;
end;

{ ===========================================================================
  NewestRevisions  (function)
  Parameters:
    const Revs: TRevisionArray
    const LegacyRev: String - text
    const LegacyDate: String - text
    ByRevision: Boolean - flag
    Count: Integer - whole number
  Returns:
    TRevisionArray
  Notes:
    With no history, a revision typed into the old Revision field is the one revision, dated
    with the sheet's date. Revisions that compare as equal keep the order of the list, the later
    being the newer. By date, text that is not a date is older than any date.
  =========================================================================== }
function NewestRevisions(const Revs: TRevisionArray; const LegacyRev, LegacyDate: String; ByRevision: Boolean; Count: Integer): TRevisionArray;
var
  All: TRevisionArray;
  Idx: array of Integer;
  i, j, t, n: Integer;
  function Newer(X, Y: Integer): Boolean;      // is revision X newer than revision Y?
  var
    C: Integer;
  begin
    if ByRevision then
      C := CompareRevisionLabels(All[X].Rev, All[Y].Rev)
    else
      C := RevisionDateKey(All[X].Date) - RevisionDateKey(All[Y].Date);
    if C <> 0 then
      Result := C > 0
    else
      Result := X > Y;
  end;
begin
  SetLength(Result, 0);
  All := Revs;
  if (Length(All) = 0) and (LegacyRev <> '') then
  begin
    SetLength(All, 1);
    All[0].Rev := LegacyRev;
    All[0].Date := LegacyDate;
    All[0].Author := ''; All[0].Approved := ''; All[0].Notes := '';
  end;
  n := Length(All);
  SetLength(Idx, n);
  for i := 0 to n - 1 do Idx[i] := i;
  { newest first: an insertion sort is plenty for a handful of revisions }
  for i := 1 to n - 1 do
  begin
    t := Idx[i]; j := i - 1;
    while (j >= 0) and Newer(t, Idx[j]) do
    begin
      Idx[j + 1] := Idx[j];
      Dec(j);
    end;
    Idx[j + 1] := t;
  end;
  if n > Count then
    n := Count;
  SetLength(Result, n);
  for i := 0 to n - 1 do Result[i] := All[Idx[i]];
end;

end.
