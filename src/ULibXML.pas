{ Library export and import as an XML file: port of CLibraryStore::SaveXML / LoadXML (LibraryStore.cpp) with CLibraryStoreNameSet::SaveXML / LoadXML and
  CSymbolRecord::SaveXML / LoadXML (Symbol.cpp), the menu commands File > Export all symbols... / Import symbols... of TinyCAD's library window and its
  context-menu command Export symbol.

  The file is the same as TinyCAD writes, so each program can read the other's files:
    <Library>
      <SYMBOL>
        <PPP>, <ORIENTATION>, then for each name <DETAILS> with <NAME type=n>, <REF type=n>, <DESCRIPTION> and <FIELD> (NAME, DEFAULT, FT)
        then the drawing: <TinyCAD> (one drawing for all the parts) or <TinyCADSheets> (one for each part)
      </SYMBOL> ...
    </Library>

  Differences from TinyCAD: a problem is raised as ELibraryError with its message (TinyCAD shows its "This file was not created by TinyCAD." message and silently
  does nothing when a file cannot be opened); importing adds the symbols, as TinyCAD does, so importing a file twice stores its symbols twice.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit ULibXML;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, UDPoint, UDrawTypes, USymbols, UDesign, UXMLWriter, UXMLReader, ULibrary;

{ writes a library, or only the set with the SymbolID ASymbolID (-1: all), to an XML file; returns how many symbols (sets) were written }
function ExportLibraryXML(ALib: TSymbolLibrary; const AFileName: String; ASymbolID: Int64 = -1): Integer;
{ stores the symbols of an XML file in a library; returns how many were stored. Raises ELibraryError when the file is not a library file }
function ImportLibraryXML(ALib: TSymbolLibrary; const AFileName: String): Integer;
{ the file name the export dialog starts with: the library's name (or the symbol's) with .xml }
function ExportFileName(const AName: String): String;

const
  MSG_NOT_TINYCAD = 'This file was not created by TinyCAD.';

implementation


uses UStrings;

{ ===========================================================================
  ExportFileName  (function)
  Parameters:
    const AName: String - the name
  Returns:
    String
  Notes:
    TODO: describe.
  =========================================================================== }
function ExportFileName(const AName: String): String;
begin
  Result := AName + '.xml';
end;

{ ===========================================================================
  WriteSet  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
    ALib: TSymbolLibrary
    ASet: TLibrarySymbolSet
  Notes:
    CLibraryStore::SaveXML for one symbol: SYMBOL with CLibraryStoreNameSet::SaveXML (PPP,
    ORIENTATION, a DETAILS of each name with its fields written in the short form) and then the
    drawing as CTinyCadMultiSymbolDoc::SaveXML writes it (only the resources it uses).
  =========================================================================== }
procedure WriteSet(W: TXMLWriter; ALib: TSymbolLibrary; ASet: TLibrarySymbolSet);
var
  i, j: Integer;
  Rec: TLibraryRecord;
  Doc: TSymbolDocument;
begin
  W.AddTag('SYMBOL');
  W.AddTag('PPP', ASet.Ppp);
  W.AddTag('ORIENTATION', ASet.Orientation);
  for i := 0 to ASet.RecordCount - 1 do
  begin
    Rec := ASet.Records[i];
    ALib.LoadFields(Rec);
    W.AddTag('DETAILS');
    W.AddTag('NAME');
    W.AddAttribute('type', Rec.NameType);
    W.AddChildData(Rec.Name);
    W.CloseTag;
    W.AddTag('REF');
    W.AddAttribute('type', Rec.RefType);
    W.AddChildData(Rec.Reference);
    W.CloseTag;
    W.AddTag('DESCRIPTION', Rec.Description);
    for j := 0 to High(Rec.Fields) do
      SaveFieldXML(W, Rec.Fields[j], True);
    W.CloseTag;
  end;
  Doc := TSymbolDocument.Create;
  try
    Doc.LoadFromBlob(ALib.GetSymbolBlob(ASet));
    Doc.SaveXML(W);
  finally
    Doc.Free;
  end;
  W.CloseTag;
end;

{ ===========================================================================
  ExportLibraryXML  (function)
  Parameters:
    ALib: TSymbolLibrary
    const AFileName: String - path of the file
    ASymbolID: Int64
  Returns:
    Integer
  Notes:
    CLibraryStore::SaveXML. The file is written whole or not at all: it is made under a
    temporary name and renamed when it is complete, so a library that cannot be read to the end
    does not leave half a file in place of a good one.
  =========================================================================== }
function ExportLibraryXML(ALib: TSymbolLibrary; const AFileName: String; ASymbolID: Int64): Integer;
var
  FS: TFileStream;
  W: TXMLWriter;
  i: Integer;
  Tmp: String;
begin
  Result := 0;
  Tmp := AFileName + '.tmp';
  FS := TFileStream.Create(Tmp, fmCreate);
  try
    try
      W := TXMLWriter.Create(FS);
      try
        W.AddComment('This file was written by TyCAD Electrical' + #10 +
          'It is the XML library format of TinyCAD (https://www.tinycad.net), which can read it too.');
        W.AddTag('Library');
        for i := 0 to ALib.SetCount - 1 do
          if (ASymbolID = -1) or (ALib.Sets[i].SymbolID = ASymbolID) then
          begin
            WriteSet(W, ALib, ALib.Sets[i]);
            Inc(Result);
          end;
        W.CloseTag;
      finally
        W.Free;
      end;
    finally
      FS.Free;
    end;
  except
    DeleteFile(Tmp);
    raise;
  end;
  if FileExists(AFileName) and not DeleteFile(AFileName) then
  begin
    DeleteFile(Tmp);
    raise ELibraryError.Create(Format(rsCannotReplace, [AFileName]));
  end;
  if not RenameFile(Tmp, AFileName) then
    raise ELibraryError.Create(Format(rsCannotWrite, [AFileName]));
end;

{ ===========================================================================
  ReadRecord  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
    Rec: TLibraryRecord
  Notes:
    CSymbolRecord::LoadXML.
  =========================================================================== }
procedure ReadRecord(R: TXMLReader; Rec: TLibraryRecord);
var
  Tag: String;
  T: Integer;
  F: TSymbolFieldDef;
begin
  while R.NextTag(Tag) do
  begin
    if Tag = 'NAME' then
    begin
      T := Rec.NameType;
      R.GetAttribute('type', T);
      Rec.NameType := T;
      R.GetChildData(Rec.Name);
    end
    else if Tag = 'REF' then
    begin
      T := Rec.RefType;
      R.GetAttribute('type', T);
      Rec.RefType := T;
      R.GetChildData(Rec.Reference);
    end
    else if Tag = 'DESCRIPTION' then
      R.GetChildData(Rec.Description)
    else if Tag = 'FIELD' then
    begin
      F.Name := ''; F.Value := ''; F.Default := ''; F.Pos := DPoint(0, 0); F.FieldType := 0;
      R.IntoTag;
      LoadFieldXML(R, F);
      R.OutOfTag;
      SetLength(Rec.Fields, Length(Rec.Fields) + 1);
      Rec.Fields[High(Rec.Fields)] := F;
    end;
  end;
  Rec.FieldsLoaded := True;
end;

{ ===========================================================================
  ImportLibraryXML  (function)
  Parameters:
    ALib: TSymbolLibrary
    const AFileName: String - path of the file
  Returns:
    Integer
  Notes:
    CLibraryStore::LoadXML: each SYMBOL is read (its names, then the drawing) and stored. A file
    that does not start with a Library tag raises ELibraryError with TinyCAD's message; a file
    that is not XML raises the parser's message the same way. Symbols stored before a problem
    stay stored.
  =========================================================================== }
function ImportLibraryXML(ALib: TSymbolLibrary; const AFileName: String): Integer;
var
  FS: TFileStream;
  R: TXMLReader;
  Tag, T2: String;
  ASet: TLibrarySymbolSet;
  Doc: TSymbolDocument;
  Rec: TLibraryRecord;
  Seen: Boolean;
begin
  Result := 0;
  try
    FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  except
    on E: Exception do
      raise ELibraryError.Create(Format(rsCannotOpen, [AFileName]));
  end;
  try
    try
      R := TXMLReader.Create(FS);
    except
      on E: Exception do
        raise ELibraryError.Create(MSG_NOT_TINYCAD + ' (' + E.Message + ')');
    end;
    try
      if (not R.NextTag(Tag)) or (Tag <> 'Library') then
        raise ELibraryError.Create(MSG_NOT_TINYCAD);
      R.IntoTag;
      while R.NextTag(Tag) do
        if Tag = 'SYMBOL' then
        begin
          R.IntoTag;
          ASet := TLibrarySymbolSet.Create;
          Doc := TSymbolDocument.Create;
          try
            Seen := False;
            while R.NextTag(T2) do
            begin
              if T2 = 'PPP' then
                R.GetChildData(ASet.Ppp)
              else if T2 = 'ORIENTATION' then
                R.GetChildData(ASet.Orientation)
              else if T2 = 'DETAILS' then
              begin
                Rec := ASet.AddRecord;
                R.IntoTag;
                ReadRecord(R, Rec);
                R.OutOfTag;
              end
              else if T2 = 'TinyCAD' then
              begin
                Doc.LoadXML(R, False);
                Seen := True;
              end
              else if T2 = 'TinyCADSheets' then
              begin
                Doc.LoadXML(R, True);
                Seen := True;
              end;
            end;
            R.OutOfTag;
            if Seen and (ASet.RecordCount > 0) then
            begin
              ALib.StoreSet(ASet, Doc);
              Inc(Result);
            end;
          finally
            Doc.Free;
            ASet.Free;
          end;
        end;
      R.OutOfTag;
    finally
      R.Free;
    end;
  finally
    FS.Free;
  end;
end;

end.
