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
  Classes, SysUtils, UDrawTypes, UDrawingObjects, USymbols, UDesign;

type
  TStringArray = array of String;

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

end.
