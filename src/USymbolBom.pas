// SPDX-License-Identifier: LGPL-2.1-or-later
{ USymbolBom - two small helpers for designs made before the parts library is in use: a check for symbols that share a reference, and a bill of materials made from
  the symbols placed (what a parts list is, but as a plain table, one column per attribute, to open in a spreadsheet).

  Duplicate references: every placed symbol (all sheets) whose reference is filled in (no "?" left) is grouped by its reference, ignoring case. A group of two or more
  is a duplicate, except that the parts of one package (the same symbol, each with its own part letter, e.g. U1A and U1B) share a reference on purpose. Two symbols of
  different names, or two with the same part, are a duplicate. Symbols still named like "R?" are not duplicates; they are counted as not numbered.

  Bill of materials: one row per kind of symbol: the same symbol, value, description and attribute values (the reference is not part of the kind). Columns: Item, Quantity, References,
  Value (the Name field), Symbol (its name in the library), Description, then one column per attribute heading (headings are shared by name, ignoring case, in the order they are met; hidden fields are left out). The parts of a package are
  counted once, as one reference; a reference that is used twice is counted once (it is a duplicate, and is reported). References are in natural order (R2 before R10).
  Hierarchical symbols are not followed: only the symbols of this design are listed.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit USymbolBom;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, UDrawTypes, UDrawingObjects, USymbols, UDesign;

type
  TSymbolRow = record
    Ref, Name, SymName, Description: String;      // Name is the Name field (the value, such as 200R); SymName the symbol's own name in the library
    Part, Sheet: Integer;         // Sheet is 1-based
    SheetName: String;
    Attrs: array of String;       // by the column of Survey.Attr (empty = none)
    Key: String;                  // what makes two rows the same kind of symbol
  end;

  { TSymbolSurvey }

  TSymbolSurvey = class
  private
    FRows: array of TSymbolRow;
    FAttrNames: TStringList;
    function GetCount: Integer;
    function GetRow(Index: Integer): TSymbolRow;
    function GetAttrCount: Integer;
    function GetAttrName(Index: Integer): String;
  public
    constructor Create;
    destructor Destroy; override;
    { reads every placed symbol of every sheet of the design }
    procedure Collect(Design: TDesignFile);
    { the duplicate references, one line each: the reference, how many symbols use it and where ("sheet 2 (Power), sheet 3"); '' when there are none }
    function DuplicateReport: String;
    { how many different references are used by more than one symbol, how many symbols have no number yet }
    function DuplicateCount: Integer;
    function UnnumberedCount: Integer;
    { the table as CSV (comma separated, quoted where needed, header line first), lines ended with EOL }
    function WriteCsv(const EOL: String = LineEnding): String;
    property Count: Integer read GetCount;
    property Rows[Index: Integer]: TSymbolRow read GetRow;
    property AttrCount: Integer read GetAttrCount;
    property AttrNames[Index: Integer]: String read GetAttrName;
  end;

type
  { one line of the symbol data report: a placed symbol or a symbol text }
  TSymbolDataRow = record
    Ref, Kind, SymName, SheetName: String;
    Sheet: Integer;               // 1-based
    Cells: array of String;       // by the report's heading number ('' = the object has no such field)
  end;

  { TSymbolDataReport: every symbol and symbol text of the design with all of its fields, for a spreadsheet or the report designer to come.
    The whole design is read twice: the first pass makes the list of every field heading used anywhere (the order they are first met, hidden fields included, headings shared
    by name ignoring case, a heading used twice by one object is numbered "Value (2)"), the second pass puts each object's values into the column of its heading, so that a
    value is always under its own heading whatever the other objects have. Columns: Reference, the headings, then Sheet, Sheet name, Kind (Symbol or Symbol text) and Symbol
    (the name in the library). Rows are in the natural order of the references (symbols without a reference last, in drawing order). }
  TSymbolDataReport = class
  private
    FRows: array of TSymbolDataRow;
    FHeads: TStringList;
    function GetCount: Integer;
    function GetRow(Index: Integer): TSymbolDataRow;
    function GetHeadCount: Integer;
    function GetHead(Index: Integer): String;
  public
    constructor Create;
    destructor Destroy; override;
    { reads the design in the two passes }
    procedure Collect(Design: TDesignFile);
    { the value of a heading for a row ('' when the object has no such field) }
    function Value(Row, Head: Integer): String;
    { the table as CSV (header line first), lines ended with EOL }
    function WriteCsv(const EOL: String = LineEnding): String;
    property Count: Integer read GetCount;
    property Rows[Index: Integer]: TSymbolDataRow read GetRow;
    property HeadCount: Integer read GetHeadCount;
    property Heads[Index: Integer]: String read GetHead;
  end;

{ compares references the way a person sorts them: letters first, then the number as a number (R2 before R10) }
function NaturalRefCompare(const A, B: String): Integer;

implementation

{ the sort for a TStringList: natural order of the references }
function CompareRefsNatural(List: TStringList; Index1, Index2: Integer): Integer;
begin
  Result := NaturalRefCompare(List[Index1], List[Index2]);
end;

{ the sort of the kinds: by the bytes of the key, so that "r" and "R" are two kinds and the order does not depend on a locale }
function CompareKinds(List: TStringList; Index1, Index2: Integer): Integer;
begin
  Result := CompareStr(List[Index1], List[Index2]);
end;

{ CSV text: quoted when it holds a comma, a quote or a line end, with the quotes in it doubled (RFC 4180) }
function CsvText(const S: String): String;
begin
  if (Pos(',', S) = 0) and (Pos('"', S) = 0) and (Pos(#10, S) = 0) and (Pos(#13, S) = 0) then
    Result := S
  else
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"';
end;

{ ===========================================================================
  NaturalRefCompare  (function)
  Parameters:
    const A, B: String - two references
  Returns:
    Integer - below zero, zero or above zero
  Notes:
    Splits both into runs of digits and runs of other characters and compares run by run: digit runs by value, the others ignoring case. A shorter reference that is the start of
    a longer one comes first.
  =========================================================================== }
function NaturalRefCompare(const A, B: String): Integer;
var
  i, j, a1, b1: Integer;
  NA, NB: QWord;
begin
  Result := 0;
  i := 1;
  j := 1;
  while (i <= Length(A)) and (j <= Length(B)) do
  begin
    if (A[i] in ['0'..'9']) and (B[j] in ['0'..'9']) then
    begin
      a1 := i;
      b1 := j;
      while (i <= Length(A)) and (A[i] in ['0'..'9']) do
        Inc(i);
      while (j <= Length(B)) and (B[j] in ['0'..'9']) do
        Inc(j);
      NA := StrToQWordDef(Copy(A, a1, i - a1), 0);
      NB := StrToQWordDef(Copy(B, b1, j - b1), 0);
      if NA <> NB then
      begin
        if NA < NB then
          Exit(-1)
        else
          Exit(1);
      end;
    end
    else
    begin
      Result := CompareText(A[i], B[j]);
      if Result <> 0 then
        Exit;
      Inc(i);
      Inc(j);
    end;
  end;
  Result := (Length(A) - i) - (Length(B) - j);
end;

constructor TSymbolSurvey.Create;
begin
  inherited Create;
  FAttrNames := TStringList.Create;
end;

destructor TSymbolSurvey.Destroy;
begin
  FAttrNames.Free;
  inherited Destroy;
end;

function TSymbolSurvey.GetCount: Integer;
begin
  Result := Length(FRows);
end;

function TSymbolSurvey.GetRow(Index: Integer): TSymbolRow;
begin
  Result := FRows[Index];
end;

function TSymbolSurvey.GetAttrCount: Integer;
begin
  Result := FAttrNames.Count;
end;

function TSymbolSurvey.GetAttrName(Index: Integer): String;
begin
  Result := FAttrNames[Index];
end;

{ ===========================================================================
  TSymbolSurvey.Collect  (procedure)
  Parameters:
    Design: TDesignFile - the design
  Notes:
    Reads the placed symbols of every sheet in drawing order. The kind of a symbol (Key) is its name, description and the visible attribute values, so symbols that only differ in
    their reference fall together. Fields are matched to columns by heading, ignoring case, as the parts list does.
  =========================================================================== }
procedure TSymbolSurvey.Collect(Design: TDesignFile);
var
  Sheet, i, k, j, N: Integer;
  Obj: TDrawingObject;
  M: TDrawMethod;
  Row: TSymbolRow;
  FieldName: String;
begin
  SetLength(FRows, 0);
  FAttrNames.Clear;
  for Sheet := 0 to Design.SheetCount - 1 do
    for i := 0 to Design.Sheets[Sheet].Drawing.Count - 1 do
    begin
      Obj := Design.Sheets[Sheet].Drawing[i];
      if Obj.GetType <> xMethodEx3 then
        Continue;
      M := Obj as TDrawMethod;
      Row := Default(TSymbolRow);
      Row.Ref := M.GetRef;
      Row.Name := M.GetName;
      Row.Part := M.Part;
      Row.Sheet := Sheet + 1;
      Row.SheetName := Design.Sheets[Sheet].SheetName;
      if M.GetSymbolData is TDesignFileSymbol then
      begin
        Row.Description := TDesignFileSymbol(M.GetSymbolData).Description;
        Row.SymName := TDesignFileSymbol(M.GetSymbolData).Name;
      end;
      for k := 2 to M.GetFieldCount - 1 do
      begin
        if M.Fields[k].FieldType = always_hidden then
          Continue;
        FieldName := M.GetFieldName(k);
        j := FAttrNames.IndexOf(FieldName);      { (a TStringList compares ignoring case unless told otherwise: the headings are shared by name, ignoring case) }
        if j < 0 then
          j := FAttrNames.Add(FieldName);
        if Length(Row.Attrs) <= j then
          SetLength(Row.Attrs, j + 1);
        Row.Attrs[j] := M.GetField(k);
      end;
      N := Length(FRows);
      SetLength(FRows, N + 1);
      FRows[N] := Row;
    end;
  { the kind of symbol: its attribute list padded to the same length for every row, so rows with fewer fields compare by what they have }
  for i := 0 to High(FRows) do
  begin
    SetLength(FRows[i].Attrs, FAttrNames.Count);
    FRows[i].Key := FRows[i].SymName + #1 + FRows[i].Name + #1 + FRows[i].Description;
    for j := 0 to FAttrNames.Count - 1 do
      FRows[i].Key := FRows[i].Key + #1 + FRows[i].Attrs[j];
  end;
end;

function IsNumbered(const Ref: String): Boolean;
begin
  Result := (Trim(Ref) <> '') and (Pos('?', Ref) = 0);
end;

{ ===========================================================================
  TSymbolSurvey.DuplicateReport  (function)
  Returns:
    String - one line per duplicated reference (sorted naturally), '' for none
  Notes:
    A reference used by several symbols is fine only when they are the parts of one package: the same symbol name and a part letter each of its own. The line reads
    "R3: 2 symbols (sheet 1, sheet 2 (Power))". References are compared ignoring case.
  =========================================================================== }
function TSymbolSurvey.DuplicateReport: String;
var
  Refs: TStringList;
  i, j, n: Integer;
  Group: TList;
  Dup: Boolean;
  Where: String;
  Tag: String;
begin
  Result := '';
  Refs := TStringList.Create;
  try
    Refs.CaseSensitive := False;
    Refs.Sorted := False;
    for i := 0 to High(FRows) do
      if IsNumbered(FRows[i].Ref) and (Refs.IndexOf(FRows[i].Ref) < 0) then
        Refs.Add(FRows[i].Ref);
    Refs.CustomSort(@CompareRefsNatural);
    for n := 0 to Refs.Count - 1 do
    begin
      Group := TList.Create;
      try
        for i := 0 to High(FRows) do
          if SameText(FRows[i].Ref, Refs[n]) then
            Group.Add(Pointer(PtrInt(i)));
        if Group.Count < 2 then
          Continue;
        Dup := False;
        for i := 0 to Group.Count - 1 do
          for j := i + 1 to Group.Count - 1 do
            if (FRows[PtrInt(Group[i])].SymName <> FRows[PtrInt(Group[j])].SymName) or (FRows[PtrInt(Group[i])].Part = FRows[PtrInt(Group[j])].Part) then
              Dup := True;
        if not Dup then
          Continue;
        Where := '';
        for i := 0 to Group.Count - 1 do
        begin
          if Where <> '' then
            Where := Where + ', ';
          Tag := 'sheet ' + IntToStr(FRows[PtrInt(Group[i])].Sheet);
          if FRows[PtrInt(Group[i])].SheetName <> '' then
            Tag := Tag + ' (' + FRows[PtrInt(Group[i])].SheetName + ')';
          Where := Where + Tag + ' ' + FRows[PtrInt(Group[i])].SymName;
        end;
        Result := Result + Refs[n] + ': ' + IntToStr(Group.Count) + ' symbols (' + Where + ')' + LineEnding;
      finally
        Group.Free;
      end;
    end;
  finally
    Refs.Free;
  end;
end;

function TSymbolSurvey.DuplicateCount: Integer;
var
  S: String;
  i: Integer;
begin
  S := DuplicateReport;
  Result := 0;
  for i := 1 to Length(S) do
    if S[i] = #10 then
      Inc(Result);
end;

function TSymbolSurvey.UnnumberedCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(FRows) do
    if not IsNumbered(FRows[i].Ref) then
      Inc(Result);
end;

{ ===========================================================================
  TSymbolSurvey.WriteCsv  (function)
  Parameters:
    const EOL: String - the line end
  Returns:
    String - the table
  Notes:
    Rows are the kinds of symbol (sorted by symbol, then value and the rest of the key). Quantity counts the distinct numbered references of the kind (parts of a package and a reference
    used twice count once) plus every symbol that is not numbered yet; References lists them in natural order, the unnumbered ones as they are. Every field is quoted when it holds
    a comma, a quote or a line end.
  =========================================================================== }
function TSymbolSurvey.WriteCsv(const EOL: String): String;
var
  Kinds: TStringList;
  i, j, k, Item, Qty: Integer;
  Refs: TStringList;
  First: Integer;
  Line: String;
begin
  Result := 'Item,Quantity,References,Value,Symbol,Description';
  for j := 0 to FAttrNames.Count - 1 do
    Result := Result + ',' + CsvText(FAttrNames[j]);
  Result := Result + EOL;
  Kinds := TStringList.Create;
  try
    Kinds.Sorted := False;
    Kinds.CaseSensitive := True;
    for i := 0 to High(FRows) do
      if Kinds.IndexOf(FRows[i].Key) < 0 then
        Kinds.Add(FRows[i].Key);
    Kinds.CustomSort(@CompareKinds);
    Item := 0;
    for k := 0 to Kinds.Count - 1 do
    begin
      Refs := TStringList.Create;
      try
        Refs.CaseSensitive := False;
        First := -1;
        Qty := 0;
        for i := 0 to High(FRows) do
        begin
          if FRows[i].Key <> Kinds[k] then
            Continue;
          if First < 0 then
            First := i;
          if IsNumbered(FRows[i].Ref) then
          begin
            if Refs.IndexOf(FRows[i].Ref) < 0 then
            begin
              Refs.Add(FRows[i].Ref);
              Inc(Qty);
            end;
          end
          else
          begin
            Refs.Add(FRows[i].Ref);
            Inc(Qty);
          end;
        end;
        Refs.CustomSort(@CompareRefsNatural);
        Inc(Item);
        Line := '';
        for i := 0 to Refs.Count - 1 do
        begin
          if i > 0 then
            Line := Line + ', ';
          Line := Line + Refs[i];
        end;
        Result := Result + IntToStr(Item) + ',' + IntToStr(Qty) + ',' + CsvText(Line) + ',' + CsvText(FRows[First].Name) + ',' + CsvText(FRows[First].SymName) + ',' +
          CsvText(FRows[First].Description);
        for j := 0 to FAttrNames.Count - 1 do
          Result := Result + ',' + CsvText(FRows[First].Attrs[j]);
        Result := Result + EOL;
      finally
        Refs.Free;
      end;
    end;
  finally
    Kinds.Free;
  end;
end;

{ ===========================================================================
  FieldHeadings  (procedure)
  Parameters:
    M: TDrawMethod - the symbol or symbol text
    out Heads: array of String - the heading of each field after the reference (field 1 on)
  Notes:
    The heading of a field is its description (Field N when that is empty). A heading met again in the same object, ignoring case, is numbered: "Value", "Value (2)".
  =========================================================================== }
procedure FieldHeadings(M: TDrawMethod; out Heads: TStringArray);
var
  k, n, c, j: Integer;
  H: String;
  Bases: array of String;
begin
  SetLength(Heads, 0);
  SetLength(Bases, 0);
  for k := 1 to M.GetFieldCount - 1 do
  begin
    H := Trim(M.GetFieldName(k));
    if H = '' then
      H := 'Field ' + IntToStr(k + 1);
    c := 1;
    for j := 0 to High(Bases) do
      if SameText(Bases[j], H) then
        Inc(c);
    n := Length(Heads);
    SetLength(Heads, n + 1);
    SetLength(Bases, n + 1);
    Bases[n] := H;
    if c > 1 then
      Heads[n] := H + ' (' + IntToStr(c) + ')'
    else
      Heads[n] := H;
  end;
end;

{ the sort of the report's rows: natural order of the references, no reference last; rows with equal references keep the drawing order (the sort is stable) }
function SymbolDataRowBefore(const A, B: TSymbolDataRow): Boolean;
begin
  if (A.Ref = '') <> (B.Ref = '') then
    Exit(B.Ref = '');
  Result := NaturalRefCompare(A.Ref, B.Ref) < 0;
end;

{ ===========================================================================
  TSymbolDataReport.Create  (constructor)
  Parameters:  none
  Notes:
    An empty report.
  =========================================================================== }
constructor TSymbolDataReport.Create;
begin
  inherited Create;
  FHeads := TStringList.Create;      { (compares ignoring case) }
end;

{ ===========================================================================
  TSymbolDataReport.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the heading list.
  =========================================================================== }
destructor TSymbolDataReport.Destroy;
begin
  FHeads.Free;
  inherited Destroy;
end;

function TSymbolDataReport.GetCount: Integer;
begin Result := Length(FRows); end;

function TSymbolDataReport.GetRow(Index: Integer): TSymbolDataRow;
begin Result := FRows[Index]; end;

function TSymbolDataReport.GetHeadCount: Integer;
begin Result := FHeads.Count; end;

function TSymbolDataReport.GetHead(Index: Integer): String;
begin Result := FHeads[Index]; end;

{ ===========================================================================
  TSymbolDataReport.Collect  (procedure)
  Parameters:
    Design: TDesignFile - the design
  Notes:
    Pass 1 goes over every sheet and every symbol and symbol text to list the headings; pass 2 goes over them again and writes each field into the column of its heading. The
    rows are then put in the order of their references. Hierarchical symbols are not followed.
  =========================================================================== }
procedure TSymbolDataReport.Collect(Design: TDesignFile);
var
  Pass, Sheet, i, j, n, Last: Integer;
  Obj: TDrawingObject;
  M: TDrawMethod;
  Hd: TStringArray;
  Row: TSymbolDataRow;
  Tmp: TSymbolDataRow;
  K, Col: Integer;
begin
  SetLength(FRows, 0);
  FHeads.Clear;
  for Pass := 1 to 2 do
    for Sheet := 0 to Design.SheetCount - 1 do
      for i := 0 to Design.Sheets[Sheet].Drawing.Count - 1 do
      begin
        Obj := Design.Sheets[Sheet].Drawing[i];
        if (Obj.GetType <> xMethodEx3) and (Obj.GetType <> xSymbolText) then
          Continue;
        M := Obj as TDrawMethod;
        FieldHeadings(M, Hd);
        if Pass = 1 then
        begin
          for j := 0 to High(Hd) do
            if FHeads.IndexOf(Hd[j]) < 0 then
              FHeads.Add(Hd[j]);
          Continue;
        end;
        Row := Default(TSymbolDataRow);
        Row.Ref := M.GetRef;
        Row.Sheet := Sheet + 1;
        Row.SheetName := Design.Sheets[Sheet].SheetName;
        if Obj.GetType = xSymbolText then
          Row.Kind := 'Symbol text'
        else
          Row.Kind := 'Symbol';
        if (Obj.GetType = xMethodEx3) and (M.GetSymbolData is TDesignFileSymbol) then
          Row.SymName := TDesignFileSymbol(M.GetSymbolData).Name;
        SetLength(Row.Cells, FHeads.Count);
        for j := 0 to High(Hd) do
        begin
          Col := FHeads.IndexOf(Hd[j]);
          K := j + 1;
          Row.Cells[Col] := M.GetField(K);
        end;
        n := Length(FRows);
        SetLength(FRows, n + 1);
        FRows[n] := Row;
      end;
  { a stable insertion sort by reference }
  for i := 1 to High(FRows) do
  begin
    Tmp := FRows[i];
    Last := i - 1;
    while (Last >= 0) and SymbolDataRowBefore(Tmp, FRows[Last]) do
    begin
      FRows[Last + 1] := FRows[Last];
      Dec(Last);
    end;
    FRows[Last + 1] := Tmp;
  end;
end;

{ ===========================================================================
  TSymbolDataReport.Value  (function)
  Parameters:
    Row: Integer - the row (0-based)
    Head: Integer - the heading (0-based)
  Returns:
    String - the value, '' when the object has no such field
  Notes:
    One cell of the table.
  =========================================================================== }
function TSymbolDataReport.Value(Row, Head: Integer): String;
begin
  if (Head < Length(FRows[Row].Cells)) then
    Result := FRows[Row].Cells[Head]
  else
    Result := '';
end;

{ ===========================================================================
  TSymbolDataReport.WriteCsv  (function)
  Parameters:
    const EOL: String - the line end
  Returns:
    String - the CSV text
  Notes:
    The header line, then one line per row: the reference, one value per heading (empty where the object has no such field), then sheet number, sheet name, kind and symbol.
    A value is quoted when it holds a comma, a quote or a line end.
  =========================================================================== }
function TSymbolDataReport.WriteCsv(const EOL: String): String;
var
  i, j: Integer;
begin
  Result := 'Reference';
  for j := 0 to FHeads.Count - 1 do
    Result := Result + ',' + CsvText(FHeads[j]);
  Result := Result + ',Sheet,Sheet name,Kind,Symbol' + EOL;
  for i := 0 to High(FRows) do
  begin
    Result := Result + CsvText(FRows[i].Ref);
    for j := 0 to FHeads.Count - 1 do
      Result := Result + ',' + CsvText(Value(i, j));
    Result := Result + ',' + IntToStr(FRows[i].Sheet) + ',' + CsvText(FRows[i].SheetName) + ',' + CsvText(FRows[i].Kind) + ',' + CsvText(FRows[i].SymName) + EOL;
  end;
end;

end.
