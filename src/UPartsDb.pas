{ UPartsDb - reads a TyCAD parts database ("TCParts", see docs/parts_schema.sql and docs/parts_design_storage.md).

  NOT a TinyCAD library: the file says so (FormatInfo.TinyCADCompatible = 0) and TinyCAD cannot open it. SQLite is used through FPC's sqlite3dyn, loaded only when
  a parts file is opened (EnsureSqlite of ULibrary), as the symbol libraries do.

  Opening follows the rules at the top of docs/parts_upgrade.py:
    version = current : opened as is;   version < current : <file>.v<old>.bak is copied first, then each step old -> old+1 runs in one transaction that also sets
    FormatInfo.SchemaVersion, PRAGMA user_version and adds a SchemaHistory row (a failing step is rolled back and the file stays at the version it had);
    version > current, or Format not 'TyCAD-Parts' (a TinyCAD .TCLib, say) : refused, the file is not written.

  What is read: the library's name and GUID, the class tree, the generic parts (name, class, GUID, description), a part's icon (the PNG of the size nearest to the
  wanted one), its required ratings, and the products that can be chosen for it with the verdict of the fit check (view ProductFitSummary of the schema).

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UPartsDb;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, ctypes, sqlite3dyn, ULibrary, UPartData, UPartsSchema;

const
  PARTS_SCHEMA_CURRENT = 1;      // the schema version this program knows (docs/parts_upgrade.py CURRENT: keep both in step)

type
  EPartsError = class(Exception);

  TPartClassInfo = record
    ID, ParentID: Int64;           // ParentID 0 for a root
    Name, Description: String;
    Abstract: Boolean;
  end;

  TFieldInfo = record
    ID, ClassID: Int64;
    DeclaredBy, Name, FieldType, Unit_, EnumValues, Description: String;
    Required, FromParent: Boolean;      // FromParent: declared by an ancestor of the class asked about
  end;

  TPartInfo = record
    ID: Int64;
    UID, Name, Description, ClassName, RefPrefix, Status, Revision, Modified: String;
    ClassID: Int64;
  end;

  TPartRating = record
    ID, ObjectID: Int64;                                 // RatingID; ObjectID 0 = the whole part
    Quantity, Unit_, Condition, ObjectName: String;      // ObjectName '' = the whole part
    HasMin, HasTyp, HasMax: Boolean;
    Min, Typ, Max: Double;
  end;

  TQuantityInfo = record
    Name, Unit_, Sense, Description: String;             // Sense: min (a product must be at least as much), max (at most), match (equal)
  end;

  TObjectRef = record
    ID: Int64;
    Name, Designator, Kind, Description: String;
    ParentID, KindID: Int64;                            // ParentID 0 = directly in the part
    Sort: Integer;
  end;

  TKindInfo = record
    ID: Int64;
    Name: String;
  end;

  TProductInfo = record
    ID: Int64;
    UID, Manufacturer, MPN, Description, Verdict: String;      // Verdict: does_not_fit, fits_oversized, fits, no_requirements (for the part asked about)
    Undersized, Missing, Mismatch, Oversized: Integer;
  end;

  TProductRow = record
    ID, ClassID: Int64;
    UID, ClassName, Manufacturer, MPN, Series, Description, Status, Revision, Modified: String;
  end;

  TValueRow = record
    ObjectID, FieldID: Int64;                              // ObjectID 0 = a field of the part's class
    ObjectName, FieldName, FieldType, Unit_, EnumValues, DeclaredBy, ValueText: String;
    Required, HasValue: Boolean;
  end;

  TProductImportResult = record
    ProductsAdded, ProductsUpdated, RatingsAdded, RatingsUpdated, Suggestions: Integer;
  end;

  TStringRow = array of String;
  TStringRows = array of TStringRow;

  TSymbolRow = record
    ID: Int64;
    Standard, Purpose, Name: String;
    Bytes: Integer;
    IsDefault: Boolean;
  end;

  TInt64Array = array of Int64;
  TSymbolRowArray = array of TSymbolRow;
  TValueRowArray = array of TValueRow;
  TProductRowArray = array of TProductRow;
  TFieldInfoArray = array of TFieldInfo;
  TQuantityInfoArray = array of TQuantityInfo;
  TObjectRefArray = array of TObjectRef;
  TKindInfoArray = array of TKindInfo;
  TPartRatingArray = array of TPartRating;
  TProductInfoArray = array of TProductInfo;

  TPartsLibrary = class
  private
    FDb: Psqlite3;
    FBatch: Integer;             // > 0 while an import runs: its edits share one transaction (BeginTx / CommitTx / RollbackTx do nothing then)
    FFileName: String;
    FSchemaVersion: Integer;
    FLibraryName, FLibraryUID, FLibraryDescription, FLibraryAuthor: String;
    FClasses: array of TPartClassInfo;
    FParts: array of TPartInfo;
    function Prepare(const SQL: String): Psqlite3_stmt;
    procedure Exec(const SQL: String);
    function QueryInt(const SQL: String): Int64;
    procedure Touch;
    procedure Mutate(const Steps: array of String);
    function RevisionAfter(PartIndex: Integer): String;
    function NextRevision(const Rev: String): String;
    procedure CheckSymbolInfo(const AStandard, APurpose: String);
    procedure BeginTx;
    procedure CommitTx;
    procedure RollbackTx;
    procedure RunWithBlob(const Sql, Blob: String);
    function FieldValueText(const FieldType: String; ValueNum: Double; const ValueText: String): String;
    procedure CheckProduct(ProductID, ClassID: Int64; const AManufacturer, AMPN, AStatus: String);
    function ProductAppliesSql(const AAppliesTo: String): String;
    function QueryText(const SQL: String): String;
    function RatingValuesSql(const AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double; out QUnit: String): String;
    function RatingObjectSql(PartID, ObjectID: Int64): String;
    function BadInheritance: Int64;
    procedure ClassTransaction(const Steps: array of String);
    function FieldNameTaken(AClassID: Int64; const AName: String; AExceptField: Int64): Boolean;
    procedure LoadAll;
    function GetPart(Index: Integer): TPartInfo;
    function GetClass(Index: Integer): TPartClassInfo;
  public
    destructor Destroy; override;
    procedure Open(const AFileName: String);
    procedure Close;
    { reads the library details, classes and parts from the file again (it was changed through another connection) }
    procedure Reload;
    function PartCount: Integer;
    function ClassCount: Integer;
    function FindPart(const UID: String): Integer;
    { the PNG (the bytes) of the part's icon whose size is nearest to Wanted; '' when the part has none; ActualSize is the size of the one found }
    function GlyphPng(PartID: Int64; Wanted: Integer; out ActualSize: Integer): String;
    { the glyph rows of a part: one PNG per square size }
    procedure SetGlyph(PartID: Int64; Size: Integer; const Png: String);
    procedure ClearGlyphs(PartID: Int64);
    function GlyphSizeList(PartID: Int64): TInt64Array;
    { the part's schematic symbol as TinyCAD XML (the BaseDefault one, else the first of purpose 'schematic'); '' when it has none }
    function SymbolXml(PartID: Int64): String;
    function Ratings(PartID: Int64): TPartRatingArray;
    procedure CheckObject(PartID, ObjectID, ParentID, KindID: Int64; const AName: String);
    function ObjectParentSql(ParentID: Int64): String;
    { the quantities that can be rated (name, its one unit, how a product is judged) and the child objects of a part a requirement can apply to }
    function Quantities: TQuantityInfoArray;
    function PartObjects(PartID: Int64): TObjectRefArray;
    function ObjectKinds(PartID: Int64): TKindInfoArray;
    function KindIDOfName(const AName: String): Int64;
    function ObjectSubtreeCount(ObjectID: Int64): Integer;
    function Products(PartID: Int64): TProductInfoArray;
    { --- products (the catalog items a generic part can be satisfied by) --- }
    function ProductRows: TProductRowArray;
    { --- the schematic symbols of a part (the drawing is TinyCAD symbol XML); the first schematic one becomes the default; every change raises the part's Revision --- }
    { --- bulk products: CSV text with a header row; columns Manufacturer, MPN (required), Series, Class, Status, Description, Part, Preferred, Quantity, Unit, Condition, AppliesTo, Min,
        Typ, Max in any order; all or nothing --- }
    function ImportProductsCsv(const Text: String): TProductImportResult;
    function ExportProductsCsv: String;
    { reads everything again (another connection changed the file) }
    procedure Reread;
    function SymbolRows(PartID: Int64): TSymbolRowArray;
    function SymbolDrawing(SymbolID: Int64): String;
    function SymbolPartID(SymbolID: Int64): Int64;
    function AddSymbol(PartID: Int64; const AStandard, APurpose, AName, ABlob: String): Int64;
    procedure UpdateSymbolDrawing(SymbolID: Int64; const ABlob: String);
    procedure UpdateSymbolInfo(SymbolID: Int64; const AStandard, APurpose, AName: String);
    procedure SetDefaultSymbol(PartID, SymbolID: Int64);
    procedure DeleteSymbol(SymbolID: Int64);
    { --- the values of fields: of the part (its class's fields) and of its child objects (their kinds' fields) --- }
    function FieldValues(PartID: Int64): TValueRowArray;
    procedure SetFieldValue(PartID, ObjectID, FieldID: Int64; const AValue: String);
    function ProductRatings(ProductID: Int64): TPartRatingArray;
    function AppliesToChoices(ClassID: Int64): TStringDynArray;
    function SuggestionState(PartID, ProductID: Int64): Integer;
    procedure SetSuggestion(PartID, ProductID: Int64; State: Integer);
    { manufacturer + model number are unique (any case); the class must not be abstract; every change raises the product's Revision and stamps Modified. Raise EPartsError when refused }
    function AddProduct(ClassID: Int64; const AManufacturer, AMPN, ASeries, ADescription, AStatus: String): Int64;
    procedure UpdateProduct(ProductID, ClassID: Int64; const AManufacturer, AMPN, ASeries, ADescription, AStatus: String);
    procedure DeleteProduct(ProductID: Int64);
    { ratings of a product: AAppliesTo '' = the whole product, an object's name, or 'kind:Contact'; the value rules are those of AddRating }
    function AddProductRating(ProductID: Int64; const AAppliesTo, AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double): Int64;
    procedure UpdateProductRating(RatingID: Int64; const AAppliesTo, AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double);
    procedure DeleteProductRating(RatingID: Int64);
    function PartCopyOf(PartIndex: Integer): TPartCopy;
    { --- editing (each call is one transaction; the part list is read again afterwards, so the indexes of Parts can change) --- }
    { requirements of a part: ObjectID 0 = the whole part. AUnit '' takes the quantity's unit; any other must be it. At least one of min / typ / max, and min <= typ <= max.
      The part's Revision goes up by one and Modified is stamped, as for any change of the part. Raise EPartsError when refused (nothing changes) }
    function AddRating(PartID, ObjectID: Int64; const AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double): Int64;
    procedure UpdateRating(RatingID, ObjectID: Int64; const AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double);
    procedure DeleteRating(RatingID: Int64);
    { child objects of a part (terminals, poles, channels ...): the kind must be one the part's class allows, the name is unique in the part, the parent is another object of the part
      (never the object itself or one below it); the part's Revision goes up. Deleting takes the objects below with it and is refused while a symbol pin, outline or 3D terminal uses them }
    function AddObject(PartID, ParentID, KindID: Int64; const AName, ADesignator, ADescription: String; ASort: Integer): Int64;
    procedure UpdateObject(ObjectID, ParentID, KindID: Int64; const AName, ADesignator, ADescription: String; ASort: Integer);
    procedure DeleteObject(ObjectID: Int64);
    { a new generic part of a (non abstract) class; returns its PartID. Raises EPartsError when the name is empty or the class has a part of that name already }
    function AddPart(const AName: String; AClassID: Int64; const ARefPrefix, ADescription: String): Int64;
    { changes name, reference letters, description and status ('active', 'obsolete', 'preview', 'custom') of a part; its Revision goes up by one and Modified is stamped }
    procedure UpdatePart(PartID: Int64; const AName, ARefPrefix, ADescription, AStatus: String);
    { a full copy of a part (values, child objects with their values, requirements, links, symbols with their pins, icons, tags, rules, suggested products) under a new name and GUID; returns its PartID }
    function DuplicatePart(PartID: Int64; const NewName: String): Int64;
    { how many products are listed as suitable for the part (PartProduct); deleting the part removes those suggestions, the products stay }
    function SuggestionCount(PartID: Int64): Integer;
    { deletes a part with everything that belongs to it, and the suggestions and rules that point at it }
    procedure DeletePart(PartID: Int64);
    { the name, description and author of the library (LibraryInfo) }
    procedure SetLibraryInfo(const AName, ADescription, AAuthor: String);
    function PartIndexOfID(PartID: Int64): Integer;
    { --- classes and their fields (the class tree editor) --- }
    function ClassIndexOfID(ClassID: Int64): Integer;
    function ClassPartCount(ClassID: Int64): Integer;
    function ClassProductCount(ClassID: Int64): Integer;
    { the whole field set of a class: the ancestors' fields from the root down (FromParent = True), then its own }
    function ClassFieldList(ClassID: Int64): TFieldInfoArray;
    function FieldValueCount(FieldID: Int64): Integer;
    { a new class under a parent (0 = a root); returns its ClassID }
    function AddClass(const AName: String; AParentID: Int64; AAbstract: Boolean; const ADescription: String): Int64;
    { name, parent (moves the class with its subclasses), abstract flag and description }
    procedure UpdateClass(AClassID: Int64; const AName: String; AParentID: Int64; AAbstract: Boolean; const ADescription: String);
    { refused while the class has subclasses, parts, products or rules that name it }
    procedure DeleteClass(AClassID: Int64);
    function AddField(AClassID: Int64; const AName, AType, AUnit, AEnum: String; ARequired: Boolean; const ADescription: String): Int64;
    procedure UpdateField(AFieldID: Int64; const AName, AType, AUnit, AEnum: String; ARequired: Boolean; const ADescription: String);
    procedure DeleteField(AFieldID: Int64);
    function ProductChoiceOf(ProductID: Int64): TProductChoice;
    property Parts[Index: Integer]: TPartInfo read GetPart;
    property Classes[Index: Integer]: TPartClassInfo read GetClass;
    property SchemaVersion: Integer read FSchemaVersion;
    property LibraryName: String read FLibraryName;
    property LibraryUID: String read FLibraryUID;
    property LibraryDescription: String read FLibraryDescription;
    property LibraryAuthor: String read FLibraryAuthor;
    property FileName: String read FFileName;
  end;

{ brings the file at Path up to version Current by running Steps[v - 1] (the SQL text of the step v -> v+1, statements separated by semicolons) for each version v
  it is behind; returns the version the file has afterwards. The rules are in the unit's header; Current and Steps are parameters so the machinery can be tested
  before a real step exists. Raises EPartsError when the file is newer, not ours, or a step fails (that step is undone and the backup is kept). }
function UpgradePartsFile(const Path: String; Current: Integer; const Steps: array of String): Integer;

{ makes a new, empty parts file at Path (which must not exist): the schema of this program's version, the starting classes, fields, child kinds and rating
  quantities, FormatInfo, LibraryInfo with a new GUID and no parts or products. Raises EPartsError (and leaves no file) when it cannot. }
procedure CreatePartsFile(const Path, LibName, Description, Author: String);

implementation


uses UStrings;

{ ===========================================================================
  ColText  (function)
  Parameters:
    St: Psqlite3_stmt - the statement
    Col: Integer - column number
  Returns:
    String - the column as text, empty for NULL
  Notes:
    Reads a result column as text (also a number).
  =========================================================================== }
function ColText(St: Psqlite3_stmt; Col: Integer): String;
var
  P: PChar;
begin
  P := PChar(sqlite3_column_text(St, Col));
  if P = nil then
    Result := ''
  else
    SetString(Result, P, sqlite3_column_bytes(St, Col));
end;

{ ===========================================================================
  OpenDb  (function)
  Parameters:
    const Path: String - the file
  Returns:
    Psqlite3 - the open database (the caller closes it)
  Notes:
    Opens an existing file (never creates one) and raises EPartsError with SQLite's message when it cannot.
  =========================================================================== }
function OpenDb(const Path: String): Psqlite3;
begin
  Result := nil;
  EnsureSqlite;
  if not FileExists(Path) then
    raise EPartsError.Create(Format(rsThePartsFileDoesNot, [Path]));
  if sqlite3_open_v2(PChar(Path), @Result, SQLITE_OPEN_READWRITE, nil) <> SQLITE_OK then
  begin
    sqlite3_close(Result);
    raise EPartsError.Create(Format(rsCannotOpenThePartsFile, [Path]));
  end;
end;

{ ===========================================================================
  DbExec  (procedure)
  Parameters:
    Db: Psqlite3 - the database
    const SQL: String - one or more statements
  Notes:
    Runs statements that return no rows; raises EPartsError with SQLite's message on failure.
  =========================================================================== }
procedure DbExec(Db: Psqlite3; const SQL: String);
var
  Err: PChar;
  Msg: String;
begin
  Err := nil;
  if sqlite3_exec(Db, PChar(SQL), nil, nil, @Err) <> SQLITE_OK then
  begin
    if Err <> nil then
      Msg := String(Err)
    else
      Msg := rsUnknownError;
    sqlite3_free(Err);
    raise EPartsError.Create(Msg);
  end;
end;

{ ===========================================================================
  FormatAndVersion  (procedure)
  Parameters:
    Db: Psqlite3 - the open database
    out Version: Integer - SchemaVersion of FormatInfo
  Notes:
    Checks the file is a TyCAD parts file (a table FormatInfo whose Format is 'TyCAD-Parts'); a TinyCAD library or any other database is refused.
  =========================================================================== }
procedure FormatAndVersion(Db: Psqlite3; out Version: Integer);
var
  St: Psqlite3_stmt;
begin
  St := nil;
  if sqlite3_prepare_v2(Db, 'select Format, SchemaVersion from FormatInfo', -1, @St, nil) <> SQLITE_OK then
    raise EPartsError.Create(rsThisIsNotATyCAD);
  try
    if (sqlite3_step(St) <> SQLITE_ROW) or (ColText(St, 0) <> 'TyCAD-Parts') then
      raise EPartsError.Create(rsThisIsNotATyCAD);
    Version := sqlite3_column_int(St, 0 + 1);
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  UpgradePartsFile  (function)
  Parameters:
    const Path: String - the file
    Current: Integer - the version wanted
    const Steps: array of String - Steps[v - 1] is the SQL of the step v -> v + 1
  Returns:
    Integer - the version the file has afterwards
  Notes:
    Follows the rules in the unit header: untouched when already current; refuses a newer file and a file that is not ours (without writing); checks every
    step exists before touching anything; copies <file>.v<old>.bak; runs each step in one transaction that also writes FormatInfo, PRAGMA user_version and
    SchemaHistory; a failing step is rolled back and reported, the steps already done stay.
  =========================================================================== }
function UpgradePartsFile(const Path: String; Current: Integer; const Steps: array of String): Integer;
var
  Db: Psqlite3;
  V, K: Integer;
  Src, Dst: TFileStream;
begin
  Db := OpenDb(Path);
  try
    FormatAndVersion(Db, V);
    Result := V;
    if V = Current then
      Exit;
    if V > Current then
      raise EPartsError.CreateFmt(rsThePartsFileIsVersion, [V, Current]);
    for K := V to Current - 1 do
      if (K - 1 > High(Steps)) or (K - 1 < 0) then
        raise EPartsError.CreateFmt(rsNoUpgradeStepFromVersion, [K]);
  finally
    sqlite3_close(Db);
  end;
  Src := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  try
    Dst := TFileStream.Create(Format('%s.v%d.bak', [Path, V]), fmCreate);
    try
      Dst.CopyFrom(Src, 0);
    finally
      Dst.Free;
    end;
  finally
    Src.Free;
  end;
  Db := OpenDb(Path);
  try
    for K := V to Current - 1 do
    begin
      DbExec(Db, 'BEGIN');
      try
        DbExec(Db, Steps[K - 1]);
        DbExec(Db, Format('update FormatInfo set SchemaVersion=%d', [K + 1]));
        DbExec(Db, Format('insert into SchemaHistory values (%d,%d,datetime(''now''),''TyCAD'','''')', [K, K + 1]));
        DbExec(Db, Format('PRAGMA user_version=%d', [K + 1]));
        DbExec(Db, 'COMMIT');
      except
        on E: Exception do
        begin
          try
            DbExec(Db, 'ROLLBACK');
          except
          end;
          raise EPartsError.CreateFmt(rsStepFailedAndWasUndone, [K, K + 1, E.Message, Path, V]);
        end;
      end;
      Result := K + 1;
    end;
  finally
    sqlite3_close(Db);
  end;
end;

{ ===========================================================================
  TPartsLibrary.Destroy  (destructor)
  Parameters:  none
  Notes:
    Closes the file.
  =========================================================================== }
destructor TPartsLibrary.Destroy;
begin
  Close;
  inherited Destroy;
end;

{ ===========================================================================
  TPartsLibrary.Prepare  (function)
  Parameters:
    const SQL: String - the statement
  Returns:
    Psqlite3_stmt - the statement (finalise when done)
  Notes:
    Compiles a statement; a failure raises EPartsError with SQLite's message.
  =========================================================================== }
function TPartsLibrary.Prepare(const SQL: String): Psqlite3_stmt;
begin
  Result := nil;
  if sqlite3_prepare_v2(FDb, PChar(SQL), -1, @Result, nil) <> SQLITE_OK then
    raise EPartsError.Create(rsCannotReadThePartsFile + String(sqlite3_errmsg(FDb)));
end;

{ ===========================================================================
  TPartsLibrary.Exec  (procedure)
  Parameters:
    const SQL: String - the statement
  Notes:
    Runs a statement that returns no rows.
  =========================================================================== }
procedure TPartsLibrary.Exec(const SQL: String);
begin
  DbExec(FDb, SQL);
end;

{ ===========================================================================
  TPartsLibrary.Open  (procedure)
  Parameters:
    const AFileName: String - the parts file
  Notes:
    Opens the file by the rules in the unit header (upgrading it when it is older), turns foreign keys on and reads the library's name and GUID, the class
    tree and the list of parts (sorted by class name, then part name, ignoring case). Raises EPartsError when the file cannot be used.
  =========================================================================== }
procedure TPartsLibrary.Open(const AFileName: String);
begin
  Close;
  FSchemaVersion := UpgradePartsFile(AFileName, PARTS_SCHEMA_CURRENT, []);
  FDb := OpenDb(AFileName);
  FFileName := AFileName;
  try
    Exec('PRAGMA foreign_keys=ON');
    LoadAll;
  except
    Close;
    raise;
  end;
end;

{ ===========================================================================
  TPartsLibrary.Close  (procedure)
  Parameters:  none
  Notes:
    Closes the file and forgets what was read.
  =========================================================================== }
procedure TPartsLibrary.Close;
begin
  if FDb <> nil then
    sqlite3_close(FDb);
  FDb := nil;
  FFileName := '';
  SetLength(FClasses, 0);
  SetLength(FParts, 0);
end;

{ ===========================================================================
  TPartsLibrary.Reload  (procedure)
  Notes:
    Reads everything again from the open file, so changes made through another connection (the library editor's) show.
  =========================================================================== }
procedure TPartsLibrary.Reload;
begin
  if FDb <> nil then
    LoadAll;
end;

{ ===========================================================================
  TPartsLibrary.LoadAll  (procedure)
  Parameters:  none
  Notes:
    Reads LibraryInfo, the class tree and the parts into memory.
  =========================================================================== }
procedure TPartsLibrary.LoadAll;
var
  St: Psqlite3_stmt;
  N: Integer;
begin
  FLibraryName := '';
  FLibraryUID := '';
  FLibraryDescription := '';
  FLibraryAuthor := '';
  St := Prepare('select Name, LibraryUID, coalesce(Description, ''''), coalesce(Author, '''') from LibraryInfo limit 1');
  try
    if sqlite3_step(St) = SQLITE_ROW then
    begin
      FLibraryName := ColText(St, 0);
      FLibraryUID := ColText(St, 1);
      FLibraryDescription := ColText(St, 2);
      FLibraryAuthor := ColText(St, 3);
    end;
  finally
    sqlite3_finalize(St);
  end;
  SetLength(FClasses, 0);
  St := Prepare('select ClassID, coalesce(ParentID, 0), Name, Abstract, coalesce(Description, '''') from PartClass order by ClassID');
  try
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      N := Length(FClasses);
      SetLength(FClasses, N + 1);
      FClasses[N].ID := sqlite3_column_int64(St, 0);
      FClasses[N].ParentID := sqlite3_column_int64(St, 1);
      FClasses[N].Name := ColText(St, 2);
      FClasses[N].Abstract := sqlite3_column_int(St, 3) <> 0;
      FClasses[N].Description := ColText(St, 4);
    end;
  finally
    sqlite3_finalize(St);
  end;
  SetLength(FParts, 0);
  St := Prepare('select p.PartID, p.UID, p.Name, coalesce(p.Description, ''''), c.Name, p.ClassID, coalesce(p.RefPrefix, ''''), p.Status, coalesce(p.Revision, ''''), coalesce(p.Modified, '''') from Part p join PartClass c using(ClassID) ' +
                'order by lower(c.Name), lower(p.Name)');
  try
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      N := Length(FParts);
      SetLength(FParts, N + 1);
      FParts[N].ID := sqlite3_column_int64(St, 0);
      FParts[N].UID := ColText(St, 1);
      FParts[N].Name := ColText(St, 2);
      FParts[N].Description := ColText(St, 3);
      FParts[N].ClassName := ColText(St, 4);
      FParts[N].ClassID := sqlite3_column_int64(St, 5);
      FParts[N].RefPrefix := ColText(St, 6);
      FParts[N].Status := ColText(St, 7);
      FParts[N].Revision := ColText(St, 8);
      FParts[N].Modified := ColText(St, 9);
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

function TPartsLibrary.GetPart(Index: Integer): TPartInfo;
begin
  Result := FParts[Index];
end;

function TPartsLibrary.GetClass(Index: Integer): TPartClassInfo;
begin
  Result := FClasses[Index];
end;

function TPartsLibrary.PartCount: Integer;
begin
  Result := Length(FParts);
end;

function TPartsLibrary.ClassCount: Integer;
begin
  Result := Length(FClasses);
end;

{ ===========================================================================
  TPartsLibrary.FindPart  (function)
  Parameters:
    const UID: String - the part's GUID
  Returns:
    Integer - the index in Parts, -1 when there is none
  Notes:
    Finds a part by its GUID (how a placed part finds the library part again).
  =========================================================================== }
function TPartsLibrary.FindPart(const UID: String): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FParts) do
    if SameText(FParts[i].UID, UID) then
      Exit(i);
end;

{ ===========================================================================
  TPartsLibrary.GlyphPng  (function)
  Parameters:
    PartID: Int64 - the part
    Wanted: Integer - the size in pixels the caller would like
    out ActualSize: Integer - the size of the image returned (0 when none)
  Returns:
    String - the PNG file's bytes, '' when the part has no icon
  Notes:
    Takes the size nearest to Wanted; at equal distance the larger one (it scales down better).
  =========================================================================== }
function TPartsLibrary.GlyphPng(PartID: Int64; Wanted: Integer; out ActualSize: Integer): String;
var
  St: Psqlite3_stmt;
  P: Pointer;
begin
  Result := '';
  ActualSize := 0;
  St := Prepare('select Size, Png from PartGlyph where PartID=? order by abs(Size - ?), Size desc limit 1');
  try
    sqlite3_bind_int64(St, 1, PartID);
    sqlite3_bind_int(St, 2, Wanted);
    if sqlite3_step(St) = SQLITE_ROW then
    begin
      ActualSize := sqlite3_column_int(St, 0);
      P := sqlite3_column_blob(St, 1);
      SetLength(Result, sqlite3_column_bytes(St, 1));
      if Length(Result) > 0 then
        Move(P^, Result[1], Length(Result));
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.SetGlyph / ClearGlyphs / GlyphSizeList  (procedures / function)
  Parameters:
    PartID: Int64 - the part; Size: Integer - the side of the square picture in pixels; const Png: String - the PNG file's bytes
  Notes:
    SetGlyph stores (replaces) the picture of that size; ClearGlyphs removes all of the part's; GlyphSizeList gives the sizes stored. Glyphs are derived data, so the part's
    Revision is not touched. Raises EPartsError for an unknown part, a size below 8 or above 512, or empty bytes.
  =========================================================================== }
procedure TPartsLibrary.SetGlyph(PartID: Int64; Size: Integer; const Png: String);
begin
  if PartIndexOfID(PartID) < 0 then
    raise EPartsError.Create(rsThePartIsNotIn);
  if (Size < 8) or (Size > 512) then
    raise EPartsError.Create(rsAGlyphIsBetweenAnd);
  if Png = '' then
    raise EPartsError.Create(rsTheGlyphHasNoPicture);
  BeginTx;
  try
    Exec('DELETE FROM PartGlyph WHERE PartID = ' + IntToStr(PartID) + ' AND Size = ' + IntToStr(Size));
    RunWithBlob('INSERT INTO PartGlyph(PartID, Size, Png) VALUES (' + IntToStr(PartID) + ', ' + IntToStr(Size) + ', ?)', Png);
    CommitTx;
  except
    on E: Exception do
    begin
      RollbackTx;
      raise EPartsError.Create(E.Message);
    end;
  end;
end;

procedure TPartsLibrary.ClearGlyphs(PartID: Int64);
begin
  if PartIndexOfID(PartID) < 0 then
    raise EPartsError.Create(rsThePartIsNotIn);
  Exec('DELETE FROM PartGlyph WHERE PartID = ' + IntToStr(PartID));
end;

function TPartsLibrary.GlyphSizeList(PartID: Int64): TInt64Array;
var
  St: Psqlite3_stmt;
begin
  SetLength(Result, 0);
  St := Prepare('select Size from PartGlyph where PartID = ? order by Size');
  try
    sqlite3_bind_int64(St, 1, PartID);
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := sqlite3_column_int(St, 0);
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.SymbolXml  (function)
  Parameters:
    PartID: Int64 - the part
  Returns:
    String - the symbol's TinyCAD XML, '' when the part has no symbol
  Notes:
    The part's default symbol (Part.BaseDefault), else its first schematic symbol: the same XML a .TCLib keeps for a symbol, so the symbol loader reads it as is.
  =========================================================================== }
function TPartsLibrary.SymbolXml(PartID: Int64): String;
var
  St: Psqlite3_stmt;
  P: Pointer;
begin
  Result := '';
  St := Prepare('select s.Drawing from Symbol s where s.PartID=? and s.Purpose=''schematic'' order by (s.SymbolID = (select BaseDefault from Part where PartID=s.PartID)) desc, s.SymbolID limit 1');
  try
    sqlite3_bind_int64(St, 1, PartID);
    if sqlite3_step(St) = SQLITE_ROW then
    begin
      P := sqlite3_column_blob(St, 0);
      SetLength(Result, sqlite3_column_bytes(St, 0));
      if Length(Result) > 0 then
        Move(P^, Result[1], Length(Result));
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.Ratings  (function)
  Parameters:
    PartID: Int64 - the part
  Returns:
    TPartRatingArray - the part's required ratings, whole-part ones first, then by object name and quantity
  Notes:
    The requirements of a generic part (a product's own ratings are not listed here).
  =========================================================================== }
function TPartsLibrary.Ratings(PartID: Int64): TPartRatingArray;
var
  St: Psqlite3_stmt;
  N: Integer;
begin
  SetLength(Result, 0);
  St := Prepare('select r.Quantity, r.Unit, coalesce(r.Condition, ''''), coalesce(o.Name, ''''), r.Min, r.Typ, r.Max, r.RatingID, coalesce(r.ObjectID, 0) from Rating r ' +
                'left join PartObject o on o.ObjectID = r.ObjectID where r.PartID=? order by o.Name is not null, o.Name, r.Quantity');
  try
    sqlite3_bind_int64(St, 1, PartID);
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N].Quantity := ColText(St, 0);
      Result[N].Unit_ := ColText(St, 1);
      Result[N].Condition := ColText(St, 2);
      Result[N].ObjectName := ColText(St, 3);
      Result[N].HasMin := sqlite3_column_type(St, 4) <> SQLITE_NULL;
      Result[N].HasTyp := sqlite3_column_type(St, 5) <> SQLITE_NULL;
      Result[N].HasMax := sqlite3_column_type(St, 6) <> SQLITE_NULL;
      Result[N].Min := sqlite3_column_double(St, 4);
      Result[N].Typ := sqlite3_column_double(St, 5);
      Result[N].Max := sqlite3_column_double(St, 6);
      Result[N].ID := sqlite3_column_int64(St, 7);
      Result[N].ObjectID := sqlite3_column_int64(St, 8);
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.Products  (function)
  Parameters:
    PartID: Int64 - the generic part
  Returns:
    TProductInfoArray - every product of the part's class with its verdict for this part, the ones that fit first
  Notes:
    The verdict comes from the schema's view ProductFitSummary (oversized is allowed; undersized, missing and mismatched ratings do not fit).
  =========================================================================== }
function TPartsLibrary.Products(PartID: Int64): TProductInfoArray;
var
  St: Psqlite3_stmt;
  N: Integer;
begin
  SetLength(Result, 0);
  St := Prepare('select p.ProductID, p.UID, p.Manufacturer, p.MPN, coalesce(p.Description, ''''), f.Verdict, f.Undersized, f.Missing, f.Mismatch, f.Oversized ' +
                'from ProductFitSummary f join Product p using(ProductID) where f.PartID=? ' +
                'order by f.Verdict = ''does_not_fit'', lower(p.Manufacturer), lower(p.MPN)');
  try
    sqlite3_bind_int64(St, 1, PartID);
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N].ID := sqlite3_column_int64(St, 0);
      Result[N].UID := ColText(St, 1);
      Result[N].Manufacturer := ColText(St, 2);
      Result[N].MPN := ColText(St, 3);
      Result[N].Description := ColText(St, 4);
      Result[N].Verdict := ColText(St, 5);
      Result[N].Undersized := sqlite3_column_int(St, 6);
      Result[N].Missing := sqlite3_column_int(St, 7);
      Result[N].Mismatch := sqlite3_column_int(St, 8);
      Result[N].Oversized := sqlite3_column_int(St, 9);
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  FillRating  (procedure)
  Parameters:
    St: Psqlite3_stmt - the statement
    var R: TRatingData - the rating to fill
    Col: Integer - the column of Min (Typ and Max follow)
  Notes:
    Reads the three values of a rating, remembering which are NULL.
  =========================================================================== }
procedure FillRating(St: Psqlite3_stmt; var R: TRatingData; Col: Integer);
begin
  R.HasMin := sqlite3_column_type(St, Col) <> SQLITE_NULL;
  R.HasTyp := sqlite3_column_type(St, Col + 1) <> SQLITE_NULL;
  R.HasMax := sqlite3_column_type(St, Col + 2) <> SQLITE_NULL;
  R.Min := sqlite3_column_double(St, Col);
  R.Typ := sqlite3_column_double(St, Col + 1);
  R.Max := sqlite3_column_double(St, Col + 2);
end;

{ ===========================================================================
  TPartsLibrary.PartCopyOf  (function)
  Parameters:
    PartIndex: Integer - the part in Parts
  Returns:
    TPartCopy - what a design keeps of the generic part
  Notes:
    The part's GUID, the library's, its name and class, and its requirements (every rating of the part with the way it is judged and the kinds of the object it is on,
    so the fit check needs no library).
  =========================================================================== }
function TPartsLibrary.PartCopyOf(PartIndex: Integer): TPartCopy;
var
  St: Psqlite3_stmt;
  N: Integer;
begin
  Result.UID := FParts[PartIndex].UID;
  Result.LibraryUID := FLibraryUID;
  Result.Name := FParts[PartIndex].Name;
  Result.ClassName := FParts[PartIndex].ClassName;
  SetLength(Result.Needs, 0);
  St := Prepare('select r.Quantity, r.Unit, coalesce(r.Condition, ''''), coalesce(o.Name, ''''), q.Sense, r.Min, r.Typ, r.Max, ' +
                'coalesce((select group_concat(k.Name, '','') from KindAncestors ka join ObjectKind k on k.KindID = ka.AncestorID where ka.KindID = o.KindID), '''') ' +
                'from Rating r join RatingQuantity q on q.Name = r.Quantity left join PartObject o on o.ObjectID = r.ObjectID where r.PartID=? order by r.RatingID');
  try
    sqlite3_bind_int64(St, 1, FParts[PartIndex].ID);
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      N := Length(Result.Needs);
      SetLength(Result.Needs, N + 1);
      Result.Needs[N].Quantity := ColText(St, 0);
      Result.Needs[N].Unit_ := ColText(St, 1);
      Result.Needs[N].Condition := ColText(St, 2);
      Result.Needs[N].AppliesTo := ColText(St, 3);
      Result.Needs[N].Sense := ColText(St, 4);
      FillRating(St, Result.Needs[N], 5);
      Result.Needs[N].Kinds := ColText(St, 8);
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.ProductChoiceOf  (function)
  Parameters:
    ProductID: Int64 - the product
  Returns:
    TProductChoice - what a design keeps of the chosen product
  Notes:
    The product's GUID, manufacturer and model number and its ratings (with the object or kind each is on).
  =========================================================================== }
function TPartsLibrary.ProductChoiceOf(ProductID: Int64): TProductChoice;
var
  St: Psqlite3_stmt;
  N: Integer;
begin
  Result.UID := '';
  Result.Manufacturer := '';
  Result.MPN := '';
  SetLength(Result.Haves, 0);
  St := Prepare('select UID, Manufacturer, MPN from Product where ProductID=?');
  try
    sqlite3_bind_int64(St, 1, ProductID);
    if sqlite3_step(St) = SQLITE_ROW then
    begin
      Result.UID := ColText(St, 0);
      Result.Manufacturer := ColText(St, 1);
      Result.MPN := ColText(St, 2);
    end;
  finally
    sqlite3_finalize(St);
  end;
  St := Prepare('select Quantity, Unit, coalesce(Condition, ''''), coalesce(AppliesTo, ''''), Min, Typ, Max from Rating where ProductID=? order by RatingID');
  try
    sqlite3_bind_int64(St, 1, ProductID);
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      N := Length(Result.Haves);
      SetLength(Result.Haves, N + 1);
      Result.Haves[N].Quantity := ColText(St, 0);
      Result.Haves[N].Unit_ := ColText(St, 1);
      Result.Haves[N].Condition := ColText(St, 2);
      Result.Haves[N].AppliesTo := ColText(St, 3);
      Result.Haves[N].Sense := '';
      Result.Haves[N].Kinds := '';
      FillRating(St, Result.Haves[N], 4);
    end;
  finally
    sqlite3_finalize(St);
  end;
end;


{ ===========================================================================
  SqlQ  (function)
  Parameters:
    const S: String - text
  Returns:
    String - the text as an SQL string literal
  Notes:
    Quotes text for an SQL statement (single quotes doubled).
  =========================================================================== }
function SqlQ(const S: String): String;
begin
  Result := '''' + StringReplace(S, '''', '''''', [rfReplaceAll]) + '''';
end;

{ ===========================================================================
  NewGuidText  (function)
  Parameters:  none
  Returns:
    String - a new GUID in lower case without braces
  Notes:
    The UID of a new part.
  =========================================================================== }
function NewGuidText: String;
var
  G: TGuid;
begin
  CreateGUID(G);
  Result := LowerCase(Copy(GUIDToString(G), 2, 36));
end;

{ ===========================================================================
  TPartsLibrary.QueryInt  (function)
  Parameters:
    const SQL: String - a query whose first column of the first row is a number
  Returns:
    Int64 - that number, 0 when there is no row
  Notes:
    Reads one number from the file.
  =========================================================================== }
function TPartsLibrary.QueryInt(const SQL: String): Int64;
var
  St: Psqlite3_stmt;
begin
  Result := 0;
  St := Prepare(SQL);
  try
    if sqlite3_step(St) = SQLITE_ROW then
      Result := sqlite3_column_int64(St, 0);
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.Touch  (procedure)
  Parameters:  none
  Notes:
    Stamps the library as changed now (LibraryInfo.Modified); part of every editing transaction.
  =========================================================================== }
procedure TPartsLibrary.Touch;
begin
  Exec('UPDATE LibraryInfo SET Modified = datetime(''now'')');
end;

{ ===========================================================================
  TPartsLibrary.Mutate  (procedure)
  Parameters:
    const Steps: array of String - statements
  Notes:
    Runs the statements in one transaction with the library's Modified stamp; on any error the transaction is rolled back and EPartsError says what SQLite
    said, with the common constraint messages in plain words. The part list is read again afterwards.
  =========================================================================== }
procedure TPartsLibrary.Mutate(const Steps: array of String);
var
  i: Integer;
  Msg: String;
begin
  if FDb = nil then
    raise EPartsError.Create(rsNoPartsLibraryIsOpen);
  BeginTx;
  try
    for i := Low(Steps) to High(Steps) do
      Exec(Steps[i]);
    Touch;
    CommitTx;
  except
    on E: Exception do
    begin
      RollbackTx;
      Msg := E.Message;
      if Pos('UNIQUE constraint failed: Part.ClassID, Part.Name', Msg) > 0 then
        Msg := rsTheClassAlreadyHasA
      else if Pos('readonly', Msg) > 0 then
        Msg := rsThePartsFileCannotBe;
      raise EPartsError.Create(Msg);
    end;
  end;
  if FBatch = 0 then
    LoadAll;
end;

{ ===========================================================================
  TPartsLibrary.Quantities  (function)
  Returns:
    TQuantityInfoArray - every quantity that can be rated, sorted by name
  =========================================================================== }
function TPartsLibrary.Quantities: TQuantityInfoArray;
var
  St: Psqlite3_stmt;
  N: Integer;
begin
  SetLength(Result, 0);
  St := Prepare('select Name, Unit, Sense, coalesce(Description, '''') from RatingQuantity order by lower(Name)');
  try
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N].Name := ColText(St, 0);
      Result[N].Unit_ := ColText(St, 1);
      Result[N].Sense := ColText(St, 2);
      Result[N].Description := ColText(St, 3);
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.PartObjects  (function)
  Parameters:
    PartID: Int64 - the part
  Returns:
    TObjectRefArray - its child objects (terminals, channels, poles ...) with their kind, in the order the part keeps them
  =========================================================================== }
function TPartsLibrary.PartObjects(PartID: Int64): TObjectRefArray;
var
  St: Psqlite3_stmt;
  N: Integer;
begin
  SetLength(Result, 0);
  St := Prepare('select o.ObjectID, o.Name, coalesce(o.Designator, ''''), k.Name, coalesce(o.ParentObjectID, 0), o.KindID, o.Sort, coalesce(o.Description, '''') from PartObject o join ObjectKind k on k.KindID = o.KindID where o.PartID = ? order by o.Sort, o.ObjectID');
  try
    sqlite3_bind_int64(St, 1, PartID);
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N].ID := sqlite3_column_int64(St, 0);
      Result[N].Name := ColText(St, 1);
      Result[N].Designator := ColText(St, 2);
      Result[N].Kind := ColText(St, 3);
      Result[N].ParentID := sqlite3_column_int64(St, 4);
      Result[N].KindID := sqlite3_column_int64(St, 5);
      Result[N].Sort := sqlite3_column_int(St, 6);
      Result[N].Description := ColText(St, 7);
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.RevisionAfter  (function)
  Parameters:
    PartIndex: Integer - index in Parts
  Returns:
    String - the part's next revision: none counts as 1 so '2'; a number goes up by one; anything else gets '.1' added
  =========================================================================== }
function TPartsLibrary.RevisionAfter(PartIndex: Integer): String;
var
  Rev: Integer;
begin
  if FParts[PartIndex].Revision = '' then
    Result := '2'
  else if TryStrToInt(FParts[PartIndex].Revision, Rev) then
    Result := IntToStr(Rev + 1)
  else
    Result := FParts[PartIndex].Revision + '.1';
end;

{ a number as SQL text, always with a point }
function SqlFloat(V: Double): String;
var
  F: TFormatSettings;
begin
  F := DefaultFormatSettings;
  F.DecimalSeparator := '.';
  Result := FloatToStrF(V, ffGeneral, 15, 0, F);
end;

{ ===========================================================================
  TPartsLibrary.QueryText  (function)
  Parameters:
    const SQL: String - a query
  Returns:
    String - the first column of the first row, '' for none
  =========================================================================== }
function TPartsLibrary.QueryText(const SQL: String): String;
var
  St: Psqlite3_stmt;
begin
  Result := '';
  St := Prepare(SQL);
  try
    if sqlite3_step(St) = SQLITE_ROW then
      Result := ColText(St, 0);
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.RatingValuesSql  (function)
  Parameters:
    AQuantity, AUnit, ACondition: the entries; HasMin.. / AMin..: which values are given and their numbers
    out QUnit: String - the quantity's unit
  Returns:
    String - the SQL text of "Quantity, Min, Typ, Max, Unit, Condition" values (NULL for a value not given)
  Notes:
    The rules of a requirement: the quantity exists; the unit is its unit (an empty unit takes it); at least one value; min <= typ <= max among the ones given.
    Raises EPartsError with the reason.
  =========================================================================== }
function TPartsLibrary.RatingValuesSql(const AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double; out QUnit: String): String;
  function V(Has: Boolean; X: Double): String;
  begin
    if Has then
      Result := SqlFloat(X)
    else
      Result := 'NULL';
  end;
var
  Cond: String;
begin
  QUnit := '';
  if Trim(AQuantity) = '' then
    raise EPartsError.Create(rsChooseWhatIsRatedA);
  if QueryInt('select count(*) from RatingQuantity where Name = ' + SqlQ(AQuantity)) = 0 then
    raise EPartsError.Create(Format(rsIsNotAQuantityOf, [AQuantity]));
  QUnit := QueryText('select Unit from RatingQuantity where Name = ' + SqlQ(AQuantity));
  if (Trim(AUnit) <> '') and (Trim(AUnit) <> QUnit) then
    raise EPartsError.Create(Format(rsTheUnitOfIsNot, [AQuantity, QUnit, Trim(AUnit)]));
  if not (HasMin or HasTyp or HasMax) then
    raise EPartsError.Create(rsGiveAtLeastOneOf);
  if HasMin and HasTyp and (AMin > ATyp) then
    raise EPartsError.Create(rsTheMinimumIsAboveThe);
  if HasTyp and HasMax and (ATyp > AMax) then
    raise EPartsError.Create(rsTheTypicalValueIsAbove);
  if HasMin and HasMax and (AMin > AMax) then
    raise EPartsError.Create(rsTheMinimumIsAboveThe2);
  Cond := Trim(ACondition);
  Result := SqlQ(AQuantity) + ', ' + V(HasMin, AMin) + ', ' + V(HasTyp, ATyp) + ', ' + V(HasMax, AMax) + ', ' + SqlQ(QUnit) + ', ';
  if Cond = '' then
    Result := Result + 'NULL'
  else
    Result := Result + SqlQ(Cond);
end;

{ ===========================================================================
  TPartsLibrary.RatingObjectSql  (function)
  Parameters:
    PartID, ObjectID: Int64 - the part and the object (0 = the whole part)
  Returns:
    String - 'NULL' or the object's number; raises EPartsError when the object is not a child of the part
  =========================================================================== }
function TPartsLibrary.RatingObjectSql(PartID, ObjectID: Int64): String;
begin
  if ObjectID = 0 then
    Exit('NULL');
  if QueryInt('select count(*) from PartObject where ObjectID = ' + IntToStr(ObjectID) + ' and PartID = ' + IntToStr(PartID)) = 0 then
    raise EPartsError.Create(rsThatObjectIsNotA);
  Result := IntToStr(ObjectID);
end;

{ ===========================================================================
  TPartsLibrary.AddRating  (function)
  Parameters:
    PartID, ObjectID: Int64 - the part and the child object it applies to (0 = the whole part)
    const AQuantity, AUnit, ACondition: String - what is rated, its unit ('' = the quantity's), the condition (such as 'AC-15 230 V', '' for none)
    HasMin, HasTyp, HasMax: Boolean - which values are given
    AMin, ATyp, AMax: Double - the values
  Returns:
    Int64 - the RatingID
  Notes:
    Adds a requirement to the part (see RatingValuesSql for the rules). Refused as well: an object that is not of this part, and a second requirement for the same
    quantity and condition on the same object (a product's rating is matched on those, so two would be ambiguous). The part's Revision goes up and Modified is stamped.
  =========================================================================== }
function TPartsLibrary.AddRating(PartID, ObjectID: Int64; const AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double): Int64;
var
  Idx: Integer;
  QUnit, Vals, Obj: String;
begin
  Idx := PartIndexOfID(PartID);
  if Idx < 0 then
    raise EPartsError.Create(rsThePartIsNotIn);
  Vals := RatingValuesSql(AQuantity, AUnit, ACondition, HasMin, HasTyp, HasMax, AMin, ATyp, AMax, QUnit);
  Obj := RatingObjectSql(PartID, ObjectID);
  if QueryInt('select count(*) from Rating where PartID = ' + IntToStr(PartID) + ' and ObjectID is ' + Obj + ' and Quantity = ' + SqlQ(AQuantity) +
    ' and coalesce(Condition, '''') = ' + SqlQ(Trim(ACondition))) > 0 then
    raise EPartsError.Create(Format(rsThePartAlreadyHasA, [AQuantity]));
  Mutate(['INSERT INTO Rating(PartID, ObjectID, Quantity, Min, Typ, Max, Unit, Condition) VALUES (' + IntToStr(PartID) + ', ' + Obj + ', ' + Vals + ')',
    'UPDATE Part SET Revision = ' + SqlQ(RevisionAfter(Idx)) + ', Modified = datetime(''now'') WHERE PartID = ' + IntToStr(PartID)]);
  Result := QueryInt('select max(RatingID) from Rating where PartID = ' + IntToStr(PartID));
end;

{ ===========================================================================
  TPartsLibrary.UpdateRating  (procedure)
  Parameters:
    RatingID: Int64 - the requirement; the other parameters as for AddRating
  Notes:
    Changes a requirement of a part (not a product's rating); the same rules as AddRating, and a requirement can be changed without clashing with itself.
  =========================================================================== }
procedure TPartsLibrary.UpdateRating(RatingID, ObjectID: Int64; const AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double);
var
  PartID: Int64;
  Idx: Integer;
  QUnit, Vals, Obj: String;
begin
  PartID := QueryInt('select coalesce(PartID, 0) from Rating where RatingID = ' + IntToStr(RatingID));
  Idx := PartIndexOfID(PartID);
  if Idx < 0 then
    raise EPartsError.Create(rsThatRequirementIsNotIn);
  Vals := RatingValuesSql(AQuantity, AUnit, ACondition, HasMin, HasTyp, HasMax, AMin, ATyp, AMax, QUnit);
  Obj := RatingObjectSql(PartID, ObjectID);
  if QueryInt('select count(*) from Rating where PartID = ' + IntToStr(PartID) + ' and RatingID <> ' + IntToStr(RatingID) + ' and ObjectID is ' + Obj + ' and Quantity = ' +
    SqlQ(AQuantity) + ' and coalesce(Condition, '''') = ' + SqlQ(Trim(ACondition))) > 0 then
    raise EPartsError.Create(Format(rsThePartAlreadyHasA, [AQuantity]));
  Mutate(['UPDATE Rating SET ObjectID = ' + Obj + ', (Quantity, Min, Typ, Max, Unit, Condition) = (' + Vals + ') WHERE RatingID = ' + IntToStr(RatingID),
    'UPDATE Part SET Revision = ' + SqlQ(RevisionAfter(Idx)) + ', Modified = datetime(''now'') WHERE PartID = ' + IntToStr(PartID)]);
end;

{ ===========================================================================
  TPartsLibrary.DeleteRating  (procedure)
  Parameters:
    RatingID: Int64 - the requirement
  Notes:
    Deletes a requirement of a part; the part's Revision goes up and Modified is stamped.
  =========================================================================== }
procedure TPartsLibrary.DeleteRating(RatingID: Int64);
var
  PartID: Int64;
  Idx: Integer;
begin
  PartID := QueryInt('select coalesce(PartID, 0) from Rating where RatingID = ' + IntToStr(RatingID));
  Idx := PartIndexOfID(PartID);
  if Idx < 0 then
    raise EPartsError.Create(rsThatRequirementIsNotIn);
  Mutate(['DELETE FROM Rating WHERE RatingID = ' + IntToStr(RatingID),
    'UPDATE Part SET Revision = ' + SqlQ(RevisionAfter(Idx)) + ', Modified = datetime(''now'') WHERE PartID = ' + IntToStr(PartID)]);
end;

{ ===========================================================================
  TPartsLibrary.ObjectKinds  (function)
  Parameters:
    PartID: Int64 - the part
  Returns:
    TKindInfoArray - the kinds of child object the part's class allows (its own and its ancestors', with their sub-kinds), not the abstract ones, sorted by name
  Notes:
    The same set the library's own rule (trigger PartObject_kind) accepts, minus the kinds that only group others.
  =========================================================================== }
function TPartsLibrary.ObjectKinds(PartID: Int64): TKindInfoArray;
var
  St: Psqlite3_stmt;
  N: Integer;
begin
  SetLength(Result, 0);
  St := Prepare('select k.KindID, k.Name from ObjectKind k join ClassKinds ck on ck.KindID = k.KindID join Part p on p.ClassID = ck.ClassID ' +
    'where p.PartID = ? and k.Abstract = 0 order by lower(k.Name)');
  try
    sqlite3_bind_int64(St, 1, PartID);
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N].ID := sqlite3_column_int64(St, 0);
      Result[N].Name := ColText(St, 1);
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.KindIDOfName  (function)
  Parameters:
    const AName: String - the name of an object kind
  Returns:
    Int64 - its KindID (any kind, allowed or not, abstract or not; any case), 0 when there is none
  =========================================================================== }
function TPartsLibrary.KindIDOfName(const AName: String): Int64;
begin
  Result := QueryInt('select KindID from ObjectKind where lower(Name) = ' + SqlQ(LowerCase(Trim(AName))));
end;

{ ===========================================================================
  TPartsLibrary.CheckObject  (procedure)
  Parameters:
    PartID, ObjectID: Int64 - the part, and the object being changed (0 = a new one)
    ParentID, KindID: Int64 - the wanted parent object (0 = none) and kind
    const AName: String - the wanted name
  Notes:
    Raises EPartsError when: the name is empty or another object of the part has it (any case); the kind is unknown, abstract or not allowed by the part's class;
    the parent is not an object of the same part, is the object itself or lies below it; the kind of an existing object changes while it holds values
    of a field the new kind lacks. Nothing is written.
  =========================================================================== }
procedure TPartsLibrary.CheckObject(PartID, ObjectID, ParentID, KindID: Int64; const AName: String);
var
  Sub: String;
begin
  if Trim(AName) = '' then
    raise EPartsError.Create(rsTheObjectNeedsAName);
  if QueryInt('select count(*) from PartObject where PartID = ' + IntToStr(PartID) + ' and ObjectID <> ' + IntToStr(ObjectID) + ' and lower(Name) = ' + SqlQ(LowerCase(Trim(AName)))) > 0 then
    raise EPartsError.Create(Format(rsThePartAlreadyHasAn, [Trim(AName)]));
  if QueryInt('select count(*) from ObjectKind where KindID = ' + IntToStr(KindID)) = 0 then
    raise EPartsError.Create(rsChooseTheKindOfThe);
  if QueryInt('select Abstract from ObjectKind where KindID = ' + IntToStr(KindID)) <> 0 then
    raise EPartsError.Create(rsThatKindOnlyGroupsOther);
  if QueryInt('select count(*) from Part p join ClassKinds ck on ck.ClassID = p.ClassID where p.PartID = ' + IntToStr(PartID) + ' and ck.KindID = ' + IntToStr(KindID)) = 0 then
    raise EPartsError.Create(rsThePartSClassDoes);
  if ParentID <> 0 then
  begin
    if QueryInt('select count(*) from PartObject where ObjectID = ' + IntToStr(ParentID) + ' and PartID = ' + IntToStr(PartID)) = 0 then
      raise EPartsError.Create(rsTheParentIsNotAn);
    if ObjectID > 0 then
    begin
      Sub := 'with recursive s(i) as (select ' + IntToStr(ObjectID) + ' union all select o.ObjectID from PartObject o join s on o.ParentObjectID = s.i) select count(*) from s where i = ' + IntToStr(ParentID);
      if QueryInt(Sub) > 0 then
        raise EPartsError.Create(rsAnObjectCannotBePlaced);
    end;
  end;
  if (ObjectID > 0) and (QueryInt('select KindID from PartObject where ObjectID = ' + IntToStr(ObjectID)) <> KindID) and
    (QueryInt('select count(*) from ObjectValue where ObjectID = ' + IntToStr(ObjectID) + ' and FieldID not in (select FieldID from KindFields where KindID = ' + IntToStr(KindID) + ')') > 0) then
    raise EPartsError.Create(rsTheObjectHoldsValuesOf);
end;

{ ===========================================================================
  TPartsLibrary.ObjectParentSql  (function)
  Parameters:
    ParentID: Int64 - an object or 0
  Returns:
    String - 'NULL' or the number, for a statement
  =========================================================================== }
function TPartsLibrary.ObjectParentSql(ParentID: Int64): String;
begin
  if ParentID > 0 then
    Result := IntToStr(ParentID)
  else
    Result := 'NULL';
end;

{ ===========================================================================
  TPartsLibrary.AddObject  (function)
  Parameters:
    PartID: Int64 - the part
    ParentID: Int64 - the object it sits in (a pole holds its contacts and terminals), 0 = directly in the part
    KindID: Int64 - the kind (see ObjectKinds)
    const AName, ADesignator, ADescription: String - name (unique in the part), the number or label printed on it, free text
    ASort: Integer - its place among the others (smaller first)
  Returns:
    Int64 - the new ObjectID
  Notes:
    Adds a child object (terminal, pole, channel ...) to a part. The part's Revision goes up and Modified is stamped. Raises EPartsError (see CheckObject);
    the MinCount / MaxCount a class gives a kind are not enforced here.
  =========================================================================== }
function TPartsLibrary.AddObject(PartID, ParentID, KindID: Int64; const AName, ADesignator, ADescription: String; ASort: Integer): Int64;
var
  Idx: Integer;
begin
  Idx := PartIndexOfID(PartID);
  if Idx < 0 then
    raise EPartsError.Create(rsThePartIsNotIn);
  CheckObject(PartID, 0, ParentID, KindID, AName);
  Mutate(['INSERT INTO PartObject(PartID, ParentObjectID, KindID, Name, Designator, Sort, Description) VALUES (' + IntToStr(PartID) + ', ' + ObjectParentSql(ParentID) + ', ' +
    IntToStr(KindID) + ', ' + SqlQ(Trim(AName)) + ', ' + SqlQ(Trim(ADesignator)) + ', ' + IntToStr(ASort) + ', ' + SqlQ(ADescription) + ')',
    'UPDATE Part SET Revision = ' + SqlQ(RevisionAfter(Idx)) + ', Modified = datetime(''now'') WHERE PartID = ' + IntToStr(PartID)]);
  Result := QueryInt('select max(ObjectID) from PartObject where PartID = ' + IntToStr(PartID));
end;

{ ===========================================================================
  TPartsLibrary.UpdateObject  (procedure)
  Parameters:
    ObjectID: Int64 - the object; the other parameters as for AddObject
  Notes:
    Changes name, designator, kind, parent, order and description of a child object; the same rules as AddObject. The part's Revision goes up.
  =========================================================================== }
procedure TPartsLibrary.UpdateObject(ObjectID, ParentID, KindID: Int64; const AName, ADesignator, ADescription: String; ASort: Integer);
var
  PartID: Int64;
  Idx: Integer;
begin
  PartID := QueryInt('select coalesce(PartID, 0) from PartObject where ObjectID = ' + IntToStr(ObjectID));
  Idx := PartIndexOfID(PartID);
  if Idx < 0 then
    raise EPartsError.Create(rsThatObjectIsNotIn);
  CheckObject(PartID, ObjectID, ParentID, KindID, AName);
  Mutate(['UPDATE PartObject SET ParentObjectID = ' + ObjectParentSql(ParentID) + ', KindID = ' + IntToStr(KindID) + ', Name = ' + SqlQ(Trim(AName)) + ', Designator = ' +
    SqlQ(Trim(ADesignator)) + ', Sort = ' + IntToStr(ASort) + ', Description = ' + SqlQ(ADescription) + ' WHERE ObjectID = ' + IntToStr(ObjectID),
    'UPDATE Part SET Revision = ' + SqlQ(RevisionAfter(Idx)) + ', Modified = datetime(''now'') WHERE PartID = ' + IntToStr(PartID)]);
end;

{ ===========================================================================
  TPartsLibrary.ObjectSubtreeCount  (function)
  Parameters:
    ObjectID: Int64 - an object
  Returns:
    Integer - how many objects lie below it, at any depth
  =========================================================================== }
function TPartsLibrary.ObjectSubtreeCount(ObjectID: Int64): Integer;
begin
  Result := QueryInt('with recursive s(i) as (select ' + IntToStr(ObjectID) + ' union all select o.ObjectID from PartObject o join s on o.ParentObjectID = s.i) select count(*) - 1 from s');
end;

{ ===========================================================================
  TPartsLibrary.DeleteObject  (procedure)
  Parameters:
    ObjectID: Int64 - the object
  Notes:
    Deletes the object with everything below it, their requirements, field values and links inside the part. Refused while a symbol pin, outline terminal or
    3D terminal names the object or one below it (that placement would be lost; remove it first). The part's Revision goes up.
  =========================================================================== }
procedure TPartsLibrary.DeleteObject(ObjectID: Int64);
var
  PartID: Int64;
  Idx: Integer;
  Sub: String;
begin
  PartID := QueryInt('select coalesce(PartID, 0) from PartObject where ObjectID = ' + IntToStr(ObjectID));
  Idx := PartIndexOfID(PartID);
  if Idx < 0 then
    raise EPartsError.Create(rsThatObjectIsNotIn);
  Sub := '(with recursive s(i) as (select ' + IntToStr(ObjectID) + ' union all select o.ObjectID from PartObject o join s on o.ParentObjectID = s.i) select i from s)';
  if QueryInt('select (select count(*) from SymbolPin where ObjectID in ' + Sub + ') + (select count(*) from OutlineTerminal where ObjectID in ' + Sub +
    ') + (select count(*) from ModelTerminal where ObjectID in ' + Sub + ')') > 0 then
    raise EPartsError.Create(rsASymbolPinOutlineTerminal);
  Mutate(['DELETE FROM Link WHERE FromObject IN ' + Sub + ' OR ToObject IN ' + Sub,
    'DELETE FROM PartObject WHERE ObjectID = ' + IntToStr(ObjectID),
    'UPDATE Part SET Revision = ' + SqlQ(RevisionAfter(Idx)) + ', Modified = datetime(''now'') WHERE PartID = ' + IntToStr(PartID)]);
end;

{ ===========================================================================
  TPartsLibrary.NextRevision  (function)
  Parameters:
    const Rev: String - a revision text
  Returns:
    String - the next one: none counts as 1 so '2'; a number goes up by one; anything else gets '.1' added
  =========================================================================== }
function TPartsLibrary.NextRevision(const Rev: String): String;
var
  N: Integer;
begin
  if Rev = '' then
    Result := '2'
  else if TryStrToInt(Rev, N) then
    Result := IntToStr(N + 1)
  else
    Result := Rev + '.1';
end;

{ ===========================================================================
  TPartsLibrary.ProductRows  (function)
  Returns:
    TProductRowArray - every product of the library with its class, sorted by manufacturer then model number (any case)
  =========================================================================== }
function TPartsLibrary.ProductRows: TProductRowArray;
var
  St: Psqlite3_stmt;
  N: Integer;
begin
  SetLength(Result, 0);
  St := Prepare('select p.ProductID, p.UID, p.ClassID, c.Name, p.Manufacturer, p.MPN, coalesce(p.Series, ''''), coalesce(p.Description, ''''), p.Status, coalesce(p.Revision, ''''), ' +
    'coalesce(p.Modified, '''') from Product p join PartClass c on c.ClassID = p.ClassID order by lower(p.Manufacturer), lower(p.MPN)');
  try
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N].ID := sqlite3_column_int64(St, 0);
      Result[N].UID := ColText(St, 1);
      Result[N].ClassID := sqlite3_column_int64(St, 2);
      Result[N].ClassName := ColText(St, 3);
      Result[N].Manufacturer := ColText(St, 4);
      Result[N].MPN := ColText(St, 5);
      Result[N].Series := ColText(St, 6);
      Result[N].Description := ColText(St, 7);
      Result[N].Status := ColText(St, 8);
      Result[N].Revision := ColText(St, 9);
      Result[N].Modified := ColText(St, 10);
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.ProductRatings  (function)
  Parameters:
    ProductID: Int64 - the product
  Returns:
    TPartRatingArray - what the product is rated for; ObjectName holds what a rating applies to ('' = the whole product, an object's name, or 'kind:Name'), ObjectID is 0
  =========================================================================== }
function TPartsLibrary.ProductRatings(ProductID: Int64): TPartRatingArray;
var
  St: Psqlite3_stmt;
  N: Integer;
begin
  SetLength(Result, 0);
  St := Prepare('select Quantity, Unit, coalesce(Condition, ''''), coalesce(AppliesTo, ''''), Min, Typ, Max, RatingID from Rating where ProductID = ? ' +
    'order by AppliesTo is not null, AppliesTo, Quantity, Condition');
  try
    sqlite3_bind_int64(St, 1, ProductID);
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N] := Default(TPartRating);
      Result[N].Quantity := ColText(St, 0);
      Result[N].Unit_ := ColText(St, 1);
      Result[N].Condition := ColText(St, 2);
      Result[N].ObjectName := ColText(St, 3);
      Result[N].HasMin := sqlite3_column_type(St, 4) <> SQLITE_NULL;
      Result[N].HasTyp := sqlite3_column_type(St, 5) <> SQLITE_NULL;
      Result[N].HasMax := sqlite3_column_type(St, 6) <> SQLITE_NULL;
      Result[N].Min := sqlite3_column_double(St, 4);
      Result[N].Typ := sqlite3_column_double(St, 5);
      Result[N].Max := sqlite3_column_double(St, 6);
      Result[N].ID := sqlite3_column_int64(St, 7);
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.AppliesToChoices  (function)
  Parameters:
    ClassID: Int64 - a product's class
  Returns:
    TStringDynArray - what a product rating can apply to: 'kind:Name' for every non-abstract kind, then the names of the child objects of the class's parts (each once)
  =========================================================================== }
function TPartsLibrary.AppliesToChoices(ClassID: Int64): TStringDynArray;
var
  St: Psqlite3_stmt;
  N: Integer;
begin
  SetLength(Result, 0);
  St := Prepare('select ''kind:'' || Name from ObjectKind where Abstract = 0 union all select Name from (select distinct o.Name from PartObject o join Part p using(PartID) where p.ClassID = ' +
    IntToStr(ClassID) + ' order by o.Name)');
  try
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N] := ColText(St, 0);
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.SuggestionState  (function)
  Parameters:
    PartID, ProductID: Int64 - a generic part and a product
  Returns:
    Integer - -1 when the library author has not suggested the product for the part, 0 when suggested, 1 when it is the preferred one
  =========================================================================== }
function TPartsLibrary.SuggestionState(PartID, ProductID: Int64): Integer;
begin
  if QueryInt('select count(*) from PartProduct where PartID = ' + IntToStr(PartID) + ' and ProductID = ' + IntToStr(ProductID)) = 0 then
    Exit(-1);
  Result := Ord(QueryInt('select Preferred from PartProduct where PartID = ' + IntToStr(PartID) + ' and ProductID = ' + IntToStr(ProductID)) <> 0);
end;

{ ===========================================================================
  TPartsLibrary.SetSuggestion  (procedure)
  Parameters:
    PartID, ProductID: Int64 - a generic part and a product
    State: Integer - -1 removes the suggestion, 0 suggests the product for the part, 1 makes it the preferred one (the part's other preferred product, if any, becomes a plain suggestion)
  Notes:
    The suggestions are the library author's short list (PartProduct); any product of the part's class can still be chosen. Raises EPartsError when the product's class
    is not the part's class. The parts' own Revision is not touched.
  =========================================================================== }
procedure TPartsLibrary.SetSuggestion(PartID, ProductID: Int64; State: Integer);
var
  P, Q: String;
begin
  P := IntToStr(PartID);
  Q := IntToStr(ProductID);
  if PartIndexOfID(PartID) < 0 then
    raise EPartsError.Create(rsThePartIsNotIn);
  if QueryInt('select count(*) from Product where ProductID = ' + Q) = 0 then
    raise EPartsError.Create(rsTheProductIsNotIn);
  if State < 0 then
  begin
    Mutate(['DELETE FROM PartProduct WHERE PartID = ' + P + ' AND ProductID = ' + Q]);
    Exit;
  end;
  if QueryInt('select count(*) from Part p join Product r on r.ClassID = p.ClassID where p.PartID = ' + P + ' and r.ProductID = ' + Q) = 0 then
    raise EPartsError.Create(rsTheProductBelongsToAnother);
  if State > 0 then
    Mutate(['UPDATE PartProduct SET Preferred = 0 WHERE PartID = ' + P,
      'INSERT OR REPLACE INTO PartProduct(PartID, ProductID, Preferred, Note) VALUES (' + P + ', ' + Q + ', 1, (SELECT Note FROM PartProduct WHERE PartID = ' + P + ' AND ProductID = ' + Q + '))'])
  else
    Mutate(['INSERT OR REPLACE INTO PartProduct(PartID, ProductID, Preferred, Note) VALUES (' + P + ', ' + Q + ', 0, (SELECT Note FROM PartProduct WHERE PartID = ' + P + ' AND ProductID = ' + Q + '))']);
end;

{ ===========================================================================
  TPartsLibrary.CheckProduct  (procedure)
  Parameters:
    ProductID: Int64 - the product being changed, 0 for a new one
    ClassID: Int64 - its class
    const AManufacturer, AMPN, AStatus: String
  Notes:
    Raises EPartsError when manufacturer or model number is empty, the pair is used by another product, the class is unknown or abstract, or the status is not active,
    obsolete, preview or custom. A class change is refused while the product is suggested for parts (their class would no longer match).
  =========================================================================== }
procedure TPartsLibrary.CheckProduct(ProductID, ClassID: Int64; const AManufacturer, AMPN, AStatus: String);
begin
  if Trim(AManufacturer) = '' then
    raise EPartsError.Create(rsTheProductNeedsAManufacturer);
  if Trim(AMPN) = '' then
    raise EPartsError.Create(rsTheProductNeedsAModel);
  if (AStatus <> 'active') and (AStatus <> 'obsolete') and (AStatus <> 'preview') and (AStatus <> 'custom') then
    raise EPartsError.Create(rsTheStatusMustBeActive);
  if QueryInt('select count(*) from PartClass where ClassID = ' + IntToStr(ClassID) + ' and Abstract = 0') = 0 then
    raise EPartsError.Create(rsChooseAClassForThe);
  if QueryInt('select count(*) from Product where ProductID <> ' + IntToStr(ProductID) + ' and lower(Manufacturer) = ' + SqlQ(LowerCase(Trim(AManufacturer))) + ' and lower(MPN) = ' +
    SqlQ(LowerCase(Trim(AMPN)))) > 0 then
    raise EPartsError.Create(Format(rsTheLibraryAlreadyHasA, [Trim(AManufacturer), Trim(AMPN)]));
  if (ProductID > 0) and (QueryInt('select ClassID from Product where ProductID = ' + IntToStr(ProductID)) <> ClassID) and
    (QueryInt('select count(*) from PartProduct where ProductID = ' + IntToStr(ProductID)) > 0) then
    raise EPartsError.Create(rsTheProductIsSuggestedFor);
end;

{ ===========================================================================
  TPartsLibrary.AddProduct  (function)
  Parameters:
    ClassID: Int64 - the (non abstract) class the product can be chosen for
    const AManufacturer, AMPN, ASeries, ADescription, AStatus: String - manufacturer and model number (together unique, any case), series, text, status
  Returns:
    Int64 - the new ProductID
  Notes:
    Adds a catalog product with a new GUID, revision 1 and Modified stamped. Raises EPartsError when refused (see CheckProduct); nothing changes.
  =========================================================================== }
function TPartsLibrary.AddProduct(ClassID: Int64; const AManufacturer, AMPN, ASeries, ADescription, AStatus: String): Int64;
begin
  CheckProduct(0, ClassID, AManufacturer, AMPN, AStatus);
  Mutate(['INSERT INTO Product(UID, ClassID, Manufacturer, MPN, Series, Description, Status, Revision, Modified) VALUES (' + SqlQ(NewGuidText) + ', ' + IntToStr(ClassID) + ', ' +
    SqlQ(Trim(AManufacturer)) + ', ' + SqlQ(Trim(AMPN)) + ', ' + SqlQ(Trim(ASeries)) + ', ' + SqlQ(ADescription) + ', ' + SqlQ(AStatus) + ', ''1'', datetime(''now''))']);
  Result := QueryInt('select max(ProductID) from Product');
end;

{ ===========================================================================
  TPartsLibrary.UpdateProduct  (procedure)
  Parameters:
    ProductID: Int64 - the product; the other parameters as for AddProduct
  Notes:
    Changes the product; its Revision goes up by one and Modified is stamped. The same rules as AddProduct.
  =========================================================================== }
procedure TPartsLibrary.UpdateProduct(ProductID, ClassID: Int64; const AManufacturer, AMPN, ASeries, ADescription, AStatus: String);
begin
  if QueryInt('select count(*) from Product where ProductID = ' + IntToStr(ProductID)) = 0 then
    raise EPartsError.Create(rsTheProductIsNotIn);
  CheckProduct(ProductID, ClassID, AManufacturer, AMPN, AStatus);
  Mutate(['UPDATE Product SET ClassID = ' + IntToStr(ClassID) + ', Manufacturer = ' + SqlQ(Trim(AManufacturer)) + ', MPN = ' + SqlQ(Trim(AMPN)) + ', Series = ' + SqlQ(Trim(ASeries)) +
    ', Description = ' + SqlQ(ADescription) + ', Status = ' + SqlQ(AStatus) + ', Revision = ' + SqlQ(NextRevision(QueryText('select coalesce(Revision, '''') from Product where ProductID = ' +
    IntToStr(ProductID)))) + ', Modified = datetime(''now'') WHERE ProductID = ' + IntToStr(ProductID)]);
end;

{ ===========================================================================
  TPartsLibrary.DeleteProduct  (procedure)
  Parameters:
    ProductID: Int64 - the product
  Notes:
    Deletes the product with its ratings, suggestions, offers, documents, outlines and models. Other products that name it as their replacement or as a substitute
    lose that mention (the products themselves stay).
  =========================================================================== }
procedure TPartsLibrary.DeleteProduct(ProductID: Int64);
var
  Q: String;
begin
  if QueryInt('select count(*) from Product where ProductID = ' + IntToStr(ProductID)) = 0 then
    raise EPartsError.Create(rsTheProductIsNotIn);
  Q := IntToStr(ProductID);
  Mutate(['UPDATE Product SET ReplacedBy = NULL WHERE ReplacedBy = ' + Q, 'DELETE FROM Substitute WHERE ProductID = ' + Q + ' OR SubstituteID = ' + Q,
    'DELETE FROM Product WHERE ProductID = ' + Q]);
end;

{ ===========================================================================
  TPartsLibrary.ProductAppliesSql  (function)
  Parameters:
    const AAppliesTo: String - what a rating applies to
  Returns:
    String - 'NULL' for the whole product; for 'kind:Name' the quoted text with the kind's own spelling; otherwise the quoted object name
  Notes:
    Raises EPartsError for a 'kind:' that names no kind of the library. An object name cannot be checked (the product is not tied to one part).
  =========================================================================== }
function TPartsLibrary.ProductAppliesSql(const AAppliesTo: String): String;
var
  T, K: String;
begin
  T := Trim(AAppliesTo);
  if T = '' then
    Exit('NULL');
  if SameText(Copy(T, 1, 5), 'kind:') then
  begin
    K := QueryText('select Name from ObjectKind where lower(Name) = ' + SqlQ(LowerCase(Trim(Copy(T, 6, MaxInt)))));
    if K = '' then
      raise EPartsError.Create(Format(rsIsNotAKindOf, [Trim(Copy(T, 6, MaxInt))]));
    Exit(SqlQ('kind:' + K));
  end;
  Result := SqlQ(T);
end;

{ ===========================================================================
  TPartsLibrary.AddProductRating  (function)
  Parameters:
    ProductID: Int64 - the product
    const AAppliesTo: String - '' for the whole product, an object's name ('Pole 1'), or 'kind:Contact' for every object of that kind
    const AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double - as for AddRating
  Returns:
    Int64 - the new RatingID
  Notes:
    What the product is actually rated for (a part's requirement is compared with it by quantity, condition and object). Same value rules as AddRating; a second rating
    for the same target, quantity and condition is refused. The product's Revision goes up and Modified is stamped.
  =========================================================================== }
function TPartsLibrary.AddProductRating(ProductID: Int64; const AAppliesTo, AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double): Int64;
var
  QUnit, Vals, App: String;
begin
  if QueryInt('select count(*) from Product where ProductID = ' + IntToStr(ProductID)) = 0 then
    raise EPartsError.Create(rsTheProductIsNotIn);
  Vals := RatingValuesSql(AQuantity, AUnit, ACondition, HasMin, HasTyp, HasMax, AMin, ATyp, AMax, QUnit);
  App := ProductAppliesSql(AAppliesTo);
  if QueryInt('select count(*) from Rating where ProductID = ' + IntToStr(ProductID) + ' and AppliesTo is ' + App + ' and Quantity = ' + SqlQ(AQuantity) +
    ' and coalesce(Condition, '''') = ' + SqlQ(Trim(ACondition))) > 0 then
    raise EPartsError.Create(Format(rsTheProductAlreadyHasA, [AQuantity]));
  Mutate(['INSERT INTO Rating(ProductID, AppliesTo, Quantity, Min, Typ, Max, Unit, Condition) VALUES (' + IntToStr(ProductID) + ', ' + App + ', ' + Vals + ')',
    'UPDATE Product SET Revision = ' + SqlQ(NextRevision(QueryText('select coalesce(Revision, '''') from Product where ProductID = ' + IntToStr(ProductID)))) +
    ', Modified = datetime(''now'') WHERE ProductID = ' + IntToStr(ProductID)]);
  Result := QueryInt('select max(RatingID) from Rating where ProductID = ' + IntToStr(ProductID));
end;

{ ===========================================================================
  TPartsLibrary.UpdateProductRating  (procedure)
  Parameters:
    RatingID: Int64 - the product rating; the other parameters as for AddProductRating
  Notes:
    Changes a product's rating (not a part's requirement); the same rules, and it can be changed without clashing with itself.
  =========================================================================== }
procedure TPartsLibrary.UpdateProductRating(RatingID: Int64; const AAppliesTo, AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double);
var
  ProductID: Int64;
  QUnit, Vals, App: String;
begin
  ProductID := QueryInt('select coalesce(ProductID, 0) from Rating where RatingID = ' + IntToStr(RatingID));
  if ProductID = 0 then
    raise EPartsError.Create(rsThatRatingIsNotA);
  Vals := RatingValuesSql(AQuantity, AUnit, ACondition, HasMin, HasTyp, HasMax, AMin, ATyp, AMax, QUnit);
  App := ProductAppliesSql(AAppliesTo);
  if QueryInt('select count(*) from Rating where ProductID = ' + IntToStr(ProductID) + ' and RatingID <> ' + IntToStr(RatingID) + ' and AppliesTo is ' + App + ' and Quantity = ' +
    SqlQ(AQuantity) + ' and coalesce(Condition, '''') = ' + SqlQ(Trim(ACondition))) > 0 then
    raise EPartsError.Create(Format(rsTheProductAlreadyHasA, [AQuantity]));
  Mutate(['UPDATE Rating SET AppliesTo = ' + App + ', (Quantity, Min, Typ, Max, Unit, Condition) = (' + Vals + ') WHERE RatingID = ' + IntToStr(RatingID),
    'UPDATE Product SET Revision = ' + SqlQ(NextRevision(QueryText('select coalesce(Revision, '''') from Product where ProductID = ' + IntToStr(ProductID)))) +
    ', Modified = datetime(''now'') WHERE ProductID = ' + IntToStr(ProductID)]);
end;

{ ===========================================================================
  TPartsLibrary.DeleteProductRating  (procedure)
  Parameters:
    RatingID: Int64 - the product rating
  Notes:
    Deletes a product's rating; the product's Revision goes up.
  =========================================================================== }
procedure TPartsLibrary.DeleteProductRating(RatingID: Int64);
var
  ProductID: Int64;
begin
  ProductID := QueryInt('select coalesce(ProductID, 0) from Rating where RatingID = ' + IntToStr(RatingID));
  if ProductID = 0 then
    raise EPartsError.Create(rsThatRatingIsNotA);
  Mutate(['DELETE FROM Rating WHERE RatingID = ' + IntToStr(RatingID), 'UPDATE Product SET Revision = ' + SqlQ(NextRevision(QueryText('select coalesce(Revision, '''') from Product where ProductID = ' +
    IntToStr(ProductID)))) + ', Modified = datetime(''now'') WHERE ProductID = ' + IntToStr(ProductID)]);
end;

{ ===========================================================================
  TPartsLibrary.FieldValueText  (function)
  Parameters:
    const FieldType: String - text, int, real, bool, enum or ref
    ValueNum: Double; const ValueText: String - the stored columns
  Returns:
    String - the value as a person reads it: numbers with a point and no trailing zeros, bool as yes / no
  =========================================================================== }
function TPartsLibrary.FieldValueText(const FieldType: String; ValueNum: Double; const ValueText: String): String;
var
  F: TFormatSettings;
begin
  F := DefaultFormatSettings;
  F.DecimalSeparator := '.';
  if (FieldType = 'int') or (FieldType = 'real') then
    Result := FloatToStrF(ValueNum, ffGeneral, 12, 0, F)
  else if FieldType = 'bool' then
  begin
    if ValueNum <> 0 then
      Result := 'yes'
    else
      Result := 'no';
  end
  else
    Result := ValueText;
end;

{ ===========================================================================
  TPartsLibrary.FieldValues  (function)
  Parameters:
    PartID: Int64 - the part
  Returns:
    TValueRowArray - one row for every field the part can hold a value for: first the fields of its class (own and inherited, ancestors first; ObjectID 0), then for each
    child object, in the part's order, the fields of its kind (the kind's ancestors' first). HasValue says whether a value is stored; ValueText shows it.
  =========================================================================== }
function TPartsLibrary.FieldValues(PartID: Int64): TValueRowArray;
var
  Idx, i, N: Integer;
  Fields: TFieldInfoArray;
  Objs: TObjectRefArray;

  procedure Fetch(const Sql: String; KeyId: Int64; const ObjName: String; FieldId: Int64; const FType: String; var Row: TValueRow);
  var
    St: Psqlite3_stmt;
  begin
    St := Prepare(Sql);
    try
      sqlite3_bind_int64(St, 1, KeyId);
      sqlite3_bind_int64(St, 2, FieldId);
      Row.HasValue := sqlite3_step(St) = SQLITE_ROW;
      if Row.HasValue then
        Row.ValueText := FieldValueText(FType, sqlite3_column_double(St, 0), ColText(St, 1))
      else
        Row.ValueText := '';
    finally
      sqlite3_finalize(St);
    end;
  end;

  procedure AddRow(ObjId: Int64; const ObjName: String; FieldId: Int64; const AName, AType, AUnit, AEnum, ADecl: String; AReq: Boolean);
  begin
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N] := Default(TValueRow);
    Result[N].ObjectID := ObjId;
    Result[N].ObjectName := ObjName;
    Result[N].FieldID := FieldId;
    Result[N].FieldName := AName;
    Result[N].FieldType := AType;
    Result[N].Unit_ := AUnit;
    Result[N].EnumValues := AEnum;
    Result[N].DeclaredBy := ADecl;
    Result[N].Required := AReq;
    if ObjId = 0 then
      Fetch('select ValueNum, ValueText from PartValue where PartID = ? and FieldID = ?', PartID, ObjName, FieldId, AType, Result[N])
    else
      Fetch('select ValueNum, ValueText from ObjectValue where ObjectID = ? and FieldID = ?', ObjId, ObjName, FieldId, AType, Result[N]);
  end;

  procedure KindFieldsOf(ObjId: Int64; const ObjName: String; KindId: Int64);
  var
    St: Psqlite3_stmt;
    Tmp: array of TValueRow;
    j: Integer;
  begin
    SetLength(Tmp, 0);
    St := Prepare('select f.FieldID, f.Name, f.Type, coalesce(f.Unit, ''''), coalesce(f.EnumValues, ''''), f.Required, k.Name from KindAncestors a join KindFieldDef f on f.KindID = a.AncestorID ' +
      'join ObjectKind k on k.KindID = f.KindID where a.KindID = ' + IntToStr(KindId) + ' order by a.Depth desc, f.FieldID');
    try
      while sqlite3_step(St) = SQLITE_ROW do
      begin
        j := Length(Tmp);
        SetLength(Tmp, j + 1);
        Tmp[j] := Default(TValueRow);
        Tmp[j].FieldID := sqlite3_column_int64(St, 0);
        Tmp[j].FieldName := ColText(St, 1);
        Tmp[j].FieldType := ColText(St, 2);
        Tmp[j].Unit_ := ColText(St, 3);
        Tmp[j].EnumValues := ColText(St, 4);
        Tmp[j].Required := sqlite3_column_int(St, 5) <> 0;
        Tmp[j].DeclaredBy := ColText(St, 6);
      end;
    finally
      sqlite3_finalize(St);
    end;
    for j := 0 to High(Tmp) do
      AddRow(ObjId, ObjName, Tmp[j].FieldID, Tmp[j].FieldName, Tmp[j].FieldType, Tmp[j].Unit_, Tmp[j].EnumValues, Tmp[j].DeclaredBy, Tmp[j].Required);
  end;
begin
  SetLength(Result, 0);
  Idx := PartIndexOfID(PartID);
  if Idx < 0 then
    Exit;
  Fields := ClassFieldList(FParts[Idx].ClassID);
  for i := 0 to High(Fields) do
    AddRow(0, '', Fields[i].ID, Fields[i].Name, Fields[i].FieldType, Fields[i].Unit_, Fields[i].EnumValues, Fields[i].DeclaredBy, Fields[i].Required);
  Objs := PartObjects(PartID);
  for i := 0 to High(Objs) do
    KindFieldsOf(Objs[i].ID, Objs[i].Name, Objs[i].KindID);
end;

{ ===========================================================================
  TPartsLibrary.SetFieldValue  (procedure)
  Parameters:
    PartID: Int64 - the part
    ObjectID: Int64 - 0 for a field of the part's class, else a child object of the part (a field of its kind)
    FieldID: Int64 - the field (FieldValues gives it)
    const AValue: String - the value as typed; empty removes the stored value
  Notes:
    Stores the value in the column its type uses (int, real and bool as a number, the rest as text). int must be a whole number; real accepts a point or a comma; bool takes
    yes / no / true / false / 1 / 0 in any case; enum must be one of the field's values (stored with the field's spelling). Refused (nothing changes): a field the part's class
    (or the object's kind) does not have, an object of another part, a wrong value. The part's Revision goes up by one and Modified is stamped. A required field can be emptied
    (the list marks it); nothing else depends on it yet.
  =========================================================================== }
procedure TPartsLibrary.SetFieldValue(PartID, ObjectID, FieldID: Int64; const AValue: String);
var
  Idx: Integer;
  FType, Enum, T, Canon, Cols, Where, Tbl, Keys, Item: String;
  V: Double;
  Items: TStringList;
  k: Integer;
  Num: Boolean;
  F: TFormatSettings;
begin
  Idx := PartIndexOfID(PartID);
  if Idx < 0 then
    raise EPartsError.Create(rsThePartIsNotIn);
  if ObjectID = 0 then
  begin
    if QueryInt('select count(*) from ClassFields where ClassID = ' + IntToStr(FParts[Idx].ClassID) + ' and FieldID = ' + IntToStr(FieldID)) = 0 then
      raise EPartsError.Create(rsThatFieldIsNotA);
    FType := QueryText('select Type from FieldDef where FieldID = ' + IntToStr(FieldID));
    Enum := QueryText('select coalesce(EnumValues, '''') from FieldDef where FieldID = ' + IntToStr(FieldID));
    Tbl := 'PartValue';
    Keys := 'PartID, FieldID';
    Where := 'PartID = ' + IntToStr(PartID) + ' AND FieldID = ' + IntToStr(FieldID);
    Cols := IntToStr(PartID) + ', ' + IntToStr(FieldID);
  end
  else
  begin
    if QueryInt('select count(*) from PartObject where ObjectID = ' + IntToStr(ObjectID) + ' and PartID = ' + IntToStr(PartID)) = 0 then
      raise EPartsError.Create(rsThatObjectIsNotAn);
    if QueryInt('select count(*) from PartObject o join KindFields kf on kf.KindID = o.KindID where o.ObjectID = ' + IntToStr(ObjectID) + ' and kf.FieldID = ' + IntToStr(FieldID)) = 0 then
      raise EPartsError.Create(rsThatFieldIsNotA2);
    FType := QueryText('select Type from KindFieldDef where FieldID = ' + IntToStr(FieldID));
    Enum := QueryText('select coalesce(EnumValues, '''') from KindFieldDef where FieldID = ' + IntToStr(FieldID));
    Tbl := 'ObjectValue';
    Keys := 'ObjectID, FieldID';
    Where := 'ObjectID = ' + IntToStr(ObjectID) + ' AND FieldID = ' + IntToStr(FieldID);
    Cols := IntToStr(ObjectID) + ', ' + IntToStr(FieldID);
  end;
  T := Trim(AValue);
  if T = '' then
  begin
    Mutate(['DELETE FROM ' + Tbl + ' WHERE ' + Where, 'UPDATE Part SET Revision = ' + SqlQ(RevisionAfter(Idx)) + ', Modified = datetime(''now'') WHERE PartID = ' + IntToStr(PartID)]);
    Exit;
  end;
  F := DefaultFormatSettings;
  F.DecimalSeparator := '.';
  Num := True;
  V := 0;
  Canon := T;
  if FType = 'int' then
  begin
    if (not TryStrToFloat(StringReplace(T, ',', '.', []), V, F)) or (Frac(V) <> 0) then
      raise EPartsError.Create(Format(rsIsNotAWholeNumber, [T]));
  end
  else if FType = 'real' then
  begin
    if not TryStrToFloat(StringReplace(T, ',', '.', []), V, F) then
      raise EPartsError.Create(Format(rsIsNotANumber, [T]));
  end
  else if FType = 'bool' then
  begin
    if SameText(T, 'yes') or SameText(T, 'true') or (T = '1') then
      V := 1
    else if SameText(T, 'no') or SameText(T, 'false') or (T = '0') then
      V := 0
    else
      raise EPartsError.Create(Format(rsIsNotYesOrNo, [T]));
  end
  else
  begin
    Num := False;
    if FType = 'enum' then
    begin
      Items := TStringList.Create;
      try
        Items.Delimiter := ',';
        Items.StrictDelimiter := True;
        Items.DelimitedText := Enum;
        Canon := '';
        for k := 0 to Items.Count - 1 do
        begin
          Item := Trim(Items[k]);
          if SameText(Item, T) then
            Canon := Item;
        end;
      finally
        Items.Free;
      end;
      if Canon = '' then
        raise EPartsError.Create(Format(rsIsNotOneOf, [T, Enum]));
    end;
  end;
  if Num then
    Mutate(['INSERT OR REPLACE INTO ' + Tbl + '(' + Keys + ', ValueNum, ValueText) VALUES (' + Cols + ', ' + SqlFloat(V) + ', NULL)',
      'UPDATE Part SET Revision = ' + SqlQ(RevisionAfter(Idx)) + ', Modified = datetime(''now'') WHERE PartID = ' + IntToStr(PartID)])
  else
    Mutate(['INSERT OR REPLACE INTO ' + Tbl + '(' + Keys + ', ValueNum, ValueText) VALUES (' + Cols + ', NULL, ' + SqlQ(Canon) + ')',
      'UPDATE Part SET Revision = ' + SqlQ(RevisionAfter(Idx)) + ', Modified = datetime(''now'') WHERE PartID = ' + IntToStr(PartID)]);
end;

procedure TPartsLibrary.Reread;
begin
  LoadAll;
end;

{ ===========================================================================
  TPartsLibrary.BeginTx / CommitTx / RollbackTx  (procedures)
  Notes:
    The transaction of one edit. During an import (FBatch > 0) the whole import is the transaction, so these do nothing and an error is left to the import to roll back.
  =========================================================================== }
procedure TPartsLibrary.BeginTx;
begin
  if FBatch = 0 then
    Exec('BEGIN');
end;

procedure TPartsLibrary.CommitTx;
begin
  if FBatch = 0 then
    Exec('COMMIT');
end;

procedure TPartsLibrary.RollbackTx;
begin
  if FBatch = 0 then
    sqlite3_exec(FDb, 'ROLLBACK', nil, nil, nil);
end;

{ ===========================================================================
  ParseCsvText  (function)
  Parameters:
    const Text: String - CSV text (UTF-8, a leading byte order mark is ignored)
  Returns:
    TStringRows - the records, each an array of fields
  Notes:
    RFC 4180 quoting: fields may be quoted, a doubled quote is a quote, quoted fields may hold the delimiter and line breaks. The delimiter is the first of comma, semicolon or tab
    found in the first line outside quotes (comma when none). Empty lines are skipped.
  =========================================================================== }
function ParseCsvText(const Text: String): TStringRows;
var
  i, N: Integer;
  Delim: Char;
  InQ, Started: Boolean;
  Field, S: String;
  Row: TStringRow;
  procedure EndField;
  begin
    SetLength(Row, Length(Row) + 1);
    Row[High(Row)] := Field;
    Field := '';
    Started := False;
  end;
  procedure EndRow;
  begin
    if (Length(Row) > 1) or ((Length(Row) = 1) and (Trim(Row[0]) <> '')) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Row;
    end;
    SetLength(Row, 0);
  end;
begin
  SetLength(Result, 0);
  S := Text;
  if Copy(S, 1, 3) = #$EF#$BB#$BF then
    Delete(S, 1, 3);
  Delim := ',';
  InQ := False;
  for i := 1 to Length(S) do
  begin
    if S[i] = '"' then
      InQ := not InQ
    else if (not InQ) and (S[i] in [#10, #13]) then
      Break
    else if (not InQ) and (S[i] in [',', ';', #9]) then
    begin
      Delim := S[i];
      Break;
    end;
  end;
  InQ := False;
  Started := False;
  Field := '';
  SetLength(Row, 0);
  N := Length(S);
  i := 1;
  while i <= N do
  begin
    if InQ then
    begin
      if S[i] = '"' then
      begin
        if (i < N) and (S[i + 1] = '"') then
        begin
          Field := Field + '"';
          Inc(i);
        end
        else
          InQ := False;
      end
      else
        Field := Field + S[i];
    end
    else if (S[i] = '"') and (not Started) then
    begin
      InQ := True;
      Started := True;
    end
    else if S[i] = Delim then
      EndField
    else if S[i] = #13 then
    begin
      if (i < N) and (S[i + 1] = #10) then
        Inc(i);
      EndField;
      EndRow;
    end
    else if S[i] = #10 then
    begin
      EndField;
      EndRow;
    end
    else
    begin
      Field := Field + S[i];
      Started := True;
    end;
    Inc(i);
  end;
  if (Field <> '') or (Length(Row) > 0) then
  begin
    EndField;
    EndRow;
  end;
end;

function CsvQuote(const S: String): String;
begin
  if (Pos(',', S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0) or (Pos(#13, S) > 0) or (Pos(';', S) > 0) or (S <> Trim(S)) then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

{ ===========================================================================
  TPartsLibrary.ImportProductsCsv  (function)
  Parameters:
    const Text: String - the CSV text; first line = column names
  Returns:
    TProductImportResult - products added / changed, ratings added / changed, suggestions made or changed
  Notes:
    One line per product, or per rating of a product (repeat Manufacturer and MPN): columns Manufacturer and MPN (required, any case; together they name the product), Series,
    Class (the class name; required for a product that is not in the library yet, or the class of the Part), Status (active when empty), Description, Part (the generic part to suggest
    the product for), Preferred (yes / no: the product is the part's preferred one), Quantity, Unit, Condition, AppliesTo (empty, an object name or kind:Name), Min, Typ, Max (a comma is
    accepted as the decimal mark). A product that is in the library has its non-empty Series, Class, Status and Description changed; a rating with the same AppliesTo, Quantity
    and Condition is replaced, otherwise added. The edits are those of the editor (same rules and messages). All or nothing: an error raises EPartsError "Line n: reason" and the
    file is unchanged.
  =========================================================================== }
function TPartsLibrary.ImportProductsCsv(const Text: String): TProductImportResult;
const
  Known: array[0..14] of String = ('manufacturer', 'mpn', 'series', 'class', 'status', 'description', 'part', 'preferred', 'quantity', 'unit', 'condition', 'appliesto', 'min', 'typ', 'max');
var
  Rows: TStringRows;
  Col: array[0..14] of Integer;
  i, j, k, LineNo: Integer;
  H: String;
  Seen: array of Int64;
  function Cell(const R: TStringRow; Idx: Integer): String;
  begin
    if (Col[Idx] >= 0) and (Col[Idx] < Length(R)) then
      Result := Trim(R[Col[Idx]])
    else
      Result := '';
  end;
  function Num(const S, What: String; out Has: Boolean): Double;
  var
    F: TFormatSettings;
  begin
    Has := Trim(S) <> '';
    Result := 0;
    if not Has then
      Exit;
    F := DefaultFormatSettings;
    F.DecimalSeparator := '.';
    if not TryStrToFloat(StringReplace(Trim(S), ',', '.', []), Result, F) then
      raise EPartsError.Create(Format(rsIsNotANumber2, [S, What]));
  end;
  function Yes(const S: String): Boolean;
  begin
    Result := SameText(S, 'yes') or SameText(S, 'true') or (S = '1') or SameText(S, 'y');
  end;
  function SeenBefore(Pid: Int64): Boolean;
  var
    n: Integer;
  begin
    Result := False;
    for n := 0 to High(Seen) do
      if Seen[n] = Pid then
        Result := True;
  end;
  procedure Remember(Pid: Int64);
  begin
    SetLength(Seen, Length(Seen) + 1);
    Seen[High(Seen)] := Pid;
  end;
  procedure OneLine(const R: TStringRow);
  var
    Man, Mpn, Ser, Cls, Stat, Desc, PartN, Pref, Qty, Cond, App, Un: String;
    Pid, Cid, RatId, Part: Int64;
    PRow: TProductRow;
    HasMin, HasTyp, HasMax: Boolean;
    VMin, VTyp, VMax: Double;
    Cnt, State, Want, n: Integer;
    Rs: TProductRowArray;
  begin
    Man := Cell(R, 0);
    Mpn := Cell(R, 1);
    Ser := Cell(R, 2);
    Cls := Cell(R, 3);
    Stat := LowerCase(Cell(R, 4));
    Desc := Cell(R, 5);
    PartN := Cell(R, 6);
    Pref := Cell(R, 7);
    Qty := Cell(R, 8);
    Un := Cell(R, 9);
    Cond := Cell(R, 10);
    App := Cell(R, 11);
    if Man = '' then
      raise EPartsError.Create(rsTheManufacturerIsEmpty);
    if Mpn = '' then
      raise EPartsError.Create(rsTheModelNumberMPNIs);
    Part := 0;
    if PartN <> '' then
    begin
      Cnt := QueryInt('select count(*) from Part where lower(Name) = ' + SqlQ(LowerCase(PartN)));
      if Cnt = 0 then
        raise EPartsError.Create(Format(rsIsNotAPartOf, [PartN]));
      if Cnt > 1 then
        raise EPartsError.Create(Format(rsNamesPartsOfMoreThan, [PartN]));
      Part := QueryInt('select PartID from Part where lower(Name) = ' + SqlQ(LowerCase(PartN)));
    end;
    Cid := 0;
    if Cls <> '' then
    begin
      Cid := QueryInt('select coalesce(max(ClassID), 0) from PartClass where lower(Name) = ' + SqlQ(LowerCase(Cls)));
      if Cid = 0 then
        raise EPartsError.Create(Format(rsIsNotAClassOf, [Cls]));
    end
    else if Part <> 0 then
      Cid := QueryInt('select ClassID from Part where PartID = ' + IntToStr(Part));
    Pid := QueryInt('select coalesce(max(ProductID), 0) from Product where lower(Manufacturer) = ' + SqlQ(LowerCase(Man)) + ' and lower(MPN) = ' + SqlQ(LowerCase(Mpn)));
    if Pid = 0 then
    begin
      if Cid = 0 then
        raise EPartsError.Create(Format(rsTheProductIsNewSo, [Man, Mpn]));
      if Stat = '' then
        Stat := 'active';
      Pid := AddProduct(Cid, Man, Mpn, Ser, Desc, Stat);
      Remember(Pid);
      Inc(Result.ProductsAdded);
    end
    else
    begin
      if (Ser <> '') or (Cls <> '') or (Stat <> '') or (Desc <> '') then
      begin
        Rs := ProductRows;
        PRow := Default(TProductRow);
        for n := 0 to High(Rs) do
          if Rs[n].ID = Pid then
            PRow := Rs[n];
        if Ser = '' then
          Ser := PRow.Series;
        if Desc = '' then
          Desc := PRow.Description;
        if Stat = '' then
          Stat := PRow.Status;
        if Cid = 0 then
          Cid := PRow.ClassID;
        if (Ser <> PRow.Series) or (Desc <> PRow.Description) or (Stat <> PRow.Status) or (Cid <> PRow.ClassID) then
        begin
          UpdateProduct(Pid, Cid, PRow.Manufacturer, PRow.MPN, Ser, Desc, Stat);
          if not SeenBefore(Pid) then
            Inc(Result.ProductsUpdated);
        end;
      end;
      Remember(Pid);
    end;
    VMin := Num(Cell(R, 12), 'minimum', HasMin);
    VTyp := Num(Cell(R, 13), 'typical', HasTyp);
    VMax := Num(Cell(R, 14), 'maximum', HasMax);
    if Qty <> '' then
    begin
      RatId := QueryInt('select coalesce(max(RatingID), 0) from Rating where ProductID = ' + IntToStr(Pid) + ' and AppliesTo is ' + ProductAppliesSql(App) + ' and Quantity = ' +
        SqlQ(Qty) + ' and coalesce(Condition, '''') = ' + SqlQ(Cond));
      if RatId = 0 then
      begin
        AddProductRating(Pid, App, Qty, Un, Cond, HasMin, HasTyp, HasMax, VMin, VTyp, VMax);
        Inc(Result.RatingsAdded);
      end
      else
      begin
        UpdateProductRating(RatId, App, Qty, Un, Cond, HasMin, HasTyp, HasMax, VMin, VTyp, VMax);
        Inc(Result.RatingsUpdated);
      end;
    end
    else if HasMin or HasTyp or HasMax or (Cond <> '') or (App <> '') or (Un <> '') then
      raise EPartsError.Create(rsARatingNeedsAQuantity);
    if Part <> 0 then
    begin
      Want := 0;
      if Yes(Pref) then
        Want := 1;
      State := SuggestionState(Part, Pid);
      if (State <> Want) and (not ((State = 1) and (Pref = ''))) then
      begin
        SetSuggestion(Part, Pid, Want);
        Inc(Result.Suggestions);
      end;
    end;
  end;
begin
  Result := Default(TProductImportResult);
  SetLength(Seen, 0);
  LineNo := 1;
  if FDb = nil then
    raise EPartsError.Create(rsNoPartsLibraryIsOpen);
  Rows := ParseCsvText(Text);
  if Length(Rows) = 0 then
    raise EPartsError.Create(rsTheFileHasNoLines);
  for k := 0 to High(Col) do
    Col[k] := -1;
  for j := 0 to High(Rows[0]) do
  begin
    H := LowerCase(Trim(Rows[0][j]));
    k := -1;
    for i := 0 to High(Known) do
      if Known[i] = H then
        k := i;
    if k < 0 then
      raise EPartsError.Create(Format(rsLineIsNotAColumn, [Trim(Rows[0][j])]));
    if Col[k] >= 0 then
      raise EPartsError.Create(Format(rsLineTheColumnIsThere, [Trim(Rows[0][j])]));
    Col[k] := j;
  end;
  if (Col[0] < 0) or (Col[1] < 0) then
    raise EPartsError.Create(rsLineTheColumnsManufacturerAnd);
  Inc(FBatch);
  Exec('BEGIN');
  try
    for i := 1 to High(Rows) do
    begin
      LineNo := i + 1;
      OneLine(Rows[i]);
    end;
    Touch;
    Exec('COMMIT');
  except
    on E: Exception do
    begin
      sqlite3_exec(FDb, 'ROLLBACK', nil, nil, nil);
      Dec(FBatch);
      LoadAll;
      raise EPartsError.Create(Format(rsLine, [LineNo, E.Message]));
    end;
  end;
  Dec(FBatch);
  LoadAll;
end;

{ ===========================================================================
  TPartsLibrary.ExportProductsCsv  (function)
  Returns:
    String - every product as CSV text in the layout ImportProductsCsv reads: a line per rating (a product without ratings: one line), then a line per suggestion (Part, Preferred)
  Notes:
    Importing the text into a library with the same classes and parts gives the same products, ratings and suggestions.
  =========================================================================== }
function TPartsLibrary.ExportProductsCsv: String;
var
  Pr: TProductRowArray;
  Rt: TPartRatingArray;
  i, j: Integer;
  St: Psqlite3_stmt;
  function Base(const P: TProductRow): String;
  begin
    Result := CsvQuote(P.Manufacturer) + ',' + CsvQuote(P.MPN) + ',' + CsvQuote(P.Series) + ',' + CsvQuote(P.ClassName) + ',' + CsvQuote(P.Status) + ',' + CsvQuote(P.Description);
  end;
  function N(Has: Boolean; X: Double): String;
  begin
    if Has then
      Result := SqlFloat(X)
    else
      Result := '';
  end;
begin
  Result := 'Manufacturer,MPN,Series,Class,Status,Description,Part,Preferred,Quantity,Unit,Condition,AppliesTo,Min,Typ,Max' + LineEnding;
  Pr := ProductRows;
  for i := 0 to High(Pr) do
  begin
    Rt := ProductRatings(Pr[i].ID);
    if Length(Rt) = 0 then
      Result := Result + Base(Pr[i]) + ',,,,,,,,,' + LineEnding;
    for j := 0 to High(Rt) do
      Result := Result + Base(Pr[i]) + ',,,' + CsvQuote(Rt[j].Quantity) + ',' + CsvQuote(Rt[j].Unit_) + ',' + CsvQuote(Rt[j].Condition) + ',' + CsvQuote(Rt[j].ObjectName) + ',' +
        N(Rt[j].HasMin, Rt[j].Min) + ',' + N(Rt[j].HasTyp, Rt[j].Typ) + ',' + N(Rt[j].HasMax, Rt[j].Max) + LineEnding;
    St := Prepare('select p.Name, pp.Preferred from PartProduct pp join Part p using(PartID) where pp.ProductID = ? order by p.PartID');
    try
      sqlite3_bind_int64(St, 1, Pr[i].ID);
      while sqlite3_step(St) = SQLITE_ROW do
      begin
        Result := Result + Base(Pr[i]) + ',' + CsvQuote(ColText(St, 0)) + ',';
        if sqlite3_column_int(St, 1) <> 0 then
          Result := Result + 'yes'
        else
          Result := Result + 'no';
        Result := Result + ',,,,,,,' + LineEnding;
      end;
    finally
      sqlite3_finalize(St);
    end;
  end;
end;

{ ===========================================================================
  TPartsLibrary.SymbolRows  (function)
  Parameters:
    PartID: Int64 - the part
  Returns:
    TSymbolRowArray - the part's symbols (id, standard, purpose, name, size of the drawing in bytes, whether it is the part's default), in the order they were made
  =========================================================================== }
function TPartsLibrary.SymbolRows(PartID: Int64): TSymbolRowArray;
var
  St: Psqlite3_stmt;
  N: Integer;
begin
  SetLength(Result, 0);
  St := Prepare('select s.SymbolID, s.Standard, s.Purpose, coalesce(s.Name, ''''), length(s.Drawing), s.SymbolID = coalesce(p.BaseDefault, 0) from Symbol s join Part p using(PartID) where s.PartID = ? order by s.SymbolID');
  try
    sqlite3_bind_int64(St, 1, PartID);
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N].ID := sqlite3_column_int64(St, 0);
      Result[N].Standard := ColText(St, 1);
      Result[N].Purpose := ColText(St, 2);
      Result[N].Name := ColText(St, 3);
      Result[N].Bytes := sqlite3_column_int(St, 4);
      Result[N].IsDefault := sqlite3_column_int(St, 5) <> 0;
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.SymbolDrawing  (function)
  Parameters:
    SymbolID: Int64 - a symbol of the library
  Returns:
    String - its drawing (TinyCAD symbol XML), '' when there is no such symbol
  =========================================================================== }
function TPartsLibrary.SymbolDrawing(SymbolID: Int64): String;
var
  St: Psqlite3_stmt;
  P: Pointer;
begin
  Result := '';
  St := Prepare('select Drawing from Symbol where SymbolID = ?');
  try
    sqlite3_bind_int64(St, 1, SymbolID);
    if sqlite3_step(St) = SQLITE_ROW then
    begin
      P := sqlite3_column_blob(St, 0);
      SetLength(Result, sqlite3_column_bytes(St, 0));
      if Length(Result) > 0 then
        Move(P^, Result[1], Length(Result));
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.SymbolPartID  (function)
  Parameters:
    SymbolID: Int64 - a symbol
  Returns:
    Int64 - the part it belongs to, 0 when there is no such symbol
  =========================================================================== }
function TPartsLibrary.SymbolPartID(SymbolID: Int64): Int64;
begin
  Result := QueryInt('select coalesce(PartID, 0) from Symbol where SymbolID = ' + IntToStr(SymbolID));
end;

{ ===========================================================================
  TPartsLibrary.CheckSymbolInfo  (procedure)
  Parameters:
    const AStandard, APurpose: String - drawing standard (IEC, ANSI ...) and purpose
  Notes:
    Raises EPartsError when the standard is empty or the purpose is not schematic, oneline, panel or block.
  =========================================================================== }
procedure TPartsLibrary.CheckSymbolInfo(const AStandard, APurpose: String);
begin
  if Trim(AStandard) = '' then
    raise EPartsError.Create(rsTheSymbolNeedsADrawing);
  if (APurpose <> 'schematic') and (APurpose <> 'oneline') and (APurpose <> 'panel') and (APurpose <> 'block') then
    raise EPartsError.Create(rsThePurposeMustBeSchematic);
end;

{ ===========================================================================
  TPartsLibrary.BindDrawingSql  (function)
  Parameters:
    const Sql: String - a statement with one ? for the drawing
    const Blob: String - the drawing
  Notes:
    Runs the statement with the drawing bound as a blob, inside the transaction the caller has open (see AddSymbol).
  =========================================================================== }
procedure TPartsLibrary.RunWithBlob(const Sql, Blob: String);
var
  St: Psqlite3_stmt;
begin
  St := Prepare(Sql);
  try
    if Length(Blob) > 0 then
      sqlite3_bind_blob(St, 1, @Blob[1], Length(Blob), sqlite3_destructor_type(-1))
    else
      sqlite3_bind_zeroblob(St, 1, 0);
    if sqlite3_step(St) <> SQLITE_DONE then
      raise EPartsError.Create(rsTheSymbolCouldNotBe);
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.AddSymbol  (function)
  Parameters:
    PartID: Int64 - the part
    const AStandard, APurpose, AName: String - drawing standard, purpose (schematic, oneline, panel, block), name (empty takes the part's)
    const ABlob: String - the drawing: TinyCAD symbol XML, as a .TCLib keeps it
  Returns:
    Int64 - the new SymbolID
  Notes:
    Adds a symbol to the part. The first schematic symbol of a part becomes its default. The part's Revision goes up and Modified is stamped. Raises EPartsError (nothing changes)
    for an empty drawing, an unknown purpose or an empty standard. Whether the text is a symbol the loader reads is for the caller (the editor checks it).
  =========================================================================== }
function TPartsLibrary.AddSymbol(PartID: Int64; const AStandard, APurpose, AName, ABlob: String): Int64;
var
  Idx: Integer;
  Nm: String;
begin
  Idx := PartIndexOfID(PartID);
  if Idx < 0 then
    raise EPartsError.Create(rsThePartIsNotIn);
  CheckSymbolInfo(AStandard, APurpose);
  if ABlob = '' then
    raise EPartsError.Create(rsTheSymbolHasNoDrawing);
  Nm := Trim(AName);
  if Nm = '' then
    Nm := FParts[Idx].Name;
  BeginTx;
  try
    RunWithBlob('INSERT INTO Symbol(PartID, Standard, Purpose, Name, Drawing) VALUES (' + IntToStr(PartID) + ', ' + SqlQ(Trim(AStandard)) + ', ' + SqlQ(APurpose) + ', ' + SqlQ(Nm) + ', ?)', ABlob);
    Result := sqlite3_last_insert_rowid(FDb);
    Exec('UPDATE Part SET BaseDefault = ' + IntToStr(Result) + ' WHERE PartID = ' + IntToStr(PartID) + ' AND BaseDefault IS NULL AND ' + SqlQ(APurpose) + ' = ''schematic''');
    Exec('UPDATE Part SET Revision = ' + SqlQ(RevisionAfter(Idx)) + ', Modified = datetime(''now'') WHERE PartID = ' + IntToStr(PartID));
    Touch;
    CommitTx;
  except
    on E: Exception do
    begin
      RollbackTx;
      raise EPartsError.Create(E.Message);
    end;
  end;
  LoadAll;
end;

{ ===========================================================================
  TPartsLibrary.UpdateSymbolDrawing  (procedure)
  Parameters:
    SymbolID: Int64 - the symbol
    const ABlob: String - its new drawing
  Notes:
    Replaces the drawing (the symbol editor storing its work). Pin assignments to the part's objects stay. The part's Revision goes up. Refused for an empty drawing.
  =========================================================================== }
procedure TPartsLibrary.UpdateSymbolDrawing(SymbolID: Int64; const ABlob: String);
var
  PartID: Int64;
  Idx: Integer;
begin
  PartID := QueryInt('select coalesce(PartID, 0) from Symbol where SymbolID = ' + IntToStr(SymbolID));
  Idx := PartIndexOfID(PartID);
  if Idx < 0 then
    raise EPartsError.Create(rsThatSymbolIsNotIn);
  if ABlob = '' then
    raise EPartsError.Create(rsTheSymbolHasNoDrawing);
  BeginTx;
  try
    RunWithBlob('UPDATE Symbol SET Drawing = ? WHERE SymbolID = ' + IntToStr(SymbolID), ABlob);
    Exec('UPDATE Part SET Revision = ' + SqlQ(RevisionAfter(Idx)) + ', Modified = datetime(''now'') WHERE PartID = ' + IntToStr(PartID));
    Touch;
    CommitTx;
  except
    on E: Exception do
    begin
      RollbackTx;
      raise EPartsError.Create(E.Message);
    end;
  end;
  LoadAll;
end;

{ ===========================================================================
  TPartsLibrary.UpdateSymbolInfo  (procedure)
  Parameters:
    SymbolID: Int64 - the symbol
    const AStandard, APurpose, AName: String - as for AddSymbol
  Notes:
    Changes standard, purpose and name. The default symbol of a part must be a schematic one: changing the purpose of the default to anything else is refused (make
    another symbol the default first). The part's Revision goes up.
  =========================================================================== }
procedure TPartsLibrary.UpdateSymbolInfo(SymbolID: Int64; const AStandard, APurpose, AName: String);
var
  PartID: Int64;
  Idx: Integer;
begin
  PartID := QueryInt('select coalesce(PartID, 0) from Symbol where SymbolID = ' + IntToStr(SymbolID));
  Idx := PartIndexOfID(PartID);
  if Idx < 0 then
    raise EPartsError.Create(rsThatSymbolIsNotIn);
  CheckSymbolInfo(AStandard, APurpose);
  if (APurpose <> 'schematic') and (QueryInt('select count(*) from Part where BaseDefault = ' + IntToStr(SymbolID)) > 0) then
    raise EPartsError.Create(rsThisIsThePartS);
  Mutate(['UPDATE Symbol SET Standard = ' + SqlQ(Trim(AStandard)) + ', Purpose = ' + SqlQ(APurpose) + ', Name = ' + SqlQ(Trim(AName)) + ' WHERE SymbolID = ' + IntToStr(SymbolID),
    'UPDATE Part SET Revision = ' + SqlQ(RevisionAfter(Idx)) + ', Modified = datetime(''now'') WHERE PartID = ' + IntToStr(PartID)]);
end;

{ ===========================================================================
  TPartsLibrary.SetDefaultSymbol  (procedure)
  Parameters:
    PartID, SymbolID: Int64 - the part and one of its schematic symbols
  Notes:
    The symbol placed by default (Part.BaseDefault). Refused for a symbol of another part or one that is not a schematic one. The part's Revision goes up.
  =========================================================================== }
procedure TPartsLibrary.SetDefaultSymbol(PartID, SymbolID: Int64);
var
  Idx: Integer;
begin
  Idx := PartIndexOfID(PartID);
  if Idx < 0 then
    raise EPartsError.Create(rsThePartIsNotIn);
  if QueryInt('select count(*) from Symbol where SymbolID = ' + IntToStr(SymbolID) + ' and PartID = ' + IntToStr(PartID)) = 0 then
    raise EPartsError.Create(rsThatSymbolBelongsToAnother);
  if QueryText('select Purpose from Symbol where SymbolID = ' + IntToStr(SymbolID)) <> 'schematic' then
    raise EPartsError.Create(rsOnlyASchematicSymbolCan);
  Mutate(['UPDATE Part SET BaseDefault = ' + IntToStr(SymbolID) + ', Revision = ' + SqlQ(RevisionAfter(Idx)) + ', Modified = datetime(''now'') WHERE PartID = ' + IntToStr(PartID)]);
end;

{ ===========================================================================
  TPartsLibrary.DeleteSymbol  (procedure)
  Parameters:
    SymbolID: Int64 - the symbol
  Notes:
    Deletes the symbol with its pin assignments. If it was the part's default, the part's first other schematic symbol takes its place (none: the part has no default). The
    part's Revision goes up.
  =========================================================================== }
procedure TPartsLibrary.DeleteSymbol(SymbolID: Int64);
var
  PartID: Int64;
  Idx: Integer;
  S: String;
begin
  PartID := QueryInt('select coalesce(PartID, 0) from Symbol where SymbolID = ' + IntToStr(SymbolID));
  Idx := PartIndexOfID(PartID);
  if Idx < 0 then
    raise EPartsError.Create(rsThatSymbolIsNotIn);
  S := IntToStr(SymbolID);
  Mutate(['UPDATE Part SET BaseDefault = NULL WHERE BaseDefault = ' + S, 'DELETE FROM Symbol WHERE SymbolID = ' + S,
    'UPDATE Part SET BaseDefault = (SELECT min(SymbolID) FROM Symbol WHERE PartID = ' + IntToStr(PartID) + ' AND Purpose = ''schematic'') WHERE PartID = ' + IntToStr(PartID) + ' AND BaseDefault IS NULL',
    'UPDATE Part SET Revision = ' + SqlQ(RevisionAfter(Idx)) + ', Modified = datetime(''now'') WHERE PartID = ' + IntToStr(PartID)]);
end;

{ ===========================================================================
  TPartsLibrary.PartIndexOfID  (function)
  Parameters:
    PartID: Int64 - a part's row number in the file
  Returns:
    Integer - the index in Parts, -1 when there is none
  Notes:
    Finds a part by its PartID (the list is sorted, so the index changes when parts are added or renamed).
  =========================================================================== }
function TPartsLibrary.PartIndexOfID(PartID: Int64): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FParts) do
    if FParts[i].ID = PartID then
      Exit(i);
end;

{ ===========================================================================
  TPartsLibrary.AddPart  (function)
  Parameters:
    const AName: String - the part's name (not empty, unique within its class)
    AClassID: Int64 - the class (not an abstract one)
    const ARefPrefix: String - the reference letters ('K' gives K1, K2 ...)
    const ADescription: String - what it is
  Returns:
    Int64 - the new part's PartID
  Notes:
    Adds a generic part with a new GUID, status 'active', revision '1' and the Modified stamp, in one transaction. Raises EPartsError for an empty name, an unknown or
    abstract class, or a name the class has already.
  =========================================================================== }
function TPartsLibrary.AddPart(const AName: String; AClassID: Int64; const ARefPrefix, ADescription: String): Int64;
begin
  if Trim(AName) = '' then
    raise EPartsError.Create(rsThePartNeedsAName);
  if QueryInt('select count(*) from PartClass where ClassID = ' + IntToStr(AClassID) + ' and Abstract = 0') = 0 then
    raise EPartsError.Create(rsChooseAClassForThe2);
  Mutate(['INSERT INTO Part(UID, ClassID, Name, Description, RefPrefix, Status, Revision, Modified) VALUES (' + SqlQ(NewGuidText) + ', ' + IntToStr(AClassID) + ', ' +
    SqlQ(Trim(AName)) + ', ' + SqlQ(ADescription) + ', ' + SqlQ(Trim(ARefPrefix)) + ', ''active'', ''1'', datetime(''now''))']);
  Result := QueryInt('select PartID from Part where ClassID = ' + IntToStr(AClassID) + ' and Name = ' + SqlQ(Trim(AName)));
end;

{ ===========================================================================
  TPartsLibrary.UpdatePart  (procedure)
  Parameters:
    PartID: Int64 - the part
    const AName, ARefPrefix, ADescription, AStatus: String - the new values
  Notes:
    Changes the part's name, reference letters, description and status; Revision goes up by one (none counts as 1; a number is added to; any other text gets ".1" appended) and
    Modified is stamped, in one transaction. The class is not changed here. Raises EPartsError for an empty name, a bad status or a name the class has already.
  =========================================================================== }
procedure TPartsLibrary.UpdatePart(PartID: Int64; const AName, ARefPrefix, ADescription, AStatus: String);
var
  Idx: Integer;
  NewRev: String;
begin
  if Trim(AName) = '' then
    raise EPartsError.Create(rsThePartNeedsAName);
  if (AStatus <> 'active') and (AStatus <> 'obsolete') and (AStatus <> 'preview') and (AStatus <> 'custom') then
    raise EPartsError.Create(rsTheStatusMustBeActive);
  Idx := PartIndexOfID(PartID);
  if Idx < 0 then
    raise EPartsError.Create(rsThePartIsNotIn);
  NewRev := RevisionAfter(Idx);
  Mutate(['UPDATE Part SET Name = ' + SqlQ(Trim(AName)) + ', RefPrefix = ' + SqlQ(Trim(ARefPrefix)) + ', Description = ' + SqlQ(ADescription) + ', Status = ' + SqlQ(AStatus) +
    ', Revision = ' + SqlQ(NewRev) + ', Modified = datetime(''now'') WHERE PartID = ' + IntToStr(PartID)]);
end;

{ ===========================================================================
  TPartsLibrary.SuggestionCount  (function)
  Parameters:
    PartID: Int64 - the part
  Returns:
    Integer - how many products are listed as suitable for it
  Notes:
    PartProduct rows of the part.
  =========================================================================== }
function TPartsLibrary.SuggestionCount(PartID: Int64): Integer;
begin
  Result := QueryInt('select count(*) from PartProduct where PartID = ' + IntToStr(PartID));
end;

{ ===========================================================================
  TPartsLibrary.DeletePart  (procedure)
  Parameters:
    PartID: Int64 - the part
  Notes:
    Deletes the part with its values, child objects, requirements, links, symbols, icons, tags and suggestions, in one transaction. Rules of other parts that name it
    as their target, and the 2D outline and 3D model terminals of products that point at its child objects, are removed first (they would block the delete). Products
    stay. A design that has placed the part keeps its own copy. Raises EPartsError when the part is not in the library.
  =========================================================================== }
procedure TPartsLibrary.DeletePart(PartID: Int64);
var
  Id: String;
begin
  if PartIndexOfID(PartID) < 0 then
    raise EPartsError.Create(rsThePartIsNotIn);
  Id := IntToStr(PartID);
  Mutate(['DELETE FROM PartRule WHERE TargetPartID = ' + Id,
          'UPDATE Part SET BaseDefault = NULL WHERE PartID = ' + Id,
          'DELETE FROM OutlineTerminal WHERE ObjectID IN (SELECT ObjectID FROM PartObject WHERE PartID = ' + Id + ')',
          'DELETE FROM ModelTerminal WHERE ObjectID IN (SELECT ObjectID FROM PartObject WHERE PartID = ' + Id + ')',
          'DELETE FROM Link WHERE PartID = ' + Id,
          'DELETE FROM Part WHERE PartID = ' + Id]);
end;

{ ===========================================================================
  TPartsLibrary.DuplicatePart  (function)
  Parameters:
    PartID: Int64 - the part to copy
    const NewName: String - the copy's name (unique within the class)
  Returns:
    Int64 - the copy's PartID
  Notes:
    Copies the part and everything of it in one transaction: its row (new GUID, revision '1', Modified now, same class, reference letters, description and
    status), field values, child objects (the parent links and their values follow the copy), requirements (ratings of the part, on the copied objects), links,
    symbols with their pins (the default symbol is the copied one), icons, tags, rules and suggested products. Raises EPartsError for an empty or taken name.
  =========================================================================== }
function TPartsLibrary.DuplicatePart(PartID: Int64; const NewName: String): Int64;
  function IdList(const SQL: String): TInt64Array;
  var
    St: Psqlite3_stmt;
    n: Integer;
  begin
    SetLength(Result, 0);
    St := Prepare(SQL);
    try
      while sqlite3_step(St) = SQLITE_ROW do
      begin
        n := Length(Result);
        SetLength(Result, n + 1);
        Result[n] := sqlite3_column_int64(St, 0);
      end;
    finally
      sqlite3_finalize(St);
    end;
  end;
var
  Old, New: String;
  OldIds, NewIds, OldSyms, NewSyms: TInt64Array;
  i, n: Integer;
  Def: Int64;
begin
  if Trim(NewName) = '' then
    raise EPartsError.Create(rsThePartNeedsAName);
  if PartIndexOfID(PartID) < 0 then
    raise EPartsError.Create(rsThePartIsNotIn);
  Old := IntToStr(PartID);
  BeginTx;
  try
    Exec('INSERT INTO Part(UID, ClassID, Name, Description, RefPrefix, Status, Revision, Modified) SELECT ' + SqlQ(NewGuidText) + ', ClassID, ' + SqlQ(Trim(NewName)) +
      ', Description, RefPrefix, Status, ''1'', datetime(''now'') FROM Part WHERE PartID = ' + Old);
    Result := sqlite3_last_insert_rowid(FDb);
    New := IntToStr(Result);
    Exec('INSERT INTO PartValue(PartID, FieldID, ValueNum, ValueText) SELECT ' + New + ', FieldID, ValueNum, ValueText FROM PartValue WHERE PartID = ' + Old);
    { child objects: copied one by one so that the new numbers are known; the parent links are set once all exist }
    OldIds := IdList('select ObjectID from PartObject where PartID = ' + Old + ' order by ObjectID');
    SetLength(NewIds, Length(OldIds));
    for i := 0 to High(OldIds) do
    begin
      Exec('INSERT INTO PartObject(PartID, ParentObjectID, KindID, Name, Designator, Sort, Description) SELECT ' + New + ', NULL, KindID, Name, Designator, Sort, Description ' +
        'FROM PartObject WHERE ObjectID = ' + IntToStr(OldIds[i]));
      NewIds[i] := sqlite3_last_insert_rowid(FDb);
      Exec('INSERT INTO ObjectValue(ObjectID, FieldID, ValueNum, ValueText) SELECT ' + IntToStr(NewIds[i]) + ', FieldID, ValueNum, ValueText FROM ObjectValue WHERE ObjectID = ' +
        IntToStr(OldIds[i]));
    end;
    for i := 0 to High(OldIds) do
      for n := 0 to High(OldIds) do
        Exec('UPDATE PartObject SET ParentObjectID = ' + IntToStr(NewIds[n]) + ' WHERE ObjectID = ' + IntToStr(NewIds[i]) +
          ' AND (SELECT ParentObjectID FROM PartObject WHERE ObjectID = ' + IntToStr(OldIds[i]) + ') = ' + IntToStr(OldIds[n]));
    { requirements and links name child objects: the new numbers go with the old ones }
    for i := 0 to High(OldIds) do
      Exec('INSERT INTO Rating(PartID, ObjectID, Quantity, Min, Typ, Max, Unit, Condition) SELECT ' + New + ', ' + IntToStr(NewIds[i]) + ', Quantity, Min, Typ, Max, Unit, Condition ' +
        'FROM Rating WHERE PartID = ' + Old + ' AND ObjectID = ' + IntToStr(OldIds[i]));
    Exec('INSERT INTO Rating(PartID, ObjectID, Quantity, Min, Typ, Max, Unit, Condition) SELECT ' + New + ', NULL, Quantity, Min, Typ, Max, Unit, Condition FROM Rating ' +
      'WHERE PartID = ' + Old + ' AND ObjectID IS NULL');
    for i := 0 to High(OldIds) do
      for n := 0 to High(OldIds) do
        Exec('INSERT INTO Link(PartID, FromObject, ToObject, Relation) SELECT ' + New + ', ' + IntToStr(NewIds[i]) + ', ' + IntToStr(NewIds[n]) + ', Relation FROM Link WHERE PartID = ' +
          Old + ' AND FromObject = ' + IntToStr(OldIds[i]) + ' AND ToObject = ' + IntToStr(OldIds[n]));
    { symbols with their pins }
    Def := QueryInt('select coalesce(BaseDefault, 0) from Part where PartID = ' + Old);
    OldSyms := IdList('select SymbolID from Symbol where PartID = ' + Old + ' order by SymbolID');
    SetLength(NewSyms, Length(OldSyms));
    for i := 0 to High(OldSyms) do
    begin
      Exec('INSERT INTO Symbol(PartID, Standard, Purpose, PartNo, Name, Drawing, OriginX, OriginY) SELECT ' + New + ', Standard, Purpose, PartNo, Name, Drawing, OriginX, OriginY ' +
        'FROM Symbol WHERE SymbolID = ' + IntToStr(OldSyms[i]));
      NewSyms[i] := sqlite3_last_insert_rowid(FDb);
      if OldSyms[i] = Def then
        Exec('UPDATE Part SET BaseDefault = ' + IntToStr(NewSyms[i]) + ' WHERE PartID = ' + New);
      for n := 0 to High(OldIds) do
        Exec('INSERT INTO SymbolPin(SymbolID, ObjectID, X, Y, Direction) SELECT ' + IntToStr(NewSyms[i]) + ', ' + IntToStr(NewIds[n]) + ', X, Y, Direction FROM SymbolPin WHERE SymbolID = ' +
          IntToStr(OldSyms[i]) + ' AND ObjectID = ' + IntToStr(OldIds[n]));
    end;
    Exec('INSERT INTO PartGlyph(PartID, Size, Png) SELECT ' + New + ', Size, Png FROM PartGlyph WHERE PartID = ' + Old);
    Exec('INSERT INTO PartTag(PartID, Tag) SELECT ' + New + ', Tag FROM PartTag WHERE PartID = ' + Old);
    Exec('INSERT INTO PartRule(PartID, Kind, TargetClassID, TargetPartID, Note) SELECT ' + New + ', Kind, TargetClassID, TargetPartID, Note FROM PartRule WHERE PartID = ' + Old);
    Exec('INSERT INTO PartProduct(PartID, ProductID, Preferred, Note) SELECT ' + New + ', ProductID, Preferred, Note FROM PartProduct WHERE PartID = ' + Old);
    Touch;
    CommitTx;
  except
    on E: Exception do
    begin
      RollbackTx;
      if Pos('UNIQUE constraint failed: Part.ClassID, Part.Name', E.Message) > 0 then
        raise EPartsError.Create(rsTheClassAlreadyHasA);
      raise EPartsError.Create(E.Message);
    end;
  end;
  LoadAll;
end;

{ ===========================================================================
  TPartsLibrary.SetLibraryInfo  (procedure)
  Parameters:
    const AName, ADescription, AAuthor: String - the new values
  Notes:
    Changes the library's name, description and author (LibraryInfo) and stamps it modified. The name cannot be empty.
  =========================================================================== }
procedure TPartsLibrary.SetLibraryInfo(const AName, ADescription, AAuthor: String);
begin
  if Trim(AName) = '' then
    raise EPartsError.Create(rsTheLibraryNeedsAName);
  Mutate(['UPDATE LibraryInfo SET Name = ' + SqlQ(Trim(AName)) + ', Description = ' + SqlQ(ADescription) + ', Author = ' + SqlQ(AAuthor)]);
end;

{ ===========================================================================
  TPartsLibrary.ClassIndexOfID  (function)
  Parameters:
    ClassID: Int64 - a class's row number in the file
  Returns:
    Integer - the index in Classes, -1 when there is none
  Notes:
    Finds a class by its ClassID.
  =========================================================================== }
function TPartsLibrary.ClassIndexOfID(ClassID: Int64): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FClasses) do
    if FClasses[i].ID = ClassID then
      Exit(i);
end;

{ ===========================================================================
  TPartsLibrary.ClassPartCount  (function)
  Parameters:
    ClassID: Int64 - the class
  Returns:
    Integer - how many parts are of exactly this class
  Notes:
    Parts of the class itself (not of its subclasses).
  =========================================================================== }
function TPartsLibrary.ClassPartCount(ClassID: Int64): Integer;
begin
  Result := QueryInt('select count(*) from Part where ClassID = ' + IntToStr(ClassID));
end;

{ ===========================================================================
  TPartsLibrary.ClassProductCount  (function)
  Parameters:
    ClassID: Int64 - the class
  Returns:
    Integer - how many products are of exactly this class
  Notes:
    Products of the class itself (a product can be chosen for any part of its class).
  =========================================================================== }
function TPartsLibrary.ClassProductCount(ClassID: Int64): Integer;
begin
  Result := QueryInt('select count(*) from Product where ClassID = ' + IntToStr(ClassID));
end;

{ ===========================================================================
  TPartsLibrary.ClassFieldList  (function)
  Parameters:
    ClassID: Int64 - the class
  Returns:
    TFieldInfoArray - the fields of the class: those of its ancestors from the root down (FromParent = True), then its own
  Notes:
    The whole field set of a class (view ClassFields of the schema), each with the class that declares it.
  =========================================================================== }
function TPartsLibrary.ClassFieldList(ClassID: Int64): TFieldInfoArray;
var
  St: Psqlite3_stmt;
  N: Integer;
begin
  SetLength(Result, 0);
  St := Prepare('select f.FieldID, f.ClassID, c.Name, f.Name, f.Type, coalesce(f.Unit, ''''), coalesce(f.EnumValues, ''''), f.Required, coalesce(f.Description, '''') ' +
    'from ClassAncestors a join FieldDef f on f.ClassID = a.AncestorID join PartClass c on c.ClassID = f.ClassID where a.ClassID = ' + IntToStr(ClassID) +
    ' order by a.Depth desc, f.FieldID');
  try
    while sqlite3_step(St) = SQLITE_ROW do
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N].ID := sqlite3_column_int64(St, 0);
      Result[N].ClassID := sqlite3_column_int64(St, 1);
      Result[N].DeclaredBy := ColText(St, 2);
      Result[N].Name := ColText(St, 3);
      Result[N].FieldType := ColText(St, 4);
      Result[N].Unit_ := ColText(St, 5);
      Result[N].EnumValues := ColText(St, 6);
      Result[N].Required := sqlite3_column_int(St, 7) <> 0;
      Result[N].Description := ColText(St, 8);
      Result[N].FromParent := Result[N].ClassID <> ClassID;
    end;
  finally
    sqlite3_finalize(St);
  end;
end;

{ ===========================================================================
  TPartsLibrary.FieldValueCount  (function)
  Parameters:
    FieldID: Int64 - the field
  Returns:
    Integer - how many parts have a value for it
  Notes:
    PartValue rows of the field.
  =========================================================================== }
function TPartsLibrary.FieldValueCount(FieldID: Int64): Integer;
begin
  Result := QueryInt('select count(*) from PartValue where FieldID = ' + IntToStr(FieldID));
end;

{ ===========================================================================
  TPartsLibrary.BadInheritance  (function)
  Returns:
    Int64 - how many things in the file break the inheritance rules
  Notes:
    Counts (1) classes that get two fields of the same name from their own and their ancestors' declarations, (2) part values for fields the part's class does not
    have, (3) child objects of a kind the part's class does not allow. A class edit that raises the count is undone.
  =========================================================================== }
function TPartsLibrary.BadInheritance: Int64;
begin
  Result := QueryInt('select (select count(*) from ClassFields a join ClassFields b on a.ClassID = b.ClassID and a.Name = b.Name and a.FieldID < b.FieldID)' +
    ' + (select count(*) from PartValue v join Part p using(PartID) where not exists (select 1 from ClassFields cf where cf.ClassID = p.ClassID and cf.FieldID = v.FieldID))' +
    ' + (select count(*) from PartObject o join Part p using(PartID) where not exists (select 1 from ClassKinds ck where ck.ClassID = p.ClassID and ck.KindID = o.KindID))');
end;

{ ===========================================================================
  TPartsLibrary.ClassTransaction  (procedure)
  Parameters:
    const Steps: array of String - statements
  Notes:
    Like Mutate, and afterwards checks BadInheritance: when the statements made the file break the inheritance rules (a moved class leaves its parts with values or
    children the new ancestors do not give, or two fields of a class get the same name) everything is undone and EPartsError says so.
  =========================================================================== }
procedure TPartsLibrary.ClassTransaction(const Steps: array of String);
var
  Before: Int64;
  i: Integer;
  Msg: String;
begin
  if FDb = nil then
    raise EPartsError.Create(rsNoPartsLibraryIsOpen);
  Before := BadInheritance;
  BeginTx;
  try
    for i := Low(Steps) to High(Steps) do
      Exec(Steps[i]);
    if BadInheritance > Before then
      raise EPartsError.Create(rsThatChangeWouldLeaveFields);
    Touch;
    CommitTx;
  except
    on E: Exception do
    begin
      RollbackTx;
      Msg := E.Message;
      if Pos('UNIQUE constraint failed: PartClass.Name', Msg) > 0 then
        Msg := rsAClassWithThatName
      else if Pos('UNIQUE constraint failed: FieldDef.ClassID, FieldDef.Name', Msg) > 0 then
        Msg := rsTheClassHasAField
      else if Pos('readonly', Msg) > 0 then
        Msg := rsThePartsFileCannotBe;
      raise EPartsError.Create(Msg);
    end;
  end;
  LoadAll;
end;

{ ===========================================================================
  TPartsLibrary.AddClass  (function)
  Parameters:
    const AName: String - the class name (unique in the library)
    AParentID: Int64 - the parent class, 0 for a new root
    AAbstract: Boolean - an abstract class holds no parts, only gives its fields to its subclasses
    const ADescription: String - what the class is
  Returns:
    Int64 - the new class's ClassID
  Notes:
    Adds a class under its parent. Raises EPartsError for an empty or taken name or an unknown parent.
  =========================================================================== }
function TPartsLibrary.AddClass(const AName: String; AParentID: Int64; AAbstract: Boolean; const ADescription: String): Int64;
var
  Par: String;
begin
  if Trim(AName) = '' then
    raise EPartsError.Create(rsTheClassNeedsAName);
  if (AParentID <> 0) and (ClassIndexOfID(AParentID) < 0) then
    raise EPartsError.Create(rsTheParentClassIsNot);
  if AParentID = 0 then
    Par := 'NULL'
  else
    Par := IntToStr(AParentID);
  ClassTransaction(['INSERT INTO PartClass(ParentID, Name, Abstract, Description) VALUES (' + Par + ', ' + SqlQ(Trim(AName)) + ', ' + IntToStr(Ord(AAbstract)) + ', ' + SqlQ(ADescription) + ')']);
  Result := QueryInt('select ClassID from PartClass where Name = ' + SqlQ(Trim(AName)));
end;

{ ===========================================================================
  TPartsLibrary.UpdateClass  (procedure)
  Parameters:
    AClassID: Int64 - the class
    const AName: String - the new name
    AParentID: Int64 - the new parent, 0 for a root
    AAbstract: Boolean - whether it is abstract
    const ADescription: String - the description
  Notes:
    Changes name, parent (a move of the class with its subclasses), abstract flag and description. Refused: an empty or taken name, a parent that is the class itself or
    one of its subclasses, making a class abstract while it has parts or products, and a move that would leave parts with values or child objects their new ancestors
    do not give, or two fields of one class with the same name (undone, nothing changes).
  =========================================================================== }
procedure TPartsLibrary.UpdateClass(AClassID: Int64; const AName: String; AParentID: Int64; AAbstract: Boolean; const ADescription: String);
var
  Par, Id: String;
begin
  if ClassIndexOfID(AClassID) < 0 then
    raise EPartsError.Create(rsTheClassIsNotIn);
  if Trim(AName) = '' then
    raise EPartsError.Create(rsTheClassNeedsAName);
  Id := IntToStr(AClassID);
  if AParentID <> 0 then
  begin
    if ClassIndexOfID(AParentID) < 0 then
      raise EPartsError.Create(rsTheParentClassIsNot);
    if QueryInt('select count(*) from ClassAncestors where ClassID = ' + IntToStr(AParentID) + ' and AncestorID = ' + Id) > 0 then
      raise EPartsError.Create(rsAClassCannotBeMoved);
    Par := IntToStr(AParentID);
  end
  else
    Par := 'NULL';
  if AAbstract and ((ClassPartCount(AClassID) > 0) or (ClassProductCount(AClassID) > 0)) then
    raise EPartsError.Create(rsTheClassHasPartsOr);
  ClassTransaction(['UPDATE PartClass SET Name = ' + SqlQ(Trim(AName)) + ', ParentID = ' + Par + ', Abstract = ' + IntToStr(Ord(AAbstract)) + ', Description = ' + SqlQ(ADescription) +
    ' WHERE ClassID = ' + Id]);
end;

{ ===========================================================================
  TPartsLibrary.DeleteClass  (procedure)
  Parameters:
    AClassID: Int64 - the class
  Notes:
    Deletes a class with its own field declarations and the kinds it allows. Refused while it has subclasses, parts or products, or a part rule names it, or a product
    option changes one of its fields.
  =========================================================================== }
procedure TPartsLibrary.DeleteClass(AClassID: Int64);
var
  Id: String;
begin
  if ClassIndexOfID(AClassID) < 0 then
    raise EPartsError.Create(rsTheClassIsNotIn);
  Id := IntToStr(AClassID);
  if QueryInt('select count(*) from PartClass where ParentID = ' + Id) > 0 then
    raise EPartsError.Create(rsTheClassHasSubclassesDelete);
  if ClassPartCount(AClassID) > 0 then
    raise EPartsError.Create(rsTheClassHasPartsDelete);
  if ClassProductCount(AClassID) > 0 then
    raise EPartsError.Create(rsTheClassHasProducts);
  if QueryInt('select count(*) from PartRule where TargetClassID = ' + Id) > 0 then
    raise EPartsError.Create(rsAPartRuleRefersTo);
  if QueryInt('select count(*) from ProductOption where ChangesField in (select FieldID from FieldDef where ClassID = ' + Id + ')') > 0 then
    raise EPartsError.Create(rsAProductOptionChangesOne);
  ClassTransaction(['DELETE FROM FieldDef WHERE ClassID = ' + Id, 'DELETE FROM ClassAllowsKind WHERE ClassID = ' + Id, 'DELETE FROM PartClass WHERE ClassID = ' + Id]);
end;

{ ===========================================================================
  CheckFieldEntries  (procedure)
  Parameters:
    const AName, AType, AEnum: String - name, type and the values of an enum
  Notes:
    The rules of a field declaration: a name, a type of text, int, real, bool, enum or ref, and for an enum its comma separated values.
  =========================================================================== }
procedure CheckFieldEntries(const AName, AType, AEnum: String);
begin
  if Trim(AName) = '' then
    raise EPartsError.Create(rsTheFieldNeedsAName);
  if (AType <> 'text') and (AType <> 'int') and (AType <> 'real') and (AType <> 'bool') and (AType <> 'enum') and (AType <> 'ref') then
    raise EPartsError.Create(rsTheTypeMustBeText);
  if (AType = 'enum') and (Trim(AEnum) = '') then
    raise EPartsError.Create(rsAnEnumFieldNeedsIts);
end;

{ ===========================================================================
  TPartsLibrary.FieldNameTaken  (function)
  Parameters:
    AClassID: Int64 - the class that declares (or declares already) the field
    const AName: String - the field name
    AExceptField: Int64 - a field to leave out (the one being changed), 0 for none
  Returns:
    Boolean - True when a field of that name exists in the class, its ancestors or its subclasses
  Notes:
    A field name must be unique along the whole line of a class (parents above, subclasses below), or a class would inherit two fields of one name.
  =========================================================================== }
function TPartsLibrary.FieldNameTaken(AClassID: Int64; const AName: String; AExceptField: Int64): Boolean;
begin
  Result := QueryInt('select count(*) from FieldDef f where lower(f.Name) = lower(' + SqlQ(Trim(AName)) + ') and f.FieldID <> ' + IntToStr(AExceptField) +
    ' and (f.ClassID in (select AncestorID from ClassAncestors where ClassID = ' + IntToStr(AClassID) + ')' +
    ' or f.ClassID in (select ClassID from ClassAncestors where AncestorID = ' + IntToStr(AClassID) + '))') > 0;
end;

{ ===========================================================================
  TPartsLibrary.AddField  (function)
  Parameters:
    AClassID: Int64 - the class that declares the field
    const AName, AType, AUnit, AEnum: String - name, type (text, int, real, bool, enum, ref), unit, enum values
    ARequired: Boolean - whether parts must have a value
    const ADescription: String - what the field is
  Returns:
    Int64 - the new field's FieldID
  Notes:
    Declares a field on a class; its subclasses inherit it. Refused: no name, a bad type, an enum without values, a name already used along the class's line.
  =========================================================================== }
function TPartsLibrary.AddField(AClassID: Int64; const AName, AType, AUnit, AEnum: String; ARequired: Boolean; const ADescription: String): Int64;
begin
  if ClassIndexOfID(AClassID) < 0 then
    raise EPartsError.Create(rsTheClassIsNotIn);
  CheckFieldEntries(AName, AType, AEnum);
  if FieldNameTaken(AClassID, AName, 0) then
    raise EPartsError.Create(rsAFieldOfThatName);
  ClassTransaction(['INSERT INTO FieldDef(ClassID, Name, Type, Unit, EnumValues, Required, Description) VALUES (' + IntToStr(AClassID) + ', ' + SqlQ(Trim(AName)) + ', ' + SqlQ(AType) + ', ' +
    SqlQ(AUnit) + ', ' + SqlQ(AEnum) + ', ' + IntToStr(Ord(ARequired)) + ', ' + SqlQ(ADescription) + ')']);
  Result := QueryInt('select FieldID from FieldDef where ClassID = ' + IntToStr(AClassID) + ' and Name = ' + SqlQ(Trim(AName)));
end;

{ ===========================================================================
  TPartsLibrary.UpdateField  (procedure)
  Parameters:
    AFieldID: Int64 - the field
    const AName, AType, AUnit, AEnum: String - the new entries
    ARequired: Boolean - whether parts must have a value
    const ADescription: String - the description
  Notes:
    Changes a field of a class. The type cannot change while parts have values for the field.
  =========================================================================== }
procedure TPartsLibrary.UpdateField(AFieldID: Int64; const AName, AType, AUnit, AEnum: String; ARequired: Boolean; const ADescription: String);
var
  Cls: Int64;
  OldType: String;
  St: Psqlite3_stmt;
begin
  Cls := 0;
  OldType := '';
  St := Prepare('select ClassID, Type from FieldDef where FieldID = ' + IntToStr(AFieldID));
  try
    if sqlite3_step(St) = SQLITE_ROW then
    begin
      Cls := sqlite3_column_int64(St, 0);
      OldType := ColText(St, 1);
    end;
  finally
    sqlite3_finalize(St);
  end;
  if Cls = 0 then
    raise EPartsError.Create(rsTheFieldIsNotIn);
  CheckFieldEntries(AName, AType, AEnum);
  if FieldNameTaken(Cls, AName, AFieldID) then
    raise EPartsError.Create(rsAFieldOfThatName);
  if (AType <> OldType) and (FieldValueCount(AFieldID) > 0) then
    raise EPartsError.Create(rsPartsHaveValuesForThis);
  ClassTransaction(['UPDATE FieldDef SET Name = ' + SqlQ(Trim(AName)) + ', Type = ' + SqlQ(AType) + ', Unit = ' + SqlQ(AUnit) + ', EnumValues = ' + SqlQ(AEnum) + ', Required = ' +
    IntToStr(Ord(ARequired)) + ', Description = ' + SqlQ(ADescription) + ' WHERE FieldID = ' + IntToStr(AFieldID)]);
end;

{ ===========================================================================
  TPartsLibrary.DeleteField  (procedure)
  Parameters:
    AFieldID: Int64 - the field
  Notes:
    Deletes a field declaration. Refused while parts have values for it or a product option changes it.
  =========================================================================== }
procedure TPartsLibrary.DeleteField(AFieldID: Int64);
var
  Id: String;
begin
  Id := IntToStr(AFieldID);
  if QueryInt('select count(*) from FieldDef where FieldID = ' + Id) = 0 then
    raise EPartsError.Create(rsTheFieldIsNotIn);
  if FieldValueCount(AFieldID) > 0 then
    raise EPartsError.Create(Format(rsPartSHaveAValue, [FieldValueCount(AFieldID)]));
  if QueryInt('select count(*) from ProductOption where ChangesField = ' + Id) > 0 then
    raise EPartsError.Create(rsAProductOptionChangesThis);
  ClassTransaction(['DELETE FROM FieldDef WHERE FieldID = ' + Id]);
end;

{ ===========================================================================
  CreatePartsFile  (procedure)
  Parameters:
    const Path: String - the new file (must not exist)
    const LibName: String - the library's name (LibraryInfo.Name)
    const Description: String - its description (may be empty)
    const Author: String - who made it (may be empty)
  Notes:
    Makes a new TyCAD parts file in one transaction: the tables, views and triggers of UPartsSchema, the starting taxonomy (classes with their fields, child
    kinds, which kinds a class allows, rating quantities), FormatInfo (current schema version, Generator 'TyCAD'), and LibraryInfo with a fresh GUID. It holds no
    parts and no products. If anything fails the half-made file is deleted and EPartsError says why. An existing file is never overwritten (the caller asks the
    person and deletes it first).
  =========================================================================== }
procedure CreatePartsFile(const Path, LibName, Description, Author: String);
var
  Db: Psqlite3;
  i: Integer;
  G: TGuid;
  function Q(const S: String): String;
  begin
    Result := '''' + StringReplace(S, '''', '''''', [rfReplaceAll]) + '''';
  end;
begin
  EnsureSqlite;
  if FileExists(Path) then
    raise EPartsError.Create(Format(rsTheFileAlreadyExists, [Path]));
  Db := nil;
  if sqlite3_open_v2(PChar(Path), @Db, SQLITE_OPEN_READWRITE or SQLITE_OPEN_CREATE, nil) <> SQLITE_OK then
  begin
    sqlite3_close(Db);
    raise EPartsError.Create(Format(rsCannotCreateThePartsFile, [Path]));
  end;
  try
    try
      DbExec(Db, 'PRAGMA foreign_keys=ON');
      DbExec(Db, 'BEGIN');
      for i := Low(PARTS_SCHEMA_SQL) to High(PARTS_SCHEMA_SQL) do
        DbExec(Db, PARTS_SCHEMA_SQL[i]);
      for i := Low(PARTS_STARTER_SQL) to High(PARTS_STARTER_SQL) do
        DbExec(Db, PARTS_STARTER_SQL[i]);
      CreateGUID(G);
      DbExec(Db, 'INSERT INTO FormatInfo(Format, SchemaVersion, TinyCADCompatible, Created, Generator) VALUES (''TyCAD-Parts'', ' + IntToStr(PARTS_SCHEMA_CURRENT) +
        ', 0, datetime(''now''), ''TyCAD'')');
      DbExec(Db, 'INSERT INTO LibraryInfo(LibraryUID, Name, Description, Author, Created, Modified) VALUES (' + Q(LowerCase(Copy(GUIDToString(G), 2, 36))) + ', ' +
        Q(LibName) + ', ' + Q(Description) + ', ' + Q(Author) + ', datetime(''now''), datetime(''now''))');
      DbExec(Db, 'COMMIT');
    except
      on E: Exception do
      begin
        sqlite3_close(Db);
        Db := nil;
        DeleteFile(Path);
        if E is EPartsError then
          raise
        else
          raise EPartsError.Create(E.Message);
      end;
    end;
  finally
    if Db <> nil then
      sqlite3_close(Db);
  end;
end;

end.
