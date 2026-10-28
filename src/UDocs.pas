{ The list of open documents. Each document keeps together everything that belongs to it: its design,
  the file it was loaded from or saved to, whether it has unsaved changes, and its own drawing view
  (the view carries the document's undo history, zoom, scroll position and selection, so switching
  between documents loses none of them).

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UDocs;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, UDesign, UView, USymEdit, QPartsEditor;

type
  TDocument = class
  public
    Design: TDesignFile;     // owned
    View: TSchematicView;    // this document's drawing area; owned (freed with the document)
    FileName: String;        // '' while the document has never been saved
    Modified: Boolean;
    UntitledNumber: Integer; // 1, 2, 3 ... for documents without a file name
    Symbol: TSymbolEditor;   // not nil for a library symbol being edited (then Design is in symbol mode and FileName is empty); owned
    SymbolLibFile: String;   // ... the .TCLib file it is stored in
    OnePxGrid: Boolean;      // the grid dots of the symbol being edited are drawn one pixel wide (the Alignment panel's check box)
    ConvertedFrom: String;   // the old binary design this one was read from (then FileName is empty until it is saved under a new name)
    PartsEditor: TfrPartsEditor;   // not nil for a parts library being edited (then Design is nil, FileName is empty and the view is an unused hidden one); owned
    PartsFile: String;       // ... the parts file it edits
    destructor Destroy; override;
    function DisplayName: String;
    function TabCaption: String;
  end;

  TDocumentList = class
  private
    FItems: TObjectList;
    FUntitledCount: Integer;
    function GetItem(Index: Integer): TDocument;
  public
    constructor Create;
    destructor Destroy; override;
    function Count: Integer;
    function Add(ADesign: TDesignFile; const AFileName: String): TDocument;
    function AddParts(const APartsFile: String): TDocument;
    function IndexOfParts(const APartsFile: String): Integer;
    procedure Delete(Index: Integer);
    function IndexOf(Doc: TDocument): Integer;
    function IndexOfFile(const AFileName: String): Integer;
    function IndexOfView(AView: TObject): Integer;
    property Items[Index: Integer]: TDocument read GetItem; default;
  end;

implementation


uses UStrings;

{ ===========================================================================
  TDocument.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the document: its view lets go of the design first, then the view and the design are
    freed.
  =========================================================================== }
destructor TDocument.Destroy;
begin
  if View <> nil then
  begin
    View.SetDesign(nil, 0);    // let go of the design before it is freed
    View.Free;
  end;
  PartsEditor.Free;
  Design.Free;
  Symbol.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TDocument.DisplayName  (function)
  Parameters:  none
  Returns:
    String - the name
  Notes:
    The name shown for the document: the file name without its folder, or "Untitled N" while it
    has never been saved; a symbol being edited shows its first name with "(symbol)", or "New
    symbol" before it has one.
  =========================================================================== }
function TDocument.DisplayName: String;
begin
  if PartsEditor <> nil then
  begin
    if (PartsEditor.Lib <> nil) and (PartsEditor.Lib.LibraryName <> '') then
      Result := Format(rsParts, [PartsEditor.Lib.LibraryName])
    else
      Result := Format(rsParts, [ChangeFileExt(ExtractFileName(PartsFile), '')]);
  end
  else if Symbol <> nil then
  begin
    { a symbol is named by its first name; a new one has none until it is stored }
    if (Symbol.LibrarySet.RecordCount > 0) and (Symbol.LibrarySet.Records[0].Name <> '') then
      Result := Format(rsSymbol3, [Symbol.LibrarySet.Records[0].Name])
    else
      Result := rsNewSymbol;
  end
  else if FileName <> '' then
    Result := ExtractFileName(FileName)
  else if ConvertedFrom <> '' then
    Result := Format(rsConverted, [ExtractFileName(ConvertedFrom)])
  else
    Result := Format(rsUntitled2, [UntitledNumber]);
end;

{ ===========================================================================
  TDocument.TabCaption  (function)
  Parameters:  none
  Returns:
    String - the caption
  Notes:
    The caption of the document's tab and Window menu entry: its name, followed by " *" when it
    has unsaved changes.
  =========================================================================== }
function TDocument.TabCaption: String;
begin
  Result := DisplayName;
  if Modified then
    Result := Result + ' *';
end;

{ ===========================================================================
  TDocumentList.Create  (constructor)
  Parameters:  none
  Notes:
    Creates an empty list of documents.
  =========================================================================== }
constructor TDocumentList.Create;
begin
  inherited Create;
  FItems := TObjectList.Create(True);
end;

{ ===========================================================================
  TDocumentList.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the list and every document in it.
  =========================================================================== }
destructor TDocumentList.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TDocumentList.GetItem  (function)
  Parameters:
    Index: Integer - position, 0-based
  Returns:
    TDocument - the document
  Notes:
    One document of the list.
  =========================================================================== }
function TDocumentList.GetItem(Index: Integer): TDocument;
begin
  Result := TDocument(FItems[Index]);
end;

{ ===========================================================================
  TDocumentList.Count  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    How many documents are open.
  =========================================================================== }
function TDocumentList.Count: Integer;
begin
  Result := FItems.Count;
end;

{ ===========================================================================
  TDocumentList.Add  (function)
  Parameters:
    ADesign: TDesignFile - the design; the document owns it
    const AFileName: String - the file it came from, or empty
  Returns:
    TDocument - the new document (its view is made by the caller)
  Notes:
    Adds a document for a design. A document without a file name gets the next "Untitled"
    number; the numbers are never reused, so closing Untitled 1 and opening a new one gives
    Untitled 2.
  =========================================================================== }
function TDocumentList.Add(ADesign: TDesignFile; const AFileName: String): TDocument;
begin
  Result := TDocument.Create;
  Result.Design := ADesign;
  Result.FileName := AFileName;
  if AFileName = '' then
  begin
    Inc(FUntitledCount);
    Result.UntitledNumber := FUntitledCount;
  end;
  FItems.Add(Result);
end;

{ ===========================================================================
  TDocumentList.AddParts  (function)
  Parameters:
    const APartsFile: String - the parts file being edited
  Returns:
    TDocument - the new document (its editor and view are made by the caller)
  Notes:
    Adds a document for a parts library editor: no design, no file name of its own (it is not a design file, so it is not saved with the others or reopened with
    the session), and no Untitled number.
  =========================================================================== }
function TDocumentList.AddParts(const APartsFile: String): TDocument;
begin
  Result := TDocument.Create;
  Result.PartsFile := APartsFile;
  FItems.Add(Result);
end;

{ ===========================================================================
  TDocumentList.IndexOfParts  (function)
  Parameters:
    const APartsFile: String - a parts file
  Returns:
    Integer - the position of the editor of that file, -1 when it is not being edited
  Notes:
    Finds the open parts editor of a file (file names compared as the system does).
  =========================================================================== }
function TDocumentList.IndexOfParts(const APartsFile: String): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to FItems.Count - 1 do
    if (TDocument(FItems[i]).PartsEditor <> nil) and SameFileName(TDocument(FItems[i]).PartsFile, APartsFile) then
      Exit(i);
end;

{ ===========================================================================
  TDocumentList.Delete  (procedure)
  Parameters:
    Index: Integer - position, 0-based
  Notes:
    Removes a document and frees it, with its view and design.
  =========================================================================== }
procedure TDocumentList.Delete(Index: Integer);
begin
  FItems.Delete(Index);      // frees the document, its view and its design
end;

{ ===========================================================================
  TDocumentList.IndexOf  (function)
  Parameters:
    Doc: TDocument - the document
  Returns:
    Integer - its position, or -1
  Notes:
    Where a document is in the list.
  =========================================================================== }
function TDocumentList.IndexOf(Doc: TDocument): Integer;
begin
  Result := FItems.IndexOf(Doc);
end;

{ ===========================================================================
  TDocumentList.IndexOfFile  (function)
  Parameters:
    const AFileName: String - the file name
  Returns:
    Integer - its position, or -1 if that file is not open
  Notes:
    Finds the open document that was loaded from or saved to a file (file names compared as the
    operating system compares them).
  =========================================================================== }
function TDocumentList.IndexOfFile(const AFileName: String): Integer;
var
  i: Integer;
begin
  Result := -1;
  if AFileName = '' then
    Exit;
  for i := 0 to FItems.Count - 1 do
    if ((Items[i].FileName <> '') and SameFileName(Items[i].FileName, AFileName)) or
       ((Items[i].ConvertedFrom <> '') and SameFileName(Items[i].ConvertedFrom, AFileName)) then
    begin
      Result := i;
      Exit;
    end;
end;

{ ===========================================================================
  TDocumentList.IndexOfView  (function)
  Parameters:
    AView: TObject - the view
  Returns:
    Integer - its position, or -1
  Notes:
    Finds the document that owns a view, used to work out which document an event came from.
  =========================================================================== }
function TDocumentList.IndexOfView(AView: TObject): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to FItems.Count - 1 do
    if Items[i].View = AView then
    begin
      Result := i;
      Exit;
    end;
end;

end.
