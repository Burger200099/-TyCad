// SPDX-License-Identifier: LGPL-2.1-or-later
{ Port of LibrarySQLite.* and the library parts of Symbol.cpp (CLibraryStoreNameSet,
  CLibraryStoreSymbol): reading and writing .TCLib symbol libraries.

  A .TCLib file is a SQLite database:
    Symbol    (SymbolID, Data)  Data = the symbol's drawing as TinyCAD XML (a BLOB)
    Name      (NameID, Name, SymbolID, Type, Reference, ppp, Description, ShowName, ShowRef, DefRotate)
    Attribute (AttributeID, NameID, AttName, AttValue, ShowAtt)
  One drawing (a "symbol set") can have several names (aliases), each with its own reference,
  description and parameters.

  Uses SQLite through FPC's sqlite3dyn unit (loaded at run time, so libsqlite3 / sqlite3.dll
  must be installed). The higher level SQLDB driver is deliberately not used: its memo-field
  handling re-encodes the XML blob.

  Differences from the C++ original:
  - Storing a set also deletes the old Symbol row. The C++ code removed the old Name and
    Attribute rows but left the superseded drawing behind as an orphan.
  - StoreSet re-reads the library afterwards (as ReRead does), so Sets/records obtained earlier
    must not be used afterwards.

  Original: Copyright 1994-2019 Matt Pyne, LGPL 2.1+. This port keeps that licence. }
unit ULibrary;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs, ctypes, sqlite3dyn, {$IFDEF WINDOWS}Windows,{$ENDIF} UDPoint, UDrawTypes, USymbols, UDesign;

type
  ELibraryError = class(Exception);

  { One name (alias) of a symbol: CLibraryStoreSymbol / CSymbolRecord }
  TLibraryRecord = class
  public
    Name, Reference, Description: String;
    NameType, RefType: Integer;
    NameID: Int64;                 // -1 when not stored yet
    Fields: array of TSymbolFieldDef;
    FieldsLoaded: Boolean;
    constructor Create;
  end;

  { One drawing plus its names (CLibraryStoreNameSet) }
  TLibrarySymbolSet = class
  private
    FRecords: TObjectList;
    function GetRecord(Index: Integer): TLibraryRecord;
  public
    SymbolID: Int64;               // FilePos; -1 when not stored yet
    Ppp: Integer;                  // parts per package
    Orientation: Integer;          // default rotation (DefRotate)
    constructor Create;
    destructor Destroy; override;
    function AddRecord: TLibraryRecord;
    function RecordCount: Integer;
    property Records[Index: Integer]: TLibraryRecord read GetRecord;
  end;

  TSymbolLibrary = class
  private
    FDb: Psqlite3;
    FFileName: String;
    FSets: TObjectList;
    function GetSet(Index: Integer): TLibrarySymbolSet;
    function Prepare(const SQL: String): Psqlite3_stmt;
    procedure ExecSQL(const SQL: String);
    procedure Fail(const What: String);
  public
    constructor Create;
    destructor Destroy; override;
    { Attach to an existing library file (CLibrarySQLite::Attach) }
    procedure Open(const AFileName: String);
    { Create a new, empty library file with the standard tables (CLibrarySQLite::Create) }
    procedure CreateNew(const AFileName: String);
    procedure Close;
    procedure Reread;
    function SetCount: Integer;
    property Sets[Index: Integer]: TLibrarySymbolSet read GetSet;
    function FindSet(SymbolID: Int64): TLibrarySymbolSet;
    { Load a record's parameters on demand }
    procedure LoadFields(Rec: TLibraryRecord);
    { Raw XML of a set's drawing; empty for a set that is not stored yet }
    function GetSymbolBlob(ASet: TLibrarySymbolSet): String;
    { Build a design symbol from one name of a set. Its resources are merged into Target's
      tables (as when placing a library symbol in a design). Nil when it cannot be loaded.
      The caller owns the result (e.g. hand it to Target.Options.AddSymbol). }
    function GetDesignSymbol(Target: TDesignSheet; ASet: TLibrarySymbolSet;
      RecIndex: Integer): TDesignFileSymbol;
    { Write a set and its drawing (CLibrarySQLite::Store); returns the new SymbolID }
    function StoreSet(ASet: TLibrarySymbolSet; Doc: TSymbolDocument): Int64;
    procedure DeleteSet(SymbolID: Int64);
    procedure Cleanup; // VACUUM
    property FileName: String read FFileName;
  end;

{ the CPU a Windows library (.dll) is built for: $014C (32-bit x86), $8664 (64-bit x64), $AA64 (ARM64), 0 when the file is missing or is not a PE file }
function PeMachine(const AFile: String): Word;
{ the problem of a library of this CPU (PeMachine) for a program of 32 or 64 bits, '' when there is none }
function CpuProblem(const AFile: String; AMachine: Word; AProgram64: Boolean): String;
{ what is wrong with the SQLite library file, '' when nothing is wrong that can be told from the file: missing, not a Windows library, or built for another CPU than this program }
function SqliteFileProblem(const AFile: String): String;
{ loads SQLite now (the libraries do it by themselves when first used): raises ELibraryError saying what is wrong when it cannot }
procedure EnsureSqlite;

implementation


uses UStrings;

const
  SQLITE_TRANSIENT_PTR = -1; // destructor "copy the data now"

{ ===========================================================================
  TLibraryRecord.Create  (constructor)
  Parameters:  none
  Notes:
    Creates an empty record (one named part of a symbol set).
  =========================================================================== }
constructor TLibraryRecord.Create;
begin
  inherited Create;
  NameID := -1;
  NameType := default_show;
  RefType := default_show;
  FieldsLoaded := False;
end;

{ ===========================================================================
  TLibrarySymbolSet.Create  (constructor)
  Parameters:  none
  Notes:
    Creates an empty set (a symbol and the records that name it).
  =========================================================================== }
constructor TLibrarySymbolSet.Create;
begin
  inherited Create;
  FRecords := TObjectList.Create(True);
  SymbolID := -1;
  Ppp := 1;
  Orientation := 0;
end;

{ ===========================================================================
  TLibrarySymbolSet.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the records.
  =========================================================================== }
destructor TLibrarySymbolSet.Destroy;
begin
  FRecords.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TLibrarySymbolSet.AddRecord  (function)
  Parameters:  none
  Returns:
    TLibraryRecord - the new record
  Notes:
    Adds an empty record to the set.
  =========================================================================== }
function TLibrarySymbolSet.AddRecord: TLibraryRecord;
begin
  Result := TLibraryRecord.Create;
  FRecords.Add(Result);
end;

{ ===========================================================================
  TLibrarySymbolSet.RecordCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    Number of records in the set.
  =========================================================================== }
function TLibrarySymbolSet.RecordCount: Integer;
begin
  Result := FRecords.Count;
end;

{ ===========================================================================
  TLibrarySymbolSet.GetRecord  (function)
  Parameters:
    Index: Integer - position
  Returns:
    TLibraryRecord - the record
  Notes:
    One record of the set.
  =========================================================================== }
function TLibrarySymbolSet.GetRecord(Index: Integer): TLibraryRecord;
begin
  Result := TLibraryRecord(FRecords[Index]);
end;

{ ---- TSymbolLibrary ---- }

var
  SqliteReady: Boolean = False;

{ ===========================================================================
  PeMachine  (function)
  Parameters:
    const AFile: String - text
  Returns:
    Word
  Notes:
    A 32-bit sqlite3.dll cannot be loaded by a 64-bit program (and the other way round) whatever
    folder it is in, and Windows only says it was not found.
  =========================================================================== }
function PeMachine(const AFile: String): Word;
var
  F: TFileStream;
  Sig: array[0..1] of Char;
  Off: LongWord;
  Pe: array[0..3] of Char;
begin
  Result := 0;
  try
    F := TFileStream.Create(AFile, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;
  try
    if F.Size < 64 then
      Exit;
    F.ReadBuffer(Sig, 2);
    if (Sig[0] <> 'M') or (Sig[1] <> 'Z') then
      Exit;
    F.Position := $3C;
    F.ReadBuffer(Off, 4);
    Off := LEtoN(Off);
    if Int64(Off) + 6 > F.Size then
      Exit;
    F.Position := Off;
    F.ReadBuffer(Pe, 4);
    if (Pe[0] <> 'P') or (Pe[1] <> 'E') or (Pe[2] <> #0) or (Pe[3] <> #0) then
      Exit;
    F.ReadBuffer(Result, 2);
    Result := LEtoN(Result);
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  CpuProblem  (function)
  Parameters:
    const AFile: String - text
    AMachine: Word
    AProgram64: Boolean - flag
  Returns:
    String
  Notes:
    Not a PE file ($0000), or a library built for the other CPU. Unknown machines are left to
    Windows to say.
  =========================================================================== }
function CpuProblem(const AFile: String; AMachine: Word; AProgram64: Boolean): String;
begin
  Result := '';
  if AMachine = 0 then
    Result := AFile + ' is not a Windows library (is it a web page, or a .def or .zip file?)'
  else if AProgram64 and (AMachine = $014C) then
    Result := AFile + ' is a 32-bit library but this program is 64-bit. Use the 64-bit sqlite3.dll (sqlite-dll-win-x64).'
  else if (not AProgram64) and (AMachine = $8664) then
    Result := AFile + ' is a 64-bit library but this program is 32-bit. Use the 32-bit sqlite3.dll (sqlite-dll-win-x86).';
end;

{ ===========================================================================
  SqliteFileProblem  (function)
  Parameters:
    const AFile: String - text
  Returns:
    String
  Notes:
    Missing, and (on Windows, where the file is a PE library) not a library or built for the
    other CPU than the program.
  =========================================================================== }
function SqliteFileProblem(const AFile: String): String;
begin
  Result := '';
  if not FileExists(AFile) then
  begin
    Result := ExtractFileName(AFile) + ' is not in ' + ExtractFilePath(AFile);
    Exit;
  end;
  {$IFDEF WINDOWS}
  Result := CpuProblem(AFile, PeMachine(AFile), SizeOf(Pointer) = 8);
  {$ENDIF}
end;

{ ===========================================================================
  EnsureSqlite  (procedure)
  Parameters:  none
  Notes:
    Loads the SQLite library the first time it is needed; raises a clear error when it is not
    installed.
  =========================================================================== }
procedure EnsureSqlite;
var
  Own, Problem, Detail: String;
  Err: Integer;
  Tried: Boolean;
begin
  if SqliteReady then
    Exit;
  Own := ExtractFilePath(ParamStr(0)) + SQLiteDefaultLibrary;
  Err := 0;
  Tried := False;
  if FileExists(Own) then
  begin
    Tried := True;
    if TryInitializeSqlite(Own) <> -1 then
    begin
      SqliteReady := True;
      Exit;
    end;
    {$IFDEF WINDOWS}
    Err := GetLastError;
    {$ENDIF}
  end;
  if TryInitializeSqlite('') <> -1 then
  begin
    SqliteReady := True;
    Exit;
  end;
  {$IFDEF UNIX}
  if TryInitializeSqlite('libsqlite3.so.0') <> -1 then
  begin
    SqliteReady := True;
    Exit;
  end;
  {$ENDIF}
  Problem := SqliteFileProblem(Own);
  if Problem <> '' then
    Detail := Problem
  else if Tried then
  begin
    Detail := Format(rsIsThereButCouldNot, [Own]);
    {$IFDEF WINDOWS}
    Detail := Format(rsWindowsErrorItMayNeed, [Detail, Err, Trim(SysErrorMessage(Err))]);
    {$ENDIF}
    Detail := Detail + '.';
  end
  else
    Detail := Format(rsWasNotFoundNextTo, [SQLiteDefaultLibrary, ExtractFilePath(ParamStr(0))]);
  raise ELibraryError.Create(Format(rsCannotLoadTheSQLiteLibrary, [Detail]));
end;

{ ===========================================================================
  TSymbolLibrary.Create  (constructor)
  Parameters:  none
  Notes:
    Creates a library object with nothing open.
  =========================================================================== }
constructor TSymbolLibrary.Create;
begin
  inherited Create;
  FSets := TObjectList.Create(True);
  FDb := nil;
end;

{ ===========================================================================
  TSymbolLibrary.Destroy  (destructor)
  Parameters:  none
  Notes:
    Closes the database and frees the sets.
  =========================================================================== }
destructor TSymbolLibrary.Destroy;
begin
  Close;
  FSets.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TSymbolLibrary.Fail  (procedure)
  Parameters:
    const What: String - what was being attempted
  Notes:
    Raises an error that includes SQLite's own message.
  =========================================================================== }
procedure TSymbolLibrary.Fail(const What: String);
var
  Msg: String;
begin
  if FDb <> nil then
    Msg := String(sqlite3_errmsg(FDb))
  else
    Msg := rsNoDatabase;
  raise ELibraryError.Create(What + ': ' + Msg);
end;

{ ===========================================================================
  TSymbolLibrary.GetSet  (function)
  Parameters:
    Index: Integer - position
  Returns:
    TLibrarySymbolSet - the set
  Notes:
    One symbol set of the open library.
  =========================================================================== }
function TSymbolLibrary.GetSet(Index: Integer): TLibrarySymbolSet;
begin
  Result := TLibrarySymbolSet(FSets[Index]);
end;

{ ===========================================================================
  TSymbolLibrary.SetCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    Number of symbol sets.
  =========================================================================== }
function TSymbolLibrary.SetCount: Integer;
begin
  Result := FSets.Count;
end;

{ ===========================================================================
  TSymbolLibrary.FindSet  (function)
  Parameters:
    SymbolID: Int64 - the id in the Symbol table
  Returns:
    TLibrarySymbolSet - the set, or nil
  Notes:
    Finds a set by its database id.
  =========================================================================== }
function TSymbolLibrary.FindSet(SymbolID: Int64): TLibrarySymbolSet;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to FSets.Count - 1 do
    if Sets[i].SymbolID = SymbolID then
    begin
      Result := Sets[i];
      Exit;
    end;
end;

{ ===========================================================================
  TSymbolLibrary.Prepare  (function)
  Parameters:
    const SQL: String - the statement text
  Returns:
    Psqlite3_stmt - the statement handle (finalise when done)
  Notes:
    Compiles an SQL statement; a failure raises an error.
  =========================================================================== }
function TSymbolLibrary.Prepare(const SQL: String): Psqlite3_stmt;
begin
  Result := nil;
  if sqlite3_prepare_v2(FDb, PChar(SQL), -1, @Result, nil) <> SQLITE_OK then
    Fail(Format(rsCannotPrepare, [SQL]));
end;

{ ===========================================================================
  TSymbolLibrary.ExecSQL  (procedure)
  Parameters:
    const SQL: String - the statement text
  Notes:
    Runs an SQL statement that returns no rows.
  =========================================================================== }
procedure TSymbolLibrary.ExecSQL(const SQL: String);
var
  St: Psqlite3_stmt;
begin
  St := Prepare(SQL);
  try
    if sqlite3_step(St) <> SQLITE_DONE then
      Fail(Format(rsCannotExecute, [SQL]));
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  ColText  (function)
  Parameters:
    St: Psqlite3_stmt - the statement
    Col: Integer - column number
  Returns:
    String - the column text (empty for NULL)
  Notes:
    Reads a result column as text.
  =========================================================================== }
function ColText(St: Psqlite3_stmt; Col: Integer): String;
var
  P: PChar;
  N: Integer;
begin
  P := PChar(sqlite3_column_text(St, Col));
  if P = nil then
    Result := ''
  else
  begin
    N := sqlite3_column_bytes(St, Col);
    SetString(Result, P, N);
  end;
end;

{ ===========================================================================
  TSymbolLibrary.Close  (procedure)
  Parameters:  none
  Notes:
    Closes the database and forgets the loaded sets.
  =========================================================================== }
procedure TSymbolLibrary.Close;
begin
  if FDb <> nil then
  begin
    sqlite3_close(FDb);
    FDb := nil;
  end;
  FSets.Clear;
end;

{ ===========================================================================
  TSymbolLibrary.Open  (procedure)
  Parameters:
    const AFileName: String - path of the library
  Notes:
    Opens a .TCLib (an SQLite file) and reads its sets, records and attributes. The raw symbol
    text is kept untouched so it can be written back unchanged.
  =========================================================================== }
procedure TSymbolLibrary.Open(const AFileName: String);
begin
  Close;
  EnsureSqlite;
  FFileName := AFileName;
  if sqlite3_open_v2(PChar(AFileName), @FDb, SQLITE_OPEN_READWRITE, nil) <> SQLITE_OK then
  begin
    try
      Fail(Format(rsCannotOpenLibrary, [AFileName]));
    finally
      Close;
    end;
  end;
  try
    Reread;
  except
    Close;
    raise;
  end;
end;

{ ===========================================================================
  CompareSets  (function)
  Parameters:
    A: Pointer - first set
    B: Pointer - second set
  Returns:
    Integer - negative, zero or positive as A sorts before, with or after B
  Notes:
    Ordering function for sets: by the name of their first record, as TinyCAD lists them.
  =========================================================================== }
function CompareSets(A, B: Pointer): Integer;
var
  X, Y: Int64;
begin
  X := TLibrarySymbolSet(A).SymbolID;
  Y := TLibrarySymbolSet(B).SymbolID;
  if X < Y then
    Result := -1 else if X > Y then
    Result := 1
  else
    Result := 0;
end;

{ ===========================================================================
  TSymbolLibrary.Reread  (procedure)
  Parameters:  none
  Notes:
    Reads the sets and records from the open database again (after a change).
  =========================================================================== }
procedure TSymbolLibrary.Reread;
var
  St: Psqlite3_stmt;
  SymID: Int64;
  ASet: TLibrarySymbolSet;
  Rec: TLibraryRecord;
begin
  FSets.Clear;
  St := Prepare('SELECT [NameID], [Name], [SymbolID], [Reference], [ppp], [Description], ' +
                '[ShowName], [ShowRef], [DefRotate] FROM [Name] WHERE [Type]=0 ORDER BY [NameID]');
  try
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      SymID := sqlite3_column_int64(St, 2);
      ASet := FindSet(SymID);
      if ASet = nil then
      begin
        ASet := TLibrarySymbolSet.Create;
        ASet.SymbolID := SymID;
        ASet.Ppp := sqlite3_column_int(St, 4) and $FF; // BYTE in the C++ code
        ASet.Orientation := sqlite3_column_int(St, 8);
        FSets.Add(ASet);
      end;
      Rec := ASet.AddRecord;
      Rec.NameID := sqlite3_column_int64(St, 0);
      Rec.Name := ColText(St, 1);
      Rec.Reference := ColText(St, 3);
      Rec.Description := ColText(St, 5);
      Rec.NameType := sqlite3_column_int(St, 6);
      Rec.RefType := sqlite3_column_int(St, 7);
    end;
  finally
    sqlite3_finalize(St);
  end;
  FSets.Sort(@CompareSets); // the C++ code keeps sets in a std::map keyed by SymbolID
end;

{ ===========================================================================
  TSymbolLibrary.LoadFields  (procedure)
  Parameters:
    Rec: TLibraryRecord - the record to fill in
  Notes:
    Loads the extra field values of a record from the Attribute table.
  =========================================================================== }
procedure TSymbolLibrary.LoadFields(Rec: TLibraryRecord);
var
  St: Psqlite3_stmt;
  F: TSymbolFieldDef;
begin
  if Rec.FieldsLoaded or (Rec.NameID < 0) then
    Exit;
  SetLength(Rec.Fields, 0);
  St := Prepare('SELECT [AttName], [AttValue], [ShowAtt] FROM [Attribute] WHERE [NameID]=? ORDER BY [AttributeID]');
  try
    sqlite3_bind_int64(St, 1, Rec.NameID);
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      F.Name := ColText(St, 0);
      F.Default := ColText(St, 1);
      F.FieldType := Cardinal(sqlite3_column_int(St, 2));
      F.Value := '';
      F.Pos := DPoint(0, 0);
      SetLength(Rec.Fields, Length(Rec.Fields) + 1);
      Rec.Fields[High(Rec.Fields)] := F;
    end;
  finally
    sqlite3_finalize(St);
  end;
  Rec.FieldsLoaded := True;
end;

{ ===========================================================================
  TSymbolLibrary.GetSymbolBlob  (function)
  Parameters:
    ASet: TLibrarySymbolSet - the set
  Returns:
    String - the stored text
  Notes:
    Reads a set's symbol drawing as stored text.
  =========================================================================== }
function TSymbolLibrary.GetSymbolBlob(ASet: TLibrarySymbolSet): String;
var
  St: Psqlite3_stmt;
  P: Pointer;
  N: Integer;
begin
  Result := '';
  if ASet.SymbolID = -1 then
    Exit;
  St := Prepare('SELECT [Data] FROM [Symbol] WHERE [SymbolID]=?');
  try
    sqlite3_bind_int64(St, 1, ASet.SymbolID);
    if sqlite3_step(St) = SQLITE_ROW then
    begin
      P := sqlite3_column_blob(St, 0);
      N := sqlite3_column_bytes(St, 0);
      if (P <> nil) and (N > 0) then
      begin
        SetLength(Result, N);
        Move(P^, Result[1], N);
      end;
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TSymbolLibrary.GetDesignSymbol  (function)
  Parameters:
    Target: TDesignSheet - the sheet the symbol will be used on
    ASet: TLibrarySymbolSet - the set
    RecIndex: Integer - which record of the set (which part name)
  Returns:
    TDesignFileSymbol - the symbol, or nil if it cannot be read
  Notes:
    Builds a symbol definition for placing on a sheet from a set's stored drawing and one
    record's name and fields.
  =========================================================================== }
function TSymbolLibrary.GetDesignSymbol(Target: TDesignSheet; ASet: TLibrarySymbolSet;
  RecIndex: Integer): TDesignFileSymbol;
var
  Rec: TLibraryRecord;
  Blob: String;
begin
  Result := nil;
  if ASet.SymbolID = -1 then
    Exit; // brand new symbol: nothing to load
  Rec := ASet.Records[RecIndex];
  LoadFields(Rec);
  Blob := GetSymbolBlob(ASet);
  Result := TDesignFileSymbol.Create(Target.Options);
  Result.Description := Rec.Description;
  Result.Name := Rec.Name;
  Result.Ppp := ASet.Ppp;
  Result.Reference := Rec.Reference;
  Result.NameType := Rec.NameType;
  Result.RefType := Rec.RefType;
  Result.Fields := Copy(Rec.Fields, 0, Length(Rec.Fields));
  if not LoadLibrarySymbolBlob(Target, Result, Blob) then
    FreeAndNil(Result);
end;

{ ===========================================================================
  TSymbolLibrary.CreateNew  (procedure)
  Parameters:
    const AFileName: String - path of the new file
  Notes:
    Creates a new empty library file with the TinyCAD tables.
  =========================================================================== }
procedure TSymbolLibrary.CreateNew(const AFileName: String);
begin
  Close;
  EnsureSqlite;
  FFileName := AFileName;
  if sqlite3_open_v2(PChar(AFileName), @FDb,
       SQLITE_OPEN_READWRITE or SQLITE_OPEN_CREATE, nil) <> SQLITE_OK then
    try
      Fail(Format(rsCannotCreateLibrary, [AFileName]));
    finally
      Close;
    end;
  ExecSQL('BEGIN TRANSACTION');
  try
    ExecSQL('CREATE TABLE [Name] ([NameID] INTEGER PRIMARY KEY,[Name] TEXT,[SymbolID] INTEGER,' +
            '[Type] INTEGER,[Reference] TEXT,[ppp] INTEGER,[Description] TEXT,[ShowName] INTEGER,' +
            '[ShowRef] INTEGER,[DefRotate] INTEGER)');
    ExecSQL('CREATE TABLE [Symbol] ([SymbolID] INTEGER PRIMARY KEY,[Data] TEXT)');
    ExecSQL('CREATE TABLE [Attribute] ([AttributeID] INTEGER PRIMARY KEY,[NameID] INTEGER,' +
            '[AttName] TEXT,[AttValue] TEXT,[ShowAtt] INTEGER)');
    ExecSQL('CREATE INDEX [idx_NameID] ON [Attribute] ( [NameID] )');
    ExecSQL('COMMIT TRANSACTION');
  except
    ExecSQL('ROLLBACK TRANSACTION');
    raise;
  end;
  Reread;
end;

{ ===========================================================================
  BindText  (procedure)
  Parameters:
    St: Psqlite3_stmt - the statement
    Idx: Integer - 1-based parameter number
    const S: String - the text
  Notes:
    Binds a text value to a statement parameter.
  =========================================================================== }
procedure BindText(St: Psqlite3_stmt; Idx: Integer; const S: String);
begin
  sqlite3_bind_text(St, Idx, PChar(S), Length(S), sqlite3_destructor_type(SQLITE_TRANSIENT_PTR));
end;

{ ===========================================================================
  TSymbolLibrary.StoreSet  (function)
  Parameters:
    ASet: TLibrarySymbolSet - the set (new, or an edited existing one)
    Doc: TSymbolDocument - the symbol document holding the drawing
  Returns:
    Int64 - the database id of the set
  Notes:
    Writes a symbol set (its drawing and records) to the library inside a transaction and
    returns its database id. A superseded drawing row is deleted, unlike TinyCAD which leaves it
    behind.
  =========================================================================== }
function TSymbolLibrary.StoreSet(ASet: TLibrarySymbolSet; Doc: TSymbolDocument): Int64;
var
  St: Psqlite3_stmt;
  Blob: String;
  OldID, NewID, NameID: Int64;
  i, j: Integer;
  Rec: TLibraryRecord;
  Fld: TSymbolFieldDef;
  Names: array of Int64;
  PpP, Orient: Integer;
begin
  Blob := Doc.SaveToBlob;
  OldID := ASet.SymbolID;
  PpP := ASet.Ppp;
  Orient := ASet.Orientation;
  ExecSQL('BEGIN TRANSACTION');
  try
    { the drawing first, so that it is guaranteed a new SymbolID }
    St := Prepare('INSERT INTO [Symbol] ( [Data] ) VALUES (?)');
    try
      if Length(Blob) > 0 then
        sqlite3_bind_blob(St, 1, @Blob[1], Length(Blob), sqlite3_destructor_type(SQLITE_TRANSIENT_PTR))
      else
        sqlite3_bind_zeroblob(St, 1, 0);
      if sqlite3_step(St) <> SQLITE_DONE then
        Fail(rsCannotStoreSymbolDrawing);
    finally
      sqlite3_finalize(St);
    end;
    NewID := sqlite3_last_insert_rowid(FDb);

    { remove the old names, their attributes and (unlike the C++ code) the old drawing }
    if OldID <> -1 then
    begin
      SetLength(Names, 0);
      St := Prepare('SELECT [NameID] FROM [Name] WHERE [SymbolID]=?');
      try
        sqlite3_bind_int64(St, 1, OldID);
        while sqlite3_step(St) = SQLITE_ROW do
        begin
          SetLength(Names, Length(Names) + 1);
          Names[High(Names)] := sqlite3_column_int64(St, 0);
        end;
      finally
        sqlite3_finalize(St);
      end;
      for i := 0 to High(Names) do
      begin
        St := Prepare('DELETE FROM [Attribute] WHERE [NameID]=?');
        try
          sqlite3_bind_int64(St, 1, Names[i]);
          sqlite3_step(St);
        finally
          sqlite3_finalize(St);
        end;
      end;
      St := Prepare('DELETE FROM [Name] WHERE [SymbolID]=?');
      try
        sqlite3_bind_int64(St, 1, OldID);
        sqlite3_step(St);
      finally
        sqlite3_finalize(St);
      end;
      St := Prepare('DELETE FROM [Symbol] WHERE [SymbolID]=?');
      try
        sqlite3_bind_int64(St, 1, OldID);
        sqlite3_step(St);
      finally
        sqlite3_finalize(St);
      end;
    end;

    for i := 0 to ASet.RecordCount - 1 do
    begin
      Rec := ASet.Records[i];
      St := Prepare('INSERT INTO [Name] ([Name], [SymbolID], [Type], [Reference], [ppp], ' +
                    '[Description], [ShowName], [ShowRef], [DefRotate]) VALUES (?,?,?,?,?,?,?,?,?)');
      try
        BindText(St, 1, Rec.Name);
        sqlite3_bind_int64(St, 2, NewID);
        sqlite3_bind_int(St, 3, 0);
        BindText(St, 4, Rec.Reference);
        sqlite3_bind_int(St, 5, PpP);
        BindText(St, 6, Rec.Description);
        sqlite3_bind_int(St, 7, Rec.NameType);
        sqlite3_bind_int(St, 8, Rec.RefType);
        sqlite3_bind_int(St, 9, Orient);
        if sqlite3_step(St) <> SQLITE_DONE then
          Fail(rsCannotStoreSymbolName);
      finally
        sqlite3_finalize(St);
      end;
      NameID := sqlite3_last_insert_rowid(FDb);
      for j := 0 to High(Rec.Fields) do
      begin
        Fld := Rec.Fields[j];
        St := Prepare('INSERT INTO [Attribute] ([NameID], [AttName], [AttValue], [ShowAtt]) VALUES (?,?,?,?)');
        try
          sqlite3_bind_int64(St, 1, NameID);
          BindText(St, 2, Fld.Name);
          BindText(St, 3, Fld.Default);
          sqlite3_bind_int(St, 4, Integer(Fld.FieldType));
          if sqlite3_step(St) <> SQLITE_DONE then
            Fail(rsCannotStoreSymbolAttribute);
        finally
          sqlite3_finalize(St);
        end;
      end;
    end;
    ExecSQL('COMMIT TRANSACTION');
  except
    ExecSQL('ROLLBACK TRANSACTION');
    raise;
  end;
  Result := NewID;
  Reread; // as the C++ code does; ASet may now be invalid if the library owned it
end;

{ ===========================================================================
  TSymbolLibrary.DeleteSet  (procedure)
  Parameters:
    SymbolID: Int64 - the set's database id
  Notes:
    Deletes a set and its records and attributes from the library.
  =========================================================================== }
procedure TSymbolLibrary.DeleteSet(SymbolID: Int64);
var
  St: Psqlite3_stmt;
  Names: array of Int64;
  i: Integer;
begin
  ExecSQL('BEGIN TRANSACTION');
  try
    St := Prepare('SELECT [NameID] FROM [Name] WHERE [SymbolID]=?');
    try
      sqlite3_bind_int64(St, 1, SymbolID);
      while sqlite3_step(St) = SQLITE_ROW do
      begin
        SetLength(Names, Length(Names) + 1);
        Names[High(Names)] := sqlite3_column_int64(St, 0);
      end;
    finally
      sqlite3_finalize(St);
    end;
    for i := 0 to High(Names) do
    begin
      St := Prepare('DELETE FROM [Attribute] WHERE [NameID]=?');
      try
        sqlite3_bind_int64(St, 1, Names[i]);
        sqlite3_step(St);
      finally
        sqlite3_finalize(St);
      end;
    end;
    St := Prepare('DELETE FROM [Name] WHERE [SymbolID]=?');
    try
      sqlite3_bind_int64(St, 1, SymbolID);
      sqlite3_step(St);
    finally
      sqlite3_finalize(St);
    end;
    St := Prepare('DELETE FROM [Symbol] WHERE [SymbolID]=?');
    try
      sqlite3_bind_int64(St, 1, SymbolID);
      sqlite3_step(St);
    finally
      sqlite3_finalize(St);
    end;
    ExecSQL('COMMIT TRANSACTION');
  except
    ExecSQL('ROLLBACK TRANSACTION');
    raise;
  end;
  Reread;
end;

{ ===========================================================================
  TSymbolLibrary.Cleanup  (procedure)
  Parameters:  none
  Notes:
    Compacts the library file (SQLite VACUUM), as TinyCAD's Cleanup does; the symbols are not
    changed.
  =========================================================================== }
procedure TSymbolLibrary.Cleanup;
begin
  ExecSQL('VACUUM');
end;

end.
