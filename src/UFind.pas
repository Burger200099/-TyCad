// SPDX-License-Identifier: LGPL-2.1-or-later
{ Find and Replace of the text in a design.

  What can be searched is what TinyCAD's own Find searches (CDrawingObject::Find and its overrides): the text of a
  label, a text, a note and a power symbol, the name of a pin, and the value of every field of a placed symbol (its
  reference, name, and the others, shown or not). TinyCAD's Find lists each object that contains the text; this adds
  what the Find and Replace dialog needs: Find Next and Find Previous, match case, whole word, Replace and Replace All.

  A search covers every sheet, in the order of the design: sheet by sheet, the objects of a sheet in their drawing
  order, the texts of an object in order, the occurrences in a text from left to right. It wraps round at the end.
  Occurrences do not overlap. Without "match case" capital and small ASCII letters are the same. A "whole word" has
  no letter, digit, underscore or non-ASCII character just before or after it.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UFind;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, UDPoint, UDrawTypes, UDrawingObjects, UDesign;

type
  TSearchOption = (foMatchCase, foWholeWord);
  TSearchOptions = set of TSearchOption;

  { one occurrence of the text that is looked for }
  TFindHit = record
    Sheet: Integer;            // the sheet, 0 for the first
    ObjIndex: Integer;         // the object's place in the sheet's drawing
    Obj: TDrawingObject;       // the object that holds the text
    Slot: Integer;             // which of its texts (0, except for the fields of a symbol)
    Offset, Len: Integer;      // where it is in that text (1 for the first character) and how long it is
  end;
  TFindHitArray = array of TFindHit;

  { one object that contains the text, as TinyCAD's Find lists it }
  TObjectHit = record
    Sheet: Integer;
    ObjIndex: Integer;
    Obj: TDrawingObject;
    Slot: Integer;             // the first of its texts that has the text in it
    Name: String;              // what the object is called in the list (Label, Text, Power ... or a symbol's name)
    Text: String;              // that text, whole
    Point: TDPoint;            // where the object is: where TinyCAD puts the red circle
  end;
  TObjectHitArray = array of TObjectHit;

  { a search in progress: what is looked for, and where the last occurrence was found }
  TFindSession = class
  private
    FHasCurrent: Boolean;
    FIsMatch: Boolean;         // the current place is an occurrence that has not been replaced (False after a replacement)
    FCurrent: TFindHit;
    FWrapped: Boolean;
    function StillThere(Design: TDesignFile): Boolean;
    function ScopedHits(Design: TDesignFile): TFindHitArray;
  public
    Needle, Replacement: String;
    Options: TSearchOptions;
    OnlySheet: Integer;        // -1 searches every sheet of the design, otherwise only the sheet with this index
    constructor Create;
    procedure Reset;
    function FindNext(Design: TDesignFile; Down: Boolean; StartSheet: Integer): Boolean;
    function ReplaceCurrent(Design: TDesignFile): Boolean;
    function ReplaceAll(Design: TDesignFile; out ObjectsChanged: Integer): Integer;
    property HasCurrent: Boolean read FHasCurrent;
    property Current: TFindHit read FCurrent;
    property Wrapped: Boolean read FWrapped;
  end;

{ the texts of an object that can be searched }
function SlotCount(Obj: TDrawingObject): Integer;
function SlotText(Obj: TDrawingObject; Slot: Integer): String;
procedure SetSlotText(Obj: TDrawingObject; Slot: Integer; const S: String);
function SlotName(Obj: TDrawingObject; Slot: Integer): String;
{ the first occurrence of Needle in Text at or after position From (1 for the start), or 0 }
function FindInText(const Text, Needle: String; Opts: TSearchOptions; From: Integer): Integer;
{ every occurrence in the whole design, in the order of the design }
function CollectHits(Design: TDesignFile; const Needle: String; Opts: TSearchOptions): TFindHitArray;
{ what TinyCAD's own Find lists: each object that has the text in any of its texts (not case sensitive), once }
function FindObjects(Design: TDesignFile; const Needle: String): TObjectHitArray;
{ what an object is called in TinyCAD's list of what was found }
function ObjectName(Obj: TDrawingObject): String;

implementation

{ ===========================================================================
  SlotCount  (function)
  Parameters:
    Obj: TDrawingObject - the drawing object
  Returns:
    Integer
  Notes:
    A label, a text, a note, a power symbol and a pin have one; a placed symbol has one for each
    of its fields.
  =========================================================================== }
function SlotCount(Obj: TDrawingObject): Integer;
begin
  if Obj is TDrawMethod then
    Result := Length(TDrawMethod(Obj).Fields)
  else if (Obj is TDrawLabel) or (Obj is TDrawText) or (Obj is TDrawNoteText) or (Obj is TDrawPower) or (Obj is TDrawPin) then
    Result := 1
  else
    Result := 0;
end;

{ ===========================================================================
  SlotText  (function)
  Parameters:
    Obj: TDrawingObject - the object
    Slot: Integer - which of its texts
  Returns:
    String - the text, empty if the object has no such text
  Notes:
    One of the searchable texts of an object, as it is stored (variables such as $(TITLE) are
    not expanded).
  =========================================================================== }
function SlotText(Obj: TDrawingObject; Slot: Integer): String;
begin
  Result := '';
  if (Slot < 0) or (Slot >= SlotCount(Obj)) then
    Exit;
  if Obj is TDrawMethod then
    Result := TDrawMethod(Obj).Fields[Slot].Value
  else if Obj is TDrawLabel then
    Result := TDrawLabel(Obj).Str
  else if Obj is TDrawText then
    Result := TDrawText(Obj).Str
  else if Obj is TDrawNoteText then
    Result := TDrawNoteText(Obj).Str
  else if Obj is TDrawPower then
    Result := TDrawPower(Obj).Str
  else if Obj is TDrawPin then
    Result := TDrawPin(Obj).Str;
end;

{ ===========================================================================
  SetSlotText  (procedure)
  Parameters:
    Obj: TDrawingObject - the drawing object
    Slot: Integer - whole number
    const S: String - text
  Notes:
    Changes one text of an object. The layout of the sheet has to be worked out again
    afterwards.
  =========================================================================== }
procedure SetSlotText(Obj: TDrawingObject; Slot: Integer; const S: String);
begin
  if (Slot < 0) or (Slot >= SlotCount(Obj)) then
    Exit;
  if Obj is TDrawMethod then
    TDrawMethod(Obj).Fields[Slot].Value := S
  else if Obj is TDrawLabel then
    TDrawLabel(Obj).Str := S
  else if Obj is TDrawText then
    TDrawText(Obj).Str := S
  else if Obj is TDrawNoteText then
    TDrawNoteText(Obj).Str := S
  else if Obj is TDrawPower then
    TDrawPower(Obj).Str := S
  else if Obj is TDrawPin then
    TDrawPin(Obj).Str := S;
end;

{ ===========================================================================
  SlotName  (function)
  Parameters:
    Obj: TDrawingObject - the object
    Slot: Integer - which of its texts
  Returns:
    String - the name
  Notes:
    What to call one of an object's texts: Label, Text, Note, Power, Pin, or, for a placed
    symbol, the description of the field (Ref, Name ...).
  =========================================================================== }
function SlotName(Obj: TDrawingObject; Slot: Integer): String;
begin
  Result := '';
  if (Slot < 0) or (Slot >= SlotCount(Obj)) then
    Exit;
  if Obj is TDrawMethod then
    Result := TDrawMethod(Obj).Fields[Slot].Description
  else if Obj is TDrawLabel then
    Result := 'Label'
  else if Obj is TDrawText then
    Result := 'Text'
  else if Obj is TDrawNoteText then
    Result := 'Note'
  else if Obj is TDrawPower then
    Result := 'Power'
  else if Obj is TDrawPin then
    Result := 'Pin';
end;

{ ===========================================================================
  IsWordChar  (function)
  Parameters:
    C: Char - the character
  Returns:
    Boolean - True if it does
  Notes:
    Whether a character counts as part of a word for "whole word" searches: a letter, digit,
    underscore, or any non-ASCII byte.
  =========================================================================== }
function IsWordChar(C: Char): Boolean;
begin
  Result := (C in ['0'..'9', 'A'..'Z', 'a'..'z', '_']) or (Ord(C) > 127);
end;

{ ===========================================================================
  FindInText  (function)
  Parameters:
    const Text: String - the text
    const Needle: String - text
    Opts: TSearchOptions - the sheet options
    From: Integer - whole number
  Returns:
    Integer
  Notes:
    Without match case, capital and small letters (ASCII) are the same. With whole word, an
    occurrence only counts when the characters just before and after it are not part of a word
    (letters, digits, underscore, anything non-ASCII).
  =========================================================================== }
function FindInText(const Text, Needle: String; Opts: TSearchOptions; From: Integer): Integer;
var
  H, N: String;
  p, Stop: Integer;
begin
  Result := 0;
  if (Needle = '') or (From < 1) then
    Exit;
  if foMatchCase in Opts then begin
    H := Text;
    N := Needle;
  end
  else begin
    H := LowerCase(Text);
    N := LowerCase(Needle);
  end;
  p := From;
  Stop := Length(H) - Length(N) + 1;
  while p <= Stop do
  begin
    if Copy(H, p, Length(N)) = N then
    begin
      if (foWholeWord in Opts) and
         (((p > 1) and IsWordChar(H[p - 1])) or ((p + Length(N) <= Length(H)) and IsWordChar(H[p + Length(N)]))) then
        Inc(p)
      else
      begin
        Result := p;
        Exit;
      end;
    end
    else
      Inc(p);
  end;
end;

{ ===========================================================================
  CollectHits  (function)
  Parameters:
    Design: TDesignFile - the design to search
    const Needle: String - what to look for
    Opts: TSearchOptions - match case and whole word
  Returns:
    TFindHitArray - the occurrences, in that order
  Notes:
    Every occurrence of a text in the whole design, sheet by sheet, the objects of a sheet in
    drawing order, the texts of an object in order, left to right. Occurrences do not overlap.
  =========================================================================== }
function CollectHits(Design: TDesignFile; const Needle: String; Opts: TSearchOptions): TFindHitArray;
var
  s, o, k, p: Integer;
  Obj: TDrawingObject;
  T: String;
  H: TFindHit;
begin
  SetLength(Result, 0);
  if Needle = '' then
    Exit;
  for s := 0 to Design.SheetCount - 1 do
    for o := 0 to Design.Sheets[s].Drawing.Count - 1 do
    begin
      Obj := Design.Sheets[s].Drawing[o];
      for k := 0 to SlotCount(Obj) - 1 do
      begin
        T := SlotText(Obj, k);
        p := FindInText(T, Needle, Opts, 1);
        while p > 0 do
        begin
          H.Sheet := s; H.ObjIndex := o; H.Obj := Obj; H.Slot := k; H.Offset := p; H.Len := Length(Needle);
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := H;
          p := FindInText(T, Needle, Opts, p + Length(Needle));
        end;
      end;
    end;
end;

{ ===========================================================================
  TFindSession.Create  (constructor)
  Parameters:  none
  Notes:
    A new session looks at every sheet (OnlySheet is -1) and has found nothing yet.
  =========================================================================== }
constructor TFindSession.Create;
begin
  inherited Create;
  OnlySheet := -1;
  Reset;
end;

{ ===========================================================================
  TFindSession.ScopedHits  (function)
  Parameters:
    Design: TDesignFile - the design
  Returns:
    TFindHitArray - the occurrences in the sheets the search covers
  Notes:
    CollectHits, kept to the sheet OnlySheet names when it is not -1 ("search entire file" off).
  =========================================================================== }
function TFindSession.ScopedHits(Design: TDesignFile): TFindHitArray;
var
  All: TFindHitArray;
  i: Integer;
begin
  All := CollectHits(Design, Needle, Options);
  if OnlySheet < 0 then
    Exit(All);
  SetLength(Result, 0);
  for i := 0 to High(All) do
    if All[i].Sheet = OnlySheet then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := All[i];
    end;
end;

{ ===========================================================================
  TFindSession.Reset  (procedure)
  Parameters:  none
  Notes:
    Forgets where the last occurrence was found (for a new document, or when the search starts
    afresh).
  =========================================================================== }
procedure TFindSession.Reset;
begin
  FHasCurrent := False;
  FIsMatch := False;
  FWrapped := False;
end;

{ ===========================================================================
  TFindSession.StillThere  (function)
  Parameters:
    Design: TDesignFile - the design
  Returns:
    Boolean
  Notes:
    Edits between searches may delete the object or change its text. If it is still there its
    place in the sheet's drawing is brought up to date.
  =========================================================================== }
function TFindSession.StillThere(Design: TDesignFile): Boolean;
var
  i: Integer;
begin
  Result := False;
  if (not FHasCurrent) or (FCurrent.Sheet < 0) or (FCurrent.Sheet >= Design.SheetCount) then
    Exit;
  i := Design.Sheets[FCurrent.Sheet].Drawing.IndexOf(FCurrent.Obj);
  if (i < 0) or (FCurrent.Slot >= SlotCount(FCurrent.Obj)) then
    Exit;
  FCurrent.ObjIndex := i;
  Result := True;
end;

{ ===========================================================================
  TFindSession.FindNext  (function)
  Parameters:
    Design: TDesignFile - the design
    Down: Boolean - flag
    StartSheet: Integer - whole number
  Returns:
    Boolean
  Notes:
    Carries on from the occurrence found (or replaced) last, if its object is still there;
    otherwise it starts at the beginning of StartSheet (forwards) or the end of it (backwards).
    When there is nothing more in that direction it wraps round, and Wrapped says so.
  =========================================================================== }
function TFindSession.FindNext(Design: TDesignFile; Down: Boolean; StartSheet: Integer): Boolean;
var
  Hits: TFindHitArray;
  i, Pick, c: Integer;
  UseCurrent: Boolean;
  function Cmp(const H: TFindHit): Integer;       // where a hit is compared with the current place: -1 before it, 0 same text, 1 after it
  begin
    if H.Sheet <> FCurrent.Sheet then
      Result := Ord(H.Sheet > FCurrent.Sheet) * 2 - 1
    else if H.ObjIndex <> FCurrent.ObjIndex then
      Result := Ord(H.ObjIndex > FCurrent.ObjIndex) * 2 - 1
    else if H.Slot <> FCurrent.Slot then
      Result := Ord(H.Slot > FCurrent.Slot) * 2 - 1
    else
      Result := 0;
  end;
begin
  FWrapped := False;
  Result := False;
  Hits := ScopedHits(Design);
  if Length(Hits) = 0 then
  begin
    FHasCurrent := False;
    Exit;
  end;
  UseCurrent := StillThere(Design);
  Pick := -1;
  if Down then
  begin
    for i := 0 to High(Hits) do
    begin
      if UseCurrent then
      begin
        c := Cmp(Hits[i]);
        if (c > 0) or ((c = 0) and (Hits[i].Offset >= FCurrent.Offset + FCurrent.Len)) then begin
          Pick := i;
          Break;
        end;
      end
      else if Hits[i].Sheet >= StartSheet then begin
        Pick := i;
        Break;
      end;
    end;
    if Pick < 0 then begin
      Pick := 0;
      FWrapped := True;
    end;
  end
  else
  begin
    for i := High(Hits) downto 0 do
    begin
      if UseCurrent then
      begin
        c := Cmp(Hits[i]);
        if (c < 0) or ((c = 0) and (Hits[i].Offset + Hits[i].Len <= FCurrent.Offset)) then begin
          Pick := i;
          Break;
        end;
      end
      else if Hits[i].Sheet <= StartSheet then begin
        Pick := i;
        Break;
      end;
    end;
    if Pick < 0 then begin
      Pick := High(Hits);
      FWrapped := True;
    end;
  end;
  FCurrent := Hits[Pick];
  FHasCurrent := True;
  FIsMatch := True;
  Result := True;
end;

{ ===========================================================================
  TFindSession.ReplaceCurrent  (function)
  Parameters:
    Design: TDesignFile - the design
  Returns:
    Boolean
  Notes:
    Replaces the occurrence that was found last, if it is still there and still reads as what is
    looked for; otherwise nothing is changed and False is returned (the caller then finds the
    next one). The current place moves to just after the new text, so the next Find Next carries
    on from there. The layout of the sheet is not worked out again here.
  =========================================================================== }
function TFindSession.ReplaceCurrent(Design: TDesignFile): Boolean;
var
  T, Was: String;
begin
  Result := False;
  if (not FIsMatch) or (not StillThere(Design)) then
    Exit;
  T := SlotText(FCurrent.Obj, FCurrent.Slot);
  Was := Copy(T, FCurrent.Offset, FCurrent.Len);
  if (Length(Was) <> Length(Needle)) or (FindInText(T, Needle, Options, FCurrent.Offset) <> FCurrent.Offset) then
    Exit;
  SetSlotText(FCurrent.Obj, FCurrent.Slot, Copy(T, 1, FCurrent.Offset - 1) + Replacement + Copy(T, FCurrent.Offset + FCurrent.Len, MaxInt));
  FCurrent.Len := Length(Replacement);
  FIsMatch := False;
  Result := True;
end;

{ ===========================================================================
  TFindSession.ReplaceAll  (function)
  Parameters:
    Design: TDesignFile - the design
    out ObjectsChanged: Integer - whole number (out: set by the call)
  Returns:
    Integer
  Notes:
    Replaces every occurrence in the sheets the search covers (the whole design unless OnlySheet names one). Text that the replacement itself contains is
    not looked at again. The layout of each sheet that changed is worked out again. The search
    starts afresh afterwards.
  =========================================================================== }
function TFindSession.ReplaceAll(Design: TDesignFile; out ObjectsChanged: Integer): Integer;
var
  s, o, k, p, Last: Integer;
  Obj: TDrawingObject;
  T, R: String;
  SheetChanged, ObjChanged: Boolean;
begin
  Result := 0;
  ObjectsChanged := 0;
  if Needle = '' then
    Exit;
  for s := 0 to Design.SheetCount - 1 do
  begin
    if (OnlySheet >= 0) and (s <> OnlySheet) then
      Continue;
    SheetChanged := False;
    for o := 0 to Design.Sheets[s].Drawing.Count - 1 do
    begin
      Obj := Design.Sheets[s].Drawing[o];
      ObjChanged := False;
      for k := 0 to SlotCount(Obj) - 1 do
      begin
        T := SlotText(Obj, k);
        p := FindInText(T, Needle, Options, 1);
        if p = 0 then
          Continue;
        R := '';
        Last := 1;
        while p > 0 do
        begin
          R := R + Copy(T, Last, p - Last) + Replacement;
          Last := p + Length(Needle);
          Inc(Result);
          p := FindInText(T, Needle, Options, Last);
        end;
        R := R + Copy(T, Last, MaxInt);
        SetSlotText(Obj, k, R);
        ObjChanged := True;
      end;
      if ObjChanged then
      begin
        Inc(ObjectsChanged);
        SheetChanged := True;
      end;
    end;
    if SheetChanged then
      Design.Sheets[s].UpdateLayout;
  end;
  Reset;
end;

{ ===========================================================================
  ObjectName  (function)
  Parameters:
    Obj: TDrawingObject - the drawing object
  Returns:
    String
  Notes:
    As TinyCAD's GetName: Label, Text, BusName, NoteText, Pin and Power; a placed symbol is
    called by the value of its Name field.
  =========================================================================== }
function ObjectName(Obj: TDrawingObject): String;
begin
  if Obj is TDrawMethod then
    Result := TDrawMethod(Obj).GetName
  else if Obj is TDrawLabel then
    Result := 'Label'
  else if Obj is TDrawText then
  begin
    if TDrawText(Obj).Kind = xLabelEx2 then
      Result := 'Label'
    else if TDrawText(Obj).Kind = xBusNameEx then
      Result := 'BusName'
    else
      Result := 'Text';
  end
  else if Obj is TDrawNoteText then
    Result := 'NoteText'
  else if Obj is TDrawPin then
    Result := 'Pin'
  else if Obj is TDrawPower then
    Result := 'Power'
  else
    Result := '';
end;

{ ===========================================================================
  FindObjects  (function)
  Parameters:
    Design: TDesignFile - the design
    const Needle: String - text
  Returns:
    TObjectHitArray
  Notes:
    This is TinyCAD's own Find (CTinyCadView::OnFindFind): not case sensitive, the text can be
    anywhere in the object's text, and each object is listed once, with the first of its texts
    that has the text in it (for a placed symbol, the first field). The position is the object's
    own point, where TinyCAD puts its red circle.
  =========================================================================== }
function FindObjects(Design: TDesignFile; const Needle: String): TObjectHitArray;
var
  s, o, k: Integer;
  Obj: TDrawingObject;
  H: TObjectHit;
begin
  SetLength(Result, 0);
  if Needle = '' then
    Exit;
  for s := 0 to Design.SheetCount - 1 do
  begin
    { an object's own point (a label's text box, for one) is worked out by the layout, which a sheet that has not been
      shown yet does not have }
    Design.Sheets[s].UpdateLayout;
    for o := 0 to Design.Sheets[s].Drawing.Count - 1 do
    begin
      Obj := Design.Sheets[s].Drawing[o];
      for k := 0 to SlotCount(Obj) - 1 do
        if FindInText(SlotText(Obj, k), Needle, [], 1) > 0 then
        begin
          H.Sheet := s; H.ObjIndex := o; H.Obj := Obj; H.Slot := k;
          H.Name := ObjectName(Obj);
          H.Text := SlotText(Obj, k);
          H.Point := Obj.PointA;
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := H;
          Break;
        end;
    end;
  end;
end;

end.
