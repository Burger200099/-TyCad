// SPDX-License-Identifier: LGPL-2.1-or-later
{ Port of the netlist core of NetList.cpp / Net.h (CNetList, CNetListNode) and the Protel writer.

  How a netlist is built (all of it a post-processing step; nets are not stored in the file):
    1. per sheet (MakeNetForSheet): every connection point becomes a node (pin ends, power
       symbols, wire ends, junctions, no-connects, labels); nodes at the same point share a net,
       and a wire joins the nets at its two ends. Junctions join the wires they sit on; labels
       join the wire they sit on, and equal labels join together.
    2. Link: the nets of all sheets are merged by label name, and every net gets a preferred
       name (power names beat labels, otherwise _N_<number>).
    3. ApplyHints: nets are renumbered using the per-pin hints stored in the placed symbols so
       that numbers stay stable, and the numbers are written back into the symbols.
    4. WriteWires: each wire is told which net it is on.

  Hierarchical designs: a placed hierarchical symbol loads its design as a new "import" with the
  next context instance number (the root is 0, a design placed twice is two instances). Its pins
  become nodes of that instance labelled with the pin name, and every label inside gets the
  instance number in its name (_HN_<n>_<name>), so the two meet by name. References inside carry
  the path of symbols leading to them (H1_U2). FollowImports = False (as ERC uses) keeps to the
  root design.

  Original: Copyright 1994-2019 Matt Pyne, LGPL 2.1+. This port keeps that licence. }
unit UNetList;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, UDPoint, UDrawTypes, UGeometry, UDrawingObjects, UDesign;

type
  { CNetListNode }
  TNetListNode = record
    FileNameIndex: Integer;   // the context instance: 0 for the root design, one number for each placed copy of a hierarchical design
    LabelText: String;        // net name this node contributes (not unique within a net)
    PreferredLabel: String;
    NetList: Integer;         // the net this node is a member of (-1: none yet)
    Reference: String;
    Pin: String;
    A: TDPoint;               // where the node is on the sheet (invalid for hidden power pins)
    Sheet: Integer;           // 1-based
    Parent: TDrawingObject;   // the object that produced the node
    Method: TDrawMethod;      // the placed symbol a pin belongs to
  end;

  TNodeVector = array of TNetListNode;

  { CImportFile: one design taking part in a netlist - the root, or the design behind one placed hierarchical symbol.
    Every placed instance gets its own (a design placed twice is two imports), numbered in the order found. }
  TImportFile = class
  public
    Design: TDesignFile;
    OwnsDesign: Boolean;
    FileIndex: Integer;       // the context instance number: 0 is the root
    ParentIndex: Integer;     // position of the parent in the import list; -1 for the root
    RefContext: String;       // path to this instance, '/H1/H3/H2'; '' for the root
    destructor Destroy; override;
  end;

function NewNode(AFileIndex, ASheet: Integer; AParent: TDrawingObject; const AA: TDPoint): TNetListNode;
{ getLabel: the label, made unique per hierarchical instance when file index <> 0 }
function NodeLabel(const N: TNetListNode): String;
function NodePreferredLabel(const N: TNetListNode): String;
{ the number of characters of a UTF-8 text (TinyCAD counts characters, not bytes, when it wraps a line) }
function CharLength(const S: String): Integer;

type
  { std::map<int, nodeVector>: nets in ascending number order }
  TNetCollection = class
  private
    FKeys: array of Integer;
    FVecs: array of TNodeVector;
    function IndexOf(ANet: Integer): Integer; // -1 when absent
  public
    function Count: Integer;
    function Key(Index: Integer): Integer;
    function Vec(Index: Integer): TNodeVector;
    procedure SetNode(Index, NodeIndex: Integer; const Node: TNetListNode);
    procedure Push(ANet: Integer; const Node: TNetListNode);   // m_nets[key].push_back(node)
    function Has(ANet: Integer): Boolean;
    procedure Erase(ANet: Integer);
    procedure Clear;
  end;

  { std::map<CDPoint,int> with CDPoint's tolerance-based ordering (points within 0.001 are equal) }
  TPointNetMap = class
  private
    FPts: array of TDPoint;
    FNet: array of Integer;
    function LowerBound(const P: TDPoint): Integer;
  public
    function Get(const P: TDPoint): Integer;        // operator[]: absent points are added as 0
    procedure SetValue(const P: TDPoint; Net: Integer);
    procedure Clear;
  end;

  TNetList = class
  private
    FCurrentNet: Integer;
    FImports: TList;   // the designs read for the hierarchical symbols; the nodes point into them, so they live as long as the netlist
    procedure ClearImports;
    function GetNewNet: Integer;
    function Add(var Ins: TNetListNode): Integer;
    procedure MakeNetForSheet(Imports: TList; ImportIndex, SheetZero: Integer; var FileCounter: Integer;
      FollowImports: Boolean);
    procedure Link(Lists: array of TNetList; Imports: TList);
    procedure ApplyHints;
    procedure WriteWires;
  public
    Nets: TNetCollection;
    Nodes: TPointNetMap;
    { False: hierarchical symbols are not followed (only the root design is netlisted); ERC does this }
    FollowImports: Boolean;
    { why a hierarchical design could not be followed (a file that cannot be read, too many levels), one per line }
    ImportErrors: String;
    constructor Create;
    destructor Destroy; override;
    { Build the netlist of a whole design (CNetList::MakeNet) }
    procedure MakeNet(Design: TDesignFile);
    { The net name TinyCAD shows for a net: label / power name / _N_<n> }
    class function GetPowerLabel(Power: TDrawPower): String;
    { The reference of a placed symbol with the path of the hierarchical symbols it is inside: 'H22_H1_U1'
      (CNetList::get_reference_path, forward, '_' separator); just the reference in the root design }
    class function GetReferencePath(Meth: TDrawMethod; Ctx: TImportFile): String;
    { The path alone, each part followed by '_': 'H22_H1_' (get_partial_reference_path); '' in the root design }
    class function GetPartialReferencePath(Ctx: TImportFile): String;
    { Protel netlist file (CNetList::WriteNetListFileProtel); calls MakeNet first }
    procedure WriteProtel(Design: TDesignFile; Dest: TStream);
    { Plain text dump: one block per net, for testing }
    function DumpText: String;
  end;

implementation


uses UStrings;

{ ---- nodes ---- }

{ ===========================================================================
  NewNode  (function)
  Parameters:
    AFileIndex: Integer - 0 for the root design (hierarchy is not supported)
    ASheet: Integer - 1-based sheet number
    AParent: TDrawingObject - the object that produced it
    const AA: TDPoint - where it is on the sheet; an invalid point for hidden power pins
  Returns:
    TNetListNode - the node
  Notes:
    Creates a netlist node with no label, reference or pin and no net yet.
  =========================================================================== }
function NewNode(AFileIndex, ASheet: Integer; AParent: TDrawingObject; const AA: TDPoint): TNetListNode;
begin
  Result.FileNameIndex := AFileIndex;
  Result.LabelText := '';
  Result.PreferredLabel := '';
  Result.NetList := -1;
  Result.Reference := '';
  Result.Pin := '';
  Result.A := AA;
  Result.Sheet := ASheet;
  Result.Parent := AParent;
  Result.Method := nil;
end;

{ ===========================================================================
  NodeLabel  (function)
  Parameters:
    const N: TNetListNode - the node
  Returns:
    String - the name, or empty when the node has no label
  Notes:
    The net name a node contributes: its label, made unique per hierarchical instance when the
    file index is not 0.
  =========================================================================== }
function NodeLabel(const N: TNetListNode): String;
begin
  if N.LabelText = '' then
    Result := ''
  else if N.FileNameIndex <> 0 then
    Result := Format('_HN_%d_%s', [N.FileNameIndex, N.LabelText])
  else
    Result := N.LabelText;
end;

{ ===========================================================================
  NodePreferredLabel  (function)
  Parameters:
    const N: TNetListNode - the node
  Returns:
    String - the preferred name
  Notes:
    The net's preferred name once linking has chosen one; falls back to the node's own label.
  =========================================================================== }
function NodePreferredLabel(const N: TNetListNode): String;
begin
  if N.PreferredLabel = '' then
    Result := NodeLabel(N) // (C++ returns m_label here, not the decorated one; same for file index 0)
  else
    Result := N.PreferredLabel;
end;

{ ===========================================================================
  CharLength  (function)
  Parameters:
    const S: String - text
  Returns:
    Integer
  Notes:
    Counts the bytes that start a character (those that are not continuation bytes), as
    CString::GetLength counts characters in TinyCAD; used where a line is wrapped at a number of
    characters.
  =========================================================================== }
function CharLength(const S: String): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to System.Length(S) do
    if (Ord(S[i]) and $C0) <> $80 then
      Inc(Result);
end;

{ ---- TNetCollection ---- }

{ ===========================================================================
  TNetCollection.IndexOf  (function)
  Parameters:
    ANet: Integer - the net number
  Returns:
    Integer - position, or -1 if the net is absent
  Notes:
    Binary search for a net number among the sorted keys.
  =========================================================================== }
function TNetCollection.IndexOf(ANet: Integer): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Lo := 0;
  Hi := Length(FKeys) - 1;
  Result := -1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if FKeys[Mid] = ANet then begin
      Result := Mid;
      Exit;
    end
    else if FKeys[Mid] < ANet then
      Lo := Mid + 1
    else
      Hi := Mid - 1;
  end;
end;

{ ===========================================================================
  TNetCollection.Count  (function)
  Parameters:  none
  Returns:
    Integer - the number of nets
  Notes:
    How many nets there are.
  =========================================================================== }
function TNetCollection.Count: Integer;
begin
  Result := Length(FKeys);
end;

{ ===========================================================================
  TNetCollection.Key  (function)
  Parameters:
    Index: Integer - position
  Returns:
    Integer - the net number
  Notes:
    The net number at a position (nets are kept in ascending order).
  =========================================================================== }
function TNetCollection.Key(Index: Integer): Integer;
begin
  Result := FKeys[Index];
end;

{ ===========================================================================
  TNetCollection.Vec  (function)
  Parameters:
    Index: Integer - position
  Returns:
    TNodeVector - the nodes in the order they were added
  Notes:
    The nodes of the net at a position.
  =========================================================================== }
function TNetCollection.Vec(Index: Integer): TNodeVector;
begin
  Result := FVecs[Index];
end;

{ ===========================================================================
  TNetCollection.SetNode  (procedure)
  Parameters:
    Index: Integer - position of the net
    NodeIndex: Integer - position of the node inside it
    const Node: TNetListNode - the new node value
  Notes:
    Replaces one node of a net in place (used when linking changes a node's net, label or
    number).
  =========================================================================== }
procedure TNetCollection.SetNode(Index, NodeIndex: Integer; const Node: TNetListNode);
begin
  FVecs[Index][NodeIndex] := Node;
end;

{ ===========================================================================
  TNetCollection.Has  (function)
  Parameters:
    ANet: Integer - the net number
  Returns:
    Boolean - True if present
  Notes:
    Whether a net number exists.
  =========================================================================== }
function TNetCollection.Has(ANet: Integer): Boolean;
begin
  Result := IndexOf(ANet) >= 0;
end;

{ ===========================================================================
  TNetCollection.Push  (procedure)
  Parameters:
    ANet: Integer - the net number
    const Node: TNetListNode - the node to add
  Notes:
    Appends a node to a net, creating the net (in sorted position) if it does not exist yet; the
    same as m_nets[net].push_back(node) in TinyCAD.
  =========================================================================== }
procedure TNetCollection.Push(ANet: Integer; const Node: TNetListNode);
var
  i, Pos: Integer;
begin
  i := IndexOf(ANet);
  if i < 0 then
  begin
    Pos := 0;
    while (Pos < Length(FKeys)) and (FKeys[Pos] < ANet) do Inc(Pos);
    SetLength(FKeys, Length(FKeys) + 1);
    SetLength(FVecs, Length(FVecs) + 1);
    for i := High(FKeys) downto Pos + 1 do
    begin
      FKeys[i] := FKeys[i - 1];
      FVecs[i] := FVecs[i - 1];
    end;
    FKeys[Pos] := ANet;
    FVecs[Pos] := nil;
    i := Pos;
  end;
  SetLength(FVecs[i], Length(FVecs[i]) + 1);
  FVecs[i][High(FVecs[i])] := Node;
end;

{ ===========================================================================
  TNetCollection.Erase  (procedure)
  Parameters:
    ANet: Integer - the net number
  Notes:
    Removes a net and all its nodes (after merging it into another net).
  =========================================================================== }
procedure TNetCollection.Erase(ANet: Integer);
var
  i, k: Integer;
begin
  i := IndexOf(ANet);
  if i < 0 then
    Exit;
  for k := i to High(FKeys) - 1 do
  begin
    FKeys[k] := FKeys[k + 1];
    FVecs[k] := FVecs[k + 1];
  end;
  SetLength(FKeys, Length(FKeys) - 1);
  SetLength(FVecs, Length(FVecs) - 1);
end;

{ ===========================================================================
  TNetCollection.Clear  (procedure)
  Parameters:  none
  Notes:
    Removes every net.
  =========================================================================== }
procedure TNetCollection.Clear;
begin
  SetLength(FKeys, 0);
  SetLength(FVecs, 0);
end;

{ ---- TPointNetMap ---- }

{ ===========================================================================
  PointLessThan  (function)
  Parameters:
    const A: TDPoint - first point
    const B: TDPoint - second point
  Returns:
    Boolean - True if A sorts before B
  Notes:
    TinyCAD's tolerant point ordering (CDPoint::operator<): points within 0.001 compare equal,
    otherwise ordered by x then y. Used to keep the point-to-net map ordered.
  =========================================================================== }
function PointLessThan(const A, B: TDPoint): Boolean; // CDPoint::operator<
const
  Close = 0.001;
begin
  if Abs(B.x - A.x) < Close then
    Result := A.y < B.y - Close
  else
    Result := A.x < B.x - Close;
end;

{ ===========================================================================
  TPointNetMap.LowerBound  (function)
  Parameters:
    const P: TDPoint - the point
  Returns:
    Integer - the position where P is or would be inserted
  Notes:
    Binary search for the first entry that is not before P.
  =========================================================================== }
function TPointNetMap.LowerBound(const P: TDPoint): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Lo := 0;
  Hi := Length(FPts);
  while Lo < Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if PointLessThan(FPts[Mid], P) then
      Lo := Mid + 1
    else
      Hi := Mid;
  end;
  Result := Lo;
end;

{ ===========================================================================
  TPointNetMap.Get  (function)
  Parameters:
    const P: TDPoint - the point
  Returns:
    Integer - the net number (0 if none)
  Notes:
    Net number stored at a point; like std::map operator[], an absent point is added with net 0.
  =========================================================================== }
function TPointNetMap.Get(const P: TDPoint): Integer;
var
  i, k: Integer;
begin
  i := LowerBound(P);
  if (i < Length(FPts)) and (not PointLessThan(P, FPts[i])) then
  begin
    Result := FNet[i];
    Exit;
  end;
  { absent: insert with the default value 0 }
  SetLength(FPts, Length(FPts) + 1);
  SetLength(FNet, Length(FNet) + 1);
  for k := High(FPts) downto i + 1 do
  begin
    FPts[k] := FPts[k - 1];
    FNet[k] := FNet[k - 1];
  end;
  FPts[i] := P;
  FNet[i] := 0;
  Result := 0;
end;

{ ===========================================================================
  TPointNetMap.SetValue  (procedure)
  Parameters:
    const P: TDPoint - the point
    Net: Integer - the net number
  Notes:
    Stores a net number at a point, adding the point if needed.
  =========================================================================== }
procedure TPointNetMap.SetValue(const P: TDPoint; Net: Integer);
var
  i: Integer;
begin
  Get(P); // make sure the entry exists
  i := LowerBound(P);
  FNet[i] := Net;
end;

{ ===========================================================================
  TPointNetMap.Clear  (procedure)
  Parameters:  none
  Notes:
    Removes every point.
  =========================================================================== }
procedure TPointNetMap.Clear;
begin
  SetLength(FPts, 0);
  SetLength(FNet, 0);
end;

{ ---- imports ---- }

{ ===========================================================================
  TImportFile.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the design when this import loaded it (the root design belongs to the caller).
  =========================================================================== }
destructor TImportFile.Destroy;
begin
  if OwnsDesign then
    Design.Free;
  inherited Destroy;
end;

{ ===========================================================================
  FindImport  (function)
  Parameters:
    Imports: TList
    AFileIndex: Integer - whole number
  Returns:
    TImportFile
  Notes:
    The C++ uses the number as a position in the list, which is only the same while every
    hierarchical design loads; here the number is looked for, so a design that failed to load
    cannot shift the others.
  =========================================================================== }
function FindImport(Imports: TList; AFileIndex: Integer): TImportFile;
var
  i: Integer;
begin
  Result := nil;
  if Imports = nil then
    Exit;
  for i := 0 to Imports.Count - 1 do
    if TImportFile(Imports[i]).FileIndex = AFileIndex then
    begin
      Result := TImportFile(Imports[i]);
      Exit;
    end;
end;

{ ---- TNetList ---- }

{ ===========================================================================
  TNetList.Create  (constructor)
  Parameters:  none
  Notes:
    Creates an empty netlist; net numbers start at 1.
  =========================================================================== }
constructor TNetList.Create;
begin
  inherited Create;
  Nets := TNetCollection.Create;
  Nodes := TPointNetMap.Create;
  FCurrentNet := 1;
  FollowImports := True;
  ImportErrors := '';
  FImports := nil;
end;

{ ===========================================================================
  TNetList.ClearImports  (procedure)
  Parameters:  none
  Notes:
    Frees the designs read for hierarchical symbols (CNetList::clear). The nodes of the nets
    point into them, so this is done when the netlist is made again or freed, not when it is
    finished.
  =========================================================================== }
procedure TNetList.ClearImports;
var
  i: Integer;
begin
  if FImports = nil then
    Exit;
  for i := 0 to FImports.Count - 1 do TImportFile(FImports[i]).Free;
  FreeAndNil(FImports);
end;

{ ===========================================================================
  TNetList.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the point map and the net collection.
  =========================================================================== }
destructor TNetList.Destroy;
begin
  Nodes.Free;
  Nets.Free;
  ClearImports;
  inherited Destroy;
end;

{ ===========================================================================
  TNetList.GetNewNet  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    Assigns net numbers (which may later get an alpha prefix to form a name).
  =========================================================================== }
function TNetList.GetNewNet: Integer;
begin
  Result := FCurrentNet;
  Inc(FCurrentNet);
end;

{ ===========================================================================
  TNetList.Add  (function)
  Parameters:
    var Ins: TNetListNode - in/out: changed by the call
  Returns:
    Integer
  Notes:
    Add a node (if necessary) and return the net it ended up in.
  =========================================================================== }
function TNetList.Add(var Ins: TNetListNode): Integer;
var
  Found, NewList, OldList, i, k, Idx: Integer;
  OldVec: TNodeVector;
begin
  if not DPointHasValue(Ins.A) then
  begin
    { a node without a connection point always gets a net of its own }
    Ins.NetList := GetNewNet;
    Nets.Push(Ins.NetList, Ins);
    Result := Ins.NetList;
  end
  else if Ins.NetList = -1 then
  begin
    Found := Nodes.Get(Ins.A);
    if Found <> 0 then
      Ins.NetList := Found
    else
    begin
      Ins.NetList := GetNewNet;
      Nodes.SetValue(Ins.A, Ins.NetList);
    end;
    Nets.Push(Ins.NetList, Ins);
    Result := Ins.NetList;
  end
  else
  begin
    Found := Nodes.Get(Ins.A);
    { already known under a different net: the two nets must be joined }
    if (Found <> 0) and (Found <> Ins.NetList) then
    begin
      NewList := Ins.NetList;
      OldList := Found;
      for Idx := 0 to Nets.Count - 1 do
        if Nets.Key(Idx) = OldList then
        begin
          OldVec := Nets.Vec(Idx);
          for i := 0 to High(OldVec) do
          begin
            OldVec[i].NetList := NewList;
            if DPointHasValue(OldVec[i].A) then
              Nodes.SetValue(OldVec[i].A, NewList);
          end;
          for k := 0 to High(OldVec) do
            Nets.Push(NewList, OldVec[k]);
          Break;
        end;
      Nets.Erase(OldList);
      Ins.NetList := NewList;
    end;
    Nets.Push(Ins.NetList, Ins);
    Nodes.SetValue(Ins.A, Ins.NetList);
    Result := Ins.NetList;
  end;
end;

{ ===========================================================================
  TNetList.GetPowerLabel  (function)
  Parameters:
    Power: TDrawPower - the power symbol
  Returns:
    String - the name
  Notes:
    The net name a power symbol gives: its text if it has one, otherwise a fixed name for its
    shape (TCPOWERBAR, TCPOWERCIRCLE ...).
  =========================================================================== }
class function TNetList.GetPowerLabel(Power: TDrawPower): String;
begin
  { use the power value as the net name where there is one }
  if Power.GetValue <> '' then
  begin
    Result := Power.GetValue;
    Exit;
  end;
  { otherwise a fixed name per power symbol shape }
  case Power.Which of
    0: Result := 'TCPOWERBAR';
    1: Result := 'TCPOWERCIRCLE';
    2: Result := 'TCPOWERWAVE';
    3: Result := 'TCPOWERARROW';
    4: Result := 'TCPOWEREARTH';
  else
    Result := 'TCPOWER';
  end;
end;

{ ===========================================================================
  TNetList.GetPartialReferencePath  (function)
  Parameters:
    Ctx: TImportFile
  Returns:
    String
  Notes:
    CNetList::get_partial_reference_path (forward, '_' separator). Empty parts of the context
    ('/H1//H2') are skipped, as the C++ tokenizer does.
  =========================================================================== }
class function TNetList.GetPartialReferencePath(Ctx: TImportFile): String;
var
  i, Start: Integer;
  Ref, Tok: String;
begin
  Result := '';
  if (Ctx = nil) or (Ctx.RefContext = '') then
    Exit;
  Ref := Ctx.RefContext;
  Start := 1;
  for i := 1 to Length(Ref) + 1 do
    if (i > Length(Ref)) or (Ref[i] = '/') then
    begin
      Tok := Copy(Ref, Start, i - Start);
      if Tok <> '' then
        Result := Result + Tok + '_';
      Start := i + 1;
    end;
end;

{ ===========================================================================
  TNetList.GetReferencePath  (function)
  Parameters:
    Meth: TDrawMethod
    Ctx: TImportFile
  Returns:
    String
  Notes:
    CNetList::get_reference_path (forward). In the root design it is the symbol's own reference.
    For a hierarchical symbol the result repeats its own reference after the path, as TinyCAD
    does.
  =========================================================================== }
class function TNetList.GetReferencePath(Meth: TDrawMethod; Ctx: TImportFile): String;
begin
  if (Ctx <> nil) and (Ctx.RefContext <> '') then
    Result := GetPartialReferencePath(Ctx) + Meth.GetRef
  else
    Result := Meth.GetRef;
end;

{ ===========================================================================
  TNetList.MakeNetForSheet  (procedure)
  Parameters:
    Imports: TList
    ImportIndex: Integer - whole number
    SheetZero: Integer - whole number
    var FileCounter: Integer - whole number (in/out: changed by the call)
    FollowImports: Boolean - flag
  Notes:
    Builds the nets of one sheet: a node for every pin end, power symbol, wire end, junction,
    no-connect and label; wires join their two ends, junctions join the wires they sit on,
    labels join the wire they are on and each other; hidden power pins and power symbols join by
    name. A port of CNetList::MakeNetForSheet for flat designs.
  =========================================================================== }
procedure TNetList.MakeNetForSheet(Imports: TList; ImportIndex, SheetZero: Integer; var FileCounter: Integer;
  FollowImports: Boolean);
var
  FileIndex, SheetOneIndexed: Integer;
  Sheet: TDesignSheet;
  Ctx, NewImp: TImportFile;
  Hs: TDrawHierarchicalSymbol;
  Child: TDesignFile;
  Powers, Connected, Labels: TStringList;
  i, j, Hold, FoundIdx, NetNumber: Integer;
  Obj, Search, Pointer_: TDrawingObject;
  Meth: TDrawMethod;
  Pin: TDrawPin;
  Pw: TDrawPower;
  Lbl: TDrawLabel;
  Tr: TDPoint;
  View: TDrawingList;
  N: TNetListNode;
  MyRef, PowerLabelStr: String;
  A: TDPoint;
  DistAlong: Double;
  Drawing: TDrawingList;

  function FindName(L: TStringList; const Name: String): Integer;
  begin
    Result := L.IndexOf(Name);
  end;

begin
  Ctx := TImportFile(Imports[ImportIndex]);
  FileIndex := Ctx.FileIndex;
  SheetOneIndexed := SheetZero + 1;
  Sheet := Ctx.Design.Sheets[SheetZero];
  FCurrentNet := 1;
  Nodes.Clear;
  Nets.Clear;
  Powers := TStringList.Create;
  Connected := TStringList.Create;
  Labels := TStringList.Create;
  try
    Powers.CaseSensitive := True;
    Connected.CaseSensitive := True;
    Labels.CaseSensitive := True;
    Drawing := Sheet.Drawing;

    { ---- search for nodes and build the node tree ---- }
    for i := 0 to Drawing.Count - 1 do
    begin
      Obj := Drawing[i];
      case Obj.GetType of
        xHierarchicalSymbol:
          begin
            Hs := Obj as TDrawHierarchicalSymbol;
            if not FollowImports then
              Continue;
            if Imports.Count > 100 then
            begin
              ImportErrors := Format(rsTooManyLevelsOfHierarchy, [ImportErrors]);
              Continue;
            end;
            Child := TDesignFile.Create;
            try
              Child.LoadFromFile(Hs.FileName);
            except
              on E: Exception do
              begin
                FreeAndNil(Child);
                ImportErrors := ImportErrors + Hs.FileName + ': ' + E.Message + LineEnding;
              end;
            end;
            if Child <> nil then
            begin
              NewImp := TImportFile.Create;
              NewImp.Design := Child;
              NewImp.OwnsDesign := True;
              NewImp.FileIndex := FileCounter;
              Inc(FileCounter);
              NewImp.ParentIndex := ImportIndex;
              if Ctx.RefContext = '' then
                NewImp.RefContext := Hs.GetRef
              else
                NewImp.RefContext := Ctx.RefContext + '/' + Hs.GetRef;
              Imports.Add(NewImp);
              { the symbol's pins stand for the design: each is labelled with its name in the new instance }
              Hs.ExtractSymbol(Tr, View);
              for j := 0 to View.Count - 1 do
              begin
                Pointer_ := View[j];
                if Pointer_.GetType = xPinEx then
                begin
                  Pin := Pointer_ as TDrawPin;
                  N := NewNode(NewImp.FileIndex, SheetOneIndexed, Pin, Pin.GetActivePoint(Hs));
                  N.LabelText := Pin.GetPinName;
                  N.Reference := GetReferencePath(Hs, Ctx);
                  N.Pin := Pin.GetNumber;
                  N.Method := Hs;
                  Add(N);
                end;
              end;
            end;
          end;
        xMethodEx3:
          begin
            Meth := Obj as TDrawMethod;
            Meth.ExtractSymbol(Tr, View);
            MyRef := GetReferencePath(Meth, Ctx);
            for j := 0 to View.Count - 1 do
            begin
              Pointer_ := View[j];
              if (Pointer_.GetType = xPinEx) and (not (Pointer_ as TDrawPin).IsPower) then
              begin
                { only pins that are NOT power pins here: power pins are handled below }
                Pin := Pointer_ as TDrawPin;
                N := NewNode(FileIndex, SheetOneIndexed, Pin, Pin.GetActivePoint(Meth));
                N.Reference := MyRef;
                N.Pin := Pin.GetNumber;
                N.Method := Meth;
                Add(N);
              end;
            end;
            { has this symbol had its power connected? }
            if Connected.IndexOf(MyRef) < 0 then
            begin
              Connected.Add(MyRef);
              Meth.ExtractSymbol(Tr, View);
              for j := 0 to View.Count - 1 do
              begin
                Pointer_ := View[j];
                if (Pointer_.GetType = xPinEx) and (Pointer_ as TDrawPin).IsPower then
                begin
                  Pin := Pointer_ as TDrawPin;
                  { hidden power pins get no connection point: Add never joins them to anything
                    by position, only by their (label) name }
                  N := NewNode(FileIndex, SheetOneIndexed, Pin, DPointInvalid);
                  N.LabelText := Pin.GetPinName;
                  N.Reference := MyRef;
                  N.Pin := Pin.GetNumber;
                  N.Method := Meth;
                  FoundIdx := FindName(Powers, Pin.GetPinName);
                  if FoundIdx >= 0 then
                    N.NetList := PtrInt(Powers.Objects[FoundIdx]);
                  Hold := Add(N);
                  if FoundIdx < 0 then
                    Powers.AddObject(Pin.GetPinName, TObject(PtrInt(Hold)));
                end;
              end;
            end;
          end;
        xNoConnect, xJunction:
          begin
            N := NewNode(FileIndex, SheetOneIndexed, Obj, Obj.PointA);
            Add(N);
          end;
        xPower:
          begin
            Pw := Obj as TDrawPower;
            N := NewNode(FileIndex, SheetOneIndexed, Obj, Obj.PointA);
            PowerLabelStr := GetPowerLabel(Pw);
            N.LabelText := PowerLabelStr;
            { does this power item exist already? }
            FoundIdx := FindName(Powers, PowerLabelStr);
            if FoundIdx >= 0 then
              N.NetList := PtrInt(Powers.Objects[FoundIdx]);
            Hold := Add(N);
            if FoundIdx < 0 then
              Powers.AddObject(PowerLabelStr, TObject(PtrInt(Hold)));
          end;
        xWire:
          begin
            N := NewNode(FileIndex, SheetOneIndexed, Obj, Obj.PointA);
            Hold := Add(N);
            N := NewNode(FileIndex, SheetOneIndexed, Obj, Obj.PointB);
            N.NetList := Hold;
            Add(N);
          end;
      end;
    end;

    { ---- junctions join the wires they sit on ---- }
    for i := 0 to Drawing.Count - 1 do
    begin
      Obj := Drawing[i];
      if Obj.GetType = xJunction then
      begin
        A := Obj.PointA;
        NetNumber := Nodes.Get(A);
        for j := 0 to Drawing.Count - 1 do
        begin
          Search := Drawing[j];
          { a wire with an end at this junction is already connected }
          if (Search.GetType = xWire) and (not PointsClose(Search.PointA, A)) and
             (not PointsClose(Search.PointB, A)) then
            if LineIsPointOnLine(Search.PointA, Search.PointB, A, DistAlong) then
            begin
              N := NewNode(FileIndex, SheetOneIndexed, nil, Search.PointA);
              N.NetList := NetNumber;
              NetNumber := Add(N);
            end;
        end;
      end;
    end;

    { ---- labels connect to the wire they sit on, and equal labels join ---- }
    for i := 0 to Drawing.Count - 1 do
    begin
      Obj := Drawing[i];
      if Obj.GetType = xLabelEx2 then
      begin
        Lbl := Obj as TDrawLabel;
        A := Lbl.GetLabelPoint;
        { look for a wire this label is on: only the first one found is used }
        for j := 0 to Drawing.Count - 1 do
        begin
          Search := Drawing[j];
          if (Search.GetType = xWire) and Search.IsInside(A.x, A.x, A.y, A.y) then
          begin
            A := Search.PointA; // the label point becomes the wire's first point
            Break;
          end;
        end;
        N := NewNode(FileIndex, SheetOneIndexed, Obj, A);
        N.LabelText := Lbl.GetValue;
        FoundIdx := FindName(Labels, Lbl.GetValue);
        if FoundIdx >= 0 then
        begin
          N.NetList := PtrInt(Labels.Objects[FoundIdx]);
          N.LabelText := '';
        end;
        Hold := Add(N);
        if FoundIdx < 0 then
          Labels.AddObject(Lbl.GetValue, TObject(PtrInt(Hold)));
      end;
    end;

    { the position map is no longer needed }
    Nodes.Clear;
  finally
    Labels.Free;
    Connected.Free;
    Powers.Free;
  end;
end;

{ ===========================================================================
  TNetList.Link  (procedure)
  Parameters:
    Lists: array of TNetList
    Imports: TList
  Notes:
    Link together the netlists of several sheets: nets with nodes of the same label are one net.
  =========================================================================== }
procedure TNetList.Link(Lists: array of TNetList; Imports: TList);
type
  TMap = record
    Old, New_: array of Integer;
  end;
var
  Labels: TStringList;
  Maps: array of TMap;
  Li, Ni, Vi, k, Q, NewNet, OldNet, Idx: Integer;
  Lst: TNetList;
  V: TNodeVector;
  Lab: String;
  Preferred: String;
  PreferredLevel: Integer;
  PreferredType: TObjType;
  LastNode: TNetListNode;
  Node: TNetListNode;

  function MapGet(const M: TMap; Old: Integer): Integer;
  var
    t: Integer;
  begin
    Result := 0;
    for t := 0 to High(M.Old) do
      if M.Old[t] = Old then begin
        Result := M.New_[t];
        Exit;
      end;
  end;

begin
  FCurrentNet := 1;
  Nodes.Clear;
  Nets.Clear;
  Labels := TStringList.Create;
  try
    Labels.CaseSensitive := True;
    SetLength(Maps, Length(Lists));

    { pass 1: which labels belong together }
    for Li := 0 to High(Lists) do
    begin
      Lst := Lists[Li];
      for Ni := 0 to Lst.Nets.Count - 1 do
      begin
        V := Lst.Nets.Vec(Ni);
        NewNet := 0;
        for Vi := 0 to High(V) do
        begin
          Lab := NodeLabel(V[Vi]);
          if Lab <> '' then
          begin
            Idx := Labels.IndexOf(Lab);
            if Idx >= 0 then
            begin
              Q := PtrInt(Labels.Objects[Idx]);
              if NewNet = 0 then
                NewNet := Q;
              if NewNet <> Q then
                for k := 0 to Labels.Count - 1 do
                  if PtrInt(Labels.Objects[k]) = Q then
                    Labels.Objects[k] := TObject(PtrInt(NewNet));
            end
            else
            begin
              if NewNet = 0 then
              begin
                NewNet := FCurrentNet;
                Inc(FCurrentNet);
              end;
              Labels.AddObject(Lab, TObject(PtrInt(NewNet)));
            end;
          end;
        end;
      end;
    end;

    { pass 2: the new net number of every (sheet, old net) }
    for Li := 0 to High(Lists) do
    begin
      Lst := Lists[Li];
      for Ni := 0 to Lst.Nets.Count - 1 do
      begin
        V := Lst.Nets.Vec(Ni);
        OldNet := Lst.Nets.Key(Ni);
        NewNet := 0;
        for Vi := 0 to High(V) do
        begin
          Lab := NodeLabel(V[Vi]);
          if Lab <> '' then
          begin
            Idx := Labels.IndexOf(Lab);
            if Idx >= 0 then
            begin
              Q := PtrInt(Labels.Objects[Idx]);
              if NewNet = 0 then
                NewNet := Q;
            end;
          end;
        end;
        if NewNet = 0 then
        begin
          NewNet := FCurrentNet;
          Inc(FCurrentNet);
        end;
        SetLength(Maps[Li].Old, Length(Maps[Li].Old) + 1);
        SetLength(Maps[Li].New_, Length(Maps[Li].New_) + 1);
        Maps[Li].Old[High(Maps[Li].Old)] := OldNet;
        Maps[Li].New_[High(Maps[Li].New_)] := NewNet;
      end;
    end;

    { pass 3: gather every node into its new net }
    for Li := 0 to High(Lists) do
    begin
      Lst := Lists[Li];
      for Ni := 0 to Lst.Nets.Count - 1 do
      begin
        V := Lst.Nets.Vec(Ni);
        NewNet := MapGet(Maps[Li], Lst.Nets.Key(Ni));
        for Vi := 0 to High(V) do
        begin
          V[Vi].NetList := NewNet;
          Nets.Push(NewNet, V[Vi]);
        end;
      end;
    end;

    { pass 4: the preferred name of each net }
    for Ni := 0 to Nets.Count - 1 do
    begin
      V := Nets.Vec(Ni);
      Preferred := '';
      PreferredLevel := 99999999;
      PreferredType := xNULL;
      LastNode := V[0];
      for Vi := 0 to High(V) do
      begin
        Node := V[Vi];
        LastNode := Node;
        if (Node.Parent <> nil) and (Node.Parent.GetType = xLabelEx2) then
        begin
          if (PreferredLevel >= Node.FileNameIndex) and (PreferredType <> xPower) then
          begin
            if Node.FileNameIndex <> 0 then
              { labels inside a hierarchical design are not unique: put the path of references in front }
              Preferred := GetPartialReferencePath(FindImport(Imports, Node.FileNameIndex)) +
                (Node.Parent as TDrawLabel).GetValue
            else
              { level 0 labels are unique and safe to use unmodified }
              Preferred := (Node.Parent as TDrawLabel).GetValue;
            PreferredLevel := Node.FileNameIndex;
            PreferredType := xLabelEx2;
          end;
        end
        else if (Node.Parent <> nil) and (Node.Parent.GetType = xPower) then
        begin
          { power symbols are effectively global }
          if PreferredLevel >= Node.FileNameIndex then
          begin
            Preferred := GetPowerLabel(Node.Parent as TDrawPower);
            PreferredLevel := Node.FileNameIndex;
            PreferredType := xPower;
          end;
        end;
      end;
      if Preferred = '' then
        Preferred := Format('_N_%d', [LastNode.NetList]);
      for Vi := 0 to High(V) do
      begin
        V[Vi].PreferredLabel := Preferred;
        Nets.SetNode(Ni, Vi, V[Vi]);
      end;
    end;
  finally
    Labels.Free;
  end;
end;

{ ===========================================================================
  TNetList.ApplyHints  (procedure)
  Parameters:  none
  Notes:
    Renumber the nets using the hints stored in the symbols, and store the numbers back.
  =========================================================================== }
procedure TNetList.ApplyHints;
var
  RemapFrom, RemapTo: array of Integer;
  Used: array of Integer;
  NextUnused, Ni, Vi, Hint, At, k: Integer;
  V: TNodeVector;
  Node: TNetListNode;
  DoRemap: Boolean;

  function RemapIndex(Net: Integer): Integer;
  var
    t: Integer;
  begin
    Result := -1;
    for t := 0 to High(RemapFrom) do
      if RemapFrom[t] = Net then begin
        Result := t;
        Exit;
      end;
  end;

  function IsUsed(N: Integer): Boolean;
  var
    t: Integer;
  begin
    Result := False;
    for t := 0 to High(Used) do
      if Used[t] = N then begin
        Result := True;
        Exit;
      end;
  end;

begin
  NextUnused := 1;
  for Ni := 0 to Nets.Count - 1 do
  begin
    V := Nets.Vec(Ni);
    for Vi := 0 to High(V) do
    begin
      Node := V[Vi];
      if Node.Method <> nil then
      begin
        Hint := Node.Method.GetNetlistHint(Node.Pin);
        if Hint <> 0 then
        begin
          DoRemap := True;
          At := RemapIndex(Node.NetList);
          if At >= 0 then
            if RemapTo[At] <= Hint then
              DoRemap := False; // the smaller number wins
          if DoRemap and IsUsed(Hint) then
            DoRemap := False;
          if DoRemap then
          begin
            if At >= 0 then
              RemapTo[At] := Hint
            else
            begin
              SetLength(RemapFrom, Length(RemapFrom) + 1);
              SetLength(RemapTo, Length(RemapTo) + 1);
              RemapFrom[High(RemapFrom)] := Node.NetList;
              RemapTo[High(RemapTo)] := Hint;
            end;
            SetLength(Used, Length(Used) + 1);
            Used[High(Used)] := Hint;
            NextUnused := Max(NextUnused, Node.NetList + 1);
            NextUnused := Max(NextUnused, Hint + 1);
          end;
        end;
      end;
    end;
  end;

  for Ni := 0 to Nets.Count - 1 do
  begin
    V := Nets.Vec(Ni);
    for Vi := 0 to High(V) do
    begin
      Node := V[Vi];
      At := RemapIndex(Node.NetList);
      if At < 0 then
      begin
        SetLength(RemapFrom, Length(RemapFrom) + 1);
        SetLength(RemapTo, Length(RemapTo) + 1);
        RemapFrom[High(RemapFrom)] := Node.NetList;
        RemapTo[High(RemapTo)] := NextUnused;
        Inc(NextUnused);
        At := High(RemapFrom);
      end;
      Node.NetList := RemapTo[At];
      if Node.Method <> nil then
        Node.Method.SetNetlistHint(Node.Pin, Node.NetList);
      Nets.SetNode(Ni, Vi, Node);
    end;
  end;
end;

{ ===========================================================================
  TNetList.WriteWires  (procedure)
  Parameters:  none
  Notes:
    Tell every wire which net it is on.
  =========================================================================== }
procedure TNetList.WriteWires;
var
  Ni, Vi: Integer;
  V: TNodeVector;
begin
  for Ni := 0 to Nets.Count - 1 do
  begin
    V := Nets.Vec(Ni);
    for Vi := 0 to High(V) do
      if (V[Vi].Parent <> nil) and (V[Vi].Parent.GetType = xWire) then
        (V[Vi].Parent as TDrawLine).Network := Nets.Key(Ni);
  end;
end;

{ ===========================================================================
  TNetList.MakeNet  (procedure)
  Parameters:
    Design: TDesignFile - the design
  Notes:
    Builds the netlist of a whole design: nets per sheet, linked across sheets by label,
    preferred names chosen, numbers stabilised from the symbols' hints (which are stored back
    into them), and wires told which net they are on.
  =========================================================================== }
procedure TNetList.MakeNet(Design: TDesignFile);
var
  Lists: array of TNetList;
  Imports: TList;
  Root: TImportFile;
  Ip, i, Base, NewSheets, Counter: Integer;
begin
  ClearImports;
  FImports := TList.Create;
  Imports := FImports;
  SetLength(Lists, 0);
  ImportErrors := '';
  try
    Root := TImportFile.Create;
    Root.Design := Design;
    Root.OwnsDesign := False;
    Root.FileIndex := 0;
    Root.ParentIndex := -1;
    Root.RefContext := '';
    Imports.Add(Root);
    Counter := 1;
    { every import has its sheets netlisted; a hierarchical symbol met on the way adds an import at the end,
      so the list grows while it is walked }
    Ip := 0;
    while Ip < Imports.Count do
    begin
      Base := Length(Lists);
      NewSheets := TImportFile(Imports[Ip]).Design.SheetCount;
      SetLength(Lists, Base + NewSheets);
      for i := Base to High(Lists) do Lists[i] := nil;
      for i := 0 to NewSheets - 1 do
      begin
        Lists[Base + i] := TNetList.Create;
        Lists[Base + i].MakeNetForSheet(Imports, Ip, i, Counter, FollowImports);
        ImportErrors := ImportErrors + Lists[Base + i].ImportErrors;
      end;
      if not FollowImports then
        Break;
      Inc(Ip);
    end;
    Link(Lists, Imports);
    ApplyHints;
    WriteWires;
  finally
    for i := 0 to High(Lists) do Lists[i].Free;
    { the imports stay: the nodes point into the designs they hold (ClearImports) }
  end;
end;

{ ---- output ---- }

{ ===========================================================================
  PutText  (procedure)
  Parameters:
    Dest: TStream - where to write
    const S: String - the text
  Notes:
    Writes text to a stream the way TinyCAD's text-mode output does: every line feed becomes a
    carriage return plus line feed.
  =========================================================================== }
procedure PutText(Dest: TStream; const S: String);
var
  T: String;
begin
  T := StringReplace(S, #10, #13#10, [rfReplaceAll]); // text-mode file: LF becomes CRLF
  if T <> '' then
    Dest.WriteBuffer(T[1], Length(T));
end;

{ ===========================================================================
  TNetList.WriteProtel  (procedure)
  Parameters:
    Design: TDesignFile - the design
    Dest: TStream - the stream to write to
  Notes:
    Writes the design's netlist in Protel format: a [ ] block for each distinct reference
    (reference, package, name) in drawing order, then a ( ) block for each net with two or more
    pins, named by its label or N followed by the net number. Builds the netlist first.
  =========================================================================== }
procedure TNetList.WriteProtel(Design: TDesignFile; Dest: TStream);
var
  Referenced: TStringList;
  i, j, k, Ni, Len, Count, LabelNet: Integer;
  Obj: TDrawingObject;
  M: TDrawMethod;
  Ref, Pkg, Name, TheLine, TheLabel, Add_: String;
  V: TNodeVector;
  First, Labeled: Boolean;
begin
  MakeNet(Design);
  Referenced := TStringList.Create;
  try
    Referenced.CaseSensitive := True;
    { a component for every distinct reference, in drawing order }
    for i := 0 to Design.SheetCount - 1 do
      for j := 0 to Design.Sheets[i].Drawing.Count - 1 do
      begin
        Obj := Design.Sheets[i].Drawing[j];
        if Obj.GetType = xMethodEx3 then
        begin
          M := Obj as TDrawMethod;
          Ref := M.GetRef;
          if Referenced.IndexOf(Ref) < 0 then
          begin
            Referenced.Add(Ref);
            Pkg := 'This part has no ''Package'' attribute';
            Name := M.GetName;
            for k := 2 to M.GetFieldCount - 1 do
              if SameText(M.GetFieldName(k), 'package') then
                Pkg := M.GetField(k);
            PutText(Dest, '[' + #10 + Ref + #10 + Pkg + #10 + Name + #10#10#10 + #10 + ']' + #10);
          end;
        end;
      end;

    for Ni := 0 to Nets.Count - 1 do
    begin
      V := Nets.Vec(Ni);
      if Length(V) = 0 then
        Continue;
      TheLine := '';
      TheLabel := '';
      First := True;
      Labeled := False;
      Len := 0;
      Count := 0;
      LabelNet := V[0].NetList;
      for k := 0 to High(V) do
      begin
        if (NodeLabel(V[k]) <> '') and (not Labeled) then
        begin
          TheLabel := NodeLabel(V[k]);
          Labeled := True;
        end;
        if V[k].Reference <> '' then
        begin
          Add_ := V[k].Reference + '-' + V[k].Pin;
          Len := Len + CharLength(Add_);
          if Len > 127 then
          begin
            TheLine := TheLine + #10;
            Len := CharLength(Add_);
            First := True;
          end;
          if First then
            First := False
          else
          begin
            TheLine := TheLine + #10;
            Inc(Len);
          end;
          TheLine := TheLine + Add_;
          Inc(Count);
        end;
      end;
      if Count > 1 then
      begin
        PutText(Dest, '(' + #10);
        if Labeled then
          PutText(Dest, TheLabel)
        else
          PutText(Dest, Format('N%.6d', [LabelNet]));
        PutText(Dest, #10 + TheLine + #10 + ')' + #10);
      end;
    end;
  finally
    Referenced.Free;
  end;
end;

{ ===========================================================================
  TNetList.DumpText  (function)
  Parameters:  none
  Returns:
    String - the listing
  Notes:
    A plain-text listing for testing: one line per net with its number, preferred name and its
    pins as reference-pin.
  =========================================================================== }
function TNetList.DumpText: String;
var
  Ni, Vi: Integer;
  V: TNodeVector;
  Line: String;
begin
  Result := '';
  for Ni := 0 to Nets.Count - 1 do
  begin
    V := Nets.Vec(Ni);
    Line := Format('NET %d name=%s :', [Nets.Key(Ni), NodePreferredLabel(V[0])]);
    for Vi := 0 to High(V) do
      if V[Vi].Reference <> '' then
        Line := Line + ' ' + V[Vi].Reference + '-' + V[Vi].Pin;
    Result := Result + Line + #10;
  end;
end;

end.
