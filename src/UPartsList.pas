// SPDX-License-Identifier: LGPL-2.1-or-later
{ Port of BOMGenerator.cpp / BOMGenerator.h (CBOMGenerator): the parts list (bill of materials).

  How a list is made:
    1. every placed symbol of the chosen sheet(s) becomes an entry: its text "name" (the symbol's
       name, followed - with "all attribute information" - by one comma / semicolon separated
       column per attribute) and its reference. Entries are kept in a sorted set, ordered by that
       text and then by the reference, so symbols that are the same part come out together, and a
       symbol with the same text and reference as one already in the set is dropped.
    2. the list is written one line per distinct text: the references of the symbols, the count,
       and the text. Three formats exist: the plain text file (references wrapped at 25 columns),
       CSV (a quoted reference list, the count, the text), and the "spreadsheet compatible" CSV
       (semicolons as separators).

  Hierarchical designs: with "include all hierarchical links", every placed hierarchical symbol
  loads its design (all its sheets, whatever "all sheets" says) and the symbols in it are listed
  too, with the path of symbols leading to them in front of their reference (H1_R2), as the
  netlist writes it. Without the option the placed designs are passed by.

  Not ported: "prefix symbol references with the
  sheet number" - TinyCAD stores that option but its generator never reads it, and this port is
  the same.

  Text is written as UTF-8 (TinyCAD wrote the program's ANSI code page). Entries are ordered by
  the bytes of the text, which is the same order as TinyCAD's for every character in the Basic
  Multilingual Plane.

  Original: Copyright 1994-2019 Matt Pyne, LGPL 2.1+. This port keeps that licence. }
unit UPartsList;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, UDrawTypes, UDrawingObjects, USymbols, UDesign, UNetList, UPartData;

const
  BOM_TEXT = 0;          // "Text file"
  BOM_CSV = 1;           // "CSV file"
  BOM_XLS = 2;           // "Spreadsheet compatible CSV file"
  BOM_PAD = 25;          // PARTSLIST_PAD: the width the references are wrapped at in a text list

type
  TBomOptions = record
    AllSheets: Boolean;     // every sheet, not just the one being shown
    AllAttrs: Boolean;      // add the attribute columns to each symbol's text
    PrefixSheet: Boolean;   // stored only (TinyCAD's generator never reads it)
    Hierarchical: Boolean;  // follow the placed hierarchical symbols and list the parts inside
    FileType: Integer;      // BOM_TEXT, BOM_CSV or BOM_XLS
    PartColumns: Boolean;   // add Manufacturer, Model number, Status and Fit columns when the design has placed parts of a parts library (TinyCAD's own columns are unchanged without part data)
  end;

  TBomEntry = record
    Name: String;     // symbol name plus attribute columns
    RefDes: String;   // the reference field as typed (GetRef: no part letter, so the parts of one package are one entry)
    Sheet: Integer;   // 1-based
    Method: TDrawMethod;
    Extra: String;    // the part columns (manufacturer, model number, status, fit) separated by #1; '' for a plain symbol; part of the sort key, so parts are grouped by (name, product)
    AttrCols: Integer; // how many attribute columns Name holds (a symbol with fewer fields gets no trailing ones; they are padded when the part columns follow)
    HasPart: Boolean;  // the symbol is a generic part of a parts library
  end;

  TBomList = class
  private
    FEntries: array of TBomEntry;
    FAttrs: TStringList;
    FMissingRef: Boolean;
    FFileName: String;
    FPartCols: Boolean;     // the part columns are written (asked for, and some entry is a placed part)
    FDelim: Char;
    FImports: TList;        // the designs read for hierarchical symbols; the entries point into them
    procedure ClearImports;
    procedure AddLevel(Level: Integer; Design: TDesignFile; Ctx: TImportFile; ActiveSheet: Integer;
      const Options: TBomOptions; Delim: Char; var FileCounter: Integer);
    function Compare(const A, B: TBomEntry): Integer;
    function ShownName(const E: TBomEntry): String;
    function PartExtra(M: TDrawMethod): String;
    function Find(const E: TBomEntry; out Index: Integer): Boolean;
    procedure Insert(const E: TBomEntry);
    function GetCount: Integer;
    function GetEntry(Index: Integer): TBomEntry;
    function GetAttr(Index: Integer): String;
    function GetAttrCount: Integer;
  public
    { why a hierarchical design could not be followed, one per line }
    ImportErrors: String;
    constructor Create;
    destructor Destroy; override;
    procedure Generate(Design: TDesignFile; ActiveSheet: Integer; const Options: TBomOptions;
      const AFileName: String);
    function WriteText(Csv: Boolean; const EOL: String = LineEnding): String;
    function WriteXls(const EOL: String = LineEnding): String;
    function WriteFor(FileType: Integer; const EOL: String = LineEnding): String;
    property Count: Integer read GetCount;
    property Entries[Index: Integer]: TBomEntry read GetEntry;
    property AttrCount: Integer read GetAttrCount;
    property Attrs[Index: Integer]: String read GetAttr;
    property MissingRef: Boolean read FMissingRef;
  end;

function EscapeForCSV(const S: String; Delimiter: Char): String;
{ the extension the file dialog offers for a format: .txt or .csv }
function BomExtension(FileType: Integer): String;
{ the file name TinyCAD proposes: the design's name with .txt, or output.txt when it has none }
function BomDefaultFileName(const DesignFile: String): String;
{ the name after the format was changed: everything after the last dot replaced by the new extension }
function BomChangeExtension(const FileName: String; FileType: Integer): String;

implementation


uses UStrings;

{ ===========================================================================
  EscapeForCSV  (function)
  Parameters:
    const S: String - text
    Delimiter: Char
  Returns:
    String
  Notes:
    As TinyCAD: the text is only wrapped in quotes; quotes inside it are not doubled.
  =========================================================================== }
function EscapeForCSV(const S: String; Delimiter: Char): String;
begin
  if Pos(Delimiter, S) = 0 then
    Result := S
  else
    Result := '"' + S + '"';
end;

{ ===========================================================================
  BomExtension  (function)
  Parameters:
    FileType: Integer - whole number
  Returns:
    String
  Notes:
    The extension of a parts list file; anything unknown gives ".txt".
  =========================================================================== }
function BomExtension(FileType: Integer): String;
begin
  if (FileType = BOM_CSV) or (FileType = BOM_XLS) then
    Result := '.csv'
  else
    Result := '.txt';
end;

{ ===========================================================================
  BomDefaultFileName  (function)
  Parameters:
    const DesignFile: String - text
  Returns:
    String
  Notes:
    As TinyCAD: the design's file name with its last extension replaced by .txt; a name without
    a dot (including an unsaved design) gives "output.txt".
  =========================================================================== }
function BomDefaultFileName(const DesignFile: String): String;
var
  P: Integer;
begin
  P := Length(DesignFile);
  while (P > 0) and (DesignFile[P] <> '.') do Dec(P);
  if P = 0 then
    Result := 'output.txt'
  else
    Result := Copy(DesignFile, 1, P - 1) + '.txt';
end;

{ ===========================================================================
  BomChangeExtension  (function)
  Parameters:
    const FileName: String - path of the file
    FileType: Integer - whole number
  Returns:
    String
  Notes:
    As TinyCAD's OnSelchangeFileType: only a name that has a dot is changed, and everything from
    the last dot on is replaced.
  =========================================================================== }
function BomChangeExtension(const FileName: String; FileType: Integer): String;
var
  P: Integer;
begin
  P := Length(FileName);
  while (P > 0) and (FileName[P] <> '.') do Dec(P);
  if P = 0 then
    Result := FileName
  else
    Result := Copy(FileName, 1, P - 1) + BomExtension(FileType);
end;

{ ===========================================================================
  TBomList.Create  (constructor)
  Parameters:  none
  Notes:
    Creates an empty list.
  =========================================================================== }
constructor TBomList.Create;
begin
  inherited Create;
  FAttrs := TStringList.Create;
end;

{ ===========================================================================
  TBomList.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the list.
  =========================================================================== }
destructor TBomList.Destroy;
begin
  FAttrs.Free;
  ClearImports;
  inherited Destroy;
end;

{ ===========================================================================
  TBomList.GetCount  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    Number of entries in the set.
  =========================================================================== }
function TBomList.GetCount: Integer;
begin
  Result := Length(FEntries);
end;

{ ===========================================================================
  TBomList.GetEntry  (function)
  Parameters:
    Index: Integer - zero-based index
  Returns:
    TBomEntry
  Notes:
    One entry of the set.
  =========================================================================== }
function TBomList.GetEntry(Index: Integer): TBomEntry;
begin
  Result := FEntries[Index];
end;

{ ===========================================================================
  TBomList.GetAttrCount  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    Number of attribute headings (Description and Package, then each further field name met).
  =========================================================================== }
function TBomList.GetAttrCount: Integer;
begin
  Result := FAttrs.Count;
end;

{ ===========================================================================
  TBomList.GetAttr  (function)
  Parameters:
    Index: Integer - zero-based index
  Returns:
    String
  Notes:
    One attribute heading.
  =========================================================================== }
function TBomList.GetAttr(Index: Integer): String;
begin
  Result := FAttrs[Index];
end;

{ ===========================================================================
  TBomList.Compare  (function)
  Parameters:
    const A: TBomEntry - a point, in design units
    const B: TBomEntry - a point, in design units
  Returns:
    Integer
  Notes:
    BomSort::operator(): by the text first, then by the reference. The part columns (empty for
    TinyCAD's own entries) come between them, so the parts of one product are listed together.
  =========================================================================== }
function TBomList.Compare(const A, B: TBomEntry): Integer;
begin
  Result := CompareStr(A.Name, B.Name);
  if Result = 0 then
    Result := CompareStr(A.Extra, B.Extra);
  if Result = 0 then
    Result := CompareStr(A.RefDes, B.RefDes);
end;

{ ===========================================================================
  TBomList.Find  (function)
  Parameters:
    const E: TBomEntry
    out Index: Integer - zero-based index (out: set by the call)
  Returns:
    Boolean
  Notes:
    Binary search in the sorted set.
  =========================================================================== }
function TBomList.Find(const E: TBomEntry; out Index: Integer): Boolean;
var
  Lo, Hi, Mid, C: Integer;
begin
  Lo := 0;
  Hi := Length(FEntries) - 1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    C := Compare(FEntries[Mid], E);
    if C = 0 then
    begin
      Index := Mid;
      Exit(True);
    end;
    if C < 0 then
      Lo := Mid + 1
    else
      Hi := Mid - 1;
  end;
  Index := Lo;
  Result := False;
end;

{ ===========================================================================
  TBomList.Insert  (procedure)
  Parameters:
    const E: TBomEntry
  Notes:
    std::set::insert: an entry equal to one already in the set (same text and reference) is not
    added, and the one already there stays.
  =========================================================================== }
procedure TBomList.Insert(const E: TBomEntry);
var
  Ix, i: Integer;
begin
  if Find(E, Ix) then
    Exit;
  SetLength(FEntries, Length(FEntries) + 1);
  for i := High(FEntries) downto Ix + 1 do FEntries[i] := FEntries[i - 1];
  FEntries[Ix] := E;
end;

{ ===========================================================================
  TBomList.PartExtra  (function)
  Parameters:
    M: TDrawMethod - a placed symbol
  Returns:
    String - manufacturer, model number, status and fit, separated by #1; '' for a plain symbol
  Notes:
    Status is 'resolved' (a product of a library was chosen), 'typed only' (manufacturer and/or
    model typed by hand: nothing known of its ratings) or 'unresolved' (neither). Fit is the
    verdict of a resolved product against the part's requirements (FitSummaryText, so a resolved
    part that no longer fits says so); empty for the other two.
  =========================================================================== }
function TBomList.PartExtra(M: TDrawMethod): String;
var
  Sym: TDesignFileSymbol;
  Status, Fit: String;
begin
  Result := '';
  if not (M.GetSymbolData is TDesignFileSymbol) then
    Exit;
  Sym := TDesignFileSymbol(M.GetSymbolData);
  if Sym.PartInfo.IsEmpty then
    Exit;
  Fit := '';
  if M.Product.UID <> '' then
  begin
    Status := 'resolved';
    Fit := FitSummaryText(CheckFit(Sym.PartInfo.Needs, M.Product.Haves));
  end
  else if (M.Product.Manufacturer <> '') or (M.Product.MPN <> '') then
    Status := 'typed only'
  else
    Status := 'unresolved';
  Result := M.Product.Manufacturer + #1 + M.Product.MPN + #1 + Status + #1 + Fit;
end;

{ ===========================================================================
  TBomList.ShownName  (function)
  Parameters:
    const E: TBomEntry
  Returns:
    String - the text of a list line: the name, with the part columns after the attribute columns
  Notes:
    Without part columns (none asked for, or no placed part in the design) this is TinyCAD's
    text unchanged. With them every line has all of them: the attribute columns are padded to the
    number of headings, then manufacturer, model number, status and fit follow.
  =========================================================================== }
function TBomList.ShownName(const E: TBomEntry): String;
var
  i, N: Integer;
  Part: String;
  Cols: array[0..3] of String;
begin
  Result := E.Name;
  if not FPartCols then
    Exit;
  for i := E.AttrCols to FAttrs.Count - 1 do
    Result := Result + FDelim;
  Part := E.Extra;
  for i := 0 to 3 do
  begin
    N := Pos(#1, Part);
    if N = 0 then
    begin
      Cols[i] := Part;
      Part := '';
    end
    else
    begin
      Cols[i] := Copy(Part, 1, N - 1);
      Part := Copy(Part, N + 1, MaxInt);
    end;
    Result := Result + FDelim + EscapeForCSV(Cols[i], FDelim);
  end;
end;

{ ===========================================================================
  TBomList.Generate  (procedure)
  Parameters:
    Design: TDesignFile - the design
    ActiveSheet: Integer - whole number
    const Options: TBomOptions
    const AFileName: String - path of the file
  Notes:
    GenerateBomForDesign for the top-level design. Collects every placed symbol of the sheet(s).
    With all attributes, each symbol's text is its name followed by the symbol's description,
    then its visible fields in the column of the field's heading (headings are shared by name,
    ignoring case, and grow as new names are met); a symbol with fewer fields gets no trailing
    columns for the others. Hidden fields (always hidden) are left out.
  =========================================================================== }
procedure TBomList.Generate(Design: TDesignFile; ActiveSheet: Integer; const Options: TBomOptions;
  const AFileName: String);
var
  Delim: Char;
  Root: TImportFile;
  Counter: Integer;
begin
  FAttrs.Clear;
  SetLength(FEntries, 0);
  ClearImports;
  FImports := TList.Create;
  ImportErrors := '';
  FMissingRef := False;
  FPartCols := False;
  FAttrs.Add('Description');
  FAttrs.Add('Package');
  FFileName := AFileName;
  if Options.FileType = BOM_XLS then
    Delim := ';'
  else
    Delim := ',';
  FDelim := Delim;
  Root := TImportFile.Create;
  try
    Root.Design := Design;
    Root.OwnsDesign := False;
    Root.FileIndex := 0;
    Root.ParentIndex := -1;
    Root.RefContext := '';
    Counter := 0;
    AddLevel(0, Design, Root, ActiveSheet, Options, Delim, Counter);
  finally
    Root.Free;
  end;
  if Options.PartColumns then
    for Counter := 0 to High(FEntries) do
      if FEntries[Counter].HasPart then
        FPartCols := True;
end;

{ ===========================================================================
  TBomList.ClearImports  (procedure)
  Parameters:  none
  Notes:
    Frees the designs read for hierarchical symbols (the entries point into them, so this is
    done when the list is made again or freed).
  =========================================================================== }
procedure TBomList.ClearImports;
var
  i: Integer;
begin
  if FImports = nil then
    Exit;
  for i := 0 to FImports.Count - 1 do TImportFile(FImports[i]).Free;
  FreeAndNil(FImports);
end;

{ ===========================================================================
  TBomList.AddLevel  (procedure)
  Parameters:
    Level: Integer - whole number
    Design: TDesignFile - the design
    Ctx: TImportFile
    ActiveSheet: Integer - whole number
    const Options: TBomOptions
    Delim: Char
    var FileCounter: Integer - whole number (in/out: changed by the call)
  Notes:
    GenerateBomForDesign(level, parent, file): lists the placed symbols of the sheet(s), and
    with Options.Hierarchical a placed hierarchical symbol loads its design and lists that first
    (every sheet of it). More than 100 levels stops the following; the C++ shows a message and
    then loops for ever on that symbol, which is not copied. A design that cannot be read is
    skipped and added to ImportErrors. Collects every placed symbol of the sheet(s). With all
    attributes, each symbol's text is its name followed by the symbol's description, then its
    visible fields in the column of the field's heading (headings are shared by name, ignoring
    case, and grow as new names are met); a symbol with fewer fields gets no trailing columns
    for the others. Hidden fields (always hidden) are left out. The reference listed is the
    symbol's reference with the path.
  =========================================================================== }
procedure TBomList.AddLevel(Level: Integer; Design: TDesignFile; Ctx: TImportFile; ActiveSheet: Integer;
  const Options: TBomOptions; Delim: Char; var FileCounter: Integer);
var
  Sheet, i, j, k: Integer;
  Obj: TDrawingObject;
  M: TDrawMethod;
  E: TBomEntry;
  Fields: array of String;
  FieldName: String;
  AllSheets: Boolean;
  Hs: TDrawHierarchicalSymbol;
  Child: TDesignFile;
  NewImp: TImportFile;
begin
  AllSheets := Options.AllSheets or (Level <> 0);
  if AllSheets then
    Sheet := 0
  else
    Sheet := ActiveSheet;
  if (Sheet < 0) or (Sheet >= Design.SheetCount) then
    Exit;
  repeat
    for i := 0 to Design.Sheets[Sheet].Drawing.Count - 1 do
    begin
      Obj := Design.Sheets[Sheet].Drawing[i];
      if (Obj.GetType = xHierarchicalSymbol) and Options.Hierarchical then
      begin
        Hs := Obj as TDrawHierarchicalSymbol;
        if Level > 100 then
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
          NewImp.ParentIndex := -1;
          if Ctx.RefContext = '' then
            NewImp.RefContext := Hs.GetRef
          else
            NewImp.RefContext := Ctx.RefContext + '/' + Hs.GetRef;
          FImports.Add(NewImp);
          AddLevel(Level + 1, Child, NewImp, ActiveSheet, Options, Delim, FileCounter);
        end;
        Continue;
      end;
      if Obj.GetType <> xMethodEx3 then
        Continue;
      M := Obj as TDrawMethod;
      E.Name := EscapeForCSV(M.GetName, Delim);
      if Options.AllAttrs then
      begin
        SetLength(Fields, 1);
        Fields[0] := (M.GetSymbolData as TDesignFileSymbol).Description;
        for k := 2 to M.GetFieldCount - 1 do
        begin
          if M.Fields[k].FieldType = always_hidden then
            Continue;
          FieldName := M.GetFieldName(k);
          j := 0;
          while (j < FAttrs.Count) and not SameText(FieldName, FAttrs[j]) do Inc(j);
          if j = FAttrs.Count then
            FAttrs.Add(FieldName);
          if Length(Fields) <= j then
            SetLength(Fields, j + 1);
          Fields[j] := M.GetField(k);
        end;
        for k := 0 to High(Fields) do E.Name := E.Name + Delim + EscapeForCSV(Fields[k], Delim);
        E.AttrCols := Length(Fields);
      end
      else
        E.AttrCols := 0;
      E.HasPart := (M.GetSymbolData is TDesignFileSymbol) and not TDesignFileSymbol(M.GetSymbolData).PartInfo.IsEmpty;
      if Options.PartColumns then
        E.Extra := PartExtra(M)
      else
        E.Extra := '';
      E.RefDes := TNetList.GetReferencePath(M, Ctx);
      E.Sheet := Sheet + 1;
      E.Method := M;
      Insert(E);
    end;
    Inc(Sheet);
  until (not AllSheets) or (Sheet >= Design.SheetCount);
end;

{ ===========================================================================
  TBomList.WriteText  (function)
  Parameters:
    Csv: Boolean - flag
    const EOL: String - text
  Returns:
    String
  Notes:
    WriteToFile. Text: a heading, then for each distinct text its references wrapped at 25
    columns, padded, the count and the text. CSV: a heading line (Reference, Quantity, Name and
    every attribute heading), then a quoted reference list, the count and the text. Also sets
    MissingRef when any symbol still has the reference its symbol was defined with (for example
    "U?").
  =========================================================================== }
function TBomList.WriteText(Csv: Boolean; const EOL: String): String;
var
  Out: String;
  Xpos, Pieces, ix, i: Integer;
  LastRef, LastName, Ref, Nm: String;

  procedure XInc(Amount: Integer);
  begin
    Xpos := Xpos + Amount;
    if Xpos >= BOM_PAD then
    begin
      Out := Out + EOL;
      Xpos := Amount;
    end;
  end;

  procedure EndLine(const AName: String);
  begin
    if Csv then
      Out := Out + '",' + Format('%3d', [Pieces]) + ',' + AName + EOL
    else
    begin
      while Xpos < BOM_PAD do
      begin
        Out := Out + ' ';
        Inc(Xpos);
      end;
      Out := Out + '   ' + Format('%3d', [Pieces]) + '   ' + AName + EOL;
      Xpos := 0;
    end;
  end;

begin
  FMissingRef := False;
  Out := '';
  if Csv then
  begin
    Out := 'Reference,Quantity,Name';
    for i := 0 to FAttrs.Count - 1 do Out := Out + ',' + FAttrs[i];
    if FPartCols then
      Out := Out + ',Manufacturer,Model number,Status,Fit';
    Out := Out + EOL;
  end
  else
    Out := '====+  Parts List for ' + FFileName + '  +====' + EOL + EOL;

  LastRef := '';
  LastName := '';
  Xpos := 0;
  Pieces := 0;
  for ix := 0 to High(FEntries) do
  begin
    Nm := ShownName(FEntries[ix]);
    if (Nm <> LastName) and (LastName <> '') then
    begin
      EndLine(LastName);
      Pieces := 0;
    end;
    Ref := FEntries[ix].RefDes;
    if Ref <> LastRef then
    begin
      if Csv then
      begin
        if Pieces = 0 then
          Out := Out + '"'
        else
          Out := Out + ',';
      end
      else
      begin
        if (Xpos <> BOM_PAD - 1) and (Xpos <> 0) then
        begin
          XInc(1);
          Out := Out + ',';
        end;
        XInc(Length(Ref));
      end;
      Out := Out + Ref;
      Inc(Pieces);
    end;
    if Ref = (FEntries[ix].Method.GetSymbolData as TDesignFileSymbol).Reference then
      FMissingRef := True;
    LastRef := Ref;
    LastName := Nm;
  end;
  if Pieces > 0 then
    EndLine(LastName);
  Result := Out;
end;

{ ===========================================================================
  TBomList.WriteXls  (function)
  Parameters:
    const EOL: String - text
  Returns:
    String
  Notes:
    WriteToXls, the semicolon separated file for spreadsheets: a heading line, then for each
    distinct text its comma separated references, the count and the text. Also sets MissingRef.
  =========================================================================== }
function TBomList.WriteXls(const EOL: String): String;
var
  Out: String;
  Pieces, ix, i: Integer;
  LastRef, LastName, Ref, Nm: String;
begin
  FMissingRef := False;
  Out := 'Reference;Quantity;Name';
  for i := 0 to FAttrs.Count - 1 do Out := Out + ';' + EscapeForCSV(FAttrs[i], ';');
  if FPartCols then
    Out := Out + ';Manufacturer;Model number;Status;Fit';
  Out := Out + EOL;
  LastRef := '';
  LastName := '';
  Pieces := 0;
  for ix := 0 to High(FEntries) do
  begin
    Nm := ShownName(FEntries[ix]);
    if (Nm <> LastName) and (LastName <> '') then
    begin
      Out := Out + ';' + IntToStr(Pieces) + ';' + LastName + EOL;
      Pieces := 0;
    end;
    Ref := FEntries[ix].RefDes;
    if Ref <> LastRef then
    begin
      if Pieces > 0 then
        Out := Out + ',';
      Out := Out + Ref;
      Inc(Pieces);
    end;
    if Ref = (FEntries[ix].Method.GetSymbolData as TDesignFileSymbol).Reference then
      FMissingRef := True;
    LastRef := Ref;
    LastName := Nm;
  end;
  if Pieces > 0 then
    Out := Out + ';' + IntToStr(Pieces) + ';' + LastName + EOL;
  Result := Out;
end;

{ ===========================================================================
  TBomList.WriteFor  (function)
  Parameters:
    FileType: Integer - whole number
    const EOL: String - text
  Returns:
    String
  Notes:
    Picks the writer as TinyCAD's OnSpecialBom does: the spreadsheet format has its own writer;
    the others share one, with CSV on for BOM_CSV.
  =========================================================================== }
function TBomList.WriteFor(FileType: Integer; const EOL: String): String;
begin
  if FileType = BOM_XLS then
    Result := WriteXls(EOL)
  else
    Result := WriteText(FileType = BOM_CSV, EOL);
end;

end.
