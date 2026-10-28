// SPDX-License-Identifier: LGPL-2.1-or-later
{ Port of the symbol-definition part of Symbol.h/.cpp (CSymbolField, CDesignFileSymbol) and
  ListOfSymbols.*: the SYMBOLDEF tables stored inside each design.

  A symbol definition is a set of drawing objects (a nested <TinyCAD> block, or several inside
  <TinyCADSheets> for multi-part "heterogeneous" symbols) plus name/reference/fields.

  Reference points (REF_POINT) are preserved exactly as loaded. The C++ program also adds new
  ones lazily while placing symbols (it needs symbol geometry for that); regenerating them is
  left to the geometry step.

  Original: Copyright 1994-2019 Matt Pyne, LGPL 2.1+. This port keeps that licence. }
unit USymbols;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs, Math, UDPoint, UDrawTypes, UResources, UDrawingObjects, UXMLReader,
  UXMLWriter, UXMLCodec, UPartData;

var
  { When True, the extent used to place a part's reference point also counts the pins of the
    OTHER parts of a multi-part symbol (as designs made by older TinyCAD versions assume). The
    current C++ code does not, and neither does the default here. Experimental. }
  LegacyPartExtents: Boolean = False;

type
  { One per-symbol parameter definition (CSymbolField) }
  TSymbolFieldDef = record
    Name, Value, Default: String;
    Pos: TDPoint;
    FieldType: Cardinal; // SymbolFieldType, written as hex
  end;

  { One entry of the symbol cache (CDesignFileSymbolFilter plus its drawing). Entries read from a
    REF_POINT tag have a reference point but no View yet. }
  TSymbolFilter = class
  public
    Part: Integer;
    Power: Boolean;
    RefPoint: TDPoint;
    View: TSymbolView;   // owns the shifted copies; nil until built
    destructor Destroy; override;
  end;

  TDesignFileSymbol = class(TSymbolInfo)
  private
    FOpts: TDocOptionsBase;
    FMethods: TObjectList; // of TDrawingList, one per part when heterogeneous, else one
    FFilters: TObjectList; // of TSymbolFilter (std::map<filter, drawing> m_filter_cache)
    function MethodList(Index: Integer): TDrawingList;
    function FindFilter(Part: Integer; Power: Boolean): TSymbolFilter;
    function BuildView(Part: Integer; Power, HaveRef: Boolean; const Ref: TDPoint): TSymbolView;
    function CreateView(Part: Integer; Power: Boolean): TSymbolFilter;
    function ComputeTr(L: TDrawingList): TDPoint;
  public
    Name, Reference, Description, Guid: String;
    PartInfo: TPartCopy;      // set when the symbol is a generic part of a parts library: its GUID, the library's, name, class and required ratings (saved as <PART>); empty for a plain symbol
    NameType, RefType: Integer;
    Ppp: Integer; // BYTE: parts per package
    Fields: array of TSymbolFieldDef;
    Heterogeneous: Boolean;
    constructor Create(AOpts: TDocOptionsBase);
    destructor Destroy; override;
    procedure CreateNoSymbol;
    procedure LoadXML(R: TXMLReader);
    procedure SaveXML(W: TXMLWriter; WithRefPoints: Boolean = True);
    { C++ operator==: same name and identical serialisation (without REF_POINTs) }
    function SameAs(Other: TDesignFileSymbol): Boolean;
    function MethodCount: Integer;
    property Methods[Index: Integer]: TDrawingList read MethodList;
    { Used by loaders that fill the drawing(s) themselves (library symbols) }
    procedure ClearMethods;
    function AddMethod: TDrawingList;
    { Objects shown for a placed instance: CDesignFileSymbol::GetMethod without the geometry.
      Dest receives borrowed pointers. }
    procedure GetMethodObjects(Part: Integer; IncludePower: Boolean; Dest: TList);
    { ---- geometry (TSymbolInfo) ---- }
    function GetView(Part: Integer; IncludePower: Boolean): TSymbolView; override;
    function GetTr(Part: Integer; IncludePower: Boolean): TDPoint; override;
    function GetOrigin(Part: Integer; IncludePower: Boolean): TDPoint; override;
    function PartsPerPackage: Integer; override;
    function SymbolName: String; override;
    function SymbolReference: String; override;
    function SymbolNameType: Integer; override;
    function SymbolRefType: Integer; override;
    function IsHeterogeneous: Boolean; override;
    function FieldCount: Integer; override;
    function FieldName(Index: Integer): String; override;
    function FieldDefault(Index: Integer): String; override;
    function FieldType(Index: Integer): Integer; override;
    { The reference point CreateSymbol would compute from scratch (ignoring any saved
      REF_POINT): the snapped far corner of the drawing, kept on the pin grid. For testing and
      for placing a symbol the first time. }
    function ComputeRefPoint(Part: Integer; IncludePower: Boolean): TDPoint;
    { number of REF_POINT entries currently cached, and the nth entry }
    function CachedRefCount: Integer;
    procedure CachedRef(Index: Integer; out Part: Integer; out Power: Boolean; out Ref: TDPoint);
  end;

  TSymbolResource = class(TResourceItem)
  private
    FOpts: TDocOptionsBase;
  public
    Symbol: TDesignFileSymbol;
    constructor CreateFor(AOpts: TDocOptionsBase; ASymbol: TDesignFileSymbol);
    destructor Destroy; override;
    function Compare(Other: TResourceItem): Boolean; override;
    procedure WriteItem(W: TXMLWriter); override;
    procedure ReadItem(R: TXMLReader); override;
  end;

  TSymbolList = class(TResourceList)
  private
    FOpts: TDocOptionsBase;
  protected
    function CreateItem: TResourceItem; override;
  public
    constructor CreateFor(AOpts: TDocOptionsBase);
    function Symbol(Id: Integer): TDesignFileSymbol;
  end;

{ reads / writes one FIELD element of a symbol (a parameter of a name): the short form is the one of the library export, with the name, default and type only }
procedure LoadFieldXML(R: TXMLReader; var F: TSymbolFieldDef);
procedure SaveFieldXML(W: TXMLWriter; const F: TSymbolFieldDef; Simple: Boolean);

implementation

{ ---- TDesignFileSymbol ---- }

{ ===========================================================================
  TDesignFileSymbol.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options the symbol is part of
  Notes:
    Creates an empty symbol definition belonging to a sheet's options, with no parts and no
    cached drawings.
  =========================================================================== }
constructor TDesignFileSymbol.Create(AOpts: TDocOptionsBase);
begin
  inherited Create;
  FOpts := AOpts;
  FMethods := TObjectList.Create(True);
  FFilters := TObjectList.Create(True);
  NameType := default_show;
  RefType := default_show;
  Ppp := 1;
  Heterogeneous := False;
end;

{ ===========================================================================
  TDesignFileSymbol.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the parts and the cached views.
  =========================================================================== }
destructor TDesignFileSymbol.Destroy;
begin
  FFilters.Free;
  FMethods.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TDesignFileSymbol.MethodList  (function)
  Parameters:
    Index: Integer - part number, 0-based
  Returns:
    TDrawingList - the drawing objects of that part
  Notes:
    The master drawing of one part.
  =========================================================================== }
function TDesignFileSymbol.MethodList(Index: Integer): TDrawingList;
begin
  Result := TDrawingList(FMethods[Index]);
end;

{ ===========================================================================
  TDesignFileSymbol.MethodCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    Number of drawings (parts) the symbol has.
  =========================================================================== }
function TDesignFileSymbol.MethodCount: Integer;
begin
  Result := FMethods.Count;
end;

{ ===========================================================================
  TDesignFileSymbol.ClearMethods  (procedure)
  Parameters:  none
  Notes:
    Removes all part drawings and invalidates the cached views (the saved reference points are
    kept).
  =========================================================================== }
procedure TDesignFileSymbol.ClearMethods;
var
  i: Integer;
begin
  FMethods.Clear;
  { cached drawings belonged to the old methods; the reference points are kept }
  for i := 0 to FFilters.Count - 1 do
    FreeAndNil(TSymbolFilter(FFilters[i]).View);
end;

{ ===========================================================================
  TDesignFileSymbol.AddMethod  (function)
  Parameters:  none
  Returns:
    TDrawingList - the new list of drawing objects
  Notes:
    Adds an empty part drawing.
  =========================================================================== }
function TDesignFileSymbol.AddMethod: TDrawingList;
begin
  Result := TDrawingList.Create;
  FMethods.Add(Result);
end;

{ ===========================================================================
  TDesignFileSymbol.CreateNoSymbol  (procedure)
  Parameters:  none
  Notes:
    Makes the stand-in "no symbol" definition: a plain rectangle, used when a placed symbol's
    definition is missing.
  =========================================================================== }
procedure TDesignFileSymbol.CreateNoSymbol;
var
  Sq: TDrawSquare;
  L: TDrawingList;
begin
  Sq := TDrawSquare.CreateKind(FOpts, xSquareEx3);
  Sq.PointA := DPoint(0, 0);
  Sq.PointB := DPoint(-40, -40);
  L := TDrawingList.Create;
  L.Add(Sq);
  FMethods.Clear;
  FMethods.Add(L);
  Name := 'No Symbol Defined';
  Reference := 'H?'; // CTinyCadDoc::getDefaultReferenceString
  Ppp := 1;
  Heterogeneous := False;
end;

{ ---- symbol field helpers ---- }

{ ===========================================================================
  LoadFieldXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader on the FIELD element
    var F: TSymbolFieldDef - receives the field definition
  Notes:
    Reads one symbol field definition (name, default value, type) from XML.
  =========================================================================== }
procedure LoadFieldXML(R: TXMLReader; var F: TSymbolFieldDef);
var
  Tag: String;
begin
  while R.NextTag(Tag) do
  begin
    if Tag = 'NAME' then
      R.GetChildData(F.Name)
    else if Tag = 'VALUE' then
      R.GetChildData(F.Value)
    else if Tag = 'DEFAULT' then
      R.GetChildData(F.Default)
    else if Tag = 'POS' then
      R.GetChildData(F.Pos)
    else if Tag = 'FT' then
      R.GetChildDataColor(F.FieldType);
  end;
end;

{ ===========================================================================
  SaveFieldXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
    const F: TSymbolFieldDef - the field definition
    Simple: Boolean - True to write only the short form used inside placed symbols
  Notes:
    Writes one symbol field definition as a FIELD element.
  =========================================================================== }
procedure SaveFieldXML(W: TXMLWriter; const F: TSymbolFieldDef; Simple: Boolean);
begin
  W.AddTag('FIELD');
  W.AddTag('NAME', F.Name);
  W.AddTag('DEFAULT', F.Default);
  W.AddTagColor('FT', F.FieldType); // DWORD: formatted as 6 hex digits by the C++ writer
  if not Simple then
  begin
    W.AddTag('VALUE', F.Value);
    W.AddTag('POS', F.Pos);
  end;
  W.CloseTag;
end;

{ Read a nested <TinyCAD> block that holds only drawing objects (CTinyCadDoc::ReadFileXML with
  Details = FALSE, AlreadyStarted = TRUE). }

{ ===========================================================================
  LoadObjectBlock  (procedure)
  Parameters:
    R: TXMLReader - the XML reader
    Opts: TDocOptionsBase - the sheet options the objects belong to
    List: TDrawingList - receives the objects
  Notes:
    Reads a block of drawing objects (a part's drawing) and its origin from XML into a list.
  =========================================================================== }
procedure LoadObjectBlock(R: TXMLReader; Opts: TDocOptionsBase; List: TDrawingList);
var
  Tag: String;
  Origin: TDPoint;
begin
  Origin := DPointInvalid;
  R.IntoTag;
  while R.NextTag(Tag) do
    LoadObjectTag(R, Tag, Opts, List, Origin);
  R.OutOfTag;
end;

{ ===========================================================================
  SaveObjectBlock  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
    List: TDrawingList - the objects to write
  Notes:
    Writes a list of drawing objects as a TinyCAD element, without the details block.
  =========================================================================== }
procedure SaveObjectBlock(W: TXMLWriter; List: TDrawingList);
begin
  W.AddTag('TinyCAD');
  SaveObjects(W, List, False, True);
  W.CloseTag;
end;

{ ===========================================================================
  TDesignFileSymbol.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader on the symbol
  Notes:
    Reads a symbol definition (name, reference, fields, parts, and any saved reference points)
    from XML. Reference points saved by TinyCAD are remembered so views reproduce the saved
    geometry.
  =========================================================================== }
procedure TDesignFileSymbol.LoadXML(R: TXMLReader);
var
  Tag, Next: String;
  V, i: Integer;
  F: TSymbolFieldDef;
  RP: record Part: Integer; Pos: TDPoint; end;
  PowerB: Boolean;
  L: TDrawingList;
  Flt: TSymbolFilter;
begin
  while R.NextTag(Tag) do
  begin
    if Tag = 'NAME' then
    begin
      V := 0;
      R.GetAttribute('type', V);
      R.GetChildData(Name);
      NameType := V;
    end
    else if Tag = 'REF' then
    begin
      V := 0;
      R.GetAttribute('type', V);
      R.GetChildData(Reference);
      RefType := V;
    end
    else if Tag = 'DESCRIPTION' then
      R.GetChildData(Description)
    else if Tag = 'PPP' then
    begin
      V := Ppp;
      R.GetChildData(V);
      Ppp := V and $FF;
    end
    else if Tag = 'GUID' then
      R.GetChildData(Guid)
    else if Tag = 'PART' then
      LoadPartCopyXml(R, PartInfo)
    else if Tag = 'FIELD' then
    begin
      F.Name := ''; F.Value := ''; F.Default := '';
      F.Pos := DPoint(0, 0);
      F.FieldType := 0;
      R.IntoTag;
      LoadFieldXML(R, F);
      R.OutOfTag;
      SetLength(Fields, Length(Fields) + 1);
      Fields[High(Fields)] := F;
    end
    else if Tag = 'REF_POINT' then
    begin
      PowerB := False;
      RP.Part := 0;
      RP.Pos := DPointInvalid;
      R.GetAttribute('power', PowerB);
      R.GetAttribute('part', RP.Part);
      R.GetAttribute('pos', RP.Pos);
      { std::map::insert keeps the first entry for a duplicate key }
      if FindFilter(RP.Part, PowerB) = nil then
      begin
        Flt := TSymbolFilter.Create;
        Flt.Part := RP.Part;
        Flt.Power := PowerB;
        Flt.RefPoint := RP.Pos;
        FFilters.Add(Flt);
      end;
    end
    else if Tag = 'TinyCAD' then
    begin
      FMethods.Clear;
      L := TDrawingList.Create;
      FMethods.Add(L);
      LoadObjectBlock(R, FOpts, L);
      Heterogeneous := False;
    end
    else if Tag = 'TinyCADSheets' then
    begin
      R.IntoTag;
      FMethods.Clear;
      i := 0;
      while R.NextTag(Next) do
        if Next = 'TinyCAD' then
        begin
          L := TDrawingList.Create;
          FMethods.Add(L);
          LoadObjectBlock(R, FOpts, L);
          Inc(i);
        end;
      R.OutOfTag;
      Heterogeneous := True;
    end;
  end;
end;

{ ===========================================================================
  TDesignFileSymbol.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
    WithRefPoints: Boolean - True to include REF_POINT entries
  Notes:
    Writes the symbol definition, optionally with the reference points of the cached views
    (sorted as TinyCAD sorts them).
  =========================================================================== }
procedure TDesignFileSymbol.SaveXML(W: TXMLWriter; WithRefPoints: Boolean);
var
  i, j: Integer;
  Sorted: array of TSymbolFilter;
  Tmp: TSymbolFilter;

  function Less(A, B: TSymbolFilter): Boolean; // CDesignFileSymbolFilter::operator<
  begin
    if A.Part = B.Part then
      Result := Ord(A.Power) < Ord(B.Power)
    else
      Result := A.Part < B.Part;
  end;

begin
  W.AddTag('NAME');
  W.AddAttribute('type', NameType);
  W.AddChildData(Name);
  W.CloseTag;
  W.AddTag('REF');
  W.AddAttribute('type', RefType);
  W.AddChildData(Reference);
  W.CloseTag;
  W.AddTag('DESCRIPTION', Description);
  W.AddTag('PPP', Ppp);
  W.AddTag('GUID', Guid);
  if not PartInfo.IsEmpty then
    SavePartCopyXml(W, PartInfo);
  for i := 0 to High(Fields) do
    SaveFieldXML(W, Fields[i], False);
  if WithRefPoints then
  begin
    SetLength(Sorted, FFilters.Count);
    for i := 0 to FFilters.Count - 1 do Sorted[i] := TSymbolFilter(FFilters[i]);
    for i := 1 to High(Sorted) do // insertion sort by the map key
    begin
      Tmp := Sorted[i];
      j := i - 1;
      while (j >= 0) and Less(Tmp, Sorted[j]) do
      begin
        Sorted[j + 1] := Sorted[j];
        Dec(j);
      end;
      Sorted[j + 1] := Tmp;
    end;
    for i := 0 to High(Sorted) do
      if (Sorted[i].Part = 0) or Heterogeneous then
      begin
        W.AddTag('REF_POINT');
        W.AddAttribute('power', Ord(Sorted[i].Power));
        W.AddAttribute('part', Sorted[i].Part);
        W.AddAttribute('pos', Sorted[i].RefPoint);
        W.CloseTag;
      end;
  end;
  if Heterogeneous then
  begin
    W.AddTag('TinyCADSheets');
    for i := 0 to FMethods.Count - 1 do
      SaveObjectBlock(W, MethodList(i));
    W.CloseTag;
  end
  else if FMethods.Count > 0 then
    SaveObjectBlock(W, MethodList(0));
end;

{ ===========================================================================
  SymbolXMLText  (function)
  Parameters:
    S: TDesignFileSymbol - the symbol
    WithRef: Boolean - include the reference points
  Returns:
    String - the XML text
  Notes:
    The symbol's XML as text, used to decide whether two symbols are the same.
  =========================================================================== }
function SymbolXMLText(S: TDesignFileSymbol; WithRef: Boolean): String;
var
  MS: TMemoryStream;
  W: TXMLWriter;
begin
  MS := TMemoryStream.Create;
  try
    W := TXMLWriter.Create(MS);
    try
      S.SaveXML(W, WithRef);
    finally
      W.Free;
    end;
    SetLength(Result, MS.Size);
    if MS.Size > 0 then
      Move(MS.Memory^, Result[1], MS.Size);
  finally
    MS.Free;
  end;
end;

{ ===========================================================================
  TDesignFileSymbol.SameAs  (function)
  Parameters:
    Other: TDesignFileSymbol - the symbol to compare with
  Returns:
    Boolean - True if they are the same symbol
  Notes:
    Whether another symbol is the same: same name and same XML content (reference points
    ignored).
  =========================================================================== }
function TDesignFileSymbol.SameAs(Other: TDesignFileSymbol): Boolean;
begin
  if Name <> Other.Name then
    Result := False
  else
    Result := SymbolXMLText(Self, False) = SymbolXMLText(Other, False);
end;

{ ===========================================================================
  TDesignFileSymbol.GetMethodObjects  (procedure)
  Parameters:
    Part: Integer - part number
    IncludePower: Boolean - whether power pins are shown
    Dest: TList - receives the copies
  Notes:
    Copies the drawing objects for a part into a list: for heterogeneous symbols the part's own
    drawing; otherwise the shared drawing without the pins of other parts; power pins are
    converted to normal pins when shown (CreateSymbol's selection step).
  =========================================================================== }
procedure TDesignFileSymbol.GetMethodObjects(Part: Integer; IncludePower: Boolean; Dest: TList);
var
  Src: TDrawingList;
  i: Integer;
  Obj: TDrawingObject;
begin
  { CreateSymbol: pick the part's drawing for heterogeneous symbols; otherwise drop pins that
    belong to another part and drop the origin marker. IncludePower only converts power pins
    to normal ones (geometry/flags), it does not change which objects are present. }
  if FMethods.Count = 0 then
    Exit;
  if Heterogeneous then
  begin
    if (Part < 0) or (Part >= FMethods.Count) then
      Exit;
    Src := MethodList(Part);
  end
  else
    Src := MethodList(0);
  for i := 0 to Src.Count - 1 do
  begin
    Obj := Src[i];
    if (not Heterogeneous) and (Obj.GetType = xPinEx) and ((Obj as TDrawPin).Part <> Part) then
      Continue;
    if Obj.GetType = xOrigin then
      Continue;
    Dest.Add(Obj);
  end;
end;


{ ---- geometry: the symbol cache (CreateSymbol / GetMethod / GetTr / GetOrigin) ---- }

{ ===========================================================================
  TSymbolFilter.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the cached view.
  =========================================================================== }
destructor TSymbolFilter.Destroy;
begin
  View.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TDesignFileSymbol.FindFilter  (function)
  Parameters:
    Part: Integer - part number
    Power: Boolean - power pins shown
  Returns:
    TSymbolFilter - the entry, or nil if none yet
  Notes:
    Finds the cache entry for a part and power-pin setting.
  =========================================================================== }
function TDesignFileSymbol.FindFilter(Part: Integer; Power: Boolean): TSymbolFilter;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to FFilters.Count - 1 do
    if (TSymbolFilter(FFilters[i]).Part = Part) and (TSymbolFilter(FFilters[i]).Power = Power) then
    begin
      Result := TSymbolFilter(FFilters[i]);
      Exit;
    end;
end;

{ ===========================================================================
  TDesignFileSymbol.CachedRefCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    Number of cached (part, power) entries.
  =========================================================================== }
function TDesignFileSymbol.CachedRefCount: Integer;
begin
  Result := FFilters.Count;
end;

{ ===========================================================================
  TDesignFileSymbol.CachedRef  (procedure)
  Parameters:
    Index: Integer - entry number
    out Part: Integer - set to the part
    out Power: Boolean - set to the power flag
    out Ref: TDPoint - set to the reference point
  Notes:
    Reads one cache entry's part, power flag and reference point (for saving them).
  =========================================================================== }
procedure TDesignFileSymbol.CachedRef(Index: Integer; out Part: Integer; out Power: Boolean;
  out Ref: TDPoint);
begin
  Part := TSymbolFilter(FFilters[Index]).Part;
  Power := TSymbolFilter(FFilters[Index]).Power;
  Ref := TSymbolFilter(FFilters[Index]).RefPoint;
end;

{ CDesignFileSymbol::GetTr(pDesign, drawing): the size of the symbol's visible primitives,
  snapped outwards to the grid. Returned as (snapped b - snapped a), where a is the far corner and b
  the near one, so the values are negative for a symbol drawn left/up of its reference point. }

{ ===========================================================================
  TDesignFileSymbol.ComputeTr  (function)
  Parameters:
    L: TDrawingList - the drawing objects
  Returns:
    TDPoint - the size point
  Notes:
    Works out the symbol's size (the "top right" used by rotation) from its objects: the snapped
    far corner, as CreateSymbol and GetTr do.
  =========================================================================== }
function TDesignFileSymbol.ComputeTr(L: TDrawingList): TDPoint;
var
  A, B, SnapA, SnapB: TDPoint;
  First: Boolean;
  i: Integer;
  Obj: TDrawingObject;
  Grid: Double;
begin
  A := DPoint(0, 0);
  B := DPoint(0, 0);
  First := True;
  for i := 0 to L.Count - 1 do
  begin
    Obj := L[i];
    if (Obj.GetType = xPinEx) and (Obj as TDrawPin).IsInvisible then
      Continue;
    if First then
    begin
      First := False;
      A := DPoint(Max(Obj.PointA.x, Obj.PointB.x), Max(Obj.PointA.y, Obj.PointB.y));
      B := DPoint(Min(Obj.PointA.x, Obj.PointB.x), Min(Obj.PointA.y, Obj.PointB.y));
    end
    else
    begin
      A := DPoint(Max(A.x, Max(Obj.PointA.x, Obj.PointB.x)), Max(A.y, Max(Obj.PointA.y, Obj.PointB.y)));
      B := DPoint(Min(B.x, Min(Obj.PointA.x, Obj.PointB.x)), Min(B.y, Min(Obj.PointA.y, Obj.PointB.y)));
    end;
  end;
  if First then
  begin
    Result := DPoint(0, 0); // no visible primitives
    Exit;
  end;
  Grid := FOpts.Snap.Grid;
  SnapA := FOpts.Snap.Snap(A);
  SnapB := FOpts.Snap.Snap(B);
  { snapping must always round outwards }
  if SnapA.x < A.x then
    SnapA.x := SnapA.x + Grid;
  if SnapA.y < A.y then
    SnapA.y := SnapA.y + Grid;
  if SnapB.x > B.x then
    SnapB.x := SnapB.x - Grid;
  if SnapB.y > B.y then
    SnapB.y := SnapB.y - Grid;
  Result := DPoint(SnapB.x - SnapA.x, SnapB.y - SnapA.y);
end;

{ CDesignFileSymbol::CreateSymbol. HaveRef: use the given (cached) reference point instead of
  working it out. }

{ ===========================================================================
  TDesignFileSymbol.BuildView  (function)
  Parameters:
    Part: Integer - part number
    Power: Boolean - power pins shown
    HaveRef: Boolean - True when Ref is a saved reference point
    const Ref: TDPoint - the saved reference point
  Returns:
    TSymbolView - the view; the caller owns it
  Notes:
    Builds the drawing used when a symbol is placed: copies of the part's objects shifted so the
    reference point is the origin, with layout updated. Uses the saved reference point when
    there is one, otherwise computes it from the pins and extent.
  =========================================================================== }
function TDesignFileSymbol.BuildView(Part: Integer; Power, HaveRef: Boolean;
  const Ref: TDPoint): TSymbolView;
var
  Method: TDrawingList;
  i: Integer;
  Ptr: TDrawingObject;
  Pin: TDrawPin;
  A, PinPos, SnapA, Origin: TDPoint;
  First, HasPins: Boolean;
  Grid: Double;
begin
  Result := TSymbolView.Create;
  if FMethods.Count = 0 then
    Exit;
  if Heterogeneous then
  begin
    if (Part < 0) or (Part >= FMethods.Count) then
      Exit;
    Method := MethodList(Part);
  end
  else
    Method := MethodList(0);

  A := DPoint(0, 0);
  Origin := DPointInvalid;
  First := True;
  HasPins := False;
  PinPos := DPoint(0, 0);

  { make a copy of the master drawing, applying the changes required as we go }
  for i := 0 to Method.Count - 1 do
  begin
    Ptr := Method[i].Clone;
    Ptr.UpdateLayout; // the copy as the C++ Dup gives it: bounding boxes from the text metrics
    if Ptr.GetType = xPinEx then
    begin
      Pin := Ptr as TDrawPin;
      { power pins become normal pins when asked }
      if Pin.IsPower and Power then
        Pin.ConvertPowerToNormal;
      { the first visible pin keeps the pin grid }
      if (not HasPins) and (not Pin.IsInvisible) then
      begin
        PinPos := Ptr.PointA;
        HasPins := True;
      end;
    end;
    if (not Heterogeneous) and (Ptr.GetType = xPinEx) and ((Ptr as TDrawPin).Part <> Part) then
    begin
      if LegacyPartExtents then
      begin
        if First then
        begin
          First := False;
          A := DPoint(Max(Ptr.PointA.x, Ptr.PointB.x), Max(Ptr.PointA.y, Ptr.PointB.y));
        end
        else
          A := DPoint(Max(A.x, Max(Ptr.PointA.x, Ptr.PointB.x)), Max(A.y, Max(Ptr.PointA.y, Ptr.PointB.y)));
      end;
      Ptr.Free // a pin of another part
    end
    else if Ptr.GetType = xOrigin then
    begin
      Origin := Ptr.PointA; // kept as a point, not as an object
      Ptr.Free;
    end
    else
    begin
      if First then
      begin
        First := False;
        A := DPoint(Max(Ptr.PointA.x, Ptr.PointB.x), Max(Ptr.PointA.y, Ptr.PointB.y));
      end
      else
        A := DPoint(Max(A.x, Max(Ptr.PointA.x, Ptr.PointB.x)), Max(A.y, Max(Ptr.PointA.y, Ptr.PointB.y)));
      Result.Objects.Add(Ptr);
    end;
  end;

  { the reference point: the saved one, else the snapped far corner (pins stay on-grid) }
  if HaveRef then
    SnapA := Ref
  else
  begin
    Grid := FOpts.Snap.Grid;
    SnapA := FOpts.Snap.Snap(A);
    if HasPins then
      SnapA := DPoint(SnapA.x + (PinPos.x - FOpts.Snap.Snap(PinPos.x)),
                      SnapA.y + (PinPos.y - FOpts.Snap.Snap(PinPos.y)));
    { make sure snapping is always positive }
    if SnapA.x < A.x then
      SnapA.x := SnapA.x + Grid;
    if SnapA.y < A.y then
      SnapA.y := SnapA.y + Grid;
  end;

  { translate so the reference point is at 0,0 }
  for i := 0 to Result.Objects.Count - 1 do
    Result.Objects[i].Shift(DPoint(-SnapA.x, -SnapA.y));
  if DPointHasValue(Origin) then
    Origin := DPoint(Origin.x - SnapA.x, Origin.y - SnapA.y);
  Result.RefPoint := SnapA;
  Result.TopRight := ComputeTr(Result.Objects);
  Result.Origin := Origin;
end;

{ ===========================================================================
  TDesignFileSymbol.CreateView  (function)
  Parameters:
    Part: Integer - part number
    Power: Boolean - power pins shown
  Returns:
    TSymbolFilter - the cache entry
  Notes:
    Builds and caches the view for a part and power setting (reusing a saved reference point).
  =========================================================================== }
function TDesignFileSymbol.CreateView(Part: Integer; Power: Boolean): TSymbolFilter;
var
  View: TSymbolView;
begin
  Result := FindFilter(Part, Power);
  if Result <> nil then
    View := BuildView(Part, Power, True, Result.RefPoint)  // reuse the saved reference point
  else
    View := BuildView(Part, Power, False, DPointInvalid);
  if Result = nil then
  begin
    Result := TSymbolFilter.Create;
    Result.Part := Part;
    Result.Power := Power;
    FFilters.Add(Result);
  end;
  Result.View.Free;
  Result.View := View;
  Result.RefPoint := View.RefPoint;
end;

{ ===========================================================================
  TDesignFileSymbol.ComputeRefPoint  (function)
  Parameters:
    Part: Integer - part number
    IncludePower: Boolean - power pins shown
  Returns:
    TDPoint - the reference point
  Notes:
    Computes the reference point a fresh view would have, without caching it.
  =========================================================================== }
function TDesignFileSymbol.ComputeRefPoint(Part: Integer; IncludePower: Boolean): TDPoint;
var
  V: TSymbolView;
begin
  V := BuildView(Part, IncludePower, False, DPointInvalid);
  try
    Result := V.RefPoint;
  finally
    V.Free;
  end;
end;

{ ===========================================================================
  TDesignFileSymbol.GetView  (function)
  Parameters:
    Part: Integer - part number
    IncludePower: Boolean - power pins shown
  Returns:
    TSymbolView - the view
  Notes:
    The cached view for a part and power setting, building it on first use.
  =========================================================================== }
function TDesignFileSymbol.GetView(Part: Integer; IncludePower: Boolean): TSymbolView;
var
  Flt: TSymbolFilter;
begin
  Flt := FindFilter(Part, IncludePower);
  if (Flt <> nil) and (Flt.View <> nil) and (Flt.View.Objects.Count > 0) then
    Result := Flt.View
  else
    Result := CreateView(Part, IncludePower).View;
end;

{ ===========================================================================
  TDesignFileSymbol.GetTr  (function)
  Parameters:
    Part: Integer - part number
    IncludePower: Boolean - power pins shown
  Returns:
    TDPoint - the size point
  Notes:
    The symbol's size for placing it. Only heterogeneous symbols use the part number; all parts
    of a normal symbol use part 0's size, as in TinyCAD.
  =========================================================================== }
function TDesignFileSymbol.GetTr(Part: Integer; IncludePower: Boolean): TDPoint;
var
  Flt: TSymbolFilter;
begin
  { only heterogeneous symbols use the part number }
  if not Heterogeneous then
    Part := 0;
  Flt := FindFilter(Part, IncludePower);
  if (Flt <> nil) and (Flt.View <> nil) and (Flt.View.Objects.Count > 0) then
    Result := Flt.View.TopRight
  else if (FMethods.Count > 0) and (MethodList(0).Count > 0) then
    Result := CreateView(Part, IncludePower).View.TopRight
  else
    Result := DPoint(0, 0);
end;

{ ===========================================================================
  TDesignFileSymbol.GetOrigin  (function)
  Parameters:
    Part: Integer - part number
    IncludePower: Boolean - power pins shown
  Returns:
    TDPoint - the origin point
  Notes:
    The origin of the symbol's view (part 0 unless heterogeneous).
  =========================================================================== }
function TDesignFileSymbol.GetOrigin(Part: Integer; IncludePower: Boolean): TDPoint;
var
  Flt: TSymbolFilter;
begin
  if not Heterogeneous then
    Part := 0;
  Flt := FindFilter(Part, IncludePower);
  if (Flt <> nil) and (Flt.View <> nil) and (Flt.View.Objects.Count > 0) then
    Result := Flt.View.Origin
  else if (FMethods.Count > 0) and (MethodList(0).Count > 0) then
    Result := CreateView(Part, IncludePower).View.Origin
  else
    Result := DPointInvalid;
end;

{ ===========================================================================
  TDesignFileSymbol.PartsPerPackage  (function)
  Parameters:  none
  Returns:
    Integer - the number of parts
  Notes:
    How many parts the symbol has (gates in an IC).
  =========================================================================== }
function TDesignFileSymbol.PartsPerPackage: Integer; begin Result := Ppp; end;

{ ===========================================================================
  TDesignFileSymbol.SymbolName  (function)
  Parameters:  none
  Returns:
    String - the name
  Notes:
    The symbol's name.
  =========================================================================== }
function TDesignFileSymbol.SymbolName: String; begin Result := Name; end;

{ ===========================================================================
  TDesignFileSymbol.SymbolReference  (function)
  Parameters:  none
  Returns:
    String - the reference prefix
  Notes:
    The symbol's reference prefix, e.g. R or U.
  =========================================================================== }
function TDesignFileSymbol.SymbolReference: String; begin Result := Reference; end;

{ ===========================================================================
  TDesignFileSymbol.IsHeterogeneous  (function)
  Parameters:  none
  Returns:
    Boolean - True if every part has its own outline
  Notes:
    CDesignFileSymbol::IsHeterogeneous: heterogeneous symbols have different outlines per part.
  =========================================================================== }
function TDesignFileSymbol.IsHeterogeneous: Boolean; begin Result := Heterogeneous; end;

{ ===========================================================================
  TDesignFileSymbol.SymbolNameType  (function)
  Parameters:  none
  Returns:
    Integer - the name field type code
  Notes:
    How the name field is shown.
  =========================================================================== }
function TDesignFileSymbol.SymbolNameType: Integer; begin Result := NameType; end;

{ ===========================================================================
  TDesignFileSymbol.SymbolRefType  (function)
  Parameters:  none
  Returns:
    Integer - the reference field type code
  Notes:
    How the reference field is shown.
  =========================================================================== }
function TDesignFileSymbol.SymbolRefType: Integer; begin Result := RefType; end;

{ ===========================================================================
  TDesignFileSymbol.FieldCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    Number of extra fields the symbol defines.
  =========================================================================== }
function TDesignFileSymbol.FieldCount: Integer; begin Result := Length(Fields); end;

{ ===========================================================================
  TDesignFileSymbol.FieldName  (function)
  Parameters:
    Index: Integer - field number
  Returns:
    String - the name
  Notes:
    Name of an extra field.
  =========================================================================== }
function TDesignFileSymbol.FieldName(Index: Integer): String; begin Result := Fields[Index].Name; end;

{ ===========================================================================
  TDesignFileSymbol.FieldDefault  (function)
  Parameters:
    Index: Integer - field number
  Returns:
    String - the default text
  Notes:
    Default value of an extra field.
  =========================================================================== }
function TDesignFileSymbol.FieldDefault(Index: Integer): String; begin Result := Fields[Index].Default; end;

{ ===========================================================================
  TDesignFileSymbol.FieldType  (function)
  Parameters:
    Index: Integer - field number
  Returns:
    Integer - the type code
  Notes:
    Display type of an extra field (shown, hidden, always hidden).
  =========================================================================== }
function TDesignFileSymbol.FieldType(Index: Integer): Integer; begin Result := Integer(Fields[Index].FieldType); end;

{ ---- TSymbolResource ---- }

{ ===========================================================================
  TSymbolResource.CreateFor  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options
    ASymbol: TDesignFileSymbol - the symbol; the entry owns it
  Notes:
    Wraps a symbol definition as an entry of the sheet's symbol table.
  =========================================================================== }
constructor TSymbolResource.CreateFor(AOpts: TDocOptionsBase; ASymbol: TDesignFileSymbol);
begin
  inherited Create;
  FOpts := AOpts;
  Symbol := ASymbol;
end;

{ ===========================================================================
  TSymbolResource.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the symbol it owns.
  =========================================================================== }
destructor TSymbolResource.Destroy;
begin
  Symbol.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TSymbolResource.Compare  (function)
  Parameters:
    Other: TResourceItem - the entry to compare with
  Returns:
    Boolean - True if equal
  Notes:
    Whether another table entry is the same symbol (unnamed symbols never match, as in TinyCAD).
  =========================================================================== }
function TSymbolResource.Compare(Other: TResourceItem): Boolean;
var
  O: TSymbolResource;
begin
  O := Other as TSymbolResource;
  { correct for a bug in previous versions: unnamed symbols never match }
  if (Symbol.Name = '') or (O.Symbol.Name = '') then
    Result := False
  else
    Result := Symbol.SameAs(O.Symbol);
end;

{ ===========================================================================
  TSymbolResource.WriteItem  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer
  Notes:
    Writes the symbol with its reference points.
  =========================================================================== }
procedure TSymbolResource.WriteItem(W: TXMLWriter);
begin
  Symbol.SaveXML(W, True);
end;

{ ===========================================================================
  TSymbolResource.ReadItem  (procedure)
  Parameters:
    R: TXMLReader - the XML reader on the entry
  Notes:
    Reads a symbol definition.
  =========================================================================== }
procedure TSymbolResource.ReadItem(R: TXMLReader);
begin
  Symbol := TDesignFileSymbol.Create(FOpts);
  R.IntoTag;
  Symbol.LoadXML(R);
  R.OutOfTag;
end;

{ ---- TSymbolList ---- }

{ ===========================================================================
  TSymbolList.CreateFor  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options
  Notes:
    Creates the symbol table of a sheet; entry 0 is the "no symbol" stand-in.
  =========================================================================== }
constructor TSymbolList.CreateFor(AOpts: TDocOptionsBase);
var
  NoSym: TDesignFileSymbol;
begin
  NoSym := TDesignFileSymbol.Create(AOpts);
  NoSym.CreateNoSymbol;
  inherited Create(TSymbolResource.CreateFor(AOpts, NoSym));
  FOpts := AOpts;
end;

{ ===========================================================================
  TSymbolList.CreateItem  (function)
  Parameters:  none
  Returns:
    TResourceItem - a new symbol resource
  Notes:
    Makes an empty symbol entry for the loader.
  =========================================================================== }
function TSymbolList.CreateItem: TResourceItem;
begin
  Result := TSymbolResource.CreateFor(FOpts, nil);
end;

{ ===========================================================================
  TSymbolList.Symbol  (function)
  Parameters:
    Id: Integer - symbol number
  Returns:
    TDesignFileSymbol - the symbol
  Notes:
    The symbol with a given number (the stand-in if there is none).
  =========================================================================== }
function TSymbolList.Symbol(Id: Integer): TDesignFileSymbol;
begin
  Result := (Get(Id) as TSymbolResource).Symbol;
end;

end.
