// SPDX-License-Identifier: LGPL-2.1-or-later
{ Counting names and pin numbers when objects are placed one after another (TinyCAD's Options > Repeat Directions).

  Place a label, text or pin, and the next one to place starts as a copy of it with its number counted up or down: net names A1, A2, A3 ... or pin numbers 1, 2, 3 ... counting down
  instead if the direction says so. There are two directions, one for names and one for pin numbers (a pin also counts its name by the name direction), each +1 or -1.

  Two rules, as TinyCAD has them:
    - a label's or text's (and so a net name's) text: the first digit or minus sign in it starts the number, which is counted and written back in place of everything from there to the
      end; text with no digit or minus sign does not change (CDrawLabel::LButtonDown, CDrawText::LButtonDown)
    - a pin's number and name (CDrawPin, IncrementNumber, which TinyCAD builds with TP_EDIT): the first run of digits is counted, kept between 1 and 999, and the text round it kept;
      with no digits the last character is moved along the alphabet if it is a letter and stays a letter

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit URepeat;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils;

{ the text of the next label or text to place: the number in it counted by Dir (+1 or -1), as described above }
function IncrementLabelText(const S: String; Dir: Integer): String;
{ a pin's number or name counted by Step (+1 or -1): digits stay between 1 and 999, and with no digits a final letter moves along the alphabet }
function IncrementNumber(const S: String; Step: Integer): String;
{ what the next pin placed starts with: its number counted by the pin direction and its name by the name direction }
procedure NextPinValues(var Number, PinName: String; PinDir, NameDir: Integer);

implementation

{ ===========================================================================
  AToI  (function)
  Parameters:
    const S: String - the text
  Returns:
    Integer - the number
  Notes:
    What the C library's atoi gives for text that starts with a number: leading spaces skipped,
    an optional sign, the digits after it, and 0 if there are none. What comes after the digits
    is ignored, and a number too big stops at the largest.
  =========================================================================== }
function AToI(const S: String): Integer;
var
  i: Integer;
  Neg: Boolean;
  V: Int64;
begin
  i := 1;
  while (i <= Length(S)) and (S[i] in [' ', #9, #10, #11, #12, #13]) do Inc(i);
  Neg := False;
  if (i <= Length(S)) and (S[i] in ['+', '-']) then
  begin
    Neg := S[i] = '-';
    Inc(i);
  end;
  V := 0;
  while (i <= Length(S)) and (S[i] in ['0'..'9']) do
  begin
    V := V * 10 + (Ord(S[i]) - Ord('0'));
    if V > 2147483647 then
      V := 2147483647;        // (strtol stops at the largest number)
    Inc(i);
  end;
  if Neg then
    V := -V;
  Result := Integer(V);
end;

{ ===========================================================================
  IncrementLabelText  (function)
  Parameters:
    const S: String - text
    Dir: Integer - whole number
  Returns:
    String
  Notes:
    From the first digit or minus sign to the end is taken as a number (what comes after the
    digits is not kept) and written back counted by Dir: "A1" with +1 is "A2", "R9" is "R10",
    "A-3" counts from -3 and gives "A-2", and "D1-5" gives "D2". Text with no digit or minus
    sign is returned as it was.
  =========================================================================== }
function IncrementLabelText(const S: String; Dir: Integer): String;
var
  p: Integer;
begin
  p := 1;
  while (p <= Length(S)) and not (S[p] in ['0'..'9', '-']) do Inc(p);
  if p > Length(S) then
    Exit(S);
  Result := Copy(S, 1, p - 1) + IntToStr(Integer(Int64(AToI(Copy(S, p, MaxInt))) + Dir));      // (a whole number as in C: past the largest it wraps round)
end;

{ ===========================================================================
  IncrementNumber  (function)
  Parameters:
    const S: String - text
    Step: Integer - whole number
  Returns:
    String
  Notes:
    The first run of digits is counted and kept from 1 to 999 (so counting down stops at 1),
    with whatever came before and after it kept: "A1B" with +1 is "A2B". With no digits, the
    last character is moved along by Step if it is still a letter afterwards (so "A" is "B", but
    "Z" stays "Z" going up and "A" stays "A" going down).
  =========================================================================== }
function IncrementNumber(const S: String; Step: Integer): String;
var
  p, q, N: Integer;
  Ch: Integer;
begin
  Result := S;
  p := 1;
  while (p <= Length(S)) and not (S[p] in ['0'..'9']) do Inc(p);
  if p <= Length(S) then
  begin
    q := p;
    while (q <= Length(S)) and (S[q] in ['0'..'9']) do Inc(q);
    N := AToI(Copy(S, p, q - p)) + Step;
    if N > 999 then
      N := 999;
    if N < 1 then
      N := 1;
    Result := Copy(S, 1, p - 1) + IntToStr(N) + Copy(S, q, MaxInt);
  end
  else if Length(S) > 0 then
  begin
    Ch := Ord(S[Length(S)]) + Step;
    if ((Ch >= Ord('A')) and (Ch <= Ord('Z'))) or ((Ch >= Ord('a')) and (Ch <= Ord('z'))) then
      Result[Length(Result)] := Chr(Ch);
  end;
end;

{ ===========================================================================
  NextPinValues  (procedure)
  Parameters:
    var Number: String - text (in/out: changed by the call)
    var PinName: String - text (in/out: changed by the call)
    PinDir: Integer - whole number
    NameDir: Integer - whole number
  Notes:
    CDrawPin::LButtonDown after a pin is placed: the number is counted by the pin direction and
    the name by the name direction, both as IncrementNumber does.
  =========================================================================== }
procedure NextPinValues(var Number, PinName: String; PinDir, NameDir: Integer);
begin
  Number := IncrementNumber(Number, PinDir);
  PinName := IncrementNumber(PinName, NameDir);
end;

end.
