{ Test driver for the symbol editor's data layer.
    symedittest build <lib>                       create <lib> with three symbols (one part, a 4-part IC with an alias and a field, a 2-part heterogeneous op-amp)
    symedittest edit <lib> <name>                 open a symbol, add a pin, change its description, add an alias, save
    symedittest reopen <lib> <name>               open a symbol and print what the editor sees
    symedittest copyto <src> <name> <dst>         store a symbol of <src> into <dst> as a new symbol
    symedittest delete <lib> <name>               delete a symbol from the library
    symedittest validate                          build symbols with deliberate mistakes and print what the check reports
    symedittest parts <lib> <name>                change the number of parts of a symbol and save }
program symedittest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, UDPoint, UDrawTypes, UDrawingObjects, USymbols, UDesign, ULibrary, USymEdit;

{ ===========================================================================
  FindSetByName  (function)
  Parameters:
    L: TSymbolLibrary - the library
    const AName: String - the name to look for
  Returns:
    TLibrarySymbolSet - the set, or nil
  Notes:
    Finds the set that has a name.
  =========================================================================== }
function FindSetByName(L: TSymbolLibrary; const AName: String): TLibrarySymbolSet;
var
  i, j: Integer;
begin
  Result := nil;
  for i := 0 to L.SetCount - 1 do
    for j := 0 to L.Sets[i].RecordCount - 1 do
      if L.Sets[i].Records[j].Name = AName then Result := L.Sets[i];
end;

{ ===========================================================================
  DoBuild  (procedure)
  Parameters:
    const LibName: String - the library file to create
  Notes:
    Test mode: creates a library with a two pin symbol, a four-part IC with an alias and a
    field, and a two-part heterogeneous op-amp, and prints their ids.
  =========================================================================== }
procedure DoBuild(const LibName: String);
var
  L: TSymbolLibrary;
  E: TSymbolEditor;
  P: Integer;
  Id: Int64;
begin
  if FileExists(LibName) then DeleteFile(LibName);
  L := TSymbolLibrary.Create;
  E := TSymbolEditor.Create(L);
  try
    L.CreateNew(LibName);
    { 1: a plain two pin symbol }
    E.NewSymbol('R_TEST', 'R?', 'Test resistor', 1, False);
    E.AddPin(0, DPoint(0, 0), '1', '1', 0, 30, 0);
    E.AddPin(0, DPoint(0, 100), '2', '2', 1, 30, 0);
    WriteLn('VALID R_TEST ', Length(E.Validate));
    Id := E.Save;
    WriteLn('ID R_TEST ', Id);
    { 2: a four part IC with a shared drawing, an alias and an extra field }
    E.NewSymbol('QUAD_NAND', 'U?', 'Quad 2-input NAND', 4, False);
    for P := 0 to 3 do
    begin
      E.AddPin(P, DPoint(0, 0), 'A', IntToStr(P * 3 + 1), 2, 30, 0);
      E.AddPin(P, DPoint(0, 20), 'B', IntToStr(P * 3 + 2), 2, 30, 0);
      E.AddPin(P, DPoint(100, 10), 'Y', IntToStr(P * 3 + 3), 3, 30, 1);
    end;
    E.AddAlias('74HC00', 'U?', 'Quad NAND (HC)');
    E.SetField(0, 'Footprint', 'DIP14', 1);
    E.SetField(1, 'Footprint', 'SO14', 1);
    WriteLn('VALID QUAD_NAND ', Length(E.Validate));
    Id := E.Save;
    WriteLn('ID QUAD_NAND ', Id);
    { 3: two parts that are drawn differently }
    E.NewSymbol('OPAMP2', 'U?', 'Dual op-amp', 2, True);
    E.AddPin(0, DPoint(0, 0), '+', '3', 2, 30, 0);
    E.AddPin(0, DPoint(0, 20), '-', '2', 2, 30, 0);
    E.AddPin(0, DPoint(80, 10), 'OUT', '1', 3, 30, 0);
    E.AddPin(1, DPoint(0, 0), '+', '5', 2, 30, 0);
    E.AddPin(1, DPoint(0, 20), '-', '6', 2, 30, 0);
    E.AddPin(1, DPoint(80, 10), 'OUT', '7', 3, 30, 0);
    Id := E.Save;
    WriteLn('ID OPAMP2 ', Id);
    WriteLn('SETS ', L.SetCount);
  finally
    E.Free;
    L.Free;
  end;
end;

{ ===========================================================================
  DoReopen  (procedure)
  Parameters:
    const LibName: String - the library
    const AName: String - the symbol's name
  Notes:
    Test mode: opens a symbol in the editor and prints its parts, pin counts, names and fields.
  =========================================================================== }
procedure DoReopen(const LibName, AName: String);
var
  L: TSymbolLibrary;
  E: TSymbolEditor;
  S: TLibrarySymbolSet;
  i, j: Integer;
  R: TLibraryRecord;
begin
  L := TSymbolLibrary.Create;
  E := TSymbolEditor.Create(L);
  try
    L.Open(LibName);
    S := FindSetByName(L, AName);
    if S = nil then begin WriteLn('NOTFOUND'); Exit; end;
    E.OpenSet(S);
    WriteLn('PARTS ', E.PartCount, ' hetero=', Ord(E.Heterogeneous), ' sheets=', E.Doc.SheetCount, ' id=', E.SourceID);
    for i := 0 to E.PartCount - 1 do WriteLn('PINS part ', i, ' = ', E.PinCount(i));
    for i := 0 to E.LibrarySet.RecordCount - 1 do
    begin
      R := E.LibrarySet.Records[i];
      WriteLn('NAME ', R.Name, '|', R.Reference, '|', R.Description);
      for j := 0 to High(R.Fields) do WriteLn('FIELD ', R.Name, '|', R.Fields[j].Name, '|', R.Fields[j].Default, '|', R.Fields[j].FieldType);
    end;
  finally
    E.Free;
    L.Free;
  end;
end;

{ ===========================================================================
  DoEdit  (procedure)
  Parameters:
    const LibName: String - the library
    const AName: String - the symbol's name
  Notes:
    Test mode: opens a symbol, adds a pin, changes its description, adds an alias and saves.
  =========================================================================== }
procedure DoEdit(const LibName, AName: String);
var
  L: TSymbolLibrary;
  E: TSymbolEditor;
  S: TLibrarySymbolSet;
  Before, After: Int64;
begin
  L := TSymbolLibrary.Create;
  E := TSymbolEditor.Create(L);
  try
    L.Open(LibName);
    S := FindSetByName(L, AName);
    if S = nil then begin WriteLn('NOTFOUND'); Exit; end;
    Before := S.SymbolID;
    E.OpenSet(S);
    E.AddPin(0, DPoint(200, 0), 'EXTRA', '99', 0, 30, 0);
    E.LibrarySet.Records[0].Description := 'Edited description';
    E.AddAlias(AName + '_ALT', E.LibrarySet.Records[0].Reference, 'An alias');
    After := E.Save;
    WriteLn('IDS ', Before, ' ', After, ' sets=', L.SetCount);
  finally
    E.Free;
    L.Free;
  end;
end;

{ ===========================================================================
  DoParts  (procedure)
  Parameters:
    const LibName: String - the library
    const AName: String - the symbol's name
  Notes:
    Test mode: cuts a symbol down to two parts and saves.
  =========================================================================== }
procedure DoParts(const LibName, AName: String);
var
  L: TSymbolLibrary;
  E: TSymbolEditor;
  S: TLibrarySymbolSet;
begin
  L := TSymbolLibrary.Create;
  E := TSymbolEditor.Create(L);
  try
    L.Open(LibName);
    S := FindSetByName(L, AName);
    E.OpenSet(S);
    E.SetPartCount(2);
    WriteLn('ID ', E.Save);
  finally
    E.Free;
    L.Free;
  end;
end;

{ ===========================================================================
  DoCopyTo  (procedure)
  Parameters:
    const SrcName: String - the library to copy from
    const AName: String - the symbol's name
    const DstName: String - the library to copy into
  Notes:
    Test mode: stores a symbol of one library into another (creating it if needed).
  =========================================================================== }
procedure DoCopyTo(const SrcName, AName, DstName: String);
var
  A, B: TSymbolLibrary;
  E: TSymbolEditor;
  S: TLibrarySymbolSet;
begin
  A := TSymbolLibrary.Create;
  B := TSymbolLibrary.Create;
  E := TSymbolEditor.Create(A);
  try
    A.Open(SrcName);
    if not FileExists(DstName) then B.CreateNew(DstName) else B.Open(DstName);
    S := FindSetByName(A, AName);
    E.OpenSet(S);
    WriteLn('ID ', E.CopyTo(B), ' sets=', B.SetCount);
  finally
    E.Free; B.Free; A.Free;
  end;
end;

{ ===========================================================================
  DoDelete  (procedure)
  Parameters:
    const LibName: String - the library (a copy)
    const AName: String - the name
  Notes:
    Test mode: deletes one set from a library.
  =========================================================================== }
procedure DoDelete(const LibName, AName: String);
var
  L: TSymbolLibrary;
  E: TSymbolEditor;
  S: TLibrarySymbolSet;
begin
  L := TSymbolLibrary.Create;
  E := TSymbolEditor.Create(L);
  try
    L.Open(LibName);
    S := FindSetByName(L, AName);
    E.OpenSet(S);
    E.DeleteFromLibrary;
    WriteLn('SETS ', L.SetCount);
  finally
    E.Free; L.Free;
  end;
end;

{ ===========================================================================
  DoValidate  (procedure)
  Parameters:  none
  Notes:
    Test mode: builds symbols with deliberate mistakes and prints what the check reports for
    each.
  =========================================================================== }
procedure DoValidate;
var
  L: TSymbolLibrary;
  E: TSymbolEditor;
  Iss: TSymbolIssues;

{ ===========================================================================
  Show  (procedure)
  Parameters:
    const Title: String - label for the case
  Notes:
    Prints the check results for the symbol currently being edited.
  =========================================================================== }
procedure Show(const Title: String);
var
  k: Integer;
begin
  Iss := E.Validate;
  WriteLn('CASE ', Title);
  for k := 0 to High(Iss) do WriteLn('  ', Iss[k].Severity, ' ', Iss[k].Text);
end;
begin
  L := TSymbolLibrary.Create;
  E := TSymbolEditor.Create(L);
  try
    E.NewSymbol('GOOD', 'R?', 'fine', 1, False);
    E.AddPin(0, DPoint(0, 0), '1', '1', 0, 30, 0);
    E.AddPin(0, DPoint(0, 100), '2', '2', 1, 30, 0);
    Show('good');
    E.NewSymbol('', '', '', 1, False);
    E.AddPin(0, DPoint(0, 0), '1', '1', 0, 30, 0);
    Show('empty name and reference');
    E.NewSymbol('DUP', 'U?', '', 1, False);
    E.AddPin(0, DPoint(0, 0), 'A', '1', 0, 30, 0);
    E.AddPin(0, DPoint(0, 100), 'B', '1', 1, 30, 0);
    Show('duplicate pin number');
    E.NewSymbol('TOP', 'U?', '', 1, False);
    E.AddPin(0, DPoint(10, 10), 'A', '1', 0, 30, 0);
    E.AddPin(0, DPoint(10, 10), 'B', '2', 1, 30, 0);
    Show('pins on top of each other');
    E.NewSymbol('NONUM', 'U?', '', 1, False);
    E.AddPin(0, DPoint(0, 0), 'A', '', 0, 30, 0);
    Show('pin without a number');
    E.NewSymbol('OFFGRID', 'U?', '', 1, False);
    E.AddPin(0, DPoint(3, 7), 'A', '1', 0, 30, 0);
    Show('pin off the grid');
    E.NewSymbol('NOPINS', 'U?', '', 1, False);
    Show('no pins');
    E.NewSymbol('EMPTYPART', 'U?', '', 3, False);
    E.AddPin(0, DPoint(0, 0), 'A', '1', 0, 30, 0);
    Show('a part without pins');
    E.NewSymbol('DUPNAME', 'U?', '', 1, False);
    E.AddPin(0, DPoint(0, 0), 'A', '1', 0, 30, 0);
    E.AddAlias('DUPNAME', 'U?', '');
    Show('same name twice');
    E.NewSymbol('POWERDUP', 'U?', '', 2, False);
    E.AddPin(0, DPoint(0, 0), 'A', '1', 0, 30, 0);
    E.AddPin(0, DPoint(0, 100), 'GND', '7', 1, 30, 4);
    E.AddPin(1, DPoint(0, 0), 'B', '2', 0, 30, 0);
    E.AddPin(1, DPoint(0, 100), 'GND', '7', 1, 30, 4);
    Show('the same power pin number in two parts is fine');
  finally
    E.Free; L.Free;
  end;
end;

begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultSystemCodePage := CP_UTF8;
  if ParamCount < 1 then Halt(2);
  if ParamStr(1) = 'build' then DoBuild(ParamStr(2))
  else if ParamStr(1) = 'reopen' then DoReopen(ParamStr(2), ParamStr(3))
  else if ParamStr(1) = 'edit' then DoEdit(ParamStr(2), ParamStr(3))
  else if ParamStr(1) = 'parts' then DoParts(ParamStr(2), ParamStr(3))
  else if ParamStr(1) = 'copyto' then DoCopyTo(ParamStr(2), ParamStr(3), ParamStr(4))
  else if ParamStr(1) = 'delete' then DoDelete(ParamStr(2), ParamStr(3))
  else if ParamStr(1) = 'validate' then DoValidate;
end.
