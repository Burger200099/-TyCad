// SPDX-License-Identifier: LGPL-2.1-or-later
{ UContacts - which contacts of a device are already drawn in a design (Insert Contact of a coil).

  A device (a relay, a contactor) is one part with a reference such as K1: its coil is one placed symbol and each contact another, all with the reference K1. A placed
  symbol knows which object of its part it draws (TPartCopy.ObjectName / ObjectKind), so the contacts in use are found by looking at every sheet for symbols of that part
  with that reference whose object is a Contact.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UContacts;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, UDrawTypes, UDrawingObjects, USymbols, UDesign, ULinks;

type
  TStringArray = array of String;
  TIntegerArray = array of Integer;

type
  { where an object of a device is drawn: the placed symbol, its sheet (0-based) and ladder line (0 when the sheet has no rung grid there) }
  TPlacedObject = record
    ObjectName: String;
    Sheet, Line: Integer;
    Obj: TDrawMethod;
  end;
  TPlacedObjectArray = array of TPlacedObject;

{ every placed symbol of the part PartUID with the reference Ref (the objects of that device drawn so far). A reference that is not numbered yet (one with a ?) does not say
  which device it is, so then only the symbols with the ids in OnlyIds count }
function PlacedObjectsOf(Design: TDesignFile; const PartUID, Ref: String; const OnlyIds: array of Integer): TPlacedObjectArray;

{ the ids of the symbols that make up the device the symbol Sel belongs to, found at the time it is chosen: Sel itself and, for each other object of the same part and reference
  (all sheets) that Sel's object and the ones already taken do not cover, the first symbol that draws it. For a numbered reference every symbol with it is the device, so this is for
  the unnumbered ones (CB?), where the reference alone cannot say which symbols belong together; two devices that are both still CB? of one part are taken as one }
function LinkedSymbolIds(Design: TDesignFile; const PartUID, Ref: String; Sel: TDrawMethod): TIntegerArray;

{ names of the contact objects already placed for the part PartUID with the reference Ref (all sheets; the reference compared ignoring case) }
function UsedContactNames(Design: TDesignFile; const PartUID, Ref: String): TStringArray;

implementation

{ ===========================================================================
  UsedContactNames  (function)
  Parameters:
    Design: TDesignFile - the design
    const PartUID, Ref: String - the part's GUID and the device's reference
  Returns:
    TStringArray - ObjectName of every placed symbol of that part and reference whose ObjectKind is Contact
  Notes:
    A symbol with no part data, or one that draws the coil, does not count.
  =========================================================================== }
function UsedContactNames(Design: TDesignFile; const PartUID, Ref: String): TStringArray;
var
  Sheet, i: Integer;
  Obj: TDrawingObject;
  M: TDrawMethod;
  D: TObject;
begin
  SetLength(Result, 0);
  if (Design = nil) or (PartUID = '') then
    Exit;
  for Sheet := 0 to Design.SheetCount - 1 do
    for i := 0 to Design.Sheets[Sheet].Drawing.Count - 1 do
    begin
      Obj := Design.Sheets[Sheet].Drawing[i];
      if Obj.GetType <> xMethodEx3 then
        Continue;
      M := Obj as TDrawMethod;
      D := M.GetSymbolData;
      if not (D is TDesignFileSymbol) then
        Continue;
      with TDesignFileSymbol(D).PartInfo do
        if SameText(UID, PartUID) and SameText(M.GetRef, Ref) and (ObjectKind = 'Contact') then
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := ObjectName;
        end;
    end;
end;

{ ===========================================================================
  LinkedSymbolIds  (function)
  Parameters:
    Design: TDesignFile - the design
    const PartUID, Ref: String - the part's GUID and the reference of Sel
    Sel: TDrawMethod - the chosen symbol of the part
  Returns:
    TIntegerArray - the ids of Sel and of one symbol for each other object of the device, in sheet order
  =========================================================================== }
function LinkedSymbolIds(Design: TDesignFile; const PartUID, Ref: String; Sel: TDrawMethod): TIntegerArray;
var
  Sh, i, q: Integer;
  M: TDrawMethod;
  D: TObject;
  Taken: TStringArray;
  Nm: String;
  Dup: Boolean;
begin
  SetLength(Result, 0);
  SetLength(Taken, 0);
  if Sel = nil then
    Exit;
  SetLength(Result, 1);
  Result[0] := Sel.Id;
  if (Design = nil) or (PartUID = '') then
    Exit;
  if Sel.GetSymbolData is TDesignFileSymbol then
  begin
    SetLength(Taken, 1);
    Taken[0] := TDesignFileSymbol(Sel.GetSymbolData).PartInfo.ObjectName;
  end;
  for Sh := 0 to Design.SheetCount - 1 do
    for i := 0 to Design.Sheets[Sh].Drawing.Count - 1 do
    begin
      if Design.Sheets[Sh].Drawing[i].GetType <> xMethodEx3 then
        Continue;
      M := Design.Sheets[Sh].Drawing[i] as TDrawMethod;
      if M = Sel then
        Continue;
      D := M.GetSymbolData;
      if not (D is TDesignFileSymbol) then
        Continue;
      if not SameText(TDesignFileSymbol(D).PartInfo.UID, PartUID) or not SameText(M.GetRef, Ref) then
        Continue;
      Nm := TDesignFileSymbol(D).PartInfo.ObjectName;
      Dup := False;
      for q := 0 to High(Taken) do
        if SameText(Taken[q], Nm) then
          Dup := True;
      if Dup then
        Continue;
      SetLength(Taken, Length(Taken) + 1);
      Taken[High(Taken)] := Nm;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := M.Id;
    end;
end;

{ ===========================================================================
  PlacedObjectsOf  (function)
  Parameters:
    Design: TDesignFile - the design
    const PartUID, Ref: String - the part's GUID and the device's reference
    OnlyIds - the symbols that stand for the device while its reference has a ? (none: nothing is found)
  Returns:
    TPlacedObjectArray - one entry for each placed symbol of the device, in sheet order
  =========================================================================== }
function PlacedObjectsOf(Design: TDesignFile; const PartUID, Ref: String; const OnlyIds: array of Integer): TPlacedObjectArray;
var
  Sh, i, Ln, q: Integer;
  M: TDrawMethod;
  D: TObject;
  Unnumbered, Listed: Boolean;
begin
  SetLength(Result, 0);
  if (Design = nil) or (PartUID = '') then
    Exit;
  Unnumbered := (Ref = '') or (Pos('?', Ref) > 0);
  for Sh := 0 to Design.SheetCount - 1 do
    for i := 0 to Design.Sheets[Sh].Drawing.Count - 1 do
    begin
      if Design.Sheets[Sh].Drawing[i].GetType <> xMethodEx3 then
        Continue;
      M := Design.Sheets[Sh].Drawing[i] as TDrawMethod;
      D := M.GetSymbolData;
      if not (D is TDesignFileSymbol) then
        Continue;
      if not SameText(TDesignFileSymbol(D).PartInfo.UID, PartUID) then
        Continue;
      if Unnumbered then
      begin
        Listed := False;
        for q := 0 to High(OnlyIds) do
          if OnlyIds[q] = M.Id then
            Listed := True;
        if not Listed then
          Continue;
      end
      else if not SameText(M.GetRef, Ref) then
        Continue;
      if not LineNumberOfObject(Design.Sheets[Sh], M, Ln) then
        Ln := 0;
      SetLength(Result, Length(Result) + 1);
      with Result[High(Result)] do
      begin
        ObjectName := TDesignFileSymbol(D).PartInfo.ObjectName;
        Sheet := Sh;
        Line := Ln;
        Obj := M;
      end;
    end;
end;

end.
