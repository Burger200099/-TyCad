// SPDX-License-Identifier: LGPL-2.1-or-later
{ The data side of the symbol (.TCLib) editor: everything the editor does to a symbol except the
  window. A TSymbolEditor works on its own copy of one library symbol (its drawing and its names),
  so the library can be re-read underneath it. It creates new symbols, edits existing ones, manages
  parts, pins, aliases and extra fields, checks the symbol for mistakes, and stores it back into a
  library, another library, or deletes it.

  A library "set" is one drawing with one or more names (aliases). A symbol with several parts per
  package (the gates of an IC) either shares one drawing, with each pin tagged with its part
  (homogeneous), or has a drawing per part (heterogeneous).

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit USymEdit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, UDPoint, UDrawTypes, UGeometry, UDrawingObjects, USymbols, UDesign,
  ULibrary, UXMLReader, UXMLWriter;

type
  TSymbolIssue = record
    Severity: Integer;   // 0 = error (should not be saved), 1 = warning
    Text: String;
  end;
  TSymbolIssues = array of TSymbolIssue;

  TSymbolEditor = class;

  { a symbol editor that stores somewhere else than a .TCLib (the parts file): gets the symbol's text and returns the id it was stored under }
  TSymbolBlobSave = function(const Blob: String; Ed: TSymbolEditor): Int64 of object;

  TSymbolEditor = class
  private
    FOnSaveBlob: TSymbolBlobSave;
    FSink: TObject;
    FLib: TSymbolLibrary;
    FSet: TLibrarySymbolSet;     // the editor's own copy
    FDoc: TSymbolDocument;
    FSourceID: Int64;            // SymbolID in the library this was opened from; -1 when new
    FDirty: Boolean;
    function CopySet(Src: TLibrarySymbolSet; ALib: TSymbolLibrary): TLibrarySymbolSet;
    procedure Issue(var L: TSymbolIssues; Severity: Integer; const Text: String);
  public
    constructor Create(ALib: TSymbolLibrary);
    destructor Destroy; override;
    procedure NewSymbol(const AName, ARef, ADescription: String; AParts: Integer; AHetero: Boolean);
    procedure OpenSet(ASet: TLibrarySymbolSet);
    { edits a symbol that does not come from a .TCLib: its text, the name / reference letters / description it is shown with, and the id it has where it is kept (-1 for a
      new one). Needs OnSaveBlob to be stored; there is no library (StoreLibrary is nil). }
    procedure OpenBlob(const Blob, AName, ARef, ADescription: String; ASourceID: Int64);
    function PartCount: Integer;
    procedure SetPartCount(N: Integer);
    function Heterogeneous: Boolean;
    function PartSheet(Part: Integer): TDesignSheet;
    function AddPin(Part: Integer; const At: TDPoint; const AName, ANumber: String;
      ADir, ALength, AWhich: Integer): TDrawPin;
    function PinCount(Part: Integer): Integer;
    function AddAlias(const AName, ARef, ADescription: String): TLibraryRecord;
    procedure RemoveAlias(Index: Integer);
    procedure SetField(RecIndex: Integer; const AName, ADefault: String; AType: Integer);
    { the symbol as a design file the drawing view can edit (symbol mode: a sheet per part for a heterogeneous symbol, otherwise one shared sheet), and the
      view's edited design taken back; both go through the XML a save writes, so nothing is shared between the two }
    function MakeDesign: TDesignFile;
    procedure TakeDesign(D: TDesignFile);
    { the symbol's names and fields as a copy the Symbol Properties dialog works on, and the dialog's result put in their place (the symbol keeps its id and its
      number of parts) }
    function CloneSet: TLibrarySymbolSet;
    procedure ReplaceSet(Src: TLibrarySymbolSet);
    { the library the symbol is stored into (the library panel may open a library again, so the owner says which object holds it now) }
    procedure SetLibrary(ALib: TSymbolLibrary);
    { Set parts per package and the Homogeneous / Heterogeneous commands, applied to the design the view is editing }
    procedure ApplyPartCount(D: TDesignFile; N: Integer);
    function ApplyHeterogeneous(D: TDesignFile; Value: Boolean): Boolean;
    function Validate: TSymbolIssues;
    function Save: Int64;
    function CopyTo(ADest: TSymbolLibrary): Int64;
    procedure DeleteFromLibrary;
    property StoreLibrary: TSymbolLibrary read FLib;
    property OnSaveBlob: TSymbolBlobSave read FOnSaveBlob write FOnSaveBlob;
    { an object that belongs to this editor (freed with it): the owner of OnSaveBlob keeps its data there }
    property Sink: TObject read FSink write FSink;
    property LibrarySet: TLibrarySymbolSet read FSet;
    property Doc: TSymbolDocument read FDoc;
    property SourceID: Int64 read FSourceID;
    property Dirty: Boolean read FDirty write FDirty;
  end;

implementation


uses UStrings;

{ ===========================================================================
  TSymbolEditor.Create  (constructor)
  Parameters:
    ALib: TSymbolLibrary - the library that symbols are stored into (not owned)
  Notes:
    Creates an editor bound to a library; nothing is open until NewSymbol or OpenSet.
  =========================================================================== }
constructor TSymbolEditor.Create(ALib: TSymbolLibrary);
begin
  inherited Create;
  FLib := ALib;
  FSourceID := -1;
end;

{ ===========================================================================
  TSymbolEditor.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the editor's own copy of the symbol; the library is untouched.
  =========================================================================== }
destructor TSymbolEditor.Destroy;
begin
  FSink.Free;
  FDoc.Free;
  FSet.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TSymbolEditor.Issue  (procedure)
  Parameters:
    var L: TSymbolIssues - the list (in/out)
    Severity: Integer - 0 for an error, 1 for a warning
    const Text: String - what is wrong
  Notes:
    Appends a finding to a list of validation results.
  =========================================================================== }
procedure TSymbolEditor.Issue(var L: TSymbolIssues; Severity: Integer; const Text: String);
begin
  SetLength(L, Length(L) + 1);
  L[High(L)].Severity := Severity;
  L[High(L)].Text := Text;
end;

{ ===========================================================================
  TSymbolEditor.CopySet  (function)
  Parameters:
    Src: TLibrarySymbolSet - the set to copy
    ALib: TSymbolLibrary - the library to read field values from, or nil
  Returns:
    TLibrarySymbolSet - the copy; the caller owns it
  Notes:
    Makes a copy of a library set's data (parts per package, orientation, every name with
    reference, description, display types and fields), loading field values from the library
    first when a library is given. The copy has no database ids.
  =========================================================================== }
function TSymbolEditor.CopySet(Src: TLibrarySymbolSet; ALib: TSymbolLibrary): TLibrarySymbolSet;
var
  i, j: Integer;
  R, NewR: TLibraryRecord;
begin
  Result := TLibrarySymbolSet.Create;
  Result.SymbolID := Src.SymbolID;
  Result.Ppp := Src.Ppp;
  Result.Orientation := Src.Orientation;
  for i := 0 to Src.RecordCount - 1 do
  begin
    R := Src.Records[i];
    if (ALib <> nil) and (not R.FieldsLoaded) then
      ALib.LoadFields(R);
    NewR := Result.AddRecord;
    NewR.Name := R.Name;
    NewR.Reference := R.Reference;
    NewR.Description := R.Description;
    NewR.NameType := R.NameType;
    NewR.RefType := R.RefType;
    NewR.NameID := -1;
    NewR.FieldsLoaded := True;
    SetLength(NewR.Fields, Length(R.Fields));
    for j := 0 to High(R.Fields) do NewR.Fields[j] := R.Fields[j];
  end;
end;

{ ===========================================================================
  TSymbolEditor.NewSymbol  (procedure)
  Parameters:
    const AName: String - the symbol's first name
    const ARef: String - its reference prefix, e.g. R? or U?
    const ADescription: String - the description shown in the library list
    AParts: Integer - number of parts per package (at least 1)
    AHetero: Boolean - True if every part is drawn differently
  Notes:
    Starts a new symbol: one name, no pins, and either one shared drawing or (heterogeneous) one
    drawing per part. Replaces whatever was being edited.
  =========================================================================== }
procedure TSymbolEditor.NewSymbol(const AName, ARef, ADescription: String; AParts: Integer; AHetero: Boolean);
var
  R: TLibraryRecord;
  i, N: Integer;
begin
  FDoc.Free;
  FSet.Free;
  FSourceID := -1;
  N := Max(1, AParts);
  FSet := TLibrarySymbolSet.Create;
  FSet.SymbolID := -1;
  FSet.Ppp := N;
  FSet.Orientation := 0;
  R := FSet.AddRecord;
  R.Name := AName;
  R.Reference := ARef;
  R.Description := ADescription;
  R.NameType := 0;
  R.RefType := 1;
  FDoc := TSymbolDocument.Create;
  FDoc.Heterogeneous := AHetero;
  if AHetero then
    for i := 1 to N do FDoc.AddSheet
  else
    FDoc.AddSheet;
  FDirty := True;
end;

{ ===========================================================================
  TSymbolEditor.OpenSet  (procedure)
  Parameters:
    ASet: TLibrarySymbolSet - the set to edit (from the library's list)
  Notes:
    Opens an existing library symbol for editing on a private copy of its data and drawing, so
    the library can be re-read while editing.
  =========================================================================== }
procedure TSymbolEditor.OpenSet(ASet: TLibrarySymbolSet);
begin
  FDoc.Free;
  FDoc := nil;
  FSet.Free;
  FSet := CopySet(ASet, FLib);
  FSourceID := ASet.SymbolID;
  FDoc := TSymbolDocument.Create;
  FDoc.LoadFromBlob(FLib.GetSymbolBlob(ASet));
  FDirty := False;
end;

{ ===========================================================================
  TSymbolEditor.OpenBlob  (procedure)
  Parameters:
    const Blob: String - the symbol's text (the XML a .TCLib keeps)
    const AName, ARef, ADescription: String - the name, reference letters and description the symbol is shown with
    ASourceID: Int64 - the id the symbol has where it is kept; -1 starts a symbol that is not stored yet
  Notes:
    Edits a symbol held outside a symbol library (the parts file). An empty Blob starts an empty one-part symbol. A symbol with a drawing per part keeps its parts; the
    parts per package of the set is the number of drawings (1 for a shared drawing). Replaces whatever was being edited.
  =========================================================================== }
procedure TSymbolEditor.OpenBlob(const Blob, AName, ARef, ADescription: String; ASourceID: Int64);
var
  R: TLibraryRecord;
begin
  FDoc.Free;
  FDoc := nil;
  FSet.Free;
  FSet := TLibrarySymbolSet.Create;
  FSet.SymbolID := ASourceID;
  FSet.Orientation := 0;
  R := FSet.AddRecord;
  R.Name := AName;
  R.Reference := ARef;
  R.Description := ADescription;
  R.NameType := 0;
  R.RefType := 1;
  FDoc := TSymbolDocument.Create;
  if Blob <> '' then
    FDoc.LoadFromBlob(Blob)
  else
    FDoc.AddSheet;
  if FDoc.Heterogeneous then
    FSet.Ppp := Max(1, FDoc.SheetCount)
  else
    FSet.Ppp := 1;
  FSourceID := ASourceID;
  FDirty := Blob = '';
end;

{ ===========================================================================
  TSymbolEditor.PartCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    Number of parts per package.
  =========================================================================== }
function TSymbolEditor.PartCount: Integer;
begin
  Result := FSet.Ppp;
end;

{ ===========================================================================
  TSymbolEditor.Heterogeneous  (function)
  Parameters:  none
  Returns:
    Boolean - True for a drawing per part
  Notes:
    Whether each part has its own drawing.
  =========================================================================== }
function TSymbolEditor.Heterogeneous: Boolean;
begin
  Result := FDoc.Heterogeneous;
end;

{ ===========================================================================
  TSymbolEditor.PartSheet  (function)
  Parameters:
    Part: Integer - part number, 0-based
  Returns:
    TDesignSheet - the sheet
  Notes:
    The sheet to draw a part on: that part's own sheet for a heterogeneous symbol, otherwise the
    one shared sheet.
  =========================================================================== }
function TSymbolEditor.PartSheet(Part: Integer): TDesignSheet;
begin
  if FDoc.Heterogeneous then
    Result := FDoc.Sheets[Part]
  else
    Result := FDoc.Sheets[0];
end;

{ ===========================================================================
  TSymbolEditor.SetPartCount  (procedure)
  Parameters:
    N: Integer - the new number of parts (at least 1)
  Notes:
    Changes the number of parts. A heterogeneous symbol gains or loses part sheets; a shared
    drawing loses the pins of parts that no longer exist.
  =========================================================================== }
procedure TSymbolEditor.SetPartCount(N: Integer);
var
  j: Integer;
  Sh: TDesignSheet;
  Obj: TDrawingObject;
begin
  N := Max(1, N);
  if FDoc.Heterogeneous then
  begin
    while FDoc.SheetCount < N do FDoc.AddSheet;
    while FDoc.SheetCount > N do FDoc.RemoveLastSheet;
  end
  else
  begin
    { one shared drawing: pins of parts that no longer exist go }
    Sh := FDoc.Sheets[0];
    for j := Sh.Drawing.Count - 1 downto 0 do
    begin
      Obj := Sh.Drawing[j];
      if (Obj is TDrawPin) and ((Obj as TDrawPin).Part >= N) then
        Sh.Drawing.Remove(Obj);
    end;
  end;
  FSet.Ppp := N;
  FDirty := True;
end;

{ ===========================================================================
  TSymbolEditor.AddPin  (function)
  Parameters:
    Part: Integer - part number, 0-based
    const At: TDPoint - the pin's connection point, in internal units
    const AName: String - the pin name
    const ANumber: String - the pin number
    ADir: Integer - 0 up, 1 down, 2 left, 3 right
    ALength: Integer - length of the pin line
    AWhich: Integer - the pin shape code
  Returns:
    TDrawPin - the new pin
  Notes:
    Adds a pin to a part: its connection point, name, number, direction, length and shape (0
    normal, 1 dot, 2 clock, 3 dot and clock, 4 power, 5 hidden). Name and number are shown. On a
    shared drawing the pin is tagged with its part.
  =========================================================================== }
function TSymbolEditor.AddPin(Part: Integer; const At: TDPoint; const AName, ANumber: String;
  ADir, ALength, AWhich: Integer): TDrawPin;
var
  Sh: TDesignSheet;
begin
  Sh := PartSheet(Part);
  Result := TDrawPin.Create(Sh.Options);
  Result.PointA := At;
  Result.Str := AName;
  Result.Number := ANumber;
  Result.Dir := ADir;
  Result.Length := ALength;
  Result.Which := AWhich;
  Result.Show := 3;
  if FDoc.Heterogeneous then
    Result.Part := 0
  else
    Result.Part := Part;
  Sh.Options.EditPart := Result.Part;
  Result.DetermineSize;
  Sh.Drawing.Add(Result);
  FDirty := True;
end;

{ ===========================================================================
  TSymbolEditor.PinCount  (function)
  Parameters:
    Part: Integer - part number, 0-based
  Returns:
    Integer - the count
  Notes:
    Number of pins in a part.
  =========================================================================== }
function TSymbolEditor.PinCount(Part: Integer): Integer;
var
  Sh: TDesignSheet;
  i: Integer;
begin
  Result := 0;
  Sh := PartSheet(Part);
  for i := 0 to Sh.Drawing.Count - 1 do
    if (Sh.Drawing[i] is TDrawPin) then
      if FDoc.Heterogeneous or ((Sh.Drawing[i] as TDrawPin).Part = Part) then
        Inc(Result);
end;

{ ===========================================================================
  TSymbolEditor.AddAlias  (function)
  Parameters:
    const AName: String - the alias
    const ARef: String - its reference prefix
    const ADescription: String - its description
  Returns:
    TLibraryRecord - the new record
  Notes:
    Adds another name for the same drawing (an alias, e.g. the 74HC00 for a 7400); it starts
    with the first name's extra fields.
  =========================================================================== }
function TSymbolEditor.AddAlias(const AName, ARef, ADescription: String): TLibraryRecord;
var
  First: TLibraryRecord;
  j: Integer;
begin
  Result := FSet.AddRecord;
  Result.Name := AName;
  Result.Reference := ARef;
  Result.Description := ADescription;
  Result.NameType := 0;
  Result.RefType := 1;
  Result.NameID := -1;
  Result.FieldsLoaded := True;
  if FSet.RecordCount > 1 then
  begin
    First := FSet.Records[0];
    SetLength(Result.Fields, Length(First.Fields));
    for j := 0 to High(First.Fields) do Result.Fields[j] := First.Fields[j];
  end;
  FDirty := True;
end;

{ ===========================================================================
  TSymbolEditor.RemoveAlias  (procedure)
  Parameters:
    Index: Integer - position of the name, 0-based
  Notes:
    Removes one name. The last remaining name cannot be removed.
  =========================================================================== }
procedure TSymbolEditor.RemoveAlias(Index: Integer);
var
  Keep: TLibrarySymbolSet;
  i: Integer;
  R, NewR: TLibraryRecord;
  j: Integer;
begin
  if (Index < 0) or (Index >= FSet.RecordCount) or (FSet.RecordCount <= 1) then
    Exit;
  { a set has no "delete a record" operation, so rebuild it without that one }
  Keep := TLibrarySymbolSet.Create;
  Keep.SymbolID := FSet.SymbolID;
  Keep.Ppp := FSet.Ppp;
  Keep.Orientation := FSet.Orientation;
  for i := 0 to FSet.RecordCount - 1 do
    if i <> Index then
    begin
      R := FSet.Records[i];
      NewR := Keep.AddRecord;
      NewR.Name := R.Name; NewR.Reference := R.Reference; NewR.Description := R.Description;
      NewR.NameType := R.NameType; NewR.RefType := R.RefType; NewR.NameID := -1; NewR.FieldsLoaded := True;
      SetLength(NewR.Fields, Length(R.Fields));
      for j := 0 to High(R.Fields) do NewR.Fields[j] := R.Fields[j];
    end;
  FSet.Free;
  FSet := Keep;
  FDirty := True;
end;

{ ===========================================================================
  TSymbolEditor.SetField  (procedure)
  Parameters:
    RecIndex: Integer - which name, 0-based
    const AName: String - the field name
    const ADefault: String - its default value
    AType: Integer - display type: 0 hidden, 1 shown ...
  Notes:
    Sets an extra field (such as Footprint) of one name, adding it if it is not there; field
    names are matched ignoring case.
  =========================================================================== }
procedure TSymbolEditor.SetField(RecIndex: Integer; const AName, ADefault: String; AType: Integer);
var
  R: TLibraryRecord;
  i, n: Integer;
begin
  R := FSet.Records[RecIndex];
  for i := 0 to High(R.Fields) do
    if SameText(R.Fields[i].Name, AName) then
    begin
      R.Fields[i].Default := ADefault;
      R.Fields[i].FieldType := Cardinal(AType);
      FDirty := True;
      Exit;
    end;
  n := Length(R.Fields);
  SetLength(R.Fields, n + 1);
  R.Fields[n].Name := AName;
  R.Fields[n].Default := ADefault;
  R.Fields[n].FieldType := Cardinal(AType);
  R.FieldsLoaded := True;
  FDirty := True;
end;

{ ===========================================================================
  TSymbolEditor.MakeDesign  (function)
  Parameters:  none
  Returns:
    TDesignFile - a design file in symbol mode; the caller owns it
  Notes:
    Copies the symbol's drawing into a design file the drawing view can edit, with the pins of
    the first part showing, and gives its objects ids.
  =========================================================================== }
function TSymbolEditor.MakeDesign: TDesignFile;
var
  MS: TMemoryStream;
  W: TXMLWriter;
  i: Integer;
begin
  MS := TMemoryStream.Create;
  try
    for i := 0 to FDoc.SheetCount - 1 do FDoc.Sheets[i].Options.UnTagAll;
    W := TXMLWriter.Create(MS);
    try
      W.AddTag('TinyCADSheets');
      for i := 0 to FDoc.SheetCount - 1 do FDoc.Sheets[i].SaveXMLEx(W, True, True, False);
      W.CloseTag;
    finally
      W.Free;
    end;
    MS.Position := 0;
    Result := TDesignFile.Create;
    try
      Result.SymbolMode := True;
      Result.Heterogeneous := FDoc.Heterogeneous;
      Result.AllowEmptySheets := True;
      Result.LoadFromStream(MS);
      Result.AssignIds;
    except
      Result.Free;
      raise;
    end;
  finally
    MS.Free;
  end;
end;

{ ===========================================================================
  TSymbolEditor.TakeDesign  (procedure)
  Parameters:
    D: TDesignFile - the design the view has been editing
  Notes:
    Replaces the symbol's drawing with what the design holds: every sheet for a heterogeneous
    symbol, the first sheet otherwise. The names and fields are not touched. This is how the
    drawing view's work reaches the symbol before it is stored.
  =========================================================================== }
procedure TSymbolEditor.TakeDesign(D: TDesignFile);
var
  MS: TMemoryStream;
  R: TXMLReader;
  Tag: String;
  Sh: TDesignSheet;
begin
  MS := TMemoryStream.Create;
  try
    D.SaveToStream(MS);
    MS.Position := 0;
    R := TXMLReader.Create(MS);
    try
      R.NextTag(Tag);
      FDoc.Clear;
      FDoc.Heterogeneous := D.Heterogeneous;
      R.IntoTag;
      while R.NextTag(Tag) do
        if (Tag = 'TinyCAD') and (D.Heterogeneous or (FDoc.SheetCount = 0)) then
        begin
          Sh := FDoc.AddSheet;
          Sh.LoadXMLInto(R, Sh.Drawing, True, True);
        end;
      R.OutOfTag;
    finally
      R.Free;
    end;
  finally
    MS.Free;
  end;
  FDirty := True;
end;

{ ===========================================================================
  TSymbolEditor.CloneSet  (function)
  Parameters:  none
  Returns:
    TLibrarySymbolSet - a copy of the symbol's names and fields; the caller owns it
  Notes:
    What the Symbol Properties dialog edits, so Cancel leaves the symbol as it was.
  =========================================================================== }
function TSymbolEditor.CloneSet: TLibrarySymbolSet;
begin
  Result := CopySet(FSet, nil);
end;

{ ===========================================================================
  TSymbolEditor.ReplaceSet  (procedure)
  Parameters:
    Src: TLibrarySymbolSet - the edited copy
  Notes:
    Puts the names, fields and default orientation of an edited copy in place of the symbol's
    own. The symbol keeps its id in the library and its number of parts.
  =========================================================================== }
procedure TSymbolEditor.ReplaceSet(Src: TLibrarySymbolSet);
var
  New: TLibrarySymbolSet;
begin
  New := CopySet(Src, nil);
  New.SymbolID := FSet.SymbolID;
  New.Ppp := FSet.Ppp;
  FSet.Free;
  FSet := New;
  FDirty := True;
end;

{ ===========================================================================
  TSymbolEditor.SetLibrary  (procedure)
  Parameters:
    ALib: TSymbolLibrary - the library object that holds the symbol's library now
  Notes:
    Points the editor at a library object (not owned).
  =========================================================================== }
procedure TSymbolEditor.SetLibrary(ALib: TSymbolLibrary);
begin
  FLib := ALib;
end;

{ ===========================================================================
  TSymbolEditor.ApplyPartCount  (procedure)
  Parameters:
    D: TDesignFile - the symbol-mode design being edited
    N: Integer - the number of parts (1 to 26)
  Notes:
    Set parts per package (CTinyCadMultiSymbolDoc::OnLibrarySetpartsperpackage): a symbol with a
    drawing for each part gains or loses sheets from the end; a shared drawing loses the pins of
    the parts that are gone and shows the last part if it was showing one that is gone.
  =========================================================================== }
procedure TSymbolEditor.ApplyPartCount(D: TDesignFile; N: Integer);
var
  j: Integer;
  Sh: TDesignSheet;
  Obj: TDrawingObject;
begin
  N := Max(1, Min(26, N));
  if D.Heterogeneous then
  begin
    while D.SheetCount < N do D.AddSheet;
    while D.SheetCount > N do D.RemoveSheet(D.SheetCount - 1);
  end
  else
  begin
    Sh := D.Sheets[0];
    for j := Sh.Drawing.Count - 1 downto 0 do
    begin
      Obj := Sh.Drawing[j];
      if (Obj is TDrawPin) and ((Obj as TDrawPin).Part >= N) then
        Sh.Drawing.Remove(Obj);
    end;
    if D.EditPart >= N then
      D.EditPart := N - 1;
    Sh.Options.EditPart := D.EditPart;
  end;
  FSet.Ppp := N;
  FDirty := True;
end;

{ ===========================================================================
  TSymbolEditor.ApplyHeterogeneous  (function)
  Parameters:
    D: TDesignFile - the symbol-mode design being edited
    Value: Boolean - True for a drawing for each part, False for one shared drawing
  Returns:
    Boolean - False when the symbol has several parts, so nothing changed
  Notes:
    Homogeneous / Heterogeneous Symbol. As in TinyCAD the kind can only be changed while the
    symbol has one part per package; choosing the kind it already is does nothing.
  =========================================================================== }
function TSymbolEditor.ApplyHeterogeneous(D: TDesignFile; Value: Boolean): Boolean;
begin
  Result := True;
  if D.Heterogeneous = Value then
    Exit;
  if FSet.Ppp <> 1 then
    Exit(False);
  D.Heterogeneous := Value;
  D.EditPart := 0;
  D.Sheets[0].Options.EditPart := 0;
  FDirty := True;
end;

{ ===========================================================================
  TSymbolEditor.Validate  (function)
  Parameters:  none
  Returns:
    TSymbolIssues - the findings; empty when all is well
  Notes:
    Checks the symbol for mistakes. Errors: an empty or repeated name, a pin in a part the
    symbol does not have, two pins on the same spot. Warnings: no reference prefix, a pin with
    no number, pins off the grid (one warning that counts them), a repeated pin number (power
    pins excepted), a part without pins, no pins at all.
  =========================================================================== }
function TSymbolEditor.Validate: TSymbolIssues;
var
  i, j, k, a, b, Pins: Integer;
  Sh: TDesignSheet;
  P, Q: TDrawPin;
  R: TLibraryRecord;
  Seen: TStringList;
  Key: String;
  Grid: Double;
  OffGrid: Integer;
  FirstOff: String;
begin
  SetLength(Result, 0);
  OffGrid := 0;
  FirstOff := '';
  for i := 0 to FSet.RecordCount - 1 do
  begin
    R := FSet.Records[i];
    if Trim(R.Name) = '' then
      Issue(Result, 0, Format(rsNameIsEmpty, [i + 1]));
    for j := 0 to i - 1 do
      if (Trim(R.Name) <> '') and SameText(R.Name, FSet.Records[j].Name) then
        Issue(Result, 0, Format(rsTheNameIsUsedTwice, [R.Name]));
    if Trim(R.Reference) = '' then
      Issue(Result, 1, Format(rsTheNameHasNoReference, [R.Name]));
  end;
  Pins := 0;
  Seen := TStringList.Create;
  try
    Seen.CaseSensitive := True;
    for i := 0 to FDoc.SheetCount - 1 do
    begin
      Sh := FDoc.Sheets[i];
      Grid := Sh.Snap.Grid;
      for j := 0 to Sh.Drawing.Count - 1 do
        if Sh.Drawing[j] is TDrawPin then
        begin
          P := Sh.Drawing[j] as TDrawPin;
          Inc(Pins);
          if P.Part >= FSet.Ppp then
            Issue(Result, 0, Format(rsPinBelongsToPartBut, [P.Number, P.Part + 1, FSet.Ppp]));
          if (Trim(P.Number) = '') and (P.Which <> 5) then
            Issue(Result, 1, Format(rsAPinHasNoNumber, [IfThen(P.Str <> '', ' named ' + P.Str, '')]));
          if (Grid > 0) and ((Abs(Frac(P.PointA.x / Grid)) > 0.0001) and (Abs(Frac(P.PointA.x / Grid)) < 0.9999) or
             (Abs(Frac(P.PointA.y / Grid)) > 0.0001) and (Abs(Frac(P.PointA.y / Grid)) < 0.9999)) then
          begin
            Inc(OffGrid);
            if OffGrid = 1 then
              FirstOff := P.Number;
          end;
          if (Trim(P.Number) <> '') and (P.Which <> 4) then
          begin
            Key := P.Number;
            if Seen.IndexOf(Key) >= 0 then
              Issue(Result, 1, Format(rsPinNumberIsUsedMore, [P.Number]))
            else
              Seen.Add(Key);
          end;
          { two pins on the same spot of the same part }
          for k := 0 to j - 1 do
            if Sh.Drawing[k] is TDrawPin then
            begin
              Q := Sh.Drawing[k] as TDrawPin;
              if (Q.Part = P.Part) and PointsClose(Q.PointA, P.PointA) then
                Issue(Result, 0, Format(rsPinsAndAreOnTop, [Q.Number, P.Number]));
            end;
        end;
    end;
    { a package with several parts should have pins in each part }
    if (FSet.Ppp > 1) and (Pins > 0) then
      for a := 0 to FSet.Ppp - 1 do
      begin
        b := PinCount(a);
        if b = 0 then
          Issue(Result, 1, Format(rsPartHasNoPins, [a + 1]));
      end;
  finally
    Seen.Free;
  end;
  if OffGrid = 1 then
    Issue(Result, 1, Format(rsPinIsNotOnThe, [FirstOff]))
  else if OffGrid > 1 then
    Issue(Result, 1, Format(rsPinsAreNotOnThe, [OffGrid, FirstOff]));
  if Pins = 0 then
    Issue(Result, 1, rsTheSymbolHasNoPins);
end;

{ ===========================================================================
  TSymbolEditor.Save  (function)
  Parameters:  none
  Returns:
    Int64 - the symbol's new id in the library
  Notes:
    Stores the symbol in the library, replacing the symbol it was opened from (its old drawing,
    names and fields are removed), and returns its new id. The editor's copy is unaffected by
    the library re-reading itself.
  =========================================================================== }
function TSymbolEditor.Save: Int64;
begin
  FSet.SymbolID := FSourceID;
  FSet.Ppp := Max(1, FSet.Ppp);
  if Assigned(FOnSaveBlob) then
    Result := FOnSaveBlob(FDoc.SaveToBlob, Self)
  else
    Result := FLib.StoreSet(FSet, FDoc);     // rereads the library; the editor's copy is unaffected
  FSourceID := Result;
  FSet.SymbolID := Result;
  FDirty := False;
end;

{ ===========================================================================
  TSymbolEditor.CopyTo  (function)
  Parameters:
    ADest: TSymbolLibrary - the library to store into
  Returns:
    Int64 - the new symbol's id in that library
  Notes:
    Stores the symbol in another library as a new symbol.
  =========================================================================== }
function TSymbolEditor.CopyTo(ADest: TSymbolLibrary): Int64;
var
  Tmp: TLibrarySymbolSet;
begin
  Tmp := CopySet(FSet, nil);
  try
    Tmp.SymbolID := -1;       // a new symbol in the other library
    Result := ADest.StoreSet(Tmp, FDoc);
  finally
    Tmp.Free;
  end;
end;

{ ===========================================================================
  TSymbolEditor.DeleteFromLibrary  (procedure)
  Parameters:  none
  Notes:
    Deletes the symbol this editor was opened from, with its names and fields, from its library.
  =========================================================================== }
procedure TSymbolEditor.DeleteFromLibrary;
begin
  if (FSourceID <> -1) and (FLib <> nil) then
  begin
    FLib.DeleteSet(FSourceID);
    FSourceID := -1;
    FSet.SymbolID := -1;
    FDirty := True;
  end;
end;

end.
