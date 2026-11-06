// SPDX-License-Identifier: LGPL-2.1-or-later
{ Table cells that show the text of other objects of the sheet.

  CollectTextSources lists what a cell can show: the text of a text, wire label, note, power symbol or linked text (KIND:"text"), and each field of a placed symbol
  (Symbol R1:Value:"10k"), sorted alphabetically. A cell holds the id of the object and the number of the field (UTable.TTableLink); ResolveTableLinks, called whenever
  the drawing changes (ULinks.UpdateLinks), puts the object's text in the cell. When the object (or the field) is gone the cell says #REF! and the link is cut.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UTableLinks;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, UDrawTypes, UDrawingObjects, UTable, UDesign;

type
  TTextSource = record
    Obj: TDrawingObject;
    Field: Integer;          // the field of a symbol; -1 for the text of the other objects
    Caption: String;         // Kind:"text", for the list
  end;
  TTextSources = array of TTextSource;

const
  TABLE_REF_ERROR = '#REF!';

{ everything on the sheet with a text a cell can show, sorted by caption (without regard to case) }
function CollectTextSources(Sheet: TDesignSheet): TTextSources;
{ the text of an object (a field of a symbol with Field >= 0); False when the object has no such text }
function SourceText(Obj: TDrawingObject; Field: Integer; out Text: String): Boolean;
{ works out the text of every linked cell of the tables of the sheet; a link to an object that is not on the sheet becomes #REF! }
procedure ResolveTableLinks(Sheet: TDesignSheet);
{ the object on the sheet with that id, or nil }
function FindObjectById(Sheet: TDesignSheet; Id: Integer): TDrawingObject;

implementation

uses
  Math;

function OneLine(const S: String): String;
begin
  Result := StringReplace(StringReplace(StringReplace(S, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]), #9, ' ', [rfReplaceAll]);
end;

{ ===========================================================================
  KindName  (function)
  Parameters:
    Obj: TDrawingObject - the object
  Returns:
    String - the kind as the list names it, '' for an object that has no text of its own
  =========================================================================== }
function KindName(Obj: TDrawingObject): String;
begin
  Result := '';
  if Obj is TDrawMethod then
    Result := ''                      // (symbols are listed field by field)
  else if Obj is TDrawText then
    Result := 'Text'
  else if Obj is TDrawLabel then
    Result := 'Wire Label'
  else if Obj is TDrawNoteText then
    Result := 'Note'
  else if Obj is TDrawPower then
    Result := 'Power'
  else if Obj is TDrawRefText then
    Result := 'Linked Text';
end;

function SourceText(Obj: TDrawingObject; Field: Integer; out Text: String): Boolean;
begin
  Result := True;
  Text := '';
  if Obj is TDrawMethod then
  begin
    if (Field >= 0) and (Field < Length(TDrawMethod(Obj).Fields)) then
      Text := TDrawMethod(Obj).Fields[Field].Value
    else
      Result := False;
  end
  else if Field >= 0 then
    Result := False
  else if Obj is TDrawText then
    Text := TDrawText(Obj).Str
  else if Obj is TDrawLabel then
    Text := TDrawLabel(Obj).Str
  else if Obj is TDrawNoteText then
    Text := TDrawNoteText(Obj).Str
  else if Obj is TDrawPower then
    Text := TDrawPower(Obj).Str
  else if Obj is TDrawRefText then
    Text := TDrawRefText(Obj).CachedText
  else
    Result := False;
  Text := OneLine(Text);
end;

function FindObjectById(Sheet: TDesignSheet; Id: Integer): TDrawingObject;
var
  i: Integer;
begin
  Result := nil;
  if (Sheet = nil) or (Id = 0) then
    Exit;
  for i := 0 to Sheet.Drawing.Count - 1 do
    if Sheet.Drawing[i].Id = Id then
    begin
      Result := Sheet.Drawing[i];
      Exit;
    end;
end;

function CollectTextSources(Sheet: TDesignSheet): TTextSources;
var
  i, f, n, a, b: Integer;
  O: TDrawingObject;
  M: TDrawMethod;
  K, T, Nm: String;
  Tmp: TTextSource;

  procedure Put(AObj: TDrawingObject; AField: Integer; const ACaption: String);
  begin
    SetLength(Result, n + 1);
    Result[n].Obj := AObj; Result[n].Field := AField; Result[n].Caption := ACaption;
    Inc(n);
  end;

begin
  SetLength(Result, 0);
  n := 0;
  if Sheet = nil then
    Exit;
  for i := 0 to Sheet.Drawing.Count - 1 do
  begin
    O := Sheet.Drawing[i];
    if O is TDrawMethod then
    begin
      M := TDrawMethod(O);
      if Length(M.Fields) = 0 then
        Continue;
      if O is TDrawSymbolText then K := 'Symbol Text ' else K := 'Symbol ';
      for f := 0 to High(M.Fields) do
        if (M.Fields[f].Value <> '') and (M.Fields[f].Value <> '..') then          // ('..' is a library's mark for a field with nothing in it)
        begin
          Nm := M.Fields[f].Description;
          if Nm = '' then Nm := 'Field ' + IntToStr(f + 1);
          Put(O, f, Trim(K + OneLine(M.Fields[0].Value)) + ':' + Nm + ':"' + OneLine(M.Fields[f].Value) + '"');
        end;
    end
    else
    begin
      K := KindName(O);
      if (K <> '') and SourceText(O, -1, T) and (T <> '') then
        Put(O, -1, K + ':"' + T + '"');
    end;
  end;
  { a plain insertion sort by caption (the lists are short) }
  for a := 1 to High(Result) do
  begin
    Tmp := Result[a];
    b := a - 1;
    while (b >= 0) and (CompareText(Result[b].Caption, Tmp.Caption) > 0) do
    begin
      Result[b + 1] := Result[b];
      Dec(b);
    end;
    Result[b + 1] := Tmp;
  end;
end;

procedure ResolveTableLinks(Sheet: TDesignSheet);
var
  i, r, c: Integer;
  T: TDrawTable;
  Lk: TTableLink;
  Src: TDrawingObject;
  Txt: String;
begin
  if Sheet = nil then
    Exit;
  for i := 0 to Sheet.Drawing.Count - 1 do
    if Sheet.Drawing[i] is TDrawTable then
    begin
      T := TDrawTable(Sheet.Drawing[i]);
      for r := 0 to T.Rows - 1 do
        for c := 0 to T.Cols - 1 do
        begin
          Lk := T.LinkAt(r, c);
          if Lk.ObjId = 0 then
            Continue;
          Src := FindObjectById(Sheet, Lk.ObjId);
          if (Src <> nil) and SourceText(Src, Lk.Field, Txt) then
            T.SetShown(r, c, Txt)
          else
          begin
            T.SetShown(r, c, TABLE_REF_ERROR);
            T.SetLink(r, c, 0, -1);
          end;
        end;
      T.Fit;
    end;
end;

end.
